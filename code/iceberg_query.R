library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

temp <- dbGetQuery(pg, "
    WITH

    sharkwatch_permno AS (
        SELECT DISTINCT a.*, b.permno
        FROM factset.sharkwatch_new AS a
        INNER JOIN crsp.stocknames AS b
        ON substr(a.cusip_9_digit, 1, 8)=b.ncusip),

    stocknames AS (
        SELECT permno, array_agg(comnam) AS crsp_co_names
        FROM crsp.stocknames
        GROUP BY permno),

    by_cik AS (
        SELECT cik, array_agg(DISTINCT activist_name) AS activist_names
        FROM activist_director.activist_ciks
        GROUP BY cik),

    activist_cik_arrays AS (
        SELECT activist_names, array_agg(DISTINCT cik) AS ciks
        FROM by_cik
        GROUP BY activist_names),

    starboard_data AS (
        SELECT permno, d.cusip_number, min(c.period_of_report), max(c.period_of_report),
            bool_or(f.permno IS NOT NULL) AS on_sharkwatch
        FROM activist_cik_arrays AS a
        INNER JOIN whalewisdom.filers AS b
        ON b.cik=ANY(a.ciks)
        INNER JOIN whalewisdom.filings AS c
        USING (filer_id)
        INNER JOIN whalewisdom.filing_stock_records AS d
        USING (filing_id)
        LEFT JOIN crsp.stocknames AS e
        ON substr(d.cusip_number,1,8)=e.ncusip
        LEFT JOIN sharkwatch_permno AS f
        USING (permno)
        WHERE b.cik=1517137 --'Starboard Value LP'=ANY(activist_names)
        GROUP BY permno, d.cusip_number)

    SELECT *
    FROM starboard_data
    LEFT JOIN stocknames
    USING (permno)")

write.csv(temp, "~/Google Drive/activism/data/starboard_stocks.csv", row.names=FALSE)

rs <- dbDisconnect(pg)
