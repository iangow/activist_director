library(DBI)
library(dplyr)

# Get data from PostgreSQL
pg <- dbConnect(RPostgres::Postgres(), bigint = "integer")

rs <- dbExecute(pg, "SET search_path TO activist_director")
rs <- dbExecute(pg, "SET work_mem='3GB'")

dsedelist <- tbl(pg, sql("SELECT * FROM crsp.dsedelist"))
wrds_keydev <- tbl(pg, sql("SELECT * FROM ciq.wrds_keydev"))
ccmxpf_linktable <- tbl(pg, sql("SELECT * FROM crsp.ccmxpf_linktable"))
dsedist <- tbl(pg, sql("SELECT * FROM crsp.dsedist"))

dbExecute(pg, "DROP TABLE IF EXISTS delisting")

delisting <-
    dsedelist %>%
    select(permno, dlstdt, dlstcd) %>%
    mutate(delist = dlstcd > 100L,
           merger = between(dlstcd, 200L, 399L),
           failure = between(dlstcd, 520L, 599L)) %>%
    select(-dlstcd) %>%
    compute(name = "delisting", temporary = FALSE)

sql <- "ALTER TABLE delisting OWNER TO activism"
rs <- dbExecute(pg, sql)

sql <- paste0("COMMENT ON TABLE delisting IS
        'CREATED USING create_events_linked.R ON ",
              format(Sys.time(), "%Y-%m-%d %X %Z"), "';")
rs <- dbExecute(pg, sql)

permno_link <-
    ccmxpf_linktable %>%
    filter(usedflag=='1', linkprim %in% c('C', 'P')) %>%
    rename(permno = lpermno) %>%
    select(gvkey, permno, linkdt, linkenddt)

spinoff <-
    wrds_keydev %>%
    filter(keydeveventtypeid == 137L,
           keydevtoobjectroletypeid == 4L,
           !is.na(gvkey)) %>%
    select(gvkey, announcedate) %>%
    compute()

dbExecute(pg, "DROP TABLE IF EXISTS spinoff_linked")

spinoff_linked <-
    spinoff %>%
    inner_join(permno_link, by = "gvkey") %>%
    filter(announcedate >= linkdt,
           announcedate <= linkenddt | is.na(linkenddt)) %>%
    select(permno, announcedate) %>%
    mutate(year = date_part('year', announcedate)) %>%
    compute(name = "spinoff_linked", temporary = FALSE)

sql <- "ALTER TABLE spinoff_linked OWNER TO activism"
rs <- dbExecute(pg, sql)

sql <- paste0("COMMENT ON TABLE spinoff_linked IS
        'CREATED USING create_events_linked.R ON ",
              format(Sys.time(), "%Y-%m-%d %X %Z"), "';")
rs <- dbExecute(pg, sql)

dbExecute(pg, "DROP TABLE IF EXISTS spinoff_crsp")

spinoff_crsp <-
    dsedist %>%
    mutate(year = date_part('year', rcrddt),
           crsp_date = greatest(dclrdt, exdt, rcrddt, paydt)) %>%
    rename(new_permno = acperm) %>%
    full_join(spinoff_linked, by = c("permno", "year")) %>%
    mutate(date = coalesce(crsp_date, announcedate)) %>%
    select(permno, new_permno, date) %>%
    compute(name = "spinoff_crsp",
            temporary = FALSE)

sql <- "ALTER TABLE spinoff_crsp OWNER TO activism"
rs <- dbExecute(pg, sql)

sql <- paste0("COMMENT ON TABLE spinoff_crsp IS
        'CREATED USING create_events_linked.R ON ",
              format(Sys.time(), "%Y-%m-%d %X %Z"), "';")
rs <- dbExecute(pg, sql)

divestiture <-
    wrds_keydev %>%
    filter(keydeveventtypeid == 81L,
           keydevtoobjectroletypeid == 4L,
           !is.na(gvkey)) %>%
    select(gvkey, announcedate) %>%
    compute()

dbExecute(pg, "DROP TABLE IF EXISTS divestiture_linked")

divestiture_linked <-
    divestiture %>%
    inner_join(permno_link, by = "gvkey") %>%
    filter(announcedate >= linkdt,
           announcedate <= linkenddt | is.na(linkenddt)) %>%
    select(permno, announcedate) %>%
    mutate(year = date_part('year', announcedate)) %>%
    compute(name = "divestiture_linked",
            temporary = FALSE)

sql <- "ALTER TABLE divestiture_linked OWNER TO activism"
rs <- dbExecute(pg, sql)

sql <- paste0("COMMENT ON TABLE divestiture_linked IS
        'CREATED USING create_events_linked.R ON ",
              format(Sys.time(), "%Y-%m-%d %X %Z"), "';")
rs <- dbExecute(pg, sql)

acquisition <-
    wrds_keydev %>%
    filter(keydeveventtypeid == 81L,
           keydevtoobjectroletypeid == 3L,
           !is.na(gvkey)) %>%
    select(gvkey, announcedate) %>%
    compute()

dbExecute(pg, "DROP TABLE IF EXISTS acquisition_linked")

acquisition_linked <-
    acquisition %>%
    inner_join(permno_link, by = "gvkey") %>%
    filter(announcedate >= linkdt,
           announcedate <= linkenddt | is.na(linkenddt)) %>%
    select(permno, announcedate) %>%
    mutate(year = date_part('year', announcedate)) %>%
    compute(name = "acquisition_linked",
            temporary = FALSE)

sql <- "ALTER TABLE acquisition_linked OWNER TO activism"
rs <- dbExecute(pg, sql)

sql <- paste0("COMMENT ON TABLE acquisition_linked IS
        'CREATED USING create_events_linked.R ON ",
              format(Sys.time(), "%Y-%m-%d %X %Z"), "';")
rs <- dbExecute(pg, sql)

rs <- dbDisconnect(pg)
