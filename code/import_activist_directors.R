# Import Dataset from Google Drive ----
library(googlesheets)

# As a one-time thing per user and machine, you will need to run gs_auth()
# to authorize googlesheets to access your Google Sheets.
gs <- gs_key("13TRLvEequPmsgZNSrqelm3aDnTtMN5N34TNUa7mk3Eo")

activist_directors <- as.data.frame(gs_read(gs, ws = "clean_up_version"))

# Fix variable names
names(activist_directors) <- gsub("\\.+", "_", tolower(names(activist_directors)))
names(activist_directors) <- gsub("_s_", "_", names(activist_directors))
names(activist_directors) <- gsub("_$", "", names(activist_directors))

# Clean up variables: clean up names
activist_directors$first_name <- gsub("\\n", "", activist_directors$first_name)
activist_directors$first_name <- gsub("\\s+$", "", activist_directors$first_name)

# Clean up variables: set to correct type
# activist_directors$issuer_cik <- as.integer(activist_directors$issuer_cik)
activist_directors$permno <- as.integer(activist_directors$permno)
activist_directors$cusip_9_digit <- gsub(pattern="^'+", "", activist_directors$cusip_9_digit)
activist_directors$eff_announce_date <- as.Date(activist_directors$eff_announce_date)
activist_directors$appointment_date <- as.Date(activist_directors$appointment_date)
activist_directors$retirement_date <- as.Date(activist_directors$retirement_date)
activist_directors$dissident_board_seats_wongranted_date <-
  as.Date(activist_directors$dissident_board_seats_wongranted_date)
# activist_directors$activist_affiliate <- !as.logical(activist_directors$independence)
activist_directors <- subset(activist_directors,
                       subset=!is.na(appointment_date),
                       select=c(permno, cusip_9_digit, eff_announce_date,
                                dissident_group,
                                dissident_board_seats_wongranted_date,
                                dissident_board_seats_won,
                                last_name, first_name,
                                appointment_date,
                                retirement_date, activist_affiliate))

# Export da taset to PostgreSQL (activist_director.activist_directors) ----
library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

rs <- dbWriteTable(pg, c("activist_director", "activist_directors"),
                   activist_directors, overwrite=TRUE, row.names=FALSE)
# rs <- dbGetQuery(pg, "CREATE ROLE activism")

# rs <- dbGetQuery(pg, "
#     DROP TABLE IF EXISTS activist_director.activist_directors;
#
#     CREATE TABLE activist_director.activist_directors AS
#     SELECT b.campaign_id, a.*
#     FROM activist_director.activist_directors_temp AS a
# 	LEFT JOIN factset.campaign_ids AS b
# 	USING (cusip_9_digit, dissident_group, announce_date)")
#
# dbGetQuery(pg, "DROP TABLE activist_director.activist_directors_temp")
#
rs <- dbGetQuery(pg, "
    ALTER TABLE activist_director.activist_directors OWNER TO activism")

rs <- dbGetQuery(pg, "VACUUM activist_director.activist_directors")

sql <- paste("
  COMMENT ON TABLE activist_director.activist_directors IS
    'CREATED USING import_activist_directors.R ON ", Sys.time() , "';", sep="")

rs <- dbGetQuery(pg, sql)
