# Code to pull down data on PERMNOs that need to be manually matched to CUSIPs
# and put data into a view called activism.permnos.

# Get spreadsheet data from Google Docs
library(googlesheets)
gs <- gs_key("1yGJtmSLy1hGT4Od1whGJB9SbghCEfpwjkrbsSwqMpAY")
missing_permnos <-
    gs_read(gs)

# Put data into the database
library(RPostgreSQL)

pg <- dbConnect(PostgreSQL())

# Need to drop the view to replace the table it depends on
rs <- dbGetQuery(pg, "DROP VIEW IF EXISTS factset.permnos CASCADE")

rs <- dbWriteTable(pg, c("factset", "missing_permnos"),
                   missing_permnos, overwrite=TRUE, row.names=FALSE)

# Recreate the view
rs <- dbGetQuery(pg, "
  CREATE VIEW factset.permnos AS
  SELECT DISTINCT permno::integer, ncusip
  FROM crsp.stocknames
  WHERE ncusip IS NOT NULL
  UNION
  SELECT DISTINCT permno, cusip AS ncusip
  FROM factset.missing_permnos
  WHERE permno IS NOT NULL")
