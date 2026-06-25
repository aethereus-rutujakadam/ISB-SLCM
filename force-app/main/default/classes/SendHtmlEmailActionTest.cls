@isTest
private class SendHtmlEmailActionTest {

    private static EmailTemplate getAnyActiveTemplate() {
        List<EmailTemplate> templates = [
            SELECT Id, Name, Subject, Folder.Name, HtmlValue, Body
            FROM EmailTemplate
            WHERE IsActive = true
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        System.assert(!templates.isEmpty(), 'At least one active email template is required in org data.');
        return templates[0];
    }

    private static EmailTemplate getTemplateWithFolder() {
        List<EmailTemplate> templates = [
            SELECT Id, Name, Subject, Folder.Name, HtmlValue, Body
            FROM EmailTemplate
            WHERE IsActive = true
              AND Folder.Name != null
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        System.assert(!templates.isEmpty(), 'At least one active email template with folder is required in org data.');
        return templates[0];
    }

    private static EmailTemplate getTextOnlyTemplateOrFallback() {
        List<EmailTemplate> templates = [
            SELECT Id, Name, Subject, Folder.Name, HtmlValue, Body
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
        return getAnyActiveTemplate();
    }

    private static Contact createTemplateRecipient(String lastNameValue) {
        Account acc = new Account(Name = lastNameValue + ' Account');
        insert acc;

        Contact c = new Contact(
            FirstName = 'Template',
            LastName = lastNameValue,
            AccountId = acc.Id,
            Email = lastNameValue.toLowerCase() + '@test.com'
        );
        insert c;
        return c;
    }
    
    @isTest
    static void testSendEmailSuccess() {
        // Setup test data
        SendHtmlEmailAction.Request req = new SendHtmlEmailAction.Request();
        req.htmlBody = '<p>Test <strong>HTML</strong> email body</p>';
        req.subject = 'Test Email Subject';
        req.toAddresses = new List<String>{'test@example.com'};
        // Note: org-wide email address won't exist in test context, will use default
        req.orgWideEmailAddress = null;
        
        Test.startTest();
        List<SendHtmlEmailAction.Result> results = SendHtmlEmailAction.sendEmail(
            new List<SendHtmlEmailAction.Request>{req}
        );
        Test.stopTest();
        
        // Verify results
        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(true, results[0].isSuccess, 'Email should be sent successfully');
        System.assertEquals(null, results[0].errorMessage, 'No error message expected');
    }
    
    @isTest
    static void testSendEmailWithOrgWideAddress() {
        // Create a test org-wide email address (in test context this won't actually exist)
        SendHtmlEmailAction.Request req = new SendHtmlEmailAction.Request();
        req.htmlBody = '<p>Test email with org-wide address</p>';
        req.subject = 'Test Subject';
        req.toAddresses = new List<String>{'faculty@test.com'};
        req.orgWideEmailAddress = 'test@orgwide.com';
        
        Test.startTest();
        List<SendHtmlEmailAction.Result> results = SendHtmlEmailAction.sendEmail(
            new List<SendHtmlEmailAction.Request>{req}
        );
        Test.stopTest();
        
        // In test context, org-wide address won't be found but email should still process
        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(true, results[0].isSuccess, 'Email should be sent successfully');
    }
    
    @isTest
    static void testSendEmailNoRecipients() {
        SendHtmlEmailAction.Request req = new SendHtmlEmailAction.Request();
        req.htmlBody = '<p>Test email</p>';
        req.subject = 'Test Subject';
        req.toAddresses = new List<String>(); // Empty list
        req.orgWideEmailAddress = null;
        
        Test.startTest();
        List<SendHtmlEmailAction.Result> results = SendHtmlEmailAction.sendEmail(
            new List<SendHtmlEmailAction.Request>{req}
        );
        Test.stopTest();
        
        // Verify validation error
        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(false, results[0].isSuccess, 'Should fail due to no recipients');
        System.assert(results[0].errorMessage.contains('No recipient'), 
                      'Error message should mention no recipients');
    }
    
    @isTest
    static void testSendEmailMultipleRecipients() {
        SendHtmlEmailAction.Request req = new SendHtmlEmailAction.Request();
        req.htmlBody = '<p>Test email to multiple recipients</p>';
        req.subject = 'Multi-recipient Test';
        req.toAddresses = new List<String>{
            'faculty1@test.com',
            'faculty2@test.com',
            'faculty3@test.com'
        };
        req.orgWideEmailAddress = null;
        
        Test.startTest();
        List<SendHtmlEmailAction.Result> results = SendHtmlEmailAction.sendEmail(
            new List<SendHtmlEmailAction.Request>{req}
        );
        Test.stopTest();
        
        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(true, results[0].isSuccess, 'Email should be sent successfully');
    }
    
    @isTest
    static void testSendEmailBulkRequests() {
        // Test multiple email requests in one call
        List<SendHtmlEmailAction.Request> requests = new List<SendHtmlEmailAction.Request>();
        
        for (Integer i = 0; i < 3; i++) {
            SendHtmlEmailAction.Request req = new SendHtmlEmailAction.Request();
            req.htmlBody = '<p>Test email ' + i + '</p>';
            req.subject = 'Test Subject ' + i;
            req.toAddresses = new List<String>{'test' + i + '@example.com'};
            req.orgWideEmailAddress = null;
            requests.add(req);
        }
        
        Test.startTest();
        List<SendHtmlEmailAction.Result> results = SendHtmlEmailAction.sendEmail(requests);
        Test.stopTest();
        
        System.assertEquals(3, results.size(), 'Should return three results');
        for (SendHtmlEmailAction.Result result : results) {
            System.assertEquals(true, result.isSuccess, 
                              'All emails should be sent successfully');
        }
    }
    
    @isTest
    static void testSendEmailWithNullToAddresses() {
        SendHtmlEmailAction.Request req = new SendHtmlEmailAction.Request();
        req.htmlBody = '<p>Test email</p>';
        req.subject = 'Test Subject';
        req.toAddresses = null; // Null list
        req.orgWideEmailAddress = null;
        
        Test.startTest();
        List<SendHtmlEmailAction.Result> results = SendHtmlEmailAction.sendEmail(
            new List<SendHtmlEmailAction.Request>{req}
        );
        Test.stopTest();
        
        // Verify validation error
        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(false, results[0].isSuccess, 'Should fail due to null recipients');
        System.assert(results[0].errorMessage != null, 
                      'Error message should be present');
    }

    @isTest
    static void testSendEmailWithEmptyRequestListReturnsEmptyResults() {
        Test.startTest();
        List<SendHtmlEmailAction.Result> results =
            SendHtmlEmailAction.sendEmail(new List<SendHtmlEmailAction.Request>());
        Test.stopTest();

        System.assertEquals(0, results.size());
    }

    @isTest
    static void testSendEmailMixedBulkRequests() {
        SendHtmlEmailAction.Request validReq = new SendHtmlEmailAction.Request();
        validReq.htmlBody = '<p>Valid email</p>';
        validReq.subject = 'Valid Subject';
        validReq.toAddresses = new List<String>{'valid@test.com'};
        validReq.orgWideEmailAddress = null;

        SendHtmlEmailAction.Request invalidReq = new SendHtmlEmailAction.Request();
        invalidReq.htmlBody = '<p>Invalid email</p>';
        invalidReq.subject = 'Invalid Subject';
        invalidReq.toAddresses = new List<String>();
        invalidReq.orgWideEmailAddress = null;

        Test.startTest();
        List<SendHtmlEmailAction.Result> results =
            SendHtmlEmailAction.sendEmail(new List<SendHtmlEmailAction.Request>{ validReq, invalidReq });
        Test.stopTest();

        System.assertEquals(2, results.size());
        System.assertEquals(true, results[0].isSuccess);
        System.assertEquals(false, results[1].isSuccess);
    }

    @isTest
    static void testSendEmailHandlesNullRequestEntry() {
        Test.startTest();
        List<SendHtmlEmailAction.Result> results =
            SendHtmlEmailAction.sendEmail(new List<SendHtmlEmailAction.Request>{ null });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].isSuccess);
        System.assertNotEquals(null, results[0].errorMessage);
    }

    @isTest
    static void testSendEmailInvalidRecipientCapturesFailure() {
        SendHtmlEmailAction.Request req = new SendHtmlEmailAction.Request();
        req.htmlBody = '<p>Invalid recipient test</p>';
        req.subject = 'Invalid Recipient';
        req.toAddresses = new List<String>{ 'invalid-email-address' };
        req.orgWideEmailAddress = null;

        Test.startTest();
        List<SendHtmlEmailAction.Result> results =
            SendHtmlEmailAction.sendEmail(new List<SendHtmlEmailAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].isSuccess);
        System.assert(results[0].errorMessage != null && results[0].errorMessage.contains('Email failed'));
    }

    @isTest(SeeAllData=true)
    static void testRenderEmailTemplateActionSuccessAndPassThrough() {
        EmailTemplate et = getAnyActiveTemplate();
        Contact c = createTemplateRecipient('RenderRecipient1');

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

    @isTest(SeeAllData=true)
    static void testRenderEmailTemplateActionFallbackToText() {
        EmailTemplate et = getTextOnlyTemplateOrFallback();
        Contact c = createTemplateRecipient('RenderRecipient2');

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

    @isTest(SeeAllData=true)
    static void testRenderEmailTemplateActionExceptionPath() {
        Contact c = createTemplateRecipient('RenderRecipient3');

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

    @isTest(SeeAllData=true)
    static void testFacultyComposerGetTemplatesReturnsRecords() {
        EmailTemplate et = getTemplateWithFolder();

        Test.startTest();
        List<FacultyCommunicationComposerController.TemplateOption> options =
            FacultyCommunicationComposerController.getFacultyEmailTemplates(et.Folder.Name);
        Test.stopTest();

        System.assert(options.size() > 0);
        Boolean found = false;
        for (FacultyCommunicationComposerController.TemplateOption option : options) {
            if (option.templateId == et.Id) {
                found = true;
                break;
            }
        }
        System.assertEquals(true, found, 'Expected queried template to be returned for its folder.');
    }

    @isTest(SeeAllData=true)
    static void testFacultyComposerFolderNotFound() {
        Test.startTest();
        List<FacultyCommunicationComposerController.TemplateOption> options =
            FacultyCommunicationComposerController.getFacultyEmailTemplates('No Such Folder');
        Test.stopTest();

        System.assertEquals(0, options.size());
    }

    @isTest(SeeAllData=true)
    static void testFacultyComposerRenderPreviewSuccessAndFallback() {
        EmailTemplate htmlTemplate = getTemplateWithFolder();
        EmailTemplate textTemplate = getTextOnlyTemplateOrFallback();
        Contact c = createTemplateRecipient('ComposerReceiver');

        Test.startTest();
        FacultyCommunicationComposerController.RenderResult htmlResult =
            FacultyCommunicationComposerController.renderTemplatePreview(
                htmlTemplate.Id,
                c.Id,
                null,
                'TH-2001'
            );

        FacultyCommunicationComposerController.RenderResult textResult =
            FacultyCommunicationComposerController.renderTemplatePreview(
                textTemplate.Id,
                c.Id,
                null,
                'TH-2002'
            );

        FacultyCommunicationComposerController.RenderResult noThreadResult =
            FacultyCommunicationComposerController.renderTemplatePreview(
                htmlTemplate.Id,
                c.Id,
                null,
                null
            );
        Test.stopTest();

        System.assertEquals(htmlTemplate.Name, htmlResult.templateName);
        System.assert(htmlResult.renderedSubject.endsWith('[TH-2001]'));
        System.assertNotEquals(null, htmlResult.renderedHtmlBody);

        System.assertEquals(textTemplate.Name, textResult.templateName);
        System.assert(textResult.renderedSubject.endsWith('[TH-2002]'));
        System.assertNotEquals(null, textResult.renderedHtmlBody);

        System.assertNotEquals(null, noThreadResult.renderedSubject);
        System.assertEquals(false, noThreadResult.renderedSubject.endsWith(']'));
    }

    @isTest(SeeAllData=true)
    static void testFacultyComposerRenderPreviewMissingRequiredInputs() {
        Contact c = createTemplateRecipient('ComposerErrors');
        Boolean threwTemplate = false;
        Boolean threwRecipient = false;

        try {
            FacultyCommunicationComposerController.renderTemplatePreview(null, c.Id, null, 'TH-ERR1');
        } catch (AuraHandledException ex) {
            threwTemplate = true;
        }

        EmailTemplate et = getTemplateWithFolder();

        try {
            FacultyCommunicationComposerController.renderTemplatePreview(et.Id, null, null, 'TH-ERR2');
        } catch (AuraHandledException ex) {
            threwRecipient = true;
        }

        System.assertEquals(true, threwTemplate);
        System.assertEquals(true, threwRecipient);
    }

    @isTest(SeeAllData=true)
    static void testSendEmailUsesOrgWideAddressWhenPresent() {
        List<OrgWideEmailAddress> owea = [
            SELECT Address
            FROM OrgWideEmailAddress
            WHERE Address != null
            LIMIT 1
        ];

        if (owea.isEmpty()) {
            return;
        }

        SendHtmlEmailAction.Request req = new SendHtmlEmailAction.Request();
        req.htmlBody = '<p>Org wide branch coverage</p>';
        req.subject = 'Org Wide Branch';
        req.toAddresses = new List<String>{ 'branch@test.com' };
        req.orgWideEmailAddress = owea[0].Address;

        Test.startTest();
        List<SendHtmlEmailAction.Result> results =
            SendHtmlEmailAction.sendEmail(new List<SendHtmlEmailAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].isSuccess, 'Expected email send path to remain successful with org-wide address.');
    }
}