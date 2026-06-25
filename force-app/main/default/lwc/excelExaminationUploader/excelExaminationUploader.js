import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import processExaminationData from '@salesforce/apex/ExaminationUploadController.processExaminationData';
import SHEETJS from '@salesforce/resourceUrl/SheetJS';
import { loadScript } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { publish, MessageContext } from 'lightning/messageService';
import EXAM_REFRESH_CHANNEL from '@salesforce/messageChannel/examDataRefreshChannel__c';

export default class ExcelExaminationUploader extends NavigationMixin(LightningElement) {

    fileData = [];
    fileName = '';
    sheetJsInitialized = false;
    isLoading = false;
    dynamicColumns = [];
    errorColumns = [];                 // <<< ADDED

    
    // NEW
    errorData = [];
    errorCSV = '';

    @wire(MessageContext)
    messageContext;

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
        return this.fileData.map((row, index) => ({
            id: `row-${index}`,
            ...row
        }));
    }

    renderedCallback() {
        if (this.sheetJsInitialized) return;
        this.sheetJsInitialized = true;
        loadScript(this, SHEETJS)
            .then(() => console.log('SheetJS loaded'))
            .catch(() => this.showToast('Error', 'SheetJS failed to load.', 'error'));
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
                const worksheet = workbook.Sheets[workbook.SheetNames[0]];
                const json = window.XLSX.utils.sheet_to_json(worksheet, { header: 1 });

                if (!json || json.length <= 1) {
                    this.showToast('Error', 'No data found in Excel.', 'error');
                    this.resetForm();
                    return;
                }

                const headers = json[0].map(h => (h ? String(h).trim() : h));
                this.dynamicColumns = this.generateDynamicColumns(headers);

                this.fileData = json.slice(1)
                    .filter(r => r && r.some(v => v !== null && v !== undefined && v !== ''))
                    .map(r => {
                        const record = {};
                        headers.forEach((header, i) => {
                            if (header && r[i] !== undefined && r[i] !== null && r[i] !== '') {
                                const cleanFieldName = this.getCleanFieldName(header);
                                record[cleanFieldName] = r[i];
                            }
                        });

                        // >>> ADDED BLOCK START - Fix display for UI and matching Excel visual output
                        // FIX: Convert Excel numeric or string to Salesforce-compatible YYYY-MM-DD format
if (record.Date_of_Exam) {
    if (!isNaN(record.Date_of_Exam)) {
        // Excel numeric date conversion
        const excelEpoch = new Date(Date.UTC(1899, 11, 30)); 
        const dateValue = new Date(excelEpoch.getTime() + record.Date_of_Exam * 86400000);
        record.Date_of_Exam = dateValue.toISOString().split('T')[0]; // ---> YYYY-MM-DD
    } else {
        // Convert formatted dd-mmm-yyyy to yyyy-mm-dd
        const parsed = new Date(record.Date_of_Exam);
        record.Date_of_Exam = parsed.toISOString().split('T')[0];
    }
}

                        if (record.Time_of_Exam) {
                            record.Time_of_Exam = record.Time_of_Exam.toUpperCase().replace("AM", " AM").replace("PM"," PM"); // >>> ADDED
                        }
                        // >>> FIX for numeric End_Time coming from Excel
                     if (record.End_Time) {
                      if (typeof record.End_Time === "number") {
                       record.End_Time = window.XLSX.SSF.format("hh:mm AM/PM", record.End_Time); // Convert excel numeric time
                     } else if (typeof record.End_Time === "string") {
                      record.End_Time = record.End_Time.toUpperCase().replace("AM"," AM").replace("PM"," PM");
                     }
                   }

                        // >>> ADDED BLOCK END

                        return record;
                    })
                    .filter(rec => Object.keys(rec).length > 0 && rec.Name && rec.Exam_Schedule);

                if (this.fileData.length === 0)
                    this.showToast('Warning', 'No valid data found.', 'warning');
                else
                    this.showToast('Success', `Loaded ${this.fileData.length} records for preview.`, 'success');

            } catch (e) {
                this.showToast('Error', 'Error reading Excel: ' + e.message, 'error');
                console.error(e);
                this.resetForm();
            } finally {
                this.isLoading = false;
            }
        };

        reader.onerror = () => {
            this.showToast('Error', 'Error reading file.', 'error');
            this.isLoading = false;
            this.resetForm();
        };

        reader.readAsArrayBuffer(file);
    }

    generateDynamicColumns(headers) {
        return headers
            .filter(h => h && h.trim() !== '')
            .map(header => {
                const cleanFieldName = this.getCleanFieldName(header);
                return {
                    label: header,
                    fieldName: cleanFieldName,
                    type: 'text',
                    initialWidth: 200,
                    wrapText: true
                };
            });
    }

    getCleanFieldName(header) {
        const fieldMap = {
            'Name': 'Name',
            'Exam Schedule': 'Exam_Schedule',
            'Term': 'Academic_Term',
            'Course Name': 'Course_Catalog',
            'Date of Exam': 'Date_of_Exam',
            'Time of Exam': 'Time_of_Exam',
            'Duration of Exam': 'Duration_mins',
            'Venue': 'Venue',
            'Program': 'Program',
            'Allott No. of AAs': 'Allott_No_of_AAs',
            'Status': 'Status',
            'End Time': 'End_Time'//,        // >>> ADDED
           // 'Exam Venue': 'Exam_Venue'     // >>> ADDED
        };
        const lowerHeader = header.trim().toLowerCase();
        return fieldMap[header] || Object.keys(fieldMap).find(k => k.toLowerCase() === lowerHeader) || header.replace(/\s+/g, '_');
    }

  handleSubmit() {

    this.isLoading = true;

    processExaminationData({ records: this.fileData })
        .then(result => {

            // Always show summary result toast
            this.showToast(
                "Upload Result",
                `Inserted: ${result.successCount} | Failed: ${result.failedCount}`,
                result.failedCount > 0 ? "warning" : "success"
            );

           if (result.failedCount > 0) {

    if (!this.dynamicColumns.find(c => c.fieldName === "Error")) {
        this.dynamicColumns = [
            ...this.dynamicColumns,
            {
                label: "Error",
                fieldName: "Error",
                type: "text",
                wrapText: false,
                cellAttributes: { class: 'error-cell' }
            }
        ];
    }

    this.errorData = result.errorRows.map(err => {
        const rowNumber = parseInt(err.match(/Row\s(\d+)/)[1], 10);
        const originalRow = this.fileData[rowNumber - 2] || {};
        return { ...originalRow, Error: err, id: rowNumber };
    });

    this.errorCSV = result.errorCSV;

    if (result.successCount > 0)
        this.showToast("Success", `${result.successCount} records inserted`, "success");

    // >>> Replace generic toast with detailed error message
    const detailedErrorMessage = result.errorRows.length
        ? result.errorRows[0]
        : "Upload failed";

    this.showToast("Error", detailedErrorMessage, "error");

    //setTimeout(() => this.downloadErrorCSV(), 600);
    this.isLoading = false;
    return;
}

            // All rows successful
            if (result.successCount > 0 && result.failedCount === 0) {
                this.showToast("Success", `${result.successCount} records inserted successfully`, "success");
                publish(this.messageContext, EXAM_REFRESH_CHANNEL, { refresh: true });
                this.resetForm();
                window.history.back();
            }
        })
        .catch(err => {
            // Standard catch block for unexpected exceptions
            this.showToast("Error", err.body?.message || "Unexpected error occurred", "error");
        })
        .finally(() => (this.isLoading = false));
}

    downloadErrorCSV() {
        if (!this.errorCSV) return;
        const link = document.createElement("a");
        link.style.display = "none"; 
        link.href = "data:text/csv;base64," + btoa(unescape(encodeURIComponent(this.errorCSV)));
        link.download = "ExamUploadResults.csv";
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
    }

    resetForm() {
        this.fileData = [];
        this.fileName = '';
        this.dynamicColumns = [];
        this.errorData = []; 
        this.errorCSV = '';   

        const fileInput = this.template.querySelector('lightning-input[type="file"]');
        if (fileInput) fileInput.value = '';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}