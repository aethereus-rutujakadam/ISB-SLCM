import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

import getExamSchedules from '@salesforce/apex/ExamSchedulerController.getExamSchedules';
import getLatestAANameByExamIds from '@salesforce/apex/ExamSchedulerController.getLatestAANameByExamIds';
import getAAAllocationCounts from '@salesforce/apex/ExamSchedulerController.getAAAllocationCounts';
import getAcademicAssociates from '@salesforce/apex/ExamSchedulerController.getAcademicAssociates';
import createExamAA from '@salesforce/apex/ExamSchedulerController.createExamAA';
import isCurrentUserProgramOffice from '@salesforce/apex/ExamSchedulerController.isCurrentUserProgramOffice';
import removeExamAA from '@salesforce/apex/ExamSchedulerController.removeExamAA';
import hasConflict from '@salesforce/apex/ExamSchedulerController.hasConflict';
import getAAIdsByExamIds from '@salesforce/apex/ExamSchedulerController.getAAIdsByExamIds';
import checkExactDuplicate from '@salesforce/apex/ExamSchedulerController.checkExactDuplicate';
import checkOverlap from '@salesforce/apex/ExamSchedulerController.checkOverlap';
import getAvailableAcademicAssociates from '@salesforce/apex/ExamSchedulerController.getAvailableAcademicAssociates'; // Added By Adesh on 26-dec-2025
import getVenues from '@salesforce/apex/ExamSchedulerController.getVenues'; // Added By Adesh on 31-dec-2025
import updateExamData from '@salesforce/apex/ExamSchedulerController.updateSelectedExams'; // Added By Adesh on 31-dec-2025
import updateSelectedExamsInReview from '@salesforce/apex/ExamSchedulerController.updateSelectedExamsInReview'; //Added By Adesh on 02-Jan-2026
import publishExams from '@salesforce/apex/ExamSchedulerController.publishExams'; // Added By Adesh on 02-Jan-2026

export default class ExamSchedulerDetails extends LightningElement {
    @api recordId;
    @track tableData = [];
    @track baseRows = [];
    @track selectedRowIds = [];
    @track showAssignModal = false;
    @track showUpdateModal = false; // Added By Adesh on 31-Dec-2025
    @track showConfirmModal = false; // confirmation modal when selected AA is not assigned to course
    @track selectedAAIds = [];
    @track aaOptions = [];
    @track showAssignAction = false;
    @track showFilter = false;
    @track originalAAIds = [];

    @track locationOptions = [{ label:'Select an Option', value:'' }];
    @track programOptions = [];
    @track termOptions = [];
    @track examVenueOptions = []; 
    // Added by Diksha – 19-01-2026
    @track newAAIds = [];
    @track removedAAIds = [];
    // ================== NEW ADDITION ==================
//     //@track modeOptions = [
//         { label: 'All', value: '' },
//        // { label: 'Offline', value: 'Offline' },
//        // { label: 'Online', value: 'Online' }
//    // ];

    @track filters = {
        location: '',
        program: '',
        term: '',
        examDate: '',
        examTime: '',
        endTime: '',
        examVenue: '', // ================== NEW ADDITION ==================
        search: '',
        // mode: ''
    };

    //Added By Adesh on 31-dec-2025
   /*  examDate;
    startTime;
    endTime; */
    venueId;
    venueOptions = [];
    showSubmitAAModal = false;
    showPublishConfirmModal = false;


    wiredResult;

    
    formatTimeForDisplay(sfTime) {
        if (!sfTime) return '';
        let ms = parseInt(sfTime, 10);
        if (isNaN(ms)) return '';
        let date = new Date(ms);
        let h = date.getUTCHours();
        let m = date.getUTCMinutes();
        let ampm = h >= 12 ? 'PM' : 'AM';
        h = h % 12 || 12;
        return `${h}:${m.toString().padStart(2, '0')} ${ampm}`;
    }
    
    
    




    toggleFilter = () => { this.showFilter = !this.showFilter; };

    handleFilterChange(event) {
        const field = event.currentTarget.dataset.field;
        const value = event.target.value;
        this.filters = { ...this.filters, [field]: value };
    }

    clearFilters() {
        this.filters = {
            location:'',
            program:'',
            term:'',
            examDate:'',
            examTime:'',
            endTime:'',
            search:'',
            examVenue:'', // ================== NEW ADDITION ==================
            // mode:''
        };
    }

    get filteredRows() {
        let rows = [...this.baseRows];

        if (this.filters.location) {
            rows = rows.filter(r => (r.Venue__r_Name || '').trim() === this.filters.location);
        }
        if (this.filters.examVenue) {  // ================== NEW ADDITION ==================
            rows = rows.filter(r => (r.Exam_Venue__r_Name || '') === this.filters.examVenue);
        }
        if (this.filters.program) {
            rows = rows.filter(r => (r.Program__r?.Name || '') === this.filters.program);
        }
        /*
        if (this.filters.term) {
            rows = rows.filter(r => (r.Academic_Term__r_Name || '') === this.filters.term);
        }
        */
        // if (this.filters.mode) {
        //     rows = rows.filter(r => (r.Mode__c || '') === this.filters.mode);
        // }
        if (this.filters.examDate) {
          rows = rows.filter(r => r.Date_of_Exam__c === this.filters.examDate);
        }

        if (this.filters.examTime) {
            rows = rows.filter(r => (r.Time_of_Exam__c || '').includes(this.filters.examTime));
        }
        if (this.filters.endTime) {
            rows = rows.filter(r => (r.End_Time__c || '').includes(this.filters.endTime));
        }
        // if (this.filters.search) {
        //     const searchValue = this.filters.search.toLowerCase();
        //     rows = rows.filter(r => r.Name.toLowerCase().includes(searchValue));
        // }

        return rows;
    }

    get headerTitle() {
        return this.filteredRows.length > 0
            ? (this.filteredRows[0].Academic_Term__r_Name || 'Examinations')
            : 'Examinations';
    }

    defaultColumns = [
        { label: 'Name', fieldName:'recordUrl', type:'url', typeAttributes:{ label:{ fieldName:'Name' }, target:'_blank' }},
        { label:'Academic Session', fieldName:'Academic_Session__r_Name' },
        { label:'Exam Type', fieldName:'Exam_Type__c' },
        { label:'Campus', fieldName:'Venue__r_Name' },
        { label:'Course Name', fieldName:'Course_Catalog__r_Name' },
        { label:'Status', fieldName:'Status' },   
        /*{ label:'Term', fieldName:'Academic_Term__r_Name' },*/
       //{ label:'Venue Name', fieldName:'Venue_Name__c' },
        { label:'Exam Venue', fieldName:'Exam_Venue__r_Name' },
        { label:'Date of Exam', fieldName:'Date_of_Exam__c', type:'date' },
        { label:'Time of Exam', fieldName:'Time_of_Exam__c', type:'text' },
        { label:'End Time', fieldName:'End_Time__c', type:'text' },
        { label:'Duration (mins)', fieldName:'Duration_mins__c', type:'number' },
        { label:'Allotted AAs', fieldName:'Allott_No_of_AAs__c', type:'number' }
        
    ];

    rowAssignColumn = {
        type:'button',
        initialWidth: 130,
        typeAttributes:{ label:{ fieldName:'rowButtonLabel' }, name:'assign-aa', variant:'brand-outline' }
    };

    columns = this.defaultColumns;

    @wire(isCurrentUserProgramOffice)
    wiredUserCheck({ data }) {
        this.showAssignAction = data === true;
        this.columns = this.showAssignAction
            ? [...this.defaultColumns, this.rowAssignColumn]
            : [...this.defaultColumns];
    }

    connectedCallback() { 
        this.loadAAOptions(); 


        // Load Venues for Edit Modal - Added By Adesh on 31-Dec-2025
        getVenues({recordId:this.recordId})
        .then(result => {
            this.venueOptions = result.map(v => ({
                label: v.label,
                value: v.value
            }));
        })
        .catch(error => {
            console.error('Error loading venues', error);
        });
    
    }

    async loadAAOptions() {
        const data = await getAcademicAssociates();
        this.aaOptions = data.map(c => ({ label:c.Name, value:c.Id }));
    }
    

    @wire(getExamSchedules, { examinationId:'$recordId' })
    wiredExams(result) {
        this.wiredResult = result;
        const { data, error } = result;
        if (!data || error) return;

        const base = data.map(row => ({
            ...row,
            recordUrl: '/' + row.Id,
            //Academic_Term__r_Name: row.Academic_Term__r?.Name || '',
            Course_Catalog__r_Name: row.Course_Catalog__r?.Name || '',
            Venue__r_Name: row.Venue__r?.Name || '',
             rawStartTime: row.Time_of_Exam__c,   // ADD THIS
             rawEndTime: row.End_Time__c, 
            Time_of_Exam__c: this.formatTimeForDisplay(row.Time_of_Exam__c),
            End_Time__c: this.formatTimeForDisplay(row.End_Time__c),
            Exam_Venue__r_Name: row.Exam_Venue__r?.Name || '',
            Academic_Session__r_Name: row.Academic_Session__r?.Name || ''
        }));

        const ids = base.map(x => x.Id);

        Promise.all([
            getLatestAANameByExamIds({ examIds: ids }),
            getAAAllocationCounts({ examIds: ids })
        ])
        .then(([nameMap, countMap]) => {
            this.baseRows = base.map(r => {
                const currentAAName = nameMap[r.Id] || '';
                return {
                    ...r,
                    currentAAName,
                    rowButtonLabel: currentAAName ? 'Update AA' : 'Assign AA',
                    Allott_No_of_AAs__c: countMap[r.Id] || 0
                };
            });

            this.tableData = this.baseRows;

            // ================== NEW ADDITION (Populate filter options) ==================
            this.programOptions = [
                { label:'Select an Option', value:'' },
                ...[...new Set(this.baseRows.map(r => r.Program__r?.Name).filter(v => v))]
                    .map(v => ({ label:v, value:v }))
            ];

            /*
            this.termOptions = [
                { label:'Select an Option', value:'' },
                ...[...new Set(this.baseRows.map(r => r.Academic_Term__r_Name).filter(v => v))]
                    .map(v => ({ label:v, value:v }))
            ];
            */

            this.locationOptions = [
                { label:'Select an Option', value:'' },
                ...[...new Set(this.baseRows.map(r => r.Venue__r_Name).filter(v => v))]
                    .map(v => ({ label:v, value:v }))
            ];

            this.examVenueOptions = [
                { label:'Select an Option', value:'' },
                ...[...new Set(this.baseRows.map(r => r.Exam_Venue__r_Name).filter(v => v))]
                    .map(v => ({ label:v, value:v }))
            ];
            // ================== END NEW ADDITION ==================
        });
    }

    handleRowSelection(event) {
        this.selectedRowIds = event.detail.selectedRows.map(r => r.Id);
    }

    handleRowAction(event) {
        if (event.detail.action.name === 'assign-aa') {
            this.selectedRowIds = [event.detail.row.Id];
            if(!this.checkStatus('In Review')){
                this.showToast('Warning', 'AA Assignment is only allowed for examinations with status "In Review".', 'warning');
                return;
            }
            this.preselectExistingAAs();
            this.showAssignModal = true;
        }
    }

    openAssignModal() {
        if (!this.selectedRowIds.length) {
            this.showToast('Warning', 'Please select at least one record.', 'warning');
            return;
        }
        //Added By Adesh on 16 Jan 2026
        if(!this.checkStatus('In Review')){
            this.showToast('Warning', 'AA Assignment is only allowed for examinations with status "In Review".', 'warning');
            return;
        }
        //End Added By Adesh on 16 Jan 2026

        this.preselectExistingAAs();
        this.showAssignModal = true;
    }

    //Added By Adesh on 16 Jan 2026
    checkStatus(statusToCheck) {
        for (let examId of this.selectedRowIds) {
            const exam = this.baseRows.find(r => r.Id === examId);
            if(exam.Status !== statusToCheck){
                return false;
            }
        }
        return true;
    }

    //Added By Adesh on 31-Dec-2025
    openUpdateModal() {
        if (!this.selectedRowIds.length) {
            this.showToast('Warning', 'Please select at least one record.', 'warning');
            return;
        }
        this.examDate = null;
        this.startTime = null;
        this.endTime = null;
        this.venueId = null;
        this.showUpdateModal = true;
    }

    closeUpdateModal() { 
        this.showUpdateModal = false;
    }
    // End Added By Adesh on 31-Dec-2025

    closeAssignModal() {
        this.showAssignModal = false;
    }

    handleAAChange(event) {
        this.selectedAAIds = event.detail.value;
    }

    async preselectExistingAAs() {
        if (!this.selectedRowIds.length) return;
        const result = await getAAIdsByExamIds({ examIds: this.selectedRowIds });
        const existingIds = result[this.selectedRowIds[0]] || [];
        this.selectedAAIds = existingIds;
        this.originalAAIds = [...existingIds]; 
    }

    async checkConflicts() {
        const warnings = [];
        for (let aaId of this.selectedAAIds) {
            for (let examId of this.selectedRowIds) {
                const exam = this.baseRows.find(r => r.Id === examId);
                const conflict = await hasConflict({
                    contactId: aaId,
                    examDate: exam.Date_of_Exam__c,
                    examTime: exam.Time_of_Exam__c
                });
                if (conflict) {
                    warnings.push(`${exam.Name} (${exam.Date_of_Exam__c})`);
                }
            }
        }

        if (warnings.length > 0) {
            this.showToast('Conflict Warning', warnings.join('\n'), 'warning');
        }
    }

    async assignSelected() {

    const exam = this.baseRows.find(r => r.Id === this.selectedRowIds[0]);
    // Added by Diksha – 19-01-2026
    this.newAAIds = this.selectedAAIds.filter(
            id => !this.originalAAIds.includes(id)
        );

        this.removedAAIds = this.originalAAIds.filter(
            id => !this.selectedAAIds.includes(id)
        );

        if (this.removedAAIds.length > 0) {
            await removeExamAA({
                examIds: this.selectedRowIds,
                contactIds: this.removedAAIds
            });
        }
       // ========= EXACT DUPLICATE CHECK (SINGLE + BULK) =========
for (let examId of this.selectedRowIds) {
    const exam = this.baseRows.find(r => r.Id === examId);
    if (!exam) continue;

    for (let aaId of this.selectedAAIds) {
        const isDuplicate = await checkExactDuplicate({
            contactId: aaId,
            examDate: exam.Date_of_Exam__c,
            startTime: exam.rawStartTime,
            endTime: exam.rawEndTime,
            examId: examId
        });

        if (isDuplicate) {
            this.showToast(
                'Duplicate Assignment',
                'Same Academic Associate cannot be assigned to multiple exams having identical date and time.',
                'error'
            );
            return;
        }
    }
}
  // ================= BULK SAME-SELECTION DUPLICATE CHECK =================
// Added by Diksha – 19-01-2026
const bulkTimeKeySet = new Set();

for (let examId of this.selectedRowIds) {
    const examRec = this.baseRows.find(r => r.Id === examId);
    if (!examRec) continue;

    const key =
        examRec.Date_of_Exam__c + '_' +
        examRec.rawStartTime + '_' +
        examRec.rawEndTime;

    if (bulkTimeKeySet.has(key)) {
        this.showToast(
            'Duplicate Assignment',
            'Same Academic Associate cannot be assigned to multiple exams having identical date and time.',
            'error'
        );
        return;
    }
    bulkTimeKeySet.add(key);
}
        // ========= OVERLAP WARNING (SINGLE + BULK) =========
let hasOverlapWarning = false;
if (this.selectedRowIds.length > 0 && this.selectedAAIds.length > 0) {
    for (let examId of this.selectedRowIds) {
        const exam = this.baseRows.find(r => r.Id === examId);
        if (!exam) continue;

        for (let aaId of this.selectedAAIds) {
            const conflict = await checkOverlap({
                contactId: aaId,
                examDate: exam.Date_of_Exam__c,
                startTime: exam.rawStartTime,
                endTime: exam.rawEndTime
            });

            if (conflict) {
                hasOverlapWarning = true;
                break;
            }
        }
        if (hasOverlapWarning) break;
    }
}

if (hasOverlapWarning) {
    this.showToast(
        'Conflict Warning',
        'AA has overlapping exam duty. Assignment allowed.',
        'warning'
    );
}
// ========== CLIENT-SIDE BULK OVERLAP CHECK ==========
let bulkOverlapDetected = false;

if (this.selectedRowIds.length > 1 && this.selectedAAIds.length > 0) {

    const exams = this.selectedRowIds
        .map(id => this.baseRows.find(r => r.Id === id))
        .filter(Boolean);

    for (let i = 0; i < exams.length; i++) {
        for (let j = i + 1; j < exams.length; j++) {

            const e1 = exams[i];
            const e2 = exams[j];

            // same date?
            if (e1.Date_of_Exam__c !== e2.Date_of_Exam__c) continue;

            const start1 = e1.rawStartTime;
            const end1   = e1.rawEndTime;
            const start2 = e2.rawStartTime;
            const end2   = e2.rawEndTime;

            // time overlap condition
            if (start1 < end2 && start2 < end1) {
                bulkOverlapDetected = true;
                break;
            }
        }
        if (bulkOverlapDetected) break;
    }
}

if (bulkOverlapDetected) {
    this.showToast(
        'Conflict Warning',
        'AA has overlapping exam duty. Assignment allowed.',
        'warning'
    );
}
        const aaAvailable = await this.checkAvailableAA(
            this.selectedRowIds,
            this.newAAIds
        );

        if (!aaAvailable) {
            this.showConfirmModal = true;
            return;
        }

        if (!this.newAAIds.length) {
            this.showToast('Success', 'Academic Associates updated successfully', 'success');
            await this.handleRefresh();
            this.showAssignModal = false;
            return;
        }

        await this.executeCreateExamAA();
    }
   // Added by Diksha – 19-01-2026
    async executeCreateExamAA() {
        await createExamAA({
            contactIds: this.newAAIds,
            examIds: this.selectedRowIds,
            assignedOn: null
        });

        this.showToast('Success', 'Academic Associates updated successfully', 'success');
        await this.handleRefresh();
        this.showAssignModal = false;
    }
    
    async removeSelected() {
    
    const removedIds = this.originalAAIds.filter(x => !this.selectedAAIds.includes(x));

    if (!removedIds.length) {
        this.showToast('Warning', 'Select AA to remove', 'warning');
        return;
    }

    await removeExamAA({
        examIds: this.selectedRowIds,
        contactIds: removedIds
    });

    this.showToast('Success', 'Academic Associate removed', 'success');

    await this.handleRefresh();
    this.closeAssignModal();
}


    async handleRefresh() {
    await refreshApex(this.wiredResult);

    const ids = this.baseRows.map(x => x.Id);

    // Fetch new AA Names & Count
    const [nameMap, countMap] = await Promise.all([
        getLatestAANameByExamIds({ examIds: ids }),
        getAAAllocationCounts({ examIds: ids })
    ]);

    this.baseRows = this.baseRows.map(r => {
        const currentAAName = nameMap[r.Id] || '';
        return {
            ...r,
            currentAAName,
            rowButtonLabel: currentAAName ? 'Update AA' : 'Assign AA',   // FIX NEW LOGIC
            Allott_No_of_AAs__c: countMap[r.Id] || 0
        };
    });

    this.tableData = [...this.baseRows];   // force re-render
}


    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    get countLabel() {
        return `${this.filteredRows.length} record(s)`;
    }
    // // helper to execute create & follow-up UI
    // async executeCreateExamAA() {
    //     await createExamAA({
    //         contactIds: this.selectedAAIds,
    //         examIds: this.selectedRowIds,
    //         assignedOn: null
    //     });

    //     this.showToast('Success', 'Academic Associates assigned successfully', 'success');
    //     await this.handleRefresh();
    //     this.showAssignModal = false;
    // }

    // Confirmation handlers for when selected AA(s) are not related to course(s)
    async confirmYes() {
        this.showConfirmModal = false;
        await this.executeCreateExamAA();
    }

    confirmNo() {
        this.showConfirmModal = false;
    }

    // Added By Adesh on 26-dec-2025
    async checkAvailableAA(examIds , selectedAAIds) {
        try {
            console.log('examIds:' , examIds);
            console.log('selectedAAIds:' , selectedAAIds);

            this.isLoading = true;
            const data = await getAvailableAcademicAssociates({ examIds , selectedAAIds });
            console.log('data:',data);

            // data === false indicates none of the selected AAs are related to the course(s)
            if (data === false) {
                //this.showToast('Error', 'No Academic Associates found related to the course of the selected exam(s).', 'error');
                return false;
            }
            return true;
        } catch (error) {
            this.showToast('Error', 'Error fetching Academic Associates: ' + (error.body ? error.body.message : error.message), 'error');
            return false;
        } finally {
            this.isLoading = false;
        }
    }
    // End Added By Adesh on 26-dec-2025

    //Added By Adesh on 31-Dec-2025
    handleChange(event) {
        const field = event.target.dataset.field;
    const value = event.detail ? event.detail.value : event.target.value;
    this[field] = value;
    }

    handleVenueChange(event) {
        this.venueId = event.target.value;
    }

    validate() {

        console.log('Validating:', this.examDate, this.startTime, this.endTime, this.venueId);

        /*
        if(!this.examDate || !this.startTime || !this.endTime || !this.venueId){
            this.showToast('Error','All fields are required.','error');
            return false;
        }
        */

        if(this.startTime && this.endTime){
            if(this.endTime <= this.startTime){
                this.showToast('Error','End Time must be after Start Time.','error');
                return false;
            }
        }

        return true;
    }


    updateExaminationData() {

        if(!this.validate()) return;

        updateExamData({ examIds: this.selectedRowIds,
                                        examDate: this.examDate,
                                        startTime: this.startTime ? this.startTime.split('.')[0] : null,
                                        endTime:  this.endTime ? this.endTime.split('.')[0] : null,
                                        venueId: this.venueId })
            .then(() => {
                this.showToast('Success','Examination updated successfully','success');
                this.handleRefresh();
                this.closeUpdateModal();
            })
            .catch(error => {
                this.showToast('Error', error.body.message, 'error');
            });
    }
    /*

    showToast(title, message, variant){
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
    */

    //End Added By Adesh on 31-Dec-2025

    //Submit For AA Assignment Modal - Added By Adesh on 31-Dec-2025
    openSubmitAAModal() {
        if (!this.selectedRowIds.length) {
            this.showToast('Warning', 'Please select at least one record.', 'warning');
            return;
        }
        this.showSubmitAAModal = true;
    }

    submitAAConfirmNo() {
        this.showSubmitAAModal = false;
    }

    submitAAConfirmYes() {
        updateSelectedExamsInReview({ examIds: this.selectedRowIds , recordId: this.recordId })
            .then(() => {
                this.showToast('Success','Selected Examinations submitted for AA Assignment successfully','success');
                this.handleRefresh();
            })
            .catch(error => {
                this.showToast('Error', error.body.message, 'error');
            });
        this.showSubmitAAModal = false;
    }
    // End Submit For AA Assignment Modal - Added By Adesh on 31-Dec-2025

    //Publish Confirmation Modal - Added By Adesh on 02-Jan-2026
    openPublishConfirmationModal() {
        if (!this.selectedRowIds.length) {
            this.showToast('Warning', 'Please select at least one record.', 'warning');
            return;
        }
        this.showPublishConfirmModal = true;
    }

    publishConfirmNo() {
        this.showPublishConfirmModal = false;
    }

    publishConfirmYes() {
        // Call Apex method to publish exams
        // Assuming there's an Apex method named 'publishExams'
        publishExams({ examIds: this.selectedRowIds })
            .then(() => {
                this.showToast('Success','Selected Examinations published successfully','success');
                this.handleRefresh();
            })
            .catch(error => {
                this.showToast('Error', error.body.message, 'error');
            });
        this.showPublishConfirmModal = false;
    }
    // End Publish Confirmation Modal - Added By Adesh on 02-Jan-2026
}