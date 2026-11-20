# Ansa Daily Invoicing Report — production release

Production preparation branch: `release/invoicing-report`, based on `origin/main` at `d306a826`. The seven report commits were cherry-picked in order: `f65fb64e`, `79b2ec59`, `fe30f0ce`, `dd53992f`, `46e1397d`, `60dd68a8`, `039ae6dc`. No unrelated staging features were included. Deployment remains with Bitbucket; no release, credential change or user assignment has been performed during this preparation.

## Location and access

Open **App Launcher → Ansa Daily Invoicing Report → Daily Invoicing Report**. The dedicated app's metadata name is `Ansa_Reporting`. Assign **Daily Invoice Reporting** (`ABT_Daily_Invoice_Reporting`) to approved internal Salesforce users. The custom permission is checked on the context, summary and detail endpoints. Existing invoice sharing, object/field access and Stripe package/account access still apply. Portal/B2B Shopper accounts are not supported. Partial permission assignments do not transfer to production.

The report is the app's first tab. The production release does not change Ansa Finance navigation or package its app metadata: that shortcut never existed on the production baseline.

## Environment selection

The server reads `Organization.IsSandbox`; users cannot override the mode from the browser.

| Salesforce environment      | Required Stripe connection | Source label     | Invoice dashboard route            |
| --------------------------- | -------------------------- | ---------------- | ---------------------------------- |
| Partial and other sandboxes | Connected, non-live        | Stripe (sandbox) | Account-specific `/test/invoices/` |
| Production                  | Connected, live            | Stripe (live)    | Account-specific `/invoices/`      |

Exactly one matching connection must be accessible to the reporting user. Missing or multiple matches fail explicitly; the report never falls back to the other mode or selects an arbitrary account. Every returned invoice's `livemode` must match the org environment. The UI loads its badge and source labels from the gated server context and blocks reads if that context cannot be determined.

The report reuses the installed Stripe managed connector through invoice-list and invoice-line-list actions. It copies typed output fields directly because the package prohibits JSON serialization/deserialization. It performs read actions only. No API keys, OAuth setup, webhooks, payment flows, retry jobs or other integration routing are changed by this release. Existing production live connection availability, ownership and user access still require verification by the release owner. Do not add a live connection to Partial for this release.

## Report behavior

Choose an inclusive range of 1–31 days and one currency (USD by default). Summary cards total each successful source separately; the daily table shows Invoice Date, System, Invoices Created, Invoice Line Items, Currency and Invoice Amount. Successful zero-activity days show zero. A failed source is shown as unavailable, never as zero, while successful results remain visible.

- Salesforce groups `ABT_Invoice__c` by `ABT_Invoice_Date__c`, counts each parent once, counts related `ABT_InvoiceLineItem__c` records, and sums native `ABT_Amount_Paid__c` values. That field is labeled Invoice Amount. Undated/deleted invoices are excluded. User-mode queries enforce record and field access.
- Stripe groups by actual creation date in UTC, includes all invoice statuses (including drafts and voided invoices), and sums `total` in the selected currency using the applicable minor units. These are independently fetched source figures, not a transactionally consistent reconciliation snapshot. Invoice date, creation timing, shipping, tax and product consolidation can cause legitimate differences.
- NetSuite is not connected and remains out of scope.

Select an **Invoice Line Items** count to see items for that date/source/currency and open each item's parent invoice in a new tab. **Item Name** shows Stripe's line description, falling back to its ID when blank; Salesforce shows line Description, then record name, then ID. Long descriptions wrap. Stripe dashboard links require separate access to the connected Stripe account. Details are fetched on demand and can differ from an earlier summary after source activity. Errors support retry, and older responses cannot overwrite a newly selected source.

## Limits

Salesforce summary reads at most 10,000 invoices. Stripe invoice/line pagination is capped at 50 pages with a 90-callout headroom guard. Invoice detail reads allow at most 2,000 line items for the selected day. Oversized/incomplete reads return errors rather than partial totals/details. Select a shorter summary period or review large detail sets in the source system. Connector timeouts and Salesforce/API limits can still cause failures.

The installed connector uses signed 32-bit creation timestamps, limiting Stripe date ranges to 1970-01-01 through 2038-01-18.

## Validation evidence

- **14 LWC tests passed**, including sandbox labels, production labels/live invoice links, live-source errors, blocking/retry when environment lookup fails, source summaries, detail navigation, empty states and stale-response handling.
- Targeted ESLint, formatting, parsing/reference inspection of 8 XML files, and local source-to-metadata conversion passed.
- Apex regression tests now force the intended synthetic environment per test and cover live rows/links, rejection of sandbox invoices in production, rejection of live invoices in sandbox mode, missing matching connections, both server contexts and permissions. **The updated Apex suite has not been run.**
- Production metadata validation, installed connector contracts, actual live reads, performance and a finance-user browser smoke test remain **not run**. No local evidence establishes production release readiness by itself.

## Release path and smoke checks

Use `manifest/invoicing-report.xml` for the feature's metadata scope; the repository pipeline computes deployment deltas. Open a PR from this release branch to **main** so the configured PR validation targets production. Merging main runs lint/Jest and production validation, then the configured merge-back step. Production deployment is a **manual Bitbucket gate**. A successful production deployment is followed by the configured AnsaPortal deployment; production also attempts its configured community publish step. This internal reporting feature does not itself require portal publishing.

Before the release, verify exactly one intended accessible live Stripe connection, the installed managed package/action contract, required invoice fields, and the intended reporting user/license. After the authorized pipeline deploy:

1. Assign Daily Invoice Reporting to the approved internal production users.
2. Open the app and confirm **Stripe live**, with no sandbox wording or test-mode invoice links.
3. Compare a known date/currency against Salesforce and Stripe, including draft/void status expectations.
4. Open line details and verify names and parent invoice links for both sources.
5. Confirm the same code still shows sandbox data in Partial and rejects wrong-mode responses.
6. Verify denied users cannot call context/summary/detail endpoints and source failures do not display zero totals.

## Recovery

Prepare a source revert of this isolated reporting release for the normal Bitbucket process if necessary; do not substitute sandbox data for live production totals. Reversing metadata does not reverse separate permission assignments or credential changes. The feature writes no invoice data. No recovery action has been run.
