trigger TaskTrigger on Task (before insert, before update, before delete, after insert) {
    if (Trigger.isBefore && Trigger.isInsert) {
        TaskTriggerHandler.beforeInsert(Trigger.new);
    }

    if (Trigger.isBefore && Trigger.isUpdate) {
        TaskTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
    }

    if (Trigger.isBefore && Trigger.isDelete) {
        TaskTriggerHandler.beforeDelete(Trigger.old);
    }

    if (Trigger.isAfter && Trigger.isInsert) {
        TaskTriggerHandler.afterInsert(Trigger.new);
    }
}