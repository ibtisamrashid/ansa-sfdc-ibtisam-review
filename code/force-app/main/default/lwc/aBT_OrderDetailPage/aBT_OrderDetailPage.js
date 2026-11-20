import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { getRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import USER_ID from '@salesforce/user/Id';
import USER_NAME_FIELD from '@salesforce/schema/User.Name';
import ORDER_PRODUCT_FIELD from '@salesforce/schema/Order.Order_Product__c';
import REQUESTED_PACKAGING_FIELD from '@salesforce/schema/Order.Requested_Packaging__c';
import { ensureGoogleAdsTrackingLoaded } from 'c/abtGoogleAdsTracking';

import getOrderPortalDetail from '@salesforce/apex/ABT_Portal_Controller.getOrderPortalDetail';
import { formatProductName } from 'c/abtProductNameUtils';
import {
    sequenceNameFromOrderItem,
    normalizedSequenceClassificationFromOrderItem,
    buildOrderItemCsvRow
} from 'c/abtOrderSequenceUtils';
import updateOrderAcceptPartialShipment from '@salesforce/apex/ABT_Portal_Controller.updateOrderAcceptPartialShipment';
import updateOrderTaxExempt from '@salesforce/apex/ABT_Portal_Controller.updateOrderTaxExempt';
import getOrderItemRelatedList from '@salesforce/apex/ABT_Portal_Controller.getOrderItemRelatedList';
import getOrderItemGlycerolAddons from '@salesforce/apex/ABT_Portal_Controller.getOrderItemGlycerolAddons';
import getQuoteDisplayNumbersForOrder from '@salesforce/apex/ABT_Portal_Controller.getQuoteDisplayNumbersForOrder';
import getRelatedList from '@salesforce/apex/ABT_Portal_Controller.getRelatedList';
import triggerOrderCollateralFlow from '@salesforce/apex/ABT_Portal_Controller.triggerOrderCollateralFlow';
import checkOrderCollateralLinkStatus from '@salesforce/apex/ABT_CollateralFileService.checkOrderCollateralLinkStatus';
import notifyCollateralDownloadFailure from '@salesforce/apex/ABT_Portal_Controller.notifyCollateralDownloadFailure';
import triggerCoAFlow from '@salesforce/apex/ABT_Portal_Controller.triggerCoAFlow';
import triggerFASTAFlow from '@salesforce/apex/ABT_Portal_Controller.triggerFASTAFlow';
import triggerGenbankFlow from '@salesforce/apex/ABT_Portal_Controller.triggerGenbankFlow';
import triggerPlateMapsFlow from '@salesforce/apex/ABT_Portal_Controller.triggerPlateMapsFlow';
import triggerTabularCoAFlow from '@salesforce/apex/ABT_Portal_Controller.triggerTabularCoAFlow';
import triggerIndividualCoAFlow from '@salesforce/apex/ABT_Portal_Controller.triggerIndividualCoAFlow';
import triggerIndividualGenbankFlow from '@salesforce/apex/ABT_Portal_Controller.triggerIndividualGenbankFlow';
import triggerIndividualFASTAFlow from '@salesforce/apex/ABT_Portal_Controller.triggerIndividualFASTAFlow';
import checkIndividualFileStatus from '@salesforce/apex/ABT_CollateralFileService.checkIndividualFileStatus';

import iconAllFiles from '@salesforce/resourceUrl/icon_all_files';
import iconCoA from '@salesforce/resourceUrl/icon_coa';
import iconFasta from '@salesforce/resourceUrl/icon_fasta';
import iconGenbank from '@salesforce/resourceUrl/icon_genbank';
import iconPlateMaps from '@salesforce/resourceUrl/icon_plate_maps';
import iconTabCoA from '@salesforce/resourceUrl/icon_tab_coa';

export default class ABT_OrderDetailV2Design extends LightningElement {
    _apiRecordId;
    _pageRef;
    @track effectiveOrderId;

    @api
    get recordId() {
        return this._apiRecordId;
    }
    set recordId(value) {
        this._apiRecordId = value;
        this.syncEffectiveOrderId();
    }

    currentUserName = '';
 
    @track orderHeader = {
        orderNumber: '--',
        projectName: '--',
        requestor: '--',
        orderPlaced: '--',
        status: '--',
        statusPicklist: '',
        paymentMethod: '--',
        poNumber: '--',
        shippingMethod: '--',
        incoTerms: 'FCA',
        billingAddress: '--',
        shippingAddress: '--',
        notes: '--',
        subtotal: '$0.00',
        shippingAndPackaging: '$0.00',
        discount: '$0.00',
        tax: '$0.00',
        total: '$0.00',
        ansaQuoteNumber: '',
        trackingNumber: '',
        taxExempt: false,
        canEditTaxExempt: false,
        acceptPartial: false,
        canEditAcceptPartial: false
    };

    isUpdatingTaxExempt = false;
    isUpdatingAcceptPartial = false;
    @track showPartialShipmentTooltip = false;
 
    @track orderItems = [];
    @track quoteNumberByItemId = {};
    @track glycerolAddonByItemId = {};
    _rawOrderItems = [];
    @track csvLineData = [];
    @track invoices = [];

    /** Avoid showing a status pill until Order is loaded (empty picklist was mapped to IN PROGRESS). */
    @track orderHeaderReady = false;

    orderProduct;
    requestedPackaging;
    pendingDownloadUrl;

    @track showOrderPlacedBanner = false;


    @track isDownloadModalOpen = false;
    @track showCategorySelection = true;
    @track showSequenceSelection = false;
    @track selectedFileCategory = '';
    @track sequenceList = [];
    @track isDownloadInProgress = false;
    @track downloadProgressMessage = '';
    @track hasDownloadError = false;
    @track downloadErrorMessage = '';
    hasSentCollateralFailureEmail = false;

    @wire(CurrentPageReference)
    handlePageReference(pageRef) {
        this._pageRef = pageRef;
        this.syncEffectiveOrderId();
    }

    connectedCallback() {
        this.syncEffectiveOrderId();
        this.checkOrderPlacedBanner();
        ensureGoogleAdsTrackingLoaded();
        this._outsideClickHandler = () => {
            if (this.showPartialShipmentTooltip) {
                this.showPartialShipmentTooltip = false;
            }
        };
        document.addEventListener('click', this._outsideClickHandler);
    }

    disconnectedCallback() {
        document.removeEventListener('click', this._outsideClickHandler);
    }

    handlePartialShipmentLearnMore(event) {
        event.preventDefault();
        event.stopPropagation();
        this.showPartialShipmentTooltip = !this.showPartialShipmentTooltip;
    }

    checkOrderPlacedBanner() {
        if (typeof window === 'undefined') {
            return;
        }
        const params = new URLSearchParams(window.location.search || '');
        if (params.get('orderPlaced') !== '1') {
            return;
        }
        this.showOrderPlacedBanner = true;
        params.delete('orderPlaced');
        const newSearch = params.toString();
        const newUrl =
            window.location.pathname +
            (newSearch ? '?' + newSearch : '') +
            window.location.hash;
        window.history.replaceState({}, '', newUrl);
    }

    

    handleDismissOrderPlacedBanner() {
        this.showOrderPlacedBanner = false;
    }

    syncEffectiveOrderId() {
        const fromUrl = this.parseOrderIdFromUrl();
        const fromRef =
            this._pageRef?.attributes?.recordId || this._pageRef?.state?.recordId;
        const next = this._apiRecordId || fromRef || fromUrl || null;
        if (next !== this.effectiveOrderId) {
            this.effectiveOrderId = next;
        }
        if (!this.effectiveOrderId) {
            this.orderHeaderReady = true;
        }
    }

    parseOrderIdFromUrl() {
        if (typeof window === 'undefined') {
            return null;
        }
        const match = window.location.pathname.match(
            /\/order\/([a-zA-Z0-9]{15,18})(?:\/detail)?\/?$/i
        );
        return match ? match[1] : null;
    }

    @wire(getOrderPortalDetail, { orderId: '$effectiveOrderId' })
    wiredPortalDetail({ error, data }) {
        if (data) {
            this.orderHeader = {
                orderNumber: data.orderNumber || '--',
                projectName: data.projectName || '--',
                requestor: data.requestorName || this.currentUserName || '--',
                orderPlaced: this.formatDate(data.orderPlaced),
                statusPicklist: data.status || '',
                status: data.status || '',
                paymentMethod: this.formatPaymentMethod(data.paymentMethod),
                poNumber: this.formatPoNumber(data.poNumber),
                shippingMethod: this.formatShippingMethod(data.shippingMethod),
                incoTerms: data.incoTerms || 'FCA',
                billingAddress: data.billingAddress || '--',
                shippingAddress: data.shippingAddress || '--',
                notes: data.notes || '--',
                ansaQuoteNumber: data.ansaQuoteNumber || '',
                trackingNumber: data.trackingNumber || '',
                subtotal: this.formatCurrency(data.subtotal),
                shippingAndPackaging: this.formatCurrency(
                    Number(data.shipping || 0) + Number(data.packaging || 0)
                ),
                discount: this.formatCurrency(data.discount, true),
                tax: this.formatCurrency(data.tax),
                total: this.formatCurrency(data.total),
                taxExempt: Boolean(data.taxExempt),
                canEditTaxExempt: Boolean(data.canEditTaxExempt),
                acceptPartial: data.acceptPartial === true,
                canEditAcceptPartial: Boolean(data.canEditAcceptPartial)
            };
            this.orderHeaderReady = true;
            this.refreshSequenceRows();
            this._updateDocumentTitle();
        } else if (error) {
            console.error('Error loading order portal detail:', error);
            this.orderHeaderReady = true;
            this.showError('Unable to load order details', error);
        } else {
            this.orderHeaderReady = false;
        }
    }
 
    // Wire service to get Order Line Items
    @wire(getOrderItemRelatedList, { recordId: '$effectiveOrderId' })
    wiredOrderItems({ error, data }) {
        if (data) {
            this._rawOrderItems = data || [];
            this.csvLineData = this.buildCsvLineData(this._rawOrderItems);
            this.loadQuoteNumbersForItems();
        } else if (error) {
            console.error('Error loading order items:', error);
            this._rawOrderItems = [];
            this.csvLineData = [];
            this.orderItems = [];
            this.quoteNumberByItemId = {};
        }
    }

    @wire(getOrderItemGlycerolAddons, { recordId: '$effectiveOrderId' })
    wiredGlycerolAddons({ error, data }) {
        if (data) {
            this.glycerolAddonByItemId = data || {};
            this.refreshSequenceRows();
        } else if (error) {
            console.error('Error loading glycerol add-ons:', error);
            this.glycerolAddonByItemId = {};
            this.refreshSequenceRows();
        }
    }

    loadQuoteNumbersForItems() {
        if (!this.effectiveOrderId) {
            this.quoteNumberByItemId = {};
            this.refreshSequenceRows();
            return;
        }

        getQuoteDisplayNumbersForOrder({ orderId: this.effectiveOrderId })
            .then((quoteNumbers) => {
                this.quoteNumberByItemId = quoteNumbers || {};
                this.refreshSequenceRows();
            })
            .catch((quoteNumberError) => {
                console.error('Error loading per-line quote numbers:', quoteNumberError);
                this.quoteNumberByItemId = {};
                this.refreshSequenceRows();
            });
    }

    buildCsvLineData(items) {
        return (items || []).map((item) => buildOrderItemCsvRow(item));
    }

    refreshSequenceRows() {
        if (!this._rawOrderItems.length) {
            this.orderItems = [];
            return;
        }
        const defaultQuoteId =
            this.orderHeader.ansaQuoteNumber ||
            this.getQuoteIdFromItem(this._rawOrderItems[0]) ||
            '--';
        this.orderItems = this._rawOrderItems.map((item) =>
            this.mapOrderItemToSequenceRow(item, defaultQuoteId)
        );
    }

    // Wire service to get Invoices
    @wire(getRelatedList, { parentId: '$effectiveOrderId', parentApiName: 'ABT_Invoice__c' })
    wiredInvoices({ error, data }) {
        if (data) {
            this.invoices = (data || []).map((inv) => {
                const paymentUrl = inv.ABT_Stripe_Payment_Link__c || '--';
                return {
                    id: inv.Id,
                    invoiceNumber: inv.Name || '--',
                    amount: this.formatCurrency(inv.ABT_Amount_Paid__c),
                    invoiceDate: this.formatDate(inv.ABT_Invoice_Date__c),
                    dueDate: this.formatDate(this.addDays(inv.ABT_Invoice_Date__c, 30)),
                    paymentUrl,
                    hasPaymentUrl: Boolean(paymentUrl && paymentUrl !== '--'),
                    status: inv.ABT_Status__c || 'Pending'
                };
            });
        } else if (error) {
            // Invoices may not exist yet - don't show error
            this.invoices = [];
        }
    }

    @wire(getRecord, { recordId: USER_ID, fields: [USER_NAME_FIELD] })
    wiredCurrentUser({ data }) {
        if (data?.fields?.Name?.value) {
            this.currentUserName = data.fields.Name.value;
        }
    }

    @wire(getRecord, {
        recordId: '$effectiveOrderId',
        fields: [ORDER_PRODUCT_FIELD, REQUESTED_PACKAGING_FIELD]
    })
    wiredOrderContext({ data }) {
        if (data) {
            this.orderProduct = data.fields.Order_Product__c?.value;
            this.requestedPackaging = data.fields.Requested_Packaging__c?.value;
        }
    }

    get statusClass() {
        return this.portalStatusPill(this.orderHeader.statusPicklist).className;
    }

    get statusLabel() {
        return this.portalStatusPill(this.orderHeader.statusPicklist).label;
    }

    get hasOrderLines() {
        return Array.isArray(this.orderItems) && this.orderItems.length > 0;
    }

    get hasInvoices() {
        return Array.isArray(this.invoices) && this.invoices.length > 0;
    }

    get hasTrackingNumber() {
        return Boolean(this.orderHeader.trackingNumber);
    }

    get isTaxExemptDisabled() {
        return !this.orderHeader.canEditTaxExempt || this.isUpdatingTaxExempt;
    }

    get taxExemptRowClass() {
        return this.orderHeader.canEditTaxExempt
            ? 'check-row check-row-editable'
            : 'check-row';
    }

    get isAcceptPartialDisabled() {
        return !this.orderHeader.canEditAcceptPartial || this.isUpdatingAcceptPartial;
    }

    get acceptPartialRowClass() {
        return this.orderHeader.canEditAcceptPartial
            ? 'check-row check-row-editable'
            : 'check-row';
    }

    handleTaxExemptChange(event) {
        if (!this.orderHeader.canEditTaxExempt || !this.effectiveOrderId) {
            event.target.checked = this.orderHeader.taxExempt;
            return;
        }

        const previousValue = this.orderHeader.taxExempt;
        const newValue = event.target.checked;
        this.isUpdatingTaxExempt = true;

        updateOrderTaxExempt({
            orderId: this.effectiveOrderId,
            taxExempt: newValue
        })
            .then(() => {
                this.orderHeader = {
                    ...this.orderHeader,
                    taxExempt: newValue
                };
                this.showToast(
                    'Saved',
                    newValue
                        ? 'This order is marked as tax exempt.'
                        : 'This order is no longer marked as tax exempt.',
                    'success'
                );
            })
            .catch((error) => {
                event.target.checked = previousValue;
                this.showError('Unable to update tax exempt status', error);
            })
            .finally(() => {
                this.isUpdatingTaxExempt = false;
            });
    }

    handleAcceptPartialChange(event) {
        if (!this.orderHeader.canEditAcceptPartial || !this.effectiveOrderId) {
            event.target.checked = this.orderHeader.acceptPartial;
            return;
        }

        const previousValue = this.orderHeader.acceptPartial;
        const newValue = event.target.checked;
        this.isUpdatingAcceptPartial = true;

        updateOrderAcceptPartialShipment({
            orderId: this.effectiveOrderId,
            acceptPartial: newValue
        })
            .then(() => {
                this.orderHeader = {
                    ...this.orderHeader,
                    acceptPartial: newValue
                };
                this.showToast(
                    'Saved',
                    newValue
                        ? 'You will receive partial shipments as sequences are ready.'
                        : 'You will receive all sequences in a single shipment.',
                    'success'
                );
            })
            .catch((error) => {
                event.target.checked = previousValue;
                this.showError('Unable to update partial shipment preference', error);
            })
            .finally(() => {
                this.isUpdatingAcceptPartial = false;
            });
    }

    get isOrderFilesButtonDisabled() {
        return !this.effectiveOrderId;
    }

    get categorySelectionVisible() {
        return this.showCategorySelection && !this.isDownloadInProgress && !this.hasDownloadError;
    }

    get sequenceSelectionVisible() {
        return this.showSequenceSelection && !this.isDownloadInProgress && !this.hasDownloadError;
    }

    get iconAllFilesUrl() {
        return iconAllFiles;
    }

    get iconCoAUrl() {
        return iconCoA;
    }

    get iconFastaUrl() {
        return iconFasta;
    }

    get iconGenbankUrl() {
        return iconGenbank;
    }

    get iconPlateMapsUrl() {
        return iconPlateMaps;
    }

    get iconTabCoAUrl() {
        return iconTabCoA;
    }

    get showLoadingSpinner() {
        return this.isDownloadInProgress;
    }

    get showErrorMessage() {
        return this.hasDownloadError;
    }

    get downloadAllButtonLabel() {
        return this.isDownloadInProgress
            ? 'Preparing Download...'
            : `Download All ${this.selectedFileCategory}`;
    }

    get isGenbankDisabled() {
        return this.orderProduct === 'Fragment';
    }

    get isFastaDisabled() {
        return this.orderProduct === 'Fragment';
    }

    get isPlateMapsDisabled() {
        return (
            this.requestedPackaging !== 'Standard' && this.requestedPackaging !== 'Axygen 96'
        );
    }

    get genbankCssClass() {
        return this.isGenbankDisabled
            ? 'slds-box slds-box_small slds-text-align_center download-option-disabled'
            : 'slds-box slds-box_small slds-text-align_center download-option';
    }

    get fastaCssClass() {
        return this.isFastaDisabled
            ? 'slds-box slds-box_small slds-text-align_center download-option-disabled'
            : 'slds-box slds-box_small slds-text-align_center download-option';
    }

    get plateMapsCssClass() {
        return this.isPlateMapsDisabled
            ? 'slds-box slds-box_small slds-text-align_center download-option-disabled'
            : 'slds-box slds-box_small slds-text-align_center download-option';
    }

    get genbankIconStyle() {
        return this.isGenbankDisabled ? 'opacity: 0.4;' : '';
    }

    get genbankTextStyle() {
        return this.isGenbankDisabled ? 'color: #c4c4c4;' : '';
    }

    get fastaIconStyle() {
        return this.isFastaDisabled ? 'opacity: 0.4;' : '';
    }

    get fastaTextStyle() {
        return this.isFastaDisabled ? 'color: #c4c4c4;' : '';
    }

    get plateMapsIconStyle() {
        return this.isPlateMapsDisabled ? 'opacity: 0.4;' : '';
    }

    get plateMapsTextStyle() {
        return this.isPlateMapsDisabled ? 'color: #c4c4c4;' : '';
    }

    get genbankDescription() {
        return this.isGenbankDisabled
            ? 'Not available for Fragment orders'
            : 'Genbank format sequence files';
    }

    get fastaDescription() {
        return this.isFastaDisabled
            ? 'Not available for Fragment orders'
            : 'FASTA format sequence files';
    }

    get plateMapsDescription() {
        return this.isPlateMapsDisabled
            ? 'Only available for Standard/Axygen 96 packaging'
            : 'Plate mapping information';
    }

    get trackingUrl() {
        return this.buildTrackingUrl(this.orderHeader.trackingNumber);
    }

    buildTrackingUrl(trackingNumber) {
        const num = (trackingNumber || '').trim();
        if (!num) {
            return null;
        }
        if (/^https?:\/\//i.test(num)) {
            return num;
        }
        return `https://www.fedex.com/fedextrack/?trknbr=${encodeURIComponent(num)}`;
    }

    resolveSequenceDisplayName(item) {
        return sequenceNameFromOrderItem(item) || '--';
    }

    mapOrderItemToSequenceRow(item, defaultQuoteId) {
        const lineStatus = this.sequenceStatusPill(item.Status__c);
        const isShipped = lineStatus.variant === 'shipped';
        const asEarlyAsRaw =
            item.As_Early_As_Date__c ||
            item.Expected_Ship_Date__c ||
            item.Original_Promise_Date__c;
        const guaranteedRaw =
            item.Expected_Ship_Date__c ||
            item.Original_Promise_Date__c;
        const expectedRaw = isShipped
            ? item.Confirmed_Ship_Date__c || item.Expected_Ship_Date__c || asEarlyAsRaw
            : asEarlyAsRaw || item.Confirmed_Ship_Date__c;
        const sequenceName = this.resolveSequenceDisplayName(item);
        const trackingNumber = (item.Tracking_Number__c || '').trim();
        const basePrice = Number(item.TotalPrice ?? item.UnitPrice ?? 0);
        const glycerolAddon = Number(this.glycerolAddonByItemId?.[item.Id]) || 0;

        return {
            id: item.Id,
            quoteId: this.getQuoteIdFromItem(item) || defaultQuoteId,
            product: formatProductName(item.Product2?.Name) || '--',
            name: sequenceName,
            feasibility: normalizedSequenceClassificationFromOrderItem(item),
            statusLabel: lineStatus.label,
            statusClass: lineStatus.className,
            expectedShipDate: expectedRaw ? this.formatDate(expectedRaw) : 'Pending',
            showShipIcon: isShipped && Boolean(expectedRaw),
            guaranteedDate: guaranteedRaw ? this.formatDate(guaranteedRaw) : 'Pending',
            totalPrice: this.formatCurrency(basePrice + glycerolAddon),
            sequenceName,
            trackingNumber,
            trackingUrl: this.buildTrackingUrl(trackingNumber)
        };
    }

    sequenceStatusPill(rawStatus) {
        const s = (rawStatus || '').toLowerCase();
        if (
            s.includes('fulfilled') ||
            s.includes('packaged') ||
            s.includes('shipped') ||
            s === 'completed'
        ) {
            return { label: 'SHIPPED', variant: 'shipped', className: 'line-status line-status-shipped' };
        }
        if (s.includes('production') || s === 'booked' || s === 'entered') {
            return {
                label: 'IN PRODUCTION',
                variant: 'inproduction',
                className: 'line-status line-status-inproduction'
            };
        }
        if (s.includes('cancel')) {
            return { label: 'CANCELED', variant: 'canceled', className: 'line-status line-status-canceled' };
        }
        if (s === 'failed') {
            return { label: 'FAILED', variant: 'failed', className: 'line-status line-status-failed' };
        }
        return {
            label: 'IN PRODUCTION',
            variant: 'inproduction',
            className: 'line-status line-status-inproduction'
        };
    }

    formatPoNumber(value) {
        const text = (value || '').trim();
        return text || '--';
    }

    portalStatusPill(rawStatus) {
        const s = rawStatus || '';
        if (!s) {
            return { label: '—', className: 'status-pill status-unknown' };
        }
        if (s === 'Completed') {
            return { label: 'COMPLETED', className: 'status-pill status-completed' };
        }
        if (s === 'Canceled') {
            return { label: 'CANCELED', className: 'status-pill status-canceled' };
        }
        if (s === 'Draft' || s === 'On Hold' || s === 'Failed') {
            return { label: 'PENDING', className: 'status-pill status-pending' };
        }
        return { label: 'IN PROGRESS', className: 'status-pill status-inprogress' };
    }
 
    // Helper methods for data formatting
    getRequestorName(data) {
        const requestorName = this.readLookupName(data, [
            'Order_Contact__c',
            'OwnerId',
            'CreatedById',
            'LastModifiedById'
        ]);
        if (requestorName && requestorName !== '--') {
            return requestorName;
        }

        const requestorText = this.readField(data, [
            'Requestor__c',
            'Requested_By__c',
            'Order_Contact_Name__c'
        ]);
        if (requestorText && requestorText !== '--') {
            return requestorText;
        }

        if (this.currentUserName) {
            return this.currentUserName;
        }

        return '--';
    }

    readLookupName(data, names) {
        const fields = data.fields || {};
        for (const fieldName of names) {
            const field = fields[fieldName];
            if (!field) {
                continue;
            }

            if (field.displayValue) {
                return field.displayValue;
            }

            if (field.value && typeof field.value === 'object') {
                const relationshipName = field.value?.fields?.Name?.value;
                if (relationshipName) {
                    return relationshipName;
                }
            }

            if (typeof field.value === 'string' && field.value && !this.isSalesforceId(field.value)) {
                return field.value;
            }
        }
        return '--';
    }

    isSalesforceId(value) {
        return /^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$/.test(value);
    }
 
    formatPaymentMethod(rawValue) {
        if (!rawValue || rawValue === '--') {
            return 'Purchase Order';
        }
        
        // Map picklist values to display labels
        const paymentMap = {
            'purchase_order': 'Purchase Order',
            'credit_card': 'Credit Card',
            'wire_transfer': 'Wire Transfer'
        };
        
        return paymentMap[rawValue] || rawValue;
    }
 
    formatShippingMethod(rawValue) {
        if (!rawValue || rawValue === '--') {
            return '--';
        }
        return rawValue;
    }
 
    resolveOrderNumber(data) {
        const orderNumber = this.readField(data, ['OrderNumber']);
        const netSuite = this.readField(data, ['NetSuite_Order_Number__c']);
        const ns = (netSuite && netSuite !== '--') ? String(netSuite).trim() : '';
        if (ns && ns.toLowerCase() !== 'pending') {
            return ns;
        }
        return 'Pending';
    }

    _updateDocumentTitle() {
        if (typeof document === 'undefined') {
            return;
        }
        const orderNum = (this.orderHeader.orderNumber || '').trim();
        let label;
        if (orderNum && orderNum.toLowerCase() !== 'pending' && orderNum !== '--') {
            label = orderNum;
        } else {
            const quoteNum = (this.orderHeader.ansaQuoteNumber || '').trim();
            label = quoteNum || 'Pending';
        }
        document.title = `Ansa Order - ${label}`;
    }

    getBillingAddress(data) {
        const addr = this.readRaw(data, ['BillingAddress']);
        return this.formatAddress(addr);
    }
 
    getShippingAddress(data) {
        const addr = this.readRaw(data, ['ShippingAddress']);
        return this.formatAddress(addr);
    }
 
    getQuoteIdFromItem(item) {
        if (item?.Id && this.quoteNumberByItemId?.[item.Id]) {
            return this.quoteNumberByItemId[item.Id];
        }
        if (item?.QuoteLineItem?.Quote?.Ansa_Quote_Number__c) {
            return item.QuoteLineItem.Quote.Ansa_Quote_Number__c;
        }
        if (item?.QuoteLineItem?.Quote?.QuoteNumber) {
            return item.QuoteLineItem.Quote.QuoteNumber;
        }
        const ord = item.Order;
        if (ord?.Ansa_Quote_Number__c) {
            return ord.Ansa_Quote_Number__c;
        }
        if (ord?.Quote?.QuoteNumber) {
            return ord.Quote.QuoteNumber;
        }
        return '';
    }

    handleTrackShipment() {
        if (this.trackingUrl) {
            window.open(this.trackingUrl, '_blank');
        }
    }
 
    // Download order files (collateral modal — same behavior as aBT_OrderDetail in partial/prod)
    openDownloadModal() {
        if (!this.effectiveOrderId) {
            this.showToast('Error', 'Order is not loaded yet. Please refresh and try again.', 'error');
            return;
        }
        this.isDownloadModalOpen = true;
        this.showCategorySelection = true;
        this.showSequenceSelection = false;
        this.selectedFileCategory = '';
        this.resetDownloadStates();
        this.loadOrderLineItemsForDownload();
    }

    closeDownloadModal() {
        this.isDownloadModalOpen = false;
        this.showCategorySelection = true;
        this.showSequenceSelection = false;
        this.selectedFileCategory = '';
        this.resetDownloadStates();
    }

    tryAgainDownload() {
        if (this.pendingDownloadUrl) {
            this.resetDownloadStates();
            this.closeDownloadModal();
            this.downloadOrderFiles(this.pendingDownloadUrl);
            this.pendingDownloadUrl = null;
            return;
        }
        this.resetDownloadStates();
        this.showCategorySelection = true;
        this.showSequenceSelection = false;
        this.selectedFileCategory = '';
    }

    resetDownloadStates() {
        this.isDownloadInProgress = false;
        this.downloadProgressMessage = '';
        this.hasDownloadError = false;
        this.downloadErrorMessage = '';
    }

    setLoadingState(message) {
        this.isDownloadInProgress = true;
        this.downloadProgressMessage = message;
        this.hasDownloadError = false;
        this.downloadErrorMessage = '';
    }

    setErrorState(message) {
        this.isDownloadInProgress = false;
        this.downloadProgressMessage = '';
        this.hasDownloadError = true;
        this.downloadErrorMessage =
            message ||
            'There was an error retrieving your collateral files. We are currently looking into it and will send you an email with your collateral within 24 business hours.';
    }

    async notifyFailureEmailOnce(fileType, reason) {
        const orderId = this.effectiveOrderId;
        if (this.hasSentCollateralFailureEmail || !orderId) {
            return;
        }

        this.hasSentCollateralFailureEmail = true;
        try {
            const result = await notifyCollateralDownloadFailure({
                orderId,
                fileType,
                errorMessage: reason
            });
            if (!result?.success) {
                console.error('Failed to send collateral failure notification:', result?.message);
            }
        } catch (notificationError) {
            console.error('Error calling collateral failure notification:', notificationError);
        }
    }

    async loadOrderLineItemsForDownload() {
        try {
            const orderItems = await getOrderItemRelatedList({
                recordId: this.effectiveOrderId
            });
            this.sequenceList = this.transformOrderItemsToSequenceList(orderItems);
        } catch (error) {
            console.error('Error loading order line items for download:', error);
            this.sequenceList = [];
            this.showToast('Error', 'Failed to load sequence data', 'error');
        }
    }

    transformOrderItemsToSequenceList(orderItems) {
        if (!orderItems || orderItems.length === 0) {
            return [];
        }
        return orderItems.map((item) => {
            const isShipped = item.Status__c === 'Fulfilled' || item.Status__c === 'Completed';
            const sequenceName = sequenceNameFromOrderItem(item) || 'Unknown Sequence';
            const productName = formatProductName(
                (item.Product2 && item.Product2.Name) || 'Unknown Product'
            );
            return {
                id: item.Id,
                name: sequenceName,
                product: productName,
                status: item.Status__c || 'Unknown',
                disabled: !isShipped,
                rowClass: !isShipped ? 'disabled-row' : ''
            };
        });
    }

    transitionToSequenceSelection(fileCategory) {
        this.selectedFileCategory = fileCategory;
        this.showCategorySelection = false;
        this.showSequenceSelection = true;
    }

    goBackToCategories() {
        this.showSequenceSelection = false;
        this.showCategorySelection = true;
        this.selectedFileCategory = '';
    }

    selectAllFiles() {
        this.selectedFileCategory = 'All Order Files';
        this.triggerSpecificFlow('All Order Files', []);
    }

    selectCoAPdf() {
        this.transitionToSequenceSelection('CoAs (PDF)');
    }

    selectTabularCoA() {
        this.selectedFileCategory = 'Tabular CoA';
        this.triggerSpecificFlow('Tabular CoA', []);
    }

    selectGenbankFiles() {
        if (this.isGenbankDisabled) {
            return;
        }
        this.transitionToSequenceSelection('Genbank Files');
    }

    selectFastaFiles() {
        if (this.isFastaDisabled) {
            return;
        }
        this.transitionToSequenceSelection('FASTA Files');
    }

    selectPlateMaps() {
        if (this.isPlateMapsDisabled) {
            return;
        }
        this.transitionToSequenceSelection('Plate Maps');
    }

    async handleIndividualDownload(event) {
        const sequenceId = event.target.dataset.sequenceId;
        if (!sequenceId) {
            this.showToast('Error', 'Unable to identify sequence for download', 'error');
            return;
        }
        try {
            await this.triggerIndividualDownloads(this.selectedFileCategory, [sequenceId]);
        } catch (error) {
            console.error('Error during individual download:', error);
            this.showToast('Error', 'Failed to download individual file. Please try again.', 'error');
        }
    }

    async downloadAllSequences() {
        const availableSequenceIds = this.sequenceList
            .filter((sequence) => !sequence.disabled)
            .map((sequence) => sequence.id);
        await this.performDownload(this.selectedFileCategory, availableSequenceIds);
    }

    getFileSuffix(fileType) {
        switch (fileType) {
            case 'CoAs (PDF)':
                return '_pdf';
            case 'Genbank Files':
                return '_gb';
            case 'FASTA Files':
                return '_fasta';
            case 'Tabular CoA':
                return '_Certificate_of_Analysis_csv';
            case 'Plate Maps':
                return '_Plate_Map_csv';
            case 'All Order Files':
            default:
                return null;
        }
    }

    getFileExtension(fileType) {
        return 'zip';
    }

    async performDownload(fileType, sequenceIds) {
        await this.triggerSpecificFlow(fileType, sequenceIds);
    }

    async triggerSpecificFlow(fileType, sequenceIds) {
        try {
            let flowTriggerMethod;
            let flowName;
            switch (fileType) {
                case 'All Order Files':
                    flowTriggerMethod = triggerOrderCollateralFlow;
                    flowName = 'Order_Collateral_Flow';
                    break;
                case 'CoAs (PDF)':
                    flowTriggerMethod = triggerCoAFlow;
                    flowName = 'Download_All_CoAs';
                    break;
                case 'FASTA Files':
                    flowTriggerMethod = triggerFASTAFlow;
                    flowName = 'Download_All_FASTAs';
                    break;
                case 'Genbank Files':
                    flowTriggerMethod = triggerGenbankFlow;
                    flowName = 'Download_All_Genbanks';
                    break;
                case 'Plate Maps':
                    flowTriggerMethod = triggerPlateMapsFlow;
                    flowName = 'Download_Plate_Maps';
                    break;
                case 'Tabular CoA':
                    flowTriggerMethod = triggerTabularCoAFlow;
                    flowName = 'Download_Tabular_CoA';
                    break;
                default:
                    this.setErrorState(`Unknown file type: ${fileType}`);
                    return;
            }

            this.setLoadingState(`Preparing ${fileType}, please wait...`);
            const fileSuffix = this.getFileSuffix(fileType);
            const fileExtension = this.getFileExtension(fileType);

            const existingFileCheck = await checkOrderCollateralLinkStatus({
                orderId: this.effectiveOrderId,
                fileSuffix: fileSuffix,
                fileExtension: fileExtension
            });

            if (existingFileCheck?.ready && existingFileCheck?.downloadUrl) {
                this.resetDownloadStates();
                this.closeDownloadModal();
                this.downloadOrderFiles(existingFileCheck.downloadUrl);
                return;
            }

            const result = await flowTriggerMethod({
                orderId: this.effectiveOrderId,
                sequenceIds: sequenceIds
            });

            if (result?.success) {
                this.setLoadingState(`Generating ${fileType}, please wait...`);
                this.pollForDownloadLink(flowName, fileSuffix, fileExtension);
            } else {
                const errorMessage = result?.message || `Failed to generate ${fileType}`;
                this.setErrorState(errorMessage);
            }
        } catch (error) {
            console.error(`Error triggering ${fileType} flow:`, error);
            this.setErrorState(`Failed to trigger ${fileType} generation. Please try again.`);
        }
    }

    pollForDownloadLink(flowName, fileSuffix, fileExtension) {
        const POLL_INTERVAL_MS = 2000;
        const MAX_POLL_COUNT = 15;
        let pollCount = 0;
        this.hasSentCollateralFailureEmail = false;

        const pollTimer = setInterval(async () => {
            pollCount++;
            try {
                const statusResult = await checkOrderCollateralLinkStatus({
                    orderId: this.effectiveOrderId,
                    fileSuffix: fileSuffix,
                    fileExtension: fileExtension
                });

                if (statusResult?.ready && statusResult?.downloadUrl) {
                    clearInterval(pollTimer);
                    try {
                        this.resetDownloadStates();
                        this.closeDownloadModal();
                        setTimeout(() => {
                            this.downloadOrderFiles(statusResult.downloadUrl);
                        }, 100);
                    } catch (downloadError) {
                        console.error('Error during download process:', downloadError);
                        this.setErrorState(
                            'Download ready! Click Try Again to download your files.'
                        );
                        this.pendingDownloadUrl = statusResult.downloadUrl;
                    }
                } else if (pollCount >= MAX_POLL_COUNT) {
                    clearInterval(pollTimer);
                    await this.notifyFailureEmailOnce(
                        flowName,
                        `Polling timed out after ${MAX_POLL_COUNT} attempts`
                    );
                    this.setErrorState(
                        "There was an error retrieving your collateral files. We're currently looking into it and we'll send you an email with your collateral within 24 business hours."
                    );
                }
            } catch (error) {
                console.error(`Error polling for ${flowName} link:`, error);
                clearInterval(pollTimer);
                await this.notifyFailureEmailOnce(
                    flowName,
                    error?.body?.message || error?.message || 'Unexpected polling error while checking collateral status'
                );
                this.setErrorState(
                    "There was an error retrieving your collateral files. We're currently looking into it and we'll send you an email with your collateral within 24 business hours."
                );
            }
        }, POLL_INTERVAL_MS);
    }

    async triggerIndividualDownloads(fileType, orderItemIds) {
        try {
            this.setLoadingState(`Preparing individual ${fileType} file, please wait...`);

            const existingFiles = [];
            const newOrderItems = [];

            for (const orderItemId of orderItemIds) {
                try {
                    const existingFileCheck = await checkIndividualFileStatus({
                        orderItemId: orderItemId,
                        fileType: fileType
                    });
                    if (existingFileCheck?.ready && existingFileCheck?.downloadUrl) {
                        existingFiles.push({
                            orderItemId,
                            downloadUrl: existingFileCheck.downloadUrl
                        });
                    } else {
                        newOrderItems.push(orderItemId);
                    }
                } catch (error) {
                    console.error(`Error checking existing file for OrderItem ${orderItemId}:`, error);
                    newOrderItems.push(orderItemId);
                }
            }

            if (existingFiles.length > 0) {
                for (const file of existingFiles) {
                    this.downloadOrderFiles(file.downloadUrl);
                }
            }

            if (newOrderItems.length > 0) {
                this.setLoadingState(`Generating individual ${fileType} file, please wait...`);
                await this.triggerIndividualFlowsForOrderItems(fileType, newOrderItems);
                this.pollForIndividualFiles(fileType, newOrderItems);
            } else {
                this.resetDownloadStates();
                this.closeDownloadModal();
            }
        } catch (error) {
            console.error(`Error triggering individual ${fileType} downloads:`, error);
            this.setErrorState(`Failed to trigger ${fileType} generation. Please try again.`);
        }
    }

    async triggerIndividualFlowsForOrderItems(fileType, orderItemIds) {
        let flowTriggerMethod;
        switch (fileType) {
            case 'CoAs (PDF)':
                flowTriggerMethod = triggerIndividualCoAFlow;
                break;
            case 'Genbank Files':
                flowTriggerMethod = triggerIndividualGenbankFlow;
                break;
            case 'FASTA Files':
                flowTriggerMethod = triggerIndividualFASTAFlow;
                break;
            default:
                throw new Error(`Individual downloads not supported for file type: ${fileType}`);
        }

        for (const orderItemId of orderItemIds) {
            try {
                const result = await flowTriggerMethod({ orderItemId });
                if (!result?.success) {
                    console.error(
                        `Failed to trigger ${fileType} for OrderItem ${orderItemId}:`,
                        result?.message
                    );
                }
            } catch (error) {
                console.error(`Error triggering ${fileType} for OrderItem ${orderItemId}:`, error);
            }
        }
    }

    pollForIndividualFiles(fileType, orderItemIds) {
        const POLL_INTERVAL_MS = 2000;
        const MAX_POLL_COUNT = 15;
        let pollCount = 0;
        const completedOrderItems = [];
        this.hasSentCollateralFailureEmail = false;

        const pollTimer = setInterval(async () => {
            pollCount++;
            try {
                const remainingOrderItems = orderItemIds.filter(
                    (id) => !completedOrderItems.includes(id)
                );

                for (const orderItemId of remainingOrderItems) {
                    try {
                        const statusResult = await checkIndividualFileStatus({
                            orderItemId: orderItemId,
                            fileType: fileType
                        });
                        if (statusResult?.ready && statusResult?.downloadUrl) {
                            completedOrderItems.push(orderItemId);
                            setTimeout(() => {
                                this.downloadOrderFiles(statusResult.downloadUrl);
                            }, 100);
                        }
                    } catch (error) {
                        console.error(`Error checking status for OrderItem ${orderItemId}:`, error);
                    }
                }

                if (completedOrderItems.length === orderItemIds.length) {
                    clearInterval(pollTimer);
                    this.resetDownloadStates();
                    this.closeDownloadModal();
                } else if (pollCount >= MAX_POLL_COUNT) {
                    clearInterval(pollTimer);
                    await this.notifyFailureEmailOnce(
                        fileType,
                        `Individual file polling timed out after ${MAX_POLL_COUNT} attempts`
                    );
                    this.setErrorState(
                        "There was an error retrieving your collateral files. We're currently looking into it and we'll send you an email with your collateral within 24 business hours."
                    );
                }
            } catch (error) {
                console.error(`Error during individual ${fileType} polling:`, error);
                clearInterval(pollTimer);
                this.setErrorState('There was an error retrieving your individual files. Please try again.');
            }
        }, POLL_INTERVAL_MS);
    }

    downloadOrderFiles(url) {
        if (!url?.trim()) {
            this.showToast('Info', 'Download link is not available yet. Please try again shortly.', 'info');
            return;
        }
        try {
            const anchor = document.createElement('a');
            anchor.href = url;
            anchor.target = '_blank';
            anchor.download = '';
            document.body.appendChild(anchor);
            anchor.click();
            setTimeout(() => {
                try {
                    document.body.removeChild(anchor);
                } catch (e) {
                    /* ignore cleanup errors */
                }
            }, 0);
        } catch (error) {
            console.error('Order files download error:', error);
            this.showToast('Error', 'Unable to start download. Please try again or contact support.', 'error');
        }
    }

    handleDownloadSequences() {
        if (!this.csvLineData || this.csvLineData.length === 0) {
            this.showToast('No Data', 'No sequences available to download.', 'warning');
            return;
        }

        const columns = [
            'SequenceName',
            'Sequence',
            'SequenceLength',
            'SequenceClassification'
        ];
        const lines = [columns.join(',')];
        this.csvLineData.forEach((row) => {
            lines.push(columns.map((col) => this.escapeCsvField(row[col])).join(','));
        });

        const blob = new Blob([lines.join('\n')], { type: 'text/csv;charset=utf-8;' });
        const url = URL.createObjectURL(blob);
        const downloadElement = document.createElement('a');
        downloadElement.href = url;
        downloadElement.download = this.orderHeader.orderNumber
            ? `${this.orderHeader.orderNumber} - Sequence Export.csv`
            : 'Order Sequences Export.csv';
        document.body.appendChild(downloadElement);
        downloadElement.click();
        document.body.removeChild(downloadElement);
        URL.revokeObjectURL(url);

        this.showToast('Download Complete', 'Sequences exported successfully.', 'success');
    }

    escapeCsvField(value) {
        const text = String(value ?? '');
        if (/[",\n\r]/.test(text)) {
            return `"${text.replace(/"/g, '""')}"`;
        }
        return text;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
 
    handleInvoiceDownload(event) {
        const url = event.currentTarget.dataset.url;
        if (url && url !== '--') {
            window.open(url, '_blank');
        }
    }
 
    // Utility methods
    readRaw(data, names) {
        const f = data.fields || {};
        for (const n of names) {
            if (f[n]) {
                return f[n].value;
            }
        }
        return null;
    }
 
    readField(data, names) {
        const f = data.fields || {};
        for (const n of names) {
            if (f[n]) {
                return f[n].displayValue || f[n].value || '--';
            }
        }
        return '--';
    }
 
    readBoolean(data, names) {
        const value = this.readRaw(data, names);
        return Boolean(value);
    }
 
    formatAddress(addressObj) {
        if (!addressObj) {
            return '--';
        }
        const streetLine = [addressObj.street, addressObj.city, addressObj.state]
            .filter(Boolean)
            .join(', ');
        const countryLine = [addressObj.country, addressObj.postalCode]
            .filter(Boolean)
            .join(', ');
        const parts = [streetLine, countryLine].filter(Boolean);
        return parts.length ? parts.join(' | ') : '--';
    }
 
    formatDate(raw) {
        if (!raw) {
            return '--/--/--';
        }
        if (/^\d{4}-\d{2}-\d{2}$/.test(raw)) {
            const [y, m, d] = raw.split('-');
            return `${m}/${d}/${y.slice(-2)}`;
        }
        if (typeof raw === 'string' && raw.includes('T')) {
            const datePart = raw.split('T')[0];
            if (/^\d{4}-\d{2}-\d{2}$/.test(datePart)) {
                const [y, m, d] = datePart.split('-');
                return `${m}/${d}/${y.slice(-2)}`;
            }
        }
        const d = new Date(raw);
        if (Number.isNaN(d.getTime())) {
            return '--/--/--';
        }
        const mm = String(d.getMonth() + 1).padStart(2, '0');
        const dd = String(d.getDate()).padStart(2, '0');
        const yy = String(d.getFullYear()).slice(-2);
        return `${mm}/${dd}/${yy}`;
    }
 
    addDays(raw, days) {
        if (!raw) {
            return null;
        }
        const d = new Date(raw);
        if (Number.isNaN(d.getTime())) {
            return null;
        }
        d.setDate(d.getDate() + days);
        return d;
    }
 
    formatCurrency(amount, showAsNegative) {
        const value = Number(amount || 0);
        const abs = Math.abs(value);
        const formatted = `$${abs.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
        if (showAsNegative && value > 0) {
            return `-${formatted}`;
        }
        return formatted;
    }
 
    showError(title, error) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message: error?.body?.message || error?.message || 'Unknown error',
                variant: 'error'
            })
        );
    }
}