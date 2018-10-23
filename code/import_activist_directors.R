# Import Dataset from Google Drive ----
library(dplyr)
library(googlesheets)
library(dplyr, warn.conflicts = FALSE)
library(RPostgreSQL)

# As a one-time thing per user and machine, you will need to run
# library(googlesheets)
# options(httr_oob_default=TRUE)
# gs_auth(new_user = TRUE)
# gs_ls()
# to authorize googlesheets to access your Google Sheets.
gs <- gs_key("1zHSKIAx4LKURXav-k06D7T3p3St0VjFa8RXvAFJnUfI")

#### Sheet 1 ####
activist_directors_1 <-
    gs_read(gs, ws = "activist_directors") %>%
    filter(!is.na(appointment_date)) %>%
    filter(!is.na(independent)) %>%
    mutate(source = 1L)

#### Sheet 2 ####
activist_directors_2 <-
    gs_read(gs, ws = "2013-2015 + Extra") %>%
    filter(!is.na(appointment_date)) %>%
    filter(!is.na(independent)) %>%
    mutate(issuer_cik=as.integer(issuer_cik)) %>%
    mutate(source = 2L)

#### Sheet 3 ####
activist_directors_3 <-
    gs_read(gs, ws = "Extra2") %>%
    filter(!is.na(appointment_date)) %>%
    filter(!is.na(independent)) %>%
    mutate(issuer_cik=as.integer(issuer_cik)) %>%
    mutate(source = 3L)

pg <- src_postgres()

campaign_ids <-
    tbl(pg, sql("SELECT * FROM factset.campaign_ids")) %>%
    collect()

activism_events <-
    tbl(pg, sql("SELECT * FROM activist_director.activism_sample")) %>%
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
    bind_rows(ad_1, ad_2, ad_3) %>%
    mutate(independent = as.logical(independent)) %>%
    left_join(activism_events) %>%
    mutate(permno = coalesce(permno, permno_alt)) %>%
    filter(!is.na(permno))
    distinct() %>%
    arrange(campaign_id, last_name, first_name)

rs <- dbWriteTable(pg$con, c("activist_director", "activist_directors"),
                   activist_directors,
                   overwrite=TRUE, row.names=FALSE)

rs <- dbGetQuery(pg$con, "ALTER TABLE activist_director.activist_directors OWNER TO activism")

rs <- dbGetQuery(pg$con, "VACUUM activist_director.activist_directors")

sql <- paste0("
              COMMENT ON TABLE activist_director.activist_directors IS
              'CREATED USING import_activist_directors.R ON ",
              format(Sys.time(), "%Y-%m-%d %X %Z"), "';")

rs <- dbGetQuery(pg$con, sql)

dbDisconnect(pg$con)
