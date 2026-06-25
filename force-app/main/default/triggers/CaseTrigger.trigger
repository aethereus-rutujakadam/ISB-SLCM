/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 06-16-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
trigger CaseTrigger on Case (before update, after update ,after insert) {

    if (Trigger.isBefore && Trigger.isUpdate) {
        CaseTriggerHandler.ensureGeneralSupportRejectedOwner(Trigger.new, (Map<Id, Case>)Trigger.oldMap);
        IncomingExchangeCaseHandler.handleBeforeUpdate(Trigger.new, (Map<Id, Case>)Trigger.oldMap);
        OutgoingExchangeCaseHandler.handleBeforeUpdate(Trigger.new, (Map<Id, Case>)Trigger.oldMap);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        CaseTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
        IncomingExchangeCaseHandler.handleAfterUpdate(Trigger.new, (Map<Id, Case>)Trigger.oldMap);
        OutgoingExchangeCaseHandler.handleAfterUpdate(Trigger.new, (Map<Id, Case>)Trigger.oldMap);
        ExchangeCaseAssignmentRuleHandler.applyOnAfterUpdate(Trigger.new, (Map<Id, Case>)Trigger.oldMap);
        //CaseAssignmentHandler.handleCaseClosure(Trigger.new, Trigger.oldMap);
        CaseTriggerHandler.handleStatusChange(Trigger.new, Trigger.oldMap);
    }
    if(Trigger.isAfter && Trigger.isInsert) {
        ExchangeCaseAssignmentRuleHandler.handleAfterInsert(Trigger.new);
                OutgoingExchangeCaseHandler.handleAfterInsert(Trigger.new);
        CaseTriggerHandler.createGraduationEligibilityOnCase(Trigger.new);
      // CaseTriggerHandler.checkCaseRecordTypes(Trigger.new);
    }
}