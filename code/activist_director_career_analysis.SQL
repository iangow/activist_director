-----------------------------------------------------------
-------- Create activist_director.equilar_activism --------
-----------------------------------------------------------
DROP TABLE IF EXISTS activist_director.equilar_activism CASCADE;

CREATE TABLE activist_director.equilar_activism AS

WITH equilar_activist_director_match AS (
	SELECT DISTINCT c.permno, a.executive_id, a.first_name, a.last_name, a.appointment_date, a.retirement_date, a.independent
	FROM activist_director.activist_director_equilar AS a
	INNER JOIN equilar_hbs.company_financials AS b
	ON a.company_id=b.company_id
	INNER JOIN crsp.stocknames AS c
	ON substr(b.cusip,1,8)=c.ncusip
	ORDER BY permno, executive_id), --1456 activist directors matched to equilar

equilar_activism_event_match AS (
    SELECT DISTINCT a.permno, a.executive_id, a.first_name, a.last_name, period, a.director_first_years, b.appointment_date, b.retirement_date,
            	COALESCE(b.independent IS NOT NULL, FALSE) AS activist_director,
            	COALESCE(b.independent IS FALSE, FALSE) AS affiliated_director,
            	COALESCE(b.independent IS TRUE, FALSE) AS unaffiliated_director,
            	COALESCE(CASE WHEN c.independent IS NOT NULL THEN TRUE WHEN d.activism IS NOT NULL THEN d.activism END, FALSE) AS activism_firm,
            	COALESCE(CASE WHEN c.independent IS NOT NULL THEN TRUE WHEN d.activist_demand IS NOT NULL THEN d.activist_demand END, FALSE) AS activist_demand_firm,
            	COALESCE(CASE WHEN c.independent IS NOT NULL THEN TRUE WHEN d.activist_director IS NOT NULL THEN d.activist_director END, FALSE) AS activist_director_firm
    FROM activist_director.equilar_final AS a
    LEFT JOIN equilar_activist_director_match AS b
    ON a.permno=b.permno AND a.executive_id=b.executive_id AND b.appointment_date BETWEEN a.company_director_min_start - INTERVAL '60 days' AND a.company_director_min_start + INTERVAL '60 days' AND a.period = a.company_director_min_period
    LEFT JOIN equilar_activist_director_match AS c
    ON a.permno=c.permno AND c.appointment_date BETWEEN a.company_director_min_start - INTERVAL '60 days' AND a.company_director_min_start + INTERVAL '60 days' AND a.period = a.company_director_min_period
    LEFT JOIN activist_director.activism_events AS d
    ON a.permno=d.permno AND company_director_min_start BETWEEN d.first_date AND d.end_date + INTERVAL '128 DAYS' AND a.period = a.company_director_min_period
    ORDER BY a.permno, executive_id),

unique_matches AS (
SELECT DISTINCT permno, executive_id, first_name, last_name, period, director_first_years, appointment_date, retirement_date,
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


-----------------------------------------------------------
-------- Create activist_director.equilar_activism --------
-----------------------------------------------------------
DROP TABLE IF EXISTS activist_director.equilar_all;

CREATE TABLE activist_director.equilar_all AS

SELECT DISTINCT a.*,
			b.own_m3, b.own_m2, b.own_m1, b.own_board, b.own_p1, b.own_p2, b.own_p3, b.own_p4, b.own_p5,
			b.firm_exists_m3, b.firm_exists_m2, b.firm_exists_m1, b.firm_exists, b.firm_exists_p1, b.firm_exists_p2, b.firm_exists_p3, b.firm_exists_p4, b.firm_exists_p5,
			b.total_m3, b.total_m2, b.total_m1, b.total_boards, b.total_p1, b.total_p2, b.total_p3, b.total_p4, b.total_p5,
			b.other_m3, b.other_m2, b.other_m1, b.other_boards, b.other_p1, b.other_p2, b.other_p3, b.other_p4, b.other_p5,
			b.inside_boards, b.outside_boards,
			c.activism_firm, c.activist_demand_firm, c.activist_director_firm, c.activist_director, c.affiliated_director, c.unaffiliated_director,
			c.appointment_date, c.retirement_date,
			d.analyst, d.inst, d.size_return, d.mv, d.btm, d.leverage, d.dividend, d.roa, d.sale_growth, d.payout,
			CASE WHEN activist_director_firm THEN 'activist_director_firm'
                WHEN activist_demand_firm THEN 'activist_demand_firm'
                WHEN activism_firm THEN 'activism_firm'
                    ELSE '_none' END AS category
FROM activist_director.equilar_final AS a
LEFT JOIN activist_director.equilar_career AS b
ON a.permno=b.permno AND a.executive_id=b.executive_id AND a.period=b.period
LEFT JOIN activist_director.equilar_activism AS c
ON a.permno=c.permno AND a.executive_id=c.executive_id AND a.period=c.period
LEFT JOIN activist_director.outcome_controls AS d
ON a.permno=d.permno AND a.period=d.datadate
WHERE own_board
ORDER BY permno, executive_id, period;


----------------------------------------------------------------
---- DESCRIPTIVE STATISTICS (Focusing on Appointment years) ----
----------------------------------------------------------------
SELECT activist_director, affiliated_director, count(activist_director),
	avg(age) AS age,
	avg(female::INT) AS female,
	avg(comp_committee::INT) AS comp_committee,
	avg(audit_committee::INT) AS audit_committee,
	avg(cmtes_cnt) AS committee,
	avg(audit_committee_financial_expert::INT) AS audit_committee_financial_expert,
	avg(industry_expert::INT) AS industry_expert,
	avg(super_industry_expert::INT) AS super_industry_expert
FROM activist_director.equilar_all
WHERE director_first_years --AND own_m1 IS FALSE
GROUP BY activist_director, affiliated_director
ORDER BY activist_director, affiliated_director;

SELECT activist_director, affiliated_director, count(own_board),
    avg(own_m3::INT) AS own_m3,
	avg(own_m2::INT) AS own_m2,
	avg(own_m1::INT) AS own_m1,
	avg(own_board::INT) AS own_p0,
	avg(own_p1::INT) AS own_p1,
	avg(own_p2::INT) AS own_p2,
	avg(own_p3::INT) AS own_p3,
	avg(own_p4::INT) AS own_p4,
	avg(own_p5::INT) AS own_p5
FROM activist_director.equilar_all
WHERE director_first_years --AND own_m1 IS FALSE
GROUP BY activist_director, affiliated_director
ORDER BY activist_director, affiliated_director;

SELECT activist_director, affiliated_director, count(other_boards),
	avg(other_m3) AS other_m3,
	avg(other_m2) AS other_m2,
	avg(other_m1) AS other_m1,
	avg(other_boards) other_p0,
	avg(other_p1) AS other_p1,
	avg(other_p2) AS other_p2,
	avg(other_p3) AS other_p3,
	avg(other_p4) AS other_p4,
	avg(other_p5) AS other_p5
FROM activist_director.equilar_all
WHERE director_first_years --AND own_m1 IS FALSE
GROUP BY activist_director, affiliated_director
ORDER BY activist_director, affiliated_director;
