import { createElement } from "lwc";
import AbtSequenceFeasibilityEditor from "c/abtSequenceFeasibilityEditor";
import { loadScript } from "lightning/platformResourceLoader";

jest.mock("lightning/platformResourceLoader", () => ({
  loadScript: jest.fn(() => Promise.resolve())
}));

const SAMPLE = {
  rank1: "Inverted repeat sequence from 2,649 to 2,702.",
  rank2: "Tandem repeat sequence from 1,262 to 1,403 and 400 to 460.",
  rank3:
    'Large number of tandem repeat sequences: "GCAG" from 431 to 443, "CGGAGG" from 239 to 282.'
};

describe("c-abt-sequence-feasibility-editor", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  afterEach(() => {
    delete window.feasibilityExplainedGenbank;
    delete URL.createObjectURL;
    delete URL.revokeObjectURL;
    jest.restoreAllMocks();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("downloads a generated GenBank record with a .gb filename", async () => {
    const genbank = "LOCUS       TEST\nORIGIN\n        1 atgc\n//\n";
    const buildGenbank = jest.fn(() => genbank);
    window.feasibilityExplainedGenbank = { buildGenbank };
    URL.createObjectURL = jest.fn(() => "blob:genbank-test");
    URL.revokeObjectURL = jest.fn();
    const click = jest
      .spyOn(HTMLAnchorElement.prototype, "click")
      .mockImplementation(function () {
        expect(this.download).toBe("Example_Sequence.gb");
      });
    const element = createElement("c-abt-sequence-feasibility-editor", {
      is: AbtSequenceFeasibilityEditor
    });
    element.sequenceText = "ATGC";
    element.originalSequence = "ATGC";
    element.sequenceName = "Example Sequence";
    element.feasibilityJson = '{"classification_contributions":[]}';
    document.body.appendChild(element);

    await Promise.resolve();
    const button = element.shadowRoot.querySelector(".feasibility-download");
    expect(button.textContent).toContain("DOWNLOAD GENBANK");
    button.click();
    await Promise.resolve();
    await Promise.resolve();

    expect(loadScript).toHaveBeenCalledTimes(1);
    expect(buildGenbank).toHaveBeenCalledWith(
      element.feasibilityJson,
      "ATGC",
      expect.objectContaining({ sequenceId: "Example Sequence" })
    );
    expect(URL.createObjectURL).toHaveBeenCalledWith(
      expect.objectContaining({ type: "text/plain;charset=utf-8" })
    );
    expect(click).toHaveBeenCalledTimes(1);
    expect(URL.revokeObjectURL).toHaveBeenCalledWith("blob:genbank-test");
  });

  it("does not export stale annotations after the sequence changes", async () => {
    const buildGenbank = jest.fn(() => "LOCUS       TEST\nORIGIN\n//\n");
    window.feasibilityExplainedGenbank = { buildGenbank };
    URL.createObjectURL = jest.fn(() => "blob:genbank-test");
    URL.revokeObjectURL = jest.fn();
    jest
      .spyOn(HTMLAnchorElement.prototype, "click")
      .mockImplementation(() => {});
    const element = createElement("c-abt-sequence-feasibility-editor", {
      is: AbtSequenceFeasibilityEditor
    });
    element.sequenceText = "ATGT";
    element.originalSequence = "ATGC";
    element.feasibilityJson =
      '{"classification_contributions":[{"start":0,"end":4}]}';
    document.body.appendChild(element);

    await Promise.resolve();
    element.shadowRoot.querySelector(".feasibility-download").click();
    await Promise.resolve();
    await Promise.resolve();

    expect(buildGenbank).toHaveBeenCalledWith(
      { classification_contributions: [] },
      "ATGT",
      { sequenceId: "sequence" }
    );
  });

  it("reports a generation failure without downloading a file", async () => {
    window.feasibilityExplainedGenbank = {
      buildGenbank: jest.fn(() => {
        throw new Error("Invalid GenBank input");
      })
    };
    URL.createObjectURL = jest.fn();
    const element = createElement("c-abt-sequence-feasibility-editor", {
      is: AbtSequenceFeasibilityEditor
    });
    element.sequenceText = "ATGC";
    const toast = jest.fn();
    element.addEventListener("lightning__showtoast", toast);
    document.body.appendChild(element);

    await Promise.resolve();
    element.shadowRoot.querySelector(".feasibility-download").click();
    await Promise.resolve();
    await Promise.resolve();

    expect(URL.createObjectURL).not.toHaveBeenCalled();
    expect(toast).toHaveBeenCalledTimes(1);
    expect(toast.mock.calls[0][0].detail).toMatchObject({
      message: "Invalid GenBank input",
      variant: "error"
    });
  });

  it("renders rank 1, 2, and 3 to the left of the color chips", () => {
    const element = createElement("c-abt-sequence-feasibility-editor", {
      is: AbtSequenceFeasibilityEditor
    });
    const sequence = "A".repeat(2800);
    element.sequenceText = sequence;
    element.originalSequence = sequence;
    element.explained1 = SAMPLE.rank1;
    element.explained2 = SAMPLE.rank2;
    element.explained3 = SAMPLE.rank3;
    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      const ranks = Array.from(
        element.shadowRoot.querySelectorAll(".feasibility-chip-rank")
      ).map((node) => node.textContent.trim());
      expect(ranks).toEqual(["1.", "2.", "3."]);
      const chips = element.shadowRoot.querySelectorAll(".feasibility-chip");
      expect(chips).toHaveLength(3);
      expect(chips[0].getAttribute("aria-label")).toBe(`1. ${SAMPLE.rank1}`);
    });
  });

  it("capitalizes the first letter of each explanation row", () => {
    const element = createElement("c-abt-sequence-feasibility-editor", {
      is: AbtSequenceFeasibilityEditor
    });
    const sequence = "N".repeat(7500);
    element.sequenceText = sequence;
    element.originalSequence = sequence;
    element.explained1 =
      "recognition site for homing endonuclease used by Ansa at bp 2500-2527";
    element.explained2 = "inverted repeat sequence at bp 34-7500";
    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      const labels = Array.from(
        element.shadowRoot.querySelectorAll(".feasibility-chip-text")
      ).map((node) => node.textContent.trim());
      expect(labels).toEqual([
        "Recognition site for homing endonuclease used by Ansa at bp 2500-2527",
        "Inverted repeat sequence at bp 34-7500"
      ]);
    });
  });

  it("scrolls the sequence to the highlighted region when a chip is clicked", () => {
    const element = createElement("c-abt-sequence-feasibility-editor", {
      is: AbtSequenceFeasibilityEditor
    });
    const sequence = "A".repeat(2800);
    element.sequenceText = sequence;
    element.originalSequence = sequence;
    element.explained1 = SAMPLE.rank1;
    element.explained2 = SAMPLE.rank2;
    element.explained3 = SAMPLE.rank3;
    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      const textarea = element.shadowRoot.querySelector("textarea");
      Object.defineProperty(textarea, "clientHeight", {
        configurable: true,
        value: 220
      });
      textarea.scrollTop = 0;
      textarea.getBoundingClientRect = () => ({
        top: 0,
        bottom: 220,
        height: 220
      });

      const target = element.shadowRoot.querySelector('[data-start-bp="2649"]');
      expect(target).not.toBeNull();
      target.getBoundingClientRect = () => ({
        top: 900,
        bottom: 920,
        height: 20
      });

      const chip = element.shadowRoot.querySelector(
        "button.feasibility-chip--rank-1"
      );
      expect(chip.classList.contains("feasibility-chip--clickable")).toBe(true);
      chip.click();

      expect(textarea.scrollTop).toBe(834);
    });
  });

  it("cycles through multiple red ranges when the same chip is clicked again", () => {
    const element = createElement("c-abt-sequence-feasibility-editor", {
      is: AbtSequenceFeasibilityEditor
    });
    const sequence = "A".repeat(2800);
    element.sequenceText = sequence;
    element.originalSequence = sequence;
    element.explained1 = SAMPLE.rank1;
    element.explained2 = SAMPLE.rank2;
    element.explained3 = SAMPLE.rank3;
    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      const textarea = element.shadowRoot.querySelector("textarea");
      Object.defineProperty(textarea, "clientHeight", {
        configurable: true,
        value: 220
      });
      textarea.getBoundingClientRect = () => ({
        top: 0,
        bottom: 220,
        height: 220
      });

      const firstRed = element.shadowRoot.querySelector(
        '[data-start-bp="400"]'
      );
      const secondRed = element.shadowRoot.querySelector(
        '[data-start-bp="1262"]'
      );
      firstRed.getBoundingClientRect = () => ({
        top: 100,
        bottom: 120,
        height: 20
      });
      secondRed.getBoundingClientRect = () => ({
        top: 500,
        bottom: 520,
        height: 20
      });

      const chip = element.shadowRoot.querySelector(
        "button.feasibility-chip--rank-2"
      );
      textarea.scrollTop = 0;
      chip.click();
      expect(textarea.scrollTop).toBe(34);
      chip.click();
      expect(textarea.scrollTop).toBe(468);
    });
  });
});
