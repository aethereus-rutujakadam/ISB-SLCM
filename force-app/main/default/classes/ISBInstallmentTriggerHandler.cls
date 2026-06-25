public class ISBInstallmentTriggerHandler {
    
private static Boolean gstAlreadyRun = false;
    public static void afterUpdate(
        List<ISB_Installment__c> newList,
        Map<Id, ISB_Installment__c> oldMap
    ) {
        System.debug('=== ISBInstallmentTriggerHandler.afterUpdate START ===');

        List<ISB_Installment__c> newlyPaidInstallments = new List<ISB_Installment__c>();

        for (ISB_Installment__c inst : newList) {
            ISB_Installment__c oldInst = oldMap.get(inst.Id);

            if (inst.Installment_Status__c == 'Paid'
                && oldInst.Installment_Status__c != 'Paid') {

                System.debug('✅ Installment moved to PAID: ' + inst.Id);
                newlyPaidInstallments.add(inst);
            }
        }

        if (!newlyPaidInstallments.isEmpty()) {
            createFees(newlyPaidInstallments);
        }

        System.debug('=== ISBInstallmentTriggerHandler.afterUpdate END ===');
    }
    private static void createFees(List<ISB_Installment__c> installments) {

    System.debug('=== createFees START ===');

    Set<Id> programEnrollmentIds = new Set<Id>();
    for (ISB_Installment__c i : installments) {
        if (i.Program_Enrollment__c != null) {
            programEnrollmentIds.add(i.Program_Enrollment__c);
        }
    }

    // 🔒 Fetch existing Installment Fees
    Map<String, ISB_Fee__c> existingFeesMap = new Map<String, ISB_Fee__c>();

    for (ISB_Fee__c fee : [
        SELECT Id, Program_Enrollment__c, Fee_Type__c
        FROM ISB_Fee__c
        WHERE Program_Enrollment__c IN :programEnrollmentIds
        AND Fee_Type__c LIKE 'Installment%'
    ]) {
        String key = fee.Program_Enrollment__c + '-' + fee.Fee_Type__c;
        existingFeesMap.put(key, fee);
    }

    List<ISB_Fee__c> feesToInsert = new List<ISB_Fee__c>();

    for (ISB_Installment__c inst : installments) {

        if (inst.Program_Enrollment__c == null/* || inst.Installment_Number__c == null*/) {
            System.debug('❌ Missing Program Enrollment or Installment Number');
            continue;
        }

        String feeType = 'Installment '/* + inst.Installment_Number__c*/;
        String key = inst.Program_Enrollment__c + '-' + feeType;

        if (existingFeesMap.containsKey(key)) {
            System.debug('⚠️ Fee already exists: ' + feeType);
            continue;
        }

        ISB_Fee__c fee = new ISB_Fee__c();
        fee.Program_Enrollment__c = inst.Program_Enrollment__c;
        fee.Fee_Type__c = feeType;
        fee.Total_amount__c = inst.Total_Amount_calc__c;
        fee.Customer__c = inst.Contact__c;
        fee.Contact__c = inst.Contact__c;
        fee.Fee_Amount__c = inst.Total_Amount_calc__c;

        feesToInsert.add(fee);

        System.debug('🧾 Prepared ISB Fee: ' + feeType);
    }

    if (!feesToInsert.isEmpty()) {
        insert feesToInsert;
        System.debug('✅ ISB Fees Created: ' + feesToInsert.size());
    }

    System.debug('=== createFees END ===');
}

/* public static void createGSTRecords(
    List<ISB_Installment__c> newList,
    Map<Id, ISB_Installment__c> oldMap
) {

    System.debug('=== createGSTRecords START ===');

    // ️ Prevent recursion in same transaction
    if (gstAlreadyRun) {
        System.debug(' GST creation already executed. Skipping.');
        return;
    }
    gstAlreadyRun = true;

    if (newList == null || newList.isEmpty()) {
        return;
    }

    System.debug('Processing ' + newList.size() + ' installments for GST creation');

    // ----------------------------------------------------
    // Step 1: Collect Program Enrollment IDs
    // ----------------------------------------------------
    Set<Id> programEnrollmentIds = new Set<Id>();

    for (ISB_Installment__c inst : newList) {
        if (inst.Program_Enrollment__c != null) {
            programEnrollmentIds.add(inst.Program_Enrollment__c);
        }
    }

    if (programEnrollmentIds.isEmpty()) {
        System.debug('⚠️ No Program Enrollments found');
        return;
    }

    // ----------------------------------------------------
    // Step 2: Query Program Enrollments
    // ----------------------------------------------------
    Map<Id, ProgramEnrollment> peMap = new Map<Id, ProgramEnrollment>(
        [
            SELECT Id, Group_Id__c
            FROM ProgramEnrollment
            WHERE Id IN :programEnrollmentIds
        ]
    );

    System.debug('📊 Found ' + peMap.size() + ' Program Enrollments');

    // ----------------------------------------------------
    // Step 3: Create GST Breakage Records
    // ----------------------------------------------------
    List<ISB_Student_Fee_Breakage__c> gstRecordsToInsert =
        new List<ISB_Student_Fee_Breakage__c>();

    for (ISB_Installment__c inst : newList) {

        if (inst.Program_Enrollment__c == null) {
            continue;
        }

        ProgramEnrollment pe = peMap.get(inst.Program_Enrollment__c);

        if (pe == null) {
            continue;
        }

        String groupId = pe.Group_Id__c;

        if (groupId == 'G006' || groupId == 'G001') {

            ISB_Student_Fee_Breakage__c cgst = new ISB_Student_Fee_Breakage__c();
            cgst.ISB_Installment__c = inst.Id;
            cgst.Fee_Type__c = 'CGST';
            cgst.Amount__c = 0;
            gstRecordsToInsert.add(cgst);

            ISB_Student_Fee_Breakage__c sgst = new ISB_Student_Fee_Breakage__c();
            sgst.ISB_Installment__c = inst.Id;
            sgst.Fee_Type__c = 'SGST';
            sgst.Amount__c = 0;
            gstRecordsToInsert.add(sgst);

        } else if (groupId == 'G008' || groupId == 'G009') {

            ISB_Student_Fee_Breakage__c igst = new ISB_Student_Fee_Breakage__c();
            igst.ISB_Installment__c = inst.Id;
            igst.Fee_Type__c = 'IGST';
            igst.Amount__c = 0;
            gstRecordsToInsert.add(igst);

        }
    }

    // ----------------------------------------------------
    // Step 4: Insert GST Records
    // ----------------------------------------------------
    if (!gstRecordsToInsert.isEmpty()) {
        try {
            insert gstRecordsToInsert;
            System.debug('✅ Inserted ' + gstRecordsToInsert.size() + ' GST breakage records');
        } catch (Exception e) {
            System.debug('❌ Error inserting GST records: ' + e.getMessage());
            System.debug('Stack Trace: ' + e.getStackTraceString());
        }
    }

    System.debug('=== createGSTRecords END ===');
}*/
    
public static void syncInstallmentsToISBFees(List<ISB_Installment__c> installments) {
    try {
        if (installments == null || installments.isEmpty()) {
            return;
        }
        
        Set<Id> installmentIds = new Set<Id>();
        Map<Id, ISB_Installment__c> installmentMap = new Map<Id, ISB_Installment__c>();
        
        for (ISB_Installment__c inst : installments) {
            installmentIds.add(inst.Id);
            installmentMap.put(inst.Id, inst);
        }
        
        // Query existing ISB Fee records linked to these installments
        Map<Id, ISB_Fee__c> installmentToFeeMap = new Map<Id, ISB_Fee__c>();
        
        for (ISB_Fee__c fee : [
            SELECT Id, ISB_Installment__c, Program_Enrollment__c, Customer__c, 
                   Total_amount__c, Due_Date__c, Extended_Due_Date__c,
                   Paid_Amount__c, Pending_Amount__c, Fee_Status__c,
                   Fee_Type__c, Is_Active__c
            FROM ISB_Fee__c
            WHERE ISB_Installment__c IN :installmentIds
            AND (Fee_Type__c LIKE 'Installment%' OR Fee_Type__c = 'Single Installment')
        ]) {
            installmentToFeeMap.put(fee.ISB_Installment__c, fee);
        }
        
        System.debug('Found ' + installmentToFeeMap.size() + ' existing ISB Fee records');
        
        // Lists for DML operations
        List<ISB_Fee__c> feesToInsert = new List<ISB_Fee__c>();
        List<ISB_Fee__c> feesToUpdate = new List<ISB_Fee__c>();
        
        // Process each installment
        for (ISB_Installment__c inst : installments) {
            ISB_Fee__c fee = installmentToFeeMap.get(inst.Id);
            
            if (fee == null) {
                // Create new ISB Fee record
                fee = new ISB_Fee__c();
                fee.ISB_Installment__c = inst.Id;
                fee.Program_Enrollment__c = inst.Program_Enrollment__c;
                fee.Contact__c = inst.Contact__c;
                fee.Customer__c = inst.Contact__c;
                
                feesToInsert.add(fee);
                System.debug('Creating new ISB Fee for Installment: ' + inst.Id);
            } else {
                // Update existing record
                feesToUpdate.add(fee);
                System.debug('Updating existing ISB Fee: ' + fee.Id);
            }
            
            
            
              // ✅ SET FEE TYPE DYNAMICALLY BASED ON INSTALLMENT NUMBER
                if (String.isNotBlank(inst.Installment_Number__c)) {
                    if (inst.Installment_Number__c == 'Single') {
                        fee.Fee_Type__c = 'Single Installment';
                        System.debug('Setting Fee_Type__c to: Installment (Single payment)');
                    } else {
                        fee.Fee_Type__c = 'Installment ' + inst.Installment_Number__c;
                        System.debug('Setting Fee_Type__c to: ' + fee.Fee_Type__c);
                    }
                } else {
                    fee.Fee_Type__c = 'Installment';
                    System.debug('⚠️ Installment Number is blank, defaulting to "Installment"');
                }
            
            // Map fields from Installment to Fee (both new and existing)
            fee.Total_amount__c = inst.Total_Amount_calc__c;
            fee.Due_Date__c = inst.Due_Date__c;
            fee.Extended_Due_Date__c = inst.Extended_Due_Date__c;
            fee.Paid_Amount__c = inst.Paid_Amount__c;
            fee.Pending_Amount__c = inst.Pending_Amount__c;
            fee.Fee_Status__c = inst.Installment_Status__c;
            fee.Fee_Amount__c = inst.Total_Amount__c;
            fee.Is_Active__c = inst.Is_Active__c; 
        }
        
        // Insert new records
        if (!feesToInsert.isEmpty()) {
            Database.SaveResult[] insertResults = Database.insert(feesToInsert, false);
            
            for (Integer i = 0; i < insertResults.size(); i++) {
                if (!insertResults[i].isSuccess()) {
                    ISB_Fee__c failedFee = feesToInsert[i];
                    String errorDetails = 'Failed to insert ISB Fee for Installment: ' + failedFee.ISB_Installment__c;
                    
                    for (Database.Error err : insertResults[i].getErrors()) {
                        errorDetails += '\nError: ' + err.getMessage();
                    }
                    System.debug(errorDetails);
                } else {
                    System.debug('✅ Successfully created ISB Fee: ' + insertResults[i].getId());
                }
            }
        }
        
        // Update existing records
        if (!feesToUpdate.isEmpty()) {
            Database.SaveResult[] updateResults = Database.update(feesToUpdate, false);
            
            for (Integer i = 0; i < updateResults.size(); i++) {
                if (!updateResults[i].isSuccess()) {
                    ISB_Fee__c failedFee = feesToUpdate[i];
                    String errorDetails = 'Failed to update ISB Fee: ' + failedFee.Id;
                    
                    for (Database.Error err : updateResults[i].getErrors()) {
                        errorDetails += '\nError: ' + err.getMessage();
                    }
                    System.debug(errorDetails);
                } else {
                    System.debug('✅ Successfully updated ISB Fee: ' + updateResults[i].getId());
                }
            }
        }
        
        System.debug('Sync complete - Inserted: ' + feesToInsert.size() + ', Updated: ' + feesToUpdate.size());
        
    } catch (Exception e) {
       System.debug('❌ Exception: ' + e.getMessage() + ' Line number: ' + e.getLineNumber());
    }
}

}