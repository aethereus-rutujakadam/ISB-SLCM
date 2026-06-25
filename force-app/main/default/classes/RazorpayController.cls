public without sharing class RazorpayController {
    
    // Inner class to hold fee breakage details for LWC consumption
    public class FeeBreakageDetail {
        @AuraEnabled public String feeType;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Decimal pendingAmount; 
        @AuraEnabled public Decimal scholarshipAmount;
    }
    
    // Create Razorpay order
    @AuraEnabled
    public static String createOrder(Decimal amount) {
        try {
            // Fetch Razorpay settings from Custom Metadata
            RazorPay_Setting__mdt setting = [
                SELECT Key_Id__c, Key_Secret__c, Order_Endpoint_URL__c
                FROM RazorPay_Setting__mdt
                LIMIT 1
            ];
            
            if (setting == null) {
                throw new AuraHandledException('Razorpay settings not configured.');
            }
            
            if (amount == null || amount <= 0) {
                throw new AuraHandledException('Invalid payment amount.');
            }
            
            Integer amountInPaise = Integer.valueOf(amount * 100);
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(setting.Order_Endpoint_URL__c);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setTimeout(20000);
            
            String auth = setting.Key_Id__c + ':' + setting.Key_Secret__c;
            String encodedAuth = EncodingUtil.base64Encode(Blob.valueOf(auth));
            req.setHeader('Authorization', 'Basic ' + encodedAuth);
            
            Map<String, Object> body = new Map<String, Object>();
            body.put('amount', String.valueOf(amountInPaise));
            body.put('currency', 'INR');
            body.put('receipt', 'rcpt_' + System.currentTimeMillis());
            // REMOVED: body.put('payment_capture', 1); - This was triggering payment_risk_check_failed
            
            req.setBody(JSON.serialize(body));
            
            System.debug('📡 Creating order: ' + amount);
            Http http = new Http();
            HTTPResponse res = http.send(req);
            
            if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
                System.debug('✅ Order created: ' + res.getBody());
                return res.getBody();
            } else {
                System.debug('❌ Error: ' + res.getBody());
                throw new AuraHandledException('Order creation failed: ' + res.getBody());
            }
        } catch (CalloutException e) {
            System.debug('❌ Callout error: ' + e.getMessage());
            throw new AuraHandledException('Payment service unavailable. Try again.');
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug('❌ Error: ' + e.getMessage());
            throw new AuraHandledException('Error: ' + e.getMessage());
        }
    }
    
    // Get Razorpay Key
    @AuraEnabled(cacheable=true)
    public static String getRazorpayKey() {
        System.debug('--- Entered getRazorpayKey ---');
        RazorPay_Setting__mdt setting = [
            SELECT Key_Id__c
            FROM RazorPay_Setting__mdt
            LIMIT 1
        ];
        return setting.Key_Id__c;
    }
    
    // Create Salesforce Payment Record
    @AuraEnabled
    public static Id createPaymentRecord(Id applicationId, String status ,Decimal amountPaid) {
        System.debug('--- Entered createPaymentRecord ---');
        System.debug('applicationId param: ' + applicationId);
        System.debug('status param: ' + status);
        
        if (applicationId == null) {
            throw new AuraHandledException('Application Id is required.');
        }
        
        try {
            ISB_Payment__c p = new ISB_Payment__c();
            //p.Individual_Application__c = applicationId; // Use dynamic applicationId
            p.Initiated__c = status;
            p.Amount__c = amountPaid;
            p.Amount_Paid__c = amountPaid;
            p.Transaction_Date__c = Date.today();
            System.debug('Payment record before insert: ' + p);
            
            insert p;
            System.debug('Payment record created successfully with Id: ' + p.Id);
            
            return p.Id;
        } catch (Exception e) {
            System.debug('Error while creating payment record: ' + e.getMessage());
            throw new AuraHandledException('Payment record creation failed: ' + e.getMessage());
        }
    }
    
    
    @AuraEnabled(cacheable=true)
    public static List<FeeBreakageDetail> getInstallmentBreakageDetails(Id feeId) {
        try {
            System.debug('--- START: getInstallmentBreakageDetails ---');
            System.debug('Input Fee Id: ' + feeId);
            
            if (feeId == null) {
                throw new AuraHandledException('Fee Id is required.');
            }
            
            // Query ISB_Fee__c to get the linked ISB_Installment__c
            List<ISB_Fee__c> fees = [
                SELECT Id, ISB_Installment__c, Fee_Type__c
                FROM ISB_Fee__c
                WHERE Id = :feeId
                LIMIT 1
            ];
            
            if (fees.isEmpty()) {
                throw new AuraHandledException('No ISB_Fee__c found with ID: ' + feeId);
            }
            
            ISB_Fee__c fee = fees[0];
            
            if (fee.Fee_Type__c == null || !fee.Fee_Type__c.contains('Installment')) {
                return new List<FeeBreakageDetail>();
            }
            
            if (fee.ISB_Installment__c == null) {
                return new List<FeeBreakageDetail>();
            }
            
            // Query Fee Breakages from the linked Installment
            List<ISB_Student_Fee_Breakage__c> feeBreakages = [
                SELECT Fee_Type__c, Amount__c,Scholarship_Amount__c,Is_Active__c  
                FROM ISB_Student_Fee_Breakage__c
                WHERE ISB_Installment__c = :fee.ISB_Installment__c and Is_Active__c = true
                ORDER BY Fee_Type__c
            ];
            
            List<FeeBreakageDetail> breakageDetails = new List<FeeBreakageDetail>();
            for (ISB_Student_Fee_Breakage__c breakage : feeBreakages) {
                FeeBreakageDetail detail = new FeeBreakageDetail();
                detail.feeType = breakage.Fee_Type__c;
                detail.amount = breakage.Amount__c;
                detail.scholarshipAmount = breakage.Scholarship_Amount__c;
                // detail.pendingAmount = breakage.Pending_Amount__c != null ? breakage.Pending_Amount__c : breakage.Amount__c;
                breakageDetails.add(detail);
            }
            
            return breakageDetails;
        } catch (Exception e) {
            System.debug('❌ Error in getInstallmentBreakageDetails: ' + e.getMessage());
            throw new AuraHandledException('Failed to load breakage details: ' + e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static Decimal getInstallmentTotalAmount(Id feeId) {
        try {
            System.debug('=== START: getInstallmentTotalAmount ===');
            System.debug('Input Fee Id: ' + feeId);
            
            if (feeId == null) {
                throw new AuraHandledException('Fee Id is required.');
            }
            
            // Query ISB_Fee__c to get Total_amount__c
            List<ISB_Fee__c> fees = [
                SELECT Id, Total_amount__c,Fee_Amount__c
                FROM ISB_Fee__c
                WHERE Id = :feeId
                LIMIT 1
            ];
            
            if (fees.isEmpty()) {
                throw new AuraHandledException('No ISB_Fee__c found with ID: ' + feeId);
            }
            
            return fees[0].Fee_Amount__c != null ? fees[0].Fee_Amount__c : 0;
        } catch (Exception e) {
            System.debug('❌ Error in getInstallmentTotalAmount: ' + e.getMessage());
            throw new AuraHandledException('Failed to load total amount: ' + e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Decimal> getInstallmentAmount(Id feeId) {
        try {
            System.debug('--- START: getInstallmentAmount ---');
            System.debug('Input Fee Id: ' + feeId);
            
            if (feeId == null) {
                throw new AuraHandledException('Fee Id is required.');
            }
            
            // Query ISB_Fee__c for all amount fields
            List<ISB_Fee__c> fees = [
                SELECT Id, Total_amount__c, Paid_Amount__c, Pending_Amount__c,Fee_Amount__c
                FROM ISB_Fee__c
                WHERE Id = :feeId
                LIMIT 1
            ];
            
            if (fees.isEmpty()) {
                throw new AuraHandledException('No ISB_Fee__c found with ID: ' + feeId);
            }
            
            ISB_Fee__c fee = fees[0];
            Map<String, Decimal> result = new Map<String, Decimal>();
            result.put('totalAmount', fee.Fee_Amount__c != null ? fee.Fee_Amount__c : 0);
            result.put('paidAmount', fee.Paid_Amount__c != null ? fee.Paid_Amount__c : 0);
            result.put('pendingAmount', fee.Pending_Amount__c != null ? fee.Pending_Amount__c : 0);
            
            return result;
        } catch (Exception e) {
            System.debug('❌ Error in getInstallmentAmount: ' + e.getMessage());
            throw new AuraHandledException('Failed to load installment amount: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void updatePaymentRecordToFailed(
        Id paymentRecordId,
        String failureReason,
        String errorCode      
    ) {
        if (paymentRecordId == null) {
            throw new AuraHandledException('Payment Record Id is required.');
        }
        
        ISB_Payment__c payment = [
            SELECT Id, Initiated__c
            FROM ISB_Payment__c
            WHERE Id = :paymentRecordId
            LIMIT 1
        ];
        
        payment.Initiated__c      = 'Failed';
        payment.Error_Code__c     = errorCode;                   
        payment.Error_Message__c  = failureReason;               
        payment.Payment_Date__c   = System.now();               
        
        update payment;
        System.debug('✅ Payment marked as FAILED');
    }
    
    @AuraEnabled
    public static void processInstallmentFromMaster(Id feeId) {
        
        System.debug('================ START processInstallmentFromFeesMaster ================');
        System.debug('Input Fee Id: ' + feeId);
        
        if (feeId == null) {
            throw new AuraHandledException('Fee Id is required.');
        }
        
        // Fetch Fee + Installment + Enrollment (with Location)
        ISB_Fee__c fee = [
            SELECT Id,
            Pending_Amount__c,
            Program_Enrollment__c,
            Program_Enrollment__r.ContactId,
            Program_Enrollment__r.Academic_Term__c,
            Program_Enrollment__r.Location__c,
            ISB_Installment__c,
            ISB_Installment__r.Installment_Number__c
            FROM ISB_Fee__c
            WHERE Id = :feeId
            LIMIT 1
        ];
        
        if (fee.Program_Enrollment__c == null ||
            fee.Program_Enrollment__r.Academic_Term__c == null) {
                System.debug('⚠️ Program Enrollment or Academic Term is NULL. Exiting...');
                return;
            }
        
        if (fee.ISB_Installment__c == null ||
            fee.ISB_Installment__r.Installment_Number__c == null) {
                System.debug('⚠️ Installment or Installment Number is NULL. Exiting...');
                return;
            }
        
        // 🔒 ✅ CRITICAL CHECK — ONLY WHEN FULL PAYMENT IS DONE
        ISB_Installment__c inst = [
            SELECT Id, Pending_Amount__c, Installment_Status__c
            FROM ISB_Installment__c
            WHERE Id = :fee.ISB_Installment__c
            LIMIT 1
        ];
        
        if (inst.Pending_Amount__c != 0 || inst.Installment_Status__c != 'Paid') {
            System.debug('❌ Installment not fully paid. Skipping Enrollment Session creation.');
            return;
        }
        
        System.debug('✅ Installment fully paid. Proceeding with Enrollment Session creation.');
        
        Id peId = fee.Program_Enrollment__c;
        Id contactId = fee.Program_Enrollment__r.ContactId;
        Id academicTermId = fee.Program_Enrollment__r.Academic_Term__c;
        String installmentNumber = fee.ISB_Installment__r.Installment_Number__c;
        String enrollmentLocation = fee.Program_Enrollment__r.Location__c;
        
        System.debug('🔍 Program Enrollment Location: ' + enrollmentLocation);
        
        // Fetch Fees Master
        List<ISB_Fees_Master__c> masters = [
            SELECT Id, Installment__c, Academic_Term__c
            FROM ISB_Fees_Master__c
            WHERE Academic_Term__c = :academicTermId
            AND Installment__c = :installmentNumber
            LIMIT 1
        ];
        
        if (masters.isEmpty()) {
            System.debug('⚠️ No ISB_Fees_Master__c found. Exiting...');
            return;
        }
        
        ISB_Fees_Master__c master = masters[0];
        
        // Fetch ISB_Eligible_Term__c records linked to this Fees Master
        List<ISB_Eligible_Term__c> eligibleTerms = [
            SELECT Id, Academic_Session__c, Academic_Session__r.Id, 
                   Academic_Session__r.Name, Academic_Session__r.Location__c,
                   Academic_Session__r.From_Date__c, Academic_Session__r.To_date__c
            FROM ISB_Eligible_Term__c
            WHERE ISB_Fees_Master__c = :master.Id
            ORDER BY Sequence__c ASC
        ];
        
        if (eligibleTerms.isEmpty()) {
            System.debug('⚠️ No ISB_Eligible_Term__c records found. Exiting...');
            return;
        }
        
        System.debug('✅ Found ' + eligibleTerms.size() + ' eligible terms');
        
        // Convert eligible terms to Academic Sessions for enrollment
        // Include only sessions with a valid name and exact location match
        List<AcademicSession> sessionsForEnrollment = new List<AcademicSession>();
        
        for (ISB_Eligible_Term__c eligibleTerm : eligibleTerms) {
            AcademicSession acadSession = eligibleTerm.Academic_Session__r;
            if (acadSession == null || acadSession.Id == null) {
                System.debug('⚠️ Eligible term has no Academic Session. Skipping term Id=' + eligibleTerm.Id);
                continue;
            }
            
            System.debug('📌 Processing eligible term with session: ' + acadSession.Name + 
                        ' location: ' + acadSession.Location__c + 
                        ' (enrollment location: ' + enrollmentLocation + ')');

            if (String.isBlank(acadSession.Name)) {
                System.debug('⚠️ Academic Session name is blank. Skipping session Id=' + acadSession.Id);
                continue;
            }

            if (String.isBlank(enrollmentLocation) || acadSession.Location__c != enrollmentLocation) {
                System.debug('⚠️ Location mismatch. Skipping session Id=' + acadSession.Id +
                             ' | session location=' + acadSession.Location__c +
                             ' | enrollment location=' + enrollmentLocation);
                continue;
            }
            
            sessionsForEnrollment.add(acadSession);
        }
        
        if (sessionsForEnrollment.isEmpty()) {
            System.debug('⚠️ No Academic Sessions matched by Name and Location. Skipping Enrollment Session creation.');
            return;
        }
        
        System.debug('✅ Preparing to create ' + sessionsForEnrollment.size() + ' enrollment sessions');
        
        // Check Existing Enrollment Sessions (avoid duplicates)
        Set<Id> existingSessionIds = new Set<Id>();
        
        for (Enrollment_Session__c existing : [
            SELECT Id, Academic_Session__c
            FROM Enrollment_Session__c
            WHERE Program_Enrollment__c = :peId
        ]) {
            existingSessionIds.add(existing.Academic_Session__c);
        }
        
        // Prepare Sessions to Insert
        List<Enrollment_Session__c> sessionsToInsert = new List<Enrollment_Session__c>();
        
        for (AcademicSession sessionRec : sessionsForEnrollment) {
            
            if (existingSessionIds.contains(sessionRec.Id)) {
                System.debug('⚠️ Skipping duplicate session: ' + sessionRec.Id);
                continue;
            }
            
            Enrollment_Session__c rec = new Enrollment_Session__c();
            rec.Program_Enrollment__c = peId;
            rec.Academic_Session__c = sessionRec.Id;
            rec.Active__c = true;
            rec.Assigned_Contact__c = contactId;
            rec.Session_Start__c = sessionRec.From_Date__c;
            rec.Session_End__c = sessionRec.To_date__c;
            
            sessionsToInsert.add(rec);
        }
        
        if (!sessionsToInsert.isEmpty()) {
            insert sessionsToInsert;
            System.debug('✅ Enrollment Sessions Inserted: ' + sessionsToInsert.size());
        } else {
            System.debug('⚠️ No new Enrollment Sessions to insert.');
        }
        
        System.debug('================ END processInstallmentFromFeesMaster ================');
    }
    
    @AuraEnabled(cacheable=true)
    public static List<ISB_Payment__c> getPreviousPayments(Id feeId) {
        System.debug('=== START: getPreviousPayments ===');
        System.debug('Input Fee Id: ' + feeId);
        
        if (feeId == null) {
            throw new AuraHandledException('Fee Id is required.');
        }
        
        // ✅ Query ISB_Fee__c to get Fee_Type__c and ISB_Installment__c
        ISB_Fee__c fee = [
            SELECT Id, ISB_Installment__c, Fee_Type__c
            FROM ISB_Fee__c
            WHERE Id = :feeId
            LIMIT 1
        ];
        
        System.debug('Fee Type: ' + fee.Fee_Type__c);
        System.debug('Linked Installment ID: ' + fee.ISB_Installment__c);
        
        // ✅ If Fee Type contains 'Installment' → query by ISB_Installment__c
        if (fee.Fee_Type__c != null && fee.Fee_Type__c.contains('Installment') && fee.ISB_Installment__c != null) {
            System.debug('✅ Installment Fee - Querying payments by ISB_Installment__c');
            return [
                SELECT Id, Amount__c, CreatedDate, Initiated__c, Payment_Mode__c, Transaction_Date__c
                FROM ISB_Payment__c
                WHERE ISB_Installment__c = :fee.ISB_Installment__c
                ORDER BY CreatedDate DESC
            ];
        }
        
        // ✅ For all other fee types → query directly by ISB_Fees__c
        System.debug('✅ Non-Installment Fee - Querying payments by ISB_Fees__c');
        return [
            SELECT Id, Amount__c, CreatedDate, Initiated__c, Payment_Mode__c, Transaction_Date__c
            FROM ISB_Payment__c
            WHERE ISB_Fees__c = :feeId
            ORDER BY CreatedDate DESC
        ];
    }
    
    @AuraEnabled
    public static Id createInitiatedPaymentRecord(
        Id feeId,
        Decimal amountPaid,
        String paymentMode,
        String currencyValue,
        String orderId
    ) {
        System.debug('=== START createInitiatedPaymentRecord ===');
        
        if (feeId == null) {
            throw new AuraHandledException('Fee Id is required.');
        }
        if (amountPaid == null || amountPaid <= 0) {
            throw new AuraHandledException('Valid payment amount is required.');
        }
        
        ISB_Fee__c fee = [
            SELECT Id, ISB_Installment__c, Contact__c, Fee_Type__c, Program_Enrollment__c,
            Contact__r.Name, Contact__r.Email, Contact__r.Phone,    
            Contact__r.MobilePhone                                   
            FROM ISB_Fee__c
            WHERE Id = :feeId
            LIMIT 1
        ];
        
        Id installmentId = fee.ISB_Installment__c;
        Id contactId     = fee.Contact__c;
        Id programEnrollmentId = fee.Program_Enrollment__c;
        String feeType   = fee.Fee_Type__c;
        
        if (contactId == null) {
            contactId = getInstallmentContact(installmentId);
        }
        
        String contactName  = fee.Contact__r.Name;
        String contactEmail = fee.Contact__r.Email;
        String contactPhone = fee.Contact__r.MobilePhone != null
            ? fee.Contact__r.MobilePhone
            : fee.Contact__r.Phone;
        
        ISB_Payment__c payment = new ISB_Payment__c();
        
        payment.ISB_Installment__c      = installmentId;
        payment.ISB_Fees__c             = feeId;
        payment.Program_Enrollment__c   = programEnrollmentId;
        payment.Customer__c             = contactId;
        payment.Payment_Type__c         = feeType;
        payment.Amount__c               = amountPaid;
        payment.Customer_Name__c        = contactName;   
        payment.Customer_Email__c       = contactEmail;  
        payment.Customer_Phone__c       = contactPhone;  
        payment.Payment_Method__c       = 'Online';
        payment.Payment_Mode_Type__c    = 'Online';
        payment.Initiated__c            = 'Initiated';
        payment.Payment_Date__c         = System.now();
        payment.Transaction_Date__c     = Date.today();
        payment.Amount_Paid__c          = amountPaid;
        
        if (String.isNotBlank(orderId)) {
            payment.Payment_Order_Id__c = orderId;
        }
        
        payment.Error_Code__c           = null;
        payment.Error_Message__c        = null;
        payment.RP_Event_Fired__c       = null;
        
        insert payment;
        System.debug('✅ Payment Record Created: ' + payment.Id);
        
        return payment.Id;
    }
    
    @AuraEnabled
    public static void updatePaymentRecordToSuccess(
        Id paymentRecordId,
        String razorpayPaymentId,
        String razorpayOrderId,       
        String razorpaySignature,     
        Boolean includeGST,           
        String couponId,             
        Decimal couponAmount         
    ) {
        System.debug('=== START updatePaymentRecordToSuccess ===');
        
        try {
            if (paymentRecordId == null) {
                throw new AuraHandledException('Payment Record Id is required.');
            }
            
            RazorPay_Setting__mdt setting = [
                SELECT Key_Id__c, Key_Secret__c
                FROM RazorPay_Setting__mdt
                LIMIT 1
            ];
            
            if (setting == null) {
                throw new AuraHandledException('Razorpay settings not configured.');
            }
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint('https://api.razorpay.com/v1/payments/' + razorpayPaymentId);
            req.setMethod('GET');
            req.setTimeout(20000);
            req.setHeader('Authorization', 'Basic ' +
                          EncodingUtil.base64Encode(Blob.valueOf(setting.Key_Id__c + ':' + setting.Key_Secret__c)));
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() != 200) {
                System.debug('❌ Verification failed: ' + res.getBody());
                throw new AuraHandledException('Verification failed: ' + res.getBody());
            }
            
            Map<String, Object> paymentResponse =
                (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            String razorpayMethod = (String) paymentResponse.get('method');
            String paymentMethod = mapRazorpayPaymentMethod(razorpayMethod);
            
            System.debug('✅ Razorpay Method: ' + razorpayMethod + ' → Mapped to: ' + paymentMethod);
            
            // === Load payment record ===
            ISB_Payment__c payment = [
                SELECT Id, ISB_Installment__c, ISB_Fees__c, Amount__c
                FROM ISB_Payment__c
                WHERE Id = :paymentRecordId
                LIMIT 1
            ];
            
            if (payment == null) {
                throw new AuraHandledException('Payment record not found.');
            }
            
            Decimal amount = payment.Amount__c;
            
            if (amount == null || amount <= 0) {
                throw new AuraHandledException('Invalid payment amount.');
            }
            
            // === Update ISB_Fee__c amounts ===
            if (payment.ISB_Fees__c != null) {
                ISB_Fee__c fee = [
                    SELECT Id, Pending_Amount__c, Paid_Amount__c, Fee_Amount__c, Fee_Status__c
                    FROM ISB_Fee__c
                    WHERE Id = :payment.ISB_Fees__c
                    LIMIT 1
                ];
                
                fee.Pending_Amount__c = (fee.Pending_Amount__c != null ? fee.Pending_Amount__c : 0) - amount;
                fee.Paid_Amount__c    = (fee.Paid_Amount__c    != null ? fee.Paid_Amount__c    : 0) + amount;
                
                if      (fee.Paid_Amount__c >= fee.Fee_Amount__c) { fee.Fee_Status__c = 'Paid'; }
                else if (fee.Paid_Amount__c  > 0)                 { fee.Fee_Status__c = 'Partially Paid'; }
                
                update fee;
            }
            
            // === Update ISB_Installment__c amounts ===
            if (payment.ISB_Installment__c != null) {
                ISB_Installment__c inst = [
                    SELECT Id, Pending_Amount__c, Paid_Amount__c, Total_Amount__c, Installment_Status__c
                    FROM ISB_Installment__c
                    WHERE Id = :payment.ISB_Installment__c
                    LIMIT 1
                ];
                
                inst.Pending_Amount__c = (inst.Pending_Amount__c != null ? inst.Pending_Amount__c : 0) - amount;
                inst.Paid_Amount__c    = (inst.Paid_Amount__c    != null ? inst.Paid_Amount__c    : 0) + amount;
                
                if      (inst.Paid_Amount__c >= inst.Total_Amount__c) { inst.Installment_Status__c = 'Paid'; }
                else if (inst.Paid_Amount__c  > 0)                    { inst.Installment_Status__c = 'Partially Paid'; }
                
                update inst;
            }
            
            // === Update payment record ===
            payment.Initiated__c            = 'Success';
            payment.Payment_ID__c           = razorpayPaymentId;
            payment.Payment_Order_Id__c     = razorpayOrderId;
            payment.Payment_Signature__c    = razorpaySignature;
            payment.Payment_Method__c       = paymentMethod;  // Mapped value from Razorpay method
            payment.Payment_Mode__c         = paymentMethod;  // Mapped value from Razorpay method
            payment.Amount__c               = amount;                                       
            payment.Payment_Date__c         = System.now();
            payment.Error_Code__c           = null;
            payment.Error_Message__c        = null;
            payment.RP_Event_Fired__c       = null;
            payment.Amount_Paid__c          = amount;
            
            update payment;
            
            // === Create approval case ===
            Case c = createPaymentApprovalCase(
                payment.Id,
                payment.ISB_Installment__c,
                amount,
                Date.today(),
                'Online'
            );
            
            payment.Case__c = c.Id;
            update payment;
            
            System.debug('✅ Payment success → amounts updated → case created');
        } catch (CalloutException e) {
            System.debug('❌ Callout Exception: ' + e.getMessage());
            throw new AuraHandledException('Payment verification failed. Try again.');
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug('❌ Error in payment success: ' + e.getMessage());
            throw new AuraHandledException('Payment processing failed: ' + e.getMessage());
        }
    }
    
    
    // Helper method to update installment status
    public static void updateInstallmentStatus(Id installmentId) {
        System.debug('=== START updateInstallmentStatus ===');
        
        ISB_Installment__c inst = [
            SELECT Id, Total_Amount_calc__c, Paid_Amount__c, Installment_Status__c,Total_Amount__c 
            FROM ISB_Installment__c
            WHERE Id = :installmentId
            LIMIT 1
        ];
        
        // Calculate Total Paid
        AggregateResult ar = [
            SELECT SUM(Amount__c) totalPaid
            FROM ISB_Payment__c
            WHERE ISB_Installment__c = :installmentId
            AND Initiated__c = 'Success'
        ];
        
        Decimal totalPaid = (Decimal) ar.get('totalPaid');
        if (totalPaid == null) totalPaid = 0;
        
        Decimal totalDue = inst.Total_Amount__c;
        Decimal pendingAmount = totalDue - totalPaid;
        
        inst.Paid_Amount__c = totalPaid;
        inst.Pending_Amount__c = pendingAmount;
        
        if (totalPaid >= totalDue) {
            inst.Installment_Status__c = 'Paid';
        } else if (totalPaid > 0) {
            inst.Installment_Status__c = 'Partially Paid';
        }
        
        try {
            update inst;
            System.debug(' Installment Updated - Status: ' + inst.Installment_Status__c);
            System.debug(' Paid Amount: ' + inst.Paid_Amount__c);
            System.debug(' Pending Amount: ' + inst.Pending_Amount__c);
        } catch (Exception ex) {
            System.debug(' Error updating installment: ' + ex.getMessage());
        }
        
        System.debug('=== END updateInstallmentStatus ===');
    }
    
    private static Id getInstallmentContact(Id installmentId) {
        ISB_Installment__c inst = [
            SELECT Id, Contact__c
            FROM ISB_Installment__c
            WHERE Id = :installmentId
            LIMIT 1
        ];
        
        if (inst.Contact__c == null) {
            throw new AuraHandledException('Installment has no Contact linked.');
        }
        
        return inst.Contact__c;
    }
    
    @AuraEnabled
    public static Id saveOfflinePayment(
        Id feeId,
        Decimal amountPaid,
        String paymentMode,
        String transactionDate,
        // Cheque/DD fields
        String chequeNumber,
        String bankName,
        // Bank Loan fields
        String rtgsNeftNumber,
        // Corporate Sponsor fields
        String companyName,
        String chequeNo,
        // Cash Transaction fields
        String receiptNumber,
        String receivedBy
    ) {
        System.debug('=== START saveOfflinePayment ===');
        System.debug('Fee ID: ' + feeId);
        System.debug('Amount Paid: ' + amountPaid);
        System.debug('Payment Mode: ' + paymentMode);
        
        if (feeId == null) {
            throw new AuraHandledException('Fee Id is required.');
        }
        
        if (amountPaid == null || amountPaid <= 0) {
            throw new AuraHandledException('Valid payment amount is required.');
        }
        
        // Query ISB_Fee__c to get ISB_Installment__c and Fee_Type__c
        ISB_Fee__c fee = [
            SELECT Id, ISB_Installment__c, Contact__c, Fee_Type__c,Pending_Amount__c,Fee_Status__c,Paid_Amount__c,Total_amount__c,Program_Enrollment__c
            FROM ISB_Fee__c
            WHERE Id = :feeId
            LIMIT 1
        ];
        
        Id installmentId = fee.ISB_Installment__c;
        Id contactId = fee.Contact__c;
        String feeType = fee.Fee_Type__c;
        Id programEnrollmentId = fee.Program_Enrollment__c; 
        
        System.debug('Fee Type: ' + feeType);
        
        if (contactId == null) {
            contactId = getInstallmentContact(installmentId);
        }
        
        // Create Offline Payment Record
        ISB_Payment__c payment = new ISB_Payment__c();
        payment.ISB_Fees__c = feeId;
        payment.Customer__c = contactId;
        payment.Amount__c = amountPaid;
        payment.Initiated__c = 'Initiated';
        payment.Payment_Mode__c = mapRazorpayPaymentMethod(paymentMode);  // Map to valid picklist value
        payment.Payment_Mode_Type__c = 'Offline';
        payment.mode_of_payment__c = 'Offline';
        payment.Transaction_Date__c = String.isNotBlank(transactionDate) ? Date.valueOf(transactionDate) : Date.today();
        payment.ISB_Installment__c = installmentId;
        payment.Payment_Type__c = feeType;
        payment.Program_Enrollment__c = programEnrollmentId;
        payment.Amount_Paid__c = amountPaid;
        payment.Payment_Date__c = String.isNotBlank(transactionDate) ? 
        DateTime.newInstance(Date.valueOf(transactionDate), Time.newInstance(0, 0, 0, 0)) : 
        DateTime.now();
        
        // Mode-specific fields
        if (paymentMode == 'Cheque/DD') {
            payment.Cheque_DD_Number__c = chequeNumber;
            payment.Bank_Name__c = bankName;
        }
        
        if (paymentMode == 'Bank Loan') {
            payment.Bank_Name__c = bankName;
            payment.RTGS_NEFT_Number__c = rtgsNeftNumber;
        }
        
        if (paymentMode == 'Corporate Sponsor') {
            payment.Company_Name__c = companyName;
            payment.Bank_Name__c = bankName;
            payment.RTGS_NEFT_Number__c = rtgsNeftNumber;
            payment.Cheque_No__c = chequeNo;
        }
        
        if (paymentMode == 'Wire Transfer') {
            payment.Bank_Name__c = bankName;
            payment.RTGS_NEFT_Number__c = rtgsNeftNumber;
        }
        
        insert payment;
        System.debug('✅ Payment Record Created: ' + payment.Id);
        
        fee.Pending_Amount__c =
            (fee.Pending_Amount__c != null ? fee.Pending_Amount__c : 0) - amountPaid;
        
        fee.Paid_Amount__c =
            (fee.Paid_Amount__c != null ? fee.Paid_Amount__c : 0) + amountPaid;
        
        if (fee.Paid_Amount__c >= fee.Total_amount__c) {
            fee.Fee_Status__c = 'Paid';
        }
        else if (fee.Paid_Amount__c > 0) {
            fee.Fee_Status__c = 'Partially Paid';
        }
        
        update fee;
        
        if (installmentId != null) {
            
            ISB_Installment__c inst = [
                SELECT Id,
                Pending_Amount__c,
                Paid_Amount__c,
                Total_Amount_calc__c,
                Installment_Status__c
                FROM ISB_Installment__c
                WHERE Id = :installmentId
                LIMIT 1
            ];
            
            inst.Pending_Amount__c =
                (inst.Pending_Amount__c != null ? inst.Pending_Amount__c : 0) - amountPaid;
            
            inst.Paid_Amount__c =
                (inst.Paid_Amount__c != null ? inst.Paid_Amount__c : 0) + amountPaid;
            
            if (inst.Paid_Amount__c >= inst.Total_Amount_calc__c) {
                inst.Installment_Status__c = 'Paid';
            }
            else if (inst.Paid_Amount__c > 0) {
                inst.Installment_Status__c = 'Partially Paid';
            }
            
            update inst;
        }
        
        // Create Case
        Id financeQueueId = getFinanceQueueId();
        
        Case c = new Case();
        c.OwnerId = financeQueueId;
        c.RecordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get('Offline_Payment').getRecordTypeId();
        c.Subject = 'Offline Payment';
        c.Status = 'Pending With Finance';
        c.ISB_Payment__c = payment.Id;
        c.ISB_Installment__c = installmentId;
        c.Amount__c = amountPaid;
        c.Transaction_Date__c = String.isNotBlank(transactionDate) ? Date.valueOf(transactionDate) : Date.today();
        
        if (paymentMode == 'Cheque/DD') {
            c.Cheque_DD_Number__c = chequeNumber;
            c.Bank_Name__c = bankName;
        }
        
        if (paymentMode == 'Bank Loan') {
            c.Bank_Name__c = bankName;
            c.RTGS_NEFT_Number__c = rtgsNeftNumber;
        }
        
        if (paymentMode == 'Corporate Sponsor') {
            c.Company_Name__c = companyName;
            c.Bank_Name__c = bankName;
            c.RTGS_NEFT_Number__c = rtgsNeftNumber;
            c.Cheque_No__c = chequeNo;
        }
        
        if (paymentMode == 'Wire Transfer') {
            c.Bank_Name__c = bankName;
            c.RTGS_NEFT_Number__c = rtgsNeftNumber;
        }
        
        try {
            insert c;
            System.debug('✅ Case Created Successfully');
            sendCaseOwnerNotification(c.Id, c.OwnerId);

        } catch (Exception ex) {
            System.debug('❌ Error creating case: ' + ex.getMessage());
        }
        
        payment.Case__c = c.Id;
        update payment;
        
        // ✅ ONLY CALL processInstallmentFromMaster FOR INSTALLMENT FEES
        if (feeType != null && feeType.contains('Installment')) {
            System.debug('✅ Fee Type contains "Installment" - Will process enrollment sessions on case approval');
        } else {
            System.debug('⚠️ Fee Type is NOT Installment (' + feeType + ') - Skipping processInstallmentFromMaster');
        }
        
        System.debug('=== END saveOfflinePayment ===');
        return payment.Id;
    }
    
    private static Case createPaymentApprovalCase(
        Id paymentId,
        Id installmentId,
        Decimal amountPaid,
        Date transactionDate,
        String paymentMode
    ) {
        Id financeQueueId = getFinanceQueueId();
        Case c = new Case();
        c.OwnerId = financeQueueId;
        c.RecordTypeId =
            Schema.SObjectType.Case
            .getRecordTypeInfosByDeveloperName()
            .get('Offline_Payment')
            .getRecordTypeId();
        
        c.Subject = paymentMode + ' Payment';
        c.Status = 'Pending With Finance';
        c.ISB_Payment__c = paymentId;
        c.ISB_Installment__c = installmentId;
        c.Amount__c = amountPaid;
        c.Transaction_Date__c = transactionDate;
        
        insert c;
        sendCaseOwnerNotification(c.Id, c.OwnerId);

        return c;
    }
    
    private static void updateProgramEnrollmentStatus(Id installmentId) {
        System.debug('=== START updateProgramEnrollmentStatus ===');
        
        try {
            // Get Installment with Program Enrollment
            ISB_Installment__c inst = [
                SELECT Id, Program_Enrollment__c, Pending_Amount__c, Installment_Status__c
                FROM ISB_Installment__c
                WHERE Id = :installmentId
                LIMIT 1
            ];
            
            System.debug('Installment Status: ' + inst.Installment_Status__c);
            System.debug('Pending Amount: ' + inst.Pending_Amount__c);
            System.debug('Program Enrollment ID: ' + inst.Program_Enrollment__c);
            
            // Only update if installment is fully paid and has a program enrollment
            if (inst.Program_Enrollment__c != null && 
                inst.Pending_Amount__c == 0 && 
                inst.Installment_Status__c == 'Paid') {
                    
                    ProgramEnrollment pe = [
                        SELECT Id, Status, Sub_Status__c
                        FROM ProgramEnrollment
                        WHERE Id = :inst.Program_Enrollment__c
                        LIMIT 1
                    ];
                    
                    System.debug('Current Program Enrollment Status: ' + pe.Status);
                    System.debug('Current Program Enrollment Sub Status: ' + pe.Sub_Status__c);
                    
                    // Only update if currently On Hold due to fee payment
                    if (pe.Status == 'On Hold' && pe.Sub_Status__c == 'Fee payment') {
                        pe.Status = 'Registered';
                        pe.Sub_Status__c = null; // Clear sub-status
                        
                        update pe;
                        System.debug(' Program Enrollment Updated to Registered');
                    } else {
                        System.debug('️ Program Enrollment not On Hold for Fee payment - Status: ' + pe.Status + ', Sub Status: ' + pe.Sub_Status__c);
                    }
                } else {
                    System.debug(' Installment not fully paid or no Program Enrollment linked');
                }
            
        } catch (Exception ex) {
            System.debug(' Error updating Program Enrollment: ' + ex.getMessage() + ' at line ' + ex.getLineNumber());
        }
        
        System.debug('=== END updateProgramEnrollmentStatus ===');
    }
    
    private static Id getFinanceQueueId() {
        return [
            SELECT Id
            FROM Group
            WHERE Type = 'Queue'
            AND DeveloperName = 'Finance_Team'
            LIMIT 1
        ].Id;
    }  
    
    
    // NEW: Enhanced Breakage Detail with Pending Amounts
    public class BreakageAllocationDetail {
        @AuraEnabled public String feeType;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public Decimal paidAmount;
        @AuraEnabled public Decimal pendingAmount;
        @AuraEnabled public Decimal allocatedPayment;  // Amount being paid NOW
        @AuraEnabled public Decimal remainingPending;   // After this payment
        @AuraEnabled public Decimal scholarshipAmount; 
    }
    
    @AuraEnabled(cacheable=true)
    public static List<BreakageAllocationDetail> getBreakageWithPending(Id feeId) {
        System.debug('=== START: getBreakageWithPending ===');
        System.debug('Input Fee Id: ' + feeId);
        
        if (feeId == null) {
            throw new AuraHandledException('Fee Id is required.');
        }
        
        // Query ISB_Fee__c to get the linked ISB_Installment__c
        ISB_Fee__c fee = [
            SELECT Id, ISB_Installment__c, Fee_Type__c
            FROM ISB_Fee__c
            WHERE Id = :feeId
            LIMIT 1
        ];
        
        if (fee.Fee_Type__c == null || !fee.Fee_Type__c.contains('Installment')) {
            System.debug('⚠️ Not an Installment Fee - No breakage available');
            return new List<BreakageAllocationDetail>();
        }
        
        if (fee.ISB_Installment__c == null) {
            System.debug('No Installment linked to this Fee');
            return new List<BreakageAllocationDetail>();
        }
        
        System.debug('Linked Installment ID: ' + fee.ISB_Installment__c);
        
        // Query Fee Breakages with Paid and Pending amounts
        List<ISB_Student_Fee_Breakage__c> feeBreakages = [
            SELECT Fee_Type__c, Amount__c
            FROM ISB_Student_Fee_Breakage__c
            WHERE ISB_Installment__c = :fee.ISB_Installment__c
            ORDER BY Fee_Type__c
        ];
        
        System.debug('Student Fee Breakage Records Found: ' + feeBreakages.size());
        
        List<BreakageAllocationDetail> breakageDetails = new List<BreakageAllocationDetail>();
        
        for (ISB_Student_Fee_Breakage__c breakage : feeBreakages) {
            BreakageAllocationDetail detail = new BreakageAllocationDetail();
            detail.feeType = breakage.Fee_Type__c;
            detail.totalAmount = breakage.Amount__c != null ? breakage.Amount__c : 0;
            //detail.paidAmount = breakage.Paid_Amount__c != null ? breakage.Paid_Amount__c : 0;
            //detail.pendingAmount = breakage.Pending_Amount__c != null ? breakage.Pending_Amount__c : 0;
            detail.allocatedPayment = 0;  // Will be calculated in LWC
            detail.remainingPending = detail.pendingAmount;
            breakageDetails.add(detail);
        }
        
        System.debug('Returning Breakage Details Size: ' + breakageDetails.size());
        return breakageDetails;
    }  
    
    /**
* Update ISB_Student_Fee_Breakage__c records based on payment allocation
*/
    @AuraEnabled
    public static void updateBreakageRecords(
        Id feeId,
        Decimal paymentAmount,
        String allocationDataJson
    ) {
        System.debug('=== START updateBreakageRecords ===');
        System.debug('Fee ID: ' + feeId);
        System.debug('Payment Amount: ' + paymentAmount);
        System.debug('Allocation Data: ' + allocationDataJson);
        
        if (feeId == null || paymentAmount == null || paymentAmount <= 0) {
            throw new AuraHandledException('Invalid input parameters');
        }
        
        // Get ISB_Installment__c ID from Fee
        ISB_Fee__c fee = [
            SELECT Id, ISB_Installment__c
            FROM ISB_Fee__c
            WHERE Id = :feeId
            LIMIT 1
        ];
        
        if (fee.ISB_Installment__c == null) {
            System.debug('⚠️ No Installment linked to Fee');
            return;
        }
        
        // Parse the allocation data from LWC
        List<Object> allocations = (List<Object>) JSON.deserializeUntyped(allocationDataJson);
        
        // Query existing breakage records
        List<ISB_Student_Fee_Breakage__c> breakages = [
            SELECT Id, Fee_Type__c, Amount__c
            FROM ISB_Student_Fee_Breakage__c
            WHERE ISB_Installment__c = :fee.ISB_Installment__c
        ];
        
        // Create a map for easier lookup
        Map<String, ISB_Student_Fee_Breakage__c> breakageMap = new Map<String, ISB_Student_Fee_Breakage__c>();
        for (ISB_Student_Fee_Breakage__c b : breakages) {
            breakageMap.put(b.Fee_Type__c, b);
        }
        
        // Update each breakage record based on allocation
        List<ISB_Student_Fee_Breakage__c> toUpdate = new List<ISB_Student_Fee_Breakage__c>();
        
        for (Object obj : allocations) {
            Map<String, Object> allocation = (Map<String, Object>) obj;
            String feeType = (String) allocation.get('feeType');
            Decimal deductedAmount = (Decimal) allocation.get('deductedAmount');
            
            if (breakageMap.containsKey(feeType) && deductedAmount != null && deductedAmount > 0) {
                ISB_Student_Fee_Breakage__c breakage = breakageMap.get(feeType);
                
                toUpdate.add(breakage);
                
            }
        }
        
        if (!toUpdate.isEmpty()) {
            update toUpdate;
            System.debug('✅ Updated ' + toUpdate.size() + ' breakage records');
        }
        
        System.debug('=== END updateBreakageRecords ===');
    }
    
    /**
* Get loan details from Program Enrollment via ISB_Fee__c
* @param feeId - Fee record ID
* @return Map with loan field values
*/
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getLoanDetails(Id feeId) {
        try {
            System.debug('=== START: getLoanDetails ===');
            System.debug('Fee ID: ' + feeId);
            
            if (feeId == null) {
                throw new AuraHandledException('Fee Id is required.');
            }
            
            // Query ISB_Fee__c to get Program Enrollment
            List<ISB_Fee__c> fees = [
                SELECT Id,
                Program_Enrollment__c,
                Program_Enrollment__r.Loan_Bank_Name__c,
                Program_Enrollment__r.Loan_UTR_Number__c,
                Program_Enrollment__r.Loan_Account_Number__c,
                Program_Enrollment__r.Loan_Amount__c,
                Program_Enrollment__r.Sponsor_Company_Name__c,
                Program_Enrollment__r.Sponsor_GST_Number__c,
                Program_Enrollment__r.Sponsor_Pan_No__c,
                Program_Enrollment__r.Sponsor_TanNo__c,
                Program_Enrollment__r.Sponsor_City__c,
                Program_Enrollment__r.Sponsor_Company_Branch__c,
                Program_Enrollment__r.Sponsor_Company_Address__c,
                Program_Enrollment__r.Sponsor_State__c
                FROM ISB_Fee__c
                WHERE Id = :feeId
                LIMIT 1
            ];
            
            Map<String, String> loanData = new Map<String, String>();
            
            if (fees.isEmpty() || fees[0].Program_Enrollment__c == null) {
                System.debug('⚠️ No Program Enrollment found');
                loanData.put('Loan_Bank_Name__c', '');
                loanData.put('Loan_UTR_Number__c', '');
                loanData.put('Loan_Account_Number__c', '');
                loanData.put('Loan_Amount__c', '0');
                return loanData;
            }
            
            ISB_Fee__c fee = fees[0];
            
            loanData.put('Loan_Bank_Name__c', 
                         fee.Program_Enrollment__r.Loan_Bank_Name__c != null ? 
                         fee.Program_Enrollment__r.Loan_Bank_Name__c : '');
            
            loanData.put('Loan_UTR_Number__c', 
                         fee.Program_Enrollment__r.Loan_UTR_Number__c != null ? 
                         fee.Program_Enrollment__r.Loan_UTR_Number__c : '');
            
            loanData.put('Loan_Account_Number__c', 
                         fee.Program_Enrollment__r.Loan_Account_Number__c != null ? 
                         fee.Program_Enrollment__r.Loan_Account_Number__c : '');

            loanData.put('Loan_Amount__c', 
                         fee.Program_Enrollment__r.Loan_Amount__c != null ? 
                         String.valueOf(fee.Program_Enrollment__r.Loan_Amount__c) : '0');

            // NEW: Corporate Sponsor Fields
            loanData.put('Sponsor_Company_Name__c', 
                         fee.Program_Enrollment__r.Sponsor_Company_Name__c != null ? 
                         fee.Program_Enrollment__r.Sponsor_Company_Name__c : '');

            loanData.put('Sponsor_GST_Number__c', 
                         fee.Program_Enrollment__r.Sponsor_GST_Number__c != null ? 
                         fee.Program_Enrollment__r.Sponsor_GST_Number__c : '');

            loanData.put('Sponsor_Pan_No__c', 
                         fee.Program_Enrollment__r.Sponsor_Pan_No__c != null ? 
                         fee.Program_Enrollment__r.Sponsor_Pan_No__c : '');

            loanData.put('Sponsor_TanNo__c', 
                         fee.Program_Enrollment__r.Sponsor_TanNo__c != null ? 
                         fee.Program_Enrollment__r.Sponsor_TanNo__c : '');

            loanData.put('Sponsor_City__c', 
                         fee.Program_Enrollment__r.Sponsor_City__c != null ? 
                         fee.Program_Enrollment__r.Sponsor_City__c : '');

            loanData.put('Sponsor_Company_Branch__c', 
                         fee.Program_Enrollment__r.Sponsor_Company_Branch__c != null ? 
                         fee.Program_Enrollment__r.Sponsor_Company_Branch__c : '');

            loanData.put('Sponsor_Company_Address__c', 
                         fee.Program_Enrollment__r.Sponsor_Company_Address__c != null ? 
                         fee.Program_Enrollment__r.Sponsor_Company_Address__c : '');

            loanData.put('Sponsor_State__c', 
                         fee.Program_Enrollment__r.Sponsor_State__c != null ? 
                         fee.Program_Enrollment__r.Sponsor_State__c : '');
            
            System.debug(' Loan Details (including Sponsor fields) Retrieved:');
            System.debug('  Bank Name: ' + loanData.get('Loan_Bank_Name__c'));
            System.debug('  UTR Number: ' + loanData.get('Loan_UTR_Number__c'));
            System.debug('  Account Number: ' + loanData.get('Loan_Account_Number__c'));
            
            return loanData;
            
        } catch (Exception e) {
            System.debug(' Error in getLoanDetails: ' + e.getMessage());
            throw new AuraHandledException('Failed to load loan details: ' + e.getMessage());
        }
    }
    
    // Map Razorpay payment methods to Salesforce picklist values
    private static String mapRazorpayPaymentMethod(String razorpayMethod) {
        if (String.isBlank(razorpayMethod)) {
            return 'Card';
        }
        
        Map<String, String> methodMapping = new Map<String, String>{
            'card' => 'Card',
            'netbanking' => 'Net Banking',
            'upi' => 'UPI',
            'wallet' => 'Wallet',
            'emandate' => 'E-Mandate',
            'paylater' => 'Pay Later',
            'bnpl' => 'BNPL',
            'bank_transfer' => 'Bank Transfer'
        };
        
        String mapped = methodMapping.get(razorpayMethod.toLowerCase());
        return mapped != null ? mapped : razorpayMethod; // Return original if no mapping found
    }
    
    private static void sendCaseOwnerNotification(Id caseId, Id ownerId) {
        System.debug('=== START sendCaseOwnerNotification ===');
        System.debug('Case Id  : ' + caseId);
        System.debug('Owner Id : ' + ownerId);
        
        try {
            // ✅ Fetch Custom Notification Type Id
            CustomNotificationType notificationType = [
                SELECT Id
                FROM CustomNotificationType
                WHERE DeveloperName = 'Payment_Case_Notification'
                LIMIT 1
            ];
            
            System.debug('Notification Type Id: ' + notificationType.Id);
            
            // ✅ Resolve recipients
            // If owner is a Queue, get all Queue members
            // If owner is a User, send directly
            Set<String> recipientIds = new Set<String>();
            
            String ownerIdStr = String.valueOf(ownerId);
            
            if (ownerIdStr.startsWith('00G')) {
                // Owner is a Queue — fetch all active members
                System.debug('Owner is a Queue. Fetching Queue members...');
                
                List<GroupMember> members = [
                    SELECT UserOrGroupId
                    FROM GroupMember
                    WHERE GroupId = :ownerId
                ];
                
                for (GroupMember member : members) {
                    recipientIds.add(member.UserOrGroupId);
                }
                
                System.debug('Queue Members Found: ' + recipientIds.size());
                
            } else {
                // Owner is a direct User
                recipientIds.add(ownerIdStr);
                System.debug('Owner is a User: ' + ownerIdStr);
            }
            
            if (recipientIds.isEmpty()) {
                System.debug('⚠️ No recipients found. Skipping notification.');
                return;
            }
            
            // ✅ Build and send notification
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setTitle(' New Payment Approval Case');
            notification.setBody('A new payment case has been assigned and requires your approval.');
            notification.setNotificationTypeId(notificationType.Id);
            notification.setTargetId(caseId); // Clicking notification opens the Case
            notification.send(recipientIds);
            
            System.debug('✅ Notification sent to ' + recipientIds.size() + ' recipient(s)');
            
        } catch (Exception e) {
            // Non-blocking — log error but don't fail the payment flow
            System.debug('❌ Error sending notification: ' + e.getMessage());
            System.debug('Stack Trace: ' + e.getStackTraceString());
        }
        
        System.debug('=== END sendCaseOwnerNotification ===');
    }
    
     @AuraEnabled
    public static void updateLoanDetails(Id feeId, String loanBankName, String loanUtrNumber, String loanAccountNumber , Decimal loanAmount) {
        try {
            System.debug('=== START: updateLoanDetails ===');
            System.debug('Fee ID: ' + feeId);
            System.debug('Loan Bank Name: ' + loanBankName);
            System.debug('Loan UTR Number: ' + loanUtrNumber);
            System.debug('Loan Account Number: ' + loanAccountNumber);
            
            if (feeId == null) {
                throw new AuraHandledException('Fee Id is required.');
            }
            
            // Query ISB_Fee__c to get Program Enrollment
            List<ISB_Fee__c> fees = [
                SELECT Id, Program_Enrollment__c
                FROM ISB_Fee__c
                WHERE Id = :feeId
                LIMIT 1
            ];
            
            if (fees.isEmpty() || fees[0].Program_Enrollment__c == null) {
                throw new AuraHandledException('No Program Enrollment found for the fee.');
            }
            
            Id programEnrollmentId = fees[0].Program_Enrollment__c;
            
            // Update the Program Enrollment with loan details
            ProgramEnrollment pe = new ProgramEnrollment(
                Id = programEnrollmentId,
                Loan_Bank_Name__c = loanBankName,
                Loan_UTR_Number__c = loanUtrNumber,
                Loan_Account_Number__c = loanAccountNumber,
                Loan_Amount__c = loanAmount 
            );
            
            update pe;
            
            System.debug('✅ Loan details updated successfully for Program Enrollment: ' + programEnrollmentId);
            
        } catch (Exception e) {
            System.debug('❌ Error in updateLoanDetails: ' + e.getMessage());
            throw new AuraHandledException('Failed to update loan details: ' + e.getMessage());
        }
    }
}