library(tidyr)
library(dplyr)

set_to_indicator <- function(df, var) {

    df %>%
        mutate_(indicator = ~TRUE) %>%
        spread_(var, "indicator", fill=FALSE)
}

cor_ind <- function(df) {
    cor(df[, unlist(lapply(df, is.logical))])
}

sql <- "
    SELECT campaign_id, demand_date, UNNEST(demand_types) AS demand_type
    FROM activist_director.key_dates"

tbl(src_postgres(), dplyr::sql(sql)) %>%
    select(campaign_id, demand_type) %>%
    distinct %>%
    as.data.frame %>%
    mutate_(indicator = ~TRUE) %>%
    spread(demand_type, indicator, fill=FALSE) %>%
    cor_ind

tbl(src_postgres(), dplyr::sql(sql)) %>%
    select(campaign_id, demand_date, demand_type) %>%
    distinct %>%
    as.data.frame %>%
    mutate_(indicator = ~TRUE) %>%
    spread(demand_type, indicator, fill=FALSE) %>%
    cor_ind

