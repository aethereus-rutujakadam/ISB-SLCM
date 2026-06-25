import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import getCourseOfferingDetails from '@salesforce/apex/BulkAssignCoursesController.getCourseOfferingDetails';
import searchStudents from '@salesforce/apex/BulkAssignCoursesController.searchStudents';
import createParticipants from '@salesforce/apex/BulkAssignCoursesController.createParticipants';
import getProgramObjectApiName from '@salesforce/apex/BulkAssignCoursesController.getProgramObjectApiName';
import getTermObjectApiName from '@salesforce/apex/BulkAssignCoursesController.getTermObjectApiName';
import getCourseOfferingsByLearningCourse from '@salesforce/apex/BulkAssignCoursesController.getCourseOfferingsByLearningCourse';
import getAcademicTermsByProgram from '@salesforce/apex/BulkAssignCoursesController.getAcademicTermsByProgram';
import getAcademicSessionsByTerm from '@salesforce/apex/BulkAssignCoursesController.getAcademicSessionsByTerm';
import getLearningCoursesBySession from '@salesforce/apex/BulkAssignCoursesController.getLearningCoursesBySession';
import getCourseTypePicklistValues from '@salesforce/apex/BulkAssignCoursesController.getCourseTypePicklistValues';

export default class BulkAssignCourses extends LightningElement {
    @api recordId; // From Record Page context
    
    @track programId;
    @track programName;
    @track programObjectApiName = 'Program'; // Dynamic API Name
    @track termObjectApiName = 'AcademicTerm'; // Dynamic API Name
    @track academicTermId;     // Academic Cohort (Term)
    @track academicTermName;   
    @track academicSessionId;  // Academic Session
    @track academicSessionName;
    @track academicYearName;
    @track targetCourseId;
    @track targetCourseName = '';
    @track learningCourseId; 
    @track courseOfferingOptions = [];
    @track academicTermOptions = [];
    @track academicSessionOptions = [];
    @track learningCourseOptions = [];
    @track students = [];
    @track selectedRowKeys = []; // For Datatable UI (ProgramEnrollment Ids)
    selectedContactIds = []; // For Logic (Contact Ids)
    @track globalCourseType; // Global Course Type selection
    @track courseTypeOptions = []; // Course Type picklist values
    @track isLoading = false;
    @track isSearchPerformed = false;

    connectedCallback() {
        this.fetchMetadata();
        if (this.recordId) {
            this.targetCourseId = this.recordId;
            this.loadCourseDetails();
        }
    }

    fetchMetadata() {
        getProgramObjectApiName()
            .then(result => {
                this.programObjectApiName = result;
            })
            .catch(error => console.error('Error fetching program metadata', error));

        getTermObjectApiName()
            .then(result => {
                this.termObjectApiName = result;
            })
            .catch(error => console.error('Error fetching term metadata', error));

        // Fetch Course Type picklist values
        getCourseTypePicklistValues()
            .then(result => {
                this.courseTypeOptions = result;
            })
            .catch(error => console.error('Error fetching course type picklist values', error));
    }

    loadCourseDetails() {
        this.isLoading = true;
        getCourseOfferingDetails({ courseOfferingId: this.recordId })
            .then(result => {
                this.programId = result.programId;
                this.programName = result.programName;
                this.academicTermId = result.academicTermId;
                this.academicTermName = result.academicTermName;
                this.academicYearName = result.academicYearName;
                this.targetCourseName = result.courseName;
                
                if (this.programId) {
                    this.handleSearch(); 
                }
            })
            .catch(error => {
                console.error('Error loading details', error);
                this.showToast('Error', 'Failed to load course details', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // Filter Change Handlers
    handleProgramChange(event) {
        this.programId = event.detail.recordId || event.detail.value;
        this.academicTermId = null;
        this.academicSessionId = null;
        this.learningCourseId = null;
        this.targetCourseId = null;
        this.academicTermOptions = [];
        this.academicSessionOptions = [];
        this.learningCourseOptions = [];
        this.courseOfferingOptions = [];
        this.students = [];
        this.isSearchPerformed = false;
        
        if (this.programId) {
            this.loadAcademicTerms();
        }
    }

    handleTermChange(event) {
        this.academicTermId = event.detail.value;
        this.academicSessionId = null;
        this.learningCourseId = null;
        this.targetCourseId = null;
        this.academicSessionOptions = [];
        this.learningCourseOptions = [];
        this.courseOfferingOptions = [];
        this.students = [];
        this.isSearchPerformed = false;
        
        if (this.academicTermId) {
            this.loadAcademicSessions();
        }
    }

    handleSessionChange(event) {
        this.academicSessionId = event.detail.value;
        this.learningCourseId = null;
        this.targetCourseId = null;
        this.learningCourseOptions = [];
        this.courseOfferingOptions = [];
        this.students = [];
        this.isSearchPerformed = false;
        
        if (this.academicSessionId) {
            this.loadLearningCourses();
        }
    }

    handleLearningCourseChange(event) {
        this.learningCourseId = event.detail.value;
        this.targetCourseId = null;
        this.courseOfferingOptions = [];
        
        if (this.learningCourseId && this.academicSessionId) {
            this.isLoading = true;
            getCourseOfferingsByLearningCourse({ 
                learningCourseId: this.learningCourseId,
                academicSessionId: this.academicSessionId 
            })
                .then(result => {
                    this.courseOfferingOptions = result;
                    if (!result || result.length === 0) {
                        this.showToast('Warning', 'No Course Offerings found for this Learning Course in the selected Academic Session', 'warning');
                    }
                })
                .catch(error => {
                    console.error('Error loading course offerings', error);
                    this.showToast('Error', 'Failed to load course offerings', 'error');
                })
                .finally(() => {
                    this.isLoading = false;
                });
        }
    }

    loadAcademicTerms() {
        this.isLoading = true;
        getAcademicTermsByProgram({ programId: this.programId })
            .then(result => {
                this.academicTermOptions = result;
            })
            .catch(error => {
                console.error('Error loading academic terms', error);
                this.showToast('Error', 'Failed to load academic terms', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    loadAcademicSessions() {
        this.isLoading = true;
        getAcademicSessionsByTerm({ termId: this.academicTermId })
            .then(result => {
                this.academicSessionOptions = result;
            })
            .catch(error => {
                console.error('Error loading academic sessions', error);
                this.showToast('Error', 'Failed to load academic sessions', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    loadLearningCourses() {
        this.isLoading = true;
        getLearningCoursesBySession({ academicSessionId: this.academicSessionId })
            .then(result => {
                this.learningCourseOptions = result;
                if (!result || result.length === 0) {
                    this.showToast('Info', 'No Learning Courses found for the selected Academic Session', 'info');
                }
            })
            .catch(error => {
                console.error('Error loading learning courses', error);
                this.showToast('Error', 'Failed to load learning courses', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleCourseChange(event) {
        this.targetCourseId = event.detail.value; // Combobox value
    }

    handleSearch() {
        if (!this.programId) {
            this.showToast('Warning', 'Please select a Program', 'warning');
            return;
        }

        this.isLoading = true;
        this.isSearchPerformed = true;
        
        searchStudents({ 
            programId: this.programId, 
            termId: this.academicTermId,
            academicSessionId: this.academicSessionId 
        })
            .then(result => {
                this.students = result.map(rec => {
                    const enrolledTerms = rec.Enrollment_Sessions__r 
                        ? rec.Enrollment_Sessions__r.map(es => es.Academic_Session__r ? es.Academic_Session__r.Name : '').filter(Boolean).join(', ')
                        : '';

                    return {
                        ...rec,
                        StudentName: rec.Contact ? rec.Contact.Name : '',
                        EnrolledTerm: enrolledTerms,
                        isSelected: this.selectedContactIds.includes(rec.ContactId)
                    };
                });
            })
            .catch(error => {
                console.error('Search error', error);
                this.showToast('Error', 'Failed to search students: ' + (error.body?.message || error.message), 'error');
                this.students = [];
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleGlobalCourseTypeChange(event) {
        this.globalCourseType = event.detail.value;
    }

    handleSelectAll(event) {
        const isChecked = event.target.checked;
        this.students = this.students.map(student => ({
            ...student,
            isSelected: isChecked
        }));
        
        if (isChecked) {
            this.selectedRowKeys = this.students.map(s => s.Id);
            this.selectedContactIds = this.students.map(s => s.ContactId);
        } else {
            this.selectedRowKeys = [];
            this.selectedContactIds = [];
        }
    }

    handleRowCheckboxChange(event) {
        const isChecked = event.target.checked;
        const rowId = event.currentTarget.dataset.id;
        const contactId = event.currentTarget.dataset.contactId;
        
        this.students = this.students.map(student => {
            if (student.Id === rowId) {
                return { ...student, isSelected: isChecked };
            }
            return student;
        });
        
        if (isChecked) {
            if (!this.selectedRowKeys.includes(rowId)) {
                this.selectedRowKeys.push(rowId);
            }
            if (!this.selectedContactIds.includes(contactId)) {
                this.selectedContactIds.push(contactId);
            }
        } else {
            this.selectedRowKeys = this.selectedRowKeys.filter(id => id !== rowId);
            this.selectedContactIds = this.selectedContactIds.filter(id => id !== contactId);
        }
    }

    handleAssign() {
        if (!this.targetCourseId) {
            this.showToast('Error', 'Please select a target Course Offering', 'error');
            return;
        }
        if (this.selectedContactIds.length === 0) {
            this.showToast('Warning', 'Please select at least one student', 'warning');
            return;
        }

        if (!this.globalCourseType) {
            this.showToast('Error', 'Please select a Course Type', 'error');
            return;
        }

        this.isLoading = true;
        createParticipants({ 
            contactIds: this.selectedContactIds, 
            courseOfferingId: this.targetCourseId,
            courseType: this.globalCourseType
        })
            .then((result) => {
                this.showToast('Success', 'Successfully assigned ' + result + ' students.', 'success');
                // Clear selection
                this.selectedRowKeys = [];
                this.selectedContactIds = [];
                this.globalCourseType = null;
                // Reset isSelected on students to uncheck checkboxes in the UI
                this.students = this.students.map(student => ({
                    ...student,
                    isSelected: false
                }));
                
                if (this.isRecordPage) {
                     this.closeAction();
                } else {
                     // For Tab, keep list but selection is now cleared
                }
            })
            .catch(error => {
                console.error('Assignment error', error);
                this.showToast('Error', 'Failed to assign students: ' + (error.body?.message || error.message), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleCancel() {
        this.closeAction();
    }

    closeAction() {
        if (this.recordId) {
            this.dispatchEvent(new CloseActionScreenEvent());
        } else {
            // Reset form if in Tab mode
            this.students = [];
            this.selectedRows = [];
            this.isSearchPerformed = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    get isRecordPage() {
        return !!this.recordId;
    }
    
    get allSelected() {
        return this.students.length > 0 && this.students.every(s => s.isSelected);
    }

    get hasResults() {
        return this.students && this.students.length > 0;
    }
}