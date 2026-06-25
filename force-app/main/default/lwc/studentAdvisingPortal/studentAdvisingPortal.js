import { LightningElement, track, wire } from 'lwc';
const STATUS_COMPLETED = 'Completed';
const STATUS_IN_PROGRESS = 'In Progress';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { getPicklistValues } from 'lightning/uiObjectInfoApi';
import APPOINTMENT_REQUEST_OBJECT from '@salesforce/schema/Appointment_Request__c';
import REQUEST_TYPE_FIELD from '@salesforce/schema/Appointment_Request__c.Request_Type__c';
import getSupportDirectory from '@salesforce/apex/AcademicSupportController.getSupportDirectory';
import createAppointmentRequest from '@salesforce/apex/AcademicSupportController.createAppointmentRequest';
import getStudentChecklists from '@salesforce/apex/AcademicSupportController.getStudentChecklists';
import updateChecklistItem from '@salesforce/apex/AcademicSupportController.updateChecklistItem';
import getStudentAppointments from '@salesforce/apex/AcademicSupportController.getStudentAppointments';
import getAvailableSlots from '@salesforce/apex/AdvisorAvailabilityService.getAvailableSlots';
import getEligibleWorkshops from '@salesforce/apex/WorkshopPortalController.getEligibleWorkshops';
import getMyRegistrations from '@salesforce/apex/WorkshopPortalController.getMyRegistrations';
import registerForWorkshop from '@salesforce/apex/WorkshopPortalController.registerForWorkshop';
import cancelRegistration from '@salesforce/apex/WorkshopPortalController.cancelRegistration';
import getAcademicTerms from '@salesforce/apex/WorkshopPortalController.getAcademicTerms';
import getStudentWorkshopFiles from '@salesforce/apex/WorkshopFileManagerController.getStudentWorkshopFiles';
import downloadWorkshopFile from '@salesforce/apex/WorkshopFileManagerController.downloadWorkshopFile';

export default class StudentAdvisingPortal extends LightningElement {

    // ── Directory / Loading ──────────────────────────────────────────────────
    @track directoryData = {};
    @track isLoading = true;
    @track hasError = false;
    @track errorMessage = '';

    /** Resolved from wiredDirectory; drives all dependent wires */
    @track studentContactId;

    // ── Tab Navigation ───────────────────────────────────────────────────────
    @track activeTab = 'support'; // 'support' | 'appointments' | 'tasks' | 'workshops'

    // ── Campus Directory sub-tab ─────────────────────────────────────────────
    @track dirSubTab = 'advisors'; // 'advisors' | 'associates' | 'tutors'

    // ── Booking Modal ────────────────────────────────────────────────────────
    @track isBookingModalOpen = false;
    @track isSubmitting = false;
    @track selectedDate = '';
    @track selectedSlot = null;    // { startISO, endISO, label }
    @track isSlotsLoading = false;
    @track noSlotsAvailable = false;
    @track availableSlots = [];
    @track formMode = '';
    @track formTitle = '';
    @track formType = '';
    @track formReason = '';
    @track selectedSlotISO = '';

    // ── Profile Modal ────────────────────────────────────────────────────────
    @track isProfileModalOpen = false;
    @track profileContactData = {};
    @track profileContactName = '';
    @track profileContactRole = '';

    // ── My Appointments Tab ──────────────────────────────────────────────────
    @track isAppointmentsLoading = true;
    @track isAppointmentsError = false;
    @track appointmentsErrorMessage = '';
    @track appointmentsData = [];
    @track appointmentsStatusFilter = 'All';
    @track selectedAppointment = null;
    wiredAppointmentsResult;

    // ── Advising Tasks / Checklist ───────────────────────────────────────────
    @track checklistData = [];
    @track isChecklistLoading = true;
    @track hasChecklistError = false;
    @track checklistErrorMessage = '';
    wiredChecklistResult;

    // ── Task Detail Modal ────────────────────────────────────────────────────
    @track editingItemId = null;
    @track editingStatus = '';
    @track editingComments = '';
    @track isSavingItem = false;
    @track isTaskModalOpen = false;
    @track selectedTask = {};

    // ── Workshops Tab ────────────────────────────────────────────────────────
    @track workshopsSubTab = 'available'; // 'available' | 'mine'
    @track workshopTermId = '';
    @track workshopTermOptions = [];
    @track isWorkshopsLoading = false;
    @track workshopsError = '';
    @track availableWorkshops = [];
    @track myRegistrations = [];
    @track isMyRegLoading = false;
    @track isRegistering = false;
    @track workshopStatusSummary = { registered: 0, available: 0, completed: 0 };
    // Modals for new UI
    @track isWorkshopDetailsModalOpen = false;
    @track selectedWorkshopForModal = null;
    @track selectedBatchLabel = null;
    @track isRegistrationDetailsModalOpen = false;
    @track selectedRegistrationForModal = null;
    @track isWorkshopFilesLoading = false;
    @track workshopFilesError = '';

    // ── Dynamic Picklist (R1: ISB-6020) ──────────────────────────────────────────
    @wire(getObjectInfo, { objectApiName: APPOINTMENT_REQUEST_OBJECT })
    objectInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$objectInfo.data.defaultRecordTypeId',
        fieldApiName: REQUEST_TYPE_FIELD
    })
    requestTypePicklist;

    // ════════════════════════════════════════════════════════════════════════
    //  WIRE: Support Directory
    // ════════════════════════════════════════════════════════════════════════
    @wire(getSupportDirectory)
    wiredDirectory({ error, data }) {
        if (data) {
            if (data.hasError) {
                this.hasError = true;
                this.errorMessage = data.errorMessage;
            } else {
                this.directoryData = data;
                if (data.studentContactId) {
                    this.studentContactId = data.studentContactId;
                } else {
                    this.isChecklistLoading = false;
                    this.isAppointmentsLoading = false;
                }
            }
            this.isLoading = false;
        } else if (error) {
            this.hasError = true;
            this.errorMessage = 'Failed to retrieve server data.';
            this.isLoading = false;
            this.isChecklistLoading = false;
            this.isAppointmentsLoading = false;
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    //  WIRE: Available Slots  (lazy — fires only when booking modal is open
    //        and both advisorUserId and selectedDate are set)
    // ════════════════════════════════════════════════════════════════════════
    get _advisorUserIdForWire() {
        return this.isBookingModalOpen ? this.primaryAdvisorUserId : null;
    }
    get _selectedDateForWire() {
        return this.isBookingModalOpen ? this.selectedDate : null;
    }

    @wire(getAvailableSlots, {
        advisorUserId: '$_advisorUserIdForWire',
        dateString: '$_selectedDateForWire',
        slotDurationMinutes: 30
    })
    wiredSlots({ error, data }) {
        this.isSlotsLoading = false;
        if (data) {
            this.availableSlots = data;
            this.noSlotsAvailable = !data.some(s => s.isAvailable);
        } else if (error) {
            this.availableSlots = [];
            this.noSlotsAvailable = true;
            console.error('[SAP] wiredSlots error:', JSON.stringify(error));
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    //  WIRE: Student Appointments
    // ════════════════════════════════════════════════════════════════════════
    @wire(getStudentAppointments, { studentContactId: '$studentContactId' })
    wiredAppointments(result) {
        this.wiredAppointmentsResult = result;
        if (result.data) {
            this.appointmentsData = result.data.map(a => ({
                ...a,
                statusClass: this._apptStatusClass(a.status),
                rowClass: 'appt-row'
            }));
            this.isAppointmentsLoading = false;
            this.isAppointmentsError = false;
        } else if (result.error) {
            const msg = result.error.body && result.error.body.message
                ? result.error.body.message
                : 'An error occurred while loading your appointment history.';
            this.appointmentsErrorMessage = msg;
            this.isAppointmentsError = true;
            this.isAppointmentsLoading = false;
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    //  WIRE: Advising Tasks / Checklists
    // ════════════════════════════════════════════════════════════════════════
    @wire(getStudentChecklists, { studentContactId: '$studentContactId' })
    wiredChecklists(result) {
        this.wiredChecklistResult = result;
        if (result.data) {
            if (result.data.hasError) {
                this.hasChecklistError = true;
                this.checklistErrorMessage = result.data.errorMessage;
                this.isChecklistLoading = false;
            } else {
                try {
                    this.checklistData = (result.data.checklists || []).map(checklist => {
                        const percentage = checklist.completionPercentage || 0;
                        let progressClass = 'progress-fill';
                        if (percentage >= 80) progressClass += ' progress-fill--high';
                        else if (percentage >= 50) progressClass += ' progress-fill--medium';
                        else progressClass += ' progress-fill--low';
                        const DONE_STATUSES = ['Completed', 'Closed', 'Waived'];
                        const mappedItems = (Array.isArray(checklist.items) ? checklist.items : []).map(item => ({
                            ...item,
                            statusClass: this.computeStatusClass(item.status),
                            priorityClass: this.computePriorityClass(item.priority),
                            rowClass: item.isOverdue ? 'task-row task-row--overdue' : 'task-row',
                            isBeingEdited: false
                        }));
                        const totalItems = mappedItems.length;
                        const completedItems = mappedItems.filter(i => DONE_STATUSES.includes(i.status)).length;
                        const overdueCount = mappedItems.filter(i => i.isOverdue).length;
                        return {
                            ...checklist,
                            isExpanded: false,
                            progressBarClass: progressClass,
                            progressBarStyle: `width: ${percentage}%`,
                            chevronIcon: 'utility:chevronright',
                            statusClass: this.computeStatusClass(checklist.status),
                            totalItems,
                            completedItems,
                            overdueCount,
                            items: mappedItems
                        };
                    });
                } catch (e) {
                    this.hasChecklistError = true;
                    this.checklistErrorMessage = 'Failed to process advising task data.';
                }
                this.isChecklistLoading = false;
            }
        } else if (result.error) {
            this.hasChecklistError = true;
            this.checklistErrorMessage = 'Failed to retrieve advising tasks.';
            this.isChecklistLoading = false;
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    //  GETTERS — Tab State
    // ════════════════════════════════════════════════════════════════════════
    get isSupportTab()      { return this.activeTab === 'support'; }
    get isAppointmentsTab() { return this.activeTab === 'appointments'; }
    get isTasksTab()        { return this.activeTab === 'tasks'; }
    get isWorkshopsTab()    { return this.activeTab === 'workshops'; }

    get supportTabClass() {
        return this.activeTab === 'support' ? 'tab-btn tab-btn--active' : 'tab-btn';
    }
    get appointmentsTabClass() {
        return this.activeTab === 'appointments' ? 'tab-btn tab-btn--active' : 'tab-btn';
    }
    get tasksTabClass() {
        return this.activeTab === 'tasks' ? 'tab-btn tab-btn--active' : 'tab-btn';
    }
    get workshopsTabClass() {
        return this.activeTab === 'workshops' ? 'tab-btn tab-btn--active' : 'tab-btn';
    }

    handleTabSwitch(event) {
        const tab = event.currentTarget.dataset.tab;
        if (tab) {
            this.activeTab = tab;
            if (tab === 'workshops' && this.workshopTermOptions.length === 0) {
                this._loadWorkshopTerms();
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    //  GETTERS — Campus Directory Sub-tabs
    // ════════════════════════════════════════════════════════════════════════
    get isAdvisorsSubTab()   { return this.dirSubTab === 'advisors'; }
    get isAssociatesSubTab() { return this.dirSubTab === 'associates'; }
    get isTutorsSubTab()     { return this.dirSubTab === 'tutors'; }

    get advisorsSubTabClass()   { return this.dirSubTab === 'advisors'   ? 'dir-tab-btn dir-tab-btn--active' : 'dir-tab-btn'; }
    get associatesSubTabClass() { return this.dirSubTab === 'associates' ? 'dir-tab-btn dir-tab-btn--active' : 'dir-tab-btn'; }
    get tutorsSubTabClass()     { return this.dirSubTab === 'tutors'     ? 'dir-tab-btn dir-tab-btn--active' : 'dir-tab-btn'; }

    get advisorsCount()   { return this.directoryData.allAdvisors         ? this.directoryData.allAdvisors.length         : 0; }
    get associatesCount() { return this.directoryData.academicAssociates  ? this.directoryData.academicAssociates.length  : 0; }
    get tutorsCount()     { return this.directoryData.tutors              ? this.directoryData.tutors.length               : 0; }

    handleDirSubTabSwitch(event) {
        const subtab = event.currentTarget.dataset.subtab;
        if (subtab) this.dirSubTab = subtab;
    }

    // ════════════════════════════════════════════════════════════════════════
    //  GETTERS — Workshops Sub-tabs
    // ════════════════════════════════════════════════════════════════════════
    get isAvailableSubTab() { return this.workshopsSubTab === 'available'; }
    get isMineSubTab()      { return this.workshopsSubTab === 'mine'; }

    get availableSubTabClass() {
        return this.workshopsSubTab === 'available' ? 'dir-tab-btn dir-tab-btn--active' : 'dir-tab-btn';
    }
    get mineSubTabClass() {
        return this.workshopsSubTab === 'mine' ? 'dir-tab-btn dir-tab-btn--active' : 'dir-tab-btn';
    }

    get browseMenuClass() {
        return this.workshopsSubTab === 'available' ? 'ws-menu-item ws-menu-item--active' : 'ws-menu-item';
    }
    get myRegMenuClass() {
        return this.workshopsSubTab === 'mine' ? 'ws-menu-item ws-menu-item--active' : 'ws-menu-item';
    }

    get workshopTermOptionsWithClass() {
        return this.workshopTermOptions.map(t => ({
            ...t,
            pillClass: t.value === this.workshopTermId ? 'ws-term-pill ws-term-pill--active' : 'ws-term-pill'
        }));
    }

    get hasAvailableWorkshops() { return this.availableWorkshops.length > 0; }
    get hasMyRegistrations()    { return this.myRegistrations.length > 0; }

    get workshopCountLabel() {
        const count = this.availableWorkshops.length;
        const termLabel = this.workshopTermOptions.find(t => t.value === this.workshopTermId)?.label || '';
        if (termLabel && termLabel !== '-- All Terms --') {
            return `Showing ${count} workshop${count === 1 ? '' : 's'} for ${termLabel}`;
        }
        return `Showing ${count} workshop${count === 1 ? '' : 's'}`;
    }

    get registeredBatchLabel() {
        if (!this.selectedWorkshopForModal) return '';
        const label = this.selectedWorkshopForModal.registeredBatchLabel;
        if (label) return label;
        
        // Fallback: try to find the registered batch from batch options
        const registeredBatch = this.selectedWorkshopForModal.batchOptions?.find(opt => opt.isRegisteredBatch);
        return registeredBatch ? registeredBatch.label : '(Not specified)';
    }

    get hasRegisteredBatch() {
        if (!this.selectedWorkshopForModal || !this.selectedWorkshopForModal.batchOptions) return false;
        return this.selectedWorkshopForModal.batchOptions.some(opt => opt.isRegisteredBatch);
    }

    handleWorkshopsSubTabSwitch(event) {
        const subtab = event.currentTarget.dataset.subtab;
        if (!subtab) return;
        this.workshopsSubTab = subtab;
        if (subtab === 'mine' && this.myRegistrations.length === 0) {
            this._loadMyRegistrations();
        }
    }

    handleWorkshopsMenuSwitch(event) {
        const subtab = event.currentTarget.dataset.subtab;
        if (!subtab) return;
        this.workshopsSubTab = subtab;
        if (subtab === 'mine' && this.myRegistrations.length === 0) {
            this._loadMyRegistrations();
        }
    }

    handleWorkshopTermChange(event) {
        this.workshopTermId = event.currentTarget.dataset.termid || event.target.value;
        this._loadEligibleWorkshops();
    }

    _loadWorkshopTerms() {
        getAcademicTerms()
            .then(terms => {
                this.workshopTermOptions = [
                    { label: '-- All Terms --', value: '' },
                    ...(terms || []).map(t => ({ label: t.Name, value: t.Id }))
                ];
                this.workshopTermId = '';
                this._loadEligibleWorkshops();
            })
            .catch(() => {
                this.workshopsError = 'Failed to load academic terms.';
            });
    }

    _loadEligibleWorkshops() {
        this.isWorkshopsLoading = true;
        this.workshopsError = '';
        getEligibleWorkshops({ termId: this.workshopTermId || null })
            .then(data => {
                console.log('[Workshop Data] Raw Apex Response:', JSON.stringify(data, null, 2));
                this.availableWorkshops = this._normalizeWorkshopData(data);
                console.log('[Workshop Data] Normalized Workshops:', this.availableWorkshops.map(w => ({
                    name: w.name,
                    isRegistered: w.isRegistered,
                    registeredBatchLabel: w.registeredBatchLabel,
                    batchOptions: w.batchOptions.map(opt => ({
                        label: opt.label,
                        isRegisteredBatch: opt.isRegisteredBatch
                    }))
                })));
            })
            .catch(err => {
                this.workshopsError = (err.body && err.body.message) ? err.body.message : 'Failed to load workshops.';
            })
            .finally(() => {
                this.isWorkshopsLoading = false;
            });
    }

    _updateStatusSummary() {
        const registered = this.availableWorkshops.filter(w => w.registrationStatus === 'Registered' || w.registrationStatus === 'Waitlisted').length;
        const available = this.availableWorkshops.filter(w => !w.registrationStatus).length;
        this.workshopStatusSummary = { registered, available, completed: 0 };
    }

    _normalizeWorkshopData(data) {
        if (!Array.isArray(data)) return [];

        const normalized = data.map(wrapper => {
            const workshop = wrapper && wrapper.workshop ? wrapper.workshop : {};
            const batchOptions = Array.isArray(wrapper.batchOptions) ? wrapper.batchOptions : [];
            const sessionBatchDetails = Array.isArray(wrapper.sessionBatchDetails) ? wrapper.sessionBatchDetails : [];
            const registrationStatus = wrapper.registrationStatus || '';
            const registeredBatchLabel = wrapper.registeredBatchLabel || '';
            const registrationRequired = wrapper.registrationRequired !== false;

            const normalizedSessionBatchDetails = sessionBatchDetails.map(detail => ({
                sessionNumber: detail.sessionNumber,
                sessionName: detail.sessionName || '',
                batchLabel: detail.batchLabel || '',
                startDate: this._formatDateOnly(detail.startDateTime),
                startTime: this._formatTimeOnly(detail.startDateTime),
                endDate: this._formatDateOnly(detail.endDateTime),
                endTime: this._formatTimeOnly(detail.endDateTime),
                mode: detail.mode || '',
                location: detail.location || '',
                meetingLink: detail.meetingLink || ''
            }));

            // Transform batch label options for display
            const normalizedBatchOptions = batchOptions.map(blo => {
                const totalCapacity = Number.isFinite(blo.totalCapacity) ? blo.totalCapacity : 0;
                const totalRegistered = Number.isFinite(blo.totalRegistered) ? blo.totalRegistered : 0;
                const availableSeats = Number.isFinite(blo.availableSeats) ? blo.availableSeats : 0;
                
                // Ensure we have the batch label for comparison
                const batchLabel = blo.label || 'Batch';
                const isRegisteredBatch = registeredBatchLabel && (batchLabel === registeredBatchLabel);

                return {
                    label: batchLabel,
                    totalCapacity,
                    totalRegistered,
                    availableSeats,
                    isAtCapacity: !!blo.isAtCapacity,
                    isFullyBlocked: !!blo.isFullyBlocked,
                    isRegisteredBatch, // Mark which batch user is registered for
                    sampleBatchInfo: blo.sampleBatchInfo || {}, // Session 1 example for time/mode display
                    startDate: this._formatDateOnly(blo.sampleBatchInfo?.startDateTime),
                    startTime: this._formatTimeOnly(blo.sampleBatchInfo?.startDateTime),
                    endDate: this._formatDateOnly(blo.sampleBatchInfo?.endDateTime),
                    endTime: this._formatTimeOnly(blo.sampleBatchInfo?.endDateTime),
                    timeRange: this._formatTimeRange(
                        blo.sampleBatchInfo?.startDateTime, 
                        blo.sampleBatchInfo?.endDateTime
                    ),
                    fullDateTimeRange: this._formatFullDateTimeRange(
                        blo.sampleBatchInfo?.startDateTime, 
                        blo.sampleBatchInfo?.endDateTime
                    ),
                    mode: blo.sampleBatchInfo?.mode || '',
                    location: blo.sampleBatchInfo?.location || '',
                    meetingLink: blo.sampleBatchInfo?.meetingLink || '',
                    seatCount: `${totalRegistered} / ${totalCapacity} registered`
                };
            });

            // For registered workshops, ensure at least one batch is marked as registered
            // If comparison failed, mark the first batch as registered as fallback
            if (registrationStatus && registeredBatchLabel && normalizedBatchOptions.length > 0) {
                const hasRegisteredBatch = normalizedBatchOptions.some(opt => opt.isRegisteredBatch);
                if (!hasRegisteredBatch) {
                    console.warn('[Workshop Data] No matching batch found for registeredBatchLabel:', registeredBatchLabel);
                    console.warn('[Workshop Data] Available batch labels:', normalizedBatchOptions.map(opt => opt.label));
                    // Fallback: mark first batch as registered
                    normalizedBatchOptions[0].isRegisteredBatch = true;
                }
            }

            return {
                workshopId: workshop.Id || '',
                name: workshop.Name || 'Workshop',
                status: workshop.Status__c || 'Published',
                series: workshop.Workshop_Series__c || '',
                description: workshop.Description__c || 'No description available.',
                campusName: workshop.Campus__r ? workshop.Campus__r.Name : '',
                sessionCount: Number.isFinite(workshop.Total_Sessions__c) ? workshop.Total_Sessions__c : 0,
                registrationStatus,
                registrationRequired,
                isReadOnlyWorkshop: !registrationRequired,
                registeredBatchLabel,
                batchOptions: normalizedBatchOptions,
                hasBatchOptions: normalizedBatchOptions.length > 0,
                sessionBatchDetails: normalizedSessionBatchDetails,
                hasSessionBatchDetails: normalizedSessionBatchDetails.length > 0,
                workshopFiles: [],
                hasWorkshopFiles: false,
                hasRestrictedFiles: false,
                isRegistered: !!registrationStatus,
                cardClass: 'ws-card', // Simple class for grid cards
                statusBadgeLabel: registrationStatus 
                    ? `${registrationStatus} (${registeredBatchLabel})`
                    : (!registrationRequired ? 'No Registration Required' : 'Available'),
                statusBadgeClass: registrationStatus
                    ? (registrationStatus === 'Waitlisted' ? 'ws-badge ws-badge--waitlist' : 'ws-badge ws-badge--registered')
                    : (!registrationRequired ? 'ws-badge ws-badge--registered' : 'ws-badge ws-badge--available')
            };
        });

        this._updateStatusSummary();
        return normalized;
    }

    _formatDate(value) {
        if (!value) return '';
        const date = new Date(value);
        if (Number.isNaN(date.getTime())) return '';
        return new Intl.DateTimeFormat('en-US', {
            month: 'short',
            day: '2-digit'
        }).format(date);
    }

    _formatDateTime(value) {
        if (!value) return '';
        const date = new Date(value);
        if (Number.isNaN(date.getTime())) return '';
        return new Intl.DateTimeFormat('en-US', {
            month: 'short',
            day: '2-digit',
            hour: 'numeric',
            minute: '2-digit'
        }).format(date);
    }

    _formatDateOnly(value) {
        if (!value) return '';
        const date = new Date(value);
        if (Number.isNaN(date.getTime())) return '';
        return new Intl.DateTimeFormat('en-US', {
            month: 'short',
            day: '2-digit',
            year: 'numeric'
        }).format(date);
    }

    _formatTimeOnly(value) {
        if (!value) return '';
        const date = new Date(value);
        if (Number.isNaN(date.getTime())) return '';
        return new Intl.DateTimeFormat('en-US', {
            hour: 'numeric',
            minute: '2-digit'
        }).format(date);
    }

    _formatTimeRange(startValue, endValue) {
        if (!startValue) return '';
        const start = new Date(startValue);
        if (Number.isNaN(start.getTime())) return '';

        const timeFmt = new Intl.DateTimeFormat('en-US', {
            hour: 'numeric',
            minute: '2-digit'
        });

        const startLabel = timeFmt.format(start);
        if (!endValue) return startLabel;

        const end = new Date(endValue);
        if (Number.isNaN(end.getTime())) return startLabel;
        return `${startLabel} - ${timeFmt.format(end)}`;
    }

    _formatFullDateTimeRange(startValue, endValue) {
        if (!startValue) return '';
        const start = new Date(startValue);
        if (Number.isNaN(start.getTime())) return '';

        const dateFmt = new Intl.DateTimeFormat('en-US', {
            month: 'short',
            day: '2-digit',
            year: 'numeric',
            hour: 'numeric',
            minute: '2-digit'
        });

        const startLabel = dateFmt.format(start);
        if (!endValue) return startLabel;

        const end = new Date(endValue);
        if (Number.isNaN(end.getTime())) return startLabel;
        return `${startLabel} - ${dateFmt.format(end)}`;
    }

    _loadMyRegistrations() {
        this.isMyRegLoading = true;
        getMyRegistrations()
            .then(data => {
                this.myRegistrations = data;
            })
            .catch(() => {
                // silently swallow; non-critical
            })
            .finally(() => {
                this.isMyRegLoading = false;
            });
    }

    handleSelectWorkshop(event) {
        const workshopId = event.currentTarget.dataset.workshopid;
        const workshop = this.availableWorkshops.find(w => w.workshopId === workshopId);
        if (workshop) {
            this.selectedWorkshopForModal = {
                ...workshop,
                workshopFiles: [],
                hasWorkshopFiles: false,
                hasRestrictedFiles: false
            };
            this.selectedBatchLabel = null;
            this.isWorkshopDetailsModalOpen = true;
            this.workshopFilesError = '';
            this.loadWorkshopFiles(workshop.workshopId);
            
            // Debug: Log workshop data to verify batch details
            console.log('[Workshop Modal] Selected Workshop:', {
                name: workshop.name,
                isRegistered: workshop.isRegistered,
                registeredBatchLabel: workshop.registeredBatchLabel,
                batchOptions: workshop.batchOptions.map(opt => ({
                    label: opt.label,
                    isRegisteredBatch: opt.isRegisteredBatch,
                    fullDateTimeRange: opt.fullDateTimeRange,
                    mode: opt.mode,
                    location: opt.location
                }))
            });
        }
    }

    async loadWorkshopFiles(workshopId) {
        if (!workshopId) {
            return;
        }

        this.isWorkshopFilesLoading = true;
        this.workshopFilesError = '';
        try {
            const response = await getStudentWorkshopFiles({ workshopId });
            const files = (response?.files || []).map(fileRecord => ({
                ...fileRecord,
                formattedSize: this.formatFileSize(fileRecord.contentSize),
                formattedDate: this._formatDateTime(fileRecord.uploadedDate),
                accessLabel: fileRecord.accessScope === 'ALL_ELIGIBLE' ? 'All Eligible' : 'Registered Only'
            }));

            if (this.selectedWorkshopForModal && this.selectedWorkshopForModal.workshopId === workshopId) {
                this.selectedWorkshopForModal = {
                    ...this.selectedWorkshopForModal,
                    workshopFiles: files,
                    hasWorkshopFiles: files.length > 0,
                    hasRestrictedFiles: !!response?.hasRestrictedFiles
                };
            }
        } catch (error) {
            this.workshopFilesError = this._extractApexErrorMessage(error) || 'Unable to load workshop files.';
        } finally {
            this.isWorkshopFilesLoading = false;
        }
    }

    async handleStudentWorkshopFileDownload(event) {
        const workshopId = event.currentTarget.dataset.workshopid;
        const contentVersionId = event.currentTarget.dataset.versionid;
        const fileName = event.currentTarget.dataset.title;
        const fileExtension = event.currentTarget.dataset.extension;

        if (!workshopId || !contentVersionId) {
            return;
        }

        this.isWorkshopFilesLoading = true;
        try {
            const base64Data = await downloadWorkshopFile({ workshopId, contentVersionId });
            this.downloadBase64File(base64Data, fileName, fileExtension);
            await this.loadWorkshopFiles(workshopId);
            this.showToast('Success', 'Workshop file downloaded.', 'success');
        } catch (error) {
            const message = this._extractApexErrorMessage(error) || 'Unable to download workshop file.';
            this.showToast('Error', message, 'error');
        } finally {
            this.isWorkshopFilesLoading = false;
        }
    }

    downloadBase64File(base64Data, fileName, fileExtension) {
        const byteCharacters = atob(base64Data);
        const byteArrays = [];

        for (let offset = 0; offset < byteCharacters.length; offset += 512) {
            const slice = byteCharacters.slice(offset, offset + 512);
            const byteNumbers = new Array(slice.length);
            for (let index = 0; index < slice.length; index++) {
                byteNumbers[index] = slice.charCodeAt(index);
            }
            byteArrays.push(new Uint8Array(byteNumbers));
        }

        const blob = new Blob(byteArrays);
        const downloadUrl = URL.createObjectURL(blob);
        const anchor = document.createElement('a');
        anchor.href = downloadUrl;
        anchor.download = fileExtension ? `${fileName}.${fileExtension}` : fileName;
        document.body.appendChild(anchor);
        anchor.click();
        document.body.removeChild(anchor);
        URL.revokeObjectURL(downloadUrl);
    }

    formatFileSize(bytes) {
        if (!bytes) {
            return '0 Bytes';
        }
        const units = ['Bytes', 'KB', 'MB', 'GB'];
        const unitIndex = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
        const size = bytes / Math.pow(1024, unitIndex);
        return `${size.toFixed(unitIndex === 0 ? 0 : 1)} ${units[unitIndex]}`;
    }

    handleSelectBatchLabel(event) {
        event.stopPropagation();
        const label = event.currentTarget.dataset.label;
        this.selectedBatchLabel = label;
        
        // Update selected class on batch option cards
        const cards = this.template.querySelectorAll('.ws-batch-option-card');
        cards.forEach(card => {
            if (card.dataset.label === label) {
                card.classList.add('ws-batch-option-card--selected');
            } else {
                card.classList.remove('ws-batch-option-card--selected');
            }
        });
    }

    handleRegisterFromModal() {
        if (!this.selectedWorkshopForModal || this.isRegistering) {
            return;
        }

        if (this.selectedWorkshopForModal.isReadOnlyWorkshop) {
            this.showToast('Read-Only Workshop', 'This workshop does not require registration. Please review the details only.', 'info');
            return;
        }

        if (!this.selectedBatchLabel) {
            this.showToast('Validation Error', 'Please select a batch option.', 'error');
            return;
        }
        
        this.isRegistering = true;
        registerForWorkshop({ 
            workshopId: this.selectedWorkshopForModal.workshopId, 
            batchLabel: this.selectedBatchLabel 
        })
            .then(result => {
                if (!result.success) {
                    this.showToast('Registration Failed', result.message || 'Registration could not be completed.', 'error');
                    return;
                }
                if (result.showWarning) {
                    this.showToast('Waitlisted', result.message || 'You have been placed on the waitlist.', 'warning');
                } else {
                    this.showToast('Registered!', result.message || 'You have been successfully registered.', 'success');
                }
                this.handleCloseWorkshopDetailsModal();
                this._loadEligibleWorkshops();
                this._loadMyRegistrations();
            })
            .catch(err => {
                const msg = (err.body && err.body.message) ? err.body.message : 'Registration failed.';
                this.showToast('Error', msg, 'error');
            })
            .finally(() => {
                this.isRegistering = false;
            });
    }

    handleCloseWorkshopDetailsModal() {
        this.isWorkshopDetailsModalOpen = false;
        this.selectedWorkshopForModal = null;
        this.selectedBatchLabel = null;
        this.workshopFilesError = '';
    }

    handleViewRegistrationDetails(event) {
        const regId = event.currentTarget.dataset.regid;
        const registration = this.myRegistrations.find(r => r.Id === regId);
        if (registration) {
            this.selectedRegistrationForModal = registration;
            this.isRegistrationDetailsModalOpen = true;
        }
    }

    handleCloseRegistrationDetailsModal() {
        this.isRegistrationDetailsModalOpen = false;
        this.selectedRegistrationForModal = null;
    }

    // ════════════════════════════════════════════════════════════════════════
    //  GETTERS — Booking Modal
    // ════════════════════════════════════════════════════════════════════════
    get primaryAdvisorUserId() {
        return this.directoryData.primaryAdvisorUserId || null;
    }

    get advisorDisplayName() {
        return this.directoryData.primaryAdvisor ? this.directoryData.primaryAdvisor.Name : 'Your Advisor';
    }

    get minDate() {
        const d = new Date();
        d.setDate(d.getDate() + 1);
        return d.toISOString().split('T')[0];
    }

    get maxDate() {
        const d = new Date();
        d.setDate(d.getDate() + 30);
        return d.toISOString().split('T')[0];
    }

    get processedSlots() {
        return this.availableSlots.map(s => ({
            ...s,
            pillClass: this._slotPillClass(s)
        }));
    }

    _slotPillClass(slot) {
        if (!slot.isAvailable) return 'slot-pill slot-pill--disabled';
        if (this.selectedSlot && this.selectedSlot.startISO === slot.startISO) return 'slot-pill slot-pill--selected';
        return 'slot-pill';
    }

    get slotOptions() {
        return this.availableSlots
            .filter(s => s.isAvailable)
            .map(s => ({ label: s.label, value: s.startISO }));
    }

    get isSubmitDisabled() {
        return this.isSubmitting || !this.selectedSlot || !this.formTitle || !this.formType || !this.formReason;
    }

    get modeOptions() {
        return [{ label: 'In-Person', value: 'In-Person' }, { label: 'Virtual', value: 'Virtual' }];
    }

    // R1: ISB-6020 - Dynamic picklist values from Appointment_Request__c.Request_Type__c
    get typeOptions() {
        if (!this.requestTypePicklist || !this.requestTypePicklist.data) {
            // Fallback: return empty array while loading
            return [];
        }
        return this.requestTypePicklist.data.values.map(option => ({
            label: option.label,
            value: option.value
        }));
    }

    // ════════════════════════════════════════════════════════════════════════
    //  GETTERS — My Appointments
    // ════════════════════════════════════════════════════════════════════════
    get filteredAppointments() {
        const src = this.appointmentsStatusFilter === 'All'
            ? this.appointmentsData
            : this.appointmentsData.filter(a => a.status === this.appointmentsStatusFilter);
        return src.map(a => ({
            ...a,
            rowClass: (this.selectedAppointment && this.selectedAppointment.id === a.id)
                ? 'appt-row appt-row--active'
                : 'appt-row'
        }));
    }

    get hasFilteredAppointments() {
        return this.filteredAppointments.length > 0;
    }

    get allFilterClass()       { return this._filterPillClass('All'); }
    get pendingFilterClass()   { return this._filterPillClass('Pending'); }
    get approvedFilterClass()  { return this._filterPillClass('Approved'); }
    get rejectedFilterClass()  { return this._filterPillClass('Rejected'); }
    get completedFilterClass() { return this._filterPillClass('Completed'); }

    _filterPillClass(filter) {
        return this.appointmentsStatusFilter === filter ? 'filter-pill filter-pill--active' : 'filter-pill';
    }

    _apptStatusClass(status) {
        const map = {
            'Pending':   'appt-status appt-status--pending',
            'Approved':  'appt-status appt-status--approved',
            'Rejected':  'appt-status appt-status--rejected',
            'Completed': 'appt-status appt-status--completed',
            'No Show':   'appt-status appt-status--noshow',
            'Cancelled': 'appt-status appt-status--cancelled'
        };
        return map[status] || 'appt-status';
    }

    // ════════════════════════════════════════════════════════════════════════
    //  GETTERS — Checklists / Tasks
    // ════════════════════════════════════════════════════════════════════════
    get hasChecklists() {
        return this.checklistData && this.checklistData.length > 0;
    }

    get isSelectedTaskCompleted() {
        return this.selectedTask && ['Completed', 'Complete', 'Closed', 'Waived'].includes(this.selectedTask.status);
    }

    // ════════════════════════════════════════════════════════════════════════
    //  HANDLERS — Booking Modal
    // ════════════════════════════════════════════════════════════════════════
    handleOpenBookingModal() {
        this._resetBookingForm();
        this.isBookingModalOpen = true;
    }

    handleCloseBookingModal() {
        this.isBookingModalOpen = false;
        this._resetBookingForm();
    }

    handleDateChange(event) {
        const selectedDateValue = event.target.value;
        
        // Check if selected date is a weekend (0 = Sunday, 6 = Saturday)
        if (selectedDateValue) {
            const selectedDate = new Date(selectedDateValue + 'T00:00:00');
            const dayOfWeek = selectedDate.getDay();
            
            if (dayOfWeek === 0 || dayOfWeek === 6) {
                // Weekend selected
                this.showToast('Weekend Not Available', 'Appointments cannot be booked on weekends. Please select a weekday (Monday-Friday).', 'warning');
                this.selectedDate = '';
                this.selectedSlot = null;
                this.selectedSlotISO = '';
                this.availableSlots = [];
                return;
            }
        }
        
        this.selectedDate = selectedDateValue;
        this.selectedSlot = null;
        this.selectedSlotISO = '';
        this.isSlotsLoading = true;
        this.noSlotsAvailable = false;
        this.availableSlots = [];
        // Wire will re-fire with new dateString; isSlotsLoading cleared in wiredSlots handler
    }

    handleSlotPicklistChange(event) {
        const startISO = event.target.value;
        this.selectedSlotISO = startISO;
        const slot = this.availableSlots.find(s => s.startISO === startISO);
        if (slot && slot.isAvailable) {
            this.selectedSlot = { startISO, endISO: slot.endISO, label: slot.label };
        }
    }

    handleFormChange(event) {
        const field = event.target.dataset.field;
        if (field === 'title')  this.formTitle  = event.target.value;
        if (field === 'mode')   this.formMode   = event.target.value;
        if (field === 'type')   this.formType   = event.target.value;
        if (field === 'reason') this.formReason = event.target.value;
    }

    handleSubmitRequest() {
        if (!this.selectedSlot || !this.formTitle || !this.formType || !this.formReason) {
            this.showToast('Validation Error', 'Please fill out all required fields.', 'error');
            return;
        }
        this.isSubmitting = true;
        const requestPayload = {
            sobjectType: 'Appointment_Request__c',
            Request_Type__c: this.formType,
            Reason__c: this.formReason,
            Mode__c: this.formMode || null
        };
        createAppointmentRequest({
            requestRecord: requestPayload,
            startISO: this.selectedSlot.startISO,
            endISO:   this.selectedSlot.endISO,
            meetingTitle: this.formTitle
        })
        .then(() => {
            this.showToast('Success', 'Your appointment request has been submitted.', 'success');
            this.handleCloseBookingModal();
            return refreshApex(this.wiredAppointmentsResult);
        })
        .catch(error => {
            const msg = (error.body && error.body.message) ? error.body.message : 'An unknown error occurred.';
            this.showToast('Submission Error', msg, 'error');
        })
        .finally(() => {
            this.isSubmitting = false;
        });
    }

    _resetBookingForm() {
        this.selectedDate    = '';
        this.selectedSlot    = null;
        this.selectedSlotISO = '';
        this.formMode        = '';
        this.formTitle       = '';
        this.formType        = '';
        this.formReason      = '';
        this.availableSlots  = [];
        this.noSlotsAvailable = false;
        this.isSlotsLoading   = false;
    }

    // ════════════════════════════════════════════════════════════════════════
    //  HANDLERS — Profile Modal
    // ════════════════════════════════════════════════════════════════════════
    handleViewProfile(event) {
        const id = event.currentTarget.dataset.id;
        const contact = this._findContactById(id);
        this.profileContactData = contact;
        this.profileContactName = contact.Name || '';
        this.profileContactRole = contact._Role || '';
        this.isProfileModalOpen = true;
    }

    handleCloseProfileModal() {
        this.isProfileModalOpen = false;
        this.profileContactData = {};
    }

    _findContactById(id) {
        if (this.directoryData.primaryAdvisor?.Id === id)
            return { ...this.directoryData.primaryAdvisor, _Role: 'Primary Advisor' };
        const adv = this.directoryData.allAdvisors?.find(a => a.Id === id);
        if (adv) return { ...adv, _Role: 'Advisor' };
        const asc = this.directoryData.academicAssociates?.find(a => a.Id === id);
        if (asc) return { ...asc, _Role: 'Academic Associate' };
        const tut = this.directoryData.tutors?.find(t => t.Id === id);
        if (tut) return { ...tut, _Role: 'Tutor' };
        return {};
    }

    // ════════════════════════════════════════════════════════════════════════
    //  HANDLERS — My Appointments
    // ════════════════════════════════════════════════════════════════════════
    handleFilterChange(event) {
        this.appointmentsStatusFilter = event.currentTarget.dataset.filter;
        this.selectedAppointment = null;
    }

    handleAppointmentSelect(event) {
        const id = event.currentTarget.dataset.id;
        const appt = this.appointmentsData.find(a => a.id === id);
        this.selectedAppointment = appt ? { ...appt } : null;
    }

    handleBookAgain() {
        if (!this.selectedAppointment) return;
        this.formType   = this.selectedAppointment.requestType || '';
        this.formMode   = this.selectedAppointment.mode        || '';
        this.formReason = this.selectedAppointment.reason      || '';
        this.selectedSlot = null;
        this.selectedDate = '';
        this.isBookingModalOpen = true;
    }

    // ════════════════════════════════════════════════════════════════════════
    //  HANDLERS — Checklists / Tasks
    // ════════════════════════════════════════════════════════════════════════
    handleToggleChecklist(event) {
        const checklistId = event.currentTarget.dataset.id;
        this.checklistData = this.checklistData.map(cl => {
            if (cl.checklistId === checklistId) {
                const expanded = !cl.isExpanded;
                return { ...cl, isExpanded: expanded, chevronIcon: expanded ? 'utility:chevrondown' : 'utility:chevronright' };
            }
            return cl;
        });
    }

    handleRowClick(event) {
        const itemId = event.currentTarget.dataset.id;
        let foundTask;
        for (const checklist of this.checklistData) {
            foundTask = checklist.items.find(i => i.itemId === itemId);
            if (foundTask) break;
        }
        if (foundTask) {
            this.selectedTask     = { ...foundTask };
            this.editingItemId    = itemId;
            this.editingStatus    = foundTask.status   || '';
            this.editingComments  = foundTask.comments || '';
            this.isTaskModalOpen  = true;
        }
    }

    handleCloseTaskModal() {
        this.isTaskModalOpen = false;
        this.selectedTask    = {};
        this.editingItemId   = null;
        this.editingStatus   = '';
        this.editingComments = '';
        this.checklistData = this.checklistData.map(cl => ({
            ...cl,
            items: cl.items.map(i => ({ ...i, isBeingEdited: false }))
        }));
    }

    handleCommentsChange(event) {
        this.editingComments = event.target.value;
    }

    handleSaveComments() {
        if (!this.editingItemId) return;
        this.isSavingItem = true;
        updateChecklistItem({
            itemId: this.editingItemId,
            newStatus: this.editingStatus,
            newComments: this.editingComments
        })
        .then(() => {
            this.showToast('Saved', 'Your comment has been saved.', 'success');
            this.selectedTask = { ...this.selectedTask, comments: this.editingComments };
            this.checklistData = this.checklistData.map(cl => ({
                ...cl,
                items: cl.items.map(i => i.itemId === this.editingItemId
                    ? { ...i, comments: this.editingComments }
                    : i
                )
            }));
            return refreshApex(this.wiredChecklistResult);
        })
        .catch(error => {
            const msg = this._extractApexErrorMessage(error) || 'Failed to save comment.';
            this.showToast('Error', msg, 'error');
        })
        .finally(() => {
            this.isSavingItem = false;
        });
    }

    handleMarkAsComplete() {
        this._updateTaskStatus(STATUS_COMPLETED, true);
    }

    handleReopenTask() {
        this._updateTaskStatus(STATUS_IN_PROGRESS);
    }

    _updateTaskStatus(newStatus, allowCompleteFallback = false) {
        this.isSavingItem = true;
        updateChecklistItem({
            itemId: this.editingItemId,
            newStatus: newStatus,
            newComments: this.editingComments
        })
        .then(() => {
            this.showToast('Success', `Task updated to ${newStatus}.`, 'success');
            this.handleCloseTaskModal();
            return refreshApex(this.wiredChecklistResult);
        })
        .catch(error => {
            const msg = this._extractApexErrorMessage(error);
            if (allowCompleteFallback && newStatus === STATUS_COMPLETED && this._isLikelyStatusPicklistError(msg)) {
                this._updateTaskStatus('Complete', false);
                return;
            }
            console.error('[SAP] updateTaskStatus error:', error);
            this.showToast('Error', msg || 'Failed to update task status.', 'error');
        })
        .finally(() => {
            this.isSavingItem = false;
        });
    }

    _extractApexErrorMessage(error) {
        if (!error) return '';
        if (error.body) {
            if (typeof error.body.message === 'string' && error.body.message) {
                return error.body.message;
            }
            if (Array.isArray(error.body) && error.body.length && error.body[0]?.message) {
                return error.body[0].message;
            }
            if (error.body.output?.errors?.length && error.body.output.errors[0].message) {
                return error.body.output.errors[0].message;
            }
        }
        return error.message || '';
    }

    _isLikelyStatusPicklistError(message) {
        if (!message) return false;
        const text = String(message).toLowerCase();
        return text.includes('restricted picklist')
            || text.includes('bad value')
            || text.includes('invalid_or_null_for_restricted_picklist')
            || text.includes('status__c');
    }

    // ════════════════════════════════════════════════════════════════════════
    //  HELPERS
    // ════════════════════════════════════════════════════════════════════════
    computeStatusClass(status) {
        const map = {
            'Not Started': 'status-badge status-badge--not-started',
            'In Progress': 'status-badge status-badge--in-progress',
            'Completed':   'status-badge status-badge--completed',
            'Blocked':     'status-badge status-badge--blocked',
            'Waived':      'status-badge status-badge--waived',
            'Open':        'status-badge status-badge--open',
            'Closed':      'status-badge status-badge--closed',
            'Draft':       'status-badge status-badge--draft',
            'Published':   'status-badge status-badge--active'
        };
        return map[status] || 'status-badge';
    }

    computePriorityClass(priority) {
        const map = {
            'High':   'priority-badge priority-badge--high',
            'Medium': 'priority-badge priority-badge--medium',
            'Low':    'priority-badge priority-badge--low'
        };
        return map[priority] || 'priority-badge';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}