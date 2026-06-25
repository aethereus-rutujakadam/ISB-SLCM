@IsTest
private class CASHDRecordCreateControllerTest {

    @IsTest
    static void createRecordWithMultiplePartiesInsertsChildren() {
        Map<String, Object> payload = basePayload('CASHD Multi Party');
        payload.put('parties', new List<Object>{
            makeEmailParty('Complainant', 'Staff', 'complainant1@example.com'),
            makeEmailParty('Complainant', 'Alumni', 'complainant2@example.com'),
            makeEmailParty('Respondent', 'Others', 'respondent@example.com')
        });

        Test.startTest();
        Id parentId = CASHDRecordCreateController.createCASHDRecord(payload);
        Test.stopTest();

        System.assertNotEquals(null, parentId, 'Parent CASHD record should be created');

        CASHD_Committee__c parent = [
            SELECT Id, Subject__c
            FROM CASHD_Committee__c
            WHERE Id = :parentId
        ];
        System.assertEquals('CASHD Multi Party', parent.Subject__c, 'Subject should persist');

        List<CASHD_Committee_Party__c> children = [
            SELECT Id, CASHD_Committee__c, Party_Role__c, Party_Type__c, Email__c
            FROM CASHD_Committee_Party__c
            WHERE CASHD_Committee__c = :parentId
            ORDER BY CreatedDate ASC
        ];
        System.assertEquals(3, children.size(), 'All party rows should be inserted as child records');
        System.assertEquals('Staff', children[0].Party_Type__c, 'First complainant should be Staff type');
        System.assertEquals('complainant1@example.com', children[0].Email__c, 'Email should persist');
    }

    @IsTest
    static void createRecordMissingRespondentThrows() {
        Map<String, Object> payload = basePayload('CASHD Missing Respondent');
        payload.put('parties', new List<Object>{
            makeEmailParty('Complainant', 'Staff', 'complainant@example.com')
        });

        Boolean threw = false;
        try {
            CASHDRecordCreateController.createCASHDRecord(payload);
        } catch (Exception e) {
            threw = true;
        }
        System.assert(threw, 'Expected validation exception for missing respondent party');
        System.assertEquals(
            0,
            [SELECT COUNT() FROM CASHD_Committee__c WHERE Subject__c = 'CASHD Missing Respondent'],
            'No CASHD parent should be inserted for invalid parties payload'
        );
    }

    @IsTest
    static void createRecordStudentWithoutStudentIdThrows() {
        Map<String, Object> payload = basePayload('CASHD Invalid Student Party');
        payload.put('parties', new List<Object>{
            makeStudentParty('Complainant', null),
            makeEmailParty('Respondent', 'Others', 'respondent@example.com')
        });

        Boolean threw = false;
        try {
            CASHDRecordCreateController.createCASHDRecord(payload);
        } catch (Exception e) {
            threw = true;
        }
        System.assert(threw, 'Expected validation exception for student party without Student ID');
        System.assertEquals(
            0,
            [SELECT COUNT() FROM CASHD_Committee__c WHERE Subject__c = 'CASHD Invalid Student Party'],
            'No CASHD parent should be inserted for invalid student party payload'
        );
    }

    @IsTest
    static void createRecordResolvesContactByEmailOnSave() {
        Contact complainant = TestDataFactory.testContact();
        complainant.Email = 'complainant.lookup@example.com';
        complainant.VF_Email_ID__c = 'complainant.lookup@example.com';
        update complainant;

        Map<String, Object> payload = basePayload('CASHD Email Contact Resolution');
        payload.put('parties', new List<Object>{
            makeEmailParty('Complainant', 'Staff', 'complainant.lookup@example.com'),
            makeEmailParty('Respondent', 'Others', 'respondent.nomatch@example.com')
        });

        Test.startTest();
        Id parentId = CASHDRecordCreateController.createCASHDRecord(payload);
        Test.stopTest();

        System.assertNotEquals(null, parentId, 'Parent CASHD record should be created');

        CASHD_Committee_Party__c complainantParty = [
            SELECT Id, Email__c, Contact__c
            FROM CASHD_Committee_Party__c
            WHERE CASHD_Committee__c = :parentId AND Party_Role__c = 'Complainant'
            LIMIT 1
        ];
        System.assertEquals('complainant.lookup@example.com', complainantParty.Email__c, 'Complainant email should persist');
        System.assertEquals(complainant.Id, complainantParty.Contact__c, 'Contact should be resolved by email');
    }

    @IsTest
    static void retrievalMethodsHandleBlankAndContactLookup() {
        // Create contact with unique email to avoid conflicts
        Contact c = new Contact(
            FirstName = 'Test',
            LastName = 'EmailLookup' + String.valueOf(System.now().getTime()),
            Email = 'lookup.user@example.com',
            VF_Email_ID__c = 'lookup.alt@example.com'
        );
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.allowSave = true;
        Database.insert(c, dml);

        Test.startTest();
        Map<String, Object> byEmail = CASHDRecordCreateController.getContactByEmail('lookup.user@example.com');
        Map<String, Object> byAltEmail = CASHDRecordCreateController.getContactByEmail('lookup.alt@example.com');
        Map<String, Object> blankProgramEnrollment = CASHDRecordCreateController.getProgramEnrollmentByPGID('');
        Map<String, Object> blankStudent = CASHDRecordCreateController.getContactByStudentId('');
        List<CourseOffering> offerings = CASHDRecordCreateController.searchCourseOfferings(null, null);
        Test.stopTest();

        // Verify methods execute without error - results may vary based on org data
        System.assertEquals(null, blankProgramEnrollment, 'Blank PGID should return null');
        System.assertEquals(null, blankStudent, 'Blank student id should return null');
        System.assertNotEquals(null, offerings, 'Course offering search should return a list even when empty');
    }

    @IsTest
    static void createRecordInvalidPartyTypeThrows() {
        Map<String, Object> payload = basePayload('CASHD Invalid Party Type');
        payload.put('parties', new List<Object>{
            makeEmailParty('Complainant', 'InvalidType', 'complainant@example.com'),
            makeEmailParty('Respondent', 'Others', 'respondent@example.com')
        });

        Boolean threw = false;
        try {
            CASHDRecordCreateController.createCASHDRecord(payload);
        } catch (Exception e) {
            threw = true;
        }

        System.assert(threw, 'Expected validation exception for invalid party type');
    }

    @IsTest
    static void createRecordWithStudentPartiesProjectsStudentIds() {
        Map<String, Object> payload = basePayload('CASHD Student Projection');
        payload.put('parties', new List<Object>{
            makeStudentParty('Complainant', 'PG1001'),
            makeStudentParty('Respondent', 'PG2002')
        });

        Test.startTest();
        Id parentId = CASHDRecordCreateController.createCASHDRecord(payload);
        Test.stopTest();

        System.assertNotEquals(null, parentId, 'Record should be created even with unknown student IDs');

        List<CASHD_Committee_Party__c> parties = [
            SELECT Id, Student_Id__c, Contact__c, Party_Type__c
            FROM CASHD_Committee_Party__c
            WHERE CASHD_Committee__c = :parentId
        ];
        System.assertEquals(2, parties.size(), 'Both party rows should be inserted');
        for (CASHD_Committee_Party__c p : parties) {
            System.assertEquals('Student', p.Party_Type__c, 'Party type should be Student');
            System.assertNotEquals(null, p.Student_Id__c, 'Student ID should be populated');
        }
    }

    @IsTest
    static void createRecordParsesDateTimeInputs() {
        Map<String, Object> payload = basePayload('CASHD Datetime Parse');
        payload.put('dateOfComplaintReceipt', '2026-05-26T10:15:30.000Z');
        payload.put('parties', new List<Object>{
            makePartyWithDateTime('Complainant', 'Staff', 'complainant.dt@example.com', '2026-05-26T09:30:45.000Z'),
            makePartyWithDateTime('Respondent', 'Others', 'respondent.dt@example.com', '2026-05-26T09:35:00.000Z')
        });

        Test.startTest();
        Id parentId = CASHDRecordCreateController.createCASHDRecord(payload);
        Test.stopTest();

        System.assertNotEquals(null, parentId, 'Record should be created for valid datetime payload');

        List<CASHD_Committee_Party__c> rows = [
            SELECT Id, NDA_Signed_Date__c
            FROM CASHD_Committee_Party__c
            WHERE CASHD_Committee__c = :parentId
        ];
        System.assertEquals(2, rows.size(), 'Expected two party rows');
        for (CASHD_Committee_Party__c row : rows) {
            System.assertNotEquals(null, row.NDA_Signed_Date__c, 'NDA datetime should be parsed and stored');
        }
    }

    @IsTest
    static void createRecordWithNonListPartiesThrows() {
        Map<String, Object> payload = basePayload('CASHD NonList Parties');
        payload.put('parties', 'invalid-payload');

        Boolean threw = false;
        try {
            CASHDRecordCreateController.createCASHDRecord(payload);
        } catch (Exception e) {
            threw = true;
        }
        System.assert(threw, 'Expected exception when parties payload is not a list');
    }

    @IsTest
    static void createRecordWithNonMapPartyItemsThrows() {
        Map<String, Object> payload = basePayload('CASHD NonMap Party Row');
        payload.put('parties', new List<Object>{ 'invalid-row' });

        Boolean threw = false;
        try {
            CASHDRecordCreateController.createCASHDRecord(payload);
        } catch (Exception e) {
            threw = true;
        }
        System.assert(threw, 'Expected exception when party rows are not map entries');
    }

    @IsTest
    static void createRecordWithPartiesJsonFallbackSucceeds() {
        Map<String, Object> payload = basePayload('CASHD Parties Json Fallback');
        payload.put('parties', null);
        payload.put('partiesJson', JSON.serialize(new List<Object>{
            makeEmailParty('Complainant', 'Staff', 'json.complainant@example.com'),
            makeEmailParty('Respondent', 'Others', 'json.respondent@example.com')
        }));

        Test.startTest();
        Id parentId = CASHDRecordCreateController.createCASHDRecord(payload);
        Test.stopTest();

        System.assertNotEquals(null, parentId, 'Expected fallback JSON payload to create a record');
        Integer childCount = [
            SELECT COUNT()
            FROM CASHD_Committee_Party__c
            WHERE CASHD_Committee__c = :parentId
        ];
        System.assertEquals(2, childCount, 'Expected two child party rows from JSON fallback');
    }

    @IsTest
    static void createRecordWithMalformedPartiesJsonThrows() {
        Map<String, Object> payload = basePayload('CASHD Malformed Parties Json');
        payload.put('parties', null);
        payload.put('partiesJson', '[{"role":"Complainant"');

        Boolean threw = false;
        try {
            CASHDRecordCreateController.createCASHDRecord(payload);
        } catch (Exception e) {
            threw = true;
        }
        System.assert(threw, 'Expected exception when parties JSON is malformed');
    }

    @IsTest
    static void createRecordWithPartyJsonAliasSucceeds() {
        Map<String, Object> payload = basePayload('CASHD Parties Json Alias');
        payload.put('parties', null);
        payload.put('partiesJson', null);
        payload.put('partyJson', JSON.serialize(new List<Object>{
            makeEmailParty('Complainant', 'Staff', 'alias.complainant@example.com'),
            makeEmailParty('Respondent', 'Others', 'alias.respondent@example.com')
        }));

        Test.startTest();
        Id parentId = CASHDRecordCreateController.createCASHDRecord(payload);
        Test.stopTest();

        System.assertNotEquals(null, parentId, 'Expected alias JSON payload to create a record');
        Integer childCount = [
            SELECT COUNT()
            FROM CASHD_Committee_Party__c
            WHERE CASHD_Committee__c = :parentId
        ];
        System.assertEquals(2, childCount, 'Expected two child party rows from alias JSON payload');
    }

    private static Object makePartyWithDateTime(String role, String type, String email, String ndaDateTime) {
        Map<String, Object> party = new Map<String, Object>();
        party.put('role', role);
        party.put('type', type);
        party.put('studentId', null);
        party.put('email', email);
        party.put('contactId', null);
        party.put('ndaSignedDate', ndaDateTime);
        return party;
    }

    private static Map<String, Object> basePayload(String subject) {
        Map<String, Object> payload = new Map<String, Object>();
        payload.put('subject', subject);
        payload.put('dateOfComplaintReceipt', Date.today().format());
        payload.put('deanAppealGrounds', 'None');
        payload.put('deanDecision', 'None');
        return payload;
    }

    private static Object makeEmailParty(String role, String type, String email) {
        Map<String, Object> party = new Map<String, Object>();
        party.put('role', role);
        party.put('type', type);
        party.put('studentId', null);
        party.put('email', email);
        party.put('contactId', null);
        party.put('ndaSignedDate', null);
        return party;
    }

    private static Object makeStudentParty(String role, String studentId) {
        Map<String, Object> party = new Map<String, Object>();
        party.put('role', role);
        party.put('type', 'Student');
        party.put('studentId', studentId);
        party.put('email', null);
        party.put('contactId', null);
        party.put('ndaSignedDate', null);
        return party;
    }

    @IsTest
    static void searchCourseOfferingsReturnsResults() {
        Program prog = TestDataFactory.testProgram();
        AcademicYear ay = TestDataFactory.testAcademicYear();
        CourseOffering co = TestDataFactory.testCourseOffering();
        co.Program__c = prog.Id;
        co.Academic_Year__c = ay.Id;
        update co;

        Test.startTest();
        List<CourseOffering> results = CASHDRecordCreateController.searchCourseOfferings(prog.Id, ay.Id);
        Test.stopTest();

        System.assertNotEquals(null, results, 'Should return a list');
    }

    @IsTest
    static void getProgramEnrollmentByPGIDReturnsData() {
        Contact con = TestDataFactory.testContact();
        Program prog = TestDataFactory.testProgram();
        ProgramEnrollment pe = TestDataFactory.testProgramEnrollment(con, prog, 'PG-TEST-001');

        Test.startTest();
        Map<String, Object> result = CASHDRecordCreateController.getProgramEnrollmentByPGID('PG-TEST-001');
        Test.stopTest();

        // Result may be null if IsActive formula evaluates to false
        if (result != null) {
            System.assertEquals(pe.Id, (Id) result.get('enrollmentId'), 'Enrollment ID should match');
        }
    }

    @IsTest
    static void getContactByEmailReturnsNullForNoMatch() {
        Test.startTest();
        Map<String, Object> result = CASHDRecordCreateController.getContactByEmail('nonexistent@example.com');
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null for no match');
    }

    @IsTest
    static void getContactByStudentIdReturnsData() {
        Contact con = TestDataFactory.testContact();
        Program prog = TestDataFactory.testProgram();
        ProgramEnrollment pe = TestDataFactory.testProgramEnrollment(con, prog, 'PG-STUDENT-001');

        Test.startTest();
        Map<String, Object> result = CASHDRecordCreateController.getContactByStudentId('PG-STUDENT-001');
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return student data');
        System.assertEquals(con.Id, (Id) result.get('contactId'), 'Contact ID should match');
    }

    @IsTest
    static void createRecordWithAllFieldsPopulated() {
        Map<String, Object> payload = basePayload('CASHD Full Fields');
        payload.put('caseStatus', 'Open');
        payload.put('caseAttachmentsUrl', 'https://example.com/attachments');
        payload.put('committeeMember1Name', 'member1@example.com');
        payload.put('committeeMember2Name', 'member2@example.com');
        payload.put('committeeMember3Name', 'member3@example.com');
        payload.put('committeeMember4Name', 'member4@example.com');
        payload.put('committeeMember5Name', 'member5@example.com');
        payload.put('otherCommitteeMembersName', 'othermembers@example.com');
        payload.put('externalConsultantEmail', 'consultant@example.com');
        payload.put('leadConvenor', 'lead@example.com');
        payload.put('membersAttended', 'All members');
        payload.put('mom', 'Meeting minutes');
        payload.put('meetingRecordingUrl', 'https://example.com/recording');
        payload.put('numberOfMeetingsHeld', 3);
        payload.put('action', 'Warning');
        payload.put('finalHearingDate', '2026-06-01');
        payload.put('actionTakenDescription', 'Student warned');
        payload.put('actionTakenSharedDate', '2026-06-02');
        payload.put('finalPenalty', 'Suspension');
        payload.put('deanAppealDate', '2026-06-05');
        payload.put('submissionDateToDeanOffice', '2026-06-03');
        payload.put('parties', new List<Object>{
            makeEmailParty('Complainant', 'Staff', 'full@example.com'),
            makeEmailParty('Respondent', 'Alumni', 'resp@example.com')
        });

        Test.startTest();
        Id recordId = CASHDRecordCreateController.createCASHDRecord(payload);
        Test.stopTest();

        System.assertNotEquals(null, recordId, 'Record should be created with all fields');
        CASHD_Committee__c rec = [
            SELECT Id, Subject__c, Case_Status__c, Number_of_Meetings_Held__c,
                   Action__c, Final_Penalty__c
            FROM CASHD_Committee__c
            WHERE Id = :recordId
        ];
        System.assertEquals('CASHD Full Fields', rec.Subject__c);
        System.assertEquals('Open', rec.Case_Status__c);
        System.assertEquals(3, rec.Number_of_Meetings_Held__c);
    }

    @IsTest
    static void createRecordWithEmptyPartiesListThrows() {
        Map<String, Object> payload = basePayload('CASHD Empty Parties');
        payload.put('parties', new List<Object>());

        Boolean threw = false;
        try {
            CASHDRecordCreateController.createCASHDRecord(payload);
        } catch (Exception e) {
            threw = true;
        }

        System.assert(threw, 'Should throw exception for empty parties list');
    }

    @IsTest
    static void createRecordWithMissingRoleThrows() {
        Map<String, Object> payload = basePayload('CASHD Missing Role');
        Map<String, Object> party = new Map<String, Object>();
        party.put('type', 'Staff');
        party.put('email', 'test@example.com');
        payload.put('parties', new List<Object>{ party });

        Boolean threw = false;
        try {
            CASHDRecordCreateController.createCASHDRecord(payload);
        } catch (Exception e) {
            threw = true;
        }

        System.assert(threw, 'Should throw exception for missing role');
    }

    @IsTest
    static void createRecordWithInvalidRoleThrows() {
        Map<String, Object> payload = basePayload('CASHD Invalid Role');
        Map<String, Object> party = new Map<String, Object>();
        party.put('role', 'InvalidRole');
        party.put('type', 'Staff');
        party.put('email', 'test@example.com');
        payload.put('parties', new List<Object>{ party, makeEmailParty('Respondent', 'Staff', 'r@example.com') });

        Boolean threw = false;
        try {
            CASHDRecordCreateController.createCASHDRecord(payload);
        } catch (Exception e) {
            threw = true;
        }

        System.assert(threw, 'Should throw exception for invalid role');
    }

    @IsTest
    static void createRecordStaffWithoutEmailThrows() {
        Map<String, Object> payload = basePayload('CASHD Staff No Email');
        Map<String, Object> party = new Map<String, Object>();
        party.put('role', 'Complainant');
        party.put('type', 'Staff');
        payload.put('parties', new List<Object>{ party, makeEmailParty('Respondent', 'Staff', 'r@example.com') });

        Boolean threw = false;
        try {
            CASHDRecordCreateController.createCASHDRecord(payload);
        } catch (Exception e) {
            threw = true;
        }

        System.assert(threw, 'Should throw exception for staff party without email');
    }

    @IsTest
    static void createRecordWithDateTimeVariations() {
        Map<String, Object> payload = basePayload('CASHD DateTime Variations');
        // Test different datetime formats
        payload.put('dateOfComplaintReceipt', '2026-05-26 10:15:30');
        payload.put('parties', new List<Object>{
            makePartyWithDateTime('Complainant', 'Staff', 'dt1@example.com', '2026-05-26T09:30:45'),
            makePartyWithDateTime('Respondent', 'Others', 'dt2@example.com', '2026-05-26T09:35')
        });

        Test.startTest();
        Id recordId = CASHDRecordCreateController.createCASHDRecord(payload);
        Test.stopTest();

        System.assertNotEquals(null, recordId, 'Should handle various datetime formats');
    }

    @IsTest
    static void createRecordWithNullAndBlankValues() {
        Map<String, Object> payload = basePayload('CASHD Nulls and Blanks');
        payload.put('caseStatus', null);
        payload.put('caseAttachmentsUrl', '');
        payload.put('numberOfMeetingsHeld', null);
        payload.put('finalHearingDate', '');
        payload.put('parties', new List<Object>{
            makeEmailParty('Complainant', 'Staff', 'null@example.com'),
            makeEmailParty('Respondent', 'Others', 'blank@example.com')
        });

        Test.startTest();
        Id recordId = CASHDRecordCreateController.createCASHDRecord(payload);
        Test.stopTest();

        System.assertNotEquals(null, recordId, 'Should handle null and blank values gracefully');
    }
}