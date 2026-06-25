global without sharing class ISBInstallmentMissedBatch 
implements Database.Batchable<SObject>, Schedulable {

    // ===========================
    // BATCH START
    // ===========================
    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id,
                   Name,
                   Contact__c,
                   Program__c,
                   Program_Enrollment__c,
                   Actual_Amount__c,
                   Pending_Amount__c,
                   Due_Date__c,
                   Extended_Due_Date__c,
                   Installment_Number__c,
                   Late_Fee_Added__c  
            FROM ISB_Installment__c
            WHERE Pending_Amount__c > 0
              AND Late_Fee_Added__c = false
              AND (
                      (Extended_Due_Date__c != null AND Extended_Due_Date__c < :System.today())
                   OR (Extended_Due_Date__c = null AND Due_Date__c < :System.today())
                  )
        ]);
    }

    // ===========================
    // BATCH EXECUTE
    // ===========================
    global void execute(Database.BatchableContext bc, List<ISB_Installment__c> scope) {

        List<ISB_Student_Fee_Breakage__c> breakageRecords = new List<ISB_Student_Fee_Breakage__c>();
        List<ISB_Installment__c> installmentUpdates = new List<ISB_Installment__c>();
        Set<Id> programEnrollmentIds = new Set<Id>();

        for (ISB_Installment__c inst : scope) {

            Decimal lateFee = 0;

            if (inst.Installment_Number__c == '1') {
                lateFee = 10000;
            } else if (inst.Pending_Amount__c != null) {
                lateFee = (inst.Pending_Amount__c * 1.5) / 100;
            }

            if (lateFee > 0) {

                // Create Late Fee Breakage
                ISB_Student_Fee_Breakage__c brk = new ISB_Student_Fee_Breakage__c();
                brk.ISB_Installment__c = inst.Id;
                brk.Fee_Type__c = 'Late Fee';
                brk.Amount__c = lateFee;

                breakageRecords.add(brk);

                // Update Installment
                inst.Pending_Amount__c += lateFee;
                inst.Late_Fee_Added__c = true;
                installmentUpdates.add(inst);

                // Collect Program Enrollment
                if (inst.Program_Enrollment__c != null) {
                    programEnrollmentIds.add(inst.Program_Enrollment__c);
                }
            }
        }

        if (!breakageRecords.isEmpty()) {
            insert breakageRecords;
        }

        if (!installmentUpdates.isEmpty()) {
            update installmentUpdates;
        }

        // ===========================
        // UPDATE PROGRAM ENROLLMENTS
        // ===========================
        if (!programEnrollmentIds.isEmpty()) {

            List<ProgramEnrollment> enrollmentsToUpdate = [
                SELECT Id, Status, Sub_Status__c
                FROM ProgramEnrollment
                WHERE Id IN :programEnrollmentIds
            ];

            for (ProgramEnrollment pe : enrollmentsToUpdate) {
                pe.Status = 'On Hold';
                pe.Sub_Status__c = 'Fee payment';
            }

            update enrollmentsToUpdate;
        }
    }

    // ===========================
    // FINISH
    // ===========================
    global void finish(Database.BatchableContext bc) {
        System.debug('Missed Installment Late Fee Batch Completed.');
    }

    // ===========================
    // SCHEDULER
    // ===========================
    global void execute(SchedulableContext sc) {
        Database.executeBatch(new ISBInstallmentMissedBatch(), 200);
    }
}