import { LightningElement, api, track } from 'lwc';
import getContentDocumentId from '@salesforce/apex/FilePreviewController.getContentDocumentId';
import { NavigationMixin } from 'lightning/navigation';

export default class FileUploaderPreviewerLWC extends NavigationMixin(LightningElement) {

    @api recordId;
    @track fName;

    @api contentVersionId;
    @api contentDocumentId;   // ✅ OUTPUT to Flow

    acceptedFormats = ['.pdf', '.png', '.jpg', '.jpeg'];

    async handleUploadFinished(event) {
        const uploadedFile = event.detail.files[0];
        this.fName = uploadedFile.name;
        this.contentVersionId = uploadedFile.contentVersionId;

        // ✅ Fetch ContentDocumentId for display and output
        try {
            this.contentDocumentId = await getContentDocumentId({ 
                contentVersionId: this.contentVersionId 
            });
        } catch (error) {
            console.error('Error fetching ContentDocumentId:', error);
        }

        // ✅ Sync to Flow
        this.dispatchFlowValueChange('contentVersionId', this.contentVersionId);
        this.dispatchFlowValueChange('contentDocumentId', this.contentDocumentId);
    }

    removeFile() {
        this.contentVersionId = null;
        this.contentDocumentId = null;

        this.dispatchFlowValueChange('contentVersionId', null);
        this.dispatchFlowValueChange('contentDocumentId', null);
    }

    dispatchFlowValueChange(name, value) {
        this.dispatchEvent(new CustomEvent('flowvaluechange', {
            detail: { name, value }
        }));
    }
}