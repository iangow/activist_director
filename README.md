# Activist directors

This repository provides the code, data, and software instructions needed to compile the paper [Activist directors: determinants and consequences.](https://doi.org/10.1007/s11142-023-09767-8).

## Install required software

Assuming that you have the ability to install software, setting up your computer so that you can compile the paper in this repository is straightforward and takes just a few minutes.
We list the required steps below and also provide a video demonstrating some of these steps [here](https://www.youtube.com/watch?v=xRY6Y8qXUJ8).

1. Download and install R.
R is available for all major platforms (Windows, Linux, and MacOS) [here](https://cloud.r-project.org).

2. Download and install RStudio. 
An open-source version of RStudio is available [here](https://www.rstudio.com/products/rstudio/download/#download).

3. Install required packages from [CRAN](https://cran.r-project.org).
CRAN stands for "Comprehensive R Archive Network" and is the official repository for **packages** (also known as **libraries**) made available for R.
  In this course, we will make use of a number of R packages.
  These can be installed easily by running the following code in RStudio.^[You can copy and paste the code into the "Console" in RStudio.]

```r
install.packages(c("DBI", "duckdb", "base", "car", "doBy", "lfe", "lmtest",
                   "plm", "psych", "quantreg", "sandwich", "stargazer", 
                   "survival", "texreg", "tidyverse", "tinytex", "xtable", "zoo"))
```

4. Install LaTeX and required packages.

```r
tinytex::install_tinytex()
tinytex::tlmgr_install(c("harvard", "mathpazo", "courier","psnfss",
                         "hyperref" ,"natbib", "palatino", "paralist",
                         "parskip", "titlesec", "setspace", "pdflscape"))
```

5. Download this repository.

6. Open this repository in RStudio.
This will means opening the file `activist_director.Rproj` in RStudio.

7. Open the file `drafts/activist_directors.Rnw`.

8. Click "Compile PDF" in RStudio.

## Data

### Google Sheets

- [Activist directors](https://docs.google.com/spreadsheets/d/1zHSKIAx4LKURXav-k06D7T3p3St0VjFa8RXvAFJnUfI/edit#gid=271850810)
- [`missing_permnos`](https://docs.google.com/spreadsheets/d/1yGJtmSLy1hGT4Od1whGJB9SbghCEfpwjkrbsSwqMpAY/edit#gid=0)
- [`key_dates`](https://docs.google.com/spreadsheets/d/1s8-xvFxQZd6lMrxfVqbPTwUB_NQtvdxCO-s6QCIYvNk/edit#gid=1796687034)
