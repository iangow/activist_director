library(DBI)
library(dplyr, warn.conflicts = FALSE)

pg <- dbConnect(RPostgres::Postgres(), bigint = "integer")

rs <- dbExecute(pg, "SET search_path TO activist_director, public")
rs <- dbExecute(pg, "SET work_mem = '2GB'")

# Create activist_director.equilar_type ----
library(DBI)
library(dplyr, warn.conflicts = FALSE)

pg <- dbConnect(RPostgres::Postgres(), bigint = "integer")

rs <- dbExecute(pg, "SET search_path TO activist_director, public")

activism_events <- tbl(pg, "activism_events")
activist_director_equilar <- tbl(pg, "activist_director_equilar")
equilar_final <- tbl(pg, "equilar_final")
company_financials <- tbl(pg, sql("SELECT * FROM equilar_hbs.company_financials"))
stocknames <- tbl(pg, sql("SELECT * FROM crsp.stocknames"))

start_dates <-
    equilar_final %>%
    select(company_id, executive_id, company_director_min_start) %>%
    distinct()

link_table <-
    company_financials %>%
    mutate(ncusip = substr(cusip, 1L, 8L)) %>%
    inner_join(stocknames, by="ncusip") %>%
    select(company_id, permno) %>%
    distinct()

rs <- dbExecute(pg, "DROP TABLE IF EXISTS equilar_type")

equilar_type <-
    activism_events %>%
    inner_join(link_table, by = "permno") %>%
    select(company_id, first_date, end_date) %>%
    inner_join(equilar_final, by = "company_id") %>%
    mutate(fix_date = is.na(company_director_min_start) & company_director_min_period > company_min_period,
           company_director_min_start = if_else(fix_date, company_director_min_period, company_director_min_start)) %>%
    select(company_id, executive_id, company_director_min_start, first_date, end_date) %>%
    distinct() %>%
    mutate(activism = between(company_director_min_start, first_date, end_date)) %>%
    left_join(activist_director_equilar, by = c("company_id", "executive_id")) %>%
    mutate(activist_director = !is.na(appointment_date)) %>%
    mutate(activism = if_else(activist_director, TRUE, activism)) %>%
    select(company_id, executive_id, activism, activist_director, independent) %>%
    group_by(company_id, executive_id) %>%
    summarize_all(funs(bool_or)) %>%
    mutate(affiliated = case_when(independent ~ "unaffiliated",
                                  !independent ~ "affiliated",
                                  TRUE ~ "non_activist")) %>%
    ungroup() %>%
    compute(name = "equilar_type", temporary = FALSE)

rs <- dbExecute(pg, "ALTER TABLE equilar_type OWNER TO activism")
