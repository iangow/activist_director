library(RPostgreSQL)
pg <- dbConnect(PostgreSQL(), host='iangow.me', port='5432', dbname='crsp')

# Match with Equilar - create_activist_director_equilar ----

activist_directors_equilar <- dbGetQuery(pg, "

    WITH permnos AS (
      SELECT DISTINCT cusip, permno, permco
      FROM factset.permnos
      INNER JOIN crsp.stocknames
      USING (permno)),

    equilar AS (
      SELECT DISTINCT company_id AS firm_id, director_id, director_name AS director,
          (director.parse_name(director_name)).*, a.fy_end, date_start AS start_date,
          substr(cusip,1,8) AS cusip
      FROM director.director AS a
      LEFT JOIN director.co_fin AS b
      USING (company_id, fy_end)),

    equilar_w_permnos AS (
      SELECT *
      FROM equilar AS a
      INNER JOIN permnos AS b
      USING (cusip)),

    first_name_years AS (
      SELECT firm_id, director_id, min(fy_end) AS fy_end
      FROM equilar_w_permnos
      GROUP BY firm_id, director_id),

    equilar_final AS (
      SELECT firm_id, director_id, fy_end,
          b.director, b.first_name, b.last_name, b.permno, b.permco
      FROM first_name_years AS a
      INNER JOIN equilar_w_permnos AS b
      USING (firm_id, director_id, fy_end)
      ORDER BY firm_id, director_id, fy_end),

    activist_directors AS (
      SELECT DISTINCT a.campaign_id, a.first_name, a.last_name,
          a.activist_affiliate, a.appointment_date,
          -- a.appointment_date < c.eff_announce_date AS prior_director,
          -- c.eff_announce_date, c.first_date,
          a.retirement_date,
          b.permno, b.permco
          -- c.campaign_ids IS NOT NULL AS on_activism_events
      FROM activist_director.activist_directors AS a
      LEFT JOIN permnos AS b
      ON substr(a.cusip_9_digit, 1, 8)=b.cusip
      --LEFT JOIN activist_director.activism_events AS c
      --ON a.campaign_id=ANY(c.campaign_ids)
      ),

    activist_director_equilar AS (
      SELECT DISTINCT a.*,
          COALESCE(b.firm_id, c.firm_id, d.firm_id, e.firm_id) AS firm_id,
          COALESCE(b.director_id, c.director_id, d.director_id, e.director_id) AS equilar_director_id,
          COALESCE(b.fy_end, c.fy_end, d.fy_end, e.fy_end) AS fy_end,
          COALESCE(b.first_name, c.first_name, d.first_name, e.first_name) AS equilar_first_name,
          COALESCE(b.last_name, c.last_name, d.last_name, e.last_name) AS equilar_last_name,
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
")

rs <- dbWriteTable(pg, c("activist_director", "activist_director_equilar"), activist_directors_equilar,
                   overwrite=TRUE, row.names=FALSE)


# Match with BoardEx - create_activist_director_boardex ----
activist_directors_boardex <- dbGetQuery(pg, "
  WITH permnos AS (
  SELECT DISTINCT cusip, permno, permco
  FROM crsp.stocknames),

  boardex AS (
  SELECT DISTINCT CASE WHEN substr(d.isin,1,2)='US' THEN substr(d.isin,3,8) END AS cusip,
  c.annual_report_date, a.boardid, a.directorid,
  b.last_name, b.first_name
  FROM boardex.director_characteristics AS a
  INNER JOIN activist_director.director_names AS b
  ON a.director_name=b.directorname
  INNER JOIN boardex.board_characteristics AS c
  ON a.boardid=c.boardid
  AND a.annual_report_date=c.annual_report_date
  INNER JOIN boardex.company_profile_stocks AS d
  ON a.boardid=d.boardid
  --INNER JOIN crsp.stocknames AS e
  --ON CASE WHEN substr(d.isin,1,2)='US' THEN substr(d.isin,3,8) END=e.ncusip
  WHERE a.row_type='Board Member' AND a.annual_report_date IS NOT NULL
  --WHERE a.boardid='12212'
  ORDER BY cusip, annual_report_date, last_name, first_name),

  boardex_w_permnos AS (
  SELECT *
  FROM boardex AS a
  INNER JOIN permnos AS b
  USING (cusip)),

  first_name_years AS (
  SELECT boardid, directorid, min(annual_report_date) AS annual_report_date
  FROM boardex_w_permnos
  GROUP BY boardid, directorid),

  boardex_final AS (
  SELECT boardid, directorid, annual_report_date,
  b.last_name, b.first_name, b.permno, b.permco
  FROM first_name_years AS a
  INNER JOIN boardex_w_permnos AS b
  USING (boardid, directorid, annual_report_date)
  ORDER BY boardid, directorid, annual_report_date),

  activist_directors AS (
  SELECT DISTINCT a.campaign_id, a.first_name, a.last_name,
  a.activist_affiliate, a.appointment_date,
  -- a.appointment_date < c.eff_announce_date AS prior_director,
  -- c.eff_announce_date, c.first_date,
  a.retirement_date,
  b.permno, b.permco
  -- c.campaign_ids IS NOT NULL AS on_activism_events
  FROM activist_director.activist_directors AS a
  LEFT JOIN permnos AS b
  ON substr(a.cusip_9_digit, 1, 8)=b.cusip
  --LEFT JOIN activist_director.activism_events AS c
  --ON a.campaign_id=ANY(c.campaign_ids)
  ),

  activist_director_boardex AS (
  SELECT DISTINCT a.*,
  COALESCE(b.boardid, c.boardid, d.boardid, e.boardid) AS boardid,
  COALESCE(b.directorid, c.directorid, d.directorid, e.directorid) AS directorid,
  COALESCE(b.annual_report_date, c.annual_report_date, d.annual_report_date, e.annual_report_date) AS annual_report_date,
  COALESCE(b.first_name, c.first_name, d.first_name, e.first_name) AS boardex_first_name,
  COALESCE(b.last_name, c.last_name, d.last_name, e.last_name) AS boardex_last_name,
  f.permco IS NOT NULL AS permco_on_boardex
  FROM activist_directors AS a
  LEFT JOIN boardex_final AS b
  ON a.permco=b.permco AND lower(a.last_name)=lower(b.last_name)
  AND lower(a.first_name)=lower(b.first_name)
  LEFT JOIN boardex_final AS c
  ON a.permco=c.permco AND lower(a.last_name)=lower(c.last_name)
  AND substr(lower(a.first_name),1,2)=substr(lower(c.first_name),1,2)
  LEFT JOIN boardex_final AS d
  ON a.permco=d.permco AND lower(a.last_name)=lower(d.last_name)
  AND substr(lower(a.first_name),1,1)=substr(lower(c.first_name),1,1)
  LEFT JOIN boardex_final AS e
  ON a.permco=e.permco AND lower(a.last_name)=lower(e.last_name)
  LEFT JOIN boardex_final AS f
  ON a.permco=f.permco)

  SELECT *, boardex_last_name IS NOT NULL AS matched_to_boardex
  FROM activist_director_boardex;
  ")

rs <- dbWriteTable(pg, c("activist_director", "activist_director_boardex"), activist_directors_boardex,
                   overwrite=TRUE, row.names=FALSE)

