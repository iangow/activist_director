library(RPostgreSQL)
library(dplyr, warn.conflicts = FALSE)

pg <- dbConnect(PostgreSQL())

rs <- dbGetQuery(pg, "SET work_mem='8GB'")
rs <- dbGetQuery(pg, "SET search_path='activist_director'")

crsp.stocknames <- tbl(pg, sql("SELECT * FROM crsp.stocknames"))
activist_director.permnos <- tbl(pg, sql("SELECT * FROM activist_director.permnos"))
director.co_fin <- tbl(pg, sql("SELECT * FROM director.co_fin"))
director.director <- tbl(pg, sql("SELECT * FROM director.director"))
activist_director.activist_directors <-
    tbl(pg, sql("SELECT * FROM activist_directors"))
activist_director.activism_events <-
    tbl(pg, sql("SELECT * FROM activism_events"))
activist_director_equilar <-
    tbl(pg, sql("SELECT * FROM activist_director_equilar"))
activist_director.director_names <-
    tbl(pg, sql("SELECT * FROM activist_director.director_names"))
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
    director.director %>%
    left_join(director.co_fin, by=c("company_id", "fy_end")) %>%
    mutate(ncusip = substr(cusip, 1L, 8L)) %>%
    rename(start_date = date_start) %>%
    mutate(first_name = sql("(director.parse_name(director_name)).first_name"),
           last_name = sql("(director.parse_name(director_name)).last_name")) %>%
    select(company_id, executive_id, director_name, fy_end,
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
    summarize(fy_end = min(fy_end)) %>%
    compute()

equilar_final <-
    first_name_years %>%
    inner_join(equilar_w_permnos,
               by = c("company_id", "executive_id", "fy_end")) %>%
    select(company_id, executive_id, fy_end,
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
    select(campaign_id, first_name, last_name, company_id, executive_id) %>%
    compute()

match_2 <-
    activist_directors %>%
    inner_join(equilar_final, by=c("permco", "last_name_l", "first2")) %>%
    select(campaign_id, first_name, last_name, company_id, executive_id)

match_3 <-
    activist_directors %>%
    inner_join(equilar_final, by=c("permco", "last_name_l", "first1")) %>%
    select(campaign_id, first_name, last_name, company_id, executive_id)

match_4 <-
    activist_directors %>%
    inner_join(equilar_final, by=c("permco", "last_name_l")) %>%
    select(campaign_id, first_name, last_name, company_id, executive_id)

match_a <-
    match_1 %>%
    union(match_2 %>% anti_join(match_1, by=c("campaign_id", "first_name",
                                           "last_name")))
match_b <-
    match_a %>%
    union(match_3 %>% anti_join(match_a, by=c("campaign_id", "first_name",
                                           "last_name"))) %>%
    compute()

dbGetQuery(pg, "DROP TABLE IF EXISTS activist_director_equilar_new")

activist_director_equilar <-
    match_a %>%
    union(match_4 %>% anti_join(match_a, by=c("campaign_id", "first_name",
                                           "last_name"))) %>%
    compute(name = "activist_director_equilar_new", temporary=FALSE)

dbGetQuery(pg, "COMMENT ON TABLE activist_director_equilar_new IS
                'CREATED USING activist_director_boardex_dplyr.R'")

dbGetQuery(pg, "ALTER TABLE activist_director_equilar_new OWNER TO activism")

# Create BoardEx link table ----

be_cusips <-
    boardex.company_profile_stocks %>%
    # We end up inner_joining on CUSIP, so filter eliminates observations
    # that wont match in any case.
    filter(substr(isin, 1L, 2L)=='US') %>%
    mutate(cusip = substr(isin, 3L, 10L)) %>%
    select(boardid, cusip) %>%
    distinct() %>%
    compute()

be_directors <-
    boardex.director_characteristics %>%
    filter(row_type=='Board Member', !is.na(annual_report_date)) %>%
    select(boardid, annual_report_date, directorid, director_name) %>%
    rename(directorname = director_name) %>%
    inner_join(activist_director.director_names) %>%
    select(-prefix, -suffix)

boardex <-
    be_directors %>%
    inner_join(be_cusips, by = "boardid") %>%
    inner_join(permnos, by = "cusip")

first_name_years <-
    boardex %>%
    group_by(boardid, directorid) %>%
    summarize(annual_report_date = min(annual_report_date))

boardex_final <-
    first_name_years %>%
    inner_join(boardex, by = c("boardid", "directorid", "annual_report_date")) %>%
    select(boardid, directorid, annual_report_date,
           last_name, first_name, permno, permco) %>%
    mutate(first_name_l = lower(first_name),
           last_name_l = lower(last_name)) %>%
    mutate(first1 = substr(first_name_l, 1L, 1L),
           first2 = substr(first_name_l, 1L, 2L)) %>%
    select(-first_name, -last_name) %>%
    distinct() %>%
    compute()

match_1 <-
    activist_directors %>%
    inner_join(boardex_final, by=c("permco", "last_name_l", "first_name_l")) %>%
    select(campaign_id, first_name, last_name, boardid, directorid) %>%
    compute()

match_2 <-
    activist_directors %>%
    inner_join(boardex_final, by=c("permco", "last_name_l", "first2")) %>%
    select(campaign_id, first_name, last_name, boardid, directorid)

match_3 <-
    activist_directors %>%
    inner_join(boardex_final, by=c("permco", "last_name_l", "first1")) %>%
    select(campaign_id, first_name, last_name, boardid, directorid)

match_4 <-
    activist_directors %>%
    inner_join(boardex_final, by=c("permco", "last_name_l")) %>%
    select(campaign_id, first_name, last_name, boardid, directorid)

match_a <-
    match_1 %>%
    union(match_2 %>%
              anti_join(match_1,
                        by=c("campaign_id", "first_name", "last_name")))
match_b <-
    match_a %>%
    union(match_3 %>%
              anti_join(match_a,
                        by=c("campaign_id", "first_name", "last_name"))) %>%
    compute()

dbGetQuery(pg, "DROP TABLE IF EXISTS activist_director_boardex_new")

activist_director_equilar <-
    match_a %>%
    union(match_4 %>%
              anti_join(match_a,
                        by=c("campaign_id", "first_name", "last_name"))) %>%
    compute(name = "activist_director_boardex_new", temporary=FALSE)

dbGetQuery(pg, "COMMENT ON TABLE activist_director_boardex_new IS
                'CREATED USING activist_director_boardex_dplyr.R'")

dbGetQuery(pg, "ALTER TABLE activist_director_boardex_new OWNER TO activism")
# boardex.board_characteristics isn't doing anything
