# Get corrected data on board-related activism from Google Sheets document ----
require(RCurl)
csv_file <- getURL(paste0("https://docs.google.com/spreadsheet/pub?",
                         "key=0AuGYuDecQAVTdEc5WmhEWVY1ZWF1cjlxVFJEaHRzUFE",
                         "&output=csv"),
                   verbose=FALSE)
manual_names <- read.csv(textConnection(csv_file), as.is=TRUE)

for (i in names(manual_names)) class(manual_names[,i]) <- "character"

library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

rs <- dbWriteTable(pg, name=c("issvoting", "manual_names"), manual_names,
                   overwrite=TRUE, row.names=FALSE)

rs <- dbGetQuery(pg, "ALTER TABLE issvoting.manual_names OWNER TO activism")

dbDisconnect(pg)

