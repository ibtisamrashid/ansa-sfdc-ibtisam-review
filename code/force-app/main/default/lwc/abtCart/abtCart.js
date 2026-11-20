import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { subscribe, unsubscribe, MessageContext } from 'lightning/messageService';
import { refreshApex } from '@salesforce/apex';
import QUOTE_UPDATE_CHANNEL from '@salesforce/messageChannel/QuoteUpdate__c';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import { getRecord } from 'lightning/uiRecordApi';
import Id from '@salesforce/user/Id';
import USER_ACCOUNT_ID from '@salesforce/schema/User.AccountId';
import ACCOUNT_SALES_REP_EMAIL from '@salesforce/schema/Account.Sales_Rep_Email__c';
import getPortalCommerceCart from '@salesforce/apex/ABT_Portal_Controller.getPortalCommerceCart';
import removeQuoteRequestFromCommerceCart from '@salesforce/apex/ABT_Portal_Controller.removeQuoteRequestFromCommerceCart';
import getQuoteRequestIdsByQuoteIds from '@salesforce/apex/ABT_Portal_Controller.getQuoteRequestIdsByQuoteIds';
import updateCartShippingMethod from '@salesforce/apex/ABT_Portal_Controller.updateCartShippingMethod';
import sendCartEmail from '@salesforce/apex/ABT_Portal_Controller.sendCartEmail';
import QUOTE_REQUEST_OBJECT from '@salesforce/schema/ABT_Quote_Request__c';
import { formatProductName, isGlycerolStockProduct, isScaleUpProduct } from 'c/abtProductNameUtils';
import { distinctTrancheCount } from 'c/abtTrancheUtils';
import SHIPPING_METHOD_FIELD from '@salesforce/schema/ABT_Quote_Request__c.ABT_Shipping_Method__c';
import SHIPPING_DESTINATION_FIELD from '@salesforce/schema/ABT_Quote_Request__c.Shipping_Destination__c';
import {
    filterShippingMethodsByDestination,
    resolveCartShippingDestination
} from 'c/abtShippingMethodUtils';
import ABT_Ansa_Logo from '@salesforce/resourceUrl/ABT_Ansa_Logo';

const QUOTE_LIST_URL = '/AnsaBiotechnologiesCustomerPortal/abt-quote-request/ABT_Quote_Request__c/Default';
const PENDING_CART_QR_KEY = 'abt_pendingCartQuoteRequestId';
const SESSION_RESUME_CHECKOUT_KEY = 'abt_resumeCheckout';
const RESUME_CHECKOUT_URL_PARAM = 'resumeCheckout';

function shouldResumeCheckoutOnLoad() {
    try {
        const params = new URLSearchParams(window.location.search || '');
        if (
            params.get(RESUME_CHECKOUT_URL_PARAM) === '1' ||
            params.get('c__resumeCheckout') === '1'
        ) {
            return true;
        }
        return sessionStorage.getItem(SESSION_RESUME_CHECKOUT_KEY) === '1';
    } catch (e) {
        return false;
    }
}
const SHIPPING_REFRESH_ATTEMPTS = 3;
const SHIPPING_REFRESH_DELAY_MS = 800;
const QUOTE_TOTAL_REFRESH_ATTEMPTS = 3;
const QUOTE_TOTAL_REFRESH_DELAY_MS = 2000;

import {
    analyzeCartQuoteOrderability,
    CHECKOUT_CART_NO_ORDERABLE_LINES_MESSAGE,
    isNotCurrentlyPossibleLine,
    quoteLineItemsFromQuote,
} from 'c/abtQuoteCheckoutUtils';
import { navigateToOrderConfirmation } from 'c/abtQuoteUrls';

function productNameFromLine(li) {
    const p2 = li?.Product2 ?? li?.product2;
    return formatProductName((p2?.Name ?? p2?.name) || '');
}

function uniqueSortedProductNamesFromLines(lines) {
    const names = new Set();
    for (const li of lines) {
        if (isGlycerolStockProduct(li) || isScaleUpProduct(li)) {
            continue;
        }
        const name = productNameFromLine(li);
        if (name) names.add(name);
    }
    return [...names].sort().join(', ');
}

function sequenceTotalFromLines(lines) {
    let sum = 0;
    let visibleCount = 0;
    for (const li of lines) {
        // Glycerol (GS-001) and Scale Up (SC-001) are fee add-ons, not sequences.
        if (isGlycerolStockProduct(li) || isScaleUpProduct(li) || isNotCurrentlyPossibleLine(li)) {
            continue;
        }
        visibleCount += 1;
        const qty = Number(li?.Quantity ?? li?.quantity);
        if (!Number.isNaN(qty) && qty > 0) sum += qty;
    }
    if (sum > 0) return sum;
    return visibleCount;
}

function distinctTrancheCountFromQuoteRequest(qr, quoteLines) {
    const lineItems = quoteRequestLineItems(qr);
    if (lineItems.length > 0) {
        return distinctTrancheCount(lineItems);
    }
    if (quoteLines.length > 0) {
        return distinctTrancheCount(quoteLines);
    }
    return 0;
}

function latestExpectedShipDateFromQuoteRequest(qr) {
    const lineItems = quoteRequestLineItems(qr);
    let latest = null;
    for (const li of lineItems) {
        const raw = li?.Expected_Ship_Date__c ?? li?.expected_Ship_Date__c;
        if (!raw) {
            continue;
        }
        const parsed = new Date(raw);
        if (Number.isNaN(parsed.getTime())) {
            continue;
        }
        if (!latest || parsed > latest) {
            latest = parsed;
        }
    }
    return latest;
}

function asEarlyAsDateFromQuoteRequest(qr) {
    const raw = qr?.As_Early_As_Date__c ?? qr?.as_Early_As_Date__c;
    if (!raw) {
        return null;
    }
    return new Date(raw);
}

function formatGuaranteedShipDate(value) {
    if (!value) {
        return 'Pending';
    }
    if (value instanceof Date) {
        if (Number.isNaN(value.getTime())) {
            return 'Pending';
        }
        const mm = String(value.getMonth() + 1).padStart(2, '0');
        const dd = String(value.getDate()).padStart(2, '0');
        const yy = String(value.getFullYear()).slice(-2);
        return `${mm}/${dd}/${yy}`;
    }
    if (/^\d{4}-\d{2}-\d{2}$/.test(value)) {
        const [y, m, d] = value.split('-');
        return `${m}/${d}/${y.slice(-2)}`;
    }
    const parsed = new Date(value);
    if (Number.isNaN(parsed.getTime())) {
        return 'Pending';
    }
    const mm = String(parsed.getMonth() + 1).padStart(2, '0');
    const dd = String(parsed.getDate()).padStart(2, '0');
    const yy = String(parsed.getFullYear()).slice(-2);
    return `${mm}/${dd}/${yy}`;
}

function productNameFromQuoteRequest(qr) {
    if (!qr) return '';
    const fromName = (qr.ABT_Product_Name__c || '').trim();
    if (fromName) return formatProductName(fromName);
    const p2 = qr.ABT_Product__r ?? qr.abt_Product__r;
    return formatProductName((p2?.Name ?? p2?.name) || '');
}

function productIdFromQuoteRequest(qr) {
    if (!qr) return '';
    const p2 = qr.ABT_Product__r ?? qr.abt_Product__r;
    return qr.ABT_Product__c || qr.abt_Product__c || p2?.Id || p2?.id || '';
}

function productIdFromLines(lines) {
    for (const li of lines) {
        if (isGlycerolStockProduct(li) || isScaleUpProduct(li)) {
            continue;
        }
        const p2 = li?.Product2 ?? li?.product2;
        const id = p2?.Id ?? p2?.id;
        if (id) return id;
    }
    return '';
}
function projectNameFromQuoteRequest(qr) {
    return (qr?.ABT_Customer_Project_Name__c || '').trim();
}

function quoteRequestLineItems(qr) {
    const raw = qr?.Quote_Request_Lineitems__r ?? qr?.quote_Request_Lineitems__r;
    return Array.isArray(raw) ? raw : [];
}

function sequenceCountFromQuoteRequest(qr) {
    if (!qr) return 0;
    const lineItems = quoteRequestLineItems(qr);
    if (lineItems.length > 0) return lineItems.length;
    const rollup = qr.Total_Quote_Request_Line_Items__c;
    if (rollup != null && rollup !== '') {
        const n = Number(rollup);
        return Number.isNaN(n) ? 0 : n;
    }
    return 0;
}

function quoteLineItems(q) {
    const raw = q?.QuoteLineItems ?? q?.quoteLineItems;
    if (Array.isArray(raw)) {
        return raw;
    }
    if (raw?.records && Array.isArray(raw.records)) {
        return raw.records;
    }
    return [];
}

/**
 * Scale Up / Glycerol fees on parent QLI fields.
 * When SC-001/GS-001 child lines exist, those amounts are already in line TotalPrice — do not add again.
 */
function quoteAddonFeesAmount(q) {
    const lines = quoteLineItems(q);
    const hasScaleUpChild = lines.some(isScaleUpProduct);
    const hasGlycerolChild = lines.some(isGlycerolStockProduct);
    return lines.reduce((sum, li) => {
        if (isGlycerolStockProduct(li) || isScaleUpProduct(li)) {
            return sum;
        }
        const scaleUp = (!hasScaleUpChild && Number(li?.Scale_Up_Price__c ?? li?.scale_Up_Price__c)) || 0;
        const glycerol = (!hasGlycerolChild && Number(li?.Glycerol_Price__c ?? li?.glycerol_Price__c)) || 0;
        return sum + (scaleUp > 0 ? scaleUp : 0) + (glycerol > 0 ? glycerol : 0);
    }, 0);
}

/** Sum discounted line totals (QLI.TotalPrice). Falls back to Quote.TotalPrice / Subtotal. */
function quoteProductLinesAmount(q) {
    const lines = quoteLineItems(q);
    if (lines.length === 0) {
        const fallback = Number(q?.TotalPrice ?? q?.totalPrice ?? q?.Subtotal ?? q?.subtotal);
        return Number.isFinite(fallback) ? fallback : 0;
    }
    return lines.reduce((sum, li) => {
        const totalPrice = Number(li?.TotalPrice ?? li?.totalPrice);
        if (Number.isFinite(totalPrice) && totalPrice >= 0) {
            return sum + totalPrice;
        }
        const unitPrice = Number(li?.UnitPrice ?? li?.unitPrice) || 0;
        const quantity = Number(li?.Quantity ?? li?.quantity) || 1;
        return sum + unitPrice * quantity;
    }, 0);
}

function quoteSubtotalAmount(q) {
    // Do not use Quote.Subtotal alone — it is pre-discount. Prefer line TotalPrice + field add-ons.
    return quoteProductLinesAmount(q) + quoteAddonFeesAmount(q);
}

function quoteShippingAmount(q) {
    const ship = Number(q?.ShippingHandling ?? q?.shippingHandling);
    return Number.isFinite(ship) ? ship : 0;
}

function maxQuoteShippingAmount(quotes) {
    return (quotes || []).reduce((maxValue, q) => {
        const shipping = quoteShippingAmount(q);
        return shipping > maxValue ? shipping : maxValue;
    }, 0);
}

function quoteGrandTotalAmount(q) {
    // Derive from product subtotal (incl. Scale Up / glycerol add-ons) + shipping.
    // Quote.GrandTotal does not include Scale_Up_Price__c custom fees.
    return quoteSubtotalAmount(q) + quoteShippingAmount(q);
}

function formatUsd(amount) {
    return '$' + (Number(amount) || 0).toFixed(2);
}

function resolveShippingMethodFromQuotes(options, quotes = []) {
    if (!Array.isArray(quotes) || !quotes.length) {
        return '';
    }

    const maxShipping = maxQuoteShippingAmount(quotes);
    const candidates = quotes
        .filter(q => quoteShippingAmount(q) === maxShipping)
        .map(q => q?.ABT_Shipping_Method__c || q?.abt_Shipping_Method__c)
        .filter(Boolean);

    const uniqueCandidates = [...new Set(candidates)];
    if (uniqueCandidates.length !== 1) {
        return '';
    }

    const candidate = uniqueCandidates[0];
    return options.some(opt => opt.value === candidate) ? candidate : '';
}

export default class AbtCart extends NavigationMixin(LightningElement) {
    @api quoteData = {};

    @track shippingMethod = '';
    @track isEmailModalOpen = false;
    @track emailModalTitle = 'Email Your Procurement';
    @track emailTo = '';
    @track emailSubject = '';
    @track emailMessage = '';
    @track isSendingEmail = false;
    accountRecordId;
    _salesRepEmail = '';
    @track _deletingId = null;
    @track isLoadingQuotes = true;
    @track isUpdatingShipping = false;

    // Inline checkout — used when abtCart is placed directly on the page (no parent)
    @track showInlineCheckout = false;
    @track inlineCheckoutData = {};
    // Detect immediately so first paint shows checkout loading, not the cart list.
    @track _pendingResumeCheckout = shouldResumeCheckoutOnLoad();

    // @track so async quote-request enrichment re-renders product/project/sequence columns
    @track _quoteRequestIdMap = {};
    @track _quoteRequestByQuoteId = {};
    _shippingPicklistOptions = [];
    _shippingMethodPicklistData;
    _shippingPicklistLoadFailed = false;
    @track _shippingPicklistLoaded = false;
    @track _quoteRequestsLoaded = false;
    _pageRef;

    userId = Id;
    ansaLogo = ABT_Ansa_Logo;
    _wiredQuotesResult;
    _cartRefreshSubscription;

    // Polling state — waits for an async-created Quote to appear in wire data
    _expectingQuoteRequestId = null;
    _pollCount = 0;
    _maxPolls = 10;
    _pollTimerId = null;
    @wire(getRecord, { recordId: '$userId', fields: [USER_ACCOUNT_ID] })
    wiredUser({ data }) {
        if (data) {
            this.accountRecordId = data.fields.AccountId?.value || null;
        }
    }

    @wire(getRecord, { recordId: '$accountRecordId', fields: [ACCOUNT_SALES_REP_EMAIL] })
    wiredAccount({ data }) {
        if (data) {
            this._salesRepEmail = data.fields.Sales_Rep_Email__c?.value || '';
        }
    }

    @wire(MessageContext)
    wiredMessageContext(context) {
        if (!context || this._cartRefreshSubscription) {
            return;
        }
        const CART_REFRESH_EVENTS = new Set([
            'cart_refresh',
            'sequence_added',
            'sequence_updated',
            'sequence_deleted',
            'pricing_refresh',
        ]);
        this._cartRefreshSubscription = subscribe(context, QUOTE_UPDATE_CHANNEL, (message) => {
            if (message?.updateType === 'show_cart_view') {
                this.showInlineCheckout = false;
                this.inlineCheckoutData = {};
                return;
            }
            if (CART_REFRESH_EVENTS.has(message?.updateType) && this._wiredQuotesResult) {
                refreshApex(this._wiredQuotesResult);
            }
        });
    }

    @wire(CurrentPageReference)
    handlePageRef(pageRef) {
        this._pageRef = pageRef;
        this._applyPendingQuoteRequestFromContext();
    }

    connectedCallback() {
        this._applyPendingQuoteRequestFromContext();
        this._maybeResumeCheckoutAfterAddress();
        this._boundPageShowHandler = (event) => {
            if (event && event.persisted) {
                this._maybeResumeCheckoutAfterAddress();
            }
            this._refreshCartData();
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            Promise.resolve().then(() => this._resumeCheckoutIfPending());
        };
        window.addEventListener('pageshow', this._boundPageShowHandler);
        // Bust cacheable wire on each cart visit so newly added quotes appear without manual refresh.
        this._refreshCartData();
    }

    _refreshCartData() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        Promise.resolve().then(() => {
            if (this._wiredQuotesResult) {
                refreshApex(this._wiredQuotesResult);
            }
        });
    }

    disconnectedCallback() {
        if (this._boundPageShowHandler) {
            window.removeEventListener('pageshow', this._boundPageShowHandler);
            this._boundPageShowHandler = null;
        }
        if (this._pollTimerId) {
            clearTimeout(this._pollTimerId);
            this._pollTimerId = null;
        }
        if (this._cartRefreshSubscription) {
            unsubscribe(this._cartRefreshSubscription);
            this._cartRefreshSubscription = null;
        }
    }

    @wire(getPortalCommerceCart, { userId: '$userId' })
    wiredQuotes(result) {
        this._wiredQuotesResult = result;

        // While data is still in-flight don't touch loading state; let
        // connectedCallback / polling control it.
        if (result.data == null && !result.error) return;

        if (result.data != null) {
            const quoteIds = result.data.map(q => q.Id);
            if (quoteIds.length > 0) {
                this._quoteRequestsLoaded = false;
                getQuoteRequestIdsByQuoteIds({ quoteIds })
                    .then(qrs => {
                        const map = {};
                        const byQuoteId = {};
                        (qrs || []).forEach(qr => {
                            map[qr.ABT_Quote__c] = qr.Id;
                            byQuoteId[qr.ABT_Quote__c] = qr;
                        });
                        this._quoteRequestIdMap = { ...map };
                        this._quoteRequestByQuoteId = { ...byQuoteId };
                        this._quoteRequestsLoaded = true;
                        this._ensureSelectedShippingMethod();
                        this._resolvePolling();
                        this._resumeCheckoutIfPending();
                    })
                    .catch(() => {
                        this._quoteRequestIdMap = {};
                        this._quoteRequestByQuoteId = {};
                        this._quoteRequestsLoaded = true;
                        this._ensureSelectedShippingMethod();
                        this._resolvePolling();
                        this._resumeCheckoutIfPending();
                    });
            } else {
                this._quoteRequestIdMap = {};
                this._quoteRequestByQuoteId = {};
                this._quoteRequestsLoaded = true;
                this._ensureSelectedShippingMethod();
                this._resolvePolling();
                this._resumeCheckoutIfPending();
            }
        } else if (result.error) {
            this._expectingQuoteRequestId = null;
            if (this._pollTimerId) { clearTimeout(this._pollTimerId); this._pollTimerId = null; }
            this.isLoadingQuotes = false;
        }
    }

    // Called after each wire result + ID-map rebuild.
    // Stops polling once the expected quote request ID appears, or after max retries.
    _resolvePolling() {
        if (!this._expectingQuoteRequestId) {
            this.isLoadingQuotes = false;
            this._resumeCheckoutIfPending();
            return;
        }
        const found = Object.values(this._quoteRequestIdMap).includes(this._expectingQuoteRequestId);
        if (found) {
            this._clearPendingQuoteRequestId();
            this._expectingQuoteRequestId = null;
            this.isLoadingQuotes = false;
            this._refreshQuoteTotalsAfterAdd();
            this._resumeCheckoutIfPending();
        } else if (this._pollCount < this._maxPolls) {
            this._pollCount++;
            // Keep spinner visible and schedule the next refresh
            this._pollTimerId = setTimeout(() => {
                this._pollTimerId = null;
                refreshApex(this._wiredQuotesResult);
            }, 2000);
        } else {
            // Pending quote never became cart-eligible (e.g. draft-only visit)
            this._clearPendingQuoteRequestId();
            this._expectingQuoteRequestId = null;
            this.isLoadingQuotes = false;
            this._resumeCheckoutIfPending();
        }
    }

    get _quotesData() {
        return (this._wiredQuotesResult && this._wiredQuotesResult.data)
            ? this._wiredQuotesResult.data
            : [];
    }

    get quotes() {
        return this._quotesData.map(q => {
            const lines = quoteLineItemsFromQuote(q);
            const productFromLines = uniqueSortedProductNamesFromLines(lines);
            const qr = this._quoteRequestByQuoteId[q.Id];
            const productFromQr = productNameFromQuoteRequest(qr);
            const productIdFromQr = productIdFromQuoteRequest(qr);
            const productIdFromLine = productIdFromLines(lines);
            const productFromQuoteField = (q.Product_Type__c || q.product_Type__c || '').trim();
            const projectFromQr = projectNameFromQuoteRequest(qr);
            const projectTitle = (q.Customer_Project_Name__c || '').trim();
            const opp = q.Opportunity || q.opportunity;
            const oppName = (opp && (opp.Name || opp.name)) || '';
            const groups = distinctTrancheCountFromQuoteRequest(qr, lines);
            const seqFromLines = sequenceTotalFromLines(lines);
            const seqFromQr = sequenceCountFromQuoteRequest(qr);
            const guaranteedShipDate = latestExpectedShipDateFromQuoteRequest(qr);
            const asEarlyAsDate = asEarlyAsDateFromQuoteRequest(qr);

            return {
                id: q.Id,
                quoteRequestId: this._quoteRequestIdMap[q.Id] || null,
                quoteId: q.Ansa_Quote_Number__c || q.QuoteNumber || q.Id,
                productId: productIdFromQr || productIdFromLine || '',   // ← new
                productName: productFromQr || productFromLines || productFromQuoteField,
                projectName: projectTitle || projectFromQr || oppName,
                // Prefer Quote Request lines (true sequences). Quote lines include
                // Scale Up / Glycerol add-ons that must not inflate the count.
                sequenceCount:
                    seqFromQr > 0 ? seqFromQr : seqFromLines,
                groupCount: String(groups),
                asEarlyAsDate: formatGuaranteedShipDate(asEarlyAsDate),
                shipDate: formatGuaranteedShipDate(guaranteedShipDate),
                subtotalAmount: quoteSubtotalAmount(q),
                shippingAmount: quoteShippingAmount(q),
                grandTotalAmount: quoteGrandTotalAmount(q),
                totalPrice: quoteSubtotalAmount(q) > 0
                    ? formatUsd(quoteSubtotalAmount(q))
                    : 'TBD',
                status: q.Status,
            };
        });
    }

    get hasQuotes() {
        return this.quotes.length > 0;
    }

    get cartIsEmpty() {
        return !this.hasQuotes;
    }

    get cartOrderability() {
        return analyzeCartQuoteOrderability(this._quotesData);
    }

    get hasNotCurrentlyPossibleSequences() {
        return this.cartOrderability.hasNotCurrentlyPossibleSequences;
    }

    get hasBlockedCartQuotes() {
        return this.cartOrderability.hasBlockedCartQuotes;
    }

    get isCheckoutDisabled() {
        return (
            this.cartIsEmpty ||
            this.isLoadingQuotes ||
            !this.isShippingReady ||
            !this.shippingMethod ||
            this.shippingOptions.length === 0 ||
            this.hasBlockedCartQuotes
        );
    }

    get isShippingReady() {
        if (!this.hasQuotes) {
            return true;
        }
        return this._shippingPicklistLoaded && this._quoteRequestsLoaded;
    }

    get isShippingSelectDisabled() {
        return this.isUpdatingShipping || !this.isShippingReady;
    }

    get showCartView() {
        return !this.showInlineCheckout && !this._pendingResumeCheckout;
    }

    get showResumingCheckout() {
        return this._pendingResumeCheckout && !this.showInlineCheckout;
    }

    get subtotal() {
        const total = this._quotesData.reduce((sum, q) => sum + quoteSubtotalAmount(q), 0);
        return formatUsd(total);
    }

    get shipping() {
        return formatUsd(maxQuoteShippingAmount(this._quotesData));
    }

    get grandTotal() {
        // Cart-level shipping should charge only the most expensive quote shipping.
        const subtotal = this._quotesData.reduce((sum, q) => sum + quoteSubtotalAmount(q), 0);
        const shipping = maxQuoteShippingAmount(this._quotesData);
        return formatUsd(subtotal + shipping);
    }

    get cartPdfDate() {
        return new Date().toLocaleDateString('en-US', {
            year: 'numeric',
            month: 'long',
            day: 'numeric',
        });
    }

    get shippingOptions() {
        if (!this.isShippingReady || !this._shippingMethodPicklistData) {
            return [];
        }

        const resolvedDestination = resolveCartShippingDestination(
            Object.values(this._quoteRequestByQuoteId || {})
        );

        return filterShippingMethodsByDestination(
            this._shippingMethodPicklistData,
            resolvedDestination
        );
    }

    _refreshQuoteTotalsAfterAdd() {
        if (!this._wiredQuotesResult) {
            return;
        }
        for (let i = 1; i <= QUOTE_TOTAL_REFRESH_ATTEMPTS; i++) {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                refreshApex(this._wiredQuotesResult);
            }, QUOTE_TOTAL_REFRESH_DELAY_MS * i);
        }
    }

    async handleShippingChange(event) {
        this.shippingMethod = event.detail.value;
        await this._persistShippingAndRefresh();
    }

    async _persistShippingAndRefresh() {
        const quoteIds = this._quotesData.map(q => q.Id).filter(Boolean);
        if (!quoteIds.length || !this.shippingMethod) {
            return;
        }

        this.isUpdatingShipping = true;
        try {
            await updateCartShippingMethod({
                quoteIds,
                shippingMethodValue: this.shippingMethod
            });

            // Flows update ShippingHandling asynchronously; refresh a few times so
            // totals reflect the recalculated server-side values.
            for (let i = 0; i < SHIPPING_REFRESH_ATTEMPTS; i++) {
                await new Promise(resolve => setTimeout(resolve, SHIPPING_REFRESH_DELAY_MS));
                // eslint-disable-next-line no-await-in-loop
                await refreshApex(this._wiredQuotesResult);
            }
        } catch (error) {
            console.error('Error updating shipping method:', error);
            const msg = error?.body?.message || error?.message || 'Unable to update shipping method.';
            // eslint-disable-next-line no-alert
            alert(msg);
        } finally {
            this.isUpdatingShipping = false;
        }
    }

    handleQuoteClick(event) {
        // Ignore clicks that originated on the delete icon
        if (event.target.closest('[data-delete]')) return;
        const quoteRequestId = event.currentTarget.dataset.requestId;
        if (!quoteRequestId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: '/AnsaBiotechnologiesCustomerPortal/abt-quote-request/' + quoteRequestId
            }
        });
    }

    handleDeleteQuote(event) {
        event.stopPropagation();
        const quoteRequestId = event.currentTarget.dataset.requestId;
        if (!quoteRequestId) {
            return;
        }
        this._deletingId = quoteRequestId;
        removeQuoteRequestFromCommerceCart({ quoteRequestId })
            .then(() => refreshApex(this._wiredQuotesResult))
            .catch(error => console.error('Error removing quote from cart:', error))
            .finally(() => { this._deletingId = null; });
    }

    async handleDownloadCartPdf() {
        if (this.cartIsEmpty) {
            // eslint-disable-next-line no-alert
            alert('Your cart is empty. Add quotes before downloading.');
            return;
        }

        if (this._wiredQuotesResult) {
            await refreshApex(this._wiredQuotesResult);
            await new Promise(resolve => setTimeout(resolve, 100));
        }

        const element = this.template.querySelector('.cart-pdf-container');
        if (!element) {
            // eslint-disable-next-line no-alert
            alert('Unable to generate cart PDF. Please try again.');
            return;
        }

        const content = element.innerHTML;
        const printWindow = window.open('', '_blank');
        if (!printWindow) {
            // eslint-disable-next-line no-alert
            alert('Please allow pop-ups for this site to download the cart PDF.');
            return;
        }

        printWindow.document.open();
        printWindow.document.write(`
            <html>
                <head>
                    <title>AnsaBio Cart</title>
                    <style>
                        body { font-family: Arial, sans-serif; margin: 24px; color: #222; }
                        @media print {
                            body { margin: 12px; }
                        }
                    </style>
                </head>
                <body>
                    ${content}
                </body>
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

    handleEmailProcurement() {
        this.emailModalTitle = 'Email Your Procurement';
        this.emailTo = '';
        this.emailSubject = '';
        this.emailMessage = '';
        this.isEmailModalOpen = true;
    }

    handleEmailSalesRep() {
        const salesRepEmail = (this._salesRepEmail || '').trim();
        if (!salesRepEmail) {
            // eslint-disable-next-line no-alert
            alert('No sales rep email is configured on your account. Please update it under My Account or contact support.');
            return;
        }
        this.emailModalTitle = 'Email Your Sales Rep';
        this.emailTo = salesRepEmail;
        this.emailSubject = '';
        this.emailMessage = '';
        this.isEmailModalOpen = true;
    }

    closeEmailModal() {
        this.isEmailModalOpen = false;
        this.emailModalTitle = 'Email Your Procurement';
        this.emailTo = '';
        this.emailSubject = '';
        this.emailMessage = '';
    }

    handleEmailToChange(event) { this.emailTo = event.target.value; }
    handleEmailSubjectChange(event) { this.emailSubject = event.target.value; }
    handleEmailMessageChange(event) { this.emailMessage = event.target.value; }

    handleContinueShopping() {
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: QUOTE_LIST_URL
            }
        });
    }

    _cartHtmlForEmail() {
        const element = this.template.querySelector('.cart-pdf-container');
        return element ? element.innerHTML : '';
    }

    async handleSendEmail() {
        if (!this.emailTo) {
            // eslint-disable-next-line no-alert
            alert('Please enter a recipient email address.');
            return;
        }
        if (this.cartIsEmpty) {
            // eslint-disable-next-line no-alert
            alert('Your cart is empty. Add quotes before sending.');
            return;
        }

        this.isSendingEmail = true;

        // Make sure the hidden cart PDF markup reflects the latest totals.
        if (this._wiredQuotesResult) {
            try {
                await refreshApex(this._wiredQuotesResult);
                await new Promise(resolve => setTimeout(resolve, 100));
            } catch (refreshError) {
                console.error('Error refreshing cart before email:', refreshError);
            }
        }

        try {
            await sendCartEmail({
                toAddress: this.emailTo,
                subject: this.emailSubject,
                message: this.emailMessage,
                cartHtml: this._cartHtmlForEmail()
            });
            this.closeEmailModal();
            // eslint-disable-next-line no-alert
            alert('Email sent successfully!');
        } catch (error) {
            console.error('Error sending cart email:', error);
            const msg = error?.body?.message || error?.message || 'Unable to send email. Please try again.';
            // eslint-disable-next-line no-alert
            alert(msg);
        } finally {
            this.isSendingEmail = false;
        }
    }

    handleCheckout() {
        if (this.isCheckoutDisabled) {
            return;
        }
        if (this.hasBlockedCartQuotes) {
            // eslint-disable-next-line no-alert
            alert(CHECKOUT_CART_NO_ORDERABLE_LINES_MESSAGE);
            return;
        }
        const orderability = this.cartOrderability;
        const quoteIds = this._quotesData.map(q => q.Id);
        const detail = {
            accountId: this._quotesData[0]?.AccountId || '',
            quoteIds,
            quotes: this.quotes,
            shippingMethod: this.shippingMethod,
            subtotal: this.subtotal,
            shipping: this.shipping,
            grandTotal: this.grandTotal,
            hasNotCurrentlyPossibleSequences: orderability.hasNotCurrentlyPossibleSequences,
            hasBlockedCartQuotes: orderability.hasBlockedCartQuotes,
        };

        // Dispatch a cancelable event — a parent (abtNewOrder) will call preventDefault()
        // to signal it handled the navigation. If nothing cancels it, we're standalone
        // on the my_Cart page and show checkout inline.
        const evt = new CustomEvent('checkout', { detail: detail, cancelable: true });
        this.dispatchEvent(evt);

        if (!evt.defaultPrevented) {
            this.inlineCheckoutData = detail;
            this.showInlineCheckout = true;
        }
    }

    handleInlineCheckoutBack() {
        this.showInlineCheckout = false;
        this.inlineCheckoutData = {};
    }

    handleInlineCheckoutComplete(event) {
        const orderId = event && event.detail && event.detail.orderId;
        navigateToOrderConfirmation(orderId);
    }

    _maybeResumeCheckoutAfterAddress() {
        try {
            const fromUrl = this._hasResumeCheckoutUrlParam();
            const fromSession = sessionStorage.getItem(SESSION_RESUME_CHECKOUT_KEY) === '1';
            if (!fromUrl && !fromSession) {
                return;
            }
            if (fromSession) {
                sessionStorage.removeItem(SESSION_RESUME_CHECKOUT_KEY);
            }
            this._pendingResumeCheckout = true;
            if (fromUrl) {
                this._clearResumeCheckoutUrlParam();
            }
        } catch (e) {
            /* ignore */
        }
    }

    _hasResumeCheckoutUrlParam() {
        try {
            const params = new URLSearchParams(window.location.search);
            return params.get(RESUME_CHECKOUT_URL_PARAM) === '1'
                || params.get('c__resumeCheckout') === '1';
        } catch (e) {
            return false;
        }
    }

    _clearResumeCheckoutUrlParam() {
        try {
            const url = new URL(window.location.href);
            url.searchParams.delete(RESUME_CHECKOUT_URL_PARAM);
            url.searchParams.delete('c__resumeCheckout');
            const next = url.pathname + url.search + url.hash;
            window.history.replaceState({}, '', next);
        } catch (e) {
            /* ignore */
        }
    }

    _resumeCheckoutIfPending() {
        if (!this._pendingResumeCheckout) {
            return;
        }
        // Wait until cart data is ready — UI already shows checkout loading, not cart list.
        if (this.isLoadingQuotes) {
            return;
        }
        if (this.cartIsEmpty) {
            this._pendingResumeCheckout = false;
            return;
        }
        if (this.isCheckoutDisabled) {
            return;
        }
        this._pendingResumeCheckout = false;
        this.handleCheckout();
    }

    @wire(getObjectInfo, { objectApiName: QUOTE_REQUEST_OBJECT })
    quoteRequestObjectInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$quoteRequestObjectInfo.data.defaultRecordTypeId',
        fieldApiName: SHIPPING_METHOD_FIELD,
        controllerFieldApiName: SHIPPING_DESTINATION_FIELD
    })
    wiredShippingMethodValues({ data, error }) {
        if (data && Array.isArray(data.values)) {
            this._shippingPicklistLoadFailed = false;
            this._shippingMethodPicklistData = data;
            this._shippingPicklistOptions = data.values.map(item => ({
                label: item.label,
                value: item.value
            }));
            this._shippingPicklistLoaded = true;
            this._ensureSelectedShippingMethod();
            this._resumeCheckoutIfPending();
        } else if (error) {
            console.error('Error loading shipping method picklist:', error);
            this._shippingPicklistLoadFailed = true;
            this._shippingMethodPicklistData = null;
            this._shippingPicklistOptions = [];
            this._shippingPicklistLoaded = false;
            this.shippingMethod = '';
        }
    }

    _applyPendingQuoteRequestFromContext() {
        let pendingId = (this.quoteData && this.quoteData.quoteRequestId) || '';

        if (!pendingId) {
            pendingId = this._quoteRequestIdFromUrl();
        }
        if (!pendingId) {
            try {
                pendingId = sessionStorage.getItem(PENDING_CART_QR_KEY) || '';
            } catch (e) {
                pendingId = '';
            }
        }

        if (!pendingId) {
            return;
        }

        if (this._expectingQuoteRequestId === pendingId) {
            return;
        }

        this._expectingQuoteRequestId = pendingId;
        this._pollCount = 0;
        this.isLoadingQuotes = true;

        if (this._wiredQuotesResult) {
            refreshApex(this._wiredQuotesResult);
        }
    }

    _quoteRequestIdFromUrl() {
        try {
            const params = new URLSearchParams(window.location.search);
            return (
                params.get('quoteRequestId') ||
                params.get('c__quoteRequestId') ||
                (this._pageRef && this._pageRef.state && (
                    this._pageRef.state.quoteRequestId ||
                    this._pageRef.state.c__quoteRequestId
                )) ||
                ''
            );
        } catch (e) {
            return '';
        }
    }

    _clearPendingQuoteRequestId() {
        try {
            sessionStorage.removeItem(PENDING_CART_QR_KEY);
        } catch (e) {
            /* ignore */
        }
    }

    _ensureSelectedShippingMethod() {
        if (!this.hasQuotes) {
            this.shippingMethod = '';
            return;
        }

        if (!this.isShippingReady) {
            return;
        }

        const options = this.shippingOptions;
        if (!options.length) {
            this.shippingMethod = '';
            return;
        }

        if (this.shippingMethod && options.some(opt => opt.value === this.shippingMethod)) {
            return;
        }

        const firstQuoteMethod = this._quotesData
            .map(q => q?.ABT_Shipping_Method__c || q?.abt_Shipping_Method__c)
            .find(value => options.some(opt => opt.value === value));

        if (firstQuoteMethod) {
            this.shippingMethod = firstQuoteMethod;
            return;
        }

        const firstQrMethod = Object.values(this._quoteRequestByQuoteId || {})
            .map(qr => qr?.ABT_Shipping_Method__c)
            .find(value => options.some(opt => opt.value === value));

        if (firstQrMethod) {
            this.shippingMethod = firstQrMethod;
            return;
        }

        const matchedByAmount = resolveShippingMethodFromQuotes(options, this._quotesData);

        if (matchedByAmount) {
            this.shippingMethod = matchedByAmount;
            return;
        }

        this.shippingMethod = options[0].value;
    }
}