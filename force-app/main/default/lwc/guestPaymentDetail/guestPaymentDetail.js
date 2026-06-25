import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getPaymentById from '@salesforce/apex/PaymentController.getPaymentById';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class GuestPaymentDetail extends LightningElement {
    @api paymentId;
    @track payment;
    @track isLoading = true;
    @track error;
    @wire(CurrentPageReference) pageRef;

    connectedCallback() {
        console.log('🔌 guestPaymentDetail Connected');
        console.log('📍 Current URL:', window.location.href);
        console.log('📍 window.location.search:', window.location.search);
        console.log('📍 window.location.hash:', window.location.hash);
        
        // Small delay to ensure page reference is available
        setTimeout(() => {
            this.loadPaymentData();
        }, 100);
    }

    async loadPaymentData() {
        try {
            this.isLoading = true;
            this.error = null;

            let id = this.paymentId;
            
            console.log('📍 Component @api paymentId:', id);
            
            // Try to get from CurrentPageReference state
            if (!id && this.pageRef) {
                console.log('📍 PageRef:', JSON.stringify(this.pageRef));
                if (this.pageRef.state) {
                    id = this.pageRef.state.paymentId;
                    console.log('✅ Payment ID from pageRef.state:', id);
                }
            }

            // Try to get from URL - multiple methods for robustness
            if (!id) {
                // Method 1: Standard URL parameters
                const urlParams = new URLSearchParams(window.location.search);
                id = urlParams.get('paymentId');
                if (id) {
                    console.log('✅ Payment ID from URL params (method 1):', id);
                }
            }

            // Method 2: Direct URL parsing (in case URLSearchParams fails)
            if (!id) {
                const match = window.location.href.match(/[?&]paymentId=([^&]*)/);
                if (match && match[1]) {
                    id = decodeURIComponent(match[1]);
                    console.log('✅ Payment ID from URL regex (method 2):', id);
                }
            }

            // Method 3: Hash parameters
            if (!id) {
                const hashParams = new URLSearchParams(window.location.hash.substring(1));
                id = hashParams.get('paymentId');
                if (id) {
                    console.log('✅ Payment ID from hash params (method 3):', id);
                }
            }

            if (!id) {
                throw new Error('No payment ID provided in URL or component properties. URL: ' + window.location.href);
            }

            console.log('📥 Loading payment details for ID:', id);
            
            // Fetch payment from Apex
            const result = await getPaymentById({ paymentId: id });
            
            if (result) {
                this.payment = this.formatPayment(result);
                console.log('✅ Payment loaded:', this.payment);
            } else {
                throw new Error('Payment not found');
            }
        } catch (err) {
            console.error('❌ Error loading payment:', err);
            this.error = err.message;
            this.showToast('Error', 'Failed to load payment details: ' + err.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    formatPayment(payment) {
        return {
            ...payment,
            paymentDate: this.formatDate(new Date(payment.CreatedDate)),
            formattedAmount: this.formatCurrency(payment.Amount_Paid__c),
            paymentType: payment.Payment_Type__c || '—'
        };
    }

    formatDate(date) {
        if (!date) return '—';
        return date.toLocaleDateString('en-IN', {
            year: 'numeric',
            month: 'long',
            day: 'numeric',
            hour: '2-digit',
            minute: '2-digit'
        });
    }

    formatCurrency(amount) {
        if (!amount) return '₹0.00';
        return '₹' + parseFloat(amount).toFixed(2);
    }

    get paymentStatus() {
        if (!this.payment) return '—';
        return this.payment.Initiated__c || 'Unknown';
    }

    get paymentStatusClass() {
        if (this.payment?.Initiated__c === 'Success') {
            return 'status-badge success';
        } else if (this.payment?.Initiated__c === 'Failed') {
            return 'status-badge failed';
        }
        return 'status-badge pending';
    }

    get statusBannerClass() {
        if (this.payment?.Initiated__c === 'Success') {
            return 'status-banner success-banner';
        } else if (this.payment?.Initiated__c === 'Failed') {
            return 'status-banner error-banner';
        }
        return 'status-banner pending-banner';
    }

    get statusIconName() {
        if (this.payment?.Initiated__c === 'Success') {
            return 'utility:success';
        } else if (this.payment?.Initiated__c === 'Failed') {
            return 'utility:error';
        }
        return 'utility:clock';
    }

    get paymentStatusMessage() {
        if (this.payment?.Initiated__c === 'Success') {
            return 'Payment Successful';
        } else if (this.payment?.Initiated__c === 'Failed') {
            return 'Payment Failed';
        }
        return 'Payment Processing';
    }

    get paymentMethodDisplay() {
        return this.payment?.Payment_Method__c || this.payment?.Payment_Mode__c || '—';
    }

    get paymentModeDisplay() {
        return this.payment?.Payment_Mode__c || this.payment?.mode_of_payment__c || '—';
    }

    get formattedCreatedDate() {
        if (!this.payment?.CreatedDate) return '—';
        return new Date(this.payment.CreatedDate).toLocaleDateString('en-IN', {
            year: 'numeric',
            month: 'long',
            day: 'numeric',
            hour: '2-digit',
            minute: '2-digit'
        });
    }

    get formattedAmount() {
        if (!this.payment?.Amount_Paid__c) return '₹0.00';
        return '₹' + parseFloat(this.payment.Amount_Paid__c).toFixed(2);
    }

    get hasErrorMessage() {
        return !!(this.payment?.Error_Message__c);
    }

    get errorDetails() {
        return this.payment?.Error_Message__c || '—';
    }

    get errorCode() {
        return this.payment?.Error_Code__c || '—';
    }

    get hasComments() {
        return !!(this.payment?.Case__r?.Comments__c);
    }

    get comments() {
        return this.payment?.Case__r?.Comments__c || '—';
    }

    get razorpayDetails() {
        if (!this.payment?.Payment_ID__c) {
            return null;
        }
        return {
            paymentId: this.payment.Payment_ID__c,
            orderId: this.payment.Payment_Order_Id__c,
            signature: this.payment.Payment_Signature__c ? 
                       this.payment.Payment_Signature__c.substring(0, 20) + '...' : '—'
        };
    }

    get offlinePaymentDetails() {
        const mode = this.payment?.Payment_Mode__c || this.payment?.mode_of_payment__c;
        
        console.log('🔍 offlinePaymentDetails getter called');
        console.log('   mode_of_payment__c:', this.payment?.mode_of_payment__c);
        console.log('   Payment_Mode__c:', this.payment?.Payment_Mode__c);
        console.log('   Final mode value:', mode);
        console.log('   Mode type:', typeof mode);
        console.log('   Mode trimmed:', mode?.trim());
        
        const trimmedMode = mode?.trim();
        
        if (trimmedMode === 'Cheque/DD') {
            console.log('✅ Matched: Cheque/DD');
            return {
                type: 'Cheque/DD',
                bankName: this.payment?.Bank_Name__c || '—',
                chequeNumber: this.payment?.Cheque_DD_Number__c || '—',
                transactionDate: this.payment?.Transaction_Date__c ? 
                               new Date(this.payment.Transaction_Date__c).toLocaleDateString('en-IN') : '—'
            };
        }
        
        if (trimmedMode === 'Bank Loan') {
            console.log('✅ Matched: Bank Loan');
            return {
                type: 'Bank Loan',
                bankName: this.payment?.Bank_Name__c || '—',
                chequeNumber: this.payment?.Cheque_DD_Number__c || '—',
                rtgsNeftNumber: this.payment?.RTGS_NEFT_Number__c || '—',
                transactionDate: this.payment?.Transaction_Date__c ? 
                               new Date(this.payment.Transaction_Date__c).toLocaleDateString('en-IN') : '—'
            };
        }
        
        if (trimmedMode === 'Corporate Sponsor') {
            console.log('✅ Matched: Corporate Sponsor');
            console.log('   Company Name:', this.payment?.Company_Name__c);
            console.log('   Cheque_No__c:', this.payment?.Cheque_No__c);
            console.log('   Bank_Name__c:', this.payment?.Bank_Name__c);
            console.log('   RTGS_NEFT_Number__c:', this.payment?.RTGS_NEFT_Number__c);
            return {
                type: 'Corporate Sponsor',
                companyName: this.payment?.Company_Name__c || '—',
                chequeNumber: this.payment?.Cheque_No__c || '—',
                bankName: this.payment?.Bank_Name__c || '—',
                rtgsNeftNumber: this.payment?.RTGS_NEFT_Number__c || '—',
                transactionDate: this.payment?.Transaction_Date__c ? 
                               new Date(this.payment.Transaction_Date__c).toLocaleDateString('en-IN') : '—'
            };
        }
        
        if (trimmedMode === 'Wire Transfer') {
            console.log('✅ Matched: Wire Transfer');
            return {
                type: 'Wire Transfer',
                bankName: this.payment?.Bank_Name__c || '—',
                rtgsNeftNumber: this.payment?.RTGS_NEFT_Number__c || '—',
                transactionDate: this.payment?.Transaction_Date__c ? 
                               new Date(this.payment.Transaction_Date__c).toLocaleDateString('en-IN') : '—'
            };
        }
        
        console.log('❌ No mode matched. Mode:', trimmedMode);
        return null;
    }

    get isChequeOrBankLoan() {
        return this.offlinePaymentDetails?.type === 'Cheque/DD' || 
               this.offlinePaymentDetails?.type === 'Bank Loan';
    }

    get isCorporateSponsor() {
        return this.offlinePaymentDetails?.type === 'Corporate Sponsor';
    }

    get isWireTransfer() {
        return this.offlinePaymentDetails?.type === 'Wire Transfer';
    }

    get hasRtgsNeft() {
        return this.offlinePaymentDetails?.rtgsNeftNumber && 
               this.offlinePaymentDetails.rtgsNeftNumber !== '—';
    }

    handleBackClick() {
        console.log('🔙 Back button clicked - Navigating to Fees and Payments tab');
        
        try {
            // Store the active tab preference in sessionStorage
            sessionStorage.setItem('switchToTab', 'feesPayments');
            console.log('✅ Stored tab preference in sessionStorage');
            
            // Navigate back to the previous page (guestUserPortal)
            window.history.back();
            console.log('✅ Navigating back');
        } catch (error) {
            console.error('❌ Error in handleBackClick:', error);
            // Fallback: just go back
            window.history.back();
        }
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }
}