import { LightningElement, track, wire } from 'lwc';
import getProgramOptions from '@salesforce/apex/CourseStudentController.getProgramOptions';
import getSessionOptions from '@salesforce/apex/CourseStudentController.getSessionOptions';
import getCourseOptions from '@salesforce/apex/CourseStudentController.getCourseOptions';
import getStudents from '@salesforce/apex/CourseStudentController.getStudents';
import sendNotificationsToStudents from '@salesforce/apex/CourseStudentController.sendNotificationsToStudents';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const COLUMNS = [
    { label: 'Student Name', fieldName: 'studentName', type: 'text', sortable: true },
    { label: 'Email', fieldName: 'email', type: 'email', sortable: true },
    { label: 'Status', fieldName: 'status', type: 'text', sortable: true },
    { label: 'Program', fieldName: 'programName', type: 'text', sortable: true },
    { label: 'Session', fieldName: 'sessionName', type: 'text', sortable: true },
    { label: 'Course', fieldName: 'courseName', type: 'text', sortable: true }
];

export default class EligibleReturnReplaceStudentList extends LightningElement {
    @track programOptions = [];
    @track sessionOptions = [];
    @track courseOptions = [];
    @track students = [];
    @track selectedRows = [];
    @track columns = COLUMNS;
    
    selectedProgram = '';
    selectedSession = '';
    selectedCourse = '';
    
    isLoading = false;
    defaultSortDirection = 'asc';
    sortDirection = 'asc';
    sortedBy = '';
    
    // Add a flag to track if we should auto-search
    @track shouldAutoSearch = true;
    
    @wire(getProgramOptions)
    wiredPrograms({ error, data }) {
        if (data) {
            this.programOptions = [];
            data.forEach(item => {
                const programId = item['Program__c'];
                const programName = item['label'];
                
                if (programId && programName) {
                    this.programOptions.push({
                        label: programName,
                        value: programId
                    });
                }
            });
        } else if (error) {
            console.error('Error loading programs:', error);
            this.showToast('Error', 'Failed to load programs', 'error');
        }
    }
    
    async handleProgramChange(event) {
        this.selectedProgram = event.detail.value;
        this.selectedSession = '';
        this.selectedCourse = '';
        this.students = [];
        this.selectedRows = [];
        this.sessionOptions = [];
        this.courseOptions = [];
        
        if (this.selectedProgram) {
            await this.loadSessionOptions();
            // Auto-search for all students in this program
            await this.searchStudents();
        }
    }
    
    async loadSessionOptions() {
        try {
            this.isLoading = true;
            const sessions = await getSessionOptions({ programId: this.selectedProgram });
            
            this.sessionOptions = [];
            sessions.forEach(item => {
                const sessionId = item['AcademicSessionId'];
                const sessionName = item['label'];
                
                if (sessionId && sessionName) {
                    this.sessionOptions.push({
                        label: sessionName,
                        value: sessionId
                    });
                }
            });
            
            this.isLoading = false;
            
            if (this.sessionOptions.length === 0) {
                this.showToast('Info', 'No sessions found for selected program', 'info');
            }
        } catch (error) {
            console.error('Error loading sessions:', error);
            this.showToast('Error', 'Failed to load sessions', 'error');
            this.isLoading = false;
        }
    }
    
    async handleSessionChange(event) {
        this.selectedSession = event.detail.value;
        this.selectedCourse = '';
        this.students = [];
        this.selectedRows = [];
        this.courseOptions = [];
        
        if (this.selectedSession) {
            await this.loadCourseOptions();
            // Auto-search for all students in this program & session
            await this.searchStudents();
        } else {
            // If session is cleared, search for all students in the program
            await this.searchStudents();
        }
    }
    
    async loadCourseOptions() {
        try {
            this.isLoading = true;
            const courses = await getCourseOptions({
                programId: this.selectedProgram,
                sessionId: this.selectedSession
            });
            
            this.courseOptions = [];
            courses.forEach(item => {
                const courseId = item['LearningCourseId'];
                const courseName = item['label'];
                
                if (courseId && courseName) {
                    this.courseOptions.push({
                        label: courseName,
                        value: courseId
                    });
                }
            });
            
            this.isLoading = false;
            
            if (this.courseOptions.length === 0) {
                this.showToast('Info', 'No courses found for selected session', 'info');
            }
        } catch (error) {
            console.error('Error loading courses:', error);
            this.showToast('Error', 'Failed to load courses', 'error');
            this.isLoading = false;
        }
    }
    
    async handleCourseChange(event) {
        this.selectedCourse = event.detail.value;
        this.students = [];
        this.selectedRows = [];
        
        // Auto-search when course changes
        await this.searchStudents();
    }

    get hideCheckboxColumn() {
        return false;
    }
    
    async searchStudents() {
        // Only search if a program is selected
        if (!this.selectedProgram) {
            this.students = [];
            return;
        }
        
        // If auto-search is disabled, just return
        if (!this.shouldAutoSearch) {
            return;
        }
        
        this.isLoading = true;
        
        try {
            const result = await getStudents({
                programId: this.selectedProgram,
                sessionId: this.selectedSession || null,
                courseId: this.selectedCourse || null
            });
            
            this.students = result.map(student => ({
                ...student
            }));
            
            this.selectedRows = [];
            this.isLoading = false;
            
            if (this.students.length === 0) {
                this.showToast('Info', 'No students found for the selected filters', 'info');
            }
        } catch (error) {
            console.error('Error loading students:', error);
            this.showToast('Error', 'Failed to load students: ' + error.body?.message, 'error');
            this.isLoading = false;
        }
    }
    
    // You can keep the manual search button for users who prefer it
    async manualSearch() {
        this.shouldAutoSearch = true;
        await this.searchStudents();
    }
    
    handleRowSelection(event) {
        const selectedRows = event.detail.selectedRows || [];
        this.selectedRows = selectedRows;
    }

    get selectedStudentIds() {
        return this.selectedRows.map(row => row.studentId);
    }
    
    get selectedCount() {
        return this.selectedRows.length;
    }
    
    selectAll() {
        if (this.students.length === 0) return;
        
        const allIds = this.students.map(student => student.studentId);
        const datatable = this.template.querySelector('lightning-datatable');
        if (datatable) {
            datatable.selectedRows = allIds;
        }
        this.selectedRows = [...this.students];
    }
    
    deselectAll() {
        const datatable = this.template.querySelector('lightning-datatable');
        if (datatable) {
            datatable.selectedRows = [];
        }
        this.selectedRows = [];
    }
    
    async sendNotifications() {
        if (this.selectedCount === 0) {
            this.showToast('Error', 'Please select at least one student', 'error');
            return;
        }

        this.isLoading = true;

        try {
            await sendNotificationsToStudents({
                studentIds: this.selectedStudentIds,
                message: ''
            });

            this.showToast(
                'Success',
                `Notifications sent to ${this.selectedCount} student(s)`,
                'success'
            );
            
            this.deselectAll();
            
        } catch (error) {
            console.error('Error sending notifications:', error);
            this.showToast(
                'Error',
                'Failed to send notifications: ' + (error.body?.message || error.message),
                'error'
            );
        } finally {
            this.isLoading = false;
        }
    }
    
    clearFilters() {
        this.selectedProgram = '';
        this.selectedSession = '';
        this.selectedCourse = '';
        this.students = [];
        this.selectedRows = [];
        this.sessionOptions = [];
        this.courseOptions = [];
        this.shouldAutoSearch = true;
    }
    
    handleSort(event) {
        const { fieldName: sortedBy, sortDirection } = event.detail;
        const cloneData = [...this.students];
        
        cloneData.sort((a, b) => {
            let aValue = a[sortedBy] || '';
            let bValue = b[sortedBy] || '';
            
            if (sortDirection === 'asc') {
                return aValue > bValue ? 1 : -1;
            }
            return aValue < bValue ? 1 : -1;
        });
        
        this.students = cloneData;
        this.sortDirection = sortDirection;
        this.sortedBy = sortedBy;
    }
    
    get debugInfo() {
        console.log('Current state:', {
            selectedProgram: this.selectedProgram,
            selectedSession: this.selectedSession,
            selectedCourse: this.selectedCourse,
            selectedCount: this.selectedCount,
            students: this.students,
            selectedRows: this.selectedRows
        });
        return '';
    }
    
    get disableSession() {
        return !this.selectedProgram;
    }
    
    get disableCourse() {
        return !this.selectedSession;
    }
    
    // Update the disableSearch getter to always enable the button
    get disableSearch() {
        return false;
    }
    
    get disableSendButton() {
        return this.selectedCount === 0;
    }
    
    get hasStudents() {
        return this.students && this.students.length > 0;
    }
    
    get hasSelection() {
        return this.selectedCount > 0;
    }
    
    get showNoResults() {
        return !this.isLoading && !this.hasStudents && this.selectedProgram;
    }
    
    showToast(title, message, variant) {
        const toastEvent = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(toastEvent);
    }
}