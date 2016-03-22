WITH
outcome_controls AS (
    SELECT *,
        CASE WHEN firm_exists_p2 THEN FALSE END AS default_p2,
        CASE WHEN firm_exists_p3 THEN FALSE END AS default_p3,
        CASE WHEN firm_exists_p2 THEN 0 END AS default_num_p2,
        CASE WHEN firm_exists_p3 THEN 0 END AS default_num_p3,
        datadate + interval '2 years' AS datadate_p2,
        datadate + interval '3 years' AS datadate_p3
    FROM activist_director.outcome_controls),

delisting AS (
    SELECT DISTINCT permno, dlstdt,
        dlstcd > 100 AS delist,
        dlstcd BETWEEN 200 AND 399 AS merger,
        dlstcd BETWEEN 520 AND 599 AS failure
    FROM crsp.dsedelist),

spinoff AS (
    SELECT DISTINCT b.lpermno AS permno, announcedate, keydevtoobjectroletypeid
    FROM ciq.wrds_keydev AS a
    INNER JOIN crsp.ccmxpf_linktable AS b
    ON a.gvkey=b.gvkey
    	AND a.announcedate >= b.linkdt
    	AND (a.announcedate <= b.linkenddt OR b.linkenddt IS NULL)
    	AND b.USEDFLAG='1'
    	AND linkprim IN ('C', 'P')
    WHERE a.gvkey IS NOT NULL
    	AND keydeveventtypeid = 137
    	AND keydevtoobjectroletypeid = 4
    	--AND announcedate >= '2004-01-01'
    ORDER BY permno, announcedate),

spinoff_crsp AS (
    SELECT DISTINCT COALESCE(a.permno, b.permno) AS permno,
        COALESCE(a.acperm) AS new_permno,
        COALESCE(GREATEST(a.dclrdt, a.exdt, a.rcrddt, a.paydt), b.announcedate) AS date
    FROM activist_director.spinoff AS a
    FULL JOIN spinoff AS b
    ON a.permno=b.permno AND extract(year from a.rcrddt)=extract(year from b.announcedate)),

divestiture AS (
    SELECT DISTINCT b.lpermno AS permno, announcedate, keydevtoobjectroletypeid
    FROM ciq.wrds_keydev AS a
    INNER JOIN crsp.ccmxpf_linktable AS b
    ON a.gvkey=b.gvkey
	    AND a.announcedate >= b.linkdt
	    AND (a.announcedate <= b.linkenddt OR b.linkenddt IS NULL)
	    AND b.USEDFLAG='1'
	    AND linkprim IN ('C', 'P')
    WHERE a.gvkey IS NOT NULL
    AND keydeveventtypeid=81
    AND keydevtoobjectroletypeid = 4
    --AND announcedate >= '2004-01-01'
    ORDER BY permno, announcedate),

acquisition AS (
    SELECT DISTINCT b.lpermno AS permno, announcedate, keydevtoobjectroletypeid
    FROM ciq.wrds_keydev AS a
    INNER JOIN crsp.ccmxpf_linktable AS b
    ON a.gvkey=b.gvkey
	    AND a.announcedate >= b.linkdt
	    AND (a.announcedate <= b.linkenddt OR b.linkenddt IS NULL)
	    AND b.USEDFLAG='1'
	    AND linkprim IN ('C', 'P')
    WHERE a.gvkey IS NOT NULL
    AND keydeveventtypeid=81
    AND keydevtoobjectroletypeid = 3
    --AND announcedate >= '2004-01-01'
    ORDER BY permno, announcedate),

controls AS (
    SELECT DISTINCT a.permno, a.datadate,
        COALESCE(count(b.permno), sum(default_num_p2)) AS num_divestiture_p2,
        COALESCE(count(b.permno) > 0, bool_or(default_p2)) AS divestiture_p2,
        COALESCE(count(d.permno), sum(default_num_p2)) AS num_acquisition_p2,
        COALESCE(count(d.permno)>0, bool_or(default_p2)) AS acquisition_p2,
        COALESCE(count(f.permno), sum(default_num_p2)) AS num_spinoff_p2,
        COALESCE(bool_or(h.delist), bool_or(default_p2)) AS delist_p2,
        COALESCE(bool_or(h.merger), bool_or(default_p2)) AS merger_p2,
        COALESCE(bool_or(h.failure), bool_or(default_p2)) AS failure_p2,

        COALESCE(count(c.permno), sum(default_num_p3)) AS num_divestiture_p3,
        COALESCE(count(c.permno) > 0, bool_or(default_p3)) AS divestiture_p3,
        COALESCE(count(e.permno), sum(default_num_p3)) AS num_acquisition_p3,
        COALESCE(count(e.permno)>0, bool_or(default_p3)) AS acquisition_p3,
        COALESCE(count(g.permno), sum(default_num_p3)) AS num_spinoff_p3,
        COALESCE(bool_or(j.delist), bool_or(default_p3)) AS delist_p3,
        COALESCE(bool_or(j.merger), bool_or(default_p3)) AS merger_p3,
        COALESCE(bool_or(j.failure), bool_or(default_p3)) AS failure_p3

    FROM outcome_controls AS a
    LEFT JOIN divestiture AS b
    ON a.permno=b.permno
        AND b.announcedate BETWEEN a.datadate AND a.datadate_p2
    LEFT JOIN divestiture AS c
    ON a.permno=c.permno
        AND c.announcedate BETWEEN a.datadate AND a.datadate_p3
    LEFT JOIN acquisition AS d
    ON a.permno=d.permno
        AND d.announcedate BETWEEN a.datadate AND a.datadate_p2
    LEFT JOIN acquisition AS e
    ON a.permno=e.permno
        AND e.announcedate BETWEEN a.datadate AND a.datadate_p3
    LEFT JOIN spinoff AS f
    ON a.permno=f.permno
        AND f.announcedate BETWEEN a.datadate AND a.datadate_p2
    LEFT JOIN spinoff AS g
    ON a.permno=g.permno
        AND g.announcedate BETWEEN a.datadate AND a.datadate_p3
    LEFT JOIN delisting AS h
    ON a.permno=h.permno
        AND h.dlstdt BETWEEN a.datadate AND a.datadate_p2
    LEFT JOIN delisting AS j
    ON a.permno=j.permno
        AND j.dlstdt BETWEEN a.datadate AND a.datadate_p3
    GROUP BY a.permno, a.datadate)
SELECT *
FROM outcome_controls
INNER JOIN controls
USING (permno, datadate)
ORDER BY permno, datadate;
