public with sharing class SendHtmlEmailAction {
    
    public class Request {
        @InvocableVariable(required=true label='HTML Body')
        public String htmlBody;
        
        @InvocableVariable(required=true label='Subject')
        public String subject;
        
        @InvocableVariable(required=true label='To Addresses (List)')
        public List<String> toAddresses;
        
        @InvocableVariable(required=false label='Org Wide Email Address')
        public String orgWideEmailAddress;
    }
    
    public class Result {
        @InvocableVariable(label='Is Success')
        public Boolean isSuccess;
        
        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }
    
    @InvocableMethod(label='Send HTML Email' description='Sends an HTML email using Messaging.SingleEmailMessage preserving HTML formatting.')
    public static List<Result> sendEmail(List<Request> requests) {
        List<Result> results = new List<Result>();
        
        for (Request req : requests) {
            Result res = new Result();
            try {
                // Validate input
                if (req.toAddresses == null || req.toAddresses.isEmpty()) {
                    res.isSuccess = false;
                    res.errorMessage = 'No recipient email addresses provided';
                    results.add(res);
                    continue;
                }
                
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setToAddresses(req.toAddresses);
                mail.setSubject(req.subject);
                mail.setHtmlBody(req.htmlBody);
                mail.setSaveAsActivity(false); // Don't create activities
                
                // Set org wide email address if provided
                if (String.isNotBlank(req.orgWideEmailAddress)) {
                    List<OrgWideEmailAddress> oweaList = [
                        SELECT Id, Address FROM OrgWideEmailAddress 
                        WHERE Address = :req.orgWideEmailAddress 
                        LIMIT 1
                    ];
                    if (!oweaList.isEmpty()) {
                        mail.setOrgWideEmailAddressId(oweaList[0].Id);
                        System.debug('Using Org-Wide Email Address: ' + oweaList[0].Address);
                    } else {
                        System.debug('WARNING: Org-Wide Email Address not found: ' + req.orgWideEmailAddress);
                    }
                }
                
                // Send email and capture results
                Messaging.SendEmailResult[] sendResults = Messaging.sendEmail(
                    new List<Messaging.SingleEmailMessage>{ mail }
                );
                
                // Check if email was sent successfully
                if (sendResults != null && !sendResults.isEmpty()) {
                    Messaging.SendEmailResult result = sendResults[0];
                    
                    if (result.isSuccess()) {
                        res.isSuccess = true;
                        res.errorMessage = null;
                        System.debug('Email sent successfully to: ' + String.join(req.toAddresses, '; '));
                    } else {
                        res.isSuccess = false;
                        List<String> errors = new List<String>();
                        for (Messaging.SendEmailError error : result.getErrors()) {
                            errors.add(error.getMessage());
                            System.debug('Email send error: ' + error.getMessage() + ' (Status Code: ' + error.getStatusCode() + ')');
                        }
                        res.errorMessage = 'Email failed: ' + String.join(errors, '; ');
                    }
                } else {
                    res.isSuccess = false;
                    res.errorMessage = 'No result returned from sendEmail call';
                }
                
            } catch (Exception e) {
                res.isSuccess = false;
                res.errorMessage = e.getMessage();
                System.debug('SendHtmlEmailAction Exception: ' + e.getMessage());
                System.debug('Stack Trace: ' + e.getStackTraceString());
            }
            results.add(res);
        }
        return results;
    }
}