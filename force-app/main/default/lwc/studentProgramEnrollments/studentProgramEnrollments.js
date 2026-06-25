import { LightningElement, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getProgramEnrollments from '@salesforce/apex/StudentProgramCoursesController.getProgramEnrollments';
import getEnrollmentSessions from '@salesforce/apex/StudentProgramCoursesController.getEnrollmentSessions';

export default class StudentProgramEnrollments extends LightningElement {
    @track isLoading = true;
    @track error;
    @track currentEnrollments = [];
    @track previousEnrollments = [];
    @track expandedSections = new Set();

    // Wire to get program enrollments
    @wire(getProgramEnrollments)
    wiredEnrollments({ error, data }) {
        this.isLoading = false;
        
        if (data) {
            console.log('=== Program Enrollments Data ===');
            console.log('Data:', JSON.stringify(data, null, 2));
            
            this.currentEnrollments = this.processEnrollments(data.currentEnrollments || []);
            this.previousEnrollments = this.processEnrollments(data.previousEnrollments || []);
            
            console.log('Current Enrollments:', this.currentEnrollments.length);
            console.log('Previous Enrollments:', this.previousEnrollments.length);
            
            this.error = undefined;
        } else if (error) {
            console.error('Error fetching enrollments:', error);
            this.error = this.extractErrorMessage(error);
            this.showToast('Error', this.error, 'error');
        }
    }

    // Process enrollments to add UI properties
    processEnrollments(enrollments) {
        return enrollments.map(enrollment => {
            const hasValue = (val) => val !== null && val !== undefined && val !== '';
            
            return {
                ...enrollment,
                sectionName: `enrollment-${enrollment.id}`,
                isExpanded: false,
                sessions: [],
                isLoadingSessions: false,
                startDateFormatted: this.formatDate(enrollment.startDate),
                endDateFormatted: this.formatDate(enrollment.endDate),
                
                // Visibility flags
                hasName: hasValue(enrollment.name),
                hasProgramName: hasValue(enrollment.programName),
                hasAcademicYear: hasValue(enrollment.academicYear),
                hasCgpa: hasValue(enrollment.cgpa),
                hasCoreCgpa: hasValue(enrollment.coreCgpa),
                hasElectiveCgpa: hasValue(enrollment.electiveCgpa),
                hasStatus: hasValue(enrollment.status),
                hasPreTermStatus: hasValue(enrollment.preTermStatus)
            };
        });
    }

    // Computed properties
    get hasCurrentEnrollments() {
        return this.currentEnrollments && this.currentEnrollments.length > 0;
    }

    get hasPreviousEnrollments() {
        return this.previousEnrollments && this.previousEnrollments.length > 0;
    }

    get hasAnyEnrollments() {
        return this.hasCurrentEnrollments || this.hasPreviousEnrollments;
    }

    // Handle accordion section toggle
    async handleSectionToggle(event) {
        const openSections = event.detail.openSections;
        console.log('Open sections:', JSON.stringify(openSections, null, 2));

        // When allow-multiple-sections-open is true, openSections is an array
        const sections = Array.isArray(openSections) ? openSections : [openSections];

        for (const sectionName of sections) {
            // Skip invalid sections
            if (!sectionName) continue;

            const enrollmentId = sectionName.replace('enrollment-', '');
            const enrollment = this.findEnrollment(enrollmentId);
            
            // Load sessions if not already loaded and not currently loading
            // We verify !enrollment.sessions.length to avoid reloading (unless it was empty result, which is a tradeoff)
            // Ideally we should have a 'sessionsLoaded' flag if we want to distinguish 'not loaded' from 'loaded but empty'
            if (enrollment && !enrollment.sessions.length && !enrollment.isLoadingSessions) {
                console.log('Triggering load for enrollment:', enrollmentId);
                // We call the load function. We can await it or let it run. 
                // Since this is an event handler, awaiting inside loop is fine or using Promise.all if we wanted to wait for all.
                // Here we simply trigger it.
                this.loadEnrollmentSessions(enrollment);
            }
        }
    }

    // Find enrollment by ID in both current and previous lists
    findEnrollment(enrollmentId) {
        let enrollment = this.currentEnrollments.find(e => e.id === enrollmentId);
        if (!enrollment) {
            enrollment = this.previousEnrollments.find(e => e.id === enrollmentId);
        }
        return enrollment;
    }

    // Load enrollment sessions for a specific enrollment
    async loadEnrollmentSessions(enrollment) {
        enrollment.isLoadingSessions = true;
        
        try {
            console.log('Loading sessions for enrollment:', enrollment.id);
            const sessions = await getEnrollmentSessions({ programEnrollmentId: enrollment.id });
            
            console.log('Sessions loaded:', sessions.length);
            enrollment.sessions = sessions;
            enrollment.isExpanded = true;
            
            // Force re-render
            this.currentEnrollments = [...this.currentEnrollments];
            this.previousEnrollments = [...this.previousEnrollments];
            
        } catch (error) {
            console.error('Error loading sessions:', error);
            this.showToast('Error', this.extractErrorMessage(error), 'error');
        } finally {
            enrollment.isLoadingSessions = false;
        }
    }

    // Format date for display
    formatDate(dateValue) {
        if (!dateValue) return 'N/A';
        const date = new Date(dateValue);
        return date.toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' });
    }

    // Format date for display
    formatDate(dateValue) {
        if (!dateValue) return '';
        try {
            const date = new Date(dateValue);
            return date.toLocaleDateString('en-US', { 
                year: 'numeric', 
                month: 'short', 
                day: 'numeric' 
            });
        } catch (e) {
            return '';
        }
    }

    // Utility methods
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