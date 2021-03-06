if (!dir.exists("data")) dir.create("data")

# Enable/disable viewing of data as it will be written
view_data <- FALSE
view <- function(x, title) {
  if (view_data) {
    View(x, title)
  }
}

# ssh -N stat6 -L 3307:db1108.eqiad.wmnet:3306
con <- DBI::dbConnect(RMySQL::MySQL(), host = "127.0.0.1", group = "client", dbname = "log", port = 3307)

library(glue); library(magrittr)

common_cols <- "timestamp, event_app_install_id, event_client_dt"

earliest_version <- "2.7.236-r-2018-06-25"
earliest_date <- "20180625"
latest_date <- "20180709"
where_clause <- "WHERE timestamp >= '${earliest_date}' -- release
  AND timestamp < '${latest_date}' -- 2 weeks after release
  AND INSTR(userAgent, '-r-') > 0
  AND REGEXP_SUBSTR(userAgent, '[0-9].[0-9].[0-9]{3}-[a-z]+-[0-9]{4}-[0-9]{2}-[0-9]{2}') >= '${earliest_version}'" %>%
  glue(.open = "${")

# Language settings and searching
language_searches <- "SELECT
  ${common_cols}, event_session_token,
  event_language, event_added, event_time_spent,
  NOT (event_search_string IS NULL OR event_search_string = '') AS searched
FROM MobileWikiAppLanguageSearching_18113721
${where_clause}" %>%
  glue(.open = "${") %>%
  wmf::mysql_read(con = con) %>%
  wmf::refine_eventlogs(dt_cols = c("timestamp", "event_client_dt")) %>%
  dplyr::group_by(app_install_id, session_token) %>%
  dplyr::summarize(
    times_searched_for_language = sum(searched),
    languages_added_from_search = sum(added),
    total_time_spent_searching = sum(time_spent)
  ) %>%
  dplyr::ungroup() %T>%
  view("language_searching") %>%
  readr::write_rds("data/language_searching.rds")
"SELECT
  ${common_cols}, event_session_token,
  event_source, event_initial, event_final, event_interactions
FROM MobileWikiAppLanguageSettings_18113720
${where_clause}" %>%
  glue(.open = "${") %>%
  wmf::mysql_read(con = con) %>%
  wmf::refine_eventlogs(
    dt_cols = c("timestamp", "event_client_dt"),
    json_cols = c("event_initial", "event_final")
  ) %>%
  dplyr::group_by(app_install_id, session_token) %>%
  dplyr::mutate(
    n_initial = length(initial[[1]]), n_final = length(final[[1]]),
    additions = sum(!final[[1]] %in% initial[[1]]),
    removals = sum(!initial[[1]] %in% final[[1]]),
    changed_primary = initial[[1]][1] != final[[1]][1],
    added = additions > 0, removed = removals > 0
  ) %>%
  dplyr::ungroup() %T>%
  view("language_settings") %>%
  readr::write_rds("data/language_settings.rds")

# Feed customization
card_types <- c(
  "-1" = "main menu",
  "0" = "search bar",
  "1" = "continue reading",
  "2" = "\"because you read\" list",
  "3" = "\"most read\" list",
  "4" = "featured article card",
  "5" = "random card",
  "6" = "main page card",
  "7" = "news list",
  "8" = "featured image card",
  # sub-cards that don't provide a path into customization:
  "9" = "\"because you read\" item",
  "10" = "\"most read\" item",
  "11" = "news item",
  "12" = "news item link",
  "13" = "announcement",
  "14" = "survey",
  "15" = "fundraising",
  "17" = "onboarding (offline)",
  "18" = "on this day card",
  "19" = "onboarding - customize feed", # onboarding card that initially tells the user about customization,
  "20" = "onboarding - reading list sync",
  "97" = "day header",
  "98" = "offline",
  "99" = "progress"
)
feed_cards <- c(
  "0" = "In the news",
  "1" = "On this day",
  "2" = "Continue reading",
  "3" = "Trending",
  "4" = "Today on Wikipedia",
  "5" = "Randomizer",
  "6" = "Featured article",
  "7" = "Picture of the day",
  "8" = "Because you read"
)
"SELECT
  ${common_cols},
  event_languages, event_source, event_time_spent, event_enabled_list, event_order_list
FROM MobileWikiAppFeedConfigure_18126175
${where_clause}
  AND event_time_spent >= 0" %>%
  glue(.open = "${") %>%
  wmf::mysql_read(con = con) %>%
  wmf::refine_eventlogs(
    dt_cols = c("timestamp", "event_client_dt"),
    json_cols = c("event_languages", "event_enabled_list", "event_order_list")
  ) %>%
  dplyr::mutate(
    source = card_types[as.character(source)],
    enabled_list = lapply(enabled_list, purrr::map, ~ unname(feed_cards[.x == 1])),
    order_list = purrr::map(order_list, ~ unname(feed_cards[as.character(.x)])),
    enabled_list_v2 = purrr::map(enabled_list, wmf::invert_list)
  ) %T>%
  view("feed_customization") %>%
  readr::write_rds("data/feed_customization.rds")

# Feed engagement
"SELECT
  ${common_cols}, event_session_token,
  event_time_spent, event_action
FROM MobileWikiAppFeed_18115458
${where_clause}
  AND event_action IN('enter', 'exit', 'cardShown', 'cardClicked', 'more')" %>%
  glue(.open = "${") %>%
  wmf::mysql_read(con = con) %>%
  wmf::refine_eventlogs(dt_cols = c("timestamp", "event_client_dt")) %>%
  dplyr::group_by(app_install_id, session_token) %>%
  dplyr::summarize(
    valid = all(c("enter", "exit") %in% action),
    engaged = any(c("cardClicked", "more") %in% action),
    cards_in_feed = any(action == "cardShown"),
    clicked = all(c("cardShown", "cardClicked") %in% action),
    session_length = difftime(max(client_dt), min(client_dt), units = "secs"),
    total_time_spent = sum(time_spent),
    longest_time_spent = max(time_spent),
    shorted_time_spent = ifelse(all(time_spent == 0), NA, min(time_spent[time_spent > 0])),
    n_backtracks = sum(action == "enter") - 1
  ) %>%
  dplyr::ungroup() %>%
  dplyr::filter(valid) %>%
  dplyr::select(-valid) %>%
  dplyr::ungroup() %T>%
  view("feed_sessions") %>%
  readr::write_rds("data/feed_sessions.rds")
"SELECT
  timestamp, event_client_dt, event_app_install_id, event_session_token,
  event_time_spent, event_language, event_cardType AS card_type,
  IF(event_action = 'cardShown', 'impression', 'click') AS event
FROM MobileWikiAppFeed_18115458
${where_clause}
  AND event_action IN('cardShown', 'cardClicked')
  AND event_time_spent >= 0" %>%
  glue(.open = "${") %>%
  wmf::mysql_read(con = con) %>%
  wmf::refine_eventlogs(dt_cols = c("timestamp", "event_client_dt")) %>%
  dplyr::mutate(card_type = unname(card_types[as.character(card_type)])) %>%
  dplyr::group_by(app_install_id, session_token, card_type, language) %>%
  dplyr::summarize(
    time_spent = max(time_spent),
    clicks = sum(event == "click"),
    impressions = sum(event == "impression"),
    clickthrough = "click" %in% event,
    valid = "impression" %in% event
  ) %>%
  dplyr::ungroup() %>%
  {
    message("Filtering out ", sum(.$valid), " invalid events.")
    dplyr::select(dplyr::filter(., valid), -valid)
  } %T>%
  view("card_clickthroughs") %>%
  readr::write_rds("data/card_clickthroughs.rds")

# Search
language_switching <- "SELECT ${common_cols}, event_session_token, event_language
FROM MobileWikiAppSearch_18144266
${where_clause}
  AND event_action = 'langswitch'
  AND event_language IS NOT NULL" %>%
  glue(.open = "${") %>%
  wmf::mysql_read(con = con) %>%
  wmf::refine_eventlogs(dt_cols = c("timestamp", "event_client_dt")) %>%
  tidyr::extract(language, c("from_language", "to_language"), "(.*)\\>(.*)") %T>%
  view("search_langswitches") %>%
  readr::write_rds("data/search_langswitches.rds")
"SELECT
  ${common_cols}, event_session_token,
  event_action, event_number_of_results
FROM MobileWikiAppSearch_18144266
${where_clause}
  AND event_action IN('start', 'results', 'click', 'cancel', 'langswitch')" %>%
  glue(.open = "${") %>%
  wmf::mysql_read(con = con) %>%
  wmf::refine_eventlogs(dt_cols = c("timestamp", "event_client_dt")) %>%
  dplyr::arrange(app_install_id, session_token, client_dt, action) %>%
  dplyr::distinct(app_install_id, session_token, client_dt, action, .keep_all = TRUE) %>%
  dplyr::group_by(app_install_id, session_token) %>%
  dplyr::summarize(
    session_length = difftime(max(client_dt), min(client_dt), units = "secs"),
    saw_results = any(number_of_results > 0, na.rm = TRUE),
    clicked = any(action == "click"), abandoned = any(action == "cancel"),
    language_switches = sum(action == "langswitch"),
    events = n(), valid = any(action == "start")
  ) %>%
  dplyr::ungroup() %>%
  dplyr::filter(events > 1, valid) %>%
  dplyr::select(-c(events, valid)) %T>%
  view("search_sessions") %>%
  readr::write_rds("data/search_sessions.rds")

# Session summary
"SELECT
  ${common_cols},
  event_languages, event_totalPages AS total_pages, event_length AS session_length
FROM MobileWikiAppSessions_18115099
${where_clause}
  AND event_length >= 0" %>%
  glue(.open = "${") %>%
  wmf::mysql_read(con = con) %>%
  wmf::refine_eventlogs(dt_cols = c("timestamp", "event_client_dt"), json_cols = "event_languages") %>%
  dplyr::mutate(n_languages = purrr::map_int(languages, length)) %>%
  dplyr::arrange(app_install_id, client_dt, timestamp) %>%
  readr::write_rds("data/sessions.rds")

DBI::dbDisconnect(con)
