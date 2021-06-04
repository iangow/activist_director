library(DBI)
library(dplyr, warn.conflicts = FALSE)
library(googlesheets4)
library(stringr)

gs_key <- "1zHSKIAx4LKURXav-k06D7T3p3St0VjFa8RXvAFJnUfI"
skills <-
    read_sheet(gs_key, sheet = "skills", na = "NA",
               col_types = "iccDiDliccicDccc")
names(skills) <- tolower(names(skills))

regexes <- list(
    "academic" = "academia|academic|dean|doctorate|education|faculty|graduate|masters|phd|ph.d|ph d|professor|school environment",
    "company_business" = "all aspects of our industry|chief executive officer of our|chief executive officer of the company|company’s business|executive of our|executive of the company|experience with the company|historical insight|historical knowledge|history of the operation|history with our company|in-depth knowledge of|industry-specific perspective|industry experience|industry knowledge|inner workings|insider’s perspective|internal operation|knowledge of all aspects of the company|knowledge of the|knowledge of the history|officer of our|officer of the company|president of our|president of the company|the company’s chief|understanding of our business|working with the company",
    "compensation" = "compensation",
    "entrepreneurial" = "entrepreneur|entrepreneurial|entrepreneurship|evaluating business|innovative idea",
    "finance_accounting" = "accountant|accounting and|accounting experience|accounting principles|and accounting|auditing|banking|capital markets|capital structure|corporate finance|experience in accounting|experience in finance|expertise in finance|finance experience|finance industry|finance matters|financial accounting|financial acumen|financial background|financial experience|financial expert|financial expertise|financial field|financial foundation|financial management|financial matters|financial reporting|financial services|investment|securities|understanding of finance",
    "governance" = "governance",
    "government_policy" = "government|policy|politics|regulatory",
    "international" = "global|international|multinational|worldwide",
    "leadership" = "leadership",
    "legal" = "attorney|lawyer|legal",
    "management" = "experience in leading|experience in managing|management",
    "manufacturing" = "industrial|manufactured|manufacturing",
    "marketing" = "marketing",
    "outside_board" = "board experience|board of other|board practices of other|boards of companies|boards of other|boards of several other|boards of various|director of other|director of several other|member of the board of|numerous boards|on the boards of|other company boards|prior service as a director|several corporate boards|several other corporate boards|varied boards",
    "outside_executive" = "as the chairman of a|business career|chief executive officer of a|executive experience|experience as a chief|experience as an executive officer of|experience as a senior|former executive of a|officer of a public|officer of other|officer of several companies|officer of numerous companies|president of a|senior-level executive|senior executive|senior management positions|serving as the ceo of a",
    "risk_management" = "risk",
    "scientific" = "research and development|scientific expertise",
    "strategic_planning" = "business planning|decision-making|problem-solving|strategic|strategies",
    "sustainability" = "environmental|safety|sustainability|sustainable",
    "technology" = "technological|technology")

regex_results <-
    regexes %>%
    lapply(function(x) str_detect(tolower(skills$skillset_bio), x)) %>%
    bind_cols()

activist_director_skills <-
    skills %>%
    bind_cols(regex_results) %>%
    rowwise() %>%
    mutate(num_skills = sum(c_across(academic:technology)))

pg <- dbConnect(RPostgres::Postgres())

rs <- dbExecute(pg, "SET search_path TO activist_director")

rs <- dbWriteTable(pg, "activist_director_skills", activist_director_skills,
                   overwrite = TRUE, row.names = FALSE)

rs <- dbExecute(pg, "ALTER TABLE activist_director_skills OWNER TO activism")

rs <- dbExecute(pg, "VACUUM activist_director_skills")

sql <- paste0("COMMENT ON TABLE activist_director_skills IS ",
             "'CREATED USING import_activist_director_skills.R ON ",
             format(Sys.time(), "%Y-%m-%d %X %Z"), "';")
rs <- dbExecute(pg, sql)

rs <- dbDisconnect(pg)

