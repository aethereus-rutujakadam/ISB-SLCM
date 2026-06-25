public with sharing class CreateThreadContactsAction {
    public class Request {
        @InvocableVariable(required=true label='Communication Thread ID')
        public Id threadId;

        @InvocableVariable(required=true label='Selected Faculty IDs (semicolon or comma separated)')
        public String selectedFacultyIds;

        @InvocableVariable(required=false label='Primary Faculty ID')
        public Id primaryFacultyId;
    }

    public class Result {
        @InvocableVariable(label='Number of Junction Records Created')
        public Integer recordsCreated;

        @InvocableVariable(label='Error Message')
        public String errorMessage;

        @InvocableVariable(label='Success')
        public Boolean success;
    }

    @InvocableMethod(
        label='Create Thread Contact Junction Records'
        description='Creates Communication_Thread_Contact__c records for all selected faculty on a communication thread.'
    )
    public static List<Result> createThreadContacts(List<Request> requests) {
        List<Result> results = new List<Result>();

        Set<Id> allThreadIds = new Set<Id>();
        Map<Id, Set<Id>> requestedContactsByThread = new Map<Id, Set<Id>>();
        List<Set<Id>> parsedContactIdsByRequest = new List<Set<Id>>();
        for (Request req : requests) {
            if (req != null && req.threadId != null) {
                allThreadIds.add(req.threadId);
            }

            Set<Id> requestContactIds = new Set<Id>();
            if (req != null && !String.isBlank(req.selectedFacultyIds)) {
                List<String> rawIds = req.selectedFacultyIds.split('[;,]');
                for (String rawId : rawIds) {
                    String trimmedId = rawId == null ? null : rawId.trim();
                    if (String.isBlank(trimmedId)) {
                        continue;
                    }

                    try {
                        Id contactId = (Id)trimmedId;
                        requestContactIds.add(contactId);
                    } catch (Exception ex) {
                        // Skip invalid id values from flow input.
                    }
                }
            }
            parsedContactIdsByRequest.add(requestContactIds);

            if (req != null && req.threadId != null && !requestContactIds.isEmpty()) {
                if (!requestedContactsByThread.containsKey(req.threadId)) {
                    requestedContactsByThread.put(req.threadId, new Set<Id>());
                }
                requestedContactsByThread.get(req.threadId).addAll(requestContactIds);
            }
        }

        Map<String, Communication_Thread_Contact__c> existingByKey = new Map<String, Communication_Thread_Contact__c>();
        if (!allThreadIds.isEmpty()) {
            for (Communication_Thread_Contact__c existing : [
                SELECT Id, Communication_Thread__c, Contact__c
                FROM Communication_Thread_Contact__c
                WHERE Communication_Thread__c IN :allThreadIds
            ]) {
                String key = String.valueOf(existing.Communication_Thread__c) + '_' + String.valueOf(existing.Contact__c);
                existingByKey.put(key, existing);
            }
        }

        Map<Id, Id> offeringByThreadId = new Map<Id, Id>();
        if (!allThreadIds.isEmpty()) {
            for (Communication_Thread__c threadRow : [
                SELECT Id, Course_Offering__c
                FROM Communication_Thread__c
                WHERE Id IN :allThreadIds
            ]) {
                offeringByThreadId.put(threadRow.Id, threadRow.Course_Offering__c);
            }
        }

        Set<Id> offeringIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();
        for (Id threadId : requestedContactsByThread.keySet()) {
            Id offeringId = offeringByThreadId.get(threadId);
            if (offeringId == null) {
                continue;
            }
            offeringIds.add(offeringId);
            contactIds.addAll(requestedContactsByThread.get(threadId));
        }

        Map<String, Id> uniquePaymentByOfferingFaculty = new Map<String, Id>();
        Set<String> ambiguousPaymentKeys = new Set<String>();
        if (!offeringIds.isEmpty() && !contactIds.isEmpty()) {
            for (Payment_Information__c payment : [
                SELECT Id, Course_Offering__c, Faculty__c
                FROM Payment_Information__c
                WHERE Course_Offering__c IN :offeringIds
                AND Faculty__c IN :contactIds
            ]) {
                String key = paymentKey(payment.Course_Offering__c, payment.Faculty__c);
                if (ambiguousPaymentKeys.contains(key)) {
                    continue;
                }
                if (!uniquePaymentByOfferingFaculty.containsKey(key)) {
                    uniquePaymentByOfferingFaculty.put(key, payment.Id);
                } else {
                    uniquePaymentByOfferingFaculty.remove(key);
                    ambiguousPaymentKeys.add(key);
                }
            }
        }

        List<Communication_Thread_Contact__c> toInsert = new List<Communication_Thread_Contact__c>();

        for (Integer requestIndex = 0; requestIndex < requests.size(); requestIndex++) {
            Request req = requests[requestIndex];
            Result res = new Result();
            res.success = false;
            res.recordsCreated = 0;

            try {
                if (req == null || req.threadId == null || String.isBlank(req.selectedFacultyIds)) {
                    res.errorMessage = 'threadId and selectedFacultyIds are required.';
                    results.add(res);
                    continue;
                }

                Set<Id> requestContactIds = parsedContactIdsByRequest[requestIndex];
                Id offeringId = offeringByThreadId.get(req.threadId);

                for (Id contactId : requestContactIds) {
                    String dedupeKey = String.valueOf(req.threadId) + '_' + String.valueOf(contactId);
                    if (existingByKey.containsKey(dedupeKey)) {
                        continue;
                    }

                    Id paymentInformationId;
                    if (offeringId != null) {
                        String paymentKey = paymentKey(offeringId, contactId);
                        if (!ambiguousPaymentKeys.contains(paymentKey)) {
                            paymentInformationId = uniquePaymentByOfferingFaculty.get(paymentKey);
                        }
                    }

                    Communication_Thread_Contact__c recordToCreate = new Communication_Thread_Contact__c(
                        Communication_Thread__c = req.threadId,
                        Contact__c = contactId,
                        Is_Primary__c = (req.primaryFacultyId != null && req.primaryFacultyId == contactId),
                        Payment_Information__c = paymentInformationId
                    );

                    toInsert.add(recordToCreate);
                    existingByKey.put(dedupeKey, recordToCreate);
                    res.recordsCreated++;
                }

                res.success = true;
            } catch (Exception e) {
                res.errorMessage = e.getMessage();
                res.success = false;
            }

            results.add(res);
        }

        if (!toInsert.isEmpty()) {
            Database.SaveResult[] saveResults = Database.insert(toInsert, false);
            if (saveResults.size() != toInsert.size()) {
                for (Result res : results) {
                    if (res.success && res.recordsCreated > 0) {
                        res.success = false;
                        res.errorMessage = 'Unexpected DML result size mismatch.';
                    }
                }
            }
        }

        return results;
    }

    private static String paymentKey(Id offeringId, Id contactId) {
        return String.valueOf(offeringId) + '_' + String.valueOf(contactId);
    }
}