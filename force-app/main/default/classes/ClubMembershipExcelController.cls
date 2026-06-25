public with sharing class ClubMembershipExcelController {
    @AuraEnabled
    public static Map<String,Object> processExcelRows(String jsonRows) {
        Map<String,Object> result = new Map<String,Object>{
            'createdCount' => 0,
            'updatedCount' => 0,
            'failedCount' => 0,
            'errors' => new List<String>(),
            'createdIds' => new List<Id>(),
            'updatedIds' => new List<Id>()
        };

        try {
            if (String.isBlank(jsonRows)) {
                ((List<String>) result.get('errors')).add('No rows received.');
                return result;
            }

            Object des = JSON.deserializeUntyped(jsonRows);
            if (!(des instanceof List<Object>)) {
                ((List<String>) result.get('errors')).add('Invalid payload format. Expected array of rows.');
                return result;
            }

            List<Object> rawRows = (List<Object>) des;
            if (rawRows.isEmpty()) {
                ((List<String>) result.get('errors')).add('No rows in payload.');
                return result;
            }

            // Normalize and collect lookup keys
            List<Map<String,String>> normalizedRows = new List<Map<String,String>>();
            Set<String> studentIds = new Set<String>();
            Set<String> clubNames = new Set<String>();
            Integer lineNum = 1;
            for (Object o : rawRows) {
                lineNum++;
                if (!(o instanceof Map<String,Object>)) continue;
                Map<String,Object> rowObj = (Map<String,Object>) o;
                Map<String,String> row = new Map<String,String>{
                    'StudentId' => '',
                    'ClubName' => '',
                    'Role' => '',
                    'Status' => '',
                    'rowNum' => String.valueOf(lineNum)
                };

                for (String k : rowObj.keySet()) {
                    String lower = k == null ? '' : k.toLowerCase();
                    Object v = rowObj.get(k);
                    String vs = v == null ? '' : String.valueOf(v).trim();
                    if (lower == 'StudentId' || lower == 'student_id' || lower == 'id' || lower == 'pgid') {
                        row.put('StudentId', vs);
                    } else if (lower == 'clubname' || lower == 'club_name' || lower == 'club') {
                        row.put('ClubName', vs);
                    } else if (lower == 'role') {
                        row.put('Role', vs);
                    } else if (lower == 'status') {
                        row.put('Status', vs);
                    }
                }

                if (!String.isBlank(row.get('StudentId'))) studentIds.add(row.get('StudentId').trim());
                if (!String.isBlank(row.get('ClubName'))) clubNames.add(row.get('ClubName').trim());
                normalizedRows.add(row);
            }

            if (normalizedRows.isEmpty()) {
                ((List<String>) result.get('errors')).add('No valid rows after normalization.');
                return result;
            }

            // Resolve Contacts via ProgramEnrollment using PGID__c (Label: Student Id)
            Map<String, Id> studentIdToContactId = new Map<String, Id>();
            Map<String, Id> studentIdToProgramEnrollmentId = new Map<String, Id>();
            if (!studentIds.isEmpty()) {
                for (ProgramEnrollment pe : [
                    SELECT Id, ContactId, PGID__c 
                    FROM ProgramEnrollment 
                    WHERE PGID__c IN :studentIds
                ]) {
                    if (pe.PGID__c != null && pe.ContactId != null) {
                        studentIdToContactId.put(pe.PGID__c.toLowerCase().trim(), pe.ContactId);
                        studentIdToProgramEnrollmentId.put(pe.PGID__c.toLowerCase().trim(),pe.Id);
                    }
                    
                }
            }

            // Resolve Club__c by Name
            Map<String, Id> clubNameToId = new Map<String, Id>();
            if (!clubNames.isEmpty() && Schema.getGlobalDescribe().containsKey('Club__c')) {
                for (Club__c c : [SELECT Id, Name FROM Club__c WHERE Name IN :clubNames]) {
                    if (c.Name != null) clubNameToId.put(c.Name.trim(), c.Id);
                }
            }
            // fallback for missing names (best-effort)
            Set<String> missingClubNames = new Set<String>();
            for (String cn : clubNames) if (!clubNameToId.containsKey(cn)) missingClubNames.add(cn);
            if (!missingClubNames.isEmpty() && Schema.getGlobalDescribe().containsKey('Club__c')) {
                for (String mcn : missingClubNames) {
                    try {
                        List<Club__c> found = [SELECT Id, Name FROM Club__c WHERE Name = :mcn LIMIT 1];
                        if (!found.isEmpty()) clubNameToId.put(mcn, found[0].Id);
                    } catch (Exception ex) {
                        // best-effort
                    }
                }
            }

            // Prepare per-row resolved ids and collect contacts for membership query
            List<Id> rowContactIds = new List<Id>();
            List<Id> rowClubIds = new List<Id>();
            Set<Id> contactIdsForQuery = new Set<Id>();
            List<Id> rowProgramEnrollmentIds = new List<Id>();
            for (Integer i = 0; i < normalizedRows.size(); i++) {
                Map<String,String> r = normalizedRows[i];
                String contactStudentId = r.get('StudentId') == null ? '' : r.get('StudentId').trim();
                String clubName = r.get('ClubName') == null ? '' : r.get('ClubName').trim();
                Id cid = null;
                Id clid = null;
                Id peid = null;
                if (!String.isBlank(contactStudentId)) {
                    cid = studentIdToContactId.containsKey(contactStudentId.toLowerCase()) ? studentIdToContactId.get(contactStudentId.toLowerCase()) : null;
                    peid = studentIdToProgramEnrollmentId.containsKey(contactStudentId.toLowerCase()) ? studentIdToProgramEnrollmentId.get(contactStudentId.toLowerCase()) : null;
                    if (cid != null) contactIdsForQuery.add(cid);
                }
                if (!String.isBlank(clubName)) {
                    clid = clubNameToId.containsKey(clubName) ? clubNameToId.get(clubName) : null;
                }
                rowContactIds.add(cid);
                rowClubIds.add(clid);
                rowProgramEnrollmentIds.add(peid);
            }

            // Query existing memberships for contacts (keyed by contact::club)
            Map<String, Club_Membership__c> existingByContactClub = new Map<String, Club_Membership__c>();
            if (!contactIdsForQuery.isEmpty()) {
                try {
                    for (Club_Membership__c cm : [
                        SELECT Id, Contact__c, Club__c, Role__c, Status__c, Start_Date__c, End_Date__c
                        FROM Club_Membership__c
                        WHERE Contact__c IN :contactIdsForQuery
                    ]) {
                        if (cm.Contact__c != null && cm.Club__c != null) {
                            String k = String.valueOf(cm.Contact__c) + '::' + String.valueOf(cm.Club__c);
                            if (!existingByContactClub.containsKey(k)) existingByContactClub.put(k, cm);
                        }
                    }
                } catch (Exception ex) {
                    // best-effort; let validation surface duplicates if query fails
                }
            }

            // Build lists: inserts, updates, duplicates (attempted inserts that will fail to preserve validation behavior)
            List<Club_Membership__c> toInsert = new List<Club_Membership__c>();
            List<Integer> insertRowIndexes = new List<Integer>();
            List<Club_Membership__c> toUpdate = new List<Club_Membership__c>();
            List<Integer> updateRowIndexes = new List<Integer>();

            for (Integer i = 0; i < normalizedRows.size(); i++) {
                Map<String,String> r = normalizedRows[i];
                String rn = r.get('rowNum');
                Id cid = rowContactIds[i];
                Id clid = rowClubIds[i];
                String incomingRole = r.get('Role') == null ? '' : r.get('Role').trim();
                String incomingStatus = r.get('Status') == null ? '' : r.get('Status').trim();

                // Preserve original validation messages if lookups missing
                if (cid == null) {
                    if (String.isBlank(r.get('StudentId'))) {
                        ((List<String>) result.get('errors')).add('Row ' + rn + ': StudentId is blank.');
                    } else {
                        ((List<String>) result.get('errors')).add('Row ' + rn + ': Contact not found for this Student ' + r.get('StudentId'));
                    }
                    continue;
                }
                if (clid == null) {
                    if (String.isBlank(r.get('ClubName'))) {
                        ((List<String>) result.get('errors')).add('Row ' + rn + ': ClubName is blank.');
                    } else {
                        ((List<String>) result.get('errors')).add('Row ' + rn + ': Club not found with Name = ' + r.get('ClubName'));
                    }
                    continue;
                }

                String key = String.valueOf(cid) + '::' + String.valueOf(clid);
                Club_Membership__c existing = existingByContactClub.containsKey(key) ? existingByContactClub.get(key) : null;

                if (existing != null) {
                    // Compare updatable fields (Role, Status). If any difference -> UPDATE.
                    Boolean roleChanged = false;
                    Boolean statusChanged = false;
                    if (existing.Role__c == null && !String.isBlank(incomingRole)) roleChanged = true;
                    else if (existing.Role__c != null && incomingRole != null && existing.Role__c.trim() != incomingRole.trim()) roleChanged = true;

                    if (existing.Status__c == null && !String.isBlank(incomingStatus)) statusChanged = true;
                    else if (existing.Status__c != null && incomingStatus != null && existing.Status__c.trim() != incomingStatus.trim()) statusChanged = true;

                    if (roleChanged || statusChanged) {
                        Club_Membership__c upd = new Club_Membership__c(Id = existing.Id);
                        if (roleChanged) upd.Role__c = incomingRole;
                        if (statusChanged) upd.Status__c = incomingStatus;
                        upd.Source__c = 'CSV Upload';
                        toUpdate.add(upd);
                        updateRowIndexes.add(i);
                    } else {
                        // No change — create a duplicate insert attempt so your existing validation rule triggers and returns same message
                        Club_Membership__c dup = new Club_Membership__c(
                            Contact__c = cid,
                            Club__c = clid,
                            Role__c = incomingRole,
                            Status__c = incomingStatus,
                            Start_Date__c = existing.Start_Date__c == null ? System.today() : existing.Start_Date__c,
                            End_Date__c = existing.End_Date__c == null ? System.today().addMonths(12) : existing.End_Date__c,
                            Source__c = 'CSV Upload',
                            Program_Enrollment__c = rowProgramEnrollmentIds[i]
                        );
                        toInsert.add(dup);
                        insertRowIndexes.add(i);
                    }
                } else {
                    // No existing -> insert new
                    Club_Membership__c nm = new Club_Membership__c();
                    nm.Contact__c = cid;
                    nm.Club__c = clid;
                    nm.Status__c = incomingStatus;
                    if (!String.isBlank(incomingRole)) nm.Role__c = incomingRole;
                    nm.Start_Date__c = System.today();
                    nm.End_Date__c = System.today().addMonths(12);
                    nm.Source__c = 'CSV Upload';
                    nm.Program_Enrollment__c = rowProgramEnrollmentIds[i];
                    toInsert.add(nm);
                    insertRowIndexes.add(i);
                }
            }

            // Execute DML partial
            Database.SaveResult[] insertSrs = new Database.SaveResult[]{};
            Database.SaveResult[] updateSrs = new Database.SaveResult[]{};
            if (!toInsert.isEmpty()) insertSrs = Database.insert(toInsert, false);
            if (!toUpdate.isEmpty()) updateSrs = Database.update(toUpdate, false);

            // Map results back to original rows
            Map<Integer, String> rowStatus = new Map<Integer, String>();
            Map<Integer, String> rowMessage = new Map<Integer, String>();
            Map<Integer, String> rowCreatedId = new Map<Integer, String>();
            Map<Integer, String> rowUpdatedId = new Map<Integer, String>();

            // handle inserts (includes duplicate attempts that will generate validation errors)
            for (Integer j = 0; j < insertSrs.size(); j++) {
                Integer rowIdx = insertRowIndexes[j];
                String rn = normalizedRows[rowIdx].get('rowNum');
                Database.SaveResult sr = insertSrs[j];
                if (sr.isSuccess()) {
                    rowStatus.put(rowIdx, 'Success');
                    rowCreatedId.put(rowIdx, String.valueOf(sr.getId()));
                    ((List<Id>) result.get('createdIds')).add(sr.getId());
                    result.put('createdCount', ((Integer) result.get('createdCount')) + 1);
                } else {
                    List<String> msgs = new List<String>();
                    for (Database.Error err : sr.getErrors()) msgs.add(err.getStatusCode() + ' - ' + err.getMessage());
                    System.debug('msg->'+ msgs);
                    //System.debug('meeesgg->'+err.getMessage());
                    String joined = String.join(msgs, ' | ');
                    rowStatus.put(rowIdx, 'Failed');
                    rowMessage.put(rowIdx, joined);
                    ((List<String>) result.get('errors')).add('Row ' + rn + ': ' + joined);
                    result.put('failedCount', ((Integer) result.get('failedCount')) + 1);
                    
                }
            }

            // handle updates
            for (Integer j = 0; j < updateSrs.size(); j++) {
                Integer rowIdx = updateRowIndexes[j];
                String rn = normalizedRows[rowIdx].get('rowNum');
                Database.SaveResult sr = updateSrs[j];
                if (sr.isSuccess()) {
                    rowStatus.put(rowIdx, 'Updated');
                    try {
                        Id updId = toUpdate[j].Id;
                        if (updId != null) {
                            rowUpdatedId.put(rowIdx, String.valueOf(updId));
                            ((List<Id>) result.get('updatedIds')).add(updId);
                        }
                    } catch (Exception ignore) {}
                    result.put('updatedCount', ((Integer) result.get('updatedCount')) + 1);
                } else {
                    List<String> msgs = new List<String>();
                    for (Database.Error err : sr.getErrors()) msgs.add(err.getStatusCode() + ' - ' + err.getMessage());
                    String joined = String.join(msgs, ' | ');
                    rowStatus.put(rowIdx, 'Update Failed');
                    rowMessage.put(rowIdx, joined);
                    ((List<String>) result.get('errors')).add('Row ' + rn + ': ' + joined);
                    result.put('failedCount', ((Integer) result.get('failedCount')) + 1);
                }
            }

            // any rows not present -> Skipped (or carry earlier validation messages)
            for (Integer i = 0; i < normalizedRows.size(); i++) {
                if (!rowStatus.containsKey(i)) {
                    String rn = normalizedRows[i].get('rowNum');
                    List<String> matching = new List<String>();
                    for (String em : (List<String>) result.get('errors')) {
                        if (em != null && em.startsWith('Row ' + rn + ':')) matching.add(em.substring(('Row ' + rn + ':').length()).trim());
                    }
                    if (!matching.isEmpty()) {
                        rowStatus.put(i, 'Skipped');
                        rowMessage.put(i, String.join(matching, ' | '));
                    } else {
                        rowStatus.put(i, 'Skipped');
                        rowMessage.put(i, '');
                    }
                }
            }

            // Build CSV
            try {
                String csv = '';
                csv += 'Row,StudentId,ClubName,Role,Status,Message,CreatedId,UpdatedId\n';
                for (Integer i = 0; i < normalizedRows.size(); i++) {
                    Map<String,String> r = normalizedRows[i];
                    String rn = r.get('rowNum');
                    String conStudentId = r.get('StudentId') == null ? '' : r.get('StudentId').replace('"','""');
                    String clubName = r.get('ClubName') == null ? '' : r.get('ClubName').replace('"','""');
                    String role = r.get('Role') == null ? '' : r.get('Role').replace('"','""');

                    String status = rowStatus.containsKey(i) ? rowStatus.get(i) : 'Skipped';
                    String message = rowMessage.containsKey(i) ? rowMessage.get(i) : '';
                    String createdId = rowCreatedId.containsKey(i) ? rowCreatedId.get(i) : '';
                    String updatedId = rowUpdatedId.containsKey(i) ? rowUpdatedId.get(i) : '';

                    String safeStudentId = '"' + conStudentId + '"';
                    String safeClub = '"' + clubName + '"';
                    String safeRole = '"' + role + '"';
                    String safeMsg = '"' + (message == null ? '' : message.replace('"','""')) + '"';
                    String safeCreated = '"' + (createdId == null ? '' : createdId) + '"';
                    String safeUpdated = '"' + (updatedId == null ? '' : updatedId) + '"';

                    csv += rn + ',' + safeStudentId + ',' + safeClub + ',' + safeRole + ',' + status + ',' + safeMsg + ',' + safeCreated + ',' + safeUpdated + '\n';
                }

                Blob csvBlob = Blob.valueOf(csv);
                String base64 = EncodingUtil.base64Encode(csvBlob);
                result.put('resultCsvBase64', base64);
                String fname = 'ClubMembershipUploadResults_' + Datetime.now().format('yyyyMMdd_HHmmss') + '.csv';
                result.put('resultCsvFilename', fname);

                try {
                    ContentVersion cv = new ContentVersion();
                    cv.Title = fname;
                    cv.PathOnClient = fname;
                    cv.VersionData = csvBlob;
                    insert cv;
                    result.put('resultCvId', cv.Id);
                } catch (Exception excv) {
                    ((List<String>) result.get('errors')).add('Failed to create result file: ' + excv.getMessage());
                }
            } catch (Exception ex2) {
                ((List<String>) result.get('errors')).add('Failed to build CSV: ' + ex2.getMessage());
            }

            return result;

        } catch (Exception ex) {
            ((List<String>) result.get('errors')).add('Unexpected error: ' + ex.getMessage());
            return result;
        }
    }

    @AuraEnabled
    public static Id createResultFile(String base64Body, String filename) {
        if (String.isBlank(base64Body)) throw new AuraHandledException('Empty file body');
        if (String.isBlank(filename)) filename = 'UploadResults.csv';
        try {
            Blob body = EncodingUtil.base64Decode(base64Body);
            ContentVersion cv = new ContentVersion();
            cv.Title = filename;
            cv.PathOnClient = filename;
            cv.VersionData = body;
            insert cv;
            return cv.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to save result file: ' + e.getMessage());
        }
    }
}