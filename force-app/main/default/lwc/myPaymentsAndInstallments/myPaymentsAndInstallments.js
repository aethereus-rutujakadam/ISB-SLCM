import { LightningElement, track, wire } from 'lwc';
import getInstallments from '@salesforce/apex/InstallmentController.getInstallments';
import getPayments from '@salesforce/apex/PaymentController.getPayments';
import getInstallmentBreakageDetails from '@salesforce/apex/RazorpayController.getInstallmentBreakageDetails';
import getInstallmentTotalAmount from '@salesforce/apex/RazorpayController.getInstallmentTotalAmount';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import basePath from '@salesforce/community/basePath';

export default class MyPaymentsAndInstallments extends LightningElement {
    
    // Accordion
    activeSections = ['installments', 'payments']; // Both sections open by default
    
    // Installments
    @track installments = [];
    @track isLoadingInstallments = true;
    @track installmentsError;
    wiredInstallmentsResult;
    
    // Payments
    @track payments = [];
    @track isLoadingPayments = true;
    @track paymentsError;
    
    // Fee Breakage Modal
    @track isFeeBreakageModalOpen = false;
    @track isLoadingBreakage = false;
    @track selectedFeeBreakdown = [];
    @track selectedTotalAmount = 0;
    @track selectedInstallmentId = null;
    
    // Constants
    PAYMENT_WINDOW_DAYS = 3;

    // ========================================
    // INSTALLMENTS SECTION
    // ========================================

    @wire(getInstallments)
    wiredInstallments(result) {
        this.wiredInstallmentsResult = result;
        const { error, data } = result;
        this.isLoadingInstallments = false;

        if (data) {
            console.log('✅ Installments retrieved:', data);

            this.installments = data.map(wrapper => {
                const record = wrapper.installment;
                const hasInitiatedPayment = wrapper.hasInitiatedPayment;

                const totalAmount = record.Total_Amount_calc__c || 0;
                const paidAmount = record.Paid_Amount__c || 0;
                const pendingAmount = record.Pending_Amount__c || 0;

                const isPaid = (paidAmount === totalAmount) && (totalAmount > 0);
                const isUnderVerification = (pendingAmount === 0) && (paidAmount !== totalAmount);

                const today = new Date();
                today.setHours(0, 0, 0, 0);

                let dueDate = null;
                let canPayNow = false;
                let isOverdue = false;
                let isPaymentNotYetAvailable = false;
                let paymentAvailableFromDate = '';
                let formattedDueDate = '';

                if (record.Due_Date__c) {
                    dueDate = new Date(record.Due_Date__c);
                    dueDate.setHours(0, 0, 0, 0);

                    const paymentWindowStart = new Date(dueDate);
                    paymentWindowStart.setDate(paymentWindowStart.getDate() - this.PAYMENT_WINDOW_DAYS);

                    formattedDueDate = this.formatDate(dueDate);
                    paymentAvailableFromDate = this.formatDate(paymentWindowStart);

                    if (!isPaid && !isUnderVerification) {
                        canPayNow = today >= paymentWindowStart;
                        isOverdue = today > dueDate;
                        isPaymentNotYetAvailable = today < paymentWindowStart;
                    }
                }

                return {
                    ...record,
                    programName: record.Program__r?.Name || 'N/A',
                    isPaid: isPaid,
                    isUnderVerification: isUnderVerification,
                    canPayNow: canPayNow,
                    isOverdue: isOverdue,
                    isPaymentNotYetAvailable: isPaymentNotYetAvailable,
                    paymentAvailableFromDate: paymentAvailableFromDate,
                    formattedDueDate: formattedDueDate
                };
            });

            this.installmentsError = undefined;

        } else if (error) {
            console.error('❌ Error loading installments:', error);
            this.installmentsError = this.reduceErrors(error);
            this.installments = [];
        }
    }

    handlePaymentSuccess() {
        console.log('🔄 Payment completed - Refreshing page...');
        setTimeout(() => {
            window.location.reload();
        }, 200);
    }

    handleViewFeeBreakage(event) {
        event.preventDefault();
        const installmentId = event.currentTarget.dataset.recordId;

        console.log('📊 Opening Fee Breakage for Installment:', installmentId);

        this.selectedInstallmentId = installmentId;
        this.isFeeBreakageModalOpen = true;
        this.isLoadingBreakage = true;

        Promise.all([
            getInstallmentBreakageDetails({ installmentId: installmentId }),
            getInstallmentTotalAmount({ installmentId: installmentId })
        ])
            .then(([breakageDetails, totalAmount]) => {
                console.log('✅ Fee Breakage Details:', breakageDetails);
                console.log('✅ Total Amount:', totalAmount);

                this.selectedFeeBreakdown = this.sortFeeBreakdown(breakageDetails || []);
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

    closeFeeBreakageModal() {
        this.isFeeBreakageModalOpen = false;
        this.selectedFeeBreakdown = [];
        this.selectedTotalAmount = 0;
        this.selectedInstallmentId = null;
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

    get hasInstallments() {
        return this.installments && this.installments.length > 0;
    }

    get totalInstallments() {
        return this.installments ? this.installments.length : 0;
    }

    get pluralSuffixInstallments() {
        return this.totalInstallments === 1 ? '' : 's';
    }

    // ========================================
    // PAYMENTS SECTION
    // ========================================

    @wire(getPayments)
    wiredPayments({ data, error }) {
        console.log('🔄 wiredPayments called');
        this.isLoadingPayments = false;

        if (data) {
            console.log('✅ Raw Payments from Apex:', JSON.stringify(data));

            this.payments = data.map(p => {
                const isSuccess = p.Initiated__c === 'Success';

                return {
                    ...p,
                    paymentDate: this.formatDate(new Date(p.CreatedDate)),
                    formattedAmount: this.formatCurrency(p.Amount__c),
                    paymentType: p.Payment_Type__c || '—',
                    isSuccess: isSuccess,
                    statusClass: isSuccess ? 'status-success' : 'status-failed'
                };
            });

            console.log('📦 Final Payments used in UI:', this.payments);
            this.paymentsError = undefined;

        } else if (error) {
            console.error('❌ Error from Apex:', JSON.stringify(error));
            this.paymentsError = this.reduceErrors(error);
            this.payments = [];
        }
    }

    handleDownloadInvoice(event) {
        const paymentId = event.target.dataset.id;
        const sitePrefix = basePath.replace(/\/s$/i, '');
        const url = `${window.location.origin}${sitePrefix}/apex/ISBPaymentReceipt?id=${paymentId}`;
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

    // ========================================
    // UTILITY METHODS
    // ========================================

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