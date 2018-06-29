pkgs <- c(
  "base",
  "rmarkdown",
  "knitr",
  "magrittr",
  "dplyr",
  "tidyr",
  "jsonlite",
  "ggplot2"
)

# install.packages("bibtex")
bibtex::write.bib(pkgs, "report/packages.bib")
