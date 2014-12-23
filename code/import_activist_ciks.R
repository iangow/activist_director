###############################################################
#
# This file imports the following data from Google Drive:
#   - sw50_ciks
#   - sw50_names (short names for each of the members of
#     SharkWatch50)
#
###############################################################

# Program to read in CIKs of activists.

# Function to retrieve a Google Sheets document
getSheetData = function(key, gid=NULL) {
    library(RCurl)
    url <- paste0("https://docs.google.com/spreadsheets/d/", key,
                  "/export?format=csv&id=", key, if (is.null(gid)) "" else paste0("&gid=", gid),
                  "&single=true")
    csv_file <- getURL(url, verbose=FALSE)
    the_data <- read.csv(textConnection(csv_file), as.is=TRUE)
    return( the_data )
}

key <- "1TZi_Mp3RUIwjuFoUcXnmOOCJUcnMZgk4bnO51TUGYgk"
activist_ciks <- getSheetData(key, gid="1889075352")
# "968776406")

activist_ciks$non_activist <- !is.na(activist_ciks$non_activist)
activist_ciks$cik <- as.integer(activist_ciks$cik)

library(RPostgreSQL)

pg <- dbConnect(PostgreSQL())

rs <- dbWriteTable(pg, c("activist_director", "activist_ciks_temp"),
                   activist_ciks, overwrite=TRUE, row.names=FALSE)

rs <- dbGetQuery(pg, "
    DROP TABLE IF EXISTS activist_director.activist_ciks;

    CREATE TABLE activist_director.activist_ciks AS
    WITH names AS (
      SELECT cik, array_agg(DISTINCT activist_name) AS activist_names
      FROM activist_director.activist_ciks_temp
      WHERE NOT non_activist
      GROUP BY cik),

    ciks AS (
      SELECT activist_name, array_agg(cik) AS ciks
      FROM activist_director.activist_ciks_temp
      GROUP BY activist_name),

    processed AS (
      SELECT DISTINCT unnest(activist_names) AS activist_name, ciks
      FROM names AS a
      INNER JOIN ciks AS b
      ON a.cik = ANY(b.ciks))

    SELECT DISTINCT activist_name, unnest(ciks) AS cik
    FROM processed;

    DROP TABLE IF EXISTS activist_director.activist_ciks_temp; ")

rs <- dbGetQuery(pg, "ALTER TABLE activist_director.activist_ciks OWNER TO activism")
rs <- dbGetQuery(pg, "VACUUM activist_director.activist_ciks")

sql <- paste("COMMENT ON TABLE activist_director.activist_ciks IS
    'CREATED USING import_activist_ciks.R ON ", Sys.time() , "';", sep="")
rs <- dbGetQuery(pg, sql)
rs <- dbDisconnect(pg)
rm(activist_ciks)


