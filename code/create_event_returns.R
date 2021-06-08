library(dplyr, warn.conflicts = FALSE)
library(DBI)
library(farr)

pg <- dbConnect(RPostgres::Postgres())

rs <- dbExecute(pg, "SET search_path TO activist_director")

activism_events <- tbl(pg, "activism_events")
activist_directors <- tbl(pg, "activist_directors")

ad_linked <-
    activism_events %>%
    mutate(campaign_id = unnest(campaign_ids)) %>%
    inner_join(activist_directors, by = "campaign_id") %>%
    group_by(campaign_ids) %>%
    summarize(appointment_date = min(appointment_date, na.rm = TRUE),
              won_date = min(dissident_board_seats_wongranted_date,
                             na.rm = TRUE)) %>%
    mutate(appointment_date = least(appointment_date, won_date)) %>%
    select(-won_date)

events <-
    activism_events %>%
    left_join(ad_linked, by = "campaign_ids") %>%
    collect()

# Around Appointment Date
rets <- get_event_cum_rets(events, pg, permno = "permno",
                               event_date = "appointment_date",
                               win_start = -1, win_end = 1,
                               suffix = "_d_appt")
merged <-
    rets %>%
    right_join(events, by = c("permno", "appointment_date"))

# Around Settlement Date
merged <-
    events %>%
    get_event_cum_rets(pg, permno = "permno",
                               event_date = "settle_date",
                               win_start = -1, win_end = 1,
                               suffix = "_d_sett") %>%
    right_join(merged, by = c("permno", "settle_date"))

# Around Standstill Date
merged <-
    events %>%
    get_event_cum_rets(pg, permno = "permno",
                               event_date = "standstill_date",
                               win_start = -1, win_end = 1,
                               suffix = "_d_ss") %>%
    right_join(merged, by = c("permno", "standstill_date"))

# Around Any Settlement Date
merged <-
    events %>%
    get_event_cum_rets(pg, permno = "permno",
                               event_date = "any_settle_date",
                               win_start = -1, win_end = 1,
                               suffix = "_d_any_sett") %>%
    right_join(merged, by = c("permno", "any_settle_date"))

# Around Any Announcement Date
merged <-
    events %>%
    get_event_cum_rets(pg, permno = "permno",
                               event_date = "eff_announce_date",
                               win_start = -1, win_end = 1,
                               suffix = "_d_annc") %>%
    right_join(merged, by = c("permno", "eff_announce_date"))

# Before Announcement Date (Long-term, -12,0)
merged <-
    get_event_cum_rets_mth(events, pg, permno = "permno",
                                   event_date = "eff_announce_date",
                                   win_start = -12, win_end = 0,
                                   read_only = FALSE,
                                   suffix="_annc_m12p0") %>%
    right_join(merged, by = c("permno", "eff_announce_date"))

# After Announcement Date (Long-term, 0,12)
merged <-
    get_event_cum_rets_mth(events, pg, permno = "permno",
                                   event_date = "eff_announce_date",
                                   win_start = 0, win_end = 12,
                                   read_only = FALSE,
                                   suffix="_annc_m0p12") %>%
    right_join(merged, by = c("permno", "eff_announce_date"))

# After Announcement Date (Long-term, 0,24)
merged <-
    get_event_cum_rets_mth(events, pg, permno = "permno",
                                   event_date = "eff_announce_date",
                                   win_start = 0, win_end = 24,
                                   read_only = FALSE,
                                   suffix="_annc_m0p24") %>%
    right_join(merged, by = c("permno", "eff_announce_date"))

# After Announcement Date (Long-term, 0,36)
merged <-
    get_event_cum_rets_mth(events, pg, permno = "permno",
                                   event_date = "eff_announce_date",
                                   win_start = 0, win_end = 36,
                                   read_only = FALSE,
                                   suffix="_annc_m0p36") %>%
    right_join(merged, by = c("permno", "eff_announce_date"))


# Before Appointment Date (Long-term, -12,0)
merged <-
    get_event_cum_rets_mth(events, pg, permno = "permno",
                                   event_date = "appointment_date",
                                   win_start = -12, win_end = 0,
                                   read_only = FALSE,
                                   suffix="_appt_m12p0") %>%
    right_join(merged, by = c("permno", "appointment_date"))


# After Appointment Date (Long-term, 0,12)
merged <-
    get_event_cum_rets_mth(events, pg, permno = "permno",
                                   event_date = "appointment_date",
                                   win_start = 0, win_end = 12,
                                   read_only = FALSE,
                                   suffix="_appt_m0p12") %>%
    right_join(merged, by = c("permno", "appointment_date"))

# After Appointment Date (Long-term, 0,24)
merged <-
    get_event_cum_rets_mth(events, pg, permno = "permno",
                                   event_date = "appointment_date",
                                   win_start = 0, win_end = 24,
                                   read_only = FALSE,
                                   suffix="_appt_m0p24") %>%
    right_join(merged, by = c("permno", "appointment_date"))

# After Appointment Date (Long-term, 0,36)
merged <-
    get_event_cum_rets_mth(events, pg, permno = "permno",
                                   event_date = "appointment_date",
                                   win_start = 0, win_end = 36,
                                   read_only = FALSE,
                                   suffix="_appt_m0p36") %>%
    right_join(merged, by = c("permno", "appointment_date"))

# Before Appointment Date (Long-term, -12,0) - Breakdown_1 (-12,annc)
subevents <-
    events %>%
    filter(eff_announce_date < appointment_date)

merged <-
    get_event_cum_rets(events, pg, permno = "permno",
                               event_date = "appointment_date",
                               win_start = -252, win_end = 0,
                               suffix = "_appt_m12_annc") %>%
    right_join(merged, by = c("permno", "appointment_date"))

# Before Appointment Date (Long-term, -12,0) - Breakdown_2 (annc, appt)
event_returns <-
    get_event_cum_rets(events, pg, permno = "permno",
                               event_date = "eff_announce_date",
                               win_start = 0, win_end = 0,
                               suffix = "_appt_annc_appt") %>%
    right_join(merged, by = c("permno", "eff_announce_date"))

rs <- dbWriteTable(pg, "event_returns", event_returns,
                   overwrite=TRUE, row.names=FALSE)

sql <- "ALTER TABLE event_returns OWNER TO activism;"
rs <- dbExecute(pg, sql)

sql <- paste("
             COMMENT ON TABLE event_returns IS
             'CREATED USING create_event_returns.R ON ",
             format(Sys.time(), "%Y-%m-%d %X %Z"), "';", sep="")
rs <- dbExecute(pg, paste(sql, collapse="\n"))

rs <- dbDisconnect(pg)
