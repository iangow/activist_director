library(RPostgreSQL)
library(dplyr, warn.conflicts = FALSE)
library(tidyverse)
pg <- dbConnect(PostgreSQL())

rs <- dbGetQuery(pg, "SET work_mem='8GB'")
rs <- dbGetQuery(pg, "SET search_path TO activist_director, equilar_hbs")

stocknames <- tbl(pg, sql("SELECT * FROM crsp.stocknames"))

activist_director_equilar <- tbl(pg, "activist_director_equilar") %>% collect()

equilar_w_activism <- tbl(pg, "equilar_w_activism")

# Bring in SIC code----
sics <-
    stocknames %>%
    select(permno, siccd, namedt, nameenddt) %>%
    mutate(siccd = substr(as.character(siccd), 1, 2)) %>%
    distinct() %>%
    arrange(permno, namedt) %>%
    collect()

# Match Equilar company_id with SIC code----
equilar_sics <-
    equilar_w_activism %>%
    inner_join(sics, by = "permno") %>%
    filter(period >= namedt, period <= nameenddt) %>%
    select(-permno, -namedt, -nameenddt) %>%
    distinct() %>%
    arrange(company_id, period) %>%
    collect()

# Very first year for each executive-company ID----
first_years <-
    equilar_sics %>%
    select(executive_id, company_id, siccd, date_start) %>%
    distinct() %>%
    arrange(executive_id, date_start)

# Create a dummy "same_sic2"----
prior_appts <-
    first_years %>%
    left_join(first_years, by = c("executive_id"),
               suffix = c("_own", "_other")) %>%
    filter(company_id_own != company_id_other,
           date_start_other < date_start_own) %>%
    distinct() %>%
    mutate(same_sic2 = siccd_own==siccd_other) %>%
    filter(date_start_own >= '2004-01-01') %>%
    select(company_id=company_id_own, executive_id, same_sic2) %>%
    group_by(executive_id, company_id) %>%
    summarize(prior_ind_exp = sum(same_sic2))

table(prior_appts$prior_ind_exp)

# Identify activist director cases using activist_director_equilar----
final <-
    prior_appts %>%
    left_join(activist_director_equilar) %>%
    mutate(activist_director=!is.na(independent),
           affiliated_director=ifelse(!activist_director,"_na",ifelse(!independent,"affiliated","unaffiliated"))) %>%
    select(company_id, executive_id, activist_director, affiliated_director, prior_ind_exp) %>%
    distinct()

final %>% group_by(activist_director) %>% summarise(mean(prior_ind_exp))

final %>% group_by(affiliated_director) %>% summarise(mean(prior_ind_exp))

table(final$prior_ind_exp, final$activist_director)

table(final$prior_ind_exp, final$affiliated_director)

t.test(subset(final,activist_director)$prior_ind_exp, subset(final,!activist_director)$prior_ind_exp)

t.test(subset(final,affiliated_director=="affiliated")$prior_ind_exp, subset(final,affiliated_director=="_na")$prior_ind_exp)

t.test(subset(final,affiliated_director=="unaffiliated")$prior_ind_exp, subset(final,affiliated_director=="_na")$prior_ind_exp)

t.test(subset(final,affiliated_director=="unaffiliated")$prior_ind_exp, subset(final,affiliated_director=="affiliated")$prior_ind_exp)
