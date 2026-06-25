import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { getPicklistValues } from 'lightning/uiObjectInfoApi';

import HONOUR_CODE_COMMITTEE_OBJECT from '@salesforce/schema/Honour_Code_Committee__c';
import CHAIR_DECISION_FIELD        from '@salesforce/schema/Honour_Code_Committee__c.Chair_Decision__c';
import COMMITTEE_DECISION_FIELD    from '@salesforce/schema/Honour_Code_Committee__c.Committee_Decision__c';
import DEAN_APPEAL_GROUNDS_FIELD   from '@salesforce/schema/Honour_Code_Committee__c.Dean_Appeal_Grounds__c';
import DEAN_DECISION_FIELD         from '@salesforce/schema/Honour_Code_Committee__c.Dean_Decision__c';
import FINAL_COMM_OUTCOME_FIELD    from '@salesforce/schema/Honour_Code_Committee__c.Final_communication_Outcome__c';
import HEARING_STATUS_FIELD        from '@salesforce/schema/Honour_Code_Committee__c.Hearing_Status__c';
import PENALTY_TYPE_FIELD          from '@salesforce/schema/Honour_Code_Committee__c.Penalty_Type__c';
import RESPONSE_TO_CHARGES_FIELD   from '@salesforce/schema/Honour_Code_Committee__c.Response_To_Charges__c';
import VIOLATION_TYPE_FIELD        from '@salesforce/schema/Honour_Code_Committee__c.Violation_Type__c';

import searchPrograms             from '@salesforce/apex/HCCRecordCreateController.searchPrograms';
import searchAcademicYears        from '@salesforce/apex/HCCRecordCreateController.searchAcademicYears';
import searchLocations            from '@salesforce/apex/HCCRecordCreateController.searchLocations';
import searchAcademicSessions     from '@salesforce/apex/HCCRecordCreateController.searchAcademicSessions';
import searchCourseOfferings      from '@salesforce/apex/HCCRecordCreateController.searchCourseOfferings';
import searchFacultiesByCourseOffering from '@salesforce/apex/HCCRecordCreateController.searchFacultiesByCourseOffering';
import getProgramEnrollmentByPGID from '@salesforce/apex/HCCRecordCreateController.getProgramEnrollmentByPGID';
import getContactByEmail          from '@salesforce/apex/HCCRecordCreateController.getContactByEmail';
import createHCCRecord            from '@salesforce/apex/HCCRecordCreateController.createHCCRecord';

const NONE_OPTION = { label: '--None--', value: '' };

export default class HccRecordCreate extends NavigationMixin(LightningElement) {

    // â”€â”€ Form state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    @track isLoading = false;
    @track submitted = false;
    @track errorMessage = '';
    @track pgidLookupLoading = false;

    // â”€â”€ Student context fields â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    @track pgid = '';

    // Program lookup
    @track programId = '';
    @track programName = '';
    @track programCode = '';
    @track programSearchTerm = '';
    @track programOptions = [];
    @track programLoading = false;
    @track showProgramDropdown = false;
    _programTimer;

    // Academic Year lookup
    @track academicYearId = '';
    @track academicYearName = '';
    @track academicYearSearchTerm = '';
    @track academicYearOptions = [];
    @track academicYearLoading = false;
    @track showAcademicYearDropdown = false;
    _academicYearTimer;

    // Current Reporting Location lookup
    @track currentReportingLocationId = '';
    @track currentReportingLocationName = '';
    @track currentReportingLocationSearchTerm = '';
    @track currentReportingLocationOptions = [];
    @track currentReportingLocationLoading = false;
    @track showCurrentReportingLocationDropdown = false;
    _currentReportingLocationTimer;

    // Academic Session lookup
    @track academicSessionId = '';
    @track academicSessionName = '';
    @track academicSessionSearchTerm = '';
    @track academicSessionOptions = [];
    @track academicSessionLoading = false;
    @track showAcademicSessionDropdown = false;
    _academicSessionTimer;

    // â”€â”€ Auto-populated student fields (read-only) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    @track enrollmentId = '';
    @track contactId = '';
    @track studentName = '';
    @track studentEmail = '';
    @track studentMobile = '';
    @track studentNameEditable = false;
    @track studentEmailEditable = false;
    @track studentMobileEditable = false;

    // â”€â”€ Course Offering lookup â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    @track courseOfferingId = '';
    @track courseOfferingName = '';
    @track courseOfferingSearchTerm = '';
    @track courseOfferingOptions = [];
    @track courseOfferingLoading = false;
    @track showCourseOfferingDropdown = false;
    _courseOfferingTimer;

    // Reported Faculty lookup (depends on selected course offering)
    @track reportedFacultyId = '';
    @track reportedFacultyName = '';
    @track reportedFacultySearchTerm = '';
    @track reportedFacultyOptions = [];
    @track reportedFacultyLoading = false;
    @track showReportedFacultyDropdown = false;
    _reportedFacultyTimer;

    // â”€â”€ Case Initiation â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    @track caseReportedDate = new Date().toISOString().substring(0, 10);
    @track submissionDate = '';
    @track violationType = '';
    @track componentName = '';
    @track turnitinSimilarity = '';
    @track initialEvidence = '';

    // â”€â”€ Student Information (editable) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    @track previousViolationFoundGuiltyDate = '';

    // â”€â”€ Initial Review â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    @track hccChairISBEmail = '';
    @track chairContactName = '';
    @track chairContactId = '';
    @track chairLookupLoading = false;
    @track chairDecision = '';
    @track decisionReason = '';

    // â”€â”€ Student Communication â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    @track responseDeadline = '';
    @track responseToCharges = '';
    @track statementRequestDate = '';
    @track outcomeEmailDate = '';

    // â”€â”€ Committee Preparation â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    @track hearingDate = '';
    @track convenerEmail = '';
    @track emailIdsFacultyMembers = '';
    @track emailIdsStudentMembers = '';
    @track emailSentToCommittee = false;

    // â”€â”€ Hearing â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    @track hearingStatus = '';
    @track recordingUrl = '';
    @track hearingAttendance = '';

    // â”€â”€ Committee Decision â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    @track voteResult = '';
    @track committeeDecision = '';
    @track penaltyType = '';
    @track penaltyDetails = '';

    // â”€â”€ Communication â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    @track decisionNotificationDateToStudent = '';
    @track finalCommunicationOutcome = '';

    // â”€â”€ Appeal (Dean) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    @track deanAppealDate = '';
    @track deanAppealGrounds = '';
    @track deanDecision = '';
    @track finalPenalty = '';
    @track appealRemarks = '';

    // â”€â”€ Closure â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    @track caseClosedDate = '';
    @track coursePenalty = '';
    @track penaltyEnforced = false;

    // â”€â”€ Picklist options (dynamically loaded from org) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    @track chairDecisionOptions = [];
    @track committeeDecisionOptions = [];
    @track deanAppealGroundsOptions = [];
    @track deanDecisionOptions = [];
    @track finalCommOutcomeOptions = [];
    @track hearingStatusOptions = [];
    @track penaltyTypeOptions = [];
    @track filteredPenaltyTypeOptions = [];
    @track responseToChargesOptions = [];
    @track violationTypeOptions = [];

    // â”€â”€ Wire: object info (needed to resolve default record type for picklists) â”€
    @wire(getObjectInfo, { objectApiName: HONOUR_CODE_COMMITTEE_OBJECT })
    objectInfo;

    @wire(getPicklistValues, { recordTypeId: '$objectInfo.data.defaultRecordTypeId', fieldApiName: CHAIR_DECISION_FIELD })
    wiredChairDecision({ data }) {
        if (data) this.chairDecisionOptions = [NONE_OPTION, ...data.values.map(v => ({ label: this.normalizePicklistLabel('Chair_Decision__c', v.label), value: v.value }))];
    }

    @wire(getPicklistValues, { recordTypeId: '$objectInfo.data.defaultRecordTypeId', fieldApiName: COMMITTEE_DECISION_FIELD })
    wiredCommitteeDecision({ data }) {
        if (data) this.committeeDecisionOptions = [NONE_OPTION, ...data.values.map(v => ({ label: this.normalizePicklistLabel('Committee_Decision__c', v.label), value: v.value }))];
    }

    @wire(getPicklistValues, { recordTypeId: '$objectInfo.data.defaultRecordTypeId', fieldApiName: DEAN_APPEAL_GROUNDS_FIELD })
    wiredDeanAppealGrounds({ data }) {
        if (data) this.deanAppealGroundsOptions = [NONE_OPTION, ...data.values.map(v => ({ label: this.normalizePicklistLabel('Dean_Appeal_Grounds__c', v.label), value: v.value }))];
    }

    @wire(getPicklistValues, { recordTypeId: '$objectInfo.data.defaultRecordTypeId', fieldApiName: DEAN_DECISION_FIELD })
    wiredDeanDecision({ data }) {
        if (data) this.deanDecisionOptions = [NONE_OPTION, ...data.values.map(v => ({ label: this.normalizePicklistLabel('Dean_Decision__c', v.label), value: v.value }))];
    }

    @wire(getPicklistValues, { recordTypeId: '$objectInfo.data.defaultRecordTypeId', fieldApiName: FINAL_COMM_OUTCOME_FIELD })
    wiredFinalCommOutcome({ data }) {
        if (data) this.finalCommOutcomeOptions = [NONE_OPTION, ...data.values.map(v => ({ label: v.label, value: v.value }))];
    }

    @wire(getPicklistValues, { recordTypeId: '$objectInfo.data.defaultRecordTypeId', fieldApiName: HEARING_STATUS_FIELD })
    wiredHearingStatus({ data }) {
        if (data) this.hearingStatusOptions = [NONE_OPTION, ...data.values.map(v => ({ label: v.label, value: v.value }))];
    }

    @wire(getPicklistValues, { recordTypeId: '$objectInfo.data.defaultRecordTypeId', fieldApiName: PENALTY_TYPE_FIELD })
    wiredPenaltyType({ data }) {
        if (data) {
            this.penaltyTypeOptions = [NONE_OPTION, ...data.values.map(v => ({ label: this.normalizePicklistLabel('Penalty_Type__c', v.label), value: v.value }))];
            this.applyPenaltyTypeFilter();
        }
    }

    @wire(getPicklistValues, { recordTypeId: '$objectInfo.data.defaultRecordTypeId', fieldApiName: RESPONSE_TO_CHARGES_FIELD })
    wiredResponseToCharges({ data }) {
        if (data) this.responseToChargesOptions = [NONE_OPTION, ...data.values.map(v => ({ label: v.label, value: v.value }))];
    }

    @wire(getPicklistValues, { recordTypeId: '$objectInfo.data.defaultRecordTypeId', fieldApiName: VIOLATION_TYPE_FIELD })
    wiredViolationType({ data }) {
        if (data) this.violationTypeOptions = [NONE_OPTION, ...data.values.map(v => ({ label: v.label, value: v.value }))];
    }

    // â”€â”€ Computed getters: lookup dropdown helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    get hasProgramOptions()        { return this.programOptions.length > 0; }
    get hasAcademicYearOptions()   { return this.academicYearOptions.length > 0; }
    get hasAcademicSessionOptions(){ return this.academicSessionOptions.length > 0; }
    get hasCourseOfferingOptions() { return this.courseOfferingOptions.length > 0; }
    get hasReportedFacultyOptions(){ return this.reportedFacultyOptions.length > 0; }
    get isReportedFacultyLookupDisabled() { return !this.courseOfferingId; }
    get isStudentNameLocked() { return !!this.studentName; }
    get isStudentEmailLocked() { return !!this.studentEmail; }
    get isStudentMobileLocked() { return !!this.studentMobile; }

    // â”€â”€ Computed getters: custom lookup validation state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    get programHasError()      { return this.submitted && !this.programId; }
    get academicYearHasError() { return this.submitted && !this.academicYearId; }
    get chairNoContactFound()  { return this.hccChairISBEmail && !this.chairLookupLoading && !this.chairContactName; }

    get programContainerClass() {
        return 'slds-form-element lookup-container' + (this.programHasError ? ' has-error' : '');
    }
    get academicYearContainerClass() {
        return 'slds-form-element lookup-container' + (this.academicYearHasError ? ' has-error' : '');
    }

    // â”€â”€ PGID change: clear auto-populated student fields â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    handlePgidChange(e) {
        this.pgid = e.target.value;
        this.enrollmentId  = '';
        this.contactId     = '';
        this.studentName   = '';
        this.studentEmail  = '';
        this.studentMobile = '';
        this.studentNameEditable = false;
        this.studentEmailEditable = false;
        this.studentMobileEditable = false;
        this.programId = '';
        this.programName = '';
        this.academicYearId = '';
        this.academicYearName = '';
        this.currentReportingLocationId = '';
        this.currentReportingLocationName = '';
    }

    // â”€â”€ PGID blur: auto-lookup student details â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    handlePgidBlur() {
        if (!this.pgid || this.pgidLookupLoading) return;
        this.pgidLookupLoading = true;
        this.errorMessage = '';
        getProgramEnrollmentByPGID({ pgid: this.pgid })
            .then(result => {
                this.pgidLookupLoading = false;
                if (result) {
                    this.enrollmentId  = result.enrollmentId  || '';
                    this.contactId     = result.contactId     || '';
                    this.studentName   = result.studentName   || '';
                    this.studentEmail  = result.studentEmail  || '';
                    this.studentMobile = result.studentMobile || '';
                    this.studentNameEditable = !result.studentName;
                    this.studentEmailEditable = !result.studentEmail;
                    this.studentMobileEditable = !result.studentMobile;
                    if (result.programId) {
                        this.programId = result.programId;
                        this.programName = result.programName || '';
                        this.programCode = result.programCode || '';
                    }
                    if (result.academicYearId) {
                        this.academicYearId = result.academicYearId;
                        this.academicYearName = result.academicYearName || '';
                    }
                    if (result.currentReportingLocationId) {
                        this.currentReportingLocationId = result.currentReportingLocationId;
                        this.currentReportingLocationName = result.currentReportingLocationName || '';
                    }
                    this.applyPenaltyTypeFilter();
                } else {
                    this.errorMessage = 'No active Program Enrollment found for PGID: ' + this.pgid;
                }
            })
            .catch(err => {
                this.pgidLookupLoading = false;
                this.errorMessage = err.body ? err.body.message : String(err);
            });
    }

    // â”€â”€ Simple field handlers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    handleCaseReportedDateChange(e)             { this.caseReportedDate = e.target.value; }
    handleSubmissionDateChange(e)               { this.submissionDate = e.target.value; }
    handleViolationTypeChange(e)                { this.violationType = e.detail.value; }
    handleComponentNameChange(e)                { this.componentName = e.target.value; }
    handleTurnitinSimilarityChange(e)           { this.turnitinSimilarity = e.target.value; }
    handleInitialEvidenceChange(e)              { this.initialEvidence = e.target.value; }
    handlePreviousViolationFoundGuiltyDateChange(e) { this.previousViolationFoundGuiltyDate = e.target.value; }
    handleHccChairISBEmailChange(e) {
        this.hccChairISBEmail = e.target.value;
        this.chairContactName = '';
        this.chairContactId   = '';
    }
    handleHccChairISBEmailBlur() {
        if (!this.hccChairISBEmail || this.chairLookupLoading) return;
        this.chairLookupLoading = true;
        getContactByEmail({ email: this.hccChairISBEmail })
            .then(result => {
                this.chairLookupLoading = false;
                if (result) {
                    this.chairContactId   = result.id   || '';
                    this.chairContactName = result.name || '';
                } else {
                    this.chairContactId   = '';
                    this.chairContactName = '';
                }
            })
            .catch(() => { this.chairLookupLoading = false; });
    }
    handleChairDecisionChange(e)                { this.chairDecision = e.detail.value; }
    handleDecisionReasonChange(e)               { this.decisionReason = e.target.value; }
    handleResponseDeadlineChange(e)             { this.responseDeadline = e.target.value; }
    handleResponseToChargesChange(e)            { this.responseToCharges = e.detail.value; }
    handleStatementRequestDateChange(e)         { this.statementRequestDate = e.target.value; }
    handleOutcomeEmailDateChange(e)             { this.outcomeEmailDate = e.target.value; }
    handleHearingDateChange(e)                  { this.hearingDate = e.target.value; }
    handleConvenerEmailChange(e)                { this.convenerEmail = e.target.value; }
    handleEmailIdsFacultyMembersChange(e)       { this.emailIdsFacultyMembers = e.target.value; }
    handleEmailIdsStudentMembersChange(e)       { this.emailIdsStudentMembers = e.target.value; }
    handleEmailSentToCommitteeChange(e)         { this.emailSentToCommittee = e.target.checked; }
    handleHearingStatusChange(e)                { this.hearingStatus = e.detail.value; }
    handleRecordingUrlChange(e)                 { this.recordingUrl = e.target.value; }
    handleHearingAttendanceChange(e)            { this.hearingAttendance = e.target.value; }
    handleVoteResultChange(e)                   { this.voteResult = e.target.value; }
    handleCommitteeDecisionChange(e)            { this.committeeDecision = e.detail.value; }
    handlePenaltyTypeChange(e)                  { this.penaltyType = e.detail.value; }
    handlePenaltyDetailsChange(e)               { this.penaltyDetails = e.target.value; }
    handleDecisionNotificationDateToStudentChange(e) { this.decisionNotificationDateToStudent = e.target.value; }
    handleFinalCommunicationOutcomeChange(e)    { this.finalCommunicationOutcome = e.detail.value; }
    handleDeanAppealDateChange(e)               { this.deanAppealDate = e.target.value; }
    handleDeanAppealGroundsChange(e)            { this.deanAppealGrounds = e.detail.value; }
    handleDeanDecisionChange(e)                 { this.deanDecision = e.detail.value; }
    handleFinalPenaltyChange(e)                 { this.finalPenalty = e.target.value; }
    handleAppealRemarksChange(e)                { this.appealRemarks = e.target.value; }
    handleCaseClosedDateChange(e)               { this.caseClosedDate = e.target.value; }
    handleCoursePenaltyChange(e)                { this.coursePenalty = e.target.value; }
    handlePenaltyEnforcedChange(e)              { this.penaltyEnforced = e.target.checked; }

    // Reported Faculty lookup
    handleReportedFacultyKeyUp(e) {
        this.reportedFacultySearchTerm = e.target.value;
        clearTimeout(this._reportedFacultyTimer);
        this.showReportedFacultyDropdown = true;
        if (!this.courseOfferingId) {
            this.reportedFacultyOptions = [];
            return;
        }
        this._reportedFacultyTimer = setTimeout(() => {
            this.reportedFacultyLoading = true;
            searchFacultiesByCourseOffering({ searchTerm: this.reportedFacultySearchTerm, courseOfferingId: this.courseOfferingId })
                .then(data => {
                    this.reportedFacultyOptions = data.map(r => ({
                        id: r.Id,
                        name: r.Name,
                        label: r.Email ? (r.Name + ' (' + r.Email + ')') : r.Name
                    }));
                    this.reportedFacultyLoading = false;
                })
                .catch(() => { this.reportedFacultyLoading = false; });
        }, 300);
    }
    handleReportedFacultyFocus() {
        this.showReportedFacultyDropdown = true;
        if (!this.courseOfferingId) {
            this.reportedFacultyOptions = [];
            return;
        }
        if (this.reportedFacultyOptions.length === 0 && !this.reportedFacultyLoading) {
            this.reportedFacultyLoading = true;
            searchFacultiesByCourseOffering({ searchTerm: '', courseOfferingId: this.courseOfferingId })
                .then(data => {
                    this.reportedFacultyOptions = data.map(r => ({
                        id: r.Id,
                        name: r.Name,
                        label: r.Email ? (r.Name + ' (' + r.Email + ')') : r.Name
                    }));
                    this.reportedFacultyLoading = false;
                })
                .catch(() => { this.reportedFacultyLoading = false; });
        }
    }
    handleReportedFacultyBlur() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { this.showReportedFacultyDropdown = false; }, 200);
    }
    handleReportedFacultySelect(e) {
        this.reportedFacultyId = e.currentTarget.dataset.id;
        this.reportedFacultyName = e.currentTarget.dataset.name;
        this.showReportedFacultyDropdown = false;
        this.reportedFacultySearchTerm = '';
    }
    handleReportedFacultyClear() {
        this.clearReportedFaculty();
    }

    clearReportedFaculty() {
        this.reportedFacultyId = '';
        this.reportedFacultyName = '';
        this.reportedFacultySearchTerm = '';
        this.reportedFacultyOptions = [];
        this.reportedFacultyLoading = false;
        this.showReportedFacultyDropdown = false;
    }

    // â”€â”€ Program lookup â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    handleProgramKeyUp(e) {
        this.programSearchTerm = e.target.value;
        clearTimeout(this._programTimer);
        this.showProgramDropdown = true;
        this._programTimer = setTimeout(() => {
            this.programLoading = true;
            searchPrograms({ searchTerm: this.programSearchTerm })
                .then(data => { this.programOptions = data.map(r => ({ id: r.Id, name: r.Name })); this.programLoading = false; })
                .catch(() => { this.programLoading = false; });
        }, 300);
    }
    handleProgramFocus() {
        this.showProgramDropdown = true;
        if (this.programOptions.length === 0 && !this.programLoading) {
            this.programLoading = true;
            searchPrograms({ searchTerm: '' })
                .then(data => { this.programOptions = data.map(r => ({ id: r.Id, name: r.Name })); this.programLoading = false; })
                .catch(() => { this.programLoading = false; });
        }
    }
    handleProgramBlur() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { this.showProgramDropdown = false; }, 200);
    }
    handleProgramSelect(e) {
        this.programId   = e.currentTarget.dataset.id;
        this.programName = e.currentTarget.dataset.name;
        this.programCode = '';
        this.showProgramDropdown = false;
        this.programSearchTerm = '';
        this.academicSessionId = '';
        this.academicSessionName = '';
        this.academicSessionSearchTerm = '';
        this.academicSessionOptions = [];
        this.courseOfferingId = ''; this.courseOfferingName = ''; this.courseOfferingOptions = [];
        this.clearReportedFaculty();
        this.currentReportingLocationId = '';
        this.currentReportingLocationName = '';
        this.applyPenaltyTypeFilter();
    }
    handleProgramClear() {
        this.programId = ''; this.programName = ''; this.programCode = ''; this.programSearchTerm = ''; this.programOptions = [];
        this.academicSessionId = '';
        this.academicSessionName = '';
        this.academicSessionSearchTerm = '';
        this.academicSessionOptions = [];
        this.courseOfferingId = ''; this.courseOfferingName = ''; this.courseOfferingOptions = [];
        this.clearReportedFaculty();
        this.currentReportingLocationId = '';
        this.currentReportingLocationName = '';
        this.applyPenaltyTypeFilter();
    }

    // â”€â”€ Academic Year lookup â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    handleAcademicYearKeyUp(e) {
        this.academicYearSearchTerm = e.target.value;
        clearTimeout(this._academicYearTimer);
        this.showAcademicYearDropdown = true;
        this._academicYearTimer = setTimeout(() => {
            this.academicYearLoading = true;
            searchAcademicYears({ searchTerm: this.academicYearSearchTerm })
                .then(data => { this.academicYearOptions = data.map(r => ({ id: r.Id, name: r.Name })); this.academicYearLoading = false; })
                .catch(() => { this.academicYearLoading = false; });
        }, 300);
    }
    handleAcademicYearFocus() {
        this.showAcademicYearDropdown = true;
        if (this.academicYearOptions.length === 0 && !this.academicYearLoading) {
            this.academicYearLoading = true;
            searchAcademicYears({ searchTerm: '' })
                .then(data => { this.academicYearOptions = data.map(r => ({ id: r.Id, name: r.Name })); this.academicYearLoading = false; })
                .catch(() => { this.academicYearLoading = false; });
        }
    }
    handleAcademicYearBlur() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { this.showAcademicYearDropdown = false; }, 200);
    }
    handleAcademicYearSelect(e) {
        this.academicYearId   = e.currentTarget.dataset.id;
        this.academicYearName = e.currentTarget.dataset.name;
        this.showAcademicYearDropdown = false;
        this.academicYearSearchTerm = '';
        this.courseOfferingId = ''; this.courseOfferingName = ''; this.courseOfferingOptions = [];
        this.clearReportedFaculty();
        this.currentReportingLocationId = '';
        this.currentReportingLocationName = '';
    }
    handleAcademicYearClear() {
        this.academicYearId = ''; this.academicYearName = ''; this.academicYearSearchTerm = ''; this.academicYearOptions = [];
        this.courseOfferingId = ''; this.courseOfferingName = ''; this.courseOfferingOptions = [];
        this.clearReportedFaculty();
        this.currentReportingLocationId = '';
        this.currentReportingLocationName = '';
    }

    // Current Reporting Location lookup
    handleCurrentReportingLocationKeyUp(e) {
        this.currentReportingLocationSearchTerm = e.target.value;
        clearTimeout(this._currentReportingLocationTimer);
        this.showCurrentReportingLocationDropdown = true;
        this._currentReportingLocationTimer = setTimeout(() => {
            this.currentReportingLocationLoading = true;
            searchLocations({ searchTerm: this.currentReportingLocationSearchTerm })
                .then(data => {
                    this.currentReportingLocationOptions = data.map(r => ({ id: r.id, name: r.name }));
                    this.currentReportingLocationLoading = false;
                })
                .catch(() => { this.currentReportingLocationLoading = false; });
        }, 300);
    }
    handleCurrentReportingLocationFocus() {
        this.showCurrentReportingLocationDropdown = true;
        if (this.currentReportingLocationOptions.length === 0 && !this.currentReportingLocationLoading) {
            this.currentReportingLocationLoading = true;
            searchLocations({ searchTerm: '' })
                .then(data => {
                    this.currentReportingLocationOptions = data.map(r => ({ id: r.id, name: r.name }));
                    this.currentReportingLocationLoading = false;
                })
                .catch(() => { this.currentReportingLocationLoading = false; });
        }
    }
    handleCurrentReportingLocationBlur() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { this.showCurrentReportingLocationDropdown = false; }, 200);
    }
    handleCurrentReportingLocationSelect(e) {
        this.currentReportingLocationId = e.currentTarget.dataset.id;
        this.currentReportingLocationName = e.currentTarget.dataset.name;
        this.showCurrentReportingLocationDropdown = false;
        this.currentReportingLocationSearchTerm = '';
    }
    handleCurrentReportingLocationClear() {
        this.currentReportingLocationId = '';
        this.currentReportingLocationName = '';
        this.currentReportingLocationSearchTerm = '';
        this.currentReportingLocationOptions = [];
        this.currentReportingLocationLoading = false;
        this.showCurrentReportingLocationDropdown = false;
    }

    // â”€â”€ Academic Session lookup â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    handleAcademicSessionKeyUp(e) {
        this.academicSessionSearchTerm = e.target.value;
        clearTimeout(this._academicSessionTimer);
        this.showAcademicSessionDropdown = true;
        this._academicSessionTimer = setTimeout(() => {
            this.academicSessionLoading = true;
            searchAcademicSessions({ searchTerm: this.academicSessionSearchTerm, programId: this.programId })
                .then(data => { this.academicSessionOptions = data.map(r => ({ id: r.Id, name: r.Name })); this.academicSessionLoading = false; })
                .catch(() => { this.academicSessionLoading = false; });
        }, 300);
    }
    handleAcademicSessionFocus() {
        this.showAcademicSessionDropdown = true;
        if (this.academicSessionOptions.length === 0 && !this.academicSessionLoading) {
            this.academicSessionLoading = true;
            searchAcademicSessions({ searchTerm: '', programId: this.programId })
                .then(data => { this.academicSessionOptions = data.map(r => ({ id: r.Id, name: r.Name })); this.academicSessionLoading = false; })
                .catch(() => { this.academicSessionLoading = false; });
        }
    }
    handleAcademicSessionBlur() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { this.showAcademicSessionDropdown = false; }, 200);
    }
    handleAcademicSessionSelect(e) {
        this.academicSessionId   = e.currentTarget.dataset.id;
        this.academicSessionName = e.currentTarget.dataset.name;
        this.showAcademicSessionDropdown = false;
        this.academicSessionSearchTerm = '';
        this.courseOfferingId = ''; this.courseOfferingName = ''; this.courseOfferingOptions = [];
        this.clearReportedFaculty();
    }
    handleAcademicSessionClear() {
        this.academicSessionId = ''; this.academicSessionName = ''; this.academicSessionSearchTerm = ''; this.academicSessionOptions = [];
        this.courseOfferingId = ''; this.courseOfferingName = ''; this.courseOfferingOptions = [];
        this.clearReportedFaculty();
    }

    // â”€â”€ Course Offering lookup â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    handleCourseOfferingKeyUp(e) {
        this.courseOfferingSearchTerm = e.target.value;
        clearTimeout(this._courseOfferingTimer);
        this.showCourseOfferingDropdown = true;
        this._courseOfferingTimer = setTimeout(() => {
            this.courseOfferingLoading = true;
            searchCourseOfferings({ searchTerm: this.courseOfferingSearchTerm, programId: this.programId, sessionId: this.academicSessionId })
                .then(data => { this.courseOfferingOptions = data.map(r => ({ id: r.Id, name: (r.LearningCourse && r.LearningCourse.Name ? r.LearningCourse.Name + ' - ' : '') + r.Name })); this.courseOfferingLoading = false; })
                .catch(() => { this.courseOfferingLoading = false; });
        }, 300);
    }
    handleCourseOfferingFocus() {
        this.showCourseOfferingDropdown = true;
        if (this.courseOfferingOptions.length === 0 && !this.courseOfferingLoading) {
            this.courseOfferingLoading = true;
            searchCourseOfferings({ searchTerm: '', programId: this.programId, sessionId: this.academicSessionId })
                .then(data => { this.courseOfferingOptions = data.map(r => ({ id: r.Id, name: (r.LearningCourse && r.LearningCourse.Name ? r.LearningCourse.Name + ' - ' : '') + r.Name })); this.courseOfferingLoading = false; })
                .catch(() => { this.courseOfferingLoading = false; });
        }
    }
    handleCourseOfferingBlur() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { this.showCourseOfferingDropdown = false; }, 200);
    }
    handleCourseOfferingSelect(e) {
        this.courseOfferingId   = e.currentTarget.dataset.id;
        this.courseOfferingName = e.currentTarget.dataset.name;
        this.showCourseOfferingDropdown = false;
        this.courseOfferingSearchTerm = '';
        this.clearReportedFaculty();
    }
    handleCourseOfferingClear() {
        this.courseOfferingId = ''; this.courseOfferingName = ''; this.courseOfferingSearchTerm = ''; this.courseOfferingOptions = [];
        this.clearReportedFaculty();
    }

    applyPenaltyTypeFilter() {
        if (!this.programCode || this.programCode.toUpperCase() !== 'PGP') {
            this.filteredPenaltyTypeOptions = this.penaltyTypeOptions;
            return;
        }
        this.filteredPenaltyTypeOptions = this.penaltyTypeOptions.filter(option => !option.value || option.value === 'Academic');
        if (this.penaltyType !== 'Academic') {
            this.penaltyType = 'Academic';
        }
    }

    get penaltyTypeOptionList() {
        return this.filteredPenaltyTypeOptions.length > 0 ? this.filteredPenaltyTypeOptions : this.penaltyTypeOptions;
    }

    normalizePicklistLabel(fieldApiName, label) {
        const labelMap = {
            Chair_Decision__c: {
                'Case Accepted': 'Escalate to Case Accepted'
            },
            Committee_Decision__c: {
                'Case Accepted': 'Guilty',
                'Not Case Accepted': 'Not Guilty'
            },
            Dean_Decision__c: {
                'Modify': 'Return to Committee'
            },
            Dean_Appeal_Grounds__c: {
                'Other': 'Others'
            }
        };
        return (labelMap[fieldApiName] && labelMap[fieldApiName][label]) ? labelMap[fieldApiName][label] : label;
    }

    // â”€â”€ Save â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    handleSave() {
        this.submitted = true;
        this.errorMessage = '';

        // Validate native lightning-input / combobox / textarea fields (triggers built-in highlights)
        const allNativeValid = [...this.template.querySelectorAll('lightning-input, lightning-combobox, lightning-textarea')]
            .reduce((valid, cmp) => cmp.reportValidity() && valid, true);

        // Validate required custom lookup fields
        const lookupValid = !!this.pgid && !!this.programId && !!this.academicYearId;

        if (!allNativeValid || !lookupValid) {
            this.errorMessage = 'Please correct the highlighted errors before saving.';
            window.scrollTo({ top: 0, behavior: 'smooth' });
            return;
        }

        if (this.responseToCharges && !this.outcomeEmailDate) {
            this.errorMessage = 'Outcome Email Date is required when Response to Charges is provided.';
            window.scrollTo({ top: 0, behavior: 'smooth' });
            return;
        }

        this.isLoading = true;

        // If student not yet fetched (user skipped blur), fetch now
        const studentPromise = this.contactId
            ? Promise.resolve(null)
            : getProgramEnrollmentByPGID({ pgid: this.pgid });

        // Resolve chair contact from email (use cached Id if already looked up)
        const chairPromise = (this.hccChairISBEmail && !this.chairContactId)
            ? getContactByEmail({ email: this.hccChairISBEmail })
            : Promise.resolve(this.chairContactId ? { id: this.chairContactId, name: this.chairContactName } : null);

        Promise.all([studentPromise, chairPromise])
            .then(([enrollmentResult, chairResult]) => {
                const chairId = chairResult ? chairResult.id : null;
                if (enrollmentResult) {
                    this.enrollmentId  = enrollmentResult.enrollmentId  || '';
                    this.contactId     = enrollmentResult.contactId     || '';
                    this.studentName   = enrollmentResult.studentName   || '';
                    this.studentEmail  = enrollmentResult.studentEmail  || '';
                    this.studentMobile = enrollmentResult.studentMobile || '';
                    this.studentNameEditable = !enrollmentResult.studentName;
                    this.studentEmailEditable = !enrollmentResult.studentEmail;
                    this.studentMobileEditable = !enrollmentResult.studentMobile;
                }

                // Prevent opaque trigger failure by surfacing PGID issue before DML.
                if (!this.contactId && !this.enrollmentId) {
                    throw { body: { message: 'Incorrect PG ID. No student found with PG ID: ' + this.pgid } };
                }

                const data = {
                    pgid:                             this.pgid,
                    programId:                        this.programId,
                    academicYearId:                   this.academicYearId,
                    academicSessionId:                this.academicSessionId,
                    enrollmentId:                     this.enrollmentId,
                    contactId:                        this.contactId,
                    studentEmail:                     this.studentEmail,
                    studentMobile:                    this.studentMobile,
                    courseOfferingId:                 this.courseOfferingId,
                    currentReportingLocationId:       this.currentReportingLocationId,
                    reportedFaculty:                  this.reportedFacultyId,
                    caseReportedDate:                 this.caseReportedDate,
                    submissionDate:                   this.submissionDate,
                    violationType:                    this.violationType,
                    componentName:                    this.componentName,
                    turnitinSimilarity:               this.turnitinSimilarity,
                    initialEvidence:                  this.initialEvidence,
                    previousViolationFoundGuiltyDate: this.previousViolationFoundGuiltyDate,
                    hccChairISBEmail:                 this.hccChairISBEmail,
                    chairId:                          chairId || null,
                    chairDecision:                    this.chairDecision,
                    decisionReason:                   this.decisionReason,
                    responseDeadline:                 this.responseDeadline,
                    responseToCharges:                this.responseToCharges,
                    statementRequestDate:             this.statementRequestDate,
                    outcomeEmailDate:                 this.outcomeEmailDate,
                    hearingDate:                      this.hearingDate,
                    convenerEmail:                    this.convenerEmail,
                    emailIdsFacultyMembers:           this.emailIdsFacultyMembers,
                    emailIdsStudentMembers:           this.emailIdsStudentMembers,
                    emailSentToCommittee:             this.emailSentToCommittee,
                    hearingStatus:                    this.hearingStatus,
                    recordingUrl:                     this.recordingUrl,
                    hearingAttendance:                this.hearingAttendance,
                    voteResult:                       this.voteResult,
                    committeeDecision:                this.committeeDecision,
                    penaltyType:                      this.penaltyType,
                    penaltyDetails:                   this.penaltyDetails,
                    decisionNotificationDateToStudent:this.decisionNotificationDateToStudent,
                    finalCommunicationOutcome:        this.finalCommunicationOutcome,
                    deanAppealDate:                   this.deanAppealDate,
                    deanAppealGrounds:                this.deanAppealGrounds,
                    deanDecision:                     this.deanDecision,
                    finalPenalty:                     this.finalPenalty,
                    appealRemarks:                    this.appealRemarks,
                    caseClosedDate:                   this.caseClosedDate,
                    coursePenalty:                    this.coursePenalty,
                    penaltyEnforced:                  this.penaltyEnforced
                };
                return createHCCRecord({ data });
            })
            .then(recordId => {
                this.isLoading = false;
                // Navigate directly to the created record
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: recordId,
                        actionName: 'view'
                    }
                });
            })
            .catch(err => {
                this.errorMessage = this.extractErrorMessage(err);
                this.isLoading = false;
                window.scrollTo({ top: 0, behavior: 'smooth' });
            });
    }

    extractErrorMessage(err) {
        if (!err) {
            return 'Unable to save the record. Please try again.';
        }
        if (err.body) {
            if (typeof err.body.message === 'string' && err.body.message) {
                return err.body.message;
            }
            if (Array.isArray(err.body) && err.body.length > 0) {
                const messages = err.body
                    .map(e => (e && e.message ? e.message : ''))
                    .filter(Boolean);
                if (messages.length > 0) {
                    return messages.join(' | ');
                }
            }
            if (Array.isArray(err.body.pageErrors) && err.body.pageErrors.length > 0) {
                const msg = err.body.pageErrors[0].message;
                if (msg) {
                    return msg;
                }
            }
            if (Array.isArray(err.body.fieldErrors)) {
                const fieldErrorMsg = err.body.fieldErrors
                    .flatMap(e => (e && e.message ? [e.message] : []))
                    .join(' | ');
                if (fieldErrorMsg) {
                    return fieldErrorMsg;
                }
            }
        }
        if (err.message) {
            return err.message;
        }
        return String(err);
    }

    // â”€â”€ Cancel â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    handleCancel() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Honour_Code_Committee__c',
                actionName: 'list'
            }
        });
    }
}