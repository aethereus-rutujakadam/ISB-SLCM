@IsTest
private class OutgoingExchangeCaseHandlerTest {

    private static Id createExchangeSchoolPartner() {
        Account school = new Account(Name = 'Partner University ' + String.valueOf(System.now().getTime()));
        insert school;
        return school.Id;
    }

    private static Id getOutgoingRTId() {
        return Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName()
            .containsKey('Outgoing_Exchange')
            ? Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get('Outgoing_Exchange').getRecordTypeId()
            : null;
    }

    private static Case buildCase(String status) {
        Id rtId = getOutgoingRTId();
        Id exchangeSchoolId = createExchangeSchoolPartner();
        Contact student = TestDataFactory.testContact();
        Program program = TestDataFactory.testProgram();
        ProgramEnrollment pe = TestDataFactory.testProgramEnrollment(
            student,
            program,
            'PG-' + String.valueOf(System.now().getTime())
        );
        pe.Exchange_School__c = exchangeSchoolId;
        update pe;

        Case c = new Case(
            RecordTypeId = rtId,
            Status = status,
            Subject = 'Outgoing Exchange Test',
            ContactId = student.Id,
            Program__c = program.Id,
            Program_Enrollment__c = pe.Id,
            Exchange_School_Partner__c = exchangeSchoolId,
            Finance_Cleared__c = 'Open',
            ASA_SA_Cleared__c = false,
            Operations_Cleared__c = false,
            IT_Cleared__c = false,
            LRC_Cleared__c = false,
            Partner_Transcript_Received__c = false,
            Grading_Scale_Uploaded__c = false,
            Course_Confirmation_Form__c = false,
            Ready_for_Graduation_Audit__c = false
        );

        if (status == 'RO Review' || status == 'Transcript Check' || status == 'Student Credit Check' || status == 'Closed') {
            c.Finance_Cleared__c = 'Cleared';
            c.ASA_SA_Cleared__c = true;
            c.Operations_Cleared__c = true;
            c.IT_Cleared__c = true;
            c.LRC_Cleared__c = true;
        }

        if (status == 'Transcript Check' || status == 'Student Credit Check' || status == 'Closed') {
            c.Partner_Transcript_Received__c = true;
        }

        if (status == 'Student Credit Check' || status == 'Closed') {
            c.Grading_Scale_Uploaded__c = true;
            c.Course_Confirmation_Form__c = true;
        }

        return c;
    }

    private static Id getOutgoingChecklistRtId(Schema.SObjectType sObjectType) {
        Map<String, Schema.RecordTypeInfo> infos = sObjectType.getDescribe().getRecordTypeInfosByDeveloperName();
        return infos.containsKey('Outgoing_Exchange_Checklist')
            ? infos.get('Outgoing_Exchange_Checklist').getRecordTypeId()
            : null;
    }

    private static void createOutgoingTemplate() {
        Id templateRtId = getOutgoingChecklistRtId(Course_Checklist_Item_Template__c.SObjectType);
        if (templateRtId == null) {
            return;
        }

        insert new Course_Checklist_Item_Template__c(
            RecordTypeId = templateRtId,
            Active__c = true,
            Subject__c = 'Outgoing Activity Template',
            Description__c = 'Template for outgoing checklist creation',
            Priority__c = 'High',
            Owner_Roles__c = 'Associate',
            Activity_Type__c = 'Quiz'
        );
    }

    @IsTest
    static void testStage1_ASAToROReview() {
        Id rtId = getOutgoingRTId();
        if (rtId == null) return;
        Case c = buildCase('ASA In Progress');
        insert c;
        c.Finance_Cleared__c = 'Cleared';
        c.ASA_SA_Cleared__c = true;
        c.Operations_Cleared__c = true;
        c.IT_Cleared__c = true;
        c.LRC_Cleared__c = true;
        Test.startTest();
        update c;
        Test.stopTest();
        c = [SELECT Status FROM Case WHERE Id = :c.Id];
        System.assertEquals('RO Review', c.Status, 'Should advance to RO Review');
    }

    @IsTest
    static void testStage2_ROReviewToTranscriptCheck() {
        Id rtId = getOutgoingRTId();
        if (rtId == null) return;
        Case c = buildCase('RO Review');
        insert c;
        c.Partner_Transcript_Received__c = true;
        Test.startTest();
        update c;
        Test.stopTest();
        c = [SELECT Status FROM Case WHERE Id = :c.Id];
        System.assertEquals('Transcript Check', c.Status, 'Should advance to Transcript Check');
    }

    @IsTest
    static void testStage3_TranscriptCheckToStudentCreditCheck() {
        Id rtId = getOutgoingRTId();
        if (rtId == null) return;
        Case c = buildCase('Transcript Check');
        insert c;
        c.Grading_Scale_Uploaded__c = true;
        c.Course_Confirmation_Form__c = true;
        Test.startTest();
        update c;
        Test.stopTest();
        c = [SELECT Status FROM Case WHERE Id = :c.Id];
        System.assertEquals('Student Credit Check', c.Status, 'Should advance to Student Credit Check');
    }

    @IsTest
    static void testStage4_StudentCreditCheckToClosedWithDate() {
        Id rtId = getOutgoingRTId();
        if (rtId == null) return;
        Case c = buildCase('Student Credit Check');
        insert c;
        c.Ready_for_Graduation_Audit__c = true;
        Test.startTest();
        update c;
        Test.stopTest();
        c = [SELECT Status, Closed_Date__c FROM Case WHERE Id = :c.Id];
        System.assertEquals('Closed', c.Status, 'Should be Closed');
        System.assertNotEquals(null, c.Closed_Date__c, 'Closed_Date__c should be stamped');
    }

    @IsTest
    static void testNonOutgoingRTSkipped() {
        // Use a different RT or null RT case — should not be affected
        Case c = new Case(Status = 'ASA In Progress', Subject = 'Other Case',
                          Finance_Cleared__c = 'Cleared', ASA_SA_Cleared__c = true,
                          Operations_Cleared__c = true, IT_Cleared__c = true, LRC_Cleared__c = true);
        insert c;
        c.Finance_Cleared__c = 'Cleared';
        update c;
        c = [SELECT Status FROM Case WHERE Id = :c.Id];
        // Status should NOT have changed to 'RO Review' since RT is not Outgoing_Exchange
        System.assertNotEquals('RO Review', c.Status, 'Non-Outgoing RT should not be affected');
    }

    @IsTest
    static void testAfterInsertCreatesChecklistAndItemsFromTemplate() {
        Id outgoingRtId = getOutgoingRTId();
        Id checklistRtId = getOutgoingChecklistRtId(Course_Checklist__c.SObjectType);
        Id checklistItemRtId = getOutgoingChecklistRtId(Course_Checklist_Item__c.SObjectType);
        Id templateRtId = getOutgoingChecklistRtId(Course_Checklist_Item_Template__c.SObjectType);
        if (outgoingRtId == null || checklistRtId == null || checklistItemRtId == null || templateRtId == null) {
            return;
        }

        createOutgoingTemplate();

        Case c = buildCase('ASA In Progress');
        insert c;

        Course_Checklist__c checklist = [
            SELECT Id, RecordTypeId, Case__c, OwnerId, Status__c
            FROM Course_Checklist__c
            WHERE Case__c = :c.Id
            LIMIT 1
        ];

        System.assertEquals(checklistRtId, checklist.RecordTypeId, 'Checklist RT should be Outgoing_Exchange_Checklist');
        System.assertEquals(c.Id, checklist.Case__c, 'Checklist should be linked to case');
        System.assertEquals('Active', checklist.Status__c, 'Checklist status should default to Active');
        System.assertEquals(c.OwnerId, checklist.OwnerId, 'Checklist owner should be case owner');

        List<Course_Checklist_Item__c> items = [
            SELECT Id, RecordTypeId, Course_Checklist__c, Status__c, Subject__c, Role__c, Course_Checklist_Item_Template__c
            FROM Course_Checklist_Item__c
            WHERE Course_Checklist__c = :checklist.Id
        ];

        System.assertEquals(1, items.size(), 'Exactly one item should be created from one active template');
        System.assertEquals(checklistItemRtId, items[0].RecordTypeId, 'Item RT should be Outgoing_Exchange_Checklist');
        System.assertEquals('Not Started', items[0].Status__c, 'Item status should default to Not Started');
        System.assertEquals('Outgoing Activity Template', items[0].Subject__c, 'Item should copy subject from template');
        System.assertEquals('Associate', items[0].Role__c, 'Role should map to Associate when template role is Associate');
        System.assertNotEquals(null, items[0].Course_Checklist_Item_Template__c, 'Item should keep template reference');
    }

    @IsTest
    static void testAfterInsertDedupesChecklistByCase() {
        Id outgoingRtId = getOutgoingRTId();
        Id checklistRtId = getOutgoingChecklistRtId(Course_Checklist__c.SObjectType);
        Id templateRtId = getOutgoingChecklistRtId(Course_Checklist_Item_Template__c.SObjectType);
        if (outgoingRtId == null || checklistRtId == null || templateRtId == null) {
            return;
        }

        createOutgoingTemplate();

        Case c = buildCase('ASA In Progress');
        insert c;

        c = [SELECT Id, RecordTypeId FROM Case WHERE Id = :c.Id];

        Test.startTest();
        OutgoingExchangeCaseHandler.handleAfterInsert(new List<Case>{ c });
        Test.stopTest();

        Integer checklistCount = [
            SELECT COUNT()
            FROM Course_Checklist__c
            WHERE Case__c = :c.Id
              AND RecordTypeId = :checklistRtId
        ];

        System.assertEquals(1, checklistCount, 'Exactly one checklist should exist per case');
    }
}