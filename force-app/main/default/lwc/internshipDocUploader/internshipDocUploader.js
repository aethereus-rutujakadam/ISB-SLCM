import { LightningElement, api, track } from 'lwc';

export default class InternshipDocUploader extends LightningElement {

    @api recordId;
    @api contentDocumentId;
    @api fileName;
    @api documentType;

    @track showTypeError = false;

    handleTypeChange(event) {
        this.documentType = event.target.value;
        this.showTypeError = false;

        // Reset file if type changes
        if (this.fileName) {
            this.removeFile();
        }

        this.dispatchFlowValueChange('documentType', this.documentType);
    }

    handleUploadFinished(event) {
        const uploadedFile = event.detail.files[0];

        this.fileName = uploadedFile.name;
        this.contentDocumentId = uploadedFile.documentId;

        this.dispatchFlowValueChange('fileName', this.fileName);
        this.dispatchFlowValueChange('contentDocumentId', this.contentDocumentId);
    }

    removeFile() {
        this.fileName = null;
        this.contentDocumentId = null;

        this.dispatchFlowValueChange('fileName', null);
        this.dispatchFlowValueChange('contentDocumentId', null);
    }

    dispatchFlowValueChange(name, value) {
        this.dispatchEvent(new CustomEvent('flowvaluechange', {
            detail: { name, value }
        }));
    }
}