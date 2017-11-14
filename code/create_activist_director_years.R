library(dplyr, warn.conflicts = FALSE)
library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

dbGetQuery(pg, "SET work_mem='8GB'")

dbGetQuery(pg, "SET search_path='activist_director'")
dbGetQuery(pg, "DROP TABLE IF EXISTS activist_director_years_new")

comp.funda <- tbl(pg, sql("SELECT * FROM comp.funda"))
crsp.ccmxpf_linktable <- tbl(pg, sql("SELECT * FROM crsp.ccmxpf_linktable"))
activist_directors <- tbl(pg, sql("SELECT * FROM activist_directors"))
outcome_controls <- tbl(pg, sql("SELECT * FROM outcome_controls"))
# DROP TABLE IF EXISTS activist_director.activist_director_years;

# CREATE TABLE activist_director.activist_director_years AS

# Compustat with PERMNO
firm_years <-
    comp.funda %>%
    filter(fyear > 2000) %>%
    inner_join(crsp.ccmxpf_linktable) %>%
    filter(usedflag=='1',
           linkprim %in% c('C', 'P')) %>%
    rename(permno = lpermno) %>%
    select(gvkey, datadate, permno) %>%
    distinct() %>%
    arrange(gvkey, datadate)

#COMMENT ON TABLE activist_director.activist_director_years IS
#'CREATED USING create_activist_director_years.sql';

# ALTER TABLE activist_director.activist_director_years OWNER TO activism;
activist_director <-
    activist_directors %>%
    group_by(campaign_id, permno) %>%
    summarize(appointment_date = min(appointment_date),
              retirement_date = max(coalesce(retirement_date, '2016-12-31'))) %>%
    arrange(permno, appointment_date)

activist_director_on_board <-
    outcome_controls %>%
    left_join(activist_director, by="permno") %>%
    filter(between(datadate, appointment_date, retirement_date)) %>%
    mutate(on_board = !is.na(permno)) %>%
    select(permno, datadate, on_board)

dbGetQuery(pg, "DROP TABLE IF EXISTS activist_director_years")

activist_director_years <-
    activist_director_on_board %>%
    group_by(permno, datadate) %>%
    summarize(ad_on_board = bool_or(on_board)) %>%
    arrange(permno, datadate) %>%
    compute(name = "activist_director_years", temporary=FALSE)

