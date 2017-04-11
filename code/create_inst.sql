SET work_mem='10GB';

DROP TABLE IF EXISTS activist_director.inst;

CREATE TABLE activist_director.inst AS

WITH latest_filings AS (
  SELECT filer_id, period_of_report, max(filed_as_of_date) AS filed_as_of_date
  FROM whalewisdom.filings
  GROUP BY filer_id, period_of_report),

latest_filing_ids AS (
  SELECT filer_id, period_of_report, filing_id
  FROM whalewisdom.filings AS a
  INNER JOIN latest_filings AS b
  USING (filer_id, period_of_report, filed_as_of_date)),

filing_stock_records AS (
  SELECT DISTINCT cusip_number, id, filing_id, stock_id, shares, security_type
  FROM whalewisdom.filing_stock_records AS a
  /*WHERE permno='22752'*/),

shares AS (
  SELECT a.cusip_number, b.period_of_report, sum(shares) AS shares
  FROM filing_stock_records AS a
  INNER JOIN latest_filing_ids AS b
  USING (filing_id)
  GROUP BY a.cusip_number, b.period_of_report),

shares_w_permno AS (
  SELECT b.permno, a.*
  FROM shares AS a
  INNER JOIN factset.permnos AS b
  ON substr(a.cusip_number, 1, 8)=b.ncusip),

shares2 AS (
  SELECT permno, period_of_report, sum(shares) AS shares
  FROM shares_w_permno
  GROUP BY permno, period_of_report),

compustat AS (
  SELECT DISTINCT b.lpermno AS permno, a.gvkey, a.datadate, a.csho
  FROM comp.funda AS a
  INNER JOIN crsp.ccmxpf_linktable AS b
  ON a.gvkey=b.gvkey
  AND a.datadate >= b.linkdt
  AND (a.datadate <= b.linkenddt OR b.linkenddt IS NULL)
  AND b.USEDFLAG='1'
  AND linkprim IN ('C', 'P')
  WHERE indfmt='INDL' AND consol='C' AND popsrc='D' AND datafmt='STD'
  AND datadate > '2000-01-01'
  ORDER BY permno, datadate)

SELECT b.permno, b.datadate, a.period_of_report, a.shares, b.csho*1000000 AS shares_outstanding,
  CASE WHEN b.csho > 0 THEN a.shares/(b.csho*1000000) END AS inst
FROM shares2 AS a
INNER JOIN compustat AS b
ON a.permno=b.permno AND a.period_of_report
    BETWEEN b.datadate - interval '3 months - 2 days' AND b.datadate
ORDER BY permno, datadate;

ALTER TABLE activist_director.inst OWNER TO activism;

COMMENT ON TABLE activist_director.inst IS
    'CREATED USING create_inst.sql';

--Query returned successfully with no result in 221212 ms.
