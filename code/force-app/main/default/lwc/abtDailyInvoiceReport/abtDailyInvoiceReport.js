import { LightningElement } from "lwc";
import salesforceRows from "@salesforce/apex/ABT_DailyInvoiceReport.salesforceRows";
import stripeRows from "@salesforce/apex/ABT_DailyInvoiceReport.stripeRows";
import lineItems from "@salesforce/apex/ABT_DailyInvoiceReport.lineItems";
import reportContext from "@salesforce/apex/ABT_DailyInvoiceReport.reportContext";

const COLUMNS = [
  { label: "Invoice Date", fieldName: "invoiceDate", type: "date-local" },
  { label: "System", fieldName: "systemName" },
  { label: "Invoices Created", fieldName: "invoicesCreated", type: "number" },
  {
    label: "Invoice Line Items",
    fieldName: "lineItems",
    type: "button",
    typeAttributes: {
      label: { fieldName: "lineItems" },
      name: "view_line_items",
      variant: "base",
      title: "View line items and their invoices"
    }
  },
  { label: "Currency", fieldName: "currencyCode" },
  {
    label: "Invoice Amount",
    fieldName: "invoiceAmount",
    type: "currency",
    typeAttributes: { currencyCode: { fieldName: "currencyCode" } }
  }
];

export default class AbtDailyInvoiceReport extends LightningElement {
  startDate = new Date().toISOString().slice(0, 10);
  endDate = this.startDate;
  currencyCode = "USD";
  columns = COLUMNS;
  rows = [];
  errors = [];
  loading = false;
  resultLabel = "";
  detailColumns = [
    { label: "Item Name", fieldName: "lineName", wrapText: true },
    {
      label: "Invoice",
      fieldName: "invoiceUrl",
      type: "url",
      typeAttributes: {
        label: { fieldName: "invoiceName" },
        target: "_blank",
        tooltip: "Open invoice"
      }
    }
  ];
  selectedDetailRow;
  detailRows = [];
  detailsLoading = false;
  detailError = "";
  detailRequest = 0;
  context;
  contextLoading = true;
  contextError = "";

  connectedCallback() {
    this.loadContext();
  }

  async loadContext() {
    this.contextLoading = true;
    this.contextError = "";
    this.context = undefined;
    try {
      const context = await reportContext();
      if (
        typeof context?.isSandbox !== "boolean" ||
        context.stripeSource !==
          (context.isSandbox ? "Stripe (sandbox)" : "Stripe (live)")
      ) {
        throw new Error("Invalid report environment");
      }
      this.context = context;
    } catch (error) {
      this.contextError =
        error?.body?.message ||
        "Could not determine the reporting environment. Please retry.";
    } finally {
      this.contextLoading = false;
    }
  }

  get runDisabled() {
    return this.loading || this.contextLoading || !this.context;
  }
  get environmentBadge() {
    if (!this.context) return "Checking Stripe environment";
    return this.context.isSandbox ? "Stripe sandbox" : "Stripe live";
  }
  get stripeAccessNote() {
    if (!this.context)
      return "Stripe access depends on the reporting environment.";
    return this.context.isSandbox
      ? "Stripe links require access to the connected Stripe sandbox."
      : "Stripe links require access to the connected live Stripe account.";
  }
  get stripeDataNote() {
    if (!this.context)
      return "Stripe data is loaded only after the reporting environment is confirmed.";
    return this.context.isSandbox
      ? "Stripe uses creation date (UTC) and all invoices in the connected sandbox, including drafts and voided invoices."
      : "Stripe uses creation date (UTC) and all invoices in the connected live account, including drafts and voided invoices.";
  }

  handleChange(event) {
    this[event.target.name] = event.target.value;
  }

  async handleRun() {
    const inputs = [...this.template.querySelectorAll("lightning-input")];
    const valid = inputs.reduce(
      (ok, input) => input.reportValidity() && ok,
      true
    );
    if (!valid || this.runDisabled) return;
    this.closeDetails();
    this.errors = [];
    this.rows = [];
    this.resultLabel = "";
    const start = new Date(`${this.startDate}T00:00:00Z`);
    const end = new Date(`${this.endDate}T00:00:00Z`);
    const span = (end - start) / 86400000;
    if (!Number.isFinite(span) || span < 0 || span > 30) {
      this.errors = [
        {
          source: "Date range",
          message: "Choose a date range of 1 to 31 days."
        }
      ];
      return;
    }
    this.loading = true;
    const params = {
      startDate: this.startDate,
      endDate: this.endDate,
      currencyCode: this.currencyCode.trim().toUpperCase()
    };
    const sources = ["Salesforce", this.context.stripeSource];
    const results = await Promise.allSettled([
      salesforceRows(params),
      stripeRows(params)
    ]);
    const rows = [];
    const errors = [];
    results.forEach((result, index) => {
      if (result.status === "fulfilled") rows.push(...result.value);
      else
        errors.push({
          source: sources[index],
          message:
            result.reason?.body?.message ||
            "Could not load invoices. Check access and retry."
        });
    });
    this.rows = rows.sort(
      (a, b) =>
        b.invoiceDate.localeCompare(a.invoiceDate) ||
        a.systemName.localeCompare(b.systemName)
    );
    this.errors = errors;
    this.resultLabel = `${params.startDate} to ${params.endDate} · ${params.currencyCode}`;
    this.loading = false;
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  async handleRowAction(event) {
    if (event.detail.action.name !== "view_line_items") return;
    this.selectedDetailRow = { ...event.detail.row };
    await this.loadDetails();
  }

  async loadDetails() {
    if (!this.selectedDetailRow) return;
    const request = ++this.detailRequest;
    const row = this.selectedDetailRow;
    this.detailsLoading = true;
    this.detailError = "";
    this.detailRows = [];
    try {
      const details = await lineItems({
        invoiceDate: row.invoiceDate,
        currencyCode: row.currencyCode,
        systemName: row.systemName
      });
      if (request === this.detailRequest) this.detailRows = details;
    } catch (error) {
      if (request === this.detailRequest)
        this.detailError =
          error?.body?.message || "Could not load line items. Please retry.";
    } finally {
      if (request === this.detailRequest) {
        this.detailsLoading = false;
        this.template
          .querySelector(".details-panel")
          ?.scrollIntoView?.({ block: "nearest" });
      }
    }
  }

  closeDetails() {
    this.detailRequest++;
    this.selectedDetailRow = undefined;
    this.detailRows = [];
    this.detailsLoading = false;
    this.detailError = "";
  }

  get detailsOpen() {
    return Boolean(this.selectedDetailRow);
  }
  get detailTitle() {
    const row = this.selectedDetailRow;
    return row
      ? `${row.systemName} · ${row.invoiceDate} · ${row.currencyCode}`
      : "";
  }
  get hasDetailRows() {
    return this.detailRows.length > 0;
  }
  get showNoDetailRows() {
    return (
      this.detailsOpen &&
      !this.detailsLoading &&
      !this.detailError &&
      !this.hasDetailRows
    );
  }

  get showEmptyState() {
    return !this.loading && !this.hasRows && this.errors.length === 0;
  }

  get sourceSummaries() {
    const summaries = new Map();
    this.rows.forEach((row) => {
      if (!summaries.has(row.systemName)) {
        summaries.set(row.systemName, {
          source: row.systemName,
          currencyCode: row.currencyCode,
          invoicesCreated: 0,
          lineItems: 0,
          invoiceAmount: 0
        });
      }
      const summary = summaries.get(row.systemName);
      summary.invoicesCreated += row.invoicesCreated;
      summary.lineItems += row.lineItems;
      summary.invoiceAmount += row.invoiceAmount;
    });
    return [...summaries.values()];
  }
}
