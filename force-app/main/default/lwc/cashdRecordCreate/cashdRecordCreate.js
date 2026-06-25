import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import CASHD_COMMITTEE_OBJECT from '@salesforce/schema/CASHD_Committee__c';
import CASE_STATUS_FIELD from '@salesforce/schema/CASHD_Committee__c.Case_Status__c';
import DEAN_APPEAL_GROUNDS_FIELD from '@salesforce/schema/CASHD_Committee__c.Dean_Appeal_Grounds__c';
import DEAN_DECISION_FIELD from '@salesforce/schema/CASHD_Committee__c.Dean_Decision__c';
import FINAL_OUTCOME_FIELD from '@salesforce/schema/CASHD_Committee__c.FinalOutcome__c';

import getProgramEnrollmentByPGID from '@salesforce/apex/CASHDRecordCreateController.getProgramEnrollmentByPGID';
import getContactByEmail from '@salesforce/apex/CASHDRecordCreateController.getContactByEmail';
import getContactByStudentId from '@salesforce/apex/CASHDRecordCreateController.getContactByStudentId';
import searchCourseOfferings from '@salesforce/apex/CASHDRecordCreateController.searchCourseOfferings';
import createCASHDRecord from '@salesforce/apex/CASHDRecordCreateController.createCASHDRecord';

const PARTY_TYPES = ['Student', 'Staff', 'Alumni', 'Others'];
const PARTY_ROLES = ['Complainant', 'Respondent'];
const STUDENT_TYPE = 'Student';

export default class CashdRecordCreate extends NavigationMixin(LightningElement) {
    @track form = {
        subject: '',
        dateOfComplaintReceipt: null,
        caseStatus: '',
        courseOfferingId: '',
        caseAttachmentsUrl: '',
        studentPgid: '',
        studentProgramEnrollmentId: null,
        studentContactId: null,
        studentName: '',
        studentEmail: '',
        studentMobile: '',
        programEnrollmentId: null,
        programEnrollmentName: '',
        programId: null,
        programName: '',
        programCode: '',
        academicYearId: null,
        academicYear: '',
        currentReportingLocationId: null,
        currentReportingLocationName: '',

        committeeMember1Name: '',
        committeeMember2Name: '',
        committeeMember3Name: '',
        committeeMember4Name: '',
        committeeMember5Name: '',
        otherCommitteeMembersName: '',
        externalConsultantEmail: '',

        studentStaffType: STUDENT_TYPE,
        staffEmail: '',
        studentId: '',
        studentStaffContactId: null,
        studentStaffName: '',
        dateOfThe1stMeeting: null,
        firstMeetingDateWithComplainant: null,
        firstMeetingWithComplainant: '',
        firstMeetingDateWithRespondent: null,
        firstMeetingWithRespondent: '',
        secondMeetingDate: null,
        natureOfActivity: '',
        leadConvenor: '',
        metWith: '',
        membersAttended: '',
        namesOfCommitteeMembersInvolved: '',
        meetingRecordingUrl: '',
        numberOfMeetingsHeld: null,

        action: '',
        mom: '',

        finalHearingDate: null,
        finalOutcome: '',
        actionTakenDescription: '',
        actionTakenSharedDate: null,
        finalPenalty: '',
        deanAppealDate: null,
        deanAppealGrounds: 'None',
        deanDecision: 'None',
        submissionDateToDeanOffice: null
    };

    @track parties = [
        this.createParty('Complainant'),
        this.createParty('Respondent')
    ];

    @track courseOptions = [];
    @track filteredCourseOptions = [];
    @track caseStatusOptions = [];
    @track deanAppealGroundsOptions = [];
    @track deanDecisionOptions = [];
    @track finalOutcomeOptions = [];

    saving = false;
    courseSearchTerm = '';
    isCourseDropdownOpen = false;

    get isLoading() {
        return this.saving;
    }

    get partyTypeOptions() {
        return PARTY_TYPES.map((value) => ({ label: value, value }));
    }

    get partyRoleOptions() {
        return PARTY_ROLES.map((value) => ({ label: value, value }));
    }

    get partyRows() {
        return this.parties.map((party, index) => ({
            ...party,
            title: `Party ${index + 1}`,
            disableRemove: this.parties.length <= 1
        }));
    }

    get isStudentStaffStudent() {
        return this.form.studentStaffType === STUDENT_TYPE;
    }

    get isStudentStaffNonStudent() {
        return this.form.studentStaffType !== STUDENT_TYPE;
    }

    get meetingCompletionOptions() {
        return [
            { label: 'Completed', value: 'Completed' },
            { label: 'Not Completed', value: 'Not Completed' }
        ];
    }

    get isCourseDisabled() {
        return !this.form.programId || !this.form.academicYearId;
    }

    get hasFilteredCourseOptions() {
        return this.filteredCourseOptions.length > 0;
    }

    get courseComboboxClass() {
        return `slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click ${this.isCourseDropdownOpen ? 'slds-is-open' : ''}`;
    }

    @wire(getObjectInfo, { objectApiName: CASHD_COMMITTEE_OBJECT })
    cashdObjectInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$cashdObjectInfo.data.defaultRecordTypeId',
        fieldApiName: CASE_STATUS_FIELD
    })
    wiredCaseStatusValues({ data, error }) {
        if (data?.values) {
            this.caseStatusOptions = data.values.map((item) => ({ label: item.label, value: item.value }));
            return;
        }
        if (error) {
            this.caseStatusOptions = [];
        }
    }

    @wire(getPicklistValues, {
        recordTypeId: '$cashdObjectInfo.data.defaultRecordTypeId',
        fieldApiName: DEAN_APPEAL_GROUNDS_FIELD
    })
    wiredDeanAppealGroundsValues({ data, error }) {
        if (data?.values) {
            this.deanAppealGroundsOptions = data.values.map((item) => ({ label: item.label, value: item.value }));
            return;
        }
        if (error) {
            this.deanAppealGroundsOptions = [];
        }
    }

    @wire(getPicklistValues, {
        recordTypeId: '$cashdObjectInfo.data.defaultRecordTypeId',
        fieldApiName: DEAN_DECISION_FIELD
    })
    wiredDeanDecisionValues({ data, error }) {
        if (data?.values) {
            this.deanDecisionOptions = data.values.map((item) => ({ label: item.label, value: item.value }));
            return;
        }
        if (error) {
            this.deanDecisionOptions = [];
        }
    }

    @wire(getPicklistValues, {
        recordTypeId: '$cashdObjectInfo.data.defaultRecordTypeId',
        fieldApiName: FINAL_OUTCOME_FIELD
    })
    wiredFinalOutcomeValues({ data, error }) {
        if (data?.values) {
            this.finalOutcomeOptions = data.values.map((item) => ({
                label: item.label,
                value: item.value
            }));
            return;
        }
        if (error) {
            this.finalOutcomeOptions = [];
        }
    }

    createParty(defaultRole) {
        return this.decorateParty({
            key: `${Date.now()}-${Math.random()}`,
            role: defaultRole,
            type: STUDENT_TYPE,
            studentId: '',
            email: '',
            contactId: null,
            resolvedName: '',
            ndaSignedDate: null
        });
    }

    decorateParty(party) {
        const isComplainant = party.role === 'Complainant';
        const isStudentType = party.type === STUDENT_TYPE;
        const prefix = isComplainant ? 'Complainant' : 'Respondent';
        return {
            ...party,
            isStudentType,
            isNonStudentType: !isStudentType,
            typeLabel: `${prefix} Type`,
            emailLabel: `${prefix} Email`,
            studentIdLabel: `${prefix} Student ID`,
            nameLabel: isComplainant ? 'Name of the Complainant' : 'Name of the Respondent',
            ndaLabel: isComplainant ? 'Complainant NDA Signed and Date' : 'Respondent NDA Signed and date'
        };
    }

    handleFieldChange(event) {
        const field = event.target.dataset.field;
        this.form = { ...this.form, [field]: event.target.value };
    }

    handleStudentStaffTypeChange(event) {
        const studentStaffType = event.target.value;
        this.form = {
            ...this.form,
            studentStaffType,
            staffEmail: '',
            studentId: '',
            studentStaffContactId: null,
            studentStaffName: ''
        };
    }

    async loadCourseOfferingsByContext(programId, academicYearId) {
        if (!programId || !academicYearId) {
            this.courseOptions = [];
            this.filteredCourseOptions = [];
            this.courseSearchTerm = '';
            this.form = { ...this.form, courseOfferingId: '' };
            return;
        }
        try {
            const results = await searchCourseOfferings({ programId, academicYearId });
            this.courseOptions = (results || []).map((item) => ({
                value: item.Id,
                label: item?.LearningCourse?.Name ? `${item.LearningCourse.Name} (${item.Name})` : item.Name
            }));
            if (this.courseOptions.length === 1) {
                this.form = {
                    ...this.form,
                    courseOfferingId: this.courseOptions[0].value
                };
                this.courseSearchTerm = this.courseOptions[0].label;
            } else {
                this.form = { ...this.form, courseOfferingId: '' };
                this.courseSearchTerm = '';
            }
            this.filteredCourseOptions = [...this.courseOptions];
        } catch (error) {
            this.showToast('Course load failed', this.getErrorMessage(error), 'error');
        }
    }

    handleCourseSearchInput(event) {
        const term = (event.target.value || '').trim();
        this.courseSearchTerm = event.target.value || '';
        this.form = { ...this.form, courseOfferingId: '' };
        this.filteredCourseOptions = this.filterCourseOptions(term);
        this.isCourseDropdownOpen = !this.isCourseDisabled;
    }

    handleCourseSearchFocus() {
        if (this.isCourseDisabled) {
            return;
        }
        this.filteredCourseOptions = this.filterCourseOptions(this.courseSearchTerm.trim());
        this.isCourseDropdownOpen = true;
    }

    handleCourseSearchBlur() {
        window.clearTimeout(this.courseBlurTimeout);
        this.courseBlurTimeout = window.setTimeout(() => {
            this.isCourseDropdownOpen = false;
            const selected = this.courseOptions.find((opt) => opt.value === this.form.courseOfferingId);
            if (selected) {
                this.courseSearchTerm = selected.label;
            }
        }, 150);
    }

    handleCourseOptionSelect(event) {
        const selectedId = event.currentTarget?.dataset?.value;
        this.applyCourseSelection(selectedId);
    }

    handleCourseOptionMouseDown(event) {
        event.preventDefault();
        const selectedId = event.currentTarget?.dataset?.value;
        this.applyCourseSelection(selectedId);
    }

    applyCourseSelection(selectedId) {
        const selected = this.courseOptions.find((opt) => opt.value === selectedId);
        if (!selected) {
            return;
        }
        this.form = {
            ...this.form,
            courseOfferingId: selected.value
        };
        this.courseSearchTerm = selected.label;
        this.filteredCourseOptions = this.filterCourseOptions(selected.label);
        this.isCourseDropdownOpen = false;
    }

    filterCourseOptions(term) {
        const normalized = (term || '').toLowerCase();
        if (!normalized) {
            return [...this.courseOptions];
        }
        return this.courseOptions.filter((option) => (option.label || '').toLowerCase().includes(normalized));
    }

    handleCourseSelection(event) {
        const courseOfferingId = event.detail.value;
        this.form = {
            ...this.form,
            courseOfferingId
        };
    }

    async handlePgidBlur() {
        const pgid = (this.form.studentPgid || '').trim();
        if (!pgid) {
            return;
        }
        try {
            const result = await getProgramEnrollmentByPGID({ pgid });
            if (!result) {
                this.showToast('Invalid PG ID', `No active Program Enrollment found for ${pgid}.`, 'error');
                return;
            }

            this.form = {
                ...this.form,
                studentProgramEnrollmentId: result.enrollmentId || null,
                studentContactId: result.contactId || null,
                studentName: result.studentName || '',
                studentEmail: result.studentEmail || '',
                studentMobile: result.studentMobile || '',
                programEnrollmentId: result.enrollmentId || null,
                programEnrollmentName: result.enrollmentName || '',
                programId: result.programId || null,
                programName: result.programName || '',
                programCode: result.programCode || '',
                academicYearId: result.academicYearId || null,
                academicYear: result.academicYearName || '',
                currentReportingLocationId: result.currentReportingLocationId || null,
                currentReportingLocationName: result.currentReportingLocationName || ''
            };

            await this.loadCourseOfferingsByContext(result.programId || null, result.academicYearId || null);
        } catch (error) {
            this.showToast('PGID lookup failed', this.getErrorMessage(error), 'error');
        }
    }

    async handleStudentStaffBlur() {
        try {
            if (this.form.studentStaffType === STUDENT_TYPE) {
                if (!this.form.studentId) {
                    return;
                }
                const result = await getContactByStudentId({ studentId: this.form.studentId });
                if (!result) {
                    return;
                }
                this.form = {
                    ...this.form,
                    studentStaffContactId: result.contactId,
                    studentStaffName: result.name || ''
                };
                return;
            }

            if (!this.form.staffEmail) {
                return;
            }
            const result = await getContactByEmail({ email: this.form.staffEmail });
            if (!result) {
                return;
            }
            this.form = {
                ...this.form,
                studentStaffContactId: result.id,
                studentStaffName: result.name || ''
            };
        } catch (error) {
            this.showToast('Student/Staff lookup failed', this.getErrorMessage(error), 'error');
        }
    }

    addParty() {
        this.parties = [...this.parties, this.createParty('Complainant')];
    }

    removeParty(event) {
        const key = event.target.dataset.key;
        if (this.parties.length <= 1) {
            return;
        }
        this.parties = this.parties.filter((p) => p.key !== key);
    }

    handlePartyChange(event) {
        const key = event.target.dataset.key;
        const field = event.target.dataset.field;
        const value = event.target.value;

        this.parties = this.parties.map((party) => {
            if (party.key !== key) {
                return party;
            }
            const updated = { ...party, [field]: value };
            if (field === 'type') {
                updated.studentId = '';
                updated.email = '';
                updated.contactId = null;
                updated.resolvedName = '';
            }
            return this.decorateParty(updated);
        });
    }

    async handlePartyStudentBlur(event) {
        const key = event.target.dataset.key;
        const party = this.parties.find((p) => p.key === key);
        if (!party || !party.studentId) {
            return;
        }
        try {
            const result = await getContactByStudentId({ studentId: party.studentId });
            if (!result) {
                return;
            }
            this.parties = this.parties.map((p) => (
                p.key === key
                    ? this.decorateParty({ ...p, contactId: result.contactId, resolvedName: result.name || '' })
                    : p
            ));
        } catch (error) {
            this.showToast('Student lookup failed', this.getErrorMessage(error), 'error');
        }
    }

    async handlePartyEmailBlur(event) {
        const key = event.target.dataset.key;
        const party = this.parties.find((p) => p.key === key);
        if (!party || !party.email) {
            return;
        }
        try {
            const result = await getContactByEmail({ email: party.email });
            this.parties = this.parties.map((p) => (
                p.key === key
                    ? this.decorateParty({
                        ...p,
                        contactId: result?.id || null,
                        resolvedName: result?.name || p.email || ''
                    })
                    : p
            ));
        } catch (error) {
            this.showToast('Email lookup failed', this.getErrorMessage(error), 'error');
        }
    }

    async handleSave() {
        if (!this.form.subject) {
            this.showToast('Missing data', 'Subject is required.', 'error');
            return;
        }

        const partyValidationMessage = this.validateParties();
        if (partyValidationMessage) {
            this.showToast('Missing data', partyValidationMessage, 'error');
            return;
        }

        this.saving = true;
        try {
            const partiesPayload = this.parties.map((p) => ({
                role: p.role,
                type: p.type,
                studentId: p.studentId,
                email: p.email,
                contactId: p.contactId,
                ndaSignedDate: p.ndaSignedDate
            }));
            const partiesJson = JSON.stringify(partiesPayload);
            const payload = {
                ...this.form,
                parties: partiesPayload,
                partiesJson,
                // Duplicate alias protects against serialization edge cases in Aura payload mapping.
                partyJson: partiesJson
            };
            const recordId = await createCASHDRecord({ data: payload });

            this.showToast('Success', 'CASHD record created successfully.', 'success');
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId,
                    objectApiName: 'CASHD_Committee__c',
                    actionName: 'view'
                }
            });
        } catch (error) {
            this.showToast('Save failed', this.getErrorMessage(error), 'error');
        } finally {
            this.saving = false;
        }
    }

    validateParties() {
        if (!this.parties.length) {
            return 'Add at least one party.';
        }

        let hasComplainant = false;
        let hasRespondent = false;

        for (const party of this.parties) {
            if (!party.role || !party.type) {
                return 'Each party row must have Role and Type.';
            }
            if (party.role === 'Complainant') {
                hasComplainant = true;
            }
            if (party.role === 'Respondent') {
                hasRespondent = true;
            }
            if (party.type === STUDENT_TYPE && !party.studentId) {
                return 'Student party rows require Student ID.';
            }
            if (party.type !== STUDENT_TYPE && !party.email) {
                return 'Staff/Alumni/Others party rows require Email.';
            }
        }

        if (!hasComplainant || !hasRespondent) {
            return 'Add at least one Complainant and one Respondent party.';
        }

        return null;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    getErrorMessage(error) {
        if (error?.body?.message) {
            return error.body.message;
        }

        const outputError = error?.body?.output?.errors?.[0]?.message;
        if (outputError) {
            return outputError;
        }

        const fieldErrors = error?.body?.output?.fieldErrors;
        if (fieldErrors) {
            const firstField = Object.keys(fieldErrors)[0];
            const firstFieldMsg = firstField && fieldErrors[firstField]?.[0]?.message;
            if (firstFieldMsg) {
                return firstFieldMsg;
            }
        }

        return error?.message || 'Unknown error';
    }
}