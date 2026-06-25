public with sharing class IncomingExchangeStudentService {

    // --- Wrapper Classes ---
    public class IncomingExchangeStudentResponse {
        public String status;
        public Integer totalStudents;
        public List<StudentInfo> students;

        public IncomingExchangeStudentResponse() {
            this.status = 'SUCCESS';
            this.totalStudents = 0;
            this.students = new List<StudentInfo>();
        }
    }

    public class StudentInfo {
        public String pgid;
        public String studentName;
        public String email;
        public String cohort;
        public String campus;
        public String exchangeType;
        public String accommodationType;
        public String educationCategory;
        public String gender;
        public String dob;
        public String mobile;
        public String nationality;
        public String scholarship;
        public String diversity;
        public Decimal bidPointsAllotted;
        public List<TermInfo> terms;

        public StudentInfo() {
            this.terms = new List<TermInfo>();
        }
    }

    public class TermInfo {
        public String campus;
        public String termLabel;
    }

    // --- Service Methods ---
    public static IncomingExchangeStudentResponse getStudents(Map<String, String> filters) {
        IncomingExchangeStudentResponse response = new IncomingExchangeStudentResponse();
        
        // 1. Build Query for ProgramEnrollment
        String query = 'SELECT Id, PGID__c, Academic_Term__r.Name, Location__r.Name, Bid_Points_Alloted__c, Accomodation_Type__c,' +
                       'ContactId, Contact.Name, Contact.New_Admit_Email__c, Contact.Education_Category__c, ' +
                       'Contact.Gender__c, Contact.Nationality__c, Contact.Birthdate, Contact.Phone, Contact.Scholarship__c, ' +
                       'Contact.Diversity__c, Contact.Exchange_Type__c ' +
                       'FROM ProgramEnrollment ' +
                       'WHERE Contact.Exchange_Type__c = \'Incoming\' '; 

        // 2. Add Filters
        if (filters != null) {
            if (String.isNotBlank(filters.get('pgid'))) {
                String pgid = String.escapeSingleQuotes(filters.get('pgid'));
                query += ' AND PGID__c = \'' + pgid + '\' ';
            }
            if (String.isNotBlank(filters.get('exchangeType'))) {
                String exType = String.escapeSingleQuotes(filters.get('exchangeType'));
                query += ' AND Contact.Exchange_Type__c = \'' + exType + '\' ';
            }
            if (String.isNotBlank(filters.get('cohort'))) {
                String cohort = String.escapeSingleQuotes(filters.get('cohort'));
                query += ' AND Academic_Term__r.Name = \'' + cohort + '\' ';
            }
            if (String.isNotBlank(filters.get('campus'))) {
                String campus = String.escapeSingleQuotes(filters.get('campus'));
                query += ' AND Location__r.Name = \'' + campus + '\' ';
            }
            if (String.isNotBlank(filters.get('academicYear'))) {
                String academicYear = String.escapeSingleQuotes(filters.get('academicYear'));
                query += ' AND Academic_Year__r.Name = \'' + academicYear + '\' ';
            }
            if (String.isNotBlank(filters.get('lastModifiedDate'))) {
                // expecting format like 2023-10-01T00:00:00Z
                String lmd = String.escapeSingleQuotes(filters.get('lastModifiedDate'));
                query += ' AND LastModifiedDate >= ' + lmd + ' ';
            }
        }

        query += ' ORDER BY PGID__c ASC LIMIT 40000';

        List<ProgramEnrollment> peList = Database.query(query);

        if (peList.isEmpty()) {
            response.totalStudents = 0;
            return response;
        }

        Map<Id, ProgramEnrollment> peMap = new Map<Id, ProgramEnrollment>();
        Map<String, StudentInfo> pgidToStudentMap = new Map<String, StudentInfo>();

        // Populate base student details
        for (ProgramEnrollment pe : peList) {
            if (String.isBlank(pe.PGID__c)) continue;
            
            peMap.put(pe.Id, pe);

            if (!pgidToStudentMap.containsKey(pe.PGID__c)) {
                StudentInfo student = new StudentInfo();
                student.pgid = pe.PGID__c;
                student.studentName = pe.Contact?.Name;
                student.email = pe.Contact?.New_Admit_Email__c;
                student.cohort = pe.Academic_Term__r?.Name;
                student.campus = pe.Location__r?.Name;
                student.exchangeType = String.valueOf(pe.Contact?.Exchange_Type__c);
                student.accommodationType = String.valueOf(pe.Accomodation_Type__c);
                student.educationCategory = String.valueOf(pe.Contact?.Education_Category__c);
                student.gender = String.valueOf(pe.Contact?.Gender__c);
                
                if (pe.Contact?.Birthdate != null) {
                    DateTime dt = DateTime.newInstance(pe.Contact.Birthdate.year(), pe.Contact.Birthdate.month(), pe.Contact.Birthdate.day());
                    student.dob = dt.format('yyyy-MM-dd');
                }
                
                student.mobile = String.valueOf(pe.Contact?.Phone);
                student.nationality = String.valueOf(pe.Contact?.Nationality__c);
                student.scholarship = String.valueOf(pe.Contact?.Scholarship__c);
                student.diversity = String.valueOf(pe.Contact?.Diversity__c);
                student.bidPointsAllotted = pe.Bid_Points_Alloted__c;
                
                pgidToStudentMap.put(pe.PGID__c, student);
            }
        }

        // 3. Query Enrollment Sessions (Academic Terms)
        if (!peMap.isEmpty()) {
            List<Enrollment_Session__c> sessionList = [
                SELECT Id, Program_Enrollment__c, Academic_Session__r.Name, Academic_Session__r.Location__r.Name 
                FROM Enrollment_Session__c 
                WHERE Program_Enrollment__c IN :peMap.keySet()
            ];

            // 4. Map Terms to Students
            for (Enrollment_Session__c session : sessionList) {
                ProgramEnrollment parentPe = peMap.get(session.Program_Enrollment__c);
                if (parentPe != null && String.isNotBlank(parentPe.PGID__c)) {
                    StudentInfo student = pgidToStudentMap.get(parentPe.PGID__c);
                    if (student != null) {
                        TermInfo term = new TermInfo();
                        term.termLabel = session.Academic_Session__r?.Name;
                        term.campus = session.Academic_Session__r?.Location__r?.Name;
                        student.terms.add(term);
                    }
                }
            }
        }

        response.students.addAll(pgidToStudentMap.values());
        response.totalStudents = response.students.size();

        return response;
    }
}