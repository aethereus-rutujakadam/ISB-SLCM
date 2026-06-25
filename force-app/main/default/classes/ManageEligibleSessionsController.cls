public without sharing class ManageEligibleSessionsController {
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getEligibleSessionsData(String feesMasterId) {
        Map<String, Object> result = new Map<String, Object>();
        
        try {
            // Get Fees Master with Academic Term
            ISB_Fees_Master__c feesMaster = [
                SELECT Id, Academic_Term__c, 
                       Academic_Term__r.Name,
                       Academic_Term__r.Program__c
                FROM ISB_Fees_Master__c
                WHERE Id = :feesMasterId
                LIMIT 1
            ];
            
            result.put('academicTermName', feesMaster.Academic_Term__r.Name);
            
            // Get all Academic Sessions for this term and program
            List<AcademicSession> sessions = [
                SELECT Id, Name, Location__c
                FROM AcademicSession
                WHERE Program__c = :feesMaster.Academic_Term__r.Program__c
                AND (AcademicTermId = :feesMaster.Academic_Term__c OR AcademicTermId = null)
                ORDER BY Name ASC
            ];
            
            result.put('sessions', sessions);
            
            // Get existing Eligible Terms for this Fees Master with Academic Session details
            List<ISB_Eligible_Term__c> existingTerms = [
                SELECT Id, Academic_Session__c
                FROM ISB_Eligible_Term__c
                WHERE ISB_Fees_Master__c = :feesMasterId
            ];
            
            // Extract existing session IDs for pre-selection
            List<String> existingSessionIds = new List<String>();
            for (ISB_Eligible_Term__c term : existingTerms) {
                existingSessionIds.add(term.Academic_Session__c);
            }
            
            result.put('existingTerms', existingTerms);
            result.put('existingSessionIds', existingSessionIds);
            
            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Error loading session data: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static void createEligibleTerms(String feesMasterId, List<String> sessionIds) {
        try {
            // Get Fees Master
            ISB_Fees_Master__c feesMaster = [
                SELECT Id
                FROM ISB_Fees_Master__c
                WHERE Id = :feesMasterId
                LIMIT 1
            ];
            
            // Delete existing records before creating new ones
            List<ISB_Eligible_Term__c> existingTerms = [
                SELECT Id
                FROM ISB_Eligible_Term__c
                WHERE ISB_Fees_Master__c = :feesMasterId
            ];
            if (!existingTerms.isEmpty()) {
                delete existingTerms;
            }
            
            // Get sequence counter for ordering
            Integer sequenceCounter = 1;
            
            // Create new Eligible Term records
            List<ISB_Eligible_Term__c> newTerms = new List<ISB_Eligible_Term__c>();
            for (String sessionId : sessionIds) {
                newTerms.add(new ISB_Eligible_Term__c(
                    Academic_Session__c = sessionId,
                    ISB_Fees_Master__c = feesMasterId,
                    Sequence__c = sequenceCounter++
                ));
            }
            
            if (!newTerms.isEmpty()) {
                insert newTerms;
            }
            
        } catch (Exception e) {
            throw new AuraHandledException('Error creating eligible terms: ' + e.getMessage());
        }
    }
}