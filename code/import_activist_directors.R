# Import Dataset from Google Drive ----
library(googlesheets4)
library(dplyr, warn.conflicts = FALSE)
library(DBI)

# As a one-time thing per user and machine, you will need to run
# library(googlesheets)
# options(httr_oob_default=TRUE)
# gs_auth(new_user = TRUE)
# gs_ls()
# to authorize googlesheets to access your Google Sheets.
gs <- read_sheet("1zHSKIAx4LKURXav-k06D7T3p3St0VjFa8RXvAFJnUfI")

#### Sheet 1 ####
activist_directors_1 <-
    read_sheet("https://docs.google.com/spreadsheets/d/1zHSKIAx4LKURXav-k06D7T3p3St0VjFa8RXvAFJnUfI", range="activist_directors") %>%
    filter(!is.na(appointment_date)) %>%
    filter(!is.na(independent)) %>%
    mutate(announce_date=as.Date(announce_date),
           issue_cik=as.integer(as.character(issuer_cik))) %>%
    mutate(source = 1L)

#### Sheet 2 ####
activist_directors_2 <-
    read_sheet("https://docs.google.com/spreadsheets/d/1zHSKIAx4LKURXav-k06D7T3p3St0VjFa8RXvAFJnUfI", range="2013-2015 + Extra") %>%
    filter(!is.na(appointment_date)) %>%
    filter(!is.na(independent)) %>%
    mutate(issuer_cik=as.integer(as.character(issuer_cik)),
           bio=as.character(bio)) %>%
    mutate(source = 2L)

#### Sheet 3 ####
activist_directors_3 <-
    read_sheet("https://docs.google.com/spreadsheets/d/1zHSKIAx4LKURXav-k06D7T3p3St0VjFa8RXvAFJnUfI", range="Extra2") %>%
    filter(!is.na(appointment_date)) %>%
    filter(!is.na(independent)) %>%
    mutate(issue_cik=as.integer(as.character(issuer_cik))) %>%
    mutate(source = 3L)

pg <- dbConnect(RPostgreSQL::PostgreSQL())

rs <- dbExecute(pg, "SET search_path TO activist_director, public")

activism_sample <- tbl(pg, "activism_sample")

campaign_ids <-
    tbl(pg, sql("SELECT * FROM factset.campaign_ids")) %>%
    collect()

activism_events <-
    activism_sample %>%
    select(campaign_id, permno, dissident_group, eff_announce_date) %>%
    rename(permno_alt = permno) %>%
    mutate(permno_alt = as.integer(permno_alt)) %>%
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
    mutate(permno = as.integer(permno)) %>%
    mutate(independent = as.logical(independent)) %>%
    left_join(activism_events, by = "campaign_id") %>%
    mutate(permno = coalesce(permno, permno_alt)) %>%
    filter(!is.na(permno)) %>%
    distinct() %>%
    arrange(campaign_id, last_name, first_name)

rs <- dbWriteTable(pg, c("activist_director", "activist_directors"),
                   activist_directors,
                   overwrite=TRUE, row.names=FALSE)

rs <- dbExecute(pg, "ALTER TABLE activist_director.activist_directors OWNER TO activism")

rs <- dbExecute(pg, "VACUUM activist_director.activist_directors")

sql <- paste0("
              COMMENT ON TABLE activist_director.activist_directors IS
              'CREATED USING import_activist_directors.R ON ",
              format(Sys.time(), "%Y-%m-%d %X %Z"), "';")

rs <- dbExecute(pg, sql)

dbDisconnect(pg)
