# Import Dataset from Google Drive ----
library(googlesheets)
library(dplyr, warn.conflicts = FALSE)
library(DBI)

pg <- dbConnect(RPostgreSQL::PostgreSQL())

rs <- dbExecute(pg, "SET search_path TO activist_director, public")

activist_directors <-
    tbl(pg, sql("SELECT *
                FROM activist_director.activist_directors
                WHERE retirement_date >= '2009-12-21' OR retirement_date IS NULL
                ORDER BY permno, appointment_date")) %>%
    collect()

write.csv(activist_directors, "activist_director_skills.csv", row.names=FALSE)
