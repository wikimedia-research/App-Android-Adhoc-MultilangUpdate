pkgs <- c(
  "base",       # core workflow
  "memor",      # presentation
  "rmarkdown",  # presentation
  "knitr",      # presentation
  "kableExtra", # presentation
  "DBI",        # data workflow
  "dplyr",      # data workflow
  "jsonlite",   # data workflow
  "magrittr",   # data workflow
  "purrr",      # data workflow
  "tidyr",      # data workflow
  "wmf",        # data workflow
  "ggplot2"     # data visualization
)

# install.packages("bibtex")
bibtex::write.bib(pkgs, "report/packages.bib")
