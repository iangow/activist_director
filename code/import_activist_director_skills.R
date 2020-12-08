library(DBI)
library(dplyr, warn.conflicts = FALSE)
library(readxl)
library(stringr)

activist_director_skills <- read_xlsx("data/activist_director_skills.xlsx",
                                      na = "NA")
names(activist_director_skills) <- tolower(names(activist_director_skills))

regex_skill <- function(x, regex) {
    str_detect(tolower(x), regex)
}

activist_director_skills <-
    activist_director_skills %>%
    mutate(academic = regex_skill(skillset_bio, "academia|academic|dean|doctorate|education|faculty|graduate|masters|phd|ph.d|ph d|professor|school environment"),
           company_business = regex_skill(skillset_bio, "all aspects of our industry|chief executive officer of our|chief executive officer of the company|company’s business|executive of our|executive of the company|experience with the company|historical insight|historical knowledge|history of the operation|history with our company|in-depth knowledge of|industry-specific perspective|industry experience|industry knowledge|inner workings|insider’s perspective|internal operation|knowledge of all aspects of the company|knowledge of the|knowledge of the history|officer of our|officer of the company|president of our|president of the company|the company’s chief|understanding of our business|working with the company"),
           compensation = regex_skill(skillset_bio, "compensation"),
           entrepreneurial = regex_skill(skillset_bio, "entrepreneur|entrepreneurial|entrepreneurship|evaluating business|innovative idea"),
           finance_accounting = regex_skill(skillset_bio, "accountant|accounting and|accounting experience|accounting principles|and accounting|auditing|banking|capital markets|capital structure|corporate finance|experience in accounting|experience in finance|expertise in finance|finance experience|finance industry|finance matters|financial accounting|financial acumen|financial background|financial experience|financial expert|financial expertise|financial field|financial foundation|financial management|financial matters|financial reporting|financial services|investment|securities|understanding of finance"),
           governance = regex_skill(skillset_bio, "governance"),
           government_policy = regex_skill(skillset_bio, "government|policy|politics|regulatory"),
           international = regex_skill(skillset_bio, "global|international|multinational|worldwide"),
           leadership = regex_skill(skillset_bio, "leadership"),
           legal = regex_skill(skillset_bio, "attorney|lawyer|legal"),
           management = regex_skill(skillset_bio, "experience in leading|experience in managing|management"),
           manufacturing = regex_skill(skillset_bio, "industrial|manufactured|manufacturing"),
           marketing = regex_skill(skillset_bio, "marketing"),
           outside_board = regex_skill(skillset_bio, "board experience|board of other|board practices of other|boards of companies|boards of other|boards of several other|boards of various|director of other|director of several other|member of the board of|numerous boards|on the boards of|other company boards|prior service as a director|several corporate boards|several other corporate boards|varied boards"),
           outside_executive = regex_skill(skillset_bio, "as the chairman of a|business career|chief executive officer of a|executive experience|experience as a chief|experience as an executive officer of|experience as a senior|former executive of a|officer of a public|officer of other|officer of several companies|officer of numerous companies|president of a|senior-level executive|senior executive|senior management positions|serving as the ceo of a"),
           risk_management = regex_skill(skillset_bio, "risk"),
           scientific = regex_skill(skillset_bio, "research and development|scientific expertise"),
           strategic_planning = regex_skill(skillset_bio, "business planning|decision-making|problem-solving|strategic|strategies"),
           sustainability = regex_skill(skillset_bio, "environmental|safety|sustainability|sustainable"),
           technology = regex_skill(skillset_bio, "technological|technology")) %>%
    rowwise() %>%
    mutate(num_skills = sum(c_across(academic:technology)))

pg <- dbConnect(RPostgres::Postgres())

rs <- dbExecute(pg, "SET search_path TO activist_director")

rs <- dbWriteTable(pg, "activist_director_skills",
                   activist_director_skills, overwrite=TRUE, row.names=FALSE)

rs <- dbExecute(pg, "ALTER TABLE activist_director_skills OWNER TO activism")

rs <- dbExecute(pg, "VACUUM activist_director.key_dates")

sql <- paste0("COMMENT ON TABLE activist_director_skills IS ",
             "'CREATED USING import_activist_director_skills.R ON ",
             format(Sys.time(), "%Y-%m-%d %X %Z"), "';")
rs <- dbExecute(pg, sql)

rs <- dbDisconnect(pg)

