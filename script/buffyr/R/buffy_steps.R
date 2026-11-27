buffy_steps <- function(context, snapshot) {
  me <- paste0("@", context$user)
  fake_package <- paste0(context$package_name, "-smoke-test")

  airtable_step <- function(step, run_step, expected_tables = character()) {
    if (!context$airtable) {
      return(\() skipped_result(step, "airtable = FALSE"))
    }
    \() with_airtable_cleanup(context, snapshot, step, run_step, expected_tables)
  }
  team_step <- function(step, run_step) {
    if (!context$team_commands) {
      return(\() skipped_result(step, "team_commands = FALSE"))
    }
    run_step
  }

  list(
    help = \() run_command(context, "help", "help", "here are the things you can ask me to do"),
    submission = \() submission_step(context),
    coc = \() run_command(context, "coc", "code of conduct", "Code of Conduct can be found"),
    `coc-whitespace` = \() run_command(context, "coc-whitespace", "   code   of   conduct  ", "Code of Conduct can be found"),
    `unknown-command` = \() run_command(context, "unknown-command", "foo bar baz", "I'm sorry human, I don't understand that"),
    `reviewer-without-editor` = \() run_command(context, "reviewer-without-editor", paste("assign", me, "as reviewer"), "no editor assigned"),
    `ping-editors` = \() ping_editors_step(context),
    `assign-editor` = \() assign_editor_step(context, me),
    `check-package` = \() check_package_step(context),
    `similar-packages` = \() run_command(context, "similar-packages", "similar packages", "Five most similar"),
    `check-srr` = \() run_command(context, "check-srr", "check srr", "not an .srr. package"),
    `check-readme` = \() run_command(context, "check-readme", "check readme", "badge"),
    mint = \() run_command(context, "mint", "mint silver", "can be minted"),
    `on-hold` = \() on_hold_step(context),
    `finalize-transfer` = \() run_command(context, "finalize-transfer", paste("finalize transfer of", fake_package), "Can.t find repository"),
    `invite-me` = team_step("invite-me", \() run_command(context, "invite-me", paste0("invite me to ropensci/", fake_package), "Invitation sent!|Can.t send invitation")),
    `seeking-reviewers` = airtable_step("seeking-reviewers", \() seeking_reviewers_step(context)),
    `assign-reviewer` = airtable_step("assign-reviewer", \() assign_reviewer_step(context, me), "reviews"),
    `set-due-date` = if (context$airtable) \() set_due_date_step(context, me) else \() skipped_result("set-due-date", "airtable = FALSE"),
    `remove-reviewer` = airtable_step("remove-reviewer", \() remove_reviewer_step(context, me)),
    `submit-review` = airtable_step("submit-review", \() submit_review_step(context, me), "reviews"),
    `submit-response` = airtable_step("submit-response", \() submit_response_step(context), "author-responses"),
    pkgcheck = \() NULL,
    close = close_step(context, snapshot, fake_package)
  )
}

with_airtable_cleanup <- function(context, snapshot, step, run_step, expected_tables) {
  result <- run_step()
  records <- clean_airtable(context, snapshot, step)
  record_checks <- purrr::map(expected_tables, \(table) step_result(
    paste0(step, ":airtable-", table),
    sprintf("Airtable '%s' record written", table),
    table,
    if (table %in% records$table) "PASS" else "FAIL"
  ))
  cleanup_check <- step_result(
    paste0(step, ":airtable-cleanup"),
    "Airtable cleanup",
    "nothing left behind",
    if (airtable_cleanup_succeeded(records)) "PASS" else "FAIL"
  )
  combined <- purrr::list_rbind(c(list(result), record_checks, list(cleanup_check)))
  attr(combined, "airtable_records") <- records
  combined
}

submission_step <- function(context) {
  result <- combine_results(
    expect_reply(context, "submission-welcome", "(issue opened) welcome", "Thanks for submitting to rOpenSci", after_id = 0),
    expect_reply(context, "submission-editorcheck", "(issue opened) editor check", "Editor check started", after_id = 0),
    expect_reply(context, "submission-pkgmatch", "(issue opened) similar packages", "Five most similar", after_id = 0)
  )
  expect_pkgcheck_later(result, "submission-pkgcheck", "(issue opened) pkgcheck results", after_id = 0, requested_at = context$opened_at)
}

ping_editors_step <- function(context) {
  combine_results(
    run_command(context, "ping-editors", "ping editors", "Editors have been notified"),
    expect_issue(context, "ping-editors:label", "label editors-pinged", "present", has_label("editors-pinged"))
  )
}

assign_editor_step <- function(context, me) {
  combine_results(
    run_command(context, "assign-editor", paste("assign", me, "as editor"), paste("Assigned!", me, "is now the editor")),
    expect_issue(context, "assign-editor:field", "editor field", me, field_matches("editor", paste0("^", me, "$"))),
    expect_issue(context, "assign-editor:label", "label 1/editor-checks", "present", has_label("1/editor-checks")),
    expect_issue(context, "assign-editor:unlabel", "label editors-pinged", "absent", lacks_label("editors-pinged"))
  )
}

check_package_step <- function(context) {
  requested_at <- Sys.time()
  posted <- post_bot_command(context, "check package")
  result <- combine_results(
    expect_reply(context, "check-package", bot_command("check package"), "about to send the query", posted$id),
    expect_reply(context, "check-package:started", "(after check package) editor check", "Editor check started", posted$id)
  )
  expect_pkgcheck_later(result, "check-package:pkgcheck", "(after check package) pkgcheck results", posted$id, requested_at)
}

on_hold_step <- function(context) {
  combine_results(
    run_command(context, "on-hold", "put on hold", "Submission on hold!"),
    expect_issue(context, "on-hold:label", "label holding", "present", has_label("holding"))
  )
}

seeking_reviewers_step <- function(context) {
  combine_results(
    run_command(context, "seeking-reviewers", "seeking reviewers", "Please add this badge to the README"),
    expect_issue(context, "seeking-reviewers:label", "label 2/seeking-reviewer(s)", "present", has_label("2/seeking-reviewer(s)")),
    expect_issue(context, "seeking-reviewers:unlabel", "label 1/editor-checks", "absent", lacks_label("1/editor-checks"))
  )
}

assign_reviewer_step <- function(context, me) {
  command <- paste("assign", me, "as reviewer")
  posted <- post_bot_command(context, command)
  combine_results(
    expect_reply(context, "assign-reviewer", bot_command(command), paste(me, "added to the reviewers list"), posted$id),
    expect_reply(context, "assign-reviewer:form", "(after assign reviewer) reviewer form", "please fill \\[this form\\]", posted$id),
    expect_issue(context, "assign-reviewer:field", "reviewers-list field", me, field_matches("reviewers-list", me)),
    expect_issue(context, "assign-reviewer:due-date", "due-dates-list field", paste("Due date for", me), field_matches("due-dates-list", paste0("Due date for ", me, ":")))
  )
}

set_due_date_step <- function(context, me) {
  due_date <- format(Sys.Date() + 30)
  run_command(context, "set-due-date", paste("set due date for", me, "to", due_date), paste("Review due date for", me, "is now"))
}

remove_reviewer_step <- function(context, me) {
  combine_results(
    run_command(context, "remove-reviewer", paste("remove", me, "from reviewers"), paste(me, "removed from the reviewers list!")),
    expect_issue(context, "remove-reviewer:field", "reviewers-list field", "TBD", field_matches("reviewers-list", "^TBD$"))
  )
}

submit_review_step <- function(context, me) {
  command <- paste("add", me, "as reviewer")
  posted <- post_bot_command(context, command)
  added <- combine_results(
    expect_reply(context, "add-reviewer", bot_command(command), paste(me, "added to the reviewers list"), posted$id),
    expect_reply(context, "add-reviewer:form", "(after add reviewer) reviewer form", "please fill \\[this form\\]", posted$id)
  )
  review <- post_comment(context, "Smoke test: this comment stands in for a review.")
  combine_results(
    added,
    run_command(context, "submit-review", paste("submit review", review$url, "time 1"), paste0("Logged review for _", context$user, "_"))
  )
}

submit_response_step <- function(context) {
  response <- post_comment(context, "Smoke test: this comment stands in for an author response.")
  run_command(context, "submit-response", paste("submit response", response$url), "Logged author response!")
}

close_step <- function(context, snapshot, fake_package) {
  if (!context$team_commands) {
    return(\() combine_results(skipped_result("approve", "team_commands = FALSE"), out_of_scope_step(context)))
  }
  if (context$airtable) {
    return(\() with_airtable_cleanup(context, snapshot, "approve", \() approve_step(context, fake_package), character()))
  }
  \() approve_step(context, fake_package)
}

approve_step <- function(context, fake_package) {
  combine_results(
    run_command(context, "approve", paste("approve", fake_package), "Approved! Thanks"),
    expect_issue(context, "approve:label", "label 6/approved", "present", has_label("6/approved")),
    expect_issue(context, "approve:closed", "issue state", "closed", is_closed),
    delete_smoke_test_team(fake_package)
  )
}

out_of_scope_step <- function(context) {
  post_bot_command(context, "out of scope")
  combine_results(
    expect_issue(context, "out-of-scope", bot_command("out of scope"), "closed", is_closed),
    expect_issue(context, "out-of-scope:label", "label out-of-scope", "present", has_label("out-of-scope"))
  )
}

delete_smoke_test_team <- function(team) {
  team_endpoint <- sprintf("/orgs/ropensci/teams/%s", team)
  check <- sprintf("delete the ropensci/%s team created by the team commands", team)
  if (!github_succeeds(team_endpoint)) {
    return(step_result("team-cleanup", check, "deleted", "PASS"))
  }
  deleted <- github_succeeds(paste("DELETE", team_endpoint))
  step_result("team-cleanup", check, "deleted", if (deleted) "PASS" else "FAIL (ask an org owner to delete it)")
}
