public without sharing class ExamSchedulerController {

    @AuraEnabled(cacheable=true)
    public static List<Examination> getExamSchedules(Id examinationId) {
        if (examinationId == null) return new List<Examination>();

        return [
            SELECT Id, Name,
                   Academic_Term__r.Name,
                   Course_Catalog__r.Name,
                   Date_of_Exam__c,
                   Time_of_Exam__c,
                   End_Time__c,
                   Duration_mins__c,
                   Venue__r.Name,
                   Exam_Venue__r.Name,
                   Program__r.Name,
                   Allott_No_of_AAs__c,
                   Academic_Session__r.Name,
                   Exam_Type__c,
                   Status
                   //Venue_Name__c
            FROM Examination
            WHERE Exam_Schedule__c = :examinationId
            ORDER BY Name ASC
        ];
    }

    @AuraEnabled
    public static Map<Id, Integer> getAAAllocationCounts(List<Id> examIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (examIds == null || examIds.isEmpty()) return counts;

        for (AggregateResult ar : [
            SELECT Exam__c examId, COUNT(Id) cnt
            FROM Exam_AA__c
            WHERE Exam__c IN :examIds
            GROUP BY Exam__c
        ]) {
            counts.put((Id) ar.get('examId'), Integer.valueOf(ar.get('cnt')));
        }

        List<Examination> updates = new List<Examination>();
        for (Id eid : counts.keySet()) {
            updates.add(new Examination(Id = eid, Allott_No_of_AAs__c = counts.get(eid)));
        }
System.debug('updates '+updates);
        if (!updates.isEmpty())
        try{
         update updates;
        }catch(Exception ex){
            System.debug('error '+ ex.getMessage());
        }

        return counts;
    }

    public class AssignmentResult {
        @AuraEnabled public Integer created;
        @AuraEnabled public List<Id> createdIds;
        @AuraEnabled public List<Id> duplicates;
        @AuraEnabled public List<String> errors;

        public AssignmentResult() {
            created = 0;
            createdIds = new List<Id>();
            duplicates = new List<Id>();
            errors = new List<String>();
        }
    }

    @AuraEnabled
    public static AssignmentResult createExamAA(List<Id> contactIds, List<Id> examIds, Date assignedOn) {
        AssignmentResult res = new AssignmentResult();

        if (contactIds == null || contactIds.isEmpty() ||
            examIds == null || examIds.isEmpty()) {
            return res;
        }
        Date assignDate = assignedOn != null ? assignedOn : Date.today();

        Map<String, Id> existingMap = new Map<String, Id>();
        for (Exam_AA__c exaa : [
            SELECT Id, Exam__c, Academic_Associate__c
            FROM Exam_AA__c
            WHERE Exam__c IN :examIds
              AND Academic_Associate__c IN :contactIds
        ]) {
            String key = exaa.Exam__c + '-' + exaa.Academic_Associate__c;
            existingMap.put(key, exaa.Id);
        }

        List<Exam_AA__c> inserts = new List<Exam_AA__c>();

        for (Id cId : contactIds) {
            for (Id eId : examIds) {
                String key = eId + '-' + cId;
                if (!existingMap.containsKey(key)) {
                    inserts.add(new Exam_AA__c(
                        Academic_Associate__c = cId,
                        Exam__c = eId,
                        Assigned_On__c = assignDate
                    ));
                } else {
                    res.duplicates.add(eId);
                }
            }
        }

        if (!inserts.isEmpty()) {
            Database.SaveResult[] results = Database.insert(inserts, false);
            for (Database.SaveResult sr : results) {
                if (sr.isSuccess()) res.createdIds.add(sr.getId());
                else res.errors.add(sr.getErrors()[0].getMessage());
            }
        }

        res.created = res.createdIds.size();
        getAAAllocationCounts(examIds);
        return res;
    }

    @AuraEnabled
    public static List<Contact> getAcademicAssociates() {
        Map<Id, User> userMap = new Map<Id, User>([ select id , name , Profile.name  from User where IsActive = true AND Profile.Name ='Academic Associate']);

        return [
            SELECT Id, Name
            FROM Contact
            WHERE RecordType.DeveloperName = 'Academic_Associate'
              AND Active_Status__c = 'Active'
              AND Linked_User_Id__c IN :userMap.keySet()
            ORDER BY Name
        ];
    }

    @AuraEnabled(cacheable=true)
    public static Boolean isCurrentUserProgramOffice() {
        User u = [
            SELECT Profile.Name, UserRole.Name
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];

        return (u.Profile.Name != null &&
                u.Profile.Name.equalsIgnoreCase('ASA') &&
                u.UserRole.Name != null &&
                (u.UserRole.Name.equalsIgnoreCase('ASA Senior Manager') ||
                 u.UserRole.Name.equalsIgnoreCase('Program Office')));
    }

    @AuraEnabled
    public static Map<Id, String> getLatestAANameByExamIds(List<Id> examIds) {
        Map<Id, String> resultMap = new Map<Id, String>();
        if (examIds == null || examIds.isEmpty()) return resultMap;

        List<Exam_AA__c> listAA = [
            SELECT Exam__c, Academic_Associate__r.Name
            FROM Exam_AA__c
            WHERE Exam__c IN :examIds
            ORDER BY CreatedDate DESC
        ];

        for (Exam_AA__c eaa : listAA) {
            if (!resultMap.containsKey(eaa.Exam__c)) {
                resultMap.put(eaa.Exam__c, eaa.Academic_Associate__r.Name);
            } else {
                resultMap.put(
                    eaa.Exam__c,
                    resultMap.get(eaa.Exam__c) + ', ' + eaa.Academic_Associate__r.Name
                );
            }
        }

        return resultMap;
    }

    @AuraEnabled
    public static Boolean hasConflict(Id contactId, Date examDate, String examTime) {
        for (Exam_AA__c rec : [
            SELECT Id, Exam__r.Date_of_Exam__c, Exam__r.Time_of_Exam__c
            FROM Exam_AA__c
            WHERE Academic_Associate__c = :contactId
        ]) {
            if (rec.Exam__r.Date_of_Exam__c == examDate &&
                String.valueOf(rec.Exam__r.Time_of_Exam__c) == examTime) {
                return true;
            }
        }
        return false;
    }

    @AuraEnabled
    public static void removeExamAA(List<Id> examIds, List<Id> contactIds) {
        if (examIds == null || examIds.isEmpty()) return;

        List<Exam_AA__c> delList = [
            SELECT Id
            FROM Exam_AA__c
            WHERE Exam__c IN :examIds
              AND Academic_Associate__c IN :contactIds
        ];

        if (!delList.isEmpty()) delete delList;

        getAAAllocationCounts(examIds);
    }

    // NEW FIX: get actual AA IDs for selected exams
    @AuraEnabled
    public static Map<Id, List<Id>> getAAIdsByExamIds(List<Id> examIds) {
        Map<Id, List<Id>> result = new Map<Id, List<Id>>();
        if (examIds == null || examIds.isEmpty()) return result;

        for (Exam_AA__c eaa : [
            SELECT Exam__c, Academic_Associate__c
            FROM Exam_AA__c
            WHERE Exam__c IN :examIds
        ]) {
            if (!result.containsKey(eaa.Exam__c)) {
                result.put(eaa.Exam__c, new List<Id>());
            }
            result.get(eaa.Exam__c).add(eaa.Academic_Associate__c);
        }

        return result;
    }
// ================= CHECK OVERLAP AND DUPLICATE =================

private static Integer convertTimeToMinutes(Time t) {
    if (t == null) return 0;
    return (t.hour() * 60) + t.minute();
}

@AuraEnabled
public static Boolean checkExactDuplicate(Id contactId, Date examDate, Time startTime, Time endTime) {

    Integer newStartMin = convertTimeToMinutes(startTime);
    Integer newEndMin   = convertTimeToMinutes(endTime);

    for (Exam_AA__c rec : [
        SELECT Id, Exam__r.Date_of_Exam__c, Exam__r.Time_of_Exam__c, Exam__r.End_Time__c
        FROM Exam_AA__c
        WHERE Academic_Associate__c = :contactId
    ]) {

        if (rec.Exam__r.Date_of_Exam__c == examDate) {

            Integer dbStartMin = convertTimeToMinutes(rec.Exam__r.Time_of_Exam__c);
            Integer dbEndMin   = convertTimeToMinutes(rec.Exam__r.End_Time__c);

            if (dbStartMin == newStartMin && dbEndMin == newEndMin) {
                return true;  // exact same time match
            }
        }
    }
    return false;
}

@AuraEnabled
public static Boolean checkOverlap(Id contactId, Date examDate, Time startTime, Time endTime) {

    Integer newStartMin = convertTimeToMinutes(startTime);
    Integer newEndMin   = convertTimeToMinutes(endTime);

    for (Exam_AA__c rec : [
        SELECT Id, Exam__r.Date_of_Exam__c, Exam__r.Time_of_Exam__c, Exam__r.End_Time__c
        FROM Exam_AA__c
        WHERE Academic_Associate__c = :contactId
    ]) {

        if (rec.Exam__r.Date_of_Exam__c == examDate) {

            Integer dbStartMin = convertTimeToMinutes(rec.Exam__r.Time_of_Exam__c);
            Integer dbEndMin   = convertTimeToMinutes(rec.Exam__r.End_Time__c);

            // overlap check: A < D AND C < B
            if (dbStartMin < newEndMin && newStartMin < dbEndMin) {
                return true;
            }
        }
    }
    return false;
}

//Added By Adesh on 26-dec-2025
    @AuraEnabled
    public static Boolean getAvailableAcademicAssociates(List<Id> examIds , List<Id> selectedAAIds) {
        if (examIds == null || examIds.isEmpty()) return false;

        Set<Id> courseCatalogIds = new Set<Id>();
        for (Examination ex : [SELECT Course_Catalog__c FROM Examination WHERE Id IN :examIds]) {
            if (ex.Course_Catalog__c != null) {
                courseCatalogIds.add(ex.Course_Catalog__c);
            }
        }

        if (courseCatalogIds.isEmpty()) return false;

        // Find matches via Course_AA_Assignment__c -> AA_Profile__c -> Contact
        // We want Contact IDs that are valid for ALL courses.
        // Course_AA_Assignment__c.Academic_Associate__c is AA_Profile__c.
        // AA_Profile__c.Academic_Associate__c is Contact.
        
        Integer requiredCourseCount = courseCatalogIds.size();

        // Aggregate by Contact ID
        List<AggregateResult> aggResults = [
            SELECT Academic_Associate__r.Academic_Associate__c contactId, COUNT_DISTINCT(Course_Offering__r.LearningCourseId) courseCnt
            FROM Course_AA_Assignment__c
            WHERE Course_Offering__r.LearningCourseId IN :courseCatalogIds
              AND Academic_Associate__r.Status__c = 'Active'
            GROUP BY Academic_Associate__r.Academic_Associate__c
        ];

        Set<Id> validContactIds = new Set<Id>();
        for (AggregateResult ar : aggResults) {
            Integer cnt = (Integer)ar.get('courseCnt');
            if (cnt == requiredCourseCount) {
                validContactIds.add((Id)ar.get('contactId'));
            }
        }
        
        if (validContactIds.isEmpty()) return false;

        for(Id selectedId : selectedAAIds){
            if(validContactIds.contains(selectedId)){
                return false;
            }
        }
        return true;
    }
    //Ended By Adesh on 26-dec-2025

    //Added By Adesh on 31-Dec-2025
    @AuraEnabled(cacheable=true)
    public static List<PicklistWrapper> getVenues(Id recordId) {
        List<PicklistWrapper> options = new List<PicklistWrapper>();
        //List<Venue__c> locList = new List<Venue__c>();
        //locList = [select Id , Name from Venue__c where Location__c =:locationId ORDER BY Name];
         options.add(new PicklistWrapper('--None--', ''));
        Id locationId = [select id , Location__c from Exam_Schedule__c where id=:recordId LIMIT 1].Location__c;
        for(Exam_Venue__c loc : [select Id , Name from Exam_Venue__c where Location__c =:locationId ORDER BY Name]){
            options.add(new PicklistWrapper(loc.Name, loc.Id));
        }
        return options;
    }

    
    public class PicklistWrapper {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public PicklistWrapper(String label, String value){
            this.label = label;
            this.value = value;
        }
    }
    //Ended By Adesh on 31-Dec-2025

    @AuraEnabled
    public static void updateSelectedExams(List<Id> examIds,
                                        Date examDate,
                                        String startTime,
                                        String endTime,
                                        Id venueId) {

        if(examIds == null || examIds.isEmpty()){
            throw new AuraHandledException('No records selected.');
        }

        System.debug('examDate '+ examDate);
        System.debug('startTime '+ startTime);
        System.debug('endTime '+ endTime);
        System.debug('venueId '+ venueId);

        List<Examination> exams = [
            SELECT Id ,Name , Exam_Venue__c , Date_of_Exam__c, Time_of_Exam__c, End_Time__c, Duration_mins__c
            FROM Examination
            WHERE Id IN :examIds
        ];

        for(Examination e : exams){
            e.Date_of_Exam__c = examDate == null ? e.Date_of_Exam__c : examDate;
            e.Time_of_Exam__c = startTime==null ? e.Time_of_Exam__c : Time.newInstance(Integer.valueof(startTime.split(':')[0]), Integer.valueof(startTime.split(':')[1]), Integer.valueof(startTime.split(':')[2]), 0);
            e.End_Time__c = endTime==null ? e.End_Time__c : Time.newInstance(Integer.valueof(endTime.split(':')[0]), Integer.valueof(endTime.split(':')[1]), Integer.valueof(endTime.split(':')[2]), 0);
            e.Exam_Venue__c = venueId == null ? e.Exam_Venue__c : venueId;
            e.Duration_mins__c = e.Time_of_Exam__c ==null || e.End_Time__c ==null ? e.Duration_mins__c : ((Integer.valueof((''+e.End_Time__c).split(':')[0]) * 60) + Integer.valueof((''+e.End_Time__c).split(':')[1])) - ((Integer.valueof((''+e.Time_of_Exam__c).split(':')[0]) * 60) + Integer.valueof((''+e.Time_of_Exam__c).split(':')[1]));
        
            if(e.Duration_mins__c < 0){
                throw new AuraHandledException('End Time must be greater than Start Time for Exam: ' + e.Name);
            }
        }

        

        update exams;
    }
    //Ended By Adesh on 31-Dec-2025

    @AuraEnabled
    public static void updateSelectedExamsInReview(List<Id> examIds, Id recordId) {

        if(examIds == null || examIds.isEmpty()){
            throw new AuraHandledException('No records selected.');
        }
        List<Examination> exams = [
            SELECT Id ,Name , Status , Time_of_Exam__c,  End_Time__c, Date_of_Exam__c , Venue__c, Exam_Venue__c, Duration_mins__c 
            FROM Examination
            WHERE Id IN :examIds
        ];
        for(Examination e : exams){
            if(e.Status != 'Draft'){
                throw new AuraHandledException('Exam: ' + e.Name + ' is not Draft status.');
            }
            if(e.Date_of_Exam__c == null || e.Time_of_Exam__c == null || e.End_Time__c == null || e.Venue__c == null || e.Exam_Venue__c == null || e.Duration_mins__c == null){
                throw new AuraHandledException('Please fill all mandatory fields for Exam: ' + e.Name + ' before submitting for AA Assignment.');
            }
            e.Status = 'In Review';
        }

        Exam_Schedule__c examSchedule = [SELECT Id ,status__c FROM Exam_Schedule__c where Id =: recordId LIMIT 1];
        examSchedule.status__c = 'In Progress';

        update exams;
        update examSchedule;

        // Send notification to ASA Managers
        CustomNotificationType cnType = [select id,CustomNotifTypeName, DeveloperName from CustomNotificationType where DeveloperName ='Push_Notification' limit 1];
        Set<String> recipientUserIds = new Set<String>();
        for (GroupMember gm : [SELECT UserOrGroupId FROM GroupMember WHERE Group.DeveloperName = 'ASA_Queue_For_Exams']) {
            recipientUserIds.add(gm.UserOrGroupId);
        }
        // Keep only actual users
        if (!recipientUserIds.isEmpty()) {
            Set<String> realUsers = new Set<String>();
            for (User u : [SELECT Id FROM User WHERE Id IN :recipientUserIds AND IsActive = true]) realUsers.add(u.Id);
            recipientUserIds = realUsers;
        }
        if (recipientUserIds.isEmpty()) recipientUserIds.add(UserInfo.getUserId());

        Messaging.CustomNotification cn = new Messaging.CustomNotification();
        cn.setTitle('Action Needed: Exam Schedule');
        cn.setBody('Exam Schedule requires your attention.');
        cn.setTargetId(examSchedule.Id);
        cn.setNotificationTypeId(cnType.Id);
        cn.setSenderId(UserInfo.getUserId());
        cn.send(recipientUserIds);   
        
    }

    //Added By Adesh on 02-Jan-2026
    @AuraEnabled
    public static void publishExams(List<Id> examIds) {
        if(examIds == null || examIds.isEmpty()){
            throw new AuraHandledException('No records selected.');
        }
        List<Examination> exams = [
            SELECT Id ,Name , Status , Allott_No_of_AAs__c
            FROM Examination
            WHERE Id IN :examIds
        ];
        for(Examination e : exams){
            if(e.Allott_No_of_AAs__c == null || e.Allott_No_of_AAs__c == 0){
                throw new AuraHandledException('Please allocate Academic Associate(s) for Exam: ' + e.Name + ' before publishing.');
            }
            if(e.Status != 'In Review'){
                throw new AuraHandledException('Exam: ' + e.Name + ' is not In Review status.');
            }
            e.Status = 'Scheduled';
        }

        update exams;
    }
}