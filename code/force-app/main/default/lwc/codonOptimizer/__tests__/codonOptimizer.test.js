import { createElement } from "lwc";
import CodonOptimizer from "c/codonOptimizer";
import getOrganisms from "@salesforce/apex/CodonController.getOrganisms";
import submitJob from "@salesforce/apex/CodonController.submitJob";
import submitSequenceJob from "@salesforce/apex/CodonController.submitSequenceJob";
import getJobStatus from "@salesforce/apex/CodonController.getJobStatus";

jest.mock(
  "@salesforce/apex/CodonController.getOrganisms",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CodonController.submitJob",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CodonController.submitSequenceJob",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CodonController.getJobStatus",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flushPromises = async () => {
  await Promise.resolve();
  await Promise.resolve();
};

async function createOptimizer(selectOrganism = true) {
  getOrganisms.mockResolvedValue({
    groups: [
      {
        label: "Bacteria",
        organisms: [
          {
            slug: "ecoli",
            name: "E. coli",
            models: ["trias", "codontransformer"],
            default_model: "codontransformer"
          }
        ]
      }
    ]
  });
  submitJob.mockResolvedValue({ jobId: "job-1", status: "queued" });
  getJobStatus.mockResolvedValue({ status: "done", results: [], warnings: [] });

  const element = createElement("c-codon-optimizer", { is: CodonOptimizer });
  document.body.appendChild(element);
  await flushPromises();
  if (selectOrganism) {
    const organism = element.shadowRoot.querySelector("lightning-combobox");
    organism.value = "ecoli";
    organism.dispatchEvent(new CustomEvent("change"));
    await flushPromises();
  }
  return element;
}

async function paste(element, text) {
  const field = element.shadowRoot.querySelector(
    "lightning-textarea.paste-sequence"
  );
  field.value = text;
  field.dispatchEvent(new CustomEvent("change"));
  await flushPromises();
}

describe("c-codon-optimizer pasted sequence input", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("shows both model labels before an organism is selected", async () => {
    const element = await createOptimizer(false);
    const buttons = [...element.shadowRoot.querySelectorAll(".model-button")];
    expect(buttons.map((button) => button.textContent.trim())).toEqual([
      "Trias",
      "CodonTransformer"
    ]);
    expect(buttons.every((button) => button.disabled)).toBe(true);
    expect(buttons[1].getAttribute("aria-pressed")).toBe("true");
  });

  it("keeps unavailable models visible and disabled for the selected organism", async () => {
    getOrganisms.mockResolvedValueOnce({
      groups: [
        {
          organisms: [
            {
              slug: "ecoli",
              name: "E. coli",
              models: ["codontransformer"],
              default_model: "codontransformer"
            }
          ]
        }
      ]
    });
    const element = await createOptimizer();
    const trias = element.shadowRoot.querySelector('[data-model="trias"]');
    const transformer = element.shadowRoot.querySelector(
      '[data-model="codontransformer"]'
    );
    expect(trias.disabled).toBe(true);
    expect(transformer.disabled).toBe(false);
    expect(transformer.getAttribute("aria-pressed")).toBe("true");
    trias.click();
    await flushPromises();
    expect(transformer.getAttribute("aria-pressed")).toBe("true");
  });

  it("only offers file removal while an uploaded file is attached", async () => {
    const element = await createOptimizer();
    const removeFile = () =>
      element.shadowRoot.querySelector('[aria-label="Remove uploaded file"]');
    expect(removeFile()).toBeNull();

    const input = element.shadowRoot.querySelector('input[type="file"]');
    Object.defineProperty(input, "files", {
      value: [new File([">protein\nMKT*"], "protein.fasta")]
    });
    input.dispatchEvent(new CustomEvent("change"));
    await flushPromises();
    expect(element.shadowRoot.querySelector(".file-name").textContent).toBe(
      "protein.fasta"
    );
    expect(removeFile()).not.toBeNull();

    removeFile().click();
    await flushPromises();
    expect(removeFile()).toBeNull();
    expect(element.initialFile).toBeNull();

    input.dispatchEvent(new CustomEvent("change"));
    await flushPromises();
    expect(removeFile()).not.toBeNull();
    await paste(element, "MKT*");
    expect(removeFile()).toBeNull();
  });

  it("optimizes selected sequences with their own proteins and original record IDs", async () => {
    const element = await createOptimizer();
    element.sequenceTargets = [
      {
        id: "source-1",
        name: "First",
        aminoAcidId: "protein-1",
        aminoAcidSequence: "MKT*"
      },
      {
        id: "source-2",
        name: "Second",
        aminoAcidId: "protein-2",
        aminoAcidSequence: "MGA*"
      }
    ];
    submitSequenceJob.mockImplementation(({ sequenceId }) =>
      Promise.resolve({ jobId: `job-${sequenceId}`, status: "queued" })
    );
    getJobStatus.mockImplementation(({ jobId }) =>
      Promise.resolve({
        status: "done",
        optimizedSequenceId: `copy-${jobId}`,
        results: [
          {
            recordId: "row-0",
            name: "optimized",
            dna: "ATGTAA",
            fidelity: "ok"
          }
        ]
      })
    );
    const optimized = jest.fn();
    element.addEventListener("optimized", optimized);
    await flushPromises();
    const submitButton = [
      ...element.shadowRoot.querySelectorAll("lightning-button")
    ].find((button) => button.label === "Optimize selected sequences");
    expect(submitButton).toBeDefined();
    submitButton.click();
    await flushPromises();
    await flushPromises();
    expect(submitSequenceJob).toHaveBeenCalledWith(
      expect.objectContaining({
        sequenceId: "source-1",
        aminoAcidId: "protein-1",
        sequences: ["MKT*"]
      })
    );
    expect(submitSequenceJob).toHaveBeenCalledWith(
      expect.objectContaining({
        sequenceId: "source-2",
        aminoAcidId: "protein-2",
        sequences: ["MGA*"]
      })
    );
    expect(submitJob).not.toHaveBeenCalled();
    expect(optimized).toHaveBeenCalledTimes(1);
    expect(optimized.mock.calls[0][0].detail.optimizedSequenceIds).toEqual([
      "copy-job-source-1",
      "copy-job-source-2"
    ]);
  });

  it("normalizes whitespace and submits a pasted amino acid sequence", async () => {
    const element = await createOptimizer();
    await paste(element, " MKT\nAY* ");

    await element.optimize();
    await flushPromises();

    expect(submitJob).toHaveBeenCalledWith(
      expect.objectContaining({ names: ["Sequence_1"], sequences: ["MKTAY*"] })
    );
    expect(getJobStatus).toHaveBeenCalledWith({ jobId: "job-1" });
  });

  it("requires a protein for every selected sequence before submitting any job", async () => {
    const element = await createOptimizer();
    element.sequenceTargets = [
      { id: "source-1", name: "First", aminoAcidSequence: "MKT*" },
      { id: "source-2", name: "Second" }
    ];
    await element.optimize();
    await flushPromises();
    expect(submitSequenceJob).not.toHaveBeenCalled();
    expect(
      element.shadowRoot.querySelector(".codon-error").textContent
    ).toContain("Second");
  });

  it("reports partial bulk failures without mixing original sequence IDs", async () => {
    const element = await createOptimizer();
    element.sequenceTargets = [
      { id: "source-1", name: "First", aminoAcidSequence: "MKT*" },
      { id: "source-2", name: "Second", aminoAcidSequence: "MGA*" }
    ];
    submitSequenceJob.mockImplementation(({ sequenceId }) => {
      return sequenceId === "source-2"
        ? Promise.reject(new Error("Service unavailable"))
        : Promise.resolve({ jobId: "good-job", status: "queued" });
    });
    getJobStatus.mockResolvedValue({
      status: "done",
      optimizedSequenceId: "copy-1",
      results: [{ recordId: "row-0", dna: "ATGTAA", fidelity: "ok" }]
    });
    const optimized = jest.fn();
    element.addEventListener("optimized", optimized);
    await element.optimize();
    await flushPromises();
    const result = optimized.mock.calls[0][0].detail;
    expect(result.optimizedSequenceIds).toEqual(["copy-1"]);
    expect(result.successes[0].originalSequenceId).toBe("source-1");
    expect(result.failures).toEqual([
      { sequenceId: "source-2", name: "Second", error: "Service unavailable" }
    ]);
    expect(element.isBusy).toBe(false);
  });

  it("combines DNA, missing-start, and missing-stop warnings before submission", async () => {
    const element = await createOptimizer();
    await paste(element, ">dna\nACGT\n>protein\nAST");

    await element.optimize();

    const warning = element.shadowRoot.querySelector(".codon-warning p");
    expect(warning.textContent).toContain("look like DNA");
    expect(warning.textContent).toContain("do not start with M");
    expect(warning.textContent).toContain("do not end with a stop symbol");
    expect(submitJob).not.toHaveBeenCalled();
  });

  it("rejects unsupported amino acid characters", async () => {
    const element = await createOptimizer();
    await paste(element, "MKTX?");

    await element.optimize();

    expect(
      element.shadowRoot.querySelector('[role="alert"].codon-error').textContent
    ).toContain("unsupported amino acid characters");
    expect(submitJob).not.toHaveBeenCalled();
  });

  it("enforces the 96-record upload limit for pasted FASTA", async () => {
    const element = await createOptimizer();
    const fasta = Array.from(
      { length: 97 },
      (_, index) => `>seq${index + 1}\nM*`
    ).join("\n");
    await paste(element, fasta);

    await element.optimize();

    expect(
      element.shadowRoot.querySelector('[role="alert"].codon-error').textContent
    ).toContain("Maximum 96 sequences per upload");
    expect(submitJob).not.toHaveBeenCalled();
  });

  it("enforces the optimizer's 2,045 amino acid limit", async () => {
    const element = await createOptimizer();
    await paste(element, `M${"A".repeat(2045)}*`);

    await element.optimize();

    expect(
      element.shadowRoot.querySelector('[role="alert"].codon-error').textContent
    ).toContain("exceeds the optimizer limit of 2,045");
    expect(submitJob).not.toHaveBeenCalled();
  });
});
