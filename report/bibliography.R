pkgs <- c(
  "base",       # core workflow
  "memor",      # presentation
  "rmarkdown",  # presentation
  "knitr",      # presentation
  "kableExtra", # presentation
  "DBI",        # data workflow
  "dplyr",      # data workflow
  "forcats",    # data workflow
  "glue",       # data workflow
  "import",     # data workflow
  "jsonlite",   # data workflow
  "magrittr",   # data workflow
  "purrr",      # data workflow
  "tidyr",      # data workflow
  "wmf",        # data workflow
  "ggforce",    # data visualization
  "ggplot2"     # data visualization
)

# install.packages("bibtex")
bibtex::write.bib(pkgs, "report/packages.bib")
