library(RPostgreSQL)
library(dplyr, warn.conflicts = FALSE)

pg <- dbConnect(PostgreSQL())

rs <- dbGetQuery(pg, "SET work_mem='8GB'")
rs <- dbGetQuery(pg, "SET search_path TO activist_director, equilar_hbs")

stocknames <- tbl(pg, sql("SELECT * FROM crsp.stocknames"))

company_financials <- tbl(pg, "company_financials")
director_index <- tbl(pg, "director_index")
activism_events <- tbl(pg, "activism_events")
activist_directors <- tbl(pg, "activist_directors")

# Create Equilar link table ----
permcos <-
    stocknames %>%
    select(permno, permco) %>%
    distinct() %>%
    arrange(permno, permco) %>%
    compute()

permnos <-
    stocknames %>%
    select(permno, permco, ncusip) %>%
    # rename(cusip = ncusip) %>%
    distinct() %>%
    arrange(permno, permco) %>%
    compute()

fy_ends <-
    company_financials %>%
    select(company_id, fye) %>%
    rename(period = fye) %>%
    group_by(company_id) %>%
    arrange(period) %>%
    mutate(lead_period = coalesce(lead(period), period + sql("interval '1 year'"))) %>%
    mutate(lead_period = sql("lead_period::date")) %>%
    compute()

equilar_final <-
    company_financials %>%
    rename(period = fye) %>%
    mutate(ncusip = substr(cusip, 1L, 8L)) %>%
    select(company_id, period, ncusip) %>%
    group_by(company_id) %>%
    arrange(period) %>%
    mutate(lead_period = coalesce(lead(period), period + sql("interval '1 year'"))) %>%
    mutate(lead_period = sql("lead_period::date")) %>%
    inner_join(permnos, by = "ncusip") %>%
    inner_join(permcos, by = c("permno", "permco")) %>%
    select(company_id, period, lead_period, permco) %>%
    distinct() %>%
    compute()

activism_events_mod <-
    activism_events %>%
    inner_join(permcos, by = "permno") %>%
    select(campaign_id, eff_announce_date, permco, affiliated) %>%
    inner_join(equilar_final, by = "permco") %>%
    filter(between(eff_announce_date, period, lead_period)) %>%
    select(campaign_id, company_id, period)

rs <- dbExecute(pg, "DROP TABLE IF EXISTS activism_events_equilar")

activism_events_equilar <-
    equilar_final %>%
    inner_join(activism_events_mod, by = c("company_id", "period")) %>%
    select(company_id, period, campaign_id) %>%
    compute(name = "activism_events_equilar", temporary=FALSE)

dbGetQuery(pg, "ALTER TABLE activism_events_equilar OWNER TO activism")

sql <- paste("
  COMMENT ON TABLE activism_events_equilar IS
             'CREATED USING create_activism_events_equilar ON ",
             format(Sys.time(), "%Y-%m-%d %X %Z"), "';", sep="")
rs <- dbExecute(pg, paste(sql, collapse="\n"))

rs <- dbDisconnect(pg)
