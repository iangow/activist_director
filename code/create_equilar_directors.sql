SET work_mem='10GB';

-- All Directors from Equilar (365,738 --> 409,137)
DROP TABLE IF EXISTS activist_director.equilar_directors;

CREATE TABLE activist_director.equilar_directors AS

WITH equilar AS (
      SELECT DISTINCT equilar_id(a.director_id) AS equilar_id, 
				director_id(director_id) AS director_id, director, 
        last_name, first_name, a.fy_end, start_date, substr(cusip,1,8) AS cusip,
        gender='M' AS male, age, (a.fy_end - start_date)/365 AS tenure, 
        committees ilike '%comp%' AS comp_committee, 
        committees ilike '%audit%' AS audit_committee, 
        audit_committee_financial_expert
      FROM director.director AS a
      INNER JOIN director.director_names AS b
      USING (director)
      LEFT JOIN director.co_fin AS c
      ON equilar_id(a.director_id)=equilar_id(c.company_id))

SELECT DISTINCT  c.permco, b.permno, a.*
FROM equilar AS a
LEFT JOIN activist_director.permnos AS b
ON a.cusip=b.ncusip
INNER JOIN crsp.stocknames AS c
ON b.permno=c.permno
ORDER BY permco, permno, fy_end, last_name;

ALTER TABLE activist_director.equilar_directors
  OWNER TO activism;

COMMENT ON TABLE activist_director.equilar_directors
  IS 'CREATED USING create_equilar_directors.sql ON 2014-02-09';
