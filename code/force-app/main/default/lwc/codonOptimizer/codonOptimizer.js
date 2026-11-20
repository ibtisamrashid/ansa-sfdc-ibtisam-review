import { LightningElement, api, track } from "lwc";
import getOrganisms from "@salesforce/apex/CodonController.getOrganisms";
import submitJob from "@salesforce/apex/CodonController.submitJob";
import submitSequenceJob from "@salesforce/apex/CodonController.submitSequenceJob";
import getJobStatus from "@salesforce/apex/CodonController.getJobStatus";

const MAX_SEQUENCES = 96;
const MAX_PROTEIN_LENGTH = 2045;
const AA_PATTERN = /^[ACDEFGHIKLMNPQRSTVWY*]+$/i;
const DNA_PATTERN = /^[ACGT]+$/i;
const TERMINAL_STATUSES = new Set(["done", "error", "cancelled"]);

export default class CodonOptimizer extends LightningElement {
  @api quoteId;
  @api sequenceId;
  @api aminoAcidId;
  _sequenceTargets = [];
  @track bulkProteins = {};
  bulkJobs = [];
  bulkCompletionSent = false;

  @api
  get sequenceTargets() {
    return this._sequenceTargets;
  }
  set sequenceTargets(value) {
    this._sequenceTargets = Array.isArray(value) ? value : [];
    this.bulkProteins = Object.fromEntries(
      this._sequenceTargets.map((target) => [
        target.id,
        target.aminoAcidSequence || ""
      ])
    );
  }

  get isBulkMode() {
    return this._sequenceTargets.length > 1;
  }
  get hasSequenceContext() {
    return Boolean(this.sequenceId) || this.isBulkMode;
  }
  get optimizeButtonLabel() {
    return this.isBulkMode
      ? "Optimize selected sequences"
      : "Optimize sequence";
  }
  get bulkProteinRows() {
    return this._sequenceTargets.map((target) => ({
      ...target,
      protein: this.bulkProteins[target.id] || ""
    }));
  }
  get bulkInputTitle() {
    return `Selected sequences (${this._sequenceTargets.length})`;
  }
  handleBulkProteinInput(event) {
    this.bulkProteins = {
      ...this.bulkProteins,
      [event.target.dataset.sequenceId]: event.target.value || ""
    };
    this.errorMessage = "";
  }
  _initialSequence = "";
  _initialSettings = {};

  @api
  get initialSequence() {
    return this._initialSequence;
  }
  set initialSequence(value) {
    this._initialSequence = value || "";
    this.manualSequence = this._initialSequence;
  }

  @api
  get initialSettings() {
    return this._initialSettings;
  }
  set initialSettings(value) {
    this._initialSettings = value || {};
    this.modelKey = this._initialSettings.modelKey || this.modelKey;
    this.organismSlug = this._initialSettings.organismSlug || "";
    this.flank5 = this._initialSettings.flank5 || "";
    this.flank3 = this._initialSettings.flank3 || "";
  }

  @track organismGroups = [];
  @track organismSlug = "";
  @track modelKey = "codontransformer";
  @track flank5 = "";
  @track flank3 = "";
  @track includeStop = true;
  @track deterministic = true;
  @track showFlanks = false;
  @track showSites = false;
  @track showAdvanced = false;
  @track showCustomSites = false;
  @track selectedEnzymes = [];
  @track customSitesText = "";
  @track fileName = "";
  @track manualSequence = "";
  @track errorMessage = "";
  @track warningMessage = "";
  @track results = [];
  @track jobStatus = "";
  @track jobStage = "";
  @track progress = 0;
  @track isLoadingCatalog = false;
  @track showWarningDecision = false;
  @track resultSummary = "";
  _isBusy = false;
  isPolling = false;
  file = null;
  pendingRows = [];
  pollTimer;
  jobId;

  @api
  get isBusy() {
    return this._isBusy;
  }

  connectedCallback() {
    this.loadOrganisms();
  }

  disconnectedCallback() {
    if (this.pollTimer) clearTimeout(this.pollTimer);
    this.isPolling = false;
  }

  @api
  get initialFile() {
    return this.file;
  }
  set initialFile(file) {
    if (file && file !== this.file) {
      this.file = file;
      this.fileName = file.name;
    }
  }

  get organismOptions() {
    return (this.organismGroups || []).flatMap((group) =>
      (group.organisms || []).map((organism) => ({
        label: organism.name,
        value: organism.slug
      }))
    );
  }

  get organismLabel() {
    return `Target organism (${this.organismCount} available)`;
  }

  get organismCount() {
    return this.organismOptions.length;
  }

  get availableModels() {
    return (
      (this.organismGroups || [])
        .flatMap((group) => group.organisms || [])
        .find((organism) => organism.slug === this.organismSlug)?.models || []
    );
  }

  get modelOptions() {
    return this.availableModels.map((model) => ({
      label: this.modelLabel(model),
      value: model
    }));
  }

  get modelOptionsForButtons() {
    const models = [
      ...new Set(["trias", "codontransformer", ...this.availableModels])
    ];
    return models
      .map((value) => ({ value, label: this.modelLabel(value) }))
      .map((model) => ({
        ...model,
        selected: this.modelKey === model.value,
        disabled:
          !this.organismSlug || !this.availableModels.includes(model.value),
        className: `model-button${this.modelKey === model.value ? " model-button--selected" : ""}${this.organismSlug && !this.availableModels.includes(model.value) ? " model-button--unavailable" : ""}`
      }));
  }

  modelLabel(modelKey) {
    const labels = {
      trias: "Trias",
      codontransformer: "CodonTransformer"
    };
    return labels[modelKey] || modelKey;
  }

  get hasModelChoice() {
    return this.availableModels.length > 1;
  }

  get selectedModelLabel() {
    return this.modelLabel(this.modelKey);
  }

  get enzymeOptions() {
    return [
      { label: "BsaI", value: "BsaI", sequence: "GGTCTC" },
      { label: "BsmBI", value: "BsmBI", sequence: "CGTCTC" },
      { label: "PaqCI", value: "PaqCI", sequence: "CACCTGC" },
      { label: "SapI", value: "SapI", sequence: "GCTCTTC" }
    ].map((enzyme) => {
      const checked = this.selectedEnzymes.includes(enzyme.value);
      return {
        ...enzyme,
        checked,
        className: `enzyme-chip${checked ? " enzyme-chip--selected" : ""}`
      };
    });
  }

  get selectedEnzymeCount() {
    return this.selectedEnzymes.length + (this.hasCustomSites ? 1 : 0);
  }

  get hasCustomSites() {
    return this.showCustomSites || Boolean(this.customSitesText.trim());
  }

  get hasResults() {
    return this.results.length > 0;
  }

  get succeededCount() {
    return this.results.filter((row) => !row.error && row.dna).length;
  }

  get failedCount() {
    return this.results.filter((row) => row.error || !row.dna).length;
  }

  get progressLabel() {
    return this.jobStatus === "queued" || this.jobStatus === "loading_model"
      ? "Preparing optimizer…"
      : this.jobStage || "Optimizing sequences…";
  }

  async loadOrganisms() {
    this.isLoadingCatalog = true;
    try {
      const response = await getOrganisms();
      this.organismGroups = response?.groups || [];
      if (this.organismSlug) {
        const selected = this.organismGroups
          .flatMap((group) => group.organisms || [])
          .find((organism) => organism.slug === this.organismSlug);
        if (!selected) this.organismSlug = "";
        else if (!selected.models?.includes(this.modelKey))
          this.modelKey = selected.default_model || selected.models?.[0] || "";
      }
    } catch (error) {
      this.errorMessage = this.errorText(error);
    } finally {
      this.isLoadingCatalog = false;
    }
  }

  handleChange(event) {
    const { name, value, checked, type } = event.target;
    this[name] = type === "checkbox" ? checked : value;
    if (name === "organismSlug") {
      const organism = this.organismGroups
        .flatMap((group) => group.organisms || [])
        .find((item) => item.slug === value);
      this.modelKey = organism?.default_model || organism?.models?.[0] || "";
    }
  }

  handleReplacementFile(event) {
    const file = event.target.files?.[0];
    if (!file) return;
    this.manualSequence = "";
    this.file = file;
    this.fileName = file.name;
    this.errorMessage = "";
    this.results = [];
    this.jobStatus = "";
  }

  handleManualInput(event) {
    this.manualSequence = event.target.value || "";
    this.file = null;
    this.fileName = "";
    this.errorMessage = "";
    this.results = [];
    this.jobStatus = "";
  }

  handleModelSelect(event) {
    const nextModel = event.currentTarget.dataset.model;
    if (
      !this.availableModels.length ||
      this.availableModels.includes(nextModel)
    ) {
      this.modelKey = nextModel;
    }
  }

  toggleFlanks() {
    this.showFlanks = !this.showFlanks;
  }

  toggleSites() {
    this.showSites = !this.showSites;
  }

  toggleAdvanced() {
    this.showAdvanced = !this.showAdvanced;
  }

  toggleCustomSites(event) {
    this.showCustomSites = event.target.checked;
    if (!this.showCustomSites) this.customSitesText = "";
  }

  handleEnzymeChange(event) {
    const value = event.target.value;
    this.selectedEnzymes = event.target.checked
      ? [...new Set([...this.selectedEnzymes, value])]
      : this.selectedEnzymes.filter((enzyme) => enzyme !== value);
  }

  @api
  async optimize() {
    if (this._isBusy) return;
    this.errorMessage = "";
    this.warningMessage = "";
    this.results = [];
    if (!this.isBulkMode && !this.file && !this.manualSequence.trim()) {
      this.errorMessage =
        "Upload a FASTA or CSV file, or paste an amino acid sequence.";
      return;
    }
    if (!this.organismSlug || !this.modelKey) {
      this.errorMessage = "Please select a target organism.";
      return;
    }

    this._isBusy = true;
    try {
      const rows = this.isBulkMode
        ? this._sequenceTargets.map((target) => ({
            name: target.name,
            sequence: (this.bulkProteins[target.id] || "")
              .replace(/\s+/g, "")
              .toUpperCase()
          }))
        : this.file
          ? this.parseFile(await this.file.text(), this.file.name)
          : this.parsePastedSequences(this.manualSequence);
      const missingProtein = rows.find((row) => !row.sequence);
      if (missingProtein) {
        this.errorMessage = `Enter the amino acid sequence for ${missingProtein.name}.`;
        return;
      }
      if (!rows.length) {
        this.errorMessage = "No sequences found in file.";
        return;
      }
      if (rows.length > MAX_SEQUENCES) {
        this.errorMessage = `Maximum ${MAX_SEQUENCES} sequences per upload.`;
        return;
      }
      if (this.sequenceId && !this.isBulkMode && rows.length !== 1) {
        this.errorMessage =
          "Sequence Hub optimization accepts one sequence at a time.";
        return;
      }
      const invalid = rows.findIndex((row) => !AA_PATTERN.test(row.sequence));
      if (invalid >= 0) {
        this.errorMessage = `Sequence ${rows[invalid].name} contains unsupported amino acid characters.`;
        return;
      }
      const tooLong = rows.findIndex(
        (row) => row.sequence.length > MAX_PROTEIN_LENGTH
      );
      if (tooLong >= 0) {
        this.errorMessage = `Sequence ${rows[tooLong].name} exceeds the optimizer limit of ${MAX_PROTEIN_LENGTH.toLocaleString()} amino acids.`;
        return;
      }

      this.pendingRows = rows;
      const dnaRows = rows.filter((row) => DNA_PATTERN.test(row.sequence));
      const startRows = rows.filter(
        (row) =>
          !DNA_PATTERN.test(row.sequence) && !row.sequence.startsWith("M")
      );
      const stopRows = rows.filter(
        (row) => !DNA_PATTERN.test(row.sequence) && !row.sequence.endsWith("*")
      );
      const warnings = [];
      if (dnaRows.length) {
        warnings.push(
          `These sequences look like DNA: ${this.names(dnaRows)}. Proceed as amino acid sequences?`
        );
      }
      if (startRows.length) {
        warnings.push(
          `These sequences do not start with M: ${this.names(startRows)}. Proceed?`
        );
      }
      if (stopRows.length) {
        warnings.push(
          `These sequences do not end with a stop symbol (*): ${this.names(stopRows)}. Proceed?`
        );
      }
      if (warnings.length) {
        this.warningMessage = warnings.join(" ");
        this.showWarningDecision = true;
        return;
      }
      await this.submitPendingRows();
    } catch (error) {
      this.errorMessage = this.errorText(error);
    } finally {
      if (!this.isPolling) this._isBusy = false;
    }
  }

  handleSequenceOptimize() {
    this.optimize();
  }

  async handleProceedWarnings() {
    if (this._isBusy) return;
    this.showWarningDecision = false;
    this._isBusy = true;
    this.errorMessage = "";
    try {
      await this.submitPendingRows();
    } catch (error) {
      this.errorMessage = this.errorText(error);
    } finally {
      if (!this.isPolling) this._isBusy = false;
    }
  }

  handleEditWarnings() {
    this.showWarningDecision = false;
    this.warningMessage = "";
  }

  async submitPendingRows() {
    const request = {
      names: this.pendingRows.map((row) => row.name),
      sequences: this.pendingRows.map((row) => row.sequence),
      modelKey: this.modelKey,
      organismSlug: this.organismSlug,
      flank5: this.flank5,
      flank3: this.flank3,
      includeStop: this.includeStop,
      deterministic: this.deterministic,
      enzymes: this.selectedEnzymes,
      customSites: this.customSitesText
        .split(/[\s,]+/)
        .map((site) => site.trim())
        .filter(Boolean)
    };
    if (this.isBulkMode) {
      await this.submitBulkRows(request);
      return;
    }
    const response = this.sequenceId
      ? await submitSequenceJob({
          ...request,
          sequenceId: this.sequenceId,
          aminoAcidId: this.aminoAcidId
        })
      : await submitJob({ ...request, quoteRequestId: this.quoteId });
    this.jobId = response.jobId;
    this.jobStatus = response.status || "queued";
    this.jobStage = "Job submitted";
    this._isBusy = true;
    this.isPolling = true;
    this.pollJob();
  }

  async submitBulkRows(request) {
    this.bulkJobs = [];
    this.bulkCompletionSent = false;
    this.isPolling = true;
    this.jobStatus = "queued";
    this.jobStage = "Submitting selected sequences";
    this.progress = 0;
    for (let offset = 0; offset < this._sequenceTargets.length; offset += 4) {
      const jobs = await Promise.all(
        this._sequenceTargets
          .slice(offset, offset + 4)
          .map(async (target, index) => {
            const row = this.pendingRows[offset + index];
            try {
              const response = await submitSequenceJob({
                ...request,
                sequenceId: target.id,
                aminoAcidId: target.aminoAcidId || null,
                names: [row.name],
                sequences: [row.sequence]
              });
              if (!response?.jobId)
                throw new Error("The optimizer did not return a job ID.");
              return { target, row, jobId: response.jobId, status: "queued" };
            } catch (error) {
              return {
                target,
                row,
                status: "error",
                error: this.errorText(error)
              };
            }
          })
      );
      this.bulkJobs = [...this.bulkJobs, ...jobs];
    }
    await this.pollBulkJobs();
  }

  async pollBulkJobs() {
    if (!this.isPolling) return;
    const pending = this.bulkJobs.filter(
      (job) => !TERMINAL_STATUSES.has(job.status)
    );
    for (let offset = 0; offset < pending.length; offset += 4) {
      await Promise.all(
        pending.slice(offset, offset + 4).map(async (job) => {
          try {
            const status = await getJobStatus({ jobId: job.jobId });
            job.status = status.status;
            if (status.status === "done") {
              const result = (status.results || []).find(
                (row) => row.fidelity === "ok" && row.dna && !row.error
              );
              if (result && status.optimizedSequenceId) {
                job.result = result;
                job.copyId = status.optimizedSequenceId;
              } else {
                job.status = "error";
                job.error =
                  status.results?.find((row) => row.error)?.error ||
                  "The optimizer returned no verified optimized copy.";
              }
            } else if (TERMINAL_STATUSES.has(status.status)) {
              job.error = status.error || `Optimizer job ${status.status}.`;
            }
          } catch (error) {
            job.status = "error";
            job.error = this.errorText(error);
          }
        })
      );
    }
    const completed = this.bulkJobs.filter((job) =>
      TERMINAL_STATUSES.has(job.status)
    );
    this.progress = Math.round((completed.length / this.bulkJobs.length) * 100);
    this.jobStage = `${completed.length} of ${this.bulkJobs.length} sequences completed`;
    this.results = completed.map((job) => ({
      key: job.target.id,
      name: job.target.name,
      dna: job.result?.dna || "",
      error: job.error || ""
    }));
    if (completed.length !== this.bulkJobs.length) {
      this.pollTimer = setTimeout(() => this.pollBulkJobs(), 1500);
      return;
    }
    this.isPolling = false;
    this._isBusy = false;
    this.jobStatus = "done";
    const successes = this.bulkJobs.filter((job) => job.copyId);
    const failures = this.bulkJobs
      .filter((job) => !job.copyId)
      .map((job) => ({
        sequenceId: job.target.id,
        name: job.target.name,
        error: job.error
      }));
    this.resultSummary = `${successes.length} optimized, ${failures.length} failed`;
    if (successes.length && !this.bulkCompletionSent) {
      this.bulkCompletionSent = true;
      this.dispatchEvent(
        new CustomEvent("optimized", {
          detail: {
            sequenceHub: true,
            optimizedSequenceIds: successes.map((job) => job.copyId),
            successes: successes.map((job) => ({
              name: job.target.name,
              sequence: job.result.dna,
              originalSequenceId: job.target.id
            })),
            failures
          }
        })
      );
    } else if (!successes.length) {
      this.errorMessage =
        "No sequences were optimized. Review the errors for each selected sequence.";
    }
  }

  async pollJob() {
    if (!this.jobId) return;
    try {
      const status = await getJobStatus({ jobId: this.jobId });
      this.jobStatus = status.status;
      this.jobStage = status.stage || status.status;
      const completed = status.progress?.completed || 0;
      const total = status.progress?.total || this.pendingRows.length || 1;
      this.progress = Math.min(100, Math.round((completed / total) * 100));
      if (status.status === "done") {
        this.results = (status.results || []).map((row, index) => ({
          ...row,
          key: row.recordId || String(index),
          error:
            row.error ||
            (row.fidelity !== "ok"
              ? `Sequence verification failed (${row.fidelity || "status unavailable"}).`
              : "")
        }));
        this.resultSummary = `${this.succeededCount} optimized, ${this.failedCount} failed`;
        const successes = this.results
          .filter((row) => !row.error && row.dna)
          .map((row) => {
            const rowIndex = Number(
              String(row.recordId || "").replace(/^row-/, "")
            );
            const original = Number.isInteger(rowIndex)
              ? this.pendingRows[rowIndex]
              : null;
            return {
              name: row.name,
              sequence: row.dna,
              aminoAcidSequence: original?.sequence || null,
              aminoAcidRecordId: row.aminoAcidId || null
            };
          });
        const failures = this.results
          .filter((row) => row.error || !row.dna)
          .map((row) => ({
            name: row.name,
            error: row.error || "No DNA was returned."
          }));
        if (successes.length) {
          this.dispatchEvent(
            new CustomEvent("optimized", {
              detail: {
                successes,
                failures,
                warnings: status.warnings || [],
                sequenceHub: Boolean(this.sequenceId),
                optimizedSequenceId: status.optimizedSequenceId || null
              }
            })
          );
        }
        this._isBusy = false;
        this.isPolling = false;
        return;
      }
      if (TERMINAL_STATUSES.has(status.status)) {
        this.errorMessage = status.error || `Optimizer job ${status.status}.`;
        this._isBusy = false;
        this.isPolling = false;
        return;
      }
      this.pollTimer = setTimeout(() => this.pollJob(), 1500);
    } catch (error) {
      this.errorMessage = this.errorText(error);
      this._isBusy = false;
      this.isPolling = false;
    }
  }

  parseFile(text, fileName) {
    const extension = (fileName.split(".").pop() || "").toLowerCase();
    if (["fasta", "fa", "faa"].includes(extension)) {
      const rows = [];
      let current;
      for (const rawLine of text.replace(/\r/g, "").split("\n")) {
        const line = rawLine.trim();
        if (!line) continue;
        if (line.startsWith(">")) {
          current = {
            name: line.slice(1).trim() || `Sequence_${rows.length + 1}`,
            sequence: ""
          };
          rows.push(current);
        } else if (current) {
          current.sequence += line.replace(/\s+/g, "").toUpperCase();
        } else {
          throw new Error(
            "FASTA data must start with a >sequence-name header."
          );
        }
      }
      return rows.filter((row) => row.sequence);
    }
    if (extension !== "csv") {
      throw new Error(
        "Unsupported file type. Upload a .fasta, .fa, .faa, or .csv file."
      );
    }
    const table = this.parseCsv(text);
    if (table.length < 2) return [];
    const headers = table[0].map((value) => value.trim().toLowerCase());
    const nameIndex = headers.findIndex((value) =>
      ["name", "sequencename", "sequence_name"].includes(value)
    );
    const sequenceIndex = headers.findIndex((value) =>
      ["sequence", "amino acid sequence", "amino_acid_sequence"].includes(value)
    );
    if (sequenceIndex < 0) {
      throw new Error(
        "CSV must include a Sequence column and may include a Name column."
      );
    }
    return table
      .slice(1)
      .map((columns, index) => ({
        name:
          (nameIndex >= 0 ? columns[nameIndex] : "").trim() ||
          `Sequence_${index + 1}`,
        sequence: (columns[sequenceIndex] || "")
          .replace(/\s+/g, "")
          .toUpperCase()
      }))
      .filter((row) => row.sequence);
  }

  parsePastedSequences(text) {
    const normalized = (text || "").trim();
    if (!normalized) return [];
    if (normalized.startsWith(">"))
      return this.parseFile(normalized, "pasted.fasta");
    return [
      {
        name: "Sequence_1",
        sequence: normalized.replace(/\s+/g, "").toUpperCase()
      }
    ];
  }

  parseCsv(text) {
    const rows = [];
    let row = [];
    let value = "";
    let quoted = false;
    const input = text.replace(/^\uFEFF/, "");
    for (let i = 0; i < input.length; i++) {
      const char = input[i];
      if (char === '"') {
        if (quoted && input[i + 1] === '"') {
          value += '"';
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (char === "," && !quoted) {
        row.push(value);
        value = "";
      } else if ((char === "\n" || char === "\r") && !quoted) {
        if (char === "\r" && input[i + 1] === "\n") i++;
        row.push(value);
        if (row.some((cell) => cell.trim())) rows.push(row);
        row = [];
        value = "";
      } else {
        value += char;
      }
    }
    if (quoted) throw new Error("CSV contains an unclosed quoted field.");
    row.push(value);
    if (row.some((cell) => cell.trim())) rows.push(row);
    return rows;
  }

  names(rows) {
    return rows.map((row) => row.name).join(", ");
  }

  errorText(error) {
    return (
      error?.body?.message ||
      error?.message ||
      "Optimizer request failed. Please try again."
    );
  }

  downloadResults() {
    const quoteCsv = (value) => `"${String(value || "").replace(/"/g, '""')}"`;
    const rows = ["Name,DNA,Error"];
    this.results.forEach((row) => {
      rows.push([row.name, row.dna, row.error].map(quoteCsv).join(","));
    });
    const blobUrl = window.URL.createObjectURL(
      new Blob([rows.join("\r\n")], { type: "text/csv;charset=utf-8" })
    );
    const link = document.createElement("a");
    link.href = blobUrl;
    link.download = "codon-optimization-results.csv";
    link.click();
    window.URL.revokeObjectURL(blobUrl);
  }

  handleRemoveFile() {
    if (this._isBusy) return;
    this.file = null;
    this.fileName = "";
    this.errorMessage = "";
    this.results = [];
    this.jobStatus = "";
  }
}
