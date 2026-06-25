import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getTemplates from '@salesforce/apex/FeedbackManagementController.getTemplates';
import createTemplate from '@salesforce/apex/FeedbackManagementController.createTemplate';
import updateTemplate from '@salesforce/apex/FeedbackManagementController.updateTemplate';
import deactivateTemplate from '@salesforce/apex/FeedbackManagementController.deactivateTemplate';
import createQuestion from '@salesforce/apex/FeedbackManagementController.createQuestion';
import updateQuestion from '@salesforce/apex/FeedbackManagementController.updateQuestion';
import deleteQuestion from '@salesforce/apex/FeedbackManagementController.deleteQuestion';
import reorderQuestions from '@salesforce/apex/FeedbackManagementController.reorderQuestions';

/**
 * @description Feedback Template Manager component
 * Allows CRUD operations on templates and questions
 */
export default class FeedbackTemplateManager extends LightningElement {
    @api scenarios = [];

    @track templates = [];
    @track selectedTemplate = null;
    @track isLoading = false;
    @track wiredTemplatesResult;

    // Modal states
    @track showTemplateModal = false;
    @track showQuestionModal = false;
    @track isEditMode = false;

    // Template form data
    @track templateForm = {
        templateId: null,
        name: '',
        applicableFor: '',
        description: '',
        isActive: true
    };

    // Question form data
    @track questionForm = {
        questionId: null,
        templateId: null,
        questionText: '',
        questionType: 'Rating',
        weightage: 1,
        displayOrder: 1,
        isRequired: true,
        picklistOptions: '',
        minRating: 1,
        maxRating: 5
    };

    // Columns for template list
    templateColumns = [
        { label: 'Template Name', fieldName: 'name', type: 'text' },
        { label: 'Applicable For', fieldName: 'applicableFor', type: 'text' },
        { label: 'Questions', fieldName: 'questionCount', type: 'number' },
        { 
            label: 'Status', 
            fieldName: 'isActive', 
            type: 'boolean',
            cellAttributes: { alignment: 'center' }
        },
        {
            type: 'action',
            typeAttributes: {
                rowActions: [
                    { label: 'Edit', name: 'edit' },
                    { label: 'Manage Questions', name: 'questions' },
                    { label: 'Deactivate', name: 'deactivate' }
                ]
            }
        }
    ];

    // Question type options
    get questionTypeOptions() {
        return [
            { label: 'Rating (1-5 Scale)', value: 'Rating' },
            { label: 'Picklist (Single Select)', value: 'Picklist' },
            { label: 'Text Area', value: 'Text' }
        ];
    }

    // Scenario options for template
    get scenarioOptions() {
        return this.scenarios.map(s => ({
            label: s.label,
            value: s.value
        }));
    }

    get isPicklistType() {
        return this.questionForm.questionType === 'Picklist';
    }

    get isRatingType() {
        return this.questionForm.questionType === 'Rating';
    }

    get hasSelectedTemplate() {
        return this.selectedTemplate !== null;
    }

    get selectedTemplateQuestions() {
        return this.selectedTemplate?.questions || [];
    }

    get modalTitle() {
        if (this.showTemplateModal) {
            return this.isEditMode ? 'Edit Template' : 'New Template';
        }
        if (this.showQuestionModal) {
            return this.isEditMode ? 'Edit Question' : 'New Question';
        }
        return '';
    }

    // Wire templates
    @wire(getTemplates)
    wiredTemplates(result) {
        this.wiredTemplatesResult = result;
        const { data, error } = result;
        if (data) {
            this.templates = data;
        } else if (error) {
            this.showError('Error loading templates', error);
        }
    }

    // Template Actions
    handleNewTemplate() {
        this.templateForm = {
            templateId: null,
            name: '',
            applicableFor: '',
            description: '',
            isActive: true
        };
        this.isEditMode = false;
        this.showTemplateModal = true;
    }

    handleTemplateRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;

        switch (action.name) {
            case 'edit':
                this.editTemplate(row);
                break;
            case 'questions':
                this.manageQuestions(row);
                break;
            case 'deactivate':
                this.handleDeactivateTemplate(row.templateId);
                break;
        }
    }

    editTemplate(template) {
        this.templateForm = {
            templateId: template.templateId,
            name: template.name,
            applicableFor: template.applicableFor,
            description: template.description,
            isActive: template.isActive
        };
        this.isEditMode = true;
        this.showTemplateModal = true;
    }

    manageQuestions(template) {
        this.selectedTemplate = template;
    }

    handleTemplateInputChange(event) {
        const field = event.target.name;
        if (field === 'isActive') {
            this.templateForm[field] = event.target.checked;
        } else {
            this.templateForm[field] = event.target.value;
        }
    }

    async handleSaveTemplate() {
        if (!this.validateTemplateForm()) {
            return;
        }

        try {
            this.isLoading = true;
            
            if (this.isEditMode) {
                await updateTemplate({ templateJson: JSON.stringify(this.templateForm) });
                this.showToast('Success', 'Template updated successfully', 'success');
            } else {
                await createTemplate({ templateJson: JSON.stringify(this.templateForm) });
                this.showToast('Success', 'Template created successfully', 'success');
            }
            
            this.showTemplateModal = false;
            await refreshApex(this.wiredTemplatesResult);
            
        } catch (error) {
            this.showError('Error saving template', error);
        } finally {
            this.isLoading = false;
        }
    }

    async handleDeactivateTemplate(templateId) {
        try {
            this.isLoading = true;
            await deactivateTemplate({ templateId });
            this.showToast('Success', 'Template deactivated', 'success');
            await refreshApex(this.wiredTemplatesResult);
        } catch (error) {
            this.showError('Error deactivating template', error);
        } finally {
            this.isLoading = false;
        }
    }

    validateTemplateForm() {
        if (!this.templateForm.name) {
            this.showToast('Validation Error', 'Template name is required', 'error');
            return false;
        }
        if (!this.templateForm.applicableFor) {
            this.showToast('Validation Error', 'Applicable For is required', 'error');
            return false;
        }
        return true;
    }

    // Question Actions
    handleNewQuestion() {
        this.questionForm = {
            questionId: null,
            templateId: this.selectedTemplate.templateId,
            questionText: '',
            questionType: 'Rating',
            weightage: 1,
            displayOrder: (this.selectedTemplateQuestions.length + 1),
            isRequired: true,
            picklistOptions: '',
            minRating: 1,
            maxRating: 5
        };
        this.isEditMode = false;
        this.showQuestionModal = true;
    }

    handleEditQuestion(event) {
        const questionId = event.currentTarget.dataset.id;
        const question = this.selectedTemplateQuestions.find(q => q.questionId === questionId);
        
        if (question) {
            this.questionForm = {
                questionId: question.questionId,
                templateId: this.selectedTemplate.templateId,
                questionText: question.questionText,
                questionType: question.questionType,
                weightage: question.weightage || 1,
                displayOrder: question.displayOrder || 1,
                isRequired: question.isRequired,
                picklistOptions: question.picklistOptions || '',
                minRating: question.minRating || 1,
                maxRating: question.maxRating || 5
            };
            this.isEditMode = true;
            this.showQuestionModal = true;
        }
    }

    handleQuestionInputChange(event) {
        const field = event.target.name;
        if (field === 'isRequired') {
            this.questionForm[field] = event.target.checked;
        } else {
            this.questionForm[field] = event.target.value;
        }
    }

    async handleSaveQuestion() {
        if (!this.validateQuestionForm()) {
            return;
        }

        try {
            this.isLoading = true;
            
            if (this.isEditMode) {
                await updateQuestion({ questionJson: JSON.stringify(this.questionForm) });
                this.showToast('Success', 'Question updated successfully', 'success');
            } else {
                await createQuestion({ questionJson: JSON.stringify(this.questionForm) });
                this.showToast('Success', 'Question created successfully', 'success');
            }
            
            this.showQuestionModal = false;
            await refreshApex(this.wiredTemplatesResult);
            
            // Update selected template
            const updatedTemplates = this.wiredTemplatesResult.data;
            if (updatedTemplates) {
                this.selectedTemplate = updatedTemplates.find(
                    t => t.templateId === this.selectedTemplate.templateId
                );
            }
            
        } catch (error) {
            this.showError('Error saving question', error);
        } finally {
            this.isLoading = false;
        }
    }

    async handleDeleteQuestion(event) {
        const questionId = event.currentTarget.dataset.id;
        
        if (!confirm('Are you sure you want to delete this question?')) {
            return;
        }

        try {
            this.isLoading = true;
            await deleteQuestion({ questionId });
            this.showToast('Success', 'Question deleted', 'success');
            await refreshApex(this.wiredTemplatesResult);
            
            // Update selected template
            const updatedTemplates = this.wiredTemplatesResult.data;
            if (updatedTemplates) {
                this.selectedTemplate = updatedTemplates.find(
                    t => t.templateId === this.selectedTemplate.templateId
                );
            }
        } catch (error) {
            this.showError('Error deleting question', error);
        } finally {
            this.isLoading = false;
        }
    }

    async handleMoveQuestion(event) {
        const questionId = event.currentTarget.dataset.id;
        const direction = event.currentTarget.dataset.direction;
        
        const questions = [...this.selectedTemplateQuestions];
        const currentIndex = questions.findIndex(q => q.questionId === questionId);
        
        if (direction === 'up' && currentIndex > 0) {
            [questions[currentIndex], questions[currentIndex - 1]] = 
            [questions[currentIndex - 1], questions[currentIndex]];
        } else if (direction === 'down' && currentIndex < questions.length - 1) {
            [questions[currentIndex], questions[currentIndex + 1]] = 
            [questions[currentIndex + 1], questions[currentIndex]];
        } else {
            return; // No move needed
        }

        // Build order array
        const orderArray = questions.map((q, index) => ({
            questionId: q.questionId,
            order: index + 1
        }));

        try {
            this.isLoading = true;
            await reorderQuestions({ questionOrderJson: JSON.stringify(orderArray) });
            await refreshApex(this.wiredTemplatesResult);
            
            // Update selected template
            const updatedTemplates = this.wiredTemplatesResult.data;
            if (updatedTemplates) {
                this.selectedTemplate = updatedTemplates.find(
                    t => t.templateId === this.selectedTemplate.templateId
                );
            }
        } catch (error) {
            this.showError('Error reordering questions', error);
        } finally {
            this.isLoading = false;
        }
    }

    validateQuestionForm() {
        if (!this.questionForm.questionText) {
            this.showToast('Validation Error', 'Question text is required', 'error');
            return false;
        }
        if (this.questionForm.questionType === 'Picklist' && !this.questionForm.picklistOptions) {
            this.showToast('Validation Error', 'Picklist options are required for Picklist type', 'error');
            return false;
        }
        return true;
    }

    // Navigation
    handleBackToTemplates() {
        this.selectedTemplate = null;
    }

    handleCloseModal() {
        this.showTemplateModal = false;
        this.showQuestionModal = false;
    }

    // Utilities
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