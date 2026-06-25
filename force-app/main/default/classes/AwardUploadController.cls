public with sharing class AwardUploadController {

    @AuraEnabled
    public static Map<String, Object> processAwardData(List<Map<String, Object>> records) {

        Map<String, Object> response = new Map<String, Object>{
            'successCount' => 0,
            'failedCount'  => 0
        };
        if (records == null || records.isEmpty()) return response;

        Set<String> studentIds = new Set<String>();
        Set<String> catalogNames = new Set<String>();

        // Extract IDs from Uploaded Excel Rows
        for (Map<String, Object> row : records) {
            Object studentIdObj = row.get('studentId');
            Object catalogObj = row.get('awardCatalog');
            if (studentIdObj != null) studentIds.add(String.valueOf(studentIdObj).trim());
            if (catalogObj != null) catalogNames.add(String.valueOf(catalogObj).trim());
        }
        
        // -----------------------------------------------------------
        // NEW LOGIC – Fetch Contact and Program Enrollment via PGID__c
        // -----------------------------------------------------------
        Map<String, Id> studentIdToContactId = new Map<String, Id>();
        Map<String, Id> studentIdToProgramEnrollmentId = new Map<String, Id>();

        for (ProgramEnrollment pe : [
            SELECT Id, PGID__c, ContactId, ProgramId, Academic_Term__c
            FROM ProgramEnrollment
            WHERE PGID__c IN :studentIds
        ]) {
            if (pe.PGID__c != null && pe.ContactId != null) {
                studentIdToContactId.put(pe.PGID__c.trim(), pe.ContactId);
                studentIdToProgramEnrollmentId.put(pe.PGID__c.trim(), pe.Id);
            }
        }

        // -----------------------------------------------------------
        // Fetch Award Catalog with Active Flag
        // -----------------------------------------------------------
        Map<String, Award_Catalog__c> catalogNameToRecord = new Map<String, Award_Catalog__c>();
        for (Award_Catalog__c ac : [
            SELECT Id, Name, Active__c, Category__c 
            FROM Award_Catalog__c
            WHERE Name IN :catalogNames
        ]) {
            catalogNameToRecord.put(ac.Name.trim(), ac);
        }

        // -----------------------------------------------------------
        // Check for Existing Awards in Org (Duplicate Check)
        // -----------------------------------------------------------
        Set<Id> programEnrollmentIds = new Set<Id>(studentIdToProgramEnrollmentId.values());
        Set<Id> catalogIds = new Set<Id>();
        for (Award_Catalog__c ac : catalogNameToRecord.values()) {
            catalogIds.add(ac.Id);
        }

        // Create a map to store existing Award combinations with details
        Map<String, Award> existingAwardsMap = new Map<String, Award>();
        Set<String> existingAwardKeys = new Set<String>();
        
        List<Award> existingAwards = [
            SELECT Id, Program_Enrollment__c, Award_Catalog__c, 
                   Program_Enrollment__r.PGID__c, Award_Catalog__r.Name
            FROM Award
            WHERE Program_Enrollment__c IN :programEnrollmentIds
            AND Award_Catalog__c IN :catalogIds
        ];
        
        for (Award existingAward : existingAwards) {
            // Create unique key: ProgramEnrollmentId + '|' + AwardCatalogId
            String key = existingAward.Program_Enrollment__c + '|' + existingAward.Award_Catalog__c;
            existingAwardKeys.add(key);
            existingAwardsMap.put(key, existingAward);
        }

        Map<String, Id> categoryToRecordTypeId = new Map<String, Id>();
        for (RecordType rt : [
            SELECT Id, DeveloperName, Name
            FROM RecordType
            WHERE SObjectType = 'Award'
            AND IsActive = true
            AND (DeveloperName = 'Academic' OR DeveloperName = 'Leadership')
        ]) {
            categoryToRecordTypeId.put(rt.DeveloperName, rt.Id);
        }

        List<Award> awardsToInsert = new List<Award>();
        List<Map<String, Object>> errorRows = new List<Map<String, Object>>();

        Integer success = 0;
        Integer fail = 0;
        Integer rowNumber = 0;

        // -----------------------------------------------------------
        // Build Award Records or Capture Errors
        // -----------------------------------------------------------
        for (Map<String, Object> row : records) {
            rowNumber++;
            try {
                String studentId = row.get('studentId') != null ? String.valueOf(row.get('studentId')).trim() : null;
                String catalogName = row.get('awardCatalog') != null ? String.valueOf(row.get('awardCatalog')).trim() : null;

                Id contactId = studentIdToContactId.get(studentId);
                Id programEnrollmentId = studentIdToProgramEnrollmentId.get(studentId);
                Award_Catalog__c acRecord = catalogNameToRecord.get(catalogName);

                // Award Catalog Active Check
                if (acRecord != null && acRecord.Active__c == false) {
                    fail++;
                    errorRows.add(new Map<String, Object>{
                        'studentId'    => studentId,
                        'awardCatalog' => catalogName,
                        'errorMessage' => 'Award Catalog "' + catalogName + '" is not Active'
                    });
                    continue;
                }

                // Check for duplicate against existing org records ONLY
                if (programEnrollmentId != null && acRecord != null) {
                    String duplicateKey = programEnrollmentId + '|' + acRecord.Id;
                    System.debug('Duplicate Check Key: ' + duplicateKey);
                    
                    if (existingAwardKeys.contains(duplicateKey)) {
                        fail++;
                        Award existingAward = existingAwardsMap.get(duplicateKey);
                       
                        errorRows.add(new Map<String, Object>{
                            'studentId'    => studentId,
                            'awardCatalog' => catalogName,
                            'errorMessage' => 'Duplicate Award: PGID "' + studentId + '" already has Award Catalog "' + catalogName + '" (Award Id: ' + existingAward.Id + ')'
                        });
                        continue;
                    } else {
                        System.debug('✓ No duplicate found - Safe to proceed');
                    }
                }

                Award award = new Award();
                if (contactId != null) award.Contact__c = contactId;
                if (programEnrollmentId != null) award.Program_Enrollment__c = programEnrollmentId;
                if (acRecord != null) award.Award_Catalog__c = acRecord.Id;

                // Parse and set AwardDate (Datetime) if provided. Accepts ISO or date-only strings.
                Object awardDateObj = row.get('awardDate');
                if (awardDateObj != null) {
                    String awardDateStr = String.valueOf(awardDateObj).trim();
                    if (awardDateStr != '') {
                        // Normalize ISO-ish strings to a format Datetime.valueOf can accept
                        String normalized = awardDateStr.replace('T', ' ').replace('Z', '');
                        if (normalized.contains('.')) {
                            normalized = normalized.substring(0, normalized.indexOf('.'));
                        }
                        Boolean parsedOk = false;
                        try {
                            Datetime dt = Datetime.valueOf(normalized);
                            award.put('AwardDate', dt);
                            parsedOk = true;
                        } catch (Exception e1) {
                            // Try parsing as Date then convert to Datetime at midnight
                            try {
                                Date d = Date.valueOf(awardDateStr);
                                Datetime dt2 = Datetime.newInstance(d.year(), d.month(), d.day());
                                award.put('AwardDate', dt2);
                                parsedOk = true;
                            } catch (Exception e2) {
                                // failed to parse
                            }
                        }

                        if (!parsedOk) {
                            fail++;
                            errorRows.add(new Map<String, Object>{
                                'studentId'    => studentId,
                                'awardCatalog' => catalogName,
                                'awardDate'    => awardDateStr,
                                'errorMessage' => 'Invalid Award Date: ' + awardDateStr
                            });
                            continue;
                        }
                    }
                }

                if (acRecord != null && acRecord.Category__c != null) {
                    Id recordTypeId = categoryToRecordTypeId.get(acRecord.Category__c);
                    
                    if (recordTypeId != null) {
                        Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe().get('Award').getDescribe().fields.getMap();
                        if (fieldMap.containsKey('RecordTypeId')) {
                            award.put('RecordTypeId', recordTypeId);
                            System.debug('RecordType Assigned: ' + acRecord.Category__c + ' -> ' + recordTypeId);
                        } else {
                            System.debug('RecordTypeId field does not exist on Award object');
                        }
                    } else {
                        System.debug('Warning: No RecordType found for Category: ' + acRecord.Category__c);
                    }
                }

                awardsToInsert.add(award);

            } catch (Exception ex) {
                fail++;
                errorRows.add(new Map<String, Object>{
                    'studentId'    => row.get('studentId'),
                    'awardCatalog' => row.get('awardCatalog'),
                    'errorMessage' => ex.getMessage()
                });
            }
        }

        // -----------------------------------------------------------
        // Insert Awards
        // -----------------------------------------------------------
        if (!awardsToInsert.isEmpty()) {
            List<Database.SaveResult> results = Database.insert(awardsToInsert, false);

            Integer insertIndex = 0;
            for (Database.SaveResult sr : results) {
                if (sr.isSuccess()) {
                    success++;
                } else {
                    fail++;
                    String errorMsg = sr.getErrors()[0].getMessage();
                    errorRows.add(new Map<String, Object>{
                        'studentId'    => '',
                        'awardCatalog' => '',
                        'errorMessage' => errorMsg
                    });
                }
                insertIndex++;
            }
        }

        // -----------------------------------------------------------
        // Build CSV for LWC Download
        // -----------------------------------------------------------
        String csv = 'studentId,awardCatalog,awardDate,errorMessage\n';
        for (Map<String,Object> er : errorRows) {
            csv += '"' + er.get('studentId') + '","' + er.get('awardCatalog') + '","' + er.get('awardDate') + '","' + er.get('errorMessage') + '"\n';
        }

        response.put('successCount', success);
        response.put('failedCount', fail);
        response.put('errorRows', errorRows);
        response.put('errorCSV', csv);

        return response;
    }
}