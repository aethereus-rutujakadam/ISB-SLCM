global class AttendanceReminderBatch
    implements Database.Batchable<Course_Attendance__c> {

    // --------------------------------------------------
    // START
    // --------------------------------------------------
    global Iterable<Course_Attendance__c> start(Database.BatchableContext bc) {

        Date twoDaysAgo = System.today().addDays(-2);

        List<Course_Attendance__c> records = [
            SELECT Id,
                   Contact__c,
                   Session_Attendance__c,
                   Learning_Course__c,
                   Session_Attendance__r.Date__c,
                   Reminder_Sent__c
            FROM Course_Attendance__c
            WHERE Status__c = 'Absent'
              AND Reminder_Sent__c = FALSE
              AND Session_Attendance__c IN (
                    SELECT Id
                    FROM Session_Attendance__c
                    WHERE Date__c <= :twoDaysAgo
              )
        ];

        System.debug('=== ATTENDANCE REMINDER BATCH START ===');
        System.debug('Processing absences 2 or more days old (cutoff date: ' + twoDaysAgo + ')');
        System.debug('Total absent records found: ' + records.size());
        System.debug('Attendance Record IDs: ' + records);

        return records;
    }

    // --------------------------------------------------
    // EXECUTE
    // --------------------------------------------------
    global void execute(
        Database.BatchableContext bc,
        List<Course_Attendance__c> scope
    ) {

        if (scope.isEmpty()) return;

        Set<Id> studentIds = new Set<Id>();
        Set<Id> sessionIds = new Set<Id>();
        Set<Id> courseIds  = new Set<Id>();
        Set<Date> absenceDates = new Set<Date>();

        Map<Id, String> attendanceIdToKey = new Map<Id, String>();

        for (Course_Attendance__c a : scope) {
            if (a.Contact__c == null || a.Session_Attendance__c == null) continue;

            Date sessionDate =
                a.Session_Attendance__c != null ? a.Session_Attendance__r.Date__c : null;
            if (sessionDate == null) continue;

            studentIds.add(a.Contact__c);
            sessionIds.add(a.Session_Attendance__c);
            absenceDates.add(sessionDate);

            if (a.Learning_Course__c != null) {
                courseIds.add(a.Learning_Course__c);
            }

            String key = buildKey(
                a.Contact__c,
                sessionDate,
                a.Session_Attendance__c,
                a.Learning_Course__c
            );

            attendanceIdToKey.put(a.Id, key);
        }

        System.debug('Student IDs being checked: ' + studentIds);
        System.debug('Session IDs being checked: ' + sessionIds);
        System.debug('Attendance records to process: ' + attendanceIdToKey.size());

        if (attendanceIdToKey.isEmpty()) return;

        // --------------------------------------------------
        // FETCH EXCEPTION CASES
        // --------------------------------------------------
        List<Case> exceptionCases = [
            SELECT Id,
                   ContactId,
                   Date_of_Absence__c,
                   Session__c,
                   Learning_Course__c
            FROM Case
            WHERE ContactId IN :studentIds
              AND Session__c IN :sessionIds
              AND Date_of_Absence__c IN :absenceDates
              AND RecordType.DeveloperName = 'Attendance_Exception'
              AND (Learning_Course__c = NULL
                   OR Learning_Course__c IN :courseIds)
        ];

        System.debug('Exception cases found: ' + exceptionCases.size());
        System.debug('Exception Case IDs: ' + exceptionCases);

        Set<String> exceptionKeys = new Set<String>();
        for (Case c : exceptionCases) {
            exceptionKeys.add(
                buildKey(
                    c.ContactId,
                    c.Date_of_Absence__c,
                    c.Session__c,
                    c.Learning_Course__c
                )
            );
        }

        System.debug('Exception keys (for matching): ' + exceptionKeys);

        // --------------------------------------------------
        // IDENTIFY ELIGIBLE STUDENTS
        // --------------------------------------------------
        Set<Id> eligibleStudents = new Set<Id>();

        for (Course_Attendance__c a : scope) {
            String key = attendanceIdToKey.get(a.Id);
            if (key == null) continue;
            if (exceptionKeys.contains(key)) continue;

            // Any unexcused absence qualifies for reminder
            eligibleStudents.add(a.Contact__c);
        }

        System.debug('Eligible students for reminder: ' + eligibleStudents.size());
        System.debug('Eligible Student IDs: ' + eligibleStudents);

        if (eligibleStudents.isEmpty()) return;

        // --------------------------------------------------
        // LOAD STUDENTS
        // --------------------------------------------------
        List<Contact> students = [
            SELECT Id, FirstName, Email
            FROM Contact
            WHERE Id IN :eligibleStudents
              AND Email != NULL
        ];

        System.debug('Students with valid emails: ' + students.size());
        for (Contact c : students) {
            System.debug('Will send email to: ' + c.Id + ' - ' + c.FirstName + ' (' + c.Email + ')');
        }

        // --------------------------------------------------
        // SEND EMAILS
        // --------------------------------------------------
        List<Messaging.SingleEmailMessage> emails =
            new List<Messaging.SingleEmailMessage>();

        for (Contact c : students) {
            Messaging.SingleEmailMessage mail =
                new Messaging.SingleEmailMessage();

            mail.setToAddresses(new String[] { c.Email });
            mail.setSubject('Attendance Reminder');
            mail.setPlainTextBody(
                'Hi ' +
                (c.FirstName == null ? 'there' : c.FirstName) +
                ', you have been absent for 1 or more sessions recently. ' +
                'If there is a valid reason, please raise an attendance exception case.'
            );

            emails.add(mail);
        }

        if (!emails.isEmpty()) {
            System.debug('Sending ' + emails.size() + ' reminder emails...');
            Messaging.sendEmail(emails);
            System.debug('Emails sent successfully!');
        }

        // --------------------------------------------------
        // MARK REMINDER SENT
        // --------------------------------------------------
        List<Course_Attendance__c> toUpdate =
            new List<Course_Attendance__c>();

        for (Course_Attendance__c a : scope) {
            if (!eligibleStudents.contains(a.Contact__c)) continue;

            String key = attendanceIdToKey.get(a.Id);
            if (key == null) continue;
            if (exceptionKeys.contains(key)) continue;

            toUpdate.add(new Course_Attendance__c(
                Id = a.Id,
                Reminder_Sent__c = true
            ));
        }

        if (!toUpdate.isEmpty()) {
            System.debug('Marking ' + toUpdate.size() + ' attendance records as Reminder_Sent = true');
            System.debug('Attendance IDs being updated: ' + toUpdate);
            update toUpdate;
            System.debug('Attendance records updated successfully!');
        }
    }

    // --------------------------------------------------
    // FINISH
    // --------------------------------------------------
    global void finish(Database.BatchableContext bc) {}

    // --------------------------------------------------
    // HELPER
    // --------------------------------------------------
    private static String buildKey(
        Id contactId,
        Date absenceDate,
        Id sessionId,
        Id courseId
    ) {
        return String.valueOf(contactId) + '|' +
               String.valueOf(absenceDate) + '|' +
               String.valueOf(sessionId) + '|' +
               String.valueOf(courseId);
    }
}