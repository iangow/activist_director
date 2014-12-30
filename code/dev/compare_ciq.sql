WITH spinoff_new AS (
    SELECT DISTINCT permno, announcedate AS date
    FROM ciq.wrds_keydev 
    INNER JOIN ciq.wrds_cusip AS a
    USING (companyid)
    INNER JOIN activist_director.permnos AS b
    ON substr(a.cusip,1,8)=b.ncusip
    WHERE keydeveventtypeid=137 
        AND keydevtoobjectroletypeid=4 AND announcedate BETWEEN '2004-01-01' AND '2012-12-31'),
    
spinoff_ciq AS (
    SELECT DISTINCT b.permno, c.permno AS new_permno, a.date
    FROM activist_director.spinoff_ciq AS a
    INNER JOIN activist_director.permnos AS b
    ON substr(a.cusip,1,8)=b.ncusip
    LEFT JOIN activist_director.permnos AS c
    ON substr(a.new_cusip,1,8)=c.ncusip)

SELECT *, a.permno IS NOT NULL AS on_wrds_ciq,
    b.permno IS NOT NULL AS on_spinoff_ciq
FROM spinoff_new AS a
FULL OUTER JOIN spinoff_ciq AS b
USING (permno, date)
ORDER BY date, permno