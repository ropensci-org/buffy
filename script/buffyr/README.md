# buffyr

Smoke test for the rOpenSci review bot.
`test_buffy()` checks that the [bot cheatsheet](https://github.com/ropensci/dev_guide/blob/main/bot_cheatsheet.Rmd) commands still work.
An editor runs it with their own GitHub account, against [ropenscilabs/statistical-software-review](https://github.com/ropenscilabs/statistical-software-review).

It:

1. opens an issue submitting [riem](https://github.com/ropensci/riem);
2. posts `help`, and stops if the bot doesn't answer;
3. runs each command (you are author, editor and reviewer) and waits for the reply;
4. checks the pkgcheck results at the end;
5. closes the issue, cleans up Airtable, and writes a markdown report.

A run takes 20 to 30 minutes, longer if pkgcheck is slow.

## Setup

From the buffy repository:

```r
pak::local_install("script/buffyr")
```

You need a GitHub token that {gh} can find: see `usethis::gh_token_help()`.
You must be in the ropensci `editors` team.

The test repository uses the production bot, so it writes to the production Airtable base.
Store the Airtable credentials once:

```r
keyring::key_set("AIRTABLE_ID")       # base ID, the "app..." part of the base URL
keyring::key_set("AIRTABLE_API_KEY")  # token from https://airtable.com/create/tokens
```

The token needs `data.records:read` and `data.records:write` on the rOpenSci base.

## Usage

First [take a snapshot of the Airtable base](https://support.airtable.com/docs/taking-and-restoring-base-snapshots), so you can restore it if the cleanup goes wrong.
Run from the buffy repository, so the report records the buffy commit.

```r
library(buffyr)
buffy_test_sitrep()  # check your setup first
run <- test_buffy()
run <- test_buffy(airtable = FALSE)
run <- test_buffy(report = "my-report.md", keep_open = TRUE)
```

See `?test_buffy` for all arguments.

## Side effects

- **Airtable**: reviewer commands, `seeking reviewers`, `submit review` and `submit response` write to production.
  `test_buffy()` snapshots your rows first.
  After each step that writes to Airtable, it deletes what the step created and restores your `current_assignment`.
- **ping editors**: roreviewapi only emails admins for the test repository.
- **`team_commands = TRUE`**: `invite me to` and `approve` create a `ropensci/riem-smoke-test` team and add you to it.
  The run tries to delete it (needs org owner rights).
  Otherwise the issue is closed with `out of scope`.
- **Reminders**: `put on hold` and adding a reviewer schedule reminders on the closed issue.

## Report

Contains: a header (result, time, who, issue, buffy commit, options), a table of steps, the bot's last reply for each failure, pkgcheck timings, and the Airtable cleanup.
`TIMEOUT (pkgcheck)` usually means roreviewapi is slow, not that buffy is broken.

## Testing buffyr

Force steps to fail with `force_failure`:

```r
test_buffy(force_failure = "coc")    # fails, the rest still runs
test_buffy(force_failure = "help")   # stops after help
test_buffy(pkgcheck_timeout = 60)    # pkgcheck timeout
```

Step IDs:
`help`,
`submission-welcome`, `submission-editorcheck`, `submission-pkgmatch`, `submission-pkgcheck`,
`coc`, `coc-whitespace`, `unknown-command`, `reviewer-without-editor`,
`ping-editors`, `ping-editors:label`,
`assign-editor`, `assign-editor:field`, `assign-editor:label`, `assign-editor:unlabel`,
`check-package`, `check-package:started`, `check-package:pkgcheck`,
`similar-packages`, `check-srr`, `check-readme`, `mint`, `on-hold`, `on-hold:label`,
`finalize-transfer`, `invite-me`,
`seeking-reviewers`, `seeking-reviewers:label`, `seeking-reviewers:unlabel`,
`assign-reviewer`, `assign-reviewer:form`, `assign-reviewer:field`, `assign-reviewer:due-date`,
`set-due-date`, `remove-reviewer`, `remove-reviewer:field`,
`add-reviewer`, `add-reviewer:form`, `submit-review`, `submit-response`,
`approve`, `approve:label`, `approve:closed`, `team-cleanup`,
`out-of-scope`, `out-of-scope:label`.

Airtable steps also get `<step>:airtable-<table>` (record written) and `<step>:airtable-cleanup` checks; these can't be forced to fail.
