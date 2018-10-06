# Program that captures the data steps for activist_director project

library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

rs <- dbGetQuery(pg, "
    CREATE SCHEMA IF NOT EXISTS activist_director;

    ALTER SCHEMA activist_director OWNER TO activism;")

rs <- dbGetQuery(pg, "
    DROP AGGREGATE IF EXISTS product(double precision);

    CREATE AGGREGATE product(double precision) (
        SFUNC=float8mul,
        STYPE=float8
    )")
rs <- dbDisconnect(pg)

runSQL <- function(sql_file) {
    library(RPostgreSQL)
    pg <- dbConnect(PostgreSQL())
    sql <- paste(readLines(sql_file), collapse="\n")
    rs <- dbGetQuery(pg, sql)
    dbDisconnect(pg)
}

pg_comment <- function(table, comment) {
    library(RPostgreSQL)
    pg <- dbConnect(PostgreSQL())
    sql <- paste0("COMMENT ON TABLE ", table, " IS '",
                  comment, " ON ", Sys.time() , "'")
    rs <- dbGetQuery(pg, sql)
    dbDisconnect(pg)
}

source("code/import_activist_directors.R")

# Column 6
source('code/import_key_dates.R', echo=TRUE)

# Column 5
source('code/create_activism_sample.R', echo=TRUE)
source('code/create_activism_events.R', echo=TRUE)

# This one takes a long time to run (~23 minutes)
source("code/create_activist_holdings.R", echo=TRUE)

# runSQL('code/create_first_voting.sql')
source('code/create_activist_director_equilar.R', echo=TRUE)
source('code/create_equilar_w_activism.R', echo=TRUE)
source('code/create_iss_voting.R', echo=TRUE)

source('~/git/activist_director/code/create_equilar_final.R')
source('~/git/activist_director/code/create_equilar_career.R')
runSQL('code/activist_director_career_analysis.SQL')

# Column 7
# Need CRSP, Compustat, IBES, director.percent_owned
source('code/create_outcome_controls.R', echo=TRUE)
