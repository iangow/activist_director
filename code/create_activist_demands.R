# Sys.setenv(PGHOST="iangow.me", PGDATABASE="crsp")
library(dplyr, warn.conflicts = FALSE)
library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

rs <- dbExecute(pg, "SET search_path TO activist_director, public")

demands_data <- dbGetQuery(pg, "WITH demand_outcome AS (
    SELECT DISTINCT campaign_id,
    CASE WHEN value_demands_followthroughsuccess ilike '%Breakup Company, Divest Assets/Divisions(Yes)%' THEN TRUE
    WHEN value_demands_followthroughsuccess ilike '%Breakup Company, Divest Assets/Divisions(No)%' THEN TRUE
    WHEN value_demands_followthroughsuccess IS NOT NULL OR governance_demands_followthroughsuccess IS NOT NULL THEN FALSE
    END AS divestiture_demand,
    CASE WHEN value_demands_followthroughsuccess ilike '%Seek Sale/Merger/Liquidation(Yes)%' THEN TRUE
    WHEN value_demands_followthroughsuccess ilike '%Seek Sale/Merger/Liquidation(No)%' THEN TRUE
    WHEN value_demands_followthroughsuccess IS NOT NULL OR governance_demands_followthroughsuccess IS NOT NULL THEN FALSE
    END AS merger_demand,
    CASE WHEN value_demands_followthroughsuccess ilike '%Review Strategic Alternatives(Yes)%' THEN TRUE
    WHEN value_demands_followthroughsuccess ilike '%Review Strategic Alternatives(No)%' THEN TRUE
    WHEN value_demands_followthroughsuccess IS NOT NULL OR governance_demands_followthroughsuccess IS NOT NULL THEN FALSE
    END AS strategy_demand,
    CASE WHEN value_demands_followthroughsuccess ilike '%Return Cash via Dividends/Buybacks(Yes)%' THEN TRUE
    WHEN value_demands_followthroughsuccess ilike '%Return Cash via Dividends/Buybacks(No)%' THEN TRUE
    WHEN value_demands_followthroughsuccess IS NOT NULL OR governance_demands_followthroughsuccess IS NOT NULL THEN FALSE
    END AS payout_demand,
    CASE WHEN value_demands_followthroughsuccess ilike '%Block Merger/Agitate for Higher Price (Shareholder of Target)(Yes)%' THEN TRUE
    WHEN value_demands_followthroughsuccess ilike '%Block Merger/Agitate for Higher Price (Shareholder of Target)(No)%' THEN TRUE
    WHEN primary_campaign_type ilike '%Vote/Activism Against a Merger%' THEN TRUE
    WHEN secondary_campaign_type ilike '%Vote/Activism Against a Merger%' THEN TRUE
    WHEN value_demands_followthroughsuccess IS NOT NULL OR governance_demands_followthroughsuccess IS NOT NULL OR primary_campaign_type IS NOT NULL OR secondary_campaign_type IS NOT NULL THEN FALSE
    END AS block_merger_demand,
    CASE WHEN value_demands_followthroughsuccess ilike '%Potential Acquisition (Friendly and Unfriendly)(Yes)%' THEN TRUE
    WHEN value_demands_followthroughsuccess ilike '%Potential Acquisition (Friendly and Unfriendly)(No)%' THEN TRUE
    WHEN primary_campaign_type ilike '%Hostile/Unsolicited Acquisition%' THEN TRUE
    WHEN secondary_campaign_type ilike '%Hostile/Unsolicited Acquisition%' THEN TRUE
    WHEN value_demands_followthroughsuccess IS NOT NULL OR governance_demands_followthroughsuccess IS NOT NULL OR primary_campaign_type IS NOT NULL OR secondary_campaign_type IS NOT NULL THEN FALSE
    END AS acquisition_demand,
    CASE WHEN value_demands_followthroughsuccess ilike '%Separate Real Estate/Create REIT(Yes)%' THEN TRUE
    WHEN value_demands_followthroughsuccess ilike '%Separate Real Estate/Create REIT(No)%' THEN TRUE
    WHEN value_demands_followthroughsuccess IS NOT NULL OR governance_demands_followthroughsuccess IS NOT NULL THEN FALSE
    END AS reits_demand,
    CASE WHEN value_demands_followthroughsuccess ilike '%Other Capital Structure Related, Increase Leverage, etc.(Yes)%' THEN TRUE
    WHEN value_demands_followthroughsuccess ilike '%Other Capital Structure Related, Increase Leverage, etc.(No)%' THEN TRUE
    WHEN value_demands_followthroughsuccess IS NOT NULL OR governance_demands_followthroughsuccess IS NOT NULL THEN FALSE
    END AS leverage_demand,
    CASE WHEN value_demands_followthroughsuccess ilike 'Block Acquisition/Agitate for Lower Price (Shareholder of Acquirer)(Yes)%' THEN TRUE
    WHEN value_demands_followthroughsuccess ilike '%Block Acquisition/Agitate for Lower Price (Shareholder of Acquirer)(No)%' THEN TRUE
    WHEN value_demands_followthroughsuccess IS NOT NULL OR governance_demands_followthroughsuccess IS NOT NULL THEN FALSE
    END AS block_acquisition_demand,

    CASE WHEN governance_demands_followthroughsuccess ilike '%Add Independent Directors(Yes)%' THEN TRUE
    WHEN governance_demands_followthroughsuccess ilike '%Add Independent Directors(No)%' THEN TRUE
    WHEN value_demands_followthroughsuccess IS NOT NULL OR governance_demands_followthroughsuccess IS NOT NULL THEN FALSE
    END AS add_indep_demand,
    CASE WHEN governance_demands_followthroughsuccess ilike '%Other Governance Enhancements(Yes)%' THEN TRUE
    WHEN governance_demands_followthroughsuccess ilike '%Other Governance Enhancements(No)%' THEN TRUE
    WHEN value_demands_followthroughsuccess IS NOT NULL OR governance_demands_followthroughsuccess IS NOT NULL THEN FALSE
    END AS other_gov_demand,
    CASE WHEN governance_demands_followthroughsuccess ilike '%Compensation Related Enhancements(Yes)%' THEN TRUE
    WHEN governance_demands_followthroughsuccess ilike '%Compensation Related Enhancements(No)%' THEN TRUE
    WHEN value_demands_followthroughsuccess IS NOT NULL OR governance_demands_followthroughsuccess IS NOT NULL THEN FALSE
    END AS compensation_demand,
    CASE WHEN governance_demands_followthroughsuccess ilike '%Remove Officer(s)(Yes)%' THEN TRUE
    WHEN governance_demands_followthroughsuccess ilike '%Remove Officer(s)(No)%' THEN TRUE
    WHEN primary_campaign_type ilike '%Remove Officer(s)%' THEN TRUE
    WHEN secondary_campaign_type ilike '%Remove Officer(s)%' THEN TRUE
    WHEN value_demands_followthroughsuccess IS NOT NULL OR governance_demands_followthroughsuccess IS NOT NULL OR primary_campaign_type IS NOT NULL OR secondary_campaign_type IS NOT NULL THEN FALSE
    END AS remove_officer_demand,
    CASE WHEN governance_demands_followthroughsuccess ilike '%Remove Director(s)(Yes)%' THEN TRUE
    WHEN governance_demands_followthroughsuccess ilike '%Remove Director(s)(No)%' THEN TRUE
    WHEN primary_campaign_type ilike '%Remove Director(s), No Dissident Nominee to Fill Vacancy%' THEN TRUE
    WHEN secondary_campaign_type ilike '%Remove Director(s), No Dissident Nominee to Fill Vacancy%' THEN TRUE
    WHEN value_demands_followthroughsuccess IS NOT NULL OR governance_demands_followthroughsuccess IS NOT NULL OR primary_campaign_type IS NOT NULL OR secondary_campaign_type IS NOT NULL THEN FALSE
    END AS remove_director_demand,
    CASE WHEN governance_demands_followthroughsuccess ilike '%Remove Takeover Defenses(Yes)%' THEN TRUE
    WHEN governance_demands_followthroughsuccess ilike '%Remove Takeover Defenses(No)%' THEN TRUE
    WHEN value_demands_followthroughsuccess IS NOT NULL OR governance_demands_followthroughsuccess IS NOT NULL THEN FALSE
    END AS remove_defense_demand,
    CASE WHEN governance_demands_followthroughsuccess ilike '%Board Seats (activist group)(Yes)%' THEN TRUE
    WHEN governance_demands_followthroughsuccess ilike '%Board Seats (activist group)(No)%' THEN TRUE
    WHEN primary_campaign_type ilike '%Board Representation%' THEN TRUE
    WHEN secondary_campaign_type ilike '%Board Representation%' THEN TRUE
    WHEN primary_campaign_type ilike '%Board Control%' THEN TRUE
    WHEN secondary_campaign_type ilike '%Board Control%' THEN TRUE
    WHEN dissident_board_seats_sought > 0 THEN TRUE
    WHEN dissident_board_seats_won > 0 THEN TRUE
    WHEN dissident_tactic_nominate_slate_of_directors = 'Yes' THEN TRUE
    WHEN campaign_resulted_in_board_seats_for_activist = 'Yes' THEN TRUE
    WHEN dissident_board_seats_wongranted_date IS NOT NULL THEN TRUE
    WHEN value_demands_followthroughsuccess IS NOT NULL OR governance_demands_followthroughsuccess IS NOT NULL
    OR primary_campaign_type IS NOT NULL OR secondary_campaign_type IS NOT NULL
    OR dissident_board_seats_sought IS NOT NULL OR dissident_board_seats_won IS NOT NULL
    OR dissident_tactic_nominate_slate_of_directors IS NOT NULL OR campaign_resulted_in_board_seats_for_activist IS NOT NULL
    OR dissident_board_seats_wongranted_date IS NOT NULL THEN FALSE
    END AS board_seat_demand,
    CASE WHEN governance_demands_followthroughsuccess ilike '%Social/Environmental/Political Issues(Yes)%' THEN TRUE
    WHEN governance_demands_followthroughsuccess ilike '%Social/Environmental/Political Issues(No)%' THEN TRUE
    WHEN value_demands_followthroughsuccess IS NOT NULL OR governance_demands_followthroughsuccess IS NOT NULL THEN FALSE
    END AS esg_demand,

    CASE WHEN value_demands_followthroughsuccess ilike '%Breakup Company, Divest Assets/Divisions(Yes)%' THEN TRUE
    WHEN value_demands_followthroughsuccess ilike '%Breakup Company, Divest Assets/Divisions(No)%' THEN FALSE
    END AS divestiture_outcome,
    CASE WHEN value_demands_followthroughsuccess ilike '%Seek Sale/Merger/Liquidation(Yes)%' THEN TRUE
    WHEN value_demands_followthroughsuccess ilike '%Seek Sale/Merger/Liquidation(No)%' THEN FALSE
    END AS merger_outcome,
    CASE WHEN value_demands_followthroughsuccess ilike '%Review Strategic Alternatives(Yes)%' THEN TRUE
    WHEN value_demands_followthroughsuccess ilike '%Review Strategic Alternatives(No)%' THEN FALSE
    END AS strategy_outcome,
    CASE WHEN value_demands_followthroughsuccess ilike '%Return Cash via Dividends/Buybacks(Yes)%' THEN TRUE
    WHEN value_demands_followthroughsuccess ilike '%Return Cash via Dividends/Buybacks(No)%' THEN FALSE
    END AS payout_outcome,
    CASE WHEN value_demands_followthroughsuccess ilike '%Block Merger/Agitate for Higher Price (Shareholder of Target)(Yes)%' THEN TRUE
    WHEN value_demands_followthroughsuccess ilike '%Block Merger/Agitate for Higher Price (Shareholder of Target)(No)%' THEN FALSE
    END AS block_merger_outcome,
    CASE WHEN value_demands_followthroughsuccess ilike '%Potential Acquisition (Friendly and Unfriendly)(Yes)%' THEN TRUE
    WHEN value_demands_followthroughsuccess ilike '%Potential Acquisition (Friendly and Unfriendly)(No)%' THEN FALSE
    END AS acquisition_outcome,
    CASE WHEN value_demands_followthroughsuccess ilike '%Separate Real Estate/Create REIT(Yes)%' THEN TRUE
    WHEN value_demands_followthroughsuccess ilike '%Separate Real Estate/Create REIT(No)%' THEN FALSE
    END AS reits_outcome,
    CASE WHEN value_demands_followthroughsuccess ilike '%Other Capital Structure Related, Increase Leverage, etc.(Yes)%' THEN TRUE
    WHEN value_demands_followthroughsuccess ilike '%Other Capital Structure Related, Increase Leverage, etc.(No)%' THEN FALSE
    END AS leverage_outcome,
    CASE WHEN value_demands_followthroughsuccess ilike 'Block Acquisition/Agitate for Lower Price (Shareholder of Acquirer)(Yes)%' THEN TRUE
    WHEN value_demands_followthroughsuccess ilike '%Block Acquisition/Agitate for Lower Price (Shareholder of Acquirer)(No)%' THEN FALSE
    END AS block_acquisition_outcome,
    CASE WHEN governance_demands_followthroughsuccess ilike '%Add Independent Directors(Yes)%' THEN TRUE
    WHEN governance_demands_followthroughsuccess ilike '%Add Independent Directors(No)%' THEN FALSE
    END AS add_indep_outcome,
    CASE WHEN governance_demands_followthroughsuccess ilike '%Other Governance Enhancements(Yes)%' THEN TRUE
    WHEN governance_demands_followthroughsuccess ilike '%Other Governance Enhancements(No)%' THEN FALSE
    END AS other_gov_outcome,
    CASE WHEN governance_demands_followthroughsuccess ilike '%Compensation Related Enhancements(Yes)%' THEN TRUE
    WHEN governance_demands_followthroughsuccess ilike '%Compensation Related Enhancements(No)%' THEN FALSE
    END AS compensation_outcome,
    CASE WHEN governance_demands_followthroughsuccess ilike '%Remove Officer(s)(Yes)%' THEN TRUE
    WHEN governance_demands_followthroughsuccess ilike '%Remove Officer(s)(No)%' THEN FALSE
    END AS remove_officer_outcome,
    CASE WHEN governance_demands_followthroughsuccess ilike '%Remove Director(s)(Yes)%' THEN TRUE
    WHEN governance_demands_followthroughsuccess ilike '%Remove Director(s)(No)%' THEN FALSE
    END AS remove_director_outcome,
    CASE WHEN governance_demands_followthroughsuccess ilike '%Remove Takeover Defenses(Yes)%' THEN TRUE
    WHEN governance_demands_followthroughsuccess ilike '%Remove Takeover Defenses(No)%' THEN FALSE
    END AS remove_defense_outcome,
    CASE WHEN governance_demands_followthroughsuccess ilike '%Board Seats (activist group)(Yes)%' THEN TRUE
    WHEN dissident_board_seats_won > 0 THEN TRUE
    WHEN dissident_board_seats_wongranted_date IS NOT NULL THEN TRUE
    WHEN campaign_resulted_in_board_seats_for_activist = 'Yes' THEN TRUE
    WHEN governance_demands_followthroughsuccess ilike '%Board Seats (activist group)(No)%' THEN FALSE
    END AS board_seat_outcome,
    CASE WHEN governance_demands_followthroughsuccess ilike '%Social/Environmental/Political Issues(Yes)%' THEN TRUE
    WHEN governance_demands_followthroughsuccess ilike '%Social/Environmental/Political Issues(No)%' THEN FALSE
    END AS esg_outcome
    FROM factset.sharkwatch
    WHERE campaign_id IS NOT NULL
    AND (governance_demands_followthroughsuccess != '' OR value_demands_followthroughsuccess != '')
    ORDER BY campaign_id),

match1 AS (
    SELECT DISTINCT campaign_ids, b.*
        FROM activist_director.activism_events AS a
    INNER JOIN demand_outcome AS b
    ON b.campaign_id = ANY(a.campaign_ids)
    ORDER BY campaign_ids),

match2 AS (
    SELECT DISTINCT campaign_ids,
    --activism demand
    bool_or(strategy_demand) AS strategy_demand,
    bool_or(merger_demand) AS merger_demand,
    bool_or(block_merger_demand) AS block_merger_demand,
    bool_or(acquisition_demand) AS acquisition_demand,
    bool_or(block_acquisition_demand) AS block_acquisition_demand,
    bool_or(divestiture_demand) AS divestiture_demand,
    bool_or(payout_demand) AS payout_demand,
    bool_or(leverage_demand) AS leverage_demand,
    bool_or(reits_demand) AS reits_demand,

    bool_or(board_seat_demand) AS board_seat_demand,
    bool_or(remove_director_demand) AS remove_director_demand,
    bool_or(add_indep_demand) AS add_indep_demand,
    bool_or(remove_officer_demand) AS remove_officer_demand,
    bool_or(remove_defense_demand) AS remove_defense_demand,
    bool_or(compensation_demand) AS compensation_demand,
    bool_or(other_gov_demand) AS other_gov_demand,
    bool_or(esg_demand) AS esg_demand,
    --activism outcome
    bool_or(strategy_outcome) AS strategy_outcome,
    bool_or(merger_outcome) AS merger_outcome,
    bool_or(block_merger_outcome) AS block_merger_outcome,
    bool_or(acquisition_outcome) AS acquisition_outcome,
    bool_or(block_acquisition_outcome) AS block_acquisition_outcome,
    bool_or(divestiture_outcome) AS divestiture_outcome,
    bool_or(payout_outcome) AS payout_outcome,
    bool_or(leverage_outcome) AS leverage_outcome,
    bool_or(reits_outcome) AS reits_outcome,

    bool_or(board_seat_outcome) AS board_seat_outcome,
    bool_or(remove_director_outcome) AS remove_director_outcome,
    bool_or(add_indep_outcome) AS add_indep_outcome,
    bool_or(remove_officer_outcome) AS remove_officer_outcome,
    bool_or(remove_defense_outcome) AS remove_defense_outcome,
    bool_or(compensation_outcome) AS compensation_outcome,
    bool_or(other_gov_outcome) AS other_gov_outcome,
    bool_or(esg_outcome) AS esg_outcome
    FROM match1
    GROUP BY campaign_ids
    ORDER BY campaign_ids)

SELECT * FROM match2")

# Write data to PostgreSQL
rs <- dbWriteTable(pg, c("activist_director", "demands"), demands_data,
             row.names = FALSE, overwrite = TRUE)

rs <- dbGetQuery(pg, "ALTER TABLE demands OWNER TO activism")

sql <- paste("
  COMMENT ON TABLE demands IS
             'CREATED USING create_activist_demands.R ON ",
             format(Sys.time(), "%Y-%m-%d %X %Z"), "';", sep="")
rs <- dbGetQuery(pg, paste(sql, collapse="\n"))

rs <- dbDisconnect(pg)

# sharkwatch <- tbl(pg, sql("SELECT * FROM factset.sharkwatch"))
#
# gov_demands <-
#     sharkwatch %>%
#     mutate(demand = regexp_split_to_array(governance_demands_followthroughsuccess,
#                                           "(?<=(?:Yes|No)\\))")) %>%
#     mutate(demand = unnest(demand)) %>%
#     select(campaign_id, demand)
#
# val_demands <-
#     sharkwatch %>%
#     mutate(demand = regexp_split_to_array(value_demands_followthroughsuccess,
#                                           "(?<=(?:Yes|No)\\))")) %>%
#     mutate(demand = unnest(demand)) %>%
#     select(campaign_id, demand)
#
# demands <-
#     val_demands %>%
#     union(gov_demands) %>%
#     mutate(demand= regexp_split_to_array(demand, "\\((?=(?:Yes|No))")) %>%
#     mutate(demand = sql("demand[1]"), outcome=sql("demand[2]")) %>%
#     mutate(outcome = regexp_replace(outcome, "\\)", "")) %>%
#     filter(!is.na(outcome))
#
# demands_data <- demands %>% as.data.frame
#
# # Write data to PostgreSQL
# rs <- dbWriteTable(pg, c("activist_director", "demands"), demands_data,
#              row.names = FALSE, overwrite = TRUE)
#
# rs <- dbGetQuery(pg, "ALTER TABLE activist_director.demands OWNER TO activism")
#
# #> Source:   query [?? x 3]
# #> Database: postgres 9.6.3 [igow@iangow.me:5432/crsp]
# #>
# #> # A tibble: ?? x 3
# #>    campaign_id
# #>          <int>
# #>  1       54704
# #>  2      396364
# #>  3      396364
# #>  4      396364
# #>  5      396364
# #>  6      411278
# #>  7      411278
# #>  8      411278
# #>  9      411278
# #> 10      556550
# #> # ... with more rows, and 2 more variables: demand <chr>, outcome <chr>
#
# demands %>%
#     count(demand, outcome) %>%
#     collect() %>%
#     spread(key = outcome, value = n) %>%
#     mutate(Total = No + Yes) %>%
#     arrange(desc(Total))
