@IsTest
public class FeedbackURLGeneratorTest {

    /* =====================================================
       TEST SETUP
       ===================================================== */
    @TestSetup
    static void setupData() {

        // Faculty User
        User faculty =
            TestDataFactory.testUser('facUsr', 'faculty@test.com');

        // Academic Associate User + Contact
        User aaUser =
            TestDataFactory.testUser('aaUsr', 'aa@test.com');

        TestDataFactory.testAAContact(aaUser);
    }

    /* =====================================================
       INVOCABLE – FACULTY TO AA FEEDBACK
       ===================================================== */
    @IsTest
    static void test_generateFeedbackURL_FacultyToAA() {

        // Use ANY valid Id — object type is irrelevant
        Id fakeCourseOfferingId = UserInfo.getUserId();

        Contact aaContact =
            [SELECT Id, Name FROM Contact LIMIT 1];

        User faculty =
            [SELECT Id FROM User WHERE Alias = 'facUsr' LIMIT 1];

        FeedbackURLGenerator.FeedbackURLRequest req =
            new FeedbackURLGenerator.FeedbackURLRequest();
        req.courseOfferingId = fakeCourseOfferingId;
        req.academicAssociateId = aaContact.Id;
        req.facultyId = faculty.Id;
        req.templateName = 'Faculty-AA';

        Test.startTest();
        List<FeedbackURLGenerator.FeedbackURLResponse> res =
            FeedbackURLGenerator.generateFeedbackURLs(
                new List<FeedbackURLGenerator.FeedbackURLRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, res.size());
        System.assertNotEquals(null, res[0].feedbackUrl);
        System.assertNotEquals(null, res[0].guid);
        System.assert(res[0].guid.contains('AA'));
        System.assertEquals(aaContact.Name, res[0].aaName);
    }

    /* =====================================================
       INVOCABLE – FACULTY TO ASA FEEDBACK
       ===================================================== */
    @IsTest
    static void test_generateFeedbackURL_FacultyToASA() {

        Id fakeCourseOfferingId = UserInfo.getUserId();

        User faculty =
            [SELECT Id FROM User WHERE Alias = 'facUsr' LIMIT 1];

        FeedbackURLGenerator.FeedbackURLRequest req =
            new FeedbackURLGenerator.FeedbackURLRequest();
        req.courseOfferingId = fakeCourseOfferingId;
        req.facultyId = faculty.Id;
        req.templateName = 'Faculty-ASA';

        Test.startTest();
        List<FeedbackURLGenerator.FeedbackURLResponse> res =
            FeedbackURLGenerator.generateFeedbackURLs(
                new List<FeedbackURLGenerator.FeedbackURLRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, res.size());
        System.assertNotEquals(null, res[0].feedbackUrl);
        System.assert(res[0].guid.contains('ASA'));
        System.assertEquals('Academic Services', res[0].aaName);
    }

    /* =====================================================
       INVOCABLE – AA + ASA TOGETHER
       ===================================================== */
    @IsTest
    static void test_generateFeedbackURL_WithASAAdditionalLink() {

        Id fakeCourseOfferingId = UserInfo.getUserId();

        Contact aaContact =
            [SELECT Id FROM Contact LIMIT 1];

        User faculty =
            [SELECT Id FROM User WHERE Alias = 'facUsr' LIMIT 1];

        FeedbackURLGenerator.FeedbackURLRequest req =
            new FeedbackURLGenerator.FeedbackURLRequest();
        req.courseOfferingId = fakeCourseOfferingId;
        req.academicAssociateId = aaContact.Id;
        req.facultyId = faculty.Id;
        req.templateName = 'Faculty-AA';
        req.includeASAFeedback = true;

        Test.startTest();
        List<FeedbackURLGenerator.FeedbackURLResponse> res =
            FeedbackURLGenerator.generateFeedbackURLs(
                new List<FeedbackURLGenerator.FeedbackURLRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, res.size());
        System.assertNotEquals(null, res[0].feedbackUrl);
        System.assertNotEquals(null, res[0].asaFeedbackUrl);
        System.assertNotEquals(null, res[0].asaGuid);
    }

    /* =====================================================
       NON-INVOCABLE METHOD – generateLink()
       ===================================================== */
    @IsTest
    static void test_generateLink_method() {

        Id fakeCourseOfferingId = UserInfo.getUserId();

        Contact aaContact =
            [SELECT Id FROM Contact LIMIT 1];

        User faculty =
            [SELECT Id FROM User WHERE Alias = 'facUsr' LIMIT 1];

        Test.startTest();
        String url =
            FeedbackURLGenerator.generateLink(
                fakeCourseOfferingId,
                faculty.Id,
                aaContact.Id,
                'Faculty-AA'
            );
        Test.stopTest();

        System.assertNotEquals(null, url);
        System.assert(url.contains('template=Faculty-AA'));
        System.assert(url.contains('guid='));
    }

    /* =====================================================
       EXPERIENCE CLOUD BASE URL
       ===================================================== */
    @IsTest
    static void test_getExperienceCloudBaseUrl() {

        Test.startTest();
        String baseUrl = FeedbackURLGenerator.getExperienceCloudBaseUrl();
        Test.stopTest();

        System.assertNotEquals(null, baseUrl);
        System.assert(
            baseUrl.contains('.site.com'),
            'Expected Experience Cloud style URL'
        );
    }
}