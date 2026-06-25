import { LightningElement } from 'lwc';

// Mock Apex method
jest.mock('@salesforce/apex/UploadInstallmentPaymentsController.processPaymentUpload', () => {
    return jest.fn().mockResolvedValue({
        isSuccess: true,
        totalProcessed: 1,
        successCount: 1,
        errorCount: 0,
        errorMessages: [],
        warnings: []
    });
}, { virtual: true });

import UploadInstallmentPayments from 'c/uploadInstallmentPayments';

describe('Upload Installment Payments - File Upload Tests', () => {
    let element;

    beforeEach(() => {
        // Create element directly
        element = new UploadInstallmentPayments();
    });

    afterEach(() => {
        element = null;
    });

    describe('handleFileUpload', () => {
        it('should handle CSV file correctly', () => {
            // Create a mock CSV file
            const csvContent = 'Student ID,BPID,Cohort,First Name,Last Name,Admission Fee\n123,BP001,2024,John,Doe,5000';
            const csvFile = new File([csvContent], 'test.csv', { type: 'text/csv' });
            
            // Create mock event
            const event = {
                target: {
                    files: [csvFile]
                }
            };

            // Call the handler
            element.handleFileUpload(event);
            
            // Verify file was processed
            return new Promise(resolve => {
                setTimeout(() => {
                    expect(element.fileData).toBeTruthy();
                    expect(element.totalRowsInFile).toBeGreaterThan(0);
                    resolve();
                }, 200);
            });
        });

        it('should handle empty file selection', () => {
            const event = {
                target: {
                    files: []
                }
            };

            element.handleFileUpload(event);
            
            expect(element.fileData).toBeNull();
        });

        it('should reject non-CSV/Excel files', () => {
            const txtFile = new File(['test content'], 'test.txt', { type: 'text/plain' });
            
            const event = {
                target: {
                    files: [txtFile]
                }
            };

            element.handleFileUpload(event);
            
            expect(element.fileData).toBeNull();
        });
    });

    describe('parseCSVFile', () => {
        it('should correctly parse valid CSV content', (done) => {
            const csvContent = 'Student ID,BPID,Cohort\n123,BP001,2024\n124,BP002,2024';
            const csvFile = new File([csvContent], 'test.csv', { type: 'text/csv' });

            element.parseCSVFile(csvFile);

            // Wait for FileReader to complete
            setTimeout(() => {
                expect(element.fileData.length).toBe(2);
                expect(element.fileData[0].studentId).toBe('123');
                done();
            }, 200);
        });

        it('should handle empty CSV file', (done) => {
            const csvFile = new File([''], 'empty.csv', { type: 'text/csv' });

            element.parseCSVFile(csvFile);

            setTimeout(() => {
                expect(element.fileData.length).toBe(0);
                done();
            }, 200);
        });

        it('should reject invalid file object', () => {
            const invalidFile = { name: 'test.csv' }; // Not a Blob
            
            expect(() => {
                element.parseCSVFile(invalidFile);
            }).toThrow();
        });
    });

    describe('csvToArray', () => {
        it('should correctly parse CSV with headers', () => {
            const csv = 'Student ID,First Name,Admission Fee\n123,John,5000\n124,Jane,6000';
            
            const result = element.csvToArray(csv);
            
            expect(result.length).toBe(2);
            expect(result[0].studentId).toBe('123');
            expect(result[0].firstName).toBe('John');
        });

        it('should handle case-insensitive headers', () => {
            const csv = 'STUDENT ID,first NAME,admission FEE\n123,John,5000';
            
            const result = element.csvToArray(csv);
            
            expect(result.length).toBe(1);
            expect(result[0].studentId).toBe('123');
        });

        it('should skip empty rows', () => {
            const csv = 'Student ID,First Name\n123,John\n\n124,Jane';
            
            const result = element.csvToArray(csv);
            
            expect(result.length).toBe(2);
        });

        it('should parse decimal values correctly', () => {
            const csv = 'Student ID,Admission Fee,GST\n123,5000.50,500.25';
            
            const result = element.csvToArray(csv);
            
            expect(result[0].admissionFee).toBe(5000.50);
            expect(result[0].gst).toBe(500.25);
        });
    });
});