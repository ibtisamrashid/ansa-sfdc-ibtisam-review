import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getUserDetailsById from '@salesforce/apex/ABT_Portal_Controller.getUserDetailsById';
import getContactPointAddresses from '@salesforce/apex/ABT_Portal_Controller.getContactPointAddresses';
import placeOrder from '@salesforce/apex/ABT_Portal_Controller.placeOrder';
import { PORTAL_BASE, navigateToOrderConfirmation } from 'c/abtQuoteUrls';
import userId from '@salesforce/user/Id';

const ADDRESS_FORM_PAGE_NAME = 'Address_Form';
const SESSION_RESUME_CHECKOUT_KEY = 'abt_resumeCheckout';
const SESSION_RETURN_URL_KEY = 'abt_addressFormReturnUrl';

export default class AbtCheckout extends NavigationMixin(LightningElement) {
    @api quoteData = {};

    @track isLoadingCheckout = true;
    @track isCheckingOut = false;

    @track isAddressModalOpen = false;
@track addressModalType = 'Shipping';
@track addressModalRecordId = null;

    // User info
    currentUserId = userId;
    @track currentUserName = '';

    // Checkout form fields
    @track checkoutPaymentMethod = 'purchase_order';
    @track poNumber = '';
    @track isTaxExempt = false;
    @track isPartialShipment = true;
    @track checkoutNotes = '';
    @track promoCode = '';

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
    }

    // ─── Load user details + addresses ──────────────────────────────────

    loadCheckoutData() {
        this.isLoadingCheckout = true;
        const accountId = this.quoteData.accountId || '';

        getUserDetailsById({ userId: this.currentUserId })
            .then(user => {
                this.currentUserName = user.Name || user.name || '';
                this.incoTerms = user.Account?.IncoTerms__c || 'FCA';
                return Promise.all([
                    getContactPointAddresses({ accountId: accountId, addressType: 'Billing' }),
                    getContactPointAddresses({ accountId: accountId, addressType: 'Shipping' })
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
            })
            .catch(error => {
                console.error('Error loading checkout data:', error);
                this.isLoadingCheckout = false;
            });
    }

    // ─── Computed getters from quoteData ────────────────────────────────

    get quoteId() { return this.quoteData.quoteId || ''; }
    get productName() { return this.quoteData.productName || ''; }
    get projectName() { return this.quoteData.projectName || ''; }

    get sequenceCount() {
        return (this.quoteData.sequences || []).length;
    }

    get groupCount() {
        const groups = new Set((this.quoteData.sequences || []).map(s => s.group || '1'));
        return groups.size;
    }

    get shipDate() { return 'Pending'; }

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

    get packaging() {
        return this.quoteData.packaging || '$0.00';
    }

    get grandTotal() {
        if (this.quoteData.grandTotal) {
            return this.quoteData.grandTotal;
        }
        const sub = parseFloat((this.subtotal || '$0').replace(/[^0-9.]/g, '')) || 0;
        const ship = parseFloat((this.shipping || '$0').replace(/[^0-9.]/g, '')) || 0;
        const pack = parseFloat((this.packaging || '$0').replace(/[^0-9.]/g, '')) || 0;
        return '$' + (sub + ship + pack).toFixed(2);
    }

    get checkoutShippingLabel() {
        const shippingMap = {
            'fedex_priority': 'FedEx Priority Express Overnight',
            'fedex_standard': 'FedEx Standard Overnight',
            'fedex_2day': 'FedEx 2Day',
        };
        return shippingMap[this.quoteData.shippingMethod]
            || this.quoteData.shippingMethod
            || 'FedEx Priority Express Overnight';
    }

    get paymentMethodOptions() {
        return [
            { label: 'Purchase Order', value: 'purchase_order' },
            { label: 'Credit Card', value: 'credit_card' },
            { label: 'Wire Transfer', value: 'wire_transfer' },
        ];
    }

    get hasBillingAddresses() { return this.billingAddresses && this.billingAddresses.length > 0; }
    get hasShippingAddresses() { return this.shippingAddresses && this.shippingAddresses.length > 0; }

    // ─── Form handlers ──────────────────────────────────────────────────

    handlePaymentMethodChange(event) { this.checkoutPaymentMethod = event.detail.value; }
    handlePoNumberChange(event) { this.poNumber = event.target.value; }
    handleTaxExemptChange(event) { this.isTaxExempt = event.target.checked; }
    handlePartialShipChange(event) { this.isPartialShipment = event.target.checked; }
    handleNotesChange(event) { this.checkoutNotes = event.target.value; }
    handlePromoChange(event) { this.promoCode = event.target.value; }
    handleLearnMore(event) { event.preventDefault(); }

    handleNewBillingAddress(event) {
        event.preventDefault();
        this.addressModalType = 'Billing';
        this.addressModalRecordId = null;
        this.isAddressModalOpen = true;
    }

    handleNewShippingAddress(event) {
        event.preventDefault();
        this.addressModalType = 'Shipping';
        this.addressModalRecordId = null;
        this.isAddressModalOpen = true;
    }

    closeAddressModal() {
        this.isAddressModalOpen = false;
    }

    handleAddressModalSuccess() {
        this.isAddressModalOpen = false;
        this.loadCheckoutData();
    }

    get checkoutAccountId() {
        return this.quoteData?.accountId || '';
    }

    handleDocumentUpload(event) {
        const file = event.target.files[0];
        if (file) this.uploadedDocName = file.name;
    }

    handleRemoveDoc() {
        this.uploadedDocName = '';
        this.uploadedDocData = '';
    }

    

    // ─── Place Order ────────────────────────────────────────────────────

    handlePlaceOrder() {
        if (!this.poNumber) {
            const inputEl = this.template.querySelector('lightning-input[type="text"]');
            if (inputEl) {
                inputEl.setCustomValidity('PO number is required.');
                inputEl.reportValidity();
            }
            return;
        }

        if (!this.quoteId) {
            alert('No quote found. Please start the order process again.');
            return;
        }

        // Salesforce IDs are always 15 or 18 characters. Anything else means wrong data reached here.
        if (this.quoteId.length !== 15 && this.quoteId.length !== 18) {
            alert('Invalid quote ID (' + this.quoteId + '). Please go back to the cart and try again.');
            return;
        }

        if (!this.selectedBillingAddr) {
            alert('Please select a billing address before placing your order.');
            return;
        }

        if (!this.selectedShippingAddr) {
            alert('Please select a shipping address before placing your order.');
            return;
        }

        console.log('[abt_Checkout] Placing order - quoteId:', this.quoteId, '| accountId:', this.quoteData.accountId);

        const params = {
            quoteId: this.quoteId,
            shippingMethod: this.quoteData.shippingMethod || 'FedEx Priority Overnight One Rate ($35)',
            isExpedite: !!this.quoteData.isExpedite,
            packagingType: this.quoteData.packagingType || 'standard_tubes',
            poNumber: this.poNumber,
            billingAddressId: this.selectedBillingAddr,
            shippingAddressId: this.selectedShippingAddr,
            paymentMethod: this.checkoutPaymentMethod,
            notes: this.checkoutNotes,
            promoCode: this.promoCode,
            sequencesJson: null,
            isTaxExempt: this.isTaxExempt,
            isPartialShipment: this.isPartialShipment
        };
        this.isCheckingOut = true;

        placeOrder(params)
        .then(orderId => {
            this.isCheckingOut = false;
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
            const msg = error?.body?.message || error?.message || 'An unexpected error occurred. Please try again.';
            alert(msg);
        });
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('back'));
    }
}