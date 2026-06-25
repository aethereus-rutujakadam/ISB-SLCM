public with sharing class AwardCatalogUploadController {

    @AuraEnabled
    public static Map<String, Object> processCatalogData(List<Map<String, Object>> records) {

        Map<String, Object> response = new Map<String, Object>{
            'successCount' => 0,
            'failedCount'  => 0,
            'errorRows'    => new List<String>(),
            'errorCSV'     => ''
        };

        List<String> errorRows = (List<String>)response.get('errorRows');

        if (records == null || records.isEmpty()) {
            errorRows.add('Row 0: No records found in Excel');
            response.put('errorCSV', 'Row,Message\n"0","No records found in Excel"');
            return response;
        }

        // Collect names and check for Excel duplicates
        Set<String> incomingNames = new Set<String>();
        Set<String> excelDuplicates = new Set<String>();
        for (Map<String, Object> row : records) {
            String nm = (String)row.get('Award Catalog Name');
            if (nm != null) {
                String normalized = nm.trim().toLowerCase();
                if (incomingNames.contains(normalized)) {
                    excelDuplicates.add(normalized);
                }
                incomingNames.add(normalized);
            }
        }

        Map<String, Award_Catalog__c> existingCatalog = new Map<String, Award_Catalog__c>();
        if (!incomingNames.isEmpty()) {
            for (Award_Catalog__c ac : [
                SELECT Id, Name FROM Award_Catalog__c WHERE Name IN :incomingNames
            ]) {
                existingCatalog.put(ac.Name.trim().toLowerCase(), ac);
            }
        }

        List<Award_Catalog__c> toInsert = new List<Award_Catalog__c>();
        List<Integer> validRows = new List<Integer>();
        Integer rowNo = 2;

        for (Map<String, Object> row : records) {
            try {
                String name = (String) row.get('Award Catalog Name');

                if (String.isBlank(name)) {
                    errorRows.add('Row ' + rowNo + ': Award Catalog Name is required');
                    rowNo++;
                    continue;
                }

                String normalized = name.trim().toLowerCase();

                // Excel duplicate
                if (excelDuplicates.contains(normalized)) {
                    errorRows.add('Row ' + rowNo + ': Duplicate entry in uploaded Excel for "' + name + '"');
                    rowNo++;
                    continue;
                }

                // Org duplicate
                if (existingCatalog.containsKey(normalized)) {
                    Award_Catalog__c existing = existingCatalog.get(normalized);
                    errorRows.add('Row ' + rowNo + ': Duplicate found in Salesforce. "' + name + '" exists. Id: ' + existing.Id);
                    rowNo++;
                    continue;
                }

                Award_Catalog__c ac = new Award_Catalog__c(
                    Name = name,
                    Award_Recipient_Type__c = (String) row.get('Award Recipient Type'),
                    Category__c = (String) row.get('Category'),
                    Active__c = (((String) row.get('Active')) != null && ((String) row.get('Active')).toLowerCase().contains('yes')),
                    Description__c = (String) row.get('Description')
                );

                toInsert.add(ac);
                validRows.add(rowNo);

            } catch (Exception e) {
                errorRows.add('Row ' + rowNo + ': ' + e.getMessage());
            }

            rowNo++;
        }

        // PARTIAL INSERT
        List<Database.SaveResult> results = Database.insert(toInsert, false);

        Integer successCount = 0;
        Integer failedCount = 0;
        List<String> csvLines = new List<String>();

        for (String e : errorRows) csvLines.add(e);

        for (Integer i = 0; i < results.size(); i++) {
            Integer originalRow = validRows[i];

            if (results[i].isSuccess()) {
                successCount++;
            } else {
                failedCount++;
                for (Database.Error er : results[i].getErrors()) {
                    String msg = 'Row ' + originalRow + ': ' + er.getMessage();
                    csvLines.add(msg);
                    errorRows.add(msg);
                }
            }
        }

        // Build CSV
        String csv = 'Row,Message\n';
        for (String line : csvLines) {
            csv += '"' + line.replace('"','""') + '"\n';
        }

        response.put('successCount', successCount);
        response.put('failedCount', failedCount);
        response.put('errorCSV', csv);

        return response;
    }
}