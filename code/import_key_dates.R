#### Functions ####
# Fix Cusips
fixCUSIPs <- function(cusips) {
  to.fix <- nchar(cusips) < 9 & nchar(cusips) > 0
  cusips[to.fix] <- sprintf("%09d", as.integer(cusips[to.fix]))
  return(cusips)
}

#### Sharkwatch 50 ####
# Import Dataset from Google Drive ----
require(RCurl)
csv_file <- getURL(paste0("https://docs.google.com/spreadsheet/pub?key=",
                          "0AtCJeBFBO_EddHNGTEdra29BX0YxZHdIRVN0SFE0TWc",
                          "&single=true&gid=0&output=csv"),
                   verbose=FALSE)

key_dates_sw50 <- read.csv(textConnection(csv_file), stringsAsFactors=FALSE)

key_dates_sw50$event_date <- as.Date(key_dates_sw50$event_date)
key_dates_sw50$announce_date <- as.Date(key_dates_sw50$announce_date)
key_dates_sw50$cusip_9_digit <- fixCUSIPs(key_dates_sw50$cusip_9_digit)

for (i in names(key_dates_sw50)) {
    if (is.numeric(key_dates_sw50[,i])) key_dates_sw50[,i] <- !is.na(key_dates_sw50[,i])
}

# Import Dataset from Google Drive ----
# SHARKWATCH50 2012
require(RCurl)
csv_file <- getURL(paste0("https://docs.google.com/spreadsheet/pub?key=",
                          "0AtCJeBFBO_EddFJ6YVQtWlVOcTItYzlmUklOU1N2OFE",
                          "&output=csv"),
                   verbose=FALSE)
key_dates_2012 <- read.csv(textConnection(csv_file), stringsAsFactors=FALSE)

key_dates_2012$event_date <- as.Date(key_dates_2012$event_date)
key_dates_2012$announce_date <- as.Date(key_dates_2012$announce_date)
key_dates_2012$cusip_9_digit <- fixCUSIPs(key_dates_2012$cusip_9_digit)

for (i in names(key_dates_2012)) {
    if (is.numeric(key_dates_2012[,i])) key_dates_2012[,i] <- !is.na(key_dates_2012[,i])
}

key_dates_sw50 <- rbind(key_dates_sw50, key_dates_2012)
rm(key_dates_2012)

# Export dataset to PostgreSQL (activist_director.activist_directors) ----
library(RPostgreSQL)
drv <- dbDriver("PostgreSQL")
pg <- dbConnect(drv, dbname="crsp")

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
        bool_or(sell_company OR take_control_private) AS sell_company,
        bool_or(strategic_alternatives OR growth_strategy OR against_deal_acquirer OR against_deal_target) AS strategic_alternatives,
        bool_or(operational_efficiency OR capital_restructure) AS operational_efficiency,
        bool_or(compensation) AS ceo_comp,
        bool_or(governance_general OR
                poison_pill OR
                oust_ceo_director OR
                withhold_votes OR
                board_restructuring OR
                more_disclosure OR
                separate_chairman_ceo) AS governance
    FROM activist_director.key_dates_sw50
    WHERE event_date IS NOT NULL
    GROUP BY cusip_9_digit, announce_date, dissident_group, event_date
    ")


#### Non-Sharkwatch 50 ####
# Import Dataset from Google Drive ----
require(RCurl)

csv_file <- getURL(paste0("https://docs.google.com/spreadsheet/pub?key=",
                          "0AtCJeBFBO_EddEdMMXpRTUFUaUJzcTZHeEFLd0hrSkE",
                          "&output=csv"),
                          verbose=FALSE)

key_dates_nsw50 <- read.csv(textConnection(csv_file), stringsAsFactors=FALSE)

key_dates_nsw50$cusip_9_digit <- fixCUSIPs(key_dates_nsw50$cusip_9_digit)
key_dates_nsw50$announce_date <- as.Date(key_dates_nsw50$announce_date)
key_dates_nsw50$event_date <- as.Date(key_dates_nsw50$event_date)

for (i in names(key_dates_nsw50)) {
    if (is.numeric(key_dates_nsw50[,i])) key_dates_nsw50[,i] <- !is.na(key_dates_nsw50[,i])
}

# Export da taset to PostgreSQL (activist_director.activist_directors) ----
library(RPostgreSQL)
drv <- dbDriver("PostgreSQL")
pg <- dbConnect(drv, dbname="crsp")

rs <- dbWriteTable(pg, c("activist_director", "key_dates_nsw50"),
                   key_dates_nsw50, overwrite=TRUE, row.names=FALSE)
# rs <- dbGetQuery(pg, "CREATE ROLE activism")
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

#### Aggregation ----
agg_data <- rbind(sw50_data, nsw50_data)

agg_data$announce_date <- as.Date(agg_data$announce_date)
agg_data$event_date <- as.Date(agg_data$event_date)

rs <- dbWriteTable(pg, c("activist_director", "key_dates_all"),
                   agg_data, overwrite=TRUE, row.names=FALSE)
# rs <- dbGetQuery(pg, "CREATE ROLE activism")
rs <- dbGetQuery(pg, "
    ALTER TABLE activist_director.key_dates_all OWNER TO activism")

rs <- dbGetQuery(pg, "VACUUM activist_director.key_dates_all")

sql <- paste("
  COMMENT ON TABLE activist_director.key_dates_all IS
    'CREATED USING import_key_dates.R ON ", Sys.time() , "';", sep="")
rs <- dbGetQuery(pg, sql)





# first_board_demand_date
temp <- dbGetQuery(pg, "
WITH first_board_demand_date AS (
SELECT DISTINCT cusip_9_digit, announce_date, dissident_group, min(event_date) AS first_board_demand_date
FROM activist_director.key_dates_all
WHERE board_demand
GROUP BY cusip_9_digit, announce_date, dissident_group)

SELECT DISTINCT a.*, b.first_board_demand_date, b.first_board_demand_date IS NOT NULL AS board_demand
FROM activist_director.activism_events AS a
LEFT JOIN first_board_demand_date AS b
ON a.cusip_9_digit=b.cusip_9_digit AND a.announce_date=b.announce_date AND a.dissident_group=b.dissident_group
ORDER BY permno, announce_date, dissident_group
")




# #### Classifications ####
# # Board Representation
# sw50_data$nominate <- grepl('(?:nomin(?:ee|at))', sw50_data$event_texts)
# sw50_data$candidate <- grepl('(?:represent*|candidate)', sw50_data$event_texts)
# with(sw50_data, table(candidate | nominate, board_demand))
# subset(sw50_data, candidate & nominate & !board_demand)[1:20,]
#
# # Payouts
# sw50_data$repurchase <- grepl('(repurch|buy-?back)', sw50_data$event_texts)
# sw50_data$dividend <- grepl('(dividend|return.{1,15}cash)', sw50_data$event_texts)
# with(sw50_data, table(repurchase | dividend, payout))
#
# # Sale/Divestiture
# sw50_data$divest <- grepl('(sale|sell|divest|spin)', sw50_data$event_texts)
# with(sw50_data, table(divest, divest_demand))
#
# # Strategic Alternatives
# sw50_data$strategy <- grepl('(strateg)', sw50_data$event_texts)
# with(sw50_data, table(strategy, strategic_alternatives))
#
# # Operational Efficiency
# sw50_data$oper <- grepl('(operat|improv)', sw50_data$event_texts)
# with(sw50_data, table(oper, operational_efficiency))
#
# # Governance
# sw50_data$govern <- grepl('(governance)', sw50_data$event_texts)
# with(sw50_data, table(govern, governance))
#
# # CEO Compensation
# sw50_data$comp <- grepl('(compensat)', sw50_data$event_texts)
# with(sw50_data, table(comp, compensation))
#
# #"(nomin(ee|at)|candida)";"(sale|sell|divest|spin)";"(repurch|buy-?back|dividend|return.{1,15}cash)";"(merge|acqui[rs])";"(compensat)";"(strateg)";"(operat|improv)";"(governan)";"(13D)"
