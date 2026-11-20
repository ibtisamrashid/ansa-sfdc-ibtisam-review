# Ibtisam's ANSA Salesforce code review

Browse the actual source files under [`code/`](code/) or use the [file catalog](CATALOG.md) to see the Git commit used for each file. The collection contains files touched by commits recorded under Ibtisam's author name. Each file is a complete historical snapshot, so it can contain adjacent code written by teammates. The collection is for review and is not a deployable Salesforce DX checkout.

## Start here

- Not Currently Possible orders: [cart service](code/force-app/main/default/classes/ABT_Cart_Service.cls), [portal controller](code/force-app/main/default/classes/ABT_Portal_Controller.cls), [quote line UI](code/force-app/main/default/lwc/aBT_RequestQuoteLineDataTable/), [checkout utilities](code/force-app/main/default/lwc/abtQuoteCheckoutUtils/).
- CX impersonation audit: [order history report](code/force-app/main/default/reports/CustomerExperience/CX_Order_Field_Changes.report-meta.xml), [deployment manifest](code/manifest/cx-impersonation-audit.xml), [audit notes](code/CX_IMPERSONATION_AUDIT.md). The earlier report types were removed in the final CX commit.
- Sequence Hub and codon optimizer: [Sequence Hub UI](code/force-app/main/default/lwc/sequenceHub/), [controller](code/force-app/main/default/classes/SequenceHubController.cls), [codon optimizer UI](code/force-app/main/default/lwc/codonOptimizer/), [codon service](code/force-app/main/default/classes/CodonService.cls).
- Invoicing and Stripe: [daily invoice report](code/force-app/main/default/classes/ABT_DailyInvoiceReport.cls), [Stripe invoice processor](code/force-app/main/default/classes/ABT_StripeInvoiceProcessor.cls).
- [Current Sequence Hub work](current-work/sequence-hub/)
- [Current Stripe invoice rollback work](current-work/stripe-invoice-rollback/)

The source snapshots come from multiple feature and release branches. The current-work folders contain local uncommitted files. Portal monitoring, backups, generated reports, personal settings, and scratch scripts with org-specific data are excluded.

## Review notes

Use the catalog's commit ID to locate the original change in the company repository when a line-by-line diff or merge context is needed. Files deleted by Ibtisam's latest touched commit are listed below. No Salesforce or CI checks were run for this review collection.

- Source files: 190
- Current Sequence Hub files: 9
- Current Stripe rollback files: 10

### Deleted paths

- `PORTAL_CONSOLE_HOTFIX.md` (`ed53b967`)
- `force-app/main/default/cspTrustedSites/Google_Pakistan.cspTrustedSite-meta.xml` (`8768d9ff`)
- `force-app/main/default/reportTypes/Order_History.reportType-meta.xml` (`4a26176d`)
- `force-app/main/default/reportTypes/Order_Product_History.reportType-meta.xml` (`4a26176d`)
- `scripts/tests/test_stripe_flow_contracts.py` (current Stripe rollback work)
