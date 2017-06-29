DROP TABLE IF EXISTS activist_director.activist_director_years;

CREATE TABLE activist_director.activist_director_years AS

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
    WHERE fyear > 2000
    ORDER BY gvkey, datadate),

activist_director AS (
    SELECT DISTINCT campaign_id, permno, MIN(appointment_date) AS appointment_date, MAX(COALESCE(retirement_date, '2016-12-31')) AS retirement_date
    FROM activist_director.activist_directors
    GROUP BY campaign_id, permno
    ORDER BY permno, appointment_date),

activist_director_on_board AS (
    SELECT DISTINCT a.permno, a.datadate, b.permno IS NOT NULL AS on_board
    FROM activist_director.outcome_controls AS a
    LEFT JOIN activist_director AS b
    ON a.permno=b.permno AND a.datadate BETWEEN appointment_date AND retirement_date)

SELECT DISTINCT permno, datadate, BOOL_OR(on_board) AS ad_on_board
FROM activist_director_on_board
GROUP BY permno, datadate
ORDER BY permno, datadate;

COMMENT ON TABLE activist_director.activist_director_years IS
'CREATED USING create_activist_director_years.sql';

ALTER TABLE activist_director.activist_director_years OWNER TO activism;
