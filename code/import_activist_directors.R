# Import Dataset from Google Drive ----
library(googlesheets)
Sys.setenv(PGHOST = "iangow.me", PGDATABASE = "crsp")
pg <- src_postgres()
# As a one-time thing per user and machine, you will need to run gs_auth()
# to authorize googlesheets to access your Google Sheets.
gs <- gs_key("1zHSKIAx4LKURXav-k06D7T3p3St0VjFa8RXvAFJnUfI")

factset.campaign_ids <-
    tbl(pg, sql("SELECT * FROM factset.campaign_ids")) %>%
    collect()

activist_directors_2 <-
    gs_read(gs, ws = "2013-2015 + Extra") %>%
    mutate(retirement_date=ifelse(grepl("[A-Za-z]", retirement_date),
                                  NA, retirement_date)) %>%
    mutate(retirement_date=as.Date(retirement_date)) %>%
    mutate(appointment_date=as.Date(appointment_date))

activist_directors_3 <-
    gs_read(gs, ws = "Extra2") %>%
    mutate(appointment_date=as.Date(appointment_date))

cols_to_keep <- intersect(colnames(activist_directors_2),
                          colnames(activist_directors_3))

activist_directors_1 <-
    gs_read(gs, ws = "activist_directors") %>%
    mutate(retirement_date=ifelse(grepl("[A-Za-z]", retirement_date),
                                  NA, retirement_date)) %>%
    mutate(retirement_date=as.Date(retirement_date)) %>%
    mutate(appointment_date=as.Date(appointment_date)) %>%
    left_join(factset.campaign_ids) %>%
    select(one_of(cols_to_keep))

# activist_affiliate
activist_directors <-
    bind_rows(activist_directors_1, activist_directors_2,
              activist_directors_3) %>%
    # Clean up variables: clean up names
    mutate(first_name=gsub("\\n", "", first_name),
           last_name=gsub("\\n", "", last_name)) %>%
    filter(!is.na(appointment_date)) %>%
    mutate(activist_affiliate=independent==0L & !is.na(independent)) %>%
    select(-synopsis_text)

# Export dataset to PostgreSQL (activist_director.activist_directors) ----
library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

rs <- dbWriteTable(pg, c("activist_director", "activist_directors"),
                   activist_directors, overwrite=TRUE, row.names=FALSE)
#
rs <- dbGetQuery(pg, "ALTER TABLE activist_director.activist_directors OWNER TO activism")

rs <- dbGetQuery(pg, "VACUUM activist_director.activist_directors")

sql <- paste0("
  COMMENT ON TABLE activist_director.activist_directors IS
    'CREATED USING import_activist_directors.R ON ", Sys.time() , "';")

rs <- dbGetQuery(pg, sql)
