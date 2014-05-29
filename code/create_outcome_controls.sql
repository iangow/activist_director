-- This tables about 2 minutes to run.

SET work_mem='8GB';

DROP TABLE IF EXISTS activist_director.outcome_controls;

CREATE TABLE activist_director.outcome_controls AS

-- Compustat with PERMNO
WITH firm_years AS (
    SELECT DISTINCT a.gvkey, a.datadate, b.lpermno AS permno
    FROM comp.funda AS a
    INNER JOIN crsp.ccmxpf_linktable AS b
    ON a.gvkey=b.gvkey
        AND a.datadate >= b.linkdt
        AND (a.datadate <= b.linkenddt OR b.linkenddt IS NULL)
        AND b.USEDFLAG='1'
        AND linkprim IN ('C', 'P')),

-- Compustat controls
funda AS (
    SELECT DISTINCT a.gvkey, a.datadate, fyear,
        at, sale, prcc_f, csho, ceq, oibdp,
        COALESCE(dvc,0) AS dvc,
        COALESCE(dvp,0) AS dvp,
        COALESCE(prstkc, 0) AS prstkc,
        COALESCE(pstkrv, 0) AS pstkrv,
        COALESCE(dltt,0) AS dltt,
        COALESCE(dlc, 0) AS dlc,
        COALESCE(capx, 0) AS capx,
        ppent, che,
        b.sic, substr(b.sic,1,2) AS sic2
    FROM comp.funda AS a
    LEFT JOIN comp.names AS b
    ON a.gvkey=b.gvkey
        AND EXTRACT(year FROM a.datadate) BETWEEN b.year1 AND b.year2
    WHERE indfmt='INDL' AND consol='C' AND popsrc='D' AND datafmt='STD'),

compustat AS (
    SELECT DISTINCT gvkey, datadate, fyear,
        at, sale, prcc_f, csho, ceq AS bv, sic, sic2,
        CASE WHEN at > 0 THEN log(at) END as log_at,
        CASE WHEN oibdp > 0 THEN (dvc+prstkc-pstkrv)/oibdp END AS payout,
        CASE WHEN prcc_f * csho > 0 THEN log(prcc_f * csho) END AS mv,
        CASE WHEN prcc_f * csho > 0 THEN ceq/(prcc_f*csho) END AS btm,
        CASE WHEN dltt+dlc+ceq > 0 THEN (dltt+dlc)/(dltt+dlc+ceq)  END AS leverage,
        CASE WHEN lag(ppent) over w > 0 THEN capx/(lag(ppent) over w) END AS capex,
        CASE WHEN oibdp > 0 THEN (dvc + dvp)/oibdp
             WHEN oibdp <= 0 AND (dvc + dvp)=0 THEN 0 END AS dividend,
        CASE WHEN at > 0 THEN che/at END AS cash,
        CASE WHEN lag(at) over w > 0 THEN oibdp/lag(at) OVER w END AS roa,
        CASE WHEN lag(sale) over w > 0 THEN sale/lag(sale) OVER w END AS sale_growth,
        lead(datadate, 1) OVER w IS NOT NULL AS firm_exists_p1,
        lead(datadate, 2) OVER w IS NOT NULL AS firm_exists_p2,
        lead(datadate, 3) OVER w IS NOT NULL AS firm_exists_p3
    FROM funda
    WINDOW w AS (PARTITION BY gvkey ORDER BY datadate)),

compustat_w_permno AS (
    SELECT *
    FROM compustat AS a
    INNER JOIN firm_years AS b
    USING (gvkey, datadate)),

-- CRSP Returns
crsp AS (
    SELECT permno, datadate,
    product(1+b.ret)-product(1+b.vwretd) AS size_return
    FROM firm_years AS a
    INNER JOIN crsp.mrets AS b
    ON a.permno=b.permno AND
    b.date BETWEEN eomonth(a.datadate) - interval '12 months - 2 day' AND eomonth(a.datadate)
    GROUP BY a.permno, a.datadate),

-- CRSP returns
crsp2 AS (
    SELECT a.permno, a.datadate,
    product(1+b.ret)-product(1+b.vwretd) AS size_return_m1
    FROM firm_years AS a
    INNER JOIN crsp.mrets AS b
    ON a.permno=b.permno AND
    b.date BETWEEN eomonth(a.datadate) - interval '24 months - 4 days'
        AND eomonth(a.datadate) - interval '12 months - 2 days'
    GROUP BY a.permno, a.datadate),

sharkrepellent_data AS (
    SELECT DISTINCT permno,
        sum(insider_ownership_percent) AS insider_percent,
    	sum(insider_ownership_diluted_percent) AS insider_diluted_percent,
    	sum(institutional_ownership_percent) AS inst_percent,
    	sum(top_10_institutional_ownership_percent) AS top_10_percent,
    	bool_or(vote_requirement_to_elect_directors='Majority') AS majority,
    	bool_or(unequal_voting='Yes') AS dual_class
    FROM factset.sharkrepellent AS a
    INNER JOIN activist_director.permnos AS b
    ON substr(a.cusip_9_digit,1,8) = b.ncusip
    WHERE unequal_voting IS NOT NULL
    GROUP BY permno),

sharkrepellent AS (
    SELECT DISTINCT permno,
        insider_percent, insider_diluted_percent, inst_percent, top_10_percent,
        majority, dual_class
    FROM sharkrepellent_data),

-- analyst coverage
ibes AS (
    SELECT permno, eomonth(statpers) AS fy_end, numest AS analyst
    FROM ibes.statsum_epsus AS a
    INNER JOIN activist_director.permnos AS b
    ON a.cusip=b.ncusip
    WHERE measure='EPS' AND fiscalp='ANN' AND fpi='1'),

equilar_directors AS (
    SELECT DISTINCT equilar_id(a.director_id) AS equilar_id,
        director_id(a.director_id) AS equilar_director_id, director_id,
        a.fy_end, extract(year from a.fy_end) AS year,
        a.insider_outsider_related = 'Outsider' AS outsider,
        age, (a.fy_end-start_date)/365.25 AS tenure_yrs
    FROM director.director AS a
    INNER JOIN director.director_names AS b
    ON a.director=b.director),

staggered_board AS (
    SELECT DISTINCT equilar_id(company_id), fy_end, staggered_board='Y' AS staggered_board
    FROM board.board AS a
    WHERE staggered_board IS NOT NULL),

-- board characteristics at firm-level
equilar AS (
    SELECT DISTINCT a.equilar_id, a.fy_end, year,
		sum(outsider::int)::float8/count(outsider) AS outside_percent,
	    avg(age) AS age,
		avg(tenure_yrs) AS tenure_yrs,
	    sum(percent_shares_owned) AS percent_owned,
	    BOOL_OR(staggered_board) AS staggered_board
    FROM equilar_directors AS a
    LEFT JOIN director.percent_owned AS b
    ON a.equilar_id=b.equilar_id AND a.fy_end=b.fy_end AND a.director_id=b.director_id
    LEFT JOIN staggered_board AS c
    ON a.equilar_id=c.equilar_id AND a.fy_end=c.fy_end
    GROUP BY a.equilar_id, a.fy_end, year),

equilar_w_permno AS (
    SELECT DISTINCT c.permno, a.fy_end, a.year,
		a.outside_percent, a.age, a.tenure_yrs,
        a.percent_owned, a.staggered_board
    FROM equilar AS a
    LEFT JOIN director.co_fin AS b
    ON a.equilar_id=equilar_id(b.company_id) AND a.fy_end=b.fy_end
    INNER JOIN activist_director.permnos AS c
    ON substr(b.cusip,1,8)=c.ncusip
    -- IDG: What is this about?
    WHERE
        a.equilar_id NOT IN ('2583', '8598', '2907', '7506')
        AND NOT (equilar_id = '4431' AND a.fy_end ='2010-09-30')
        AND NOT (equilar_id = '46588' AND a.fy_end = '2012-12-31')),

count_directors AS (
    SELECT DISTINCT equilar_id(director_id) AS equilar_id, fy_end,
        count(director_id(director_id)) AS num_directors
    FROM director.director
    WHERE equilar_id(director_id) NOT IN ('2583', '8598', '2907', '7506')
        AND NOT (equilar_id(director_id) = '4431' AND fy_end ='2010-09-30')
    GROUP BY equilar_id(director_id), fy_end),

num_directors AS (
    SELECT DISTINCT c.permno, a.fy_end, a.num_directors
    FROM count_directors AS a
    LEFT JOIN director.co_fin AS b
    ON a.equilar_id=equilar_id(b.company_id) AND a.fy_end=b.fy_end
    INNER JOIN activist_director.permnos AS c
    ON substr(b.cusip,1,8)=c.ncusip),

controls AS (
    SELECT DISTINCT a.*,
        c.size_return, h.size_return_m1,
        e.insider_percent, e.insider_diluted_percent, e.inst_percent, e.top_10_percent,
        e.majority, e.dual_class,
    	COALESCE(f.analyst, 0) AS analyst, COALESCE(g.inst,0) AS inst,
    	i.outside_percent, i.age, i.tenure_yrs, i.percent_owned, i.staggered_board, j.num_directors,
        i.permno IS NOT NULL AS on_equilar
    FROM compustat_w_permno AS a
    LEFT JOIN crsp AS c
    ON a.permno=c.permno AND a.datadate=c.datadate
    LEFT JOIN sharkrepellent AS e
    ON a.permno=e.permno
    LEFT JOIN ibes AS f
    ON a.permno=f.permno AND eomonth(a.datadate)=f.fy_end
    LEFT JOIN targeted.inst AS g
    ON a.permno=g.permno AND eomonth(a.datadate)=eomonth(g.fy_end)
    LEFT JOIN crsp2 AS h
    ON a.permno=h.permno AND a.datadate=h.datadate
    LEFT JOIN equilar_w_permno AS i
    ON a.permno=i.permno
        AND i.fy_end BETWEEN a.datadate - interval '1 year 2 days' AND a.datadate
    LEFT JOIN num_directors AS j
    ON a.permno=j.permno
        AND j.fy_end BETWEEN a.datadate - interval '1 year 2 days' AND a.datadate),

activism_dates AS (
    SELECT
         min(eff_announce_date) - interval '1 year - 1 day' AS first_date,
         max(eff_announce_date) AS last_date
    FROM activist_director.activism_events)

SELECT DISTINCT a.*, extract(year FROM datadate) AS year,
    announce_date, dissident_group, end_date, first_appointment_date,
    num_activist_directors, num_affiliate_directors,
    proxy_fight, proxy_fight_went_definitive, proxy_fight_went_the_distance,
    COALESCE(category,'_none') AS category,
    COALESCE(affiliated,'_none') AS affiliated,
    COALESCE(early,'_none') AS early,
    COALESCE(big_investment,'_none') AS big_investment,
    COALESCE(two_plus,'_none') AS two_plus,
    CASE WHEN activist_director THEN 'activist_director'
    WHEN activism THEN 'non_activist_director'
    ELSE '_none' END AS activist_director
FROM controls AS a
INNER JOIN activism_dates AS c
ON a.datadate BETWEEN c.first_date AND c.last_date
LEFT JOIN activist_director.activism_events AS b
ON a.permno=b.permno
    AND b.eff_announce_date BETWEEN a.datadate AND a.datadate + interval '1 year - 1 day';

COMMENT ON TABLE activist_director.outcome_controls IS
    'CREATED USING create_outcome_controls.sql';

CREATE INDEX ON activist_director.outcome_controls (permno, datadate);

ALTER TABLE activist_director.outcome_controls OWNER TO activism;
