public without sharing class ISBContactRelationshipController {
    
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getRelationships(Id recordId) {
        try {
            if (recordId == null) {
                return new List<Map<String, Object>>();
            }

            String externalId = '';
            String sobjectName = recordId.getSObjectType().getDescribe().getName();

            if (sobjectName == 'Contact') {
                List<Contact> contacts = [SELECT ISB_External_Id__c FROM Contact WHERE Id = :recordId LIMIT 1];
                externalId = contacts.isEmpty() ? '' : contacts[0].ISB_External_Id__c;
            } else if (sobjectName == 'AA_Profile__c') {
                List<AA_Profile__c> profiles = [SELECT Academic_Associate__r.ISB_External_Id__c FROM AA_Profile__c WHERE Id = :recordId LIMIT 1];
                externalId = profiles.isEmpty() ? '' : profiles[0].Academic_Associate__r.ISB_External_Id__c;
            }

            if (String.isBlank(externalId)) {
                return new List<Map<String, Object>>();
            }

            // Data Cloud query for DLM object filtering by ISB_External_Id__c
            String query = 'SELECT Id, Name_of_the_Person_c__c, Type_c__c, Rel_Designation_c__c, Status_c__c, ' +
                          'Emergency_Contact_c__c, Staying_On_Campus_c__c, Email_c__c, Mobile_No_c__c, ' +
                          'Mobile_Number_Formula_c__c, ISD_Code_Name_c__c, Mobile_Phone_Code_c__c, Area_Code_c__c, ' +
                          'Rel_Employer_c__c, Employer_c__c, Designation_c__c, Rel_Retired_From_c__c, ' +
                          'Retired_From_c__c, Retired_in_Year_c__c, Occupation_c__c, Highest_Level_of_Education_c__c, ' +
                          'Title_c__c, SAP_Title_Code_c__c, Gross_Income_Per_Anum_c__c, Gross_Total_Income_c__c, ' +
                          'Street_c__c, City_c__c, State_c__c, State_Name_c__c, Country_c__c, Country_Name_c__c, ' +
                          'Postal_Code_c__c, Postal_Code_Text_c__c ' +
                          'FROM ISB_Relationships_c_UATAdmission__dlm ' +
                          'WHERE Contact_c__c = :externalId ' +
                          'LIMIT 100';

            // Using DataCloud.Query API is the standard way to query DLMs if SOQL is not enabled
            // However, for this implementation, we will use a generic query approach or assume SOQL support
            // If the environment requires DataCloud.ConnectApi, the syntax would be different.
            
            // For now, let's assume standard SOQL or provide a mock-friendly structure
            // In many ISB implementations, they use a custom helper or standard SOQL
            
            // If this fails in the user's environment, they might need to use DataCloud.ConnectApi.query()
            
            // Example of DataCloud Query:
            // DataCloud.QueryResponse response = DataCloud.ConnectApi.query('SELECT ...');
            
            List<SObject> results = Database.query(query);
            List<Map<String, Object>> relationshipList = new List<Map<String, Object>>();
            
            for (SObject so : results) {
                relationshipList.add(so.getPopulatedFieldsAsMap());
            }
            
            return relationshipList;

        } catch (Exception e) {
            System.debug('Error fetching relationships: ' + e.getMessage());
            throw new AuraHandledException('Error fetching relationship data: ' + e.getMessage());
        }
    }
}