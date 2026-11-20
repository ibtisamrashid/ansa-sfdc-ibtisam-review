import saveVector from "@salesforce/apex/SequenceHubActions.saveVector";
import { LightningElement, track, wire } from "lwc";
import { NavigationMixin, CurrentPageReference } from "lightning/navigation";
import annotationConfigured from "@salesforce/apex/SequenceHubAnnotation.isConfigured";
import requestAnnotation from "@salesforce/apex/SequenceHubAnnotation.requestAnnotation";
import getQuoteOptions from "@salesforce/apex/SequenceHubActions.getQuoteOptions";
import addToQuote from "@salesforce/apex/SequenceHubActions.addToQuote";
import saveAnnotations from "@salesforce/apex/SequenceHubActions.saveAnnotations";
import appendManualAnnotations from "@salesforce/apex/SequenceHubActions.appendManualAnnotations";
import removeManualFeature from "@salesforce/apex/SequenceHubActions.removeManualFeature";
import removePlannotateFeature from "@salesforce/apex/SequenceHubActions.removePlannotateFeature";
import renameSequence from "@salesforce/apex/SequenceHubActions.renameSequence";
import requestFeasibility from "@salesforce/apex/SequenceHubActions.requestFeasibility";
import { loadScript } from "lightning/platformResourceLoader";
import SHEETJS from "@salesforce/resourceUrl/sheetJs";
import getSequences from "@salesforce/apex/SequenceHubController.getSequences";
import getSequence from "@salesforce/apex/SequenceHubController.getSequence";
import uploadSequences from "@salesforce/apex/SequenceUploadController.uploadSequences";
import { ShowToastEvent } from "lightning/platformShowToastEvent";

const PAGE_SIZE = 25;
const FEASIBILITY_VALUES = ["Pending", "Feasible", "Infeasible", "Borderline"];
const COMPLEXITY_VALUES = ["Pending", "Standard", "Complex", "Early Access"];
const MAX_UPLOAD_BYTES = 5 * 1024 * 1024;
const MAX_UPLOAD_ROWS = 100;

// Dates arrive as "YYYY-MM-DD" or ISO datetimes. Parse date-only values by
// hand so the browser time zone cannot shift them by a day.
function formatDate(value) {
  if (!value) return "";
  const text = String(value);
  const dateOnly = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
  if (dateOnly) return `${dateOnly[2]}/${dateOnly[3]}/${dateOnly[1]}`;
  const parsed = new Date(text);
  if (Number.isNaN(parsed.getTime())) return "";
  return parsed.toLocaleDateString("en-US", {
    month: "2-digit",
    day: "2-digit",
    year: "numeric"
  });
}

// Annotations / Plannotate can come back as an array or a comma string.
function toChips(value, prefix) {
  const list = Array.isArray(value)
    ? value
    : String(value || "")
        .split(",")
        .map((item) => item.trim());
  return list
    .filter(Boolean)
    .map((label, index) => ({ key: `${prefix}-${index}-${label}`, label }));
}

// ---------- upload file parsing ----------

function cleanBases(text) {
  return String(text || "")
    .replace(/\s+/g, "")
    .toUpperCase();
}

function readFile(file, asBuffer) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = () => reject(new Error(`Could not read ${file.name}.`));
    if (asBuffer) reader.readAsArrayBuffer(file);
    else reader.readAsText(file);
  });
}

function parseFasta(text) {
  const records = [];
  let current = null;
  String(text)
    .split(/\r?\n/)
    .forEach((line) => {
      if (line.startsWith(">")) {
        if (current) records.push(current);
        current = {
          name: line.slice(1).trim().split(/\s+/)[0] || "",
          sequence: ""
        };
      } else if (current) {
        current.sequence += cleanBases(line);
      }
    });
  if (current) records.push(current);
  return records;
}

function parseGenBank(text) {
  return String(text)
    .split(/^\/\/\s*$/m)
    .flatMap((block) => {
      const locus = /^LOCUS\s+(\S+)/m.exec(block);
      const origin = /^ORIGIN[^\n]*\n([\s\S]*)$/m.exec(block);
      return origin
        ? [
            {
              name: locus ? locus[1] : "",
              sequence: cleanBases(origin[1].replace(/\d+/g, ""))
            }
          ]
        : [];
    });
}

// Checks every record before anything is sent, so a bad file saves nothing.
function normalizeRecords(records, fileName) {
  const baseName = fileName.replace(/\.[^.]+$/, "") || "Sequence";
  const names = [];
  const sequences = [];
  const errors = [];
  if (!records.length) {
    errors.push("No sequences were found in the file.");
  }
  if (records.length > MAX_UPLOAD_ROWS) {
    errors.push(`Upload at most ${MAX_UPLOAD_ROWS} sequences at a time.`);
  }
  records.forEach((record, index) => {
    const name = String(record.name || "").trim() || `${baseName}_${index + 1}`;
    const sequence = cleanBases(record.sequence);
    if (!sequence) {
      errors.push(`Row ${index + 1} (${name}) has no sequence.`);
    } else if (!/^[ACGTN]+$/.test(sequence)) {
      errors.push(
        `Row ${index + 1} (${name}) must contain DNA bases only (A, C, G, T, N).`
      );
    }
    names.push(name);
    sequences.push(sequence);
  });
  return { names, sequences, errors };
}

export default class SequenceHub extends NavigationMixin(LightningElement) {
  @track rows = [];
  @track activeDialog = "";
  @track isSaving = false;
  @track quoteOptions = [];
  @track vectorOptions = [];
  @track showVectorDropdown = false;
  @track isLoadingVectors = false;
  @track vectorError = "";
  vectorRequest = 0;
  @track editableFeatures = [];
  @track optimizationTargets = [];
  @track annotationTargets = [];
  @track shareUrl = "";
  @track annotationServiceAvailable = false;
  quoteSequenceIds = [];
  selectedQuote = "";
  selectedVector = "";
  draftName = "";
  featureLabel = "";
  featureStart = "";
  featureEnd = "";
  featureStrand = "1";
  dialogError = "";
  linkedSequenceId;

  @wire(CurrentPageReference)
  readPageReference(reference) {
    if (!reference) return;
    const sequenceId = reference.state?.c__sequenceId;
    if (!sequenceId && this.linkedSequenceId) {
      this.handleBack();
      return;
    }
    if (
      sequenceId &&
      sequenceId !== this.linkedSequenceId &&
      /^[a-zA-Z0-9]{15,18}$/.test(sequenceId)
    ) {
      this.linkedSequenceId = sequenceId;
      this.openSequence(sequenceId);
    }
  }
  @track selectedSequence;
  @track errorMessage = "";
  @track isLoading = false;
  @track isUploading = false;
  @track bannerMessage = "";
  @track bannerType = "info";
  @track hasMore = false;
  @track showOptimizeInfo = false;
  @track showFilters = false;
  @track selectedIds = [];

  // Active filters (sent to Apex)
  searchTerm = "";
  appliedSearchTerm = "";
  ownerName = "";
  feasibility = "";
  complexity = "";
  createdOn = "";

  // Draft values shown in the filter popup until Apply is clicked
  draftOwner = "";
  draftFeasibility = "";
  draftComplexity = "";
  draftDate = "";

  knownOwners = [];
  offsetRows = 0;
  sheetJsLoaded = false;
  listRequest = 0;
  detailRequest = 0;

  connectedCallback() {
    this.loadSequences(false);
    annotationConfigured()
      .then((available) => {
        this.annotationServiceAvailable = available;
      })
      .catch(() => {
        this.annotationServiceAvailable = false;
      });
  }

  // ---------- list state ----------

  get isListView() {
    return !this.selectedSequence;
  }

  get hubClass() {
    return this.isListView
      ? "hub slds-p-around_large"
      : "hub hub--detail slds-p-around_large";
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get hasBanner() {
    return Boolean(this.bannerMessage);
  }

  get bannerClass() {
    const tone =
      this.bannerType === "error"
        ? "slds-alert_error"
        : this.bannerType === "success"
          ? "slds-theme_success"
          : "slds-theme_info";
    return `slds-notify slds-notify_alert ${tone} slds-m-bottom_small`;
  }

  dismissBanner() {
    this.bannerMessage = "";
  }

  get isBusy() {
    return this.isLoading || this.isUploading || this.isSaving;
  }

  get displayRows() {
    return this.rows.map((row) => {
      const status = row.status || "";
      return {
        ...row,
        selected: this.selectedIds.includes(row.id),
        rowClass: this.selectedIds.includes(row.id)
          ? "seq-row seq-row--selected"
          : "seq-row",
        displayName: row.sequenceName || row.sequenceNumber,
        createdDisplay: formatDate(row.createdDate),
        orderedDisplay: formatDate(row.orderedDate) || "—",
        annotationChips: toChips(row.annotations, "a"),
        plannotateChips: toChips(row.plannotate, "p"),
        status,
        statusClass: `pill pill--${status.toLowerCase().replace(/\s+/g, "-")}`
      };
    });
  }

  get hasSelection() {
    return this.selectedIds.length > 0;
  }

  get selectedCount() {
    return this.selectedIds.length;
  }

  get allSelected() {
    return (
      this.rows.length > 0 &&
      this.rows.every((row) => this.selectedIds.includes(row.id))
    );
  }

  get isBulkOptimizeDisabled() {
    return this.isBusy || !this.hasSelection || this.selectedIds.length > 96;
  }

  get isBulkQuoteDisabled() {
    return this.isBusy || !this.hasSelection || this.selectedIds.length > 25;
  }
  get isBulkAnnotation() {
    return this.annotationTargets.length > 0;
  }

  renderedCallback() {
    const checkbox = this.template.querySelector(
      '[aria-label="Select all sequences"]'
    );
    if (checkbox)
      checkbox.indeterminate = this.hasSelection && !this.allSelected;
  }

  get hasActiveFilters() {
    return Boolean(
      this.ownerName || this.feasibility || this.complexity || this.createdOn
    );
  }

  // ---------- filter popup options ----------

  get ownerOptions() {
    return this.choices(this.knownOwners, this.draftOwner);
  }

  get feasibilityChoices() {
    return this.choices(FEASIBILITY_VALUES, this.draftFeasibility);
  }

  get complexityChoices() {
    return this.choices(COMPLEXITY_VALUES, this.draftComplexity);
  }

  choices(values, current) {
    return [
      { label: "Select", value: "" },
      ...values.map((value) => ({ label: value, value }))
    ].map((opt) => ({ ...opt, selected: opt.value === current }));
  }

  // ---------- search + filters ----------

  handleSearchInput(event) {
    this.searchTerm = event.target.value;
  }

  handleSearchKey(event) {
    if (event.key === "Enter") this.applySearch();
  }

  applySearch() {
    this.appliedSearchTerm = this.searchTerm.trim();
    this.offsetRows = 0;
    this.loadSequences(false);
  }

  toggleFilters() {
    if (!this.showFilters) {
      this.draftOwner = this.ownerName;
      this.draftFeasibility = this.feasibility;
      this.draftComplexity = this.complexity;
      this.draftDate = this.createdOn;
    }
    this.showFilters = !this.showFilters;
  }

  handleFilterKey(event) {
    if (event.key === "Escape") this.showFilters = false;
  }

  handleDraftChange(event) {
    this[event.target.dataset.field] = event.target.value || "";
  }

  applyFilters() {
    this.ownerName = this.draftOwner;
    this.feasibility = this.draftFeasibility;
    this.complexity = this.draftComplexity;
    this.createdOn = this.draftDate;
    this.showFilters = false;
    this.applySearch();
  }

  clearFilters() {
    this.draftOwner = "";
    this.draftFeasibility = "";
    this.draftComplexity = "";
    this.draftDate = "";
    this.applyFilters();
  }

  // ---------- data ----------

  async loadSequences(append) {
    const request = ++this.listRequest;
    const requestedOffset = append ? this.offsetRows + PAGE_SIZE : 0;
    this.isLoading = true;
    this.errorMessage = "";
    try {
      const result = await getSequences({
        searchTerm: this.appliedSearchTerm,
        ownerName: this.ownerName,
        feasibility: this.feasibility,
        complexity: this.complexity,
        // The design has one Created Date field, so use it for both ends.
        createdAfter: this.createdOn || null,
        createdBefore: this.createdOn || null,
        pageSize: PAGE_SIZE,
        offsetRows: requestedOffset
      });
      if (request !== this.listRequest) return;
      this.offsetRows = requestedOffset;
      this.rows = append ? [...this.rows, ...result] : result;
      this.hasMore = result.length === PAGE_SIZE && requestedOffset < 2000;
      if (!append) this.selectedIds = [];
      const owners = new Set(this.knownOwners);
      result.forEach((row) => row.ownerName && owners.add(row.ownerName));
      this.knownOwners = [...owners].sort();
    } catch (error) {
      if (request !== this.listRequest) return;
      this.errorMessage = this.errorText(error);
      if (!append) this.rows = [];
    } finally {
      if (request === this.listRequest) this.isLoading = false;
    }
  }

  handleLoadMore() {
    if (!this.hasMore || this.isLoading) return;
    this.loadSequences(true);
  }

  // ---------- selection ----------

  stopClick(event) {
    event.stopPropagation();
  }

  handleSelectRow(event) {
    const id = event.target.dataset.id;
    this.selectedIds = event.target.checked
      ? [...new Set([...this.selectedIds, id])]
      : this.selectedIds.filter((item) => item !== id);
  }

  handleSelectAll(event) {
    this.selectedIds = event.target.checked
      ? this.rows.map((row) => row.id)
      : [];
  }

  // ---------- row + bulk actions ----------

  async handleRowClick(event) {
    await this.openSequence(event.currentTarget.dataset.id);
  }

  async handleRowKey(event) {
    if (event.target !== event.currentTarget) return;
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      await this.openSequence(event.currentTarget.dataset.id);
    }
  }

  async handleRowOptimize(event) {
    event.stopPropagation();
    if (await this.openSequence(event.currentTarget.dataset.id))
      this.openOptimizeInfo();
  }

  async selectedDetails() {
    if (!this.selectedIds.length || this.selectedIds.length > 96)
      throw new Error("Select between 1 and 96 sequences.");
    return Promise.all(
      this.selectedIds.map((sequenceId) => getSequence({ sequenceId }))
    );
  }

  async handleBulkOptimize() {
    if (this.isBulkOptimizeDisabled) return;
    this.isSaving = true;
    try {
      const sequences = await this.selectedDetails();
      const unavailable = sequences.filter(
        (sequence) => !sequence.optimizationAvailable
      );
      if (unavailable.length)
        throw new Error(
          `Optimization is unavailable for: ${unavailable.map((sequence) => sequence.sequenceName).join(", ")}. Select eligible sequences only.`
        );
      this.optimizationTargets = sequences.map((sequence) => ({
        id: sequence.id,
        name: sequence.sequenceName || sequence.sequenceNumber,
        aminoAcidId: sequence.aminoAcidId,
        aminoAcidSequence: sequence.aminoAcidSequence,
        settings: sequence.optimizationSettings
      }));
      this.showOptimizeInfo = true;
    } catch (error) {
      this.toast("Optimization not started", this.errorText(error), "error");
    } finally {
      this.isSaving = false;
    }
  }

  async handleBulkAnnotations() {
    if (this.isBulkOptimizeDisabled) return;
    this.isSaving = true;
    try {
      this.annotationTargets = await this.selectedDetails();
      this.resetAnnotationEditor([]);
    } catch (error) {
      this.toast("Annotations unavailable", this.errorText(error), "error");
    } finally {
      this.isSaving = false;
    }
  }

  async handleBulkFeasibility() {
    if (this.isBulkOptimizeDisabled) return;
    const ids = [...this.selectedIds];
    this.isSaving = true;
    const failed = [];
    for (let offset = 0; offset < ids.length; offset += 4) {
      await Promise.all(
        ids.slice(offset, offset + 4).map(async (sequenceId) => {
          try {
            await requestFeasibility({ sequenceId });
          } catch (error) {
            failed.push({ id: sequenceId, error: this.errorText(error) });
          }
        })
      );
    }
    this.isSaving = false;
    await this.loadSequences(false);
    this.selectedIds = failed.map((failure) => failure.id);
    this.toast(
      "Feasibility requested",
      `${ids.length - failed.length} sequences queued.${failed.length ? " " + failed.length + " failed: " + failed.map((failure) => failure.error).join("; ") : ""}`,
      failed.length ? "warning" : "success"
    );
  }

  async handleAddToQuote() {
    this.activeDialog = "quote";
    this.dialogError = "";
    this.quoteSequenceIds = this.selectedSequence
      ? [this.selectedSequence.id]
      : [...this.selectedIds];
    this.selectedQuote = "";
    this.selectedVector = "";
    this.isSaving = true;
    try {
      const options = await getQuoteOptions();
      this.quoteOptions = [
        { label: "Choose an open quote", value: "" },
        ...options.quotes
      ];
      this.vectorOptions = [
        { label: "No vector", value: "" },
        ...options.vectors
      ];
    } catch (error) {
      this.dialogError = this.errorText(error);
    } finally {
      this.isSaving = false;
    }
  }

  get isQuoteDialog() {
    return this.activeDialog === "quote";
  }
  get isAnnotationDialog() {
    return this.activeDialog === "annotations";
  }
  get isShareDialog() {
    return this.activeDialog === "share";
  }
  get isRenameDialog() {
    return this.activeDialog === "rename";
  }
  get isVisualizationDialog() {
    return this.activeDialog === "visualize";
  }
  get hasDialog() {
    return Boolean(this.activeDialog);
  }
  get dialogTitle() {
    if (this.isAnnotationDialog && this.annotationTargets.length)
      return `Add annotations to ${this.annotationTargets.length} sequences`;
    return (
      {
        vector: "Select vector",
        quote: "Add to quote",
        annotations: "Add manual annotation",
        share: "Share sequence",
        rename: "Rename sequence",
        visualize: "Visualize sequence"
      }[this.activeDialog] || "Sequence"
    );
  }
  get isQuoteSaveDisabled() {
    return (
      this.isSaving || !this.selectedQuote || this.quoteSequenceIds.length === 0
    );
  }
  get noOpenQuotes() {
    return this.quoteOptions.length <= 1 && !this.isSaving;
  }
  get manualFeatures() {
    return (this.selectedSequence?.manualFeatures || []).map(
      (feature, index) => ({
        ...feature,
        key: String(index),
        tooltip: `${feature.label}: ${feature.start}-${feature.end}`,
        removeLabel: `Remove ${feature.label}`
      })
    );
  }
  get automaticFeatures() {
    return (this.selectedSequence?.plannotateFeatures || []).map(
      (feature, index) => ({
        ...feature,
        key: String(index),
        tooltip: `${feature.label}: ${feature.start}-${feature.end}`,
        removeLabel: `Remove ${feature.label}`
      })
    );
  }
  get hasManualFeatures() {
    return this.manualFeatures.length > 0;
  }
  get hasAutomaticFeatures() {
    return this.automaticFeatures.length > 0;
  }
  get featureRows() {
    return this.editableFeatures.map((feature, index) => ({
      ...feature,
      key: String(index)
    }));
  }
  openVisualization() {
    this.activeDialog = "visualize";
    this.dialogError = "";
  }
  get visualizationFeatures() {
    return [
      ...this.manualFeatures.map((f) => ({ ...f, source: "manual" })),
      ...this.automaticFeatures.map((f) => ({ ...f, source: "plannotate" }))
    ];
  }
  get detailVector() {
    return this.selectedSequence?.vectorName || "Not selected";
  }
  get proteinNeeded() {
    return this.optimizationTargets.length
      ? this.optimizationTargets.some((target) => !target.aminoAcidSequence)
      : this.selectedSequence?.requiresProtein;
  }
  get optimizerSequenceId() {
    return this.optimizationTargets.length === 1
      ? this.optimizationTargets[0].id
      : this.selectedSequence?.id;
  }
  get optimizerAminoAcidId() {
    return this.optimizationTargets.length === 1
      ? this.optimizationTargets[0].aminoAcidId
      : this.selectedSequence?.aminoAcidId;
  }
  get optimizerProtein() {
    return this.optimizationTargets.length === 1
      ? this.optimizationTargets[0].aminoAcidSequence
      : this.selectedSequence?.aminoAcidSequence;
  }
  get optimizerSettings() {
    return this.optimizationTargets.length
      ? this.optimizationTargets[0].settings
      : this.selectedSequence?.optimizationSettings;
  }
  get optimizerTitle() {
    return this.optimizationTargets.length > 1
      ? `Optimize ${this.optimizationTargets.length} sequences`
      : "Optimize sequence";
  }

  closeDialog() {
    if (!this.isSaving) {
      this.activeDialog = "";
      this.dialogError = "";
    }
  }
  handleDialogKey(event) {
    if (event.key === "Escape") this.closeDialog();
  }
  handleDialogInput(event) {
    this[event.target.dataset.field] =
      event.detail?.value ?? event.target.value;
  }

  async confirmAddToQuote() {
    if (this.isQuoteSaveDisabled) return;
    this.isSaving = true;
    this.dialogError = "";
    try {
      const result = await addToQuote({
        sequenceIds: this.quoteSequenceIds,
        quoteRequestId: this.selectedQuote,
        vectorId: this.selectedVector || null
      });
      this.activeDialog = "";
      this.toast(
        "Added to quote",
        result.added + " sequence(s) copied to the selected quote.",
        "success"
      );
      this.selectedIds = [];
      if (this.isListView) await this.loadSequences(false);
    } catch (error) {
      this.dialogError = this.errorText(error);
    } finally {
      this.isSaving = false;
    }
  }

  openAnnotations() {
    this.annotationTargets = [];
    this.resetAnnotationEditor([]);
  }

  get dialogClass() {
    return this.isAnnotationDialog
      ? "modal-card manual-annotation-modal"
      : "modal-card";
  }

  get annotationStrandOptions() {
    return [
      { label: "Forward", value: "1" },
      { label: "Reverse", value: "-1" }
    ];
  }

  async confirmManualAnnotation() {
    if (this.isSaving) return;
    const start = Number(this.featureStart);
    const end = Number(this.featureEnd);
    const label = this.featureLabel.trim();
    const length = this.selectedSequence?.sequence?.length || 0;
    if (
      !label ||
      label.length > 80 ||
      !Number.isInteger(start) ||
      !Number.isInteger(end) ||
      start < 1 ||
      end < start ||
      end > length ||
      !["1", "-1"].includes(this.featureStrand)
    ) {
      this.dialogError =
        "Enter a feature name (up to 80 characters), a valid strand, and start/end positions within the DNA sequence (1-based).";
      return;
    }
    this.isSaving = true;
    this.dialogError = "";
    try {
      const sequenceId = this.selectedSequence.id;
      await appendManualAnnotations({
        sequenceId,
        annotationsJson: JSON.stringify([
          { label, start, end, strand: this.featureStrand }
        ])
      });
      await this.openSequence(sequenceId);
      this.activeDialog = "";
      this.toast(
        "Annotation added",
        "The manual annotation was saved.",
        "success"
      );
    } catch (error) {
      this.dialogError = this.errorText(error);
    } finally {
      this.isSaving = false;
    }
  }

  resetAnnotationEditor(features) {
    this.editableFeatures = features;
    this.featureLabel = "";
    this.featureStart = "";
    this.featureEnd = "";
    this.featureStrand = "1";
    this.dialogError = "";
    this.activeDialog = "annotations";
  }

  addFeature() {
    const start = Number(this.featureStart),
      end = Number(this.featureEnd);
    const length = this.annotationTargets.length
      ? Math.min(
          ...this.annotationTargets.map(
            (sequence) => sequence.sequence?.length || 0
          )
        )
      : this.selectedSequence?.sequence?.length || 0;
    if (
      !this.featureLabel.trim() ||
      this.featureLabel.trim().length > 80 ||
      !Number.isInteger(start) ||
      !Number.isInteger(end) ||
      start < 1 ||
      end < start ||
      end > length ||
      this.editableFeatures.length >= 200
    ) {
      this.dialogError =
        "Enter a feature name and start/end positions within the sequence (1-based). Save at most 200 features.";
      return;
    }
    this.editableFeatures = [
      ...this.editableFeatures,
      {
        label: this.featureLabel.trim(),
        start,
        end,
        strand: this.featureStrand
      }
    ];
    this.featureLabel = "";
    this.featureStart = "";
    this.featureEnd = "";
    this.dialogError = "";
  }

  removeFeature(event) {
    this.editableFeatures = this.editableFeatures.filter(
      (feature, index) => index !== Number(event.currentTarget.dataset.index)
    );
  }

  async confirmAnnotations() {
    if (this.annotationTargets.length) {
      await this.confirmBulkAnnotations();
      return;
    }
    this.isSaving = true;
    this.dialogError = "";
    try {
      await saveAnnotations({
        sequenceId: this.selectedSequence.id,
        annotationsJson: JSON.stringify(this.editableFeatures)
      });
      await this.openSequence(this.selectedSequence.id);
      this.activeDialog = "";
      this.toast(
        "Annotations saved",
        "Manual annotations were saved for this sequence.",
        "success"
      );
    } catch (error) {
      this.dialogError = this.errorText(error);
    } finally {
      this.isSaving = false;
    }
  }

  async confirmBulkAnnotations() {
    if (!this.editableFeatures.length) {
      this.dialogError =
        "Add at least one annotation to apply to the selected sequences.";
      return;
    }
    this.isSaving = true;
    const targets = [...this.annotationTargets];
    const failed = [];
    for (let offset = 0; offset < targets.length; offset += 4) {
      await Promise.all(
        targets.slice(offset, offset + 4).map(async (sequence) => {
          try {
            await appendManualAnnotations({
              sequenceId: sequence.id,
              annotationsJson: JSON.stringify(this.editableFeatures)
            });
          } catch (error) {
            failed.push({ sequence, error: this.errorText(error) });
          }
        })
      );
    }
    this.isSaving = false;
    if (failed.length) {
      this.annotationTargets = failed.map((failure) => failure.sequence);
      this.dialogError = `${targets.length - failed.length} sequences saved. Retry the remaining ${failed.length}: ${failed.map((failure) => failure.error).join("; ")}`;
      return;
    }
    this.activeDialog = "";
    this.annotationTargets = [];
    await this.loadSequences(false);
    this.toast(
      "Annotations saved",
      `Annotations added to ${targets.length} sequences.`,
      "success"
    );
  }

  async removeManualFeature(event) {
    if (this.isBusy) return;
    const index = Number(event.currentTarget.dataset.index);
    const feature = this.selectedSequence.manualFeatures[index];
    this.isSaving = true;
    try {
      await removeManualFeature({
        sequenceId: this.selectedSequence.id,
        featureIndex: index,
        featureJson: JSON.stringify(feature)
      });
      await this.openSequence(this.selectedSequence.id);
    } catch (error) {
      this.toast("Annotation not removed", this.errorText(error), "error");
    } finally {
      this.isSaving = false;
    }
  }

  async removeAutomaticFeature(event) {
    if (this.isBusy) return;
    const index = Number(event.currentTarget.dataset.index);
    const feature = this.selectedSequence.plannotateFeatures[index];
    this.isSaving = true;
    try {
      await removePlannotateFeature({
        sequenceId: this.selectedSequence.id,
        featureIndex: index,
        featureJson: JSON.stringify(feature)
      });
      await this.openSequence(this.selectedSequence.id);
    } catch (error) {
      this.toast("Annotation not removed", this.errorText(error), "error");
    } finally {
      this.isSaving = false;
    }
  }

  openRename() {
    this.draftName = this.selectedSequence.sequenceName;
    this.dialogError = "";
    this.activeDialog = "rename";
  }
  async confirmRename() {
    this.isSaving = true;
    this.dialogError = "";
    try {
      await renameSequence({
        sequenceId: this.selectedSequence.id,
        name: this.draftName
      });
      await this.openSequence(this.selectedSequence.id);
      this.activeDialog = "";
    } catch (error) {
      this.dialogError = this.errorText(error);
    } finally {
      this.isSaving = false;
    }
  }

  get detailVectorOptions() {
    if (this.isLoadingVectors) return [];
    return this.vectorOptions.map((option) => ({
      ...option,
      selected: option.value === (this.selectedSequence?.vectorId || ""),
      checkmark:
        option.value === (this.selectedSequence?.vectorId || "") ? "✓" : ""
    }));
  }

  get noAvailableVectors() {
    return (
      !this.isLoadingVectors &&
      !this.vectorError &&
      this.vectorOptions.length === 1
    );
  }

  closeVectorDropdown() {
    this.showVectorDropdown = false;
    this.isLoadingVectors = false;
    ++this.vectorRequest;
  }

  async openVectorEditor() {
    if (this.isBusy) return;
    if (this.showVectorDropdown) {
      this.closeVectorDropdown();
      return;
    }
    const sequenceId = this.selectedSequence.id;
    const request = ++this.vectorRequest;
    this.vectorError = "";
    this.vectorOptions = [];
    this.showVectorDropdown = true;
    this.isLoadingVectors = true;
    try {
      const options = await getQuoteOptions();
      if (
        request !== this.vectorRequest ||
        sequenceId !== this.selectedSequence?.id
      )
        return;
      this.vectorOptions = [
        { label: "No vector", value: "" },
        ...options.vectors
      ];
    } catch (error) {
      if (request === this.vectorRequest)
        this.vectorError = this.errorText(error);
    } finally {
      if (request === this.vectorRequest) this.isLoadingVectors = false;
    }
  }

  handleVectorBlur(event) {
    if (!event.currentTarget.contains(event.relatedTarget))
      this.closeVectorDropdown();
  }

  handleVectorKey(event) {
    if (event.key === "Escape") {
      event.preventDefault();
      this.closeVectorDropdown();
      this.template.querySelector(".vector-select")?.focus();
      return;
    }
    if (
      !this.showVectorDropdown ||
      !["ArrowDown", "ArrowUp", "Home", "End"].includes(event.key)
    )
      return;
    event.preventDefault();
    const options = [...this.template.querySelectorAll(".vector-option")];
    if (!options.length) return;
    const current = options.indexOf(event.target);
    const next =
      event.key === "Home"
        ? 0
        : event.key === "End"
          ? options.length - 1
          : event.key === "ArrowDown"
            ? (current + 1) % options.length
            : current <= 0
              ? options.length - 1
              : current - 1;
    options[next].focus();
  }

  async handleSelectVector(event) {
    const vectorId = event.currentTarget.dataset.vectorId;
    this.closeVectorDropdown();
    if (vectorId === (this.selectedSequence.vectorId || "")) return;
    this.isSaving = true;
    this.vectorError = "";
    try {
      await saveVector({
        sequenceId: this.selectedSequence.id,
        vectorId: vectorId || null
      });
      if (await this.openSequence(this.selectedSequence.id)) {
        this.toast(
          "Vector updated",
          "Feasibility was requested for the new vector.",
          "success"
        );
      }
    } catch (error) {
      this.vectorError = this.errorText(error);
    } finally {
      this.isSaving = false;
    }
  }

  async handleShare() {
    this.dialogError = "";
    this.shareUrl = "";
    this.activeDialog = "share";
    try {
      const path = await this[NavigationMixin.GenerateUrl]({
        type: "comm__namedPage",
        attributes: { name: "Sequences__c" },
        state: { c__sequenceId: this.selectedSequence.id }
      });
      this.shareUrl = new URL(path, window.location.origin).href;
    } catch (error) {
      this.dialogError = this.errorText(error);
    }
  }
  async copyShareLink() {
    try {
      if (!navigator.clipboard?.writeText) {
        this.template.querySelector(".share-url")?.select();
        return;
      }
      await navigator.clipboard.writeText(this.shareUrl);
      this.toast(
        "Link copied",
        "Account access is still required to open this sequence.",
        "success"
      );
    } catch (error) {
      this.dialogError = "Select the link and copy it using your browser.";
    }
  }
  get annotationStatus() {
    return this.selectedSequence?.plannotateStatus || "Not run";
  }
  get isAnnotationRunDisabled() {
    return (
      this.isBusy ||
      !this.annotationServiceAvailable ||
      this.annotationStatus === "Queued"
    );
  }
  get annotationServiceHint() {
    if (!this.annotationServiceAvailable)
      return "The hosted Plannotate service is not configured.";
    if (this.annotationStatus === "Failed")
      return "Automatic annotation failed. Try again or contact support.";
    if (this.annotationStatus === "Queued")
      return "Annotation was requested. Refresh to see the result.";
    if (this.annotationStatus === "Outdated")
      return "The DNA changed. Run Plannotate again for the current sequence.";
    return "Run automatic annotation";
  }
  async runAnnotation() {
    this.isSaving = true;
    try {
      await requestAnnotation({ sequenceId: this.selectedSequence.id });
      await this.refreshDetail();
      this.toast(
        "Plannotate requested",
        "Automatic annotation was queued. Refresh to see the result.",
        "success"
      );
    } catch (error) {
      this.toast("Plannotate failed", this.errorText(error), "error");
    } finally {
      this.isSaving = false;
    }
  }
  async refreshDetail() {
    await this.openSequence(this.selectedSequence.id);
  }
  async handleRequestFeasibility() {
    this.isSaving = true;
    try {
      await requestFeasibility({ sequenceId: this.selectedSequence.id });
      await this.refreshDetail();
      this.toast(
        "Feasibility requested",
        "Your sequence was queued for assessment. Refresh to see the returned result.",
        "success"
      );
    } catch (error) {
      this.toast("Feasibility request failed", this.errorText(error), "error");
    } finally {
      this.isSaving = false;
    }
  }

  // ---------- upload ----------

  async handleUploadFile(event) {
    const input = event.target;
    const file = input.files?.[0];
    input.value = "";
    if (!file || this.isUploading) return;
    this.isUploading = true;
    this.bannerMessage = "";
    this.toast("Upload", `Reading ${file.name}...`, "info");
    try {
      const records = await this.readRecords(file);
      const { names, sequences, errors } = normalizeRecords(records, file.name);
      if (errors.length) {
        this.toast(
          "Upload not saved",
          `${errors.slice(0, 3).join(" ")} Nothing was added.`,
          "error"
        );
        return;
      }
      await uploadSequences({ names, sequences });
      this.toast(
        "Upload complete",
        `${names.length} sequence${names.length === 1 ? "" : "s"} added from ${file.name}.`,
        "success"
      );
      this.offsetRows = 0;
      await this.loadSequences(false);
    } catch (error) {
      console.error("Sequence upload failed", error);
      this.toast("Upload failed", this.errorText(error), "error");
    } finally {
      this.isUploading = false;
    }
  }

  async readRecords(file) {
    if (file.size > MAX_UPLOAD_BYTES) {
      throw new Error("The file is larger than 5 MB.");
    }
    const ext = (file.name.split(".").pop() || "").toLowerCase();
    if (ext === "xls" || ext === "xlsx") return this.readSpreadsheet(file);
    const text = await readFile(file, false);
    if (ext === "gb" || ext === "gbk") return parseGenBank(text);
    if (ext === "fasta" || ext === "fa") return parseFasta(text);
    throw new Error("Unsupported file type. Use XLS, FASTA, or GB.");
  }

  // Reads the first sheet. Uses "Name" and "Sequence" headers when present,
  // otherwise treats column A as the name and column B as the sequence.
  async readSpreadsheet(file) {
    if (!this.sheetJsLoaded) {
      await loadScript(this, SHEETJS);
      this.sheetJsLoaded = true;
    }
    const XLSX = window.XLSX;
    const workbook = XLSX.read(await readFile(file, true), { type: "array" });
    const sheet = workbook.Sheets[workbook.SheetNames[0]];
    const rows = XLSX.utils.sheet_to_json(sheet, {
      header: 1,
      blankrows: false
    });
    const header = (rows[0] || []).map((cell) =>
      String(cell || "")
        .trim()
        .toLowerCase()
    );
    let sequenceIndex = header.findIndex(
      (text) => text.includes("sequence") && !text.includes("name")
    );
    let nameIndex = header.findIndex(
      (text) => text.includes("name") || text === "id"
    );
    let start = 1;
    if (sequenceIndex < 0) {
      nameIndex = 0;
      sequenceIndex = 1;
      start = 0;
    }
    return rows.slice(start).map((cells) => ({
      name: nameIndex >= 0 ? cells[nameIndex] : "",
      sequence: cells[sequenceIndex]
    }));
  }

  // ---------- detail + optimize ----------

  async openSequence(sequenceId) {
    if (this.linkedSequenceId !== sequenceId) {
      this.linkedSequenceId = sequenceId;
      this[NavigationMixin.Navigate]({
        type: "comm__namedPage",
        attributes: { name: "Sequences__c" },
        state: { c__sequenceId: sequenceId }
      });
    }
    this.closeVectorDropdown();
    const request = ++this.detailRequest;
    this.isLoading = true;
    this.errorMessage = "";
    try {
      const sequence = await getSequence({ sequenceId });
      if (request !== this.detailRequest) return false;
      this.selectedSequence = sequence;
      return true;
    } catch (error) {
      if (request === this.detailRequest)
        this.errorMessage = this.errorText(error);
      return false;
    } finally {
      if (request === this.detailRequest) this.isLoading = false;
    }
  }

  handleBack() {
    this.linkedSequenceId = undefined;
    this[NavigationMixin.Navigate]({
      type: "comm__namedPage",
      attributes: { name: "Sequences__c" },
      state: { c__sequenceId: undefined }
    });
    this.activeDialog = "";
    this.closeVectorDropdown();
    ++this.detailRequest;
    this.showOptimizeInfo = false;
    this.selectedSequence = null;
    this.offsetRows = 0;
    this.loadSequences(false); // show new optimized copies and uploads
  }

  get sequenceText() {
    return this.selectedSequence?.sequence || "No sequence data available.";
  }

  get isOptimizeDisabled() {
    return !this.selectedSequence?.optimizationAvailable;
  }

  get detailFeasibility() {
    return this.selectedSequence?.feasibility || "Not available";
  }

  get detailStatus() {
    return this.selectedSequence?.status || "Designed";
  }

  get detailStatusClass() {
    return `pill pill--${this.detailStatus.toLowerCase().replace(/\s+/g, "-")}`;
  }

  get detailCreatedDate() {
    return formatDate(this.selectedSequence?.createdDate) || "\u2014";
  }

  get detailOrderedDate() {
    return formatDate(this.selectedSequence?.orderedDate) || "\u2014";
  }

  get detailComplexity() {
    return this.selectedSequence?.complexity || "Not available";
  }

  openOptimizeInfo() {
    this.optimizationTargets = [];
    if (!this.isOptimizeDisabled) this.showOptimizeInfo = true;
  }

  closeOptimizeInfo() {
    const optimizer = this.template.querySelector("c-codon-optimizer");
    if (optimizer?.isBusy) return;
    this.showOptimizeInfo = false;
    this.optimizationTargets = [];
  }

  handleDownloadCsv() {
    const s = this.selectedSequence;
    if (!s) return;
    // Prefix risky leading characters so Excel cannot run a cell as a formula.
    const cell = (value) => {
      let text = String(value ?? "");
      if (/^\s*[=+\-@]/.test(text) || /^[\t\r\n]/.test(text)) text = `'${text}`;
      return `"${text.replace(/"/g, '""')}"`;
    };
    const header = [
      "Name",
      "Sequence",
      "Length",
      "Owner",
      "Vector",
      "Feasibility",
      "Complexity",
      "Status"
    ];
    const values = [
      s.sequenceName,
      s.sequence,
      s.length,
      s.ownerName,
      s.vectorName,
      this.detailFeasibility,
      this.detailComplexity,
      this.detailStatus
    ];
    const csv = `${header.map(cell).join(",")}\r\n${values.map(cell).join(",")}\r\n`;
    const url = URL.createObjectURL(
      new Blob([csv], { type: "text/csv;charset=utf-8" })
    );
    const link = document.createElement("a");
    link.href = url;
    link.download = `${s.sequenceName || "sequence"}.csv`;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
  }

  stopModalClick(event) {
    event.stopPropagation();
  }

  async handleOptimizationComplete(event) {
    if (this.optimizationTargets.length && this.isListView) {
      const count =
        event.detail.optimizedSequenceIds?.length ||
        event.detail.successes?.length ||
        1;
      const failures = event.detail.failures || [];
      this.showOptimizeInfo = false;
      this.optimizationTargets = [];
      await this.loadSequences(false);
      this.selectedIds = failures.map((failure) => failure.sequenceId);
      this.toast(
        "Optimization complete",
        `${count} optimized copies created.${failures.length ? " " + failures.length + " failed: " + failures.map((failure) => failure.name + ": " + failure.error).join("; ") : ""}`,
        failures.length ? "warning" : "success"
      );
      return;
    }
    const copyId = event?.detail?.optimizedSequenceId;
    this.showOptimizeInfo = false;
    const openId = copyId || this.selectedSequence?.id;
    if (openId) await this.openSequence(openId);
    this.toast(
      "Optimized copy created",
      "The optimized DNA was saved as a new sequence. The original is unchanged.",
      "success"
    );
  }

  // ---------- helpers ----------

  toast(title, message, variant) {
    this.bannerMessage = `${title}: ${message}`;
    this.bannerType = variant || "info";
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  errorText(error) {
    return (
      error?.body?.message || error?.message || "Unable to load sequences."
    );
  }
}
