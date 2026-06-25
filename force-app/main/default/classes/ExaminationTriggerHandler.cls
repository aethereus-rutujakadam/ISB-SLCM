public class ExaminationTriggerHandler {

    // ----------------------------------------------
    // Prevent delete if Published
    // ----------------------------------------------
    public static void preventDeleteIfPublished(List<Examination> oldRecords) {
        for (Examination e : oldRecords) {
            if (e.Status == 'Published') {
                e.addError('You cannot delete this Examination because it is in Published state.');
            }
        }
    }


    // ----------------------------------------------
    // MAIN METHOD: Prevent Duplicate Name + Schedule
    // ----------------------------------------------
    public static void preventDuplicateAcrossSchedules(List<Examination> newRecords) {

        // ---------------------------------------------------
        // 1) SIMPLE MANUAL CREATE DUPLICATE NAME VALIDATION
        // ---------------------------------------------------
        for (Examination e : newRecords) {
            if (e.Id == null && !String.isBlank(e.Name)) {

                Integer existingCount = [
                    SELECT COUNT() 
                    FROM Examination 
                    WHERE Name = :e.Name
                ];

                if (existingCount > 0) {
                    e.addError('An Examination with this Name already exists.');
                }
            }
        }
        // ---------------------------------------------------
        // END OF MANUAL CREATE VALIDATION
        // ---------------------------------------------------



        // ---------------------------------------------------
        // 2) EXISTING LOGIC — DO NOT TOUCH
        // ---------------------------------------------------

        // Collect values
        Set<String> examNames = new Set<String>();
        for (Examination e : newRecords) {
            if (e.Name != null)
                examNames.add(e.Name.trim().toLowerCase());
        }

        if (examNames.isEmpty()) return;

        // Query existing exams in org
        Map<String, List<Examination>> existingExamMap = new Map<String, List<Examination>>();
        for (Examination e : [
            SELECT Id, Name, Exam_Schedule__c
            FROM Examination
            WHERE Name IN :examNames
        ]) {
            String key = e.Name.trim().toLowerCase();
            if (!existingExamMap.containsKey(key)) {
                existingExamMap.put(key, new List<Examination>());
            }
            existingExamMap.get(key).add(e);
        }

        // Validate against existing
        for (Examination newExam : newRecords) {

            if (newExam.Name == null || newExam.Exam_Schedule__c == null) continue;

            String key = newExam.Name.trim().toLowerCase();

            if (existingExamMap.containsKey(key)) {

                for (Examination ex : existingExamMap.get(key)) {

                    if (ex.Exam_Schedule__c != newExam.Exam_Schedule__c) {

                        newExam.addError(
                            'Duplicate Exam Conflict: Exam "' + newExam.Name +
                            '" is already associated with another Exam Schedule.'
                        );
                    }
                }
            }
        }
    }
}