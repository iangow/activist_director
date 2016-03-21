DROP VIEW IF EXISTS activist_director.boardex_board_profiles;

CREATE VIEW activist_director.boardex_board_profiles AS

WITH director_age AS (
    SELECT DISTINCT a.boardid, a.directorid,
                    CASE WHEN a.annual_report_date = 'Current' THEN NULL ELSE eomonth(to_date(a.annual_report_date::text,'Mon YYYY')) END AS annual_report_date,
                    COALESCE(dob, '2015-07-01'::DATE - age*365) AS dob,
                    (CASE WHEN a.annual_report_date = 'Current' THEN NULL ELSE eomonth(to_date(a.annual_report_date::text,'Mon YYYY')) END - COALESCE(dob, '2015-07-01'::DATE - age*365))/365.25 AS age
    FROM boardex.director_characteristics AS a
    LEFT JOIN boardex.director_profile_details AS b
    ON a.directorid=b.directorid
    WHERE annual_report_date != 'Current'
    ORDER BY boardid, directorid, annual_report_date),

board_age AS (
    SELECT DISTINCT boardid, annual_report_date, avg(age) AS age
    FROM director_age
    GROUP BY boardid, annual_report_date
    ORDER BY boardid, annual_report_date)

SELECT DISTINCT a.boardid, a.annual_report_date,
	a.time_retirement, a.time_role, a.time_brd, a.time_inco, a.avg_time_oth_co,
	a.tot_nolstd_brd, a.tot_noun_lstd_brd, a.tot_curr_nolstd_brd, a.tot_curr_noun_lstd_brd,
	a.no_quals, a.gender_ratio, a.nationality_mix,
	a.number_directors, b.number_directors::DOUBLE PRECISION/a.number_directors::DOUBLE PRECISION AS outside_percent, c.age
FROM boardex.board_characteristics AS a
LEFT JOIN boardex.board_characteristics AS b
ON a.boardid=b.boardid AND a.annual_report_date=b.annual_report_date
LEFT JOIN board_age AS c
ON a.boardid=c.boardid AND a.annual_report_date=c.annual_report_date
WHERE a.row_type='Overall Board Characteristics'
AND b.row_type='ED Board Characteristics'
ORDER BY boardid, annual_report_date;

