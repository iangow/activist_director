# Get data from database ----
library(RPostgreSQL)
library(dplyr, warn.conflicts = FALSE)
pg <- dbConnect(PostgreSQL())

rs <- dbExecute(pg, "SET search_path TO activist_director, risk")

permnos <- tbl(pg, "permnos")
risk.vavoteresults <- tbl(pg, "vavoteresults")
activist_directors <- tbl(pg, "activist_directors")
vavoteresults <-
    risk.vavoteresults %>%
    filter(issagendaitemid %in% c('S0299', 'M0299', 'M0201', 'S0201', 'M0225'),
           itemdesc %~% '^Elect',
           voteresult != 'Withdrawn',
           !(agendageneraldesc %ilike% '%inactive%'),
           !(votedfor %in% c(0L,1L) |
                 greatest(votedagainst, votedabstain, votedwithheld) %in% c(0L, 1L))) %>%
    mutate(last_name = sql("(extract_name(itemdesc)).last_name"),
           first_name = sql("(extract_name(itemdesc)).first_name")) %>%
    compute()

# When there are multiple items (i.e., in contested elections), we need to
# aggregate votes by ballotitem number to get all votes cast for the
# competing directors
multiple_items <-
    vavoteresults %>%
    filter(issagendaitemid %in% c('M0299','S0299')) %>%
    group_by(companyid, meetingid, ballotitemnumber) %>%
    summarise(votes_cast = sum(votedfor + votedagainst + votedabstain, na.rm = TRUE),
              num_items = n_distinct(itemdesc)) %>%
    filter(num_items > 1) %>%
    select(-num_items) %>%
    compute()

# Otherwise we just add up votes for the director.
# Sometimes the votedagainst number is duplicated as votewithheld, so we
# want to just take the one number in these cases. Otherwise, I think
# we should include for, against, withheld, and abstain in the denominator.
single_items <-
    vavoteresults %>%
    mutate(votes_cast = votedfor +
               if_else(votedwithheld==votedagainst, votedagainst,
                       coalesce(votedagainst, 0) + coalesce(votedwithheld, 0)) +
               coalesce(votedabstain, 0)) %>%
    select(companyid, meetingid, ballotitemnumber, votes_cast) %>%
    filter(!is.na(votes_cast)) %>%
    compute()

# Combine the two mutually exclusive datasets
votes_cast <-
    multiple_items %>%
    union(single_items)

# Calculate vote_pct
director_votes <-
    vavoteresults %>%
    inner_join(votes_cast, by = c("companyid", "meetingid", "ballotitemnumber")) %>%
    mutate(vote_pct = if_else(votes_cast > 0, votedfor/votes_cast, NA_real_),
           vote_for_pct = if_else(votes_cast > 0, votedfor/votes_cast, NA_real_)) %>%
    mutate(ncusip = substr(cusip, 1L, 8L)) %>%
    left_join(permnos, by = "ncusip") %>%
    select(-ncusip)

issvoting <-
    director_votes %>%
    select(permno, companyid, name, meetingdate, last_name,
           first_name, mgmtrec, base, vote_pct, votes_cast) %>%
    mutate(year = as.integer(date_part('year', meetingdate)),
           initial3 = substr(first_name, 1L, 3L),
           initial2 = substr(first_name, 1L, 2L),
           initial  = substr(first_name, 1L, 1L)) %>%
    compute()

issvoting_year <-
    issvoting %>%
    select(year) %>%
    distinct() %>%
    compute()

issvoting_min_max_year <-
    issvoting %>%
    group_by(permno) %>%
    summarize(min_year = min(year, na.rm = TRUE),
              max_year = max(year, na.rm = TRUE)) %>%
    compute()

issvoting_firm_name <-
    issvoting %>%
    select(permno, last_name, first_name) %>%
    distinct() %>%
    compute()

issvoting_firm_name_year <-
    issvoting_firm_name %>%
    mutate(join = TRUE) %>%
    inner_join(issvoting_year %>% mutate(join = TRUE)) %>%
    select(-join) %>%
    compute()

issvoting_firm_year_meetingdate <-
    issvoting %>%
    select(permno, year, meetingdate) %>%
    filter(!is.na(permno)) %>%
    distinct()

issvoting_detailed <-
    issvoting_firm_name_year %>%
    inner_join(issvoting_min_max_year, by = "permno") %>%
    filter(between(year, min_year, max_year)) %>%
    left_join(issvoting_firm_year_meetingdate, by = c("permno", "year")) %>%
    left_join(issvoting,
              by = c("permno", "last_name", "first_name", "year", "meetingdate"))

#
director_votes <-
    issvoting_detailed %>%
    select(permno, last_name, first_name, year, meetingdate, votes_cast, vote_pct) %>%
    group_by(permno, last_name, first_name) %>%
    arrange(year, meetingdate) %>%
    mutate(meetingdate_m3 = lag(meetingdate, 3L),
           meetingdate_m2 = lag(meetingdate, 2L),
           meetingdate_m1 = lag(meetingdate, 1L),
           meetingdate_p1  = lead(meetingdate, 1L),
           meetingdate_p2 = lead(meetingdate, 2L),
           vote_pct_m3 = lag(vote_pct, 3L),
           vote_pct_m2 = lag(vote_pct, 2L),
           vote_pct_m1 = lag(vote_pct, 1L),
           vote_pct_p1 = lead(vote_pct, 1L),
           vote_pct_p2 = lead(vote_pct, 2L),
           votes_cast_m3 = lag(votes_cast, 3L),
           votes_cast_m2 = lag(votes_cast, 2L),
           votes_cast_m1 = lag(votes_cast, 1L),
           votes_cast_p1 = lead(votes_cast, 1L),
           votes_cast_p2 = lead(votes_cast, 2L)) %>%
    ungroup()



activist_director_names <-
    activist_directors  %>%
    select(permno, last_name, first_name, appointment_date, independent) %>%
    mutate(lname = upper(last_name),
           fname = upper(first_name),
           initial3 = substr(fname, 1L, 3L),
           initial2 = substr(fname, 1L, 2L),
           initial  = substr(fname, 1L, 1L))

director_names <-
    director_votes %>%
    select(permno, last_name, first_name) %>%
    distinct() %>%
    mutate(lname = upper(last_name),
           fname = upper(first_name),
           initial3 = substr(fname, 1L, 3L),
           initial2 = substr(fname, 1L, 2L),
           initial  = substr(fname, 1L, 1L))

match1 <-
    director_names %>%
    inner_join(
        activist_director_names %>%
            select(permno, lname, initial3, appointment_date, independent)) %>%
    select(permno, last_name, first_name, appointment_date, independent)

match2 <-
    director_names %>%
    anti_join(match1, by= c("permno", "last_name", "first_name")) %>%
    inner_join(
        activist_director_names %>%
            select(permno, lname, initial2, appointment_date, independent)) %>%
    select(permno, last_name, first_name, appointment_date, independent)

if (pull(count(match2))>0) {
    matchA <-
        match1 %>%
        union_all(match2)
} else {
    matchA <- match1
}

match3 <-
    director_names %>%
    anti_join(matchA, by= c("permno", "last_name", "first_name")) %>%
    inner_join(
        activist_director_names %>%
            select(permno, lname, initial, appointment_date, independent)) %>%
    select(permno, last_name, first_name, appointment_date, independent)

if (pull(count(match3))>0) {
    matchB <-
        matchA %>%
        union_all(match3)
} else {
    matchB <- matchA
}

match4 <-
    director_names %>%
    anti_join(matchB, by= c("permno", "last_name", "first_name")) %>%
    inner_join(
        activist_director_names %>%
            select(permno, lname, appointment_date, independent)) %>%
    select(permno, last_name, first_name, appointment_date, independent)

if (pull(count(match4))>0) {
    final_match <-
        matchB %>%
        union_all(match4)
} else {
    final_match <- matchB
}

activist_director_matches <-
    director_votes %>%
    select(permno, last_name, first_name, meetingdate,
           vote_pct, meetingdate_p1, vote_pct_p1, meetingdate_p2, vote_pct_p2) %>%
    left_join(final_match) %>%
    mutate(activist_director = !is.na(appointment_date)) %>%
    compute()

activist_director_years <-
    activist_director_matches %>%
    filter(activist_director, !is.na(vote_pct),
           meetingdate > appointment_date) %>%
    select(permno, meetingdate) %>%
    distinct() %>%
    compute()

first_election_dates <-
    activist_director_matches %>%
    filter(activist_director, !is.na(vote_pct)) %>%
    filter(between(meetingdate,
                   sql("appointment_date + INTERVAL '1 day'"),
                   sql("appointment_date + INTERVAL '3 years'"))) %>%
    group_by(permno, last_name, first_name) %>%
    summarize(first_election_date =  min(meetingdate, na.rm = TRUE)) %>%
    ungroup()

any_first_election_dates <-
    first_election_dates %>%
    select(permno, first_election_date) %>%
    distinct() %>%
    rename(any_first_election_date = first_election_date)

vote.data <-
    activist_director_matches %>%
    inner_join(activist_director_years, by = c("permno", "meetingdate")) %>%
    left_join(first_election_dates %>% mutate(meetingdate = first_election_date)) %>%
    left_join(any_first_election_dates %>% mutate(meetingdate = any_first_election_date)) %>%
    mutate(first_election = !is.na(first_election_date),
           any_first_election = !is.na(any_first_election_date)) %>%
    select(-first_election_date, -any_first_election_date) %>%
    filter(any_first_election) %>%
    collect() %>%
    mutate(permno_meetingdate = paste0(permno, "_", meetingdate))

# Get voting changes data from PostgreSQL ----

## Create permno_meetingdate variable

dbDisconnect(pg)

# Functions
library(psych)
require(texreg)
library(car)
library(doBy)
source("https://raw.githubusercontent.com/iangow/acct_data/master/code/cluster2.R")

### Summary Tables----
vote.data %>%
    filter(!is.na(vote_pct)) %>%
    group_by(activist_director, independent) %>%
    summarize_at(vars(vote_pct), funs(mean, median, sd, length))

### Regression Analyses----

#### voting_p1 ~ activism
reg.data <- subset(vote.data)

fm.t1.pa.c1 <- lm(vote_pct * 100 ~ activist_director * affiliated_director,
                  data=reg.data, na.action="na.exclude")
fm.t1.pa.c1.se <- coeftest.cluster(reg.data, fm.t1.pa.c1, cluster1="permno")

#### voting_p1 ~ activism (activist_director firms only)
## reg.data <- subset(vote.data, activist_director_period)

fm.t1.pa.c2 <- lm(vote_pct * 100 ~ activist_director * affiliated_director + factor(permno_meetingdate),
                  data=reg.data, na.action="na.exclude")
fm.t1.pa.c2.se <- coeftest.cluster(reg.data, fm.t1.pa.c2, cluster1="permno")

fm.t1.pa.c3 <- lm(vote_pct_p1 * 100 ~ activist_director * affiliated_director + factor(permno_meetingdate),
                  data=reg.data, na.action="na.exclude")
fm.t1.pa.c3.se <- coeftest.cluster(reg.data, fm.t1.pa.c3, cluster1="permno")

fm.t1.pa.c4 <- lm(vote_pct_p2 * 100 ~ activist_director * affiliated_director + factor(permno_meetingdate),
                  data=reg.data, na.action="na.exclude")
fm.t1.pa.c4.se <- coeftest.cluster(reg.data, fm.t1.pa.c4, cluster1="permno")

fm.t1.pa.c5 <- lm(vote_pct_p1 * 100 ~ activist_director * affiliated_director + vote_pct + factor(permno_meetingdate),
                  data=reg.data, na.action="na.exclude")
fm.t1.pa.c5.se <- coeftest.cluster(reg.data, fm.t1.pa.c5, cluster1="permno")

fm.t1.pa.c6 <- lm(vote_pct_p2 * 100 ~ activist_director * affiliated_director + vote_pct + factor(permno_meetingdate),
                  data=reg.data, na.action="na.exclude")
fm.t1.pa.c6.se <- coeftest.cluster(reg.data, fm.t1.pa.c6, cluster1="permno")

# Produce Excel file with results for prob_activism
screenreg(list(fm.t1.pa.c1, fm.t1.pa.c2, fm.t1.pa.c3, fm.t1.pa.c4, fm.t1.pa.c5, fm.t1.pa.c6),
        # file = "tables/voting_analysis.docx",
        caption = "Voting support for activist directors",
        caption.above = TRUE,
        digits = 3,
        stars = c(0.01, 0.05, 0.1),
        omit.coef = "(permno_meetingdate)",
        custom.model.names = c("% Voting Support","% Voting Support","% Voting Support_t+1","% Voting Support_t+2","% Voting Support_t+1","% Voting Support_t+2"),
        custom.coef.names = c("Intercept","Activist Director","Affiliated Director","Vote_Pct"),
        override.se = list(fm.t1.pa.c1.se[,2], fm.t1.pa.c2.se[,2], fm.t1.pa.c3.se[,2], fm.t1.pa.c4.se[,2], fm.t1.pa.c5.se[,2], fm.t1.pa.c6.se[,2]),
        override.pval = list(fm.t1.pa.c1.se[,4], fm.t1.pa.c2.se[,4], fm.t1.pa.c3.se[,4], fm.t1.pa.c4.se[,4], fm.t1.pa.c5.se[,4], fm.t1.pa.c6.se[,4]))
