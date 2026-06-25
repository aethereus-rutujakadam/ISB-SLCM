public without sharing class CaseAssignmentHandler {

    public static void handleAfterUpdate(List<Case> newCases, Map<Id, Case> oldMap) {

        System.debug('=== CaseAssignmentHandler.handleAfterUpdate started ===');

        // Identify LOA cases that changed from Open → Closed
        List<Case> loaCases = new List<Case>();
        Set<Id> recordTypeIds = new Set<Id>();

        for (Case c : newCases) {
            Case oldC = oldMap.get(c.Id);

            if (c.Status == 'Closed' && oldC.Status != 'Closed' && c.RecordTypeId != null) {
                recordTypeIds.add(c.RecordTypeId);
            }
        }

        if (recordTypeIds.isEmpty()) {
            System.debug('No cases moved to Closed.');
            return;
        }

        // Fetch record types
        Map<Id, RecordType> rtMap = new Map<Id, RecordType>(
            [SELECT Id, DeveloperName FROM RecordType WHERE Id IN :recordTypeIds]
        );

        // Filter only LOA record type cases
        for (Case c : newCases) {
            Case oldC = oldMap.get(c.Id);

            if (rtMap.containsKey(c.RecordTypeId) &&
                rtMap.get(c.RecordTypeId).DeveloperName == 'LOA' &&
                c.Status == 'Closed' && oldC.Status != 'Closed') {

                loaCases.add(c);
            }
        }

        if (loaCases.isEmpty()) {
            System.debug('No LOA cases to process.');
            return;
        }



        // Fire Helper
        CaseTriggerHelper.processLOACases(loaCases);

        System.debug('=== CaseAssignmentHandler.handleAfterUpdate completed ===');
    }


private static Id getCaseRecordTypeId(String developerName) {
    if (String.isBlank(developerName)) return null;
    List<RecordType> rts = [
        SELECT Id FROM RecordType
        WHERE SObjectType = 'Case' AND DeveloperName = :developerName
        LIMIT 1
    ];
    return rts.isEmpty() ? null : rts[0].Id;
}
public static void handleCaseClosure(List<Case> newList, Map<Id, Case> oldMap) {
    System.debug('🔒 Checking for closed Academic Probation cases');
    
    Id academicProbationRtId = getCaseRecordTypeId('Academic_Probation');
    if (academicProbationRtId == null) {
        System.debug('❌ Academic Probation Record Type not found');
        return;
    }
    
    List<Case> closedCases = new List<Case>();
    
    for (Case c : newList) {
        Case oldCase = oldMap.get(c.Id);
        
        if (c.IsClosed && !oldCase.IsClosed && 
            c.RecordTypeId == academicProbationRtId && 
            c.ContactId != null) {
            closedCases.add(c);
        }
    }
    
    if (!closedCases.isEmpty()) {
        System.debug('🔒 Found ' + closedCases.size() + ' newly closed Academic Probation cases');
        sendProbationClearedEmails(closedCases);
    }
}
// NEW METHOD: Send Probation Cleared Emails
private static void sendProbationClearedEmails(List<Case> closedCases) {
    System.debug('📧 Preparing probation cleared emails for ' + closedCases.size() + ' cases');
    
    Set<Id> contactIds = new Set<Id>();
    for (Case c : closedCases) {
        if (c.ContactId != null) {
            contactIds.add(c.ContactId);
        }
    }
    
    if (contactIds.isEmpty()) return;
    
    Map<Id, Contact> contactsById = new Map<Id, Contact>([
        SELECT Id, Email, FirstName, LastName, Name 
        FROM Contact 
        WHERE Id IN :contactIds AND Email != null
    ]);
    
    System.debug('📧 Found ' + contactsById.size() + ' contacts with email addresses');
    
    if (contactsById.isEmpty()) return;
    
    List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
    
    OrgWideEmailAddress[] owea = [SELECT Id, Address FROM OrgWideEmailAddress LIMIT 1];
    
    for (Case closedCase : closedCases) {
        Contact contact = contactsById.get(closedCase.ContactId);
        if (contact == null) continue;
        
        System.debug('📧 Preparing probation cleared email for: ' + contact.Name + ' (' + contact.Email + ')');
        
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        
        if (!owea.isEmpty()) {
            mail.setOrgWideEmailAddressId(owea[0].Id);
        } else {
            mail.setSenderDisplayName('Academic Affairs Office');
        }
        
        mail.setToAddresses(new String[]{contact.Email});
        mail.setSubject('Congratulations: Academic Probation Cleared');
        
        String studentName = contact.FirstName != null ? contact.FirstName : 'Student';
        String plainTextBody = 'Dear ' + studentName + ',\n\n' +
            'We are pleased to inform you that your Academic Probation case has been successfully resolved and closed.\n\n' +
            'CONGRATULATIONS on improving your academic performance!\n\n' +
            'Your dedication and hard work have paid off. You are no longer on academic probation.\n\n' +
            'KEY POINTS:\n' +
            '• Your academic standing has been restored\n' +
            '• Continue to maintain good academic performance\n' +
            '• Academic support services remain available if needed\n\n' +
            'Keep up the excellent work!\n\n' +
            'Best regards,\n' +
            'Academic Affairs Office';
        
        mail.setPlainTextBody(plainTextBody);
        mail.setSaveAsActivity(true);
        
        emails.add(mail);
    }
    
    if (!emails.isEmpty()) {
        try {
            System.debug('📧 Attempting to send ' + emails.size() + ' probation cleared emails');
            List<Messaging.SendEmailResult> results = Messaging.sendEmail(emails);
            
            Integer successCount = 0;
            for(Messaging.SendEmailResult result : results) {
                if(result.isSuccess()) {
                    successCount++;
                    System.debug('✅ Probation cleared email sent successfully');
                } else {
                    System.debug('❌ Probation cleared email failed: ' + result.getErrors()[0].getMessage());
                }
            }
            System.debug('✅ Final result: ' + successCount + '/' + emails.size() + ' probation cleared emails sent successfully');
        } catch (Exception e) {
            System.debug('❌ Error sending probation cleared emails: ' + e.getMessage());
        }
    }
}


}