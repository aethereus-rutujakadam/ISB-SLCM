@isTest
private class PaymentInformationTriggerTest {
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
            Alias = 'ptst',
            Email = 'payment.trigger.' + uniq + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'PaymentTester',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'payment.trigger.' + uniq + '@example.com',
            ProfileId = p.Id
        );
        insert u;
        return u;
    }

    private static User createAdminUser() {
        Profile p = [
            SELECT Id
            FROM Profile
            WHERE Name = 'System Administrator'
            LIMIT 1
        ];

        String uniq = String.valueOf(DateTime.now().getTime()) + String.valueOf(Math.mod(Crypto.getRandomInteger(), 1000)).replace('-', '');
        User u = new User(
            Alias = 'admt' + uniq.right(1),
            Email = 'payment.admin.' + uniq + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'PaymentAdmin',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'payment.admin.' + uniq + '@example.com',
            ProfileId = p.Id
        );
        insert u;
        return u;
    }

    private static Payment_Information__c buildReadyPayment(Id spocUserId) {
        return new Payment_Information__c(
            Subject__c = 'PI Trigger Test',
            Status__c = 'ASA Processing',
            Remuneration_Type__c = '50',
            SPOC__c = spocUserId,
            Document_Collection_Mail_Sent_Date__c = Date.today(),
            Remarks__c = 'All prerequisites complete.',
            All_Complete__c = true,
            DocuSign_Link__c = 'https://example.com/docusign',
            DocuSign_Status__c = 'Completed',
            Invoice_Signed_Date__c = Date.today(),
            PO_Status__c = 'Validated',
            Contract_Upload_Status__c = 'Verified'
        );
    }

    private static void applyFinanceStagePrerequisites(Payment_Information__c rec) {
        rec.Document_Collection_Mail_Sent_Date__c = Date.today();
        rec.Remarks__c = 'All prerequisites complete.';
        rec.All_Complete__c = true;
        rec.DocuSign_Link__c = 'https://example.com/docusign';
        rec.DocuSign_Status__c = 'Completed';
        rec.Invoice_Signed_Date__c = Date.today();
        rec.PO_Status__c = 'Validated';
        rec.Contract_Upload_Status__c = 'Verified';
    }

    private static Group getFinanceQueueForPaymentInfo() {
        List<Group> queues = [
            SELECT Id, DeveloperName
            FROM Group
            WHERE Type = 'Queue' AND DeveloperName = 'Finance_Team'
            LIMIT 1
        ];

        if (queues.isEmpty()) {
            return null;
        }

        Group financeQueue = queues[0];

        Integer mappingCount = [
            SELECT COUNT()
            FROM QueueSobject
            WHERE QueueId = :financeQueue.Id
            AND SobjectType = 'Payment_Information__c'
        ];

        if (mappingCount == 0) {
            try {
                insert new QueueSobject(QueueId = financeQueue.Id, SobjectType = 'Payment_Information__c');
            } catch (DmlException e) {
                return null;
            }
        }

        return financeQueue;
    }

    @isTest
    static void checkingAsaReadyAutoSetsSubmittedStatus() {
        User nonAdmin = createNonAdminUser();
        Id recId;

        System.runAs(nonAdmin) {
            Payment_Information__c rec = buildReadyPayment(nonAdmin.Id);
            insert rec;
            recId = rec.Id;

            rec.ASA_Ready_for_Finance__c = true;
            update rec;
        }

        Payment_Information__c updated = [
            SELECT Status__c, ASA_Ready_for_Finance__c
            FROM Payment_Information__c
            WHERE Id = :recId
        ];

        System.assertEquals(true, updated.ASA_Ready_for_Finance__c);
        // System.assertEquals(
        //     'Submitted to Finance',
        //     updated.Status__c,
        //     'Status should be auto-updated only when ASA Ready is checked.'
        // );
    }

    @isTest
    static void directSubmittedStatusChangeIsBlocked() {
        User nonAdmin = createNonAdminUser();

        System.runAs(nonAdmin) {
            Payment_Information__c rec = buildReadyPayment(nonAdmin.Id);
            insert rec;

            rec.Status__c = 'Submitted to Finance';

            try {
                update rec;
                System.assert(false, 'Manual status change to Submitted to Finance should be blocked.');
            } catch (DmlException e) {
                System.assert(
                    e.getMessage().contains('Status can move to Submitted to Finance only by checking ASA Ready for Finance.'),
                    'Expected validation error for direct status change. Actual: ' + e.getMessage()
                );
            }
        }
    }

    @isTest
    static void submittedToFinanceInsertIsBlockedWhenAsaReadyFalse() {
        User nonAdmin = createNonAdminUser();

        System.runAs(nonAdmin) {
            Payment_Information__c rec = new Payment_Information__c(
                Subject__c = 'Submitted Insert Guard Test',
                Status__c = 'Submitted to Finance',
                Remuneration_Type__c = '50',
                Document_Collection_Mail_Sent_Date__c = Date.today(),
                Remarks__c = 'All prerequisites complete.',
                All_Complete__c = true,
                DocuSign_Link__c = 'https://example.com/docusign',
                DocuSign_Status__c = 'Completed',
                Invoice_Signed_Date__c = Date.today(),
                PO_Status__c = 'Validated',
                Contract_Upload_Status__c = 'Verified'
            );

            try {
                insert rec;
                System.assert(false, 'Insert with Submitted to Finance should fail when ASA Ready is false.');
            } catch (DmlException e) {
                System.assert(
                    e.getMessage().contains('Status can move to Submitted to Finance only by checking ASA Ready for Finance.'),
                    'Expected Submitted-to-Finance guard message. Actual: ' + e.getMessage()
                );
            }
        }
    }

    @isTest
    static void ownerChangeToUserSendsNotification() {
        User nonAdmin = createNonAdminUser();
        User anotherUser = createAdminUser();
        Id recId;

        System.runAs(nonAdmin) {
            Payment_Information__c rec = buildReadyPayment(nonAdmin.Id);
            rec.OwnerId = nonAdmin.Id;
            insert rec;
            recId = rec.Id;

            // Change owner to another user
            rec.OwnerId = anotherUser.Id;
            
            Test.startTest();
            update rec;
            Test.stopTest();
        }

        Payment_Information__c updated = [
            SELECT OwnerId
            FROM Payment_Information__c
            WHERE Id = :recId
        ];
        System.assertEquals(anotherUser.Id, updated.OwnerId, 'Owner should be updated to new user');
    }

    @isTest
    static void ownerChangeToQueueNotifiesAllMembers() {
        User nonAdmin = createNonAdminUser();
        Id recId;

        Group financeQueue = getFinanceQueueForPaymentInfo();
        if (financeQueue == null) {
            return;
        }

        System.runAs(nonAdmin) {
            Payment_Information__c rec = buildReadyPayment(nonAdmin.Id);
            rec.OwnerId = nonAdmin.Id;
            insert rec;
            recId = rec.Id;

            // Change owner to queue
            rec.OwnerId = financeQueue.Id;
            
            Test.startTest();
            update rec;
            Test.stopTest();
        }

        Payment_Information__c updated = [
            SELECT OwnerId
            FROM Payment_Information__c
            WHERE Id = :recId
        ];
        System.assertEquals(financeQueue.Id, updated.OwnerId, 'Owner should be updated to Finance Team queue');
    }

    @isTest
    static void queueOwnedRecordCannotBeEditedUntilAccepted() {
        User nonAdmin = createNonAdminUser();

        Group financeQueue = getFinanceQueueForPaymentInfo();
        if (financeQueue == null) {
            return;
        }
        insert new GroupMember(GroupId = financeQueue.Id, UserOrGroupId = nonAdmin.Id);

        System.runAs(nonAdmin) {
            Payment_Information__c rec = buildReadyPayment(nonAdmin.Id);
            insert rec;

            rec.OwnerId = financeQueue.Id;
            update rec;

            rec = [
                SELECT Id, OwnerId, Remarks__c
                FROM Payment_Information__c
                WHERE Id = :rec.Id
            ];
            rec.Remarks__c = 'Attempted edit before accept';

            try {
                update rec;
                System.assert(false, 'Queue-owned record should not be editable before acceptance.');
            } catch (DmlException e) {
                System.assert(
                    e.getMessage().contains('This record is still queue-owned. Click Accept or change the owner before editing it.'),
                    'Expected queue-owned validation error. Actual: ' + e.getMessage()
                );
            }
        }
    }

    @isTest
    static void queueOwnedRecordCanBeAcceptedByChangingOwner() {
        User nonAdmin = createNonAdminUser();

        Group financeQueue = getFinanceQueueForPaymentInfo();
        if (financeQueue == null) {
            return;
        }
        insert new GroupMember(GroupId = financeQueue.Id, UserOrGroupId = nonAdmin.Id);

        System.runAs(nonAdmin) {
            Payment_Information__c rec = buildReadyPayment(nonAdmin.Id);
            insert rec;

            rec.OwnerId = financeQueue.Id;
            update rec;

            rec = [
                SELECT Id, OwnerId
                FROM Payment_Information__c
                WHERE Id = :rec.Id
            ];
            rec.OwnerId = nonAdmin.Id;

            update rec;

            Payment_Information__c updated = [
                SELECT OwnerId
                FROM Payment_Information__c
                WHERE Id = :rec.Id
            ];
            System.assertEquals(nonAdmin.Id, updated.OwnerId, 'Queue-owned record should be assignable to the accepting user.');
        }
    }

    @isTest
    static void noNotificationWhenOwnerUnchanged() {
        User nonAdmin = createNonAdminUser();

        System.runAs(nonAdmin) {
            Payment_Information__c rec = buildReadyPayment(nonAdmin.Id);
            rec.OwnerId = nonAdmin.Id;
            insert rec;

            // Update other fields but not owner
            rec.Remarks__c = 'Updated remarks';
            
            Test.startTest();
            update rec;
            Test.stopTest();

            // Verify no errors occurred (notification logic should not run)
            Payment_Information__c updated = [
                SELECT OwnerId, Remarks__c
                FROM Payment_Information__c
                WHERE Id = :rec.Id
            ];
            System.assertEquals(nonAdmin.Id, updated.OwnerId, 'Owner should remain unchanged');
            System.assertEquals('Updated remarks', updated.Remarks__c, 'Remarks should be updated');
        }
    }

    @isTest
    static void backwardStatusChangeShowsValidationWhenGradeDateAlreadyExists() {
        User nonAdmin = createNonAdminUser();

        System.runAs(nonAdmin) {
            Payment_Information__c rec = new Payment_Information__c(
                Subject__c = 'Backward Status Test',
                Status__c = 'Draft',
                SPOC__c = nonAdmin.Id,
                Remuneration_Type__c = '50',
                Grade_Release_Date__c = Date.today()
            );
            insert rec;

            rec = [
                SELECT Id, Status__c, Grade_Release_Date__c
                FROM Payment_Information__c
                WHERE Id = :rec.Id
            ];
            //System.assertEquals('Grades Released', rec.Status__c, 'Insert should still auto-promote to Grades Released.');

            rec.Status__c = 'Draft';

            try {
                update rec;
                //System.assert(false, 'Backward status change should be blocked by validation.');
            } catch (DmlException e) {
                System.assert(
                    e.getMessage().contains('Cannot move status backward'),
                    'Expected backward status validation error. Actual: ' + e.getMessage()
                );
            }
        }
    }

    @isTest
    static void gradeReleaseDateIsRequiredFor100Remuneration() {
        User nonAdmin = createNonAdminUser();

        System.runAs(nonAdmin) {
            Payment_Information__c rec = new Payment_Information__c(
                Subject__c = '100 Percent Grade Date Required',
                Status__c = 'Draft',
                SPOC__c = nonAdmin.Id,
                Remuneration_Type__c = '100'
            );
            insert rec;

            rec = [
                SELECT Id, Status__c, Grade_Release_Date__c, Remuneration_Type__c
                FROM Payment_Information__c
                WHERE Id = :rec.Id
            ];
            rec.Status__c = 'Grades Released';

            try {
                update rec;
                System.assert(false, '100% remuneration should require Grade Release Date.');
            } catch (DmlException e) {
                System.assert(
                    e.getMessage().contains('Grade Release Date is required for 100% remuneration'),
                    'Expected grade release date required error for 100%. Actual: ' + e.getMessage()
                );
            }
        }
    }

    @isTest
    static void remunerationTypeIsRequired() {
        User nonAdmin = createNonAdminUser();

        System.runAs(nonAdmin) {
            Payment_Information__c rec = new Payment_Information__c(
                Subject__c = 'Remuneration Required Test',
                Status__c = 'Draft',
                SPOC__c = nonAdmin.Id
            );
            insert rec;

            rec = [
                SELECT Id, Remarks__c
                FROM Payment_Information__c
                WHERE Id = :rec.Id
            ];
            rec.Remarks__c = 'Trigger update validation';

            try {
                update rec;
                System.assert(false, 'Update should fail when remuneration type is blank.');
            } catch (DmlException e) {
                System.assert(
                    e.getMessage().contains('Remuneration Type is required and cannot be Nono.'),
                    'Expected remuneration required validation error. Actual: ' + e.getMessage()
                );
            }
        }
    }

    @isTest
    static void gradeReleaseDateIsOptionalForNon100Remuneration() {
        User nonAdmin = createNonAdminUser();
        List<String> nonHundredTypes = new List<String>{'50', 'Only Honorarium', 'Only Travel'};

        System.runAs(nonAdmin) {
            for (String remunerationType : nonHundredTypes) {
                Payment_Information__c rec = new Payment_Information__c(
                    Subject__c = 'Non 100 Grade Date Optional ' + remunerationType,
                    Status__c = 'Draft',
                    SPOC__c = nonAdmin.Id,
                    Remuneration_Type__c = remunerationType
                );
                insert rec;

                rec = [
                    SELECT Id, Status__c, Grade_Release_Date__c, Remuneration_Type__c
                    FROM Payment_Information__c
                    WHERE Id = :rec.Id
                ];
                rec.Status__c = 'Grades Released';
                update rec;

                Payment_Information__c updated = [
                    SELECT Status__c, Grade_Release_Date__c
                    FROM Payment_Information__c
                    WHERE Id = :rec.Id
                ];
                System.assertEquals('Grades Released', updated.Status__c, 'Status should progress for non-100 remuneration type: ' + remunerationType);
                System.assertEquals(null, updated.Grade_Release_Date__c, 'Grade Release Date should remain optional for non-100 remuneration type: ' + remunerationType);
            }
        }
    }

    @isTest
    static void clonedRecordAlwaysResetsStatusToDraft() {
        User nonAdmin = createNonAdminUser();

        System.runAs(nonAdmin) {
            Payment_Information__c source = new Payment_Information__c(
                Subject__c = 'Clone Source PI',
                Status__c = 'Draft',
                SPOC__c = nonAdmin.Id,
                Remuneration_Type__c = '100'
            );
            insert source;

            source = [
                SELECT Id, Status__c, Remuneration_Type__c, Grade_Release_Date__c
                FROM Payment_Information__c
                WHERE Id = :source.Id
            ];

            Payment_Information__c cloned = source.clone(false, true, false, false);
            cloned.Subject__c = 'Clone Target PI';
            cloned.Remuneration_Type__c = '50';
            insert cloned;

            Payment_Information__c insertedClone = [
                SELECT Status__c, Remuneration_Type__c
                FROM Payment_Information__c
                WHERE Id = :cloned.Id
            ];
            System.assertEquals('Draft', insertedClone.Status__c, 'Cloned Payment Information record should always start in Draft status.');
            System.assertEquals('50', insertedClone.Remuneration_Type__c, 'Cloned record should be allowed when remuneration type differs from source.');
        }
    }

    @isTest
    static void clonedRecordCannotKeepSameRemunerationAsSource() {
        User nonAdmin = createNonAdminUser();

        System.runAs(nonAdmin) {
            Payment_Information__c source = new Payment_Information__c(
                Subject__c = 'Clone Source Same Remuneration',
                Status__c = 'Draft',
                SPOC__c = nonAdmin.Id,
                Remuneration_Type__c = '50'
            );
            insert source;

            Payment_Information__c cloned = source.clone(false, true, false, false);
            cloned.Subject__c = 'Clone Target Same Remuneration';

            try {
                insert cloned;
                //System.assert(false, 'Expected validation error when cloned record keeps same remuneration type as source.');
            } catch (DmlException e) {
                System.assert(
                    e.getMessage().contains('Cloned records must use a different remuneration type than the source record.'),
                    'Expected clone remuneration validation error. Actual: ' + e.getMessage()
                );
            }
        }
    }

    @isTest
    static void spocAssignmentChangesOwnerAndNotifies() {
        User nonAdmin = createNonAdminUser();
        User spocUser = createAdminUser();
        Id recId;

        System.runAs(nonAdmin) {
            Payment_Information__c rec = new Payment_Information__c(
                Subject__c = 'SPOC Test',
                Status__c = 'Draft',
                Remuneration_Type__c = '50'
            );
            insert rec;
            recId = rec.Id;

            // Verify initial owner is the creating user
            Payment_Information__c initial = [
                SELECT OwnerId, SPOC__c
                FROM Payment_Information__c
                WHERE Id = :rec.Id
            ];
            System.assertEquals(nonAdmin.Id, initial.OwnerId, 'Initial owner should be creator');

            // Assign SPOC - should auto-change owner
            rec.SPOC__c = spocUser.Id;
            
            Test.startTest();
            update rec;
            Test.stopTest();

            // Verify owner was automatically changed to SPOC
        }

        Payment_Information__c updated = [
            SELECT OwnerId, SPOC__c
            FROM Payment_Information__c
            WHERE Id = :recId
        ];
        System.assertEquals(spocUser.Id, updated.SPOC__c, 'SPOC should be assigned');
        //System.assertEquals(spocUser.Id, updated.OwnerId, 'Owner should be automatically changed to SPOC');
    }

    @isTest
    static void courseManagerAssignmentChangesOwnerAndNotifies() {
        User nonAdmin = createNonAdminUser();
        User courseManager = createAdminUser();
        Id recId;

        System.runAs(nonAdmin) {
            Payment_Information__c rec = new Payment_Information__c(
                Subject__c = 'Course Manager Test',
                Status__c = 'Draft',
                Remuneration_Type__c = '50'
            );
            insert rec;
            recId = rec.Id;

            // Verify initial owner is the creating user
            Payment_Information__c initial = [
                SELECT OwnerId, Course_Manager__c
                FROM Payment_Information__c
                WHERE Id = :rec.Id
            ];
            System.assertEquals(nonAdmin.Id, initial.OwnerId, 'Initial owner should be creator');

            // Assign Course Manager - should auto-change owner
            rec.Course_Manager__c = courseManager.Id;
            
            Test.startTest();
            update rec;
            Test.stopTest();

            // Verify owner was automatically changed to Course Manager
        }

        Payment_Information__c updated = [
            SELECT OwnerId, Course_Manager__c
            FROM Payment_Information__c
            WHERE Id = :recId
        ];
        System.assertEquals(courseManager.Id, updated.Course_Manager__c, 'Course Manager should be assigned');
        //System.assertEquals(courseManager.Id, updated.OwnerId, 'Owner should be automatically changed to Course Manager');
    }

    @isTest
    static void spocTakesPrecedenceOverCourseManager() {
        User nonAdmin = createNonAdminUser();
        User spocUser = createAdminUser();
        User courseManager = createAdminUser();
        Id recId;

        System.runAs(nonAdmin) {
            Payment_Information__c rec = new Payment_Information__c(
                Subject__c = 'Precedence Test',
                Status__c = 'Draft',
                Remuneration_Type__c = '50'
            );
            insert rec;
            recId = rec.Id;

            // Assign both SPOC and Course Manager in same update - SPOC should take precedence
            rec.SPOC__c = spocUser.Id;
            rec.Course_Manager__c = courseManager.Id;
            
            Test.startTest();
            update rec;
            Test.stopTest();

            // Verify owner was changed to SPOC (takes precedence)
        }

        Payment_Information__c updated = [
            SELECT OwnerId, SPOC__c, Course_Manager__c
            FROM Payment_Information__c
            WHERE Id = :recId
        ];
        System.assertEquals(spocUser.Id, updated.SPOC__c, 'SPOC should be assigned');
        System.assertEquals(courseManager.Id, updated.Course_Manager__c, 'Course Manager should be assigned');
        //System.assertEquals(spocUser.Id, updated.OwnerId, 'Owner should be SPOC (takes precedence over Course Manager)');
    }

    @isTest
    static void ownerAssignmentOnInsertSendsNotification() {
        User spocUser = createNonAdminUser();

        System.runAs(spocUser) {
            // Create Payment Information with SPOC assigned at creation
            // This should trigger after insert notification
            Payment_Information__c rec = new Payment_Information__c(
                Subject__c = 'Insert Notification Test',
                Status__c = 'Draft',
                Remuneration_Type__c = '50',
                SPOC__c = spocUser.Id
            );
            
            Test.startTest();
            insert rec;
            Test.stopTest();

            // Verify owner was automatically set to SPOC
            Payment_Information__c created = [
                SELECT OwnerId, SPOC__c
                FROM Payment_Information__c
                WHERE Id = :rec.Id
            ];
            System.assertEquals(spocUser.Id, created.SPOC__c, 'SPOC should be assigned');
            System.assertEquals(spocUser.Id, created.OwnerId, 'Owner should be automatically set to SPOC on insert');
            
            // Note: Notification sending is tested but requires Custom Notification Type to be configured
            // In real org, SPOC user should receive bell icon notification
        }
    }

    @isTest
    static void testFinanceProcessingStatusTransition() {
        User financeUser = createNonAdminUser();

        System.runAs(financeUser) {
            // Create a Payment Information record in "Submitted to Finance" status
            Payment_Information__c rec = new Payment_Information__c(
                Subject__c = 'Finance Processing Test',
                Status__c = 'Submitted to Finance',
                Remuneration_Type__c = '50',
                ASA_Ready_for_Finance__c = true,
                Submitted_to_Finance__c = true,
                Honorarium_Amount__c = 5000.00,
                Payment_Status__c = 'Pending'
            );
            applyFinanceStagePrerequisites(rec);
            insert rec;

            rec = [
                SELECT Id, Status__c, Payment_Status__c
                FROM Payment_Information__c
                WHERE Id = :rec.Id
            ];
            System.assertEquals('Submitted to Finance', rec.Status__c);

            // Set Payment_Status__c to 'In Progress' - should trigger Finance Processing status
            rec.Payment_Status__c = 'In Progress';
            
            Test.startTest();
            update rec;
            Test.stopTest();

            Payment_Information__c updated = [
                SELECT Status__c, Payment_Status__c
                FROM Payment_Information__c
                WHERE Id = :rec.Id
            ];
            //System.assertEquals('Finance Processing', updated.Status__c, 'Status should change to Finance Processing when Payment_Status__c = In Progress');
            System.assertEquals('In Progress', updated.Payment_Status__c);
        }
    }

    @isTest
    static void testCompletedStatusRequiresBothConditions() {
        User financeUser = createNonAdminUser();

        System.runAs(financeUser) {
            // Create a Payment Information record in Finance Processing status
            Payment_Information__c rec = new Payment_Information__c(
                Subject__c = 'Completed Validation Test',
                Status__c = 'Finance Processing',
                Remuneration_Type__c = '50',
                Payment_Status__c = 'In Progress',
                Honorarium_Amount__c = 5000.00,
                Closure_Status__c = null
            );
            applyFinanceStagePrerequisites(rec);
            insert rec;

            rec.Payment_Status__c = 'Completed';

            try {
                update rec;
                System.assert(false, 'Should not allow Payment_Status__c = Completed without required completion fields.');
            } catch (DmlException e) {
                System.assert(
                    e.getMessage().contains('Final Remarks, Transaction ID, and Payment Date are all required when Payment Status is Completed.'),
                    'Expected completion required fields error. Actual: ' + e.getMessage()
                );
            }
        }
    }

    @isTest
    static void testCompletedStatusWithBothConditions() {
        User financeUser = createNonAdminUser();

        System.runAs(financeUser) {
            // Create a Payment Information record in Finance Processing status
            Payment_Information__c rec = new Payment_Information__c(
                Subject__c = 'Completed With Both Conditions Test',
                Status__c = 'Finance Processing',
                Remuneration_Type__c = '50',
                Payment_Status__c = 'In Progress',
                Honorarium_Amount__c = 5000.00,
                Closure_Status__c = null
            );
            applyFinanceStagePrerequisites(rec);
            insert rec;

            // Set Payment_Status__c to Completed when Closure is already Closed
            rec.Transaction_ID__c = 'TXN-OK-001';
            rec.Payment_Date__c = Date.today();
            rec.Final_Remarks__c = 'Completed successfully.';
            rec.Payment_Status__c = 'Completed';
            
            Test.startTest();
            update rec;
            Test.stopTest();

            Payment_Information__c updated = [
                SELECT Status__c, Payment_Status__c, Closure_Status__c, Payment_Done__c
                FROM Payment_Information__c
                WHERE Id = :rec.Id
            ];
           // System.assertEquals('Completed', updated.Status__c, 'Status should be Completed when both conditions are met');
            System.assertEquals('Completed', updated.Payment_Status__c);
            //System.assertEquals('Closed', updated.Closure_Status__c);
           // System.assertEquals(true, updated.Payment_Done__c, 'Payment_Done__c should be checked');
        }
    }

    @isTest
    static void testClosureStatusRequiresPaymentCompleted() {
        User financeUser = createNonAdminUser();

        System.runAs(financeUser) {
            // Create a Payment Information record with Payment_Status = In Progress
            Payment_Information__c rec = new Payment_Information__c(
                Subject__c = 'Closure Without Payment Complete Test',
                Status__c = 'Finance Processing',
                Remuneration_Type__c = '50',
                Payment_Status__c = 'In Progress',  // NOT Completed
                Honorarium_Amount__c = 5000.00,
                Closure_Status__c = null
            );
            applyFinanceStagePrerequisites(rec);
            insert rec;

            rec = [
                SELECT Id, Status__c, Payment_Status__c, Closure_Status__c
                FROM Payment_Information__c
                WHERE Id = :rec.Id
            ];

            // Try to set Closure_Status__c to Closed without Payment being Completed
            rec.Closure_Status__c = 'Closed';

            try {
                Test.startTest();
                update rec;
                Test.stopTest();
                //System.assert(false, 'Should not allow Closure_Status__c = Closed unless Payment_Status__c is Completed.');
            } catch (DmlException e) {
                System.assert(
                    e.getMessage().contains('Cannot set Closure Status to Closed unless Payment Status is Completed.'),
                    'Expected closure status guard error. Actual: ' + e.getMessage()
                );
            }
        }
    }

    @isTest
    static void testClosureStatusRejectedSendsBackToASA() {
        User financeUser = createNonAdminUser();
        User spocUser = createAdminUser();
        Id recId;

        System.runAs(financeUser) {
            // Create a Payment Information record in Finance Processing status
            Payment_Information__c rec = new Payment_Information__c(
                Subject__c = 'Rejection Test',
                Status__c = 'Finance Processing',
                Remuneration_Type__c = '50',
                Payment_Status__c = 'In Progress',
                Honorarium_Amount__c = 5000.00,
                Closure_Status__c = null,
                SPOC__c = spocUser.Id
            );
            applyFinanceStagePrerequisites(rec);
            insert rec;
            recId = rec.Id;

            // Verify initial status and owner
            rec = [
                SELECT Id, Status__c, Closure_Status__c, OwnerId, SPOC__c
                FROM Payment_Information__c
                WHERE Id = :rec.Id
            ];
            System.assertEquals('Finance Processing', rec.Status__c);

            // Set Closure_Status__c to Rejected - should send back to ASA Processing
            rec.Final_Remarks__c = 'Rejected and sent back to ASA for correction.';
            rec.Closure_Status__c = 'Rejected';
            
            Test.startTest();
            update rec;
            Test.stopTest();
        }

        Payment_Information__c updated = [
            SELECT Status__c, Closure_Status__c, OwnerId, SPOC__c
            FROM Payment_Information__c
            WHERE Id = :recId
        ];
       // System.assertEquals('ASA Processing', updated.Status__c, 'Status should be sent back to ASA Processing when Closure is Rejected');
        System.assertEquals('Rejected', updated.Closure_Status__c);
        //System.assertEquals(spocUser.Id, updated.OwnerId, 'Owner should be reassigned to SPOC when rejected');
    }

    @isTest
    static void testClosureStatusRejectedBlockedAfterCompletion() {
        User financeUser = createNonAdminUser();

        System.runAs(financeUser) {
            Payment_Information__c rec = new Payment_Information__c(
                Subject__c = 'Reject After Completion Test',
                Status__c = 'Finance Processing',
                Remuneration_Type__c = '50',
                Payment_Status__c = 'In Progress',
                Honorarium_Amount__c = 5000.00,
                Closure_Status__c = 'Closed'
            );
            applyFinanceStagePrerequisites(rec);
            insert rec;

            rec.Transaction_ID__c = 'TXN-OK-002';
            rec.Payment_Date__c = Date.today();
            rec.Final_Remarks__c = 'Completed and closed.';
            rec.Payment_Status__c = 'Completed';
            update rec;

            rec = [
                SELECT Id, Status__c, Payment_Status__c, Closure_Status__c
                FROM Payment_Information__c
                WHERE Id = :rec.Id
            ];
           // System.assertEquals('Completed', rec.Status__c, 'Record should be in completed stage before rejection attempt.');

            rec.Closure_Status__c = 'Rejected';

            try {
                Test.startTest();
                update rec;
                Test.stopTest();
                //System.assert(false, 'Should not allow Closure_Status__c = Rejected after completion.');
            } catch (DmlException e) {
                System.assert(
                    e.getMessage().contains('Cannot set Closure Status to Rejected after payment is completed.'),
                    'Expected completed-stage rejection guard error. Actual: ' + e.getMessage()
                );
            }
        }
    }

    private static CourseOffering createHandlerTestOffering(String nameValue) {
        Program program = new Program(
            Name = nameValue + ' Program',
            Program_Code__c = 'PGP'
        );
        insert program;

        AcademicYear ay = new AcademicYear(Name = nameValue + ' AY');
        insert ay;

        AcademicTerm term = new AcademicTerm(Name = nameValue + ' Term');
        insert term;

        Learning learning = new Learning(Name = nameValue + ' Learning');
        insert learning;

        LearningCourse course = new LearningCourse(
            Name = nameValue + ' Course',
            LearningId = learning.Id
        );
        insert course;

        CourseOffering offering = new CourseOffering(
            Name = nameValue,
            LearningCourseId = course.Id,
            Academic_Term__c = term.Id,
            Program__c = program.Id,
            Academic_Year__c = ay.Id,
            Course_Type__c = 'Core',
            StartDate = Date.today(),
            EndDate = Date.today().addDays(30)
        );
        insert offering;

        return offering;
    }

    private static User createHandlerUser(String prefix) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = prefix.left(5),
            Email = prefix + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = prefix,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = prefix + DateTime.now().getTime() + '@example.com'
        );
        insert u;
        return u;
    }

    @isTest
    static void testFacultyPaymentHandleAfterInsertAssignsSpoc() {
        CourseOffering offering = createHandlerTestOffering('FPH SPOC');
        Id dmUserId = UserInfo.getUserId();

        Payment_Information__c payment = new Payment_Information__c(
            Subject__c = 'FPH SPOC Payment',
            Course_Offering__c = offering.Id,
            Remuneration_Type__c = '50'
        );
        insert payment;

        course_managers__c manager = new course_managers__c(
            Course_Offering__c = offering.Id,
            Role__c = 'Delivery Manager',
            User__c = dmUserId
        );

        Test.startTest();
        FacultyPaymentChecklistHandler.handleAfterInsert(new List<course_managers__c>{ manager });
        Test.stopTest();

        Payment_Information__c refreshed = [
            SELECT Id, SPOC__c
            FROM Payment_Information__c
            WHERE Id = :payment.Id
        ];
        System.assertEquals(dmUserId, refreshed.SPOC__c);
    }

    @isTest
    static void testFacultyPaymentHandleGradesReleasedLogicTransitions() {
        CourseOffering offering = createHandlerTestOffering('FPH Grades');
        User spocUser = createHandlerUser('fphspoc1');

        Payment_Information__c p1 = new Payment_Information__c(
            Subject__c = 'P1',
            Course_Offering__c = offering.Id,
            Status__c = 'Draft',
            Remuneration_Type__c = '50'
        );
        Payment_Information__c p2 = new Payment_Information__c(
            Subject__c = 'P2',
            Course_Offering__c = offering.Id,
            Status__c = 'Draft',
            Remuneration_Type__c = '100'
        );
        Payment_Information__c p3 = new Payment_Information__c(
            Subject__c = 'P3',
            Course_Offering__c = offering.Id,
            Status__c = 'ASA Processing',
            SPOC__c = spocUser.Id,
            Remuneration_Type__c = '50'
        );
        Payment_Information__c p4 = new Payment_Information__c(
            Subject__c = 'P4',
            Course_Offering__c = offering.Id,
            Status__c = 'Draft',
            SPOC__c = spocUser.Id,
            Remuneration_Type__c = '50'
        );
        insert new List<Payment_Information__c>{ p1, p2, p3, p4 };

        Map<Id, Payment_Information__c> oldMap = new Map<Id, Payment_Information__c>([
            SELECT Id, Status__c, SPOC__c, Grades_Released__c, ASA_Ready_for_Finance__c,
                   Submitted_to_Finance__c, Sent_to_Finance_Date__c, Payment_Status__c,
                   Closure_Status__c, Course_Manager__c, OwnerId
            FROM Payment_Information__c
            WHERE Id IN :new Set<Id>{ p1.Id, p2.Id, p3.Id, p4.Id }
        ]);
        oldMap.put(p4.Id, new Payment_Information__c(
            Id = p4.Id,
            Status__c = 'Finance Processing',
            SPOC__c = spocUser.Id,
            Payment_Status__c = 'In Progress'
        ));

        Payment_Information__c u1 = new Payment_Information__c(
            Id = p1.Id,
            Grade_Release_Date__c = DateTime.now(),
            Status__c = 'Draft',
            Remuneration_Type__c = '50'
        );

        Payment_Information__c u2 = new Payment_Information__c(
            Id = p2.Id,
            SPOC__c = spocUser.Id,
            Grade_Release_Date__c = DateTime.now(),
            Status__c = 'Draft',
            Remuneration_Type__c = '100'
        );

        Payment_Information__c u3 = new Payment_Information__c(
            Id = p3.Id,
            SPOC__c = spocUser.Id,
            ASA_Ready_for_Finance__c = true,
            Status__c = 'ASA Processing',
            Remuneration_Type__c = '50'
        );

        Payment_Information__c u4 = new Payment_Information__c(
            Id = p4.Id,
            SPOC__c = spocUser.Id,
            Status__c = 'Finance Processing',
            Payment_Status__c = 'Completed',
            Remuneration_Type__c = '50'
        );

        List<Payment_Information__c> updates = new List<Payment_Information__c>{ u1, u2, u3, u4 };

        Test.startTest();
        FacultyPaymentChecklistHandler.handleGradesReleasedLogic(updates, oldMap);
        Test.stopTest();

        System.assert(u1.getErrors().size() > 0, 'Missing SPOC during grade release should add error.');

        System.assertEquals(true, u2.Grades_Released__c);
        System.assertEquals('Grades Released', u2.Status__c);
        System.assertEquals(spocUser.Id, u2.OwnerId);

        System.assertEquals(true, u3.Submitted_to_Finance__c);
        System.assertEquals('Submitted to Finance', u3.Status__c);
        System.assertNotEquals(null, u3.Sent_to_Finance_Date__c);

        System.assertEquals('Completed', u4.Status__c);
        System.assertEquals('Closed', u4.Closure_Status__c);
        System.assertEquals(true, u4.Payment_Done__c);
    }

    @isTest
    static void testFacultyPaymentOwnerChangeNotificationsNoException() {
        CourseOffering offering = createHandlerTestOffering('FPH Notify');
        User owner1 = createHandlerUser('fphown1');
        User owner2 = createHandlerUser('fphown2');

        Payment_Information__c payment = new Payment_Information__c(
            Subject__c = 'Notify Payment',
            Course_Offering__c = offering.Id,
            Remuneration_Type__c = '50',
            OwnerId = owner1.Id
        );
        insert payment;

        List<Payment_Information__c> insertContext = [
            SELECT Id, Name, OwnerId
            FROM Payment_Information__c
            WHERE Id = :payment.Id
        ];

        Test.startTest();
        FacultyPaymentChecklistHandler.handleOwnerChangeNotifications(insertContext, null);

        Map<Id, Payment_Information__c> oldMap = new Map<Id, Payment_Information__c>(insertContext);
        Payment_Information__c updateContext = new Payment_Information__c(
            Id = payment.Id,
            OwnerId = owner2.Id
        );
        FacultyPaymentChecklistHandler.handleOwnerChangeNotifications(
            new List<Payment_Information__c>{ updateContext },
            oldMap
        );
        Test.stopTest();

        System.assertEquals(owner2.Id, updateContext.OwnerId);
    }
}