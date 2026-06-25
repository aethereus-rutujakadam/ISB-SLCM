@isTest
private class InboundThreadHandlerTest {

    private static Messaging.InboundEnvelope buildEnvelope() {
        Messaging.InboundEnvelope env = new Messaging.InboundEnvelope();
        env.toAddress = 'faculty-comms@reply.university.edu';
        return env;
    }

    private static Messaging.InboundEmail buildEmail(String subjectValue) {
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        email.subject = subjectValue;
        email.fromAddress = 'faculty@university.edu';
        email.fromName = 'Faculty User';
        email.plainTextBody = 'Test plain body';
        email.htmlBody = '<p>Test html body</p>';
        return email;
    }

    @isTest
    static void testMatchedTokenUpdatesExistingThread() {
        Communication_Thread__c existing = new Communication_Thread__c(
            Subject__c = 'Initial',
            Status__c = 'Open'
        );
        insert existing;

        existing = [SELECT Id, Name FROM Communication_Thread__c WHERE Id = :existing.Id];

        Messaging.InboundEmail email = buildEmail('Re: Faculty Reply [' + existing.Name + ']');

        Test.startTest();
        Messaging.InboundEmailResult result = new InboundThreadHandler().handleInboundEmail(email, buildEnvelope());
        Test.stopTest();

        System.assertEquals(true, result.success);

        Communication_Thread__c updated = [
            SELECT Id, Status__c, Last_Reply_Date__c
            FROM Communication_Thread__c
            WHERE Id = :existing.Id
        ];
        System.assertEquals('Pending Review', updated.Status__c);
        System.assertNotEquals(null, updated.Last_Reply_Date__c);

        List<EmailMessage> msgs = [
            SELECT Id, RelatedToId, Communication_Thread__c, Incoming
            FROM EmailMessage
            WHERE RelatedToId = :existing.Id
        ];
        System.assertEquals(1, msgs.size());
        System.assertEquals(existing.Id, msgs[0].Communication_Thread__c);
        System.assertEquals(true, msgs[0].Incoming);
    }

    @isTest
    static void testUnmatchedWhenNoThreadToken() {
        Messaging.InboundEmail email = buildEmail('General faculty question');

        Test.startTest();
        Messaging.InboundEmailResult result = new InboundThreadHandler().handleInboundEmail(email, buildEnvelope());
        Test.stopTest();

        System.assertEquals(true, result.success);

        List<Communication_Thread__c> unmatched = [
            SELECT Id, Status__c, Subject__c
            FROM Communication_Thread__c
            WHERE Status__c = 'Inbound Unmatched'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals(1, unmatched.size());
        System.assertEquals('General faculty question', unmatched[0].Subject__c);
    }

    @isTest
    static void testUnmatchedWhenTokenHasNoMatchingThread() {
        Messaging.InboundEmail email = buildEmail('Re: Missing thread [TH-NOTFOUND]');

        Test.startTest();
        Messaging.InboundEmailResult result = new InboundThreadHandler().handleInboundEmail(email, buildEnvelope());
        Test.stopTest();

        System.assertEquals(true, result.success);

        List<Communication_Thread__c> unmatched = [
            SELECT Id, Status__c
            FROM Communication_Thread__c
            WHERE Status__c = 'Inbound Unmatched'
        ];
        System.assert(!unmatched.isEmpty());
    }

    @isTest
    static void testUnmatchedWhenSubjectBlank() {
        Messaging.InboundEmail email = buildEmail(null);

        Test.startTest();
        Messaging.InboundEmailResult result = new InboundThreadHandler().handleInboundEmail(email, buildEnvelope());
        Test.stopTest();

        System.assertEquals(false, result.success);
    }
}