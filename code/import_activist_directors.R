# Import Dataset from Google Drive ----
library(googlesheets4)
library(dplyr, warn.conflicts = FALSE)
library(DBI)

pg <- dbConnect(RPostgres::Postgres())

rs <- dbExecute(pg, "SET search_path TO activist_director")

# As a one-time thing per user and machine, you will need
# to authorize googlesheets4 to access your Google Sheets.
gs_key <- "1zHSKIAx4LKURXav-k06D7T3p3St0VjFa8RXvAFJnUfI"

#### Sheet 1 ####
col_types <- paste0("iici", paste(rep("?", 28), collapse = ""))
activist_directors_1 <-
    read_sheet(gs_key, range="activist_directors",
               na = "NA", col_types=col_types) %>%
    filter(!is.na(appointment_date)) %>%
    filter(!is.na(independent)) %>%
    mutate(retirement_date = as.Date(retirement_date),
           appointment_date = as.Date(appointment_date),
           announce_date=as.Date(announce_date),
           issue_cik=as.integer(as.character(issuer_cik))) %>%
    mutate(source = 1L) %>%
    select(cusip_9_digit, announce_date, dissident_group,
           first_name, last_name, appointment_date, permno,
           retirement_date, independent, source, bio, issuer_cik) %>%
    copy_to(pg, .,
            name = "activist_directors_1", overwrite=TRUE)

#### Sheet 2 ####
col_types <- "iicicDccDiicccccDcDcicc"

activist_directors_2 <-
    read_sheet(gs_key, range="2013-2015 + Extra", na = "#N/A",
               col_types = col_types) %>%
    filter(!is.na(appointment_date)) %>%
    filter(!is.na(independent)) %>%
    mutate(bio=as.character(bio)) %>%
    mutate(source = 2L) %>%
    select(campaign_id, first_name, last_name, appointment_date, permno,
           retirement_date, independent, source, bio, issuer_cik) %>%
    copy_to(pg, .,
            name = "activist_directors_2", overwrite=TRUE)

#### Sheet 3 ####
col_types <- "iidcciiDccccDcDciccci"
activist_directors_3 <-
    read_sheet(gs_key, range="Extra2",
               col_types = col_types) %>%
    filter(!is.na(appointment_date)) %>%
    filter(!is.na(independent)) %>%
    mutate(source = 3L) %>%
    select(campaign_id, first_name, last_name, appointment_date, permno,
           retirement_date, independent, source, bio, issuer_cik) %>%
    copy_to(pg, .,
            name = "activist_directors_3", overwrite=TRUE)

activism_sample <- tbl(pg, "activism_sample")

campaign_ids <-
    tbl(pg, sql("SELECT * FROM factset.campaign_ids")) %>%
    distinct() %>%
    compute()

activism_events <-
    activism_sample %>%
    select(campaign_id, permno, dissident_group, eff_announce_date) %>%
    rename(permno_alt = permno) %>%
    mutate(permno_alt = as.integer(permno_alt))

ad_1 <-
    activist_directors_1 %>%
    left_join(campaign_ids,
              by = c("cusip_9_digit", "announce_date", "dissident_group")) %>%
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

rs <- dbExecute(pg, "DROP TABLE IF EXISTS activist_directors")

activist_directors <-
    ad_1 %>%
    union_all(ad_2) %>%
    union_all(ad_3) %>%
    mutate(permno = as.integer(permno)) %>%
    mutate(independent = as.logical(as.integer(independent))) %>%
    left_join(activism_events, by = "campaign_id") %>%
    mutate(permno = coalesce(permno, permno_alt)) %>%
    filter(!is.na(permno)) %>%
    compute(name = "activist_directors", temporary = FALSE)


rs <- dbExecute(pg, "ALTER TABLE activist_directors OWNER TO activism")

rs <- dbExecute(pg, "VACUUM activist_directors")

sql <- paste0("
              COMMENT ON TABLE activist_directors IS
              'CREATED USING import_activist_directors.R ON ",
              format(Sys.time(), "%Y-%m-%d %X %Z"), "';")

rs <- dbExecute(pg, sql)

dbDisconnect(pg)
