public with sharing class AAUserCreationAction {
	
     @InvocableMethod(label='Send Welcome Email with Reset Password Link')
     public static void sendWelcomeEmail(List<Id> userIds) {
        sendWelcomeEmailFuture(userIds);
        System.debug('Welcome Email future initiated');
     }
     @future(callout=false)
    public static void sendWelcomeEmailFuture(List<Id> userIds) {
        System.debug('in ');
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Id userId : userIds) {
            try {
                User u = [SELECT Id, FirstName, LastName, Email FROM User WHERE Id = :userId LIMIT 1];
                System.debug('u '+u);
  Id orgWideEmailId = [
                SELECT Id
                FROM OrgWideEmailAddress
                WHERE DisplayName = 'ISB Support'
                LIMIT 1
            ].Id;
             System.debug('orgWideEmailId '+orgWideEmailId);   
                // 1️⃣ Trigger Salesforce to send its own secure reset password email
                System.resetPassword(u.Id, true);

                // 2️⃣ (Optional) Send your own Welcome Email
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setToAddresses(new List<String>{u.Email});
                mail.setSubject('Welcome to the Academic Associate Portal');
                mail.setOrgWideEmailAddressId(orgWideEmailId);
                mail.setPlainTextBody(
                    'Hello ' + (u.FirstName != null ? u.FirstName : '') + ',\n\n' +
                    'Welcome to the Academic Associate Portal!\n\n' +
                    'A secure email has been sent separately with instructions to set your Salesforce password.\n' +
                    'Please follow that email to activate your account.\n\n' +
                    'Regards,\nAcademic Support Team'
                );

                emails.add(mail);
            System.debug('emails'+ emails);

            } catch (Exception e) {
                System.debug('Error sending welcome email: ' + e.getMessage());
            }
        }

        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails, false);
            System.debug('Email Sent successfully');
        }
    }
}