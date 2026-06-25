import { LightningElement, track, wire } from 'lwc';
import getAcademicYearOptions from '@salesforce/apex/CourseOfferingLMSController.getAcademicYearOptions';
import getProgramOptions      from '@salesforce/apex/CourseOfferingLMSController.getProgramOptions';
import getTermOptions         from '@salesforce/apex/CourseOfferingLMSController.getTermOptions';
import getSessionOptions      from '@salesforce/apex/CourseOfferingLMSController.getSessionOptions';
import getOfferings           from '@salesforce/apex/CourseOfferingLMSController.getOfferings';
import getDashboardStats      from '@salesforce/apex/CourseOfferingLMSController.getDashboardStats';
import pushToLMS              from '@salesforce/apex/CourseOfferingLMSController.pushToLMS';
import { ShowToastEvent }     from 'lightning/platformShowToastEvent';
import { refreshApex }        from '@salesforce/apex';

const PENDING_COLUMNS = [
    { label: 'Course Name',    fieldName: 'Name',               type: 'text', sortable: true },
    { label: 'Program',        fieldName: 'Program_Name',       type: 'text' },
    { label: 'Year',            fieldName: 'Academic_Year_Name', type: 'text', initialWidth: 100 },
    { label: 'Term',            fieldName: 'Term_Name',          type: 'text' },
    { label: 'Session',         fieldName: 'Session_Name',       type: 'text' },
    { label: 'Sections',       fieldName: 'Section_Name__c',    type: 'text' },
    { label: 'Status',         fieldName: 'LMS_Sync_Status__c', type: 'text', cellAttributes: { class: 'slds-text-color_weak' } }
];

const SUCCESS_COLUMNS = [
    { label: 'Course Name',    fieldName: 'Name',               type: 'text', sortable: true },
    { label: 'Group Mappings', fieldName: 'Section_Mappings__c', type: 'text' },
    { label: 'Program',        fieldName: 'Program_Name',       type: 'text' },
    { label: 'Year',            fieldName: 'Academic_Year_Name', type: 'text', initialWidth: 90 },
    { label: 'Term',            fieldName: 'Term_Name',          type: 'text' },
    { label: 'Session',         fieldName: 'Session_Name',       type: 'text' },
    { label: 'Status',         fieldName: 'LMS_Sync_Status__c', type: 'text', cellAttributes: { class: 'slds-text-color_success' } },
    { type: 'button-icon', initialWidth: 50, typeAttributes: { iconName: 'utility:open', name: 'view_moodle', variant: 'bare' } }
];

const FAILED_COLUMNS = [
    { label: 'Course Name',    fieldName: 'Name',               type: 'text', sortable: true },
    { label: 'Error detail',   fieldName: 'LMS_Error__c',       type: 'text' },
    { label: 'Program',        fieldName: 'Program_Name',       type: 'text' },
    { label: 'Year',            fieldName: 'Academic_Year_Name', type: 'text', initialWidth: 90 },
    { label: 'Term',            fieldName: 'Term_Name',          type: 'text' },
    { label: 'Session',         fieldName: 'Session_Name',       type: 'text' },
    { type: 'button', typeAttributes: { label: 'Retry', name: 'retry', variant: 'brand-outline', iconName: 'utility:refresh' }, initialWidth: 100 },
    { type: 'button-icon', typeAttributes: { iconName: 'utility:info', name: 'info', variant: 'bare' }, initialWidth: 50 }
];

export default class PushToLmsDashboard extends LightningElement {

    @track rows = [];
    @track selectedRows = [];
    @track selectedRowKeys = [];
    @track stats = { totalCourses: 0, pendingCourses: 0, successCourses: 0, failedCourses: 0 };
    
    // View state
    @track activeView = 'NEEDS_SYNC';
    @track syncFilter = 'NEEDS_SYNC';
    
    // Filters
    @track year = '';
    @track program = '';
    @track term = '';
    @track session = '';
    @track searchKey = '';
    
    // Pagination
    @track pageSize = 50;
    @track pageOffset = 0;
    @track total = 0;
    
    // UI
    @track isLoading = false;
    @track isActionLoading = false;
    @track showErrorModal = false;
    @track currentError = '';
    @track selectedRowName = '';
    
    // Filter Option Lists
    @track yearOptions = [];
    @track programOptions = [];
    @track termOptions = [];
    @track sessionOptions = [];

    wiredOfferingsResult;

    @wire(getAcademicYearOptions) wiredYears({data}) { if(data) this.yearOptions = data; }
    @wire(getProgramOptions)      wiredProgs({data}) { if(data) this.programOptions = data; }
    @wire(getTermOptions,    { programName: '$program', yearName: '$year' }) wiredTerms({data}) { if(data) this.termOptions = data; }
    @wire(getSessionOptions, { programName: '$program', termName: '$term' })  wiredSessions({data}) { if(data) this.sessionOptions = data; }

    @wire(getOfferings, {
        academicYear: '$year',
        programName: '$program',
        termName: '$term',
        sessionName: '$session',
        searchTerm: '$searchKey',
        pSize: '$pageSize',
        pOffset: '$pageOffset',
        syncFilter: '$syncFilter'
    })
    wiredOfferings(result) {
        this.wiredOfferingsResult = result;
        const {data, error} = result;
        if(data) {
            this.rows = data.records.map(r => ({
                ...r,
                Academic_Year_Name: r.Academic_Year__r ? r.Academic_Year__r.Name : '',
                Program_Name: r.Program__r ? r.Program__r.Name : '',
                Term_Name: r.Academic_Term__r ? r.Academic_Term__r.Name : '',
                Session_Name: r.AcademicSession ? r.AcademicSession.Name : ''
            }));
            this.total = data.total;
            this.isLoading = false;
        } else if(error) {
            this.toast('Error', 'Failed to load courses.', 'error');
            this.isLoading = false;
        }
    }

    connectedCallback() {
        this.loadStats();
    }

    // Getters
    get isPendingView() { return this.activeView === 'NEEDS_SYNC'; }
    get isSuccessView() { return this.activeView === 'SUCCESS'; }
    get isFailedView()  { return this.activeView === 'FAILED'; }

    get pendingTabCls() { return 'nav-tab pending-tab' + (this.isPendingView ? ' active' : ''); }
    get successTabCls() { return 'nav-tab success-tab' + (this.isSuccessView ? ' active' : ''); }
    get failedTabCls()  { return 'nav-tab failed-tab'  + (this.isFailedView ? ' active' : ''); }

    get currentColumns() {
        if(this.isSuccessView) return SUCCESS_COLUMNS;
        if(this.isFailedView)  return FAILED_COLUMNS;
        return PENDING_COLUMNS;
    }

    get hasRows() { return this.rows && this.rows.length > 0; }
    get isPrevDisabled() { return this.pageOffset === 0; }
    get isNextDisabled() { return (this.pageOffset + this.pageSize) >= this.total; }
    get isBulkPushDisabled() { return this.selectedRows.length === 0; }
    
    get rangeText() {
        const start = this.total === 0 ? 0 : this.pageOffset + 1;
        const end = Math.min(this.pageOffset + this.pageSize, this.total);
        return `${start}–${end} of ${this.total}`;
    }

    get tableHeading() {
        if(this.isSuccessView) return '✓ Successfully Created Moodle Courses';
        if(this.isFailedView) return '✗ Failed Courses';
        return '⏳ Courses Pending Creation in Moodle';
    }

    get emptyTitle() {
        if(this.isSuccessView) return 'No synced courses yet.';
        if(this.isFailedView)  return 'Great! No failed records found.';
        return 'No courses pending creation for these filters.';
    }

    get emptySubtitle() {
        return 'Try adjusting your filters or refresh the list.';
    }

    // Navigation
    handleNavToSync()    { this.switchView('NEEDS_SYNC'); }
    handleNavToSuccess() { this.switchView('SUCCESS'); }
    handleNavToFailed()  { this.switchView('FAILED'); }

    switchView(view) {
        this.activeView = view;
        this.syncFilter = view;
        this.pageOffset = 0;
        this.selectedRows = [];
        this.selectedRowKeys = [];
        this.isLoading = true;
    }

    // Filters
    handleYear(e)   { this.year = e.detail.value; this.resetPaging(); }
    handleProg(e)   { this.program = e.detail.value; this.resetPaging(); }
    handleTerm(e)   { this.term = e.detail.value; this.resetPaging(); }
    handleSess(e)   { this.session = e.detail.value; this.resetPaging(); }
    handleSearch(e) { this.searchKey = e.detail.value; this.resetPaging(); }
    resetPaging()   { this.pageOffset = 0; this.isLoading = true; }

    handleRefresh() {
        this.isLoading = true;
        refreshApex(this.wiredOfferingsResult);
        this.loadStats();
    }

    loadStats() {
        getDashboardStats().then(data => { this.stats = data; }).catch(err => console.error(err));
    }

    handleSelection(event) {
        this.selectedRows = event.detail.selectedRows;
        this.selectedRowKeys = this.selectedRows.map(r => r.Id);
    }

    handleRowAction(event) {
        const action = event.detail.action.name;
        const row = event.detail.row;
        if(action === 'retry') {
            this.retrySync([row.Id]);
        } else if(action === 'info') {
            this.currentError = row.LMS_Error__c || 'No error details available.';
            this.selectedRowName = row.Name;
            this.showErrorModal = true;
        }
    }

    // Sync Actions
    async handleBulkPush() {
        if(!this.selectedRows.length) return;
        this.retrySync(this.selectedRowKeys);
    }

    async handleRetryRow() {
        this.closeModal();
        const row = this.rows.find(r => r.Name === this.selectedRowName);
        if(row) this.retrySync([row.Id]);
    }

    async retrySync(ids) {
        this.isActionLoading = true;
        this.isLoading = true;
        try {
            const message = await pushToLMS({ courseOfferingIds: ids });
            this.toast('Sync Started', message, 'info');
            this.startPolling();
        } catch(err) {
            this.toast('Sync Error', err.body?.message || err.message, 'error');
            this.isLoading = false;
        } finally {
            this.isActionLoading = false;
        }
    }

    // Polling logic to refresh data while background jobs run
    pollingInterval;
    startPolling() {
        if (this.pollingInterval) clearInterval(this.pollingInterval);
        this.pollingInterval = setInterval(() => {
            this.loadStats();
            refreshApex(this.wiredOfferingsResult);
            
            // Auto-stop polling if no more "Pending" status in current rows
            const hasPending = this.rows.some(r => r.LMS_Sync_Status__c === 'Pending');
            if (!hasPending) {
                // We could check if stats.pending changed, but this is a good start
            }
        }, 4000);

        // Stop after 1 minute regardless
        setTimeout(() => this.stopPolling(), 60000);
    }

    stopPolling() {
        if (this.pollingInterval) {
            clearInterval(this.pollingInterval);
            this.pollingInterval = null;
        }
    }

    disconnectedCallback() {
        this.stopPolling();
    }

    closeModal() { this.showErrorModal = false; }
    handleNext() { this.pageOffset += this.pageSize; this.isLoading = true; }
    handlePrev() { this.pageOffset -= this.pageSize; this.isLoading = true; }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}