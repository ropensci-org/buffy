ROpenSci :: Approve
===================

This responder is used to approve a package.
It performs a series of tasks:

- Adds `date-accepted` to the body of the issue
- Clears reviewers' _current_assignment_ in AirTable
- Creates a new team named like the package-name and invites the creator of the issue to it (owner right needed)
- Can reply with a [template](../../using_templates)
- Allows [labeling](../../labeling)
- Closes the issue
- If the submission-type is `stats` it checks if stasgrade is present and if so adds the proper label

## Listens to

```
@botname approve package-name
```

## Requirements

The _package-name_ must be specified in the command, otherwise an error message will be sent as reply.

If the _submission-type_ of the issue is _stats_, then for the responder to work there must be a valid value for a _statsgrade_ variable (marked with HTML comments) in the body of the issue:

```html
# the responder will add the label: '6/approved-silver'
<!--statsgrade-->silver<!--end-statsgrade-->
```

## Settings key

`ropensci_approve`

## Params

For the **Airtable** connection to work two parameters must be present in the `env` section of the settings file, configured using environment variable:
```yaml
...
  env:
    airtable_api_key: <%= ENV['AIRTABLE_API_KEY'] %>
    airtable_base_id: <%= ENV['AIRTABLE_BASE_ID'] %>
...
```

## Examples

**Simplest case:**
```yaml
...
  responders:
    ropensci_approve:
...
```

**With labeling, template response, limiting access and only if there's an editor already assigned:**
```yaml
...
  responders:
    ropensci_approve:
      only: editors
      template_file: approved.md
      data_from_issue:
        - reviewers-list
      remove_labels:
        - 5/awaiting-reviewer(s)-response
      add_labels:
        - 6/approved
...
```
