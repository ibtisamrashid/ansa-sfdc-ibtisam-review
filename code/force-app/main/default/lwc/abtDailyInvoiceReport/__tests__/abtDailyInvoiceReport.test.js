import { createElement } from "lwc";
import AbtDailyInvoiceReport from "c/abtDailyInvoiceReport";
import salesforceRows from "@salesforce/apex/ABT_DailyInvoiceReport.salesforceRows";
import stripeRows from "@salesforce/apex/ABT_DailyInvoiceReport.stripeRows";
import lineItems from "@salesforce/apex/ABT_DailyInvoiceReport.lineItems";
import reportContext from "@salesforce/apex/ABT_DailyInvoiceReport.reportContext";

jest.mock(
  "@salesforce/apex/ABT_DailyInvoiceReport.salesforceRows",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ABT_DailyInvoiceReport.stripeRows",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ABT_DailyInvoiceReport.lineItems",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ABT_DailyInvoiceReport.reportContext",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = async () => {
  await Promise.resolve();
  await Promise.resolve();
};
const row = (systemName, day = "2026-10-30") => ({
  key: `${day}-${systemName}`,
  invoiceDate: day,
  systemName,
  currencyCode: "USD",
  invoicesCreated: 2,
  lineItems: 3,
  invoiceAmount: 125.25
});

async function mount() {
  const element = createElement("c-abt-daily-invoice-report", {
    is: AbtDailyInvoiceReport
  });
  document.body.appendChild(element);
  element.shadowRoot.querySelectorAll("lightning-input").forEach((input) => {
    input.reportValidity = jest.fn(() => true);
    const value = input.name === "currencyCode" ? "USD" : "2026-10-30";
    input.value = value;
    input.dispatchEvent(new CustomEvent("change"));
  });
  await flush();
  return element;
}

describe("daily invoicing report", () => {
  beforeEach(() => {
    reportContext.mockResolvedValue({
      isSandbox: true,
      stripeSource: "Stripe (sandbox)"
    });
  });
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("renders both systems grouped by date and labels sandbox data", async () => {
    salesforceRows.mockResolvedValue([row("Salesforce")]);
    stripeRows.mockResolvedValue([row("Stripe (sandbox)")]);
    const element = await mount();
    element.shadowRoot.querySelector("lightning-button").click();
    await flush();
    const table = element.shadowRoot.querySelector("lightning-datatable");
    expect(table.data).toHaveLength(2);
    expect(table.data.map((item) => item.systemName)).toEqual([
      "Salesforce",
      "Stripe (sandbox)"
    ]);
    expect(salesforceRows).toHaveBeenCalledWith({
      startDate: "2026-10-30",
      endDate: "2026-10-30",
      currencyCode: "USD"
    });
    expect(element.shadowRoot.textContent).toContain("Stripe sandbox");
    expect(element.shadowRoot.querySelector("lightning-button").disabled).toBe(
      false
    );
  });

  it("labels production as live and uses live invoice links", async () => {
    reportContext.mockResolvedValue({
      isSandbox: false,
      stripeSource: "Stripe (live)"
    });
    salesforceRows.mockResolvedValue([row("Salesforce")]);
    stripeRows.mockResolvedValue([row("Stripe (live)")]);
    const liveDetails = [
      {
        key: "live-line",
        lineName: "Synthetic service",
        invoiceName: "in_live",
        invoiceUrl:
          "https://dashboard.stripe.com/acct_synthetic/invoices/in_live"
      }
    ];
    lineItems.mockResolvedValue(liveDetails);
    const element = await mount();
    expect(
      element.shadowRoot.querySelector(".environment-badge").textContent
    ).toBe("Stripe live");
    expect(element.shadowRoot.textContent).not.toContain("Stripe sandbox");
    element.shadowRoot.querySelector("lightning-button").click();
    await flush();
    element.shadowRoot.querySelector("lightning-datatable").dispatchEvent(
      new CustomEvent("rowaction", {
        detail: {
          action: { name: "view_line_items" },
          row: row("Stripe (live)")
        }
      })
    );
    await flush();
    expect(lineItems).toHaveBeenCalledWith({
      invoiceDate: "2026-10-30",
      currencyCode: "USD",
      systemName: "Stripe (live)"
    });
    expect(
      element.shadowRoot.querySelector(".details-panel lightning-datatable")
        .data
    ).toEqual(liveDetails);
    expect(
      element.shadowRoot.querySelector(".details-panel").textContent
    ).toContain("connected live Stripe account");
  });

  it("labels a failed production read as live rather than sandbox", async () => {
    reportContext.mockResolvedValue({
      isSandbox: false,
      stripeSource: "Stripe (live)"
    });
    salesforceRows.mockResolvedValue([row("Salesforce")]);
    stripeRows.mockRejectedValue({
      body: { message: "No matching live account" }
    });
    const element = await mount();
    element.shadowRoot.querySelector("lightning-button").click();
    await flush();
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("Stripe (live) unavailable");
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).not.toContain("sandbox");
  });

  it("blocks reads when the environment cannot be determined and supports retry", async () => {
    reportContext.mockRejectedValue({
      body: { message: "Environment check failed" }
    });
    const element = await mount();
    const run = [
      ...element.shadowRoot.querySelectorAll("lightning-button")
    ].find((button) => button.label === "Run report");
    expect(run.disabled).toBe(true);
    run.click();
    await flush();
    expect(salesforceRows).not.toHaveBeenCalled();
    expect(stripeRows).not.toHaveBeenCalled();
    reportContext.mockResolvedValue({
      isSandbox: false,
      stripeSource: "Stripe (live)"
    });
    const retry = [
      ...element.shadowRoot.querySelectorAll("lightning-button")
    ].find((button) => button.label === "Retry environment check");
    retry.click();
    await flush();
    expect(run.disabled).toBe(false);
    expect(
      element.shadowRoot.querySelector(".environment-badge").textContent
    ).toBe("Stripe live");
  });

  it("rejects contradictory environment settings before reading invoice data", async () => {
    reportContext.mockResolvedValue({
      isSandbox: false,
      stripeSource: "Stripe (sandbox)"
    });
    const element = await mount();
    const run = [
      ...element.shadowRoot.querySelectorAll("lightning-button")
    ].find((button) => button.label === "Run report");
    expect(run.disabled).toBe(true);
    run.click();
    await flush();
    expect(stripeRows).not.toHaveBeenCalled();
    expect(salesforceRows).not.toHaveBeenCalled();
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("Could not determine the reporting environment");
  });

  it("keeps Salesforce results and shows a Stripe failure instead of zero", async () => {
    salesforceRows.mockResolvedValue([row("Salesforce")]);
    stripeRows.mockRejectedValue({
      body: { message: "Sandbox connection unavailable" }
    });
    const element = await mount();
    element.shadowRoot.querySelector("lightning-button").click();
    await flush();
    expect(
      element.shadowRoot.querySelector("lightning-datatable").data
    ).toEqual([row("Salesforce")]);
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("Sandbox connection unavailable");
    expect(element.shadowRoot.querySelectorAll(".source-card")).toHaveLength(1);
    expect(element.shadowRoot.querySelector(".source-name").textContent).toBe(
      "Salesforce"
    );
    expect(element.shadowRoot.querySelector("lightning-button").disabled).toBe(
      false
    );
  });

  it("rejects reversed dates without calling either source", async () => {
    const element = await mount();
    const end = [
      ...element.shadowRoot.querySelectorAll("lightning-input")
    ].find((input) => input.name === "endDate");
    end.value = "2026-10-29";
    end.dispatchEvent(new CustomEvent("change"));
    element.shadowRoot.querySelector("lightning-button").click();
    await flush();
    expect(salesforceRows).not.toHaveBeenCalled();
    expect(stripeRows).not.toHaveBeenCalled();
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("1 to 31 days");
  });

  it("prevents duplicate requests while loading and recovers after both fail", async () => {
    let rejectSalesforce;
    salesforceRows.mockReturnValue(
      new Promise((resolve, reject) => {
        rejectSalesforce = reject;
      })
    );
    stripeRows.mockRejectedValue(new Error("unavailable"));
    const element = await mount();
    const button = element.shadowRoot.querySelector("lightning-button");
    button.click();
    button.click();
    await flush();
    expect(salesforceRows).toHaveBeenCalledTimes(1);
    expect(button.disabled).toBe(true);
    rejectSalesforce(new Error("unavailable"));
    await flush();
    expect(element.shadowRoot.querySelectorAll('[role="alert"]')).toHaveLength(
      2
    );
    expect(element.shadowRoot.querySelector("lightning-datatable")).toBeNull();
    expect(button.disabled).toBe(false);
    salesforceRows.mockResolvedValue([row("Salesforce")]);
    stripeRows.mockResolvedValue([row("Stripe (sandbox)")]);
    button.click();
    await flush();
    expect(element.shadowRoot.querySelectorAll('[role="alert"]')).toHaveLength(
      0
    );
    expect(
      element.shadowRoot.querySelector("lightning-datatable").data
    ).toHaveLength(2);
  });

  it("honors required input validation without requesting data", async () => {
    const element = await mount();
    element.shadowRoot
      .querySelector("lightning-input")
      .reportValidity.mockReturnValue(false);
    element.shadowRoot.querySelector("lightning-button").click();
    await flush();
    expect(salesforceRows).not.toHaveBeenCalled();
  });

  it("shows an initial prompt without implying that invoice totals are zero", async () => {
    const element = await mount();
    await flush();
    expect(element.shadowRoot.querySelector("h1").textContent).toBe(
      "Daily Invoicing Report"
    );
    expect(
      element.shadowRoot.querySelector(".empty-state").textContent
    ).toContain("run the report");
    expect(element.shadowRoot.querySelector("lightning-datatable")).toBeNull();
    expect(element.shadowRoot.querySelectorAll(".source-card")).toHaveLength(0);
    expect(salesforceRows).not.toHaveBeenCalled();
  });

  it("opens the selected date's line items with links to their parent invoices", async () => {
    salesforceRows.mockResolvedValue([row("Salesforce")]);
    stripeRows.mockResolvedValue([row("Stripe (sandbox)")]);
    const details = [
      {
        key: "synthetic-line",
        lineName: "Synthetic line",
        invoiceName: "INV-TEST",
        invoiceUrl: "/lightning/r/ABT_Invoice__c/synthetic/view"
      }
    ];
    lineItems.mockResolvedValue(details);
    const element = await mount();
    element.shadowRoot.querySelector("lightning-button").click();
    await flush();
    const table = element.shadowRoot.querySelector("lightning-datatable");
    expect(
      table.columns.find((column) => column.fieldName === "lineItems").type
    ).toBe("button");
    table.dispatchEvent(
      new CustomEvent("rowaction", {
        detail: { action: { name: "view_line_items" }, row: row("Salesforce") }
      })
    );
    await flush();
    expect(lineItems).toHaveBeenCalledWith({
      invoiceDate: "2026-10-30",
      currencyCode: "USD",
      systemName: "Salesforce"
    });
    const detailTable = element.shadowRoot.querySelector(
      ".details-panel lightning-datatable"
    );
    expect(detailTable.data).toEqual(details);
    expect(detailTable.columns[0]).toMatchObject({
      label: "Item Name",
      fieldName: "lineName",
      wrapText: true
    });
    expect(detailTable.columns[1]).toMatchObject({
      fieldName: "invoiceUrl",
      type: "url",
      typeAttributes: { label: { fieldName: "invoiceName" }, target: "_blank" }
    });
    element.shadowRoot.querySelector("lightning-button-icon").click();
    await flush();
    expect(element.shadowRoot.querySelector(".details-panel")).toBeNull();
  });

  it("shows a detail failure and can retry without changing the daily totals", async () => {
    salesforceRows.mockResolvedValue([row("Salesforce")]);
    stripeRows.mockResolvedValue([row("Stripe (sandbox)")]);
    lineItems.mockRejectedValue({ body: { message: "Source unavailable" } });
    const element = await mount();
    element.shadowRoot.querySelector("lightning-button").click();
    await flush();
    element.shadowRoot.querySelector("lightning-datatable").dispatchEvent(
      new CustomEvent("rowaction", {
        detail: {
          action: { name: "view_line_items" },
          row: row("Stripe (sandbox)")
        }
      })
    );
    await flush();
    expect(
      element.shadowRoot.querySelector(".details-panel [role='alert']")
        .textContent
    ).toBe("Source unavailable");
    expect(
      element.shadowRoot.querySelector("lightning-datatable").data
    ).toHaveLength(2);
    lineItems.mockResolvedValue([]);
    element.shadowRoot.querySelector(".details-panel lightning-button").click();
    await flush();
    expect(
      element.shadowRoot.querySelector(".details-panel [role='alert']")
    ).toBeNull();
    expect(
      element.shadowRoot.querySelector(".details-panel [role='status']")
        .textContent
    ).toContain("No line items");
  });

  it("ignores an older detail response after a different source is selected", async () => {
    salesforceRows.mockResolvedValue([row("Salesforce")]);
    stripeRows.mockResolvedValue([row("Stripe (sandbox)")]);
    let resolveFirst;
    lineItems.mockReturnValueOnce(
      new Promise((resolve) => {
        resolveFirst = resolve;
      })
    );
    const stripeDetails = [
      {
        key: "stripe-line",
        lineName: "il_test",
        invoiceName: "in_test",
        invoiceUrl:
          "https://dashboard.stripe.com/acct_test/test/invoices/in_test"
      }
    ];
    lineItems.mockResolvedValueOnce(stripeDetails);
    const element = await mount();
    element.shadowRoot.querySelector("lightning-button").click();
    await flush();
    const table = element.shadowRoot.querySelector("lightning-datatable");
    for (const source of ["Salesforce", "Stripe (sandbox)"]) {
      table.dispatchEvent(
        new CustomEvent("rowaction", {
          detail: { action: { name: "view_line_items" }, row: row(source) }
        })
      );
    }
    await flush();
    resolveFirst([{ key: "old", invoiceName: "Wrong source" }]);
    await flush();
    expect(
      element.shadowRoot.querySelector(".details-panel lightning-datatable")
        .data
    ).toEqual(stripeDetails);
    expect(
      element.shadowRoot.querySelector(".details-panel").textContent
    ).toContain("Stripe (sandbox)");
  });

  it("summarizes each system separately across the selected dates", async () => {
    salesforceRows.mockResolvedValue([
      row("Salesforce"),
      {
        ...row("Salesforce", "2026-10-29"),
        invoicesCreated: 1,
        lineItems: 4,
        invoiceAmount: 10.5
      }
    ]);
    stripeRows.mockResolvedValue([
      {
        ...row("Stripe (sandbox)"),
        invoicesCreated: 0,
        lineItems: 0,
        invoiceAmount: 0
      }
    ]);
    const element = await mount();
    element.shadowRoot.querySelector("lightning-button").click();
    await flush();
    const cards = [...element.shadowRoot.querySelectorAll(".source-card")];
    expect(
      cards.map((card) => card.querySelector(".source-name").textContent)
    ).toEqual(["Salesforce", "Stripe (sandbox)"]);
    expect(
      [...cards[0].querySelectorAll("lightning-formatted-number")].map(
        (number) => number.value
      )
    ).toEqual([3, 7, 135.75]);
    expect(
      [...cards[1].querySelectorAll("lightning-formatted-number")].map(
        (number) => number.value
      )
    ).toEqual([0, 0, 0]);
    expect(
      cards[0].querySelectorAll("lightning-formatted-number")[2].currencyCode
    ).toBe("USD");
    expect(element.shadowRoot.querySelector(".empty-state")).toBeNull();
  });
});
