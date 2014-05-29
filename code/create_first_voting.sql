DROP TABLE IF EXISTS activist_director.first_voting;

CREATE TABLE activist_director.first_voting AS 

-- Get all votes on directors that were not withdrawn and which have meaningful vote data
WITH compvote AS (
  SELECT *
  FROM issvoting.compvote
  WHERE issagendaitemid IN ('S0299', 'M0299', 'M0201', 'S0201', 'M0225') 
    AND itemdesc ~ '^Elect' AND voteresult != 'Withdrawn' 
    AND NOT (votedfor IN (0,1) OR greatest(votedagainst, votedabstain, votedwithheld) IN (0,1))),

-- When there are multiple items (i.e., in contested elections), we need to 
-- aggregate votes by ballotitem number to get all votes cast for the
-- competing directors
multiple_items AS (
  SELECT companyid, meetingid, ballotitemnumber, sum(votedfor + votedagainst + votedabstain) AS votes_cast
  FROM compvote
  GROUP BY companyid, meetingid, ballotitemnumber
  HAVING count(DISTINCT itemdesc)>1),

-- Otherwise we just add up votes for the director.
-- Sometimes the votedagainst number is duplicated as votewithheld, so we 
-- want to just take the one number in these cases. Otherwise, I think
-- we should include for, against, withheld, and abstain in the denominator.
single_items AS (
  SELECT companyid, meetingid, ballotitemnumber, 
    sum(votedfor + 
        CASE 
          WHEN votedwithheld=votedagainst THEN votedagainst 
          ELSE COALESCE(votedagainst, 0) + COALESCE(votedwithheld, 0) END + 
        COALESCE(votedabstain, 0)) AS votes_cast
  FROM compvote
  GROUP BY companyid, meetingid, ballotitemnumber
  HAVING count(itemdesc)=1),

-- Combine the two mutually exclusive datasets
votes_cast AS (
  SELECT companyid, meetingid, ballotitemnumber, votes_cast
  FROM compvote AS a
  INNER JOIN (
    SELECT * FROM multiple_items
    UNION
    SELECT * FROM single_items) AS b
  USING (companyid, meetingid, ballotitemnumber)),

-- Calculate vote_pct
director_votes AS (
  SELECT a.*, c.permno, b.votes_cast, CASE WHEN votes_cast > 0 THEN votedfor/votes_cast END AS vote_pct
  FROM compvote AS a
  INNER JOIN votes_cast AS b
  USING (companyid, meetingid, ballotitemnumber)
  LEFT JOIN activist_director.permnos AS c
  ON substr(a.cusip, 1, 8)=c.ncusip
  ORDER BY a.companyid, a.meetingid, a.ballotitemnumber),

issvoting AS (
    SELECT DISTINCT permno, extract(year from meetingdate) as year, meetingdate, 
        b.last_name, b.first_name, substr(b.first_name,1,3) AS initial3, substr(b.first_name,1,2) AS initial2, substr(b.first_name,1,1) AS initial, 
        mgmtrec, issrec, base, vote_pct, votes_cast
    FROM director_votes AS a
    INNER JOIN issvoting.director_names AS b
    ON a.itemdesc=b.itemdesc
    WHERE vote_pct >= 0.5
    ),

first_meetingdate AS (
    SELECT DISTINCT permno, last_name, first_name, min(meetingdate) AS first_meetingdate
    FROM issvoting
    GROUP BY permno, last_name, first_name),

first_voting AS (
	SELECT DISTINCT a.*, b.vote_pct, b.issrec
	FROM first_meetingdate AS a
	LEFT JOIN issvoting AS b
	ON a.permno=b.permno AND a.first_meetingdate=b.meetingdate AND a.last_name=b.last_name AND a.first_name=b.first_name)

SELECT * FROM first_voting ORDER BY PERMNO, LAST_NAME;

ALTER TABLE activist_director.first_voting OWNER TO activism;

COMMENT ON TABLE activist_director.first_voting
  IS 'CREATED USING first_voting.sql';
