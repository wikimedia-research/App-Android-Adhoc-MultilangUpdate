if (!dir.exists("data")) dir.create("data")

# ssh -N stat6 -L 3307:db1108.eqiad.wmnet:3306
con <- DBI::dbConnect(RMySQL::MySQL(), host = "127.0.0.1", group = "client", dbname = "log", port = 3307)

library(glue); library(magrittr)

common_cols <- "uuid, timestamp, event_app_install_id, event_client_dt"

# Language settings and searching
language_searches <- "SELECT
  {common_cols}, event_session_token,
  event_language, event_added, event_time_spent,
  NOT (event_search_string IS NULL OR event_search_string = '') AS searched
FROM MobileWikiAppLanguageSearching_18113721" %>%
  glue() %>%
  wmf::mysql_read(con = con) %>%
  wmf::refine_eventlogs(dt_cols = c("timestamp", "event_client_dt")) %>%
  dplyr::group_by(app_install_id, session_token) %>%
  dplyr::summarize(
    times_searched_for_language = sum(searched),
    languages_added_from_search = sum(added),
    total_time_spent_searching = sum(time_spent)
  ) %>%
  dplyr::ungroup()
"SELECT
  {common_cols}, event_session_token,
  event_source, event_initial, event_final, event_searched, event_interactions
FROM MobileWikiAppLanguageSettings_18113720" %>%
  glue %>%
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
  dplyr::ungroup() %>%
  dplyr::left_join(language_searches, by = c("app_install_id", "session_token")) %T>%
  View("language_settings") %>%
  readr::write_rds("data/language_settings.rds")

# Session summary
"SELECT
  {common_cols},
  event_languages, event_totalPages AS total_pages, event_length AS session_length
FROM MobileWikiAppSessions_18115099" %>%
  glue() %>%
  wmf::mysql_read(con = con) %>%
  wmf::refine_eventlogs(dt_cols = c("timestamp", "event_client_dt"), json_cols = "event_languages") %>%
  readr::write_rds("data/session_summaries.rds")

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
"SELECT
  {common_cols},
  event_languages, event_source, event_enabled_list, event_order_list, event_time_spent
FROM MobileWikiAppFeedConfigure_18126175" %>%
  glue() %>%
  wmf::mysql_read(con = con) %>%
  wmf::refine_eventlogs(
    dt_cols = c("timestamp", "event_client_dt"),
    json_cols = c("event_languages", "event_enabled_list", "event_order_list")
  ) %>%
  dplyr::mutate(source = card_types[as.character(source)]) %T>%
  View("feed_customization") %>%
  readr::write_rds("data/feed_customization.rds")

# Feed engagement
"SELECT
  {common_cols}, event_session_token,
  event_time_spent, event_action
FROM MobileWikiAppFeed_18115458
WHERE event_action IN('enter', 'exit', 'cardShown', 'cardClicked', 'more')" %>%
  glue() %>%
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
  View("feed_sessions") %>%
  readr::write_rds("data/feed_sessions.rds")
"SELECT
  uuid, timestamp, event_client_dt, event_app_install_id, event_session_token,
  event_time_spent, event_language, event_cardType AS card_type,
  IF(event_action = 'cardShown', 'impression', 'click') AS event
FROM MobileWikiAppFeed_18115458
WHERE event_action IN('cardShown', 'cardClicked')" %>%
  glue() %>%
  wmf::mysql_read(con = con) %>%
  wmf::refine_eventlogs(dt_cols = c("timestamp", "event_client_dt")) %>%
  dplyr::mutate(card_type = card_types[as.character(card_type)]) %>%
  dplyr::group_by(app_install_id, session_token, card_type, language) %>%
  dplyr::summarize(
    time_spent = max(time_spent),
    clickthrough = all(c("impression", "click") %in% event)
  ) %>%
  dplyr::ungroup() %T>%
  View("card_clickthroughs") %>%
  readr::write_rds("data/card_clickthroughs.rds")

# Search
language_switching <- "SELECT {common_cols}, event_session_token, event_language
FROM MobileWikiAppSearch_18144266
WHERE event_action = 'langswitch' AND event_language IS NOT NULL" %>%
  glue() %>%
  wmf::mysql_read(con = con) %>%
  wmf::refine_eventlogs(dt_cols = c("timestamp", "event_client_dt")) %>%
  tidyr::extract(language, c("from_language", "to_language"), "(.*)\\>(.*)") %T>%
  View("search_langswitches") %>%
  readr::write_rds("data/search_langswitches.rds")
"SELECT
  {common_cols}, event_session_token,
  event_action, event_number_of_results
FROM MobileWikiAppSearch_18144266
WHERE event_action IN('start', 'results', 'click', 'cancel', 'langswitch')" %>%
  glue() %>%
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
  View("search_sessions") %>%
  readr::write_rds("data/search_sessions.rds")

DBI::dbDisconnect(con)
