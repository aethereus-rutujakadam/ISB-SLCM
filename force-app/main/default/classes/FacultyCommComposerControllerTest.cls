@isTest(SeeAllData=true)
private class FacultyCommComposerControllerTest {

    private static EmailTemplate getAnyTemplateWithFolder() {
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
              AND Folder.Name != null
            ORDER BY LastModifiedDate DESC
            LIMIT 200
        ];
        for (EmailTemplate templateRow : templates) {
            if (String.isBlank(templateRow.HtmlValue) && !String.isBlank(templateRow.Body)) {
                return templateRow;
            }
        }
        return getAnyTemplateWithFolder();
    }

    private static Contact createRecipient() {
        Account acc = new Account(Name = 'FCC Recipient Account');
        insert acc;

        Contact c = new Contact(
            FirstName = 'Faculty',
            LastName = 'Receiver',
            AccountId = acc.Id,
            Email = 'faculty.receiver@test.com'
        );
        insert c;
        return c;
    }

    @isTest
    static void testGetFacultyEmailTemplatesReturnsRecords() {
        EmailTemplate et = getAnyTemplateWithFolder();

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

    @isTest
    static void testGetFacultyEmailTemplatesFolderNotFound() {
        Test.startTest();
        List<FacultyCommunicationComposerController.TemplateOption> options =
            FacultyCommunicationComposerController.getFacultyEmailTemplates('No Such Folder');
        Test.stopTest();

        System.assertEquals(0, options.size());
    }

    @isTest
    static void testRenderTemplatePreviewSuccessAndFallback() {
        EmailTemplate htmlTemplate = getAnyTemplateWithFolder();
        EmailTemplate textTemplate = getTextOnlyTemplateOrFallback();
        Contact c = createRecipient();

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

    @isTest
    static void testRenderTemplatePreviewThrowsWhenRequiredInputsMissing() {
        Contact c = createRecipient();
        Boolean threwTemplate = false;
        Boolean threwRecipient = false;

        try {
            FacultyCommunicationComposerController.renderTemplatePreview(null, c.Id, null, 'TH-ERR1');
        } catch (AuraHandledException ex) {
            threwTemplate = true;
        }

        EmailTemplate et = getAnyTemplateWithFolder();

        try {
            FacultyCommunicationComposerController.renderTemplatePreview(et.Id, null, null, 'TH-ERR2');
        } catch (AuraHandledException ex) {
            threwRecipient = true;
        }

        System.assertEquals(true, threwTemplate);
        System.assertEquals(true, threwRecipient);
    }
}