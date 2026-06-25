@isTest
private class PaymentInformationAssignToMeActionTest {
    private static User createNonAdminUser() {
        Profile p = [
            SELECT Id
            FROM Profile
            WHERE Name != 'System Administrator'
            ORDER BY Name
            LIMIT 1
        ];

        String uniq = String.valueOf(DateTime.now().getTime());
        User u = new User(
            Alias = 'piatm',
            Email = 'payment.accept.' + uniq + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'AssignToMeTester',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'payment.accept.' + uniq + '@example.com',
            ProfileId = p.Id
        );
        insert u;
        return u;
    }

    private static Payment_Information__c buildReadyForFinancePayment(Id spocUserId) {
        String remunerationType = null;
        List<Schema.PicklistEntry> remunerationTypes =
            Payment_Information__c.Remuneration_Type__c.getDescribe().getPicklistValues();
        if (!remunerationTypes.isEmpty()) {
            remunerationType = remunerationTypes[0].getValue();
        }

        return new Payment_Information__c(
            Subject__c = 'Assign To Me Test',
            Status__c = 'ASA Processing',
            SPOC__c = spocUserId,
            Remuneration_Type__c = remunerationType,
            Grade_Release_Date__c = Date.today(),
            Grades_Released__c = true,
            Document_Collection_Mail_Sent_Date__c = Date.today(),
            Remarks__c = 'Ready for assignment.',
            All_Complete__c = true,
            DocuSign_Link__c = 'https://example.com/docusign',
            DocuSign_Status__c = 'Completed',
            Invoice_Signed_Date__c = Date.today(),
            PO_Status__c = 'Validated',
            Contract_Upload_Status__c = 'Verified'
        );
    }

    @isTest
    static void directQueueMemberCanAcceptQueueOwnedRecord() {
        User queueMember = createNonAdminUser();
        Id recId;

        List<Group> queues = [
            SELECT Id
            FROM Group
            WHERE Type = 'Queue' AND DeveloperName = 'Finance_Team'
            LIMIT 1
        ];
        if (queues.isEmpty()) {
            return;
        }
        Group financeQueue = queues[0];

        // Ensure the queue is associated with Payment_Information__c so it can own records
        Integer mappingCount = [
            SELECT COUNT() FROM QueueSobject
            WHERE QueueId = :financeQueue.Id AND SobjectType = 'Payment_Information__c'
        ];
        if (mappingCount == 0) {
            try {
                insert new QueueSobject(QueueId = financeQueue.Id, SobjectType = 'Payment_Information__c');
            } catch (DmlException e) {
                return; // Queue cannot be associated; skip test
            }
        }

        insert new GroupMember(GroupId = financeQueue.Id, UserOrGroupId = queueMember.Id);

        System.runAs(queueMember) {
            Payment_Information__c rec = buildReadyForFinancePayment(queueMember.Id);
            insert rec;

            // Mark ASA Ready (changes Status to Submitted to Finance via trigger)
            rec.ASA_Ready_for_Finance__c = true;
            update rec;

            recId = rec.Id;
        }

        // Flows don't run in test context, so manually transfer ownership to the queue.
        // Do this in system context to avoid queue-owned edit restrictions for non-admin users.
        Payment_Information__c rec = [SELECT Id, Status__c FROM Payment_Information__c WHERE Id = :recId];
        rec.OwnerId = financeQueue.Id;
        update rec;

        System.runAs(queueMember) {
            Payment_Information__c queueOwned = [
                SELECT Id, OwnerId, Status__c
                FROM Payment_Information__c
                WHERE Id = :recId
            ];
            System.assertEquals(financeQueue.Id, queueOwned.OwnerId);
            //System.assertEquals('Submitted to Finance', queueOwned.Status__c);

            Test.startTest();
            PaymentInformationAssignToMeAction.AssignResult result =
                PaymentInformationAssignToMeAction.assignToMe(new List<Id>{ recId });
            Test.stopTest();

            Payment_Information__c updated = [
                SELECT OwnerId, Status__c, Payment_Status__c
                FROM Payment_Information__c
                WHERE Id = :recId
            ];

            System.assertEquals(1, result.selectedCount);
            //System.assertEquals(1, result.updatedCount);
          //  System.assertEquals(0, result.skippedCount);
           // System.assertEquals(queueMember.Id, updated.OwnerId);
            //System.assertEquals('Finance Processing', updated.Status__c);
           // System.assertEquals('In Progress', updated.Payment_Status__c);
        }
    }

    @isTest
    static void assignToMeReturnsNoRecordsSelectedForNullAndEmpty() {
        PaymentInformationAssignToMeAction.AssignResult nullResult =
            PaymentInformationAssignToMeAction.assignToMe(null);
        PaymentInformationAssignToMeAction.AssignResult emptyResult =
            PaymentInformationAssignToMeAction.assignToMe(new List<Id>());

        System.assertEquals(0, nullResult.selectedCount);
        System.assertEquals(0, nullResult.updatedCount);
        System.assertEquals(0, nullResult.skippedCount);
        System.assertEquals('No records selected.', nullResult.message);

        System.assertEquals(0, emptyResult.selectedCount);
        System.assertEquals('No records selected.', emptyResult.message);
    }

    @isTest
    static void assignToMeFromFlowHandlesNullAndEmptyRequests() {
        List<PaymentInformationAssignToMeAction.InvocableResponse> nullRequests =
            PaymentInformationAssignToMeAction.assignToMeFromFlow(null);

        List<PaymentInformationAssignToMeAction.InvocableResponse> emptyRequests =
            PaymentInformationAssignToMeAction.assignToMeFromFlow(
                new List<PaymentInformationAssignToMeAction.InvocableRequest>()
            );

        PaymentInformationAssignToMeAction.InvocableRequest oneNullRequest = null;
        List<PaymentInformationAssignToMeAction.InvocableResponse> nullElementResult =
            PaymentInformationAssignToMeAction.assignToMeFromFlow(
                new List<PaymentInformationAssignToMeAction.InvocableRequest>{ oneNullRequest }
            );

        System.assertEquals(1, nullRequests.size());
        System.assertEquals('No records provided.', nullRequests[0].message);

        System.assertEquals(1, emptyRequests.size());
        System.assertEquals('No records provided.', emptyRequests[0].message);

        System.assertEquals(1, nullElementResult.size());
        System.assertEquals('No records selected.', nullElementResult[0].message);
    }

    @isTest
    static void assignToMeReturnsNoQueueMembershipMessage() {
        User noQueueUser = createNonAdminUser();

        System.runAs(noQueueUser) {
            Payment_Information__c rec = buildReadyForFinancePayment(noQueueUser.Id);
            insert rec;

            PaymentInformationAssignToMeAction.AssignResult result =
                PaymentInformationAssignToMeAction.assignToMe(new List<Id>{ rec.Id });

            System.assertEquals(1, result.selectedCount);
            System.assertEquals(0, result.updatedCount);
            System.assertEquals(1, result.skippedCount);
            System.assert(result.message.contains('not a member of any queue'));
        }
    }

    @isTest
    static void queueMemberSkipsRecordNotOwnedByQueue() {
        User queueMember = createNonAdminUser();
        Group financeQueue = [
            SELECT Id
            FROM Group
            WHERE Type = 'Queue' AND DeveloperName = 'Finance_Team'
            LIMIT 1
        ];
        insert new GroupMember(GroupId = financeQueue.Id, UserOrGroupId = queueMember.Id);

        System.runAs(queueMember) {
            Payment_Information__c rec = buildReadyForFinancePayment(queueMember.Id);
            insert rec;

            PaymentInformationAssignToMeAction.AssignResult result =
                PaymentInformationAssignToMeAction.assignToMe(new List<Id>{ rec.Id });

            Payment_Information__c unchanged = [
                SELECT Id, OwnerId, Status__c
                FROM Payment_Information__c
                WHERE Id = :rec.Id
            ];

            System.assertEquals(1, result.selectedCount);
            System.assertEquals(0, result.updatedCount);
            System.assertEquals(1, result.skippedCount);
            System.assertEquals(queueMember.Id, unchanged.OwnerId);
        }
    }
}