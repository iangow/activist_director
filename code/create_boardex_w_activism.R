library(RPostgreSQL)
library(dplyr, warn.conflicts = FALSE)
pg <- dbConnect(PostgreSQL())

rs <- dbExecute(pg, "SET work_mem='10GB'")

# BoardEx tables
rs <- dbExecute(pg, "SET search_path TO activist_director, boardex")
board_and_director_committees <- tbl(pg, "board_and_director_committees")
director_characteristics <- tbl(pg, "director_characteristics")
director_profile_details <- tbl(pg, "director_profile_details")
company_profile_stocks <- tbl(pg, "company_profile_stocks")

# Activist Director tables
director_names <- tbl(pg, "director_names")
permnos <- tbl(pg, "permnos")
activism_events <- tbl(pg, "activism_events")
activist_directors <- tbl(pg, "activist_directors")

# Create link table ----
be_permnos <-
    company_profile_stocks %>%
    # We end up inner_joining on CUSIP, so filter eliminates
    # observations that won't match in any case.
    filter(substr(isin, 1L, 2L)=='US') %>%
    mutate(cusip = substr(isin, 3L, 10L)) %>%
    select(boardid, cusip) %>%
    distinct() %>%
    inner_join(permnos %>% rename(cusip = ncusip), by = "cusip") %>%
    select(boardid, permno) %>%
    compute()

be_directors <-
    director_characteristics %>%
    filter(row_type=='Board Member', !is.na(annual_report_date)) %>%
    select(boardid, annual_report_date, directorid, director_name) %>%
    rename(directorname = director_name) %>%
    inner_join(director_names) %>%
    select(-prefix, -suffix)

be_directors_linked <-
    be_directors %>%
    inner_join(be_permnos, by = "boardid") %>%
    compute()

first_name_years <-
    be_directors_linked %>%
    group_by(boardid, directorid) %>%
    summarize(annual_report_date = min(annual_report_date)) %>%
    compute()

boardex_final <-
    first_name_years %>%
    inner_join(be_directors_linked, by = c("boardid", "directorid", "annual_report_date")) %>%
    select(boardid, directorid, annual_report_date,
           last_name, first_name, permno) %>%
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
    inner_join(permnos) %>%
    compute()

match_1 <-
    activist_directors_mod %>%
    inner_join(boardex_final, by=c("permno", "last_name_l", "first_name_l")) %>%
    select(campaign_id, first_name, last_name, boardid, directorid) %>%
    compute()

match_2 <-
    activist_directors_mod %>%
    inner_join(boardex_final, by=c("permno", "last_name_l", "first2")) %>%
    select(campaign_id, first_name, last_name, boardid, directorid)

match_3 <-
    activist_directors_mod %>%
    inner_join(boardex_final, by=c("permno", "last_name_l", "first1")) %>%
    select(campaign_id, first_name, last_name, boardid, directorid)

match_4 <-
    activist_directors_mod %>%
    inner_join(boardex_final, by=c("permno", "last_name_l")) %>%
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

activist_director_boardex <-
    match_b %>%
    union(match_4 %>%
              anti_join(match_b,
                        by=c("campaign_id", "first_name", "last_name"))) %>%
    compute()

# Create components of boardex_w_activism ----
committees <-
    board_and_director_committees %>%
    filter(!is.na(annual_report_date)) %>%
    group_by(boardid, directorid, annual_report_date) %>%
    summarize(audit_committee = bool_or(committee_name %~*% 'audit'),
              comp_committee = bool_or(committee_name %~*% '(compensat|remunerat)'),
              nom_committee = bool_or(committee_name %~*% 'nominat')) %>%
    ungroup() %>%
    compute()

boardex_date <-
    director_profile_details %>%
    filter(is.na(dod)) %>%
    summarise(max= max(dob + make_interval(age))) %>%
    pull() %>%
    as.Date() %>%
    paste0("'", ., "'::date")

ages <-
    director_profile_details %>%
    select(directorid, dob, age) %>%
    inner_join(director_characteristics) %>%
    mutate(dob = coalesce(dob, sql(boardex_date) - make_interval(age))) %>%
    mutate(age = date_part('year', age(annual_report_date, dob))) %>%
    select(boardid, directorid, annual_report_date, age) %>%
    filter(!is.na(annual_report_date)) %>%
    distinct() %>% # Why do I need DISTINCT?
    compute()

# Pull together director characteristics
names <-
    director_names %>%
    rename(director_name = directorname) %>%
    select(director_name, first_name, last_name)

boardex <-
    director_characteristics %>%
    filter(row_type=='Board Member', !is.na(annual_report_date)) %>%
    mutate(female = gender=='F') %>%
    select(directorid, director_name, boardid, annual_report_date,
           time_retirement, time_role, time_brd, time_inco, avg_time_oth_co,
           tot_nolstd_brd, tot_noun_lstd_brd, tot_curr_nolstd_brd, tot_curr_noun_lstd_brd,
           female, no_quals) %>%
    left_join(committees, by = c("directorid", "boardid", "annual_report_date")) %>%
    left_join(ages, by = c("directorid", "boardid", "annual_report_date")) %>%
    compute()

# Identify companies' first years
company_first_years <-
    boardex %>%
    group_by(boardid) %>%
    summarize(annual_report_date = min(annual_report_date)) %>%
    mutate(firm_first_year = TRUE) %>%
    compute()

# Identify directors' first years
director_first_years <-
    boardex %>%
    group_by(boardid, directorid) %>%
    summarize(annual_report_date = min(annual_report_date)) %>%
    mutate(director_first_year = TRUE) %>%
    compute()

# Classify directors' first years on boardex based on whether
# they were appointed during an activism event or shortly thereafter
boardex_activism_match <-
    director_first_years %>%
    left_join(activist_director_boardex,
              by = c("boardid", "directorid")) %>%
    left_join(activism_events, by = "campaign_id") %>%
    filter(between(annual_report_date, eff_announce_date,
                   end_date + sql("interval '128 days'"))) %>%
    group_by(boardid, directorid, annual_report_date) %>%
    summarize(sharkwatch50 = bool_or(sharkwatch50),
              activism_firm = bool_or(activism),
              activist_demand_firm = bool_or(activist_demand),
              activist_director_firm  = bool_or(activist_director)) %>%
    ungroup() %>%
    compute()

ad_data <-
    boardex_activism_match %>%
    left_join(activist_director_boardex, by = c("directorid", "boardid")) %>%
    left_join(activist_directors, by = c("campaign_id", "first_name", "last_name")) %>%
    mutate(activist_director = !is.na(appointment_date),
           affiliated_director = !independent) %>%
    select(campaign_id, first_name, last_name,
           boardid, directorid, annual_report_date,
           sharkwatch50, activism_firm, activist_demand_firm,
           activist_director_firm, activist_director, affiliated_director) %>%
    compute()
# Now pull all directors from boardex and add data on activism from above

# Merge components of boardex_w_activism ----
rs <- dbExecute(pg, "BEGIN")
rs <- dbExecute(pg, "DROP TABLE IF EXISTS boardex_w_activism")

boardex %>%
    left_join(company_first_years, by = c("boardid", "annual_report_date")) %>%
    left_join(director_first_years,
              by = c("directorid", "boardid", "annual_report_date")) %>%
    left_join(boardex_activism_match,
              by = c("directorid", "boardid", "annual_report_date")) %>%
    left_join(activist_director_boardex, by = c("directorid", "boardid")) %>%
    left_join(activist_directors, by = c("campaign_id", "first_name", "last_name")) %>%
    mutate(activist_director = !is.na(appointment_date),
           affiliated_director = !independent,
           firm_first_year = coalesce(firm_first_year, FALSE),
           director_first_year = coalesce(director_first_year, FALSE),
           sharkwatch50 = coalesce(sharkwatch50, FALSE),
           activism_firm = coalesce(activism_firm, FALSE),
           activist_demand_firm = coalesce(activist_demand_firm, FALSE),
           activist_director_firm = coalesce(activist_director_firm, FALSE),
           activist_director = coalesce(activist_director, FALSE),
           affiliated_director = coalesce(affiliated_director, FALSE),
           category = case_when(activist_director_firm ~ "activist_director_firm",
                                activist_demand_firm ~ "activist_demand_firm",
                                activism_firm ~ "activism_firm",
                                TRUE ~ "_none")) %>%
    distinct() %>%
    compute(name = "boardex_w_activism", temporary = FALSE)
rs <- dbExecute(pg, "ALTER TABLE boardex_w_activism OWNER TO activism")
rs <- dbExecute(pg, "COMMIT")
# Query returned successfully: 516096 rows affected, 122490 ms execution time.

rs <- dbDisconnect(pg)
