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
                     SELECT DISTINCT a.campaign_id, a.permno, a.eff_announce_date, a.proxy_fight_went_the_distance, a.category,
                     a.dissident_board_seats_wongranted_date AS appointment_date, b.settle_date, c.standstill_date, COALESCE(b.settle_date, c.standstill_date)::DATE AS any_settle_date
                     FROM activist_director.activism_events AS a
                     LEFT JOIN settlement_agreement AS b
                     ON b.campaign_id=ANY(a.campaign_ids)
                     LEFT JOIN standstill_agreement AS c
                     ON c.campaign_id=ANY(a.campaign_ids)
                     --WHERE a.activist_director
                     ORDER BY campaign_id)

                     SELECT DISTINCT campaign_id, permno, eff_announce_date, proxy_fight_went_the_distance, category, extract(year from eff_announce_date) AS year,
                     min(appointment_date) As appointment_date, min(settle_date) AS settle_date, min(standstill_date) AS standstill_date, min(any_settle_date) AS any_settle_date
                     FROM before_remove_dups
                     GROUP BY campaign_id, permno, eff_announce_date, proxy_fight_went_the_distance, category
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







# Before Announcement Date (Long-term, -12,0)
ret.data.d <- getEventReturnsMonthly(events$permno, events$eff_announce_date,
                                     start.month=-12, end.month=0,
                                     label="ret_annc_m12p0")
ret.data.d$eff_announce_date <- ret.data.d$event_date
ret.data.d$event_date <- NULL
ret.data.d$end_event_date <- NULL
merged <- merge(merged, ret.data.d, by = c("permno", "eff_announce_date"), all = TRUE)

# After Announcement Date (Long-term, 0,12)
ret.data.d <- getEventReturnsMonthly(events$permno, events$eff_announce_date,
                                     start.month=0, end.month=12,
                                     label="ret_annc_m0p12")
ret.data.d$eff_announce_date <- ret.data.d$event_date
ret.data.d$event_date <- NULL
ret.data.d$end_event_date <- NULL
merged <- merge(merged, ret.data.d, by = c("permno", "eff_announce_date"), all = TRUE)

# After Announcement Date (Long-term, 0,24)
ret.data.d <- getEventReturnsMonthly(events$permno, events$eff_announce_date,
                                     start.month=0, end.month=24,
                                     label="ret_annc_m0p24")
ret.data.d$eff_announce_date <- ret.data.d$event_date
ret.data.d$event_date <- NULL
ret.data.d$end_event_date <- NULL
merged <- merge(merged, ret.data.d, by = c("permno", "eff_announce_date"), all = TRUE)

# After Announcement Date (Long-term, 0,36)
ret.data.d <- getEventReturnsMonthly(events$permno, events$eff_announce_date,
                                     start.month=0, end.month=36,
                                     label="ret_annc_m0p36")
ret.data.d$eff_announce_date <- ret.data.d$event_date
ret.data.d$event_date <- NULL
ret.data.d$end_event_date <- NULL
merged <- merge(merged, ret.data.d, by = c("permno", "eff_announce_date"), all = TRUE)





# Before Appointment Date (Long-term, -12,0)
ret.data.d <- getEventReturnsMonthly(events$permno, events$appointment_date,
                                     start.month=-12, end.month=0,
                                     label="ret_appt_m12p0")
ret.data.d$appointment_date <- ret.data.d$event_date
ret.data.d$event_date <- NULL
ret.data.d$end_event_date <- NULL
merged <- merge(merged, ret.data.d, by = c("permno", "appointment_date"), all = TRUE)

# After Appointment Date (Long-term, 0,12)
ret.data.d <- getEventReturnsMonthly(events$permno, events$appointment_date,
                                     start.month=0, end.month=12,
                                     label="ret_appt_m0p12")
ret.data.d$appointment_date <- ret.data.d$event_date
ret.data.d$event_date <- NULL
ret.data.d$end_event_date <- NULL
merged <- merge(merged, ret.data.d, by = c("permno", "appointment_date"), all = TRUE)

# After Appointment Date (Long-term, 0,24)
ret.data.d <- getEventReturnsMonthly(events$permno, events$appointment_date,
                                     start.month=0, end.month=24,
                                     label="ret_appt_m0p24")
ret.data.d$appointment_date <- ret.data.d$event_date
ret.data.d$event_date <- NULL
ret.data.d$end_event_date <- NULL
merged <- merge(merged, ret.data.d, by = c("permno", "appointment_date"), all = TRUE)

# After Appointment Date (Long-term, 0,36)
ret.data.d <- getEventReturnsMonthly(events$permno, events$appointment_date,
                                     start.month=0, end.month=36,
                                     label="ret_appt_m0p36")
ret.data.d$appointment_date <- ret.data.d$event_date
ret.data.d$event_date <- NULL
ret.data.d$end_event_date <- NULL
merged <- merge(merged, ret.data.d, by = c("permno", "appointment_date"), all = TRUE)

# Before Appointment Date (Long-term, -12,0) - Breakdown_1 (-12,annc)
subevents <- subset(events, eff_announce_date < appointment_date)
ret.data.d <- getEventReturns(subevents$permno, subevents$appointment_date, subevents$eff_announce_date,
                              days.before=-252, days.after=0,
                              label="ret_appt_m12_annc")
ret.data.d$appointment_date <- ret.data.d$event_date
ret.data.d$eff_announce_date <- ret.data.d$end_event_date
ret.data.d$event_date <- NULL
ret.data.d$end_event_date <- NULL
merged <- merge(merged, ret.data.d, by = c("permno", "appointment_date", "eff_announce_date"), all = TRUE)

# Before Appointment Date (Long-term, -12,0) - Breakdown_2 (annc, appt)
ret.data.d <- getEventReturns(subevents$permno, subevents$eff_announce_date, subevents$appointment_date,
                              days.before=0, days.after=0,
                              label="ret_appt_annc_appt")
ret.data.d$eff_announce_date <- ret.data.d$event_date
ret.data.d$appointment_date <- ret.data.d$end_event_date
ret.data.d$event_date <- NULL
ret.data.d$end_event_date <- NULL
merged <- merge(merged, ret.data.d, by = c("permno", "eff_announce_date", "appointment_date"), all = TRUE)




rs <- dbWriteTable(pg, c("activist_director", "event_returns"),
                   merged, overwrite=TRUE, row.names=FALSE)

returns <- dbGetQuery(pg, "SELECT * FROM activist_director.event_returns")
