public with sharing class UploadInstallmentPaymentsController {
//Inser payment sap true 
//Case creation on success
// verify ISB Installments ,ISB Fees ,PE status Update, enrollment session creation and ORG A Status check
   
    public class PaymentRow {
        public Integer rowNumber { get; set; }
        public String studentId { get; set; }
        public String bpid { get; set; }
        public String cohort { get; set; }
        public String firstName { get; set; }
        public String lastName { get; set; }
        public String fullName { get; set; }
        public Decimal tuitionFee { get; set; }
        public Decimal quadAccommodation { get; set; }
        public Decimal studioAccommodation { get; set; }
        public Decimal gst { get; set; }
        public Decimal securityDeposit { get; set; }
        public Decimal totalAmount { get; set; }
    }

    public class ProcessResult {
        @AuraEnabled
        public Boolean isSuccess { get; set; }
        @AuraEnabled
        public Integer totalProcessed { get; set; }
        @AuraEnabled
        public Integer successCount { get; set; }
        @AuraEnabled
        public Integer errorCount { get; set; }
        @AuraEnabled
        public List<String> errorMessages { get; set; }
        @AuraEnabled
        public List<String> warnings { get; set; }
    }



    /**
     * Process uploaded payment data from CSV/Excel
     * @param paymentDataJson - JSON string of payment records
     * @return ProcessResult with success/error details
     */
    @AuraEnabled(cacheable=false)
    public static ProcessResult processPaymentUpload(String paymentDataJson) {
        ProcessResult result = new ProcessResult();
        result.errorMessages = new List<String>();
        result.warnings = new List<String>();
        result.successCount = 0;
        result.errorCount = 0;
        result.totalProcessed = 0;
        result.isSuccess = true;

        System.debug('=== APEX: processPaymentUpload called ===');

        if (String.isBlank(paymentDataJson)) {
            System.debug('❌ paymentDataJson is blank!');
            result.isSuccess = false;
            result.errorMessages.add('No payment data provided');
            return result;
        }

        List<PaymentRow> paymentData;
        try {
            System.debug('Attempting to deserialize...');
            paymentData = (List<PaymentRow>) JSON.deserialize(paymentDataJson, List<PaymentRow>.class);
            System.debug('✅ Deserialized paymentData: ' + paymentData);
            System.debug('paymentData size: ' + paymentData.size());
        } catch (Exception ex) {
            System.debug('❌ DESERIALIZATION ERROR: ' + ex.getMessage());
            System.debug('Stack: ' + ex.getStackTraceString());
            result.isSuccess = false;
            result.totalProcessed = 0;
            result.errorMessages.add('Error deserializing payment data: ' + ex.getMessage());
            return result;
        }

        if (paymentData == null || paymentData.isEmpty()) {
            System.debug('❌ paymentData is null or empty!');
            result.isSuccess = false;
            result.totalProcessed = 0;
            result.errorMessages.add('No payment data provided');
            return result;
        }

        result.totalProcessed = paymentData.size();
        System.debug('✅ Set totalProcessed = ' + result.totalProcessed);

        // Map of PGID to Program Enrollment records
        Map<String, ProgramEnrollment> enrollmentMap = new Map<String, ProgramEnrollment>();
        Set<String> studentIds = new Set<String>();

        for (PaymentRow row : paymentData) {
            if (String.isNotBlank(row.studentId)) {
                studentIds.add(row.studentId);
                System.debug('Added studentId: ' + row.studentId);
            }
        }

        System.debug('✅ Total unique studentIds to query: ' + studentIds.size());
        System.debug('studentIds set: ' + studentIds);

        // Query Program Enrollments by PGID__c
        try {
            System.debug('🔵 Starting ProgramEnrollment query with WHERE PGID__c IN :studentIds');
            List<ProgramEnrollment> enrollments = [
                SELECT Id, ContactId, ISB_Fee_Amount__c, 
                       Academic_Term__c, Learning_Program__c, Location__c, ISB_Fee_Payment_Installments__c, PGID__c
                FROM ProgramEnrollment
                WHERE PGID__c IN :studentIds
                LIMIT 1000
            ];
            
            System.debug('✅ Query returned ' + enrollments.size() + ' records');

            for (ProgramEnrollment pe : enrollments) {
                System.debug('Found PE: Id=' + pe.Id + ', PGID=' + pe.PGID__c + ', ContactId=' + pe.ContactId);
                if (pe.PGID__c != null) {
                    enrollmentMap.put(pe.PGID__c, pe);
                }
            }

            // Warn if no enrollments found
            if (enrollmentMap.isEmpty() && !studentIds.isEmpty()) {
                System.debug('⚠️  WARNING: No Program Enrollment records found for studentIds: ' + studentIds);
                result.warnings.add(
                    'No Program Enrollment records found. ' + studentIds.size() + 
                    ' Student ID(s) were provided but none match existing PGID__c values in the system. ' +
                    'Student IDs searched: ' + String.join(new List<String>(studentIds), ', ')
                );
            }

        } catch (Exception ex) {
            System.debug('❌ QUERY ERROR: ' + ex.getMessage());
            System.debug('Stack: ' + ex.getStackTraceString());
            result.isSuccess = false;
            result.errorMessages.add('Error querying Program Enrollment: ' + ex.getMessage());
            return result;
        }

        List<ISB_Student_Fee_Breakage__c> breakagesToUpsert = new List<ISB_Student_Fee_Breakage__c>();
        List<ISB_Installment__c> installmentsToUpdate = new List<ISB_Installment__c>();
        List<ISB_Installment__c> completedInstallments = new List<ISB_Installment__c>();

        // Process each payment row
        Integer rowNum = 1;
        for (PaymentRow row : paymentData) {
            try {
                if (String.isBlank(row.studentId)) {
                    result.errorCount++;
                    result.errorMessages.add('Row ' + rowNum + ': Student ID is empty. All rows must have a Student ID.');
                    rowNum++;
                    continue;
                }

                System.debug('Row ' + rowNum + ': Looking up Student ID = "' + row.studentId + '"');
                ProgramEnrollment enrollment = enrollmentMap.get(row.studentId);
                
                if (enrollment == null) {
                    System.debug('❌ Row ' + rowNum + ': No enrollment found for studentId="' + row.studentId + '"');
                    System.debug('Available enrollmentMap keys: ' + enrollmentMap.keySet());
                    result.errorCount++;
                    String displayName = String.isNotBlank(row.fullName) ? row.fullName : (row.firstName + ' ' + row.lastName);
                    result.errorMessages.add(
                        'Row ' + rowNum + ' (Student ID: "' + row.studentId + '"): ' +
                        'No Program Enrollment record found with PGID__c matching this Student ID. ' +
                        'Please verify the Student ID in your upload file matches PGID__c in Program Enrollment records. ' +
                        'Name: ' + displayName
                    );
                    rowNum++;
                    continue;
                }

                System.debug('✅ Row ' + rowNum + ': Found enrollment PE Id=' + enrollment.Id);
                // Validate and update fees
                validateAndMapFees(row, enrollment, breakagesToUpsert, installmentsToUpdate, completedInstallments, result, rowNum);
                result.successCount++;

            } catch (Exception ex) {
                result.errorCount++;
                String lastNameStr = row.lastName != null ? row.lastName : '';
                String firstNameStr = String.isNotBlank(row.firstName) ? (row.firstName + ' ' + lastNameStr) : '';
                String studentName = String.isNotBlank(row.fullName) ? row.fullName : firstNameStr;
                result.errorMessages.add(
                    'Row ' + rowNum + ' (Student ID: ' + row.studentId + ', Name: ' + studentName + '): ' + 
                    'Error processing payment: ' + ex.getMessage()
                );
            }

            rowNum++;
        }

        // Update/Insert breakage records
        if (!breakagesToUpsert.isEmpty()) {
            try {
                upsert breakagesToUpsert;
            } catch (Exception ex) {
                result.errorMessages.add(
                    'Error updating fee breakages: ' + ex.getMessage() + 
                    '. ' + breakagesToUpsert.size() + ' breakage record(s) could not be saved. ' +
                    'Please check field permissions and data validation rules.'
                );
                result.isSuccess = false;
                return result;
            }
        }

        if (!installmentsToUpdate.isEmpty()) {
            try {
                update installmentsToUpdate;
            } catch (Exception ex) {
                result.errorMessages.add(
                    'Error updating ISB_Installment__c records: ' + ex.getMessage() + 
                    '. ' + installmentsToUpdate.size() + ' installment record(s) could not be saved. ' +
                    'Please check field permissions and data validation rules.'
                );
                result.isSuccess = false;
                return result;
            }
        }

        // Process completed installments - Create Enrollment Sessions for SAP Payments
        System.debug('completedInstallments count: ' + completedInstallments.size());
        if (!completedInstallments.isEmpty()) {
            System.debug('🔵 SAP: Processing ' + completedInstallments.size() + ' completed installment(s) for enrollment sessions...');
            try {
                // Process each completed installment
                for (ISB_Installment__c inst : completedInstallments) {
                    System.debug('✅ SAP PROCESSING: Creating enrollment sessions for Installment ID=' + inst.Id);
                    
                    // Find the Program Enrollment for this installment
                    List<ISB_Fee__c> fees = [
                        SELECT Id, Program_Enrollment__c
                        FROM ISB_Fee__c
                        WHERE ISB_Installment__c = :inst.Id
                        LIMIT 1
                    ];
                    
                    if (!fees.isEmpty()) {
                        processInstallmentForSAP(inst.Id, fees[0].Program_Enrollment__c);
                    }
                }
                System.debug('✅ SAP: Successfully processed ' + completedInstallments.size() + ' installments');
            } catch (Exception ex) {
                result.warnings.add(
                    'Note: Fees were processed successfully (' + result.successCount + ' records), but ' +
                    'some enrollment sessions may not have been created. ' +
                    'Details: ' + ex.getMessage()
                );
                System.debug('⚠️ Warning: ' + ex.getMessage());
            }
        } else {
            System.debug('⏳ NO COMPLETED INSTALLMENTS: No records were uploaded.');
        }



        result.isSuccess = result.errorCount == 0;
        System.debug('=== APEX: Final Result ===');
        System.debug('Result object: ' + JSON.serialize(result));
        System.debug('isSuccess: ' + result.isSuccess);
        System.debug('totalProcessed: ' + result.totalProcessed);
        System.debug('successCount: ' + result.successCount);
        System.debug('errorCount: ' + result.errorCount);
        System.debug('errorMessages count: ' + result.errorMessages.size());
        System.debug('warnings count: ' + result.warnings.size());
        return result;
    }

    /**
     * Validate payment amounts and map to ISB_Student_Fee_Breakage__c records
     */
    private static void validateAndMapFees(
        PaymentRow row,
        ProgramEnrollment enrollment,
        List<ISB_Student_Fee_Breakage__c> breakagesToUpsert,
        List<ISB_Installment__c> installmentsToUpdate,
        List<ISB_Installment__c> completedInstallments,
        ProcessResult result,
        Integer rowNum
    ) {
        // Determine target installment number
        String targetInstallmentNumber = getInstallmentNumber(enrollment);
        System.debug('Row ' + rowNum + ': targetInstallmentNumber = ' + targetInstallmentNumber);

        // Query ISB_Installment with breakage records
        // ✅ FIXED: Accept both '1' and 'Single' to handle all installment formats
        List<ISB_Installment__c> installments = [
            SELECT Id, Contact__c, Installment_Number__c, Paid_Amount__c, Pending_Amount__c, 
                   Installment_Status__c, Total_Amount__c
            FROM ISB_Installment__c
            WHERE Contact__c = :enrollment.ContactId 
            AND Installment_Number__c IN ('1', 'Single')
            LIMIT 1
        ];

        if (installments.isEmpty()) {
            result.errorCount++;
            result.errorMessages.add(
                'Row ' + rowNum + ' (Student: ' + row.fullName + '): ' +
                'No ISB_Installment found with Installment_Number = ' + targetInstallmentNumber
            );
            return;
        }

        ISB_Installment__c installment = installments[0];

        // Query existing breakage records for this installment
        List<ISB_Student_Fee_Breakage__c> existingBreakagesList = [
            SELECT Id, Fee_Type__c, Amount__c
            FROM ISB_Student_Fee_Breakage__c
            WHERE ISB_Installment__c = :installment.Id
        ];

        // Map of fee types to amounts from CSV
        Map<String, Decimal> paymentMap = new Map<String, Decimal>();
        paymentMap.put('Tuition Fee', row.tuitionFee);
        paymentMap.put('Accommodation Shared', row.quadAccommodation);
        paymentMap.put('Accommodation Studio', row.studioAccommodation);
        paymentMap.put('CGST', row.gst);
        paymentMap.put('SGST', row.gst);
        paymentMap.put('IGST', row.gst);
        paymentMap.put('Security Deposit', row.securityDeposit);

        // Map existing breakage records by fee type
        Map<String, ISB_Student_Fee_Breakage__c> existingBreakages = new Map<String, ISB_Student_Fee_Breakage__c>();
        for (ISB_Student_Fee_Breakage__c breakage : existingBreakagesList) {
            existingBreakages.put(breakage.Fee_Type__c, breakage);
        }

        // Use totalAmount from Excel as the paid amount (this is what was paid in SAP)
        Decimal totalPaid = (row.totalAmount != null && row.totalAmount > 0) ? row.totalAmount : 0;
        System.debug('Row ' + rowNum + ': Using totalAmount from Excel: ' + totalPaid);

        // Update or create breakage records for individual fees if provided
        for (String feeType : paymentMap.keySet()) {
            Decimal amount = paymentMap.get(feeType);

            // Skip zero, null, or negative amounts
            if (amount == null || amount <= 0) {
                System.debug('  Skipping ' + feeType + ': amount=' + amount);
                continue;
            }

            ISB_Student_Fee_Breakage__c breakage = existingBreakages.get(feeType);
            if (breakage == null) {
                breakage = new ISB_Student_Fee_Breakage__c();
                breakage.ISB_Installment__c = installment.Id;
                breakage.Fee_Type__c = feeType;
            }

            breakage.Amount__c = amount;
            breakagesToUpsert.add(breakage);

            System.debug('Breakage: ' + feeType + ' = ' + amount);
        }

        // Update installment paid amount
        installment.Paid_Amount__c = totalPaid;
        installment.Pending_Amount__c = (installment.Total_Amount__c != null ? installment.Total_Amount__c : 0.0) - totalPaid;
        
        System.debug('Row ' + rowNum + ': Payment Summary - Total_Amount__c=' + installment.Total_Amount__c + ', totalPaid=' + totalPaid + ', Pending=' + installment.Pending_Amount__c);
        
        // ✅ ALWAYS MARK AS PAID FOR SAP (NO PARTIAL CHECK)
        installment.Installment_Status__c = 'Paid';
        completedInstallments.add(installment);
        installmentsToUpdate.add(installment);
        
        System.debug('Row ' + rowNum + ': ✅ Installment marked as PAID (SAP) - Enrollment sessions will be created');
        System.debug('Row ' + rowNum + ': Total paid = ' + totalPaid);
        
        // ✅ NEW: CREATE ISB_PAYMENT__C + CASE + PROCESS ENROLLMENT
        try {
            // 1️⃣ Create ISB_Payment record with SAP_Payment_Collected__c = true
            ISB_Payment__c payment = createPaymentRecord(
                enrollment.ContactId,
                null,  // We'll create case with payment reference
                installment.Id,
                totalPaid,
                row,
                enrollment.Id,  // Program Enrollment ID
                targetInstallmentNumber  // Installment Number
            );
            
            // 2️⃣ Create Case for this payment
            Case paymentCase = createCaseForPayment(
                enrollment.ContactId,
                payment.Id,
                row,
                enrollment
            );
            
            System.debug('✅ Row ' + rowNum + ': Payment & Case created successfully (SAP_Payment_Collected = true)');
            
        } catch (Exception ex) {
            result.warnings.add(
                'Row ' + rowNum + ': Payment/Case creation warning: ' + ex.getMessage() + 
                ' But installment was marked as paid.'
            );
            System.debug('⚠️ Warning: ' + ex.getMessage());
        }
    }

    /**
     * Determine installment number based on ISB_Fee_Payment_Installments__c field
     * Maps values:
     * - "One Installment" or "1" → 'Single'
     * - "Two Installments" or "2" → '1'
     */
    public static String getInstallmentNumber(ProgramEnrollment enrollment) {
        try {
            String installmentField = String.valueOf(enrollment.ISB_Fee_Payment_Installments__c);
            
            if (String.isBlank(installmentField) || installmentField == 'null') {
                return '1';
            }

            // Check for "One Installment" text value (for PGP, PGPYL, etc.)
            if (installmentField.containsIgnoreCase('One Installment')) {
                System.debug('Detected: One Installment → returning Single');
                return 'Single';
            }

            // Check for "Two Installments" text value
            if (installmentField.containsIgnoreCase('Two Installments')) {
                System.debug('Detected: Two Installments → returning 1');
                return '1';
            }

            // Handle numeric values
            if (installmentField.isNumeric()) {
                Integer num = Integer.valueOf(installmentField);
                return (num == 1) ? 'Single' : '1';
            }

            // Legacy: Handle text values like 'single' or 'one'
            if (installmentField.containsIgnoreCase('single') || installmentField.containsIgnoreCase('one')) {
                return 'Single';
            }

            return '1';
        } catch (Exception ex) {
            System.debug('Error parsing installment: ' + ex.getMessage());
            return '1';
        }
    }

    /**
     * Parse CSV string into PaymentRow objects
     */
    public static List<PaymentRow> parseCSV(String csvContent) {
        List<PaymentRow> rows = new List<PaymentRow>();
        List<String> lines = csvContent.split('\n');

        if (lines.isEmpty()) {
            return rows;
        }

        // Skip header row
        for (Integer i = 1; i < lines.size(); i++) {
            String line = lines[i].trim();
            if (String.isBlank(line)) continue;

            try {
                List<String> values = line.split(',');
                // Columns: S.No, Student ID, BPID, Cohort, First Name, Last Name, Full name, 
                // Admission Fee (ignore), Commitment Fee (ignore), Tuition Fee, Tuition Waiver (ignore),
                // Quad Accommodation Fee, Studio Accommodation Fee, GST, Security Deposit, Total Amount
                if (values.size() >= 16) {
                    PaymentRow row = new PaymentRow();
                    row.rowNumber = i;
                    row.studentId = values[1].trim();
                    row.bpid = values[2].trim();
                    row.cohort = values[3].trim();
                    row.firstName = values[4].trim();
                    row.lastName = values[5].trim();
                    row.fullName = values[6].trim();
                    row.tuitionFee = parseDecimal(values[9]);
                    row.quadAccommodation = parseDecimal(values[11]);
                    row.studioAccommodation = parseDecimal(values[12]);
                    row.gst = parseDecimal(values[13]);
                    row.securityDeposit = parseDecimal(values[14]);
                    row.totalAmount = parseDecimal(values[15]);

                    rows.add(row);
                }
            } catch (Exception ex) {
                // Skip malformed rows
                continue;
            }
        }

        return rows;
    }

    /**
     * Safe decimal parsing
     */
    public static Decimal parseDecimal(String value) {
        try {
            return Decimal.valueOf(value.trim());
        } catch (Exception ex) {
            return 0;
        }
    }

    /**
     * CREATE ISB_PAYMENT__C RECORD WITH SAP_PAYMENT_COLLECTED__C = TRUE
     */
    public static ISB_Payment__c createPaymentRecord(
        Id contactId, 
        Id caseId, 
        Id installmentId, 
        Decimal amountPaid,
        PaymentRow row,
        Id programEnrollmentId,  // ✅ Program Enrollment Lookup
        String installmentNumber  // ✅ Installment Number (Single or 1)
    ) {
        ISB_Payment__c payment = new ISB_Payment__c();
        payment.Customer__c = contactId;
        payment.Case__c = caseId;
        payment.ISB_Installment__c = installmentId;
        payment.Amount__c = amountPaid;
        payment.Program_Enrollment__c = programEnrollmentId;  // ✅ LINK PROGRAM ENROLLMENT
        
        // ✅ SET PAYMENT_TYPE__C BASED ON INSTALLMENT NUMBER
        if (installmentNumber == 'Single') {
            payment.Payment_Type__c = 'Single Installment';
        } else {
            payment.Payment_Type__c = 'Installment 1';
        }
        
        // ✅ MARK FIRST INSTALLMENT AS PAID
        payment.First_Installment_Paid__c = true;
        
        //payment.Payment_Mode__c = 'SAP';  // SAP Payment
        payment.Initiated__c = 'Success';
        payment.SAP_Payment_Collected__c = true;  // ✅ MARK SAP PAYMENT COLLECTED
        payment.Transaction_Date__c = System.today();
        
        insert payment;
        System.debug('✅ ISB_Payment__c Created: ' + payment.Id + ' | Payment_Type = ' + payment.Payment_Type__c + ' | First_Installment_Paid = true');
        return payment;
    }

    /**
     * CREATE CASE FOR PAYMENT
     */
    public static Case createCaseForPayment(
        Id contactId,
        Id paymentId,
        PaymentRow row,
        ProgramEnrollment enrollment
    ) {
        Case caseRecord = new Case();
        caseRecord.ContactId = contactId;
        caseRecord.Type = 'Payment';
        caseRecord.Status = 'Closed';
        caseRecord.Subject = 'SAP Payment - ' + row.fullName + ' - Amount: ' + row.totalAmount;
        caseRecord.Description = 'Payment Collected from SAP\n' +
                                 'Student ID: ' + row.studentId + '\n' +
                                 'BPID: ' + row.bpid + '\n' +
                                 'Cohort: ' + row.cohort + '\n' +
                                 'Amount: ' + row.totalAmount + '\n' +
                                 'Payment Mode: SAP';
        
        insert caseRecord;
        System.debug('✅ Case Created: ' + caseRecord.Id);
        return caseRecord;
    }

    /**
     * CLONED: PROCESS INSTALLMENT FOR SAP (NO PARTIAL CHECK - ALWAYS MARK AS PAID)
     * Creates Enrollment Sessions after payment completion
     * Based on RazorpayController.processInstallmentFromMaster
     */
    public static void processInstallmentForSAP(Id installmentId, Id programEnrollmentId) {
        
        System.debug('================ START processInstallmentForSAP (SAP PAYMENTS) ================');
        System.debug('Input Installment Id: ' + installmentId);
        System.debug('Input Program Enrollment Id: ' + programEnrollmentId);
        
        if (installmentId == null || programEnrollmentId == null) {
            System.debug('⚠️ Installment ID or Program Enrollment ID is NULL. Exiting...');
            return;
        }
        
        // Query ISB_Fee__c with all related data (following RazorpayController pattern)
        List<ISB_Fee__c> fees = [
            SELECT Id,
                   Program_Enrollment__c,
                   Program_Enrollment__r.ContactId,
                   Program_Enrollment__r.Academic_Term__c,
                   Program_Enrollment__r.Location__c,
                   ISB_Installment__c,
                   ISB_Installment__r.Installment_Number__c
            FROM ISB_Fee__c
            WHERE ISB_Installment__c = :installmentId
            AND Program_Enrollment__c = :programEnrollmentId
            LIMIT 1
        ];
        
        if (fees.isEmpty()) {
            System.debug('⚠️ No ISB_Fee__c found for this installment and program enrollment. Exiting...');
            return;
        }
        
        ISB_Fee__c fee = fees[0];
        
        if (fee.Program_Enrollment__c == null || fee.Program_Enrollment__r.Academic_Term__c == null) {
            System.debug('⚠️ Program Enrollment or Academic Term is NULL. Exiting...');
            return;
        }
        
        if (fee.ISB_Installment__c == null || fee.ISB_Installment__r.Installment_Number__c == null) {
            System.debug('⚠️ Installment or Installment Number is NULL. Exiting...');
            return;
        }
        
        System.debug('✅ Installment paid (SAP). Proceeding with Enrollment Session creation.');
        
        Id peId = fee.Program_Enrollment__c;
        Id contactId = fee.Program_Enrollment__r.ContactId;
        Id academicTermId = fee.Program_Enrollment__r.Academic_Term__c;
        String installmentNumber = fee.ISB_Installment__r.Installment_Number__c;
        String enrollmentLocation = fee.Program_Enrollment__r.Location__c;
        
        System.debug('🔍 Contact ID: ' + contactId);
        System.debug('🔍 Program Enrollment Location: ' + enrollmentLocation);
        System.debug('🔍 Installment Number: ' + installmentNumber);
        
        // Fetch Fees Master
        List<ISB_Fees_Master__c> masters = [
            SELECT Id, 
                   Installment__c, 
                   Academic_Term__c
            FROM ISB_Fees_Master__c
            WHERE Academic_Term__c = :academicTermId
            AND Installment__c = :installmentNumber
            LIMIT 1
        ];
        
        if (masters.isEmpty()) {
            System.debug('⚠️ No ISB_Fees_Master__c found. Exiting...');
            return;
        }
        
        ISB_Fees_Master__c master = masters[0];
        
        // Fetch ISB_Eligible_Term__c records linked to this Fees Master
        List<ISB_Eligible_Term__c> eligibleTerms = [
            SELECT Id, 
                   Academic_Session__c, 
                   Academic_Session__r.Id,
                   Academic_Session__r.Name, 
                   Academic_Session__r.Location__c,
                   Academic_Session__r.From_Date__c, 
                   Academic_Session__r.To_date__c
            FROM ISB_Eligible_Term__c
            WHERE ISB_Fees_Master__c = :master.Id
            ORDER BY Sequence__c ASC
        ];
        
        if (eligibleTerms.isEmpty()) {
            System.debug('⚠️ No ISB_Eligible_Term__c records found. Exiting...');
            return;
        }
        
        System.debug('✅ Found ' + eligibleTerms.size() + ' eligible terms');
        
        // ✅ FILTER: Convert eligible terms to Academic Sessions matching Program Enrollment Location
        List<AcademicSession> sessionsForEnrollment = new List<AcademicSession>();
        
        for (ISB_Eligible_Term__c eligibleTerm : eligibleTerms) {
            AcademicSession acadSession = eligibleTerm.Academic_Session__r;
            
            System.debug('📌 Processing eligible term with session: ' + acadSession.Name + 
                        ' location: ' + acadSession.Location__c + 
                        ' (enrollment location: ' + enrollmentLocation + ')');
            
            // ✅ FILTER: Only include sessions where location matches Program Enrollment location
            if (acadSession.Location__c == enrollmentLocation) {
                System.debug('✅ Location MATCH: Adding session for enrollment');
                sessionsForEnrollment.add(acadSession);
            } else {
                System.debug('⚠️ Location MISMATCH: Skipping session (session location: ' + acadSession.Location__c + ', enrollment location: ' + enrollmentLocation + ')');
            }
        }
        
        if (sessionsForEnrollment.isEmpty()) {
            System.debug('⚠️ No Academic Sessions found matching Program Enrollment Location. Skipping Enrollment Session creation.');
            return;
        }
        
        System.debug('✅ Preparing to create ' + sessionsForEnrollment.size() + ' enrollment sessions');
        
        // Check Existing Enrollment Sessions (avoid duplicates)
        Set<Id> existingSessionIds = new Set<Id>();
        
        for (Enrollment_Session__c existing : [
            SELECT Id, Academic_Session__c
            FROM Enrollment_Session__c
            WHERE Program_Enrollment__c = :peId
        ]) {
            existingSessionIds.add(existing.Academic_Session__c);
        }
        
        // Prepare Sessions to Insert
        List<Enrollment_Session__c> sessionsToInsert = new List<Enrollment_Session__c>();
        
        for (AcademicSession sessionRec : sessionsForEnrollment) {
            
            if (existingSessionIds.contains(sessionRec.Id)) {
                System.debug('⚠️ Skipping duplicate session: ' + sessionRec.Id);
                continue;
            }
            
            Enrollment_Session__c rec = new Enrollment_Session__c();
            rec.Program_Enrollment__c = peId;
            rec.Academic_Session__c = sessionRec.Id;
            // ✅ Set Active__c = false initially to avoid trigger processing
            // Will be activated separately if needed
            rec.Active__c = false;
            rec.Assigned_Contact__c = contactId;
            rec.Session_Start__c = sessionRec.From_Date__c;
            rec.Session_End__c = sessionRec.To_date__c;
            
            sessionsToInsert.add(rec);
        }
        
        if (!sessionsToInsert.isEmpty()) {
            try {
                // Insert with allOrNone=false for partial success
                List<Database.SaveResult> results = Database.insert(sessionsToInsert, false);
                
                Integer successCount = 0;
                Integer failureCount = 0;
                List<Id> successfulSessionIds = new List<Id>();
                
                for (Database.SaveResult sr : results) {
                    if (sr.isSuccess()) {
                        successCount++;
                        successfulSessionIds.add(sr.getId());
                        System.debug('✅ Enrollment Session created: ' + sr.getId());
                    } else {
                        failureCount++;
                        for (Database.Error err : sr.getErrors()) {
                            System.debug('⚠️ Error creating enrollment session: ' + err.getMessage() + ' | Status Code: ' + err.getStatusCode());
                        }
                    }
                }
                
                System.debug('✅ Enrollment Sessions: ' + successCount + ' created, ' + failureCount + ' failed');
                
                // Now activate all successfully created sessions (Active__c = true)
                if (!successfulSessionIds.isEmpty()) {
                    List<Enrollment_Session__c> sessionsToActivate = [
                        SELECT Id FROM Enrollment_Session__c
                        WHERE Id IN :successfulSessionIds
                        AND Active__c = false
                    ];
                    
                    if (!sessionsToActivate.isEmpty()) {
                        for (Enrollment_Session__c es : sessionsToActivate) {
                            es.Active__c = true;
                        }
                        update sessionsToActivate;
                        System.debug('✅ Activated ' + sessionsToActivate.size() + ' enrollment sessions');
                    }
                }
                
            } catch (Exception ex) {
                System.debug('⚠️ Enrollment Session processing error (non-blocking): ' + ex.getMessage() + ' | Line: ' + ex.getLineNumber());
            }
        } else {
            System.debug('⚠️ No new Enrollment Sessions to insert.');
        }
        
        System.debug('================ END processInstallmentForSAP ================');
    }
}