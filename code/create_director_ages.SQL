DROP TABLE IF EXISTS activist_director.director_ages;

CREATE TABLE activist_director.director_ages AS

WITH equilar_age AS (
SELECT DISTINCT permno, boardid, directorid, annual_report_date, age,
	CASE WHEN age IS NULL
		AND lag(age,1) OVER w IS NOT NULL
		AND lag(annual_report_date,1) OVER w IS NOT NULL
			THEN lag(age,1) OVER w + (annual_report_date - lag(annual_report_date,1) OVER w)/365
	WHEN age IS NULL
		AND lead(age,1) OVER w IS NOT NULL
		AND lead(annual_report_date,1) OVER w IS NOT NULL
			THEN lead(age,1) OVER w - (lead(annual_report_date,1) OVER w - annual_report_date)/365
	WHEN age IS NULL
		AND lag(age,2) OVER w IS NOT NULL
		AND lag(annual_report_date,2) OVER w IS NOT NULL
			THEN lag(age,2) OVER w + (annual_report_date - lag(annual_report_date,2) OVER w)/365
	WHEN age IS NULL
		AND lead(age,2) OVER w IS NOT NULL
		AND lead(annual_report_date,2) OVER w IS NOT NULL
			THEN lead(age,2) OVER w - (lead(annual_report_date,2) OVER w - annual_report_date)/365
	WHEN age IS NULL
		AND lag(age,3) OVER w IS NOT NULL
		AND lag(annual_report_date,3) OVER w IS NOT NULL
			THEN lag(age,3) OVER w + (annual_report_date - lag(annual_report_date,3) OVER w)/365
	WHEN age IS NULL
		AND lead(age,3) OVER w IS NOT NULL
		AND lead(annual_report_date,3) OVER w IS NOT NULL
			THEN lead(age,3) OVER w - (lead(annual_report_date,3) OVER w - annual_report_date)/365
	WHEN age IS NULL
		AND lag(age,4) OVER w IS NOT NULL
		AND lag(annual_report_date,4) OVER w IS NOT NULL
			THEN lag(age,4) OVER w + (annual_report_date - lag(annual_report_date,4) OVER w)/365
	WHEN age IS NULL
		AND lead(age,4) OVER w IS NOT NULL
		AND lead(annual_report_date,4) OVER w IS NOT NULL
			THEN lead(age,4) OVER w - (lead(annual_report_date,4) OVER w - annual_report_date)/365
	WHEN age IS NULL
		AND lag(age,5) OVER w IS NOT NULL
		AND lag(annual_report_date,5) OVER w IS NOT NULL
			THEN lag(age,5) OVER w + (annual_report_date - lag(annual_report_date,5) OVER w)/365
	WHEN age IS NULL
		AND lead(age,5) OVER w IS NOT NULL
		AND lead(annual_report_date,5) OVER w IS NOT NULL
			THEN lead(age,5) OVER w - (lead(annual_report_date,5) OVER w - annual_report_date)/365
	WHEN age IS NULL
		AND lag(age,6) OVER w IS NOT NULL
		AND lag(annual_report_date,6) OVER w IS NOT NULL
			THEN lag(age,6) OVER w + (annual_report_date - lag(annual_report_date,6) OVER w)/365
	WHEN age IS NULL
		AND lead(age,6) OVER w IS NOT NULL
		AND lead(annual_report_date,6) OVER w IS NOT NULL
			THEN lead(age,6) OVER w - (lead(annual_report_date,6) OVER w - annual_report_date)/365
	WHEN age IS NULL
		AND lag(age,7) OVER w IS NOT NULL
		AND lag(annual_report_date,7) OVER w IS NOT NULL
			THEN lag(age,7) OVER w + (annual_report_date - lag(annual_report_date,7) OVER w)/365
	WHEN age IS NULL
		AND lead(age,7) OVER w IS NOT NULL
		AND lead(annual_report_date,7) OVER w IS NOT NULL
			THEN lead(age,7) OVER w - (lead(annual_report_date,7) OVER w - annual_report_date)/365
	WHEN age IS NULL
		AND lag(age,8) OVER w IS NOT NULL
		AND lag(annual_report_date,8) OVER w IS NOT NULL
			THEN lag(age,8) OVER w + (annual_report_date - lag(annual_report_date,8) OVER w)/365
	WHEN age IS NULL
		AND lead(age,8) OVER w IS NOT NULL
		AND lead(annual_report_date,8) OVER w IS NOT NULL
			THEN lead(age,8) OVER w - (lead(annual_report_date,8) OVER w - annual_report_date)/365
	ELSE age END AS equilar_age
FROM activist_director.equilar_boardex AS a
--WHERE permno < 10100
WINDOW w AS (PARTITION BY permno, boardid, directorid ORDER BY annual_report_date)
ORDER BY permno, boardid, directorid, annual_report_date),

ages AS (
    SELECT *
    FROM boardex.director_profile_details
    WHERE dob IS NULL AND age IS NOT NULL),

max_date AS (
    SELECT max(announcement_date) AS max_date
    FROM boardex.board_and_director_announcements),

ages_plus AS (
    SELECT *
    FROM ages, max_date),

boardex_age AS (
SELECT DISTINCT a.directorid, a.annual_report_date,
	CASE WHEN b.dob IS NOT NULL THEN age_years(a.annual_report_date, b.dob)
		ELSE c.age - age_years(c.max_date, a.annual_report_date) END AS boardex_age
FROM boardex.director_characteristics AS a
LEFT JOIN boardex.director_profile_details AS b
ON a.directorid=b.directorid
LEFT JOIN ages_plus AS c
ON a.directorid=c.directorid
WHERE a.annual_report_date IS NOT NULL
ORDER BY directorid, annual_report_date)

SELECT DISTINCT a.directorid, a.annual_report_date, COALESCE(equilar_age, boardex_age) AS age
FROM boardex.director_characteristics AS a
LEFT JOIN equilar_age AS b
ON a.directorid=b.directorid AND a.annual_report_date=b.annual_report_date
LEFT JOIN boardex_age AS c
ON a.directorid=c.directorid AND a.annual_report_date=c.annual_report_date
WHERE a.annual_report_date IS NOT NULL
ORDER BY directorid, annual_report_date
