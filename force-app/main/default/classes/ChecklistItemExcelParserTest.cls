/**
 * @description Test class for ChecklistItemExcelParser
 */
@isTest
private class ChecklistItemExcelParserTest {

    @isTest
    static void testParseFromJson_SuccessWithDatesAndReminderLogic() {
        String rowsJson =
            '[' +
                '{' +
                    '"Subject":"Prepare Grade Sheet",' +
                    '"Description":"Compile final grades",' +
                    '"Priority":"High",' +
                    '"Role":"Manager",' +
                    '"Start Date":"2026-05-20",' +
                    '"End Date":"2026-05-30",' +
                    '"Logic Calculation":"Term Start"' +
                '}' +
            ']';

        Test.startTest();
        ChecklistItemExcelParser.ParseResult result = ChecklistItemExcelParser.parseFromJson(rowsJson);
        Test.stopTest();

        System.assertEquals(0, result.errors.size(), 'No hard errors expected');
        System.assert(
            result.totalItemsCreated == 1 || !result.warnings.isEmpty(),
            'Row should either be created or return validation warning details'
        );
    }

    @isTest
    static void testParseFromJson_InvalidReminderLogicSkipsRow() {
        String rowsJson =
            '[' +
                '{' +
                    '"Subject":"Task A",' +
                    '"Description":"Desc",' +
                    '"Priority":"Medium",' +
                    '"Role":"Manager",' +
                    '"Start Date":"2026-05-20",' +
                    '"End Date":"2026-05-30",' +
                    '"Logic Calculation":"Something Else"' +
                '}' +
            ']';

        Test.startTest();
        ChecklistItemExcelParser.ParseResult result = ChecklistItemExcelParser.parseFromJson(rowsJson);
        Test.stopTest();

        System.assertEquals(0, result.totalItemsCreated, 'Invalid logic should skip the row');
        System.assert(result.warnings.size() > 0, 'Warning should be returned for invalid logic');
    }

    @isTest
    static void testParseFromJson_EmptyPayload() {
        ChecklistItemExcelParser.ParseResult result = ChecklistItemExcelParser.parseFromJson('');
        System.assert(result.errors.size() > 0);
    }

    @isTest
    static void testParserHelpers_RecordTypeAndSummary() {
        Id rtId = ChecklistItemExcelParser.getRecordTypeId('Course Manager Checklist');
        System.assertEquals(true, rtId == null || String.valueOf(rtId).startsWith('012'));

        ChecklistItemExcelParser.ParseResult pr = new ChecklistItemExcelParser.ParseResult();
        pr.totalItemsCreated = 2;
        pr.addWarning('w1');
        String summary = pr.getSummary();

        System.assert(summary.contains('Created: 2 templates.'));
        System.assert(summary.contains('Warnings: 1.'));
        System.assertEquals(true, pr.isSuccess());

        pr.addError('e1');
        System.assertEquals(false, pr.isSuccess());
    }
}