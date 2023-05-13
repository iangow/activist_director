library(DBI)
library(dplyr)

pg <- dbConnect(RPostgres::Postgres(), bigint = "integer")

rs <- dbExecute(pg, "SET search_path TO activist_director")
rs <- dbExecute(pg, "SET work_mem='3GB'")

rs <- dbExecute(pg, "DROP TABLE IF EXISTS other_outcomes")

outcomes <-
    tbl(pg, sql(paste0(readLines("code/other_outcomes.sql"), collapse="\n"))) %>%
    compute(name = "other_outcomes", temporary = FALSE)

sql <- "ALTER TABLE other_outcomes OWNER TO activism"
rs <- dbExecute(pg, sql)

sql <- paste0("COMMENT ON TABLE other_outcomes IS
        'CREATED USING create_other_outcomes.R ON ",
              format(Sys.time(), "%Y-%m-%d %X %Z"), "';")

rs <- dbExecute(pg, sql)

rs <- dbDisconnect(pg)
