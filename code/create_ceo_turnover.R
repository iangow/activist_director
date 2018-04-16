library(RPostgreSQL)
library(dplyr, warn.conflicts = FALSE)

pg <- dbConnect(PostgreSQL())
rs <- dbExecute(pg, "SET search_path TO activist_director")
rs <- dbExecute(pg, "SET work_mem='5GB';")

# Connect to underlying tables ----
proxy_management <-
    tbl(pg, sql("SELECT * FROM executive.proxy_management"))
proxy_management_calc <-
    tbl(pg, sql("SELECT * FROM executive.proxy_management_calc"))
proxy_company <-
    tbl(pg, sql("SELECT * FROM executive.proxy_company"))

fy_ends <-
    proxy_company %>%
    select(company_id, fy_id, fy_end)

ceos <-
    proxy_management_calc %>%
    filter(is_ceo) %>%
    select(company_id, fy_id, management_id) %>%
    inner_join(proxy_management) %>%
    inner_join(fy_ends) %>%
    filter(is.na(date_resign_ceo) | date_resign_ceo > fy_end) %>%
    select(company_id, fy_end, management_id, executive_id, date_start_ceo,
           date_resign_ceo, title) %>%
    compute()

num_ceos <-
    ceos %>%
    select(company_id, fy_end, executive_id) %>%
    distinct() %>%
    group_by(company_id, fy_end) %>%
    summarize(num_ceos = n()) %>%
    ungroup() %>%
    compute()

sole_ceo_firm_years <-
    num_ceos %>%
    filter(num_ceos == 1)

# Finalize table creation ----
dbExecute(pg, "DROP TABLE IF EXISTS ceo_turnover")

ceo_turnover <-
    ceos %>%
    semi_join(sole_ceo_firm_years) %>%
    group_by(company_id) %>%
    arrange(fy_end) %>%
    mutate(lag_fy_end = lag(fy_end),
           ceo_turnover = executive_id != lag(executive_id)) %>%
    ungroup() %>%
    filter(is.na(lag_fy_end) | lag_fy_end > sql("fy_end - interval '13 months'")) %>%
    select(company_id, fy_end, ceo_turnover) %>%
    group_by(company_id) %>%
    arrange(fy_end) %>%
    mutate(ceo_turnover_p1 = lead(ceo_turnover, 1L)) %>%
    mutate(ceo_turnover_p2 = ceo_turnover_p1 | lead(ceo_turnover, 2L)) %>%
    mutate(ceo_turnover_p3 = ceo_turnover_p2 | lead(ceo_turnover, 3L)) %>%
    mutate_at(vars(matches("^ceo_turnover_p")), .funs = as.integer) %>%
    compute(name = "ceo_turnover", temporary = FALSE)

rs <- dbExecute(pg, "ALTER TABLE ceo_turnover OWNER TO activism")
rs <- dbExecute(pg, "COMMENT ON TABLE ceo_turnover IS 'CREATED WITH create_ceo_turnover.R'")

rs <- dbDisconnect(pg)
