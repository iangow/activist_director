###############################################################
#
# This file imports the following data from Google Drive:
#   - sw50_ciks
#   - sw50_names (short names for each of the members of
#     SharkWatch50
#
###############################################################

# Program to read in CIKs of activists.
require(RCurl)
csv_file <- getURL(paste("https://docs.google.com/spreadsheet/pub?",
						 "key=0AvP4wvS7Nk-QdGVoTS1SakxaTF9PU2JzWmFaWXRFRmc&",
						 "single=true&gid=0&output=csv", sep=""),
                   verbose=FALSE)
activist_ciks <- read.csv(textConnection(csv_file), as.is=TRUE)

library(RPostgreSQL)
drv <- dbDriver("PostgreSQL")
pg <- dbConnect(drv)

activist_ciks$non_activist <- !is.na(activist_ciks$non_activist)
activist_ciks$cik <- as.integer(activist_ciks$cik)
# activist_ciks <- activist_ciks[, c("activist_name", "cik")]
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


