@isTest
private class myHandlerTest {

    @isTest
    static void handleInboundEmail_returnsResultWithoutException() {
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        email.subject = 'Unit Test Subject';
        email.fromAddress = 'sender@example.com';
        email.plainTextBody = 'Sample body';

        Messaging.InboundEnvelope envelope = new Messaging.InboundEnvelope();
        envelope.toAddress = 'receiver@example.com';

        Test.startTest();
        Messaging.InboundEmailResult result = new myHandler().handleInboundEmail(email, envelope);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Handler must return an InboundEmailResult instance.');
    }
}