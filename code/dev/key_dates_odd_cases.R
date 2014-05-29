#### Data Validation
library(RPostgreSQL)
drv <- dbDriver("PostgreSQL")
pg <- dbConnect(drv, dbname="crsp")

# Problematic... Why don't these events have any demand? Why missing?
dbGetQuery(pg, "
SELECT DISTINCT a.announce_date, a.announce_date, a.dissident_group, category, board_demand
FROM activist_director.activism_events AS a
LEFT JOIN activist_director.key_dates_all AS b
ON a.cusip_9_digit=b.cusip_9_digit AND a.announce_date=b.announce_date AND a.dissident_group=b.dissident_group
WHERE b.cusip_9_digit IS NULL
")

# Why changes in categories?----
case1 <- dbGetQuery(pg, "
WITH first_board_demand_date AS (
SELECT DISTINCT cusip_9_digit, announce_date, dissident_group, min(event_date) AS first_board_demand_date
FROM activist_director.key_dates_all
WHERE board_demand
GROUP BY cusip_9_digit, announce_date, dissident_group),

PENULTIMATE AS (
SELECT DISTINCT a.*, b.first_board_demand_date, b.first_board_demand_date IS NOT NULL AS board_demand
FROM activist_director.activism_events AS a
LEFT JOIN first_board_demand_date AS b
ON a.cusip_9_digit=b.cusip_9_digit AND a.announce_date=b.announce_date AND a.dissident_group=b.dissident_group
ORDER BY permno, announce_date, dissident_group)

SELECT a.cusip_9_digit, a.announce_date, a.dissident_group,
        COALESCE(b.event_date,c.event_date) AS event_date,
        COALESCE(b.event_text,c.event_text) AS event_text,
        b.dissident_group is NOT NULL AS from_sw50,
        c.dissident_group is NOT NULL AS from_nsw50
FROM penultimate AS a
LEFT JOIN activist_director.key_dates_sw50 AS b
USING (cusip_9_digit, announce_date, dissident_group)
LEFT JOIN activist_director.key_dates_nsw50 AS c
USING (cusip_9_digit, announce_date, dissident_group)
WHERE board_demand IS FALSE AND category='activist_demand'
ORDER BY cusip_9_digit, announce_date, dissident_group, event_date
")

write.csv(case1, "case1.csv")
