public without sharing class AACoursePreferenceController {

    // ──────────────────────────────────────────────────────────────────────────────
    // ✅ Get Active Programs for Filter
    // ──────────────────────────────────────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getPrograms() {
        List<Map<String, String>> programs = new List<Map<String, String>>();
        try {
            // Check if it's a standard 'Program' or 'Program__c'. 
            // Based on CourseOffering metadata, referenceTo is 'Program'.
            // In SF, standard Program object often belongs to Education Cloud.
            // If it's custom, it would be Program__c. 
            // We'll perform a dynamic query to be safe or assuming standard.
            for (Program prog : [
                SELECT Id, Name
                FROM Program
                ORDER BY Name ASC
            ]) {
                programs.add(new Map<String, String>{
                    'label' => prog.Name,
                    'value' => prog.Id
                });
            }
            System.debug('✅ Programs retrieved: ' + programs.size());
        } catch (Exception e) {
            System.debug('❌ Error fetching programs: ' + e.getMessage());
            // Fallback for custom Program__c if standard Program fails
            try {
                List<SObject> customProgs = Database.query('SELECT Id, Name FROM Program__c ORDER BY Name ASC');
                for (SObject p : customProgs) {
                    programs.add(new Map<String, String>{
                        'label' => (String)p.get('Name'),
                        'value' => (Id)p.get('Id')
                    });
                }
            } catch (Exception ex) {
                throw new AuraHandledException('Error loading programs: ' + e.getMessage());
            }
        }
        return programs;
    }

    // ──────────────────────────────────────────────────────────────────────────────
    // ✅ Get Academic Sessions for Filter (Filtered by Program if provided)
    // ──────────────────────────────────────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getAcademicSessions(Id programId) {
        List<Map<String, String>> sessions = new List<Map<String, String>>();
        try {
            List<AcademicSession> sessionList;
            if (programId != null) {
                // Return only sessions that have active course offerings for this program
                sessionList = [
                    SELECT Id, Name
                    FROM AcademicSession
                    WHERE IsActive = true
                    AND Id IN (
                        SELECT AcademicSessionId
                        FROM CourseOffering
                        WHERE IsActive = true
                        AND Program__c = :programId
                        AND AcademicSessionId != null
                    )
                    ORDER BY Name ASC
                ];
            } else {
                sessionList = [
                    SELECT Id, Name
                    FROM AcademicSession
                    WHERE IsActive = true
                    ORDER BY Name ASC
                ];
            }
            
            for (AcademicSession sess : sessionList) {
                sessions.add(new Map<String, String>{
                    'label' => sess.Name,
                    'value' => sess.Id
                });
            }
            System.debug('✅ Academic Sessions retrieved: ' + sessions.size());
        } catch (Exception e) {
            System.debug('❌ Error fetching academic sessions: ' + e.getMessage());
            throw new AuraHandledException('Error loading academic sessions: ' + e.getMessage());
        }
        return sessions;
    }

    // ──────────────────────────────────────────────────────────────────────────────
    // ✅ Get Learning Courses for Filter (all, no term restriction)
    // ──────────────────────────────────────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getLearningCourses(Id academicSessionId, Id programId) {
        List<Map<String, String>> courses = new List<Map<String, String>>();
        try {
            String subQuery = 'SELECT LearningCourseId FROM CourseOffering WHERE IsActive = true AND LearningCourseId != null';
            if (academicSessionId != null) {
                subQuery += ' AND AcademicSessionId = :academicSessionId';
            }
            if (programId != null) {
                subQuery += ' AND Program__c = :programId';
            }

            // Fix: We need the LearningCourseId values from the offerings, not the offering IDs
            List<CourseOffering> offerings = Database.query(subQuery);
            Set<Id> lcIds = new Set<Id>();
            for (CourseOffering co : offerings) {
                lcIds.add(co.LearningCourseId);
            }

            List<LearningCourse> learningCourses = [
                SELECT Id, Name, CourseNumber
                FROM LearningCourse
                WHERE Id IN :lcIds
                ORDER BY CourseNumber ASC NULLS LAST, Name ASC
            ];
            for (LearningCourse lc : learningCourses) {
                String label = String.isNotBlank(lc.CourseNumber)
                    ? lc.CourseNumber + ' – ' + lc.Name
                    : lc.Name;
                courses.add(new Map<String, String>{
                    'label' => label,
                    'value' => lc.Id
                });
            }
            System.debug('✅ Learning Courses retrieved: ' + courses.size());
        } catch (Exception e) {
            System.debug('❌ Error fetching learning courses: ' + e.getMessage());
            throw new AuraHandledException('Error loading learning courses: ' + e.getMessage());
        }
        return courses;
    }

    // ──────────────────────────────────────────────────────────────────────────────
    // ✅ Get Available Course Offerings (with Acronym, Program, Term info)
    // ──────────────────────────────────────────────────────────────────────────────
    @AuraEnabled(cacheable=false)
    public static List<CourseOffering> getAvailableCourses(Id academicSessionId, Id learningCourseId, Id programId) {
        try {
            String query =
                'SELECT Id, Name, SectionNumber, Course_Acronym__c, Program__c, ' +
                'AcademicSessionId, AcademicSession.Name, ' +
                'PrimaryFacultyId, PrimaryFaculty.Name, ' +
                'LearningCourseId, LearningCourse.Name, LearningCourse.CourseNumber, ' +
                'LearningCourse.Course_Acronym__c ' +
                'FROM CourseOffering ' +
                'WHERE IsActive = true';

            if (academicSessionId != null) {
                query += ' AND AcademicSessionId = :academicSessionId';
            }
            if (learningCourseId != null) {
                query += ' AND LearningCourseId = :learningCourseId';
            }
            if (programId != null) {
                query += ' AND Program__c = :programId';
            }
            query += ' ORDER BY LearningCourse.CourseNumber ASC NULLS LAST, Name ASC';

            List<CourseOffering> courseOfferings = Database.query(query);
            System.debug('✅ Course Offerings retrieved: ' + courseOfferings.size());
            return courseOfferings;
        } catch (Exception e) {
            System.debug('❌ Error fetching course offerings: ' + e.getMessage());
            throw new AuraHandledException('Error loading courses: ' + e.getMessage());
        }
    }

    // ──────────────────────────────────────────────────────────────────────────────
    // ✅ Get AA Profile Details (term is optional – no hard dependency now)
    // ──────────────────────────────────────────────────────────────────────────────
    @AuraEnabled
    public static Map<String, Object> getAAProfileDetails(Id aaProfileId) {
        try {
            AA_Profile__c aaProfile = [
                SELECT Id, Name, Academic_Term__c, Academic_Term__r.Name, Academic_Associate__c
                FROM AA_Profile__c
                WHERE Id = :aaProfileId
                LIMIT 1
            ];
            System.debug('✅ AA Profile found: ' + aaProfile.Name);
            return new Map<String, Object>{
                'profileId'   => aaProfile.Id,
                'profileName' => aaProfile.Name,
                'termId'      => aaProfile.Academic_Term__c,
                'termName'    => aaProfile.Academic_Term__r != null ? aaProfile.Academic_Term__r.Name : null,
                'contactId'   => aaProfile.Academic_Associate__c
            };
        } catch (Exception e) {
            System.debug('❌ Error fetching AA Profile: ' + e.getMessage());
            throw new AuraHandledException('Error loading AA Profile details: ' + e.getMessage());
        }
    }

    // ──────────────────────────────────────────────────────────────────────────────
    // ✅ Get Current Preferences
    //    Returns individual AA_Course_Preference__c records (one per preference rank)
    //    for the current "active" batch (In Approval, Rejected, or Approved).
    // ──────────────────────────────────────────────────────────────────────────────
    @AuraEnabled
    public static List<Map<String, Object>> getPreferences(Id contactId) {
        if (contactId == null) {
            return new List<Map<String, Object>>();
        }
        try {
            // Fetch the most recent batch – group by Submitted_On__c (null = In Approval/draft batch)
            // We look for In Approval first, then Approved, then Rejected (most recent group)
            List<AA_Course_Preference__c> prefRecords = [
                SELECT Id, Name,
                       Status__c,
                       Preference_Rank__c,
                       Type__c,
                       Course_Offering__c,
                       Course_Offering__r.Name,
                       Course_Offering__r.Course_Acronym__c,
                       Course_Offering__r.LearningCourse.Name,
                       Course_Offering__r.LearningCourse.CourseNumber,
                       Course_Offering__r.LearningCourse.Course_Acronym__c,
                       Course_Offering__r.AcademicSession.Name,
                       Academic_Term__c,
                       Academic_Term__r.Name,
                       Program__c,
                       Approval_Manager__c,
                       Approval_Manager__r.Name,
                       Approval_Comments__c,
                       Approved_On__c,
                       Submitted_On__c,
                       CreatedDate
                FROM AA_Course_Preference__c
                WHERE AA_Contact__c = :contactId
                AND Status__c IN ('In Approval', 'Approved', 'Rejected')
                ORDER BY Preference_Rank__c ASC, CreatedDate DESC
            ];

            if (prefRecords.isEmpty()) {
                System.debug('📭 No preferences found for this contact');
                return new List<Map<String, Object>>();
            }

            List<Map<String, Object>> preferenceList = new List<Map<String, Object>>();
            for (AA_Course_Preference__c p : prefRecords) {

                String courseAcronym  = null;
                String courseOfferName = p.Course_Offering__r != null ? p.Course_Offering__r.Name : null;
                String termName = p.Academic_Term__r != null ? p.Academic_Term__r.Name : null;
                String sessionName = (p.Course_Offering__r != null && p.Course_Offering__r.AcademicSession != null)
                    ? p.Course_Offering__r.AcademicSession.Name : null;
                String lcName = null;
                String lcCourseNumber = null;

                if (p.Course_Offering__r != null) {
                    // Prefer LearningCourse acronym; fall back to CourseOffering formula field
                    if (p.Course_Offering__r.LearningCourse != null) {
                        lcName         = p.Course_Offering__r.LearningCourse.Name;
                        lcCourseNumber = p.Course_Offering__r.LearningCourse.CourseNumber;
                        courseAcronym  = p.Course_Offering__r.LearningCourse.Course_Acronym__c;
                    }
                    if (String.isBlank(courseAcronym)) {
                        courseAcronym = p.Course_Offering__r.Course_Acronym__c;
                    }
                }

                preferenceList.add(new Map<String, Object>{
                    'Id'                   => p.Id,
                    'Preference_Rank__c'   => p.Preference_Rank__c,
                    'Course_Offering__c'   => p.Course_Offering__c,
                    'Course_Offering_Name' => courseOfferName,
                    'Course_Acronym'       => courseAcronym,
                    'Learning_Course_Name' => lcName,
                    'Course_Number'        => lcCourseNumber,
                    'Term_Name'            => termName != null ? termName : sessionName,
                    'Program__c'           => p.Program__c,
                    'Type__c'              => p.Type__c,
                    'Status__c'            => p.Status__c,
                    'Approval_Manager__c'  => p.Approval_Manager__c,
                    'Approval_Manager_Name'=> p.Approval_Manager__r != null ? p.Approval_Manager__r.Name : null,
                    'Rejection_Reason__c'  => p.Approval_Comments__c
                });
            }

            System.debug('✅ Returning ' + preferenceList.size() + ' preferences (total active)');
            return preferenceList;

        } catch (Exception e) {
            System.debug('❌ Error fetching preferences: ' + e.getMessage());
            System.debug('Stack Trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Error loading preferences: ' + e.getMessage());
        }
    }

    // ──────────────────────────────────────────────────────────────────────────────
    // ✅ Get Preference History (all submitted batches)
    // ──────────────────────────────────────────────────────────────────────────────
    @AuraEnabled
    public static List<PreferenceHistoryRecord> getPreferenceHistory(Id contactId) {
        if (contactId == null) {
            return new List<PreferenceHistoryRecord>();
        }
        try {
            // Fetch all non-draft preferences grouped by submission
            List<AA_Course_Preference__c> allPreferences = [
                SELECT Id, Name,
                       Status__c,
                       Preference_Rank__c,
                       Type__c,
                       Course_Offering__c,
                       Course_Offering__r.Name,
                       Course_Offering__r.Course_Acronym__c,
                       Course_Offering__r.LearningCourse.Name,
                       Course_Offering__r.LearningCourse.CourseNumber,
                       Course_Offering__r.LearningCourse.Course_Acronym__c,
                       Approval_Manager__c,
                       Approval_Manager__r.Name,
                       Approval_Comments__c,
                       Submitted_On__c,
                       Approved_On__c,
                       CreatedDate
                FROM AA_Course_Preference__c
                WHERE AA_Contact__c = :contactId
                AND Status__c IN ('In Approval', 'Approved', 'Rejected')
                ORDER BY Submitted_On__c DESC NULLS LAST, Preference_Rank__c ASC
            ];

            // Group by Submitted_On__c (same batch = same submission timestamp, ±1 second)
            Map<String, List<AA_Course_Preference__c>> batchMap = new Map<String, List<AA_Course_Preference__c>>();
            Map<String, String> batchKeyToStatus = new Map<String, String>();
            Map<String, String> batchKeyToManager = new Map<String, String>();
            Map<String, String> batchKeyToReason = new Map<String, String>();
            Map<String, DateTime> batchKeyToSubmittedOn = new Map<String, DateTime>();

            for (AA_Course_Preference__c p : allPreferences) {
                // Group by Status + Submitted_On date (YYYY-MM-DD) to bucket same-day submissions
                String dateKey = p.Submitted_On__c != null
                    ? p.Status__c + '_' + String.valueOf(p.Submitted_On__c.date())
                    : p.Status__c + '_' + p.Id;

                if (!batchMap.containsKey(dateKey)) {
                    batchMap.put(dateKey, new List<AA_Course_Preference__c>());
                    batchKeyToStatus.put(dateKey, p.Status__c);
                    batchKeyToManager.put(dateKey, p.Approval_Manager__r != null ? p.Approval_Manager__r.Name : '');
                    batchKeyToReason.put(dateKey, p.Approval_Comments__c);
                    batchKeyToSubmittedOn.put(dateKey, p.Submitted_On__c);
                }
                batchMap.get(dateKey).add(p);
            }

            List<PreferenceHistoryRecord> historyList = new List<PreferenceHistoryRecord>();
            for (String key : batchMap.keySet()) {
                List<AA_Course_Preference__c> batch = batchMap.get(key);
                PreferenceHistoryRecord rec = new PreferenceHistoryRecord();
                rec.recordId        = batch[0].Id;
                rec.recordName      = batch[0].Name;
                rec.status          = batchKeyToStatus.get(key);
                rec.approvalManager = batchKeyToManager.get(key);
                rec.rejectionReason = batchKeyToReason.get(key);
                rec.submittedOn     = batchKeyToSubmittedOn.get(key);
                rec.createdDate     = batch[0].CreatedDate;
                rec.preferenceItems = new List<Map<String, Object>>();

                for (AA_Course_Preference__c p : batch) {
                    String courseAcronym = null;
                    String lcName = null;
                    String lcCourseNumber = null;
                    String courseOfferName = p.Course_Offering__r != null ? p.Course_Offering__r.Name : null;

                    if (p.Course_Offering__r != null) {
                        if (p.Course_Offering__r.LearningCourse != null) {
                            lcName         = p.Course_Offering__r.LearningCourse.Name;
                            lcCourseNumber = p.Course_Offering__r.LearningCourse.CourseNumber;
                            courseAcronym  = p.Course_Offering__r.LearningCourse.Course_Acronym__c;
                        }
                        if (String.isBlank(courseAcronym)) {
                            courseAcronym = p.Course_Offering__r.Course_Acronym__c;
                        }
                    }

                    rec.preferenceItems.add(new Map<String, Object>{
                        'rank'               => p.Preference_Rank__c,
                        'courseOfferingName' => courseOfferName,
                        'courseAcronym'      => courseAcronym,
                        'learningCourseName' => lcName,
                        'courseNumber'       => lcCourseNumber,
                        'type'               => p.Type__c
                    });
                }
                historyList.add(rec);
            }

            System.debug('✅ History batches retrieved: ' + historyList.size());
            return historyList;

        } catch (Exception e) {
            System.debug('❌ Error fetching preference history: ' + e.getMessage());
            throw new AuraHandledException('Error loading preference history: ' + e.getMessage());
        }
    }

    // ──────────────────────────────────────────────────────────────────────────────
    // ✅ Wrapper Class for Preference History
    // ──────────────────────────────────────────────────────────────────────────────
    public class PreferenceHistoryRecord {
        @AuraEnabled public String recordId        { get; set; }
        @AuraEnabled public String recordName      { get; set; }
        @AuraEnabled public String status          { get; set; }
        @AuraEnabled public String approvalManager { get; set; }
        @AuraEnabled public String rejectionReason { get; set; }
        @AuraEnabled public DateTime submittedOn   { get; set; }
        @AuraEnabled public DateTime createdDate   { get; set; }
        @AuraEnabled public List<Map<String, Object>> preferenceItems { get; set; }
    }

    // ──────────────────────────────────────────────────────────────────────────────
    // ✅ Create & Submit Preferences (one record per rank, status = In Approval)
    //    Max 4 preferences per contact per call.
    //    Validates duplicate Course Offerings and duplicate Learning Courses.
    // ──────────────────────────────────────────────────────────────────────────────
    @AuraEnabled
    public static String createDraftPreferences(
        List<Id> selectedCourseIds,
        List<String> selectedTypes,
        Id termId,
        Id contactId,
        Id aaProfileId
    ) {
        try {
            System.debug('💾 Creating preferences (one-per-rank)...');
            System.debug('📋 Selected Courses: ' + selectedCourseIds);
            System.debug('👤 Contact ID: ' + contactId);

            // Basic validation
            if (selectedCourseIds == null || selectedCourseIds.isEmpty()) {
                throw new AuraHandledException('Please select at least one course.');
            }
            if (selectedCourseIds.size() > 4) {
                throw new AuraHandledException('You can select a maximum of 4 courses.');
            }

            // Duplicate Course Offering check
            Set<Id> uniqueCourseIds = new Set<Id>(selectedCourseIds);
            if (uniqueCourseIds.size() != selectedCourseIds.size()) {
                throw new AuraHandledException('Duplicate course offerings are not allowed.');
            }

            // Duplicate Learning Course check (different sections of same LC)
            List<CourseOffering> offerings = [
                SELECT Id, LearningCourseId
                FROM CourseOffering
                WHERE Id IN :selectedCourseIds
            ];
            Set<Id> uniqueLCIds = new Set<Id>();
            for (CourseOffering co : offerings) {
                if (co.LearningCourseId != null) {
                    if (uniqueLCIds.contains(co.LearningCourseId)) {
                        throw new AuraHandledException('You cannot select multiple sections of the same Learning Course.');
                    }
                    uniqueLCIds.add(co.LearningCourseId);
                }
            }

            // Count existing Approved records to determine starting rank
            List<AA_Course_Preference__c> existingRecords = [
                SELECT Id, Status__c, Course_Offering__c
                FROM AA_Course_Preference__c
                WHERE AA_Contact__c = :contactId
                AND Status__c IN ('Approved', 'In Approval', 'Rejected')
                ORDER BY Preference_Rank__c ASC
            ];

            List<AA_Course_Preference__c> approvedRecords = new List<AA_Course_Preference__c>();
            List<AA_Course_Preference__c> toDelete = new List<AA_Course_Preference__c>();
            Set<Id> approvedCourseIds = new Set<Id>();

            for (AA_Course_Preference__c p : existingRecords) {
                if (p.Status__c == 'Approved') {
                    approvedRecords.add(p);
                    approvedCourseIds.add(p.Course_Offering__c);
                } else {
                    // Delete In Approval or Rejected records as we are re-applying
                    toDelete.add(p);
                }
            }

            if (approvedRecords.size() + selectedCourseIds.size() > 4) {
                throw new AuraHandledException('Total approved and new preferences cannot exceed 4. You already have ' + 
                    approvedRecords.size() + ' approved preference(s).');
            }

            // Check if any selected course is already approved
            for (Id selId : selectedCourseIds) {
                if (approvedCourseIds.contains(selId)) {
                    throw new AuraHandledException('One or more selected courses are already in your Approved list.');
                }
            }

            if (!toDelete.isEmpty()) {
                System.debug('🗑️ Deleting ' + toDelete.size() + ' In Approval/Rejected records for re-application');
                delete toDelete;
            }

            Integer startingRank = approvedRecords.size() + 1;

            // Fetch Approval Manager from AA_Profile__c -> Contact -> Reporting_Manager__c
            Id approvalManagerId = null;
            if (aaProfileId != null) {
                List<AA_Profile__c> profiles = [
                    SELECT Academic_Associate__r.Reporting_Manager__c 
                    FROM AA_Profile__c 
                    WHERE Id = :aaProfileId 
                    LIMIT 1
                ];
                if (!profiles.isEmpty()) {
                    approvalManagerId = profiles[0].Academic_Associate__r.Reporting_Manager__c;
                }
            }

            // Record naming handled by AutoNumber

            // Determine Program from Course Offering (if available)
            Map<Id, Id> courseToProgram = new Map<Id, Id>();
            // If CourseOffering has a Program lookup, we can derive it, else leave null.

            // Create one record per preference
            List<AA_Course_Preference__c> newPrefs = new List<AA_Course_Preference__c>();
            for (Integer i = 0; i < selectedCourseIds.size(); i++) {
                Integer rank = startingRank + i;
                String type = (selectedTypes != null && selectedTypes.size() > i) ? selectedTypes[i] : null;

                AA_Course_Preference__c pref = new AA_Course_Preference__c();
                pref.AA_Contact__c         = contactId;
                pref.Academic_Associate__c = aaProfileId;  // lookup to AA_Profile__c
                pref.Academic_Term__c      = termId;
                pref.Course_Offering__c    = selectedCourseIds[i];
                pref.Preference_Rank__c    = rank;
                pref.Type__c               = type;
                pref.Status__c             = 'In Approval';
                pref.Approval_Manager__c   = approvalManagerId;
                pref.Submitted_On__c       = System.now();
                newPrefs.add(pref);
            }

            insert newPrefs;
            System.debug('✅ Created ' + newPrefs.size() + ' preference records');
            return newPrefs[0].Id;

        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            System.debug('❌ Error creating preferences: ' + e.getMessage());
            System.debug('Stack Trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Error creating preferences: ' + e.getMessage());
        }
    }

    // ──────────────────────────────────────────────────────────────────────────────
    // ✅ Submit Preferences (kept for backward-compat; now a no-op since records
    //    are created directly in "In Approval" status)
    // ──────────────────────────────────────────────────────────────────────────────
    @AuraEnabled
    public static void submitPreferences(Id contactId) {
        try {
            // Records are already in "In Approval" — nothing to change.
            // This method is kept so existing LWC wiring doesn't break.
            System.debug('ℹ️ submitPreferences called – records already In Approval for: ' + contactId);
        } catch (Exception e) {
            throw new AuraHandledException('Error submitting preferences: ' + e.getMessage());
        }
    }

    // ──────────────────────────────────────────────────────────────────────────────
    // ✅ Delete Draft / In Approval Preferences
    // ──────────────────────────────────────────────────────────────────────────────
    @AuraEnabled
    public static void deleteDraftPreferences(Id contactId) {
        try {
            List<AA_Course_Preference__c> toDelete = [
                SELECT Id
                FROM AA_Course_Preference__c
                WHERE AA_Contact__c = :contactId
                AND Status__c = 'In Approval'
            ];
            if (!toDelete.isEmpty()) {
                delete toDelete;
                System.debug('✅ Deleted ' + toDelete.size() + ' In Approval preference(s)');
            } else {
                System.debug('📭 No In Approval preferences found to delete');
            }
        } catch (Exception e) {
            System.debug('❌ Error deleting preferences: ' + e.getMessage());
            throw new AuraHandledException('Error deleting preferences: ' + e.getMessage());
        }
    }
}