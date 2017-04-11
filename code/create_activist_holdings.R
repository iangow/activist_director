library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

# Data step ----
rs <- dbGetQuery(pg, "
   CREATE OR REPLACE FUNCTION quarters_of(date)
   RETURNS int STRICT IMMUTABLE LANGUAGE sql AS $$
    SELECT extract(years FROM $1)::int * 4 + extract(quarter FROM $1)::int
  $$;

  CREATE OR REPLACE FUNCTION quarters_between(date, date)
   RETURNS int STRICT IMMUTABLE LANGUAGE sql AS $$
     SELECT quarters_of($1) - quarters_of($2)
  $$;")

system.time({
# Takes ~23 minutes
holding_data <- dbGetQuery(pg, "
    SET work_mem='20GB';

    DROP TABLE IF EXISTS activist_director.activist_holdings;

    CREATE TABLE activist_director.activist_holdings AS

    WITH
    activist_filers AS (
        SELECT DISTINCT b.filing_id, c.cik, b.period_of_report, b.filed_as_of_date
        FROM whalewisdom.filings AS b
        INNER JOIN whalewisdom.filers AS c
        USING (filer_id)
        INNER JOIN activist_director.activist_ciks AS e
        USING (cik)),

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
        USING (filing_id)
        WHERE substr(COALESCE(a.alt_cusip, a.cusip_number),1,8) IS NOT NULL
            OR substr(COALESCE(a.alt_cusip, a.cusip_number),1,8) != ' '),

    latest_filings AS (
        SELECT DISTINCT cik, cusip, period_of_report,
            max(filed_as_of_date) AS filed_as_of_date
        FROM activist_stocks
        GROUP BY cik, cusip, period_of_report),

    final_ah AS (
        SELECT a.cik, a.cusip, a.period_of_report,
            sum(market_value) AS market_value, sum(shares) AS shares
        FROM activist_stocks AS a
        INNER JOIN latest_filings AS b
        USING (cik, cusip, period_of_report, filed_as_of_date)
        GROUP BY a.cik, a.cusip, a.period_of_report
        ORDER BY cik, cusip, period_of_report),

    by_cik AS (
        SELECT cik, array_agg(DISTINCT activist_name) AS activist_names
        FROM activist_director.activist_ciks
        GROUP BY cik),

    activist_names AS (
        SELECT activist_names, array_agg(DISTINCT cik) AS ciks
        FROM by_cik
        GROUP BY activist_names),

    activist_holdings AS (
        SELECT activist_names, cusip, period_of_report,
            sum(market_value) AS market_value, sum(shares) AS shares
        FROM final_ah AS a
        INNER JOIN activist_names AS b
        ON a.cik=ANY(b.ciks)
        GROUP BY activist_names, cusip, period_of_report),

    partitions AS (
        SELECT activist_names, cusip,
            sum(shares) AS shares, sum(market_value) AS market_value,
            period_of_report,
            COALESCE(lag(period_of_report) OVER w
                < period_of_report - interval '3 months', TRUE) AS new_holding
        FROM activist_holdings AS a
        GROUP BY activist_names, cusip, period_of_report
        WINDOW w AS (PARTITION BY activist_names, cusip ORDER BY period_of_report)
        ORDER BY activist_names, cusip, period_of_report),

    window_nums AS (
        SELECT activist_names, cusip, shares, period_of_report,
            sum(new_holding::integer) OVER w AS window_number
        FROM partitions
        WINDOW w AS (PARTITION BY activist_names, cusip ORDER BY period_of_report)),

    entry_exit AS (
        SELECT activist_names, cusip,
            min(period_of_report) AS entry_date,
            max(period_of_report) AS exit_date
        FROM window_nums
        GROUP BY activist_names, cusip, window_number),

    holdings AS (
        SELECT DISTINCT *
        FROM partitions
        INNER JOIN entry_exit
        USING (activist_names, cusip)
        WHERE shares>0
            AND period_of_report BETWEEN entry_date AND exit_date
        ORDER BY activist_names, cusip, period_of_report),

    activist_dates AS (
        SELECT activist_names,
            min(period_of_report) AS first_date,
            max(period_of_report) AS last_date
        FROM holdings
        GROUP BY activist_names),

    activist_holdings_merged AS (
        SELECT DISTINCT activist_names, period_of_report, cusip, shares, market_value,
            first_date, last_date, entry_date, exit_date
        FROM holdings AS a
        INNER JOIN activist_dates
        USING (activist_names)),

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

  cusips AS (
      SELECT DISTINCT cusip, period_of_report, gvkey
      FROM activist_holdings AS a
      INNER JOIN factset.permnos AS b
      ON a.cusip=b.ncusip
      INNER JOIN crsp.ccmxpf_linktable AS c
      ON b.permno=c.lpermno
          AND a.period_of_report >= c.linkdt
          AND (a.period_of_report <= c.linkenddt OR c.linkenddt IS NULL)
          AND c.USEDFLAG='1'
          AND c.linkprim IN ('C', 'P')),

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
	  WINDOW w AS (PARTITION BY cusip, gvkey ORDER BY period_of_report)),

  activist_holdings_link AS (
    SELECT DISTINCT lpermno AS permno, a.*
    FROM final AS a
    INNER JOIN crsp.ccmxpf_linktable AS b
    ON a.gvkey=b.gvkey
      AND a.datadate >= b.linkdt AND (a.datadate <= b.linkenddt OR b.linkenddt IS NULL)
      AND b.USEDFLAG='1' AND linkprim IN ('C','P')),

  exit_quarter_extra AS (
        SELECT DISTINCT a.activist_names, a.cusip,
            COALESCE(b.permno,c.permno) AS permno, datadate,
            a.entry_date, a.exit_date,
            a.first_date, a.last_date,
            a.market_value, a.shares, a.period_of_report,
            FALSE as EXIT,
            quarters_between(a.period_of_report, entry_date) AS quarter
        FROM activist_holdings_merged AS a
        LEFT JOIN activist_holdings_link AS b
        ON a.cusip=b.cusip AND a.period_of_report=b.period_of_report
        LEFT JOIN factset.permnos AS c
        ON a.cusip=c.ncusip

      UNION

        SELECT DISTINCT a.activist_names, a.cusip, b.permno, c.datadate,
              a.entry_date, a.exit_date,
              a.first_date, a.last_date,
              0 AS market_value, 0 AS shares,
              eomonth((a.period_of_report + INTERVAL '3 months')::DATE) AS period_of_report,
              TRUE as EXIT,
              quarters_between(a.period_of_report, entry_date) + 1 AS quarter
          FROM activist_holdings_merged AS a
          LEFT JOIN activist_holdings_link AS b
          ON a.cusip=b.cusip AND a.period_of_report=b.period_of_report
          LEFT JOIN activist_holdings_link AS c
          ON a.cusip=c.cusip AND eomonth((a.period_of_report + INTERVAL '3 months')::DATE)=c.period_of_report
          WHERE a.period_of_report = exit_date AND exit_date < last_date)

    SELECT DISTINCT a.activist_names[1] AS activist_name, a.permno, a.datadate,
        a.entry_date, a.exit_date, a.first_date, a.last_date,
        a.market_value, a.shares, a.period_of_report, a.exit, a.quarter,
        b.next_report_period,
        e.first_appointment_date,
        e.eff_announce_date,
        e.eff_announce_date IS NOT NULL AS activism, e.category, e.big_investment,
        COALESCE(e.activist_demand, FALSE) AS activist_demand,
        COALESCE(e.activist_director, FALSE) AS activist_director,
        COALESCE(a.period_of_report >= e.eff_announce_date, FALSE) AS activism_announced,
        COALESCE(a.period_of_report >= e.first_appointment_date, FALSE) AS director_appt,
        COALESCE(e.eff_announce_date
            BETWEEN a.period_of_report + interval '1 day'
            AND next_report_period, FALSE) AS activism_quarter,
        COALESCE(e.first_appointment_date
            BETWEEN a.period_of_report + interval '1 day'
            AND next_report_period, FALSE) AS appt_quarter
    FROM exit_quarter_extra AS a
    LEFT JOIN activist_holdings_link AS b
    ON a.permno=b.permno AND a.period_of_report=b.period_of_report
    LEFT JOIN activist_director.activism_events AS e
    ON a.permno=e.permno AND (e.dissidents && a.activist_names)
    AND eff_announce_date BETWEEN entry_date - 90 AND exit_date
    ORDER BY activist_name, permno, entry_date, eff_announce_date,
        period_of_report, quarter;

    ALTER TABLE activist_director.activist_holdings OWNER TO activism")
})

sql <- "ALTER TABLE activist_director.activist_holdings OWNER TO activism;"
rs <- dbGetQuery(pg, sql)

sql <- paste("
  COMMENT ON TABLE activist_director.activist_holdings IS
    'CREATED USING create_activist_holdings.R ON ", Sys.time() , "';", sep="")
rs <- dbGetQuery(pg, paste(sql, collapse="\n"))

dbDisconnect(pg)

