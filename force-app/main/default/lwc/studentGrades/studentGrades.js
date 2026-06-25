import { LightningElement, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getStudentGrades from '@salesforce/apex/StudentProgramCoursesController.getStudentGrades';

export default class StudentGrades extends LightningElement {
    @track isLoading = true;
    @track error;
    @track groupedGrades = [];

    // Wire to get student grades
    @wire(getStudentGrades)
    wiredGrades({ error, data }) {
        this.isLoading = false;
        if (data) {
            const processedGrades = (data || []).map(grade => {
                const letterGrade = grade.letterGrade || 'N/A';
                return {
                    ...grade,
                    creditsEarned: grade.creditsEarned != null ? grade.creditsEarned : 0,
                    creditsAttempted: grade.creditsAttempted != null ? grade.creditsAttempted : 0,
                    letterGrade: letterGrade,
                    badgeClass: `grade-badge-${letterGrade.replace(/[^a-zA-Z0-9]/g, '_')}`
                };
            });
            this.groupGradesByTerm(processedGrades);
            this.error = undefined;
        } else if (error) {
            this.error = this.extractErrorMessage(error);
            this.showToast('Error', this.error, 'error');
        }
    }

    groupGradesByTerm(grades) {
        const groups = {};
        grades.forEach(grade => {
            const term = grade.termName || 'Other';
            if (!groups[term]) {
                groups[term] = [];
            }
            groups[term].push(grade);
        });

        this.groupedGrades = Object.keys(groups).map(term => ({
            term: term,
            grades: groups[term]
        }));
    }

    get hasData() {
        return this.groupedGrades && this.groupedGrades.length > 0;
    }

    extractErrorMessage(error) {
        if (error.body) {
            if (error.body.message) return error.body.message;
            if (error.body.pageErrors && error.body.pageErrors.length > 0) {
                return error.body.pageErrors[0].message;
            }
        }
        return 'An unexpected error occurred';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant
            })
        );
    }
}