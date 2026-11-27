#' Check your setup before running the smoke test
#'
#' Run this before [test_buffy()]. Reports your GitHub setup, checks that you
#' are a ropensci editor and not logged in as the bot, that the Airtable
#' credentials work, and that the test repository has the bot templates.
#'
#' @inheritParams test_buffy
#'
#' @return Invisibly, `TRUE` if no problem was found.
#' @export
buffy_test_sitrep <- function(repo = "ropenscilabs/statistical-software-review", airtable = TRUE) {
  usethis::git_sitrep(tool = "github", scope = "user")
  cli::cli_h2("buffyr")
  check_prerequisites(gh::gh("/user")$login, repo, airtable)
}

check_prerequisites <- function(user, repo, airtable) {
  if (identical(user, bot_login)) {
    cli::cli_abort("You are logged in as {.val {bot_login}}, whose commands are ignored. Log in as yourself.")
  }
  editor_membership <- sprintf("/orgs/ropensci/teams/editors/memberships/%s", user)
  is_editor <- tryCatch(identical(gh::gh(editor_membership)$state, "active"), error = function(e) FALSE)
  if (is_editor) {
    cli::cli_alert_success("{.val {user}} is a ropensci editor.")
  } else {
    cli::cli_alert_warning("Could not confirm that {.val {user}} is a ropensci editor: editor-only commands may be refused.")
  }

  if (airtable) check_airtable_access()

  missing_templates <- purrr::discard(
    file.path(".buffy/templates", c("badge.md", "approved.md")),
    \(path) github_file_exists(repo, path)
  )
  if (length(missing_templates) == 0) {
    cli::cli_alert_success("{.val {repo}} has the bot templates.")
  } else {
    cli::cli_alert_warning(
      "{.val {repo}} lacks {.file {missing_templates}}: {.code seeking reviewers} and {.code approve} will fail."
    )
  }
  invisible(is_editor && length(missing_templates) == 0)
}
