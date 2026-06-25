import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTrackingStats from '@salesforce/apex/FeedbackManagementController.getTrackingStats';
import getFeedbackRecords from '@salesforce/apex/FeedbackManagementController.getFeedbackRecords';
import sendReminderEmail from '@salesforce/apex/FeedbackManagementController.sendReminderEmail';

/**
 * @description Feedback Tracking Dashboard component
 * Shows statistics and feedback record list with filtering
 */
export default class FeedbackTrackingDashboard extends LightningElement {
    @api programs = [];
    @api locations = [];
    @api scenarios = [];

    @track stats = {
        totalTriggered: 0,
        totalSubmitted: 0,
        totalPending: 0,
        totalExpired: 0,
        submissionRate: 0
    };

    @track feedbackRecords = [];
    @track filteredRecords = [];
    @track isLoading = false;

    // Filters
    @track filterScenario = '';
    @track filterStatus = '';
    @track filterProgram = '';
    @track filterDateFrom = '';
    @track filterDateTo = '';

    // Pagination
    @track currentPage = 1;
    @track pageSize = 25;
    @track totalRecords = 0;

    // Columns for feedback records
    feedbackColumns = [
        { label: 'Recipient', fieldName: 'recipientName', type: 'text' },
        { label: 'AA Name', fieldName: 'aaName', type: 'text' },
        { label: 'Scenario', fieldName: 'scenario', type: 'text' },
        { label: 'Course', fieldName: 'courseName', type: 'text' },
        { label: 'Status', fieldName: 'status', type: 'text', 
            cellAttributes: { 
                class: { fieldName: 'statusClass' }
            }
        },
        { label: 'Due Date', fieldName: 'dueDate', type: 'date' },
        { label: 'Submitted', fieldName: 'submittedDate', type: 'date' },
        { label: 'Rating', fieldName: 'overallRating', type: 'number', 
            typeAttributes: { minimumFractionDigits: 1, maximumFractionDigits: 1 }
        },
        {
            type: 'action',
            typeAttributes: {
                rowActions: [
                    { label: 'Send Reminder', name: 'reminder' },
                    { label: 'View Details', name: 'view' }
                ]
            }
        }
    ];

    // Status options for filter
    get statusOptions() {
        return [
            { label: 'All Statuses', value: '' },
            { label: 'Pending', value: 'Pending' },
            { label: 'Submitted', value: 'Submitted' },
            { label: 'Expired', value: 'Expired' }
        ];
    }

    get scenarioFilterOptions() {
        return [
            { label: 'All Scenarios', value: '' },
            ...this.scenarios.map(s => ({ label: s.label, value: s.value }))
        ];
    }

    get programFilterOptions() {
        return [
            { label: 'All Programs', value: '' },
            ...this.programs.map(p => ({ label: p.label, value: p.value }))
        ];
    }

    // Computed stats
    get pendingPercentage() {
        if (this.stats.totalTriggered === 0) return 0;
        return Math.round((this.stats.totalPending / this.stats.totalTriggered) * 100);
    }

    get submittedPercentage() {
        if (this.stats.totalTriggered === 0) return 0;
        return Math.round((this.stats.totalSubmitted / this.stats.totalTriggered) * 100);
    }

    get expiredPercentage() {
        if (this.stats.totalTriggered === 0) return 0;
        return Math.round((this.stats.totalExpired / this.stats.totalTriggered) * 100);
    }

    // Pagination
    get totalPages() {
        return Math.ceil(this.totalRecords / this.pageSize);
    }

    get paginatedRecords() {
        const start = (this.currentPage - 1) * this.pageSize;
        const end = start + this.pageSize;
        return this.filteredRecords.slice(start, end);
    }

    get hasPreviousPage() {
        return this.currentPage > 1;
    }

    get hasNextPage() {
        return this.currentPage < this.totalPages;
    }

    get disablePrevious() {
        return !this.hasPreviousPage;
    }

    get disableNext() {
        return !this.hasNextPage;
    }

    get pageInfo() {
        const start = ((this.currentPage - 1) * this.pageSize) + 1;
        const end = Math.min(this.currentPage * this.pageSize, this.totalRecords);
        return `${start}-${end} of ${this.totalRecords}`;
    }

    // Lifecycle
    connectedCallback() {
        this.loadData();
    }

    // Data loading
    async loadData() {
        this.isLoading = true;
        try {
            await Promise.all([
                this.loadStats(),
                this.loadFeedbackRecords()
            ]);
        } catch (error) {
            this.showError('Error loading data', error);
        } finally {
            this.isLoading = false;
        }
    }

    async loadStats() {
        try {
            const filters = this.buildFilterParams();
            this.stats = await getTrackingStats({ filtersJson: JSON.stringify(filters) });
        } catch (error) {
            this.showError('Error loading statistics', error);
        }
    }

    async loadFeedbackRecords() {
        try {
            const filters = this.buildFilterParams();
            const records = await getFeedbackRecords({ filtersJson: JSON.stringify(filters) });
            
            // Add status class for styling
            this.feedbackRecords = records.map(rec => ({
                ...rec,
                statusClass: this.getStatusClass(rec.status)
            }));
            
            this.applyFilters();
        } catch (error) {
            this.showError('Error loading feedback records', error);
        }
    }

    buildFilterParams() {
        return {
            scenario: this.filterScenario,
            status: this.filterStatus,
            programId: this.filterProgram,
            dateFrom: this.filterDateFrom,
            dateTo: this.filterDateTo
        };
    }

    getStatusClass(status) {
        switch (status) {
            case 'Submitted':
                return 'slds-text-color_success';
            case 'Pending':
                return 'slds-text-color_default';
            case 'Expired':
                return 'slds-text-color_error';
            default:
                return '';
        }
    }

    // Filter handlers
    handleScenarioFilter(event) {
        this.filterScenario = event.detail.value;
        this.loadData();
    }

    handleStatusFilter(event) {
        this.filterStatus = event.detail.value;
        this.applyFilters();
    }

    handleProgramFilter(event) {
        this.filterProgram = event.detail.value;
        this.loadData();
    }

    handleDateFromChange(event) {
        this.filterDateFrom = event.detail.value;
        this.loadData();
    }

    handleDateToChange(event) {
        this.filterDateTo = event.detail.value;
        this.loadData();
    }

    handleClearFilters() {
        this.filterScenario = '';
        this.filterStatus = '';
        this.filterProgram = '';
        this.filterDateFrom = '';
        this.filterDateTo = '';
        this.loadData();
    }

    applyFilters() {
        let records = [...this.feedbackRecords];

        // Status filter (client-side for quick response)
        if (this.filterStatus) {
            records = records.filter(r => r.status === this.filterStatus);
        }

        this.filteredRecords = records;
        this.totalRecords = records.length;
        this.currentPage = 1;
    }

    // Pagination handlers
    handlePreviousPage() {
        if (this.hasPreviousPage) {
            this.currentPage--;
        }
    }

    handleNextPage() {
        if (this.hasNextPage) {
            this.currentPage++;
        }
    }

    // Row actions
    handleRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;

        switch (action.name) {
            case 'reminder':
                this.handleSendReminder(row);
                break;
            case 'view':
                this.handleViewDetails(row);
                break;
        }
    }

    async handleSendReminder(record) {
        if (record.status !== 'Pending') {
            this.showToast('Cannot Send Reminder', 'Reminders can only be sent for Pending feedback', 'warning');
            return;
        }

        try {
            this.isLoading = true;
            await sendReminderEmail({ feedbackId: record.feedbackId });
            this.showToast('Success', 'Reminder email sent successfully', 'success');
        } catch (error) {
            this.showError('Error sending reminder', error);
        } finally {
            this.isLoading = false;
        }
    }

    handleViewDetails(record) {
        // Navigate to feedback record
        this.dispatchEvent(new CustomEvent('viewfeedback', {
            detail: { feedbackId: record.feedbackId }
        }));
    }

    handleRefresh() {
        this.loadData();
    }

    // Export functionality
    handleExport() {
        // Build CSV content
        let csvContent = 'Recipient,AA Name,Scenario,Course,Status,Due Date,Submitted Date,Rating\n';
        
        this.filteredRecords.forEach(rec => {
            csvContent += `"${rec.recipientName || ''}","${rec.aaName || ''}","${rec.scenario || ''}","${rec.courseName || ''}","${rec.status || ''}","${rec.dueDate || ''}","${rec.submittedDate || ''}","${rec.overallRating || ''}"\n`;
        });

        // Create download link
        const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
        const url = URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.href = url;
        link.download = `feedback_tracking_${new Date().toISOString().split('T')[0]}.csv`;
        link.click();
        URL.revokeObjectURL(url);

        this.showToast('Export Complete', 'CSV file downloaded', 'success');
    }

    // Utilities
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }

    showError(title, error) {
        console.error(title, error);
        const message = error.body?.message || error.message || 'Unknown error';
        this.showToast(title, message, 'error');
    }
}