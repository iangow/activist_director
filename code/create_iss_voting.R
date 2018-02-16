library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

rs <-dbGetQuery(pg, "

SET work_mem = '15GB';

DROP TABLE IF EXISTS activist_director.iss_voting CASCADE;

CREATE TABLE activist_director.iss_voting AS

-- Get all votes on directors that were not withdrawn and which have meaningful vote data
WITH compvote AS (
    SELECT *,
    (issvoting.extract_name(itemdesc)).last_name,
    (issvoting.extract_name(itemdesc)).first_name,
    dense_rank() over
    (ORDER BY companyid, meetingid, ballotitemnumber,
        (issvoting.extract_name(itemdesc)).last_name,
        (issvoting.extract_name(itemdesc)).first_name) AS id
    FROM issvoting.compvote
    WHERE issagendaitemid IN ('S0299', 'M0299', 'M0201', 'S0201', 'M0225')
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
    FROM compvote
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
    FROM compvote),

-- Combine the two mutually exclusive datasets
votes_cast AS (
    SELECT a.companyid, a.meetingid, a.ballotitemnumber,
    a.last_name, a.first_name, a.id,
    COALESCE(b.votes_cast, c.votes_cast) AS votes_cast
    FROM compvote AS a
    LEFT JOIN multiple_items AS b
    ON a.companyid=b.companyid AND a.meetingid=b.meetingid AND a.ballotitemnumber=b.ballotitemnumber
    LEFT JOIN single_items AS c
    ON a.id=c.id),

-- Calculate vote_pct
director_votes AS (
    SELECT DISTINCT a.*, c.permno, b.votes_cast,
    CASE WHEN votes_cast > 0 THEN votedfor/votes_cast END AS vote_pct,
    CASE WHEN votes_cast > 0 THEN votedfor/votes_cast END AS vote_for_pct
    FROM compvote AS a
    INNER JOIN votes_cast AS b
    USING (id)
    LEFT JOIN activist_director.permnos AS c
    ON substr(a.cusip, 1, 8)=c.ncusip
    ORDER BY a.companyid, a.meetingid, a.ballotitemnumber),

issvoting AS (
    SELECT DISTINCT permno, extract(year from meetingdate) as year,
    meetingdate, last_name, first_name,
    substr(first_name,1,3) AS initial3,
    substr(first_name,1,2) AS initial2,
    substr(first_name,1,1) AS initial,
    mgmtrec, issrec, base, vote_pct, votes_cast
    FROM director_votes
    ORDER BY permno, meetingdate, last_name, first_name),

equilar_simplified AS (
    SELECT DISTINCT permno, executive_id, last_name,
    substr(first_name,1,3) AS initial3,
    substr(first_name,1,2) AS initial2,
    substr(first_name,1,1) AS initial
    FROM activist_director.equilar_w_activism
    WHERE permno IS NOT NULL AND executive_id IS NOT NULL),

issvoting_w_id AS (
    SELECT DISTINCT coalesce(e.executive_id, b.executive_id, c.executive_id, d.executive_id) AS executive_id, a.*
        FROM issvoting AS a
    LEFT JOIN equilar_simplified AS e
    ON a.permno=e.permno AND a.last_name ilike e.last_name AND a.initial3 ilike e.initial3
    LEFT JOIN equilar_simplified AS b
    ON a.permno=b.permno AND a.last_name ilike b.last_name AND a.initial2 ilike b.initial2
    LEFT JOIN equilar_simplified AS c
    ON a.permno=c.permno AND a.last_name ilike c.last_name AND a.initial ilike c.initial
    LEFT JOIN equilar_simplified AS d
    ON a.permno=d.permno AND a.last_name ilike d.last_name
    WHERE coalesce(e.executive_id, b.executive_id, c.executive_id, d.executive_id) IS NOT NULL),

issvoting_year AS (
    SELECT DISTINCT year
    FROM issvoting
    ORDER BY year),

issvoting_min_max_year AS (
    SELECT DISTINCT permno, min(year) AS min_year, max(year) AS max_year
    FROM issvoting
    GROUP BY permno
    ORDER BY permno),

issvoting_firm_id AS (
    SELECT DISTINCT b.permno, b.executive_id
    FROM issvoting_w_id AS b
    ORDER BY permno, executive_id),

issvoting_firm_id_year AS (
    SELECT DISTINCT a.permno, a.executive_id, b.year
    FROM issvoting_firm_id AS a, issvoting_year AS b
    ORDER BY permno, executive_id, year),

issvoting_firm_year_meetingdate AS (
    SELECT DISTINCT permno, year, meetingdate
    FROM issvoting
    ORDER BY permno, year, meetingdate),

issvoting_detailed AS (
    SELECT DISTINCT a.*, c.meetingdate, b.vote_pct, b.votes_cast,
    CASE WHEN b.issrec='For' THEN 'For'
    WHEN b.issrec IN ('Withhold', 'Against', 'Do Not Vote', 'Refer', 'Abstain', 'None') THEN 'Against' END AS issrec
    FROM issvoting_firm_id_year AS a
    INNER JOIN issvoting_min_max_year AS d
    ON a.permno=d.permno AND a.year BETWEEN d.min_year AND d.max_year
    LEFT JOIN issvoting_firm_year_meetingdate AS c
    ON a.permno=c.permno AND a.year=c.year
    LEFT JOIN issvoting_w_id AS b
    ON a.permno=b.permno AND a.executive_id=b.executive_id AND c.meetingdate=b.meetingdate
    ORDER BY permno, executive_id, year, meetingdate),

issvoting_lead_lag AS (
    SELECT DISTINCT permno, executive_id, year,
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
    lead(votes_cast,2) over w AS votes_cast_p2
    FROM issvoting_detailed
    WINDOW w AS (PARTITION BY permno, executive_id ORDER BY year, meetingdate)
    ORDER BY permno, executive_id, year, meetingdate),

average_voting_support AS (
    SELECT DISTINCT permno, meetingdate,
    avg(vote_pct_m3) AS avg_vote_pct_m3,
    avg(vote_pct_m2) AS avg_vote_pct_m2,
    avg(vote_pct_m1) AS avg_vote_pct_m1,
    avg(vote_pct) AS avg_vote_pct,
    avg(vote_pct_p1) AS avg_vote_pct_p1,
    avg(vote_pct_p2) AS avg_vote_pct_p2
    FROM issvoting_lead_lag
    GROUP BY permno, meetingdate
    ORDER BY permno, meetingdate),

issvoting_matched AS (
    SELECT DISTINCT a.permno, a.executive_id, a.year, COALESCE(b.period, c.period, d.period) AS period,
    meetingdate_m3, meetingdate_m2, meetingdate_m1, meetingdate, meetingdate_p1, meetingdate_p2,
    issrec_m3, issrec_m2, issrec_m1, issrec, issrec_p1, issrec_p2,
    vote_pct_m3, vote_pct_m2, vote_pct_m1, vote_pct, vote_pct_p1, vote_pct_p2,
    votes_cast_m3, votes_cast_m2, votes_cast_m1, votes_cast, votes_cast_p1, votes_cast_p2
    FROM issvoting_lead_lag AS a
    LEFT JOIN activist_director.equilar_w_activism AS b
    ON a.permno=b.permno AND a.executive_id=b.executive_id
    AND a.meetingdate_p1 BETWEEN b.period AND b.period + interval '1 year'
    LEFT JOIN activist_director.equilar_w_activism AS c
    ON a.permno=c.permno AND a.executive_id=c.executive_id
    AND a.meetingdate BETWEEN c.period - interval '1 year' AND c.period
    LEFT JOIN activist_director.equilar_w_activism AS d
    ON a.permno=d.permno AND a.executive_id=d.executive_id
    AND a.meetingdate_p2 BETWEEN d.period + interval '1 year' AND d.period + interval '2 years'
    WHERE COALESCE(b.period, c.period, d.period) IS NOT NULL
    ORDER BY permno, executive_id, year, meetingdate)

SELECT DISTINCT a.permno, a.executive_id, a.period, c.eff_announce_date,
    a.meetingdate_m3, a.meetingdate_m2, a.meetingdate_m1, a.meetingdate, a.meetingdate_p1, a.meetingdate_p2,
    issrec_m3, issrec_m2, issrec_m1, issrec, issrec_p1, issrec_p2,
    votes_cast_m3, votes_cast_m2, votes_cast_m1, votes_cast, votes_cast_p1, votes_cast_p2,
    vote_pct_m3, vote_pct_m2, vote_pct_m1, vote_pct, vote_pct_p1, vote_pct_p2,
    c.first_date, c.last_date,
    avg_vote_pct_m3, avg_vote_pct_m2, avg_vote_pct_m1, avg_vote_pct, avg_vote_pct_p1, avg_vote_pct_p2,
    c.activism_category,
    c.dissident_group_ownership_percent,
    c.board_seats_won,
    c.targeted_firm, c.targeted_firm_non_board,
    c.targeted_board_non_proxy, c.targeted_board_proxy,
    c.targeted_board_settled,
    c.first_appointment_date,
    c.activist_director, c.elected, c.went_the_distance, c.sharkwatch50,
    c.num_activist_directors, c.num_affiliate_directors, c.num_unaffiliate_directors,
    b.age, b.tenure, b.tenure_calc, b.comp_committee, b.audit_committee, b.audit_committee_financial_expert, --is_chairman, is_lead,
    b.insider, b.outsider,
    --ceo, ceo_turnover_p1, ceo_turnover_p0,
    --return, size_return, mkt_return, ind_return,
    --return_m5p3, size_return_m5p3, mkt_return_m5p3, ind_return_m5p3,
    --return_m6p0, size_return_m6p0, mkt_return_m6p0, ind_return_m6p0,
    --return_m8p4, size_return_m8p4, mkt_return_m8p4, ind_return_m8p4,
    --return_m9p3, size_return_m9p3, mkt_return_m9p3, ind_return_m9p3,
    --size_return_activism, mkt_return_activism,
    mv, btm, leverage, --rnd, capex, payout, dividend, cash_ivst, roa, ind_roa, sale_growth,
    dual_class, analyst, inst
FROM issvoting_matched AS a
LEFT JOIN activist_director.equilar_w_activism AS b
ON a.permno=b.permno AND a.executive_id=b.executive_id AND a.period=b.period
LEFT JOIN targeted.activism_events AS c
ON a.permno=c.permno
AND c.eff_announce_date BETWEEN
COALESCE(meetingdate, meetingdate_p1 - interval '1 year', meetingdate_m1 + interval '1 year')
AND COALESCE(meetingdate_p1, meetingdate + interval '1 year', meetingdate_p2 - interval '1 year')
LEFT JOIN activist_director.outcome_controls AS d
ON a.permno=d.permno AND a.period=d.datadate
LEFT JOIN average_voting_support AS e
ON a.permno=e.permno AND a.meetingdate=e.meetingdate
ORDER BY permno, executive_id, period;

ALTER TABLE activist_director.iss_voting OWNER TO activism;
")
