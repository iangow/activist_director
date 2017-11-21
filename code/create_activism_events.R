library(dplyr, warn.conflicts = FALSE)
library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

dbGetQuery(pg, "SET work_mem='8GB'")

dbGetQuery(pg, "SET search_path='activist_director'")
dbGetQuery(pg, "DROP TABLE IF EXISTS activism_events")

activism_sample <- tbl(pg, sql("SELECT * FROM activism_sample"))

activist_directors <- tbl(pg, sql("SELECT * FROM activist_directors"))

activist_director <-
    activist_directors %>%
    group_by(campaign_id) %>%
    summarize(
        first_appointment_date= min(appointment_date),
        num_activist_directors = n(),
        num_affiliate_directors = sum(as.integer(!independent)),
        num_unaffiliate_directors = sum(as.integer(independent)))

matched <-
    activism_sample %>%
    left_join(activist_director,
              by = "campaign_id") %>%
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
	        TRUE ~ '_none')) %>%
    mutate(affiliated = case_when(
            activist_director & num_affiliate_directors > 0 ~ 'affiliated',
            activist_director & num_affiliate_directors == 0 ~ 'non_affiliated',
	        TRUE ~ category),
           two_plus = case_when(
            num_activist_directors > 1 ~ 'two_plus_directors',
	        activist_director ~ 'one_director',
            TRUE ~ category),
           early = case_when(
            first_appointment_date - eff_announce_date <= 180 ~ 'early',
            first_appointment_date - eff_announce_date > 180 ~ 'late',
            TRUE ~ category),
           big_investment = case_when(
	        activist_director &
                market_capitalization_at_time_of_campaign *
                dissident_group_ownership_percent_at_announcement/100
	                > 100 ~ 'big investment director',
            activist_director ~ 'small investment director',
	        TRUE ~ category)) %>%
    compute(name = "activism_events", temporary = FALSE)

sql <- paste0("

    ALTER TABLE activism_events OWNER TO activism;

    COMMENT ON TABLE activism_events IS
        'CREATED USING create_activism_events.R ON ", Sys.time() , "';")

rs <- dbGetQuery(pg, sql)

dbDisconnect(pg)
