@isTest(SeeAllData=true)
private class RenderEmailTemplateActionTest {

    private static EmailTemplate getAnyTemplate() {
        List<EmailTemplate> templates = [
            SELECT Id, Subject, HtmlValue, Body
            FROM EmailTemplate
            WHERE IsActive = true
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        System.assert(!templates.isEmpty(), 'At least one active email template is required in org data.');
        return templates[0];
    }

    private static EmailTemplate getTextOnlyTemplateOrFallback() {
        List<EmailTemplate> templates = [
            SELECT Id, Subject, HtmlValue, Body
            FROM EmailTemplate
            WHERE IsActive = true
            ORDER BY LastModifiedDate DESC
            LIMIT 200
        ];
        for (EmailTemplate templateRow : templates) {
            if (String.isBlank(templateRow.HtmlValue) && !String.isBlank(templateRow.Body)) {
                return templateRow;
            }
        }
        return getAnyTemplate();
    }

    private static Contact createRecipient() {
        Account acc = new Account(Name = 'RETA Account');
        insert acc;

        Contact c = new Contact(
            FirstName = 'Render',
            LastName = 'Recipient',
            AccountId = acc.Id,
            Email = 'render.recipient@test.com'
        );
        insert c;
        return c;
    }

    @isTest
    static void testRenderTemplateSuccessAndPassThrough() {
        EmailTemplate et = getAnyTemplate();
        Contact c = createRecipient();

        RenderEmailTemplateAction.Request req = new RenderEmailTemplateAction.Request();
        req.templateId = et.Id;
        req.recipientId = c.Id;
        req.threadName = 'TH-1001';
        req.additionalRecipientEmails = new List<String>{ 'cc1@test.com', 'cc2@test.com' };

        Test.startTest();
        List<RenderEmailTemplateAction.Result> results =
            RenderEmailTemplateAction.renderTemplate(new List<RenderEmailTemplateAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertNotEquals(null, results[0].finalSubject);
        System.assert(results[0].finalSubject.contains(et.Subject));
        System.assert(results[0].finalSubject.endsWith('[TH-1001]'));
        System.assertNotEquals(null, results[0].htmlBody);
        System.assertEquals(2, results[0].additionalRecipientEmails.size());
    }

    @isTest
    static void testRenderTemplateFallbackToText() {
        EmailTemplate et = getTextOnlyTemplateOrFallback();
        Contact c = createRecipient();

        RenderEmailTemplateAction.Request req = new RenderEmailTemplateAction.Request();
        req.templateId = et.Id;
        req.recipientId = c.Id;
        req.threadName = 'TH-1002';

        Test.startTest();
        List<RenderEmailTemplateAction.Result> results =
            RenderEmailTemplateAction.renderTemplate(new List<RenderEmailTemplateAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertNotEquals(null, results[0].finalSubject);
        if (String.isBlank(et.HtmlValue) && !String.isBlank(results[0].textBody)) {
            System.assertEquals(results[0].textBody, results[0].htmlBody);
        }
        System.assertEquals(null, results[0].additionalRecipientEmails);
    }

    @isTest
    static void testRenderTemplateExceptionPath() {
        Contact c = createRecipient();

        RenderEmailTemplateAction.Request req = new RenderEmailTemplateAction.Request();
        req.templateId = (Id) '00X000000000001';
        req.recipientId = c.Id;
        req.threadName = 'TH-ERR';

        Test.startTest();
        List<RenderEmailTemplateAction.Result> results =
            RenderEmailTemplateAction.renderTemplate(new List<RenderEmailTemplateAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(null, results[0].finalSubject);
        System.assertEquals(null, results[0].htmlBody);
        System.assertEquals(null, results[0].textBody);
    }
}