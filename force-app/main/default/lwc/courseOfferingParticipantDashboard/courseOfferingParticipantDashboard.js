import { LightningElement, track, wire } from 'lwc';
import getAcademicYearOptions   from '@salesforce/apex/COParticipantDashCtrl.getAcademicYearOptions';
import getProgramOptions         from '@salesforce/apex/COParticipantDashCtrl.getProgramOptions';
import getTermOptions            from '@salesforce/apex/COParticipantDashCtrl.getTermOptions';
import getSessionOptions         from '@salesforce/apex/COParticipantDashCtrl.getSessionOptions';
import getOfferings              from '@salesforce/apex/COParticipantDashCtrl.getOfferings';
import getDashboardStats         from '@salesforce/apex/COParticipantDashCtrl.getDashboardStats';
import getParticipantsByStatusFilter from '@salesforce/apex/COParticipantDashCtrl.getParticipantsByStatusFilter';
import enqueueSyncForCO          from '@salesforce/apex/COParticipantDashCtrl.enqueueSyncForCO';
import enqueueSyncForCOP         from '@salesforce/apex/COParticipantDashCtrl.enqueueSyncForCOP';
import getSyncStatusForCOPs      from '@salesforce/apex/COParticipantDashCtrl.getSyncStatusForCOPs';
import { ShowToastEvent }        from 'lightning/platformShowToastEvent';
import { refreshApex }           from '@salesforce/apex';

// ── Column definitions per view ───────────────────────────────────────────────

const PENDING_COLUMNS = [
    { label: 'Course Offering', fieldName: 'name',             type: 'text',   sortable: true },
    { label: 'Program',         fieldName: 'programName',      type: 'text' },
    { label: 'Year',            fieldName: 'academicYear',     type: 'text',   initialWidth: 90 },
    { label: 'Term',            fieldName: 'termName',         type: 'text' },
    { label: 'Session',         fieldName: 'sessionName',      type: 'text' },
    { label: 'Total',           fieldName: 'totalParticipants',type: 'number', initialWidth: 75 },
    { label: '⏳ Pending',      fieldName: 'pendingCount',     type: 'number', initialWidth: 90, cellAttributes: { class: 'cell-pending' } },
    { label: '✗ Failed',        fieldName: 'failedCount',      type: 'number', initialWidth: 90, cellAttributes: { class: 'cell-failed' } },
    { type: 'button', typeAttributes: { label: 'View Students', name: 'view_students', variant: 'brand-outline', iconName: 'utility:people' }, initialWidth: 150 }
];

const SUCCESS_COLUMNS = [
    { label: 'Course Offering', fieldName: 'name',              type: 'text',   sortable: true },
    { label: 'Program',         fieldName: 'programName',       type: 'text' },
    { label: 'Year',            fieldName: 'academicYear',      type: 'text',   initialWidth: 90 },
    { label: 'Term',            fieldName: 'termName',          type: 'text' },
    { label: 'Session',         fieldName: 'sessionName',       type: 'text' },
    { label: 'Total',           fieldName: 'totalParticipants', type: 'number', initialWidth: 75 },
    { label: '✓ Synced',        fieldName: 'successCount',      type: 'number', initialWidth: 100, cellAttributes: { class: 'cell-success' } },
    { label: '⏳ Pending',      fieldName: 'pendingCount',      type: 'number', initialWidth: 90 },
    { type: 'button', typeAttributes: { label: 'View Synced', name: 'view_students', variant: 'success', iconName: 'utility:check' }, initialWidth: 130 }
];

const FAILED_COLUMNS = [
    { label: 'Course Offering', fieldName: 'name',              type: 'text',   sortable: true },
    { label: 'Program',         fieldName: 'programName',       type: 'text' },
    { label: 'Year',            fieldName: 'academicYear',      type: 'text',   initialWidth: 90 },
    { label: 'Term',            fieldName: 'termName',          type: 'text' },
    { label: 'Session',         fieldName: 'sessionName',       type: 'text' },
    { label: 'Total',           fieldName: 'totalParticipants', type: 'number', initialWidth: 75 },
    { label: '✗ Failed',        fieldName: 'failedCount',       type: 'number', initialWidth: 90, cellAttributes: { class: 'cell-failed' } },
    { label: '✓ Success',       fieldName: 'successCount',      type: 'number', initialWidth: 90, cellAttributes: { class: 'cell-success' } },
    { type: 'button', typeAttributes: { label: 'Retry Sync',   name: 'retry_sync',   variant: 'destructive-text', iconName: 'utility:refresh' }, initialWidth: 130 },
    { type: 'button', typeAttributes: { label: 'View Failed',  name: 'view_students', variant: 'brand-outline',   iconName: 'utility:people'  }, initialWidth: 130 }
];

const PARTICIPANT_COLUMNS = [
    { label: 'Student Name',  fieldName: 'name',         type: 'text', sortable: true },
    { label: 'Section',       fieldName: 'section',      type: 'text', initialWidth: 140 },
    { label: 'LMS Status',    fieldName: 'lmsSyncStatus',type: 'text', initialWidth: 120, cellAttributes: { class: { fieldName: 'syncClass' } } },
    { label: 'LMS Group ID',  fieldName: 'lmsGroupId',   type: 'text', initialWidth: 130 },
    { label: 'Moodle Course', fieldName: 'lmsCourseId',  type: 'text', initialWidth: 130 }
];

// ─────────────────────────────────────────────────────────────────────────────

export default class CourseOfferingParticipantDashboard extends LightningElement {

    // ── Tracked state ────────────────────────────────────────────────────────
    @track rows                = [];
    @track participants         = [];
    @track selectedParticipants = [];
    @track selectedOfferings    = [];
    @track selectedRowKeys      = [];
    @track stats = { totalParticipants: 0, pendingParticipants: 0, successParticipants: 0, failedParticipants: 0 };

    // Active view: 'NEEDS_SYNC' | 'SUCCESS' | 'FAILED'
    @track activeView  = 'NEEDS_SYNC';
    @track syncFilter  = 'NEEDS_SYNC';

    // Filters
    @track year      = '';
    @track program   = '';
    @track term      = '';
    @track session   = '';
    @track searchKey = '';

    // Pagination
    @track pageSize   = 50;
    @track pageOffset = 0;
    @track total      = 0;

    // UI state
    @track isLoading      = false;
    @track isModalLoading = false;
    @track showModal      = false;
    @track modalTitle     = '';

    // Filter option lists
    @track yearOptions    = [];
    @track programOptions = [];
    @track termOptions    = [];
    @track sessionOptions = [];

    // Polling
    pollIntervalId;
    isPolling = false;

    // Modal context
    selectedOfferingId;
    modalStatusFilter;
    wiredOfferingsResult;

    // ── Wire: filter options ─────────────────────────────────────────────────
    @wire(getAcademicYearOptions) wiredYears({ data }) { if (data) this.yearOptions = data; }
    @wire(getProgramOptions)      wiredProgs({ data }) { if (data) this.programOptions = data; }
    @wire(getTermOptions,   { programName: '$program', yearName: '$year' })    wiredTerms({ data })    { if (data) this.termOptions = data; }
    @wire(getSessionOptions,{ programName: '$program', termName:  '$term' })   wiredSessions({ data }) { if (data) this.sessionOptions = data; }

    // ── Wire: main offering data ─────────────────────────────────────────────
    @wire(getOfferings, {
        academicYear: '$year',
        programName:  '$program',
        termName:     '$term',
        sessionName:  '$session',
        searchTerm:   '$searchKey',
        pSize:        '$pageSize',
        pOffset:      '$pageOffset',
        syncFilter:   '$syncFilter'
    })
    wiredOfferings(result) {
        this.wiredOfferingsResult = result;
        const { data, error } = result;
        if (data) {
            this.rows = (data.records || []).map(r => ({ ...r, id: r.id ? String(r.id) : undefined }));
            this.total = data.total;
            this.selectedOfferings = [];
            this.selectedRowKeys   = [];
            this.isLoading = false;
        } else if (error) {
            this.toast('Error', 'Failed to load course offerings.', 'error');
            this.isLoading = false;
        }
    }

    connectedCallback() {
        this.loadStats();
    }

    // ── Computed getters: view state ─────────────────────────────────────────
    get isPendingView() { return this.activeView === 'NEEDS_SYNC'; }
    get isSuccessView() { return this.activeView === 'SUCCESS'; }
    get isFailedView()  { return this.activeView === 'FAILED'; }

    get pendingTabCls() { return 'nav-tab pending-tab' + (this.isPendingView ? ' active' : ''); }
    get successTabCls() { return 'nav-tab success-tab' + (this.isSuccessView ? ' active' : ''); }
    get failedTabCls()  { return 'nav-tab failed-tab'  + (this.isFailedView  ? ' active' : ''); }

    get currentColumns() {
        if (this.isSuccessView) return SUCCESS_COLUMNS;
        if (this.isFailedView)  return FAILED_COLUMNS;
        return PENDING_COLUMNS;
    }
    get participantColumns() { return PARTICIPANT_COLUMNS; }

    // ── Computed getters: table / pagination ─────────────────────────────────
    get hasRows()          { return this.rows && this.rows.length > 0; }
    get hasParticipants()  { return this.participants && this.participants.length > 0; }
    get isPrevDisabled()   { return this.pageOffset === 0; }
    get isNextDisabled()   { return (this.pageOffset + this.pageSize) >= this.total; }
    get isBulkPushDisabled() { return this.selectedOfferings.length === 0; }
    get isSyncButtonDisabled() { return this.selectedParticipants.length === 0; }

    get rangeText() {
        const start = this.total === 0 ? 0 : this.pageOffset + 1;
        const end   = Math.min(this.pageOffset + this.pageSize, this.total);
        return `${start}–${end} of ${this.total}`;
    }

    get tableHeading() {
        if (this.isSuccessView) return '✓ Successfully Synced Course Offerings';
        if (this.isFailedView)  return '✗ Course Offerings with Failed Sync';
        return '⏳ Pending Sync — Includes Pending & Failed Records';
    }
    get emptyTitle() {
        if (this.isSuccessView) return 'No successfully synced course offerings yet.';
        if (this.isFailedView)  return '🎉 No failed sync records!';
        return 'All participants are synced! Nothing pending.';
    }
    get emptySubtitle() {
        if (this.isSuccessView) return 'Synced offerings will appear here once students are successfully pushed to Moodle.';
        if (this.isFailedView)  return 'All sync operations have succeeded or are in progress.';
        return 'Try adjusting your filters or triggering a new sync.';
    }

    // ── Modal getters ────────────────────────────────────────────────────────
    get modalHeaderClass() {
        if (this.isSuccessView) return 'slds-modal__header modal-header-success';
        if (this.isFailedView)  return 'slds-modal__header modal-header-failed';
        return 'slds-modal__header modal-header-pending';
    }
    get modalSubtitle() {
        if (this.isSuccessView) return 'Read-only view of successfully synced students';
        if (this.isFailedView)  return 'Showing failed students — use Retry Sync to re-attempt';
        return 'Showing pending students — select rows and click Sync Selected';
    }
    get modalTotalCount()   { return this.participants.length; }
    get modalPendingCount() { return this.participants.filter(p => p.lmsSyncStatus === 'Pending').length; }
    get modalFailedCount()  { return this.participants.filter(p => p.lmsSyncStatus === 'Failed').length; }
    get modalSuccessCount() { return this.participants.filter(p => p.lmsSyncStatus === 'Success').length; }

    // ── Navigation ───────────────────────────────────────────────────────────
    handleNavToSync()    { this.switchView('NEEDS_SYNC'); }
    handleNavToSuccess() { this.switchView('SUCCESS'); }
    handleNavToFailed()  { this.switchView('FAILED'); }

    switchView(view) {
        this.activeView  = view;
        this.syncFilter  = view;
        this.pageOffset  = 0;
        this.selectedOfferings = [];
        this.selectedRowKeys   = [];
        this.isLoading = true;
    }

    // ── Filters ──────────────────────────────────────────────────────────────
    handleYear(e)   { this.year      = e.detail.value; this.resetPaging(); }
    handleProg(e)   { this.program   = e.detail.value; this.resetPaging(); }
    handleTerm(e)   { this.term      = e.detail.value; this.resetPaging(); }
    handleSess(e)   { this.session   = e.detail.value; this.resetPaging(); }
    handleSearch(e) { this.searchKey = e.detail.value; this.resetPaging(); }
    resetPaging()   { this.pageOffset = 0; this.isLoading = true; }

    // ── Pagination ───────────────────────────────────────────────────────────
    handleNext() { this.pageOffset += this.pageSize; this.isLoading = true; }
    handlePrev() { this.pageOffset -= this.pageSize; this.isLoading = true; }

    // ── Refresh ──────────────────────────────────────────────────────────────
    handleRefresh() {
        this.isLoading = true;
        if (this.wiredOfferingsResult) refreshApex(this.wiredOfferingsResult);
        this.loadStats();
    }

    // ── Stats ────────────────────────────────────────────────────────────────
    loadStats() {
        getDashboardStats()
            .then(data  => { this.stats = data; })
            .catch(() => {});
    }

    // ── Selection ────────────────────────────────────────────────────────────
    handleSelection(event) {
        const sel = event?.detail?.selectedRows;
        this.selectedOfferings = Array.isArray(sel) ? sel : [];
        this.selectedRowKeys   = this.selectedOfferings.map(r => r.id).filter(Boolean);
    }

    // ── Row Actions ──────────────────────────────────────────────────────────
    handleRowAction(event) {
        const action = event.detail.action.name;
        const row    = event.detail.row;
        if (action === 'view_students') {
            this.openParticipantModal(row);
        } else if (action === 'retry_sync') {
            this.retrySyncForRow(row);
        }
    }

    openParticipantModal(row) {
        this.selectedOfferingId = row.id;
        let statusFilter = null;
        let titleSuffix  = '';
        if (this.isSuccessView) { statusFilter = 'Success'; titleSuffix = ' — Synced Students'; }
        else if (this.isFailedView) { statusFilter = 'Failed'; titleSuffix = ' — Failed Students'; }
        else { statusFilter = null; titleSuffix = ' — Pending Students'; }

        this.modalStatusFilter = statusFilter;
        this.modalTitle        = row.name + titleSuffix;
        this.showModal         = true;
        this.fetchParticipants(statusFilter);
    }

    fetchParticipants(statusFilter) {
        this.isModalLoading = true;
        this.participants   = [];
        getParticipantsByStatusFilter({ offeringId: this.selectedOfferingId, statusFilter })
            .then(data => {
                this.participants   = this.styleParticipants(data);
                this.isModalLoading = false;
                if (!this.isSuccessView) this.checkAndStartPolling();
            })
            .catch(() => {
                this.toast('Error', 'Failed to load students.', 'error');
                this.isModalLoading = false;
            });
    }

    styleParticipants(parts) {
        return parts.map(p => {
            let sClass = '';
            if (p.lmsSyncStatus === 'Success') sClass = 'slds-text-color_success';
            else if (p.lmsSyncStatus === 'Failed')  sClass = 'slds-text-color_error';
            else if (p.lmsSyncStatus === 'Pending') sClass = 'slds-text-color_weak';
            return { ...p, syncClass: sClass };
        });
    }

    handleParticipantSelection(event) {
        this.selectedParticipants = event.detail.selectedRows || [];
    }

    // ── Sync actions ─────────────────────────────────────────────────────────

    async retrySyncForRow(row) {
        this.isLoading = true;
        try {
            const msg = await enqueueSyncForCO({ courseOfferingIds: [row.id] });
            this.toast('Retry Queued', msg, 'success');
            this.handleRefresh();
        } catch (err) {
            this.toast('Error', err?.body?.message || 'Failed to queue retry.', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleBulkPush() {
        if (!this.selectedOfferings.length) return;
        this.isLoading = true;
        const coIds = this.selectedOfferings.map(o => o.id);
        try {
            const msg = await enqueueSyncForCO({ courseOfferingIds: coIds });
            this.toast('Bulk Sync Queued', msg, 'success');
            this.handleRefresh();
        } catch (err) {
            this.toast('Error', err?.body?.message || 'Failed to enqueue bulk sync.', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleSyncParticipants() {
        if (!this.selectedParticipants.length) return;
        this.isModalLoading = true;
        const pIds = this.selectedParticipants.map(p => p.id);
        try {
            const msg = await enqueueSyncForCOP({ copIds: pIds });
            this.toast('Sync Queued', msg, 'success');
            this.participants = this.participants.map(p =>
                pIds.includes(p.id) ? { ...p, lmsSyncStatus: 'Pending', syncClass: '' } : p
            );
            this.checkAndStartPolling();
            this.closeModal();
            this.loadStats();
        } catch (err) {
            this.toast('Error', err?.body?.message || 'Failed to enqueue sync.', 'error');
        } finally {
            this.isModalLoading = false;
        }
    }

    async handleSyncAllCOPs() {
        this.isModalLoading = true;
        try {
            const msg = await enqueueSyncForCO({ courseOfferingIds: [this.selectedOfferingId] });
            this.toast('Sync Queued', msg, 'success');
            this.closeModal();
            this.loadStats();
            this.handleRefresh();
        } catch (err) {
            this.toast('Error', err?.body?.message || 'Failed to enqueue sync.', 'error');
        } finally {
            this.isModalLoading = false;
        }
    }

    async handleRetryAllFailed() {
        const failedIds = this.participants
            .filter(p => p.lmsSyncStatus === 'Failed')
            .map(p => p.id);
        if (!failedIds.length) { this.toast('Info', 'No failed students to retry.', 'info'); return; }
        this.isModalLoading = true;
        try {
            const msg = await enqueueSyncForCOP({ copIds: failedIds });
            this.toast('Retry Queued', msg, 'success');
            this.closeModal();
            this.loadStats();
            this.handleRefresh();
        } catch (err) {
            this.toast('Error', err?.body?.message || 'Failed to queue retry.', 'error');
        } finally {
            this.isModalLoading = false;
        }
    }

    // ── Polling ──────────────────────────────────────────────────────────────

    checkAndStartPolling() {
        const hasPending = this.participants.some(p => p.lmsSyncStatus === 'Pending');
        if (hasPending && !this.isPolling) {
            this.isPolling     = true;
            this.pollIntervalId = setInterval(() => this.pollSyncStatus(), 3000);
        } else if (!hasPending && this.isPolling) {
            this.stopPolling();
        }
    }

    async pollSyncStatus() {
        const pendingIds = this.participants
            .filter(p => p.lmsSyncStatus === 'Pending')
            .map(p => p.id);
        if (!pendingIds.length) { this.stopPolling(); return; }

        try {
            const statusMap = await getSyncStatusForCOPs({ copIds: pendingIds });
            let changed = false;
            this.participants = this.participants.map(p => {
                const newStatus = statusMap[p.id];
                if (newStatus && newStatus !== p.lmsSyncStatus) {
                    changed = true;
                    let sClass = '';
                    if (newStatus === 'Success') sClass = 'slds-text-color_success';
                    else if (newStatus === 'Failed') sClass = 'slds-text-color_error';
                    return { ...p, lmsSyncStatus: newStatus, syncClass: sClass };
                }
                return p;
            });
            if (changed) {
                this.loadStats();
                if (this.wiredOfferingsResult) refreshApex(this.wiredOfferingsResult);
            }
            this.checkAndStartPolling();
        } catch (e) { this.stopPolling(); }
    }

    stopPolling() {
        if (this.pollIntervalId) { clearInterval(this.pollIntervalId); this.pollIntervalId = null; }
        this.isPolling = false;
    }

    // ── Modal ────────────────────────────────────────────────────────────────
    closeModal() {
        this.stopPolling();
        this.showModal         = false;
        this.participants       = [];
        this.selectedParticipants = [];
        if (this.wiredOfferingsResult) refreshApex(this.wiredOfferingsResult);
    }

    // ── Toast ────────────────────────────────────────────────────────────────
    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    disconnectedCallback() { this.stopPolling(); }
}