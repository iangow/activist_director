library(RPostgreSQL)
library(dplyr, warn.conflicts = FALSE)

pg <- dbConnect(PostgreSQL())

rs <- dbGetQuery(pg, "RESET search_path")

rs <- dbGetQuery(pg, "SET work_mem='8GB'")

# Get all votes on directors that were not withdrawn and which have meaningful vote data
issvoting.compvote <- tbl(pg, sql("SELECT * FROM issvoting.compvote"))
factset.permnos <- tbl(pg, sql("SELECT * FROM factset.permnos"))
factset.sharkrepellent  <- tbl(pg, sql("SELECT * FROM factset.sharkrepellent"))
factset.staggered_board  <- tbl(pg, sql("SELECT * FROM factset.staggered_board"))
director_names <- tbl(pg, sql("SELECT * FROM issvoting.director_names"))
# This tables about 2 minutes to run.
equilar_w_activism  <- tbl(pg, sql("SELECT * FROM activist_director.equilar_w_activism"))
funda <- tbl(pg, sql("SELECT * FROM comp.funda"))
ccmxpf_linktable <- tbl(pg, sql("SELECT * FROM crsp.ccmxpf_linktable"))
activism_events <- tbl(pg, sql("SELECT * FROM activist_director.activism_events"))
names <- tbl(pg, sql("SELECT * FROM comp.names"))
activist_director.inst <- tbl(pg, sql("SELECT * FROM activist_director.inst"))
ibes.statsum_epsus <- tbl(pg, sql("SELECT * FROM ibes.statsum_epsus"))
mrets <- tbl(pg, sql("SELECT * FROM crsp.mrets"))
director.co_fin <- tbl(pg, sql("SELECT * FROM director.co_fin"))
director.director <- tbl(pg, sql("SELECT * FROM director.director"))

# DROP TABLE IF EXISTS activist_director.outcome_controls;

# CREATE TABLE activist_director.outcome_controls AS

#-- Compustat with PERMNO
firm_years <-
    funda %>%
    filter(fyear > 2000) %>%
    filter(indfmt=='INDL', consol=='C', popsrc=='D', datafmt=='STD') %>%
    inner_join(ccmxpf_linktable) %>%
    filter(usedflag=='1', linkprim %in% c('C', 'P')) %>%
    filter(datadate >= linkdt,
           datadate <= linkenddt | is.na(linkenddt)) %>%
    select(gvkey, datadate, lpermno) %>%
    rename(permno = lpermno) %>%
    compute()

sics <-
    firm_years %>%
    mutate(year = date_part('year', datadate)) %>%
    inner_join(names) %>%
    filter(between(year, year1, year2)) %>%
    select(gvkey, datadate, sic) %>%
    mutate(sic2 = substr(sic, 1L, 2L)) %>%
    compute()

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
           mv = if_else(prcc_f * csho > 0, log(prcc_f * csho), NA),
           btm = if_else(prcc_f * csho > 0, ceq/(prcc_f*csho), NA),
           leverage = if_else(dltt+dlc+ceq > 0, (dltt+dlc)/(dltt+dlc+ceq), NA),
           dividend = if_else(oibdp > 0, (dvc + dvp)/oibdp,
                              if_else(oibdp <= 0 & (dvc + dvp)==0, 0, NA)),
           cash = if_else(at > 0, che/at, NA),
           roa = if_else(lag(at) > 0, oibdp/lag(at), NA),
           sale_growth = if_else(lag(sale) > 0, sale/lag(sale), NA),
           firm_exists_p1 = !is.na(lead(datadate, 1L)),
            firm_exists_p2 = !is.na(lead(datadate, 2L)),
            firm_exists_p3 = !is.na(lead(datadate, 3L)),
            tnol_carryforward = tlcf > 0 & coalesce(pi,txfed) <= 0) %>%
    compute()

compustat_w_permno <-
    compustat %>%
    inner_join(firm_years) %>%
    inner_join(sics)

#- CRSP Returns
crsp <-
    mrets %>%
    inner_join(firm_years) %>%
    mutate(end_date = eomonth(datadate),
        start_date = sql("datadate - interval '11 months'")) %>%
    mutate(start_date = date_trunc('month', start_date)) %>%
    filter(between(date, start_date, end_date)) %>%
    group_by(permno, datadate) %>%
    summarize(size_return =  product(1+ret) - product(1+vwretd),
              num_months = n()) %>%
    ungroup() %>%
    compute()

# crsp %>% count(num_months) %>% arrange(num_months) %>% print(n=12)

#- CRSP returns
crsp_m1 <-
    firm_years %>%
    mutate(end_date = sql("datadate - interval '12 months'"),
           start_date = sql("datadate - interval '23 months'")) %>%
    mutate(start_date = date_trunc('month', start_date),
           end_date = eomonth(end_date)) %>%
    inner_join(mrets) %>%
    filter(between(date, start_date, end_date)) %>%
    group_by(permno, datadate) %>%
    summarize(size_return_m1 =  product(1+ret) - product(1+vwretd),
              num_months = n()) %>%
    ungroup() %>%
    select(-num_months) %>%
    compute()

# crsp_m1 %>% count(num_months) %>% arrange(num_months) %>% print(n = Inf)
factset.sharkrepellent %>%
    select(vote_requirement_to_elect_directors, cusip_9_digit) %>%
    distinct() %>%
    group_by(cusip_9_digit) %>%
    filter(n() > 1) %>%
    inner_join(factset.sharkrepellent) %>%
    count()

factset.sharkrepellent %>%
    select(unequal_voting, cusip_9_digit) %>%
    distinct() %>%
    group_by(cusip_9_digit) %>%
    filter(n() > 1) %>%
    inner_join(factset.sharkrepellent) %>%
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
    inner_join(factset.permnos) %>%
    inner_join(firm_years) %>%
    select(-gvkey) %>%
    filter(datadate < company_status_date | is.na(company_status_date),
           datadate >= prior_date | is.na(prior_date)) %>%
    select(permno, datadate, everything()) %>%
    ungroup() %>%
    compute()

without_agg <-
    sharkrepellent %>%
    mutate(has_insider_percent=!is.na(insider_percent)) %>%
    count(has_insider_percent) %>%
    filter(has_insider_percent==TRUE) %>%
    select(n) %>%
    pull()

with_agg <-
    sharkrepellent %>%
    group_by(permno) %>%
    mutate_at(vars(insider_percent, insider_diluted_percent,
           inst_percent, top_10_percent), funs(is.na)) %>%
    mutate_at(vars(insider_percent, insider_diluted_percent,
           inst_percent, top_10_percent), funs(not)) %>%
    summarize_at(vars(insider_percent, insider_diluted_percent,
           inst_percent, top_10_percent), funs(bool_or)) %>%
    inner_join(sharkrepellent %>% select(permno, datadate)) %>%
    select(-permno, -datadate) %>%
    mutate_all(.funs = as.integer) %>%
    summarize_all(.funs = sum) %>%
    collect()

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
    summarize_all(.funs = sum) %>%
    collect()

with_agg - without_agg

staggered_board <-
    # SELECT DISTINCT permno, beg_date, end_date, staggered_board
    factset.staggered_board %>%
    mutate(ncusip = substr(cusip_9_digit, 1L, 8L)) %>%
    inner_join(factset.permnos) %>%
    inner_join(firm_years) %>%
    filter(between(datadate, beg_date, end_date)) %>%
    select(permno, datadate, staggered_board)


# analyst coverage
ibes <-
    ibes.statsum_epsus %>%
    filter(measure=='EPS', fiscalp=='ANN', fpi=='1') %>%
    mutate(analyst = numest, ncusip = cusip,
           fy_end = eomonth(statpers)) %>%
    select(ncusip, fy_end, analyst) %>%
    inner_join(factset.permnos) %>%
    inner_join(
        firm_years %>%
            mutate(fy_end = eomonth(datadate))) %>%
    select(permno, datadate, analyst)


equilar <-
    equilar_w_activism %>%
    group_by(company_id, fy_end) %>%
    summarize(outside_percent = mean(as.integer(outsider)),
              age = avg(age), tenure = avg(tenure)) %>%
    filter(company_id %NOT IN% c(2583L, 8598L, 2907L, 7506L),
           !(company_id == 4431L & fy_end =='2010-09-30'),
           !(company_id == 46588L & fy_end == '2012-12-31')) %>%
    ungroup()

count_directors <-
    director.director %>%
        select(company_id, fy_end, director_id) %>%
        distinct() %>%
        group_by(company_id, fy_end) %>%
        summarize(num_directors = n())


equilar_w_permno <-
    equilar %>%
    inner_join(count_directors) %>%
    inner_join(
        director.co_fin %>%
            mutate(ncusip = substr(cusip, 1L, 8L)) %>%
            select(company_id, fy_end, ncusip)) %>%
    inner_join(factset.permnos) %>%
    select(-ncusip, -company_id) %>%
    rename(datadate = fy_end) %>%
    select(permno, datadate, everything()) %>%
    compute()

inst <-
    activist_director.inst %>%
    select(permno, datadate, inst)

controls <-
    compustat_w_permno %>%
    left_join(equilar_w_permno %>% mutate(on_equilar = TRUE)) %>%
    left_join(crsp) %>%
    left_join(crsp_m1) %>%
    left_join(staggered_board) %>%
    left_join(sharkrepellent) %>%
    left_join(ibes) %>%
    left_join(inst) %>%
    mutate(inst = coalesce(inst, 0),
           analyst = coalesce(analyst, 0),
           on_equilar = coalesce(on_equilar, FALSE)) %>%
    compute()

first_date <-
    activism_events %>%
    summarize(sql("min(eff_announce_date) - interval '1 year - 1 day'")) %>%
    pull() %>%
    as.Date()

last_date <-
    activism_events %>%
    summarize(max(eff_announce_date)) %>%
    pull() %>%
    as.Date()

rs <- dbGetQuery(pg, "DROP TABLE IF EXISTS activist_director.outcome_controls_new")

outcome_controls <-
    controls %>%
    filter(between(datadate, first_date, last_date)) %>%
    left_join(activism_events) %>%
    filter(between(eff_announce_date, datadate,
                   sql("datadate + interval '1 year - 1 day'"))) %>%
    mutate_at(vars(category, affiliated,
                   two_plus, early, big_investment, two_plus),
              funs(coalesce(., '_none'))) %>%
    mutate_at(vars(),
              funs(coalesce(., FALSE))) %>%
    mutate(category_activist_director = if_else(activist_director, 'activist_director',
            if_else(activism, 'non_activist_director', '_none'))) %>%
    compute(name = "outcome_controls_new", temporary = FALSE)

rs <- dbGetQuery(pg, "ALTER TABLE outcome_controls_new SET SCHEMA activist_director")

rs <- dbGetQuery(pg, "COMMENT ON TABLE activist_director.outcome_controls_new IS
    'CREATED USING create_outcome_controls.R'")

rs <- dbGetQuery(pg, "CREATE INDEX ON activist_director.outcome_controls_new (permno, datadate)")

rs <- dbGetQuery(pg, "ALTER TABLE activist_director.outcome_controls_new OWNER TO activism")