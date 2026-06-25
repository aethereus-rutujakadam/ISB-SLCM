import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import processPaymentUpload from '@salesforce/apex/UploadInstallmentPaymentsController.processPaymentUpload';

const BATCH_SIZE = 100;

// Dynamically load SheetJS library
function loadSheetJS() {
    return new Promise((resolve, reject) => {
        if (typeof XLSX !== 'undefined') {
            console.log('SheetJS already loaded');
            resolve();
            return;
        }
        
        console.log('Loading SheetJS library...');
        const script = document.createElement('script');
        script.src = 'https://cdn.jsdelivr.net/npm/xlsx@0.18.5/dist/xlsx.full.min.js';
        script.async = true;
        script.onload = () => {
            console.log('SheetJS loaded successfully');
            resolve();
        };
        script.onerror = () => {
            console.error('Failed to load SheetJS');
            reject(new Error('Failed to load Excel library'));
        };
        document.head.appendChild(script);
    });
}

export default class UploadInstallmentPayments extends LightningElement {
    @track fileData = null;
    @track isProcessing = false;
    @track processResult = null;
    @track currentBatch = 0;
    @track totalBatches = 0;
    @track totalRowsInFile = 0;

    get isProcessDisabled() {
        return !this.fileData || this.fileData.length === 0;
    }

    get hasErrors() {
        return this.processResult && 
               Array.isArray(this.processResult.errorMessages) && 
               this.processResult.errorMessages.length > 0;
    }

    get hasWarnings() {
        return this.processResult && 
               Array.isArray(this.processResult.warnings) && 
               this.processResult.warnings.length > 0;
    }

    get errorList() {
        console.log('=== errorList getter ===');
        console.log('processResult:', this.processResult);
        
        if (!this.processResult) {
            console.log('processResult is null/undefined, returning []');
            return [];
        }

        const errorMessages = this.processResult.errorMessages;
        console.log('errorMessages value:', errorMessages);
        console.log('errorMessages type:', typeof errorMessages);
        console.log('Is array?:', Array.isArray(errorMessages));

        if (Array.isArray(errorMessages)) {
            console.log('Returning array of', errorMessages.length, 'errors');
            return errorMessages;
        }

        // If it's an object but not an array, convert it
        if (errorMessages && typeof errorMessages === 'object') {
            console.log('Converting object to array');
            const arr = Object.values(errorMessages);
            console.log('Converted to array of', arr.length, 'items');
            return arr;
        }

        console.log('Returning empty array as fallback');
        return [];
    }

    get warningList() {
        console.log('=== warningList getter ===');
        console.log('processResult:', this.processResult);
        
        if (!this.processResult) {
            console.log('processResult is null/undefined, returning []');
            return [];
        }

        const warnings = this.processResult.warnings;
        console.log('warnings value:', warnings);
        console.log('warnings type:', typeof warnings);
        console.log('Is array?:', Array.isArray(warnings));

        if (Array.isArray(warnings)) {
            console.log('Returning array of', warnings.length, 'warnings');
            return warnings;
        }

        // If it's an object but not an array, convert it
        if (warnings && typeof warnings === 'object') {
            console.log('Converting object to array');
            const arr = Object.values(warnings);
            console.log('Converted to array of', arr.length, 'items');
            return arr;
        }

        console.log('Returning empty array as fallback');
        return [];
    }

    get hasSuccessRecords() {
        return this.processResult && this.processResult.successCount > 0;
    }

    get hasFailedRecords() {
        return this.processResult && this.processResult.errorCount > 0;
    }

    /**
     * Handle file upload
     */
    handleFileUpload(event) {
        console.log('=== handleFileUpload START ===');
        try {
            const input = event.target;
            console.log('Files:', input.files.length);

            if (!input.files || input.files.length === 0) {
                this.showToast('Warning', 'No file selected', 'warning');
                return;
            }

            const file = input.files[0];
            console.log('File:', file.name, 'Size:', file.size, 'Type:', file.type);

            const fileName = file.name.toLowerCase();
            this.readAndParseFile(file);

        } catch (error) {
            console.error('handleFileUpload error:', error);
            this.showToast('Error', 'Upload error: ' + error.message, 'error');
        }
    }

    /**
     * Read and parse file
     */
    readAndParseFile(file) {
        console.log('=== readAndParseFile START ===');
        console.log('File name:', file.name);
        console.log('File type:', file.type);
        console.log('File size:', file.size);
        
        const fileName = file.name.toLowerCase();
        
        // Check file type
        if (fileName.endsWith('.xlsx') || fileName.endsWith('.xls')) {
            console.log('Excel file detected - using SheetJS parser');
            this.readExcelFile(file);
        } else if (fileName.endsWith('.csv')) {
            console.log('CSV file detected - using CSV parser');
            this.readCSVFile(file);
        } else {
            this.showToast('Error', 'Unsupported file format. Please use Excel or CSV.', 'error');
        }
    }

    /**
     * Read CSV file
     */
    readCSVFile(file) {
        const reader = new FileReader();

        reader.onload = (event) => {
            console.log('CSV read complete');
            try {
                const content = event.target.result;
                console.log('Content length:', content.length);
                console.log('First 500 chars:', content.substring(0, 500));

                if (!content || content.length === 0) {
                    throw new Error('File is empty');
                }

                this.fileData = this.csvToArray(content);
                this.totalRowsInFile = this.fileData.length;

                console.log('✅ Parsed rows:', this.fileData.length);
                console.log('fileData:', this.fileData);

                if (!this.fileData || this.fileData.length === 0) {
                    this.showToast('Warning', 'No data found - please check your file format', 'warning');
                } else {
                    this.showToast('Success', `✅ Loaded ${this.fileData.length} records from CSV`, 'success');
                }
            } catch (error) {
                console.error('❌ Parse error:', error);
                console.error('Full error:', error.stack);
                this.fileData = null;
                this.showToast('Error', 'Parse error: ' + error.message, 'error');
            }
        };

        reader.onerror = () => {
            console.error('Read error:', reader.error);
            this.showToast('Error', 'Failed to read: ' + reader.error.name, 'error');
        };

        reader.readAsText(file);
    }

    /**
     * Read Excel file
     */
    readExcelFile(file) {
        // First, load SheetJS library if not already loaded
        loadSheetJS().then(() => {
            const reader = new FileReader();

            reader.onload = (event) => {
                console.log('Excel read complete');
                try {
                    const data = new Uint8Array(event.target.result);
                    
                    // Check if SheetJS library is available
                    if (typeof XLSX === 'undefined') {
                        throw new Error('Excel library not loaded. Please try again.');
                    }

                    // Read workbook
                    const workbook = XLSX.read(data, { type: 'array' });
                    console.log('Workbook loaded, sheet names:', workbook.SheetNames);

                    // Get first sheet
                    const sheet = workbook.Sheets[workbook.SheetNames[0]];
                    console.log('First sheet:', workbook.SheetNames[0]);

                    // Convert sheet to JSON
                    const jsonData = XLSX.utils.sheet_to_json(sheet);
                    console.log('JSON data:', jsonData);

                    // Parse to payment rows
                    this.fileData = this.excelToArray(jsonData);
                    this.totalRowsInFile = this.fileData.length;

                    console.log('Parsed rows:', this.fileData.length);

                    if (this.fileData.length === 0) {
                        this.showToast('Warning', 'No data found', 'warning');
                    } else {
                        this.showToast('Success', `Loaded ${this.fileData.length} records from Excel`, 'success');
                    }
                } catch (error) {
                    console.error('Excel parse error:', error);
                    this.showToast('Error', 'Excel parse error: ' + error.message, 'error');
                }
            };

            reader.onerror = () => {
                console.error('Read error:', reader.error);
                this.showToast('Error', 'Failed to read: ' + reader.error.name, 'error');
            };

            reader.readAsArrayBuffer(file);
        }).catch((error) => {
            console.error('Failed to load Excel library:', error);
            this.showToast('Error', 'Failed to load Excel library: ' + error.message, 'error');
        });
    }

    /**
     * Convert Excel JSON to payment array
     */
    excelToArray(jsonData) {
        console.log('=== excelToArray START ===');
        console.log('JSON rows:', jsonData.length);
        
        // Check if Total Amount column exists by checking first row keys - warn if missing but don't block
        if (jsonData.length > 0) {
            const firstRowKeys = Object.keys(jsonData[0]);
            const hasTotalAmount = firstRowKeys.some(key => {
                const lower = key.toLowerCase();
                return (lower.includes('total') && lower.includes('amount')) || 
                       lower === 'total amount' ||
                       lower === 'total_amount' ||
                       lower === 'totalamount' ||
                       lower.includes('total amt');
            });
            
            if (!hasTotalAmount) {
                console.warn('WARNING: Total Amount column not found in Excel!');
                console.log('Available columns:', firstRowKeys.join(' | '));
            }
        }
        
        const rows = [];
        let rowNum = 0;

        for (const row of jsonData) {
            rowNum++;
            console.log(`\nRow ${rowNum}:`, row);

            // Find and normalize column values (SheetJS sometimes uses different key patterns)
            const getColumnValue = (keys, row) => {
                for (const key of keys) {
                    if (row[key] !== undefined && row[key] !== null && row[key] !== '') {
                        return String(row[key]).trim();
                    }
                }
                return '';
            };

            const studentId = getColumnValue(
                ['Student ID', 'student id', 'StudentID', 'studentid', 'STUDENT ID'],
                row
            );

            if (!studentId) {
                console.log(`  → SKIPPED: No Student ID`);
                continue;
            }

            console.log(`  → Student ID: ${studentId}`);

            const paymentRow = {
                rowNumber: rowNum,
                studentId: studentId,
                bpid: getColumnValue(['BPID', 'bpid', 'BP ID'], row),
                cohort: getColumnValue(['Cohort', 'cohort', 'COHORT'], row),
                firstName: getColumnValue(['First Name', 'first name', 'FirstName', 'firstname'], row),
                lastName: getColumnValue(['Last Name', 'last name', 'LastName', 'lastname'], row),
                fullName: getColumnValue(['Full name', 'full name', 'FullName', 'fullname', 'Full Name'], row),
                commitmentFee: this.parseDecimal(getColumnValue(['Commitment', 'commitment', 'COMMITMENT'], row)),
                tuitionFee: this.parseDecimal(getColumnValue(['Tuition Fee', 'tuition fee', 'Tuition', 'tuition'], row)),
                tuitionWaiver: this.parseDecimal(getColumnValue(['Tuition Waiver', 'tuition waiver'], row)),
                quadAccommodation: this.parseDecimal(getColumnValue(['Quad Accommodation', 'quad accommodation', 'Quad Accom'], row)),
                studioAccommodation: this.parseDecimal(getColumnValue(['Studio Accommodation', 'studio accommodation', 'Studio Accom'], row)),
                gst: this.parseDecimal(getColumnValue(['GST', 'gst', 'Gst'], row)),
                securityDeposit: this.parseDecimal(getColumnValue(['Security deposit', 'security deposit', 'Security Deposit'], row)),
                totalAmount: this.parseDecimal(getColumnValue(['Total Amount', 'total amount', 'Total_Amount', 'total_amount', 'Totalamount', 'totalamount'], row))
            };

            console.log(`  → Row added:`, paymentRow);
            rows.push(paymentRow);
        }

        console.log(`\n=== FINAL RESULT ===`);
        console.log(`Total rows: ${rows.length}`);
        console.log('=== excelToArray END ===');
        return rows;
    }

    /**
     * Convert CSV to array
     */
    csvToArray(csvString) {
        console.log('=== csvToArray START ===');
        console.log('CSV length:', csvString.length);
        console.log('First 500 chars:', csvString.substring(0, 500));
        
        const rows = [];
        const lines = csvString.split('\n');
        console.log('Total lines:', lines.length);

        if (lines.length < 2) return rows;

        // Find header row (first non-empty line)
        let headerIdx = 0;
        for (let i = 0; i < lines.length; i++) {
            if (lines[i].trim().length > 0) {
                headerIdx = i;
                break;
            }
        }

        const headers = this.parseCSVLine(lines[headerIdx]);
        console.log('=== HEADERS ===');
        console.log('Raw headers:', headers);
        console.log('Header count:', headers.length);
        headers.forEach((h, i) => console.log(`Header[${i}]: "${h}"`));

        // Find column indices with more flexible matching and fallbacks
        const indices = {
            sNo: headers.findIndex(h => {
                const lower = h.toLowerCase().trim();
                return lower.includes('s.no') || lower.includes('s. no') || lower === 's. no' || lower === 's.no';
            }),
            studentId: headers.findIndex(h => {
                const lower = h.toLowerCase().trim();
                return (lower.includes('student') && lower.includes('id')) || lower === 'student id' || lower === 'studentid';
            }),
            bpid: headers.findIndex(h => h.toLowerCase().trim() === 'bpid'),
            cohort: headers.findIndex(h => h.toLowerCase().trim() === 'cohort'),
            firstName: headers.findIndex(h => {
                const lower = h.toLowerCase().trim();
                return lower.includes('first') && lower.includes('name');
            }),
            lastName: headers.findIndex(h => {
                const lower = h.toLowerCase().trim();
                return lower.includes('last') && lower.includes('name');
            }),
            fullName: headers.findIndex(h => {
                const lower = h.toLowerCase().trim();
                return lower.includes('full') && lower.includes('name');
            }),
            commitmentFee: headers.findIndex(h => {
                const lower = h.toLowerCase().trim();
                return lower.includes('commitment');
            }),
            tuitionFee: headers.findIndex(h => {
                const lower = h.toLowerCase().trim();
                return lower.includes('tuition') && !lower.includes('waiver');
            }),
            tuitionWaiver: headers.findIndex(h => {
                const lower = h.toLowerCase().trim();
                return lower.includes('tuition') && lower.includes('waiver');
            }),
            quadAccommodation: headers.findIndex(h => {
                const lower = h.toLowerCase().trim();
                return lower.includes('quad');
            }),
            studioAccommodation: headers.findIndex(h => {
                const lower = h.toLowerCase().trim();
                return lower.includes('studio');
            }),
            gst: headers.findIndex(h => h.toLowerCase().trim() === 'gst'),
            securityDeposit: headers.findIndex(h => {
                const lower = h.toLowerCase().trim();
                return lower.includes('security');
            }),
            totalAmount: headers.findIndex(h => {
                const lower = h.toLowerCase().trim();
                return (lower.includes('total') && lower.includes('amount')) || 
                       lower === 'total amount' ||
                       lower === 'total_amount' ||
                       lower === 'totalamount' ||
                       lower.includes('total amt');
            })
        };

        console.log('=== COLUMN INDICES ===');
        Object.keys(indices).forEach(key => {
            const idx = indices[key];
            const colName = idx >= 0 ? headers[idx] : 'NOT FOUND';
            console.log(`${key}: ${idx} (${colName})`);
        });

        // Check if critical columns were found
        if (indices.studentId < 0) {
            console.error('❌ CRITICAL: Student ID column not found!');
            console.log('Available columns:', headers.join(' | '));
            throw new Error('Student ID column not found. Check your CSV headers.');
        }

        // Check if Total Amount column exists - warn if missing but don't block
        if (indices.totalAmount < 0) {
            console.warn('⚠️  WARNING: Total Amount column not found - will use 0');
            console.log('Available columns:', headers.join(' | '));
        }

        // Parse data rows
        let dataRowsParsed = 0;
        let rowsSkipped = 0;
        
        for (let i = headerIdx + 1; i < lines.length; i++) {
            const line = lines[i].trim();
            
            // Skip empty lines
            if (line.length === 0) {
                console.log(`Line ${i}: EMPTY, skipping`);
                rowsSkipped++;
                continue;
            }

            const values = this.parseCSVLine(line);
            console.log(`Line ${i}: ${values.length} columns - [${values.slice(0, 5).join(', ')}...]`);

            // Skip if no student ID
            const studentIdValue = values[indices.studentId];
            const studentId = studentIdValue ? String(studentIdValue).trim() : '';
            
            if (!studentId) {
                console.log(`  ⏭️  SKIPPED: No Student ID`);
                rowsSkipped++;
                continue;
            }

            console.log(`  ✅ Processing Row ${dataRowsParsed + 1}: Student=${studentId}`);

            const row = {
                rowNumber: i,
                studentId: studentId,
                bpid: values[indices.bpid] ? String(values[indices.bpid]).trim() : '',
                cohort: values[indices.cohort] ? String(values[indices.cohort]).trim() : '',
                firstName: values[indices.firstName] ? String(values[indices.firstName]).trim() : '',
                lastName: values[indices.lastName] ? String(values[indices.lastName]).trim() : '',
                fullName: values[indices.fullName] ? String(values[indices.fullName]).trim() : '',
                commitmentFee: this.parseDecimal(values[indices.commitmentFee]),
                tuitionFee: this.parseDecimal(values[indices.tuitionFee]),
                tuitionWaiver: this.parseDecimal(values[indices.tuitionWaiver]),
                quadAccommodation: this.parseDecimal(values[indices.quadAccommodation]),
                studioAccommodation: this.parseDecimal(values[indices.studioAccommodation]),
                gst: this.parseDecimal(values[indices.gst]),
                securityDeposit: this.parseDecimal(values[indices.securityDeposit]),
                totalAmount: indices.totalAmount >= 0 ? this.parseDecimal(values[indices.totalAmount]) : 0
            };

            console.log(`  → Row added: ${JSON.stringify(row)}`);
            rows.push(row);
            dataRowsParsed++;
        }

        console.log(`\n=== 📊 CSV PARSING COMPLETE ===`);
        console.log(`Total data rows parsed: ${dataRowsParsed}`);
        console.log(`Total rows skipped: ${rowsSkipped}`);
        console.log(`Total rows in array: ${rows.length}`);
        if (rows.length > 0) {
            console.log(`First row:`, rows[0]);
            console.log(`Last row:`, rows[rows.length - 1]);
        }
        console.log('=== csvToArray END ===');
        return rows;
    }

    /**
     * Parse CSV line
     */
    parseCSVLine(line) {
        const result = [];
        let current = '';
        let insideQuotes = false;

        for (let i = 0; i < line.length; i++) {
            const char = line[i];

            if (char === '"') {
                insideQuotes = !insideQuotes;
            } else if (char === ',' && !insideQuotes) {
                result.push(current.trim().replace(/^"|"$/g, ''));
                current = '';
            } else {
                current += char;
            }
        }

        result.push(current.trim().replace(/^"|"$/g, ''));
        return result;
    }

    /**
     * Parse decimal
     */
    parseDecimal(value) {
        if (!value) return 0;
        const num = parseFloat(String(value).replace(/[^0-9.-]/g, ''));
        return isNaN(num) ? 0 : num;
    }

    /**
     * Process payments
     */
    async handleProcessPayments() {
        console.log('=== 🚀 handleProcessPayments STARTED ===');
        console.log('Component state at processing time:');
        console.log('  this.fileData:', this.fileData);
        console.log('  typeof this.fileData:', typeof this.fileData);
        console.log('  is Array?:', Array.isArray(this.fileData));
        console.log('  fileData length:', this.fileData ? this.fileData.length : 'NULL/UNDEFINED');
        console.log('Full component:', this);
        
        // Defensive check
        if (!this.fileData) {
            console.error('❌ CRITICAL: fileData is null or undefined at processing time!');
            console.trace('Stack trace:');
            this.showToast('Error', 'No file data loaded. Please upload a file first.', 'error');
            return;
        }

        if (!Array.isArray(this.fileData)) {
            console.error('❌ CRITICAL: fileData is not an array!', typeof this.fileData);
            this.showToast('Error', 'File data is not in valid format', 'error');
            return;
        }

        if (this.fileData.length === 0) {
            console.error('❌ CRITICAL: fileData is empty array!');
            this.showToast('Warning', 'No records to process. File has no valid data.', 'warning');
            return;
        }

        console.log('✅ fileData validation PASSED');
        console.log('✅ Starting payment processing with', this.fileData.length, 'records');

        try {
            let allResults = {
                isSuccess: true,
                totalProcessed: this.fileData.length,  // Initialize with total file rows
                successCount: 0,
                errorCount: 0,
                errorMessages: [],
                warnings: []
            };
            
            console.log('📊 Initialized allResults with totalProcessed=' + allResults.totalProcessed);

            for (let i = 0; i < this.fileData.length; i += BATCH_SIZE) {
                this.currentBatch++;
                const batch = this.fileData.slice(i, i + BATCH_SIZE);
                
                console.log(`\n🔵 === BATCH ${this.currentBatch} START ===`);
                console.log(`📦 Batch size: ${batch.length} records`);
                console.log(`📋 Batch data (first 2 rows):`, batch.slice(0, 2));
                
                // Verify batch has proper structure
                if (!batch || batch.length === 0) {
                    console.error('❌ Batch is empty!');
                    break;
                }
                
                if (!batch[0].studentId) {
                    console.error('❌ First record has no studentId!', batch[0]);
                    break;
                }
                
                const batchJson = JSON.stringify(batch);
                console.log('Serialized batchJson length:', batchJson.length);
                console.log('Serialized batchJson first 300 chars:', batchJson.substring(0, 300));
                console.log('About to call processPaymentUpload()...');
                
                let result;
                try {
                    result = await processPaymentUpload({ paymentDataJson: batchJson });
                    console.log('✅ Apex call successful, result:', result);
                } catch (apexError) {
                    console.error('❌ APEX ERROR on call:', apexError);
                    console.error('Error message:', apexError.message);
                    console.error('Error body:', apexError.body);
                    this.showToast('Error', 'Apex failed: ' + apexError.message, 'error');
                    break;
                }

                if (!result) {
                    console.error('❌ Apex returned null/undefined');
                    this.showToast('Error', 'Apex returned no data', 'error');
                    break;
                }

                // Extract and validate each field
                const totalProcessed = parseInt(result.totalProcessed) || 0;
                const successCount = parseInt(result.successCount) || 0;
                const errorCount = parseInt(result.errorCount) || 0;
                const isSuccess = result.isSuccess === true;
                
                console.log('Extracted values:', { totalProcessed, successCount, errorCount, isSuccess });

                // Initialize arrays if they don't exist
                if (!result.errorMessages) {
                    result.errorMessages = [];
                }
                if (!result.warnings) {
                    result.warnings = [];
                }

                // Ensure errorMessages is an array
                let errorMessages = [];
                if (Array.isArray(result.errorMessages)) {
                    errorMessages = result.errorMessages;
                    console.log('errorMessages is array:', errorMessages.length, 'items');
                } else if (result.errorMessages && typeof result.errorMessages === 'object') {
                    errorMessages = Object.values(result.errorMessages);
                    console.log('errorMessages was object, converted to array:', errorMessages.length, 'items');
                } else if (result.errorMessages) {
                    console.warn('errorMessages is unexpected type:', typeof result.errorMessages);
                    errorMessages = [];
                }

                // Ensure warnings is an array
                let warnings = [];
                if (Array.isArray(result.warnings)) {
                    warnings = result.warnings;
                    console.log('warnings is array:', warnings.length, 'items');
                } else if (result.warnings && typeof result.warnings === 'object') {
                    warnings = Object.values(result.warnings);
                    console.log('warnings was object, converted to array:', warnings.length, 'items');
                } else if (result.warnings) {
                    console.warn('warnings is unexpected type:', typeof result.warnings);
                    warnings = [];
                }

                // Merge results safely
                allResults.totalProcessed += totalProcessed;
                allResults.successCount += successCount;
                allResults.errorCount += errorCount;
                allResults.errorMessages = allResults.errorMessages.concat(errorMessages);
                allResults.warnings = allResults.warnings.concat(warnings);
                allResults.isSuccess = allResults.isSuccess && isSuccess;

                console.log('Batch summary:', { 
                    totalProcessed, 
                    successCount, 
                    errorCount,
                    errorMessagesCount: errorMessages.length,
                    warningsCount: warnings.length
                });
                console.log('Running totals:', allResults);

                await new Promise(resolve => setTimeout(resolve, 500));
            }

            // Final result assignment
            console.log('\n=== Final Results ===');
            console.log('Final allResults:', allResults);
            console.log('errorMessages type:', typeof allResults.errorMessages);
            console.log('errorMessages is array:', Array.isArray(allResults.errorMessages));
            
            // Ensure errorMessages and warnings are always arrays
            if (!Array.isArray(allResults.errorMessages)) {
                console.warn('errorMessages is not an array, fixing...');
                allResults.errorMessages = allResults.errorMessages ? Object.values(allResults.errorMessages) : [];
            }
            if (!Array.isArray(allResults.warnings)) {
                console.warn('warnings is not an array, fixing...');
                allResults.warnings = allResults.warnings ? Object.values(allResults.warnings) : [];
            }

            console.log('After fix - errorMessages is array:', Array.isArray(allResults.errorMessages));
            console.log('After fix - warnings is array:', Array.isArray(allResults.warnings));

            this.processResult = allResults;
            this.showToast(
                allResults.isSuccess ? 'Success' : 'Completed',
                `${allResults.successCount} / ${allResults.totalProcessed}`,
                allResults.isSuccess ? 'success' : 'warning'
            );

        } catch (error) {
            console.error('Error during processing:', error);
            console.error('Error message:', error.message);
            console.error('Error stack:', error.stack);
            
            // Set error result
            this.processResult = {
                isSuccess: false,
                totalProcessed: this.fileData.length,
                successCount: 0,
                errorCount: this.fileData.length,
                errorMessages: ['Processing failed: ' + (error.message || 'Unknown error occurred')],
                warnings: []
            };
            
            this.showToast('Error', 'Processing failed: ' + (error.message || 'Unknown error'), 'error');
        }

        this.isProcessing = false;
    }

    /**
     * Download Success File
     */
    handleDownloadSuccessFile() {
        if (!this.processResult || !this.fileData) {
            this.showToast('Warning', 'No data to download', 'warning');
            return;
        }

        // Get error messages map for quick lookup
        const errorMap = {};
        this.processResult.errorMessages.forEach(msg => {
            // Error message format includes row info, parse it if possible
            const rowMatch = msg.match(/Row (\d+)/);
            if (rowMatch) {
                errorMap[rowMatch[1]] = msg;
            }
        });

        // Filter successful rows (those without errors)
        const successRows = this.fileData.filter(row => !errorMap[row.rowNumber]);

        if (successRows.length === 0) {
            this.showToast('Warning', 'No successful records to download', 'warning');
            return;
        }

        const csvContent = this.generateCSV(successRows);
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, -5);
        this.downloadFile(csvContent, `Success_Payments_${timestamp}.csv`);
        this.showToast('Success', `Downloaded ${successRows.length} successful records`, 'success');
    }

    /**
     * Download Failed File
     */
    handleDownloadFailedFile() {
        if (!this.processResult || !this.fileData) {
            this.showToast('Warning', 'No data to download', 'warning');
            return;
        }

        // Get error messages map
        const errorMap = {};
        this.processResult.errorMessages.forEach(msg => {
            const rowMatch = msg.match(/Row (\d+)/);
            if (rowMatch) {
                errorMap[rowMatch[1]] = msg;
            }
        });

        // Filter failed rows (those with errors)
        const failedRows = this.fileData.filter(row => errorMap[row.rowNumber]);

        if (failedRows.length === 0) {
            this.showToast('Warning', 'No failed records to download', 'warning');
            return;
        }

        // Create rows with error messages
        const failedRowsWithErrors = failedRows.map(row => ({
            ...row,
            errorMessage: errorMap[row.rowNumber] || 'Unknown error'
        }));

        const csvContent = this.generateCSVWithErrors(failedRowsWithErrors);
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, -5);
        this.downloadFile(csvContent, `Failed_Payments_${timestamp}.csv`);
        this.showToast('Success', `Downloaded ${failedRows.length} failed records`, 'success');
    }

    /**
     * Generate CSV from rows
     */
    generateCSV(rows) {
        if (rows.length === 0) return '';

        // Headers
        const headers = [
            'S.No',
            'Student ID',
            'BPID',
            'Cohort',
            'First Name',
            'Last Name',
            'Full Name',
            'Tuition Fee',
            'Quad Accommodation',
            'Studio Accommodation',
            'GST',
            'Security Deposit',
            'Total Amount'
        ];

        // Build CSV
        let csv = headers.join(',') + '\n';

        rows.forEach((row, index) => {
            const values = [
                (index + 1).toString(),
                this.escapeCsv(row.studentId),
                this.escapeCsv(row.bpid),
                this.escapeCsv(row.cohort),
                this.escapeCsv(row.firstName),
                this.escapeCsv(row.lastName),
                this.escapeCsv(row.fullName),
                (row.tuitionFee || 0).toString(),
                (row.quadAccommodation || 0).toString(),
                (row.studioAccommodation || 0).toString(),
                (row.gst || 0).toString(),
                (row.securityDeposit || 0).toString(),
                (row.totalAmount || 0).toString()
            ];
            csv += values.join(',') + '\n';
        });

        return csv;
    }

    /**
     * Generate CSV with error messages
     */
    generateCSVWithErrors(rows) {
        if (rows.length === 0) return '';

        // Headers
        const headers = [
            'S.No',
            'Student ID',
            'BPID',
            'Cohort',
            'First Name',
            'Last Name',
            'Full Name',
            'Tuition Fee',
            'Quad Accommodation',
            'Studio Accommodation',
            'GST',
            'Security Deposit',
            'Total Amount',
            'Error Message'
        ];

        // Build CSV
        let csv = headers.join(',') + '\n';

        rows.forEach((row, index) => {
            const values = [
                (index + 1).toString(),
                this.escapeCsv(row.studentId),
                this.escapeCsv(row.bpid),
                this.escapeCsv(row.cohort),
                this.escapeCsv(row.firstName),
                this.escapeCsv(row.lastName),
                this.escapeCsv(row.fullName),
                (row.tuitionFee || 0).toString(),
                (row.quadAccommodation || 0).toString(),
                (row.studioAccommodation || 0).toString(),
                (row.gst || 0).toString(),
                (row.securityDeposit || 0).toString(),
                (row.totalAmount || 0).toString(),
                this.escapeCsv(row.errorMessage)
            ];
            csv += values.join(',') + '\n';
        });

        return csv;
    }

    /**
     * Escape CSV values
     */
    escapeCsv(value) {
        if (!value) return '';
        const stringValue = String(value);
        if (stringValue.includes(',') || stringValue.includes('"') || stringValue.includes('\n')) {
            return '"' + stringValue.replace(/"/g, '""') + '"';
        }
        return stringValue;
    }

    /**
     * Download file
     */
    downloadFile(content, filename) {
        const element = document.createElement('a');
        element.setAttribute('href', 'data:text/csv;charset=utf-8,' + encodeURIComponent(content));
        element.setAttribute('download', filename);
        element.style.display = 'none';
        document.body.appendChild(element);
        element.click();
        document.body.removeChild(element);
    }

    /**
     * Reset
     */
    handleReset() {
        this.fileData = null;
        this.processResult = null;
        this.totalRowsInFile = 0;
    }

    /**
     * Finish
     */
    handleFinish() {
        this.dispatchEvent(new CloseActionScreenEvent());
        setTimeout(() => window.location.reload(), 500);
    }

    /**
     * Show toast
     */
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}