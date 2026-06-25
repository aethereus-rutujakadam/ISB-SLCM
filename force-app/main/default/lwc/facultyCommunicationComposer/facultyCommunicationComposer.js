import { LightningElement, api, track } from 'lwc';
import getFacultyEmailTemplates from '@salesforce/apex/FacultyCommunicationComposerController.getFacultyEmailTemplates';
import renderTemplatePreview from '@salesforce/apex/FacultyCommunicationComposerController.renderTemplatePreview';

export default class FacultyCommunicationComposer extends LightningElement {
    @api courseOfferingId;
    @api selectedContactId;
    @api threadName;
    @api folderName = 'Faculty Communications';

    @api composedSubject = '';
    @api composedBody = '';
    @api selectedTemplateId = '';
    @api selectedTemplateName = '';

    @track templateOptions = [];
    @track isLoadingTemplates = false;
    @track isRenderingTemplate = false;
    @track errorMessage = '';

    connectedCallback() {
        this.loadTemplates();
    }

    get disableTemplateSelect() {
        return this.isLoadingTemplates || this.isRenderingTemplate;
    }

    get disableEditor() {
        return this.isRenderingTemplate;
    }

    async loadTemplates() {
        this.isLoadingTemplates = true;
        this.errorMessage = '';
        try {
            const rows = await getFacultyEmailTemplates({ folderName: this.folderName });
            this.templateOptions = (rows || []).map((row) => ({
                label: row.templateName,
                value: row.templateId
            }));
        } catch (e) {
            this.errorMessage = this.normalizeError(e);
        } finally {
            this.isLoadingTemplates = false;
        }
    }

    async handleTemplateChange(event) {
        this.selectedTemplateId = event.detail.value;
        if (!this.selectedTemplateId) {
            this.selectedTemplateName = '';
            this.composedSubject = '';
            this.composedBody = '';
            return;
        }

        this.isRenderingTemplate = true;
        this.errorMessage = '';
        try {
            const result = await renderTemplatePreview({
                templateId: this.selectedTemplateId,
                recipientId: this.selectedContactId,
                relatedRecordId: this.courseOfferingId,
                threadName: this.threadName
            });
            this.selectedTemplateName = result?.templateName || '';
            this.composedSubject = result?.renderedSubject || '';
            this.composedBody = result?.renderedHtmlBody || '';
        } catch (e) {
            this.errorMessage = this.normalizeError(e);
        } finally {
            this.isRenderingTemplate = false;
        }
    }

    handleSubjectChange(event) {
        this.composedSubject = event.target.value;
    }

    handleBodyChange(event) {
        this.composedBody = event.target.value;
    }

    normalizeError(error) {
        if (error?.body?.message) return error.body.message;
        if (Array.isArray(error?.body) && error.body.length > 0) {
            return error.body.map((x) => x.message).join('; ');
        }
        return 'Unable to load template details.';
    }
}