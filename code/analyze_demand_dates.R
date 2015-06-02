# library(tidyr)
library(dplyr)

pg <- src_postgres()

key_dates <- tbl(pg, sql("
    SELECT campaign_id, demand_date, UNNEST(demand_types) AS demand_type
    FROM activist_director.key_dates"))

activism_events <- tbl(pg, sql("
    SELECT campaign_id, synopsis_text, activist_demand,
        dissident_board_seats_sought
    FROM activist_director.activism_events"))

# Identify the different kinds of demands we've coded
key_dates %>% group_by(demand_type) %>%
    summarize(count = n()) %>%
    arrange(desc(count)) %>%
    collect()

# Identify cases with board but not board demand dates
key_dates %>%
    filter(demand_type=="board") %>%
    group_by(campaign_id) %>%
    summarize(first_board_date = min(demand_date)) %>%
    left_join(activism_events, .) %>%
    mutate(board_demand=!is.na(first_board_date)) %>%
    filter(is.na(first_board_date) & activist_demand) %>%
    collect() %>% as.data.frame -> problem_cases


