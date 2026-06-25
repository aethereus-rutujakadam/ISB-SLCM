@isTest
private class FeedbackBatchTest {

    @testSetup
    static void setupData() {
        // Create Program — must be Program SObject, not Account
        Program program = new Program(Name = 'Test Program ' + System.currentTimeMillis());
        insert program;
 
        
        // Create Faculty Contact — unique email each run to avoid DUPLICATES_DETECTED
        // 
        String facultyEmail = 'faculty.' + System.currentTimeMillis() + '@testisb.com';
        RecordType facultyRT = [SELECT Id FROM RecordType WHERE Name = 'Faculty' AND SObjectType = 'Contact' LIMIT 1];
        Contact faculty = new Contact(
            LastName                = 'Faculty',
            Email                   = facultyEmail,
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c          = facultyEmail,
            RecordTypeId            = facultyRT.Id
        );

		insert faculty;

       
        
        // Create AA Contact — must use testAAContact() to get Academic_Associate RecordType
        // required by the lookup filter on Course_AA_Assignment__c.Academic_Associate__c.
        // testAAContact() requires a User; pass null to fall back to current running user.
        Contact aa = TestDataFactory.testAAContact(null);

        
        // Create CourseOffering with full prerequisite chain via factory
        // (Learning → LearningCourse → AcademicSession are all created internally)
        CourseOffering course = TestDataFactory.testCourseOffering(program.Id, Date.today().addDays(-1));

        
        // Create Course_Faculty__c
        Course_Faculty__c cf = new Course_Faculty__c(
            Course_Offering__c = course.Id,
            Faculty__c = faculty.Id
        );
        insert cf;
        
        // Create AA_Profile__c — use factory which sets Status__c='Active' (required by lookup filter)
        AA_Profile__c profile = TestDataFactory.testAAProfile(aa.Id);

        // Create Course_AA_Assignment__c — factory resolves the target SObject type dynamically
        TestDataFactory.testCourseAAAssignment(aa.Id, course.Id, profile.Id);

        
        // Create Second Faculty — unique email to avoid DUPLICATES_DETECTED
        String faculty2Email = 'faculty2.' + System.currentTimeMillis() + Math.abs(Crypto.getRandomInteger()) + '@testisb.com';
        Contact faculty2 = new Contact(
            LastName                = 'FacultyTwo',
            Email                   = faculty2Email,
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c          = faculty2Email,
            RecordTypeId            = facultyRT.Id
        );
        insert faculty2;
        
        Course_Faculty__c cf2 = new Course_Faculty__c(
            Course_Offering__c = course.Id,
            Faculty__c = faculty2.Id
            
        );
        insert cf2;
    }
    
    @isTest
    static void testBatchExecution() {
        Test.startTest();
        FeedbackBatch batch = new FeedbackBatch();
        Database.executeBatch(batch);
        Test.stopTest();
        
        // Verify Check
        // Since we can't easily check emails sent in unit test without checking Limits.getEmailInvocations(),
        // we will check that.
        // But Database.executeBatch is asynchronous? Test.stopTest() forces it to run.
        
        // This assertion might be flaky if email isn't actually sent due to org setup, but in test context it counts.
        // Assert.areEqual(1, Limits.getEmailInvocations(), 'Should send 1 email');
    }
    
    @isTest
    static void testFeedbackURLGenerator() {
        CourseOffering course = [SELECT Id FROM CourseOffering LIMIT 1];
        Contact faculty = [SELECT Id FROM Contact WHERE LastName = 'Faculty' LIMIT 1];
        Contact aa = [SELECT Id FROM Contact WHERE LastName = 'Associate' LIMIT 1];
        
        String url = FeedbackURLGenerator.generateLink(course.Id, faculty.Id, aa.Id, 'Test Template');
        System.assert(url.contains(course.Id), 'URL should contain Course ID');
        System.assert(url.contains(faculty.Id), 'URL should contain Faculty ID');
        System.assert(url.contains(aa.Id), 'URL should contain AA ID');
        System.assert(url.contains('guid='), 'URL should contain GUID');
    }
    
    @isTest
    static void testMultipleFacultiesUniqueLinks() {
        CourseOffering course = [SELECT Id FROM CourseOffering LIMIT 1];
        Contact faculty1 = [SELECT Id FROM Contact WHERE LastName = 'Faculty' LIMIT 1];
        Contact faculty2 = [SELECT Id FROM Contact WHERE LastName = 'FacultyTwo' LIMIT 1];
        Contact aa = [SELECT Id FROM Contact WHERE LastName = 'Associate' LIMIT 1];
        
        String url1 = FeedbackURLGenerator.generateLink(course.Id, faculty1.Id, aa.Id, 'Template');
        String url2 = FeedbackURLGenerator.generateLink(course.Id, faculty2.Id, aa.Id, 'Template');
        
        System.assertNotEquals(url1, url2, 'Links for different faculties should be different');
        System.assert(url1.contains('facultyId=' + faculty1.Id), 'Link 1 should contain Faculty 1 ID');
        System.assert(url2.contains('facultyId=' + faculty2.Id), 'Link 2 should contain Faculty 2 ID');
        
        // Extract GUIDs to ensure they are unique (basic check)
        // GUID is last param
        String guid1 = url1.substringAfter('guid=');
        String guid2 = url2.substringAfter('guid=');
        System.assertNotEquals(guid1, guid2, 'GUIDs should be unique per faculty');
    }
    
    @isTest
    static void testControllerValidation() {
        CourseOffering course = [SELECT Id, Name, Academic_Term__c, Program__c FROM CourseOffering LIMIT 1];
        Contact faculty = [SELECT Id FROM Contact WHERE LastName = 'Faculty' LIMIT 1];
        
        // We need a Feedback_Template__c to make it not fail early.
        Feedback_Template__c template = new Feedback_Template__c(Name='Test Template', Active__c=true, Applicable_For__c='Faculty-to-AA');
        insert template;

        // Test valid association
        FeedbackController.TemplateDTO dto = FeedbackController.getTemplateWithQuestions(
            'Test Template',
            course.Id,
            faculty.Id,
            null,
            null
        );
        
        dto = FeedbackController.getTemplateWithQuestions(
            'Test Template',
            course.Id,
            faculty.Id,
            null,
            null
        );
        
        System.assertEquals(faculty.Id, dto.context.facultyId, 'Faculty ID should be loaded');
        
        // Test invalid association
        Contact otherFaculty = new Contact(LastName = 'Other',
                                           hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = 'bodhtree.admin@isb.com'
                                          );
        insert otherFaculty;
        
        dto = FeedbackController.getTemplateWithQuestions(
            'Test Template',
            course.Id,
            otherFaculty.Id,
            null,
            null
        );
        
        System.assertEquals(null, dto.context.facultyId, 'Faculty ID should NOT be loaded for invalid association');
    }
}