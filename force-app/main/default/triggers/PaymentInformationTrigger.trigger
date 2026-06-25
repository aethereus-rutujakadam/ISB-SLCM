trigger PaymentInformationTrigger on Payment_Information__c (before insert, before update, after insert, after update) {
    
    // Before Insert: Handle Grades Released logic
    if (Trigger.isBefore && Trigger.isInsert) {
        FacultyPaymentChecklistHandler.handleGradesReleasedLogic(Trigger.new, null);
    }
    
    // Before Update: Handle Grades Released logic
    if (Trigger.isBefore && Trigger.isUpdate) {
        FacultyPaymentChecklistHandler.handleGradesReleasedLogic(Trigger.new, Trigger.oldMap);
    }
    
    // After Insert: Handle owner assignment notifications (when SPOC/Course Manager assigned at creation)
    if (Trigger.isAfter && Trigger.isInsert) {
        FacultyPaymentChecklistHandler.handleOwnerChangeNotifications(Trigger.new, null);
    }
    
    // After Update: Handle owner change notifications
    if (Trigger.isAfter && Trigger.isUpdate) {
        FacultyPaymentChecklistHandler.handleOwnerChangeNotifications(Trigger.new, Trigger.oldMap);
    }
}