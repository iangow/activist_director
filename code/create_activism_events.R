library(dplyr, warn.conflicts = FALSE)
library(DBI)
pg <- dbConnect(RPostgreSQL::PostgreSQL())

rs <-  dbGetQuery(pg, "SET work_mem='8GB'")
rs <- dbGetQuery(pg, "SET search_path TO activist_director")

activism_sample <- tbl(pg, "activism_sample")
activist_directors <- tbl(pg, "activist_directors")
prior_campaigns <- tbl(pg, "prior_campaigns")

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

prior_campaigns <-
    activism_sample %>%
    mutate(link_campaign_id = unnest(campaign_ids)) %>%
    inner_join(prior_campaigns, by = c("link_campaign_id"="campaign_id")) %>%
    distinct() %>%
    group_by(campaign_ids) %>%
    summarize(
        prev_campaigns = max(prev_campaigns, na.rm = TRUE),
        recent_campaigns = max(recent_campaigns, na.rm = TRUE),
        recent_three_years = max(recent_three_years, na.rm = TRUE),
        prior_dummy = any(prior_dummy, na.rm = TRUE),
        recent_dummy = any(recent_dummy, na.rm = TRUE),
        recent_three_dummy = any(recent_three_dummy, na.rm = TRUE)) %>%
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
    left_join(prior_campaigns, by = "campaign_ids") %>%
    mutate(hostile_resistance = poison_pill_post | proxy_fight_went_the_distance,
           high_stake = dissident_group_ownership_percent_at_announcement >= 10,
           big_inv = market_capitalization_at_time_of_campaign * dissident_group_ownership_percent_at_announcement/100 >= 100) %>%
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
	            activist_director & big_inv ~ 'big investment director',
                activist_director & !big_inv ~ 'small investment director',
	            TRUE ~ category_activist_director)) %>%
    mutate(affiliated_hostile = case_when(
               affiliated == 'affiliated' & hostile_resistance ~ 'affiliated_hostile',
               affiliated == 'unaffiliated' & hostile_resistance ~ 'unaffiliated_hostile',
               affiliated == 'affiliated' & !hostile_resistance ~ 'affiliated_nothostile',
               affiliated == 'unaffiliated' & !hostile_resistance ~ 'unaffiliated_nothostile',
               TRUE ~ category_activist_director),
           affiliated_two_plus = case_when(
               affiliated == 'affiliated' & num_activist_directors > 1 ~ 'affiliated_two_plus',
               affiliated == 'unaffiliated' & num_activist_directors > 1 ~ 'unaffiliated_two_plus',
               affiliated == 'affiliated' ~ 'affiliated_one',
               affiliated == 'unaffiliated' ~ 'unaffiliated_one',
               category_activist_director != 'activist_director' ~ category_activist_director),
           affiliated_high_stake = case_when(
               affiliated == 'affiliated' & high_stake ~ 'affiliated_high_stake',
               affiliated == 'unaffiliated' & high_stake ~ 'unaffiliated_high_stake',
               affiliated == 'affiliated' & !high_stake ~ 'affiliated_low_stake',
               affiliated == 'unaffiliated' & !high_stake ~ 'unaffiliated_low_stake',
               category_activist_director != 'activist_director' ~ category_activist_director),
           affiliated_big_inv = case_when(
               affiliated == 'affiliated' & big_inv ~ 'affiliated_big_inv',
               affiliated == 'unaffiliated' & big_inv ~ 'unaffiliated_big_inv',
               affiliated == 'affiliated' & !big_inv ~ 'affiliated_small_inv',
               affiliated == 'unaffiliated' & !big_inv ~ 'unaffiliated_small_inv',
               category_activist_director != 'activist_director' ~ category_activist_director),
           affiliated_prior = case_when(
               affiliated == 'affiliated' & prior_dummy ~ 'affiliated_high_prior',
               affiliated == 'unaffiliated' & prior_dummy ~ 'unaffiliated_high_prior',
               affiliated == 'affiliated' & !prior_dummy ~ 'affiliated_small_prior',
               affiliated == 'unaffiliated' & !prior_dummy ~ 'unaffiliated_small_prior',
               category_activist_director != 'activist_director' ~ category_activist_director),
           affiliated_recent = case_when(
               affiliated == 'affiliated' & recent_dummy ~ 'affiliated_high_recent',
               affiliated == 'unaffiliated' & recent_dummy ~ 'unaffiliated_high_recent',
               affiliated == 'affiliated' & !recent_dummy ~ 'affiliated_small_recent',
               affiliated == 'unaffiliated' & !recent_dummy ~ 'unaffiliated_small_recent',
               category_activist_director != 'activist_director' ~ category_activist_director),
           affiliated_recent_three = case_when(
               affiliated == 'affiliated' & recent_three_dummy ~ 'affiliated_high_recent_three',
               affiliated == 'unaffiliated' & recent_three_dummy ~ 'unaffiliated_high_recent_three',
               affiliated == 'affiliated' & !recent_three_dummy ~ 'affiliated_small_recent_three',
               affiliated == 'unaffiliated' & !recent_three_dummy ~ 'unaffiliated_small_recent_three',
               category_activist_director != 'activist_director' ~ category_activist_director)) %>%
    compute(name = "activism_events", temporary = FALSE)

sql <- paste0("
    ALTER TABLE activism_events OWNER TO activism;

    COMMENT ON TABLE activism_events IS
        'CREATED USING create_activism_events.R ON ",
              format(Sys.time(), "%Y-%m-%d %X %Z"), "';")

rs <- dbExecute(pg, sql)

rs <- dbDisconnect(pg)
