library(googlesheets)

# Functions ----
# Fix Cusips
fixCUSIPs <- function(cusips) {
  to.fix <- nchar(cusips) < 9 & nchar(cusips) > 0
  cusips[to.fix] <- sprintf("%09d", as.integer(cusips[to.fix]))
  return(cusips)
}

is_boolean <- function(vec) {
    if (length(setdiff(unique(vec), c(NA)))==0) return(FALSE)
    length(setdiff(unique(vec), c(NA, "0", "1")))==0
}

get_booleans <- function(df) {
    temp <- unlist(lapply(df, is_boolean))
    names(temp[temp])
}

convert_logical <- function(vec) {
    temp <- as.logical(vec)
    temp[is.na(temp)] <- FALSE
    temp
}

# Get data from Google Sheets ----
# Get PERMNO-CIK data
key='1s8-xvFxQZd6lMrxfVqbPTwUB_NQtvdxCO-s6QCIYvNk'
gs <- gs_key(key)

#### Sharkwatch 50 ####
# Import Dataset from Google Drive ----
key_dates_sw50 <-
    gs %>% gs_read(ws = "sw50_2004_2012",
                   col_types = paste(c("cDccDl", rep("c", 39)), collapse="")) %>%
    mutate_at(vars(one_of(get_booleans(.))), convert_logical) %>%
    select(-etc) %>%
    mutate(gid = "sw50_2004_2012")

# SHARKWATCH50 2012

key_dates_2012 <-
    gs %>%
    gs_read_csv(ws = "sw_2012",
                col_types = paste(c("cDccDl", rep("c", 38)), collapse="")) %>%
    mutate_at(vars(one_of(get_booleans(.))), convert_logical) %>%
    mutate(gid = "sw_2012")

key_dates_sw50 <- bind_rows(key_dates_sw50, key_dates_2012)

key_dates_2013 <-
    gs %>%
    gs_read_csv(ws = "sw_2013",
                col_types = paste(c("cDccDl", rep("c", 38)), collapse="")) %>%
    mutate_at(vars(one_of(get_booleans(.))), convert_logical) %>%
    mutate(gid = "sw_2013")

key_dates_sw50 <- bind_rows(key_dates_sw50, key_dates_2013)
rm(key_dates_2013)

#### Non-Sharkwatch 50 ####
key_dates_nsw50 <-
    gs %>%
    gs_read_csv(ws = "non_sw50") %>%
    mutate_at(vars(one_of(get_booleans(.))), convert_logical) %>%
    mutate(gid = "non_sw50")

# Use PostgreSQL to reshape the data ----
library(RPostgreSQL)

pg <- dbConnect(PostgreSQL())
rs <- dbWriteTable(pg, c("activist_director", "key_dates_sw50"),
                   key_dates_sw50, overwrite=TRUE, row.names=FALSE)
rs <- dbGetQuery(pg, "
    ALTER TABLE activist_director.key_dates_sw50 OWNER TO activism")

rs <- dbGetQuery(pg, "VACUUM activist_director.key_dates_sw50")

sql <- paste("
  COMMENT ON TABLE activist_director.key_dates_sw50 IS
    'CREATED USING import_key_dates.R ON ", format(Sys.time(), "%Y-%m-%d %X %Z"), "';", sep="")
rs <- dbGetQuery(pg, sql)

# Demand aggregation ----
sw50_data <- dbGetQuery(pg, "
    SELECT cusip_9_digit, announce_date, dissident_group, event_date, gid,
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
    GROUP BY cusip_9_digit, announce_date, dissident_group, event_date, gid")

rs <- dbWriteTable(pg, c("activist_director", "key_dates_nsw50"),
                   as.data.frame(key_dates_nsw50), overwrite=TRUE, row.names=FALSE)

rs <- dbGetQuery(pg, "
    ALTER TABLE activist_director.key_dates_nsw50 OWNER TO activism")

rs <- dbGetQuery(pg, "VACUUM activist_director.key_dates_nsw50")

sql <- paste("
  COMMENT ON TABLE activist_director.key_dates_nsw50 IS
    'CREATED USING import_key_dates.R ON ",
             format(Sys.time(), "%Y-%m-%d %X %Z"), "';", sep="")
rs <- dbGetQuery(pg, sql)

# Demand aggregation ----
nsw50_data <- dbGetQuery(pg, "
    SELECT cusip_9_digit, announce_date, dissident_group, event_date, gid,
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
    GROUP BY cusip_9_digit, announce_date, dissident_group, event_date, gid
")

key_dates <- rbind(nsw50_data, sw50_data)

key_dates_long <- reshape2::melt(key_dates,
                       id.vars=c("cusip_9_digit", "announce_date",
                           "dissident_group", "event_date", "gid"),
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
            array_agg(DISTINCT gid) AS gids,
            array_agg(DISTINCT demand_type) AS demand_types
        FROM activist_director.key_dates_long
        GROUP BY cusip_9_digit, announce_date,
            dissident_group, event_date, gid)
    SELECT c.campaign_id, a.demand_date,
        a.demand_types, a.gids
    FROM key_dates AS a
    LEFT JOIN factset.campaign_ids AS b
	USING (cusip_9_digit, dissident_group, announce_date)
    INNER JOIN activist_director.activism_events AS c
    ON b.campaign_id=ANY(c.campaign_ids)
    ORDER BY a.cusip_9_digit, a.announce_date, a.dissident_group, demand_date")

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
    'CREATED USING import_key_dates.R ON ", format(Sys.time(), "%Y-%m-%d %X %Z"), "';", sep="")
rs <- dbGetQuery(pg, sql)

rs <- dbDisconnect(pg)
