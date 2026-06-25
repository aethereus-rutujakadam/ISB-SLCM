/**
 * @description Handler for EventRelation trigger
 *              Sends email notifications to event attendees when they are added
 * @author Salesforce Team
 * @date 2026-05-20
 */
public with sharing class EventRelationHandler {
    
    /**
     * @description Handles after-insert EventRelation logic
     *              Sends email notifications to newly added event attendees
     * @param newRelations List of newly inserted EventRelation records
     */
    public static void handleAfterInsert(List<EventRelation> newRelations) {
        if (newRelations == null || newRelations.isEmpty()) {
            return;
        }

        try {
            System.debug('EventRelationHandler: Processing ' + newRelations.size() + ' EventRelation records');
            
            // Filter for person relations only (IsWhat = false means Person)
            List<EventRelation> personRelations = new List<EventRelation>();
            Set<Id> eventIds = new Set<Id>();
            
            for (EventRelation rel : newRelations) {
                if (!rel.IsWhat) {  // Person relation (User or Contact)
                    personRelations.add(rel);
                    eventIds.add(rel.EventId);
                }
            }

            System.debug('EventRelationHandler: Found ' + personRelations.size() + ' person relations');
            
            if (personRelations.isEmpty()) {
                return;
            }

            // Query Event details including creator info
            Map<Id, Event> eventMap = new Map<Id, Event>([
                SELECT Id, Subject, StartDateTime, EndDateTime, Location, 
                       Description, CreatedById, CreatedBy.Name
                FROM Event
                WHERE Id IN :eventIds
                WITH SECURITY_ENFORCED
            ]);

            System.debug('EventRelationHandler: Found ' + eventMap.size() + ' events');

            // Separate User IDs and Contact IDs
            Set<Id> userIds = new Set<Id>();
            Set<Id> contactIds = new Set<Id>();

            for (EventRelation rel : personRelations) {
                String relIdStr = String.valueOf(rel.RelationId);
                if (relIdStr.startsWith('005')) {
                    userIds.add(rel.RelationId); // User
                } else if (relIdStr.startsWith('003')) {
                    contactIds.add(rel.RelationId); // Contact
                }
            }

            System.debug('EventRelationHandler: ' + userIds.size() + ' users, ' + contactIds.size() + ' contacts');

            // Query User information
            Map<Id, User> userById = new Map<Id, User>([
                SELECT Id, Email, Name, IsActive
                FROM User
                WHERE Id IN :userIds
            ]);

            // Query Contact information
            Map<Id, Contact> contactById = new Map<Id, Contact>([
                SELECT Id, Email, Name, HasOptedOutOfEmail
                FROM Contact
                WHERE Id IN :contactIds
                WITH SECURITY_ENFORCED
            ]);

            // Build email list
            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

            for (EventRelation rel : personRelations) {
                Event evt = eventMap.get(rel.EventId);
                if (evt == null) {
                    continue;
                }

                String recipientEmail;
                String recipientName;

                // Determine recipient based on RelationId type
                String relIdStr = String.valueOf(rel.RelationId);
                if (relIdStr.startsWith('005')) {
                    // User attendee
                    User u = userById.get(rel.RelationId);
                    if (u == null || !u.IsActive || String.isBlank(u.Email)) {
                        continue;
                    }
                    // Skip if this is the event creator (they don't need a notification)
                    if (u.Id == evt.CreatedById) {
                        System.debug('EventRelationHandler: Skipping creator ' + u.Name);
                        continue;
                    }
                    recipientEmail = u.Email;
                    recipientName = u.Name;
                } else if (relIdStr.startsWith('003')) {
                    // Contact attendee
                    Contact c = contactById.get(rel.RelationId);
                    if (c == null || c.HasOptedOutOfEmail || String.isBlank(c.Email)) {
                        continue;
                    }
                    recipientEmail = c.Email;
                    recipientName = c.Name;
                } else {
                    continue;
                }

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
                emails.add(email);
            }

            System.debug('EventRelationHandler: Prepared ' + emails.size() + ' emails to send');

            // Send emails in batches (max 10 per send)
            if (!emails.isEmpty()) {
                Integer batchSize = 10;
                for (Integer i = 0; i < emails.size(); i += batchSize) {
                    Integer endIndex = Math.min(i + batchSize, emails.size());
                    List<Messaging.SingleEmailMessage> batch = new List<Messaging.SingleEmailMessage>();
                    for (Integer j = i; j < endIndex; j++) {
                        batch.add(emails[j]);
                    }
                    Messaging.sendEmail(batch, false);
                }
                System.debug('EventRelationHandler: Successfully sent ' + emails.size() + ' emails');
            }

        } catch (Exception ex) {
            System.debug('EventRelationHandler.handleAfterInsert error: ' + ex.getMessage());
            System.debug('EventRelationHandler.handleAfterInsert stack trace: ' + ex.getStackTraceString());
        }
    }
}