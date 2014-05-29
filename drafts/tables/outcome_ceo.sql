WITH outcome_controls AS (
    SELECT *,
        CASE WHEN firm_exists_p2 THEN FALSE END AS default_p2,
        CASE WHEN firm_exists_p3 THEN FALSE END AS default_p3,
        CASE WHEN firm_exists_p2 THEN 0 END AS default_num_p2,
        CASE WHEN firm_exists_p3 THEN 0 END AS default_num_p3,
        datadate + interval '2 years' AS datadate_p2,
        datadate + interval '3 years' AS datadate_p3
    FROM activist_director.outcome_controls),

ceo_turnover_prep AS (
    SELECT DISTINCT c.permno, a.fy_end, a.executive, a.ceo_turnover
    FROM activist_director.ceo_turnover AS a
    LEFT JOIN board.co_fin AS b
    ON a.equilar_id=equilar_id(b.company_id)
    INNER JOIN activist_director.permnos AS c
    ON b.cusip=c.ncusip),

ceo_turnover AS (
    SELECT DISTINCT permno, fy_end, ceo_turnover::int,
        (lead(ceo_turnover, 1) OVER w)::int AS ceo_turnover_p1,
        (lead(ceo_turnover, 1) OVER w OR lead(ceo_turnover, 2) OVER w)::int AS ceo_turnover_p2,
        (lead(ceo_turnover, 1) OVER w OR lead(ceo_turnover, 2) OVER w
            OR lead(ceo_turnover, 3) OVER w)::int AS ceo_turnover_p3
    FROM ceo_turnover_prep
    WINDOW w AS (PARTITION BY permno ORDER BY fy_end)
    ORDER BY permno, fy_end),

new_data AS (
    SELECT DISTINCT executive_id, executive, ticker, fy_end, company,
        COALESCE(base_salary, 0) AS salary,
        COALESCE(base_salary, 0) +
        COALESCE(bonus, 0) +
        COALESCE(stock_awards_as_disclosed, 0) +
        COALESCE(option_awards_as_disclosed, 0) +
        COALESCE(non_equity_incentive_plan_neip_payouts, 0) +
        COALESCE(change_in_pension_and_nqdc_earnings, 0) +
        COALESCE(all_other_comp, 0) AS calc_total_comp,
        total_compensation_as_disclosed
    FROM executive.executive_nd
    WHERE title ~* '(C\.?E\.?O\.|Chief Executive Officer)'),

old_data AS (
    SELECT DISTINCT executive_id, executive, ticker, fy_end, company,
        COALESCE(base_salary, 0) AS salary,
        COALESCE(base_salary, 0) +
        COALESCE(bonus, 0) +
        COALESCE(restricted_Stock_Awards, 0) +
        COALESCE(value_of_stock_options_black_scholes, 0) +
        COALESCE(Other_Comp, 0) +
        COALESCE(Other_Annual_Comp, 0) AS calc_total_comp,
        NULL::float8 AS total_compensation_as_disclosed
    FROM executive.executive
    WHERE title ~* '(C\.?E\.?O\.|Chief Executive Officer)'),

combined_data AS (
    SELECT *, calc_total_comp AS total_comp
    FROM old_data
    UNION
    SELECT *, COALESCE(total_compensation_as_disclosed, calc_total_comp) AS total_comp
    FROM new_data),

ceo_comp_w_permno AS (
    SELECT DISTINCT permno, a.fy_end,
        total_comp,
        CASE WHEN total_comp > 0 THEN 1 - salary/total_comp END AS perf_comp
    FROM combined_data AS a
    LEFT JOIN director.co_fin AS b
    ON equilar_id(a.executive_id)=equilar_id(b.company_id) AND a.fy_end=b.fy_end
    INNER JOIN activist_director.permnos AS c
    ON substr(b.cusip,1,8)=c.ncusip),

ceo_comp_prep AS (
    SELECT DISTINCT permno, fy_end,
        avg(total_comp) AS ceo_comp, avg(perf_comp) AS perf_comp
    FROM ceo_comp_w_permno
    GROUP BY permno, fy_end),

ceo_comp AS (
    SELECT DISTINCT permno, fy_end, ceo_comp, perf_comp,
        lead(ceo_comp,1) OVER w AS ceo_comp_p1,
        lead(ceo_comp,2) OVER w AS ceo_comp_p2,
        lead(ceo_comp,3) OVER w AS ceo_comp_p3,
        lead(perf_comp,1) OVER w AS perf_comp_p1,
        lead(perf_comp,2) OVER w AS perf_comp_p2,
        lead(perf_comp,3) OVER w AS perf_comp_p3
    FROM ceo_comp_prep
    WINDOW W AS (PARTITION BY permno ORDER BY fy_end)
    ORDER BY permno, fy_end)

SELECT a.*,
    f.ceo_turnover, f.ceo_turnover_p1, f.ceo_turnover_p2, f.ceo_turnover_p3,
    CASE WHEN g.ceo_comp > 0 THEN ln(g.ceo_comp) END AS ceo_comp,
    CASE WHEN g.ceo_comp_p1 > 0 THEN ln(g.ceo_comp_p1) END AS ceo_comp_p1,
    CASE WHEN g.ceo_comp_p2 > 0 THEN ln(g.ceo_comp_p2) END AS ceo_comp_p2,
    CASE WHEN g.ceo_comp_p3 > 0 THEN ln(g.ceo_comp_p3) END AS ceo_comp_p3,
    g.perf_comp, g.perf_comp_p1, g.perf_comp_p2, g.perf_comp_p3
FROM outcome_controls AS a
LEFT JOIN ceo_turnover AS f
ON a.permno=f.permno AND a.datadate=f.fy_end
LEFT JOIN ceo_comp AS g
ON a.permno=g.permno AND a.datadate=g.fy_end
WHERE a.firm_exists_p3
ORDER BY a.permno, a.datadate;
