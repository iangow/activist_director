  SET work_mem='10GB';

  DROP TABLE IF EXISTS activist_director.boardex_w_activism;

  CREATE TABLE activist_director.boardex_w_activism AS

      -- Pull together director characteristics
  WITH permnos AS (
  SELECT DISTINCT cusip, permno, permco
  FROM crsp.stocknames),

  committees AS (
	SELECT DISTINCT boardid, directorid, annual_report_date,
	    BOOL_OR(committee_name ilike '%audit%') AS audit_committee,
	    BOOL_OR(committee_name ilike '%compensat%' OR committee_name ilike '%remunerat%') AS comp_committee,
	    BOOL_OR(committee_name ilike '%nominat%') AS nom_committee
	FROM boardex.board_and_director_committees
	WHERE annual_report_date IS NOT NULL
	GROUP BY boardid, directorid, annual_report_date
	ORDER BY boardid, directorid, annual_report_date),

  ages AS (
    SELECT DISTINCT a.boardid, a.directorid,
                    CASE WHEN a.annual_report_date = 'Current' THEN NULL ELSE eomonth(to_date(a.annual_report_date::text,'Mon YYYY')) END AS annual_report_date,
                    COALESCE(dob, '2015-07-01'::DATE - age*365) AS dob,
                    (CASE WHEN a.annual_report_date = 'Current' THEN NULL ELSE eomonth(to_date(a.annual_report_date::text,'Mon YYYY')) END - COALESCE(dob, '2015-07-01'::DATE - age*365))/365.25 AS age
    FROM boardex.director_characteristics AS a
    LEFT JOIN boardex.director_profile_details AS b
    ON a.directorid=b.directorid
    WHERE annual_report_date != 'Current'
    ORDER BY boardid, directorid, annual_report_date),

  boardex AS (
  SELECT DISTINCT CASE WHEN substr(d.isin,1,2)='US' THEN substr(d.isin,3,8) END AS cusip,
	  c.annual_report_date, a.boardid, a.directorid,
	  b.last_name, b.first_name,
	  a.time_retirement, a.time_role, a.time_brd, a.time_inco, a.avg_time_oth_co,
	  a.tot_nolstd_brd, a.tot_noun_lstd_brd, a.tot_curr_nolstd_brd, a.tot_curr_noun_lstd_brd,
	  a.gender='F' AS female, a.no_quals,
	  audit_committee, comp_committee, nom_committee,
	  dob, age
  FROM boardex.director_characteristics AS a
  INNER JOIN activist_director.director_names AS b
  ON a.director_name=b.directorname
  INNER JOIN boardex.board_characteristics AS c
  ON a.boardid=c.boardid
  AND CASE WHEN a.annual_report_date = 'Current' THEN NULL ELSE eomonth(to_date(a.annual_report_date::text,'Mon YYYY')) END=eomonth(c.annual_report_date)
  INNER JOIN boardex.company_profile_stocks AS d
  ON a.boardid=d.boardid
  LEFT JOIN committees AS e
  ON a.boardid=e.boardid AND a.directorid=e.directorid
  AND CASE WHEN a.annual_report_date = 'Current' THEN NULL ELSE eomonth(to_date(a.annual_report_date::text,'Mon YYYY')) END=eomonth(e.annual_report_date)
  LEFT JOIN ages AS f
  ON a.boardid=f.boardid AND a.directorid=f.directorid
  AND CASE WHEN a.annual_report_date = 'Current' THEN NULL ELSE eomonth(to_date(a.annual_report_date::text,'Mon YYYY')) END=eomonth(f.annual_report_date)
  WHERE a.row_type='Board Member' AND a.annual_report_date!='Current'
  --AND a.boardid='12212'
  ORDER BY cusip, annual_report_date, last_name, first_name),

  boardex_permnos AS (
  SELECT *
  FROM boardex AS a
  INNER JOIN permnos AS b
  USING (cusip)),

    -- Identify companies' first years
    company_first_years AS (
        SELECT boardid, min(annual_report_date) AS annual_report_date
        FROM boardex_permnos AS a
        GROUP BY boardid
        ORDER BY boardid),

    -- Identify directors' first years
    director_first_years AS (
        SELECT boardid, directorid, min(annual_report_date) AS annual_report_date
        FROM boardex_permnos AS a
        GROUP BY boardid, directorid
        ORDER BY boardid, directorid),

    -- Classify directors' first years on boardex based on whether
    -- they were appointed during an activism event or shortly thereafter
    boardex_activism_match AS (
        SELECT DISTINCT b.permno, boardid, a.directorid, annual_report_date,
            bool_or(sharkwatch50) AS sharkwatch50,
            bool_or(activism) AS activism_firm,
	    bool_or(activist_demand) AS activist_demand_firm,
            bool_or(activist_director) AS activist_director_firm
        FROM director_first_years AS a
        INNER JOIN boardex_permnos AS b
        USING (boardid, annual_report_date)
        LEFT JOIN activist_director.activism_events AS c
        ON b.permco=c.permco AND
            a.annual_report_date BETWEEN c.first_date AND c.end_date + interval '128 days'
        GROUP BY b.permno, boardid, a.directorid, annual_report_date
        ORDER BY permno, boardid, directorid)

    -- Now pull all directors from boardex and add data on activism from above
    SELECT DISTINCT a.permno, a.permco, a.annual_report_date, a.boardid,
	a.directorid, a.last_name, a.first_name,
	b.annual_report_date IS NOT NULL AS firm_first_year,
	c.annual_report_date IS NOT NULL AS director_first_year,
        COALESCE(c.sharkwatch50, FALSE) AS sharkwatch50,
        COALESCE(c.activism_firm, FALSE) AS activism_firm,
        COALESCE(c.activist_demand_firm, FALSE) AS activist_demand_firm,
        COALESCE(c.activist_director_firm, FALSE) AS activist_director_firm,
        CASE
            WHEN activist_director_firm THEN 'activist_director_firm'
            WHEN activist_demand_firm THEN 'activist_demand_firm'
            WHEN activism_firm THEN 'activism_firm'
		ELSE '_none' END AS category,
        d.directorid IS NOT NULL AS activist_director,
        d.activist_affiliate IS TRUE AS affiliated_director,
        audit_committee, comp_committee, nom_committee,
	  a.time_retirement, a.time_role, a.time_brd, a.time_inco, a.avg_time_oth_co,
	  a.tot_nolstd_brd, a.tot_noun_lstd_brd, a.tot_curr_nolstd_brd, a.tot_curr_noun_lstd_brd,
	  a.female, a.no_quals, a.dob, a.age
    FROM boardex_permnos AS a
    LEFT JOIN company_first_years AS b
    ON a.boardid=b.boardid AND a.annual_report_date=b.annual_report_date
    LEFT JOIN boardex_activism_match AS c
    ON a.boardid=c.boardid
        AND a.directorid=c.directorid
        AND a.annual_report_date=c.annual_report_date
    LEFT JOIN activist_director.activist_director_boardex AS d
    ON a.boardid=d.boardid --boardid
    AND a.directorid=d.directorid --directorid
    AND a.annual_report_date=d.annual_report_date
    ORDER BY permno, boardid, directorid, annual_report_date;

-- Query returned successfully: 506822 rows affected, 201434 ms execution time.
