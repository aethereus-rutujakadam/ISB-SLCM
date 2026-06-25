import { LightningElement, api, track } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import sendAdvisorEmailToAudience from '@salesforce/apex/WorkshopNotificationService.sendAdvisorEmailToAudience';

export default class WorkshopEmailComposer extends LightningElement {

    /** Provided by the Quick Action framework — Workshop__c record Id */
    @api recordId;

    @track subject = '';
    @track body = '';
    @track resourceLink = '';
    @track attachedFiles = [];   // [{ documentId, name }]
    @track isSending = false;
    @track isSent = false;
    @track errorMessage = '';
    @track subjectError = '';
    @track bodyError = '';
    @track audience = 'REGISTERED';  // default: registered students only
    @track currentStep = 1;  // 1 = audience selection, 2 = email composer

    acceptedFormats = ['.pdf', '.doc', '.docx', '.ppt', '.pptx', '.xls', '.xlsx', '.png', '.jpg', '.jpeg', '.txt'];

    audienceOptions = [
        { label: 'Send email to registered students', value: 'REGISTERED' },
        { label: 'Send to all students', value: 'ALL_ENROLLED' }
    ];

    // ── Getters ──────────────────────────────────────────────────────────────────

    get hasAttachments() {
        return this.attachedFiles.length > 0;
    }

    get isRegisteredAudience() {
        return this.audience === 'REGISTERED';
    }

    get isStepOne() {
        return this.currentStep === 1;
    }

    get isStepTwo() {
        return this.currentStep === 2;
    }

    get sendButtonLabel() {
        return this.isSending ? 'Sending...' : 'Send Email';
    }

    // ── Event handlers ───────────────────────────────────────────────────────────

    handleSubjectChange(event) {
        this.subject = event.target.value;
        if (this.subject.trim()) this.subjectError = '';
    }

    handleBodyChange(event) {
        this.body = event.target.value;
        if (this.body.trim()) this.bodyError = '';
    }

    handleLinkChange(event) {
        this.resourceLink = event.target.value;
    }

    handleAudienceChange(event) {
        this.audience = event.detail.value;
    }

    handleFileUpload(event) {
        const files = event.detail.files;
        if (files && files.length > 0) {
            files.forEach(file => {
                // Avoid duplicates
                const already = this.attachedFiles.some(f => f.documentId === file.documentId);
                if (!already) {
                    this.attachedFiles = [...this.attachedFiles, { documentId: file.documentId, name: file.name }];
                }
            });
        }
    }

    handleRemoveFile(event) {
        const docId = event.currentTarget.dataset.id;
        this.attachedFiles = this.attachedFiles.filter(f => f.documentId !== docId);
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleContinue() {
        // Move from Step 1 (audience selection) to Step 2 (email composer)
        this.currentStep = 2;
    }

    handleBack() {
        // Move back from Step 2 to Step 1
        this.currentStep = 1;
    }

    handleSend() {
        // Validate
        let valid = true;
        this.subjectError = '';
        this.bodyError = '';
        this.errorMessage = '';

        if (!this.subject.trim()) {
            this.subjectError = 'Subject is required.';
            valid = false;
        }
        if (!this.body.trim()) {
            this.bodyError = 'Message body is required.';
            valid = false;
        }
        if (!valid) return;

        this.isSending = true;

        // Build body — append resource link if provided
        let finalBody = this.body.trim();
        if (this.resourceLink && this.resourceLink.trim()) {
            finalBody += '\n\nResource Link: ' + this.resourceLink.trim();
        }

        const contentDocIds = this.attachedFiles.map(f => f.documentId);

        sendAdvisorEmailToAudience({
            workshopId: this.recordId,
            subject: this.subject.trim(),
            body: finalBody,
            contentDocIds: contentDocIds,
            audience: this.audience
        })
        .then(() => {
            this.isSent = true;
            this.dispatchEvent(new ShowToastEvent({
                title: 'Email Sent',
                message: 'Your email has been sent to the selected audience.',
                variant: 'success'
            }));
        })
        .catch(error => {
            const msg = (error && error.body && error.body.message)
                ? error.body.message
                : 'An unexpected error occurred. Please try again.';
            this.errorMessage = msg;
        })
        .finally(() => {
            this.isSending = false;
        });
    }
}