public with sharing class GraduationEligibilityLwcController {
    
    @AuraEnabled
    public static void updateEligibilities(List<Map<String, Object>> eligibilityUpdates) {
        try {
            List<Graduation_Eligibility__c> recordsToUpdate = new List<Graduation_Eligibility__c>();
            
            for (Map<String, Object> updateMap : eligibilityUpdates) {
                Graduation_Eligibility__c record = new Graduation_Eligibility__c();
                record.Id = (String) updateMap.get('Id');
                
                if (updateMap.containsKey('Notes__c')) {
                    record.Notes__c = (String) updateMap.get('Notes__c');
                }
                if (updateMap.containsKey('Eligibility_Status__c')) {
                    record.Eligibility_Status__c = (String) updateMap.get('Eligibility_Status__c');
                }
                
                recordsToUpdate.add(record);
            }
            
            if (!recordsToUpdate.isEmpty()) {
                update recordsToUpdate;
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error updating eligibilities: ' + e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getPicklistValues(String objectName, String fieldName) {
        List<Map<String, String>> picklistValues = new List<Map<String, String>>();
        
        try {
            Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectName);
            Schema.DescribeSObjectResult objDescribe = objType.getDescribe();
            Schema.DescribeFieldResult fieldDescribe = objDescribe.fields.getMap().get(fieldName).getDescribe();
            
            for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
                if (entry.isActive()) {
                    Map<String, String> picklistOption = new Map<String, String>();
                    picklistOption.put('label', entry.getLabel());
                    picklistOption.put('value', entry.getValue());
                    picklistValues.add(picklistOption);
                }
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching picklist values: ' + e.getMessage());
        }
        
        return picklistValues;
    }
    
    @AuraEnabled (cacheable=true)
    public static List<Graduation_Eligibility__c> fetchEligibiltystatus(String recordId){   
        try {
            Case caseRecord = [
                SELECT Program__c, Academic_Year__c,Academic_Term__c
                FROM Case 
                WHERE Id = :recordId 
                LIMIT 1
            ];
            return [
                SELECT Id, Name, 
                Academic_Year__c, Academic_Year__r.Name,
                Academic_Term__c, Academic_Term__r.Name,
                Program__c, Program__r.Name,
                Contact__c, Contact__r.Name,
                Program_Enrollment__c,
                Program_Enrollment__r.ContactId,
                Program_Enrollment__r.Contact.Name,
                Eligibility_Status__c,Finance_Clearance__c,CGPA__c,Disciplinary_Hold__c,
                Notes__c
                FROM Graduation_Eligibility__c
                WHERE Program__c = :caseRecord.Program__c
                AND Academic_Term__c = :caseRecord.Academic_Term__c 
                ORDER BY Name
            ];
            
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching eligibility records: ' + e.getMessage());
        }   
    }
    
   /* @AuraEnabled
    public static String sendGraduationEmails(String recordId) {
        
        // Get Program + Academic Year from Case
        Case caseRecord = [
            SELECT Program__c, Academic_Year__c
            FROM Case 
            WHERE Id = :recordId
            LIMIT 1
        ];
        
        // Get all Approved eligibility records
        List<Graduation_Eligibility__c> eligibilities = [
            SELECT Id, Program_Enrollment__c
            ,Program_Enrollment__r.ContactId
            ,Program_Enrollment__r.Contact.Email
            ,Program_Enrollment__r.Contact.Name
            FROM Graduation_Eligibility__c
            WHERE Program__c = :caseRecord.Program__c
            AND Academic_Year__c = :caseRecord.Academic_Year__c //add case check
            AND Eligibility_Status__c = 'Approved'
        ];
        
        if (eligibilities.isEmpty()) {
            return 'No approved eligibility records found.';
        }
        
        // Fetch Program Enrollment
        Set<Id> peIds = new Set<Id>();
        for (Graduation_Eligibility__c ge : eligibilities) {
            if (ge.Program_Enrollment__c != null)
                peIds.add(ge.Program_Enrollment__c);
        }
        
        Map<Id, ProgramEnrollment> peMap = new Map<Id, ProgramEnrollment>(
            [SELECT Id, Status, ContactId, Contact.Email
             FROM ProgramEnrollment
             WHERE Id IN :peIds]
        );
        
        // Get Email Template
        Id templateId = [
            SELECT Id 
            FROM EmailTemplate 
            WHERE DeveloperName = 'Graduated'
            LIMIT 1
        ].Id;
        
        // Get Org-Wide Email Address
        Id orgWideEmailId;
        try {
            orgWideEmailId = [
                SELECT Id
                FROM OrgWideEmailAddress
                WHERE DisplayName = 'Gradutaion Email'
                LIMIT 1
            ].Id;
        } catch (Exception e) {}
        
        // Prepare Emails
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<ProgramEnrollment> updatePE = new List<ProgramEnrollment>();
        
        for (Graduation_Eligibility__c ge : eligibilities) {
            
            if (!peMap.containsKey(ge.Program_Enrollment__c)) continue;
            
            ProgramEnrollment pe = peMap.get(ge.Program_Enrollment__c);
            
            // Update Program Enrollment status → Graduated
            if (pe.Status != 'Graduated') {
                pe.Status = 'Graduated';
                updatePE.add(pe);
            }
            //Enrollment Session Tag from here 
            // Prepare Email
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setTargetObjectId(pe.ContactId);
            email.setWhatId(ge.Id);
            email.setTemplateId(templateId);
            email.setSaveAsActivity(false);
            if (orgWideEmailId != null) {
                email.setOrgWideEmailAddressId(orgWideEmailId);
            }
            emails.add(email);
        }
        
        if (!updatePE.isEmpty()) update updatePE;
        if (!emails.isEmpty()) Messaging.sendEmail(emails);
        
        return emails.size() + ' graduation notification(s) sent successfully.';
    }*/

        @AuraEnabled
    public static String sendGraduationEmails(Id recordId) {

    Case c = [
        SELECT Program__c, Academic_Year__c,Academic_Term__c
        FROM Case
        WHERE Id = :recordId
        LIMIT 1
    ];

    List<Graduation_Eligibility__c> elig = [
        SELECT Id, Program_Enrollment__c
        FROM Graduation_Eligibility__c
        WHERE Program__c = :c.Program__c
          AND Academic_Term__c = :c.Academic_Term__c
          AND Eligibility_Status__c = 'Approved'
    ];
    if (elig.isEmpty()) return 'No approved eligibility records found.';

    // Template
    List<EmailTemplate> ts = [
        SELECT Id FROM EmailTemplate WHERE DeveloperName = 'Graduated' LIMIT 1
    ];
    if (ts.isEmpty()) return 'Email template "Graduated" not found.';
    Id templateId = ts[0].Id;

    // Program Enrollments
    Set<Id> peIds = new Set<Id>();
    for (Graduation_Eligibility__c ge : elig) 
   if (ge.Program_Enrollment__c != null) peIds.add(ge.Program_Enrollment__c);

    Map<Id, ProgramEnrollment> peMap = new Map<Id, ProgramEnrollment>([
        SELECT Id, Status, ContactId, Contact.Email
        FROM ProgramEnrollment
        WHERE Id IN :peIds
    ]);

    // Org-wide email (optional, safer to query by Address if possible)
    Id oweaId = null;
    List<OrgWideEmailAddress> owes = [
        SELECT Id FROM OrgWideEmailAddress WHERE DisplayName = 'ISB Support' LIMIT 1
    ];
    if (!owes.isEmpty()) oweaId = owes[0].Id;

    // Dedupe: one email per Program Enrollment
    Set<Id> processedPE = new Set<Id>();

    List<ProgramEnrollment> toUpdate = new List<ProgramEnrollment>();
    List<Messaging.SingleEmailMessage> msgs = new List<Messaging.SingleEmailMessage>();
	List<Enrollment_Session__c> sessionsToUpdate = new List<Enrollment_Session__c>();
    for (Graduation_Eligibility__c ge : elig) {
        if (ge.Program_Enrollment__c == null || processedPE.contains(ge.Program_Enrollment__c)) continue;
        ProgramEnrollment pe = peMap.get(ge.Program_Enrollment__c);
        if (pe == null) continue;

        // must have recipient
        if (pe.ContactId == null || String.isBlank(pe.Contact.Email)) continue;

        processedPE.add(pe.Id);

        if (pe.Status != 'Graduated') {
            pe.Status = 'Graduated';
            toUpdate.add(pe);
        }
        sessionsToUpdate = [
            SELECT Id, Program_Enrollment__c, Status__c
            FROM Enrollment_Session__c
            WHERE Program_Enrollment__c IN :peIds
              AND (Status__c != 'Completed'
              AND Status__c != 'LOA')
        ];
        
        for (Enrollment_Session__c es : sessionsToUpdate) {
            es.Status__c = 'Completed';
        } 
        
        Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
        m.setTargetObjectId(pe.ContactId);

        // SAFEST default: use Case as whatId for merge fields
        m.setWhatId(recordId);

        m.setTemplateId(templateId);
        m.setSaveAsActivity(false);
        if (oweaId != null) m.setOrgWideEmailAddressId(oweaId);
        msgs.add(m);
    }
	if (!sessionsToUpdate.isEmpty()) {
            update sessionsToUpdate;
        }
    if (!toUpdate.isEmpty()) update toUpdate;

    Integer success = 0, fail = 0;
    if (!msgs.isEmpty()) {
        Messaging.SendEmailResult[] rs = Messaging.sendEmail(msgs, false);
        for (Messaging.SendEmailResult r : rs) {
            if (r.isSuccess()) success++; else fail++;
        }
    }

    return success + ' sent, ' + fail + ' failed.';
}
    
}