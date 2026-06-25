@isTest
public class CourseOfferingPtcpResultHandlerTest {

    @testSetup
    static void setup() {
        // Basic infrastructure
        Contact con = TestDataFactory.testContact();
        Program prog = TestDataFactory.testProgram();
        ProgramEnrollment pe = TestDataFactory.testProgramEnrollment(con, prog);
        
        // Session 1
        AcademicTerm term1 = TestDataFactory.testAcademicTerm(prog.Id);
        AcademicSession sess1 = TestDataFactory.testAcademicSession();
        sess1.AcademicTermId = term1.Id;
        update sess1;
        
        Enrollment_Session__c es1 = TestDataFactory.createEnrollmentSession(pe.Id, sess1.Id);
        
        // Course 1 (Core)
        Learning lrn1 = TestDataFactory.testLearning();
        LearningCourse lc1 = TestDataFactory.testLearningCourse(lrn1.Id);
        CourseOffering co1 = TestDataFactory.testCourseOffering(lc1.Id, sess1.Id);
        CourseOfferingParticipant cop1 = TestDataFactory.testCourseOfferingParticipant(co1.Id, con.Id);
        cop1.Course_Type__c = 'Core';
        update cop1;
        
        // Course 2 (Elective)
        Learning lrn2 = TestDataFactory.testLearning();
        LearningCourse lc2 = TestDataFactory.testLearningCourse(lrn2.Id);
        CourseOffering co2 = TestDataFactory.testCourseOffering(lc2.Id, sess1.Id);
        CourseOfferingParticipant cop2 = TestDataFactory.testCourseOfferingParticipant(co2.Id, con.Id);
        cop2.Course_Type__c = 'Elective';
        update cop2;
        
        // Session 2
        AcademicTerm term2 = TestDataFactory.testAcademicTerm(prog.Id);
        AcademicSession sess2 = TestDataFactory.testAcademicSession();
        sess2.AcademicTermId = term2.Id;
        update sess2;
        
        Enrollment_Session__c es2 = TestDataFactory.createEnrollmentSession(pe.Id, sess2.Id);
        
        // Course 3 (Core)
        Learning lrn3 = TestDataFactory.testLearning();
        LearningCourse lc3 = TestDataFactory.testLearningCourse(lrn3.Id);
        CourseOffering co3 = TestDataFactory.testCourseOffering(lc3.Id, sess2.Id);
        CourseOfferingParticipant cop3 = TestDataFactory.testCourseOfferingParticipant(co3.Id, con.Id);
        cop3.Course_Type__c = 'Core';
        update cop3;

        // Store some IDs in a way we can retrieve easily
        // (Contact is already in TestDataFactory.testDataMap)
    }

    @isTest
    static void testInsertResults() {
        CourseOfferingParticipant cop1 = [SELECT Id, CourseOffering.LearningCourseId FROM CourseOfferingParticipant WHERE Course_Type__c = 'Core' AND CourseOffering.AcademicSession.Name = '2025 Fall' LIMIT 1];
        CourseOfferingParticipant cop2 = [SELECT Id, CourseOffering.LearningCourseId FROM CourseOfferingParticipant WHERE Course_Type__c = 'Elective' LIMIT 1];
        
        // Update LearningCourse credits to ensure formula works
        LearningCourse lc1 = new LearningCourse(Id = cop1.CourseOffering.LearningCourseId, Credit__c = 3);
        LearningCourse lc2 = new LearningCourse(Id = cop2.CourseOffering.LearningCourseId, Credit__c = 3);
        update new List<LearningCourse>{lc1, lc2};

        List<CourseOfferingPtcpResult> results = new List<CourseOfferingPtcpResult>{
            new CourseOfferingPtcpResult(
                CourseOfferingParticipantId = cop1.Id,
                NumericGrade = 1, // Becomes Earned_Credits__c = 1 * 3 = 3
                Grade_Letter__c = 'A'
            ),
            new CourseOfferingPtcpResult(
                CourseOfferingParticipantId = cop2.Id,
                NumericGrade = 0.6666, // Becomes Earned_Credits__c = 0.6666 * 3 = 2 (approx)
                Grade_Letter__c = 'B'
            )
        };
        
        Test.startTest();
        insert results;
        Test.stopTest();
        
        ProgramEnrollment pe = [SELECT CGPA__c, Core_CGPA__c, Elective_CGPA__c FROM ProgramEnrollment LIMIT 1];
        // Session 1: 
        // Core: 3 earned / 3 attempted = 1.0 (relative)
        // Elective: 2 earned / 3 attempted = 0.666
        // Total: 5 earned / 6 attempted = 0.8333
        
        System.assertEquals(0.8333, pe.CGPA__c.setScale(4));
        System.assertEquals(1.0, pe.Core_CGPA__c.setScale(1));
        System.assertEquals(0.6667, pe.Elective_CGPA__c.setScale(4));
        
        Enrollment_Session__c es = [SELECT GPA__c FROM Enrollment_Session__c WHERE Academic_Session__r.Name = '2025 Fall' LIMIT 1];
        System.assertEquals(0.8333, es.GPA__c.setScale(4));
    }

    @isTest
    static void testUpdateResults() {
        CourseOfferingParticipant cop1 = [SELECT Id, CourseOffering.LearningCourseId FROM CourseOfferingParticipant WHERE Course_Type__c = 'Core' LIMIT 1];
        update new LearningCourse(Id = cop1.CourseOffering.LearningCourseId, Credit__c = 3);

        CourseOfferingPtcpResult res = new CourseOfferingPtcpResult(
            CourseOfferingParticipantId = cop1.Id,
            NumericGrade = 1,
            Grade_Letter__c = 'A'
        );
        insert res;
        
        Test.startTest();
        res.NumericGrade = 0;
        res.Grade_Letter__c = 'F';
        update res;
        Test.stopTest();
        
        ProgramEnrollment pe = [SELECT CGPA__c, Failed_Courses__c FROM ProgramEnrollment LIMIT 1];
        System.assertEquals(0, pe.CGPA__c);
        System.assertEquals(1, pe.Failed_Courses__c);
    }

    @isTest
    static void testMultipleSessions() {
        List<CourseOfferingParticipant> cops = [SELECT Id, CourseOffering.LearningCourseId, CourseOffering.AcademicSessionId FROM CourseOfferingParticipant ORDER BY CourseOffering.AcademicSessionId];
        
        List<LearningCourse> lcs = new List<LearningCourse>();
        for (CourseOfferingParticipant cop : cops) {
            lcs.add(new LearningCourse(Id = cop.CourseOffering.LearningCourseId, Credit__c = 3));
        }
        update lcs;

        CourseOfferingPtcpResult res1 = new CourseOfferingPtcpResult(
            CourseOfferingParticipantId = cops[0].Id,
            NumericGrade = 1,
            Grade_Letter__c = 'A'
        );
        CourseOfferingPtcpResult res2 = new CourseOfferingPtcpResult(
            CourseOfferingParticipantId = cops[2].Id, // Course 3 from Session 2
            NumericGrade = 1,
            Grade_Letter__c = 'A'
        );
        
        Test.startTest();
        insert new List<CourseOfferingPtcpResult>{res1, res2};
        Test.stopTest();
        
        ProgramEnrollment pe = [SELECT CGPA__c, Overall_Earned_Credits__c FROM ProgramEnrollment LIMIT 1];
        System.assertEquals(1.0, pe.CGPA__c);
        System.assertEquals(6, pe.Overall_Earned_Credits__c);
    }

    @isTest
    static void testDeleteResult() {
        CourseOfferingParticipant cop1 = [SELECT Id, CourseOffering.LearningCourseId FROM CourseOfferingParticipant LIMIT 1];
        update new LearningCourse(Id = cop1.CourseOffering.LearningCourseId, Credit__c = 3);

        CourseOfferingPtcpResult res = new CourseOfferingPtcpResult(
            CourseOfferingParticipantId = cop1.Id,
            NumericGrade = 1,
            Grade_Letter__c = 'A'
        );
        insert res;
        
        ProgramEnrollment peBefore = [SELECT CGPA__c FROM ProgramEnrollment LIMIT 1];
        System.assertEquals(1.0, peBefore.CGPA__c);
        
        Test.startTest();
        delete res;
        Test.stopTest();
        
        ProgramEnrollment peAfter = [SELECT CGPA__c FROM ProgramEnrollment LIMIT 1];
        System.assertEquals(0, peAfter.CGPA__c);
    }
}