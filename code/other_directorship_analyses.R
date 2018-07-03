# Connect to database ----
library(RPostgreSQL)
drv <- dbDriver("PostgreSQL")
pg <- dbConnect(drv, dbname = "crsp")

other.dir.data <- dbGetQuery(pg, "

    WITH num_boards AS (
        SELECT DISTINCT executive_id, extract(year FROM period) AS year, count(*)
        FROM activist_director.equilar_w_activism
        GROUP BY executive_id, extract(year FROM period)
        ORDER BY executive_id, YEAR),

    master AS (
        SELECT DISTINCT a.executive_id, b.YEAR
        FROM (SELECT DISTINCT executive_id FROM activist_director.equilar_w_activism) AS a,
        (SELECT DISTINCT extract(YEAR FROM period) AS YEAR FROM activist_director.equilar_w_activism) AS b
        ORDER BY executive_id, YEAR),

    merged AS (
        SELECT DISTINCT a.executive_id, a.YEAR, COALESCE(count,0) AS count
        FROM master AS a
        LEFT JOIN num_boards AS b
        ON a.executive_id=b.executive_id AND a.YEAR=b.YEAR
        ORDER BY executive_id, YEAR),

    lead_lag AS (
        SELECT DISTINCT executive_id, YEAR,
        lag(count,5) OVER w AS count_m5,
        lag(count,4) OVER w AS count_m4,
        lag(count,3) OVER w AS count_m3,
        lag(count,2) OVER w AS count_m2,
        lag(count,1) OVER w AS count_m1,
        count,
        lead(count,1) OVER w AS count_p1,
        lead(count,2) OVER w AS count_p2,
        lead(count,3) OVER w AS count_p3,
        lead(count,4) OVER w AS count_p4,
        lead(count,5) OVER w AS count_p5
        FROM merged AS a
        WINDOW w AS (PARTITION BY executive_id ORDER BY year)
        ORDER BY executive_id, year),

    merged2 AS (
        SELECT DISTINCT a.company_id, a.executive_id, a.period, extract(year from period) AS year,
                activist_director, CASE WHEN activist_director IS FALSE THEN NULL ELSE affiliated_director END AS affiliated_director,
                count_m5, count_m4, count_m3, count_m2, count_m1, count,
                count_p1, count_p2, count_p3, count_p4, count_p5,
                age, tenure, tenure_calc, female, male, outsider, insider, comp_committee, audit_committee, activist_director_firm, director_first_year
        FROM activist_director.equilar_w_activism AS a
        LEFT JOIN lead_lag AS b
        ON a.executive_id=b.executive_id AND extract(YEAR FROM a.period)=b.YEAR
        ORDER BY company_id, executive_id, period),

    permnos AS (
        SELECT DISTINCT permno, company_id, fye AS period
        FROM equilar_hbs.company_financials AS a
        INNER JOIN activist_director.permnos AS b
        ON substr(a.cusip,1,8)=b.ncusip
        ORDER BY permno, period)

    SELECT DISTINCT b.permno, a.*, c.analyst, c.inst, c.size_return, c.mv, c.btm, c.leverage, c.dividend, c.roa, c.sale_growth, c.payout, c.sic2
    FROM merged2 AS a
    INNER JOIN permnos AS b
    ON a.company_id=b.company_id AND a.period=b.period
    LEFT JOIN activist_director.outcome_controls AS c
    ON b.permno=c.permno AND a.period=c.datadate
    ORDER BY permno, executive_id, period
")

# Functions
library(psych)
require(texreg)
source("https://raw.githubusercontent.com/iangow/acct_data/master/code/cluster2.R")

# Create Variables and Winsorize ----
other.dir.data <- within(other.dir.data, {

    # Calculate indicators

    activist_director <- ifelse(is.na(activist_director), FALSE, activist_director)

##### Winsorize variables
    # bv <- winsor(bv, trim=0.01)
    mv <- winsor(mv, trim=0.01)
    btm <- winsor(btm, trim=0.01)
    leverage <- winsor(leverage, trim=0.01)
    # capex <- winsor(capex, trim=0.01)
    # rnd <- winsor(rnd, trim=0.01)
    dividend <- winsor(dividend, trim=0.01)
    payout <- winsor(payout, trim=0.01)
    roa <- winsor(roa, trim=0.01)
    sale_growth <- winsor(sale_growth, trim=0.01)
    inst <- winsor(inst, trim=0.01)
})

controls <- c("factor(year)", "factor(sic2)",
              "outsider", "age", "tenure_calc", "comp_committee", "audit_committee",
              "analyst", "inst", "size_return", "mv", "btm", "leverage", "dividend", "roa", "sale_growth")
controls2 <- c("factor(year)", "factor(sic2)",
               "age", "tenure_calc", "comp_committee", "audit_committee",
               "analyst", "inst", "size_return", "mv", "btm", "leverage", "dividend", "roa", "sale_growth")

# Set up models
target_inds <- "activist_director"
target_vars <- target_inds

lhs.t5 <- "count_p2"
rhs.t5.1 <- paste(c("count", target_vars, controls), collapse=" + ")
model.t5.1 <- paste(lhs.t5, "~", rhs.t5.1)

reg.data <- subset(other.dir.data)
fm.t5.c1 <- lm(model.t5.1, data=reg.data, na.action="na.exclude")
fm.t5.c1.se <- coeftest.cluster(reg.data, fm.t5.c1, cluster1="permno")
# fm.t5.c1.cov <- coeftest.cluster(reg.data, fm.t5.c1, cluster1="permno", ret="cov")

reg.data <- subset(other.dir.data, director_first_year)
fm.t5.c2  <- lm(model.t5.1, data=reg.data, na.action="na.exclude")
fm.t5.c2.se <- coeftest.cluster(reg.data, fm.t5.c2, cluster1="permno")

reg.data <- subset(other.dir.data, outsider)
fm.t5.c3  <- lm(model.t5.1, data=reg.data, na.action="na.exclude")
fm.t5.c3.se <- coeftest.cluster(reg.data, fm.t5.c3, cluster1="permno")

reg.data <- subset(other.dir.data, director_first_year & outsider)
fm.t5.c4  <- lm(model.t5.1, data=reg.data, na.action="na.exclude")
fm.t5.c4.se <- coeftest.cluster(reg.data, fm.t5.c4, cluster1="permno")

# Tabulate results
# Produce Excel file with results for Table 5
screenreg(list(fm.t5.c1, fm.t5.c2, fm.t5.c3, fm.t5.c4),
        # file="tables/count.doc",
        stars = c(0.01, 0.05, 0.1),
        caption="Table 5: Effects on other directorships",
        caption.above=TRUE,
        omit.coef = "((Intercept)|sic2|year)",
        custom.model.names = c("All Directors", "1st-Year Directors", "Independent", "1st-Yr Ind. Directors"),
        override.se=  list(fm.t5.c1.se[,2], fm.t5.c2.se[,2], fm.t5.c3.se[,2], fm.t5.c4.se[,2]),
        override.pval= list(fm.t5.c1.se[,4], fm.t5.c2.se[,4], fm.t5.c3.se[,4], fm.t5.c4.se[,4]))
