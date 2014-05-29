# Import Dataset from Google Drive ----
require(RCurl)
csv_file <- getURL(paste("https://docs.google.com/spreadsheet/pub?",
                         "key=0AtCJeBFBO_EddGVDbVBONTJndlhMYU11NXlHTml1clE",
                         "&single=true&gid=1&output=csv", sep=""),
                   verbose=FALSE) 
activist_directors <- read.csv(textConnection(csv_file), as.is=TRUE)

# Fix variable names
names(activist_directors) <- gsub("\\.+", "_", tolower(names(activist_directors)))
names(activist_directors) <- gsub("_s_", "_", names(activist_directors))
names(activist_directors) <- gsub("_$", "", names(activist_directors))

# Clean up variables: clean up names
activist_directors$first_name <- gsub("\\n", "", activist_directors$first_name)
activist_directors$first_name <- gsub("\\s+$", "", activist_directors$first_name)

# Clean up variables: set to correct type
activist_directors$issuer_cik <- as.integer(activist_directors$issuer_cik)
activist_directors$cusip_9_digit <- gsub(pattern="^'+", "", activist_directors$cusip_9_digit)
activist_directors$permno <- as.integer(activist_directors$permno)
activist_directors$announce_date <- as.Date(activist_directors$announce_date)
activist_directors$appointment_date <- as.Date(activist_directors$appointment_date)
activist_directors$retirement_date <- as.Date(activist_directors$retirement_date)
activist_directors$dissident_board_seats_wongranted_date <- 
  as.Date(activist_directors$dissident_board_seats_wongranted_date)
activist_directors$activist_affiliate <- !as.logical(activist_directors$independence)
activist_directors <- subset(activist_directors,
                       subset=!is.na(appointment_date),
                       select=c(gss_id, announce_date, cusip_9_digit,
                                dissident_group, first_name, last_name,
                                activist_affiliate, appointment_date,
                                dissident_board_seats_wongranted_date,
                                retirement_date, issuer_cik)) 

# Export da taset to PostgreSQL (activist_director.activist_directors) ----
library(RPostgreSQL)
drv <- dbDriver("PostgreSQL")
pg <- dbConnect(drv, dbname="crsp")

rs <- dbWriteTable(pg, c("activist_director", "activist_directors"), 
                   activist_directors, overwrite=TRUE, row.names=FALSE)
# rs <- dbGetQuery(pg, "CREATE ROLE activism")
rs <- dbGetQuery(pg, "
    ALTER TABLE activist_director.activist_directors OWNER TO activism")

# Add PERMNO to the table (match to CUSIP)
# rs <- dbGetQuery(pg,"
#   ALTER TABLE activist_director.activist_directors ADD COLUMN permno integer;
# 
#   WITH permnos AS (
#     SELECT DISTINCT permno, ncusip AS cusip 
#     FROM activism.permnos)
#   UPDATE activist_director.activist_directors AS a
#   SET permno_alt = (
#     SELECT permno 
#     FROM permnos AS b
#     WHERE b.cusip=substr(a.cusip_9_digit,1,8))
# ")

rs <- dbGetQuery(pg, "VACUUM activist_director.activist_directors")

sql <- paste("
  COMMENT ON TABLE activist_director.activist_directors IS
    'CREATED USING import_bio_data.R ON ", Sys.time() , "';", sep="")

rs <- dbGetQuery(pg, sql)

# processed <-  dbGetQuery(pg, "SELECT * FROM activist_director.activist_directors")
# matched <-  dbGetQuery(pg, "
#     SELECT a.*,  b.dissident_board_seats_wongranted_date AS factset_granted_date
#     FROM activist_director.activist_directors AS a
#     INNER JOIN factset.sharkwatch AS b
#     USING (announce_date, cusip_9_digit, dissident_group)")
# 
# subset(matched, dissident_board_seats_wongranted_date != factset_granted_date)
# subset(matched, !is.na(dissident_board_seats_wongranted_date) & is.na(factset_granted_date))
# subset(matched, is.na(dissident_board_seats_wongranted_date) & !is.na(factset_granted_date))
# subset(matched,  is.na(dissident_board_seats_wongranted_date))
