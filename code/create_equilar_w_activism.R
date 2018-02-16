library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

rs <-dbGetQuery(pg, "
    SET work_mem='10GB';

    DROP TABLE IF EXISTS activist_director.equilar_w_activism;

    CREATE TABLE activist_director.equilar_w_activism AS

    WITH
    -- Pull together director characteristics
    equilar AS (
        SELECT DISTINCT a.company_id, executive_id, a.period,
            (director.parse_name(director_name)).*, director_name AS director,
            date_start, age, (a.period - date_start)/365.25 AS tenure_calc, tenure,
            gender='F' AS female, gender='M' AS male,
            insider_outsider_related='Outsider' AS outsider, insider_outsider_related='Insider' AS insider,
            cmtes_cnt, cmtes, cmtes_cnt > 0 AS any_committee,
            CASE WHEN cmtes IS NOT NULL THEN COALESCE(cmtes ~ 'Comp', FALSE)
            WHEN cmtes_cnt = 0 THEN FALSE END AS comp_committee,
            CASE WHEN cmtes IS NOT NULL THEN COALESCE(cmtes ~ 'Audit', FALSE)
            WHEN cmtes_cnt = 0 THEN FALSE END AS audit_committee,
            is_chair, is_vice_chair, is_lead, is_audit_cmte_spec,
            is_audit_cmte_spec AS audit_committee_financial_expert
        FROM equilar_hbs.director_index AS a
        INNER JOIN equilar_hbs.company_financials AS c
        ON a.company_id=c.company_id AND a.period=c.fye
        WHERE a.period > '2003-12-31'
        ORDER BY company_id, executive_id, period),

    -- Match Equilar to PERMCOs
    equilar_permnos AS (
        SELECT DISTINCT c.permco, b.permno, company_id AS company_id, fye AS period
        FROM equilar_hbs.company_financials AS a
        LEFT JOIN activist_director.permnos AS b
        ON substr(a.cusip, 1, 8)=b.ncusip
        INNER JOIN crsp.stocknames AS c
        ON b.permno=c.permno),

    -- Identify companies' first years
    company_first_years AS (
        SELECT company_id AS company_id, min(fye) AS period
        FROM equilar_hbs.company_financials AS a
        GROUP BY company_id
        ORDER BY company_id),

    -- Identify directors' first years
    director_first_years AS (
        SELECT company_id AS company_id, executive_id,
            min(a.date_start) AS date_start,
            min(a.period) AS period
        FROM equilar_hbs.director_index AS a
        GROUP BY company_id, executive_id
        ORDER BY company_id, executive_id),

    -- Classify directors' first years on Equilar based on whether
    -- they were appointed during an activism event or shortly thereafter
    equilar_activism_match AS (
        SELECT DISTINCT b.permno, company_id, executive_id, period,
            bool_or(sharkwatch50) AS sharkwatch50,
            bool_or(activism) AS activism_firm,
            bool_or(activist_demand) AS activist_demand_firm,
            bool_or(activist_director) AS activist_director_firm
        FROM director_first_years AS a
        INNER JOIN equilar_permnos AS b
        USING (company_id, period)
        LEFT JOIN activist_director.activism_events AS c
        ON b.permno=c.permno AND
        a.date_start BETWEEN c.first_date AND c.end_date + interval '128 days'
        GROUP BY b.permno, company_id, executive_id, period
        ORDER BY permno, company_id, executive_id)

    -- Now pull all directors from Equilar and add data on activism from above
    SELECT DISTINCT c.permno, a.*,
        b.period IS NOT NULL AS firm_first_year,
        c.period IS NOT NULL AS director_first_year,
        COALESCE(c.sharkwatch50, FALSE) AS sharkwatch50,
        COALESCE(c.activism_firm, FALSE) AS activism_firm,
        COALESCE(c.activist_demand_firm, FALSE) AS activist_demand_firm,
        COALESCE(c.activist_director_firm, FALSE) AS activist_director_firm,
        CASE
        WHEN activist_director_firm THEN 'activist_director_firm'
        WHEN activist_demand_firm THEN 'activist_demand_firm'
        WHEN activism_firm THEN 'activism_firm'
        ELSE '_none' END AS category,
        d.executive_id IS NOT NULL --AND NOT d.prior_director
                AS activist_director,
        d.independent IS FALSE AS affiliated_director,
        d.independent IS TRUE AS independent --, d.prior_director IS TRUE AS prior_director
    FROM equilar AS a
    LEFT JOIN company_first_years AS b
    ON a.company_id=b.company_id AND a.period=b.period
    INNER JOIN equilar_activism_match AS c
    ON a.company_id=c.company_id
    AND a.executive_id=c.executive_id
    AND a.period=c.period
    LEFT JOIN activist_director.activist_director_equilar AS d
    ON a.company_id=d.company_id
    AND a.executive_id=d.executive_id
    AND a.period=d.period
    ORDER BY permno, period, executive_id;
    --Query returned in 108940ms")

rs <- dbGetQuery(pg, "
    ALTER TABLE activist_director.equilar_w_activism OWNER TO activism")

sql <- paste("
  COMMENT ON TABLE activist_director.equilar_w_activism IS
    'CREATED USING create_equilar_w_activism ON ", Sys.time() , "';", sep="")
rs <- dbGetQuery(pg, paste(sql, collapse="\n"))

dbDisconnect(pg)
