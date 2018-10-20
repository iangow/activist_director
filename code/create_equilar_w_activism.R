library(RPostgreSQL)
library(dplyr, warn.conflicts = FALSE)

pg <- dbConnect(PostgreSQL())

rs <- dbGetQuery(pg, "SET work_mem='8GB'")
rs <- dbGetQuery(pg, "SET search_path TO activist_director, equilar_hbs")

stocknames <- tbl(pg, sql("SELECT * FROM crsp.stocknames"))

company_financials <- tbl(pg, "company_financials")
director_index <- tbl(pg, "director_index")

activist_directors <- tbl(pg, "activist_directors")
activist_director_equilar <- tbl(pg, "activist_director_equilar")
activism_events <- tbl(pg, "activism_events")

permnos <- tbl(pg, sql("SELECT * FROM factset.permnos"))

# Pull together director characteristics
equilar <-
    company_financials %>%
    select(-ticker, -company_name) %>%
    rename(period = fye) %>%
    inner_join(director_index, by = c("company_id", "period")) %>%
    filter(period > '2000-12-31') %>%
    mutate(tenure_calc = (period - date_start)/365.25,
           female = gender=='F',
           male = gender=='M') %>%
    mutate(parsed_name = sql("director.parse_name(director_name)")) %>%
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
    arrange(company_id, executive_id, period) %>%
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
    arrange(permno, period) %>%
    compute()

# Identify companies' first years
company_first_years <-
    company_financials %>%
    group_by(company_id) %>%
    summarize(period = min(fye, na.rm=TRUE)) %>%
    mutate(firm_first_year = TRUE) %>%
    arrange(company_id)

# Identify directors' first years
director_first_years <-
    director_index %>%
    group_by(company_id, executive_id) %>%
    summarize(date_start = min(date_start, na.rm=TRUE),
              period = min(period, na.rm=TRUE)) %>%
    arrange(company_id, executive_id)

# Classify directors' first years on Equilar based on whether
# they were appointed during an activism event or shortly thereafter
equilar_activism_match <-
    director_first_years %>%
    inner_join(equilar_permnos, by = c("company_id", "period")) %>%
    inner_join(activism_events, by = "permno") %>%
    filter(between(date_start, first_date, sql("end_date + interval '128 days'"))) %>%
    group_by(permno, company_id, executive_id, period) %>%
    summarize(sharkwatch50 = bool_or(sharkwatch50),
              activism_firm = bool_or(activism),
              activist_demand_firm = bool_or(activist_demand),
              activist_director_firm = bool_or(activist_director)) %>%
    arrange(permno, executive_id, period)

activist_directors_mod <-
    activist_directors %>%
    inner_join(activist_director_equilar) %>%
    arrange(company_id, executive_id, appointment_date)

director_first_years_plus <-
    director_first_years %>%
    left_join(equilar_activism_match,
              by = c("company_id", "executive_id", "period")) %>%
    select(-date_start, -permno) %>%
    mutate(director_first_year = TRUE)

rs <- dbGetQuery(pg, "DROP TABLE IF EXISTS activist_director.equilar_w_activism")

equilar_w_activism <-
    equilar %>%
    left_join(equilar_permnos) %>%
    left_join(company_first_years, by = c("company_id", "period")) %>%
    left_join(director_first_years_plus,
               by = c("company_id", "executive_id", "period")) %>%
    select(-first_name, -last_name) %>%
    left_join(activist_directors_mod) %>%
    mutate(firm_first_year = coalesce(firm_first_year, FALSE),
           director_first_year = coalesce(director_first_year, FALSE),
           sharkwatch50 = coalesce(sharkwatch50, FALSE),
           activism_firm = coalesce(activism_firm, FALSE),
           activist_demand_firm = coalesce(activist_demand_firm, FALSE),
           activist_director_firm = coalesce(activist_director_firm, FALSE),
           activist_director = !is.na(appointment_date) & director_first_year,
           independent = case_when(independent & director_first_year ~ TRUE, TRUE ~ FALSE),
           affiliated_director = !independent,
           category = case_when(activist_director_firm ~ "activist_director_firm",
                                activist_demand_firm ~ "activist_demand_firm",
                                activism_firm ~ "activism_firm",
                                TRUE ~ "_none")) %>%
    distinct() %>%
    arrange(permno, executive_id, period) %>%
    collect()

rs <- dbWriteTable(pg, c("activist_director", "equilar_w_activism"),
                   equilar_w_activism, overwrite=TRUE, row.names=FALSE)

rs <- dbExecute(pg, "ALTER TABLE activist_director.equilar_w_activism OWNER TO activism")

sql <- paste("
  COMMENT ON TABLE activist_director.equilar_w_activism IS
    'CREATED USING create_equilar_w_activism ON ",
             format(Sys.time(), "%Y-%m-%d %X %Z"), "';", sep="")
rs <- dbExecute(pg, paste(sql, collapse="\n"))

rs <- dbDisconnect(pg)
