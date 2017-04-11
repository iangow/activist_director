# Import Dataset from Google Drive ----
library(googlesheets)
Sys.setenv(PGHOST = "iangow.me", PGDATABASE = "crsp")
pg <- src_postgres()
# As a one-time thing per user and machine, you will need to run gs_auth()
# to authorize googlesheets to access your Google Sheets.
gs <- gs_key("1zHSKIAx4LKURXav-k06D7T3p3St0VjFa8RXvAFJnUfI")

#### Sheet 1 ####
activist_directors_1 <- as.data.frame(gs_read(gs, ws = "activist_directors"))

# Fix variable names
names(activist_directors_1) <- gsub("\\.+", "_", tolower(names(activist_directors_1)))
names(activist_directors_1) <- gsub("_s_", "_", names(activist_directors_1))
names(activist_directors_1) <- gsub("_$", "", names(activist_directors_1))

# Clean up variables: clean up names
activist_directors_1$first_name <- gsub("\\n", "", activist_directors_1$first_name)
activist_directors_1$first_name <- gsub("\\s+$", "", activist_directors_1$first_name)

# Clean up variables: set to correct type
# activist_directors_1$issuer_cik <- as.integer(activist_directors_1$issuer_cik)
activist_directors_1$permno <- as.integer(activist_directors_1$permno)
activist_directors_1$cusip_9_digit <- gsub(pattern="^'+", "", activist_directors_1$cusip_9_digit)
activist_directors_1$announce_date <- as.Date(activist_directors_1$announce_date)
activist_directors_1$appointment_date <- as.Date(activist_directors_1$appointment_date)
activist_directors_1$retirement_date <- as.Date(activist_directors_1$retirement_date)
activist_directors_1$dissident_board_seats_wongranted_date <-
    as.Date(activist_directors_1$dissident_board_seats_wongranted_date)
# activist_directors_1$activist_affiliate <- !as.logical(activist_directors_1$independence)
activist_directors_1 <- subset(activist_directors_1,
                               subset=!is.na(appointment_date),
                               select=c(permno, cusip_9_digit, announce_date,
                                        dissident_group,
                                        dissident_board_seats_wongranted_date,
                                        dissident_board_seats_won,
                                        last_name, first_name,
                                        appointment_date,
                                        retirement_date, independent))

#### Sheet 2 ####
activist_directors_2 <- as.data.frame(gs_read(gs, ws = "2013-2015 + Extra"))

# Fix variable names
names(activist_directors_2) <- gsub("\\.+", "_", tolower(names(activist_directors_2)))
names(activist_directors_2) <- gsub("_s_", "_", names(activist_directors_2))
names(activist_directors_2) <- gsub("_$", "", names(activist_directors_2))

# Clean up variables: clean up names
activist_directors_2$first_name <- gsub("\\n", "", activist_directors_2$first_name)
activist_directors_2$first_name <- gsub("\\s+$", "", activist_directors_2$first_name)

# Clean up variables: set to correct type
# activist_directors_2$issuer_cik <- as.integer(activist_directors_2$issuer_cik)
activist_directors_2$permno <- as.integer(activist_directors_2$permno)
activist_directors_2$cusip_9_digit <- gsub(pattern="^'+", "", activist_directors_2$cusip_9_digit)
activist_directors_2$announce_date <- as.Date(activist_directors_2$announce_date)
activist_directors_2$appointment_date <- as.Date(activist_directors_2$appointment_date)
activist_directors_2$retirement_date <- as.Date(activist_directors_2$retirement_date)
activist_directors_2$dissident_board_seats_wongranted_date <-
    as.Date(activist_directors_2$dissident_board_seats_wongranted_date)
# activist_directors_2$activist_affiliate <- !as.logical(activist_directors_2$independence)
activist_directors_2 <- subset(activist_directors_2,
                               subset=!is.na(appointment_date),
                               select=c(permno, cusip_9_digit, announce_date,
                                        dissident_group,
                                        dissident_board_seats_wongranted_date,
                                        dissident_board_seats_won,
                                        last_name, first_name,
                                        appointment_date,
                                        retirement_date, independent))


#### Sheet 3 ####
activist_directors_3 <- as.data.frame(gs_read(gs, ws = "Extra2"))

# Fix variable names
names(activist_directors_3) <- gsub("\\.+", "_", tolower(names(activist_directors_3)))
names(activist_directors_3) <- gsub("_s_", "_", names(activist_directors_3))
names(activist_directors_3) <- gsub("_$", "", names(activist_directors_3))

# Clean up variables: clean up names
activist_directors_3$first_name <- gsub("\\n", "", activist_directors_3$first_name)
activist_directors_3$first_name <- gsub("\\s+$", "", activist_directors_3$first_name)

# Clean up variables: set to correct type
# activist_directors_3$issuer_cik <- as.integer(activist_directors_3$issuer_cik)
activist_directors_3$permno <- as.integer(activist_directors_3$permno)
activist_directors_3$eff_announce_date <- as.Date(activist_directors_3$eff_announce_date)
activist_directors_3$appointment_date <- as.Date(activist_directors_3$appointment_date)
activist_directors_3$retirement_date <- as.Date(activist_directors_3$retirement_date)
activist_directors_3$dissident_board_seats_wongranted_date <-
    as.Date(activist_directors_3$dissident_board_seats_wongranted_date)
# activist_directors_3$activist_affiliate <- !as.logical(activist_directors_3$independence)
activist_directors_3 <- subset(activist_directors_3,
                               subset=!is.na(appointment_date),
                               select=c(permno, eff_announce_date,
                                        dissident_group,
                                        dissident_board_seats_wongranted_date,
                                        dissident_board_seats_won,
                                        last_name, first_name,
                                        appointment_date,
                                        retirement_date, independent))

# Export dataset to PostgreSQL (activist_director.activist_directors) ----
library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

rs <- dbWriteTable(pg, c("activist_director", "activist_directors_1"),
                   activist_directors_1, overwrite=TRUE, row.names=FALSE)

rs <- dbWriteTable(pg, c("activist_director", "activist_directors_2"),
                   activist_directors_2, overwrite=TRUE, row.names=FALSE)

rs <- dbWriteTable(pg, c("activist_director", "activist_directors_3"),
                   activist_directors_3, overwrite=TRUE, row.names=FALSE)

# rs <- dbGetQuery(pg, "CREATE ROLE activism")

rs <- dbGetQuery(pg, "
                 SET work_mem='8GB';

                 DROP TABLE IF EXISTS activist_director.activist_directors;

                 CREATE TABLE activist_director.activist_directors AS

                 WITH activist_director_1 AS (
                 SELECT DISTINCT d.permno, c.dissident_group,
                 least(c.announce_date, c.date_original_13d_filed) AS eff_announce_date,
                 first_name, last_name, appointment_date, retirement_date, independent, 1 AS source
                 FROM activist_director.activist_directors_1 AS a
                 LEFT JOIN factset.campaign_ids AS b
                 ON a.cusip_9_digit=b.cusip_9_digit AND a.dissident_group=b.dissident_group AND a.announce_date=b.announce_date
                 LEFT JOIN factset.sharkwatch_new AS c
                 ON b.campaign_id=c.campaign_id
                 INNER JOIN factset.permnos AS d
                 ON substr(c.cusip_9_digit,1,8)=d.ncusip
                 ORDER BY d.permno, dissident_group, eff_announce_date),
                 --944 813

                 activist_director_2 AS (
                 SELECT DISTINCT a.permno, COALESCE(c.dissident_group, d.dissident_group) AS dissident_group,
                 least(COALESCE(c.announce_date,d.announce_date), COALESCE(c.date_original_13d_filed,d.date_original_13d_filed)) AS eff_announce_date,
                 first_name, last_name, appointment_date, retirement_date, independent, 2 AS source
                 FROM activist_director.activist_directors_2 AS a
                 LEFT JOIN factset.campaign_ids AS b
                 ON a.cusip_9_digit=b.cusip_9_digit AND a.dissident_group=b.dissident_group AND a.announce_date=b.announce_date
                 LEFT JOIN factset.sharkwatch_new AS c
                 ON b.campaign_id=c.campaign_id
                 LEFT JOIN factset.sharkwatch_new AS d
                 ON a.cusip_9_digit=d.cusip_9_digit AND a.dissident_group=d.dissident_group AND a.announce_date=d.announce_date
                 ORDER BY permno, dissident_group, eff_announce_date),
                 --627 538

                 activist_director_3 AS (
                 SELECT DISTINCT permno, dissident_group, eff_announce_date,
                 first_name, last_name, appointment_date, retirement_date, independent, 3 AS source
                 FROM activist_director.activist_directors_3 AS a
                 ORDER BY permno, dissident_group, eff_announce_date),
                 --68 65

                 activist_directors AS (
                 SELECT DISTINCT a.permno, a.dissident_group, a.eff_announce_date,
                 first_name, last_name, appointment_date, retirement_date, independent --, source
                 FROM activist_director.activism_sample AS a
                 INNER JOIN activist_director_1 AS b
                 ON a.permno=b.permno AND a.dissident_group=b.dissident_group AND a.eff_announce_date=b.eff_announce_date

                 UNION

                 SELECT DISTINCT a.permno, a.dissident_group, a.eff_announce_date,
                 first_name, last_name, appointment_date, retirement_date, independent --, source
                 FROM activist_director.activism_sample AS a
                 INNER JOIN activist_director_2 AS b
                 ON a.permno=b.permno AND a.dissident_group=b.dissident_group AND a.eff_announce_date=b.eff_announce_date

                 UNION

                 SELECT DISTINCT a.permno, a.dissident_group, a.eff_announce_date,
                 first_name, last_name, appointment_date, retirement_date, independent --, source
                 FROM activist_director.activism_sample AS a
                 INNER JOIN activist_director_3 AS b
                 ON a.permno=b.permno AND a.dissident_group=b.dissident_group AND a.eff_announce_date=b.eff_announce_date
                 ORDER BY permno, dissident_group, eff_announce_date),

                 finals AS (
                 SELECT DISTINCT a.permno, dissident_group, eff_announce_date, first_name, last_name,
                 appointment_date, LEAST(retirement_date, dlstdt) AS retirement_date, independent
                 FROM activist_directors AS a
                 LEFT JOIN crsp.dsedelist AS b
                 ON a.permno=b.permno AND dlstcd!=100
                 WHERE appointment_date < LEAST(retirement_date, dlstdt) OR LEAST(retirement_date, dlstdt) IS NULL
                 --WHERE appointment_date >= LEAST(RETIREMENT_DATE, DLSTDT)
                 ORDER BY permno, dissident_group, eff_announce_date)

                 SELECT *
                 FROM finals
                 ")

rs <- dbWriteTable(pg, c("activist_director", "activist_directors"),
                   activist_directors, overwrite=TRUE, row.names=FALSE)

rs <- dbGetQuery(pg, "ALTER TABLE activist_director.activist_directors OWNER TO activism")

rs <- dbGetQuery(pg, "VACUUM activist_director.activist_directors")

sql <- paste0("
              COMMENT ON TABLE activist_director.activist_directors IS
              'CREATED USING import_activist_directors.R ON ", Sys.time() , "';")

rs <- dbGetQuery(pg, sql)
rs <- dbDisconnect(pg)
