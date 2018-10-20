library(RPostgreSQL)
library(dplyr, warn.conflicts = FALSE)
library(stringr)
pg <- dbConnect(PostgreSQL())
rs <- dbExecute(pg, "SET search_path TO activist_director")

# Get data from activist director tables ----
outcome_controls <- tbl(pg, "outcome_controls")

# Data from CRSP ----
ccmxpf_linktable <-
    tbl(pg, sql("SELECT * FROM crsp.ccmxpf_linktable"))

gvkeys <- tbl(pg, sql("SELECT * FROM executive.gvkeys"))

# Data from Equilar ----
proxy_company <- tbl(pg, sql("SELECT * FROM executive.proxy_company"))
proxy_management <-
    tbl(pg, sql("SELECT * FROM executive.proxy_management"))
proxy_management_calc <-
    tbl(pg, sql("SELECT * FROM executive.proxy_management_calc"))
executive <-
    tbl(pg, sql("SELECT * FROM executive.executive"))

fy_ends <-
    proxy_company %>%
    select(company_id, fy_id, fy_end)

# CEO compensation data ----
executive_names <-
    executive %>%
    select(executive_id, lname, fname)

salary <-
    proxy_management %>%
    select(fy_id, company_id, management_id, fiscal_year,
           executive_id, comp_salary, title)

total_comp <-
    proxy_management_calc %>%
    filter(is_ceo | is_ceo_iss) %>%
    select(fy_id, company_id, management_id, comp_total)

combined_data <-
    salary %>%
    inner_join(executive_names) %>%
    inner_join(total_comp) %>%
    inner_join(fy_ends) %>%
    select(-fy_id) %>%
    mutate(perf_comp = if_else(comp_total > 0, 1 - 1.0*comp_salary/comp_total, NA_real_))

ceo_comp <-
    combined_data %>%
    group_by(company_id, fy_end) %>%
    summarize(ceo_comp = avg(comp_total),
              perf_comp = avg(perf_comp)) %>%
    group_by(company_id) %>%
    arrange(fy_end) %>%
    mutate(ceo_comp_p1 = lead(ceo_comp, 1L),
           ceo_comp_p2 = lead(ceo_comp, 2L),
           ceo_comp_p3 = lead(ceo_comp, 3L),
           perf_comp_p1 = lead(perf_comp, 1L),
           perf_comp_p2 = lead(perf_comp, 2L),
           perf_comp_p3 = lead(perf_comp, 3L)) %>%
    mutate(ceo_comp = if_else(ceo_comp > 0, ln(ceo_comp), NA_real_),
           ceo_comp_p1 = if_else(ceo_comp_p1 > 0, ln(ceo_comp_p1), NA_real_),
           ceo_comp_p2 = if_else(ceo_comp_p2 > 0, ln(ceo_comp_p2), NA_real_),
           ceo_comp_p3 = if_else(ceo_comp_p3 > 0, ln(ceo_comp_p3), NA_real_)) %>%
    compute()

# CEO turnover ----
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

# Finalize table creation
ceo_turnover <-
    ceos %>%
    semi_join(sole_ceo_firm_years) %>%
    group_by(company_id) %>%
    arrange(fy_end) %>%
    mutate(lag_fy_end = lag(fy_end),
           ceo_turnover = executive_id != lag(executive_id)) %>%
    mutate(ceo_turnover = if_else(!is.na(date_start_ceo) &
                                      date_start_ceo < fy_end - sql("interval '1 year'") &
                                      (is.na(date_resign_ceo) | date_resign_ceo > fy_end),
                                  FALSE, ceo_turnover)) %>%
    ungroup() %>%
    filter(is.na(lag_fy_end) | lag_fy_end > sql("fy_end - interval '13 months'")) %>%
    select(company_id, fy_end, ceo_turnover) %>%
    group_by(company_id) %>%
    arrange(fy_end) %>%
    mutate(ceo_turnover_p1 = lead(ceo_turnover, 1L)) %>%
    mutate(ceo_turnover_p2 = ceo_turnover_p1 | lead(ceo_turnover, 2L)) %>%
    mutate(ceo_turnover_p3 = ceo_turnover_p2 | lead(ceo_turnover, 3L)) %>%
    mutate_at(vars(matches("^ceo_turnover_p")), .funs = as.integer) %>%
    ungroup() %>%
    compute()

# Process data ----
ceo_data <-
    ceo_comp %>%
    full_join(ceo_turnover) %>%
    select(company_id, fy_end, ceo_turnover, matches("(ceo_turnover_p|ceo_comp|perf_comp)"))

fy_ends <-
    ceo_data %>%
    select(company_id, fy_end) %>%
    distinct() %>%
    compute()

permno_links <-
    fy_ends %>%
    inner_join(gvkeys) %>%
    filter(between(fy_end, fye_first, fye_last)) %>%
    select(company_id, fy_end, gvkey) %>%
    inner_join(ccmxpf_linktable) %>%
    rename(permno = lpermno) %>%
    filter(usedflag == 1L,
           linkprim %in% c('C', 'P'),
           fy_end >= linkdt,
           fy_end <= linkenddt | is.na(linkenddt)) %>%
    select(company_id, fy_end, permno) %>%
    distinct() %>%
    compute()

ceo_data_permnos <-
    ceo_data %>%
    left_join(permno_links, by = c("company_id", "fy_end")) %>%
    rename(datadate = fy_end)

rs <- dbExecute(pg, "DROP TABLE IF EXISTS ceo_outcomes")
ceo_outcomes <-
    outcome_controls %>%
    mutate(default_p2 = if_else(firm_exists_p2, FALSE, NA),
           default_p3 = if_else(firm_exists_p3, FALSE, NA),
           default_num_p2 = if_else(firm_exists_p2, 0, NA_real_),
           default_num_p3 = if_else(firm_exists_p3, 0, NA_real_),
           datadate_p2 = sql("datadate + interval '2 years'"),
           datadate_p3 = sql("datadate + interval '3 years'")) %>%
    filter(firm_exists_p3) %>%
    left_join(ceo_data_permnos, by = c("permno", "datadate")) %>%
    arrange(permno, datadate) %>%
    compute(name = "ceo_outcomes", temporary = FALSE)

rs <- dbExecute(pg, "ALTER TABLE ceo_outcomes OWNER TO activism")

sql <- paste("
  COMMENT ON TABLE ceo_outcomes IS
             'CREATED USING create_ceo_outcomes.R ON ",
             format(Sys.time(), "%Y-%m-%d %X %Z"), "';", sep="")
rs <- dbGetQuery(pg, paste(sql, collapse="\n"))


rs <- dbDisconnect(pg)
