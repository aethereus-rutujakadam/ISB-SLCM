import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { loadScript } from 'lightning/platformResourceLoader';
import SHEETJS from '@salesforce/resourceUrl/SheetJS';
import uploadCourseManagers from '@salesforce/apex/CourseManagerUploadController.uploadCourseManagers';

export default class CourseManagerUploader extends NavigationMixin(LightningElement) {
    fileName;
    fileData = [];
    columns = [];
    sheetLoaded = false;
    isLoading = false;
    uploadMessages = [];
    hasUploadErrors = false;
    hasUploadWarnings = false;

    // Required columns for validation
    requiredColumns = ['owner', 'courses', 'coursecode', 'coursetype', 'location', 'academicyear', 'academicterm', 'roles'];

    get recordsCount() {
        return this.fileData.length;
    }

    get isUploadDisabled() {
        return this.isLoading || this.fileData.length === 0;
    }

    /**
     * Load SheetJS library on component render
     */
    renderedCallback() {
        if (this.sheetLoaded) return;
        loadScript(this, SHEETJS)
            .then(() => { 
                this.sheetLoaded = true; 
            })
            .catch(error => {
                this.showToast('error', 'Error Loading SheetJS', error.message);
            });
    }

    /**
     * Handle file selection and parse Excel
     */
    handleFileChange(event) {
        const file = event.target.files[0];
        if (!file) return;

        this.fileName = file.name;
        this.uploadMessages = [];
        this.hasUploadErrors = false;
        this.hasUploadWarnings = false;
        const reader = new FileReader();

        reader.onload = e => {
            try {
                const data = new Uint8Array(e.target.result);
                const workbook = window.XLSX.read(data, { type: 'array' });
                const sheet = workbook.Sheets[workbook.SheetNames[0]];
                const json = window.XLSX.utils.sheet_to_json(sheet);

                if (json.length === 0) {
                    this.showToast('error', 'Validation Error', 'Excel file has no data rows');
                    this.resetForm();
                    return;
                }

                // Add unique ID for datatable
                this.fileData = json.map((r, i) => ({ id: i, ...r }));

                // Validate required columns exist (case-insensitive)
                const firstRow = this.fileData[0];
                const fileColumns = Object.keys(firstRow).map(k => k.toLowerCase());
                
                const missingColumns = this.requiredColumns.filter(
                    reqCol => !fileColumns.includes(reqCol)
                );

                if (missingColumns.length > 0) {
                    this.showToast(
                        'error', 
                        'Missing Required Columns', 
                        `Excel must have columns: Owner, Courses, CourseCode, CourseType, Location, AcademicYear, AcademicTerm, Roles. Missing: ${missingColumns.join(', ')}`
                    );
                    this.resetForm();
                    return;
                }

                // Generate columns for preview table
                if (this.fileData.length > 0) {
                    this.columns = Object.keys(this.fileData[0])
                        .filter(key => key !== 'id')
                        .map(col => ({ 
                            label: col, 
                            fieldName: col, 
                            type: 'text', 
                            wrapText: true 
                        }));
                }

            } catch (error) {
                this.showToast('error', 'Error Parsing Excel', error.message);
                this.resetForm();
            }
        };

        reader.onerror = () => {
            this.showToast('error', 'Error Reading File', 'Unable to read the selected file');
            this.resetForm();
        };

        reader.readAsArrayBuffer(file);
    }

    /**
     * Handle upload button click
     */
    handleUploadClick() {
        console.log('🔵 handleUploadClick called');
        if (this.fileData.length === 0) {
            console.warn('⚠️ No file data');
            this.showToast('error', 'Validation Error', 'Please select an Excel file with data');
            return;
        }

        this.isLoading = true;
        this.uploadMessages = [];
        this.hasUploadErrors = false;
        this.hasUploadWarnings = false;
        console.log('🟢 Starting upload with', this.fileData.length, 'rows');

        // Remove 'id' field before sending to Apex
        const rowsJson = JSON.stringify(this.fileData.map(({ id, ...rest }) => rest));
        console.log('📤 Sending to Apex:', rowsJson.substring(0, 200) + '...');

        uploadCourseManagers({ rowsJson })
            .then(result => {
                console.log('✅ Apex returned result:', JSON.stringify(result));
                this.handleUploadResult(result);
            })
            .catch(error => {
                console.error('❌ Apex error:', error);
                this.showToast('error', 'Error', error.body?.message || error.message || 'Unknown error occurred');
            })
            .finally(() => {
                this.isLoading = false;
                console.log('🔚 Upload handler finally block, isLoading set to false');
            });
    }

    /**
     * Handle upload result from Apex
     */
    handleUploadResult(result) {
        console.log('\ud83d\udcca handleUploadResult called with result:', result);
        console.log('  - isSuccess:', result.isSuccess);
        console.log('  - totalRowsSubmitted:', result.totalRowsSubmitted);
        console.log('  - warnings count:', result.warnings ? result.warnings.length : 0);
        console.log('  - errors count:', result.errors ? result.errors.length : 0);
        
        const messages = [];
        console.log('\ud83c\udfab Created empty messages array, length:', messages.length);
        
        const hasErrors = result.errors && result.errors.length > 0;
        console.log('📊 hasErrors:', hasErrors);

        if (hasErrors) {
            console.log('\ud83d\udea8 Processing errors...');
            result.errors.forEach(error => {
                console.error('🚫 Error:', error);
                messages.push({
                    type: 'error',
                    text: error,
                    cssClass: 'slds-notify slds-notify_alert slds-alert_error slds-m-bottom_small'
                });
            });
            console.log('After errors, messages.length:', messages.length);
            this.hasUploadErrors = true;
        } else {
            console.log('\u2705 No fatal errors, processing warnings/success...');
            // Process warnings and skipped records
            if (result.warnings && result.warnings.length > 0) {
                console.log('\u26a0\ufe0f Total warnings:', result.warnings.length);
                result.warnings.forEach((warning, index) => {
                    console.warn('Warning ' + (index + 1) + ':', warning);
                    messages.push({
                        type: 'warning',
                        text: warning,
                        cssClass: 'slds-notify slds-notify_alert slds-alert_warning slds-m-bottom_small'
                    });
                });
                console.log('After warnings, messages.length:', messages.length);
                this.hasUploadWarnings = true;
            } else {
                console.log('ℹ️ No warnings to display');
            }

            // Success message for processed rows
            console.log('Checking success condition: isSuccess=' + result.isSuccess + ', totalRowsSubmitted=' + result.totalRowsSubmitted);
            if (result.isSuccess && result.totalRowsSubmitted > 0) {
                console.log('✅ Entering success branch - pushing success message');
                messages.push({
                    type: 'info',
                    text: `Successfully submitted ${result.totalRowsSubmitted} row(s) for processing. Processing happens in the background. Check Error Handling records for batch results.`,
                    cssClass: 'slds-notify slds-notify_alert slds-alert_info slds-m-bottom_small'
                });
                console.log('After success message, messages.length:', messages.length);
            } else if (result.totalRowsSubmitted === 0) {
                console.log('⚠️ No rows submitted - pushing warning');
                messages.push({
                    type: 'warning',
                    text: 'No valid records to process. Please check the skipped records above.',
                    cssClass: 'slds-notify slds-notify_alert slds-alert_warning slds-m-bottom_small'
                });
                console.log('After no-records warning, messages.length:', messages.length);
                this.hasUploadWarnings = true;
            }
        }

        console.log('\ud83d\udccb Before assignment - messages array:', messages);
        console.log('\ud83d\udccb messages.length before assignment:', messages.length);
        this.uploadMessages = messages;
        console.log('\ud83d\udccb After assignment - this.uploadMessages:', this.uploadMessages);
        console.log('\ud83d\udccb this.uploadMessages.length after assignment:', this.uploadMessages.length);
        this.isLoading = false;
        console.log('✔️ handleUploadResult complete');
    }

    /**
     * Clear messages
     */
    clearMessages() {
        this.uploadMessages = [];
        this.hasUploadErrors = false;
        this.hasUploadWarnings = false;
    }

    /**
     * Get CSS class for message based on type
     */
    getMessageClass(messageType) {
        const baseClass = 'slds-notify slds-notify_alert slds-m-bottom_small';
        if (messageType === 'error') {
            return baseClass + ' slds-alert_error';
        } else if (messageType === 'warning') {
            return baseClass + ' slds-alert_warning';
        } else {
            return baseClass + ' slds-alert_info';
        }
    }

    /**
     * Reset form to initial state
     */
    resetForm() {
        this.fileName = null;
        this.fileData = [];
        this.columns = [];
        this.uploadMessages = [];
        this.hasUploadErrors = false;
        this.hasUploadWarnings = false;
        const input = this.template.querySelector('lightning-input[type="file"]');
        if (input) input.value = null;
    }

    /**
     * Show toast notification
     */
    showToast(variant, title, message) {
        this.dispatchEvent(new ShowToastEvent({ 
            title, 
            message, 
            variant,
            mode: variant === 'error' ? 'sticky' : 'dismissable'
        }));
    }
}