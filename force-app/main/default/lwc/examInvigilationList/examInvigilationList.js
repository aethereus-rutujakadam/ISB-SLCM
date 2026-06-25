import { LightningElement, track } from 'lwc';
import getUpcomingInvigilations from '@salesforce/apex/ExamAAController.getUpcomingInvigilations';

export default class ExamInvigilationList extends LightningElement {
    @track records = [];
    @track filteredRecords = [];
    @track loading = true;

    // Filter values
    @track selectedCourse = '';
    @track selectedProgram = '';
    @track selectedTerm = '';
    @track selectedVenueMode = '';

    // Filter options
    @track courseOptions = [];
    @track programOptions = [];
    @track termOptions = [];
    @track venueModeOptions = [];

    columns = [
        { 
            label: 'Exam', 
            fieldName: 'examUrl', 
            type: 'url', 
            sortable: true,
            typeAttributes: {
                label: { fieldName: 'examName' },
                target: '_self'
            }
        },
        { label: 'Course', fieldName: 'course', type: 'text' },
        { label: 'Program', fieldName: 'program', type: 'text' },
        { label: 'Term', fieldName: 'term', type: 'text' },
        { label: 'Date of Exam', fieldName: 'examDate', type: 'date', sortable: true },
        { label: 'Exam Start Time', fieldName: 'startTime', type: 'text', sortable: true },
        { label: 'Exam End Time', fieldName: 'endTime', type: 'text', sortable: true },
        { label: 'Slot', fieldName: 'slot', type: 'text' },
        { label: 'Venue / Mode', fieldName: 'venueMode', type: 'text' },
        { label: 'Assigned Academic Associates', fieldName: 'allAssignedAAs', type: 'text', wrapText: true },
        { label: 'Special Instructions', fieldName: 'specialInstructions', type: 'text' }
    ];

    get totalRecords() {
        return this.records ? this.records.length : 0;
    }

    connectedCallback() {
        this.loadData();
    }

    // Helper method to format Time to HH:MM
    formatTime(timeValue) {
        if (!timeValue) return '';
        
        try {
            // Time comes as milliseconds from midnight
            // Convert to HH:MM format
            const totalMs = timeValue;
            const hours = Math.floor(totalMs / (1000 * 60 * 60));
            const minutes = Math.floor((totalMs % (1000 * 60 * 60)) / (1000 * 60));
            
            // Pad with zeros
            const hoursStr = String(hours).padStart(2, '0');
            const minutesStr = String(minutes).padStart(2, '0');
            
            return `${hoursStr}:${minutesStr}`;
        } catch (e) {
            console.error('Error formatting time:', e);
            return timeValue;
        }
    }

    loadData() {
        this.loading = true;
        getUpcomingInvigilations()
            .then(result => {
                // map server wrapper fields to datatable-friendly format
                this.records = result.map(r => {
                    return {
                        examAAId: r.examAAId,
                        examId: r.examId,
                        examName: r.examName,
                        examUrl: r.examId ? `/${r.examId}` : null,
                        course: r.course,
                        program: r.program,
                        term: r.term,
                        examDate: r.examDate,
                        startTime: this.formatTime(r.startTime),
                        endTime: this.formatTime(r.endTime),
                        slot: r.slot,
                        venueMode: (r.venue ? r.venue : '') + (r.mode ? (' / ' + r.mode) : ''),
                        allAssignedAAs: r.allAssignedAAs || '',
                        specialInstructions: r.specialInstructions
                    };
                });
                
                // Build filter options from the data
                this.buildFilterOptions();
                
                // Initially show all records
                this.filteredRecords = [...this.records];
                this.loading = false;
            })
            .catch(error => {
                console.error('Error loading invigilation:', error);
                this.records = [];
                this.filteredRecords = [];
                this.loading = false;
            });
    }

    buildFilterOptions() {
        // Extract unique values for each filter
        const courses = new Set();
        const programs = new Set();
        const terms = new Set();
        const venueModes = new Set();

        this.records.forEach(record => {
            if (record.course) courses.add(record.course);
            if (record.program) programs.add(record.program);
            if (record.term) terms.add(record.term);
            if (record.venueMode) venueModes.add(record.venueMode);
        });

        // Convert to combobox options format with "All" option
        this.courseOptions = [
            { label: 'All Courses', value: '' },
            ...Array.from(courses).sort().map(c => ({ label: c, value: c }))
        ];

        this.programOptions = [
            { label: 'All Programs', value: '' },
            ...Array.from(programs).sort().map(p => ({ label: p, value: p }))
        ];

        this.termOptions = [
            { label: 'All Terms', value: '' },
            ...Array.from(terms).sort().map(t => ({ label: t, value: t }))
        ];

        this.venueModeOptions = [
            { label: 'All Venues/Modes', value: '' },
            ...Array.from(venueModes).sort().map(v => ({ label: v, value: v }))
        ];
    }

    handleFilterChange(event) {
        const filterName = event.target.name;
        const filterValue = event.detail.value;

        // Update the selected filter value
        if (filterName === 'course') {
            this.selectedCourse = filterValue;
        } else if (filterName === 'program') {
            this.selectedProgram = filterValue;
        } else if (filterName === 'term') {
            this.selectedTerm = filterValue;
        } else if (filterName === 'venueMode') {
            this.selectedVenueMode = filterValue;
        }

        // Apply filters
        this.applyFilters();
    }

    applyFilters() {
        this.filteredRecords = this.records.filter(record => {
            // Check each filter condition
            const courseMatch = !this.selectedCourse || record.course === this.selectedCourse;
            const programMatch = !this.selectedProgram || record.program === this.selectedProgram;
            const termMatch = !this.selectedTerm || record.term === this.selectedTerm;
            const venueModeMatch = !this.selectedVenueMode || record.venueMode === this.selectedVenueMode;

            // Record must match all selected filters
            return courseMatch && programMatch && termMatch && venueModeMatch;
        });
    }

    handleClearFilters() {
        // Reset all filter values
        this.selectedCourse = '';
        this.selectedProgram = '';
        this.selectedTerm = '';
        this.selectedVenueMode = '';

        // Show all records
        this.filteredRecords = [...this.records];
    }
}