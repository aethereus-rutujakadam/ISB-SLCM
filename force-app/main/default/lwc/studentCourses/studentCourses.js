import { LightningElement, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getStudentCourses from '@salesforce/apex/StudentProgramCoursesController.getStudentCourses';

const COLUMNS = [
    { label: 'Course Name', fieldName: 'learningCourseName', type: 'text', wrapText: true },
    { label: 'Course Offering', fieldName: 'courseOfferingName', type: 'text', wrapText: true },
    { label: 'Term / Year', fieldName: 'termInfo', type: 'text' },
    { 
        label: 'Start Date', 
        fieldName: 'startDate', 
        type: 'text'
    },
    { 
        label: 'End Date', 
        fieldName: 'endDate', 
        type: 'text'
    },
    { label: 'Status', fieldName: 'status', type: 'text' }
];

export default class StudentCourses extends LightningElement {
    @track isLoading = true;
    @track error;
    @track courses = [];
    @track totalCourses = 0;
    
    columns = COLUMNS;

    // Wire to get student courses
    @wire(getStudentCourses)
    wiredCourses({ error, data }) {
        this.isLoading = false;
        
        if (data) {
            console.log('=== Student Courses Data (Table) ===');
            console.log('Data:', JSON.stringify(data, null, 2));
            
            this.courses = (data || []).map(course => ({
                ...course,
                termInfo: this.formatTermInfo(course.termName, course.yearName)
            }));
            
            this.totalCourses = this.courses.length;
            this.error = undefined;
        } else if (error) {
            console.error('Error fetching courses:', error);
            this.error = this.extractErrorMessage(error);
            this.showToast('Error', this.error, 'error');
        }
    }

    // Computed properties
    get hasData() {
        return this.courses && this.courses.length > 0;
    }
    
    // Helper to extract error message
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

    formatTermInfo(term, year) {
        if (term && year) return `${term} | ${year}`;
        if (term) return term;
        if (year) return year;
        return '';
    }
}