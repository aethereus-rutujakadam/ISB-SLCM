import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getCohorts from '@salesforce/apex/FeedbackManagementController.getCohorts';
import getTerms from '@salesforce/apex/FeedbackManagementController.getTerms';
import getCourseOfferings from '@salesforce/apex/FeedbackManagementController.getCourseOfferings';
import getRecipientsForPreview from '@salesforce/apex/FeedbackManagementController.getRecipientsForPreview';
import getTemplatesForScenario from '@salesforce/apex/FeedbackManagementController.getTemplatesForScenario';
import getAllAcademicAssociates from '@salesforce/apex/FeedbackManagementController.getAllAcademicAssociates';
import triggerFeedback from '@salesforce/apex/FeedbackManagementController.triggerFeedback';

/**
 * @description Feedback Trigger Section component
 * Allows admin to select scenario, filters, and trigger feedback
 */
export default class FeedbackTriggerSection extends LightningElement {
    @api programs = [];
    @api locations = [];
    @api scenarios = [];

    @track selectedScenario = '';
    @track selectedProgram = '';
    @track selectedLocation = '';
    @track selectedCohort = '';
    @track selectedTerm = '';
    @track selectedTemplate = '';
    @track dueDate = '';
    
    @track cohorts = [];
    @track terms = [];
    @track courseOfferings = [];
    @track selectedCourseOfferings = [];
    @track recipients = [];
    @track templates = [];
    @track academicAssociates = [];
    @track selectedAcademicAssociates = [];
    
    @track isLoading = false;
    @track showPreview = false;
    @track showConfirmModal = false;
    @track triggerResult = null;

    // Columns for course offerings table
    courseOfferingColumns = [
        { label: 'Course Name', fieldName: 'courseName', type: 'text' },
        { label: 'Program', fieldName: 'programName', type: 'text' },
        { label: 'Location', fieldName: 'locationName', type: 'text' },
        { label: 'Term', fieldName: 'termName', type: 'text' },
        { label: 'Students', fieldName: 'studentCount', type: 'number' },
        { label: 'Faculty', fieldName: 'facultyCount', type: 'number' },
        { label: 'AAs', fieldName: 'aaCount', type: 'number' }
    ];

    // Columns for recipient preview
    recipientColumns = [
        { label: 'Recipient', fieldName: 'recipientName', type: 'text' },
        { label: 'Email', fieldName: 'recipientEmail', type: 'email' },
        { label: 'Type', fieldName: 'recipientType', type: 'text' },
        { label: 'Course', fieldName: 'courseName', type: 'text' }
    ];

    // AA columns for non-course scenarios
    aaColumns = [
        { label: 'Name', fieldName: 'name', type: 'text' },
        { label: 'Email', fieldName: 'email', type: 'email' },
        { label: 'Program', fieldName: 'programName', type: 'text' }
    ];

    // Computed properties
    get scenarioOptions() {
        return this.scenarios.map(s => ({
            label: s.label,
            value: s.value
        }));
    }

    get programOptions() {
        return this.programs.map(p => ({
            label: p.label,
            value: p.value
        }));
    }

    get locationOptions() {
        return this.locations.map(l => ({
            label: l.label,
            value: l.value
        }));
    }

    get cohortOptions() {
        return this.cohorts.map(c => ({
            label: c.label,
            value: c.value
        }));
    }

    get termOptions() {
        return this.terms.map(t => ({
            label: t.label,
            value: t.value
        }));
    }

    get templateOptions() {
        return this.templates.map(t => ({
            label: t.name,
            value: t.templateId
        }));
    }

    get isCourseBasedScenario() {
        return this.selectedScenario === 'Student-to-AA' || 
               this.selectedScenario === 'Faculty-to-AA';
    }

    get showCourseFilters() {
        return this.isCourseBasedScenario && this.selectedScenario;
    }

    get showAASelection() {
        return !this.isCourseBasedScenario && this.selectedScenario;
    }

    get hasCourseOfferings() {
        return this.courseOfferings.length > 0;
    }

    get hasSelectedCourses() {
        return this.selectedCourseOfferings.length > 0;
    }

    get hasRecipients() {
        return this.recipients.length > 0;
    }

    get canTrigger() {
        if (!this.selectedTemplate) return false;
        if (!this.dueDate) return false;
        
        if (this.isCourseBasedScenario) {
            return this.selectedCourseOfferings.length > 0;
        } else {
            return this.selectedAcademicAssociates.length > 0;
        }
    }
    
    get cannotTrigger() {
        return !this.canTrigger;
    }
    
    get isTemplateDisabled() {
        return !this.selectedScenario;
    }
    
    get isProgramDisabled() {
        return false; // Program is always enabled
    }
    
    get isCohortDisabled() {
        return !this.selectedProgram;
    }
    
    get isTermDisabled() {
        return !this.selectedCohort;
    }

    get recipientCount() {
        return this.recipients.length;
    }

    get feedbackCount() {
        // Count total feedback records that will be created
        let count = 0;
        this.recipients.forEach(r => {
            if (r.academicAssociates) {
                count += r.academicAssociates.length;
            } else {
                count += 1;
            }
        });
        return count;
    }

    get minDueDate() {
        const today = new Date();
        return today.toISOString().split('T')[0];
    }

    // Event handlers
    handleScenarioChange(event) {
        this.selectedScenario = event.detail.value;
        this.resetFilters();
        this.loadTemplatesForScenario();
        
        if (this.showAASelection) {
            this.loadAcademicAssociates();
        }
    }

    handleProgramChange(event) {
        this.selectedProgram = event.detail.value;
        this.selectedCohort = '';
        this.selectedTerm = '';
        this.courseOfferings = [];
        this.loadCohorts();
        
        if (this.showAASelection) {
            this.loadAcademicAssociates();
        }
    }

    handleLocationChange(event) {
        this.selectedLocation = event.detail.value;
        this.loadCourseOfferings();
    }

    handleCohortChange(event) {
        this.selectedCohort = event.detail.value;
        this.selectedTerm = '';
        this.loadTerms();
    }

    handleTermChange(event) {
        this.selectedTerm = event.detail.value;
        this.loadCourseOfferings();
    }

    handleTemplateChange(event) {
        this.selectedTemplate = event.detail.value;
    }

    handleDueDateChange(event) {
        this.dueDate = event.detail.value;
    }

    handleCourseSelection(event) {
        this.selectedCourseOfferings = event.detail.selectedRows.map(row => row.courseOfferingId);
    }

    handleAASelection(event) {
        this.selectedAcademicAssociates = event.detail.selectedRows.map(row => row.aaProfileId);
    }

    // Data loading methods
    async loadCohorts() {
        if (!this.selectedProgram) {
            this.cohorts = [];
            return;
        }
        
        try {
            this.isLoading = true;
            this.cohorts = await getCohorts({ programId: this.selectedProgram });
        } catch (error) {
            this.showError('Error loading cohorts', error);
        } finally {
            this.isLoading = false;
        }
    }

    async loadTerms() {
        if (!this.selectedCohort) {
            this.terms = [];
            return;
        }
        
        try {
            this.isLoading = true;
            this.terms = await getTerms({ cohortId: this.selectedCohort });
        } catch (error) {
            this.showError('Error loading terms', error);
        } finally {
            this.isLoading = false;
        }
    }

    async loadCourseOfferings() {
        try {
            this.isLoading = true;
            this.courseOfferings = await getCourseOfferings({
                programId: this.selectedProgram,
                locationId: this.selectedLocation,
                termId: this.selectedTerm
            });
        } catch (error) {
            this.showError('Error loading course offerings', error);
        } finally {
            this.isLoading = false;
        }
    }

    async loadTemplatesForScenario() {
        if (!this.selectedScenario) {
            this.templates = [];
            return;
        }
        
        try {
            this.isLoading = true;
            this.templates = await getTemplatesForScenario({ scenario: this.selectedScenario });
        } catch (error) {
            this.showError('Error loading templates', error);
        } finally {
            this.isLoading = false;
        }
    }

    async loadAcademicAssociates() {
        try {
            this.isLoading = true;
            this.academicAssociates = await getAllAcademicAssociates({ 
                programId: this.selectedProgram 
            });
        } catch (error) {
            this.showError('Error loading academic associates', error);
        } finally {
            this.isLoading = false;
        }
    }

    async loadRecipientPreview() {
        if (!this.hasSelectedCourses) {
            this.recipients = [];
            return;
        }
        
        try {
            this.isLoading = true;
            this.recipients = await getRecipientsForPreview({
                scenario: this.selectedScenario,
                courseOfferingIds: this.selectedCourseOfferings
            });
            this.showPreview = true;
        } catch (error) {
            this.showError('Error loading recipient preview', error);
        } finally {
            this.isLoading = false;
        }
    }

    // Action handlers
    handlePreviewClick() {
        this.loadRecipientPreview();
    }

    handleTriggerClick() {
        this.showConfirmModal = true;
    }

    handleCancelTrigger() {
        this.showConfirmModal = false;
    }

    async handleConfirmTrigger() {
        this.showConfirmModal = false;
        
        const request = {
            scenario: this.selectedScenario,
            templateId: this.selectedTemplate,
            programId: this.selectedProgram,
            locationId: this.selectedLocation,
            cohortId: this.selectedCohort,
            termId: this.selectedTerm,
            courseOfferingIds: this.isCourseBasedScenario ? this.selectedCourseOfferings : null,
            academicAssociateIds: !this.isCourseBasedScenario ? this.selectedAcademicAssociates : null,
            dueDate: this.dueDate
        };
        
        try {
            this.isLoading = true;
            const result = await triggerFeedback({ requestJson: JSON.stringify(request) });
            this.triggerResult = result;
            
            if (result.success) {
                this.showToast(
                    'Feedback Triggered Successfully',
                    `Created ${result.feedbackRecordsCreated} feedback records. ${result.emailsSent} emails sent.`,
                    'success'
                );
                this.resetAll();
                this.dispatchEvent(new CustomEvent('refresh'));
            } else {
                this.showToast('Error', result.errorMessage, 'error');
            }
        } catch (error) {
            this.showError('Error triggering feedback', error);
        } finally {
            this.isLoading = false;
        }
    }

    // Reset methods
    resetFilters() {
        this.selectedProgram = '';
        this.selectedLocation = '';
        this.selectedCohort = '';
        this.selectedTerm = '';
        this.cohorts = [];
        this.terms = [];
        this.courseOfferings = [];
        this.selectedCourseOfferings = [];
        this.recipients = [];
        this.showPreview = false;
        this.academicAssociates = [];
        this.selectedAcademicAssociates = [];
    }

    resetAll() {
        this.selectedScenario = '';
        this.selectedTemplate = '';
        this.dueDate = '';
        this.templates = [];
        this.resetFilters();
    }

    // Utility methods
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }

    showError(title, error) {
        console.error(title, error);
        const message = error.body?.message || error.message || 'Unknown error';
        this.showToast(title, message, 'error');
    }
}