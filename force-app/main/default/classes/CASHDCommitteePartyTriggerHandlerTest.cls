@isTest
private class CASHDCommitteePartyTriggerHandlerTest {

    private static Id studentRecordTypeId;

    private static String unique(String prefix) {
        return prefix + String.valueOf(DateTime.now().getTime());
    }

    private static CASHD_Committee__c createCommittee() {
        CASHD_Committee__c committee = new CASHD_Committee__c();
        insert committee;
        return committee;
    }

    private static Contact createContact(String lastName, String vfEmail) {
        if (studentRecordTypeId == null) {
            studentRecordTypeId = [SELECT Id FROM RecordType WHERE SObjectType='Contact' AND DeveloperName='Student' LIMIT 1].Id;
        }
        String emailToUse = !String.isBlank(vfEmail) ? vfEmail : lastName.toLowerCase() + '@test.com';
        Contact c = new Contact(
            FirstName = 'Party', 
            LastName = lastName,
            Email = emailToUse,
            VF_Email_ID__c = emailToUse,
            hed__Preferred_Email__c = 'VF Email ID',
            RecordTypeId = studentRecordTypeId
        );
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.allowSave = true;
        Database.insert(c, dml);
        return c;
    }

    private static Id createProgramEnrollment(Contact contactRecord, String pgId) {
        Program prog = new Program(Name = unique('Prog-'));
        insert prog;

        ProgramEnrollment pe = new ProgramEnrollment(
            Name = unique('PE-'),
            ContactId = contactRecord.Id,
            ProgramId = prog.Id,
            PGID__c = pgId,
            Status = 'Registered'
        );
        insert pe;
        return pe.Id;
    }

    @isTest
    static void studentInsertPopulatesContactFromProgramEnrollment() {
        CASHD_Committee__c committee = createCommittee();
        Contact studentContact = createContact(unique('Student-'), null);
        String pgId = unique('PG-');
        createProgramEnrollment(studentContact, pgId);

        CASHD_Committee_Party__c party = new CASHD_Committee_Party__c(
            CASHD_Committee__c = committee.Id,
            Party_Role__c = 'Complainant',
            Party_Type__c = 'Student',
            Student_Id__c = pgId,
            Email__c = 'stale@example.com',
            Contact__c = null
        );

        insert party;

        CASHD_Committee_Party__c savedParty = [
            SELECT Student_Id__c, Email__c, Contact__c
            FROM CASHD_Committee_Party__c
            WHERE Id = :party.Id
        ];

        System.assertEquals(pgId, savedParty.Student_Id__c);
        System.assertEquals(null, savedParty.Email__c);
        System.assertEquals(studentContact.Id, savedParty.Contact__c);
    }

    @isTest
    static void nonStudentInsertPopulatesContactFromVfEmail() {
        CASHD_Committee__c committee = createCommittee();
        String vfEmail = unique('staff') + '@example.com';
        Contact staffContact = createContact(unique('Staff-'), vfEmail);

        CASHD_Committee_Party__c party = new CASHD_Committee_Party__c(
            CASHD_Committee__c = committee.Id,
            Party_Role__c = 'Respondent',
            Party_Type__c = 'Staff',
            Email__c = vfEmail.toUpperCase(),
            Contact__c = null
        );
        insert party;

        CASHD_Committee_Party__c savedParty = [
            SELECT Party_Type__c, Student_Id__c, Email__c, Contact__c
            FROM CASHD_Committee_Party__c
            WHERE Id = :party.Id
        ];

        System.assertEquals('Staff', savedParty.Party_Type__c);
        System.assertEquals(null, savedParty.Student_Id__c);
        System.assertEquals(vfEmail.toLowerCase(), savedParty.Email__c);
        System.assertEquals(staffContact.Id, savedParty.Contact__c);
    }

    @isTest
    static void typeChangeRepopulatesContactUsingRelevantIdentifier() {
        CASHD_Committee__c committee = createCommittee();
        String vfEmail = unique('alumni') + '@example.com';
        Contact alumniContact = createContact(unique('Alumni-'), vfEmail);

        Contact studentContact = createContact(unique('Student-'), null);
        String pgId = unique('PG-');
        createProgramEnrollment(studentContact, pgId);

        CASHD_Committee_Party__c party = new CASHD_Committee_Party__c(
            CASHD_Committee__c = committee.Id,
            Party_Role__c = 'Respondent',
            Party_Type__c = 'Alumni',
            Email__c = vfEmail,
            Contact__c = null
        );
        insert party;

        party.Party_Type__c = 'Student';
        party.Student_Id__c = pgId;
        party.Email__c = 'shouldclear@example.com';
        update party;

        CASHD_Committee_Party__c studentParty = [
            SELECT Party_Type__c, Student_Id__c, Email__c, Contact__c
            FROM CASHD_Committee_Party__c
            WHERE Id = :party.Id
        ];

        System.assertEquals('Student', studentParty.Party_Type__c);
        System.assertEquals(pgId, studentParty.Student_Id__c);
        System.assertEquals(null, studentParty.Email__c);
        System.assertEquals(studentContact.Id, studentParty.Contact__c);

        studentParty.Party_Type__c = 'Others';
        studentParty.Email__c = vfEmail;
        update studentParty;

        CASHD_Committee_Party__c othersParty = [
            SELECT Party_Type__c, Student_Id__c, Email__c, Contact__c
            FROM CASHD_Committee_Party__c
            WHERE Id = :party.Id
        ];

        System.assertEquals('Others', othersParty.Party_Type__c);
        System.assertEquals(null, othersParty.Student_Id__c);
        System.assertEquals(vfEmail, othersParty.Email__c);
        System.assertEquals(alumniContact.Id, othersParty.Contact__c);
    }

    @isTest
    static void validationRequiresStudentIdForStudentType() {
        CASHD_Committee__c committee = createCommittee();
        Boolean threw = false;

        try {
            insert new CASHD_Committee_Party__c(
                CASHD_Committee__c = committee.Id,
                Party_Role__c = 'Complainant',
                Party_Type__c = 'Student'
            );
        } catch (DmlException e) {
            threw = true;
            System.assert(e.getDmlMessage(0).contains('Student party rows require Student ID.'));
        }

        System.assert(threw, 'Expected validation error for student party without Student ID.');
    }

    @isTest
    static void validationRequiresEmailForNonStudentTypes() {
        CASHD_Committee__c committee = createCommittee();
        Boolean threw = false;

        try {
            insert new CASHD_Committee_Party__c(
                CASHD_Committee__c = committee.Id,
                Party_Role__c = 'Respondent',
                Party_Type__c = 'Others'
            );
        } catch (DmlException e) {
            threw = true;
            System.assert(e.getDmlMessage(0).contains('Staff, Alumni, and Others party rows require Email.'));
        }

        System.assert(threw, 'Expected validation error for non-student party without Email.');
    }

    @isTest
    static void directHandlerCallSkipsBlankAndUnchangedTypes() {
        String vfEmail = unique('keep') + '@example.com';
        Contact contactRecord = createContact(unique('Keep-'), vfEmail);

        CASHD_Committee__c committee = createCommittee();
        CASHD_Committee_Party__c existingParty = new CASHD_Committee_Party__c(
            CASHD_Committee__c = committee.Id,
            Party_Role__c = 'Complainant',
            Party_Type__c = 'Staff',
            Email__c = vfEmail
        );
        insert existingParty;

        CASHD_Committee_Party__c unchanged = new CASHD_Committee_Party__c(
            Id = existingParty.Id,
            Party_Type__c = 'Staff',
            Student_Id__c = 'PG-3003',
            Email__c = vfEmail,
            Contact__c = null
        );
        CASHD_Committee_Party__c blankType = new CASHD_Committee_Party__c(
            Party_Type__c = null,
            Student_Id__c = 'PG-4004',
            Email__c = 'blank@example.com',
            Contact__c = contactRecord.Id
        );

        Map<Id, CASHD_Committee_Party__c> oldMap = new Map<Id, CASHD_Committee_Party__c>{
            unchanged.Id => new CASHD_Committee_Party__c(Id = unchanged.Id, Party_Type__c = 'Staff')
        };

        Test.startTest();
        CASHDCommitteePartyTriggerHandler.clearStaleFields(
            new List<CASHD_Committee_Party__c>{ unchanged, blankType },
            oldMap
        );
        Test.stopTest();

        System.assertEquals('PG-3003', unchanged.Student_Id__c);
        System.assertEquals(vfEmail, unchanged.Email__c);
        System.assertEquals(contactRecord.Id, unchanged.Contact__c);

        System.assertEquals('PG-4004', blankType.Student_Id__c);
        System.assertEquals('blank@example.com', blankType.Email__c);
        System.assertEquals(contactRecord.Id, blankType.Contact__c);
    }
}