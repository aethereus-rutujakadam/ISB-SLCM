trigger ISBFeesTrigger on ISB_Fee__c (before insert , after insert) {
    
    if (Trigger.isBefore && Trigger.isInsert) {
        ISBFeeTriggerHandler.handleBeforeInsert(Trigger.new);
    }
    
    if(Trigger.isAfter && Trigger.isInsert){
        ISBFeeTriggerHandler.handleAfterInsert(Trigger.new);
    }
    
}