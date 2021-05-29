library(DBI)
library(dplyr, warn.conflicts = FALSE)
library(dbplyr) # For window_order

pg <- dbConnect(RPostgres::Postgres())

rs <- dbExecute(pg, "SET work_mem='8GB'")
rs <- dbExecute(pg, "SET search_path TO activist_director, equilar_hbs")

stocknames <- tbl(pg, sql("SELECT * FROM crsp.stocknames"))

company_financials <- tbl(pg, "company_financials")
director_index <- tbl(pg, "director_index")

activist_directors <- tbl(pg, "activist_directors")
activist_director_equilar <- tbl(pg, "activist_director_equilar")
activism_events <- tbl(pg, "activism_events")

permnos <- tbl(pg, "permnos")

# Identify companies' first years + lag_period
company_first_years <-
    company_financials %>%
    select(company_id, fye) %>%
    rename(period = fye) %>%
    # Here distinct() eliminates three rows; seems to be garbage.
    distinct() %>%
    compute() %>%
    group_by(company_id) %>%
    window_order(period) %>%
    mutate(lag_period = lag(period),
           first_period_company = min(period, na.rm = TRUE),
           firm_first_year = period==first_period_company)

# Bring in activist directors matched with Equilar
activist_directors_mod <-
    activist_directors %>%
    inner_join(activist_director_equilar) %>%
    select(-source, -bio, -issuer_cik)

# Pull together director characteristics
equilar <-
    company_first_years %>%
    inner_join(director_index, by = c("company_id", "period")) %>%
    filter(period > '2000-12-31') %>%
    mutate(tenure_calc = (period - date_start)/365.25,
           female = gender=='F',
           male = gender=='M') %>%
    mutate(parsed_name = parse_name(director_name)) %>%
    mutate(first_name = sql("(parsed_name).first_name"),
           last_name = sql("(parsed_name).first_name")) %>%
    select(company_id, executive_id, period, director_name,
           date_start, age, tenure_calc, tenure, female, male, cmtes_cnt, cmtes,
           insider_outsider_related, is_chair, is_vice_chair, is_lead,
           is_audit_cmte_spec, first_name, last_name) %>%
    mutate(any_committee = cmtes_cnt > 0,
           outsider = insider_outsider_related=='Outsider',
           insider = insider_outsider_related=='Insider',
           comp_committee = coalesce(cmtes %~% 'Comp', FALSE),
           audit_committee = coalesce(cmtes %~% 'Audit', FALSE)) %>%
    rename(director = director_name,
           audit_committee_financial_expert = is_audit_cmte_spec)  %>%
    distinct() %>%
    compute()

# Match Equilar to PERMCOs
equilar_permnos <-
    company_financials %>%
    rename(period = fye) %>%
    mutate(ncusip = substr(cusip, 1L, 8L)) %>%
    left_join(permnos, by = "ncusip") %>%
    select(company_id, period, permno) %>%
    inner_join(stocknames, by = "permno") %>%
    select(company_id, period, permno, permco) %>%
    distinct() %>%
    compute()

# Identify directors' first years
director_first_years <-
    director_index %>%
    left_join(company_first_years,
              by = c("company_id", "period")) %>%
    left_join(activist_director_equilar,
              by = c("company_id", "executive_id")) %>%
    select(-campaign_id, -first_name, -last_name, -retirement_date, -independent) %>%
    mutate(date_start = coalesce(appointment_date, date_start)) %>%
    mutate(first_period_director = min(period)) %>%
    select(-appointment_date) %>%
    distinct() %>%
    compute() %>%
    group_by(executive_id, company_id) %>%
    mutate(first_period_director = min(period, na.rm = TRUE)) %>%
    mutate(new_director = (between(date_start, lag_period, period))
                        | (is.na(lag_period) & date_start >
                             sql("period - interval '12 months'"))
                        | (first_period_director==period &
                             first_period_company==period &
                             is.na(date_start))) %>%
    select(company_id, executive_id, period, firm_first_year, date_start,
           new_director)

# Classify directors' first years on Equilar based on whether
# they were appointed during an activism event or shortly thereafter
equilar_activism_match <-
    director_first_years %>%
    filter(new_director) %>%
    inner_join(equilar_permnos, by = c("company_id", "period")) %>%
    inner_join(activism_events, by = "permno") %>%
    filter(between(date_start, first_date, sql("end_date + interval '128 days'"))) %>%
    group_by(permno, company_id, executive_id, period) %>%
    summarize(sharkwatch50 = bool_or(sharkwatch50),
              activism_firm = bool_or(activism),
              activist_demand_firm = bool_or(activist_demand),
              activist_director_firm = bool_or(activist_director),
              .groups = "drop")

director_first_years_plus <-
    director_first_years %>%
    left_join(equilar_activism_match,
              by = c("company_id", "executive_id", "period")) %>%
    select(-date_start, -permno)

rs <- dbExecute(pg, "DROP TABLE IF EXISTS equilar_w_activism")

equilar_w_activism <-
    equilar %>%
    left_join(equilar_permnos) %>%
    left_join(director_first_years_plus,
               by = c("company_id", "executive_id", "period")) %>%
    select(-first_name, -last_name) %>%
    left_join(activist_directors_mod) %>%
    mutate(firm_first_year = coalesce(firm_first_year, FALSE),
           sharkwatch50 = coalesce(sharkwatch50, FALSE),
           activism_firm = coalesce(activism_firm, FALSE),
           activist_demand_firm = coalesce(activist_demand_firm, FALSE),
           activist_director_firm = coalesce(activist_director_firm, FALSE),
           activist_director = !is.na(appointment_date) & new_director,
           independent = case_when(independent & new_director ~ TRUE, TRUE ~ FALSE),
           affiliated_director = !independent,
           category = case_when(activist_director_firm ~ "activist_director_firm",
                                activist_demand_firm ~ "activist_demand_firm",
                                activism_firm ~ "activism_firm",
                                TRUE ~ "_none")) %>%
    distinct() %>%
    compute(name = "equilar_w_activism", temporary = FALSE)

rs <- dbExecute(pg, "ALTER TABLE equilar_w_activism OWNER TO activism")

sql <- paste("
  COMMENT ON TABLE equilar_w_activism IS
    'CREATED USING create_equilar_w_activism ON ",
             format(Sys.time(), "%Y-%m-%d %X %Z"), "';", sep="")
rs <- dbExecute(pg, paste(sql, collapse="\n"))

rs <- dbDisconnect(pg)
