trigger ProgramEnrollmentTrigger on ProgramEnrollment (before insert, before update, after insert, after update) {

    if (Trigger.isBefore && Trigger.isInsert) {
        ProgramEnrollmentHandler.handleBeforeInsert(Trigger.new);
    }

    if (Trigger.isAfter) {
        // Recursion guard: prevent re-entrant after-context executions
        if (ProgramEnrollmentHandler.hasRun) return;
        ProgramEnrollmentHandler.hasRun = true;
    }

    if (Trigger.isAfter && Trigger.isInsert) {
        ProgramEnrollmentHandler.handleAfterInsert(Trigger.new);
    }

    if (Trigger.isAfter && Trigger.isUpdate) {
        ProgramEnrollmentHandler.updateEnrollmentSessionsOnEnrollmentUpdate(Trigger.new);
    }

    // F-05 FIX: Skip probation and stamp logic during bulk incoming upload.
    // isIncomingUpload is set by InternationalExchangeController.processIncomingExchangeUpload
    // to avoid firing expensive handlers on every row insert during batch processing.
    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)
            && !ProgramEnrollmentHandler.isIncomingUpload) {
        ProgramEnrollmentHandler.createAcademicProbationCases(Trigger.new, Trigger.oldMap);
        ProgramEnrollmentHandler.stampCurrentProgramOnContact(Trigger.new, Trigger.oldMap);
    }
}