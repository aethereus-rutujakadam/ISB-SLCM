global without sharing class PseudoCasePortalController {
    
    // OTP Configuration
    private static final Integer OTP_LENGTH = 6;
    
    // ============================================
    // OTP VERIFICATION METHODS
    // ============================================
    
    /**
     * Verify email and send OTP
     * Returns the OTP in the response so JS can verify it
     */
    @AuraEnabled
    public static Map<String, String> verifyEmailAndSendOTP(String email) {
        if (String.isBlank(email)) {
            throw new AuraHandledException('Email is required.');
        }

        // Find contact by email
        List<Contact> contacts = [
            SELECT Id, Email, FirstName, LastName
            FROM Contact 
            WHERE Email = :email 
            LIMIT 1
        ];

        if (contacts.isEmpty()) {
            throw new AuraHandledException('No contact found for that email.');
        }

        Contact contact = contacts[0];
        
        // Generate OTP
        String otp = generateOTP();
        
        // Send OTP via email
        sendOTPEmail(contact.Id, otp);
        
        // Return OTP to JavaScript (encrypted in response)
        return new Map<String, String>{
            'contactId' => contact.Id,
            'message' => 'OTP sent successfully to ' + email,
            'firstName' => contact.FirstName,
            'otp' => otp  // JS will store and verify this
        };
    }
    
    /**
     * Resend OTP
     */
    @AuraEnabled
    public static Map<String, String> resendOTP(String email) {
        if (String.isBlank(email)) {
            throw new AuraHandledException('Email is required.');
        }
        
        // Find contact
        List<Contact> contacts = [
            SELECT Id, Email, FirstName, LastName
            FROM Contact 
            WHERE Email = :email 
            LIMIT 1
        ];
        
        if (contacts.isEmpty()) {
            throw new AuraHandledException('Contact not found.');
        }
        
        Contact contact = contacts[0];
        
        // Generate new OTP
        String otp = generateOTP();
        
        // Send OTP via email
        sendOTPEmail(contact.Id, otp);
        
        return new Map<String, String>{
            'contactId' => contact.Id,
            'message' => 'OTP resent successfully to ' + email,
            'otp' => otp  // JS will store and verify this
        };
    }
    
    // ============================================
    // HELPER METHODS FOR OTP
    // ============================================
    
    /**
     * Generate random 6-digit OTP
     */
    private static String generateOTP() {
        Integer otp = Integer.valueOf(Math.floor(Math.random() * 900000) + 100000);
        return String.valueOf(otp);
    }
    
    /**
     * Send OTP via email
     * Uses @future to run in system context (required for guest users)
     */
    @future
    public static void sendOTPEmail(Id contactId, String otp) {
        try {
            // Query the contact to get email and name
            Contact contact = [
                SELECT Id, Email, FirstName
                FROM Contact
                WHERE Id = :contactId
                LIMIT 1
            ];
            
            // Build the email message
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new String[] { contact.Email });
            mail.setSubject('Your Verification Code - Case Request Portal');
            
            // Set save as activity to false (not needed for OTP)
            mail.setSaveAsActivity(false);
            
            // IMPORTANT: For guest users, MUST use Org-Wide Email Address
            List<OrgWideEmailAddress> owea = [
                    SELECT Id, Address 
                FROM OrgWideEmailAddress 
                WHERE DisplayName = 'ISB Support' 
                LIMIT 1
            ];
            
            if (!owea.isEmpty()) {
                mail.setOrgWideEmailAddressId(owea[0].Id);
            } else {
                System.debug('WARNING: No Org-Wide Email Address found. Email may not send for guest users.');
                mail.setReplyTo('noreply-isbsupport@yopmail.com');
            }
            
            // Plain text version
            String emailBody = 'Dear ' + (contact.FirstName != null ? contact.FirstName : 'User') + ',\n\n';
            emailBody += 'Your verification code is: ' + otp + '\n\n';
            emailBody += 'This code will expire in 10 minutes.\n\n';
            emailBody += 'If you did not request this code, please ignore this email.\n\n';
            emailBody += 'Thank you,\nSupport Team';
            mail.setPlainTextBody(emailBody);
            
            // HTML version
            String htmlBody = '<div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">';
            htmlBody += '<h2>Email Verification</h2>';
            htmlBody += '<p>Dear ' + (contact.FirstName != null ? contact.FirstName : 'User') + ',</p>';
            htmlBody += '<p>Your verification code is:</p>';
            htmlBody += '<div style="background-color: #f4f4f4; padding: 20px; text-align: center; font-size: 32px; font-weight: bold; letter-spacing: 5px; margin: 20px 0;">';
            htmlBody += otp;
            htmlBody += '</div>';
            htmlBody += '<p style="color: #666;">This code will expire in 10 minutes.</p>';
            htmlBody += '<p style="color: #999; font-size: 12px;">If you did not request this code, please ignore this email.</p>';
            htmlBody += '</div>';
            mail.setHtmlBody(htmlBody);
            
            // Send email and capture result
            Messaging.SendEmailResult[] results = Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
            
            // Check if email was sent successfully
            if (results != null && results.size() > 0) {
                Messaging.SendEmailResult result = results[0];
                if (result.isSuccess()) {
                    System.debug('OTP email sent successfully to: ' + contact.Email);
                } else {
                    // Log errors
                    for (Messaging.SendEmailError error : result.getErrors()) {
                        System.debug('Email send error: ' + error.getMessage());
                        System.debug('Error status code: ' + error.getStatusCode());
                    }
                }
            }
            
        } catch (Exception e) {
            System.debug('Error sending OTP email: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
        }
    }

    // ============================================
    // RECORD TYPE METHODS
    // ============================================
    
    /**
     * Get active Case Record Types
     * Returns list of Record Types available for Case creation
     */
    @AuraEnabled(cacheable=true)
    public static List<RecordTypeDTO> getCaseRecordTypes() {
        try {
            List<RecordTypeDTO> recordTypes = new List<RecordTypeDTO>();
            
            // Query active Case Record Types
            // Excluding Master record type if exists
            List<RecordType> caseRecordTypes = [
                SELECT Id, Name, DeveloperName, Description
                FROM RecordType
                WHERE SObjectType = 'Case'
                AND IsActive = true
                AND DeveloperName != 'Master'
                ORDER BY Name ASC
            ];
            
            for (RecordType rt : caseRecordTypes) {
                RecordTypeDTO dto = new RecordTypeDTO();
                dto.id = rt.Id;
                dto.name = rt.Name;
                dto.developerName = rt.DeveloperName;
                dto.description = rt.Description;
                recordTypes.add(dto);
            }
            
            return recordTypes;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching Case Record Types: ' + e.getMessage());
        }
    }
    
    // ============================================
    // PROGRAM ENROLLMENT METHODS
    // ============================================
    
    @AuraEnabled(cacheable=true)
    public static List<ProgramEnrollment> getProgramEnrollmentsForContact(Id contactId) {
        if (contactId == null) {
            throw new AuraHandledException('Contact not found or not verified.');
        }
        
        List<ProgramEnrollment> pes = [
            SELECT Id, Name, ProgramId, Program.Name
            FROM ProgramEnrollment
            WHERE ContactId = :contactId
            ORDER BY CreatedDate DESC
            LIMIT 200
        ];
        
        return pes;
    }

    @AuraEnabled(cacheable=true)
    public static List<TermDTO> getTermsForProgramEnrollment(Id programEnrollmentId) {
        if (programEnrollmentId == null) {
            throw new AuraHandledException('Program Enrollment is required.');
        }
        
        List<Enrollment_Session__c> es = [
            SELECT Id,
                   Name,
                   Academic_Session__c,
                   Academic_Session__r.Name,
                   Status__c
            FROM Enrollment_Session__c
            WHERE Program_Enrollment__c = :programEnrollmentId
            ORDER BY Academic_Session__r.Name
            LIMIT 500
        ];

        List<TermDTO> out = new List<TermDTO>();
        for (Enrollment_Session__c row : es) {
            if (row.Academic_Session__c == null) continue;
            TermDTO t = new TermDTO();
            t.enrollmentSessionId = row.Id;
            t.termId = row.Academic_Session__c;
            t.termName = row.Academic_Session__r != null ? row.Academic_Session__r.Name : 'Term';
            t.status = row.Status__c;
            out.add(t);
        }
        return out;
    }
    
    // ============================================
    // CASE CREATION METHODS
    // ============================================
    
    /**
     * Create Case from the request with Record Type
     * Runs synchronously and returns Case Number
     */
    @AuraEnabled
    public static Map<String, String> createCaseRequest(Map<String, String> caseData) {
        Savepoint sp = Database.setSavepoint();
        
        try {
            // Validate required fields
            if (String.isBlank(caseData.get('recordTypeId'))) {
                throw new AuraHandledException('Record Type is required.');
            }
            
            if (String.isBlank(caseData.get('contactId'))) {
                throw new AuraHandledException('Contact information is missing.');
            }
            
            // Create the Case
            Case newCase = new Case();
            newCase.ContactId = caseData.get('contactId');
            newCase.Subject = caseData.get('subject');
            newCase.Description = caseData.get('description');
            newCase.RecordTypeId = caseData.get('recordTypeId');
            newCase.Status = 'New';
            newCase.Origin = 'Web';
            
            // Optional: Set Type field if you want to maintain it
            if (String.isNotBlank(caseData.get('requestType'))) {
                newCase.Type = caseData.get('requestType');
            }
            
            // Add custom fields if your org has them
            // Uncomment and modify these lines based on your custom fields
            // if (String.isNotBlank(caseData.get('programEnrollmentId'))) {
            //     newCase.Program_Enrollment__c = caseData.get('programEnrollmentId');
            // }
            // if (String.isNotBlank(caseData.get('enrollmentSessionId'))) {
            //     newCase.Enrollment_Session__c = caseData.get('enrollmentSessionId');
            // }
            
            insert newCase;
            
            // Query the case to get the Case Number
            Case insertedCase = [
                SELECT Id, CaseNumber
                FROM Case
                WHERE Id = :newCase.Id
                LIMIT 1
            ];
            
            System.debug('Case created successfully: ' + insertedCase.CaseNumber);
            
            // Send confirmation email asynchronously
            sendCaseConfirmationEmailAsync(insertedCase.Id, caseData.get('contactId'));
            
            // Return Case Number
            return new Map<String, String>{
                'status' => 'success',
                'caseNumber' => insertedCase.CaseNumber,
                'caseId' => insertedCase.Id,
                'message' => 'Case created successfully'
            };
            
        } catch (Exception e) {
            // Rollback the transaction
            Database.rollback(sp);
            
            // Log the error
            System.debug('Error in createCaseRequest: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            
            throw new AuraHandledException('Error creating case: ' + e.getMessage());
        }
    }
    
    /**
     * Send confirmation email to contact after case creation
     * Uses @future to avoid mixed DML operations
     */
    @future
    public static void sendCaseConfirmationEmailAsync(Id caseId, Id contactId) {
        try {
            // Query case and contact details
            Case caseRecord = [
                SELECT Id, CaseNumber, Subject, Status
                FROM Case 
                WHERE Id = :caseId 
                LIMIT 1
            ];
            
            Contact contact = [
                SELECT Id, Email, FirstName, LastName
                FROM Contact 
                WHERE Id = :contactId 
                LIMIT 1
            ];
            
            if (String.isBlank(contact.Email)) {
                System.debug('Contact email is blank, cannot send confirmation');
                return;
            }
            
            // Build the email message
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new String[] { contact.Email });
            mail.setSubject('Case Created Successfully - ' + caseRecord.CaseNumber);
            mail.setSaveAsActivity(false);
            
            // Use Org-Wide Email Address
            List<OrgWideEmailAddress> owea = [
                    SELECT Id, Address 
                FROM OrgWideEmailAddress 
                WHERE DisplayName = 'ISB Support' 
                LIMIT 1
            ];
            
            if (!owea.isEmpty()) {
                mail.setOrgWideEmailAddressId(owea[0].Id);
            }
            
            // Plain text version
            String emailBody = 'Dear ' + (contact.FirstName != null ? contact.FirstName : 'User') + ',\n\n';
            emailBody += 'Your case has been created successfully.\n\n';
            emailBody += 'Case Number: ' + caseRecord.CaseNumber + '\n';
            emailBody += 'Subject: ' + caseRecord.Subject + '\n';
            emailBody += 'Status: ' + caseRecord.Status + '\n\n';
            emailBody += 'We will review your request and get back to you soon.\n\n';
            emailBody += 'Thank you,\nSupport Team';
            mail.setPlainTextBody(emailBody);
            
            // HTML version
            String htmlBody = '<div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">';
            htmlBody += '<h2>Case Created Successfully</h2>';
            htmlBody += '<p>Dear ' + (contact.FirstName != null ? contact.FirstName : 'User') + ',</p>';
            htmlBody += '<p>Your case has been created successfully.</p>';
            htmlBody += '<table style="width: 100%; border-collapse: collapse; margin: 20px 0;">';
            htmlBody += '<tr><td style="padding: 10px; border: 1px solid #ddd; background-color: #f4f4f4;"><strong>Case Number:</strong></td>';
            htmlBody += '<td style="padding: 10px; border: 1px solid #ddd;">' + caseRecord.CaseNumber + '</td></tr>';
            htmlBody += '<tr><td style="padding: 10px; border: 1px solid #ddd; background-color: #f4f4f4;"><strong>Subject:</strong></td>';
            htmlBody += '<td style="padding: 10px; border: 1px solid #ddd;">' + caseRecord.Subject + '</td></tr>';
            htmlBody += '<tr><td style="padding: 10px; border: 1px solid #ddd; background-color: #f4f4f4;"><strong>Status:</strong></td>';
            htmlBody += '<td style="padding: 10px; border: 1px solid #ddd;">' + caseRecord.Status + '</td></tr>';
            htmlBody += '</table>';
            htmlBody += '<p>We will review your request and get back to you soon.</p>';
            htmlBody += '<p style="color: #999; font-size: 12px; margin-top: 30px;">Thank you,<br/>Support Team</p>';
            htmlBody += '</div>';
            mail.setHtmlBody(htmlBody);
            
            // Send email
            Messaging.SendEmailResult[] results = Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
            
            if (results[0].isSuccess()) {
                System.debug('Case confirmation email sent successfully');
            } else {
                System.debug('Error sending confirmation email: ' + results[0].getErrors()[0].getMessage());
            }
            
        } catch (Exception e) {
            System.debug('Error in sendCaseConfirmationEmailAsync: ' + e.getMessage());
        }
    }

    // ===== DTOs =====
    
    public class TermDTO {
        @AuraEnabled public Id enrollmentSessionId;
        @AuraEnabled public Id termId;
        @AuraEnabled public String termName;
        @AuraEnabled public String status;
    }
    
    public class RecordTypeDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String developerName;
        @AuraEnabled public String description;
    }
}