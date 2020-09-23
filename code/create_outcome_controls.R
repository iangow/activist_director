#!/usr/bin/env Rscript
library(RPostgreSQL)
library(dplyr, warn.conflicts = FALSE)

pg <- dbConnect(PostgreSQL())

rs <- dbGetQuery(pg, "SET search_path TO activist_director, public")

rs <- dbGetQuery(pg, "SET work_mem='8GB'")

# Get all votes on directors that were not withdrawn and which have meaningful vote data

permnos <- tbl(pg, "permnos")
activism_events <- tbl(pg, "activism_events")
activist_director.inst <- tbl(pg, "inst")
equilar_w_activism <- tbl(pg, sql("SELECT * FROM activist_director.equilar_w_activism"))

issvoting.compvote <- tbl(pg, sql("SELECT * FROM issvoting.compvote"))
factset.sharkrepellent  <- tbl(pg, sql("SELECT * FROM factset.sharkrepellent"))
factset.staggered_board  <- tbl(pg, sql("SELECT * FROM factset.staggered_board"))

funda <- tbl(pg, sql("SELECT * FROM comp.funda"))
ccmxpf_linktable <- tbl(pg, sql("SELECT * FROM crsp.ccmxpf_linktable"))
names <- tbl(pg, sql("SELECT * FROM comp.names"))
ibes.statsum_epsus <- tbl(pg, sql("SELECT * FROM ibes.statsum_epsus"))
mrets <- tbl(pg, sql("SELECT * FROM crsp.mrets"))
equilar_hbs.company_financials <-
    tbl(pg, sql("SELECT * FROM equilar_hbs.company_financials")) %>%
    rename(period = fye)
equilar_hbs.director_index <-
    tbl(pg, sql("SELECT * FROM equilar_hbs.director_index"))

#-- Compustat with PERMNO
firm_years <-
    funda %>%
    filter(fyear > 2000) %>%
    filter(indfmt=='INDL', consol=='C', popsrc=='D', datafmt=='STD') %>%
    mutate(year = date_part('year', datadate)) %>%
    inner_join(ccmxpf_linktable, by = "gvkey") %>%
    filter(usedflag=='1', linkprim %in% c('C', 'P')) %>%
    filter(datadate >= linkdt,
           datadate <= linkenddt | is.na(linkenddt)) %>%
    select(gvkey, year, datadate, lpermno) %>%
    rename(permno = lpermno) %>%
    compute() %>%
    arrange(permno, datadate)

sics <-
    firm_years %>%
    mutate(year = date_part('year', datadate)) %>%
    inner_join(names, by = "gvkey") %>%
    filter(between(year, year1, year2)) %>%
    select(gvkey, datadate, sic) %>%
    mutate(sic2 = substr(sic, 1L, 2L)) %>%
    compute() %>%
    arrange(gvkey, datadate)

#- Compustat controls
funda_mod <-
    funda %>%
    filter(indfmt=='INDL', consol=='C', popsrc=='D', datafmt=='STD') %>%
    select(gvkey, datadate, fyear,
        at, sale, prcc_f, csho, ceq, oibdp, dvc, dvp, prstkc,
        pstkrv,dltt, dlc, capx, ppent, che, tlcf, pi, txfed) %>%
    mutate(dvc= coalesce(dvc, 0),
        dvp = coalesce(dvp, 0),
        prstkc = coalesce(prstkc, 0),
        pstkrv = coalesce(pstkrv, 0),
        dltt = coalesce(dltt, 0),
        dlc  = coalesce(dlc, 0),
        capx = coalesce(capx, 0))

compustat <-
    funda_mod %>%
    group_by(gvkey) %>%
    arrange(datadate) %>%
    mutate(capex = if_else(lag(ppent) > 0, capx/lag(ppent), NA),
            log_at = if_else(at > 0, log(at), NA),
            payout = if_else(oibdp > 0, (dvc+prstkc-pstkrv)/oibdp, NA),
            bv = if_else(ceq > 0, log(ceq), NA),
            mv = if_else(prcc_f * csho > 0, log(prcc_f*csho), NA),
            btm = if_else(prcc_f * csho > 0, ceq/(prcc_f*csho), NA),
            leverage = if_else(dltt+dlc+ceq > 0, (dltt+dlc)/(dltt+dlc+ceq), NA),
            book_leverage = if_else(at > 0, (dltt+dlc)/at, NA),
            market_leverage = if_else(at-ceq+prcc_f*csho > 0, (dltt+dlc)/(at-ceq+prcc_f*csho), NA),
            net_leverage = if_else(at > 0, (dltt+dlc-che)/at, NA),
            dividend = if_else(oibdp > 0, (dvc + dvp)/oibdp,
                        if_else(oibdp <= 0 & (dvc + dvp)==0, 0, NA)),
            cash = if_else(at > 0, che/at, NA),
            roa = if_else(lag(at) > 0, oibdp/lag(at), NA),
            sale_growth = if_else(lag(sale) > 0, sale/lag(sale), NA),
            firm_exists_p1 = !is.na(lead(datadate, 1L)),
            firm_exists_p2 = !is.na(lead(datadate, 2L)),
            firm_exists_p3 = !is.na(lead(datadate, 3L)),
            nol_carryforward = tlcf > 0 & coalesce(pi,txfed) <= 0) %>%
    compute()

compustat_w_permno <-
    compustat %>%
    inner_join(firm_years, by = c("gvkey", "datadate")) %>%
    inner_join(sics, by = c("gvkey", "datadate")) %>%
    select(permno, datadate, everything()) %>%
    arrange(permno, datadate)


#- CRSP Returns
crsp <-
    mrets %>%
    inner_join(firm_years, by = "permno") %>%
    mutate(end_date = eomonth(datadate),
           start_date = sql("datadate - interval '11 months'")) %>%
    mutate(start_date = date_trunc('month', start_date)) %>%
    filter(between(date, start_date, end_date)) %>%
    group_by(permno, datadate) %>%
    summarize(size_return =  product(1+ret) - product(1+vwretd),
              num_months = n()) %>%
    ungroup() %>%
    compute() %>%
    arrange(permno, datadate)

# crsp %>% count(num_months) %>% arrange(num_months) %>% print(n=12)

#- CRSP returns
crsp_m1 <-
    firm_years %>%
    mutate(end_date = sql("datadate - interval '12 months'"),
           start_date = sql("datadate - interval '23 months'")) %>%
    mutate(start_date = date_trunc('month', start_date),
           end_date = eomonth(end_date)) %>%
    inner_join(mrets, by = "permno") %>%
    filter(between(date, start_date, end_date)) %>%
    group_by(permno, datadate) %>%
    summarize(size_return_m1 =  product(1+ret) - product(1+vwretd),
              num_months = n()) %>%
    ungroup() %>%
    select(-num_months) %>%
    compute() %>%
    arrange(permno, datadate)

# crsp_m1 %>% count(num_months) %>% arrange(num_months) %>% print(n = Inf)
factset.sharkrepellent %>%
    select(vote_requirement_to_elect_directors, cusip_9_digit) %>%
    distinct() %>%
    group_by(cusip_9_digit) %>%
    filter(n() > 1) %>%
    inner_join(factset.sharkrepellent,
               by = c("vote_requirement_to_elect_directors", "cusip_9_digit")) %>%
    count()

factset.sharkrepellent %>%
    select(unequal_voting, cusip_9_digit) %>%
    distinct() %>%
    group_by(cusip_9_digit) %>%
    filter(n() > 1) %>%
    inner_join(factset.sharkrepellent,
               by = c("unequal_voting", "cusip_9_digit")) %>%
    count()

sharkrepellent <-
    factset.sharkrepellent %>%
    group_by(cusip_9_digit) %>%
    arrange(company_status_date) %>%
    mutate(prior_date=lag(company_status_date)) %>%
    mutate(insider_percent = insider_ownership_percent,
              insider_diluted_percent = insider_ownership_diluted_percent,
              inst_percent = institutional_ownership_percent,
              top_10_percent = top_10_institutional_ownership_percent,
              majority = vote_requirement_to_elect_directors=='Majority',
              dual_class = unequal_voting=='Yes') %>%
    select(cusip_9_digit, company_status, company_status_date,
           prior_date, insider_percent, insider_diluted_percent,
           inst_percent, top_10_percent, majority, dual_class,
           company_name) %>%
    mutate(ncusip = substr(cusip_9_digit, 1L, 8L)) %>%
    inner_join(permnos, by = "ncusip") %>%
    inner_join(firm_years, by = "permno") %>%
    select(-gvkey) %>%
    filter(datadate < company_status_date | is.na(company_status_date),
           datadate >= prior_date | is.na(prior_date)) %>%
    select(permno, datadate, everything()) %>%
    ungroup() %>%
    compute()

with_agg <-
    sharkrepellent %>%
    group_by(permno) %>%
    mutate_at(vars(insider_percent, insider_diluted_percent,
           inst_percent, top_10_percent), funs(is.na)) %>%
    mutate_at(vars(insider_percent, insider_diluted_percent,
           inst_percent, top_10_percent), funs(not)) %>%
    summarize_at(vars(insider_percent, insider_diluted_percent,
           inst_percent, top_10_percent), funs(bool_or)) %>%
    inner_join(sharkrepellent %>% select(permno, datadate),
               by = "permno") %>%
    select(-permno, -datadate) %>%
    mutate_all(.funs = as.integer) %>%
    summarize_all(.funs = sum)

without_agg <-
    sharkrepellent %>%
    select(permno, insider_percent, insider_diluted_percent,
           inst_percent, top_10_percent) %>%
    mutate_at(vars(insider_percent, insider_diluted_percent,
           inst_percent, top_10_percent), funs(is.na)) %>%
    mutate_at(vars(insider_percent, insider_diluted_percent,
           inst_percent, top_10_percent), funs(not)) %>%
    select(-permno) %>%
    mutate_all(.funs = as.integer) %>%
    summarize_all(.funs = sum)

staggered_board <-
    factset.staggered_board %>%
    mutate(ncusip = substr(cusip_9_digit, 1L, 8L)) %>%
    inner_join(permnos, by = "ncusip") %>%
    inner_join(firm_years, by = "permno") %>%
    filter(between(datadate, beg_date, end_date)) %>%
    select(permno, datadate, staggered_board)

# analyst coverage
ibes <-
    ibes.statsum_epsus %>%
    filter(measure=='EPS', fiscalp=='ANN', fpi=='1') %>%
    mutate(analyst = numest, ncusip = cusip,
           fy_end = eomonth(statpers)) %>%
    select(ncusip, fy_end, analyst) %>%
    inner_join(permnos, by = "ncusip") %>%
    inner_join(
        firm_years %>%
            mutate(fy_end = eomonth(datadate)),
        by = c("fy_end", "permno")) %>%
    select(permno, datadate, analyst) %>%
    distinct()

equilar <-
    equilar_w_activism %>%
    group_by(permno, period) %>%
    summarize(outside_percent = mean(as.integer(outsider), na.rm = TRUE),
              age = mean(as.integer(age), na.rm = TRUE),
              tenure = mean(as.integer(tenure_calc), na.rm = TRUE)) %>%
    ungroup() %>%
    arrange(permno, period)

count_directors <-
    equilar_w_activism %>%
        select(permno, period, executive_id) %>%
        distinct() %>%
        group_by(permno, period) %>%
        summarize(num_directors = n())

equilar_w_permno <-
    equilar %>%
    inner_join(count_directors, by = c("permno", "period")) %>%
    inner_join(
        equilar_hbs.company_financials %>%
            mutate(ncusip = substr(cusip, 1L, 8L)) %>%
            select(company_id, period, ncusip), by = "period") %>%
    inner_join(permnos, by = c("permno", "ncusip")) %>%
    select(-ncusip, -company_id) %>%
    rename(datadate = period) %>%
    select(permno, datadate, everything()) %>%
    compute() %>%
    arrange(permno, datadate)

inst <-
    activist_director.inst %>%
    select(permno, datadate, inst)

controls <-
    compustat_w_permno %>%
    left_join(equilar_w_permno %>% mutate(on_equilar = TRUE),
              by = c("permno", "datadate")) %>%
    left_join(crsp, by = c("permno", "datadate")) %>%
    left_join(crsp_m1, by = c("permno", "datadate")) %>%
    left_join(staggered_board, by = c("permno", "datadate")) %>%
    left_join(sharkrepellent, by = c("permno", "datadate", "year")) %>%
    left_join(ibes, by = c("permno", "datadate")) %>%
    left_join(inst, by = c("permno", "datadate")) %>%
    mutate(inst = coalesce(inst, 0),
           analyst = coalesce(analyst, 0),
           on_equilar = coalesce(on_equilar, FALSE)) %>%
    compute() %>%
    arrange(permno, datadate)

first_date <-
    activism_events %>%
    summarize(sql("min(eff_announce_date) - interval '1 year - 1 day'")) %>%
    pull() %>%
    as.Date()

last_date <-
    activism_events %>%
    summarize(max(eff_announce_date, na.rm = TRUE)) %>%
    pull() %>%
    as.Date()

controls_activism_years <-
    firm_years %>%
    inner_join(activism_events, by = "permno") %>%
    filter(between(eff_announce_date, datadate,
                    sql("datadate + interval '1 year - 1 day'"))) %>%
    select(-gvkey) %>%
    distinct() %>%
    arrange(permno, datadate)

rs <- dbExecute(pg, "DROP TABLE IF EXISTS outcome_controls")

outcome_controls <-
    controls %>%
    filter(between(datadate, first_date, last_date)) %>%
    compute() %>%
    left_join(controls_activism_years, by = c("permno", "datadate", "year")) %>%
    arrange(permno, datadate) %>%
    mutate_at(vars(category, affiliated,
                   two_plus, early, big_investment,
                   affiliated_hostile, affiliated_two_plus, affiliated_high_stake, affiliated_big_inv,
                   affiliated_prior, affiliated_recent, affiliated_recent_three),
              funs(coalesce(., '_none'))) %>%
    mutate_at(vars(),
              funs(coalesce(., FALSE))) %>%
    mutate(category_activist_director = if_else(activist_director, 'activist_director',
            if_else(activism, 'non_activist_director', '_none'))) %>%
    distinct() %>%
    arrange(permno, datadate) %>%
    compute(name = "outcome_controls", tempoary = FALSE)

# Write data to PostgreSQL
rs <- dbExecute(pg, "ALTER TABLE outcome_controls OWNER to activism")

rs <- dbExecute(pg, "CREATE INDEX ON outcome_controls (permno, datadate)")

sql <- paste("
  COMMENT ON TABLE activist_director.outcome_controls IS
             'CREATED USING create_outcome_controls.R ON ",
             format(Sys.time(), "%Y-%m-%d %X %Z"), "';", sep="")
rs <- dbExecute(pg, paste(sql, collapse="\n"))

rs <- dbDisconnect(pg)
