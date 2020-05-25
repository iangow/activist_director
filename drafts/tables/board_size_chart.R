source("https://raw.githubusercontent.com/iangow/acct_data/master/code/cluster2.R")

pg <- dbConnect(RPostgreSQL::PostgreSQL())

chart_data <- dbGetQuery(pg, "
WITH num_directors AS (
    SELECT DISTINCT company_id, period, sum(own_board::INT) AS num_directors
    FROM activist_director.equilar_career AS a
    GROUP BY company_id, period
    ORDER BY company_id, period),

lead_lags AS (
    SELECT DISTINCT company_id, period,
    lag(num_directors, 3) OVER w AS num_directors_m3,
    lag(num_directors, 2) OVER w AS num_directors_m2,
    lag(num_directors, 1) OVER w AS num_directors_m1,
    num_directors,
    lead(num_directors, 1) OVER w AS num_directors_p1,
    lead(num_directors, 2) OVER w AS num_directors_p2,
    lead(num_directors, 3) OVER w AS num_directors_p3
    FROM num_directors
    WINDOW w AS (PARTITION BY company_id ORDER BY period)
    ORDER BY company_id, period),

FINAL AS (
    SELECT DISTINCT d.permno, datadate, affiliated, num_directors_m3, num_directors_m2, num_directors_m1, a.num_directors, num_directors_p1, num_directors_p2, num_directors_p3
    FROM lead_lags AS a
    INNER JOIN equilar_hbs.company_financials AS b
    ON a.company_id=b.company_id
    INNER JOIN activist_director.permnos AS c
    ON substr(b.cusip,1,8)=c.ncusip
    INNER JOIN activist_director.outcome_controls AS d
    ON c.permno=d.permno AND a.period=d.datadate
    ORDER BY permno, datadate)

SELECT DISTINCt affiliated, avg(num_directors_m3) AS num_directors_m3, avg(num_directors_m2) AS num_directors_m2, avg(num_directors_m1) AS num_directors_m1,
    avg(num_directors) AS num_directors,
    avg(num_directors_p1) AS num_directors_p1, avg(num_directors_p2) AS num_directors_p2, avg(num_directors_p3) AS num_directors_p3
FROM FINAL
WHERE num_directors_m3 IS NOT NULL
AND num_directors_m2 IS NOT NULL
AND num_directors_m1 IS NOT NULL
AND num_directors IS NOT NULL
AND num_directors_p1 IS NOT NULL
AND num_directors_p2 IS NOT NULL
AND num_directors_p3 IS NOT NULL
GROUP BY affiliated
ORDER BY affiliated
")


