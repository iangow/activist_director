library(RPostgreSQL)
library(dplyr, warn.conflicts = FALSE)

pg <- dbConnect(PostgreSQL())

rs <- dbGetQuery(pg, "SET work_mem='8GB'")
rs <- dbGetQuery(pg, "SET search_path TO activist_director, executive_gsb")

stocknames <- tbl(pg, sql("SELECT * FROM crsp.stocknames"))

company_financials <- tbl(pg, "proxy_company")
proxy_board_director <- tbl(pg, "proxy_board_director")
executive <- tbl(pg, "executive")

director_index <-
    proxy_board_director %>%
    left_join(executive %>% select(-title))

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

equilar <-
    director_index %>%
    left_join(company_financials, by=c("company_id", "fiscal_year_id")) %>%
    rename(period = fy_end) %>%
    mutate(ncusip = substr(cusip, 1L, 8L)) %>%
    rename(start_date = date_start) %>%
    mutate(first_name = fname,
           last_name = lname) %>%
    select(company_id, executive_id, period,
           first_name, last_name, start_date, cusip) %>%
    mutate(director = first_name %||% last_name) %>%
    arrange(company_id, executive_id, period) %>%
    compute()

equilar_w_permnos <-
    equilar %>%
    rename(ncusip = cusip) %>%
    inner_join(permnos) %>%
    inner_join(permcos)

first_name_years <-
    equilar %>%
    group_by(company_id, executive_id) %>%
    summarize(period = min(period)) %>%
    arrange(company_id, executive_id) %>%
    compute()

equilar_final <-
    first_name_years %>%
    inner_join(equilar_w_permnos,
               by = c("company_id", "executive_id", "period")) %>%
    select(company_id, executive_id, period,
           director, first_name, last_name, permno, permco) %>%
    mutate(first_name_l = lower(first_name),
           last_name_l = lower(last_name)) %>%
    mutate(first1 = substr(first_name_l, 1L, 1L),
           first2 = substr(first_name_l, 1L, 2L)) %>%
    select(-first_name, -last_name) %>%
    distinct() %>%
    compute()

activist_directors_mod <-
    activist_directors %>%
    select(campaign_id, first_name, last_name,
           independent, appointment_date, retirement_date,
           permno) %>%
    mutate(first_name_l = lower(first_name),
           last_name_l = lower(last_name)) %>%
    mutate(first1 = substr(first_name_l, 1L, 1L),
           first2 = substr(first_name_l, 1L, 2L)) %>%
    inner_join(permcos) %>%
    arrange(permco, appointment_date) %>%
    compute()

match_1 <-
    activist_directors_mod %>%
    inner_join(equilar_final, by=c("permco", "last_name_l", "first_name_l")) %>%
    select(campaign_id, period, first_name, last_name, company_id,
           executive_id, appointment_date, retirement_date, independent) %>%
    compute()

match_2 <-
    activist_directors_mod %>%
    inner_join(equilar_final, by=c("permco", "last_name_l", "first2")) %>%
    select(campaign_id, period, first_name, last_name, company_id,
           executive_id, appointment_date, retirement_date, independent)

match_3 <-
    activist_directors_mod %>%
    inner_join(equilar_final, by=c("permco", "last_name_l", "first1")) %>%
    select(campaign_id, period, first_name, last_name, company_id,
           executive_id, appointment_date, retirement_date, independent)

match_4 <-
    activist_directors_mod %>%
    inner_join(equilar_final, by=c("permco", "last_name_l")) %>%
    select(campaign_id, period, first_name, last_name, company_id,
           executive_id, appointment_date, retirement_date, independent)

match_a <-
    match_1 %>%
    union(match_2 %>%
              anti_join(match_1,
                        by=c("campaign_id", "period", "first_name", "last_name")))

match_b <-
    match_a %>%
    union(match_3 %>%
              anti_join(match_a,
                        by=c("campaign_id", "period", "first_name", "last_name"))) %>%
    compute()

dbGetQuery(pg, "DROP TABLE IF EXISTS activist_director_equilar_alt")

activist_director_equilar <-
    match_b %>%
    union(match_4 %>%
              anti_join(match_b,
                        by=c("campaign_id", "period", "first_name", "last_name"))) %>%
    select(campaign_id, first_name, last_name, company_id, executive_id, appointment_date, retirement_date, independent) %>%
    arrange(company_id, executive_id) %>%
    compute(name = "activist_director_equilar_alt", temporary=FALSE)

dbGetQuery(pg, "COMMENT ON TABLE activist_director_equilar_alt IS
                'CREATED USING activist_director_equilar.R'")

dbGetQuery(pg, "ALTER TABLE activist_director_equilar_alt OWNER TO activism")
