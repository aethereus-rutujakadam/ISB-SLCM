public with sharing class RenderEmailTemplateAction {
    public class Request {
        @InvocableVariable(required=true label='Recipient ID (WhoId, e.g. Contact Id)')
        public Id recipientId;
        
        @InvocableVariable(required=true label='Template ID')
        public Id templateId;
        
        @InvocableVariable(required=false label='Related Record ID (WhatId, e.g. Course Offering Id)')
        public Id relatedRecordId;
        
        @InvocableVariable(required=true label='Thread Name (e.g. TH-00012) to append')
        public String threadName;
        
        @InvocableVariable(required=false label='Additional Recipient Emails (for CC/BCC purposes)')
        public List<String> additionalRecipientEmails;
    }
    
    public class Result {
        @InvocableVariable(label='Resolved Subject with Thread Tag')
        public String finalSubject;
        
        @InvocableVariable(label='Resolved HTML Body')
        public String htmlBody;
        
        @InvocableVariable(label='Resolved Plain Text Body')
        public String textBody;
        
        @InvocableVariable(label='Additional Recipient Emails')
        public List<String> additionalRecipientEmails;
    }
    
    @InvocableMethod(label='Render Email Template & Append Thread ID' description='Parses an email template, resolves merge fields, and appends [TH-XXXX] to the subject.')
    public static List<Result> renderTemplate(List<Request> requests) {
        List<Result> results = new List<Result>();
        
        for(Request req : requests) {
            Result res = new Result();
            try {
                // Render the template using standard Apex method
                Messaging.SingleEmailMessage msg = Messaging.renderStoredEmailTemplate(req.templateId, req.recipientId, req.relatedRecordId);
                
                // Append Thread ID to the resolved subject
                res.finalSubject = msg.getSubject() + ' [' + req.threadName + ']';
                res.htmlBody = msg.getHtmlBody();
                res.textBody = msg.getPlainTextBody();
                
                // Fallback to text if HTML is empty
                if(String.isBlank(res.htmlBody)) {
                    res.htmlBody = res.textBody;
                }
                
                // Pass through additional recipient emails
                if (req.additionalRecipientEmails != null) {
                    res.additionalRecipientEmails = new List<String>(req.additionalRecipientEmails);
                }
            } catch(Exception e) {
                System.debug('Error rendering template: ' + e.getMessage());
            }
            results.add(res);
        }
        return results;
    }
}