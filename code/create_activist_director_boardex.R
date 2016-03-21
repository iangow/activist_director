library(RPostgreSQL)
drv <- dbDriver("PostgreSQL")
pg <- dbConnect(drv, host='iangow.me', port='5432', dbname='crsp')

# Import Activist Director Datasets from Google Drive ----
require(RCurl)

# 2013-2015
csv_file <- getURL(paste("https://docs.google.com/spreadsheets/d/",
                         "13TRLvEequPmsgZNSrqelm3aDnTtMN5N34TNUa7mk3Eo/",
                         "pub?gid=1314945913&single=true&output=csv", sep=""),
                   verbose=FALSE)

activist_directors <- read.csv(textConnection(csv_file), as.is=TRUE)

activist_directors$announce_date <- as.Date(activist_directors$announce_date, "%Y-%m-%d")
activist_directors$dissident_board_seats_wongranted_date <- as.Date(activist_directors$dissident_board_seats_wongranted_date, "%Y-%m-%d")
activist_directors$appointment_date <- as.Date(activist_directors$appointment_date, "%Y-%m-%d")

rs <- dbWriteTable(pg, c("activist_director", "activist_directors_1315"), activist_directors,
                   overwrite=TRUE, row.names=FALSE)

# 2004-2012
csv_file <- getURL(paste("https://docs.google.com/spreadsheets/d/",
                         "13TRLvEequPmsgZNSrqelm3aDnTtMN5N34TNUa7mk3Eo/",
                         "pub?gid=8&single=true&output=csv", sep=""),
                   verbose=FALSE)

activist_directors <- read.csv(textConnection(csv_file), as.is=TRUE, na.strings = "")

activist_directors$announce_date <- as.Date(activist_directors$announce_date, "%Y-%m-%d")
activist_directors$dissident_board_seats_wongranted_date <- as.Date(activist_directors$dissident_board_seats_wongranted_date, "%Y-%m-%d")
activist_directors$appointment_date <- as.Date(activist_directors$appointment_date, "%Y-%m-%d")

rs <- dbWriteTable(pg, c("activist_director", "activist_directors_0412"), activist_directors,
                   overwrite=TRUE, row.names=FALSE)

# Activist Director Spreadsheet Combined ----
activist_directors <- dbGetQuery(pg, "
    WITH activism_events AS (
        SELECT DISTINCT b.permno, a.*
        FROM factset.sharkwatch_new AS a
        INNER JOIN crsp.stocknames AS b
        ON substr(a.cusip_9_digit,1,8) = b.ncusip
        WHERE (dissident_board_seats_wongranted_date IS NOT NULL
              OR dissident_board_seats_won > 0
              OR campaign_resulted_in_board_seats_for_activist = 'Yes')
              AND announce_date BETWEEN '2004-01-01' AND '2015-12-31'
              AND country='United States'
              AND state_of_incorporation != 'Non-U.S.'
              AND factset_industry != 'Investment Trusts/Mutual Funds'
              AND (s13d_filer='Yes' OR proxy_fight='Yes' OR holder_type IN ('Hedge Fund Company', 'Investment Adviser'))
              AND holder_type NOT IN ('Corporation')
              AND campaign_status='Closed'
              AND activism_type != '13D Filer - No Publicly Disclosed Activism'
        ORDER BY permno, announce_date, dissident_group)

    SELECT DISTINCT b.campaign_id, a.permno, a.cusip_9_digit, a.announce_date, b.dissident_group,
            a.last_name, a.first_name, a.appointment_date, a.retirement_date,
            CASE WHEN a.independent=1 THEN FALSE WHEN a.independent=0 THEN TRUE END AS activist_affiliate
    FROM activist_director.activist_directors_0412 AS a
    INNER JOIN activism_events AS b
    ON a.permno=b.permno AND a.announce_date=b.announce_date
    WHERE a.activism_type != '13D Filer - No Publicly Disclosed Activism' AND a.permno IS NOT NULL

    UNION

    SELECT DISTINCT campaign_id, permno, cusip_9_digit, announce_date, dissident_group,
            last_name, first_name, appointment_date, retirement_date,
            CASE WHEN a.independent=1 THEN FALSE WHEN a.independent=0 THEN TRUE END AS activist_affiliate
    FROM activist_director.activist_directors_1315 AS a
    WHERE a.activism_type != '13D Filer - No Publicly Disclosed Activism' AND a.permno IS NOT NULL
    ORDER BY permno, announce_date, last_name, first_name
")

rs <- dbWriteTable(pg, c("activist_director", "activist_directors"), activist_directors,
                   overwrite=TRUE, row.names=FALSE)


# Match with Equilar - create_activist_director_equilar ----

activist_directors_equilar <- dbGetQuery(pg, "

    WITH permnos AS (
      SELECT DISTINCT cusip, permno, permco
      FROM activist_director.permnos
      INNER JOIN crsp.stocknames
      USING (permno)),

    equilar AS (
      SELECT DISTINCT equilar_firm_id(a.director_id) AS firm_id,
          equilar_director_id(director_id) AS director_id, director,
          (equilar.parse_name(director)).*, a.fy_end, start_date,
          substr(cusip,1,8) AS cusip
      FROM equilar.director AS a
      LEFT JOIN equilar.co_fin AS b
      ON equilar_firm_id(a.director_id)=equilar_firm_id(b.company_id)
      AND a.fy_end=b.fy_end),

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
  AND CASE WHEN a.annual_report_date = 'Current' THEN NULL ELSE eomonth(to_date(a.annual_report_date::text,'Mon YYYY')) END=eomonth(c.annual_report_date)
  INNER JOIN boardex.company_profile_stocks AS d
  ON a.boardid=d.boardid
  --INNER JOIN crsp.stocknames AS e
  --ON CASE WHEN substr(d.isin,1,2)='US' THEN substr(d.isin,3,8) END=e.ncusip
  WHERE a.row_type='Board Member' AND a.annual_report_date!='Current'
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

