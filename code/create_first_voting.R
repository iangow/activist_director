library(RPostgreSQL)
library(dplyr, warn.conflicts = FALSE)

pg <- dbConnect(PostgreSQL())

rs <- dbGetQuery(pg, "SET search_path='activist_director'")

rs <- dbGetQuery(pg, "SET work_mem='5GB'")

# Get all votes on directors that were not withdrawn and which have meaningful vote data
issvoting.compvote <- tbl(pg, sql("SELECT * FROM issvoting.compvote"))
factset.permnos <- tbl(pg, sql("SELECT * FROM factset.permnos"))
director_names <- tbl(pg, sql("SELECT * FROM issvoting.director_names"))

compvote <-
  issvoting.compvote %>%
  filter(issagendaitemid %in% c('S0299', 'M0299', 'M0201', 'S0201', 'M0225'),
         itemdesc %~% '^Elect',
         voteresult != 'Withdrawn',
   !(votedfor %in% c(0,1) |
         greatest(votedagainst, votedabstain, votedwithheld) %in% c(0,1))) %>%
    compute()

# When there are multiple items (i.e., in contested elections), we need to
# aggregate votes by ballotitem number to get all votes cast for the
# competing directors
multiple_items <-
  compvote %>%
  group_by(companyid, meetingid, ballotitemnumber) %>%
  summarize(votes_cast = sum(votedfor + votedagainst + votedabstain),
            num_items = sql("count(DISTINCT itemdesc)")) %>%
  filter(num_items > 1)

# Otherwise we just add up votes for the director.
# Sometimes the votedagainst number is duplicated as votewithheld, so we
# want to just take the one number in these cases. Otherwise, I think
# we should include for, against, withheld, and abstain in the denominator.
single_items <-
    compvote %>%
    mutate(votedagainst =
               if_else(votedwithheld==votedagainst, votedagainst,
                       coalesce(votedagainst, 0) +
                           coalesce(votedwithheld, 0))) %>%
    mutate(votedabstain = coalesce(votedabstain, 0)) %>%
    group_by(companyid, meetingid, ballotitemnumber) %>%
    summarize(votes_cast = sum(votedfor + votedagainst + votedabstain),
              num_items = sql("count(DISTINCT itemdesc)")) %>%
    filter(num_items == 1)

# Combine the two mutually exclusive datasets
votes_cast <-
    multiple_items %>%
    union(single_items) %>%
    select(-num_items) %>%
    compute()

# Calculate vote_pct
director_votes <-
    compvote %>%
    inner_join(votes_cast) %>%
    mutate(ncusip = substr(cusip, 1L, 8L)) %>%
    left_join(factset.permnos) %>%
    select(-ncusip) %>%
    mutate(vote_pct = if_else(votes_cast > 0, votedfor/votes_cast, NA)) %>%
    compute()

issvoting <-
    director_names %>%
    mutate(initial1 = substr(first_name, 1L, 3L),
           initial2 = substr(first_name, 1L, 2L),
           initial = substr(first_name, 1L, 1L)) %>%
    inner_join(director_votes, by="itemdesc") %>%
    mutate(year = date_part('year', meetingdate)) %>%
    select(permno, year, meetingdate, first_name, last_name,
           mgmtrec, issrec, base, vote_pct, votes_cast,
           matches("^initial")) %>%
    filter(vote_pct >= 0.5) %>%
    distinct() %>%
    compute()

first_meetingdate <-
    issvoting %>%
    group_by(permno, last_name, first_name) %>%
    summarize(meetingdate = min(meetingdate)) %>%
    compute()

rs <- dbGetQuery(pg, "DROP TABLE IF EXISTS first_voting;")

first_voting <-
	issvoting %>%
	select(permno, meetingdate, first_name, last_name, vote_pct, issrec) %>%
	inner_join(first_meetingdate) %>%
	compute(name = "first_voting", temporary = FALSE)

rs <- dbGetQuery(pg, "ALTER TABLE first_voting OWNER TO activism")

rs <- dbGetQuery(pg, "COMMENT ON TABLE activist_director.first_voting
  IS 'CREATED USING first_voting.R'")
