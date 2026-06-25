@isTest
private class ISB_OrgACalloutQueueableTest {

    /*
    MOCK CLASS - SUCCESS RESPONSE
    */
    private class SuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type','application/json');
            res.setBody('{"status":"success"}');
            res.setStatusCode(200);
            return res;
        }
    }

    /*
    MOCK CLASS - FAILURE RESPONSE
    */
    private class FailureMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type','application/json');
            res.setBody('{"error":"failed"}');
            res.setStatusCode(500);
            return res;
        }
    }

    /*
    SUCCESS TEST
    */
    @isTest
    static void testQueueableSuccess() {

        Contact con = TestDataFactory.testContact();
        Program prog = TestDataFactory.testProgram();
        ProgramEnrollment pe = TestDataFactory.testProgramEnrollment(con, prog, 'PG001');

        pe.ISB_External_Id__c = 'APP-123';
        update pe;

        ISB_Payment__c payment = new ISB_Payment__c(
            Customer__c = con.Id,
            Program_Enrollment__c = pe.Id,
            Amount__c = 1000
        );
        insert payment;

        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();

        System.enqueueJob(
            new ISB_OrgACalloutQueueable(
                pe.ISB_External_Id__c,
                payment.Id,
                null,
                true,
                null,
                null,
                null,
                'SUCCESS',
                null
            )
        );

        Test.stopTest();

        ISB_Payment__c updatedPayment =
            [SELECT Initiated__c FROM ISB_Payment__c WHERE Id = :payment.Id];

        System.assertEquals('Success', updatedPayment.Initiated__c);
    }


    /*
    FAILURE TEST
    */
    @isTest
    static void testQueueableFailure() {

        Contact con = TestDataFactory.testContact();
        Program prog = TestDataFactory.testProgram();
        ProgramEnrollment pe = TestDataFactory.testProgramEnrollment(con, prog, 'PG002');

        pe.ISB_External_Id__c = 'APP-456';
        update pe;

        ISB_Payment__c payment = new ISB_Payment__c(
            Customer__c = con.Id,
            Program_Enrollment__c = pe.Id,
            Amount__c = 2000
        );
        insert payment;

        Test.setMock(HttpCalloutMock.class, new FailureMock());

        Test.startTest();

        System.enqueueJob(
            new ISB_OrgACalloutQueueable(
                pe.ISB_External_Id__c,
                payment.Id,
                null,
                true,
                null,
                null,
                null,
                'FAILED',
                null
            )
        );

        Test.stopTest();

        ISB_Payment__c updatedPayment =
            [SELECT Initiated__c FROM ISB_Payment__c WHERE Id = :payment.Id];

        System.assertEquals('Failed', updatedPayment.Initiated__c);
    }
}