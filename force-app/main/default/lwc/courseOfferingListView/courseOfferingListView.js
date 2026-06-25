import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin }               from 'lightning/navigation';
import { ShowToastEvent }                from 'lightning/platformShowToastEvent';

// Apex imports
import getAcademicYearOptions    from '@salesforce/apex/CourseOfferingListViewController.getAcademicYearOptions';
import getProgramOptions         from '@salesforce/apex/CourseOfferingListViewController.getProgramOptions';
import getAcademicTermOptions    from '@salesforce/apex/CourseOfferingListViewController.getAcademicTermOptions';
import getAcademicSessionOptions from '@salesforce/apex/CourseOfferingListViewController.getAcademicSessionOptions';
import getCourseOfferings        from '@salesforce/apex/CourseOfferingListViewController.getCourseOfferings';

// ─── Constants ─────────────────────────────────────────────────────────────
const DEFAULT_PAGE_SIZE = 50;
const PAGE_SIZE_OPTIONS = [
    { label: '5',   value: '5'   },
    { label: '10',  value: '10'  },
    { label: '25',  value: '25'  },
    { label: '50',  value: '50'  },
    { label: '100', value: '100' }
];

const EMPTY_FILTERS = {
    academicYear    : '',
    program         : '',
    academicTerm    : '',
    academicSession : ''
};

// Column definitions for lightning-datatable (Supports resizable columns)
const COLUMNS = [
    {
        label: 'Name',
        fieldName: 'recordUrl',
        type: 'url',
        typeAttributes: { label: { fieldName: 'name' }, target: '_self' },
        sortable: true,
        initialWidth: 200
    },
    { label: 'Learning Course', fieldName: 'learningCourse', type: 'text', sortable: true },
    { label: 'Academic Year', fieldName: 'academicYearName', type: 'text', sortable: true },
    { label: 'Program', fieldName: 'programName', type: 'text', sortable: true },
    { label: 'Academic Term', fieldName: 'academicTermName', type: 'text', sortable: true },
    { label: 'Academic Session', fieldName: 'academicSession', type: 'text', sortable: true },
    { label: 'Location', fieldName: 'location', type: 'text', sortable: true }
];

export default class CourseOfferingListView extends NavigationMixin(LightningElement) {

    // ── Reactive State ─────────────────────────────────────────────────────
    @track filters      = { ...EMPTY_FILTERS };
    @track result       = null;
    @track isLoading    = false;
    @track hasError     = false;
    @track errorMessage = '';

    columns = COLUMNS;

    // Filter option arrays
    @track academicYearOptions    = [];
    @track programOptions         = [];
    @track academicTermOptions    = [];
    @track academicSessionOptions = [];

    // Pagination & sort
    currentPage   = 1;
    pageSize      = DEFAULT_PAGE_SIZE;
    sortField     = 'name';
    sortDirection = 'asc';

    pageSizeOptions = PAGE_SIZE_OPTIONS;

    // ── Lifecycle ──────────────────────────────────────────────────────────
    connectedCallback() {
        this.loadInitialFiltersAndData();
    }

    async loadInitialFiltersAndData() {
        this.isLoading = true;
        try {
            const [years, progs, terms, sessions] = await Promise.all([
                getAcademicYearOptions(),
                getProgramOptions(),
                getAcademicTermOptions({ 
                    programName: this.filters.program, 
                    academicYearName: this.filters.academicYear 
                }),
                getAcademicSessionOptions({ 
                    programName: this.filters.program,
                    termName: this.filters.academicTerm 
                })
            ]);
            
            this.academicYearOptions    = years;
            this.programOptions         = progs;
            this.academicTermOptions    = terms;
            this.academicSessionOptions = sessions;
        } catch (err) {
            this.showToast('Warning', 'Could not load filter options.', 'warning');
        }
        await this.fetchData();
        this.isLoading = false;
    }

    async fetchData() {
        this.hasError = false;
        try {
            const res = await getCourseOfferings({
                academicYear    : this.filters.academicYear    || null,
                program         : this.filters.program         || null,
                academicTerm    : this.filters.academicTerm    || null,
                academicSession : this.filters.academicSession || null,
                sortField       : this.sortField,
                sortDirection   : this.sortDirection,
                pageNumber      : this.currentPage,
                pageSize        : this.pageSize
            });

            res.records = res.records.map(r => ({
                ...r,
                recordUrl: `/lightning/r/CourseOffering/${r.id}/view`
            }));

            this.result = res;
        } catch (err) {
            this.hasError     = true;
            this.errorMessage = this.extractError(err);
            this.result       = null;
        }
    }

    // ── Filter-change Handlers (with Dependencies) ─────────────────────────

    async handleAcademicYearChange(event) {
        const val = event.detail.value;
        this.filters     = { ...this.filters, academicYear: val, academicTerm: '', academicSession: '' };
        this.currentPage = 1;
        this.isLoading   = true;

        try {
            const [terms, sessions] = await Promise.all([
                getAcademicTermOptions({ 
                    programName: this.filters.program, 
                    academicYearName: val 
                }),
                getAcademicSessionOptions({ 
                    programName: this.filters.program,
                    termName: '' 
                })
            ]);
            this.academicTermOptions    = terms;
            this.academicSessionOptions = sessions;
        } catch (e) { /* swallow */ }

        await this.fetchData();
        this.isLoading = false;
    }

    async handleProgramChange(event) {
        const val = event.detail.value;
        this.filters = { ...this.filters, program: val, academicTerm: '', academicSession: '' };
        this.currentPage = 1;
        this.isLoading   = true;

        try {
            const [terms, sessions] = await Promise.all([
                getAcademicTermOptions({ 
                    programName: val, 
                    academicYearName: this.filters.academicYear 
                }),
                getAcademicSessionOptions({ 
                    programName: val,
                    termName: '' 
                })
            ]);
            this.academicTermOptions    = terms;
            this.academicSessionOptions = sessions;
        } catch (e) { /* swallow */ }

        await this.fetchData();
        this.isLoading = false;
    }

    async handleAcademicTermChange(event) {
        const val = event.detail.value;
        this.filters = { ...this.filters, academicTerm: val, academicSession: '' };
        this.currentPage = 1;
        this.isLoading   = true;

        try {
            this.academicSessionOptions = await getAcademicSessionOptions({ 
                programName: this.filters.program,
                termName: val 
            });
        } catch (e) { /* swallow */ }

        await this.fetchData();
        this.isLoading = false;
    }

    async handleAcademicSessionChange(event) {
        this.filters     = { ...this.filters, academicSession: event.detail.value };
        this.currentPage = 1;
        this.isLoading   = true;
        await this.fetchData();
        this.isLoading = false;
    }

    async handleClearFilters() {
        this.filters     = { ...EMPTY_FILTERS };
        this.currentPage = 1;
        await this.loadInitialFiltersAndData();
    }

    async handleRefresh() {
        this.isLoading = true;
        await this.fetchData();
        this.isLoading = false;
    }

    // ── Sorting (Datatable compatible) ─────────────────────────────────────
    async handleSort(event) {
        const { fieldName: sortedBy, sortDirection } = event.detail;
        this.sortField     = sortedBy === 'recordUrl' ? 'name' : sortedBy;
        this.sortDirection = sortDirection;
        this.currentPage   = 1;
        
        this.isLoading = true;
        await this.fetchData();
        this.isLoading = false;
    }

    // ── Pagination ─────────────────────────────────────────────────────────
    async handlePageSizeChange(event) {
        this.pageSize    = parseInt(event.detail.value, 10);
        this.currentPage = 1;
        this.isLoading   = true;
        await this.fetchData();
        this.isLoading = false;
    }

    async handleFirstPage() {
        if (this.isFirstPage) return;
        this.currentPage = 1;
        this.isLoading   = true;
        await this.fetchData();
        this.isLoading = false;
    }

    async handlePrevPage() {
        if (this.isFirstPage) return;
        this.currentPage -= 1;
        this.isLoading    = true;
        await this.fetchData();
        this.isLoading = false;
    }

    async handleNextPage() {
        if (this.isLastPage) return;
        this.currentPage += 1;
        this.isLoading    = true;
        await this.fetchData();
        this.isLoading = false;
    }

    async handleLastPage() {
        if (this.isLastPage || !this.result) return;
        this.currentPage = this.result.totalPages;
        this.isLoading   = true;
        await this.fetchData();
        this.isLoading = false;
    }

    // ── Computed Getters ───────────────────────────────────────────────────
    get hasRecords()      { return !this.isLoading && !this.hasError && this.result && this.result.records && this.result.records.length > 0; }
    get isEmpty()         { return !this.isLoading && !this.hasError && this.result && (!this.result.records || this.result.records.length === 0); }
    get hasActiveFilters(){ return Object.values(this.filters).some(v => v && v !== ''); }
    get pluralSuffix()    { return (this.result && this.result.totalCount === 1) ? '' : 's'; }
    get isFirstPage()     { return this.currentPage <= 1; }
    get isLastPage()      { return !this.result || this.currentPage >= this.result.totalPages; }

    get pageStart() {
        if (!this.result || this.result.totalCount === 0) return 0;
        return (this.currentPage - 1) * this.pageSize + 1;
    }
    get pageEnd() {
        if (!this.result) return 0;
        return Math.min(this.currentPage * this.pageSize, this.result.totalCount);
    }
    get pageSizeStr()  { return String(this.pageSize); }

    // ── Utility ────────────────────────────────────────────────────────────
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    extractError(err) {
        if (err && err.body && err.body.message) return err.body.message;
        if (err && err.message)                  return err.message;
        return 'An unexpected error occurred.';
    }
}