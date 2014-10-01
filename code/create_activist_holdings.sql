SET work_mem='10GB';
SET enable_seqscan=FALSE;

DROP TABLE IF EXISTS activist_director.activist_holdings;

CREATE TABLE activist_director.activist_holdings AS
WITH activist_filers AS (
  SELECT DISTINCT b.filing_id, c.cik, b.period_of_report, b.filed_as_of_date
  FROM whalewisdom.filings AS b
  INNER JOIN whalewisdom.filers AS c
  ON b.filer_id=c.filer_id
  INNER JOIN activist_director.activist_ciks AS e
  ON c.cik=e.cik),

activist_stocks AS (
  SELECT DISTINCT b.cik, b.period_of_report, b.filed_as_of_date,
    CASE
      WHEN alt_cusip != ' ' THEN substr(alt_cusip,1,8)
      WHEN alt_cusip = ' ' THEN substr(cusip_number,1,8)
      WHEN alt_cusip IS NULL THEN substr(cusip_number,1,8)
      ELSE NULL
    END AS cusip, market_value, shares
  FROM activist_filers AS b
  INNER JOIN whalewisdom.filing_stock_records AS a
  ON a.filing_id=b.filing_id
  WHERE substr(COALESCE(a.alt_cusip, a.cusip_number),1,8) IS NOT NULL
    OR substr(COALESCE(a.alt_cusip, a.cusip_number),1,8) != ' '),

latest_filings AS (
  SELECT DISTINCT cik, cusip, period_of_report,
    max(filed_as_of_date) AS filed_as_of_date
  FROM activist_stocks
  GROUP BY cik, cusip, period_of_report),

final AS (
    SELECT a.cik, a.cusip, a.period_of_report,
        sum(market_value) AS market_value, sum(shares) AS shares
    FROM activist_stocks AS a
    INNER JOIN latest_filings AS b
    USING (cik, cusip, period_of_report, filed_as_of_date)
    GROUP BY a.cik, a.cusip, a.period_of_report
    ORDER BY cik, cusip, period_of_report),

activist_names AS (
    SELECT cik, array_agg(DISTINCT activist_name) AS activist_names
    FROM activist_director.activist_ciks
    GROUP BY cik)

SELECT activist_names, cusip, period_of_report,
    sum(market_value) AS market_value, sum(shares) AS shares
FROM final AS a
INNER JOIN activist_names AS b
ON a.cik=b.cik
GROUP BY activist_names, cusip, period_of_report
ORDER BY activist_names, cusip, period_of_report;


CREATE INDEX ON activist_director.activist_holdings (activist_names);

ALTER TABLE activist_director.activist_holdings
  OWNER TO activism;

SET enable_seqscan=TRUE;
