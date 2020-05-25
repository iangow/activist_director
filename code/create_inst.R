library(DBI)
library(dplyr, warn.conflicts = FALSE)

pg <- dbConnect(RPostgres::Postgres(), bigint = "integer")

rs <- dbExecute(pg, "SET search_path TO activist_director, whalewisdom")
rs <- dbExecute(pg, "SET work_mem='10GB';")

filings <- tbl(pg, "filings")
filing_stock_records <- tbl(pg, "filing_stock_records")
permnos <- tbl(pg, "permnos")
funda <- tbl(pg, sql("SELECT * FROM comp.funda"))
ccmxpf_linktable <- tbl(pg, sql("SELECT * FROM crsp.ccmxpf_linktable"))

latest_filings <-
    filings %>%
    group_by(filer_id, period_of_report) %>%
    summarize(filed_as_of_date = max(filed_as_of_date, na.rm = TRUE)) %>%
    compute()

latest_filing_ids <-
    filings %>%
    inner_join(latest_filings,
               by = c("filer_id", "period_of_report", "filed_as_of_date")) %>%
    select(filer_id, period_of_report, filing_id) %>%
    compute()


filing_stock_records_mod <-
    filing_stock_records %>%
    select(cusip_number, id, filing_id, stock_id, shares, security_type) %>%
    distinct()

shares <-
    filing_stock_records_mod %>%
    inner_join(latest_filing_ids, by = "filing_id") %>%
    group_by(cusip_number, period_of_report) %>%
    summarize(shares = sum(shares, na.rm=TRUE)) %>%
    compute()

shares_w_permno <-
    shares %>%
    mutate(ncusip = substr(cusip_number, 1L, 8L)) %>%
    inner_join(permnos, by = "ncusip") %>%
    select(-ncusip)

shares2 <-
    shares_w_permno %>%
    group_by(permno, period_of_report) %>%
    summarize(shares = sum(shares, na.rm=TRUE)) %>%
    compute()

comp_link <-
    ccmxpf_linktable %>%
    filter(usedflag==1,  linkprim %in% c('C', 'P')) %>%
    select(gvkey, lpermno, linkdt, linkenddt) %>%
    rename(permno = lpermno) %>%
    compute()

compustat <-
    funda %>%
    filter(indfmt=='INDL', consol=='C', popsrc=='D', datafmt=='STD') %>%
    filter(datadate > '2000-01-01') %>%
    select(gvkey, datadate, csho) %>%
    inner_join(comp_link, by = "gvkey") %>%
    filter(datadate >= linkdt, datadate <= linkenddt | is.na(linkenddt)) %>%
    select(-linkdt, -linkenddt) %>%
    compute()

rs <- dbExecute(pg, "DROP TABLE IF EXISTS inst")

inst <-
    shares2 %>%
    inner_join(compustat, by="permno") %>%
    filter(between(period_of_report,
                   sql("datadate - interval '3 months - 2 days'"), datadate)) %>%
    mutate(shares_outstanding = csho * 1000000.0) %>%
    mutate(inst = if_else(shares_outstanding > 0, shares/shares_outstanding, NA_real_)) %>%
    select(permno, datadate, period_of_report, shares, shares_outstanding, inst) %>%
    compute(name = "inst", temporary = FALSE)

rs <- dbExecute(pg, "ALTER TABLE inst OWNER TO activism")

sql <- paste0("
    COMMENT ON TABLE inst IS 'CREATED USING create_inst.R ON ",
              format(Sys.time(), "%Y-%m-%d %X %Z"), "';")

rs <- dbExecute(pg, sql)

rs <- dbDisconnect(pg)
