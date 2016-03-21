# Functions ----
# Fix Cusips
fixCUSIPs <- function(cusips) {
  to.fix <- nchar(cusips) < 9 & nchar(cusips) > 0
  cusips[to.fix] <- sprintf("%09d", as.integer(cusips[to.fix]))
  return(cusips)
}

# Function to retrieve a Google Sheets document
getSheetData = function(key, gid=NULL) {
    library(RCurl)
    url <- paste0("https://docs.google.com/spreadsheets/d/", key,
                  "/export?format=csv&id=", key,
                  if (is.null(gid)) "" else paste0("&gid=", gid),
                  "&single=true")
    csv_file <- getURL(url, verbose=FALSE)
    the_data <- read.csv(textConnection(csv_file), as.is=TRUE)
    return( the_data )
}

# Get data from Google Sheets ----
# Get PERMNO-CIK data
key='1s8-xvFxQZd6lMrxfVqbPTwUB_NQtvdxCO-s6QCIYvNk'

#### Sharkwatch 50 ####
# Import Dataset from Google Drive ----
key_dates_sw50 <- getSheetData(key, gid=1862254343)
key_dates_sw50$event_date <- as.Date(key_dates_sw50$event_date)
key_dates_sw50$announce_date <- as.Date(key_dates_sw50$announce_date)
key_dates_sw50$cusip_9_digit <- fixCUSIPs(key_dates_sw50$cusip_9_digit)
key_dates_sw50$etc <- NULL

for (i in names(key_dates_sw50)) {
    if (is.numeric(key_dates_sw50[,i])) key_dates_sw50[,i] <- !is.na(key_dates_sw50[,i])
}

# SHARKWATCH50 2012
key_dates_2012 <- getSheetData(key, gid=1226808791)

key_dates_2012$event_date <- as.Date(key_dates_2012$event_date)
key_dates_2012$announce_date <- as.Date(key_dates_2012$announce_date)
key_dates_2012$cusip_9_digit <- fixCUSIPs(key_dates_2012$cusip_9_digit)

for (i in names(key_dates_2012)) {
    if (is.numeric(key_dates_2012[,i])) key_dates_2012[,i] <- !is.na(key_dates_2012[,i])
}

key_dates_sw50 <- rbind(key_dates_sw50, key_dates_2012)
rm(key_dates_2012)

key_dates_2013 <- getSheetData(key, gid=1841891641)

key_dates_2013$event_date <- as.Date(key_dates_2013$event_date)
key_dates_2013$announce_date <- as.Date(key_dates_2013$announce_date)
key_dates_2013$cusip_9_digit <- fixCUSIPs(key_dates_2013$cusip_9_digit)

for (i in names(key_dates_2013)) {
    if (is.numeric(key_dates_2013[,i])) key_dates_2013[,i] <- !is.na(key_dates_2013[,i])
}

key_dates_sw50 <- rbind(key_dates_sw50, key_dates_2013)
rm(key_dates_2013)

#### Non-Sharkwatch 50 ####
key_dates_nsw50 <- getSheetData(key, gid=1796687034)
key_dates_nsw50$cusip_9_digit <- fixCUSIPs(key_dates_nsw50$cusip_9_digit)
key_dates_nsw50$announce_date <- as.Date(key_dates_nsw50$announce_date)
key_dates_nsw50$event_date <- as.Date(key_dates_nsw50$event_date)

# TODO: Fix weird values in these two variables.
key_dates_nsw50$governance <- key_dates_nsw50$governance=="1"
key_dates_nsw50$no_demand <- key_dates_nsw50$no_demand=="1"

for (i in names(key_dates_nsw50)) {
    if (is.numeric(key_dates_nsw50[,i])) key_dates_nsw50[,i] <- !is.na(key_dates_nsw50[,i])
}

# Use PostgreSQL to reshape the data ----
library(RPostgreSQL)

pg <- dbConnect(PostgreSQL())
rs <- dbWriteTable(pg, c("activist_director", "key_dates_sw50"),
                   key_dates_sw50, overwrite=TRUE, row.names=FALSE)
# rs <- dbGetQuery(pg, "CREATE ROLE activism")
rs <- dbGetQuery(pg, "
    ALTER TABLE activist_director.key_dates_sw50 OWNER TO activism")

rs <- dbGetQuery(pg, "VACUUM activist_director.key_dates_sw50")

sql <- paste("
  COMMENT ON TABLE activist_director.key_dates_sw50 IS
    'CREATED USING import_key_dates.R ON ", Sys.time() , "';", sep="")
rs <- dbGetQuery(pg, sql)

# Demand aggregation ----
sw50_data <- dbGetQuery(pg, "
    SELECT cusip_9_digit, announce_date, dissident_group, event_date,
        bool_or(board_representation) AS board_demand,
        bool_or(dividend_repurchase) AS payout,
        bool_or(focus_spin_off) AS divest,
        bool_or(sell_company
                OR take_control_private) AS sell_company,
        bool_or(strategic_alternatives
                OR growth_strategy
                OR against_deal_acquirer
                OR against_deal_target) AS strategic_alternatives,
        bool_or(operational_efficiency
                OR capital_restructure) AS operational_efficiency,
        bool_or(compensation) AS ceo_comp,
        bool_or(governance_general
                OR poison_pill
                OR oust_ceo_director
                OR withhold_votes
                OR board_restructuring
                OR more_disclosure
                OR separate_chairman_ceo) AS governance
    FROM activist_director.key_dates_sw50
    WHERE event_date IS NOT NULL
    GROUP BY cusip_9_digit, announce_date, dissident_group, event_date
    ")

rs <- dbWriteTable(pg, c("activist_director", "key_dates_nsw50"),
                   key_dates_nsw50, overwrite=TRUE, row.names=FALSE)

rs <- dbGetQuery(pg, "
    ALTER TABLE activist_director.key_dates_nsw50 OWNER TO activism")

rs <- dbGetQuery(pg, "VACUUM activist_director.key_dates_nsw50")

sql <- paste("
  COMMENT ON TABLE activist_director.key_dates_nsw50 IS
    'CREATED USING import_key_dates.R ON ", Sys.time() , "';", sep="")
rs <- dbGetQuery(pg, sql)

# Demand aggregation ----
nsw50_data <- dbGetQuery(pg, "
    SELECT cusip_9_digit, announce_date, dissident_group, event_date,
        bool_or(board_rep) AS board_demand,
        bool_or(payout) AS payout,
        bool_or(divest) AS divest,
        bool_or(sell_company) AS sell_company,
        bool_or(strategic_alt) AS strategic_alternatives,
        bool_or(oper_efficiency) AS operational_efficiency,
        bool_or(ceo_comp) AS ceo_comp,
        bool_or(governance) AS governance
    FROM activist_director.key_dates_nsw50
    WHERE event_date IS NOT NULL
    GROUP BY cusip_9_digit, announce_date, dissident_group, event_date
")

key_dates <- rbind(nsw50_data, sw50_data)

library(reshape)
key_dates_long <- melt(key_dates,
                       id.vars=c("cusip_9_digit", "announce_date",
                           "dissident_group", "event_date"),
                       variable="demand_type")

key_dates_long <- subset(key_dates_long, value, select=-value)
key_dates_long$demand_type <- gsub("_demand$", "", key_dates_long$demand_type)
key_dates_long$announce_date <- as.Date(key_dates_long$announce_date)
key_dates_long$event_date <- as.Date(key_dates_long$event_date)

# Export dataset to PostgreSQL (activist_director.key_dates) ----
rs <- dbWriteTable(pg, c("activist_director", "key_dates_long"),
                   key_dates_long, overwrite=TRUE, row.names=FALSE)

rs <- dbGetQuery(pg, "
    DROP TABLE IF EXISTS activist_director.key_dates;

    CREATE TABLE activist_director.key_dates AS
    WITH key_dates AS (
        SELECT cusip_9_digit, announce_date, dissident_group,
            event_date AS demand_date,
            array_agg(demand_type) AS demand_types
        FROM activist_director.key_dates_long
        GROUP BY cusip_9_digit, announce_date, dissident_group, event_date)
    SELECT b.campaign_id, a.demand_date, a.demand_types
    FROM key_dates AS a
    LEFT JOIN factset.campaign_ids AS b
	USING (cusip_9_digit, dissident_group, announce_date)
    ORDER BY cusip_9_digit, announce_date, dissident_group, demand_date")

# Delete temporary tables
dbGetQuery(pg, "
    DROP TABLE activist_director.key_dates_long;
    DROP TABLE activist_director.key_dates_nsw50;
    DROP TABLE activist_director.key_dates_sw50;")

rs <- dbGetQuery(pg, "
    ALTER TABLE activist_director.key_dates OWNER TO activism")

rs <- dbGetQuery(pg, "VACUUM activist_director.key_dates")

sql <- paste("
  COMMENT ON TABLE activist_director.key_dates IS
    'CREATED USING import_key_dates.R ON ", Sys.time() , "';", sep="")
rs <- dbGetQuery(pg, sql)

rs <- dbDisconnect(pg)
