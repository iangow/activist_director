base <- lm("payout ~ ad_on_board + factor(year) + factor(permno) + cash + inst + mv + analyst + leverage + size_return + btm + roa + sale_growth + num_directors + outside_percent + staggered_board + log_at",
   data=reg.data, na.action="na.exclude")
robust <- coeftest.cluster(reg.data, base, cluster1="permno")
robust


demand_outcome <- dbGetQuery(pg, "
    SELECT DISTINCT a.*,
        coalesce(strategy_demand) AS strategy_demand,
        coalesce(merger_demand) AS merger_demand,
        coalesce(block_merger_demand) AS block_merger_demand,
        coalesce(acquisition_demand) AS acquisition_demand,
        coalesce(block_acquisition_demand) AS block_acquisition_demand,
        coalesce(divestiture_demand) AS divestiture_demand,
        coalesce(payout_demand) AS payout_demand,
        coalesce(leverage_demand) AS leverage_demand,
        coalesce(reits_demand) AS reits_demand,

        coalesce(board_seat_demand) AS board_seat_demand,
        coalesce(remove_director_demand) AS remove_director_demand,
        coalesce(add_indep_demand) AS add_indep_demand,
        coalesce(remove_officer_demand) AS remove_officer_demand,
        coalesce(remove_defense_demand) AS remove_defense_demand,
        coalesce(compensation_demand) AS compensation_demand,
        coalesce(other_gov_demand) AS other_gov_demand,
        coalesce(esg_demand) AS esg_demand,

        coalesce(strategy_outcome, FALSE) AS strategy_outcome,
        coalesce(merger_outcome, FALSE) AS merger_outcome,
        coalesce(block_merger_outcome, FALSE) AS block_merger_outcome,
        coalesce(acquisition_outcome, FALSE) AS acquisition_outcome,
        coalesce(block_acquisition_outcome, FALSE) AS block_acquisition_outcome,
        coalesce(divestiture_outcome, FALSE) AS divestiture_outcome,
        coalesce(payout_outcome, FALSE) AS payout_outcome,
        coalesce(leverage_outcome, FALSE) AS leverage_outcome,
        coalesce(reits_outcome, FALSE) AS reits_outcome,

        coalesce(board_seat_outcome, FALSE) AS board_seat_outcome,
        coalesce(remove_director_outcome, FALSE) AS remove_director_outcome,
        coalesce(add_indep_outcome, FALSE) AS add_indep_outcome,
        coalesce(remove_officer_outcome, FALSE) AS remove_officer_outcome,
        coalesce(remove_defense_outcome, FALSE) AS remove_defense_outcome,
        coalesce(compensation_outcome, FALSE) AS compensation_outcome,
        coalesce(other_gov_outcome, FALSE) AS other_gov_outcome,
        coalesce(esg_outcome, FALSE) AS esg_outcome
    FROM activist_director.activism_events AS a
    INNER JOIN activist_director.demands AS b
    ON a.campaign_ids::TEXT=b.campaign_ids
")

demand <- lm("board_seat_demand ~ strategy_demand + merger_demand + block_merger_demand + acquisition_demand + block_acquisition_demand + divestiture_demand + payout_demand + leverage_demand + reits_demand + remove_director_demand + add_indep_demand + remove_officer_demand + remove_defense_demand + compensation_demand + other_gov_demand + esg_demand - 1",
              data=demand_outcome, na.action="na.exclude")
demand <- coeftest.cluster(demand_outcome, demand, cluster1="permno")
demand

demand_to_ad <- lm("board_seat_outcome ~ strategy_demand + merger_demand + block_merger_demand + acquisition_demand + block_acquisition_demand + divestiture_demand + payout_demand + leverage_demand + reits_demand + board_seat_demand + remove_director_demand + add_indep_demand + remove_officer_demand + remove_defense_demand + compensation_demand + other_gov_demand + esg_demand - 1",
           data=demand_outcome, na.action="na.exclude")
demand_to_ad <- coeftest.cluster(demand_outcome, demand_to_ad, cluster1="permno")
demand_to_ad

outcome <- lm("board_seat_outcome ~ strategy_outcome + merger_outcome + block_merger_outcome + acquisition_outcome + block_acquisition_outcome + divestiture_outcome + payout_outcome + leverage_outcome + reits_outcome + remove_director_outcome + add_indep_outcome + remove_officer_outcome + remove_defense_outcome + compensation_outcome + other_gov_outcome + esg_outcome - 1",
              data=demand_outcome, na.action="na.exclude")
outcome <- coeftest.cluster(demand_outcome, outcome, cluster1="permno")
outcome



strategy <- lm("strategy_outcome ~ board_seat_outcome",
              data=subset(demand_outcome, strategy_demand), na.action="na.exclude")
strategy.se <- coeftest.cluster(subset(demand_outcome, strategy_demand), strategy, cluster1="permno")
strategy.se

merger <- lm("merger_outcome ~ board_seat_outcome",
               data=subset(demand_outcome, merger_demand), na.action="na.exclude")
merger.se <- coeftest.cluster(subset(demand_outcome, merger_demand), merger, cluster1="permno")
merger.se

block_merger <- lm("block_merger_outcome ~ board_seat_outcome",
               data=subset(demand_outcome, block_merger_demand), na.action="na.exclude")
block_merger.se <- coeftest.cluster(subset(demand_outcome, block_merger_demand), block_merger, cluster1="permno")
block_merger.se

acquisition <- lm("acquisition_outcome ~ board_seat_outcome",
               data=subset(demand_outcome, acquisition_demand), na.action="na.exclude")
acquisition.se <- coeftest.cluster(subset(demand_outcome, acquisition_demand), acquisition, cluster1="permno")
acquisition.se

block_acquisition <- lm("block_acquisition_outcome ~ board_seat_outcome",
               data=subset(demand_outcome, block_acquisition_demand), na.action="na.exclude")
block_acquisition.se <- coeftest.cluster(subset(demand_outcome, block_acquisition_demand), block_acquisition, cluster1="permno")
block_acquisition.se

divestiture <- lm("divestiture_outcome ~ board_seat_outcome",
               data=subset(demand_outcome, divestiture_demand), na.action="na.exclude")
divestiture.se <- coeftest.cluster(subset(demand_outcome, divestiture_demand), divestiture, cluster1="permno")
divestiture.se

payout <- lm("payout_outcome ~ board_seat_outcome",
               data=subset(demand_outcome, payout_demand), na.action="na.exclude")
payout.se <- coeftest.cluster(subset(demand_outcome, payout_demand), payout, cluster1="permno")
payout.se

leverage <- lm("leverage_outcome ~ board_seat_outcome",
               data=subset(demand_outcome, leverage_demand), na.action="na.exclude")
leverage.se <- coeftest.cluster(subset(demand_outcome, leverage_demand), leverage, cluster1="permno")
leverage.se

reits <- lm("reits_outcome ~ board_seat_outcome",
               data=subset(demand_outcome, reits_demand), na.action="na.exclude")
reits.se <- coeftest.cluster(subset(demand_outcome, reits_demand), reits, cluster1="permno")
reits.se

remove_director <- lm("remove_director_outcome ~ board_seat_outcome",
               data=subset(demand_outcome, remove_director_demand), na.action="na.exclude")
remove_director.se <- coeftest.cluster(subset(demand_outcome, remove_director_demand), remove_director, cluster1="permno")
remove_director.se

add_indep <- lm("add_indep_outcome ~ board_seat_outcome",
               data=subset(demand_outcome, add_indep_demand), na.action="na.exclude")
add_indep.se <- coeftest.cluster(subset(demand_outcome, add_indep_demand), add_indep, cluster1="permno")
add_indep.se

remove_officer <- lm("remove_officer_outcome ~ board_seat_outcome",
               data=subset(demand_outcome, remove_officer_demand), na.action="na.exclude")
remove_officer.se <- coeftest.cluster(subset(demand_outcome, remove_officer_demand), remove_officer, cluster1="permno")
remove_officer.se

remove_defense <- lm("remove_defense_outcome ~ board_seat_outcome",
               data=subset(demand_outcome, remove_defense_demand), na.action="na.exclude")
remove_defense.se <- coeftest.cluster(subset(demand_outcome, remove_defense_demand), remove_defense, cluster1="permno")
remove_defense.se

compensation <- lm("compensation_outcome ~ board_seat_outcome",
               data=subset(demand_outcome, compensation_demand), na.action="na.exclude")
compensation.se <- coeftest.cluster(subset(demand_outcome, compensation_demand), compensation, cluster1="permno")
compensation.se

other_gov <- lm("other_gov_outcome ~ board_seat_outcome",
               data=subset(demand_outcome, other_gov_demand), na.action="na.exclude")
other_gov.se <- coeftest.cluster(subset(demand_outcome, other_gov_demand), other_gov, cluster1="permno")
other_gov.se

strategy.se
merger.se
block_merger.se
acquisition.se
block_acquisition.se
divestiture.se
payout.se
leverage.se
reits.se
remove_director.se
add_indep.se
remove_officer.se
remove_defense.se
compensation.se
other_gov.se
