library(dplyr, warn.conflicts = FALSE)
library(DBI)
pg <- dbConnect(RPostgreSQL::PostgreSQL())

rs <-  dbGetQuery(pg, "SET work_mem='8GB'")
rs <- dbGetQuery(pg, "SET search_path TO activist_director")

activism_sample <- tbl(pg, "activism_sample")
activist_directors <- tbl(pg, "activist_directors")

activist_director <-
    activism_sample %>%
    mutate(link_campaign_id = unnest(campaign_ids)) %>%
    inner_join(activist_directors, by = c("link_campaign_id"="campaign_id")) %>%
    distinct() %>%
    group_by(campaign_ids) %>%
    summarize(
        first_appointment_date = min(appointment_date, na.rm = TRUE),
        num_activist_directors = n(),
        num_affiliate_directors = sum(as.integer(!independent), na.rm = TRUE),
        num_unaffiliate_directors = sum(as.integer(independent), na.rm = TRUE)) %>%
    ungroup() %>%
    compute()

rs <- dbGetQuery(pg, "DROP TABLE IF EXISTS activism_events")
matched <-
    activism_sample %>%
    # Fixing campaign_id==1027721875 to board_related (sharkwatch error)
    mutate(dissident_board_seats_won = ifelse(campaign_id==1027721875, 1, dissident_board_seats_won),
           dissident_board_seats_wongranted_date = ifelse(campaign_id==1027721875, '2009-03-31', dissident_board_seats_wongranted_date),
           board_related = ifelse(campaign_id==1027721875, TRUE, board_related)) %>%
    left_join(activist_director, by = "campaign_ids") %>%
    mutate(activist_director = !is.na(dissident_board_seats_wongranted_date) |
               dissident_board_seats_won > 0 |
               campaign_resulted_in_board_seats_for_activist) %>%
    mutate(activist_director = coalesce(activist_director, FALSE)) %>%
    mutate(elected = proxy_fight_went_the_distance=='Yes' & activist_director) %>%
    mutate(activist_demand = activist_demand_old |
            !is.na(first_board_demand_date)) %>%
    mutate(category = case_when(
            activist_director ~ 'activist_director',
            activist_demand ~ 'activist_demand',
            activism ~ 'activism',
	        TRUE ~ '_none'),
           category_activist_director = case_when(
               activist_director ~ 'activist_director',
               activist_demand ~ 'activism',
               activism ~ 'activism',
               TRUE ~ '_none')) %>%
    mutate(affiliated = case_when(
                activist_director & num_affiliate_directors > 0 ~ 'affiliated',
                activist_director ~ 'unaffiliated',
	            TRUE ~ category_activist_director),
           two_plus = case_when(
                num_activist_directors > 1 ~ 'two_plus_directors',
	            activist_director ~ 'one_director',
                TRUE ~ category_activist_director),
           early = case_when(
                first_appointment_date - eff_announce_date <= 180 ~ 'early',
                first_appointment_date - eff_announce_date > 180 ~ 'late',
                TRUE ~ category_activist_director),
           big_investment = case_when(
	            activist_director &
                market_capitalization_at_time_of_campaign *
                    dissident_group_ownership_percent_at_announcement/100
	                > 100 ~ 'big investment director',
                activist_director ~ 'small investment director',
	            TRUE ~ category_activist_director),
           hostile_resistance = poison_pill_post | proxy_fight_went_the_distance,
           high_stake = dissident_group_ownership_percent_at_announcement >= 10) %>%
    compute(name = "activism_events", temporary = FALSE)

sql <- paste0("
    ALTER TABLE activism_events OWNER TO activism;

    COMMENT ON TABLE activism_events IS
        'CREATED USING create_activism_events.R ON ",
              format(Sys.time(), "%Y-%m-%d %X %Z"), "';")

rs <- dbExecute(pg, sql)

rs <- dbDisconnect(pg)
