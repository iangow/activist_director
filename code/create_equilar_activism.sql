-----------------------------------------------------------
-------- Create activist_director.equilar_activism --------
-----------------------------------------------------------
DROP TABLE IF EXISTS activist_director.equilar_activism CASCADE;

CREATE TABLE activist_director.equilar_activism AS

WITH equilar_activist_director_match AS (
	SELECT DISTINCT c.permno, a.executive_id, a.first_name, a.last_name,
	    a.appointment_date, a.retirement_date, a.independent
	FROM activist_director.activist_director_equilar AS a
	INNER JOIN equilar_hbs.company_financials AS b
	ON a.company_id=b.company_id
	INNER JOIN crsp.stocknames AS c
	ON substr(b.cusip,1,8)=c.ncusip
	ORDER BY permno, executive_id), --1456 activist directors matched to equilar

equilar_activism_event_match AS (
    SELECT DISTINCT a.permno, a.executive_id, a.first_name, a.last_name, period,
        a.director_first_years, b.appointment_date, b.retirement_date,
        COALESCE(b.independent IS NOT NULL, FALSE) AS activist_director,
        COALESCE(b.independent IS FALSE, FALSE) AS affiliated_director,
        COALESCE(b.independent IS TRUE, FALSE) AS unaffiliated_director,
        COALESCE(CASE
                 WHEN c.independent IS NOT NULL THEN TRUE
                 WHEN d.activism IS NOT NULL THEN d.activism END, FALSE) AS activism_firm,
        COALESCE(CASE
                 WHEN c.independent IS NOT NULL THEN TRUE
                 WHEN d.activist_demand IS NOT NULL
                    THEN d.activist_demand END, FALSE) AS activist_demand_firm,
        COALESCE(CASE
                 WHEN c.independent IS NOT NULL THEN TRUE
                 WHEN d.activist_director IS NOT NULL
                    THEN d.activist_director END, FALSE) AS activist_director_firm
    FROM activist_director.equilar_final AS a
    LEFT JOIN equilar_activist_director_match AS b
    ON a.permno=b.permno
        AND a.executive_id=b.executive_id
        AND b.appointment_date BETWEEN a.company_director_min_start - INTERVAL '60 days'
        AND a.company_director_min_start + INTERVAL '60 days'
        AND a.period = a.company_director_min_period
    LEFT JOIN equilar_activist_director_match AS c
    ON a.permno=c.permno
        AND c.appointment_date BETWEEN a.company_director_min_start - INTERVAL '60 days'
        AND a.company_director_min_start + INTERVAL '60 days'
        AND a.period = a.company_director_min_period
    LEFT JOIN activist_director.activism_events AS d
    ON a.permno=d.permno
        AND company_director_min_start BETWEEN d.first_date AND d.end_date + INTERVAL '128 DAYS'
        AND a.period = a.company_director_min_period
    ORDER BY a.permno, executive_id),

unique_matches AS (
    SELECT DISTINCT permno, executive_id, first_name, last_name, period, director_first_years,
        appointment_date, retirement_date,
		BOOL_OR(activism_firm) AS activism_firm,
		BOOL_OR(activist_demand_firm) AS activist_demand_firm,
		BOOL_OR(activist_director_firm) AS activist_director_firm,
		BOOL_OR(activist_director) AS activist_director,
		BOOL_OR(affiliated_director) AS affiliated_director,
		BOOL_OR(unaffiliated_director) AS unaffiliated_director
    FROM equilar_activism_event_match
    GROUP BY permno, executive_id, first_name, last_name, period, director_first_years, appointment_date, retirement_date
    ORDER BY permno, executive_id, period)
--1316 activist directors successfully MATCHED

SELECT *
FROM unique_matches;

ALTER TABLE activist_director.equilar_activism OWNER TO activism;
