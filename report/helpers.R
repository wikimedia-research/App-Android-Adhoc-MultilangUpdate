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
    mutate(relative = (prop / prop[status == "monolingual"]) - 1) %>%
    ungroup() %>%
    mutate(relative = ifelse(status == "monolingual", NA, relative))
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
