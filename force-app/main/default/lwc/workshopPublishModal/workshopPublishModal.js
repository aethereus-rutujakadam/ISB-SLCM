import { LightningElement, api, wire, track } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getPublishRecipientCount from '@salesforce/apex/WorkshopController.getPublishRecipientCount';
import publishWorkshopWithEmail from '@salesforce/apex/WorkshopController.publishWorkshopWithEmail';

const WORKSHOP_FIELDS = [
    'Workshop__c.Name',
    'Workshop__c.Description__c',
    'Workshop__c.Program__c',
    'Workshop__c.Cohort__c',
    'Workshop__c.Eligible_Term__c'
];

export default class WorkshopPublishModal extends NavigationMixin(LightningElement) {
    @api recordId; // Workshop__c ID
    @track subject = '';
    @track body = '';
    @track resourceLink = '';
    @track attachedFiles = [];
    @track recipientCount = 0;
    @track isLoading = true;
    @track isPublishing = false;

    workshopName = '';
    workshopDescription = '';

    acceptedFormats = ['.pdf', '.doc', '.docx', '.ppt', '.pptx', '.xls', '.xlsx', '.png', '.jpg', '.jpeg', '.txt'];

    @wire(getRecord, { recordId: '$recordId', fields: WORKSHOP_FIELDS })
    wiredWorkshop({ error, data }) {
        if (data) {
            this.workshopName = data.fields.Name.value || '';
            this.workshopDescription = data.fields.Description__c.value || '';
            
            // Pre-fill subject and body
            this.subject = `New Workshop Available: ${this.workshopName}`;
            this.body = this.workshopDescription || 'A new workshop is now open for registration. Log in to the Advising Portal to view details and register.';
            
            this.isLoading = false;
        } else if (error) {
            this.showToast('Error', 'Failed to load workshop details.', 'error');
            this.isLoading = false;
        }
    }

    @wire(getPublishRecipientCount, { workshopId: '$recordId' })
    wiredRecipientCount({ error, data }) {
        if (data !== undefined && data !== null) {
            this.recipientCount = data;
        } else if (error) {
            console.error('getPublishRecipientCount error:', error);
            this.recipientCount = 0;
        }
    }

    get isPublishDisabled() {
        return this.isPublishing || !this.subject || !this.body;
    }

    get recipientPreview() {
        if (this.recipientCount === 0) {
            return 'No eligible students found';
        }
        if (this.recipientCount === 1) {
            return '1 eligible student';
        }
        return `${this.recipientCount} eligible students`;
    }

    get hasAttachments() {
        return this.attachedFiles.length > 0;
    }

    handleSubjectChange(event) {
        this.subject = event.target.value;
    }

    handleBodyChange(event) {
        this.body = event.target.value;
    }

    handleResourceLinkChange(event) {
        this.resourceLink = event.target.value;
    }

    handleFileUpload(event) {
        const files = event.detail.files;
        if (files && files.length > 0) {
            files.forEach(file => {
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

    handlePublish() {
        if (!this.subject || !this.body) {
            this.showToast('Validation Error', 'Subject and body are required.', 'error');
            return;
        }

        this.isPublishing = true;

        // Build final body with resource link if provided
        let finalBody = this.body.trim();
        if (this.resourceLink && this.resourceLink.trim()) {
            finalBody += '\n\nResource Link: ' + this.resourceLink.trim();
        }

        const contentDocIds = this.attachedFiles.map(f => f.documentId);

        publishWorkshopWithEmail({
            workshopId: this.recordId,
            subject: this.subject,
            body: finalBody,
            contentDocIds: contentDocIds
        })
            .then(() => {
                this.showToast('Success', 'Workshop published and notifications sent.', 'success');
                this.dispatchEvent(new CloseActionScreenEvent());
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: this.recordId,
                        objectApiName: 'Workshop__c',
                        actionName: 'view'
                    }
                });
            })
            .catch(error => {
                const message = error.body && error.body.message ? error.body.message : 'Failed to publish workshop.';
                this.showToast('Error', message, 'error');
            })
            .finally(() => {
                this.isPublishing = false;
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}