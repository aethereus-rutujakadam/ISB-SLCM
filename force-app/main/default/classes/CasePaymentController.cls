public with sharing class CasePaymentController {
    
    // ⬅️ FETCH PAYMENT AMOUNT FOR CASE
    @AuraEnabled(cacheable=true)
    public static Decimal getCasePaymentAmount(Id caseId) {
        Case c = [
            SELECT Id, ContactId, Amount__c 
            FROM Case 
            WHERE Id = :caseId
            LIMIT 1
        ];
        return c.Amount__c;
    }
    
    // ⬅️ GET RAZORPAY KEY FROM CUSTOM METADATA
    @AuraEnabled(cacheable=true)
    public static String getRazorpayKey() {
        RazorPay_Setting__mdt setting = [
            SELECT Key_Id__c
            FROM RazorPay_Setting__mdt
            LIMIT 1
        ];
        return setting.Key_Id__c;
    }
    
    // ⬅️ CREATE ORDER USING EXISTING RAZORPAY CONTROLLER
    @AuraEnabled
    public static String createOrder(Decimal amount) {
        return RazorpayController.createOrder(amount);
    }
    
    // ⬅️ CREATE PAYMENT RECORD FOR REJOIN FEE
    @AuraEnabled
    public static Id createRejoinPayment(Id caseId, Decimal amountPaid, String status, String razorpayPaymentId) {
        
        if (caseId == null) {
            throw new AuraHandledException('Case Id is required.');
        }
        
        // 1️⃣ Get Case
        Case c = [
            SELECT Id, ContactId 
            FROM Case 
            WHERE Id = :caseId
            LIMIT 1
        ];
        
        // 2️⃣ Fetch Razorpay Secret to get payment mode
        RazorPay_Setting__mdt setting = [
            SELECT Key_Id__c, Key_Secret__c
            FROM RazorPay_Setting__mdt
            LIMIT 1
        ];
        
        // 3️⃣ Call Razorpay "fetch payment" API to retrieve payment mode
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.razorpay.com/v1/payments/' + razorpayPaymentId);
        req.setMethod('GET');
        
        String auth = setting.Key_Id__c + ':' + setting.Key_Secret__c;
        String encodedAuth = EncodingUtil.base64Encode(Blob.valueOf(auth));
        req.setHeader('Authorization', 'Basic ' + encodedAuth);
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        Map<String, Object> paymentResponse =
            (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        
        String paymentMode = (String) paymentResponse.get('method');
        
        System.debug('✅ Payment Mode from Razorpay: ' + paymentMode);
        
        // 4️⃣ INSERT PAYMENT RECORD
        ISB_Payment__c p = new ISB_Payment__c();
        p.Customer__c        = c.ContactId;
        p.Case__c           = caseId;
        p.Amount__c         = amountPaid;
        p.Payment_Type__c   = 'RejoinFee';
        p.Initiated__c      = status;
        p.Payment_Mode__c   = paymentMode;
        
        insert p;
        System.debug('✅ Rejoin Payment Record Created: ' + p.Id);
        
        Case caseToUpdate = new Case(
            Id = caseId,
            Rejoin_Amount_Paid__c = true
            //status = 'Payment Successful'
        );
        update caseToUpdate;
        
        System.debug('✅ Case Updated → Rejoin_Amount_Paid__c = TRUE');
        
        
        return p.Id;
    }
}