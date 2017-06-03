# Import Dataset from Google Drive ----
library(dplyr)
library(googlesheets)
library(dplyr, warn.conflicts = FALSE)
library(RPostgreSQL)

# As a one-time thing per user and machine, you will need to run gs_auth()
# to authorize googlesheets to access your Google Sheets.
gs <- gs_key("1zHSKIAx4LKURXav-k06D7T3p3St0VjFa8RXvAFJnUfI")

#### Sheet 1 ####
activist_directors_1 <-
    gs_read(gs, ws = "activist_directors") %>%
    filter(!is.na(appointment_date)) %>%
    mutate(source = 1L)

#### Sheet 2 ####
activist_directors_2 <-
    gs_read(gs, ws = "2013-2015 + Extra") %>%
    filter(!is.na(appointment_date)) %>%
    mutate(source = 2L)

#### Sheet 3 ####
activist_directors_3 <-
    gs_read(gs, ws = "Extra2") %>%
    filter(!is.na(appointment_date)) %>%
    mutate(source = 3L)

Sys.setenv(PGHOST = "iangow.me", PGDATABASE = "crsp")
pg <- src_postgres()

campaign_ids <-
    tbl(pg, sql("SELECT * FROM factset.campaign_ids")) %>%
    collect()

activism_events <-
    tbl(pg, sql("SELECT * FROM activist_director.activism_events")) %>%
    select(campaign_id, permno, dissident_group, eff_announce_date) %>%
    rename(permno_alt = permno) %>%
    collect()

ad_1 <-
    activist_directors_1 %>%
    left_join(campaign_ids) %>%
    select(campaign_id, first_name, last_name, appointment_date, permno,
           retirement_date, independent, source, bio, issuer_cik)

ad_2 <-
    activist_directors_2 %>%
    select(campaign_id, first_name, last_name, appointment_date, permno,
           retirement_date, independent, source, bio, issuer_cik)

ad_3 <-
    activist_directors_3 %>%
    select(campaign_id, first_name, last_name, appointment_date, permno,
           retirement_date, independent, source, bio, issuer_cik)

activist_directors <-
    ad_1 %>%
    union(ad_2) %>%
    union(ad_3) %>%
    mutate(independent = as.logical(independent)) %>%
    left_join(activism_events) %>%
    mutate(permno = coalesce(permno, permno_alt))

rs <- dbWriteTable(pg$con, c("activist_director", "activist_directors"),
                   activist_directors,
                   overwrite=TRUE, row.names=FALSE)

rs <- dbGetQuery(pg$con, "ALTER TABLE activist_director.activist_directors OWNER TO activism")

rs <- dbGetQuery(pg$con, "VACUUM activist_director.activist_directors")

sql <- paste0("
              COMMENT ON TABLE activist_director.activist_directors IS
              'CREATED USING import_activist_directors.R ON ", Sys.time() , "';")

rs <- dbGetQuery(pg$con, sql)

