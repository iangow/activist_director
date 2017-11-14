library(dplyr, warn.conflicts = FALSE)
# Sys.setenv(PGHOST = "iangow.me", PGDATABASE = "crsp")
pg <- src_postgres()

activist_director_equilar <-
    tbl(pg, sql("SELECT * FROM activist_director.activist_director_equilar"))
activist_directors <-
    tbl(pg, sql("SELECT * FROM activist_director.activist_directors"))
company_ids <-
    tbl(pg, sql("SELECT * FROM activist_director.company_ids"))
co_fin <- tbl(pg, sql("SELECT * FROM director.co_fin"))

executive <-  tbl(pg, sql("SELECT * FROM executive.executive"))
director <-  tbl(pg, sql("SELECT * FROM director.director"))

stocknames <- tbl(pg, sql("SELECT * FROM crsp.stocknames"))

unmatched_permnos <-
    activist_directors %>%
    anti_join(company_ids) %>%
    select(permno, permno_alt) %>%
    distinct() # %>%

unmatched_permnos %>%
    inner_join(stocknames) %>%
    select(permno, ncusip) %>%
    distinct() %>%
    rename(cusip = ncusip) %>%
    inner_join(co_fin) %>%
    select(permno, company_id) %>%
    distinct() %>%
    count()

activist_director_equilar %>%
    anti_join(activist_directors,
              by=c("permno", "first_name", "last_name")) %>%
    count()

activist_director_equilar %>%
    count(matched_to_equilar)

activist_directors %>%
    anti_join(new_match) %>%
    inner_join(directors) %>%
    select(last_name, first_name, campaign_id, company_name, executive_id, director_name, bio) %>%
    filter(director_name %~% first_name) %>%
    distinct() %>%
    inner_join(
        proxy_board_director %>%
            select(executive_id, bio) %>%
            distinct() %>%
            rename(equilar_bio = bio)) %>%
    collect() %>%
    write_csv("~/Google Drive/data/activist_director/activist_director_hand.csv")

directors <-
    director %>%
    mutate(last_name = regexp_replace(director_name, ",.*$", ""),
           first_name = regexp_replace(director_name, "^.*,", "")) %>%
    select(company_id, director_id, executive_id, last_name, first_name)

new_match <-
    activist_directors %>%
    inner_join(company_ids) %>%
    left_join(directors) %>%
    select(company_id, director_id, executive_id,
           last_name, first_name, director_name) %>%
    distinct() %>%
    compute()
