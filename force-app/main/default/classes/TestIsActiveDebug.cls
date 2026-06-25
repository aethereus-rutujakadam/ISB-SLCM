@IsTest
public class TestIsActiveDebug {
    @IsTest
    static void checkIsActiveValue() {
        // Create test contact
        Contact con = new Contact(
            FirstName = 'Test',
            LastName = 'Student'
        );
        insert con;

        // Create test program
        Program prog = new Program(Name = 'Test Program');
        insert prog;

        // Create AcademicYear
        AcademicYear ay = new AcademicYear(Name = 'Test AY');
        insert ay;

        // Create ProgramEnrollment with Status='Registered'
        ProgramEnrollment pe = new ProgramEnrollment(
            Name = 'Test PE',
            ContactId = con.Id,
            ProgramId = prog.Id,
            PGID__c = 'TEST-PGID',
            Status = 'Registered',
            Academic_Year__c = ay.Id
        );
        insert pe;

        // Query it back to see IsActive
        ProgramEnrollment queried = [
            SELECT Id, Name, PGID__c, Status, IsActive, Academic_Year__c
            FROM ProgramEnrollment
            WHERE Id = :pe.Id
        ];

        System.debug('IsActive: ' + queried.IsActive);
        System.debug('Status: ' + queried.Status);
        System.debug('Academic_Year__c: ' + queried.Academic_Year__c);
        
        // This test is just for debugging
        System.assert(true, 'Check debug logs for IsActive value');
    }
}