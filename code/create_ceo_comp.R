library(RPostgreSQL)
library(dplyr, warn.conflicts = FALSE)
library(stringr)
pg <- dbConnect(PostgreSQL())
rs <- dbExecute(pg, "SET search_path TO activist_director")

# Data from Equilar ----
proxy_company <- tbl(pg, sql("SELECT * FROM executive.proxy_company"))
proxy_management <-
    tbl(pg, sql("SELECT * FROM executive.proxy_management"))
proxy_management_calc <-
    tbl(pg, sql("SELECT * FROM executive.proxy_management_calc"))
executive <-
    tbl(pg, sql("SELECT * FROM executive.executive"))

ccmxpf_linktable <-
    tbl(pg, sql("SELECT * FROM crsp.ccmxpf_linktable"))

# Process data ----
fy_ends <-
    proxy_company %>%
    select(company_id, fy_id, fy_end)

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

# Create final table ----
rs <- dbExecute(pg, "DROP TABLE IF EXISTS ceo_comp")

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
    compute(name = "ceo_comp", temporary = FALSE)

rs <- dbExecute(pg, "ALTER TABLE ceo_comp OWNER TO activism")
rs <- dbExecute(pg, "COMMENT ON TABLE ceo_comp IS 'CREATED WITH create_ceo_comp.R'")

rs <- dbDisconnect(pg)
