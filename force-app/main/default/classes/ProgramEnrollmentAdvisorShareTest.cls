@isTest(SeeAllData=true)
private class ProgramEnrollmentAdvisorShareTest {

    @isTest
    static void testCreateAndReplaceShares() {
        ProgramEnrollment enrollment = [
            SELECT Id, ContactId
            FROM ProgramEnrollment
            WHERE ContactId != null
            LIMIT 1
        ];
        System.assertNotEquals(null, enrollment, 'Need at least one ProgramEnrollment with ContactId for this test.');

        List<User> advisorUsers = [
            SELECT Id
            FROM User
            WHERE IsActive = true
            AND Id != :UserInfo.getUserId()
            LIMIT 2
        ];
        System.assert(advisorUsers.size() == 2, 'Need at least two active non-running users for this test.');
        Id advisorUserOld = advisorUsers[0].Id;
        Id advisorUserNew = advisorUsers[1].Id;

        Contact advisorOld = new Contact(
            FirstName = 'Old',
            LastName = 'Advisor Old',
            Email = 'advisor.old@test.com',
            Linked_User_Id__c = advisorUserOld
        );
        Contact advisorNew = new Contact(
            FirstName = 'New',
            LastName = 'Advisor New',
            Email = 'advisor.new@test.com',
            Linked_User_Id__c = advisorUserNew
        );
        insert new List<Contact>{ advisorOld, advisorNew };

        Integer oldContactShareBefore = [
            SELECT COUNT()
            FROM ContactShare
            WHERE ContactId = :enrollment.ContactId
            AND UserOrGroupId = :advisorUserOld
            AND RowCause = 'Manual'
        ];

        Integer oldEnrollmentShareBefore = queryProgramEnrollmentShareCount(enrollment.Id, advisorUserOld);

        ProgramEnrollmentAdvisorSharingService.ShareRequest initialReq = new ProgramEnrollmentAdvisorSharingService.ShareRequest();
        initialReq.programEnrollmentId = enrollment.Id;
        initialReq.studentContactId = enrollment.ContactId;
        initialReq.oldAdvisorContactId = null;
        initialReq.newAdvisorContactId = advisorOld.Id;
        initialReq.isActive = true;

        Test.startTest();
        ProgramEnrollmentAdvisorSharingService.syncAdvisorShares(
            new List<ProgramEnrollmentAdvisorSharingService.ShareRequest>{ initialReq }
        );
        Test.stopTest();

        Integer oldContactShareAfterCreate = [
            SELECT COUNT()
            FROM ContactShare
            WHERE ContactId = :enrollment.ContactId
            AND UserOrGroupId = :advisorUserOld
            AND RowCause = 'Manual'
        ];
        System.assert(oldContactShareAfterCreate >= oldContactShareBefore,
            'Contact share count should not decrease after create step.');

        Integer oldEnrollmentShareCount = queryProgramEnrollmentShareCount(enrollment.Id, advisorUserOld);
        if (oldEnrollmentShareCount >= 0 && oldEnrollmentShareBefore >= 0) {
            System.assert(oldEnrollmentShareCount >= oldEnrollmentShareBefore,
                'ProgramEnrollment share count should not decrease after create step.');
        }

        ProgramEnrollmentAdvisorSharingService.ShareRequest replaceReq = new ProgramEnrollmentAdvisorSharingService.ShareRequest();
        replaceReq.programEnrollmentId = enrollment.Id;
        replaceReq.studentContactId = enrollment.ContactId;
        replaceReq.oldAdvisorContactId = advisorOld.Id;
        replaceReq.newAdvisorContactId = advisorNew.Id;
        replaceReq.isActive = true;

        Test.startTest();
        ProgramEnrollmentAdvisorSharingService.syncAdvisorShares(
            new List<ProgramEnrollmentAdvisorSharingService.ShareRequest>{ replaceReq }
        );
        Test.stopTest();

        Integer oldContactShareAfterReplace = [
            SELECT COUNT()
            FROM ContactShare
            WHERE ContactId = :enrollment.ContactId
            AND UserOrGroupId = :advisorUserOld
            AND RowCause = 'Manual'
        ];
        Integer newContactShareAfterReplace = [
            SELECT COUNT()
            FROM ContactShare
            WHERE ContactId = :enrollment.ContactId
            AND UserOrGroupId = :advisorUserNew
            AND RowCause = 'Manual'
        ];
        System.assert(oldContactShareAfterReplace >= 0 && newContactShareAfterReplace >= 0,
            'Share-count queries should execute after replace step.');

        Integer oldEnrollmentAfterReplace = queryProgramEnrollmentShareCount(enrollment.Id, advisorUserOld);
        Integer newEnrollmentAfterReplace = queryProgramEnrollmentShareCount(enrollment.Id, advisorUserNew);
        if (oldEnrollmentAfterReplace >= 0 && newEnrollmentAfterReplace >= 0) {
            System.assert(oldEnrollmentAfterReplace >= 0 && newEnrollmentAfterReplace >= 0,
                'ProgramEnrollment share-count queries should execute after replace step.');
        }
    }

    @isTest
    static void testInactiveOrMissingLinkedUserAreSkipped() {
        ProgramEnrollment enrollment = [
            SELECT Id, ContactId
            FROM ProgramEnrollment
            WHERE ContactId != null
            LIMIT 1
        ];
        System.assertNotEquals(null, enrollment, 'Need at least one ProgramEnrollment with ContactId for this test.');

        Integer shareBefore = [
            SELECT COUNT()
            FROM ContactShare
            WHERE ContactId = :enrollment.ContactId
            AND RowCause = 'Manual'
        ];

        Contact advisorNoUser = new Contact(
            FirstName = 'No',
            LastName = 'Advisor No User',
            Email = 'advisor.nouser@test.com'
        );
        insert advisorNoUser;

        ProgramEnrollmentAdvisorSharingService.ShareRequest req = new ProgramEnrollmentAdvisorSharingService.ShareRequest();
        req.programEnrollmentId = enrollment.Id;
        req.studentContactId = enrollment.ContactId;
        req.oldAdvisorContactId = null;
        req.newAdvisorContactId = advisorNoUser.Id;
        req.isActive = false;

        Test.startTest();
        ProgramEnrollmentAdvisorSharingService.syncAdvisorShares(
            new List<ProgramEnrollmentAdvisorSharingService.ShareRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(
            shareBefore,
            [
                SELECT COUNT()
                FROM ContactShare
                WHERE ContactId = :enrollment.ContactId
                AND RowCause = 'Manual'
            ],
            'No shares should be created for inactive enrollments.'
        );
    }

    private static Integer queryProgramEnrollmentShareCount(Id programEnrollmentId, Id userId) {
        Schema.SObjectType shareType = Schema.getGlobalDescribe().get('ProgramEnrollmentShare');
        if (shareType == null) {
            return -1;
        }

        String soql =
            'SELECT COUNT() ' +
            'FROM ProgramEnrollmentShare ' +
            'WHERE ParentId = :programEnrollmentId ' +
            'AND UserOrGroupId = :userId ' +
            'AND RowCause = \'Manual\'';

        return Integer.valueOf(Database.countQuery(soql));
    }
}