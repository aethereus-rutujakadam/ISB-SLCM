trigger ISBPaymentTrigger on ISB_Payment__c (after update , after Insert) {
    if (Trigger.isAfter && Trigger.isUpdate) {
        //ISBPaymentTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
    
     if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            ISB_PaymentTriggerHelper.handlePaymentUpdates(Trigger.new, null);
            system.debug('Insert');
        }
        if (Trigger.isUpdate) {
            system.debug('Updated');
            ISB_PaymentTriggerHelper.handlePaymentUpdates(
                Trigger.new, 
                Trigger.oldMap
            );
        }
    }
}