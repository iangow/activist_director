# Create a table for changes in outcomes (create_outcome_changes.R)

# Load Libraries
library(lmtest)
library(sandwich)
library(car)
library(stargazer)
library(xtable)
library(parallel)
library(DBI)
library(psych)
library(dplyr)

# Get data from PostgreSQL
pg <- dbConnect(RPostgres::Postgres(), bigint = "integer")
rs <- dbExecute(pg, "SET search_path TO activist_director")
rs <- dbExecute(pg, "SET work_mem='5GB'")

outcome_controls <- tbl(pg, "outcome_controls")
activist_director_years <- tbl(pg, "activist_director_years")
outcomes <- tbl(pg, sql(paste0(readLines("~/activist_director/drafts/tables/other_outcomes.sql"), collapse="\n")))
activist_demands <- tbl(pg, sql("SELECT * FROM activist_director.demands"))

# Winsorize selected variables in a data frame
win01 <- function(x) psych::winsor(x, trim=0.01)

controls <- paste("analyst inst size_return mv btm leverage payout roa sale_growth",
                  "num_directors outside_percent staggered_board log_at")

# Winsorize changes
omits <- unlist(strsplit(controls, "\\s+"))

lhs.vars <- c("cash", "leverage", "payout", "capex_cum", "rnd_cum", "adv_cum")
winsor.vars <- unique(c(unlist(strsplit(controls, "\\s+")), lhs.vars,
                        paste0(lhs.vars, "_p1"), paste0(lhs.vars, "_p2"),
                        paste0(lhs.vars, "_p3")))

win_vars <- vars(winsor.vars)

outcome_changes <-
    outcome_controls %>%
    inner_join(outcomes, by = c("gvkey", "datadate")) %>%
    inner_join(activist_director_years, by = c("permno", "datadate")) %>%
    filter(firm_exists_p2) %>%
    left_join(activist_demands) %>%
    mutate(strategy_demand = coalesce(strategy_demand, FALSE),
           merger_demand = coalesce(merger_demand, FALSE),
           block_merger_demand = coalesce(block_merger_demand, FALSE),
           acquisition_demand = coalesce(acquisition_demand, FALSE),
           block_acquisition_demand = coalesce(block_acquisition_demand, FALSE),
           divestiture_demand = coalesce(divestiture_demand, FALSE),
           payout_demand = coalesce(payout_demand, FALSE),
           leverage_demand = coalesce(leverage_demand, FALSE),
           remove_director_demand = coalesce(remove_director_demand, FALSE),
           add_indep_demand = coalesce(add_indep_demand, FALSE),
           remove_officer_demand = coalesce(remove_officer_demand, FALSE),
           remove_defense_demand = coalesce(remove_defense_demand, FALSE),
           compensation_demand = coalesce(compensation_demand, FALSE),
           other_gov_demand = coalesce(other_gov_demand, FALSE),
           esg_demand = coalesce(esg_demand, FALSE)) %>%
    collect() %>%
    mutate_at(win_vars, win01) %>%
    mutate(affiliated = if_else(affiliated=="affiliated", "affiliated",
                                if_else(affiliated=="unaffiliated", "unaffiliated",
                                        if_else(affiliated=="activist_director", "unaffiliated",
                                                if_else(affiliated=="activist_demand", "z_other_activism",
                                                        if_else(affiliated=="activism", "z_other_activism", "_none"))))))

outcome_changes <-
    outcome_changes %>%
    select(permno, gvkey, datadate, fyear,
           cash, cash_p2, cash_p3,
           leverage, leverage_p2, leverage_p3,
           payout, payout_p2, payout_p3,
           rnd_cum, rnd_cum_p2, rnd_cum_p3,
           capex_cum, capex_cum_p2, capex_cum_p3,
           adv_cum, adv_cum_p2, adv_cum_p3) %>%
    distinct() %>%
    group_by(fyear) %>%
    mutate(cash_10 = as.numeric(ntile(cash_p2,10)==1),
           cash_20 = as.numeric(ntile(cash_p2,5)==1),
           cash_25 = as.numeric(ntile(cash_p2,4)==1),
           cash_33 = as.numeric(ntile(cash_p2,3)==1),
           cash_50 = as.numeric(ntile(cash_p2,2)==1),
           leverage_10 = as.numeric(ntile(leverage_p2,10)==10),
           leverage_20 = as.numeric(ntile(leverage_p2,5)==5),
           leverage_25 = as.numeric(ntile(leverage_p2,4)==4),
           leverage_33 = as.numeric(ntile(leverage_p2,3)==3),
           leverage_50 = as.numeric(ntile(leverage_p2,2)==2),
           payout_10 = as.numeric(ntile(payout_p2,10)==10),
           payout_20 = as.numeric(ntile(payout_p2,5)==5),
           payout_25 = as.numeric(ntile(payout_p2,4)==4),
           payout_33 = as.numeric(ntile(payout_p2,3)==3),
           payout_50 = as.numeric(ntile(payout_p2,2)==2),
           rnd_cum_10 = as.numeric(ntile(rnd_cum_p2,10)==1),
           rnd_cum_20 = as.numeric(ntile(rnd_cum_p2,5)==1),
           rnd_cum_25 = as.numeric(ntile(rnd_cum_p2,4)==1),
           rnd_cum_33 = as.numeric(ntile(rnd_cum_p2,3)==1),
           rnd_cum_50 = as.numeric(ntile(rnd_cum_p2,2)==1),
           capex_cum_10 = as.numeric(ntile(capex_cum_p2,10)==1),
           capex_cum_20 = as.numeric(ntile(capex_cum_p2,5)==1),
           capex_cum_25 = as.numeric(ntile(capex_cum_p2,4)==1),
           capex_cum_33 = as.numeric(ntile(capex_cum_p2,3)==1),
           capex_cum_50 = as.numeric(ntile(capex_cum_p2,2)==1),
           adv_cum_10 = as.numeric(ntile(adv_cum_p2,10)==1),
           adv_cum_20 = as.numeric(ntile(adv_cum_p2,5)==1),
           adv_cum_25 = as.numeric(ntile(adv_cum_p2,4)==1),
           adv_cum_33 = as.numeric(ntile(adv_cum_p2,3)==1),
           adv_cum_50 = as.numeric(ntile(adv_cum_p2,2)==1),

           d2_cash_10 = as.numeric(ntile(cash_p2-cash,10)==1),
           d2_cash_20 = as.numeric(ntile(cash_p2-cash,5)==1),
           d2_cash_25 = as.numeric(ntile(cash_p2-cash,4)==1),
           d2_cash_33 = as.numeric(ntile(cash_p2-cash,3)==1),
           d2_cash_50 = as.numeric(ntile(cash_p2-cash,2)==1),
           d2_leverage_10 = as.numeric(ntile(leverage_p2-leverage,10)==10),
           d2_leverage_20 = as.numeric(ntile(leverage_p2-leverage,5)==5),
           d2_leverage_25 = as.numeric(ntile(leverage_p2-leverage,4)==4),
           d2_leverage_33 = as.numeric(ntile(leverage_p2-leverage,3)==3),
           d2_leverage_50 = as.numeric(ntile(leverage_p2-leverage,2)==2),
           d2_payout_10 = as.numeric(ntile(payout_p2-payout,10)==10),
           d2_payout_20 = as.numeric(ntile(payout_p2-payout,5)==5),
           d2_payout_25 = as.numeric(ntile(payout_p2-payout,4)==4),
           d2_payout_33 = as.numeric(ntile(payout_p2-payout,3)==3),
           d2_payout_50 = as.numeric(ntile(payout_p2-payout,2)==2),
           d2_rnd_cum_10 = as.numeric(ntile(rnd_cum_p2-rnd_cum,10)==1),
           d2_rnd_cum_20 = as.numeric(ntile(rnd_cum_p2-rnd_cum,5)==1),
           d2_rnd_cum_25 = as.numeric(ntile(rnd_cum_p2-rnd_cum,4)==1),
           d2_rnd_cum_33 = as.numeric(ntile(rnd_cum_p2-rnd_cum,3)==1),
           d2_rnd_cum_50 = as.numeric(ntile(rnd_cum_p2-rnd_cum,2)==1),
           d2_capex_cum_10 = as.numeric(ntile(capex_cum_p2-capex_cum,10)==1),
           d2_capex_cum_20 = as.numeric(ntile(capex_cum_p2-capex_cum,5)==1),
           d2_capex_cum_25 = as.numeric(ntile(capex_cum_p2-capex_cum,4)==1),
           d2_capex_cum_33 = as.numeric(ntile(capex_cum_p2-capex_cum,3)==1),
           d2_capex_cum_50 = as.numeric(ntile(capex_cum_p2-capex_cum,2)==1),
           d2_adv_cum_10 = as.numeric(ntile(adv_cum_p2-adv_cum,10)==1),
           d2_adv_cum_20 = as.numeric(ntile(adv_cum_p2-adv_cum,5)==1),
           d2_adv_cum_25 = as.numeric(ntile(adv_cum_p2-adv_cum,4)==1),
           d2_adv_cum_33 = as.numeric(ntile(adv_cum_p2-adv_cum,3)==1),
           d2_adv_cum_50 = as.numeric(ntile(adv_cum_p2-adv_cum,2)==1),

           d3_cash_10 = as.numeric(ntile(cash_p3-cash,10)==1),
           d3_cash_20 = as.numeric(ntile(cash_p3-cash,5)==1),
           d3_cash_25 = as.numeric(ntile(cash_p3-cash,4)==1),
           d3_cash_33 = as.numeric(ntile(cash_p3-cash,3)==1),
           d3_cash_50 = as.numeric(ntile(cash_p3-cash,2)==1),
           d3_leverage_10 = as.numeric(ntile(leverage_p3-leverage,10)==10),
           d3_leverage_20 = as.numeric(ntile(leverage_p3-leverage,5)==5),
           d3_leverage_25 = as.numeric(ntile(leverage_p3-leverage,4)==4),
           d3_leverage_33 = as.numeric(ntile(leverage_p3-leverage,3)==3),
           d3_leverage_50 = as.numeric(ntile(leverage_p3-leverage,2)==2),
           d3_payout_10 = as.numeric(ntile(payout_p3-payout,10)==10),
           d3_payout_20 = as.numeric(ntile(payout_p3-payout,5)==5),
           d3_payout_25 = as.numeric(ntile(payout_p3-payout,4)==4),
           d3_payout_33 = as.numeric(ntile(payout_p3-payout,3)==3),
           d3_payout_50 = as.numeric(ntile(payout_p3-payout,2)==2),
           d3_rnd_cum_10 = as.numeric(ntile(rnd_cum_p3-rnd_cum,10)==1),
           d3_rnd_cum_20 = as.numeric(ntile(rnd_cum_p3-rnd_cum,5)==1),
           d3_rnd_cum_25 = as.numeric(ntile(rnd_cum_p3-rnd_cum,4)==1),
           d3_rnd_cum_33 = as.numeric(ntile(rnd_cum_p3-rnd_cum,3)==1),
           d3_rnd_cum_50 = as.numeric(ntile(rnd_cum_p3-rnd_cum,2)==1),
           d3_capex_cum_10 = as.numeric(ntile(capex_cum_p3-capex_cum,10)==1),
           d3_capex_cum_20 = as.numeric(ntile(capex_cum_p3-capex_cum,5)==1),
           d3_capex_cum_25 = as.numeric(ntile(capex_cum_p3-capex_cum,4)==1),
           d3_capex_cum_33 = as.numeric(ntile(capex_cum_p3-capex_cum,3)==1),
           d3_capex_cum_50 = as.numeric(ntile(capex_cum_p3-capex_cum,2)==1),
           d3_adv_cum_10 = as.numeric(ntile(adv_cum_p3-adv_cum,10)==1),
           d3_adv_cum_20 = as.numeric(ntile(adv_cum_p3-adv_cum,5)==1),
           d3_adv_cum_25 = as.numeric(ntile(adv_cum_p3-adv_cum,4)==1),
           d3_adv_cum_33 = as.numeric(ntile(adv_cum_p3-adv_cum,3)==1),
           d3_adv_cum_50 = as.numeric(ntile(adv_cum_p3-adv_cum,2)==1)) %>%
    ungroup() %>%
    as.data.frame()

rs <- dbWriteTable(pg, "outcome_changes", outcome_changes,
                   overwrite=TRUE, row.names=FALSE)

rs <- dbExecute(pg, "ALTER TABLE outcome_changes OWNER TO activism")

rs <- dbExecute(pg, "CREATE INDEX ON outcome_changes (permno, datadate)")

sql <- paste("COMMENT ON TABLE outcome_changes IS
             'CREATED USING create_outcome_changes.R ON ",
             format(Sys.time(), "%Y-%m-%d %X %Z"), "';", sep="")
rs <- dbExecute(pg, paste(sql, collapse="\n"))

rs <- dbDisconnect(pg)
