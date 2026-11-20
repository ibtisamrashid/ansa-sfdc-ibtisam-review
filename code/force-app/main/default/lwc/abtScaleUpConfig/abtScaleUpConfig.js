import { LightningElement, api, track } from "lwc";
import {
  getScaleUpMass,
  getScaleUpNormalizationOptions,
  SCALE_UP_DEFAULT_BUFFER,
  SCALE_UP_DEFAULT_NORMALIZATION,
  SCALE_UP_QUANTITY_OPTIONS,
  SCALE_UP_EARLY_ACCESS_MESSAGE,
  toScaleUpNormalizationApiValue
} from "c/abtScaleUpUtils";

const PLACEHOLDER = "—";

export default class AbtScaleUpConfig extends LightningElement {
  @api disabled = false;
  @api isOpen = false;
  @api showIcon = false;
  /** Drives the icon colour: green when configured, red when prep quantity still needs saving. */
  @api configured = false;
  @api saving = false;

  /** Vector copy number used for mass / normalization previews. */
  @api copyNumber = "";

  /** Total selected rows in the quote table (includes this row). */
  @api totalSelectedCount = 0;
  /** Total rows on the quote. */
  @api totalLineCount = 0;

  @api quantityOptions = [];
  @api bufferOptions = [];
  /** Scale_Up_Normalization__c picklist options from Salesforce (labels/values). */
  @api normalizationOptions = [];
  /** Picklist default from Salesforce (falls back to Lo-TE Buffer). */
  @api defaultBuffer = SCALE_UP_DEFAULT_BUFFER;

  // Current (saved) values passed down from the parent row.
  @api quantity = "";
  @api glycerolStock = false;
  @api endotoxinFree = false;
  @api buffer = "";
  @api normalization = "";
  // Display-only, derived server-side values.
  @api mass = "";
  @api price = "";
  @api leadTime = "";

  @track _draft = {};
  @track _quantityError = false;
  /** Last mass from Salesforce or from Apply in this session (not live draft preview). */
  @track _appliedMass = "";
  _wasOpen = false;
  _wasConfigured = false;

  renderedCallback() {
    if (this._wasOpen !== this.isOpen) {
      if (this.isOpen) {
        this._resetDraft();
        this._syncAppliedMassFromApi();
      }
      this._wasOpen = this.isOpen;
    }
    // Prefer the latest Salesforce / parent value whenever it arrives after Apply.
    if (this.mass && this.mass !== this._appliedMass) {
      this._appliedMass = this.mass;
    }
    if (this._wasConfigured && this.configured !== true) {
      this._appliedMass = "";
      // Scale Up was cleared on the row — drop stale draft glycerol / qty so reopen starts clean.
      this._resetDraft();
    }
    this._wasConfigured = this.configured === true;
  }

  _syncAppliedMassFromApi() {
    if (this.mass) {
      this._appliedMass = this.mass;
      return;
    }
    // Already applied (saved quantity) but mass not on the wire yet — show matrix for saved qty.
    if (this.configured && this.quantity) {
      const fromSaved = getScaleUpMass(this.copyNumber, this.quantity);
      if (fromSaved) {
        this._appliedMass = fromSaved;
      }
    }
  }

  _resetDraft() {
    const savedNorm = this.normalization || "";
    this._draft = {
      quantity: this.quantity || "1",
      glycerolStock: this.glycerolStock === true,
      endotoxinFree: this.endotoxinFree === true,
      buffer: this.buffer || this.defaultBuffer || SCALE_UP_DEFAULT_BUFFER,
      normalization: savedNorm || SCALE_UP_DEFAULT_NORMALIZATION,
      applyToSelected: false
    };
    this._quantityError = false;
  }

  get containerClass() {
    const base = "scaleup-config";
    return this.showIcon ? base : `${base} scaleup-config--placeholder`;
  }

  get iconClass() {
    return `scaleup-icon-btn${this.configured ? " scaleup-icon-btn--active" : ""}`;
  }

  get iconStyle() {
    return `--scaleup-icon-color: ${this.configured ? "#34bba6" : "#EE5C42"}`;
  }

  get earlyAccessMessage() {
    return SCALE_UP_EARLY_ACCESS_MESSAGE;
  }

  get copyNumberDisplay() {
    const copy = String(this.copyNumber || "").trim();
    return copy || PLACEHOLDER;
  }

  get quantitySelectOptions() {
    return this.quantityOptions && this.quantityOptions.length
      ? this.quantityOptions
      : SCALE_UP_QUANTITY_OPTIONS;
  }

  get bufferSelectOptions() {
    return this.bufferOptions || [];
  }

  get normalizationSelectOptions() {
    return getScaleUpNormalizationOptions(
      this.copyNumber,
      this.normalizationOptions
    );
  }

  get draftQuantity() {
    return this._draft.quantity || "";
  }

  get draftBuffer() {
    return this._draft.buffer || this.defaultBuffer || SCALE_UP_DEFAULT_BUFFER;
  }

  get draftNormalization() {
    return this._draft.normalization || "";
  }

  get draftEndotoxinFree() {
    return this._draft.endotoxinFree === true;
  }

  get draftGlycerol() {
    return this._draft.glycerolStock === true;
  }

  get draftApplyToSelected() {
    return this._draft.applyToSelected === true;
  }

  /**
   * Expected Yield: Salesforce value, or last Apply result.
   * Does not live-update while Prep Quantity draft changes.
   */
  get massDisplay() {
    return this.mass || this._appliedMass || PLACEHOLDER;
  }

  get priceDisplay() {
    return this.price || PLACEHOLDER;
  }

  get leadTimeDisplay() {
    return this.leadTime || PLACEHOLDER;
  }

  get quantityFieldClass() {
    return "scaleup-select-field";
  }

  get showQuantityError() {
    return this._quantityError === true;
  }

  get isActionsDisabled() {
    return this.disabled === true || this.saving === true;
  }

  get showApplyCheckbox() {
    // Show when the quote has more than one line (apply-to-all / apply-to-selected).
    return Number(this.totalLineCount) > 1;
  }

  get applyCheckboxLabel() {
    return Number(this.totalSelectedCount) > 1
      ? "Apply to selected lines"
      : "Apply to all quote lines?";
  }

  stopProp(event) {
    event.stopPropagation();
  }

  handleIconClick(event) {
    event.stopPropagation();
    if (this.disabled || !this.showIcon) {
      return;
    }
    this.dispatchEvent(
      new CustomEvent("toggle", { bubbles: true, composed: true })
    );
  }

  handleQuantityChange(event) {
    const value = event.detail?.value ?? event.target?.value ?? "";
    this._draft = { ...this._draft, quantity: value };
    if (value) {
      this._quantityError = false;
    }
  }

  handleBufferChange(event) {
    const value = event.detail?.value ?? event.target?.value ?? "";
    this._draft = { ...this._draft, buffer: value };
  }

  handleNormalizationChange(event) {
    const value = event.detail?.value ?? event.target?.value ?? "";
    this._draft = { ...this._draft, normalization: value };
  }

  handleEndotoxinFreeChange(event) {
    this._draft = { ...this._draft, endotoxinFree: event.target.checked };
  }

  handleGlycerolChange(event) {
    this._draft = { ...this._draft, glycerolStock: event.target.checked };
  }

  handleApplyToSelectedChange(event) {
    this._draft = { ...this._draft, applyToSelected: event.target.checked };
  }

  handleDefinitionsClick(event) {
    event.stopPropagation();
    this.dispatchEvent(
      new CustomEvent("definitionstoggle", {
        detail: { open: true },
        bubbles: true,
        composed: true
      })
    );
  }

  handleCancel(event) {
    event.stopPropagation();
    this.dispatchEvent(
      new CustomEvent("cancel", { bubbles: true, composed: true })
    );
  }

  handleApply(event) {
    event.stopPropagation();
    if (this.disabled || this.saving) {
      return;
    }
    if (!this._draft.quantity) {
      this._quantityError = true;
      return;
    }
    // Lock in mass for this Apply (shown until Salesforce returns / next Apply).
    const appliedMass = getScaleUpMass(this.copyNumber, this._draft.quantity);
    if (appliedMass) {
      this._appliedMass = appliedMass;
    }
    this.dispatchEvent(
      new CustomEvent("save", {
        detail: {
          quantity: this._draft.quantity,
          glycerolStock: this._draft.glycerolStock === true,
          buffer:
            this._draft.buffer || this.defaultBuffer || SCALE_UP_DEFAULT_BUFFER,
          normalization: toScaleUpNormalizationApiValue(
            this._draft.normalization
          ),
          endotoxinFree: this._draft.endotoxinFree === true,
          // Portal no longer collects animal-free; kept false for Apex payload compatibility.
          animalFree: false,
          applyToSelected: this._draft.applyToSelected === true
        },
        bubbles: true,
        composed: true
      })
    );
  }
}
