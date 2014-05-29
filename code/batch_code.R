# Program that captures the data steps for activist_director project

library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

rs <- dbGetQuery(pg, "
    CREATE SCHEMA IF NOT EXISTS activist_director")

rs <- dbGetQuery(pg, "
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

source("code/import_activist_ciks.R")

runSQL("code/create_activist_holdings.sql")

source('code/create_activism_events.R', echo=TRUE)

source('code/create_equilar_w_activism.R', echo=TRUE)

runSQL("code/create_activist_director_matched.sql")

runSQL('code/create_equilar_directors.sql')

runSQL('code/create_first_voting.sql')

source('code/create_activist_director_equilar.R', echo=TRUE)

source('code/create_equilar_w_activism.R', echo=TRUE)

# Column 6
source('code/import_key_dates.R', echo=TRUE)

# Column 5
source('code/create_activism_events.R', echo=TRUE)

# Column 7
# Need CRSP, Compustat, IBES, director.percent_owned
runSQL('code/create_outcome_controls.sql')