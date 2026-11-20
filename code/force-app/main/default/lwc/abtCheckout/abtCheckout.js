import { LightningElement, api, track } from 'lwc';
import { distinctTrancheCount } from 'c/abtTrancheUtils';
import getUserDetailsById from '@salesforce/apex/ABT_Portal_Controller.getUserDetailsById';
import getContactPointAddresses from '@salesforce/apex/ABT_Portal_Controller.getContactPointAddresses';
import getActiveBpoForAccount from '@salesforce/apex/ABT_Portal_Controller.getActiveBpoForAccount';
import getPaymentMethodsByContact from '@salesforce/apex/ABT_Portal_Controller.getPaymentMethodsByContact';
import getPaymentMethodsByContactFresh from '@salesforce/apex/ABT_Portal_Controller.getPaymentMethodsByContactFresh';
import placeOrder from '@salesforce/apex/ABT_Portal_Controller.placeOrder';
import placeOrderForCart from '@salesforce/apex/ABT_Portal_Controller.placeOrderForCart';
import updateContactInvoiceEmail from '@salesforce/apex/ABT_Portal_Controller.updateContactInvoiceEmail';
import {
    CHECKOUT_CART_NO_ORDERABLE_LINES_MESSAGE,
    CHECKOUT_CUSTOMER_MESSAGE,
} from 'c/abtQuoteCheckoutUtils';
import { isInvalidApexRequestError } from 'c/abtPortalSessionUtils';
import { PORTAL_BASE, navigateToOrderConfirmation } from 'c/abtQuoteUrls';
import userId from '@salesforce/user/Id';
import ABT_Portal_Url_for_VF_Page from '@salesforce/label/c.ABT_Portal_Url_for_VF_Page';
import { pushDataLayerEvent } from 'c/abtGoogleAdsTracking';

const SESSION_RESUME_CHECKOUT_KEY = 'abt_resumeCheckout';
const SESSION_RETURN_URL_KEY = 'abt_addressFormReturnUrl';

function formatCardOptionLabel(row) {
    const holder = row.ABT_Card_Holder_Name__c || 'Card';
    const cardNumber = row.ABT_Card_Number__c || '';
    return cardNumber ? `${holder} - ${cardNumber}` : holder;
}

export default class AbtCheckout extends LightningElement {
    @api quoteData = {};

    @track isLoadingCheckout = true;
    @track isCheckingOut = false;
    @track checkoutCompleted = false;

    // User info
    currentUserId = userId;
    @track currentUserName = '';

    // Checkout form fields
    @track checkoutPaymentMethod = 'purchase_order';
    @track poNumber = '';
    @track isTaxExempt = false;
    @track isPartialShipment = false;
    @track checkoutNotes = '';
    @track promoCode = '';
    @track invoiceEmail = '';
    _savedInvoiceEmail = '';

    // Credit card — saved Stripe payment methods
    contactId = '';
    @track savedPaymentMethods = [];
    @track selectedPaymentMethodId = '';
    @track isLoadingPaymentMethods = false;
    @track isNewCreditCardModalOpen = false;
    paymentMethodIframeUrl = '';

    // BPO fields
    accountId = '';
    @track bpoId = null;
    @track bpoNumber = '';
    @track bpoRemainingAmount = null;
    @track bpoLookupDone = false;
    @track isLookingUpBpo = false;

    // Tooltip
    @track showPartialTooltip = false;

    // Documents
    @track uploadedDocName = '';
    @track uploadedDocData = '';

    // Addresses
    @track billingAddresses = [];
    @track shippingAddresses = [];
    @track selectedBillingAddr = '';
    @track selectedShippingAddr = '';
    @track incoTerms = 'FCA';

    connectedCallback() {
        this.loadCheckoutData();
        this._outsideClickHandler = () => {
            if (this.showPartialTooltip) this.showPartialTooltip = false;
        };
        this._paymentMessageHandler = this.handlePaymentMethodMessage.bind(this);
        document.addEventListener('click', this._outsideClickHandler);
        window.addEventListener('message', this._paymentMessageHandler);
    }

    disconnectedCallback() {
        document.removeEventListener('click', this._outsideClickHandler);
        window.removeEventListener('message', this._paymentMessageHandler);
    }

    // ─── Load user details + addresses ──────────────────────────────────

    loadCheckoutData() {
        this.isLoadingCheckout = true;

        getUserDetailsById({ userId: this.currentUserId })
            .then(user => {
                this.currentUserName = user.Name || user.name || '';
                this.contactId = user.ContactId || '';
                this.invoiceEmail = this.normalizeInvoiceEmail(user.Contact?.Invoice_Email__c);
                this._savedInvoiceEmail = user.Contact?.Invoice_Email__c || '';
                // Prefer accountId from quoteData; fall back to the user's own AccountId
                this.accountId = this.quoteData.accountId || user.AccountId || '';
                this.incoTerms = user.Account?.IncoTerms__c || 'FCA';
                this.isPartialShipment = user.Account?.Always_Accept_Partial__c === true;
                return Promise.all([
                    getContactPointAddresses({ accountId: this.accountId, addressType: 'Billing' }),
                    getContactPointAddresses({ accountId: this.accountId, addressType: 'Shipping' })
                ]);
            })
            .then(([billing, shipping]) => {
                this.billingAddresses = (billing || []).map((a, i) => {
                    const addr = a.Address || {};
                    const line = [addr.street, addr.city, addr.state, addr.country, addr.postalCode].filter(Boolean).join(', ');
                    return { ...a, displayAddress: line, isSelected: i === 0 };
                });
                this.shippingAddresses = (shipping || []).map((a, i) => {
                    const addr = a.Address || {};
                    const line = [addr.street, addr.city, addr.state, addr.country, addr.postalCode].filter(Boolean).join(', ');
                    return { ...a, displayAddress: line, isSelected: i === 0 };
                });
                if (this.billingAddresses.length > 0) this.selectedBillingAddr = this.billingAddresses[0].Id;
                if (this.shippingAddresses.length > 0) this.selectedShippingAddr = this.shippingAddresses[0].Id;
                this.isLoadingCheckout = false;
                if (this.isBpo) {
                    this.lookupBpo();
                }
                if (this.isCreditCard) {
                    this.loadSavedPaymentMethods();
                }
            })
            .catch(error => {
                console.error('Error loading checkout data:', error);
                this.isLoadingCheckout = false;
            });
    }

    // ─── Computed getters from quoteData ────────────────────────────────

    // CHANGED: display getter uses quoteNumber for the table, not the record ID
    get quoteId() { return this.quoteData.quoteNumber || this.quoteData.quoteId || ''; }
    get productName() { return this.quoteData.productName || ''; }
    get projectName() { return this.quoteData.projectName || ''; }

    get sequenceCount() {
        return (this.quoteData.sequences || []).length;
    }

    get groupCount() {
        const quotes = this.quoteData.quotes || [];
        if (quotes.length === 1 && quotes[0].groupCount) {
            return quotes[0].groupCount;
        }
        return distinctTrancheCount(this.quoteData.sequences || []);
    }

    get shipDate() {
        const quotes = this.quoteData.quotes || [];
        if (quotes.length === 1 && quotes[0].shipDate) {
            return quotes[0].shipDate;
        }
        if (this.quoteData.shipDate) {
            return this.quoteData.shipDate;
        }
        const seqDates = (this.quoteData.sequences || [])
            .map(s => s.guaranteedDate)
            .filter(d => d && d !== 'Pending' && d !== 'TBD');
        return seqDates.length ? seqDates[0] : 'Pending';
    }

    get asEarlyAsDate() {
        const quotes = this.quoteData.quotes || [];
        if (quotes.length === 1 && quotes[0].asEarlyAsDate) {
            return quotes[0].asEarlyAsDate;
        }
        if (this.quoteData.asEarlyAsDate) {
            return this.quoteData.asEarlyAsDate;
        }
        const seqDates = (this.quoteData.sequences || [])
            .map(s => s.asEarlyAsDate)
            .filter(d => d && d !== 'Pending' && d !== 'TBD');
        return seqDates.length ? seqDates[0] : 'Pending';
    }

    get totalPrice() {
        const quotes = this.quoteData.quotes || [];
        if (quotes.length === 1 && quotes[0].totalPrice) {
            return quotes[0].totalPrice;
        }
        return this.quoteData.subtotal || '$0.00';
    }

    get subtotal() {
        if (this.quoteData.subtotal) {
            return this.quoteData.subtotal;
        }
        const quotes = this.quoteData.quotes || [];
        if (quotes.length > 0) {
            const sum = quotes.reduce((acc, q) => {
                const price = parseFloat((q.totalPrice || '$0').replace(/[^0-9.]/g, '')) || 0;
                return acc + price;
            }, 0);
            return '$' + sum.toFixed(2);
        }
        return '$0.00';
    }

    get shipping() {
        return this.quoteData.shipping || '$0.00';
    }

    get grandTotal() {
        if (this.quoteData.grandTotal) {
            return this.quoteData.grandTotal;
        }
        const sub = parseFloat((this.subtotal || '$0').replace(/[^0-9.]/g, '')) || 0;
        const ship = parseFloat((this.shipping || '$0').replace(/[^0-9.]/g, '')) || 0;
        return '$' + (sub + ship).toFixed(2);
    }

    get checkoutShippingLabel() {
        // Server/picklist value is the source of truth for checkout shipping display.
        return this.quoteData.shippingMethod || 'FedEx Express Priority Overnight ($35)';
    }

    get paymentMethodOptions() {
        return [
            { label: 'Purchase Order', value: 'purchase_order' },
            { label: 'Blanket Purchase Order', value: 'bpo' },
            { label: 'Credit Card', value: 'credit_card' },
        ];
    }

    get isPurchaseOrder() { return this.checkoutPaymentMethod === 'purchase_order'; }
    get isCreditCard() { return this.checkoutPaymentMethod === 'credit_card'; }
    get isBpo() { return this.checkoutPaymentMethod === 'bpo'; }

    get hasBpoOnFile() { return this.bpoRemainingAmount !== null; }

    get hasSavedPaymentMethods() {
        return this.savedPaymentMethods.length > 0;
    }

    get hasBillingAddresses() { return this.billingAddresses && this.billingAddresses.length > 0; }
    get hasShippingAddresses() { return this.shippingAddresses && this.shippingAddresses.length > 0; }

    get isMultiQuote() { return (this.quoteData.quoteIds || []).length > 0; }
    get quotesForDisplay() { return this.quoteData.quotes || []; }
    get hasNotCurrentlyPossibleSequences() {
        return this.quoteData.hasNotCurrentlyPossibleSequences === true;
    }
    get hasBlockedCartQuotes() {
        return this.quoteData.hasBlockedCartQuotes === true;
    }
    get checkoutBlockedMessage() {
        return CHECKOUT_CART_NO_ORDERABLE_LINES_MESSAGE;
    }
    get showBlockingOverlay() { return this.isLoadingCheckout || this.isCheckingOut; }
    get isSubmitDisabled() {
        return (
            this.isCheckingOut ||
            this.isLoadingCheckout ||
            this.checkoutCompleted ||
            this.hasBlockedCartQuotes
        );
    }
    get isCancelDisabled() { return this.isCheckingOut || this.checkoutCompleted; }

    // ─── Form handlers ──────────────────────────────────────────────────

    handlePaymentMethodChange(event) {
        this.checkoutPaymentMethod = event.detail.value;
        // Reset dependent fields when switching
        this.poNumber = '';
        this.selectedPaymentMethodId = '';
        this.bpoId = null;
        this.bpoNumber = '';
        this.bpoRemainingAmount = null;
        this.bpoLookupDone = false;

        // Auto-lookup BPO when selected
        if (this.checkoutPaymentMethod === 'bpo') {
            this.lookupBpo();
        }
        if (this.checkoutPaymentMethod === 'credit_card') {
            this.loadSavedPaymentMethods();
        }
    }

    handlePoNumberChange(event) { this.poNumber = event.target.value; }
    handleTaxExemptChange(event) { this.isTaxExempt = event.target.checked; }
    handlePartialShipChange(event) { this.isPartialShipment = event.target.checked; }
    handleNotesChange(event) { this.checkoutNotes = event.target.value; }
    handlePromoChange(event) { this.promoCode = event.target.value; }

    handleLearnMore(event) {
        event.preventDefault();
        event.stopPropagation();
        this.showPartialTooltip = !this.showPartialTooltip;
    }

    loadSavedPaymentMethods(preferredPaymentMethodId) {
        if (!this.contactId) {
            this.savedPaymentMethods = [];
            return Promise.resolve();
        }

        this.isLoadingPaymentMethods = true;
        return getPaymentMethodsByContactFresh({ contactId: this.contactId })
            .then(rows => {
                const options = (rows || []).map(pm => ({
                    label: formatCardOptionLabel(pm),
                    value: pm.Id
                }));
                this.savedPaymentMethods = options;
                if (preferredPaymentMethodId) {
                    this.selectedPaymentMethodId = preferredPaymentMethodId;
                } else if (options.length === 1) {
                    this.selectedPaymentMethodId = options[0].value;
                } else if (
                    this.selectedPaymentMethodId &&
                    !options.some(o => o.value === this.selectedPaymentMethodId)
                ) {
                    this.selectedPaymentMethodId = options[0]?.value || '';
                }
            })
            .catch(error => {
                console.error('Error loading payment methods:', error);
                this.savedPaymentMethods = [];
            })
            .finally(() => {
                this.isLoadingPaymentMethods = false;
            });
    }

    handlePaymentMethodMessage(event) {
        if (event?.data?.type === 'abtPaymentMethodAdded') {
            const paymentMethodId = event.data.paymentMethodId || null;
            this.loadSavedPaymentMethods(paymentMethodId);
        }
    }

    handleSavedPaymentMethodChange(event) {
        this.selectedPaymentMethodId = event.detail.value;
    }

    handleNewCreditCard(event) {
        event.preventDefault();
        if (!this.contactId) {
            alert('Unable to add a card — contact not found.');
            return;
        }
        this.paymentMethodIframeUrl =
            `${ABT_Portal_Url_for_VF_Page}/apex/ABT_AddPaymentMethod?contactId=${this.contactId}&t=${Date.now()}`;
        this.isNewCreditCardModalOpen = true;
    }

    handleCreditCardModalClose() {
        this.isNewCreditCardModalOpen = false;
        this.loadSavedPaymentMethods(this.selectedPaymentMethodId || null);
    }

    handleBpoNumberChange(event) { this.bpoNumber = event.target.value; }

    lookupBpo(poNumberOverride) {
        if (!this.accountId) {
            this.bpoId = null;
            this.bpoRemainingAmount = null;
            this.bpoLookupDone = true;
            return;
        }

        this.isLookingUpBpo = true;
        this.bpoLookupDone = false;

        const poNumber = poNumberOverride !== undefined ? poNumberOverride : this.bpoNumber;

        getActiveBpoForAccount({
            accountId: this.accountId,
            poNumber: poNumber || null
        })
            .then(result => {
                if (result && result.id) {
                    this.bpoId = result.id;
                    this.bpoNumber = result.poNumber || this.bpoNumber;
                    this.bpoRemainingAmount = this.formatCurrency(result.remainingAmount);
                } else {
                    this.bpoId = null;
                    this.bpoRemainingAmount = null;
                }
                this.bpoLookupDone = true;
                this.isLookingUpBpo = false;
            })
            .catch(error => {
                console.error('Error looking up BPO:', error);
                this.bpoId = null;
                this.bpoRemainingAmount = null;
                this.bpoLookupDone = true;
                this.isLookingUpBpo = false;
            });
    }

    formatCurrency(amount) {
        if (amount === null || amount === undefined) {
            return null;
        }
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD'
        }).format(amount);
    }

    handleBillingAddrChange(event) {
        const id = event.target.value;
        this.selectedBillingAddr = id;
        this.billingAddresses = this.billingAddresses.map(a => ({ ...a, isSelected: a.Id === id }));
    }

    handleShippingAddrChange(event) {
        const id = event.target.value;
        this.selectedShippingAddr = id;
        this.shippingAddresses = this.shippingAddresses.map(a => ({ ...a, isSelected: a.Id === id }));
    }

    normalizeInvoiceEmail(value) {
        return (value || '').replace(/\s+/g, '').trim();
    }

    handleInvoiceEmailChange(event) {
        this.invoiceEmail = this.normalizeInvoiceEmail(event.target.value);
    }

    handleDocumentUpload(event) {
        const file = event.target.files[0];
        if (file) this.uploadedDocName = file.name;
    }

    handleRemoveDoc() {
        this.uploadedDocName = '';
        this.uploadedDocData = '';
    }

    persistInvoiceEmailIfChanged() {
        if (!this.contactId || this.invoiceEmail === this._savedInvoiceEmail) {
            return Promise.resolve();
        }
        return updateContactInvoiceEmail({
            contactId: this.contactId,
            invoiceEmail: this.invoiceEmail
        }).then(() => {
            this._savedInvoiceEmail = this.invoiceEmail;
        });
    }

    resolveCheckoutReturnUrl() {
        const path = window.location.pathname || '';
        if (path.includes('my-cart')) {
            return `${PORTAL_BASE}/my-cart?resumeCheckout=1`;
        }
        if (path.includes('new-order')) {
            return `${PORTAL_BASE}/new-order?resumeCheckout=1`;
        }
        return null;
    }

    navigateToAddressForm(type) {
        const params = new URLSearchParams({ type });
        const returnUrl = this.resolveCheckoutReturnUrl();
        if (returnUrl) {
            params.set('returnUrl', returnUrl);
            try {
                sessionStorage.setItem(SESSION_RESUME_CHECKOUT_KEY, '1');
                sessionStorage.setItem(SESSION_RETURN_URL_KEY, returnUrl);
            } catch (e) {
                /* ignore */
            }
        }
        window.location.assign(`${PORTAL_BASE}/addressForm?${params.toString()}`);
    }

    handleNewBillingAddress(event) {
        event.preventDefault();
        this.navigateToAddressForm('Billing');
    }

    handleNewShippingAddress(event) {
        event.preventDefault();
        this.navigateToAddressForm('Shipping');
    }

    // ─── Place Order ────────────────────────────────────────────────────

    handlePlaceOrder() {
        if (this.hasBlockedCartQuotes) {
            // eslint-disable-next-line no-alert
            alert(CHECKOUT_CART_NO_ORDERABLE_LINES_MESSAGE);
            return;
        }

        // Validate based on payment method
        if (this.isPurchaseOrder && !this.poNumber) {
            const inputEl = this.template.querySelector('[data-id="poNumber"]');
            if (inputEl) {
                inputEl.setCustomValidity('PO number is required.');
                inputEl.reportValidity();
            }
            return;
        }
        if (this.isCreditCard && !this.selectedPaymentMethodId) {
            alert('Please select a credit card or add a new one.');
            return;
        }
        if (this.isBpo && !this.hasBpoOnFile && !this.bpoNumber) {
            alert('Please enter a BPO number.');
            return;
        }

        // Resolve PO number per payment method
        let poNumberValue = '';
        if (this.isPurchaseOrder) {
            poNumberValue = this.poNumber;
        } else if (this.isBpo) {
            poNumberValue = this.bpoNumber || '';
        }

        const shippingMethod = this.quoteData.shippingMethod || 'FedEx Express Priority Overnight ($35)';
        const isExpedite = this.quoteData.isExpedite || false;
        const packagingType = this.quoteData.packagingType || 'standard_tubes';

        this.isCheckingOut = true;
        this.checkoutCompleted = false;

        const quoteIds = this.quoteData.quoteIds || [];
        let orderPromise;

        if (quoteIds.length > 0) {
            // Multi-quote cart checkout → single Order
            const cartSequences = this.quoteData.sequences || [];
            const cartSequencesJson = cartSequences.length ? JSON.stringify(cartSequences) : null;
            orderPromise = this.persistInvoiceEmailIfChanged().then(() => placeOrderForCart({
                quoteIdsJson: JSON.stringify(quoteIds),
                shippingMethod: shippingMethod,
                isExpedite: isExpedite,
                packagingType: packagingType,
                poNumber: poNumberValue,
                billingAddressId: this.selectedBillingAddr,
                shippingAddressId: this.selectedShippingAddr,
                paymentMethod: this.checkoutPaymentMethod,
                notes: this.checkoutNotes,
                promoCode: this.promoCode,
                isTaxExempt: this.isTaxExempt,
                isPartialShipment: this.isPartialShipment,
                bpoId: this.bpoId,
                paymentMethodRecordId: this.selectedPaymentMethodId || null,
                sequencesJson: cartSequencesJson
            }));
        } else {
            // Single-quote fallback (new order wizard flow)
            const quoteId = this.quoteData.quoteRequestId || this.quoteData.quoteId;
            if (!quoteId) {
                alert('No quote found. Please start the order process again.');
                this.isCheckingOut = false;
                return;
            }
            const sequences = this.quoteData.sequences || [];
            const sequencesJson = sequences.length ? JSON.stringify(sequences) : null;
            orderPromise = this.persistInvoiceEmailIfChanged().then(() => placeOrder({
                quoteId: quoteId,
                shippingMethod: shippingMethod,
                isExpedite: isExpedite,
                packagingType: packagingType,
                poNumber: poNumberValue,
                billingAddressId: this.selectedBillingAddr,
                shippingAddressId: this.selectedShippingAddr,
                paymentMethod: this.checkoutPaymentMethod,
                notes: this.checkoutNotes,
                promoCode: this.promoCode,
                sequencesJson: sequencesJson,
                isTaxExempt: this.isTaxExempt,
                isPartialShipment: this.isPartialShipment,
                bpoId: this.bpoId,
                paymentMethodRecordId: this.selectedPaymentMethodId || null
            }));
        }

        orderPromise
            .then(orderId => {
                this.checkoutCompleted = true;

                pushDataLayerEvent({ ecommerce: null });
                pushDataLayerEvent({
                    event: 'purchase',
                    ecommerce: {
                        transaction_id: orderId,
                        currency: 'USD',
                        value: parseFloat((this.grandTotal || '$0').replace(/[^0-9.]/g, '')) || 0,
                        items: this.isMultiQuote
                            ? (this.quoteData.quotes || []).map((q) => ({
                                item_id: q.productId || q.productName || '',
                                item_name: q.productName || '',
                                price: parseFloat((q.totalPrice || '$0').replace(/[^0-9.]/g, '')) || 0,
                                quantity: 1
                            }))
                            : [{
                                item_id: this.quoteData.productId || this.quoteData.productName || '',
                                item_name: this.quoteData.productName || '',
                                price: parseFloat((this.totalPrice || '$0').replace(/[^0-9.]/g, '')) || 0,
                                quantity: 1
                            }]
                    }
                });

                try {
                    this.dispatchEvent(new CustomEvent('complete', { detail: { orderId } }));
                } catch (navError) {
                    console.error('Checkout complete handler failed:', navError);
                }
                navigateToOrderConfirmation(orderId);
            })
            .catch(error => {
                console.error('Error placing order:', error);
                this.isCheckingOut = false;
                this.checkoutCompleted = false;
                let msg = (error.body && error.body.message) ? error.body.message : (error.message || 'Unknown error');
                if (isInvalidApexRequestError(error) || !error.body) {
                    msg = CHECKOUT_CUSTOMER_MESSAGE;
                }
                alert(msg);
            });
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('back'));
    }
}