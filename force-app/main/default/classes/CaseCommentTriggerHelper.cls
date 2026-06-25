public class CaseCommentTriggerHelper {
    
    // Configuration class for role settings using Custom Labels
    public class NotificationConfig {
        public Set<String> notifyCaseCreatorRoles {
            get {
                return parseRolesFromLabel('NOTIFY_CASE_CREATOR_ROLES', 
                    new Set<String>{'RO Level 1', 'RO Level 2', 'RO HOD' , 'ASA Senior Manager','Academic Associate','Program Office'});
            }
        }
        
        public Set<String> notifyPreviousCommenterRoles {
            get {
                return parseRolesFromLabel('NOTIFY_PREVIOUS_COMMENTER_ROLES', 
                    new Set<String>{'rkada Customer Person Account'});
            }
        }
        
        public String notificationTypeDeveloperName {
            get {
                // Check if label exists using try-catch
                try {
                    String labelValue = System.Label.NOTIFICATION_TYPE_NAME;
                    return String.isNotBlank(labelValue) ? labelValue : 'Case_Comment_Added';
                } catch (Exception e) {
                    return 'Case_Comment_Added';
                }
            }
        }
        
        public String notificationTitle {
            get {
                // Check if label exists using try-catch
                try {
                    String labelValue = System.Label.NOTIFICATION_TITLE;
                    return String.isNotBlank(labelValue) ? labelValue : 'New Case Comment Added';
                } catch (Exception e) {
                    return 'New Case Comment Added';
                }
            }
        }
        
        public String notificationBodyTemplate {
            get {
                // Check if label exists using try-catch
                try {
                    String labelValue = System.Label.NOTIFICATION_BODY_TEMPLATE;
                    return String.isNotBlank(labelValue) ? labelValue : 'A new comment has been added to Case: {0}';
                } catch (Exception e) {
                    return 'A new comment has been added to Case: {0}';
                }
            }
        }
        
        // Helper method to parse roles from Custom Labels
        private Set<String> parseRolesFromLabel(String labelName, Set<String> defaultRoles) {
            try {
                // Use dynamic reference based on label name
                String labelValue = getLabelValue(labelName);
                if (String.isNotBlank(labelValue)) {
                    Set<String> roles = new Set<String>();
                    for (String role : labelValue.split(',')) {
                        String trimmedRole = role.trim();
                        if (String.isNotBlank(trimmedRole)) {
                            roles.add(trimmedRole);
                        }
                    }
                    return roles;
                }
            } catch (Exception e) {
                System.debug('Error parsing Custom Label ' + labelName + ': ' + e.getMessage());
            }
            return defaultRoles;
        }
        
        // Helper method to get label value dynamically
        private String getLabelValue(String labelName) {
            // Use a switch or if-else to handle different label names
            if (labelName == 'NOTIFY_CASE_CREATOR_ROLES') {
                return System.Label.NOTIFY_CASE_CREATOR_ROLES;
            } else if (labelName == 'NOTIFY_PREVIOUS_COMMENTER_ROLES') {
                return System.Label.NOTIFY_PREVIOUS_COMMENTER_ROLES;
            } else if (labelName == 'NOTIFICATION_TYPE_NAME') {
                return System.Label.NOTIFICATION_TYPE_NAME;
            } else if (labelName == 'NOTIFICATION_TITLE') {
                return System.Label.NOTIFICATION_TITLE;
            } else if (labelName == 'NOTIFICATION_BODY_TEMPLATE') {
                return System.Label.NOTIFICATION_BODY_TEMPLATE;
            }
            return null;
        }
    }
    
    // Rest of the class remains the same...
    public static void processNotifications(List<CaseComment> comments, Set<Id> caseIds) {
        NotificationConfig config = new NotificationConfig();
        
        // Get related data
        Map<Id, Case> caseMap = getCaseMap(caseIds);
        Set<Id> creatorIds = getCommentCreatorIds(comments);
        Map<Id, User> userMap = getUserMap(creatorIds);
        
        // Identify recipients based on business logic
        Set<Id> recipients = identifyNotificationRecipients(comments, caseMap, userMap, config);
        
        // Send notifications if recipients exist
        if (!recipients.isEmpty()) {
            sendNotifications(recipients, comments, caseMap, config);
        }
    }
    
    private static Map<Id, Case> getCaseMap(Set<Id> caseIds) {
        return new Map<Id, Case>([
            SELECT Id, CreatedById, CaseNumber, Subject
            FROM Case 
            WHERE Id IN :caseIds
        ]);
    }
    
    private static Set<Id> getCommentCreatorIds(List<CaseComment> comments) {
        Set<Id> creatorIds = new Set<Id>();
        for (CaseComment comment : comments) {
            creatorIds.add(comment.CreatedById);
        }
        return creatorIds;
    }
    
    private static Map<Id, User> getUserMap(Set<Id> userIds) {
        return new Map<Id, User>([
            SELECT Id, UserRole.Name, Name, Email
            FROM User 
            WHERE Id IN :userIds
        ]);
    }
    
    private static Set<Id> identifyNotificationRecipients(
        List<CaseComment> comments, 
        Map<Id, Case> caseMap, 
        Map<Id, User> userMap,
        NotificationConfig config
    ) {
        Set<Id> recipients = new Set<Id>();
        Map<Id, Id> caseToPreviousCommentCreatorMap = getPreviousCommentCreators(comments);
        
        for (CaseComment comment : comments) {
            Case relatedCase = caseMap.get(comment.ParentId);
            User commentCreator = userMap.get(comment.CreatedById);
            
            if (relatedCase == null || commentCreator == null) continue;
            
            String userRole = getUserRole(commentCreator);
            
            // Check if comment creator should trigger notifications
            if (shouldNotifyCaseCreator(userRole, config)) {
                recipients.add(relatedCase.CreatedById);
                
            } else if (shouldNotifyPreviousCommenter(userRole, config)) {
                Id previousCommentCreator = caseToPreviousCommentCreatorMap.get(comment.ParentId);
                
                // Ensure we don't notify the same user who just commented
                if (previousCommentCreator != null && 
                    previousCommentCreator != comment.CreatedById &&
                    previousCommentCreator != relatedCase.CreatedById) {
                    recipients.add(previousCommentCreator);
                }
            }
        }
        
        return recipients;
    }
    
    private static Map<Id, Id> getPreviousCommentCreators(List<CaseComment> comments) {
        Map<Id, Id> caseToPreviousCreatorMap = new Map<Id, Id>();
        Set<Id> caseIds = new Set<Id>();
        
        for (CaseComment comment : comments) {
            caseIds.add(comment.ParentId);
        }
        
        // Aggregate query to get latest comment before these new ones
        for (AggregateResult agg : [
            SELECT ParentId, MAX(CreatedDate) latestDate
            FROM CaseComment
            WHERE ParentId IN :caseIds
              AND Id NOT IN :comments
            GROUP BY ParentId
        ]) {
            Id caseId = (Id)agg.get('ParentId');
            Datetime latestDate = (Datetime)agg.get('latestDate');
            
            // Get the actual comment for that latest date
            List<CaseComment> latestComments = [
                SELECT CreatedById
                FROM CaseComment
                WHERE ParentId = :caseId
                  AND CreatedDate = :latestDate
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            
            if (!latestComments.isEmpty()) {
                caseToPreviousCreatorMap.put(caseId, latestComments[0].CreatedById);
            }
        }
        
        return caseToPreviousCreatorMap;
    }
    
    private static String getUserRole(User userRecord) {
        return userRecord.UserRole != null ? userRecord.UserRole.Name : '';
    }
    
    private static Boolean shouldNotifyCaseCreator(String userRole, NotificationConfig config) {
        for (String role : config.notifyCaseCreatorRoles) {
            if (userRole.contains(role)) {
                return true;
            }
        }
        return false;
    }
    
    private static Boolean shouldNotifyPreviousCommenter(String userRole, NotificationConfig config) {
        for (String role : config.notifyPreviousCommenterRoles) {
            if (userRole.contains(role)) {
                return true;
            }
        }
        return false;
    }
    
    private static void sendNotifications(
        Set<Id> recipients, 
        List<CaseComment> comments, 
        Map<Id, Case> caseMap,
        NotificationConfig config
    ) {
        // Get notification type
        CustomNotificationType notificationType = getNotificationType(config.notificationTypeDeveloperName);
        if (notificationType == null) {
            System.debug('Notification type not found: ' + config.notificationTypeDeveloperName);
            return;
        }
        
        // Group comments by case for batch processing
        Map<Id, List<CaseComment>> caseToCommentsMap = new Map<Id, List<CaseComment>>();
        for (CaseComment comment : comments) {
            if (!caseToCommentsMap.containsKey(comment.ParentId)) {
                caseToCommentsMap.put(comment.ParentId, new List<CaseComment>());
            }
            caseToCommentsMap.get(comment.ParentId).add(comment);
        }
        
        // Send notifications
        List<Messaging.CustomNotification> notifications = new List<Messaging.CustomNotification>();
        List<String> errors = new List<String>();
        
        for (Id caseId : caseToCommentsMap.keySet()) {
            Case relatedCase = caseMap.get(caseId);
            if (relatedCase == null) continue;
            
            String notificationBody = String.format(
                config.notificationBodyTemplate, 
                new List<String>{relatedCase.CaseNumber}
            );
            
            // Send to each recipient
            for (Id recipientId : recipients) {
                try {
                    Messaging.CustomNotification notification = new Messaging.CustomNotification();
                    notification.setTitle(config.notificationTitle);
                    notification.setBody(notificationBody);
                    notification.setNotificationTypeId(notificationType.Id);
                    notification.setTargetId(caseId);
                    notification.setSenderId(UserInfo.getUserId());
                    
                    // Send notification
                    notification.send(new Set<String>{recipientId});
                    notifications.add(notification);
                    
                } catch (Exception e) {
                    errors.add('Error sending to user ' + recipientId + 
                              ' for case ' + relatedCase.CaseNumber + 
                              ': ' + e.getMessage());
                }
            }
        }
        
        // Log errors if any
        if (!errors.isEmpty()) {
            System.debug('Notification errors: ' + errors);
            logErrors(errors);
        }
    }
    
    private static CustomNotificationType getNotificationType(String developerName) {
        try {
            return [
                SELECT Id, DeveloperName 
                FROM CustomNotificationType 
                WHERE DeveloperName = :developerName
                LIMIT 1
            ];
        } catch (QueryException e) {
            return null;
        }
    }
    
    private static void logErrors(List<String> errorMessages) {
        // Implement custom error logging if needed
        // Example: insert a custom Error_Log__c record
    }
}