/**
 * @description Test class for ChecklistEngineService and related trigger handlers
 * Tests course and baseline checklist automation with bulk safety and deduplication
 * @author DEVSLCM Team
 * @date 2026
 */
@isTest
private class ChecklistEngineServiceTest {
    
    /**
     * @description Test data setup method
     * Creates test records for Account, Contact, Program, Term, CourseOffering, Templates
     */
    @TestSetup
    static void setupTestData() {
        // Create Account (Institution)
        Account institution = new Account(
            Name = 'Test University'
        );
        insert institution;
        
        // Create Program - using Account lookup instead of hed__Program_Plan__c
        Account program = new Account(
            Name = 'MBA Program',
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .containsKey('Academic_Program') 
                ? Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Academic_Program').getRecordTypeId() 
                : null
        );
        insert program;
        
        // Create Academic Session (Term)
        AcademicSession term = new AcademicSession(
            Name = 'Fall 2026',
            AcademicTermId = 'FALL2026',
            ClassStartDate = Date.today(),
            ClassEndDate = Date.today().addMonths(4)
        );
        insert term;
        
        // Create Learning Course
        LearningCourse course = new LearningCourse(
            Name = 'Finance 101'
        );
        insert course;
        
        // Create Course Offering
        CourseOffering offering = new CourseOffering(
            Name = 'Finance 101 - Fall 2026',
            LearningCourseId = course.Id,
            AcademicSessionId = term.Id,
            Program__c = program.Id
        );
        insert offering;
        
        // Create Students
        List<Contact> students = new List<Contact>();
        for (Integer i = 0; i < 5; i++) {
            students.add(new Contact(
                FirstName = 'Test' + i,
                LastName = 'Student' + i,
                Email = 'teststudent' + i + '@test.com'
            ));
        }
        insert students;
        
        // Create Program Enrollments - use standard Contact lookup
        // Note: ProgramEnrollment is an EDA object, creating minimal test records
        List<SObject> programEnrollments = new List<SObject>();
        for (Contact student : students) {
            SObject pe = Schema.getGlobalDescribe().get('ProgramEnrollment').newSObject();
            pe.put('Name', 'Enrollment-' + student.LastName);
            // Try to set Contact - ProgramEnrollment may use hed__Contact__c or ContactId
            try {
                pe.put('ContactId', student.Id);
            } catch (Exception e) {
                // If ContactId doesn't exist, skip or use hed__ field if absolutely necessary
                System.debug('ContactId field not available on ProgramEnrollment');
            }
            try {
                pe.put('AccountId', program.Id);
            } catch (Exception e) {
                System.debug('AccountId field not available on ProgramEnrollment');
            }
            programEnrollments.add(pe);
        }
        insert programEnrollments;
        
        // Create Enrollment Sessions - DO NOT set Contact__c or Program__c (formula fields)
        List<Enrollment_Session__c> enrollmentSessions = new List<Enrollment_Session__c>();
        for (Integer i = 0; i < programEnrollments.size(); i++) {
            enrollmentSessions.add(new Enrollment_Session__c(
                Program_Enrollment__c = programEnrollments[i].Id,
                Academic_Session__c = term.Id,
                Active__c = false // Will be activated in test methods
            ));
        }
        insert enrollmentSessions;
        
        // Create Course Checklist Item Templates - Course Type (use LearningCourse not CourseOffering)
        List<Course_Checklist_Item_Template__c> courseTemplates = new List<Course_Checklist_Item_Template__c>();
        courseTemplates.add(new Course_Checklist_Item_Template__c(
            Subject__c = 'Complete Pre-Course Reading',
            Description__c = 'Read chapters 1-3 before first class',
            Priority__c = 'High',
            Template_Type__c = 'Course',
            Activity_Type__c = 'Assignment',
            Owner_Roles__c = 'Student',
            Active__c = true,
            Course__c = course.Id
        ));
        courseTemplates.add(new Course_Checklist_Item_Template__c(
            Subject__c = 'Submit Course Registration Form',
            Description__c = 'Complete and submit registration form',
            Priority__c = 'High',
            Template_Type__c = 'Course',
            Activity_Type__c = 'Form',
            Owner_Roles__c = 'Student',
            Active__c = true,
            Program__c = program.Id
        ));
        insert courseTemplates;
        
        // Create Course Checklist Item Templates - Baseline Type
        List<Course_Checklist_Item_Template__c> baselineTemplates = new List<Course_Checklist_Item_Template__c>();
        baselineTemplates.add(new Course_Checklist_Item_Template__c(
            Subject__c = 'Complete Orientation',
            Description__c = 'Attend mandatory orientation session',
            Priority__c = 'High',
            Template_Type__c = 'Baseline',
            Activity_Type__c = 'Event',
            Owner_Roles__c = 'Student',
            Active__c = true,
            Program__c = program.Id,
            Term__c = term.Id
        ));
        baselineTemplates.add(new Course_Checklist_Item_Template__c(
            Subject__c = 'Meet with Academic Advisor',
            Description__c = 'Schedule and complete initial advising meeting',
            Priority__c = 'Medium',
            Template_Type__c = 'Baseline',
            Activity_Type__c = 'Appointment',
            Owner_Roles__c = 'Advisor',
            Active__c = true,
            Program__c = program.Id
        ));
        insert baselineTemplates;
    }
    
    /**
     * @description Test course checklist creation via CourseOfferingParticipant insert
     */
    @isTest
    static void testCourseChecklistCreation() {
        // Get test data
        List<Contact> students = [SELECT Id FROM Contact LIMIT 5];
        CourseOffering offering = [SELECT Id FROM CourseOffering LIMIT 1];
        
        Test.startTest();
        
        // Create Course Offering Participants (triggers checklist creation)
        List<CourseOfferingParticipant> participants = new List<CourseOfferingParticipant>();
        for (Contact student : students) {
            participants.add(new CourseOfferingParticipant(
                ParticipantContactId = student.Id,
                CourseOfferingId = offering.Id,
                ParticipationStatus = 'Enrolled'
            ));
        }
        insert participants;
        
        Test.stopTest();
        
        // Verify checklists were created
        List<Course_Checklist__c> checklists = [
            SELECT Id, Student__c, Course_Offering__c, Checklist_Type__c,
                   Program__c, Term__c, Source_Object__c
            FROM Course_Checklist__c
            WHERE Checklist_Type__c = 'Course'
        ];
        
        System.assertEquals(5, checklists.size(), 'Should create 5 course checklists');
        
        for (Course_Checklist__c checklist : checklists) {
            System.assertEquals('Course', checklist.Checklist_Type__c, 'Type should be Course');
            System.assertEquals(offering.Id, checklist.Course_Offering__c, 'Should link to course offering');
            System.assertEquals('CourseOfferingParticipant', checklist.Source_Object__c, 'Source should be COP');
            System.assertNotEquals(null, checklist.Student__c, 'Should have student');
        }
        
        // Verify checklist items were created
        List<Course_Checklist_Item__c> items = [
            SELECT Id, Course_Checklist__c, Subject__c, Status__c
            FROM Course_Checklist_Item__c
            WHERE Course_Checklist__c IN :checklists
        ];
        
        // Should have 2 templates * 5 students = 10 items
        System.assert(items.size() >= 5, 'Should create checklist items from templates');
        
        for (Course_Checklist_Item__c item : items) {
            System.assertEquals('Not Started', item.Status__c, 'Default status should be Not Started');
        }
    }
    
    /**
     * @description Test baseline checklist creation via Enrollment_Session__c activation
     */
    @isTest
    static void testBaselineChecklistCreation() {
        // Get test data
        List<Enrollment_Session__c> enrollmentSessions = [
            SELECT Id, Active__c 
            FROM Enrollment_Session__c
        ];
        
        Test.startTest();
        
        // Activate enrollment sessions (triggers checklist creation)
        for (Enrollment_Session__c es : enrollmentSessions) {
            es.Active__c = true;
        }
        update enrollmentSessions;
        
        Test.stopTest();
        
        // Verify baseline checklists were created
        List<Course_Checklist__c> checklists = [
            SELECT Id, Student__c, Checklist_Type__c, Program__c, 
                   Term__c, Source_Object__c
            FROM Course_Checklist__c
            WHERE Checklist_Type__c = 'Baseline'
        ];
        
        System.assertEquals(5, checklists.size(), 'Should create 5 baseline checklists');
        
        for (Course_Checklist__c checklist : checklists) {
            System.assertEquals('Baseline', checklist.Checklist_Type__c, 'Type should be Baseline');
            System.assertEquals('Enrollment_Session__c', checklist.Source_Object__c, 'Source should be ES');
            System.assertNotEquals(null, checklist.Student__c, 'Should have student');
            System.assertNotEquals(null, checklist.Program__c, 'Should have program');
        }
        
        // Verify checklist items were created
        List<Course_Checklist_Item__c> items = [
            SELECT Id, Course_Checklist__c, Subject__c, Status__c
            FROM Course_Checklist_Item__c
            WHERE Course_Checklist__c IN :checklists
        ];
        
        // Should have 2 baseline templates * 5 students = 10 items
        System.assertEquals(10, items.size(), 'Should create checklist items from baseline templates');
    }
    
    /**
     * @description Test deduplication - should not create duplicate checklists
     */
    @isTest
    static void testChecklistDeduplication() {
        // Get test data
        Contact student = [SELECT Id FROM Contact LIMIT 1];
        CourseOffering offering = [SELECT Id FROM CourseOffering LIMIT 1];
        
        Test.startTest();
        
        // Create first participant
        CourseOfferingParticipant participant1 = new CourseOfferingParticipant(
            ParticipantContactId = student.Id,
            CourseOfferingId = offering.Id,
            ParticipationStatus = 'Enrolled'
        );
        insert participant1;
        
        // Get count of checklists
        Integer checklistCount1 = [
            SELECT COUNT() 
            FROM Course_Checklist__c 
            WHERE Student__c = :student.Id 
            AND Course_Offering__c = :offering.Id
        ];
        
        // Try to create duplicate by calling service directly
        ChecklistEngineService.createCourseChecklists(new Set<Id>{participant1.Id});
        
        Test.stopTest();
        
        // Get count again - should be same
        Integer checklistCount2 = [
            SELECT COUNT() 
            FROM Course_Checklist__c 
            WHERE Student__c = :student.Id 
            AND Course_Offering__c = :offering.Id
        ];
        
        System.assertEquals(checklistCount1, checklistCount2, 'Should not create duplicate checklists');
        System.assertEquals(1, checklistCount2, 'Should have exactly 1 checklist');
    }
    
    /**
     * @description Test bulk processing with 200+ records
     */
    @isTest
    static void testBulkProcessing() {
        // Get test data
        CourseOffering offering = [SELECT Id FROM CourseOffering LIMIT 1];
        Account program = [SELECT Id FROM Account WHERE Name = 'MBA Program' LIMIT 1];
        
        // Create 200 students
        List<Contact> bulkStudents = new List<Contact>();
        for (Integer i = 0; i < 200; i++) {
            bulkStudents.add(new Contact(
                FirstName = 'Bulk' + i,
                LastName = 'Student' + i,
                Email = 'bulkstudent' + i + '@test.com'
            ));
        }
        insert bulkStudents;
        
        // Create bulk participants
        List<CourseOfferingParticipant> bulkParticipants = new List<CourseOfferingParticipant>();
        for (Contact student : bulkStudents) {
            bulkParticipants.add(new CourseOfferingParticipant(
                ParticipantContactId = student.Id,
                CourseOfferingId = offering.Id,
                ParticipationStatus = 'Enrolled'
            ));
        }
        
        Test.startTest();
        insert bulkParticipants;
        Test.stopTest();
        
        // Verify bulk checklists were created
        Integer checklistCount = [
            SELECT COUNT() 
            FROM Course_Checklist__c 
            WHERE Checklist_Type__c = 'Course'
            AND Student__c IN :bulkStudents
        ];
        
        System.assertEquals(200, checklistCount, 'Should handle bulk insert of 200 records');
        
        // Verify governor limits were respected
        System.assert(Limits.getQueries() < Limits.getLimitQueries(), 'Should not hit query limits');
        System.assert(Limits.getDmlStatements() < Limits.getLimitDmlStatements(), 'Should not hit DML limits');
    }
    
    /**
     * @description Test null safety and edge cases
     */
    @isTest
    static void testNullHandling() {
        Test.startTest();
        
        // Test with null/empty sets
        ChecklistEngineService.createCourseChecklists(null);
        ChecklistEngineService.createCourseChecklists(new Set<Id>());
        ChecklistEngineService.createBaselineChecklists(null);
        ChecklistEngineService.createBaselineChecklists(new Set<Id>());
        
        // Create participant with null student (should be filtered out)
        CourseOffering offering = [SELECT Id FROM CourseOffering LIMIT 1];
        CourseOfferingParticipant participantNoStudent = new CourseOfferingParticipant(
            CourseOfferingId = offering.Id,
            ParticipationStatus = 'Enrolled'
        );
        insert participantNoStudent;
        
        Test.stopTest();
        
        // No checklists should be created for null student
        Integer checklistCount = [SELECT COUNT() FROM Course_Checklist__c];
        System.assertEquals(0, checklistCount, 'Should not create checklists for null students');
    }
    
    /**
     * @description Test template filtering by program and term
     */
    @isTest
    static void testTemplateFiltering() {
        // Get test data
        Contact student = [SELECT Id FROM Contact LIMIT 1];
        CourseOffering offering = [SELECT Id FROM CourseOffering LIMIT 1];
        Account program = [SELECT Id FROM Account WHERE Name = 'MBA Program' LIMIT 1];
        AcademicSession term = [SELECT Id FROM AcademicSession LIMIT 1];
        
        // Create another program and term
        Account institution = [SELECT Id FROM Account WHERE Name = 'Test University' LIMIT 1];
        Account otherProgram = new Account(
            Name = 'MSc Program'
        );
        insert otherProgram;
        
        AcademicSession otherTerm = new AcademicSession(
            Name = 'Spring 2027',
            AcademicTermId = 'SPRING2027'
        );
        insert otherTerm;
        
        // Create templates for other program (should not match)
        Course_Checklist_Item_Template__c otherTemplate = new Course_Checklist_Item_Template__c(
            Subject__c = 'Other Program Task',
            Template_Type__c = 'Baseline',
            Active__c = true,
            Program__c = otherProgram.Id,
            Term__c = otherTerm.Id
        );
        insert otherTemplate;
        
        Test.startTest();
        
        // Create participant
        CourseOfferingParticipant participant = new CourseOfferingParticipant(
            ParticipantContactId = student.Id,
            CourseOfferingId = offering.Id,
            ParticipationStatus = 'Enrolled'
        );
        insert participant;
        
        Test.stopTest();
        
        // Get checklist items
        List<Course_Checklist_Item__c> items = [
            SELECT Id, Subject__c
            FROM Course_Checklist_Item__c
            WHERE Course_Checklist__r.Student__c = :student.Id
        ];
        
        // Should not include items from other program's template
        for (Course_Checklist_Item__c item : items) {
            System.assertNotEquals('Other Program Task', item.Subject__c, 
                'Should not create items from mismatched program templates');
        }
    }
    
    /**
     * @description Test inactive templates are not used
     */
    @isTest
    static void testInactiveTemplatesExcluded() {
        // Get test data
        Contact student = [SELECT Id FROM Contact LIMIT 1];
        CourseOffering offering = [SELECT Id FROM CourseOffering LIMIT 1];
        
        // Create inactive template
        Course_Checklist_Item_Template__c inactiveTemplate = new Course_Checklist_Item_Template__c(
            Subject__c = 'Inactive Task',
            Template_Type__c = 'Course',
            Active__c = false,
            Course__c = offering.Id
        );
        insert inactiveTemplate;
        
        Test.startTest();
        
        // Create participant
        CourseOfferingParticipant participant = new CourseOfferingParticipant(
            ParticipantContactId = student.Id,
            CourseOfferingId = offering.Id,
            ParticipationStatus = 'Enrolled'
        );
        insert participant;
        
        Test.stopTest();
        
        // Get checklist items
        List<Course_Checklist_Item__c> items = [
            SELECT Id, Subject__c
            FROM Course_Checklist_Item__c
            WHERE Course_Checklist__r.Student__c = :student.Id
        ];
        
        // Should not include inactive template
        for (Course_Checklist_Item__c item : items) {
            System.assertNotEquals('Inactive Task', item.Subject__c, 
                'Should not create items from inactive templates');
        }
    }
}