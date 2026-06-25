trigger ISBStudentFeeBreakageTrigger on ISB_Student_Fee_Breakage__c (before insert ,after insert, after update) {
   // ISBStudentFeeBreakageTriggerHandler.handleBeforeInsert(Trigger.new);
    System.debug('Inside Trigger Classsss');
    if (Trigger.isAfter) {
            System.debug('Inside Trigger Classsssqwefgrhtjry');
        ISBStudentFeeBreakageTriggerHandler.updateScholarshipOnInstallment(Trigger.new);
    }    
}