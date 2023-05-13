library(DBI)
library(dplyr, warn.conflicts = FALSE)
library(stargazer)

# Get data from database ----
pg <- dbConnect(RPostgres::Postgres())
rs <- dbExecute(pg, "SET work_mem = '3GB'")
rs <- dbExecute(pg, "SET search_path TO activist_director, risk")

risk.vavoteresults <- tbl(pg, "vavoteresults")
risk.issrec <- tbl(pg, "issrec")
director_names <- tbl(pg, "director_names")

issrec <-
    risk.issrec %>%
    select(itemonagendaid, issrec)

dbExecute(pg, "DROP TABLE IF EXISTS dirvoteresults")

dirvoteresults <-
    risk.vavoteresults %>%
    left_join(issrec, by = "itemonagendaid") %>%
    left_join(director_names %>% select(-name),
              by = "itemdesc") %>%
    mutate(itemonagendaid = as.integer(itemonagendaid)) %>%
    filter(issagendaitemid %in% c('S0299', 'M0299', 'M0201', 'S0201', 'M0225'),
           itemdesc %~% '^Elect',
           voteresult != 'Withdrawn',
           !(agendageneraldesc %ilike% '%inactive%'),
           !(votedfor %in% c(0L,1L) |
                 greatest(votedagainst, votedabstain, votedwithheld) %in% c(0L, 1L))) %>%
    mutate(issrec = issrec == "For") %>%
    compute(name = "dirvoteresults", temporary = FALSE)

dbExecute(pg, "ALTER TABLE dirvoteresults OWNER TO activism")

sql <- paste("
  COMMENT ON TABLE dirvoteresults IS
             'CREATED USING create_dirvoteresults.R ON ",
             format(Sys.time(), "%Y-%m-%d %X %Z"), "';", sep="")
rs <- dbExecute(pg, paste(sql, collapse="\n"))

rs <- dbDisconnect(pg)
