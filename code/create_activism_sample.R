library(DBI)
library(dplyr, warn.conflicts = FALSE)

pg <- dbConnect(RPostgres::Postgres(), bigint = "integer")

rs <- dbExecute(pg, "SET search_path TO activist_director, public")

key_dates <- tbl(pg, "key_dates")

permnos <- tbl(pg, "permnos")
activist_ciks <- tbl(pg, sql("SELECT * FROM factset.activist_ciks"))
sharkwatch <- tbl(pg, sql("SELECT * FROM factset.sharkwatch"))
dissidents <- tbl(pg, sql("SELECT * FROM factset.dissidents"))
stocknames <- tbl(pg, sql("SELECT * FROM crsp.stocknames"))
msedelist <- tbl(pg, sql("SELECT * FROM crsp.msedelist"))

dissident_data <-
    dissidents %>%
    group_by(campaign_id) %>%
    summarize(hedge_fund = bool_or(holder_type %in% c("Hedge Fund Company", "Investment Adviser")),
              sharkwatch50 = bool_or(sharkwatch50 == "Yes"),
              holder_types = sql("array_agg(holder_type ORDER BY holder_type)"),
              dissidents = sql("array_agg(dissident ORDER BY dissident)"))

permnos_all <-
    permnos %>%
    mutate(ncusip = substr(ncusip, 1L, 8L)) %>%
    union_all(
        stocknames %>%
            select(permno, ncusip) %>%
            distinct()) %>%
    left_join(stocknames %>% distinct(permno, permco), by="permno") %>%
    compute()

sharkwatch_raw <-
    sharkwatch %>%
    inner_join(dissident_data, by = "campaign_id") %>%
    mutate(eff_announce_date = least(announce_date, date_original_13d_filed),
           classified_board = classified_board=='Yes',
           s13d_filer = s13d_filer=='Yes',
           first_date = least(proxy_fight_announce_date, announce_date, date_original_13d_filed),
           last_date = greatest(meeting_date, end_date),
           proxy_fight = proxy_fight=='Yes',
           proxy_fight_went_definitive = proxy_fight_went_definitive=='Yes',
           proxy_fight_went_the_distance = proxy_fight_went_the_distance=='Yes',
           poison_pill_pre = poison_pill_in_force_prior_to_announcement=='Yes',
           poison_pill_post = poison_pill_adopted_in_response_to_campaign=='Yes',
           campaign_resulted_in_board_seats_for_activist  = campaign_resulted_in_board_seats_for_activist=='Yes',
           board_related = coalesce(activism_type=='Proxy Fight' |
                                        dissident_board_seats_sought > 0 |
                                        dissident_board_seats_won > 0 |
                                        primary_campaign_type %in%
                                            c('Withhold Vote for Director(s)',
                                              'Board Representation',
                                              'Board Control',
                                              'Remove Director(s), No Dissident Nominee to Fill Vacancy'),
                                    FALSE),
           activist_demand_old = primary_campaign_type %in% c('Board Representation', 'Board Control') |
               dissident_board_seats_sought > 0 |
               dissident_board_seats_won > 0 |
               campaign_resulted_in_board_seats_for_activist=='Yes' |
               !is.na(dissident_board_seats_wongranted_date),
           settlement_agreement_special_exhibit_included = settlement_agreement_special_exhibit_included=='Yes',
           standstill_agreement_special_exhibit_included = standstill_agreement_special_exhibit_included=='Yes',
           concession_made = governance_demands_followthroughsuccess %~% 'Yes'|
               value_demands_followthroughsuccess %~% 'Yes' |
               settlement_agreement_special_exhibit_included=='Yes' |
               standstill_agreement_special_exhibit_included=='Yes') %>%
    mutate(settled = settlement_agreement_special_exhibit_included |
               standstill_agreement_special_exhibit_included) %>%
    filter(country=='United States',
           state_of_incorporation != 'Non-U.S.',
           factset_industry != 'Investment Trusts/Mutual Funds',
           s13d_filer=='Yes' | proxy_fight=='Yes' | hedge_fund,
           campaign_status=='Closed',
           between(eff_announce_date, '2004-01-01', '2016-12-31'),
           activism_type != '13D Filer - No Publicly Disclosed Activism') %>%
    select(campaign_id, cusip_9_digit, announce_date, synopsis_text,
           dissidents,
           hedge_fund,
           eff_announce_date, dissident_group,
           activism_type, primary_campaign_type, secondary_campaign_type,
           dissident_board_seats_sought,
           dissident_board_seats_won,
           campaign_resulted_in_board_seats_for_activist,
           classified_board,
           campaign_status, stock_exchange_primary, primary_sic_code,
           s13d_filer, sharkwatch50,
           company_name, country, dissident_group_ownership_percent,
           dissident_group_ownership_percent_at_announcement,
           date_original_13d_filed, proxy_fight_announce_date,
           meeting_date, dissident_board_seats_wongranted_date, end_date, state_of_headquarters,
           market_capitalization_at_time_of_campaign, factset_industry,
           first_date, last_date,
           proxy_fight, proxy_fight_went_definitive, proxy_fight_went_the_distance,
           poison_pill_pre, poison_pill_post,
           governance_demands_followthroughsuccess,
           value_demands_followthroughsuccess,
           outcome, board_related,
        activist_demand_old,
        settlement_agreement_special_exhibit_included, standstill_agreement_special_exhibit_included,
        concession_made, settled) %>%
    compute()

settlement_agreement <-
    sharkwatch %>%
    mutate(campaign_id = as.integer(campaign_id)) %>%
    mutate(dates = regexp_matches(settlement_agreement_special_exhibit_source,
                          '\\d{1,2}-\\d{1,2}-\\d{4}', 'g')) %>%
    mutate(dates = unnest(dates)) %>%
    mutate(settle_date  = to_date(dates, 'MM-DD-YYYY')) %>%
    select(campaign_id, settle_date)

standstill_agreement <-
    sharkwatch %>%
    mutate(campaign_id = as.integer(campaign_id)) %>%
    mutate(dates = regexp_matches(standstill_agreement_special_exhibit_source,
                                  '\\d{1,2}-\\d{1,2}-\\d{4}', 'g')) %>%
    mutate(dates = unnest(dates)) %>%
    mutate(standstill_date  = to_date(dates, 'MM-DD-YYYY')) %>%
    select(campaign_id, standstill_date)

any_settle_date <-
    standstill_agreement %>%
    full_join(settlement_agreement, by = "campaign_id") %>%
    mutate(any_settle_date = coalesce(settle_date, standstill_date)) %>%
    distinct() %>%
    compute()

sharkwatch_all <-
    sharkwatch_raw %>%
    mutate(ncusip = substr(cusip_9_digit, 1L, 8L)) %>%
    left_join(permnos_all, by = "ncusip") %>%
    left_join(any_settle_date)

sharkwatch_all %>%
    distinct() %>%
    count()

sharkwatch_agg <-
    sharkwatch_all %>%
    group_by(permno, eff_announce_date, dissident_group, dissidents) %>%
    summarize(campaign_ids = array_agg(campaign_id),
              synopsis_text = string_agg(synopsis_text, ' '),
              activist_demand_old = bool_or(activist_demand_old),
              board_related = bool_or(board_related),
              proxy_fight = bool_or(proxy_fight),
              proxy_fight_went_definitive = bool_or(proxy_fight_went_definitive),
              proxy_fight_went_the_distance = bool_or(proxy_fight_went_the_distance),
              poison_pill_pre = bool_or(poison_pill_pre),
              poison_pill_post = bool_or(poison_pill_post),
              campaign_resulted_in_board_seats_for_activist = bool_or(campaign_resulted_in_board_seats_for_activist),
              settled = bool_or(settled),
              concession_made = bool_or(concession_made),
              governance_demands = sql("array_agg(DISTINCT governance_demands_followthroughsuccess)"),
              value_demands = sql("array_agg(DISTINCT value_demands_followthroughsuccess)"),
              settlement_agreement_special_exhibit_included = bool_or(settlement_agreement_special_exhibit_included),
              standstill_agreement_special_exhibit_included = bool_or(standstill_agreement_special_exhibit_included),
              settle_date = min(settle_date, na.rm = TRUE),
              standstill_date = min(standstill_date, na.rm = TRUE),
              any_settle_date = min(any_settle_date, na.rm = TRUE),
              sharkwatch50 = bool_or(sharkwatch50),
              s13d_filer = bool_or(s13d_filer),
              first_date = min(first_date, na.rm = TRUE),
              last_date = max(last_date, na.rm = TRUE),
              dissident_board_seats_wongranted_date = min(dissident_board_seats_wongranted_date, na.rm = TRUE),
              dissident_group_ownership_percent_at_announcement = max(dissident_group_ownership_percent_at_announcement,
                                                                      na.rm = TRUE),
              dissident_group_ownership_percent = max(dissident_group_ownership_percent, na.rm = TRUE),
              classified_board = bool_or(classified_board),
              end_date = max(end_date, na.rm = TRUE),
              meeting_dates = sql("array_agg(DISTINCT meeting_date)"),
              date_original_13d_filed = min(date_original_13d_filed, na.rm = TRUE),
              proxy_fight_announce_date = min(proxy_fight_announce_date, na.rm = TRUE),
              activism_types = sql("array_agg(DISTINCT activism_type)"),
              dissident_board_seats_won = max(dissident_board_seats_won, na.rm = TRUE),
              dissident_board_seats_sought = max(dissident_board_seats_sought, na.rm = TRUE),
              market_capitalization_at_time_of_campaign = max(market_capitalization_at_time_of_campaign, na.rm = TRUE),
              campaign_status = sql("array_agg(DISTINCT campaign_status)"),
              campaign_types= sql("array_remove(array_cat(array_agg(primary_campaign_type),
                                     array_agg(secondary_campaign_type)), NULL)"),
              company_names = sql("array_agg(DISTINCT company_name)"),
              countries = sql("array_agg(DISTINCT country)"),
              states_of_headquarters = sql("array_agg(DISTINCT state_of_headquarters)"),
              stock_exchanges = sql("array_agg(DISTINCT stock_exchange_primary)"),
              factset_industries = sql("array_agg(DISTINCT factset_industry)") ,
              primary_sic_codes = sql("array_agg(DISTINCT primary_sic_code)"),
              activism = TRUE) %>%
    ungroup() %>%
    compute()

delist <-
    msedelist %>%
    filter(dlstcd > 100) %>%
    distinct(permno, dlstcd, dlstdt)

first_board_demand_date <-
    sharkwatch_agg %>%
    mutate(campaign_id = unnest(campaign_ids)) %>%
    inner_join(key_dates, by = "campaign_id") %>%
    mutate(demand_type = unnest(demand_types)) %>%
    filter('board' == demand_type) %>%
    group_by(campaign_ids) %>%
    summarize(first_board_demand_date = min(demand_date, na.rm = TRUE))

delisted_status <-
    sharkwatch_agg %>%
    filter(!is.na(permno)) %>%
    left_join(delist) %>%
    mutate(status = case_when(
        between(dlstcd, 200, 399) ~ 'merged',
        between(dlstcd, 400, 599) ~ 'dropped',
        TRUE ~ 'active')) %>%
    select(campaign_ids, eff_announce_date, dlstdt, status) %>%
    mutate(delisted_p1 = if_else(dlstdt <= eff_announce_date + sql("interval '1 year'"), status, "active"),
           delisted_p2 = if_else(dlstdt <= eff_announce_date + sql("interval '2 years'"), status, "active"),
           delisted_p3 = if_else(dlstdt <= eff_announce_date + sql("interval '3 years'"), status, "active")) %>%
    select(-status, -eff_announce_date) %>%
    compute()

dbExecute(pg, "DROP TABLE IF EXISTS activism_sample")

activism_sample <-
    sharkwatch_agg %>%
    filter(!is.na(permno)) %>%
    left_join(first_board_demand_date, by = "campaign_ids") %>%
    left_join(delisted_status, by = "campaign_ids") %>%
    filter(is.na(dlstdt) | first_date <= dlstdt) %>%
    mutate(inv_value = market_capitalization_at_time_of_campaign *
               dissident_group_ownership_percent_at_announcement/100.0,
           campaign_id = array_min(campaign_ids)) %>%
    compute(name = "activism_sample", temporary = FALSE)

rs <- dbExecute(pg, "ALTER TABLE activism_sample OWNER TO activism")

sql <- paste0("
    COMMENT ON TABLE activism_sample IS
        'CREATED USING create_activism_sample.R ON ",
              format(Sys.time(), "%Y-%m-%d %X %Z"), "';")

rs <- dbExecute(pg, sql)

rs <- dbDisconnect(pg)
