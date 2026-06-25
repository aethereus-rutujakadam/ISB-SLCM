@IsTest
public class GuestOtpAuthServiceTest {
 
    @TestSetup
    static void setupData() {
        
        Account acc = new Account(Name = 'OTP Account');
        insert acc;
        
        // Normal Contact with valid domain
        Contact normalContact = new Contact(
            FirstName = 'Normal',
            LastName = 'User',
            Email = 'normal@test.com',
            New_Admit_Email__c = 'normal@isb.edu',
            AccountId = acc.Id,
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = 'bodhtree.admin@isb.com'
            
        );
        insert normalContact;
        
        // PGP Contact with valid domain
        Contact pgpContact = new Contact(
            FirstName = 'PGP',
            LastName = 'User',
            Email = 'pgp@test.com',
            New_Admit_Email__c = 'pgp@yopmail.com',
            AccountId = acc.Id,
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = 'bodhtree.admin@isb.com'
        );
        insert pgpContact;
        
        Program prog = new Program(
            Name = 'PGP Program',
            Program_Type__c = 'PGP'
        );
        insert prog;
        
        ProgramEnrollment pe = new ProgramEnrollment(
            ContactId = pgpContact.Id,
            ProgramId = prog.Id,
            IsActive = true
        );
        insert pe;
    }
    
    @IsTest
    static void testSendOtp_BlankEmail() {
        String result = GuestOtpAuthService.sendOtp(null);
        System.assertEquals('Email is required', result);
    }
    
    @IsTest
    static void testSendOtp_InvalidDomain() {
        String result = GuestOtpAuthService.sendOtp('user@invalid.com');
    }
    
    @IsTest
    static void testSendOtp_NoContact() {
        String result = GuestOtpAuthService.sendOtp('unknown@isb.edu');
        System.assertEquals('No user found with this email address.', result);
    }
    @IsTest
    static void testSendOtp_PGPSuccess() {
        
           Account acc = new Account(Name = 'Test Account');
            insert acc;
        
          Contact con = new Contact(
                FirstName = 'Portal',
                LastName = 'Student',
                Email = 'portal@test.com',
                AccountId = acc.Id,
                hed__Preferred_Email__c = 'VF Email ID',
                VF_Email_ID__c = 'bodhtree.admin@isb.com',
               New_Admit_Email__c = 'portal@yopmail.com' 
            );
            insert con;
        
        Test.startTest();
        String result = GuestOtpAuthService.sendOtp(con.New_Admit_Email__c);
        Test.stopTest();
        
        System.assertEquals('SUCCESS', result);
    }
    
    @IsTest
    static void testSendOtp_Success() {
        
        // Get inserted contact dynamically
        Contact c = TestDataFactory.testContact();
        
        // Ensure contact has valid domain in New_Admit_Email__c
        c.New_Admit_Email__c = 'test@isb.edu';
        update c;
        
        Test.startTest();
        String result = GuestOtpAuthService.sendOtp(c.New_Admit_Email__c);
        Test.stopTest();
        
        System.assertEquals('SUCCESS', result);
        
        List<Guest_OTP_Session__c> sessions = [
            SELECT Id 
            FROM Guest_OTP_Session__c
            WHERE Email__c = :c.New_Admit_Email__c.toLowerCase()
        ];
        
        System.assertEquals(1, sessions.size());
    }
    
    
    @IsTest
    static void testVerifyOtp_NoSession() {
        try {
            GuestOtpAuthService.verifyOtp('nosession@test.com', '123456');
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }
    
    @IsTest
    static void testVerifyOtp_CorrectOtp() {
        
        Guest_OTP_Session__c session = new Guest_OTP_Session__c(
            Email__c = 'verify@test.com',
            OTP__c = '123456',
            Expires_At__c = System.now().addMinutes(10),
            Attempts__c = 0,
            Verified__c = false
        );
        insert session;
        
        String result = GuestOtpAuthService.verifyOtp('verify@test.com', '123456');
        
        System.assertNotEquals(null, result);
        
        Guest_OTP_Session__c updated = [
            SELECT Verified__c, Attempts__c
            FROM Guest_OTP_Session__c
            WHERE Id = :session.Id
        ];
        
        System.assertEquals(true, updated.Verified__c);
        // FIX: Correct OTP should NOT increment attempts (only failures increment)
        System.assertEquals(0, updated.Attempts__c);
    }
    
    @IsTest
    static void testVerifyOtp_WrongOtp() {
        
        Guest_OTP_Session__c session = new Guest_OTP_Session__c(
            Email__c = 'wrong@test.com',
            OTP__c = '999999',
            Expires_At__c = System.now().addMinutes(10),
            Attempts__c = 0,
            Verified__c = false
        );
        insert session;
        
        Test.startTest();
        try {
            GuestOtpAuthService.verifyOtp('wrong@test.com', '111111');
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            // ✅ Verify error message for wrong OTP
            System.assert(e.getMessage().contains('Incorrect OTP'), 'Should show incorrect OTP message. Actual: ' + e.getMessage());
            System.assert(e.getMessage().contains('2 attempt'), 'Should show remaining attempts. Actual: ' + e.getMessage());
        }
        Test.stopTest();
        
        Guest_OTP_Session__c updated = [
            SELECT Attempts__c
            FROM Guest_OTP_Session__c
            WHERE Id = :session.Id
        ];
        
        System.assertEquals(1, updated.Attempts__c);
    }
    
    @IsTest
    static void testVerifyOtp_Expired() {
        
        Guest_OTP_Session__c session = new Guest_OTP_Session__c(
            Email__c = 'expired@test.com',
            OTP__c = '123456',
            Expires_At__c = System.now().addMinutes(-5),
            Attempts__c = 0,
            Verified__c = false
        );
        insert session;
        
        Test.startTest();
        try {
            GuestOtpAuthService.verifyOtp('expired@test.com', '123456');
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            // ✅ Verify error message for expired OTP
            System.assert(e.getMessage().contains('OTP expired'), 'Should show OTP expired message. Actual: ' + e.getMessage());
            System.assert(e.getMessage().contains('new OTP'), 'Should suggest requesting new OTP. Actual: ' + e.getMessage());
        }
        Test.stopTest();
    }
    
    @IsTest
    static void testVerifyOtp_MaxAttemptsExceeded() {
        
        Guest_OTP_Session__c session = new Guest_OTP_Session__c(
            Email__c = 'max@test.com',
            OTP__c = '123456',
            Expires_At__c = System.now().addMinutes(10),
            Attempts__c = 3,
            Verified__c = false
        );
        insert session;
        
        Test.startTest();
        try {
            GuestOtpAuthService.verifyOtp('max@test.com', '123456');
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            // ✅ Verify error message for max attempts
            System.assert(e.getMessage().contains('Maximum attempts exceeded'), 'Should show max attempts exceeded. Actual: ' + e.getMessage());
            System.assert(e.getMessage().contains('15 minute'), 'Should mention 15 minutes cooldown. Actual: ' + e.getMessage());
        }
        Test.stopTest();
    }
    
    @IsTest
    static void testVerifyOtp_MultipleWrongAttempts() {
        
        Guest_OTP_Session__c session = new Guest_OTP_Session__c(
            Email__c = 'multi@test.com',
            OTP__c = '999999',
            Expires_At__c = System.now().addMinutes(10),
            Attempts__c = 0,
            Verified__c = false
        );
        insert session;
        
        Test.startTest();
        // Attempt 1 - wrong OTP
        try {
            GuestOtpAuthService.verifyOtp('multi@test.com', '111111');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('2 attempt'), 'Attempt 1 should show 2 remaining. Actual: ' + e.getMessage());
        }
        
        // Attempt 2 - wrong OTP
        try {
            GuestOtpAuthService.verifyOtp('multi@test.com', '222222');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('1 attempt'), 'Attempt 2 should show 1 remaining. Actual: ' + e.getMessage());
        }
        
        // Attempt 3 - wrong OTP (last attempt)
        try {
            GuestOtpAuthService.verifyOtp('multi@test.com', '333333');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Maximum attempts exceeded'), 'Attempt 3 should show max exceeded. Actual: ' + e.getMessage());
        }
        Test.stopTest();
        
        // Verify session has 3 attempts
        Guest_OTP_Session__c final_session = [
            SELECT Attempts__c
            FROM Guest_OTP_Session__c
            WHERE Id = :session.Id
        ];
        System.assertEquals(3, final_session.Attempts__c);
    }
    
    @IsTest
    static void testIsOtpVerified_True() {
        
        insert new Guest_OTP_Session__c(
            Email__c = 'true@test.com',
            OTP__c = '123456',
            Expires_At__c = System.now().addMinutes(10),
            Attempts__c = 0,
            Verified__c = true
        );
        
        Boolean result = GuestOtpAuthService.isOtpVerified('true@test.com');
        System.assertEquals(true, result);
    }
    
    @IsTest
    static void testIsOtpVerified_False() {
        Boolean result = GuestOtpAuthService.isOtpVerified('false@test.com');
        System.assertEquals(false, result);
    }
    
    @IsTest
    static void testGetContactDetails_Found() {
        
        Contact c = TestDataFactory.testContact();
        
        Contact result = GuestOtpAuthService.getContactDetails(c.Email);
    }
    
    @IsTest
    static void testGetContactDetails_NotFound() {
        Contact result = GuestOtpAuthService.getContactDetails('unknown@test.com');
        System.assertEquals(null, result);
    }
    
    @IsTest
    static void testGetContactDetails_Blank() {
        Contact result = GuestOtpAuthService.getContactDetails(null);
        System.assertEquals(null, result);
    }
    
    // ===== ISB-6036: COMPREHENSIVE AC TEST COVERAGE =====
    
    @IsTest
    static void testAC001_FirstIncorrectAttempt_Shows2Remaining() {
        // AC-001: After entering first incorrect OTP, error message displays "Incorrect OTP. 2 attempt(s) remaining."
        
        Guest_OTP_Session__c session = new Guest_OTP_Session__c(
            Email__c = 'ac001@test.com',
            OTP__c = '999999',
            Expires_At__c = System.now().addMinutes(10),
            Attempts__c = 0,
            Verified__c = false
        );
        insert session;
        
        Test.startTest();
        try {
            GuestOtpAuthService.verifyOtp('ac001@test.com', '111111'); // Wrong OTP
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Incorrect OTP'), 'Should contain Incorrect OTP. Actual: ' + e.getMessage());
            System.assert(e.getMessage().contains('2 attempt'), 'Should show 2 attempts remaining (AC-001). Actual: ' + e.getMessage());
        }
        Test.stopTest();
        
        // Verify counter incremented to 1
        Guest_OTP_Session__c updated = [SELECT Attempts__c FROM Guest_OTP_Session__c WHERE Id = :session.Id];
        System.assertEquals(1, updated.Attempts__c, 'Counter should be 1 after first failure');
    }
    
    @IsTest
    static void testAC002_SecondIncorrectAttempt_Shows1Remaining() {
        // AC-002: After entering second incorrect OTP, error message displays "Incorrect OTP. 1 attempt remaining."
        
        Guest_OTP_Session__c session = new Guest_OTP_Session__c(
            Email__c = 'ac002@test.com',
            OTP__c = '999999',
            Expires_At__c = System.now().addMinutes(10),
            Attempts__c = 1, // Already 1 failed attempt
            Verified__c = false
        );
        insert session;
        
        Test.startTest();
        try {
            GuestOtpAuthService.verifyOtp('ac002@test.com', '222222'); // Wrong OTP
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Incorrect OTP'), 'Should contain Incorrect OTP. Actual: ' + e.getMessage());
            System.assert(e.getMessage().contains('1 attempt'), 'Should show 1 attempt remaining (AC-002). Actual: ' + e.getMessage());
        }
        Test.stopTest();
        
        // Verify counter incremented to 2
        Guest_OTP_Session__c updated = [SELECT Attempts__c FROM Guest_OTP_Session__c WHERE Id = :session.Id];
        System.assertEquals(2, updated.Attempts__c, 'Counter should be 2 after second failure');
    }
    
    @IsTest
    static void testAC003_AC004_MaxAttempts_ShowsMaxExceeded() {
        // AC-003: After maximum failed attempts reached, system displays "Send OTP Again" option
        // AC-004: After maximum failed attempts reached, system does not allow OTP entry
        
        Guest_OTP_Session__c session = new Guest_OTP_Session__c(
            Email__c = 'ac003@test.com',
            OTP__c = '999999',
            Expires_At__c = System.now().addMinutes(10),
            Attempts__c = 2, // Already 2 failed attempts
            Verified__c = false
        );
        insert session;
        
        Test.startTest();
        try {
            GuestOtpAuthService.verifyOtp('ac003@test.com', '333333'); // 3rd wrong OTP
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Maximum attempts exceeded'), 'Should show max attempts exceeded (AC-003/004). Actual: ' + e.getMessage());
        }
        Test.stopTest();
        
        // Verify counter incremented to 3
        Guest_OTP_Session__c updated = [SELECT Attempts__c FROM Guest_OTP_Session__c WHERE Id = :session.Id];
        System.assertEquals(3, updated.Attempts__c, 'Counter should be 3 after third failure');
    }
    
    @IsTest
    static void testAC005_CounterDecrementsExactlyByOne() {
        // AC-005: Attempt counter correctly decrements by exactly 1 after each incorrect OTP verification attempt
        // (Note: "decrements" in requirements means remaining attempts decrease; counter increments)
        
        Guest_OTP_Session__c session = new Guest_OTP_Session__c(
            Email__c = 'ac005@test.com',
            OTP__c = '999999',
            Expires_At__c = System.now().addMinutes(10),
            Attempts__c = 0,
            Verified__c = false
        );
        insert session;
        
        Test.startTest();
        // Failure 1
        try { GuestOtpAuthService.verifyOtp('ac005@test.com', '111111'); } catch (Exception e) {}
        session = [SELECT Attempts__c FROM Guest_OTP_Session__c WHERE Id = :session.Id];
        System.assertEquals(1, session.Attempts__c, '1st failure: counter should be 1');
        
        // Failure 2
        try { GuestOtpAuthService.verifyOtp('ac005@test.com', '222222'); } catch (Exception e) {}
        session = [SELECT Attempts__c FROM Guest_OTP_Session__c WHERE Id = :session.Id];
        System.assertEquals(2, session.Attempts__c, '2nd failure: counter should be 2 (incremented by 1)');
        
        // Failure 3
        try { GuestOtpAuthService.verifyOtp('ac005@test.com', '333333'); } catch (Exception e) {}
        session = [SELECT Attempts__c FROM Guest_OTP_Session__c WHERE Id = :session.Id];
        System.assertEquals(3, session.Attempts__c, '3rd failure: counter should be 3 (incremented by 1)');
        Test.stopTest();
    }
    
    @IsTest
    static void testQ004_NewOtpRequest_ResetsCounter() {
        // Q-004 fix: When user requests new OTP during active attempts, counter should reset to 0
        
        Account acc = new Account(Name = 'Q004 Account');
        insert acc;
        
        Contact con = new Contact(
            FirstName = 'Q004',
            LastName = 'User',
            Email = 'q004@test.com',
            New_Admit_Email__c = 'q004@isb.edu',
            AccountId = acc.Id,
            hed__Preferred_Email__c = 'VF Email ID',
            VF_Email_ID__c = 'test@isb.com'
        );
        insert con;
        
        // Create session with 2 failed attempts
        Guest_OTP_Session__c session = new Guest_OTP_Session__c(
            Email__c = 'q004@isb.edu',
            OTP__c = '999999',
            Expires_At__c = System.now().addMinutes(10),
            Attempts__c = 2,
            Verified__c = false
        );
        insert session;
        
        Test.startTest();
        // User requests new OTP - should reset counter
        String result = GuestOtpAuthService.sendOtp('q004@isb.edu');
        Test.stopTest();
        
        System.assertEquals('SUCCESS', result, 'SendOTP should succeed');
        
        // Verify counter was reset to 0
        Guest_OTP_Session__c updated = [SELECT Attempts__c FROM Guest_OTP_Session__c WHERE Id = :session.Id];
        System.assertEquals(0, updated.Attempts__c, 'Counter should reset to 0 when new OTP requested (Q-004)');
    }
}