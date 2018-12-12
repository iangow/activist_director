library(dplyr, warn.conflicts = FALSE)
library(DBI)

pg <- dbConnect(RPostgreSQL::PostgreSQL())

rs <- dbExecute(pg, "SET work_mem = '2GB'")
rs <- dbExecute(pg, "SET search_path TO activist_director, public")

activism_events_equilar <- tbl(pg, "activism_events_equilar")
activism_events <- tbl(pg, "activism_events")
director_index <- tbl(pg, sql("SELECT * FROM equilar_hbs.director_index"))

num_directors <-
    director_index %>%
    group_by(company_id, period) %>%
    summarise(num_dirs = n()) %>%
    compute()

rel_periods <-
    num_directors %>%
    group_by(company_id) %>%
    arrange(period) %>%
    mutate(ord_period = row_number()) %>%
    compute()

plot_data_raw <-
    rel_periods %>%
    select(company_id, period, ord_period) %>%
    inner_join(
        rel_periods %>%
            select(company_id, ord_period, num_dirs), by = "company_id") %>%
    mutate(rel_period = ord_period.y - ord_period.x) %>%
    select(company_id, period, rel_period, num_dirs) %>%
    filter(between(rel_period, -3, 3)) %>%
    group_by(company_id, period) %>%
    mutate(num_obs = n()) %>%
    ungroup() %>%
    filter(num_obs == 7) %>%
    select(-num_obs) %>%
    compute()

categories <-
    activism_events_equilar %>%
    inner_join(activism_events, by = "campaign_id") %>%
    group_by(company_id, period) %>%
    summarize(categories = array_agg(affiliated)) %>%
    ungroup() %>%
    mutate(category = case_when(
        "affiliated" == sql("any(categories)") ~ "affiliated",
        "unaffiliated" == sql("any(categories)") ~ "unaffiliated",
        "activism" == sql("any(categories)") ~ "activism"))

plot_data <-
    plot_data_raw %>%
    left_join(categories, by = c("company_id", "period")) %>%
    mutate(category = coalesce(category, "_none")) %>%
    group_by(rel_period, category) %>%
    summarize(num_dirs = mean(num_dirs, na.rm = TRUE)) %>%
    collect()

library(ggplot2)

plot_data %>%
    ggplot(aes(x = rel_period, y = num_dirs, color = category)) %+%
    geom_line() +
    geom_point()

library(tidyr)

fix_number <- function(x) {
    num <-
        case_when(
            x < 0 ~ gsub("-", "m", x),
            x == "0" ~ "p0",
            TRUE ~ paste0("p", x))
    paste0("num_directors_", num)
}

plot_data %>% spread(key = rel_period, value = num_dirs) %>% rename_if(is.numeric, fix_number)
