import { LightningElement, track, wire } from 'lwc';
import getPayments from '@salesforce/apex/PaymentController.getPayments';
import basePath from '@salesforce/community/basePath';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';



export default class PaymentListView extends LightningElement {

    @track payments = [];
    @track isLoading = true;
    @track error;

    // @wire(getPayments)
    // wiredPayments({ data, error }) {
    //     this.isLoading = false;

    //     if (data) {
    //         this.payments = data.map(p => {
    //             const isSuccess = p.Payment_Status__c === 'Success';

    //             return {
    //                 ...p,
    //                 paymentDate: this.formatDate(p.CreatedDate),
    //                 formattedAmount: this.formatCurrency(p.Amount__c),
    //                 installmentName: p.ISB_Installment__r?.Name || '—',
    //                 isSuccess: isSuccess,
    //                 statusClass: isSuccess
    //                     ? 'status-success'
    //                     : 'status-failed'
    //             };
    //         });
    //         this.error = undefined;
    //     } else if (error) {
    //         this.error = error.body?.message || 'Unknown error';
    //         this.payments = [];
    //         this.showToast('Error', this.error, 'error');
    //     }
    // }

    @wire(getPayments)
wiredPayments({ data, error }) {
    console.log('🔄 wiredPayments called');
    this.isLoading = false;

    if (data) {
        console.log('✅ Raw Payments from Apex:', JSON.stringify(data));

        this.payments = data.map(p => {
            console.log('➡️ Processing payment:', p.Id);

            const isSuccess = p.Initiated__c === 'Success';

            return {
                ...p,
                paymentDate: this.formatDate(p.CreatedDate),
                formattedAmount: this.formatCurrency(p.Amount__c),
                paymentType: p.Payment_Type__c || '—',
                isSuccess: isSuccess,
                statusClass: isSuccess
                    ? 'status-success'
                    : 'status-failed'
            };
        });

        console.log('📦 Final Payments used in UI:', this.payments);
        this.error = undefined;

    } else if (error) {
        console.error('❌ Error from Apex:', JSON.stringify(error));
        this.error = error.body?.message || 'Unknown error';
        this.payments = [];
        this.showToast('Error', this.error, 'error');
    }
}


    get hasPayments() {
        return this.payments.length > 0;
    }

    get totalPayments() {
        return this.payments.length;
    }

    handleDownload(event) {
        const paymentId = event.target.dataset.id;
        const sitePrefix = basePath.replace(/\/s$/i, '');
        const url =
            `${window.location.origin}${sitePrefix}/apex/ISBPaymentReceipt?id=${paymentId}`;
        window.open(url, '_blank');
    }

    formatDate(dateVal) {
        return new Intl.DateTimeFormat('en-IN', {
            year: 'numeric',
            month: 'short',
            day: '2-digit'
        }).format(new Date(dateVal));
    }

    formatCurrency(amount) {
        return new Intl.NumberFormat('en-IN', {
            style: 'currency',
            currency: 'INR',
            minimumFractionDigits: 2
        }).format(amount);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }
}