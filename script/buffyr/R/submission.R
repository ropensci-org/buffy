open_submission <- function(context) {
  context$title <- sprintf(
    "%s smoke test %s (buffy %s)",
    context$package_name,
    format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    git_commit("HEAD")
  )
  issue <- gh::gh(
    sprintf("POST /repos/%s/issues", context$repo),
    title = context$title,
    body = submission_body(context)
  )
  context$issue <- issue$number
  context$issue_url <- issue$html_url
  context$opened_at <- Sys.time()
  cli::cli_alert_success("Opened {.url {context$issue_url}}")
  utils::browseURL(context$issue_url)
  context
}

use_existing_issue <- function(context, number) {
  context$issue <- number
  issue <- get_issue(context)
  context$issue_url <- issue$html_url
  context$title <- issue$title
  context$opened_at <- Sys.time()
  cli::cli_alert_warning("Reusing {.url {context$issue_url}}: steps can fail if the issue isn't fresh")
  context
}

submission_body <- function(context) {
  template <- read_github_file(context$repo, ".github/ISSUE_TEMPLATE/A-submit-software-for-review.md")
  description <- read_github_file(context$package_repo, "DESCRIPTION")
  version <- sub("^Version:\\s*", "", grep("^Version:", strsplit(description, "\n")[[1]], value = TRUE)[1])

  body <- sub("(?s)^---\n.*?\n---\n", "", template, perl = TRUE)
  body <- replace_field(body, "author1", paste0("@", context$user))
  body <- replace_field(body, "author-others", "")
  body <- replace_field(body, "repourl", context$package_url)
  body <- sub("Submitting Author Name:[^\n]*", paste("Submitting Author Name:", context$user, "(smoke test)"), body)
  body <- sub("Version submitted:[^\n]*", paste("Version submitted:", version), body)
  insert_after(body, "Paste the full DESCRIPTION[^\n]*\n\\s*```\n", paste0(trimws(description, "right"), "\n"))
}

replace_field <- function(body, field, value) {
  sub(
    sprintf("<!--%s-->.*?<!--end-%s-->", field, field),
    sprintf("<!--%s-->%s<!--end-%s-->", field, value, field),
    body,
    perl = TRUE
  )
}

insert_after <- function(text, pattern, insertion) {
  match <- regexpr(pattern, text, perl = TRUE)
  if (match == -1) {
    return(text)
  }
  end <- match + attr(match, "match.length") - 1
  paste0(substr(text, 1, end), insertion, substr(text, end + 1, nchar(text)))
}

git_commit <- function(ref) {
  commit <- tryCatch(
    suppressWarnings(system2("git", c("rev-parse", "--short", ref), stdout = TRUE, stderr = FALSE)),
    error = function(e) character()
  )
  if (length(commit) == 1) commit else "unknown"
}
