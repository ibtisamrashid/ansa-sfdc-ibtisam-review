import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import { getRecord } from 'lightning/uiRecordApi';
import { subscribe, unsubscribe, publish, MessageContext } from 'lightning/messageService';
import QUOTE_UPDATE_CHANNEL from '@salesforce/messageChannel/QuoteUpdate__c';
import { pushDataLayerEvent } from 'c/abtGoogleAdsTracking';
import USER_Id from '@salesforce/user/Id';
import getQuoteRequestById from '@salesforce/apex/ABT_Portal_Controller.getQuoteRequestById';
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
    normalizeSequenceNameForCompare
} from 'c/abtProductNameUtils';
import { trancheDisplay } from 'c/abtTrancheUtils';
import getProductById from '@salesforce/apex/ABT_Portal_Controller.getProductById';
import getQuoteRequestDisplayQuoteNumber from '@salesforce/apex/ABT_Portal_Controller.getQuoteRequestDisplayQuoteNumber';
import getQuoteLineItemsWithVectors from '@salesforce/apex/ABT_Portal_Controller.getQuoteLineItemsWithVectors';
import getVectorLibraryData from '@salesforce/apex/ABT_Portal_Controller.getVectorLibraryData';
import getScaleUpLibraryData from '@salesforce/apex/ABT_Portal_Controller.getScaleUpLibraryData';
import getUserDetailsById from '@salesforce/apex/ABT_Portal_Controller.getUserDetailsById';
import isIdtChannelPartnerAccount from '@salesforce/apex/ABT_IdtChannelPartner.isAccountIdtChannelPartner';
import createQuoteRequestLineItem from '@salesforce/apex/ABT_Portal_Controller.createQuoteRequestLineItem';
import createQuoteRequestLineItemsDeferredKick from '@salesforce/apex/ABT_PortalSequenceCreate.createQuoteRequestLineItemsDeferredKick';
import enqueuePendingForQuoteRequest from '@salesforce/apex/ABT_PortalSequenceCreate.enqueuePendingForQuoteRequest';
import updateSequenceForLineItem from '@salesforce/apex/ABT_Portal_Controller.updateSequenceForLineItem';
import deleteRecordById from '@salesforce/apex/ABT_Portal_Controller.deleteRecordById';
import updateQuoteLineItemVector from '@salesforce/apex/ABT_Portal_Controller.updateQuoteLineItemVector';
import bulkUpdateQuoteLineItemVectors from '@salesforce/apex/ABT_Portal_Controller.bulkUpdateQuoteLineItemVectors';
import updateQuoteRequestLineItemGlycerol from '@salesforce/apex/ABT_Portal_Controller.updateQuoteRequestLineItemGlycerol';
import bulkUpdateQuoteRequestLineItemGlycerol from '@salesforce/apex/ABT_Portal_Controller.bulkUpdateQuoteRequestLineItemGlycerol';
import updateQuoteRequestLineItemPotentiallyToxic from '@salesforce/apex/ABT_Portal_Controller.updateQuoteRequestLineItemPotentiallyToxic';
import bulkUpdateQuoteRequestLineItemPotentiallyToxic from '@salesforce/apex/ABT_Portal_Controller.bulkUpdateQuoteRequestLineItemPotentiallyToxic';
import updateQuoteRequestLineItemReflexVectorOptIn from '@salesforce/apex/ABT_Portal_Controller.updateQuoteRequestLineItemReflexVectorOptIn';
import bulkUpdateQuoteRequestLineItemReflexVectorOptIn from '@salesforce/apex/ABT_Portal_Controller.bulkUpdateQuoteRequestLineItemReflexVectorOptIn';
import updateQuoteRequestLineItemScaleUp from '@salesforce/apex/ABT_Portal_Controller.updateQuoteRequestLineItemScaleUp';
import { SCALE_UP_DEFAULT_BUFFER, fromScaleUpNormalizationApiValue, toScaleUpNormalizationApiValue } from 'c/abtScaleUpUtils';
import {
    sequenceNameFromRow,
    sequenceTextFromRow,
    sequenceLengthFromRow,
    normalizeFeasibilityFromRow,
    normalizeComplexityFromRow,
    createQuoteRequestLineItemsChunked
} from 'c/abtPortalLineItemUtils';
import addQuoteRequestToCommerceCart from '@salesforce/apex/ABT_Portal_Controller.addQuoteRequestToCommerceCart';
import removeQuoteRequestFromCommerceCart from '@salesforce/apex/ABT_Portal_Controller.removeQuoteRequestFromCommerceCart';
import getPortalCommerceCart from '@salesforce/apex/ABT_Portal_Controller.getPortalCommerceCart';
import updateQuoteRequestPackaging from '@salesforce/apex/ABT_Portal_Controller.updateQuoteRequestPackaging';
import {
    formatPackagingPicklistOptions,
    PACKAGING_PLACEHOLDER,
    resolvePackagingPicklistValue
} from 'c/abtPackagingUtils';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import QUOTE_REQUEST_OBJECT from '@salesforce/schema/ABT_Quote_Request__c';
import REQUEST_PACKAGING_FIELD from '@salesforce/schema/ABT_Quote_Request__c.Request_Packaging__c';
import QUOTE_REQUEST_LINE_ITEM_OBJECT from '@salesforce/schema/ABT_Quote_Request_Lineitem__c';
import SCALE_UP_BUFFER_FIELD from '@salesforce/schema/ABT_Quote_Request_Lineitem__c.Scale_Up_Buffer__c';
import SCALE_UP_NORMALIZATION_FIELD from '@salesforce/schema/ABT_Quote_Request_Lineitem__c.Scale_Up_Normalization__c';
import {
    DEFAULT_ALLOWED_SEQUENCE_CHARACTERS,
    getAllowedSequenceCharactersText,
    validateSequenceCharacters
} from 'c/abtSequenceValidationUtils';
import deleteQuoteRequest from '@salesforce/apex/ABT_Portal_Controller.deleteQuoteRequest';
import {
    QUOTE_LIST_URL,
    isSalesforceId,
    parseQuoteIdentifierFromPathname
} from 'c/abtQuoteUrls';
import getLineItemPricing from '@salesforce/apex/ABT_Portal_Controller.getLineItemPricing';
import ABT_Ansa_Logo from '@salesforce/resourceUrl/ABT_Ansa_Logo';
import ABT_MiniGame from '@salesforce/resourceUrl/ABT_MiniGame';

import pdfTerms from '@salesforce/label/c.ABT_QuotePdf_Terms_and_Condition';

const PENDING_CART_QR_KEY = 'abt_pendingCartQuoteRequestId';
const CART_PAGE_URL = '/my-cart';
const LINE_ITEM_POLL_INTERVAL_MS = 10000;
const GLYCEROL_POLL_DELAY_MS = 3000;
const GLYCEROL_POLL_MAX_ATTEMPTS = 10;
const GLYCEROL_SYNC_DELAY_MS = 2500;
const GLYCEROL_SYNC_MAX_ATTEMPTS = 8;
const ANSA_CLONAL_DNA_SKU = '1002';
const ANSA_CLONAL_XL_SKUS = new Set(['6001', '6003']);

/** Prep Quantity options for the Scale Up config panel (Scale_Up_Quantity__c restricted picklist 1-5). */
const SCALE_UP_QUANTITY_OPTIONS = [
    { label: '1', value: '1' },
    { label: '2', value: '2' },
    { label: '3', value: '3' },
    { label: '4', value: '4' },
    { label: '5', value: '5' }
];

const QUOTE_PDF_FIELDS = [
    'ABT_Quote_Request__c.ABT_Requested_Date__c',
    'ABT_Quote_Request__c.ABT_Requester_Name__c',
    'ABT_Quote_Request__c.ABT_Expiration_Date__c',
    'ABT_Quote_Request__c.ABT_Total_Price__c',
    'ABT_Quote_Request__c.ABT_Quote__r.Subtotal',
    'ABT_Quote_Request__c.Discount__c',
    'ABT_Quote_Request__c.ABT_Quote__r.GrandTotal',
    'ABT_Quote_Request__c.ABT_Quote__r.End_Customer_Subtotal__c',
    'ABT_Quote_Request__c.ABT_Quote__r.End_Customer_Total__c',
    'ABT_Quote_Request__c.ABT_Billing_Address_Lookup__r.Street',
    'ABT_Quote_Request__c.ABT_Billing_Address_Lookup__r.City',
    'ABT_Quote_Request__c.ABT_Billing_Address_Lookup__r.State',
    'ABT_Quote_Request__c.ABT_Billing_Address_Lookup__r.Country',
    'ABT_Quote_Request__c.ABT_Billing_Address_Lookup__r.PostalCode',
    'ABT_Quote_Request__c.ABT_Shipping_Address_Lookup__r.Street',
    'ABT_Quote_Request__c.ABT_Shipping_Address_Lookup__r.City',
    'ABT_Quote_Request__c.ABT_Shipping_Address_Lookup__r.State',
    'ABT_Quote_Request__c.ABT_Shipping_Address_Lookup__r.Country',
    'ABT_Quote_Request__c.ABT_Shipping_Address_Lookup__r.PostalCode',
    'ABT_Quote_Request__c.ABT_IncoTerms__c',
    'ABT_Quote_Request__c.ABT_Payment_Terms__c',
    'ABT_Quote_Request__c.ABT_Contact__r.Email',
    'ABT_Quote_Request__c.ABT_Account__r.Name',
    'ABT_Quote_Request__c.ABT_Account__r.Special_Agreement__c',
    'ABT_Quote_Request__c.Shipping_Amount__c',
    'ABT_Quote_Request__c.Invoice_Email__c',
    'ABT_Quote_Request__c.Ansa_Quote_Number__c',
    'ABT_Quote_Request__c.Delivery_Format__c',
    'ABT_Quote_Request__c.Yield__c'
];

/** ABT_Stage__c formula values: Draft | Quoted | In Cart | Ordered | Canceled */
function normalizeQuoteStage(stage) {
    return (stage || '').trim();
}

function isDraftStage(stage) {
    return normalizeQuoteStage(stage).toLowerCase() === 'draft';
}

function isQuotedStage(stage) {
    return normalizeQuoteStage(stage).toLowerCase() === 'quoted';
}

function isInCartStage(stage, isInCart) {
    if (isInCart !== true) {
        return false;
    }
    const normalized = normalizeQuoteStage(stage).toLowerCase();
    return normalized === 'in cart' || normalized !== 'ordered';
}

function resolveQuoteStage(stage, isInCart) {
    if (isInCartStage(stage, isInCart)) {
        return 'In Cart';
    }
    if (normalizeQuoteStage(stage).toLowerCase() === 'in cart') {
        return 'Quoted';
    }
    return normalizeQuoteStage(stage);
}

function isViewOnlyStage(stage) {
    const s = normalizeQuoteStage(stage).toLowerCase();
    return s === 'ordered' || s === 'canceled' || s === 'completed';
}

function formatAddress(addr) {
    if (!addr) return 'NA';
    const street = addr.Street?.value ?? addr.Street;
    const city = addr.City?.value ?? addr.City;
    const state = addr.State?.value ?? addr.State;
    const country = addr.Country?.value ?? addr.Country;
    const postal = addr.PostalCode?.value ?? addr.PostalCode;
    const parts = [street, city, state, country].filter(Boolean);
    if (!parts.length) return 'NA';
    return `${parts.join(', ')}${postal ? ` - ${postal}` : ''}`;
}

function formatMoney(value) {
    if (value == null || value === '' || Number.isNaN(Number(value))) return 'NA';
    return Number(value).toFixed(2);
}

function pdfTermsLinkParts(raw) {
    const text = String(raw || '')
        .replace(/<[^>]*>/g, ' ')
        .replace(/\s+/g, ' ')
        .trim();
    const match = text.match(/https?:\/\/[^\s]+/i);
    if (!match) {
        return { before: text, url: '', after: '' };
    }
    const rawUrl = match[0];
    const punct = (rawUrl.match(/[.,;:]+$/) || [''])[0];
    const url = punct ? rawUrl.slice(0, -punct.length) : rawUrl;
    return {
        before: text.slice(0, match.index),
        url,
        after: punct + text.slice(match.index + rawUrl.length)
    };
}

import POTENTIALLY_TOXIC_FIELD from '@salesforce/schema/ABT_Quote_Request_Lineitem__c.Potentially_Toxic__c';

export default class Abt_QuoteDetails extends NavigationMixin(LightningElement) {
    @api recordId;

    _pageRef;

    get effectiveRecordId() {
        const fromApi = (this.recordId || '').trim();
        const fromRef =
            this._pageRef?.attributes?.recordId || this._pageRef?.state?.recordId;
        const fromUrl =
            typeof window !== 'undefined'
                ? parseQuoteIdentifierFromPathname(window.location.pathname)
                : null;

        for (const candidate of [fromApi, fromRef, fromUrl]) {
            const trimmed = (candidate || '').trim();
            if (trimmed && isSalesforceId(trimmed)) {
                return trimmed;
            }
        }
        return null;
    }

    get wiredRecordId() {
        return this.effectiveRecordId || undefined;
    }

    @track activeTab = 'sequences';
    @track isLoading = true;
    @track isProcessing = false;
    @track quoteDisplayId = '';
    @track quoteStage = '';
    @track quoteInCart = false;
    @track productId = null;
    @track productName = '';
    @track productSku = '';
    @track packagingType = '';
    @track packagingOptions = [];
    @track scaleUpBufferOptions = [];
    @track scaleUpNormalizationOptions = [];
    @track _scaleUpBufferDefault = SCALE_UP_DEFAULT_BUFFER;
    _packagingPicklistWireData;
    _packagingFromRecord;
    @track vectorOptions = [];
    @track scaleUpOptions = [];
    @track isScaleUpEnabled = false;
    @track isScaleUpProductEnabled = false;
    @track isGlycerolStockEnabled = false;
    @track accountDefaultGlycerol = false;
    @track isVectorProductEnabled = false;
    @track allowedSequenceCharacters = DEFAULT_ALLOWED_SEQUENCE_CHARACTERS;
    @track quoteHeaderVector = '';
    /** Contact.Default_Vector__c — fallback when quote has no header vector */
    defaultVectorId = null;
    /** Last vector chosen on a row/draft — overrides header/contact for new empty rows */
    _workingVectorId = null;
    @track _sequences = [];
    @track _draftRows = [];
    /** Debounce timers for draft-row validation display (draftId → timeoutId). */
    _draftValidationTimers = new Map();
    static DRAFT_VALIDATION_DELAY_MS = 1000;
    /** Serializes draft→Salesforce creates so concurrent pastes share one batch update. */
    _draftCommitTail = Promise.resolve();
    @track sequenceLengthLimits = { min: 200, max: 600 };
    _localIdCounter = 0;

    @track showEditModal = false;
    @track showDeleteQuoteModal = false;
    @track editSequenceName = '';
    @track editSequenceVector = '';
    @track editSequenceText = '';
    @track editSequenceError = '';
    @track editSequenceNameError = '';
    @track editSequenceVectorError = '';
    @track editSequenceCharCount = 0;
    @track editingSequenceId = null;
    @track isInsertingSequence = false;
    @track isModalSaveInProgress = false;
    @track _glycerolUpdatingIds = [];
    @track _deletingSequenceIds = [];
    @track _reflexPopoverLineId = null;
    @track _scaleUpPopoverLineId = null;
    @track _scaleUpDefinitionsOpen = false;
    @track _scaleUpUpdatingIds = [];
    @track _scaleUpSavingIds = [];
    @track bulkVectorValue = '';
    @track bulkReflexChecked = false;
    @track bulkToxicChecked = false;
    @track bulkGlycerolChecked = false;
    @track _bulkUpdateCount = 0;

    _scaleUpClearInFlightIds = new Set();

    accountRecordId;
    accountIsIdtChannelPartner = false;
    userId = USER_Id;
    wiredQuoteResult;
    wiredLineItemsResult;
    wiredPdfRecordResult;
    ansaLogo = ABT_Ansa_Logo;
    messageContext;
    subscription;
    _lineItemPollingTimer = null;
    _pendingGlycerolApplyIds = new Set();
    _deferredGlycerolApplyInFlight = false;
    _navigatingAway = false;
    _editOriginalSnapshot = null;
    _wasFeasibilityPending = undefined;

    // Mini-Game Modal (Helix Rush while feasibility is calculated)
    @track isGameModalOpen = false;
    @track gameStartTimestamp = null;
    @track progressPercentage = 0;
    progressTimer = null;
    gameResourceUrl = ABT_MiniGame;

    @track quoteRequestInfo = {};
    quoteId = null;
    _baseQuoteStage = '';

    @wire(getObjectInfo, { objectApiName: QUOTE_REQUEST_OBJECT })
    quoteRequestObjectInfo;

    @wire(getObjectInfo, { objectApiName: QUOTE_REQUEST_LINE_ITEM_OBJECT })
    quoteRequestLineItemObjectInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$quoteRequestObjectInfo.data.defaultRecordTypeId',
        fieldApiName: REQUEST_PACKAGING_FIELD
    })
    wiredPackagingPicklist({ data, error }) {
        if (data) {
            this._packagingPicklistWireData = data;
            this.packagingOptions = formatPackagingPicklistOptions(data);
            this._syncPackagingSelection();
        } else if (error) {
            console.error('Error loading packaging picklist:', error);
        }
    }

    @wire(getPicklistValues, {
        recordTypeId: '$quoteRequestLineItemObjectInfo.data.defaultRecordTypeId',
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
            console.error('Error loading Scale Up Buffer picklist:', error);
        }
    }

    @wire(getPicklistValues, {
        recordTypeId: '$quoteRequestLineItemObjectInfo.data.defaultRecordTypeId',
        fieldApiName: SCALE_UP_NORMALIZATION_FIELD
    })
    wiredScaleUpNormalizationPicklist({ data, error }) {
        if (data) {
            this.scaleUpNormalizationOptions = (data.values || []).map((opt) => ({
                label: opt.label,
                value: opt.value
            }));
        } else if (error) {
            console.error('Error loading Scale Up Normalization picklist:', error);
        }
    }

    @wire(CurrentPageReference)
    handlePageReference(pageRef) {
        this._pageRef = pageRef;
        if (this.effectiveRecordId) {
            this._loadPageData();
        } else {
            this.isLoading = false;
        }
    }

    @wire(MessageContext)
    setMessageContext(value) {
        this.messageContext = value;
        if (value && !this.subscription) {
            this.subscription = subscribe(value, QUOTE_UPDATE_CHANNEL, (message) => {
                this._handleQuoteUpdateMessage(message);
            });
        }
    }

    _handleQuoteUpdateMessage(message) {
        if (!message || message.quoteRequestId !== this.effectiveRecordId) {
            return;
        }
        // Glycerol/line pricing is merged locally; refreshing the line-item wire races the update.
        if (message.updateType === 'pricing_refresh' && message.details?.lineItemId) {
            if (this.wiredQuoteResult) {
                refreshApex(this.wiredQuoteResult);
            }
            if (this.wiredPdfRecordResult) {
                refreshApex(this.wiredPdfRecordResult);
            }
            return;
        }
        this.refreshData();
    }

    disconnectedCallback() {
        if (this._boundCloseReflexPopover) {
            document.removeEventListener('click', this._boundCloseReflexPopover, true);
        }
        this._clearAllDraftValidationTimers();
        this._navigatingAway = true;
        if (this.subscription) {
            unsubscribe(this.subscription);
            this.subscription = null;
        }
        this._stopLineItemPolling();
        this.stopProgressBar();
    }

    _applyQuoteStage() {
        this.quoteStage = resolveQuoteStage(this._baseQuoteStage, this.quoteInCart);
    }

    _refreshQuoteCartState() {
        if (!this.quoteId) {
            this.quoteInCart = false;
            this._applyQuoteStage();
            return Promise.resolve(false);
        }

        return getPortalCommerceCart({ userId: this.userId })
            .then((quotes) => {
                this.quoteInCart = (quotes || []).some((quote) => quote.Id === this.quoteId);
                this._applyQuoteStage();
                return this.quoteInCart;
            })
            .catch((error) => {
                console.error('Error loading cart membership for quote detail:', error);
                this.quoteInCart = false;
                this._applyQuoteStage();
                return false;
            });
    }

    _syncQuoteHeaderFromWire(data) {
        this.quoteId = data.ABT_Quote__c || null;
        this._baseQuoteStage = normalizeQuoteStage(data.ABT_Stage__c);
        this._applyQuoteStage();
        this._refreshQuoteCartState();
    }

    @wire(getQuoteRequestById, { quoteRequestId: '$wiredRecordId' })
    wiredQuote(value) {
        this.wiredQuoteResult = value;
        const { data, error } = value;
        if (data) {
            this._syncQuoteHeaderFromWire(data);
            this.productId = data.ABT_Product__c || null;
            this.productName = formatProductName(data.ABT_Product_Name__c) || '';
            this.productSku = data.ABT_Product__r?.StockKeepingUnit || '';
            this.quoteHeaderVector = data.Vector__c || '';
            this._packagingFromRecord = data.Request_Packaging__c;
            this._syncPackagingSelection();
            this.fetchProductSequenceLimits();
            this._syncEmptyDraftVectorsFromDefault();
            this.isLoading = false;
        } else if (error) {
            if (!this.wiredRecordId) {
                this.isLoading = false;
                return;
            }
            console.error('Error loading quote request:', error);
            this.isLoading = false;
        }
    }

    @wire(getQuoteLineItemsWithVectors, { quoteRequestId: '$wiredRecordId' })
    wiredLineItems(value) {
        this.wiredLineItemsResult = value;
        const { data, error } = value;
        if (data) {
            this._mergeLineItemsFromWire(data);
            this._startPollingForPendingLineItems();
            this._applyFeasibilityGameState();
        } else if (error && this.wiredRecordId) {
            console.error('Error loading line items:', error);
        }
    }

    @wire(getRecord, { recordId: '$wiredRecordId', fields: QUOTE_PDF_FIELDS })
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
        const specialAgreement = accountFields?.Special_Agreement__c?.value || pdfTerms;
        const termsParts = pdfTermsLinkParts(specialAgreement);

        this.quoteRequestInfo = {
            contactName: f.ABT_Requester_Name__c?.value || 'NA',
            createdDate: f.ABT_Requested_Date__c?.displayValue || 'NA',
            expiryDate: f.ABT_Expiration_Date__c?.displayValue || 'NA',
            totalPrice: formatMoney(f.ABT_Total_Price__c?.value),
            quoteNumber: f.Ansa_Quote_Number__c?.value || this.quoteDisplayId || 'NA',
            subTotal: formatMoney(quoteFields?.Subtotal?.value),
            formattedDiscount: discountValue > 0 ? `-$${formatMoney(discountValue)}` : null,
            contactEmail: f.ABT_Contact__r?.value?.fields?.Email?.value || 'NA',
            billTo: formatAddress(f.ABT_Billing_Address_Lookup__r?.value?.fields),
            shipTo: formatAddress(f.ABT_Shipping_Address_Lookup__r?.value?.fields),
            paymentTerms: f.ABT_Payment_Terms__c?.value || 'NA',
            incoTerms: f.ABT_IncoTerms__c?.value || 'NA',
            accountName: accountFields?.Name?.value || 'NA',
            invoiceEmail: f.Invoice_Email__c?.value || 'NA',
            shippingAmount: formatMoney(f.Shipping_Amount__c?.value),
            specialAgreement,
            specialAgreementBeforeUrl: termsParts.before,
            specialAgreementUrl: termsParts.url,
            specialAgreementAfterUrl: termsParts.after,
            endCustomerSubtotal: formatMoney(quoteFields?.End_Customer_Subtotal__c?.value),
            endCustomerTotal: formatMoney(quoteFields?.End_Customer_Total__c?.value),
            deliveryFormat: f.Delivery_Format__c?.value || 'NA',
            yield: f.Yield__c?.value || 'NA'
        };
    }

    connectedCallback() {
        this._boundCloseReflexPopover = this._closeOpenPopoversOnOutsideClick.bind(this);
        document.addEventListener('click', this._boundCloseReflexPopover, true);
        this._loadPageData();
        this._refreshQuoteHeaderFromServer();

        const savedTimestamp = this.loadGameTimestamp();
        if (savedTimestamp) {
            this.gameStartTimestamp = savedTimestamp;
        }
    }

    _refreshQuoteHeaderFromServer() {
        if (!this.effectiveRecordId) {
            return;
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        Promise.resolve().then(() => {
            if (this.wiredQuoteResult) {
                refreshApex(this.wiredQuoteResult);
            }
        });
    }

    _loadPageData() {
        if (!this.effectiveRecordId) {
            return;
        }
        getUserDetailsById({ userId: this.userId })
            .then(user => {
                this.accountRecordId = user.AccountId;
                return Promise.all([
                    getQuoteRequestDisplayQuoteNumber({ quoteRequestId: this.effectiveRecordId }),
                    getVectorLibraryData({ currentUserAccountId: user.AccountId }),
                    getScaleUpLibraryData({ accountId: user.AccountId }),
                    isIdtChannelPartnerAccount({ accountId: user.AccountId })
                ]);
            })
            .then(([displayId, vectorData, scaleUpData, isIdt]) => {
                this.accountIsIdtChannelPartner = isIdt === true;
                if (displayId) {
                    this.quoteDisplayId = displayId;
                }
                this._buildVectorOptions(vectorData);
                this.isScaleUpEnabled = scaleUpData?.scaleUpEnabled === true;
                this.accountDefaultGlycerol = scaleUpData?.defaultGlycerol === true;
                this.scaleUpOptions = (scaleUpData?.scaleUpOptions || []).map(o => ({
                    label: o.label,
                    value: o.value
                }));
            })
            .catch(err => console.error('Error loading quote detail data:', err));
    }

    fetchProductSequenceLimits() {
        if (!this.productId) {
            return Promise.resolve();
        }

        return getProductById({ productId: this.productId })
            .then(product => {
                this.isGlycerolStockEnabled = product?.Glycerol_Stock_Enabled__c === true;
                this.isScaleUpProductEnabled = product?.Scale_Up_Enabled__c === true;
                this.isVectorProductEnabled = product?.Vector_Enabled__c === true;
                this._sequences = (this._sequences || []).map(seq =>
                    this._withAdditionalFees(this._sequenceForFeeDisplay(seq))
                );
                if (!this.isVectorProductEnabled) {
                    this.quoteHeaderVector = '';
                    this._sequences = (this._sequences || []).map(seq => ({
                        ...seq,
                        vector: ''
                    }));
                }
                const parsedMin = parseInt(product?.Minimum_Length__c, 10);
                const parsedMax = parseInt(product?.Maximum_Length__c, 10);
                this.allowedSequenceCharacters = product?.Allowed_Characters__c || DEFAULT_ALLOWED_SEQUENCE_CHARACTERS;
                const min = Number.isFinite(parsedMin) ? parsedMin : 200;
                const max = Number.isFinite(parsedMax) ? parsedMax : 600;
                this.sequenceLengthLimits = {
                    min,
                    max: max >= min ? max : min
                };
                this._syncEmptyDraftVectorsFromDefault();
            })
            .catch(error => {
                console.error('Error loading product sequence limits:', JSON.stringify(error));
            });
    }

    _buildVectorOptions(vectorData) {
        const defaultVectorId = vectorData?.defaultVectorId || null;
        this.defaultVectorId = defaultVectorId;
        const allVectors = [
            ...(vectorData?.catalogVectors || []),
            ...(vectorData?.customVectors || [])
        ];
        this.vectorOptions = [
            { label: '-- None --', value: 'none' },
            ...allVectors.map(v => ({
                label: v.Id === defaultVectorId ? `${v.Name} (Default)` : v.Name,
                value: v.Id,
                reflexApplicable: v.Reflex_Applicable__c === true,
                copyNumber: v.Copy_Number__c || ''
            }))
        ];
        this._syncEmptyDraftVectorsFromDefault();
    }

    /**
     * Prefer last in-session vector choice, then quote header, then Contact.Default_Vector__c.
     */
    _effectiveVectorForNewRows() {
        if (!this.showVectorSelection) {
            return '';
        }
        if (this._workingVectorId && this._workingVectorId !== 'none') {
            return this._workingVectorId;
        }
        const header = this.quoteHeaderVector;
        if (header && header !== 'none') {
            return header;
        }
        if (
            this.defaultVectorId
            && (this.vectorOptions || []).some((opt) => opt.value === this.defaultVectorId)
        ) {
            return this.defaultVectorId;
        }
        return '';
    }

    _syncEmptyDraftVectorsFromDefault() {
        const vector = this._effectiveVectorForNewRows();
        this._draftRows = (this._draftRows || []).map((row) => {
            if (this._isDraftRowEmpty(row) && !row.isSaving) {
                return { ...row, vector };
            }
            return row;
        });
    }

    _setWorkingVectorDefault(vectorId) {
        if (!this.showVectorSelection) {
            return;
        }
        const normalized = (!vectorId || vectorId === 'none') ? '' : vectorId;
        this._workingVectorId = normalized || null;
        this._syncEmptyDraftVectorsFromDefault();
    }

    _sequenceRecordFromRow(row) {
        return row?.Related_Sequence__r || null;
    }

    _sequenceNameFromRow(row) {
        return sequenceNameFromRow(row);
    }

    _sequenceTextFromRow(row) {
        return sequenceTextFromRow(row);
    }

    _sequenceLengthFromRow(row) {
        return sequenceLengthFromRow(row);
    }

    _vectorIdFromRow(row, quoteLineItem = null) {
        const sequenceRecord = this._sequenceRecordFromRow(row);
        return sequenceRecord?.Vector__c || quoteLineItem?.Vector__c || '';
    }

    _normalizeFeasibilityFromRow(row, quoteLineItem) {
        return normalizeFeasibilityFromRow(row, quoteLineItem);
    }

    _normalizeComplexityFromRow(row) {
        return normalizeComplexityFromRow(row);
    }

    _normalizeTotalPriceFromRow(row) {
        const totalPriceValue = row?.Total_Combined_Price__c ?? row?.ABT_Total_Price__c;
        const parsedPrice = Number(totalPriceValue);
        if (Number.isFinite(parsedPrice) && parsedPrice > 0) {
            return `$${parsedPrice.toFixed(2)}`;
        }
        return undefined;
    }

    _hasGlycerolFeeIntent(seq = {}) {
        return seq.glycerol === true
            || (seq.scaleUpSelected === true && seq.scaleUpGlycerolStock === true);
    }

    _parseFeeAmount(value) {
        return parseFloat(String(value || '0').replace('$', '').replace(',', '').replace('NA', '0')) || 0;
    }

    _recalculateSequenceTotal(seq = {}) {
        const base = Number(seq.basePrice);
        const scaleUp = seq.scaleUpSelected === true ? this._parseFeeAmount(seq.scaleUpFee) : 0;
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
        const combined = Number(row?.Total_Combined_Price__c);
        const glycerol = Number(row?.Glycerol_Price__c) || 0;
        const scaleUpSelected = seq.scaleUpSelected === true;
        const scaleUpRaw = Number(
            row?.Scale_Up_Price__c ?? row?.ABT_Quote_Line_Item__r?.Scale_Up_Price__c
        ) || 0;
        const scaleUp = scaleUpSelected ? scaleUpRaw : 0;
        const glycFee = includeGlycerol
            ? (this._parseFeeAmount(seq.glycerolFee) || glycerol)
            : 0;

        if (Number.isFinite(base) && base >= 0) {
            const total = base + scaleUp + glycFee;
            return `$${total.toFixed(2)}`;
        }
        if (Number.isFinite(combined) && combined > 0) {
            let total = combined;
            if (!includeGlycerol && glycerol > 0) {
                total -= glycerol;
            }
            if (!scaleUpSelected && scaleUpRaw > 0) {
                total -= scaleUpRaw;
            }
            return `$${Math.max(0, total).toFixed(2)}`;
        }
        return seq.totalPrice || '$0.00';
    }

    _adjustTotalPriceForGlycerolToggle(seq, enabled, feeAmount) {
        const current = parseFloat((seq.totalPrice || '$0').replace('$', '').replace(',', '')) || 0;
        const fee = feeAmount != null
            ? Number(feeAmount)
            : parseFloat((seq.glycerolFee || '$0').replace('$', '').replace('NA', '0')) || 0;
        if (!Number.isFinite(fee) || fee <= 0) {
            return seq.totalPrice || '$0.00';
        }
        const adjusted = enabled ? current + fee : Math.max(0, current - fee);
        return `$${adjusted.toFixed(2)}`;
    }

    _isFeasibilityPending(seq) {
        const f = (seq?.feasibility || '').trim();
        return !f || f.toLowerCase() === 'pending';
    }

    _isComplexityPending(seq) {
        const c = (seq?.complexity || '').trim();
        return !c || c.toLowerCase() === 'pending';
    }

    _isAsEarlyAsDatePending(seq) {
        return String(seq?.asEarlyAsDate || '')
            .trim()
            .toLowerCase() === 'pending';
    }

    _isGuaranteedDatePending(seq) {
        return String(seq?.guaranteedDate || '')
            .trim()
            .toLowerCase() === 'pending';
    }

    _isLineItemCalculationComplete(row) {
        if (!row) {
            return false;
        }
        const qli = row.ABT_Quote_Line_Item__r || {};
        if (this._isFeasibilityPending({ feasibility: this._normalizeFeasibilityFromRow(row, qli) })
            || this._isComplexityPending({ complexity: this._normalizeComplexityFromRow(row) })
            || !this._normalizeTotalPriceFromRow(row)) {
            return false;
        }
        return true;
    }

    _formatGlycerolFee(price) {
        if (price == null || price === '') {
            return null;
        }
        const parsed = Number(price);
        if (!Number.isFinite(parsed) || parsed <= 0) {
            return null;
        }
        return `$${parsed.toFixed(2)}`;
    }

    _resolveGlycerolFeeFromLineItem(row, glycerol) {
        if (!glycerol) {
            return null;
        }
        const explicit = this._formatGlycerolFee(row?.Glycerol_Price__c);
        if (explicit) {
            return explicit;
        }
        const base = Number(row?.ABT_Total_Price__c);
        const combined = Number(row?.Total_Combined_Price__c);
        if (Number.isFinite(combined) && Number.isFinite(base) && combined > base) {
            return `$${(combined - base).toFixed(2)}`;
        }
        return null;
    }

    _effectiveGlycerolFee(seq = {}) {
        if (!this._hasGlycerolFeeIntent(seq)) {
            return null;
        }
        if (seq.glycerolFee) {
            return seq.glycerolFee;
        }
        return this._resolveGlycerolFeeFromLineItem({
            Glycerol_Price__c: seq.glycerolPriceRaw,
            ABT_Total_Price__c: seq.basePrice,
            Total_Combined_Price__c: seq.combinedPrice
        }, true);
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
        if (price == null || price === '' || Number.isNaN(Number(price))) {
            return null;
        }
        return Number(price).toFixed(2);
    }

    _sumAdditionalFees(seq = {}) {
        if (!this.showAddlFeesSelection) {
            return 0;
        }
        const scaleUp = seq.scaleUpSelected === true
            ? this._parseFeeAmount(seq.scaleUpFee || seq.scaleUpPriceDisplay)
            : 0;
        const glycerol = this._parseFeeAmount(this._effectiveGlycerolFee(seq));
        return scaleUp + glycerol;
    }

    _effectiveGlycerolStock(checked) {
        return this.showGlycerolSelection && this.isGlycerolApplicable && checked === true;
    }

    _formatAdditionalFeesDisplay(seq = {}) {
        const sum = this._sumAdditionalFees(seq);
        return sum > 0 ? `$${sum.toFixed(2)}` : 'NA';
    }

    _withAdditionalFees(seq) {
        return {
            ...seq,
            additionalFees: this._formatAdditionalFeesDisplay(seq)
        };
    }

    /** Empty Scale Up UI state used when the checkbox is cleared. */
    _clearedScaleUpUiFields() {
        return {
            scaleUpSelected: false,
            scaleUpQuantity: '',
            scaleUpGlycerolStock: false,
            scaleUpBuffer: '',
            scaleUpNormalization: '',
            scaleUpEndotoxinFree: false,
            scaleUpAnimalFree: false,
            scaleUpMass: '',
            scaleUpPriceDisplay: '',
            scaleUpLeadTime: '',
            scaleUpFee: null
        };
    }

    _shouldApplyDefaultGlycerolForNewSequence() {
        return this.showGlycerolSelection && this.isGlycerolApplicable && this.accountDefaultGlycerol === true;
    }

    _queueDefaultGlycerolApply(lineItemId) {
        if (!lineItemId || !this._shouldApplyDefaultGlycerolForNewSequence()) {
            return;
        }
        this._pendingGlycerolApplyIds.add(String(lineItemId));
    }

    _applyPendingGlycerolIfReady() {
        if (!this._pendingGlycerolApplyIds?.size || this._deferredGlycerolApplyInFlight) {
            return Promise.resolve();
        }

        this._deferredGlycerolApplyInFlight = true;
        const lineItemIds = [...this._pendingGlycerolApplyIds];
        this._pendingGlycerolApplyIds = new Set();
        lineItemIds.forEach((lineItemId) => this._addGlycerolUpdating(lineItemId));

        return this._bulkApplyGlycerolWithRetry(lineItemIds, true, 0)
            .finally(() => {
                lineItemIds.forEach((lineItemId) => this._removeGlycerolUpdating(lineItemId));
                this._deferredGlycerolApplyInFlight = false;
                if (this._pendingGlycerolApplyIds?.size) {
                    this._applyPendingGlycerolIfReady();
                }
            });
    }

    // One bulk Apex call with lock retry so default glycerol does not fire N parallel QLI updates.
    _bulkApplyGlycerolWithRetry(lineItemIds, glycerolStock, attempt = 0) {
        if (!lineItemIds?.length) {
            return Promise.resolve();
        }
        return bulkUpdateQuoteRequestLineItemGlycerol({
            lineItemIds,
            glycerolStockFlags: lineItemIds.map(() => glycerolStock === true)
        }).then((result) => {
            if (!result?.success) {
                if (result?.retryable && attempt < GLYCEROL_SYNC_MAX_ATTEMPTS) {
                    return new Promise((resolve) => {
                        // eslint-disable-next-line @lwc/lwc/no-async-operation
                        setTimeout(() => {
                            resolve(this._bulkApplyGlycerolWithRetry(lineItemIds, glycerolStock, attempt + 1));
                        }, GLYCEROL_SYNC_DELAY_MS);
                    });
                }
                throw new Error(result?.error || 'Glycerol update failed');
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
                lineItemIds.map((lineItemId) => this._pollLineItemPricingUntilGlycerolSettled(lineItemId))
            );
        }).catch((err) => {
            if (this._isRetryableGlycerolError(err) && attempt < GLYCEROL_SYNC_MAX_ATTEMPTS) {
                return new Promise((resolve) => {
                    // eslint-disable-next-line @lwc/lwc/no-async-operation
                    setTimeout(() => {
                        resolve(this._bulkApplyGlycerolWithRetry(lineItemIds, glycerolStock, attempt + 1));
                    }, GLYCEROL_SYNC_DELAY_MS);
                });
            }
            console.error('Deferred glycerol apply failed:', err);
            return Promise.resolve();
        });
    }

    _isRetryableGlycerolError(err) {
        const message = String(
            err?.message || err?.body?.message || err?.body?.pageErrors?.[0]?.message || ''
        );
        return message.includes('UNABLE_TO_LOCK_ROW');
    }

    _applyGlycerolToLineItemWithRetry(lineItemId, attempt = 0) {
        return getLineItemPricing({ lineItemId })
            .then(li => {
                if (!li?.ABT_Quote_Line_Item__c) {
                    if (attempt < GLYCEROL_SYNC_MAX_ATTEMPTS) {
                        return new Promise(resolve => {
                            // eslint-disable-next-line @lwc/lwc/no-async-operation
                            setTimeout(() => {
                                resolve(this._applyGlycerolToLineItemWithRetry(lineItemId, attempt + 1));
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
                }).then(result => {
                    if (!result?.success) {
                        if (result?.retryable && attempt < GLYCEROL_SYNC_MAX_ATTEMPTS) {
                            return new Promise(resolve => {
                                // eslint-disable-next-line @lwc/lwc/no-async-operation
                                setTimeout(() => {
                                    resolve(this._applyGlycerolToLineItemWithRetry(lineItemId, attempt + 1));
                                }, GLYCEROL_SYNC_DELAY_MS);
                            });
                        }
                        return Promise.reject(new Error(result?.error || 'Glycerol apply failed'));
                    }
                    const fee = this._formatGlycerolFee(result.glycerolPrice);
                    this._sequences = this._sequences.map(s =>
                        String(s.id) === String(lineItemId)
                            ? this._withAdditionalFees({
                                ...s,
                                glycerol: result.glycerolStock === true,
                                glycerolFee: fee ?? s.glycerolFee
                            })
                            : s
                    );
                    return this._pollLineItemPricingUntilGlycerolSettled(lineItemId);
                }).finally(() => {
                    this._removeGlycerolUpdating(lineItemId);
                }).catch(err => {
                    if (this._isRetryableGlycerolError(err) && attempt < GLYCEROL_SYNC_MAX_ATTEMPTS) {
                        return new Promise(resolve => {
                            // eslint-disable-next-line @lwc/lwc/no-async-operation
                            setTimeout(() => {
                                resolve(this._applyGlycerolToLineItemWithRetry(lineItemId, attempt + 1));
                            }, GLYCEROL_SYNC_DELAY_MS);
                        });
                    }
                    console.error('Deferred glycerol apply failed:', err);
                });
            })
            .catch(() => {
                if (attempt < GLYCEROL_SYNC_MAX_ATTEMPTS) {
                    return new Promise(resolve => {
                        // eslint-disable-next-line @lwc/lwc/no-async-operation
                        setTimeout(() => {
                            resolve(this._applyGlycerolToLineItemWithRetry(lineItemId, attempt + 1));
                        }, GLYCEROL_SYNC_DELAY_MS);
                    });
                }
                return Promise.resolve();
            });
    }

    _glycerolFieldsFromLineItem(li, seq = {}) {
        const stock = li?.Glycerol_Stock__c === true;
        const scaleUpGlycerol = (li?.Scale_Up_Selected__c === true && li?.Scale_Up_Glycerol_Stock__c === true)
            || (seq.scaleUpSelected === true && seq.scaleUpGlycerolStock === true);
        const hasFeeIntent = stock || scaleUpGlycerol;
        const fee = this._resolveGlycerolFeeFromLineItem(li, hasFeeIntent);
        return {
            glycerol: stock,
            glycerolFee: hasFeeIntent ? (fee ?? seq.glycerolFee ?? null) : null,
            glycerolPriceRaw: li?.Glycerol_Price__c,
            basePrice: li?.ABT_Total_Price__c ?? seq.basePrice,
            combinedPrice: li?.Total_Combined_Price__c ?? seq.combinedPrice
        };
    }

    _glycerolFieldsFromLineItemWithLocalState(li, seq = {}) {
        if (this._isGlycerolUpdatingLine(seq.id)) {
            const hasFeeIntent = seq.glycerol === true || seq.scaleUpGlycerolStock === true;
            return {
                glycerol: seq.glycerol === true,
                glycerolFee: hasFeeIntent ? (seq.glycerolFee ?? null) : null,
                glycerolPriceRaw: li?.Glycerol_Price__c ?? seq.glycerolPriceRaw,
                basePrice: li?.ABT_Total_Price__c ?? seq.basePrice,
                combinedPrice: li?.Total_Combined_Price__c ?? seq.combinedPrice
            };
        }
        const serverGlycerol = li?.Glycerol_Stock__c === true;
        const localGlycerol = seq.glycerol === true;
        const localGlycerolExplicit = typeof seq.glycerol === 'boolean';
        if (localGlycerolExplicit && serverGlycerol !== localGlycerol) {
            const hasFeeIntent = localGlycerol || seq.scaleUpGlycerolStock === true
                || li?.Scale_Up_Glycerol_Stock__c === true;
            return {
                glycerol: localGlycerol,
                glycerolFee: hasFeeIntent ? (seq.glycerolFee ?? null) : null,
                glycerolPriceRaw: li?.Glycerol_Price__c ?? seq.glycerolPriceRaw,
                basePrice: li?.ABT_Total_Price__c ?? seq.basePrice,
                combinedPrice: li?.Total_Combined_Price__c ?? seq.combinedPrice
            };
        }
        return this._glycerolFieldsFromLineItem(li, seq);
    }

    _pricingExtrasFromLineItem(li, seq = {}) {
        const qli = li?.ABT_Quote_Line_Item__r;
        const scaleUpFields = this._scaleUpFieldsFromLineItem(li, seq);
        const scaleUpPrice = li?.Scale_Up_Price__c ?? qli?.Scale_Up_Price__c;
        // When Scale Up is off, never keep a stale fee from previous local state.
        const scaleUpFee = scaleUpFields.scaleUpSelected === true
            ? (this._formatCurrencyFee(scaleUpPrice) || seq.scaleUpFee || null)
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

    /** Maps Scale Up config fields from a line item, clearing when Salesforce Selected is false. */
    _scaleUpFieldsFromLineItem(li, seq = {}) {
        const has = (v) => v !== undefined && v !== null;
        const lineId = String(seq.id || li?.Id || '');
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
        // Local UI already cleared; keep it cleared until Salesforce Selected flips back to true.
        if (seq.scaleUpSelected !== true && has(li?.Scale_Up_Selected__c) && li.Scale_Up_Selected__c !== true) {
            return this._clearedScaleUpUiFields();
        }
        if (seq.scaleUpSelected !== true && !has(li?.Scale_Up_Selected__c)) {
            return this._clearedScaleUpUiFields();
        }
        const qli = li?.ABT_Quote_Line_Item__r;
        const mass = has(li?.Scale_Up_Mass__c)
            ? li.Scale_Up_Mass__c
            : (has(qli?.Scale_Up_Mass__c) ? qli.Scale_Up_Mass__c : undefined);
        const price = has(li?.Scale_Up_Price__c)
            ? li.Scale_Up_Price__c
            : (has(qli?.Scale_Up_Price__c) ? qli.Scale_Up_Price__c : undefined);
        const leadTime = has(li?.Scale_Up_Lead_Time__c)
            ? li.Scale_Up_Lead_Time__c
            : (has(qli?.Scale_Up_Lead_Time__c) ? qli.Scale_Up_Lead_Time__c : undefined);
        return {
            scaleUpSelected: has(li?.Scale_Up_Selected__c) ? li.Scale_Up_Selected__c === true : (seq.scaleUpSelected === true),
            scaleUpQuantity: has(li?.Scale_Up_Quantity__c) ? String(li.Scale_Up_Quantity__c) : (seq.scaleUpQuantity || ''),
            scaleUpGlycerolStock: has(li?.Scale_Up_Glycerol_Stock__c) ? li.Scale_Up_Glycerol_Stock__c === true : (seq.scaleUpGlycerolStock === true),
            scaleUpBuffer: has(li?.Scale_Up_Buffer__c) ? (li.Scale_Up_Buffer__c || '') : (seq.scaleUpBuffer || ''),
            scaleUpNormalization: has(li?.Scale_Up_Normalization__c)
                ? fromScaleUpNormalizationApiValue(li.Scale_Up_Normalization__c)
                : (seq.scaleUpNormalization || ''),
            scaleUpEndotoxinFree: has(li?.Scale_Up_Endotoxin_Free__c) ? li.Scale_Up_Endotoxin_Free__c === true : (seq.scaleUpEndotoxinFree === true),
            scaleUpAnimalFree: has(li?.Scale_Up_Animal_Free__c) ? li.Scale_Up_Animal_Free__c === true : (seq.scaleUpAnimalFree === true),
            scaleUpMass: has(mass) ? (mass || '') : (seq.scaleUpMass || ''),
            scaleUpPriceDisplay: this._formatCurrencyFee(price) || seq.scaleUpPriceDisplay || '',
            scaleUpLeadTime: has(leadTime) ? (leadTime || '') : (seq.scaleUpLeadTime || '')
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
        const scaleUpGlycerol = li.Scale_Up_Glycerol_Stock__c === true
            || (seq.scaleUpSelected === true && seq.scaleUpGlycerolStock === true);
        const glycerolPrice = Number(li.Glycerol_Price__c) || 0;
        // Wait for price only when glycerol is intentionally on.
        // Orphan Glycerol_Price leftovers must not leave the UI stuck on "Updating...".
        if ((localStock || scaleUpGlycerol) && glycerolPrice <= 0) {
            return false;
        }
        return true;
    }

    _mergeLineItemsFromWire(rows) {
        const existingById = new Map(
            (this._sequences || []).map(seq => [String(seq.id), seq])
        );
        this._sequences = (rows || []).map(row => {
            const existing = existingById.get(String(row.Id));
            return this._mapLineItem(row, existing);
        });
    }

    _addGlycerolUpdating(lineItemId) {
        const key = String(lineItemId);
        if (!this._glycerolUpdatingIds.includes(key)) {
            this._glycerolUpdatingIds = [...this._glycerolUpdatingIds, key];
        }
    }

    _removeGlycerolUpdating(lineItemId) {
        const key = String(lineItemId);
        this._glycerolUpdatingIds = this._glycerolUpdatingIds.filter(id => id !== key);
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
        this._deletingSequenceIds = this._deletingSequenceIds.filter(id => id !== key);
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
        this._scaleUpUpdatingIds = this._scaleUpUpdatingIds.filter(id => id !== key);
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
        this._scaleUpSavingIds = this._scaleUpSavingIds.filter(id => id !== key);
    }

    _isScaleUpSavingLine(lineItemId) {
        return this._scaleUpSavingIds.includes(String(lineItemId));
    }

    _vectorOptionForId(vectorId) {
        if (!vectorId || vectorId === 'none') {
            return null;
        }
        return (this.vectorOptions || []).find(opt => opt.value === vectorId) || null;
    }

    _isReflexApplicableVector(vectorId) {
        return this._vectorOptionForId(vectorId)?.reflexApplicable === true;
    }

    _copyNumberForVector(vectorId) {
        return this._vectorOptionForId(vectorId)?.copyNumber || '';
    }

    _isEventInsideOpenPopover(event) {
        const path = typeof event.composedPath === 'function' ? event.composedPath() : [];
        return path.some((node) => {
            if (!node || !node.tagName) {
                return false;
            }
            const tag = node.tagName.toUpperCase();
            if (tag === 'C-ABT-SCALE-UP-CONFIG' && this._scaleUpPopoverLineId) {
                return true;
            }
            if (tag === 'C-ABT-REFLEX-VECTOR-OPT-IN' && this._reflexPopoverLineId) {
                return true;
            }
            if (tag === 'C-ABT-SCALE-UP-DEFINITIONS-MODAL' && this._scaleUpDefinitionsOpen) {
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
        this._sequences = this._sequences.map(seq =>
            String(seq.id) === String(id)
                ? { ...seq, reflexVectorOptIn: false }
                : seq
        );
        return updateQuoteRequestLineItemReflexVectorOptIn({
            lineItemId: id,
            reflexVectorOptIn: false
        }).then(result => {
            if (!result?.success) {
                this._sequences = this._sequences.map(seq =>
                    String(seq.id) === String(id) ? previous : seq
                );
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: result?.error || 'Failed to update reflex vector opt-in.',
                    variant: 'error'
                }));
            }
        }).catch(err => {
            this._sequences = this._sequences.map(seq =>
                String(seq.id) === String(id) ? previous : seq
            );
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'Failed to update reflex vector opt-in.',
                variant: 'error'
            }));
            console.error('Reflex vector opt-in clear failed:', err);
        });
    }

    _mapLineItem(row, existingSeq = null) {
        const qli = row.ABT_Quote_Line_Item__r || {};
        const feasibility = this._normalizeFeasibilityFromRow(row, qli);
        const complexity = this._normalizeComplexityFromRow(row);
        const pendingGlycerol = this._pendingGlycerolApplyIds?.has(String(row.Id)) === true;
        const existingWithGlycerolIntent = pendingGlycerol && row.Glycerol_Stock__c !== true
            ? { ...(existingSeq || {}), glycerol: true }
            : existingSeq;
        const pricingExtras = this._pricingExtrasFromLineItem(
            row,
            existingWithGlycerolIntent || {}
        );
        const mapped = {
            id: row.Id,
            name: this._sequenceNameFromRow(row) || 'N/A',
            productName: formatProductName(row.ABT_Product_Name__c) || this.productName || 'NA',
            quantity: row.ABT_Quantity__c ?? 1,
            vector: this._vectorIdFromRow(row, qli),
            sequence: this._sequenceTextFromRow(row),
            length: this._sequenceLengthFromRow(row),
            feasibility,
            potentiallyToxic: row.Potentially_Toxic__c === true,
            reflexVectorOptIn: row.Reflex_Vector_Opt_In__c === true,
            complexity,
            asEarlyAsDate: this._formatDate(row.As_Early_As_Date__c),
            guaranteedDate: this._formatDate(row.Expected_Ship_Date__c),
            tranche: trancheDisplay(row),
            scaleUp: row.Scale_Up__c || existingWithGlycerolIntent?.scaleUp || '',
            scaleUpFee: pricingExtras.scaleUpFee,
            scaleUpSelected: pricingExtras.scaleUpSelected === true,
            scaleUpQuantity: pricingExtras.scaleUpQuantity || '',
            scaleUpGlycerolStock: pricingExtras.scaleUpGlycerolStock === true,
            scaleUpBuffer: pricingExtras.scaleUpBuffer || '',
            scaleUpNormalization: pricingExtras.scaleUpNormalization || '',
            scaleUpEndotoxinFree: pricingExtras.scaleUpEndotoxinFree === true,
            scaleUpAnimalFree: pricingExtras.scaleUpAnimalFree === true,
            scaleUpMass: pricingExtras.scaleUpMass || '',
            scaleUpPriceDisplay: pricingExtras.scaleUpPriceDisplay || '',
            scaleUpLeadTime: pricingExtras.scaleUpLeadTime || '',
            glycerol: pricingExtras.glycerol,
            glycerolFee: pricingExtras.glycerolFee,
            glycerolPriceRaw: pricingExtras.glycerolPriceRaw,
            basePrice: pricingExtras.basePrice,
            combinedPrice: pricingExtras.combinedPrice,
            selected: existingWithGlycerolIntent?.selected === true,
            savedToSalesforce: true
        };

        return {
            ...mapped,
            additionalFees: pricingExtras.additionalFees,
            totalPrice: this._sequenceTotalPriceFromRow(row, mapped),
            endCustomerPrice: this._endCustomerPriceFromRow(row) ?? existingWithGlycerolIntent?.endCustomerPrice
        };
    }

    _formatDate(dateValue) {
        if (!dateValue) return 'Pending';
        if (/^\d{4}-\d{2}-\d{2}$/.test(dateValue)) {
            const [y, m, d] = dateValue.split('-');
            return `${m}/${d}/${y.slice(-2)}`;
        }
        if (typeof dateValue === 'string' && dateValue.includes('T')) {
            const datePart = dateValue.split('T')[0];
            if (/^\d{4}-\d{2}-\d{2}$/.test(datePart)) {
                const [y, m, d] = datePart.split('-');
                return `${m}/${d}/${y.slice(-2)}`;
            }
        }
        const d = new Date(dateValue);
        if (Number.isNaN(d.getTime())) return 'Pending';
        const mm = String(d.getMonth() + 1).padStart(2, '0');
        const dd = String(d.getDate()).padStart(2, '0');
        const yy = String(d.getFullYear()).slice(-2);
        return `${mm}/${dd}/${yy}`;
    }

    refreshData() {
        if (this._navigatingAway || !this.effectiveRecordId) {
            return;
        }
        if (this.wiredQuoteResult) refreshApex(this.wiredQuoteResult);
        if (this.wiredLineItemsResult) refreshApex(this.wiredLineItemsResult);
        if (this.wiredPdfRecordResult) refreshApex(this.wiredPdfRecordResult);
        this._refreshQuoteCartState();
    }

    _publishQuoteUpdate(updateType, details = {}) {
        if (!this.messageContext) {
            return;
        }
        publish(this.messageContext, QUOTE_UPDATE_CHANNEL, {
            updateType,
            quoteRequestId: this.effectiveRecordId,
            timestamp: new Date().toISOString(),
            details
        });
    }

    _applyCartRemoval(removed) {
        if (!removed) {
            return;
        }
        const wasInCartStage = (this.quoteStage || '').toLowerCase() === 'in cart';
        this.quoteInCart = false;
        if (wasInCartStage) {
            this._baseQuoteStage = 'Quoted';
        }
        this._applyQuoteStage();
        this._publishQuoteUpdate('cart_refresh', { priceUpdateRequired: true });
        if (this.wiredQuoteResult) {
            refreshApex(this.wiredQuoteResult);
        }
    }

    _applyCartRemovalFromResult(result) {
        this._applyCartRemoval(result?.removedFromCart === true);
    }

    _removeFromCartIfNeeded() {
        if (!this.quoteInCart && !this.isInCart) {
            return Promise.resolve(false);
        }
        return removeQuoteRequestFromCommerceCart({ quoteRequestId: this.effectiveRecordId })
            .then(() => {
                this._applyCartRemoval(true);
                return true;
            })
            .catch((err) => {
                console.error('Failed to remove quote from cart:', err);
                return false;
            });
    }

    get pdfLineItems() {
        return (this._sequences || []).map(seq => ({
            id: seq.id,
            sequenceName: seq.name,
            productName: formatProductName(seq.productName) || this.productName || 'NA',
            length: seq.length,
            quantity: seq.quantity ?? 1,
            formattedPrice: (seq.totalPrice || '$0.00').replace('$', '').replace(',', '')
        }));
    }

    get endUserPdfLineItems() {
        return (this._sequences || []).map(seq => ({
            id: seq.id,
            sequenceName: seq.name,
            productName: formatProductName(seq.productName) || this.productName || 'NA',
            length: seq.length,
            quantity: seq.quantity ?? 1,
            formattedEndCustomerPrice: seq.endCustomerPrice || '0.00'
        }));
    }

    // True when the user's account has "IDT Channel Partner" ticked
    // (Account.IDT_Channel_Partner__c). Set in _loadPageData.
    get isIDTChannelPartnership() {
        return this.accountIsIdtChannelPartner === true;
    }

    get quoteRequestCreatedDate() {
        return this.quoteRequestInfo.createdDate || 'NA';
    }

    get showPdfDiscount() {
        return !!this.quoteRequestInfo.formattedDiscount;
    }

    // ─── Tab navigation ─────────────────────────────────────────────────

    handleSequencesTab() { this.activeTab = 'sequences'; }
    handleDeliveryTab() { this.activeTab = 'delivery'; }

    get isSequencesTab() { return this.activeTab === 'sequences'; }
    get isDeliveryTab() { return this.activeTab === 'delivery'; }

    get sequencesTabClass() {
        return `quote-detail-tab${this.isSequencesTab ? ' quote-detail-tab_active' : ''}`;
    }

    get deliveryTabClass() {
        return `quote-detail-tab${this.isDeliveryTab ? ' quote-detail-tab_active' : ''}`;
    }

    // ─── Header / status ────────────────────────────────────────────────

    get normalizedStage() {
        return normalizeQuoteStage(this.quoteStage);
    }

    get isDraft() {
        return isDraftStage(this.quoteStage);
    }

    get isQuoted() {
        return isQuotedStage(this.quoteStage) && !this.isInCart;
    }

    get isInCart() {
        return isInCartStage(this._baseQuoteStage, this.quoteInCart);
    }

    get isInCartForDisplay() {
        return this.quoteInCart === true || this.isInCart;
    }

    get isViewOnly() {
        return isViewOnlyStage(this.quoteStage);
    }

    get isOrdered() {
        return normalizeQuoteStage(this.quoteStage).toLowerCase() === 'ordered';
    }

    get canDeleteQuote() {
        return !this.isOrdered;
    }

    get pageTitle() {
        const id = (this.quoteDisplayId || '').trim();
        return id ? `Quote ID ${id}` : 'Quote ID';
    }

    get showStatusBadge() {
        return !!this.normalizedStage;
    }

    get statusLabel() {
        const s = this.normalizedStage.toUpperCase();
        return s === 'DRAFT' ? 'DRAFTED' : s;
    }

    get statusBadgeClass() {
        const s = this.normalizedStage.toLowerCase();
        if (s === 'ordered') return 'status-pill status-pill_ordered';
        if (s === 'in cart') return 'status-pill status-pill_in-cart';
        if (s === 'quoted') return 'status-pill status-pill_quoted';
        if (s === 'canceled') return 'status-pill status-pill_canceled';
        return 'status-pill status-pill_draft';
    }

    /** Editable until ordered — draft, quoted, and in-cart quotes */
    get canEdit() {
        return !this.isViewOnly;
    }

    get isReadOnly() {
        return !this.canEdit;
    }

    get editModalTitle() {
        if (!this.canEdit) {
            return 'View Sequence';
        }
        return this.editingSequenceId ? 'Edit Sequence' : 'Add Sequence';
    }

    get showEditModalSave() {
        return this.canEdit;
    }

    get modalCloseLabel() {
        return this.canEdit ? 'Cancel' : 'Close';
    }

    get instructionText() {
        if (!this.canEdit) {
            return 'Click on a row to view the sequence.';
        }
        // Delivery Details has no empty draft row — keep the shorter copy from before inline drafts.
        if (this.isDeliveryTab) {
            return 'Click on a row to view or edit the sequence.';
        }
        return 'Enter data in the empty row to add a sequence. Click on a row to view or edit the sequence.';
    }

    // ─── Product flags ──────────────────────────────────────────────────

    get isFragment() {
        return (this.productName || '').toLowerCase().includes('fragment');
    }

    get isLibrary() {
        return (this.productName || '').toLowerCase().includes('library');
    }

    get isClonal() {
        const name = (this.productName || '').toLowerCase();
        return name.includes('clonal') && !name.includes('fragment');
    }

    get isAnsaClonalDNA() {
        return this.productSku === ANSA_CLONAL_DNA_SKU;
    }

    get isAnsaClonalXL() {
        return ANSA_CLONAL_XL_SKUS.has(this.productSku);
    }

    /** Standard Ansa Clonal DNA (SKU 1002) — not fragments or XL */
    get isVectorRequired() {
        return this.showVectorSelection && this.isAnsaClonalDNA && !this.isAnsaClonalXL;
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
        return this.isReadOnly || !this.isGlycerolApplicable;
    }

    /** Product flag controls vector UI on the portal */
    get showVectorSelection() {
        return this.isVectorProductEnabled;
    }

    get showScaleUpSelection() {
        return this.isScaleUpEnabled && this.isScaleUpProductEnabled && !this.isFragment;
    }

    get isScaleUpSelectionDisabled() {
        return this.isReadOnly;
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

    // ─── Table getters ──────────────────────────────────────────────────

    get hasSequences() {
        return this._sequences && this._sequences.length > 0;
    }

    get allSequencesSelected() {
        return this.hasSequences && this._sequences.every(s => s.selected);
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
        if (this.bulkVectorValue && this._isReflexApplicableVector(this.bulkVectorValue)) {
            return true;
        }
        return selected.every((seq) => this._isReflexApplicableVector(seq.vector));
    }

    get hasAnyReflexApplicableVector() {
        return (this._sequences || []).some((seq) => this._isReflexApplicableVector(seq.vector));
    }

    get showBulkSequenceActions() {
        return this.hasSelectedSequences && this.canEdit;
    }

    get showGlycerolBulkActions() {
        return this.hasSelectedSequences && this.canEdit && this.isGlycerolApplicable;
    }

    get isBulkUpdateInProgress() {
        return this._bulkUpdateCount > 0;
    }

    get isBulkToxicDisabled() {
        return this.isReadOnly || this.isBulkUpdateInProgress;
    }

    get isBulkReflexDisabled() {
        return this.isReadOnly || this.isBulkUpdateInProgress;
    }

    get isBulkVectorDisabled() {
        return this.isReadOnly || this.isBulkUpdateInProgress;
    }

    get isGlycerolBulkDisabled() {
        return this.isReadOnly || this.isGlycerolSelectionDisabled || this.isBulkUpdateInProgress;
    }

    get showAddSequenceButton() {
        return false;
    }

    get showDraftRows() {
        return this.canEdit;
    }

    get showEmptySequencesMessage() {
        return !this.hasSequences && !this.showDraftRows;
    }

    get headerBulkSlotClass() {
        return 'step4-packaging-column quote-detail-action-slot step4-bulk-action-slot';
    }

    get step3Colspan() {
        return this.showVectorSelection ? 8 : 7;
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

    get step3TableClass() {
        const base = 'step3-table';
        return this.showVectorSelection ? base : `${base} step3-table--no-vector`;
    }

    get step3TableWrapClass() {
        return this._reflexPopoverLineId
            ? 'step3-table-wrap step3-table-wrap--reflex-open'
            : 'step3-table-wrap';
    }

    get step4TableClass() {
        const base = 'step3-table step4-line-table';
        const modifiers = [];
        if (!this.showScaleUpSelection) {
            modifiers.push('step4-line-table--no-scaleup');
        }
        if (!this.showGlycerolSelection) {
            modifiers.push('step4-line-table--no-glycerol');
        }
        return modifiers.length ? `${base} ${modifiers.join(' ')}` : base;
    }

    get step4TableWrapClass() {
        return this._scaleUpPopoverLineId || this._scaleUpDefinitionsOpen
            ? 'step3-table-wrap step3-table-wrap--reflex-open'
            : 'step3-table-wrap';
    }

    get isUpdatingGlycerol() {
        return (this._glycerolUpdatingIds || []).length > 0;
    }

    get isCalculatingPricing() {
        if (!this.hasSequences) {
            return false;
        }
        return (this._sequences || []).some(s =>
            this._isFeasibilityPending(s) ||
            this._isComplexityPending(s)
        );
    }

    get isCalculationPending() {
        return this.isCalculatingPricing || this.isUpdatingGlycerol;
    }

    get calculationPendingLabel() {
        if (this.isUpdatingGlycerol && !this.isCalculatingPricing) {
            return 'Updating Glycerol Stock & fees';
        }
        return 'Calculating Sequence Classification & Pricing';
    }

    get showClassificationComplete() {
        return !this.isLoading && this.hasSequences && !this.isCalculationPending;
    }

    get showCalculationStatus() {
        return this.hasSequences && (this.isCalculationPending || this.showClassificationComplete);
    }

    get showFeasibilityGameLink() {
        if (!this.hasSequences) {
            return false;
        }
        return (this._sequences || []).some(s => this._isFeasibilityPending(s));
    }

    get progressBarStyle() {
        return `width: ${this.progressPercentage}%`;
    }

    get feasibilityStatusMessage() {
        if (this.progressPercentage >= 100) {
            return 'Feasibility calculation complete!';
        }
        return 'Calculating feasibility...';
    }

    get feasibilityStatusIcon() {
        return this.progressPercentage >= 100 ? 'utility:check' : 'utility:spinner';
    }

    get isFooterProcessing() {
        return this.isProcessing;
    }

    get sequencesWithDisplay() {
        const duplicateNameKeys = getDuplicateSequenceNameKeys(this._sequences);
        return (this._sequences || []).map(seq => {
            const sequence = seq.sequence || '';
            const validation = this._validateSequenceCharacters(sequence);
            const truncated = sequence.length > 40 ? sequence.substring(0, 40) + '...' : sequence;
            const feeSeq = this._sequenceForFeeDisplay(seq);
            const nameKey = normalizeSequenceNameForCompare(seq.name);
            const nameValidationError = getSequenceNameValidationError(seq.name, SEQUENCE_NAME_MAX_LENGTH);
            const isDuplicateName = !!nameKey && duplicateNameKeys.has(nameKey);
            const nameError = nameValidationError
                || (isDuplicateName ? DUPLICATE_SEQUENCE_NAME_ERROR : '');
            const vectorError = getSequenceVectorValidationError(seq.vector, this.isVectorRequired);
            return {
                ...feeSeq,
                additionalFees: this._formatAdditionalFeesDisplay(feeSeq),
                sequenceTruncated: truncated,
                hasInvalidChars: !validation.isValid,
                hasInvalidName: !!nameValidationError,
                nameError,
                nameTooltip: nameError || seq.name,
                hasDuplicateName: isDuplicateName,
                hasMissingVector: !!vectorError,
                vectorError,
                isGlycerolUpdating: this._isGlycerolUpdatingLine(seq.id),
                isDeleting: this._isDeletingSequence(seq.id),
                glycerolCheckboxDisabled: this.isGlycerolSelectionDisabled
                    || this._isGlycerolUpdatingLine(seq.id)
                    || seq.scaleUpSelected === true
                    || this._isScaleUpUpdatingLine(seq.id),
                scaleUpSelected: seq.scaleUpSelected === true,
                isScaleUpUpdating: this._isScaleUpUpdatingLine(seq.id),
                scaleUpPopoverOpen: String(this._scaleUpPopoverLineId) === String(seq.id),
                scaleUpSaving: this._isScaleUpSavingLine(seq.id),
                scaleUpCheckboxDisabled: this.isScaleUpSelectionDisabled
                    || this._isScaleUpUpdatingLine(seq.id)
                    || this._isScaleUpSavingLine(seq.id),
                scaleUpConfigured: seq.scaleUpSelected === true && !!seq.scaleUpQuantity,
                scaleUpCopyNumber: this._copyNumberForVector(seq.vector),
                totalSelectedCount: this.totalSelectedSequenceCount,
                totalLineCount: this.totalSequenceCount,
                showReflexOptIn: this._isReflexApplicableVector(seq.vector),
                reflexPopoverOpen: String(this._reflexPopoverLineId) === String(seq.id),
                reflexVectorOptIn: seq.reflexVectorOptIn === true,
                vectorCellClass: `step3-td step3-td-vector${String(this._reflexPopoverLineId) === String(seq.id) ? ' step3-td-vector--popover-open' : ''
                    }`,
                rowClass: 'step3-row'
            };
        });
    }

    _syncPackagingSelection() {
        if (!this.packagingOptions?.length) {
            return;
        }
        const candidate = this._packagingFromRecord || this.packagingType;
        this.packagingType = resolvePackagingPicklistValue(candidate, this.packagingOptions);
    }

    get packagingPlaceholder() {
        return PACKAGING_PLACEHOLDER;
    }

    get totalScaleUpFee() {
        const sum = (this._sequences || []).reduce((acc, seq) => {
            if (seq.scaleUpSelected !== true) {
                return acc;
            }
            const fee = parseFloat((seq.scaleUpFee || '0').replace('$', '').replace('NA', '0')) || 0;
            return acc + fee;
        }, 0);
        return `$${sum.toFixed(2)}`;
    }

    get totalGlycerolFee() {
        if (!this.showGlycerolSelection) {
            return '$0.00';
        }
        const sum = (this._sequences || []).reduce((acc, seq) => {
            const fee = parseFloat((this._effectiveGlycerolFee(seq) || '0').replace('$', '').replace('NA', '0')) || 0;
            return acc + fee;
        }, 0);
        return `$${sum.toFixed(2)}`;
    }

    get totalGlycerolFeeDisplay() {
        if (this.isUpdatingGlycerol) {
            return 'Updating...';
        }
        return this.totalGlycerolFee;
    }

    get grandTotal() {
        const sequences = this._sequences || [];
        if (sequences.length > 0) {
            const lineTotal = sequences.reduce((acc, seq) => {
                const price = parseFloat((seq.totalPrice || '$0').replace('$', '').replace(',', '')) || 0;
                return acc + price;
            }, 0);
            return `$${lineTotal.toFixed(2)}`;
        }
        const wireTotal = this.wiredQuoteResult?.data?.ABT_Total_Price__c;
        if (wireTotal != null && Number(wireTotal) > 0) {
            return `$${Number(wireTotal).toFixed(2)}`;
        }
        return '$0.00';
    }

    get showCartAction() {
        return this.isDraft || this.isQuoted || this.isInCart;
    }

    get showFooterActions() {
        return this.showCartAction || this.canDeleteQuote;
    }

    get isDeleteQuoteDisabled() {
        return this.isProcessing || this.isFooterProcessing;
    }

    get deleteQuoteLabel() {
        return this.isProcessing ? 'Processing...' : 'Delete Quote';
    }

    get cartActionLabel() {
        return this.isInCartForDisplay ? 'View in Cart' : 'Add to Cart';
    }

    get isCartActionDisabled() {
        if (this.isInCartForDisplay) {
            return this.isFooterProcessing;
        }
        if (!this.isDraft && !this.isQuoted) {
            return true;
        }
        if (this.isQuoted) {
            return this.isFooterProcessing || this.hasIncompleteScaleUpConfig;
        }
        return this.isFooterProcessing || !this.hasSequences || this.isCalculationPending
            || this.hasSequenceErrors || this.hasSequenceNameErrors || this.hasDuplicateSequenceNames
            || this.hasVectorErrors || this.hasIncompleteScaleUpConfig;
    }

    get cartActionLabelProcessing() {
        return this.isFooterProcessing ? 'Processing...' : this.cartActionLabel;
    }

    get isPdfDisabled() {
        return !this.hasSequences;
    }

    // ─── Validation ─────────────────────────────────────────────────────

    _validateSequenceCharacters(sequence) {
        return validateSequenceCharacters(sequence, this.allowedSequenceCharacters);
    }

    get hasSequenceErrors() {
        const sequenceInvalid = (sequence) => {
            if (!sequence) return false;
            return !this._validateSequenceCharacters(sequence).isValid
                || this._isLengthOutOfRange(sequence);
        };
        const fromSaved = (this._sequences || []).some(seq => sequenceInvalid(seq?.sequence));
        const fromDrafts = (this._draftRows || []).some(draft =>
            !!this._getDraftSequenceValidationError(draft)
        );
        return fromSaved || fromDrafts;
    }

    get hasSequenceNameErrors() {
        const peers = this._rowsForDraftNameValidation();
        const fromSaved = (this._sequences || []).some(seq =>
            !!getSequenceNameErrorForRow(seq?.name, peers, seq?.id)
        );
        const fromDrafts = (this._draftRows || []).some(draft =>
            !!this._getDraftNameValidationError(draft, peers)
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
        const fromSaved = (this._sequences || []).some(seq =>
            !!getSequenceVectorValidationError(seq?.vector, true)
        );
        const fromDrafts = (this._draftRows || []).some(draft =>
            this._shouldShowDraftValidation(draft)
            && !!getSequenceVectorValidationError(draft?.vector, true)
        );
        return fromSaved || fromDrafts;
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
            return qty == null || String(qty).trim() === '';
        });
    }

    get sequenceErrorBannerMessage() {
        const hasMissingSequence = (this._draftRows || []).some((draft) => {
            if (!this._shouldShowDraftValidation(draft)) {
                return false;
            }
            return !!(draft.name || '').trim() && !(draft.sequence || '').trim();
        });
        if (hasMissingSequence) {
            return 'Sequence is required. Please enter a sequence for each row.';
        }
        return `Sequence contains invalid characters or is outside product limits (${this.sequenceLengthLimits.min}-${this.sequenceLengthLimits.max} bp). Please click on the sequence to correct the issue.`;
    }

    get duplicateSequenceNameBannerMessage() {
        return DUPLICATE_SEQUENCE_NAME_ERROR;
    }

    get sequenceNameErrorBannerMessage() {
        const hasMissingName = (this._draftRows || []).some((draft) => {
            if (!this._shouldShowDraftValidation(draft)) {
                return false;
            }
            return !(draft.name || '').trim() && !!(draft.sequence || '').trim();
        });
        if (hasMissingName) {
            return 'Sequence name is required. Please enter a name for each sequence.';
        }
        return 'One or more sequence names contain invalid characters or exceed the length limit. Please click on the sequence to correct the name.';
    }



    get sequenceVectorErrorBannerMessage() {
        return getVectorRequiredBannerMessage(this.productName);
    }

    get sequenceNameMaxLength() {
        return SEQUENCE_NAME_MAX_LENGTH;
    }

    _isLengthOutOfRange(sequence) {
        const len = (sequence || '').length;
        const { min, max } = this.sequenceLengthLimits;
        return len > 0 && (len < min || len > max);
    }

    _validateEditSequenceName(name) {
        const trimmed = (name || '').trim();
        if (!trimmed) {
            this.editSequenceNameError = '';
            return;
        }
        const excludeId = this.isInsertingSequence ? null : this.editingSequenceId;
        this.editSequenceNameError = getSequenceNameErrorForRow(
            name,
            this._sequences,
            excludeId
        );
    }

    _validateEditSequenceVector(vector) {
        this.editSequenceVectorError = getSequenceVectorValidationError(vector, this.isVectorRequired);
    }

    _completeEditModalSave(lineItemId) {
        this.handleCloseEditModal(true);
        if (lineItemId) {
            this._pollLineItemPricing(lineItemId);
        }
        this.refreshData();
    }

    _warnEditModalFollowUpFailed(message) {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Warning',
            message,
            variant: 'warning'
        }));
    }

    _validateEditSequence(val) {
        const { min, max } = this.sequenceLengthLimits;
        if (val.length < min) {
            this.editSequenceError = `Sequence must be at least ${min} characters.`;
        } else if (val.length > max) {
            this.editSequenceError = `Sequence must not exceed ${max} characters.`;
        } else if (!this._validateSequenceCharacters(val).isValid) {
            this.editSequenceError = `Sequence must contain only ${getAllowedSequenceCharactersText(this.allowedSequenceCharacters)}.`;
        } else {
            this.editSequenceError = '';
        }
    }

    get isSaveDisabled() {
        return this.isModalSaveInProgress
            || !!this.editSequenceError
            || !!this.editSequenceNameError
            || !!this.editSequenceVectorError
            || (this.isVectorRequired && isSequenceVectorMissing(this.editSequenceVector))
            || this.editSequenceCharCount < this.sequenceLengthLimits.min
            || !(this.editSequenceName || '').trim();
    }

    get editTextareaClass() {
        return this.editSequenceError
            ? 'manual-sequence-textarea manual-sequence-textarea--error'
            : 'manual-sequence-textarea';
    }

    get sequencePlaceholder() {
        const { min, max } = this.sequenceLengthLimits;
        return `Enter your sequence here (min ${min}, max ${max} characters). Must contain only ${getAllowedSequenceCharactersText(this.allowedSequenceCharacters)}`;
    }

    // ─── Row interactions ───────────────────────────────────────────────

    _generateLocalId(prefix) {
        this._localIdCounter += 1;
        return `${prefix}_${Date.now()}_${this._localIdCounter}`;
    }

    get draftRowsWithDisplay() {
        const namePeers = this._rowsForDraftNameValidation();
        return (this._draftRows || []).map((draft) => {
            const sequence = draft.sequence || '';
            const showValidation = this._shouldShowDraftValidation(draft);
            const nameValidationError = this._getDraftNameValidationError(draft, namePeers);
            const sequenceValidationError = this._getDraftSequenceValidationError(draft);
            const vectorError = showValidation
                ? getSequenceVectorValidationError(draft.vector, this.isVectorRequired)
                : '';
            const hasInvalidChars = !!sequenceValidationError;
            const length = sequence.length || 0;
            return {
                ...draft,
                rowClass: draft.isSaving
                    ? 'step3-row step3-row--draft step3-row--draft-saving'
                    : 'step3-row step3-row--draft',
                lengthDisplay: length > 0 ? String(length) : '',
                hasInvalidName: !!nameValidationError,
                nameTooltip: nameValidationError || '',
                hasInvalidChars,
                sequenceTooltip: sequenceValidationError || '',
                hasMissingVector: !!vectorError,
                nameInputClass: nameValidationError
                    ? 'step3-draft-input step3-draft-input--error'
                    : 'step3-draft-input',
                sequenceInputClass: hasInvalidChars
                    ? 'step3-draft-input step3-draft-input--seq step3-draft-input--error'
                    : 'step3-draft-input step3-draft-input--seq'
            };
        });
    }

    _createEmptyDraftRow() {
        return {
            id: this._generateLocalId('draft'),
            name: '',
            sequence: '',
            vector: this._effectiveVectorForNewRows(),
            potentiallyToxic: false,
            isSaving: false,
            showValidation: false
        };
    }

    _isDraftRowEmpty(draft) {
        return !(draft?.name || '').trim() && !(draft?.sequence || '').trim();
    }

    /** True once debounce elapsed or blur — surface inline/banner validation for this draft. */
    _shouldShowDraftValidation(draft) {
        return draft?.showValidation === true && !this._isDraftRowEmpty(draft);
    }

    _getDraftNameValidationError(draft, namePeers) {
        if (!this._shouldShowDraftValidation(draft)) {
            return '';
        }
        const name = (draft?.name || '').trim();
        if (!name) {
            return (draft?.sequence || '').trim() ? 'Sequence name is required' : '';
        }
        return getSequenceNameErrorForRow(draft.name, namePeers || this._rowsForDraftNameValidation(), draft.id) || '';
    }

    _getDraftSequenceValidationError(draft) {
        if (!this._shouldShowDraftValidation(draft)) {
            return '';
        }
        const sequence = draft?.sequence || '';
        if (!sequence.trim()) {
            return (draft?.name || '').trim() ? 'Sequence is required' : '';
        }
        const validation = this._validateSequenceCharacters(sequence);
        if (!validation.isValid) {
            return validation.message || 'Invalid sequence characters.';
        }
        if (this._isLengthOutOfRange(sequence)) {
            return `Sequence length must be between ${this.sequenceLengthLimits.min} and ${this.sequenceLengthLimits.max} bp.`;
        }
        return '';
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

    /** Hide errors while typing; show after idle delay. */
    _scheduleDraftValidation(draftId) {
        if (!draftId) {
            return;
        }
        this._clearDraftValidationTimer(draftId);
        this._updateDraftRow(draftId, { showValidation: false });
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        const timer = setTimeout(() => {
            this._draftValidationTimers.delete(String(draftId));
            const draft = (this._draftRows || []).find((d) => String(d.id) === String(draftId));
            if (!draft || this._isDraftRowEmpty(draft)) {
                this._updateDraftRow(draftId, { showValidation: false });
                return;
            }
            this._updateDraftRow(draftId, { showValidation: true });
        }, this.constructor.DRAFT_VALIDATION_DELAY_MS);
        this._draftValidationTimers.set(String(draftId), timer);
    }

    /** Show validation immediately (blur / vector change). */
    _enableDraftValidationNow(draftId) {
        if (!draftId) {
            return;
        }
        this._clearDraftValidationTimer(draftId);
        const draft = (this._draftRows || []).find((d) => String(d.id) === String(draftId));
        this._updateDraftRow(draftId, {
            showValidation: !!(draft && !this._isDraftRowEmpty(draft))
        });
    }

    _rowsForDraftNameValidation(excludeDraftId) {
        const sequences = this._sequences || [];
        const drafts = (this._draftRows || [])
            .filter((d) => excludeDraftId == null || String(d.id) !== String(excludeDraftId))
            .map((d) => ({ id: d.id, name: d.name }));
        return [...sequences, ...drafts];
    }

    _isDraftRowValidForSave(draft) {
        if (!draft || this._isDraftRowEmpty(draft)) {
            return false;
        }
        if (!(draft.name || '').trim()) {
            return false;
        }
        if (!(draft.sequence || '').trim()) {
            return false;
        }
        const sequenceOk = this._validateSequenceCharacters(draft.sequence || '').isValid
            && !this._isLengthOutOfRange(draft.sequence || '');
        return sequenceOk
            && !getSequenceNameErrorForRow(
                draft.name,
                this._rowsForDraftNameValidation(draft.id),
                draft.id
            )
            && !getSequenceVectorValidationError(draft?.vector, this.isVectorRequired);
    }

    _ensureTrailingEmptyDraftRow() {
        if (!this.canEdit) {
            this._draftRows = [];
            return;
        }
        // Keep any filled draft rows and ensure exactly one empty trailing row.
        // Do NOT overwrite an existing empty draft's vector — that resets dropdown changes.
        const rows = this._draftRows || [];
        const nonEmpty = rows.filter((r) => !this._isDraftRowEmpty(r) || r.isSaving);
        const trailingEmpty = rows.find((r) => this._isDraftRowEmpty(r) && !r.isSaving);

        if (nonEmpty.length === 0 && !trailingEmpty) {
            this._draftRows = [this._createEmptyDraftRow()];
            return;
        }
        if (!trailingEmpty) {
            this._draftRows = [...nonEmpty, this._createEmptyDraftRow()];
            return;
        }
        const normalized = [...nonEmpty, trailingEmpty];
        const unchanged = normalized.length === rows.length
            && normalized.every((row, index) => String(row.id) === String(rows[index].id));
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
        if (!this.canEdit) return;
        const id = event.currentTarget.dataset.id;
        this._updateDraftRow(id, { name: event.target.value });
        this._scheduleDraftValidation(id);
    }

    handleDraftSequenceInput(event) {
        event.stopPropagation();
        if (!this.canEdit) return;
        const id = event.currentTarget.dataset.id;
        this._updateDraftRow(id, { sequence: event.target.value });
        this._scheduleDraftValidation(id);
    }

    handleDraftVectorChange(event) {
        event.stopPropagation();
        if (!this.canEdit) return;
        const id = event.currentTarget.dataset.id;
        const val = event.detail?.value;
        if (!id) {
            return;
        }
        const normalized = (!val || val === 'none') ? '' : val;
        this._setWorkingVectorDefault(normalized);
        this._updateDraftRow(id, { vector: normalized });
        this._enableDraftValidationNow(id);
        this._tryCommitDraftRow(id);
    }

    handleDraftToxicChange(event) {
        event.stopPropagation();
        if (!this.canEdit) return;
        const id = event.currentTarget.dataset.id;
        if (!id) {
            return;
        }
        this._updateDraftRow(id, { potentiallyToxic: event.target.checked === true });
    }

    handleDraftBlur(event) {
        event.stopPropagation();
        if (!this.canEdit) return;
        const id = event.currentTarget.dataset.id;
        if (!id) {
            return;
        }
        this._enableDraftValidationNow(id);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => this._tryCommitDraftRow(id), 0);
    }

    _parseSpreadsheetPaste(text) {
        const raw = (text || '').replace(/\r\n/g, '\n').replace(/\r/g, '\n');
        const lines = raw.split('\n').map((line) => line.trim()).filter(Boolean);
        if (!lines.length) {
            return null;
        }
        const parseLine = (line) => {
            if (line.includes('\t')) {
                const parts = line.split('\t');
                return {
                    name: (parts[0] || '').trim(),
                    sequence: parts.slice(1).join('\t').replace(/\s+/g, '').trim()
                };
            }
            if (line.includes(',')) {
                const parts = line.split(',');
                const maybeSeq = parts[parts.length - 1].replace(/\s/g, '');
                if (parts.length >= 2 && /^[ACGTRYSWKMBDHVN]+$/i.test(maybeSeq)) {
                    return {
                        name: parts.slice(0, -1).join(',').trim(),
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
                        name: spaced.slice(0, -1).join(' ').trim(),
                        sequence: maybeSeq
                    };
                }
            }
            return { name: '', sequence: line.replace(/\s/g, '') };
        };
        const looksLikeSpreadsheet = lines.some((line) =>
            line.includes('\t')
            || line.includes(',')
            || /\s+[ACGTRYSWKMBDHVN]{8,}\s*$/i.test(line)
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
        if (!this.canEdit) return;
        const clipboard = event.clipboardData;
        const text = clipboard?.getData('text/plain') || clipboard?.getData('text') || '';
        const parsed = this._parseSpreadsheetPaste(text);
        if (!parsed || !parsed.length) {
            return;
        }
        event.preventDefault();
        event.stopPropagation();
        const startId = event.currentTarget.dataset.id;
        const draft = (this._draftRows || []).find((d) => String(d.id) === String(startId));
        if (!draft) {
            return;
        }

        const vectorForRows = draft.vector
            || this._effectiveVectorForNewRows();

        // Paste fills drafts, then immediately creates valid rows in Salesforce
        // (Feasibility via _pollLineItemPricing). Invalid rows stay as drafts with errors.
        const otherDrafts = (this._draftRows || []).filter((row) =>
            String(row.id) !== String(startId)
            && (!this._isDraftRowEmpty(row) || row.isSaving)
        );
        const pastedDrafts = parsed
            .map((item) => {
                const name = (item.name || '').trim();
                const sequence = (item.sequence || '').replace(/\s/g, '');
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

        const validPasted = pastedDrafts.filter((row) => this._isDraftRowValidForSave(row));
        if (validPasted.length) {
            this._commitValidDraftRows(validPasted);
        }
    }

    /**
     * Batch-create valid draft rows so multi-paste polls Feasibility for every inserted line.
     */
    _commitValidDraftRows(drafts) {
        if (!this.canEdit) {
            return Promise.resolve();
        }
        const rows = (drafts || []).filter((d) => d && this._isDraftRowValidForSave(d) && !d.isSaving);
        if (!rows.length) {
            return Promise.resolve();
        }
        if (!this.effectiveRecordId) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'Unable to save sequence. Quote request is not ready.',
                variant: 'error'
            }));
            return Promise.resolve();
        }

        const draftIds = rows.map((d) => String(d.id));
        this._draftRows = (this._draftRows || []).map((row) =>
            draftIds.includes(String(row.id)) ? { ...row, isSaving: true } : row
        );

        const sequenceNames = rows.map((d) => (d.name || '').trim());
        const sequences = rows.map((d) => d.sequence || '');
        const vectorIds = rows.map((d) => this._vectorIdForApex(d.vector));
        const potentiallyToxicFlags = rows.map((d) => d.potentiallyToxic === true);
        const glycerolStockFlags = rows.map(() => false);
        const reflexVectorOptInFlags = rows.map(() => false);

        const run = () => createQuoteRequestLineItemsChunked(createQuoteRequestLineItemsDeferredKick, {
            quoteRequestId: this.effectiveRecordId,
            sequenceNames,
            sequences,
            vectorIds,
            potentiallyToxicFlags,
            glycerolStockFlags,
            reflexVectorOptInFlags,
            afterAll: () => enqueuePendingForQuoteRequest({
                quoteRequestId: this.effectiveRecordId
            })
        })
            .then((results) => {
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
                    insertedIds.push(inserted.Id);
                    this._queueDefaultGlycerolApply(inserted.Id);
                });
                if (successDraftIds.size) {
                    this._draftRows = (this._draftRows || []).filter(
                        (d) => !successDraftIds.has(String(d.id))
                    );
                    this._ensureTrailingEmptyDraftRow();
                    this._applyPendingGlycerolIfReady();
                    this._applyCartRemoval(this.isInCart || this.quoteInCart);
                    insertedIds.forEach((lineItemId) => this._pollLineItemPricing(lineItemId));
                    this.refreshData();
                }
                if (successDraftIds.size < rows.length) {
                    this.dispatchEvent(new ShowToastEvent({
                        title: 'Error',
                        message: 'Unable to save one or more sequences.',
                        variant: 'error'
                    }));
                }
            })
            .catch((err) => {
                console.error('Error creating sequences from draft rows:', err);
                rows.forEach((draft) => this._updateDraftRow(draft.id, { isSaving: false }));
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: 'Unable to save sequence.',
                    variant: 'error'
                }));
            });

        this._draftCommitTail = this._draftCommitTail.then(run, run);
        return this._draftCommitTail;
    }

    _tryCommitDraftRow(draftId) {
        if (!this.canEdit) {
            return;
        }
        const draft = (this._draftRows || []).find((d) => String(d.id) === String(draftId));
        if (!draft || draft.isSaving || this._isDraftRowEmpty(draft)) {
            return;
        }
        if (!this._isDraftRowValidForSave(draft)) {
            return;
        }
        this._commitValidDraftRows([draft]);
    }

    renderedCallback() {
        if (this.canEdit && this.isSequencesTab) {
            this._ensureTrailingEmptyDraftRow();
        }
    }

    stopProp(event) { event.stopPropagation(); }

    handleSelectAll(event) {
        event.stopPropagation();
        const checked = event.target.checked;
        this._sequences = this._sequences.map(s => ({ ...s, selected: checked }));
        this._syncBulkControlsAfterSelectionChange();
    }

    handleCheckboxClick(event) {
        event.stopPropagation();
        const id = event.target.dataset.id;
        const checked = event.target.checked;
        this._sequences = this._sequences.map(s =>
            String(s.id) === String(id) ? { ...s, selected: checked } : s
        );
        this._syncBulkControlsAfterSelectionChange();
    }

    _syncBulkControlsAfterSelectionChange() {
        if (!this.hasSelectedSequences) {
            this.bulkToxicChecked = false;
            this.bulkReflexChecked = false;
            this.bulkGlycerolChecked = false;
            this.bulkVectorValue = '';
        }
    }

    _getSelectedSequencesOrWarn() {
        const selected = this.selectedSequences;
        if (!selected.length) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Selection required',
                message: 'Please select at least one sequence.',
                variant: 'warning'
            }));
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
        if (this.isBulkUpdateInProgress) {
            return;
        }
        if (!this.canEdit || !this.showVectorBulkSelection) {
            return;
        }
        event.stopPropagation();
        const val = event.detail?.value ?? event.target.value;
        if (!val) {
            return;
        }

        const selected = this._getSelectedSequencesOrWarn();
        if (!selected) {
            this.bulkVectorValue = '';
            return;
        }

        const selectedIds = new Set(selected.map((seq) => String(seq.id)));
        const snapshots = new Map(selected.map((seq) => [String(seq.id), { ...seq }]));
        const nextIsReflexApplicable = this._isReflexApplicableVector(val);
        const vectorId = this._vectorIdForApex(val);
        const savedIds = selected.filter((seq) => seq.savedToSalesforce).map((seq) => seq.id);

        this.bulkVectorValue = val;
        this.bulkReflexChecked = false;

        this._sequences = this._sequences.map((seq) => {
            if (!selectedIds.has(String(seq.id))) {
                return seq;
            }
            return {
                ...seq,
                vector: val,
                ...(nextIsReflexApplicable ? {} : { reflexVectorOptIn: false }),
                feasibility: 'Pending',
                complexity: 'Pending'
            };
        });

        selected.forEach((seq) => {
            if (!nextIsReflexApplicable && seq.reflexVectorOptIn) {
                this._clearReflexOptInForSequence(seq.id, seq);
            }
        });

        this._applyFeasibilityGameState();

        if (!savedIds.length) {
            return;
        }

        this._beginBulkUpdate();
        bulkUpdateQuoteLineItemVectors({
            lineItemIds: savedIds,
            vectorId
        })
            .then((result) => {
                if (result?.success) {
                    this._applyCartRemovalFromResult(result);
                    savedIds.forEach((id) => this._pollLineItemPricing(id));
                    return;
                }
                this._sequences = this._sequences.map((seq) => {
                    const snapshot = snapshots.get(String(seq.id));
                    return snapshot || seq;
                });
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: result?.error || 'Failed to update vector.',
                    variant: 'error'
                }));
            })
            .catch((err) => {
                this._sequences = this._sequences.map((seq) => {
                    const snapshot = snapshots.get(String(seq.id));
                    return snapshot || seq;
                });
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: 'Failed to update vector.',
                    variant: 'error'
                }));
                console.error('Bulk vector update failed:', err);
            })
            .finally(() => {
                this._endBulkUpdate();
            });
    }

    handleBulkReflexChange(event) {
        if (this.isBulkUpdateInProgress) {
            return;
        }
        if (!this.canEdit) {
            return;
        }
        event.stopPropagation();
        const reflexVectorOptIn = event.target.checked === true;
        this.bulkReflexChecked = reflexVectorOptIn;
        const selected = this._getSelectedSequencesOrWarn();
        if (!selected) {
            this.bulkReflexChecked = false;
            return;
        }

        const applicable = selected.filter((seq) => this._isReflexApplicableVector(seq.vector));
        if (!applicable.length) {
            this.bulkReflexChecked = false;
            this.dispatchEvent(new ShowToastEvent({
                title: 'Reflex unavailable',
                message: 'Reflex is only available for sequences with a reflex-applicable vector.',
                variant: 'warning'
            }));
            return;
        }

        const applicableIds = new Set(applicable.map((seq) => String(seq.id)));
        const snapshots = new Map(applicable.map((seq) => [String(seq.id), { ...seq }]));
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
                    throw new Error(result?.error || 'Failed to save reflex vector opt-in.');
                }
                this._applyCartRemovalFromResult(result);
                const byId = new Map(
                    (result.lines || []).map((line) => [String(line.id), line.reflexVectorOptIn === true])
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
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: 'Failed to save reflex vector opt-in.',
                    variant: 'error'
                }));
                console.error('Bulk reflex update failed:', err);
            })
            .finally(() => {
                this._endBulkUpdate();
            });
    }

    handleBulkToxicChange(event) {
        if (this.isBulkUpdateInProgress) {
            return;
        }
        if (!this.canEdit) {
            return;
        }
        event.stopPropagation();
        const potentiallyToxic = event.target.checked === true;
        this.bulkToxicChecked = potentiallyToxic;
        const selected = this._getSelectedSequencesOrWarn();
        if (!selected) {
            this.bulkToxicChecked = false;
            return;
        }

        const selectedIds = new Set(selected.map((seq) => String(seq.id)));
        const snapshots = new Map(selected.map((seq) => [String(seq.id), { ...seq }]));
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
                    throw new Error(result?.error || 'Potentially Toxic update failed');
                }
                this._applyCartRemovalFromResult(result);
                const byId = new Map(
                    (result.lines || []).map((line) => [String(line.id), line.potentiallyToxic === true])
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
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: 'Failed to update Potentially Toxic. Please try again.',
                    variant: 'error'
                }));
                console.error('Bulk toxic update failed:', err);
            })
            .finally(() => {
                this._endBulkUpdate();
            });
    }

    handleBulkGlycerolChange(event) {
        if (this.isBulkUpdateInProgress) {
            return;
        }
        if (!this.canEdit || !this.isGlycerolApplicable || this.isGlycerolSelectionDisabled) {
            this.bulkGlycerolChecked = false;
            return;
        }
        event.stopPropagation();
        const glycerol = event.target.checked === true;
        this.bulkGlycerolChecked = glycerol;
        const selected = this._getSelectedSequencesOrWarn();
        if (!selected) {
            this.bulkGlycerolChecked = false;
            return;
        }

        const selectedIds = new Set(selected.map((seq) => String(seq.id)));
        const snapshots = new Map(selected.map((seq) => [String(seq.id), { ...seq }]));
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
                    throw new Error(result?.error || 'Glycerol update failed');
                }
                this._applyCartRemovalFromResult(result);
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
                savedSelected.forEach((seq) => {
                    this._publishQuoteUpdate('pricing_refresh', {
                        lineItemId: seq.id,
                        glycerolStock: glycerol,
                        priceUpdateRequired: true
                    });
                });
                return Promise.all(
                    savedSelected.map((seq) => this._pollLineItemPricingUntilGlycerolSettled(seq.id))
                );
            })
            .catch((err) => {
                this.bulkGlycerolChecked = !glycerol;
                this._sequences = this._sequences.map((seq) => {
                    const snapshot = snapshots.get(String(seq.id));
                    return snapshot || seq;
                });
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: 'Failed to update Glycerol. Please try again.',
                    variant: 'error'
                }));
                console.error('Bulk glycerol update failed:', err);
            })
            .finally(() => {
                savedSelected.forEach((seq) => this._removeGlycerolUpdating(seq.id));
                this._endBulkUpdate();
            });
    }

    handleRowClick(event) {
        const id = event.currentTarget.dataset.id;
        const seq = this._sequences.find(s => String(s.id) === String(id));
        if (!seq) return;
        this.isInsertingSequence = false;
        this.editingSequenceId = id;
        this.editSequenceName = seq.name || '';
        this.editSequenceVector = this.showVectorSelection ? seq.vector || '' : '';
        this.editSequenceText = seq.sequence || '';
        this.editSequenceCharCount = (seq.sequence || '').length;
        this.editSequenceError = '';
        this.editSequenceNameError = '';
        this.editSequenceVectorError = '';
        if (this.canEdit) {
            this._validateEditSequence(this.editSequenceText);
            this._validateEditSequenceName(this.editSequenceName);
            this._validateEditSequenceVector(this.editSequenceVector);
        }
        this._editOriginalSnapshot = this._snapshotFromEditFields();
        this.showEditModal = true;
    }

    handleAddSequence() {
        if (!this.canEdit) return;
        this._editOriginalSnapshot = null;
        this.isInsertingSequence = true;
        this.editingSequenceId = null;
        this.editSequenceName = '';
        this.editSequenceVector = this._effectiveVectorForNewRows();
        this.editSequenceText = '';
        this.editSequenceCharCount = 0;
        this.editSequenceError = '';
        this.editSequenceNameError = '';
        this.editSequenceVectorError = '';
        this.showEditModal = true;
    }

    handleRowVectorChange(event) {
        if (!this.canEdit) return;
        event.stopPropagation();
        const id = event.currentTarget.dataset.id;
        const val = event.detail?.value;
        if (!id || !val) return;

        const previous = (this._sequences || []).find(s => String(s.id) === String(id));
        if (!previous) return;

        if (val !== 'none') {
            this._setWorkingVectorDefault(val);
        }

        const nextIsReflexApplicable = this._isReflexApplicableVector(val);
        this._sequences = this._sequences.map(s =>
            String(s.id) === String(id)
                ? {
                    ...s,
                    vector: val,
                    ...(nextIsReflexApplicable ? {} : { reflexVectorOptIn: false }),
                    feasibility: 'Pending',
                    complexity: 'Pending'
                }
                : s
        );

        if (!nextIsReflexApplicable && previous.reflexVectorOptIn) {
            this._clearReflexOptInForSequence(id, previous);
        }

        if (nextIsReflexApplicable) {
            this._openReflexPopoverForLine(id);
        } else if (String(this._reflexPopoverLineId) === String(id)) {
            this._reflexPopoverLineId = null;
        }

        this._applyFeasibilityGameState();

        updateQuoteLineItemVector({
            lineItemId: id,
            vectorId: this._vectorIdForApex(val)
        })
            .then(result => {
                if (result?.success) {
                    this._applyCartRemovalFromResult(result);
                    this._pollLineItemPricing(id);
                    return;
                }
                this._sequences = this._sequences.map(s =>
                    String(s.id) === String(id) ? previous : s
                );
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: result?.error || 'Failed to update vector.',
                    variant: 'error'
                }));
            })
            .catch(err => {
                this._sequences = this._sequences.map(s =>
                    String(s.id) === String(id) ? previous : s
                );
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: 'Failed to update vector.',
                    variant: 'error'
                }));
                console.error('Vector update failed:', err);
            });
    }

    handleReflexToggle(event) {
        if (!this.canEdit) return;
        event.stopPropagation();
        const id = event.currentTarget.dataset.id;
        if (!id) {
            return;
        }
        this._reflexPopoverLineId = String(this._reflexPopoverLineId) === String(id) ? null : id;
    }

    handleReflexSave(event) {
        if (!this.canEdit) return;
        event.stopPropagation();
        const id = event.currentTarget.dataset.id;
        const reflexVectorOptIn = event.detail?.reflexVectorOptIn === true;
        if (!id) {
            return;
        }

        const previous = (this._sequences || []).find(seq => String(seq.id) === String(id));
        if (!previous) {
            return;
        }

        this._sequences = this._sequences.map(seq =>
            String(seq.id) === String(id) ? { ...seq, reflexVectorOptIn } : seq
        );
        this._reflexPopoverLineId = null;

        updateQuoteRequestLineItemReflexVectorOptIn({
            lineItemId: id,
            reflexVectorOptIn
        }).then(result => {
            if (result?.success) {
                this._applyCartRemovalFromResult(result);
                this._sequences = this._sequences.map(seq =>
                    String(seq.id) === String(id)
                        ? { ...seq, reflexVectorOptIn: result.reflexVectorOptIn === true }
                        : seq
                );
                return;
            }
            this._sequences = this._sequences.map(seq =>
                String(seq.id) === String(id) ? previous : seq
            );
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: result?.error || 'Failed to save reflex vector opt-in.',
                variant: 'error'
            }));
        }).catch(err => {
            this._sequences = this._sequences.map(seq =>
                String(seq.id) === String(id) ? previous : seq
            );
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'Failed to save reflex vector opt-in.',
                variant: 'error'
            }));
            console.error('Reflex vector opt-in save failed:', err);
        });
    }

    handleToxicChange(event) {
        if (!this.canEdit) return;
        const id = event.target.dataset.id;
        const checked = event.target.checked;
        const previous = (this._sequences || []).find(s => String(s.id) === String(id));
        this._sequences = this._sequences.map(s =>
            String(s.id) === String(id) ? { ...s, potentiallyToxic: checked } : s
        );
        if (!previous?.savedToSalesforce) {
            return;
        }
        updateQuoteRequestLineItemPotentiallyToxic({
            lineItemId: id,
            potentiallyToxic: checked
        }).then(result => {
            if (!result?.success) {
                throw new Error(result?.error || 'Potentially Toxic update failed');
            }
            this._applyCartRemovalFromResult(result);
            this._sequences = this._sequences.map(s =>
                String(s.id) === String(id)
                    ? { ...s, potentiallyToxic: result.potentiallyToxic === true }
                    : s
            );
        }).catch(err => {
            this._sequences = this._sequences.map(s =>
                String(s.id) === String(id)
                    ? { ...s, potentiallyToxic: previous.potentiallyToxic }
                    : s
            );
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'Failed to update Potentially Toxic. Please try again.',
                variant: 'error'
            }));
            console.error('Potentially Toxic update failed:', err);
        });
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
        if (!this.canEdit) return;
        event.stopPropagation();
        const id = event.target.dataset.id;
        const checked = event.target.checked === true;
        const previous = (this._sequences || []).find((s) => String(s.id) === String(id));
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
                    ...(checked ? { scaleUpSelected: true } : this._clearedScaleUpUiFields()),
                    glycerol: checked ? false : s.glycerol,
                    glycerolFee: checked
                        ? null
                        : (s.glycerol === true ? s.glycerolFee : null),
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
            this._openScaleUpPopoverForLine(id);
            if (previous.glycerol === true) {
                updateQuoteRequestLineItemGlycerol({
                    lineItemId: id,
                    glycerolStock: false
                }).catch((err) => {
                    console.error('Failed to clear Glycerol Stock for Scale Up:', err);
                });
            }
            return;
        }

        // Clearing the checkbox removes the configuration and re-enables Glycerol Stock.
        this._scaleUpPopoverLineId = null;
        this._persistScaleUp([id], {
            selected: false,
            quantity: '',
            glycerolStock: false,
            buffer: '',
            normalization: null,
            endotoxinFree: false,
            animalFree: false
        }, this._snapshotSequencesById([id]));
    }

    handleScaleUpToggle(event) {
        if (!this.canEdit) return;
        event.stopPropagation();
        const id = event.currentTarget.dataset.id;
        if (!id) {
            return;
        }
        this._scaleUpPopoverLineId =
            String(this._scaleUpPopoverLineId) === String(id) ? null : id;
    }

    handleScaleUpCancel(event) {
        if (!this.canEdit) return;
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
        if (!this.canEdit) return;
        event.stopPropagation();
        const id = event.currentTarget.dataset.id;
        const detail = event.detail || {};
        if (!id) {
            return;
        }

        const targetIds = this._scaleUpTargetIds(id, detail.applyToSelected === true);
        // Keep the Scale Up popover open after Apply (Cancel / outside click closes it).
        this._persistScaleUp(targetIds, {
            selected: true,
            quantity: detail.quantity || '',
            glycerolStock: detail.glycerolStock === true,
            buffer: detail.buffer || this._scaleUpBufferDefault || SCALE_UP_DEFAULT_BUFFER,
            normalization: toScaleUpNormalizationApiValue(detail.normalization),
            endotoxinFree: detail.endotoxinFree === true,
            animalFree: detail.animalFree === true
        }, this._snapshotSequencesById(targetIds));
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
                scaleUpQuantity: settings.quantity || '',
                scaleUpGlycerolStock: settings.glycerolStock === true,
                scaleUpBuffer: settings.buffer || this._scaleUpBufferDefault || SCALE_UP_DEFAULT_BUFFER,
                scaleUpNormalization: fromScaleUpNormalizationApiValue(settings.normalization),
                scaleUpEndotoxinFree: settings.endotoxinFree === true,
                scaleUpAnimalFree: settings.animalFree === true,
                glycerol: false
            };
        });

        return updateQuoteRequestLineItemScaleUp({
            lineItemIds: idList,
            selected,
            quantity: selected ? (settings.quantity || null) : null,
            glycerolStock: settings.glycerolStock === true,
            buffer: selected ? (settings.buffer || this._scaleUpBufferDefault || SCALE_UP_DEFAULT_BUFFER) : null,
            endotoxinFree: settings.endotoxinFree === true,
            animalFree: settings.animalFree === true,
            normalization: selected ? toScaleUpNormalizationApiValue(settings.normalization) : null
        }).then((result) => {
            if (!result?.success) {
                throw new Error(result?.error || 'Scale Up update failed');
            }
            this._applyCartRemovalFromResult(result);
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
                        glycerolFee: l.glycerolStock === true
                            ? (this._formatGlycerolFee(l.glycerolPrice) || s.glycerolFee)
                            : null,
                        glycerolPriceRaw: l.glycerolPrice
                    };
                    return this._withAdditionalFees({
                        ...cleared,
                        totalPrice: this._recalculateSequenceTotal(cleared)
                    });
                }
                const priceDisplay = this._formatCurrencyFee(l.scaleUpPrice) || '';
                const scaleUpGlycerol = l.scaleUpGlycerolStock === true;
                const glycFee = (scaleUpGlycerol || l.glycerolStock === true)
                    ? this._formatGlycerolFee(l.glycerolPrice)
                    : null;
                const next = {
                    ...s,
                    scaleUpSelected: true,
                    scaleUpQuantity: l.scaleUpQuantity != null ? String(l.scaleUpQuantity) : '',
                    scaleUpGlycerolStock: scaleUpGlycerol,
                    scaleUpBuffer: l.scaleUpBuffer || '',
                    scaleUpNormalization: fromScaleUpNormalizationApiValue(l.scaleUpNormalization),
                    scaleUpEndotoxinFree: l.scaleUpEndotoxinFree === true,
                    scaleUpAnimalFree: l.scaleUpAnimalFree === true,
                    scaleUpMass: l.scaleUpMass || '',
                    scaleUpPriceDisplay: priceDisplay,
                    scaleUpLeadTime: l.scaleUpLeadTime || '',
                    scaleUpFee: priceDisplay || null,
                    glycerol: false,
                    glycerolFee: glycFee,
                    glycerolPriceRaw: l.glycerolPrice
                };
                return this._withAdditionalFees({
                    ...next,
                    totalPrice: this._recalculateSequenceTotal(next)
                });
            });
        }).catch((err) => {
            if (previousById) {
                this._sequences = this._sequences.map(
                    (s) => previousById[String(s.id)] || s
                );
            }
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'Failed to update Scale Up. Please try again.',
                variant: 'error'
            }));
            console.error('Scale Up update failed:', err);
        }).finally(() => {
            if (!selected) {
                idList.forEach((id) => this._scaleUpClearInFlightIds.delete(id));
                idList.forEach((id) => this._removeScaleUpUpdating(id));
            } else {
                idList.forEach((id) => this._removeScaleUpSaving(id));
            }
        });
    }

    handleGlycerolRowChange(event) {
        if (!this.canEdit || !this.isGlycerolApplicable) return;
        const id = event.target.dataset.id;
        const checked = event.target.checked;
        const previous = (this._sequences || []).find(s => String(s.id) === String(id));
        this._sequences = this._sequences.map(s =>
            String(s.id) === String(id)
                ? this._withAdditionalFees({
                    ...s,
                    glycerol: checked,
                    glycerolFee: checked ? s.glycerolFee : null,
                    totalPrice: this._adjustTotalPriceForGlycerolToggle(s, checked)
                })
                : s
        );
        if (!previous?.savedToSalesforce) {
            return;
        }
        this._addGlycerolUpdating(id);
        updateQuoteRequestLineItemGlycerol({
            lineItemId: id,
            glycerolStock: checked
        }).then(result => {
            if (!result?.success) {
                throw new Error(result?.error || 'Glycerol update failed');
            }
            this._applyCartRemovalFromResult(result);
            this._publishQuoteUpdate('pricing_refresh', {
                lineItemId: id,
                glycerolStock: result.glycerolStock === true,
                priceUpdateRequired: true
            });
            const fee = this._formatGlycerolFee(result.glycerolPrice);
            this._sequences = this._sequences.map(s =>
                String(s.id) === String(id)
                    ? this._withAdditionalFees({
                        ...s,
                        glycerol: result.glycerolStock === true,
                        glycerolFee: fee ?? (checked ? s.glycerolFee : null)
                    })
                    : s
            );
            return this._pollLineItemPricingUntilGlycerolSettled(id);
        }).catch(err => {
            this._removeGlycerolUpdating(id);
            this._sequences = this._sequences.map(s =>
                String(s.id) === String(id)
                    ? this._withAdditionalFees({
                        ...s,
                        glycerol: previous.glycerol,
                        glycerolFee: previous.glycerolFee,
                        totalPrice: previous.totalPrice
                    })
                    : s
            );
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'Failed to update Glycerol. Please try again.',
                variant: 'error'
            }));
            console.error('Glycerol update failed:', err);
        });
    }

    handlePackagingChange(event) {
        if (!this.canEdit) return;
        const nextValue = event.detail?.value ?? event.target.value;
        if (nextValue === this.packagingType) {
            return;
        }
        this.packagingType = nextValue;
        updateQuoteRequestPackaging({
            quoteRequestId: this.effectiveRecordId,
            packagingType: nextValue
        })
            .then(() => this._removeFromCartIfNeeded())
            .catch(err => {
                console.error('Packaging update failed:', err);
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: 'Unable to save packaging type. Please try again.',
                    variant: 'error'
                }));
            });
    }

    handleDeleteSequence(event) {
        event.stopPropagation();
        if (!this.canEdit) return;
        const id = event.currentTarget.dataset.id;
        if (!id || this._isDeletingSequence(id)) return;

        this._addDeletingSequence(id);
        deleteRecordById({ recordId: id })
            .then(() => this._removeFromCartIfNeeded())
            .then(() => {
                this._sequences = this._sequences.filter(s => String(s.id) !== String(id));
                this._removeDeletingSequence(id);
                this.refreshData();
                if (this.messageContext) {
                    publish(this.messageContext, QUOTE_UPDATE_CHANNEL, {
                        updateType: 'sequence_deleted',
                        quoteRequestId: this.effectiveRecordId,
                        timestamp: new Date().toISOString(),
                        details: { sequenceId: id, priceUpdateRequired: true },
                    });
                }
            })
            .catch(err => {
                this._removeDeletingSequence(id);
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: 'Unable to delete sequence.',
                    variant: 'error'
                }));
                console.error(err);
            });
    }

    // ─── Edit modal ─────────────────────────────────────────────────────

    handleCloseEditModal(forceClose) {
        if (forceClose !== true && this.isModalSaveInProgress) {
            return;
        }
        this.showEditModal = false;
        this.editingSequenceId = null;
        this.isInsertingSequence = false;
        this._editOriginalSnapshot = null;
        this.isModalSaveInProgress = false;
        this.editSequenceVectorError = '';
    }

    handleModalContentClick(event) { event.stopPropagation(); }

    _clearModalSaveLock() {
        this.isModalSaveInProgress = false;
    }

    _onModalFieldEdited() {
        if (this.isModalSaveInProgress) {
            this._clearModalSaveLock();
        }
    }

    handleEditNameChange(event) {
        this._onModalFieldEdited();
        this.editSequenceName = event.target.value;
        this._validateEditSequenceName(this.editSequenceName);
    }
    handleEditVectorChange(event) {
        this._onModalFieldEdited();
        this.editSequenceVector = event.detail.value;
        this._validateEditSequenceVector(this.editSequenceVector);
    }

    handleEditSequenceChange(event) {
        this._onModalFieldEdited();
        const val = event.target.value;
        this.editSequenceText = val;
        this.editSequenceCharCount = val.length;
        this._validateEditSequence(val);
    }

    handleSaveEdit() {
        if (!this.canEdit || this.isModalSaveInProgress) {
            return;
        }
        this._validateEditSequence(this.editSequenceText);
        this._validateEditSequenceName(this.editSequenceName);
        this._validateEditSequenceVector(this.editSequenceVector);
        if (this.editSequenceError || this.editSequenceNameError || this.editSequenceVectorError) {
            return;
        }

        if (this.isInsertingSequence) {
            const sequenceName = this.editSequenceName;
            const sequence = this.editSequenceText;
            const vectorId = this._vectorIdForApex(this.editSequenceVector);
            this.isModalSaveInProgress = true;
            createQuoteRequestLineItem({
                quoteRequestId: this.effectiveRecordId,
                sequenceName,
                sequence,
                vectorId,
                potentiallyToxic: false,
                glycerolStock: false,
                reflexVectorOptIn: false
            })
                .then(result => {
                    if (result?.Id) {
                        this._queueDefaultGlycerolApply(result.Id);
                        this._applyPendingGlycerolIfReady();
                        this._applyCartRemoval(this.isInCart || this.quoteInCart);
                        this._completeEditModalSave(result.Id);
                    } else {
                        this.dispatchEvent(new ShowToastEvent({
                            title: 'Error',
                            message: 'Unable to save sequence.',
                            variant: 'error'
                        }));
                    }
                })
                .catch(err => {
                    this.dispatchEvent(new ShowToastEvent({
                        title: 'Error',
                        message: 'Unable to save sequence.',
                        variant: 'error'
                    }));
                    console.error('Create line item failed:', err);
                })
                .finally(() => {
                    this._clearModalSaveLock();
                });
            return;
        }

        if (this._isEditUnchanged()) {
            this.handleCloseEditModal();
            return;
        }

        const lineItemId = this.editingSequenceId;
        const vectorId = this._vectorIdForApex(this.editSequenceVector);
        const original = this._editOriginalSnapshot || {};
        const current = this._snapshotFromEditFields();
        const vectorOnlyChange = this.showVectorSelection
            && current.name === original.name
            && current.sequence === original.sequence
            && current.vector !== original.vector;

        if (vectorOnlyChange) {
            if (!vectorId) {
                return;
            }
            this.isModalSaveInProgress = true;
            updateQuoteLineItemVector({ lineItemId, vectorId })
                .then((result) => {
                    if (!result?.success) {
                        throw new Error(result?.error || 'Failed to update vector.');
                    }
                    return this._removeFromCartIfNeeded();
                })
                .then((result) => {
                    if (result?.removedFromCart === true) {
                        this._applyCartRemovalFromResult(result);
                    }
                    this._completeEditModalSave(lineItemId);
                })
                .catch(err => {
                    this.dispatchEvent(new ShowToastEvent({
                        title: 'Error',
                        message: 'Unable to save sequence changes.',
                        variant: 'error'
                    }));
                    console.error(err);
                })
                .finally(() => {
                    this._clearModalSaveLock();
                });
            return;
        }

        const shouldUpdateVector = this.showVectorSelection && vectorId;

        this.isModalSaveInProgress = true;
        updateSequenceForLineItem({
            lineItemId,
            sequenceName: this.editSequenceName,
            sequence: this.editSequenceText,
            vectorId: shouldUpdateVector ? vectorId : null
        })
            .then((result) => {
                if (!result?.success) {
                    throw new Error(result?.error || 'Unable to save sequence changes.');
                }
                this._completeEditModalSave(lineItemId);
                return this._removeFromCartIfNeeded().then((cartResult) => {
                    if (cartResult?.removedFromCart === true) {
                        this._applyCartRemovalFromResult(cartResult);
                    }
                });
            })
            .catch(err => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: 'Unable to save sequence changes.',
                    variant: 'error'
                }));
                console.error(err);
            })
            .finally(() => {
                this._clearModalSaveLock();
            });
    }

    _snapshotFromEditFields() {
        const vector = !this.showVectorSelection
            ? ''
            : (this.editSequenceVector && this.editSequenceVector !== 'none' ? this.editSequenceVector : '');
        return {
            name: (this.editSequenceName || '').trim(),
            sequence: (this.editSequenceText || '').trim(),
            vector
        };
    }

    _isEditUnchanged() {
        if (!this._editOriginalSnapshot) {
            return false;
        }
        const current = this._snapshotFromEditFields();
        const original = this._editOriginalSnapshot;
        return current.name === original.name
            && current.sequence === original.sequence
            && current.vector === original.vector;
    }

    _vectorIdForApex(val) {
        if (!val || val === 'none') return null;
        return val;
    }

    _applyLineItemPricingToSequence(lineItemId, li) {
        const qli = li.ABT_Quote_Line_Item__r || {};
        let updated = false;
        this._sequences = (this._sequences || []).map(seq => {
            if (String(seq.id) !== String(lineItemId)) {
                return seq;
            }
            updated = true;
            const pricingExtras = this._pricingExtrasFromLineItem(li, seq);
            const merged = {
                ...seq,
                feasibility: this._normalizeFeasibilityFromRow(li, qli),
                complexity: this._normalizeComplexityFromRow(li),
                asEarlyAsDate: li.As_Early_As_Date__c
                    ? this._formatDate(li.As_Early_As_Date__c)
                    : seq.asEarlyAsDate,
                guaranteedDate: li.Expected_Ship_Date__c
                    ? this._formatDate(li.Expected_Ship_Date__c)
                    : seq.guaranteedDate,
                tranche: trancheDisplay(li),
                scaleUp: li.Scale_Up__c || seq.scaleUp,
                potentiallyToxic: li.Potentially_Toxic__c === true,
                reflexVectorOptIn: li.Reflex_Vector_Opt_In__c != null
                    ? li.Reflex_Vector_Opt_In__c === true
                    : seq.reflexVectorOptIn === true,
                ...pricingExtras
            };
            return {
                ...merged,
                totalPrice: this._sequenceTotalPriceFromRow(li, merged),
                endCustomerPrice: this._endCustomerPriceFromRow(li) ?? seq.endCustomerPrice
            };
        });
        if (updated) {
            this._applyFeasibilityGameState();
        }
        return updated;
    }

    _hasPendingLineItemCalculations() {
        return (this._sequences || []).some(seq =>
            this._isFeasibilityPending(seq) ||
            this._isComplexityPending(seq) ||
            this._isAsEarlyAsDatePending(seq) ||
            this._isGuaranteedDatePending(seq)
        );
    }

    _refreshQuoteDataAfterCalculations() {
        if (this._navigatingAway || !this.effectiveRecordId) {
            return;
        }
        if (this.wiredQuoteResult) {
            refreshApex(this.wiredQuoteResult);
        }
        if (this.wiredLineItemsResult && !this.isUpdatingGlycerol) {
            refreshApex(this.wiredLineItemsResult);
        }
    }

    _pollPendingLineItemsSnapshot() {
        if (!this._hasPendingLineItemCalculations()) {
            this._stopLineItemPolling();
            this._refreshQuoteDataAfterCalculations();
            return;
        }

        const pendingIds = (this._sequences || [])
            .filter(seq =>
                this._isFeasibilityPending(seq) ||
                this._isComplexityPending(seq) ||
                this._isAsEarlyAsDatePending(seq) ||
                this._isGuaranteedDatePending(seq)
            )
            .map(seq => seq.id)
            .filter(Boolean);

        pendingIds.forEach(lineItemId => {
            getLineItemPricing({ lineItemId })
                .then(li => {
                    if (li) {
                        const updated = this._applyLineItemPricingToSequence(lineItemId, li);
                        if (updated && !this._hasPendingLineItemCalculations()) {
                            this._stopLineItemPolling();
                            this._refreshQuoteDataAfterCalculations();
                        }
                    }
                })
                .catch(() => {
                    // best-effort; next interval retries
                });
        });
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

    _pollLineItemPricing(lineItemId) {
        if (!lineItemId) {
            return Promise.resolve(false);
        }
        const pollPromise = getLineItemPricing({ lineItemId })
            .then(li => {
                if (li) {
                    const updated = this._applyLineItemPricingToSequence(lineItemId, li);
                    if (updated && !this._hasPendingLineItemCalculations()) {
                        this._stopLineItemPolling();
                        this._refreshQuoteDataAfterCalculations();
                    }
                }
                return Boolean(li);
            })
            .catch(() => false);
        this._startLineItemPolling();
        return pollPromise;
    }

    _pollLineItemPricingUntilGlycerolSettled(lineItemId, attempt = 0) {
        if (!lineItemId) {
            return Promise.resolve();
        }
        return getLineItemPricing({ lineItemId })
            .then(li => {
                const seq = (this._sequences || []).find(s => String(s.id) === String(lineItemId));
                if (li) {
                    this._applyLineItemPricingToSequence(lineItemId, li);
                }
                if (li && seq && this._isGlycerolPricingSettled(li, seq)) {
                    this._removeGlycerolUpdating(lineItemId);
                    if (!this._hasPendingLineItemCalculations()) {
                        this._stopLineItemPolling();
                        this._refreshQuoteDataAfterCalculations();
                    }
                    return;
                }
                if (attempt >= GLYCEROL_POLL_MAX_ATTEMPTS) {
                    this._removeGlycerolUpdating(lineItemId);
                    return;
                }
                this._startLineItemPolling();
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                return new Promise(resolve => {
                    setTimeout(() => {
                        resolve(this._pollLineItemPricingUntilGlycerolSettled(lineItemId, attempt + 1));
                    }, GLYCEROL_POLL_DELAY_MS);
                });
            })
            .catch(() => {
                if (attempt >= GLYCEROL_POLL_MAX_ATTEMPTS) {
                    this._removeGlycerolUpdating(lineItemId);
                    return;
                }
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                return new Promise(resolve => {
                    setTimeout(() => {
                        resolve(this._pollLineItemPricingUntilGlycerolSettled(lineItemId, attempt + 1));
                    }, GLYCEROL_POLL_DELAY_MS);
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

    // ─── Downloads & cart ─────────────────────────────────────────────────

    handleDownloadSequences() {
        if (!this.hasSequences) return;
        const csv = 'SequenceName,Sequence\n' +
            this._sequences.map(s => `${s.name},${s.sequence}`).join('\n');
        this._downloadBlob(csv, 'sequences.csv', 'text/csv');
    }

    async handleDownloadQuotePdf() {
        if (this.isPdfDisabled) return;

        if (this.wiredPdfRecordResult) {
            await refreshApex(this.wiredPdfRecordResult);
        }
        if (this.wiredLineItemsResult) {
            await refreshApex(this.wiredLineItemsResult);
        }
        await new Promise(resolve => setTimeout(resolve, 100));

        const element = this.template.querySelector('.quote-pdf-container');
        if (!element) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Quote PDF',
                message: 'Unable to generate PDF. Please try again.',
                variant: 'error'
            }));
            return;
        }

        const quoteNumber = this.quoteRequestInfo.quoteNumber || this.quoteDisplayId || 'Quote';
        const content = element.innerHTML;
        const printWindow = window.open('', '_blank');
        if (!printWindow) {
            // eslint-disable-next-line no-alert
            alert('Please allow pop-ups for this site to download the quote PDF.');
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
        if (printWindow.document.readyState === 'complete') {
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
        if (this.wiredLineItemsResult) {
            await refreshApex(this.wiredLineItemsResult);
        }
        await new Promise(resolve => setTimeout(resolve, 100));

        const element = this.template.querySelector('.end-customer-pdf-container');
        if (!element) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'End User Quote PDF',
                message: 'Unable to generate PDF. Please try again.',
                variant: 'error'
            }));
            return;
        }

        const quoteNumber = this.quoteRequestInfo.quoteNumber || this.quoteDisplayId || 'Quote';
        const content = element.innerHTML;
        const printWindow = window.open('', '_blank');
        if (!printWindow) {
            // eslint-disable-next-line no-alert
            alert('Please allow pop-ups for this site to download the end user quote PDF.');
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
        if (printWindow.document.readyState === 'complete') {
            triggerPrint();
        } else {
            printWindow.onload = triggerPrint;
        }
    }

    handleCartAction() {
        if (this.isInCartForDisplay) {
            this._navigateToCart();
            return;
        }
        if (!this.isDraft && !this.isQuoted) {
            return;
        }
        if (this.hasSequenceErrors || this.hasSequenceNameErrors || this.hasDuplicateSequenceNames || this.hasVectorErrors) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Required fields missing',
                message: 'Please fix invalid sequences, names, or missing vectors before adding to cart.',
                variant: 'error'
            }));
            return;
        }
        this.isProcessing = true;
        updateQuoteRequestPackaging({
            quoteRequestId: this.effectiveRecordId,
            packagingType: this.packagingType
        })
            .then(() => addQuoteRequestToCommerceCart({ quoteRequestId: this.effectiveRecordId }))
            .then(() => {
                pushDataLayerEvent({ ecommerce: null });
                pushDataLayerEvent({
                    event: 'add_to_cart',
                    quote_id: this.effectiveRecordId,
                    ecommerce: {
                        currency: 'USD',
                        value: this._parseFeeAmount(this.grandTotal),
                        items: [{
                            item_id: this.productId,
                            item_name: this.productName,
                            price: this._parseFeeAmount(this.grandTotal),
                            quantity: 1
                        }]
                    }
                });
                this.quoteInCart = true;
                this._applyQuoteStage();
                if (this.wiredQuoteResult) {
                    return refreshApex(this.wiredQuoteResult);
                }
                return undefined;
            })
            .then(() => {
                this._navigateToCart();
            })
            .catch(err => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: err?.body?.message || 'Unable to add quote to cart.',
                    variant: 'error'
                }));
            })
            .finally(() => { this.isProcessing = false; });
    }

    _navigateToCart() {
        this._navigatingAway = true;
        this._stopLineItemPolling();
        try {
            sessionStorage.setItem(PENDING_CART_QR_KEY, this.effectiveRecordId);
        } catch (e) { /* ignore */ }
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: { url: CART_PAGE_URL }
        });
    }

    handleDeleteQuoteClick() {
        this.showDeleteQuoteModal = true;
    }

    handleCloseDeleteQuoteModal() {
        this.showDeleteQuoteModal = false;
    }

    handleDeleteQuoteModalBackdrop(event) {
        if (event.target.classList.contains('delete-quote-modal-backdrop')) {
            this.handleCloseDeleteQuoteModal();
        }
    }

    async handleConfirmDeleteQuote() {
        if (!this.effectiveRecordId) {
            this.handleCloseDeleteQuoteModal();
            return;
        }

        try {
            this.showDeleteQuoteModal = false;
            this.isProcessing = true;
            await deleteQuoteRequest({ quoteRequestId: this.effectiveRecordId });
            this._navigatingAway = true;
            this._stopLineItemPolling();
            this.dispatchEvent(new ShowToastEvent({
                title: 'Quote deleted',
                variant: 'success'
            }));
            this[NavigationMixin.Navigate]({
                type: 'standard__webPage',
                attributes: { url: QUOTE_LIST_URL }
            });
        } catch (error) {
            const message =
                (error && error.body && error.body.message) ||
                (error && error.message) ||
                'Unable to delete quote.';
            this.dispatchEvent(new ShowToastEvent({
                title: 'Delete failed',
                message,
                variant: 'error',
                mode: 'sticky'
            }));
        } finally {
            this.isProcessing = false;
        }
    }

    _downloadBlob(content, filename, mime) {
        const blob = new Blob([content], { type: mime });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = filename;
        a.click();
        URL.revokeObjectURL(url);
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
            const savedTimestamp = this.gameStartTimestamp || this.loadGameTimestamp();
            if (savedTimestamp && !this.progressTimer && this.isGameModalOpen) {
                this.gameStartTimestamp = savedTimestamp;
                this.startProgressBar();
            }
        }

        this._wasFeasibilityPending = pending;
    }

    loadGameTimestamp() {
        if (!this.effectiveRecordId) {
            return null;
        }
        try {
            const storageKey = `gameTimestamp_${this.effectiveRecordId}`;
            const storedData = localStorage.getItem(storageKey);
            return storedData ? parseInt(storedData, 10) : null;
        } catch (error) {
            return null;
        }
    }

    saveGameTimestamp(timestamp) {
        if (!this.effectiveRecordId) {
            return;
        }
        try {
            const storageKey = `gameTimestamp_${this.effectiveRecordId}`;
            localStorage.setItem(storageKey, timestamp.toString());
        } catch (error) {
            // best-effort
        }
    }

    clearGameTimestamp() {
        if (!this.effectiveRecordId) {
            return;
        }
        try {
            const storageKey = `gameTimestamp_${this.effectiveRecordId}`;
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
        this.progressPercentage = Math.min(Math.round((elapsed / maxDuration) * 100), 100);

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