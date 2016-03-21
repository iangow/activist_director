SET work_mem='4GB';

DROP TABLE IF EXISTS activist_director.staggered_board;

CREATE TABLE activist_director.staggered_board AS

WITH charterbylaw_defense_change_desc AS (
	SELECT cusip_9_digit, company_name, company_status_date,
		regexp_replace(regexp_split_to_table(charterbylaw_defense_change_desc, '(?=\d{2}-\d{2}-\d{4})'), '\n', '', 'g') AS event_text
	FROM activist_director.sharkrepellent
	--WHERE cusip_9_digit = '585141104'
	ORDER BY cusip_9_digit),

changes_by_date AS (
	SELECT *,
		to_date(regexp_replace(regexp_matches(event_text, '\d{1,2}-\d{1,2}-\d{4}', 'g')::text, '[{}]', '', 'g'), 'MM-DD-YYYY') AS event_date
	FROM charterbylaw_defense_change_desc
	ORDER BY cusip_9_digit, event_date, event_text),
-- SELECT * FROM changes_by_date WHERE event_text ilike '%advance notice%'

staggered_board_changes AS (
	SELECT *
	FROM changes_by_date
	WHERE event_text ilike '%staggered%' OR event_text ilike '%classified%'
		OR event_text ilike '%classify%' OR event_text ilike '%declassify%'
		OR event_text ilike '%stagger%' OR event_text ilike '%destagger%'
	ORDER BY cusip_9_digit, event_date, event_text),

declassify_staggered_board AS (
SELECT *
FROM staggered_board_changes
WHERE event_text ilike '%declassify%'
ORDER BY cusip_9_digit),

classify_staggered_board AS (
SELECT *
FROM staggered_board_changes
WHERE NOT event_text ilike '%declassify%' AND event_text ilike '%classify%'
ORDER BY cusip_9_digit),

beg_dates AS (
SELECT DISTINCT cusip_9_digit, event_date AS beg_date
FROM staggered_board_changes
UNION
SELECT DISTINCT cusip_9_digit, '2000-01-01'::DATE AS beg_date
FROM staggered_board_changes),

beg_end_dates AS (
SELECT DISTINCT cusip_9_digit, beg_date, COALESCE((lead(beg_date) OVER w - interval '1 day')::DATE, '2016-03-20') AS end_date
FROM beg_dates AS a
WINDOW w AS (PARTITION BY cusip_9_digit ORDER BY beg_date)
ORDER BY cusip_9_digit, beg_date),

staggered_board_beg_end AS (
SELECT DISTINCT a.cusip_9_digit, beg_date, end_date,
	CASE WHEN b.cusip_9_digit IS NOT NULL THEN FALSE WHEN c.cusip_9_digit IS NOT NULL THEN TRUE
		WHEN d.cusip_9_digit IS NOT NULL THEN TRUE WHEN e.cusip_9_digit IS NOT NULL THEN FALSE END AS staggered_board
FROM beg_end_dates AS a
LEFT JOIN declassify_staggered_board AS b
ON a.cusip_9_digit=b.cusip_9_digit AND a.beg_date=b.event_date
LEFT JOIN classify_staggered_board AS c
ON a.cusip_9_digit=c.cusip_9_digit AND a.beg_date=c.event_date
LEFT JOIN declassify_staggered_board AS d
ON a.cusip_9_digit=d.cusip_9_digit AND a.end_date+1=d.event_date
LEFT JOIN classify_staggered_board AS e
ON a.cusip_9_digit=e.cusip_9_digit AND a.end_date+1=e.event_date
ORDER BY cusip_9_digit, beg_date, end_date),

firm_years AS (
SELECT DISTINCT a.cusip_9_digit, '2000-01-01'::DATE AS beg_date, COALESCE(company_status_date, '2016-03-20') AS end_date,
	CASE WHEN classified_board_with_staggered_terms = 'Yes' THEN TRUE WHEN classified_board_with_staggered_terms = 'No' THEN FALSE END AS staggered_board
FROM activist_director.sharkrepellent AS a
LEFT JOIN staggered_board_beg_end AS b
ON a.cusip_9_digit=b.cusip_9_digit
WHERE a.cusip_9_digit IS NOT NULL AND b.cusip_9_digit IS NULL

UNION

SELECT DISTINCT *
FROM staggered_board_beg_end
ORDER BY cusip_9_digit, beg_date)

SELECT *
FROM firm_years
WHERE cusip_9_digit IS NOT NULL AND staggered_board IS NOT NULL;

