library(RPostgreSQL)
library(dplyr, warn.conflicts = FALSE)
pg <- dbConnect(PostgreSQL())

rs <- dbExecute(pg, "SET search_path TO boardex")
rs <- dbExecute(pg, "SET work_mem='10GB'")

director_names <- tbl(pg, sql("SELECT * FROM activist_director.director_names"))
permnos <- tbl(pg, sql("SELECT * FROM activist_director.permnos"))
activism_events <- tbl(pg, sql("SELECT * FROM activist_director.activism_events"))
activist_director_boardex <- tbl(pg, sql("SELECT * FROM activist_director.activist_director_boardex"))

board_and_director_committees <- tbl(pg, "board_and_director_committees")
director_characteristics <- tbl(pg, "director_characteristics")
director_profile_details <- tbl(pg, "director_profile_details")
company_profile_stocks <- tbl(pg, "company_profile_stocks")

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

# CREATE TABLE activist_director.boardex_w_activism AS

# Pull together director characteristics
link_table <-
    company_profile_stocks %>%
    filter(substr(isin, 1L, 2L)=='US') %>%
    mutate(cusip = substr(isin, 3L, 10L)) %>%
    select(boardid, cusip) %>%
    distinct() %>%
    compute()

# Some duplicates here!
link_table %>%
    group_by(cusip) %>%
    filter(n() > 1) %>%
    inner_join(company_profile_stocks) %>%
    arrange(cusip) %>%
    compute()

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
    inner_join(link_table, by = "boardid") %>%
    inner_join(names, by = "director_name") %>%
    left_join(committees, by = c("directorid", "boardid", "annual_report_date")) %>%
    left_join(ages, by = c("directorid", "boardid", "annual_report_date")) %>%
    compute()

boardex_permnos <-
    boardex %>%
    inner_join(permnos %>% rename(cusip = ncusip),
               by = "cusip") %>%
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
    inner_join(boardex_permnos, by = c("boardid", "directorid", "annual_report_date")) %>%
    inner_join(activism_events, by = "permno") %>%
    filter(between(annual_report_date, eff_announce_date, end_date + sql("interval '128 days'"))) %>%
    group_by(boardid, directorid, annual_report_date) %>%
    summarize(sharkwatch50 = bool_or(sharkwatch50),
              activism_firm = bool_or(activism),
              activist_demand_firm = bool_or(activist_demand),
              activist_director_firm  = bool_or(activist_director)) %>%
    compute()
# Now pull all directors from boardex and add data on activism from above
ad_boardex <-
    activist_director_boardex %>%
    select(boardid, directorid, annual_report_date, activist_affiliate) %>%
    mutate(activist_director = !is.na(directorid)) %>%
    rename(affiliated_director = activist_affiliate)

rs <- dbExecute(pg, "SET search_path TO activist_director")
rs <- dbExecute(pg, "BEGIN")
rs <- dbExecute(pg, "DROP TABLE IF EXISTS boardex_w_activism")
boardex_permnos %>%
    left_join(company_first_years, by = c("boardid", "annual_report_date")) %>%
    left_join(director_first_years, by = c("directorid", "boardid", "annual_report_date")) %>%
    left_join(boardex_activism_match, by = c("directorid", "boardid", "annual_report_date")) %>%
    left_join(ad_boardex, by = c("directorid", "boardid", "annual_report_date")) %>%
    mutate(firm_first_year = coalesce(firm_first_year, FALSE),
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
