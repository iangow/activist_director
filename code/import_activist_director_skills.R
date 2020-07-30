library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())
library(tidyverse)
library(dplyr)
library(readxl)

activist_director_skills <- read_xlsx("~/activist_director/data/activist_director_skills.xlsx")
names(activist_director_skills)[14] <- "_url_"
names(activist_director_skills) <- tolower(names(activist_director_skills))

activist_director_skills <-
    activist_director_skills %>%
    mutate(academic = str_detect(tolower(skillset_bio), "academia|academic|dean|doctorate|education|faculty|graduate|masters|phd|ph.d|ph.d.|professor|school environment"),
           company_business = str_detect(tolower(skillset_bio), "all aspects of our industry|chief executive officer of our|chief executive officer of the company|company’s business|executive of our|executive of the company|experience with the company|historical insight|historical knowledge|history of the operation|history with our company|in-depth knowledge of|industry-specific perspective|industry experience|industry knowledge|inner workings|insider’s perspective|internal operation|knowledge of all aspects of the company|knowledge of the|knowledge of the history|officer of our|officer of the company|president of our|president of the company|the company’s chief|understanding of our business|working with the company"),
           compensation = str_detect(tolower(skillset_bio), "compensation"),
           entrepreneurial = str_detect(tolower(skillset_bio), "entrepreneur|entrepreneurial|entrepreneurship|evaluating business|innovative idea"),
           finance_accounting = str_detect(tolower(skillset_bio), "accountant|accounting and|accounting experience|accounting principles|and accounting,
auditing|banking|capital markets|capital structure|corporate finance|experience in accounting|experience in finance|expertise in finance|finance experience|finance industry|finance matters|financial accounting|financial acumen|financial background|financial experience|financial expert|financial expertise|financial field|financial foundation|financial management|financial matters|financial reporting|financial services|investment|securities|understanding of finance"),
           governance = str_detect(tolower(skillset_bio), "governance"),
           government_policy = str_detect(tolower(skillset_bio), "government|policy|politics|regulatory"),
           international = str_detect(tolower(skillset_bio), "global|international|multinational|worldwide"),
           leadership = str_detect(tolower(skillset_bio), "leadership"),
           legal = str_detect(tolower(skillset_bio), "attorney|lawyer|legal"),
           management = str_detect(tolower(skillset_bio), "experience in leading|experience in managing|management"),
           manufacturing = str_detect(tolower(skillset_bio), "industrial|manufactured|manufacturing"),
           marketing = str_detect(tolower(skillset_bio), "marketing"),
           outside_board = str_detect(tolower(skillset_bio), "board experience|board of other|board practices of other|boards of companies|boards of
other|boards of several other|boards of various|director of other|director of several other|member of the board of|numerous boards|on the boards of|other company boards|prior service as a director|several corporate boards|several other corporate boards|varied boards"),
           outside_executive = str_detect(tolower(skillset_bio), "as the chairman of a|business career|chief executive officer of a|executive experience|experience as a chief|experience as an executive officer of|experience as a senior|former executive of a|officer of a public|officer of other|officer of several companies|officer of numerous companies|president of a|senior-level executive|senior executive|senior management positions|serving as the ceo of a"),
           risk_management = str_detect(tolower(skillset_bio), "risk"),
           scientific = str_detect(tolower(skillset_bio), "research and development|scientific expertise"),
           strategic_planning = str_detect(tolower(skillset_bio), "business planning|decision-making|problem-solving|strategic|strategies"),
           sustainability = str_detect(tolower(skillset_bio), "environmental|safety|sustainability|sustainable"),
           technology = str_detect(tolower(skillset_bio), "technological|technology"))

activist_director_skills <- activist_director_skills %>%
    mutate(num_skills = as.integer(academic)+as.integer(company_business)
           +as.integer(compensation)+as.integer(entrepreneurial)
           +as.integer(finance_accounting)+as.integer(governance)
           +as.integer(government_policy)+as.integer(international)
           +as.integer(leadership)+as.integer(legal)
           +as.integer(management)+as.integer(manufacturing)+as.integer(marketing)
           +as.integer(outside_board)+as.integer(outside_executive)
           +as.integer(risk_management)+as.integer(scientific)
           +as.integer(strategic_planning)+as.integer(sustainability)
           +as.integer(technology)) %>%
    collect()

rs <- dbWriteTable(pg, c("activist_director", "activist_director_skills"),
                   activist_director_skills, overwrite=TRUE, row.names=FALSE)

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

# Merge with activist_director.activist_directors
library(RPostgreSQL)
drv <- dbDriver("PostgreSQL")
pg <- dbConnect(drv, host='iangow.me', port='5432', dbname='crsp')

rs <- dbExecute(pg, "SET search_path TO activist_director, public")

activist_directors <- tbl(pg, sql("SELECT * FROM activist_director.activist_directors")) %>% collect()

