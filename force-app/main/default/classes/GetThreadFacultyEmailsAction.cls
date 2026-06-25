public with sharing class GetThreadFacultyEmailsAction {

    public class Request {
        @InvocableVariable(required=true label='Thread Id')
        public Id threadId;

        @InvocableVariable(label='Selected Faculty Ids (semicolon-separated Contact Ids, leave blank for all)')
        public String selectedFacultyIds;
    }

    public class Result {
        @InvocableVariable(label='Email Addresses')
        public List<String> emailAddresses;

        @InvocableVariable(label='Primary Faculty Email')
        public String primaryEmail;

        @InvocableVariable(label='All Faculty Emails Joined')
        public String allEmailsJoined;
    }

    @InvocableMethod(label='Get Thread Faculty Emails' description='Returns all faculty email addresses linked to a Communication Thread via junction records')
    public static List<Result> getEmails(List<Request> requests) {
        List<Result> results = new List<Result>();

        for (Request req : requests) {
            Result res = new Result();
            res.emailAddresses = new List<String>();
            res.primaryEmail = '';

            // Parse optional selected faculty IDs
            Set<Id> selectedIds = new Set<Id>();
            if (String.isNotBlank(req.selectedFacultyIds)) {
                for (String idStr : req.selectedFacultyIds.split('[;,]')) {
                    String trimmed = idStr == null ? null : idStr.trim();
                    if (String.isBlank(trimmed)) {
                        continue;
                    }

                    try {
                        selectedIds.add((Id) trimmed);
                    } catch (Exception ex) {
                        // Ignore malformed IDs from flow input and continue.
                    }
                }
            }

            List<Communication_Thread_Contact__c> junctions = selectedIds.isEmpty()
                ? [
                    SELECT Contact__r.FacultyEmail__c, Is_Primary__c
                    FROM Communication_Thread_Contact__c
                    WHERE Communication_Thread__c = :req.threadId
                    AND Contact__r.FacultyEmail__c != null
                    ORDER BY Is_Primary__c DESC
                  ]
                : [
                    SELECT Contact__r.FacultyEmail__c, Is_Primary__c
                    FROM Communication_Thread_Contact__c
                    WHERE Communication_Thread__c = :req.threadId
                    AND Contact__c IN :selectedIds
                    AND Contact__r.FacultyEmail__c != null
                    ORDER BY Is_Primary__c DESC
                  ];

            for (Communication_Thread_Contact__c j : junctions) {
                if (String.isNotBlank(j.Contact__r.FacultyEmail__c)) {
                    res.emailAddresses.add(j.Contact__r.FacultyEmail__c);
                    if (j.Is_Primary__c && String.isBlank(res.primaryEmail)) {
                        res.primaryEmail = j.Contact__r.FacultyEmail__c;
                    }
                }
            }

            // Fall back to first email if no primary flagged
            if (String.isBlank(res.primaryEmail) && !res.emailAddresses.isEmpty()) {
                res.primaryEmail = res.emailAddresses[0];
            }

            res.allEmailsJoined = String.join(res.emailAddresses, ';');

            results.add(res);
        }

        return results;
    }
}