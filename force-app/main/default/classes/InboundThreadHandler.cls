global class InboundThreadHandler implements Messaging.InboundEmailHandler {

    global Messaging.InboundEmailResult handleInboundEmail(Messaging.InboundEmail email, Messaging.InboundEnvelope envelope) {  Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();   
        try {
            String extractedName = extractThreadNameFromSubject(email.subject);
            
            if (String.isNotBlank(extractedName)) {                
                List<Communication_Thread__c> threads = [                    
                    SELECT Id, Status__c, Course_Offering__c                    
                    FROM Communication_Thread__c  
                    WHERE Name = :extractedName
                    LIMIT 1
                ];
                
                if (!threads.isEmpty()) {
                    Communication_Thread__c thread = threads[0];
                    EmailMessage inboundMsg = new EmailMessage();
                    inboundMsg.RelatedToId = thread.Id;
                    inboundMsg.Communication_Thread__c = thread.Id;
                    inboundMsg.FromAddress = email.fromAddress;
                    inboundMsg.FromName = email.fromName;
                    inboundMsg.ToAddress = envelope.toAddress;
                    inboundMsg.Subject = email.subject;
                    inboundMsg.TextBody = email.plainTextBody;
                    inboundMsg.HtmlBody = email.htmlBody;
                    inboundMsg.Incoming = true;
                    inboundMsg.MessageDate = System.now();
                    insert inboundMsg;
                    
                    thread.Status__c = 'Pending Review';
                    thread.Last_Reply_Date__c = System.now();
                    update thread;
                } else {
                    createUnmatchedThread(email, envelope);
                }
            } else {
                createUnmatchedThread(email, envelope);
            }
            result.success = true;
        
      } catch (Exception e) {
            System.debug('InboundThreadHandler Error: ' + e.getMessage());                
            result.success = false;                
        }
        return result;                
    }

    private String extractThreadNameFromSubject(String subject) {
        if (String.isBlank(subject)) return null;
        
        // Regex to match specifically [TH-XXXXXX] — avoids false matches on tokens like [TERM] or [DEADLINE DATE]
        Pattern p = Pattern.compile('\\[(TH-[A-Z0-9]+)\\]');
        Matcher m = p.matcher(subject);
        
        if (m.find()) {
            return m.group(1); // Returns TH-XXXXXX without the brackets
        }
        return null;
    }

private void createUnmatchedThread(Messaging.InboundEmail email,Messaging.InboundEnvelope envelope) {
                Communication_Thread__c newThread = new Communication_Thread__c();
                newThread.Subject__c = email.subject;
                newThread.Status__c = 'Inbound Unmatched';
                newThread.Initiated_Date__c = System.now();
                insert newThread;
    
                EmailMessage msg = new EmailMessage();
                msg.RelatedToId = newThread.Id;
                msg.FromAddress = email.fromAddress;
                msg.Subject = email.subject;
                msg.TextBody = email.plainTextBody;
                msg.HtmlBody = email.htmlBody;
                msg.Incoming = true;
                msg.MessageDate = System.now();
                insert msg;
        }
}