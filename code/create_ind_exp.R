equilar_lib <- "executive_gsb"
library(dplyr, warn.conflicts = FALSE)
library(DBI)

pg <- dbConnect(RPostgres::Postgres(), bigint = "integer")

rs <- dbExecute(pg,
                paste0("SET search_path TO activist_director, ", equilar_lib))

activist_directors <- tbl(pg, "activist_directors")

activist_directors
activist_director_equilar <- tbl(pg, "activist_director_equilar")

proxy_company  <- tbl(pg, "proxy_company")

fy_ends <-
    proxy_company %>%
    select(fy_id, company_id, fy_end)

fy_ends
proxy_company <- tbl(pg, "proxy_company")
proxy_management <- tbl(pg, "proxy_management")
executive <- tbl(pg, "executive")

stocknames <- tbl(pg, sql("SELECT * FROM crsp.stocknames"))

sics <-
    stocknames %>%
    select(ncusip, siccd) %>%
    rename(cusip = ncusip) %>%
    distinct()

equilar_sics <-
    proxy_company %>%
    select(company_id, cusip) %>%
    inner_join(sics, by = "cusip") %>%
    distinct() %>%
    select(-cusip) %>%
    compute()

start_dates <-
    proxy_management %>%
    select(company_id, fy_id, executive_id, date_start) %>%
    inner_join(fy_ends, by = c("company_id", "fy_id")) %>%
    mutate(date = coalesce(date_start, fy_end)) %>%
    group_by(company_id, executive_id) %>%
    summarize(date = min(date, na.rm = TRUE)) %>%
    ungroup() %>%
    compute()

prior_appts <-
    activist_director_equilar %>%
    inner_join(start_dates, by = c("executive_id"),
              suffix = c("_own", "_other")) %>%
    filter(company_id_own != company_id_other,
           date < appointment_date) %>%
    left_join(equilar_sics, by=c("company_id_own"="company_id")) %>%
    rename(sic_own = siccd) %>%
    left_join(equilar_sics, by=c("company_id_other"="company_id")) %>%
    rename(sic_other = siccd) %>%
    select(campaign_id, first_name, last_name, sic_own, sic_other)

rs <- dbExecute(pg, "DROP TABLE IF EXISTS ind_exp")

ind_exp <-
    prior_appts %>%
    mutate(same_sic2 = substr(as.character(sic_own), 1, 2)==
               substr(as.character(sic_other), 1, 2)) %>%
    group_by(campaign_id, first_name, last_name) %>%
    summarize(prior_ind_exp = bool_or(same_sic2)) %>%
    compute(name = "ind_exp", temporary = FALSE)

rs <- dbExecute(pg, "ALTER TABLE ind_exp OWNER TO activism")

sql <- paste0("
    COMMENT ON TABLE ind_exp IS
              'CREATED USING create_ind_exp.R ON ",
              format(Sys.time(), "%Y-%m-%d %X %Z"), "';")

rs <- dbExecute(pg, sql)

rs <- dbDisconnect(pg)
