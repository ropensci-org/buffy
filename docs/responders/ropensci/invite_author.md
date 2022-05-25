ROpenSci :: Invite author
=========================

This responder is used by the author of an approved package to receive an invitation to join the team managing the new transfered package. Usually this invitation is sent automatically when the package is approved but it expires in a week. This responder allows the author to have the invitation sent again.

## Listens to

```
@botname invite me to ropensci/package-name
```

## Requirements

The _ropensci/package-name_ team must exist and the _package-name_ must be a package already transfered to rOpenSci, otherwise an error message will be sent as reply.


## Settings key

`ropensci_invite_author`

## Example:

```yaml
...
  responders:
    ropensci_invite_author:
...
```

## In action

![](../../images/responders/ropensci/ropensci_invite_author.png "ROpenSci :: Invite author in action")
