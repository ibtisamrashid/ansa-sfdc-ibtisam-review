# CX impersonation audit

## Scope and current capability

This feature uses Salesforce native audit data to investigate a CX employee's
**Login As** session and changes to a Quote, Order, Quote Line Item, or Order
Product. It does not create an impersonation flag on a business record.

The existing Quote, Quote Line Item, Order, and Order Product layouts contain
history related lists. Selected fields have history tracking enabled. The repo
already includes Quote History and Quote Line Item History report types. This
change adds a CX Order Field Changes report using Salesforce's standard
`OrderAuditHistory` report type, which is already used by other CX reports in
this repository. The report shows the affected order, field, time, and history
user. It does not identify the CX employee who started a Login As session.

Salesforce `LoginAsEvent` records the initiating username in
`DelegatedUsername`, the impersonated user in `UserId` / `Username`, and the
event time in `EventDate`. The partial sandbox allowed a read-only query of
this object during development. Access in other orgs and for the intended
reviewer must be verified. Salesforce documents a Shield or Event Monitoring
subscription and **View Real-Time Event Monitoring Data** permission for it.

## Investigation procedure

1. Open the Quote or Order and its history related list. The CX Order Field
   Changes report provides a cross-order view of tracked Order fields. For
   changes to a product, inspect the relevant line item's history. Record the
   history row's record ID, field, timestamp, and history user. History starts
   only when the corresponding field was enabled for tracking.
2. In an authorized audit session, inspect `LoginAsEvent` for the same target
   user and time window. Record the initiating CX username, target user,
   `EventDate`, `LoginAsCategory`, and, when present, `LoginKey` and
   `LoginHistoryId`. Restrict queries by `EventDate`; this is a big object with
   limited query filters.
3. Compare the session and change evidence. State whether the event **could
   explain** the change. Do not state that it proves who edited the record
   unless an independent, reliable session-to-record correlation is available.
   Multiple sessions or the customer's own activity make a timestamp match
   ambiguous. Keep customer record contents out of tickets and logs.

Setup Audit Trail is a fallback for confirming that Login As occurred when
Event Monitoring is unavailable. Its API can omit Login As login entries that
are present in the UI export; use the UI export for that investigation. It
does not link a Login As event to a Quote or Order field history row.

## Acceptance checks in partial

Use synthetic records and an authorized CX test user. Perform one ordinary
customer update and one CX Login As update to a tracked Quote field, Order
field, and relevant line item field. Confirm:

- the existing Quote history reporting and the new CX Order Field Changes
  report open for an authorized reviewer;
- the history rows show the expected record, field, time, and history user;
- `LoginAsEvent` shows the CX initiator and impersonated user for the CX
  session, and no corresponding event is inferred for the ordinary login;
- the reviewer can distinguish a definite actor from a possible match when
  concurrent sessions exist;
- access to audit events is limited to approved reviewers.

Do not treat passing metadata validation as proof of these runtime behaviors.
No org data was changed as part of this branch.

## Remaining product decision

Native field history has no guaranteed join key to `LoginAsEvent`. If the
requirement is a definitive CX employee attribution **on every Quote or Order
edit**, this native audit approach is insufficient. That requirement needs a
separately designed transaction-level capture mechanism and a tested way to
preserve the true actor across the impersonated session. Do not populate a
``CX modified by`` field from timestamp matching.

## References

- [Salesforce field history tracking](https://help.salesforce.com/s/articleView?id=000221754&language=en_US&type=1)
- [Salesforce LoginAsEvent](https://developer.salesforce.com/docs/platform/platform-events/guide/sforce-api-objects-loginasevent.html)
- [Salesforce Setup Audit Trail Login As API behavior](https://help.salesforce.com/s/issue?id=a028c00000qQ02kAAC&language=en_US)
