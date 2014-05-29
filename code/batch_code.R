library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

pgSchemaExists <- function(conn, schema) {
    
    temp <- dbGetQuery(conn, paste0(
        "SELECT schema_name 
        FROM information_schema.schemata
        WHERE schema_name = '", schema, "'"))

    return(dim(temp)[1]>0)
}

if (!pgSchemaExists(pg, "activist_director")) {
    rs <- dbGetQuery(pg, "CREATE SCHEMA activist_director")
}

rs <- dbDisconnect(pg)

source("code/import_activist_ciks.R")

runSQL <- function(sql_file) {
    library(RPostgreSQL)
    pg <- dbConnect(PostgreSQL())
    sql <- paste(readLines(sql_file), collapse="\n")
    rs <- dbGetQuery(pg, sql)
    dbDisconnect(pg)
}

runSQL("code/create_activist_holdings.sql")