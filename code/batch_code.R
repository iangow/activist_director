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
source("code/import_activist_ciks.R")

# Column 5
source('code/create_activism_events.R', echo=TRUE)

source("code/import_key_dates.R")

runSQL("code/create_activist_director_matched.sql")
pg_comment("activist_director.activist_director_matched",
           "CREATED USING activist_director_matched.sql")

## Already done!!!
runSQL("code/create_activist_holdings.sql")

runSQL('code/create_equilar_directors.sql')
pg_comment("activist_director.equilar_directors",
           "CREATED USING create_equilar_directors.sql")

source('code/create_equilar_w_activism.R', echo=TRUE)





runSQL("code/create_view_financials.sql")
pg_comment("activist_director.financials",
           "CREATED USING create_view_financials.sql")



# This one takes a long time to run!
source("code/create_activist_holdings_matched_ss.R", echo=TRUE)






runSQL('code/create_first_voting.sql')

source('code/create_activist_director_equilar.R', echo=TRUE)

source('code/create_equilar_w_activism.R', echo=TRUE)

# Column 6
source('code/import_key_dates.R', echo=TRUE)


# Column 7
# Need CRSP, Compustat, IBES, director.percent_owned
runSQL('code/create_outcome_controls.sql')
