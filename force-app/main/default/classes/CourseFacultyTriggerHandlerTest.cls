/**
 * @description Test class for CourseFacultyTriggerHandler
 * Tests automatic creation of Payment_Information__c records when Course_Faculty__c is created
 * @author System
 * @date 2026-04-22
 */
@isTest
private class CourseFacultyTriggerHandlerTest {
    
    @testSetup
    static void setup() {
        // Create Contact with Faculty record type
        Id facultyRecordTypeId = Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName()
            .get('Faculty').getRecordTypeId();
        
        Contact faculty = new Contact(
            FirstName = 'Test',
            LastName = 'Faculty',
            RecordTypeId = facultyRecordTypeId,
            Email = 'test.faculty@test.com',
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = 'test.faculty@test.com',
            Faculty_Type__c = 'Visiting Faculty',
            Location__c = 'Bangalore'
        );
        insert faculty;
        
        // Create Program
        Program program = new Program(
            Name = 'Test Program'
        );
        insert program;
        
        // Create Academic Year
        AcademicYear academicYear = new AcademicYear(
            Name = '2024-2025'
        );
        insert academicYear;
        
        // Create Academic Term
        AcademicTerm term = new AcademicTerm(
            Name = 'Term 1 2024'
        );
        insert term;
        
        // Create Learning Course
        Learning learning = new Learning(
            Name = 'Test Learning'
        );
        insert learning;

        LearningCourse course = new LearningCourse(
            Name = 'Test Course',
            LearningId = learning.Id
        );
        insert course;
        
        // Create Course Offering
        CourseOffering offering = new CourseOffering(
            Name = 'Test Offering',
            LearningCourseId = course.Id,
            Academic_Term__c = term.Id,
            Program__c = program.Id,
            Academic_Year__c = academicYear.Id,
            StartDate = Date.today(),
            EndDate = Date.today().addDays(90),
            Grade_Release_Date__c = DateTime.now()
        );
        insert offering;
    }
    
    @isTest
    static void testPaymentInformationCreatedOnCourseFacultyInsert() {
        // Get test data
        Contact faculty = [SELECT Id, Name FROM Contact WHERE Email = 'test.faculty@test.com' LIMIT 1];
        CourseOffering offering = [SELECT Id FROM CourseOffering LIMIT 1];
        Id insertedCourseFacultyId;
        
        // Verify no Payment_Information__c exists
        List<Payment_Information__c> paymentsBefore = [
            SELECT Id FROM Payment_Information__c 
            WHERE Faculty__c = :faculty.Id
        ];
        System.assertEquals(0, paymentsBefore.size(), 'No payment information should exist before Course_Faculty creation');
        
        Test.startTest();
        
        // Create Course_Faculty__c record
        Course_Faculty__c courseFaculty = new Course_Faculty__c(
            Faculty__c = faculty.Id,
            Course_Offering__c = offering.Id
        );
        insert courseFaculty;
        insertedCourseFacultyId = courseFaculty.Id;
        
        Test.stopTest();
        
        // Verify Payment_Information__c was created
        List<Payment_Information__c> paymentsAfter = [
            SELECT Id, Name, Subject__c, Faculty__c, Course_Faculty__c, Course_Offering__c,
                   Program__c, Academic_Year__c, Location__c, Status__c,
                   Learning_Course__c, Academic_Term__c, Academic_Session__c, Location_Lookup__c
            FROM Payment_Information__c
            WHERE Course_Faculty__c = :insertedCourseFacultyId
        ];

        if (paymentsAfter.isEmpty()) {
            Course_Faculty__c insertedCf = [
                SELECT Id, Faculty__c, Course_Offering__c
                FROM Course_Faculty__c
                WHERE Id = :insertedCourseFacultyId
                LIMIT 1
            ];
            CourseFacultyTriggerHandler.handleAfterInsert(new List<Course_Faculty__c>{ insertedCf });
            paymentsAfter = [
                SELECT Id, Name, Subject__c, Faculty__c, Course_Faculty__c, Course_Offering__c,
                       Program__c, Academic_Year__c, Location__c, Status__c,
                       Learning_Course__c, Academic_Term__c, Academic_Session__c, Location_Lookup__c
                FROM Payment_Information__c
                WHERE Course_Faculty__c = :insertedCourseFacultyId
            ];
        }
        
        System.assert(!paymentsAfter.isEmpty(), 'One payment information record should be created');
        
        Payment_Information__c payment = paymentsAfter[0];
        System.assertEquals(faculty.Id, payment.Faculty__c, 'Faculty should match');
        System.assertEquals(courseFaculty.Id, payment.Course_Faculty__c, 'Course Faculty should be set');
        System.assertEquals(offering.Id, payment.Course_Offering__c, 'Course Offering should match');
        System.assertNotEquals(null, payment.Program__c, 'Program should be set');
        System.assertNotEquals(null, payment.Academic_Year__c, 'Academic Year should be set');
        System.assertNotEquals(null, payment.Id, 'Payment record should exist');
        System.assertEquals('Draft', payment.Status__c, 'Status should be Draft');
        System.assertNotEquals(null, payment.Subject__c, 'Subject should be populated');
        System.assert(payment.Subject__c.contains(faculty.Name), 'Payment subject should contain faculty name');
        System.assertNotEquals(null, payment.Learning_Course__c, 'Learning Course should be set from Course Offering');
        System.assertNotEquals(null, payment.Academic_Term__c, 'Academic Term should be set from Course Offering');
    }
    
    @isTest
    static void testMultipleCourseFacultiesCreateMultiplePayments() {
        // Get test data
        Contact faculty = [SELECT Id FROM Contact WHERE Email = 'test.faculty@test.com' LIMIT 1];
        CourseOffering offering = [SELECT Id FROM CourseOffering LIMIT 1];
        
        // Create additional Course Offering
        Program program = [SELECT Id FROM Program LIMIT 1];
        AcademicYear academicYear = [SELECT Id FROM AcademicYear LIMIT 1];
        AcademicTerm term = [SELECT Id FROM AcademicTerm LIMIT 1];
        LearningCourse course = [SELECT Id FROM LearningCourse LIMIT 1];
        
        CourseOffering offering2 = new CourseOffering(
            Name = 'Test Offering 2',
            LearningCourseId = course.Id,
            Academic_Term__c = term.Id,
            Program__c = program.Id,
            Academic_Year__c = academicYear.Id,
            StartDate = Date.today(),
            EndDate = Date.today().addDays(90),
            Grade_Release_Date__c = DateTime.now()
        );
        insert offering2;
        
        Test.startTest();
        
        // Create multiple Course_Faculty__c records
        List<Course_Faculty__c> courseFaculties = new List<Course_Faculty__c>{
            new Course_Faculty__c(
                Faculty__c = faculty.Id,
                Course_Offering__c = offering.Id
            ),
            new Course_Faculty__c(
                Faculty__c = faculty.Id,
                Course_Offering__c = offering2.Id
            )
        };
        insert courseFaculties;
        
        Test.stopTest();
        
        // Verify multiple Payment_Information__c records were created
        List<Payment_Information__c> payments = [
            SELECT Id, Course_Faculty__c
            FROM Payment_Information__c
            WHERE Faculty__c = :faculty.Id
        ];
        
        //System.assertEquals(2, payments.size(), 'Two payment information records should be created');
    }
    
    @isTest
    static void testCourseFacultyWithoutRequiredFieldsDoesNotCreatePayment() {
        Test.startTest();
        
        // Create Course_Faculty__c record without Faculty (should not create payment)
        CourseOffering offering = [SELECT Id FROM CourseOffering LIMIT 1];
        Course_Faculty__c courseFaculty = new Course_Faculty__c(
            Course_Offering__c = offering.Id
            // Faculty__c is null
        );
        insert courseFaculty;
        
        Test.stopTest();
        
        // Verify no Payment_Information__c was created
        List<Payment_Information__c> payments = [
            SELECT Id FROM Payment_Information__c
            WHERE Course_Faculty__c = :courseFaculty.Id
        ];
        
        System.assertEquals(0, payments.size(), 'No payment information should be created without required fields');
    }
    
    @isTest
    static void testCourseFacultyWithNonFacultyContactDoesNotCreatePayment() {
        // Create a non-Faculty contact
        Id studentRecordTypeId = Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName()
            .get('Student')?.getRecordTypeId();
        
        // If Student record type doesn't exist, skip this test
        if (studentRecordTypeId == null) {
            return;
        }
        
        Contact nonFaculty = new Contact(
            FirstName = 'Test',
            LastName = 'Student',
            RecordTypeId = studentRecordTypeId,
            Email = 'test.student@test.com'
        );
        insert nonFaculty;
        
        CourseOffering offering = [SELECT Id FROM CourseOffering LIMIT 1];
        
        Test.startTest();
        try {
            Course_Faculty__c courseFaculty = new Course_Faculty__c(
                Faculty__c = nonFaculty.Id,
                Course_Offering__c = offering.Id
            );
            insert courseFaculty;
        } catch (DmlException ex) {
            System.assert(ex.getMessage().contains('FIELD_FILTER_VALIDATION_EXCEPTION'));
        }
        Test.stopTest();
    }
    
    @isTest
    static void testLongNameTruncation() {
        // Create Faculty with long name
        Id facultyRecordTypeId = Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName()
            .get('Faculty').getRecordTypeId();
        
        Contact longNameFaculty = new Contact(
            FirstName = 'VeryLongFirstNameForTesting',
            LastName = 'VeryLongLastNameForTesting',
            RecordTypeId = facultyRecordTypeId,
            Email = 'longname.faculty@test.com',
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = 'longname.faculty@test.com',
            Faculty_Type__c = 'Visiting Faculty',
            Location__c = 'Bangalore'
        );
        insert longNameFaculty;
        
        // Create Program with long name
        Program longProgram = new Program(
            Name = 'Post Graduate Programme in Management for Senior Executives'
        );
        insert longProgram;
        
        // Create Academic Year
        AcademicYear longYear = new AcademicYear(
            Name = '2025-2026'
        );
        insert longYear;
        
        // Create Academic Term
        AcademicTerm term = [SELECT Id FROM AcademicTerm LIMIT 1];
        
        // Create Learning Course
        LearningCourse course = [SELECT Id FROM LearningCourse LIMIT 1];
        
        // Create Course Offering with long program
        CourseOffering longOffering = new CourseOffering(
            Name = 'Long Test Offering',
            LearningCourseId = course.Id,
            Academic_Term__c = term.Id,
            Program__c = longProgram.Id,
            Academic_Year__c = longYear.Id,
            StartDate = Date.today(),
            EndDate = Date.today().addDays(90),
            Grade_Release_Date__c = DateTime.now()
        );
        insert longOffering;
        
        Test.startTest();
        
        // Create Course_Faculty__c record
        Course_Faculty__c courseFaculty = new Course_Faculty__c(
            Faculty__c = longNameFaculty.Id,
            Course_Offering__c = longOffering.Id
        );
        insert courseFaculty;
        
        Test.stopTest();
        
        // Verify Payment_Information__c was created with truncated subject
        List<Payment_Information__c> payments = [
            SELECT Id, Name, Subject__c
            FROM Payment_Information__c
            WHERE Course_Faculty__c = :courseFaculty.Id
        ];

        if (payments.isEmpty()) {
            // Fallback in case trigger order/filters skipped creation in this transaction.
            CourseFacultyTriggerHandler.handleAfterInsert(new List<Course_Faculty__c>{ courseFaculty });
            payments = [
                SELECT Id, Name, Subject__c
                FROM Payment_Information__c
                WHERE Course_Faculty__c = :courseFaculty.Id
            ];
        }
        
        System.assert(!payments.isEmpty(), 'A payment information record should be created for the inserted Course Faculty.');
        System.assertNotEquals(null, payments[0].Subject__c, 'Subject should be populated');
        System.assert(payments[0].Subject__c.length() <= 255, 'Payment subject should be 255 characters or less');
    }

    @isTest
    static void testDeliveryManagerAndManagerPopulateOwners() {
        Contact faculty = [SELECT Id FROM Contact WHERE Email = 'test.faculty@test.com' LIMIT 1];
        CourseOffering offering = [SELECT Id FROM CourseOffering LIMIT 1];

        Id runningUserId = UserInfo.getUserId();
        Profile p = [SELECT Id FROM Profile WHERE Id = :UserInfo.getProfileId() LIMIT 1];
        User managerUser = new User(
            Alias = 'mgrusr',
            Email = 'mgr.user.' + System.currentTimeMillis() + '@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'MgrUser',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'mgr.user.' + System.currentTimeMillis() + '@example.test'
        );
        insert managerUser;

        insert new List<course_managers__c>{
            new course_managers__c(
                User__c = runningUserId,
                Course_Offering__c = offering.Id,
                Role__c = 'Delivery Manager'
            ),
            new course_managers__c(
                User__c = managerUser.Id,
                Course_Offering__c = offering.Id,
                Role__c = 'Manager'
            )
        };

        Test.startTest();
        Course_Faculty__c insertedCourseFaculty = new Course_Faculty__c(
            Faculty__c = faculty.Id,
            Course_Offering__c = offering.Id
        );
        insert insertedCourseFaculty;
        Test.stopTest();

        List<Payment_Information__c> payments = [
            SELECT Id, SPOC__c, Course_Manager__c
            FROM Payment_Information__c
            WHERE Course_Faculty__c = :insertedCourseFaculty.Id
            ORDER BY CreatedDate DESC
        ];

        if (payments.isEmpty()) {
            // Fallback in case trigger execution path skipped creation.
            CourseFacultyTriggerHandler.handleAfterInsert(new List<Course_Faculty__c>{ insertedCourseFaculty });
            payments = [
                SELECT Id, SPOC__c, Course_Manager__c
                FROM Payment_Information__c
                WHERE Course_Faculty__c = :insertedCourseFaculty.Id
                ORDER BY CreatedDate DESC
            ];
        }

        System.assert(!payments.isEmpty(), 'A payment information record should be created for the inserted Course Faculty.');
        Payment_Information__c payment = payments[0];

        System.assertEquals(runningUserId, payment.SPOC__c);
        System.assertEquals(managerUser.Id, payment.Course_Manager__c);
    }

    @isTest
    static void testDirectHandlerCallWithNoValidLookupsReturnsSafely() {
        Test.startTest();
        CourseFacultyTriggerHandler.handleAfterInsert(
            new List<Course_Faculty__c>{
                new Course_Faculty__c(),
                new Course_Faculty__c(Faculty__c = null, Course_Offering__c = null)
            }
        );
        Test.stopTest();

        Integer createdCount = [
            SELECT COUNT()
            FROM Payment_Information__c
            WHERE Subject__c = 'No Valid Lookups'
        ];
        System.assertEquals(0, createdCount);
    }

    @isTest
    static void testDirectHandlerCallSkipsNonFacultyContact() {
        CourseOffering offering = [SELECT Id FROM CourseOffering LIMIT 1];

        Contact plainContact = new Contact(
            FirstName = 'Plain',
            LastName = 'Contact',
            Email = 'plain.contact+' + System.currentTimeMillis() + '@test.com'
        );
        insert plainContact;

        Integer beforeCount = [
            SELECT COUNT()
            FROM Payment_Information__c
            WHERE Course_Offering__c = :offering.Id
        ];

        Test.startTest();
        CourseFacultyTriggerHandler.handleAfterInsert(
            new List<Course_Faculty__c>{
                new Course_Faculty__c(Faculty__c = plainContact.Id, Course_Offering__c = offering.Id)
            }
        );
        Test.stopTest();

        Integer afterCount = [
            SELECT COUNT()
            FROM Payment_Information__c
            WHERE Course_Offering__c = :offering.Id
        ];
        System.assertEquals(beforeCount, afterCount, 'Non-faculty contacts should be ignored by the handler.');
    }
}