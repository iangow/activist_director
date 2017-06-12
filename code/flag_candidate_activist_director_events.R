library(dplyr, warn.conflicts = FALSE)
pg <- src_postgres()

activist_directors <- tbl(pg, sql("SELECT * FROM activist_director.activist_directors"))
sharkwatch <- tbl(pg, sql("SELECT * FROM factset.sharkwatch"))
cusip_cik <- tbl(pg, sql("SELECT * FROM filings.cusip_cik"))

activist_director_events <-
    sharkwatch %>%
    filter(!is.na(dissident_board_seats_wongranted_date)) %>%
    select(campaign_id, cusip_9_digit, dissident_board_seats_wongranted_date)

matched_cases <-
    activist_director_events %>%
    anti_join(activist_directors) %>%
    filter(between(dissident_board_seats_wongranted_date, '2016-01-01',
                   '2016-12-31')) %>%
    rename(cusip = cusip_9_digit) %>%
    inner_join(cusip_cik) %>%
    group_by(campaign_id, cusip, cik) %>%
    summarize(num_filings = n()) %>%
    group_by(campaign_id, cusip) %>%
    filter(num_filings == max(num_filings)) %>%
    ungroup() %>%
    inner_join(activist_director_events)

matched_cases
