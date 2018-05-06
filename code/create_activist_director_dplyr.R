library(RPostgreSQL)
library(dplyr, warn.conflicts = FALSE)

pg <- dbConnect(PostgreSQL())

rs <- dbGetQuery(pg, "SET work_mem='8GB'")
rs <- dbGetQuery(pg, "SET search_path='activist_director'")

crsp.stocknames <- tbl(pg, sql("SELECT * FROM crsp.stocknames"))
activist_director.permnos <- tbl(pg, sql("SELECT * FROM activist_director.permnos"))
equilar_hbs.company_financials <- tbl(pg, sql("SELECT *, fye AS period FROM equilar_hbs.company_financials"))
equilar_hbs.director_index <- tbl(pg, sql("SELECT * FROM equilar_hbs.director_index"))
activist_director.activist_directors <-
    tbl(pg, sql("SELECT * FROM activist_directors"))
activist_director.activism_events <-
    tbl(pg, sql("SELECT * FROM activism_events"))
activist_director_equilar <-
    tbl(pg, sql("SELECT * FROM activist_director_equilar"))
activist_equilar_hbs.director_index <-
    tbl(pg, sql("SELECT * FROM equilar_hbs.director_index"))
boardex.director_characteristics <-
    tbl(pg, sql("SELECT * FROM boardex.director_characteristics"))
boardex.board_characteristics <-
    tbl(pg, sql("SELECT * FROM boardex.board_characteristics"))
boardex.company_profile_stocks <-
    tbl(pg, sql("SELECT * FROM boardex.company_profile_stocks"))

# Create Equilar link table ----
permcos <-
    crsp.stocknames %>%
    select(permno, permco) %>%
    distinct() %>%
    compute()

permnos <-
    crsp.stocknames %>%
    select(permno, permco, ncusip) %>%
    rename(cusip = ncusip) %>%
    distinct() %>%
    compute()

equilar <-
    equilar_hbs.director_index %>%
    left_join(equilar_hbs.company_financials, by=c("company_id", "period")) %>%
    mutate(ncusip = substr(cusip, 1L, 8L)) %>%
    rename(start_date = date_start) %>%
    mutate(first_name = sql("(director.parse_name(director_name)).first_name"),
           last_name = sql("(director.parse_name(director_name)).last_name")) %>%
    select(company_id, executive_id, director_name, period,
           first_name, last_name, start_date, cusip) %>%
    rename(director = director_name) %>%
    compute()

equilar_w_permnos <-
    equilar %>%
    rename(ncusip = cusip) %>%
    inner_join(activist_director.permnos) %>%
    inner_join(permcos)

first_name_years <-
    equilar %>%
    group_by(company_id, executive_id) %>%
    summarize(period = min(period)) %>%
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

activist_directors <-
    activist_director.activist_directors %>%
    select(campaign_id, first_name, last_name,
           independent, appointment_date, retirement_date,
           permno) %>%
    mutate(first_name_l = lower(first_name),
           last_name_l = lower(last_name)) %>%
    mutate(first1 = substr(first_name_l, 1L, 1L),
           first2 = substr(first_name_l, 1L, 2L)) %>%
    inner_join(permcos) %>%
    compute()

match_1 <-
    activist_directors %>%
    inner_join(equilar_final, by=c("permco", "last_name_l", "first_name_l")) %>%
    select(campaign_id, period, first_name, last_name, company_id, executive_id, appointment_date, retirement_date, independent) %>%
    compute()

match_2 <-
    activist_directors %>%
    inner_join(equilar_final, by=c("permco", "last_name_l", "first2")) %>%
    select(campaign_id, period, first_name, last_name, company_id, executive_id, appointment_date, retirement_date, independent)

match_3 <-
    activist_directors %>%
    inner_join(equilar_final, by=c("permco", "last_name_l", "first1")) %>%
    select(campaign_id, period, first_name, last_name, company_id, executive_id, appointment_date, retirement_date, independent)

match_4 <-
    activist_directors %>%
    inner_join(equilar_final, by=c("permco", "last_name_l")) %>%
    select(campaign_id, period, first_name, last_name, company_id, executive_id, appointment_date, retirement_date, independent)

match_a <-
    match_1 %>%
    union(match_2 %>% anti_join(match_1, by=c("campaign_id", "period", "first_name", "last_name")))

match_b <-
    match_a %>%
    union(match_3 %>% anti_join(match_a, by=c("campaign_id", "period", "first_name", "last_name"))) %>%
    compute()

dbGetQuery(pg, "DROP TABLE IF EXISTS activist_director_equilar")

activist_director_equilar <-
    match_b %>%
    union(match_4 %>% anti_join(match_b, by=c("campaign_id", "period", "first_name", "last_name"))) %>%
    compute(name = "activist_director_equilar", temporary=FALSE) %>%
    arrange(campaign_id, period, last_name)

dbGetQuery(pg, "COMMENT ON TABLE activist_director_equilar IS
                'CREATED USING activist_director_dplyr.R'")

dbGetQuery(pg, "ALTER TABLE activist_director_equilar OWNER TO activism")
