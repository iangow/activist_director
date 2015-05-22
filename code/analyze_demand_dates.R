library(tidyr)
library(dplyr)

set_to_indicator <- function(df, var) {

    df %>%
        mutate_(indicator = ~TRUE) %>%
        spread_(var, "indicator", fill=FALSE)
}

cor_ind <- function(df) {
    cor(df[, unlist(lapply(df, is.logical))])
}

pg <- src_postgres()

key_dates <- tbl(pg, dplyr::sql("
    SELECT campaign_id, demand_date, UNNEST(demand_types) AS demand_type
    FROM activist_director.key_dates"))

activism_events <- tbl(pg, dplyr::sql("
    SELECT *
    FROM activist_director.activism_events"))

event_tbl <- left_join(activism_events, key_dates) #, by="campaign_id")


first_board_demands <- key_dates %>%
    filter(demand_type=="board") %>%
    group_by(campaign_id) %>%
    summarize(first_board_date = min(demand_date))

first_demands <- key_dates %>%
    group_by(campaign_id) %>%
    summarize(first_board_date = min(demand_date))

first_demands_merged <- left_join(first_demands, first_board_demands)

event_tbl <- left_join(activism_events, first_demands_merged)

event_tbl %>%
    select(campaign_id, demand_type) %>%
    distinct %>%
    as.data.frame %>%
    mutate_(indicator = ~TRUE) %>%
    spread(demand_type, indicator, fill=FALSE) %>%
    cor_ind %>%
    print

event_tbl %>%
    select(campaign_id, demand_date, demand_type) %>%
    distinct %>%
    as.data.frame %>%
    mutate_(indicator = ~TRUE) %>%
    spread(demand_type, indicator, fill=FALSE) %>%
    cor_ind %>%
    print
