library(googlesheets4)
library(DBI)

gs <- as_sheets_id("1yGJtmSLy1hGT4Od1whGJB9SbghCEfpwjkrbsSwqMpAY")
missing_permnos <- read_sheet(gs, col_types = "cDccci")

pg <- dbConnect(RPostgres::Postgres())

rs <- dbExecute(pg, "SET search_path TO activist_director")

# Need to drop the view to replace the table it depends on
rs <- dbExecute(pg, "DROP TABLE IF EXISTS permnos CASCADE")
rs <- dbExecute(pg, "
  DROP TABLE IF EXISTS missing_permnos CASCADE")

rs <- dbWriteTable(pg, "missing_permnos", missing_permnos,
                   overwrite=TRUE, row.names=FALSE)
# Recreate the view
rs <- dbExecute(pg, "
  CREATE TABLE permnos AS
  SELECT DISTINCT permno::integer, ncusip
  FROM crsp.stocknames
  WHERE ncusip IS NOT NULL
  UNION
  SELECT DISTINCT permno, cusip AS ncusip
  FROM missing_permnos
  WHERE permno IS NOT NULL")

rs <- dbExecute(pg, "ALTER TABLE missing_permnos OWNER TO activism")
rs <- dbExecute(pg, "ALTER TABLE permnos OWNER TO activism")

dbDisconnect(pg)
