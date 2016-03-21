# Code to pull down data on PERMNOs that need to be manually matched to CUSIPs
# and put data into a view called activism.permnos.

# Get spreadsheet data from Google Docs
require(RCurl)
url <- "https://docs.google.com/spreadsheet/pub?key=0AvP4wvS7Nk-QdFlwZ0k4T3lFaHBNZm9MRnBjRDFhQlE&output=csv"
csv_file <- getURL(url, verbose=FALSE)
missing_permnos <- read.csv(textConnection(csv_file), as.is=TRUE)

# Add leading zeros to PERMNOs
#fixCUSIPs <- function(cusips) {
#    to.fix <- nchar(cusips) < 9 & nchar(cusips) > 0
#    cusips[to.fix] <- sprintf("%09d", as.integer(cusips[to.fix]))
#    return(cusips)
#}
#missing_permnos$cusip <- substr(fixCUSIPs(missing_permnos$cusip), 1, 8)
missing_permnos$permno <- as.integer(missing_permnos$permno)

# Put data into the database
library(RPostgreSQL)
drv <- dbDriver("PostgreSQL")
pg <- dbConnect(drv, dbname="crsp")

# Need to drop the view to replace the table it depends on
rs <- dbGetQuery(pg, "
  DROP VIEW IF EXISTS activist_director.permnos CASCADE")
rs <- dbGetQuery(pg, "
  DROP TABLE IF EXISTS activism.missing_permnos CASCADE")


rs <- dbWriteTable(pg, c("activist_director", "missing_permnos"), missing_permnos, overwrite=TRUE, row.names=FALSE)
# Recreate the view
rs <- dbGetQuery(pg, "
  CREATE VIEW activist_director.permnos AS
  SELECT DISTINCT permno::integer, ncusip
  FROM crsp.stocknames
  WHERE ncusip IS NOT NULL
  UNION
  SELECT DISTINCT permno, cusip AS ncusip
  FROM activism.missing_permnos
  WHERE permno IS NOT NULL")


rs <- dbGetQuery(pg, "

  SELECT DISTINCT permno, ncusip
  FROM crsp.stocknames
  WHERE ncusip IS NOT NULL")
