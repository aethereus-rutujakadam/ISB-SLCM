/**
 * @description Test class for PaymentRequestController
 */
@isTest
private class PaymentRequestControllerTest {
    
    @testSetup
    static void setup() {
        // Create Faculty Contact
        Id facultyRecordTypeId = Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName()
            .get('Faculty').getRecordTypeId();
        
        List<Contact> faculties = new List<Contact>();
        for (Integer i = 0; i < 3; i++) {
            String email = 'faculty' + i + '@test.com';
            faculties.add(new Contact(
                FirstName = 'Test' + i,
                LastName = 'Faculty' + i,
                RecordTypeId = facultyRecordTypeId,
                Email = email,
                hed__Preferred_Email__c = 'VF Email ID',
                VF_Email_ID__c = email,
                Location__c = 'Hyderabad'
            ));
        }
        insert faculties;
        
        // Create Program
        Program prog = new Program(Name = 'MBA Program');
        insert prog;
        
        // Create Academic Year
        AcademicYear year = new AcademicYear(Name = '2024-2025');
        insert year;
        
        // Create Academic Term
        AcademicTerm term = new AcademicTerm(Name = 'Term 1 2024');
        insert term;
        
        // Create Learning Course
        Learning learning = new Learning(Name = 'Payment Request Learning');
        insert learning;

        LearningCourse course = new LearningCourse(
            Name = 'Business Strategy',
            LearningId = learning.Id
        );
        insert course;
        
        // Create Course Offerings
        List<CourseOffering> offerings = new List<CourseOffering>();
        for (Integer i = 0; i < 2; i++) {
            offerings.add(new CourseOffering(
                Name = 'MBA-Strategy-' + i,
                LearningCourseId = course.Id,
                Academic_Term__c = term.Id,
                Program__c = prog.Id,
                Academic_Year__c = year.Id,
                StartDate = Date.today(),
                EndDate = Date.today().addDays(90)
            ));
        }
        insert offerings;
        
        // Create Course_Faculty__c records
        List<Course_Faculty__c> courseFaculties = new List<Course_Faculty__c>();
        for (Integer i = 0; i < 3; i++) {
            for (Integer j = 0; j < 2; j++) {
                courseFaculties.add(new Course_Faculty__c(
                    Faculty__c = faculties[i].Id,
                    Course_Offering__c = offerings[j].Id
                ));
            }
        }
        insert courseFaculties;
    }
    
    @isTest
    static void testGetPrograms() {
        Test.startTest();
        List<Program> programs = PaymentRequestController.getPrograms();
        Test.stopTest();
        
        System.assert(programs.size() > 0, 'Should return at least one program');
        System.assertEquals('MBA Program', programs[0].Name);
    }
    
    @isTest
    static void testGetAcademicYears() {
        Test.startTest();
        List<AcademicYear> years = PaymentRequestController.getAcademicYears();
        Test.stopTest();
        
        System.assert(years.size() > 0, 'Should return at least one academic year');
        System.assertEquals('2024-2025', years[0].Name);
    }
    
    @isTest
    static void testGetFacultiesByProgramYear() {
        Program prog = [SELECT Id FROM Program LIMIT 1];
        AcademicYear year = [SELECT Id FROM AcademicYear LIMIT 1];
        
        Test.startTest();
        List<PaymentRequestController.FacultyWrapper> faculties = 
            PaymentRequestController.getFacultiesByProgramYear(prog.Id, year.Id);
        Test.stopTest();
        
        System.assertEquals(3, faculties.size(), 'Should return 3 faculties');
        System.assertEquals(2, faculties[0].courseCount, 'Each faculty should have 2 courses');
        System.assertEquals('Hyderabad', faculties[0].location);
    }
    
    @isTest
    static void testCreatePaymentRequests() {
        Program prog = [SELECT Id FROM Program LIMIT 1];
        AcademicYear year = [SELECT Id FROM AcademicYear LIMIT 1];
        
        // Get faculties
        List<PaymentRequestController.FacultyWrapper> faculties = 
            PaymentRequestController.getFacultiesByProgramYear(prog.Id, year.Id);
        
        // Select first 2 faculties
        List<PaymentRequestController.FacultyWrapper> selectedFaculties = 
            new List<PaymentRequestController.FacultyWrapper>{faculties[0], faculties[1]};
        
        Test.startTest();
        String result = PaymentRequestController.createPaymentRequests(selectedFaculties, prog.Id, year.Id);
        Test.stopTest();
        
        // Verify Payment_Information__c created
        List<Payment_Information__c> payments = [
            SELECT Id, Name, Faculty__c, Location__c, 
                   Program__c, Academic_Year__c, Status__c
            FROM Payment_Information__c
        ];
        System.assert(payments.size() >= 2, 'Should create at least the requested payment records');
        System.assertEquals('Draft', payments[0].Status__c, 'Status should be Draft');
        System.assertNotEquals(null, payments[0].Id);
        
        // Verify Faculty_Term_Mapping__c created
        List<Faculty_Term_Mapping__c> mappings = [
            SELECT Id, Payment_Information__c, Course_Offering__c
            FROM Faculty_Term_Mapping__c
        ];
        System.assert(mappings.size() >= 4, 'Should create at least 4 mappings for selected faculties.');
        
        System.assert(result.contains('Successfully created 2 payment request'), 'Result message should be correct');
    }
    
    @isTest
    static void testCreatePaymentRequestsNoFaculties() {
        Program prog = [SELECT Id FROM Program LIMIT 1];
        AcademicYear year = [SELECT Id FROM AcademicYear LIMIT 1];

        Integer beforeCount = [SELECT COUNT() FROM Payment_Information__c];
        
        Test.startTest();
        String result = PaymentRequestController.createPaymentRequests(
            new List<PaymentRequestController.FacultyWrapper>(), 
            prog.Id, 
            year.Id
        );
        Test.stopTest();
        
        Integer afterCount = [SELECT COUNT() FROM Payment_Information__c];
        System.assertEquals(beforeCount, afterCount, 'Should not create additional payment requests');
    }

            @isTest
            static void testGetAcademicSessionsNoData() {
                Test.startTest();
                List<AcademicSession> sessions = PaymentRequestController.getAcademicSessions();
                Test.stopTest();

                System.assertEquals(0, sessions.size(), 'No AcademicSession test records are created in setup.');
            }

            @isTest
            static void testGetFacultiesByProgramSessionsGuards() {
                Program prog = [SELECT Id FROM Program LIMIT 1];

                Test.startTest();
                List<PaymentRequestController.FacultyWrapper> nullProgram =
                    PaymentRequestController.getFacultiesByProgramSessions(null, null);
                List<PaymentRequestController.FacultyWrapper> nullSessions =
                    PaymentRequestController.getFacultiesByProgramSessions(prog.Id, null);
                List<PaymentRequestController.FacultyWrapper> emptySessions =
                    PaymentRequestController.getFacultiesByProgramSessions(prog.Id, new List<Id>());
                Test.stopTest();

                System.assertEquals(0, nullProgram.size());
                System.assertEquals(0, nullSessions.size());
                System.assertEquals(0, emptySessions.size());
            }

            @isTest
            static void testCreatePaymentRequestsBySessionsNoFaculties() {
                Program prog = [SELECT Id FROM Program LIMIT 1];

                Test.startTest();
                String result = PaymentRequestController.createPaymentRequestsBySessions(
                    new List<Id>(),
                    prog.Id,
                    new List<Id>()
                );
                Test.stopTest();

                System.assertEquals('No faculties selected.', result);
            }

            @isTest
            static void testCreatePaymentRequestsBySessionsNoOfferingsFound() {
                Program prog = [SELECT Id FROM Program LIMIT 1];
                Contact c = [SELECT Id FROM Contact LIMIT 1];

                Test.startTest();
                String result = PaymentRequestController.createPaymentRequestsBySessions(
                    new List<Id>{ c.Id },
                    prog.Id,
                    new List<Id>()
                );
                Test.stopTest();

                System.assertEquals('No course offerings found for selected faculties and sessions.', result);
            }

    @isTest
    static void testSessionBasedMethodsSuccessPath() {
        Program prog = [SELECT Id FROM Program LIMIT 1];
        AcademicTerm term = [SELECT Id, Name FROM AcademicTerm LIMIT 1];

        AcademicSession session = new AcademicSession(
            Name = 'Session For Payment Request Test',
            AcademicTermId = term.Id
        );
        insert session;

        List<CourseOffering> offerings = [
            SELECT Id, AcademicSessionId
            FROM CourseOffering
            WHERE Program__c = :prog.Id
        ];
        for (CourseOffering co : offerings) {
            co.AcademicSessionId = session.Id;
        }
        update offerings;

        List<PaymentRequestController.FacultyWrapper> wrappers =
            PaymentRequestController.getFacultiesByProgramSessions(prog.Id, new List<Id>{ session.Id });

        System.assert(!wrappers.isEmpty(), 'Expected session-based faculty wrappers.');

        List<Id> facultyIds = new List<Id>();
        for (PaymentRequestController.FacultyWrapper fw : wrappers) {
            facultyIds.add(fw.facultyId);
            if (facultyIds.size() == 2) {
                break;
            }
        }
        System.assert(!facultyIds.isEmpty(), 'Expected at least one faculty id for session-based creation.');

        String result = PaymentRequestController.createPaymentRequestsBySessions(
            facultyIds,
            prog.Id,
            new List<Id>{ session.Id }
        );

        System.assert(result.contains('Successfully created'));
    }

    @isTest
    static void testGetFacultiesByProgramSessionsWithNullTermIds() {
        Program prog = [SELECT Id FROM Program LIMIT 1];

        // Create session without academic term
        AcademicSession sessionNoTerm = new AcademicSession(
            Name = 'Session No Term',
            AcademicTermId = null
        );
        insert sessionNoTerm;

        Test.startTest();
        List<PaymentRequestController.FacultyWrapper> result =
            PaymentRequestController.getFacultiesByProgramSessions(prog.Id, new List<Id>{ sessionNoTerm.Id });
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Should return empty list when session has no academic term');
    }

    @isTest
    static void testCreatePaymentRequestsBySessionsInvalidProgram() {
        // Test with a program that has no matching course offerings
        Program emptyProg = new Program(Name = 'Empty Program For Test');
        insert emptyProg;
        Contact c = [SELECT Id FROM Contact LIMIT 1];

        Test.startTest();
        String result = PaymentRequestController.createPaymentRequestsBySessions(
            new List<Id>{ c.Id },
            emptyProg.Id,
            new List<Id>()
        );
        Test.stopTest();

        System.assertEquals('No course offerings found for selected faculties and sessions.', result, 'Should return message when no offerings found');
    }

    @isTest
    static void testCreatePaymentRequestsWithMultipleYears() {
        Program prog = [SELECT Id FROM Program LIMIT 1];
        AcademicTerm term = [SELECT Id FROM AcademicTerm LIMIT 1];
        AcademicYear year1 = [SELECT Id FROM AcademicYear WHERE Name = '2024-2025' LIMIT 1];

        // Create second academic year
        AcademicYear year2 = new AcademicYear(Name = '2025-2026');
        insert year2;

        // Create sessions for both years
        AcademicSession session1 = new AcademicSession(
            Name = 'Session Year 1',
            AcademicTermId = term.Id
        );
        AcademicSession session2 = new AcademicSession(
            Name = 'Session Year 2',
            AcademicTermId = term.Id
        );
        insert new List<AcademicSession>{ session1, session2 };

        Contact faculty = [SELECT Id FROM Contact LIMIT 1];

        // Update existing offerings to span multiple years
        List<CourseOffering> existingOfferings = [
            SELECT Id
            FROM CourseOffering
            WHERE Program__c = :prog.Id
            LIMIT 2
        ];
        
        existingOfferings[0].AcademicSessionId = session1.Id;
        existingOfferings[0].Academic_Year__c = year1.Id;
        existingOfferings[0].Academic_Term__c = term.Id;
        
        if (existingOfferings.size() > 1) {
            existingOfferings[1].AcademicSessionId = session2.Id;
            existingOfferings[1].Academic_Year__c = year2.Id;
            existingOfferings[1].Academic_Term__c = term.Id;
        }
        update existingOfferings;

        Test.startTest();
        String result = PaymentRequestController.createPaymentRequestsBySessions(
            new List<Id>{ faculty.Id },
            prog.Id,
            new List<Id>{ session1.Id, session2.Id }
        );
        Test.stopTest();

        System.assert(result.contains('Successfully created'), 'Should create payment request for multi-year faculty');

        // Verify payment was created
        List<Payment_Information__c> payments = [
            SELECT Id, Academic_Year__c, Faculty__c
            FROM Payment_Information__c
            WHERE Faculty__c = :faculty.Id
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertNotEquals(null, payments[0], 'Payment should be created');
    }

    @isTest
    static void testCreatePaymentRequestsWithSingleYear() {
        Program prog = [SELECT Id FROM Program LIMIT 1];
        AcademicYear year = [SELECT Id FROM AcademicYear WHERE Name = '2024-2025' LIMIT 1];
        AcademicTerm term = [SELECT Id FROM AcademicTerm LIMIT 1];

        AcademicSession session = new AcademicSession(
            Name = 'Single Year Session',
            AcademicTermId = term.Id
        );
        insert session;

        Contact faculty = [SELECT Id FROM Contact LIMIT 1];

        // Update existing offerings to use the session
        List<CourseOffering> offerings = [
            SELECT Id
            FROM CourseOffering
            WHERE Program__c = :prog.Id
            LIMIT 1
        ];
        offerings[0].AcademicSessionId = session.Id;
        offerings[0].Academic_Year__c = year.Id;
        update offerings;

        Test.startTest();
        String result = PaymentRequestController.createPaymentRequestsBySessions(
            new List<Id>{ faculty.Id },
            prog.Id,
            new List<Id>{ session.Id }
        );
        Test.stopTest();

        System.assert(result.contains('Successfully created'), 'Should create payment request');

        // Verify payment has the single academic year
        List<Payment_Information__c> payments = [
            SELECT Academic_Year__c, Faculty__c
            FROM Payment_Information__c
            WHERE Faculty__c = :faculty.Id
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals(year.Id, payments[0].Academic_Year__c, 'Academic Year should be set for single-year faculty');
    }

    @isTest
    static void testGetFacultiesByProgramYearNoResults() {
        // Create program and year with no offerings
        Program emptyProg = new Program(Name = 'Empty Program');
        insert emptyProg;

        AcademicYear emptyYear = new AcademicYear(Name = '2099-2100');
        insert emptyYear;

        Test.startTest();
        List<PaymentRequestController.FacultyWrapper> result =
            PaymentRequestController.getFacultiesByProgramYear(emptyProg.Id, emptyYear.Id);
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Should return empty list when no faculties found');
    }

    @isTest
    static void testFacultyWrapperAggregation() {
        Program prog = [SELECT Id FROM Program LIMIT 1];
        AcademicYear year = [SELECT Id FROM AcademicYear LIMIT 1];

        Test.startTest();
        List<PaymentRequestController.FacultyWrapper> faculties =
            PaymentRequestController.getFacultiesByProgramYear(prog.Id, year.Id);
        Test.stopTest();

        System.assert(faculties.size() > 0, 'Should have faculties');

        // Verify wrapper properties are populated
        PaymentRequestController.FacultyWrapper firstFaculty = faculties[0];
        System.assertNotEquals(null, firstFaculty.facultyId, 'Faculty ID should be populated');
        System.assertNotEquals(null, firstFaculty.facultyName, 'Faculty name should be populated');
        System.assertNotEquals(null, firstFaculty.location, 'Location should be populated');
        System.assertNotEquals(null, firstFaculty.courseOfferings, 'Course offerings should be populated');
        System.assert(firstFaculty.courseCount > 0, 'Course count should be greater than 0');

        // Verify course offering info properties
        PaymentRequestController.CourseOfferingInfo firstCourse = firstFaculty.courseOfferings[0];
        System.assertNotEquals(null, firstCourse.courseOfferingId, 'Course offering ID should be populated');
        System.assertNotEquals(null, firstCourse.courseName, 'Course name should be populated');
    }

    @isTest
    static void testCreatePaymentRequestsWithMappings() {
        Program prog = [SELECT Id FROM Program LIMIT 1];
        AcademicYear year = [SELECT Id FROM AcademicYear LIMIT 1];

        List<PaymentRequestController.FacultyWrapper> faculties =
            PaymentRequestController.getFacultiesByProgramYear(prog.Id, year.Id);

        Integer beforePaymentCount = [SELECT COUNT() FROM Payment_Information__c];
        Integer beforeMappingCount = [SELECT COUNT() FROM Faculty_Term_Mapping__c];

        Test.startTest();
        String result = PaymentRequestController.createPaymentRequests(
            new List<PaymentRequestController.FacultyWrapper>{ faculties[0] },
            prog.Id,
            year.Id
        );
        Test.stopTest();

        Integer afterPaymentCount = [SELECT COUNT() FROM Payment_Information__c];
        Integer afterMappingCount = [SELECT COUNT() FROM Faculty_Term_Mapping__c];

        System.assertEquals(beforePaymentCount + 1, afterPaymentCount, 'Should create exactly 1 payment');
        System.assert(afterMappingCount > beforeMappingCount, 'Should create mappings');
        System.assert(result.contains('1 payment request'), 'Message should mention 1 payment');
    }

    @isTest
    static void testGetFacultiesByProgramSessionsEmptyTermIds() {
        Program prog = [SELECT Id FROM Program LIMIT 1];

        // Create multiple sessions with null terms
        AcademicSession session1 = new AcademicSession(
            Name = 'Session No Term 1',
            AcademicTermId = null
        );
        AcademicSession session2 = new AcademicSession(
            Name = 'Session No Term 2',
            AcademicTermId = null
        );
        insert new List<AcademicSession>{ session1, session2 };

        Test.startTest();
        List<PaymentRequestController.FacultyWrapper> result =
            PaymentRequestController.getFacultiesByProgramSessions(
                prog.Id,
                new List<Id>{ session1.Id, session2.Id }
            );
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Should return empty when all sessions have null term IDs');
    }
}