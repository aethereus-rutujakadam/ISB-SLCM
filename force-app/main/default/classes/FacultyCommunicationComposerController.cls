public with sharing class FacultyCommunicationComposerController {

    public class TemplateOption {
        @AuraEnabled public Id templateId;
        @AuraEnabled public String templateName;
        @AuraEnabled public String subject;
    }

    public class RenderResult {
        @AuraEnabled public String renderedSubject;
        @AuraEnabled public String renderedHtmlBody;
        @AuraEnabled public String templateName;
    }

    @AuraEnabled(cacheable=true)
    public static List<TemplateOption> getFacultyEmailTemplates(String folderName) {
        List<TemplateOption> results = new List<TemplateOption>();
        if (String.isBlank(folderName)) {
            folderName = 'Faculty Communications';
        }

        List<Folder> folders = [
            SELECT Id
            FROM Folder
            WHERE Name = :folderName
            LIMIT 1
        ];
        if (folders.isEmpty()) {
            return results;
        }

        for (EmailTemplate et : [
            SELECT Id, Name, Subject
            FROM EmailTemplate
            WHERE FolderId = :folders[0].Id
            ORDER BY Name
        ]) {
            TemplateOption opt = new TemplateOption();
            opt.templateId = et.Id;
            opt.templateName = et.Name;
            opt.subject = et.Subject;
            results.add(opt);
        }

        return results;
    }

    @AuraEnabled
    public static RenderResult renderTemplatePreview(
        Id templateId,
        Id recipientId,
        Id relatedRecordId,
        String threadName
    ) {
        if (templateId == null || recipientId == null) {
            throw new AuraHandledException('Template and recipient are required.');
        }

        RenderResult result = new RenderResult();

        EmailTemplate selectedTemplate = [
            SELECT Name
            FROM EmailTemplate
            WHERE Id = :templateId
            LIMIT 1
        ];
        result.templateName = selectedTemplate.Name;

        Messaging.SingleEmailMessage rendered = Messaging.renderStoredEmailTemplate(
            templateId,
            recipientId,
            relatedRecordId
        );

        String subject = rendered.getSubject();
        if (String.isBlank(subject)) {
            subject = '';
        }
        if (!String.isBlank(threadName)) {
            subject += ' [' + threadName + ']';
        }

        result.renderedSubject = subject;
        result.renderedHtmlBody = rendered.getHtmlBody();
        if (String.isBlank(result.renderedHtmlBody)) {
            result.renderedHtmlBody = rendered.getPlainTextBody();
        }

        return result;
    }
}