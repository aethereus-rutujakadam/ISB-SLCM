/**
 * @description Queueable job to send email notifications to event attendees
 *              Executes asynchronously after Event insert, allowing EventRelation records to be created
 * @author Salesforce Team
 * @date 2026-05-20
 */
public class EventAttendeeEmailQueueable implements Queueable {
    private static final String ASA_OWEA_DISPLAY_NAME = 'ISB ASA Admin';
    private static final String STUDENT_ADVISING_PAGE_REF = '{"type":"standard__webPage","attributes":{"url":"/ISBStudentSuccessPortal/s/advising"}}';
    private static Id cachedOrgWideEmailAddressId;
    
    private Set<Id> eventIds;
    
    public EventAttendeeEmailQueueable(Set<Id> eventIds) {
        this.eventIds = eventIds;
    }
    
    public void execute(QueueableContext context) {
        if (eventIds == null || eventIds.isEmpty()) {
            return;
        }

        try {
            System.debug('EventAttendeeEmailQueueable: Processing ' + eventIds.size() + ' events');
            
            // Query Event details including creator info
            Map<Id, Event> eventMap = new Map<Id, Event>([
                  SELECT Id, Subject, StartDateTime, EndDateTime, Location, 
                      Description, CreatedById, CreatedBy.Name, OwnerId
                FROM Event
                WHERE Id IN :eventIds
                WITH USER_MODE
            ]);

            // Query EventRelation records - they should exist by now
            List<EventRelation> attendees = [
                SELECT Id, EventId, RelationId, IsWhat, IsParent, Status
                FROM EventRelation
                WHERE EventId IN :eventIds
                AND IsWhat = false
                AND IsParent = false
                WITH USER_MODE
            ];

            System.debug('EventAttendeeEmailQueueable: Found ' + attendees.size() + ' EventRelation records');

            if (attendees.isEmpty()) {
                System.debug('EventAttendeeEmailQueueable: No attendees found - exiting');
                return;
            }

            // Separate User IDs and Contact IDs
            Set<Id> userIds = new Set<Id>();
            Set<Id> contactIds = new Set<Id>();

            for (EventRelation rel : attendees) {
                String relIdStr = String.valueOf(rel.RelationId);
                if (relIdStr.startsWith('005')) {
                    userIds.add(rel.RelationId); // User
                } else if (relIdStr.startsWith('003')) {
                    contactIds.add(rel.RelationId); // Contact
                }
            }

            System.debug('EventAttendeeEmailQueueable: ' + userIds.size() + ' users, ' + contactIds.size() + ' contacts');

            // Query User information
            Map<Id, User> userById = new Map<Id, User>([
                SELECT Id, Email, Name, IsActive
                FROM User
                WHERE Id IN :userIds
            ]);

            // Query Contact information. In USER_MODE, some profiles cannot read HasOptedOutOfEmail.
            // Build query dynamically so we do not fail the entire queueable for that user.
            Boolean canReadOptOutField = canReadContactOptOutField();
            String contactQuery = canReadOptOutField
                ? 'SELECT Id, Email, Name, HasOptedOutOfEmail, New_Admit_Email__c FROM Contact WHERE Id IN :contactIds WITH USER_MODE'
                : 'SELECT Id, Email, Name, New_Admit_Email__c FROM Contact WHERE Id IN :contactIds WITH USER_MODE';
            Map<Id, Contact> contactById = new Map<Id, Contact>((List<Contact>)Database.query(contactQuery));

            System.debug('EventAttendeeEmailQueueable: Queried ' + userById.size() + ' users and ' + contactById.size() + ' contacts');

            // Build email list
            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
            Set<String> queuedEmailAddresses = new Set<String>();
            Id senderOrgWideEmailId = getSenderOrgWideEmailAddressId();

            for (EventRelation rel : attendees) {
                Event evt = eventMap.get(rel.EventId);
                if (evt == null) {
                    continue;
                }

                String recipientEmail;
                String recipientName;

                // Send emails to both User and Contact attendees.
                String relIdStr = String.valueOf(rel.RelationId);
                if (relIdStr.startsWith('005')) {
                    User u = userById.get(rel.RelationId);
                    if (u == null || !u.IsActive || String.isBlank(u.Email)) {
                        continue;
                    }
                    recipientEmail = u.Email;
                    recipientName = u.Name;
                } else if (relIdStr.startsWith('003')) {
                    Contact c = contactById.get(rel.RelationId);
                    Boolean contactOptedOut = canReadOptOutField && c != null && c.HasOptedOutOfEmail;
                    if (c == null || contactOptedOut) {
                        continue;
                    }
                    recipientEmail = getPreferredContactEmail(c);
                    if (String.isBlank(recipientEmail)) {
                        continue;
                    }
                    recipientName = c.Name;
                } else {
                    continue;
                }

                String dedupeKey = recipientEmail != null ? recipientEmail.trim().toLowerCase() : null;
                if (String.isBlank(dedupeKey) || queuedEmailAddresses.contains(dedupeKey)) {
                    continue;
                }
                queuedEmailAddresses.add(dedupeKey);

                // Create email message
                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setToAddresses(new List<String>{ recipientEmail });
                email.setSubject('Event Invitation: ' + evt.Subject);

                // Format date/time
                String startTime = evt.StartDateTime != null ? 
                    evt.StartDateTime.format('MMMM d, yyyy h:mm a') : 'Not specified';
                String endTime = evt.EndDateTime != null ? 
                    evt.EndDateTime.format('h:mm a') : 'Not specified';

                // Build email body
                String emailBody = 'Dear ' + recipientName + ',\n\n';
                emailBody += 'You have been invited to the following event:\n\n';
                emailBody += 'Event: ' + evt.Subject + '\n';
                emailBody += 'Organized by: ' + evt.CreatedBy.Name + '\n';
                emailBody += 'Start: ' + startTime + '\n';
                emailBody += 'End: ' + endTime + '\n';
                
                if (String.isNotBlank(evt.Location)) {
                    emailBody += 'Location: ' + evt.Location + '\n';
                }
                
                if (String.isNotBlank(evt.Description)) {
                    emailBody += '\nDescription:\n' + evt.Description + '\n';
                }
                
                emailBody += '\nPlease mark your calendar accordingly.\n\n';
                emailBody += 'Best regards,\n';
                emailBody += 'Academic Advising Team';

                email.setPlainTextBody(emailBody);
                if (senderOrgWideEmailId != null) {
                    email.setOrgWideEmailAddressId(senderOrgWideEmailId);
                }
                emails.add(email);
            }

            System.debug('EventAttendeeEmailQueueable: Prepared ' + emails.size() + ' emails to send');
            
            if (emails.isEmpty()) {
                System.debug('EventAttendeeEmailQueueable: WARNING - No emails prepared. Check if attendees have valid email addresses.');
            }

            // Send emails in batches (max 10 per send)
            if (!emails.isEmpty()) {
                Integer batchSize = 10;
                for (Integer i = 0; i < emails.size(); i += batchSize) {
                    Integer endIndex = Math.min(i + batchSize, emails.size());
                    List<Messaging.SingleEmailMessage> batch = new List<Messaging.SingleEmailMessage>();
                    for (Integer j = i; j < endIndex; j++) {
                        batch.add(emails[j]);
                    }
                    List<Messaging.SendEmailResult> results = Messaging.sendEmail(batch, false);
                    
                    // Log any email failures
                    for (Messaging.SendEmailResult result : results) {
                        if (!result.isSuccess()) {
                            System.debug('EventAttendeeEmailQueueable: Email send error - ' + result.getErrors()[0].getMessage());
                        }
                    }
                }
                System.debug('EventAttendeeEmailQueueable: Successfully sent ' + emails.size() + ' emails');
            }

            // Send in-app Custom Notifications to attendees
            sendInAppNotifications(attendees, eventMap, userById, contactById, canReadOptOutField);

        } catch (Exception ex) {
            System.debug('EventAttendeeEmailQueueable.execute error: ' + ex.getMessage());
            System.debug('EventAttendeeEmailQueueable.execute stack trace: ' + ex.getStackTraceString());
        }
    }
    
    /**
     * @description Sends in-app Custom Notifications to event attendees
     * @param attendees List of EventRelation records
     * @param eventMap Map of Event records by Id
     * @param userById Map of User records by Id
     * @param contactById Map of Contact records by Id
     */
    private static void sendInAppNotifications(
        List<EventRelation> attendees, 
        Map<Id, Event> eventMap,
        Map<Id, User> userById,
        Map<Id, Contact> contactById,
        Boolean canReadOptOutField
    ) {
        try {
            // Collect recipient User IDs (Custom Notifications only work for Users)
            // For standalone event notifications, only student users (mapped from
            // Contact attendees) should receive in-app notifications.
            Set<Id> recipientUserIds = new Set<Id>();
            Map<Id, Id> contactToUserId = new Map<Id, Id>(); // Map Contact to User
            
            // For User attendees, add directly
            for (EventRelation rel : attendees) {
                Event evt = eventMap.get(rel.EventId);
                if (evt == null) {
                    continue;
                }
                
                String relIdStr = String.valueOf(rel.RelationId);
                if (relIdStr.startsWith('003')) {
                    // Contact attendee - need to find their linked User
                    Contact c = contactById.get(rel.RelationId);
                    Boolean contactOptedOut = canReadOptOutField && c != null && c.HasOptedOutOfEmail;
                    if (c != null && !contactOptedOut) {
                        contactToUserId.put(c.Id, null); // Will populate in next query
                    }
                }
            }
            
            // Resolve Contact attendees to active Users via User.ContactId
            if (!contactToUserId.isEmpty()) {
                for (User u : [
                    SELECT Id, ContactId
                    FROM User
                    WHERE ContactId IN :contactToUserId.keySet()
                    AND IsActive = TRUE
                    WITH USER_MODE
                ]) {
                    contactToUserId.put(u.ContactId, u.Id);
                    recipientUserIds.add(u.Id);
                }
            }
            
            System.debug('EventAttendeeEmailQueueable: Sending notifications to ' + recipientUserIds.size() + ' users');
            
            if (recipientUserIds.isEmpty()) {
                return;
            }
            
            // Send Custom Notification for each event
            for (Id eventId : eventMap.keySet()) {
                Event evt = eventMap.get(eventId);
                
                // Get all recipient user IDs for this event
                Set<Id> eventRecipients = new Set<Id>();

                for (EventRelation rel : attendees) {
                    if (rel.EventId != eventId) {
                        continue;
                    }
                    
                    String relIdStr = String.valueOf(rel.RelationId);
                    if (relIdStr.startsWith('003')) {
                        Id linkedUserId = contactToUserId.get(rel.RelationId);
                        if (linkedUserId != null) {
                            eventRecipients.add(linkedUserId);
                        }
                    }
                }
                
                if (eventRecipients.isEmpty()) {
                    continue;
                }
                
                // Create Custom Notification
                Messaging.CustomNotification notification = new Messaging.CustomNotification();
                
                // Format date/time for notification body
                String startTime = evt.StartDateTime != null ? 
                    evt.StartDateTime.format('MMM d, h:mm a') : 'TBD';
                
                String notificationBody = 'Event: ' + evt.Subject + ' | ' + startTime;
                if (String.isNotBlank(evt.Location)) {
                    notificationBody += ' | ' + evt.Location;
                }
                
                notification.setTitle('New Event Invitation');
                notification.setBody(notificationBody);
                Id notificationTypeId = getEventNotificationTypeId();
                if (notificationTypeId == null) {
                    System.debug('EventAttendeeEmailQueueable: No Custom Notification Type found. Skipping in-app notification for event ' + evt.Id);
                    continue;
                }
                notification.setNotificationTypeId(notificationTypeId);
                notification.setTargetPageRef(STUDENT_ADVISING_PAGE_REF);
                
                // Convert Set<Id> to Set<String> for send()
                Set<String> recipientIds = new Set<String>();
                for (Id userId : eventRecipients) {
                    recipientIds.add(String.valueOf(userId));
                }

                System.debug('EventAttendeeEmailQueueable: Notification recipients for event ' + evt.Id + ' => ' + recipientIds);
                
                // Send to all recipients for this event
                notification.send(recipientIds);
                
                System.debug('EventAttendeeEmailQueueable: Sent notification for event ' + evt.Subject + ' to ' + eventRecipients.size() + ' users');
            }
            
        } catch (Exception ex) {
            System.debug('EventAttendeeEmailQueueable.sendInAppNotifications error: ' + ex.getMessage());
            System.debug('EventAttendeeEmailQueueable.sendInAppNotifications stack trace: ' + ex.getStackTraceString());
        }
    }
    
    /**
     * @description Gets the CustomNotificationType ID for event notifications
     * @return Id of the CustomNotificationType, or null if not found
     */
    private static Id getEventNotificationTypeId() {
        try {
            CustomNotificationType notifType = [
                SELECT Id, DeveloperName 
                FROM CustomNotificationType 
                WHERE DeveloperName = 'Event_Notification' 
                LIMIT 1
            ];
            return notifType.Id;
        } catch (Exception ex) {
            System.debug('EventAttendeeEmailQueueable: Event_Notification type not found, attempting fallback');
            try {
                // Fallback to Workshop_Notification if Event_Notification doesn't exist
                CustomNotificationType notifType = [
                    SELECT Id, DeveloperName 
                    FROM CustomNotificationType 
                    WHERE DeveloperName = 'Workshop_Notification' 
                    LIMIT 1
                ];
                return notifType.Id;
            } catch (Exception ex2) {
                System.debug('EventAttendeeEmailQueueable: No notification type found - ' + ex2.getMessage());
                return null;
            }
        }
    }

    /**
     * @description Gets the Org-Wide Email Address Id for ISB ASA Admin sender
     * @return Id of OrgWideEmailAddress or null if not configured
     */
    private static Id getSenderOrgWideEmailAddressId() {
        if (cachedOrgWideEmailAddressId != null) {
            return cachedOrgWideEmailAddressId;
        }

        try {
            List<OrgWideEmailAddress> oweaList = [
                SELECT Id, DisplayName, Address
                FROM OrgWideEmailAddress
                WHERE DisplayName = :ASA_OWEA_DISPLAY_NAME
                LIMIT 1
            ];

            if (!oweaList.isEmpty()) {
                cachedOrgWideEmailAddressId = oweaList[0].Id;
                System.debug('EventAttendeeEmailQueueable: Using OrgWideEmailAddress ' + oweaList[0].DisplayName + ' <' + oweaList[0].Address + '>');
                return cachedOrgWideEmailAddressId;
            }

            System.debug('EventAttendeeEmailQueueable: WARNING - OrgWideEmailAddress not found for display name: ' + ASA_OWEA_DISPLAY_NAME);
            return null;
        } catch (Exception ex) {
            System.debug('EventAttendeeEmailQueueable: Error resolving OrgWideEmailAddress - ' + ex.getMessage());
            return null;
        }
    }

    /**
     * @description Returns true when Contact.HasOptedOutOfEmail is available in USER_MODE for current user
     */
    private static Boolean canReadContactOptOutField() {
        try {
            return Contact.HasOptedOutOfEmail.getDescribe().isAccessible();
        } catch (Exception ex) {
            System.debug('EventAttendeeEmailQueueable: Unable to describe HasOptedOutOfEmail - ' + ex.getMessage());
            return false;
        }
    }

    /**
     * @description Returns preferred contact email for event invitations.
     *              Priority: New_Admit_Email__c, then Contact.Email.
     */
    private static String getPreferredContactEmail(Contact c) {
        if (c == null) {
            return null;
        }
        if (String.isNotBlank(c.New_Admit_Email__c)) {
            return c.New_Admit_Email__c;
        }
        if (String.isNotBlank(c.Email)) {
            return c.Email;
        }
        return null;
    }
}