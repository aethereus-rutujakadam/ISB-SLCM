@IsTest
private class CourseFacultyTriggerTest {
    @IsTest
    static void createsPaymentInformationOnCourseFacultyInsert() {
        Id facultyRtId = Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName()
            .get('Faculty')
            .getRecordTypeId();

        Contact faculty = new Contact(
            FirstName = 'Trigger',
            LastName = 'Faculty',
            RecordTypeId = facultyRtId,
            Email = 'trigger.faculty+' + System.currentTimeMillis() + '@test.com',
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = 'trigger.faculty@test.com',
            Faculty_Type__c = 'Visiting Faculty',
            Location__c = 'Mohali'
        );
        insert faculty;

        Program program = new Program(Name = 'Trigger Test Program');
        insert program;

        AcademicYear year = new AcademicYear(Name = '2026-2027');
        insert year;

        AcademicTerm term = new AcademicTerm(Name = 'Term Trigger Test');
        insert term;

        Learning learning = new Learning(Name = 'Trigger Test Learning');
        insert learning;

        LearningCourse lc = new LearningCourse(
            Name = 'Trigger Test Course',
            LearningId = learning.Id
        );
        insert lc;

        CourseOffering offering = new CourseOffering(
            Name = 'Trigger Test Offering',
            LearningCourseId = lc.Id,
            Academic_Term__c = term.Id,
            Program__c = program.Id,
            Academic_Year__c = year.Id,
            StartDate = Date.today(),
            EndDate = Date.today().addDays(10),
            Grade_Release_Date__c = System.now()
        );
        insert offering;

        Test.startTest();
        Course_Faculty__c cf = new Course_Faculty__c(
            Faculty__c = faculty.Id,
            Course_Offering__c = offering.Id
        );
        insert cf;
        Test.stopTest();

        List<Payment_Information__c> pis = [
            SELECT Id, Faculty__c, Course_Faculty__c, Course_Offering__c, Program__c, Academic_Year__c
            FROM Payment_Information__c
            WHERE Course_Faculty__c = :cf.Id
        ];

        System.assertEquals(1, pis.size(), 'Exactly one payment record should be created by the trigger.');
        System.assertEquals(faculty.Id, pis[0].Faculty__c, 'Faculty lookup should match Course Faculty record.');
        System.assertEquals(offering.Id, pis[0].Course_Offering__c, 'Course offering lookup should match Course Faculty record.');
        System.assertEquals(program.Id, pis[0].Program__c, 'Program should be populated from Course Offering.');
        System.assertEquals(year.Id, pis[0].Academic_Year__c, 'Academic year should be populated from Course Offering.');
    }
}