library(dplyr, warn.conflicts = FALSE)
library(DBI)
pg <- dbConnect(RPostgres::Postgres(), bigint = "integer")

rs <- dbExecute(pg, "SET work_mem='8GB'")
rs <- dbExecute(pg, "SET search_path TO activist_director, factset")

rs <- dbExecute(pg, "SET search_path TO factset")

sharkwatch <- tbl(pg, "sharkwatch")
dissidents <- tbl(pg, "dissidents")

dbExecute(pg, "DROP TABLE IF EXISTS prior_campaigns")
prior_campaigns <-
    sharkwatch %>%
    inner_join(dissidents) %>%
    select(dissident, campaign_id, announce_date) %>%
    distinct() %>%
    group_by(dissident) %>%
    arrange(announce_date) %>%
    mutate(prev_campaigns = row_number() - 1L) %>%
    compute(name = "prior_campaigns", temporary = FALSE,
            index = "dissident")

rs <- dbExecute(pg, "ALTER TABLE prior_campaigns OWNER TO activism")

sql <- paste("
  COMMENT ON TABLE prior_campaigns IS
    'CREATED USING create_prior_campaigns.R ON ",
             format(Sys.time(), "%Y-%m-%d %X %Z"), "';", sep="")
rs <- dbExecute(pg, paste(sql, collapse="\n"))

rs <- dbDisconnect(pg)
