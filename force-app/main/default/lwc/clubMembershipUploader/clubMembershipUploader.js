import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import processClubRows from '@salesforce/apex/ClubMembershipExcelController.processExcelRows';
import createResultFile from '@salesforce/apex/ClubMembershipExcelController.createResultFile';
import SHEETJS from '@salesforce/resourceUrl/SheetJS';
import { loadScript } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class ClubMembershipUploader extends NavigationMixin(LightningElement) {
    fileData = [];
    fileName = '';
    sheetJsInitialized = false;
    isLoading = false;
    dynamicColumns = [];
    uploadResult = null;
    _lastResultRaw = null;

    get hasNoData() {
        return !this.fileData || this.fileData.length === 0;
    }
    get hasPreviewData() {
        return this.fileData && this.fileData.length > 0;
    }
    get isSubmitDisabled() {
        return this.hasNoData || this.isLoading;
    }
    get previewData() {
        if (this.hasNoData) return [];
        return this.fileData.map((row, index) => ({ id: `row-${index}`, ...row }));
    }

    renderedCallback() {
        if (this.sheetJsInitialized) return;
        this.sheetJsInitialized = true;
        loadScript(this, SHEETJS)
            .then(() => console.log('SheetJS loaded successfully'))
            .catch(error => {
                this.showToast('Error', 'SheetJS failed to load. Please refresh the page.', 'error');
                console.error('SheetJS loading error:', error);
            });
    }

    handleFileChange(event) {
        const file = event.target.files[0];
        if (!file) return;
        this.fileName = file.name;
        this.isLoading = true;
        const reader = new FileReader();
        reader.onload = (e) => {
            try {
                const data = new Uint8Array(e.target.result);
                const workbook = window.XLSX.read(data, { type: 'array' });
                const sheet = workbook.SheetNames[0];
                const worksheet = workbook.Sheets[sheet];
                const json = window.XLSX.utils.sheet_to_json(worksheet, { header: 1 });

                if (!json || json.length <= 1) {
                    this.showToast('Error', 'No data found in the Excel file.', 'error');
                    this.isLoading = false;
                    this.fileData = [];
                    this.dynamicColumns = [];
                    return;
                }

                const headers = json[0];
                const cleanedHeaders = headers.map(header => {
                    if (!header) return header;
                    return String(header)
                        .replace(/\n/g, ' ')
                        .replace(/\s+/g, ' ')
                        .trim();
                });

                this.dynamicColumns = this.generateDynamicColumns(cleanedHeaders);

                this.fileData = json.slice(1)
                    .filter(row => row && row.some(cell => cell !== null && cell !== undefined && cell !== ''))
                    .map((row, index) => {
                        const record = {};
                        cleanedHeaders.forEach((header, colIndex) => {
                            if (header && row[colIndex] !== undefined && row[colIndex] !== null && row[colIndex] !== '') {
                                const cleanFieldName = this.getCleanFieldName(header);
                                record[cleanFieldName] = row[colIndex];
                            }
                        });
                        return record;
                    })
                    .filter(record => Object.keys(record).length > 0 && (record.Student_Id || record.Student_Id === 0) && (record.Club || record.Club === 0));

                if (this.fileData.length === 0) {
                    this.showToast('Warning', 'No valid data found in the Excel file. Please ensure the file contains Student Id and Club columns.', 'warning');
                } else {
                    this.showToast('Success', `Loaded ${this.fileData.length} club membership records for preview`, 'success');
                }
            } catch (error) {
                this.showToast('Error', 'Error processing Excel file: ' + error.message, 'error');
                console.error('File processing error:', error);
                this.fileData = [];
                this.dynamicColumns = [];
            } finally {
                this.isLoading = false;
            }
        };
        reader.onerror = () => {
            this.showToast('Error', 'Error reading file', 'error');
            this.isLoading = false;
            this.fileData = [];
            this.dynamicColumns = [];
        };
        reader.readAsArrayBuffer(file);
    }

    generateDynamicColumns(headers) {
        const determineType = (h) => (typeof this.determineColumnType === 'function' ? this.determineColumnType(h) : 'text');
        const determineWidth = (h, f) => (typeof this.determineColumnWidth === 'function' ? this.determineColumnWidth(h, f) : 150);
        const getClass = (f) => (typeof this.getCellClass === 'function' ? this.getCellClass(f) : 'text-cell');

        return headers
            .filter(header => header && header.trim() !== '')
            .map(header => {
                const cleanFieldName = this.getCleanFieldName(header);
                const columnConfig = {
                    label: header,
                    fieldName: cleanFieldName,
                    type: determineType(header),
                    initialWidth: determineWidth(header, cleanFieldName),
                    wrapText: true,
                    cellAttributes: {
                        class: {
                            fieldName: getClass(cleanFieldName)
                        }
                    }
                };
                return columnConfig;
            });
    }

    getCleanFieldName(header) {
        if (!header) return header;
        const fieldMap = {
            'Student Id': 'Student_Id',
            'student id': 'Student_Id',
            'student_id': 'Student_Id',
            'studentid': 'Student_Id',
            'Id': 'Student_Id',
            'club': 'Club',
            'club name': 'Club',
            'club_name': 'Club',
            'role': 'Role',
            'Role': 'Role',
            'status': 'Status',
            'Status': 'Status',
            'leader': 'Leader',
            'Leader': 'Leader'
        };
        const lowerHeader = header.toLowerCase().trim();
        return fieldMap[lowerHeader] || header.replace(/\s+/g, '_');
    }

    validateDataBeforeSubmit() {
        if (!this.fileData || this.fileData.length === 0) {
            return { isValid: false, message: 'No data to submit' };
        }

        const invalidRecords = [];

        this.fileData.forEach((record, index) => {
            const errors = [];
            if (!record.Student_Id || record.Student_Id.trim() === '') {
                errors.push('Student Id is required');
            }
            if (!record.Club || record.Club.trim() === '') {
                errors.push('Student club is required');
            }
            if (errors.length > 0) {
                invalidRecords.push({
                    row: index + 2,
                    errors: errors
                });
            }
        });

        if (invalidRecords.length > 0) {
            const errorMessage = `Please fix the following errors:\n${invalidRecords.map(rec =>
                `Row ${rec.row}: ${rec.errors.join(', ')}`
            ).join('\n')}`;
            return { isValid: false, message: errorMessage };
        }

        return { isValid: true, message: '' };
    }

    handleSubmit() {
        if (this.hasNoData) {
            this.showToast('Error', 'Please upload a valid Excel file with Student club membership data.', 'error');
            return;
        }

        const validation = this.validateDataBeforeSubmit();
        if (!validation.isValid) {
            this.showToast('Error', validation.message, 'error');
            return;
        }

        this.isLoading = true;

        // call Apex - note we pass the same JSON shape your controller expects
        processClubRows({ jsonRows: JSON.stringify(this.fileData) })
            .then(result => {
                // result shape: createdCount, updatedCount, failedCount, errors, createdIds, updatedIds, resultCsvBase64, resultCsvFilename, resultCvId
                const created = result && result.createdCount ? result.createdCount : 0;
                const updated = result && result.updatedCount ? result.updatedCount : 0;
                const failed = result && result.failedCount ? result.failedCount : 0;
                const errors = result && result.errors ? result.errors : [];

                // show toast with created/updated/failed
                this.showToast('Success', `Completed: ${created} created, ${updated} updated, ${failed} failed.`, 'success');

                // store raw result and minimal uploadResult for template
                this._lastResultRaw = result;
                this.uploadResult = {
                    createdCount: created,
                    updatedCount: updated,
                    failedCount: failed,
                    resultCsvFilename: result && result.resultCsvFilename ? result.resultCsvFilename : undefined,
                    resultCvId: result && result.resultCvId ? result.resultCvId : undefined
                };

                // Add redirect logic to Club Membership list view on total success
                if (failed === 0 && errors.length === 0) {
                    this[NavigationMixin.Navigate]({
                        type: 'standard__objectPage',
                        attributes: {
                            objectApiName: 'Club_Membership__c',
                            actionName: 'list'
                        },
                        state: {
                            filterName: 'Recent'
                        }
                    });
                }
            })
            .catch(error => {
                const msg = error?.body?.message || error?.message || 'An error occurred while processing club memberships';
                this.showToast('Error', msg, 'error');
                console.error('Submission error:', error);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    resetForm() {
        this.fileData = [];
        this.fileName = '';
        this.dynamicColumns = [];
        const fileInput = this.template.querySelector('lightning-input[type="file"]');
        if (fileInput) fileInput.value = '';
        this.uploadResult = null;
        this._lastResultRaw = null;
    }

    downloadResults() {
        const raw = this._lastResultRaw;
        if (!raw || (!raw.resultCvId && !raw.resultCsvBase64)) {
            this.showToast('Error', 'No result CSV available to download.', 'error');
            return;
        }
        try {
            const cvId = raw.resultCvId;
            const base64 = raw.resultCsvBase64;
            const fname = raw.resultCsvFilename || 'ClubMembershipUploadResults.csv';

            if (cvId) {
                const url = '/sfc/servlet.shepherd/version/download/' + cvId;
                window.open(url, '_blank');
                return;
            }

            createResultFile({ base64Body: base64, filename: fname })
                .then(newCvId => {
                    if (newCvId) {
                        const url = '/sfc/servlet.shepherd/version/download/' + newCvId;
                        window.open(url, '_blank');
                    } else {
                        this.showToast('Error', 'Failed to create result file on server.', 'error');
                    }
                })
                .catch(err => {
                    console.error('createResultFile error', err);
                    const msg = err?.body?.message || (err && err.message) || JSON.stringify(err);
                    this.showToast('Error', 'Failed to save result file: ' + msg, 'error');
                });
        } catch (e) {
            console.error('Download error', e);
            this.showToast('Error', 'Failed to prepare download: ' + (e && e.message ? e.message : e), 'error');
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}