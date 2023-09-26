library(DBI)
library(dplyr, warn.conflicts = FALSE)
library(duckdb)

pg <- dbConnect(RPostgres::Postgres(), bigint = "integer")

rs <- dbExecute(pg, "SET search_path TO activist_director")

table_list <- dbListTables(pg)



db <- dbConnect(duckdb::duckdb())

dbExecute(db, "LOAD postgres_scanner")


export_table <- function(table) {
    dbExecute(db, paste0("COPY (SELECT * FROM postgres_scan_pushdown('', 'activist_director', '",
                     table,
                     "')) TO 'data/", table, ".parquet' (FORMAT PARQUET)"))
}

lapply(table_list, export_table)
