import { LightningElement, api, track } from 'lwc';
import getCasePaymentAmount from '@salesforce/apex/CasePaymentController.getCasePaymentAmount';
import getRazorpayKey from '@salesforce/apex/CasePaymentController.getRazorpayKey';
import createOrder from '@salesforce/apex/CasePaymentController.createOrder';
import createRejoinPayment from '@salesforce/apex/CasePaymentController.createRejoinPayment';

import razorpayCheckout from '@salesforce/resourceUrl/razorpay';
import { loadScript } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class CaseRejoinPayment extends LightningElement {

    @api recordId;  // Case Id
    @track isModalOpen = false;
    @track amount = 0;
    razorpayLoaded = false;
    paymentMode;
    connectedCallback() {
                console.log('inside js ');
        this.loadRazorpay();
        this.fetchCaseAmount();
        console.log('inside js ');
    }
    loadRazorpay() {
        if (this.razorpayLoaded) return;

        loadScript(this, razorpayCheckout)
            .then(() => {
                this.razorpayLoaded = true;
            })
            .catch(err => {
                console.error(err);
                this.showToast('Error', 'Razorpay SDK Failed to Load', 'error');
            });
    }

    fetchCaseAmount() {
        getCasePaymentAmount({ caseId: this.recordId })
            .then(res => {
                console.log('amount',res);
                this.amount = res;
            })
            .catch(err => console.error(err));
    }

    openModal() {
        console.log('hu');
        this.isModalOpen = true;
    }
    
    closeModal() {
        this.isModalOpen = false;
    }

    handlePay() {
        Promise.all([
            getRazorpayKey(),
            createOrder({ amount: this.amount })
        ])
        .then(([key, orderResponse]) => {
            const order = JSON.parse(orderResponse);
            this.openCheckout({
                key_id: key,
                orderId: order.id,
                amount: order.amount,
                currency: order.currency
            });
        })
        .catch(error => {
            console.error('Payment Initialization Failed', error);
            this.showToast('Error', 'Payment start failed', 'error');
        });
    }

    openCheckout(obj) {
        let options = {
            key: obj.key_id,
            amount: obj.amount,
            currency: obj.currency,
            name: 'Rejoin Fee Payment',
            description: 'Case Rejoin Payment',
            order_id: obj.orderId,

            handler: (response) => {
                this.paymentMode = response.method;
                this.savePaymentRecord();
            }
        };

        const rzp = new window.Razorpay(options);
        rzp.open();
    }

    savePaymentRecord() {
        createRejoinPayment({
            caseId: this.recordId,
            amountPaid: this.amount,
            status: 'Success',
            paymentMode: this.paymentMode
        })
        .then(() => {
            this.showToast('Success', 'Payment Completed Successfully', 'success');
            this.isModalOpen = false;
        })
        .catch(err => {
            console.error(err);
            this.showToast('Error', 'Payment done but saving failed', 'error');
        });
    }

    showToast(title, msg, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message: msg, variant }));
    }
}