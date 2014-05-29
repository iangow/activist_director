DROP TABLE IF EXISTS activist_director.activist_director_matched;

CREATE TABLE activist_director.activist_director_matched AS
WITH permnos AS (
    SELECT DISTINCT ncusip AS cusip, permno
    FROM crsp.stocknames),
matched AS (
    SELECT DISTINCT a.*, permno, sharkwatch50 = 'Yes' AS sharkwatch50,
        proxy_fight_went_the_distance ='Yes' AS elected
    FROM activist_director.activist_directors AS a
    INNER JOIN factset.sharkwatch AS b
    USING (cusip_9_digit, announce_date, dissident_group)
    INNER JOIN permnos AS c
    ON substr(a.cusip_9_digit, 1, 8)=c.cusip
    WHERE c.permno IS NOT NULL),
delist AS (
    SELECT DISTINCT permno,
        CASE WHEN dlstcd > 100 THEN dlstdt END AS dlstdt
    FROM crsp.msedelist)
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
WHERE (dlstdt IS NULL OR dlstdt>appointment_date)
--OR NOT (last_name='Fox' AND first_name='Bernard A.' AND fy_end='2010-12-31')
AND NOT (last_name='Goldfarb' AND first_name='Matthew' AND appointment_date = '2012-05-09')
AND NOT (last_name='Lynch' AND first_name='James' AND appointment_date = '2009-02-11')
AND NOT (last_name='Mitarotonda' AND first_name='James' AND appointment_date = '2007-11-16')
AND NOT (last_name='Hussein' AND first_name='Ahmed' AND appointment_date = '2008-09-04')
AND NOT (last_name='Hussein' AND first_name='Ahmed' AND appointment_date = '2012-08-16')

ORDER BY permno, announce_date;

COMMENT ON TABLE activist_director.activist_director_matched IS
    'CREATED USING create_activist_director_matched.sql';

ALTER TABLE activist_director.activist_director_matched
	  OWNER TO activism;
