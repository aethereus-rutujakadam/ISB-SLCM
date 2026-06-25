@isTest
public class CourseOfferingParticipantHandlerTest {

    @testSetup
    static void setup() {
        Contact con1 = TestDataFactory.testContact();
        Contact con2 = TestDataFactory.testContact();
        
        AcademicSession sess = TestDataFactory.testAcademicSession();
        Learning lrn = TestDataFactory.testLearning();
        LearningCourse lc = TestDataFactory.testLearningCourse(lrn.Id);
        
        TestDataFactory.testCourseOffering(lc.Id, sess.Id);
    }

    @isTest
    static void testInsertUniqueParticipants() {
        CourseOffering co = [SELECT Id FROM CourseOffering LIMIT 1];
        List<Contact> contacts = [SELECT Id FROM Contact];
        
        List<CourseOfferingParticipant> participants = new List<CourseOfferingParticipant>();
        for (Contact con : contacts) {
            participants.add(new CourseOfferingParticipant(
                CourseOfferingId = co.Id,
                ParticipantContactId = con.Id
            ));
        }
        
        Test.startTest();
        insert participants;
        Test.stopTest();
        
        System.assertEquals(2, [SELECT count() FROM CourseOfferingParticipant]);
    }

    @isTest
    static void testInsertDuplicateInBatch() {
        CourseOffering co = [SELECT Id FROM CourseOffering LIMIT 1];
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        
        List<CourseOfferingParticipant> participants = new List<CourseOfferingParticipant>{
            new CourseOfferingParticipant(CourseOfferingId = co.Id, ParticipantContactId = con.Id),
            new CourseOfferingParticipant(CourseOfferingId = co.Id, ParticipantContactId = con.Id)
        };
        
        Test.startTest();
        try {
            insert participants;
            System.assert(false, 'Should have thrown a duplicate error');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('This Contact is already added as a participant for this Course Offering.'), 'Error message should match');
        }
        Test.stopTest();
    }

    @isTest
    static void testInsertDuplicateExisting() {
        CourseOffering co = [SELECT Id FROM CourseOffering LIMIT 1];
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        
        insert new CourseOfferingParticipant(CourseOfferingId = co.Id, ParticipantContactId = con.Id);
        
        CourseOfferingParticipant dup = new CourseOfferingParticipant(CourseOfferingId = co.Id, ParticipantContactId = con.Id);
        
        Test.startTest();
        try {
            insert dup;
            System.assert(false, 'Should have thrown a duplicate error');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('Duplicate participant: this Contact is already a participant for this Course.'), 'Error message should match');
        }
        Test.stopTest();
    }

    @isTest
    static void testUpdateToDuplicate() {
        CourseOffering co = [SELECT Id FROM CourseOffering LIMIT 1];
        List<Contact> contacts = [SELECT Id FROM Contact];
        
        insert new CourseOfferingParticipant(CourseOfferingId = co.Id, ParticipantContactId = contacts[0].Id);
        CourseOfferingParticipant cop2 = new CourseOfferingParticipant(CourseOfferingId = co.Id, ParticipantContactId = contacts[1].Id);
        insert cop2;
        
        cop2.ParticipantContactId = contacts[0].Id;
        
        Test.startTest();
        try {
            update cop2;
            System.assert(false, 'Should have thrown a duplicate error');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('Duplicate participant: this Contact is already a participant for this Course.'), 'Error message should match');
        }
        Test.stopTest();
    }

    @isTest
    static void testUpdateNoChange() {
        CourseOffering co = [SELECT Id FROM CourseOffering LIMIT 1];
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        
        CourseOfferingParticipant cop = new CourseOfferingParticipant(CourseOfferingId = co.Id, ParticipantContactId = con.Id);
        insert cop;
        
        Test.startTest();
        update cop; // Should not trigger duplicate error even though it matches DB (it's itself)
        Test.stopTest();
        
        System.assertEquals(1, [SELECT count() FROM CourseOfferingParticipant]);
    }
}