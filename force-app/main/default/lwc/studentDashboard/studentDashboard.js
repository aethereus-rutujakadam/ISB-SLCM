import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getStudentDashboardData from '@salesforce/apex/StudentDashboardController.getStudentDashboardData';
import getDetailedAttendanceData from '@salesforce/apex/StudentDashboardController.getDetailedAttendanceData';

export default class StudentDashboard extends NavigationMixin(LightningElement) {
    @track isLoading = true;
    @track error;
    @track dashboardData = {};
    
    // Attendance Modal
    @track showAttendanceModal = false;
    @track isLoadingAttendance = false;
    @track attendanceRecords = [];
    @track attendanceSummary = null;
    @track termGroups = [];
    
    contactId;

    get isPgpylStudent() {
        const currentProgram = this.dashboardData.profile?.currentProgram || '';
        return this.dashboardData.isPgpylStudent === true
            || currentProgram.toUpperCase().includes('PGPYL');
    }

    // Wire dashboard data
    @wire(getStudentDashboardData)
    wiredDashboardData({ error, data }) {
        this.isLoading = false;
        
        if (data) {
            console.log('=== Dashboard Data Received ===');
            console.log('Full Dashboard Data:', JSON.stringify(data, null, 2));
            console.log('Profile Data:', data.profile);
            console.log('Program Data:', data.program);
            console.log('Tasks Data:', data.tasks);
            console.log('Cases Data:', data.cases);
            console.log('Attendance Data:', data.attendance);
            
            this.dashboardData = data;
            this.contactId = data.profile?.recordId;
            this.error = undefined;
            
            console.log('Contact ID:', this.contactId);
        } else if (error) {
            console.error('=== Dashboard Data Error ===');
            console.error('Error Object:', error);
            console.error('Error Body:', error.body);
            this.error = this.extractErrorMessage(error);
            this.showToast('Error', this.error, 'error');
        }
    }

    // Computed properties for dashboard cards
    get studentName() {
        return this.dashboardData.profile?.name || 'Student';
    }

    get profileData() {
        const profile = this.dashboardData.profile || {};
        console.log('=== Profile Data Getter ===');
        console.log('Raw profile object:', profile);
        
        return {
            name: profile.name || '',
            studentId: profile.studentId || '',
            email: profile.email || '',
            phone: profile.phone || ''
        };
    }

    get programData() {
        const program = this.dashboardData.program || {};
        console.log('=== Program Data Getter ===');
        console.log('Raw program object:', program);
        
        return {
            name: program.name || 'N/A',
            cohort: program.cohort || 'N/A',
            status: program.status || 'Active',
            primaryAdvisor: program.primaryAdvisor || ''
        };
    }

    get attendanceData() {
        const attendance = this.dashboardData.attendance || {};
        console.log('=== Attendance Data Getter ===');
        console.log('Raw attendance object:', JSON.stringify(attendance, null, 2));
        console.log('Percentage:', attendance.percentage);
        console.log('Total Scheduled:', attendance.totalScheduled);
        console.log('Total Attended:', attendance.totalAttended);
        console.log('Last Updated:', attendance.lastUpdated);
        
        // Check if we have any attendance data at all
        if (!attendance || Object.keys(attendance).length === 0) {
            console.warn('⚠️ NO ATTENDANCE DATA RECEIVED FROM APEX!');
        } else if (attendance.totalScheduled === 0) {
            console.warn('⚠️ ATTENDANCE DATA RECEIVED BUT totalScheduled = 0');
        } else {
            console.log('✅ Attendance data looks good!');
        }
        
        return {
            percentage: attendance.percentage || 0,
            totalScheduled: attendance.totalScheduled || 0,
            totalAttended: attendance.totalAttended || 0,
            lastUpdated: attendance.lastUpdated || ''
        };
    }

    get attendancePercentageStyle() {
        return `--percentage: ${this.attendanceData.percentage || 0};`;
    }

    get tasksData() {
        const tasksObj = this.dashboardData.tasks;
        console.log('=== Tasks Data Getter ===');
        console.log('Raw tasks object:', tasksObj);
        console.log('Open count:', tasksObj?.openCount);
        
        return {
            openCount: this.dashboardData.tasks?.openCount || 0
        };
    }

    get casesData() {
        const cases = this.dashboardData.cases || {};
        console.log('=== Cases Data Getter ===');
        console.log('Raw cases object:', cases);
        console.log('Open count:', cases.openCount);
        console.log('Recent subject:', cases.recentSubject);
        
        return {
            openCount: cases.openCount || 0,
            recentSubject: cases.recentSubject || ''
        };
    }

    // Attendance Modal computed properties
    get hasAttendanceRecords() {
        return this.attendanceRecords && this.attendanceRecords.length > 0;
    }

    get groupedByTerm() {
        if (!this.attendanceRecords || this.attendanceRecords.length === 0) {
            return [];
        }

        // Group records by term
        const termMap = new Map();
        this.attendanceRecords.forEach(record => {
            const term = record.academicSession || 'No Session';
            if (!termMap.has(term)) {
                termMap.set(term, []);
            }
            termMap.get(term).push(record);
        });

        // Convert to array format for template
        const grouped = [];
        termMap.forEach((records, term) => {
            grouped.push({
                termName: term,
                courses: records,
                isExpanded: true // Default to expanded
            });
        });

        return grouped;
    }

    // Modal handlers
    async openAttendanceModal() {
        console.log('=== Opening Attendance Modal ===');
        console.log('Contact ID available:', this.contactId);
        this.showAttendanceModal = true;
        await this.loadAttendanceDetails();
    }

    closeAttendanceModal() {
        console.log('=== Closing Attendance Modal ===');
        this.showAttendanceModal = false;
    }

    async loadAttendanceDetails() {
        this.isLoadingAttendance = true;
        console.log('=== Loading Attendance Details ===');
        console.log('Contact ID:', this.contactId);

        try {
            const data = await getDetailedAttendanceData({
                contactId: this.contactId
            });

            console.log('=== Attendance Data Received ===');
            console.log('Full Attendance Data:', JSON.stringify(data, null, 2));
            console.log('Records Count:', data?.records?.length);
            console.log('Summary:', JSON.stringify(data?.summary, null, 2));
            console.log('Term Groups:', JSON.stringify(data?.termGroups, null, 2));

            // Log individual records for debugging
            if (data?.records && data.records.length > 0) {
                console.log('✅ Found ' + data.records.length + ' attendance records');
                data.records.forEach((record, index) => {
                    console.log(`Record ${index + 1}:`, {
                        courseName: record.courseName,
                        academicSession: record.academicSession,
                        scheduled: record.classesScheduled,
                        attended: record.classesAttended,
                        percentage: record.percentage
                    });
                });
            } else {
                console.warn('⚠️ NO ATTENDANCE RECORDS FOUND!');
            }

            if (data) {
                // Process records and apply new color rules
                const processedRecords = (data.records || []).map(record => {
                    const percentage = record.percentage || 0;
                    let statusClass;
                    
                    // New color rules: 100% = green, 99% = amber, <99% = red
                    if (percentage === 100) {
                        statusClass = 'status-excellent';
                    } else if (percentage === 99) {
                        statusClass = 'status-warning';
                    } else {
                        statusClass = 'status-critical';
                    }
                    
                    return {
                        ...record,
                        statusClass: statusClass,
                        dynamicStyle: `--percentage: ${percentage};`
                    };
                });
                
                this.attendanceRecords = processedRecords;
                this.attendanceSummary = data.summary;
                this.termGroups = data.termGroups || [];
                
                console.log('Attendance Records Set:', this.attendanceRecords.length);
                console.log('Grouped By Term:', this.groupedByTerm);
            }
        } catch (error) {
            console.error('=== Attendance Loading Error ===');
            console.error('Error:', error);
            console.error('Error Message:', this.extractErrorMessage(error));
            this.showToast('Error', this.extractErrorMessage(error), 'error');
        } finally {
            this.isLoadingAttendance = false;
            console.log('=== Attendance Loading Complete ===');
        }
    }

    // Navigation methods
    navigateToProfile() {
        const recordId = this.dashboardData.profile?.recordId;
        console.log('=== Navigate to Profile ===');
        console.log('Record ID:', recordId);
        if (recordId) {
            this.navigateToRecord(recordId, 'Contact');
        } else {
            console.warn('No profile record ID available');
        }
    }

    navigateToProgram() {
        console.log('=== Navigate to My 360 ===');
        // Redirect to My 360 tab in experience site
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: '/my-360'
            }
        });
    }

    navigateToTasks() {
        console.log('=== Navigate to Tasks ===');
        this.navigateToObjectList('Task');
    }

    navigateToCases() {
        console.log('=== Navigate to Cases ===');
        this.navigateToObjectList('Case');
    }

    navigateToAllAttendances() {
        console.log('=== Navigate to All Attendances ===');
        this.navigateToObjectList('Course_Attendance__c');
    }

    navigateToRecord(recordId, objectApiName) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                objectApiName: objectApiName,
                actionName: 'view'
            }
        });
    }

    navigateToObjectList(objectApiName) {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: objectApiName,
                actionName: 'list'
            }
        });
    }

    // Utility methods
    extractErrorMessage(error) {
        if (error.body) {
            if (error.body.message) return error.body.message;
            if (error.body.pageErrors && error.body.pageErrors.length > 0) {
                return error.body.pageErrors[0].message;
            }
        }
        return 'An unexpected error occurred';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant
            })
        );
    }
}