library(DBI)
library(dplyr, warn.conflicts = FALSE)

pg <- dbConnect(RPostgres::Postgres(), bigint = "integer")

rs <- dbExecute(pg, "SET search_path TO activist_director, public")
rs <- dbExecute(pg, "SET work_mem = '2GB'")

equilar_final <- tbl(pg, "equilar_final")

company_years <-
    equilar_final %>%
    distinct(company_id, period)

company_directors <-
    equilar_final %>%
    distinct(company_id, executive_id, company_director_min_start,
             company_director_min_period, company_director_max_term)

own_board <-
    company_directors %>%
    left_join(company_years, by="company_id") %>%
    select(company_id, executive_id,  period, company_director_min_start, company_director_min_period,
           company_director_max_term) %>%
    mutate(start = least(company_director_min_start, company_director_min_period),
           firm_exists = TRUE) %>%
    mutate(own_board = between(period, start, company_director_max_term),
           year = date_part('year', period))

own_boards_raw <-
    own_board %>%
    group_by(company_id, executive_id) %>%
    arrange(period) %>%
    mutate(own_m3 = lag(own_board, 3L),
           own_m2 = lag(own_board, 2L),
           own_m1 = lag(own_board, 1L),
           own_board,
           own_p1 = lead(own_board, 1L),
           own_p2 = lead(own_board, 2L),
           own_p3 = lead(own_board, 3L),
           own_p4 = lead(own_board, 4L),
           own_p5 = lead(own_board, 5L),
           firm_exists_m3 = lag(firm_exists, 3L),
           firm_exists_m2 = lag(firm_exists, 2L),
           firm_exists_m1 = lag(firm_exists, 1L),
           firm_exists,
           firm_exists_p1 = lead(firm_exists, 1L),
           firm_exists_p2 = lead(firm_exists, 2L),
           firm_exists_p3 = lead(firm_exists, 3L),
           firm_exists_p4 = lead(firm_exists, 4L),
           firm_exists_p5 = lead(firm_exists, 5L)) %>%
    ungroup() %>%
    compute()

own_board_default <-
    own_boards_raw %>%
    group_by(period) %>%
    select(matches("^(own|firm_exists)")) %>%
    collect() %>%
    summarize_all(function(x) if_else(any(!is.na(x)), FALSE, NA)) %>%
    copy_to(pg, ., overwrite = TRUE)

own_boards <-
    own_boards_raw %>%
    inner_join(own_board_default, by = "period") %>%
    mutate(own_m3 = coalesce(own_m3.x, own_m3.y),
           own_m2 = coalesce(own_m2.x, own_m2.y),
           own_m1 = coalesce(own_m1.x, own_m1.y),
           own_board = coalesce(own_board.x, own_board.y),
           own_p1 = coalesce(own_p1.x, own_p1.y),
           own_p2 = coalesce(own_p2.x, own_p2.y),
           own_p3 = coalesce(own_p3.x, own_p3.y),
           own_p4 = coalesce(own_p4.x, own_p4.y),
           own_p5 = coalesce(own_p5.x, own_p5.y),
           firm_exists_m3 = coalesce(firm_exists_m3.x, firm_exists_m3.y),
           firm_exists_m2 = coalesce(firm_exists_m2.x, firm_exists_m2.y),
           firm_exists_m1 = coalesce(firm_exists_m1.x, firm_exists_m1.y),
           firm_exists = coalesce(firm_exists.x, firm_exists.y),
           firm_exists_p1 = coalesce(firm_exists_p1.x, firm_exists_p1.y),
           firm_exists_p2 = coalesce(firm_exists_p2.x, firm_exists_p2.y),
           firm_exists_p3 = coalesce(firm_exists_p3.x, firm_exists_p3.y),
           firm_exists_p4 = coalesce(firm_exists_p4.x, firm_exists_p4.y),
           firm_exists_p5 = coalesce(firm_exists_p5.x, firm_exists_p5.y)) %>%
    select(-matches("\\.[xy]$")) %>%
    mutate(year = date_part('year', period))

directorship_counts <-
    equilar_final %>%
    group_by(executive_id, year) %>%
    summarize(total_boards = n(),
              inside_boards = sum(as.integer(insider), na.rm = TRUE),
              outside_boards = sum(as.integer(outsider), na.rm = TRUE))

all_company_director_years <-
    equilar_final %>%
    distinct(year) %>%
    mutate(merge = TRUE) %>%
    inner_join(
        equilar_final %>%
            distinct(executive_id, company_id) %>%
            mutate(merge=TRUE),
        by = "merge") %>%
    select(-merge)

count_other <-
    all_company_director_years %>%
    left_join(directorship_counts, by = c("year", "executive_id")) %>%
    left_join(own_board,
              by = c("year", "executive_id", "company_id")) %>%
    mutate(own_boards = coalesce(as.integer(own_board), 0L),
           total_boards = coalesce(as.integer(total_boards), 0L)) %>%
    mutate(other_boards = total_boards - own_boards) %>%
    select(executive_id, company_id, year, own_boards, total_boards,
           other_boards, inside_boards, outside_boards)

count_others <-
    count_other %>%
    group_by(company_id, executive_id) %>%
    window_order(year) %>%
    mutate(total_m3 = lag(total_boards, 3L),
           total_m2 = lag(total_boards, 2L),
           total_m1 = lag(total_boards, 1L),
           total_boards,
           total_p1 = lead(total_boards, 1L),
           total_p2 = lead(total_boards, 2L),
           total_p3 = lead(total_boards, 3L),
           total_p4 = lead(total_boards, 4L),
           total_p5 = lead(total_boards, 5L),
           other_m3 = lag(other_boards, 3L),
           other_m2 = lag(other_boards, 2L),
           other_m1 = lag(other_boards, 1L),
           other_boards,
           other_p1 = lead(other_boards, 1L),
           other_p2 = lead(other_boards, 2L),
           other_p3 = lead(other_boards, 3L),
           other_p4 = lead(other_boards, 4L),
           other_p5 = lead(other_boards, 5L))

rs <- dbExecute(pg, "DROP TABLE IF EXISTS equilar_career")

equilar_career <-
    own_boards %>%
    left_join(count_others, by = c("company_id", "executive_id", "year")) %>%
    compute(name = "equilar_career", temporary = FALSE)

rs <- dbExecute(pg, "ALTER TABLE equilar_career OWNER TO activism")

sql <- paste0("
    COMMENT ON TABLE equilar_career IS
              'CREATED USING create_equilar_career.R ON ",
              format(Sys.time(), "%Y-%m-%d %X %Z"), "';")

rs <- dbExecute(pg, sql)

rs <- dbDisconnect(pg)
