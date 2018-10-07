-----------------------------------------------------------
-------- Create activist_director.equilar_activism --------
-----------------------------------------------------------
DROP TABLE IF EXISTS activist_director.equilar_all;

CREATE TABLE activist_director.equilar_all AS

SELECT DISTINCT a.*,
	b.own_m3, b.own_m2, b.own_m1, b.own_board, b.own_p1, b.own_p2, b.own_p3, b.own_p4, b.own_p5,
	b.firm_exists_m3, b.firm_exists_m2, b.firm_exists_m1, b.firm_exists, b.firm_exists_p1,
	b.firm_exists_p2, b.firm_exists_p3, b.firm_exists_p4, b.firm_exists_p5,
	b.total_m3, b.total_m2, b.total_m1, b.total_boards, b.total_p1, b.total_p2,
	b.total_p3, b.total_p4, b.total_p5, b.other_m3, b.other_m2, b.other_m1, b.other_boards,
	b.other_p1, b.other_p2, b.other_p3, b.other_p4, b.other_p5,
	b.inside_boards, b.outside_boards,
	c.activism_firm, c.activist_demand_firm, c.activist_director_firm, c.activist_director,
	c.affiliated_director, c.unaffiliated_director,
	c.appointment_date, c.retirement_date,
	d.analyst, d.inst, d.size_return, d.mv, d.btm, d.leverage, d.dividend, d.roa, d.sale_growth, d.payout,
	CASE WHEN activist_director_firm THEN 'activist_director_firm'
        WHEN activist_demand_firm THEN 'activism_firm'
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

ALTER TABLE activist_director.equilar_all OWNER TO activism;
