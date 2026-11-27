check_airtable_access <- function() {
  local_airtable_token()
  airtabler::air_select(airtable_base_id(), "reviewers-prod", maxRecord = 1, pageSize = 1)
  cli::cli_alert_success("Airtable: keyring entries found and read access works.")
  invisible(TRUE)
}

local_airtable_token <- function(env = parent.frame()) {
  withr::local_envvar(AIRTABLE_API_KEY = keyring_secret("AIRTABLE_API_KEY"), .local_envir = env)
}

keyring_secret <- function(name) {
  tryCatch(
    keyring::key_get(name),
    error = function(e) {
      cli::cli_abort("No keyring entry {.val {name}}: set it with {.code keyring::key_set(\"{name}\")}.")
    }
  )
}

airtable_base_id <- function() {
  keyring_secret("AIRTABLE_ID")
}

snapshot_airtable <- function(context) {
  local_airtable_token()
  base <- airtable_base_id()
  reviewer <- select_airtable_rows(base, "reviewers-prod", github_login_formula(context$user))
  snapshot <- list(
    reviewer_id = if (nrow(reviewer) > 0) reviewer$id[1] else NA_character_,
    reviewer_assignment = if (nrow(reviewer) > 0) airtable_value(reviewer, 1, "current_assignment") else "",
    author_existed = nrow(select_airtable_rows(base, "authors", github_login_formula(context$user))) > 0,
    package_existed = nrow(select_airtable_rows(base, "packages", package_formula(context$package_name))) > 0
  )
  cli::cli_alert_info(
    "Airtable snapshot: reviewer row {.val {snapshot$reviewer_id}} (current_assignment {.val {snapshot$reviewer_assignment}}), author row {if (snapshot$author_existed) 'exists' else 'absent'}, package row {if (snapshot$package_existed) 'exists' else 'absent'}."
  )
  snapshot
}

clean_airtable <- function(context, snapshot, step) {
  local_airtable_token()
  base <- airtable_base_id()
  wait_for_airtable_writes(base, context)
  touched <- touched_airtable_records(base, context, snapshot)
  touched$step <- rep(step, nrow(touched))
  touched$result <- rep("not applied", nrow(touched))
  if (nrow(touched) == 0) {
    cli::cli_alert_info("{.field {step}}: no Airtable records touched.")
    return(structure(touched, leftovers = touched))
  }
  print_airtable_records(touched)
  touched$result <- purrr::pmap_chr(touched, \(table, id, action, restore_value, ...) {
    undo_airtable_change(base, table, id, action, restore_value)
  })
  leftovers <- touched_airtable_records(base, context, snapshot)
  if (nrow(leftovers) == 0) {
    cli::cli_alert_success("{.field {step}}: Airtable cleaned up.")
  } else {
    cli::cli_alert_danger("{.field {step}}: some Airtable records still need attention:")
    print_airtable_records(leftovers)
  }
  structure(touched, leftovers = leftovers)
}

airtable_cleanup_succeeded <- function(records) {
  leftovers <- attr(records, "leftovers")
  !any(startsWith(records$result, "ERROR")) && !is.null(leftovers) && nrow(leftovers) == 0
}

airtable_string <- function(x) {
  paste0("'", gsub("'", "\\\\'", x), "'")
}

github_login_formula <- function(user) sprintf("{github} = %s", airtable_string(user))

package_formula <- function(package_name) sprintf("{package-name} = %s", airtable_string(package_name))

reviews_formula <- function(issue_url) {
  sprintf(
    "OR({onboarding_url} = %s, FIND(%s, {review_url} & ''))",
    airtable_string(issue_url), airtable_string(paste0(issue_url, "#"))
  )
}

responses_formula <- function(issue_url) {
  sprintf("FIND(%s, {response_url} & '')", airtable_string(paste0(issue_url, "#")))
}

select_airtable_rows <- function(base, table, formula) {
  rows <- airtabler::air_select(base, table, filterByFormula = formula)
  if (!is.data.frame(rows) || nrow(rows) == 0) {
    return(data.frame(id = character()))
  }
  offset <- attr(rows, "offset")
  while (!is.null(offset)) {
    more_rows <- airtabler::air_select(base, table, filterByFormula = formula, offset = offset)
    offset <- attr(more_rows, "offset")
    if (is.data.frame(more_rows) && nrow(more_rows) > 0) rows <- bind_rows_filling(rows, more_rows)
  }
  rows
}

bind_rows_filling <- function(a, b) {
  columns <- union(names(a), names(b))
  for (column in setdiff(columns, names(a))) a[[column]] <- NA
  for (column in setdiff(columns, names(b))) b[[column]] <- NA
  rbind(a[columns], b[columns])
}

airtable_value <- function(rows, i, field) {
  if (!field %in% names(rows)) {
    return("")
  }
  values <- unlist(rows[[field]][[i]])
  paste(values[!is.na(values)], collapse = ", ")
}

airtable_values <- function(rows, field) {
  purrr::map_chr(seq_len(nrow(rows)), \(i) airtable_value(rows, i, field))
}

airtable_record <- function(table, id, change, action, details, restore_value = NA_character_) {
  data.frame(table = table, id = id, change = change, action = action, details = details, restore_value = restore_value)
}

touched_airtable_records <- function(base, context, snapshot) {
  records <- list()
  add_created <- function(table, rows, details) {
    if (nrow(rows) > 0) records[[length(records) + 1]] <<- airtable_record(table, rows$id, "created", "delete", details)
  }

  reviews <- select_airtable_rows(base, "reviews", reviews_formula(context$issue_url))
  add_created("reviews", reviews, sprintf("id_no=%s review_url=%s", airtable_values(reviews, "id_no"), airtable_values(reviews, "review_url")))

  responses <- select_airtable_rows(base, "author-responses", responses_formula(context$issue_url))
  add_created("author-responses", responses, airtable_values(responses, "response_url"))

  invites <- select_airtable_rows(base, "slack-invites", sprintf("{package} = %s", airtable_string(context$title)))
  add_created("slack-invites", invites, airtable_values(invites, "github"))

  if (!snapshot$author_existed) {
    add_created("authors", select_airtable_rows(base, "authors", github_login_formula(context$user)), context$user)
  }
  if (!snapshot$package_existed) {
    add_created("packages", select_airtable_rows(base, "packages", package_formula(context$package_name)), context$package_name)
  }

  reviewers <- select_airtable_rows(base, "reviewers-prod", github_login_formula(context$user))
  if (is.na(snapshot$reviewer_id)) {
    add_created("reviewers-prod", reviewers, context$user)
  } else {
    row <- which(reviewers$id == snapshot$reviewer_id)
    current_assignment <- if (length(row) == 1) airtable_value(reviewers, row, "current_assignment") else ""
    if (!identical(current_assignment, snapshot$reviewer_assignment)) {
      records[[length(records) + 1]] <- airtable_record(
        "reviewers-prod", snapshot$reviewer_id, "modified", "restore current_assignment",
        sprintf("'%s' -> '%s'", current_assignment, snapshot$reviewer_assignment),
        snapshot$reviewer_assignment
      )
    }
  }

  purrr::list_rbind(records) %||% airtable_record(character(), character(), character(), character(), character(), character())
}

wait_for_airtable_writes <- function(base, context, stable_for = 30, max_wait = 180) {
  count_linked_rows <- function() {
    nrow(select_airtable_rows(base, "reviews", reviews_formula(context$issue_url))) +
      nrow(select_airtable_rows(base, "author-responses", responses_formula(context$issue_url)))
  }
  cli::cli_alert("Waiting for the bot's Airtable writes to settle...")
  started_at <- Sys.time()
  last_count <- count_linked_rows()
  last_change <- Sys.time()
  while (seconds_since(last_change) < stable_for && seconds_since(started_at) < max_wait) {
    Sys.sleep(10)
    count <- count_linked_rows()
    if (count != last_count) {
      last_count <- count
      last_change <- Sys.time()
    }
  }
}

print_airtable_records <- function(records) {
  cli::cli_verbatim(
    sprintf("%-17s %-18s %-9s %-26s %s", "TABLE", "RECORD", "CHANGE", "ACTION", "DETAILS"),
    sprintf("%-17s %-18s %-9s %-26s %s", records$table, records$id, records$change, records$action, records$details)
  )
}

undo_airtable_change <- function(base, table, id, action, restore_value) {
  tryCatch(
    {
      if (action == "delete") {
        airtabler::air_delete(base, table, id)
        "deleted"
      } else {
        airtabler::air_update(base, table, id, list(current_assignment = restore_value))
        "restored"
      }
    },
    error = function(e) paste("ERROR:", conditionMessage(e))
  )
}
