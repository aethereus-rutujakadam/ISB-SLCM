import { LightningElement, api, wire, track } from 'lwc';
import getStudentGrades from '@salesforce/apex/StudentCourseGradesController.getStudentGrades';
import { refreshApex } from '@salesforce/apex';

const COLUMNS = [
    { label: 'Academic Session (Term)', fieldName: 'academicSession', type: 'text' },
    { label: 'Learning Course', fieldName: 'courseName', type: 'text' },
    { label: 'Enrollment Status', fieldName: 'enrollmentStatus', type: 'text' },
    { label: 'Grade (Numeric)', fieldName: 'numericGrade', type: 'number', cellAttributes: { alignment: 'left' } },
    { label: 'Grade (Letter)', fieldName: 'letterGrade', type: 'text' },
];

export default class StudentCourseGrades extends LightningElement {
    @api recordId;
    @track grades;
    @track error;
    wiredGradesResult;
    columns = COLUMNS;

    @wire(getStudentGrades, { contactId: '$recordId' })
    wiredGrades(result) {
        this.wiredGradesResult = result;
        const { error, data } = result;
        if (data) {
            this.grades = data;
            this.error = undefined;
        } else if (error) {
            this.error = error.body?.message || 'Unknown error';
            this.grades = undefined;
        }
    }

    handleRefresh() {
        return refreshApex(this.wiredGradesResult);
    }

    get cardTitle() {
        return `Course Grades (${this.grades ? this.grades.length : 0})`;
    }

    get hasGrades() {
        return this.grades && this.grades.length > 0;
    }
}