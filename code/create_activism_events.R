library(RPostgreSQL)
drv <- dbDriver("PostgreSQL")
pg <- dbConnect(drv, dbname="crsp")

sql <- paste("
  DROP VIEW IF EXISTS activist_director.permnos CASCADE;

  CREATE VIEW activist_director.permnos AS
  SELECT DISTINCT permno, ncusip
  FROM crsp.stocknames
  WHERE ncusip IS NOT NULL
  UNION
  SELECT DISTINCT permno, cusip AS ncusip
  FROM activism.missing_permnos
  WHERE permno IS NOT NULL;

  ALTER VIEW activist_director.permnos OWNER TO activism;

  COMMENT ON VIEW activist_director.permnos IS
    'CREATED USING create_activism_events.R ON ", Sys.time() , "';", sep="")

rs <- dbGetQuery(pg, sql)

# Now run SQL to get the other data (word counts, word share, lexical diversity)
sql <- paste(readLines("~/Dropbox/research/activism/activist_director/code/create_activism_events.sql"),
             collapse="\n")
rs <- dbGetQuery(pg, sql)

sql <- paste("
  COMMENT ON TABLE activist_director.activism_events IS
    'CREATED USING create_activism_events.R ON ", Sys.time() , "';", sep="")

rs <- dbGetQuery(pg, sql)

# Get corrected data on board-related activism from Google Sheets document ----
require(RCurl)
csv_file <- getURL(paste("https://docs.google.com/spreadsheet/pub?",
                         "key=0AtCJeBFBO_EddEdiYzZVVEI0d01nTTBkVWtqZ19QOFE",
                         "&single=true&gid=1&output=csv",
                         sep=""),
                   verbose=FALSE)
event_fix <- read.csv(textConnection(csv_file), as.is=TRUE)
event_fix$announce_date <- as.Date(event_fix$announce_date)
# Put data into PostgreSQL ----

rs <- dbWriteTable(pg, name=c("activist_director", "event_fix"), event_fix,
             overwrite=TRUE, row.names=FALSE)

cat("Original data:")
targeted_firms_mod <- dbGetQuery(pg, "
    SELECT *
    FROM activist_director.activism_events")

table(targeted_firms_mod$board_related, targeted_firms_mod$proxy_fight)

# Update relevant table ----

# IDG: Sean, we are implicitly using PERMNO and first_date as the key here
#      I guess we should make sure that there are no cases where there
#      are multiple dissident groups launching activism against a single firm
#      on the same date.
#      Also, are there other fields that need to be updated?
#      Fields that may need to be updated:
#          primary_campaign_type, targeted_firm_board_settled, activism_type,
#          non_proxy_board, proxy_fight

# holder_type on_defc went_the_distance dissident_group_ownership_percent

rs <- dbGetQuery(pg, "
    UPDATE activist_director.activism_events AS a
    SET board_related=b.board_related
    FROM activist_director.event_fix AS b
    WHERE a.cusip_9_digit=b.cusip_9_digit AND a.announce_date=b.announce_date
                 AND a.dissident_group=b.dissident_group;

    UPDATE activist_director.activism_events AS a
    SET proxy_fight=b.proxy_fight
    FROM activist_director.event_fix AS b
    WHERE a.cusip_9_digit=b.cusip_9_digit AND a.announce_date=b.announce_date
                 AND a.dissident_group=b.dissident_group;

    DROP TABLE activist_director.event_fix;")

# Check what the effect is of the changes above ----
cat("Modified data:")
targeted_firms_mod <- dbGetQuery(pg, "
    SELECT *
    FROM activist_director.activism_events")

table(targeted_firms_mod$board_related, targeted_firms_mod$proxy_fight)

