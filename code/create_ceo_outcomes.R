library(RPostgreSQL)
library(dplyr, warn.conflicts = FALSE)
library(stringr)
pg <- dbConnect(PostgreSQL())
rs <- dbExecute(pg, "SET search_path TO activist_director")

# Get data from activist director tables ----
ceo_turnover <- tbl(pg, "ceo_turnover")
ceo_comp <- tbl(pg, "ceo_comp")
outcome_controls <- tbl(pg, "outcome_controls")

# Data from CRSP ----
ccmxpf_linktable <-
    tbl(pg, sql("SELECT * FROM crsp.ccmxpf_linktable"))

gvkeys <- tbl(pg, sql("SELECT * FROM executive.gvkeys"))

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
rs <- dbExecute(pg, "COMMENT ON TABLE ceo_outcomes IS 'CREATED WITH create_ceo_outcomes.R'")

rs <- dbDisconnect(pg)
