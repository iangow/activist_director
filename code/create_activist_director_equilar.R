library(RPostgreSQL)
drv <- dbDriver("PostgreSQL")
pg <- dbConnect(drv, dbname="crsp")

rs <-dbGetQuery(pg, "

  SET work_mem='10GB';

  DROP TABLE IF EXISTS activist_director.activist_director_equilar;

  CREATE TABLE activist_director.activist_director_equilar AS
  WITH
    permnos AS (
        SELECT DISTINCT ncusip AS cusip, permno, permco
        FROM crsp.stocknames),

    matched AS (
        SELECT DISTINCT a.*, permno, permco, sharkwatch50 = 'Yes' AS sharkwatch50,
            proxy_fight_went_the_distance ='Yes' AS elected
        FROM activist_director.activist_directors AS a
        INNER JOIN factset.sharkwatch_new AS b
        USING (campaign_id)
        INNER JOIN permnos AS c
        ON substr(a.cusip_9_digit, 1, 8)=c.cusip
        WHERE c.permno IS NOT NULL),

    delist AS (
        SELECT DISTINCT permno,
            CASE WHEN dlstcd > 100 THEN dlstdt END AS dlstdt
        FROM crsp.msedelist),

    activist_directors AS (
        SELECT DISTINCT a.*, dlstdt,
            CASE WHEN dlstdt <= appointment_date THEN 'UNLISTED'
                WHEN (retirement_date IS NOT NULL AND dlstdt IS NULL)
                    OR (dlstdt > retirement_date) THEN 'RESIGNED'
                WHEN dlstdt IS NULL THEN 'ACTIVE'
                WHEN dlstdt IS NOT NULL THEN 'DELISTED'
                ELSE 'OTHER'
            END AS status
        FROM matched AS a
        INNER JOIN delist AS c
        USING (permno)
        WHERE (dlstdt IS NULL OR dlstdt>appointment_date)),

  co_fin AS (
      SELECT DISTINCT equilar_id(company_id) AS equilar_id, fy_end,
            substr(cusip,1,8) AS cusip
      FROM director.co_fin),

  equilar AS (
      SELECT equilar_id(a.director_id) AS equilar_id,
        director_id(a.director_id) AS equilar_director_id,
        director, (director.parse_name(director)).*, a.fy_end, cusip
      FROM director.director AS a
      INNER JOIN co_fin AS c
      ON equilar_id(a.director_id)=c.equilar_id AND a.fy_end=c.fy_end),

  equilar_w_permnos AS (
      SELECT a.*, b.permno, c.permco
      FROM equilar AS a
      LEFT JOIN activist_director.permnos AS b
      ON a.cusip=b.ncusip
      INNER JOIN crsp.stocknames AS c
      ON b.permno=c.permno),

  equilar_first_years AS (
      SELECT permco, equilar_id, equilar_director_id, director,
          last_name AS equilar_last, first_name AS equilar_first,
          min(fy_end) AS fy_end
      FROM equilar_w_permnos
      GROUP BY permco, equilar_id, equilar_director_id, director, last_name, first_name),

  match_permno AS (
      SELECT a.*, b.permco IS NOT NULL AS permco_on_equilar
      FROM activist_directors AS a
      LEFT JOIN equilar_w_permnos AS b
      ON a.permco=b.permco),

  final AS (
	  SELECT DISTINCT a.*,
	  COALESCE(b.equilar_id, c.equilar_id, d.equilar_id, e.equilar_id) AS equilar_id,
	  COALESCE(b.equilar_director_id, c.equilar_director_id, d.equilar_director_id, e.equilar_director_id) AS equilar_director_id,
	  COALESCE(b.fy_end, c.fy_end, d.fy_end, e.fy_end) AS fy_end,
	  COALESCE(b.equilar_first, c.equilar_first, d.equilar_first, e.equilar_first) AS equilar_first,
	  COALESCE(b.equilar_last, c.equilar_last, d.equilar_last, e.equilar_last) AS equilar_last,
	  CASE WHEN dlstdt IS NOT NULL AND retirement_date IS NULL THEN dlstdt
	  WHEN dlstdt IS NOT NULL AND retirement_date IS NOT NULL
	  THEN least(dlstdt, retirement_date)
	  WHEN retirement_date IS NOT NULL THEN retirement_date
	  END AS last_observed_date,
	  appointment_date < announce_date AS prior_director
	  FROM match_permno AS a
	  LEFT JOIN equilar_first_years AS b
	  ON a.permco=b.permco AND lower(a.last_name)=lower(b.equilar_last) AND lower(a.first_name)=lower(b.equilar_first)
	  LEFT JOIN equilar_first_years AS c
	  ON a.permco=c.permco AND lower(a.last_name)=lower(c.equilar_last) AND substr(lower(a.first_name),1,2)=substr(lower(c.equilar_first),1,2)
	  LEFT JOIN equilar_first_years AS d
	  ON a.permco=d.permco AND lower(a.last_name)=lower(d.equilar_last) AND substr(lower(a.first_name),1,1)=substr(lower(c.equilar_first),1,1)
	  LEFT JOIN equilar_first_years AS e
	  ON a.permco=e.permco AND lower(a.last_name)=lower(e.equilar_last)
	  -- take out duplicate matches due to Equilar
	  WHERE NOT (last_name='Fox' AND first_name='Bernard A.' AND COALESCE(b.fy_end, c.fy_end, d.fy_end, e.fy_end)='2010-12-31')
	  AND NOT (last_name='Maura' AND first_name='David' AND COALESCE(b.equilar_id, c.equilar_id, d.equilar_id, e.equilar_id) = 4431)
	  AND NOT (last_name='Roger' AND first_name='Robin' AND COALESCE(b.equilar_id, c.equilar_id, d.equilar_id, e.equilar_id) = 4431)
	  AND NOT (last_name='McKenzie' AND first_name='Craig' AND COALESCE(b.fy_end, c.fy_end, d.fy_end, e.fy_end)='2011-12-31')),

	final2 AS (
	  SELECT DISTINCT a.*, COALESCE(b.permno, c.permno, d.permno, e.permno) AS permno_real,
	  COALESCE(b.age, c.age, d.age, e.age) AS age,
	  COALESCE(b.audit_committee_financial_expert, c.audit_committee_financial_expert, d.audit_committee_financial_expert, e.audit_committee_financial_expert) AS audit_committee_financial_expert,
	  COALESCE(b.comp_committee, c.comp_committee, d.comp_committee, e.comp_committee) AS comp_committee,
	  COALESCE(b.audit_committee, c.audit_committee, d.audit_committee, e.audit_committee) AS audit_committee,
	  f.market_capitalization_at_time_of_campaign
	  FROM final AS a
	  LEFT JOIN activist_director.equilar_directors AS b
	  ON a.permco=b.permco AND a.fy_end=b.fy_end AND a.last_name ilike b.last_name AND a.first_name ilike b.first_name
	  LEFT JOIN activist_director.equilar_directors AS c
	  ON a.permco=c.permco AND a.fy_end=c.fy_end AND a.last_name ilike c.last_name AND substr(a.first_name,1,2) ilike substr(c.first_name,1,2)
	  LEFT JOIN activist_director.equilar_directors AS d
	  ON a.permco=d.permco AND a.fy_end=d.fy_end AND a.last_name ilike d.last_name AND substr(a.first_name,1,1) ilike substr(d.first_name,1,1)
	  LEFT JOIN activist_director.equilar_directors AS e
	  ON a.permco=e.permco AND a.fy_end=e.fy_end AND a.last_name ilike e.last_name
	  INNER JOIN activist_director.activism_events AS f
	  ON a.permno=f.permno AND a.cusip_9_digit=f.cusip_9_digit AND a.announce_date=f.announce_date)

  SELECT DISTINCT a.*,
    COALESCE(b.first_meetingdate, c.first_meetingdate, d.first_meetingdate, e.first_meetingdate) AS first_meetingdate,
    COALESCE(b.vote_pct, c.vote_pct, d.vote_pct, e.vote_pct) AS vote_pct,
    COALESCE(b.issrec, c.issrec, d.issrec, e.issrec) AS issrec
  FROM final2 AS a
  LEFT JOIN activist_director.first_voting AS b
  ON a.permno_real=b.permno AND b.first_meetingdate BETWEEN a.appointment_date - INTERVAL '1 month' AND a.appointment_date + INTERVAL '11 months' AND a.last_name ilike b.last_name AND substr(a.first_name,1,3) ilike substr(b.first_name,1,3)
  LEFT JOIN activist_director.first_voting AS c
  ON a.permno_real=c.permno AND c.first_meetingdate BETWEEN a.appointment_date - INTERVAL '1 month' AND a.appointment_date + INTERVAL '11 months' AND a.last_name ilike c.last_name AND substr(a.first_name,1,2) ilike substr(c.first_name,1,2)
  LEFT JOIN activist_director.first_voting AS d
  ON a.permno_real=d.permno AND d.first_meetingdate BETWEEN a.appointment_date - INTERVAL '1 month' AND a.appointment_date + INTERVAL '11 months' AND a.last_name ilike d.last_name AND substr(a.first_name,1,1) ilike substr(d.first_name,1,1)
  LEFT JOIN activist_director.first_voting AS e
  ON a.permno_real=e.permno AND e.first_meetingdate BETWEEN a.appointment_date - INTERVAL '1 month' AND a.appointment_date + INTERVAL '11 months' AND a.last_name ilike e.last_name
  ORDER BY permno, last_name;

  ALTER TABLE activist_director.activist_director_equilar OWNER TO activism;

  CREATE INDEX ON activist_director.activist_director_equilar (permno);
")

sql <- paste("
  COMMENT ON TABLE activist_director.activist_director_equilar IS
    'CREATED USING create_activism_director_equilar ON ", Sys.time() , "';", sep="")
rs <- dbGetQuery(pg, paste(sql, collapse="\n"))

