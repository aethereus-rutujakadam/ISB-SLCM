import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getProgramEnrollmentByPGID from '@salesforce/apex/DCRecordCreateController.getProgramEnrollmentByPGID';
import getTermOptionsByProgramAndCohort from '@salesforce/apex/DCRecordCreateController.getTermOptionsByProgramAndCohort';
import getStudentByPGID from '@salesforce/apex/DCRecordCreateController.getStudentByPGID';
import getStaffByEmail from '@salesforce/apex/DCRecordCreateController.getStaffByEmail';
import createDCRecord from '@salesforce/apex/DCRecordCreateController.createDCRecord';

export default class DcRecordCreate extends NavigationMixin(LightningElement) {
    @track form = {
        studentPgid: '',
        studentName: '',
        studentEmail: '',
        studentMobile: '',
        programEnrollmentId: null,
        programEnrollmentName: '',
        programId: null,
        programName: '',
        cohortId: null,
        cohortName: '',
        termId: null,
        status: 'Pending',
        complaintDescription: '',
        complaintReceived: null,
        complaintRaisedBy: '',
        complaintReceivedByContactInfo: '',
        // Student Complaint
        complaintStudentId: '',
        complaintStudentContactId: null,
        complaintStudentName: '',
        complaintStudentMobile: '',
        // Staff Complaint
        complaintStaffEmail: '',
        complaintStaffContactId: null,
        complaintStaffName: '',
        complaintStaffMobile: '',
        // Show Cause
        showcauseNoticeSent: null,
        studentResponseToShowcause: '',
        // Committee Info
        committeeChairEmail: '',
        committeeChairName: '',
        meetingName: '',
        meetingDate: null,
        meetingParticipants: '',
        studentsInvolved: '',
        meetingDuration: null,
        // Decision
        numberOfSittings: null,
        finalHearingDate: null,
        finalOutcome: '',
        actionSharedDate: null,
        actionTakenDescription: '',
        // Appeal
        deanAppealDate: null,
        deanAppealGrounds: '',
        deanDecision: '',
        finalPenalty: ''
    };

    @track testimonyRows = [];
    @track termOptions = [];
    @track isLoading = false;
    @track saving = false;

    testimonyKeyCounter = 0;

    get statusOptions() {
        return [
            { label: 'Pending', value: 'Pending' },
            { label: 'Closed', value: 'Closed' }
        ];
    }

    get complaintRaisedByOptions() {
        return [
            { label: '--None--', value: '' },
            { label: 'Student', value: 'Student' },
            { label: 'Staff', value: 'Staff' }
        ];
    }

    get testimonyTypeOptions() {
        return [
            { label: '--None--', value: '' },
            { label: 'Complainant', value: 'Complainant' },
            { label: 'Respondent', value: 'Respondent' }
        ];
    }

    get showStudentComplaintSection() {
        return this.form.complaintRaisedBy === 'Student';
    }

    get showStaffComplaintSection() {
        return this.form.complaintRaisedBy === 'Staff';
    }

    connectedCallback() {
        this.addTestimony();
        this.termOptions = [{ label: '--None--', value: '' }];
    }

    async loadTermOptions(programId, cohortId) {
        if (!programId || !cohortId) {
            this.termOptions = [{ label: '--None--', value: '' }];
            this.form.termId = null;
            return;
        }
        try {
            const terms = await getTermOptionsByProgramAndCohort({ programId, cohortId });
            this.termOptions = [
                { label: '--None--', value: '' },
                ...terms.map(t => ({ label: t.name, value: t.id }))
            ];
            this.form.termId = null;
        } catch (error) {
            console.error('Error loading term options:', error);
            this.termOptions = [{ label: '--None--', value: '' }];
        }
    }

    handleFieldChange(event) {
        const field = event.target.dataset.field;
        this.form[field] = event.target.value;
    }

    handleComplaintRaisedByChange(event) {
        const value = event.target.value;
        this.form.complaintRaisedBy = value;

        // Clear the opposite section's fields
        if (value === 'Student') {
            this.form.complaintStaffEmail = '';
            this.form.complaintStaffContactId = null;
            this.form.complaintStaffName = '';
            this.form.complaintStaffMobile = '';
        } else if (value === 'Staff') {
            this.form.complaintStudentId = '';
            this.form.complaintStudentContactId = null;
            this.form.complaintStudentName = '';
            this.form.complaintStudentMobile = '';
        }
    }

    async handlePgidBlur(event) {
        const pgid = event.target.value?.trim();
        if (!pgid) {
            this.clearStudentFields();
            return;
        }

        this.isLoading = true;
        try {
            const result = await getProgramEnrollmentByPGID({ pgid });
            if (result) {
                this.form.studentPgid = pgid;
                this.form.programEnrollmentId = result.enrollmentId;
                this.form.programEnrollmentName = result.enrollmentName;
                this.form.studentContactId = result.contactId;
                this.form.studentName = result.studentName || '';
                this.form.studentEmail = result.studentEmail || '';
                this.form.studentMobile = result.studentMobile || '';
                this.form.programId = result.programId;
                this.form.programName = result.programName || '';
                // Auto-populate cohort from ProgramEnrollment.Academic_Term__c
                this.form.cohortId = result.cohortId || null;
                this.form.cohortName = result.cohortName || '';
                // Load filtered term options for this program + cohort
                await this.loadTermOptions(result.programId, result.cohortId);
            } else {
                this.showToast('Warning', 'No active enrollment found for this PG ID', 'warning');
                this.clearStudentFields();
            }
        } catch (error) {
            this.showToast('Error', error.body?.message || 'Error looking up student', 'error');
            this.clearStudentFields();
        } finally {
            this.isLoading = false;
        }
    }

    clearStudentFields() {
        this.form.programEnrollmentId = null;
        this.form.programEnrollmentName = '';
        this.form.studentContactId = null;
        this.form.studentName = '';
        this.form.studentEmail = '';
        this.form.studentMobile = '';
        this.form.programId = null;
        this.form.programName = '';
        this.form.cohortId = null;
        this.form.cohortName = '';
        this.form.termId = null;
        this.termOptions = [{ label: '--None--', value: '' }];
    }

    async handleComplaintStudentIdBlur(event) {
        const studentId = event.target.value?.trim();
        if (!studentId) {
            this.form.complaintStudentContactId = null;
            this.form.complaintStudentName = '';
            this.form.complaintStudentMobile = '';
            return;
        }

        this.isLoading = true;
        try {
            const result = await getStudentByPGID({ pgid: studentId });
            if (result) {
                this.form.complaintStudentContactId = result.contactId;
                this.form.complaintStudentName = result.name || '';
                this.form.complaintStudentMobile = result.mobile || '';
            } else {
                this.showToast('Warning', 'No student found with this ID', 'warning');
                this.form.complaintStudentContactId = null;
                this.form.complaintStudentName = '';
                this.form.complaintStudentMobile = '';
            }
        } catch (error) {
            this.showToast('Error', error.body?.message || 'Error looking up student', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleComplaintStaffEmailBlur(event) {
        const email = event.target.value?.trim();
        if (!email) {
            this.form.complaintStaffContactId = null;
            this.form.complaintStaffName = '';
            this.form.complaintStaffMobile = '';
            return;
        }

        this.isLoading = true;
        try {
            const result = await getStaffByEmail({ email });
            if (result) {
                this.form.complaintStaffContactId = result.contactId;
                this.form.complaintStaffName = result.name || '';
                this.form.complaintStaffMobile = result.mobile || '';
            } else {
                this.showToast('Warning', 'No staff found with this email', 'warning');
                this.form.complaintStaffContactId = null;
                this.form.complaintStaffName = '';
                this.form.complaintStaffMobile = '';
            }
        } catch (error) {
            this.showToast('Error', error.body?.message || 'Error looking up staff', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // Testimony management
    addTestimony() {
        this.testimonyKeyCounter++;
        const newTestimony = {
            key: this.testimonyKeyCounter,
            type: '',
            mom: '',
            recordingUrl: '',
            get title() {
                return `Testimony ${this.key}`;
            },
            get disableRemove() {
                return false;
            }
        };
        this.testimonyRows = [...this.testimonyRows, newTestimony];
    }

    removeTestimony(event) {
        const key = parseInt(event.target.dataset.key, 10);
        this.testimonyRows = this.testimonyRows.filter(t => t.key !== key);
    }

    handleTestimonyChange(event) {
        const key = parseInt(event.target.dataset.key, 10);
        const field = event.target.dataset.field;
        const value = event.target.value;

        this.testimonyRows = this.testimonyRows.map(t => {
            if (t.key === key) {
                return { ...t, [field]: value };
            }
            return t;
        });
    }

    isTenDigitMobile(value) {
        return /^\d{10}$/.test((value || '').trim());
    }

    async handleSave() {
        // Validate required fields
        if (!this.form.studentPgid) {
            this.showToast('Error', 'Student PG ID is required', 'error');
            return;
        }
        if (!this.form.status) {
            this.showToast('Error', 'Status is required', 'error');
            return;
        }
        const staffMobile = (this.form.complaintStaffMobile || '').trim();
        if (this.form.complaintRaisedBy === 'Staff' && staffMobile && !this.isTenDigitMobile(staffMobile)) {
            this.showToast('Error', 'Mobile Number (Staff) must be exactly 10 digits when Complaint Raised By is Staff.', 'error');
            return;
        }

        this.saving = true;
        this.isLoading = true;

        try {
            // Build testimonies array
            const testimonies = this.testimonyRows
                .filter(t => t.type)
                .map(t => ({
                    type: t.type,
                    mom: t.mom,
                    recordingUrl: t.recordingUrl
                }));

            const data = {
                ...this.form,
                testimonies: testimonies,
                testimoniesJson: JSON.stringify(testimonies)
            };

            const recordId = await createDCRecord({ data });

            this.showToast('Success', 'Disciplinary Committee record created successfully', 'success');

            // Navigate to the new record
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: recordId,
                    objectApiName: 'Disciplinary_Committee__c',
                    actionName: 'view'
                }
            });
        } catch (error) {
            console.error('Save error:', error);
            this.showToast('Error', error.body?.message || 'Error creating record', 'error');
        } finally {
            this.saving = false;
            this.isLoading = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}