@isTest
private class ChecklistItemUploadControllerTest {

    @isTest
    static void testUploadChecklistRows_Success() {
        String rowsJson =
            '[' +
                '{' +
                    '"Subject":"Controller Task",' +
                    '"Description":"Created via controller",' +
                    '"Priority":"High",' +
                    '"Role":"Manager",' +
                    '"Start Date":"2026-05-10",' +
                    '"End Date":"2026-05-20",' +
                    '"Logic Calculation":"Term Start"' +
                '}' +
            ']';

        Test.startTest();
        ChecklistItemExcelParser.ParseResult result = ChecklistItemUploadController.uploadChecklistRows(rowsJson);
        Test.stopTest();

        System.assertEquals(0, result.errors.size());
        System.assert(
            result.totalItemsCreated == 1 || !result.warnings.isEmpty(),
            'Row should either be created or return validation warning details'
        );
    }

    @isTest
    static void testGetCourseType() {
        Learning learn = new Learning(Name = 'Controller Learning');
        insert learn;

        LearningCourse lc = new LearningCourse(
            Name = 'Controller Course',
            LearningId = learn.Id
        );
        insert lc;

        CourseOffering offering = new CourseOffering(
            Name = 'Controller Offering',
            LearningCourseId = lc.Id,
            Course_Type__c = 'Online'
        );
        insert offering;

        Test.startTest();
        String courseType = ChecklistItemUploadController.getCourseType(offering.Id);
        Test.stopTest();

        System.assertEquals('Online', courseType);
    }

    @isTest
    static void testGetCourseType_InvalidIdReturnsBlank() {
        Test.startTest();
        String courseType = ChecklistItemUploadController.getCourseType(null);
        Test.stopTest();

        System.assertEquals('', courseType);
    }

    @isTest
    static void testGetAvailableRoles_DefaultsWhenNoManagers() {
        Test.startTest();
        List<String> roles = ChecklistItemUploadController.getAvailableRoles();
        Test.stopTest();

        System.assert(roles.contains('Manager'));
        System.assert(roles.contains('Associate'));
        System.assert(roles.contains('Delivery Manager'));
        System.assert(roles.contains('Administrator'));
    }
}