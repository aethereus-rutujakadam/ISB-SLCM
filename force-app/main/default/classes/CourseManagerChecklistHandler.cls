/**
 * @description Trigger handler for course_managers__c that assigns ownership of
 * Course_Checklist__c records to the manager's user.
 *
 * When a new course_managers__c record is created (manager assigned to offering + role),
 * this handler finds existing Course_Checklist__c records for that offering, role, and courseType,
 * and updates their OwnerId to the manager's user.
 *
 * Supports two scenarios:
 * 1. Excel Upload: Creates checklist header + items first, then manager is assigned
 * 2. Manager Creation: Manager is added, handler assigns ownership to existing checklists
 */
public class CourseManagerChecklistHandler {

    public static void handleAfterInsert(List<course_managers__c> newManagers) {
        Set<Id> offeringIds = new Set<Id>();
        Set<String> roles = new Set<String>();

        for (course_managers__c mgr : newManagers) {
            if (mgr.Course_Offering__c != null && mgr.Role__c != null && mgr.User__c != null) {
                offeringIds.add(mgr.Course_Offering__c);
                roles.add(mgr.Role__c);
            }
        }

        // Keep Payment Information ownership fields aligned to role mapping.
        // Delivery Manager -> SPOC, Manager -> Course Manager.
        updatePaymentInfoSpocForDeliveryManagers(newManagers);
        updatePaymentInfoCourseManagerForManagers(newManagers);

        if (offeringIds.isEmpty()) return;

        // Query Course Offerings with their Course Type
        Map<Id, CourseOffering> offeringsMap = new Map<Id, CourseOffering>([
            SELECT Id, Name, Course_Type__c, Term_Start_Date__c, Term_To_Date__c
            FROM CourseOffering
            WHERE Id IN :offeringIds
        ]);

        if (offeringsMap.isEmpty()) return;

        Set<String> courseTypes = new Set<String>();
        for (CourseOffering offering : offeringsMap.values()) {
            if (!String.isBlank(offering.Course_Type__c)) {
                courseTypes.add(offering.Course_Type__c);
            }
        }

        if (courseTypes.isEmpty()) return;

        // Get active Zoho templates for roles and course types in scope.
         List<Course_Checklist_Item_Template__c> allTemplates = [
             SELECT Id, Subject__c, Description__c, Priority__c, Owner_Roles__c, Course_Type__c,
                 Template_Type__c,
                   Start_Date__c, End_Date__c, Reminder_Logic_Calculation__c, Reminder_Reference_Days__c
            FROM Course_Checklist_Item_Template__c
            WHERE Owner_Roles__c IN :roles
              AND Active__c = true
                            AND Template_Type__c = 'Zoho Tasks'
              AND Course_Type__c IN :courseTypes
        ];

        if (allTemplates.isEmpty()) return;

        Map<String, List<Course_Checklist_Item_Template__c>> templatesByRoleAndType =
            new Map<String, List<Course_Checklist_Item_Template__c>>();
        for (Course_Checklist_Item_Template__c t : allTemplates) {
            if (!isZohoTasksTemplate(t.Template_Type__c)) continue;
            String key = t.Owner_Roles__c + '|' + t.Course_Type__c;
            if (!templatesByRoleAndType.containsKey(key)) {
                templatesByRoleAndType.put(key, new List<Course_Checklist_Item_Template__c>());
            }
            templatesByRoleAndType.get(key).add(t);
        }

        Id checklistItemRecordTypeId = getChecklistItemRecordTypeId('Course Manager Checklist');
        Id checklistRecordTypeId = getChecklistRecordTypeId('Course Manager Checklist');

        List<Course_Checklist__c> checklistsToInsert = new List<Course_Checklist__c>();
        List<course_managers__c> validManagers = new List<course_managers__c>();

        for (course_managers__c mgr : newManagers) {
            if (mgr.Course_Offering__c == null || mgr.Role__c == null || mgr.User__c == null) continue;
            
            CourseOffering offering = offeringsMap.get(mgr.Course_Offering__c);
            if (offering == null) continue;

            if (String.isBlank(offering.Course_Type__c)) continue;

            String templateKey = mgr.Role__c + '|' + offering.Course_Type__c;
            if (!templatesByRoleAndType.containsKey(templateKey)) continue;

            Course_Checklist__c cl = new Course_Checklist__c(
                RecordTypeId = checklistRecordTypeId,
                Name = 'Course Manager Checklist for - ' + mgr.Role__c,
                Course_Offering__c = mgr.Course_Offering__c,
                Role__c = mgr.Role__c,
                OwnerId = mgr.User__c,
                Status__c = 'Active',
                Checklist_Type__c = 'Zoho Tasks'
            );
            checklistsToInsert.add(cl);
            validManagers.add(mgr);
        }

        if (!checklistsToInsert.isEmpty()) {
            insert checklistsToInsert;

            List<Course_Checklist_Item__c> itemsToInsert = new List<Course_Checklist_Item__c>();
            
            for (Integer i = 0; i < validManagers.size(); i++) {
                course_managers__c mgr = validManagers[i];
                Course_Checklist__c cl = checklistsToInsert[i];
                CourseOffering offering = offeringsMap.get(mgr.Course_Offering__c);
                if (offering == null || String.isBlank(offering.Course_Type__c)) continue;

                String templateKey = mgr.Role__c + '|' + offering.Course_Type__c;
                List<Course_Checklist_Item_Template__c> matchingTemplates = templatesByRoleAndType.get(templateKey);
                if (matchingTemplates == null || matchingTemplates.isEmpty()) continue;

                for (Course_Checklist_Item_Template__c t : matchingTemplates) {
                    if (String.isBlank(t.Template_Type__c)) continue;
                    if (!isZohoTasksTemplate(t.Template_Type__c)) continue;

                    Integer reminderReferenceDays = calculateReminderReferenceDays(
                        t.Start_Date__c,
                        t.Reminder_Logic_Calculation__c,
                        offering
                    );

                    Date reminderDate = calculateReminderDate(
                        t.Start_Date__c,
                        t.Reminder_Logic_Calculation__c,
                        offering,
                        reminderReferenceDays
                    );

                    itemsToInsert.add(new Course_Checklist_Item__c(
                        RecordTypeId = checklistItemRecordTypeId,
                        Course_Checklist__c = cl.Id,
                        Course_Offering__c = mgr.Course_Offering__c,
                        Subject__c = t.Subject__c,
                        Description__c = t.Description__c,
                        Priority__c = t.Priority__c,
                        Role__c = t.Owner_Roles__c,
                        Status__c = 'Not Started',
                        Checklist_Item_Type__c = 'Zoho Tasks',
                        Course_Checklist_Item_Template__c = t.Id,
                        // Always stamp item course type from the offering driving checklist creation.
                        Course_Type__c = offering.Course_Type__c,
                        Start_Date__c = t.Start_Date__c,
                        End_Date__c = t.End_Date__c,
                        Reminder_Logic_Calculation__c = t.Reminder_Logic_Calculation__c,
                        Reminder_Reference_Days__c = reminderReferenceDays
                    ));
                }
            }

            if (!itemsToInsert.isEmpty()) {
                insert itemsToInsert;
            }

            shareChecklists(checklistsToInsert);
        }

        sendNotifications(newManagers, offeringsMap);
    }

    private static Boolean isZohoTasksTemplate(String templateType) {
        return !String.isBlank(templateType)
            && templateType.trim().toLowerCase() == 'zoho tasks';
    }

    private static Id getChecklistRecordTypeId(String recordTypeName) {
        List<RecordType> rts = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Course_Checklist__c'
              AND Name = :recordTypeName
            LIMIT 1
        ];
        return rts.isEmpty() ? null : rts[0].Id;
    }

    private static Id getChecklistItemRecordTypeId(String recordTypeName) {
        List<RecordType> rts = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Course_Checklist_Item__c'
              AND Name = :recordTypeName
            LIMIT 1
        ];
        return rts.isEmpty() ? null : rts[0].Id;
    }

    private static void shareChecklists(List<Course_Checklist__c> checklists) {
        List<Course_Checklist__Share> sharesToInsert = new List<Course_Checklist__Share>();

        for (Course_Checklist__c cl : checklists) {
            if (cl.OwnerId == null) continue;
            sharesToInsert.add(new Course_Checklist__Share(
                ParentId      = cl.Id,
                UserOrGroupId = cl.OwnerId,
                AccessLevel   = 'Edit',
                RowCause      = Schema.Course_Checklist__Share.RowCause.Manual
            ));
        }

        if (!sharesToInsert.isEmpty()) {
            Database.insert(sharesToInsert, false);
        }
    }



    private static Integer calculateReminderReferenceDays(
        Date templateStartDate,
        String reminderLogic,
        CourseOffering offering
    ) {
        if (templateStartDate == null || String.isBlank(reminderLogic) || offering == null) {
            return null;
        }

        if (reminderLogic == 'Term Start' && offering.Term_Start_Date__c != null) {
            return templateStartDate.daysBetween(offering.Term_Start_Date__c);
        }

        if (reminderLogic == 'Term End' && offering.Term_To_Date__c != null) {
            return offering.Term_To_Date__c.daysBetween(templateStartDate);
        }

        return null;
    }

    private static Date calculateReminderDate(
        Date templateStartDate,
        String reminderLogic,
        CourseOffering offering,
        Integer reminderReferenceDays
    ) {
        if (templateStartDate == null || String.isBlank(reminderLogic) || offering == null || reminderReferenceDays == null) {
            return null;
        }

        if (reminderLogic == 'Term Start' && offering.Term_Start_Date__c != null) {
            return offering.Term_Start_Date__c.addDays(-reminderReferenceDays);
        }

        if (reminderLogic == 'Term End' && offering.Term_To_Date__c != null) {
            return offering.Term_To_Date__c.addDays(reminderReferenceDays);
        }

        return null;
    }

    private static void sendNotifications(
        List<course_managers__c> managers,
        Map<Id, CourseOffering> offeringsMap
    ) {
        Set<Id> userIds = new Set<Id>();
        Map<Id, List<String>> assignmentLinesByUser = new Map<Id, List<String>>();
        Set<String> uniqueAssignments = new Set<String>();

        for (course_managers__c mgr : managers) {
            if (mgr.User__c != null) {
                userIds.add(mgr.User__c);
            }

            if (mgr.User__c == null || mgr.Course_Offering__c == null || String.isBlank(mgr.Role__c)) continue;

            String assignmentKey = String.valueOf(mgr.User__c) + '|' + String.valueOf(mgr.Course_Offering__c) + '|' + mgr.Role__c;
            if (uniqueAssignments.contains(assignmentKey)) continue;
            uniqueAssignments.add(assignmentKey);

            CourseOffering offering = offeringsMap.get(mgr.Course_Offering__c);
            String offeringName = offering != null ? offering.Name : String.valueOf(mgr.Course_Offering__c);
            String assignedRole = mgr.Role__c == 'Manager' ? 'Course Manager' : mgr.Role__c;

            if (!assignmentLinesByUser.containsKey(mgr.User__c)) {
                assignmentLinesByUser.put(mgr.User__c, new List<String>());
            }
            assignmentLinesByUser.get(mgr.User__c).add('- ' + assignedRole + ' for ' + offeringName);
        }

        Map<Id, User> usersById = new Map<Id, User>();
        if (!userIds.isEmpty()) {
            usersById = new Map<Id, User>([
                SELECT Id, Email
                FROM User
                WHERE Id IN :userIds
            ]);
        }

        String notifTypeId;
        List<CustomNotificationType> notifTypes = [
            SELECT Id FROM CustomNotificationType LIMIT 1
        ];
        if (!notifTypes.isEmpty()) {
            notifTypeId = notifTypes[0].Id;
        }

        List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();
    Set<String> notifiedAssignments = new Set<String>();

        for (course_managers__c mgr : managers) {
            if (mgr.User__c == null || mgr.Course_Offering__c == null || mgr.Role__c == null) continue;

            CourseOffering offering = offeringsMap.get(mgr.Course_Offering__c);
            String offeringName = offering != null ? offering.Name : '';

            String assignedRole = mgr.Role__c == 'Manager' ? 'Course Manager' : mgr.Role__c;
            String body = 'You have been assigned as the ' + assignedRole + ' for ' + offeringName + '.';
            String notificationKey = String.valueOf(mgr.User__c) + '|' + String.valueOf(mgr.Course_Offering__c) + '|' + mgr.Role__c;

            if (notifTypeId != null) {
                if (notifiedAssignments.contains(notificationKey)) continue;
                try {
                    Messaging.CustomNotification notif = new Messaging.CustomNotification();
                    notif.setNotificationTypeId(notifTypeId);
                    notif.setTargetId(mgr.Course_Offering__c);
                    notif.setTitle('Course Manager Assignment');
                    notif.setBody(body);
                    notif.send(new Set<String>{ String.valueOf(mgr.User__c) });
                    notifiedAssignments.add(notificationKey);
                } catch (Exception e) {
                    System.debug(LoggingLevel.WARN, 'CourseManagerChecklistHandler notification warning: ' + e.getMessage());
                }
            }
        }

        for (Id userId : assignmentLinesByUser.keySet()) {
            User assignedUser = usersById.get(userId);
            if (assignedUser == null || String.isBlank(assignedUser.Email)) continue;

            List<String> userAssignments = assignmentLinesByUser.get(userId);
            if (userAssignments == null || userAssignments.isEmpty()) continue;

            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{ assignedUser.Email });
            email.setSubject('Course Manager Assignment - ' + String.valueOf(userAssignments.size()) + ' Course Offering(s)');
            email.setPlainTextBody(
                'You have been assigned to the following course offering(s):\n\n'
                + String.join(userAssignments, '\n')
            );
            emailsToSend.add(email);
        }

        if (!emailsToSend.isEmpty()) {
            try {
                Messaging.sendEmail(emailsToSend, false);
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'CourseManagerChecklistHandler email warning: ' + e.getMessage());
            }
        }
    }

    private static void updatePaymentInfoSpocForDeliveryManagers(List<course_managers__c> managers) {
        Map<Id, Id> deliveryManagerByOffering = new Map<Id, Id>();

        for (course_managers__c mgr : managers) {
            if (mgr.Course_Offering__c == null || mgr.User__c == null || String.isBlank(mgr.Role__c)) {
                continue;
            }
            if (mgr.Role__c != 'Delivery Manager') {
                continue;
            }
            deliveryManagerByOffering.put(mgr.Course_Offering__c, mgr.User__c);
        }

        if (deliveryManagerByOffering.isEmpty()) {
            return;
        }

        List<Payment_Information__c> paymentsToUpdate = new List<Payment_Information__c>();
        for (Payment_Information__c payment : [
            SELECT Id, Course_Offering__c, SPOC__c, OwnerId
            FROM Payment_Information__c
            WHERE Course_Offering__c IN :deliveryManagerByOffering.keySet()
        ]) {
            Id targetSpoc = deliveryManagerByOffering.get(payment.Course_Offering__c);
            if (targetSpoc == null) {
                continue;
            }
            Boolean requiresUpdate = false;
            if (payment.SPOC__c != targetSpoc) {
                payment.SPOC__c = targetSpoc;
                requiresUpdate = true;
            }
            if (payment.OwnerId != targetSpoc) {
                payment.OwnerId = targetSpoc;
                requiresUpdate = true;
            }
            if (!requiresUpdate) {
                continue;
            }
            paymentsToUpdate.add(payment);
        }

        if (!paymentsToUpdate.isEmpty()) {
            Database.update(paymentsToUpdate, false);
        }
    }

    private static void updatePaymentInfoCourseManagerForManagers(List<course_managers__c> managers) {
        Map<Id, Id> managerByOffering = new Map<Id, Id>();

        for (course_managers__c mgr : managers) {
            if (mgr.Course_Offering__c == null || mgr.User__c == null || String.isBlank(mgr.Role__c)) {
                continue;
            }
            if (mgr.Role__c != 'Manager') {
                continue;
            }
            managerByOffering.put(mgr.Course_Offering__c, mgr.User__c);
        }

        if (managerByOffering.isEmpty()) {
            return;
        }

        List<Payment_Information__c> paymentsToUpdate = new List<Payment_Information__c>();
        for (Payment_Information__c payment : [
            SELECT Id, Course_Offering__c, Course_Manager__c
            FROM Payment_Information__c
            WHERE Course_Offering__c IN :managerByOffering.keySet()
        ]) {
            Id targetManager = managerByOffering.get(payment.Course_Offering__c);
                if (targetManager == null) {
                continue;
            }
                // Only update if the field is not already set to this manager
                if (payment.Course_Manager__c != targetManager) {
                    payment.Course_Manager__c = targetManager;
                    paymentsToUpdate.add(payment);
                }
        }

        if (!paymentsToUpdate.isEmpty()) {
            Database.update(paymentsToUpdate, false);
        }
    }

}