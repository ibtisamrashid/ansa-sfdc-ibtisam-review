import { LightningElement, api } from "lwc";
import { loadScript } from "lightning/platformResourceLoader";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import genbankWriter from "@salesforce/resourceUrl/feasibilityExplainedGenbank";
import {
  buildExplanationView,
  firstHighlightStart,
  highlightStarts
} from "c/abtFeasibilityExplainedUtils";

export default class AbtSequenceFeasibilityEditor extends LightningElement {
  _sequenceText = "";
  _originalSequence;
  _chipCycleRank = null;
  _chipCycleIndex = 0;

  @api feasibilityJson = "";
  @api explained1 = "";
  @api explained2 = "";
  @api explained3 = "";
  @api readOnly = false;
  @api hasError = false;
  @api placeholder = "";
  @api sequenceName = "";

  @api
  get sequenceText() {
    return this._sequenceText;
  }

  set sequenceText(value) {
    const next = value == null ? "" : String(value);
    if (next === this._sequenceText) {
      return;
    }
    this._sequenceText = next;
    this._writeTextarea(next);
  }

  @api
  get originalSequence() {
    return this._originalSequence == null
      ? this._sequenceText
      : this._originalSequence;
  }

  set originalSequence(value) {
    this._originalSequence = value == null ? "" : String(value);
  }

  get boxClass() {
    return this.hasError
      ? "feasibility-box feasibility-box--error"
      : "feasibility-box";
  }

  get explanation() {
    return buildExplanationView(this.originalSequence, this._sequenceText, {
      json: this.feasibilityJson,
      rank1: this.explained1,
      rank2: this.explained2,
      rank3: this.explained3
    });
  }

  get segments() {
    return this.explanation.segments;
  }

  get chips() {
    return this.explanation.chips.map((chip) => {
      const clickable = firstHighlightStart(chip) != null;
      return {
        ...chip,
        disabled: !clickable,
        className: clickable
          ? `${chip.className} feasibility-chip--clickable`
          : chip.className
      };
    });
  }

  get showChips() {
    return this.chips.length > 0;
  }

  get showDownload() {
    return !!this._sequenceText;
  }

  get footerClass() {
    return this.showChips
      ? "feasibility-footer"
      : "feasibility-footer feasibility-footer--no-chips";
  }

  renderedCallback() {
    const textarea = this.template.querySelector("textarea");
    if (
      textarea &&
      textarea !== this.template.activeElement &&
      textarea.value !== this._sequenceText
    ) {
      textarea.value = this._sequenceText;
    }
  }

  handleInput(event) {
    if (this.readOnly) {
      return;
    }
    this._sequenceText = event.target.value;
    this.dispatchEvent(
      new CustomEvent("textchange", {
        detail: { value: this._sequenceText }
      })
    );
  }

  handleScroll(event) {
    this._syncBackdrop(event.target);
  }

  handleChipClick(event) {
    const rank = Number(event.currentTarget.dataset.rank);
    const chip = this.chips.find((item) => item.rank === rank);
    const starts = highlightStarts(chip);
    if (!starts.length) {
      return;
    }
    if (this._chipCycleRank === rank) {
      this._chipCycleIndex = (this._chipCycleIndex + 1) % starts.length;
    } else {
      this._chipCycleRank = rank;
      this._chipCycleIndex = 0;
    }
    this._scrollToBasePair(starts[this._chipCycleIndex]);
  }

  _scrollToBasePair(startBp) {
    const textarea = this.template.querySelector("textarea");
    if (!textarea) {
      return;
    }
    const target = this.template.querySelector(`[data-start-bp="${startBp}"]`);
    if (target && typeof target.getBoundingClientRect === "function") {
      const delta =
        target.getBoundingClientRect().top -
        textarea.getBoundingClientRect().top;
      textarea.scrollTop = Math.max(
        0,
        textarea.scrollTop + delta - textarea.clientHeight * 0.3
      );
    }
    this._syncBackdrop(textarea);
  }

  _syncBackdrop(textarea) {
    const backdrop = this.template.querySelector(".feasibility-backdrop");
    if (backdrop && textarea) {
      backdrop.scrollTop = textarea.scrollTop;
      backdrop.scrollLeft = textarea.scrollLeft;
    }
  }

  async handleDownload() {
    const text = this._sequenceText || "";
    if (!text) {
      return;
    }
    try {
      if (!this._genbankLoadPromise) {
        this._genbankLoadPromise = loadScript(this, genbankWriter);
      }
      await this._genbankLoadPromise;
      const buildGenbank = window.feasibilityExplainedGenbank?.buildGenbank;
      if (typeof buildGenbank !== "function") {
        throw new Error("GenBank writer is unavailable");
      }
      const normalizedText = text.replace(/\s+/g, "").toUpperCase();
      const normalizedOriginal = this.originalSequence
        .replace(/\s+/g, "")
        .toUpperCase();
      const annotations =
        normalizedText === normalizedOriginal && this.feasibilityJson
          ? this.feasibilityJson
          : { classification_contributions: [] };
      const genbank = buildGenbank(annotations, text, {
        sequenceId: this.sequenceName || "sequence"
      });
      const safeName =
        (this.sequenceName || "sequence").replace(/[^\w.-]+/g, "_") ||
        "sequence";
      const blob = new Blob([genbank], { type: "text/plain;charset=utf-8" });
      const url = URL.createObjectURL(blob);
      try {
        const anchor = document.createElement("a");
        anchor.href = url;
        anchor.download = `${safeName}.gb`;
        anchor.click();
      } finally {
        URL.revokeObjectURL(url);
      }
    } catch (error) {
      this._genbankLoadPromise = null;
      this.dispatchEvent(
        new ShowToastEvent({
          title: "GenBank download failed",
          message: error.message || "Please try again.",
          variant: "error"
        })
      );
    }
  }

  _writeTextarea(value) {
    const textarea = this.template?.querySelector("textarea");
    if (textarea && textarea !== this.template.activeElement) {
      textarea.value = value;
    }
  }
}
