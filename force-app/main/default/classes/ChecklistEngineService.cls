/**
 * @description Service class to handle automated checklist generation
 * for students based on course enrollments and baseline program/term configurations
 * @author DEVSLCM Team
 * @date 2026
 */
public with sharing class ChecklistEngineService {
    
    // Cache for Record Type IDs
    private static Id checklistRecordTypeId;
    private static Id checklistItemRecordTypeId;
    
    /**
     * @description Gets the Student Checklist Record Type ID for Course_Checklist__c
     * @return RecordType Id
     */
    private static Id getChecklistRecordTypeId() {
        if (checklistRecordTypeId == null) {
            RecordType rt = [SELECT Id 
                           FROM RecordType 
                           WHERE SobjectType = 'Course_Checklist__c' 
                           AND Name = 'Student Checklist' 
                           LIMIT 1];
            checklistRecordTypeId = rt.Id;
        }
        return checklistRecordTypeId;
    }
    
    /**
     * @description Gets the Student Checklist Record Type ID for Course_Checklist_Item__c
     * @return RecordType Id
     */
    private static Id getChecklistItemRecordTypeId() {
        if (checklistItemRecordTypeId == null) {
            RecordType rt = [SELECT Id 
                           FROM RecordType 
                           WHERE SobjectType = 'Course_Checklist_Item__c' 
                           AND Name = 'Student Checklist' 
                           LIMIT 1];
            checklistItemRecordTypeId = rt.Id;
        }
        return checklistItemRecordTypeId;
    }
    
    /**
     * @description Creates course-specific checklists for enrolled students
     * @param copIds Set of CourseOfferingParticipant record IDs
     */
    public static void createCourseChecklists(Set<Id> copIds) {
        if (copIds == null || copIds.isEmpty()) {
            return;
        }
        
        // Fetch CourseOfferingParticipant records with related data
        Map<Id, CourseOfferingParticipant> copMap = new Map<Id, CourseOfferingParticipant>(
            [SELECT Id, 
                    ParticipantContactId, 
                    ParticipantContact.Name,
                    CourseOfferingId,
                    CourseOffering.Name,
                    CourseOffering.LearningCourseId,
                    CourseOffering.LearningCourse.Name,
                    CourseOffering.AcademicSessionId,
                    CourseOffering.Program__c,
                    ParticipationStatus
             FROM CourseOfferingParticipant
             WHERE Id IN :copIds
             AND ParticipationStatus = 'Enrolled'
             AND ParticipantContactId != null
             AND CourseOfferingId != null]
        );
        
        if (copMap.isEmpty()) {
            return;
        }
        
        // Extract filter criteria
        Set<Id> studentIds = new Set<Id>();
        Set<Id> courseOfferingIds = new Set<Id>();
        Set<Id> learningCourseIds = new Set<Id>();
        Set<Id> programIds = new Set<Id>();
        Set<Id> termIds = new Set<Id>();
        
        for (CourseOfferingParticipant cop : copMap.values()) {
            studentIds.add(cop.ParticipantContactId);
            courseOfferingIds.add(cop.CourseOfferingId);
            if (cop.CourseOffering.LearningCourseId != null) {
                learningCourseIds.add(cop.CourseOffering.LearningCourseId);
            }
            if (cop.CourseOffering.Program__c != null) {
                programIds.add(cop.CourseOffering.Program__c);
            }
            if (cop.CourseOffering.AcademicSessionId != null) {
                termIds.add(cop.CourseOffering.AcademicSessionId);
            }
        }
        
        // Query templates for course-specific checklists
        List<Course_Checklist_Item_Template__c> templates = [
            SELECT Id, Subject__c, Description__c, Priority__c, 
                   Owner_Roles__c, Activity_Type__c, Course__c,
                   Program__c, Term__c
            FROM Course_Checklist_Item_Template__c
            WHERE Template_Type__c = 'Course'
            AND Active__c = true
            AND (Course__c IN :learningCourseIds 
                 OR (Program__c IN :programIds AND Course__c = null)
                 OR (Term__c IN :termIds AND Course__c = null))
            ORDER BY Course__c NULLS LAST
        ];
        
        if (templates.isEmpty()) {
            return;
        }
        
        // Check for existing checklists (deduplication)
        List<Course_Checklist__c> existingChecklists = [
            SELECT Id, Student__c, Course_Offering__c, Checklist_Type__c
            FROM Course_Checklist__c
            WHERE Student__c IN :studentIds
            AND Course_Offering__c IN :courseOfferingIds
            AND Checklist_Type__c = 'Course'
        ];
        
        // Build a set of existing checklist keys
        Set<String> existingChecklistKeys = new Set<String>();
        for (Course_Checklist__c existing : existingChecklists) {
            existingChecklistKeys.add(
                existing.Student__c + '_' + 
                existing.Course_Offering__c + '_' + 
                existing.Checklist_Type__c
            );
        }
        
        // Prepare data for insert
        List<Course_Checklist__c> checklistsToInsert = new List<Course_Checklist__c>();
        Map<String, Course_Checklist__c> checklistKeyMap = new Map<String, Course_Checklist__c>();
        
        for (CourseOfferingParticipant cop : copMap.values()) {
            String checklistKey = cop.ParticipantContactId + '_' + 
                                  cop.CourseOfferingId + '_Course';
            
            // Skip if checklist already exists
            if (existingChecklistKeys.contains(checklistKey)) {
                continue;
            }
            
            String courseName = cop.CourseOffering.LearningCourse.Name != null ? cop.CourseOffering.LearningCourse.Name : cop.CourseOffering.Name;
            Course_Checklist__c checklist = new Course_Checklist__c(
                Name = 'Course Checklist - ' + courseName + ' - ' + cop.ParticipantContact.Name,
                Student__c = cop.ParticipantContactId,
                Course_Offering__c = cop.CourseOfferingId,
                Checklist_Type__c = 'Course',
                Program__c = cop.CourseOffering.Program__c,
                Term__c = cop.CourseOffering.AcademicSessionId,
                Source_Record_Id__c = cop.Id,
                Source_Object__c = 'CourseOfferingParticipant',
                Status__c = 'Active',
                Start_Date__c = System.today(),
                RecordTypeId = getChecklistRecordTypeId()
            );
            
            checklistsToInsert.add(checklist);
            checklistKeyMap.put(checklistKey, checklist);
        }
        
        // Insert checklists
        if (!checklistsToInsert.isEmpty()) {
            insert checklistsToInsert;
            
            // Build map of checklist ID to LearningCourseId for template matching
            Map<Id, Id> checklistToLearningCourseMap = new Map<Id, Id>();
            for (CourseOfferingParticipant cop : copMap.values()) {
                String checklistKey = cop.ParticipantContactId + '_' + 
                                      cop.CourseOfferingId + '_Course';
                if (checklistKeyMap.containsKey(checklistKey)) {
                    Course_Checklist__c checklist = checklistKeyMap.get(checklistKey);
                    if (cop.CourseOffering.LearningCourseId != null) {
                        checklistToLearningCourseMap.put(checklist.Id, cop.CourseOffering.LearningCourseId);
                    }
                }
            }
            
            // Create checklist items
            createChecklistItems(checklistKeyMap, templates, 'Course', checklistToLearningCourseMap);
        }
    }
    
    /**
     * @description Creates baseline checklists for students based on program and term
     * @param enrollmentSessionIds Set of Enrollment_Session__c record IDs
     */
    public static void createBaselineChecklists(Set<Id> enrollmentSessionIds) {
        System.debug('>>> ChecklistEngineService.createBaselineChecklists started with ' + 
                     (enrollmentSessionIds != null ? enrollmentSessionIds.size() : 0) + ' enrollment session IDs.');
        
        if (enrollmentSessionIds == null || enrollmentSessionIds.isEmpty()) {
            System.debug('<<< No enrollment session IDs provided. Exiting.');
            return;
        }
        
        // Fetch Enrollment_Session__c records with related data
        Map<Id, Enrollment_Session__c> enrollmentSessionMap = new Map<Id, Enrollment_Session__c>(
            [SELECT Id, 
                    Assigned_Contact__c,
                    Assigned_Contact__r.Name,
                    Program_Enrollment__r.ProgramId,
                    Academic_Session__c,
                    Academic_Session__r.Name,
                    Program_Enrollment__c,
                    Active__c
             FROM Enrollment_Session__c
             WHERE Id IN :enrollmentSessionIds
             AND Active__c = true
             AND Assigned_Contact__c != null]
        );
        
        System.debug('Queried ' + enrollmentSessionMap.size() + ' active enrollment sessions with Assigned_Contact__c.');
        
        if (enrollmentSessionMap.isEmpty()) {
            System.debug('<<< No active enrollment sessions found with Assigned_Contact__c. Exiting.');
            return;
        }
        
        // Extract filter criteria
        Set<Id> studentIds = new Set<Id>();
        Set<Id> programIds = new Set<Id>();
        Set<Id> termIds = new Set<Id>();
        
        for (Enrollment_Session__c es : enrollmentSessionMap.values()) {
            System.debug('Processing ES ID: ' + es.Id + ' | Contact: ' + es.Assigned_Contact__c + 
                         ' | Program: ' + es.Program_Enrollment__r.ProgramId + ' | Term: ' + es.Academic_Session__c);
            studentIds.add(es.Assigned_Contact__c);
            if (es.Program_Enrollment__r.ProgramId != null) {
                programIds.add(es.Program_Enrollment__r.ProgramId);
            }
            if (es.Academic_Session__c != null) {
                termIds.add(es.Academic_Session__c);
            }
        }
        
        System.debug('Extracted - Students: ' + studentIds.size() + ', Programs: ' + programIds.size() + ', Terms: ' + termIds.size());
        
        // Query templates for baseline checklists
        List<Course_Checklist_Item_Template__c> templates = [
            SELECT Id, Subject__c, Description__c, Priority__c, 
                   Owner_Roles__c, Activity_Type__c,
                   Program__c, Term__c
            FROM Course_Checklist_Item_Template__c
            WHERE Template_Type__c = 'Baseline'
            AND Active__c = true
            AND (/*Program__c IN :programIds OR*/ Term__c IN :termIds)
        ];
        
        System.debug('Found ' + templates.size() + ' baseline templates.');
        
        if (templates.isEmpty()) {
            System.debug('<<< No baseline templates found. Exiting.');
            return;
        }
        
        // Check for existing baseline checklists (deduplication)
        List<Course_Checklist__c> existingChecklists = [
            SELECT Id, Student__c, Program__c, Term__c, Checklist_Type__c
            FROM Course_Checklist__c
            WHERE Student__c IN :studentIds
            AND Checklist_Type__c = 'Baseline'
            AND (Program__c IN :programIds OR Term__c IN :termIds)
        ];
        
        // Build a set of existing checklist keys
        System.debug('Found ' + existingChecklists.size() + ' existing baseline checklists.');
        Set<String> existingChecklistKeys = new Set<String>();
        for (Course_Checklist__c existing : existingChecklists) {
            String key = existing.Student__c + '_' + 
                        (existing.Program__c != null ? existing.Program__c : '') + '_' + 
                        (existing.Term__c != null ? existing.Term__c : '') + '_' + 
                        existing.Checklist_Type__c;
            existingChecklistKeys.add(key);
            System.debug('Existing checklist key: ' + key);
        }
        
        // Prepare data for insert
        List<Course_Checklist__c> checklistsToInsert = new List<Course_Checklist__c>();
        Map<String, Course_Checklist__c> checklistKeyMap = new Map<String, Course_Checklist__c>();
        
        for (Enrollment_Session__c es : enrollmentSessionMap.values()) {
            String checklistKey = es.Assigned_Contact__c + '_' + 
                                  (es.Program_Enrollment__r.ProgramId != null ? es.Program_Enrollment__r.ProgramId : '') + '_' + 
                                  (es.Academic_Session__c != null ? es.Academic_Session__c : '') + 
                                  '_Baseline';
            
            System.debug('Generated checklist key: ' + checklistKey);
            
            // Skip if checklist already exists
            if (existingChecklistKeys.contains(checklistKey)) {
                System.debug('Checklist already exists for key: ' + checklistKey + '. Skipping.');
                continue;
            }
            
            System.debug('Creating new baseline checklist for ES ID: ' + es.Id);
            
            Course_Checklist__c checklist = new Course_Checklist__c(
                Name = 'Baseline Checklist - ' + es.Academic_Session__r.Name + ' - ' + es.Assigned_Contact__r.Name,
                Student__c = es.Assigned_Contact__c,
                Checklist_Type__c = 'Baseline',
                Program__c = es.Program_Enrollment__r.ProgramId,
                Term__c = es.Academic_Session__c,
                Source_Record_Id__c = es.Id,
                Source_Object__c = 'Enrollment_Session__c',
                Status__c = 'Active',
                Start_Date__c = System.today(),
                RecordTypeId = getChecklistRecordTypeId()
            );
            
            checklistsToInsert.add(checklist);
            checklistKeyMap.put(checklistKey, checklist);
        }
        
        // Insert checklists
        if (!checklistsToInsert.isEmpty()) {
            System.debug('Attempting to insert ' + checklistsToInsert.size() + ' baseline checklists.');
            try {
                insert checklistsToInsert;
                System.debug('Successfully inserted ' + checklistsToInsert.size() + ' baseline checklists.');
                
                // Create checklist items (baseline checklists don't need LearningCourse mapping)
                createChecklistItems(checklistKeyMap, templates, 'Baseline', new Map<Id, Id>());
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, '### Error inserting baseline checklists: ' + 
                           e.getMessage() + '\nStack Trace: ' + e.getStackTraceString());
            }
        } else {
            System.debug('<<< No new baseline checklists to insert. All already exist.');
        }
        
        System.debug('<<< ChecklistEngineService.createBaselineChecklists finished.');
    }
    
    /**
     * @description Creates checklist items from templates
     * @param checklistKeyMap Map of checklist keys to Course_Checklist__c records
     * @param templates List of Course_Checklist_Item_Template__c records
     * @param checklistType Type of checklist (Course or Baseline)
     * @param checklistToLearningCourseMap Map of checklist Id to LearningCourseId (for course checklists)
     */
    private static void createChecklistItems(
        Map<String, Course_Checklist__c> checklistKeyMap,
        List<Course_Checklist_Item_Template__c> templates,
        String checklistType,
        Map<Id, Id> checklistToLearningCourseMap
    ) {
        List<Course_Checklist_Item__c> itemsToInsert = new List<Course_Checklist_Item__c>();
        
        for (String checklistKey : checklistKeyMap.keySet()) {
            Course_Checklist__c checklist = checklistKeyMap.get(checklistKey);
            
            for (Course_Checklist_Item_Template__c template : templates) {
                // Filter templates based on context
                if (checklistType == 'Course') {
                    // For course checklists, match by learning course or program/term
                    Id checklistLearningCourseId = checklistToLearningCourseMap.get(checklist.Id);
                    if (template.Course__c != null && template.Course__c != checklistLearningCourseId) {
                        continue;
                    }
                    if (template.Program__c != null && template.Program__c != checklist.Program__c) {
                        continue;
                    }
                    if (template.Term__c != null && template.Term__c != checklist.Term__c) {
                        continue;
                    }
                } else if (checklistType == 'Baseline') {
                    // For baseline checklists, match by program and/or term
                    if (template.Program__c != null && template.Program__c != checklist.Program__c) {
                        continue;
                    }
                    if (template.Term__c != null && template.Term__c != checklist.Term__c) {
                        continue;
                    }
                }
                
                Course_Checklist_Item__c item = new Course_Checklist_Item__c(
                    Course_Checklist__c = checklist.Id,
                    Course_Checklist_Item_Template__c = template.Id,
                    Subject__c = template.Subject__c,
                    Description__c = template.Description__c,
                    Priority__c = template.Priority__c,
                    Activity_Type__c = template.Activity_Type__c,
                    Status__c = 'Not Started',
                    Role__c = template.Owner_Roles__c,
                    Start_Date__c = System.today(),
                    RecordTypeId = getChecklistItemRecordTypeId()
                );
                
                // Resolve assigned to based on owner roles (placeholder - can be enhanced)
                // For now, inherit from checklist level
                if (checklist.Assigned_To__c != null) {
                    item.Assigned_To__c = checklist.Assigned_To__c;
                }
                
                itemsToInsert.add(item);
            }
        }
        
        // Bulk insert all items
        if (!itemsToInsert.isEmpty()) {
            insert itemsToInsert;
        }
    }
}