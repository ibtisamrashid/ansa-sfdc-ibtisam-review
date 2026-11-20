import { LightningElement, api, track, wire } from 'lwc';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import getContactPointAddressById from '@salesforce/apex/ABT_AddressForm_Controller.getContactPointAddressById';
import saveContactPointAddress from '@salesforce/apex/ABT_AddressForm_Controller.saveContactPointAddress';
import searchAddress from '@salesforce/apex/ABT_AddressAutoCompleteController.searchAddress';
import CONTACT_POINT_ADDRESS from '@salesforce/schema/ContactPointAddress';
import COUNTRY_CODE from '@salesforce/schema/ContactPointAddress.CountryCode';
import STATE_CODE from '@salesforce/schema/ContactPointAddress.StateCode';
import USER_ID from '@salesforce/user/Id';
import getUserDetailsById from '@salesforce/apex/ABT_Portal_Controller.getUserDetailsById';

const ADDRESS_TYPE_OPTIONS = [
    { label: 'Shipping Address', value: 'Shipping' },
    { label: 'Billing Address', value: 'Billing' }
];

const PHONE_COUNTRY_CODE_OPTIONS = [
    { label: '+1', value: '+1' },
    { label: '+44', value: '+44' },
    { label: '+61', value: '+61' },
    { label: '+49', value: '+49' },
    { label: '+33', value: '+33' },
    { label: '+81', value: '+81' },
    { label: '+86', value: '+86' },
    { label: '+91', value: '+91' }
];

export default class AbtAddressForm extends LightningElement {
    _accountId;
_hasResolvedOwnAccountId = false;

@api
get accountId() {
    return this._accountId;
}

set accountId(value) {
    this._accountId = value;
    if (!value && !this._hasResolvedOwnAccountId) {
        this.resolveOwnAccountId();
    }
}



resolveOwnAccountId() {
    this._hasResolvedOwnAccountId = true;
    getUserDetailsById({ userId: USER_ID })
    .then((result) => {
        this._accountId = result?.AccountId || null; 
    })
        .catch((error) => {
            this.errorMessage = this.extractErrorMessage(error);
        });
}

    @api recordId;
    @api inModal = false;
    @api showDifferentAddressTypes;

    _addressType = 'Shipping';
    @track selectedAddressType = 'Shipping';
    @track firstName = '';
    @track lastName = '';
    @track companyName = '';
    @track street = '';
    @track addressLine2 = '';
    @track city = '';
    @track stateCode = '';
    @track postalCode = '';
    @track countryCode = 'US';
    @track phoneCountryCode = '+1';
    @track phoneNumber = '';
    @track isDefault = false;
    @track isSaving = false;
    @track isLoading = false;
    @track errorMessage = '';

    // --- NEW: LocationIQ address suggestions state ---
    @track suggestions = [];
    addressSearchTimeout;

    recordTypeId;
    countryPicklistData;
    statePicklistData;
    _pendingStateLabel = null;

    @api
    get addressType() {
        return this._addressType;
    }
    set addressType(value) {
        this._addressType = value || 'Shipping';
        this.selectedAddressType = this.normalizeAddressTypeChoice(this._addressType);
    }

    get isEditMode() {
        return !!this.recordId;
    }

    get formTitle() {
        return this.isEditMode ? 'Edit Address' : 'New Address';
    }

    get addressTypeOptions() {
        return ADDRESS_TYPE_OPTIONS;
    }

    get showAddressTypeSelector() {
        const enabled = this.showDifferentAddressTypes !== false;
        return enabled && !this.isEditMode;
    }

    get resolvedAddressType() {
        const raw = this.selectedAddressType || this._addressType || 'Shipping';
        return /bill/i.test(raw) ? 'Billing Address' : 'Shipping Address';
    }

    get containerClass() {
        return this.inModal
            ? 'address-form-container address-form-container_modal'
            : 'address-form-container';
    }

    get showCardHeader() {
        return !this.inModal;
    }

    get saveButtonLabel() {
        return this.isSaving ? 'Saving...' : 'Save';
    }

    get isFormDisabled() {
        return this.isSaving || this.isLoading || !this.accountId;
    }

    get phoneCountryCodeOptions() {
        return PHONE_COUNTRY_CODE_OPTIONS;
    }

    get countryOptions() {
        return this.countryPicklistData?.values || [];
    }

    get stateOptions() {
        if (!this.statePicklistData?.values) {
            return [];
        }
        if (!this.countryCode || !this.statePicklistData.controllerValues) {
            return this.statePicklistData.values;
        }
        const controllerKey = this.statePicklistData.controllerValues[this.countryCode];
        if (controllerKey === undefined) {
            return this.statePicklistData.values;
        }
        return this.statePicklistData.values.filter((option) =>
            option.validFor.includes(controllerKey)
        );
    }

    get selectedCountryLabel() {
        const match = this.countryOptions.find((option) => option.value === this.countryCode);
        return match ? match.label : this.countryCode;
    }

    get selectedStateLabel() {
        const match = this.stateOptions.find((option) => option.value === this.stateCode);
        return match ? match.label : this.stateCode;
    }

    // --- NEW: controls the suggestions dropdown visibility ---
    get showSuggestions() {
        return this.suggestions && this.suggestions.length > 0;
    }

    @wire(getObjectInfo, { objectApiName: CONTACT_POINT_ADDRESS })
    wiredObjectInfo({ data }) {
        if (data) {
            this.recordTypeId = data.defaultRecordTypeId;
        }
    }

    @wire(getPicklistValues, {
        recordTypeId: '$recordTypeId',
        fieldApiName: COUNTRY_CODE
    })
    wiredCountryPicklist({ data }) {
        if (data) {
            this.countryPicklistData = data;
        }
    }

    @wire(getPicklistValues, {
        recordTypeId: '$recordTypeId',
        fieldApiName: STATE_CODE
    })
    wiredStatePicklist({ data }) {
        if (data) {
            this.statePicklistData = data;
        }
    }

    connectedCallback() {
        if (this.recordId) {
            this.loadAddressForEdit();
        }
        if (!this._accountId) {
            this.resolveOwnAccountId();
        }
    }

    renderedCallback() {
        if (this._pendingStateLabel && this.stateOptions.length) {
            const code = this.mapStateLabelToCode(this._pendingStateLabel);
            if (code) {
                this.stateCode = code;
                this._pendingStateLabel = null;
            }
        }
    }

    loadAddressForEdit() {
        this.isLoading = true;
        getContactPointAddressById({ addressId: this.recordId })
            .then((record) => {
                if (!record) {
                    return;
                }
                this.firstName = record.AddressFirstName || '';
                this.lastName = record.AddressLastName || '';
                this.companyName = record.CompanyName || '';
                this.city = record.City || '';
                this.postalCode = record.PostalCode || '';
                this.isDefault = !!record.IsDefault;
                this.countryCode = record.CountryCode || this.mapCountryLabelToCode(record.Country) || 'US';
                if (record.StateCode) {
                    this.stateCode = record.StateCode;
                } else if (record.State) {
                    this._pendingStateLabel = record.State;
                    this.stateCode = this.mapStateLabelToCode(record.State) || '';
                } else {
                    this.stateCode = '';
                }
                this.parseStreetLines(record.Street || '');
                this.parsePhoneNumber(record.PhoneNumber || '');
                this._addressType = /bill/i.test(record.AddressType || '') ? 'Billing' : 'Shipping';
                this.selectedAddressType = this._addressType;
            })
            .catch((error) => {
                this.errorMessage = this.extractErrorMessage(error);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    mapCountryLabelToCode(label) {
        if (!label || !this.countryOptions.length) {
            return null;
        }
        const match = this.countryOptions.find(
            (option) => option.label === label || option.value === label
        );
        return match ? match.value : null;
    }

    mapStateLabelToCode(label) {
        if (!label || !this.stateOptions.length) {
            return null;
        }
        const match = this.stateOptions.find(
            (option) => option.label === label || option.value === label
        );
        return match ? match.value : null;
    }

    parseStreetLines(streetValue) {
        const parts = String(streetValue || '').split('\n');
        this.street = parts[0] || '';
        this.addressLine2 = parts.length > 1 ? parts.slice(1).join('\n') : '';
    }

    parsePhoneNumber(rawPhone) {
        const phone = String(rawPhone || '').trim();
        if (!phone) {
            return;
        }
        const match = phone.match(/^(\+\d{1,3})\s*(.*)$/);
        if (match) {
            this.phoneCountryCode = match[1];
            this.phoneNumber = match[2];
            return;
        }
        this.phoneNumber = phone;
    }

    normalizeAddressTypeChoice(value) {
        return /bill/i.test(String(value || '')) ? 'Billing' : 'Shipping';
    }

    handleAddressTypeChange(event) {
        this.selectedAddressType = event.detail.value;
        this.errorMessage = '';
    }

    handleFieldChange(event) {
        const field = event.target.dataset.field;
        const value = event.detail?.value ?? event.target.value;
        if (!field) {
            return;
        }
        this[field] = value;
        this.errorMessage = '';
        if (field === 'countryCode') {
            this.stateCode = '';
        }
    }

    // --- NEW: handles typing in Address 1, debounces, calls LocationIQ ---
    handleStreetInput(event) {
        // keep existing behavior: this still updates this.street
        this.handleFieldChange(event);

        const query = event.target.value;
        window.clearTimeout(this.addressSearchTimeout);

        if (!query || query.length < 3) {
            this.suggestions = [];
            return;
        }

        this.addressSearchTimeout = window.setTimeout(() => {
            searchAddress({ query })
                .then((results) => {
                    this.suggestions = results || [];
                })
                .catch(() => {
                    this.suggestions = [];
                });
        }, 400);
    }

    // --- NEW: handles clicking a suggestion from the dropdown ---
    handleSuggestionClick(event) {
        const index = event.currentTarget.dataset.index;
        const suggestion = this.suggestions[index];
        if (!suggestion) {
            return;
        }
        console.log(JSON.stringify(suggestion));

        const composedStreet = [suggestion.houseNumber, suggestion.road].filter(Boolean).join(' ');
        this.street = composedStreet || this.street;
            this.city = suggestion.city || this.city;
        this.postalCode = suggestion.postcode || this.postalCode;

        const countryCode =
            this.mapCountryLabelToCode(suggestion.country) ||
            (suggestion.countryCode ? suggestion.countryCode.toUpperCase() : null);
        if (countryCode) {
            this.countryCode = countryCode;
        }

        const stateCode = this.mapStateLabelToCode(suggestion.state);
        if (stateCode) {
            this.stateCode = stateCode;
        } else if (suggestion.state) {
            this._pendingStateLabel = suggestion.state;
        }

        this.suggestions = [];
        this.errorMessage = '';
    }

    handleDefaultChange(event) {
        this.isDefault = event.target.checked;
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    validateForm() {
        const inputs = this.template.querySelectorAll(
            'lightning-input, lightning-combobox'
        );
        let valid = true;
        inputs.forEach((input) => {
            if (!input.reportValidity()) {
                valid = false;
            }
        });
        if (!this.firstName?.trim() || !this.lastName?.trim()) {
            valid = false;
        }
        if (!this.countryCode || !this.street?.trim() || !this.city?.trim() || !this.stateCode || !this.postalCode?.trim()) {
            valid = false;
            if (!this.errorMessage) {
                this.errorMessage = 'Please complete all required address fields.';
            }
        }
        if (!this.phoneNumber?.trim()) {
            valid = false;
            if (!this.errorMessage) {
                this.errorMessage = 'Phone number is required.';
            }
        }
        return valid;
    }

    buildStreetValue() {
        const line1 = (this.street || '').trim();
        const line2 = (this.addressLine2 || '').trim();
        if (line1 && line2) {
            return `${line1}\n${line2}`;
        }
        return line1 || line2;
    }

    buildPhoneValue() {
        const digits = (this.phoneNumber || '').trim();
        if (!digits) {
            return null;
        }
        return `${this.phoneCountryCode || '+1'} ${digits}`.trim();
    }

    handleSave() {
        this.errorMessage = '';
        if (!this.validateForm()) {
            return;
        }

        this.isSaving = true;
        const payload = {
            recordId: this.recordId || null,
            parentId: this.accountId,
            addressType: this.resolvedAddressType,
            firstName: this.firstName?.trim(),
            lastName: this.lastName?.trim(),
            companyName: this.companyName?.trim() || null,
            street: this.buildStreetValue(),
            city: this.city?.trim(),
            state: this.selectedStateLabel,
            stateCode: this.stateCode,
            postalCode: this.postalCode?.trim(),
            country: this.selectedCountryLabel,
            countryCode: this.countryCode,
            phoneNumber: this.buildPhoneValue(),
            isDefault: this.isDefault
        };

        saveContactPointAddress({ addressJson: JSON.stringify(payload) })
            .then((savedId) => {
                this.isSaving = false;
                this.dispatchEvent(
                    new CustomEvent('success', {
                        detail: {
                            id: savedId,
                            addressType: this.isEditMode
                                ? this._addressType
                                : this.selectedAddressType || this._addressType
                        }
                    })
                );
            })
            .catch((error) => {
                this.isSaving = false;
                this.errorMessage = this.extractErrorMessage(error);
            });
    }

    extractErrorMessage(error) {
        if (!error) {
            return 'Unable to save address. Please try again.';
        }
        if (Array.isArray(error.body)) {
            return error.body.map((e) => e.message).join(' ');
        }
        if (error.body?.message) {
            return error.body.message;
        }
        return error.message || 'Unable to save address. Please try again.';
    }
}