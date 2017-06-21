WITH activism_events AS (
    SELECT DISTINCT permno, fiscal_year(eff_announce_date) AS fyear
    -- SELECT DISTINCT permno, fiscal_year(COALESCE(first_appointment_date,eff_announce_date)) AS fyear
    FROM activist_director.activism_events),

activist_director_events AS (
    SELECT DISTINCT permno, fiscal_year(first_appointment_date) AS fyear
    FROM activist_director.activism_events
    WHERE first_appointment_date IS NOT NULL),

compustat AS (
    SELECT DISTINCT a.gvkey, fyear, datadate,
        -- (datadate - lag(datadate) OVER w)::integer AS fyear_len,
        substr(b.sic,1,2) AS sic2, substr(b.sic,1,3) AS sic3,
        at, sale,
        CASE WHEN at > 0 THEN log(at) END AS log_at,
        CASE WHEN sale > 0 THEN log(sale) END AS log_sale,
        CASE WHEN ceq > 0 THEN log(ceq) END AS bv,
        CASE WHEN prcc_f * csho > 0 THEN log(prcc_f * csho) END AS mv,
        CASE WHEN lag(at) OVER w > 0 THEN oibdp/lag(at) OVER w END AS roa,
        CASE WHEN ceq > 0 AND prcc_f * csho > 0 AND dlc + dltt >= 0 THEN
          (prcc_f * csho + dlc + dltt) / (ceq + dlc + dltt) END AS tobins_q
    FROM comp.funda AS a
    LEFT JOIN comp.names AS b
    ON a.gvkey=b.gvkey AND a.fyear BETWEEN b.year1 AND b.year2
    WHERE indfmt='INDL' AND consol='C' AND popsrc='D' AND datafmt='STD'
        AND fyear >= (SELECT min(fyear)-3 FROM activism_events)
    WINDOW w AS (PARTITION BY a.gvkey ORDER BY datadate)),

industry_median_roa AS (
    SELECT fyear, sic2,
        median(roa) AS roa_median
    FROM compustat
    WHERE roa IS NOT NULL
    GROUP BY fyear, sic2),

industry_median_tobins_q AS (
    SELECT fyear, sic2,
        median(tobins_q) AS tobins_q_median
    FROM compustat
    WHERE tobins_q IS NOT NULL
    GROUP BY fyear, sic2),

industry_adjusted AS (
    SELECT DISTINCT gvkey, a.fyear, datadate, a.sic2, a.sic3, at, log_at,
        sale, log_sale, bv, mv,
        roa,
        tobins_q,
        roa - roa_median AS roa_ind_adj,
        tobins_q - tobins_q_median AS tobins_q_ind_adj
    FROM compustat AS a
    LEFT JOIN industry_median_roa AS b
    ON a.fyear=b.fyear AND a.sic2=b.sic2
    LEFT JOIN industry_median_tobins_q AS c
    ON a.fyear=c.fyear AND a.sic2=c.sic2),
    -- WHERE fyear_len > 270

permnos AS (
    SELECT DISTINCT a.datadate, a.gvkey, b.lpermno AS permno
    FROM compustat AS a
    INNER JOIN crsp.ccmxpf_linktable AS b
    ON a.gvkey=b.gvkey
    AND a.datadate >= b.linkdt
    AND (a.datadate <= b.linkenddt OR b.linkenddt IS NULL)
    AND b.USEDFLAG='1'
    AND linkprim IN ('C', 'P')),

roa_q AS (
    SELECT *
    FROM industry_adjusted AS a
    INNER JOIN permnos AS b
    USING (gvkey, datadate)),

dummies AS (
    SELECT DISTINCT a.permno, a.fyear,
        b.fyear IS NOT NULL AS activism,
        c.fyear IS NOT NULL AS activist_director,
        lead(b.fyear, 1) over w IS NOT NULL AS year_m1,
        lead(b.fyear, 2) over w IS NOT NULL AS year_m2,
        lead(b.fyear, 3) over w IS NOT NULL AS year_m3,
        b.fyear IS NOT NULL AS year_p0,
        lag(b.fyear, 1) over w IS NOT NULL AS year_p1,
        lag(b.fyear, 2) over w IS NOT NULL AS year_p2,
        lag(b.fyear, 3) over w IS NOT NULL AS year_p3,
        lag(b.fyear, 4) over w IS NOT NULL AS year_p4,
        lag(b.fyear, 5) over w IS NOT NULL AS year_p5,

        -- Non-activist director indicators
        lead(b.fyear, 1) over w IS NOT NULL AND lead(c.fyear, 1) over w IS NULL AS year_nad_m1,
        lead(b.fyear, 2) over w IS NOT NULL AND lead(c.fyear, 2) over w IS NULL AS year_nad_m2,
        lead(b.fyear, 3) over w IS NOT NULL AND lead(c.fyear, 3) over w IS NULL AS year_nad_m3,
        b.fyear IS NOT NULL AND c.fyear IS NULL AS year_nad_p0,
        lag(b.fyear, 1) over w IS NOT NULL AND lag(c.fyear, 1) over w IS NULL AS year_nad_p1,
        lag(b.fyear, 2) over w IS NOT NULL AND lag(c.fyear, 2) over w IS NULL AS year_nad_p2,
        lag(b.fyear, 3) over w IS NOT NULL AND lag(c.fyear, 3) over w IS NULL AS year_nad_p3,
        lag(b.fyear, 4) over w IS NOT NULL AND lag(c.fyear, 4) over w IS NULL AS year_nad_p4,
        lag(b.fyear, 5) over w IS NOT NULL AND lag(c.fyear, 5) over w IS NULL AS year_nad_p5,

        -- Activist director indicators
        lead(c.fyear, 1) over w IS NOT NULL AS year_ad_m1,
        lead(c.fyear, 2) over w IS NOT NULL AS year_ad_m2,
        lead(c.fyear, 3) over w IS NOT NULL AS year_ad_m3,
        c.fyear IS NOT NULL AS year_ad_p0,
        lag(c.fyear, 1) over w IS NOT NULL AS year_ad_p1,
        lag(c.fyear, 2) over w IS NOT NULL AS year_ad_p2,
        lag(c.fyear, 3) over w IS NOT NULL AS year_ad_p3,
        lag(c.fyear, 4) over w IS NOT NULL AS year_ad_p4,
        lag(c.fyear, 5) over w IS NOT NULL AS year_ad_p5
    FROM roa_q AS a
    LEFT JOIN activism_events AS b
    ON a.permno=b.permno
        AND b.fyear = a.fyear-1
    LEFT JOIN activist_director_events AS c
    ON a.permno=c.permno
        AND c.fyear = a.fyear-1
    WINDOW w AS (PARTITION BY a.permno ORDER BY a.fyear)),

founding_year AS (
    SELECT DISTINCT permno, extract(year from min(date)) AS founding_year
    FROM crsp.msf
    WHERE ret IS NOT NULL
    GROUP BY permno)

SELECT DISTINCT
    a.*, b.activism, b.activist_director,
    b.year_m3, b.year_m2, b.year_m1, b.year_p0, b.year_p1, b.year_p2, b.year_p3, b.year_p4, b.year_p5,
    b.year_nad_m3, b.year_nad_m2, b.year_nad_m1, b.year_nad_p0, b.year_nad_p1, b.year_nad_p2, b.year_nad_p3, b.year_nad_p4, b.year_nad_p5,
    b.year_ad_m3, b.year_ad_m2, b.year_ad_m1, b.year_ad_p0, b.year_ad_p1, b.year_ad_p2, b.year_ad_p3, b.year_ad_p4, b.year_ad_p5,
    CASE WHEN (a.fyear-founding_year) >= 0 THEN log(1 + a.fyear-founding_year) END AS age
FROM roa_q AS a
LEFT JOIN dummies AS b
ON a.permno=b.permno AND a.fyear = b.fyear
LEFT JOIN founding_year AS c
ON a.permno=c.permno
ORDER BY permno, fyear;
