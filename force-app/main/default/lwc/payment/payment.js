import { LightningElement, track, api } from 'lwc';
import createOrder from '@salesforce/apex/RazorpayController.createOrder';
import getRazorpayKey from '@salesforce/apex/RazorpayController.getRazorpayKey';
import getInstallmentAmount from '@salesforce/apex/RazorpayController.getInstallmentAmount';
import createInitiatedPaymentRecord from '@salesforce/apex/RazorpayController.createInitiatedPaymentRecord';
import updatePaymentRecordToSuccess from '@salesforce/apex/RazorpayController.updatePaymentRecordToSuccess';
import saveOfflinePayment from '@salesforce/apex/RazorpayController.saveOfflinePayment';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import razorpayCheckout from '@salesforce/resourceUrl/razorpay';
import { loadScript } from 'lightning/platformResourceLoader';
import getInstallmentBreakageDetails from '@salesforce/apex/RazorpayController.getInstallmentBreakageDetails';
import processInstallmentFromMaster from '@salesforce/apex/RazorpayController.processInstallmentFromMaster';
import getPreviousPayments from '@salesforce/apex/RazorpayController.getPreviousPayments';
import getInstallmentTotalAmount from '@salesforce/apex/RazorpayController.getInstallmentTotalAmount';
import updatePaymentRecordToFailed from '@salesforce/apex/RazorpayController.updatePaymentRecordToFailed';
import updateBreakageRecords from '@salesforce/apex/RazorpayController.updateBreakageRecords';
import getLoanDetails from '@salesforce/apex/RazorpayController.getLoanDetails';

import wireInfoPdf from '@salesforce/resourceUrl/Wire_Transfer_Info';


export default class RazorpayPayment extends LightningElement {
    @api recordId;
    @track isModalOpen = false;
    @track totalFees = 0;
    @track feeBreakdown = [];
    @track payAmount = 0;
    @track remainingAmount = 0;
    @track totalInstallmentFees = 0;
    @track paymentHistory = [];
    @track totalAmount = 0;
    @track paidAmount = 0;
    @track pendingAmount = 0;

    @track allPayments = [];
    @track filteredPayments = [];
    @track selectedHistoryTab = 'Success';
    @track feeBreakdownWithDeduction = [];


    // Payment Mode Selection
    @track selectedPaymentMode = 'Online Payment';
    @track isOnlinePayment = true;
    @track showOfflineFields = false;

    // Conditional Field Flags
    @track isChequeDD = false;
    @track isBankLoan = false;
    @track isCorporateSponsor = false;
    @track isWireTransfer = false;
    @track isCashTransaction = false;

    // Common Fields
    @track transactionDate = '';
    @track bankName = '';

    // Cheque/DD Fields
    @track chequeNumber = '';

    // Bank Loan Fields
    @track rtgsNeftNumber = '';
    @track loanAccountNumber = '';

    // Loan data from Fee record
    @track loanBankName = '';
    @track loanUtrNumber = '';
    @track loanAccNumber = '';
    @track loanAmountValue = 0;
    @track loanAmount = 0;

    // Corporate Sponsor Fields
    @track companyName = '';
    @track sponsorCompanyName = '';
    @track sponsorGstNumber = '';
    @track sponsorPanNo = '';
    @track sponsorTanNo = '';
    @track sponsorCity = '';
    @track sponsorCompanyBranch = '';
    @track sponsorCompanyAddress = '';
    @track sponsorState = '';
    @track chequeNo = '';

    // Cash Transaction Fields
    @track receiptNumber = '';
    @track receivedBy = '';

    // Store payment record ID
    currentPaymentRecordId = null;

    razorpayLoaded = false;

    openWireInfo() {
        window.open(wireInfoPdf, '_blank');
    }


    // Payment Mode Options with checked state
    get paymentModeOptions() {
        return [
            { label: 'Cheque/DD', value: 'Cheque/DD', isChecked: this.selectedPaymentMode === 'Cheque/DD' },
            { label: 'Online Payment', value: 'Online Payment', isChecked: this.selectedPaymentMode === 'Online Payment' },
            { label: 'Payment through Bank Loan', value: 'Bank Loan', isChecked: this.selectedPaymentMode === 'Bank Loan' },
            { label: 'Corporate Sponsor', value: 'Corporate Sponsor', isChecked: this.selectedPaymentMode === 'Corporate Sponsor' },
            { label: 'NEFT/RTGS', value: 'Wire Transfer', isChecked: this.selectedPaymentMode === 'Wire Transfer' }
        ];
    }

    // Get today's date for max date validation
    get todayDate() {
        return new Date().toISOString().split('T')[0];
    }

    connectedCallback() {
        console.log('--- Connected Callback Triggered ---');
        console.log('Record ID:', this.recordId);

        // ✅ VALIDATE RECORD ID TYPE
        if (!this.recordId) {
            this.showToast('Error', 'No record ID provided', 'error');
            return;
        }

        // Check if it's a Fee ID (should start with ISB_Fee__c prefix)
        // ISB_Fee__c IDs typically start with a specific prefix
        // We can check the length and format
        const recordIdStr = String(this.recordId);

        // Salesforce IDs are 15 or 18 characters
        if (recordIdStr.length !== 15 && recordIdStr.length !== 18) {
            this.showToast('Error', 'Invalid record ID format', 'error');
            return;
        }

        console.log('✅ Record ID validated, proceeding with data fetch');

        if (!this.razorpayLoaded) {
            loadScript(this, razorpayCheckout)
                .then(() => {
                    this.razorpayLoaded = true;
                    console.log('Razorpay SDK loaded successfully');
                })
                .catch(error => {
                    console.error('Razorpay SDK failed to load', error);
                    this.showToast('Error', 'Could not load Razorpay SDK', 'error');
                });
        }

        this.fetchInstallmentAmount();
        this.fetchBreakageDetails();
        this.fetchPreviousPayments();
        this.fetchInstallmentTotalAmount();
        this.fetchLoanDetails();
    }

    fetchPreviousPayments() {
        getPreviousPayments({ feeId: this.recordId })
            .then(result => {
                this.allPayments = result || [];
                this.applyPaymentFilter();
            })
            .catch(error => {
                console.error('Error fetching payments', error);
            });
    }

    applyPaymentFilter() {
        if (this.selectedHistoryTab === 'Success') {
            this.filteredPayments =
                this.allPayments.filter(p => p.Initiated__c === 'Success');
        }
        else if (this.selectedHistoryTab === 'In Progress') {
            this.filteredPayments =
                this.allPayments.filter(p => p.Initiated__c === 'Initiated');
        }
        else if (this.selectedHistoryTab === 'Failed') {
            this.filteredPayments =
                this.allPayments.filter(p => p.Initiated__c === 'Failed');
        }
    }

    handleHistoryTabClick(event) {
        this.selectedHistoryTab = event.target.dataset.tab;
        this.applyPaymentFilter();
    }


    get successTabVariant() {
        return this.selectedHistoryTab === 'Success' ? 'brand' : 'neutral';
    }

    get inProgressTabVariant() {
        return this.selectedHistoryTab === 'In Progress' ? 'brand' : 'neutral';
    }

    get failedTabVariant() {
        return this.selectedHistoryTab === 'Failed' ? 'brand' : 'neutral';
    }

    get hasFeeBreakdown() {
        return this.feeBreakdown && this.feeBreakdown.length > 0;
    }

    // Add this validation method
    validateChequeNumber(chequeNumber) {
        if (!chequeNumber) {
            return { isValid: false, message: 'Cheque/DD Number is required' };
        }

        // Trim the value
        const trimmed = chequeNumber.trim();

        // Check if original value had spaces
        if (trimmed !== chequeNumber) {
            return { isValid: false, message: 'Cheque/DD Number cannot contain spaces' };
        }

        // Validate format: 6-20 characters, alphanumeric plus - and /
        const regex = /^[A-Za-z0-9\-/]{6,20}$/;
        if (!regex.test(trimmed)) {
            return { isValid: false, message: 'Enter a valid Cheque/DD Number (6–20 chars). No spaces' };
        }

        return { isValid: true, message: '' };
    }

    // Optional: For digits-only validation (if your business confirms)
    validateChequeNumberDigitsOnly(chequeNumber) {
        if (!chequeNumber) {
            return { isValid: false, message: 'Cheque/DD Number is required' };
        }

        const trimmed = chequeNumber.trim();

        // Validate format: 6-12 digits only
        const regex = /^[0-9]{6,12}$/;
        if (!regex.test(trimmed)) {
            return { isValid: false, message: 'Enter a valid Cheque/DD Number (6–12 digits only). No spaces.' };
        }

        return { isValid: true, message: '' };
    }



    fetchInstallmentAmount() {
        console.log('Fetching Installment Amount for ID:', this.recordId);
        getInstallmentAmount({ feeId: this.recordId })
            .then(result => {
                console.log('Installment Amount Result:', result);

                this.totalAmount = result.totalAmount || 0;
                this.paidAmount = result.paidAmount || 0;
                this.pendingAmount = result.pendingAmount || 0;
                this.totalInstallmentFees = result.totalAmount || 0;

                this.totalFees = this.pendingAmount;
                this.payAmount = this.pendingAmount;
                this.remainingAmount = 0;
            })
            .catch(error => {
                console.error('Error fetching amount:', error);
                const message = error.body ? error.body.message : error.message;
                this.showToast('Error', 'Failed to fetch installment amount: ' + message, 'error');
            });
    }

    fetchInstallmentTotalAmount() {
        console.log('Fetching Total Installment Amount for ID:', this.recordId);
        getInstallmentTotalAmount({ feeId: this.recordId })
            .then(result => {
                console.log('Total Installment Amount Result:', result);
                this.totalInstallmentFees = result;
            })
            .catch(error => {
                console.error('Error fetching total amount:', error);
                const message = error.body ? error.body.message : error.message;
                this.showToast('Error', 'Failed to fetch total installment amount: ' + message, 'error');
            });
    }

    // ✅ UPDATED: Fetch Loan Details from Program Enrollment
    fetchLoanDetails() {
        getLoanDetails({ feeId: this.recordId })
            .then(result => {
                console.log('✅ Loan Details from Program Enrollment:', result);
                if (result) {
                    this.loanBankName = result.Loan_Bank_Name__c || '';
                    this.loanUtrNumber = result.Loan_UTR_Number__c || '';
                    this.loanAccNumber = result.Loan_Account_Number__c || '';
                    this.loanAmountValue = result.Loan_Amount__c || 0;

                    // Populate Sponsor Fields
                    this.sponsorCompanyName = result.Sponsor_Company_Name__c || '';
                    this.sponsorGstNumber = result.Sponsor_GST_Number__c || '';
                    this.sponsorPanNo = result.Sponsor_Pan_No__c || '';
                    this.sponsorTanNo = result.Sponsor_TanNo__c || '';
                    this.sponsorCity = result.Sponsor_City__c || '';
                    this.sponsorCompanyBranch = result.Sponsor_Company_Branch__c || '';
                    this.sponsorCompanyAddress = result.Sponsor_Company_Address__c || '';
                    this.sponsorState = result.Sponsor_State__c || '';

                    console.log('Sponsor Details Fetched:', this.sponsorCompanyName);
                }
            })
            .catch(error => {
                console.error('❌ Error fetching loan/sponsor details:', error);
                this.loanBankName = '';
                this.loanUtrNumber = '';
                this.loanAccNumber = '';
                this.loanAmountValue = 0;
                this.sponsorCompanyName = '';
                this.sponsorGstNumber = '';
                this.sponsorPanNo = '';
                this.sponsorTanNo = '';
                this.sponsorCity = '';
                this.sponsorCompanyBranch = '';
                this.sponsorCompanyAddress = '';
                this.sponsorState = '';
            });
    }

    /**
 * Sort fee breakdown to show Late Fee at the end
 */
    sortFeeBreakdown(breakdown) {
        if (!breakdown || breakdown.length === 0) {
            return breakdown;
        }

        // Separate late fees from other fees
        const lateFees = [];
        const otherFees = [];

        breakdown.forEach(item => {
            if (item.feeType && item.feeType.toLowerCase().includes('late fee')) {
                lateFees.push(item);
            } else {
                otherFees.push(item);
            }
        });

        // Return other fees first, then late fees
        return [...otherFees, ...lateFees];
    }

    fetchBreakageDetails() {
        console.log('Fetching Breakage Details for ID:', this.recordId);
        getInstallmentBreakageDetails({ feeId: this.recordId })
            .then(result => {
                console.log('Breakage Details Result:', JSON.stringify(result));
                if (result && result.length > 0) {
                    // ✅ Process each item to add scholarship info
                    this.feeBreakdown = this.sortFeeBreakdown(result).map(item => {
                        return {
                            ...item,
                            // ✅ Check if this is Tuition Fee and has scholarship
                            hasScholarship: this.isTuitionFee(item.feeType) &&
                                item.scholarshipAmount != null &&
                                item.scholarshipAmount > 0,
                            // ✅ Calculate net amount (amount - scholarship)
                            netAmount: item.amount - (item.scholarshipAmount || 0)
                        };
                    });
                    this.calculateFeeDeduction();
                } else {
                    console.warn('Breakage details returned empty list');
                    this.feeBreakdown = [];
                    this.feeBreakdownWithDeduction = [];

                }
            })
            .catch(error => {
                console.error('Error fetching breakage details:', error);
                this.showToast('Error', 'Failed to fetch fee breakage details: ' + (error.body ? error.body.message : error.message), 'error');
            });
    }

    // ✅ Helper method to check if fee type is Tuition Fee
    isTuitionFee(feeType) {
        if (!feeType) return false;
        return feeType.toLowerCase().includes('tuition');
    }

    openModal() {
        console.log('Opening Modal. Current Fees:', this.totalFees);
        console.log('Current Breakdown:', JSON.stringify(this.feeBreakdown));
        this.isModalOpen = true;
        // Reset to Online payment by default
        this.selectedPaymentMode = 'Online Payment';
        this.isOnlinePayment = true;
        this.showOfflineFields = false;
        this.resetOfflineFields();
        this.resetConditionalFlags();
        this.currentPaymentRecordId = null;
    }

    closeModal() {
        this.isModalOpen = false;
        this.resetOfflineFields();
        this.resetConditionalFlags();
        this.currentPaymentRecordId = null;
    }

    handleAmountChange(event) {
        this.payAmount = Number(event.target.value);
        this.remainingAmount = this.totalFees - this.payAmount;
        this.calculateFeeDeduction();

    }

    handleLoanAccountNumberChange(event) {
        this.loanAccountNumber = event.detail.value;
    }

    calculateFeeDeduction() {
        if (!this.feeBreakdown || this.feeBreakdown.length === 0) {
            this.feeBreakdownWithDeduction = [];
            return;
        }

        let paymentAmount = this.payAmount || 0;

        // Clone the original breakdown
        let breakdown = JSON.parse(JSON.stringify(this.feeBreakdown));

        // Define priority order for deduction
        const priorityOrder = [
            'IGST',
            'CGST',
            'SGST',
            'Tuition Fee',
            'Tuition',
            'Accommodation Studio',
            'Accommodation',
            'Security Deposit',
            'Security'
        ];

        // Sort by priority
        breakdown.sort((a, b) => {
            let priorityA = this.getPriorityIndex(a.feeType, priorityOrder);
            let priorityB = this.getPriorityIndex(b.feeType, priorityOrder);
            return priorityA - priorityB;
        });

        // ✅ STEP 1: Identify which GST types exist
        let hasIGST = breakdown.some(item =>
            item.feeType && item.feeType.toUpperCase().includes('IGST')
        );
        let hasCGST = breakdown.some(item =>
            item.feeType && item.feeType.toUpperCase().includes('CGST')
        );
        let hasSGST = breakdown.some(item =>
            item.feeType && item.feeType.toUpperCase().includes('SGST')
        );

        // ✅ STEP 2: Calculate GST amounts from payment (18% total)
        let calculatedIGST = 0;
        let calculatedCGST = 0;
        let calculatedSGST = 0;
        let totalCalculatedGST = 0;

        if (hasIGST) {
            // IGST = 18% of payment amount
            calculatedIGST = Math.round(paymentAmount * 0.18 * 100) / 100;
            totalCalculatedGST = calculatedIGST;
        } else if (hasCGST || hasSGST) {
            // CGST = 9% of payment amount
            // SGST = 9% of payment amount
            calculatedCGST = Math.round(paymentAmount * 0.09 * 100) / 100;
            calculatedSGST = Math.round(paymentAmount * 0.09 * 100) / 100;
            totalCalculatedGST = calculatedCGST + calculatedSGST;
        }

        console.log('💰 Payment Allocation Calculation:');
        console.log('Payment Amount:', paymentAmount);
        console.log('Calculated IGST (18%):', calculatedIGST);
        console.log('Calculated CGST (9%):', calculatedCGST);
        console.log('Calculated SGST (9%):', calculatedSGST);
        console.log('Total Calculated GST:', totalCalculatedGST);

        // ✅ STEP 3: Remaining amount after GST deduction
        let remainingAfterGST = paymentAmount - totalCalculatedGST;
        console.log('Remaining after GST deduction:', remainingAfterGST);

        // ✅ STEP 4: Allocate amounts to each fee type
        this.feeBreakdownWithDeduction = breakdown.map(item => {
            let deductedAmount = 0;
            let feeTypeUpper = item.feeType ? item.feeType.toUpperCase() : '';

            // ✅ Get pending amount for this fee type
            let pendingAmount = item.pendingAmount || 0;

            // Allocate GST amounts first (capped at pending amount)
            if (feeTypeUpper.includes('IGST')) {
                // ✅ DEDUCT MINIMUM OF (Calculated IGST, Pending IGST)
                deductedAmount = Math.min(calculatedIGST, pendingAmount);
                console.log(`IGST: Calculated=${calculatedIGST}, Pending=${pendingAmount}, Deducted=${deductedAmount}`);

                // ✅ If IGST pending was less than calculated, add difference back to remaining
                if (deductedAmount < calculatedIGST) {
                    let excess = calculatedIGST - deductedAmount;
                    remainingAfterGST += excess;
                    console.log(`⚠️ IGST pending exhausted. Adding ₹${excess} back to remaining pool`);
                }

            } else if (feeTypeUpper.includes('CGST')) {
                // ✅ DEDUCT MINIMUM OF (Calculated CGST, Pending CGST)
                deductedAmount = Math.min(calculatedCGST, pendingAmount);
                console.log(`CGST: Calculated=${calculatedCGST}, Pending=${pendingAmount}, Deducted=${deductedAmount}`);

                // ✅ If CGST pending was less than calculated, add difference back to remaining
                if (deductedAmount < calculatedCGST) {
                    let excess = calculatedCGST - deductedAmount;
                    remainingAfterGST += excess;
                    console.log(`⚠️ CGST pending exhausted. Adding ₹${excess} back to remaining pool`);
                }

            } else if (feeTypeUpper.includes('SGST')) {
                // ✅ DEDUCT MINIMUM OF (Calculated SGST, Pending SGST)
                deductedAmount = Math.min(calculatedSGST, pendingAmount);
                console.log(`SGST: Calculated=${calculatedSGST}, Pending=${pendingAmount}, Deducted=${deductedAmount}`);

                // ✅ If SGST pending was less than calculated, add difference back to remaining
                if (deductedAmount < calculatedSGST) {
                    let excess = calculatedSGST - deductedAmount;
                    remainingAfterGST += excess;
                    console.log(`⚠️ SGST pending exhausted. Adding ₹${excess} back to remaining pool`);
                }

            } else {
                // For non-GST fees (Tuition, Accommodation, Security)
                // Deduct from remaining amount after GST
                if (remainingAfterGST > 0) {
                    deductedAmount = Math.min(remainingAfterGST, pendingAmount);
                    remainingAfterGST -= deductedAmount;
                    console.log(`${item.feeType}: Pending=${pendingAmount}, Deducted=${deductedAmount}, Remaining Pool=${remainingAfterGST}`);
                }
            }

            // Round to 2 decimal places
            deductedAmount = Math.round(deductedAmount * 100) / 100;

            return {
                ...item,
                deductedAmount: deductedAmount,
                remainingAmount: Math.round((pendingAmount - deductedAmount) * 100) / 100
            };
        });

        console.log('✅ Fee Breakdown with Deduction:', this.feeBreakdownWithDeduction);
        console.log('💰 Final Remaining (should be 0):', remainingAfterGST);
    }

    // ✅ Helper: Get priority index
    getPriorityIndex(feeType, priorityOrder) {
        if (!feeType) return 999;

        for (let i = 0; i < priorityOrder.length; i++) {
            if (feeType.toLowerCase().includes(priorityOrder[i].toLowerCase())) {
                return i;
            }
        }
        return 999; // Unknown types go last
    }

    // Custom Payment Mode Change Handler for Radio Buttons
    handlePaymentModeChangeCustom(event) {
        this.selectedPaymentMode = event.target.value;

        // Reset all flags
        this.resetConditionalFlags();

        // Set flags based on selection
        this.isOnlinePayment = (this.selectedPaymentMode === 'Online Payment');
        this.showOfflineFields = !this.isOnlinePayment;

        if (this.showOfflineFields) {
            // Set specific mode flags
            this.isChequeDD = (this.selectedPaymentMode === 'Cheque/DD');
            this.isBankLoan = (this.selectedPaymentMode === 'Bank Loan');
            this.isCorporateSponsor = (this.selectedPaymentMode === 'Corporate Sponsor');
            this.isWireTransfer = (this.selectedPaymentMode === 'Wire Transfer');
            this.isCashTransaction = (this.selectedPaymentMode === 'Cash Transaction');

            if (this.isBankLoan) {
                this.bankName = this.loanBankName;
                this.rtgsNeftNumber = this.loanUtrNumber;
                this.loanAccountNumber = this.loanAccNumber;
                this.loanAmount = this.loanAmountValue;
            }

            if (this.isCorporateSponsor) {
                this.companyName = this.sponsorCompanyName;
            }
        }

        console.log('Payment Mode Changed to:', this.selectedPaymentMode);
    }

    resetConditionalFlags() {
        this.isChequeDD = false;
        this.isBankLoan = false;
        this.isCorporateSponsor = false;
        this.isWireTransfer = false;
        this.isCashTransaction = false;
    }

    // Common Field Handlers
    handleTransactionDateChange(event) {
        this.transactionDate = event.detail.value;
    }

    handleBankNameChange(event) {
        this.bankName = event.detail.value;
    }

    // Cheque/DD Field Handlers
    handleChequeNumberChange(event) {
        this.chequeNumber = event.detail.value.trim();
    }


    // Bank Loan Field Handler
    handleRtgsNeftNumberChange(event) {
        this.rtgsNeftNumber = event.detail.value;
    }

    handleLoanAmountChange(event) {
        this.loanAmount = event.target.value;
    }

    // Corporate Sponsor Field Handlers
    handleCompanyNameChange(event) {
        this.companyName = event.detail.value;
    }

    handleChequeNoChange(event) {
        this.chequeNo = event.detail.value;
    }

    // Cash Transaction Field Handlers
    handleReceiptNumberChange(event) {
        this.receiptNumber = event.detail.value;
    }

    handleReceivedByChange(event) {
        this.receivedBy = event.detail.value;
    }

    resetOfflineFields() {
        this.transactionDate = '';
        this.bankName = '';
        this.chequeNumber = '';
        this.rtgsNeftNumber = '';
        this.companyName = '';
        this.chequeNo = '';
        this.receiptNumber = '';
        this.receivedBy = '';
        this.loanAccountNumber = '';
    }

    // Validate Offline Payment
    validateOfflinePayment() {
        if (this.payAmount > this.pendingAmount) {
            this.showToast('Error', `Payment amount (₹${this.payAmount}) cannot exceed pending amount (₹${this.pendingAmount})`, 'error');
            return false;
        }

        if (!this.payAmount || this.payAmount <= 0) {
            this.showToast('Error', 'Please enter a valid payment amount', 'error');
            return false;
        }

        if (!this.transactionDate) {
            this.showToast('Error', 'Please select transaction date', 'error');
            return false;
        }

        const today = new Date().toISOString().split('T')[0];
        if (this.transactionDate > today) {
            this.showToast('Error', 'Transaction Date cannot be in the future', 'error');
            return;
        }

        // Mode-specific validations
        if (this.isChequeDD) {
            if (!this.bankName) {
                this.showToast('Error', 'Please enter bank name', 'error');
                return false;
            }


            if (!this.chequeNumber) {
                this.showToast('Error', 'Please enter Cheque or DD number', 'error');
                return false;
            }

            const chequeValidation = this.validateChequeNumber(this.chequeNumber);
            // Or use this for digits-only: const chequeValidation = this.validateChequeNumberDigitsOnly(this.chequeNumber);

            if (!chequeValidation.isValid) {
                this.showToast('Error', chequeValidation.message, 'error');
                return false;
            }

        }

        if (this.isBankLoan) {
            if (!this.bankName) {
                this.showToast('Error', 'Please enter bank name', 'error');
                return false;
            }
            if (!this.loanAccountNumber) {
                this.showToast('Error', 'Please enter loan account number', 'error');
                return false;
            }
            if (!this.rtgsNeftNumber) {
                this.showToast('Error', 'Please enter RTGS / NEFT number', 'error');
                return false;
            }
        }

        if (this.isCorporateSponsor) {
            if (!this.sponsorCompanyName) {
                this.showToast('Error', 'Sponsor Company Name not found in Enrollment.', 'error');
                return false;
            }
        }

        if (this.isWireTransfer) {
            if (!this.bankName) {
                this.showToast('Error', 'Please enter bank name', 'error');
                return false;
            }
            if (!this.rtgsNeftNumber) {
                this.showToast('Error', 'Please enter RTGS / NEFT number', 'error');
                return false;
            }
        }

        if (this.isCashTransaction && !this.receiptNumber) {
            this.showToast('Error', 'Please enter receipt number', 'error');
            return false;
        }

        return true;
    }

    // Save Offline Payment
    handleSaveOfflinePayment() {
        if (!this.validateOfflinePayment()) {
            return;
        }

        console.log('Saving Offline Payment...');

        // First create payment record with "Initiated" status
        saveOfflinePayment({
            feeId: this.recordId,
            amountPaid: this.payAmount,
            paymentMode: this.selectedPaymentMode,
            transactionDate: this.transactionDate,
            // Cheque/DD fields
            chequeNumber: this.chequeNumber,
            bankName: this.bankName,
            // Bank Loan fields
            rtgsNeftNumber: this.rtgsNeftNumber,
            loanAccountNumber: this.loanAccountNumber, // ✅ NEW
            // Corporate Sponsor fields
            companyName: this.companyName,
            chequeNo: this.chequeNo,
            // Cash Transaction fields
            receiptNumber: this.receiptNumber,
            receivedBy: this.receivedBy
        })
            .then(result => {
                console.log('Offline Payment Saved Successfully:', result);

                // ✅ UPDATE BREAKAGE RECORDS
                const allocationData = JSON.stringify(this.feeBreakdownWithDeduction);
                return updateBreakageRecords({
                    feeId: this.recordId,
                    paymentAmount: this.payAmount,
                    allocationDataJson: allocationData
                });
            })
            .then(() => {
                //this.showToast('Success', 'Payment recorded successfully', 'success');
                this.refreshComponent();
            })
            .catch(error => {
                console.error('Error saving offline payment:', error);
                this.showToast('Error', 'Failed to save payment: ' + (error.body?.message || error.message), 'error');
            });
    }

    // Online Payment (Razorpay)
    handleOnlinePayment() {
        console.log('💳 ========== PAYMENT FLOW INITIATED ==========');
        console.log('💳 Payment Amount:', this.payAmount);
        console.log('💳 Fee Record ID:', this.recordId);
        console.log('💳 Pending Amount:', this.pendingAmount);

        if (this.payAmount > this.pendingAmount) {
            console.error('❌ Amount exceeds pending. Amount:', this.payAmount, 'Pending:', this.pendingAmount);
            this.showToast('Error', `Payment amount (₹${this.payAmount}) cannot exceed pending amount (₹${this.pendingAmount})`, 'error');
            return;
        }

        if (!this.payAmount || this.payAmount <= 0) {
            console.error('❌ Invalid amount. Amount:', this.payAmount);
            this.showToast('Error', 'Please enter a valid payment amount', 'error');
            return;
        }

        console.log('💳 Validation passed. Creating initiated payment record...');

        // Step 1: Create payment record with "Initiated" status
        createInitiatedPaymentRecord({
            feeId: this.recordId,
            amountPaid: this.payAmount,
            paymentMode: 'Online Payment'
        })
            .then(paymentRecordId => {
                console.log('✅ Payment Record Created with Initiated Status:', paymentRecordId);
                this.currentPaymentRecordId = paymentRecordId;

                console.log('💳 Fetching Razorpay Key and Creating Order...');
                console.log('💳 Order Amount (in paise):', this.payAmount * 100);

                // Step 2: Get Razorpay Key and Create Order
                return Promise.all([
                    getRazorpayKey(),
                    createOrder({ amount: this.payAmount, currency: 'INR' })
                ]);
            })
            .then(([key, orderResponse]) => {
                console.log('✅ Razorpay Key Retrieved:', key);
                console.log('✅ Order Response (RAW):', orderResponse);
                console.log('✅ Order Response Type:', typeof orderResponse);

                let order;
                try {
                    order = JSON.parse(orderResponse);
                    console.log('✅ Order Parsed Successfully:', order);
                    console.log('✅ Order ID:', order.id);
                    console.log('✅ Order Amount:', order.amount);
                    console.log('✅ Order Currency:', order.currency);
                } catch (parseError) {
                    console.error('❌ Failed to parse order response:', parseError);
                    console.error('❌ Raw response was:', orderResponse);
                    throw new Error('Invalid order response format');
                }

                console.log('💳 Opening Razorpay Checkout with Order ID:', order.id);

                this.openCheckout({
                    key_id: key,
                    orderId: order.id,
                    amount: order.amount,
                    currency: order.currency
                });
            })
            .catch(error => {
                console.error('❌ ========== PAYMENT INITIATION FAILED ==========');
                console.error('❌ Error Object:', error);
                console.error('❌ Error Message:', error.message);
                console.error('❌ Error Body:', error.body);
                console.error('❌ Error Stack:', error.stack);
                this.showToast('Error', 'Failed to initiate payment: ' + (error.message || 'Unknown error'), 'error');
            });
    }

    openCheckout(myObj) {
        console.log('💳 ========== OPENING RAZORPAY CHECKOUT ==========');
        console.log('💳 Checkout Configuration:');
        console.log('  - Key ID:', myObj.key_id);
        console.log('  - Order ID:', myObj.orderId);
        console.log('  - Amount:', myObj.amount, 'paise (₹' + (myObj.amount / 100) + ')');
        console.log('  - Currency:', myObj.currency);
        console.log('  - Razorpay SDK Loaded:', typeof window.Razorpay !== 'undefined');

        let options = {
            key: myObj.key_id,
            amount: myObj.amount,
            currency: myObj.currency,
            name: 'ISB Installment Payment',
            description: 'Installment Fee Payment',
            order_id: myObj.orderId,

            // ✅ SUCCESS
            handler: (response) => {
                console.log('✅ ========== PAYMENT SUCCESS HANDLER ==========');
                console.log('✅ Payment Response Received:');
                console.log('  - Razorpay Payment ID:', response.razorpay_payment_id);
                console.log('  - Razorpay Order ID:', response.razorpay_order_id);
                console.log('  - Razorpay Signature:', response.razorpay_signature);
                console.log('  - Full Response:', JSON.stringify(response));

                console.log('💳 Current Payment Record ID:', this.currentPaymentRecordId);
                console.log('💳 Calling updatePaymentRecordToSuccess...');

                updatePaymentRecordToSuccess({
                    paymentRecordId: this.currentPaymentRecordId,
                    razorpayPaymentId: response.razorpay_payment_id,
                    razorpayOrderId: response.razorpay_order_id,
                    razorpaySignature: response.razorpay_signature,
                })
                    .then(() => {
                        console.log('✅ Payment record updated successfully');

                        // ✅ UPDATE BREAKAGE RECORDS
                        console.log('💳 Updating breakage records with allocation...');
                        const allocationData = JSON.stringify(this.feeBreakdownWithDeduction);
                        console.log('💳 Allocation Data:', allocationData);
                        
                        return updateBreakageRecords({
                            feeId: this.recordId,
                            paymentAmount: this.payAmount,
                            allocationDataJson: allocationData
                        });
                    })
                    .then(() => {
                        console.log('✅ Breakage records updated');
                        console.log('💳 Processing installment from master...');
                        return processInstallmentFromMaster({ feeId: this.recordId });
                    })
                    .then(() => {
                        console.log('✅ ========== PAYMENT FLOW COMPLETE ==========');
                        this.showToast('Success', 'Payment completed successfully', 'success');
                        this.refreshComponent();
                    })
                    .catch(error => {
                        console.error('❌ ========== POST-PAYMENT ERROR ==========');
                        console.error('❌ Error during post-payment processing:', error);
                        console.error('❌ Error Message:', error.message);
                        console.error('❌ Error Body:', error.body);
                        console.error('❌ Error Stack:', error.stack);
                        this.showToast('Error', 'Payment done but update failed: ' + (error.message || 'Unknown error'), 'error');
                    });
            },

            // ❌ PAYMENT FAILED EVENT
            modal: {
                ondismiss: () => {
                    console.warn('⚠️ ========== PAYMENT POPUP DISMISSED ==========');
                    console.warn('⚠️ User closed Razorpay popup without completing payment');
                    console.log('💳 Current Payment Record ID:', this.currentPaymentRecordId);

                    updatePaymentRecordToFailed({
                        paymentRecordId: this.currentPaymentRecordId,
                        failureReason: 'Payment popup closed by user'
                    });

                    this.showToast('Info', 'Payment was cancelled', 'info');
                }
            }
        };

        console.log('💳 Creating Razorpay instance with options...');
        
        try {
            const rzp1 = new window.Razorpay(options);
            console.log('✅ Razorpay instance created successfully');

            // ❌ Explicit failure event
            rzp1.on('payment.failed', (response) => {
                console.error('❌ ========== RAZORPAY PAYMENT.FAILED EVENT ==========');
                console.error('❌ Payment Failed Response:');
                console.error('  - Error Code:', response.error?.code);
                console.error('  - Error Description:', response.error?.description);
                console.error('  - Error Source:', response.error?.source);
                console.error('  - Error Reason:', response.error?.reason);
                console.error('  - Error Metadata:', response.error?.metadata);
                console.error('  - Full Error Object:', JSON.stringify(response.error));
                console.error('  - Full Response:', JSON.stringify(response));

                console.log('💳 Current Payment Record ID:', this.currentPaymentRecordId);
                console.log('💳 Calling updatePaymentRecordToFailed...');

                updatePaymentRecordToFailed({
                    paymentRecordId: this.currentPaymentRecordId,
                    failureReason: response.error?.description || 'Payment failed'
                });

                this.showToast('Error', 'Payment declined. ' + (response.error?.description || 'Please try again.'), 'error');
            });

            console.log('💳 Opening Razorpay checkout modal...');
            rzp1.open();
            console.log('✅ Razorpay checkout modal opened');
        } catch (error) {
            console.error('❌ ========== RAZORPAY INITIALIZATION ERROR ==========');
            console.error('❌ Failed to create Razorpay instance:', error);
            console.error('❌ Error Message:', error.message);
            console.error('❌ Error Stack:', error.stack);
            this.showToast('Error', 'Failed to open payment gateway: ' + error.message, 'error');
        }
    }
    refreshComponent() {
        // Reset modal & fields
        this.isModalOpen = false;
        this.resetOfflineFields();
        this.resetConditionalFlags();
        this.currentPaymentRecordId = null;

        // Refresh data
        this.fetchPreviousPayments();
        this.fetchInstallmentAmount();
        this.fetchBreakageDetails();
        this.fetchInstallmentTotalAmount();

        // Notify parent (if embedded)
        this.dispatchEvent(new CustomEvent('paymentsuccess', {
            bubbles: true,
            composed: true
        }));
    }


    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}