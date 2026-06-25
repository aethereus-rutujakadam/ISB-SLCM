trigger StudentPostTrigger on Student_Post__c (after update) {
    if (Trigger.isAfter && Trigger.isUpdate) {
        StudentPostTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
    }
}