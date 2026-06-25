import { LightningElement, track, wire, api } from 'lwc';
import getFees from '@salesforce/apex/FeeController.getFees';
import getFeesForContact from '@salesforce/apex/FeeController.getFeesForContact';
import getPayments from '@salesforce/apex/PaymentController.getPayments';
import getPaymentsForContact from '@salesforce/apex/PaymentController.getPaymentsForContact';
import getInstallmentBreakageDetails from '@salesforce/apex/RazorpayController.getInstallmentBreakageDetails';
import getInstallmentTotalAmount from '@salesforce/apex/RazorpayController.getInstallmentTotalAmount';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import basePath from '@salesforce/community/basePath';
import { NavigationMixin } from 'lightning/navigation';

export default class MyFeesAndPayments extends NavigationMixin(LightningElement) {

    @api guestEmail;
    @api contactId;

    activeSections = ['fees', 'payments'];

    @track fees = [];
    @track isLoadingFees = true;
    @track feesError;
    wiredFeesResult;

    @track payments = [];
    @track isLoadingPayments = true;
    @track paymentsError;

    @track isFeeBreakageModalOpen = false;
    @track isLoadingBreakage = false;
    @track selectedFeeBreakdown = [];
    @track selectedTotalAmount = 0;
    @track selectedFeeId = null;

    @track isInstallmentFee = false;
    @track feeType = '';

    connectedCallback() {
        if (this.contactId) {
            console.log('myFeesAndPayments: Guest context detected. ContactId:', this.contactId);
            this.loadFeesForGuest();
            this.loadPaymentsForGuest();
        }
    }

    renderedCallback() {
        if (this.contactId && this.isLoadingFees && !this._guestDataLoaded) {
            this._guestDataLoaded = true;
            console.log('myFeesAndPayments: renderedCallback - loading guest data for:', this.contactId);
            this.loadFeesForGuest();
            this.loadPaymentsForGuest();
        }
    }

    loadFeesForGuest() {
        this.isLoadingFees = true;
        this.feesError = undefined;

        getFeesForContact({ contactId: this.contactId })
            .then(data => {
                console.log('✅ [Guest] Fees retrieved:', data);
                this.fees = this.mapFees(data);
                this.feesError = undefined;
                this.isLoadingFees = false;
            })
            .catch(error => {
                console.error('❌ [Guest] Error loading fees:', error);
                this.feesError = this.reduceErrors(error);
                this.fees = [];
                this.isLoadingFees = false;
            });
    }

    loadPaymentsForGuest() {
        this.isLoadingPayments = true;
        this.paymentsError = undefined;

        getPaymentsForContact({ contactId: this.contactId })
            .then(data => {
                console.log('✅ [Guest] Payments retrieved:', data);
                this.payments = this.mapPayments(data);
                this.paymentsError = undefined;
                this.isLoadingPayments = false;
            })
            .catch(error => {
                console.error('❌ [Guest] Error loading payments:', error);
                this.paymentsError = this.reduceErrors(error);
                this.payments = [];
                this.isLoadingPayments = false;
            });
    }

    @wire(getFees)
    wiredFees(result) {
        if (this.contactId) {
            return;
        }

        this.wiredFeesResult = result;
        const { error, data } = result;
        this.isLoadingFees = false;

        if (data) {
            console.log('✅ Fees retrieved:', data);
            this.fees = this.mapFees(data);
            this.feesError = undefined;
        } else if (error) {
            console.error('❌ Error loading fees:', error);
            this.feesError = this.reduceErrors(error);
            this.fees = [];
        }
    }

    @wire(getPayments)
    wiredPayments({ data, error }) {
        if (this.contactId) {
            return;
        }

        this.isLoadingPayments = false;

        if (data) {
            this.payments = this.mapPayments(data);
            this.paymentsError = undefined;
        } else if (error) {
            console.error('❌ Error loading payments:', error);
            this.paymentsError = this.reduceErrors(error);
            this.payments = [];
        }
    }

    /**
     * Extracts installment number from Fee_Type__c field
     * e.g., "Installment 1" -> 1, "Installment 2" -> 2
     */
    extractInstallmentNumber(feeType) {
        if (!feeType) return null;
        
        const match = feeType.match(/Installment\s+(\d+)/i);
        return match ? parseInt(match[1], 10) : null;
    }

    /**
     * Checks if all previous installments are paid for the same program enrollment
     */
    checkPreviousInstallmentsPaid(allFees, currentFee, currentInstallmentNumber) {
        if (currentInstallmentNumber === null || currentInstallmentNumber === 1) {
            return true;
        }
        
        const currentProgramEnrollmentId = currentFee.ISB_Installment__r?.Program_Enrollment__c;
        
        if (!currentProgramEnrollmentId) {
            console.warn('⚠️ Cannot identify Program Enrollment for installment validation');
            return false;
        }
        
        for (let i = 1; i < currentInstallmentNumber; i++) {
            const previousInstallmentPaid = allFees.some(wrapper => {
                const fee = wrapper.fee;
                
                const sameProgramEnrollment = fee.ISB_Installment__r?.Program_Enrollment__c === currentProgramEnrollmentId;
                const installmentNumber = this.extractInstallmentNumber(fee.Fee_Type__c);
                const isTargetInstallment = installmentNumber === i;
                const isPaid = fee.Fee_Status__c === 'Paid';
                
                return sameProgramEnrollment && isTargetInstallment && isPaid;
            });
            
            if (!previousInstallmentPaid) {
                console.log(`🚫 Installment ${currentInstallmentNumber} blocked: Installment ${i} not paid yet`);
                return false;
            }
        }
        
        console.log(`✅ All previous installments paid for Installment ${currentInstallmentNumber}`);
        return true;
    }

    mapFees(data) {
        return data.map(wrapper => {
            const record = wrapper.fee;
            const hasInitiatedPayment = wrapper.hasInitiatedPayment;

            const totalAmount = record.Total_amount__c || 0;
            const paidAmount = record.Paid_Amount__c || 0;
            const pendingAmount = record.Pending_Amount__c || 0;

            const isPaid = record.Fee_Status__c === 'Paid';
            const isUnderVerification = !isPaid && hasInitiatedPayment && (pendingAmount === 0);
            const isInstallmentFee = record.Fee_Type__c && record.Fee_Type__c.includes('Installment');

            const today = new Date();
            today.setHours(0, 0, 0, 0);

            let dueDate = null;
            let canPayNow = false;
            let isOverdue = false;
            let isPaymentNotYetAvailable = false;
            let isPreviousInstallmentNotPaid = false;
            let paymentAvailableFromDate = '';
            let formattedDueDate = '';

            if (record.Due_Date__c) {
                dueDate = new Date(record.Due_Date__c);
                dueDate.setHours(0, 0, 0, 0);

                const windowDays = record.Payment_Window__c != null ? record.Payment_Window__c : 0;
                const paymentWindowStart = new Date(dueDate);
                paymentWindowStart.setDate(paymentWindowStart.getDate() - windowDays);

                formattedDueDate = this.formatDate(dueDate);
                paymentAvailableFromDate = this.formatDate(paymentWindowStart);

                if (!isPaid && !isUnderVerification) {
                    const isPaymentWindowOpen = today >= paymentWindowStart;
                    
                    if (isInstallmentFee) {
                        const currentInstallmentNumber = this.extractInstallmentNumber(record.Fee_Type__c);
                        const arePreviousInstallmentsPaid = this.checkPreviousInstallmentsPaid(
                            data, 
                            record, 
                            currentInstallmentNumber
                        );
                        
                        canPayNow = isPaymentWindowOpen && arePreviousInstallmentsPaid;
                        isPreviousInstallmentNotPaid = !arePreviousInstallmentsPaid;
                    } else {
                        canPayNow = isPaymentWindowOpen;
                    }
                    
                    isOverdue = today > dueDate;
                    isPaymentNotYetAvailable = !isPreviousInstallmentNotPaid && today < paymentWindowStart;
                }
            }

            let cohortName = 'N/A';
            if (record.ISB_Installment__r?.Program_Enrollment__r?.Academic_Term__r?.Name) {
                cohortName = record.ISB_Installment__r.Program_Enrollment__r.Academic_Term__r.Name;
            }

            return {
                ...record,
                cohortName: cohortName,
                isInstallmentFee: isInstallmentFee,
                displayAmount: totalAmount,
                isPaid: isPaid,
                isUnderVerification: isUnderVerification,
                canPayNow: canPayNow,
                isOverdue: isOverdue,
                isPaymentNotYetAvailable: isPaymentNotYetAvailable,
                isPreviousInstallmentNotPaid: isPreviousInstallmentNotPaid,
                paymentAvailableFromDate: paymentAvailableFromDate,
                formattedDueDate: formattedDueDate
            };
        });
    }

    handlePaymentClick(event) {
        event.preventDefault();
        const paymentId = event.currentTarget.dataset.id;
        const paymentName = event.currentTarget.dataset.name;

        console.log('💳 Payment clicked - ID:', paymentId, 'Name:', paymentName);

        // Get the base URL of the community
        const baseUrl = window.location.origin + basePath;
        const paymentDetailsUrl = baseUrl + '/payment-details?paymentId=' + paymentId + '&paymentName=' + paymentName;
        
        console.log('🔗 Navigating to:', paymentDetailsUrl);
        
        // Direct navigation to the payment details page
        window.location.href = paymentDetailsUrl;
    }

    mapPayments(data) {
        console.log('=== START mapPayments ===');
        console.log('📊 Total payments received:', data ? data.length : 0);
        console.log('📋 Raw payment data:', JSON.stringify(data, null, 2));

        const sitePrefix = basePath.replace(/\/s$/i, '');

        return data.map(p => {
            const isSuccess = p.Initiated__c === 'Success';
            const comments = p.Case__r?.Comments__c || '—';
            const hasComments = !!(p.Case__r?.Comments__c);
            const isSAPPayment = p.SAP_Payment_Collected__c === true;

            console.log('  - comments:', comments);
            console.log('  - hasComments:', hasComments);
            console.log('  - isSAPPayment:', isSAPPayment);
            return {
                ...p,
                paymentDate: this.formatDate(new Date(p.CreatedDate)),
                formattedAmount: this.formatCurrency(p.Amount_Paid__c),
                paymentType: p.Payment_Type__c || '—',
                isSuccess: isSuccess,
                statusClass: isSuccess ? 'status-success' : 'status-failed',
                comments: comments,
                hasComments: hasComments,
                isSAPPayment: isSAPPayment
            };
        });
    }

    handlePaymentSuccess() {
        console.log('🔄 Payment completed - Refreshing data...');
        if (this.contactId) {
            this.loadFeesForGuest();
            this.loadPaymentsForGuest();
        } else {
            setTimeout(() => {
                window.location.reload();
            }, 200);
        }
    }

    handleViewFeeBreakage(event) {
        const feeId = event.currentTarget.dataset.recordId;
        event.preventDefault();

        console.log('📊 Opening Fee Breakage for Fee:', feeId);

        this.selectedFeeId = feeId;
        this.isFeeBreakageModalOpen = true;
        this.isLoadingBreakage = true;

        Promise.all([
            getInstallmentBreakageDetails({ feeId: feeId }),
            getInstallmentTotalAmount({ feeId: feeId })
        ])
            .then(([breakageDetails, totalAmount]) => {
                console.log('✅ Fee Breakage Details:', breakageDetails);
                console.log('✅ Total Amount:', totalAmount);

                const processedBreakdown = this.sortFeeBreakdown(breakageDetails || []).map(item => {
                    return {
                        ...item,
                        hasScholarship: this.isTuitionFee(item.feeType) &&
                            item.scholarshipAmount != null &&
                            item.scholarshipAmount > 0,
                        netAmount: item.amount - (item.scholarshipAmount || 0)
                    };
                });

                this.selectedFeeBreakdown = processedBreakdown;
                this.selectedTotalAmount = totalAmount || 0;
                this.isLoadingBreakage = false;
            })
            .catch(error => {
                console.error('❌ Error fetching fee breakage:', error);
                this.showToast('Error', 'Failed to load fee breakage details', 'error');
                this.isLoadingBreakage = false;
                this.isFeeBreakageModalOpen = false;
            });
    }

    isTuitionFee(feeType) {
        if (!feeType) return false;
        return feeType.toLowerCase().includes('tuition');
    }

    closeFeeBreakageModal() {
        this.isFeeBreakageModalOpen = false;
        this.selectedFeeBreakdown = [];
        this.selectedTotalAmount = 0;
        this.selectedFeeId = null;
    }

    sortFeeBreakdown(breakdown) {
        if (!breakdown || breakdown.length === 0) {
            return breakdown;
        }

        const lateFees = [];
        const otherFees = [];

        breakdown.forEach(item => {
            if (item.feeType && item.feeType.toLowerCase().includes('late fee')) {
                lateFees.push(item);
            } else {
                otherFees.push(item);
            }
        });

        return [...otherFees, ...lateFees];
    }

    get hasFees() {
        return this.fees && this.fees.length > 0;
    }

    get totalFees() {
        return this.fees ? this.fees.length : 0;
    }

    get pluralSuffixFees() {
        return this.totalFees === 1 ? '' : 's';
    }

    handleDownloadInvoice(event) {
        const paymentId = event.target.dataset.id;
        const sitePrefix = basePath.split('/s')[0] || '';
        const url = `${window.location.origin}${sitePrefix}/apex/ISBPaymentReceipt?id=${paymentId}`;
        console.log('DownloadInvoice: Initiating download for ID:', paymentId, 'URL:', url);
        window.open(url, '_blank');
    }

    get hasPayments() {
        return this.payments.length > 0;
    }

    get totalPayments() {
        return this.payments.length;
    }

    get pluralSuffixPayments() {
        return this.totalPayments === 1 ? '' : 's';
    }

    get isGuest() {
        return !!this.contactId;
    }

    formatDate(date) {
        if (!date) return '';

        return new Intl.DateTimeFormat('en-IN', {
            year: 'numeric',
            month: 'short',
            day: '2-digit'
        }).format(date);
    }

    formatCurrency(amount) {
        if (amount == null) return '—';

        return new Intl.NumberFormat('en-IN', {
            style: 'currency',
            currency: 'INR',
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        }).format(amount);
    }

    reduceErrors(errors) {
        if (!Array.isArray(errors)) {
            errors = [errors];
        }

        return (
            errors
                .filter((error) => !!error)
                .map((error) => {
                    if (Array.isArray(error.body)) {
                        return error.body.map((e) => e.message);
                    }
                    else if (error?.body?.pageErrors && error.body.pageErrors.length > 0) {
                        return error.body.pageErrors.map((e) => e.message);
                    }
                    else if (error?.body?.fieldErrors && Object.keys(error.body.fieldErrors).length > 0) {
                        const fieldErrors = [];
                        Object.values(error.body.fieldErrors).forEach((errorArray) => {
                            fieldErrors.push(...errorArray.map((e) => e.message));
                        });
                        return fieldErrors;
                    }
                    else if (error?.body?.message) {
                        return error.body.message;
                    }
                    else if (error?.message) {
                        return error.message;
                    }
                    return 'Unknown error';
                })
                .reduce((prev, curr) => prev.concat(curr), [])
                .filter((message, index, self) => self.indexOf(message) === index)
                .join(', ')
        );
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
            mode: 'dismissable'
        });
        this.dispatchEvent(event);
    }
}