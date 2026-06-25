import { LightningElement, track } from 'lwc';
import sendOtp from '@salesforce/apex/GuestOtpAuthService.sendOtp';
import verifyOtp from '@salesforce/apex/GuestOtpAuthService.verifyOtp';

export default class GuestOtpAuth extends LightningElement {

    @track email;
    @track otp;
    @track otpSent = false;
    @track verified = false;
    @track errorMessage;
    @track otpErrorMessage;
    @track isLoading = false;
    @track otpInputError = false;
    @track maxAttemptsExceeded = false;

    handleEmail(e) {
        this.email = e.target.value;
        this.errorMessage = undefined;
        console.log('GuestOtpAuth: Email changed to ' + this.email);
    }

    handleOtp(e) {
        this.otp = e.target.value;
        // Clear error message when user starts typing
        this.otpErrorMessage = undefined;
        this.otpInputError = false;
        console.log('GuestOtpAuth: OTP input changed');
    }

    sendOtp() {
        console.log('GuestOtpAuth: invoking sendOtp for email ' + this.email);
        this.errorMessage = undefined;
        this.maxAttemptsExceeded = false; // Reset lockout state when requesting new OTP
        this.isLoading = true;

        // Client-side domain validation
        if (!this.email || !this.email.includes('@')) {
            this.errorMessage = '❌ Please enter a valid email address.';
            this.isLoading = false;
            return;
        }

        const emailDomain = this.email.toLowerCase().split('@')[1];
        if (emailDomain !== 'isb.edu' && emailDomain !== 'yopmail.com') {
            this.errorMessage = '❌ Only isb.edu email domains are allowed.';
            this.isLoading = false;
            return;
        }

        sendOtp({ email: this.email })
            .then(result => {
                this.isLoading = false;
                if (result === 'SUCCESS') {
                    console.log('✅ GuestOtpAuth: OTP sent successfully');
                    this.otpSent = true;
                    this.errorMessage = '✅ OTP sent to ' + this.email + '. Valid for 10 minutes.';
                } else {
                    console.error('❌ GuestOtpAuth: sendOtp returned error: ', result);
                    this.errorMessage = '❌ ' + result;
                }
            })
            .catch(e => {
                this.isLoading = false;
                console.error('❌ GuestOtpAuth: sendOtp error: ', JSON.stringify(e));
                this.errorMessage = '❌ ' + (e.body ? e.body.message : e.message);
            });
    }

    verifyOtp() {
        console.log('🔵 GuestOtpAuth: invoking verifyOtp with code ' + this.otp);
        
        // Client-side validation
        if (!this.otp || this.otp.length !== 6 || isNaN(this.otp)) {
            this.otpErrorMessage = '❌ Please enter a valid 6-digit OTP.';
            this.otpInputError = true;
            return;
        }

        this.isLoading = true;
        this.otpErrorMessage = undefined;
        this.otpInputError = false;

        verifyOtp({ email: this.email, otp: this.otp })
            .then(result => {
                this.isLoading = false;
                if (result && typeof result === 'string' && result.startsWith('ERROR:')) {
                    const errorMsg = result.substring(6);
                    console.error('❌ GuestOtpAuth: verifyOtp business error: ', errorMsg);
                    this.handleVerifyError(errorMsg);
                    return;
                }

                console.log('✅ GuestOtpAuth: verifyOtp successful. Result: ' + result);
                this.verified = result;
                
                if (this.verified) {
                    console.log('✅ GuestOtpAuth: Dispatching verified event with ID: ' + this.verified + ' and email: ' + this.email);
                    this.dispatchEvent(new CustomEvent('verified', { 
                        detail: { userId: this.verified, email: this.email },
                        bubbles: true,
                        composed: true
                    }));
                }
            })
            .catch(e => {
                this.isLoading = false;
                const errorMsg = e.body?.message || e.message;
                console.error('❌ GuestOtpAuth: verifyOtp error: ', errorMsg);
                this.handleVerifyError(errorMsg);
            });
    }

    handleVerifyError(errorMsg) {
        if (errorMsg.includes('Incorrect OTP')) {
            this.otpErrorMessage = errorMsg;
            this.otpInputError = true;
        } else if (errorMsg.includes('Maximum attempts exceeded')) {
            this.otpErrorMessage = errorMsg;
            this.otpInputError = true;
            this.maxAttemptsExceeded = true;
        } else if (errorMsg.includes('OTP expired')) {
            this.otpErrorMessage = '❌ OTP expired. Please request a new OTP.';
            this.otpSent = false;
            this.otpInputError = true;
        } else if (errorMsg.includes('OTP request not found')) {
            this.otpErrorMessage = '❌ OTP request not found. Please send OTP again.';
            this.otpSent = false;
            this.otpInputError = true;
        } else {
            this.otpErrorMessage = '❌ ' + errorMsg;
            this.otpInputError = true;
        }
    }

    // Dynamic CSS classes for OTP input error state
    get otpInputContainerClass() {
        return this.otpInputError ? 'slds-m-bottom_small otp-input-error' : 'slds-m-bottom_small';
    }

    get otpInputClass() {
        return this.otpInputError ? 'otp-input-invalid' : '';
    }
}