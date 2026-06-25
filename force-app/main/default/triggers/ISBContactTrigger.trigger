trigger ISBContactTrigger on Contact (before update, after update, before delete) {
    System.debug('--- ISBContactTrigger Execution Started ---');
    if (Trigger.isBefore && Trigger.isUpdate) {
        System.debug('Trigger Context: Before Update. Calling Handler.');
        ISBContactTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
    }
    
     if (Trigger.isAfter && Trigger.isUpdate) {
        System.debug('Trigger Context: After Update. Calling Handler.');
        ISBContactTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
    }
    System.debug('--- ISBContactTrigger Execution Completed ---');
    if (Trigger.isBefore && Trigger.isDelete) {
        ISBContactTriggerHandler.handleBeforeDelete(Trigger.old);
    }
}