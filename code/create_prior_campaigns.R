library(dplyr, warn.conflicts = FALSE)
library(DBI)
pg <- dbConnect(RPostgres::Postgres(), bigint = "integer")

rs <- dbExecute(pg, "SET work_mem='8GB'")
rs <- dbExecute(pg, "SET search_path TO activist_director, factset")

sharkwatch <- tbl(pg, "activism_sample") %>% select(-sharkwatch50)
dissidents <- tbl(pg, "dissidents")

campaigns <-
    sharkwatch %>%
    inner_join(dissidents) %>%
    select(dissident, campaign_id, eff_announce_date) %>%
    rename(announce_date = eff_announce_date) %>%
    distinct()

recent_campaigns <-
    campaigns %>%
    inner_join(campaigns, by = "dissident") %>%
    filter(between(announce_date.y,
                   announce_date.x - sql("interval '1 year'"),
                   announce_date.x - sql("interval '1 day'"))) %>%
    group_by(dissident, announce_date.x) %>%
    summarize(recent_campaigns = n()) %>%
    rename(announce_date = announce_date.x)

recent_three_years <-
    campaigns %>%
    inner_join(campaigns, by = "dissident") %>%
    filter(between(announce_date.y,
                   announce_date.x - sql("interval '3 years'"),
                   announce_date.x - sql("interval '1 day'"))) %>%
    group_by(dissident, announce_date.x) %>%
    summarize(recent_three_years = n()) %>%
    rename(announce_date = announce_date.x)

all_campaigns <-
    campaigns %>%
    group_by(dissident) %>%
    arrange(announce_date) %>%
    mutate(prev_campaigns = row_number() - 1L)

rs <- dbExecute(pg, "DROP TABLE IF EXISTS prior_campaigns")

prior_campaigns <-
    all_campaigns %>%
    left_join(recent_campaigns, by = c("dissident", "announce_date")) %>%
    left_join(recent_three_years, by = c("dissident", "announce_date")) %>%
    compute() %>%
    rename(eff_announce_date = announce_date) %>%
    mutate(recent_campaigns = coalesce(recent_campaigns, 0),
           recent_dummy = coalesce(recent_campaigns > 2, FALSE),
           recent_three_dummy = recent_three_years > 5,
           prior_dummy = prev_campaigns > 6) %>%
    compute(name = "prior_campaigns", temporary = FALSE,
            index = "dissident")

rs <- dbExecute(pg, "ALTER TABLE prior_campaigns OWNER TO activism")

sql <- paste("
  COMMENT ON TABLE prior_campaigns IS
    'CREATED USING create_prior_campaigns.R ON ",
             format(Sys.time(), "%Y-%m-%d %X %Z"), "';", sep="")
rs <- dbExecute(pg, paste(sql, collapse="\n"))

rs <- dbDisconnect(pg)
