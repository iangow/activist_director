library(RPostgreSQL)
library(dplyr, warn.conflicts = FALSE)

pg <- dbConnect(PostgreSQL())

rs <- dbGetQuery(pg, "SET search_path TO activist_director")

equilar_all <- tbl(pg, "equilar_all")



# DESCRIPTIVE STATISTICS (Focusing on Appointment years) ----
equilar_all %>%
    group_by(activist_director, affiliated_director) %>%
    summarize(count = n(),
              age = avg(age),
              female = avg(as.integer(female)),
              comp_committee = avg(as.integer(comp_committee)),
              audit_committee = avg(as.integer(audit_committee)),
              # committee = avg(cmtes_cnt),
              audit_committee_financial_expert = avg(as.integer(audit_committee_financial_expert)),
              industry_expert = avg(as.integer(industry_expert)),
              super_industry_expert = avg(as.integer(super_industry_expert)))

equilar_all %>%
    group_by(activist_director, affiliated_director) %>%
    summarize(count = n(),
              own_m3 = avg(as.integer(own_m3)),
              own_m2 = avg(as.integer(own_m2)),
              own_m1 = avg(as.integer(own_m1)),
              own_board = avg(as.integer(own_board)),
              own_p1 = avg(as.integer(own_p1)),
              own_p2 = avg(as.integer(own_p2)),
              own_p3 = avg(as.integer(own_p3)),
              own_p4 = avg(as.integer(own_p4)),
              own_p5 = avg(as.integer(own_p5)))

equilar_all %>%
    group_by(activist_director, affiliated_director) %>%
    summarize(count = n(),
              other_m3 = avg(as.integer(other_m3)),
              other_m2 = avg(as.integer(other_m2)),
              other_m1 = avg(as.integer(other_m1)),
              other_boards = avg(as.integer(other_boards)),
              other_p1 = avg(as.integer(other_p1)),
              other_p2 = avg(as.integer(other_p2)),
              other_p3 = avg(as.integer(other_p3)),
              other_p4 = avg(as.integer(other_p4)),
              other_p5 = avg(as.integer(other_p5)))

rs <- dbDisconnect(pg)
