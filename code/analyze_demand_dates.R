# library(tidyr)
library(dplyr)

pg <- src_postgres()

key_dates <- tbl(pg, sql("
    SELECT campaign_id, demand_date, gids::text AS gid,
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

# Identify cases with board but not board demand dates
problem_cases <- key_dates %>%
    filter(demand_type=="board") %>%
    group_by(campaign_id) %>%
    summarize(first_board_date = min(demand_date)) %>%
    left_join(activism_events, .) %>%
    mutate(board_demand=!is.na(first_board_date)) %>%
    filter(is.na(first_board_date) & activist_demand) %>%
    inner_join(key_dates %>% select(campaign_id, gid)) %>%
    collect() %>% as.data.frame

problem_cases %>% group_by(gid) %>% summarize(count = n())
