###############################################################
#
# This file imports the following data from Google Drive:
#   - sw50_ciks
#
###############################################################

# Get data from Google Sheets ----
library(googlesheets4)
library(dplyr, warn.conflicts = FALSE)
library(DBI)

# You might need to run gs_auth() before the following works:

key <- "1TZi_Mp3RUIwjuFoUcXnmOOCJUcnMZgk4bnO51TUGYgk"

activist_ciks <-
    read_sheet(key, sheet = "sw50_cik", col_types = "cilc") %>%
    mutate(non_activist = coalesce(non_activist, FALSE))

activist_names <-
    read_sheet(key, sheet = "activist_names", col_types="ccc") %>%
    select(-notes)

# Push data to PostgreSQL ----
pg <- dbConnect(RPostgres::Postgres())

dbExecute(pg, "SET search_path TO factset")

rs <- dbWriteTable(pg, "activist_names",
                   activist_names, overwrite=TRUE, row.names=FALSE)

rs <- dbWriteTable(pg, "activist_ciks_temp",
                   activist_ciks, overwrite=TRUE, row.names=FALSE)

rs <- dbExecute(pg, "DROP TABLE IF EXISTS activist_ciks")

rs <- dbExecute(pg, "
    CREATE TABLE activist_ciks AS
    WITH names AS (
        SELECT cik, array_agg(DISTINCT activist_name) AS activist_names
        FROM activist_ciks_temp
        WHERE NOT non_activist
        GROUP BY cik),

    ciks AS (
        SELECT activist_name, array_agg(cik) AS ciks
        FROM activist_ciks_temp
        GROUP BY activist_name),

    processed AS (
        SELECT DISTINCT unnest(activist_names) AS activist_name, ciks
        FROM names AS a
        INNER JOIN ciks AS b
        ON a.cik = ANY(b.ciks))

    SELECT DISTINCT activist_name, unnest(ciks) AS cik
    FROM processed")

rs <- dbExecute(pg, "DROP TABLE IF EXISTS activist_ciks_temp")

rs <- dbExecute(pg, "ALTER TABLE activist_ciks OWNER TO factset")
rs <- dbExecute(pg, "ALTER TABLE activist_names OWNER TO factset")
rs <- dbExecute(pg, "VACUUM activist_ciks")

sql <- paste("COMMENT ON TABLE activist_names IS
    'CREATED USING import_activist_ciks.R ON ", Sys.time() , "';", sep="")
sql <- paste("COMMENT ON TABLE activist_ciks IS
    'CREATED USING import_activist_ciks.R ON ", Sys.time() , "';", sep="")
rs <- dbExecute(pg, sql)
rs <- dbDisconnect(pg)
