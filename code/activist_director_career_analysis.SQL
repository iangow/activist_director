--------------------------------------------------------
-------- Create activist_director.equilar_final --------
--------------------------------------------------------

DROP TABLE IF EXISTS activist_director.equilar_final CASCADE;

CREATE TABLE activist_director.equilar_final AS

WITH equilar AS (
    SELECT DISTINCT c.permno, a.executive_id, extract(YEAR FROM a.period) AS YEAR, a.period,
                substr(b.sic,1,2) AS sic2,
                (director.parse_name(director_name)).first_name AS first_name,
                (director.parse_name(director_name)).last_name AS last_name,
                a.date_start, a.term_exp_dt,
                a.age, tenure, (a.period - a.date_start)/365.25 AS tenure_calc,
                gender='F' AS female, gender='M' AS male,
                insider_outsider_related='Outsider' AS outsider,
                insider_outsider_related='Insider' AS insider,
                COALESCE(cmtes ~ 'Comp', FALSE) AS comp_committee,
                COALESCE(cmtes ~ 'Audit', FALSE) AS audit_committee,
                cmtes_cnt, cmtes, is_audit_cmte_spec AS audit_committee_financial_expert,
                is_chair, is_vice_chair, is_lead
    FROM equilar_hbs.director_index AS a
    INNER JOIN equilar_hbs.company_financials AS b
    ON a.company_id=b.company_id AND a.period=b.fye
    INNER JOIN crsp.stocknames AS c
    ON substr(b.cusip,1,8)=c.ncusip
    WHERE period > '2000-12-31'
    ORDER BY permno, executive_id, period),

company_min_period AS (
    SELECT DISTINCT permno, min(period) AS company_min_period,
                max(period) AS company_max_period,
                COALESCE(max(term_exp_dt), max(period)) AS company_max_term
    FROM equilar
    GROUP BY permno
    ORDER BY permno),

company_min_start AS (
    SELECT DISTINCT permno, min(date_start) AS company_min_start
    FROM equilar
    WHERE date_start > '1900-01-01'
    GROUP BY permno
    ORDER BY permno),

company_director_min_period AS (
    SELECT DISTINCT permno, executive_id,
                min(period) AS company_director_min_period,
                max(period) AS company_director_max_period,
                COALESCE(max(term_exp_dt), max(period)) AS company_director_max_term
    FROM equilar
    GROUP BY permno, executive_id
    ORDER BY permno, executive_id),

company_director_min_start AS (
    SELECT DISTINCT permno, executive_id, min(date_start) AS company_director_min_start
    FROM equilar
    WHERE date_start > '1900-01-01'
    GROUP BY permno, executive_id
    ORDER BY permno, executive_id),

director_min_period AS (
    SELECT DISTINCT executive_id, min(period) AS director_min_period,
                max(period) AS director_max_period,
                COALESCE(max(term_exp_dt), max(period)) AS director_max_term
    FROM equilar
    GROUP BY executive_id
    ORDER BY executive_id),

director_min_start AS (
    SELECT DISTINCT executive_id, min(date_start) AS director_min_start
    FROM equilar
    WHERE date_start > '1900-01-01'
    GROUP BY executive_id
    ORDER BY executive_id),

director_industry_expert AS (
    SELECT DISTINCT executive_id, sic2, count(permno)
    FROM (SELECT DISTINCT permno, executive_id, sic2 FROM equilar WHERE sic2 IS NOT NULL) AS a
    GROUP BY executive_id, sic2
    ORDER BY executive_id),

equilar_final AS (
    SELECT DISTINCT a.*,
                b.company_min_period, b.company_max_term,
                c.company_director_min_period, c.company_director_max_term,
                d.director_min_period, d.director_max_term,
                bb.company_min_start,
                cc.company_director_min_start,
                dd.director_min_start,
                COALESCE(e.count > 1, FALSE) AS industry_expert,
                COALESCE(e.count > 2, FALSE) AS super_industry_expert,
                CASE WHEN company_director_min_start BETWEEN company_director_min_period - INTERVAL '18 MONTHS' AND company_director_min_period + INTERVAL '18 MONTHS'
                    THEN company_director_min_period = period END AS director_first_years
    FROM equilar AS a
    LEFT JOIN company_min_period AS b
    ON a.permno=b.permno
    LEFT JOIN company_director_min_period AS c
    ON a.permno=c.permno AND a.executive_id=c.executive_id
    LEFT JOIN director_min_period AS d
    ON a.executive_id=d.executive_id
    LEFT JOIN company_min_start AS bb
    ON a.permno=bb.permno
    LEFT JOIN company_director_min_start AS cc
    ON a.permno=cc.permno AND a.executive_id=cc.executive_id
    LEFT JOIN director_min_start AS dd
    ON a.executive_id=dd.executive_id
    LEFT JOIN director_industry_expert AS e
    ON a.executive_id=e.executive_id AND a.sic2=e.sic2 AND e.count > 1
    ORDER BY permno, executive_id)

SELECT * FROM equilar_final;


---------------------------------------------------------
-------- Create activist_director.equilar_career --------
---------------------------------------------------------

DROP TABLE IF EXISTS activist_director.equilar_career CASCADE;

CREATE TABLE activist_director.equilar_career AS

WITH company_years AS (
    SELECT DISTINCT permno, period
    FROM activist_director.equilar_final
    ORDER BY permno, period),

-- Get all firm-director combinations (note: no years)
company_directors AS (
    SELECT DISTINCT permno, executive_id, company_director_min_start, company_director_min_period, company_director_max_term
    FROM activist_director.equilar_final
    ORDER BY permno, executive_id),

own_board AS (
    SELECT DISTINCT a.permno, a.executive_id, b.period, a.company_director_min_start, a.company_director_min_period, a.company_director_max_term,
                b.period BETWEEN LEAST(a.company_director_min_start, a.company_director_min_period) AND a.company_director_max_term AS own_board,
    TRUE AS firm_exists
    FROM company_directors AS a
    LEFT JOIN company_years AS b
    ON a.permno=b.permno
    ORDER BY permno, executive_id, period),

own_boards AS (
    SELECT permno, executive_id, period, company_director_min_start, company_director_min_period, company_director_max_term,
                --        lag(own_board, 3) over w AS own_m3,
                --        lag(own_board, 2) over w AS own_m2,
                --        lag(own_board, 1) over w AS own_m1,
                --        own_board,
                --        lead(own_board, 1) OVER w AS own_p1,
                --        lead(own_board, 2) OVER w AS own_p2,
                --        lead(own_board, 3) OVER w AS own_p3,
                --        lead(own_board, 4) OVER w AS own_p4,
                --        lead(own_board, 5) OVER w AS own_p5,
                COALESCE(lag(own_board, 3) OVER w, CASE WHEN period >= '2004-12-31' THEN FALSE END) AS own_m3,
                COALESCE(lag(own_board, 2) OVER w, CASE WHEN period >= '2003-12-31' THEN FALSE END) AS own_m2,
                COALESCE(lag(own_board, 1) OVER w, CASE WHEN period >= '2002-12-31' THEN FALSE END) AS own_m1,
                own_board,
                COALESCE(lead(own_board, 1) OVER w, CASE WHEN period <= '2015-12-31' THEN FALSE END) AS own_p1,
                COALESCE(lead(own_board, 2) OVER w, CASE WHEN period <= '2014-12-31' THEN FALSE END) AS own_p2,
                COALESCE(lead(own_board, 3) OVER w, CASE WHEN period <= '2013-12-31' THEN FALSE END) AS own_p3,
                COALESCE(lead(own_board, 4) OVER w, CASE WHEN period <= '2012-12-31' THEN FALSE END) AS own_p4,
                COALESCE(lead(own_board, 5) OVER w, CASE WHEN period <= '2011-12-31' THEN FALSE END) AS own_p5,

                COALESCE(lag(firm_exists, 3) OVER w, CASE WHEN period >= '2004-12-31' THEN FALSE END) AS firm_exists_m3,
                COALESCE(lag(firm_exists, 2) OVER w, CASE WHEN period >= '2003-12-31' THEN FALSE END) AS firm_exists_m2,
                COALESCE(lag(firm_exists, 1) OVER w, CASE WHEN period >= '2002-12-31' THEN FALSE END) AS firm_exists_m1,
                firm_exists,
                COALESCE(lead(firm_exists, 1) OVER w, CASE WHEN period <= '2015-12-31' THEN FALSE END) AS firm_exists_p1,
                COALESCE(lead(firm_exists, 2) OVER w, CASE WHEN period <= '2014-12-31' THEN FALSE END) AS firm_exists_p2,
                COALESCE(lead(firm_exists, 3) OVER w, CASE WHEN period <= '2013-12-31' THEN FALSE END) AS firm_exists_p3,
                COALESCE(lead(firm_exists, 4) OVER w, CASE WHEN period <= '2012-12-31' THEN FALSE END) AS firm_exists_p4,
                COALESCE(lead(firm_exists, 5) OVER w, CASE WHEN period <= '2011-12-31' THEN FALSE END) AS firm_exists_p5
    FROM own_board
    WINDOW w AS (PARTITION BY permno, executive_id ORDER BY period)),

directorship_counts AS (
    SELECT DISTINCT a.executive_id, YEAR, count(a.permno) AS total_boards, sum(a.insider::INT) AS inside_boards, sum(a.outsider::INT) AS outside_boards
    FROM activist_director.equilar_final AS a
    GROUP BY executive_id, YEAR
    ORDER BY executive_id, YEAR),

all_company_director_years AS (
    SELECT DISTINCT a.executive_id, a.permno, b.year
    FROM (SELECT DISTINCT executive_id, permno FROM activist_director.equilar_final) AS a,
    (SELECT DISTINCT year FROM activist_director.equilar_final) AS b
    ORDER BY executive_id, permno, year),

-- Other Boards = Total Boards - Own Board
count_other AS (
    SELECT DISTINCT a.executive_id, a.permno, a.year,
                COALESCE(c.own_board::INT,0) AS own_boards, COALESCE(b.total_boards,0) AS total_boards,
                COALESCE(b.total_boards,0) - COALESCE(c.own_board::INT,0) AS other_boards,
                inside_boards, outside_boards
    FROM all_company_director_years AS a
    LEFT JOIN directorship_counts AS b
    ON a.executive_id=b.executive_id AND a.year=b.YEAR
    LEFT JOIN own_board AS c
    ON a.permno=c.permno AND a.executive_id=c.executive_id AND a.YEAR=extract(YEAR FROM c.period)
    ORDER BY executive_id, permno, year),

-- Lead/Lag
count_others AS (
    SELECT DISTINCT permno, executive_id, year, inside_boards, outside_boards,
                lag(total_boards, 3) OVER w AS total_m3,
                lag(total_boards, 2) OVER w AS total_m2,
                lag(total_boards, 1) OVER w AS total_m1,
                total_boards,
                lead(total_boards, 1) OVER w AS total_p1,
                lead(total_boards, 2) OVER w AS total_p2,
                lead(total_boards, 3) OVER w AS total_p3,
                lead(total_boards, 4) OVER w AS total_p4,
                lead(total_boards, 5) OVER w AS total_p5,
                lag(other_boards, 3) OVER w AS other_m3,
                lag(other_boards, 2) OVER w AS other_m2,
                lag(other_boards, 1) OVER w AS other_m1,
                other_boards,
                lead(other_boards, 1) OVER w AS other_p1,
                lead(other_boards, 2) OVER w AS other_p2,
                lead(other_boards, 3) OVER w AS other_p3,
                lead(other_boards, 4) OVER w AS other_p4,
                lead(other_boards, 5) OVER w AS other_p5
    FROM count_other
    WINDOW w AS (PARTITION BY permno, executive_id ORDER BY year)
    ORDER BY executive_id, permno, year)

SELECT DISTINCT a.*, b.inside_boards, outside_boards,
                total_m3, total_m2, total_m1, total_boards, total_p1, total_p2, total_p3, total_p4, total_p5,
                other_m3, other_m2, other_m1, other_boards, other_p1, other_p2, other_p3, other_p4, other_p5
FROM own_boards AS a
LEFT JOIN count_others AS b
ON a.permno=b.permno AND a.executive_id=b.executive_id AND extract(YEAR FROM a.period)=b.year
ORDER BY permno, executive_id, period;


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
    SELECT DISTINCT a.permno, a.executive_id, a.first_name, a.last_name, period, a.director_first_years,
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
SELECT DISTINCT permno, executive_id, first_name, last_name, period, director_first_years,
				BOOL_OR(activism_firm) AS activism_firm,
				BOOL_OR(activist_demand_firm) AS activist_demand_firm,
				BOOL_OR(activist_director_firm) AS activist_director_firm,
				BOOL_OR(activist_director) AS activist_director,
				BOOL_OR(affiliated_director) AS affiliated_director,
				BOOL_OR(unaffiliated_director) AS unaffiliated_director
FROM equilar_activism_event_match
--WHERE activist_director
GROUP BY permno, executive_id, first_name, last_name, period, director_first_years
ORDER BY permno, executive_id, first_name, last_name, period, director_first_years)
--1316 activist directors successfully MATCHED

SELECT *
FROM unique_matches


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
			d.analyst, d.inst, d.size_return, d.mv, d.btm, d.leverage, d.dividend, d.roa, d.sale_growth, d.payout
FROM activist_director.equilar_final AS a
LEFT JOIN activist_director.equilar_career AS b
ON a.permno=b.permno AND a.executive_id=b.executive_id AND a.period=b.period
LEFT JOIN activist_director.equilar_activism AS c
ON a.permno=c.permno AND a.executive_id=c.executive_id AND a.period=c.period
LEFT JOIN activist_director.outcome_controls AS d
ON a.permno=d.permno AND a.period=d.datadate
WHERE own_board
ORDER BY permno, executive_id, period;

SELECT * FROM activist_director.equilar_all;

-- DESCRIPTIVE STATISTICS (Focusing on Appointment years)
SELECT activist_director, affiliated_director,
	avg(age) AS age,
	avg(female::INT) AS female,
	avg(comp_committee::INT) AS comp_committee,
	avg(audit_committee::INT) AS audit_committee,
	avg(cmtes_cnt) AS committee,
	avg(audit_committee_financial_expert::INT) AS audit_committee_financial_expert,
	avg(industry_expert::INT) AS industry_expert,
	avg(super_industry_expert::INT) AS super_industry_expert,
FROM activist_director.equilar_all
WHERE director_first_years --AND own_m1 IS FALSE
GROUP BY activist_director, affiliated_director
ORDER BY activist_director, affiliated_director;

SELECT activist_director, affiliated_director,
    avg(own_m3::INT) AS own_m3,
	avg(own_m2::INT) AS own_m2,
	avg(own_m1::INT) AS own_m1,
	avg(own_board::INT) AS own_p0,
	avg(own_p1::INT) AS own_p1,
	avg(own_p2::INT) AS own_p2,
	avg(own_p3::INT) AS own_p3,
	avg(own_p4::INT) AS own_p4,
	avg(own_p5::INT) AS own_p5,
FROM activist_director.equilar_all
WHERE director_first_years --AND own_m1 IS FALSE
GROUP BY activist_director, affiliated_director
ORDER BY activist_director, affiliated_director;

SELECT activist_director, affiliated_director,
	avg(other_m3) AS other_m3,
	avg(other_m2) AS other_m2,
	avg(other_m1) AS other_m1,
	avg(other_boards) other_p0,
	avg(other_p1) AS other_p1,
	avg(other_p2) AS other_p2,
	avg(other_p3) AS other_p3,
	avg(other_p4) AS other_p4,
	avg(other_p5) AS other_p5,
	count(other_boards)
FROM activist_director.equilar_all
WHERE director_first_years --AND own_m1 IS FALSE
GROUP BY activist_director, affiliated_director
ORDER BY activist_director, affiliated_director;
