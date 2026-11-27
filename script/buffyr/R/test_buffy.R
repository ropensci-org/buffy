#' Run the bot smoke test
#'
#' Opens a submission issue in the test repository, runs the bot cheatsheet
#' commands, waits for the replies, cleans up Airtable after each step that
#' writes to it, closes the issue and writes a markdown report.
#' Stops right after `help` if the bot doesn't answer.
#' Run [buffy_test_sitrep()] first to check your setup.
#'
#' @param airtable Run the commands that write to Airtable.
#' @param team_commands Also run `invite me to` and `approve`. Both create a
#'   `<package>-smoke-test` team in the ropensci organization, which the run
#'   then tries to delete.
#' @param repo Test repository.
#' @param package_repo Repository of the package to submit.
#' @param issue Number of an existing issue to reuse instead of opening one.
#' @param reply_timeout Seconds to wait for each bot reply.
#' @param pkgcheck_timeout Seconds to wait for pkgcheck results.
#' @param report Path of the markdown report.
#' @param keep_open Leave the issue open.
#' @param force_failure Step IDs to fail on purpose, to check failure reporting.
#'
#' @return Invisibly, a `buffy_test` object.
#' @export
test_buffy <- function(airtable = TRUE,
                       team_commands = FALSE,
                       repo = "ropenscilabs/statistical-software-review",
                       package_repo = "ropensci/riem",
                       issue = NULL,
                       reply_timeout = 120,
                       pkgcheck_timeout = 3600,
                       report = sprintf("buffy-report-%s.md", format(Sys.time(), "%Y-%m-%d-%H%M%S")),
                       keep_open = FALSE,
                       force_failure = character()) {
  context <- list(
    airtable = airtable,
    team_commands = team_commands,
    repo = repo,
    package_repo = package_repo,
    package_name = basename(package_repo),
    package_url = paste0("https://github.com/", package_repo),
    reply_timeout = reply_timeout,
    pkgcheck_timeout = pkgcheck_timeout,
    report = report,
    keep_open = keep_open,
    force_failure = force_failure,
    poll_interval = 10,
    started_at = Sys.time(),
    user = gh::gh("/user")$login
  )
  check_prerequisites(context$user, repo, airtable)
  snapshot <- if (airtable) snapshot_airtable(context)
  context <- if (is.null(issue)) open_submission(context) else use_existing_issue(context, issue)

  steps <- buffy_steps(context, snapshot)
  results <- list()
  stopped_after_help <- FALSE
  aborted <- NULL
  tryCatch(
    for (name in names(steps)) {
      results[[name]] <- if (name == "pkgcheck") {
        wait_for_pkgcheck(context, pkgcheck_requests(results))
      } else {
        steps[[name]]()
      }
      if (name == "help" && !step_passed(results[[name]])) {
        stopped_after_help <- TRUE
        cli::cli_alert_danger("{.code help} failed: no other command will run.")
        break
      }
    },
    error = function(condition) {
      aborted <<- conditionMessage(condition)
      cli::cli_alert_danger("Error: {aborted}")
    }
  )

  test <- structure(
    list(
      context = context,
      results = purrr::list_rbind(results),
      airtable_records = purrr::list_rbind(purrr::map(results, attr, "airtable_records")),
      airtable_snapshot = snapshot,
      stopped_after_help = stopped_after_help,
      aborted = aborted
    ),
    class = "buffy_test"
  )

  if (!keep_open && !is_closed(get_issue(context))) {
    cli::cli_alert("Closing {.url {context$issue_url}}")
    close_issue(context)
  }
  write_report(test)
  if (test_passed(test)) {
    cli::cli_alert_success("Buffy smoke test passed. Report: {.file {report}}")
  } else {
    cli::cli_alert_danger("Buffy smoke test failed. Report: {.file {report}}")
  }
  invisible(test)
}

test_passed <- function(test) {
  is.null(test$aborted) && !test$stopped_after_help && step_passed(test$results)
}

#' @export
print.buffy_test <- function(x, ...) {
  status <- x$results$status
  cli::cli_text("{.strong Buffy smoke test} {if (test_passed(x)) 'passed' else 'failed'}")
  cli::cli_bullets(c(
    "*" = "Issue: {.url {x$context$issue_url}}",
    "*" = "{sum(status == 'PASS')} passed, {sum(is_failure(status))} failed, {sum(startsWith(status, 'SKIPPED'))} skipped",
    "*" = "Report: {.file {x$context$report}}"
  ))
  invisible(x)
}
