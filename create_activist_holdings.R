library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

sql <- readLines("code/create_activist_holdings.sql")
system.time(rs <- dbGetQuery(pg, paste(sql, collapse="\n")))

sql <- paste("
  COMMENT ON TABLE activist_director.activist_holdings IS
    'CREATED USING create_activist_holdings.R ON ", Sys.time() , "';", sep="")
rs <- dbGetQuery(pg, paste(sql, collapse="\n"))

dbDisconnect(pg)
