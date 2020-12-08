skill_summ <- activist_director_skills %>%
    summarise(academic = mean(academic, na.rm=TRUE),
              company_business = mean(company_business, na.rm=TRUE),
              compensation = mean(compensation, na.rm=TRUE),
              entrepreneurial = mean(entrepreneurial, na.rm=TRUE),
              finance_accounting = mean(finance_accounting, na.rm=TRUE),
              governance = mean(governance, na.rm=TRUE),
              government_policy = mean(government_policy, na.rm=TRUE),
              international = mean(international, na.rm=TRUE),
              leadership = mean(leadership, na.rm=TRUE),
              legal = mean(legal, na.rm=TRUE),
              management = mean(management, na.rm=TRUE),
              manufacturing = mean(manufacturing, na.rm=TRUE),
              marketing = mean(marketing, na.rm=TRUE),
              outside_board = mean(outside_board, na.rm=TRUE),
              outside_executive = mean(outside_executive, na.rm=TRUE),
              risk_management = mean(risk_management, na.rm=TRUE),
              scientific = mean(scientific, na.rm=TRUE),
              strategic_planning = mean(strategic_planning, na.rm=TRUE),
              sustainability = mean(sustainability, na.rm=TRUE),
              technology = mean(technology, na.rm=TRUE),
              num_skills = mean(num_skills, na.rm=TRUE))

skill_summ_affiliated <- activist_director_skills %>% filter(!independent) %>%
    summarise(academic = mean(academic, na.rm=TRUE),
              company_business = mean(company_business, na.rm=TRUE),
              compensation = mean(compensation, na.rm=TRUE),
              entrepreneurial = mean(entrepreneurial, na.rm=TRUE),
              finance_accounting = mean(finance_accounting, na.rm=TRUE),
              governance = mean(governance, na.rm=TRUE),
              government_policy = mean(government_policy, na.rm=TRUE),
              international = mean(international, na.rm=TRUE),
              leadership = mean(leadership, na.rm=TRUE),
              legal = mean(legal, na.rm=TRUE),
              management = mean(management, na.rm=TRUE),
              manufacturing = mean(manufacturing, na.rm=TRUE),
              marketing = mean(marketing, na.rm=TRUE),
              outside_board = mean(outside_board, na.rm=TRUE),
              outside_executive = mean(outside_executive, na.rm=TRUE),
              risk_management = mean(risk_management, na.rm=TRUE),
              scientific = mean(scientific, na.rm=TRUE),
              strategic_planning = mean(strategic_planning, na.rm=TRUE),
              sustainability = mean(sustainability, na.rm=TRUE),
              technology = mean(technology, na.rm=TRUE),
              num_skills = mean(num_skills, na.rm=TRUE))

skill_summ_unaffiliated <- activist_director_skills %>% filter(independent) %>%
    summarise(academic = mean(academic, na.rm=TRUE),
              company_business = mean(company_business, na.rm=TRUE),
              compensation = mean(compensation, na.rm=TRUE),
              entrepreneurial = mean(entrepreneurial, na.rm=TRUE),
              finance_accounting = mean(finance_accounting, na.rm=TRUE),
              governance = mean(governance, na.rm=TRUE),
              government_policy = mean(government_policy, na.rm=TRUE),
              international = mean(international, na.rm=TRUE),
              leadership = mean(leadership, na.rm=TRUE),
              legal = mean(legal, na.rm=TRUE),
              management = mean(management, na.rm=TRUE),
              manufacturing = mean(manufacturing, na.rm=TRUE),
              marketing = mean(marketing, na.rm=TRUE),
              outside_board = mean(outside_board, na.rm=TRUE),
              outside_executive = mean(outside_executive, na.rm=TRUE),
              risk_management = mean(risk_management, na.rm=TRUE),
              scientific = mean(scientific, na.rm=TRUE),
              strategic_planning = mean(strategic_planning, na.rm=TRUE),
              sustainability = mean(sustainability, na.rm=TRUE),
              technology = mean(technology, na.rm=TRUE),
              num_skills = mean(num_skills, na.rm=TRUE))

skill_summ[2,] <- skill_summ_affiliated
skill_summ[3,] <- skill_summ_unaffiliated
skill_summ <- as.data.frame(t(skill_summ))
colnames(skill_summ) <- c("activist_director","affiliated", "unaffiliated")
skill_summ


# Regression
library(zoo)
source("https://raw.githubusercontent.com/iangow/acct_data/master/code/cluster2.R")

skill_summ$diff_affil_unaffil <- skill_summ$unaffiliated - skill_summ$affiliated

skill_summ$diff_p_value_affil_unaffil <- list(t.test(academic ~ independent, data=activist_director_skills)[3],
                                              t.test(company_business ~ independent, data=activist_director_skills)[3],
                                              t.test(compensation ~ independent, data=activist_director_skills)[3],
                                              t.test(entrepreneurial ~ independent, data=activist_director_skills)[3],
                                              t.test(finance_accounting ~ independent, data=activist_director_skills)[3],
                                              t.test(governance ~ independent, data=activist_director_skills)[3],
                                              t.test(government_policy ~ independent, data=activist_director_skills)[3],
                                              t.test(international ~ independent, data=activist_director_skills)[3],
                                              t.test(leadership ~ independent, data=activist_director_skills)[3],
                                              t.test(legal ~ independent, data=activist_director_skills)[3],
                                              t.test(management ~ independent, data=activist_director_skills)[3],
                                              t.test(manufacturing ~ independent, data=activist_director_skills)[3],
                                              t.test(marketing ~ independent, data=activist_director_skills)[3],
                                              t.test(outside_board ~ independent, data=activist_director_skills)[3],
                                              t.test(outside_executive ~ independent, data=activist_director_skills)[3],
                                              t.test(risk_management ~ independent, data=activist_director_skills)[3],
                                              t.test(scientific ~ independent, data=activist_director_skills)[3],
                                              t.test(strategic_planning ~ independent, data=activist_director_skills)[3],
                                              t.test(sustainability ~ independent, data=activist_director_skills)[3],
                                              t.test(technology ~ independent, data=activist_director_skills)[3],
                                              t.test(num_skills ~ independent, data=activist_director_skills)[3])

skill_summ

# Simulation Study 0.075, 0.253, 0.082, 0.023, 0.340, 0.201, 0.089, 0.291, 0.287, 0.049, 0.383, 0.088, 0.113, 0.130, 0.234, 0.060, 0.014, 0.199, 0.016, 0.140
academic <- ifelse(runif(29209) <= 0.075, TRUE, FALSE)
company_business <- ifelse(runif(29209) <= 0.253, TRUE, FALSE)
compensation <- ifelse(runif(29209) <= 0.082, TRUE, FALSE)
entrepreneurial <- ifelse(runif(29209) <= 0.023, TRUE, FALSE)
finance_accounting <- ifelse(runif(29209) <= 0.340, TRUE, FALSE)
governance <- ifelse(runif(29209) <= 0.201, TRUE, FALSE)
government_policy <- ifelse(runif(29209) <= 0.089, TRUE, FALSE)
international <- ifelse(runif(29209) <= 0.291, TRUE, FALSE)
leadership <- ifelse(runif(29209) <= 0.287, TRUE, FALSE)
legal <- ifelse(runif(29209) <= 0.049, TRUE, FALSE)
management <- ifelse(runif(29209) <= 0.383, TRUE, FALSE)
manufacturing <- ifelse(runif(29209) <= 0.088, TRUE, FALSE)
marketing <- ifelse(runif(29209) <= 0.113, TRUE, FALSE)
outside_board <- ifelse(runif(29209) <= 0.130, TRUE, FALSE)
outside_executive <- ifelse(runif(29209) <= 0.234, TRUE, FALSE)
risk_management <- ifelse(runif(29209) <= 0.060, TRUE, FALSE)
scientific <- ifelse(runif(29209) <= 0.014, TRUE, FALSE)
strategic_planning <- ifelse(runif(29209) <= 0.199, TRUE, FALSE)
sustainability <- ifelse(runif(29209) <= 0.016, TRUE, FALSE)
technology <- ifelse(runif(29209) <= 0.140, TRUE, FALSE)

sim_director_skills_0 <- data.frame(academic, company_business, compensation, entrepreneurial,
                                    finance_accounting, governance, government_policy, international,
                                    leadership, legal, management, manufacturing, marketing,
                                    outside_board, outside_executive, risk_management,
                                    scientific, strategic_planning, sustainability, technology)
sim_director_skills_0$affiliated <- FALSE
sim_director_skills_0$unaffiliated <- FALSE
sim_director_skills_0$activist_director <- FALSE

activist_director_skills$affiliated <- !activist_director_skills$independent
activist_director_skills$unaffiliated <- activist_director_skills$independent
activist_director_skills$activist_director <- !is.na(activist_director_skills$independent)

sim_director_skills_1 <- activist_director_skills %>%
    select(academic, company_business, compensation, entrepreneurial,
           finance_accounting, governance, government_policy, international,
           leadership, legal, management, manufacturing, marketing,
           outside_board, outside_executive, risk_management,
           scientific, strategic_planning, sustainability, technology,
           activist_director, affiliated, unaffiliated) %>%
    as.data.frame()

sim_director_skills <- rbind(sim_director_skills_0, sim_director_skills_1)

skill_summ_sim <- sim_director_skills %>% filter(activist_director) %>%
    summarise(academic = mean(academic, na.rm=TRUE),
              company_business = mean(company_business, na.rm=TRUE),
              compensation = mean(compensation, na.rm=TRUE),
              entrepreneurial = mean(entrepreneurial, na.rm=TRUE),
              finance_accounting = mean(finance_accounting, na.rm=TRUE),
              governance = mean(governance, na.rm=TRUE),
              government_policy = mean(government_policy, na.rm=TRUE),
              international = mean(international, na.rm=TRUE),
              leadership = mean(leadership, na.rm=TRUE),
              legal = mean(legal, na.rm=TRUE),
              management = mean(management, na.rm=TRUE),
              manufacturing = mean(manufacturing, na.rm=TRUE),
              marketing = mean(marketing, na.rm=TRUE),
              outside_board = mean(outside_board, na.rm=TRUE),
              outside_executive = mean(outside_executive, na.rm=TRUE),
              risk_management = mean(risk_management, na.rm=TRUE),
              scientific = mean(scientific, na.rm=TRUE),
              strategic_planning = mean(strategic_planning, na.rm=TRUE),
              sustainability = mean(sustainability, na.rm=TRUE),
              technology = mean(technology, na.rm=TRUE))

skill_summ_adams <- sim_director_skills %>% filter(!activist_director) %>%
    summarise(academic = mean(academic, na.rm=TRUE),
              company_business = mean(company_business, na.rm=TRUE),
              compensation = mean(compensation, na.rm=TRUE),
              entrepreneurial = mean(entrepreneurial, na.rm=TRUE),
              finance_accounting = mean(finance_accounting, na.rm=TRUE),
              governance = mean(governance, na.rm=TRUE),
              government_policy = mean(government_policy, na.rm=TRUE),
              international = mean(international, na.rm=TRUE),
              leadership = mean(leadership, na.rm=TRUE),
              legal = mean(legal, na.rm=TRUE),
              management = mean(management, na.rm=TRUE),
              manufacturing = mean(manufacturing, na.rm=TRUE),
              marketing = mean(marketing, na.rm=TRUE),
              outside_board = mean(outside_board, na.rm=TRUE),
              outside_executive = mean(outside_executive, na.rm=TRUE),
              risk_management = mean(risk_management, na.rm=TRUE),
              scientific = mean(scientific, na.rm=TRUE),
              strategic_planning = mean(strategic_planning, na.rm=TRUE),
              sustainability = mean(sustainability, na.rm=TRUE),
              technology = mean(technology, na.rm=TRUE))

skill_summ_sim
skill_summ_sim[2,] <- skill_summ_adams
skill_summ_sim <- as.data.frame(t(skill_summ_sim))
colnames(skill_summ_sim) <- c("activist_director","adams_2018")
skill_summ_sim$diff <- skill_summ_sim$activist_director - skill_summ_sim$adams_2018
skill_summ_sim$diff_pct <- (skill_summ_sim$activist_director - skill_summ_sim$adams_2018)/skill_summ_sim$adams_2018
skill_summ_sim

skill_summ_sim$p_value_act_vs_adams <-
    list(t.test(academic ~ activist_director, data=sim_director_skills)[3],
         t.test(company_business ~ activist_director, data=sim_director_skills)[3],
         t.test(compensation ~ activist_director, data=sim_director_skills)[3],
         t.test(entrepreneurial ~ activist_director, data=sim_director_skills)[3],
         t.test(finance_accounting ~ activist_director, data=sim_director_skills)[3],
         t.test(governance ~ activist_director, data=sim_director_skills)[3],
         t.test(government_policy ~ activist_director, data=sim_director_skills)[3],
         t.test(international ~ activist_director, data=sim_director_skills)[3],
         t.test(leadership ~ activist_director, data=sim_director_skills)[3],
         t.test(legal ~ activist_director, data=sim_director_skills)[3],
         t.test(management ~ activist_director, data=sim_director_skills)[3],
         t.test(manufacturing ~ activist_director, data=sim_director_skills)[3],
         t.test(marketing ~ activist_director, data=sim_director_skills)[3],
         t.test(outside_board ~ activist_director, data=sim_director_skills)[3],
         t.test(outside_executive ~ activist_director, data=sim_director_skills)[3],
         t.test(risk_management ~ activist_director, data=sim_director_skills)[3],
         t.test(scientific ~ activist_director, data=sim_director_skills)[3],
         t.test(strategic_planning ~ activist_director, data=sim_director_skills)[3],
         t.test(sustainability ~ activist_director, data=sim_director_skills)[3],
         t.test(technology ~ activist_director, data=sim_director_skills)[3])
skill_summ_sim
