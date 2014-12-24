# Import Dataset from Google Drive ----
getSheetData = function(key, gid=NULL) {
    library(RCurl)
    url <- paste0("https://docs.google.com/spreadsheets/d/", key,
                  "/export?format=csv&id=", key, if (is.null(gid)) "" else paste0("&gid=", gid),
                  "&single=true")
    csv_file <- getURL(url, verbose=FALSE)
    the_data <- read.csv(textConnection(csv_file), as.is=TRUE)
    return( the_data )
}

key <- "1zHSKIAx4LKURXav-k06D7T3p3St0VjFa8RXvAFJnUfI"
activist_directors <- getSheetData(key, gid="271850810")

# Fix variable names
names(activist_directors) <- gsub("\\.+", "_", tolower(names(activist_directors)))
names(activist_directors) <- gsub("_s_", "_", names(activist_directors))
names(activist_directors) <- gsub("_$", "", names(activist_directors))

# Clean up variables: clean up names
activist_directors$first_name <- gsub("\\n", "", activist_directors$first_name)
activist_directors$first_name <- gsub("\\s+$", "", activist_directors$first_name)

# Clean up variables: set to correct type
activist_directors$issuer_cik <- as.integer(activist_directors$issuer_cik)
activist_directors$cusip_9_digit <- gsub(pattern="^'+", "", activist_directors$cusip_9_digit)
activist_directors$permno <- as.integer(activist_directors$permno)
activist_directors$announce_date <- as.Date(activist_directors$announce_date)
activist_directors$appointment_date <- as.Date(activist_directors$appointment_date)
activist_directors$retirement_date <- as.Date(activist_directors$retirement_date)
activist_directors$dissident_board_seats_wongranted_date <-
  as.Date(activist_directors$dissident_board_seats_wongranted_date)
activist_directors$activist_affiliate <- !as.logical(activist_directors$independence)
activist_directors <- subset(activist_directors,
                       subset=!is.na(appointment_date),
                       select=c(gss_id, announce_date, cusip_9_digit,
                                dissident_group, first_name, last_name,
                                activist_affiliate, appointment_date,
                                dissident_board_seats_wongranted_date,
                                retirement_date, issuer_cik))

# Export da taset to PostgreSQL (activist_director.activist_directors) ----
library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

rs <- dbWriteTable(pg, c("activist_director", "activist_directors_temp"),
                   activist_directors, overwrite=TRUE, row.names=FALSE)
# rs <- dbGetQuery(pg, "CREATE ROLE activism")

rs <- dbGetQuery(pg, "
    DROP TABLE IF EXISTS activist_director.activist_directors;

    CREATE TABLE activist_director.activist_directors AS
    SELECT b.campaign_id, a.*
    FROM activist_director.activist_directors_temp AS a
	LEFT JOIN factset.campaign_ids AS b
	USING (cusip_9_digit, dissident_group, announce_date)")

dbGetQuery(pg, "DROP TABLE activist_director.activist_directors_temp")

rs <- dbGetQuery(pg, "
    ALTER TABLE activist_director.activist_directors OWNER TO activism")

rs <- dbGetQuery(pg, "VACUUM activist_director.activist_directors")

sql <- paste("
  COMMENT ON TABLE activist_director.activist_directors IS
    'CREATED USING import_activist_directors.R ON ", Sys.time() , "';", sep="")

rs <- dbGetQuery(pg, sql)
