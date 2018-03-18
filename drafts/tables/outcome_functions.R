
devtools::source_url(paste0("https://raw.githubusercontent.com/iangow/",
                            "acct_data/master/code/cluster2.R"))
# Simple regressions ----
getFitted <- function(list) {
  temp <- list()
  for (i in 1:length(list)) {
    temp[[i]] <- list[[i]][[1]]
  }
  return(temp)
}

# Get standard errors
getSEs <- function(a.list) {
  temp <- list()
  for (i in 1:length(a.list)) {
    temp[[i]] <- a.list[[i]][[2]][,2]
  }
  return(temp)
}

# Get p-values
getPs <- function(a.list) {
  temp <- list()
  for (i in 1:length(a.list)) {
    temp[[i]] <- a.list[[i]][[2]][,4]
  }
  return(temp)
}

combineVars <- function(vars) {
  paste(unlist(strsplit(vars, "\\s+")), collapse=" + ")
}

ols.model <- function(data, lhs, rhs, cluster1) {
    model <- paste0(lhs, " ~ ", combineVars(rhs))
    fitted <- lm(model, data=data, na.action="na.exclude")
    return(list(fitted, coeftest.cluster(data, fitted, cluster1="permno")))
}

make.fTest.table <- function(model.set, data) {
    # require(parallel)

    fTest <- function(model) {
        model <- model[[1]]
        cov <- coeftest.cluster(data, model, cluster1="permno", ret="cov")
        c(linearHypothesis(model, "categoryactivism - categoryactivist_director",
                           vcov.=cov)[4][2,],
          linearHypothesis(model, "categoryactivism - categoryactivist_demand",
                           vcov.=cov)[4][2,],
          linearHypothesis(model, "categoryactivist_demand - categoryactivist_director",
                           vcov.=cov)[4][2,])
    }

    temp <-  do.call(cbind, lapply(model.set, FUN = fTest))
    # temp <-  do.call(cbind, mclapply(t6.pa, FUN = fTest, mc.cores=4))
    row.names(temp) <- c("Non-board activism = Activist director",
                         "Non-board activism = Board demand",
                         "Board demand = Activist director")
    return(as.data.frame(temp))
}

# Function to prepare a table of F-test p-values for
# inclusion by stargazer.
convertToLines <- function(ftable) {
    if(is.null(ftable)) return(NULL)

    # Convert the data frame to a list of rows
    temp <- split(ftable, rownames(ftable))

    # Convert a row from a data frame into a vector
    convertLine <- function(line) {
        c(rownames(line),
          formatC(unlist(line), format="f", digits=3))
    }

    # Make a header for the F-test portion of the table
    first.row <- list("", "F-tests for equal coefficients (p-values)", "\\hline")
    return(c(first.row, lapply(temp, convertLine), ""))
}

stargazer.mod <- function(model.set, col.labels, row.labels, omits, ftable=NULL) {
    stargazer(getFitted(model.set),
              dep.var.labels=col.labels,
              covariate.labels=row.labels,
              p=getPs(model.set),
              se=getSEs(model.set),
              align=TRUE, float=FALSE, no.space=TRUE,
              omit=c("^sic", "^year", omits),
              keep.stat=c("n", "adj.rsq"),
              omit.table.layout="n",
              font.size="small",
              add.lines=convertToLines(ftable))
}
xtable.mod <- function(summ) {
    print(xtable(summ, digits=3,
                 display=c("s", rep("f",(dim(summ)[2])))),
          include.rownames=TRUE,  include.colnames=TRUE, only.contents=TRUE,
          size="footnotesize", type="latex", sanitize.text.function=function(x){x},
          format.args = list(big.mark = ","))
}

# RHS of models
rhs.t6.1 <- "category year sic2"
rhs.t6.2 <- "activist_director year sic2 log_at"
rhs.t6.3 <- "activism activist_demand affiliated non_affiliated year sic2 "
rhs.t6.4 <- "early year sic2 log_at"
rhs.t6.5 <- "big_investment year sic2 log_at"
rhs.t6.6 <- "two_plus year sic2 log_at"

trim <- function (x) {
  # Function removes spaces at end or beginning
  # And removes multiple spaces
  x <- gsub("^\\s+|\\s+$", "", x)
  x <- gsub("\\s+", " ", x)
}

get.model <- function(the.var, data, include.lag=FALSE, changes=FALSE, use.controls=FALSE) {

    data <- within(data, {
        year <- as.factor(year)
        category <- as.factor(category)
        sic2 <- as.factor(sic2)
    })

    rhs <- trim(paste(rhs.t6.1, if(include.lag) "lagged.var", if(use.controls) controls))

    if(include.lag) {
        data$lagged.var <- data[, the.var]

        # Exclude lagged LHS from RHS if already there.
        rhs <- paste(setdiff(unlist(strsplit(rhs, "\\s+")), the.var), collapse=" ")
    }
  if (include.lag) {
    lhs <- paste0(the.var,"_p2")
  } else if (changes) {
    lhs <- paste0("(", the.var,"_p2 - ", the.var, ")")
  } else {
    lhs <- the.var
  }

  ols.model(data=data, lhs=lhs, rhs=rhs)
}

get.model.2 <- function(the.var, data, include.lag=FALSE, changes=FALSE, use.controls=FALSE) {

    data <- within(data, {
        year <- as.factor(year)
        category <- as.factor(category)
        sic2 <- as.factor(sic2)
    })

    rhs <- trim(paste(rhs.t6.1, if(include.lag) "lagged.var", if(use.controls) controls))

    if(include.lag) {
        data$lagged.var <- data[, the.var]

        # Exclude lagged LHS from RHS if already there.
        rhs <- paste(setdiff(unlist(strsplit(rhs, "\\s+")), the.var), collapse=" ")
    }
    if (include.lag) {
        lhs <- paste0(the.var,"_p2")
    } else if (changes) {
        lhs <- paste0("(", the.var,"_p2 - ", the.var, ")")
    } else {
        lhs <- the.var
    }

    ols.model(data=data, lhs=lhs, rhs=rhs)
}
