import saveVector from "@salesforce/apex/SequenceHubActions.saveVector";
jest.mock(
  "@salesforce/apex/SequenceHubActions.saveVector",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
import { CurrentPageReference } from "lightning/navigation";
import requestAnnotation from "@salesforce/apex/SequenceHubAnnotation.requestAnnotation";
jest.mock(
  "@salesforce/apex/SequenceHubAnnotation.requestAnnotation",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
import annotationConfigured from "@salesforce/apex/SequenceHubAnnotation.isConfigured";
jest.mock(
  "@salesforce/apex/SequenceHubAnnotation.isConfigured",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
import requestFeasibility from "@salesforce/apex/SequenceHubActions.requestFeasibility";
jest.mock(
  "@salesforce/apex/SequenceHubActions.requestFeasibility",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
import renameSequence from "@salesforce/apex/SequenceHubActions.renameSequence";
jest.mock(
  "@salesforce/apex/SequenceHubActions.renameSequence",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
import saveAnnotations from "@salesforce/apex/SequenceHubActions.saveAnnotations";
import appendManualAnnotations from "@salesforce/apex/SequenceHubActions.appendManualAnnotations";
import removeManualFeature from "@salesforce/apex/SequenceHubActions.removeManualFeature";
jest.mock(
  "@salesforce/apex/SequenceHubActions.appendManualAnnotations",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/SequenceHubActions.removeManualFeature",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
import removePlannotateFeature from "@salesforce/apex/SequenceHubActions.removePlannotateFeature";
jest.mock(
  "@salesforce/apex/SequenceHubActions.removePlannotateFeature",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/SequenceHubActions.saveAnnotations",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
import addToQuote from "@salesforce/apex/SequenceHubActions.addToQuote";
jest.mock(
  "@salesforce/apex/SequenceHubActions.addToQuote",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
import getQuoteOptions from "@salesforce/apex/SequenceHubActions.getQuoteOptions";
jest.mock(
  "@salesforce/apex/SequenceHubActions.getQuoteOptions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
import { createElement } from "lwc";
import { loadScript } from "lightning/platformResourceLoader";
jest.mock("lightning/platformResourceLoader", () => ({
  loadScript: jest.fn().mockResolvedValue()
}));
import SequenceHub from "c/sequenceHub";
import getSequences from "@salesforce/apex/SequenceHubController.getSequences";
import uploadSequences from "@salesforce/apex/SequenceUploadController.uploadSequences";
import getSequence from "@salesforce/apex/SequenceHubController.getSequence";

jest.mock(
  "@salesforce/apex/SequenceHubController.getSequences",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/SequenceHubController.getSequence",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/SequenceUploadController.uploadSequences",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flushPromises = async () => {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
};

describe("c-sequence-hub", () => {
  beforeEach(() => {
    getQuoteOptions.mockReset().mockResolvedValue({ quotes: [], vectors: [] });
    addToQuote.mockReset().mockResolvedValue({ added: 1 });
    saveVector.mockReset().mockResolvedValue();
    renameSequence.mockReset().mockResolvedValue();
    saveAnnotations.mockReset().mockResolvedValue([]);
    appendManualAnnotations.mockReset().mockResolvedValue();
    removeManualFeature.mockReset().mockResolvedValue();
    removePlannotateFeature.mockReset().mockResolvedValue();
    requestFeasibility.mockReset().mockResolvedValue();
    annotationConfigured.mockReset().mockResolvedValue(false);
    requestAnnotation.mockReset().mockResolvedValue("job");
    getSequences.mockReset().mockResolvedValue([]);
    getSequence.mockReset();
    uploadSequences.mockReset().mockResolvedValue({ created: 1 });
  });

  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    delete window.XLSX;
    jest.restoreAllMocks();
    jest.clearAllMocks();
  });

  it("returns to the list when navigation clears the detail route", async () => {
    const element = await openDetail();
    expect(element.shadowRoot.textContent).toContain("Sequence ID");
    getSequences.mockResolvedValue([
      { id: "a01000000000001AAA", sequenceName: "Construct" }
    ]);
    CurrentPageReference.emit({
      type: "comm__namedPage",
      attributes: { name: "Sequences__c" },
      state: {}
    });
    await flushPromises();
    expect(element.shadowRoot.querySelector("tbody")).not.toBeNull();
    expect(
      element.shadowRoot.querySelector('[aria-label="Edit vector"]')
    ).toBeNull();
    CurrentPageReference.emit({
      type: "comm__namedPage",
      attributes: { name: "Sequences__c" },
      state: { c__sequenceId: "a01000000000001AAA" }
    });
    await flushPromises();
    expect(
      element.shadowRoot.querySelector('[aria-label="Edit vector"]')
    ).not.toBeNull();
  });

  it("appends a manual annotation and refreshes its chip", async () => {
    const existing = { label: "Existing", start: 1, end: 2, strand: "1" };
    const added = { label: "New feature", start: 3, end: 6, strand: "-1" };
    const element = await openDetail({ manualFeatures: [existing] });
    clickButton(element, "Add manual annotation");
    await flushPromises();
    await changeField(element, "featureLabel", "New feature");
    await changeField(element, "featureStart", "3");
    await changeField(element, "featureEnd", "6");
    await changeField(element, "featureStrand", "-1");
    getSequence.mockResolvedValue({
      id: "a01000000000001AAA",
      sequence: "ACGTACGT",
      manualFeatures: [existing, added],
      plannotateFeatures: []
    });
    clickButton(element, "Add annotation");
    await flushPromises();
    expect(appendManualAnnotations).toHaveBeenCalledWith({
      sequenceId: "a01000000000001AAA",
      annotationsJson: JSON.stringify([added])
    });
    expect(element.shadowRoot.querySelector('[role="dialog"]')).toBeNull();
    expect(element.shadowRoot.textContent).toContain("Existing");
    expect(element.shadowRoot.textContent).toContain("New feature");
  });

  it("rejects out-of-range annotation coordinates and cancels without saving", async () => {
    const element = await openDetail();
    clickButton(element, "Add manual annotation");
    await flushPromises();
    await changeField(element, "featureLabel", "Feature");
    await changeField(element, "featureStart", "1");
    await changeField(element, "featureEnd", "9");
    clickButton(element, "Add annotation");
    await flushPromises();
    expect(appendManualAnnotations).not.toHaveBeenCalled();
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("within the DNA");
    clickButton(element, "Cancel");
    await flushPromises();
    expect(element.shadowRoot.querySelector('[role="dialog"]')).toBeNull();
  });

  it("keeps annotation inputs available for retry when saving fails", async () => {
    const element = await openDetail();
    clickButton(element, "Add manual annotation");
    await flushPromises();
    await changeField(element, "featureLabel", "Feature");
    await changeField(element, "featureStart", "1");
    await changeField(element, "featureEnd", "2");
    appendManualAnnotations.mockRejectedValueOnce(new Error("Please retry"));
    clickButton(element, "Add annotation");
    await flushPromises();
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("Please retry");
    expect(
      element.shadowRoot.querySelector('[data-field="featureLabel"]').value
    ).toBe("Feature");
    expect(element.shadowRoot.querySelector('[role="dialog"]')).not.toBeNull();
  });

  it("keeps the unconfirmed visualization workflow unavailable", async () => {
    const element = await openDetail();

    const visualize = [...element.shadowRoot.querySelectorAll("button")].find(
      (button) => button.textContent.includes("Visualize")
    );
    expect(visualize.disabled).toBe(true);
    expect(
      element.shadowRoot.querySelector("c-sequence-visualizer")
    ).toBeNull();
  });

  it("loads sequence rows and applies filters with pagination", async () => {
    getSequences.mockResolvedValue([
      {
        id: "a01000000000001AAA",
        sequenceName: "Test construct",
        sequenceNumber: "SQ-000001",
        length: 120,
        feasibility: "Feasible",
        complexity: "Standard",
        ownerName: "Test Buyer"
      }
    ]);
    const element = createElement("c-sequence-hub", { is: SequenceHub });
    document.body.appendChild(element);
    await flushPromises();

    expect(getSequences).toHaveBeenCalledWith(
      expect.objectContaining({ pageSize: 25, offsetRows: 0 })
    );
    expect(element.shadowRoot.querySelectorAll("tbody tr")).toHaveLength(1);

    const searchInput = element.shadowRoot.querySelector("input[type=search]");
    searchInput.value = "Test";
    searchInput.dispatchEvent(new CustomEvent("input"));
    element.shadowRoot.querySelector('[aria-label="Run search"]').click();
    await flushPromises();

    expect(getSequences).toHaveBeenLastCalledWith(
      expect.objectContaining({ searchTerm: "Test", offsetRows: 0 })
    );
  });

  it("opens an accessible sequence detail without the top navigation buttons", async () => {
    getSequences.mockResolvedValue([
      { id: "a01000000000001AAA", sequenceName: "Test construct" }
    ]);
    getSequence.mockResolvedValue({
      id: "a01000000000001AAA",
      sequenceNumber: "SQ-000001",
      sequenceName: "Test construct",
      sequence: "ATGC",
      length: 4,
      feasibility: "Feasible",
      complexity: "Standard"
    });
    const element = createElement("c-sequence-hub", { is: SequenceHub });
    document.body.appendChild(element);
    await flushPromises();

    element.shadowRoot.querySelector("tbody tr").click();
    await flushPromises();

    expect(getSequence).toHaveBeenCalledWith({
      sequenceId: "a01000000000001AAA"
    });
    expect(element.shadowRoot.textContent).toContain("ATGC");
    const buttonLabels = Array.from(
      element.shadowRoot.querySelectorAll("lightning-button")
    ).map((button) => button.label);
    expect(buttonLabels).not.toContain("Back to sequences");
    expect(buttonLabels).not.toContain("Refresh");
  });

  it("disables optimization when the sequence is not eligible", async () => {
    getSequences.mockResolvedValue([
      { id: "a01000000000001AAA", sequenceName: "Test construct" }
    ]);
    getSequence.mockResolvedValue({
      id: "a01000000000001AAA",
      sequenceNumber: "SQ-000001",
      sequenceName: "Test construct",
      sequence: "ATGC",
      optimizationAvailable: false,
      optimizationUnavailableReason:
        "This sequence has no linked amino acid protein to optimize."
    });
    const element = createElement("c-sequence-hub", { is: SequenceHub });
    document.body.appendChild(element);
    await flushPromises();
    element.shadowRoot.querySelector("tbody tr").click();
    await flushPromises();
    const buttons = [
      ...element.shadowRoot.querySelectorAll("lightning-button, button")
    ];
    expect(
      buttons.find(
        (button) => (button.label || button.textContent.trim()) === "Optimize"
      ).disabled
    ).toBe(true);
    expect(element.shadowRoot.textContent).toContain(
      "This sequence has no linked amino acid protein to optimize."
    );
  });
  async function mount() {
    const element = createElement("c-sequence-hub", { is: SequenceHub });
    document.body.appendChild(element);
    await flushPromises();
    return element;
  }

  function search(element, value) {
    const input = element.shadowRoot.querySelector("input[type=search]");
    input.value = value;
    input.dispatchEvent(new CustomEvent("input"));
    input.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter" }));
  }

  it("keeps the newest search when requests finish out of order", async () => {
    const element = await mount();
    let resolveOld;
    getSequences.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          resolveOld = resolve;
        })
    );
    search(element, "old");
    getSequences.mockResolvedValueOnce([{ id: "new", sequenceName: "Newest" }]);
    search(element, "new");
    await flushPromises();
    resolveOld([{ id: "old", sequenceName: "Outdated" }]);
    await flushPromises();
    expect(element.shadowRoot.textContent).toContain("Newest");
    expect(element.shadowRoot.textContent).not.toContain("Outdated");
  });

  it("retries the same page after a failed load more", async () => {
    getSequences.mockResolvedValueOnce(
      Array.from({ length: 25 }, (_, i) => ({ id: String(i) }))
    );
    const element = await mount();
    getSequences.mockRejectedValueOnce({ body: { message: "Try again" } });
    element.shadowRoot.querySelector("lightning-button").click();
    await flushPromises();
    expect(element.shadowRoot.querySelectorAll("tbody tr")).toHaveLength(25);
    expect(element.shadowRoot.textContent).toContain("Try again");
    getSequences.mockResolvedValueOnce([
      { id: "next", sequenceName: "Next page" }
    ]);
    element.shadowRoot.querySelector("lightning-button").click();
    await flushPromises();
    expect(
      getSequences.mock.calls.slice(-2).map(([args]) => args.offsetRows)
    ).toEqual([25, 25]);
    expect(element.shadowRoot.querySelectorAll("tbody tr")).toHaveLength(26);
  });

  it("applies and clears draft filters", async () => {
    const element = await mount();
    element.shadowRoot.querySelector('[aria-label="Filter sequences"]').click();
    await flushPromises();
    const input = element.shadowRoot.querySelector(
      '[data-field="draftFeasibility"]'
    );
    input.value = "Feasible";
    input.dispatchEvent(new CustomEvent("change"));
    expect(getSequences).toHaveBeenCalledTimes(1);
    element.shadowRoot.querySelector(".filter-actions .btn-solid").click();
    await flushPromises();
    expect(getSequences).toHaveBeenLastCalledWith(
      expect.objectContaining({ feasibility: "Feasible", offsetRows: 0 })
    );
    element.shadowRoot.querySelector('[aria-label="Filter sequences"]').click();
    await flushPromises();
    element.shadowRoot.querySelector(".filter-actions .btn-outline").click();
    await flushPromises();
    expect(getSequences).toHaveBeenLastCalledWith(
      expect.objectContaining({ feasibility: "" })
    );
  });

  it("does not open detail when a checkbox receives Space", async () => {
    getSequences.mockResolvedValueOnce([{ id: "one", sequenceName: "One" }]);
    const element = await mount();
    const checkbox = element.shadowRoot.querySelector(
      "tbody input[type=checkbox]"
    );
    checkbox.dispatchEvent(
      new KeyboardEvent("keydown", { key: " ", bubbles: true })
    );
    checkbox.checked = true;
    checkbox.dispatchEvent(new CustomEvent("change"));
    await flushPromises();
    expect(getSequence).not.toHaveBeenCalled();
    expect(element.shadowRoot.textContent).toContain("1 selected");
  });

  it("shows errors when detail cannot be loaded", async () => {
    getSequences.mockResolvedValueOnce([{ id: "one" }]);
    getSequence.mockRejectedValueOnce({ body: { message: "Unavailable" } });
    const element = await mount();
    element.shadowRoot
      .querySelector('[aria-label="Optimize sequence"]')
      .click();
    await flushPromises();
    expect(element.shadowRoot.textContent).toContain("Unavailable");
    expect(element.shadowRoot.querySelector("c-codon-optimizer")).toBeNull();
  });

  async function upload(element, name, contents) {
    jest.spyOn(window, "FileReader").mockImplementation(() => ({
      result: contents,
      readAsText() {
        this.onload();
      },
      readAsArrayBuffer() {
        this.onload();
      }
    }));
    const input = element.shadowRoot.querySelector("input[type=file]");
    Object.defineProperty(input, "files", {
      configurable: true,
      value: [new File([contents], name)]
    });
    input.dispatchEvent(new CustomEvent("change"));

    await flushPromises();
  }

  it("imports multiple FASTA records and refreshes the list", async () => {
    const element = await mount();
    await upload(
      element,
      "test.fasta",
      ">first description\nacgt nn\n>second\nGGCC"
    );
    expect(uploadSequences).toHaveBeenCalledWith({
      names: ["first", "second"],
      sequences: ["ACGTNN", "GGCC"]
    });
    expect(getSequences).toHaveBeenCalledTimes(2);
    expect(element.shadowRoot.textContent).toContain("Upload complete");
  });

  it("rejects invalid characters without silently changing the DNA", async () => {
    const element = await mount();
    await upload(element, "bad.fa", ">valid\nACGT\n>invalid\nAC-GT123");
    expect(uploadSequences).not.toHaveBeenCalled();
    expect(element.shadowRoot.textContent).toContain("Nothing was added");
  });

  it("imports numbered GenBank ORIGIN lines", async () => {
    const element = await mount();
    await upload(
      element,
      "test.gb",
      "LOCUS       TEST\nORIGIN\n        1 acgt nn\n//\n"
    );
    expect(uploadSequences).toHaveBeenCalledWith({
      names: ["TEST"],
      sequences: ["ACGTNN"]
    });
  });
  it("opens the shared optimizer and displays its new copy on completion", async () => {
    getSequences.mockResolvedValueOnce([
      { id: "original", sequenceName: "Original" }
    ]);
    getSequence.mockResolvedValueOnce({
      id: "original",
      sequenceName: "Original",
      optimizationAvailable: true,
      aminoAcidId: "protein",
      aminoAcidSequence: "MK*"
    });
    const element = await mount();
    element.shadowRoot
      .querySelector('[aria-label="Optimize sequence"]')
      .click();
    await flushPromises();
    const optimizer = element.shadowRoot.querySelector("c-codon-optimizer");
    expect(optimizer).not.toBeNull();
    getSequence.mockResolvedValueOnce({
      id: "copy",
      sequenceName: "Original_optimized",
      sequence: "ACGT"
    });
    optimizer.dispatchEvent(
      new CustomEvent("optimized", { detail: { optimizedSequenceId: "copy" } })
    );
    await flushPromises();
    expect(getSequence).toHaveBeenLastCalledWith({ sequenceId: "copy" });
    expect(element.shadowRoot.textContent).toContain("Original_optimized");
    expect(element.shadowRoot.querySelector("c-codon-optimizer")).toBeNull();
  });

  it("keeps the applied search while paging after an unsubmitted edit", async () => {
    getSequences.mockResolvedValueOnce(
      Array.from({ length: 25 }, (_, i) => ({ id: String(i) }))
    );
    const element = await mount();
    const input = element.shadowRoot.querySelector("input[type=search]");
    input.value = "not submitted";
    input.dispatchEvent(new CustomEvent("input"));
    element.shadowRoot.querySelector("lightning-button").click();
    await flushPromises();
    expect(getSequences).toHaveBeenLastCalledWith(
      expect.objectContaining({ searchTerm: "", offsetRows: 25 })
    );
  });
  it("imports spreadsheet columns using their headers", async () => {
    window.XLSX = {
      read: jest.fn().mockReturnValue({
        SheetNames: ["Sequences"],
        Sheets: { Sequences: {} }
      }),
      utils: {
        sheet_to_json: jest.fn().mockReturnValue([
          ["Sequence", "Sequence Name"],
          ["acgt nn", "Spreadsheet DNA"]
        ])
      }
    };
    const element = await mount();
    await upload(element, "sequences.xlsx", "placeholder binary");
    expect(loadScript).toHaveBeenCalled();
    expect(uploadSequences).toHaveBeenCalledWith({
      names: ["Spreadsheet DNA"],
      sequences: ["ACGTNN"]
    });
  });
  async function openDetail(data = {}) {
    getSequences.mockResolvedValueOnce([
      { id: "a01000000000001AAA", sequenceName: "Construct" }
    ]);
    getSequence.mockResolvedValue({
      id: "a01000000000001AAA",
      sequenceName: "Construct",
      sequence: "ACGTACGT",
      manualFeatures: [],
      plannotateFeatures: [],
      ...data
    });
    const element = await mount();
    element.shadowRoot.querySelector("tbody tr").click();
    await flushPromises();
    return element;
  }
  function clickButton(element, label) {
    const button = [
      ...element.shadowRoot.querySelectorAll(
        "lightning-button, lightning-button-icon, button"
      )
    ].find(
      (item) =>
        (item.label ||
          item.alternativeText ||
          item.getAttribute("aria-label") ||
          item.textContent.trim()) === label
    );
    expect(button).toBeDefined();
    button.click();
  }
  async function changeField(element, field, value) {
    const input = element.shadowRoot.querySelector(
      '[data-field="' + field + '"]'
    );
    input.value = value;
    input.dispatchEvent(new CustomEvent("change", { detail: { value } }));
    await flushPromises();
  }

  it("adds selected DNA to the chosen quote using the existing creation path", async () => {
    getQuoteOptions.mockResolvedValueOnce({
      quotes: [{ value: "quote-1", label: "Draft quote" }],
      vectors: [{ value: "vector-1", label: "Catalog vector" }]
    });
    const element = await openDetail();
    clickButton(element, "Add to quote");
    await flushPromises();
    await changeField(element, "selectedQuote", "quote-1");
    await changeField(element, "selectedVector", "vector-1");
    clickButton(element, "Add selected sequences");
    await flushPromises();
    expect(addToQuote).toHaveBeenCalledWith({
      sequenceIds: ["a01000000000001AAA"],
      quoteRequestId: "quote-1",
      vectorId: "vector-1"
    });
    expect(element.shadowRoot.textContent).toContain(
      "copied to the selected quote"
    );
  });

  it("keeps the quote dialog open with an actionable error after rejection", async () => {
    getQuoteOptions.mockResolvedValueOnce({
      quotes: [{ value: "quote-1", label: "Draft quote" }],
      vectors: []
    });
    addToQuote.mockRejectedValueOnce({
      body: { message: "Choose an open quote for your account." }
    });
    const element = await openDetail();
    clickButton(element, "Add to quote");
    await flushPromises();
    await changeField(element, "selectedQuote", "quote-1");
    clickButton(element, "Add selected sequences");
    await flushPromises();
    expect(element.shadowRoot.querySelector('[role="dialog"]')).not.toBeNull();
    expect(element.shadowRoot.textContent).toContain(
      "Choose an open quote for your account."
    );
  });

  it("shares a link without granting extra access and opens deep-linked records", async () => {
    const element = await openDetail();
    clickButton(element, "Share");
    await flushPromises();
    expect(element.shadowRoot.querySelector(".share-url").value).toBe(
      "https://www.example.com/"
    );
    expect(element.shadowRoot.textContent).toContain(
      "grants no new permissions"
    );
    CurrentPageReference.emit({
      state: { c__sequenceId: "a01000000000002AAA" }
    });
    await flushPromises();
    expect(getSequence).toHaveBeenLastCalledWith({
      sequenceId: "a01000000000002AAA"
    });
  });

  it("requests feasibility and refreshes the returned status", async () => {
    requestFeasibility.mockResolvedValueOnce();
    const element = await openDetail({ feasibility: "Pending" });
    clickButton(element, "Request feasibility");
    await flushPromises();
    expect(requestFeasibility).toHaveBeenCalledWith({
      sequenceId: "a01000000000001AAA"
    });
    expect(element.shadowRoot.textContent).toContain("Feasibility requested");
  });

  it("enables hosted annotation only when configured", async () => {
    annotationConfigured.mockResolvedValueOnce(true);
    const element = await openDetail();
    const run = element.shadowRoot.querySelector(
      '[aria-label="Run Plannotate"]'
    );
    expect(run.disabled).toBe(false);
    run.click();
    await flushPromises();
    expect(requestAnnotation).toHaveBeenCalledWith({
      sequenceId: "a01000000000001AAA"
    });
  });
  it("renames a sequence through the Hub action and refreshes its detail", async () => {
    const element = await openDetail();
    [...element.shadowRoot.querySelectorAll("lightning-button-icon")]
      .find((button) => button.alternativeText === "Rename sequence")
      .click();
    await flushPromises();
    await changeField(element, "draftName", "Renamed construct");
    clickButton(element, "Save name");
    await flushPromises();
    expect(renameSequence).toHaveBeenCalledWith({
      sequenceId: "a01000000000001AAA",
      name: "Renamed construct"
    });
  });
  it("saves a selected vector and refreshes feasibility", async () => {
    getQuoteOptions.mockResolvedValueOnce({
      quotes: [],
      vectors: [{ label: "Catalog", value: "vector-1" }]
    });
    const element = await openDetail();
    clickButton(element, "Edit vector");
    await flushPromises();
    expect(element.shadowRoot.querySelector('[role="dialog"]')).toBeNull();
    const option = element.shadowRoot.querySelector(
      '[data-vector-id="vector-1"]'
    );
    expect(option).not.toBeNull();
    option.click();
    await flushPromises();
    expect(saveVector).toHaveBeenCalledWith({
      sequenceId: "a01000000000001AAA",
      vectorId: "vector-1"
    });
    expect(element.shadowRoot.textContent).toContain("Vector updated");
  });

  async function selectTwoSequences() {
    getSequences.mockResolvedValue([
      { id: "source-1", sequenceName: "First", length: 8 },
      { id: "source-2", sequenceName: "Second", length: 8 }
    ]);
    getSequence.mockImplementation(({ sequenceId }) =>
      Promise.resolve({
        id: sequenceId,
        sequenceName: sequenceId,
        sequence: "ACGTACGT",
        optimizationAvailable: true,
        aminoAcidSequence: "MKT*",
        manualFeatures: [{ label: "Existing", start: 1, end: 2, strand: "1" }]
      })
    );
    const element = await mount();
    const selectAll = element.shadowRoot.querySelector(
      '[aria-label="Select all sequences"]'
    );
    selectAll.checked = true;
    selectAll.dispatchEvent(new CustomEvent("change"));
    await flushPromises();
    return element;
  }

  it("shows vector load failures inline and never opens a modal", async () => {
    getQuoteOptions.mockRejectedValueOnce(
      new Error("Vector library unavailable")
    );
    const element = await openDetail({ vectorName: "Current vector" });
    clickButton(element, "Edit vector");
    await flushPromises();
    expect(element.shadowRoot.querySelector('[role="dialog"]')).toBeNull();
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("Vector library unavailable");
    expect(element.shadowRoot.querySelectorAll('[role="option"]')).toHaveLength(
      0
    );
    element.shadowRoot
      .querySelector(".vector-select")
      .dispatchEvent(
        new KeyboardEvent("keydown", { key: "Escape", bubbles: true })
      );
    await flushPromises();
    expect(element.shadowRoot.querySelector('[role="listbox"]')).toBeNull();
  });

  it("keeps the current vector when the server rejects a dropdown selection", async () => {
    getQuoteOptions.mockResolvedValueOnce({
      quotes: [],
      vectors: [{ label: "Next vector", value: "next-vector" }]
    });
    saveVector.mockRejectedValueOnce(
      new Error("Ordered sequences cannot be changed.")
    );
    const element = await openDetail({
      vectorId: "old-vector",
      vectorName: "Current vector"
    });
    clickButton(element, "Edit vector");
    await flushPromises();
    element.shadowRoot.querySelector('[data-vector-id="next-vector"]').click();
    await flushPromises();
    expect(
      element.shadowRoot.querySelector(".vector-select").textContent
    ).toContain("Current vector");
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("Ordered sequences cannot be changed");
  });

  it("removes manual and automatic chips through their respective account-scoped actions", async () => {
    const manual = { label: "GFP", start: 1, end: 4, strand: "1" };
    const automatic = { label: "Promoter", start: 5, end: 8, strand: "-1" };
    const element = await openDetail({
      manualFeatures: [manual],
      plannotateFeatures: [automatic]
    });
    element.shadowRoot.querySelector('[aria-label="Remove GFP"]').click();
    await flushPromises();
    expect(removeManualFeature).toHaveBeenCalledWith({
      sequenceId: "a01000000000001AAA",
      featureIndex: 0,
      featureJson: JSON.stringify(manual)
    });
    element.shadowRoot.querySelector('[aria-label="Remove Promoter"]').click();
    await flushPromises();
    expect(removePlannotateFeature).toHaveBeenCalledWith({
      sequenceId: "a01000000000001AAA",
      featureIndex: 0,
      featureJson: JSON.stringify(automatic)
    });
  });

  it("highlights selected rows and opens optimization for every selected original", async () => {
    const element = await selectTwoSequences();
    const toolbar = element.shadowRoot.querySelector(
      '[aria-label="Selected sequences"]'
    );
    expect(toolbar.textContent).toContain("Add Annotation");
    expect(toolbar.textContent).toContain("Run Feasibility");
    expect(
      element.shadowRoot.querySelectorAll('tbody tr[aria-selected="true"]')
    ).toHaveLength(2);
    clickButton(element, "Optimize");
    await flushPromises();
    const optimizer = element.shadowRoot.querySelector("c-codon-optimizer");
    expect(optimizer.sequenceTargets.map((target) => target.id)).toEqual([
      "source-1",
      "source-2"
    ]);
    expect(element.shadowRoot.querySelector("table")).not.toBeNull();
  });

  it("requests feasibility for every selected sequence", async () => {
    const element = await selectTwoSequences();
    clickButton(element, "Run Feasibility");
    await flushPromises();
    expect(requestFeasibility).toHaveBeenCalledWith({ sequenceId: "source-1" });
    expect(requestFeasibility).toHaveBeenCalledWith({ sequenceId: "source-2" });
    expect(element.shadowRoot.textContent).toContain("2 sequences");
  });
});
