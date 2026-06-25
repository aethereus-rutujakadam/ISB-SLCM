import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import SHEETJS from '@salesforce/resourceUrl/SheetJS';
import uploadChecklistRows from '@salesforce/apex/ChecklistItemUploadController.uploadChecklistRows';

export default class ChecklistItemExcelUploader extends LightningElement {
    fileName;
    fileData = [];
    columns = [];
    sheetLoaded = false;
    isLoading = false;

    get recordsCount() {
        return this.fileData.length;
    }

    get isUploadDisabled() {
        return this.isLoading || this.fileData.length === 0;
    }

    renderedCallback() {
        if (this.sheetLoaded) return;
        loadScript(this, SHEETJS).then(() => { this.sheetLoaded = true; });
    }

    normalizeDateCell(columnName, value) {
        if (value === null || value === undefined || value === '') {
            return value;
        }

        const isDateColumn = /date/i.test(columnName);
        if (!isDateColumn) {
            return value;
        }

        // Excel serial date (e.g., 46035) => yyyy-mm-dd
        const numeric = Number(value);
        if (!Number.isNaN(numeric) && Number.isFinite(numeric) && numeric > 20000) {
            const utcMillis = Math.round((numeric - 25569) * 86400 * 1000);
            const dt = new Date(utcMillis);
            const y = dt.getUTCFullYear();
            const m = String(dt.getUTCMonth() + 1).padStart(2, '0');
            const d = String(dt.getUTCDate()).padStart(2, '0');
            return `${y}-${m}-${d}`;
        }

        return value;
    }

    handleFileChange(event) {
        const file = event.target.files[0];
        if (!file) return;

        this.fileName = file.name;
        const reader = new FileReader();

        reader.onload = e => {
            const data = new Uint8Array(e.target.result);
            const workbook = window.XLSX.read(data, { type: 'array' });
            const sheet = workbook.Sheets[workbook.SheetNames[0]];
            const json = window.XLSX.utils.sheet_to_json(sheet, {
                raw: false,
                dateNF: 'yyyy-mm-dd',
                defval: ''
            });

            this.fileData = json.map((r, i) => {
                const normalized = {};
                Object.keys(r).forEach(key => {
                    normalized[key] = this.normalizeDateCell(key, r[key]);
                });
                return { id: i, ...normalized };
            });

            if (this.fileData.length > 0) {
                this.columns = Object.keys(this.fileData[0])
                    .filter(key => key !== 'id')
                    .map(col => ({ label: col, fieldName: col, type: 'text', wrapText: true }));
            }
        };

        reader.readAsArrayBuffer(file);
    }

    handleUploadClick() {
        if (this.fileData.length === 0) {
            this.showToast('error', 'Validation Error', 'Please select an Excel file with data');
            return;
        }
        this.isLoading = true;

        const rowsJson = JSON.stringify(this.fileData.map(({ id, ...rest }) => rest));

        uploadChecklistRows({ rowsJson })
        .then(result => {
            const hasErrors = result.errors && result.errors.length > 0;
            if (hasErrors) {
                this.showToast('error', 'Error', result.errors[0]);
            } else if (result.totalItemsCreated > 0) {
                const warnMsg = result.warnings && result.warnings.length > 0
                    ? ` (${result.warnings.length} row(s) skipped)` : '';
                this.showToast('success', 'Success',
                    `Successfully created ${result.totalItemsCreated} checklist template(s)${warnMsg}`);
                this.resetForm();
            } else {
                // 0 items — show all warnings so user sees column diagnostic
                const msgs = result.warnings && result.warnings.length > 0
                    ? result.warnings.join(' | ')
                    : 'No items were created. Check your Excel column names (Subject, Role, Priority, Description, CourseType).';
                this.showToast('warning', 'No Records Created', msgs);
            }
        })
        .catch(error => {
            this.showToast('error', 'Error', error.body?.message || 'Unknown error occurred');
        })
        .finally(() => {
            this.isLoading = false;
        });
    }

    resetForm() {
        this.fileName = null;
        this.fileData = [];
        this.columns = [];
        const input = this.template.querySelector('lightning-input');
        if (input) input.value = null;
    }

    showToast(variant, title, message) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}