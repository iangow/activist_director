# Get data from database ----
library("RPostgreSQL")
pg <- dbConnect(PostgreSQL())

# Create View "activist_director.director_votes" to take care of contested elections and create lead/lag votes ----
rs <- dbGetQuery(pg, "
    DROP VIEW IF EXISTS activist_director.director_votes;

    CREATE VIEW activist_director.director_votes AS

    -- IDENTIFY THE ONES THAT REQUIRE HAND-MATCHING
    -- Get all votes on directors that were not withdrawn and which have meaningful vote data
    WITH vavoteresults AS (
    SELECT a.*, issrec,
    (risk.extract_name(itemdesc)).last_name,
    (risk.extract_name(itemdesc)).first_name,
    dense_rank() over
    (ORDER BY a.companyid, a.meetingid, ballotitemnumber,
    (risk.extract_name(itemdesc)).last_name,
    (risk.extract_name(itemdesc)).first_name) AS id
    FROM risk.vavoteresults AS a
    LEFT JOIN risk.issrec AS b
    ON a.companyid=b.companyid AND a.meetingid=b.meetingid AND a.meetingdate=b.meetingdate AND a.recorddate=b.recorddate
    AND a.issagendaitemid=b.issagendaitemid AND a.itemonagendaid=b.itemonagendaid
    WHERE a.issagendaitemid IN ('S0299', 'M0299', 'M0201', 'S0201', 'M0225')
    AND itemdesc ~ '^Elect' AND voteresult != 'Withdrawn'
    AND NOT agendageneraldesc ilike '%inactive%'
    AND NOT (votedfor IN (0,1) OR
    greatest(votedagainst, votedabstain, votedwithheld) IN (0,1))),

    -- When there are multiple items (i.e., in contested elections), we need to
    -- aggregate votes by ballotitem number to get all votes cast for the
    -- competing directors
    multiple_items AS (
    SELECT companyid, meetingid, ballotitemnumber,
    sum(votedfor + votedagainst + votedabstain) AS votes_cast
    FROM vavoteresults
    WHERE issagendaitemid IN ('M0299','S0299')
    GROUP BY companyid, meetingid, ballotitemnumber
    HAVING count(DISTINCT itemdesc)>1),

    -- Otherwise we just add up votes for the director.
    -- Sometimes the votedagainst number is duplicated as votewithheld, so we
    -- want to just take the one number in these cases. Otherwise, I think
    -- we should include for, against, withheld, and abstain in the denominator.
    single_items AS (
    SELECT companyid, meetingid, ballotitemnumber, last_name, first_name, id,
    votedfor + CASE WHEN votedwithheld=votedagainst THEN votedagainst
    ELSE COALESCE(votedagainst, 0) + COALESCE(votedwithheld, 0)
    END + COALESCE(votedabstain, 0) AS votes_cast
    FROM vavoteresults),

    -- Combine the two mutually exclusive datasets
    votes_cast AS (
    SELECT a.companyid, a.meetingid, a.ballotitemnumber,
    a.last_name, a.first_name, a.id, a.issrec,
    COALESCE(b.votes_cast, c.votes_cast) AS votes_cast,
    b.votes_cast IS NOT NULL AS contested
    FROM vavoteresults AS a
    LEFT JOIN multiple_items AS b
    ON a.companyid=b.companyid AND a.meetingid=b.meetingid AND a.ballotitemnumber=b.ballotitemnumber
    LEFT JOIN single_items AS c
    ON a.id=c.id),

    -- Calculate vote_pct
    director_votes AS (
    SELECT DISTINCT a.*, c.permno, b.votes_cast, b.contested,
    CASE WHEN votes_cast > 0 THEN votedfor/votes_cast END AS vote_pct,
    CASE WHEN votes_cast > 0 THEN votedfor/votes_cast END AS vote_for_pct
    FROM vavoteresults AS a
    INNER JOIN votes_cast AS b
    USING (id)
    LEFT JOIN activist_director.permnos AS c
    ON substr(a.cusip, 1, 8)=c.ncusip
    ORDER BY a.companyid, a.meetingid, a.ballotitemnumber),

    issvoting AS (
    SELECT DISTINCT permno, companyid, name, extract(year from meetingdate) as year,
    meetingdate, last_name, first_name,
    substr(first_name,1,3) AS initial3,
    substr(first_name,1,2) AS initial2,
    substr(first_name,1,1) AS initial,
    mgmtrec, base, vote_pct, votes_cast, issrec, contested
    FROM director_votes
    ORDER BY permno, meetingdate, last_name, first_name),

    issvoting_year AS (
    SELECT DISTINCT year
    FROM issvoting
    ORDER BY year),

    issvoting_min_max_year AS (
    SELECT DISTINCT permno, min(year) AS min_year, max(year) AS max_year
    FROM issvoting
    GROUP BY permno
    ORDER BY permno),

    issvoting_firm_name AS (
    SELECT DISTINCT permno, last_name, first_name
    FROM issvoting
    ORDER BY permno, last_name, first_name),

    issvoting_firm_name_year AS (
    SELECT DISTINCT a.permno, a.last_name, a.first_name, b.year
    FROM issvoting_firm_name AS a, issvoting_year AS b
    ORDER BY permno, last_name, first_name, year),

    issvoting_firm_year_meetingdate AS (
    SELECT DISTINCT permno, year, meetingdate
    FROM issvoting
    ORDER BY permno, year, meetingdate),

    issvoting_detailed AS (
    SELECT DISTINCT a.*, c.meetingdate, b.vote_pct, b.votes_cast, b.contested,
    CASE WHEN b.issrec='For' THEN 'For'
    WHEN b.issrec IN ('Withhold', 'Against', 'Do Not Vote', 'Refer', 'Abstain', 'None') THEN 'Against' END AS issrec
    FROM issvoting_firm_name_year AS a
    INNER JOIN issvoting_min_max_year AS d
    ON a.permno=d.permno AND a.year BETWEEN d.min_year AND d.max_year
    LEFT JOIN issvoting_firm_year_meetingdate AS c
    ON a.permno=c.permno AND a.year=c.year
    LEFT JOIN issvoting AS b
    ON a.permno=b.permno AND a.last_name=b.last_name AND a.first_name=b.first_name AND c.meetingdate=b.meetingdate
    ORDER BY permno, last_name, first_name, year, meetingdate),

    issvoting_lead_lag AS (
    SELECT DISTINCT permno, last_name, first_name, year,
    lag(meetingdate,3) over w AS meetingdate_m3,
    lag(meetingdate,2) over w AS meetingdate_m2,
    lag(meetingdate,1) over w AS meetingdate_m1,
    meetingdate,
    lead(meetingdate,1) over w AS meetingdate_p1,
    lead(meetingdate,2) over w AS meetingdate_p2,
    lag(issrec,3) over w AS issrec_m3,
    lag(issrec,2) over w AS issrec_m2,
    lag(issrec,1) over w AS issrec_m1,
    issrec,
    lead(issrec,1) over w AS issrec_p1,
    lead(issrec,2) over w AS issrec_p2,
    lag(vote_pct,3) over w AS vote_pct_m3,
    lag(vote_pct,2) over w AS vote_pct_m2,
    lag(vote_pct,1) over w AS vote_pct_m1,
    vote_pct,
    lead(vote_pct,1) over w AS vote_pct_p1,
    lead(vote_pct,2) over w AS vote_pct_p2,
    lag(votes_cast,3) over w AS votes_cast_m3,
    lag(votes_cast,2) over w AS votes_cast_m2,
    lag(votes_cast,1) over w AS votes_cast_m1,
    votes_cast,
    lead(votes_cast,1) over w AS votes_cast_p1,
    lead(votes_cast,2) over w AS votes_cast_p2,
    lag(contested,3) over w AS contested_m3,
    lag(contested,2) over w AS contested_m2,
    lag(contested,1) over w AS contested_m1,
    contested,
    lead(contested,1) over w AS contested_p1,
    lead(contested,2) over w AS contested_p2
    FROM issvoting_detailed
    WINDOW w AS (PARTITION BY permno, last_name, first_name ORDER BY year, meetingdate)
    ORDER BY permno, last_name, first_name, year, meetingdate)

    SELECT * FROM issvoting_lead_lag;
")

# Matching activist directors with ISS Voting Analytics ----
vote.data <- dbGetQuery(pg, "
    WITH activist_director_matches AS (
        SELECT DISTINCT a.permno, a.last_name, a.first_name,
            a.meetingdate, a.vote_pct, a.issrec, a.contested,
            a.meetingdate_p1, a.vote_pct_p1, a.issrec_p1, a.contested_p1,
            a.meetingdate_p2, a.vote_pct_p2, a.issrec_p2, a.contested_p2,
            COALESCE(b.appointment_date, c.appointment_date, d.appointment_date, e.appointment_date) AS appointment_date,
            COALESCE(b.appointment_date, c.appointment_date, d.appointment_date, e.appointment_date) IS NOT NULL AS activist_director,
            COALESCE(b.independent, c.independent, d.independent, e.independent) IS FALSE AS affiliated_director
        FROM activist_director.director_votes AS a
        LEFT JOIN activist_director.activist_directors AS b
        ON a.permno=b.permno AND a.last_name ILIKE b.last_name AND substr(a.first_name,1,3) ILIKE substr(b.first_name,1,3)
        LEFT JOIN activist_director.activist_directors AS c
        ON a.permno=c.permno AND a.last_name ILIKE c.last_name AND substr(a.first_name,1,2) ILIKE substr(c.first_name,1,2)
        LEFT JOIN activist_director.activist_directors AS d
        ON a.permno=d.permno AND a.last_name ILIKE d.last_name AND substr(a.first_name,1,1) ILIKE substr(d.first_name,1,1)
        LEFT JOIN activist_director.activist_directors AS e
        ON a.permno=e.permno AND a.last_name ILIKE e.last_name
        WHERE a.last_name IS NOT NULL AND a.first_name IS NOT NULL
        ORDER BY permno, last_name, first_name, meetingdate),

    activist_director_years AS (
        SELECT DISTINCT permno, meetingdate
        FROM activist_director_matches
        WHERE activist_director AND vote_pct IS NOT NULL
        AND meetingdate > appointment_date - interval '1 week'
        ORDER BY permno, meetingdate),

    first_election_dates AS (
        SELECT DISTINCT permno, last_name, first_name, min(meetingdate) AS first_election_date
        FROM activist_director_matches
        WHERE activist_director AND vote_pct IS NOT NULL
        AND meetingdate BETWEEN appointment_date - INTERVAL '1 week' AND appointment_date + INTERVAL '3 years'
        GROUP BY permno, last_name, first_name
        ORDER BY permno, last_name, first_name),

    any_first_election_dates AS (
        SELECT DISTINCT permno, first_election_date AS any_first_election_date
        FROM first_election_dates
        ORDER BY permno, any_first_election_date),

    director_votes AS (
        SELECT DISTINCT a.*,
            c.first_election_date IS NOT NULL AS first_election,
            d.any_first_election_date IS NOT NULL AS any_first_election
        FROM activist_director_matches AS a
        INNER JOIN activist_director_years AS b
        USING (permno, meetingdate)
        LEFT JOIN first_election_dates AS c
        ON a.permno=c.permno AND a.last_name=c.last_name AND a.first_name=c.first_name AND a.meetingdate=c.first_election_date
        LEFT JOIN any_first_election_dates AS d
        ON a.permno=d.permno AND a.meetingdate=d.any_first_election_date
        ORDER BY permno, last_name, first_name, meetingdate)

        SELECT DISTINCT *
        FROM director_votes
        WHERE any_first_election
")

## Create permno_meetingdate variable
vote.data$permno_meetingdate <- paste(vote.data$permno, " & ", vote.data$meetingdate, sep="")

dbDisconnect(pg)

# Functions
library(psych)
require(texreg)
library(car)
library(doBy)
source("https://raw.githubusercontent.com/iangow/acct_data/master/code/cluster2.R")

### Summary Tables----
summaryBy(vote_pct ~ activist_director + affiliated_director,
          data=subset(vote.data, !is.na(vote_pct)),
          FUN=function(x) { c( mean = mean(x), median = median(x), sd = sd(x), N = length(x)) })

summaryBy(vote_pct_p1 ~ activist_director + affiliated_director,
          data=subset(vote.data, !is.na(vote_pct_p1)),
          FUN=function(x) { c( mean = mean(x), median = median(x), sd = sd(x), N = length(x)) })

summaryBy(vote_pct_p2 ~ activist_director + affiliated_director,
          data=subset(vote.data, !is.na(vote_pct_p2)),
          FUN=function(x) { c( mean = mean(x), median = median(x), sd = sd(x), N = length(x)) })

### Regression Analyses----

#### voting_p1 ~ activism
reg.data <- subset(vote.data)

fm.t1.pa.c0 <- lm(vote_pct * 100 ~ activist_director * affiliated_director + factor(permno_meetingdate),
                  data=reg.data, na.action="na.exclude")
fm.t1.pa.c0.se <- coeftest.cluster(reg.data, fm.t1.pa.c1, cluster1="permno")

#### voting_p1 ~ activism (activist_director firms only)
## reg.data <- subset(vote.data, activist_director_period)

fm.t1.pa.c1 <- lm(vote_pct * 100 ~ activist_director * affiliated_director + issrec + factor(permno_meetingdate),
                  data=reg.data, na.action="na.exclude")
fm.t1.pa.c1.se <- coeftest.cluster(reg.data, fm.t1.pa.c1, cluster1="permno")

fm.t1.pa.c2 <- lm(vote_pct * 100 ~ activist_director * affiliated_director * contested + factor(permno_meetingdate),
                  data=reg.data, na.action="na.exclude")
fm.t1.pa.c2.se <- coeftest.cluster(reg.data, fm.t1.pa.c2, cluster1="permno")

fm.t1.pa.c3 <- lm(vote_pct_p1 * 100 ~ activist_director * affiliated_director + factor(permno_meetingdate),
                  data=reg.data, na.action="na.exclude")
fm.t1.pa.c3.se <- coeftest.cluster(reg.data, fm.t1.pa.c3, cluster1="permno")

fm.t1.pa.c4 <- lm(vote_pct_p1 * 100 ~ activist_director * affiliated_director * contested_p1 + factor(permno_meetingdate),
                  data=reg.data, na.action="na.exclude")
fm.t1.pa.c4.se <- coeftest.cluster(reg.data, fm.t1.pa.c4, cluster1="permno")

fm.t1.pa.c5 <- lm(vote_pct_p2 * 100 ~ activist_director * affiliated_director + factor(permno_meetingdate),
                  data=reg.data, na.action="na.exclude")
fm.t1.pa.c5.se <- coeftest.cluster(reg.data, fm.t1.pa.c5, cluster1="permno")

fm.t1.pa.c6 <- lm(vote_pct_p2 * 100 ~ activist_director * affiliated_director * contested_p2 + factor(permno_meetingdate),
                  data=reg.data, na.action="na.exclude")
fm.t1.pa.c6.se <- coeftest.cluster(reg.data, fm.t1.pa.c6, cluster1="permno")

# Produce Excel file with results for prob_activism
screenreg(list(fm.t1.pa.c0, fm.t1.pa.c1, fm.t1.pa.c2, fm.t1.pa.c3, fm.t1.pa.c4, fm.t1.pa.c5, fm.t1.pa.c6),
        # file = "tables/voting_analysis.docx",
        caption = "Voting support for activist directors",
        caption.above = TRUE,
        digits = 3,
        stars = c(0.01, 0.05, 0.1),
        omit.coef = "(permno_meetingdate)",
        custom.model.names = c("% Voting Support","% Voting Support","% Voting Support","% Voting Support_t+1","% Voting Support_t+1","% Voting Support_t+2","% Voting Support_t+2"),
        # custom.coef.names = c("Intercept","Activist Director","Affiliated Director","Vote_Pct"),
        override.se = list(fm.t1.pa.c0.se[,2], fm.t1.pa.c1.se[,2], fm.t1.pa.c2.se[,2], fm.t1.pa.c3.se[,2], fm.t1.pa.c4.se[,2], fm.t1.pa.c5.se[,2], fm.t1.pa.c6.se[,2]),
        override.pval = list(fm.t1.pa.c0.se[,4], fm.t1.pa.c1.se[,4], fm.t1.pa.c2.se[,4], fm.t1.pa.c3.se[,4], fm.t1.pa.c4.se[,4], fm.t1.pa.c5.se[,4], fm.t1.pa.c6.se[,4]))
