library(dplyr, warn.conflicts = FALSE)
library(dbplyr, warn.conflicts = FALSE)
library(DBI)

# PostgreSQL Connection
pg <- dbConnect(RPostgres::Postgres())
rs <- dbExecute(pg, "SET search_path TO activist_director, public")
rs <- dbExecute(pg, "SET work_mem = '8GB'")

# Get data from activist director tables ----
activism_events <- tbl(pg, "activism_events")
funda <- tbl(pg, sql("SELECT * FROM comp.funda"))
names <- tbl(pg, sql("SELECT * FROM comp.names"))
ccmxpf_linktable <- tbl(pg, sql("SELECT * FROM crsp.ccmxpf_linktable"))
msf <- tbl(pg, sql("SELECT * FROM crsp.msf"))

founding_year <-
    msf %>%
    filter(!is.na(ret)) %>%
    group_by(permno) %>%
    summarize(date = min(date, na.rm = TRUE)) %>%
    mutate(founding_year = date_part('year', date)) %>%
    ungroup() %>%
    select(permno, founding_year) %>%
    compute()

act_events <-
    activism_events %>%
    mutate(fyear = if_else(month(eff_announce_date) <= 5, year(eff_announce_date) - 1,
                           year(eff_announce_date))) %>%
    mutate(fyear = as.integer(fyear) + 1L) %>%
    select(permno, fyear) %>%
    distinct() %>%
    mutate(activism = TRUE) %>%
    compute()

activist_director_events <-
    activism_events %>%
    filter(!is.na(first_appointment_date)) %>%
    mutate(fyear = if_else(month(eff_announce_date) <= 5, year(eff_announce_date) - 1,
                           year(eff_announce_date))) %>%
    mutate(fyear = as.integer(fyear) + 1L) %>%
    select(permno, fyear) %>%
    distinct() %>%
    mutate(activist_director = TRUE) %>%
    compute()

affiliated_director_events <-
    activism_events %>%
    filter(affiliated=='affiliated') %>%
    mutate(fyear = if_else(month(eff_announce_date) <= 5, year(eff_announce_date) - 1,
                           year(eff_announce_date))) %>%
    mutate(fyear = as.integer(fyear) + 1L) %>%
    select(permno, fyear) %>%
    distinct() %>%
    mutate(affiliated_director = TRUE) %>%
    compute()

min_year <-
    act_events %>%
    summarize(min_year = as.integer(min(fyear, na.rm = TRUE)) - 3L) %>%
    pull()

funda_mod <-
    funda %>%
    filter(indfmt=='INDL', consol=='C', popsrc=='D', datafmt=='STD') %>%
    filter(fyear >= min_year)

sic_codes <-
    funda_mod %>%
    select(gvkey, fyear) %>%
    inner_join(names,  by = "gvkey") %>%
    filter(between(fyear, year1, year2)) %>%
    mutate(sic2 = substr(sic, 1L, 2L), sic3 = substr( sic, 1L, 3L)) %>%
    select(gvkey, fyear, sic2, sic3) %>%
    compute()

compustat <-
    funda_mod %>%
    group_by(gvkey) %>%
    window_order(fyear) %>%
    mutate(log_at = if_else(at > 0, log(at), NA),
           bv = if_else(ceq > 0, log(ceq), NA),
           log_sale = if_else(sale > 0, log(sale), NA),
           mv = if_else(prcc_f * csho > 0, log(prcc_f * csho), NA),
           roa = if_else(lag(at)  > 0,  oibdp/lag(at), NA),
           tobins_q = if_else(ceq > 0 & prcc_f * csho > 0 & dlc + dltt >= 0,
                              (prcc_f * csho + dlc + dltt) /
                                  (ceq + dlc + dltt), NA)) %>%
    select(gvkey, fyear, datadate, log_at, log_sale,
           bv, log_sale, mv, roa, tobins_q) %>%
    ungroup() %>%
    compute()

compustat_mod <-
    compustat %>%
    left_join(sic_codes, by = c("gvkey", "fyear"))

industry_median_roa <-
    compustat_mod %>%
    filter(!is.na(roa)) %>%
    group_by(fyear, sic2) %>%
    summarize(roa_median = median(roa), .groups = "drop") %>%
    compute()

industry_median_tobins_q <-
    compustat_mod %>%
    filter(!is.na(tobins_q)) %>%
    group_by(fyear, sic2) %>%
    summarize(tobins_q_median = median(tobins_q), .groups = "drop") %>%
    compute()

industry_adjusted <-
    compustat_mod %>%
    left_join(industry_median_roa, by = c("fyear", "sic2")) %>%
    left_join(industry_median_tobins_q, by = c("fyear", "sic2")) %>%
    mutate(roa_ind_adj = roa - roa_median,
           tobins_q_ind_adj = tobins_q - tobins_q_median) %>%
    select(-matches("median")) %>%
    compute()

permnos <-
    funda_mod %>%
    select(gvkey, datadate) %>%
    inner_join(ccmxpf_linktable, by = "gvkey") %>%
    rename(permno = lpermno) %>%
    filter(usedflag=='1',
           linkprim %in% c('C', 'P'),
           datadate >= linkdt,
           datadate <= linkenddt | is.na(linkenddt)) %>%
    select(gvkey, datadate, permno) %>%
    distinct() %>%
    compute()

roa_q <-
    industry_adjusted %>%
    inner_join(permnos, by = c("gvkey", "datadate")) %>%
    compute()

dummies <-
    roa_q %>%
    select(permno, fyear) %>%
    distinct() %>%
    left_join(act_events, by = c("fyear", "permno")) %>%
    left_join(activist_director_events, by = c("fyear", "permno")) %>%
    left_join(affiliated_director_events, by = c("fyear", "permno")) %>%
    mutate(activism = coalesce(activism, FALSE),
           activist_director = coalesce(activist_director, FALSE),
           affiliated_director = coalesce(affiliated_director, FALSE)) %>%
    ungroup() %>%
    group_by(permno) %>%
    window_order(permno, fyear) %>%
    mutate(year_m1 = lead(activism, 1L),
           year_m2 = lead(activism, 2L),
           year_m3 = lead(activism, 3L),
           year_p0 = lag(activism, 0L),
           year_p1 = lag(activism, 1L),
           year_p2 = lag(activism, 2L),
           year_p3 = lag(activism, 3L),
           year_p4 = lag(activism, 4L),
           year_p5 = lag(activism, 5L),

           year_ad_m1 = lead(activist_director, 1L),
           year_ad_m2 = lead(activist_director, 2L),
           year_ad_m3 = lead(activist_director, 3L),
           year_ad_p0 = lag(activist_director, 0L),
           year_ad_p1 = lag(activist_director, 1L),
           year_ad_p2 = lag(activist_director, 2L),
           year_ad_p3 = lag(activist_director, 3L),
           year_ad_p4 = lag(activist_director, 4L),
           year_ad_p5 = lag(activist_director, 5L),

           year_nad_m1  = year_m1 & !year_ad_m1,
           year_nad_m2  = year_m2 & !year_ad_m2,
           year_nad_m3  = year_m3 & !year_ad_m3,
           year_nad_p0  = year_p0 & !year_ad_p0,
           year_nad_p1  = year_p1 & !year_ad_p1,
           year_nad_p2  = year_p2 & !year_ad_p2,
           year_nad_p3  = year_p3 & !year_ad_p3,
           year_nad_p4  = year_p4 & !year_ad_p4,
           year_nad_p5  = year_p5 & !year_ad_p5,

           year_aff_m1 = lead(affiliated_director, 1L),
           year_aff_m2 = lead(affiliated_director, 2L),
           year_aff_m3 = lead(affiliated_director, 3L),
           year_aff_p0 = lag(affiliated_director, 0L),
           year_aff_p1 = lag(affiliated_director, 1L),
           year_aff_p2 = lag(affiliated_director, 2L),
           year_aff_p3 = lag(affiliated_director, 3L),
           year_aff_p4 = lag(affiliated_director, 4L),
           year_aff_p5 = lag(affiliated_director, 5L),

           year_naff_m1  = year_m1 & year_ad_m1 & !year_aff_m1,
           year_naff_m2  = year_m2 & year_ad_m2 & !year_aff_m2,
           year_naff_m3  = year_m3 & year_ad_m3 & !year_aff_m3,
           year_naff_p0  = year_p0 & year_ad_p0 & !year_aff_p0,
           year_naff_p1  = year_p1 & year_ad_p1 & !year_aff_p1,
           year_naff_p2  = year_p2 & year_ad_p2 & !year_aff_p2,
           year_naff_p3  = year_p3 & year_ad_p3 & !year_aff_p3,
           year_naff_p4  = year_p4 & year_ad_p4 & !year_aff_p4,
           year_naff_p5  = year_p5 & year_ad_p5 & !year_aff_p5)

win_01 <- function(x) psych::winsor(x, trim = 0.01, na.rm = TRUE)

sw <-
    roa_q %>%
    left_join(dummies, by = c("fyear", "permno")) %>%
    left_join(founding_year, by = "permno") %>%
    mutate(age = if_else(fyear - founding_year >= 0,
                         log(1 + fyear - founding_year), NA)) %>%
    mutate_at(vars(matches("year_")), as.integer) %>%
    collect() %>%
    mutate_at(vars("tobins_q", "roa"), win_01) %>%
    copy_to(pg, ., name = "roa_data",
            temporary = FALSE, overwrite = TRUE)

sql <- "ALTER TABLE roa_data OWNER TO activism"

rs <- dbExecute(pg, sql)

sql <- paste0("COMMENT ON TABLE roa_data IS
        'CREATED USING create_roa_datas.R ON ",
              format(Sys.time(), "%Y-%m-%d %X %Z"), "';")

rs <- dbExecute(pg, sql)

rs <- dbDisconnect(pg)
