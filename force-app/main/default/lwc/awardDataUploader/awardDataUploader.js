import { LightningElement } from 'lwc';
import processAwardData from '@salesforce/apex/AwardUploadController.processAwardData';
import SHEETJS from '@salesforce/resourceUrl/SheetJS';
import { loadScript } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
export default class AwardDataUploader extends LightningElement {
    fileData = [];
    fileName = '';
    sheetLoaded = false;
    isLoading = false;
    dynamicColumns = [];
    errorCSV = null;
    get isSubmitDisabled() {
        return this.isLoading || this.fileData.length === 0;
    }
    renderedCallback() {
        if (this.sheetLoaded) return;
        this.sheetLoaded = true;
        loadScript(this, SHEETJS);
    }
    handleFileChange(event) {
    const file = event.target.files[0];
    if (!file) return;

    this.fileName = file.name;
    this.isLoading = true;

    const reader = new FileReader();

    reader.onload = (e) => {
        try {
            // Parse workbook
            const workbook = window.XLSX.read(
                new Uint8Array(e.target.result),
                { type: "array" }
            );
            const sheet = workbook.Sheets[workbook.SheetNames[0]];
            const json = window.XLSX.utils.sheet_to_json(sheet, { header: 1 });

            // ---------------------------
            // IMPORTANT FIX → Define headers
            // ---------------------------
            const headers = json[0] || [];

            // ---------------------------
            // Validate correct file upload
            // ---------------------------
            if (
                !headers[0] ||
                !headers[1] ||
                headers[0].toString().toLowerCase() !== "student id" ||
                headers[1].toString().toLowerCase() !== "award catalog"
            ) {
                this.isLoading = false;
                this.showToast(
                    "Invalid File",
                    "Upload a valid file with columns: Student Id, Award Catalog (optional: Award Date)",
                    "error"
                );
                return;
            }

            // Extract rows
            const rows = json.slice(1);

            // Helper to parse Excel dates and return ISO datetimes (handles Date objects, ISO strings, and Excel serial numbers)
            const parseExcelDate = (val) => {
                if (!val && val !== 0) return '';
                try {
                    if (val instanceof Date) return val.toISOString();
                    if (typeof val === 'number') {
                        const jsDate = new Date((val - 25569) * 86400 * 1000);
                        if (!isNaN(jsDate)) return jsDate.toISOString();
                        return String(val);
                    }
                    const asStr = String(val).trim();
                    const parsed = new Date(asStr);
                    if (!isNaN(parsed)) return parsed.toISOString();
                    return asStr;
                } catch (e) {
                    return String(val);
                }
            };

            // Helper to extract just the date part (YYYY-MM-DD) for display
            const formatDateDisplay = (isoString) => {
                if (!isoString) return '';
                return isoString.split('T')[0];
            };

            this.fileData = rows
                .filter((row) => row && row.length >= 2)
                .map((row, index) => ({
                    id: "row_" + index,
                    studentId: row[0] ? String(row[0]).trim() : "",
                    awardCatalog: row[1] ? String(row[1]).trim() : "",
                    // Award Date is optional in the sheet (column 3) - store ISO for backend, format for display
                    awardDate: parseExcelDate(row[2]),
                    awardDateDisplay: formatDateDisplay(parseExcelDate(row[2]))
                }))
                .filter((r) => r.studentId && r.awardCatalog);

            // Keep your existing table columns and add Award Date
            this.dynamicColumns = [
                { label: "Student ID", fieldName: "studentId", type: "text" },
                { label: "Award Catalog", fieldName: "awardCatalog", type: "text" },
                { label: "Award Date", fieldName: "awardDateDisplay", type: "text" }
            ];

            this.isLoading = false;
            this.showToast("Success", `${this.fileData.length} records loaded`, "success");

        } catch (error) {
            this.isLoading = false;
            this.showToast("Error", "Failed to parse Excel file: " + error.message, "error");
        }
    };

    reader.onerror = () => {
        this.isLoading = false;
        this.showToast("Error", "Failed to read file", "error");
    };

    reader.readAsArrayBuffer(file);
}

   handleSubmit() {
    this.isLoading = true;

    processAwardData({ records: this.fileData })
        .then(result => {
            console.log(result);

            let errorMessage = '';
            if (result.errorRows && result.errorRows.length > 0) {
                const firstError = result.errorRows[0];
                errorMessage = firstError.errorMessage;
            }

            this.showToast(
                'Completed',
                `${result.successCount} inserted | ${result.failedCount} failed${errorMessage ? (' - ' + errorMessage) : ''}`,
                result.failedCount > 0 ? 'warning' : 'success'
            );

            this.errorCSV = result.failedCount > 0 ? result.errorCSV : null;
            if (result.successCount > 0) {
                setTimeout(() => {
                    window.location.href = '/lightning/o/Award/list?filterName=Recent';
                }, 700);
            }
        })
        .catch(error => {
            this.showToast('Error', error.body?.message || error.message, 'error');
        })
        .finally(() => {
            this.isLoading = false;
        });
}
downloadErrorCSV() {
    if (!this.errorCSV) return;

    const base64CSV = btoa(unescape(encodeURIComponent(this.errorCSV)));
    const dataUrl = 'data:text/csv;base64,' + base64CSV;

    const link = document.createElement('a');
    link.href = dataUrl;
    link.download = 'AwardUploadResults.csv';

    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
}

    resetForm() {
        this.fileData = [];
        this.fileName = '';
        this.dynamicColumns = [];
        const input = this.template.querySelector('lightning-input[type="file"]');
        if (input) input.value = '';
    }
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant, mode: 'dismissable' }));
    }
}