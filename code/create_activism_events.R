library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

# Now run SQL to get the other data (word counts, word share, lexical diversity)
sql <- paste(readLines("code/create_activism_events.sql"),
             collapse="\n")
rs <- dbGetQuery(pg, sql)

sql <- paste0("
    ALTER TABLE activist_director.activism_events OWNER TO activism;

    COMMENT ON TABLE activist_director.activism_events IS
        'CREATED USING create_activism_events.R ON ", Sys.time() , "';")

rs <- dbGetQuery(pg, sql)

# Get corrected data on board-related activism from Google Sheets document ----
library(googlesheets)

# As a one-time thing per user and machine, you will need to run gs_auth()
# to authorize googlesheets to access your Google Sheets.
gs <- gs_key("16Hmw7B1kzL5eIa3k7Jw5j-9RTsfspEB18r-wNfTRiYM")

event_fix <- gs_read(gs)

# Put data into PostgreSQL ----

rs <- dbWriteTable(pg, name=c("activist_director", "event_fix"), event_fix,
                   overwrite=TRUE, row.names=FALSE)
sql <- paste0("
    ALTER TABLE activist_director.event_fix OWNER TO activism;

    COMMENT ON TABLE activist_director.event_fix IS
        'CREATED USING create_activism_events.R ON ", Sys.time() , "';")

rs <- dbGetQuery(pg, sql)

cat("Original data:")
targeted_firms_mod <- dbGetQuery(pg, "
    SELECT *
    FROM activist_director.activism_events")

table(targeted_firms_mod$board_related, targeted_firms_mod$proxy_fight)

# Update relevant table ----

# TODO: Sean, we are implicitly using PERMNO and first_date as the key here
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
    WHERE b.campaign_id=ANY(a.campaign_ids);

    UPDATE activist_director.activism_events AS a
    SET proxy_fight=b.proxy_fight
    FROM activist_director.event_fix AS b
    WHERE b.campaign_id=ANY(a.campaign_ids);

    DROP TABLE activist_director.event_fix;")

# Check what the effect is of the changes above ----
cat("Modified data:")
targeted_firms_mod <- dbGetQuery(pg, "
    SELECT *
    FROM activist_director.activism_events")

table(targeted_firms_mod$board_related, targeted_firms_mod$proxy_fight)

rs <-dbDisconnect(pg)
