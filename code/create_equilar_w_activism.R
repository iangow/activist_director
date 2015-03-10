library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

rs <-dbGetQuery(pg, "
  SET work_mem='10GB';

  DROP TABLE IF EXISTS activist_director.equilar_w_activism;

  CREATE TABLE activist_director.equilar_w_activism AS

  WITH
      -- Pull together director characteristics
    equilar AS (
        SELECT DISTINCT equilar_id(director_id) AS equilar_id,
            director_id(director_id) AS equilar_director_id,
            director_id, a.fy_end,
            gender ='F' AS female, gender='M' AS male, age,
            (a.fy_end - start_date)/365 AS tenure,
             (director.parse_name(director)).*, director,
            start_date, insider_outsider_related='Outsider' AS outsider,
            num_committees > 0 AS any_committee,
            committees ~ 'Comp' AS comp_committee,
            committees ~ 'Audit' AS audit_committee,
            audit_committee_financial_expert
        FROM director.director AS a
        INNER JOIN director.co_fin AS c
        ON equilar_id(a.director_id)=equilar_id(c.company_id) AND a.fy_end=c.fy_end
        WHERE a.fy_end > '2003-12-31'),

    -- Match Equilar to PERMCOs
    equilar_permnos AS (
        SELECT DISTINCT c.permco, b.permno, equilar_id(company_id) AS equilar_id, fy_end
        FROM director.co_fin AS a
        LEFT JOIN activist_director.permnos AS b
        ON substr(a.cusip, 1, 8)=b.ncusip
        INNER JOIN crsp.stocknames AS c
        ON b.permno=c.permno),

    -- Identify companies' first years
    company_first_years AS (
       SELECT equilar_id(company_id) AS equilar_id,
            min(fy_end) AS fy_end
        FROM director.co_fin AS a
        GROUP BY equilar_id(company_id)),

    -- Identify directors' first years
    director_first_years AS (
       SELECT equilar_id(director_id) AS equilar_id,
            director_id(director_id) AS equilar_director_id,
						min(a.start_date) AS start_date, min(a.fy_end) AS fy_end
        FROM director.director AS a
        GROUP BY equilar_id(director_id), director_id(director_id)),

    -- Classify directors' first years on Equilar based on whether
    -- they were appointed during an activism event or shortly thereafter
    equilar_activism_match AS (
        SELECT DISTINCT b.permno, equilar_id, equilar_director_id, fy_end,
            bool_or(sharkwatch50) AS sharkwatch50,
            bool_or(activism) AS activism_firm,
						bool_or(activist_demand) AS activist_demand_firm,
            bool_or(activist_director) AS activist_director_firm
        FROM director_first_years AS a
        INNER JOIN equilar_permnos AS b
        USING (equilar_id, fy_end)
        LEFT JOIN activist_director.activism_events AS c
        ON b.permco=c.permco AND
            a.start_date BETWEEN c.first_date AND c.end_date + interval '128 days'
        GROUP BY b.permno, equilar_id, equilar_director_id, fy_end)

    -- Now pull all directors from Equilar and add data on activism from above
    SELECT DISTINCT a.*, b.fy_end IS NOT NULL AS co_first_year,
		c.fy_end IS NOT NULL AS director_first_year,
        COALESCE(c.sharkwatch50, FALSE) AS sharkwatch50,
        COALESCE(c.activism_firm, FALSE) AS activism_firm,
        COALESCE(c.activist_demand_firm, FALSE) AS activist_demand_firm,
        COALESCE(c.activist_director_firm, FALSE) AS activist_director_firm,
        CASE
            WHEN activist_director_firm THEN 'activist_director_firm'
            WHEN activist_demand_firm THEN 'activist_demand_firm'
            WHEN activism_firm THEN 'activism_firm'
            ELSE '_none'
        END AS category,
        d.equilar_director_id IS NOT NULL AND NOT d.prior_director
            AS activist_director,
        d.activist_affiliate IS TRUE AS affiliated_director,
        d.prior_director IS TRUE AS prior_director
    FROM equilar AS a
    LEFT JOIN company_first_years AS b
    ON a.equilar_id=b.equilar_id AND a.fy_end=b.fy_end
    LEFT JOIN equilar_activism_match AS c
    ON a.equilar_id=c.equilar_id
        AND a.equilar_director_id=c.equilar_director_id
        AND a.fy_end=c.fy_end
    LEFT JOIN activist_director.activist_director_equilar AS d
    ON a.equilar_id=d.equilar_id
        AND a.equilar_director_id=d.equilar_director_id
        AND a.fy_end=d.fy_end
    ORDER BY equilar_id, fy_end, director_id")

rs <- dbGetQuery(pg, "
    ALTER TABLE activist_director.equilar_w_activism OWNER TO activism")

sql <- paste("
  COMMENT ON TABLE activist_director.equilar_w_activism IS
    'CREATED USING create_equilar_w_activism ON ", Sys.time() , "';", sep="")
rs <- dbGetQuery(pg, paste(sql, collapse="\n"))

dbDisconnect(pg)
