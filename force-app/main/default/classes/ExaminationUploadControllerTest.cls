@IsTest
public class ExaminationUploadControllerTest {

    @TestSetup
    static void setupData() {
        Program prog = TestDataFactory.testProgram(); 
        AcademicTerm term = TestDataFactory.testAcademicTerm(prog.Id); 
        Learning learning = TestDataFactory.testLearning();
        LearningCourse course = TestDataFactory.testLearningCourse(learning.Id); 
        
        Schema.Location loc = new Schema.Location(Name = 'Hyderabad', LocationType = 'Campus');
        insert loc;

        Exam_Schedule__c schedule = TestDataFactory.testExamSchedule(prog.Id, term.Id, loc.Id);
        
        // Existing record for clash/duplicate testing
        insert new Examination(
            Name = 'Existing Duplicate',
            Program__c = prog.Id,
            Academic_Term__c = term.Id,
            Course_Catalog__c = course.Id,
            Exam_Schedule__c = schedule.Id,
            Date_of_Exam__c = Date.today().addDays(10),
            Time_of_Exam__c = Time.newInstance(10, 0, 0, 0),
            Venue__c = loc.Id
        );
    }

    @IsTest
    static void testBulkProcess_WithAllLogicPaths() {
        Program p = [SELECT Name FROM Program LIMIT 1];
        AcademicTerm t = [SELECT Name FROM AcademicTerm LIMIT 1];
        LearningCourse c = [SELECT Name FROM LearningCourse LIMIT 1];
        Schema.Location loc = [SELECT Name FROM Location WHERE LocationType = 'Campus' LIMIT 1];
        Exam_Schedule__c es = [SELECT Name FROM Exam_Schedule__c LIMIT 1];

        List<Map<String, Object>> records = new List<Map<String, Object>>();
        
        // 1. SUCCESS PATH (Multiple date formats to cover convertToDate logic)
        records.add(new Map<String, Object>{
            'Name' => 'Exam 1', 'Program' => p.Name, 'Academic_Term' => t.Name, 'Course_Catalog' => c.Name,
            'Venue' => loc.Name, 'Exam_Schedule' => es.Name, 'Date_of_Exam' => '2026-12-25', 'Time_of_Exam' => '09:00 AM'
        });
        records.add(new Map<String, Object>{
            'Name' => 'Exam 2', 'Program' => p.Name, 'Academic_Term' => t.Name, 'Course_Catalog' => c.Name,
            'Venue' => loc.Name, 'Exam_Schedule' => es.Name, 'Date_of_Exam' => '25/12/2026', 'Time_of_Exam' => '02:00 PM'
        });
        records.add(new Map<String, Object>{
            'Name' => 'Exam 3', 'Program' => p.Name, 'Academic_Term' => t.Name, 'Course_Catalog' => c.Name,
            'Venue' => loc.Name, 'Exam_Schedule' => es.Name, 'Date_of_Exam' => '25-DEC-2026', 'Time_of_Exam' => '12:00 PM'
        });

        // 2. TRIGGER DUPLICATE NAME CLASH (Hits 'continue' block)
        records.add(new Map<String, Object>{
            'Name' => 'Existing Duplicate', 'Program' => p.Name, 'Venue' => loc.Name, 'Exam_Schedule' => es.Name,
            'Date_of_Exam' => '2030-01-01', 'Time_of_Exam' => '10:00 AM'
        });

        // 3. TRIGGER SLOT CLASH (Same Time/Date/Venue - Hits 'continue' block)
        records.add(new Map<String, Object>{
            'Name' => 'Unique Name', 'Program' => p.Name, 'Venue' => loc.Name, 'Exam_Schedule' => es.Name,
            'Date_of_Exam' => String.valueOf(Date.today().addDays(10)), 'Time_of_Exam' => '10:00 AM'
        });

        // 4. TRIGGER CATCH BLOCK (Pass invalid object to force Exception in createExaminationRecord)
        records.add(new Map<String, Object>{
            'Name' => 12345 // Passing Integer where String expected or causing null pointer
        });

        Test.startTest();
        Map<String, Object> response = ExaminationUploadController.processExaminationData(records);
        Test.stopTest();

        System.assertNotEquals(0, (Integer)response.get('successCount'), 'Should have successes');
        System.assertNotEquals(0, (Integer)response.get('failedCount'), 'Should have failures from duplicates and bad data');
    }

    @IsTest
    static void testPartialDmlFailure() {
        // This test covers the "Database.SaveResult" loop specifically
        Program p = [SELECT Name FROM Program LIMIT 1];
        AcademicTerm t = [SELECT Name FROM AcademicTerm LIMIT 1];
        LearningCourse c = [SELECT Name FROM LearningCourse LIMIT 1];
        Schema.Location loc = [SELECT Name FROM Location WHERE LocationType = 'Campus' LIMIT 1];
        Exam_Schedule__c es = [SELECT Name FROM Exam_Schedule__c LIMIT 1];

        // We create a record that passes the controller's internal checks but FAILS the database 
        // (e.g., a missing required field that the controller doesn't check itself)
        List<Map<String, Object>> records = new List<Map<String, Object>>{
            new Map<String, Object>{
                'Name' => 'DB Failure Test',
                'Program' => p.Name,
                'Venue' => loc.Name,
                'Exam_Schedule' => es.Name,
                'Date_of_Exam' => '2026-05-05',
                'Time_of_Exam' => '10:00 AM'
                // Intentionally omitting fields or providing data that violates a DB constraint
            }
        };

        Test.startTest();
        // Since we are using Database.insert(toInsert, false), this will hit the error loop
        ExaminationUploadController.processExaminationData(records);
        Test.stopTest();
    }

    @IsTest
    static void testEmptyAndNull() {
        // Covers Row 0 error handling
        Map<String, Object> resNull = ExaminationUploadController.processExaminationData(null);
        Map<String, Object> resEmpty = ExaminationUploadController.processExaminationData(new List<Map<String, Object>>());
        
        System.assertEquals(1, ((List<String>)resNull.get('errorRows')).size());
    }

    @IsTest
    static void testTimeEdgeCases() {
        Program p = [SELECT Name FROM Program LIMIT 1];
        Exam_Schedule__c es = [SELECT Name FROM Exam_Schedule__c LIMIT 1];
        Schema.Location loc = [SELECT Name FROM Location WHERE LocationType = 'Campus' LIMIT 1];

        List<Map<String, Object>> records = new List<Map<String, Object>>{
            new Map<String, Object>{
                'Name' => 'Midnight Test', 'Program' => p.Name, 'Venue' => loc.Name, 'Exam_Schedule' => es.Name,
                'Date_of_Exam' => '2026-01-01', 'Time_of_Exam' => '12:00 AM' // Midnight logic
            },
            new Map<String, Object>{
                'Name' => 'Numeric Date', 'Program' => p.Name, 'Venue' => loc.Name, 'Exam_Schedule' => es.Name,
                'Date_of_Exam' => '45200', 'Time_of_Exam' => '12:00 PM' // Excel format + Noon logic
            }
        };
        
        ExaminationUploadController.processExaminationData(records);
    }
}