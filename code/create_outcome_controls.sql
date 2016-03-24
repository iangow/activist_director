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
        AND linkprim IN ('C', 'P')
    ORDER BY gvkey, datadate),

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
        ppent, che, tlcf, pi, txfed,
        b.sic, substr(b.sic,1,2) AS sic2
    FROM comp.funda AS a
    LEFT JOIN comp.names AS b
    ON a.gvkey=b.gvkey
    AND EXTRACT(year FROM a.datadate) BETWEEN b.year1 AND b.year2
    WHERE indfmt='INDL' AND consol='C' AND popsrc='D' AND datafmt='STD'
    ORDER BY gvkey, datadate),

compustat AS (
    SELECT DISTINCT gvkey, datadate, fyear,
        at, sale, prcc_f, csho, ceq AS bv, sic, sic2,
        CASE WHEN at > 0 THEN log(at) END as log_at,
        CASE WHEN oibdp > 0 THEN (dvc+prstkc-pstkrv)/oibdp END AS payout,
        CASE WHEN prcc_f * csho > 0 THEN log(prcc_f * csho) END AS mv,
        CASE WHEN prcc_f * csho > 0 THEN ceq/(prcc_f*csho) END AS btm,
        CASE WHEN dltt+dlc+ceq > 0 THEN (dltt+dlc)/(dltt+dlc+ceq) END AS leverage,
        CASE WHEN lag(ppent) over w > 0 THEN capx/(lag(ppent) over w) END AS capex,
        CASE WHEN oibdp > 0 THEN (dvc + dvp)/oibdp
             WHEN oibdp <= 0 AND (dvc + dvp)=0 THEN 0 END AS dividend,
        CASE WHEN at > 0 THEN che/at END AS cash,
        CASE WHEN lag(at) over w > 0 THEN oibdp/lag(at) OVER w END AS roa,
        CASE WHEN lag(sale) over w > 0 THEN sale/lag(sale) OVER w END AS sale_growth,
        lead(datadate, 1) OVER w IS NOT NULL AS firm_exists_p1,
        lead(datadate, 2) OVER w IS NOT NULL AS firm_exists_p2,
        lead(datadate, 3) OVER w IS NOT NULL AS firm_exists_p3,
        tlcf > 0 AND COALESCE(pi,txfed) <= 0 AS nol_carryforward
    FROM funda
    WINDOW w AS (PARTITION BY gvkey ORDER BY datadate)
    ORDER BY gvkey, datadate),

compustat_w_permno AS (
    SELECT b.permno, a.*
    FROM compustat AS a
    INNER JOIN firm_years AS b
    USING (gvkey, datadate)
    ORDER BY permno, datadate),

-- CRSP Returns
crsp AS (
    SELECT a.permno, a.datadate, product(1+b.ret)-product(1+b.vwretd) AS size_return
    FROM firm_years AS a
    INNER JOIN crsp.mrets AS b
    ON a.permno=b.permno AND
    b.date BETWEEN eomonth(a.datadate) - interval '12 months - 2 day' AND eomonth(a.datadate)
    GROUP BY a.permno, a.datadate
    ORDER BY permno, datadate),

-- CRSP returns
crsp_m1 AS (
    SELECT a.permno, a.datadate, product(1+b.ret)-product(1+b.vwretd) AS size_return_m1
    FROM firm_years AS a
    INNER JOIN crsp.mrets AS b
    ON a.permno=b.permno AND
    b.date BETWEEN eomonth(a.datadate) - interval '24 months - 4 days'
        AND eomonth(a.datadate) - interval '12 months - 2 days'
    GROUP BY a.permno, a.datadate
    ORDER BY permno, datadate),

sharkrepellent AS (
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
    --WHERE unequal_voting IS NOT NULL
    GROUP BY permno
    ORDER BY permno),

staggered_board AS (
    SELECT DISTINCT permno, beg_date, end_date, staggered_board
    FROM activist_director.staggered_board AS a
    INNER JOIN activist_director.permnos AS b
    ON substr(a.cusip_9_digit,1,8)=b.ncusip
    ORDER BY permno, beg_date),

-- analyst coverage
ibes AS (
    SELECT DISTINCT permno, eomonth(statpers) AS fy_end, numest AS analyst
    FROM ibes.statsum_epsus AS a
    INNER JOIN activist_director.permnos AS b
    ON a.cusip=b.ncusip
    WHERE measure='EPS' AND fiscalp='ANN' AND fpi='1'
    ORDER BY permno, fy_end),

director_age AS (
    SELECT DISTINCT a.boardid, a.directorid, a.annual_report_date, b.age
    FROM boardex.director_characteristics AS a
    LEFT JOIN activist_director.director_ages AS b
    ON a.directorid=b.directorid AND a.annual_report_date=b.annual_report_date
    WHERE a.annual_report_date IS NOT NULL
    ORDER BY boardid, directorid, annual_report_date),

board_age AS (
    SELECT DISTINCT boardid, annual_report_date, avg(age) AS age
    FROM director_age
    GROUP BY boardid, annual_report_date
    ORDER BY boardid, annual_report_date),

boardex_board_profiles AS (
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
    AND b.row_type='SD Board Characteristics'
    ORDER BY boardid, annual_report_date),

-- board characteristics at firm-level
boardex_w_permno AS (
    SELECT DISTINCT c.permno, a.*
    FROM boardex_board_profiles AS a
    LEFT JOIN boardex.company_profile_stocks AS b
    ON a.boardid=b.boardid
    INNER JOIN activist_director.permnos AS c
    ON CASE WHEN substr(b.isin,1,2)='US' THEN substr(b.isin,3,8) END = c.ncusip
    ORDER BY permno, annual_report_date),

controls AS (
    SELECT DISTINCT a.*,
        c.size_return,
        h.size_return_m1,
        e.insider_percent,
        e.insider_diluted_percent,
        e.inst_percent,
        e.top_10_percent,
        e.majority,
        e.dual_class,
    	COALESCE(f.analyst, 0) AS analyst,
    	COALESCE(g.inst,0) AS inst,
    	i.gender_ratio,
    	i.age,
    	i.time_brd AS tenure,
    	d.staggered_board,
    	i.number_directors AS num_directors,
    	i.outside_percent,
    	i.permno IS NOT NULL AS on_boardex
    FROM compustat_w_permno AS a
    LEFT JOIN crsp AS c
    ON a.permno=c.permno AND a.datadate=c.datadate
    LEFT JOIN staggered_board AS d
    ON a.permno=d.permno AND a.datadate BETWEEN d.beg_date AND d.end_date
    LEFT JOIN sharkrepellent AS e
    ON a.permno=e.permno
    LEFT JOIN ibes AS f
    ON a.permno=f.permno AND eomonth(a.datadate)=f.fy_end
    LEFT JOIN activist_director.inst AS g
    ON a.permno=g.permno AND a.datadate=g.datadate
    LEFT JOIN crsp_m1 AS h
    ON a.permno=h.permno AND a.datadate=h.datadate
    INNER JOIN boardex_w_permno AS i
    ON a.permno=i.permno AND i.annual_report_date BETWEEN a.datadate - interval '1 year - 2 days' AND a.datadate
    ORDER BY a.permno, a.datadate),

activism_dates AS (
    SELECT
         min(eff_announce_date) - interval '1 year - 1 day' AS first_date,
         max(eff_announce_date) AS last_date
    FROM activist_director.activism_events)

SELECT DISTINCT a.*, extract(year FROM datadate) AS year,
    eff_announce_date, dissident_group, end_date, first_appointment_date,
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
LEFT JOIN activism_dates AS c
ON a.datadate BETWEEN c.first_date AND c.last_date
LEFT JOIN activist_director.activism_events AS b
ON a.permno=b.permno
    AND b.eff_announce_date
        BETWEEN a.datadate AND a.datadate + interval '1 year - 1 day'
ORDER BY permno, year;

COMMENT ON TABLE activist_director.outcome_controls IS
    'CREATED USING create_outcome_controls.sql';

CREATE INDEX ON activist_director.outcome_controls (permno, datadate);

ALTER TABLE activist_director.outcome_controls OWNER TO activism;
