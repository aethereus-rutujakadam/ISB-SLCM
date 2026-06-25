@IsTest
public class AAProfileControllerTest {

    // -------------------------------------------------
    // Utility: Create Admin User
    // -------------------------------------------------
    private static User createUser(String alias) {

        Profile p = [
            SELECT Id
            FROM Profile
            WHERE Name = 'System Administrator'
            LIMIT 1
        ];

        User u = new User(
            FirstName = 'Test',
            LastName  = alias,
            Email     = alias + System.currentTimeMillis() + '@test.com',
            Username  = alias + System.currentTimeMillis() + '@test.com',
            Alias     = alias.substring(0, Math.min(8, alias.length())),
            TimeZoneSidKey     = 'Asia/Kolkata',
            LocaleSidKey       = 'en_US',
            EmailEncodingKey   = 'UTF-8',
            LanguageLocaleKey  = 'en_US',
            ProfileId          = p.Id
        );
        insert u;
        return u;
    }

    // -------------------------------------------------
    // getMyProfileData – SUCCESS
    // -------------------------------------------------
    @IsTest
    static void testGetMyProfileData_success() {

        User u = createUser('aauser');

        System.runAs(u) {

            Contact c = TestDataFactory.testAAContact(u);
            c.Active_Status__c = 'Active';
            update c;

            AcademicTerm term = TestDataFactory.testAcademicTerm();

            TestDataFactory.testAAProfile(term.Id, c.Id);

            Test.startTest();
            Map<String, Object> result =
                AAProfileController.getMyProfileData();
            Test.stopTest();

            System.assertNotEquals(null, result);
            System.assertEquals(c.Id, result.get('contactId'));
            System.assertNotEquals(null, result.get('aaProfileId'));
            System.assertNotEquals(null, result.get('contact'));
        }
    }

    // -------------------------------------------------
    // getMyProfileData – NO CONTACT
    // -------------------------------------------------
    @IsTest
    static void testGetMyProfileData_noContact() {

        User u = createUser('nouser');

        System.runAs(u) {
            Test.startTest();
            try {
                AAProfileController.getMyProfileData();
                System.assert(false, 'Exception expected');
            } catch (AuraHandledException e) {
                System.assert(true);
            }
            Test.stopTest();
        }
    }

    // -------------------------------------------------
    // getTaggedCourses – SUCCESS
    // -------------------------------------------------
    @IsTest
    static void testGetTaggedCourses_success() {

        User u = createUser('tagusr');

        System.runAs(u) {

            // AA Contact
            Contact c = TestDataFactory.testAAContact(u);
            c.Active_Status__c = 'Active';
            update c;

            AcademicTerm term = TestDataFactory.testAcademicTerm();
            AcademicSession session = TestDataFactory.testAcademicSession();
            Program prog = TestDataFactory.testProgram();

            Learning l = TestDataFactory.testLearning();
            LearningCourse lc = TestDataFactory.testLearningCourse(l.Id);

            CourseOffering co =
                TestDataFactory.testCourseOffering(lc.Id, session.Id);
            co.Academic_Term__c = term.Id;
            co.Program__c = prog.Id;
            update co;

            // ACTIVE AA PROFILE (MANDATORY)
            AA_Profile__c profile =
                TestDataFactory.testAAProfile(term.Id, c.Id);
            profile.Status__c = 'Active';
            update profile;

            // ✅ CORRECT METHOD SIGNATURE (NO TestDataFactory CHANGE)
            TestDataFactory.testCourseAAAssignment(
                c.Id,          // Contact Id
                co.Id,         // Course Offering Id
                profile.Id     // AA Profile Id
            );

            Test.startTest();
            List<AAProfileController.CourseAssignmentWrapper> res =
                AAProfileController.getTaggedCourses(profile.Id);
            Test.stopTest();

            System.assertEquals(1, res.size());
            System.assertEquals(co.Name, res[0].courseOfferingName);
        }
    }

    // -------------------------------------------------
    // getTaggedCourses – NULL
    // -------------------------------------------------
    @IsTest
    static void testGetTaggedCourses_null() {

        Test.startTest();
        List<AAProfileController.CourseAssignmentWrapper> res =
            AAProfileController.getTaggedCourses(null);
        Test.stopTest();

        System.assertEquals(0, res.size());
    }

    // -------------------------------------------------
    // updateAvailability – SUCCESS
    // -------------------------------------------------
    @IsTest
    static void testUpdateAvailability_success() {

        User u = createUser('updusr');

        System.runAs(u) {

            Contact c = TestDataFactory.testAAContact(u);
            c.Active_Status__c = 'Active';
            update c;

            AcademicTerm term = TestDataFactory.testAcademicTerm();

            AA_Profile__c profile =
                TestDataFactory.testAAProfile(term.Id, c.Id);
            profile.Status__c = 'Active';
            update profile;

            Test.startTest();
            AAProfileController.updateAvailability(
                profile.Id,
                'Morning (8-a.m. - 12 p.m.)'
            );
            Test.stopTest();

            AA_Profile__c updated =
                [SELECT Availability__c
                 FROM AA_Profile__c
                 WHERE Id = :profile.Id];

            System.assertEquals('Morning (8-a.m. - 12 p.m.)', updated.Availability__c);
        }
    }

    // -------------------------------------------------
    // updateAvailability – NULL ID
    // -------------------------------------------------
    @IsTest
    static void testUpdateAvailability_nullId() {

        Test.startTest();
        try {
            AAProfileController.updateAvailability(null, 'Available');
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }
}