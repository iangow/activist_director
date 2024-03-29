library(DBI)
library(dplyr, warn.conflicts = FALSE)

pg <- dbConnect(RPostgres::Postgres())

rs <- dbExecute(pg, "SET work_mem='8GB'")
rs <- dbExecute(pg, "SET search_path TO activist_director")

stocknames <- tbl(pg, sql("SELECT * FROM crsp.stocknames"))
company_financials <- tbl(pg, sql("SELECT * FROM equilar_hbs.company_financials"))
director_index <- tbl(pg, sql("SELECT * FROM equilar_hbs.director_index"))

activist_directors <- tbl(pg, "activist_directors")
activism_events <- tbl(pg, "activism_events")

# Create Equilar link table ----
permcos <-
    stocknames %>%
    select(permno, permco) %>%
    distinct() %>%
    compute()

permnos <-
    stocknames %>%
    select(permno, permco, ncusip) %>%
    distinct() %>%
    compute()

equilar <-
    director_index %>%
    rename(fye = period) %>%
    left_join(company_financials, by=c("company_id", "fye")) %>%
    rename(period = fye) %>%
    mutate(ncusip = substr(cusip, 1L, 8L)) %>%
    rename(start_date = date_start) %>%
    mutate(first_name = sql("(parse_name(director_name)).first_name"),
           last_name = sql("(parse_name(director_name)).last_name")) %>%
    select(company_id, executive_id, director_name, period,
           first_name, last_name, start_date, cusip) %>%
    rename(director = director_name) %>%
    compute()

equilar_w_permnos <-
    equilar %>%
    rename(ncusip = cusip) %>%
    inner_join(permnos) %>%
    inner_join(permcos)

first_name_years <-
    equilar %>%
    group_by(company_id, executive_id) %>%
    summarize(period = min(period, na.rm = TRUE)) %>%
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
           independent, appointment_date, retirement_date, permno) %>%
    mutate(first_name_l = lower(first_name),
           last_name_l = lower(last_name)) %>%
    mutate(first1 = substr(first_name_l, 1L, 1L),
           first2 = substr(first_name_l, 1L, 2L)) %>%
    inner_join(permcos) %>%
    compute()

# Manual matches ----
match_0 <-
  tribble(
    ~campaign_id, ~first_name, ~last_name, ~executive_id,
    901233382L, "Robert", "Burton", 29967L,   # Based on age
    1073547269L, "William", "Pulte", 1084104L, # Based on age

    # Two director with same name; used age and appointment date
    704946108L, "David", "Stevens", 983498L
  ) %>%
  copy_to(pg, ., name = "match_0", overwrite = TRUE)

match_1 <-
    activist_directors_mod %>%
    inner_join(equilar_final, by=c("permco", "last_name_l", "first_name_l")) %>%
    select(campaign_id, first_name, last_name, executive_id) %>%
    compute()

match_2 <-
    activist_directors_mod %>%
    inner_join(equilar_final, by=c("permco", "last_name_l", "first2")) %>%
    select(campaign_id, first_name, last_name, executive_id)

match_3 <-
    activist_directors_mod %>%
    inner_join(equilar_final, by=c("permco", "last_name_l", "first1")) %>%
    select(campaign_id, first_name, last_name,
           executive_id)

match_4 <-
    activist_directors_mod %>%
    inner_join(equilar_final, by=c("permco", "last_name_l")) %>%
  select(campaign_id, first_name, last_name, executive_id) %>%
  compute()

match_aa <-
  match_0 %>%
  union_all(match_1 %>%
            anti_join(match_0,
                      by=c("campaign_id", "first_name", "last_name"))) %>%
  compute()

match_a <-
    match_aa %>%
    union_all(match_2 %>%
              anti_join(match_aa,
                        by=c("campaign_id", "first_name", "last_name")))

match_b <-
    match_a %>%
    union_all(match_3 %>%
              anti_join(match_a,
                        by=c("campaign_id", "first_name", "last_name"))) %>%
    compute()

match_c <-
  match_b %>%
  union_all(match_4 %>%
              anti_join(match_b,
                        by=c("campaign_id", "first_name", "last_name"))) %>%
  compute()



# Link activism events to Equilar company_id values
equilar_permnos <-
  equilar_w_permnos %>%
  select(company_id, permno) %>%
  distinct() %>%
  compute()

activism_events_equilar <-
  activism_events %>%
  inner_join(equilar_permnos, by = "permno") %>%
  select(company_id, campaign_id) %>%
  compute()

dbExecute(pg, "DROP TABLE IF EXISTS activist_director_equilar")

activist_director_equilar <-
  match_c %>%
  inner_join(activism_events_equilar, by = "campaign_id") %>%
  inner_join(activist_directors) %>%
  select(campaign_id, first_name, last_name, company_id,
         executive_id) %>%
  compute(name = "activist_director_equilar", temporary=FALSE)

dbExecute(pg, "ALTER TABLE activist_director_equilar OWNER TO activism")

sql <- paste("
  COMMENT ON TABLE activist_director_equilar IS
             'CREATED USING create_activist_director_equilar ON ",
             format(Sys.time(), "%Y-%m-%d %X %Z"), "';", sep="")
rs <- dbExecute(pg, paste(sql, collapse="\n"))

rs <- dbDisconnect(pg)
