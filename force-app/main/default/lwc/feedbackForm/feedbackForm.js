import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CurrentPageReference } from 'lightning/navigation';
import getTemplateWithQuestions from '@salesforce/apex/FeedbackController.getTemplateWithQuestions';
import getTemplateFromCase from '@salesforce/apex/FeedbackController.getTemplateFromCase';
import createFeedback from '@salesforce/apex/FeedbackController.createFeedback';
import validateSubmission from '@salesforce/apex/FeedbackController.validateSubmission';
import validateFeedbackEligibility from '@salesforce/apex/FeedbackController.validateFeedbackEligibility';
import getFeedbackRecordTypes from '@salesforce/apex/FeedbackController.getFeedbackRecordTypes';
import getFeedbackByToken from '@salesforce/apex/FeedbackController.getFeedbackByToken';
import getFeedbacksByBatchToken from '@salesforce/apex/FeedbackController.getFeedbacksByBatchToken';
import submitBatchFeedback from '@salesforce/apex/FeedbackController.submitBatchFeedback';

export default class FeedbackForm extends LightningElement {
    
    // URL Parameters
    currentPageReference;
    templateName;
    courseOfferingId;
    facultyId;
    academicAssociateId;
    programId;
    guid;
    recordTypeName;
    caseId;
    feedbackToken; // Token for triggered feedback flow (unique per feedback)
    batchToken; // Batch token for course-wise scenarios (same per recipient)
    
    // Data
    @track templateData = {};
    @track contextData = {};
    @track questions = [];
    @track recordTypeMap = {};
    
    // State Management
    @track isLoading = true;
    @track isSubmitting = false;
    @track errorMessage = '';
    @track alreadySubmitted = false;
    @track submissionSuccess = false;
    @track feedbackId = '';
    @track isAnonymous = false;
    @track allowAnonymous = false;
    @track manualAAName = '';
    @track isTokenBasedFlow = false; // Flag for token-based triggered feedback
    @track isBatchMode = false; // Flag for batch token mode (course-wise scenarios)
    @track isExpired = false; // Token expired state
    @track dueDate = ''; // Due date for token-based feedback
    
    // Batch Mode State
    @track feedbackOptions = []; // List of Course-AA combinations
    @track selectedFeedbackId = ''; // Currently selected feedback record
    @track submittedCount = 0; // Number of already submitted feedbacks
    @track pendingCount = 0; // Number of pending feedbacks

    handleAANameChange(event) {
        this.manualAAName = event.target.value;
    }
    
    // Options
    yesNoOptions = [
        { label: 'Yes', value: 'Yes' },
        { label: 'No', value: 'No' }
    ];
    
    // Wire current page reference to get URL parameters
    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            this.currentPageReference = currentPageReference;
            console.log('URL Parameters:', JSON.stringify(currentPageReference.state));
            
            // Extract URL parameters
            this.templateName = currentPageReference.state?.template || 
                               currentPageReference.state?.c__template;
            this.courseOfferingId = currentPageReference.state?.courseOfferingId || 
                                   currentPageReference.state?.c__courseOfferingId;
            this.facultyId = currentPageReference.state?.facultyId || 
                            currentPageReference.state?.c__facultyId;
            this.academicAssociateId = currentPageReference.state?.academicAssociateId || 
                                       currentPageReference.state?.c__academicAssociateId;
            this.programId = currentPageReference.state?.programId || 
                            currentPageReference.state?.c__programId;
            this.guid = currentPageReference.state?.guid || 
                       currentPageReference.state?.c__guid;
            this.recordTypeName = currentPageReference.state?.recordType || 
                                 currentPageReference.state?.c__recordType;
            this.caseId = currentPageReference.state?.caseId || 
                          currentPageReference.state?.c__caseId ||
                          currentPageReference.state?.CaseId ||
                          currentPageReference.state?.caseid;
            
            // Extract feedback token for triggered feedback flow
            this.feedbackToken = currentPageReference.state?.token || 
                                currentPageReference.state?.c__token ||
                                currentPageReference.state?.t ||
                                currentPageReference.state?.c__t;
            
            // Extract batch token for course-wise scenarios
            this.batchToken = currentPageReference.state?.batch || 
                             currentPageReference.state?.c__batch ||
                             currentPageReference.state?.b ||
                             currentPageReference.state?.c__b;
            
            // Determine if anonymous is allowed
            this.allowAnonymous = !!this.guid;
            
            // Load form after parameters are set
            this.loadFeedbackForm();
        }
    }
    
    /**
     * Load feedback form data
     */
    async loadFeedbackForm() {
        this.isLoading = true;
        this.errorMessage = '';
        
        try {
            // BATCH TOKEN MODE: If batch token provided, load multiple options
            if (this.batchToken) {
                await this.loadFeedbacksByBatchToken();
                return;
            }
            
            // TOKEN-BASED FLOW: If token is provided, load from token
            if (this.feedbackToken) {
                await this.loadFeedbackByToken();
                return;
            }
            
            // Validate template name (only if not using caseId)
            if (!this.templateName && !this.caseId) {
                throw new Error('Template parameter is required in URL. Example: ?template=Faculty-AA. Received params: ' + JSON.stringify(this.currentPageReference?.state));
            }
            
            // Check if GUID already used
            if (this.guid) {
                const isUsed = await validateSubmission({ guid: this.guid });
                if (isUsed) {
                    this.alreadySubmitted = true;
                    this.isLoading = false;
                    return;
                }
            }
            
            // Validate feedback eligibility
            if (this.courseOfferingId && this.academicAssociateId) {
                const eligibility = await validateFeedbackEligibility({
                    courseOfferingId: this.courseOfferingId,
                    academicAssociateId: this.academicAssociateId,
                    submitterEmail: null
                });
                
                if (!eligibility.canSubmit) {
                    this.errorMessage = eligibility.message;
                    this.isLoading = false;
                    return;
                }
            }
            
            // Load record types
            this.recordTypeMap = await getFeedbackRecordTypes();
            
            // Load template with questions
            let data;
            
            if (this.caseId) {
                // Load from Case context
                data = await getTemplateFromCase({
                    caseId: this.caseId,
                    templateName: this.templateName // Optional, can be null
                });
            } else {
                // Load from URL parameters
                data = await getTemplateWithQuestions({
                    templateName: this.templateName,
                    courseOfferingId: this.courseOfferingId,
                    facultyId: this.facultyId,
                    academicAssociateId: this.academicAssociateId,
                    programId: this.programId
                });
            }
            
            console.log('Raw data from Apex:', JSON.stringify(data, null, 2));
            
            if (!data || !data.template) {
                throw new Error('Template not found or inactive: ' + this.templateName);
            }
            
            this.templateData = data;
            
            // Update templateName from loaded template (crucial for getSubmitterType)
            if (data.template && data.template.Name) {
                this.templateName = data.template.Name;
            }
            
            this.contextData = data.context || {};
            
            // Process questions
            this.processQuestions(data.questions || []);
            
        } catch (error) {
            console.error('Error loading feedback form:', error);
            this.errorMessage = error.body?.message || error.message || 'Unknown error occurred';
        } finally {
            this.isLoading = false;
        }
    }
    
    /**
     * Load feedback form using token (for triggered feedback flow)
     */
    async loadFeedbackByToken() {
        try {
            const result = await getFeedbackByToken({ token: this.feedbackToken });
            
            if (!result.isValid) {
                this.errorMessage = result.errorMessage || 'Invalid feedback link';
                this.isLoading = false;
                return;
            }
            
            if (result.isAlreadySubmitted) {
                this.alreadySubmitted = true;
                this.isLoading = false;
                return;
            }
            
            if (result.isExpired) {
                this.isExpired = true;
                this.errorMessage = 'This feedback request has expired. The submission deadline has passed.';
                this.isLoading = false;
                return;
            }
            
            // Set token-based flow flag
            this.isTokenBasedFlow = true;
            this.dueDate = result.dueDate;
            
            // Build template data from token result
            this.templateData = {
                template: {
                    Name: result.templateName,
                    Description__c: result.templateDescription
                }
            };
            
            // Update template name
            this.templateName = result.templateName;
            
            // Build context data
            this.contextData = {
                academicAssociateName: result.aaName,
                courseOfferingName: result.courseName,
                academicAssociateId: result.academicAssociateId,
                courseOfferingId: result.courseOfferingId
            };
            
            // Store feedback ID for update
            this.feedbackId = result.feedbackId;
            
            // Process questions
            this.processQuestionsFromToken(result.questions || []);
            
        } catch (error) {
            console.error('Error loading feedback by token:', error);
            this.errorMessage = error.body?.message || error.message || 'Unable to load feedback form';
        } finally {
            this.isLoading = false;
        }
    }
    
    /**
     * Load feedback form using batch token (for course-wise scenarios)
     * Shows picklist of Course-AA combinations
     */
    async loadFeedbacksByBatchToken() {
        try {
            const result = await getFeedbacksByBatchToken({ batchToken: this.batchToken });
            
            if (!result.isValid) {
                this.errorMessage = result.errorMessage || 'Invalid feedback link';
                this.isLoading = false;
                return;
            }
            
            // Set batch mode flag
            this.isBatchMode = true;
            this.dueDate = result.dueDate;
            
            // Build template data
            this.templateData = {
                template: {
                    Name: result.templateName,
                    Description__c: 'Please select a course and Academic Associate combination to provide feedback.'
                }
            };
            
            this.templateName = result.templateName;
            
            // Store feedback options for picklist
            this.feedbackOptions = result.feedbackOptions.map(opt => ({
                label: opt.displayLabel,
                value: opt.feedbackId,
                isSubmitted: opt.isSubmitted,
                feedbackId: opt.feedbackId,
                academicAssociateId: opt.academicAssociateId,
                academicAssociateName: opt.academicAssociateName,
                courseOfferingId: opt.courseOfferingId,
                courseName: opt.courseName
            }));
            
            this.submittedCount = result.submittedCount || 0;
            this.pendingCount = result.pendingCount || 0;
            
            // Process questions (same for all options)
            this.processQuestionsFromToken(result.questions || []);
            
        } catch (error) {
            console.error('Error loading batch feedback:', error);
            this.errorMessage = error.body?.message || error.message || 'Unable to load feedback form';
        } finally {
            this.isLoading = false;
        }
    }
    
    /**
     * Handle feedback option selection from picklist
     */
    handleFeedbackOptionChange(event) {
        const selectedId = event.target.value;
        this.selectedFeedbackId = selectedId;
        
        // Find the selected option and update context
        const selectedOption = this.feedbackOptions.find(opt => opt.feedbackId === selectedId);
        if (selectedOption) {
            this.contextData = {
                academicAssociateName: selectedOption.academicAssociateName,
                courseOfferingName: selectedOption.courseName,
                academicAssociateId: selectedOption.academicAssociateId,
                courseOfferingId: selectedOption.courseOfferingId
            };
        }
    }
    
    /**
     * Process questions from token-based response
     */
    processQuestionsFromToken(rawQuestions) {
        this.questions = rawQuestions.map((q, index) => {
            const question = {
                Id: q.questionId,
                Question_Text__c: q.questionText,
                Question_Type_c__c: q.questionType,
                Required__c: q.isRequired,
                Weightage__c: q.weightage,
                Min_Rating__c: q.minRating || 1,
                Max_Rating__c: q.maxRating || 5,
                Picklist_Options__c: q.picklistOptions
            };
            
            // Add display order
            question.displayOrder = q.displayOrder || (index + 1);
            
            // Get question type
            const type = q.questionType;
            
            // Set type flags
            question.isText = (type === 'Text');
            question.isRating = (type === 'Rating');
            question.isPicklist = (type === 'Picklist');
            question.isMultiSelect = (type === 'Multi-Select');
            question.isYesNo = (type === 'Yes/No');
            
            // Initialize answer
            question.answer = question.isMultiSelect ? [] : '';
            
            // Process rating options
            if (question.isRating) {
                const min = q.minRating || 1;
                const max = q.maxRating || 5;
                question.ratingOptions = [];
                
                for (let i = min; i <= max; i++) {
                    question.ratingOptions.push({
                        label: String(i),
                        value: String(i)
                    });
                }
                
                question.minLabel = this.getRatingLabel(min);
                question.maxLabel = this.getRatingLabel(max);
            }
            
            // Process picklist options
            if (question.isPicklist || question.isMultiSelect) {
                question.picklistOptions = [];
                
                if (q.picklistOptions) {
                    const options = q.picklistOptions.split(';');
                    question.picklistOptions = options.map(opt => ({
                        label: opt.trim(),
                        value: opt.trim()
                    }));
                }
            }
            
            return question;
        });
    }
    
    /**
     * Process questions and prepare for rendering
     */
    processQuestions(rawQuestions) {
        console.log('Processing ' + rawQuestions.length + ' questions');
        
        this.questions = rawQuestions.map((q, index) => {
            const question = { ...q };
            
            // Add display order
            question.displayOrder = index + 1;
            
            // DEBUG: Log the question type field value
            console.log('Question ' + (index + 1) + ' Type Field:', q.Question_Type_c__c);
            console.log('Full question object:', JSON.stringify(q, null, 2));
            
            // Get question type - try multiple field name variations
            const type = q.Question_Type_c__c;
            
            console.log('Extracted type for Q' + (index + 1) + ':', type);
            
            // Set type flags - EXACT MATCH required
            question.isText = (type === 'Text');
            question.isRating = (type === 'Rating');
            question.isPicklist = (type === 'Picklist');
            question.isMultiSelect = (type === 'Multi-Select');
            question.isYesNo = (type === 'Yes/No');
            
            // DEBUG: Log which flag was set
            console.log('Question ' + (index + 1) + ' flags:', {
                isText: question.isText,
                isRating: question.isRating,
                isPicklist: question.isPicklist,
                isMultiSelect: question.isMultiSelect,
                isYesNo: question.isYesNo
            });
            
            // If no flag is true, there's a mismatch
            if (!question.isText && !question.isRating && !question.isPicklist && 
                !question.isMultiSelect && !question.isYesNo) {
                console.error('⚠️ NO TYPE MATCH for question ' + (index + 1) + 
                            '! Type value is: "' + type + '"');
            }
            
            // Initialize answer
            question.answer = question.isMultiSelect ? [] : '';
            
            // Process rating options
            if (question.isRating) {
                const min = q.Min_Rating__c || 1;
                const max = q.Max_Rating__c || 5;
                question.ratingOptions = [];
                
                for (let i = min; i <= max; i++) {
                    question.ratingOptions.push({
                        label: String(i),
                        value: String(i)
                    });
                }
                
                question.minLabel = this.getRatingLabel(min);
                question.maxLabel = this.getRatingLabel(max);
                
                console.log('Rating options created:', question.ratingOptions);
            }
            
            // Process picklist options
            if (question.isPicklist || question.isMultiSelect) {
                question.picklistOptions = [];
                
                if (q.Picklist_Options__c) {
                    const options = q.Picklist_Options__c.split('\n');
                    question.picklistOptions = options.map(opt => ({
                        label: opt.trim(),
                        value: opt.trim()
                    }));
                    console.log('Picklist options:', question.picklistOptions);
                }
            }
            
            return question;
        });
        
        console.log('Final processed questions:', JSON.stringify(this.questions, null, 2));
    }
    
    /**
     * Get rating label based on value
     */
    getRatingLabel(value) {
        const labels = {
            1: 'Very Dissatisfied / Very Poor',
            2: 'Dissatisfied / Poor',
            3: 'Neutral / Average',
            4: 'Satisfied / Good',
            5: 'Very Satisfied / Excellent'
        };
        return labels[value] || '';
    }
    
    /**
     * Handle answer change
     */
    handleAnswerChange(event) {
        const questionId = event.target.dataset.id;
        const value = event.target.value;
        
        console.log('Answer changed for question:', questionId, 'Value:', value);
        
        const question = this.questions.find(q => q.Id === questionId);
        if (question) {
            question.answer = value;
            console.log('Updated answer:', question.answer);
        }
    }
    
    /**
     * Handle anonymous checkbox change
     */
    handleAnonymousChange(event) {
        this.isAnonymous = event.target.checked;
    }
    
    /**
     * Validate all required questions
     */
    validateAnswers() {
        let isValid = true;
        const errors = [];
        
        this.questions.forEach(question => {
            if (question.Required__c) {
                const answer = question.answer;
                
                if (
                    answer === '' || 
                    answer === null || 
                    answer === undefined ||
                    (Array.isArray(answer) && answer.length === 0)
                ) {
                    isValid = false;
                    errors.push(`Question ${question.displayOrder} is required`);
                }
            }
        });
        
        if (!isValid) {
            console.error('Validation errors:', errors);
            this.showToast('Error', 'Please answer all required questions', 'error');
        }
        
        return isValid;
    }
    
    /**
     * Handle form submission
     */
    async handleSubmit() {
        console.log('Submit clicked');
        
        // For batch mode, validate selection
        if (this.isBatchMode && !this.selectedFeedbackId) {
            this.showToast('Error', 'Please select a course and Academic Associate combination', 'error');
            return;
        }
        
        // Validate answers
        if (!this.validateAnswers()) {
            return;
        }
        
        this.isSubmitting = true;
        
        try {
            // BATCH MODE: Use submitBatchFeedback
            if (this.isBatchMode) {
                await this.submitBatchModeFeedback();
                return;
            }
            // Prepare feedback record
            const feedback = {
                sobjectType: 'Feedback__c',
                RecordTypeId: this.getRecordTypeId(),
                Course_Offering__c: this.contextData.courseOfferingId,
                Academic_Associate__c: this.contextData.academicAssociateId,
                Program__c: this.contextData.programId,
                Academic_Term__c: this.contextData.academicTermId,
                Anonymous__c: this.isAnonymous,
                Status__c: 'Published',
                Survey_Response_Id__c: this.guid,
                Submitter_Type__c: this.getSubmitterType()
            };
            
            // Prepare answers
            const answers = this.questions.map((question, index) => {
                const answer = {
                    questionId: question.Id,
                    questionText: question.Question_Text__c,
                    questionType: question.Question_Type_c__c,
                    textAnswer: null,
                    ratingAnswer: null,
                    picklistAnswer: null,
                    order: String(index + 1)
                };
                
                if (question.isText) {
                    answer.textAnswer = question.answer;
                } else if (question.isRating) {
                    answer.ratingAnswer = String(question.answer);
                } else if (question.isPicklist || question.isYesNo) {
                    answer.picklistAnswer = question.answer;
                } else if (question.isMultiSelect) {
                    answer.picklistAnswer = Array.isArray(question.answer) 
                        ? question.answer.join(';') 
                        : question.answer;
                }
                
                return answer;
            });
            
            console.log('Submitting feedback:', feedback);
            console.log('Submitting answers:', answers);
            
            const feedbackWrapper = {
                feedback: feedback,
                answers: answers,
                manualAAName: this.manualAAName,
                templateName: this.templateName,
                caseId: this.caseId,
                facultyId: this.contextData.facultyId,
                feedbackToken: this.isTokenBasedFlow ? this.feedbackToken : null // Include token for triggered feedback
            };
            
            const feedbackId = await createFeedback({ 
                feedbackData: JSON.stringify(feedbackWrapper) 
            });
            
            this.feedbackId = feedbackId;
            this.submissionSuccess = true;
            
            this.showToast('Success', 'Feedback submitted successfully!', 'success');
            
        } catch (error) {
            console.error('Error submitting feedback:', error);
            this.showToast(
                'Error', 
                error.body?.message || error.message || 'Failed to submit feedback', 
                'error'
            );
        } finally {
            this.isSubmitting = false;
        }
    }
    
    /**
     * Submit feedback in batch mode (course-wise scenarios)
     */
    async submitBatchModeFeedback() {
        try {
            // Calculate overall rating if applicable
            const ratingQuestions = this.questions.filter(q => q.isRating && q.answer);
            let overallRating = null;
            if (ratingQuestions.length > 0) {
                const sum = ratingQuestions.reduce((acc, q) => acc + Number(q.answer), 0);
                overallRating = sum / ratingQuestions.length;
            }
            
            // Prepare answers
            const answers = this.questions.map(question => {
                const answer = {
                    questionId: question.Id,
                    ratingValue: null,
                    textValue: null,
                    picklistValue: null
                };
                
                if (question.isRating) {
                    answer.ratingValue = Number(question.answer);
                } else if (question.isText) {
                    answer.textValue = question.answer;
                } else if (question.isPicklist || question.isYesNo) {
                    answer.picklistValue = question.answer;
                } else if (question.isMultiSelect) {
                    answer.picklistValue = Array.isArray(question.answer) 
                        ? question.answer.join(';') 
                        : question.answer;
                }
                
                return answer;
            });
            
            // Get comments from text questions (optional)
            const commentQuestion = this.questions.find(q => 
                q.isText && q.Question_Text__c?.toLowerCase().includes('comment')
            );
            const comments = commentQuestion?.answer || '';
            
            // Submit via batch feedback method
            const success = await submitBatchFeedback({
                feedbackId: this.selectedFeedbackId,
                answersJson: JSON.stringify(answers),
                overallRating: overallRating,
                comments: comments
            });
            
            if (success) {
                this.feedbackId = this.selectedFeedbackId;
                
                // Mark option as submitted
                const submittedOption = this.feedbackOptions.find(
                    opt => opt.feedbackId === this.selectedFeedbackId
                );
                if (submittedOption) {
                    submittedOption.isSubmitted = true;
                    submittedOption.label = submittedOption.label.replace(' (Submitted)', '') + ' (Submitted)';
                }
                
                this.submittedCount++;
                this.pendingCount--;
                
                // Check if all submitted
                if (this.pendingCount === 0) {
                    this.submissionSuccess = true;
                    this.showToast('Success', 'All feedback forms submitted successfully!', 'success');
                } else {
                    // Clear selection and reset form for next submission
                    this.selectedFeedbackId = '';
                    this.questions.forEach(q => {
                        q.answer = q.isMultiSelect ? [] : '';
                    });
                    this.showToast(
                        'Success', 
                        `Feedback submitted! You have ${this.pendingCount} more to complete.`, 
                        'success'
                    );
                }
            }
            
        } catch (error) {
            console.error('Error submitting batch feedback:', error);
            this.showToast(
                'Error',
                error.body?.message || error.message || 'Failed to submit feedback',
                'error'
            );
        } finally {
            this.isSubmitting = false;
        }
    }
    
    /**
     * Get record type ID
     */
    getRecordTypeId() {
        if (this.recordTypeName && this.recordTypeMap[this.recordTypeName]) {
            return this.recordTypeMap[this.recordTypeName];
        }
        
        const templateToRecordType = {
            'Faculty-AA': 'Academic_Associate',
            'Faculty-ASA': 'Faculty',
            'Student-AA': 'Academic_Associate',
            'Student-ASA': 'Student',
            'ASA-AA': 'Academic_Associate'
        };
        
        const rtName = templateToRecordType[this.templateName];
        return this.recordTypeMap[rtName];
    }
    
    /**
     * Get submitter type
     */
    getSubmitterType() {
        if (this.templateName?.includes('Faculty')) return 'Faculty';
        if (this.templateName?.includes('Student')) return 'Student';
        if (this.templateName?.includes('ASA')) return 'ASA Manager';
        return 'Other';
    }
    
    /**
     * Get feedback for
     */
    getFeedbackFor() {
        if (this.templateName?.includes('AA')) return 'Academic Associate';
        if (this.templateName?.includes('ASA')) return 'Academic Services';
        return 'Other';
    }
    
    /**
     * Check if this is ASA feedback (Academic Services)
     */
    get isASAFeedback() {
        if (!this.templateName) return false;
        const templateLower = this.templateName.toLowerCase();
        return templateLower.includes('asa') || templateLower.includes('academic services');
    }
    
    /**
     * Show manual AA input if coming from Case and AA not found
     */
    get showManualAAInput() {
        return this.caseId && !this.contextData.academicAssociateName;
    }

    /**
     * Show Academic Associate name only for non-ASA feedback
     */
    get showAAName() {
        // Only show AA name if:
        // 1. AA name exists in context
        // 2. NOT ASA feedback (based on template name)
        // 3. AA ID was provided in URL
        return this.contextData.academicAssociateName && 
               !this.isASAFeedback && 
               this.academicAssociateId;
    }
    
    /**
     * Show context section
     */
    get showContext() {
        return this.contextData.courseOfferingName || 
               this.contextData.facultyName || 
               this.contextData.academicAssociateName ||
               this.contextData.programName ||
               this.contextData.caseNumber;
    }
    
    /**
     * Check if submit button should be disabled
     */
    get isSubmitDisabled() {
        if (this.isSubmitting) {
            return true;
        }
        // In batch mode, require selection
        if (this.isBatchMode && !this.selectedFeedbackId) {
            return true;
        }
        return false;
    }
    
    /**
     * Get picklist options for batch mode (filter out submitted ones for display clarity)
     */
    get availableFeedbackOptions() {
        return this.feedbackOptions;
    }
    
    /**
     * Show toast
     */
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        }));
    }
}