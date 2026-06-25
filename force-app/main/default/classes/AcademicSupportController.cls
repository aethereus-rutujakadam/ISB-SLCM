public without sharing class AcademicSupportController {

    // Wrapper class to send a clean, single payload to the LWC
    public class SupportDirectoryWrapper {
        @AuraEnabled public Contact primaryAdvisor { get; set; }
        @AuraEnabled public List<Contact> allAdvisors { get; set; } 
        @AuraEnabled public List<Contact> academicAssociates { get; set; }
        @AuraEnabled public List<Contact> tutors { get; set; }
        @AuraEnabled public Boolean hasError { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        @AuraEnabled public Id studentContactId { get; set; }  // Exposed so LWC can use as reactive wire param
        @AuraEnabled public Id primaryAdvisorUserId { get; set; } // Advisor User ID for availability slot queries
        
        public SupportDirectoryWrapper() {
            this.allAdvisors = new List<Contact>();
            this.academicAssociates = new List<Contact>();
            this.tutors = new List<Contact>();
            this.hasError = false;
        }
    }

    @AuraEnabled(cacheable=true)
    public static SupportDirectoryWrapper getSupportDirectory() {
        SupportDirectoryWrapper wrapper = new SupportDirectoryWrapper();
        
        try {
            // 1. Get Logged-in Student's Contact ID
            Id userId = UserInfo.getUserId();
            User currentUser = [SELECT ContactId FROM User WHERE Id = :userId LIMIT 1];
            
            if (currentUser.ContactId == null) {
                wrapper.hasError = true;
                wrapper.errorMessage = 'No associated Student Contact found for this user. Please log in as a student.';
                return wrapper;
            }

            // Expose the student Contact ID so the LWC can pass it as
            // a reactive parameter to the getStudentChecklists wire call
            wrapper.studentContactId = currentUser.ContactId;

            // 2. Fetch Primary Advisor via active ProgramEnrollment
            List<ProgramEnrollment> enrollments = [
                SELECT Primary_Advisor__r.Id, 
                       Primary_Advisor__r.Name, 
                       Primary_Advisor__r.Primary_Campus__r.Name, 
                       Primary_Advisor__r.Email,
                       Primary_Advisor__r.Linked_User_Id__c
                FROM ProgramEnrollment 
                WHERE ContactId = :currentUser.ContactId 
                AND IsActive = true
                LIMIT 1
            ];
            
            if (!enrollments.isEmpty() && enrollments[0].Primary_Advisor__r != null) {
                wrapper.primaryAdvisor = enrollments[0].Primary_Advisor__r;
                wrapper.primaryAdvisorUserId = (Id) enrollments[0].Primary_Advisor__r.Linked_User_Id__c;
            }

            // 3. Fetch ALL Advisors for the Directory Tab
            wrapper.allAdvisors = [
                SELECT Id, Name, Primary_Campus__r.Name
                FROM Contact 
                WHERE RecordType.DeveloperName = 'Advisor' //AND Active_Status__c = 'Active'
            ];

            // 4. Fetch Academic Associates
            wrapper.academicAssociates = [
                SELECT Id, Name, Primary_Campus__r.Name
                FROM Contact 
                WHERE RecordType.DeveloperName = 'Academic_Associate' //AND Active_Status__c = 'Active'
            ];

            // 5. Fetch Tutors
            wrapper.tutors = [
                SELECT Id, Name
                FROM Contact 
                WHERE RecordType.DeveloperName = 'Tutor' //AND Active_Status__c = 'Active'
            ];

        } catch (Exception e) {
            System.debug('Error fetching support directory: ' + e.getMessage());
            wrapper.hasError = true;
            wrapper.errorMessage = 'An error occurred while loading your support team.';
        }
        
        return wrapper;
    }

    @AuraEnabled
    public static String createAppointmentRequest(Appointment_Request__c requestRecord, String startISO, String endISO, String meetingTitle) {
        try {
            // 1. Get Logged-in Student via User.ContactId
            Id userId = UserInfo.getUserId();
            User currentUser = [SELECT ContactId FROM User WHERE Id = :userId LIMIT 1];
            
            if (currentUser.ContactId == null) {
                throw new AuraHandledException('Invalid Student User: No associated Contact found.');
            }
            
            requestRecord.Student__c = currentUser.ContactId;
            requestRecord.Requested_User__c = userId;
            requestRecord.Status__c  = 'Pending';
            if (String.isNotBlank(meetingTitle)) {
                requestRecord.Name = meetingTitle.trim();
            }
            
            // 2. Resolve Primary Advisor from active ProgramEnrollment (Contact → User via Linked_User_Id__c)
            List<ProgramEnrollment> enrollments = [
                SELECT Primary_Advisor__c, Primary_Advisor__r.Linked_User_Id__c
                FROM ProgramEnrollment 
                WHERE ContactId = :currentUser.ContactId 
                AND IsActive = true
                LIMIT 1
            ];
            
            if (enrollments.isEmpty() || enrollments[0].Primary_Advisor__c == null) {
                throw new AuraHandledException('No active Primary Advisor found for your enrollment. Please contact the support office.');
            }
            if (enrollments[0].Primary_Advisor__r.Linked_User_Id__c == null) {
                throw new AuraHandledException('Your Primary Advisor does not have a linked Salesforce User account. Please contact the support office.');
            }
            
            requestRecord.Primary_Advisor__c = enrollments[0].Primary_Advisor__r.Linked_User_Id__c;
            requestRecord.OwnerId            = enrollments[0].Primary_Advisor__r.Linked_User_Id__c;

            // 3. Parse start/end DateTimes from ISO strings (format: yyyy-MM-ddTHH:mm:ss, user timezone)
            Datetime startDT = Datetime.valueOf(startISO.replace('T', ' '));
            Datetime endDT   = Datetime.valueOf(endISO.replace('T', ' '));
            
            requestRecord.Start_DateTime__c    = startDT;
            requestRecord.End_DateTime__c      = endDT;
            // Duration is derived at read-time from Start/End; Minutes_of_Meeting__c stores meeting transcript.

            // 4. RANGE-OVERLAP double-booking check (catches partial/exact/enclosing conflicts)
            List<Appointment_Request__c> overlaps = [
                SELECT Id
                FROM Appointment_Request__c
                WHERE Status__c IN ('Pending', 'Approved')
                AND Primary_Advisor__c = :requestRecord.Primary_Advisor__c
                AND Start_DateTime__c  < :endDT
                AND End_DateTime__c    > :startDT
                LIMIT 1
            ];
            
            if (!overlaps.isEmpty()) {
                throw new AuraHandledException('This time slot is no longer available. Please go back and select a different slot.');
            }

            // 5. Insert
            insert requestRecord;
            AdvisingNotificationService.notifyStudentOfAppointmentRequestSubmission(
                requestRecord,
                userId
            );
            AdvisingNotificationService.notifyAdvisorOfAppointmentRequest(
                new List<Appointment_Request__c>{ requestRecord }
            );
            return requestRecord.Id;
            
        } catch (AuraHandledException auraEx) {
            throw auraEx; 
        } catch (Exception e) {
            System.debug('Error inserting Appointment Request: ' + e.getMessage());
            throw new AuraHandledException('Failed to submit appointment request. System Error: ' + e.getMessage());
        }
    }

    // ===== ADVISING TASKS / COURSE CHECKLIST METHODS =====

    // Wrapper class for Course Checklist with Items
    public class ChecklistWrapper {
        @AuraEnabled public Id checklistId { get; set; }
        @AuraEnabled public String checklistName { get; set; }
        @AuraEnabled public String checklistType { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Decimal completionPercentage { get; set; }
        @AuraEnabled public List<ChecklistItemWrapper> items { get; set; }
        @AuraEnabled public Boolean isExpanded { get; set; }
        
        public ChecklistWrapper() {
            this.items = new List<ChecklistItemWrapper>();
            this.isExpanded = false;
        }
    }

    public class ChecklistItemWrapper {
        @AuraEnabled public Id itemId { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public Date dueDate { get; set; }
        @AuraEnabled public String priority { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String comments { get; set; }
        @AuraEnabled public String role { get; set; }
        @AuraEnabled public Boolean isEditable { get; set; }
        @AuraEnabled public Boolean isOverdue { get; set; }
    }

    public class ChecklistDataWrapper {
        @AuraEnabled public List<ChecklistWrapper> checklists { get; set; }
        @AuraEnabled public Boolean hasError { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        
        public ChecklistDataWrapper() {
            this.checklists = new List<ChecklistWrapper>();
            this.hasError = false;
        }
    }

    @AuraEnabled(cacheable=true)
    public static ChecklistDataWrapper getStudentChecklists(Id studentContactId) {
        ChecklistDataWrapper wrapper = new ChecklistDataWrapper();
        
        try {
            // Validate the incoming Contact ID — must not be null
            if (studentContactId == null) {
                wrapper.hasError = true;
                wrapper.errorMessage = 'Student Contact ID is required to load advising tasks.';
                return wrapper;
            }

            // Security guard: confirm the calling user owns this Contact
            Id userId = UserInfo.getUserId();
            User currentUser = [SELECT ContactId FROM User WHERE Id = :userId LIMIT 1];
            if (currentUser.ContactId == null || currentUser.ContactId != studentContactId) {
                wrapper.hasError = true;
                wrapper.errorMessage = 'You are not authorised to view these advising tasks.';
                return wrapper;
            }

            // 2. Fetch all Course Checklists for the Student with Items using subquery
            List<Course_Checklist__c> checklists = [
                SELECT Id,
                       Name,
                       Checklist_Type__c, 
                       Status__c, 
                       Completion_Percentage__c,
                       (SELECT Id, 
                               Subject__c, 
                               Description__c, 
                               Due_Date__c, 
                               Priority__c, 
                               Status__c, 
                               Comments__c, 
                               Role__c
                        FROM Course_Checklist_Items__r
                        ORDER BY Due_Date__c ASC NULLS LAST, Priority__c DESC)
                FROM Course_Checklist__c
                WHERE Student__c = :studentContactId
                ORDER BY Status__c, Checklist_Type__c
            ];

            // 3. Transform to wrapper
            Date today = Date.today();
            for (Course_Checklist__c checklist : checklists) {
                ChecklistWrapper clWrapper = new ChecklistWrapper();
                clWrapper.checklistId = checklist.Id;
                clWrapper.checklistName = checklist.Name;
                clWrapper.checklistType = checklist.Checklist_Type__c;
                clWrapper.status = checklist.Status__c;
                clWrapper.completionPercentage = checklist.Completion_Percentage__c != null ? checklist.Completion_Percentage__c : 0;
                
                // Process each item
                for (Course_Checklist_Item__c item : checklist.Course_Checklist_Items__r) {
                    ChecklistItemWrapper itemWrapper = new ChecklistItemWrapper();
                    itemWrapper.itemId = item.Id;
                    itemWrapper.subject = item.Subject__c;
                    itemWrapper.description = item.Description__c;
                    itemWrapper.dueDate = item.Due_Date__c;
                    itemWrapper.priority = item.Priority__c;
                    itemWrapper.status = item.Status__c;
                    itemWrapper.comments = item.Comments__c;
                    itemWrapper.role = item.Role__c;
                    
                    // Student owns this checklist context, so permit task actions in UI.
                    itemWrapper.isEditable = true;
                    
                    // Determine if overdue
                    itemWrapper.isOverdue = (item.Due_Date__c != null && 
                                            item.Due_Date__c < today && 
                                            item.Status__c != 'Completed' && 
                                            item.Status__c != 'Closed' &&
                                            item.Status__c != 'Waived');
                    
                    clWrapper.items.add(itemWrapper);
                }
                
                wrapper.checklists.add(clWrapper);
            }

        } catch (Exception e) {
            System.debug('Error fetching student checklists: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            wrapper.hasError = true;
            wrapper.errorMessage = 'An error occurred while loading your advising tasks.';
        }
        
        return wrapper;
    }

    @AuraEnabled
    public static String updateChecklistItem(Id itemId, String newStatus, String newComments) {
        try {
            // Security: Verify the item belongs to the logged-in student
            Id userId = UserInfo.getUserId();
            User currentUser = [SELECT ContactId FROM User WHERE Id = :userId LIMIT 1];
            
            if (currentUser.ContactId == null) {
                throw new AuraHandledException('Invalid Student User: No associated Contact found.');
            }

            // Fetch the item with its parent checklist
            Course_Checklist_Item__c item = [
                SELECT Id, Status__c, Comments__c, Role__c, Course_Checklist__r.Student__c
                FROM Course_Checklist_Item__c
                WHERE Id = :itemId
                LIMIT 1
            ];

            // Verify the checklist belongs to this student
            if (item.Course_Checklist__r.Student__c != currentUser.ContactId) {
                throw new AuraHandledException('You do not have permission to update this item.');
            }

            // Update fields
            if (String.isNotBlank(newStatus)) {
                item.Status__c = newStatus;
            }
            if (newComments != null) { // Allow empty string to clear comments
                item.Comments__c = newComments;
            }

            update item;
            return 'Success';
            
        } catch (AuraHandledException auraEx) {
            throw auraEx;
        } catch (Exception e) {
            System.debug('Error updating checklist item: ' + e.getMessage());
            throw new AuraHandledException('Failed to update task. Error: ' + e.getMessage());
        }
    }

    // ===== APPOINTMENT HISTORY METHODS =====

    public class AppointmentWrapper implements Comparable {
        @AuraEnabled public Id      id               { get; set; }
        @AuraEnabled public String  name             { get; set; }
        @AuraEnabled public String  status           { get; set; }
        @AuraEnabled public String  statusClass      { get; set; }
        @AuraEnabled public String  requestType      { get; set; }
        @AuraEnabled public String  mode             { get; set; }
        @AuraEnabled public String  reason           { get; set; }
        @AuraEnabled public Datetime startDateTime   { get; set; }
        @AuraEnabled public Datetime endDateTime     { get; set; }
        @AuraEnabled public Decimal  durationMinutes { get; set; }
        @AuraEnabled public String  advisorName      { get; set; }
        @AuraEnabled public String  eventId          { get; set; }
        @AuraEnabled public String  rejectionReason  { get; set; }
        @AuraEnabled public Datetime createdDate     { get; set; }
        @AuraEnabled public Boolean  isPending       { get; set; }
        @AuraEnabled public Boolean  isApproved      { get; set; }
        @AuraEnabled public Boolean  isRejected      { get; set; }
        @AuraEnabled public Boolean  isCancelled     { get; set; }
        @AuraEnabled public String   notesAndRemarks { get; set; }
        @AuraEnabled public Boolean  canBookAgain    { get; set; }

        public Integer compareTo(Object otherObj) {
            AppointmentWrapper other = (AppointmentWrapper)otherObj;
            Long thisTime = this.startDateTime != null ? this.startDateTime.getTime() : 0;
            Long otherTime = other != null && other.startDateTime != null ? other.startDateTime.getTime() : 0;

            if (thisTime == otherTime) {
                return 0;
            }
            return thisTime > otherTime ? -1 : 1;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<AppointmentWrapper> getStudentAppointments(Id studentContactId) {
        List<AppointmentWrapper> results = new List<AppointmentWrapper>();
        try {
            // Always use the running user's own Contact — ignore the parameter
            // to avoid 15-vs-18 char ID mismatches and ID-type casting issues.
            Id userId = UserInfo.getUserId();
            User currentUser = [SELECT ContactId FROM User WHERE Id = :userId LIMIT 1];
            if (currentUser.ContactId == null) {
                return results; // Community user not linked to a Contact — return empty
            }
            Id contactId = currentUser.ContactId;

            List<Appointment_Request__c> records = [
                SELECT Id, Name, Status__c, Request_Type__c, Reason__c,
                       Start_DateTime__c, End_DateTime__c,
                       Primary_Advisor__c, EventId__c, Rejection_Reason__c,
                       Notes_and_Remarks__c, CreatedDate
                FROM Appointment_Request__c
                WHERE Student__c = :contactId
                ORDER BY Start_DateTime__c DESC NULLS LAST
            ];

            Set<Id> linkedEventIds = new Set<Id>();
            for (Appointment_Request__c rec : records) {
                if (String.isBlank(rec.EventId__c)) {
                    continue;
                }
                try {
                    linkedEventIds.add((Id)rec.EventId__c);
                } catch (Exception ignoreEx) {
                    // Ignore malformed values and continue.
                }
            }

            List<Event> standaloneEvents;
            if (linkedEventIds.isEmpty()) {
                standaloneEvents = [
                    SELECT Id, Subject, StartDateTime, EndDateTime, DurationInMinutes,
                           OwnerId, Location, Description, CreatedDate
                    FROM Event
                    WHERE WhoId = :contactId
                    AND OwnerId != :userId
                    ORDER BY StartDateTime DESC NULLS LAST
                    LIMIT 100
                ];
            } else {
                standaloneEvents = [
                    SELECT Id, Subject, StartDateTime, EndDateTime, DurationInMinutes,
                           OwnerId, Location, Description, CreatedDate
                    FROM Event
                    WHERE WhoId = :contactId
                    AND OwnerId != :userId
                    AND Id NOT IN :linkedEventIds
                    ORDER BY StartDateTime DESC NULLS LAST
                    LIMIT 100
                ];
            }

            // Separately resolve advisor User names to avoid relationship traversal
            // exceptions when the related User is not visible in community context.
            Set<Id> advisorUserIds = new Set<Id>();
            for (Appointment_Request__c rec : records) {
                if (rec.Primary_Advisor__c != null) advisorUserIds.add(rec.Primary_Advisor__c);
            }
            for (Event evt : standaloneEvents) {
                if (evt.OwnerId != null) {
                    advisorUserIds.add(evt.OwnerId);
                }
            }
            Map<Id, String> advisorNames = new Map<Id, String>();
            if (!advisorUserIds.isEmpty()) {
                for (User u : [SELECT Id, FirstName, LastName FROM User WHERE Id IN :advisorUserIds]) {
                    // Display FirstName + LastName instead of Alias (Nickname)
                    String fullName = (String.isNotBlank(u.FirstName) ? u.FirstName : '') + 
                                    (String.isNotBlank(u.FirstName) && String.isNotBlank(u.LastName) ? ' ' : '') + 
                                    (String.isNotBlank(u.LastName) ? u.LastName : '');
                    advisorNames.put(u.Id, fullName.trim());
                }
            }

            for (Appointment_Request__c rec : records) {
                AppointmentWrapper w   = new AppointmentWrapper();
                w.id                   = rec.Id;
                w.name                 = rec.Name;
                w.status               = rec.Status__c;
                w.statusClass          = getApptStatusClass(rec.Status__c);
                w.requestType          = rec.Request_Type__c;
                w.reason               = rec.Reason__c;
                w.startDateTime        = rec.Start_DateTime__c;
                w.endDateTime          = rec.End_DateTime__c;
                w.durationMinutes      = rec.Start_DateTime__c != null && rec.End_DateTime__c != null
                    ? Decimal.valueOf((rec.End_DateTime__c.getTime() - rec.Start_DateTime__c.getTime()) / 60000)
                    : null;
                w.advisorName          = advisorNames.containsKey(rec.Primary_Advisor__c) ? advisorNames.get(rec.Primary_Advisor__c) : '';
                w.eventId              = rec.EventId__c;
                w.rejectionReason      = rec.Rejection_Reason__c;
                w.createdDate          = rec.CreatedDate;
                w.isPending            = rec.Status__c == 'Pending';
                w.isApproved           = rec.Status__c == 'Approved';
                w.isRejected           = rec.Status__c == 'Rejected';
                w.isCancelled          = rec.Status__c == 'Cancelled';
                w.notesAndRemarks      = rec.Notes_and_Remarks__c;
                w.canBookAgain         = (rec.Status__c == 'Rejected' || rec.Status__c == 'Completed' || rec.Status__c == 'No-Show' || rec.Status__c == 'Cancelled');
                results.add(w);
            }

            for (Event evt : standaloneEvents) {
                AppointmentWrapper w   = new AppointmentWrapper();
                w.id                   = evt.Id;
                w.name                 = evt.Subject;
                w.status               = 'Scheduled';
                w.statusClass          = getApptStatusClass(w.status);
                w.requestType          = 'calendar';
                w.reason               = evt.Description;
                w.startDateTime        = evt.StartDateTime;
                w.endDateTime          = evt.EndDateTime;
                w.durationMinutes      = evt.DurationInMinutes != null
                    ? Decimal.valueOf(evt.DurationInMinutes)
                    : null;
                w.advisorName          = advisorNames.containsKey(evt.OwnerId) ? advisorNames.get(evt.OwnerId) : '';
                w.eventId              = (String)evt.Id;
                w.rejectionReason      = null;
                w.createdDate          = evt.CreatedDate;
                w.isPending            = false;
                w.isApproved           = false;
                w.isRejected           = false;
                w.isCancelled          = false;
                w.notesAndRemarks      = evt.Location;
                w.canBookAgain         = false;
                results.add(w);
            }

            results.sort();
        } catch (AuraHandledException auraEx) {
            throw auraEx;
        } catch (Exception e) {
            System.debug('getStudentAppointments error: ' + e.getMessage() + ' | ' + e.getStackTraceString());
            throw new AuraHandledException('Failed to load appointment history: ' + e.getMessage());
        }
        return results;
    }

    private static Decimal parseSafeDecimal(String val) {
        if (String.isBlank(val)) return null;
        try {
            return Decimal.valueOf(val.trim());
        } catch (Exception e) {
            return null;
        }
    }

    private static String getApptStatusClass(String status) {
        if (status == 'Pending')   return 'appt-status appt-status--pending';
        if (status == 'Approved')  return 'appt-status appt-status--approved';
        if (status == 'Rejected')  return 'appt-status appt-status--rejected';
        if (status == 'Completed') return 'appt-status appt-status--completed';
        if (status == 'No-Show')   return 'appt-status appt-status--noshow';
        if (status == 'Cancelled') return 'appt-status appt-status--cancelled';
        return 'appt-status';
    }
}