# The following code identifies cases where we'd expect to find
# board demand dates, but don't.
#
# There were many more cases where I was able to identify board demands using
# the synopsis text and simply add these to the "key_dates" Google Sheets doc:
#
# URL <- paste0("https://docs.google.com/spreadsheets/d/",
# "1s8-xvFxQZd6lMrxfVqbPTwUB_NQtvdxCO-s6QCIYvNk/edit")
# GIDs refer to sheet of this document

library(dplyr)

pg <- src_postgres()

key_dates <- tbl(pg, sql("
    SELECT campaign_id, demand_date,
        UNNEST(gids) AS gid,
        UNNEST(demand_types) AS demand_type
    FROM activist_director.key_dates"))

activism_events <- tbl(pg, sql("
    SELECT campaign_id, campaign_ids, cusip_9_digit, eff_announce_date,
        dissident_group, synopsis_text, activist_demand,
        dissident_board_seats_sought
    FROM activist_director.activism_events")) %>%
    filter(dissident_board_seats_sought >0)

# Identify the different kinds of demands we've coded
key_dates %>% group_by(demand_type) %>%
    summarize(count = n()) %>%
    arrange(desc(count)) %>%
    collect()

# Identify cases with board demands but no board demand dates
problem_cases <- key_dates %>%
    filter(demand_type=="board") %>%
    group_by(campaign_id) %>%
    summarize(first_board_date = min(demand_date)) %>%
    left_join(activism_events, .) %>%
    mutate(board_demand=!is.na(first_board_date)) %>%
    filter(is.na(first_board_date) & activist_demand) %>%
    inner_join(key_dates %>% select(campaign_id, gid)) %>%
    collect() # %>% as.data.frame

# Count problems by underlying Google Sheet ID (gid)
problem_cases %>% group_by(gid) %>% summarize(count = n())
