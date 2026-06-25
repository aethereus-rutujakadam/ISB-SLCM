public without sharing class PGIDGeneratorService{

    public static void generatePGIDs(List<ProgramEnrollment> enrollments, Set<Id> programEnrollmentIds) {
        try {
            // F-08 FIX: Populate enrollmentIds from the parameter (was always empty — dead code)
            List<Id> enrollmentIds = new List<Id>(programEnrollmentIds);           
           
            // Re-query with all required fields, only PEs without a PGID
            List<ProgramEnrollment> eligibleEnrollments = [
                SELECT Id,
                       PGID__c,
                       Academic_Year__c,
                       Academic_Year__r.Name,
                       Academic_Term__c,
                       Academic_Term__r.Intake_No__c,
                       Academic_Term__r.PG_ID_sequence_start__c,
                       Program.Name,
                       Program.Program_Code__c,
                       ContactId,
                       Contact.FirstName,
                       Contact.LastName,
                       Contact.New_Admit_Email__c
                FROM ProgramEnrollment
                WHERE Id IN :programEnrollmentIds
                AND PGID__c = NULL
                AND Academic_Year__c != NULL
                AND Academic_Term__c != NULL
                AND Academic_Term__r.Intake_No__c != NULL
                AND Program.Program_Code__c != NULL
            ];

            if (eligibleEnrollments.isEmpty()) return;

            // Collect term IDs for duplicate email check
            Set<Id> termIds = new Set<Id>();
            for (ProgramEnrollment pe : eligibleEnrollments) {
                if (pe.Academic_Term__c != null) termIds.add(pe.Academic_Term__c);
            }

            // Find existing emails in same terms (for duplicate check)
            // F-08 FIX: enrollmentIds now populated so current batch is correctly excluded
            List<ProgramEnrollment> existing = [
                SELECT Id,
                       Academic_Term__c,
                       Program.Name,
                       Contact.FirstName,
                       Contact.LastName,
                       Contact.New_Admit_Email__c
                FROM ProgramEnrollment
                WHERE Contact.New_Admit_Email__c != NULL
                AND Academic_Term__c IN :termIds
                AND Id NOT IN :enrollmentIds
            ];

            // Detect duplicates within current batch
            Map<String, Integer> flowDupCount = new Map<String, Integer>();
            for (ProgramEnrollment pe : eligibleEnrollments) {
                String key =
                      (pe.Contact.FirstName != null ? pe.Contact.FirstName.trim().toLowerCase() : '')
                    + '|' +
                      (pe.Contact.LastName  != null ? pe.Contact.LastName.trim().toLowerCase()  : '')
                    + '|' +
                      (pe.Program.Name      != null ? pe.Program.Name.trim().toLowerCase()      : '');

                flowDupCount.put(key, flowDupCount.containsKey(key) ? flowDupCount.get(key) + 1 : 1);
            }

            // Fetch Program Code Mappings from Custom Metadata
            List<Program_Code_Mapping__mdt> codeMappings = [
                SELECT MasterLabel, Program_Code__c FROM Program_Code_Mapping__mdt
            ];
            Map<String, String> programCodeMap = new Map<String, String>();
            for (Program_Code_Mapping__mdt mapping : codeMappings) {
                programCodeMap.put(mapping.MasterLabel.toLowerCase(), mapping.Program_Code__c);
            }

            Map<Id, AcademicTerm>     termsToUpdateMap    = new Map<Id, AcademicTerm>();
            List<ProgramEnrollment>   enrollmentsToUpdate  = new List<ProgramEnrollment>();
            Map<Id, Contact>          contactsToUpdateMap  = new Map<Id, Contact>();
            List<String>              exchangeUserData     = new List<String>();

            for (ProgramEnrollment pe : eligibleEnrollments) {

                // PART 1: PG ID Generation

                String progCode = '0';
                String rawCode  = null;
                String progCodeKey = pe.Program.Program_Code__c != null
                    ? pe.Program.Program_Code__c.trim().toLowerCase() : '';

                if (programCodeMap.containsKey(progCodeKey) && programCodeMap.get(progCodeKey) != null) {
                    rawCode = programCodeMap.get(progCodeKey).trim();
                } else if (pe.Program.Program_Code__c != null) {
                    rawCode = pe.Program.Program_Code__c.trim();
                }

                if (rawCode != null) {
                    try {
                        Integer codeNum = Integer.valueOf(rawCode);
                        progCode = String.valueOf(codeNum);
                    } catch (Exception e) {
                        progCode = rawCode;
                    }
                }

                // "2024-2025" → "25"
                String yearCode = '00';
                String year4    = '';
                if (pe.Academic_Year__r != null && pe.Academic_Year__r.Name != null
                        && pe.Academic_Year__r.Name.contains('-')) {
                    year4    = pe.Academic_Year__r.Name.split('-')[1];
                    yearCode = year4.substring(year4.length() - 2);
                }

                String intakeCode = (pe.Academic_Term__r.Intake_No__c != null)
                    ? String.valueOf(Integer.valueOf(pe.Academic_Term__r.Intake_No__c))
                    : '1';

                Integer currentSequence;
                if (termsToUpdateMap.containsKey(pe.Academic_Term__c)) {
                    currentSequence = Integer.valueOf(
                        termsToUpdateMap.get(pe.Academic_Term__c).PG_ID_sequence_start__c
                    );
                } else {
                    currentSequence = (pe.Academic_Term__r.PG_ID_sequence_start__c != null)
                        ? Integer.valueOf(pe.Academic_Term__r.PG_ID_sequence_start__c)
                        : 0;
                }

                Integer sequenceNumber = currentSequence + 1;
                String  nextSeqText    = String.valueOf(sequenceNumber).leftPad(3, '0');

                if (termsToUpdateMap.containsKey(pe.Academic_Term__c)) {
                    termsToUpdateMap.get(pe.Academic_Term__c).PG_ID_sequence_start__c = sequenceNumber;
                } else {
                    AcademicTerm termToUpdate = new AcademicTerm();
                    termToUpdate.Id                       = pe.Academic_Term__c;
                    termToUpdate.PG_ID_sequence_start__c  = sequenceNumber;
                    termsToUpdateMap.put(pe.Academic_Term__c, termToUpdate);
                }

                // Format: [ProgCode 1] + [Year 2] + [Intake] + '9' + [Sequence 3]
                String pgId    = progCode + yearCode + intakeCode + '9' + nextSeqText;
                pe.PGID__c     = pgId;
                enrollmentsToUpdate.add(pe);
                if (pe.ContactId != null) {
                    exchangeUserData.add(pe.ContactId + '|' + pgId);
                }
				System.debug('exchangeUserData'+exchangeUserData);
                // PART 2: Email Generation

                if (pe.Contact.New_Admit_Email__c != null) continue;

                String first = pe.Contact.FirstName != null ? pe.Contact.FirstName.trim() : '';
                String last  = pe.Contact.LastName  != null ? pe.Contact.LastName.trim()  : '';

                Boolean invalidLastName = false;
                if (String.isBlank(last) || last.contains('.')) {
                    invalidLastName = true;
                    last = '';
                } else if (!Pattern.matches('^[a-zA-Z ]*$', last)) {
                    invalidLastName = true;
                    last = '';
                }

                String program = (pe.Program.Name == 'PGPpro')
                    ? pe.Program.Name.toUpperCase()
                    : pe.Program.Name;

                String emailProgramStr = pe.Program.Program_Code__c != null
                    ? pe.Program.Program_Code__c : program;

                Boolean duplicate = false;
                String  flowKey   = first.toLowerCase() + '|' + last.toLowerCase() + '|' + program.toLowerCase();
                if (flowDupCount.containsKey(flowKey) && flowDupCount.get(flowKey) > 1) {
                    duplicate = true;
                }
                for (ProgramEnrollment ex : existing) {
                    if (ex.Academic_Term__c == pe.Academic_Term__c &&
                        ex.Program.Name      == pe.Program.Name    &&
                        ex.Contact.FirstName == first              &&
                        ex.Contact.LastName  == last) {
                        duplicate = true;
                        break;
                    }
                }

                List<String> tokens  = first.replaceAll('\\s+', ' ').trim().split(' ');
                String leftSeg  = '';
                String rightSeg = '';

                if (tokens.size() >= 3) {
                    leftSeg = (tokens[0] + tokens[1]).replace(' ', '');
                    String remaining = '';
                    for (Integer i = 2; i < tokens.size(); i++) {
                        remaining += tokens[i];
                    }
                    rightSeg = (remaining + last).replaceAll('\\s+', '');
                } else {
                    leftSeg  = first.replaceAll('\\s+', '');
                    rightSeg = last.replaceAll('\\s+', '');
                }

                String sapLast4 = ('0000' + pgId).right(4);
                if (duplicate || invalidLastName) {
                    rightSeg = rightSeg + sapLast4;
                }

                String finalEmail = leftSeg + '_' + rightSeg + '_' + emailProgramStr + year4 + '@isb.edu';

                if (pe.ContactId != null) {
                    Contact contactToUpdate = new Contact(Id = pe.ContactId);
                    contactToUpdate.New_Admit_Email__c = finalEmail;
                    contactsToUpdateMap.put(pe.ContactId, contactToUpdate);
                }
            }

            if (!enrollmentsToUpdate.isEmpty()) {
                update enrollmentsToUpdate;
            }
            if (!termsToUpdateMap.isEmpty()) {
                update termsToUpdateMap.values();
            }
            if (!contactsToUpdateMap.isEmpty()) {
                update contactsToUpdateMap.values();
            }
			System.debug('exchangeUserData227'+exchangeUserData);
            // F-09 FIX: Delegate to InternationalExchangeUserCreation (single @future, sends welcome email)
            if (!exchangeUserData.isEmpty() && !System.isFuture() && !System.isBatch()) {
                // Get Permission Sets       
            
                InternationalExchangeUserCreation.createExchangeUsersAsync(exchangeUserData, true);
            }

        } catch (Exception e) {
            System.debug('PGIDGeneratorService.generatePGIDs Error: ' + e.getMessage());
        }
    }
}