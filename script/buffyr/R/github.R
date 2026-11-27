bot_login <- "ropensci-review-bot"

issue_endpoint <- function(context, suffix = "") {
  sprintf("/repos/%s/issues/%s%s", context$repo, context$issue, suffix)
}

github_succeeds <- function(endpoint) {
  tryCatch(
    {
      gh::gh(endpoint)
      TRUE
    },
    error = function(e) FALSE
  )
}

read_github_file <- function(repo, path) {
  file <- gh::gh(sprintf("/repos/%s/contents/%s", repo, path))
  text <- rawToChar(jsonlite::base64_dec(gsub("\\s", "", file$content)))
  Encoding(text) <- "UTF-8"
  gsub("\r\n", "\n", text, fixed = TRUE)
}

github_file_exists <- function(repo, path) {
  github_succeeds(sprintf("/repos/%s/contents/%s", repo, path))
}

get_comments <- function(context) {
  comments <- gh::gh(issue_endpoint(context, "/comments"), per_page = 100, .limit = Inf, .progress = FALSE)
  purrr::list_rbind(purrr::map(comments, \(comment) data.frame(
    id = comment$id,
    user = comment$user$login,
    body = comment$body %||% "",
    url = comment$html_url
  ))) %||% data.frame(id = numeric(), user = character(), body = character(), url = character())
}

bot_replies_after <- function(comments, after_id) {
  comments[comments$user == bot_login & comments$id > after_id, , drop = FALSE]
}

find_bot_reply <- function(comments, pattern, after_id) {
  replies <- bot_replies_after(comments, after_id)
  matching <- replies[grepl(pattern, replies$body, ignore.case = TRUE, perl = TRUE), , drop = FALSE]
  if (nrow(matching) == 0) NULL else matching[1, ]
}

last_bot_reply <- function(comments, after_id) {
  replies <- bot_replies_after(comments, after_id)
  if (nrow(replies) == 0) NULL else replies[nrow(replies), ]
}

wait_for_bot_reply <- function(context, pattern, after_id, timeout) {
  started_at <- Sys.time()
  repeat {
    reply <- find_bot_reply(get_comments(context), pattern, after_id)
    if (!is.null(reply) || seconds_since(started_at) >= timeout) {
      return(reply)
    }
    Sys.sleep(context$poll_interval)
  }
}

post_comment <- function(context, body) {
  comment <- gh::gh(paste("POST", issue_endpoint(context, "/comments")), body = body)
  list(id = comment$id, url = comment$html_url)
}

post_bot_command <- function(context, command) {
  post_comment(context, bot_command(command))
}

bot_command <- function(command) {
  paste0("@", bot_login, " ", command)
}

get_issue <- function(context) {
  gh::gh(issue_endpoint(context))
}

close_issue <- function(context) {
  gh::gh(paste("PATCH", issue_endpoint(context)), state = "closed")
}

issue_labels <- function(issue) {
  purrr::map_chr(issue$labels, "name")
}

issue_field <- function(issue, field) {
  pattern <- sprintf("(?s)<!--%s-->(.*?)<!--end-%s-->", field, field)
  match <- regmatches(issue$body, regexec(pattern, issue$body, perl = TRUE))[[1]]
  if (length(match) < 2) "" else trimws(match[2])
}

has_label <- function(label) function(issue) label %in% issue_labels(issue)

lacks_label <- function(label) function(issue) !label %in% issue_labels(issue)

field_matches <- function(field, pattern) {
  function(issue) grepl(pattern, issue_field(issue, field), ignore.case = TRUE, perl = TRUE)
}

is_closed <- function(issue) identical(issue$state, "closed")

seconds_since <- function(time) {
  as.numeric(difftime(Sys.time(), time, units = "secs"))
}
