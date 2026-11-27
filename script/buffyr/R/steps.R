step_result <- function(step, check, expected, status, seconds = 0,
                        link = NA_character_, last_reply = NA_character_) {
  announce_result(step, status)
  data.frame(
    step = step,
    check = check,
    expected = expected,
    status = status,
    seconds = round(seconds),
    link = link,
    last_reply = last_reply
  )
}

skipped_result <- function(step, reason) {
  step_result(step, "", "", paste0("SKIPPED (", reason, ")"))
}

combine_results <- function(...) {
  purrr::list_rbind(list(...))
}

is_failure <- function(status) {
  !(status == "PASS" | startsWith(status, "SKIPPED"))
}

step_passed <- function(result) {
  !any(is_failure(result$status))
}

announce_result <- function(step, status) {
  time <- format(Sys.time(), "%H:%M:%S")
  if (status == "PASS") {
    cli::cli_alert_success("{time} {.field {step}}")
  } else if (startsWith(status, "SKIPPED")) {
    cli::cli_alert_info("{time} {.field {step}}: {status}")
  } else {
    cli::cli_alert_danger("{time} {.field {step}}: {status}")
  }
}

is_forced_failure <- function(context, step) {
  step %in% context$force_failure
}

expected_pattern <- function(context, step, pattern) {
  if (is_forced_failure(context, step)) "__forced_failure__" else pattern
}

timeout_for <- function(context, step, timeout) {
  if (is_forced_failure(context, step)) min(timeout, 20) else timeout
}

failure_status <- function(context, step, status) {
  if (is_forced_failure(context, step)) paste(status, "(forced failure)") else status
}

expect_reply <- function(context, step, check, pattern, after_id, timeout = context$reply_timeout) {
  started_at <- Sys.time()
  reply <- wait_for_bot_reply(
    context,
    expected_pattern(context, step, pattern),
    after_id,
    timeout_for(context, step, timeout)
  )
  if (!is.null(reply)) {
    return(step_result(step, check, pattern, "PASS", seconds_since(started_at), reply$url))
  }
  last_reply <- last_bot_reply(get_comments(context), after_id)
  step_result(
    step, check, pattern,
    status = failure_status(context, step, "TIMEOUT"),
    seconds = seconds_since(started_at),
    link = last_reply$url %||% NA_character_,
    last_reply = last_reply$body %||% NA_character_
  )
}

run_command <- function(context, step, command, pattern, timeout = context$reply_timeout) {
  posted <- post_bot_command(context, command)
  expect_reply(context, step, bot_command(command), pattern, posted$id, timeout)
}

expect_issue <- function(context, step, check, expected, condition, timeout = 60) {
  started_at <- Sys.time()
  forced <- is_forced_failure(context, step)
  timeout <- timeout_for(context, step, timeout)
  repeat {
    if (!forced && condition(get_issue(context))) {
      return(step_result(step, check, expected, "PASS", seconds_since(started_at), context$issue_url))
    }
    if (seconds_since(started_at) >= timeout) {
      return(step_result(
        step, check, expected,
        failure_status(context, step, "FAIL"), seconds_since(started_at), context$issue_url
      ))
    }
    Sys.sleep(5)
  }
}

pkgcheck_pattern <- function(context) {
  paste0("## Checks for \\[", context$package_name)
}

expect_pkgcheck_later <- function(result, step, check, after_id, requested_at) {
  cli::cli_alert_info("{.field {step}}: deferred, checked at the end")
  attr(result, "pkgcheck_requests") <- list(list(
    step = step,
    check = check,
    after_id = after_id,
    requested_at = requested_at
  ))
  result
}

pkgcheck_requests <- function(results) {
  purrr::list_flatten(purrr::compact(purrr::map(results, attr, "pkgcheck_requests")))
}

wait_for_pkgcheck <- function(context, requests) {
  cli::cli_alert("Waiting for {length(requests)} pkgcheck result{?s}...")
  resolved <- list()
  while (length(requests) > 0) {
    comments <- get_comments(context)
    outcomes <- purrr::map(requests, \(request) resolve_pkgcheck(context, request, comments))
    resolved <- c(resolved, purrr::compact(outcomes))
    requests <- requests[purrr::map_lgl(outcomes, is.null)]
    if (length(requests) > 0) Sys.sleep(context$poll_interval)
  }
  purrr::list_rbind(resolved)
}

resolve_pkgcheck <- function(context, request, comments) {
  pattern <- pkgcheck_pattern(context)
  reply <- find_bot_reply(comments, expected_pattern(context, request$step, pattern), request$after_id)
  waited <- seconds_since(request$requested_at)
  if (!is.null(reply)) {
    return(step_result(request$step, request$check, pattern, "PASS", waited, reply$url))
  }
  if (waited >= timeout_for(context, request$step, context$pkgcheck_timeout)) {
    return(step_result(
      request$step, request$check, pattern,
      failure_status(context, request$step, "TIMEOUT (pkgcheck)"), waited
    ))
  }
  NULL
}
