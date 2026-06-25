global without sharing class ISBLateFeeBatch implements Database.Batchable<SObject>, Schedulable {
    
    // ---------------------------
    // START
    // ---------------------------
    global Database.QueryLocator start(Database.BatchableContext bc) {
        Date todayDt = System.today();
        return Database.getQueryLocator([
            SELECT Id,
            Due_Date__c,
            Extended_Due_Date__c,
            Pending_Amount__c,
            Fee_Type__c,
            Late_Fee_Added__c,
            Program_Enrollment__c,
            ISB_Installment__c,
            ISB_Installment__r.Installment_Number__c,
            Customer__c,  
            Total_amount__c,
            Contact__c,
            ISB_Installment__r.Late_Fee_Added__c,
            ISB_Installment__r.Pending_Amount__c,
            ISB_Installment__r.Total_Amount_calc__c
            FROM ISB_Fee__c
            WHERE (Fee_Type__c LIKE 'Installment%' OR Fee_Type__c = 'Single Installment')
            AND Pending_Amount__c > 0
            AND Late_Fee_Added__c = FALSE
            AND (
                (Extended_Due_Date__c != null AND Extended_Due_Date__c < :todayDt)
                OR (Extended_Due_Date__c = null AND Due_Date__c < :todayDt)
            )
        ]);
    }
    
    // ---------------------------
    // EXECUTE
    // ---------------------------
    global void execute(Database.BatchableContext bc, List<ISB_Fee__c> scope) {
        if (scope == null || scope.isEmpty()) return;
        
        List<ISB_Student_Fee_Breakage__c> lateFeeBreakagesToInsert = new List<ISB_Student_Fee_Breakage__c>();
        List<ISB_Fee__c> feesToUpdate = new List<ISB_Fee__c>();
        List<ISB_Installment__c> installmentsToUpdate = new List<ISB_Installment__c>();
        
        // Map to accumulate late fees per installment
        Map<Id, Decimal> installmentLateFeeMap = new Map<Id, Decimal>();
        Map<Id, ISB_Installment__c> installmentDataMap = new Map<Id, ISB_Installment__c>();
        
        for (ISB_Fee__c fee : scope) {
            if (fee.Pending_Amount__c == null || fee.Pending_Amount__c <= 0) continue;
            if (fee.ISB_Installment__c == null) {
                System.debug('⚠️ Fee has no Installment. Skipping: ' + fee.Id);
                continue;
            }
            
            Decimal lateFeeAmount;
            
            // Late fee calculation
            if (fee.ISB_Installment__r != null
                && fee.ISB_Installment__r.Installment_Number__c == '1') {
                    lateFeeAmount = 10000;
                } else {
                    // 1.5% of pending amount
                    lateFeeAmount = (fee.Pending_Amount__c * 1.5) / 100;
                }
            
            if (lateFeeAmount == null || lateFeeAmount <= 0) continue;
            
            System.debug('==========================================');
            System.debug('Processing Fee: ' + fee.Id);
            System.debug('Original Fee Pending Amount: ' + fee.Pending_Amount__c);
            System.debug('Late Fee Amount: ' + lateFeeAmount);
            
            // ✅ CREATE BREAKAGE RECORD
            ISB_Student_Fee_Breakage__c lateFeeBreakage = new ISB_Student_Fee_Breakage__c();
            
            // Required Fields
            lateFeeBreakage.ISB_Installment__c = fee.ISB_Installment__c;  
            lateFeeBreakage.Fee_Type__c = 'Late Fee';                     
            
            // Amount Fields
            lateFeeBreakage.Amount__c = lateFeeAmount;                   
            lateFeeBreakage.Pending_Amount__c = lateFeeAmount;            
            lateFeeBreakage.Paid_Amount__c = 0;                          
            
            lateFeeBreakagesToInsert.add(lateFeeBreakage);
            
            System.debug('✅ Created Late Fee Breakage: ' + lateFeeAmount + ' for Fee: ' + fee.Id);
            
            // ✅ UPDATE ISB_FEE__C - Add late fee to pending amount
            Decimal newFeePendingAmount = (fee.Pending_Amount__c != null ? fee.Pending_Amount__c : 0) + lateFeeAmount;
            Decimal newFeeTotalAmount = (fee.Total_amount__c != null ? fee.Total_amount__c : 0) + lateFeeAmount;
            
            feesToUpdate.add(new ISB_Fee__c(
                Id = fee.Id,
                Late_Fee_Added__c = true,
                Pending_Amount__c = newFeePendingAmount,  
                Total_amount__c = newFeeTotalAmount
            ));
            
            System.debug('✅ Updated Fee - New Pending: ' + newFeePendingAmount + ', New Total: ' + newFeeTotalAmount);
            
            // ✅ ACCUMULATE LATE FEE FOR INSTALLMENT
            if (!installmentLateFeeMap.containsKey(fee.ISB_Installment__c)) {
                installmentLateFeeMap.put(fee.ISB_Installment__c, lateFeeAmount);
                // Store the installment data for later use
                if (fee.ISB_Installment__r != null) {
                    installmentDataMap.put(fee.ISB_Installment__c, fee.ISB_Installment__r);
                }
            } else {
                Decimal currentTotal = installmentLateFeeMap.get(fee.ISB_Installment__c);
                installmentLateFeeMap.put(fee.ISB_Installment__c, currentTotal + lateFeeAmount);
            }
            
            System.debug('==========================================');
        }
        
        // ✅ UPDATE INSTALLMENTS - Add accumulated late fees
        for (Id installmentId : installmentLateFeeMap.keySet()) {
            Decimal totalLateFee = installmentLateFeeMap.get(installmentId);
            ISB_Installment__c installmentData = installmentDataMap.get(installmentId);
            
            if (installmentData == null) {
                System.debug('⚠️ No installment data found for: ' + installmentId);
                continue;
            }
            
            Decimal currentPending = installmentData.Pending_Amount__c != null ? installmentData.Pending_Amount__c : 0;
            Decimal currentTotal = installmentData.Total_Amount_calc__c != null ? installmentData.Total_Amount_calc__c : 0;
            
            Decimal newInstPendingAmount = currentPending + totalLateFee;
            Decimal newInstTotalAmount = currentTotal + totalLateFee;
            
            installmentsToUpdate.add(new ISB_Installment__c(
                Id = installmentId,
                Late_Fee_Added__c = true,
                Pending_Amount__c = newInstPendingAmount
            ));
            
            System.debug('✅ Updated Installment: ' + installmentId);
            System.debug('   Current Pending: ' + currentPending);
            System.debug('   Total Late Fee: ' + totalLateFee);
            System.debug('   New Pending: ' + newInstPendingAmount);
            System.debug('   New Total: ' + newInstTotalAmount);
        }
        
        // ✅ PERFORM DML OPERATIONS
        if (!lateFeeBreakagesToInsert.isEmpty()) {
            insert lateFeeBreakagesToInsert;
            System.debug('✅ Inserted ' + lateFeeBreakagesToInsert.size() + ' late fee breakage records');
        }
        
        if (!feesToUpdate.isEmpty()) {
            update feesToUpdate;
            System.debug('✅ Updated ' + feesToUpdate.size() + ' fee records (Late_Fee_Added__c = true)');
        }
        
        if (!installmentsToUpdate.isEmpty()) {
            update installmentsToUpdate;
            System.debug('✅ Updated ' + installmentsToUpdate.size() + ' Installment records (Late_Fee_Added__c = true)');
        }
    }
    
    // ---------------------------
    // FINISH
    // ---------------------------
    global void finish(Database.BatchableContext bc) {
        System.debug('==========================================');
        System.debug('✅ ISBLateFeeBatch completed successfully');
        System.debug('==========================================');
    }
    
    // ---------------------------
    // SCHEDULER
    // ---------------------------
    global void execute(SchedulableContext sc) {
        Database.executeBatch(new ISBLateFeeBatch(), 200);
    }
}