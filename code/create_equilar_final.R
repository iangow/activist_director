library(DBI)
library(dplyr, warn.conflicts = FALSE)

pg <- dbConnect(RPostgres::Postgres(), bigint = "integer")

rs <- dbExecute(pg, "SET search_path TO activist_director, public")
rs <- dbExecute(pg, "SET work_mem = '2GB'")

director_index <- tbl(pg, sql("SELECT * FROM equilar_hbs.director_index"))
company_financials <- tbl(pg, sql("SELECT * FROM equilar_hbs.company_financials"))
stocknames <- tbl(pg, sql("SELECT * FROM crsp.stocknames"))

# period > '2000-12-31'

equilar <-
    director_index %>%
    inner_join(company_financials, by=c("company_id", "period"="fye")) %>%
    select(company_id, executive_id, period, sic, director_name,
           date_start, term_exp_dt, age, tenure, gender, insider_outsider_related,
           cmtes, cmtes_cnt, is_audit_cmte_spec,
           is_chair, is_vice_chair, is_lead, cusip) %>%
    mutate(year = date_part('year', period),
           sic2 = substr(sic, 1L, 2L),
           names = sql("director.parse_name(director_name)")) %>%
    mutate(first_name = sql('(names).first_name'),
           last_name = sql('(names).last_name'),
           tenure_calc = (period - date_start)/365.25,
           female = gender=='F',
           male = gender=='M',
           outsider = insider_outsider_related=='Outsider',
           insider = insider_outsider_related=='Insider',
           comp_committee = coalesce(cmtes %~% 'Comp', FALSE),
           audit_committee = coalesce(cmtes %~% 'Audit', FALSE),
           any_committee =cmtes_cnt > 0) %>%
    rename(audit_committee_financial_expert = is_audit_cmte_spec) %>%
    select(-names, -director_name, -cmtes, -cmtes_cnt) %>%
    distinct() %>%
    compute()

company_min_period <-
    equilar %>%
    group_by(company_id) %>%
    summarize( company_min_period = min(period, na.rm = TRUE),
               company_max_period = max(period, na.rm = TRUE),
               term_exp_dt = max(term_exp_dt, na.rm = TRUE),
               period = max(period, na.rm = TRUE)) %>%
    mutate(company_max_term = coalesce(term_exp_dt, period)) %>%
    select(-period, -term_exp_dt, -company_max_period)

company_min_start <-
    equilar %>%
    filter( date_start > '1900-01-01') %>%
    group_by(company_id) %>%
    summarize(company_min_start = min(date_start, na.rm = TRUE))

company_director_min_period <-
    equilar %>%
    group_by(company_id, executive_id) %>%
    summarize(company_director_min_period = min(period, na.rm = TRUE),
              company_director_max_period = max(period, na.rm = TRUE),
              term_exp_dt = max(term_exp_dt, na.rm = TRUE)) %>%
    mutate(company_director_max_term = coalesce(term_exp_dt, company_director_max_period)) %>%
    select(-term_exp_dt, -company_director_max_period)

company_director_min_start <-
    equilar %>%
    group_by(company_id, executive_id) %>%
    filter(date_start > '1900-01-01') %>%
    group_by(company_id, executive_id) %>%
    summarize(company_director_min_start = min(date_start, na.rm=TRUE))

director_min_period <-
    equilar %>%
    group_by(executive_id) %>%
    summarize(director_min_period = min(period, na.rm = TRUE),
              director_max_period = max(period, na.rm = TRUE),
              period = max(period, na.rm = TRUE)) %>%
    mutate(director_max_term = coalesce(director_max_period, period)) %>%
    select(-director_max_period, -period)

director_min_start <-
    equilar %>%
    filter(date_start > '1900-01-01') %>%
    group_by(executive_id) %>%
    summarize(director_min_start = min(date_start, na.rm = TRUE))

director_industry_expert <-
    equilar %>%
    distinct(company_id, executive_id, sic2) %>%
    filter(!is.na(sic2)) %>%
    group_by(executive_id, sic2) %>%
    summarize(count = n())

rs <- dbExecute(pg, "DROP TABLE IF EXISTS equilar_final")

permnos <-
    stocknames %>%
    distinct(permno, ncusip)

equilar_final <-
    equilar %>%
    left_join(company_min_period, by = "company_id") %>%
    left_join(company_director_min_period, by = c("company_id", "executive_id")) %>%
    left_join(director_min_period, by = "executive_id") %>%
    left_join(company_min_start, by = "company_id") %>%
    left_join(company_director_min_start, by = c("company_id", "executive_id")) %>%
    left_join(director_min_start, by = "executive_id") %>%
    left_join(director_industry_expert, by = c("executive_id", "sic2")) %>%
    mutate(industry_expert = coalesce(count > 1, FALSE),
           super_industry_expert = coalesce(count > 2, FALSE),
           director_first_years = if_else(between(company_director_min_start,
                                                  company_director_min_period - sql("interval '18 months'"),
                                                  company_director_min_period + sql("interval '18 months'")),
                                          company_director_min_period==period, NA)) %>%
    mutate(ncusip = substr(cusip, 1L, 8L)) %>%
    inner_join(permnos, by = "ncusip") %>%
    select(-ncusip, -cusip) %>%
    compute(name = "equilar_final", temporary = FALSE)

rs <- dbExecute(pg, "ALTER TABLE equilar_final OWNER TO activism")

sql <- paste0("
    COMMENT ON TABLE equilar_final IS
              'CREATED USING create_equilar_final.R ON ",
              format(Sys.time(), "%Y-%m-%d %X %Z"), "';")

rs <- dbExecute(pg, sql)

rs <- dbDisconnect(pg)
