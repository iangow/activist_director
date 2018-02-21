# Get data from database ----
library("RPostgreSQL")
pg <- dbConnect(PostgreSQL())

# Get voting changes data from PostgreSQL ----
vote.data <- dbGetQuery(pg, "
    -- Match Equilar to PERMNOs
    WITH equilar_permnos AS (
    SELECT DISTINCT b.permno, company_id AS company_id, fye AS period
    FROM equilar_hbs.company_financials AS a
    LEFT JOIN activist_director.permnos AS b
    ON substr(a.cusip, 1, 8)=b.ncusip),

    activist_director_equilar as (
    SELECT DISTINCT b.permno, a.*
    FROM activist_director.activist_director_equilar AS a
    LEFT JOIN equilar_permnos AS b
    ON a.company_id=b.company_id AND a.period=b.period
    ORDER BY permno, period, executive_id)

    SELECT DISTINCT a.*, b.appointment_date, b.appointment_date IS NOT NULL AS activist_director, b.independent IS FALSE AS affiliated_director,
        c.permno IS NOT NULL AS activist_director_period
    FROM activist_director.iss_voting AS a
    LEFT JOIN activist_director_equilar AS b
    ON a.permno=b.permno AND a.executive_id=b.executive_id AND meetingdate BETWEEN b.appointment_date-100 AND b.appointment_date+100
    LEFT JOIN activist_director_equilar AS c
    ON a.permno=c.permno AND meetingdate BETWEEN c.appointment_date-100 AND c.appointment_date+100
")

## Create permno_meetingdate variable
vote.data$permno_meetingdate <- paste(vote.data$permno, " & ", vote.data$meetingdate, sep="")

dbDisconnect(pg)

# Functions
library(psych)
require(texreg)
library(car)
library(doBy)
source("https://raw.githubusercontent.com/iangow/acct_data/master/code/cluster2.R")

### Summary Tables----
summaryBy(vote_pct ~ activist_director + affiliated_director,
          data=subset(vote.data, !is.na(vote_pct)),
          FUN=function(x) { c( mean = mean(x), median = median(x), sd = sd(x), N = length(x)) })

summaryBy(vote_pct ~ activist_director + affiliated_director,
          data=subset(vote.data, !is.na(vote_pct) & activist_director_period),
          FUN=function(x) { c( mean = mean(x), median = median(x), sd = sd(x), N = length(x)) })

summaryBy(vote_pct_p1 ~ activist_director + affiliated_director,
          data=subset(vote.data, !is.na(vote_pct_p1)),
          FUN=function(x) { c( mean = mean(x), median = median(x), sd = sd(x), N = length(x)) })

summaryBy(vote_pct_p2 ~ activist_director + affiliated_director,
          data=subset(vote.data, !is.na(vote_pct_p2)),
          FUN=function(x) { c( mean = mean(x), median = median(x), sd = sd(x), N = length(x)) })

### Regression Analyses----

#### voting_p1 ~ activism
reg.data <- subset(vote.data)

fm.t1.pa.c1 <- lm(vote_pct * 100 ~ activist_director,
                  data=reg.data, na.action="na.exclude")
fm.t1.pa.c1.se <- coeftest.cluster(reg.data, fm.t1.pa.c1, cluster1="permno")

#### voting_p1 ~ activism (activist_director firms only)
reg.data <- subset(vote.data, activist_director_period)

fm.t1.pa.c2 <- lm(vote_pct * 100 ~ activist_director * affiliated_director + factor(permno_meetingdate),
                  data=reg.data, na.action="na.exclude")
fm.t1.pa.c2.se <- coeftest.cluster(reg.data, fm.t1.pa.c2, cluster1="permno")

fm.t1.pa.c3 <- lm(vote_pct_p1 * 100 ~ activist_director * affiliated_director + vote_pct + factor(permno_meetingdate),
                  data=reg.data, na.action="na.exclude")
fm.t1.pa.c3.se <- coeftest.cluster(reg.data, fm.t1.pa.c3, cluster1="permno")

fm.t1.pa.c4 <- lm(vote_pct_p2 * 100 ~ activist_director * affiliated_director + vote_pct + factor(permno_meetingdate),
                  data=reg.data, na.action="na.exclude")
fm.t1.pa.c4.se <- coeftest.cluster(reg.data, fm.t1.pa.c4, cluster1="permno")


# Produce Excel file with results for prob_activism
screenreg(list(fm.t1.pa.c1, fm.t1.pa.c2, fm.t1.pa.c3, fm.t1.pa.c4),
        # file = "tables/voting_analysis.docx",
        caption = "Voting support for activist directors",
        caption.above = TRUE,
        digits = 3,
        stars = c(0.01, 0.05, 0.1),
        omit.coef = "(permno_meetingdate)",
        custom.model.names = c("% Voting Support","% Voting Support","% Voting Support_t+1","% Voting Support_t+2"),
        override.se = list(fm.t1.pa.c1.se[,2], fm.t1.pa.c2.se[,2], fm.t1.pa.c3.se[,2], fm.t1.pa.c4.se[,2]),
        override.pval = list(fm.t1.pa.c1.se[,4], fm.t1.pa.c2.se[,4], fm.t1.pa.c3.se[,4], fm.t1.pa.c4.se[,4]))
