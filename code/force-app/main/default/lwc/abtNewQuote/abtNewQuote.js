import { LightningElement, api, track, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { getRecord } from "lightning/uiRecordApi";
import { refreshApex } from "@salesforce/apex";
import { pushDataLayerEvent } from "c/abtGoogleAdsTracking";
import {
  formatProductName,
  SEQUENCE_NAME_MAX_LENGTH,
  DUPLICATE_SEQUENCE_NAME_ERROR,
  getSequenceNameValidationError,
  getSequenceNameErrorForRow,
  getSequenceVectorValidationError,
  isSequenceVectorMissing,
  getVectorRequiredBannerMessage,
  getDuplicateSequenceNameKeys,
  normalizeSequenceNameForCompare,
  isModalSequenceSaved,
  salesFeesFromQuoteLineItems,
  salesFeesForQuoteRequestLine
} from "c/abtProductNameUtils";
import { trancheDisplay } from "c/abtTrancheUtils";
import {
  sequenceNameFromRow as portalSequenceNameFromRow,
  sequenceTextFromRow as portalSequenceTextFromRow,
  normalizeFeasibilityFromRow as portalNormalizeFeasibilityFromRow,
  normalizeComplexityFromRow as portalNormalizeComplexityFromRow,
  feasibilityExplainedFromRow,
  createQuoteRequestLineItemsChunked,
  recommendNotHighCopyFromRow
} from "c/abtPortalLineItemUtils";
import { homopolymerSequenceNames } from "c/abtHomopolymerFlagUtils";
import {
  buildSequenceExportCsv,
  exportColumns
} from "c/abtFeasibilityExplainedUtils";
import csvTemplate from "@salesforce/resourceUrl/ABT_CSVQuoteTemplate";
import ABT_MiniGame from "@salesforce/resourceUrl/ABT_MiniGame";
import ABT_Ansa_Logo from "@salesforce/resourceUrl/ABT_Ansa_Logo";
import pdfTerms from "@salesforce/label/c.ABT_QuotePdf_Terms_and_Condition";
import getQuoteRequestsByAccount from "@salesforce/apex/ABT_Portal_Controller.getQuoteRequestsByAccount";
import getVectorLibraryData from "@salesforce/apex/ABT_Portal_Controller.getVectorLibraryData";
import getScaleUpLibraryData from "@salesforce/apex/ABT_Portal_Controller.getScaleUpLibraryData";
import getUserDetailsById from "@salesforce/apex/ABT_Portal_Controller.getUserDetailsById";
import isIdtChannelPartnerAccount from "@salesforce/apex/ABT_IdtChannelPartner.isAccountIdtChannelPartner";
import getProductById from "@salesforce/apex/ABT_Portal_Controller.getProductById";
import createQuoteRequest from "@salesforce/apex/ABT_Portal_Controller.createQuoteRequest";
import createQuoteRequestLineItem from "@salesforce/apex/ABT_Portal_Controller.createQuoteRequestLineItem";
import updateSequenceForLineItem from "@salesforce/apex/ABT_Portal_Controller.updateSequenceForLineItem";
import createQuoteRequestLineItemsDeferredKick from "@salesforce/apex/ABT_PortalSequenceCreate.createQuoteRequestLineItemsDeferredKick";
import linkAminoAcidSequence from "@salesforce/apex/CodonController.linkAminoAcidSequence";
import enqueuePendingForQuoteRequest from "@salesforce/apex/ABT_PortalSequenceCreate.enqueuePendingForQuoteRequest";
import getQuoteRequestDisplayQuoteNumber from "@salesforce/apex/ABT_Portal_Controller.getQuoteRequestDisplayQuoteNumber";
import getLineItemPricing from "@salesforce/apex/ABT_Portal_Controller.getLineItemPricing";
import getQuoteRequestSalesLineItems from "@salesforce/apex/ABT_Portal_Controller.getQuoteRequestSalesLineItems";
import addQuoteRequestToCommerceCart from "@salesforce/apex/ABT_Portal_Controller.addQuoteRequestToCommerceCart";
import updateQuoteRequestPackaging from "@salesforce/apex/ABT_Portal_Controller.updateQuoteRequestPackaging";
import uploadPODocument from "@salesforce/apex/ABT_Portal_Controller.uploadPODocument";
import {
  formatPackagingPicklistOptions,
  PACKAGING_PLACEHOLDER,
  resolvePackagingPicklistValue
} from "c/abtPackagingUtils";
import { getObjectInfo, getPicklistValues } from "lightning/uiObjectInfoApi";
import QUOTE_REQUEST_OBJECT from "@salesforce/schema/ABT_Quote_Request__c";
import REQUEST_PACKAGING_FIELD from "@salesforce/schema/ABT_Quote_Request__c.Request_Packaging__c";
import QUOTE_REQUEST_LINE_ITEM_OBJECT from "@salesforce/schema/ABT_Quote_Request_Lineitem__c";
import SCALE_UP_BUFFER_FIELD from "@salesforce/schema/ABT_Quote_Request_Lineitem__c.Scale_Up_Buffer__c";
import SCALE_UP_NORMALIZATION_FIELD from "@salesforce/schema/ABT_Quote_Request_Lineitem__c.Scale_Up_Normalization__c";
import {
  DEFAULT_ALLOWED_SEQUENCE_CHARACTERS,
  getAllowedSequenceCharactersText,
  validateSequenceCharacters
} from "c/abtSequenceValidationUtils";
import updateQuoteLineItemVector from "@salesforce/apex/ABT_Portal_Controller.updateQuoteLineItemVector";
import bulkUpdateQuoteLineItemVectors from "@salesforce/apex/ABT_Portal_Controller.bulkUpdateQuoteLineItemVectors";
import updateQuoteRequestLineItemGlycerol from "@salesforce/apex/ABT_Portal_Controller.updateQuoteRequestLineItemGlycerol";
import bulkUpdateQuoteRequestLineItemGlycerol from "@salesforce/apex/ABT_Portal_Controller.bulkUpdateQuoteRequestLineItemGlycerol";
import updateQuoteRequestLineItemPotentiallyToxic from "@salesforce/apex/ABT_Portal_Controller.updateQuoteRequestLineItemPotentiallyToxic";
import bulkUpdateQuoteRequestLineItemPotentiallyToxic from "@salesforce/apex/ABT_Portal_Controller.bulkUpdateQuoteRequestLineItemPotentiallyToxic";
import updateQuoteRequestLineItemReflexVectorOptIn from "@salesforce/apex/ABT_Portal_Controller.updateQuoteRequestLineItemReflexVectorOptIn";
import bulkUpdateQuoteRequestLineItemReflexVectorOptIn from "@salesforce/apex/ABT_Portal_Controller.bulkUpdateQuoteRequestLineItemReflexVectorOptIn";
import updateQuoteRequestLineItemScaleUp from "@salesforce/apex/ABT_Portal_Controller.updateQuoteRequestLineItemScaleUp";
import {
  SCALE_UP_DEFAULT_BUFFER,
  fromScaleUpNormalizationApiValue,
  toScaleUpNormalizationApiValue
} from "c/abtScaleUpUtils";
import deleteRecordById from "@salesforce/apex/ABT_Portal_Controller.deleteRecordById";

import userId from "@salesforce/user/Id";

const PENDING_CART_QR_KEY = "abt_pendingCartQuoteRequestId";
const CART_PAGE_URL = "/my-cart";
/** Matches ABT_Quote_Request__c.ABT_Customer_Project_Name__c max length. */
const PROJECT_NAME_MAX_LENGTH = 50;
// Global feature switch; eligibility is additionally limited to clonal DNA SKUs below.
const AMINO_ACID_UPLOAD_ENABLED = true;
const LINE_ITEM_POLL_INTERVAL_MS = 10000;
const GLYCEROL_POLL_DELAY_MS = 3000;
const GLYCEROL_POLL_MAX_ATTEMPTS = 10;
const GLYCEROL_SYNC_DELAY_MS = 2500;
const GLYCEROL_SYNC_MAX_ATTEMPTS = 8;
const ANSA_CLONAL_DNA_SKU = "1002";
const ANSA_CLONAL_XL_SKUS = new Set(["6001", "6003"]);
const GENBANK_EXTENSIONS = [".gb", ".gbk", ".gbf", ".gbff", ".genbank"];
const SEQUENCE_UPLOAD_EXTENSIONS = [
  ".csv",
  ".fasta",
  ".fa",
  ".fna",
  ...GENBANK_EXTENSIONS
];
const GENBANK_MULTI_RECORD_ERROR = "Only one sequence per Genbank is allowed";
const GENBANK_EMPTY_SEQUENCE_ERROR =
  "No nucleotide sequence found in the Genbank file.";
const GENBANK_CONTIG_REFERENCE_ERROR =
  "This Genbank file references an external sequence (CONTIG) and does not include the nucleotide sequence. Please upload a Genbank file with an ORIGIN section.";

/** Prep Quantity options for the Scale Up config panel (Scale_Up_Quantity__c restricted picklist 1-5). */
const SCALE_UP_QUANTITY_OPTIONS = [
  { label: "1", value: "1" },
  { label: "2", value: "2" },
  { label: "3", value: "3" },
  { label: "4", value: "4" },
  { label: "5", value: "5" }
];

const QUOTE_PDF_FIELDS = [
  "ABT_Quote_Request__c.ABT_Requested_Date__c",
  "ABT_Quote_Request__c.ABT_Requester_Name__c",
  "ABT_Quote_Request__c.ABT_Expiration_Date__c",
  "ABT_Quote_Request__c.ABT_Total_Price__c",
  "ABT_Quote_Request__c.ABT_Quote__r.Subtotal",
  "ABT_Quote_Request__c.ABT_Quote__r.TotalPrice",
  "ABT_Quote_Request__c.Discount__c",
  "ABT_Quote_Request__c.ABT_Quote__r.GrandTotal",
  "ABT_Quote_Request__c.ABT_Quote__r.End_Customer_Subtotal__c",
  "ABT_Quote_Request__c.ABT_Quote__r.End_Customer_Total__c",
  "ABT_Quote_Request__c.ABT_Billing_Address_Lookup__r.Street",
  "ABT_Quote_Request__c.ABT_Billing_Address_Lookup__r.City",
  "ABT_Quote_Request__c.ABT_Billing_Address_Lookup__r.State",
  "ABT_Quote_Request__c.ABT_Billing_Address_Lookup__r.Country",
  "ABT_Quote_Request__c.ABT_Billing_Address_Lookup__r.PostalCode",
  "ABT_Quote_Request__c.ABT_Shipping_Address_Lookup__r.Street",
  "ABT_Quote_Request__c.ABT_Shipping_Address_Lookup__r.City",
  "ABT_Quote_Request__c.ABT_Shipping_Address_Lookup__r.State",
  "ABT_Quote_Request__c.ABT_Shipping_Address_Lookup__r.Country",
  "ABT_Quote_Request__c.ABT_Shipping_Address_Lookup__r.PostalCode",
  "ABT_Quote_Request__c.ABT_IncoTerms__c",
  "ABT_Quote_Request__c.ABT_Payment_Terms__c",
  "ABT_Quote_Request__c.ABT_Contact__r.Email",
  "ABT_Quote_Request__c.ABT_Account__r.Name",
  "ABT_Quote_Request__c.ABT_Account__r.Special_Agreement__c",
  "ABT_Quote_Request__c.Shipping_Amount__c",
  "ABT_Quote_Request__c.Invoice_Email__c",
  "ABT_Quote_Request__c.Ansa_Quote_Number__c",
  "ABT_Quote_Request__c.Delivery_Format__c",
  "ABT_Quote_Request__c.Yield__c"
];

function formatAddress(addr) {
  if (!addr) return "NA";
  const street = addr.Street?.value ?? addr.Street;
  const city = addr.City?.value ?? addr.City;
  const state = addr.State?.value ?? addr.State;
  const country = addr.Country?.value ?? addr.Country;
  const postal = addr.PostalCode?.value ?? addr.PostalCode;
  const parts = [street, city, state, country].filter(Boolean);
  if (!parts.length) return "NA";
  return `${parts.join(", ")}${postal ? ` - ${postal}` : ""}`;
}

function formatMoney(value) {
  if (value == null || value === "" || Number.isNaN(Number(value))) return "NA";
  return Number(value).toFixed(2);
}

function pdfTermsLinkParts(raw) {
  const text = String(raw || "")
    .replace(/<[^>]*>/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  const match = text.match(/https?:\/\/[^\s]+/i);
  if (!match) {
    return { before: text, url: "", after: "" };
  }
  const rawUrl = match[0];
  const punct = (rawUrl.match(/[.,;:]+$/) || [""])[0];
  const url = punct ? rawUrl.slice(0, -punct.length) : rawUrl;
  return {
    before: text.slice(0, match.index),
    url,
    after: punct + text.slice(match.index + rawUrl.length)
  };
}

export default class AbtNewQuote extends NavigationMixin(LightningElement) {
  @api productId;
  @api productName;
  @api restoreData;

  @track currentStep = 1;
  totalSteps = 4;
  @track quoteId = "";
  @track currentQuoteRequestId = null;
  @track isLoadingModalData = false;
  @track isProcessing = false;
  wiredSalesLineItemsResult;
  _salesFees = salesFeesFromQuoteLineItems([]);

  // Step 1
  @track existingProjects = [];
  @track selectedExistingProject = "";
  @track newProjectName = "";
  @track vectorOptions = [];
  @track selectedVector = "";
  /** Contact.Default_Vector__c — used to prefill Step 1 / uploaded sequences for clonal products */
  defaultVectorId = null;
  @track isScaleUpProductEnabled = false;
  @track isGlycerol = false;
  @track isGlycerolStockEnabled = false;
  @track isVectorProductEnabled = false;
  @track productSku = "";

  // Step 2
  @track uploadedSequenceFiles = [];
  @track aminoFileName = "";
  @track isCodonMode = false;
  aminoFile = null;
  @track showStep2ValidationError = false;
  @track step2UploadErrorMessage = "";
  @track codonOptimizationFailures = [];
  @track codonOptimizationWarnings = [];

  // Step 3/4 sequences
  @track _sequences = [];
  /** Trailing inline-add rows (spreadsheet-style empty row at bottom of Sequences table). */
  @track _draftRows = [];
  /** Debounce timers for draft-row validation display (draftId → timeoutId). */
  _draftValidationTimers = new Map();
  /** Draft name/sequence errors wait until the user clicks Next. */
  _submittedDraftValidation = false;
  /** Serializes draft→Salesforce creates so concurrent pastes cannot overwrite `_sequences`. */
  _draftCommitTail = Promise.resolve();

  // Step 4
  @track packagingType = "";
  @track packagingOptions = [];
  @track scaleUpBufferOptions = [];
  @track scaleUpNormalizationOptions = [];
  @track _scaleUpBufferDefault = SCALE_UP_DEFAULT_BUFFER;
  _packagingPicklistWireData;
  _packagingRestoreValue;

  // Edit Sequence Modal
  @track showManualInputModal = false;
  @track sequenceName = "";
  @track sequenceVector = "";
  @track sequenceText = "";
  @track sequenceError = "";
  @track sequenceNameError = "";
  @track sequenceVectorError = "";
  @track sequenceCharCount = 0;
  @track editingSequenceId = null;
  @track feasibilityOriginalSequence = "";
  @track editingFeasibilityJson = "";
  @track editingFeasibilityExplained1 = "";
  @track editingFeasibilityExplained2 = "";
  @track editingFeasibilityExplained3 = "";
  @track isModalSaveInProgress = false;
  @track _glycerolUpdatingIds = [];
  @track _deletingSequenceIds = [];
  @track _reflexPopoverLineId = null;
  @track _scaleUpPopoverLineId = null;
  @track _scaleUpDefinitionsOpen = false;
  @track _homopolymerAckOpen = false;
  @track homopolymerAckSequenceNames = [];
  _homopolymerAcknowledged = false;
  @track _scaleUpUpdatingIds = [];
  @track _scaleUpSavingIds = [];
  @track bulkVectorValue = "";
  @track bulkReflexChecked = false;
  @track bulkToxicChecked = false;
  @track bulkGlycerolChecked = false;
  @track _bulkUpdateCount = 0;
  @track sequenceLengthLimits = { min: 200, max: 600 };
  @track allowedSequenceCharacters = DEFAULT_ALLOWED_SEQUENCE_CHARACTERS;

  /** Poll until linked Quote exists and Ansa_Quote_Number__c replaces auto-number Name (QR-######). */
  _quoteDisplayPollTimer = null;
  _quoteDisplayPollAttempts = 0;
  _lineItemPollingTimer = null;
  _pendingGlycerolApplyIds = new Set();
  _deferredGlycerolApplyInFlight = false;
  _scaleUpClearInFlightIds = new Set();
  _editOriginalSnapshot = null;
  _wasFeasibilityPending = undefined;
  _localIdCounter = 0;

  // Mini-Game Modal (Helix Rush while feasibility is calculated)
  @track isGameModalOpen = false;
  @track gameStartTimestamp = null;
  @track progressPercentage = 0;
  progressTimer = null;
  gameResourceUrl = ABT_MiniGame;

  // User info
  currentUserId = userId;
  @track currentAccountId = "";
  currentAccountIsIdtChannelPartner = false;
  @track currentContactId = "";
  @track quoteRequestInfo = {};
  wiredPdfRecordResult;
  ansaLogo = ABT_Ansa_Logo;

  @wire(getObjectInfo, { objectApiName: QUOTE_REQUEST_OBJECT })
  quoteRequestObjectInfo;

  @wire(getObjectInfo, { objectApiName: QUOTE_REQUEST_LINE_ITEM_OBJECT })
  quoteRequestLineItemObjectInfo;

  @wire(getPicklistValues, {
    recordTypeId: "$quoteRequestObjectInfo.data.defaultRecordTypeId",
    fieldApiName: REQUEST_PACKAGING_FIELD
  })
  wiredPackagingPicklist({ data, error }) {
    if (data) {
      this._packagingPicklistWireData = data;
      this.packagingOptions = formatPackagingPicklistOptions(data);
      this._syncPackagingSelection();
    } else if (error) {
      console.error("Error loading packaging picklist:", error);
    }
  }

  @wire(getPicklistValues, {
    recordTypeId: "$quoteRequestLineItemObjectInfo.data.defaultRecordTypeId",
    fieldApiName: SCALE_UP_BUFFER_FIELD
  })
  wiredScaleUpBufferPicklist({ data, error }) {
    if (data) {
      this.scaleUpBufferOptions = (data.values || []).map((opt) => ({
        label: opt.label,
        value: opt.value
      }));
      if (data.defaultValue?.value) {
        this._scaleUpBufferDefault = data.defaultValue.value;
      }
    } else if (error) {
      console.error("Error loading Scale Up Buffer picklist:", error);
    }
  }

  @wire(getPicklistValues, {
    recordTypeId: "$quoteRequestLineItemObjectInfo.data.defaultRecordTypeId",
    fieldApiName: SCALE_UP_NORMALIZATION_FIELD
  })
  wiredScaleUpNormalizationPicklist({ data, error }) {
    if (data) {
      this.scaleUpNormalizationOptions = (data.values || []).map((opt) => ({
        label: opt.label,
        value: opt.value
      }));
    } else if (error) {
      console.error("Error loading Scale Up Normalization picklist:", error);
    }
  }

  @wire(getRecord, {
    recordId: "$currentQuoteRequestId",
    fields: QUOTE_PDF_FIELDS
  })
  wiredPdfRecord(value) {
    this.wiredPdfRecordResult = value;
    const { data } = value;
    if (!data) return;

    const f = data.fields;
    const quoteRel = f.ABT_Quote__r?.value;
    const quoteFields = quoteRel?.fields;
    const discountValue = f.Discount__c?.value;
    const accountRel = f.ABT_Account__r?.value;
    const accountFields = accountRel?.fields;
    const specialAgreement =
      accountFields?.Special_Agreement__c?.value || pdfTerms;
    const termsParts = pdfTermsLinkParts(specialAgreement);

    this.quoteRequestInfo = {
      contactName: f.ABT_Requester_Name__c?.value || "NA",
      createdDate: f.ABT_Requested_Date__c?.displayValue || "NA",
      expiryDate: f.ABT_Expiration_Date__c?.displayValue || "NA",
      totalPrice: formatMoney(
        quoteFields?.GrandTotal?.value ??
          quoteFields?.TotalPrice?.value ??
          f.ABT_Total_Price__c?.value
      ),
      quoteNumber: f.Ansa_Quote_Number__c?.value || this.quoteId || "NA",
      subTotal: formatMoney(
        quoteFields?.TotalPrice?.value ?? quoteFields?.Subtotal?.value
      ),
      formattedDiscount:
        discountValue > 0 ? `-$${formatMoney(discountValue)}` : null,
      contactEmail: f.ABT_Contact__r?.value?.fields?.Email?.value || "NA",
      billTo: formatAddress(f.ABT_Billing_Address_Lookup__r?.value?.fields),
      shipTo: formatAddress(f.ABT_Shipping_Address_Lookup__r?.value?.fields),
      paymentTerms: f.ABT_Payment_Terms__c?.value || "NA",
      incoTerms: f.ABT_IncoTerms__c?.value || "NA",
      accountName: accountFields?.Name?.value || "NA",
      invoiceEmail: f.Invoice_Email__c?.value || "NA",
      shippingAmount: formatMoney(f.Shipping_Amount__c?.value),
      specialAgreement,
      specialAgreementBeforeUrl: termsParts.before,
      specialAgreementUrl: termsParts.url,
      specialAgreementAfterUrl: termsParts.after,
      endCustomerSubtotal: formatMoney(
        quoteFields?.End_Customer_Subtotal__c?.value
      ),
      endCustomerTotal: formatMoney(quoteFields?.End_Customer_Total__c?.value),
      deliveryFormat: f.Delivery_Format__c?.value || "NA",
      yield: f.Yield__c?.value || "NA"
    };
  }

  @wire(getQuoteRequestSalesLineItems, {
    quoteRequestId: "$currentQuoteRequestId"
  })
  wiredSalesLineItems(value) {
    this.wiredSalesLineItemsResult = value;
    const { data, error } = value;
    if (data) {
      this._salesFees = salesFeesFromQuoteLineItems(data);
      this._applySalesFeesToSequences();
    } else if (error && this.currentQuoteRequestId) {
      console.error("Error loading quote sales line items:", error);
    }
  }

  connectedCallback() {
    this._boundCloseReflexPopover =
      this._closeOpenPopoversOnOutsideClick.bind(this);
    document.addEventListener("click", this._boundCloseReflexPopover, true);
    // If restoreData is provided (coming back from cart), restore state
    if (
      this.restoreData &&
      (this.restoreData.quoteRequestId || this.restoreData.quoteId)
    ) {
      this.currentQuoteRequestId = this.restoreData.quoteRequestId || null;
      this.quoteId = "";
      this._sequences = this.restoreData.sequences || [];
      this.selectedExistingProject = this.restoreData.projectName || "";
      this.newProjectName = this.restoreData.newProjectName || "";
      this.selectedVector = this.restoreData.vectorId || "";
      this.isGlycerol = this.restoreData.isGlycerol || false;
      this._packagingRestoreValue = this.restoreData.packagingType || "";
      this.currentStep = 1;
      if (this.currentQuoteRequestId) {
        getQuoteRequestDisplayQuoteNumber({
          quoteRequestId: this.currentQuoteRequestId
        })
          .then((v) => {
            if (v) this.quoteId = v;
          })
          .catch(() => {
            if (this.restoreData.quoteId)
              this.quoteId = this.restoreData.quoteId;
          })
          .finally(() => this._startQuoteDisplayPolling());
      } else if (this.restoreData.quoteId) {
        this.quoteId = this.restoreData.quoteId;
      }
    } else {
      this.quoteId = "";
    }
    this._startPollingForPendingLineItems();
    this.loadModalData();
    this._ensureTrailingEmptyDraftRow();

    const savedTimestamp = this.loadGameTimestamp();
    if (savedTimestamp) {
      this.gameStartTimestamp = savedTimestamp;
    }
    this._applyFeasibilityGameState();
  }

  sequenceRecordFromRow(row) {
    return row?.Related_Sequence__r || null;
  }

  sequenceNameFromRow(row) {
    return portalSequenceNameFromRow(row);
  }

  sequenceTextFromRow(row) {
    return portalSequenceTextFromRow(row);
  }

  normalizeFeasibilityFromRow(row, quoteLineItem) {
    return portalNormalizeFeasibilityFromRow(row, quoteLineItem);
  }

  normalizeComplexityFromRow(row) {
    return portalNormalizeComplexityFromRow(row);
  }

  normalizeTotalPriceFromRow(row) {
    const totalPriceValue = row?.ABT_Total_Price__c;
    const parsedPrice = Number(totalPriceValue);
    if (Number.isFinite(parsedPrice) && parsedPrice > 0) {
      return `$${parsedPrice.toFixed(2)}`;
    }
    return undefined;
  }

  _salesFeesForRow(row, seq = {}) {
    return salesFeesForQuoteRequestLine(row, this._salesFees, seq);
  }

  _applySalesFeesToSequences() {
    if (!(this._sequences || []).length) {
      return;
    }
    this._sequences = this._sequences.map((seq) => {
      const row = {
        Id: seq.id,
        ABT_Quote_Line_Item__c: seq.quoteLineItemId,
        ABT_Total_Price__c: seq.basePrice,
        Related_Sequence__r: { Sequence_Name__c: seq.name }
      };
      const extras = this._pricingExtrasFromLineItem(row, seq);
      const merged = { ...seq, ...extras };
      return {
        ...merged,
        totalPrice: this._recalculateSequenceTotal(merged)
      };
    });
  }

  _refreshSalesLineItems() {
    if (this.wiredSalesLineItemsResult) {
      return refreshApex(this.wiredSalesLineItemsResult);
    }
    return Promise.resolve();
  }

  _hasGlycerolFeeIntent(seq = {}) {
    return (
      seq.glycerol === true ||
      (seq.scaleUpSelected === true && seq.scaleUpGlycerolStock === true)
    );
  }

  _parseFeeAmount(value) {
    return (
      parseFloat(
        String(value || "0")
          .replace("$", "")
          .replace(",", "")
          .replace("NA", "0")
      ) || 0
    );
  }

  _recalculateSequenceTotal(seq = {}) {
    const base = Number(seq.basePrice);
    const scaleUp =
      seq.scaleUpSelected === true ? this._parseFeeAmount(seq.scaleUpFee) : 0;
    const glycerol = this._hasGlycerolFeeIntent(seq)
      ? this._parseFeeAmount(this._effectiveGlycerolFee(seq))
      : 0;
    if (Number.isFinite(base) && base >= 0) {
      return `$${(base + scaleUp + glycerol).toFixed(2)}`;
    }
    const current = this._parseFeeAmount(seq.totalPrice);
    return `$${Math.max(0, current).toFixed(2)}`;
  }

  _sequenceTotalPriceFromRow(row, seq = {}) {
    const includeGlycerol = this._hasGlycerolFeeIntent(seq);
    const base = Number(row?.ABT_Total_Price__c);
    const sales = this._salesFeesForRow(row, seq);
    const scaleUp = seq.scaleUpSelected === true ? sales.scaleUp : 0;
    const glycFee = includeGlycerol ? sales.glycerol : 0;

    if (Number.isFinite(base) && base >= 0) {
      return `$${(base + scaleUp + glycFee).toFixed(2)}`;
    }
    return seq.totalPrice || "$0.00";
  }

  _adjustTotalPriceForGlycerolToggle(seq, enabled, feeAmount) {
    const current =
      parseFloat((seq.totalPrice || "$0").replace("$", "").replace(",", "")) ||
      0;
    const fee =
      feeAmount != null
        ? Number(feeAmount)
        : parseFloat(
            (seq.glycerolFee || "$0").replace("$", "").replace("NA", "0")
          ) || 0;
    if (!Number.isFinite(fee) || fee <= 0) {
      return seq.totalPrice || "$0.00";
    }
    const adjusted = enabled ? current + fee : Math.max(0, current - fee);
    return `$${adjusted.toFixed(2)}`;
  }

  _isFeasibilityPending(seq) {
    const f = (seq?.feasibility || "").trim();
    return !f || f.toLowerCase() === "pending";
  }

  _isComplexityPending(seq) {
    const c = (seq?.complexity || "").trim();
    return !c || c.toLowerCase() === "pending";
  }

  _isAsEarlyAsDatePending(seq) {
    return !seq?.asEarlyAsDate;
  }

  _isGuaranteedDatePending(seq) {
    return !seq?.guaranteedDate;
  }

  _formatGlycerolFee(price) {
    if (price == null || price === "") {
      return null;
    }
    const parsed = Number(price);
    if (!Number.isFinite(parsed) || parsed <= 0) {
      return null;
    }
    return `$${parsed.toFixed(2)}`;
  }

  _resolveGlycerolFeeFromLineItem(row, glycerol, seq = {}) {
    if (!glycerol) {
      return null;
    }
    const sales = this._salesFeesForRow(row, seq);
    return this._formatGlycerolFee(sales.glycerol);
  }

  _effectiveGlycerolFee(seq = {}) {
    if (!this._hasGlycerolFeeIntent(seq)) {
      return null;
    }
    if (seq.glycerolFee) {
      const parsedFee = this._parseFeeAmount(seq.glycerolFee);
      if (parsedFee > 0) {
        return seq.glycerolFee;
      }
    }
    return this._resolveGlycerolFeeFromLineItem(
      {
        Id: seq.id,
        ABT_Quote_Line_Item__c: seq.quoteLineItemId,
        Related_Sequence__r: { Sequence_Name__c: seq.name }
      },
      true,
      seq
    );
  }

  _sequenceForFeeDisplay(seq = {}) {
    return {
      ...seq,
      glycerolFee: this._effectiveGlycerolFee(seq)
    };
  }

  _formatCurrencyFee(price) {
    const parsed = Number(price);
    if (!Number.isFinite(parsed) || parsed <= 0) {
      return null;
    }
    return `$${parsed.toFixed(2)}`;
  }

  _endCustomerPriceFromRow(row) {
    const price = row?.ABT_Quote_Line_Item__r?.End_Customer_List_Price__c;
    if (price == null || price === "" || Number.isNaN(Number(price))) {
      return null;
    }
    return Number(price).toFixed(2);
  }

  _sumAdditionalFees(seq = {}) {
    if (!this.showAddlFeesSelection) {
      return 0;
    }
    const scaleUp =
      seq.scaleUpSelected === true ? this._parseFeeAmount(seq.scaleUpFee) : 0;
    const glycerol = this._parseFeeAmount(this._effectiveGlycerolFee(seq));
    return scaleUp + glycerol;
  }

  _effectiveGlycerolStock(checked) {
    return (
      this.showGlycerolSelection &&
      this.isGlycerolApplicable &&
      checked === true
    );
  }

  /** Glycerol is applied after classification on step 4 — never on initial line-item insert. */
  _serverGlycerolStockOnCreate() {
    return false;
  }

  _queueGlycerolApplyForLineItem(lineItemId, seq) {
    if (
      !lineItemId ||
      !this.showGlycerolSelection ||
      !this._effectiveGlycerolStock(seq?.glycerol)
    ) {
      return;
    }
    this._pendingGlycerolApplyIds.add(String(lineItemId));
  }

  _queueStep4GlycerolApply() {
    if (!this.showGlycerolSelection) {
      return;
    }
    (this._sequences || []).forEach((seq) => {
      if (seq.savedToSalesforce && this._effectiveGlycerolStock(seq.glycerol)) {
        this._pendingGlycerolApplyIds.add(String(seq.id));
      }
    });
  }

  _applyPendingGlycerolIfReady() {
    if (
      !this._pendingGlycerolApplyIds?.size ||
      this._deferredGlycerolApplyInFlight
    ) {
      return Promise.resolve();
    }

    this._deferredGlycerolApplyInFlight = true;
    const lineItemIds = [...this._pendingGlycerolApplyIds];
    this._pendingGlycerolApplyIds = new Set();
    lineItemIds.forEach((lineItemId) => this._addGlycerolUpdating(lineItemId));

    return this._bulkApplyGlycerolWithRetry(lineItemIds, true, 0).finally(
      () => {
        lineItemIds.forEach((lineItemId) =>
          this._removeGlycerolUpdating(lineItemId)
        );
        this._deferredGlycerolApplyInFlight = false;
        if (this._pendingGlycerolApplyIds?.size) {
          this._applyPendingGlycerolIfReady();
        }
      }
    );
  }

  // One bulk Apex call with lock retry so default glycerol does not fire N parallel QLI updates.
  _bulkApplyGlycerolWithRetry(lineItemIds, glycerolStock, attempt = 0) {
    if (!lineItemIds?.length) {
      return Promise.resolve();
    }
    return bulkUpdateQuoteRequestLineItemGlycerol({
      lineItemIds,
      glycerolStockFlags: lineItemIds.map(() => glycerolStock === true)
    })
      .then((result) => {
        if (!result?.success) {
          if (result?.retryable && attempt < GLYCEROL_SYNC_MAX_ATTEMPTS) {
            return new Promise((resolve) => {
              // eslint-disable-next-line @lwc/lwc/no-async-operation
              setTimeout(() => {
                resolve(
                  this._bulkApplyGlycerolWithRetry(
                    lineItemIds,
                    glycerolStock,
                    attempt + 1
                  )
                );
              }, GLYCEROL_SYNC_DELAY_MS);
            });
          }
          throw new Error(result?.error || "Glycerol update failed");
        }
        const byId = new Map(
          (result.lines || []).map((line) => [String(line.id), line])
        );
        this._sequences = this._sequences.map((seq) => {
          const line = byId.get(String(seq.id));
          if (!line) {
            return seq;
          }
          const fee = this._formatGlycerolFee(line.glycerolPrice);
          return this._withAdditionalFees({
            ...seq,
            glycerol: line.glycerolStock === true,
            glycerolFee: fee ?? (glycerolStock ? seq.glycerolFee : null)
          });
        });
        return Promise.all(
          lineItemIds.map((lineItemId) =>
            this._pollLineItemPricingUntilGlycerolSettled(lineItemId)
          )
        );
      })
      .catch((err) => {
        if (
          this._isRetryableGlycerolError(err) &&
          attempt < GLYCEROL_SYNC_MAX_ATTEMPTS
        ) {
          return new Promise((resolve) => {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
              resolve(
                this._bulkApplyGlycerolWithRetry(
                  lineItemIds,
                  glycerolStock,
                  attempt + 1
                )
              );
            }, GLYCEROL_SYNC_DELAY_MS);
          });
        }
        console.error("Deferred glycerol apply failed:", err);
        return Promise.resolve();
      });
  }

  _isRetryableGlycerolError(err) {
    const message = String(
      err?.message ||
        err?.body?.message ||
        err?.body?.pageErrors?.[0]?.message ||
        ""
    );
    return message.includes("UNABLE_TO_LOCK_ROW");
  }

  _applyGlycerolToLineItemWithRetry(lineItemId, attempt = 0) {
    return getLineItemPricing({ lineItemId })
      .then((li) => {
        if (!li?.ABT_Quote_Line_Item__c) {
          if (attempt < GLYCEROL_SYNC_MAX_ATTEMPTS) {
            return new Promise((resolve) => {
              // eslint-disable-next-line @lwc/lwc/no-async-operation
              setTimeout(() => {
                resolve(
                  this._applyGlycerolToLineItemWithRetry(
                    lineItemId,
                    attempt + 1
                  )
                );
              }, GLYCEROL_SYNC_DELAY_MS);
            });
          }
          return Promise.resolve();
        }
        if (li.Glycerol_Stock__c === true) {
          const glycerolPrice = Number(li.Glycerol_Price__c) || 0;
          if (glycerolPrice > 0) {
            return this._pollLineItemPricingUntilGlycerolSettled(lineItemId);
          }
        }
        this._addGlycerolUpdating(lineItemId);
        return updateQuoteRequestLineItemGlycerol({
          lineItemId,
          glycerolStock: true
        })
          .then((result) => {
            if (!result?.success) {
              if (result?.retryable && attempt < GLYCEROL_SYNC_MAX_ATTEMPTS) {
                return new Promise((resolve) => {
                  // eslint-disable-next-line @lwc/lwc/no-async-operation
                  setTimeout(() => {
                    resolve(
                      this._applyGlycerolToLineItemWithRetry(
                        lineItemId,
                        attempt + 1
                      )
                    );
                  }, GLYCEROL_SYNC_DELAY_MS);
                });
              }
              return Promise.reject(
                new Error(result?.error || "Glycerol apply failed")
              );
            }
            const fee = this._formatGlycerolFee(result.glycerolPrice);
            this._sequences = this._sequences.map((s) =>
              String(s.id) === String(lineItemId)
                ? this._withAdditionalFees({
                    ...s,
                    glycerol: result.glycerolStock === true,
                    glycerolFee: fee ?? s.glycerolFee
                  })
                : s
            );
            return this._pollLineItemPricingUntilGlycerolSettled(lineItemId);
          })
          .finally(() => {
            this._removeGlycerolUpdating(lineItemId);
          })
          .catch((err) => {
            if (
              this._isRetryableGlycerolError(err) &&
              attempt < GLYCEROL_SYNC_MAX_ATTEMPTS
            ) {
              return new Promise((resolve) => {
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => {
                  resolve(
                    this._applyGlycerolToLineItemWithRetry(
                      lineItemId,
                      attempt + 1
                    )
                  );
                }, GLYCEROL_SYNC_DELAY_MS);
              });
            }
            console.error("Deferred glycerol apply failed:", err);
          });
      })
      .catch(() => {
        if (attempt < GLYCEROL_SYNC_MAX_ATTEMPTS) {
          return new Promise((resolve) => {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
              resolve(
                this._applyGlycerolToLineItemWithRetry(lineItemId, attempt + 1)
              );
            }, GLYCEROL_SYNC_DELAY_MS);
          });
        }
        return Promise.resolve();
      });
  }

  _formatAdditionalFeesDisplay(seq = {}) {
    const sum = this._sumAdditionalFees(seq);
    return sum > 0 ? `$${sum.toFixed(2)}` : "NA";
  }

  _glycerolFieldsFromLineItemWithLocalState(li, seq = {}) {
    if (this._isGlycerolUpdatingLine(seq.id)) {
      const hasFeeIntent =
        seq.glycerol === true || seq.scaleUpGlycerolStock === true;
      return {
        glycerol: seq.glycerol === true,
        glycerolFee: hasFeeIntent ? (seq.glycerolFee ?? null) : null
      };
    }
    const serverGlycerol = li?.Glycerol_Stock__c === true;
    const localGlycerol = seq.glycerol === true;
    const localGlycerolExplicit = typeof seq.glycerol === "boolean";
    if (localGlycerolExplicit && serverGlycerol !== localGlycerol) {
      const hasFeeIntent =
        localGlycerol ||
        seq.scaleUpGlycerolStock === true ||
        li?.Scale_Up_Glycerol_Stock__c === true;
      return {
        glycerol: localGlycerol,
        glycerolFee: hasFeeIntent ? (seq.glycerolFee ?? null) : null
      };
    }
    return this._glycerolFieldsFromLineItem(li, seq);
  }

  _applyAccountDefaultGlycerol(accountDefaultGlycerol) {
    if (this.restoreData && this.restoreData.isGlycerol != null) {
      return;
    }
    if (
      accountDefaultGlycerol === true &&
      this.showGlycerolSelection &&
      this.isGlycerolApplicable
    ) {
      this.isGlycerol = true;
    }
  }

  /** Step 1 vector used for new/empty sequence rows (`none` → blank). */
  _effectiveSelectedVector() {
    if (!this.showVectorSelection) {
      return "";
    }
    const v = this.selectedVector;
    if (!v || v === "none") {
      return "";
    }
    return v;
  }

  /**
   * Empty draft rows follow Step 1 selection so Contact default is overridden
   * when the user changes the upload-screen vector.
   */
  _syncEmptyDraftVectorsFromSelection() {
    const vector = this._effectiveSelectedVector();
    this._draftRows = (this._draftRows || []).map((row) => {
      if (this._isDraftRowEmpty(row) && !row.isSaving) {
        return { ...row, vector };
      }
      return row;
    });
  }

  /**
   * Prefill Contact.Default_Vector__c for clonal (vector-enabled) products when Step 1
   * has no vector selected yet. Does not override an explicit upload-screen selection
   * or a restored quote vector.
   */
  _applyContactDefaultVector(defaultVectorId) {
    this.defaultVectorId = defaultVectorId || null;
    if (!this.showVectorSelection || !this.defaultVectorId) {
      return;
    }
    if (this.restoreData && this.restoreData.vectorId) {
      return;
    }
    if (this.selectedVector && this.selectedVector !== "none") {
      return;
    }
    const isAvailable = (this.vectorOptions || []).some(
      (opt) => opt.value === this.defaultVectorId
    );
    if (!isAvailable) {
      return;
    }
    this.selectedVector = this.defaultVectorId;
    this._syncEmptyDraftVectorsFromSelection();
  }

  /** Empty Scale Up UI state used when the checkbox is cleared. */
  _clearedScaleUpUiFields() {
    return {
      scaleUpSelected: false,
      scaleUpQuantity: "",
      scaleUpGlycerolStock: false,
      scaleUpBuffer: "",
      scaleUpNormalization: "",
      scaleUpEndotoxinFree: false,
      scaleUpAnimalFree: false,
      scaleUpMass: "",
      scaleUpPriceDisplay: "",
      scaleUpLeadTime: "",
      scaleUpFee: null
    };
  }

  _pricingExtrasFromLineItem(li, seq = {}) {
    const scaleUpFields = this._scaleUpFieldsFromLineItem(li, seq);
    const sales = this._salesFeesForRow(li, { ...seq, ...scaleUpFields });
    const scaleUpFee =
      scaleUpFields.scaleUpSelected === true
        ? this._formatCurrencyFee(sales.scaleUp)
        : null;
    const glycerolFields = this._glycerolFieldsFromLineItemWithLocalState(li, {
      ...seq,
      ...scaleUpFields
    });
    const merged = { ...seq, scaleUpFee, ...glycerolFields, ...scaleUpFields };
    return {
      scaleUpFee,
      ...glycerolFields,
      ...scaleUpFields,
      additionalFees: this._formatAdditionalFeesDisplay(merged)
    };
  }

  /** Maps Scale Up config fields from a line item, preserving local state when the field wasn't queried. */
  _scaleUpFieldsFromLineItem(li, seq = {}) {
    const has = (v) => v !== undefined && v !== null;
    const lineId = String(seq.id || li?.Id || "");
    // Local clear in flight — don't revive Scale Up from a stale SF read.
    if (lineId && this._scaleUpClearInFlightIds?.has(lineId)) {
      return this._clearedScaleUpUiFields();
    }
    // Explicit local uncheck must stick — glycerol polls / SF lag must not re-check Scale Up.
    if (seq.scaleUpSelected === false) {
      return this._clearedScaleUpUiFields();
    }
    // Explicit false from Salesforce means clear everything — null fields are often omitted
    // from Apex/wire payloads and must not reinstate the previous local configuration.
    if (has(li?.Scale_Up_Selected__c) && li.Scale_Up_Selected__c !== true) {
      return this._clearedScaleUpUiFields();
    }
    // Local UI already cleared; keep it cleared when SF Selected isn't explicitly true.
    if (
      seq.scaleUpSelected !== true &&
      (!has(li?.Scale_Up_Selected__c) || li.Scale_Up_Selected__c !== true)
    ) {
      return this._clearedScaleUpUiFields();
    }
    const qli = li?.ABT_Quote_Line_Item__r;
    const mass = has(li?.Scale_Up_Mass__c)
      ? li.Scale_Up_Mass__c
      : has(qli?.Scale_Up_Mass__c)
        ? qli.Scale_Up_Mass__c
        : undefined;
    const price = has(li?.Scale_Up_Price__c)
      ? li.Scale_Up_Price__c
      : has(qli?.Scale_Up_Price__c)
        ? qli.Scale_Up_Price__c
        : undefined;
    const leadTime = has(li?.Scale_Up_Lead_Time__c)
      ? li.Scale_Up_Lead_Time__c
      : has(qli?.Scale_Up_Lead_Time__c)
        ? qli.Scale_Up_Lead_Time__c
        : undefined;
    return {
      scaleUpSelected: has(li?.Scale_Up_Selected__c)
        ? li.Scale_Up_Selected__c === true
        : seq.scaleUpSelected === true,
      scaleUpQuantity: has(li?.Scale_Up_Quantity__c)
        ? String(li.Scale_Up_Quantity__c)
        : seq.scaleUpQuantity || "",
      scaleUpGlycerolStock: has(li?.Scale_Up_Glycerol_Stock__c)
        ? li.Scale_Up_Glycerol_Stock__c === true
        : seq.scaleUpGlycerolStock === true,
      scaleUpBuffer: has(li?.Scale_Up_Buffer__c)
        ? li.Scale_Up_Buffer__c || ""
        : seq.scaleUpBuffer || "",
      scaleUpNormalization: has(li?.Scale_Up_Normalization__c)
        ? fromScaleUpNormalizationApiValue(li.Scale_Up_Normalization__c)
        : seq.scaleUpNormalization || "",
      scaleUpEndotoxinFree: has(li?.Scale_Up_Endotoxin_Free__c)
        ? li.Scale_Up_Endotoxin_Free__c === true
        : seq.scaleUpEndotoxinFree === true,
      scaleUpAnimalFree: has(li?.Scale_Up_Animal_Free__c)
        ? li.Scale_Up_Animal_Free__c === true
        : seq.scaleUpAnimalFree === true,
      scaleUpMass: has(mass) ? mass || "" : seq.scaleUpMass || "",
      scaleUpPriceDisplay:
        this._formatCurrencyFee(this._salesFeesForRow(li, seq).scaleUp) ||
        this._formatCurrencyFee(price) ||
        seq.scaleUpPriceDisplay ||
        "",
      scaleUpLeadTime: has(leadTime)
        ? leadTime || ""
        : seq.scaleUpLeadTime || ""
    };
  }

  _withAdditionalFees(seq) {
    return {
      ...seq,
      additionalFees: this._formatAdditionalFeesDisplay(seq)
    };
  }

  _addGlycerolUpdating(lineItemId) {
    const key = String(lineItemId);
    if (!this._glycerolUpdatingIds.includes(key)) {
      this._glycerolUpdatingIds = [...this._glycerolUpdatingIds, key];
    }
  }

  _removeGlycerolUpdating(lineItemId) {
    const key = String(lineItemId);
    this._glycerolUpdatingIds = this._glycerolUpdatingIds.filter(
      (id) => id !== key
    );
  }

  _isGlycerolUpdatingLine(lineItemId) {
    return this._glycerolUpdatingIds.includes(String(lineItemId));
  }

  _addDeletingSequence(lineItemId) {
    const key = String(lineItemId);
    if (!this._deletingSequenceIds.includes(key)) {
      this._deletingSequenceIds = [...this._deletingSequenceIds, key];
    }
  }

  _removeDeletingSequence(lineItemId) {
    const key = String(lineItemId);
    this._deletingSequenceIds = this._deletingSequenceIds.filter(
      (id) => id !== key
    );
  }

  _isDeletingSequence(lineItemId) {
    return (this._deletingSequenceIds || []).includes(String(lineItemId));
  }

  _addScaleUpUpdating(lineItemId) {
    const key = String(lineItemId);
    if (!this._scaleUpUpdatingIds.includes(key)) {
      this._scaleUpUpdatingIds = [...this._scaleUpUpdatingIds, key];
    }
  }

  _removeScaleUpUpdating(lineItemId) {
    const key = String(lineItemId);
    this._scaleUpUpdatingIds = this._scaleUpUpdatingIds.filter(
      (id) => id !== key
    );
  }

  _isScaleUpUpdatingLine(lineItemId) {
    return this._scaleUpUpdatingIds.includes(String(lineItemId));
  }

  _addScaleUpSaving(lineItemId) {
    const key = String(lineItemId);
    if (!this._scaleUpSavingIds.includes(key)) {
      this._scaleUpSavingIds = [...this._scaleUpSavingIds, key];
    }
  }

  _removeScaleUpSaving(lineItemId) {
    const key = String(lineItemId);
    this._scaleUpSavingIds = this._scaleUpSavingIds.filter((id) => id !== key);
  }

  _isScaleUpSavingLine(lineItemId) {
    return this._scaleUpSavingIds.includes(String(lineItemId));
  }

  _vectorOptionForId(vectorId) {
    if (!vectorId || vectorId === "none") {
      return null;
    }
    return (
      (this.vectorOptions || []).find((opt) => opt.value === vectorId) || null
    );
  }

  _isReflexApplicableVector(vectorId) {
    return this._vectorOptionForId(vectorId)?.reflexApplicable === true;
  }

  _copyNumberForVector(vectorId) {
    return this._vectorOptionForId(vectorId)?.copyNumber || "";
  }

  _isEventInsideOpenPopover(event) {
    const path =
      typeof event.composedPath === "function" ? event.composedPath() : [];
    return path.some((node) => {
      if (!node || !node.tagName) {
        return false;
      }
      const tag = node.tagName.toUpperCase();
      if (tag === "C-ABT-SCALE-UP-CONFIG" && this._scaleUpPopoverLineId) {
        return true;
      }
      if (tag === "C-ABT-REFLEX-VECTOR-OPT-IN" && this._reflexPopoverLineId) {
        return true;
      }
      if (
        tag === "C-ABT-SCALE-UP-DEFINITIONS-MODAL" &&
        this._scaleUpDefinitionsOpen
      ) {
        return true;
      }
      return false;
    });
  }

  /** Close open popovers on outside click; swallow the click so delete/select don't also fire. */
  _closeOpenPopoversOnOutsideClick(event) {
    if (!this._reflexPopoverLineId && !this._scaleUpPopoverLineId) {
      return;
    }
    if (this._isEventInsideOpenPopover(event)) {
      return;
    }
    this._reflexPopoverLineId = null;
    this._scaleUpPopoverLineId = null;
    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();
  }

  _closeReflexPopover() {
    this._reflexPopoverLineId = null;
    this._scaleUpPopoverLineId = null;
  }

  _openReflexPopoverForLine(lineId) {
    // Defer so the reflex icon renders before the popover opens.
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(() => {
      this._reflexPopoverLineId = String(lineId);
    }, 0);
  }

  _clearReflexOptInForSequence(id, previous) {
    if (!previous?.reflexVectorOptIn) {
      return Promise.resolve();
    }
    this._sequences = this._sequences.map((seq) =>
      String(seq.id) === String(id) ? { ...seq, reflexVectorOptIn: false } : seq
    );
    if (!previous.savedToSalesforce) {
      return Promise.resolve();
    }
    return updateQuoteRequestLineItemReflexVectorOptIn({
      lineItemId: id,
      reflexVectorOptIn: false
    })
      .then((result) => {
        if (!result?.success) {
          this._sequences = this._sequences.map((seq) =>
            String(seq.id) === String(id) ? previous : seq
          );
          this.showValidationToast(
            result?.error || "Failed to update reflex vector opt-in."
          );
        }
      })
      .catch((err) => {
        this._sequences = this._sequences.map((seq) =>
          String(seq.id) === String(id) ? previous : seq
        );
        this.showValidationToast("Failed to update reflex vector opt-in.");
        console.error("Reflex vector opt-in clear failed:", err);
      });
  }

  _glycerolFieldsFromLineItem(li, seq = {}) {
    const stock = li?.Glycerol_Stock__c === true;
    const scaleUpGlycerol =
      (li?.Scale_Up_Selected__c === true &&
        li?.Scale_Up_Glycerol_Stock__c === true) ||
      (seq.scaleUpSelected === true && seq.scaleUpGlycerolStock === true);
    const hasFeeIntent = stock || scaleUpGlycerol;
    const fee = this._resolveGlycerolFeeFromLineItem(li, hasFeeIntent, seq);
    const sales = this._salesFeesForRow(li, seq);
    return {
      glycerol: stock,
      glycerolFee: hasFeeIntent ? fee : null,
      glycerolPriceRaw: sales.glycerol || null,
      basePrice: li?.ABT_Total_Price__c,
      combinedPrice: seq.combinedPrice
    };
  }

  _isGlycerolPricingSettled(li, seq = {}) {
    if (!li) {
      return false;
    }
    const serverStock = li.Glycerol_Stock__c === true;
    const localStock = seq.glycerol === true;
    if (serverStock !== localStock) {
      return false;
    }
    const scaleUpGlycerol =
      li.Scale_Up_Glycerol_Stock__c === true ||
      (seq.scaleUpSelected === true && seq.scaleUpGlycerolStock === true);
    const glycerolPrice =
      Number(li.Glycerol_Price__c) ||
      this._salesFeesForRow(li, seq).glycerol ||
      0;
    // Wait for price only when glycerol is intentionally on.
    if ((localStock || scaleUpGlycerol) && glycerolPrice <= 0) {
      return false;
    }
    return true;
  }

  _applyLineItemPricingToSequence(lineItemId, li) {
    const ql = li.ABT_Quote_Line_Item__r || {};
    let updated = false;
    this._sequences = this._sequences.map((row) => {
      if (String(row.id) !== String(lineItemId)) {
        return row;
      }
      updated = true;
      const pricingExtras = this._pricingExtrasFromLineItem(li, row);
      const merged = {
        ...row,
        quoteLineItemId:
          li.ABT_Quote_Line_Item__c || ql.Id || row.quoteLineItemId,
        complexity: this.normalizeComplexityFromRow(li),
        scaleUp: li.Scale_Up__c || row.scaleUp,
        asEarlyAsDate:
          this.formatDateForDisplay(li.As_Early_As_Date__c) ||
          row.asEarlyAsDate,
        guaranteedDate:
          this.formatDateForDisplay(li.Expected_Ship_Date__c) ||
          row.guaranteedDate,
        feasibility: this.normalizeFeasibilityFromRow(li, ql),
        ...this._explanationFields(
          li,
          this.normalizeFeasibilityFromRow(li, ql)
        ),
        potentiallyToxic: li.Potentially_Toxic__c === true,
        recommendNotHighCopyNumVector: recommendNotHighCopyFromRow(li),
        reflexVectorOptIn:
          li.Reflex_Vector_Opt_In__c != null
            ? li.Reflex_Vector_Opt_In__c === true
            : row.reflexVectorOptIn === true,
        tranche: trancheDisplay(li),
        ...pricingExtras
      };
      return {
        ...merged,
        totalPrice: this._sequenceTotalPriceFromRow(li, merged),
        endCustomerPrice:
          this._endCustomerPriceFromRow(li) ?? row.endCustomerPrice
      };
    });
    if (updated) {
      this._applyFeasibilityGameState();
      this._refreshSalesLineItems();
    }
    return updated;
  }

  _persistPotentiallyToxicForSavedSequences() {
    const saved = (this._sequences || []).filter(
      (seq) => seq.savedToSalesforce && seq.id
    );
    if (!saved.length) {
      return Promise.resolve();
    }
    return bulkUpdateQuoteRequestLineItemPotentiallyToxic({
      lineItemIds: saved.map((seq) => seq.id),
      potentiallyToxicFlags: saved.map((seq) => seq.potentiallyToxic === true)
    })
      .then((result) => {
        if (!result?.success) {
          throw new Error(result?.error || "Potentially Toxic update failed");
        }
        const byId = new Map(
          (result.lines || []).map((line) => [
            String(line.id),
            line.potentiallyToxic === true
          ])
        );
        this._sequences = this._sequences.map((seq) => {
          if (!byId.has(String(seq.id))) {
            return seq;
          }
          return { ...seq, potentiallyToxic: byId.get(String(seq.id)) };
        });
        return result;
      })
      .catch((err) => {
        console.error("Potentially Toxic sync before step 4 failed:", err);
        this.showValidationToast(
          "Unable to save Potentially Toxic selections. Please try again."
        );
        throw err;
      });
  }

  _isSequenceValidForSave(sequence) {
    const validation = this.validateSequenceCharacters(sequence || "");
    return (
      validation.isValid && !this.isSequenceLengthOutOfRange(sequence || "")
    );
  }

  _isSequenceRowValidForSave(seq) {
    if (!seq) {
      return false;
    }
    return (
      this._isSequenceValidForSave(seq.sequence) &&
      !getSequenceNameErrorForRow(seq.name, this._sequences, seq.id) &&
      !getSequenceVectorValidationError(seq?.vector, this.isVectorRequired)
    );
  }

  _mergeLineItemIntoSequence(seq, apexLineItem) {
    const quoteLineItem = apexLineItem.ABT_Quote_Line_Item__r || {};
    const sequenceRecord = this.sequenceRecordFromRow(apexLineItem);
    const merged = {
      ...seq,
      id: apexLineItem.Id || seq.id,
      quoteLineItemId:
        apexLineItem.ABT_Quote_Line_Item__c ||
        quoteLineItem.Id ||
        seq.quoteLineItemId,
      name: this.sequenceNameFromRow(apexLineItem) || seq.name,
      sequence: this.sequenceTextFromRow(apexLineItem) || seq.sequence,
      vector:
        sequenceRecord?.Vector__c ||
        quoteLineItem.Vector__c ||
        seq.vector ||
        "",
      savedToSalesforce: true,
      asEarlyAsDate: this.formatDateForDisplay(
        apexLineItem.As_Early_As_Date__c
      ),
      guaranteedDate: this.formatDateForDisplay(
        apexLineItem.Expected_Ship_Date__c
      ),
      feasibility: this.normalizeFeasibilityFromRow(
        apexLineItem,
        quoteLineItem
      ),
      ...this._explanationFields(
        apexLineItem,
        this.normalizeFeasibilityFromRow(apexLineItem, quoteLineItem)
      ),
      complexity: this.normalizeComplexityFromRow(apexLineItem),
      scaleUp: apexLineItem.Scale_Up__c || seq.scaleUp || "",
      potentiallyToxic:
        apexLineItem.Potentially_Toxic__c === true ||
        seq.potentiallyToxic === true,
      recommendNotHighCopyNumVector: recommendNotHighCopyFromRow(apexLineItem),
      reflexVectorOptIn:
        apexLineItem.Reflex_Vector_Opt_In__c === true ||
        seq.reflexVectorOptIn === true,
      ...this._pricingExtrasFromLineItem(apexLineItem, seq),
      totalPrice: this._sequenceTotalPriceFromRow(apexLineItem, {
        ...seq,
        ...this._glycerolFieldsFromLineItem(apexLineItem, seq)
      }),
      endCustomerPrice:
        this._endCustomerPriceFromRow(apexLineItem) ?? seq.endCustomerPrice
    };
    this._queueGlycerolApplyForLineItem(merged.id, merged);
    this._applyPendingGlycerolIfReady();
    return merged;
  }

  _saveSequenceToSalesforce(seq) {
    if (!this.currentQuoteRequestId) {
      return Promise.resolve({ ...seq, savedToSalesforce: false });
    }
    if (!this._isSequenceRowValidForSave(seq)) {
      return Promise.resolve({ ...seq, savedToSalesforce: false });
    }
    return createQuoteRequestLineItem({
      quoteRequestId: this.currentQuoteRequestId,
      sequenceName: seq.name,
      sequence: seq.sequence,
      vectorId: this.lineItemVectorIdForApexFromSeq(seq),
      potentiallyToxic: seq.potentiallyToxic === true,
      glycerolStock: this._serverGlycerolStockOnCreate(),
      reflexVectorOptIn:
        this._isReflexApplicableVector(seq.vector) &&
        seq.reflexVectorOptIn === true
    })
      .then((result) => {
        if (!result?.Id) {
          return { ...seq, savedToSalesforce: false };
        }
        const merged = this._mergeLineItemIntoSequence(seq, result);
        this._pollLineItemPricing(result.Id);
        return this._attachGenbankFileToSequence(
          seq,
          this._sequenceIdFromLineItem(result)
        ).then(() => {
          const cleaned = { ...merged };
          delete cleaned.sourceGenbankFile;
          return cleaned;
        });
      })
      .catch(() => ({ ...seq, savedToSalesforce: false }));
  }

  _persistValidUnsavedSequences(options = {}) {
    const trackSequenceId = options.trackSequenceId;
    const unsavedValid = (this._sequences || []).filter(
      (seq) => !seq.savedToSalesforce && this._isSequenceRowValidForSave(seq)
    );
    if (!unsavedValid.length || !this.currentQuoteRequestId) {
      return Promise.resolve({
        trackedSequenceSaved:
          trackSequenceId != null
            ? isModalSequenceSaved(trackSequenceId, this._sequences)
            : undefined
      });
    }
    this.isProcessing = true;
    const sequenceNames = unsavedValid.map((seq) => seq.name || "");
    const sequences = unsavedValid.map((seq) => seq.sequence || "");
    const vectorIds = unsavedValid.map((seq) =>
      this.lineItemVectorIdForApexFromSeq(seq)
    );
    const potentiallyToxicFlags = unsavedValid.map(
      (seq) => seq.potentiallyToxic === true
    );
    const glycerolStockFlags = unsavedValid.map(() =>
      this._serverGlycerolStockOnCreate()
    );
    const reflexVectorOptInFlags = unsavedValid.map(
      (seq) =>
        this._isReflexApplicableVector(seq.vector) &&
        seq.reflexVectorOptIn === true
    );
    return createQuoteRequestLineItemsChunked(
      createQuoteRequestLineItemsDeferredKick,
      {
        quoteRequestId: this.currentQuoteRequestId,
        sequenceNames,
        sequences,
        vectorIds,
        potentiallyToxicFlags,
        glycerolStockFlags,
        reflexVectorOptInFlags,
        afterAll: () =>
          enqueuePendingForQuoteRequest({
            quoteRequestId: this.currentQuoteRequestId
          })
      }
    )
      .then((results) => {
        const updatesById = new Map();
        const insertedIds = [];
        const attachJobs = [];
        const aminoAcidLinkJobs = [];
        let trackedSequenceSaved = false;
        (unsavedValid || []).forEach((seq, idx) => {
          const inserted = results?.[idx];
          if (inserted?.Id) {
            const merged = this._mergeLineItemIntoSequence(seq, inserted);
            const withoutFile = { ...merged };
            delete withoutFile.sourceGenbankFile;
            updatesById.set(String(seq.id), withoutFile);
            insertedIds.push(inserted.Id);
            const aminoAcidId = seq.aminoAcidRecordId;
            const sequenceId = this._sequenceIdFromLineItem(inserted);
            if (aminoAcidId && sequenceId) {
              aminoAcidLinkJobs.push(
                linkAminoAcidSequence({ aminoAcidId, sequenceId })
              );
            }
            if (seq.sourceGenbankFile) {
              attachJobs.push(
                this._attachGenbankFileToSequence(
                  seq,
                  this._sequenceIdFromLineItem(inserted)
                )
              );
            }
            if (
              trackSequenceId != null &&
              String(seq.id) === String(trackSequenceId)
            ) {
              trackedSequenceSaved = true;
            }
          } else {
            updatesById.set(String(seq.id), {
              ...seq,
              savedToSalesforce: false
            });
          }
        });
        this._sequences = (this._sequences || []).map(
          (seq) => updatesById.get(String(seq.id)) || seq
        );
        this._applyFeasibilityGameState();
        insertedIds.forEach((lineItemId) =>
          this._pollLineItemPricing(lineItemId)
        );
        this._startPollingForPendingLineItems();
        return Promise.all([...attachJobs, ...aminoAcidLinkJobs]).then(() => ({
          trackedSequenceSaved
        }));
      })
      .catch(() => {
        // Keep failed rows local so users can correct and retry.
        return { trackedSequenceSaved: false };
      })
      .finally(() => {
        this.isProcessing = false;
      });
  }

  _hasPendingLineItemCalculations() {
    return (this._sequences || []).some(
      (seq) =>
        seq.savedToSalesforce &&
        (this._isFeasibilityPending(seq) ||
          this._isComplexityPending(seq) ||
          this._isAsEarlyAsDatePending(seq) ||
          this._isGuaranteedDatePending(seq))
    );
  }

  _startLineItemPolling() {
    if (this._lineItemPollingTimer) {
      this._pollPendingLineItemsSnapshot();
      return;
    }
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._lineItemPollingTimer = setInterval(() => {
      this._pollPendingLineItemsSnapshot();
    }, LINE_ITEM_POLL_INTERVAL_MS);
    this._pollPendingLineItemsSnapshot();
  }

  _stopLineItemPolling() {
    if (this._lineItemPollingTimer) {
      clearInterval(this._lineItemPollingTimer);
      this._lineItemPollingTimer = null;
    }
  }

  _pollPendingLineItemsSnapshot() {
    if (this.currentStep < 3) {
      return;
    }
    if (!this._hasPendingLineItemCalculations()) {
      this._stopLineItemPolling();
      return;
    }

    const pendingIds = (this._sequences || [])
      .filter(
        (seq) =>
          seq.savedToSalesforce &&
          (this._isFeasibilityPending(seq) ||
            this._isComplexityPending(seq) ||
            this._isAsEarlyAsDatePending(seq) ||
            this._isGuaranteedDatePending(seq))
      )
      .map((seq) => seq.id)
      .filter(Boolean);

    pendingIds.forEach((lineItemId) => {
      getLineItemPricing({ lineItemId })
        .then((li) => {
          if (li) {
            const updated = this._applyLineItemPricingToSequence(
              lineItemId,
              li
            );
            if (updated && !this._hasPendingLineItemCalculations()) {
              this._stopLineItemPolling();
            }
          }
        })
        .catch(() => {
          // best-effort; next interval retries
        });
    });
  }

  _startPollingForPendingLineItems() {
    if (this._hasPendingLineItemCalculations()) {
      this._startLineItemPolling();
    } else {
      this._stopLineItemPolling();
    }
  }

  disconnectedCallback() {
    if (this._boundCloseReflexPopover) {
      document.removeEventListener(
        "click",
        this._boundCloseReflexPopover,
        true
      );
    }
    this._clearAllDraftValidationTimers();
    this._stopQuoteDisplayPolling();
    this._stopLineItemPolling();
    this.stopProgressBar();
  }

  renderedCallback() {
    if (this.currentStep === 3) {
      this._ensureTrailingEmptyDraftRow();
    }
    // Populate textarea when modal is shown
    if (this.showManualInputModal && this.sequenceText) {
      const textarea = this.template.querySelector(".manual-sequence-textarea");
      if (textarea && textarea.value !== this.sequenceText) {
        textarea.value = this.sequenceText;
      }
    }
  }

  _isQrRequestAutoNumberDisplay(display) {
    const s = (display || "").trim();
    if (!s.startsWith("QR-")) return false;
    return /^QR-\d+$/i.test(s);
  }

  /** Handles CreateQuoteRequestResult object or legacy Id-only Apex response. */
  _applyCreateQuoteRequestResult(result) {
    let quoteRequestId = null;
    let displayQuoteNumber = "";
    if (result != null && typeof result === "object") {
      quoteRequestId = result.quoteRequestId || result.Id || null;
      displayQuoteNumber = (result.displayQuoteNumber || "").trim();
    } else if (result) {
      quoteRequestId = result;
    }
    this.currentQuoteRequestId = quoteRequestId;
    if (displayQuoteNumber) {
      this.quoteId = displayQuoteNumber;
    }
    if (quoteRequestId) {
      this._startQuoteDisplayPolling();
    }
  }

  _stopQuoteDisplayPolling() {
    if (this._quoteDisplayPollTimer != null) {
      clearTimeout(this._quoteDisplayPollTimer);
      this._quoteDisplayPollTimer = null;
    }
    this._quoteDisplayPollAttempts = 0;
  }

  _startQuoteDisplayPolling() {
    this._stopQuoteDisplayPolling();
    this._quoteDisplayPollAttempts = 0;
    this._runQuoteDisplayPollTick();
  }

  _runQuoteDisplayPollTick() {
    const maxAttempts = 25;
    if (!this.currentQuoteRequestId) {
      this._stopQuoteDisplayPolling();
      return;
    }
    getQuoteRequestDisplayQuoteNumber({
      quoteRequestId: this.currentQuoteRequestId
    })
      .then((v) => {
        const next = (v || "").trim();
        if (next) {
          this.quoteId = next;
        }
        this._quoteDisplayPollAttempts++;
        const d = (this.quoteId || "").trim();
        const haveDisplay = d.length > 0;
        const stillWaitingOnFormula =
          haveDisplay && this._isQrRequestAutoNumberDisplay(d);
        if (
          this._quoteDisplayPollAttempts >= maxAttempts ||
          (haveDisplay && !stillWaitingOnFormula)
        ) {
          this._stopQuoteDisplayPolling();
          return;
        }
        this._quoteDisplayPollTimer = setTimeout(
          () => this._runQuoteDisplayPollTick(),
          2000
        );
      })
      .catch(() => {
        this._quoteDisplayPollAttempts++;
        if (this._quoteDisplayPollAttempts >= maxAttempts) {
          this._stopQuoteDisplayPolling();
        } else {
          this._quoteDisplayPollTimer = setTimeout(
            () => this._runQuoteDisplayPollTick(),
            2000
          );
        }
      });
  }

  // ─── Load data ──────────────────────────────────────────────────────
  loadModalData() {
    this.isLoadingModalData = true;
    console.log("loadModalData called, userId:", this.currentUserId);

    getUserDetailsById({ userId: this.currentUserId })
      .then((user) => {
        console.log("User details loaded:", JSON.stringify(user));
        this.currentAccountId = user.AccountId;
        this.currentContactId = user.ContactId;
        return Promise.all([
          getQuoteRequestsByAccount(),
          this.fetchProductSequenceLimits(),
          isIdtChannelPartnerAccount({ accountId: user.AccountId })
        ]);
      })
      .then(([projects, , isIdt]) => {
        this.currentAccountIsIdtChannelPartner = isIdt === true;
        console.log("Projects loaded:", JSON.stringify(projects));
        this.existingProjects = [
          { label: "-- None --", value: "none" },
          ...(projects || []).map((p) => ({
            label: p.Name,
            value: p.Id
          }))
        ];
        console.log(
          "Existing projects:",
          JSON.stringify(this.existingProjects)
        );
        return getVectorLibraryData({
          currentUserAccountId: this.currentAccountId
        });
      })
      .then((vectorData) => {
        console.log("Vector data loaded:", JSON.stringify(vectorData));
        const defaultVectorId = vectorData?.defaultVectorId || null;
        const allVectors = [
          ...(vectorData.catalogVectors || []),
          ...(vectorData.customVectors || [])
        ];
        this.vectorOptions = [
          { label: "-- None --", value: "none" },
          ...allVectors.map((v) => ({
            label: v.Id === defaultVectorId ? `${v.Name} (Default)` : v.Name,
            value: v.Id,
            reflexApplicable: v.Reflex_Applicable__c === true,
            copyNumber: v.Copy_Number__c || ""
          }))
        ];
        this._applyContactDefaultVector(defaultVectorId);
        return getScaleUpLibraryData({ accountId: this.currentAccountId });
      })
      .then((scaleUpData) => {
        this._applyAccountDefaultGlycerol(
          scaleUpData?.defaultGlycerol === true
        );
        this.isLoadingModalData = false;
      })
      .catch((error) => {
        console.error("Error loading modal data:", JSON.stringify(error));
        this.isLoadingModalData = false;
      });
  }

  fetchProductSequenceLimits() {
    if (!this.productId) {
      return Promise.resolve();
    }

    return getProductById({ productId: this.productId })
      .then((product) => {
        this.isGlycerolStockEnabled =
          product?.Glycerol_Stock_Enabled__c === true;
        this.isScaleUpProductEnabled = product?.Scale_Up_Enabled__c === true;
        this.isVectorProductEnabled = product?.Vector_Enabled__c === true;
        this.productSku = product?.StockKeepingUnit || "";
        this._sequences = (this._sequences || []).map((seq) =>
          this._withAdditionalFees(this._sequenceForFeeDisplay(seq))
        );
        if (!this.showGlycerolSelection || !this.isGlycerolApplicable) {
          this.isGlycerol = false;
        }
        if (!this.isVectorProductEnabled) {
          this.selectedVector = "";
          this._sequences = (this._sequences || []).map((seq) => ({
            ...seq,
            vector: ""
          }));
        }
        const parsedMin = parseInt(product?.Minimum_Length__c, 10);
        const parsedMax = parseInt(product?.Maximum_Length__c, 10);
        this.allowedSequenceCharacters =
          product?.Allowed_Characters__c || DEFAULT_ALLOWED_SEQUENCE_CHARACTERS;
        const min = Number.isFinite(parsedMin) ? parsedMin : 200;
        const max = Number.isFinite(parsedMax) ? parsedMax : 600;
        this.sequenceLengthLimits = {
          min,
          max: max >= min ? max : min
        };
      })
      .catch((error) => {
        console.error(
          "Error loading product sequence limits:",
          JSON.stringify(error)
        );
      });
  }

  // ─── Sequence Validation ────────────────────────────────────────────

  validateSequenceCharacters(sequence) {
    return validateSequenceCharacters(sequence, this.allowedSequenceCharacters);
  }

  get hasSequenceErrors() {
    const sequenceInvalid = (sequence) => {
      if (!sequence) return false;
      const validation = this.validateSequenceCharacters(sequence);
      return !validation.isValid || this.isSequenceLengthOutOfRange(sequence);
    };
    const fromSaved = (this._sequences || []).some((seq) =>
      sequenceInvalid(seq?.sequence)
    );
    const fromDrafts = (this._draftRows || []).some(
      (draft) => !!this._getDraftSequenceValidationError(draft)
    );
    return fromSaved || fromDrafts;
  }

  get hasSequenceNameErrors() {
    const peers = this._rowsForDraftNameValidation();
    const fromSaved = (this._sequences || []).some(
      (seq) => !!getSequenceNameErrorForRow(seq?.name, peers, seq?.id)
    );
    const fromDrafts = (this._draftRows || []).some(
      (draft) => !!this._getDraftNameValidationError(draft, peers)
    );
    return fromSaved || fromDrafts;
  }

  get hasDuplicateSequenceNames() {
    const peers = (this._sequences || []).concat(
      (this._draftRows || [])
        .filter((draft) => this._shouldShowDraftValidation(draft))
        .map((draft) => ({ id: draft.id, name: draft.name }))
    );
    return getDuplicateSequenceNameKeys(peers).size > 0;
  }

  get hasVectorErrors() {
    if (!this.isVectorRequired) {
      return false;
    }
    const fromSaved = (this._sequences || []).some(
      (seq) => !!getSequenceVectorValidationError(seq?.vector, true)
    );
    const fromDrafts = (this._draftRows || []).some(
      (draft) =>
        this._shouldShowDraftValidation(draft) &&
        !!getSequenceVectorValidationError(draft?.vector, true)
    );
    return fromSaved || fromDrafts;
  }

  get sequenceErrorBannerMessage() {
    const hasMissingSequence = (this._draftRows || []).some((draft) => {
      if (!this._shouldShowDraftValidation(draft)) {
        return false;
      }
      return !!(draft.name || "").trim() && !(draft.sequence || "").trim();
    });
    if (hasMissingSequence) {
      return "Sequence is required. Please enter a sequence for each row.";
    }
    return `Sequence contains invalid characters or has a length outside product limits (${this.sequenceLengthLimits.min}-${this.sequenceLengthLimits.max} bp). Please click on the sequence to correct the issue.`;
  }

  get duplicateSequenceNameBannerMessage() {
    return DUPLICATE_SEQUENCE_NAME_ERROR;
  }

  get sequenceNameErrorBannerMessage() {
    const hasMissingName = (this._draftRows || []).some((draft) => {
      if (!this._shouldShowDraftValidation(draft)) {
        return false;
      }
      return !(draft.name || "").trim() && !!(draft.sequence || "").trim();
    });
    if (hasMissingName) {
      return "Sequence name is required. Please enter a name for each sequence.";
    }
    return "One or more sequence names contain invalid characters or exceed the length limit. Please click on the sequence to correct the name.";
  }

  get sequenceVectorErrorBannerMessage() {
    return getVectorRequiredBannerMessage(this.productName);
  }

  get sequenceNameMaxLength() {
    return SEQUENCE_NAME_MAX_LENGTH;
  }

  get projectNameMaxLength() {
    return PROJECT_NAME_MAX_LENGTH;
  }

  _validateSequenceName(name) {
    const trimmed = (name || "").trim();
    if (!trimmed) {
      this.sequenceNameError = "";
      return;
    }
    this.sequenceNameError = getSequenceNameErrorForRow(
      name,
      this._sequences,
      this.editingSequenceId
    );
  }

  _validateSequenceVector(vector) {
    this.sequenceVectorError = getSequenceVectorValidationError(
      vector,
      this.isVectorRequired
    );
  }

  // ─── Step getters ───────────────────────────────────────────────────

  get isStep1() {
    return this.currentStep === 1;
  }
  get isStep2() {
    return this.currentStep === 2;
  }
  get isStep3() {
    return this.currentStep === 3;
  }
  get isStep4() {
    return this.currentStep === 4;
  }

  /** Steps 3–4 use in-body header band (step line + action on the right). */
  get showQuoteStepRow() {
    return this.currentStep !== 3 && this.currentStep !== 4;
  }

  get stepLabel() {
    const pName = this.productName ? this.productName + " " : "";
    const labels = {
      1: "Choose " + pName + "Defaults",
      2: "Add " + pName + "Sequences",
      3: "Review and/or Edit Sequences",
      4: "Review " + pName + "Pricing & Delivery Details"
    };
    return labels[this.currentStep] || "";
  }

  get stepFraction() {
    return `Step ${this.currentStep}/${this.totalSteps}`;
  }

  /** XD: Step 1 title is "New Quote"; steps 2–4 show assigned quote ID */
  get quotePageTitle() {
    if (this.isStep1) {
      return "New Quote";
    }
    const id = (this.quoteId || "").trim();
    return id ? `New Quote ID ${id}` : "New Quote";
  }

  get showBackButton() {
    return this.currentStep > 1;
  }

  get showNextButton() {
    return this.currentStep <= this.totalSteps;
  }

  get isFragment() {
    return (this.productName || "").toLowerCase().includes("fragment");
  }

  get isLibrary() {
    return (this.productName || "").toLowerCase().includes("library");
  }

  get isClonal() {
    const name = (this.productName || "").toLowerCase();
    return name.includes("clonal") && !name.includes("fragment");
  }

  get isAnsaClonalDNA() {
    return this.productSku === ANSA_CLONAL_DNA_SKU;
  }

  get isAnsaClonalXL() {
    return ANSA_CLONAL_XL_SKUS.has(this.productSku);
  }

  /** Standard Ansa Clonal DNA (SKU 1002) — not fragments or XL */
  get isVectorRequired() {
    return (
      this.showVectorSelection && this.isAnsaClonalDNA && !this.isAnsaClonalXL
    );
  }

  /** Product flag + fragment/library exclusion */
  get showGlycerolSelection() {
    return this.isGlycerolStockEnabled && !this.isFragment && !this.isLibrary;
  }

  /** Add'l Fees column: Scale Up + Glycerol Stock fees when either feature is available */
  get showAddlFeesSelection() {
    return this.showScaleUpSelection || this.showGlycerolSelection;
  }

  /** Clonal products may opt in; other enabled products show glycerol greyed out */
  get isGlycerolApplicable() {
    return this.showGlycerolSelection && this.isClonal;
  }

  get isGlycerolSelectionDisabled() {
    return !this.isGlycerolApplicable;
  }

  /** Product flag controls vector UI on the portal */
  get showVectorSelection() {
    return this.isVectorProductEnabled;
  }

  /** Product flag controls Scale Up UI; hidden for fragments */
  get showScaleUpSelection() {
    return this.isScaleUpProductEnabled && !this.isFragment;
  }

  get isScaleUpSelectionDisabled() {
    return false;
  }

  get scaleUpQuantityOptions() {
    return SCALE_UP_QUANTITY_OPTIONS;
  }

  get totalSequenceCount() {
    return (this._sequences || []).length;
  }

  get totalSelectedSequenceCount() {
    return (this._sequences || []).filter((s) => s.selected === true).length;
  }

  /** Quote request header Vector__c — omit when product does not support vector selection */
  resolveQuoteHeaderVectorId() {
    if (!this.showVectorSelection) {
      return null;
    }
    const v = this.selectedVector;
    if (!v || v === "none") {
      return null;
    }
    return v;
  }

  /** Line item vector for Apex (null = omit / not applicable) */
  lineItemVectorIdForApexFromModal() {
    if (!this.showVectorSelection) {
      return null;
    }
    const v = this.sequenceVector;
    if (!v || v === "none") {
      return null;
    }
    return v;
  }

  /** Line item vector when saving file-uploaded rows */
  lineItemVectorIdForApexFromSeq(seq) {
    if (!this.showVectorSelection) {
      return null;
    }
    const v = seq?.vector;
    if (!v || v === "none") {
      return null;
    }
    return v;
  }

  vectorValueForSequenceRow() {
    if (!this.showVectorSelection) {
      return "";
    }
    return this.sequenceVector && this.sequenceVector !== "none"
      ? this.sequenceVector
      : "";
  }

  get step1BodyClass() {
    return this.isFragment ? "quote-body quote-body--centered" : "quote-body";
  }

  get stepFieldsRowClass() {
    return this.isFragment
      ? "step-fields-row step-fields-row--fragment"
      : "step-fields-row";
  }

  get step3Colspan() {
    return this.showVectorSelection ? 8 : 7;
  }

  get step3TableClass() {
    const base = "step3-table";
    return this.showVectorSelection ? base : `${base} step3-table--no-vector`;
  }

  get step3TableWrapClass() {
    return this._reflexPopoverLineId
      ? "step3-table-wrap step3-table-wrap--reflex-open"
      : "step3-table-wrap";
  }

  get manualModalTitle() {
    return this.editingSequenceId ? "Edit Sequence" : "Add Sequence";
  }

  get step4TableClass() {
    const base = "step3-table step4-line-table";
    const modifiers = [];
    if (!this.showScaleUpSelection) {
      modifiers.push("step4-line-table--no-scaleup");
    }
    if (!this.showGlycerolSelection) {
      modifiers.push("step4-line-table--no-glycerol");
    }
    return modifiers.length ? `${base} ${modifiers.join(" ")}` : base;
  }

  get step4TableWrapClass() {
    return this._scaleUpPopoverLineId || this._scaleUpDefinitionsOpen
      ? "step3-table-wrap step3-table-wrap--reflex-open"
      : "step3-table-wrap";
  }

  get step4Colspan() {
    let cols = 8;
    if (this.showScaleUpSelection) {
      cols++;
    }
    if (this.showGlycerolSelection) {
      cols += 2;
    }
    return cols;
  }

  get isUpdatingGlycerol() {
    return (this._glycerolUpdatingIds || []).length > 0;
  }

  get isCalculatingPricing() {
    if (!this.hasSequences) {
      return false;
    }
    const seqs = this._sequences || [];
    if (this.currentStep === 3) {
      return seqs.some(
        (seq) => seq.savedToSalesforce && this._isFeasibilityPending(seq)
      );
    }
    return seqs.some(
      (seq) => this._isFeasibilityPending(seq) || this._isComplexityPending(seq)
    );
  }

  get isCalculationPending() {
    return this.isCalculatingPricing || this.isUpdatingGlycerol;
  }

  /** Step 3: classification/feasibility only. Step 4: includes glycerol loading. */
  get isCalculationPendingForStep() {
    if (this.currentStep === 3) {
      return this.isCalculatingPricing;
    }
    if (this.currentStep === 4) {
      return this.isCalculationPending;
    }
    return false;
  }

  get calculationPendingLabel() {
    if (this.isUpdatingGlycerol && !this.isCalculatingPricing) {
      return "Updating Glycerol Stock & fees";
    }
    return "Calculating Sequence Classification & Pricing";
  }

  get hasSequencesInCalculationScope() {
    if (!this.hasSequences) {
      return false;
    }
    const seqs = this._sequences || [];
    if (this.currentStep === 3) {
      return seqs.some((seq) => seq.savedToSalesforce);
    }
    return seqs.length > 0;
  }

  get showClassificationComplete() {
    return (
      this.hasSequencesInCalculationScope && !this.isCalculationPendingForStep
    );
  }

  get showCalculationStatus() {
    return (
      this.hasSequencesInCalculationScope &&
      (this.isCalculationPendingForStep || this.showClassificationComplete)
    );
  }

  get showFeasibilityGameLink() {
    return this.isStep3 && this.isCalculatingPricing;
  }

  get progressBarStyle() {
    return `width: ${this.progressPercentage}%`;
  }

  get feasibilityStatusMessage() {
    if (this.progressPercentage >= 100) {
      return "Feasibility calculation complete!";
    }
    return "Calculating feasibility...";
  }

  get feasibilityStatusIcon() {
    return this.progressPercentage >= 100 ? "utility:check" : "utility:spinner";
  }

  get isFooterProcessing() {
    return this.isProcessing;
  }

  get nextBtnLabel() {
    return this.currentStep === 4 ? "Add to Cart" : "Next";
  }

  get isNextDisabled() {
    if (this.currentStep === 1 && !this.hasStep1RequiredFields) {
      return true;
    }
    if (this.currentStep === 2 && !this.hasStep2RequiredFields) {
      return true;
    }
    if (
      (this.currentStep === 3 || this.currentStep === 4) &&
      !this.hasStep3RequiredFields
    ) {
      return true;
    }
    if (
      (this.currentStep === 3 || this.currentStep === 4) &&
      this.isCalculationPending
    ) {
      return true;
    }
    if (this.currentStep === 4 && this.hasIncompleteScaleUpConfig) {
      return true;
    }
    if (
      (this.currentStep === 3 || this.currentStep === 4) &&
      this.hasSequenceErrors
    ) {
      return true;
    }
    if (
      (this.currentStep === 3 || this.currentStep === 4) &&
      this.hasSequenceNameErrors
    ) {
      return true;
    }
    if (
      (this.currentStep === 3 || this.currentStep === 4) &&
      this.hasDuplicateSequenceNames
    ) {
      return true;
    }
    if (
      (this.currentStep === 3 || this.currentStep === 4) &&
      this.hasVectorErrors
    ) {
      return true;
    }
    if (
      (this.currentStep === 3 || this.currentStep === 4) &&
      this.hasUnsavedSequences
    ) {
      return true;
    }
    if (
      (this.currentStep === 3 || this.currentStep === 4) &&
      this.hasIncompleteDraftSequences
    ) {
      return true;
    }
    return this.isFooterProcessing;
  }

  get hasStep1RequiredFields() {
    const hasExistingProject =
      this.selectedExistingProject && this.selectedExistingProject !== "none";
    const hasNewProject = !!(this.newProjectName && this.newProjectName.trim());
    return hasExistingProject || hasNewProject;
  }

  get isAminoAcidUploadEnabled() {
    return (
      AMINO_ACID_UPLOAD_ENABLED &&
      (this.isAnsaClonalDNA || this.isAnsaClonalXL)
    );
  }

  get hasUploadedSequenceFiles() {
    return (this.uploadedSequenceFiles || []).length > 0;
  }

  get hasStep2RequiredFields() {
    const hasAmino = this.isAminoAcidUploadEnabled && !!this.aminoFileName;
    return (
      this.hasSequences || this.uploadedSequenceFiles.length > 0 || hasAmino
    );
  }

  get hasStep3RequiredFields() {
    return this.hasSequences;
  }

  get hasUnsavedSequences() {
    return (this._sequences || []).some((seq) => !seq.savedToSalesforce);
  }

  /** Unsaved inline draft rows (empty trailing row is ignored). */
  get hasIncompleteDraftSequences() {
    return (this._draftRows || []).some((draft) => {
      if (draft.isSaving) {
        return true;
      }
      return !this._isDraftRowEmpty(draft);
    });
  }

  /** Scale Up checked but Prep Quantity not applied yet (red icon), or popover still open. */
  get hasIncompleteScaleUpConfig() {
    if (this._scaleUpPopoverLineId) {
      return true;
    }
    return (this._sequences || []).some((seq) => {
      if (seq.scaleUpSelected !== true) {
        return false;
      }
      const qty = seq.scaleUpQuantity;
      return qty == null || String(qty).trim() === "";
    });
  }

  showValidationToast(message) {
    this.dispatchEvent(
      new ShowToastEvent({
        title: "Error",
        message,
        variant: "error",
        mode: "sticky"
      })
    );
  }

  /** Step 2 banner: file-upload/parse errors only (GenBank multi-record, empty, unsupported, etc.). */
  _showStep2FileError(message) {
    this.step2UploadErrorMessage = message || "";
    this.showStep2ValidationError = !!message;
    if (message) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Error",
          message,
          variant: "error",
          mode: "sticky"
        })
      );
    }
  }

  _clearStep2UploadError() {
    this.step2UploadErrorMessage = "";
    this.showStep2ValidationError = false;
  }

  // ─── Step 1 handlers ────────────────────────────────────────────────

  handleExistingProjectChange(event) {
    this.selectedExistingProject = event.detail.value;
    if (this.selectedExistingProject) this.newProjectName = "";
  }

  handleNewProjectChange(event) {
    this.newProjectName = event.target.value;
    if (this.newProjectName) this.selectedExistingProject = "";
  }

  handleVectorChange(event) {
    const val = event.detail.value;
    this.selectedVector = val === "none" ? "" : val;
    this._syncEmptyDraftVectorsFromSelection();
  }
  handleGlycerolChange(event) {
    if (this.isGlycerolSelectionDisabled) {
      return;
    }
    this.isGlycerol = event.target.checked;
  }

  // ─── Step 2 handlers ────────────────────────────────────────────────

  handleDownloadTemplate(event) {
    event.preventDefault();
    window.open(csvTemplate, "_blank");
  }

  _sequenceFileIdentity(file) {
    return `${file.name}_${file.size}_${file.lastModified}`;
  }

  _generateLocalId(prefix) {
    this._localIdCounter += 1;
    return `${prefix}_${Date.now()}_${this._localIdCounter}`;
  }

  _fileExtension(fileName) {
    const name = (fileName || "").toLowerCase();
    const match = SEQUENCE_UPLOAD_EXTENSIONS.slice()
      .sort((a, b) => b.length - a.length)
      .find((ext) => name.endsWith(ext));
    return match || "";
  }

  _isAcceptedSequenceFileName(fileName) {
    return !!this._fileExtension(fileName);
  }

  _isGenbankFileName(fileName) {
    const name = (fileName || "").toLowerCase();
    return GENBANK_EXTENSIONS.some((ext) => name.endsWith(ext));
  }

  /** Sequence Name = file name without extension (Genbank requirement). */
  _sequenceNameFromFileName(fileName) {
    const name = fileName || "";
    const ext = this._fileExtension(name);
    if (ext) {
      return name.substring(0, name.length - ext.length).trim();
    }
    const dotIndex = name.lastIndexOf(".");
    return (dotIndex > 0 ? name.substring(0, dotIndex) : name).trim();
  }

  _fileToBase64(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => {
        const result = reader.result || "";
        resolve(
          typeof result === "string" && result.includes(",")
            ? result.substring(result.indexOf(",") + 1)
            : result
        );
      };
      reader.onerror = () => reject(reader.error);
      reader.readAsDataURL(file);
    });
  }

  _sequenceIdFromLineItem(apexLineItem) {
    return (
      apexLineItem?.Related_Sequence__c ||
      apexLineItem?.Related_Sequence__r?.Id ||
      null
    );
  }

  _attachGenbankFileToSequence(seq, sequenceId) {
    if (!seq?.sourceGenbankFile || !sequenceId) {
      return Promise.resolve();
    }
    const file = seq.sourceGenbankFile;
    return this._fileToBase64(file)
      .then((base64Data) =>
        uploadPODocument({
          base64Data,
          fileName: file.name,
          contentType: file.type || "application/octet-stream",
          parentId: sequenceId
        })
      )
      .catch((err) => {
        console.error("Error attaching Genbank file to Sequence:", err);
        this.showValidationToast(
          `Sequence was saved, but the Genbank file "${file.name}" could not be attached.`
        );
      });
  }

  handleSequenceFileUpload(event) {
    const files = event.target.files;
    if (!files || files.length === 0) {
      return;
    }

    const existing = new Set(
      this.uploadedSequenceFiles.map((entry) =>
        this._sequenceFileIdentity(entry.file)
      )
    );
    const newEntries = [];
    const rejectedNames = [];
    for (let i = 0; i < files.length; i++) {
      const file = files[i];
      if (!this._isAcceptedSequenceFileName(file.name)) {
        rejectedNames.push(file.name);
        continue;
      }
      const identity = this._sequenceFileIdentity(file);
      if (existing.has(identity)) {
        continue;
      }
      existing.add(identity);
      newEntries.push({
        id: this._generateLocalId("seqfile"),
        name: file.name,
        file
      });
    }
    if (rejectedNames.length > 0) {
      this._showStep2FileError(
        `Unsupported file type. Accepted formats: CSV, FASTA (.fasta, .fa, .fna), Genbank (${GENBANK_EXTENSIONS.join(", ")}).`
      );
    }
    if (newEntries.length > 0) {
      this.uploadedSequenceFiles = [
        ...this.uploadedSequenceFiles,
        ...newEntries
      ];
      this._clearStep2UploadError();
    }
    event.target.value = "";
  }

  handleRemoveSequenceFile(event) {
    const id = event.currentTarget.dataset.id;
    if (!id) {
      return;
    }
    this.uploadedSequenceFiles = this.uploadedSequenceFiles.filter(
      (entry) => entry.id !== id
    );
    this._clearStep2UploadError();
  }

  handleAminoFileUpload(event) {
    if (!this.isAminoAcidUploadEnabled) {
      this._showStep2FileError(
        "Amino acid optimization is available for Clonal DNA and XL Clonal DNA only."
      );
      event.target.value = "";
      return;
    }
    const file = event.target.files[0];
    if (file) {
      this.aminoFile = file;
      this.aminoFileName = file.name;
      this.isCodonMode = true;
      this.showStep2ValidationError = false;
      this.codonOptimizationFailures = [];
      this.codonOptimizationWarnings = [];
    }
  }

  handleRemoveAminoFile() {
    this.aminoFile = null;
    this.aminoFileName = "";
    this.isCodonMode = false;
    this.codonOptimizationFailures = [];
    this.codonOptimizationWarnings = [];
  }

  handleCodonClose() {
    this.handleRemoveAminoFile();
  }

  handleCodonOptimized(event) {
    if (!this.isAminoAcidUploadEnabled) {
      this._showStep2FileError(
        "Amino acid optimization is available for Clonal DNA and XL Clonal DNA only."
      );
      return;
    }
    const detail = event.detail || {};
    const successes = detail.successes || [];
    this.codonOptimizationFailures = detail.failures || [];
    this.codonOptimizationWarnings = detail.warnings || [];
    if (!successes.length) {
      return;
    }
    if (!this.appendParsedSequences(successes)) {
      return;
    }
    this.isProcessing = true;
    this._clearStep2UploadError();
    this.finalizeSequenceFileUpload()
      .catch((error) => {
        this._showStep2FileError(
          error?.body?.message || error?.message || "Unable to add optimized sequences to this quote."
        );
      })
      .finally(() => {
        this.isProcessing = false;
        this.isCodonMode = false;
        this.aminoFile = null;
        this.aminoFileName = "";
      });
  }

  readAsText(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(reader.result);
      reader.onerror = () => reject(reader.error);
      reader.readAsText(file);
    });
  }

  parseFasta(text) {
    const out = [];
    let current = null;
    for (const rawLine of text.split(/\r?\n/)) {
      const line = rawLine.trim();
      if (!line) continue;
      if (line.startsWith(">")) {
        if (current && current.sequence) out.push(current);
        const header = line.substring(1).trim();
        current = {
          name: header.split(/\s+/)[0] || `Sequence_${out.length + 1}`,
          sequence: ""
        };
      } else if (current) {
        current.sequence += line.replace(/\s/g, "");
      }
    }
    if (current && current.sequence) out.push(current);
    return out;
  }

  parseGenbank(text) {
    // Keywords and nucleotide letters are treated case-insensitively.
    const locusCount = (text.match(/^LOCUS\s+/gim) || []).length;
    if (locusCount > 1) {
      return { sequences: [], error: GENBANK_MULTI_RECORD_ERROR };
    }

    const out = [];
    const records = text.split(/^\/\//m);
    for (const rec of records) {
      if (!rec.trim()) continue;
      const locus = rec.match(/^LOCUS\s+(\S+)/im);
      const defn = rec.match(/^DEFINITION\s+(.+)/im);
      const name =
        (locus && locus[1]) ||
        (defn && defn[1].trim()) ||
        `Sequence_${out.length + 1}`;
      // Match the ORIGIN keyword at line start only (not e.g. rep_origin features).
      // Use [ \t]* instead of \s* so the newline after ORIGIN is not consumed.
      const origin = rec.match(/^ORIGIN[ \t]*\r?\n([\s\S]*)/im);
      if (origin) {
        // Strip coordinates/whitespace; normalize nucleotides to uppercase.
        const seq = origin[1].replace(/[\s0-9]/g, "").toUpperCase();
        if (seq) out.push({ name, sequence: seq });
      }
    }

    if (out.length > 1) {
      return { sequences: [], error: GENBANK_MULTI_RECORD_ERROR };
    }
    if (out.length === 0) {
      const hasContigReference = /^CONTIG\b/im.test(text);
      return {
        sequences: [],
        error: hasContigReference
          ? GENBANK_CONTIG_REFERENCE_ERROR
          : GENBANK_EMPTY_SEQUENCE_ERROR
      };
    }
    return { sequences: out, error: null };
  }

  validatePortalCsvText(text) {
    const expectedHeaders = ["SequenceName", "Sequence"];
    if (!text || !text.trim()) {
      return { valid: false, message: "The CSV file appears to be empty." };
    }
    const lines = text.split(/\r?\n/).filter((l) => l.trim());
    if (lines.length < 2) {
      return {
        valid: false,
        message: "The CSV file does not contain enough data."
      };
    }
    const headers = lines[0].split(",").map((h) => h.trim());
    const missingHeaders = expectedHeaders.filter(
      (header) => !headers.some((h) => h.toLowerCase() === header.toLowerCase())
    );
    if (missingHeaders.length > 0) {
      return {
        valid: false,
        message: `Invalid CSV format. Missing required columns: ${missingHeaders.join(", ")}. Please use the provided template.`
      };
    }
    for (let i = 1; i < lines.length; i++) {
      if (!lines[i].trim()) continue;
      const cells = lines[i].split(",");
      if (cells.length < expectedHeaders.length) {
        return {
          valid: false,
          message: `Row ${i} does not have enough columns. Please check your CSV file.`
        };
      }
    }
    return { valid: true };
  }

  parseCsv(text) {
    const validation = this.validatePortalCsvText(text);
    if (!validation.valid) {
      return { sequences: [], error: validation.message };
    }

    const lines = text.split(/\r?\n/).filter((l) => l.trim());
    const headers = lines[0].split(",").map((h) => h.trim().replace(/"/g, ""));
    const nameIdx = headers.findIndex(
      (h) => h.toLowerCase() === "sequencename"
    );
    const seqIdx = headers.findIndex((h) => h.toLowerCase() === "sequence");
    const out = [];

    for (let i = 1; i < lines.length; i++) {
      if (!lines[i].trim()) continue;
      const cols = lines[i].split(",").map((c) => c.trim().replace(/"/g, ""));
      const seq = (cols[seqIdx] || "").replace(/\s/g, "");
      const nm = nameIdx >= 0 ? cols[nameIdx] : "";
      if (seq) out.push({ name: nm || `Sequence_${i}`, sequence: seq });
    }
    return { sequences: out, error: null };
  }

  appendParsedSequences(parsed, options = {}) {
    if (!parsed || parsed.length === 0) {
      this._showStep2FileError(
        "The file was read but no sequences could be extracted. Check the file format and use the provided CSV template."
      );
      return false;
    }

    const newSeqs = parsed
      .map((seq, index) => ({
        id: this._generateLocalId("file"),
        name: seq.name || `Sequence_${index + 1}`,
        vector: this._effectiveSelectedVector(),
        sequence: (seq.sequence || "").replace(/\s/g, ""),
        aminoAcidSequence: seq.aminoAcidSequence || null,
        aminoAcidRecordId: seq.aminoAcidRecordId || null,
        length: (seq.sequence || "").replace(/\s/g, "").length,
        glycerol: this._effectiveGlycerolStock(this.isGlycerol),
        savedToSalesforce: false,
        sourceGenbankFile: options.sourceGenbankFile || null
      }))
      .filter((seq) => !!seq.sequence);

    this._sequences = [...this._sequences, ...newSeqs];
    return true;
  }

  finalizeSequenceFileUpload() {
    return this._persistValidUnsavedSequences()
      .then(() => {
        // Sequence/name/vector issues are validated on Step 3 — don't keep a Step 2 banner for them.
        this._clearStep2UploadError();
        this.currentStep = 3;
        this._ensureTrailingEmptyDraftRow();
        this._applyFeasibilityGameState();
        return true;
      })
      .finally(() => {
        this.isProcessing = false;
      });
  }

  processParsedSequences(parsed) {
    if (!this.appendParsedSequences(parsed)) {
      this.isProcessing = false;
      return Promise.resolve(false);
    }
    return this.finalizeSequenceFileUpload();
  }

  _readAndParseSequenceFile(file) {
    const name = (file.name || "").toLowerCase();

    if (
      name.endsWith(".fasta") ||
      name.endsWith(".fa") ||
      name.endsWith(".fna")
    ) {
      return this.readAsText(file)
        .then((txt) => ({ success: true, sequences: this.parseFasta(txt) }))
        .catch((err) => {
          console.error("Error reading FASTA file:", err);
          return { success: false, error: "Failed to read the FASTA file." };
        });
    }
    if (this._isGenbankFileName(file.name)) {
      return this.readAsText(file)
        .then((txt) => {
          const { sequences, error } = this.parseGenbank(txt);
          if (error) {
            return { success: false, error };
          }
          const sequenceName = this._sequenceNameFromFileName(file.name);
          const namedSequences = (sequences || []).map((seq) => ({
            ...seq,
            name: sequenceName || seq.name
          }));
          return {
            success: true,
            sequences: namedSequences,
            sourceGenbankFile: file
          };
        })
        .catch((err) => {
          console.error("Error reading Genbank file:", err);
          return { success: false, error: "Failed to read the Genbank file." };
        });
    }
    if (name.endsWith(".csv")) {
      return this.readAsText(file)
        .then((txt) => {
          const { sequences, error } = this.parseCsv(txt);
          if (error) {
            return { success: false, error };
          }
          return { success: true, sequences };
        })
        .catch((err) => {
          console.error("Error reading CSV file:", err);
          return { success: false, error: "Failed to read the CSV file." };
        });
    }

    return Promise.resolve({
      success: false,
      error:
        "Unsupported file format. Please use CSV, FASTA, or Genbank (.gb, .gbk, .gbf, .gbff, .genbank)."
    });
  }

  parseUploadedSequenceFiles() {
    const filesToProcess = [...this.uploadedSequenceFiles];
    if (filesToProcess.length === 0) {
      return Promise.resolve(false);
    }

    this.isProcessing = true;
    this._clearStep2UploadError();

    const parsedResults = [];

    const failWithError = (message) => {
      this.uploadedSequenceFiles = filesToProcess;
      this._showStep2FileError(message);
      this.isProcessing = false;
      return false;
    };

    const processNext = (index) => {
      if (index >= filesToProcess.length) {
        parsedResults.forEach((result) => {
          this.appendParsedSequences(result.sequences, {
            sourceGenbankFile: result.sourceGenbankFile || null
          });
        });
        this.uploadedSequenceFiles = [];
        return this.finalizeSequenceFileUpload();
      }

      const entry = filesToProcess[index];
      return this._readAndParseSequenceFile(entry.file)
        .then((result) => {
          if (!result.success) {
            const detail = result.error || "Failed to process file.";
            return failWithError(`${entry.name}: ${detail}`);
          }
          if (!result.sequences || result.sequences.length === 0) {
            return failWithError(
              `${entry.name}: The file was read but no sequences could be extracted.`
            );
          }
          parsedResults.push(result);
          return processNext(index + 1);
        })
        .catch((err) => {
          console.error("Error processing sequence file:", err);
          return failWithError(`${entry.name}: Failed to process file.`);
        });
    };

    return processNext(0);
  }

  // ─── Manual Input Modal ─────────────────────────────────────────────

  handleManualInput() {
    // Go straight to the empty Sequences table (Step 3) so users can type or paste
    // without first creating a sequence via the add modal. Modal remains for edit.
    this._editOriginalSnapshot = null;
    this.editingSequenceId = null;
    this.sequenceName = "";
    this.sequenceVector = this._effectiveSelectedVector();
    this.sequenceText = "";
    this.sequenceError = "";
    this.sequenceNameError = "";
    this.sequenceVectorError = "";
    this.sequenceCharCount = 0;
    this.showManualInputModal = false;
    this.showStep2ValidationError = false;
    this.step2UploadErrorMessage = "";
    this.currentStep = 3;
    this._ensureTrailingEmptyDraftRow();
    this._applyFeasibilityGameState();
  }

  handleCloseManualModal(forceClose) {
    if (forceClose !== true && this.isModalSaveInProgress) {
      return;
    }
    this.showManualInputModal = false;
    this.sequenceName = "";
    this.sequenceVector = "";
    this.sequenceText = "";
    this.sequenceError = "";
    this.sequenceNameError = "";
    this.sequenceVectorError = "";
    this.sequenceCharCount = 0;
    this.editingSequenceId = null;
    this._editOriginalSnapshot = null;
    this.isModalSaveInProgress = false;
  }

  _clearModalSaveLock() {
    this.isModalSaveInProgress = false;
  }

  _onModalFieldEdited() {
    if (this.isModalSaveInProgress) {
      this._clearModalSaveLock();
    }
  }

  handleSequenceNameChange(event) {
    this._onModalFieldEdited();
    this.sequenceName = event.target.value;
    this._validateSequenceName(this.sequenceName);
  }
  handleSequenceVectorChange(event) {
    this._onModalFieldEdited();
    this.sequenceVector = event.detail.value;
    this._validateSequenceVector(this.sequenceVector);
  }

  _explanationFields(lineItem, feasibility) {
    if (!feasibility || String(feasibility).toLowerCase() === "pending") {
      return {
        feasibilityJson: "",
        feasibilityExplained1: "",
        feasibilityExplained2: "",
        feasibilityExplained3: ""
      };
    }
    const explained = feasibilityExplainedFromRow(lineItem);
    return {
      feasibilityJson: explained.json,
      feasibilityExplained1: explained.rank1,
      feasibilityExplained2: explained.rank2,
      feasibilityExplained3: explained.rank3
    };
  }

  handleSequenceTextChange(event) {
    this._onModalFieldEdited();
    const val = event.detail?.value ?? event.target.value;
    this.sequenceText = val;
    this.sequenceCharCount = val.length;
    this.validateSequence(val);
  }

  validateSequence(val) {
    const min = this.sequenceLengthLimits.min;
    const max = this.sequenceLengthLimits.max;

    if (val.length < min) {
      this.sequenceError = `Sequence must be at least ${min} characters.`;
    } else if (val.length > max) {
      this.sequenceError = `Sequence must not exceed ${max} characters.`;
    } else if (!this.validateSequenceCharacters(val).isValid) {
      this.sequenceError = `Sequence must contain only ${getAllowedSequenceCharactersText(this.allowedSequenceCharacters)}.`;
    } else {
      this.sequenceError = "";
    }
  }

  isSequenceLengthOutOfRange(sequence) {
    const length = (sequence || "").length;
    const min = this.sequenceLengthLimits.min;
    const max = this.sequenceLengthLimits.max;
    return length > 0 && (length < min || length > max);
  }

  get isSaveDisabled() {
    return (
      this.isModalSaveInProgress ||
      !!this.sequenceError ||
      !!this.sequenceNameError ||
      !!this.sequenceVectorError ||
      (this.isVectorRequired && isSequenceVectorMissing(this.sequenceVector)) ||
      this.sequenceText.length < this.sequenceLengthLimits.min ||
      !(this.sequenceName || "").trim()
    );
  }

  get sequencePlaceholder() {
    return `Enter your sequence here (min ${this.sequenceLengthLimits.min}, max ${this.sequenceLengthLimits.max} characters). Must contain only ${getAllowedSequenceCharactersText(this.allowedSequenceCharacters)}`;
  }

  get sequenceTextareaClass() {
    return this.sequenceError
      ? "manual-sequence-textarea manual-sequence-textarea--error"
      : "manual-sequence-textarea";
  }

  _buildUpdatedSequenceFromModal(existing) {
    const markPending = !!existing?.savedToSalesforce;
    return {
      ...existing,
      name: this.sequenceName,
      vector: this.vectorValueForSequenceRow(),
      sequence: this.sequenceText,
      length: this.sequenceCharCount,
      ...(markPending
        ? {
            feasibility: "Pending",
            complexity: "Pending",
            feasibilityJson: "",
            feasibilityExplained1: "",
            feasibilityExplained2: "",
            feasibilityExplained3: ""
          }
        : {})
    };
  }

  _applyUpdatedSequenceToLocal(lineItemId, updatedLocal) {
    this._sequences = (this._sequences || []).map((seq) =>
      String(seq.id) === String(lineItemId) ? updatedLocal : seq
    );
  }

  _finishModalUnsavedPersist() {
    const modalSequenceId = this.editingSequenceId;
    this.isModalSaveInProgress = true;
    return this._persistValidUnsavedSequences({
      trackSequenceId: modalSequenceId
    })
      .then((result) => {
        if (result?.trackedSequenceSaved !== true) {
          this.showValidationToast(
            "Unable to save this sequence. Please review and try again."
          );
          return false;
        }
        this.handleCloseManualModal(true);
        return true;
      })
      .catch(() => {
        this.showValidationToast(
          "Unable to save sequence changes. Please try again."
        );
      })
      .finally(() => {
        this._clearModalSaveLock();
      });
  }

  _isModalVectorOnlyChange() {
    const original = this._editOriginalSnapshot;
    if (!original) {
      return false;
    }
    const current = this._snapshotFromModalFields();
    return (
      current.name === original.name &&
      current.sequence === original.sequence &&
      current.vector !== original.vector
    );
  }

  handleSaveSequence() {
    if (this.isModalSaveInProgress) {
      return;
    }
    this.validateSequence(this.sequenceText);
    this._validateSequenceName(this.sequenceName);
    this._validateSequenceVector(this.sequenceVector);
    if (
      this.sequenceError ||
      this.sequenceNameError ||
      this.sequenceVectorError
    ) {
      return;
    }

    if (this.editingSequenceId) {
      const existing = this._sequences.find(
        (seq) => String(seq.id) === String(this.editingSequenceId)
      );
      if (!existing) {
        this.handleCloseManualModal();
        return;
      }

      const updatedLocal = this._buildUpdatedSequenceFromModal(existing);

      if (this._isSequenceEditUnchanged(existing)) {
        if (!existing.savedToSalesforce) {
          this._applyUpdatedSequenceToLocal(
            this.editingSequenceId,
            updatedLocal
          );
          this._finishModalUnsavedPersist();
        } else {
          this.handleCloseManualModal();
        }
        return;
      }

      const lineItemId = this.editingSequenceId;

      if (!updatedLocal.savedToSalesforce) {
        this._applyUpdatedSequenceToLocal(lineItemId, updatedLocal);
        this._finishModalUnsavedPersist();
        return;
      }

      if (this._isModalVectorOnlyChange() && this.showVectorSelection) {
        const vectorId = this.lineItemVectorIdForApexFromModal();
        if (!vectorId) {
          return;
        }
        this.isModalSaveInProgress = true;
        updateQuoteLineItemVector({ lineItemId, vectorId })
          .then((result) => {
            if (!result?.success) {
              throw new Error(result?.error || "Failed to update vector.");
            }
            this._applyUpdatedSequenceToLocal(lineItemId, updatedLocal);
            this.handleCloseManualModal(true);
            this._pollLineItemPricing(lineItemId);
          })
          .catch(() => {
            this.showValidationToast(
              "Unable to save sequence changes. Please try again."
            );
          })
          .finally(() => {
            this._clearModalSaveLock();
          });
        return;
      }

      this.isModalSaveInProgress = true;
      const vectorId = this.lineItemVectorIdForApexFromModal();
      const shouldUpdateVector = this.showVectorSelection && vectorId;

      updateSequenceForLineItem({
        lineItemId,
        sequenceName: this.sequenceName,
        sequence: this.sequenceText,
        vectorId: shouldUpdateVector ? vectorId : null
      })
        .then((result) => {
          if (!result?.success) {
            throw new Error(
              result?.error || "Unable to save sequence changes."
            );
          }
          this._applyUpdatedSequenceToLocal(lineItemId, updatedLocal);
          this.handleCloseManualModal(true);
          this._pollLineItemPricing(lineItemId);
        })
        .catch(() => {
          this.showValidationToast(
            "Unable to save sequence changes. Please try again."
          );
        })
        .finally(() => {
          this._clearModalSaveLock();
        });
      return;
    }

    // Create new sequence – save to Salesforce
    if (!this.currentQuoteRequestId) {
      return;
    }

    const sequenceName = this.sequenceName;
    const sequenceText = this.sequenceText;
    const vectorId = this.lineItemVectorIdForApexFromModal();
    const vectorValue = this.vectorValueForSequenceRow();
    const sequenceCharCount = this.sequenceCharCount;

    this.isModalSaveInProgress = true;
    createQuoteRequestLineItem({
      quoteRequestId: this.currentQuoteRequestId,
      sequenceName,
      sequence: sequenceText,
      vectorId,
      potentiallyToxic: false,
      glycerolStock: this._serverGlycerolStockOnCreate(),
      reflexVectorOptIn: false
    })
      .then((result) => {
        const apexLineItem = result || {};
        if (!apexLineItem?.Id) {
          this.showValidationToast(
            "Unable to save sequence to Salesforce. Please try again."
          );
          return;
        }
        const merged = this._mergeLineItemIntoSequence(
          {
            name: sequenceName,
            vector: vectorValue,
            sequence: sequenceText,
            length: sequenceCharCount,
            glycerol: this._effectiveGlycerolStock(this.isGlycerol)
          },
          apexLineItem
        );
        this._sequences = [...this._sequences, merged];
        this.currentStep = 3;
        this.handleCloseManualModal(true);
        this._ensureTrailingEmptyDraftRow();
        this._pollLineItemPricing(apexLineItem.Id);
      })
      .catch((error) => {
        console.error("Error creating sequence record:", error);
        this.showValidationToast(
          "Unable to save sequence to Salesforce. Please try again."
        );
      })
      .finally(() => {
        this._clearModalSaveLock();
      });
  }

  _snapshotFromModalFields() {
    return {
      name: (this.sequenceName || "").trim(),
      sequence: (this.sequenceText || "").trim(),
      vector: this.vectorValueForSequenceRow()
    };
  }

  _isSequenceEditUnchanged(existing) {
    if (!this._editOriginalSnapshot || !existing) {
      return false;
    }
    const current = this._snapshotFromModalFields();
    const original = this._editOriginalSnapshot;
    return (
      current.name === original.name &&
      current.sequence === original.sequence &&
      current.vector === original.vector
    );
  }

  _pollLineItemPricing(lineItemId) {
    if (!lineItemId) {
      return Promise.resolve();
    }
    const pollPromise = getLineItemPricing({ lineItemId })
      .then((li) => {
        if (li) {
          const updated = this._applyLineItemPricingToSequence(lineItemId, li);
          if (updated && !this._hasPendingLineItemCalculations()) {
            this._stopLineItemPolling();
          }
        }
      })
      .catch(() => {
        // interval polling will retry
      });
    this._startLineItemPolling();
    return pollPromise;
  }

  _pollLineItemPricingUntilGlycerolSettled(lineItemId, attempt = 0) {
    if (!lineItemId) {
      return Promise.resolve();
    }
    return getLineItemPricing({ lineItemId })
      .then((li) => {
        const seq = (this._sequences || []).find(
          (s) => String(s.id) === String(lineItemId)
        );
        if (li) {
          this._applyLineItemPricingToSequence(lineItemId, li);
        }
        if (li && seq && this._isGlycerolPricingSettled(li, seq)) {
          this._removeGlycerolUpdating(lineItemId);
          if (!this._hasPendingLineItemCalculations()) {
            this._stopLineItemPolling();
          }
          return;
        }
        if (attempt >= GLYCEROL_POLL_MAX_ATTEMPTS) {
          this._removeGlycerolUpdating(lineItemId);
          return;
        }
        this._startLineItemPolling();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        return new Promise((resolve) => {
          setTimeout(() => {
            resolve(
              this._pollLineItemPricingUntilGlycerolSettled(
                lineItemId,
                attempt + 1
              )
            );
          }, GLYCEROL_POLL_DELAY_MS);
        });
      })
      .catch(() => {
        if (attempt >= GLYCEROL_POLL_MAX_ATTEMPTS) {
          this._removeGlycerolUpdating(lineItemId);
          return;
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        return new Promise((resolve) => {
          setTimeout(() => {
            resolve(
              this._pollLineItemPricingUntilGlycerolSettled(
                lineItemId,
                attempt + 1
              )
            );
          }, GLYCEROL_POLL_DELAY_MS);
        });
      });
  }

  _startStep4PollingForPendingSequences() {
    this._startPollingForPendingLineItems();
  }

  addSequenceLocally() {
    this._sequences = [
      ...this._sequences,
      {
        id: Date.now(),
        name: this.sequenceName,
        vector: this.vectorValueForSequenceRow(),
        sequence: this.sequenceText,
        length: this.sequenceCharCount,
        glycerol: this._effectiveGlycerolStock(this.isGlycerol)
      }
    ];
    this.showStep2ValidationError = false;
    this.step2UploadErrorMessage = "";
    this.currentStep = 3;
    this.handleCloseManualModal();
  }

  formatDateForDisplay(dateValue) {
    if (!dateValue) {
      return null;
    }
    if (/^\d{4}-\d{2}-\d{2}$/.test(dateValue)) {
      const [y, m, d] = dateValue.split("-");
      return `${m}/${d}/${y.slice(-2)}`;
    }
    if (typeof dateValue === "string" && dateValue.includes("T")) {
      const datePart = dateValue.split("T")[0];
      if (/^\d{4}-\d{2}-\d{2}$/.test(datePart)) {
        const [y, m, d] = datePart.split("-");
        return `${m}/${d}/${y.slice(-2)}`;
      }
    }
    const asDate = new Date(dateValue);
    if (Number.isNaN(asDate.getTime())) {
      return null;
    }
    const mm = String(asDate.getMonth() + 1).padStart(2, "0");
    const dd = String(asDate.getDate()).padStart(2, "0");
    const yy = String(asDate.getFullYear()).slice(-2);
    return `${mm}/${dd}/${yy}`;
  }

  // ─── Step 3 handlers ────────────────────────────────────────────────

  get hasSequences() {
    return this._sequences && this._sequences.length > 0;
  }

  get pdfLineItems() {
    return (this._sequences || []).map((seq) => ({
      id: seq.id,
      sequenceName: seq.name,
      productName:
        formatProductName(seq.productName) || this.productName || "NA",
      length: seq.length,
      quantity: seq.quantity ?? 1,
      formattedPrice: (seq.totalPrice || "$0.00")
        .replace("$", "")
        .replace(",", "")
    }));
  }

  get endUserPdfLineItems() {
    return (this._sequences || []).map((seq) => ({
      id: seq.id,
      sequenceName: seq.name,
      productName:
        formatProductName(seq.productName) || this.productName || "NA",
      length: seq.length,
      quantity: seq.quantity ?? 1,
      formattedEndCustomerPrice: seq.endCustomerPrice || "0.00"
    }));
  }

  // True when the user's account has "IDT Channel Partner" ticked
  // (Account.IDT_Channel_Partner__c). Set in loadModalData.
  get isIDTChannelPartnership() {
    return this.currentAccountIsIdtChannelPartner === true;
  }

  get quoteRequestCreatedDate() {
    return this.quoteRequestInfo.createdDate || "NA";
  }

  get showPdfDiscount() {
    return !!this.quoteRequestInfo.formattedDiscount;
  }

  get isPdfDisabled() {
    return !this.hasSequences;
  }

  get allSequencesSelected() {
    if (!this.hasSequences) {
      return false;
    }
    return this._sequences.every((seq) => seq.selected);
  }

  get selectedSequences() {
    return (this._sequences || []).filter((seq) => seq.selected);
  }

  get hasSelectedSequences() {
    return this.selectedSequences.length > 0;
  }

  get showVectorBulkSelection() {
    return this.showVectorSelection;
  }

  get showBulkReflexSelection() {
    const selected = this.selectedSequences;
    if (!selected.length) {
      return false;
    }
    if (
      this.bulkVectorValue &&
      this._isReflexApplicableVector(this.bulkVectorValue)
    ) {
      return true;
    }
    return selected.every((seq) => this._isReflexApplicableVector(seq.vector));
  }

  get hasAnyReflexApplicableVector() {
    return (this._sequences || []).some((seq) =>
      this._isReflexApplicableVector(seq.vector)
    );
  }

  get showBulkSequenceActions() {
    return this.hasSelectedSequences;
  }

  get showGlycerolBulkActions() {
    return this.hasSelectedSequences && this.isGlycerolApplicable;
  }

  get isBulkUpdateInProgress() {
    return this._bulkUpdateCount > 0;
  }

  get isBulkToxicDisabled() {
    return this.isBulkUpdateInProgress;
  }

  get isBulkReflexDisabled() {
    return this.isBulkUpdateInProgress;
  }

  get isBulkVectorDisabled() {
    return this.isBulkUpdateInProgress;
  }

  get isBulkGlycerolDisabled() {
    return this.isGlycerolSelectionDisabled || this.isBulkUpdateInProgress;
  }

  get headerBulkSlotClass() {
    return "step4-packaging-column step4-bulk-action-slot";
  }

  get sequencesWithDisplay() {
    const duplicateNameKeys = getDuplicateSequenceNameKeys(this._sequences);
    return (this._sequences || []).map((seq, seqIndex) => {
      const sequence = seq.sequence || "";
      const validation = this.validateSequenceCharacters(sequence);
      const hasLengthMismatch = this.isSequenceLengthOutOfRange(sequence);
      const truncated = sequence ? sequence.substring(0, 40) + "..." : "";
      const nameKey = normalizeSequenceNameForCompare(seq.name);
      const nameValidationError = getSequenceNameValidationError(
        seq.name,
        SEQUENCE_NAME_MAX_LENGTH
      );
      const isDuplicateName = !!nameKey && duplicateNameKeys.has(nameKey);
      const nameError =
        nameValidationError ||
        (isDuplicateName ? DUPLICATE_SEQUENCE_NAME_ERROR : "");
      const vectorError = getSequenceVectorValidationError(
        seq.vector,
        this.isVectorRequired
      );

      // Create array of character objects for template iteration
      const validChars = new Set(["A", "T", "C", "G"]);
      const sequenceChars = truncated.split("").map((char, charIndex) => ({
        char: char,
        index: `${seqIndex}-${charIndex}`,
        isInvalid: char !== "." && !validChars.has(char.toUpperCase())
      }));

      const sequenceHighlighted = sequenceChars
        .map((c) =>
          c.isInvalid
            ? `<span style="color:#c23934;font-weight:bold">${c.char}</span>`
            : c.char
        )
        .join("");

      return {
        ...seq,
        sequenceTruncated: truncated,
        sequenceChars: sequenceChars,
        sequenceHighlighted: sequenceHighlighted,
        hasInvalidChars: !validation.isValid,
        hasInvalidName: !!nameValidationError,
        nameError,
        nameTooltip: nameError || seq.name,
        hasDuplicateName: isDuplicateName,
        hasMissingVector: !!vectorError,
        vectorError,
        hasLengthMismatch: hasLengthMismatch,
        hasValidationIssue:
          !validation.isValid ||
          hasLengthMismatch ||
          !!nameError ||
          !!vectorError,
        feasibility:
          seq.feasibility ||
          (seq.savedToSalesforce ? "Pending" : "Not Submitted"),
        potentiallyToxic: seq.potentiallyToxic === true,
        reflexVectorOptIn: seq.reflexVectorOptIn === true,
        glycerol: seq.glycerol === true,
        isGlycerolUpdating: this._isGlycerolUpdatingLine(seq.id),
        isDeleting: this._isDeletingSequence(seq.id),
        glycerolCheckboxDisabled:
          this.isGlycerolSelectionDisabled ||
          this._isGlycerolUpdatingLine(seq.id) ||
          seq.scaleUpSelected === true ||
          this._isScaleUpUpdatingLine(seq.id),
        scaleUpSelected: seq.scaleUpSelected === true,
        isScaleUpUpdating: this._isScaleUpUpdatingLine(seq.id),
        scaleUpPopoverOpen:
          String(this._scaleUpPopoverLineId) === String(seq.id),
        scaleUpSaving: this._isScaleUpSavingLine(seq.id),
        scaleUpCheckboxDisabled:
          this.isScaleUpSelectionDisabled ||
          this._isScaleUpUpdatingLine(seq.id) ||
          this._isScaleUpSavingLine(seq.id),
        scaleUpConfigured:
          seq.scaleUpSelected === true && !!seq.scaleUpQuantity,
        scaleUpCopyNumber: this._copyNumberForVector(seq.vector),
        totalSelectedCount: this.totalSelectedSequenceCount,
        totalLineCount: this.totalSequenceCount,
        selected: seq.selected || false,
        complexity:
          seq.complexity ||
          (seq.savedToSalesforce ? "Pending" : "Not Submitted"),
        asEarlyAsDate: seq.asEarlyAsDate || "Pending",
        guaranteedDate: seq.guaranteedDate || "Pending",
        tranche: seq.tranche || trancheDisplay(seq),
        scaleUp: seq.scaleUp || "",
        additionalFees: this._formatAdditionalFeesDisplay(
          this._sequenceForFeeDisplay(seq)
        ),
        totalPrice: seq.totalPrice || "$0.00",
        showReflexOptIn: this._isReflexApplicableVector(seq.vector),
        showHomopolymerFlag: seq.recommendNotHighCopyNumVector === true,
        reflexPopoverOpen: String(this._reflexPopoverLineId) === String(seq.id),
        vectorCellClass: `step3-td step3-td-vector${
          String(this._reflexPopoverLineId) === String(seq.id)
            ? " step3-td-vector--popover-open"
            : ""
        }`
      };
    });
  }

  get draftRowsWithDisplay() {
    const namePeers = this._rowsForDraftNameValidation();
    return (this._draftRows || []).map((draft) => {
      const sequence = draft.sequence || "";
      const showValidation = this._shouldShowDraftValidation(draft);
      const nameValidationError = this._getDraftNameValidationError(
        draft,
        namePeers
      );
      const sequenceValidationError =
        this._getDraftSequenceValidationError(draft);
      const vectorError = showValidation
        ? getSequenceVectorValidationError(draft.vector, this.isVectorRequired)
        : "";
      const hasInvalidChars = !!sequenceValidationError;
      const length = sequence.length || 0;
      return {
        ...draft,
        rowClass: draft.isSaving
          ? "step3-row step3-row--draft step3-row--draft-saving"
          : "step3-row step3-row--draft",
        lengthDisplay: length > 0 ? String(length) : "",
        hasInvalidName: !!nameValidationError,
        nameTooltip: nameValidationError || "",
        hasInvalidChars,
        sequenceTooltip: sequenceValidationError || "",
        hasMissingVector: !!vectorError,
        nameInputClass: nameValidationError
          ? "step3-draft-input step3-draft-input--error"
          : "step3-draft-input",
        sequenceInputClass: hasInvalidChars
          ? "step3-draft-input step3-draft-input--seq step3-draft-input--error"
          : "step3-draft-input step3-draft-input--seq"
      };
    });
  }

  _createEmptyDraftRow() {
    return {
      id: this._generateLocalId("draft"),
      name: "",
      sequence: "",
      vector: this._effectiveSelectedVector(),
      potentiallyToxic: false,
      isSaving: false,
      showValidation: false
    };
  }

  _isDraftRowEmpty(draft) {
    return !(draft?.name || "").trim() && !(draft?.sequence || "").trim();
  }

  /** True after Next — surface inline/banner validation for this draft. */
  _shouldShowDraftValidation(draft) {
    return (
      this._submittedDraftValidation === true &&
      draft?.showValidation === true &&
      !this._isDraftRowEmpty(draft)
    );
  }

  _getDraftNameValidationError(draft, namePeers) {
    if (!this._shouldShowDraftValidation(draft)) {
      return "";
    }
    const name = (draft?.name || "").trim();
    if (!name) {
      // Name required once the user has entered a sequence (or other draft content).
      return (draft?.sequence || "").trim() ? "Sequence name is required" : "";
    }
    return (
      getSequenceNameErrorForRow(
        draft.name,
        namePeers || this._rowsForDraftNameValidation(),
        draft.id
      ) || ""
    );
  }

  _getDraftSequenceValidationError(draft) {
    if (this._isDraftRowEmpty(draft)) {
      return "";
    }
    const sequence = draft?.sequence || "";
    if (!sequence.trim()) {
      if (!this._submittedDraftValidation) {
        return "";
      }
      return (draft?.name || "").trim() ? "Sequence is required" : "";
    }
    const validation = this.validateSequenceCharacters(sequence);
    if (!validation.isValid) {
      return `Sequence contains invalid characters. Allowed: ${getAllowedSequenceCharactersText(this.allowedSequenceCharacters)}.`;
    }
    const length = sequence.length;
    const min = this.sequenceLengthLimits.min;
    const max = this.sequenceLengthLimits.max;
    if (length > max) {
      return `Sequence length must be between ${min} and ${max} bp.`;
    }
    if (length < min && this._submittedDraftValidation) {
      return `Sequence length must be between ${min} and ${max} bp.`;
    }
    return "";
  }

  _clearDraftValidationTimer(draftId) {
    const key = String(draftId);
    const timer = this._draftValidationTimers?.get(key);
    if (timer) {
      clearTimeout(timer);
      this._draftValidationTimers.delete(key);
    }
  }

  _clearAllDraftValidationTimers() {
    if (!this._draftValidationTimers) {
      return;
    }
    this._draftValidationTimers.forEach((timer) => clearTimeout(timer));
    this._draftValidationTimers.clear();
  }

  /** Surface inline/banner validation for every non-empty draft (Next click). */
  _enableAllDraftValidation() {
    this._clearAllDraftValidationTimers();
    this._draftRows = (this._draftRows || []).map((draft) => ({
      ...draft,
      showValidation: !this._isDraftRowEmpty(draft)
    }));
  }

  _rowsForDraftNameValidation(excludeDraftId) {
    const sequences = this._sequences || [];
    const drafts = (this._draftRows || [])
      .filter(
        (d) => excludeDraftId == null || String(d.id) !== String(excludeDraftId)
      )
      .map((d) => ({ id: d.id, name: d.name }));
    return [...sequences, ...drafts];
  }

  _isDraftRowValidForSave(draft) {
    if (!draft || this._isDraftRowEmpty(draft)) {
      return false;
    }
    if (!(draft.name || "").trim()) {
      return false;
    }
    if (!(draft.sequence || "").trim()) {
      return false;
    }
    return (
      this._isSequenceValidForSave(draft.sequence) &&
      !getSequenceNameErrorForRow(
        draft.name,
        this._rowsForDraftNameValidation(draft.id),
        draft.id
      ) &&
      !getSequenceVectorValidationError(draft?.vector, this.isVectorRequired)
    );
  }

  _ensureTrailingEmptyDraftRow() {
    // Keep any filled draft rows and ensure exactly one empty trailing row.
    // Do NOT overwrite an existing empty draft's vector here — that resets user
    // dropdown changes. New empty rows get the working default via _createEmptyDraftRow.
    const rows = this._draftRows || [];
    const nonEmpty = rows.filter(
      (r) => !this._isDraftRowEmpty(r) || r.isSaving
    );
    const trailingEmpty = rows.find(
      (r) => this._isDraftRowEmpty(r) && !r.isSaving
    );

    if (nonEmpty.length === 0 && !trailingEmpty) {
      this._draftRows = [this._createEmptyDraftRow()];
      return;
    }
    if (!trailingEmpty) {
      this._draftRows = [...nonEmpty, this._createEmptyDraftRow()];
      return;
    }
    const normalized = [...nonEmpty, trailingEmpty];
    const unchanged =
      normalized.length === rows.length &&
      normalized.every(
        (row, index) => String(row.id) === String(rows[index].id)
      );
    if (!unchanged) {
      this._draftRows = normalized;
    }
  }

  _updateDraftRow(draftId, patch) {
    this._draftRows = (this._draftRows || []).map((row) =>
      String(row.id) === String(draftId) ? { ...row, ...patch } : row
    );
    // When the user starts filling the trailing empty row, keep another empty row below.
    this._ensureTrailingEmptyDraftRow();
  }

  handleDraftNameInput(event) {
    event.stopPropagation();
    const id = event.currentTarget.dataset.id;
    this._submittedDraftValidation = false;
    this._updateDraftRow(id, { name: event.target.value });
  }

  handleDraftSequenceInput(event) {
    event.stopPropagation();
    const id = event.currentTarget.dataset.id;
    this._submittedDraftValidation = false;
    this._updateDraftRow(id, { sequence: event.target.value });
  }

  handleDraftVectorChange(event) {
    event.stopPropagation();
    const id = event.currentTarget.dataset.id;
    const val = event.detail?.value;
    if (!id) {
      return;
    }
    const normalized = !val || val === "none" ? "" : val;
    // Promote draft selection to the working default for new/empty rows.
    if (this.showVectorSelection) {
      this.selectedVector = normalized;
      this._syncEmptyDraftVectorsFromSelection();
    }
    this._updateDraftRow(id, { vector: normalized });
    this._tryCommitDraftRow(id);
  }

  handleDraftToxicChange(event) {
    event.stopPropagation();
    const id = event.currentTarget.dataset.id;
    if (!id) {
      return;
    }
    this._updateDraftRow(id, {
      potentiallyToxic: event.target.checked === true
    });
  }

  handleDraftBlur(event) {
    event.stopPropagation();
    const id = event.currentTarget.dataset.id;
    if (!id) {
      return;
    }
    // Defer so focus moves within the same draft row don't cancel a pending commit race.
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(() => this._tryCommitDraftRow(id), 0);
  }

  _parseSpreadsheetPaste(text) {
    const raw = (text || "").replace(/\r\n/g, "\n").replace(/\r/g, "\n");
    const lines = raw
      .split("\n")
      .map((line) => line.trim())
      .filter(Boolean);
    if (!lines.length) {
      return null;
    }
    const parseLine = (line) => {
      if (line.includes("\t")) {
        const parts = line.split("\t");
        return {
          name: (parts[0] || "").trim(),
          sequence: parts.slice(1).join("\t").replace(/\s+/g, "").trim()
        };
      }
      if (line.includes(",")) {
        const parts = line.split(",");
        const maybeSeq = parts[parts.length - 1].replace(/\s/g, "");
        if (parts.length >= 2 && /^[ACGTRYSWKMBDHVN]+$/i.test(maybeSeq)) {
          return {
            name: parts.slice(0, -1).join(",").trim(),
            sequence: maybeSeq
          };
        }
      }
      // Tabs often become spaces when copying from chat/docs: "Name SEQUENCE"
      const spaced = line.split(/\s+/).filter(Boolean);
      if (spaced.length >= 2) {
        const maybeSeq = spaced[spaced.length - 1];
        if (/^[ACGTRYSWKMBDHVN]+$/i.test(maybeSeq)) {
          return {
            name: spaced.slice(0, -1).join(" ").trim(),
            sequence: maybeSeq
          };
        }
      }
      return { name: "", sequence: line.replace(/\s/g, "") };
    };
    const looksLikeSpreadsheet = lines.some(
      (line) =>
        line.includes("\t") ||
        line.includes(",") ||
        /\s+[ACGTRYSWKMBDHVN]{8,}\s*$/i.test(line)
    );
    if (lines.length === 1 && !looksLikeSpreadsheet) {
      return null;
    }
    if (lines.length >= 1 && looksLikeSpreadsheet) {
      return lines.map(parseLine);
    }
    return null;
  }

  handleDraftPaste(event) {
    const clipboard = event.clipboardData;
    const text =
      clipboard?.getData("text/plain") || clipboard?.getData("text") || "";
    const parsed = this._parseSpreadsheetPaste(text);
    if (!parsed || !parsed.length) {
      return;
    }
    event.preventDefault();
    event.stopPropagation();
    const startId = event.currentTarget.dataset.id;
    const draft = (this._draftRows || []).find(
      (d) => String(d.id) === String(startId)
    );
    if (!draft) {
      return;
    }

    const vectorForRows = draft.vector || this._effectiveSelectedVector();

    // Paste fills drafts, then immediately creates valid rows in Salesforce
    // (Feasibility via _pollLineItemPricing). Invalid rows stay as drafts with errors.
    const otherDrafts = (this._draftRows || []).filter(
      (row) =>
        String(row.id) !== String(startId) &&
        (!this._isDraftRowEmpty(row) || row.isSaving)
    );
    const pastedDrafts = parsed
      .map((item) => {
        const name = (item.name || "").trim();
        const sequence = (item.sequence || "").replace(/\s/g, "");
        if (!name && !sequence) {
          return null;
        }
        return {
          ...this._createEmptyDraftRow(),
          name,
          sequence,
          vector: vectorForRows,
          potentiallyToxic: draft.potentiallyToxic === true,
          showValidation: true
        };
      })
      .filter(Boolean);

    this._clearAllDraftValidationTimers();
    this._draftRows = [
      ...otherDrafts,
      ...pastedDrafts,
      {
        ...this._createEmptyDraftRow(),
        vector: vectorForRows
      }
    ];

    const validPasted = pastedDrafts.filter((row) =>
      this._isDraftRowValidForSave(row)
    );
    if (validPasted.length) {
      this._commitValidDraftRows(validPasted);
    }
  }

  _appendMergedSequences(mergedList) {
    if (!mergedList?.length) {
      return;
    }
    const next = [...(this._sequences || [])];
    mergedList.forEach((merged) => {
      const id = String(merged.id);
      const idx = next.findIndex((s) => String(s.id) === id);
      if (idx >= 0) {
        next[idx] = merged;
      } else {
        next.push(merged);
      }
    });
    this._sequences = next;
  }

  _localSequenceFromDraft(draft) {
    const sequenceText = draft.sequence || "";
    const vectorValue = this.showVectorSelection
      ? draft.vector && draft.vector !== "none"
        ? draft.vector
        : ""
      : "";
    return {
      name: (draft.name || "").trim(),
      vector: vectorValue,
      sequence: sequenceText,
      length: sequenceText.length,
      potentiallyToxic: draft.potentiallyToxic === true,
      glycerol: this._effectiveGlycerolStock(this.isGlycerol)
    };
  }

  /**
   * Batch-create valid draft rows so multi-paste cannot race `_sequences` updates
   * and every inserted line item starts Feasibility polling.
   */
  _commitValidDraftRows(drafts) {
    const rows = (drafts || []).filter(
      (d) => d && this._isDraftRowValidForSave(d) && !d.isSaving
    );
    if (!rows.length) {
      return Promise.resolve();
    }
    if (!this.currentQuoteRequestId) {
      this.showValidationToast(
        "Unable to save sequence. Quote request is not ready."
      );
      return Promise.resolve();
    }

    const draftIds = rows.map((d) => String(d.id));
    this._draftRows = (this._draftRows || []).map((row) =>
      draftIds.includes(String(row.id)) ? { ...row, isSaving: true } : row
    );

    const sequenceNames = rows.map((d) => (d.name || "").trim());
    const sequences = rows.map((d) => d.sequence || "");
    const vectorIds = rows.map((d) => this.lineItemVectorIdForApexFromSeq(d));
    const potentiallyToxicFlags = rows.map((d) => d.potentiallyToxic === true);
    const glycerolStockFlags = rows.map(() =>
      this._serverGlycerolStockOnCreate()
    );
    const reflexVectorOptInFlags = rows.map(() => false);

    const run = () =>
      createQuoteRequestLineItemsChunked(
        createQuoteRequestLineItemsDeferredKick,
        {
          quoteRequestId: this.currentQuoteRequestId,
          sequenceNames,
          sequences,
          vectorIds,
          potentiallyToxicFlags,
          glycerolStockFlags,
          reflexVectorOptInFlags,
          afterAll: () =>
            enqueuePendingForQuoteRequest({
              quoteRequestId: this.currentQuoteRequestId
            })
        }
      )
        .then((results) => {
          const mergedList = [];
          const insertedIds = [];
          const successDraftIds = new Set();
          rows.forEach((draft, idx) => {
            const inserted = results?.[idx];
            if (!inserted?.Id) {
              this._updateDraftRow(draft.id, { isSaving: false });
              return;
            }
            successDraftIds.add(String(draft.id));
            this._clearDraftValidationTimer(draft.id);
            mergedList.push(
              this._mergeLineItemIntoSequence(
                this._localSequenceFromDraft(draft),
                inserted
              )
            );
            insertedIds.push(inserted.Id);
          });
          if (successDraftIds.size) {
            this._draftRows = (this._draftRows || []).filter(
              (d) => !successDraftIds.has(String(d.id))
            );
            this._ensureTrailingEmptyDraftRow();
            this._appendMergedSequences(mergedList);
            insertedIds.forEach((lineItemId) =>
              this._pollLineItemPricing(lineItemId)
            );
            this._startPollingForPendingLineItems();
          }
          if (successDraftIds.size < rows.length) {
            this.showValidationToast(
              "Unable to save one or more sequences to Salesforce. Please try again."
            );
          }
        })
        .catch((error) => {
          console.error("Error creating sequences from draft rows:", error);
          rows.forEach((draft) =>
            this._updateDraftRow(draft.id, { isSaving: false })
          );
          this.showValidationToast(
            "Unable to save sequence to Salesforce. Please try again."
          );
        });

    this._draftCommitTail = this._draftCommitTail.then(run, run);
    return this._draftCommitTail;
  }

  _tryCommitDraftRow(draftId) {
    const draft = (this._draftRows || []).find(
      (d) => String(d.id) === String(draftId)
    );
    if (!draft || draft.isSaving || this._isDraftRowEmpty(draft)) {
      return;
    }
    if (!this._isDraftRowValidForSave(draft)) {
      return;
    }
    this._commitValidDraftRows([draft]);
  }

  stopProp(event) {
    event.stopPropagation();
  }

  handleSelectAll(event) {
    event.stopPropagation();
    const checked = event.target.checked;
    this._sequences = this._sequences.map((seq) => ({
      ...seq,
      selected: checked
    }));
    this._syncBulkControlsAfterSelectionChange();
  }

  handleCheckboxClick(event) {
    event.stopPropagation();
    const id = event.target.dataset.id;
    const checked = event.target.checked;
    this._sequences = this._sequences.map((seq) =>
      String(seq.id) === String(id) ? { ...seq, selected: checked } : seq
    );
    this._syncBulkControlsAfterSelectionChange();
  }

  _syncBulkControlsAfterSelectionChange() {
    if (!this.hasSelectedSequences) {
      this.bulkToxicChecked = false;
      this.bulkReflexChecked = false;
      this.bulkGlycerolChecked = false;
      this.bulkVectorValue = "";
    }
  }

  _getSelectedSequencesOrWarn() {
    const selected = this.selectedSequences;
    if (!selected.length) {
      this.showValidationToast("Please select at least one sequence.");
      return null;
    }
    return selected;
  }

  _beginBulkUpdate() {
    this._bulkUpdateCount += 1;
  }

  _endBulkUpdate() {
    this._bulkUpdateCount = Math.max(0, this._bulkUpdateCount - 1);
  }

  handleBulkVectorChange(event) {
    event.stopPropagation();
    if (this.isBulkUpdateInProgress) {
      return;
    }
    if (!this.showVectorBulkSelection) {
      return;
    }
    const val = event.detail?.value ?? event.target.value;
    if (!val) {
      return;
    }

    const selected = this._getSelectedSequencesOrWarn();
    if (!selected) {
      this.bulkVectorValue = "";
      return;
    }

    const selectedIds = new Set(selected.map((seq) => String(seq.id)));
    const snapshots = new Map(
      selected.map((seq) => [String(seq.id), { ...seq }])
    );
    const nextIsReflexApplicable = this._isReflexApplicableVector(val);
    const vectorId = this.lineItemVectorIdForApexFromSeq({ vector: val });
    const savedIds = selected
      .filter((seq) => seq.savedToSalesforce)
      .map((seq) => seq.id);

    this.bulkVectorValue = val;
    this.bulkReflexChecked = false;

    this._sequences = this._sequences.map((seq) => {
      if (!selectedIds.has(String(seq.id))) {
        return seq;
      }
      const markPending = !!seq.savedToSalesforce;
      return {
        ...seq,
        vector: val,
        ...(nextIsReflexApplicable ? {} : { reflexVectorOptIn: false }),
        ...(markPending
          ? {
              feasibility: "Pending",
              complexity: "Pending",
              feasibilityJson: "",
              feasibilityExplained1: "",
              feasibilityExplained2: "",
              feasibilityExplained3: ""
            }
          : {})
      };
    });

    selected.forEach((seq) => {
      if (!nextIsReflexApplicable && seq.reflexVectorOptIn) {
        this._clearReflexOptInForSequence(seq.id, seq);
      }
    });

    if (!savedIds.length) {
      this._persistValidUnsavedSequences();
      return;
    }

    this._beginBulkUpdate();
    bulkUpdateQuoteLineItemVectors({
      lineItemIds: savedIds,
      vectorId
    })
      .then((result) => {
        if (result?.success) {
          savedIds.forEach((id) => this._pollLineItemPricing(id));
          return;
        }
        this._sequences = this._sequences.map((seq) => {
          const snapshot = snapshots.get(String(seq.id));
          return snapshot || seq;
        });
        this.showValidationToast(result?.error || "Failed to update vector.");
      })
      .catch((err) => {
        this._sequences = this._sequences.map((seq) => {
          const snapshot = snapshots.get(String(seq.id));
          return snapshot || seq;
        });
        this.showValidationToast("Failed to update vector. Please try again.");
        console.error("Bulk vector update failed:", err);
      })
      .finally(() => {
        this._endBulkUpdate();
      });
  }

  handleBulkReflexChange(event) {
    event.stopPropagation();
    if (this.isBulkUpdateInProgress) {
      return;
    }
    const reflexVectorOptIn = event.target.checked === true;
    this.bulkReflexChecked = reflexVectorOptIn;
    const selected = this._getSelectedSequencesOrWarn();
    if (!selected) {
      this.bulkReflexChecked = false;
      return;
    }

    const applicable = selected.filter((seq) =>
      this._isReflexApplicableVector(seq.vector)
    );
    if (!applicable.length) {
      this.bulkReflexChecked = false;
      this.showValidationToast(
        "Reflex is only available for sequences with a reflex-applicable vector."
      );
      return;
    }

    const applicableIds = new Set(applicable.map((seq) => String(seq.id)));
    const snapshots = new Map(
      applicable.map((seq) => [String(seq.id), { ...seq }])
    );
    const savedApplicable = applicable.filter((seq) => seq.savedToSalesforce);

    this._sequences = this._sequences.map((seq) =>
      applicableIds.has(String(seq.id)) ? { ...seq, reflexVectorOptIn } : seq
    );

    if (!savedApplicable.length) {
      return;
    }

    this._beginBulkUpdate();
    bulkUpdateQuoteRequestLineItemReflexVectorOptIn({
      lineItemIds: savedApplicable.map((seq) => seq.id),
      reflexVectorOptInFlags: savedApplicable.map(() => reflexVectorOptIn)
    })
      .then((result) => {
        if (!result?.success) {
          throw new Error(
            result?.error || "Failed to save reflex vector opt-in."
          );
        }
        const byId = new Map(
          (result.lines || []).map((line) => [
            String(line.id),
            line.reflexVectorOptIn === true
          ])
        );
        this._sequences = this._sequences.map((seq) => {
          if (!applicableIds.has(String(seq.id))) {
            return seq;
          }
          if (!byId.has(String(seq.id))) {
            return { ...seq, reflexVectorOptIn };
          }
          return { ...seq, reflexVectorOptIn: byId.get(String(seq.id)) };
        });
      })
      .catch((err) => {
        this.bulkReflexChecked = !reflexVectorOptIn;
        this._sequences = this._sequences.map((seq) => {
          const snapshot = snapshots.get(String(seq.id));
          return snapshot || seq;
        });
        this.showValidationToast("Failed to save reflex vector opt-in.");
        console.error("Bulk reflex update failed:", err);
      })
      .finally(() => {
        this._endBulkUpdate();
      });
  }

  handleBulkToxicChange(event) {
    event.stopPropagation();
    if (this.isBulkUpdateInProgress) {
      return;
    }
    const potentiallyToxic = event.target.checked === true;
    this.bulkToxicChecked = potentiallyToxic;
    const selected = this._getSelectedSequencesOrWarn();
    if (!selected) {
      this.bulkToxicChecked = false;
      return;
    }

    const selectedIds = new Set(selected.map((seq) => String(seq.id)));
    const snapshots = new Map(
      selected.map((seq) => [String(seq.id), { ...seq }])
    );
    const savedSelected = selected.filter((seq) => seq.savedToSalesforce);

    this._sequences = this._sequences.map((seq) =>
      selectedIds.has(String(seq.id)) ? { ...seq, potentiallyToxic } : seq
    );

    if (!savedSelected.length) {
      return;
    }

    this._beginBulkUpdate();
    bulkUpdateQuoteRequestLineItemPotentiallyToxic({
      lineItemIds: savedSelected.map((seq) => seq.id),
      potentiallyToxicFlags: savedSelected.map(() => potentiallyToxic)
    })
      .then((result) => {
        if (!result?.success) {
          throw new Error(result?.error || "Potentially Toxic update failed");
        }
        const byId = new Map(
          (result.lines || []).map((line) => [
            String(line.id),
            line.potentiallyToxic === true
          ])
        );
        this._sequences = this._sequences.map((seq) => {
          if (!selectedIds.has(String(seq.id))) {
            return seq;
          }
          if (!byId.has(String(seq.id))) {
            return { ...seq, potentiallyToxic };
          }
          return { ...seq, potentiallyToxic: byId.get(String(seq.id)) };
        });
      })
      .catch((err) => {
        this.bulkToxicChecked = !potentiallyToxic;
        this._sequences = this._sequences.map((seq) => {
          const snapshot = snapshots.get(String(seq.id));
          return snapshot || seq;
        });
        this.showValidationToast(
          "Failed to update Potentially Toxic. Please try again."
        );
        console.error("Bulk toxic update failed:", err);
      })
      .finally(() => {
        this._endBulkUpdate();
      });
  }

  handleBulkGlycerolChange(event) {
    event.stopPropagation();
    if (this.isBulkUpdateInProgress) {
      return;
    }
    if (!this.isGlycerolApplicable || this.isGlycerolSelectionDisabled) {
      this.bulkGlycerolChecked = false;
      return;
    }
    const glycerol = event.target.checked === true;
    this.bulkGlycerolChecked = glycerol;
    const selected = this._getSelectedSequencesOrWarn();
    if (!selected) {
      this.bulkGlycerolChecked = false;
      return;
    }

    const selectedIds = new Set(selected.map((seq) => String(seq.id)));
    const snapshots = new Map(
      selected.map((seq) => [String(seq.id), { ...seq }])
    );
    const savedSelected = selected.filter((seq) => seq.savedToSalesforce);

    this._sequences = this._sequences.map((seq) =>
      selectedIds.has(String(seq.id))
        ? this._withAdditionalFees({
            ...seq,
            glycerol,
            glycerolFee: glycerol ? seq.glycerolFee : null,
            totalPrice: this._adjustTotalPriceForGlycerolToggle(seq, glycerol)
          })
        : seq
    );

    if (!savedSelected.length) {
      return;
    }

    this._beginBulkUpdate();
    savedSelected.forEach((seq) => this._addGlycerolUpdating(seq.id));
    bulkUpdateQuoteRequestLineItemGlycerol({
      lineItemIds: savedSelected.map((seq) => seq.id),
      glycerolStockFlags: savedSelected.map(() => glycerol)
    })
      .then((result) => {
        if (!result?.success) {
          throw new Error(result?.error || "Glycerol update failed");
        }
        const byId = new Map(
          (result.lines || []).map((line) => [String(line.id), line])
        );
        this._sequences = this._sequences.map((seq) => {
          if (!selectedIds.has(String(seq.id))) {
            return seq;
          }
          const line = byId.get(String(seq.id));
          if (!line) {
            return seq;
          }
          const fee = this._formatGlycerolFee(line.glycerolPrice);
          return this._withAdditionalFees({
            ...seq,
            glycerol: line.glycerolStock === true,
            glycerolFee: fee ?? (glycerol ? seq.glycerolFee : null)
          });
        });
        return Promise.all(
          savedSelected.map((seq) =>
            this._pollLineItemPricingUntilGlycerolSettled(seq.id)
          )
        );
      })
      .catch((err) => {
        this.bulkGlycerolChecked = !glycerol;
        this._sequences = this._sequences.map((seq) => {
          const snapshot = snapshots.get(String(seq.id));
          return snapshot || seq;
        });
        this.showValidationToast(
          "Failed to update Glycerol. Please try again."
        );
        console.error("Bulk glycerol update failed:", err);
      })
      .finally(() => {
        savedSelected.forEach((seq) => this._removeGlycerolUpdating(seq.id));
        this._endBulkUpdate();
      });
  }

  handleRowClick(event) {
    const id = event.currentTarget.dataset.id;
    const seq = this._sequences.find((s) => String(s.id) === String(id));
    if (seq) {
      this.sequenceName = seq.name || "";
      this.sequenceVector = this.showVectorSelection ? seq.vector || "" : "";
      this.sequenceText = seq.sequence || "";
      this.sequenceCharCount = seq.sequence ? seq.sequence.length : 0;
      this.editingSequenceId = id;
      this.feasibilityOriginalSequence = seq.sequence || "";
      this.editingFeasibilityJson = seq.feasibilityJson || "";
      this.editingFeasibilityExplained1 = seq.feasibilityExplained1 || "";
      this.editingFeasibilityExplained2 = seq.feasibilityExplained2 || "";
      this.editingFeasibilityExplained3 = seq.feasibilityExplained3 || "";

      this.sequenceNameError = "";
      // Validate the sequence when opening for editing
      if (this.sequenceText) {
        this.validateSequence(this.sequenceText);
      } else {
        this.sequenceError = "";
      }
      this._validateSequenceName(this.sequenceName);
      this._validateSequenceVector(this.sequenceVector);

      this._editOriginalSnapshot = this._snapshotFromModalFields();
      this.showManualInputModal = true;
    }
  }

  handleRowVectorChange(event) {
    event.stopPropagation();
    const id = event.target.dataset.id || event.currentTarget.dataset.id;
    const val = event.detail?.value ?? event.target.value;
    if (!id || !val) return;

    const previous = (this._sequences || []).find(
      (seq) => String(seq.id) === String(id)
    );
    if (!previous) return;

    // Promote row selection to working default for subsequent new/empty drafts.
    if (this.showVectorSelection && val !== "none") {
      this.selectedVector = val;
      this._syncEmptyDraftVectorsFromSelection();
    }

    const markPending = !!previous.savedToSalesforce;
    const nextIsReflexApplicable = this._isReflexApplicableVector(val);
    this._sequences = this._sequences.map((seq) =>
      String(seq.id) === String(id)
        ? {
            ...seq,
            vector: val,
            ...(nextIsReflexApplicable ? {} : { reflexVectorOptIn: false }),
            ...(markPending
              ? {
                  feasibility: "Pending",
                  complexity: "Pending",
                  feasibilityJson: "",
                  feasibilityExplained1: "",
                  feasibilityExplained2: "",
                  feasibilityExplained3: ""
                }
              : {})
          }
        : seq
    );

    if (!nextIsReflexApplicable && previous.reflexVectorOptIn) {
      this._clearReflexOptInForSequence(id, previous);
    }

    if (nextIsReflexApplicable) {
      this._openReflexPopoverForLine(id);
    } else if (String(this._reflexPopoverLineId) === String(id)) {
      this._reflexPopoverLineId = null;
    }

    if (!markPending) {
      this._persistValidUnsavedSequences();
      return;
    }

    updateQuoteLineItemVector({
      lineItemId: id,
      vectorId: this.lineItemVectorIdForApexFromSeq({ vector: val })
    })
      .then((result) => {
        if (result?.success) {
          this._pollLineItemPricing(id);
          return;
        }
        this._sequences = this._sequences.map((seq) =>
          String(seq.id) === String(id) ? previous : seq
        );
        this.showValidationToast(result?.error || "Failed to update vector.");
      })
      .catch((err) => {
        this._sequences = this._sequences.map((seq) =>
          String(seq.id) === String(id) ? previous : seq
        );
        this.showValidationToast("Failed to update vector. Please try again.");
        console.error("Vector update failed:", err);
      });
  }

  handleReflexToggle(event) {
    event.stopPropagation();
    const id = event.currentTarget.dataset.id;
    if (!id) {
      return;
    }
    this._reflexPopoverLineId =
      String(this._reflexPopoverLineId) === String(id) ? null : id;
  }

  handleReflexSave(event) {
    event.stopPropagation();
    const id = event.currentTarget.dataset.id;
    const reflexVectorOptIn = event.detail?.reflexVectorOptIn === true;
    if (!id) {
      return;
    }

    const previous = (this._sequences || []).find(
      (seq) => String(seq.id) === String(id)
    );
    if (!previous) {
      return;
    }

    this._sequences = this._sequences.map((seq) =>
      String(seq.id) === String(id) ? { ...seq, reflexVectorOptIn } : seq
    );
    this._reflexPopoverLineId = null;

    if (!previous.savedToSalesforce) {
      return;
    }

    updateQuoteRequestLineItemReflexVectorOptIn({
      lineItemId: id,
      reflexVectorOptIn
    })
      .then((result) => {
        if (result?.success) {
          this._sequences = this._sequences.map((seq) =>
            String(seq.id) === String(id)
              ? { ...seq, reflexVectorOptIn: result.reflexVectorOptIn === true }
              : seq
          );
          return;
        }
        this._sequences = this._sequences.map((seq) =>
          String(seq.id) === String(id) ? previous : seq
        );
        this.showValidationToast(
          result?.error || "Failed to save reflex vector opt-in."
        );
      })
      .catch((err) => {
        this._sequences = this._sequences.map((seq) =>
          String(seq.id) === String(id) ? previous : seq
        );
        this.showValidationToast("Failed to save reflex vector opt-in.");
        console.error("Reflex vector opt-in save failed:", err);
      });
  }

  handleToxicChange(event) {
    const id = event.target.dataset.id;
    const checked = event.target.checked;
    const previous = (this._sequences || []).find(
      (seq) => String(seq.id) === String(id)
    );
    this._sequences = this._sequences.map((seq) =>
      String(seq.id) === String(id)
        ? { ...seq, potentiallyToxic: checked }
        : seq
    );
    if (!previous?.savedToSalesforce) {
      return;
    }
    updateQuoteRequestLineItemPotentiallyToxic({
      lineItemId: id,
      potentiallyToxic: checked
    })
      .then((result) => {
        if (!result?.success) {
          throw new Error(result?.error || "Potentially Toxic update failed");
        }
        this._sequences = this._sequences.map((seq) =>
          String(seq.id) === String(id)
            ? { ...seq, potentiallyToxic: result.potentiallyToxic === true }
            : seq
        );
      })
      .catch((err) => {
        this._sequences = this._sequences.map((seq) =>
          String(seq.id) === String(id)
            ? { ...seq, potentiallyToxic: previous.potentiallyToxic }
            : seq
        );
        this.showValidationToast(
          "Failed to update Potentially Toxic. Please try again."
        );
        console.error("Potentially Toxic update failed:", err);
      });
  }

  _retryPersistUnsavedSequencesAfterChange() {
    if (!this.hasUnsavedSequences || !this.currentQuoteRequestId) {
      return Promise.resolve();
    }
    return this._persistValidUnsavedSequences();
  }

  handleDeleteSequence(event) {
    event.stopPropagation();
    const id = event.currentTarget.dataset.id;
    if (!id || this._isDeletingSequence(id)) return;

    const target = (this._sequences || []).find(
      (seq) => String(seq.id) === String(id)
    );
    if (!target) return;

    const removeLocally = () => {
      this._sequences = (this._sequences || []).filter(
        (seq) => String(seq.id) !== String(id)
      );
      this._removeDeletingSequence(id);
    };

    if (!target.savedToSalesforce) {
      removeLocally();
      this._retryPersistUnsavedSequencesAfterChange();
      return;
    }

    this._addDeletingSequence(id);
    deleteRecordById({ recordId: id })
      .then(() => {
        removeLocally();
        return this._retryPersistUnsavedSequencesAfterChange();
      })
      .catch((err) => {
        this._removeDeletingSequence(id);
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Error",
            message: err?.body?.message || "Unable to delete sequence.",
            variant: "error"
          })
        );
        // eslint-disable-next-line no-console
        console.error(err);
      });
  }

  handleDownloadSequences() {
    if (!this._sequences || this._sequences.length === 0) return;
    const csv = buildSequenceExportCsv(
      this._sequences.map((seq) => ({
        SequenceName: seq.name,
        Sequence: seq.sequence,
        SequenceLength: seq.length ?? (seq.sequence || "").length,
        SequenceClassification: seq.feasibility || "",
        ...exportColumns({
          json: seq.feasibilityJson,
          rank1: seq.feasibilityExplained1,
          rank2: seq.feasibilityExplained2,
          rank3: seq.feasibilityExplained3
        })
      }))
    );
    const blob = new Blob([csv], { type: "text/csv" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = "sequences.csv";
    a.click();
    URL.revokeObjectURL(url);
  }

  // ─── Step 4 handlers ────────────────────────────────────────────────

  _syncPackagingSelection() {
    if (!this.packagingOptions?.length) {
      return;
    }
    const candidate = this._packagingRestoreValue || this.packagingType;
    this.packagingType = resolvePackagingPicklistValue(
      candidate,
      this.packagingOptions
    );
    this._packagingRestoreValue = null;
  }

  get packagingPlaceholder() {
    return PACKAGING_PLACEHOLDER;
  }

  get totalScaleUpFee() {
    const sum = (this._sequences || []).reduce((acc, seq) => {
      if (seq.scaleUpSelected !== true) {
        return acc;
      }
      const fee =
        parseFloat(
          (seq.scaleUpFee || "0").replace("$", "").replace("NA", "0")
        ) || 0;
      return acc + fee;
    }, 0);
    return `$${sum.toFixed(2)}`;
  }
  get totalGlycerolFee() {
    if (!this.showGlycerolSelection) {
      return "$0.00";
    }
    const sum = (this._sequences || []).reduce((acc, seq) => {
      const fee =
        parseFloat(
          (this._effectiveGlycerolFee(seq) || "0")
            .replace("$", "")
            .replace("NA", "0")
        ) || 0;
      return acc + fee;
    }, 0);
    return `$${sum.toFixed(2)}`;
  }

  get totalGlycerolFeeDisplay() {
    if (this.isUpdatingGlycerol) {
      return "Updating...";
    }
    return this.totalGlycerolFee;
  }

  get grandTotal() {
    const lineTotal = (this._sequences || []).reduce((sum, seq) => {
      const price =
        parseFloat(
          (seq.totalPrice || "$0").replace("$", "").replace(",", "")
        ) || 0;
      return sum + price;
    }, 0);
    return "$" + lineTotal.toFixed(2);
  }

  handlePackagingChange(event) {
    const nextValue = event.detail?.value ?? event.target.value;
    if (nextValue === this.packagingType) {
      return;
    }
    this.packagingType = nextValue;
    if (this.currentQuoteRequestId) {
      updateQuoteRequestPackaging({
        quoteRequestId: this.currentQuoteRequestId,
        packagingType: nextValue
      }).catch((err) => {
        console.error("Packaging update failed:", err);
        this.showValidationToast(
          "Unable to save packaging type. Please try again."
        );
      });
    }
  }

  _openScaleUpPopoverForLine(lineId) {
    // Defer so the icon renders (it only appears once the row is selected) before opening.
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(() => {
      this._scaleUpPopoverLineId = String(lineId);
    }, 0);
  }

  _snapshotSequencesById(ids) {
    const idList = ids.map(String);
    const snapshot = {};
    (this._sequences || []).forEach((s) => {
      if (idList.includes(String(s.id))) {
        snapshot[String(s.id)] = { ...s };
      }
    });
    return snapshot;
  }

  handleScaleUpSelectedChange(event) {
    event.stopPropagation();
    const id = event.target.dataset.id;
    const checked = event.target.checked === true;
    const previous = (this._sequences || []).find(
      (s) => String(s.id) === String(id)
    );
    if (!previous) {
      return;
    }

    const popoverOpen = String(this._scaleUpPopoverLineId) === String(id);

    // Always clear on uncheck. If the config panel was open, close it too
    // (previously the first click only closed the panel and kept Scale Up selected).
    if (!checked && previous.scaleUpSelected === true && popoverOpen) {
      this._scaleUpPopoverLineId = null;
    }

    this._sequences = this._sequences.map((s) =>
      String(s.id) === String(id)
        ? this._withAdditionalFees({
            ...s,
            ...(checked
              ? { scaleUpSelected: true }
              : this._clearedScaleUpUiFields()),
            // Scale Up disables the Glycerol column; clear local selection so it
            // doesn't stay checked-but-disabled while Scale Up Glycerol is used instead.
            glycerol: checked ? false : s.glycerol,
            glycerolFee: checked
              ? null
              : s.glycerol === true
                ? s.glycerolFee
                : null,
            totalPrice: checked
              ? s.totalPrice
              : this._recalculateSequenceTotal({
                  ...s,
                  ...this._clearedScaleUpUiFields(),
                  glycerol: s.glycerol,
                  glycerolFee: s.glycerol === true ? s.glycerolFee : null
                })
          })
        : s
    );

    if (checked) {
      // Open the config panel so the user can set the required Prep Quantity.
      // If standard glycerol was already saved, clear it now (Scale Up owns glycerol).
      this._openScaleUpPopoverForLine(id);
      if (previous.savedToSalesforce && previous.glycerol === true) {
        updateQuoteRequestLineItemGlycerol({
          lineItemId: id,
          glycerolStock: false
        }).catch((err) => {
          console.error("Failed to clear Glycerol Stock for Scale Up:", err);
        });
      }
      return;
    }

    // Clearing the checkbox removes the configuration and re-enables Glycerol Stock.
    this._scaleUpPopoverLineId = null;
    if (!previous.savedToSalesforce) {
      return;
    }
    this._persistScaleUp(
      [id],
      {
        selected: false,
        quantity: "",
        glycerolStock: false,
        buffer: "",
        normalization: null,
        endotoxinFree: false,
        animalFree: false
      },
      this._snapshotSequencesById([id])
    );
  }

  handleScaleUpToggle(event) {
    event.stopPropagation();
    const id = event.currentTarget.dataset.id;
    if (!id) {
      return;
    }
    this._scaleUpPopoverLineId =
      String(this._scaleUpPopoverLineId) === String(id) ? null : id;
  }

  handleScaleUpCancel(event) {
    event.stopPropagation();
    this._scaleUpPopoverLineId = null;
  }

  handleScaleUpDefinitionsToggle(event) {
    this._scaleUpDefinitionsOpen = event.detail?.open === true;
  }

  handleScaleUpDefinitionsClose() {
    this._scaleUpDefinitionsOpen = false;
  }

  _scaleUpTargetIds(lineId, applyToSelected) {
    if (applyToSelected !== true) {
      return [lineId];
    }
    const selected = (this._sequences || []).filter((s) => s.selected === true);
    if (selected.length > 1) {
      return selected.map((s) => s.id);
    }
    return (this._sequences || []).map((s) => s.id);
  }

  handleScaleUpSave(event) {
    event.stopPropagation();
    const id = event.currentTarget.dataset.id;
    const detail = event.detail || {};
    if (!id) {
      return;
    }

    let targetIds = this._scaleUpTargetIds(id, detail.applyToSelected === true);
    // Only persist rows that already exist in Salesforce.
    targetIds = targetIds.filter((tid) => {
      const row = (this._sequences || []).find(
        (s) => String(s.id) === String(tid)
      );
      return row && row.savedToSalesforce;
    });

    if (!targetIds.length) {
      return;
    }
    // Keep the Scale Up popover open after Apply (Cancel / outside click closes it).
    this._persistScaleUp(
      targetIds,
      {
        selected: true,
        quantity: detail.quantity || "",
        glycerolStock: detail.glycerolStock === true,
        buffer:
          detail.buffer ||
          this._scaleUpBufferDefault ||
          SCALE_UP_DEFAULT_BUFFER,
        normalization: toScaleUpNormalizationApiValue(detail.normalization),
        endotoxinFree: detail.endotoxinFree === true,
        animalFree: detail.animalFree === true
      },
      this._snapshotSequencesById(targetIds)
    );
  }

  _persistScaleUp(ids, settings, previousById) {
    const idList = ids.map(String);
    const selected = settings.selected === true;
    // Checkbox spinner only when clearing; Apply keeps the popover and uses its Processing button.
    if (selected) {
      idList.forEach((id) => this._addScaleUpSaving(id));
    } else {
      idList.forEach((id) => this._addScaleUpUpdating(id));
      idList.forEach((id) => this._scaleUpClearInFlightIds.add(id));
    }

    this._sequences = this._sequences.map((s) => {
      if (!idList.includes(String(s.id))) {
        return s;
      }
      if (!selected) {
        const cleared = {
          ...s,
          ...this._clearedScaleUpUiFields(),
          glycerol: s.glycerol,
          glycerolFee: s.glycerol === true ? s.glycerolFee : null
        };
        return this._withAdditionalFees({
          ...cleared,
          totalPrice: this._recalculateSequenceTotal(cleared)
        });
      }
      return {
        ...s,
        scaleUpSelected: true,
        scaleUpQuantity: settings.quantity || "",
        scaleUpGlycerolStock: settings.glycerolStock === true,
        scaleUpBuffer:
          settings.buffer ||
          this._scaleUpBufferDefault ||
          SCALE_UP_DEFAULT_BUFFER,
        scaleUpNormalization: fromScaleUpNormalizationApiValue(
          settings.normalization
        ),
        scaleUpEndotoxinFree: settings.endotoxinFree === true,
        scaleUpAnimalFree: settings.animalFree === true,
        glycerol: false
      };
    });

    return updateQuoteRequestLineItemScaleUp({
      lineItemIds: idList,
      selected,
      quantity: selected ? settings.quantity || null : null,
      glycerolStock: settings.glycerolStock === true,
      buffer: selected
        ? settings.buffer ||
          this._scaleUpBufferDefault ||
          SCALE_UP_DEFAULT_BUFFER
        : null,
      endotoxinFree: settings.endotoxinFree === true,
      animalFree: settings.animalFree === true,
      normalization: selected
        ? toScaleUpNormalizationApiValue(settings.normalization)
        : null
    })
      .then((result) => {
        if (!result?.success) {
          throw new Error(result?.error || "Scale Up update failed");
        }
        const byId = {};
        (result.lines || []).forEach((l) => {
          byId[String(l.id)] = l;
        });
        this._sequences = this._sequences.map((s) => {
          const l = byId[String(s.id)];
          if (!l) {
            return s;
          }
          if (l.scaleUpSelected !== true) {
            const cleared = {
              ...s,
              ...this._clearedScaleUpUiFields(),
              glycerol: l.glycerolStock === true,
              glycerolFee:
                l.glycerolStock === true
                  ? this._formatGlycerolFee(l.glycerolPrice) || s.glycerolFee
                  : null,
              glycerolPriceRaw: l.glycerolPrice
            };
            return this._withAdditionalFees({
              ...cleared,
              totalPrice: this._recalculateSequenceTotal(cleared)
            });
          }
          const sales = this._salesFeesForRow(
            {
              Id: s.id,
              ABT_Quote_Line_Item__c: s.quoteLineItemId
            },
            s
          );
          const priceDisplay =
            this._formatCurrencyFee(sales.scaleUp) ||
            this._formatCurrencyFee(l.scaleUpPrice) ||
            "";
          const scaleUpGlycerol = l.scaleUpGlycerolStock === true;
          const glycFee =
            scaleUpGlycerol || l.glycerolStock === true
              ? this._formatGlycerolFee(sales.glycerol) ||
                this._formatGlycerolFee(l.glycerolPrice)
              : null;
          const next = {
            ...s,
            scaleUpSelected: true,
            scaleUpQuantity:
              l.scaleUpQuantity != null ? String(l.scaleUpQuantity) : "",
            scaleUpGlycerolStock: scaleUpGlycerol,
            scaleUpBuffer: l.scaleUpBuffer || "",
            scaleUpNormalization: fromScaleUpNormalizationApiValue(
              l.scaleUpNormalization
            ),
            scaleUpEndotoxinFree: l.scaleUpEndotoxinFree === true,
            scaleUpAnimalFree: l.scaleUpAnimalFree === true,
            scaleUpMass: l.scaleUpMass || "",
            scaleUpPriceDisplay: priceDisplay,
            scaleUpLeadTime: l.scaleUpLeadTime || "",
            scaleUpFee:
              this._formatCurrencyFee(sales.scaleUp) || priceDisplay || null,
            glycerol: false,
            glycerolFee: glycFee,
            glycerolPriceRaw: sales.glycerol || l.glycerolPrice
          };
          return this._withAdditionalFees({
            ...next,
            totalPrice: this._recalculateSequenceTotal(next)
          });
        });
        this._refreshSalesLineItems();
      })
      .catch((err) => {
        if (previousById) {
          this._sequences = this._sequences.map(
            (s) => previousById[String(s.id)] || s
          );
        }
        this.showValidationToast("Unable to save Scale Up. Please try again.");
        console.error("Scale Up update failed:", err);
      })
      .finally(() => {
        if (!selected) {
          idList.forEach((id) => this._scaleUpClearInFlightIds.delete(id));
          idList.forEach((id) => this._removeScaleUpUpdating(id));
        } else {
          idList.forEach((id) => this._removeScaleUpSaving(id));
        }
      });
  }

  handleGlycerolRowChange(event) {
    if (!this.isGlycerolApplicable) {
      return;
    }
    const id = event.target.dataset.id;
    const checked = event.target.checked;
    const previous = (this._sequences || []).find(
      (seq) => String(seq.id) === String(id)
    );
    this._sequences = this._sequences.map((seq) =>
      String(seq.id) === String(id)
        ? this._withAdditionalFees({
            ...seq,
            glycerol: checked,
            glycerolFee: checked ? seq.glycerolFee : null,
            totalPrice: this._adjustTotalPriceForGlycerolToggle(seq, checked)
          })
        : seq
    );
    if (!previous?.savedToSalesforce) {
      return;
    }
    this._addGlycerolUpdating(id);
    updateQuoteRequestLineItemGlycerol({
      lineItemId: id,
      glycerolStock: checked
    })
      .then((result) => {
        if (!result?.success) {
          throw new Error(result?.error || "Glycerol update failed");
        }
        const fee = this._formatGlycerolFee(result.glycerolPrice);
        this._sequences = this._sequences.map((seq) =>
          String(seq.id) === String(id)
            ? this._withAdditionalFees({
                ...seq,
                glycerol: result.glycerolStock === true,
                glycerolFee: fee ?? (checked ? seq.glycerolFee : null)
              })
            : seq
        );
        return this._pollLineItemPricingUntilGlycerolSettled(id);
      })
      .finally(() => {
        this._removeGlycerolUpdating(id);
      })
      .catch((err) => {
        this._sequences = this._sequences.map((seq) =>
          String(seq.id) === String(id)
            ? this._withAdditionalFees({
                ...seq,
                glycerol: previous.glycerol,
                glycerolFee: previous.glycerolFee,
                totalPrice: previous.totalPrice
              })
            : seq
        );
        this.showValidationToast(
          "Failed to update Glycerol. Please try again."
        );
        console.error("Glycerol update failed:", err);
      });
  }

  async handleDownloadQuotePdf() {
    if (this.isPdfDisabled) return;

    if (this.wiredPdfRecordResult) {
      await refreshApex(this.wiredPdfRecordResult);
    }
    await new Promise((resolve) => setTimeout(resolve, 100));

    const element = this.template.querySelector(".quote-pdf-container");
    if (!element) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Quote PDF",
          message: "Unable to generate PDF. Please try again.",
          variant: "error"
        })
      );
      return;
    }

    const quoteNumber =
      this.quoteRequestInfo.quoteNumber || this.quoteId || "Quote";
    const content = element.innerHTML;
    const printWindow = window.open("", "_blank");
    if (!printWindow) {
      // eslint-disable-next-line no-alert
      alert("Please allow pop-ups for this site to download the quote PDF.");
      return;
    }

    printWindow.document.open();
    printWindow.document.write(`
            <html>
                <head>
                    <title>AnsaBio Quote - ${quoteNumber}</title>
                    <style>
                        body { font-family: Arial, sans-serif; margin: 24px; color: #222; }
                        @media print { body { margin: 12px; } }
                    </style>
                </head>
                <body>${content}</body>
            </html>
        `);
    printWindow.document.close();

    const triggerPrint = () => {
      printWindow.focus();
      printWindow.print();
    };
    if (printWindow.document.readyState === "complete") {
      triggerPrint();
    } else {
      printWindow.onload = triggerPrint;
    }
  }

  async handleDownloadEndUserQuotePdf() {
    if (this.isPdfDisabled || !this.isIDTChannelPartnership) return;

    if (this.wiredPdfRecordResult) {
      await refreshApex(this.wiredPdfRecordResult);
    }
    await new Promise((resolve) => setTimeout(resolve, 100));

    const element = this.template.querySelector(".end-customer-pdf-container");
    if (!element) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "End User Quote PDF",
          message: "Unable to generate PDF. Please try again.",
          variant: "error"
        })
      );
      return;
    }

    const quoteNumber =
      this.quoteRequestInfo.quoteNumber || this.quoteId || "Quote";
    const content = element.innerHTML;
    const printWindow = window.open("", "_blank");
    if (!printWindow) {
      // eslint-disable-next-line no-alert
      alert(
        "Please allow pop-ups for this site to download the end user quote PDF."
      );
      return;
    }

    printWindow.document.open();
    printWindow.document.write(`
            <html>
                <head>
                    <title>AnsaBio End Customer Quote - ${quoteNumber}</title>
                    <style>
                        body { font-family: Arial, sans-serif; margin: 24px; color: #222; }
                        @media print { body { margin: 12px; } }
                    </style>
                </head>
                <body>${content}</body>
            </html>
        `);
    printWindow.document.close();

    const triggerPrint = () => {
      printWindow.focus();
      printWindow.print();
    };
    if (printWindow.document.readyState === "complete") {
      triggerPrint();
    } else {
      printWindow.onload = triggerPrint;
    }
  }

  // ─── Navigation ─────────────────────────────────────────────────────

  handleNext() {
    if (this.isStep2 && this.isCodonMode) {
      if (!this.isAminoAcidUploadEnabled) {
        this._showStep2FileError(
          "Amino acid optimization is available for Clonal DNA and XL Clonal DNA only."
        );
        return;
      }
      this.template.querySelector("c-codon-optimizer")?.optimize();
      return;
    }
    if (this.currentStep === 1) {
      if (!this.hasStep1RequiredFields) {
        this.showValidationToast(
          "Please select an existing project or enter a new project name."
        );
        return;
      }
      if (
        !this.selectedExistingProject &&
        (this.newProjectName || "").trim().length > PROJECT_NAME_MAX_LENGTH
      ) {
        this.showValidationToast(
          `Project name must be ${PROJECT_NAME_MAX_LENGTH} characters or fewer.`
        );
        return;
      }
      // Create QuoteRequest in Salesforce, then proceed
      const projectName = this.selectedExistingProject || this.newProjectName;
      this.isProcessing = true;
      createQuoteRequest({
        accountId: this.currentAccountId,
        productId: this.productId,
        projectName: projectName,
        vectorId: this.resolveQuoteHeaderVectorId(),
        isGlycerol: this.isGlycerol
      })
        .then((result) => {
          this._applyCreateQuoteRequestResult(result);
          this.isProcessing = false;
          this.currentStep = 2;

          pushDataLayerEvent({
            event: "start_quote",
            product_id: this.productId,
            product_name: this.productName,
            quote_id: this.currentQuoteRequestId
          });
        })
        .catch((error) => {
          console.error("Error creating quote request:", error);
          this.isProcessing = false;
        });
    } else if (this.currentStep === 2 && !this.hasStep2RequiredFields) {
      this._showStep2FileError(
        this.isAminoAcidUploadEnabled
          ? "Please upload a sequence file, upload amino acids, or add at least one sequence."
          : "Please upload a sequence file or add at least one sequence."
      );
      return;
    } else if (
      this.currentStep === 2 &&
      this.uploadedSequenceFiles.length > 0
    ) {
      this._clearStep2UploadError();
      this.parseUploadedSequenceFiles();
    } else if (this.currentStep === 2) {
      this._clearStep2UploadError();
      this.currentStep = 3;
      this._ensureTrailingEmptyDraftRow();
      this._applyFeasibilityGameState();
    } else if (this.currentStep === 3) {
      this._submittedDraftValidation = true;
      this._enableAllDraftValidation();
      if (this.hasIncompleteDraftSequences) {
        this.showValidationToast(
          "Please finish or clear incomplete sequences in the empty row before continuing."
        );
        return;
      }
      if (
        this.hasSequenceErrors ||
        this.hasSequenceNameErrors ||
        this.hasDuplicateSequenceNames ||
        this.hasVectorErrors
      ) {
        this.showValidationToast(
          "Please fix invalid sequences, names, or missing vectors before continuing."
        );
        return;
      }
      if (!this.hasStep3RequiredFields) {
        this.showValidationToast(
          "Please add at least one sequence before continuing."
        );
        return;
      }

      const advanceToStep4 = () => {
        if (this.hasUnsavedSequences) {
          this.showValidationToast(
            "Some sequences could not be saved. Please fix invalid sequence, name, or vector values before continuing."
          );
          return;
        }
        this.isProcessing = true;
        this._persistPotentiallyToxicForSavedSequences()
          .then(() => {
            this._queueStep4GlycerolApply();
            this.currentStep = 4;
            this._startStep4PollingForPendingSequences();
            return this._applyPendingGlycerolIfReady();
          })
          .catch(() => {
            /* toast shown in helper */
          })
          .finally(() => {
            this.isProcessing = false;
          });
      };

      if (this.hasUnsavedSequences) {
        this._persistValidUnsavedSequences().then(advanceToStep4);
        return;
      }

      advanceToStep4();
      return;
    } else if (this.currentStep === 4) {
      if (!this.hasSequences || this.hasIncompleteDraftSequences) {
        this.showValidationToast(
          "Please add at least one finished sequence before adding to cart."
        );
        return;
      }
      if (this.isCalculationPending) {
        this.showValidationToast(
          "Please wait for sequence classification and pricing to finish."
        );
        return;
      }
      if (
        this.hasSequenceErrors ||
        this.hasSequenceNameErrors ||
        this.hasDuplicateSequenceNames ||
        this.hasUnsavedSequences ||
        this.hasVectorErrors
      ) {
        this.showValidationToast(
          "Please fix invalid sequences, names, or missing vectors before continuing."
        );
        return;
      }
      if (this._shouldPromptHomopolymerAck()) {
        this._openHomopolymerAckModal();
        return;
      }
      this._addQuoteRequestToCart();
    } else if (this.currentStep < this.totalSteps) {
      this.currentStep += 1;
    }
  }

  _shouldPromptHomopolymerAck() {
    return (
      !this._homopolymerAcknowledged &&
      homopolymerSequenceNames(this._sequences).length > 0
    );
  }

  _openHomopolymerAckModal() {
    this.homopolymerAckSequenceNames = homopolymerSequenceNames(
      this._sequences
    );
    this._homopolymerAckOpen = true;
  }

  handleHomopolymerAckClose() {
    this._homopolymerAckOpen = false;
  }

  handleHomopolymerAckUnderstand() {
    this._homopolymerAcknowledged = true;
    this._homopolymerAckOpen = false;
    this._addQuoteRequestToCart();
  }

  _addQuoteRequestToCart() {
    // Update the quote request stage to 'Quoted' before moving to cart
    const fireComplete = () => {
      const send = () => {
        const detail = {
          quoteId: this.quoteId,
          quoteRequestId: this.currentQuoteRequestId,
          productId: this.productId,
          productName: this.productName,
          projectName: this.selectedExistingProject || this.newProjectName,
          newProjectName: this.newProjectName,
          vectorId: this.resolveQuoteHeaderVectorId(),
          isGlycerol: this.isGlycerol,
          packagingType: this.packagingType,
          sequences: JSON.parse(JSON.stringify(this._sequences)),
          grandTotal: this.grandTotal,
          totalScaleUpFee: this.totalScaleUpFee,
          totalGlycerolFee: this.totalGlycerolFee,
          accountId: this.currentAccountId,
          contactId: this.currentContactId
        };
        this.dispatchEvent(new CustomEvent("quotecomplete", { detail }));
        this._navigateToCartAfterAdd(detail.quoteRequestId);
      };
      if (this.currentQuoteRequestId) {
        getQuoteRequestDisplayQuoteNumber({
          quoteRequestId: this.currentQuoteRequestId
        })
          .then((v) => {
            if (v) this.quoteId = v;
          })
          .finally(send);
      } else {
        send();
      }
    };

    if (this.currentQuoteRequestId) {
      this.isProcessing = true;
      updateQuoteRequestPackaging({
        quoteRequestId: this.currentQuoteRequestId,
        packagingType: this.packagingType
      })
        .then(() =>
          addQuoteRequestToCommerceCart({
            quoteRequestId: this.currentQuoteRequestId
          })
        )
        .then(() => {
          pushDataLayerEvent({ ecommerce: null });
          pushDataLayerEvent({
            event: "add_to_cart",
            quote_id: this.currentQuoteRequestId,
            ecommerce: {
              currency: "USD",
              value: this._parseFeeAmount(this.grandTotal),
              items: [
                {
                  item_id: this.productId,
                  item_name: this.productName,
                  price: this._parseFeeAmount(this.grandTotal),
                  quantity: 1
                }
              ]
            }
          });
          fireComplete();
        })
        .catch((err) => {
          console.error("Error updating quote stage:", err);
          const message =
            (err && err.body && err.body.message) ||
            (err && err.message) ||
            "Unable to add quote to cart.";
          this.dispatchEvent(
            new ShowToastEvent({
              title: "Error",
              message,
              variant: "error",
              mode: "sticky"
            })
          );
        })
        .finally(() => {
          this.isProcessing = false;
        });
    } else {
      fireComplete();
    }
  }

  handleBack() {
    if (this.currentStep > 1) {
      this.currentStep -= 1;
      if (this.currentStep === 1) {
        this._stopQuoteDisplayPolling();
      } else if (this.currentStep === 2) {
        // Step 2 only shows file-upload errors; clear stale banners when returning.
        this._clearStep2UploadError();
      } else if (this.currentStep === 3) {
        this._applyFeasibilityGameState();
      }
    }
  }

  handleCancel() {
    this._stopQuoteDisplayPolling();
    this.dispatchEvent(new CustomEvent("quotecancel"));
  }

  _navigateToCartAfterAdd(quoteRequestId) {
    if (quoteRequestId) {
      try {
        sessionStorage.setItem(PENDING_CART_QR_KEY, quoteRequestId);
      } catch (e) {
        /* ignore */
      }
    } else {
      try {
        sessionStorage.removeItem(PENDING_CART_QR_KEY);
      } catch (e) {
        /* ignore */
      }
    }
    this[NavigationMixin.Navigate]({
      type: "standard__webPage",
      attributes: {
        url: CART_PAGE_URL
      }
    });
  }

  handleModalContentClick(event) {
    event.stopPropagation();
  }

  // ==================== Helix Rush Mini-Game (feasibility wait) ====================

  _applyFeasibilityGameState() {
    const pending = this.showFeasibilityGameLink;

    if (this._wasFeasibilityPending === undefined) {
      this._wasFeasibilityPending = pending;
      return;
    }

    if (!this._wasFeasibilityPending && pending) {
      this.resetGameState();
    } else if (this._wasFeasibilityPending && !pending) {
      this.completeGameState();
    } else if (pending) {
      const savedTimestamp =
        this.gameStartTimestamp || this.loadGameTimestamp();
      if (savedTimestamp && !this.progressTimer && this.isGameModalOpen) {
        this.gameStartTimestamp = savedTimestamp;
        this.startProgressBar();
      }
    }

    this._wasFeasibilityPending = pending;
  }

  loadGameTimestamp() {
    if (!this.currentQuoteRequestId) {
      return null;
    }
    try {
      const storageKey = `gameTimestamp_${this.currentQuoteRequestId}`;
      const storedData = localStorage.getItem(storageKey);
      return storedData ? parseInt(storedData, 10) : null;
    } catch (error) {
      return null;
    }
  }

  saveGameTimestamp(timestamp) {
    if (!this.currentQuoteRequestId) {
      return;
    }
    try {
      const storageKey = `gameTimestamp_${this.currentQuoteRequestId}`;
      localStorage.setItem(storageKey, timestamp.toString());
    } catch (error) {
      // best-effort
    }
  }

  clearGameTimestamp() {
    if (!this.currentQuoteRequestId) {
      return;
    }
    try {
      const storageKey = `gameTimestamp_${this.currentQuoteRequestId}`;
      localStorage.removeItem(storageKey);
    } catch (error) {
      // best-effort
    }
  }

  startProgressBar() {
    if (this.progressTimer) {
      clearInterval(this.progressTimer);
    }

    let startTime = this.gameStartTimestamp || this.loadGameTimestamp();
    if (!startTime) {
      startTime = Date.now();
      this.gameStartTimestamp = startTime;
      this.saveGameTimestamp(startTime);
    } else {
      this.gameStartTimestamp = startTime;
    }

    this.updateProgressBar();
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.progressTimer = setInterval(() => {
      this.updateProgressBar();
    }, 1000);
  }

  updateProgressBar() {
    if (!this.gameStartTimestamp) {
      return;
    }

    const maxDuration = 480000;
    const elapsed = Date.now() - this.gameStartTimestamp;
    this.progressPercentage = Math.min(
      Math.round((elapsed / maxDuration) * 100),
      100
    );

    if (this.progressPercentage >= 100) {
      this.stopProgressBar();
    }
  }

  stopProgressBar() {
    if (this.progressTimer) {
      clearInterval(this.progressTimer);
      this.progressTimer = null;
    }
  }

  openGameModal() {
    this.isGameModalOpen = true;
    this.startProgressBar();
  }

  closeGameModal() {
    this.isGameModalOpen = false;
    this.stopProgressBar();
  }

  handleGameLinkClick(event) {
    event.preventDefault();
    this.openGameModal();
  }

  resetGameState() {
    const newTimestamp = Date.now();
    this.gameStartTimestamp = newTimestamp;
    this.progressPercentage = 0;
    this.saveGameTimestamp(newTimestamp);

    if (this.isGameModalOpen) {
      this.startProgressBar();
    }
  }

  completeGameState() {
    this.progressPercentage = 100;
    this.stopProgressBar();
    this.clearGameTimestamp();
    this.gameStartTimestamp = null;
  }
}
