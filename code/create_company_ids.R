Sys.setenv(PGHOST = "iangow.me", PGDATABASE = "crsp")
pg <- src_postgres()

activist_directors <- tbl(pg, sql("SELECT * FROM activist_director.activist_directors"))
activism_events <- tbl(pg, sql("SELECT * FROM activist_director.activism_events"))
sharkwatch <- tbl(pg, sql("SELECT * FROM factset.sharkwatch"))
permnos <- tbl(pg, sql("SELECT * FROM factset.permnos"))
co_fin <- tbl(pg, sql("SELECT * FROM director.co_fin"))
stocknames <- tbl(pg, sql("SELECT * FROM crsp.stocknames"))

ad_cos <-
    activism_events %>%
    semi_join(activist_directors, by="campaign_id") %>%
    select(campaign_id, permno) %>%
    inner_join(
        sharkwatch %>%
        select(campaign_id, cusip_9_digit, company_name, primary_ticker)) %>%
    mutate(cusip = substr(cusip_9_digit, 1L, 8L))

equilar_cos <-
    co_fin %>%
    left_join(
        stocknames %>%
            select(-cusip) %>%
            rename(cusip = ncusip) %>%
            select(permno, cusip)) %>%
    select(company_id, company_name, permno, ticker) %>%
    distinct()

library(readr)
merged <-
    ad_cos %>%
    left_join(equilar_cos, by="permno") %>%
    select(campaign_id, company_id, permno, primary_ticker) %>%
    distinct() %>%
    mutate(has_co_id = !is.na(company_id), has_permno = !is.na(permno))

merged %>%
    count(has_co_id, has_permno)

hand_match <-
    gs_key("1dDtXlIyFbGYNeR__jZFRvNK-bN_0OpA24fKyaFFHF-4") %>%
    gs_read(col_types="icicccil") %>%
    select(campaign_id, company_id) %>%
    copy_to(dest = pg, name = "hand_match")

merged %>%
    filter(!has_co_id) %>%
    anti_join(hand_match, by = "campaign_id") %>%
    inner_join(sharkwatch) %>%
    select(campaign_id, primary_ticker, permno, company_name, company_name_current,
           state_of_incorporation) %>%
    collect() %>%
    write_csv("~/Google Drive/activism/data/equilar_hand_match.csv")

company_ids <-
    merged %>%
    anti_join(hand_match) %>%
    select(campaign_id, company_id) %>%
    union(hand_match) %>%
    filter(!is.na(company_id)) %>%
    compute(name = "company_ids", temporary = FALSE)

rs <- dbGetQuery(pg$con, "DROP TABLE IF EXISTS activist_director.company_ids")

rs <- dbGetQuery(pg$con, "ALTER TABLE company_ids SET SCHEMA activist_director")

rs <- dbGetQuery(pg$con, "VACUUM activist_director.company_ids")

sql <- paste0("
              COMMENT ON TABLE activist_director.company_ids IS
              'CREATED USING create_company_ids.R ON ", Sys.time() , "';")

rs <- dbGetQuery(pg$con, sql)
