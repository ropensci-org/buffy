write_report <- function(test) {
  results <- test$results %||% data.frame(
    step = character(), check = character(), expected = character(), status = character(),
    seconds = numeric(), link = character(), last_reply = character()
  )
  writeLines(
    c(
      report_header(test, results),
      report_steps(results),
      report_failures(results),
      report_pkgcheck(results),
      report_airtable(test)
    ),
    test$context$report
  )
}

markdown_cell <- function(x) {
  gsub("|", "\\|", ifelse(is.na(x), "", x), fixed = TRUE)
}

minutes_seconds <- function(seconds) {
  sprintf("%d min %d s", as.integer(seconds %/% 60), as.integer(round(seconds %% 60)))
}

on_off <- function(x) if (isTRUE(x)) "on" else "off"

report_header <- function(test, results) {
  context <- test$context
  result <- if (test_passed(test)) "PASS" else "FAIL"
  if (test$stopped_after_help) result <- "FAIL (stopped after help)"
  if (!is.null(test$aborted)) result <- paste0("FAIL (aborted: ", test$aborted, ")")
  c(
    "# Buffy smoke test report",
    "",
    sprintf(
      "- **Result:** %s (%d passed, %d failed, of which %d pkgcheck timeout(s), %d skipped)",
      result,
      sum(results$status == "PASS"),
      sum(is_failure(results$status)),
      sum(startsWith(results$status, "TIMEOUT (pkgcheck)")),
      sum(startsWith(results$status, "SKIPPED"))
    ),
    sprintf("- **Started:** %s", format(context$started_at, "%Y-%m-%d %H:%M:%S %Z")),
    sprintf("- **Duration:** %s", minutes_seconds(seconds_since(context$started_at))),
    sprintf("- **Run by:** @%s", context$user),
    sprintf("- **Issue:** [%s#%s](%s) (%s)", context$repo, context$issue, context$issue_url, context$title),
    sprintf("- **Package:** %s", context$package_url),
    sprintf("- **Buffy:** `origin/ropensci` at `%s`, local `HEAD` at `%s`", git_commit("origin/ropensci"), git_commit("HEAD")),
    sprintf(
      "- **Options:** reply timeout %ss, pkgcheck timeout %ss, airtable %s, team commands %s, keep open %s",
      context$reply_timeout, context$pkgcheck_timeout, on_off(context$airtable),
      on_off(context$team_commands), on_off(context$keep_open)
    ),
    if (length(context$force_failure) > 0) sprintf("- **Forced failures:** %s", paste(context$force_failure, collapse = ", ")),
    ""
  )
}

report_steps <- function(results) {
  status <- ifelse(is_failure(results$status), paste0("**", results$status, "**"), results$status)
  expected <- ifelse(nzchar(results$expected), paste0("`", markdown_cell(results$expected), "`"), "")
  link <- ifelse(is.na(results$link), "", sprintf("[link](%s)", results$link))
  c(
    "## Steps",
    "",
    "| Step | Command / check | Expected | Status | Time (s) | Link |",
    "|---|---|---|---|---|---|",
    sprintf(
      "| `%s` | %s | %s | %s | %s | %s |",
      results$step, markdown_cell(results$check), expected, status, results$seconds, link
    ),
    ""
  )
}

report_failures <- function(results) {
  failures <- results[is_failure(results$status), , drop = FALSE]
  if (nrow(failures) == 0) {
    return(character())
  }
  details <- purrr::pmap(failures, \(step, check, expected, status, link, last_reply, ...) {
    c(
      sprintf("### `%s`: %s", step, status),
      "",
      sprintf("Command or check: %s", check),
      "",
      sprintf("Expected: `%s`", markdown_cell(expected)),
      "",
      if (is.na(last_reply)) {
        "No bot reply was received after the command."
      } else {
        c(
          sprintf("Last bot reply after the command ([link](%s)):", link),
          "",
          "````",
          utils::head(strsplit(last_reply, "\n")[[1]], 40),
          "````"
        )
      },
      ""
    )
  })
  c("## Failures", "", unlist(details))
}

report_pkgcheck <- function(results) {
  pkgcheck <- results[grepl("pkgcheck", results$step), , drop = FALSE]
  lines <- if (nrow(pkgcheck) == 0) {
    "No pkgcheck results were awaited."
  } else {
    ifelse(
      pkgcheck$status == "PASS",
      sprintf("- `%s`: results arrived after %s ([link](%s))", pkgcheck$step, minutes_seconds(pkgcheck$seconds), pkgcheck$link),
      sprintf("- `%s`: **%s** after %s", pkgcheck$step, pkgcheck$status, minutes_seconds(pkgcheck$seconds))
    )
  }
  c("## pkgcheck", "", lines, "")
}

report_airtable <- function(test) {
  records <- test$airtable_records
  body <- if (!test$context$airtable) {
    "Skipped (airtable = FALSE)."
  } else if (is.null(records) || nrow(records) == 0) {
    "No Airtable records were touched."
  } else {
    c(
      "Records touched by each step, and what the cleanup after the step did.",
      "The `:airtable-cleanup` steps above say whether anything was left behind.",
      "",
      "| Step | Table | Record | Change | Action | Result | Details |",
      "|---|---|---|---|---|---|---|",
      sprintf(
        "| `%s` | %s | `%s` | %s | %s | %s | %s |",
        records$step, records$table, records$id, records$change, records$action,
        markdown_cell(records$result), markdown_cell(records$details)
      )
    )
  }
  c("## Airtable", "", body)
}
