## PostgreSQL Connection
library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

data.path <- "~/Dropbox/research/activism/activist_director/data/"
# Add Distribution Data to PostgreSQL
# dsedist <- read.csv("~/Dropbox/research/activism/activist_director/data/dsedistbn.csv.gz")
# names(dsedist) <- tolower(names(dsedist))
# dsedist$dclrdt <- as.Date(as.character(dsedist$dclrdt), "%Y%m%d")
# dsedist$exdt <- as.Date(as.character(dsedist$exdt), "%Y%m%d")
# dsedist$rcrddt <- as.Date(as.character(dsedist$rcrddt), "%Y%m%d")
# dsedist$paydt <- as.Date(as.character(dsedist$paydt), "%Y%m%d")
# rs <- dbGetQuery(pg, "DROP TABLE IF EXISTS activist_director.dsedist")
# rs <- dbWriteTable(pg, c("activist_director", "dsedist"), dsedist, row.names=FALSE)

# Spinoff Data from CRSP
# Add Spin-Off Data to PostgreSQL
spinoff <- read.csv("~/Dropbox/research/activism/activist_director/data/spinoff.csv")
spinoff$dclrdt <- as.Date(spinoff$dclrdt, "%d%b%Y")
spinoff$exdt <- as.Date(spinoff$exdt, "%d%b%Y")
spinoff$rcrddt <- as.Date(spinoff$rcrddt, "%d%b%Y")
spinoff$paydt <- as.Date(spinoff$paydt, "%d%b%Y")
rs <- dbWriteTable(pg, c("activist_director", "spinoff"), spinoff,
                   row.names=FALSE, overwrite=TRUE)
rs <- dbGetQuery(pg, "ALTER TABLE activist_director.spinoff OWNER TO activism")

# Spinoff Data from Capital IQ - Transactions (Spinoff)
spinoff_ciq <- read.csv(file.path(data.path, "spinoff_ciq.csv"),
                             stringsAsFactors=FALSE)

names(spinoff_ciq) <- tolower(names(spinoff_ciq))
names(spinoff_ciq) <- gsub("\\.+", "_", names(spinoff_ciq))
names(spinoff_ciq) <- gsub("^target_issuer_ltm_financials_", "", names(spinoff_ciq))
names(spinoff_ciq) <- gsub("_$", "", names(spinoff_ciq))

names(spinoff_ciq) <- gsub("_usdmm_historical_rate_$", "", names(spinoff_ciq))
spinoff_ciq$date <- spinoff_ciq$spin.off.split.off.closed.date
spinoff_ciq$cusip <- substr(spinoff_ciq$primary_isin_sellers,3,10)
spinoff_ciq$new_cusip <- substr(spinoff_ciq$primary_isin_target_issuer,3,10)
spinoff_ciq$date <- as.Date(spinoff_ciq$spin_off_split_off_closed_date, "%m/%d/%Y")

rs <- dbWriteTable(pg, c("activist_director", "spinoff_ciq"), spinoff_ciq,
                   row.names=FALSE, overwrite=TRUE)
rs <- dbGetQuery(pg, "ALTER TABLE activist_director.spinoff_ciq OWNER TO activism")

# Divestiture Data from Capital IQ - Transactions (M&A - Divestiture)
# Modified divestiture_ciq.xls and only kept isin, closed date and value
divestiture_ciq <- read.csv(file.path(data.path, "divestiture_ciq.csv"),
                             stringsAsFactors=FALSE)
names(divestiture_ciq) <- tolower(names(divestiture_ciq))
divestiture_ciq$date <- as.Date(divestiture_ciq$date, "%Y-%m-%d")
divestiture_ciq$cusip <- substr(divestiture_ciq$isin,3,10)

#divestiture_ciq$date <- divestiture_ciq$date
#divestiture_ciq$date <- as.Date(divestiture_ciq$all.transactions.closed.date, "%m/%d/%y")
#divestiture_ciq$value <- divestiture_ciq$total.transaction.value...usdmm..historical.rate.
#divestiture_ciq$value <- ifelse(divestiture_ciq$value=="-","",divestiture_ciq$value)
divestiture_ciq$value <- as.numeric(as.character(divestiture_ciq$value))
#rs <- dbGetQuery(pg, "DROP TABLE IF EXISTS activist_director.divestiture_ciq")
rs <- dbWriteTable(pg, c("activist_director", "divestiture_ciq"), divestiture_ciq,
                   row.names=FALSE, overwrite=TRUE)
rs <- dbGetQuery(pg, "ALTER TABLE activist_director.divestiture_ciq OWNER TO activism")

# Acquisition Data from Capital IQ - Transactions (M&A - Acquisition of Majority Stake)
# Modified acquisitions_ciq.xls and only kept isin, closed date and value
acquisition_ciq <-  read.csv(file.path(data.path, "acquisition_ciq.csv"),
                             stringsAsFactors=FALSE)

names(acquisition_ciq) <- tolower(names(acquisition_ciq))
names(acquisition_ciq) <- gsub("^x_", "", names(acquisition_ciq))
acquisition_ciq$date <- as.Date(acquisition_ciq$date, "%Y-%m-%d")
is.cusip <- grepl("^US", acquisition_ciq$isin)
acquisition_ciq$cusip[is.cusip] <- substr(acquisition_ciq$isin[is.cusip],3,10)
acquisition_ciq$value <- as.numeric(as.character(acquisition_ciq$value))

rs <- dbWriteTable(pg, c("activist_director", "acquisition_ciq"), acquisition_ciq,
                   row.names=FALSE, overwrite=TRUE)
rs <- dbGetQuery(pg, "ALTER TABLE activist_director.acquisition_ciq OWNER TO activism")

# Fix Cusips
fixCUSIP6s <- function(cusips) {
  to.fix <- nchar(cusips) < 6 & nchar(cusips) > 0
  cusips[to.fix] <- sprintf("%06d", as.integer(cusips[to.fix]))
  return(cusips)
}

# Divestiture Data from SDC - Deals (M&A - Divestiture)
divestiture_sdc <-  read.csv(file.path(data.path, "divestiture_sdc.csv"),
                             stringsAsFactors=FALSE)
names(divestiture_sdc) <- tolower(names(divestiture_sdc))
names(divestiture_sdc) <- gsub("\\.+", "_", names(divestiture_sdc))
names(divestiture_sdc) <- gsub("^x_", "", names(divestiture_sdc))
divestiture_sdc$date <- as.Date(as.character(divestiture_sdc$date_effective_unconditional, "%Y-%m-%d"))
divestiture_sdc$cusip <- divestiture_sdc$target_cusip
names(divestiture_sdc) <- gsub("^target_immediate_parent_cusip$","cusip_parent",
                               names(divestiture_sdc))
names(divestiture_sdc) <- gsub("^target_ultimate_parent_cusip$","cusip_ultimate",
                               names(divestiture_sdc))

# divestiture_sdc$cusip <- fixCUSIP6s(as.character(divestiture_sdc$cusip))
divestiture_sdc$cusip_parent <- fixCUSIP6s(as.character(divestiture_sdc$cusip_parent))
divestiture_sdc$cusip_ultimate <- fixCUSIP6s(as.character(divestiture_sdc$cusip_ultimate))

rs <- dbWriteTable(pg, c("activist_director", "divestiture_sdc"), divestiture_sdc,
                   row.names=FALSE, overwrite=TRUE)
rs <- dbGetQuery(pg, "ALTER TABLE activist_director.divestiture_sdc OWNER TO activism")
