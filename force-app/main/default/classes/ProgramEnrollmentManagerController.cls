public without sharing class ProgramEnrollmentManagerController {
    
    /**
     * @description Fetch Programs with optional search
     */
    @AuraEnabled(cacheable=true)
    public static List<Program> getPrograms(String searchKey) {
        try {
            String query = 'SELECT Id, Name, Program_Code__c, Program_Type__c FROM Program';
            if (String.isNotBlank(searchKey)) {
                String searchPattern = '%' + searchKey + '%';
                query += ' WHERE Name LIKE :searchPattern OR Program_Code__c LIKE :searchPattern';
            }
            query += ' ORDER BY Name ASC LIMIT 100';
            return Database.query(query);
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching programs: ' + e.getMessage());
        }
    }

    /**
     * @description Fetch Academic Years for filtering
     */
    @AuraEnabled(cacheable=true)
    public static List<AcademicYear> getAcademicYears() {
        try {
            return [SELECT Id, Name FROM AcademicYear ORDER BY Name DESC LIMIT 20];
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching academic years: ' + e.getMessage());
        }
    }

    /**
     * @description Fetch Program Enrollments for a specific Program and optional Academic Year
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getProgramEnrollments(Id programId, Id academicYearId) {
        try {
            // 1. Query Program Enrollments (Status = Registered)
            String query = 'SELECT Id, Name, Status, CGPA__c, ContactId, Contact.Name, Contact.Email, Contact.New_Admit_Email__c, ' +
                           'PGID__c, Sub_Status__c, Sub_Sub_Status__c, Pre_Term__c, Location__r.Name, ' +
                           'Academic_Year__c, Academic_Year__r.Name, ' +
                           '(SELECT Id, Installment_Number__c, Installment_Status__c, Due_Date__c, Extended_Due_Date__c FROM ISB_Installments__r ORDER BY Installment_Number__c ASC NULLS LAST, Due_Date__c ASC) ' +
                           'FROM ProgramEnrollment ' +
                           'WHERE ProgramId = :programId ';
            
            if (academicYearId != null) {
                query += ' AND Academic_Year__c = :academicYearId';
            }
            
            query += ' ORDER BY Contact.Name ASC LIMIT 1000';
            List<ProgramEnrollment> allEnrollments = Database.query(query);
            
            // 2. Build Result
            List<Map<String, Object>> result = new List<Map<String, Object>>();
            
            for (ProgramEnrollment pe : allEnrollments) {
                List<Map<String, Object>> installments = new List<Map<String, Object>>();
                for(ISB_Installment__c inst : pe.ISB_Installments__r) {
                    installments.add(new Map<String, Object>{
                        'Number' => inst.Installment_Number__c,
                        'Status' => inst.Installment_Status__c,
                        'DueDate' => inst.Due_Date__c,
                        'ExtendedDueDate' => inst.Extended_Due_Date__c
                    });
                }

                result.add(new Map<String, Object>{
                    'Id' => pe.Id,
                    'Name' => pe.Name,
                    'PGID' => pe.PGID__c,
                    'StudentName' => pe.Contact.Name,
                    'Email' => pe.Contact.New_Admit_Email__c,
                    'Status' => pe.Status,
                    'SubStatus' => pe.Sub_Status__c,
                    'SubSubStatus' => pe.Sub_Sub_Status__c,
                    'Location' => pe.Location__r != null ? pe.Location__r.Name : null,
                    'AcademicYear' => pe.getSObject('Academic_Year__r') != null ? (String)pe.getSObject('Academic_Year__r').get('Name') : null,
                    'CGPA' => pe.CGPA__c,
                    'Installments' => installments
                });
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching enrollments: ' + e.getMessage());
        }
    }

    /**
     * @description Fetch Enrollment Sessions
     */
    @AuraEnabled(cacheable=true)
    public static List<Enrollment_Session__c> getEnrollmentSessions(Id enrollmentId) {
        try {
            return [
                SELECT Id, Name, Academic_Session__r.Name, Status__c,
                       Attended_Sessions__c, Attendance__c, GPA__c
                FROM Enrollment_Session__c
                WHERE Program_Enrollment__c = :enrollmentId
                ORDER BY Academic_Session__r.Name ASC
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching sessions: ' + e.getMessage());
        }
    }

    /**
     * @description Fetch Installments
     */
    @AuraEnabled(cacheable=true)
    public static List<ISB_Installment__c> getEnrollmentInstallments(Id enrollmentId) {
        try {
            return [
                SELECT Id, Name, Installment_Number__c, Installment_Status__c,
                       Due_Date__c, Total_Amount_calc__c, Paid_Amount__c, Pending_Amount__c
                FROM ISB_Installment__c
                WHERE Program_Enrollment__c = :enrollmentId
                ORDER BY Installment_Number__c ASC NULLS LAST, Due_Date__c ASC
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching installments: ' + e.getMessage());
        }
    }
}