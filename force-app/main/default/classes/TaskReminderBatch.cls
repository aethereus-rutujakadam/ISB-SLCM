/**
 * @description Batch class to send consolidated Task Reminder emails and
 *              Custom Bell Notifications to portal student users.
 *
 *  Scope Rule:
 *    ONLY Tasks assigned to Users with the "Customer Community Plus" profile
 *    (i.e., active Student Portal users) are processed.
 *
 *  Email Output per Student:
 *    - One separate email listing all "Due Today" tasks + pending checklist items  (if any)
 *    - One separate email listing all "Overdue" tasks + overdue checklist items   (if any)
 *    - One consolidated Bell Notification (portal alert) summarising both
 *
 *  Course Checklist Items:
 *    Pending/overdue Course_Checklist_Item__c records linked to a student Contact
 *    who has an active portal User are queried in finish() and merged into the same
 *    per-student emails and bell notifications.
 *    Pending statuses included: Not Started, In Progress, Open, Blocked.
 *
 *  Schedule via TaskReminderBatchScheduler or run ad-hoc:
 *    Database.executeBatch(new TaskReminderBatch(), 200);
 */
public with sharing class TaskReminderBatch implements Database.Batchable<SObject>, Database.Stateful {

    // ─── Constants ────────────────────────────────────────────────────────────
    /** API name of the Custom Notification Type used for bell alerts. */
    private static final String NOTIF_DEV_NAME       = 'Task_Assigned_Custom';
    /** Profile name for Student Portal users. Change if your org uses a different name. */
    private static final String PORTAL_PROFILE_NAME  = 'Customer Community Plus User';

    // ─── Run-mode flags (set via constructor) ────────────────────────────────
    /** When true, "Due Today" emails and notifications are sent. */
    private final Boolean sendDueToday;
    /** When true, "Overdue" emails and notifications are sent. */
    private final Boolean sendOverdue;

    /** Default constructor – sends both due-today and overdue outputs. */
    public TaskReminderBatch() {
        this(true, true);
    }

    /**
     * @param sendDueToday Pass true to send Due Today emails/notifications.
     * @param sendOverdue  Pass true to send Overdue emails/notifications.
     */
    public TaskReminderBatch(Boolean sendDueToday, Boolean sendOverdue) {
        this.sendDueToday = (sendDueToday != null) ? sendDueToday : false;
        this.sendOverdue  = (sendOverdue  != null) ? sendOverdue  : false;
    }

    // ─── Stateful Maps (preserved across execute() chunks) ───────────────────
    private Map<Id, List<Task>> overdueMap  = new Map<Id, List<Task>>();
    private Map<Id, List<Task>> dueTodayMap = new Map<Id, List<Task>>();

    // Checklist item maps: keyed by portal User Id (resolved via User.ContactId)
    private Map<Id, List<Course_Checklist_Item__c>> overdueChecklistMap   = new Map<Id, List<Course_Checklist_Item__c>>();
    private Map<Id, List<Course_Checklist_Item__c>> dueTodayChecklistMap  = new Map<Id, List<Course_Checklist_Item__c>>();

    // ─── Start ────────────────────────────────────────────────────────────────
    public Database.QueryLocator start(Database.BatchableContext bc) {
        Date today = Date.today();
        return Database.getQueryLocator([
            SELECT Id, Subject, ActivityDate, Priority, OwnerId,
                   Owner.Name, Owner.Email
            FROM   Task
            WHERE  Status       != 'Completed'
            AND    ActivityDate <= :today
            AND    Owner.Profile.Name = :PORTAL_PROFILE_NAME
            AND    Owner.IsActive      = TRUE
            ORDER BY OwnerId, ActivityDate ASC
        ]);
    }

    // ─── Execute ──────────────────────────────────────────────────────────────
    public void execute(Database.BatchableContext bc, List<Task> scope) {

        Date today = Date.today();

        for (Task t : scope) {
            if (t.ActivityDate < today) {
                // ── Overdue ─────────────────────────────────────────────────
                if (!overdueMap.containsKey(t.OwnerId)) {
                    overdueMap.put(t.OwnerId, new List<Task>());
                }
                overdueMap.get(t.OwnerId).add(t);

            } else if (t.ActivityDate == today) {
                // ── Due Today ───────────────────────────────────────────────
                if (!dueTodayMap.containsKey(t.OwnerId)) {
                    dueTodayMap.put(t.OwnerId, new List<Task>());
                }
                dueTodayMap.get(t.OwnerId).add(t);
            }
        }
    }

    // ─── Finish ───────────────────────────────────────────────────────────────
    public void finish(Database.BatchableContext bc) {

        Date today = Date.today();

        // ── Step 1: Query pending/overdue Course Checklist Items ─────────────
        Set<String> completedStatuses = new Set<String>{ 'Completed', 'Waived', 'Closed' };

        List<Course_Checklist_Item__c> checklistItems = [
            SELECT Id, Subject__c, Due_Date__c, Priority__c, Status__c,
                   Course_Checklist__r.Student__c
            FROM   Course_Checklist_Item__c
            WHERE  Due_Date__c        <= :today
            AND    Status__c NOT IN   :completedStatuses
            AND    Course_Checklist__r.Student__c != null
        ];

        // ── Step 2: Resolve student Contacts → portal Users ──────────────────
        if (!checklistItems.isEmpty()) {
            Set<Id> studentContactIds = new Set<Id>();
            for (Course_Checklist_Item__c item : checklistItems) {
                studentContactIds.add(item.Course_Checklist__r.Student__c);
            }

            // Map ContactId → User (portal users only)
            Map<Id, Id> contactToUserId = new Map<Id, Id>();
            for (User u : [
                SELECT Id, ContactId
                FROM   User
                WHERE  ContactId IN :studentContactIds
                AND    Profile.Name = :PORTAL_PROFILE_NAME
                AND    IsActive = true
            ]) {
                contactToUserId.put(u.ContactId, u.Id);
            }

            // Populate checklist stateful maps
            for (Course_Checklist_Item__c item : checklistItems) {
                Id userId = contactToUserId.get(item.Course_Checklist__r.Student__c);
                if (userId == null) continue;

                if (item.Due_Date__c < today) {
                    if (!overdueChecklistMap.containsKey(userId)) {
                        overdueChecklistMap.put(userId, new List<Course_Checklist_Item__c>());
                    }
                    overdueChecklistMap.get(userId).add(item);
                } else {
                    if (!dueTodayChecklistMap.containsKey(userId)) {
                        dueTodayChecklistMap.put(userId, new List<Course_Checklist_Item__c>());
                    }
                    dueTodayChecklistMap.get(userId).add(item);
                }
            }
        }

        // ── Step 3: Collect all unique student owner IDs ──────────────────────
        Set<Id> allOwnerIds = new Set<Id>();
        allOwnerIds.addAll(overdueMap.keySet());
        allOwnerIds.addAll(dueTodayMap.keySet());
        allOwnerIds.addAll(overdueChecklistMap.keySet());
        allOwnerIds.addAll(dueTodayChecklistMap.keySet());

        if (allOwnerIds.isEmpty()) {
            System.debug('TaskReminderBatch: No portal users have due/overdue tasks or checklist items today.');
            return;
        }

        // Re-query user details (email, name) for all affected owners
        Map<Id, User> ownerMap = new Map<Id, User>([
            SELECT Id, Name, Email
            FROM   User
            WHERE  Id IN :allOwnerIds
        ]);

        // Fetch the Custom Notification Type Id (single SOQL call)
        Id notifTypeId = getCustomNotificationTypeId();

        // Build all email messages in one list – sent in a single bulk call
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Id ownerId : allOwnerIds) {

            User owner = ownerMap.get(ownerId);
            if (owner == null || String.isBlank(owner.Email)) {
                System.debug('TaskReminderBatch: Skipping owner ' + ownerId + ' – no email address found.');
                continue;
            }

            List<Task> dueTodayTasks = dueTodayMap.containsKey(ownerId)
                ? dueTodayMap.get(ownerId)
                : new List<Task>();

            List<Task> overdueTasks = overdueMap.containsKey(ownerId)
                ? overdueMap.get(ownerId)
                : new List<Task>();

            List<Course_Checklist_Item__c> dueTodayChecklist = dueTodayChecklistMap.containsKey(ownerId)
                ? dueTodayChecklistMap.get(ownerId)
                : new List<Course_Checklist_Item__c>();

            List<Course_Checklist_Item__c> overdueChecklist = overdueChecklistMap.containsKey(ownerId)
                ? overdueChecklistMap.get(ownerId)
                : new List<Course_Checklist_Item__c>();

            // ── EMAIL 1: Due Today ────────────────────────────────────────
            if (sendDueToday && (!dueTodayTasks.isEmpty() || !dueTodayChecklist.isEmpty())) {
                emails.add(buildDueTodayEmail(owner, dueTodayTasks, dueTodayChecklist));
            }

            // ── EMAIL 2: Overdue ──────────────────────────────────────────
            if (sendOverdue && (!overdueTasks.isEmpty() || !overdueChecklist.isEmpty())) {
                emails.add(buildOverdueEmail(owner, overdueTasks, overdueChecklist));
            }

            // ── BELL NOTIFICATION: Consolidated portal alert ──────────────
            Boolean hasDueToday = !dueTodayTasks.isEmpty() || !dueTodayChecklist.isEmpty();
            Boolean hasOverdue  = !overdueTasks.isEmpty()  || !overdueChecklist.isEmpty();
            Boolean shouldNotify = (sendDueToday && hasDueToday) || (sendOverdue && hasOverdue);
            if (notifTypeId != null && shouldNotify) {
                List<Task> notifDueToday    = sendDueToday ? dueTodayTasks   : new List<Task>();
                List<Task> notifOverdue     = sendOverdue  ? overdueTasks    : new List<Task>();
                List<Course_Checklist_Item__c> notifDueTodayCl = sendDueToday ? dueTodayChecklist : new List<Course_Checklist_Item__c>();
                List<Course_Checklist_Item__c> notifOverdueCl  = sendOverdue  ? overdueChecklist  : new List<Course_Checklist_Item__c>();
                sendBellNotification(notifTypeId, ownerId,
                    notifDueToday, notifOverdue, notifDueTodayCl, notifOverdueCl);
            }
        }

        // Single bulk email send for governor limit efficiency
        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails, false);
            System.debug('TaskReminderBatch: Sent ' + emails.size() + ' reminder email(s) to portal students.');
        }
    }

    // ─── Private Helpers ─────────────────────────────────────────────────────

    /**
     * @description Builds an individual "Due Today" reminder email for one student.
     *              Lists all their due-today tasks and pending checklist items.
     */
    private Messaging.SingleEmailMessage buildDueTodayEmail(
        User owner,
        List<Task> tasks,
        List<Course_Checklist_Item__c> checklistItems
    ) {
        Integer totalCount = tasks.size() + checklistItems.size();
        String subject = '⏰ Reminder: ' + totalCount + ' Item(s) Due Today – Action Required';

        String body =
            'Dear ' + owner.Name + ',\n\n' +
            'This is a friendly reminder that the following item(s) are due TODAY ' +
            '(' + Date.today().format() + '). ' +
            'Please complete them as soon as possible.\n\n';

        if (!tasks.isEmpty()) {
            body +=
                '─────────────────────────────────\n' +
                'YOUR TASKS DUE TODAY\n' +
                '─────────────────────────────────\n\n' +
                buildTaskList(tasks);
        }

        if (!checklistItems.isEmpty()) {
            body +=
                '─────────────────────────────────\n' +
                'YOUR PENDING CHECKLIST ITEMS\n' +
                '─────────────────────────────────\n\n' +
                buildChecklistItemList(checklistItems);
        }

        body += 'Please log in to the Student Portal to take action on these items.\n\n' +
                'Best Regards,\n' +
                'ISB Student Success Team';

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ owner.Email });
        email.setSubject(subject);
        email.setPlainTextBody(body);
        email.setSaveAsActivity(false);
        return email;
    }

    /**
     * @description Builds an individual "Overdue" urgent email for one student.
     *              Lists all their overdue tasks and overdue checklist items.
     */
    private Messaging.SingleEmailMessage buildOverdueEmail(
        User owner,
        List<Task> tasks,
        List<Course_Checklist_Item__c> checklistItems
    ) {
        Integer totalCount = tasks.size() + checklistItems.size();
        String subject = '🚨 Urgent: ' + totalCount + ' Overdue Item(s) – Immediate Action Required';

        String body =
            'Dear ' + owner.Name + ',\n\n' +
            '⚠️ URGENT: The following item(s) are OVERDUE. ' +
            'Please complete them immediately to avoid any impact on your academic progress.\n\n';

        if (!tasks.isEmpty()) {
            body +=
                '─────────────────────────────────\n' +
                'YOUR OVERDUE TASKS\n' +
                '─────────────────────────────────\n\n' +
                buildTaskList(tasks);
        }

        if (!checklistItems.isEmpty()) {
            body +=
                '─────────────────────────────────\n' +
                'YOUR OVERDUE CHECKLIST ITEMS\n' +
                '─────────────────────────────────\n\n' +
                buildChecklistItemList(checklistItems);
        }

        body += 'Log in to the Student Portal now to address these items. ' +
                'If you need assistance, please contact your Academic Associate.\n\n' +
                'Best Regards,\n' +
                'ISB Student Success Team';

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ owner.Email });
        email.setSubject(subject);
        email.setPlainTextBody(body);
        email.setSaveAsActivity(false);
        return email;
    }

    /**
     * @description Formats a list of tasks into a numbered plain-text block.
     *              Used inside both email builders.
     */
    private String buildTaskList(List<Task> tasks) {  
        String rows = '';
        Integer idx  = 1;
        for (Task t : tasks) {
            String dueLabel = (t.ActivityDate != null) ? t.ActivityDate.format() : 'N/A';
            String priority = String.isBlank(t.Priority) ? 'Normal' : t.Priority;
            rows += idx + '. ' + t.Subject + '\n' +
                    '   Due Date : ' + dueLabel + '\n' +
                    '   Priority : ' + priority  + '\n\n';
            idx++;
        }
        return rows;
    }

    /**
     * @description Formats a list of checklist items into a numbered plain-text block.
     */
    private String buildChecklistItemList(List<Course_Checklist_Item__c> items) {
        String rows = '';
        Integer idx  = 1;
        for (Course_Checklist_Item__c item : items) {
            String dueLabel = (item.Due_Date__c != null) ? item.Due_Date__c.format() : 'N/A';
            String priority = String.isBlank(item.Priority__c) ? 'Normal' : item.Priority__c;
            rows += idx + '. ' + (String.isBlank(item.Subject__c) ? '(No Subject)' : item.Subject__c) + '\n' +
                    '   Due Date : ' + dueLabel + '\n' +
                    '   Priority : ' + priority  + '\n' +
                    '   Status   : ' + item.Status__c + '\n\n';
            idx++;
        }
        return rows;
    }

    /**
     * @description Sends a single consolidated Bell Notification (portal alert)
     *              to the student, summarising Tasks and Checklist Item counts.
     *              Wrapped in try-catch so one failure never blocks other students.
     */
    private void sendBellNotification(
        Id       notifTypeId,
        Id       ownerId,
        List<Task> dueTodayTasks,
        List<Task> overdueTasks,
        List<Course_Checklist_Item__c> dueTodayChecklist,
        List<Course_Checklist_Item__c> overdueChecklist
    ) {
        try {
            List<String> summaryParts = new List<String>();

            Integer dueTodayTotal = dueTodayTasks.size() + dueTodayChecklist.size();
            Integer overdueTotal  = overdueTasks.size()  + overdueChecklist.size();

            if (dueTodayTotal > 0) {
                summaryParts.add(dueTodayTotal + ' item(s) due today');
            }
            if (overdueTotal > 0) {
                summaryParts.add(overdueTotal + ' overdue item(s)');
            }

            String notifTitle = 'Action Required: Your Tasks & Checklist';
            String notifBody  = 'You have ' + String.join(summaryParts, ' and ') +
                                '. Please review them in the Student Portal.';

            // Target the first relevant record for navigation on click
            Id targetId;
            if (!dueTodayTasks.isEmpty()) {
                targetId = dueTodayTasks[0].Id;
            } else if (!overdueTasks.isEmpty()) {
                targetId = overdueTasks[0].Id;
            } else if (!dueTodayChecklist.isEmpty()) {
                targetId = dueTodayChecklist[0].Course_Checklist__c;
            } else {
                targetId = overdueChecklist[0].Course_Checklist__c;
            }

            Messaging.CustomNotification notif = new Messaging.CustomNotification();
            notif.setNotificationTypeId(notifTypeId);
            notif.setTitle(notifTitle);
            notif.setBody(notifBody);
            notif.setTargetId(targetId);
            notif.send(new Set<String>{ ownerId });

        } catch (Exception e) {
            System.debug(
                'TaskReminderBatch - Bell Notification error for owner ' +
                ownerId + ': ' + e.getMessage()
            );
        }
    }

    /**
     * @description Fetches the Salesforce Id of the Custom Notification Type
     *              by its Developer Name. Returns null if not configured.
     */
    private Id getCustomNotificationTypeId() {
        List<CustomNotificationType> types = [
            SELECT Id
            FROM   CustomNotificationType
            WHERE  DeveloperName = :NOTIF_DEV_NAME
            LIMIT  1
        ];
        return types.isEmpty() ? null : types[0].Id;
    }
}