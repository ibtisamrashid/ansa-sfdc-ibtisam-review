import { createElement } from "lwc";
import SequenceVisualizer from "c/sequenceVisualizer";
describe("sequence maps", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
  });
  it("shows actual DNA composition and positioned features in both map views", async () => {
    const element = createElement("c-sequence-visualizer", {
      is: SequenceVisualizer
    });
    element.sequence = "ACGTNN";
    element.features = [
      { label: "Feature", start: 1, end: 4, strand: "-1", source: "manual" }
    ];
    document.body.appendChild(element);
    await Promise.resolve();
    expect(element.shadowRoot.textContent).toContain("6 bp");
    expect(element.shadowRoot.textContent).toContain("GC 50.0%");
    expect(element.shadowRoot.textContent).toContain("2 unknown bases");
    expect(element.shadowRoot.querySelector("div.feature").title).toContain(
      "1-4 (reverse)"
    );
    element.shadowRoot
      .querySelector("lightning-combobox")
      .dispatchEvent(
        new CustomEvent("change", { detail: { value: "circular" } })
      );
    await Promise.resolve();
    expect(
      element.shadowRoot.querySelector("svg path").getAttribute("d")
    ).toContain(" A ");
  });
});
