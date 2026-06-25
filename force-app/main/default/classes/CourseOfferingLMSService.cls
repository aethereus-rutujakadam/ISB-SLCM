public without sharing class CourseOfferingLMSService {
    
    private static List<Error_Handling__c> pendingErrorLogs = new List<Error_Handling__c>();

    public class SyncResult {
        @AuraEnabled public List<CourseOffering> successRecords = new List<CourseOffering>();
        @AuraEnabled public List<CourseOffering> failedRecords = new List<CourseOffering>();
    }

    public static SyncResult sync(List<CourseOffering> validOfferings) {
        SyncResult result = new SyncResult();
        if (validOfferings == null || validOfferings.isEmpty()) return result;
        
        pendingErrorLogs = new List<Error_Handling__c>();
        LMS_Config__mdt lmsConfig = LMS_Config__mdt.getInstance('CourseOfferingSyncFunction');

        if (lmsConfig == null) {
            for(CourseOffering o : validOfferings) {
                o.LMS_Sync_Status__c = 'Failed';
                o.LMS_Error__c = 'Missing Custom Metadata: CourseOfferingSyncFunction';
                result.failedRecords.add(o);
                logError('LMS_CourseOfferingSync', o.LMS_Error__c, '500', o.Id, null, null);
            }
            commitLogs();
            return result;
        }

        for (CourseOffering off : validOfferings) {
            // If LMS course id already exists, skip course creation and sync only sections/groups.
            if (String.isNotBlank(off.LMS_Course_Id__c)) {
                syncGroups(new List<CourseOffering>{off});
                if (off.LMS_Sync_Status__c == 'Failed') result.failedRecords.add(off);
                else result.successRecords.add(off);
                continue;
            }

            // Standard Creation Flow
            String validationMsg = validateOffering(off);
            if (String.isNotBlank(validationMsg)) {
                off.LMS_Sync_Status__c = 'Failed';
                off.LMS_Error__c = 'Configuration Error: ' + validationMsg;
                result.failedRecords.add(off);
                logError('LMS_CourseOfferingSync_Validation', off.LMS_Error__c, '400', off.Id, null, null);
                continue;
            }

            String requestBody = buildCourseCreateBody(new List<CourseOffering>{off}, lmsConfig);
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:LMS_Integration');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            req.setBody(requestBody);
            req.setTimeout(120000);

            try {
                HttpResponse res = new Http().send(req);
                String resBody = res.getBody();

                if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
                    Object parsedRes = JSON.deserializeUntyped(resBody);
                    if (parsedRes instanceof List<Object>) {
                        List<Object> resList = (List<Object>) parsedRes;
                        if (!resList.isEmpty()) {
                            Map<String, Object> respMap = (Map<String, Object>) resList[0];
                            off.LMS_Course_Id__c = String.valueOf(respMap.get('id'));
                            syncGroups(new List<CourseOffering>{off});
                            if (off.LMS_Sync_Status__c == 'Failed') result.failedRecords.add(off);
                            else result.successRecords.add(off);
                        }
                    } else if (parsedRes instanceof Map<String, Object>) {
                        Map<String, Object> resMap = (Map<String, Object>) parsedRes;
                        String msg = resMap.containsKey('message') ? String.valueOf(resMap.get('message')) : resBody;
                        off.LMS_Sync_Status__c = 'Failed';
                        off.LMS_Error__c = 'Moodle Error: ' + msg;
                        result.failedRecords.add(off);
                        logError('LMS_CourseOfferingSync_MoodleError', off.LMS_Error__c, String.valueOf(res.getStatusCode()), off.Id, requestBody, resBody);
                    }
                } else {
                    off.LMS_Sync_Status__c = 'Failed';
                    off.LMS_Error__c = 'HTTP ' + res.getStatusCode() + ': ' + resBody.left(100);
                    result.failedRecords.add(off);
                    logError('LMS_CourseOfferingSync_HTTPError', off.LMS_Error__c, String.valueOf(res.getStatusCode()), off.Id, requestBody, resBody);
                }
            } catch (Exception e) {
                off.LMS_Sync_Status__c = 'Failed';
                off.LMS_Error__c = 'API Exception: ' + e.getMessage();
                result.failedRecords.add(off);
                logError('LMS_CourseOfferingSync_Exception', off.LMS_Error__c, '500', off.Id, requestBody, e.getStackTraceString());
            }
        }
        commitLogs();
        return result;
    }

    public static Boolean deleteGroups(List<String> groupIds, Id offeringId) {
        if (groupIds == null || groupIds.isEmpty()) return true;
        LMS_Config__mdt config = LMS_Config__mdt.getInstance('CourseOfferingDeleteGroupFunction');
        if (config == null) {
            logError('LMS_GroupDelete_Config', 'Missing Custom Metadata: CourseOfferingDeleteGroupFunction', '500', String.valueOf(offeringId), null, null);
            return false;
        }

        String body = 'wstoken=' + EncodingUtil.urlEncode(config.wsToken__c, 'UTF-8')
                    + '&wsfunction=' + EncodingUtil.urlEncode(config.wsFunction__c, 'UTF-8')
                    + '&moodlewsrestformat=json';
        for (Integer i = 0; i < groupIds.size(); i++) {
            body += '&groupids[' + i + ']=' + EncodingUtil.urlEncode(groupIds[i], 'UTF-8');
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:LMS_Integration');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setBody(body);
        req.setTimeout(120000);

        try {
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
                return true;
            }
            logError('LMS_GroupDelete_HTTPError', 'Failed to delete groups from LMS', String.valueOf(res.getStatusCode()), String.valueOf(offeringId), body, res.getBody());
        } catch (Exception e) {
            logError('LMS_GroupDelete_Exception', e.getMessage(), '500', String.valueOf(offeringId), body, e.getStackTraceString());
        }
        return false;
    }

    private static String validateOffering(CourseOffering off) {
        if (String.isBlank(off.Name)) return 'Course Shortname (Name) is missing';
        if (off.Academic_Year__r == null || String.isBlank(off.Academic_Year__r.Category_Id__c)) return 'Academic Year Category ID is missing';
        return null;
    }

    private static String buildCourseCreateBody(List<CourseOffering> offerings, LMS_Config__mdt config) {
        String body = 'wstoken=' + EncodingUtil.urlEncode(config.wsToken__c, 'UTF-8') + '&wsfunction=' + config.wsFunction__c + '&moodlewsrestformat=json';
        Integer i = 0;
        for (CourseOffering o : offerings) {
            String p = 'courses[' + (i++) + ']';
            String fn = (o.LearningCourse != null && String.isNotBlank(o.LearningCourse.Name)) ? o.LearningCourse.Name : o.Name;
            body += '&' + p + '[fullname]=' + EncodingUtil.urlEncode(fn, 'UTF-8') + '&' + p + '[shortname]=' + EncodingUtil.urlEncode(o.Name, 'UTF-8');
            if (o.Academic_Year__r != null) body += '&' + p + '[categoryid]=' + o.Academic_Year__r.Category_Id__c.trim();
            body += '&' + p + '[numsections]=' + (o.No_of_Sections__c != null ? Integer.valueOf(o.No_of_Sections__c) : 0);
        }
        return body;
    }

    private static void syncGroups(List<CourseOffering> offerings) {
        LMS_Config__mdt config = LMS_Config__mdt.getInstance('CourseOfferingGroupSyncFunction');
        if (config == null) {
            for (CourseOffering off : offerings) {
                off.LMS_Sync_Status__c = 'Failed';
                off.LMS_Error__c = 'Missing Custom Metadata: CourseOfferingGroupSyncFunction';
                logError('LMS_GroupSync_Config', off.LMS_Error__c, '500', off.Id, null, null);
            }
            return;
        }

        for (CourseOffering off : offerings) {
            if (String.isBlank(off.LMS_Course_Id__c)) {
                off.LMS_Sync_Status__c = 'Failed';
                off.LMS_Error__c = 'LMS_Course_Id__c is blank, so section sync cannot start.';
                logError('LMS_GroupSync_MissingCourseId', off.LMS_Error__c, '400', off.Id, null, null);
                continue;
            }

            Map<String, String> currentMappings = new Map<String, String>();
            if (String.isNotBlank(off.Section_Mappings__c)) {
                for (String part : off.Section_Mappings__c.split(',')) {
                    List<String> kv = part.trim().split(':');
                    if (kv.size() == 2 && String.isNotBlank(kv[0]) && String.isNotBlank(kv[1])) {
                        currentMappings.put(kv[0].trim(), kv[1].trim());
                    }
                }
            }

            Set<String> desiredNames = new Set<String>();
            if (String.isNotBlank(off.Section_Name__c)) {
                for (String s : off.Section_Name__c.split(',')) {
                    if (String.isNotBlank(s) && String.isNotBlank(s.trim())) {
                        desiredNames.add(s.trim());
                    }
                }
            }

            List<String> toCreate = new List<String>();
            List<String> toDeleteIds = new List<String>();
            List<String> removedNames = new List<String>();
            List<String> addedNames = new List<String>();
            List<String> mappingList = new List<String>();

            for (String desiredName : desiredNames) {
                if (!currentMappings.containsKey(desiredName)) {
                    toCreate.add(desiredName);
                    addedNames.add(desiredName);
                }
            }

            for (String existingName : currentMappings.keySet()) {
                if (desiredNames.contains(existingName)) {
                    mappingList.add(existingName + ':' + currentMappings.get(existingName));
                } else {
                    toDeleteIds.add(currentMappings.get(existingName));
                    removedNames.add(existingName);
                }
            }

            if (!toDeleteIds.isEmpty() && !deleteGroups(toDeleteIds, off.Id)) {
                off.LMS_Sync_Status__c = 'Failed';
                off.LMS_Error__c = 'Section delete sync failed for: ' + String.join(removedNames, ', ');
                continue;
            }

            if (!toCreate.isEmpty()) {
                String reqBody = 'wstoken=' + EncodingUtil.urlEncode(config.wsToken__c, 'UTF-8')
                               + '&wsfunction=' + EncodingUtil.urlEncode(config.wsFunction__c, 'UTF-8')
                               + '&moodlewsrestformat=json';
                for (Integer idx = 0; idx < toCreate.size(); idx++) {
                    String p = 'groups[' + idx + ']';
                    reqBody += '&' + p + '[courseid]=' + off.LMS_Course_Id__c.trim()
                            + '&' + p + '[name]=' + EncodingUtil.urlEncode(toCreate[idx], 'UTF-8')
                            + '&' + p + '[description]=' + EncodingUtil.urlEncode(toCreate[idx], 'UTF-8');
                }

                HttpRequest req = new HttpRequest();
                req.setEndpoint('callout:LMS_Integration');
                req.setMethod('POST');
                req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
                req.setBody(reqBody);
                req.setTimeout(120000);

                try {
                    HttpResponse res = new Http().send(req);
                    String resBody = res.getBody();
                    if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
                        Object parsed = JSON.deserializeUntyped(resBody);
                        if (parsed instanceof List<Object>) {
                            for (Object row : (List<Object>) parsed) {
                                Map<String, Object> g = (Map<String, Object>) row;
                                mappingList.add(String.valueOf(g.get('name')) + ':' + String.valueOf(g.get('id')));
                            }
                        } else if (parsed instanceof Map<String, Object>) {
                            Map<String, Object> errMap = (Map<String, Object>) parsed;
                            String msg = errMap.containsKey('message') ? String.valueOf(errMap.get('message')) : resBody;
                            off.LMS_Sync_Status__c = 'Failed';
                            off.LMS_Error__c = 'Section create sync failed: ' + msg;
                            logError('LMS_GroupSync_MoodleError', off.LMS_Error__c, String.valueOf(res.getStatusCode()), off.Id, reqBody, resBody);
                            continue;
                        }
                    } else {
                        off.LMS_Sync_Status__c = 'Failed';
                        off.LMS_Error__c = 'Section create sync failed. HTTP ' + res.getStatusCode();
                        logError('LMS_GroupSync_HTTPError', off.LMS_Error__c, String.valueOf(res.getStatusCode()), off.Id, reqBody, resBody);
                        continue;
                    }
                } catch (Exception e) {
                    off.LMS_Sync_Status__c = 'Failed';
                    off.LMS_Error__c = 'Section sync exception: ' + e.getMessage();
                    logError('LMS_GroupSync_Exception', off.LMS_Error__c, '500', off.Id, reqBody, e.getStackTraceString());
                    continue;
                }
            }

            off.Section_Mappings__c = String.join(mappingList, ', ');
            off.LMS_Sync_Status__c = 'Success';

            List<String> summaryParts = new List<String>();
            if (!addedNames.isEmpty()) summaryParts.add('Added sections: ' + String.join(addedNames, ', '));
            if (!removedNames.isEmpty()) summaryParts.add('Removed sections: ' + String.join(removedNames, ', '));
            if (summaryParts.isEmpty()) summaryParts.add('No section changes detected');
            off.LMS_Error__c = 'Course/Section sync successful on ' + Datetime.now() + '. ' + String.join(summaryParts, ' | ');
        }
    }

    private static void logError(String component, String message, String statusCode, String recordId, String request, String response) {
        Error_Handling__c log = new Error_Handling__c();
        log.Component_Type__c     = component;
        log.Error_message__c      = message != null && message.length() > 255 ? message.substring(0, 255) : message;
        log.Error_Status_Code__c  = statusCode;
        log.Record_Refrence_Id__c = recordId;
        log.Request__c            = request != null && request.length() > 131000 ? request.substring(0, 131000) : request;
        log.Response__c           = response != null && response.length() > 131000 ? response.substring(0, 131000) : response;
        pendingErrorLogs.add(log);
    }

    private static void commitLogs() {
        if (!pendingErrorLogs.isEmpty()) { Database.insert(pendingErrorLogs, false); pendingErrorLogs.clear(); }
    }
}