import { LightningElement, api, track } from 'lwc';
import ansaLogo from '@salesforce/resourceUrl/ABT_Ansa_Logo_v2';
import loginApex from '@salesforce/apex/ABT_Login_V2_Controller.login';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import {
    ensureGoogleAdsTrackingLoaded,
    captureAdsAttributionFromUrl,
    appendAdsAttributionToUrl,
    pushDataLayerEvent
} from 'c/abtGoogleAdsTracking';
import {
    syncNativeInputErrorState,
    validateNativeInputs
} from 'c/abtAuthFieldValidation';
import {
    isInvalidApexRequestError,
    recoverAfterLoginTransportError
} from 'c/abtPortalSessionUtils';

export default class AbtLogin extends LightningElement {
    ansaLogo = ansaLogo;

    /** URL path of the register page (e.g. /v2/SelfRegister). Set in Experience Builder or use default. */
    @api registerPageUrl = '/AnsaBiotechnologiesCustomerPortal/SelfRegister';

    /** URL path of the forgot password page (e.g. /v2/ForgotPassword). Set in Experience Builder or use default. */
    @api forgotPasswordPageUrl = '/AnsaBiotechnologiesCustomerPortal/v2/ForgotPassword';

    @track isLoading = false;
    @track errorMessage = '';
    @track loginEmail = '';
    @track loginPassword = '';
    showPassword = false;
    validationAttempted = false;

    connectedCallback() {
        ensureGoogleAdsTrackingLoaded();
        captureAdsAttributionFromUrl();
    }

    /** Keep gclid/UTM on the Create account link (login → signup). */
    get registerPageHref() {
        return appendAdsAttributionToUrl(
            this.registerPageUrl || '/AnsaBiotechnologiesCustomerPortal/SelfRegister'
        );
    }

    get passwordInputType() {
        return this.showPassword ? 'text' : 'password';
    }

    get passwordToggleIcon() {
        return this.showPassword ? 'utility:hide' : 'utility:preview';
    }

    get passwordToggleLabel() {
        return this.showPassword ? 'Hide password' : 'Show password';
    }

    handleTogglePasswordVisibility() {
        this.showPassword = !this.showPassword;
    }

    handleLoginEmailChange(event) {
        this.loginEmail = event.target.value;
        syncNativeInputErrorState(event.target, this.validationAttempted);
    }

    handleLoginPasswordChange(event) {
        this.loginPassword = event.target.value;
        syncNativeInputErrorState(event.target, this.validationAttempted);
    }

    async handleLoginSubmit(event) {
        event.preventDefault();
        this.validationAttempted = true;
        const inputs = this.template.querySelectorAll('input[data-section="login"]');
        if (!validateNativeInputs(inputs)) {
            return;
        }
        this.isLoading = true;
        this.errorMessage = '';
        try {
            const url = await loginApex({
                email: this.loginEmail.trim(),
                password: this.loginPassword
            });

            if (url) {
                pushDataLayerEvent({
                    event: 'portal_login'
                });

                if (typeof window !== 'undefined') {
                    window.location.href = url;
                }
            }
        } catch (e) {
            // Site.login can succeed while LWR fails to parse the response.
            if (isInvalidApexRequestError(e) && recoverAfterLoginTransportError()) {
                pushDataLayerEvent({
                    event: 'portal_login'
                });
                return;
            }
            const msg = isInvalidApexRequestError(e)
                ? 'Your browser session is out of date. Please refresh the page and try again.'
                : ((e.body && e.body.message) ? e.body.message : (e.message || 'Login failed.'));
            this.errorMessage = msg;
            this.dispatchEvent(new ShowToastEvent({ title: 'Login failed', message: msg, variant: 'error' }));
        } finally {
            this.isLoading = false;
        }
    }
}