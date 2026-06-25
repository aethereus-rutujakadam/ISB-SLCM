import { LightningElement, track, wire } from 'lwc';
import getInstallments from '@salesforce/apex/InstallmentController.getInstallments';
import getCurrentUserContactInfo from '@salesforce/apex/InstallmentController.getCurrentUserContactInfo';
import getInstallmentBreakageDetails from '@salesforce/apex/RazorpayController.getInstallmentBreakageDetails';
import getInstallmentTotalAmount from '@salesforce/apex/RazorpayController.getInstallmentTotalAmount';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import basePath from '@salesforce/community/basePath';


export default class InstallmentListView extends LightningElement {
    @track installments = [];
    @track isLoading = true;
    @track error;

    // Fee Breakage Modal
    @track isFeeBreakageModalOpen = false;
    @track isLoadingBreakage = false;
    @track selectedFeeBreakdown = [];
    @track selectedTotalAmount = 0;
    @track selectedInstallmentId = null;

    // Store wired result for refresh
    wiredInstallmentsResult;

    // ✅ CONSTANTS
    PAYMENT_WINDOW_DAYS = 3;

    // Wire the Apex method to fetch installments
    @wire(getInstallments)
    wiredInstallments(result) {
        this.wiredInstallmentsResult = result;
        const { error, data } = result;
        this.isLoading = false;

        if (data) {
            console.log('✅ Installments retrieved:', data);

            this.installments = data.map(wrapper => {
                const record = wrapper.installment;
                const hasInitiatedPayment = wrapper.hasInitiatedPayment;

                // Extract Payment ID
                let relatedPaymentId = null;
                if (record.ISB_Payments__r && record.ISB_Payments__r.length > 0) {
                    relatedPaymentId = record.ISB_Payments__r[0].Id;
                }

                // ✅ NEW PAYMENT STATUS LOGIC
                const totalAmount = record.Total_Amount_calc__c || 0;
                const paidAmount = record.Paid_Amount__c || 0;
                const pendingAmount = record.Pending_Amount__c || 0;

                // ✅ CORRECTED LOGIC:
                // 1. "Paid" → Paid_Amount equals Total_Amount (Finance approved)
                // 2. "Under Verification" → Pending = 0 BUT Paid_Amount ≠ Total_Amount (awaiting approval)
                // 3. "Can Pay" → Neither of above conditions

                const isPaid = (paidAmount === totalAmount) && (totalAmount > 0); // ✅ Fully paid and approved
                const isUnderVerification = (pendingAmount === 0) && (paidAmount !== totalAmount); // ✅ Awaiting approval

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

                    // ✅ Allow payment ONLY if:
                    // 1. Not paid (Paid_Amount ≠ Total_Amount)
                    // 2. Not under verification (Pending ≠ 0 OR Paid_Amount = Total_Amount)
                    // 3. Within payment window
                    if (!isPaid && !isUnderVerification) {
                        canPayNow = today >= paymentWindowStart;
                        isOverdue = today > dueDate;
                        isPaymentNotYetAvailable = today < paymentWindowStart;
                    }
                }

                console.log('📊 Record:', record.Name, {
                    totalAmount,
                    paidAmount,
                    pendingAmount,
                    hasInitiatedPayment,
                    isPaid,
                    isUnderVerification,
                    canPayNow
                });

                return {
                    ...record,
                    programName: record.Program__r?.Name || 'N/A',
                    formattedAmount: this.formatCurrency(record.Total_Amount_calc__c),
                    isPaid: isPaid,
                    isUnderVerification: isUnderVerification,
                    paymentId: relatedPaymentId,
                    canPayNow: canPayNow,
                    isOverdue: isOverdue,
                    isPaymentNotYetAvailable: isPaymentNotYetAvailable,
                    paymentAvailableFromDate: paymentAvailableFromDate,
                    formattedDueDate: formattedDueDate
                };
            });

            this.error = undefined;

        } else if (error) {
            console.error('❌ Error loading installments:', error);
            this.error = this.reduceErrors(error);
            this.installments = [];
            this.showToast('Error', this.error, 'error');
        }
    }

    // ✅ Handle payment success event from child component
    handlePaymentSuccess() {
        console.log('🔄 Payment completed - Refreshing installments...');
        console.log('🔄 Re-rendering payment component');

        setTimeout(() => {
            window.location.reload();
        }, 200);


        // Show success message
        // this.showToast('Success', 'Payment submitted. Verification may take 1-2 business days.', 'success');

        // Refresh the installment list
        // this.refreshInstallments();
    }

    // ✅ Refresh installments data
    refreshInstallments() {
        this.isLoading = true;
        return refreshApex(this.wiredInstallmentsResult)
            .then(() => {
                console.log('✅ Installments refreshed successfully');
                this.isLoading = false;
            })
            .catch(error => {
                console.error('❌ Error refreshing installments:', error);
                this.isLoading = false;
            });
    }

    connectedCallback() {
        this.loadUserInfo();
    }

    loadUserInfo() {
        getCurrentUserContactInfo()
            .then(result => {
                console.log('👤 Current User Info:', result);
            })
            .catch(error => {
                console.error('Error loading user info:', error);
            });
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

    get hasInstallments() {
        return this.installments && this.installments.length > 0;
    }

    get totalInstallments() {
        return this.installments ? this.installments.length : 0;
    }

    get pluralSuffix() {
        return this.totalInstallments === 1 ? '' : 's';
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

    handleDownloadReceipt(event) {
        const paymentId = event.target.dataset.paymentId;

        if (paymentId) {
            const sitePrefix = basePath.replace(/\/s$/i, "");
            const vfPageName = 'ISBPaymentReceipt';
            const receiptUrl = `${window.location.origin}${sitePrefix}/apex/${vfPageName}?id=${paymentId}`;

            console.log('Opening Receipt URL:', receiptUrl);
            window.open(receiptUrl, '_blank');
        } else {
            console.warn('Download clicked but no Payment ID found.');
        }
    }

    handleRowClick(event) {
        event.preventDefault();
        event.stopPropagation();
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
                    else if (
                        error?.body?.pageErrors &&
                        error.body.pageErrors.length > 0
                    ) {
                        return error.body.pageErrors.map((e) => e.message);
                    }
                    else if (
                        error?.body?.fieldErrors &&
                        Object.keys(error.body.fieldErrors).length > 0
                    ) {
                        const fieldErrors = [];
                        Object.values(error.body.fieldErrors).forEach(
                            (errorArray) => {
                                fieldErrors.push(
                                    ...errorArray.map((e) => e.message)
                                );
                            }
                        );
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