library(dplyr, warn.conflicts = FALSE)
library(RPostgreSQL)

pg <- dbConnect(PostgreSQL())

events <- dbGetQuery(pg, "
WITH settlement_agreement AS (
    SELECT DISTINCT campaign_id::INT,
    to_date(regexp_replace(regexp_matches(settlement_agreement_special_exhibit_source, '\\d{1,2}-\\d{1,2}-\\d{4}', 'g')::text, '[{}]', '', 'g'), 'MM-DD-YYYY') AS settle_date
    FROM factset.sharkwatch
    ORDER BY campaign_id),

standstill_agreement AS (
    SELECT DISTINCT campaign_id::INT,
    to_date(regexp_replace(regexp_matches(standstill_agreement_special_exhibit_source, '\\d{1,2}-\\d{1,2}-\\d{4}', 'g')::text, '[{}]', '', 'g'), 'MM-DD-YYYY') AS standstill_date
    FROM factset.sharkwatch
    ORDER BY campaign_id),

before_remove_dups AS (
    SELECT DISTINCT a.campaign_id, a.permno, a.eff_announce_date, a.proxy_fight_went_the_distance,
            a.dissident_board_seats_wongranted_date AS appointment_date, settle_date, standstill_date, COALESCE(settle_date, standstill_date)::DATE AS any_settle_date
    FROM activist_director.activism_events AS a
    LEFT JOIN settlement_agreement AS b
    ON b.campaign_id=ANY(a.campaign_ids)
    LEFT JOIN standstill_agreement AS c
    ON c.campaign_id=ANY(a.campaign_ids)
    --WHERE a.activist_director
    ORDER BY campaign_id)

SELECT DISTINCT campaign_id, permno, eff_announce_date, proxy_fight_went_the_distance, extract(year from eff_announce_date) AS year,
        min(appointment_date) As appointment_date, min(settle_date) AS settle_date, min(standstill_date) AS standstill_date, min(any_settle_date) AS any_settle_date
FROM before_remove_dups
GROUP BY campaign_id, permno, eff_announce_date, proxy_fight_went_the_distance
ORDER BY campaign_id
")

source("https://raw.githubusercontent.com/iangow/acct_data/master/code/getEventReturnsDaily.R")
source("https://raw.githubusercontent.com/iangow/acct_data/master/code/getEventReturnsMonthly.R")

# Around Appointment Date
ret.data.d <- getEventReturns(events$permno, events$appointment_date,
                              days.before=-1, days.after=1,
                              label="ret_d_appt")
ret.data.d$appointment_date <- ret.data.d$event_date
ret.data.d$event_date <- NULL
ret.data.d$end_event_date <- NULL
merged <- merge(events, ret.data.d, by = c("permno", "appointment_date"), all = TRUE)

# Around Settlement Date
ret.data.d <- getEventReturns(events$permno, events$settle_date,
                              days.before=-1, days.after=1,
                              label="ret_d_sett")
ret.data.d$settle_date <- ret.data.d$event_date
ret.data.d$event_date <- NULL
ret.data.d$end_event_date <- NULL
merged <- merge(merged, ret.data.d, by = c("permno", "settle_date"), all = TRUE)


# Around Standstill Date
ret.data.d <- getEventReturns(events$permno, events$standstill_date,
                              days.before=-1, days.after=1,
                              label="ret_d_ss")
ret.data.d$standstill_date <- ret.data.d$event_date
ret.data.d$event_date <- NULL
ret.data.d$end_event_date <- NULL
merged <- merge(merged, ret.data.d, by = c("permno", "standstill_date"), all = TRUE)


# Around Any Settlement Date
ret.data.d <- getEventReturns(events$permno, events$any_settle_date,
                              days.before=-1, days.after=1,
                              label="ret_d_any_sett")
ret.data.d$any_settle_date <- ret.data.d$event_date
ret.data.d$event_date <- NULL
ret.data.d$end_event_date <- NULL
merged <- merge(merged, ret.data.d, by = c("permno", "any_settle_date"), all = TRUE)

# Around Any Announcement Date
ret.data.d <- getEventReturns(events$permno, events$eff_announce_date,
                              days.before=-1, days.after=1,
                              label="ret_d_annc")
ret.data.d$eff_announce_date <- ret.data.d$event_date
ret.data.d$event_date <- NULL
ret.data.d$end_event_date <- NULL
merged <- merge(merged, ret.data.d, by = c("permno", "eff_announce_date"), all = TRUE)

rs <- dbWriteTable(pg, c("activist_director", "settlement_return"),
                   merged, overwrite=TRUE, row.names=FALSE)

dbGetQuery(pg, "
    SELECT year,
            count(*) AS activism,
            sum((appointment_date IS NOT NULL)::INT) AS activist_dir,
            sum((settle_date IS NOT NULL)::INT) AS settle,
            sum((standstill_date IS NOT NULL)::INT) AS standstill,
            sum((any_settle_date IS NOT NULL)::INT) AS any_settle,
            sum(proxy_fight_went_the_distance::INT) AS proxy_fight,
            sum((NOT proxy_fight_went_the_distance AND any_settle_date IS NULL)::INT) AS no_elect_no_sett
    FROM activist_director.settlement_return
    WHERE appointment_date IS NOT NULL
    GROUP BY year
    ORDER BY year
    ")
