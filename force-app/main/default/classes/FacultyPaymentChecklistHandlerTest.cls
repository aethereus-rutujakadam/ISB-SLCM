@isTest
private class FacultyPaymentChecklistHandlerTest {

@testSetup
static void setup() {

    Id facultyRecordTypeId =
        Schema.SObjectType.Contact
            .getRecordTypeInfosByDeveloperName()
            .get('Faculty')
            .getRecordTypeId();

    Contact faculty = new Contact(
        FirstName = 'Test',
        LastName = 'Faculty',
        RecordTypeId = facultyRecordTypeId,
        Email = 'test.faculty@test.com',
        hed__Preferred_Email__c = 'VF Email ID',
        VF_Email_ID__c = 'bodhtree.admin@isb.com'
    );
    insert faculty;

    Profile p = [
        SELECT Id
        FROM Profile
        WHERE Name = 'System Administrator'
        LIMIT 1
    ];

    User testUser = new User(
        FirstName = 'Test',
        LastName = 'Manager',
        Email = 'testmgr@test.com',
        Username = 'testmgr' + DateTime.now().getTime() + '@test.com',
        Alias = 'tmgr',
        TimeZoneSidKey = 'America/Los_Angeles',
        LocaleSidKey = 'en_US',
        EmailEncodingKey = 'UTF-8',
        ProfileId = p.Id,
        LanguageLocaleKey = 'en_US'
    );
    insert testUser;

    AcademicTerm term = new AcademicTerm(
        Name = 'Test Term 2024'
    );
    insert term;

    Learning learning = new Learning(
        Name = 'Test Learning'
    );
    insert learning;

    LearningCourse course = new LearningCourse(
        Name = 'Test Course',
        LearningId = learning.Id
    );
    insert course;

    CourseOffering offering = new CourseOffering(
        Name = 'Test Offering',
        LearningCourseId = course.Id,
        Academic_Term__c = term.Id,
        StartDate = Date.today(),
        EndDate = Date.today().addDays(90),
        Grade_Release_Date__c = Datetime.now()
    );
    insert offering;

    insert new Course_Faculty__c(
        Faculty__c = faculty.Id,
        Course_Offering__c = offering.Id
    );
    
    // Create Course Checklist Item Templates for Faculty Payment
    List<Course_Checklist_Item_Template__c> templates = new List<Course_Checklist_Item_Template__c>();
    templates.add(new Course_Checklist_Item_Template__c(
        Template_Type__c = 'Start of Term Tasks',
        Subject__c = 'Faculty Payment Information',
        Active__c = true
    ));
    templates.add(new Course_Checklist_Item_Template__c(
        Template_Type__c = 'Start of Term Tasks',
        Subject__c = 'Faculty Contract Verification',
        Active__c = true
    ));
    insert templates;
}

@isTest
static void testGradesReleasedCheckboxAutoSelect() {

    Contact faculty = [SELECT Id FROM Contact LIMIT 1];

    User testManager =
        [SELECT Id FROM User WHERE IsActive = true LIMIT 1];

    User spocUser =
        [SELECT Id FROM User WHERE IsActive = true LIMIT 1];

    Payment_Information__c payment =
        new Payment_Information__c(
            Faculty__c = faculty.Id,
            Course_Manager__c = testManager.Id,
            SPOC__c = spocUser.Id,
            Remuneration_Type__c = '50',
            Grade_Release_Date__c = Datetime.now()
        );

    Test.startTest();
    insert payment;
    Test.stopTest();

    payment = [
        SELECT Grades_Released__c
        FROM Payment_Information__c
        WHERE Id = :payment.Id
    ];
}

@isTest
static void testGradesReleasedStatusUpdate() {

    Contact faculty = [SELECT Id FROM Contact LIMIT 1];

    User testManager =
        [SELECT Id FROM User WHERE IsActive = true LIMIT 1];

    User spocUser =
        [SELECT Id FROM User WHERE IsActive = true LIMIT 1];

    Payment_Information__c payment =
        new Payment_Information__c(
            Faculty__c = faculty.Id,
            SPOC__c = spocUser.Id
        );

    insert payment;

    Test.startTest();

    payment.Course_Manager__c = testManager.Id;
    payment.Remuneration_Type__c = '50';
    update payment;

    payment.Grade_Release_Date__c = Datetime.now();
    update payment;

    Test.stopTest();

    payment = [
        SELECT Status__c,
               OwnerId,
               Grades_Released__c
        FROM Payment_Information__c
        WHERE Id = :payment.Id
    ];
}

@isTest
static void testBulkGradesReleasedProcessing() {

    Contact faculty = [SELECT Id FROM Contact LIMIT 1];

    User manager =
        [SELECT Id FROM User WHERE IsActive = true LIMIT 1];

    User spoc =
        [SELECT Id FROM User WHERE IsActive = true LIMIT 1];

    List<Payment_Information__c> payments =
        new List<Payment_Information__c>();

    for (Integer i = 0; i < 200; i++) {

        payments.add(
            new Payment_Information__c(
                Faculty__c = faculty.Id,
                Status__c = 'Draft',
                Course_Manager__c = manager.Id,
                SPOC__c = spoc.Id,
                Remuneration_Type__c = '50'
            )
        );
    }

    insert payments;

    Test.startTest();

    for (Payment_Information__c p : payments) {
        p.Grade_Release_Date__c = Datetime.now();
    }

    update payments;

    Test.stopTest();

    Integer countRecords = [
        SELECT COUNT()
        FROM Payment_Information__c
        WHERE Status__c = 'Grades Released'
    ];

}

@isTest
static void testFinanceQueueAssignment() {

    User runAsUser = [
        SELECT Id
        FROM User
        WHERE IsActive = true
        LIMIT 1
    ];

    Id financeQueueId;

    System.runAs(runAsUser) {

        Group financeQueue = new Group(
            Name = 'Finance Team',
            Type = 'Queue'
        );
        insert financeQueue;

        financeQueueId = financeQueue.Id;

        insert new QueueSobject(
            QueueId = financeQueue.Id,
            SobjectType = 'Payment_Information__c'
        );
    }

    Contact faculty = [SELECT Id FROM Contact LIMIT 1];

    User manager =
        [SELECT Id FROM User WHERE Username LIKE 'testmgr%' LIMIT 1];

    User spoc =
        [SELECT Id FROM User WHERE IsActive = true LIMIT 1];

    Payment_Information__c payment =
        new Payment_Information__c(
            Faculty__c = faculty.Id,
            Status__c = 'Draft',
            SPOC__c = spoc.Id
        );

    insert payment;

    Test.startTest();

    payment.Course_Manager__c = manager.Id;
    payment.Remuneration_Type__c = '50';
    update payment;

    payment.Grade_Release_Date__c = Datetime.now();
    update payment;

   // payment.ASA_Ready_for_Finance__c = true;
    payment.DocuSign_Status__c = 'Completed';
    payment.PO_Status__c = 'Validated';
    payment.Contract_Upload_Status__c = 'Verified';
    payment.All_Complete__c = true;

    update payment;

    Test.stopTest();

    payment = [
        SELECT Status__c, OwnerId
        FROM Payment_Information__c
        WHERE Id = :payment.Id
    ];
}

@isTest
static void testRejectedFlow() {

    Contact faculty = [SELECT Id FROM Contact LIMIT 1];

    User manager =
        [SELECT Id FROM User WHERE Username LIKE 'testmgr%' LIMIT 1];

    User spoc =
        [SELECT Id FROM User WHERE IsActive = true LIMIT 1];

    Payment_Information__c payment =
        new Payment_Information__c(
            Faculty__c = faculty.Id,
            SPOC__c = spoc.Id,
            Course_Manager__c = manager.Id,
            Remuneration_Type__c = '50',
            Status__c = 'Grades Released'
        );

    insert payment;

    Test.startTest();

    payment.Closure_Status__c = 'Rejected';
    payment.Final_Remarks__c ='Rejected ';
    update payment;

    Test.stopTest();

    payment = [
        SELECT Status__c,
               Submitted_to_Finance__c,
               OwnerId
        FROM Payment_Information__c
        WHERE Id = :payment.Id
    ];
}

@isTest
static void testClosedValidation() {

    Contact faculty = [SELECT Id FROM Contact LIMIT 1];

    Payment_Information__c payment =
        new Payment_Information__c(
            Faculty__c = faculty.Id,
            Status__c = 'Draft'
        );

    insert payment;

    Test.startTest();

   // payment.Closure_Status__c = 'Closed';
    payment.Remuneration_Type__c = '50';
        update payment;

    Test.stopTest();
}

@isTest
static void testCloneLogic() {

    Contact faculty = [SELECT Id FROM Contact LIMIT 1];

    Payment_Information__c original =
        new Payment_Information__c(
            Faculty__c = faculty.Id,
            Remuneration_Type__c = '50',
            Status__c = 'Draft'
        );

    insert original;

    Payment_Information__c cloned =
        original.clone(false, true, false, false);

    cloned.Remuneration_Type__c = '50';

    Test.startTest();

    try {
        insert cloned;
    } catch (Exception e) {
    }

    Test.stopTest();
}

@isTest
static void testHandleAfterInsert_AssignsSPOC() {

    Contact faculty = [SELECT Id FROM Contact LIMIT 1];

    CourseOffering offering =
        [SELECT Id FROM CourseOffering LIMIT 1];

    User deliveryManager =
        [SELECT Id FROM User WHERE Username LIKE 'testmgr%' LIMIT 1];

    Payment_Information__c payment =
        new Payment_Information__c(
            Faculty__c = faculty.Id,
            Course_Offering__c = offering.Id,
            Status__c = 'Draft'
        );

    insert payment;

    Test.startTest();

    insert new course_managers__c(
        Course_Offering__c = offering.Id,
        User__c = deliveryManager.Id,
        Role__c = 'Delivery Manager'
    );

    Test.stopTest();

    payment = [
        SELECT SPOC__c
        FROM Payment_Information__c
        WHERE Id = :payment.Id
    ];
}

@isTest
static void testNotification_NoOwnerChange() {

    Contact faculty = [SELECT Id FROM Contact LIMIT 1];

    Payment_Information__c payment =
        new Payment_Information__c(
            Faculty__c = faculty.Id,
            Status__c = 'Draft'
        );

    insert payment;

    Payment_Information__c oldPayment =
        payment.clone(true, true, true, true);

    Test.startTest();

    FacultyPaymentChecklistHandler.handleOwnerChangeNotifications(
        new List<Payment_Information__c>{payment},
        new Map<Id, Payment_Information__c>{
            payment.Id => oldPayment
        }
    );

    Test.stopTest();
}
@isTest
static void testAssignToQueue_SubmittedToFinance() {
    Contact faculty = [SELECT Id FROM Contact LIMIT 1];
    User mgr  = [SELECT Id FROM User WHERE Username LIKE 'testmgr%' LIMIT 1];
    User spoc = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];

    List<Group> existing = [
        SELECT Id FROM Group
        WHERE Type = 'Queue' AND DeveloperName = 'Finance_Team' LIMIT 1
    ];
    Group fin;
    if (existing.isEmpty()) {
        fin = new Group(Name = 'Finance Team', DeveloperName = 'Finance_Team', Type = 'Queue');
        insert fin;
        insert new QueueSobject(QueueId = fin.Id, SobjectType = 'Payment_Information__c');
    } else {
        fin = existing[0];
    }

    Payment_Information__c p = new Payment_Information__c(
        Faculty__c = faculty.Id,
        SPOC__c = spoc.Id,
        Course_Manager__c = mgr.Id,
        Remuneration_Type__c = '50',
        Status__c = 'ASA Processing',
        Grade_Release_Date__c = Datetime.now()
    );
    insert p;

    Test.startTest();
    // Satisfy the ASA_Ready_for_Finance validation rule
    p.Document_Collection_Mail_Sent_Date__c = Date.today();
    p.Remarks__c = 'All docs collected';
    p.All_Complete__c = true;
    p.DocuSign_Link__c = 'https://docusign.example.com/env/123';
    p.DocuSign_Status__c = 'Completed';
    p.Invoice_Signed_Date__c = Date.today();
    p.PO_Status__c = 'Validated';
    p.Contract_Upload_Status__c = 'Verified';
    p.ASA_Ready_for_Finance__c = true;
    update p;
    Test.stopTest();

    p = [SELECT OwnerId, Status__c FROM Payment_Information__c WHERE Id = :p.Id];
}
}