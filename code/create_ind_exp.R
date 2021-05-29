library(DBI)
library(dplyr, warn.conflicts = FALSE)
pg <- dbConnect(RPostgres::Postgres(), bigint = "integer")

rs <- dbExecute(pg, "SET work_mem='8GB'")
rs <- dbExecute(pg, "SET search_path TO activist_director")

stocknames <- tbl(pg, sql("SELECT * FROM crsp.stocknames"))
activist_directors <- tbl(pg, "activist_directors")
activist_director_equilar <- tbl(pg, "activist_director_equilar")
equilar_w_activism <- tbl(pg, "equilar_w_activism")

# Bring in SIC code ----
sics <-
    stocknames %>%
    select(permno, siccd, namedt, nameenddt) %>%
    mutate(siccd = substr(as.character(siccd), 1, 2)) %>%
    distinct() %>%
    arrange(permno, namedt)

# Match Equilar company_id with SIC code ----
equilar_sics <-

start_dates <-
    equilar_w_activism %>%
    group_by(company_id, executive_id) %>%
    summarize(date_start = max(date_start, na.rm = TRUE),
              .groups = "drop") %>%
    compute()

equilar_sic_raw <-
    equilar_w_activism %>%
    select(company_id, period, permno) %>%
    distinct() %>%
    inner_join(sics, by = "permno") %>%
    filter(period >= namedt, period <= nameenddt) %>%
    select(-permno, -namedt, -nameenddt) %>%
    compute()

equilar_sic_windows <-
    equilar_sic_raw %>%
    group_by(company_id) %>%
    window_order(period) %>%
    mutate(new_window = is.na(lag(siccd)) || lag(siccd) != siccd,
           window = cumsum(as.integer(new_window))) %>%
    group_by(company_id, siccd, window) %>%
    summarize(start_period = min(period, na.rm = TRUE),
              end_period = max(period, na.rm = TRUE),
              .groups = "drop") %>%
    select(-window) %>%
    compute()

equilar_sic_first <-
    equilar_sic_windows %>%
    group_by(company_id) %>%
    filter(start_period == min(start_period))

# Very first year for each executive-company ID ----
first_years_a <-
    start_dates %>%
    inner_join(equilar_sic_windows, by = "company_id") %>%
    filter(between(date_start, start_period, end_period))

first_years_b <-
    start_dates %>%
    anti_join(first_years_a,
              by = c("company_id", "executive_id", "date_start")) %>%
    inner_join(equilar_sic_first, by = "company_id")

first_years <-
    first_years_a %>%
    union_all(first_years_b) %>%
    select(executive_id, company_id, siccd, date_start) %>%
    compute()

# Create a dummy "same_sic2"----
prior_appts <-
    first_years %>%
    left_join(first_years, by = c("executive_id"),
               suffix = c("_own", "_other")) %>%
    filter(company_id_own != company_id_other,
           date_start_other < date_start_own)  %>%
    mutate(same_sic2 = siccd_own == siccd_other) %>%
    filter(date_start_own >= '2004-01-01') %>%
    group_by(executive_id, company_id_own) %>%
    summarize(prior_ind_exp = sum(as.integer(same_sic2)),
              .groups = "drop") %>%
    compute()

rs <- dbExecute(pg, "DROP TABLE IF EXISTS ind_exp")

# Identify activist director cases using activist_director_equilar----
ind_exp <-
    prior_appts %>%
    rename(company_id = company_id_own) %>%
    left_join(activist_director_equilar,
              by = c("executive_id", "company_id")) %>%
    left_join(activist_directors,
              by = c("campaign_id", "first_name", "last_name")) %>%
    mutate(activist_director = !is.na(independent),
           affiliated_director = case_when(!activist_director ~ "_na",
                                           !independent ~ "affiliated",
                                           independent ~ "unaffiliated")) %>%
    select(company_id, executive_id, activist_director,
           affiliated_director, prior_ind_exp) %>%
    distinct() %>%
    compute(name = "ind_exp", temporary = FALSE)

rs <- dbExecute(pg, "ALTER TABLE ind_exp OWNER TO activism;")

sql <- paste("
             COMMENT ON TABLE ind_exp IS
             'CREATED USING create_ind_exp.R ON ",
             format(Sys.time(), "%Y-%m-%d %X %Z"), "';", sep="")
rs <- dbExecute(pg, paste(sql, collapse="\n"))



prior_appts %>%
    count(prior_ind_exp)

ind_exp %>%
    group_by(activist_director) %>%
    summarise(mean(prior_ind_exp, na.rm = TRUE))

ind_exp %>%
    group_by(affiliated_director) %>%
    summarise(mean(prior_ind_exp, na.rm = TRUE))

final <- ind_exp %>% collect()

rs <- dbDisconnect(pg)

table(final$prior_ind_exp, final$activist_director)

table(final$prior_ind_exp, final$affiliated_director)

t.test(subset(final,activist_director)$prior_ind_exp, subset(final,!activist_director)$prior_ind_exp)

t.test(subset(final,affiliated_director=="affiliated")$prior_ind_exp, subset(final,affiliated_director=="_na")$prior_ind_exp)

t.test(subset(final,affiliated_director=="unaffiliated")$prior_ind_exp, subset(final,affiliated_director=="_na")$prior_ind_exp)

t.test(subset(final,affiliated_director=="unaffiliated")$prior_ind_exp, subset(final,affiliated_director=="affiliated")$prior_ind_exp)


