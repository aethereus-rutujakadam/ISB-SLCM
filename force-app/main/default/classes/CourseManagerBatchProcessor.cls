/**
 * @description Batch processor for Course Manager records.
 * Processes Excel rows, matches CourseOfferings, creates course_managers__c records,
 * and logs errors to Error_Handling__c.
 * 
 * Batch size: 100 (to accommodate downstream trigger processing)
 */
public without sharing class CourseManagerBatchProcessor implements Database.Batchable<CourseManagerExcelParser.ExcelRow>, Database.Stateful {
    
    private List<CourseManagerExcelParser.ExcelRow> excelRows;
    
    // Stateful counters across batches
    public Integer successCount = 0;
    public Integer errorCount = 0;
    
    /**
     * @description Constructor
     * @param excelRows List of validated Excel rows to process
     */
    public CourseManagerBatchProcessor(List<CourseManagerExcelParser.ExcelRow> excelRows) {
        this.excelRows = excelRows;
    }

    /**
     * @description Start method - returns iterable of Excel rows
     */
    public Iterable<CourseManagerExcelParser.ExcelRow> start(Database.BatchableContext bc) {
        return excelRows;
    }

    /**
     * @description Execute method - core processing logic
     */
    public void execute(Database.BatchableContext bc, List<CourseManagerExcelParser.ExcelRow> scope) {
        
        List<course_managers__c> courseManagersToInsert = new List<course_managers__c>();
        Map<String, List<Integer>> errorsByReason = new Map<String, List<Integer>>(); // Consolidate errors by reason
        Map<String, List<Integer>> warningsByReason = new Map<String, List<Integer>>(); // Consolidate warnings by reason
        Map<String, Integer> dmlErrorCounts = new Map<String, Integer>(); // Track DML error counts by message
        
        try {
            // Step 1: Collect unique values from batch
            Set<String> userNames = new Set<String>();
            Set<String> courseNames = new Set<String>();
            Set<String> locationNames = new Set<String>();
            
            for (CourseManagerExcelParser.ExcelRow row : scope) {
                userNames.add(row.owner.toLowerCase());
                courseNames.add(row.courses.toLowerCase());
                locationNames.add(row.location.toLowerCase());
            }

            // Step 2: Query Users (by Name, IsActive = true only)
            Map<String, User> userMap = new Map<String, User>();
            for (User u : [SELECT Id, Name, IsActive FROM User WHERE IsActive = true]) {
                userMap.put(u.Name.toLowerCase(), u);
            }

            // Step 3: Query LearningCourses (by Name)
            Map<String, LearningCourse> courseMap = new Map<String, LearningCourse>();
            for (LearningCourse lc : [SELECT Id, Name FROM LearningCourse]) {
                courseMap.put(lc.Name.toLowerCase(), lc);
            }

            // Step 4: Query Locations (by Name)
            Map<String, SObject> locationMap = new Map<String, SObject>();
            for (Schema.Location loc : [SELECT Id, Name FROM Location]) {
                locationMap.put(((String)loc.Name).toLowerCase(), loc);
            }

            // Step 5: Build maps for Year/Term/Session names to IDs BEFORE building offering query filters
            Map<String, Id> academicYearNameToId = new Map<String, Id>();
            for (AcademicYear yearRec : [SELECT Id, Name FROM AcademicYear]) {
                if (!String.isBlank(yearRec.Name)) {
                    academicYearNameToId.put(yearRec.Name.toLowerCase(), yearRec.Id);
                }
            }

            Map<String, Id> academicTermNameToId = new Map<String, Id>();
            for (AcademicTerm termRec : [SELECT Id, Name FROM AcademicTerm]) {
                if (!String.isBlank(termRec.Name)) {
                    academicTermNameToId.put(termRec.Name.toLowerCase(), termRec.Id);
                }
            }

            Map<String, Id> academicSessionNameToId = new Map<String, Id>();
            for (AcademicSession sessionRec : [SELECT Id, Name FROM AcademicSession]) {
                if (!String.isBlank(sessionRec.Name)) {
                    academicSessionNameToId.put(sessionRec.Name.toLowerCase(), sessionRec.Id);
                }
            }

            // Step 6: Collect all unique values from Excel rows for multi-dimensional filtering
            Set<Id> learningCourseIds = new Set<Id>();
            Set<Id> locationIds = new Set<Id>();
            Set<String> courseCodesFromExcel = new Set<String>();
            Set<String> courseTypesFromExcel = new Set<String>();
            Set<Id> academicYearIds = new Set<Id>();
            Set<Id> academicTermIds = new Set<Id>();
            Set<Id> academicSessionIds = new Set<Id>();
            
            for (LearningCourse lc : courseMap.values()) {
                learningCourseIds.add(lc.Id);
            }
            for (SObject locObj : locationMap.values()) {
                locationIds.add((Id)locObj.get('Id'));
            }
            
            // Build a set of all Excel row values for filtering
            for (CourseManagerExcelParser.ExcelRow row : scope) {
                if (!String.isBlank(row.courseCode)) {
                    courseCodesFromExcel.add(row.courseCode.toLowerCase());
                }
                if (!String.isBlank(row.courseType)) {
                    courseTypesFromExcel.add(row.courseType.toLowerCase());
                }
                Id yearId = academicYearNameToId.get(row.academicYear.toLowerCase());
                if (yearId != null) {
                    academicYearIds.add(yearId);
                }
                Id termId = academicTermNameToId.get(row.academicTerm.toLowerCase());
                if (termId != null) {
                    academicTermIds.add(termId);
                }
                Id sessionId = academicSessionNameToId.get(row.academicSession.toLowerCase());
                if (sessionId != null) {
                    academicSessionIds.add(sessionId);
                }
            }

            // Step 7: Query CourseOfferings with ALL criteria in AND condition
            // This ensures we only fetch CourseOfferings that match ALL header fields
            List<CourseOffering> courseOfferings = new List<CourseOffering>();
            if (!learningCourseIds.isEmpty() && !locationIds.isEmpty() && 
                !courseCodesFromExcel.isEmpty() && !courseTypesFromExcel.isEmpty() &&
                !academicYearIds.isEmpty() && !academicTermIds.isEmpty() && !academicSessionIds.isEmpty()) {
                
                courseOfferings = [
                    SELECT Id, Name, LearningCourseId, LearningCourse.Name, 
                           Location__c, Location__r.Name, Course_Type__c, Course_Code__c,
                           Academic_Year__c, Academic_Term__c, AcademicSessionId
                    FROM CourseOffering
                    WHERE LearningCourseId IN :learningCourseIds
                      AND Location__c IN :locationIds
                      AND Course_Code__c IN :courseCodesFromExcel
                      AND Course_Type__c IN :courseTypesFromExcel
                      AND Academic_Year__c IN :academicYearIds
                      AND Academic_Term__c IN :academicTermIds
                      AND AcademicSessionId IN :academicSessionIds
                ];
            }

            // Step 8: Build Map for CourseOffering lookup
            // Key format: "coursename|locationname|coursecode|coursetype|academicYearId|academicTermId|academicSessionId" (all lowercase)
            Map<String, List<CourseOffering>> offeringMap = new Map<String, List<CourseOffering>>();
            
            for (CourseOffering co : courseOfferings) {
                String courseName = co.LearningCourse?.Name != null ? co.LearningCourse.Name.toLowerCase() : '';
                String locationName = co.Location__r?.Name != null ? co.Location__r.Name.toLowerCase() : '';
                String courseCode = co.Course_Code__c != null ? co.Course_Code__c.toLowerCase() : '';
                String courseType = co.Course_Type__c != null ? co.Course_Type__c.toLowerCase() : '';
                String academicYearId = co.Academic_Year__c != null ? String.valueOf(co.Academic_Year__c).toLowerCase() : '';
                String academicTermId = co.Academic_Term__c != null ? String.valueOf(co.Academic_Term__c).toLowerCase() : '';
                String academicSessionId = co.AcademicSessionId != null ? String.valueOf(co.AcademicSessionId).toLowerCase() : '';
                
                String key = courseName + '|' + locationName + '|' + courseCode + '|' + courseType + '|' + academicYearId + '|' + academicTermId + '|' + academicSessionId;
                
                if (!offeringMap.containsKey(key)) {
                    offeringMap.put(key, new List<CourseOffering>());
                }
                offeringMap.get(key).add(co);
            }

            // Step 9: Query existing course_managers__c for duplicate detection
            // Business rule: only one record per Course Offering + Role
            Set<Id> allOfferingIds = new Set<Id>();

            for (List<CourseOffering> coList : offeringMap.values()) {
                for (CourseOffering co : coList) {
                    allOfferingIds.add(co.Id);
                }
            }

            // Query existing course managers
            Set<String> existingOfferingRoleKeys = new Set<String>();
            if (!allOfferingIds.isEmpty()) {
                for (course_managers__c cm : [
                    SELECT Course_Offering__c, Role__c
                    FROM course_managers__c
                    WHERE Course_Offering__c IN :allOfferingIds
                ]) {
                    String key = String.valueOf(cm.Course_Offering__c) + '|' + 
                                String.valueOf(cm.Role__c).toLowerCase();
                    existingOfferingRoleKeys.add(key);
                }
            }

            // Step 10: Process each Excel row
            Set<String> batchOfferingRoleKeys = new Set<String>(); // Within-batch duplicate tracking
            
            for (CourseManagerExcelParser.ExcelRow row : scope) {
                
                // Validate that all required fields are not blank
                List<String> blankFields = new List<String>();
                if (String.isBlank(row.owner)) blankFields.add('Owner');
                if (String.isBlank(row.courses)) blankFields.add('Courses');
                if (String.isBlank(row.location)) blankFields.add('Location');
                if (String.isBlank(row.courseCode)) blankFields.add('Course Code');
                if (String.isBlank(row.courseType)) blankFields.add('Course Type');
                if (String.isBlank(row.academicYear)) blankFields.add('Academic Year');
                if (String.isBlank(row.academicTerm)) blankFields.add('Academic Term');
                if (String.isBlank(row.academicSession)) blankFields.add('Academic Session');
                if (String.isBlank(row.roles)) blankFields.add('Roles');
                
                if (!blankFields.isEmpty()) {
                    String blankFieldList = String.join(blankFields, ', ');
                    addErrorToMap(errorsByReason, row.rowNumber, 'Required field(s) cannot be blank: ' + blankFieldList);
                    continue;
                }
                
                // Validate User exists and is active
                User matchedUser = userMap.get(row.owner.toLowerCase());
                if (matchedUser == null) {
                    addErrorToMap(errorsByReason, row.rowNumber, 'User not found or inactive: ' + row.owner);
                    continue;
                }

                // Validate LearningCourse exists
                LearningCourse matchedCourse = courseMap.get(row.courses.toLowerCase());
                if (matchedCourse == null) {
                    addErrorToMap(errorsByReason, row.rowNumber, 'Learning Course not found: ' + row.courses);
                    continue;
                }

                // Validate Location exists
                SObject matchedLocation = locationMap.get(row.location.toLowerCase());
                if (matchedLocation == null) {
                    addErrorToMap(errorsByReason, row.rowNumber, 'Location not found: ' + row.location);
                    continue;
                }

                // Validate and normalize Role
                String normalizedRole = normalizeRole(row.roles);
                if (normalizedRole == null) {
                    addErrorToMap(errorsByReason, row.rowNumber, 'Invalid Role value: ' + row.roles + ' (must be Manager, Associate, or Delivery Manager)');
                    continue;
                }

                Id rowAcademicYearId = academicYearNameToId.get(row.academicYear.toLowerCase());
                if (rowAcademicYearId == null) {
                    addErrorToMap(errorsByReason, row.rowNumber, 'Academic Year not found: ' + row.academicYear);
                    continue;
                }

                Id rowAcademicTermId = academicTermNameToId.get(row.academicTerm.toLowerCase());
                if (rowAcademicTermId == null) {
                    addErrorToMap(errorsByReason, row.rowNumber, 'Academic Term not found: ' + row.academicTerm);
                    continue;
                }

                Id rowAcademicSessionId = academicSessionNameToId.get(row.academicSession.toLowerCase());
                if (rowAcademicSessionId == null) {
                    addErrorToMap(errorsByReason, row.rowNumber, 'Academic Session not found: ' + row.academicSession);
                    continue;
                }

                // Match CourseOfferings using composite key (includes CourseCode for precise matching)
                String offeringKey = row.courses.toLowerCase() + '|' + 
                                    row.location.toLowerCase() + '|' + 
                                    row.courseCode.toLowerCase() + '|' + 
                                    row.courseType.toLowerCase() + '|' +
                                    String.valueOf(rowAcademicYearId).toLowerCase() + '|' +
                                    String.valueOf(rowAcademicTermId).toLowerCase() + '|' +
                                    String.valueOf(rowAcademicSessionId).toLowerCase();
                
                List<CourseOffering> matchedOfferings = offeringMap.get(offeringKey);
                
                if (matchedOfferings == null || matchedOfferings.isEmpty()) {
                    String reason = 'Condition 1 - Course Offering not found for Course: ' + row.courses + 
                        ', Course Code: ' + row.courseCode + 
                        ', Location: ' + row.location + 
                        ', Course Type: ' + row.courseType +
                        ', Academic Year: ' + row.academicYear +
                        ', Academic Term: ' + row.academicTerm +
                        ', Academic Session: ' + row.academicSession;
                    addWarningToMap(warningsByReason, row.rowNumber, reason);
                    continue;
                }

                // Create course_managers__c for EACH matched CourseOffering
                for (CourseOffering co : matchedOfferings) {
                    
                    // Check for existing duplicate by Course Offering + Role
                    String offeringRoleKey = String.valueOf(co.Id) + '|' + normalizedRole.toLowerCase();
                    
                    if (existingOfferingRoleKeys.contains(offeringRoleKey)) {
                        // Condition 3 - Role already exists for this Course Offering, skip and log warning
                        String reason = 'Condition 3 - Course Offering found but ' + normalizedRole + ' role already exists for Course: ' + row.courses + 
                            ', Location: ' + row.location + 
                            ', Course Code: ' + row.courseCode +
                            ', User: ' + row.owner;
                        addWarningToMap(warningsByReason, row.rowNumber, reason);
                        continue;
                    }
                    
                    if (batchOfferingRoleKeys.contains(offeringRoleKey)) {
                        // Condition 2 - Already processed in this batch, skip and log warning
                        String reason = 'Condition 2 - Course Offering found but ' + normalizedRole + ' role already assigned in current batch for Course: ' + row.courses + 
                            ', Location: ' + row.location + 
                            ', Course Code: ' + row.courseCode +
                            ', User: ' + row.owner;
                        addWarningToMap(warningsByReason, row.rowNumber, reason);
                        continue;
                    }
                    
                    batchOfferingRoleKeys.add(offeringRoleKey);

                    // Create course_managers__c record
                    course_managers__c cm = new course_managers__c();
                    cm.User__c = matchedUser.Id;
                    cm.Course_Offering__c = co.Id;
                    cm.Courses__c = co.LearningCourseId; // Populate from CourseOffering
                    cm.Role__c = normalizedRole;
                    cm.OwnerId = matchedUser.Id; // Set owner to the User
                    
                    courseManagersToInsert.add(cm);
                }
            }

            // Step 11: Insert course_managers__c with partial success
            if (!courseManagersToInsert.isEmpty()) {
                Database.SaveResult[] saveResults = Database.insert(courseManagersToInsert, false);
                
                for (Integer i = 0; i < saveResults.size(); i++) {
                    if (saveResults[i].isSuccess()) {
                        successCount++;
                    } else {
                        errorCount++;
                        // Track DML error by message
                        for (Database.Error err : saveResults[i].getErrors()) {
                            String errorMsg = 'DML Error: ' + err.getMessage() + ' (Fields: ' + String.join(err.getFields(), ', ') + ')';
                            dmlErrorCounts.put(errorMsg, (dmlErrorCounts.get(errorMsg) != null ? dmlErrorCounts.get(errorMsg) : 0) + 1);
                        }
                    }
                }
            }

            // Step 12: Convert consolidated errors and warnings to Error_Handling__c records
            List<Error_Handling__c> errorRecords = new List<Error_Handling__c>();
            
            // Add validation errors
            for (String reason : errorsByReason.keySet()) {
                List<Integer> rowNumbers = errorsByReason.get(reason);
                String rowNumbersStr = String.join(rowNumbers, ', ');
                
                Error_Handling__c errorRec = new Error_Handling__c();
                errorRec.Component_Name__c = 'Course Managers Upload';
                errorRec.Error_message__c = 'Error (Row numbers: ' + rowNumbersStr + '):\n' + reason;
                errorRecords.add(errorRec);
            }
            
            // Add warnings as error_handling records
            for (String reason : warningsByReason.keySet()) {
                List<Integer> rowNumbers = warningsByReason.get(reason);
                String rowNumbersStr = String.join(rowNumbers, ', ');
                
                Error_Handling__c errorRec = new Error_Handling__c();
                errorRec.Component_Name__c = 'Course Managers Upload';
                errorRec.Error_message__c = 'Warning (Row numbers: ' + rowNumbersStr + '):\n' + reason;
                errorRecords.add(errorRec);
            }
            
            // Add DML errors with count
            for (String dmlError : dmlErrorCounts.keySet()) {
                Integer count = dmlErrorCounts.get(dmlError);
                Error_Handling__c errorRec = new Error_Handling__c();
                errorRec.Component_Name__c = 'Course Managers Upload';
                errorRec.Error_message__c = dmlError + ' (Occurred ' + count + ' time(s))';
                errorRecords.add(errorRec);
            }
            
            if (!errorRecords.isEmpty()) {
                Database.insert(errorRecords, false); // Allow partial success for error records too
                errorCount += errorRecords.size();
            }

        } catch (Exception e) {
            // Log batch-level exception
            Error_Handling__c errorRec = new Error_Handling__c();
            errorRec.Component_Name__c = 'Course Managers Upload';
            errorRec.Error_message__c = 'Batch Exception: ' + e.getMessage() + 
                                       '\nStack Trace: ' + e.getStackTraceString();
            Database.insert(errorRec, false);
            errorCount++;
        }
    }

    /**
     * @description Finish method - log summary
     */
    public void finish(Database.BatchableContext bc) {
        System.debug('CourseManagerBatchProcessor completed. Success: ' + successCount + ', Errors: ' + errorCount);
        
        // Optional: Send email notification to running user
        // Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        // email.setToAddresses(new String[] { UserInfo.getUserEmail() });
        // email.setSubject('Course Manager Upload Complete');
        // email.setPlainTextBody('Success: ' + successCount + ', Errors: ' + errorCount);
        // Messaging.sendEmail(new Messaging.SingleEmailMessage[] { email });
    }

    /**
     * @description Normalizes role value to match picklist (case-insensitive)
     * @return 'Manager', 'Associate', or 'Delivery Manager'; null if invalid
     */
    private String normalizeRole(String roleValue) {
        if (String.isBlank(roleValue)) return null;
        
        String roleLower = roleValue.trim().toLowerCase();
        
        if (roleLower == 'manager') return 'Manager';
        if (roleLower == 'associate') return 'Associate';
        if (roleLower == 'delivery manager') return 'Delivery Manager';
        
        return null; // Invalid role
    }

    /**
     * @description Adds an error to the consolidated error map
     * @param errorsByReason Map tracking errors by reason
     * @param rowNumber Row number that failed
     * @param reason Error reason
     */
    private void addErrorToMap(Map<String, List<Integer>> errorsByReason, Integer rowNumber, String reason) {
        if (!errorsByReason.containsKey(reason)) {
            errorsByReason.put(reason, new List<Integer>());
        }
        errorsByReason.get(reason).add(rowNumber);
    }

    /**
     * @description Adds a warning to the consolidated warning map
     * @param warningsByReason Map tracking warnings by reason
     * @param rowNumber Row number that had a warning
     * @param reason Warning reason
     */
    private void addWarningToMap(Map<String, List<Integer>> warningsByReason, Integer rowNumber, String reason) {
        if (!warningsByReason.containsKey(reason)) {
            warningsByReason.put(reason, new List<Integer>());
        }
        warningsByReason.get(reason).add(rowNumber);
    }

    /**
     * @description Creates an Error_Handling__c record for a failed row
     */
    private Error_Handling__c createErrorRecord(Integer rowNumber, String errorMessage, CourseManagerExcelParser.ExcelRow row) {
        Error_Handling__c errorRec = new Error_Handling__c();
        errorRec.Component_Name__c = 'CourseManagerBatchProcessor';
        errorRec.Error_message__c = 'Row ' + rowNumber + ': ' + errorMessage + 
                                   '\nOwner: ' + row.owner + 
                                   '\nCourses: ' + row.courses + 
                                   '\nCourseCode: ' + row.courseCode + 
                                   '\nCourseType: ' + row.courseType + 
                                   '\nLocation: ' + row.location + 
                                   '\nAcademicYear: ' + row.academicYear +
                                   '\nAcademicTerm: ' + row.academicTerm +
                                   '\nRoles: ' + row.roles;
        return errorRec;
    }
}