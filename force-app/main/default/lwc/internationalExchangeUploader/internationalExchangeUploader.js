import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import processExchangeData from '@salesforce/apex/InternationalExchangeController.processExchangeData';
import processIncomingExchangeUpload from '@salesforce/apex/InternationalExchangeController.processIncomingExchangeUpload';
import getIncomingPrograms from '@salesforce/apex/InternationalExchangeController.getIncomingPrograms';
import getIncomingCohorts from '@salesforce/apex/InternationalExchangeController.getIncomingCohorts';
// F-07 FIX: Import renamed Apex method (was getIncomingTerms — it returns AcademicSessions)
import getIncomingSessionsByCohort from '@salesforce/apex/InternationalExchangeController.getIncomingSessionsByCohort';
import SHEETJS from '@salesforce/resourceUrl/SheetJS';
import { loadScript } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class InternationalExchangeUploader extends NavigationMixin(LightningElement) {

    uploadMode = 'Incoming';
    modeOptions = [
        { label: 'Incoming Exchange Upload', value: 'Incoming' }
    ];

    selectedProgram = '';
    selectedCohort  = '';
    selectedTerm    = [];

    programOptions = [];
    cohortOptions  = [];
    termOptions    = [];

    fileData    = [];
    sheetLoaded = false;
    isLoading   = false;

    errorCSV  = '';
    hasErrors = false;

    generalColumns = [
        { label: 'Student Id',        fieldName: 'pgid',            type: 'text' },
        { label: 'Full Name',          fieldName: 'fullName',        type: 'text' },
        { label: 'Exchange Type',      fieldName: 'exchangeType',    type: 'text' },
        { label: 'Home University',    fieldName: 'homeUniversity',  type: 'text' },
        { label: 'Visiting Term',      fieldName: 'visitingTerm',    type: 'text' },
        { label: 'Program Name',       fieldName: 'programName',     type: 'text' },
        { label: 'Academic Term',      fieldName: 'academicTerm',    type: 'text' },
        { label: 'Academic Session',   fieldName: 'academicSession', type: 'text' }
    ];

    incomingColumns = [
        { label: 'First Name',              fieldName: 'firstName',          type: 'text' },
        { label: 'Last Name',               fieldName: 'lastName',           type: 'text' },
        { label: 'Email',                   fieldName: 'email',              type: 'text' },
        { label: 'Campus',                  fieldName: 'campus',             type: 'text' },
        { label: 'Gender',                  fieldName: 'gender',             type: 'text' },
        { label: 'Home Inst Contact Name',  fieldName: 'homeInstContactName', type: 'text' },
        { label: 'Home Inst Contact Email', fieldName: 'homeInstContactEmail', type: 'text' },
        { label: 'Check-in Date',           fieldName: 'checkInDate',        type: 'text' },
        { label: 'Check-out Date',          fieldName: 'checkOutDate',       type: 'text' },
        { label: 'Accommodation Type',      fieldName: 'accommodationType',  type: 'text' },
        { label: 'School Code',             fieldName: 'schoolCode',         type: 'text' }
    ];

    get isIncomingMode() { return this.uploadMode === 'Incoming'; }
    get currentColumns() { return this.isIncomingMode ? this.incomingColumns : this.generalColumns; }
    get isCohortDisabled() { return !this.selectedProgram; }
    get isTermDisabled()   { return !this.selectedCohort; }

    get isFileUploadDisabled() {
        if (this.isLoading) return true;
        if (this.isIncomingMode) {
            return !this.selectedTerm || this.selectedTerm.length === 0;
        }
        return false;
    }

    get isSubmitDisabled() {
        return this.isLoading || this.fileData.length === 0;
    }

    @wire(getIncomingPrograms)
    wiredPrograms({ error, data }) {
        if (data) {
            this.programOptions = data.map(p => ({ label: p.Name, value: p.Id }));
        } else if (error) {
            console.error('Error fetching Programs:', JSON.stringify(error));
            this.showToast('Error Loading Programs', error.body?.message || error.message, 'error');
        }
    }

    renderedCallback() {
        if (this.sheetLoaded) return;
        this.sheetLoaded = true;

        // F-13 FIX: Removed insecure CDN fallback — static resource must be deployed correctly
        loadScript(this, SHEETJS).catch(() => {
            this.showToast(
                'Library Error',
                'SheetJS library failed to load. Please contact your administrator.',
                'error'
            );
        });
    }

    handleModeChange(event) {
        this.uploadMode = event.detail.value;
        this.resetForm();
    }

    handleProgramChange(event) {
        this.selectedProgram = event.detail.value;
        this.selectedCohort  = '';
        this.selectedTerm    = [];
        this.cohortOptions   = [];
        this.termOptions     = [];

        getIncomingCohorts({ programId: this.selectedProgram })
            .then(result => {
                this.cohortOptions = result.map(c => ({ label: c.Name, value: c.Id }));
            })
            .catch(error => this.showToast('Error', error.body?.message || error.message, 'error'));
    }

    handleCohortChange(event) {
        this.selectedCohort = event.detail.value;
        this.selectedTerm   = [];
        this.termOptions    = [];

        // Fix: Use session Name as value and ensure uniqueness
        getIncomingSessionsByCohort({ cohortId: this.selectedCohort })
            .then(result => {
                const uniqueNames = [...new Set(result.map(t => t.Name))];
                this.termOptions = uniqueNames.map(name => ({ label: name, value: name }));
            })
            .catch(error => this.showToast('Error', error.body?.message || error.message, 'error'));
    }

    handleTermChange(event) {
        this.selectedTerm = event.detail.value;
    }

    // F-14 FIX: Replaced deprecated unescape() with safe UTF-8 base64 encoding
    downloadCSV(csvContent, fileName) {
        const encoded = btoa(
            encodeURIComponent(csvContent).replace(
                /%([0-9A-F]{2})/g,
                (_, hex) => String.fromCharCode(parseInt(hex, 16))
            )
        );
        const dataUrl = 'data:text/csv;base64,' + encoded;
        const link = document.createElement('a');
        link.href = dataUrl;
        link.download = fileName;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
    }

    handleFileChange(event) {
        const file = event.target.files[0];
        if (!file) return;

        this.isLoading = true;
        this.hasErrors = false;
        this.errorCSV  = '';

        let blankErrors = [];

        const reader = new FileReader();
        reader.onload = e => {
            try {
                const workbook = window.XLSX.read(new Uint8Array(e.target.result), { type: 'array' });
                const sheet    = workbook.Sheets[workbook.SheetNames[0]];
                // F-16 FIX: raw:false + dateNF forces SheetJS to format date cells as strings
                const json  = window.XLSX.utils.sheet_to_json(sheet, {
                    header:  1,
                    raw:     false,
                    dateNF:  'yyyy-mm-dd'
                });

                const rows = json.slice(1);
                let mapped = [];

                if (this.isIncomingMode) {
                    mapped = rows.map((r, i) => ({
                        id:                   'row_' + i,
                        firstName:            r[0]  ? String(r[0]).trim()  : '',
                        lastName:             r[1]  ? String(r[1]).trim()  : '',
                        email:                r[2]  ? String(r[2]).trim()  : '',
                        campus:               r[3]  ? String(r[3]).trim()  : '',
                        gender:               r[4]  ? String(r[4]).trim()  : '',
                        homeInstContactName:  r[5]  ? String(r[5]).trim()  : '',
                        homeInstContactEmail: r[6]  ? String(r[6]).trim()  : '',
                        checkInDate:          r[7]  ? String(r[7]).trim()  : '',
                        checkOutDate:         r[8]  ? String(r[8]).trim()  : '',
                        accommodationType:    r[9]  ? String(r[9]).trim()  : '',
                        schoolCode:           r[10] ? String(r[10]).trim() : ''
                    }));

                    // F-15 FIX: Warn user about dropped rows (was silent before)
                    const dropped = mapped.filter(r => !r.lastName || !r.email);
                    if (dropped.length > 0) {
                        this.showToast(
                            'Warning',
                            dropped.length + ' row(s) skipped — missing Last Name or Email.',
                            'warning'
                        );
                    }
                    this.fileData = mapped.filter(r => r.lastName && r.email);

                } else {
                    mapped = rows.map((r, i) => {
                        const pgid = r[0] ? String(r[0]).trim() : '';
                        if (!pgid) {
                            blankErrors.push({
                                StudentId:    '',
                                FullName:     r[1] || '',
                                ProgramName:  r[5] || '',
                                errorMessage: 'Student Id is blank'
                            });
                        }
                        return {
                            id:              'row_' + i,
                            pgid,
                            fullName:        r[1] ? String(r[1]).trim() : '',
                            exchangeType:    r[2] ? String(r[2]).trim() : '',
                            homeUniversity:  r[3] ? String(r[3]).trim() : '',
                            visitingTerm:    r[4] ? String(r[4]).trim() : '',
                            programName:     r[5] ? String(r[5]).trim() : '',
                            academicTerm:    r[6] ? String(r[6]).trim() : '',
                            academicSession: r[7] ? String(r[7]).trim() : ''
                        };
                    });

                    if (blankErrors.length > 0) {
                        const csv = 'StudentId,FullName,ProgramName,ErrorMessage\n' +
                            blankErrors.map(err =>
                                `"${err.StudentId}","${err.FullName}","${err.ProgramName}","${err.errorMessage}"`
                            ).join('\n');

                        this.errorCSV  = csv;
                        this.hasErrors = true;
                        this.showToast('Error', "Student Id cannot be blank. Click 'Download Error Log' to see details.", 'error');
                        this.fileData  = [];
                        this.isLoading = false;
                        return;
                    }

                    this.fileData = mapped.filter(r => r.pgid && r.fullName && r.programName);
                }

                this.showToast('Success', `${this.fileData.length} rows loaded`, 'success');
                this.isLoading = false;

            } catch (error) {
                this.isLoading = false;
                this.showToast('Error', error.message, 'error');
            }
        };

        reader.readAsArrayBuffer(file);
    }

    handleSubmit() {
        this.isLoading = true;
        this.hasErrors = false;
        this.errorCSV  = '';

        if (this.isIncomingMode) {
            // F-18/F-19 FIX: selectedTerm now holds session IDs (not names)
            processIncomingExchangeUpload({
                records:  this.fileData,
                progId:   this.selectedProgram,
                cohortId: this.selectedCohort,
                termId:   this.selectedTerm.join(',')
            })
            .then(result => this.handleApexResult(result))
            .catch(error => this.handleApexError(error));
        } else {
            processExchangeData({ records: this.fileData })
            .then(result => this.handleApexResult(result))
            .catch(error => this.handleApexError(error));
        }
    }

    handleApexResult(result) {
        const firstErr = result.errorRows?.length ? result.errorRows[0].errorMessage : '';

        this.showToast(
            'Completed',
            `${result.successCount} inserted | ${result.failedCount} failed${firstErr ? ' — ' + firstErr : ''}`,
            result.failedCount > 0 ? 'warning' : 'success'
        );

        if (result.failedCount > 0 && result.errorCSV) {
            this.errorCSV  = result.errorCSV;
            this.hasErrors = true;
        }

        // F-17 FIX: Only navigate away on full success — partial success stays on page for error download
        if (result.successCount > 0 && result.failedCount === 0) {
            setTimeout(() => {
                this[NavigationMixin.Navigate]({
                    type: 'standard__objectPage',
                    attributes: { objectApiName: 'Contact', actionName: 'list' },
                    state: { filterName: 'Recent' }
                });
            }, 700);
        }
        this.isLoading = false;
    }

    handleApexError(error) {
        this.showToast('Error', error.body?.message || error.message, 'error');
        this.isLoading = false;
    }

    handleDownloadErrors() {
        if (!this.errorCSV) {
            this.showToast('Error', 'No errors available to download.', 'error');
            return;
        }
        this.downloadCSV(this.errorCSV, 'ExchangeUploadErrors.csv');
    }

    resetForm() {
        this.fileData  = [];
        this.errorCSV  = '';
        this.hasErrors = false;

        if (!this.isIncomingMode) {
            this.selectedProgram = '';
            this.selectedCohort  = '';
            this.selectedTerm    = [];
        }

        const input = this.template.querySelector('lightning-input[type="file"]');
        if (input) input.value = '';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant, mode: 'dismissable' }));
    }
}