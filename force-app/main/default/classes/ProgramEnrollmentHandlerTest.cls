@isTest
private class ProgramEnrollmentHandlerTest {

    @testSetup
    static void setupProbationTestData() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User advisorUser = new User(
            FirstName = 'Advisor',
            LastName = 'Handler',
            Email = 'advisor.handler@test.devslcm',
            Username = 'advisor.handler.' + System.now().getTime() + '@test.devslcm',
            Alias = 'advhnd',
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = standardProfile.Id
        );
        insert advisorUser;

        Contact advisorContact = new Contact(
            FirstName = 'Advisor',
            LastName = 'Contact',
            Email = 'advisor.contact.handler@test.devslcm',
            Linked_User_Id__c = advisorUser.Id
        );
        insert advisorContact;

        Contact advisorWithoutUser = new Contact(
            FirstName = 'Advisor',
            LastName = 'No User',
            Email = 'advisor.nouser.handler@test.devslcm'
        );
        insert advisorWithoutUser;

        Contact studentWithAdvisor = new Contact(
            FirstName = 'Student',
            LastName = 'With Advisor',
            Email = 'student.withadvisor.handler@test.devslcm'
        );
        Contact studentWithAdvisorNoUser = new Contact(
            FirstName = 'Student',
            LastName = 'Advisor No User',
            Email = 'student.nouser.handler@test.devslcm'
        );
        Contact studentWithoutAdvisor = new Contact(
            FirstName = 'Student',
            LastName = 'Without Advisor',
            Email = 'student.noadvisor.handler@test.devslcm'
        );
        insert new List<Contact>{ studentWithAdvisor, studentWithAdvisorNoUser, studentWithoutAdvisor };

        insert new List<ProgramEnrollment>{
            new ProgramEnrollment(
                ContactId = studentWithAdvisor.Id,
                Primary_Advisor__c = advisorContact.Id,
                IsActive = true
            ),
            new ProgramEnrollment(
                ContactId = studentWithAdvisorNoUser.Id,
                Primary_Advisor__c = advisorWithoutUser.Id,
                IsActive = true
            ),
            new ProgramEnrollment(
                ContactId = studentWithoutAdvisor.Id,
                IsActive = true
            )
        };
    }

    @isTest
    static void testProbationCaseSetsAdvisorAsOwnerAndSendsNotification() {
        ProgramEnrollment enrollment = getTestEnrollment('student.withadvisor.handler@test.devslcm');
        Contact advisorContact = [
            SELECT Id, Linked_User_Id__c
            FROM Contact
            WHERE Id = :enrollment.Primary_Advisor__c
        ];

        Test.startTest();
        ProgramEnrollmentHandler.createAcademicProbationCases(
            new List<ProgramEnrollment>{ buildUpdatedEnrollment(enrollment, 2.20) },
            new Map<Id, ProgramEnrollment>{
                enrollment.Id => buildPriorEnrollment(enrollment.Id, 3.10)
            }
        );
        Test.stopTest();

        Case probationCase = [
            SELECT Id, ContactId, Subject, OwnerId
            FROM Case
            WHERE ContactId = :enrollment.ContactId
            AND Subject = 'Academic Probation - Low CGPA'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        Task followUpTask = [
            SELECT Id, Subject, WhatId, WhoId
            FROM Task
            WHERE WhatId = :probationCase.Id
            AND Subject = 'Meet Primary Advisor'
            LIMIT 1
        ];
        System.assertEquals(enrollment.ContactId, followUpTask.WhoId, 'Follow-up task should be related to the student contact.');
        System.assertEquals((Id) advisorContact.Linked_User_Id__c, probationCase.OwnerId,
            'Primary advisor user should own the probation case.');
    }

    @isTest
    static void testProbationCaseFallsBackToQueueWhenAdvisorHasNoLinkedUser() {
        ProgramEnrollment enrollment = getTestEnrollment('student.nouser.handler@test.devslcm');

        Test.startTest();
        ProgramEnrollmentHandler.createAcademicProbationCases(
            new List<ProgramEnrollment>{ buildUpdatedEnrollment(enrollment, 2.10) },
            new Map<Id, ProgramEnrollment>{
                enrollment.Id => buildPriorEnrollment(enrollment.Id, 3.00)
            }
        );
        Test.stopTest();

        Case probationCase = [
            SELECT Id, ContactId, OwnerId
            FROM Case
            WHERE ContactId = :enrollment.ContactId
            AND Subject = 'Academic Probation - Low CGPA'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        Integer followUpTaskCount = [
            SELECT COUNT()
            FROM Task
            WHERE WhatId = :probationCase.Id
            AND Subject = 'Meet Primary Advisor'
        ];

        System.assertEquals(1, followUpTaskCount, 'Probation follow-up task should still be created.');
        Id asaQueueId = getAsaQueueId();
        if (asaQueueId != null) {
            System.assertEquals(asaQueueId, probationCase.OwnerId, 'Probation case should fall back to the ASA queue when advisor has no linked user.');
        } else {
            System.assertNotEquals(null, probationCase.OwnerId, 'Probation case should still have an owner when advisor is unavailable.');
        }
    }

    @isTest
    static void testProbationCaseFallsBackToQueueWhenPrimaryAdvisorMissing() {
        ProgramEnrollment enrollment = getTestEnrollment('student.noadvisor.handler@test.devslcm');

        Test.startTest();
        ProgramEnrollmentHandler.createAcademicProbationCases(
            new List<ProgramEnrollment>{ buildUpdatedEnrollment(enrollment, 2.00) },
            new Map<Id, ProgramEnrollment>{
                enrollment.Id => buildPriorEnrollment(enrollment.Id, 3.20)
            }
        );
        Test.stopTest();

        Case probationCase = [
            SELECT Id, ContactId, OwnerId
            FROM Case
            WHERE ContactId = :enrollment.ContactId
            AND Subject = 'Academic Probation - Low CGPA'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        Integer followUpTaskCount = [
            SELECT COUNT()
            FROM Task
            WHERE WhatId = :probationCase.Id
            AND Subject = 'Meet Primary Advisor'
        ];

        System.assertEquals(1, followUpTaskCount, 'Probation follow-up task should still be created without an advisor.');
        Id asaQueueId = getAsaQueueId();
        if (asaQueueId != null) {
            System.assertEquals(asaQueueId, probationCase.OwnerId, 'Probation case should fall back to the ASA queue when no advisor is assigned.');
        } else {
            System.assertNotEquals(null, probationCase.OwnerId, 'Probation case should still have an owner when no advisor is assigned.');
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private static ProgramEnrollment getTestEnrollment(String studentEmail) {
        return [
            SELECT Id, Name, ContactId, ProgramId, Primary_Advisor__c
            FROM ProgramEnrollment
            WHERE Contact.Email = :studentEmail
            LIMIT 1
        ];
    }

    private static ProgramEnrollment buildUpdatedEnrollment(ProgramEnrollment enrollment, Decimal cgpa) {
        ProgramEnrollment updatedEnrollment = new ProgramEnrollment(
            Id = enrollment.Id,
            ContactId = enrollment.ContactId,
            Primary_Advisor__c = enrollment.Primary_Advisor__c,
            ProgramId = enrollment.ProgramId,
            CGPA__c = cgpa
        );
        updatedEnrollment.put('Name', enrollment.Name);
        return updatedEnrollment;
    }

    private static ProgramEnrollment buildPriorEnrollment(Id enrollmentId, Decimal cgpa) {
        return new ProgramEnrollment(
            Id = enrollmentId,
            CGPA__c = cgpa
        );
    }

    private static Id getAsaQueueId() {
        List<Group> queues = [
            SELECT Id
            FROM Group
            WHERE Type = 'Queue'
            AND DeveloperName = 'ASA_Queue'
            LIMIT 1
        ];
        if (queues.isEmpty()) {
            return null;
        }

        List<QueueSobject> queueObjects = [
            SELECT Id
            FROM QueueSobject
            WHERE QueueId = :queues[0].Id
            AND SObjectType = 'Case'
            LIMIT 1
        ];
        return queueObjects.isEmpty() ? null : queues[0].Id;
    }
}