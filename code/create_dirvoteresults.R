library(DBI)
library(dplyr, warn.conflicts = FALSE)
library(stargazer)

# Get data from database ----
pg <- dbConnect(RPostgres::Postgres())
rs <- dbExecute(pg, "SET work_mem = '3GB'")
rs <- dbExecute(pg, "SET search_path TO activist_director, risk")

risk.vavoteresults <- tbl(pg, "vavoteresults")
risk.issrec <- tbl(pg, "issrec")

dirvoteresults <-
    risk.vavoteresults %>%
    left_join(risk.issrec) %>%
    mutate(itemonagendaid = as.integer(itemonagendaid)) %>%
    filter(issagendaitemid %in% c('S0299', 'M0299', 'M0201', 'S0201', 'M0225'),
           itemdesc %~% '^Elect',
           voteresult != 'Withdrawn',
           !(agendageneraldesc %ilike% '%inactive%'),
           !(votedfor %in% c(0L,1L) |
                 greatest(votedagainst, votedabstain, votedwithheld) %in% c(0L, 1L))) %>%
    mutate(last_name = sql("(extract_name(itemdesc)).last_name"),
           first_name = sql("(extract_name(itemdesc)).first_name"),
           issrec = issrec == "For") %>%
    compute(name = "dirvoteresults", temporary=FALSE)

dbExecute(pg, "ALTER TABLE dirvoteresults OWNER TO activism")

sql <- paste("
  COMMENT ON TABLE dirvoteresults IS
             'CREATED USING create_dirvoteresults.R ON ",
             format(Sys.time(), "%Y-%m-%d %X %Z"), "';", sep="")
rs <- dbExecute(pg, paste(sql, collapse="\n"))

rs <- dbDisconnect(pg)
