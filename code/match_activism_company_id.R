library(dplyr, warn.conflicts = FALSE)
pg <- src_postgres()

activist_directors <- tbl(pg, sql("SELECT * FROM activist_director.activist_directors"))
sharkwatch <- tbl(pg, sql("SELECT * FROM factset.sharkwatch"))
cusip_cik <- tbl(pg, sql("SELECT * FROM filings.cusip_cik"))
ciks <- tbl(pg, sql("SELECT * FROM executive.ciks"))

missing_ciks <-
    activist_directors %>%
    filter(is.na(issuer_cik))

missing_ciks %>%
    count(source)

cusips <-
    sharkwatch %>%
    select(campaign_id, cusip_9_digit, cusip_9_digit_current)

cusip_matches <-
    missing_ciks %>%
    select(campaign_id) %>%
    distinct() %>%
    left_join(cusips, by="campaign_id")

cusip_matches %>%
    mutate(has_cusip = !is.na(cusip_9_digit)) %>%
    count(has_cusip)

cik_matches <-
    cusip_matches %>%
    rename(cusip = cusip_9_digit) %>%
    inner_join(cusip_cik) %>%
    group_by(campaign_id, cusip, cik) %>%
    summarize(num_filings = n()) %>%
    group_by(campaign_id, cusip) %>%
    filter(num_filings == max(num_filings)) %>%
    ungroup()

cik_matches_current <-
    cusip_matches %>%
    rename(cusip = cusip_9_digit_current) %>%
    inner_join(cusip_cik) %>%
    group_by(campaign_id, cusip, cik) %>%
    summarize(num_filings = n()) %>%
    group_by(campaign_id, cusip) %>%
    filter(num_filings == max(num_filings)) %>%
    ungroup()

cik_matches_all <-
    cik_matches %>%
    union(cik_matches_current) %>%
    select(campaign_id, cik) %>%
    distinct() %>%
    arrange(campaign_id) %>%
    left_join(ciks) %>%
    mutate(has_co_id = !is.na(company_id))

cik_matches_all %>%
    count(has_co_id)

