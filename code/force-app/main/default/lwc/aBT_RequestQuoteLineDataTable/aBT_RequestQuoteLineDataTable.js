import { LightningElement, api, wire, track } from "lwc";
import getQuoteRequestLineitemByQuoteRequest from "@salesforce/apex/ABT_Portal_Controller.getQuoteRequestLineitemByQuoteRequest";
import deleteRecordById from "@salesforce/apex/ABT_Portal_Controller.deleteRecordById";
import updateQuoteStatusToOrdered from "@salesforce/apex/ABT_Portal_Controller.updateQuoteStatusToOrdered";
import getContactPointAddresses from "@salesforce/apex/ABT_Portal_Controller.getContactPointAddresses";
import getDefaultAddressId from "@salesforce/apex/ABT_Portal_Controller.getDefaultAddressId";
import getPaymentMethodsByContact from "@salesforce/apex/ABT_Portal_Controller.getPaymentMethodsByContact";
import getUserDetailsById from "@salesforce/apex/ABT_Portal_Controller.getUserDetailsById";
import loadCsvData from "@salesforce/apex/ABT_Portal_Controller.loadCsvData";
import uploadPODocument from "@salesforce/apex/ABT_Portal_Controller.uploadPODocument";
import applyPromoCodeToQuoteRequest from "@salesforce/apex/ABT_Portal_Controller.applyPromoCodeToQuoteRequest";
import removePromoCodeFromQuoteRequest from "@salesforce/apex/ABT_Portal_Controller.removePromoCodeFromQuoteRequest";
// import createQuotePdf2 from '@salesforce/apex/ABT_Portal_Controller.createQuotePdf';
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { refreshApex } from "@salesforce/apex";
import { getRecord } from "lightning/uiRecordApi";
import { getPicklistValues, getObjectInfo } from "lightning/uiObjectInfoApi";
import ACCOUNT_TYPE_FIELD from "@salesforce/schema/Account.Type";
import csvTemplate from "@salesforce/resourceUrl/ABT_CSVQuoteTemplate";
import ABT_Ansa_Logo from "@salesforce/resourceUrl/ABT_Ansa_Logo";
import ABT_MiniGame from "@salesforce/resourceUrl/ABT_MiniGame";
import { NavigationMixin } from "lightning/navigation";
import { publish, MessageContext } from "lightning/messageService";
import QUOTE_UPDATE_CHANNEL from "@salesforce/messageChannel/QuoteUpdate__c";
import USER_Id from "@salesforce/user/Id";
import {
  formatProductName,
  getVectorRequiredCheckoutMessage,
  getVectorRequiredTooltipMessage
} from "c/abtProductNameUtils";
import pdfTerms from "@salesforce/label/c.ABT_QuotePdf_Terms_and_Condition";
import { buildAddPaymentMethodUrl } from "c/abtQuoteUrls";
import XL_SEQUENCE_LENGTH_THRESHOLD from "@salesforce/label/c.ABT_XL_Sequence_Length_Threshold";
import PIND_CHLOR_VECTOR_ID from "@salesforce/label/c.ABT_PIND_Chlor_Vector_ID";
import getQuoteRequestById from "@salesforce/apex/ABT_Portal_Controller.getQuoteRequestById";
import isIdtChannelPartnerAccount from "@salesforce/apex/ABT_IdtChannelPartner.isAccountIdtChannelPartner";
import { INTERNAL_NCP_ORDER_ACCOUNT_ID } from "c/abtQuoteCheckoutUtils";

// Vector-related imports
import getVectorLibraryData from "@salesforce/apex/ABT_Portal_Controller.getVectorLibraryData";
import updateQuoteLineItemVector from "@salesforce/apex/ABT_Portal_Controller.updateQuoteLineItemVector";
import bulkUpdateQuoteLineItemVectors from "@salesforce/apex/ABT_Portal_Controller.bulkUpdateQuoteLineItemVectors";
import createQuoteRequestLineItem from "@salesforce/apex/ABT_Portal_Controller.createQuoteRequestLineItem";
import updateSequenceForLineItem from "@salesforce/apex/ABT_Portal_Controller.updateSequenceForLineItem";

// Genbank download flow trigger
import triggerGenerateQuoteSampleMapsFlow from "@salesforce/apex/ABT_Portal_Controller.triggerGenerateQuoteSampleMapsFlow";
import checkGenbankLinkStatus from "@salesforce/apex/ABT_Portal_Controller.checkGenbankLinkStatus";

// Import for shipping method filtering
import QUOTE_REQUEST_OBJECT from "@salesforce/schema/ABT_Quote_Request__c";
import SHIPPING_METHOD_FIELD from "@salesforce/schema/ABT_Quote_Request__c.ABT_Shipping_Method__c";
import SHIPPING_DESTINATION_FIELD from "@salesforce/schema/ABT_Quote_Request__c.Shipping_Destination__c";
import {
  FALLBACK_SHIPPING_OPTIONS,
  filterShippingMethodsByDestination,
  resolveShippingDestination
} from "c/abtShippingMethodUtils";

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

const quoteRequestFields = [
  "ABT_Quote_Request__c.ABT_Status__c",
  "ABT_Quote_Request__c.ABT_Quote__c",
  "ABT_Quote_Request__c.ABT_Requested_Date__c",
  "ABT_Quote_Request__c.ABT_Requester_Name__c",
  "ABT_Quote_Request__c.ABT_Expiration_Date__c",
  "ABT_Quote_Request__c.ABT_Total_Price__c",
  "ABT_Quote_Request__c.ABT_Quote__r.Subtotal",
  "ABT_Quote_Request__c.ABT_Quote__r.Discount",
  "ABT_Quote_Request__c.Discount__c",
  "ABT_Quote_Request__c.ABT_Quote__r.TotalPrice",
  "ABT_Quote_Request__c.ABT_Quote__r.GrandTotal",
  "ABT_Quote_Request__c.Shipping_Destination__c",
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
  "ABT_Quote_Request__c.ABT_Quote__r.QuoteNumber",
  "ABT_Quote_Request__c.ABT_IncoTerms__c",
  "ABT_Quote_Request__c.ABT_Payment_Terms__c",
  "ABT_Quote_Request__c.ABT_Contact__r.Email",
  "ABT_Quote_Request__c.ABT_Account__r.Name",
  "ABT_Quote_Request__c.ABT_Account__r.Shipping_Destination__c",
  "ABT_Quote_Request__c.ABT_Billing_Address_Lookup__r.Id",
  "ABT_Quote_Request__c.ABT_Shipping_Address_Lookup__r.Id",
  "ABT_Quote_Request__c.Shipping_Amount__c",
  "ABT_Quote_Request__c.Invoice_Email__c",
  "ABT_Quote_Request__c.Name",
  "ABT_Quote_Request__c.Ansa_Quote_Number__c",
  "ABT_Quote_Request__c.Channel_TaT__c",
  "ABT_Quote_Request__c.TaT_Business_Days__c",
  "ABT_Quote_Request__c.Delivery_Format__c",
  "ABT_Quote_Request__c.Yield__c",
  "ABT_Quote_Request__c.ABT_Account__c",
  "ABT_Quote_Request__c.ABT_Quote__r.End_Customer_Subtotal__c",
  "ABT_Quote_Request__c.ABT_Quote__r.End_Customer_Total__c",
  "ABT_Quote_Request__c.ABT_Account__r.Special_Agreement__c"
];

const ALLOWED_SEQUENCE_NAME_CHARS =
  "ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩαβγδεζηθικλμνξοπρστυφχψω+-_:()[]'. abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

// Conditional logging helper - only logs on Partial environment or localhost
const debugLog = (...args) => {
  if (
    window.location.hostname.includes("partial") ||
    window.location.hostname.includes("localhost")
  ) {
    console.log(...args);
  }
};

function validateSequenceName(name) {
  if (!name) return "Sequence name is required";

  if (name.length > 25) {
    return "Your sequence name contains invalid characters or is longer than our limit of 25 characters; please fix before continuing. Valid characters are: a-Z 0-9 A-ω + - _ : ( ) [ ] ' .";
  }

  for (let char of name) {
    if (!ALLOWED_SEQUENCE_NAME_CHARS.includes(char)) {
      return "Your sequence name contains invalid characters or is longer than our limit of 25 characters; please fix before continuing. Valid characters are: a-Z 0-9 A-ω + - _ : ( ) [ ] ' .";
    }
  }
  return null;
}

// Helper function to get sequence validation regex based on product SKU
function getSequenceValidationRegex(sku) {
  if (sku === "5002") {
    // Library product - allow IUPAC nucleotide codes
    return /^[ACGTRYSWKMBDHVN]+$/i;
  }
  // Standard products - only ATCG
  return /^[ATCG]+$/i;
}

// Helper function to get sequence validation error message based on product SKU
function getSequenceValidationErrorMessage(sku) {
  if (sku === "5002") {
    return "Sequence must contain only valid IUPAC nucleotide codes (ACGTRYSWKMBDHVN)";
  }
  return "Sequence must contain only ATCG characters";
}

// Helper function to get allowed characters text for error messages
function getAllowedSequenceChars(sku) {
  if (sku === "5002") {
    return "ACGTRYSWKMBDHVN";
  }
  return "ATCG";
}

function getClassificationClass(classification) {
  switch (classification) {
    case "Not Currently Possible":
      return "slds-text-color_error";
    case "Let's try":
      return "slds-text-color_warning";
    case "Guaranteed":
      return "slds-text-color_success";
    case "Pending":
      return "slds-text-color_weak";
    default:
      return "";
  }
}

function getComplexityClass(complexity) {
  switch (complexity) {
    case "Complex":
      return "complexity-high";
    case "Standard":
      return "complexity-standard";
    case "Pending":
      return "slds-text-color_weak";
    default:
      return "";
  }
}

function getComplexityTooltip(complexity) {
  if (!complexity || complexity === "Pending") {
    return "";
  }

  return `This assessment reflects sequence characteristics that increase synthesis and assembly difficulty, such as length, high GC content, homopolymers, repeats, and secondary structures (e.g., hairpins, loops). Our pricing model offers lower rates for standard sequences, making overall project costs more aligned with your needs.\n\nStandard: Readily manufacturable sequence with low complexity.\nComplex: Sequence exhibits moderate to high complexity, frequently rejected, or requiring manual intervention at other providers.`;
}

import {
  sequenceRecordFromRow,
  sequenceNameFromRow,
  sequenceTextFromRow,
  sequenceLengthFromRow,
  sequenceClassificationFromRow,
  sequenceComplexityFromRow,
  sequenceErrorFromRow,
  normalizeFeasibilityFromRow,
  normalizeComplexityFromRow,
  vectorNameFromRow,
  feasibilityExplainedFromRow
} from "c/abtPortalLineItemUtils";
import { exportColumns } from "c/abtFeasibilityExplainedUtils";

function normalizeQuoteRequestLineRow(row) {
  const classification = sequenceClassificationFromRow(row);
  const awaitingClassification =
    classification === "Pending" || !classification;
  return {
    ...row,
    ABT_Sequence_Name__c: sequenceNameFromRow(row),
    ABT_Sequence_Length__c: sequenceLengthFromRow(row),
    Sequence_Classification__c: awaitingClassification
      ? "Pending"
      : classification,
    Complexity__c: sequenceComplexityFromRow(row),
    Sequence_Error__c: sequenceErrorFromRow(row)
  };
}

export default class ABT_RequestQuoteLineDataTable extends NavigationMixin(
  LightningElement
) {
  ansaLogo = ABT_Ansa_Logo;

  // Wire MessageContext for Lightning Message Service
  @wire(MessageContext)
  messageContext;
  // @api quoteRequestId = 'a15VG000004q4YHYAY';
  // @api quoteRequestId = 'a15VG000005QiCDYA0';
  @api quoteRequestId;
  @api quoteRequestData;
  @api QRLIRecordId;
  @track requestQuotes;
  error;
  @track modalSequenceName = "";
  @track modalSequenceText = "";
  @track isUpdating = false;
  @track isInserting = false;
  @track isDeleting = false;
  @track isPreviewOrder = false;
  @track isTableVisible = true;
  @track isProjectDisabled = false;
  @track isOrderedSuccess = false;
  @track showError = false;
  wiredRequestQuoteResult;
  orderInfo;
  @track isCsvModalOpen;
  @track downloadPdfButtonName = "Download PDF";
  @track isDownloadPdfDisabled = false;
  @track isOrderPreviewModalOpen = false;
  @track accountRecordId;
  @track isPartnerAccount = false;
  isOrder = true;
  // user_Id = '005VG00000EdlmzYAB';
  user_Id = USER_Id;
  @track currentUserData;
  @track contactId;
  @track wiredBillingAddress;
  @track wiredShippingAddress;
  isPlacesOrderButtonDisabled = true;
  pdfTermsAnsCondition = pdfTerms;
  @track quoteRequestAccountId;
  quoteRequestIsIdtChannelPartner = false;

  @track isBillingAddressesAvailable = false;
  @track billingAddressOptions;
  @track selectedBillingAddress;
  @track isShippingAddressesAvailable = false;
  @track shippingAddressOptions;
  @track selectedShippingAddress;
  wiredQuoteRequestDetails;
  @track isCreditCardFieldVisible = false;
  @track selectedPaymentMethod;
  @track paymentMethodOptions;
  @track isPaymentMethodsAvailable;
  @track wiredPaymentMethods;
  @track isNewCreditCardModelOpen = false;
  vfPageUrlForCreditCard = "";
  @track csvLineData = [];
  @track projectName;
  @track hasSequenceNameErrors = false;
  @track hasSequenceErrors = false;
  @track hasLengthErrors = false;
  @track isAnsaClonalDNA = false;
  @track isAnsaClonalXL = false;
  @track hasNotCurrentlyPossibleSequences = false;
  @track hasOnlyNotCurrentlyPossibleSequences = false;
  _lastQuoteRequestLines = [];
  @track hasMissingComplexity = false;
  @track productSku = "";
  @track sequenceLengthLimits = { min: 200, max: 900 }; // Default limits

  @track editFormError = "";
  @track orderNotesValue = "";

  // Promo Code properties
  @track isPromoCodeVisible = false;
  @track contactPromoCode = "";
  @track currentPromoCode = "";
  @track appliedPromoCodeId = null;
  @track isApplyingPromoCode = false;
  @track promoCodeMessage = "";
  @track promoCodeMessageType = "";
  @track formRefreshKey = 0; // Used to force form refresh
  @track freshQuoteData = null; // Store fresh data from imperative calls

  // Volume Discounting Promo properties
  @track isVolumeDiscountModalOpen = false;
  @track volumeDiscountPercentage = 10;
  @track volumeDiscountPromoCode = "a18VG0000036mY5YAI"; // Promo Code record ID
  @track hasAcceptedVolumeDiscount = false;
  @track isVolumeDiscountEligible = false;

  // Shipping method filtering properties
  @track allShippingMethods = [];
  @track filteredShippingMethods = [];
  @track shippingDestination = "";
  @track accountShippingDestination = "";
  @track shippingCountry = "";
  @track selectedShippingMethod = "";
  _shippingMethodPicklistData;

  // Get current project details by Id
  @track isOrderDisabled = true;
  @track isPendingApproval = false;
  @track quoteRequestInfo = {
    contactName: "",
    contactEmail: "",
    invoiceEmail: "",
    quoteNumber: "",
    createdDate: "",
    expiryDate: "",
    shippingAmount: "",
    totalPrice: "",
    subTotal: "",
    discount: "",
    totalPrice: "",
    grnadTotal: "",
    billTo: "",
    shipTo: "",
    paymentTerms: "",
    incoTerms: "",
    accountName: "",
    AnsaProductionTaT: "",
    TotalProjectTaT: "",
    DeliveryFormat: "",
    Yield: "",
    endCustomerSubtotal: "",
    endCustomerTotal: "",
    specialAgreement: "",
    specialAgreementBeforeUrl: "",
    specialAgreementUrl: "",
    specialAgreementAfterUrl: ""
  };

  @track pollingTimer;
  @track rowsAwaitingClassification = new Set();
  @track isClassificationComplete = false;

  @track isFastaModalOpen = false;
  isFastaLoaded = false;
  isFastaButtonDisabled = true;
  fastaFilesUploadedList = [];
  @track fastaFileName = "";
  fastaFileContentsAsText;

  // Properties for drag and drop functionality
  @track isDragActive = false;

  // PO Upload properties
  @track isPODocumentUploaded = false;
  @track isPODocumentRequired = false;
  @track poFilesList = [];
  @track poFileName = "";
  @track poUploadError = "";
  @track isUploadingPO = false;
  @track hasValidationErrors = false;
  @track validationErrors = [];
  @track willDeleteRemoveVolumeDiscount = false;

  @track fileName = "";
  fileContentsAsText;
  @track csvUploadError = "";

  // Vector-related properties
  @track availableVectors = [];
  @track catalogVectors = [];
  @track customVectors = [];
  @track internalVectors = [];
  @track defaultVectorId = null;
  @track isVectorModalOpen = false;
  @track isBulkVectorModalOpen = false;
  @track selectedLineItemsForVector = [];
  @track selectedVectorForBulk = "";
  @track vectorOptions = [];
  @track hasVectorErrors = false;
  @track vectorValidationErrors = [];
  @track vectorLoadingStates = new Map(); // Track loading state per row
  @track areVectorsLoaded = false; // Track if vector options are loaded

  // Mini-Game Modal properties
  @track isGameModalOpen = false;
  @track gameStartTimestamp = null;
  @track progressPercentage = 0;
  @track progressTimer = null;
  gameResourceUrl = ABT_MiniGame; // Static resource URL for the game HTML
  isFirstWireLoad = true; // Track if this is the first data load

  // Genbank download properties
  @track genbankDownloadLink = "";
  @track isGenbankModalOpen = false;
  @track isGenbankButtonDisabled = true;

  connectedCallback() {
    // debugLog('connectedCallback:');
    // debugLog('this.user_Id:', this.user_Id);
    this.getUserDetails();
    // Start polling for classification updates
    this.startPolling();

    // Load volume discount offer decision from localStorage
    this.loadVolumeDiscountOfferDecision();

    // Check if there's an ongoing calculation and restore progress
    const savedTimestamp = this.loadGameTimestamp();
    if (savedTimestamp) {
      this.gameStartTimestamp = savedTimestamp;
      debugLog(
        "Restored game timestamp from localStorage:",
        new Date(savedTimestamp)
      );
    }
  }

  disconnectedCallback() {
    // Clear polling timer when component is destroyed
    this.stopPolling();
    // Clear progress bar timer
    this.stopProgressBar();
  }

  startPolling() {
    // Poll every 10 seconds
    this.pollingTimer = setInterval(() => {
      if (this.rowsAwaitingClassification.size > 0) {
        // Refresh both sequence line items and quote request details to get updated pricing
        refreshApex(this.wiredRequestQuoteResult);
        refreshApex(this.wiredQuoteRequestDetails);
        debugLog(
          "VD: Polling refresh - updating sequence classifications and total pricing"
        );

        // Notify other components of the pricing update during classification
        this.dispatchQuoteUpdateEvent("classification_polling_update", {
          sequencesAwaitingClassification: this.rowsAwaitingClassification.size,
          isPollingUpdate: true
        });
      }
    }, 10000);
  }

  stopPolling() {
    if (this.pollingTimer) {
      clearInterval(this.pollingTimer);
    }
  }

  getUserDetails() {
    getUserDetailsById({ userId: this.user_Id })
      .then((result) => {
        this.currentUserData = result;
        this.contactId = result.ContactId;
        this.accountRecordId = this.currentUserData.AccountId;
        // debug for code below
        // Check for promo codes visibility - show field if Contact has a promo code setup
        this.contactPromoCode =
          result.Contact && result.Contact.Promo_Code__c
            ? result.Contact.Promo_Code__c
            : "";

        // Show promo code field if Contact has a promo code configured (but don't fill it)
        this.isPromoCodeVisible = !!this.contactPromoCode;

        // Load vector data after accountRecordId is set
        debugLog(
          "Loading vector data with accountRecordId:",
          this.accountRecordId
        );
        this.loadVectorData();
      })
      .catch((error) => {
        console.error("Error fetching data:", error);
      });
  }

  // Wire service to get account type
  @wire(getRecord, {
    recordId: "$accountRecordId",
    fields: [ACCOUNT_TYPE_FIELD]
  })
  wiredAccountRecord({ error, data }) {
    if (data) {
      const accountType = data.fields.Type.value;
      this.isPartnerAccount = accountType === "Partner";
    } else if (error) {
      console.error("Error fetching account details:", error);
    }
  }

  // Wire service to get shipping method picklist values
  @wire(getObjectInfo, { objectApiName: QUOTE_REQUEST_OBJECT })
  quoteRequestObjectInfo;

  @wire(getPicklistValues, {
    recordTypeId: "$quoteRequestObjectInfo.data.defaultRecordTypeId",
    fieldApiName: SHIPPING_METHOD_FIELD,
    controllerFieldApiName: SHIPPING_DESTINATION_FIELD
  })
  shippingMethodPicklistValues({ error, data }) {
    if (data) {
      this._shippingMethodPicklistData = data;
      this.allShippingMethods = data.values.map((option) => ({
        label: option.label,
        value: option.value
      }));
      this.filterShippingMethods();
    } else if (error) {
      console.error("Error loading shipping method picklist:", error);
      this._shippingMethodPicklistData = null;
      this.allShippingMethods = FALLBACK_SHIPPING_OPTIONS;
      this.filterShippingMethods();
    }
  }

  @wire(getQuoteRequestById, { quoteRequestId: "$quoteRequestId" })
  wiredQuoteRequest(value) {
    this.wiredQuoteRequestDetails = value;
    const { data, error } = value;
    if (data) {
      this.quoteRequestAccountId = data.ABT_Account__c;
      this.refreshInternalNcpOrderEligibility();
      this.quoteRequestIsIdtChannelPartner =
        data.ABT_Account__r?.IDT_Channel_Partner__c === true;
      if (data.ABT_Account__c) {
        isIdtChannelPartnerAccount({ accountId: data.ABT_Account__c })
          .then((flag) => {
            this.quoteRequestIsIdtChannelPartner = flag === true;
          })
          .catch((err) =>
            console.error("Error loading IDT channel partner flag:", err)
          );
      }
      // Store the product SKU
      if (data.ABT_Product__r && data.ABT_Product__r.StockKeepingUnit) {
        this.productSku = data.ABT_Product__r.StockKeepingUnit;
        // Set sequence length limits based on SKU and account
        this.setSequenceLengthLimitsBySKU(this.productSku);
        // Update Genbank button state after product type is determined
        this.updateGenbankButtonState();
      }

      // Check for applied promo code and set volume discount state
      if (data.Promo_Code__c) {
        this.appliedPromoCodeId = data.Promo_Code__c;

        const isVolumeDiscount =
          data.Promo_Code__r &&
          (data.Promo_Code__r.Name === "VOLUME10" ||
            data.Promo_Code__c === this.volumeDiscountPromoCode ||
            data.Promo_Code__r.Name.toLowerCase().includes("volume"));

        if (isVolumeDiscount) {
          this.hasAcceptedVolumeDiscount = true;
          this.volumeDiscountPercentage =
            data.Promo_Code__r.Discount_Percentage__c || 10;
        }

        if (data.Promo_Code__r && data.Promo_Code__r.Name) {
          this.currentPromoCode = data.Promo_Code__r.Name;
        }
      } else {
        this.appliedPromoCodeId = null;
        this.hasAcceptedVolumeDiscount = false;
        this.currentPromoCode = "";
      }

      if (data.ABT_Billing_Address_Lookup__r != null) {
        this.selectedBillingAddress = data.ABT_Billing_Address_Lookup__c;
      }
      if (data.ABT_Shipping_Address_Lookup__r != null) {
        this.selectedShippingAddress = data.ABT_Shipping_Address_Lookup__c;
      }
      if (data.ABT_Payment_Method__c == "Credit Card") {
        this.isCreditCardFieldVisible = true;
        if (data.ABT_Payment_Method_Lookup__r != null) {
          this.selectedPaymentMethod = data.ABT_Payment_Method_Lookup__c;
          debugLog(
            "selectedPaymentMethod in wire:",
            this.selectedPaymentMethod
          );
        }
      }
      this.projectName = data.ABT_Customer_Project_Name__c;
      this.vfPageUrlForCreditCard = buildAddPaymentMethodUrl({
        quoteRequestId: data.Id
      });
    } else if (error) {
      console.error("Error fetching wiredQuoteRequest data:", error);
    }
  }

  // Function to set sequence length limits based on SKU
  setSequenceLengthLimitsBySKU(sku) {
    // Special case for account 001VH000006eZjdYAE - allow up to 60,000 chars for clonal products
    const specialAccountId = "001VH000006eZjdYAE";
    const isSpecialAccount = this.quoteRequestAccountId === specialAccountId;

    // Set the limits based on SKU
    if (sku === "1002") {
      // Ansa Clonal DNA SKU
      if (isSpecialAccount) {
        // Special account gets extended limits for clonal DNA
        this.sequenceLengthLimits = { min: 100, max: 60000 };
      } else {
        // Standard limits for all other accounts
        this.sequenceLengthLimits = { min: 100, max: 7500 };
      }
      this.isAnsaClonalDNA = true;
      this.isAnsaClonalXL = false;
    } else if (sku === "2002") {
      // Ansa DNA Fragment SKU
      this.sequenceLengthLimits = { min: 200, max: 900 };
      this.isAnsaClonalDNA = false;
      this.isAnsaClonalXL = false;
    } else if (sku === "6001" || sku === "6003") {
      // Ansa Clonal DNA 7.5 - 50 kb SKU
      if (isSpecialAccount) {
        // Special account gets extended limits for extended clonal DNA
        this.sequenceLengthLimits = {
          min: parseInt(XL_SEQUENCE_LENGTH_THRESHOLD, 10),
          max: 60000
        };
      } else {
        // Standard limits for all other accounts
        this.sequenceLengthLimits = {
          min: parseInt(XL_SEQUENCE_LENGTH_THRESHOLD, 10),
          max: 50000
        };
      }
      this.isAnsaClonalDNA = false;
      this.isAnsaClonalXL = true;
    } else {
      // For any other SKU, no specific limits
      this.sequenceLengthLimits = { min: 0, max: Number.MAX_SAFE_INTEGER };
      this.isAnsaClonalDNA = false;
      this.isAnsaClonalXL = false;
    }
  }

  wiredRecordResult;

  @wire(getRecord, { recordId: "$quoteRequestId", fields: quoteRequestFields })
  wiredRecord(value) {
    this.wiredRecordResult = value;
    const { error, data } = value;
    if (data) {
      // debugLog('PDF data: ', data);
      this.quoteRequestData = data;
      // if (this.quoteRequestData.fields.ABT_Status__c.value === 'Presented') {
      //     this.isOrderDisabled = false;
      // }

      // Check if the quote is in "Pending Approval" status
      if (
        this.quoteRequestData.fields.ABT_Status__c.value === "Pending Approval"
      ) {
        this.isPendingApproval = true;
        this.isOrderDisabled = true;
      } else {
        this.isPendingApproval = false;
      }

      if (this.quoteRequestData.fields.ABT_Status__c.value === "Ordered") {
        this.isProjectDisabled = true;
      }

      // Check if PO is required based on order amount
      this.checkIfPORequired();

      const specialAgreement =
        this.quoteRequestData.fields.ABT_Account__r.value?.fields
          .Special_Agreement__c?.value != null
          ? this.quoteRequestData.fields.ABT_Account__r.value.fields
              .Special_Agreement__c.value
          : "Products and services outlined in this quote are bound by Ansa's Terms and Conditions found here: https://ansabio.com/terms-and-conditions";
      const termsParts = pdfTermsLinkParts(specialAgreement);

      this.quoteRequestInfo = {
        contactName:
          this.quoteRequestData.fields.ABT_Requester_Name__c.value != null
            ? this.quoteRequestData.fields.ABT_Requester_Name__c.value
            : "NA",
        createdDate:
          this.quoteRequestData.fields.ABT_Requested_Date__c.displayValue !=
          null
            ? this.quoteRequestData.fields.ABT_Requested_Date__c.displayValue
            : "NA",
        expiryDate:
          this.quoteRequestData.fields.ABT_Expiration_Date__c.displayValue !=
          null
            ? this.quoteRequestData.fields.ABT_Expiration_Date__c.displayValue
            : "NA",
        totalPrice:
          this.quoteRequestData.fields.ABT_Total_Price__c.value != null
            ? this.quoteRequestData.fields.ABT_Total_Price__c.value.toFixed(2)
            : "NA",
        quoteNumber:
          this.quoteRequestData.fields.Ansa_Quote_Number__c.value != null
            ? this.quoteRequestData.fields.Ansa_Quote_Number__c.value
            : "NA",
        subTotal:
          this.quoteRequestData.fields.ABT_Quote__r.value != null
            ? this.quoteRequestData.fields.ABT_Quote__r.value.fields.Subtotal.value.toFixed(
                2
              )
            : "NA",
        discount:
          this.quoteRequestData.fields.ABT_Quote__r.value != null
            ? this.quoteRequestData.fields.ABT_Quote__r.value.fields.Discount
                .value
            : "NA",
        formattedDiscount: this.getFormattedDiscount(),
        grnadTotal:
          this.quoteRequestData.fields.ABT_Quote__r.value != null
            ? this.quoteRequestData.fields.ABT_Quote__r.value.fields.GrandTotal
                .value
            : "NA",
        contactEmail:
          this.quoteRequestData.fields.ABT_Contact__r.value != null
            ? this.quoteRequestData.fields.ABT_Contact__r.value.fields.Email
                .value
            : "NA",
        billTo:
          this.quoteRequestData.fields.ABT_Billing_Address_Lookup__r.value !=
          null
            ? this.quoteRequestData.fields.ABT_Billing_Address_Lookup__r.value
                .fields.Street.value +
              ", " +
              this.quoteRequestData.fields.ABT_Billing_Address_Lookup__r.value
                .fields.City.value +
              ", " +
              this.quoteRequestData.fields.ABT_Billing_Address_Lookup__r.value
                .fields.State.value +
              ", " +
              this.quoteRequestData.fields.ABT_Billing_Address_Lookup__r.value
                .fields.Country.value +
              " - " +
              this.quoteRequestData.fields.ABT_Billing_Address_Lookup__r.value
                .fields.PostalCode.value
            : "NA",
        shipTo:
          this.quoteRequestData.fields.ABT_Shipping_Address_Lookup__r.value !=
          null
            ? this.quoteRequestData.fields.ABT_Shipping_Address_Lookup__r.value
                .fields.Street.value +
              ", " +
              this.quoteRequestData.fields.ABT_Shipping_Address_Lookup__r.value
                .fields.City.value +
              ", " +
              this.quoteRequestData.fields.ABT_Shipping_Address_Lookup__r.value
                .fields.State.value +
              ", " +
              this.quoteRequestData.fields.ABT_Shipping_Address_Lookup__r.value
                .fields.Country.value +
              " - " +
              this.quoteRequestData.fields.ABT_Shipping_Address_Lookup__r.value
                .fields.PostalCode.value
            : "NA",
        paymentTerms:
          this.quoteRequestData.fields.ABT_Payment_Terms__c.value != null
            ? this.quoteRequestData.fields.ABT_Payment_Terms__c.value
            : "NA",
        incoTerms:
          this.quoteRequestData.fields.ABT_IncoTerms__c.value != null
            ? this.quoteRequestData.fields.ABT_IncoTerms__c.value
            : "NA",
        accountName:
          this.quoteRequestData.fields.ABT_Account__r.value != null
            ? this.quoteRequestData.fields.ABT_Account__r.value.fields.Name
                .value
            : "NA",
        invoiceEmail:
          this.quoteRequestData.fields.Invoice_Email__c.value != null
            ? this.quoteRequestData.fields.Invoice_Email__c.value
            : "NA",
        shippingAmount:
          this.quoteRequestData.fields.Shipping_Amount__c.value != null
            ? this.quoteRequestData.fields.Shipping_Amount__c.value.toFixed(2)
            : "NA",
        AnsaProductionTaT:
          this.quoteRequestData.fields.TaT_Business_Days__c.value != null
            ? this.quoteRequestData.fields.TaT_Business_Days__c.value
            : "NA",
        TotalProjectTaT:
          this.quoteRequestData.fields.Channel_TaT__c.value != null
            ? this.quoteRequestData.fields.Channel_TaT__c.value
            : "NA",
        DeliveryFormat:
          this.quoteRequestData.fields.Delivery_Format__c.value != null
            ? this.quoteRequestData.fields.Delivery_Format__c.value
            : "NA",
        Yield:
          this.quoteRequestData.fields.Yield__c.value != null
            ? this.quoteRequestData.fields.Yield__c.value
            : "NA",
        endCustomerSubtotal:
          this.quoteRequestData.fields.ABT_Quote__r.value?.fields
            .End_Customer_Subtotal__c?.value != null
            ? this.quoteRequestData.fields.ABT_Quote__r.value.fields.End_Customer_Subtotal__c.value.toFixed(
                2
              )
            : "NA",
        endCustomerTotal:
          this.quoteRequestData.fields.ABT_Quote__r.value?.fields
            .End_Customer_Total__c?.value != null
            ? this.quoteRequestData.fields.ABT_Quote__r.value.fields.End_Customer_Total__c.value.toFixed(
                2
              )
            : "NA",
        specialAgreement,
        specialAgreementBeforeUrl: termsParts.before,
        specialAgreementUrl: termsParts.url,
        specialAgreementAfterUrl: termsParts.after
        // billTo: this.quoteRequestData.fields.ABT_Quote__r.value.fields.BillingStreet.value,
        // shipTo: this.quoteRequestData.fields.ABT_Quote__r.value.fields.ShipingStreet.value
      };

      if (
        this.quoteRequestData.fields.ABT_Billing_Address_Lookup__r.value == null
      ) {
        // debugLog('accountRecordId 2: ', this.accountRecordId);
        this.getDefaultBillingAddress();
      }
      if (
        this.quoteRequestData.fields.ABT_Shipping_Address_Lookup__r.value ==
        null
      ) {
        // debugLog('accountRecordId 3: ', this.accountRecordId);
        this.getDefaultShippingAddress();
      }

      // Capture shipping destination and country for filtering
      this.shippingDestination =
        this.quoteRequestData.fields.Shipping_Destination__c?.value || "";
      this.accountShippingDestination =
        this.quoteRequestData.fields.ABT_Account__r?.value?.fields
          ?.Shipping_Destination__c?.value || "";
      if (this.quoteRequestData.fields.ABT_Shipping_Address_Lookup__r.value) {
        this.shippingCountry =
          this.quoteRequestData.fields.ABT_Shipping_Address_Lookup__r.value
            .fields.Country.value || "";
      }

      // Filter shipping methods based on destination/country
      this.filterShippingMethods();

      // Check for Genbank download link availability
      this.updateGenbankButtonState();
    } else if (error) {
      console.error("Error: ", error);
    }
  }

  updateGenbankButtonState() {
    // Unified logic (Skip classification per user): enable when product is clonal DNA (incl. XL) AND complexity is complete.
    // Also, if available in LDS, capture collateral link for download.
    try {
      const isClonal = this.isAnsaClonalDNA || this.isAnsaClonalXL;
      const complexityComplete = !this.hasMissingComplexity;

      const willEnable = isClonal && complexityComplete;
      // If enabling, also clear any residual vector error gating for Genbank button UX
      // (Checkout still validates vectors separately)

      // Debug log for decision tracking
      debugLog("updateGenbankButtonState - Decision", {
        isClonal,
        complexityComplete,
        hasMissingComplexity: this.hasMissingComplexity,
        isAnsaClonalDNA: this.isAnsaClonalDNA,
        isAnsaClonalXL: this.isAnsaClonalXL,
        productSku: this.productSku,
        willEnable
      });

      this.isGenbankButtonDisabled = !willEnable;

      // Force re-render of the specific button if it exists in DOM
      // This is defensive: LWC should react to tracked prop change,
      // but if template/child renders earlier, poke it to ensure reflect.
      try {
        const btn = this.template.querySelector('[data-id="genbankBtn"]');
        if (btn) {
          btn.disabled = !willEnable;
        }
      } catch (domErr) {
        if (
          window.location.hostname.includes("partial") ||
          window.location.hostname.includes("localhost")
        ) {
          console.warn("Genbank button DOM sync warning:", domErr);
        }
      }
    } catch (e) {
      // Fail safe: disable button on unexpected error
      this.isGenbankButtonDisabled = true;
      // Log error with debugLog
      debugLog("updateGenbankButtonState error:", e);
    }
  }

  getDefaultShippingAddress() {
    getDefaultAddressId({
      accountId: this.accountRecordId,
      addressType: "Shipping"
    })
      .then((result) => {
        // debugLog('result getDefaultShippingAddress:', result);
        this.selectedShippingAddress = result;
      })
      .catch((error) => {
        console.error("Error fetching getDefaultShippingAddress:", error);
      });
  }

  getDefaultBillingAddress() {
    getDefaultAddressId({
      accountId: this.accountRecordId,
      addressType: "Billing"
    })
      .then((result) => {
        // debugLog('result getDefaultBillingAddress:', result);
        this.selectedBillingAddress = result;
      })
      .catch((error) => {
        console.error("Error fetching getDefaultBillingAddress:", error);
      });
  }

  getSequenceErrorIcon(errorText) {
    if (!errorText) return undefined;

    // Check for character validation errors (ATCG or IUPAC codes)
    if (
      errorText.includes("characters other than AGCT") ||
      errorText.includes("characters other than") ||
      errorText.includes("invalid characters") ||
      errorText.includes("IUPAC nucleotide codes")
    ) {
      return "utility:error";
    }
    if (errorText.includes("length of this sequence is outside")) {
      return "utility:warning";
    }
    return "utility:info"; // Default icon for any other errors
  }

  getIconVariant(errorText) {
    if (!errorText) return undefined;

    // Check for character validation errors (ATCG or IUPAC codes)
    if (
      errorText.includes("characters other than AGCT") ||
      errorText.includes("characters other than") ||
      errorText.includes("invalid characters") ||
      errorText.includes("IUPAC nucleotide codes")
    ) {
      return "error";
    }
    if (errorText.includes("length of this sequence is outside")) {
      return "warning";
    }
    return "info"; // Default variant for any other errors
  }

  // Filter shipping methods based on Shipping_Destination__c dependent picklist rules
  filterShippingMethods() {
    if (!this.allShippingMethods || this.allShippingMethods.length === 0) {
      this.filteredShippingMethods = [];
      return;
    }

    const resolvedDestination = resolveShippingDestination({
      shippingDestination: this.shippingDestination,
      shippingCountry: this.shippingCountry,
      accountShippingDestination: this.accountShippingDestination
    });

    if (this._shippingMethodPicklistData) {
      this.filteredShippingMethods = filterShippingMethodsByDestination(
        this._shippingMethodPicklistData,
        resolvedDestination
      );
    } else {
      this.filteredShippingMethods = filterShippingMethodsByDestination(
        {
          values: this.allShippingMethods.map((option) => ({
            ...option,
            validFor: []
          }))
        },
        resolvedDestination
      );
    }

    if (this.selectedShippingMethod) {
      const isSelectedMethodAvailable = this.filteredShippingMethods.some(
        (method) => method.value === this.selectedShippingMethod
      );
      if (!isSelectedMethodAvailable) {
        this.selectedShippingMethod = "";
      }
    }
  }

  get allowsInternalNcpOrders() {
    return this.quoteRequestAccountId === INTERNAL_NCP_ORDER_ACCOUNT_ID;
  }

  get showSkippedNotCurrentlyPossibleSequences() {
    return (
      this.hasNotCurrentlyPossibleSequences && !this.allowsInternalNcpOrders
    );
  }

  get showOnlyNcpBlocked() {
    return (
      this.hasOnlyNotCurrentlyPossibleSequences && !this.allowsInternalNcpOrders
    );
  }

  refreshInternalNcpOrderEligibility() {
    if (!this._lastQuoteRequestLines.length) {
      return;
    }
    this.hasMissingComplexity = this._lastQuoteRequestLines.some((row) => {
      const line = normalizeQuoteRequestLineRow(row);
      if (
        this.allowsInternalNcpOrders &&
        line.Sequence_Classification__c === "Not Currently Possible"
      ) {
        return false;
      }
      return (
        !line.Complexity__c ||
        line.Complexity__c.trim() === "" ||
        line.Complexity__c === "Pending"
      );
    });
    this.isOrderDisabled =
      this.hasSequenceNameErrors ||
      this.hasSequenceErrors ||
      this.hasLengthErrors ||
      this.hasMissingComplexity ||
      this.isPendingApproval ||
      this.showOnlyNcpBlocked;
  }

  // DataTable Data and Actions
  @wire(getQuoteRequestLineitemByQuoteRequest, {
    quoteRequestId: "$quoteRequestId"
  })
  wiredRequestQuote(value) {
    this.wiredRequestQuoteResult = value;
    const { data, error } = value;
    if (data) {
      this._lastQuoteRequestLines = data;
      // Reset error flags
      this.hasSequenceErrors = false;
      this.hasSequenceNameErrors = false;
      this.hasLengthErrors = false;
      this.hasNotCurrentlyPossibleSequences = false;
      this.hasOnlyNotCurrentlyPossibleSequences = false;
      let orderableSequenceCount = 0;
      this.hasMissingComplexity = false;
      this.hasVectorErrors = false;

      // Store the previous count of rows awaiting classification
      const previousAwaitingCount = this.rowsAwaitingClassification.size;
      this.rowsAwaitingClassification.clear();

      // Check if there are any rows with sequence errors
      const hasSequenceErrors = data.some((row) => sequenceErrorFromRow(row));

      // Transform the data with proper icon assignments
      this.requestQuotes = data.map((row) => {
        const normalizedRow = normalizeQuoteRequestLineRow(row);
        const awaitingClassification =
          normalizedRow.Sequence_Classification__c === "Pending";

        const transformed = {
          ...normalizedRow,
          ABT_Product_Name__c: formatProductName(row.ABT_Product_Name__c),
          formatedPrice: row.ABT_Total_Price__c.toFixed(2),
          formatedEndCustomerPrice:
            row.ABT_Quote_Line_Item__r?.End_Customer_List_Price__c != null
              ? row.ABT_Quote_Line_Item__r.End_Customer_List_Price__c.toFixed(2)
              : "0.00",
          vectorName: row.ABT_Quote_Line_Item__r?.Vector__r?.Name || "N/A",
          classificationClass: getClassificationClass(
            normalizedRow.Sequence_Classification__c
          ),
          complexityClass: getComplexityClass(normalizedRow.Complexity__c),
          complexityTooltip: getComplexityTooltip(normalizedRow.Complexity__c)
        };

        if (awaitingClassification) {
          this.rowsAwaitingClassification.add(row.Id);
        }

        const sequenceNameError = validateSequenceName(
          normalizedRow.ABT_Sequence_Name__c
        );
        if (sequenceNameError) {
          transformed.sequenceNameClass = "slds-text-color_error";
          transformed.sequenceNameIcon = "utility:ban";
          transformed.sequenceNameError = sequenceNameError;
          this.hasSequenceNameErrors = true;
        }

        // Only add icon properties if there's an error
        if (normalizedRow.Sequence_Error__c) {
          transformed.warningIcon = this.getSequenceErrorIcon(
            normalizedRow.Sequence_Error__c
          );
          transformed.iconVariant = this.getIconVariant(
            normalizedRow.Sequence_Error__c
          );
          transformed.errorTooltip = normalizedRow.Sequence_Error__c;
          // Keep the Sequence_Error__c field empty for display
          transformed.Sequence_Error__c = "";

          // Set specific error flags based on error type
          // Check for character validation errors (works for both ATCG and IUPAC codes)
          if (
            normalizedRow.Sequence_Error__c.includes(
              "characters other than AGCT"
            ) ||
            normalizedRow.Sequence_Error__c.includes("characters other than") ||
            normalizedRow.Sequence_Error__c.includes("invalid characters")
          ) {
            this.hasSequenceErrors = true;
          }

          // Check for length errors and update error message based on product SKU
          if (
            normalizedRow.Sequence_Error__c.includes(
              "length of this sequence is outside"
            )
          ) {
            this.hasLengthErrors = true;

            // Get the current limits based on SKU
            const { min, max } = this.sequenceLengthLimits;

            // Only update the error message if we have limits (min > 0)
            if (min > 0) {
              // Update error message to match the current product's limits
              transformed.errorTooltip =
                normalizedRow.Sequence_Error__c.replace(
                  /\d+-\d+bp/,
                  `${min}-${max}bp`
                );
            }
          }
        }

        // Check if sequence is classified as "Not Currently Possible"
        if (
          normalizedRow.Sequence_Classification__c === "Not Currently Possible"
        ) {
          this.hasNotCurrentlyPossibleSequences = true;
        } else {
          orderableSequenceCount++;
        }

        // Check if complexity is missing or pending
        if (
          !normalizedRow.Complexity__c ||
          normalizedRow.Complexity__c.trim() === "" ||
          normalizedRow.Complexity__c === "Pending"
        ) {
          this.hasMissingComplexity = true;
        }

        // Add vector display logic for ANSA Clonal DNA products
        if (this.isAnsaClonalDNA || this.isAnsaClonalXL) {
          this.addVectorDisplayProperties(transformed, row);
          debugLog(
            "Added vector display properties during wire processing for row:",
            row.Id
          );
        } else if (this.areVectorsLoaded && this.vectorOptions.length > 0) {
          // Ensure vector properties are added even if product check fails but vectors are available
          this.addVectorDisplayProperties(transformed, row);
          debugLog(
            "Added vector display properties for available vectors for row:",
            row.Id
          );
        }

        return transformed;
      });

      // Check if classification status has changed
      if (
        previousAwaitingCount > 0 &&
        this.rowsAwaitingClassification.size === 0
      ) {
        // All classifications are now complete
        this.isClassificationComplete = true;
        this.showToast(
          "Sequence Classification Complete",
          "All sequences have been classified.",
          "success"
        );

        // Complete game state
        this.completeGameState();

        // Dispatch event to notify other components that classification and pricing is complete
        this.dispatchQuoteUpdateEvent("classification_complete", {
          totalSequences: this.requestQuotes.length,
          classificationComplete: true
        });

        // Update Genbank button state when classification completes
        debugLog(
          "Updating Genbank button state after classification completion"
        );
        this.updateGenbankButtonState();
      } else if (
        previousAwaitingCount === 0 &&
        this.rowsAwaitingClassification.size > 0 &&
        !this.isFirstWireLoad
      ) {
        // New sequences are awaiting classification (but not on first load)
        this.isClassificationComplete = false;

        // Reset game state for new calculation
        this.resetGameState();

        // Dispatch event to notify other components that classification started
        this.dispatchQuoteUpdateEvent("classification_started", {
          sequencesAwaitingClassification: this.rowsAwaitingClassification.size,
          classificationComplete: false
        });
      } else if (this.rowsAwaitingClassification.size > 0) {
        // Page was reloaded with pending classifications - check if we should continue progress bar
        const savedTimestamp =
          this.gameStartTimestamp || this.loadGameTimestamp();
        if (savedTimestamp && !this.progressTimer) {
          this.gameStartTimestamp = savedTimestamp;
          this.startProgressBar();
        }
      }

      // Mark that first load is complete
      this.isFirstWireLoad = false;

      this.csvLineData = data.map((cqr) => {
        const sequenceLength = sequenceLengthFromRow(cqr);
        return {
          SequenceName: sequenceNameFromRow(cqr),
          Sequence: sequenceTextFromRow(cqr),
          SequenceLength: sequenceLength != null ? sequenceLength : "",
          SequenceClassification: sequenceClassificationFromRow(cqr),
          ...exportColumns(feasibilityExplainedFromRow(cqr))
        };
      });

      this.hasOnlyNotCurrentlyPossibleSequences =
        data.length > 0 && orderableSequenceCount === 0;

      // Set isOrderDisabled and error messages based on different types of errors

      if (
        data.length === 0 ||
        this.hasSequenceNameErrors ||
        this.hasSequenceErrors ||
        this.hasLengthErrors ||
        this.hasMissingComplexity ||
        this.isPendingApproval ||
        this.showOnlyNcpBlocked
      ) {
        this.isOrderDisabled = true;
        if (data.length !== 0 && !this.isPendingApproval) {
          // Only show error message for actual sequence errors, not for missing complexity
          if (
            this.hasSequenceNameErrors ||
            this.hasSequenceErrors ||
            this.hasLengthErrors
          ) {
            this.showError = true;
          } else {
            this.showError = false;
          }
        }
      } else {
        this.isOrderDisabled = false;
        this.showError = false;
      }

      this.refreshInternalNcpOrderEligibility();

      this.error = undefined;

      // After data is loaded, ensure vectors are synced
      this.ensureVectorDataSync();
    } else if (error) {
      this.error = error;
      console.debug("error: " + error);
      this.requestQuotes = undefined;
    }
  }

  // for main table when isProjectDisabled = false
  get columns() {
    const baseColumns = [
      {
        label: "",
        fieldName: "Sequence_Error__c",
        initialWidth: 60,
        type: "text",
        sortable: false,
        hideDefaultActions: true,
        cellAttributes: {
          iconName: { fieldName: "warningIcon" },
          iconPosition: "left",
          iconAlternativeText: { fieldName: "errorTooltip" },
          title: { fieldName: "errorTooltip" },
          variant: { fieldName: "iconVariant" }
        }
      }
    ];

    // Vector column only for standard clonal DNA (not XL — fixed pIND chlor; not fragments)
    if (this.isAnsaClonalDNA && !this.isAnsaClonalXL) {
      baseColumns.push({
        label: "Vector",
        fieldName: "selectedVectorId",
        initialWidth: 180,
        type: "vectorSelector",
        typeAttributes: {
          vectorOptions: { fieldName: "vectorOptionsForRow" },
          selectedVectorId: { fieldName: "selectedVectorId" },
          rowId: { fieldName: "Id" },
          isDisabled: { fieldName: "vectorIsDisabled" },
          isVectorLoading: { fieldName: "isVectorLoading" },
          areVectorsLoaded: this.areVectorsLoaded
        },
        editable: false
      });
    }

    // Add remaining columns
    baseColumns.push(
      {
        label: "Sequence Name",
        fieldName: "ABT_Sequence_Name__c",
        cellAttributes: {
          class: { fieldName: "sequenceNameClass" },
          iconName: { fieldName: "sequenceNameIcon" },
          iconPosition: "right",
          iconAlternativeText: { fieldName: "sequenceNameError" }
        }
      },
      {
        label: "Length (bp)",
        fieldName: "ABT_Sequence_Length__c",
        initialWidth: 160
      },
      { label: "Product", fieldName: "ABT_Product_Name__c", initialWidth: 140 },
      {
        label: "Complexity",
        fieldName: "Complexity__c",
        initialWidth: 140,
        cellAttributes: {
          class: { fieldName: "complexityClass" },
          title: { fieldName: "complexityTooltip" }
        }
      },
      {
        label: "Classification",
        fieldName: "Sequence_Classification__c",
        initialWidth: 150,
        cellAttributes: {
          class: { fieldName: "classificationClass" }
        }
      },
      {
        label: "Price (USD)",
        fieldName: "ABT_Total_Price__c",
        type: "currency",
        initialWidth: 140
      }
    );

    // Add action column
    const rowActions = [
      { label: "Edit", name: "edit" },
      { label: "Delete", name: "delete" }
    ];

    baseColumns.push({
      type: "action",
      typeAttributes: {
        rowActions: rowActions
      }
    });

    return baseColumns;
  }

  get hideCheckboxColumn() {
    return !(this.isAnsaClonalDNA && !this.isAnsaClonalXL);
  }

  get showVectorFeatures() {
    // Only show vector features for regular clonal DNA, not XL clonal (since XL has fixed pIND chlor vector)
    return this.isAnsaClonalDNA && !this.isAnsaClonalXL;
  }

  get quoteProductName() {
    const data = this.wiredQuoteRequestDetails?.data;
    if (!data) {
      return "";
    }
    return formatProductName(
      data.ABT_Product_Name__c || data.ABT_Product__r?.Name || ""
    );
  }

  get vectorRequiredTooltipMessage() {
    return getVectorRequiredTooltipMessage(this.quoteProductName);
  }

  get defaultVectorName() {
    if (!this.defaultVectorId || !this.availableVectors) {
      return "None";
    }
    const defaultVector = this.availableVectors.find(
      (vector) => vector.Id === this.defaultVectorId
    );
    return defaultVector ? defaultVector.Name : "None";
  }

  get selectedSequenceName() {
    return this.selectedLineItemsForVector.length > 0
      ? this.selectedLineItemsForVector[0].ABT_Sequence_Name__c
      : "";
  }

  // for main table when isProjectDisabled = true
  get columns3() {
    return [
      {
        label: "",
        fieldName: "Sequence_Error__c",
        initialWidth: 60,
        type: "text",
        sortable: false,
        hideDefaultActions: true,
        cellAttributes: {
          iconName: { fieldName: "warningIcon" },
          iconPosition: "left",
          iconAlternativeText: { fieldName: "errorTooltip" },
          title: { fieldName: "errorTooltip" },
          variant: { fieldName: "iconVariant" }
        }
      },
      { label: "Sequence Name", fieldName: "ABT_Sequence_Name__c" },
      {
        label: "Length (bp)",
        fieldName: "ABT_Sequence_Length__c",
        initialWidth: 160
      },
      { label: "Product", fieldName: "ABT_Product_Name__c", initialWidth: 140 },
      {
        label: "Complexity",
        fieldName: "Complexity__c",
        initialWidth: 140,
        cellAttributes: {
          class: { fieldName: "complexityClass" },
          title: { fieldName: "complexityTooltip" }
        }
      },
      {
        label: "Classification",
        fieldName: "Sequence_Classification__c",
        initialWidth: 150,
        cellAttributes: {
          class: { fieldName: "classificationClass" }
        }
      },
      {
        label: "Price (USD)",
        fieldName: "ABT_Total_Price__c",
        type: "currency",
        initialWidth: 140
      }
    ];
  }

  // for order preview modal
  get columns2() {
    return [
      { label: "Sequence Name", fieldName: "ABT_Sequence_Name__c" },
      {
        label: "Length (bp)",
        fieldName: "ABT_Sequence_Length__c",
        initialWidth: 160
      },
      { label: "Product", fieldName: "ABT_Product_Name__c", initialWidth: 140 },
      {
        label: "Complexity",
        fieldName: "Complexity__c",
        initialWidth: 140,
        cellAttributes: {
          class: { fieldName: "complexityClass" },
          title: { fieldName: "complexityTooltip" }
        }
      },
      {
        label: "Classification",
        fieldName: "Sequence_Classification__c",
        initialWidth: 150,
        cellAttributes: {
          class: { fieldName: "classificationClass" }
        }
      },
      {
        label: "Price (USD)",
        fieldName: "ABT_Total_Price__c",
        type: "currency",
        initialWidth: 140
      }
    ];
  }

  handleRowAction(event) {
    const actionName = event.detail.action.name;
    const row = event.detail.row;

    switch (actionName) {
      case "edit":
        this.onEditQRLIRecord(row);
        break;
      case "delete":
        this.onDeleteQRLIRecord(row);
        break;
    }
  }

  // Handle inline vector selection changes from custom datatable
  async handleVectorPicklistChange(event) {
    const { value: vectorId, context: lineItemId } = event.detail;

    // Set loading state for this specific row
    this.setRowVectorLoading(lineItemId, true);

    try {
      const result = await updateQuoteLineItemVector({
        lineItemId: lineItemId,
        vectorId: vectorId
      });

      if (result.success) {
        this.showToast("Success", "Vector updated successfully", "success");

        // Refresh the data to show the updated vector assignment
        await refreshApex(this.wiredRequestQuoteResult);
      } else {
        this.showToast(
          "Error",
          result.error || "Failed to update vector",
          "error"
        );
        // Revert to previous state on error
        await refreshApex(this.wiredRequestQuoteResult);
      }
    } catch (error) {
      console.error("Error updating vector:", error);
      this.showToast("Error", "Failed to update vector", "error");
      // Revert to previous state on error
      await refreshApex(this.wiredRequestQuoteResult);
    } finally {
      // Clear loading state
      this.setRowVectorLoading(lineItemId, false);
    }
  }

  // Handle inline vector selection changes (fallback for standard datatable)
  async handleCellChange(event) {
    const draftValues = event.detail.draftValues;

    for (const draft of draftValues) {
      if (draft.selectedVectorId !== undefined) {
        try {
          const result = await updateQuoteLineItemVector({
            lineItemId: draft.Id,
            vectorId: draft.selectedVectorId
          });

          if (result.success) {
            this.showToast("Success", "Vector updated successfully", "success");

            // Refresh the data to show the updated vector assignment
            await refreshApex(this.wiredRequestQuoteResult);

            // Clear the draft values
            const dataTable =
              this.template.querySelector("c-a-b-t_custom-data-table") ||
              this.template.querySelector("lightning-datatable");
            if (dataTable && dataTable.draftValues) {
              dataTable.draftValues = [];
            }
          } else {
            this.showToast(
              "Error",
              result.error || "Failed to update vector",
              "error"
            );
          }
        } catch (error) {
          console.error("Error updating vector:", error);
          this.showToast("Error", "Failed to update vector", "error");
        }
      }
    }
  }

  // saveRecord() {
  //     if (this.isUpdating) {
  //         const index = this.requestQuotes.findIndex(item => item.id === this.QRLIRecordId);
  //         this.requestQuotes[index].ABT_Sequence_Name__c = this.ABT_Sequence_Name__c;
  //     } else {
  //         const newRecord = {
  //             id: (this.requestQuotes.length + 1).toString(),
  //             ABT_Sequence_Name__c: this.ABT_Sequence_Name__c,
  //         };
  //         this.requestQuotes = [...this.requestQuotes, newRecord];
  //     }
  //     this.closeModal();
  // }

  // *************** DataTable Actions **************
  handleDataTableRefresh() {
    refreshApex(this.wiredRequestQuoteResult);
    // Also refresh the quote request data to ensure button states update
    refreshApex(this.wiredQuoteRequestDetails);
    // Removed window.location.reload() to prevent page refresh and allow auto-apply logic to work

    // Dispatch event to notify other components of quote update
    this.dispatchQuoteUpdateEvent("pricing_refresh");
  }

  // Helper method to publish quote update messages via LMS
  dispatchQuoteUpdateEvent(updateType = "general", details = {}) {
    if (this.messageContext) {
      const message = {
        updateType: updateType,
        quoteRequestId: this.quoteRequestId,
        timestamp: new Date().toISOString(),
        details: details
      };
      // FIXME: uncomment this when deploying to org
      publish(this.messageContext, QUOTE_UPDATE_CHANNEL, message);
    } else {
      console.error(
        "VD: MessageContext not available, cannot publish quote update"
      );
    }
  }

  // *************** Toast Actions ***************

  showToast(title, message, variant) {
    const evt = new ShowToastEvent({
      title: title,
      message: message,
      variant: variant
    });
    this.dispatchEvent(evt);
  }

  // *************** Modal Actions ***************
  closeModal() {
    this.editFormError = "";
    this.isModalOpen = false;
    this.isUpdating = false;
    this.isInserting = false;
    this.isDeleting = false;
    this.QRLIRecordId = null;
    this.modalSequenceName = "";
    this.modalSequenceText = "";
    this.isOrderedSuccess = false;
    this.willDeleteRemoveVolumeDiscount = false;

    this.isTableVisible = true;
  }

  // *********** 1. Insert Quote Request LineItem ***********
  handleAddRecordButtonClick() {
    this.isUpdating = false;
    this.isInserting = true;
    this.isDeleting = false;
    this.modalSequenceName = "";
    this.modalSequenceText = "";
    this.isModalOpen = true;
    this.isTableVisible = false;
  }

  handleInsertQRLISuccess(event) {
    const newRecordId = event.detail.id;
    debugLog("VD: handleInsertQRLISuccess() called, newRecordId:", newRecordId);
    this.showToast("Success", "Record created: " + newRecordId, "success");
    // Optionally, reset the form or navigate to the new record page
    this.closeModal();

    // Refresh data after successful insert
    this.handleDataTableRefresh();

    // Reset game state when new sequence is added
    this.resetGameState();

    // Apply vector for ANSA Clonal products
    if (this.isAnsaClonalDNA && this.defaultVectorId) {
      debugLog("VD: Applying default vector to new record");
      this.applyDefaultVectorToNewRecord(newRecordId);
    } else if (this.isAnsaClonalXL) {
      // For XL clonal products, always apply pIND chlor vector
      this.applyPindChlorVectorToNewRecord(newRecordId);
    }

    // Check if volume discount should be auto-applied after adding sequence
    debugLog("VD: Scheduling checkVolumeDiscountAfterSequenceAdd() in 500ms");
    setTimeout(() => {
      this.checkVolumeDiscountAfterSequenceAdd();
    }, 500);

    // Dispatch event to notify other components
    this.dispatchQuoteUpdateEvent("sequence_added", {
      sequenceId: newRecordId
    });
  }

  handleInsertQRLIError(event) {
    const errors = event.detail.detail;
    this.showToast(
      "Error",
      "Error creating record: " + JSON.stringify(errors),
      "error"
    );
    this.closeModal();
  }

  // *********** 2. Update Quote Request LineItem ***********

  onEditQRLIRecord(row) {
    this.QRLIRecordId = row.Id;
    this.modalSequenceName = sequenceNameFromRow(row);
    this.modalSequenceText = sequenceTextFromRow(row);
    this.isUpdating = true;
    this.isInserting = false;
    this.isDeleting = false;
    this.isModalOpen = true;
    this.isTableVisible = false;
  }

  handleUpdateQRLISuccess(event) {
    const updatedRecordId = event.detail.id;
    // You can perform actions after the record is updated, like navigating to the record page
    // debugLog('Record updated: ' + updatedRecordId);
    this.showToast("Success", "Record updated successfully", "success");
    this.handleDataTableRefresh();
    this.closeModal();

    // Dispatch event to notify other components
    this.dispatchQuoteUpdateEvent("sequence_updated", {
      sequenceId: updatedRecordId
    });
  }

  handleUpdateQRLIError(event) {
    const errors = event.detail.detail;
    // Handle errors here
    this.showToast("Error", "Error updating record: " + errors, "error");
    console.error("Error updating record: ", errors);
    this.closeModal();
  }

  // *********** 3. Delete Quote Request LineItem ***********
  onDeleteQRLIRecord(row) {
    // debugLog('deleteRecord row: ' + row.Id);
    this.QRLIRecordId = row.Id;
    this.isUpdating = false;
    this.isInserting = false;
    this.isDeleting = true;

    // Check if deleting this sequence would remove volume discount eligibility
    this.checkIfDeleteWillRemoveVolumeDiscount();

    this.isModalOpen = true;
  }

  async onConfirmationOfDeleteQRLIRecord() {
    // debugLog('onConfirmationOfDeleteQRLIRecord: ' + this.QRLIRecordId);
    this.isTableVisible = false;

    // Store the sequence ID before deletion for event dispatching
    const deletedSequenceId = this.QRLIRecordId;

    try {
      // Delete the sequence record
      await deleteRecordById({ recordId: this.QRLIRecordId });

      // If this deletion will remove volume discount eligibility, remove it
      if (this.willDeleteRemoveVolumeDiscount) {
        await this.handleRemoveVolumeDiscount();
      }

      // Remove row from table and refresh all data including total price
      this.handleDataTableRefresh();
      this.isTableVisible = true;
      this.closeModal();

      this.showToast("Success", "Sequence deleted successfully", "success");

      // Add a small delay to ensure backend processing is complete, then refresh again
      setTimeout(() => {
        debugLog("VD: Secondary refresh after sequence deletion");
        refreshApex(this.wiredQuoteRequestDetails);

        // Dispatch event to notify other components with the stored sequence ID
        this.dispatchQuoteUpdateEvent("sequence_deleted", {
          sequenceId: deletedSequenceId,
          priceUpdateRequired: true
        });
      }, 500);
    } catch (error) {
      console.error("Error deleting sequence:", error);
      this.isTableVisible = true;
      this.showToast(
        "Error",
        "Failed to delete sequence: " + (error.body?.message || error.message),
        "error"
      );
    }
  }

  // *********** 4. Place Order ***********

  closeOrderPreviewModal() {
    this.isOrderPreviewModalOpen = false;
  }

  handlePrevieweOrder() {
    // Check if customer is eligible for volume discount and hasn't accepted it yet
    if (
      this.isEligibleForVolumeDiscount() &&
      !this.hasUserAcceptedVolumeDiscountOffer()
    ) {
      this.isVolumeDiscountModalOpen = true;
      this.isVolumeDiscountEligible = true;
    } else {
      this.proceedToCheckout();
    }
  }

  // Check if customer is eligible for volume discount (4 or fewer sequences)
  isEligibleForVolumeDiscount() {
    // Only show if:
    // 1. Customer has 4 or fewer sequences
    // 2. They have at least 1 sequence
    // 3. Volume discount is currently active
    // 4. They haven't already applied the volume discount
    return (
      this.requestQuotes &&
      this.requestQuotes.length <= 4 &&
      this.requestQuotes.length > 0 &&
      !this.hasAcceptedVolumeDiscount &&
      this.isVolumeDiscountActive()
    );
  }

  // Check if volume discount should be applied (user accepted and has 5+ sequences)
  shouldApplyVolumeDiscount() {
    return (
      this.hasAcceptedVolumeDiscount &&
      this.requestQuotes &&
      this.requestQuotes.length >= 5
    );
  }

  // Get computed promo code visibility (existing logic + volume discount logic)
  // Hide promo code field when volume discount is active
  get computedPromoCodeVisibility() {
    // Don't show promo code field when volume discount is active
    if (this.shouldApplyVolumeDiscount()) {
      return false; // Hide promo code field completely when volume discount is active
    }
    return this.isPromoCodeVisible && !this.hasAcceptedVolumeDiscount;
  }

  get computedPromoCodeValue() {
    // Hidden lookup field must always submit a Salesforce Id (or null),
    // never the free-text promo code entered by the user.
    return this.appliedPromoCodeId;
  }

  // Get computed styling for promo code message
  get promoCodeMessageClass() {
    if (!this.promoCodeMessage) return "";
    return this.promoCodeMessageType === "success"
      ? "slds-text-color_success slds-m-top_x-small"
      : "slds-text-color_error slds-m-top_x-small";
  }

  // Get computed icon for promo code message
  get promoCodeMessageIcon() {
    if (!this.promoCodeMessage) return "";
    return this.promoCodeMessageType === "success"
      ? "utility:success"
      : "utility:error";
  }

  // Get current total price from fresh data
  get currentTotalPrice() {
    if (this.freshQuoteData && this.freshQuoteData.ABT_Total_Price__c) {
      return "$" + this.freshQuoteData.ABT_Total_Price__c;
    }
    return null;
  }

  // Check if volume discount promotion is currently active
  isVolumeDiscountActive() {
    const now = new Date();
    const currentMonth = now.getMonth() + 1; // getMonth() returns 0-11, so add 1
    const currentYear = now.getFullYear();

    // Volume discount is active from July to September (Q3)
    // For testing purposes, you can modify this logic
    return true; // FIXME: uncomment this when going live
    return currentYear === 2025 && currentMonth >= 7 && currentMonth <= 9;
  }

  // Proceed to checkout without volume discount
  proceedToCheckout() {
    if (this.showOnlyNcpBlocked) {
      this.showToast(
        "Error",
        "This quote has no orderable sequences. Sequences assessed as Not Currently Possible cannot be included in an order.",
        "error"
      );
      return;
    }

    // Validate vectors before proceeding
    if (!this.validateVectorsForCheckout()) {
      this.showToast(
        "Error",
        getVectorRequiredCheckoutMessage(this.quoteProductName),
        "error"
      );
      return;
    }

    this.isOrderPreviewModalOpen = true;
    refreshApex(this.wiredQuoteRequestDetails);

    // Force a re-evaluation of the validation state
    setTimeout(() => {
      this.handlePlaceOrderButton();
    }, 100);
  }

  // Handle user accepting the volume discount offer
  handleAcceptVolumeDiscount() {
    // Save the acceptance decision to localStorage
    this.saveVolumeDiscountOfferDecision("accepted");

    this.isVolumeDiscountModalOpen = false;

    // Check if they already have 5+ sequences to auto-apply
    if (this.currentSequenceCount >= 5) {
      // Automatically apply the discount since they have enough sequences
      this.handleApplyVolumeDiscount();
      // Then proceed to checkout since they already qualify
      this.proceedToCheckout();
    } else {
      // Don't proceed to checkout - let them add more sequences first
      this.showToast(
        "Volume Discount Offer Accepted!",
        `Add ${5 - this.currentSequenceCount} more sequence${5 - this.currentSequenceCount > 1 ? "s" : ""} to automatically get ${this.volumeDiscountPercentage}% off your entire order!`,
        "success"
      );
      // Do NOT call proceedToCheckout() - user should stay on the sequences page to add more
    }
  }

  // Handle direct volume discount application via button
  async handleApplyVolumeDiscount() {
    debugLog("VD: handleApplyVolumeDiscount() called");
    try {
      // Show loading state
      this.isOrderDisabled = true;
      debugLog("VD: Set loading state, calling server...");

      // Set the volume discount as accepted
      this.hasAcceptedVolumeDiscount = true;
      this.currentPromoCode = this.volumeDiscountPromoCode;

      // Make remote call to apply promo code to quote request
      debugLog("VD: Making server call to applyPromoCodeToQuoteRequest");
      debugLog("VD: quoteRequestId:", this.quoteRequestId);
      debugLog("VD: promoCode: VOLUME10");

      const result = await applyPromoCodeToQuoteRequest({
        quoteRequestId: this.quoteRequestId,
        promoCode: "VOLUME10" //this.volumeDiscountPromoCode
      });

      debugLog("VD: Server call completed, result:", result);

      if (result.success) {
        this.appliedPromoCodeId = result.promoCodeId || null;
        debugLog("VD: Server call successful, refreshing wire services");
        // Refresh the quote request data to show updated pricing and state
        refreshApex(this.wiredQuoteRequestDetails);
        await refreshApex(this.wiredRequestQuoteResult);
        debugLog("VD: Wire services refreshed");

        // Show success message
        this.showToast(
          "Volume Discount Applied!",
          `${this.volumeDiscountPercentage}% volume discount has been successfully applied to your quote.`,
          "success"
        );
        debugLog("VD: Success toast shown");

        // Dispatch event to notify other components
        this.dispatchQuoteUpdateEvent("volume_discount_applied", {
          discountPercentage: this.volumeDiscountPercentage,
          promoCode: this.volumeDiscountPromoCode
        });
      } else {
        debugLog("VD: Server call failed, result.success = false");
        throw new Error(result.message || "Failed to apply volume discount");
      }
    } catch (error) {
      console.error("VD: Error in handleApplyVolumeDiscount:", error);

      // Show error message (state will be refreshed from server)
      this.showToast(
        "Error",
        "Failed to apply volume discount: " +
          (error.body?.message || error.message || "Unknown error"),
        "error"
      );
    } finally {
      debugLog("VD: Resetting loading state");
      // Reset loading state
      this.isOrderDisabled = false;
    }
  }

  // Handle removing volume discount
  async handleRemoveVolumeDiscount() {
    try {
      // Show loading state
      this.isOrderDisabled = true;

      // Make remote call to remove promo code from quote request
      const result = await removePromoCodeFromQuoteRequest({
        quoteRequestId: this.quoteRequestId
      });

      if (result.success) {
        this.appliedPromoCodeId = null;
        this.currentPromoCode = "";
        // Refresh the quote request data to show updated pricing and state
        await this.refreshApex(this.wiredQuoteRequestDetails);
        await refreshApex(this.wiredRequestQuoteResult);

        // Show success message
        this.showToast(
          "Volume Discount Removed!",
          "The volume discount has been successfully removed from your quote.",
          "success"
        );

        // Dispatch event to notify other components
        this.dispatchQuoteUpdateEvent("volume_discount_removed");
      } else {
        throw new Error(result.message || "Failed to remove volume discount");
      }
    } catch (error) {
      console.error("Error removing volume discount:", error);

      // Show error message
      this.showToast(
        "Error",
        "Failed to remove volume discount: " +
          (error.body?.message || error.message || "Unknown error"),
        "error"
      );
    } finally {
      // Reset loading state
      this.isOrderDisabled = false;
    }
  }

  // Handle user declining the volume discount offer
  handleDeclineVolumeDiscount() {
    // Don't save decline decision - allow them to see the offer again

    this.isVolumeDiscountModalOpen = false;

    this.appliedPromoCodeId = null;
    this.currentPromoCode = "";

    this.proceedToCheckout();
  }

  // Close volume discount modal
  closeVolumeDiscountModal() {
    this.isVolumeDiscountModalOpen = false;
    this.proceedToCheckout();
  }

  async placeOrder() {
    // PO document check removed - no longer required

    try {
      // Upload PO document if one is selected (optional)
      if (this.isPODocumentUploaded) {
        // Show loading state
        this.isUploadingPO = true;

        // Upload the document and get the document ID
        await this.uploadPODocument();
        // We don't need to check for success since PO is optional
      }

      // Proceed with the order
      const result = await updateQuoteStatusToOrdered({
        quoteId: this.quoteRequestData.fields.ABT_Quote__c.value
      });

      // Handle successful order
      this.navigateToOrder(result.Id);
      this.orderInfo = result;
      this.isOrderPreviewModalOpen = false;
      this.isOrderedSuccess = true;

      // Volume discount state is managed by server, no localStorage cleanup needed
    } catch (error) {
      // Handle error
      this.error =
        error.body?.message || error.message || "Unknown error occurred";
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Error",
          message: this.error,
          variant: "error"
        })
      );
    } finally {
      this.isUploadingPO = false;
    }
  }

  navigateToOrder(recordId) {
    // debugLog('recordId: ' + recordId);
    this[NavigationMixin.Navigate]({
      type: "standard__webPage",
      attributes: {
        url: "/AnsaBiotechnologiesCustomerPortal/order/" + recordId
      }
    });
  }

  isCsvLoaded = false;
  get csvAcceptedFormats() {
    return [".csv"];
  }
  handleUploadCsv() {
    this.isCsvModalOpen = true;
  }

  closeCsvModal() {
    this.isCsvModalOpen = false;
  }

  isCsvButtonDisabled = true;
  filesUploadedList = [];
  handleFileSelect(event) {
    this.csvUploadError = ""; // Clear any previous errors
    if (event.target.files.length > 0) {
      const file = event.target.files[0];
      this.filesUploadedList = event.target.files;
      this.fileName = file.name;

      // Basic validation for file type
      if (!file.name.endsWith(".csv")) {
        this.csvUploadError = "Please upload a valid CSV file.";
        this.isCsvButtonDisabled = true;
        return;
      }

      // Enable the upload button if file is valid
      this.isCsvButtonDisabled = false;
    }
  }

  handleFileUpload() {
    this.csvUploadError = ""; // Clear any previous errors
    this.isCsvLoaded = true;
    this.isCsvButtonDisabled = true;

    const fileReader = new FileReader();
    fileReader.onloadend = () => {
      this.fileContentsAsText = fileReader.result;

      // Basic validation of CSV content
      if (!this.fileContentsAsText || this.fileContentsAsText.trim() === "") {
        this.csvUploadError = "The CSV file appears to be empty.";
        this.isCsvLoaded = false;
        return;
      }

      // Check if the CSV has at least one header and one data row
      const lines = this.fileContentsAsText.split("\n");
      if (lines.length < 2) {
        this.csvUploadError = "The CSV file does not contain enough data.";
        this.isCsvLoaded = false;
        return;
      }

      // Validate CSV headers - check if the file has the expected structure
      const headers = lines[0].split(",");
      // Expected headers based on template - modify these based on your actual template
      const expectedHeaders = ["SequenceName", "Sequence"];
      const missingHeaders = expectedHeaders.filter(
        (header) =>
          !headers.some((h) => h.trim().toLowerCase() === header.toLowerCase())
      );

      if (missingHeaders.length > 0) {
        this.csvUploadError = `Invalid CSV format. Missing required columns: ${missingHeaders.join(", ")}. Please use the provided template.`;
        this.isCsvLoaded = false;
        return;
      }

      // Additional validation for data rows
      for (let i = 1; i < lines.length; i++) {
        if (!lines[i].trim()) continue; // Skip empty lines

        const cells = lines[i].split(",");
        if (cells.length < expectedHeaders.length) {
          this.csvUploadError = `Row ${i} does not have enough columns. Please check your CSV file.`;
          this.isCsvLoaded = false;
          return;
        }
      }

      this.uploadRecords();
    };

    fileReader.onerror = () => {
      this.csvUploadError = "Failed to read the CSV file.";
      this.isCsvLoaded = false;
    };

    fileReader.readAsText(this.filesUploadedList[0]);
  }

  uploadRecords() {
    loadCsvData({
      quoteRequestId: this.quoteRequestId,
      data: JSON.stringify(this.fileContentsAsText)
    })
      .then((result) => {
        this.isCsvLoaded = false;
        this.isCsvModalOpen = false;
        this.handleDataTableRefresh();
        this.showToast("Success", "CSV file uploaded successfully", "success");

        // Check if volume discount should be auto-applied after uploading CSV
        debugLog("VD: CSV upload successful, scheduling auto-apply check");
        setTimeout(() => {
          this.checkVolumeDiscountAfterSequenceAdd();
        }, 500);
      })
      .catch((error) => {
        this.isCsvLoaded = false;
        console.error("Error:", error);

        // Set an error message to display in the modal
        if (error.body && error.body.message) {
          this.csvUploadError = error.body.message;
        } else {
          this.csvUploadError =
            "Invalid CSV format. Please use the provided template and try again.";
        }

        this.showToast("Error", "Failed to upload CSV file", "error");
      });
  }

  async handlePdfDownlaod() {
    // Refresh data to ensure we have the latest totals before generating PDF
    await refreshApex(this.wiredRecordResult);

    // Small delay to ensure DOM is updated with latest data
    await new Promise((resolve) => setTimeout(resolve, 100));

    const element = this.template.querySelector(".quote-container");
    const content = element.innerHTML;
    const myWindow = window.open("", "Print-Window");
    myWindow.document.open();
    myWindow.document.write(`
                <html>
                    <head>
                        <title>AnsaBio Quote - ${this.quoteRequestInfo.quoteNumber}</title>
                        <style>
                            /* Add any custom styles here */
                            body {
                                font-family: Arial, sans-serif;
                            }
                        </style>
                    </head>
                    <body>
                        ${content}
                    </body>
                </html>
            `);
    myWindow.document.close();
  }

  async handleEndCustomerPdfDownload() {
    // Refresh data to ensure we have the latest totals before generating PDF
    await refreshApex(this.wiredRecordResult);

    // Small delay to ensure DOM is updated with latest data
    await new Promise((resolve) => setTimeout(resolve, 100));

    const element = this.template.querySelector(".end-customer-pdf-container");
    const content = element.innerHTML;
    const myWindow = window.open("", "Print-Window");
    myWindow.document.open();
    myWindow.document.write(`
                <html>
                    <head>
                        <title>AnsaBio End Customer Quote - ${this.quoteRequestInfo.quoteNumber}</title>
                        <style>
                            /* Add any custom styles here */
                            body {
                                font-family: Arial, sans-serif;
                            }
                        </style>
                    </head>
                    <body>
                        ${content}
                    </body>
                </html>
            `);
    myWindow.document.close();
  }

  // async handleDownloadPdf() {
  //     this.downloadPdfButtonName = 'Loading...';
  //     this.isDownloadPdfDisabled = true;

  //     try {
  //         const result = await createQuotePdf({ quoteRequestId: this.quoteRequestId });
  //         debugLog('Success......');
  //         window.location.reload();
  //     } catch (error) {
  //         console.error('Error--:', error);

  //         // Reset button state
  //         this.downloadPdfButtonName = 'Download PDF';
  //         this.isDownloadPdfDisabled = false;

  //         // Optionally display an error message to the user
  //         alert('Failed to download PDF. Please try again later.'); // or use a modal/toast
  //     }
  // }

  handleCsvTemplate() {
    window.open(csvTemplate, "_blank");
  }

  handlePaymentMethodTypeChange(event) {
    if (event.target.value == "Credit Card") {
      this.isCreditCardFieldVisible = true;
    } else {
      this.isCreditCardFieldVisible = false;
    }
  }

  @wire(getPaymentMethodsByContact, { contactId: "$contactId" })
  wiredPaymentMethodsByContact(value) {
    this.wiredPaymentMethods = value;
    const { data, error } = value;
    if (data) {
      // debugLog('Address B:', data);
      if (data.length > 0) {
        this.isPaymentMethodsAvailable = true;
      }
      // this.error = undefined;
      // Prepare radio button options
      this.paymentMethodOptions = data.map((paymentMethod) => ({
        label:
          paymentMethod.ABT_Card_Holder_Name__c +
          " - " +
          paymentMethod.ABT_Card_Number__c,
        value: paymentMethod.Id
      }));
    } else if (error) {
      // this.error = error.body.message;
      this.isPaymentMethodsAvailable = false;
    }
  }

  handleCreditCardSaveAndClose() {
    refreshApex(this.wiredPaymentMethods);
    refreshApex(this.wiredQuoteRequestDetails);
    this.closeNewCreditCardModel();
  }

  handlePaymentMethodSelection(event) {
    this.selectedPaymentMethod = event.detail.value;
    debugLog("Selected selectedPaymentMethod:", this.selectedPaymentMethod);
    this.handlePlaceOrderButton();
  }

  handleNewCreditCard() {
    this.vfPageUrlForCreditCard = buildAddPaymentMethodUrl({
      quoteRequestId: this.quoteRequestId
    });
    this.isNewCreditCardModelOpen = true;
  }

  closeNewCreditCardModel() {
    this.isNewCreditCardModelOpen = false;
  }

  @wire(getContactPointAddresses, {
    accountId: "$accountRecordId",
    addressType: "Billing"
  })
  wiredBillingAddresses(value) {
    this.wiredBillingAddress = value;
    const { data, error } = value;
    if (data) {
      // debugLog('Address B:', data);
      if (data.length > 0) {
        this.isBillingAddressesAvailable = true;
      }
      // this.error = undefined;
      // Prepare radio button options
      this.billingAddressOptions = data.map((address) => ({
        label:
          address.Name +
          " - " +
          address.Address.street +
          ", " +
          address.Address.city +
          ", " +
          address.Address.state +
          ", " +
          address.Address.country +
          ", " +
          address.Address.postalCode,
        value: address.Id
      }));
    } else if (error) {
      // this.error = error.body.message;
      this.isBillingAddressesAvailable = false;
    }
  }

  @wire(getContactPointAddresses, {
    accountId: "$accountRecordId",
    addressType: "Shipping"
  })
  wiredShippingAddresses(value) {
    this.wiredShippingAddress = value;
    const { data, error } = value;
    if (data) {
      // debugLog('Address S:', data);
      if (data.length > 0) {
        this.isShippingAddressesAvailable = true;
      }
      // this.error = undefined;
      // Prepare radio button options
      this.shippingAddressOptions = data.map((address) => ({
        label:
          address.Name +
          " - " +
          address.Address.street +
          ", " +
          address.Address.city +
          ", " +
          address.Address.state +
          ", " +
          address.Address.country +
          ", " +
          address.Address.postalCode,
        value: address.Id
      }));
    } else if (error) {
      // this.error = error.body.message;
      this.isShippingAddressesAvailable = false;
    }
  }

  handleBillingAddressSelection(event) {
    this.selectedBillingAddress = event.detail.value;
    // Additional logic can be added here to handle the selected address
    // debugLog('Selected selectedBillingAddress:', this.selectedBillingAddress);
    this.handlePlaceOrderButton();
  }

  handleShippingAddressSelection(event) {
    this.selectedShippingAddress = event.detail.value;
    // Additional logic can be added here to handle the selected address
    // debugLog('Selected selectedShippingAddress:', this.selectedShippingAddress);
    this.handlePlaceOrderButton();
  }

  handleShippingMethodChange(event) {
    this.selectedShippingMethod = event.detail.value;
    debugLog("Selected shipping method:", this.selectedShippingMethod);
    this.handlePlaceOrderButton();
  }

  handlePlaceOrderButton() {
    // Reset validation errors
    this.validationErrors = [];
    this.hasValidationErrors = false;

    // First check if upload is in progress
    if (this.isUploadingPO) {
      this.validationErrors.push("File upload in progress");
      this.isPlacesOrderButtonDisabled = true;
      this.hasValidationErrors = true;
      return;
    }

    // Check for address selection
    if (!this.selectedBillingAddress) {
      this.validationErrors.push("Billing address not selected");
    }

    if (!this.selectedShippingAddress) {
      this.validationErrors.push("Shipping address not selected");
    }

    // Check for shipping method selection
    if (!this.selectedShippingMethod) {
      this.validationErrors.push("Shipping method not selected");
    }

    // Credit card validations
    if (this.isCreditCardFieldVisible && !this.selectedPaymentMethod) {
      this.validationErrors.push("Credit card not selected");
    }

    // PO document validation removed - no longer required

    // Set button state based on validation results
    if (this.validationErrors.length > 0) {
      this.hasValidationErrors = true;
      this.isPlacesOrderButtonDisabled = true;
    } else {
      this.hasValidationErrors = false;
      this.isPlacesOrderButtonDisabled = false;
    }
  }

  handleUpdateQuoteRequestSuccess() {
    // Execute the place order method after successful form submission
    this.placeOrder();
  }

  handleOrderPreviewSubmit(event) {
    event.preventDefault();
    const fields = event.detail.fields;
    this.applyPromoCodeIdToSubmitFields(fields);
    event.target.submit(fields);
  }

  applyPromoCodeIdToSubmitFields(fields) {
    const promoCodeId = this.appliedPromoCodeId;
    const isValidSalesforceId = (value) =>
      /^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$/.test(value);
    fields.Promo_Code__c =
      promoCodeId && isValidSalesforceId(promoCodeId) ? promoCodeId : null;
  }

  showCsvTooltip = false;

  handleCsvMouseOver() {
    this.showCsvTooltip = true;
  }

  handleCsvMouseOut() {
    this.showCsvTooltip = false;
  }

  // New Address Model
  isNewAddressModelOpen = false;
  newAddressType;

  handleNewBillingAddress() {
    this.newAddressType = "Billing";
    this.isNewAddressModelOpen = true;
  }

  handleNewShippingAddress() {
    this.newAddressType = "Shipping";
    this.isNewAddressModelOpen = true;
  }

  closeNewAddressModel() {
    this.newAddressType = null;
    this.isNewAddressModelOpen = false;
  }

  handleNewAddressSuccess(event) {
    // debugLog('handleNewAddressSuccess event.detail.id : ' + event.detail.id);
    refreshApex(this.wiredBillingAddress);
    refreshApex(this.wiredShippingAddress);
    if (this.newAddressType === "Billing") {
      this.selectedBillingAddress = event.detail.id;
    }
    if (this.newAddressType === "Shipping") {
      this.selectedShippingAddress = event.detail.id;
    }
    this.handlePlaceOrderButton();
    this.closeNewAddressModel();
  }

  get quoteRequestCreatedDate() {
    // Create a Date object from the input string
    const date = new Date(this.quoteRequestInfo.createdDate);

    // Format the date to "MM/DD/YYYY"
    const month = (date.getMonth() + 1).toString().padStart(2, "0"); // Get month (1-based index)
    const day = date.getDate().toString().padStart(2, "0"); // Get day
    const year = date.getFullYear(); // Get year

    // Return the formatted date string
    return `${month}/${day}/${year}`;
  }

  // Format discount amount as negative value for PDF display
  getFormattedDiscount() {
    if (!this.quoteRequestData?.fields?.Discount__c?.value) {
      return null;
    }
    const discountValue = this.quoteRequestData.fields.Discount__c.value;
    return discountValue > 0 ? `-$${discountValue.toFixed(2)}` : null;
  }

  handleCsvDownlaod() {
    // debugLog('this.csvLineData>>>', this.csvLineData);
    let rowEnd = "\n";
    let csvString = "";
    // this set elminates the duplicates if have any duplicate keys
    let rowData = new Set();

    // getting keys from data
    this.csvLineData.forEach(function (record) {
      Object.keys(record).forEach(function (key) {
        rowData.add(key);
      });
    });

    // Array.from() method returns an Array object from any object with a length property or an iterable object.
    rowData = Array.from(rowData);

    // splitting using ','
    csvString += rowData.join(",");
    csvString += rowEnd;

    // main for loop to get the data based on key value
    for (let i = 0; i < this.csvLineData.length; i++) {
      let colValue = 0;

      // validating keys in data
      for (let key in rowData) {
        if (rowData.hasOwnProperty(key)) {
          // Key value
          // Ex: Id, Name
          let rowKey = rowData[key];
          // add , after every value except the first.
          if (colValue > 0) {
            csvString += ",";
          }
          // If the column is undefined, it as blank in the CSV file.
          let value =
            this.csvLineData[i][rowKey] === undefined
              ? ""
              : this.csvLineData[i][rowKey];
          csvString += '"' + value + '"';
          colValue++;
        }
      }
      csvString += rowEnd;
    }
    // Creating anchor element to download
    let downloadElement = document.createElement("a");
    csvString = csvString.replace(/['"]+/g, "");
    // This  encodeURI encodes special characters, except: , / ? : @ & = + $ # (Use encodeURIComponent() to encode these characters).
    downloadElement.href =
      "data:text/csv;charset=utf-8," + encodeURI(csvString);
    downloadElement.target = "_self";
    // CSV File Name
    downloadElement.download = this.projectName + " - Sequence Export.csv";
    // below statement is required if you are using firefox browser
    document.body.appendChild(downloadElement);
    // click() Javascript function to download CSV file
    downloadElement.click();
  }

  handleModalSequenceNameChange(event) {
    this.modalSequenceName = event.target.value;
  }

  handleModalSequenceTextChange(event) {
    this.modalSequenceText = event.target.value;
  }

  handleSubmit(event) {
    if (event) {
      event.preventDefault();
    }

    const sequenceName = (this.modalSequenceName || "").trim();
    const sequence = (this.modalSequenceText || "").trim();
    if (sequenceName) {
      const error = validateSequenceName(sequenceName);
      if (error) {
        this.editFormError = error;
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Error",
            message: error,
            variant: "error"
          })
        );
        return false;
      }
    }

    // Validate sequence
    if (sequence) {
      // Check for valid DNA sequence based on product SKU
      const validSequenceRegex = getSequenceValidationRegex(this.productSku);
      if (!validSequenceRegex.test(sequence)) {
        this.editFormError = getSequenceValidationErrorMessage(this.productSku);
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Error",
            message: this.editFormError,
            variant: "error"
          })
        );
        return false;
      }

      // Validate sequence length based on the SKU limits
      const { min, max } = this.sequenceLengthLimits;

      // Only validate if we have limits set (min > 0)
      if (min > 0 && (sequence.length < min || sequence.length > max)) {
        this.editFormError = `The length of this sequence is outside of our specifications (${min}-${max}bp). Please edit the length of your sequence`;
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Error",
            message: this.editFormError,
            variant: "error"
          })
        );
        return false;
      }
    }

    // Guard against malformed lookup submission: Promo_Code__c must be a Salesforce Id.
    this.editFormError = "";

    if (this.isUpdating && this.QRLIRecordId) {
      updateSequenceForLineItem({
        lineItemId: this.QRLIRecordId,
        sequenceName,
        sequence,
        vectorId: null
      })
        .then((result) => {
          if (!result?.success) {
            throw new Error(
              result?.error || "Unable to save sequence changes."
            );
          }
          this.handleUpdateQRLISuccess({ detail: { id: this.QRLIRecordId } });
        })
        .catch((error) => {
          this.editFormError =
            error?.message || "An error occurred while saving the record";
          this.dispatchEvent(
            new ShowToastEvent({
              title: "Error",
              message: this.editFormError,
              variant: "error"
            })
          );
        });
      return false;
    }

    if (this.isInserting && this.quoteRequestId) {
      createQuoteRequestLineItem({
        quoteRequestId: this.quoteRequestId,
        sequenceName,
        sequence,
        vectorId: null
      })
        .then((result) => {
          const createdId = result && result.Id ? result.Id : result;
          if (!createdId) {
            throw new Error("Unable to create sequence line item.");
          }
          this.handleInsertQRLISuccess({ detail: { id: createdId } });
        })
        .catch((error) => {
          this.editFormError =
            error?.message || "An error occurred while saving the record";
          this.dispatchEvent(
            new ShowToastEvent({
              title: "Error",
              message: this.editFormError,
              variant: "error"
            })
          );
        });
      return false;
    }

    return false;
  }

  handleError(event) {
    const error = event.detail;
    console.error("error>>>", error);
    this.editFormError =
      error.message || "An error occurred while saving the record";
    this.dispatchEvent(
      new ShowToastEvent({
        title: "Error",
        message: this.editFormError,
        variant: "error"
      })
    );
  }

  get fastaAcceptedFormats() {
    return [".fasta", ".fa", ".fna", ".ffn", ".faa", ".frn"];
  }

  get poAcceptedFormats() {
    return [".pdf", ".doc", ".docx", ".jpg", ".jpeg", ".png"];
  }

  handleUploadFasta() {
    this.isFastaModalOpen = true;
  }

  closeFastaModal() {
    this.isFastaModalOpen = false;
  }

  handleFastaFileSelect(event) {
    if (event.target.files.length > 0) {
      this.fastaFilesUploadedList = Array.from(event.target.files);
      this.fastaFileName = this.fastaFilesUploadedList
        .map((f) => f.name)
        .join(", ");
      this.isFastaButtonDisabled = false;
    }
  }

  handleFastaFileUpload() {
    this.isFastaLoaded = true;
    this.isFastaButtonDisabled = true;

    const fileReadPromises = this.fastaFilesUploadedList.map((file) => {
      return new Promise((resolve, reject) => {
        const fileReader = new FileReader();
        fileReader.onloadend = () => resolve(fileReader.result);
        fileReader.onerror = () =>
          reject(new Error("Failed to read file: " + file.name));
        fileReader.readAsText(file);
      });
    });

    Promise.all(fileReadPromises)
      .then((results) => {
        // Combine all file contents with a newline separator
        this.fastaFileContentsAsText = results.join("\n");
        this.uploadFastaRecords();
      })
      .catch((error) => {
        console.error("Error reading FASTA files:", error);
        this.isFastaLoaded = false;
        this.isFastaButtonDisabled = false;
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Error",
            message: "Failed to read one or more FASTA files.",
            variant: "error"
          })
        );
      });
  }

  uploadFastaRecords() {
    // convert fasta to csv
    const fastaContent = this.fastaFileContentsAsText;
    let fastaEntries = [];
    let currentSequenceName = "";
    let currentSequence = "";

    // Parse FASTA format
    const lines = fastaContent.split("\n");
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();

      // Skip empty lines
      if (line.length === 0) continue;

      // If this is a header line (starts with '>')
      if (line.startsWith(">")) {
        // If we already have a sequence in progress, save it
        if (currentSequenceName && currentSequence) {
          fastaEntries.push({
            SequenceName: currentSequenceName,
            Sequence: currentSequence
          });
        }

        // Start a new sequence, extract name from the header
        // Remove the '>' character and use the rest as the sequence name
        currentSequenceName = line.substring(1).trim();
        // Limit sequence name to 25 characters if needed
        if (currentSequenceName.length > 25) {
          currentSequenceName = currentSequenceName.substring(0, 25);
        }
        currentSequence = "";
      } else {
        // This is a sequence line, append to current sequence
        currentSequence += line.toUpperCase();
      }
    }

    // add the last sequence
    if (currentSequenceName && currentSequence) {
      fastaEntries.push({
        SequenceName: currentSequenceName,
        Sequence: currentSequence
      });
    }

    if (fastaEntries.length === 0) {
      this.isFastaLoaded = false;
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Error",
          message: "No sequences found in the FASTA file.",
          variant: "error"
        })
      );
      return;
    }

    // Prepare entries with sequence length
    let entries = fastaEntries.map((entry) => ({
      SequenceName: entry.SequenceName,
      Sequence: entry.Sequence,
      SequenceLength: entry.Sequence.length
    }));

    // Convert to CSV format
    let csvHeader = "SequenceName,Sequence,SequenceLength\n";
    let csvRows = entries
      .map(
        (entry) =>
          `${entry.SequenceName},${entry.Sequence},${entry.SequenceLength}`
      )
      .join("\n");

    let fastaDataAsCsv = csvHeader + csvRows;

    // Send to server
    loadCsvData({
      quoteRequestId: this.quoteRequestId,
      data: JSON.stringify(fastaDataAsCsv)
    })
      .then((result) => {
        this.isFastaLoaded = false;
        this.isFastaModalOpen = false;
        this.handleDataTableRefresh();
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Success",
            message: "FASTA file uploaded successfully",
            variant: "success"
          })
        );

        // Check if volume discount should be auto-applied after uploading FASTA
        debugLog("VD: FASTA upload successful, scheduling auto-apply check");
        setTimeout(() => {
          this.checkVolumeDiscountAfterSequenceAdd();
        }, 500);
      })
      .catch((error) => {
        console.error("Error:", error);
        this.isFastaLoaded = false;
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Error",
            message: error.body
              ? error.body.message
              : "Error uploading FASTA file",
            variant: "error"
          })
        );
      });
  }

  // Drag and drop event handlers
  handleDragOver(event) {
    event.preventDefault();
    event.stopPropagation();

    // Only allow CSV files
    if (event.dataTransfer.types.includes("Files")) {
      this.isDragActive = true;
    }
  }

  handleDragLeave(event) {
    event.preventDefault();
    event.stopPropagation();
    this.isDragActive = false;
  }

  handleDrop(event) {
    event.preventDefault();
    event.stopPropagation();
    this.isDragActive = false;

    // Check if project is disabled
    if (this.isProjectDisabled) {
      this.showToast(
        "Error",
        "Cannot upload files when project is disabled",
        "error"
      );
      return;
    }

    const files = event.dataTransfer.files;

    if (files.length > 0) {
      const file = files[0];

      // Check if it's a CSV file
      if (file.name.endsWith(".csv")) {
        this.processDroppedFile(file);
      } else {
        this.showToast("Error", "Only CSV files are allowed", "error");
      }
    }
  }

  processDroppedFile(file) {
    this.filesUploadedList = [file];
    this.fileName = file.name;

    // Show loading spinner
    this.isCsvLoaded = true;

    // Read the file
    const fileReader = new FileReader();
    fileReader.onloadend = () => {
      this.fileContentsAsText = fileReader.result;
      this.uploadRecords();
    };
    fileReader.readAsText(file);
  }

  // Method to manually refresh the data table
  refreshClassificationData() {
    refreshApex(this.wiredRequestQuoteResult);
  }

  // Getter to determine when to show the "Classification Complete" message
  get showClassificationComplete() {
    return (
      this.rowsAwaitingClassification.size === 0 &&
      this.requestQuotes &&
      this.requestQuotes.length > 0
    );
  }

  // Getter for progress bar style
  get progressBarStyle() {
    return `width: ${this.progressPercentage}%`;
  }

  get calculationStatusMessage() {
    if (this.progressPercentage >= 100) {
      return "Complexity calculation complete!";
    }
    return "Calculating complexity...";
  }

  get calculationStatusIcon() {
    if (this.progressPercentage >= 100) {
      return "utility:check";
    }
    return "utility:spinner";
  }

  handleOrderNotesChange(event) {
    this.orderNotesValue = event.target.value;
  }

  // Handle promo code changes
  handlePromoCodeChange(event) {
    this.currentPromoCode = event.target.value;
    // Clear any previous messages when user types
    this.promoCodeMessage = "";
    this.promoCodeMessageType = "";
  }

  // Handle promo code apply button click
  async handleApplyPromoCode() {
    debugLog("PC: handleApplyPromoCode() called");

    // Validation
    if (!this.currentPromoCode || this.currentPromoCode.trim() === "") {
      this.promoCodeMessage = "Please enter a promo code";
      this.promoCodeMessageType = "error";
      return;
    }

    this.isApplyingPromoCode = true;
    this.promoCodeMessage = "";
    this.promoCodeMessageType = "";

    try {
      // Make remote call to apply promo code to quote request
      debugLog("PC: Making server call to applyPromoCodeToQuoteRequest");
      debugLog("PC: quoteRequestId:", this.quoteRequestId);
      debugLog("PC: promoCode:", this.currentPromoCode);

      const result = await applyPromoCodeToQuoteRequest({
        quoteRequestId: this.quoteRequestId,
        promoCode: this.currentPromoCode.trim()
      });

      debugLog("PC: Server call result:", result);

      if (result && result.success) {
        this.appliedPromoCodeId = result.promoCodeId || null;
        debugLog("PC: Server call successful, refreshing wire services");

        // Refresh wire services to update pricing
        await refreshApex(this.wiredQuoteRequestDetails);
        await refreshApex(this.wiredRequestQuoteResult);
        debugLog("PC: Wire services refreshed");

        // Force refresh by making imperative call (similar to aBT_QuoteRequestDetail)
        await this.forceQuoteDetailsRefresh();
        debugLog("PC: Imperative refresh completed");

        // Show success message
        this.promoCodeMessage =
          result.message || "Promo code applied successfully!";
        this.promoCodeMessageType = "success";

        this.showToast("Success", this.promoCodeMessage, "success");
        debugLog("PC: Success toast shown");

        // Dispatch event to notify other components
        this.dispatchQuoteUpdateEvent("promo_code_applied", {
          promoCode: this.currentPromoCode.trim()
        });
      } else {
        throw new Error(result.message || "Failed to apply promo code");
      }
    } catch (error) {
      console.error("PC: Error in handleApplyPromoCode:", error);

      // Show error message
      const errorMessage =
        error.body?.message ||
        error.message ||
        "Failed to apply promo code. Please try again.";
      this.promoCodeMessage = errorMessage;
      this.promoCodeMessageType = "error";

      this.showToast(
        "Error",
        "Failed to apply promo code: " + errorMessage,
        "error"
      );
    } finally {
      this.isApplyingPromoCode = false;
    }
  }

  // Force refresh quote details by making imperative call (similar to aBT_QuoteRequestDetail)
  async forceQuoteDetailsRefresh() {
    try {
      debugLog("PC: Making imperative call to getQuoteRequestById");
      const freshData = await getQuoteRequestById({
        quoteRequestId: this.quoteRequestId
      });
      if (freshData) {
        debugLog("PC: Fresh data received:", freshData);
        debugLog("PC: Fresh total price:", freshData.ABT_Total_Price__c);

        // Store the fresh data to use in template
        this.freshQuoteData = freshData;

        // Force form refresh
        this.forceRecordFormRefresh();
      }
    } catch (error) {
      console.error("PC: Error in forceQuoteDetailsRefresh:", error);
    }
  }

  // Force refresh the lightning-record-view-form by incrementing refresh key
  forceRecordFormRefresh() {
    // Increment the refresh key to force template re-evaluation
    this.formRefreshKey++;
    debugLog(
      "PC: Record form refresh forced, refreshKey:",
      this.formRefreshKey
    );
  }

  // PO Upload handlers
  handlePOFileSelect(event) {
    if (event.target.files.length > 0) {
      this.poFilesList = event.target.files;
      this.poFileName = this.poFilesList[0].name;
      this.isPODocumentUploaded = true;
      this.poUploadError = "";
      this.handlePlaceOrderButton();
    }
  }

  handleRemovePOFile() {
    // Reset file selection variables
    this.poFilesList = [];
    this.poFileName = "";
    this.isPODocumentUploaded = false;
    this.poUploadError = "";

    // Reset the file input element to allow selecting the same file again
    const fileInput = this.template.querySelector(
      'input[data-id="poFileInput"]'
    );
    if (fileInput) {
      fileInput.value = "";
    }

    // Re-evaluate the place order button status
    this.handlePlaceOrderButton();

    // Show a toast message
    this.showToast("Success", "File removed", "success");
  }

  // Convert File to base64
  convertFileToBase64(file) {
    return new Promise((resolve, reject) => {
      const fileReader = new FileReader();
      fileReader.readAsDataURL(file);
      fileReader.onload = () => {
        resolve(fileReader.result);
      };
      fileReader.onerror = (error) => {
        reject(error);
      };
    });
  }

  openPOFileSelector() {
    // Find the hidden file input element and trigger a click
    const fileInput = this.template.querySelector(
      'input[data-id="poFileInput"]'
    );
    if (fileInput) {
      fileInput.click();
    }
  }

  checkIfPORequired() {
    // Always return false as PO document is no longer required
    this.isPODocumentRequired = false;
    return false;
  }

  async uploadPODocument() {
    if (!this.poFilesList || this.poFilesList.length === 0) {
      this.poUploadError = "No file selected for upload";
      return null;
    }

    try {
      // Show loading state
      this.isUploadingPO = true;

      // Get the file and convert to base64
      const file = this.poFilesList[0];
      const base64Data = await this.convertFileToBase64(file);

      // Call Apex method to upload the file
      const contentDocumentId = await uploadPODocument({
        base64Data: base64Data,
        fileName: this.poFileName,
        contentType: file.type,
        parentId: this.quoteRequestId
      });

      // Success handling
      this.showToast("Success", "PO Document uploaded successfully", "success");
      return contentDocumentId;
    } catch (error) {
      // Error handling
      console.error("Error uploading PO document:", error);
      this.poUploadError =
        "Error uploading file: " +
        (error.body ? error.body.message : error.message);
      this.showToast("Error", this.poUploadError, "error");
      return null;
    } finally {
      this.isUploadingPO = false;
    }
  }

  get sequenceLengthErrorMessage() {
    const { min, max } = this.sequenceLengthLimits;
    if (min > 0) {
      return `The length of this sequence is outside of our specifications (${min}-${max}bp). Please edit the length of your sequence.`;
    }
    return "The sequence contains invalid characters.";
  }

  get sequenceCharacterErrorMessage() {
    const allowedChars = getAllowedSequenceChars(this.productSku);
    return `Your sequence contains characters other than ${allowedChars}. Please edit your sequence to remove invalid characters.`;
  }

  // Accordion toggle handlers
  handleClassificationAccordionToggle() {
    this.isClassificationAccordionOpen = !this.isClassificationAccordionOpen;
  }

  handleComplexityAccordionToggle() {
    this.isComplexityAccordionOpen = !this.isComplexityAccordionOpen;
  }

  // Computed getters for accordion display
  get classificationIconName() {
    return this.isClassificationAccordionOpen
      ? "utility:chevrondown"
      : "utility:chevronright";
  }

  get complexityIconName() {
    return this.isComplexityAccordionOpen
      ? "utility:chevrondown"
      : "utility:chevronright";
  }

  get classificationContentClass() {
    return this.isClassificationAccordionOpen
      ? "slds-section__content"
      : "slds-hide";
  }

  get complexityContentClass() {
    return this.isComplexityAccordionOpen
      ? "slds-section__content"
      : "slds-hide";
  }

  // Computed properties for volume discount modal
  get currentSequenceCount() {
    return this.requestQuotes ? this.requestQuotes.length : 0;
  }

  get sequencePlural() {
    return this.currentSequenceCount > 1 ? "s" : "";
  }

  get sequencesNeeded() {
    return Math.max(0, 5 - this.currentSequenceCount);
  }

  get sequencesNeededPlural() {
    return this.sequencesNeeded > 1 ? "s" : "";
  }

  get isCheckoutButtonVisible() {
    return this.quoteRequestData?.fields?.ABT_Status__c?.value !== "Ordered";
  }

  // Show volume discount status when discount is applied
  get showVolumeDiscountStatus() {
    return this.hasAcceptedVolumeDiscount && this.shouldApplyVolumeDiscount();
  }

  // Check if deleting current sequence would remove volume discount eligibility
  checkIfDeleteWillRemoveVolumeDiscount() {
    // Check if volume discount is currently applied and deletion would drop below 5 sequences
    this.willDeleteRemoveVolumeDiscount =
      this.hasAcceptedVolumeDiscount && this.currentSequenceCount === 5; // Exactly 5 sequences, deleting one would make it 4
  }

  // Check if volume discount should be triggered after sequence changes
  checkVolumeDiscountAfterSequenceAdd() {
    debugLog("VD: checkVolumeDiscountAfterSequenceAdd() called");
    // Use setTimeout to ensure the requestQuotes array is updated after the wire refresh
    setTimeout(() => {
      // Auto-apply volume discount if user previously accepted offer and now has 5+ sequences
      if (
        this.hasUserAcceptedVolumeDiscountOffer() &&
        this.currentSequenceCount >= 5 &&
        !this.hasAcceptedVolumeDiscount
      ) {
        debugLog("VD: All conditions met! Auto-applying volume discount");
        // Automatically apply the volume discount
        this.handleApplyVolumeDiscount();
      } else if (
        this.hasAcceptedVolumeDiscount &&
        this.shouldApplyVolumeDiscount()
      ) {
        this.showToast(
          "Volume Discount Active!",
          `${this.volumeDiscountPercentage}% off your entire order with ${this.currentSequenceCount} sequences!`,
          "success"
        );
      } else {
      }
    }, 1000);
  }

  // Load volume discount offer decision from localStorage
  loadVolumeDiscountOfferDecision() {
    try {
      const storageKey = `volumeDiscountOffer_${this.quoteRequestId}`;
      const storedData = localStorage.getItem(storageKey);

      if (storedData) {
        const offerData = JSON.parse(storedData);
        return offerData;
      }
      return null;
    } catch (error) {
      console.error("VD: Error loading volume discount offer decision:", error);
      return null;
    }
  }

  // Save volume discount offer decision to localStorage
  saveVolumeDiscountOfferDecision(decision) {
    try {
      const storageKey = `volumeDiscountOffer_${this.quoteRequestId}`;
      const offerData = {
        decision: decision, // 'accepted' or 'declined'
        timestamp: new Date().toISOString()
      };

      localStorage.setItem(storageKey, JSON.stringify(offerData));
      debugLog("Volume discount offer decision saved:", offerData);
    } catch (error) {
      console.error("Error saving volume discount offer decision:", error);
    }
  }

  // Check if user has accepted volume discount offer (different from having it applied)
  hasUserAcceptedVolumeDiscountOffer() {
    const decision = this.loadVolumeDiscountOfferDecision();
    const result = decision && decision.decision === "accepted";
    return result;
  }

  // Vector-related methods
  async loadVectorData() {
    try {
      const result = await getVectorLibraryData({
        currentUserAccountId: this.accountRecordId
      });

      if (result.success) {
        this.catalogVectors = result.catalogVectors || [];
        this.customVectors = result.customVectors || [];
        this.internalVectors = result.internalVectors || [];
        this.defaultVectorId = result.defaultVectorId;

        // Combine all vectors for options
        this.availableVectors = [
          ...this.catalogVectors,
          ...this.customVectors,
          ...this.internalVectors
        ];
        this.prepareVectorOptions();

        debugLog("Vector data loaded successfully");
      } else {
        console.error("Failed to load vector data:", result.error);
      }
    } catch (error) {
      console.error("Error loading vector data:", error);
    }
  }

  prepareVectorOptions() {
    // Only include Catalog and Custom vectors in the global vectorOptions
    // Internal vectors will be handled separately for XL products
    const nonInternalVectors = [...this.catalogVectors, ...this.customVectors];

    debugLog("prepareVectorOptions - Vector counts:", {
      catalogVectors: this.catalogVectors.length,
      customVectors: this.customVectors.length,
      internalVectors: this.internalVectors.length,
      nonInternalVectors: nonInternalVectors.length
    });

    this.vectorOptions = nonInternalVectors
      .filter((vector) => vector.Active__c)
      .map((vector) => ({
        label:
          vector.Name +
          (vector.Id === this.defaultVectorId ? " (Default)" : ""),
        value: vector.Id,
        isDefault: vector.Id === this.defaultVectorId,
        type: vector.Type__c
      }))
      .sort((a, b) => {
        // Sort so default vector comes first
        if (a.isDefault && !b.isDefault) return -1;
        if (!a.isDefault && b.isDefault) return 1;
        // If both default or both non-default, sort alphabetically
        return a.label.localeCompare(b.label);
      });

    // Mark vectors as loaded
    this.areVectorsLoaded = true;

    // Force the columns getter to re-evaluate by triggering reactivity
    this.vectorOptions = [...this.vectorOptions];

    debugLog("Preparing vector options:", {
      vectorCount: this.vectorOptions.length,
      vectorOptions: this.vectorOptions,
      hasRequestQuotes: !!this.requestQuotes,
      requestQuotesLength: this.requestQuotes?.length || 0
    });

    // Force data refresh to reprocess vector options for each row
    if (this.requestQuotes && this.requestQuotes.length > 0) {
      debugLog("Reprocessing existing request quotes data...");
      // Reprocess the existing data to update vectorOptionsForRow
      this.requestQuotes = this.requestQuotes.map((row) => {
        const transformed = { ...row };
        this.addVectorDisplayProperties(transformed, row);
        return transformed;
      });

      // Auto-assign pIND chlor vector to XL products that don't have it set
      if (this.isAnsaClonalXL) {
        this.autoAssignPindChlorToExistingXLProducts();
      }

      debugLog("Finished reprocessing request quotes data");
    } else {
      debugLog("No requestQuotes data to reprocess yet");
    }

    // After vector options are prepared, check if we need to refresh any existing data
    this.ensureVectorDataSync();
  }

  // Ensure vectors and data are properly synced regardless of loading order
  ensureVectorDataSync() {
    debugLog("Ensuring vector data sync...", {
      areVectorsLoaded: this.areVectorsLoaded,
      hasRequestQuotes: !!this.requestQuotes,
      requestQuotesLength: this.requestQuotes?.length || 0
    });

    // If both vectors and data are available, but data might not have vector options
    if (
      this.areVectorsLoaded &&
      this.requestQuotes &&
      this.requestQuotes.length > 0
    ) {
      // Check if any row is missing vector options
      const needsReprocessing = this.requestQuotes.some(
        (row) =>
          !row.vectorOptionsForRow || row.vectorOptionsForRow.length === 0
      );

      if (needsReprocessing) {
        debugLog(
          "Some rows missing vector options, directly reprocessing data..."
        );
        // Directly reprocess the data instead of relying on refreshApex
        this.requestQuotes = this.requestQuotes.map((row) => {
          const transformed = { ...row };
          this.addVectorDisplayProperties(transformed, row);
          return transformed;
        });
        debugLog("Finished direct reprocessing of vector data");
      }
    }
  }

  addVectorDisplayProperties(transformed, row) {
    // Check if vector is assigned through the relationship
    const vectorInfo = row.ABT_Quote_Line_Item__r?.Vector__r;

    // Set the selected vector ID for the picklist
    transformed.selectedVectorId = vectorInfo?.Id || "";

    // Prepare vector options with selected state for this row
    let availableOptions = this.vectorOptions;

    // Filter vectors based on product type
    if (this.isAnsaClonalXL) {
      // For XL clonal products, include regular vectors + internal vectors, but default to pIND chlor
      const regularOptions = [...this.catalogVectors, ...this.customVectors]
        .filter((vector) => vector.Active__c)
        .map((vector) => ({
          label:
            vector.Name +
            (vector.Id === this.defaultVectorId ? " (Default)" : ""),
          value: vector.Id,
          isDefault: vector.Id === this.defaultVectorId
        }));

      const internalOptions = this.internalVectors
        .filter((vector) => vector.Active__c)
        .map((vector) => ({
          label: vector.Name,
          value: vector.Id,
          isDefault: false
        }));

      availableOptions = [...regularOptions, ...internalOptions];

      // Set the vector as disabled/readonly for XL products
      transformed.vectorIsDisabled = true;

      // Ensure XL products always show pIND chlor vector as selected
      if (
        !transformed.selectedVectorId ||
        transformed.selectedVectorId !== PIND_CHLOR_VECTOR_ID
      ) {
        transformed.selectedVectorId = PIND_CHLOR_VECTOR_ID;
      }

      // Clear loading state for XL products since vector is predetermined
      transformed.isVectorLoading = false;
    } else {
      // For non-XL products, use vectorOptions as-is
      // vectorOptions already includes Catalog and Custom vectors (which may include Internal vectors with user access)
      // The backend getVectorLibraryData ensures customVectors only includes vectors user has access to
      availableOptions = this.vectorOptions;
      transformed.vectorIsDisabled = false;

      // Set loading state based on vectorLoadingStates map
      transformed.isVectorLoading = this.vectorLoadingStates.has(row.Id);
    }

    transformed.vectorOptionsForRow = availableOptions.map((option) => ({
      ...option,
      isSelected: option.value === transformed.selectedVectorId
    }));

    // Debug logging
    debugLog("Vector data for row:", {
      rowId: row.Id,
      vectorInfo: vectorInfo,
      selectedVectorId: transformed.selectedVectorId,
      vectorOptionsCount: transformed.vectorOptionsForRow?.length || 0
    });

    // Keep the display properties for reference/validation
    if (vectorInfo && vectorInfo.Id) {
      transformed.vectorDisplayName = vectorInfo.Name;
      transformed.vectorIcon = "utility:success";
      transformed.vectorTooltip = `Vector: ${vectorInfo.Name} (${vectorInfo.Type__c})`;
      transformed.vectorClass = "slds-text-color_success";
    } else {
      transformed.vectorDisplayName = "Vector Required";
      transformed.vectorIcon = "utility:warning";
      transformed.vectorTooltip = "Please assign a vector to this sequence";
      transformed.vectorClass = "slds-text-color_warning";
      if (this.isAnsaClonalDNA && !this.isAnsaClonalXL) {
        this.hasVectorErrors = true;
      }
    }
  }

  // Vector loading state management
  setRowVectorLoading(lineItemId, isLoading) {
    if (isLoading) {
      this.vectorLoadingStates.set(lineItemId, true);
    } else {
      this.vectorLoadingStates.delete(lineItemId);
    }
    // Force reactivity by updating the requestQuotes data
    this.updateRowLoadingState(lineItemId, isLoading);
  }

  updateRowLoadingState(lineItemId, isLoading) {
    if (this.requestQuotes) {
      this.requestQuotes = this.requestQuotes.map((row) => {
        if (row.Id === lineItemId) {
          return {
            ...row,
            isVectorLoading: isLoading
          };
        }
        return row;
      });
    }
  }

  handleSelectVectorForRow(row) {
    this.selectedLineItemsForVector = [row];
    this.isVectorModalOpen = true;
  }

  handleBulkVectorSelection() {
    // Get selected rows from the data table
    const dataTable =
      this.template.querySelector("c-a-b-t_custom-data-table") ||
      this.template.querySelector("lightning-datatable");
    const selectedRows = dataTable ? dataTable.getSelectedRows() : [];

    if (selectedRows.length === 0) {
      this.showToast(
        "Warning",
        "Please select at least one sequence",
        "warning"
      );
      return;
    }

    this.selectedLineItemsForVector = selectedRows;
    this.isBulkVectorModalOpen = true;
  }

  handleVectorSelection(event) {
    this.selectedVectorForBulk = event.detail.value;
  }

  async handleApplyVectorToSelected() {
    if (!this.selectedVectorForBulk) {
      this.showToast("Warning", "Please select a vector", "warning");
      return;
    }

    try {
      const lineItemIds = this.selectedLineItemsForVector.map(
        (item) => item.Id
      );
      const result = await bulkUpdateQuoteLineItemVectors({
        lineItemIds: lineItemIds,
        vectorId: this.selectedVectorForBulk
      });

      if (result.success) {
        this.showToast("Success", result.message, "success");
        this.closeBulkVectorModal();
        // Refresh the data
        refreshApex(this.wiredRequestQuoteResult);
      } else {
        this.showToast("Error", result.error, "error");
      }
    } catch (error) {
      console.error("Error applying vector:", error);
      this.showToast("Error", "An unexpected error occurred", "error");
    }
  }

  async applyDefaultVectorToNewRecord(recordId) {
    if (!this.defaultVectorId) {
      debugLog("No default vector set, skipping auto-assignment");
      return;
    }

    try {
      const result = await updateQuoteLineItemVector({
        lineItemId: recordId,
        vectorId: this.defaultVectorId
      });

      if (result.success) {
        debugLog("Default vector applied to new record:", recordId);
        // Refresh the data to show the vector assignment
        setTimeout(() => {
          refreshApex(this.wiredRequestQuoteResult);
        }, 1000);
      } else {
        console.error(
          "Error applying default vector to new record:",
          result.error
        );
      }
    } catch (error) {
      console.error("Error in applyDefaultVectorToNewRecord:", error);
    }
  }

  async applyPindChlorVectorToNewRecord(recordId) {
    try {
      const result = await updateQuoteLineItemVector({
        lineItemId: recordId,
        vectorId: PIND_CHLOR_VECTOR_ID
      });

      if (result.success) {
        debugLog("pIND chlor vector applied to XL clonal record:", recordId);
        // Refresh the data to show the vector assignment
        setTimeout(() => {
          refreshApex(this.wiredRequestQuoteResult);
        }, 1000);
      } else {
        console.error(
          "Error applying pIND chlor vector to XL record:",
          result.error
        );
      }
    } catch (error) {
      console.error("Error in applyPindChlorVectorToNewRecord:", error);
    }
  }

  async autoAssignPindChlorToExistingXLProducts() {
    try {
      // Find XL products that don't have the pIND chlor vector assigned
      const xlProductsNeedingVector = this.requestQuotes.filter((row) => {
        const currentVectorId = row.ABT_Quote_Line_Item__r?.Vector__c;
        return !currentVectorId || currentVectorId !== PIND_CHLOR_VECTOR_ID;
      });

      if (xlProductsNeedingVector.length > 0) {
        debugLog(
          `Auto-assigning pIND chlor vector to ${xlProductsNeedingVector.length} XL products`
        );

        const lineItemIds = xlProductsNeedingVector.map((item) => item.Id);
        const result = await bulkUpdateQuoteLineItemVectors({
          lineItemIds: lineItemIds,
          vectorId: PIND_CHLOR_VECTOR_ID
        });

        if (result.success) {
          debugLog(
            "Successfully auto-assigned pIND chlor vector to existing XL products"
          );
          // Refresh the data to show the vector assignments
          setTimeout(() => {
            refreshApex(this.wiredRequestQuoteResult);
          }, 1000);
        } else {
          console.error(
            "Error auto-assigning pIND chlor vector to XL products:",
            result.error
          );
        }
      }
    } catch (error) {
      console.error("Error in autoAssignPindChlorToExistingXLProducts:", error);
    }
  }

  closeVectorModal() {
    this.isVectorModalOpen = false;
    this.selectedLineItemsForVector = [];
  }

  closeBulkVectorModal() {
    this.isBulkVectorModalOpen = false;
    this.selectedLineItemsForVector = [];
    this.selectedVectorForBulk = "";
  }

  // // Override the existing checkout validation to include vector checks
  // get isOrderDisabled() {
  //     if ((this.isAnsaClonalDNA || this.isAnsaClonalXL) && this.hasVectorErrors) {
  //         return true;
  //     }
  //     return this._isOrderDisabled;
  // }

  // set isOrderDisabled(value) {
  //     this._isOrderDisabled = value;
  // }

  validateVectorsForCheckout() {
    this.hasVectorErrors = false;
    this.vectorValidationErrors = [];

    // XL uses auto-assigned pIND chlor; fragments do not use customer vector selection
    if (!this.isAnsaClonalDNA || this.isAnsaClonalXL || !this.requestQuotes) {
      return true;
    }

    // Check for items without vectors using the relationship field
    const itemsWithoutVector = this.requestQuotes.filter(
      (item) => !item.ABT_Quote_Line_Item__r?.Vector__r?.Id
    );

    if (itemsWithoutVector.length > 0) {
      this.hasVectorErrors = true;
      this.vectorValidationErrors = itemsWithoutVector.map(
        (item) => `Vector required for sequence: ${item.ABT_Sequence_Name__c}`
      );
      return false;
    }

    return true;
  }

  // ==================== Mini-Game Modal Methods ====================

  // Load game timestamp from localStorage
  loadGameTimestamp() {
    try {
      const storageKey = `gameTimestamp_${this.quoteRequestId}`;
      const storedData = localStorage.getItem(storageKey);

      if (storedData) {
        const timestamp = parseInt(storedData, 10);
        debugLog("Game timestamp loaded:", new Date(timestamp));
        return timestamp;
      }
      return null;
    } catch (error) {
      console.error("Error loading game timestamp:", error);
      return null;
    }
  }

  // Save game timestamp to localStorage
  saveGameTimestamp(timestamp) {
    try {
      const storageKey = `gameTimestamp_${this.quoteRequestId}`;
      localStorage.setItem(storageKey, timestamp.toString());
      debugLog("Game timestamp saved:", new Date(timestamp));
    } catch (error) {
      console.error("Error saving game timestamp:", error);
    }
  }

  // Clear game timestamp from localStorage
  clearGameTimestamp() {
    try {
      const storageKey = `gameTimestamp_${this.quoteRequestId}`;
      localStorage.removeItem(storageKey);
      debugLog("Game timestamp cleared");
    } catch (error) {
      console.error("Error clearing game timestamp:", error);
    }
  }

  // Start the progress bar animation
  startProgressBar() {
    // Clear any existing timer
    if (this.progressTimer) {
      clearInterval(this.progressTimer);
    }

    // Get or create start timestamp
    let startTime = this.gameStartTimestamp || this.loadGameTimestamp();

    if (!startTime) {
      // No existing timestamp, create a new one
      startTime = Date.now();
      this.gameStartTimestamp = startTime;
      this.saveGameTimestamp(startTime);
    } else {
      this.gameStartTimestamp = startTime;
    }

    // Update progress immediately
    this.updateProgressBar();

    // Update progress every second
    this.progressTimer = setInterval(() => {
      this.updateProgressBar();
    }, 1000);
  }

  // Update progress bar based on elapsed time
  updateProgressBar() {
    if (!this.gameStartTimestamp) {
      return;
    }

    const maxDuration = 480000; // 8 minutes in milliseconds
    const elapsed = Date.now() - this.gameStartTimestamp;
    const percentage = Math.min((elapsed / maxDuration) * 100, 100);

    this.progressPercentage = Math.round(percentage);

    debugLog("Progress updated:", this.progressPercentage + "%");

    // If we've reached 100%, stop the timer
    if (this.progressPercentage >= 100) {
      this.stopProgressBar();
    }
  }

  // Stop the progress bar animation
  stopProgressBar() {
    if (this.progressTimer) {
      clearInterval(this.progressTimer);
      this.progressTimer = null;
    }
  }

  // Open the game modal
  openGameModal() {
    this.isGameModalOpen = true;
    this.startProgressBar();
    debugLog("Game modal opened");
  }

  // Close the game modal
  closeGameModal() {
    this.isGameModalOpen = false;
    this.stopProgressBar();
    debugLog("Game modal closed");
  }

  // Handle game link click
  handleGameLinkClick() {
    this.openGameModal();
  }

  // Reset game state when classification starts
  resetGameState() {
    const newTimestamp = Date.now();
    this.gameStartTimestamp = newTimestamp;
    this.progressPercentage = 0;
    this.saveGameTimestamp(newTimestamp);

    // If modal is open, restart the progress bar
    if (this.isGameModalOpen) {
      this.startProgressBar();
    }

    debugLog("Game state reset");
  }

  // Complete game state when classification finishes
  completeGameState() {
    this.progressPercentage = 100;
    this.stopProgressBar();
    this.clearGameTimestamp();
    this.gameStartTimestamp = null;
    debugLog("Game state completed");
  }

  // ==================== Genbank Download Methods ====================

  async handleGenbankDownload() {
    try {
      debugLog(
        "Starting Genbank file generation for quoteRequestId:",
        this.quoteRequestId
      );

      // Trigger the flow to generate fresh Genbank files (S3 links expire)
      const result = await triggerGenerateQuoteSampleMapsFlow({
        quoteRequestId: this.quoteRequestId
      });

      if (result?.success) {
        this.showToast(
          "Info",
          "Generating Genbank files, please wait...",
          "info"
        );
        this.pollForGenbankLink();
      } else {
        const errorMessage =
          result?.message || "Failed to generate Genbank files";
        debugLog("Genbank flow trigger failed:", errorMessage);
        this.showToast("Error", errorMessage, "error");
      }
    } catch (error) {
      debugLog("Error triggering Genbank flow:", error);
      this.showToast(
        "Error",
        "Failed to trigger Genbank file generation. Please try again.",
        "error"
      );
    }
  }

  pollForGenbankLink() {
    const POLL_INTERVAL_MS = 1000; // 1 second
    const MAX_POLL_COUNT = 30; // Poll for up to 30 seconds
    let pollCount = 0;

    const pollTimer = setInterval(async () => {
      pollCount++;
      debugLog(
        `Polling for Genbank link (attempt ${pollCount}/${MAX_POLL_COUNT})`
      );

      try {
        const statusResult = await checkGenbankLinkStatus({
          quoteRequestId: this.quoteRequestId
        });

        if (statusResult?.ready && statusResult?.downloadUrl) {
          // Link is ready! Stop polling and open modal
          clearInterval(pollTimer);
          this.genbankDownloadLink = statusResult.downloadUrl;
          this.isGenbankModalOpen = true;
          debugLog(
            "Genbank files ready, download URL:",
            statusResult.downloadUrl
          );
          this.showToast("Success", "Genbank files are ready!", "success");
        } else if (pollCount >= MAX_POLL_COUNT) {
          // Timeout - stop polling
          clearInterval(pollTimer);
          debugLog("Genbank polling timeout after", MAX_POLL_COUNT, "attempts");
          this.showToast(
            "Warning",
            "Genbank files are taking longer than expected. Please try again in a moment.",
            "warning"
          );
        }
        // Otherwise, continue polling
      } catch (error) {
        debugLog("Error polling for Genbank link:", error);
        clearInterval(pollTimer);
        this.showToast(
          "Error",
          "Failed to check Genbank file status.",
          "error"
        );
      }
    }, POLL_INTERVAL_MS);
  }

  handleCloseGenbankModal() {
    this.isGenbankModalOpen = false;
  }

  handleDownloadGenbank() {
    // Validate download link
    if (!this.genbankDownloadLink?.trim()) {
      this.showToast(
        "Info",
        "Download link is not available yet. Please try again shortly.",
        "info"
      );
      return;
    }

    try {
      this.triggerFileDownload(this.genbankDownloadLink);
    } catch (error) {
      this.handleDownloadFallback(error);
    }
  }

  triggerFileDownload(url) {
    // Create and trigger anchor element for download (works in LWR/Locker)
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.target = "_blank";
    anchor.download = ""; // Optional filename hint

    // Element must be in DOM for LWR/Locker compatibility
    document.body.appendChild(anchor);
    anchor.click();

    // Clean up DOM
    setTimeout(() => {
      try {
        document.body.removeChild(anchor);
      } catch (e) {
        debugLog("Error removing anchor element:", e);
      }
    }, 0);
  }

  handleDownloadFallback(anchorError) {
    try {
      // Fallback to NavigationMixin
      this[NavigationMixin.Navigate]({
        type: "standard__webPage",
        attributes: { url: this.genbankDownloadLink }
      });
    } catch (navError) {
      debugLog(
        "Genbank download errors - Anchor:",
        anchorError,
        "Navigation:",
        navError,
        "URL:",
        this.genbankDownloadLink
      );
      this.showToast(
        "Error",
        "Unable to start download. Please try again or contact support.",
        "error"
      );
    }
  }

  // Disable PDF button while complexity assessment is in progress
  get isPdfButtonDisabled() {
    return this.rowsAwaitingClassification.size > 0;
  }

  // True when the quote request's account has "IDT Channel Partner" ticked
  // (Account.IDT_Channel_Partner__c). Set in wiredQuoteRequest.
  get isIDTChannelPartnership() {
    return this.quoteRequestIsIdtChannelPartner === true;
  }
}
