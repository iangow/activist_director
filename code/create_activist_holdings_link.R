library(RPostgreSQL)
drv <- dbDriver("PostgreSQL")
pg <- dbConnect(drv, dbname="crsp")

# Data step ----
system.time({
# Takes ~5 minutes
entry_exit <- dbGetQuery(pg, "
  SET work_mem = '18GB';
  DROP TABLE IF EXISTS activist_director.activist_holdings_link;

  CREATE TABLE activist_director.activist_holdings_link AS
  WITH
  cstat_fyears AS (
      SELECT DISTINCT a.gvkey, a.datadate, b.lpermno AS permno
      FROM comp.funda AS a
      INNER JOIN crsp.ccmxpf_linktable AS b
      ON a.gvkey=b.gvkey 
          AND a.datadate >= b.linkdt 
          AND (a.datadate <= b.linkenddt OR b.linkenddt IS NULL) 
          AND b.USEDFLAG='1' 
          AND linkprim IN ('C', 'P')
      WHERE indfmt='INDL' AND consol='C' AND popsrc='D' AND datafmt='STD'),
  
  cusips  AS (
      SELECT DISTINCT cusip, period_of_report, gvkey
      FROM activist_director.activist_holdings AS a
      INNER JOIN activist_director.permnos AS b
      ON a.cusip=b.ncusip  
      INNER JOIN crsp.ccmxpf_linktable AS c
      ON b.permno=c.lpermno 
          AND a.period_of_report >= c.linkdt 
          AND (a.period_of_report <= c.linkenddt OR c.linkenddt IS NULL) 
          AND c.USEDFLAG='1' 
          AND c.linkprim IN ('C', 'P')
  ),

  holdings_cstat_link AS (
      SELECT DISTINCT cusip, period_of_report, a.gvkey,
          max(b.datadate) AS datadate
      FROM cusips AS a
      INNER JOIN cstat_fyears AS b
      ON a.gvkey=b.gvkey
      WHERE a.period_of_report >= b.datadate
      GROUP BY cusip, period_of_report, a.gvkey),
	  
  final AS (
	  SELECT DISTINCT *, lead(period_of_report) OVER w AS next_report_period
	  FROM holdings_cstat_link
	  WINDOW w AS (PARTITION BY cusip, gvkey ORDER BY period_of_report))
	  
  SELECT DISTINCT lpermno AS permno, a.*
  FROM final AS a
  INNER JOIN crsp.ccmxpf_linktable AS b
  ON a.gvkey=b.gvkey 
	AND a.datadate >= b.linkdt AND (a.datadate <= b.linkenddt OR b.linkenddt IS NULL) 
	AND b.USEDFLAG='1' AND linkprim IN ('C','P');

  CREATE INDEX ON activist_director.activist_holdings_link (cusip, period_of_report);

  CREATE INDEX ON activist_director.activist_holdings_link (gvkey, datadate);
  
  ALTER TABLE activist_director.activist_holdings_link
      OWNER TO activism;
")
})
