import { LightningElement, track, wire, api } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import { CurrentPageReference } from 'lightning/navigation';
import USER_ID from '@salesforce/user/Id';
import USER_NAME from '@salesforce/schema/User.Name';
import ACCOUNT_NAME from '@salesforce/schema/Account.Name';
import ACCOUNT_CATEGORY from '@salesforce/schema/Account.Category__c';
import ACCOUNT_INDUSTRY from '@salesforce/schema/Account.Industry';
import ACCOUNT_TAX_EXEMPT from '@salesforce/schema/Account.Tax_Exempt__c';
import ACCOUNT_TAX_ID from '@salesforce/schema/Account.Tax_ID_VAT__c';
import ACCOUNT_ALWAYS_ACCEPT from '@salesforce/schema/Account.Always_Accept_Partial__c';
import ACCOUNT_SALES_REP_EMAIL from '@salesforce/schema/Account.Sales_Rep_Email__c';
import ACCOUNT_SALES_REP from '@salesforce/schema/Account.Sales_Rep__c';
import OWNER_CALENDLY from '@salesforce/schema/Account.Owner_s_Calendly_Link__c';
import STAT_SAVED_WITH_GUARANTEE from '@salesforce/schema/Account.Stat_Saved_with_Guarantee__c';
import STAT_ON_TIME_SHIPMENT from '@salesforce/schema/Account.Stat_On_Time_Shipment__c';
import STAT_SEQUENCES_SHIPPED from '@salesforce/schema/Account.Stat_Sequences_Shipped__c';
import STAT_SEQUENCES_REJECTED from '@salesforce/schema/Account.Stat_Sequences_Rejected__c';
import STAT_VISIBILITY_SAVED_WITH_GUARANTEE from '@salesforce/schema/Account.Stat_Visibility_Saved_with_Guarantee__c';
import STAT_VISIBILITY_ON_TIME_SHIPMENT from '@salesforce/schema/Account.Stat_Visibility_On_Time_Shipment__c';
import STAT_VISIBILITY_SEQUENCES_SHIPPED from '@salesforce/schema/Account.Stat_Visibility_Sequences_Shipped__c';
import STAT_VISIBILITY_SEQUENCES_REJECTED from '@salesforce/schema/Account.Stat_Visibility_Sequences_Rejected__c';
import getUserDetailsById from '@salesforce/apex/ABT_Portal_Controller.getUserDetailsById';
import getContactPointAddressesFresh from '@salesforce/apex/ABT_Portal_Controller.getContactPointAddressesFresh';
import getPaymentMethodsByContact from '@salesforce/apex/ABT_Portal_Controller.getPaymentMethodsByContact';
import getPaymentMethodsByContactFresh from '@salesforce/apex/ABT_Portal_Controller.getPaymentMethodsByContactFresh';
import updateContactInvoiceEmail from '@salesforce/apex/ABT_Portal_Controller.updateContactInvoiceEmail';
import deleteContactPointAddress from '@salesforce/apex/ABT_Portal_Controller.deleteContactPointAddress';
import deletePaymentMethod from '@salesforce/apex/ABT_Portal_Controller.deletePaymentMethod';
import ABT_Portal_Url_for_VF_Page from '@salesforce/label/c.ABT_Portal_Url_for_VF_Page';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';

export default class ABT_AccountPageV2Design extends NavigationMixin(LightningElement) {
    @api userId;
    @track isLoading = true;
    @track accountRecordId;
    @track contactRecordId;
    @track userData;
    @track invoiceEmail;
    @track ownerCalendlyLink;
    @track _accountData;
    /** Address form endpoint in Customer Portal (standard myAccountInputAddress page). */
    addressFormBaseUrl = '/AnsaBiotechnologiesCustomerPortal/addressForm';

    _accountLoaded = false;

    // Account info edit modal
    @track isShowAccountModal = false;

    // Addresses
    @track addressTab = 'Shipping';
    @track shippingAddresses = [];
    @track billingAddresses = [];
    @track isAddressesBusy = false;
    @track addressError = '';

    @track isAddressModalOpen = false;
    @track addressModalType = 'Shipping';
    @track addressModalRecordId = null;

    // Payment methods
    @track paymentMethods = [];
    @track isAddPaymentMethodModalOpen = false;
    @track paymentMethodIframeUrl = '';
    @track isPaymentMethodsBusy = false;
    @track paymentMethodError = '';
    wiredPaymentMethodsResult;
    _boundPaymentMessageHandler;
    /*get paymentColumns() {
        return [
            { label: 'CARDHOLDER NAME', fieldName: 'ABT_Card_Holder_Name__c' },
            { label: 'CARD NUMBER', fieldName: 'formattedCardNumber' },
            { label: 'EXPIRATION DATE', fieldName: 'formattedExpiration' },
            { label: 'CREATED DATE', fieldName: 'formattedCreatedDate' },
            {
                type: 'action',
                typeAttributes: {
                    rowActions: [
                        { label: 'Edit', name: 'Edit', iconName: 'utility:edit' },
                        { label: 'Delete', name: 'Delete', iconName: 'utility:delete' }
                    ]
                }
            }
        ];
    }*/

    get isAccountDetailsLoading() {
        return this.isLoading && !this.accountRecordId;
    }

    connectedCallback() {
        this._boundPaymentMessageHandler = this.handlePaymentMethodMessage.bind(this);
        window.addEventListener('message', this._boundPaymentMessageHandler);
    }

    disconnectedCallback() {
        if (this._boundPaymentMessageHandler) {
            window.removeEventListener('message', this._boundPaymentMessageHandler);
        }
    }

    // Wire CurrentPageReference to ensure the component re-evaluates on navigation
    @wire(CurrentPageReference)
    pageRef;

    // Wire the logged-in User record — reliable way to get USER_ID in Experience Cloud
    @wire(getRecord, { recordId: USER_ID, fields: [USER_NAME] })
    wiredUser({ data, error }) {
        console.log('wiredUser fired. data:', data, 'error:', error);
        if (data && !this._accountLoaded) {
            this._accountLoaded = true;
            const resolvedUserId = (this.userId && this.userId !== 'undefined') ? this.userId : USER_ID;
            this.loadUserAndAccount(resolvedUserId);
        }
        if (error) {
            console.error('Error wiring user record:', error);
            if (!this._accountLoaded) {
                this._accountLoaded = true;
                const resolvedUserId = (this.userId && this.userId !== 'undefined') ? this.userId : USER_ID;
                this.loadUserAndAccount(resolvedUserId);
            }
        }
    }

    @wire(getPaymentMethodsByContact, { contactId: '$contactRecordId' })
    wiredPaymentMethods(value) {
        this.wiredPaymentMethodsResult = value;
        const { data, error } = value;
        if (data) {
            this.paymentMethods = this.formatPaymentMethodRows(data);
        } else if (error) {
            console.error('Error loading payment methods:', error);
            this.paymentMethods = [];
        } else if (!this.contactRecordId) {
            this.paymentMethods = [];
        }
    }

    // Wire account fields directly for display
    @wire(getRecord, {
        recordId: '$accountRecordId', fields: [
            OWNER_CALENDLY, ACCOUNT_NAME, ACCOUNT_CATEGORY, ACCOUNT_INDUSTRY,
            ACCOUNT_TAX_EXEMPT, ACCOUNT_TAX_ID, ACCOUNT_ALWAYS_ACCEPT,
            ACCOUNT_SALES_REP_EMAIL, ACCOUNT_SALES_REP,
            STAT_SAVED_WITH_GUARANTEE, STAT_ON_TIME_SHIPMENT,
            STAT_SEQUENCES_SHIPPED, STAT_SEQUENCES_REJECTED,
            STAT_VISIBILITY_SAVED_WITH_GUARANTEE, STAT_VISIBILITY_ON_TIME_SHIPMENT,
            STAT_VISIBILITY_SEQUENCES_SHIPPED, STAT_VISIBILITY_SEQUENCES_REJECTED
        ]
    })
    wiredAccount({ data }) {
        if (data) {
            this.ownerCalendlyLink = data.fields.Owner_s_Calendly_Link__c?.value;
            this._accountData = data.fields;
        }
    }

    // Account field getters
    get accountName() { return this._accountData?.Name?.value || '—'; }
    get accountCategory() { return this._accountData?.Category__c?.value || '—'; }
    get accountIndustry() { return this._accountData?.Industry?.value || '—'; }
    get accountTaxExempt() { return this._accountData?.Tax_Exempt__c?.value ? 'Yes' : 'No'; }
    get accountTaxId() { return this._accountData?.Tax_ID_VAT__c?.value || '—'; }
    get accountAlwaysAcceptPartial() { return this._accountData?.Always_Accept_Partial__c?.value ? 'Yes' : 'No'; }
    get accountSalesRepEmail() { return this._accountData?.Sales_Rep_Email__c?.value || '—'; }
    get accountSalesRep() { return this._accountData?.Sales_Rep__c?.value || '—'; }

    get showSavedWithGuarantee() {
        return this._accountData?.Stat_Visibility_Saved_with_Guarantee__c?.value === true;
    }

    get showOnTimeShipment() {
        return this._accountData?.Stat_Visibility_On_Time_Shipment__c?.value === true;
    }

    get showSequencesShipped() {
        return this._accountData?.Stat_Visibility_Sequences_Shipped__c?.value === true;
    }

    get showSequencesRejected() {
        return this._accountData?.Stat_Visibility_Sequences_Rejected__c?.value === true;
    }

    get hasVisibleSummaryTiles() {
        return this.showSavedWithGuarantee
            || this.showOnTimeShipment
            || this.showSequencesShipped
            || this.showSequencesRejected;
    }

    get savedAmount() {
        return this.formatCurrencyCompact(this._accountData?.Stat_Saved_with_Guarantee__c?.value);
    }

    get savedAmountSubtext() {
        const amount = this.formatCurrencyFull(this._accountData?.Stat_Saved_with_Guarantee__c?.value);
        const name = this.accountName !== '—' ? this.accountName : 'Your organization';
        return `${name} has saved ${amount}.`;
    }

    get onTimePercent() {
        return this.formatPercent(this._accountData?.Stat_On_Time_Shipment__c?.value);
    }

    get onTimeSubtext() {
        return "Ansa's On-time Guarantee assures your sequences are shipped on time, or your order is free.";
    }

    get sequencesShippedPercent() {
        return this.formatPercent(this._accountData?.Stat_Sequences_Shipped__c?.value);
    }

    get sequencesShippedSubtext() {
        return 'Total % of sequences ordered that have shipped out.';
    }

    get sequencesRejectedPercent() {
        return this.formatPercent(this._accountData?.Stat_Sequences_Rejected__c?.value);
    }

    get sequencesRejectedSubtext() {
        return 'Ansa rejects fewer sequences, than any other DNA synthesis provider.';
    }

    formatPercent(value) {
        if (value == null || value === '') {
            return '—';
        }
        const num = Number(value);
        if (Number.isNaN(num)) {
            return '—';
        }
        const pct = Math.abs(num) <= 1 ? num * 100 : num;
        return `${Math.round(pct)}%`;
    }

    formatCurrencyCompact(value) {
        if (value == null || value === '') {
            return '—';
        }
        const num = Number(value);
        if (Number.isNaN(num)) {
            return '—';
        }
        if (num >= 1000) {
            return `${new Intl.NumberFormat('en-US', {
                style: 'currency',
                currency: 'USD',
                notation: 'compact',
                maximumFractionDigits: 1
            }).format(num)}+`;
        }
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD',
            maximumFractionDigits: 0
        }).format(num);
    }

    formatCurrencyFull(value) {
        if (value == null || value === '') {
            return '—';
        }
        const num = Number(value);
        if (Number.isNaN(num)) {
            return '—';
        }
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD',
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        }).format(num);
    }

    loadUserAndAccount(resolvedUserId) {
        console.log('loadUserAndAccount called with:', resolvedUserId);
        if (!resolvedUserId) {
            console.error('No userId available — cannot load account.');
            this.isLoading = false;
            return;
        }

        getUserDetailsById({ userId: resolvedUserId })
            .then((result) => {
                console.log('getUserDetailsById result:', result);
                this.userData = result;
                this.accountRecordId = result ? result.AccountId : '001VH000011tZdZYAU';
                this.contactRecordId = result ? result.ContactId : null;
                this.invoiceEmail = result.Contact?.Invoice_Email__c || '';
                this.loadAddresses();
                this.isLoading = false;
            })
            .catch((err) => {
                console.error('Error loading user/account:', err);
                this.isLoading = false;
            });
    }

    loadAddresses() {
        if (!this.accountRecordId) {
            return Promise.resolve();
        }
        this.isAddressesBusy = true;
        return Promise.all([
            getContactPointAddressesFresh({ accountId: this.accountRecordId, addressType: 'Shipping' }),
            getContactPointAddressesFresh({ accountId: this.accountRecordId, addressType: 'Billing' })
        ])
            .then(([shipping, billing]) => {
                this.shippingAddresses = shipping || [];
                this.billingAddresses = billing || [];
            })
            .catch((err) => {
                console.error('Error loading addresses:', err);
                this.addressError = this.getApexErrorMessage(err);
            })
            .finally(() => {
                this.isAddressesBusy = false;
            });
    }

    formatPaymentMethodRows(rows) {
        return (rows || []).map((row) => {
            const created = row.CreatedDate ? new Date(row.CreatedDate) : null;
            const expVal = row.ABT_Expiration_Date__c != null ? row.ABT_Expiration_Date__c : null;
            return {
                ...row,
                formattedCardNumber: row.ABT_Card_Number__c || '—',
                formattedExpiration: expVal != null ? this.formatExpiration(expVal) : '—',
                formattedCreatedDate: created ? this.formatDate(created) : '—'
            };
        });
    }

    reloadPaymentMethods() {
        if (!this.contactRecordId) {
            this.paymentMethods = [];
            return Promise.resolve();
        }
        this.isPaymentMethodsBusy = true;
        return getPaymentMethodsByContactFresh({ contactId: this.contactRecordId })
            .then((rows) => {
                this.paymentMethods = this.formatPaymentMethodRows(rows);
            })
            .catch((err) => {
                console.error('Error loading payment methods:', err);
                this.paymentMethodError = this.getApexErrorMessage(err);
                this.paymentMethods = [];
            })
            .finally(() => {
                this.isPaymentMethodsBusy = false;
            });
    }

    refreshPaymentMethods() {
        return this.reloadPaymentMethods();
    }

    getApexErrorMessage(error) {
        if (!error) {
            return 'An unexpected error occurred.';
        }
        if (Array.isArray(error.body)) {
            return error.body.map((e) => e.message).join(' ');
        }
        if (error.body?.message) {
            return error.body.message;
        }
        return error.message || 'An unexpected error occurred.';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    handlePaymentMethodMessage(event) {
        if (event?.data?.type === 'abtPaymentMethodAdded') {
            this.reloadPaymentMethods();
        }
    }

    formatDate(val) {
        if (!val) return '—';
        const d = val instanceof Date ? val : new Date(val);
        if (isNaN(d.getTime())) return '—';
        const m = d.getMonth() + 1;
        const day = d.getDate();
        const y = d.getFullYear();
        return `${String(m).padStart(2, '0')}/${String(day).padStart(2, '0')}/${String(y).slice(-2)}`;
    }

    formatExpiration(val) {
        if (val == null) return '—';
        const d = val instanceof Date ? val : new Date(val);
        if (isNaN(d.getTime())) return '—';
        const m = d.getMonth() + 1;
        const y = d.getFullYear();
        return `${String(m).padStart(2, '0')}/${String(y).slice(-2)}`;
    }

    get hasPaymentMethods() {
        return this.paymentMethods && this.paymentMethods.length > 0;
    }

    openPaymentMethodModal() {
        if (!this.contactRecordId) {
            return;
        }
        this.paymentMethodIframeUrl =
            `${ABT_Portal_Url_for_VF_Page}/apex/ABT_AddPaymentMethod?contactId=${this.contactRecordId}&t=${Date.now()}`;
        this.isAddPaymentMethodModalOpen = true;
    }

    handleAddPaymentMethod(event) {
        event.preventDefault();
        this.openPaymentMethodModal();
    }

    handlePaymentMethodSaveAndClose() {
        this.isAddPaymentMethodModalOpen = false;
        this.paymentMethodError = '';
        this.reloadPaymentMethods();
    }

    handlePaymentEdit(event) {
        event.preventDefault();
        this.openPaymentMethodModal();
    }

    handlePaymentDelete(event) {
        const id = event.currentTarget.dataset.id;
        if (!id || !confirm('Are you sure you want to delete this payment method?')) {
            return;
        }

        this.isPaymentMethodsBusy = true;
        this.paymentMethodError = '';
        deletePaymentMethod({ paymentMethodId: id })
            .then(() => {
                this.showToast('Success', 'Payment method deleted.', 'success');
                return this.refreshPaymentMethods();
            })
            .catch((err) => {
                const message = this.getApexErrorMessage(err);
                this.paymentMethodError = message;
                this.showToast('Error', message, 'error');
                console.error('Error deleting payment method:', err);
            })
            .finally(() => {
                this.isPaymentMethodsBusy = false;
            });
    }

    handleAddressEdit(event) {
        const addressId = event.currentTarget.dataset.id;
        this.addressModalType = this.addressTab;
        this.addressModalRecordId = addressId;
        this.isAddressModalOpen = true;
    }

    handleAddressDelete(event) {
        const addressId = event.currentTarget.dataset.id;
        if (!addressId || !confirm('Are you sure you want to delete this address?')) {
            return;
        }

        this.isAddressesBusy = true;
        this.addressError = '';
        deleteContactPointAddress({ addressId })
            .then(() => {
                this.shippingAddresses = (this.shippingAddresses || []).filter((addr) => addr.Id !== addressId);
                this.billingAddresses = (this.billingAddresses || []).filter((addr) => addr.Id !== addressId);
                this.showToast('Success', 'Address deleted.', 'success');
                return this.loadAddresses();
            })
            .catch((err) => {
                const message = this.getApexErrorMessage(err);
                this.addressError = message;
                this.showToast('Error', message, 'error');
                console.error('Error deleting address:', err);
            })
            .finally(() => {
                this.isAddressesBusy = false;
            });
    }

    // ——— Account Information ———
    showAccountModal() {
        this.isShowAccountModal = true;
    }

    hideAccountModal() {
        if (this.contactRecordId && this.invoiceEmail !== this.userData?.Contact?.Invoice_Email__c) {
            updateContactInvoiceEmail({ contactId: this.contactRecordId, invoiceEmail: this.invoiceEmail })
                .then(() => {
                    if (this.userData?.Contact) this.userData.Contact.Invoice_Email__c = this.invoiceEmail;
                })
                .catch((e) => console.error('Error updating invoice email:', e));
        }
        this.isShowAccountModal = false;
    }

    handleInvoiceEmailChange(event) {
        this.invoiceEmail = event.target.value;
    }

    openCalendly() {
        if (this.ownerCalendlyLink) window.open(this.ownerCalendlyLink, '_blank');
    }

    // ——— Addresses ———
    get activeAddressTab() {
        return this.addressTab;
    }

    get currentAddressList() {
        const list = this.addressTab === 'Shipping' ? this.shippingAddresses : this.billingAddresses;
        return (list || []).map((addr) => {
            const a = addr.Address || {};
            const line2 = [a.city, a.state, a.postalCode].filter(Boolean).join(', ');
            const displayParts = [a.street || '', line2, a.country || ''].filter(Boolean);
            return {
                ...addr,
                isDefault: !!addr.IsDefault,
                line1: a.street || '',
                line2,
                country: a.country || '',
                displayAddress: displayParts.join(', ')
            };
        });
    }

    get hasCurrentAddresses() {
        return this.currentAddressList && this.currentAddressList.length > 0;
    }

    get defaultAddressId() {
        const list = this.addressTab === 'Shipping' ? this.shippingAddresses : this.billingAddresses;
        const defaultAddr = (list || []).find((addr) => addr.IsDefault);
        return defaultAddr ? defaultAddr.Id : null;
    }

    setAddressTabShipping() {
        this.addressTab = 'Shipping';
    }

    setAddressTabBilling() {
        this.addressTab = 'Billing';
    }

    get isShippingActive() {
        return this.addressTab === 'Shipping';
    }

    get isBillingActive() {
        return this.addressTab === 'Billing';
    }

    get shippingTabClass() {
        return this.addressTab === 'Shipping'
            ? 'address-tab address-tab_active'
            : 'address-tab';
    }

    get billingTabClass() {
        return this.addressTab === 'Billing'
            ? 'address-tab address-tab_active'
            : 'address-tab';
    }

    buildAddressFormUrl(addressType, addressId) {
        const params = new URLSearchParams();
        params.set('type', addressType);
        params.set('addressType', addressType);
        params.set('c__type', addressType);
        params.set('c__addressType', addressType);

        if (addressId) {
            params.set('recordId', addressId);
            params.set('addressId', addressId);
            params.set('c__recordId', addressId);
            params.set('c__addressId', addressId);
        }

        return `${this.addressFormBaseUrl}?${params.toString()}`;
    }

    handleAddShippingNavigation(event) {
        console.log('accountRecordId at click time:', this.accountRecordId);
        event.preventDefault();
        this.addressModalType = 'Shipping';
        this.addressModalRecordId = null;
        this.isAddressModalOpen = true;
    }

    handleAddBillingNavigation(event) {
        event.preventDefault();
        this.addressModalType = 'Billing';
        this.addressModalRecordId = null;
        this.isAddressModalOpen = true;
    }

    closeAddressModal() {
        this.isAddressModalOpen = false;
        this.addressModalRecordId = null;
    }

    handleAddressModalSuccess(event) {
        this.isAddressModalOpen = false;
        this.addressModalRecordId = null;
        this.showToast('Success', 'Address saved.', 'success');
        this.loadAddresses();
    }

    get addressModalTitle() {
        return `${this.addressModalType} Address`;
    }


    // ——— Payment methods (display only in this container; add/delete can be separate flows) ———
}