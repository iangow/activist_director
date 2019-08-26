library(dplyr, warn.conflicts = FALSE)
library(DBI)

# Data step ----
pg <- dbConnect(RPostgres::Postgres(), bigint = "integer")

rs <- dbExecute(pg, "
   CREATE OR REPLACE FUNCTION quarters_of(date)
   RETURNS int STRICT IMMUTABLE LANGUAGE sql AS $$
    SELECT extract(years FROM $1)::int * 4 + extract(quarter FROM $1)::int
  $$")

rs <- dbExecute(pg, "
  CREATE OR REPLACE FUNCTION quarters_between(date, date)
   RETURNS int STRICT IMMUTABLE LANGUAGE sql AS $$
     SELECT quarters_of($1) - quarters_of($2)
  $$;")

rs <- dbExecute(pg, "SET search_path TO activist_director, whalewisdom, public")
rs <- dbExecute(pg, "SET work_mem = '15GB'")

activism_events <- tbl(pg, "activism_events")

filers <- tbl(pg, "filers")
filing_stock_records <- tbl(pg, "filing_stock_records")
filings <- tbl(pg, "filings")

permnos <- tbl(pg, sql("SELECT * FROM factset.permnos"))
activist_ciks <- tbl(pg, sql("SELECT * FROM factset.activist_ciks"))
funda <- tbl(pg, sql("SELECT * FROM comp.funda"))
ccmxpf_linktable <- tbl(pg, sql("SELECT * FROM crsp.ccmxpf_linktable"))

activist_filers <-
    filings %>%
    inner_join(filers, by = "filer_id") %>%
    inner_join(activist_ciks, by = "cik") %>%
    compute(indexes = "filing_id")

activist_stocks <-
    activist_filers %>%
    inner_join(filing_stock_records, by = "filing_id") %>%
    mutate(cusip =
               case_when(
                   alt_cusip != ' ' ~ substr(alt_cusip, 1L, 8L),
                   alt_cusip == ' ' ~ substr(cusip_number, 1L, 8L),
                   is.na(alt_cusip) ~ substr(cusip_number, 1L, 8L))) %>%
    select(cik, period_of_report, filed_as_of_date, cusip,
           market_value, shares) %>%
    filter(!is.na(cusip)) %>%
    compute()

latest_filings <-
    activist_stocks %>%
    group_by(cik, cusip, period_of_report) %>%
    summarize(filed_as_of_date = max(filed_as_of_date, na.rm = TRUE)) %>%
    compute(indexes = c("cik", "period_of_report", "filed_as_of_date", "cusip"))

final_ah <-
    activist_stocks %>%
    inner_join(latest_filings,
               by = c("cik", "period_of_report", "filed_as_of_date", "cusip")) %>%
    group_by(cik, cusip, period_of_report) %>%
    summarize(market_value = sum(market_value, na.rm = TRUE),
              shares = sum(shares, na.rm = TRUE)) %>%
    compute()

final_ah %>% explain()

by_cik <-
    activist_ciks %>%
    select(cik, activist_name) %>%
    distinct() %>%
    group_by(cik) %>%
    summarize(activist_names = array_agg(activist_name)) %>%
    compute()

activist_names <-
    by_cik %>%
    select(activist_names, cik) %>%
    distinct() %>%
    group_by(activist_names) %>%
    summarize(ciks = array_agg(cik))

activist_holdings <-
    final_ah %>%
    inner_join(by_cik) %>%
    group_by(activist_names, cusip, period_of_report) %>%
    summarize(market_value = sum(market_value, na.rm = TRUE),
              shares = sum(shares, na.rm = TRUE)) %>%
    arrange(activist_names, cusip, period_of_report) %>%
    compute()

partitions <-
    activist_holdings %>%
    group_by(activist_names, cusip) %>%
    arrange(period_of_report) %>%
    mutate(lag_period = lag(period_of_report)) %>%
    mutate(new_holding =
               coalesce(lag_period < period_of_report - sql("interval '3 months'"),
                        TRUE)) %>%
    select(-lag_period) %>%
    ungroup() %>%
    compute()

window_nums <-
    partitions %>%
    group_by(activist_names, cusip) %>%
    arrange(period_of_report) %>%
    mutate(window_number = sum(as.integer(new_holding), na.rm = TRUE)) %>%
    ungroup()

entry_exit <-
    window_nums %>%
    group_by(activist_names, cusip, window_number) %>%
    summarize(entry_date = min(period_of_report, na.rm = TRUE),
              exit_date = max(period_of_report, na.rm = TRUE)) %>%
    ungroup() %>%
    compute()

holdings <-
    partitions %>%
    inner_join(entry_exit) %>%
    filter(shares > 0,
           between(period_of_report, entry_date, exit_date))

activist_dates <-
    holdings %>%
    group_by(activist_names) %>%
    summarize(first_date = min(period_of_report, na.rm = TRUE),
              last_date = max(period_of_report, na.rm = TRUE)) %>%
    ungroup()

activist_holdings_merged <-
    holdings %>%
    inner_join(activist_dates, by = "activist_names") %>%
    select(activist_names, period_of_report, cusip, shares, market_value,
           first_date, last_date, entry_date, exit_date) %>%
    compute()

cstat_fyears <-
    funda %>%
    filter(indfmt=='INDL', consol=='C', popsrc=='D', datafmt=='STD') %>%
    inner_join(ccmxpf_linktable, by = "gvkey") %>%
    filter(datadate >= linkdt,
           (datadate <= linkenddt | is.na(linkenddt)),
           usedflag=='1',
           linkprim %in% c('C', 'P')) %>%
    select(gvkey, datadate, lpermno) %>%
    rename(permno = lpermno) %>%
    distinct() %>%
    compute()

cusips <-
    activist_holdings %>%
    inner_join(
        permnos %>%
            rename(cusip = ncusip),
        by = "cusip") %>%
    inner_join(
        ccmxpf_linktable %>%
            rename(permno = lpermno),
        by = "permno") %>%
    filter(period_of_report >= linkdt,
           period_of_report <= linkenddt | is.na(linkenddt),
           usedflag == '1',
           linkprim %in% c('C', 'P')) %>%
    compute()

holdings_cstat_link <-
    cusips %>%
    inner_join(cstat_fyears, by = "gvkey") %>%
    filter(period_of_report >= datadate) %>%
    group_by(cusip, period_of_report, gvkey) %>%
    summarize(datadate = max(datadate, na.rm = TRUE)) %>%
    ungroup() %>%
    compute()

final <-
    holdings_cstat_link %>%
    group_by(cusip, gvkey) %>%
    arrange(period_of_report) %>%
    mutate(next_report_period = lead(period_of_report)) %>%
    ungroup() %>%
    compute()

activist_holdings_link <-
    final %>%
    inner_join(ccmxpf_linktable, by = "gvkey") %>%
    filter(datadate >= linkdt,
           datadate <= linkenddt | is.na(linkenddt),
           usedflag=='1',
           linkprim %in% c('C','P')) %>%
    distinct() %>%
    rename(permno = lpermno) %>%
    select(permno, period_of_report, next_report_period) %>%
    compute()

exit_qtr_1 <-
    activist_holdings_merged %>%
    left_join(activist_holdings_link, by = c("period_of_report", "cusip")) %>%
    left_join(permnos %>% rename(cusip = ncusip), by = "cusip") %>%
    mutate(permno = coalesce(permno.x, permno.y)) %>%
    mutate(quarter = quarters_between(period_of_report, entry_date)) %>%
    select(activist_names, cusip, permno, datadate,
           entry_date, exit_date, first_date, last_date,
           market_value, shares, period_of_report, quarter) %>%
    mutate(exit = FALSE) %>%
    distinct()

exit_qtr_2 <-
    activist_holdings_merged %>%
    left_join(activist_holdings_link, by = c("period_of_report", "cusip")) %>%
    left_join(permnos %>% rename(cusip = ncusip), by = "cusip") %>%
    mutate(permno = coalesce(permno.x, permno.y)) %>%
    mutate(next_period = eomonth(period_of_report + sql("interval '3 months'"))) %>%
    filter(next_period==period_of_report) %>%
    filter(period_of_report == exit_date,
           exit_date < last_date) %>%
    mutate(period_of_report = sql("next_period::date")) %>%
    mutate(quarter = quarters_between(period_of_report, entry_date) + 1L,
           market_value = 0, shares = 0) %>%
    select(activist_names, cusip, permno, datadate,
           entry_date, exit_date, first_date, last_date,
           market_value, shares, period_of_report, quarter) %>%
    mutate(exit = TRUE) %>%
    distinct()

exit_quarter_extra <-
    exit_qtr_1 %>%
    union(exit_qtr_2)

activism_linked <-
    activist_holdings_link %>%
    inner_join(activism_events, by = "permno") %>%
    filter(dissidents %&&% activist_names,
           between(eff_announce_date, entry_date - 90, exit_date) %>%
    select(activist_names, permno, first_appointment_date,
           eff_announce_date, category, affiliated, big_investment)

a.permno=e.permno AND (e.dissidents && a.activist_names)
               AND eff_announce_date BETWEEN entry_date - 90 AND exit_date)


activist_holdings <-
    exit_quarter_extra %>%
    left_join(activist_holdings_link,
              by = c("permno", "period_of_report"))


SELECT DISTINCT a.activist_names[1] AS activist_name, a.permno, a.datadate,
a.entry_date, a.exit_date, a.first_date, a.last_date,
a.market_value, a.shares, a.period_of_report, a.exit, a.quarter,
b.next_report_period,
e.first_appointment_date,
e.eff_announce_date,
e.eff_announce_date IS NOT NULL AS activism, e.category, e.affiliated, e.big_investment,
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



AS (
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
        LEFT JOIN activist_director.permnos AS c
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


SELECT DISTINCT a.activist_names, a.cusip, b.permno, c.datadate,
a.entry_date, a.exit_date,
a.first_date, a.last_date,

eomonth((a.period_of_report + INTERVAL '3 months')::DATE) AS period_of_report,
TRUE as EXIT,
quarters_between(a.period_of_report, entry_date) + 1 AS quarter
FROM activist_holdings_merged AS a
LEFT JOIN activist_holdings_link AS b
ON a.cusip=b.cusip AND a.period_of_report=b.period_of_report
LEFT JOIN activist_holdings_link AS c
ON a.cusip=c.cusip AND eomonth((a.period_of_report + INTERVAL '3 months')::DATE)=c.period_of_report
WHERE a.period_of_report = exit_date AND exit_date < last_date)

system.time({
# Takes ~23 minutes
holding_data <- dbGetQuery(pg, "
    SET work_mem='20GB';

    DROP TABLE IF EXISTS activist_director.activist_holdings;

    CREATE TABLE activist_director.activist_holdings AS




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
      INNER JOIN activist_director.permnos AS b
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
        LEFT JOIN activist_director.permnos AS c
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
        e.eff_announce_date IS NOT NULL AS activism, e.category, e.affiliated, e.big_investment,
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

sql <- "ALTER TABLE activist_holdings OWNER TO activism;"
rs <- dbExecute(pg, sql)

sql <- paste("
  COMMENT ON TABLE activist_holdings IS
    'CREATED USING create_activist_holdings.R ON ",
             format(Sys.time(), "%Y-%m-%d %X %Z"), "';", sep="")
rs <- dbGetQuery(pg, paste(sql, collapse="\n"))

dbDisconnect(pg)

