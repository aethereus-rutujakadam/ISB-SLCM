import { LightningElement, api, track } from 'lwc';
import submitFeedback from '@salesforce/apex/AAStudentFeedbackController.submitFeedback';
import { CurrentPageReference } from 'lightning/navigation';
import { wire } from 'lwc';

export default class StudentFeedbackForm extends LightningElement {
    @api recordId; // Case Id from Experience Site page
    @track overallRating;
    @track comments;
    @track isSubmitting = false;
    @track successMessage;
    @track errorMessage;
    @wire(CurrentPageReference)
    getPageRef(pageRef) {
        if (pageRef && pageRef.state.caseId) {
            this.recordId = pageRef.state.caseId;
        }
    }
    ratingOptions = [
        { label: '1 - Poor', value: '1' },
        { label: '2 - Fair', value: '2' },
        { label: '3 - Good', value: '3' },
        { label: '4 - Very Good', value: '4' },
        { label: '5 - Excellent', value: '5' }
    ];

    handleChange(event) {
        const { name, value } = event.target;
        this[name] = value;
    }

    async handleSubmit() {
        this.isSubmitting = true;
        this.successMessage = '';
        this.errorMessage = '';

        try {
            await submitFeedback({
                caseId: this.recordId,
                overallRating: Number(this.overallRating),
                comments: this.comments
            });
            this.successMessage = 'Thank you! Your feedback has been submitted.';
            this.overallRating = '';
            this.comments = '';
        } catch (error) {
            this.errorMessage = error.body ? error.body.message : error.message;
        } finally {
            this.isSubmitting = false;
        }
    }
}