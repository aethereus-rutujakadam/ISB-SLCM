/**
 * @description Controller for Advisor Student Dashboard LWC
 * Provides methods to fetch assigned students, checklists, tasks, and send bulk emails
 * @author DEVSLCM Team
 * @date 2026
 */
public without sharing class AdvisorDashboardController {
    
    private static final Integer PAGE_SIZE = 50;
    private static final Integer MAX_EMAIL_RECIPIENTS = 100;
    private static final Set<String> OVERDUE_EXCLUDED_STATUSES = new Set<String>{ 'Completed', 'Closed', 'Waived' };
    
    /**
     * @description Wrapper for student data with aggregated checklist info
     */
    public class StudentWrapper {
        @AuraEnabled public Id contactId { get; set; }
        @AuraEnabled public String studentName { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String program { get; set; }
        @AuraEnabled public String programId { get; set; }
        @AuraEnabled public String term { get; set; }
        @AuraEnabled public String termId { get; set; }
        @AuraEnabled public String termName { get; set; }
        @AuraEnabled public Decimal overallCompletion { get; set; }
        @AuraEnabled public Integer pendingTasksCount { get; set; }
        @AuraEnabled public Integer completedTasksCount { get; set; }
        @AuraEnabled public Integer totalTasksCount { get; set; }
        @AuraEnabled public Integer overdueCount { get; set; }
        @AuraEnabled public Integer totalChecklistsCount { get; set; }
        @AuraEnabled public Boolean hasOptedOut { get; set; }
    }
    
    /**
     * @description Wrapper for checklist data
     */
    public class ChecklistWrapper {
        @AuraEnabled public Id checklistId { get; set; }
        @AuraEnabled public String checklistName { get; set; }
        @AuraEnabled public String checklistType { get; set; }
        @AuraEnabled public Decimal completionPercentage { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Integer totalTasks { get; set; }
        @AuraEnabled public Integer completedTasks { get; set; }
        @AuraEnabled public Integer pendingTasks { get; set; }
        @AuraEnabled public String courseOffering { get; set; }
        @AuraEnabled public String assignedTo { get; set; }
        @AuraEnabled public Date startDate { get; set; }
        @AuraEnabled public Date endDate { get; set; }
    }
    
    /**
     * @description Wrapper for task data
     */
    public class TaskWrapper {
        @AuraEnabled public Id taskId { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Date dueDate { get; set; }
        @AuraEnabled public String priority { get; set; }
        @AuraEnabled public String activityType { get; set; }
        @AuraEnabled public String description { get; set; }
    }
    
    /**
     * @description Response wrapper for student query
     */
    public class StudentResponse {
        @AuraEnabled public List<StudentWrapper> students { get; set; }
        @AuraEnabled public Integer totalCount { get; set; }
        @AuraEnabled public Integer pageNumber { get; set; }
        @AuraEnabled public Integer pageSize { get; set; }
        @AuraEnabled public Boolean hasMore { get; set; }
        
        public StudentResponse() {
            this.students = new List<StudentWrapper>();
            this.pageSize = PAGE_SIZE;
        }
    }
    
    /**
     * @description Response wrapper for email operation
     */
    public class EmailResponse {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public Integer sentCount { get; set; }
        @AuraEnabled public Integer skippedCount { get; set; }
        @AuraEnabled public List<String> skippedReasons { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        
        public EmailResponse() {
            this.skippedReasons = new List<String>();
        }
    }
    
    /**
     * @description Fetches students assigned to current advisor with optional filters
     * @param programId Filter by program (optional)
     * @param termId Filter by term (optional)
     * @param checklistStatus Filter by checklist status (optional)
     * @param pageNumber Page number for pagination (1-based)
     * @return StudentResponse List of students with pagination info
     */
    @AuraEnabled(cacheable=true)
    public static StudentResponse getAssignedStudents(
        String programId,
        String locationId,
        String termId,
        String courseOfferingId,
        String checklistStatus,
        Integer pageNumber,
        String searchText
    ) {
        StudentResponse response = new StudentResponse();
        
        try {
            // System Admin and ASA-profile users should see all students.
            Id userId = UserInfo.getUserId();
            User currentUser = [SELECT Id, Profile.Name FROM User WHERE Id = :userId LIMIT 1];
            Boolean hasGlobalStudentAccess = hasGlobalStudentAccess(currentUser.Profile.Name);

            // For advisor-only users, resolve the linked advisor contact filter.
            Id advisorContactId = null;
            if (!hasGlobalStudentAccess) {
                List<Contact> advisorContacts = [
                    SELECT Id 
                    FROM Contact 
                    WHERE Linked_User_Id__c = :userId 
                    LIMIT 1
                ];
                if (advisorContacts.isEmpty()) {
                    response.totalCount = 0;
                    return response;
                }
                advisorContactId = advisorContacts[0].Id;
            }

            // Pre-fetch course-offering participant contact IDs if a course offering filter is applied
            Set<Id> coContactIds = new Set<Id>();
            if (String.isNotBlank(courseOfferingId)) {
                for (CourseOfferingParticipant cop : [
                    SELECT ParticipantContactId FROM CourseOfferingParticipant
                    WHERE CourseOfferingId = :courseOfferingId AND ParticipantContactId != null
                ]) {
                    coContactIds.add(cop.ParticipantContactId);
                }
            }

            // Build LIKE pattern for name / email search
            String searchPattern = String.isNotBlank(searchText)
                ? '%' + String.escapeSingleQuotes(searchText) + '%'
                : null;

            // Build dynamic query for total count
            String countQuery = 'SELECT COUNT() FROM ProgramEnrollment WHERE IsActive = true';
            if (!hasGlobalStudentAccess) {
                countQuery += ' AND Primary_Advisor__c = :advisorContactId';
            }
            if (String.isNotBlank(programId)) {
                countQuery += ' AND ProgramId = :programId';
            }
            if (String.isNotBlank(locationId)) {
                countQuery += ' AND Location__c = :locationId';
            }
            if (String.isNotBlank(termId)) {
                countQuery += ' AND Academic_Term__c = :termId';
            }
            if (!coContactIds.isEmpty()) {
                countQuery += ' AND ContactId IN :coContactIds';
            }
            if (searchPattern != null) {
                countQuery += ' AND (Contact.Name LIKE :searchPattern OR Contact.Email LIKE :searchPattern)';
            }
            response.totalCount = Database.countQuery(countQuery);
            
            if (response.totalCount == 0) {
                response.pageNumber = pageNumber;
                response.hasMore = false;
                return response;
            }

            // Build dynamic query for Program Enrollments
            String query = 'SELECT ContactId, Contact.Name, Contact.Email, ' +
                          'Contact.HasOptedOutOfEmail, ' +
                          'ProgramId, Program.Name, ' +
                          'Academic_Term__c, Academic_Term__r.Name ' +
                          'FROM ProgramEnrollment ' +
                          'WHERE IsActive = true';
            if (!hasGlobalStudentAccess) {
                query += ' AND Primary_Advisor__c = :advisorContactId';
            }
            if (String.isNotBlank(programId)) {
                query += ' AND ProgramId = :programId';
            }
            if (String.isNotBlank(locationId)) {
                query += ' AND Location__c = :locationId';
            }
            if (String.isNotBlank(termId)) {
                query += ' AND Academic_Term__c = :termId';
            }
            if (!coContactIds.isEmpty()) {
                query += ' AND ContactId IN :coContactIds';
            }
            if (searchPattern != null) {
                query += ' AND (Contact.Name LIKE :searchPattern OR Contact.Email LIKE :searchPattern)';
            }
            query += ' ORDER BY Contact.Name ASC';
            
            // Calculate pagination
            Integer offset = Math.max(0, (pageNumber - 1) * PAGE_SIZE);
            query += ' LIMIT :PAGE_SIZE OFFSET :offset';
            
            List<ProgramEnrollment> enrollments = Database.query(query);
            
            // Get contact IDs for checklist aggregation
            Set<Id> contactIds = new Set<Id>();
            for (ProgramEnrollment pe : enrollments) {
                contactIds.add(pe.ContactId);
            }
            
            // Aggregate checklist totals per student
            Map<Id, AggregateResult> checklistStats = new Map<Id, AggregateResult>();
            Map<Id, Integer> overdueCountsByStudent = new Map<Id, Integer>();
            if (!contactIds.isEmpty()) {
                String aggregateQuery = 'SELECT Student__c, ' +
                                        'COUNT(Id) totalChecklists, ' +
                                        'SUM(Total_Checklist_Items__c) totalTasks, ' +
                                        'SUM(Total_Completed_Items__c) completedTasks ' +
                                        'FROM Course_Checklist__c ' +
                                        'WHERE Student__c IN :contactIds';
                
                if (String.isNotBlank(checklistStatus)) {
                    aggregateQuery += ' AND Status__c = :checklistStatus';
                }
                
                aggregateQuery += ' GROUP BY Student__c';
                
                List<AggregateResult> aggResults = Database.query(aggregateQuery);
                for (AggregateResult ar : aggResults) {
                    checklistStats.put((Id)ar.get('Student__c'), ar);
                }

                // Aggregate overdue checklist items per student
                // Note: Date.today() and static Set cannot be used as inline bind vars in dynamic SOQL;
                // assign to local variables first.
                Date todayDate = Date.today();
                Set<String> overdueExcluded = OVERDUE_EXCLUDED_STATUSES;
                String overdueQuery = 'SELECT Course_Checklist__r.Student__c studentId, COUNT(Id) overdueCount ' +
                                      'FROM Course_Checklist_Item__c ' +
                                      'WHERE Course_Checklist__r.Student__c IN :contactIds ' +
                                      'AND Due_Date__c < :todayDate ' +
                                      'AND Status__c NOT IN :overdueExcluded';

                if (String.isNotBlank(checklistStatus)) {
                    overdueQuery += ' AND Course_Checklist__r.Status__c = :checklistStatus';
                }

                overdueQuery += ' GROUP BY Course_Checklist__r.Student__c';

                for (AggregateResult overdueAr : Database.query(overdueQuery)) {
                    Id studentId = (Id)overdueAr.get('studentId');
                    Decimal overdueDecimal = (Decimal)overdueAr.get('overdueCount');
                    overdueCountsByStudent.put(studentId, overdueDecimal != null ? overdueDecimal.intValue() : 0);
                }
            }
            
            // Build student wrappers
            for (ProgramEnrollment pe : enrollments) {
                StudentWrapper sw = new StudentWrapper();
                // Student details from Contact via ContactId
                sw.contactId = pe.ContactId;
                sw.studentName = pe.Contact.Name;
                sw.email = pe.Contact.Email;
                sw.hasOptedOut = pe.Contact.HasOptedOutOfEmail == true;
                
                // Program details from Program via ProgramId
                sw.program = pe.Program != null ? pe.Program.Name : '';
                sw.programId = pe.ProgramId;
                
                // Term details from Academic_Term__c
                sw.termId = pe.Academic_Term__c;
                sw.termName = pe.Academic_Term__r != null ? pe.Academic_Term__r.Name : '';
                sw.term = sw.termName; // For backward compatibility
                
                if (checklistStats.containsKey(pe.ContactId)) {
                    AggregateResult ar = checklistStats.get(pe.ContactId);
                    sw.totalChecklistsCount = (Integer)ar.get('totalChecklists');
                    
                    // Fix: SUM returns Decimal, not Integer
                    Decimal totalTasksDecimal = (Decimal)ar.get('totalTasks');
                    Decimal completedTasksDecimal = (Decimal)ar.get('completedTasks');
                    
                    Integer totalTasks = totalTasksDecimal != null ? totalTasksDecimal.intValue() : 0;
                    Integer completedTasks = completedTasksDecimal != null ? completedTasksDecimal.intValue() : 0;
                    
                    sw.totalTasksCount = totalTasks;
                    sw.completedTasksCount = completedTasks;
                    sw.pendingTasksCount = Math.max(0, totalTasks - completedTasks);
                    sw.overallCompletion = totalTasks > 0
                        ? ((Decimal.valueOf(completedTasks) * 100) / Decimal.valueOf(totalTasks)).setScale(2)
                        : 0;
                } else {
                    sw.overallCompletion = 0;
                    sw.totalChecklistsCount = 0;
                    sw.totalTasksCount = 0;
                    sw.completedTasksCount = 0;
                    sw.pendingTasksCount = 0;
                }

                sw.overdueCount = overdueCountsByStudent.containsKey(pe.ContactId)
                    ? overdueCountsByStudent.get(pe.ContactId)
                    : 0;
                
                response.students.add(sw);
            }
            
            response.pageNumber = pageNumber;
            response.hasMore = (offset + PAGE_SIZE) < response.totalCount;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching students: ' + e.getMessage());
        }
        
        return response;
    }

    private static Boolean hasGlobalStudentAccess(String profileName) {
        if (String.isBlank(profileName)) {
            return false;
        }

        String normalizedProfile = profileName.trim().toLowerCase();
        return normalizedProfile == 'system administrator' || normalizedProfile.contains('asa');
    }
    
    /**
     * @description Fetches all checklists for a specific student
     * @param contactId Student Contact ID
     * @param checklistTypeFilter Optional filter for checklist type (Course/Baseline)
     * @return List<ChecklistWrapper> List of checklists
     */
    @AuraEnabled(cacheable=true)
    public static List<ChecklistWrapper> getStudentChecklists(Id contactId, String checklistTypeFilter) {
        List<ChecklistWrapper> wrappers = new List<ChecklistWrapper>();
        
        try {
            String query = 'SELECT Id, Name, Checklist_Type__c, Status__c, ' +
                          'Completion_Percentage__c, Total_Checklist_Items__c, ' +
                          'Total_Completed_Items__c, Course_Offering__r.Name, ' +
                          'Assigned_To__r.Name, Start_Date__c, End_Date__c ' +
                          'FROM Course_Checklist__c ' +
                          'WHERE Student__c = :contactId';
            
            if (String.isNotBlank(checklistTypeFilter)) {
                query += ' AND Checklist_Type__c = :checklistTypeFilter';
            }
            
            query += ' ORDER BY CreatedDate DESC';
            
            List<Course_Checklist__c> checklists = Database.query(query);
            
            for (Course_Checklist__c cl : checklists) {
                ChecklistWrapper cw = new ChecklistWrapper();
                cw.checklistId = cl.Id;
                cw.checklistName = cl.Name;
                cw.checklistType = cl.Checklist_Type__c;
                cw.completionPercentage = cl.Completion_Percentage__c != null ? 
                                          cl.Completion_Percentage__c.setScale(2) : 0;
                cw.status = cl.Status__c;
                cw.totalTasks = cl.Total_Checklist_Items__c != null ? 
                                cl.Total_Checklist_Items__c.intValue() : 0;
                cw.completedTasks = cl.Total_Completed_Items__c != null ? 
                                    cl.Total_Completed_Items__c.intValue() : 0;
                cw.pendingTasks = cw.totalTasks - cw.completedTasks;
                cw.courseOffering = cl.Course_Offering__r != null ? cl.Course_Offering__r.Name : '';
                cw.assignedTo = cl.Assigned_To__r != null ? cl.Assigned_To__r.Name : '';
                cw.startDate = cl.Start_Date__c;
                cw.endDate = cl.End_Date__c;
                
                wrappers.add(cw);
            }
            
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching checklists: ' + e.getMessage());
        }
        
        return wrappers;
    }
    
    /**
     * @description Fetches tasks for a specific checklist (lazy loaded)
     * @param checklistId Course Checklist ID
     * @param taskStatusFilter Optional filter for task status
     * @return List<TaskWrapper> List of tasks
     */
    @AuraEnabled(cacheable=true)
    public static List<TaskWrapper> getChecklistTasks(Id checklistId, String taskStatusFilter) {
        List<TaskWrapper> wrappers = new List<TaskWrapper>();
        
        try {
            String query = 'SELECT Id, Subject__c, Status__c, Due_Date__c, ' +
                          'Priority__c, Activity_Type__c, Description__c ' +
                          'FROM Course_Checklist_Item__c ' +
                          'WHERE Course_Checklist__c = :checklistId';
            
            if (String.isNotBlank(taskStatusFilter)) {
                query += ' AND Status__c = :taskStatusFilter';
            }
            
            query += ' ORDER BY Due_Date__c ASC NULLS LAST, Priority__c ASC';
            
            List<Course_Checklist_Item__c> tasks = Database.query(query);
            
            for (Course_Checklist_Item__c task : tasks) {
                TaskWrapper tw = new TaskWrapper();
                tw.taskId = task.Id;
                tw.subject = task.Subject__c;
                tw.status = task.Status__c;
                tw.dueDate = task.Due_Date__c;
                tw.priority = task.Priority__c;
                tw.activityType = task.Activity_Type__c;
                tw.description = task.Description__c;
                
                wrappers.add(tw);
            }
            
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching tasks: ' + e.getMessage());
        }
        
        return wrappers;
    }
    
    /**
     * @description Sends bulk email to selected students
     * @param contactIds List of Contact IDs to send email to
     * @param templateId EmailTemplate ID for template-based send (optional)
     * @param subject Email subject (required for custom compose when templateId is blank)
     * @param body Email body (required for custom compose when templateId is blank)
     * @return EmailResponse Response with success/failure info
     */
    @AuraEnabled
    public static EmailResponse sendBulkEmail(List<Id> contactIds, String templateId, String subject, String body, List<Id> contentDocIds) {
        EmailResponse response = new EmailResponse();
        response.success = false;
        response.sentCount = 0;
        response.skippedCount = 0;
        
        try {
            // Validate input
            if (contactIds == null || contactIds.isEmpty()) {
                response.errorMessage = 'No students selected';
                return response;
            }
            
            Boolean isTemplateMode = String.isNotBlank(templateId);
            
            if (!isTemplateMode && (String.isBlank(subject) || String.isBlank(body))) {
                response.errorMessage = 'Email subject and body are required';
                return response;
            }
            
            if (contactIds.size() > MAX_EMAIL_RECIPIENTS) {
                response.errorMessage = 'Maximum ' + MAX_EMAIL_RECIPIENTS + ' recipients allowed. Selected: ' + contactIds.size();
                return response;
            }
            
            // Resolve the "ISB ASA Admin" org-wide email address (used as sender on all emails)
            Id owaId = null;
            List<OrgWideEmailAddress> owaList = [
                SELECT Id FROM OrgWideEmailAddress
                WHERE DisplayName = 'ISB ASA Admin'
                LIMIT 1
            ];
            if (!owaList.isEmpty()) {
                owaId = owaList[0].Id;
            }

            // Pre-build file attachments from uploaded ContentDocuments (custom mode only)
            List<Messaging.EmailFileAttachment> fileAttachments = new List<Messaging.EmailFileAttachment>();
            if (!isTemplateMode && contentDocIds != null && !contentDocIds.isEmpty()) {
                List<ContentVersion> cvList = [
                    SELECT Title, VersionData, FileExtension
                    FROM ContentVersion
                    WHERE ContentDocumentId IN :contentDocIds
                    AND IsLatest = true
                ];
                for (ContentVersion cv : cvList) {
                    Messaging.EmailFileAttachment efa = new Messaging.EmailFileAttachment();
                    String fileName = cv.Title;
                    if (String.isNotBlank(cv.FileExtension) && !cv.Title.endsWith('.' + cv.FileExtension)) {
                        fileName += '.' + cv.FileExtension;
                    }
                    efa.setFileName(fileName);
                    efa.setBody(cv.VersionData);
                    fileAttachments.add(efa);
                }
            }
            
            // Fetch contacts with email addresses
            List<Contact> contacts = [
                SELECT Id, Name, FirstName, Email
                FROM Contact
                WHERE Id IN :contactIds
            ];
            
            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
            List<Contact> emailedContacts = new List<Contact>();
            
            for (Contact c : contacts) {
                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                
                if (isTemplateMode) {
                    // Template-based send: Salesforce renders and personalises the template
                    email.setTargetObjectId(c.Id);
                    email.setTemplateId(templateId);
                    email.setSaveAsActivity(true);
                    if (owaId != null) {
                        email.setOrgWideEmailAddressId(owaId);
                    }
                } else {
                    // Custom compose: skip contacts with no email address
                    if (String.isBlank(c.Email)) {
                        response.skippedCount++;
                        response.skippedReasons.add(c.Name + ': No email address');
                        continue;
                    }
                    // Personalise body with merge-field substitution
                    String personalizedBody = body.replace('{!Contact.Name}', c.Name)
                                                  .replace('{!Contact.FirstName}', c.FirstName != null ? c.FirstName : c.Name);
                    email.setToAddresses(new String[]{c.Email});
                    email.setSubject(subject);
                    email.setHtmlBody(personalizedBody);
                    email.setSaveAsActivity(true);
                    email.setTargetObjectId(c.Id);
                    if (owaId != null) {
                        email.setOrgWideEmailAddressId(owaId);
                    }
                    if (!fileAttachments.isEmpty()) {
                        email.setFileAttachments(fileAttachments);
                    }
                }
                
                emails.add(email);
                emailedContacts.add(c);
            }
            
            if (emails.isEmpty()) {
                response.errorMessage = 'No valid email addresses found';
                return response;
            }
            
            // Send emails
            List<Messaging.SendEmailResult> results = Messaging.sendEmail(emails);
            
            // Process results — results[i] aligns with emailedContacts[i]
            for (Integer i = 0; i < results.size(); i++) {
                if (results[i].isSuccess()) {
                    response.sentCount++;
                } else {
                    response.skippedCount++;
                    String errorMsg = 'Error: ';
                    for (Messaging.SendEmailError err : results[i].getErrors()) {
                        errorMsg += err.getMessage() + '; ';
                    }
                    response.skippedReasons.add(emailedContacts[i].Name + ': ' + errorMsg);
                }
            }
            
            response.success = response.sentCount > 0;
            
        } catch (Exception e) {
            response.errorMessage = 'Error sending emails: ' + e.getMessage();
        }
        
        return response;
    }
    
    /**
     * @description Gets picklist values for filters
     * @return Map<String, List<String>> Picklist values
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, List<String>> getFilterPicklistValues() {
        Map<String, List<String>> picklistValues = new Map<String, List<String>>();
        
        try {
            // Checklist Type
            List<String> checklistTypes = new List<String>();
            Schema.DescribeFieldResult fieldResult = Course_Checklist__c.Checklist_Type__c.getDescribe();
            for (Schema.PicklistEntry entry : fieldResult.getPicklistValues()) {
                if (entry.isActive()) {
                    checklistTypes.add(entry.getValue());
                }
            }
            picklistValues.put('checklistTypes', checklistTypes);
            
            // Checklist Status
            List<String> checklistStatuses = new List<String>();
            fieldResult = Course_Checklist__c.Status__c.getDescribe();
            for (Schema.PicklistEntry entry : fieldResult.getPicklistValues()) {
                if (entry.isActive()) {
                    checklistStatuses.add(entry.getValue());
                }
            }
            picklistValues.put('checklistStatuses', checklistStatuses);
            
            // Task Status
            List<String> taskStatuses = new List<String>();
            fieldResult = Course_Checklist_Item__c.Status__c.getDescribe();
            for (Schema.PicklistEntry entry : fieldResult.getPicklistValues()) {
                if (entry.isActive()) {
                    taskStatuses.add(entry.getValue());
                }
            }
            picklistValues.put('taskStatuses', taskStatuses);
            
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching picklist values: ' + e.getMessage());
        }
        
        return picklistValues;
    }
    
    /**
     * @description Gets ALL programs (not filtered by advisor)
     * @return List<PicklistOption> List of all program options
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getAdvisorPrograms() {
        List<PicklistOption> options = new List<PicklistOption>();
        try {
            List<Program> programs = [
                SELECT Id, Name
                FROM Program
                WHERE IsActive = true
                ORDER BY Name ASC
                LIMIT 200
            ];
            for (Program p : programs) {
                options.add(new PicklistOption(p.Name, p.Id));
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching programs: ' + e.getMessage());
        }
        return options;
    }
    
    /**
     * @description Gets ALL academic terms (not filtered by advisor)
     * @return List<PicklistOption> List of all term options
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getAdvisorTerms(String programId) {
        List<PicklistOption> options = new List<PicklistOption>();
        try {
            // Terms (AcademicSession) are dependent on the selected Program
            String query = 'SELECT Id, Name FROM AcademicSession WHERE IsActive = true';
            if (String.isNotBlank(programId)) {
                query += ' AND Program__c = :programId';
            }
            query += ' ORDER BY Name DESC LIMIT 200';
            List<AcademicSession> sessions = Database.query(query);
            for (AcademicSession s : sessions) {
                options.add(new PicklistOption(s.Name, s.Id));
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching terms: ' + e.getMessage());
        }
        return options;
    }
    
    /**
     * @description Gets academic sessions filtered by academic term
     * @param termId Academic Term ID to filter sessions
     * @return List<PicklistOption> List of session options for the term
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getAcademicSessions(String termId) {
        List<PicklistOption> options = new List<PicklistOption>();
        
        try {
            List<AcademicSession> sessions;
            
            // Return all sessions (no term relationship filter)
            sessions = [
                SELECT Id, Name
                FROM AcademicSession
                ORDER BY Name ASC
            ];
            
            for (AcademicSession session : sessions) {
                options.add(new PicklistOption(session.Name, session.Id));
            }
            
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching sessions: ' + e.getMessage());
        }
        
        return options;
    }
    
    /**
     * @description Wrapper class for picklist options
     */
    public class PicklistOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
        
        public PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    /**
     * @description Gets campus/location options optionally filtered by program
     * @param programId Program Account ID (optional)
     * @return List<PicklistOption> List of location options
     */
    /**
     * @description Gets all campus/location options — independent of program or term filters
     * @return List<PicklistOption> List of location options
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getLocations() {
        List<PicklistOption> options = new List<PicklistOption>();
        try {
            // Use dynamic query to avoid conflict with Apex built-in System.Location type
            List<SObject> locs = Database.query(
                'SELECT Id, Name FROM Location ORDER BY Name ASC LIMIT 200'
            );
            for (SObject loc : locs) {
                options.add(new PicklistOption((String)loc.get('Name'), (String)loc.get('Id')));
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching locations: ' + e.getMessage());
        }
        return options;
    }

    /**
     * @description Gets course offerings filtered by program, location and term
     * @param programId Program Account ID
     * @param locationId Location/Campus ID
     * @param termId Academic Session ID
     * @return List<PicklistOption> List of course offering options
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getCourseOfferings(String programId, String locationId, String termId) {
        List<PicklistOption> options = new List<PicklistOption>();
        try {
            // Course Offerings are dependent on all three filters (each applied only when a value is set)
            String query = 'SELECT Id, Name FROM CourseOffering WHERE IsActive = true';
            if (String.isNotBlank(programId)) {
                query += ' AND Program__c = :programId';
            }
            if (String.isNotBlank(locationId)) {
                query += ' AND Location__c = :locationId';
            }
            if (String.isNotBlank(termId)) {
                // Academic_Term__c is consistent with the ProgramEnrollment term filter
                query += ' AND Academic_Term__c = :termId';
            }
            query += ' ORDER BY Name ASC LIMIT 200';
            List<CourseOffering> offerings = Database.query(query);
            for (CourseOffering co : offerings) {
                options.add(new PicklistOption(co.Name, co.Id));
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching course offerings: ' + e.getMessage());
        }
        return options;
    }

    /**
     * @description Gets active email templates
     * @return List<PicklistOption> List of email template options
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getEmailTemplates() {
        List<PicklistOption> options = new List<PicklistOption>();
        try {
            List<EmailTemplate> templates = [
                SELECT Id, Name, Subject
                FROM EmailTemplate
                WHERE IsActive = true
                ORDER BY Name ASC
                LIMIT 200
            ];
            for (EmailTemplate et : templates) {
                options.add(new PicklistOption(et.Name, et.Id));
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching email templates: ' + e.getMessage());
        }
        return options;
    }

    /**
     * @description Gets a single email template for preview
     * @param templateId EmailTemplate ID
     * @return EmailTemplate record with subject and body
     */
    @AuraEnabled(cacheable=true)
    public static EmailTemplate getEmailTemplatePreview(String templateId) {
        try {
            return [
                SELECT Id, Name, Subject, HtmlValue, Body
                FROM EmailTemplate
                WHERE Id = :templateId
                LIMIT 1
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching template: ' + e.getMessage());
        }
    }
}