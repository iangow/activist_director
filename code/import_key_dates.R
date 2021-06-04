library(googlesheets4)
library(DBI)
library(dplyr, warn.conflicts = FALSE)

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
key <- '1s8-xvFxQZd6lMrxfVqbPTwUB_NQtvdxCO-s6QCIYvNk'

#### Sharkwatch 50 ####
# Import Dataset from Google Drive ----
key_dates_sw50 <-
    key %>%
    read_sheet(sheet = "sw50_2004_2012",
               col_types = paste(c("cDccDl", rep("c", 39)), collapse="")) %>%
    mutate_at(vars(one_of(get_booleans(.))), convert_logical) %>%
    select(-etc) %>%
    mutate(gid = "sw50_2004_2012")

# SHARKWATCH50 2012
key_dates_2012 <-
    key %>%
    read_sheet(sheet = "sw_2012",
               col_types = paste(c("cDccDl", rep("c", 38)), collapse="")) %>%
    mutate_at(vars(one_of(get_booleans(.))), convert_logical) %>%
    mutate(gid = "sw_2012") %>%
    mutate(across(c(third_other, support_management, no_outcome,
                    multiple_outcome), as.logical))

key_dates_sw50 <- bind_rows(key_dates_sw50, key_dates_2012)

key_dates_2013 <-
    key %>%
    read_sheet(sheet = "sw_2013",
                col_types = paste(c("cDccDl", rep("c", 38)), collapse="")) %>%
    mutate_at(vars(one_of(get_booleans(.))), convert_logical) %>%
    mutate(gid = "sw_2013") %>%
    mutate(across(c(growth_strategy, vote_for_dissident_proposal,
                    support_management, third_other, no_outcome,
                    multiple_outcome), as.logical))

key_dates_sw50 <- bind_rows(key_dates_sw50, key_dates_2013)
rm(key_dates_2013)

#### Non-Sharkwatch 50 ####
key_dates_nsw50 <-
    key %>%
    read_sheet(sheet = "non_sw50") %>%
    mutate_at(vars(one_of(get_booleans(.))), convert_logical) %>%
    mutate(gid = "non_sw50")

# Use PostgreSQL to reshape the data ----


pg <- dbConnect(RPostgres::Postgres())

rs <- dbExecute(pg, "SET search_path TO activist_director")

rs <- dbWriteTable(pg, "key_dates_sw50",
                   key_dates_sw50, overwrite=TRUE, row.names=FALSE)

rs <- dbExecute(pg, "ALTER TABLE key_dates_sw50 OWNER TO activism")

rs <- dbExecute(pg, "VACUUM key_dates_sw50")

sql <- paste("
  COMMENT ON TABLE key_dates_sw50 IS
    'CREATED USING import_key_dates.R ON ", format(Sys.time(), "%Y-%m-%d %X %Z"), "';", sep="")
rs <- dbExecute(pg, sql)

# Demand aggregation ----
key_dates_sw50 <- tbl(pg, "key_dates_sw50")

rs <- dbExecute(pg, "DROP TABLE IF EXISTS key_dates_nsw50")

key_dates_sw50 <-
  key_dates_sw50 %>%
  filter(!is.na(event_date)) %>%
  group_by(cusip_9_digit, announce_date, dissident_group, event_date, gid) %>%
  summarize(board_demand = any(board_representation),
             payout = any(dividend_repurchase),
             divest = any(focus_spin_off),
             sell_company = any(sell_company | take_control_private),
             strategic_alternatives = any(strategic_alternatives
                     | growth_strategy
                     | against_deal_acquirer
                     | against_deal_target),
             operational_efficiency = any(operational_efficiency
                     | capital_restructure),
             ceo_comp = any(compensation),
             governance = any(governance_general
                     | poison_pill
                     | oust_ceo_director
                     | withhold_votes
                     | board_restructuring
                     | more_disclosure
                     | separate_chairman_ceo),
            .groups = "drop") %>%
  compute(name = "key_dates_nsw50", temporary = FALSE)

rs <- dbExecute(pg, "ALTER TABLE key_dates_nsw50 OWNER TO activism")

rs <- dbExecute(pg, "VACUUM key_dates_nsw50")

sql <- paste("
  COMMENT ON TABLE key_dates_nsw50 IS
    'CREATED USING import_key_dates.R ON ",
             format(Sys.time(), "%Y-%m-%d %X %Z"), "';", sep="")
rs <- dbExecute(pg, sql)

# Demand aggregation ----
key_dates_nsw50 <- tbl(pg, "key_dates_nsw50")

nsw50_data <-
    key_dates_nsw50 %>%
    filter(!is.na(event_date)) %>%
    group_by(cusip_9_digit, announce_date, dissident_group, event_date, gid) %>%
    summarize(board_demand = bool_or(board_rep),
              payout =bool_or(payout),
              divest = bool_or(divest),
              sell_company = bool_or(sell_company),
              strategic_alternatives = bool_or(strategic_alt),
              operational_efficiency = bool_or(oper_efficiency),
              ceo_comp = bool_or(ceo_comp),
              governance = bool_or(governance)) %>%
  collect()

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
    DROP TABLE key_dates_long;
    DROP TABLE key_dates_nsw50;
    DROP TABLE key_dates_sw50;")

rs <- dbGetQuery(pg, "ALTER TABLE key_dates OWNER TO activism")

rs <- dbGetQuery(pg, "VACUUM key_dates")

sql <- paste("
  COMMENT ON TABLE key_dates IS
    'CREATED USING import_key_dates.R ON ", format(Sys.time(), "%Y-%m-%d %X %Z"), "';", sep="")
rs <- dbGetQuery(pg, sql)

rs <- dbDisconnect(pg)
