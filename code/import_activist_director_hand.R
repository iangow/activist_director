hand_matched <-
    gs_key("1lf0Zdl_7AeCDTTiGGIWa3MXvoDKjqHKFJpipgf46b2s") %>%
    gs_read(col_types = "icci____l") %>%
    select(executive_id, last_name, first_name, campaign_id, same_person)

matched <-
    hand_matched %>%
    filter(same_person) %>%
    select(-same_person)

# Activist directors not matched to Equilar.
hand_matched %>%
    select(-same_person, -executive_id) %>%
    anti_join(matched)

hand_matched %>%
    select(last_name, first_name, campaign_id) %>%
    distinct() %>%
    count()

matched %>%
    select(executive_id, last_name, first_name, campaign_id) %>%
    distinct() %>%
    group_by(campaign_id, last_name, first_name) %>%
    summarize(num_matches = n()) %>%
    ungroup() %>%
    count(num_matches)

rs <- dbWriteTable(pg$con, c("activist_director", "activist_director_hand"),
                   matched,
                   overwrite=TRUE, row.names=FALSE)

rs <- dbGetQuery(pg$con, "ALTER TABLE activist_director.activist_director_hand OWNER TO activism")

rs <- dbGetQuery(pg$con, "VACUUM activist_director.activist_director_hand")

sql <- paste0("
              COMMENT ON TABLE activist_director.activist_director_hand IS
              'CREATED USING import_activist_director_hand.R ON ", Sys.time() , "';")

rs <- dbGetQuery(pg$con, sql)
