public without sharing class AAStudentFeedbackController {
    
    @AuraEnabled
    public static String submitFeedback(Id caseId, Decimal overallRating, String comments) {
        if (caseId == null) {
            throw new AuraHandledException('Case Id is required.');
        }

        // 1️⃣ Fetch Case
        Case c;
        try {
            c = [SELECT Id, CaseNumber, ContactId, OwnerId FROM Case WHERE Id = :caseId LIMIT 1];
        } catch (Exception ex) {
            throw new AuraHandledException('Unable to find the Case. ' + ex.getMessage());
        }

        if (c.ContactId == null) {
            throw new AuraHandledException('Case has no linked Student Contact.');
        }

        // 2️⃣ Get Case Team Member with role 'Academic Associate'
        List<CaseTeamMember> teamMembers = [
            SELECT MemberId 
            FROM CaseTeamMember 
            WHERE ParentId = :caseId 
            AND TeamRole.Name = 'Academic Associate'
            LIMIT 1
        ];

        if (teamMembers.isEmpty()) {
            throw new AuraHandledException('No Case Team Member with role "Academic Associate" found for this Case.');
        }

        Id aaId = teamMembers[0].MemberId;
        List<Contact> aaContacts;

        if (String.valueOf(aaId).startsWith('003')) {
            // Member is already a Contact
            aaContacts = [SELECT Id FROM Contact WHERE Id = :aaId LIMIT 1];
        } else {
            // Member is a User, find linked Contact
            aaContacts = [
                SELECT Id 
                FROM Contact 
                WHERE Linked_User_Id__c = :aaId
                LIMIT 1
            ];
        }

        if (aaContacts.isEmpty()) {
            throw new AuraHandledException('Unable to find a Contact record for the Academic Associate team member.');
        }
        Contact aaContact = aaContacts[0];

        // 3️⃣ Get AA Profile for that contact (latest one)
        AA_Profile__c aaProfile;
        List<AA_Profile__c> aaProfiles = [
            SELECT Id, Primary_Program__c, Academic_Term__c
            FROM AA_Profile__c
            WHERE Academic_Associate__c = :aaContact.Id
            ORDER BY Start_Date__c DESC, CreatedDate DESC
            LIMIT 1
        ];

        if (aaProfiles.isEmpty()) {
            throw new AuraHandledException('No Academic Associate profile found for the case owner contact.');
        }
        aaProfile = aaProfiles[0];

        // 4️⃣ Get RecordTypeId for Academic Associate feedback
        Map<String, Schema.RecordTypeInfo> rtMap = Schema.SObjectType.Feedback__c.getRecordTypeInfosByDeveloperName();
        if (!rtMap.containsKey('Academic_Associate')) {
            throw new AuraHandledException('Academic Associate record type not found on Feedback__c. Please ensure a record type with developer name "Academic_Associate" exists.');
        }
        Id aaRecordTypeId = rtMap.get('Academic_Associate').getRecordTypeId();

        // 5️⃣ Duplicate check (1 feedback per case)
        Integer existingCount = [
            SELECT count()
            FROM Feedback__c
            WHERE Survey_Response_Id__c = :caseId
              AND RecordTypeId = :aaRecordTypeId
        ];
        if (existingCount > 0) {
            throw new AuraHandledException('Feedback already submitted for this case.');
        }

        // 6️⃣ Create new Feedback record
        try {
            Feedback__c feedback = new Feedback__c();
            feedback.Name = 'AA Feedback for case ' + c.CaseNumber;
            feedback.RecordTypeId = aaRecordTypeId;
            feedback.Academic_Associate__c = aaProfile.Id; // AA Profile lookup
            feedback.Program__c = aaProfile.Primary_Program__c;
            feedback.Academic_Term__c = aaProfile.Academic_Term__c;
            feedback.Overall_Rating__c = (overallRating != null) ? String.valueOf(overallRating) : null;
            feedback.Comments__c = comments;
            feedback.Status__c = 'Published';
            feedback.Submitter_Type__c = 'Student';
            
            // Populate Submitter_User__c and Submitter_Contact__c
            Id studentUserId = UserInfo.getUserId();
            Id studentContactId = c.ContactId;
            
            if (studentContactId != null) {
                List<User> users = [SELECT Id FROM User WHERE ContactId = :studentContactId AND IsActive = true LIMIT 1];
                if (!users.isEmpty()) {
                    studentUserId = users[0].Id;
                }
            }
            try {
                feedback.Submitter_User__c = studentUserId;
                if (studentContactId != null) {
                    feedback.Submitter_Contact__c = studentContactId;
                }
            } catch (Exception e) {
                System.debug('Submitter fields not available: ' + e.getMessage());
            }

            feedback.Survey_Response_Id__c = caseId;

            insert feedback;
            return feedback.Id;
        } catch (DmlException dmx) {
            throw new AuraHandledException('Unable to save feedback: ' + dmx.getMessage());
        } catch (Exception ex) {
            throw new AuraHandledException('Unexpected error while saving feedback: ' + ex.getMessage());
        }
    }
}