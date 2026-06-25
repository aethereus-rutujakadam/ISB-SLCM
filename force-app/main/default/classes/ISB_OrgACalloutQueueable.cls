/**
* ORG B
* Queueable Callout to ORG A
*/
public class ISB_OrgACalloutQueueable implements Queueable, Database.AllowsCallouts {
    
    private String  orgAApplicationId;
    private String  orgBPaymentId;
    private Boolean firstInstallmentPaid;
    private String  paymentStatus;
    
    public ISB_OrgACalloutQueueable(
        String   orgAApplicationId,
        String   orgBPaymentId,
        String   orgBInstallmentId,
        Boolean  firstInstallmentPaid,
        Decimal  paidAmount,
        String   currencyIsoCode,
        Datetime paidOn,
        String   paymentStatus,
        String   paymentMode
    ) {
        this.orgAApplicationId    = orgAApplicationId;
        this.orgBPaymentId        = orgBPaymentId;
        this.firstInstallmentPaid = firstInstallmentPaid;
        this.paymentStatus        = paymentStatus;
    }
    
    public void execute(QueueableContext context) {
        System.debug('====== ISB_OrgACalloutQueueable START ======');
        System.debug('ORG A Application Id : ' + orgAApplicationId);
        System.debug('ORG B Payment Id     : ' + orgBPaymentId);
        System.debug('firstInstallmentPaid : ' + firstInstallmentPaid);
        System.debug('paymentStatus        : ' + paymentStatus);
        
        // ── Default: mark as Failed, update to Success only on HTTP 200 ──────
        String initiatedStatus = 'Failed';
        
        try {
            Map<String, Object> payload = new Map<String, Object>{
                'orgAApplicationId'    => this.orgAApplicationId,
                    'orgBPaymentId'        => this.orgBPaymentId,
                    'firstInstallmentPaid' => this.firstInstallmentPaid,
                    'paymentStatus'        => this.paymentStatus
                    };
                        
                        String requestBody = JSON.serialize(payload);
            System.debug('📤 Request Payload : ' + requestBody);
            
            String endpoint = Label.ISB_OrgA_Payment_Confirmation_Endpoint;
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setBody(requestBody);
            req.setTimeout(20000);
            
            System.debug('📡 Sending callout to ORG A...');
            
            HttpResponse res = new Http().send(req);
            
            System.debug('📥 Response Status Code : ' + res.getStatusCode());
            System.debug('📥 Response Body        : ' + res.getBody());
            
            if (res.getStatusCode() == 200) {
                System.debug('✅ ORG A sync SUCCESS');
                initiatedStatus = 'Success';  // ✅ picklist value
            } else {
                System.debug('❌ ORG A sync FAILED. HTTP ' 
                             + res.getStatusCode() + ' | ' + res.getBody());
                initiatedStatus = 'Failed';   // ✅ picklist value
            }
            
        } catch (Exception e) {
            System.debug('❌ Exception during callout: ' + e.getMessage()
                         + ' | Stack: ' + e.getStackTraceString());
            initiatedStatus = 'Failed';       // ✅ picklist value on exception
        } finally {
            // ── Always update Initiated__c with Success or Failed ─────────────
            try {
                System.debug('💾 Updating ISB_Payment__c Initiated__c = ' 
                             + initiatedStatus + ' for Id: ' + orgBPaymentId);
                
                ISB_Payment__c pay = new ISB_Payment__c(Id = orgBPaymentId);
                pay.Initiated__c   = initiatedStatus;  // 'Success' or 'Failed'
                update pay;
                
                System.debug('✅ ISB_Payment__c Initiated__c updated to: ' + initiatedStatus);
            } catch (Exception updateEx) {
                System.debug('❌ Failed to update Initiated__c: ' + updateEx.getMessage());
            }
        }
        
        System.debug('====== ISB_OrgACalloutQueueable END ======');
    }
}