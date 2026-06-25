/**
 * @description Trigger for ContentDocumentLink to ensure proper file visibility
 */
trigger ContentDocumentLinkTrigger on ContentDocumentLink (before insert, after insert) {
    // COMMENTED OUT: Contact file visibility trigger logic
    // Uncomment below to enable automatic file visibility settings
    /*
    if (Trigger.isBefore && Trigger.isInsert) {
        ContentDocumentLinkHandler.handleBeforeInsert(Trigger.new);
    }

    if (Trigger.isAfter && Trigger.isInsert) {
        try {
            CaseFileNotificationHandler.handleAfterInsert(Trigger.new);
        } catch (Exception e) {
            System.debug('ContentDocumentLinkTrigger.handleAfterInsert error: ' + e.getMessage());
        }
    }
    */

    if (Trigger.isAfter && Trigger.isInsert) {
        try {
            ContentDocumentLinkHandler.handleAfterInsert(Trigger.new);
        } catch (Exception e) {
            System.debug('ContentDocumentLinkTrigger.handleAfterInsert error: ' + e.getMessage());
        }
    }

}