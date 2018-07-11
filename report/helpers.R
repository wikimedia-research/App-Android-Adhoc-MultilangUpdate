library(glue); library(magrittr); library(purrr); library(ggplot2)
import::from(scales, percent); import::from(polloi, compress)
import::from(wmf, percent2, pretty_num)
import::from(
  dplyr,
  mutate, arrange, desc, select, rename,
  group_by, ungroup, summarize, tally, top_n,
  left_join, right_join, keep_where = filter
)
import::from(tidyr, spread, gather)

data_mode <- function(x) {
  y <- table(x)
  return(names(y)[order(y, decreasing = TRUE)][1])
}

group_props <- function(grouped_df) {
  grouped_df %>%
    tally() %>%
    mutate(prop = n / sum(n)) %>%
    ungroup() %>%
    select(-n)
}

mono_relative <- function(proportioned_df, col) {
  # assumes 'status' column
  col_q <- rlang::enexpr(col)
  proportioned_df %>%
    group_by(!!col_q) %>%
    mutate(relative = (prop / prop[status == "Monolingual"]) - 1) %>%
    ungroup() %>%
    mutate(relative = ifelse(status == "Monolingual", NA, relative))
}

lang_ability <- function(x) {
  return(factor(
    dplyr::case_when(
      x == 1 ~ "Monolingual",
      x == 2 ~ "Bilingual",
      TRUE ~ "Multilingual (3+)"
    ),
    levels = c("Monolingual", "Bilingual", "Multilingual (3+)")
  ))
}

group_rows_v2 <- function(kable_input, group_label, index) {
  start_row <- min(index); end_row <- max(index)
  return(group_rows(kable_input, group_label, start_row, end_row))
}

seconds_to_duration <- function(x) {
  y <- lubridate::seconds_to_period(x)
  z <- data.frame(
    years = y@year,
    months = y@month,
    days = y@day,
    hours = y@hour,
    minutes = y@minute,
    seconds = floor(y@.Data)
  )
  z$seconds[floor(y@.Data) == 59] <- 0
  z$minutes[floor(y@.Data) == 59] <- z$minutes[floor(y@.Data) == 59] + 1
  time_units <- c("Y", "M", "D", "h", "m", "s")
  z <- apply(z, 1, paste0, time_units)
  z[z %in% paste0(0, time_units)] <- ""
  return(apply(z, 2, paste, collapse = ""))
}
