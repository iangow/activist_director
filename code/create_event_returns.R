library(dplyr, warn.conflicts = FALSE)
library(DBI)

pg <- dbConnect(RPostgreSQL::PostgreSQL())

rs <- dbExecute(pg, "SET search_path TO activist_director")

activism_events <- tbl(pg, "activism_events")
activist_directors <- tbl(pg, "activist_directors")

ad_linked <-
    activism_events %>%
    mutate(campaign_id = unnest(campaign_ids)) %>%
    inner_join(activist_directors, by = "campaign_id") %>%
    group_by(campaign_ids) %>%
    summarize(appointment_date = min(appointment_date, na.rm = TRUE),
              won_date = min(dissident_board_seats_wongranted_date, na.rm = TRUE)) %>%
    mutate(appointment_date = least(appointment_date, won_date)) %>%
    select(-won_date)

events <-
    activism_events %>%
    left_join(ad_linked, by = "campaign_ids") %>%
    collect()

source("https://raw.githubusercontent.com/iangow/acct_data/master/code/getEventReturnsDaily.R")
source("https://raw.githubusercontent.com/iangow/acct_data/master/code/getEventReturnsMonthly.R")

merged <-
    # Around Appointment Date
    getEventReturns(events$permno, events$appointment_date,
                    days.before=-1, days.after=1,
                    label="ret_d_appt") %>%
    rename(appointment_date = event_date) %>%
    right_join(events, by = c("permno", "appointment_date"))

# Around Settlement Date
merged <-
    getEventReturns(events$permno, events$settle_date,
                    days.before=-1, days.after=1,
                    label="ret_d_sett") %>%
    rename(settle_date = event_date) %>%
    right_join(merged, by = c("permno", "settle_date"))

# Around Standstill Date
merged <-
    getEventReturns(events$permno, events$standstill_date,
                          days.before=-1, days.after=1,
                          label="ret_d_ss") %>%
    rename(standstill_date = event_date) %>%
    right_join(merged, by = c("permno", "standstill_date"))

# Around Any Settlement Date
merged <-
    getEventReturns(events$permno, events$any_settle_date,
                    days.before=-1, days.after=1,
                    label="ret_d_any_sett") %>%
    rename(any_settle_date = event_date) %>%
    right_join(merged, by = c("permno", "any_settle_date"))

# Around Any Announcement Date
merged <-
    getEventReturns(events$permno, events$eff_announce_date,
                    days.before=-1, days.after=1,
                    label="ret_d_annc") %>%
    rename(eff_announce_date = event_date) %>%
    right_join(merged, by = c("permno", "eff_announce_date"))

# Before Announcement Date (Long-term, -12,0)
merged <-
    getEventReturnsMonthly(events$permno, events$eff_announce_date,
                           start.month=-12, end.month=0,
                           label="ret_annc_m12p0") %>%
    rename(eff_announce_date = event_date) %>%
    right_join(merged, by = c("permno", "eff_announce_date"))

# After Announcement Date (Long-term, 0,12)
merged <-
    getEventReturnsMonthly(events$permno, events$eff_announce_date,
                           start.month=0, end.month=12,
                           label="ret_annc_m0p12") %>%
    rename(eff_announce_date = event_date) %>%
    right_join(merged, by = c("permno", "eff_announce_date"))

# After Announcement Date (Long-term, 0,24)
merged <-
    getEventReturnsMonthly(events$permno, events$eff_announce_date,
                           start.month=0, end.month=24,
                           label="ret_annc_m0p24") %>%
    rename(eff_announce_date = event_date) %>%
    right_join(merged, by = c("permno", "eff_announce_date"))

# After Announcement Date (Long-term, 0,36)
merged <-
    getEventReturnsMonthly(events$permno, events$eff_announce_date,
                           start.month=0, end.month=36,
                           label="ret_annc_m0p36") %>%
    rename(eff_announce_date = event_date) %>%
    right_join(merged, by = c("permno", "eff_announce_date"))

# Before Appointment Date (Long-term, -12,0)
merged <-
    getEventReturnsMonthly(events$permno, events$appointment_date,
                           start.month=-12, end.month=0,
                           label="ret_appt_m12p0") %>%
    rename(appointment_date = event_date) %>%
    right_join(merged, by = c("permno", "appointment_date"))

# After Appointment Date (Long-term, 0,12)
merged <-
    getEventReturnsMonthly(events$permno, events$appointment_date,
                           start.month=0, end.month=12,
                           label="ret_appt_m0p12") %>%
    rename(appointment_date = event_date) %>%
    right_join(merged, by = c("permno", "appointment_date"))

# After Appointment Date (Long-term, 0,24)
merged <-
    getEventReturnsMonthly(events$permno, events$appointment_date,
                           start.month=0, end.month=24,
                           label="ret_appt_m0p24")  %>%
    rename(appointment_date = event_date) %>%
    right_join(merged, by = c("permno", "appointment_date"))

# After Appointment Date (Long-term, 0,36)
merged <-
    getEventReturnsMonthly(events$permno, events$appointment_date,
                           start.month=0, end.month=36,
                           label="ret_appt_m0p36")  %>%
    rename(appointment_date = event_date) %>%
    right_join(merged, by = c("permno", "appointment_date"))

# Before Appointment Date (Long-term, -12,0) - Breakdown_1 (-12,annc)
subevents <-
    events %>%
    filter(eff_announce_date < appointment_date)

merged <-
    getEventReturns(subevents$permno,
                    subevents$appointment_date,
                    subevents$eff_announce_date,
                    days.before=-252, days.after=0,
                    label="ret_appt_m12_annc")  %>%
    rename(appointment_date = event_date) %>%
    right_join(merged, by = c("permno", "appointment_date"))

# Before Appointment Date (Long-term, -12,0) - Breakdown_2 (annc, appt)
merged <-
    getEventReturns(subevents$permno, subevents$eff_announce_date,
                    subevents$appointment_date,
                    days.before=0, days.after=0,
                    label="ret_appt_annc_appt")  %>%
    rename(eff_announce_date = event_date) %>%
    right_join(merged, by = c("permno", "eff_announce_date"))

rs <- dbWriteTable(pg, c("activist_director", "event_returns"),
                   merged, overwrite=TRUE, row.names=FALSE)

sql <- "ALTER TABLE event_returns OWNER TO activism;"
rs <- dbGetQuery(pg, sql)

sql <- paste("
             COMMENT ON TABLE event_returns IS
             'CREATED USING create_event_returns.R ON ",
             format(Sys.time(), "%Y-%m-%d %X %Z"), "';", sep="")
rs <- dbExecute(pg, paste(sql, collapse="\n"))


rs <- dbDisconnect(pg)
