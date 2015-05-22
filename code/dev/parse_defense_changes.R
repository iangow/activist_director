library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

sql <- paste0(readLines("code/dev/parse_defense_changes.sql"), collapse="\n")

defense_changes_raw <- dbGetQuery(pg, sql)
dbDisconnect(pg)

library("RJSONIO")
library("plyr")
# temp$items
defense_changes <-ldply(defense_changes_raw$items, fromJSON)
defense_changes$Date <- as.Date(defense_changes$Date, format='%m-%d-%Y')

