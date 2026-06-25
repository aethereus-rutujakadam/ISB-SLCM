public with sharing class AdvisorUserCreationAction {
	
     @InvocableMethod(label='Send Advisor Welcome Email with Reset Password Link')
     public static void sendWelcomeEmail(List<Id> userIds) {
        sendWelcomeEmailFuture(userIds);
        System.debug('Advisor Welcome Email future initiated');
     }

     @future(callout=false)
    public static void sendWelcomeEmailFuture(List<Id> userIds) {
        System.debug('Advisor Welcome Email processing started');
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Id userId : userIds) {
            try {
                User u = [SELECT Id, FirstName, LastName, Email FROM User WHERE Id = :userId LIMIT 1];
                System.debug('Processing welcome email for User: ' + u);

                Id orgWideEmailId = [
                    SELECT Id
                    FROM OrgWideEmailAddress
                    WHERE DisplayName = 'ISB Support'
                    LIMIT 1
                ].Id;
                System.debug('Using OrgWideEmailAddress ID: ' + orgWideEmailId);   
                
                // Trigger Salesforce to send its own secure reset password email
                System.resetPassword(u.Id, true);

                // Send Welcome Email
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setToAddresses(new List<String>{u.Email});
                mail.setSubject('Welcome to the Advisor Portal');
                mail.setOrgWideEmailAddressId(orgWideEmailId);
                mail.setPlainTextBody(
                    'Hello ' + (u.FirstName != null ? u.FirstName : '') + ',\n\n' +
                    'Welcome to the Advisor Portal!\n\n' +
                    'A secure email has been sent separately with instructions to set your Salesforce password.\n' +
                    'Please follow that email to activate your account.\n\n' +
                    'Regards,\nISB Support Team'
                );

                emails.add(mail);
                System.debug('Welcome email prepared for: ' + u.Email);

            } catch (Exception e) {
                System.debug('Error sending welcome email for User ' + userId + ': ' + e.getMessage());
            }
        }

        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails, false);
            System.debug('Advisor Welcome Emails sent successfully. Count: ' + emails.size());
        }
    }
}