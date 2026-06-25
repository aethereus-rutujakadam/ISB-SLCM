import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPrograms from '@salesforce/apex/ProgramEnrollmentManagerController.getPrograms';
import getAcademicYears from '@salesforce/apex/ProgramEnrollmentManagerController.getAcademicYears';
import getProgramEnrollments from '@salesforce/apex/ProgramEnrollmentManagerController.getProgramEnrollments';
import getEnrollmentSessions from '@salesforce/apex/ProgramEnrollmentManagerController.getEnrollmentSessions';
import getEnrollmentInstallments from '@salesforce/apex/ProgramEnrollmentManagerController.getEnrollmentInstallments';

const DELAY = 300;

export default class ProgramEnrollmentManager extends LightningElement {
    // State
    @track currentView = 'program-list'; // program-list, program-detail
    @track isLoading = false;
    @track isModalOpen = false;

    // Search & Filters
    @track searchTerm = '';
    @track selectedAcademicYear = '';
    
    // Data Lists
    @track programs = [];
    @track academicYears = [];
    @track enrollments = [];
    @track enrollmentSessions = [];
    @track enrollmentInstallments = [];

    // Selected Items
    @track selectedProgram = {};
    @track selectedEnrollment = {};

    // Wired Data
    @wire(getAcademicYears)
    wiredAcademicYears({ error, data }) {
        if (data) {
            this.academicYears = data.map(year => ({ label: year.Name, value: year.Id }));
        } else if (error) {
            this.showToast('Error', 'Failed to load Academic Years', 'error');
        }
    }

    // Program Search Logic
    connectedCallback() {
        this.fetchPrograms();
    }

    handleSearch(event) {
        window.clearTimeout(this.delayTimeout);
        const searchKey = event.target.value;
        this.delayTimeout = setTimeout(() => {
            this.searchTerm = searchKey;
            this.fetchPrograms();
        }, DELAY);
    }

    fetchPrograms() {
        this.isLoading = true;
        getPrograms({ searchKey: this.searchTerm })
            .then(result => {
                this.programs = result;
                this.isLoading = false;
            })
            .catch(error => {
                this.isLoading = false;
                this.showToast('Error', 'Failed to fetch programs', 'error');
            });
    }

    // Navigation
    handleProgramSelect(event) {
        const programId = event.currentTarget.dataset.id;
        this.selectedProgram = this.programs.find(p => p.Id === programId);
        this.currentView = 'program-detail';
        this.fetchEnrollments();
    }

    handleBackToPrograms() {
        this.currentView = 'program-list';
        this.selectedProgram = {};
        this.enrollments = [];
        this.selectedAcademicYear = '';
    }

    // Enrollment Logic
    handleYearChange(event) {
        this.selectedAcademicYear = event.detail.value;
        this.fetchEnrollments();
    }

    fetchEnrollments() {
        if (!this.selectedProgram.Id) return;
        
        this.isLoading = true;
        getProgramEnrollments({ 
            programId: this.selectedProgram.Id, 
            academicYearId: this.selectedAcademicYear || null 
        })
        .then(result => {
            this.enrollments = result.map(enroll => {
                const installments = enroll.Installments || [];
                const getInstDetails = (targetNum) => {
                    // Try to find by explicit Number
                    let inst = installments.find(i => i.Number == targetNum);
                    
                    // Fallback to index if not found (assuming ordered list)
                    if (!inst && installments.length >= targetNum) {
                        inst = installments[targetNum - 1];
                    }
                    
                    if (!inst) return 'N/A';
                    
                    const dueDate = inst.DueDate ? new Date(inst.DueDate).toLocaleDateString() : 'N/A';
                    const extDate = inst.ExtendedDueDate ? new Date(inst.ExtendedDueDate).toLocaleDateString() : 'N/A';
                    const status = inst.Status || 'N/A';
                    return `Due: ${dueDate}, Ext: ${extDate}, Status: ${status}`;
                };

                return { 
                    ...enroll, 
                    inst1: getInstDetails(1),
                    inst2: getInstDetails(2),
                    inst3: getInstDetails(3),
                    inst4: getInstDetails(4)
                };
            });
            this.isLoading = false;
        })
        .catch(error => {
            this.isLoading = false;
            let message = 'Failed to fetch enrollments';
            if (error && error.body && error.body.message) {
                message = error.body.message;
            }
            this.showToast('Error', message, 'error');
            console.error('Error fetching enrollments:', error);
        });
    }

    // Modal & Drill Down
    handleEnrollmentClick(event) {
        const enrollmentId = event.currentTarget.dataset.id;
        this.selectedEnrollment = this.enrollments.find(e => e.Id === enrollmentId);
        this.isModalOpen = true;
        this.fetchDrillDownData(enrollmentId);
    }

    closeModal() {
        this.isModalOpen = false;
        this.selectedEnrollment = {};
        this.enrollmentSessions = [];
        this.enrollmentInstallments = [];
    }

    fetchDrillDownData(enrollmentId) {
        this.isLoading = true;
        
        Promise.all([
            getEnrollmentSessions({ enrollmentId }),
            getEnrollmentInstallments({ enrollmentId })
        ])
        .then(([sessions, installments]) => {
            this.enrollmentSessions = sessions;
            this.enrollmentInstallments = installments;
            this.isLoading = false;
        })
        .catch(error => {
            this.isLoading = false;
            this.showToast('Error', 'Failed to load enrollment details', 'error');
        });
    }

    // Utilities
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    get isProgramList() {
        return this.currentView === 'program-list';
    }

    get isProgramDetail() {
        return this.currentView === 'program-detail';
    }
}