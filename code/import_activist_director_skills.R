library(tidyverse)
library(dplyr)
library(readxl)

activist_director_skills <- read_xlsx("~/dropbox/research/activism/activist_director/data/activist_director_skills.xlsx")
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
              technology = mean(technology, na.rm=TRUE))

skill_summ[2,] <- list(0.081, 0.119, 0.092, 0.025, 0.373, 0.220, 0.099, 0.306, 0.274, 0.053, 0.385, 0.091, 0.114, 0.140, 0.214, 0.066, 0.014, 0.189, 0.017, 0.147)
#list(0.075, 0.253, 0.082, 0.023, 0.340, 0.201, 0.089, 0.291, 0.287, 0.049, 0.383, 0.088, 0.113, 0.130, 0.234, 0.060, 0.014, 0.199, 0.016, 0.140)
skill_summ <- as.data.frame(t(skill_summ))
colnames(skill_summ) <- c("activist_director", "adams_2018")
skill_summ$diff <- skill_summ$activist_director - skill_summ$adams_2018
skill_summ$diff_pct <- (skill_summ$activist_director - skill_summ$adams_2018)/skill_summ$adams_2018
skill_summ
