import { LightningElement, track, wire } from 'lwc';
import verifyEmailAndSendOTP from '@salesforce/apex/PseudoCasePortalController.verifyEmailAndSendOTP';
import resendOTP from '@salesforce/apex/PseudoCasePortalController.resendOTP';
import getCaseRecordTypes from '@salesforce/apex/PseudoCasePortalController.getCaseRecordTypes';
import getProgramEnrollmentsForContact from '@salesforce/apex/PseudoCasePortalController.getProgramEnrollmentsForContact';
import getTermsForProgramEnrollment from '@salesforce/apex/PseudoCasePortalController.getTermsForProgramEnrollment';
import createCaseRequest from '@salesforce/apex/PseudoCasePortalController.createCaseRequest';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class PseudoCasePortal extends LightningElement {
    // Step 1: Email Entry
    @track email = '';
    @track emailError = '';
    
    // Step 2: OTP Verification
    @track otp = '';
    @track otpError = '';
    @track isResending = false;
    
    // OTP Storage (client-side)
    storedOtp = '';
    otpExpiryTime = null;
    OTP_EXPIRY_MINUTES = 10;
    
    // Step 3+: Case Request Form
    @track contactId;
    @track firstName = '';
    @track selectedRecordTypeId = '';
    @track selectedRecordTypeName = '';
    @track selectedPeId = '';
    @track selectedPeLabel = '';
    @track selectedEsId = '';
    @track selectedTermLabel = '';
    @track caseDescription = '';
    
    // Options
    @track recordTypeOptions = [];
    @track programEnrollmentOptions = [];
    @track termOptions = [];
    
    // UI State Control
    @track showEmailStep = true;
    @track showOtpStep = false;
    @track showRequestStep = false;
    @track isLoading = false;
    @track showSuccessScreen = false;
    @track createdCaseNumber = '';

    // ============================================
    // WIRE - Load Record Types
    // ============================================
    
    @wire(getCaseRecordTypes)
    wiredRecordTypes({ error, data }) {
        if (data) {
            this.recordTypeOptions = data.map(rt => ({
                label: rt.name,
                value: rt.id
            }));
            
            if (this.recordTypeOptions.length === 0) {
                this.showToast('Warning', 'No Case Record Types found. Please contact administrator.', 'warning');
            }
        } else if (error) {
            this.showToast('Error', 'Unable to load Case types: ' + this.normalizeError(error), 'error');
            this.recordTypeOptions = [];
        }
    }

    // ============================================
    // STEP 1: EMAIL VERIFICATION
    // ============================================
    
    handleEmailChange(event) {
        this.email = event.target.value?.trim();
        this.emailError = '';
    }

    async handleSendOTP() {
        this.emailError = '';
        
        if (!this.email) {
            this.emailError = 'Please enter your email address.';
            return;
        }
        
        // Basic email validation
        const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (!emailPattern.test(this.email)) {
            this.emailError = 'Please enter a valid email address.';
            return;
        }

        this.isLoading = true;
        
        try {
            const result = await verifyEmailAndSendOTP({ email: this.email });
            
            if (result && result.contactId) {
                this.contactId = result.contactId;
                this.firstName = result.firstName || '';
                
                // Store OTP with expiry time (client-side)
                this.storedOtp = result.otp;
                this.otpExpiryTime = new Date().getTime() + (this.OTP_EXPIRY_MINUTES * 60 * 1000);
                
                // Move to OTP step
                this.showEmailStep = false;
                this.showOtpStep = true;
                
                this.showToast('Success', result.message || 'OTP sent to your email', 'success');
            }
        } catch (error) {
            this.emailError = this.normalizeError(error);
        } finally {
            this.isLoading = false;
        }
    }

    // ============================================
    // STEP 2: OTP VERIFICATION (Client-Side)
    // ============================================
    
    handleOtpChange(event) {
        this.otp = event.target.value?.trim();
        this.otpError = '';
    }

    handleVerifyOTP() {
        this.otpError = '';
        
        if (!this.otp) {
            this.otpError = 'Please enter the OTP sent to your email.';
            return;
        }
        
        if (this.otp.length !== 6) {
            this.otpError = 'OTP must be 6 digits.';
            return;
        }

        // Check if OTP has expired
        const currentTime = new Date().getTime();
        if (currentTime > this.otpExpiryTime) {
            this.otpError = 'OTP has expired. Please request a new one.';
            return;
        }

        // Verify OTP matches
        if (this.otp !== this.storedOtp) {
            this.otpError = 'Invalid OTP. Please try again.';
            return;
        }

        // OTP verified successfully
        this.isLoading = true;
        
        // Clear stored OTP
        this.storedOtp = '';
        this.otpExpiryTime = null;
        
        // Load Program Enrollments
        this.loadProgramEnrollments()
            .then(() => {
                // Move to request form
                this.showOtpStep = false;
                this.showRequestStep = true;
                
                this.showToast('Success', 'Email verified successfully!', 'success');
            })
            .catch(error => {
                this.otpError = this.normalizeError(error);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    async handleResendOTP() {
        this.isResending = true;
        this.otpError = '';
        
        try {
            const result = await resendOTP({ email: this.email });
            
            // Store new OTP with expiry time (client-side)
            this.storedOtp = result.otp;
            this.otpExpiryTime = new Date().getTime() + (this.OTP_EXPIRY_MINUTES * 60 * 1000);
            
            this.showToast('Success', result.message || 'OTP resent successfully', 'success');
            
            // Clear OTP field
            this.otp = '';
        } catch (error) {
            this.otpError = this.normalizeError(error);
            this.showToast('Error', this.normalizeError(error), 'error');
        } finally {
            this.isResending = false;
        }
    }

    handleBackToEmail() {
        this.showOtpStep = false;
        this.showEmailStep = true;
        this.otp = '';
        this.otpError = '';
        this.storedOtp = '';
        this.otpExpiryTime = null;
    }

    // ============================================
    // STEP 3: CASE REQUEST FORM
    // ============================================
    
    async loadProgramEnrollments() {
        try {
            const pes = await getProgramEnrollmentsForContact({ contactId: this.contactId });
            
            this.programEnrollmentOptions = (pes || []).map(pe => ({
                label: pe.Program?.Name || pe.Name,
                value: pe.Id
            }));

            if (this.programEnrollmentOptions.length === 0) {
                this.showToast('Warning', 'No Program Enrollments found.', 'warning');
            }
        } catch (error) {
            this.showToast('Error', this.normalizeError(error), 'error');
        }
    }

    handleRecordTypeChange(event) {
        this.selectedRecordTypeId = event.detail.value;
        const selected = this.recordTypeOptions.find(opt => opt.value === this.selectedRecordTypeId);
        this.selectedRecordTypeName = selected ? selected.label : '';
    }

    async handlePeChange(event) {
        this.selectedPeId = event.detail.value;
        const sel = this.programEnrollmentOptions.find(o => o.value === this.selectedPeId);
        this.selectedPeLabel = sel ? sel.label : '';

        // Load terms for selected program enrollment
        this.termOptions = [];
        this.selectedEsId = '';
        this.selectedTermLabel = '';

        if (!this.selectedPeId) return;

        try {
            const terms = await getTermsForProgramEnrollment({ 
                programEnrollmentId: this.selectedPeId 
            });
            
            this.termOptions = (terms || []).map(t => ({
                label: `${t.termName}${t.status ? ' (' + t.status + ')' : ''}`,
                value: t.enrollmentSessionId
            }));
        } catch (error) {
            this.showToast('Error', 'Unable to load terms', 'error');
            this.termOptions = [];
        }
    }

    handleTermChange(event) {
        this.selectedEsId = event.detail.value;
        const sel = this.termOptions.find(o => o.value === this.selectedEsId);
        this.selectedTermLabel = sel ? sel.label : '';
    }

    handleDescriptionChange(event) {
        this.caseDescription = event.target.value;
    }

    // ============================================
    // FORM SUBMISSION
    // ============================================
    
    get isFormValid() {
        return this.selectedRecordTypeId && 
               this.selectedPeId && 
               this.selectedEsId && 
               this.caseDescription?.trim().length > 0;
    }

    get isTermDisabled() {
        return !this.selectedPeId;
    }

    async handleSubmitCase() {
        if (!this.isFormValid) {
            this.showToast('Error', 'Please fill in all required fields.', 'error');
            return;
        }

        this.isLoading = true;

        try {
            const caseData = {
                contactId: this.contactId,
                subject: `${this.selectedRecordTypeName} Request - ${this.selectedPeLabel}`,
                description: this.caseDescription,
                recordTypeId: this.selectedRecordTypeId,
                requestType: this.selectedRecordTypeName,
                programEnrollmentId: this.selectedPeId,
                enrollmentSessionId: this.selectedEsId
            };

            const result = await createCaseRequest({ caseData: caseData });
            
            if (result && result.status === 'success') {
                // Store Case Number for display
                this.createdCaseNumber = result.caseNumber;
                
                this.showRequestStep = false;
                this.showSuccessScreen = true;
                
                this.showToast('Success', 'Your request has been submitted successfully!', 'success');
            }
        } catch (error) {
            this.showToast('Error', this.normalizeError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleStartNew() {
        // Reset all fields
        this.resetForm();
        this.showSuccessScreen = false;
        this.showEmailStep = true;
    }

    resetForm() {
        this.email = '';
        this.otp = '';
        this.contactId = null;
        this.selectedRecordTypeId = '';
        this.selectedRecordTypeName = '';
        this.selectedPeId = '';
        this.selectedEsId = '';
        this.caseDescription = '';
        this.emailError = '';
        this.otpError = '';
        this.storedOtp = '';
        this.otpExpiryTime = null;
        this.programEnrollmentOptions = [];
        this.termOptions = [];
        this.createdCaseNumber = '';
    }

    // ============================================
    // UTILITY METHODS
    // ============================================

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
            mode: 'dismissable'
        }));
    }

    normalizeError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map(e => e.message).join(', ');
        } else if (error?.body?.message) {
            return error.body.message;
        } else if (error?.message) {
            return error.message;
        }
        return 'Something went wrong. Please try again.';
    }
}