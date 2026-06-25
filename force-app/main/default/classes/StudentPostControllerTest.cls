@IsTest
public class StudentPostControllerTest {

    @IsTest
    static void testGetPublishedPosts_withValidPosts() {

        Student_Post__c validPost =
            TestDataFactory.createStudentPost(
                'Published',
                Date.today().addDays(5),
                Datetime.now().addDays(-1)
            );

        Student_Post__c noExpiryPost =
            TestDataFactory.createStudentPost(
                'Published',
                null,
                Datetime.now()
            );

        Student_Post__c expiredPost =
            TestDataFactory.createStudentPost(
                'Published',
                Date.today().addDays(-1),
                Datetime.now()
            );

        Student_Post__c draftPost =
            TestDataFactory.createStudentPost(
                'Draft',
                Date.today().addDays(5),
                Datetime.now()
            );

        insert new List<Student_Post__c>{
            validPost, noExpiryPost, expiredPost, draftPost
        };

        Test.startTest();
        List<StudentPostController.PostDTO> results =
            StudentPostController.getPublishedPosts();
        Test.stopTest();

        System.assertEquals(2, results.size(),
            'Only valid published posts should be returned');
    }

    @IsTest
    static void testGetPublishedPosts_noData() {
        Test.startTest();
        List<StudentPostController.PostDTO> results =
            StudentPostController.getPublishedPosts();
        Test.stopTest();

        System.assertEquals(0, results.size());
    }
}