SET work_mem='10GB';

DROP TABLE IF EXISTS activist_director.equilar_boardex;

CREATE TABLE activist_director.equilar_boardex AS

-- BoardEx permno-year-director_names(+id)
WITH boardex AS (
    SELECT DISTINCT c.permno, a.boardid, annual_report_date, extract(year from annual_report_date) AS year,
        a.directorid,
        lower(d.last_name) AS last_name,
        lower(d.first_name) AS first_name,
        lower(substr(d.first_name,1,1)) AS initial,
        lower(substr(d.first_name,1,2)) AS initial2,
        lower(substr(d.first_name,1,3)) AS initial3
    FROM boardex.director_characteristics AS a
    INNER JOIN boardex.company_profile_stocks AS b
    ON a.boardid=b.boardid
    INNER JOIN activist_director.permnos AS c
    ON CASE WHEN substr(b.isin,1,2)='US' THEN substr(b.isin,3,8) END=c.ncusip
    INNER JOIN activist_director.director_names AS d
    ON a.director_name=d.directorname
    WHERE annual_report_date IS NOT NULL
    ORDER BY permno, directorid, year),

equilar AS (
    SELECT DISTINCT permno, equilar_id(a.director_id) AS firm_id, a.fy_end, extract(year from a.fy_end) AS year,
        director_id(a.director_id) AS directorid,
        lower(d.last_name) AS last_name,
        lower(d.first_name) AS first_name,
    	lower(substr(d.first_name,1,1)) AS initial,
    	lower(substr(d.first_name,1,2)) AS initial2,
    	lower(substr(d.first_name,1,3)) AS initial3,
    	a.age
    FROM director.director AS a
    INNER JOIN director.co_fin AS b
    ON equilar_id(a.director_id)=equilar_id(b.company_id)
    INNER JOIN activist_director.permnos AS c
    ON substr(b.cusip,1,8)=c.ncusip
    LEFT JOIN director.director_names AS d
    ON a.director=d.original_name
    WHERE a.fy_end IS NOT NULL
    ORDER BY permno, directorid, fy_end),

-- permno-last_name-first_name-year match
first_match AS (
    SELECT DISTINCT a.permno, a.boardid, a.annual_report_date, b.fy_end, a.year,
        a.directorid, a.last_name, a.first_name, a.initial, a.initial2, a.initial3,
        b.age,
        CASE WHEN b.directorid IS NOT NULL THEN 1 END AS matched
    FROM boardex AS a
    LEFT JOIN equilar AS b
    ON a.permno=b.permno
    AND a.last_name=b.last_name
    AND a.first_name=b.first_name
    AND a.annual_report_date=b.fy_end),

-- permno-last_name-initial3-year match
second_match AS (
    SELECT DISTINCT a.permno, a.boardid, a.year, a.annual_report_date,
	CASE WHEN a.fy_end IS NULL THEN b.fy_end ELSE a.fy_end END AS fy_end,
        a.directorid, a.last_name, a.first_name, a.initial, a.initial2, a.initial3,
        CASE WHEN a.age IS NULL THEN b.age ELSE a.age END AS age,
        CASE WHEN b.directorid IS NOT NULL AND a.matched IS NULL THEN 2 ELSE a.matched END AS matched
    FROM first_match AS a
    LEFT JOIN equilar AS b
    ON a.permno=b.permno
    AND a.last_name=b.last_name
    AND a.initial3=b.initial3
    AND a.annual_report_date=b.fy_end),

-- permno-last_name-initial2-year match
third_match AS (
    SELECT DISTINCT a.permno, a.boardid, a.year, a.annual_report_date,
	CASE WHEN a.fy_end IS NULL THEN b.fy_end ELSE a.fy_end END AS fy_end,
        a.directorid, a.last_name, a.first_name, a.initial, a.initial2, a.initial3,
        CASE WHEN a.age IS NULL THEN b.age ELSE a.age END AS age,
        CASE WHEN b.directorid IS NOT NULL AND a.matched IS NULL THEN 3 ELSE a.matched END AS matched
    FROM second_match AS a
    LEFT JOIN equilar AS b
    ON a.permno=b.permno
    AND a.last_name=b.last_name
    AND a.initial2=b.initial2
    AND a.annual_report_date=b.fy_end),

-- permno-last_name-initial-year match
fourth_match AS (
    SELECT DISTINCT a.permno, a.boardid, a.year, a.annual_report_date,
	CASE WHEN a.fy_end IS NULL THEN b.fy_end ELSE a.fy_end END AS fy_end,
        a.directorid, a.last_name, a.first_name, a.initial, a.initial2, a.initial3,
        CASE WHEN a.age IS NULL THEN b.age ELSE a.age END AS age,
        CASE WHEN b.directorid IS NOT NULL AND a.matched IS NULL THEN 4 ELSE a.matched END AS matched
    FROM third_match AS a
    LEFT JOIN equilar AS b
    ON a.permno=b.permno
    AND a.last_name=b.last_name
    AND a.initial=b.initial
    AND a.annual_report_date=b.fy_end),

-- permno-last_name-year match
fifth_match AS (
    SELECT DISTINCT a.permno, a.boardid, a.year, a.annual_report_date,
	CASE WHEN a.fy_end IS NULL THEN b.fy_end ELSE a.fy_end END AS fy_end,
        a.directorid, a.last_name, a.first_name, a.initial, a.initial2, a.initial3,
        CASE WHEN a.age IS NULL THEN b.age ELSE a.age END AS age,
        CASE WHEN b.directorid IS NOT NULL AND a.matched IS NULL THEN 5 ELSE a.matched END AS matched
    FROM fourth_match AS a
    LEFT JOIN equilar AS b
    ON a.permno=b.permno
    AND a.last_name=b.last_name
    AND a.annual_report_date=b.fy_end)

SELECT *
FROM fifth_match
ORDER BY permno, boardid, directorid, annual_report_date;

CREATE INDEX on activist_director.equilar_boardex (permno, fy_end);

ALTER TABLE activist_director.equilar_boardex OWNER TO activism;

--Query returned successfully with no result in 123620 ms.
