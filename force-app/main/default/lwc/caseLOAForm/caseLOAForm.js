import { LightningElement, track, wire, api } from 'lwc';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { CurrentPageReference } from 'lightning/navigation';
import CASE_OBJECT from '@salesforce/schema/Case';
import getUserAccountContact from '@salesforce/apex/CaseLOAController.getUserAccountContact';
import getAcademicYears from '@salesforce/apex/CaseLOAController.getAcademicYears';
import getLocation from '@salesforce/apex/CaseLOAController.getLocation';
import getUserPrograms from '@salesforce/apex/CaseLOAController.getUserPrograms';
import getCompletedTerms from '@salesforce/apex/CaseLOAController.getCompletedTerms';
import getAcademicSessionsByProgram from '@salesforce/apex/CaseLOAController.getAcademicSessionsByProgram';
import getRejoinEligiblePrograms from '@salesforce/apex/CaseLOAController.getRejoinEligiblePrograms';
import createLOACase from '@salesforce/apex/CaseLOAController.createLOACase';
import saveFiles from '@salesforce/apex/CaseLOAController.saveFiles';
//prajwa;
import getUserAccountContactByEmail from '@salesforce/apex/CaseLOAController.getUserAccountContactByEmail';
import getUserProgramsByEmail from '@salesforce/apex/CaseLOAController.getUserProgramsByEmail';
import getContactCases from '@salesforce/apex/CaseLOAController.getContactCases';
//Prajwal
import getCaseFiles from '@salesforce/apex/CaseLOAController.getCaseFiles';
import downloadFile from '@salesforce/apex/CaseLOAController.downloadFile';
import getFilePreviewUrl from '@salesforce/apex/CaseLOAController.getFilePreviewUrl';
import getRecordTypes from '@salesforce/apex/CaseLOAController.getRecordTypes';
import getCaseDetails from '@salesforce/apex/CaseLOAController.getCaseDetails';
import getOwnerName from '@salesforce/apex/CaseLOAController.getOwnerName';
import getAcademicTermsForRejoin from '@salesforce/apex/CaseLOAController.getAcademicTermsForRejoin';
import validateStudentEnrollment from '@salesforce/apex/CaseLOAController.validateStudentEnrollment';
import validateExistingCases from '@salesforce/apex/CaseLOAController.validateExistingCases';
import validateGeneralSupportOpenCase from '@salesforce/apex/CaseLOAController.validateGeneralSupportOpenCase';
import USER_ID from '@salesforce/user/Id';
//prajwal
import isGuest from '@salesforce/user/isGuest';
//prajwal
import getCaseComments from '@salesforce/apex/CaseLOAController.getCaseComments';
import addCaseComment from '@salesforce/apex/CaseLOAController.addCaseComment';
import requiresTermsAndConditions from '@salesforce/apex/CaseLOAController.requiresTermsAndConditions';
import acceptTermsAndConditions from '@salesforce/apex/CaseLOAController.acceptTermsAndConditions';
import getUserCoursesByAcademicSessions from '@salesforce/apex/CaseLOAController.getUserCoursesByAcademicSessions';
import getSubTypeOptions from '@salesforce/apex/CaseLOAController.getSubTypeOptions';
import getSubCategoryOptions from '@salesforce/apex/CaseLOAController.getSubCategoryOptions';
import getReturnReplaceCases from '@salesforce/apex/CaseLOAController.getReturnReplaceCases';
import getReturnReplaceCourses from '@salesforce/apex/CaseLOAController.getReturnReplaceCourses';
// Add these imports
import requiresFinancialStatement from '@salesforce/apex/CaseLOAController.requiresFinancialStatement';
import acceptFinancialStatement from '@salesforce/apex/CaseLOAController.acceptFinancialStatement';
import getRejoinCases from '@salesforce/apex/CaseLOAController.getRejoinCases';
import getAttendanceExceptionSessions from '@salesforce/apex/CaseLOAController.getAttendanceExceptionSessions';
import getAttendanceExceptionCoursesBySession from '@salesforce/apex/CaseLOAController.getAttendanceExceptionCoursesBySession';
import getAttendanceExceptionReasonValues from '@salesforce/apex/CaseLOAController.getAttendanceExceptionReasonValues';
import validateTermOverlap from '@salesforce/apex/CaseLOAController.validateTermOverlap';
import validateOpenCaseByRecordType from '@salesforce/apex/CaseLOAController.validateOpenCaseByRecordType';
//Attendance Duplicacy check Sid - START
import checkDuplicateAttendanceException from '@salesforce/apex/CaseLOAController.checkDuplicateAttendanceException';
//Attendance Duplicacy check Sid - END
import isRejoinCasePresent from '@salesforce/apex/CaseLOAController.isRejoinCasePresent';
//Prajwal
import getContactDetails from '@salesforce/apex/GuestOtpAuthService.getContactDetails';
import getOpenCasesByEmail from '@salesforce/apex/CaseLOAController.getOpenCasesByEmail';
import getRejoinEligibleProgramsByEmail from '@salesforce/apex/CaseLOAController.getRejoinEligibleProgramsByEmail';
import getAcademicSessionsByProgramByEmail from '@salesforce/apex/CaseLOAController.getAcademicSessionsByProgramByEmail';
import getReturnReplaceCasesByEmail from '@salesforce/apex/CaseLOAController.getReturnReplaceCasesByEmail';
import getUserCoursesByAcademicSessionsByEmail from '@salesforce/apex/CaseLOAController.getUserCoursesByAcademicSessionsByEmail';
import getRejoinCasesByEmail from '@salesforce/apex/CaseLOAController.getRejoinCasesByEmail';
//Prajwal

const MAX_FILE_SIZE = 4500000;
const MIN_EVENT_DAYS = 15; // Configurable - minimum days before event

export default class CaseLOAForm extends NavigationMixin(LightningElement) {
    @track recordTypeOptions = [];
    @track selectedRecordTypeId = '';
    @track selectedRecordTypeLabel = '';
    @track selectedRecordTypeIcon = '';
    @track programName = '';
    @track showRecordTypeSelection = false;
    @track showForm = false;
    @track activeSections = ['contactInfo', 'requestDetails', 'attachDocuments', 'caseInfo', 'caseDocuments', 'termsConditions', 'actions'];
    @track showAttendanceExceptionFields = false;
    @track attendanceExceptionSessions = [];
    @track attendanceExceptionCourses = [];
    @track selectedSessionId = '';
    @track selectedSessionKey = '';
    @track selectedCourseId = '';
    @track extractedDateOfAbsence = '';
    @track sessionOptions = [];
    @track attendanceCourseOptions = [];
    @track attendanceExceptionReason = '';
    @track attendanceExceptionReasonOptions = [];
    @track noAttendanceSessions = false;
    @track showRejoinCaseSelection = false;
    @track rejoinCaseOptions = [];

    @track selectedRejoinCaseId = '';
    @track selectedRejoinCaseNumber = '';
    //sid
    @track showReturnReplaceCaseSelection = false;
    @track returnReplaceCaseOptions = [];
    @track selectedReturnReplaceCaseId = '';
    @track selectedReturnReplaceCaseNumber = '';
    @track selectedReturnReplaceCaseLOA = '';
    @track selectedReturnReplaceCaseProgram = '';
    @track selectedReturnReplaceCaseFromTerm = '';
    @track selectedReturnReplaceCaseToTerm = '';

    //sid
    @track showReturnReplaceCourses = false;
    @track returnReplaceCourseOptions = [];
    @track selectedReturnReplaceCourseId = '';
    @track isReturnReplace = false;
    @track showWellbeingFields = false;
    @track caseNumber = '';
    @track accountName = '';
    @track email = '';
    @track phone = '';
    @track contactPhone = '';
    @track contactMobile = '';
    @track ownerName = '';
    //@track contactId = '';
    @track accountId = '';
    //@track contactName = '';
    @track mailingStreet = '';
    @track mailingCity = '';
    @track mailingState = '';
    @track mailingPostalCode = '';
    @track mailingCountry = '';
    //@track academicSessionOptions = [];
    @track locationOptions = [];
    @track programOptions = [];
    @track academicSessionOptions = [];
    @track alternateEmail = '';
    @track alternatePhone = '';
    @track caseAlternateEmail = '';
    @track caseAlternatePhone = '';
    // Add these with your other @track properties
    @track severity = '';
    @track modeOfInteraction = '';
    @track typeField = '';
    @track actionTaken = '';
    @track caseSeverity = '';
    @track caseModeOfInteraction = '';
    @track caseTypeField = '';
    @track caseActionTaken = '';
    @track subject = '';

    get computedSubject() {
        let parts = [];
        if (this.contactName) parts.push(this.contactName);

        let rt = this.selectedRecordTypeLabel || this.caseRecordType;
        if (rt) parts.push(rt);

        let cnum = this.caseNumber || this.selectedRejoinCaseNumber || this.selectedReturnReplaceCaseNumber;
        if (cnum) parts.push(cnum);

        return parts.join(' - ');
    }
    @track description = '';
    @track pgid = '';
    @track academicYear = '';
    @track locationValue = '';
    @track program = '';
    @track fromTerm = '';
    @track toTerm = '';
    @track completedTerm = '';
    @track requestedEndDate = '';
    //prajwal
    @track currentAcademicTerm = '';
    @track showCaseList = false;
    @track contactCases = [];
    @track isCaseModalOpen = false;
    @track selectedCaseId = '';
    @track caseDetail = {};
    @track isOtpVerified = true; // Default to true for internal, or if set by parent for guest
    isGuest = isGuest; // Track if user is a guest
    //Prajwal

    @track uploadedFiles = [];
    @track caseFiles = [];
    @track showFilePreview = false;
    @track selectedFile = null;
    @track isLoading = false;
    @track caseId = '';
    @api recordId;

    // Guest user context passed from parent component (guestUserPortal)
    @api guestEmail;
    @api contactId = '';
    @api contactName = '';

    @track isRejoin = false;
    @track hasCompletedTerms = false;
    @track caseAcademicYear = '';
    @track caseProgram = '';
    @track caseFromTerm = '';
    @track caseToTerm = '';
    @track caseCompletedTerm = '';
    @track caseLocation = '';
    @track caseSubject = '';
    @track caseDescription = '';
    @track caseLoaType = '';
    @track caseComments = [];
    @track newCommentText = '';
    @track showCommentSection = false;
    @track requiresTermsAndConditions = false;
    @track termsAccepted = false;
    @track termsReason = '';
    @track showTermsSection = false;
    @track userCourses = [];
    @track filteredCourses = [];
    @track courseOptions = [];
    @track showSubTypeSelection = false;
    @track subTypeOptions = [];
    @track selectedSubType = '';
    @track showSubCategorySelection = false;
    @track subCategoryOptions = [];
    @track selectedSubCategory = '';
    @track isReadOnlyForSimpleSubTypes = false;
    @track hideLoaTypeForAcademicRecords = false;
    @track hideLoaTypeForLoaRecords = false;
    @track hideLoaTypeForVisaNoc = false;
    @track hideLoaTypeForGraduationWalk = false;
    @track hideTermsForAcademicRecords = false;
    @track hideTermsForVisaNoc = false;
    @track hideLoaTypeForWellbeing = false;
    @track hideAcademicSessionsForWellbeing = false;
    @track caseAccountHolderName = '';
    @track fromTermName = '';
    @track toTermName = '';
    // Also add this for new cases
    @track accountHolderName = '';
    @track hideSubjectAndDescriptionForNameChange = false;

    @track loaType;
    @track loaTypeOptions = [
        { label: 'Term Wise', value: 'TermWise' },
        { label: 'Full Year', value: 'Full Year' }
    ];

    @track showAcademicRecordsFields = false;
    @track documentType = '';
    @track deliveryMode = '';
    @track dispatchAddress = '';
    @track caseRecordType = '';
    @track caseSubType = '';
    @track caseShowAcademicRecordsFields = false;
    @track caseShowVisaNocFields = false;
    @track caseShowNameChangeFields = false;
    @track caseHideLoaType = false;
    @track caseHideSubjectAndDescription = false;

    documentTypeOptions = [
        { label: 'Transcript', value: 'Transcript' },
        { label: 'Dean’s', value: 'Dean’s' },
        { label: 'Scholar', value: 'Scholar' },
        { label: 'Merit', value: 'Merit' },
        { label: 'Certificate', value: 'Certificate' }
    ];

    @track showVisaNocFields = false;
    @track passportNumber = '';
    @track passportExpiry = '';
    @track travelStartDate = '';
    @track travelEndDate = '';
    @track visaType = '';
    @track visaPurpose = '';
    @track termValidationMessage = '';
    @track showTermValidation = false;
    @track overlappingCases = [];

    visaTypeOptions = [
        { label: 'Tourist', value: 'Tourist' },
        { label: 'Business', value: 'Business' },
        { label: 'Student', value: 'Student' },
        { label: 'Work', value: 'Work' },
        { label: 'Transit', value: 'Transit' }
    ];

    visaPurposeOptions = [
        { label: 'Vacation', value: 'Vacation' },
        { label: 'Conference', value: 'Conference' },
        { label: 'Study', value: 'Study' },
        { label: 'Employment', value: 'Employment' },
        { label: 'Family Visit', value: 'Family Visit' },
        { label: 'Medical Treatment', value: 'Medical Treatment' }
    ];
    @track caseAmount = 0;
    @track showAmountField = false;
    @track accountNumber = '';
    @track ifscCode = '';
    @track bankName = '';
    @track branchName = '';
    @track caseAccountNumber = '';
    @track caseIfscCode = '';
    @track caseBankName = '';
    @track caseBranchName = '';

    @track showNameChangeFields = false;
    @track programYear = '';
    @track requestedLegalName = '';
    @track nameChangeReason = '';
    @track caseDocumentType = '';
    @track caseDeliveryMode = '';
    @track caseDispatchAddress = '';
    @track casePassportNumber = '';
    @track casePassportExpiry = '';
    @track caseTravelStartDate = '';
    @track caseTravelEndDate = '';
    @track caseVisaType = '';
    @track caseVisaPurpose = '';
    @track caseRequestedLegalName = '';
    @track caseNameChangeReason = '';
    @track completedTermName = '';
    @track termsAndConditionsData = '';
    @track showTermsAndConditionsData = false;

    programYearOptions = [
        { label: '2024', value: '2024' },
        { label: '2025', value: '2025' },
        { label: '2026', value: '2026' },
        { label: '2027', value: '2027' },
        { label: '2028', value: '2028' }
    ];

    deliveryModeOptions = [
        { label: 'Digitary', value: 'Digitary' },
        { label: 'Print', value: 'Print' }
    ];

    // Event & Budget Proposal Fields
    @track showEventBudgetFields = false;
    @track eventTitle = '';
    @track eventProposedDateTime = '';
    @track eventVenue = '';
    @track eventHostBody = '';
    @track eventDescription = '';
    @track eventExpectedHeadcount = '';
    @track eventBudgetAsk = '';
    @track eventContacts = '';
    @track caseStatus = '';
    @track statusLabelMapping = {};
    @track caseStatusLabel = '';
    @track requiresFinancialStatement = false;
    @track showFinancialStatementSection = false;
    @track financialStatementAccepted = false;
    @track financialStatementRejected = false;
    @track financialStatementReason = '';
    @track selectedRejoinCaseLOA = '';
    @track selectedRejoinCaseProgram = '';
    @track selectedRejoinCaseFromTerm = '';
    @track selectedRejoinCaseToTerm = '';
    @track isFromRecordAlert = false;
    // OTP verification is now handled by parent component (guestUserPortal)
    // For internal/authenticated users, they don't need OTP verification
    // @track isOtpVerified = true; (Removed duplicate)
    @track showBankDetailsSection = false;
    @track showBankDetailsReadOnly = false;
    resultMessage = '';
    @track caseTermsCondition = false;
    @track wellbeingSeverity = '';
    @track wellbeingModeOfInteraction = '';
    @track wellbeingType = '';
    @track wellbeingActionTaken = '';

    @track caseRecordType;
    @track rejoinAmountPaid;
    @track caseType;

    wellbeingTypeOptions = [
        { label: 'Mental Health', value: 'Mental Health' },
        { label: 'Physical Health / Medical', value: 'Physical Health / Medical' },
        { label: 'Safety / Security Concern', value: 'Safety / Security Concern' },
        { label: 'Accessibility / Accommodation', value: 'Accessibility / Accommodation' },
        { label: 'Financial Hardship', value: 'Financial Hardship' },
        { label: 'Harassment / Misconduct / Bullying', value: 'Harassment / Misconduct / Bullying' },
        { label: 'Family / Personal Emergency', value: 'Family / Personal Emergency' },
        { label: 'Other', value: 'Other' }
    ];

    wellbeingSeverityOptions = [
        { label: 'Low', value: 'Low' },
        { label: 'Medium', value: 'Medium' },
        { label: 'High', value: 'High' }
    ];

    wellbeingModeOfInteractionOptions = [
        { label: 'In Person', value: 'In Person' },
        { label: 'Video call', value: 'Video call' },
        { label: 'Email', value: 'Email' },
        { label: 'Messaging', value: 'Messaging' },
        { label: 'Phone Call', value: 'Phone Call' }
    ];

    wellbeingActionTakenOptions = [
        { label: 'Wellbeing Counselling Scheduled', value: 'Wellbeing Counselling Scheduled' },
        //{ label: 'Guidance Provided', value: 'Guidance Provided' }
    ];
    currentUserId = USER_ID;
    eventHostBodyOptions = [
        { label: 'Council', value: 'Council' },
        { label: 'Club', value: 'Club' },
        { label: 'SIG', value: 'SIG' }
    ];
    @wire(CurrentPageReference)
    currentPageReference;

    @wire(getCompletedTerms, {
        contactId: '$contactId',
        programId: '$program'
    })
    wiredCompletedTerm({ error, data }) {
        if (data) {
            this.completedTermName = data;
            this.hasCompletedTerms = true;

        } else if (error) {
            console.error('Error loading completed term via wire:', error);
            this.completedTermName = '';
        }
    }

    @wire(getObjectInfo, { objectApiName: CASE_OBJECT })
    caseObjectInfo;

    /*handleOtpVerified(event) {
      this.isOtpVerified = true;
      if (event && event.detail) {
          this.currentUserId = event.detail;
          console.log('CaseLOAForm: Set currentUserId to ' + this.currentUserId);
      }
    }*/
    renderedCallback() {
        console.log('CaseLOAForm: renderedCallback executed');
        console.log('CaseLOAForm Visibility State:', {
            isOtpVerified: this.isOtpVerified,
            recordId: this.recordId,
            showRecordTypeSelection: this.showRecordTypeSelection,
            showForm: this.showForm,
            hasRecordTypes: this.hasRecordTypes, // Getter result
            recordTypeOptionsCount: this.recordTypeOptions ? this.recordTypeOptions.length : 0,
            currentUserId: this.currentUserId,
            contactId: this.contactId,
            email: this.email
        });
    }

    errorCallback(error, stack) {
        console.error('CaseLOAForm: Error detected', error);
        console.error('CaseLOAForm: Error stack', stack);
    }

    // handleVerified is no longer needed - OTP authentication is handled by parent component (guestUserPortal)
    /* async handleVerified(event) {
        console.log('CaseLOAForm: handleVerified called!');
        this.isOtpVerified = true;
        
        if (event && event.detail) {
            console.log('CaseLOAForm: Verified Event Detail:', JSON.stringify(event.detail));
            
            let email = null;
            if (typeof event.detail === 'object' && event.detail !== null) {
                email = event.detail.email;
            } else if (typeof event.detail === 'string') {
                email = event.detail;
            }

            if (email) {
                console.log('CaseLOAForm: SUCCESS - Email found for guest:', email);
                this.email = email;
                await this.initializeUserContext();
            } else {
                console.warn('CaseLOAForm: WARNING - Verified but no email found in event detail!');
            }
        }
    } */

    async initializeUserContext() {
        console.log('🔵 [UserContext] START initialization');
        console.log('🔵 [UserContext] Context flags - isGuest:', isGuest, 'recordId:', this.recordId, 'email:', this.email);

        this.isLoading = true;
        try {
            // 1. Load User/Contact Details
            console.log('🔵 [UserContext] STEP 1: Loading User/Account/Contact info...');
            const contactResult = await this.loadUserAccountContact();
            console.log('🔵 [UserContext] STEP 1 RESULT:', JSON.stringify(contactResult));

            // 2. Parallel data loads
            console.log('🔵 [UserContext] STEP 2: Dispatching parallel loads (Location, Programs, Rejoin)...');
            const promises = [
                this.loadLocation(),
                this.loadUserPrograms(),
                this.loadRejoinPrograms()
            ];

            if (this.contactId) {
                console.log('🔵 [UserContext] contactId available (' + this.contactId + '), loading sessions...');
                promises.push(this.loadAttendanceExceptionSessions());

                // Only load cases and show list for Guest Users (but NOT when a recordId is present — detail mode)
                if (!this.recordId && (this.isGuest || this.guestEmail)) {
                    console.log('Loading cases for guest user (list mode)...');
                    promises.push(this.loadContactCases());
                    this.showCaseList = true;
                } else if (!this.recordId) {
                    // Internal User w/o Record ID: Default to New Case Flow
                    console.log('Internal User: Defaulting to Record Type Selection');
                    this.showCaseList = false;
                    this.showRecordTypeSelection = true;
                }
            } else {
                console.warn('🟠 [UserContext] WARNING: No contactId found after Step 1. Data might be incomplete.');
            }

            const results = await Promise.all(promises);
            console.log('🔵 [UserContext] STEP 2 COMPLETE. All parallel promises resolved.');

            // Logic for visibility based on user type and state
            if (!this.recordId && (this.isGuest || this.guestEmail)) {
                // Guest user in list mode: show the case list
                console.log('Guest User (list mode) detected - showing case list');
                this.showCaseList = true;
                this.showRecordTypeSelection = false;
                await this.loadContactCases();
            } else if (this.recordId && (this.isGuest || this.guestEmail)) {
                // Guest user in detail mode (record-id passed from guestUserPortal)
                console.log('Guest User (detail mode) - showing existing case details inline');
                this.showCaseList = false;
                this.showRecordTypeSelection = false;
                this.isOtpVerified = true;
                this.isLoading = false;
            } else if (!this.recordId) {
                console.log('Authenticated User without RecordId - showing new request flow');
                this.showCaseList = false;
                this.showRecordTypeSelection = true;
                if (!this.recordTypeOptions || this.recordTypeOptions.length === 0) {
                    await this.loadRecordTypes();
                }
            } else {
                console.log('Authenticated User with RecordId - showing existing case details');
                this.showCaseList = false;
                this.showRecordTypeSelection = false;
                this.isOtpVerified = true;
                this.isLoading = false; // Stop spinner here to show record header
            }

            console.log('🔵 [UserContext] Final PGID:', this.pgid);
            console.log('🔵 [UserContext] Final Academic Year:', this.academicYear);
            console.log('🔵 [UserContext] COMPLETE');
        } catch (error) {
            console.error('🔴 [UserContext] ERROR during initialization:', error);
            console.error('🔴 [UserContext] Error Stack:', error.stack);
        } finally {
            this.isLoading = false;
        }
    }

    loadContactCases() {
        if (!this.contactId) return Promise.resolve();
        this.isLoading = true;
        return getContactCases({ contactId: this.contactId })
            .then(result => {
                this.contactCases = result;
                this.isLoading = false;
            })
            .catch(error => {
                console.error('Error loading contact cases:', error);
                this.isLoading = false;
            });
    }

    handleCaseClick(event) {
        const caseId = event.currentTarget.dataset.id;
        this.selectedCaseId = caseId;
//<!--new change Prajwal-->
        // For guest users: fire event to parent (guestUserPortal) to show full case detail inline
        if (this.isGuestUser) {
            console.log('CaseLOAForm: Guest user - dispatching showcasedetail event for caseId:', caseId);
            this.dispatchEvent(new CustomEvent('showcasedetail', {
                detail: { caseId: caseId },
                bubbles: true,
                composed: true
            }));
            return;
        }
//<!--new change Prajwal-->

        // For non-guest users: open the basic modal as before
        this.isLoading = true;
        // Reset files so stale files from a previous case don't show briefly
        this.caseFiles = [];
        getCaseDetails({ caseId: caseId })
            .then(result => {
                this.caseDetail = result;
                this.isCaseModalOpen = true;
                this.isLoading = false;
                // Load files for this case so they appear in the modal
                this.loadCaseFiles(caseId);
            })
            .catch(error => {
                console.error('Error loading case details:', error);
                this.isLoading = false;
            });
    }

    closeCaseModal() {
        this.isCaseModalOpen = false;
    }

    // Returns true when the viewed case is a Graduation Walk — Exception Petition sub type
    // Used to conditionally show From Term and To Term in the Case Detail modal
    // Uses case-insensitive includes() to avoid em-dash vs hyphen character mismatch
    get isGraduationWalkExceptionPetition() {
        const subType = this.caseDetail && this.caseDetail.Sub_Types__c;
        if (!subType) return false;
        console.log('[isGraduationWalkExceptionPetition] Sub_Types__c value:', JSON.stringify(subType));
        return subType.toLowerCase().includes('graduation walk');
    }

    // Returns true when the NEW CASE form should show From/To Term for Graduation Walk sub-type
    get isGraduationWalkSubType() {
        return this.selectedSubType &&
            this.selectedSubType.toLowerCase().includes('graduation walk');
    }

    handleNewRequest() {
        this.showCaseList = false;
        this.showRecordTypeSelection = true;
        if (!this.recordTypeOptions || this.recordTypeOptions.length === 0) {
            this.loadRecordTypes();
        }
    }

    handleBackToList() {
        this.showCaseList = true;
        this.showForm = false;
        this.showRecordTypeSelection = false;
        this.showSubTypeSelection = false;
        this.showRejoinCaseSelection = false;
        this.showReturnReplaceCaseSelection = false;
        this.loadContactCases();
    }

    navigateToCaseList() {
        console.log('navigateToCaseList called');
        console.log('isGuest:', this.isGuest);
        console.log('guestEmail:', this.guestEmail);
        console.log('contactId:', this.contactId);

        if (this.isGuest || this.guestEmail) {
            // For guest users: do a full page reload after case submission
            // This ensures OTP state, case list, and all component state are cleanly refreshed
            console.log('Guest context detected - reloading page after submission');
            if (typeof window !== 'undefined') {
                window.location.reload();
                return;
            }
            // Fallback if window is not available
            this.showCaseList = true;
            this.showForm = false;
            this.showRecordTypeSelection = false;
            this.showSubTypeSelection = false;
            this.showRejoinCaseSelection = false;
            this.showReturnReplaceCaseSelection = false;
            this.loadContactCases();

        } else if (this.contactId) {
            // --- AUTHENTICATED EXPERIENCE SITE STUDENTS ---
            // Navigate to the Experience Site Case list page after submission
            console.log('Authenticated Experience Site user - navigating to Case list page');
            this[NavigationMixin.Navigate]({
                type: 'standard__webPage',
                attributes: {
                    url: '/ISBStudentSuccessPortal/s/case/Case/Default'
                }
            });

        } else {
            // --- TRUE INTERNAL SALESFORCE USERS ---
            // No contactId, no guestEmail, not a guest → navigate to the case record page
            console.log('Internal Salesforce user detected - navigating to case record page, caseId:', this.caseId);
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: this.caseId,
                    objectApiName: 'Case',
                    actionName: 'view'
                }
            });
        }
    }
    //Sid

    navigateToCaseDetail(caseId) {
        if (!caseId) return;

        if (this.isGuestUser) {
            // Guest User: fire event to parent (guestUserPortal) to show full case detail inline
            console.log('CaseLOAForm: Guest user - dispatching showcasedetail event for caseId:', caseId);
            this.dispatchEvent(new CustomEvent('showcasedetail', {
                detail: { caseId: caseId },
                bubbles: true,
                composed: true
            }));
        } else {
            // For authenticated users (Students/Internal Users):
            // Navigate directly to the newly created case record page
            console.log('Navigating to Case record page:', caseId);
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: caseId,
                    objectApiName: 'Case',
                    actionName: 'view'
                }
            });
        }
    }

    connectedCallback() {

        this.loadUserAccountContact();
        this.loadLocation();
        this.loadRejoinPrograms()
        this.loadUserPrograms();

        console.log('Component connected, recordId:', this.recordId);
        console.log('CaseLOAForm: currentUserId (Initial):', this.currentUserId);
        console.log('CaseLOAForm: guestEmail from parent:', this.guestEmail);
        console.log('CaseLOAForm: contactId from parent:', this.contactId);

        // If guest user context is provided by parent, use it directly
        if (this.guestEmail) {
            console.log('Using guest user context from parent component');
            this.email = this.guestEmail;
            this.isOtpVerified = true;
            // contactId and contactName are already set via @api properties
            this.initializeUserContext();
        }
        // For non-guest users or when not called from parent
        else if (!this.isGuestUser || this.recordId) {
            this.initializeUserContext();
        }

        this.loadStatusLabelMapping();
        this.checkURLParameters();

        if (this.recordId) {
            console.log('RecordId exists, loading case details');
            this.showRecordTypeSelection = false;
            this.checkForExistingCase();
            this.checkFinancialStatement();
            setTimeout(() => {
                this.checkTermsAndConditions();
            }, 1000);
        } else {
            console.log('No recordId, loading record types');
            this.loadRecordTypes();
        }
    }

    checkURLParameters() {
        if (typeof window !== 'undefined') {
            const urlParams = new URLSearchParams(window.location.search);
            const recordId = urlParams.get('recordId');
            const source = urlParams.get('source');

            if (recordId && !this.recordId) {
                this.recordId = recordId;
                console.log('RecordId from URL:', this.recordId);
            }

            if (source === 'recordAlert') {
                this.isFromRecordAlert = true;
                console.log('Source from URL: recordAlert');
            }
        }
    }


    checkNavigationSource() {
        if (this.currentPageReference) {
            const source = this.currentPageReference.state?.source;
            const fromRecordAlert = this.currentPageReference.state?.fromRecordAlert;

            if (source === 'recordAlert' || fromRecordAlert === 'true') {
                this.isFromRecordAlert = true;
                console.log('Navigating from Record Alerts - showing existing case view only');
            }
        }
    }

    @wire(CurrentPageReference)
    currentPageReferenceWire(pageRef) {
        if (pageRef) {
            console.log('Page reference received:', pageRef);

            const recordId = pageRef.state?.c__recordId ||
                pageRef.state?.recordId ||
                pageRef.state?.id ||
                pageRef.attributes?.recordId ||
                pageRef.attributes?.id;

            if (recordId && recordId !== this.recordId) {
                this.recordId = recordId;
                console.log('RecordId from navigation:', this.recordId);
            }

            const source = pageRef.state?.source;
            const fromRecordAlert = pageRef.state?.fromRecordAlert;

            if (source === 'recordAlert' || fromRecordAlert === 'true') {
                this.isFromRecordAlert = true;
                console.log('Navigating from Record Alerts - showing existing case view only');
            }

            if (this.recordId) {
                this.showRecordTypeSelection = false;
                this.checkForExistingCase();
            }
        }
    }

    async loadRecordTypes() {
        try {
            console.log('Loading record types...');
            const recordTypes = await getRecordTypes();
            console.log('Record types loaded:', recordTypes);

            this.recordTypeOptions = recordTypes.map(rt => {
                let icon = 'standard:case';

                if (rt.Name.toLowerCase().includes('medical')) {
                    icon = 'standard:healthcare';
                } else if (rt.Name.toLowerCase().includes('academic')) {
                    icon = 'standard:education';
                } else if (rt.Name.toLowerCase().includes('personal')) {
                    icon = 'standard:user';
                } else if (rt.Name.toLowerCase().includes('emergency')) {
                    icon = 'standard:emergency';
                } else if (rt.Name.toLowerCase().includes('rejoin')) {
                    icon = 'standard:recurring_exception';
                } else if (rt.Name.toLowerCase().includes('general support') || rt.Name.toLowerCase().includes('general')) {
                    icon = 'standard:service_request';
                } else if (rt.Name.toLowerCase().includes('event') || rt.Name.toLowerCase().includes('budget')) {
                    icon = 'standard:event';
                }

                return {
                    label: rt.Name,
                    value: rt.Id
                };
            });

            console.log('Processed record type options:', + JSON.stringify(this.recordTypeOptions));
            console.log('isFromRecordAlert:', this.isFromRecordAlert);

            if (!this.isFromRecordAlert && !this.recordId) {
                this.showRecordTypeSelection = true;
                console.log('Showing record type selection');
            } else {
                this.showRecordTypeSelection = false;
                console.log('Skipping record type selection');
            }
        } catch (error) {
            console.error('Error loading record types:', error);
            this.showToast('Error', 'Failed to load request types', 'error');
            this.showRecordTypeSelection = false;
        }
    }
    async loadRejoinPrograms() {
        try {
            let result;
            if (this.email) {
                console.log('Using getRejoinEligibleProgramsByEmail with email:', this.email);
                result = await getRejoinEligibleProgramsByEmail({ email: this.email });
            } else {
                console.log('Using standard getRejoinEligiblePrograms');
                result = await getRejoinEligiblePrograms();
            }

            if (result && result.length > 0) {
                this.programOptions = result.map(program => ({
                    label: program.name,
                    value: program.id
                }));
                this.program = result[0].id;
                this.programName = result[0].name;
            } else {
                // ORIGINAL CODE (Commented out):
                // this.showToast('Info', 'No eligible programs found for Rejoin. You must have an active Leave of Absence to rejoin.', 'info');

                // NEW CODE:
                if (!this.isGuestUser) {
                    this.showToast('Info', 'No eligible programs found for Rejoin. You must have an active Leave of Absence to rejoin.', 'info');
                }
                this.programOptions = [];
            }
        } catch (error) {
            // ORIGINAL CODE (Commented out):
            // this.showToast('Error', 'Error loading rejoin programs: ' + error.body?.message, 'error');

            // NEW CODE:
            if (!this.isGuestUser) {
                this.showToast('Error', 'Error loading rejoin programs: ' + error.body?.message, 'error');
            }
        }
    }
    get hasRecordTypes() {
        return this.recordTypeOptions && this.recordTypeOptions.length > 0;
    }

    get showBackToListButton() {
        // Only show 'Back to List' if the list is actually accessible (i.e. for Guests)
        return this.isGuestUser;
    }

    get isGuestUser() {
        return this.isGuest || !!this.guestEmail;
    }

    get showRejoinPaymentButton() {
        console.log('this.caseType ', this.caseType);
        console.log('this.rejoinAmountPaid ', this.rejoinAmountPaid);
        return this.caseType === 'Rejoin' && this.rejoinAmountPaid === false && this.caseStatus === 'Finance Statement Accepted';
    }


    async loadStatusLabelMapping() {
        try {
            // Get dynamic mapping from Apex
            const result = await getStatusLabelMapping();
            this.statusLabelMapping = result;

            // Ensure specific mappings
            this.statusLabelMapping['Approved11'] = 'Approved-Pending T&C';
            this.statusLabelMapping['Approved-Pending T&C'] = 'Approved-Pending T&C';

            console.log('Status mapping loaded:', this.statusLabelMapping);

            // Update current status label if case is loaded
            if (this.caseStatus) {
                //this.caseStatusLabel = this.statusLabelMapping[this.caseStatus] || this.caseStatus;
                this.caseStatusLabel = this._computeStatusLabel(this.caseStatus);
            }
        } catch (error) {
            console.error('Error loading status label mapping:', error);
            // Fallback hardcoded mapping
            this.statusLabelMapping = {
                'Draft': 'Draft',
                'Submitted': 'Submitted',
                'In Progress': 'In Progress',
                'Approved': 'Approved',
                'Approved11': 'Approved-Pending T&C',
                'T&C Accepted': 'T&C Accepted',
                'T & C Rejected': 'T & C Rejected',
                'Closed': 'Closed',
                'Rejected': 'Rejected',
                'Finance Statement Accepted': 'Finance Statement Accepted',
                'Finance Statement Rejected': 'Finance Statement Rejected'
            };
        }
    }
    get isFeeExceptionCase() {
        return this.selectedRecordTypeLabel &&
            this.selectedRecordTypeLabel.toLowerCase().includes('general support') &&
            this.selectedSubType &&
            this.selectedSubType.toLowerCase().includes('fee exception');
    }

    // Used in the existing case view (recordId path) where selectedRecordTypeLabel/selectedSubType are not set
    get isExistingFeeExceptionCase() {
        return this.caseRecordType &&
            this.caseRecordType.toLowerCase().includes('general support') &&
            this.caseSubType &&
            this.caseSubType.toLowerCase().includes('fee exception');
    }

    async handleRecordTypeChange(event) {
        const recordTypeId = event.detail.value;
        console.log('Record type selected:', recordTypeId);

        if (recordTypeId) {
            const selectedRecordType = this.recordTypeOptions.find(
                rt => rt.value === recordTypeId
            );

            if (selectedRecordType) {
                this.selectedRecordTypeId = recordTypeId;
                this.selectedRecordTypeLabel = selectedRecordType.label;
                this.isReturnReplace = this.selectedRecordTypeLabel.toLowerCase().includes('return and replace') ||
                    this.selectedRecordTypeLabel.toLowerCase().includes('return & replace');

                // ✅ ADD THIS: Check for Attendance Exception
                const isAttendanceException = this.selectedRecordTypeLabel.toLowerCase().includes('attendance');
                console.log('attendance ', isAttendanceException);
                if (isAttendanceException) {
                    // Load attendance exception data
                    await this.loadAttendanceExceptionSessions();
                    console.log('loadAttendanceExceptionSessions called');
                    await this.loadAttendanceExceptionReasonPicklist();
                    this.showAttendanceExceptionFields = true;
                    console.log('attendance ', this.showAttendanceExceptionFields);
                    this.showRecordTypeSelection = false;
                    this.showForm = true;
                    this.showToast('Success', `Selected: ${this.selectedRecordTypeLabel}`, 'success');
                    return;
                }

                if (this.selectedRecordTypeLabel.toLowerCase().includes('withdrawal') ||
                    this.selectedRecordTypeLabel.toLowerCase().includes('withdraw')) {
                    this.loaType = '';
                }

                console.log('Selected record type:', this.selectedRecordTypeLabel);

                const isGeneralSupport = this.selectedRecordTypeLabel.toLowerCase().includes('general support') ||
                    this.selectedRecordTypeLabel.toLowerCase().includes('general');

                const isEventBudget = this.selectedRecordTypeLabel.toLowerCase().includes('event') ||
                    this.selectedRecordTypeLabel.toLowerCase().includes('budget');

                this.isRejoin = this.selectedRecordTypeLabel.toLowerCase().includes('rejoin');
                console.log('Is Rejoin type:', this.isRejoin);

                if (this.isRejoin) {
                    this.loaType = '';
                }

                this.showRecordTypeSelection = false;

                // Reset all field visibility flags
                this.showAcademicRecordsFields = false;
                this.showVisaNocFields = false;
                this.showNameChangeFields = false;
                this.showEventBudgetFields = false;

                if (this.isReturnReplace) {
                    // Directly show form for Return and Replace
                    this.showForm = true;
                    // Load programs to ensure this.program is set
                    //sid
                    await this.loadRejoinPrograms();
                    //sid
                    // Load cohorts for Return and Replace
                    await this.loadCohortsForReturnReplace();
                    // Load courses for Return and Replace
                    this.loadReturnReplaceCourses();
                    // Don't show LOA Type
                    this.loaType = '';
                    // Hide academic session fields
                    this.showAcademicSessionFields = false;

                } else if (isGeneralSupport) {
                    await this.loadSubTypeOptions();
                    this.showSubTypeSelection = true;
                } else if (this.isRejoin) {
                    // ✅ FIX: Load rejoin cases and show selection screen
                    await this.loadRejoinCases();  // Add this line
                    this.showRejoinCaseSelection = true;  // Show the rejoin case selection screen
                    this.showForm = false;  // Don't show form yet
                    // Don't show LOA Type for Rejoin
                    this.loaType = '';
                    // Don't load cohorts yet - wait for case selection
                } else if (isEventBudget) {
                    // Directly show form for Event & Budget
                    this.showForm = true;
                    this.showEventBudgetFields = true;
                    // Clear fields that shouldn't be shown for Event & Budget
                    this.loaType = '';
                    this.fromTerm = '';
                    this.toTerm = '';
                } else {
                    // Directly show form for other types
                    this.showForm = true;
                }

                this.showToast('Success', `Selected: ${this.selectedRecordTypeLabel}`, 'success');
            }
        }
    }

    async loadCohortsForReturnReplace() {
        if (!this.program) {
            console.log('Program not selected for Return and Replace');
            return;
        }

        this.isLoading = true;
        try {
            const cohorts = await getAcademicTermsForRejoin({
                programId: this.program
            });

            this.cohortOptions = cohorts.map(cohort => ({
                label: `${cohort.name} (${cohort.formattedDateRange})`,
                value: cohort.id,
                cohortName: cohort.name
            }));

            console.log('Cohorts loaded for Return and Replace:', this.cohortOptions);

            /*if (this.cohortOptions.length === 0) {
                this.showToast('Info', 'No upcoming cohorts available for Return and Replace. Please contact support.', 'info');
            }*/

        } catch (error) {
            console.error('Error loading cohorts for Return and Replace:', error);
            this.showToast('Error', 'Failed to load cohorts for Return and Replace', 'error');
            this.cohortOptions = [];
        } finally {
            this.isLoading = false;
        }
    }

    async loadCohortsForRejoin() {
        if (!this.program) {
            console.log('Program not selected for Rejoin');
            return;
        }

        this.isLoading = true;
        try {
            const cohorts = await getAcademicTermsForRejoin({
                programId: this.program
            });

            this.cohortOptions = cohorts.map(cohort => ({
                label: `${cohort.name} (${cohort.formattedDateRange})`,
                value: cohort.id,
                cohortName: cohort.name
            }));

            console.log('Cohorts loaded for Rejoin:', this.cohortOptions);

            if (this.cohortOptions.length === 0) {
                this.showToast('Info', 'No upcoming cohorts available for Rejoin. Please contact support.', 'info');
            }

        } catch (error) {
            console.error('Error loading cohorts for Rejoin:', error);
            this.showToast('Error', 'Failed to load cohorts for Rejoin', 'error');
            this.cohortOptions = [];
        } finally {
            this.isLoading = false;
        }
    }


    async loadAttendanceExceptionSessions() {
        this.isLoading = true;
        try {
            console.log('=== LOADING ATTENDANCE SESSIONS START ===');
            console.log('Loading attendance sessions for contact:', this.contactId);

            const sessions = await getAttendanceExceptionSessions({
                contactId: this.contactId
            });

            console.log('Sessions returned from Apex:', sessions);
            console.log('Number of sessions:', sessions ? sessions.length : 0);

            this.attendanceExceptionSessions = sessions;

            // Build session options for dropdown
            this.sessionOptions = sessions.map(session => ({
                label: `${session.sessionKey}`, // Include course name
                value: session.sessionId,
                sessionKey: session.sessionKey,
                courseName: session.courseName,
                dateOfSession: session.dateOfSession,
                timeOfSession: session.timeOfSession,
                courseAttendanceId: session.courseAttendanceId
            }));

            console.log('Attendance sessions loaded:', this.attendanceExceptionSessions);
            console.log('Session options created:', this.sessionOptions);

            if (!this.program && this.programOptions && this.programOptions.length > 0) {
                // Set the first program as default
                this.program = this.programOptions[0].value;
                this.programName = this.programOptions[0].label;
                console.log('Default program set:', this.program);
            }

            if (sessions.length === 0) {
                this.noAttendanceSessions = true;

                // ORIGINAL CODE (Commented out):
                // this.showToast('Info', 'No sessions found for your enrolled courses. Please ensure you are enrolled in courses for the current term.', 'info');

                // NEW CODE:
                if (!this.isGuestUser) {
                    this.showToast('Info', 'No sessions found for your enrolled courses. Please ensure you are enrolled in courses for the current term.', 'info');
                }
            } else {
                this.noAttendanceSessions = false;
                console.log('✅ Sessions loaded successfully');
            }

            console.log('=== LOADING ATTENDANCE SESSIONS END ===');

        } catch (error) {
            console.error('=== ERROR LOADING ATTENDANCE SESSIONS ===');

            // ORIGINAL CODE (Commented out):
            // this.showToast('Error', 'Failed to load attendance sessions: ' + (error.body?.message || error.message), 'error');

            // NEW CODE:
            if (!this.isGuestUser) {
                this.showToast('Error', 'Failed to load attendance sessions: ' + (error.body?.message || error.message), 'error');
            }
            this.sessionOptions = [];
            this.noAttendanceSessions = true;
        } finally {
            this.isLoading = false;
        }
    }


    async loadAttendanceExceptionReasonPicklist() {
        try {
            const result = await getAttendanceExceptionReasonValues();
            console.log('Attendance Exception Reason Values:', result);

            this.attendanceExceptionReasonOptions = result.map(item => ({
                label: item.label,
                value: item.value
            }));
        } catch (error) {
            console.error('Error loading attendance exception reason values:', error);
            this.showToast('Error', 'Error loading reason values: ' + error.body?.message || error.message, 'error');
        }
    }
    //Sid
    async loadReturnReplaceCases() {
        this.isLoading = true;
        try {
            let cases;
            if (this.email) {
                console.log('Using getReturnReplaceCasesByEmail with email:', this.email);
                cases = await getReturnReplaceCasesByEmail({ email: this.email });
            } else {
                console.log('Using standard getReturnReplaceCases');
                cases = await getReturnReplaceCases();
            }

            console.log('Return and Replace cases fetched:', cases);

            this.returnReplaceCaseOptions = cases.map(c => ({
                label: `${c.displayLabel} (Case: ${c.caseNumber})`,
                value: c.caseId,
                caseNumber: c.caseNumber,
                loaType: c.loaType,
                programName: c.programName,
                fromTerm: c.fromTerm,
                toTerm: c.toTerm
            }));

            if (this.returnReplaceCaseOptions.length === 0) {
                this.showToast('Info', 'No eligible cases found for Return and Replace', 'info');
            }
        } catch (error) {
            console.error('Error loading return and replace cases:', error);
            this.showToast('Error', 'Failed to load eligible cases for Return and Replace', 'error');
            this.returnReplaceCaseOptions = [];
        } finally {
            this.isLoading = false;
        }
    }


    handleReturnReplaceCaseSelect(event) {
        this.selectedReturnReplaceCaseId = event.detail.value;
        const selectedCase = this.returnReplaceCaseOptions.find(c => c.value === this.selectedReturnReplaceCaseId);
        if (selectedCase) {
            this.selectedReturnReplaceCaseNumber = selectedCase.caseNumber;
            this.selectedReturnReplaceCaseLOA = selectedCase.loaType;
            this.selectedReturnReplaceCaseProgram = selectedCase.programName;
            this.selectedReturnReplaceCaseFromTerm = selectedCase.fromTerm;
            this.selectedReturnReplaceCaseToTerm = selectedCase.toTerm;
            console.log('Selected Return and Replace Case:', selectedCase.label);

            // Load courses for the selected program
            this.loadReturnReplaceCourses();
        }
    }
    //SId NEW Code
    handleReturnReplaceCaseConfirm() {
        if (!this.selectedReturnReplaceCaseId) {
            this.showToast('Warning', 'Please select a case to continue', 'warning');
            return;
        }

        this.showReturnReplaceCaseSelection = false;
        this.showForm = true;
        console.log('this.program', this.program);

        if (this.program) {
            this.loadCohortsForReturnReplace();
        }

        // Ensure courses are loaded
        this.loadReturnReplaceCourses();
    }

    get hasReturnReplaceCaseOptions() {
        return this.returnReplaceCaseOptions && this.returnReplaceCaseOptions.length > 0;
    }

    get isReturnReplaceCaseSelected() {
        return !!this.selectedReturnReplaceCaseId;
    }
    //Sid NEW Code
    //Sid
    // Add this method to load courses for Return and Replace
    // Update the existing loadReturnReplaceCourses method:
    async loadReturnReplaceCourses() {
        if (!this.contactId || !this.program) {
            return;
        }

        this.isLoading = true;
        try {
            const courses = await getReturnReplaceCourses({
                contactId: this.contactId,
                programId: this.program
            });

            this.returnReplaceCourseOptions = courses.map(course => ({
                label: course.courseName,
                value: course.courseId,
                academicSessionName: course.academicSessionName
            }));

            console.log('Return and Replace courses loaded:', this.returnReplaceCourseOptions);

            if (this.returnReplaceCourseOptions.length === 0) {
                this.showToast('Info', 'No courses found for your enrollment', 'info');
            }
        } catch (error) {
            console.error('Error loading return and replace courses:', error);
            this.showToast('Error', 'Failed to load courses', 'error');
            this.returnReplaceCourseOptions = [];
        } finally {
            this.isLoading = false;
        }
    }

    // Add this method to handle course selection
    handleReturnReplaceCourseSelect(event) {
        this.selectedReturnReplaceCourseId = event.detail.value;
    }

    get shouldShowBankDetails() {
        return this.showBankDetailsSection;
    }

    handleSessionChange(event) {
        this.selectedSessionId = event.detail.value;

        // Find selected session to get all details
        const selectedSession = this.sessionOptions.find(
            session => session.value === this.selectedSessionId
        );

        if (selectedSession) {
            this.selectedSessionKey = selectedSession.sessionKey;

            // Auto-populate course name and ID from the selected session
            this.selectedCourseName = selectedSession.courseName;
            this.selectedCourseId = selectedSession.courseAttendanceId;

            console.log('Auto-populated Course:', {
                name: this.selectedCourseName,
                id: this.selectedCourseId
            });

            this.selectedSessionDate = selectedSession.dateOfSession;
            this.selectedSessionTime = selectedSession.timeOfSession;

            // Extract date from session key
            this.extractDateFromSessionKey(selectedSession.sessionKey);

            // No need to load courses based on session separately as it's now linked to the session directly
            // this.loadCoursesForSession();
        } else {
            this.selectedSessionKey = '';
            this.selectedCourseName = '';
            this.selectedCourseId = '';
            this.selectedSessionDate = '';
            this.selectedSessionTime = '';
            this.extractedDateOfAbsence = '';
            this.attendanceCourseOptions = [];
        }
    }



    extractDateFromSessionKey(sessionKey) {
        if (!sessionKey) {
            this.extractedDateOfAbsence = '';
            return;
        }

        try {
            // Split by pipe delimiter and get first part (date)
            // Format: "2025-07-01 | | A | | 10:00 AM"
            const parts = sessionKey.split('||');
            if (parts.length > 0) {
                const datePart = parts[0].trim();
                this.extractedDateOfAbsence = datePart;
                console.log('Extracted date of absence:', this.extractedDateOfAbsence);
            }
        } catch (error) {
            console.error('Error extracting date from session key:', error);
            this.extractedDateOfAbsence = '';
        }
    }

    handleAttendanceReasonChange(event) {
        this.attendanceExceptionReason = event.detail.value;
    }

    validateAttendanceExceptionDate() {
        if (!this.extractedDateOfAbsence || !this.attendanceExceptionReason) {
            return null;
        }

        console.log('extractedDateOfAbsence raw value:', this.extractedDateOfAbsence);

        // OLD LOGIC - COMMENTED OUT (Simple date parsing that fails with certain formats)
        // const absenceDate = new Date(this.extractedDateOfAbsence);

        // NEW LOGIC - Parse the date string properly - handle YYYY-MM-DD format
        const dateParts = this.extractedDateOfAbsence.trim().split('-');
        let absenceDate;

        if (dateParts.length === 3) {
            // Parse as YYYY-MM-DD format
            const year = parseInt(dateParts[0], 10);
            const month = parseInt(dateParts[1], 10) - 1; // Month is 0-indexed
            const day = parseInt(dateParts[2], 10);
            absenceDate = new Date(year, month, day, 0, 0, 0, 0);
        } else {
            absenceDate = new Date(this.extractedDateOfAbsence);
        }

        const currentDate = new Date();

        // Reset time to start of day for date comparison
        absenceDate.setHours(0, 0, 0, 0);
        currentDate.setHours(0, 0, 0, 0);

        // Calculate difference in milliseconds
        const timeDiff = currentDate - absenceDate;
        console.log('Time difference (ms):', timeDiff, 'currentDate:', currentDate, 'absenceDate:', absenceDate);
        const hoursDiff = timeDiff / (1000 * 60 * 60);
        console.log('Hours difference:', hoursDiff);
        const daysDiff = Math.floor(timeDiff / (1000 * 60 * 60 * 24));
        console.log('Days difference:', daysDiff);

        // Reasons that require submission within 72 hours
        const urgentReasons = [
            'Medical Exigency',
            'Medical Emergency in Immediate Family',
            'Loss/Bereavement',
            'Hardship/Trauma'
        ];

        // Reasons that require submission within 7 working days
        const standardReasons = [
            'Approved Case Competitions',
            'Professional Certification Exams',
            'National/International Sports Tournaments'
        ];

        const reasonLower = this.attendanceExceptionReason.toLowerCase();
        const isUrgentReason = urgentReasons.some(reason =>
            reasonLower.includes(reason.toLowerCase())
        );
        const isStandardReason = standardReasons.some(reason =>
            reasonLower.includes(reason.toLowerCase())
        );

        if (isUrgentReason) {
            // Check if more than 72 hours have passed
            console.log('isUrgentReason:', isUrgentReason);
            if (hoursDiff > 72) {
                return `For "${this.attendanceExceptionReason}", the exception must be raised within 72 hours from the date of absence. The absence date is more than 72 hours ago. Please contact support for assistance.`;
            }
        } else if (isStandardReason) {
            // OLD LOGIC - COMMENTED OUT
            // Check if more than 7 working days have passed
            // For simplicity, we'll count calendar days (you can enhance to exclude weekends)
            // if (daysDiff > 7) {
            //     return `For "${this.attendanceExceptionReason}", the exception must be raised within 7 working days from the date of absence. The absence date is more than 7 days ago. Please contact support for assistance.`;
            // }

            // NEW LOGIC - Check if absence date is in the future and at least 7 days in advance
            console.log('isStandardReason:', isStandardReason);
            if (daysDiff >= 0) {
                // Absence date is in the past or today
                return `For "${this.attendanceExceptionReason}", the absence date must be in the future. Please select an upcoming absence date.`;
            } else if (Math.abs(daysDiff) < 7) {
                // Absence date is less than 7 days in advance
                return `For "${this.attendanceExceptionReason}", the exception must be raised at least 7 days in advance. The absence date must be more than 7 days from today.`;
            }

        }

        return null; // No validation error
    }

    async checkFinancialStatement() {
        if (this.recordId && !this.isCaseClosed) {
            try {
                console.log('=== Checking financial statement for case:', this.recordId);

                // Directly call the imported Apex method
                this.requiresFinancialStatement = await requiresFinancialStatement({
                    caseId: this.recordId
                });

                console.log('requiresFinancialStatement result:', this.requiresFinancialStatement);
                console.log('Current case status from details:', this.caseStatus);

                this.showFinancialStatementSection = this.requiresFinancialStatement;

                if (this.showFinancialStatementSection) {
                    this.financialStatementAccepted = false;
                    this.financialStatementRejected = false;
                    this.financialStatementReason = '';
                    console.log('Financial statement section should be VISIBLE');
                } else {
                    console.log('Financial statement section should be HIDDEN');
                }

            } catch (error) {
                console.error('Error checking financial statement:', error);
                console.error('Error details:', error.body?.message || error.message);
                this.showFinancialStatementSection = false;
            }
        } else {
            console.log('No recordId available or case is closed for financial statement check');
            this.showFinancialStatementSection = false;
        }
    }
    handleFinancialStatementAcceptChange(event) {
        this.financialStatementAccepted = event.target.checked;
        if (this.financialStatementAccepted) {
            this.financialStatementRejected = false;
            this.financialStatementReason = '';
        }
    }

    handleFinancialStatementRejectChange(event) {
        this.financialStatementRejected = event.target.checked;
        if (this.financialStatementRejected) {
            this.financialStatementAccepted = false;
        }
    }

    handleFinancialStatementReasonChange(event) {
        this.financialStatementReason = event.target.value;
    }
    // Replace the existing financial statement checkbox handlers with this single handler
    // Replace the existing checkbox handlers with this radio button handler
    handleFinancialStatementResponseChange(event) {
        const value = event.target.value;

        // Reset both values
        this.financialStatementAccepted = false;
        this.financialStatementRejected = false;

        // Set the selected value
        if (value === 'accepted') {
            this.financialStatementAccepted = true;
            this.financialStatementReason = ''; // Clear reason if accepting
        } else if (value === 'rejected') {
            this.financialStatementRejected = true;
        }

        console.log('Financial Statement Response:', {
            accepted: this.financialStatementAccepted,
            rejected: this.financialStatementRejected,
            reason: this.financialStatementReason
        });
    }

    // Keep this method
    handleFinancialStatementReasonChange(event) {
        this.financialStatementReason = event.target.value;
    }

    // Remove the handleFinancialStatementSubmit method completely
    // We'll handle it in the main handleSubmit method

    loadUserPrograms() {
        console.log('Loading programs for:', { email: this.email, contactId: this.contactId });

        let programPromise;
        if (this.email) {
            console.log('Using getUserProgramsByEmail');
            programPromise = getUserProgramsByEmail({ email: this.email });
        } else {
            console.log('Using getUserPrograms (standard)');
            programPromise = getUserPrograms();
        }

        return programPromise
            .then(result => {
                console.log('DEBUG - Programs loaded from Apex:', JSON.stringify(result));
                if (result && result.length > 0) {
                    this.programOptions = result.map(program => ({
                        label: program.name,
                        value: program.id,
                        // debug info
                        programId: program.programId,
                        term: program.academicTermName
                    }));

                    if (result.length === 1) {
                        this.program = result[0].id;
                        this.programName = result[0].name;
                        if (this.isLOARecordType || this.isExistingLOARecordType) {
                            if (this.programName === 'Post Graduate Programme in Management' ||
                                this.programName === 'Post Graduate Programme in Management for Young Leaders') {
                                this.loaType = 'None';
                            }
                        }
                        this.loadAcademicSessions();
                    } else if (result.length > 1) {
                        this.program = result[0].id;
                        this.programName = result[0].name;
                        if (this.isLOARecordType || this.isExistingLOARecordType) {
                            if (this.programName === 'Post Graduate Programme in Management' ||
                                this.programName === 'Post Graduate Programme in Management for Young Leaders') {
                                this.loaType = 'None';
                            }
                        }
                        this.loadAcademicSessions();
                    }
                } else {
                    console.log('No programs found');
                }
            })
            .catch(error => {
                console.error('Error loading programs:', error);
                this.resultMessage = 'Error loading programs: ' + (error.body ? error.body.message : error.message);
            });
    }

    async loadSubTypeOptions() {
        try {
            const subTypes = await getSubTypeOptions({
                recordTypeId: this.selectedRecordTypeId
            });

            // For General Support, students should only be able to raise requests
            // under the "Academic" sub type. Filtering here instead of deactivating
            // the picklist globally to avoid impacting other profiles/record types
            // that share the same Case.Sub_Types__c picklist.
            const isGeneralSupport = this.selectedRecordTypeLabel &&
                this.selectedRecordTypeLabel.toLowerCase().includes('general support');

            this.subTypeOptions = subTypes
                .filter(st => !isGeneralSupport || st.label === 'Academic')
                .map(st => ({
                    label: st.label,
                    value: st.value
                }));

            console.log('Loaded sub types:', this.subTypeOptions);

        } catch (error) {
            console.error('Error loading sub types:', error);
            this.showToast('Error', 'Failed to load sub types', 'error');
            this.subTypeOptions = [];
        }
    }

    async loadSubCategoryOptions() {
        try {
            const subCategories = await getSubCategoryOptions();

            let filteredSubCategories = subCategories;

            // Define allowed sub-categories for specific sub-types
            const allowedSubCategories = {
                'Bidding (Registro)': [
                    'Course Related- Core',
                    'Course Related- Elective',
                    'Course Related- Flexi Core',
                    'Programme Requirements',
                    'Study Group',
                    'Attendance',
                    'Student ID Card',
                    'Classroom Seating',
                    'Others',
                    'Feedback',
                    'Inter-cohort Exchange',
                    'Inter-cohort Transfer',
                    'Pre-term'
                ],
                'Incoming & Outgoing Student Exchange (Registro)': [
                    'ExchangeSchoolsconfirmations',
                    'Exchange Schoolsfactsheets',
                    'Exchange SchoolsMOU',
                    'Exchange school Surveys',
                    'Student Bidding',
                    'Student Nominations',
                    'Student Undertakings',
                    'Student Withdrawal',
                    'Student Visa - Recommendation letter, Visa copy, passport copy etc.',
                    'Student Course Confirmation forms',
                    'Student Exit',
                    'Student Transcripts',
                    'Student Registrations',
                    'Course Information',
                    'Student Arrival - Accommodation, Buddy, Welcome email etc.'
                ],
                'Academic': [
                    'Academic Advising',
                    'Documents and Transcripts',
                    'Exams and Assessments',
                    'Feedback, Concerns and Suggestions',
                    'Program and Policy Queries',
                    'Scheduling and Availability',
                    'Course Management',
                    'Attendance Related',
                    'Course related',
                    'Exams & Grades',
                    'GPA/CGPA',
                    'Fee Related Queries'
                ]
            };

            if (allowedSubCategories[this.selectedSubType]) {
                filteredSubCategories = subCategories.filter(sc =>
                    allowedSubCategories[this.selectedSubType].includes(sc.label)
                );
            }

            this.subCategoryOptions = filteredSubCategories.map(sc => ({
                label: sc.label,
                value: sc.value
            }));

            console.log('Loaded sub categories:', this.subCategoryOptions);

        } catch (error) {
            console.error('Error loading sub categories:', error);
            this.showToast('Error', 'Failed to load sub categories', 'error');
            this.subCategoryOptions = [];
        }
    }

    handleSubTypeSelect(event) {
        this.selectedSubType = event.detail.value;
        const subTypesWithSubCategory = ['Bidding (Registro)', 'Incoming & Outgoing Student Exchange (Registro)', 'Academic'];
        if (subTypesWithSubCategory.includes(this.selectedSubType)) {
            this.showSubCategorySelection = true;
            this.loadSubCategoryOptions();
        } else {
            this.showSubCategorySelection = false;
            this.selectedSubCategory = '';
        }
        this.updateFieldVisibilities();
    }

    handleSubCategoryChange(event) {
        this.selectedSubCategory = event.detail.value;
        console.log('Sub category-->' + this.selectedSubCategory);
    }

    updateFieldVisibilities() {
        const isGeneralSupport = this.selectedRecordTypeLabel &&
            (this.selectedRecordTypeLabel.toLowerCase().includes('general support') ||
                this.selectedRecordTypeLabel.toLowerCase().includes('general'));

        // Explicitly match "Academic Records (Certificates / Transcripts)" sub-type only.
        // The "Academic" sub-type (General Support > Academic > sub-categories) must NOT
        // trigger Document Type / Delivery Mode fields — those are only for cert/transcript requests.
        const isAcademicRecords = this.selectedSubType &&
            (this.selectedSubType.toLowerCase().includes('academic records') ||
                this.selectedSubType.toLowerCase().includes('certificates') ||
                this.selectedSubType.toLowerCase().includes('transcripts'));

        const isVisaNoc = this.selectedSubType &&
            this.selectedSubType.toLowerCase().includes('visa');

        const isNameChange = this.selectedSubType &&
            (this.selectedSubType.toLowerCase().includes('name change') ||
                this.selectedSubType.toLowerCase().includes('name change / display'));

        const isGraduationWalk = this.selectedSubType &&
            this.selectedSubType.toLowerCase().includes('graduation walk');

        const isFeeException = this.selectedSubType &&
            this.selectedSubType.toLowerCase().includes('fee exception');

        const isWellbeing = this.selectedSubType &&
            this.selectedSubType.toLowerCase().includes('wellbeing');

        // Fee Exception specific logic
        if (isFeeException) {
            this.showAcademicRecordsFields = false;
            this.showVisaNocFields = false;
            this.showNameChangeFields = false;
            this.showEventBudgetFields = false;
            this.showWellbeingFields = false;

            // Hide LOA type and academic session fields for Fee Exception
            this.hideLoaTypeForAcademicRecords = true;
            this.hideLoaTypeForLoaRecords = true;
            this.hideLoaTypeForVisaNoc = true;
            this.hideLoaTypeForGraduationWalk = true;
            this.hideLoaTypeForWellbeing = true;
            this.hideAcademicSessionsForWellbeing = true;
            this.hideTermsForAcademicRecords = true;
            this.hideTermsForVisaNoc = true;
            this.hideSubjectAndDescriptionForNameChange = true;
        } else if (isWellbeing) {
            // Wellbeing specific logic
            this.showAcademicRecordsFields = false;
            this.showVisaNocFields = false;
            this.showNameChangeFields = false;
            this.showEventBudgetFields = false;
            this.showWellbeingFields = true; // ADD THIS

            // Hide LOA type and academic session fields for Wellbeing
            this.hideLoaTypeForWellbeing = true;
            this.hideAcademicSessionsForWellbeing = true;

            // Show subject and description for Wellbeing
            this.hideSubjectAndDescriptionForNameChange = false;
        } else {
            // Existing logic for other sub-types
            this.showAcademicRecordsFields = isGeneralSupport && isAcademicRecords;
            this.showVisaNocFields = isGeneralSupport && isVisaNoc;
            this.showNameChangeFields = isGeneralSupport && isNameChange;
            this.showWellbeingFields = false;

            this.hideLoaTypeForAcademicRecords = isGeneralSupport && isAcademicRecords;
            this.hideLoaTypeForLoaRecords = isGeneralSupport && isNameChange;
            this.hideLoaTypeForVisaNoc = isGeneralSupport && isVisaNoc;
            this.hideLoaTypeForGraduationWalk = isGeneralSupport && isGraduationWalk;
            this.hideLoaTypeForWellbeing = false;
            this.hideAcademicSessionsForWellbeing = false;
            this.hideTermsForAcademicRecords = isGeneralSupport && isAcademicRecords;
            this.hideTermsForVisaNoc = isGeneralSupport && isVisaNoc;
            this.hideSubjectAndDescriptionForNameChange = isGeneralSupport && isNameChange;
        }

        console.log('Field Visibilities:', {
            feeException: isFeeException,
            wellbeing: isWellbeing,
            academicRecords: this.showAcademicRecordsFields,
            visaNoc: this.showVisaNocFields,
            nameChange: this.showNameChangeFields,
            wellbeingFields: this.showWellbeingFields,
            graduationWalk: isGraduationWalk,
            hideLoaType: this.hideLoaTypeForAcademicRecords || this.hideLoaTypeForVisaNoc ||
                this.hideLoaTypeForGraduationWalk || this.hideLoaTypeForLoaRecords ||
                this.hideLoaTypeForWellbeing,
            hideAcademicSessions: this.hideAcademicSessionsForWellbeing,
            hideTerms: this.hideTermsForAcademicRecords || this.hideTermsForVisaNoc,
            hideSubjectAndDescription: this.hideSubjectAndDescriptionForNameChange,
            recordType: this.selectedRecordTypeLabel,
            subType: this.selectedSubType
        });
    }


    async validateTermOverlap() {
        // Only validate for specific record types that require term validation
        const shouldValidate = this.shouldValidateTermOverlap;

        if (!shouldValidate || !this.fromTerm || !this.toTerm || !this.program || !this.contactId) {
            return { isValid: true };
        }

        try {
            const validationResult = await validateTermOverlap({
                contactId: this.contactId,
                recordTypeId: this.selectedRecordTypeId,
                fromTermId: this.fromTerm,  // Send ID, not name
                toTermId: this.toTerm,      // Send ID, not name
                programId: this.program
            });

            // REMOVE the check for same terms here
            this.termValidationMessage = validationResult.message;
            this.showTermValidation = !validationResult.isValid;
            this.overlappingCases = validationResult.overlappingCases || [];

            console.log('Term Overlap Validation Result:', {
                isValid: validationResult.isValid,
                message: validationResult.message,
                showTermValidation: this.showTermValidation,
                overlappingCases: this.overlappingCases
            });

            if (!validationResult.isValid) {
                this.showToast('Term Overlap Warning', 'Please review the term overlap validation', 'warning');
            } else {
                this.showToast('Success', validationResult.message, 'success');
            }

            return validationResult;

        } catch (error) {
            console.error('Error validating term overlap:', error);
            this.termValidationMessage = 'Error validating term overlap: ' + error.body?.message;
            return { isValid: true }; // Allow submission on error
        }
    }

    // Add helper method to determine if term overlap validation should run
    get shouldValidateTermOverlap() {
        // Validate for these record types (modify as needed)
        const recordTypesToValidate = [
            'LOA',
            'Leave of Absence',
            'Withdrawal',
            'Rejoin'
        ];

        const currentRecordType = this.selectedRecordTypeLabel || this.caseRecordType;

        if (!currentRecordType) return false;

        return recordTypesToValidate.some(type =>
            currentRecordType.toLowerCase().includes(type.toLowerCase())
        );
    }
    get isAcademicProbation() {
        return this.selectedRecordTypeLabel &&
            (this.selectedRecordTypeLabel.toLowerCase().includes('academic  probation') ||  // Double space
                this.selectedRecordTypeLabel.toLowerCase().includes('academic probation'));    // Single space
    }

    get isExistingAcademicProbation() {
        return this.caseRecordType &&
            (this.caseRecordType.toLowerCase().includes('academic  probation') ||  // Double space
                this.caseRecordType.toLowerCase().includes('academic probation'));    // Single space
    }
    /* PREVIOUS IMPLEMENTATION COMMENTED OUT AS PER REQUEST
    get shouldShowLoaType() {
        // Hide LOA Type if program is Post Graduate Programme in Management or Post Graduate Programme in Management for Young Leaders, ONLY FOR LOA record type
        if (this.isLOARecordType || this.isExistingLOARecordType) {
            if (this.programName === 'Post Graduate Programme in Management' || 
                this.programName === 'Post Graduate Programme in Management for Young Leaders') {
                return false;
            }
        }

        // Don't show for Attendance Exception, Withdrawal, Rejoin, Return Replace, Fee Exception, Academic Probation, or Wellbeing
        if (this.showAttendanceExceptionFields || this.isWithdrawalCase ||
            this.isRejoin || this.isReturnReplace || this.isFeeExceptionCase ||
            this.isAcademicProbation || this.isWellbeingRecordType) {
            return false;
        }

        // Hide for simple sub-types
        if (this.isSimpleSubType) {
            return false;
        }

        return !this.hideLoaTypeForAcademicRecords &&
            !this.hideLoaTypeForVisaNoc &&
            !this.hideLoaTypeForGraduationWalk &&
            !this.hideLoaTypeForLoaRecords &&
            !this.hideLoaTypeForWellbeing &&
            !this.showEventBudgetFields;
    }
    */

    get shouldShowLoaType() {
        // If it's explicitly NOT an LOA case, hide it
        if (!this.isLOARecordType && !this.isExistingLOARecordType) {
            return false;
        }

        // Hide LOA Type if program is Post Graduate Programme in Management or Post Graduate Programme in Management for Young Leaders
        if (this.programName === 'Post Graduate Programme in Management' ||
            this.programName === 'Post Graduate Programme in Management for Young Leaders') {
            return false;
        }

        // Don't show for Attendance Exception, Withdrawal, Rejoin, Return Replace, Fee Exception, Academic Probation, or Wellbeing
        if (this.showAttendanceExceptionFields || this.isWithdrawalCase ||
            this.isRejoin || this.isReturnReplace || this.isFeeExceptionCase ||
            this.isAcademicProbation || this.isWellbeingRecordType) {
            return false;
        }

        // Hide for simple sub-types
        if (this.isSimpleSubType) {
            return false;
        }

        return !this.hideLoaTypeForAcademicRecords &&
            !this.hideLoaTypeForVisaNoc &&
            !this.hideLoaTypeForGraduationWalk &&
            !this.hideLoaTypeForLoaRecords &&
            !this.hideLoaTypeForWellbeing &&
            !this.showEventBudgetFields;
    }

    get shouldShowCohortSelection() {
        return this.isRejoin;
    }

    get shouldShowTerms() {
        return !this.hideTermsForAcademicRecords &&
            !this.hideTermsForVisaNoc;
    }

    get shouldShowSubjectAndDescription() {
        // Don't show for Event & Budget Proposal
        if (this.showEventBudgetFields || this.isReturnReplace) {
            return false;
        }

        // Don't show for Name Change sub-type
        if (this.hideSubjectAndDescriptionForNameChange) {
            return false;
        }

        // Show for Fee Exception (we want Subject and Reason)
        if (this.isFeeExceptionCase) {
            return true;
        }

        return true;
    }

    get shouldShowAttachDocuments() {
        // Upload section is already wrapped in <template if:false={recordId}> in HTML,
        // so it only renders for new case creation. Show for all sub-types on new case.
        return true;
    }

    get isSimpleSubType() {
        const simpleSubTypes = [
            'Bidding (Registro)',
            'Incoming & Outgoing Student Exchange (Registro)',
            'Academic',
            'Events & Budgets',
            'Posts',
            'Special Interest Group Request',
            'Awards Management - Approval'
        ];
        return simpleSubTypes.includes(this.selectedSubType);
    }

    getCourseAttendanceId() {
        if (this.showAttendanceExceptionFields) {
            return this.selectedCourseId;
        }
        if (!this.selectedCourseId) return null;

        const selectedCourse = this.attendanceCourseOptions.find(
            course => course.value === this.selectedCourseId
        );

        return selectedCourse ? selectedCourse.courseAttendanceId : null;
    }

    get showDispatchAddress() {
        // Show dispatch address only when:
        // 1. It's General Support with Academic Records sub-type AND
        // 2. Delivery Mode is "Print"
        const isGeneralSupport = this.selectedRecordTypeLabel &&
            (this.selectedRecordTypeLabel.toLowerCase().includes('general support') ||
                this.selectedRecordTypeLabel.toLowerCase().includes('general'));

        const isAcademicRecords = this.selectedSubType &&
            (this.selectedSubType.toLowerCase().includes('academic') ||
                this.selectedSubType.toLowerCase().includes('certificates') ||
                this.selectedSubType.toLowerCase().includes('transcripts'));

        return isGeneralSupport && isAcademicRecords && this.deliveryMode === 'Print';
    }

    get showDocumentMessage() {
        // Show "Please attach document if any" message when:
        // 1. It's General Support AND
        // 2. Sub-type is Certificates / Transcripts (or Academic Records)
        const isGeneralSupport = this.selectedRecordTypeLabel &&
            (this.selectedRecordTypeLabel.toLowerCase().includes('general support') ||
                this.selectedRecordTypeLabel.toLowerCase().includes('general'));

        const isCertificatesTranscripts = this.selectedSubType &&
            (this.selectedSubType.toLowerCase().includes('certificates') ||
                this.selectedSubType.toLowerCase().includes('transcripts'));

        return isGeneralSupport && isCertificatesTranscripts;
    }

    get getSelectedCourseName() {
        if (this.showAttendanceExceptionFields) {
            return this.selectedCourseName;
        }
        if (!this.selectedCourseId) return '';
        const course = this.attendanceCourseOptions.find(c => c.value === this.selectedCourseId);
        return course ? course.label : '';
    }

    get getSelectedSessionKey() {
        if (this.showAttendanceExceptionFields) {
            return this.selectedSessionKey;
        }
        if (!this.selectedSessionId) return '';
        return this.sessionOptions.find(s => s.value === this.selectedSessionId)?.label || '';
    }

    get isAttendanceExceptionFormValid() {
        return this.showAttendanceExceptionFields &&
            this.selectedSessionId &&
            this.selectedCourseId &&
            this.extractedDateOfAbsence &&
            this.attendanceExceptionReason &&
            this.subject &&
            this.description;
    }

    get disableCourseDropdown() {
        return !this.selectedSessionId || this.attendanceCourseOptions.length === 0;
    }

    get showSelectedDetails() {
        return this.selectedSessionId && this.selectedCourseId && this.extractedDateOfAbsence;
    }
    get isWithdrawalCase() {
        return this.selectedRecordTypeLabel &&
            (this.selectedRecordTypeLabel.toLowerCase().includes('withdrawal') ||
                this.selectedRecordTypeLabel.toLowerCase().includes('withdraw'));
    }

    get isLOACase() {
        return this.selectedRecordTypeLabel &&
            (this.selectedRecordTypeLabel.toLowerCase().includes('leave of absence'));
    }

    get isExistingWithdrawalCase() {
        return this.caseRecordType &&
            (this.caseRecordType.toLowerCase().includes('withdrawal') ||
                this.caseRecordType.toLowerCase().includes('withdraw'));
    }

    get shouldShowAcademicSessionFields() {
        // Don't show for Attendance Exception
        if (this.showAttendanceExceptionFields || this.isReturnReplace) {
            return false;
        }

        // ✅ ADD: Don't show for Academic Probation
        if (this.isAcademicProbation) {
            return false;
        }

        // Don't show for Fee Exception
        if (this.isFeeExceptionCase) {
            return false;
        }
        if (this.isWellbeingRecordType) {
            return false;
        }

        // Hide for simple sub-types
        if (this.isSimpleSubType) {
            return false;
        }

        const isGeneralSupport = this.selectedRecordTypeLabel &&
            (this.selectedRecordTypeLabel.toLowerCase().includes('general support') ||
                this.selectedRecordTypeLabel.toLowerCase().includes('general'));

        // Explicitly match "Academic Records (Certificates / Transcripts)" sub-type only.
        // "Academic" sub-type must NOT suppress LOA type fields — it goes through sub-categories.
        const isAcademicRecords = this.selectedSubType &&
            (this.selectedSubType.toLowerCase().includes('academic records') ||
                this.selectedSubType.toLowerCase().includes('certificates') ||
                this.selectedSubType.toLowerCase().includes('transcripts'));

        const isVisaNoc = this.selectedSubType &&
            this.selectedSubType.toLowerCase().includes('visa');

        const isNameChange = this.selectedSubType &&
            (this.selectedSubType.toLowerCase().includes('name change') ||
                this.selectedSubType.toLowerCase().includes('name change / display'));

        return !this.isRejoin &&  // Add this condition
            !(isGeneralSupport && (isAcademicRecords || isVisaNoc || isNameChange)) &&
            !this.showEventBudgetFields;
    }

    get shouldShowWellbeingFields() {
        return this.isWellbeingRecordType;
    }
    get selectedSubTypeLabel() {
        if (!this.selectedSubType || !this.subTypeOptions) return '';
        const selected = this.subTypeOptions.find(st => st.value === this.selectedSubType);
        return selected ? selected.label : '';
    }

    get isSubTypeContinueDisabled() {
        if (!this.selectedSubType) return true;
        if (this.showSubCategorySelection && !this.selectedSubCategory) return true;
        return false;
    }

    get submitButtonLabel() {
        if (this.showEventBudgetFields) {
            return 'Submit Event & Budget Proposal';
        } else if (this.isRejoin) {
            return 'Submit Rejoin Request';
        } else if (this.isFeeExceptionCase) {
            return 'Submit Fee Exception Request';
        } else {
            return 'Submit Request';
        }
    }
    // For new cases
    get isLOARecordType() {
        return this.selectedRecordTypeLabel &&
            (this.selectedRecordTypeLabel.toLowerCase().includes('leave of absence'));
    }

    // For existing cases
    get isExistingLOARecordType() {
        return this.caseRecordType &&
            (this.caseRecordType.toLowerCase().includes('leave of absence'));
    }
    handleSubTypeConfirm() {
        if (!this.selectedSubType) {
            this.showToast('Warning', 'Please select a sub type to continue', 'warning');
            return;
        }

        if (this.showSubCategorySelection && !this.selectedSubCategory) {
            this.showToast('Warning', 'Please select a sub category to continue', 'warning');
            return;
        }

        this.updateFieldVisibilities();
        this.showSubTypeSelection = false;
        this.showSubCategorySelection = false;

        // Check if this is a Fee Exception subtype
        const isFeeException = this.selectedSubType &&
            this.selectedSubType.toLowerCase().includes('fee exception');

        // Check if this is a Wellbeing subtype
        const isWellbeing = this.selectedSubType &&
            this.selectedSubType.toLowerCase().includes('wellbeing');

        if (isFeeException || isWellbeing) {
            // For Fee Exception or Wellbeing, directly show the form
            this.showForm = true;
        } else {
            // For other General Support subtypes, also directly show the form
            this.showForm = true;
        }

        // Special handling for simple sub-types
        if (this.isSimpleSubType) {
            this.subject = this.selectedSubType + (this.selectedSubCategory ? ' - ' + this.selectedSubCategory : '');
            this.description = 'Case created for ' + this.selectedSubType + (this.selectedSubCategory ? ' with sub-category: ' + this.selectedSubCategory : '');
            this.isReadOnlyForSimpleSubTypes = true;
        }

        this.showToast('Success', `Selected: ${this.selectedSubTypeLabel}`, 'success');
    }

    handleBackToRecordType() {
        this.showSubTypeSelection = false;
        this.showForm = false;
        this.showRecordTypeSelection = true;
        this.showRejoinCaseSelection = false;
        //sid
        this.showReturnReplaceCaseSelection = false;
        //sid
        this.selectedRecordTypeId = '';
        this.selectedRecordTypeLabel = '';
        //sid
        this.selectedReturnReplaceCaseId = '';
        this.selectedReturnReplaceCaseNumber = '';
        this.returnReplaceCaseOptions = [];
        //sid
        this.returnReplaceCourseOptions = [];
        this.selectedReturnReplaceCourseId = '';
        this.isReturnReplace = false;
        this.selectedRecordTypeIcon = '';
        this.selectedRejoinCaseId = '';
        this.selectedRejoinCaseNumber = '';
        this.isRejoin = false;
        this.selectedSubType = '';
        this.selectedSubCategory = '';
        this.showSubCategorySelection = false;
        this.subCategoryOptions = [];
        this.showAcademicRecordsFields = false;
        this.showVisaNocFields = false;
        this.showNameChangeFields = false;
        this.showEventBudgetFields = false;
        this.showWellbeingFields = false;
        this.requestedEndDate = '';
    }

    // Replace the existing loadRejoinCases method with this:
    async loadRejoinCases() {
        this.isLoading = true;
        try {
            let cases;
            if (this.email) {
                console.log('Using getRejoinCasesByEmail with email:', this.email);
                cases = await getRejoinCasesByEmail({ email: this.email });
            } else {
                console.log('Using standard getRejoinCases');
                cases = await getRejoinCases();
            }

            console.log('Rejoin cases fetched:', cases);

            this.rejoinCaseOptions = cases.map(c => ({
                label: `${c.displayLabel} (Case: ${c.caseNumber})`,
                value: c.caseId,
                caseNumber: c.caseNumber,
                loaType: c.loaType,
                programName: c.programName,
                fromTerm: c.fromTerm,
                toTerm: c.toTerm
            }));

            if (this.rejoinCaseOptions.length === 0) {
                this.showToast('Info', 'No approved LOA cases found for Rejoin', 'info');
            }
        } catch (error) {
            console.error('Error loading rejoin cases:', error);
            this.showToast('Error', 'Failed to load eligible cases', 'error');
            this.rejoinCaseOptions = [];
        } finally {
            this.isLoading = false;
        }
    }

    async handleRejoinCaseSelect(event) {
        this.selectedRejoinCaseId = event.detail.value;
        const selectedCase = this.rejoinCaseOptions.find(c => c.value === this.selectedRejoinCaseId);
        if (!selectedCase) {
            this.showToast('Error', 'Please select a valid Case.', 'error');
            return;
        }
        try {
            // ✅ Validation 2: Check if any Rejoin child case already exists
            const rejoinExists = await isRejoinCasePresent({
                caseId: this.selectedRejoinCaseId   // Parent Case Id
            });

            if (rejoinExists) {
                this.showToast(
                    'Validation Error',
                    'Already Rejoin case present for the selected Case.',
                    'error'
                );

                // Optional: reset selection so user must choose another
                this.selectedRejoinCaseId = null;
                return;
            }

            // ✅ If validation passes, proceed with assignments
            this.selectedRejoinCaseNumber = selectedCase.caseNumber;
            this.selectedRejoinCaseLOA = selectedCase.loaType;
            this.selectedRejoinCaseProgram = selectedCase.programName;
            this.selectedRejoinCaseFromTerm = selectedCase.fromTerm;
            this.selectedRejoinCaseToTerm = selectedCase.toTerm;

            console.log('Selected Rejoin Case:', selectedCase.label);

            // ✅ Store the term NAMES from the parent case
            this.fromTermName = selectedCase.fromTerm;
            this.toTermName = selectedCase.toTerm;

        } catch (error) {
            console.error('Rejoin case validation failed:', error);
            this.showToast('Error', 'Unable to validate Rejoin case. Please try again.', 'error');
        }


        /*if (selectedCase) {
            this.selectedRejoinCaseNumber = selectedCase.caseNumber;
            this.selectedRejoinCaseLOA = selectedCase.loaType;
            this.selectedRejoinCaseProgram = selectedCase.programName;
            this.selectedRejoinCaseFromTerm = selectedCase.fromTerm;
            this.selectedRejoinCaseToTerm = selectedCase.toTerm;
            console.log('Selected Rejoin Case:', selectedCase.label);
    
            // ✅ Store the term NAMES from the parent case
            this.fromTermName = selectedCase.fromTerm;  // Store term name
            this.toTermName = selectedCase.toTerm;      // Store term name
        }*/
    }

    handleRejoinCaseConfirm() {
        if (!this.selectedRejoinCaseId) {
            this.showToast('Warning', 'Please select a case to continue', 'warning');
            return;
        }

        this.showRejoinCaseSelection = false;
        this.showForm = true;

        // Load cohorts after case selection
        if (this.program) {
            this.loadCohortsForRejoin();
        }

        // ✅ Show success message with prepopulated terms
        // this.showToast('Success', `Selected Case: ${this.selectedRejoinCaseNumber}. Terms will be inherited from the LOA case.`, 'success');
    }

    get hasRejoinCaseOptions() {
        return this.rejoinCaseOptions && this.rejoinCaseOptions.length > 0;
    }

    get isRejoinCaseSelected() {
        return !!this.selectedRejoinCaseId;
    }

    get isRejoinCaseNotSelected() {
        return !this.selectedRejoinCaseId;
    }

    checkForExistingCase() {
        let caseId = this.recordId;

        if (!caseId && this.currentPageReference) {
            caseId = this.currentPageReference.state?.recordId ||
                this.currentPageReference.state?.c__recordId ||
                this.currentPageReference.state?.id ||
                this.currentPageReference.attributes?.recordId ||
                this.currentPageReference.attributes?.id;
        }

        if (!caseId && typeof window !== 'undefined') {
            const urlParams = new URLSearchParams(window.location.search);
            caseId = urlParams.get('recordId') || urlParams.get('id');

            // Fallback: Path segments scanning (e.g. /s/case/500.../subject)
            if (!caseId) {
                const pathSegments = window.location.pathname.split('/');
                caseId = pathSegments.find(segment =>
                    segment.startsWith('500') && (segment.length === 15 || segment.length === 18)
                );
            }
        }

        if (caseId) {
            console.log('Found existing case:', caseId);
            this.recordId = caseId;
            this.loadCaseDetails(caseId);
            this.loadCaseFiles(caseId);
            this.checkTermsAndConditions();
            if (this.isFromRecordAlert) {
                console.log('Showing existing case view only (from Record Alerts)');
                this.showForm = true;
                this.showRecordTypeSelection = false;
            } else {
                console.log('Showing normal flow (not from Record Alerts)');
                this.showForm = true;
                this.showRecordTypeSelection = false;
                this.showCaseList = false;
            }
        }
    }

    loadCaseDetails(caseId) {
        console.log('LOAD CASE: loadCaseDetails called with caseId:', caseId);
        getCaseDetails({ caseId: caseId })
            .then(result => {
                console.log('LOAD CASE: getCaseDetails returned result');
                if (result) {
                    console.log('DEBUG - loadCaseDetails result:', {
                        recordTypeName: result.RecordType?.Name,
                        recordTypeDeveloperName: result.RecordType?.DeveloperName,
                        isAcademicProbation: result.RecordType?.Name?.toLowerCase().includes('academic  probation'),
                        caseFromTerm: result.From_Term__c,
                        caseToTerm: result.To_Term__c,
                        caseLoaType: result.LOA_Type__c
                    });
                    this.caseNumber = result.CaseNumber;
                    this.caseSubject = result.Subject || '';
                    this.caseDescription = result.Description || '';
                    this.caseAcademicYear = result.Academic_Year__r?.Name || '';
                    this.academicYear = this.caseAcademicYear; // Update global property for template consistency
                    this.caseProgram = result.Program__r?.Name || '';
                    this.caseFromTerm = result.From_Term__c || '';
                    this.caseToTerm = result.To_Term__c || '';
                    this.caseCompletedTerm = result.Completed_Term__c || '';
                    this.caseLoaType = result.LOA_Type__c || '';
                    this.caseRecordType = result.RecordType?.Name || '';

                    // Populate email and contactId for context matching if not already set
                    if (!this.email && result.ContactEmail) {
                        this.email = result.ContactEmail;
                        // Avoid full re-init if we already have it, but for guest it's vital
                        if (isGuest) this.loadUserAccountContact();
                    }
                    if (!this.contactId && result.ContactId) {
                        this.contactId = result.ContactId;
                    }
                    // Add these in the loadCaseDetails method after other case field assignments
                    //this.caseSeverity = result.Severity__c || '';
                    this.wellbeingModeOfInteraction = result.Mode_of_Interaction__c || '';
                    this.wellbeingType = result.Type__c || '';
                    //this.caseActionTaken = result.Action_Taken__c || '';
                    this.caseSubType = result.Sub_Types__c || '';
                    this.caseStatus = result.Status || '';
                    this.caseTermsCondition = result.TermsCondition__c || false;
                    // this.caseStatusLabel = this.statusLabelMapping[this.caseStatus] || this.caseStatus;
                    this.caseStatusLabel = this._computeStatusLabel(this.caseStatus);

                    // Academic Records fields
                    this.caseDocumentType = result.Document_Type__c || '';
                    this.caseDeliveryMode = result.Delivery_Mode__c || '';
                    this.caseDispatchAddress = result.Dispatch_Address__c || '';
                    this.caseStatus = result.Status || '';
                    // this.caseStatusLabel = this.statusLabelMapping[this.caseStatus] || this.caseStatus;
                    this.caseStatusLabel = this._computeStatusLabel(this.caseStatus);

                    this.termsAndConditionsData = result.Terms_and_Condition__c || '';
                    this.showTermsAndConditionsData = !!this.termsAndConditionsData;
                    // this.caseModifiedDate = result.LastModifiedDate || '';
                    this.caseAlternateEmail = result.Alternate_Email__c || '';
                    this.caseAlternatePhone = result.Alternate_Phone__c || '';
                    // Contact Phone and Mobile fields
                    this.contactPhone = result.ContactPhone || '';
                    this.contactMobile = result.ContactMobile || '';
                    
                    // Fetch owner name from OwnerId
                    if (result.OwnerId) {
                        getOwnerName({ ownerId: result.OwnerId })
                            .then(ownerName => {
                                this.ownerName = ownerName || '';
                            })
                            .catch(error => {
                                console.error('Error fetching owner name:', error);
                                this.ownerName = '';
                            });
                    }
                    
                    // Visa NOC fields
                    this.casePassportNumber = result.Passport_Number__c || '';
                    this.casePassportExpiry = result.Passport_Expiry__c || '';
                    this.caseTravelStartDate = result.Travel_Start_Date__c || '';
                    this.caseTravelEndDate = result.Travel_End_Date__c || '';
                    this.caseVisaType = result.Visa_Type__c || '';
                    this.caseVisaPurpose = result.Visa_Purpose__c || '';
                    this.caseAlternateEmail = result.Alternate_Email__c || '';
                    this.caseAlternatePhone = result.Alternate_Phone__c || '';
                    // Bank details
                    this.caseAccountHolderName = result.Account_Holder_Name__c || '';
                    this.caseAccountNumber = result.AccountNumber__c || '';
                    this.caseIfscCode = result.IFSC_Code__c || '';
                    this.caseBankName = result.Bank__c || '';
                    this.caseBranchName = result.Branch_Name__c || '';

                    // Name Change fields
                    this.caseRequestedLegalName = result.Requested_Legal_Name__c || '';
                    this.caseNameChangeReason = result.Description || '';

                    // Location field (for Rejoin cases)
                    this.caseLocation = result.Location__r?.Name || '';
                    //this.caseAccountNumber = result.Account_Holder_Name__c || '';
                    this.caseIfscCode = result.IFSC_Code__c || '';
                    this.caseBankName = result.Bank__c || '';
                    this.caseBranchName = result.Branch_Name__c || '';

                    // Event & Budget fields
                    this.eventTitle = result.Title__c || '';
                    this.eventProposedDateTime = result.Proposed_Date_Time__c || '';
                    this.eventVenue = result.Venue__c || '';
                    this.eventHostBody = result.Host_Body__c || '';
                    this.eventDescription = result.Description || '';
                    this.eventExpectedHeadcount = result.Expected_Headcount__c || '';
                    this.eventBudgetAsk = result.Budget_Ask__c || '';
                    this.eventContacts = result.Event_Contact__c || '';

                    // Store both DeveloperName and Name for debugging
                    const recordTypeDeveloperName = result.RecordType?.DeveloperName || '';
                    const recordTypeName = result.RecordType?.Name || '';
                    this.caseRecordType = recordTypeName; // Use Name (label) not DeveloperName

                    // Recompute status label now that caseRecordType is set (needed for Academic Probation override)
                    this.caseStatusLabel = this._computeStatusLabel(this.caseStatus);

                    console.log('DEBUG - caseRecordType set to:', this.caseRecordType);
                    console.log('DEBUG - isExistingAcademicProbation:', this.isExistingAcademicProbation);
                    console.log('DEBUG - shouldShowLoaTypeInCase will be:', this.shouldShowLoaTypeInCase);
                    console.log('DEBUG - shouldShowAcademicSessionFieldsInCase will be:', this.shouldShowAcademicSessionFieldsInCase);

                    this.rejoinAmountPaid = result.Rejoin_Amount_Paid__c || false;
                    this.caseType = result.Type;
                    this.caseAmount = result.Amount__c || 0;
                    console.log('Case Amount field value:', result.Amount__c);
                    console.log('Case Amount field exists:', 'Amount__c' in result);
                    // Also check if this field exists in the response
                    console.log('Does Amount__c exist in result?', 'Amount__c' in result);

                    // Logic for showing Payment Required section:
                    // 1. Case Type matches 'Rejoin'
                    // 2. Amount is greater than 0
                    // 3. Payment hasn't been made yet
                    // MODIFICATION POINT: Update logic here to support other record types
                    this.showAmountField = ((this.caseType === 'Rejoin') || (this.caseType === 'Return and Replace')) &&
                        this.caseAmount > 0 &&
                        !this.rejoinAmountPaid;
                    console.log('showAmountField calculated:', this.showAmountField, {
                        caseType: this.caseType,
                        caseAmount: this.caseAmount,
                        rejoinAmountPaid: this.rejoinAmountPaid
                    });

                    // Fee Exception field
                    this.requestedEndDate = result.Requested_End_Date__c || '';

                    // Set field visibilities based on record type and sub-type
                    this.updateExistingCaseFieldVisibilities();

                    if (result.ProgramId) {
                        const program = this.programOptions.find(p => p.value === result.ProgramId);
                        this.caseProgram = program ? program.label : '';
                    }
                    // Check if financial statement has already been processed
                    if (this.caseStatus === 'Finance Statement Accepted' || this.caseStatus === 'Finance Statement Rejected') {
                        this.requiresFinancialStatement = false;
                        this.showFinancialStatementSection = false;
                    }

                    setTimeout(() => {
                        this.checkTermsAndConditions();
                    }, 500);

                    this.checkWithdrawalBankDetails();
                    console.log('LOAD CASE: checkWithdrawalBankDetails called');
                }
                this.checkTermsAndConditions();
                this.checkFinancialStatement();
                this.isLoading = false; // Data loaded
            })
            .catch(error => {
                console.error('Error loading case details:', error);
                this.caseNumber = caseId;
                this.isLoading = false; // Even on error, stop spinner
            });
        this.loadCaseComments(caseId);
        this.loadCaseFiles(caseId);
    }

    _computeStatusLabel(status) {
        if (!status) return '';
        // For Academic Probation cases, show "Open" instead of "Submitted"
        if (this.isExistingAcademicProbation && status === 'Submitted') {
            return 'Open';
        }
        if (status === 'Submitted' || status === 'In Review') {
            return 'Submitted';
        } else if (status === 'Closed') {
            return 'Closed';
        } else if (status === 'Rejected') {
            return 'Case Rejected'
        } else if (status === 'RFI Requested' || status === 'Decision Pending HOD' || status === 'Approved by HOD'){
            return 'Pending at RO';
        } else if (this.caseRecordTypeId === '012C4000000xt0ZIAQ' || status === 'Finance Review' || status === 'Decision Pending to Finance HOD' || status === 'Approved By Finance HOD'){
            return 'Approved by RO & Pending at Finance';
        }
            
    }

    get formattedCaseAmount() {
        if (!this.caseAmount || this.caseAmount === 0) {
            return '0.00';
        }

        // Format as Indian Rupees (₹) with proper formatting
        return new Intl.NumberFormat('en-IN', {
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        }).format(this.caseAmount);
    }

    handleCheckTerms() {
        console.log('Manually checking terms and conditions...');
        console.log('Current state:', {
            caseId: this.recordId,
            caseStatus: this.caseStatus,
            caseStatusLabel: this.caseStatusLabel,
            isCaseClosed: this.isCaseClosed,
            requiresTermsAndConditions: this.requiresTermsAndConditions,
            showTermsSection: this.showTermsSection
        });
        this.checkTermsAndConditions();
    }

    getStatusLabelMapping() {
        return new Promise((resolve, reject) => {
            getStatusLabelMapping()
                .then(result => {
                    resolve(result);
                })
                .catch(error => {
                    reject(error);
                });
        });
    }

    checkWithdrawalBankDetails() {
        console.log('BANK CHECK: checkWithdrawalBankDetails called');
        console.log('BANK CHECK: isExistingWithdrawalCase =', this.isExistingWithdrawalCase);
        console.log('BANK CHECK: caseStatus =', this.caseStatus);
        console.log('BANK CHECK: caseStatusLabel =', this.caseStatusLabel);
        console.log('BANK CHECK: caseTermsCondition =', this.caseTermsCondition);
        console.log('BANK CHECK: caseRecordType =', this.caseRecordType);


        this.showBankDetailsSection = this.isExistingWithdrawalCase && (this.caseStatus === 'Approved11' || this.caseStatusLabel === 'Approved-Pending T&C' || this.caseStatusLabel === 'T&C Accepted') && this.caseTermsCondition === true;
        this.showBankDetailsReadOnly = this.showBankDetailsSection && this.caseStatusLabel === 'T&C Accepted';

        console.log('BANK CHECK: showBankDetailsSection =', this.showBankDetailsSection);
        console.log('BANK CHECK: showBankDetailsReadOnly =', this.showBankDetailsReadOnly);
        // if(this.caseStatusLabel === 'T&C Accepted'){
        //     this.showBankDetailsReadOnly =true;
        // }   


    }
    get isCaseClosed() {
        return this.caseStatus === 'Closed' || this.caseStatusLabel === 'Closed';
    }

    get isCaseRejected() {
        return this.caseStatus === 'Rejected' || this.caseStatusLabel === 'Case Rejected';
    }
    get formattedTermsAndConditions() {
        if (!this.termsAndConditionsData) return '';
        // Convert newlines to HTML line breaks
        return this.termsAndConditionsData.replace(/\n/g, '<br>');
    }

    // Add this method to handle terms submission separately

    // Add this getter to check if rejection reason should be shown
    get showRejectionReason() {
        return !this.termsAccepted;
    }
    // Add this getter method to split the terms and conditions data into lines
    get termsAndConditionsLines() {
        if (!this.termsAndConditionsData) {
            return [];
        }

        // Split the text by newlines and filter out empty lines
        const lines = this.termsAndConditionsData.split('\n').filter(line => line.trim() !== '');

        // Return an array of objects with index and text
        return lines.map((text, index) => ({
            index: index,
            text: text
        }));
    }

    // Or for better formatting with paragraphs, use this:
    get formattedTermsAndConditions() {
        if (!this.termsAndConditionsData) {
            return [];
        }

        // Split the terms into logical paragraphs (by double newlines)
        const paragraphs = this.termsAndConditionsData.split('\n\n');

        return paragraphs.map((paragraph, index) => ({
            id: `para-${index}`,
            content: paragraph.trim()
        }));
    }
    updateExistingCaseFieldVisibilities() {
        const isGeneralSupport = this.caseRecordType &&
            (this.caseRecordType.toLowerCase().includes('general support') ||
                this.caseRecordType.toLowerCase().includes('general'));

        const isAcademicRecords = this.caseSubType &&
            this.caseSubType.toLowerCase().includes('academic');

        const isVisaNoc = this.caseSubType &&
            this.caseSubType.toLowerCase().includes('visa');

        const isNameChange = this.caseSubType &&
            (this.caseSubType.toLowerCase().includes('name change') ||
                this.caseSubType.toLowerCase().includes('name change / display'));

        const isGraduationWalk = this.caseSubType &&
            this.caseSubType.toLowerCase().includes('graduation walk');

        const isEventBudget = this.caseRecordType &&
            (this.caseRecordType.toLowerCase().includes('event') ||
                this.caseRecordType.toLowerCase().includes('budget'));

        const isFeeException = this.caseSubType &&
            this.caseSubType.toLowerCase().includes('fee exception');

        const isWellbeing = this.caseRecordType &&
            this.caseRecordType.toLowerCase().includes('wellbeing');


        // Use EXACTLY the same logic as new case creation
        this.caseShowAcademicRecordsFields = isGeneralSupport && isAcademicRecords;
        this.caseShowVisaNocFields = isGeneralSupport && isVisaNoc;
        this.caseShowNameChangeFields = isGeneralSupport && isNameChange;
        this.showEventBudgetFields = isEventBudget;

        // Use the same hide/show logic as new cases
        this.caseHideLoaType = isGeneralSupport && (isAcademicRecords || isVisaNoc || isNameChange || isGraduationWalk || isFeeException || isWellbeing);
        this.caseHideSubjectAndDescription = isGeneralSupport && isNameChange;
        this.caseHideAcademicSessions = isWellbeing;

        console.log('Existing Case Field Visibilities:', {
            recordType: this.caseRecordType,
            subType: this.caseSubType,
            academicRecords: this.caseShowAcademicRecordsFields,
            visaNoc: this.caseShowVisaNocFields,
            wellbeing: this.showWellbeingFields,
            nameChange: this.caseShowNameChangeFields,
            eventBudget: this.showEventBudgetFields,
            feeException: isFeeException,
            hideLoaType: this.caseHideLoaType,
            hideSubjectAndDescription: this.caseHideSubjectAndDescription
        });
    }

    /* PREVIOUS IMPLEMENTATION COMMENTED OUT AS PER REQUEST
    get shouldShowLoaTypeInCase() {
         console.log('DEBUG - shouldShowLoaTypeInCase:', {
        isReturnReplace: this.isReturnReplace,
        isExistingWithdrawalCase: this.isExistingWithdrawalCase,
        isExistingAcademicProbation: this.isExistingAcademicProbation,
        isExistingAttendanceException: this.isExistingAttendanceException,
        caseRecordType: this.caseRecordType,
        caseHideLoaType: this.caseHideLoaType
    });

        if (this.isReturnReplace) {
            return false;
        }
        // Don't show LOA Type for Withdrawal cases
        if (this.isExistingWithdrawalCase) {
            return false;
        }
       // ✅ DON'T show for Academic Probation
    if (this.isExistingAcademicProbation) {
        console.log('DEBUG - Not showing LOA Type for Academic Probation');
        return false;
    }

     if (this.isExistingWellbeingCase) {
        console.log('DEBUG - Not showing LOA Type for Wellbeing');
        return false;
    }
    
    // ✅ DON'T show for Attendance Exception
    if (this.isExistingAttendanceException) {
        console.log('DEBUG - Not showing LOA Type for Attendance Exception');
        return false;
    }
        // Don't show LOA Type for General Support record type
        const isGeneralSupport = this.caseRecordType &&
            (this.caseRecordType.toLowerCase().includes('general support') ||
                this.caseRecordType.toLowerCase().includes('general'));

        console.log('shouldShowLoaTypeInCase check:', {
            caseRecordType: this.caseRecordType,
            isGeneralSupport: isGeneralSupport,
            willShow: !isGeneralSupport && !this.caseHideLoaType
        });

        if (isGeneralSupport) {
            return false;
        }

        return !this.caseHideLoaType;
    }
    */
    get shouldShowLoaTypeInCase() {
        // Only show if it is an LOA case
        const isLOA = this.caseRecordType &&
            (this.caseRecordType.toLowerCase().includes('leave of absence') ||
                this.caseRecordType.toLowerCase() === 'loa');

        if (!isLOA) {
            return false;
        }

        // Hide LOA Type if program is Post Graduate Programme in Management or Post Graduate Programme in Management for Young Leaders
        if (this.caseProgramName === 'Post Graduate Programme in Management' ||
            this.caseProgramName === 'Post Graduate Programme in Management for Young Leaders') {
            return false;
        }

        if (this.isReturnReplace) {
            return false;
        }

        // Don't show LOA Type for Withdrawal and Rejoin cases
        if (this.isExistingWithdrawalCase || this.isRejoin) {
            return false;
        }

        // DON'T show for Academic Probation
        if (this.isExistingAcademicProbation) {
            return false;
        }

        if (this.isExistingWellbeingCase) {
            return false;
        }

        // DON'T show for Attendance Exception
        if (this.isExistingAttendanceException) {
            return false;
        }
        // Don't show LOA Type for General Support record type
        const isGeneralSupport = this.caseRecordType &&
            (this.caseRecordType.toLowerCase().includes('general support') ||
                this.caseRecordType.toLowerCase().includes('general'));

        if (isGeneralSupport) {
            return false;
        }

        return !this.caseHideLoaType;
    }

    // Add this getter to your JavaScript
    get isReturnReplaceCaseNotSelected() {
        return !this.isReturnReplaceCaseSelected;
    }
    get shouldShowSubjectAndDescriptionInCase() {
        // Don't show for Event & Budget Proposal in existing cases
        if (this.showEventBudgetFields) {
            return false;
        }

        // Don't show for Name Change sub-type
        if (this.caseHideSubjectAndDescription) {
            return false;
        }

        return true;
    }

    get shouldShowAcademicSessionFieldsInCase() {
        console.log('DEBUG - shouldShowAcademicSessionFieldsInCase:', {
            isExistingAcademicProbation: this.isExistingAcademicProbation,
            isExistingAttendanceException: this.isExistingAttendanceException,
            caseRecordType: this.caseRecordType,
            caseSubType: this.caseSubType
        });


        if (this.isExistingAcademicProbation) {
            console.log('DEBUG - Not showing Academic Session fields for Academic Probation');
            return false;
        }

        // ✅ DON'T show for Attendance Exception
        if (this.isExistingAttendanceException) {
            console.log('DEBUG - Not showing Academic Session fields for Attendance Exception');
            return false;
        }

        if (this.isExistingWellbeingCase || this.caseHideAcademicSessions) {
            console.log('DEBUG - Not showing Academic Session fields for Wellbeing');
            return false;
        }

        const isGeneralSupport = this.caseRecordType &&
            (this.caseRecordType.toLowerCase().includes('general support') ||
                this.caseRecordType.toLowerCase().includes('general'));

        const isAcademicRecords = this.caseSubType &&
            this.caseSubType.toLowerCase().includes('academic');

        const isVisaNoc = this.caseSubType &&
            this.caseSubType.toLowerCase().includes('visa');

        const isNameChange = this.caseSubType &&
            (this.caseSubType.toLowerCase().includes('name change') ||
                this.caseSubType.toLowerCase().includes('name change / display'));

        const isEventBudget = this.caseRecordType &&
            (this.caseRecordType.toLowerCase().includes('event') ||
                this.caseRecordType.toLowerCase().includes('budget'));

        const isFeeException = this.caseSubType &&
            this.caseSubType.toLowerCase().includes('fee exception');

        console.log('shouldShowAcademicSessionFieldsInCase check:', {
            caseRecordType: this.caseRecordType,
            caseSubType: this.caseSubType,
            isGeneralSupport: isGeneralSupport,
            caseFromTerm: this.caseFromTerm,
            caseToTerm: this.caseToTerm
        });

        // For General Support: only hide terms if the case has NO term data at all.
        // Sub-types like Graduation Walk — Exception Petition DO have From/To Term populated.
        if (isGeneralSupport) {
            const hasTermData = (this.caseFromTerm && this.caseFromTerm.trim() !== '') ||
                (this.caseToTerm && this.caseToTerm.trim() !== '');
            return hasTermData;
        }

        // Show academic session fields UNLESS it's Academic Records, Visa NOC, Name Change, Fee Exception, or Event Budget
        return !(isAcademicRecords || isVisaNoc || isNameChange || isFeeException || isEventBudget);
    }

    get isExistingAttendanceException() {
        return this.caseRecordType &&
            this.caseRecordType.toLowerCase().includes('attendance exception');
    }

    loadCaseFiles(caseId) {
        getCaseFiles({ caseId: caseId })
            .then(result => {
                if (result && result.length > 0) {
                    this.caseFiles = result.map(file => {
                        const fileExtension = file.fileExtension ? file.fileExtension.toLowerCase() :
                            file.title ? file.title.split('.').pop().toLowerCase() : '';
                        const isPDF = file.fileType === 'PDF' || fileExtension === 'pdf';
                        const isImage = this.isImageFileByExtension(fileExtension);

                        return {
                            id: file.contentDocumentId,
                            versionId: file.contentVersionId,
                            name: file.title,
                            type: file.fileType,
                            fileExtension: fileExtension,
                            size: file.contentSize,
                            iconName: this.getFileIcon(file.title),
                            formattedSize: this.formatFileSize(file.contentSize),
                            isPDF: isPDF,
                            isImage: isImage,
                            uploadedDate: file.uploadedDate
                        };
                    });
                } else {
                    this.caseFiles = [];
                }
            })
            .catch(error => {
                console.error('Error loading case files:', error);
                this.caseFiles = [];
            });
    }

    isImageFileByExtension(extension) {
        const imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg'];
        return imageExtensions.includes(extension.toLowerCase());
    }

    handleDownloadCaseFile(event) {
        const fileId = event.currentTarget.dataset.id;
        const file = this.caseFiles.find(f => f.id === fileId);

        if (file) {
            this.isLoading = true;
            downloadFile({ contentDocumentId: fileId })
                .then(result => {
                    const link = document.createElement('a');
                    link.href = `data:${this.getMimeType(file.type)};base64,${result}`;
                    link.download = file.name;
                    link.target = '_blank';
                    document.body.appendChild(link);
                    link.click();
                    document.body.removeChild(link);
                    this.showToast('Success', `Downloaded ${file.name}`, 'success');
                })
                .catch(error => {
                    console.error('Download error:', error);
                    this.showToast('Error', 'Failed to download file', 'error');
                })
                .finally(() => {
                    this.isLoading = false;
                });
        }
    }

    getMimeType(fileType, fileName) {
        if (fileType === 'PDF' || (fileName && fileName.toLowerCase().endsWith('.pdf'))) {
            return 'application/pdf';
        }
        const mimeMap = {
            'PDF': 'application/pdf',
            'JPG': 'image/jpeg',
            'JPEG': 'image/jpeg',
            'PNG': 'image/png',
            'DOC': 'application/msword',
            'DOCX': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
        };
        return mimeMap[fileType.toUpperCase()] || 'application/octet-stream';
    }

    isPDFFile(file) {
        if (!file) return false;
        if (file.type === 'application/pdf' || file.fileType === 'PDF') return true;
        const extension = file.fileExtension ? file.fileExtension.toLowerCase() :
            file.name ? file.name.split('.').pop().toLowerCase() : '';
        if (extension === 'pdf') return true;
        if (file.name && file.name.toLowerCase().endsWith('.pdf')) return true;
        return false;
    }

    handlePreviewCaseFile(event) {
        const fileId = event.currentTarget.dataset.id;
        const file = this.caseFiles.find(f => f.id === fileId);

        if (file) {
            if (this.isPDFFile(file)) {
                // Use rendition service like studentPostPublisher
                const sitePrefix = window.location.pathname.split('/s/')[0];
                const previewUrl = sitePrefix + `/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId=${file.versionId}`;

                this.selectedFile = {
                    ...file,
                    previewUrl: previewUrl,
                    iconname: file.iconName,
                    ispdf: true,
                    isimage: false,
                    formattedSize: file.formattedSize,
                    type: file.type,
                    useDistributionUrl: true
                };
                this.showFilePreview = true;
            } else {
                this.isLoading = true;
                downloadFile({ contentDocumentId: fileId })
                    .then(result => {
                        const mimeType = this.getMimeType(file.type, file.name);
                        const base64Data = `data:${mimeType};base64,${result}`;
                        const isImage = this.isImageFile(file.type, file.name);

                        this.selectedFile = {
                            ...file,
                            base64: base64Data,
                            iconname: file.iconName,
                            ispdf: this.isPDFFile(file),
                            isimage: isImage,
                            formattedSize: file.formattedSize,
                            type: file.type,
                            useDistributionUrl: false
                        };
                        this.showFilePreview = true;
                    })
                    .catch(error => {
                        console.error('Preview error:', error);
                        this.showToast('Error', 'Failed to load file for preview', 'error');
                    })
                    .finally(() => {
                        this.isLoading = false;
                    });
            }
        }
    }

    loadUserAccountContact() {
        console.log('🔴 loadUserAccountContact CALLED');
        console.log('🔴 BEFORE loadUserAccountContact - this.contactId:', this.contactId);
        console.log('🔴 BEFORE loadUserAccountContact - this.email:', this.email);
        console.log('Loading user account contact for:', { email: this.email, contactId: this.contactId });

        let contactPromise;
        if (this.email) {
            console.log('Using getUserAccountContactByEmail for guest context');
            contactPromise = getUserAccountContactByEmail({ email: this.email });
        } else {
            console.log('Using getUserAccountContact (standard logged-in user context)');
            contactPromise = getUserAccountContact();
        }

        return contactPromise
            .then(result => {
                console.log('🔴 loadUserAccountContact SUCCESS result:', JSON.stringify(result));
                this.contactId = result.contactId;
                this.accountId = result.accountId;
                this.accountName = result.accountName;
                this.email = result.email;
                this.phone = result.phone;
                this.contactName = result.contactName;
                this.mailingStreet = result.mailingStreet;
                this.mailingCity = result.mailingCity;
                this.mailingState = result.mailingState;
                this.mailingPostalCode = result.mailingPostalCode;
                this.mailingCountry = result.mailingCountry;
                this.pgid = result.pgid || '';
                this.academicYear = result.academicYear || '';
                console.log('🔴 loadUserAccountContact: POPULATED pgid:', this.pgid, 'academicYear:', this.academicYear);
                // Add bank details if available
                this.accountNumber = result.accountNumber || '';
                this.ifscCode = result.ifscCode || '';
                this.bankName = result.bankName || '';
                this.branchName = result.branchName || '';

                //Sid
                this.currentAcademicTerm = result.currentAcademicTerm || '';
                console.log('//Sid Fetching Academic Term:', this.currentAcademicTerm);
                return result;
            })
            .catch(error => {
                this.resultMessage = 'Error loading user info: ' + (error.body ? error.body.message : error.message);
            });
    }

    get isWithdrawalCase() {
        return this.selectedRecordTypeLabel &&
            (this.selectedRecordTypeLabel.toLowerCase().includes('withdrawal') ||
                this.selectedRecordTypeLabel.toLowerCase().includes('withdraw'));
    }

    get isExistingWithdrawalCase() {
        return this.caseRecordType &&
            (this.caseRecordType.toLowerCase().includes('withdrawal') ||
                this.caseRecordType.toLowerCase().includes('withdraw'));
    }

    loadAcademicYears() {
        getAcademicYears()
            .then(result => {
                this.academicYearOptions = result.map(item => ({
                    label: item.Name,
                    value: item.Id
                }));
            })
            .catch(error => {
                this.resultMessage = 'Error loading academic years: ' + (error.body ? error.body.message : error.message);
            });
    }

    loadLocation() {
        getLocation()
            .then(result => {
                this.locationOptions = result.map(item => ({
                    label: item.Name,
                    value: item.Id
                }));
            })
            .catch(error => {
                this.resultMessage = 'Error loading locations: ' + (error.body ? error.body.message : error.message);
            });
    }

    loadAcademicSessions() {
        if (!this.program) {
            this.academicSessionOptions = [];
            this.fromTerm = '';
            this.toTerm = '';
            this.completedTerm = '';
            return;
        }

        let sessionPromise;
        if (this.email) {
            console.log('Using getAcademicSessionsByProgramByEmail with email:', this.email);
            sessionPromise = getAcademicSessionsByProgramByEmail({
                programId: this.program,
                email: this.email
            });
        } else {
            console.log('Using standard getAcademicSessionsByProgram');
            sessionPromise = getAcademicSessionsByProgram({
                programId: this.program
            });
        }

        sessionPromise
            .then(result => {
                this.academicSessionOptions = result.map(session => ({
                    label: session.name,
                    value: session.id
                }));
                this.fromTerm = '';
                this.toTerm = '';
                this.completedTerm = '';
            })
            .catch(error => {
                this.resultMessage = 'Error loading academic sessions: ' + (error.body ? error.body.message : error.message);
                this.academicSessionOptions = [];
                this.fromTerm = '';
                this.toTerm = '';
                this.completedTerm = '';
            });
    }

    get isAcademicSessionDisabled() {
        return !this.program;
    }

    get acceptedFormats() {
        return ['.pdf', '.jpg', '.jpeg', '.png', '.doc', '.docx'];
    }

    get uploadedFilesCount() {
        return this.uploadedFiles.length;
    }

    get hasUploadedFiles() {
        return this.uploadedFiles.length > 0;
    }

    get totalFileSize() {
        return this.uploadedFiles.reduce((total, file) => total + file.size, 0);
    }

    get formattedTotalFileSize() {
        return this.formatFileSize(this.totalFileSize);
    }

    get formattedUploadedFiles() {
        return this.uploadedFiles.map(file => ({
            ...file,
            formattedSize: this.formatFileSize(file.size),
            iconName: this.getFileIcon(file.name)
        }));
    }

    get hasCaseFiles() {
        // Always show the Case Documents section for all case record types
        return true;
    }

    // True only when there are actually files attached — used to toggle between list and empty state
    get hasActualCaseFiles() {
        return this.caseFiles && this.caseFiles.length > 0;
    }

    get formattedCaseFiles() {
        return this.caseFiles.map(file => ({
            ...file,
            formattedSize: this.formatFileSize(file.size),
            iconName: this.getFileIcon(file.name)
        }));
    }

    async loadCoursesBySelectedTerms() {
        // Only load courses for LOA record type
        if (!this.isLOARecordType) {
            console.log('Not an LOA record type, skipping course load');
            this.filteredCourses = [];
            return;
        }

        if (!this.fromTerm || !this.toTerm) {
            console.log('FromTerm or ToTerm not selected yet');
            this.filteredCourses = [];
            return;
        }

        try {
            console.log('Loading courses for FromTerm:', this.fromTerm, 'ToTerm:', this.toTerm);

            this.isLoading = true;
            let courses;
            if (this.email) {
                console.log('Using getUserCoursesByAcademicSessionsByEmail with email:', this.email);
                courses = await getUserCoursesByAcademicSessionsByEmail({
                    programId: this.program,
                    fromTermId: this.fromTerm,
                    toTermId: this.toTerm,
                    email: this.email
                });
            } else {
                console.log('Using standard getUserCoursesByAcademicSessions');
                courses = await getUserCoursesByAcademicSessions({
                    programId: this.program,
                    fromTermId: this.fromTerm,
                    toTermId: this.toTerm
                });
            }

            // Deduplicate by courseOfferingParticipantId at source before grouping
            const seenIds = new Set();
            const uniqueCourses = courses.filter(course => {
                const key = course.courseOfferingParticipantId || course.learningCourseName;
                if (seenIds.has(key)) return false;
                seenIds.add(key);
                return true;
            });
            this.filteredCourses = uniqueCourses;
            console.log('Filtered courses loaded (deduplicated):', this.filteredCourses);

        } catch (error) {
            console.error('Error loading filtered courses:', error);
            this.showToast('Error', 'Failed to load courses for selected terms', 'error');
            this.filteredCourses = [];
        } finally {
            this.isLoading = false;
        }
    }
    // Add this method to force UI refresh
    forceUIUpdate() {
        // Force a re-render by re-assigning the array
        this.filteredCourses = [...this.filteredCourses];
    }

    get hasFilteredCourses() {
        return this.filteredCourses && this.filteredCourses.length > 0;
    }

    get coursesByTerm() {
        if (!this.hasFilteredCourses) return [];

        const grouped = {};
        this.filteredCourses.forEach(course => {
            const termName = course.academicTermName || 'Unknown Term';
            if (!grouped[termName]) {
                grouped[termName] = { seenNames: new Set(), courses: [] };
            }
            // Deduplicate by course name within each term
            const courseName = course.learningCourseName || '';
            if (!grouped[termName].seenNames.has(courseName)) {
                grouped[termName].seenNames.add(courseName);
                grouped[termName].courses.push(course);
            }
        });

        return Object.keys(grouped).map(termName => ({
            termName: termName,
            courses: grouped[termName].courses
        }));
    }

    get fromTermLabel() {
        if (!this.fromTerm || !this.academicSessionOptions) return '';
        const term = this.academicSessionOptions.find(option => option.value === this.fromTerm);
        return term ? term.label : this.fromTerm;
    }

    get toTermLabel() {
        if (!this.toTerm || !this.academicSessionOptions) return '';
        const term = this.academicSessionOptions.find(option => option.value === this.toTerm);
        return term ? term.label : this.toTerm;
    }

    /*validatePrintDeliveryMode() {
        if (this.deliveryMode === 'Print') {
            const hasRequiredDocument = this.uploadedFiles.some(file => {
                const fileName = file.name.toLowerCase();
                const feeKeywords = ['fee', 'payment', 'receipt', 'transaction', 'bank', 'challan'];
                const idKeywords = ['id', 'identity', 'proof', 'document', 'passport', 'license', 'aadhar', 'pan', 'voter', 'driving'];
    
                return feeKeywords.some(keyword => fileName.includes(keyword)) ||
                    idKeywords.some(keyword => fileName.includes(keyword));
            });
    
            if (!hasRequiredDocument) {
                this.showToast(
                    'Document Required',
                    'For Print delivery mode, please upload either:\n• Fee payment receipt/reference\n• ID proof document (Passport, License, Aadhar, etc.)',
                    'warning'
                );
                return false;
            }
        }
        return true;
    }
    
    validatePrintDeliveryRequirements() {
        if (this.deliveryMode === 'Print') {
            const uploadedFileNames = this.uploadedFiles.map(file => file.name.toLowerCase());
    
            const hasFeeDocument = uploadedFileNames.some(name =>
                name.includes('fee') ||
                name.includes('payment') ||
                name.includes('receipt') ||
                name.includes('transaction') ||
                name.includes('bank') ||
                name.includes('challan')
            );
    
            const hasIdDocument = uploadedFileNames.some(name =>
                name.includes('id') ||
                name.includes('identity') ||
                name.includes('proof') ||
                name.includes('document') ||
                name.includes('passport') ||
                name.includes('license') ||
                name.includes('aadhar') ||
                name.includes('pan') ||
                name.includes('voter') ||
                name.includes('driving')
            );
    
            if (!hasFeeDocument && !hasIdDocument) {
                this.showToast(
                    'Document Required',
                    'For Print delivery mode, please upload either:\n• Fee payment receipt/reference\n• ID proof document (Passport, License, Aadhar, etc.)',
                    'warning'
                );
                return false;
            }
        }
        return true;
    }
    
        get showPrintDeliveryWarning() {
        return this.showAcademicRecordsFields &&
            this.deliveryMode === 'Print' &&
            this.uploadedFiles.length === 0;
    }*/

    handleFileChange(event) {
        const files = event.target.files;
        if (files.length > 0) {
            Array.from(files).forEach(file => {
                if (file.size > MAX_FILE_SIZE) {
                    this.showToast('Error', `File "${file.name}" exceeds maximum size of 5MB`, 'error');
                    return;
                }

                const isSignedVersion = this.isSignedVersion(file.name);
                const reader = new FileReader();
                reader.onload = () => {
                    const base64 = reader.result;
                    const fileData = {
                        id: Date.now() + Math.random(),
                        name: file.name,
                        type: file.type,
                        size: file.size,
                        base64: base64,
                        formattedSize: this.formatFileSize(file.size),
                        isPDF: file.type === 'application/pdf',
                        isImage: this.isImageFile(file.type, file.name),
                        isSignedVersion: isSignedVersion,
                        originalFileName: this.getOriginalFileName(file.name)
                    };
                    this.uploadedFiles = [...this.uploadedFiles, fileData];
                    this.showToast('Success', `File "${file.name}" added successfully`, 'success');
                };
                reader.onerror = () => {
                    this.showToast('Error', `Error reading file "${file.name}"`, 'error');
                };
                reader.readAsDataURL(file);
            });
        }
        event.target.value = '';
    }

    isSignedVersion(fileName) {
        const signedIndicators = ['signed', 'executed', 'completed', '_signed', '-signed'];
        const lowerFileName = fileName.toLowerCase();
        return signedIndicators.some(indicator => lowerFileName.includes(indicator));
    }

    getOriginalFileName(signedFileName) {
        const patterns = [
            /_signed(\.[^.]+)$/i,
            /-signed(\.[^.]+)$/i,
            /_executed(\.[^.]+)$/i,
            /-executed(\.[^.]+)$/i,
            /_completed(\.[^.]+)$/i,
            /-completed(\.[^.]+)$/i,
            /\s+signed(\.[^.]+)$/i,
            /\s+executed(\.[^.]+)$/i
        ];

        let originalName = signedFileName;
        patterns.forEach(pattern => {
            originalName = originalName.replace(pattern, '$1');
        });
        return originalName !== signedFileName ? originalName : null;
    }

    getFileIcon(fileName) {
        const extension = fileName.split('.').pop().toLowerCase();
        const iconMap = {
            'pdf': 'doctype:pdf',
            'doc': 'doctype:word',
            'docx': 'doctype:word',
            'png': 'doctype:image',
            'jpg': 'doctype:image',
            'jpeg': 'doctype:image'
        };
        return iconMap[extension] || 'doctype:unknown';
    }

    formatFileSize(bytes) {
        if (bytes === undefined || bytes === null || isNaN(bytes) || bytes < 0) {
            return 'Unknown size';
        }
        if (bytes === 0) return '0 Bytes';
        const k = 1024;
        const sizes = ['Bytes', 'KB', 'MB', 'GB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        const safeIndex = Math.min(i, sizes.length - 1);
        return parseFloat((bytes / Math.pow(k, safeIndex)).toFixed(2)) + ' ' + sizes[safeIndex];
    }

    handleRemoveFile(event) {
        event.preventDefault();
        event.stopPropagation();
        const fileId = event.currentTarget.dataset.id;
        if (fileId) {
            const fileName = this.uploadedFiles.find(f => f.id.toString() === fileId.toString())?.name;
            this.uploadedFiles = this.uploadedFiles.filter(file => file.id.toString() !== fileId.toString());
            this.showToast('Success', `File "${fileName}" removed successfully`, 'success');
        }
    }

    handlePreviewFile(event) {
        event.preventDefault();
        event.stopPropagation();
        const fileId = event.currentTarget.dataset.id;

        if (fileId) {
            const file = this.uploadedFiles.find(f => f.id.toString() === fileId.toString());
            if (file) {
                const isPDF = this.isPDFFile(file);
                const isImage = this.isImageFile(file.type, file.name);

                this.selectedFile = {
                    ...file,
                    // For local PDF, use base64
                    base64: file.base64,
                    iconname: this.getFileIcon(file.name),
                    ispdf: isPDF,
                    isimage: isImage,
                    formattedSize: file.formattedSize,
                    type: file.type,
                    useDistributionUrl: false // Don't use iframe for local base64 if it's blocked, or use object
                };
                this.showFilePreview = true;
            }
        }
    }

    isImageFile(fileType, fileName) {
        const imageTypes = ['image/jpeg', 'image/jpg', 'image/png', 'image/gif', 'image/webp', 'image/bmp', 'image/svg+xml'];
        const extension = fileName.split('.').pop().toLowerCase();
        return imageTypes.includes(fileType) || this.isImageFileByExtension(extension);
    }

    closeFilePreview(event) {
        if (event) {
            event.preventDefault();
            event.stopPropagation();
        }
        this.showFilePreview = false;
        this.selectedFile = null;
    }

    handleOpenInNewTab() {
        if (this.selectedFile && this.selectedFile.previewUrl) {
            window.open(this.selectedFile.previewUrl, '_blank');
        } else if (this.selectedFile && this.selectedFile.base64) {
            const newWindow = window.open();
            if (newWindow) {
                newWindow.document.write(`<iframe src="${this.selectedFile.base64}" frameborder="0" style="border:0; top:0px; left:0px; bottom:0px; right:0px; width:100%; height:100%;" allowfullscreen></iframe>`);
            }
        }
    }

    get hasCaseComments() {
        return this.caseComments && this.caseComments.length > 0;
    }

    get hasUserCourses() {
        return this.userCourses && this.userCourses.length > 0;
    }

    loadCaseComments(caseId) {
        getCaseComments({ caseId: caseId })
            .then(result => {
                this.caseComments = result.map(comment => ({
                    ...comment,
                    formattedDate: new Date(comment.CreatedDate).toLocaleString()
                }));
                this.showCommentSection = true;
            })
            .catch(error => {
                console.error('Error loading comments:', error);
                this.caseComments = [];
            });
    }

    handleCommentChange(event) {
        this.newCommentText = event.target.value;
    }

    async handleAddComment() {
        if (!this.newCommentText || this.newCommentText.trim() === '') {
            this.showToast('Warning', 'Please enter a comment', 'warning');
            return;
        }

        this.isLoading = true;
        try {
            await addCaseComment({
                caseId: this.recordId,
                commentBody: this.newCommentText,
                isPublished: false
            });

            this.newCommentText = '';
            this.loadCaseComments(this.recordId);
            this.showToast('Success', 'Comment added successfully', 'success');
        } catch (error) {
            this.showToast('Error', 'Failed to add comment: ' + error.body.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }


    handleDownloadFile(event) {
        event.preventDefault();
        event.stopPropagation();

        if (this.selectedFile && this.selectedFile.base64) {
            try {
                const link = document.createElement('a');
                link.href = this.selectedFile.base64;
                link.download = this.selectedFile.name;
                link.target = '_blank';
                document.body.appendChild(link);
                link.click();
                document.body.removeChild(link);
                this.showToast('Success', `Downloaded ${this.selectedFile.name}`, 'success');
            } catch (error) {
                console.error('Download error:', error);
                this.showToast('Error', 'Failed to download file', 'error');
            }
        }
    }

    handleOpenInNewTab(event) {
        event.preventDefault();
        event.stopPropagation();
        if (this.selectedFile && this.selectedFile.previewUrl) {
            window.open(this.selectedFile.previewUrl, '_blank');
        }
    }

    // Event & Budget Proposal Field Handlers
    handleEventTitleChange(event) {
        this.eventTitle = event.target.value;
    }

    handleEventProposedDateTimeChange(event) {
        this.eventProposedDateTime = event.target.value;
    }

    handleEventVenueChange(event) {
        this.eventVenue = event.target.value;
    }

    handleEventHostBodyChange(event) {
        this.eventHostBody = event.detail.value;  // Changed from event.target.value to event.detail.value
    }

    handleEventDescriptionChange(event) {
        this.eventDescription = event.target.value;
    }

    handleEventExpectedHeadcountChange(event) {
        this.eventExpectedHeadcount = event.target.value;
    }

    handleEventBudgetAskChange(event) {
        this.eventBudgetAsk = event.target.value;
    }

    handleEventContactsChange(event) {
        this.eventContacts = event.target.value;
    }

    // Validation for Event & Budget Proposal
    validateEventBudgetFields() {
        // Check all mandatory fields

        // Ensure program is selected if available
        if (!this.program && this.programOptions && this.programOptions.length > 0) {
            console.log('Program was empty, defaulting to first available program');
            this.program = this.programOptions[0].value;
            this.programName = this.programOptions[0].label;
        }

        if (!this.eventTitle || !this.program || !this.eventProposedDateTime ||
            !this.eventVenue || !this.eventHostBody || !this.eventDescription ||
            !this.eventExpectedHeadcount || !this.eventBudgetAsk || !this.eventContacts) {
            console.log("Program for Event", this.program);
            this.showToast('Error', 'Please fill all mandatory fields for Event & Budget Proposal', 'error');
            return false;
        }

        // Date validation - at least 15 days before event
        const proposedDate = new Date(this.eventProposedDateTime);
        const today = new Date();
        const minDate = new Date();
        minDate.setDate(today.getDate() + MIN_EVENT_DAYS);

        if (proposedDate <= minDate) {
            this.showToast('Error', `Event must be at least ${MIN_EVENT_DAYS} days from today`, 'error');
            return false;
        }

        // Date sanity check - not in past
        if (proposedDate < today) {
            this.showToast('Error', 'Event date cannot be in the past', 'error');
            return false;
        }

        // Budget validation - positive number
        // const budgetValue = parseFloat(this.eventBudgetAsk);
        // if (isNaN(budgetValue) || budgetValue <= 0) {
        //     this.showToast('Error', 'Budget Ask must be a positive number', 'error');
        //     return false;
        // }

        // Headcount validation - positive integer
        const headcountValue = parseInt(this.eventExpectedHeadcount, 10);
        if (isNaN(headcountValue) || headcountValue <= 0) {
            this.showToast('Error', 'Expected Headcount must be a positive number', 'error');
            return false;
        }

        return true;
    }

    handleInputChange(event) {
        const field = event.target.name;
        const value = event.target.value;

        switch (field) {
            case 'requestedEndDate':
                this.requestedEndDate = value;
                break;
            case 'subject':
                this.subject = value;
                break;
            case 'description':
                this.description = value;
                break;
            case 'program':
                this.program = value;
                const selectedProgram = this.programOptions.find(p => p.value === value);
                if (selectedProgram) {
                    this.programName = selectedProgram.label;

                    if (this.isLOARecordType || this.isExistingLOARecordType) {
                        if (this.programName === 'Post Graduate Programme in Management' ||
                            this.programName === 'Post Graduate Programme in Management for Young Leaders') {
                            this.loaType = 'None';
                        }
                    }
                }
                if (this.isRejoin) {
                    // Load cohorts for Rejoin
                    this.loadCohortsForRejoin();
                }
                // Always load academic sessions for From/To Term selection
                this.loadAcademicSessions();
                break;
            case 'cohort':
                this.selectedCohortId = value;
                break;
            case 'accountHolderName':
                this.caseAccountHolderName = value;
                console.log(this.caseAccountHolderName);

                break;
            case 'accountNumber':
                //this.caseAccountNumber = value; 
                this.accountNumber = value;

                break;
            case 'ifscCode':
                //this.caseIfscCode = value;
                this.ifscCode = value;

                break;
            case 'bankName':
                //this.caseBankName = value; 
                this.bankName = value;
                break;
            case 'branchName':
                //this.caseBranchName = value; 
                this.branchName = value;
                break;

            case 'wellbeingSeverity':
                this.wellbeingSeverity = value;
                break;
            case 'wellbeingModeOfInteraction':
                this.wellbeingModeOfInteraction = value;
                break;
            case 'wellbeingType':
                this.wellbeingType = value;
                break;
            case 'wellbeingActionTaken':
                this.wellbeingActionTaken = value;
                break;

            case 'fromTerm':
                this.fromTerm = value;
                // Clear validation message when term changes
                this.termValidationMessage = '';
                this.showTermValidation = false;

                setTimeout(() => {
                    if (this.toTerm) {
                        this.loadCoursesBySelectedTerms();
                        // Validate term overlap if applicable
                        this.validateTermOverlap();
                    }
                }, 0);
                break;

            case 'toTerm':
                this.toTerm = value;
                // Clear validation message when term changes
                this.termValidationMessage = '';
                this.showTermValidation = false;

                setTimeout(() => {
                    if (this.fromTerm) {
                        this.loadCoursesBySelectedTerms();
                        // Validate term overlap if applicable
                        this.validateTermOverlap();
                    }
                }, 0);
                break;
            case 'eventHostBody':
                this.eventHostBody = value;
                break;
            case 'completedTerm':
                this.completedTerm = value;
                break;
            case 'location':
                this.locationValue = value;
                break;
            case 'loaType':
                this.loaType = value;
                break;
            case 'documentType':
                this.documentType = value;
                break;
            case 'deliveryMode':
                this.deliveryMode = value;
                // Clear dispatch address if delivery mode changes from Print to something else
                if (value !== 'Print') {
                    this.dispatchAddress = '';
                }
                break;
            case 'dispatchAddress':
                this.dispatchAddress = value;
                break;
            case 'passportNumber':
                this.passportNumber = value;
                break;
            case 'passportExpiry':
                this.passportExpiry = value;
                break;
            case 'travelStartDate':
                this.travelStartDate = value;
                break;
            case 'travelEndDate':
                this.travelEndDate = value;
                break;
            case 'visaType':
                this.visaType = value;
                break;
            case 'visaPurpose':
                this.visaPurpose = value;
                break;
            case 'programYear':
                this.programYear = value;
                break;
            case 'requestedLegalName':
                this.requestedLegalName = value;
                break;
            case 'nameChangeReason':
                this.nameChangeReason = value;
                break;
            case 'alternateEmail':
                this.alternateEmail = value;
                break;
            case 'alternatePhone':
                this.alternatePhone = value;
                break;
            case 'severity':
                this.severity = value;
                break;
            case 'modeOfInteraction':
                this.modeOfInteraction = value;
                break;
            case 'typeField':
                this.typeField = value;
                break;
            case 'actionTaken':
                this.actionTaken = value;
                break;
            default:
                break;
        }
    }

    handleProgramYearChange(event) {
        this.programYear = event.detail.value;
    }

    handleRequestedLegalNameChange(event) {
        this.requestedLegalName = event.target.value;
    }

    handleNameChangeReasonChange(event) {
        this.nameChangeReason = event.target.value;
    }
    get isWellbeingRecordType() {
        return this.selectedRecordTypeLabel &&
            this.selectedRecordTypeLabel.toLowerCase().includes('wellbeing');
    }

    get isExistingWellbeingCase() {
        return this.caseRecordType &&
            this.caseRecordType.toLowerCase().includes('wellbeing');
    }

    get shouldShowWellbeingFields() {
        return this.isWellbeingRecordType;
    }

    get shouldShowWellbeingFieldsInCase() {
        return this.isExistingWellbeingCase;
    }
    // Add this getter to your JavaScript
    get shouldShowLoaTypeForWithdrawal() {
        // Don't show LOA Type for Withdrawal cases
        if (this.isWithdrawalCase) {
            return false;
        }
        return !this.hideLoaTypeForAcademicRecords &&
            !this.hideLoaTypeForVisaNoc &&
            !this.hideLoaTypeForGraduationWalk &&
            !this.hideLoaTypeForLoaRecords &&
            !this.showEventBudgetFields &&
            !this.isFeeExceptionCase;
    }

    validateRequestedEndDate() {
        if (!this.requestedEndDate) {
            return true; // Let required field validation handle empty case
        }

        const selectedDate = new Date(this.requestedEndDate);
        const today = new Date();

        // Reset time part for accurate date comparison
        today.setHours(0, 0, 0, 0);
        selectedDate.setHours(0, 0, 0, 0);

        if (selectedDate < today) {
            this.showToast('Error', 'Requested End Date cannot be in the past', 'error');
            return false;
        }

        return true;
    }
    async handleSubmit() {
        try {
            console.log('=== SUBMIT STARTED ===');
            console.log('SUBMIT: recordId =', this.recordId);
            console.log('SUBMIT: is existing case =', !!this.recordId);
            console.log('SUBMIT: caseRecordType =', this.caseRecordType);
            console.log('SUBMIT: isExistingWithdrawalCase =', this.isExistingWithdrawalCase);
            console.log('Is Loading?', this.isLoading);
            //onsole.log('accoutnHolderName?', this.caseAccountHolderName);

            // Debug all Academic Records fields
            if (this.showAcademicRecordsFields) {
                console.log('Academic Records Fields:', {
                    program: this.program,
                    documentType: this.documentType,
                    deliveryMode: this.deliveryMode,
                    dispatchAddress: this.dispatchAddress,
                    dispatchAddressLength: this.dispatchAddress?.length,
                    subject: this.computedSubject,
                    description: this.description
                });
            }

            // Update the Return and Replace validation:
            if (this.isReturnReplace) {
                if (!this.selectedReturnReplaceCourseId || !this.selectedCohortId ||
                    !this.description) {
                    this.showToast('Error', 'Please fill all required fields for Return and Replace', 'error');
                    return;
                }
            }
            if (this.isReturnReplace) {
                if (!this.selectedReturnReplaceCourseId || !this.selectedCohortId ||
                    !this.description) {
                    this.showToast('Error', 'Please fill all required fields for Return and Replace', 'error');
                    return;
                }
            }

            // In the handleSubmit method, add validation for Wellbeing fields
            if (this.isWellbeingRecordType) {
                if (!this.wellbeingActionTaken) {
                    this.showToast('Error', 'Please fill all required fields for Wellbeing request', 'error');
                    return;
                }
            }

            if (this.isReturnReplace) {
                if (!this.selectedReturnReplaceCourseId ||
                    !this.selectedCohortId || !this.description) {
                    this.showToast('Error', 'Please fill all required fields for Return and Replace', 'error');
                    return;
                }
            }
            // If it's an attendance exception case
            if (this.showAttendanceExceptionFields) {
                console.log('selectedSessionId', this.selectedSessionId);
                console.log('selectedCourseId', this.selectedCourseId);
                console.log('extractedDateOfAbsence', this.extractedDateOfAbsence);
                console.log('attendanceExceptionReason', this.attendanceExceptionReason);
                console.log('subject', this.subject);
                console.log('description', this.description);
                if (!this.selectedSessionId || !this.extractedDateOfAbsence ||
                    !this.attendanceExceptionReason || !this.subject || !this.description) {
                    this.showToast('Error', 'Please fill all required fields for Attendance Exception', 'error');
                    return;
                }

                // Validate date of absence based on reason
                const validationError = this.validateAttendanceExceptionDate();
                if (validationError) {
                    this.showToast('Validation Error', validationError, 'error');
                    return;
                }

                this.isLoading = true;
                try {
                    const courseAttendanceId = this.getCourseAttendanceId();
                    const selectedCourseName = this.getSelectedCourseName;
                    const selectedSessionKey = this.getSelectedSessionKey;

                    if (!courseAttendanceId) {
                        this.showToast('Error', 'Could not find Course Attendance record. Please try again.', 'error');
                        this.isLoading = false;
                        return;
                    }

                    //Attendance Duplicacy check Sid - START
                    // Check for duplicate attendance exception case

                    try {
                        console.log('=== DUPLICATE CHECK START ===');
                        console.log('Contact ID:', this.contactId);
                        console.log('Date of Absence:', this.extractedDateOfAbsence);
                        console.log('Session Key:', this.selectedSessionKey);
                        console.log('Learning Course Name:', selectedCourseName);

                        // Extract just the date portion from the session key
                        // Session key format: "2026-02-09 | | D | | 10:00 AM"
                        // We need just: "2026-02-09"
                        let dateOnly = this.extractedDateOfAbsence;
                        if (this.extractedDateOfAbsence && this.extractedDateOfAbsence.includes(' | ')) {
                            dateOnly = this.extractedDateOfAbsence.split(' | ')[0].trim();
                        }
                        console.log('Extracted date only:', dateOnly);

                        const duplicateCheckResult = await checkDuplicateAttendanceException({
                            contactId: this.contactId,
                            dateOfAbsence: dateOnly,
                            sessionKey: this.selectedSessionKey,
                            learningCourseName: selectedCourseName
                        });

                        console.log('Duplicate check result:', duplicateCheckResult);
                        console.log('Is Duplicate?', duplicateCheckResult.isDuplicate);

                        if (duplicateCheckResult.isDuplicate) {
                            this.isLoading = false;
                            console.log('DUPLICATE FOUND - Blocking case creation');
                            this.showToast(
                                'Duplicate Case Found',
                                `An Attendance Exception case already exists with the same details.\n` +
                                `Case Number: ${duplicateCheckResult.existingCaseNumber}\n` +
                                `Status: ${duplicateCheckResult.existingCaseStatus}\n` +
                                `Subject: ${duplicateCheckResult.existingCaseSubject}\n\n` +
                                `Please check your existing cases before creating a new one.`,
                                'error'
                            );
                            return;
                        }

                        console.log('No duplicate found - Proceeding with case creation');
                    } catch (duplicateCheckError) {
                        console.error('Error checking for duplicate:', duplicateCheckError);
                        console.error('Error details:', duplicateCheckError.body?.message || duplicateCheckError.message);
                        // Continue with case creation even if duplicate check fails
                        // You can uncomment the line below to stop case creation if duplicate check fails
                        // this.showToast('Error', 'Error checking for duplicate cases: ' + duplicateCheckError.body?.message, 'error');
                        // this.isLoading = false;
                        // return;
                    }

                    //Attendance Duplicacy check Sid - END

                    // Create case using the standard createLOACase method
                    const caseData = {
                        contactId: this.contactId,
                        accountId: this.accountId,
                        subject: this.subject,
                        description: this.description,

                        recordTypeId: this.selectedRecordTypeId,
                        programId: this.program,
                        attendanceExceptionReason: this.attendanceExceptionReason,
                        courseAttendanceId: courseAttendanceId,
                        sessionAttendanceId: this.selectedSessionId,
                        sessionKey: this.selectedSessionKey,
                        courseName: selectedCourseName, // Pass course name
                        sessionName: selectedSessionKey, // Pass session key as session name
                        cohortId: this.selectedCohortId,
                        accountHolderName: this.caseAccountHolderName,
                        accountNumber: this.caseAccountNumber,
                        ifscCode: this.caseIfscCode,
                        bankName: this.caseBankName,
                        branchName: this.caseBranchName,
                        subType: this.selectedSubType,
                        documentType: this.documentType,
                        deliveryMode: this.deliveryMode,
                        dispatchAddress: this.dispatchAddress
                    };

                    const caseId = await createLOACase({ caseData: caseData });
                    this.caseId = caseId;

                    if (this.uploadedFiles.length > 0) {
                        await this.uploadFilesToCase(caseId);
                    }

                    this.resetForm();
                    this.showToast('Success', 'Attendance Exception request submitted successfully!', 'success');
                    //Sid - redirect to newly created case detail
                    this.navigateToCaseDetail(caseId);
                    //Sid

                } catch (error) {
                    console.error('Error submitting attendance exception:', error);
                    this.showToast('Error', 'Error submitting attendance exception: ' + (error.body?.message || error.message), 'error');
                } finally {
                    this.isLoading = false;
                }
                return;
            }

            if (this.recordId) {
                console.log('SUBMIT: Processing existing case scenario');
                // Existing case scenario - handle file upload and terms/financial statements
                // In the handleSubmit method, update the bank details validation:
                if (this.shouldShowBankDetails) {
                    /* if (!this.caseAccountHolderName || !this.caseAccountNumber || !this.caseIfscCode ||
                         !this.caseBankName || !this.caseBranchName) {
                         this.showToast('Error', 'Please fill all bank account details', 'error');
                         return;
                     }*/
                    // Add this validation check
                    if (this.caseAccountHolderName && this.caseAccountHolderName.trim().length < 3) {
                        this.showToast('Error', 'Account Holder Name must be at least 3 characters', 'error');
                        return;
                    }

                    // Validate IFSC code format (11 characters)
                    if (this.caseIfscCode && this.caseIfscCode.length !== 11) {
                        this.showToast('Error', 'IFSC code must be 11 characters', 'error');
                        return;
                    }

                    // Validate account number (at least 9 digits)
                    if (this.caseAccountNumber && !/^\d{9,}$/.test(this.caseAccountNumber)) {
                        this.showToast('Error', 'Account number must be at least 9 digits', 'error');
                        return;
                    }
                }
                console.log('3336');
                // Validate Terms and Conditions section if visible
                if (this.showTermsSection) {
                    if (!this.termsAccepted && (!this.termsReason || this.termsReason.trim() === '')) {
                        this.showToast('Warning', 'Please provide a reason for rejecting the terms and conditions.', 'warning');
                        return;
                    }
                }

                // Validate Financial Statement section if visible
                if (this.showFinancialStatementSection) {
                    /*  if (!this.financialStatementAccepted && !this.financialStatementRejected) {
                          this.showToast('Warning', 'Please select either Accept or Reject for the financial statement requirement.', 'warning');
                          return;
                      }*/

                    if (this.financialStatementRejected && (!this.financialStatementReason || this.financialStatementReason.trim() === '')) {
                        this.showToast('Warning', 'Please provide a reason for rejecting the financial statement.', 'warning');
                        return;
                    }
                }
                console.log(this.showTermsSection);
                console.log(this.showFinancialStatementSection);
                console.log(this.caseAccountHolderName);
                this.isLoading = true;
                try {
                    let hasProcessedTerms = false;
                    let hasProcessedFinancial = false;
                    let hasUploadedFiles = false;
                    /** Added as accountHoldeerName was geeting overrident by SHowTermSection By SID */
                    if (this.shouldShowBankDetails) {
                        console.log('BANK DETAILS UPDATE: Starting bank details update');
                        console.log('BANK DETAILS UPDATE: accoutnHolderName =', this.caseAccountHolderName);
                        console.log('BANK DETAILS UPDATE: shouldShowBankDetails =', this.shouldShowBankDetails);
                        console.log('BANK DETAILS UPDATE: showBankDetailsSection =', this.showBankDetailsSection);
                        console.log('BANK DETAILS UPDATE: caseRecordType =', this.caseRecordType);
                        console.log('BANK DETAILS UPDATE: isExistingWithdrawalCase =', this.isExistingWithdrawalCase);
                        try {
                            console.log('DEBUG - Updating bank details for existing case');
                            console.log('this.caseAccountNumber ' + this.caseAccountNumber);
                            console.log('this.AccountNumber ' + this.accountNumber);
                            console.log('this.caseAccountNumber ' + this.caseIfscCode);
                            console.log('this.caseAccountNumber ' + this.caseBankName);
                            console.log('DEBUG - END');

                            const bankCaseData = {
                                caseId: this.recordId,
                                accountHolderName: this.caseAccountHolderName,
                                accountNumber: this.accountNumber,
                                ifscCode: this.ifscCode,
                                bankName: this.bankName,
                                branchName: this.branchName

                            };
                            console.log('DEBUG - Bank case data:', JSON.stringify(bankCaseData));

                            const bankUpdateResult = await createLOACase({
                                caseData: bankCaseData
                            });

                            console.log('DEBUG - Bank details update result:', bankUpdateResult);
                            this.showToast('Success', 'Bank details updated successfully', 'success');
                        } catch (error) {
                            this.showToast('Error', 'Failed to update bank details: ' + error.body?.message, 'error');
                            this.isLoading = false;
                            return;
                        }
                    }

                    // Process Terms and Conditions first if required
                    if (this.showTermsSection) {
                        try {
                            await this.handleAcceptTerms(this.termsAccepted, this.termsReason);
                            hasProcessedTerms = true;
                            this.showTermsSection = false;
                            this.requiresTermsAndConditions = false;
                        } catch (error) {
                            this.showToast('Error', 'Failed to process terms and conditions: ' + error.body?.message, 'error');
                            this.isLoading = false;
                            return;
                        }
                    }

                    // Process Financial Statement if required
                    if (this.showFinancialStatementSection) {
                        try {
                            const financialResult = await acceptFinancialStatement({
                                caseId: this.recordId,
                                isAccepted: this.financialStatementAccepted,
                                reason: this.financialStatementReason
                            });

                            this.showToast('Success', financialResult, 'success');
                            hasProcessedFinancial = true;
                            this.showFinancialStatementSection = false;
                            this.requiresFinancialStatement = false;

                            // Reload case details to update status
                            this.loadCaseDetails(this.recordId);
                        } catch (error) {
                            this.showToast('Error', 'Failed to process financial statement: ' + error.body?.message, 'error');
                            this.isLoading = false;
                            return;
                        }
                    }
                    console.log('3400');
                    // Process Bank Details update if required
                    console.log('SUBMIT: About to check shouldShowBankDetails');
                    console.log('SUBMIT: shouldShowBankDetails =', this.shouldShowBankDetails);
                    console.log('SUBMIT: showBankDetailsSection =', this.showBankDetailsSection);
                    /*if (this.shouldShowBankDetails) {
                        console.log('BANK DETAILS UPDATE: Starting bank details update');
                        console.log('BANK DETAILS UPDATE: accoutnHolderName =', this.caseAccountHolderName);
                        console.log('BANK DETAILS UPDATE: shouldShowBankDetails =', this.shouldShowBankDetails);
                        console.log('BANK DETAILS UPDATE: showBankDetailsSection =', this.showBankDetailsSection);
                        console.log('BANK DETAILS UPDATE: caseRecordType =', this.caseRecordType);
                        console.log('BANK DETAILS UPDATE: isExistingWithdrawalCase =', this.isExistingWithdrawalCase);
                        try {
                            console.log('DEBUG - Updating bank details for existing case');
                             console.log('this.caseAccountNumber '+this.caseAccountNumber);
                              console.log('this.AccountNumber '+this.accountNumber);
                             console.log('this.caseAccountNumber '+this.caseIfscCode);
                             console.log('this.caseAccountNumber '+this.caseBankName);
                             console.log('DEBUG - END');
                            
                            const bankCaseData = {
                                caseId: this.recordId,
                                accountHolderName: this.caseAccountHolderName,
                                 accountNumber: this.accountNumber, 
                                 ifscCode: this.ifscCode, 
                                 bankName: this.bankName, 
                                 branchName: this.branchName 
                               
                            };
                            console.log('DEBUG - Bank case data:', JSON.stringify(bankCaseData));
                            
                            const bankUpdateResult = await createLOACase({
                                caseData: bankCaseData
                            });
                            
                            console.log('DEBUG - Bank details update result:', bankUpdateResult);
                            this.showToast('Success', 'Bank details updated successfully', 'success');
                        } catch (error) {
                            this.showToast('Error', 'Failed to update bank details: ' + error.body?.message, 'error');
                            this.isLoading = false;
                            return;
                        }
                    }*/

                    // Upload files if any
                    if (this.uploadedFiles.length > 0) {
                        try {
                            await this.uploadFilesToCase(this.recordId);
                            hasUploadedFiles = true;
                            this.uploadedFiles = [];
                        } catch (error) {
                            this.showToast('Error', 'Failed to upload files: ' + error.body?.message, 'error');
                            this.isLoading = false;
                            return;
                        }
                    }

                    // Show appropriate success message
                    if (hasProcessedTerms && hasProcessedFinancial && hasUploadedFiles) {
                        this.showToast('Success', 'Terms, financial statement, and documents processed successfully!', 'success');
                    } else if (hasProcessedTerms && hasProcessedFinancial) {
                        this.showToast('Success', 'Terms and financial statement processed successfully!', 'success');
                    } else if (hasProcessedTerms && hasUploadedFiles) {
                        this.showToast('Success', 'Terms and documents processed successfully!', 'success');
                    } else if (hasProcessedFinancial && hasUploadedFiles) {
                        this.showToast('Success', 'Financial statement and documents processed successfully!', 'success');
                    } else if (hasProcessedTerms) {
                        this.showToast('Success', 'Terms and conditions processed successfully!', 'success');
                    } else if (hasProcessedFinancial) {
                        this.showToast('Success', 'Financial statement processed successfully!', 'success');
                    } else if (hasUploadedFiles) {
                        this.showToast('Success', 'Documents uploaded successfully!', 'success');
                    } else {
                        this.showToast('Success', 'Case updated successfully!', 'success');
                    }
                    //Sid - STAY on the case detail page and refresh data (No redirect to list)
                    this.checkForExistingCase();
                    if (this.recordId) {
                        this.loadCaseComments(this.recordId);
                    }
                    //Sid

                } catch (error) {
                    this.resultMessage = 'Error processing request: ' + (error.body ? error.body.message : error.message);
                    this.showToast('Error', this.resultMessage, 'error');
                } finally {
                    this.isLoading = false;
                }
                return;
            }

            // New case scenario
            if (!this.selectedRecordTypeId) {
                this.showToast('Error', 'Please select a request type first', 'error');
                return;
            }
            // if (this.shouldValidateTermOverlap && this.fromTerm && this.toTerm) {
            //     const termValidation = await this.validateTermOverlap();
            //     if (!termValidation.isValid) {
            //         this.showToast('Term Overlap Error', termValidation.message, 'error');
            //         return;
            //     }
            // }
            if (this.isRejoin && !this.selectedRejoinCaseId) {
                this.showToast('Error', 'Please select a case to rejoin', 'error');
                return;
            }

            if (this.isFeeExceptionCase) {
                if (!this.requestedEndDate || !this.description) {
                    this.showToast('Error', 'Please fill all required fields for Fee Exception request', 'error');
                    return;
                }

                // Add date validation for Fee Exception
                if (!this.validateRequestedEndDate()) {
                    return;
                }
            }
            // Event & Budget Proposal validation
            else if (this.showEventBudgetFields) {
                const isValidEvent = this.validateEventBudgetFields();
                if (!isValidEvent) {
                    return;
                }
            } else if (this.isWithdrawalCase) {
                if (!this.description || !this.program ||
                    !this.fromTerm || !this.toTerm) {
                    this.showToast('Error', 'Please fill all required fields', 'error');
                    return;
                }



                // Validate IFSC code format (11 characters)
                if (this.ifscCode && this.ifscCode.length !== 11) {
                    this.showToast('Error', '** IFSC code must be 11 characters', 'error');
                    return;
                }

                // Validate account number (at least 9 digits)
                if (this.accountNumber && !/^\d{9,}$/.test(this.accountNumber)) {
                    this.showToast('Error', 'Account number must be at least 9 digits', 'error');
                    return;
                }
            } else if (this.isLOACase) {
                // Standard LOA validation (only for non-Event cases)
                if (!this.description || !this.program ||
                    !this.fromTerm || !this.toTerm) {
                    this.showToast('Error', 'Please fill all required fields', 'error');
                    return;
                }

                if (this.shouldShowAcademicSessionFields) {
                    if (!this.fromTerm || !this.toTerm) {
                        this.showToast('Error', 'Please select From Term and To Term', 'error');
                        return;
                    }
                }
            }

            // Other validations for different case types
            // if (this.showAcademicRecordsFields && this.deliveryMode === 'Print') {
            //     const isValidPrintDelivery = this.validatePrintDeliveryRequirements();
            //     if (!isValidPrintDelivery) {
            //         return;
            //     }
            // }
            if (this.recordId && this.isCaseClosed) {
                this.showToast('Error', 'This case is closed and cannot be modified.', 'error');
                return;
            }
            else if (this.showNameChangeFields) {
                if (!this.requestedLegalName || !this.nameChangeReason) {
                    this.showToast('Error', 'Please fill all required fields for Name Change request', 'error');
                    return;
                }
            }
            // In handleSubmit method, update the Academic Records validation section:
            //     // In handleSubmit method, update the validation for Academic Records:
            // // Replace the entire Academic Records validation block with:
            // else if (this.showAcademicRecordsFields) {
            //     console.log('Validating Academic Records fields...');

            //     if (!this.program || !this.documentType || !this.deliveryMode) {
            //         this.showToast('Error', 'Please fill all required fields for Academic Records request', 'error');
            //         return;
            //     }

            //     console.log('Delivery Mode:', this.deliveryMode);
            //     console.log('Dispatch Address:', this.dispatchAddress);

            //     // Validate dispatch address for Print delivery
            //     if (this.deliveryMode === 'Print') {
            //         // Check if dispatchAddress exists and is valid
            //         if (!this.dispatchAddress || this.dispatchAddress.trim() === '') {
            //             this.showToast('Error', 'Please provide Dispatch Address for Print delivery mode', 'error');
            //             return;
            //         }

            //         // Validate dispatch address format (minimum 10 characters)
            //         if (this.dispatchAddress && this.dispatchAddress.trim().length < 10) {
            //             this.showToast('Error', 'Please provide a complete dispatch address (minimum 10 characters)', 'error');
            //             return;
            //         }
            //     }
            // }
            else if (this.showVisaNocFields) {
                if (!this.passportNumber || !this.passportExpiry ||
                    !this.travelStartDate || !this.travelEndDate || !this.visaType || !this.visaPurpose) {
                    this.showToast('Error', 'Please fill all required fields for Visa NOC request', 'error');
                    return;
                }
                if (this.travelStartDate > this.travelEndDate) {
                    this.showToast('Error', 'Travel Start date cannot be greater than Travel End date', 'error');
                    return;
                }
            }

            this.isLoading = true;

            try {
                if (this.shouldShowAcademicSessionFields && !this.showEventBudgetFields && !this.isFeeExceptionCase) {
                    const validationResult = await validateStudentEnrollment({
                        contactId: this.contactId,
                        programId: this.program,
                        fromTermId: this.fromTerm,
                        toTermId: this.toTerm
                    });

                    if (!validationResult.isValid) {
                        this.showToast('Validation Error', validationResult.message, 'error');
                        this.isLoading = false;
                        return;
                    }

                    const existingCaseValidation = await validateExistingCases({
                        contactId: this.contactId,
                        fromTermId: this.fromTerm,
                        toTermId: this.toTerm,
                        recordTypeId: this.selectedRecordTypeId
                    });

                    if (!existingCaseValidation.isValid) {
                        this.showToast('Validation Error', existingCaseValidation.message, 'error');
                        this.isLoading = false;
                        return;
                    }
                }

                // Check for open cases for specific record types
                const recordTypesToCheck = ['attendance exception', 'event', 'general support'];
                const shouldCheckOpenCase = recordTypesToCheck.some(type =>
                    this.selectedRecordTypeLabel && this.selectedRecordTypeLabel.toLowerCase().includes(type)
                );

                if (this.selectedRecordTypeLabel &&
                    (this.selectedRecordTypeLabel.toLowerCase().includes('general support') ||
                        this.selectedRecordTypeLabel.toLowerCase().includes('general'))) {

                    if (this.selectedSubType) {
                        const generalSupportValidation = await validateGeneralSupportOpenCase({
                            contactId: this.contactId,
                            recordTypeId: this.selectedRecordTypeId,
                            subType: this.selectedSubType
                        });

                        if (!generalSupportValidation.isValid) {
                            this.showToast('Duplicate Request', generalSupportValidation.message, 'error');
                            this.isLoading = false;
                            return;
                        }
                    }
                }
                // For other record types, use the general validation
                else if (shouldCheckOpenCase) {
                    const openCaseValidation = await validateOpenCaseByRecordType({
                        contactId: this.contactId,
                        recordTypeId: this.selectedRecordTypeId
                    });

                    if (!openCaseValidation.isValid) {
                        this.showToast('Duplicate Request', openCaseValidation.message, 'error');
                        this.isLoading = false;
                        return;
                    }
                }

                console.log('BANK DEBUG: About to create caseData for existing case update');
                console.log('BANK DEBUG: caseAccountHolderName =', this.caseAccountHolderName);
                console.log('BANK DEBUG: caseAccountNumber =', this.caseAccountNumber);
                console.log('BANK DEBUG: caseIfscCode =', this.caseIfscCode);
                console.log('BANK DEBUG: caseBankName =', this.caseBankName);
                console.log('BANK DEBUG: caseBranchName =', this.caseBranchName);

                const caseData = {
                    userId: this.currentUserId,
                    contactId: this.contactId,
                    accountId: this.accountId,
                    subject: this.showEventBudgetFields ? this.eventTitle : this.computedSubject,
                    description: this.showEventBudgetFields ? this.eventDescription : this.description,
                    caseType: null,
                    wellbeingSeverity: this.wellbeingSeverity,
                    wellbeingModeOfInteraction: this.wellbeingModeOfInteraction,
                    wellbeingType: this.wellbeingType,
                    wellbeingActionTaken: this.wellbeingActionTaken,
                    accountHolderName: this.caseAccountHolderName,
                    accountNumber: this.caseAccountNumber,
                    ifscCode: this.caseIfscCode,
                    bankName: this.caseBankName,
                    branchName: this.caseBranchName,
                    programId: this.program,
                    fromTermId: this.fromTerm,
                    toTermId: this.toTerm,
                    contactEmail: this.email,
                    contactPhone: this.phone,
                    recordTypeId: this.selectedRecordTypeId,
                    parentId: this.isRejoin ? this.selectedRejoinCaseId : null,
                    loaType: this.loaType,
                    subType: this.selectedSubType,
                    subCategory: this.selectedSubCategory,
                    documentType: this.documentType,
                    deliveryMode: this.deliveryMode,
                    requestedEndDate: this.requestedEndDate,
                    //wellbeingSeverity:this.wellbeingSeverity,
                    //wellbeingModeOfInteraction : this.wellbeingModeOfInteraction,
                    // wellbeingType: this.wellbeingType,
                    // wellbeingActionTaken: this.wellbeingActionTaken,
                    passportNumber: this.passportNumber,
                    passportExpiry: this.passportExpiry,
                    travelStartDate: this.travelStartDate,
                    travelEndDate: this.travelEndDate,
                    visaType: this.visaType,
                    visaPurpose: this.visaPurpose,
                    requestedLegalName: this.requestedLegalName,
                    nameChangeReason: this.nameChangeReason,
                    // Event & Budget fields
                    eventTitle: this.eventTitle,
                    eventProposedDateTime: this.eventProposedDateTime,
                    eventVenue: this.eventVenue,
                    eventHostBody: this.eventHostBody,
                    eventExpectedHeadcount: this.eventExpectedHeadcount,
                    eventBudgetAsk: this.eventBudgetAsk,
                    eventContacts: this.eventContacts,
                    cohortId: this.selectedCohortId,
                    alternateEmail: this.alternateEmail,
                    alternatePhone: this.alternatePhone,
                    selectedReturnReplaceCourseId: this.selectedReturnReplaceCourseId,
                    //Sid - Only pass currentAcademicTerm for case types that require it (LOA, Withdrawal, Rejoin, etc.)
                    // General Support cases have a lookup filter on Academic_Term__c that rejects ProgramEnrollment-sourced term IDs
                    // For Rejoin cases, use the selected cohort instead of the current ProgramEnrollment term
                    currentAcademicTerm: (this.selectedRecordTypeLabel &&
                        (this.selectedRecordTypeLabel.toLowerCase().includes('general support') ||
                            this.selectedRecordTypeLabel.toLowerCase().includes('general') ||
                            this.selectedRecordTypeLabel.toLowerCase().includes('event') ||
                            this.selectedRecordTypeLabel.toLowerCase().includes('budget') ||
                            this.selectedRecordTypeLabel.toLowerCase().includes('attendance')))
                        ? null
                        : (this.isRejoin && this.selectedCohortId ? this.selectedCohortId : this.currentAcademicTerm)
                    //Sid
                };
                console.log('DEBUG - Case data being sent to Apex:', JSON.stringify(caseData));
                console.log('DEBUG - Bank details in caseData:');
                console.log('  accountHolderName:', caseData.accountHolderName);
                console.log('  accountNumber:', caseData.accountNumber);
                console.log('  ifscCode:', caseData.ifscCode);
                console.log('  bankName:', caseData.bankName);
                console.log('  branchName:', caseData.branchName);
                console.log('DEBUG - Record type ID:', this.selectedRecordTypeId);
                console.log('DEBUG - Record type label:', this.selectedRecordTypeLabel);
                console.log('DEBUG - Is existing case:', !!this.recordId);
                console.log('DEBUG - Case ID (if existing):', this.recordId);
                const targetCaseId = await createLOACase({
                    caseData: caseData
                });

                this.caseId = targetCaseId;
                console.log('Case created successfully with ID:');

                // Show success toast for case creation - specific to Academic Records
                if (this.showAcademicRecordsFields) {
                    this.showToast('Success', `Case created successfully!`, 'success');
                    /*  let academicRecordsMessage = `Academic Records request created successfully!\n\nCase ID: ${targetCaseId}`;
                      academicRecordsMessage += `\nDocument Type: ${this.documentType}`;
                      academicRecordsMessage += `\nDelivery Mode: ${this.deliveryMode}`;
  
                      if (this.deliveryMode === 'Print' && this.dispatchAddress) {
                          academicRecordsMessage += `\nDispatch Address: Saved`;
                      }
  
                      this.showToast('Academic Records Request Created!', academicRecordsMessage, 'success'); */
                }
                //else {
                // Generic success toast for other record types
                // this.showToast('Success', `Case created successfully!`, 'success');
                // }

                if (this.uploadedFiles.length > 0) {
                    await this.uploadFilesToCase(targetCaseId);
                }

                let successMessage = `${this.selectedRecordTypeLabel} Request submitted successfully!`;
                if (this.isRejoin && this.selectedRejoinCaseNumber) {
                    successMessage += ` (Linked to Case: ${this.selectedRejoinCaseNumber})`;
                }

                if (this.uploadedFiles.length > 0) {
                    successMessage += ` with ${this.uploadedFiles.length} attached file(s)`;
                }

                this.resetForm();
                this.resultMessage = successMessage;
                this.showToast('Success', `${this.selectedRecordTypeLabel} Request submitted successfully!`, 'success');
                //Sid - redirect to newly created case detail
                this.navigateToCaseDetail(targetCaseId);
                //Sid

            } catch (error) {
                this.resultMessage = 'Error processing request: ' + (error.body ? error.body.message : error.message);
                this.showToast('Error', this.resultMessage, 'error');
            } finally {
                this.isLoading = false;
            }
        } catch (error) {
            // Catch any uncaught errors from the entire handleSubmit method
            console.error('Uncaught error in handleSubmit:', error);
            this.showToast('Error', 'An unexpected error occurred: ' + (error.body?.message || error.message || error.toString()), 'error');
            this.isLoading = false;
        }
    }

    async uploadFilesToCase(caseId) {
        const filesToUpload = this.uploadedFiles.map(file => {
            const base64Data = file.base64.includes(',') ? file.base64.split(',')[1] : file.base64;
            return {
                fileName: file.name,
                base64Data: base64Data,
                contentType: file.type
            };
        });

        try {
            await saveFiles({
                parentId: caseId,
                files: filesToUpload
            });
            this.showToast('Success', `${filesToUpload.length} file(s) attached successfully`, 'success');
        } catch (error) {
            this.showToast('Error', 'Error uploading files: ' + (error.body ? error.body.message : error.message), 'error');
        }
    }

    async checkTermsAndConditions() {
        // Only check for existing cases
        if (!this.recordId) {
            console.log('No recordId - skipping terms check for new case');
            this.showTermsSection = false;
            return;
        }

        try {
            console.log('=== Checking terms and conditions for case:', this.recordId);
            console.log('Current case status:', this.caseStatus);
            console.log('Current case status label:', this.caseStatusLabel);
            console.log('Current case record type:', this.caseRecordType);
            console.log('Is Withdrawal case:', this.isExistingWithdrawalCase);
            console.log('TermsCondition field:', this.caseTermsCondition);
            console.log('Has terms data:', !!this.termsAndConditionsData);

            // Get fresh data from server for LOA cases
            if (this.isExistingLOARecordType) {
                this.requiresTermsAndConditions = await requiresTermsAndConditions({
                    caseId: this.recordId
                });
                console.log('LOA - requiresTermsAndConditions result:', this.requiresTermsAndConditions);
            } else {
                this.requiresTermsAndConditions = false;
            }

            // LOGIC FOR WITHDRAWAL CASES:
            // Show terms section for Withdrawal cases when:
            // 1. Status is 'Approved11' OR 'Approved-Pending T&C' 
            // 2. TermsCondition__c is TRUE
            // 3. We have terms and conditions data
            if (this.isExistingWithdrawalCase) {
                const isApprovedPending = this.caseStatus === 'Approved11' ||
                    this.caseStatusLabel === 'Approved-Pending T&C';

                console.log('Withdrawal case check:', {
                    isApprovedPending: isApprovedPending,
                    termsCondition: this.caseTermsCondition,
                    hasTermsData: !!this.termsAndConditionsData,
                    caseStatus: this.caseStatus,
                    caseStatusLabel: this.caseStatusLabel
                });

                this.showTermsSection = isApprovedPending &&
                    this.caseTermsCondition === true &&
                    this.termsAndConditionsData &&
                    this.termsAndConditionsData.length > 0;
            }
            // LOGIC FOR LOA CASES:
            // Show terms section for LOA cases when:
            // 1. Apex method returns true (status is Approved/Approved11 AND TermsCondition__c is true AND record type contains 'LOA')
            // 2. We have terms and conditions data
            else if (this.isExistingLOARecordType) {
                this.showTermsSection = this.requiresTermsAndConditions &&
                    this.termsAndConditionsData &&
                    this.termsAndConditionsData.length > 0;
            } else {
                this.showTermsSection = false;
            }

            console.log('Final showTermsSection:', this.showTermsSection, {
                isWithdrawal: this.isExistingWithdrawalCase,
                isLOA: this.isExistingLOARecordType,
                caseStatus: this.caseStatus,
                caseStatusLabel: this.caseStatusLabel,
                termsCondition: this.caseTermsCondition,
                hasTermsData: !!this.termsAndConditionsData,
                requiresTermsFromApex: this.requiresTermsAndConditions
            });

            // Reset terms acceptance state when showing section
            if (this.showTermsSection) {
                this.termsAccepted = false;
                this.termsReason = '';
            }

        } catch (error) {
            console.error('Error checking terms and conditions:', error);
            console.error('Error details:', error.body?.message || error.message);
            this.showTermsSection = false;
        }
    }


    async handleAcceptTerms(isAccepted, reason) {
        return new Promise((resolve, reject) => {
            this.isLoading = true;
            acceptTermsAndConditions({
                caseId: this.recordId,
                isAccepted: isAccepted,
                reason: reason
            })
                .then(result => {
                    this.showToast('Success', result, 'success');
                    this.showTermsSection = false;
                    this.requiresTermsAndConditions = false;
                    this.loadCaseDetails(this.recordId);
                    resolve(true);
                })
                .catch(error => {
                    this.showToast('Error', error.body?.message || error.message, 'error');
                    if (isAccepted) {
                        this.termsAccepted = false;
                    }
                    reject(error);
                })
                .finally(() => {
                    this.isLoading = false;
                });
        });
    }

    handleTermsCheckboxChange(event) {
        this.termsAccepted = event.target.checked;

        // Clear reason when accepting
        if (this.termsAccepted) {
            this.termsReason = '';
        }
    }

    handleTermsReasonChange(event) {
        this.termsReason = event.target.value;
    }
    get formattedOverlappingCases() {
        if (!this.overlappingCases || this.overlappingCases.length === 0) {
            return [];
        }

        return this.overlappingCases.map(caseInfo => {
            let overlapTypeLabel = '';
            switch (caseInfo.overlapType) {
                case 'within':
                    overlapTypeLabel = 'Selected terms are completely within existing range';
                    break;
                case 'contains':
                    overlapTypeLabel = 'Selected terms completely contain existing range';
                    break;
                case 'start':
                    overlapTypeLabel = 'From Term overlaps with existing range';
                    break;
                case 'end':
                    overlapTypeLabel = 'To Term overlaps with existing range';
                    break;
                case 'partial':
                    overlapTypeLabel = 'Partial overlap with existing range';
                    break;
                default:
                    overlapTypeLabel = 'Overlap detected';
            }

            return {
                ...caseInfo,
                overlapTypeLabel: overlapTypeLabel,
                displayText: `Case ${caseInfo.caseNumber}: ${caseInfo.existingFromTerm} to ${caseInfo.existingToTerm} (${caseInfo.status}) - ${overlapTypeLabel}`
            };
        });
    }

    // Add this method to your LWC
    formatDateTime(dateTimeValue) {
        if (!dateTimeValue) return 'Not available';
        return new Date(dateTimeValue).toLocaleString();
    }
    // Add method to manually trigger overlap check
    async handleCheckOverlap() {
        if (!this.fromTerm || !this.toTerm) {
            this.showToast('Warning', 'Please select both From and To Terms first', 'warning');
            return;
        }

        this.isLoading = true;
        try {
            await this.validateTermOverlap();
        } catch (error) {
            console.error('Error checking overlap:', error);
        } finally {
            this.isLoading = false;
        }
    }
    get showNoOverlapMessage() {
        return !this.showTermValidation && this.fromTerm && this.toTerm;
    }
    get isPrintDeliveryMode() {
        return this.caseDeliveryMode === 'Print';
    }
    get isReturnReplaceCase() {
        return this.isReturnReplace;
    }

    resetForm() {
        this.showWellbeingFields = false;
        this.wellbeingSeverity = '';
        this.wellbeingModeOfInteraction = '';
        this.wellbeingType = '';
        this.wellbeingActionTaken = '';
        this.showRecordTypeSelection = true;
        this.showForm = false;
        this.showRejoinCaseSelection = false;
        this.selectedRecordTypeId = '';
        this.selectedRecordTypeLabel = '';
        this.selectedRecordTypeIcon = '';
        this.selectedRejoinCaseId = '';
        this.selectedRejoinCaseNumber = '';
        this.rejoinCaseOptions = [];
        this.isRejoin = false;
        this.subject = '';
        this.description = '';
        this.academicYear = '';
        this.pgid = '';
        this.program = '';
        this.fromTerm = '';
        this.toTerm = '';
        this.completedTermName = '';
        this.locationValue = '';
        this.academicSessionOptions = [];
        this.uploadedFiles = [];
        this.showAcademicRecordsFields = false;
        this.documentType = '';
        this.deliveryMode = '';
        this.dispatchAddress = '';
        this.selectedSubType = '';
        this.selectedSubCategory = '';
        this.isReadOnlyForSimpleSubTypes = false;
        this.showSubCategorySelection = false;
        this.subCategoryOptions = [];
        this.showVisaNocFields = false;
        this.passportNumber = '';
        this.passportExpiry = '';
        this.travelStartDate = '';
        this.travelEndDate = '';
        this.visaType = '';
        this.visaPurpose = '';
        this.showNameChangeFields = false;
        this.programYear = '';
        this.requestedLegalName = '';
        this.nameChangeReason = '';
        // Reset Event & Budget fields
        this.showEventBudgetFields = false;
        this.eventTitle = '';
        this.eventProposedDateTime = '';
        this.eventVenue = '';
        this.eventHostBody = '';
        this.eventDescription = '';
        this.eventExpectedHeadcount = '';
        this.eventBudgetAsk = '';
        // Reset Attendance Exception fields
        this.showAttendanceExceptionFields = false;
        this.selectedSessionId = '';
        this.selectedSessionKey = '';
        this.selectedCourseId = '';
        this.extractedDateOfAbsence = '';
        this.attendanceExceptionReason = '';
        this.sessionOptions = [];
        this.attendanceCourseOptions = [];
        this.attendanceExceptionSessions = [];
        this.attendanceExceptionCourses = [];
        this.noAttendanceSessions = false;
        this.eventContacts = '';
        // Reset Fee Exception field
        this.requestedEndDate = '';
        this.requiresTermsAndConditions = false;
        this.showTermsSection = false;
        this.termsAccepted = false;
        this.termsReason = '';
        this.termsAndConditionsData = '';
        this.showTermsAndConditionsData = false;
    }



    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }
}