public without sharing class ExaminationUploadController {

    @AuraEnabled
    public static Map<String, Object> processExaminationData(List<Map<String, Object>> records) {

        Map<String, Object> response = new Map<String, Object>{
            'successCount' => 0,
            'failedCount'  => 0,
            'errorRows'    => new List<String>(),
            'errorCSV'     => ''
        };

        List<String> errorRows = (List<String>)response.get('errorRows');

        if (records == null || records.isEmpty()) {
            errorRows.add('Row 0: No examination records received');
            response.put('errorCSV', 'Row,Message\n"0","No records received"');
            return response;
        }

        Set<String> programNames = new Set<String>();
        Set<String> venueNames = new Set<String>();
        Set<String> termNames = new Set<String>();
        Set<String> courseNames = new Set<String>();
        Set<String> examScheduleNames = new Set<String>();

        Set<String> examVenueNames = new Set<String>(); // >>> ADDED

        for (Map<String, Object> row : records) {
            if (row.get('Program') != null) programNames.add(String.valueOf(row.get('Program')).trim());
            if (row.get('Venue') != null) venueNames.add(String.valueOf(row.get('Venue')).trim());
            if (row.get('Academic_Term') != null) termNames.add(String.valueOf(row.get('Academic_Term')).trim());
            if (row.get('Term') != null) termNames.add(String.valueOf(row.get('Term')).trim());
            if (row.get('Course_Catalog') != null) courseNames.add(String.valueOf(row.get('Course_Catalog')).trim());
            if (row.get('Exam_Schedule') != null) examScheduleNames.add(String.valueOf(row.get('Exam_Schedule')).trim());
            if (row.get('Exam Schedule') != null) examScheduleNames.add(String.valueOf(row.get('Exam Schedule')).trim());

           // if (row.get('Exam_Venue') != null) examVenueNames.add(String.valueOf(row.get('Exam_Venue')).trim()); // >>> ADDED
        }

        Map<String, Id> programMap = new Map<String, Id>();
        if (!programNames.isEmpty()) {
            for (Program p : [SELECT Id, Name FROM Program WHERE Name IN :programNames]) {
                programMap.put(p.Name.toLowerCase(), p.Id);
            }
        }

        Map<String, Id> venueMap = new Map<String, Id>();
        if (!venueNames.isEmpty()) {
            for (Schema.Location loc : [
                SELECT Id, Name FROM Location WHERE Name IN :venueNames AND LocationType = 'Campus'
            ]) {
                venueMap.put(loc.Name.toLowerCase(), loc.Id);
            }
        }

        Map<String, Id> termMap = new Map<String, Id>();
        if (!termNames.isEmpty()) {
            for (AcademicTerm t : [SELECT Id, Name FROM AcademicTerm WHERE Name IN :termNames]) {
                termMap.put(t.Name.toLowerCase(), t.Id);
            }
        }

        Map<String, Id> courseMap = new Map<String, Id>();
        if (!courseNames.isEmpty()) {
            for (LearningCourse lc : [SELECT Id, Name FROM LearningCourse WHERE Name IN :courseNames]) {
                courseMap.put(lc.Name.toLowerCase(), lc.Id);
            }
        }

        Map<String, Id> examScheduleMap = new Map<String, Id>();
        if (!examScheduleNames.isEmpty()) {
            for (Exam_Schedule__c e : [SELECT Id, Name FROM Exam_Schedule__c WHERE Name IN :examScheduleNames]) {
                examScheduleMap.put(e.Name.toLowerCase(), e.Id);
            }
        }

        // >>> ADDED BLOCK START - Load Exam Venue object custom lookup
        Map<String, Id> examVenueMap = new Map<String, Id>();
      /*  if (!examVenueNames.isEmpty()) {
            for (Exam_Venue__c ev : [SELECT Id, Name FROM Exam_Venue__c WHERE Name IN :examVenueNames]) {
                examVenueMap.put(ev.Name.toLowerCase(), ev.Id);
                system.debug('examVenueMapInside-->'+ examVenueMap);
            }
            system.debug('examVenueMapInside-->'+ examVenueMap);
        }*/
        // >>> ADDED BLOCK END

        List<Examination> examList = [
            SELECT Id, Name, Program__c, Course_Catalog__c, Exam_Schedule__c,
                   Date_of_Exam__c, Time_of_Exam__c, Venue__c
            FROM Examination
            WHERE Exam_Schedule__c IN :examScheduleMap.values()
        ];

        Set<String> existingNameScheduleKeys = new Set<String>();
        Set<String> existingSlotClashKeys = new Set<String>();

        for (Examination e : examList) {
            existingNameScheduleKeys.add(e.Name.toLowerCase() + '|' + e.Exam_Schedule__c);
            String t = formatTime(e.Time_of_Exam__c);
            existingSlotClashKeys.add(e.Date_of_Exam__c + '|' + t + '|' + e.Venue__c + '|' + e.Exam_Schedule__c);
        }

        Set<String> newNameScheduleKeys = new Set<String>();
        Set<String> newSlotClashKeys = new Set<String>();
        List<Examination> toInsert = new List<Examination>();

        Integer successCount = 0;
        Integer failedCount = 0;
        List<String> csvLines = new List<String>();

        for (Integer i = 0; i < records.size(); i++) {
            try {
                Examination exam = createExaminationRecord(records[i], programMap, venueMap, termMap, courseMap, examScheduleMap, examVenueMap);

                String nameScheduleKey = exam.Name.toLowerCase() + '|' + exam.Exam_Schedule__c;
                if (existingNameScheduleKeys.contains(nameScheduleKey) || newNameScheduleKeys.contains(nameScheduleKey)) {
                    String msg = 'Row ' + (i + 2) + ': Exam Name "' + exam.Name + '" already exists for this Exam Schedule';
                    csvLines.add(msg);
                    errorRows.add(msg);
                    failedCount++;
                    continue;
                }

                String timeStr = formatTime(exam.Time_of_Exam__c);
                String slotKey = exam.Date_of_Exam__c + '|' + timeStr + '|' + exam.Venue__c + '|' + exam.Exam_Schedule__c;
                if (existingSlotClashKeys.contains(slotKey) || newSlotClashKeys.contains(slotKey)) {
                    String msg = 'Row ' + (i + 2) + ': Date/Time/Venue/Schedule already exists';
                    csvLines.add(msg);
                    errorRows.add(msg);
                    failedCount++;
                    continue;
                }

                newNameScheduleKeys.add(nameScheduleKey);
                newSlotClashKeys.add(slotKey);
                toInsert.add(exam);

            } catch (Exception ex) {
                String msg = 'Row ' + (i + 2) + ': ' + ex.getMessage();
                csvLines.add(msg);
                errorRows.add(msg);
                system.debug('examVenueMapoutside-->'+ examVenueMap + 'venueMap-->'+venueMap);
                system.debug('error-->'+ ex.getMessage());
                System.debug('***DEBUG LOG: Exception Type: ' + ex.getTypeName() + '***'); // Gets the specific type, e.g., DmlException
    System.debug('***DEBUG LOG: Error Message: ' + ex.getMessage() + '***'); // The error message
    System.debug('***DEBUG LOG: Line Number: ' + ex.getLineNumber() + '***'); // The line where the exception occurred
    System.debug('***DEBUG LOG: Stack Trace: ' + ex.getStackTraceString() + '***'); // Full stack trace for context
                failedCount++;
            }
        }

        if (!toInsert.isEmpty()) {
            Database.SaveResult[] results = Database.insert(toInsert, false);
for (Integer idx = 0; idx < results.size(); idx++) {
    Database.SaveResult r = results[idx];

    if (r.isSuccess()) {
        successCount++;
    } else {
        failedCount++;
        for (Database.Error e : r.getErrors()) {
            String msg = 'Row ' + (idx + 2) + ': ' + e.getMessage();
            csvLines.add(msg);
            errorRows.add(msg);
        }
    }
}

        }

        String csv = 'Row,Message\n';
        for (String line : csvLines) {
            csv += '"' + line.replace('"','""') + '"\n';
        }

        response.put('successCount', successCount);
        response.put('failedCount', failedCount);
        response.put('errorCSV', csv);

        return response;
    }

    private static Examination createExaminationRecord(
        Map<String, Object> row,
        Map<String, Id> programMap,
        Map<String, Id> venueMap,
        Map<String, Id> termMap,
        Map<String, Id> courseMap,
        Map<String, Id> examScheduleMap ,
        Map<String, Id> examVenueMap // >>> ADDED
    ) {
        Examination exam = new Examination();

        exam.Name = String.valueOf(row.get('Name')).trim();
        exam.Date_of_Exam__c = convertToDate(row.get('Date_of_Exam'));
        exam.Time_of_Exam__c = convertToTime(row.get('Time_of_Exam'));

        // >>> ADDED populate duration
        if (row.containsKey('Duration_mins')) {
            exam.Duration_mins__c = Integer.valueOf(row.get('Duration_mins'));
        }

        // >>> ADDED populate Term
        if (row.containsKey('Academic_Term')) {
            exam.Academic_Term__c = termMap.get(String.valueOf(row.get('Academic_Term')).trim().toLowerCase());
        }

        // >>> ADDED populate End Time
        if (row.containsKey('End_Time')) {
            exam.End_Time__c = convertToTime(row.get('End_Time'));
        }

        exam.Program__c = programMap.get(String.valueOf(row.get('Program')).trim().toLowerCase());
        
        // >>> ADDED Exam Venue custom lookup
        //exam.Exam_Venue__c = examVenueMap.get(String.valueOf(row.get('Exam_Venue')).trim().toLowerCase());
        //Adding null chevck
     /*   if (row.containsKey('Exam_Venue') && row.get('Exam_Venue') != null) {
    String ev = String.valueOf(row.get('Exam_Venue')).trim().toLowerCase();
    if (examVenueMap.containsKey(ev)) {
        exam.Exam_Venue__c = examVenueMap.get(ev);
    } else {
        throw new AuraHandledException('Invalid Exam Venue: ' + row.get('Exam_Venue'));
    }
}*/

		//system.debug('Venue value-->'+ exam.Exam_Venue__c);
        exam.Venue__c = venueMap.get(String.valueOf(row.get('Venue')).trim().toLowerCase());
        exam.Course_Catalog__c = courseMap.get(String.valueOf(row.get('Course_Catalog')).trim().toLowerCase());

        String scheduleKey = row.containsKey('Exam_Schedule')
            ? String.valueOf(row.get('Exam_Schedule')).trim().toLowerCase()
            : String.valueOf(row.get('Exam Schedule')).trim().toLowerCase();
        exam.Exam_Schedule__c = examScheduleMap.get(scheduleKey);

        return exam;
    }

    private static String formatTime(Time t) {
        return (t == null) ? '' : Datetime.newInstance(Date.today(), t).format('HH:mm');
    }

    private static Date convertToDate(Object val) {
    if (val == null) return null;
    try {
        String s = String.valueOf(val).trim();

        // Excel numeric date
        if (s.isNumeric()) {
            return Date.newInstance(1900, 1, 1).addDays(Integer.valueOf(s) - 2);
        }

        // dd/mm/yyyy
        if (s.contains('/')) {
            List<String> p = s.split('/');
            return Date.newInstance(Integer.valueOf(p[2]), Integer.valueOf(p[1]), Integer.valueOf(p[0]));
        }

        // yyyy-mm-dd  ---> Correct fix
        // yyyy-mm-dd or dd-mmm-yyyy support
if (s.contains('-')) {
    List<String> p = s.split('-');

    // Case: 2025-12-27 (ISO style)
    if (p[0].length() == 4) {
        return Date.newInstance(Integer.valueOf(p[0]), Integer.valueOf(p[1]), Integer.valueOf(p[2]));
    }

    // Case: 27-Dec-2025
    Map<String,Integer> months = new Map<String,Integer>{
        'JAN'=>1,'FEB'=>2,'MAR'=>3,'APR'=>4,'MAY'=>5,'JUN'=>6,
        'JUL'=>7,'AUG'=>8,'SEP'=>9,'OCT'=>10,'NOV'=>11,'DEC'=>12
    };
    return Date.newInstance(
        Integer.valueOf(p[2]),
        months.get(p[1].substring(0,3).toUpperCase()),
        Integer.valueOf(p[0])
    );
}


        // ISO or other formats
        return Date.valueOf(s);

    } catch (Exception e) {
        return null;
    }
}


    private static Time convertToTime(Object val) {
        if (val == null) return null;
        try {
            String s = String.valueOf(val).trim().toUpperCase();
            Boolean pm = s.contains('PM');
            Boolean am = s.contains('AM');

            s = s.replace('AM','').replace('PM','').trim();
            List<String> parts = s.split(':');

            Integer hour = Integer.valueOf(parts[0]);
            Integer minute = parts.size() > 1 ? Integer.valueOf(parts[1]) : 0;

            if (pm && hour < 12) hour += 12;
            if (am && hour == 12) hour = 0;

            return Time.newInstance(hour, minute, 0, 0);
        } catch (Exception e) {
            return null;
        }
    }
}