# Connect to database ----
library(RPostgreSQL)
drv <- dbDriver("PostgreSQL")
pg <- dbConnect(drv, dbname = "crsp")

dir.data <- dbGetQuery(pg, "SELECT * FROM activist_director.equilar_all")

# Functions
library(psych)
require(texreg)
source("https://raw.githubusercontent.com/iangow/acct_data/master/code/cluster2.R")

# Create Variables and Winsorize ----
dir.data <- within(dir.data, {

    #### Winsorize variables

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
controls1 <- c("factor(year)", "factor(sic2)",
              "outsider", "age", "comp_committee", "audit_committee",
              "analyst", "inst", "size_return", "mv", "btm", "leverage", "dividend", "roa", "sale_growth")
controls2 <- c("factor(year)", "factor(sic2)",
               "age", "tenure_calc", "comp_committee", "audit_committee",
               "analyst", "inst", "size_return", "mv", "btm", "leverage", "dividend", "roa", "sale_growth")

# Set up models
lhs.t1.1 <- "own_p2"
rhs.t1.1 <- paste(c("activist_director", controls1), collapse=" + ")
model.t1.1 <- paste(lhs.t1.1, "~", rhs.t1.1)

reg.data <- subset(dir.data)
fm.t1.c1 <- lm(model.t1.1, data=reg.data, na.action="na.exclude")
fm.t1.c1.se <- coeftest.cluster(reg.data, fm.t1.c1, cluster1="permno")

reg.data <- subset(dir.data, director_first_years)
fm.t1.c2  <- lm(model.t1.1, data=reg.data, na.action="na.exclude")
fm.t1.c2.se <- coeftest.cluster(reg.data, fm.t1.c2, cluster1="permno")

reg.data <- subset(dir.data, outsider)
fm.t1.c3  <- lm(model.t1.1, data=reg.data, na.action="na.exclude")
fm.t1.c3.se <- coeftest.cluster(reg.data, fm.t1.c3, cluster1="permno")

reg.data <- subset(dir.data, director_first_years & outsider)
fm.t1.c4  <- lm(model.t1.1, data=reg.data, na.action="na.exclude")
fm.t1.c4.se <- coeftest.cluster(reg.data, fm.t1.c4, cluster1="permno")

reg.data <- subset(dir.data, director_first_years & activism_firm)
fm.t1.c5  <- lm(model.t1.1, data=reg.data, na.action="na.exclude")
fm.t1.c5.se <- coeftest.cluster(reg.data, fm.t1.c5, cluster1="permno")

reg.data <- subset(dir.data, director_first_years & activist_demand_firm)
fm.t1.c6  <- lm(model.t1.1, data=reg.data, na.action="na.exclude")
fm.t1.c6.se <- coeftest.cluster(reg.data, fm.t1.c6, cluster1="permno")

# Tabulate results
# Produce Excel file with results for Table 5
screenreg(list(fm.t1.c1, fm.t1.c2, fm.t1.c3, fm.t1.c4, fm.t1.c5, fm.t1.c6),
        # file="tables/count.doc",
        stars = c(0.01, 0.05, 0.1),
        caption="Table 1: Career Consequences for Activist Directors: Activism Firm Directorship",
        caption.above=TRUE,
        omit.coef = "((Intercept)|sic2|year)",
        custom.model.names = c("All Directors", "1st-Year Directors", "Independent", "1st-Yr Ind. Directors", "Activism Years", "Activist Demand Years"),
        override.se=  list(fm.t1.c1.se[,2], fm.t1.c2.se[,2], fm.t1.c3.se[,2], fm.t1.c4.se[,2], fm.t1.c5.se[,2], fm.t1.c6.se[,2]),
        override.pval= list(fm.t1.c1.se[,4], fm.t1.c2.se[,4], fm.t1.c3.se[,4], fm.t1.c4.se[,4], fm.t1.c5.se[,4], fm.t1.c6.se[,4]))

# Set up models
lhs.t2.1 <- "own_p2"
rhs.t2.1 <- paste(c("affiliated_director", "unaffiliated_director", controls1), collapse=" + ")
model.t2.1 <- paste(lhs.t2.1, "~", rhs.t2.1)

reg.data <- subset(dir.data)
fm.t2.c1 <- lm(model.t2.1, data=reg.data, na.action="na.exclude")
fm.t2.c1.se <- coeftest.cluster(reg.data, fm.t2.c1, cluster1="permno")

reg.data <- subset(dir.data, director_first_years)
fm.t2.c2  <- lm(model.t2.1, data=reg.data, na.action="na.exclude")
fm.t2.c2.se <- coeftest.cluster(reg.data, fm.t2.c2, cluster1="permno")

reg.data <- subset(dir.data, outsider)
fm.t2.c3  <- lm(model.t2.1, data=reg.data, na.action="na.exclude")
fm.t2.c3.se <- coeftest.cluster(reg.data, fm.t2.c3, cluster1="permno")

reg.data <- subset(dir.data, director_first_years & outsider)
fm.t2.c4  <- lm(model.t2.1, data=reg.data, na.action="na.exclude")
fm.t2.c4.se <- coeftest.cluster(reg.data, fm.t2.c4, cluster1="permno")

reg.data <- subset(dir.data, director_first_years & activism_firm)
fm.t2.c5  <- lm(model.t2.1, data=reg.data, na.action="na.exclude")
fm.t2.c5.se <- coeftest.cluster(reg.data, fm.t2.c5, cluster1="permno")

reg.data <- subset(dir.data, director_first_years & activist_demand_firm)
fm.t2.c6  <- lm(model.t2.1, data=reg.data, na.action="na.exclude")
fm.t2.c6.se <- coeftest.cluster(reg.data, fm.t2.c6, cluster1="permno")

# Tabulate results
# Produce Excel file with results for Table 5
screenreg(list(fm.t2.c1, fm.t2.c2, fm.t2.c3, fm.t2.c4, fm.t2.c5, fm.t2.c6),
          # file="tables/count.doc",
          stars = c(0.01, 0.05, 0.1),
          caption="Table 2: Career Consequences for Activist Directors: Activism Firm Directorship",
          caption.above=TRUE,
          omit.coef = "((Intercept)|sic2|year)",
          custom.model.names = c("All Directors", "1st-Year Directors", "Independent", "1st-Yr Ind. Directors", "Activism Years", "Activist Demand Years"),
          override.se=  list(fm.t2.c1.se[,2], fm.t2.c2.se[,2], fm.t2.c3.se[,2], fm.t2.c4.se[,2], fm.t2.c5.se[,2], fm.t2.c6.se[,2]),
          override.pval= list(fm.t2.c1.se[,4], fm.t2.c2.se[,4], fm.t2.c3.se[,4], fm.t2.c4.se[,4], fm.t2.c5.se[,4], fm.t2.c6.se[,4]))

# Set up models
lhs.t3.1 <- "other_p2"
rhs.t3.1 <- paste(c("other_boards", "activist_director", controls1), collapse=" + ")
model.t3.1 <- paste(lhs.t3.1, "~", rhs.t3.1)

lhs.t3.2 <- "other_p2"
rhs.t3.2 <- paste(c("other_boards", "affiliated_director", "unaffiliated_director", controls1), collapse=" + ")
model.t3.2 <- paste(lhs.t3.2, "~", rhs.t3.2)

reg.data <- subset(dir.data)
fm.t3.c1 <- lm(model.t3.1, data=reg.data, na.action="na.exclude")
fm.t3.c1.se <- coeftest.cluster(reg.data, fm.t3.c1, cluster1="permno")

reg.data <- subset(dir.data, director_first_years)
fm.t3.c2  <- lm(model.t3.1, data=reg.data, na.action="na.exclude")
fm.t3.c2.se <- coeftest.cluster(reg.data, fm.t3.c2, cluster1="permno")

reg.data <- subset(dir.data, outsider)
fm.t3.c3  <- lm(model.t3.1, data=reg.data, na.action="na.exclude")
fm.t3.c3.se <- coeftest.cluster(reg.data, fm.t3.c3, cluster1="permno")

reg.data <- subset(dir.data, director_first_years & outsider)
fm.t3.c4  <- lm(model.t3.1, data=reg.data, na.action="na.exclude")
fm.t3.c4.se <- coeftest.cluster(reg.data, fm.t3.c4, cluster1="permno")

reg.data <- subset(dir.data, director_first_years & activism_firm)
fm.t3.c5  <- lm(model.t3.1, data=reg.data, na.action="na.exclude")
fm.t3.c5.se <- coeftest.cluster(reg.data, fm.t3.c5, cluster1="permno")

reg.data <- subset(dir.data, director_first_years & activist_demand_firm)
fm.t3.c6  <- lm(model.t3.1, data=reg.data, na.action="na.exclude")
fm.t3.c6.se <- coeftest.cluster(reg.data, fm.t3.c6, cluster1="permno")

# Tabulate results
# Produce Excel file with results for Table 5
screenreg(list(fm.t3.c1, fm.t3.c2, fm.t3.c3, fm.t3.c4, fm.t3.c5, fm.t3.c6),
          # file="tables/count.doc",
          stars = c(0.01, 0.05, 0.1),
          caption="Table 3: Career Consequences for Activist Directors: Other Directorships",
          caption.above=TRUE,
          omit.coef = "((Intercept)|sic2|year)",
          custom.model.names = c("All Directors", "1st-Year Directors", "Independent", "1st-Yr Ind. Directors", "Activism Years", "Activist Demand Years"),
          override.se=  list(fm.t3.c1.se[,2], fm.t3.c2.se[,2], fm.t3.c3.se[,2], fm.t3.c4.se[,2], fm.t3.c5.se[,2], fm.t3.c6.se[,2]),
          override.pval= list(fm.t3.c1.se[,4], fm.t3.c2.se[,4], fm.t3.c3.se[,4], fm.t3.c4.se[,4], fm.t3.c5.se[,4], fm.t3.c6.se[,4]))

# Set up models
lhs.t4.1 <- "other_p2"
rhs.t4.1 <- paste(c("other_boards", "affiliated_director", "unaffiliated_director", controls1), collapse=" + ")
model.t4.1 <- paste(lhs.t4.1, "~", rhs.t4.1)

reg.data <- subset(dir.data)
fm.t4.c1 <- lm(model.t4.1, data=reg.data, na.action="na.exclude")
fm.t4.c1.se <- coeftest.cluster(reg.data, fm.t4.c1, cluster1="permno")

reg.data <- subset(dir.data, director_first_years)
fm.t4.c2  <- lm(model.t4.1, data=reg.data, na.action="na.exclude")
fm.t4.c2.se <- coeftest.cluster(reg.data, fm.t4.c2, cluster1="permno")

reg.data <- subset(dir.data, outsider)
fm.t4.c3  <- lm(model.t4.1, data=reg.data, na.action="na.exclude")
fm.t4.c3.se <- coeftest.cluster(reg.data, fm.t4.c3, cluster1="permno")

reg.data <- subset(dir.data, director_first_years & outsider)
fm.t4.c4  <- lm(model.t4.1, data=reg.data, na.action="na.exclude")
fm.t4.c4.se <- coeftest.cluster(reg.data, fm.t4.c4, cluster1="permno")

reg.data <- subset(dir.data, director_first_years & activism_firm)
fm.t4.c5  <- lm(model.t4.1, data=reg.data, na.action="na.exclude")
fm.t4.c5.se <- coeftest.cluster(reg.data, fm.t4.c5, cluster1="permno")

reg.data <- subset(dir.data, director_first_years & activist_demand_firm)
fm.t4.c6  <- lm(model.t4.1, data=reg.data, na.action="na.exclude")
fm.t4.c6.se <- coeftest.cluster(reg.data, fm.t4.c6, cluster1="permno")

# Tabulate results
# Produce Excel file with results for Table 5
screenreg(list(fm.t4.c1, fm.t4.c2, fm.t4.c3, fm.t4.c4, fm.t4.c5, fm.t4.c6),
          # file="tables/count.doc",
          stars = c(0.01, 0.05, 0.1),
          caption="Table 4: Career Consequences for Activist Directors: Other Directorships",
          caption.above=TRUE,
          omit.coef = "((Intercept)|sic2|year)",
          custom.model.names = c("All Directors", "1st-Year Directors", "Independent", "1st-Yr Ind. Directors", "Activism Years", "Activist Demand Years"),
          override.se=  list(fm.t4.c1.se[,2], fm.t4.c2.se[,2], fm.t4.c3.se[,2], fm.t4.c4.se[,2], fm.t4.c5.se[,2], fm.t4.c6.se[,2]),
          override.pval= list(fm.t4.c1.se[,4], fm.t4.c2.se[,4], fm.t4.c3.se[,4], fm.t4.c4.se[,4], fm.t4.c5.se[,4], fm.t4.c6.se[,4]))
