//Sid: Changed to without sharing to allow Guest User to query the OTP record they just created
public without sharing class GuestOtpAuthService {

    private static final Integer OTP_EXPIRY_MIN = 10;
    private static final Integer MAX_ATTEMPTS = 3;

    // STEP 1: SEND OTP
    @AuraEnabled
    public static String sendOtp(String email) {
        System.debug('🔵 sendOtp invoked');
        System.debug('Current User ID: ' + UserInfo.getUserId());
        System.debug('Current User Name: ' + UserInfo.getUserName());
        System.debug('Current User Type: ' + UserInfo.getUserType());
        System.debug('📧 Input email = ' + email);
        
        if (String.isBlank(email)) {
            return 'Email is required';
        }

        // Domain validation - only allow isb.edu or yopmail.com
        String emailDomain = email.toLowerCase().substringAfter('@');
        if (emailDomain != 'isb.edu' && emailDomain != 'yopmail.com') {
            return 'Only isb.edu email domains are allowed.';
        }

        try {
            // Check if contact exists using New_Admit_Email__c field
            List<Contact> existingContacts = [SELECT Id FROM Contact WHERE New_Admit_Email__c = :email LIMIT 1];
            if (existingContacts.isEmpty()) {
                return 'No user found with this email address.';
            }

            String otp = String.valueOf(Math.mod(Math.abs(Crypto.getRandomInteger()), 900000) + 100000);

            // Check if an active session already exists for this email
            List<Guest_OTP_Session__c> existingSessions = [
                SELECT Id, OTP__c, Expires_At__c, Attempts__c, Verified__c, LastModifiedDate
                FROM Guest_OTP_Session__c
                WHERE Email__c = :email.toLowerCase()
                AND Verified__c = false
                ORDER BY LastModifiedDate DESC
                LIMIT 1
            ];

            Guest_OTP_Session__c session;
            
            if (!existingSessions.isEmpty()) {
                // Reuse existing session
                session = existingSessions[0];
                Decimal currentAttempts = session.Attempts__c != null ? session.Attempts__c : 0;
                System.debug('✅ FOUND EXISTING SESSION');
                System.debug('   ID: ' + session.Id);
                System.debug('   Attempts: ' + currentAttempts);
                
                // Check if max attempts exceeded - enforce cooldown BLOCK
                if (currentAttempts >= MAX_ATTEMPTS) {
                    DateTime lastModified = session.LastModifiedDate;
                    DateTime cooldownEnd = lastModified.addMinutes(15);
                    Integer minutesRemaining = (Integer)((cooldownEnd.getTime() - System.now().getTime()) / 60000);
                    
                    System.debug('⏱️ Max attempts reached. Cooldown: ' + minutesRemaining + ' min remaining');
                    
                    if (minutesRemaining > 0) {
                        System.debug('❌ BLOCKING - Still in cooldown');
                        String cooldownMsg = 'Maximum attempts exceeded. Please try again after ' + minutesRemaining + ' minute(s).';
                        AuraHandledException ex = new AuraHandledException(cooldownMsg);
                        ex.setMessage(cooldownMsg);
                        throw ex;
                    }
                    
                    // Cooldown expired, reset
                    System.debug('🔄 Cooldown expired. Resetting attempts to 0');
                    session.Attempts__c = 0;
                } else if (session.Expires_At__c < System.now()) {
                    System.debug('🔄 Previous OTP expired. Resetting attempts to 0');
                    session.Attempts__c = 0;
                } else {
                    // FIX: Per Q-004, reset counter when user requests new OTP during active attempts
                    System.debug('🔄 Reusing session. Resetting attempts to 0 (new OTP request)');
                    session.Attempts__c = 0;
                }
                
                // Update with new OTP
                System.debug('📝 Updating session ' + session.Id + ' with new OTP');
                session.OTP__c = otp;
                session.Expires_At__c = System.now().addMinutes(OTP_EXPIRY_MIN);
                update session;
                System.debug('✅ Session updated');
            } else {
                // Create new session
                System.debug('❌ No existing session found. Creating NEW session');
                session = new Guest_OTP_Session__c(
                    Email__c = email.toLowerCase(),
                    OTP__c = otp,
                    Expires_At__c = System.now().addMinutes(OTP_EXPIRY_MIN),
                    Attempts__c = 0,
                    Verified__c = false
                );
                insert session;
                System.debug('✅ NEW SESSION CREATED');
                System.debug('   ID: ' + session.Id);
                System.debug('   Attempts: 0');
            }

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            
            try {
                List<OrgWideEmailAddress> owea = [
                    SELECT Id, Address 
                    FROM OrgWideEmailAddress 
                    WHERE DisplayName = 'ISB Support' 
                    LIMIT 1];
                if (!owea.isEmpty()) {
                    mail.setOrgWideEmailAddressId(owea[0].Id);
                    System.debug('📧 Using OrgWideEmailAddress: ' + owea[0].Address);
                } else {
                    System.debug('⚠️ No OrgWideEmailAddress found. Sending as current user (may fail for Guest Users).');
                }
            } catch (Exception e) {
                System.debug('⚠️ Error fetching OrgWideEmailAddress: ' + e.getMessage());
            }

            mail.setToAddresses(new String[]{ email });
            mail.setSubject('Your verification code');
            mail.setPlainTextBody('Your OTP is ' + otp + '. It expires in 10 minutes.');
            mail.setSaveAsActivity(false);
            
            System.debug('📤 Attempting to send email...');
            System.debug('📨 To Address = ' + email);
        
            Messaging.SendEmailResult[] results = Messaging.sendEmail(new Messaging.SingleEmailMessage[]{ mail });

            System.debug('📬 sendEmail results size = ' + results.size());

            for (Messaging.SendEmailResult r : results) {
                System.debug('📬 Email success = ' + r.isSuccess());
                if (!r.isSuccess()) {
                    for (Messaging.SendEmailError err : r.getErrors()) {
                        System.debug('❌ Email error: ' + err.getMessage());
                        System.debug('❌ Status code: ' + err.getStatusCode());
                    }
                }
            }
            
            return 'SUCCESS';

        } catch (Exception e) {
            System.debug('❌ EXCEPTION during sendEmail: ' + e.getMessage());
            return 'Error: ' + e.getMessage();
        }
    }

    // STEP 2: VERIFY OTP - BULLETPROOF VERSION WITH SESSION ID LOGGING
    @AuraEnabled
    public static String verifyOtp(String email, String otp) {
        System.debug('═══════════════════════════════════════════════════════════');
        System.debug('🔵 [VERIFY] Verifying OTP for email: ' + email + ' | OTP: ' + otp);
        
        try {
            // QUERY 1: GET CURRENT SESSION - GET THE MOST RECENT ONE ONLY
            String emailLower = email.toLowerCase();
            System.debug('Query: Fetching most recent unverified session for email: ' + emailLower);
            
            List<Guest_OTP_Session__c> sessions = [
                SELECT Id, OTP__c, Expires_At__c, Attempts__c, Verified__c, LastModifiedDate
                FROM Guest_OTP_Session__c
                WHERE Email__c = :emailLower
                AND Verified__c = false
                ORDER BY Attempts__c DESC, LastModifiedDate DESC
                LIMIT 1
            ];

            if (sessions.isEmpty()) {
                System.debug('❌ No unverified session found');
                return 'ERROR:OTP request not found. Please send OTP again.';
            }

            Guest_OTP_Session__c session = sessions[0];
            String sessionId = session.Id;
            Decimal currentAttemptsDecimal = session.Attempts__c != null ? session.Attempts__c : 0;
            Integer currentAttempts = Integer.valueOf(currentAttemptsDecimal);
            
            System.debug('✅ SESSION FETCHED');
            System.debug('   ID: ' + sessionId);
            System.debug('   Attempts: ' + currentAttempts + ' / ' + MAX_ATTEMPTS);
            System.debug('   OTP Match: ' + (session.OTP__c == otp));

            // CHECK: Already verified?
            if (session.Verified__c) {
                System.debug('✅ Already verified');
                return '0057200000AznKjAAJ';
            }

            // CHECK: Expired?
            if (session.Expires_At__c < System.now()) {
                System.debug('❌ OTP expired');
                return 'ERROR:OTP expired. Please request a new OTP.';
            }

            // CHECK: Max attempts exceeded?
            if (currentAttempts >= MAX_ATTEMPTS) {
                DateTime lastMod = session.LastModifiedDate;
                DateTime cooldownEnd = lastMod.addMinutes(15);
                Integer minutesLeft = (Integer)((cooldownEnd.getTime() - System.now().getTime()) / 60000);
                System.debug('Max attempts check: minutesLeft=' + minutesLeft);
                
                if (minutesLeft > 0) {
                    String msg = 'Maximum attempts exceeded. Please try again after ' + minutesLeft + ' minute(s).';
                    return 'ERROR:' + msg;
                }
            }

            // CHECK: OTP Match?
            if (session.OTP__c == otp) {
                System.debug('✅ OTP CORRECT!');
                session.Verified__c = true;
                // FIX: Don't increment attempts on correct OTP - only increment on failures
                update session;
                System.debug('✅ Session ' + sessionId + ' marked verified');
                return '0057200000AznKjAAJ';
            }

            // INCORRECT OTP - INCREMENT ATTEMPTS
            System.debug('❌ OTP INCORRECT');
            System.debug('Before increment: Attempts=' + currentAttempts);
            
            Integer newAttempts = currentAttempts + 1;
            session.Attempts__c = newAttempts;
            
            System.debug('Setting Attempts__c to: ' + newAttempts);
            
            // Use Database.update to get detailed error info
            List<Database.SaveResult> results = Database.update(new List<SObject>{session}, false);
            
            if (!results[0].isSuccess()) {
                String errorMsg = '';
                for (Database.Error err : results[0].getErrors()) {
                    errorMsg += err.getMessage() + ' | ';
                }
                System.debug('❌ UPDATE FAILED: ' + errorMsg);
                AuraHandledException ex = new AuraHandledException('Failed to update attempts: ' + errorMsg);
                ex.setMessage('Failed to update attempts: ' + errorMsg);
                throw ex;
            }
            System.debug('✅ Update succeeded for session ' + sessionId);

            // RE-QUERY TO VERIFY
            System.debug('Re-querying session ' + sessionId + ' to verify persistence...');
            List<Guest_OTP_Session__c> requeriedList = [
                SELECT Attempts__c
                FROM Guest_OTP_Session__c
                WHERE Id = :sessionId
                LIMIT 1
            ];
            
            if (requeriedList.isEmpty()) {
                System.debug('❌ RE-QUERY FAILED: Record not found!');
                return 'ERROR:Session record disappeared';
            }
            
            Decimal requeriedAttemptsDecimal = requeriedList[0].Attempts__c != null ? requeriedList[0].Attempts__c : 0;
            Integer requeriedAttempts = Integer.valueOf(requeriedAttemptsDecimal);
            System.debug('✅ RE-QUERIED: Attempts=' + requeriedAttempts + ' (expected: ' + newAttempts + ')');
            
            if (requeriedAttempts != newAttempts) {
                System.debug('⚠️ MISMATCH after update! Expected ' + newAttempts + ' but got ' + requeriedAttempts);
            }

            // CALCULATE & RESPOND
            Integer remaining = MAX_ATTEMPTS - requeriedAttempts;
            System.debug('Remaining: ' + MAX_ATTEMPTS + ' - ' + requeriedAttempts + ' = ' + remaining);

            if (remaining > 0) {
                String msg = 'Incorrect OTP. ' + remaining + ' attempt(s) remaining.';
                System.debug('📢 Sending: ' + msg);
                System.debug('═══════════════════════════════════════════════════════════════');
                return 'ERROR:' + msg;
            } else {
                String msg = 'Maximum attempts exceeded. Please try again after 15 minute(s).';
                System.debug('📢 Sending: ' + msg);
                System.debug('═══════════════════════════════════════════════════════════');
                return 'ERROR:' + msg;
            }

        } catch (AuraHandledException ae) {
            System.debug('🔴 AuraHandledException: ' + ae.getMessage());
            ae.setMessage(ae.getMessage());
            throw ae;
        } catch (Exception e) {
            System.debug('🔴 Exception: ' + e.getTypeName() + ' - ' + e.getMessage());
            System.debug('   Stack: ' + e.getStackTraceString());
            return 'ERROR:Error: ' + e.getMessage();
        }
    }

    // STEP 3: SERVER-SIDE AUTH CHECK (IMPORTANT)
    @AuraEnabled(cacheable=true)
    public static Boolean isOtpVerified(String email) {
        List<Guest_OTP_Session__c> sessions = [
            SELECT Verified__c, Expires_At__c
            FROM Guest_OTP_Session__c
            WHERE Email__c = :email.toLowerCase()
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];

        return !sessions.isEmpty()
            && sessions[0].Verified__c
            && sessions[0].Expires_At__c > System.now();
    }
//sid
    @AuraEnabled
    public static Contact getContactDetails(String email) {
        if (String.isBlank(email)) return null;
        List<Contact> contacts = [
            SELECT Id, Name, Email, Phone, AccountId, Account.Name, MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry, New_Admit_Email__c
            FROM Contact
            WHERE New_Admit_Email__c = :email
            LIMIT 1
        ];
        return contacts.isEmpty() ? null : contacts[0];
    }
    //sid
}