public with sharing class InternationalExchangeController {

    @AuraEnabled
    public static Map<String, Object> processExchangeData(List<Map<String, Object>> records) {

        Map<String, Object> response = new Map<String, Object>{
            'successCount' => 0,
            'failedCount'  => 0,
            'errorRows'    => new List<Map<String,Object>>(),
            'errorCSV'     => ''
        };

        if (records == null || records.isEmpty()) return response;

        List<Map<String,Object>> errorRows = new List<Map<String,Object>>();
        Set<String> programNames        = new Set<String>();
        Set<String> pgidSet             = new Set<String>();
        Set<String> academicTermNames   = new Set<String>();
        Set<String> academicSessionNames = new Set<String>();

        for (Map<String,Object> r : records) {
            programNames.add((String) r.get('programName'));
            pgidSet.add((String) r.get('pgid'));

            String termName = (String) r.get('academicTerm');
            if (String.isNotBlank(termName)) {
                academicTermNames.add(termName.trim());
            }
            String sessionName = (String) r.get('academicSession');
            if (String.isNotBlank(sessionName)) {
                for (String token : sessionName.split(',')) {
                    if (String.isNotBlank(token)) {
                        academicSessionNames.add(token.trim());
                    }
                }
            }
        }

        // Fetch Programs
        Map<String, Id> programNameToId = new Map<String, Id>();
        for (Program p : [SELECT Id, Name FROM Program WHERE Name IN :programNames]) {
            programNameToId.put(p.Name.trim(), p.Id);
        }

        // Fetch Academic Terms filtered by Program
        Map<String, Id> academicTermNameToId = new Map<String, Id>();
        Set<Id> programIds = new Set<Id>(programNameToId.values());
        for (AcademicTerm at : [
            SELECT Id, Name FROM AcademicTerm
            WHERE Name IN :academicTermNames AND Program__c IN :programIds
        ]) {
            academicTermNameToId.put(at.Name.trim(), at.Id);
        }

        // Fetch Academic Sessions
        Map<String, Id> academicSessionNameToId = new Map<String, Id>();
        for (AcademicSession asess : [
            SELECT Id, Name FROM AcademicSession WHERE Name IN :academicSessionNames
        ]) {
            academicSessionNameToId.put(asess.Name.trim(), asess.Id);
        }

        // Duplicate StudentId check within uploaded file
        Set<String> seen = new Set<String>();
        for (Map<String,Object> row : records) {
            String pg = (String) row.get('pgid');
            if (seen.contains(pg)) {
                errorRows.add(new Map<String,Object>{
                    'StudentId'    => pg,
                    'ContactName'  => row.get('fullName'),
                    'ProgramName'  => row.get('programName'),
                    'errorMessage' => 'Duplicate Student Id in uploaded file'
                });
            } else {
                seen.add(pg);
            }
        }

        // Check PGIDs that already exist in system
        Map<String, Id> pgidToExistingContact = new Map<String, Id>();
        for (ProgramEnrollment pe : [
            SELECT PGID__c, ContactId FROM ProgramEnrollment WHERE PGID__c IN :pgidSet
        ]) {
            if (pe.ContactId != null) {
                pgidToExistingContact.put(pe.PGID__c, pe.ContactId);
            }
        }

        // F-04 FIX: Single-pass O(n) check — was O(n×m) nested loop
        for (Map<String,Object> row : records) {
            String pg = (String) row.get('pgid');
            if (pgidToExistingContact.containsKey(pg)) {
                errorRows.add(new Map<String,Object>{
                    'StudentId'    => pg,
                    'ContactName'  => row.get('fullName'),
                    'ProgramName'  => row.get('programName'),
                    'errorMessage' => 'Student Id already exists in system'
                });
            }
        }

        // Check for outgoing exchange type (not supported)
        for (Map<String,Object> row : records) {
            String exchangeType = (String) row.get('exchangeType');
            if (String.isNotBlank(exchangeType) && exchangeType.trim().equalsIgnoreCase('outgoing')) {
                errorRows.add(new Map<String,Object>{
                    'StudentId'    => row.get('pgid'),
                    'ContactName'  => row.get('fullName'),
                    'ProgramName'  => row.get('programName'),
                    'errorMessage' => 'Outgoing exchange type is not supported'
                });
            }
        }

        // Remove invalid PGIDs from processing
        Set<String> invalidPgids = new Set<String>();
        for (Map<String,Object> e : errorRows) {
            invalidPgids.add((String)e.get('StudentId'));
        }

        List<Map<String,Object>> validRecords = new List<Map<String,Object>>();
        for (Map<String,Object> r : records) {
            if (!invalidPgids.contains((String) r.get('pgid'))) {
                validRecords.add(r);
            }
        }

        Id studentContactRTId = Schema.SObjectType.Contact
            .getRecordTypeInfosByName().get('Student').getRecordTypeId();

        List<Map<String,Object>> contactRecords = new List<Map<String,Object>>();
        List<Contact> contacts = new List<Contact>();

        for (Map<String,Object> row : validRecords) {
            try {
                String pg = (String) row.get('pgid');
                if (pgidToExistingContact.containsKey(pg)) continue;

                Contact c = new Contact();
                c.LastName         = (String) row.get('fullName');
                c.Exchange_Type__c = (String) row.get('exchangeType');
                c.Home_University__c = (String) row.get('homeUniversity');
                c.Visiting_Term__c = (String) row.get('visitingTerm');
                c.RecordTypeId     = studentContactRTId;

                contacts.add(c);
                contactRecords.add(row);

            } catch (Exception ex) {
                errorRows.add(new Map<String,Object>{
                    'StudentId'    => row.get('pgid'),
                    'ContactName'  => row.get('fullName'),
                    'ProgramName'  => row.get('programName'),
                    'errorMessage' => ex.getMessage()
                });
            }
        }

        // Insert Contacts
        List<ProgramEnrollment>     enrollments   = new List<ProgramEnrollment>();
        List<Map<String, Object>>   enrollmentData = new List<Map<String, Object>>();
        // F-02 FIX: parallel list stores row context for PE failure error reporting
        List<Map<String,Object>>    peRowData      = new List<Map<String,Object>>();
        // F-01 FIX: track contacts that need cleanup if term/session lookup fails
        Set<Id>                     orphanedContactIds = new Set<Id>();

        Database.SaveResult[] inserted = Database.insert(contacts, false);
        Integer index = 0;

        for (Database.SaveResult sr : inserted) {
            Map<String,Object> excel = contactRecords[index];

            if (!sr.isSuccess()) {
                errorRows.add(new Map<String,Object>{
                    'StudentId'    => excel.get('pgid'),
                    'ContactName'  => excel.get('fullName'),
                    'ProgramName'  => excel.get('programName'),
                    'errorMessage' => sr.getErrors()[0].getMessage()
                });
            } else {
                ProgramEnrollment pe = new ProgramEnrollment();
                pe.PGID__c    = (String) excel.get('pgid');
                pe.IsActive   = true;
                pe.ContactId  = sr.getId();
                pe.ProgramId  = programNameToId.get((String) excel.get('programName'));
                pe.Status     = 'Exchange Student';

                String exchangeTypeValue = (String) excel.get('exchangeType');
                if (String.isNotBlank(exchangeTypeValue) && exchangeTypeValue.trim().equalsIgnoreCase('incoming')) {
                    pe.Sub_Status__c     = 'Incoming Exchange';
                    pe.Sub_Sub_Status__c = 'Incoming Exchange';
                } else {
                    pe.Sub_Status__c = exchangeTypeValue;
                }

                // Resolve Academic Term
                String termName    = (String) excel.get('academicTerm');
                Id     academicTermId = null;
                if (String.isNotBlank(termName)) {
                    String trimmedTermName = termName.trim();
                    if (academicTermNameToId.containsKey(trimmedTermName)) {
                        academicTermId       = academicTermNameToId.get(trimmedTermName);
                        pe.Academic_Term__c  = academicTermId;
                    } else {
                        // F-01 FIX: mark contact for deletion so no orphan is left
                        orphanedContactIds.add(sr.getId());
                        errorRows.add(new Map<String,Object>{
                            'StudentId'    => excel.get('pgid'),
                            'ContactName'  => excel.get('fullName'),
                            'ProgramName'  => excel.get('programName'),
                            'errorMessage' => 'Academic Term "' + trimmedTermName + '" not found for the selected program'
                        });
                        index++;
                        continue;
                    }
                }

                // Resolve Academic Sessions (comma-separated)
                String sessionName = (String) excel.get('academicSession');
                List<Id> academicSessionIds = new List<Id>();
                if (String.isNotBlank(sessionName)) {
                    Boolean invalidSession = false;
                    for (String token : sessionName.split(',')) {
                        String t = (token == null) ? '' : token.trim();
                        if (String.isNotBlank(t)) {
                            if (academicSessionNameToId.containsKey(t)) {
                                academicSessionIds.add(academicSessionNameToId.get(t));
                            } else {
                                // F-01 FIX: mark contact for deletion so no orphan is left
                                orphanedContactIds.add(sr.getId());
                                errorRows.add(new Map<String,Object>{
                                    'StudentId'    => excel.get('pgid'),
                                    'ContactName'  => excel.get('fullName'),
                                    'ProgramName'  => excel.get('programName'),
                                    'errorMessage' => 'Academic Session "' + t + '" not found'
                                });
                                invalidSession = true;
                                break;
                            }
                        }
                    }
                    if (invalidSession) {
                        index++;
                        continue;
                    }
                }

                enrollments.add(pe);

                // F-02 FIX: store row context so PE failure errors have identifying info
                peRowData.add(new Map<String,Object>{
                    'pgid'        => excel.get('pgid'),
                    'fullName'    => excel.get('fullName'),
                    'programName' => excel.get('programName')
                });

                enrollmentData.add(new Map<String, Object>{
                    'academicTermId'     => academicTermId,
                    'academicSessionIds' => academicSessionIds
                });
            }
            index++;
        }

        // F-01 FIX: Delete contacts whose term/session was not found (prevent orphaned records)
        if (!orphanedContactIds.isEmpty()) {
            Database.delete([SELECT Id FROM Contact WHERE Id IN :orphanedContactIds], false);
        }

        Integer success = 0;
        Integer fail    = errorRows.size();

        List<Database.SaveResult>   peResults        = Database.insert(enrollments, false);
        List<Enrollment_Session__c> enrollmentSessions = new List<Enrollment_Session__c>();
        // F-03 FIX: parallel context list for session failure reporting
        List<Map<String,Object>>    esContextList    = new List<Map<String,Object>>();

        Integer peIndex = 0;
        for (Database.SaveResult sr : peResults) {
            if (sr.isSuccess()) {
                success++;

                Map<String, Object> sessData       = enrollmentData[peIndex];
                Id                  academicTermId  = (Id) sessData.get('academicTermId');
                List<Id>            academicSessionIds = (List<Id>) sessData.get('academicSessionIds');

                if (academicTermId != null && academicSessionIds != null && !academicSessionIds.isEmpty()) {
                    for (Id academicSessionId : academicSessionIds) {
                        if (academicSessionId != null) {
                            Enrollment_Session__c es = new Enrollment_Session__c();
                            es.Program_Enrollment__c = sr.getId();
                            es.Academic_Session__c   = academicSessionId;
                            es.active__c             = true;
                            es.Status__c             = 'Registered';
                            enrollmentSessions.add(es);
                            esContextList.add(peRowData[peIndex]);
                        }
                    }
                }
            } else {
                fail++;
                // F-02 FIX: use stored context — was empty '' fields before
                Map<String,Object> ctx = peRowData[peIndex];
                errorRows.add(new Map<String,Object>{
                    'StudentId'    => ctx.get('pgid'),
                    'ContactName'  => ctx.get('fullName'),
                    'ProgramName'  => ctx.get('programName'),
                    'errorMessage' => sr.getErrors()[0].getMessage()
                });
            }
            peIndex++;
        }

        // F-03 FIX: Check enrollment session results and report failures (was silent before)
        if (!enrollmentSessions.isEmpty()) {
            List<Database.SaveResult> esResults = Database.insert(enrollmentSessions, false);
            for (Integer i = 0; i < esResults.size(); i++) {
                if (!esResults[i].isSuccess()) {
                    Map<String,Object> ctx = esContextList[i];
                    errorRows.add(new Map<String,Object>{
                        'StudentId'    => ctx.get('pgid'),
                        'ContactName'  => ctx.get('fullName'),
                        'ProgramName'  => ctx.get('programName'),
                        'errorMessage' => 'Enrollment Session Error: ' + esResults[i].getErrors()[0].getMessage()
                    });
                }
            }
        }

        String csv = 'StudentId,ContactName,ProgramName,ErrorMessage\n';
        for (Map<String,Object> er : errorRows) {
            csv += '"' + er.get('StudentId') + '","' +
                         er.get('ContactName') + '","' +
                         er.get('ProgramName') + '","' +
                         er.get('errorMessage') + '"\n';
        }

        response.put('successCount', success);
        response.put('failedCount',  fail);
        response.put('errorRows',    errorRows);
        response.put('errorCSV',     csv);

        return response;
    }

    @AuraEnabled(cacheable=true)
    public static List<Program> getIncomingPrograms() {
        return [SELECT Id, Name FROM Program ORDER BY Name];
    }

    @AuraEnabled(cacheable=true)
    public static List<AcademicTerm> getIncomingCohorts(String programId) {
        if (String.isBlank(programId)) return new List<AcademicTerm>();
        return [SELECT Id, Name FROM AcademicTerm WHERE Program__c = :programId ORDER BY Name];
    }

    // F-07 FIX: Renamed from getIncomingTerms — returns AcademicSessions, not Terms
    @AuraEnabled(cacheable=true)
    public static List<AcademicSession> getIncomingSessionsByCohort(String cohortId) {
        if (String.isBlank(cohortId)) return new List<AcademicSession>();
        return [SELECT Id, Name, Location__c FROM AcademicSession WHERE AcademicTermId = :cohortId ORDER BY Name];
    }

    @AuraEnabled
    public static Map<String, Object> processIncomingExchangeUpload(
            List<Map<String, Object>> records,
            String progId,
            String cohortId,
            String termId) {

        Map<String, Object> response = new Map<String, Object>{
            'successCount' => 0,
            'failedCount'  => 0,
            'errorRows'    => new List<Map<String,Object>>(),
            'errorCSV'     => ''
        };

        if (records == null || records.isEmpty()) return response;

        // Validate selected Program once for the whole upload; rows should never insert
        // with a null/invalid ProgramId.
        if (String.isBlank(progId)) {
            throw new AuraHandledException('Please select a Program before uploading.');
        }
        Program selectedProgram;
        try {
            selectedProgram = [SELECT Id, Program_Code__c FROM Program WHERE Id = :progId LIMIT 1];
        } catch (Exception ex) {
            throw new AuraHandledException('Selected Program is invalid. Please re-select Program and try again.');
        }
        String selectedProgramCode = selectedProgram.Program_Code__c;

        // F-06 FIX: Upfront row limit guard to prevent governor limit violations (was unbounded)
        if (records.size() > 150) {
            throw new AuraHandledException('Maximum 150 rows per upload. Please split your file into smaller batches.');
        }

        List<Map<String,Object>> errorRows = new List<Map<String,Object>>();

        Id studentContactRTId = Schema.SObjectType.Contact
            .getRecordTypeInfosByName().get('Student').getRecordTypeId();

        Set<String> emailSet   = new Set<String>();
        Set<String> schoolCodes = new Set<String>();
        Set<String> campuses    = new Set<String>();

        for (Map<String,Object> r : records) {
            String email = (String) r.get('email');
            if (String.isNotBlank(email)) emailSet.add(email.trim());

            String sc = (String) r.get('schoolCode');
            if (String.isNotBlank(sc)) schoolCodes.add(sc.trim());

            String camp = (String) r.get('campus');
            if (String.isNotBlank(camp)) campuses.add(camp.trim());
        }

        Map<String, Contact> existingContacts = new Map<String, Contact>();
        for (Contact c : [SELECT Id, Email FROM Contact WHERE Email IN :emailSet]) {
            if (String.isNotBlank(c.Email)) {
                existingContacts.put(c.Email.toLowerCase(), c);
            }
        }

        Map<String, Id> schoolCodeToAccountId = new Map<String, Id>();
        for (Account a : [
            SELECT Id, School_Code__c FROM Account
            WHERE RecordType.DeveloperName = 'University_Department' AND School_Code__c IN :schoolCodes
        ]) {
            if (String.isNotBlank(a.School_Code__c)) {
                schoolCodeToAccountId.put(a.School_Code__c.trim().toLowerCase(), a.Id);
            }
        }

        Map<String, Id> campusToLocationId = new Map<String, Id>();
        for (Schema.Location loc : [SELECT Id, Name FROM Location WHERE Name IN :campuses]) {
            if (String.isNotBlank(loc.Name)) {
                campusToLocationId.put(loc.Name.trim().toLowerCase(), loc.Id);
            }
        }

        // Accept session names from LWC and match by Name + Location
        Set<String> sessionNameSet = new Set<String>();
        if (String.isNotBlank(termId)) {
            for (String s : termId.split(',')) {
                String trimmed = s.trim();
                if (String.isNotBlank(trimmed)) {
                    sessionNameSet.add(trimmed);
                }
            }
        }

        Map<Id, List<Id>> locationIdToSessionIds = new Map<Id, List<Id>>();
        List<Id> globalSessionIds = new List<Id>();

        if (!sessionNameSet.isEmpty()) {
            for (AcademicSession sess : [SELECT Id, Name, Location__c FROM AcademicSession WHERE Name IN :sessionNameSet AND AcademicTermId = :cohortId]) {
                if (sess.Location__c != null) {
                    if (!locationIdToSessionIds.containsKey(sess.Location__c)) {
                        locationIdToSessionIds.put(sess.Location__c, new List<Id>());
                    }
                    locationIdToSessionIds.get(sess.Location__c).add(sess.Id);
                } else {
                    globalSessionIds.add(sess.Id);
                }
            }
        }

        Integer success = 0;
        Integer fail    = 0;

        // F-05 FIX: Flag incoming upload context — suppresses probation/stamp handlers in trigger
        ProgramEnrollmentHandler.isIncomingUpload = true;

        for (Map<String,Object> row : records) {
            ProgramEnrollmentHandler.hasRun = false;
            Savepoint sp = Database.setSavepoint();
            try {
                String email             = (String) row.get('email');
                String homeContactName   = (String) row.get('homeInstContactName');
                String homeContactEmail  = (String) row.get('homeInstContactEmail');
                String schoolCode        = (String) row.get('schoolCode');
                String campus            = (String) row.get('campus');
                String genderLabel       = (String) row.get('gender');
                String checkInDateStr    = (String) row.get('checkInDate');
                String checkOutDateStr   = (String) row.get('checkOutDate');
                String accommodationType = (String) row.get('accommodationType');

                Date checkInDate = null;
                if (String.isNotBlank(checkInDateStr)) {
                    try { checkInDate = Date.valueOf(checkInDateStr.trim()); } catch(Exception e) {}
                }

                Date checkOutDate = null;
                if (String.isNotBlank(checkOutDateStr)) {
                    try { checkOutDate = Date.valueOf(checkOutDateStr.trim()); } catch(Exception e) {}
                }

                // F-06 FIX: Use AuraHandledException for business validation (not CalloutException)
                if (String.isBlank(homeContactName) || String.isBlank(homeContactEmail)) {
                    throw new AuraHandledException('Home Institution Contact Name and Email are required (V-INC-08)');
                }

                if (String.isNotBlank(email) && existingContacts.containsKey(email.trim().toLowerCase())) {
                    throw new AuraHandledException('Duplicate email — contact already exists');
                }

                Id accountId = null;
                if (String.isNotBlank(schoolCode)) {
                    String cleanCode = schoolCode.trim().toLowerCase();
                    if (schoolCodeToAccountId.containsKey(cleanCode)) {
                        accountId = schoolCodeToAccountId.get(cleanCode);
                    }
                }

                Id locationId = null;
                if (String.isNotBlank(campus)) {
                    String cleanCamp = campus.trim().toLowerCase();
                    if (campusToLocationId.containsKey(cleanCamp)) {
                        locationId = campusToLocationId.get(cleanCamp);
                    }
                }

                Contact c = new Contact();
                c.FirstName                        = (String) row.get('firstName');
                c.LastName                         = (String) row.get('lastName');
                if (String.isBlank(c.LastName))  throw new AuraHandledException('Last Name is required');
                if (String.isBlank(email))        throw new AuraHandledException('Email is required');
                c.Email                            = email;
                c.RecordTypeId                     = studentContactRTId;
                c.Exchange_Type__c                 = 'Incoming';
                c.Home_Institution_Contact_Name__c  = homeContactName;
                c.Home_Institution_Contact_Email__c = homeContactEmail;
                c.AccountId                        = accountId;
                applyIncomingGenderIdentity(c, genderLabel);
                if (String.isNotBlank(selectedProgramCode)) {
                    c.Current_Program__c = selectedProgramCode;
                }

                insert c;

                ProgramEnrollment pe = new ProgramEnrollment();
                pe.ContactId              = c.Id;
                pe.ProgramId              = progId;
                pe.Academic_Term__c       = cohortId;
                pe.Status                 = 'Exchange Student';
                pe.Sub_Status__c          = 'Incoming Exchange';
                pe.Sub_Sub_Status__c      = 'Incoming Exchange';
                pe.Registro_Sync_Status__c = false;
                pe.Location__c            = locationId;
                pe.Accomodation_Type__c   = accommodationType;
                pe.Exchange_School__c     = accountId;
                pe.Check_In_Date__c       = checkInDate;
                pe.Check_Out_Date__c      = checkOutDate;
				pe.IsActive 			  = true;
                insert pe;

                // Match session by student campus location
                if (!sessionNameSet.isEmpty()) {
                    List<Enrollment_Session__c> esList = new List<Enrollment_Session__c>();

                    if (locationId != null && locationIdToSessionIds.containsKey(locationId)) {
                        for (Id sId : locationIdToSessionIds.get(locationId)) {
                            Enrollment_Session__c es = new Enrollment_Session__c();
                            es.Program_Enrollment__c = pe.Id;
                            es.Academic_Session__c   = sId;
                            es.active__c             = true;
                            es.Status__c             = 'Registered';
                            esList.add(es);
                        }
                    }
                    
                    if (esList.isEmpty()) {
                        throw new AuraHandledException(
                            'For campus "' +
                            (String.isNotBlank(campus) ? campus : 'unspecified') + 
                            '" there are no Academic Sessions available'
                        );
                    }
                    insert esList;
                }

                success++;

            } catch (Exception ex) {
                Database.rollback(sp);
                fail++;
                errorRows.add(new Map<String,Object>{
                    'Email'        => row.get('email'),
                    'FullName'     => row.get('lastName'),
                    'errorMessage' => ex.getMessage()
                });
            }
        }

        // F-05 FIX: Clear the upload flag after all rows are processed
        ProgramEnrollmentHandler.isIncomingUpload = false;

        String csv = 'Email,FullName,ErrorMessage\n';
        for (Map<String,Object> er : errorRows) {
            csv += '"' + er.get('Email') + '","' +
                         er.get('FullName') + '","' +
                         er.get('errorMessage') + '"\n';
        }

        response.put('successCount', success);
        response.put('failedCount',  fail);
        response.put('errorRows',    errorRows);
        response.put('errorCSV',     csv);

        return response;
    }

    private static void applyIncomingGenderIdentity(Contact c, String genderLabel) {
        if (String.isBlank(genderLabel)) return;

        String normalized = genderLabel.trim().toLowerCase();
        Integer codedValue;

        if (normalized == 'male') {
            codedValue = 1;
        } else if (normalized == 'female') {
            codedValue = 2;
        } else if (normalized == 'other') {
            codedValue = 0;
        } else {
            return;
        }

        Map<String, Schema.SObjectField> contactFields = Contact.SObjectType.getDescribe().fields.getMap();
        if (contactFields.containsKey('SAP_Gender_Code__c')) {
            Schema.DisplayType fieldType = contactFields.get('SAP_Gender_Code__c').getDescribe().getType();
            if (fieldType == Schema.DisplayType.Integer
                || fieldType == Schema.DisplayType.Double
                || fieldType == Schema.DisplayType.Currency
                || fieldType == Schema.DisplayType.Percent) {
                c.put('SAP_Gender_Code__c', Decimal.valueOf(String.valueOf(codedValue)));
            } else {
                c.put('SAP_Gender_Code__c', String.valueOf(codedValue));
            }
        }
    }
}