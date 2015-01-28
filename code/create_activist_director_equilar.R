library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

rs <-dbGetQuery(pg, "

  SET work_mem='10GB';

  DROP TABLE IF EXISTS activist_director.activist_director_equilar;

  CREATE TABLE activist_director.activist_director_equilar AS
  WITH permnos AS (
        SELECT DISTINCT cusip, permno, permco
        FROM activist_director.permnos
        INNER JOIN crsp.stocknames
        USING (permno)),

    equilar AS (
        SELECT DISTINCT equilar_id(a.director_id) AS equilar_id,
            director_id(director_id) AS equilar_director_id, director,
            (director.parse_name(director)).*, a.fy_end, start_date,
            substr(cusip,1,8) AS cusip
        FROM director.director AS a
        LEFT JOIN director.co_fin AS b
        ON equilar_id(a.director_id)=equilar_id(b.company_id)
            AND a.fy_end=b.fy_end),

    equilar_w_permnos AS (
          SELECT *
          FROM equilar AS a
          LEFT JOIN permnos AS b
          USING (cusip)),

    first_name_years AS (
          SELECT equilar_id, equilar_director_id,
              min(fy_end) AS fy_end
          FROM equilar_w_permnos
          GROUP BY equilar_id, equilar_director_id),

    equilar_final AS (
        SELECT equilar_id, equilar_director_id, fy_end,
            b.director, b.first_name, b.last_name, b.permno, b.permco
        FROM first_name_years AS a
        INNER JOIN equilar_w_permnos AS b
        USING (equilar_id, equilar_director_id, fy_end)),

    activist_directors AS (
        SELECT DISTINCT a.campaign_id, a.first_name, a.last_name,
            a.activist_affiliate, a.appointment_date,
            a.appointment_date < c.eff_announce_date AS prior_director,
            c.eff_announce_date, c.first_date,
            a.retirement_date,
            b.permno, b.permco,
            c.campaign_ids IS NOT NULL AS on_activism_events
        FROM activist_director.activist_directors AS a
        LEFT JOIN permnos AS b
        ON substr(a.cusip_9_digit, 1, 8)=b.cusip
        LEFT JOIN activist_director.activism_events AS c
        ON a.campaign_id=ANY(c.campaign_ids)),

    activist_director_equilar AS (
        SELECT DISTINCT a.*,
            COALESCE(b.equilar_id, c.equilar_id, d.equilar_id, e.equilar_id)
            AS equilar_id,
            COALESCE(b.equilar_director_id, c.equilar_director_id,
                d.equilar_director_id, e.equilar_director_id)
            AS equilar_director_id,
            COALESCE(b.fy_end, c.fy_end, d.fy_end, e.fy_end) AS fy_end,
            COALESCE(b.first_name, c.first_name, d.first_name, e.first_name)
            AS equilar_first_name,
            COALESCE(b.last_name, c.last_name, d.last_name, e.last_name)
            AS equilar_last_name,
            f.permco IS NOT NULL AS permco_on_equilar
        FROM activist_directors AS a
        LEFT JOIN equilar_final AS b
        ON a.permco=b.permco AND lower(a.last_name)=lower(b.last_name)
            AND lower(a.first_name)=lower(b.first_name)
        LEFT JOIN equilar_final AS c
        ON a.permco=c.permco AND lower(a.last_name)=lower(c.last_name)
            AND substr(lower(a.first_name),1,2)=substr(lower(c.first_name),1,2)
        LEFT JOIN equilar_final AS d
        ON a.permco=d.permco AND lower(a.last_name)=lower(d.last_name)
            AND substr(lower(a.first_name),1,1)=substr(lower(c.first_name),1,1)
        LEFT JOIN equilar_final AS e
        ON a.permco=e.permco AND lower(a.last_name)=lower(e.last_name)
        LEFT JOIN equilar_final AS f
        ON a.permco=f.permco)

    SELECT *, equilar_last_name IS NOT NULL AS matched_to_equilar
    FROM activist_director_equilar;

    ALTER TABLE activist_director.activist_director_equilar OWNER TO activism;

    CREATE INDEX ON activist_director.activist_director_equilar (permno);
")

sql <- paste("
  COMMENT ON TABLE activist_director.activist_director_equilar IS
    'CREATED USING create_activism_director_equilar ON ", Sys.time() , "';", sep="")
rs <- dbGetQuery(pg, paste(sql, collapse="\n"))

matched_data <- dbGetQuery(pg, "SELECT *
   FROM activist_director.activist_director_equilar")
