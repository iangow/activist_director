Sys.setenv(PGHOST="iangow.me", PGDATABASE="crsp")
library(dplyr, warn.conflicts = FALSE)
library(tidyr)
library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

sharkwatch <- tbl(pg, sql("SELECT * FROM factset.sharkwatch"))

gov_demands <-
    sharkwatch %>%
    mutate(demand = regexp_split_to_array(governance_demands_followthroughsuccess,
                                          "(?<=(?:Yes|No)\\))")) %>%
    mutate(demand = unnest(demand)) %>%
    select(campaign_id, demand)

val_demands <-
    sharkwatch %>%
    mutate(demand = regexp_split_to_array(value_demands_followthroughsuccess,
                                          "(?<=(?:Yes|No)\\))")) %>%
    mutate(demand = unnest(demand)) %>%
    select(campaign_id, demand)

demands <-
    val_demands %>%
    union(gov_demands) %>%
    mutate(demand= regexp_split_to_array(demand, "\\((?=(?:Yes|No))")) %>%
    mutate(demand = sql("demand[1]"), outcome=sql("demand[2]")) %>%
    mutate(outcome = regexp_replace(outcome, "\\)", "")) %>%
    filter(!is.na(outcome))

demands_data <- demands %>% as.data.frame

# Write data to PostgreSQL
rs <- dbWriteTable(pg, c("activist_director", "demands"), demands_data,
             row.names = FALSE, overwrite = TRUE)

rs <- dbGetQuery(pg, "ALTER TABLE activist_director.demands OWNER TO activism")

#> Source:   query [?? x 3]
#> Database: postgres 9.6.3 [igow@iangow.me:5432/crsp]
#>
#> # A tibble: ?? x 3
#>    campaign_id
#>          <int>
#>  1       54704
#>  2      396364
#>  3      396364
#>  4      396364
#>  5      396364
#>  6      411278
#>  7      411278
#>  8      411278
#>  9      411278
#> 10      556550
#> # ... with more rows, and 2 more variables: demand <chr>, outcome <chr>

demands %>%
    count(demand, outcome) %>%
    collect() %>%
    spread(key = outcome, value = n) %>%
    mutate(Total = No + Yes) %>%
    arrange(desc(Total))
