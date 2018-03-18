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





rs <- dbWriteTable(pg, c("activist_director", "settlement_return"),
                   merged, overwrite=TRUE, row.names=FALSE)

returns <- dbGetQuery(pg, "SELECT * FROM activist_director.settlement_return")


#### announcement return ~ activism
reg.data <- subset(returns)

fm.t2.pa.c1 <- lm(ret_d_annc ~ category - 1,
                  data=reg.data, na.action="na.exclude")
fm.t2.pa.c1.se <- coeftest.cluster(reg.data, fm.t2.pa.c1, cluster1="permno")

fm.t2.pa.c2 <- lm(ret_d_annc_mkt ~ category - 1,
                  data=reg.data, na.action="na.exclude")
fm.t2.pa.c2.se <- coeftest.cluster(reg.data, fm.t2.pa.c2, cluster1="permno")

fm.t2.pa.c3 <- lm(ret_d_annc_sz ~ category - 1,
                  data=reg.data, na.action="na.exclude")
fm.t2.pa.c3.se <- coeftest.cluster(reg.data, fm.t2.pa.c3, cluster1="permno")


# Produce Excel file with results for announcement return
screenreg(list(fm.t2.pa.c1, fm.t2.pa.c2, fm.t2.pa.c3),
          # file = "tables/voting_analysis.docx",
          caption = "Announcement day return for activism events",
          caption.above = TRUE,
          digits = 3,
          stars = c(0.01, 0.05, 0.1),
          # omit.coef = "(permno_meetingdate)",
          custom.model.names = c("ret_d_annc","ret_d_annc_mkt","ret_d_annc_sz"),
          override.se = list(fm.t2.pa.c1.se[,2], fm.t2.pa.c2.se[,2], fm.t2.pa.c3.se[,2]),
          override.pval = list(fm.t2.pa.c1.se[,4], fm.t2.pa.c2.se[,4], fm.t2.pa.c3.se[,4]))


#### settlement return ~ activism
fm.t2.pb.c1 <- lm(ret_d_any_sett ~ category - 1,
                  data=reg.data, na.action="na.exclude")
fm.t2.pb.c1.se <- coeftest.cluster(reg.data, fm.t2.pb.c1, cluster1="permno")

fm.t2.pb.c2 <- lm(ret_d_any_sett_mkt ~ category - 1,
                  data=reg.data, na.action="na.exclude")
fm.t2.pb.c2.se <- coeftest.cluster(reg.data, fm.t2.pb.c2, cluster1="permno")

fm.t2.pb.c3 <- lm(ret_d_any_sett_sz ~ category - 1,
                  data=reg.data, na.action="na.exclude")
fm.t2.pb.c3.se <- coeftest.cluster(reg.data, fm.t2.pb.c3, cluster1="permno")

# Produce Excel file with results for settlement return
screenreg(list(fm.t2.pb.c1, fm.t2.pb.c2, fm.t2.pb.c3),
          # file = "tables/voting_analysis.docx",
          caption = "Announcement day return for activism events",
          caption.above = TRUE,
          digits = 3,
          stars = c(0.01, 0.05, 0.1),
          # omit.coef = "(permno_meetingdate)",
          custom.model.names = c("ret_d_any_sett","ret_d_any_sett_mkt","ret_d_any_sett_sz"),
          override.se = list(fm.t2.pb.c1.se[,2], fm.t2.pb.c2.se[,2], fm.t2.pb.c3.se[,2]),
          override.pval = list(fm.t2.pb.c1.se[,4], fm.t2.pb.c2.se[,4], fm.t2.pb.c3.se[,4]))

#### appointment return ~ activism
reg.data <- subset(returns, !is.na(ret_d_appt))

fm.t2.pc.c1 <- lm(ret_d_appt ~ 1,
                  data=reg.data, na.action="na.exclude")
fm.t2.pc.c1.se <- coeftest.cluster(reg.data, fm.t2.pc.c1)

fm.t2.pc.c2 <- lm(ret_d_appt_mkt ~ 1,
                  data=reg.data, na.action="na.exclude")
fm.t2.pc.c2.se <- coeftest.cluster(reg.data, fm.t2.pc.c2)

fm.t2.pc.c3 <- lm(ret_d_appt_sz ~ 1,
                  data=reg.data, na.action="na.exclude")
fm.t2.pc.c3.se <- coeftest.cluster(reg.data, fm.t2.pc.c3)

# Produce Excel file with results for appointment return
screenreg(list(fm.t2.pc.c1, fm.t2.pc.c2, fm.t2.pc.c3),
          # file = "tables/voting_analysis.docx",
          caption = "Announcement day return for activism events",
          caption.above = TRUE,
          digits = 3,
          stars = c(0.01, 0.05, 0.1),
          # omit.coef = "(permno_meetingdate)",
          custom.model.names = c("ret_d_appt","ret_d_any_appt_mkt","ret_d_any_appt_sz"),
          override.se = list(fm.t2.pc.c1.se[,2], fm.t2.pc.c2.se[,2], fm.t2.pc.c3.se[,2]),
          override.pval = list(fm.t2.pc.c1.se[,4], fm.t2.pc.c2.se[,4], fm.t2.pc.c3.se[,4]))




#### announcement return (long-term) ~ activism
reg.data <- subset(returns)

fm.t2.pd.c1 <- lm(ret_annc_m12p0_sz ~ category - 1,
                  data=reg.data, na.action="na.exclude")
fm.t2.pd.c1.se <- coeftest.cluster(reg.data, fm.t2.pd.c1, cluster1="permno")

fm.t2.pd.c2 <- lm(ret_annc_m0p12_sz ~ category - 1,
                  data=reg.data, na.action="na.exclude")
fm.t2.pd.c2.se <- coeftest.cluster(reg.data, fm.t2.pd.c2, cluster1="permno")

fm.t2.pd.c3 <- lm(ret_annc_m0p24_sz ~ category - 1,
                  data=reg.data, na.action="na.exclude")
fm.t2.pd.c3.se <- coeftest.cluster(reg.data, fm.t2.pd.c3, cluster1="permno")

fm.t2.pd.c4 <- lm(ret_annc_m0p36_sz ~ category - 1,
                  data=reg.data, na.action="na.exclude")
fm.t2.pd.c4.se <- coeftest.cluster(reg.data, fm.t2.pd.c4, cluster1="permno")

# Produce Excel file with results for announcement return
screenreg(list(fm.t2.pd.c1, fm.t2.pd.c2, fm.t2.pd.c3, fm.t2.pd.c4),
          # file = "tables/voting_analysis.docx",
          caption = "Announcement day return for activism events",
          caption.above = TRUE,
          digits = 3,
          stars = c(0.01, 0.05, 0.1),
          # omit.coef = "(permno_meetingdate)",
          custom.model.names = c("ret_annc_m12p0","ret_annc_m0p12","ret_annc_m0p24", "ret_annc_m0p36"),
          override.se = list(fm.t2.pd.c1.se[,2], fm.t2.pd.c2.se[,2], fm.t2.pd.c3.se[,2], fm.t2.pd.c4.se[,2]),
          override.pval = list(fm.t2.pd.c1.se[,4], fm.t2.pd.c2.se[,4], fm.t2.pd.c3.se[,4], fm.t2.pd.c4.se[,4]))


#### appointment return (long-term) ~ activism
reg.data <- subset(returns, !is.na(ret_d_appt))

fm.t2.pe.c1 <- lm(ret_appt_m12p0_sz ~ 1,
                  data=reg.data, na.action="na.exclude")
fm.t2.pe.c1.se <- coeftest.cluster(reg.data, fm.t2.pe.c1)

fm.t2.pe.c2 <- lm(ret_appt_m0p12_sz ~ 1,
                  data=reg.data, na.action="na.exclude")
fm.t2.pe.c2.se <- coeftest.cluster(reg.data, fm.t2.pe.c2)

fm.t2.pe.c3 <- lm(ret_appt_m0p24_sz ~ 1,
                  data=reg.data, na.action="na.exclude")
fm.t2.pe.c3.se <- coeftest.cluster(reg.data, fm.t2.pe.c3)

fm.t2.pe.c4 <- lm(ret_appt_m0p36_sz ~ 1,
                  data=reg.data, na.action="na.exclude")
fm.t2.pe.c4.se <- coeftest.cluster(reg.data, fm.t2.pe.c4)

# Produce Excel file with results for announcement return
screenreg(list(fm.t2.pe.c1, fm.t2.pe.c2, fm.t2.pe.c3, fm.t2.pe.c4),
          # file = "tables/voting_analysis.docx",
          caption = "Announcement day return for activism events",
          caption.above = TRUE,
          digits = 3,
          stars = c(0.01, 0.05, 0.1),
          # omit.coef = "(permno_meetingdate)",
          custom.model.names = c("ret_appt_m12p0","ret_appt_m0p12","ret_appt_m0p24", "ret_appt_m0p36"),
          override.se = list(fm.t2.pe.c1.se[,2], fm.t2.pe.c2.se[,2], fm.t2.pe.c3.se[,2], fm.t2.pe.c4.se[,2]),
          override.pval = list(fm.t2.pe.c1.se[,4], fm.t2.pe.c2.se[,4], fm.t2.pe.c3.se[,4], fm.t2.pe.c4.se[,4]))


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
