#!/usr/bin/env Rscript
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

source("code/import_activist_directors.R")

# Column 6
source('code/import_key_dates.R', echo=TRUE)

# Column 5
source('code/create_activism_sample.R', echo=TRUE)
source('code/create_activism_events.R', echo=TRUE)
source('code/create_activist_demands.R', echo=TRUE)

# Returns around activism events
source('code/create_event_returns.R', echo=TRUE)

# This one takes a long time to run (~23 minutes)
source("code/create_activist_holdings.R", echo=TRUE)
source('code/create_inst.R', echo=TRUE)

source('code/create_activist_director_equilar.R', echo=TRUE)
source('code/create_equilar_w_activism.R', echo=TRUE)
source('code/create_equilar_final.R', echo=TRUE)
source('code/create_equilar_career.R', echo=TRUE)
source('code/create_equilar_type.R', echo=TRUE)

# Column 7
# Need CRSP, Compustat, IBES, director.percent_owned
source('code/create_outcome_controls.R', echo=TRUE)
source('code/create_ceo_outcomes.R', echo=TRUE)
source('code/create_activist_director_years.R', echo=TRUE)
