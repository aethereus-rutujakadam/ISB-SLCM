trigger ISBInstallmentTrigger on ISB_Installment__c (after insert, after update) {

    if (Trigger.isAfter && Trigger.isInsert) {
        //ISBInstallmentTriggerHandler.createGSTRecords(Trigger.new, null);
    }

    if (Trigger.isAfter && Trigger.isUpdate) {
       // ISBInstallmentTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
    }
    
    if (Trigger.isAfter) {
        if (Trigger.isInsert || Trigger.isUpdate) {
            ISBInstallmentTriggerHandler.syncInstallmentsToISBFees(Trigger.new);
        }
    }
}