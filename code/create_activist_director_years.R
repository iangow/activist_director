library(dplyr, warn.conflicts = FALSE)
library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

dbGetQuery(pg, "SET work_mem='8GB'")

dbGetQuery(pg, "SET search_path TO activist_director")

activist_directors <- tbl(pg, "activist_directors")
outcome_controls <- tbl(pg, "outcome_controls")

comp.funda <- tbl(pg, sql("SELECT * FROM comp.funda"))
crsp.ccmxpf_linktable <- tbl(pg, sql("SELECT * FROM crsp.ccmxpf_linktable"))

# Compustat with PERMNO
firm_years <-
    comp.funda %>%
    filter(indfmt=='INDL', consol=='C', popsrc=='D', datafmt=='STD') %>%
    filter(fyear > 2000) %>%
    inner_join(crsp.ccmxpf_linktable) %>%
    filter(usedflag=='1',
           linkprim %in% c('C', 'P')) %>%
    filter(datadate >= linkdt,
           datadate <= linkenddt | is.na(linkenddt)) %>%
    rename(permno = lpermno) %>%
    select(gvkey, datadate, permno) %>%
    compute()

activist_director <-
    activist_directors %>%
    group_by(campaign_id, permno) %>%
    summarize(appointment_date = min(appointment_date, na.rm = TRUE),
              retirement_date = max(coalesce(retirement_date, '2017-12-31'), na.rm = TRUE)) %>%
    ungroup() %>%
    compute()

matched <-
    outcome_controls %>%
    inner_join(activist_director, by="permno") %>%
    filter(between(datadate, appointment_date, retirement_date)) %>%
    mutate(on_board = !is.na(permno)) %>%
    distinct(permno, datadate, on_board)

activist_director_on_board <-
    outcome_controls %>%
    left_join(matched, by = c("permno", "datadate")) %>%
    mutate(on_board = coalesce(on_board, FALSE)) %>%
    distinct(permno, datadate, on_board)

rs <- dbExecute(pg, "DROP TABLE IF EXISTS activist_director_years")

activist_director_years <-
    activist_director_on_board %>%
    group_by(permno, datadate) %>%
    summarize(ad_on_board = bool_or(on_board)) %>%
    arrange(permno, datadate) %>%
    compute(name = "activist_director_years", temporary=FALSE)

rs <- dbExecute(pg, "COMMENT ON TABLE activist_director_years IS
                'CREATED USING create_activist_director_years.R'")

rs <- dbExecute(pg, "ALTER TABLE activist_director_years OWNER TO activism")

sql <- paste0("
    COMMENT ON TABLE activist_director_years IS
        'CREATED USING create_activist_director_years.R ON ",
              format(Sys.time(), "%Y-%m-%d %X %Z"), "';")

rs <- dbGetQuery(pg, sql)

dbDisconnect(pg)
