import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getContactDetails from '@salesforce/apex/GuestOtpAuthService.getContactDetails';

export default class GuestUserPortal extends LightningElement {
    @track isOtpVerified = false;
    @track email = '';
    @track contactId = '';
    @track contactName = '';
    @track activeTab = 'myCases';
    @track isLoading = false;
    /** When set, hides the case list and shows the full case detail inline */
    @track selectedGuestCaseId = null;

    // Session Timeout variables
    _timeoutId;
    _eventsBound = false;
    _timeoutDuration = 5 * 60 * 1000; // 5 minutes in milliseconds


    connectedCallback() {
        this.checkAuthPersistence();
        
        // Check if we need to switch to a specific tab (from sessionStorage)
        try {
            const switchToTab = sessionStorage.getItem('switchToTab');
            if (switchToTab) {
                console.log('GuestUserPortal: Switching to tab:', switchToTab);
                this.activeTab = switchToTab;
                // Clear the switch request after using it
                sessionStorage.removeItem('switchToTab');
                console.log('✅ Tab switched to:', this.activeTab);
            }
        } catch (error) {
            console.error('GuestUserPortal: Error reading switchToTab from sessionStorage:', error);
        }
        
        // Listen for tab navigation events from child components
        this.addEventListener('navigatetotab', (event) => {
            console.log('GuestUserPortal: Received tab navigation event:', event.detail);
            if (event.detail && event.detail.tabValue) {
                this.activeTab = event.detail.tabValue;
                console.log('✅ GuestUserPortal: Switched to tab:', this.activeTab);
            }
        });
    }

    disconnectedCallback() {
        this.clearSessionEvents();
    }

    renderedCallback() {
        // Check if we need to switch to a specific tab after DOM rendering
        try {
            const switchToTab = sessionStorage.getItem('switchToTab');
            if (switchToTab && this.activeTab !== switchToTab) {
                console.log('GuestUserPortal renderedCallback: Switching to tab:', switchToTab);
                this.activeTab = switchToTab;
                // Clear the switch request
                sessionStorage.removeItem('switchToTab');
                console.log('✅ Tab switched in renderedCallback to:', this.activeTab);
            }
        } catch (error) {
            console.error('GuestUserPortal renderedCallback: Error checking switchToTab:', error);
        }
    }

    /**
     * Check if user is already authenticated in this session
     */
    checkAuthPersistence() {
        try {
            const storedIsOtpVerified = sessionStorage.getItem('isOtpVerified');
            if (storedIsOtpVerified === 'true') {
                this.isOtpVerified = true;
                this.email = sessionStorage.getItem('guestEmail') || '';
                this.contactId = sessionStorage.getItem('guestContactId') || '';
                this.contactName = sessionStorage.getItem('guestContactName') || '';
                console.log('GuestUserPortal: Auth state restored from sessionStorage', {
                    email: this.email,
                    contactId: this.contactId
                });
                this.setupSessionTimeout();
            }
        } catch (error) {
            console.error('GuestUserPortal: Error checking auth persistence', error);
        }
    }

    /**
     * Handle OTP verification event from guestOtpAuth component
     */
    async handleVerified(event) {
        console.log('GuestUserPortal: handleVerified called!');
        this.isLoading = true;

        if (event && event.detail) {
            console.log('GuestUserPortal: Verified Event Detail:', JSON.stringify(event.detail));

            // Extract email from event detail
            let email = null;
            if (typeof event.detail === 'object' && event.detail !== null) {
                email = event.detail.email;
            } else if (typeof event.detail === 'string') {
                email = event.detail;
            }

            if (email) {
                console.log('GuestUserPortal: Email verified:', email);
                this.email = email;
                // Move isOtpVerified = true to loadContactDetails after successful contact fetch
                
                // Fetch contact details based on email
                await this.loadContactDetails();
            } else {
                console.warn('GuestUserPortal: No email found in event detail!');
                this.showToast('Error', 'Could not retrieve email from verification', 'error');
            }
        }

        this.isLoading = false;
    }

    /**
     * Load contact details using the verified email
     */
    async loadContactDetails() {
        try {
            console.log('GuestUserPortal: Loading contact details for email:', this.email);
            
            const result = await getContactDetails({ email: this.email });
            
            if (result && result.Id) {
                this.contactId = result.Id;
                this.contactName = result.Name || 'Guest User';
                this.isOtpVerified = true; // Only grant access if contact is found
                
                // Store in sessionStorage for persistence across refresh
                try {
                    sessionStorage.setItem('isOtpVerified', 'true');
                    sessionStorage.setItem('guestEmail', this.email);
                    sessionStorage.setItem('guestContactId', this.contactId);
                    sessionStorage.setItem('guestContactName', this.contactName);
                } catch (e) {
                    console.error('GuestUserPortal: Failed to save auth state to sessionStorage', e);
                }
                
                console.log('GuestUserPortal: Contact loaded - ID:', this.contactId, 'Name:', this.contactName);
                
                this.showToast('Success', 'Welcome ' + this.contactName + '!', 'success');
                this.setupSessionTimeout();
            } else {
                console.warn('GuestUserPortal: No contact found for email:', this.email);
                this.showToast('Error', 'No registered contact found for this email. Please contact support.', 'error');
                this.isOtpVerified = false;
            }
        } catch (error) {
            console.error('GuestUserPortal: Error loading contact details:', error);
            this.showToast('Error', 'Failed to load contact details: ' + (error.body ? error.body.message : error.message), 'error');
        }
    }

    /**
     * Received from c-case-l-o-a-form when a guest user clicks the case action row.
     * Switches the My Cases tab from list view to full inline case detail view.
     */
    handleShowCaseDetail(event) {
        const caseId = event.detail && event.detail.caseId;
        if (caseId) {
            console.log('GuestUserPortal: Showing inline case detail for caseId:', caseId);
            this.selectedGuestCaseId = caseId;
        }
    }

    /**
     * Returns from the inline case detail view back to the case list.
     */
    handleBackToCaseList() {
        console.log('GuestUserPortal: Back to case list');
        this.selectedGuestCaseId = null;
    }

    /**
     * Show toast notification
     */
    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
            mode: 'dismissable'
        });
        this.dispatchEvent(event);
    }

    // =====================================
    // SESSION TIMEOUT LOGIC
    // =====================================

    setupSessionTimeout() {
        if (!this._eventsBound && typeof window !== 'undefined') {
            this._boundResetSessionTimer = this.resetSessionTimer.bind(this);
            // Listen to broad user interactions
            window.addEventListener('mousemove', this._boundResetSessionTimer);
            window.addEventListener('keydown', this._boundResetSessionTimer);
            window.addEventListener('scroll', this._boundResetSessionTimer);
            window.addEventListener('click', this._boundResetSessionTimer);
            this._eventsBound = true;
        }
        this.resetSessionTimer();
    }

    resetSessionTimer() {
        // Clear existing timer if any
        if (this._timeoutId) {
            clearTimeout(this._timeoutId);
        }
        // Start a new 5 minute timer
        this._timeoutId = setTimeout(() => {
            this.handleSessionTimeout();
        }, this._timeoutDuration);
    }

    handleSessionTimeout() {
        console.log('GuestUserPortal: Session timed out due to inactivity.');
        this.showToast('Session Expired', 'Your session has timed out due to 5 minutes of inactivity. Please log in again.', 'warning');
        
        // Clear state
        this.isOtpVerified = false;
        this.email = '';
        this.contactId = '';
        this.contactName = '';
        this.selectedGuestCaseId = null;
        
        // Clear session storage
        try {
            sessionStorage.removeItem('isOtpVerified');
            sessionStorage.removeItem('guestEmail');
            sessionStorage.removeItem('guestContactId');
            sessionStorage.removeItem('guestContactName');
        } catch(e) {}

        this.clearSessionEvents();
    }

    clearSessionEvents() {
        if (this._eventsBound && typeof window !== 'undefined') {
            window.removeEventListener('mousemove', this._boundResetSessionTimer);
            window.removeEventListener('keydown', this._boundResetSessionTimer);
            window.removeEventListener('scroll', this._boundResetSessionTimer);
            window.removeEventListener('click', this._boundResetSessionTimer);
            this._eventsBound = false;
        }
        if (this._timeoutId) {
            clearTimeout(this._timeoutId);
            this._timeoutId = null;
        }
    }
}