import { LightningElement, track, wire } from 'lwc';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';
import casFunctionListResource from '@salesforce/resourceUrl/CAS_FUNCTION_LIST';

import INTERNSHIP_DETAILS_OBJECT from '@salesforce/schema/Internship_Details__c';
import INDUSTRY_FIELD            from '@salesforce/schema/Internship_Details__c.Industry__c';
import SUB_INDUSTRY_FIELD        from '@salesforce/schema/Internship_Details__c.Sub_Industry__c';
import JOB_FUNCTION_FIELD        from '@salesforce/schema/Internship_Details__c.Job_Function__c';
import STIPEND_CURRENCY_FIELD    from '@salesforce/schema/Internship_Details__c.Stipend_Currency__c';

import getStudentInternships           from '@salesforce/apex/InternshipController.getStudentInternships';
import getProgramEnrollmentId          from '@salesforce/apex/InternshipController.getProgramEnrollmentId';
import saveInternship                  from '@salesforce/apex/InternshipController.saveInternship';
import deleteInternship                from '@salesforce/apex/InternshipController.deleteInternship';
import getDocuments                    from '@salesforce/apex/InternshipController.getDocuments';
import createDocumentRecord            from '@salesforce/apex/InternshipController.createDocumentRecord';
import getDocumentContentId            from '@salesforce/apex/InternshipController.getDocumentContentId';
import getDocumentPreviewData          from '@salesforce/apex/InternshipController.getDocumentPreviewData';
import deleteDocument                  from '@salesforce/apex/InternshipController.deleteDocument';
import createInternshipWithDocuments   from '@salesforce/apex/InternshipController.createInternshipWithDocuments';
import uploadFileToDocument            from '@salesforce/apex/InternshipController.uploadFileToDocument';

const SINGLE_UPLOAD_TYPES = new Set([
    'Summer Internship Offer Letter',
    'Internship Completion Certificate'
]);

const DOC_TYPE_OPTIONS = [
    { label: 'Summer Internship Offer Letter',    value: 'Summer Internship Offer Letter'    },
    { label: 'Internship Completion Certificate', value: 'Internship Completion Certificate' },
    { label: 'Other',                             value: 'Other'                             }
];

const BLANK_NEW_DOC = () => ({ Document_Type__c: '', Document_Title__c: '', Notes__c: '' });
const BLANK_WIZARD_DOC = () => ({ 
    tempId: Date.now() + Math.random(), 
    Document_Type__c: '', 
    Document_Title__c: '', 
    Notes__c: '',
    hasFile: false,
    recordId: null,
    fileName: '',
    fileData: null,
    typeError: '',
    titleError: '',
    fileError: ''
});

export default class InternshipPortal extends NavigationMixin(LightningElement) {
    functionListUrl = casFunctionListResource;

    // ─── Page state ────────────────────────────────────────────────────────────
    @track isLoading = true;
    @track currentView = 'list';  // 'list' | 'detail'
    @track selectedInternshipId = null;

    // ─── Modal states ──────────────────────────────────────────────────────────
    @track isModalOpen         = false;    @track isWizardMode        = false;    // true = wizard for new internship, false = modal for editing    @track isDeleteConfirmOpen = false;
    @track isSubmitConfirmOpen = false;
    @track modalStep           = 'form';   // 'form' | 'docs'
    
    // ─── Wizard states (for Add Internship wizard) ────────────────────────────
    @track wizardStep          = 1;        // 1 = internship details, 2 = documents, 3 = file upload
    @track wizardDocuments     = [];       // Array of document metadata {Document_Type__c, Document_Title__c, Notes__c, tempId, hasFile}
    @track createdInternshipId = null;     // Set after internship is created
    @track uploadingDocIndex   = -1;       // Which document is currently having its file uploaded
    @track uploadStatusMessage = '';       // Status message during upload

    // ─── Operation flags ───────────────────────────────────────────────────────
    @track isSaving    = false;
    @track isDeleting  = false;
    @track isSubmitting = false;

    // ─── Form / selection state ────────────────────────────────────────────────
    @track selectedRecord = {};
    @track formErrors     = {};
    @track deleteTargetId = null;

    // ─── Table row expansion (detail panel) ───────────────────────────────────
    // Removed - now using separate detail view instead of inline expansion

    // ─── Wire data ────────────────────────────────────────────────────────────
    @track internships = [];
    _internshipsWireResult;
    @track programEnrollmentId;

    // ─── Documents ────────────────────────────────────────────────────────────
    // expandedInternshipId: used in modal for doc operations
    @track expandedInternshipId = null;
    @track documentsMap         = {};
    @track showAddDocForm       = false;
    @track docFormStep          = 1;
    @track newDoc               = BLANK_NEW_DOC();
    @track newDocRecordId       = null;
    @track docTypeError         = '';
    @track docTitleError        = '';
    @track isCreatingDoc        = false;

    // ─── File Preview Modal ───────────────────────────────────────────────────
    @track showFilePreview     = false;
    @track previewSrc          = '';
    @track previewFileName     = '';
    @track previewIsPdf        = false;
    @track previewContentDocId = '';

    // ─── Document Deletion ────────────────────────────────────────────────────
    @track showDeleteDocModal  = false;
    @track deleteDocId         = null;
    @track isDeletingDoc       = false;

    // ─── Picklist data ────────────────────────────────────────────────────────
    @track industryOptions        = [];
    @track _subIndustryOptionsAll = [];
    @track _subIndustryCtrlValues = {};
    @track jobFunctionOptions     = [];
    @track stipendCurrencyOptions = [];

    @wire(getObjectInfo, { objectApiName: INTERNSHIP_DETAILS_OBJECT })
    _objectInfo;

    @wire(getPicklistValues, { recordTypeId: '$_objectInfo.data.defaultRecordTypeId', fieldApiName: INDUSTRY_FIELD })
    wiredIndustry({ data }) {
        if (data) this.industryOptions = data.values.map(v => ({ label: v.label, value: v.value }));
    }

    @wire(getPicklistValues, { recordTypeId: '$_objectInfo.data.defaultRecordTypeId', fieldApiName: SUB_INDUSTRY_FIELD })
    wiredSubIndustry({ data }) {
        if (data) {
            this._subIndustryOptionsAll = data.values.map(v => ({ label: v.label, value: v.value, validFor: v.validFor }));
            this._subIndustryCtrlValues = data.controllerValues;
        }
    }

    @wire(getPicklistValues, { recordTypeId: '$_objectInfo.data.defaultRecordTypeId', fieldApiName: JOB_FUNCTION_FIELD })
    wiredJobFunction({ data }) {
        if (data) this.jobFunctionOptions = data.values.map(v => ({ label: v.label, value: v.value }));
    }

    @wire(getPicklistValues, { recordTypeId: '$_objectInfo.data.defaultRecordTypeId', fieldApiName: STIPEND_CURRENCY_FIELD })
    wiredStipendCurrency({ data }) {
        if (data) this.stipendCurrencyOptions = data.values.map(v => ({ label: v.label, value: v.value }));
    }

    @wire(getStudentInternships)
    wiredInternships(result) {
        this._internshipsWireResult = result;
        if (result.data) {
            this.internships = result.data;
            this.isLoading   = false;
        } else if (result.error) {
            this.isLoading = false;
            this._showToast('', this._extractMessage(result.error), 'error');
        }
    }

    connectedCallback() {
        getProgramEnrollmentId()
            .then(id => { this.programEnrollmentId = id; })
            .catch(() => {});
    }

    // ─── Getters ──────────────────────────────────────────────────────────────

    get hasNoInternships()      { return !this.internships || this.internships.length === 0; }
    get isListView()            { return this.currentView === 'list'; }
    get isDetailView()          { return this.currentView === 'detail'; }
    get isFormStep()            { return this.modalStep === 'form'; }
    get isDocsStep()            { return this.modalStep === 'docs'; }
    get showDocTab()            { return !!this.expandedInternshipId; }
    get isExistingRecord()      { return !!this.selectedRecord.Id; }
    get isDocFormStep1()        { return this.docFormStep === 1; }
    get isDocFormStep2()        { return this.docFormStep === 2; }
    get docTypeOptions()        { return DOC_TYPE_OPTIONS; }
    get hasFormErrors()         { return false; }
    get formErrorMessages()     { return []; }
    get isSubIndustryDisabled() { return !this.selectedRecord.Industry__c; }

    get modalTitle() {
        if (this.modalStep === 'docs') return 'Documents';
        return this.selectedRecord.Id ? 'Edit Internship' : 'Add Internship';
    }

    get formTabClass() {
        return 'slds-tabs_default__item' + (this.isFormStep ? ' slds-is-active' : '');
    }

    get docsTabClass() {
        return 'slds-tabs_default__item' + (this.isDocsStep ? ' slds-is-active' : '');
    }

    get processedInternships() {
        return (this.internships || []).map((r, idx) => ({
            ...r,
            rowIndex: idx + 1,
            formattedStartDate: this._formatDate(r.Start_Date__c),
            formattedEndDate: this._formatDate(r.End_Date__c)
        }));
    }

    // Selected internship for detail view
    get selectedInternship() {
        if (!this.selectedInternshipId) return null;
        const record = this.internships.find(r => r.Id === this.selectedInternshipId) || null;
        if (record) {
            return {
                ...record,
                formattedStartDate: this._formatDate(record.Start_Date__c),
                formattedEndDate: this._formatDate(record.End_Date__c),
                readOnlyLabel: record.Read_Only__c ? 'Yes' : 'No'
            };
        }
        return null;
    }

    // Check if selected internship is read-only
    get isReadOnly() {
        return this.selectedInternship && this.selectedInternship.Read_Only__c === true;
    }

    // Title attributes for buttons
    get editButtonTitle() {
        return this.isReadOnly ? 'This record is read-only and cannot be edited' : 'Edit Internship';
    }

    get addDocButtonTitle() {
        return this.isReadOnly ? 'Cannot add documents to a read-only record' : 'Add Document';
    }

    // Wizard getters
    get isWizardStep1()     { return this.wizardStep === 1; }
    get isWizardStep2()     { return this.wizardStep === 2; }

    get step1BarClass() {
        return this.wizardStep === 1
            ? 'wizard-step wizard-step_active'
            : 'wizard-step wizard-step_completed';
    }
    get step2BarClass() {
        return this.wizardStep === 2
            ? 'wizard-step wizard-step_active'
            : 'wizard-step wizard-step_inactive';
    }
    get wizardHasDocuments() { return this.wizardDocuments && this.wizardDocuments.length > 0; }
    get allWizardDocsHaveFiles() { 
        return this.wizardDocuments && this.wizardDocuments.length > 0 && 
               this.wizardDocuments.every(doc => doc.hasFile); 
    }
    get isCreateDisabled() {
        if (this.isSaving) return true;
        if (!this.wizardDocuments || this.wizardDocuments.length === 0) return true;
        const validDocs = this.wizardDocuments.filter(d => d.Document_Type__c && d.Document_Title__c);
        const hasOfferLetter  = validDocs.some(d => d.Document_Type__c === 'Summer Internship Offer Letter');
        const hasCertificate  = validDocs.some(d => d.Document_Type__c === 'Internship Completion Certificate');
        if (!hasOfferLetter || !hasCertificate) return true;
        return validDocs.some(d => !d.hasFile || !d.fileData);
    }
    
    get wizardTitle() {
        if (this.wizardStep === 1) return 'Add Internship - Step 1: Details';
        if (this.wizardStep === 2) return 'Add Internship - Step 2: Add Documents & Upload Files';
        return 'Add Internship';
    }

    // Docs for the detail view
    get detailDocs()    { return this.documentsMap[this.selectedInternshipId] || []; }
    get detailHasDocs() { return this.detailDocs.length > 0; }

    // Docs for the modal docs step
    get modalDocs()    { return this.documentsMap[this.expandedInternshipId] || []; }
    get modalHasDocs() { return this.modalDocs.length > 0; }

    // Which internship ID to attach a new document to
    get currentDocSourceId() {
        return this.isModalOpen ? this.expandedInternshipId : this.selectedInternshipId;
    }

    get filteredSubIndustryOptions() {
        if (!this.selectedRecord.Industry__c) return [];
        const idx = this._subIndustryCtrlValues[this.selectedRecord.Industry__c];
        if (idx === undefined) return this._subIndustryOptionsAll;
        return this._subIndustryOptionsAll.filter(opt => Array.isArray(opt.validFor) && opt.validFor.includes(idx));
    }

    // ─── Navigation ────────────────────────────────────────────────────────────

    handleRowClick(event) {
        const id = event.currentTarget.dataset.id;
        this.selectedInternshipId = id;
        this.currentView = 'detail';
        this._resetDocForm();
        if (!this.documentsMap[id]) {
            this._loadDocs(id);
        }
    }

    handleBackToList() {
        this.currentView = 'list';
        this.selectedInternshipId = null;
        this._resetDocForm();
    }

    // ─── Edit internship (from detail view) ───────────────────────────────────

    handleEdit() {
        // Check if record is read-only
        if (this.isReadOnly) {
            this._showToast('Warning', 'This internship record is read-only and cannot be edited.', 'warning');
            return;
        }
        
        const rec = this.internships.find(r => r.Id === this.selectedInternshipId);
        this.selectedRecord       = { ...rec };
        this.expandedInternshipId = this.selectedInternshipId;
        this.formErrors           = {};
        this.modalStep            = 'form';
        this.isWizardMode         = false;
        this.isModalOpen          = true;
        this._resetDocForm();
        if (!this.documentsMap[this.selectedInternshipId]) {
            this._loadDocs(this.selectedInternshipId);
        }
    }

    // ─── Add new internship (wizard flow) ─────────────────────────────────────

    handleAdd() {
        // Initialize wizard
        this.selectedRecord        = {};
        this.formErrors            = {};
        this.wizardStep            = 1;
        this.wizardDocuments       = [];
        this.createdInternshipId   = null;
        this.uploadingDocIndex     = -1;
        this.isWizardMode          = true;
        this.isModalOpen           = true;
    }

    // ─── Wizard Step Navigation ──────────────────────────────────────────────

    handleWizardNext() {
        if (this.wizardStep === 1) {
            // Validate internship details
            if (!this._validateForm()) {
                this._showToast('', 'Please fix the validation errors before continuing.', 'error');
                return;
            }
            // Move to documents step
            this.wizardStep = 2;
            // Initialize with at least one empty document
            if (this.wizardDocuments.length === 0) {
                this.wizardDocuments = [BLANK_WIZARD_DOC()];
            }
        } else if (this.wizardStep === 2) {
            // Validate documents before final submission
            if (!this._validateWizardDocuments()) {
                return;
            }
            // Create internship with documents
            this._createInternshipTransaction();
        }
    }

    handleWizardBack() {
        if (this.wizardStep === 2) {
            this.wizardStep = 1;
        }
    }

    handleWizardCancel() {
        this.isModalOpen           = false;
        this.isWizardMode          = false;
        this.wizardStep            = 1;
        this.wizardDocuments       = [];
        this.selectedRecord        = {};
        this.formErrors            = {};
        this.createdInternshipId   = null;
        this.uploadingDocIndex     = -1;
        this.uploadStatusMessage   = '';
        this.isSaving              = false;
    }

    // ─── Wizard Document Management ───────────────────────────────────────────

    handleAddWizardDoc() {
        this.wizardDocuments = [...this.wizardDocuments, BLANK_WIZARD_DOC()];
    }

    handleRemoveWizardDoc(event) {
        const tempId = event.currentTarget.dataset.id;
        this.wizardDocuments = this.wizardDocuments.filter(doc => doc.tempId != tempId);
    }

    handleWizardDocFieldChange(event) {
        const tempId = event.target.dataset.docid;
        const field = event.target.dataset.field;
        const value = event.detail.value;
        
        this.wizardDocuments = this.wizardDocuments.map(doc => {
            if (doc.tempId == tempId) {
                const updated = { ...doc, [field]: value };
                if (field === 'Document_Type__c') updated.typeError = '';
                if (field === 'Document_Title__c') updated.titleError = '';
                return updated;
            }
            return doc;
        });

        // Clear native validity on the changed element
        const el = this.template.querySelector(`[data-docid="${tempId}"][data-field="${field}"]`);
        if (el) { el.setCustomValidity(''); el.reportValidity(); }

        // Real-time validation for duplicate types
        if (field === 'Document_Type__c' && value && value !== 'Other') {
            const count = this.wizardDocuments.filter(d => d.Document_Type__c === value).length;
            if (count > 1) {
                this._showToast('Warning', `Duplicate document type: "${value}". Only one of each type is allowed.`, 'warning');
            }
        }
    }

    handleWizardFileSelect(event) {
        const tempId = event.target.dataset.docid;
        const files = event.target.files;
        
        if (files && files.length > 0) {
            const file = files[0];
            this.wizardDocuments = this.wizardDocuments.map(doc => {
                if (doc.tempId == tempId) {
                    return { 
                        ...doc, 
                        fileName: file.name,
                        fileData: file,
                        hasFile: true,
                        fileError: ''
                    };
                }
                return doc;
            });
        }
    }

    _validateWizardDocuments() {
        const REQUIRED_TYPES = [
            'Summer Internship Offer Letter',
            'Internship Completion Certificate'
        ];

        let isValid = true;

        // Per-document field-level validation
        const updatedDocs = this.wizardDocuments.map(doc => {
            const errors = { typeError: '', titleError: '', fileError: '' };

            if (!doc.Document_Type__c) {
                errors.typeError = 'Document Type is required.';
                isValid = false;
            }
            if (!doc.Document_Title__c || !doc.Document_Title__c.trim()) {
                errors.titleError = 'Document Title is required.';
                isValid = false;
            }
            if (!doc.hasFile || !doc.fileData) {
                errors.fileError = 'Please select a file to upload.';
                isValid = false;
            }

            // Apply native validity to combobox/input elements
            const typeEl = this.template.querySelector(`[data-docid="${doc.tempId}"][data-field="Document_Type__c"]`);
            if (typeEl) { typeEl.setCustomValidity(errors.typeError); typeEl.reportValidity(); }
            const titleEl = this.template.querySelector(`[data-docid="${doc.tempId}"][data-field="Document_Title__c"]`);
            if (titleEl) { titleEl.setCustomValidity(errors.titleError); titleEl.reportValidity(); }

            return { ...doc, ...errors };
        });

        this.wizardDocuments = updatedDocs;

        if (!isValid) return false;

        // Aggregate: both required types must be present
        const presentTypes = this.wizardDocuments.map(d => d.Document_Type__c);
        const missingTypes = REQUIRED_TYPES.filter(type => !presentTypes.includes(type));
        if (missingTypes.length > 0) {
            const missingList = missingTypes.map(t => `"${t}"`).join(' & ');
            this._showToast('', `Required documents missing: ${missingList}. Both must be added.`, 'error');
            return false;
        }

        // Aggregate: no duplicate types (excluding 'Other')
        const seen = [];
        for (const doc of this.wizardDocuments) {
            if (doc.Document_Type__c !== 'Other') {
                if (seen.includes(doc.Document_Type__c)) {
                    this._showToast('', `Duplicate document type: "${doc.Document_Type__c}". Only one of each type is allowed.`, 'error');
                    return false;
                }
                seen.push(doc.Document_Type__c);
            }
        }

        return true;
    }

    _createInternshipTransaction() {
        this.isSaving = true;
        this.uploadStatusMessage = 'Creating internship and document records...';

        // Prepare internship record
        const record = { ...this.selectedRecord };
        if (!record.Program_Enrollment__c && this.programEnrollmentId) {
            record.Program_Enrollment__c = this.programEnrollmentId;
        }

        // Prepare document metadata (only those with both type and title)
        const documentMetadata = this.wizardDocuments
            .filter(doc => doc.Document_Type__c && doc.Document_Title__c)
            .map(doc => ({
                documentType: doc.Document_Type__c,
                documentTitle: doc.Document_Title__c,
                notes: doc.Notes__c || ''
            }));

        // Call Apex to create everything in one transaction
        createInternshipWithDocuments({ 
            internshipRecord: record, 
            documentMetadataList: documentMetadata 
        })
            .then(result => {
                this.createdInternshipId = result.internshipId;
                
                // Map document IDs to wizard documents
                this.wizardDocuments = this.wizardDocuments.map((wizDoc, index) => {
                    if (wizDoc.Document_Type__c && wizDoc.Document_Title__c && result.documentIds[index]) {
                        return { ...wizDoc, recordId: result.documentIds[index] };
                    }
                    return wizDoc;
                });

                // Trigger automatic file uploads
                this._triggerFileUploads();

                // Refresh the internships list
                return refreshApex(this._internshipsWireResult);
            })
            .catch(err => {
                this.isSaving = false;
                this.uploadStatusMessage = '';
                this._showToast('', this._extractMessage(err), 'error');
            });
    }

    _triggerFileUploads() {
        // Upload all files sequentially
        const docsWithFiles = this.wizardDocuments.filter(doc => doc.recordId && doc.fileData);
        
        if (docsWithFiles.length === 0) {
            this.isSaving = false;
            this.uploadStatusMessage = '';
            this._showToast('Success', 'Internship created successfully and marked as read-only.', 'success');
            this.handleWizardCancel();
            // Navigate back to list view
            this.currentView = 'list';
            return;
        }

        this.uploadStatusMessage = 'Uploading files (0 of ' + docsWithFiles.length + ')...';
        // Upload files one by one
        this._uploadFiles(docsWithFiles, 0);
    }

    _uploadFiles(docs, index) {
        if (index >= docs.length) {
            // All files uploaded
            this.isSaving = false;
            this.uploadStatusMessage = '';
            this._showToast('Success', 'Internship created successfully. All files uploaded and marked as read-only.', 'success');
            this.handleWizardCancel();
            // Navigate back to list view
            this.currentView = 'list';
            return;
        }

        const doc = docs[index];
        const file = doc.fileData;
        
        // Update progress message
        this.uploadStatusMessage = 'Uploading file ' + (index + 1) + ' of ' + docs.length + ': ' + doc.fileName;
        
        const reader = new FileReader();

        reader.onload = () => {
            const base64 = reader.result.split(',')[1];
            
            uploadFileToDocument({
                documentId: doc.recordId,
                fileName: doc.fileName,
                base64Data: base64
            })
                .then(() => {
                    // Upload next file
                    this._uploadFiles(docs, index + 1);
                })
                .catch(err => {
                    this.isSaving = false;
                    this.uploadStatusMessage = '';
                    this._showToast('', 'Failed to upload file ' + doc.fileName + ': ' + this._extractMessage(err), 'error');
                });
        };

        reader.onerror = () => {
            this.isSaving = false;
            this.uploadStatusMessage = '';
            this._showToast('', 'Failed to read file: ' + doc.fileName, 'error');
        };

        reader.readAsDataURL(file);
    }

    // ─── Modal tab switching ──────────────────────────────────────────────────

    handleGoToDocs() {
        this.modalStep = 'docs';
        this._resetDocForm();
        if (this.expandedInternshipId && !this.documentsMap[this.expandedInternshipId]) {
            this._loadDocs(this.expandedInternshipId);
        }
    }

    handleGoToForm() {
        this.modalStep = 'form';
        this._resetDocForm();
    }

    // ─── Modal close ──────────────────────────────────────────────────────────

    handleModalCancel() {
        this.isModalOpen          = false;
        this.isWizardMode         = false;
        this.selectedRecord       = {};
        this.formErrors           = {};
        this.modalStep            = 'form';
        this.expandedInternshipId = null;
        this._resetDocForm();
    }

    handleModalDone() {
        this.isModalOpen = false;
        this.modalStep   = 'form';
        this._resetDocForm();
        // Keep expandedRowId so detail panel stays open for the saved/edited record
    }

    // ─── Field change ─────────────────────────────────────────────────────────

    handleFieldChange(event) {
        const field = event.target.dataset.field;
        const value = event.detail.value;
        this.selectedRecord = { ...this.selectedRecord, [field]: value };
        if (field === 'Industry__c') {
            this.selectedRecord = { ...this.selectedRecord, Sub_Industry__c: null };
            const subEl = this.template.querySelector('[data-field="Sub_Industry__c"]');
            if (subEl) { subEl.setCustomValidity(''); subEl.reportValidity(); }
        }
        // Clear validity on the changed field immediately
        const el = this.template.querySelector(`[data-field="${field}"]`);
        if (el) { el.setCustomValidity(''); el.reportValidity(); }
        // Re-validate date range in real-time
        if (field === 'Start_Date__c' || field === 'End_Date__c') {
            const r = this.selectedRecord;
            const startEl = this.template.querySelector('[data-field="Start_Date__c"]');
            if (startEl && r.Start_Date__c && r.End_Date__c && r.Start_Date__c > r.End_Date__c) {
                startEl.setCustomValidity('Start Date cannot be after End Date.');
                startEl.reportValidity();
            }
        }
    }

    // ─── Save internship ──────────────────────────────────────────────────────

    handleSave() {
        if (!this._validateForm()) return;
        this.isSaving = true;
        const record = { ...this.selectedRecord };
        if (!record.Program_Enrollment__c && this.programEnrollmentId) {
            record.Program_Enrollment__c = this.programEnrollmentId;
        }
        saveInternship({ record })
            .then(savedId => {
                this.expandedInternshipId = savedId;
                this.selectedInternshipId = savedId;
                return refreshApex(this._internshipsWireResult);
            })
            .then(() => {
                this.isSaving = false;
                this.modalStep = 'docs';
                this._loadDocs(this.expandedInternshipId);
                this._showToast('Success', 'Internship details saved.', 'success');
            })
            .catch(err => {
                this.isSaving = false;
                this._showToast('', this._extractMessage(err), 'error');
            });
    }

    // ─── Delete internship (removed - no longer needed) ──────────────────────

    // ─── Submit functionality (removed) ───────────────────────────────────────

    // ─── Validation ───────────────────────────────────────────────────────────

    _validateForm() {
        const r = this.selectedRecord;
        let isValid = true;

        const setValidity = (selector, msg) => {
            const el = this.template.querySelector(selector);
            if (el) {
                el.setCustomValidity(msg);
                el.reportValidity();
            }
            if (msg) isValid = false;
        };

        setValidity('[data-field="Company_Name__c"]',
            (!r.Company_Name__c || !r.Company_Name__c.trim()) ? 'Company Name is required.' : '');

        setValidity('[data-field="Designation__c"]',
            (!r.Designation__c || !r.Designation__c.trim()) ? 'Designation is required.' : '');

        const startDateErr = !r.Start_Date__c
            ? 'Start Date is required.'
            : (r.Start_Date__c && r.End_Date__c && r.Start_Date__c > r.End_Date__c
                ? 'Start Date cannot be after End Date.' : '');
        setValidity('[data-field="Start_Date__c"]', startDateErr);

        setValidity('[data-field="End_Date__c"]',
            !r.End_Date__c ? 'End Date is required.' : '');

        setValidity('[data-field="Job_Location__c"]',
            (!r.Job_Location__c || !r.Job_Location__c.trim()) ? 'Job Location is required.' : '');

        setValidity('[data-field="Industry__c"]',
            !r.Industry__c ? 'Industry is required.' : '');

        setValidity('[data-field="Sub_Industry__c"]',
            !r.Sub_Industry__c ? 'Sub Industry is required.' : '');

        setValidity('[data-field="Job_Function__c"]',
            !r.Job_Function__c ? 'Job Function is required.' : '');

        const stipendVal = r.Total_Stipend__c;
        const stipendErr = (stipendVal === null || stipendVal === undefined || stipendVal === '')
            ? 'Total Stipend is required.'
            : (Number(stipendVal) < 0 ? 'Total Stipend cannot be negative.' : '');
        setValidity('[data-field="Total_Stipend__c"]', stipendErr);

        setValidity('[data-field="Stipend_Currency__c"]',
            !r.Stipend_Currency__c ? 'Stipend Currency is required.' : '');

        this.formErrors = {};
        return isValid;
    }

    // ─── Document handlers ────────────────────────────────────────────────────

    _loadDocs(internshipId) {
        getDocuments({ internshipId })
            .then(docs => {
                this.documentsMap = { ...this.documentsMap, [internshipId]: docs };
            })
            .catch(err => {
                this._showToast('', this._extractMessage(err), 'error');
            });
    }

    handleShowAddDoc() {
        // Check if internship is read-only
        if (this.isReadOnly) {
            this._showToast('Warning', 'Cannot add documents to a read-only internship record.', 'warning');
            return;
        }
        
        this._resetDocForm();
        this.showAddDocForm = true;
    }

    handleCancelAddDoc() {
        this._resetDocForm();
    }

    handleDocFieldChange(event) {
        const field = event.target.dataset.field;
        const value = event.detail.value;
        this.newDoc = { ...this.newDoc, [field]: value };
        if (field === 'Document_Type__c') {
            this.docTypeError  = '';
            this.docTitleError = '';
            // Clear native validity on all matching elements (detail + modal forms)
            this.template.querySelectorAll('[data-field="Document_Type__c"]').forEach(el => {
                el.setCustomValidity(''); el.reportValidity();
            });
            this._validateDocType(value);
        } else if (field === 'Document_Title__c') {
            this.docTitleError = '';
            this.template.querySelectorAll('[data-field="Document_Title__c"]').forEach(el => {
                el.setCustomValidity(''); el.reportValidity();
            });
        }
    }

    _validateDocType(docType) {
        if (!docType || !SINGLE_UPLOAD_TYPES.has(docType)) return;
        const exists = (this.documentsMap[this.currentDocSourceId] || [])
            .some(d => d.Document_Type__c === docType);
        if (exists) {
            this.docTypeError = `A "${docType}" has already been uploaded for this internship.`;
        }
    }

    handleSaveDocMetadata() {
        let formValid = true;
        if (!this.newDoc.Document_Type__c) {
            this.docTypeError = 'Document Type is required.';
            this.template.querySelectorAll('[data-field="Document_Type__c"]').forEach(el => {
                el.setCustomValidity('Document Type is required.'); el.reportValidity();
            });
            formValid = false;
        } else if (this.docTypeError) {
            this.template.querySelectorAll('[data-field="Document_Type__c"]').forEach(el => {
                el.setCustomValidity(this.docTypeError); el.reportValidity();
            });
            formValid = false;
        }
        if (!this.newDoc.Document_Title__c || !this.newDoc.Document_Title__c.trim()) {
            this.docTitleError = 'Document Title is required.';
            this.template.querySelectorAll('[data-field="Document_Title__c"]').forEach(el => {
                el.setCustomValidity('Document Title is required.'); el.reportValidity();
            });
            formValid = false;
        }
        if (!formValid) return;
        this.isCreatingDoc = true;
        const doc = { ...this.newDoc, Internship_Details__c: this.currentDocSourceId };
        createDocumentRecord({ doc })
            .then(id => {
                this.newDocRecordId = id;
                this.docFormStep    = 2;
                this.isCreatingDoc  = false;
            })
            .catch(err => {
                this.isCreatingDoc = false;
                this.docTypeError  = this._extractMessage(err);
            });
    }

    handleUploadFinished() {
        const src = this.currentDocSourceId;
        this._resetDocForm();
        this._loadDocs(src);
        this._showToast('Success', 'Document uploaded successfully.', 'success');
    }

    handleSkipFileUpload() {
        const src = this.currentDocSourceId;
        this._resetDocForm();
        this._loadDocs(src);
        this._showToast('Info', 'Document record saved. No file was attached.', 'info');
    }

    // ─── Delete document ──────────────────────────────────────────────────────

    handleDeleteDoc(event) {
        event.stopPropagation();
        
        // Check if internship is read-only
        if (this.isReadOnly) {
            this._showToast('Warning', 'Cannot delete documents from a read-only internship record.', 'warning');
            return;
        }
        
        this.deleteDocId = event.currentTarget.dataset.id;
        this.showDeleteDocModal = true;
    }

    handleDeleteDocCancel() {
        this.showDeleteDocModal = false;
        this.deleteDocId = null;
    }

    handleDeleteDocConfirm() {
        this.isDeletingDoc = true;
        const docId = this.deleteDocId;
        const internshipId = this.selectedInternshipId || this.expandedInternshipId;
        
        deleteDocument({ documentRecordId: docId })
            .then(() => {
                this.isDeletingDoc = false;
                this.showDeleteDocModal = false;
                this.deleteDocId = null;
                this._loadDocs(internshipId);
                this._showToast('Success', 'Document deleted successfully.', 'success');
            })
            .catch(err => {
                this.isDeletingDoc = false;
                this._showToast('', this._extractMessage(err), 'error');
            });
    }

    _resetDocForm() {
        this.showAddDocForm = false;
        this.docFormStep    = 1;
        this.newDoc         = BLANK_NEW_DOC();
        this.newDocRecordId = null;
        this.docTypeError   = '';
        this.docTitleError  = '';
        this.isCreatingDoc  = false;
    }

    handlePreviewDoc(event) {
        event.stopPropagation();
        const docRecordId = event.currentTarget.dataset.id;
        
        // Find the document from the maps to get its title
        let docTitle = 'Document';
        for (const internshipId in this.documentsMap) {
            const doc = this.documentsMap[internshipId].find(d => d.Id === docRecordId);
            if (doc) {
                docTitle = doc.Document_Title__c || doc.Document_Type__c || 'Document';
                break;
            }
        }
        
        // Get the file metadata for preview
        getDocumentPreviewData({ documentRecordId: docRecordId })
            .then(fileData => {
                if (fileData) {
                    this.previewContentDocId = fileData.contentDocumentId;
                    this.previewFileName = fileData.title || docTitle;
                    
                    const ext = (fileData.fileExtension || '').toLowerCase();
                    const versionId = fileData.contentVersionId;
                    
                    // Check if it's a PDF
                    this.previewIsPdf = ext === 'pdf';
                    
                    // Generate appropriate preview URL based on file type
                    this.previewSrc = this._getPreviewSrc(ext, versionId);
                    this.showFilePreview = true;
                } else {
                    this._showToast('Warning', 'No file attached to this document record.', 'warning');
                }
            })
            .catch(err => {
                this._showToast('', 'Failed to preview document: ' + this._extractMessage(err), 'error');
            });
    }

    _getPreviewSrc(fileExt, versionId) {
        if (!versionId) return '';
        const base = `/sfc/servlet.shepherd/version/renditionDownload?versionId=${versionId}`;
        
        // For PNG/JPG, use original quality
        if (fileExt === 'png') {
            return `${base}&rendition=ORIGINAL_Png`;
        }
        if (fileExt === 'jpg' || fileExt === 'jpeg') {
            return `${base}&rendition=ORIGINAL_Jpg`;
        }
        // For PDFs and other files, use thumbnail rendition (first page for PDFs)
        return `${base}&rendition=THUMB720BY480`;
    }

    closeFilePreview() {
        this.showFilePreview     = false;
        this.previewSrc          = '';
        this.previewFileName     = '';
        this.previewIsPdf        = false;
        this.previewContentDocId = '';
    }

    // ─── Utilities ────────────────────────────────────────────────────────────

    _formatDate(dateString) {
        if (!dateString) return '';
        
        const date = new Date(dateString + 'T00:00:00');
        const day = date.getDate();
        const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        const month = monthNames[date.getMonth()];
        const year = date.getFullYear();
        
        // Add ordinal suffix
        let suffix = 'th';
        if (day === 1 || day === 21 || day === 31) suffix = 'st';
        else if (day === 2 || day === 22) suffix = 'nd';
        else if (day === 3 || day === 23) suffix = 'rd';
        
        return `${day}${suffix} ${month} ${year}`;
    }

    _showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    _extractMessage(err) {
        return (err && err.body && err.body.message) ? err.body.message : 'An unexpected error occurred.';
    }
}