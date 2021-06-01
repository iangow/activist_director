#!/usr/bin/env Rscript
# Program that captures the data steps for activist_director project

library(DBI)
pg <- dbConnect(RPostgres::Postgres())

rs <- dbExecute(pg, "CREATE SCHEMA IF NOT EXISTS activist_director")
rs <- dbExecute(pg, "ALTER SCHEMA activist_director OWNER TO activism")

rs <- dbExecute(pg, "DROP AGGREGATE IF EXISTS product(double precision)")
rs <- dbExecute(pg, "
    CREATE AGGREGATE product(double precision) (
        SFUNC=float8mul,
        STYPE=float8
    )")

rs <- dbExecute(pg, "CREATE OR REPLACE FUNCTION array_min(an_array integer[])
    RETURNS integer AS
    $BODY$
        WITH unnested AS (
            SELECT UNNEST(an_array) AS ints)
        SELECT min(ints)
        FROM unnested
    $BODY$ LANGUAGE sql;")

rs <- dbDisconnect(pg)

source('code/create_permnos.R', echo=TRUE)
source('code/create_activism_sample.R', echo=TRUE)
source("code/import_activist_directors.R")

# Column 6
source('code/import_key_dates.R', echo=TRUE)

# Column 5
source('code/create_prior_campaigns.R', echo=TRUE)
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
source('code/create_activism_events_equilar.R', echo=TRUE)

# Column 7
# Need CRSP, Compustat, IBES, director.percent_owned
source('code/create_outcome_controls.R', echo=TRUE)
source('code/create_ceo_outcomes.R', echo=TRUE)
source('code/create_activist_director_years.R', echo=TRUE)
