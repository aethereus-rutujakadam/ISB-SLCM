public without sharing class ISB_ReceiptGenerator {
    
    /**
     * @description Generate receipt PDF, attach to payment, and send email asynchronously
     * @param paymentId The ID of the payment record
     * @param paymentName The name of the payment record
     */
    @future(callout=true)
    public static void generateAndAttachReceiptAsync(Id paymentId, String paymentName) {
        System.debug('=== START generateAndAttachReceiptAsync ===');
        System.debug('Payment Id: ' + paymentId);
        System.debug('Payment Name: ' + paymentName);
        
        try {
            // Generate receipt and get the ContentVersion Id
            Id contentVersionId = generateReceipt(paymentId, paymentName);
            System.debug('✅ Receipt generated successfully, ContentVersion Id: ' + contentVersionId);
            
            // Send email with receipt attachment
            sendPaymentSuccessEmail(paymentId, contentVersionId);
            System.debug('✅ Email sent successfully');
            
        } catch (Exception e) {
            System.debug('❌ Error in future method: ' + e.getMessage());
            System.debug('Stack Trace: ' + e.getStackTraceString());
        }
        
        System.debug('=== END generateAndAttachReceiptAsync ===');
    }
    
    /**
     * @description Core logic to generate receipt PDF and attach to payment
     * @param paymentId The ID of the payment record
     * @param paymentName The name of the payment record
     * @return Id of the created ContentVersion
     */
    private static Id generateReceipt(Id paymentId, String paymentName) {
        System.debug('Starting PDF generation for Payment: ' + paymentId);
        
        // 1. Reference the Visualforce Page
        PageReference pdfPage = Page.ISBPaymentReceipt; 
        pdfPage.getParameters().put('id', paymentId);
        
        // 2. Generate the PDF Blob (Handle Test Context)
        Blob pdfBlob;
        if (Test.isRunningTest()) { 
            pdfBlob = Blob.valueOf('Unit Test Attachment Body');
        } else {
            pdfBlob = pdfPage.getContentAsPDF();
        }
        
        System.debug('PDF Blob generated, size: ' + pdfBlob.size());

        // 3. Create ContentVersion (The File)
        ContentVersion cv = new ContentVersion();
        cv.Title = 'Receipt_' + paymentName + '.pdf';
        cv.PathOnClient = 'Receipt_' + paymentName + '.pdf';
        cv.VersionData = pdfBlob;
        cv.IsMajorVersion = true;
        insert cv;
        
        System.debug('ContentVersion created: ' + cv.Id);

        // 4. Get the ContentDocumentId
        Id conDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        
        System.debug('ContentDocument Id: ' + conDocId);

        // 5. Link the File to the Payment Record
        ContentDocumentLink cdl = new ContentDocumentLink();
        cdl.LinkedEntityId = paymentId; 
        cdl.ContentDocumentId = conDocId;
        cdl.ShareType = 'V'; // Viewer permission
        cdl.Visibility = 'AllUsers'; // Visible to Community Users
        insert cdl;
        
        System.debug('ContentDocumentLink created, file attached to Payment');
        
        return cv.Id;
    }
    
    /**
     * @description Send payment success email with receipt attachment
     * @param paymentId The ID of the payment record
     * @param contentVersionId The ID of the receipt ContentVersion
     */
    private static void sendPaymentSuccessEmail(Id paymentId, Id contentVersionId) {
        System.debug('=== START sendPaymentSuccessEmail ===');
        
        try {
            // Query payment details with Customer info
            ISB_Payment__c payment = [
                SELECT Id, Name, Customer__c, Customer__r.Email, Customer__r.Name
                FROM ISB_Payment__c
                WHERE Id = :paymentId
                LIMIT 1
            ];
            
            System.debug('Payment retrieved: ' + payment.Name);
            System.debug('Customer: ' + payment.Customer__r.Name);
            System.debug('Customer Email: ' + payment.Customer__r.Email);
            
            if (payment.Customer__c == null) {
                System.debug('❌ No customer linked to payment. Cannot send email.');
                return;
            }
            
            if (String.isBlank(payment.Customer__r.Email)) {
                System.debug('❌ Customer has no email address. Cannot send email.');
                return;
            }
            
            OrgWideEmailAddress orgWideEmail;
            try {
                orgWideEmail = [
                    SELECT Id, Address, DisplayName
                    FROM OrgWideEmailAddress
                    WHERE DisplayName = 'ISB Finance'
                    LIMIT 1
                ];
                System.debug('Org-Wide Email Address found: ' + orgWideEmail.DisplayName + ' (' + orgWideEmail.Address + ')');
            } catch (Exception e) {
                System.debug('⚠️ Org-Wide Email Address "ISB Finance" not found. Email will be sent from default address.');
            }
            
            // Get the Email Template
            EmailTemplate template = [
                SELECT Id, Name, Subject, Body, HtmlValue
                FROM EmailTemplate
                WHERE DeveloperName = 'Payment_Success_Template'
                LIMIT 1
            ];
            
            System.debug('Email Template found: ' + template.Name);
            
            // Query ContentVersion to get the PDF as an attachment
            ContentVersion cv = [
                SELECT Id, Title, VersionData, FileExtension
                FROM ContentVersion
                WHERE Id = :contentVersionId
                LIMIT 1
            ];
            
            System.debug('ContentVersion retrieved for attachment: ' + cv.Title);
            
            // Create Email Attachment
            Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
            attachment.setFileName(cv.Title);
            attachment.setBody(cv.VersionData);
            
            // Create Single Email Message
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setTemplateId(template.Id);
            email.setTargetObjectId(payment.Customer__c); // Contact Id
            email.setWhatId(payment.Id); // Payment record for merge fields
            email.setSaveAsActivity(true);
            email.setFileAttachments(new Messaging.EmailFileAttachment[] { attachment });
            if (orgWideEmail != null) {
                email.setOrgWideEmailAddressId(orgWideEmail.Id);
                System.debug('Using Org-Wide Email: ' + orgWideEmail.DisplayName);
            }
            
            // Send Email
            Messaging.SendEmailResult[] results = Messaging.sendEmail(new Messaging.SingleEmailMessage[] { email });
            
            // Check results
            if (results[0].isSuccess()) {
                System.debug('✅ Email sent successfully to: ' + payment.Customer__r.Email);
            } else {
                System.debug('❌ Email send failed: ' + results[0].getErrors()[0].getMessage());
            }
            
        } catch (Exception e) {
            System.debug('❌ Error sending email: ' + e.getMessage());
            System.debug('Stack Trace: ' + e.getStackTraceString());
            // Don't throw - we don't want to fail the entire transaction
        }
        
        System.debug('=== END sendPaymentSuccessEmail ===');
    }
}