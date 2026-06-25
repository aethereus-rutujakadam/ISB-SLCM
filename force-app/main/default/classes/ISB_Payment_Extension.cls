public without sharing class ISB_Payment_Extension {
    
    // --- Existing Visualforce Logic ---
    public ISB_Payment__c paymentRecord { get; set; }
    public String amountInWords { get; private set; }
    public String finalProgramName { get; private set; }
    public String studentId { get; private set; }
    
    public ISB_Payment_Extension(ApexPages.StandardController stdController) {
        Id paymentId = stdController.getId();
        
        if (paymentId != null) {
            this.paymentRecord = [
                SELECT Id, Name, CreatedDate, Transaction_Date__c, Amount__c,
                Cheque_DD_Number__c, RTGS_NEFT_Number__c, 
                Bank_Name__c, Branch_Branch__c,
                
                // Installment Info
                ISB_Installment__r.Name, 
                ISB_Installment__r.Program__r.Name,
                
                Program_Enrollment__c,
                Program_Enrollment__r.PGID__c,
                Program_Enrollment__r.Program.Name,
                
                // Customer Info
                Customer__r.Name,
                Customer__r.MailingStreet,
                Customer__r.MailingCity,
                Customer__r.MailingPostalCode,
                Customer__r.MailingCountry
                FROM ISB_Payment__c 
                WHERE Id = :paymentId 
                LIMIT 1
            ];
            
            // Get Student ID from Program Enrollment
            if (this.paymentRecord.Program_Enrollment__r != null) {
                this.studentId = this.paymentRecord.Program_Enrollment__r.PGID__c;
                System.debug('DEBUG_STUDENT_ID: ' + this.studentId);
            } else {
                this.studentId = '';
                System.debug('DEBUG_STUDENT_ID: Program Enrollment not found on Payment');
            }
            
            // Get Program Name - Try Program Enrollment first, then fallback to Installment
            if (this.paymentRecord.Program_Enrollment__r != null &&
                this.paymentRecord.Program_Enrollment__r.Program != null) {
                    
                    this.finalProgramName = this.paymentRecord.Program_Enrollment__r.Program.Name;
                    
                } else {
                    this.finalProgramName = '';
                }
            
            System.debug('DEBUG_FINAL: Program Name = ' + this.finalProgramName + ', Student ID = ' + this.studentId);
            
            // Calculate Amount in Words
            if (this.paymentRecord.Amount__c != null) {
                this.amountInWords = convertToIndianCurrency(this.paymentRecord.Amount__c);
            } else {
                this.amountInWords = '';
            }
        }
    }
    
    // --- NEW: LWC Method to Generate File ---
    @AuraEnabled
    public static String generateAndAttachReceipt(Id paymentId, String paymentName) {
        try {
            // 1. Reference the Visualforce Page
            PageReference pdfPage = Page.ISBPaymentReceipt; 
            pdfPage.getParameters().put('id', paymentId);
            
            // 2. Generate the PDF Blob (Handle Test Context)
            Blob pdfBlob;
            if (Test.isRunningTest()) { 
                pdfBlob = Blob.valueOf('Unit Test Attachment Body');
            } else {
                pdfBlob = pdfPage.getContentAsPDF();
            }
            
            // 3. Create ContentVersion (The File)
            ContentVersion cv = new ContentVersion();
            cv.Title = 'Receipt_' + paymentName + '.pdf';
            cv.PathOnClient = 'Receipt_' + paymentName + '.pdf';
            cv.VersionData = pdfBlob;
            cv.IsMajorVersion = true;
            insert cv;
            
            // 4. Get the ContentDocumentId
            Id conDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
            
            // 5. Link the File to the Payment Record
            ContentDocumentLink cdl = new ContentDocumentLink();
            cdl.LinkedEntityId = paymentId; 
            cdl.ContentDocumentId = conDocId;
            cdl.ShareType = 'V'; // Viewer permission
            cdl.Visibility = 'AllUsers'; // Visible to Community Users
            insert cdl;
            
            return 'Success';
            
        } catch (Exception e) {
            throw new AuraHandledException('Error generating receipt: ' + e.getMessage());
        }
    }
    
    // --- Existing Utility Methods ---
    public static String convertToIndianCurrency(Decimal amount) {
        if (amount == null || amount == 0) return 'Rupees Zero Only';
        Long amountLong = amount.longValue();
        Integer paise = (Integer)((amount - amountLong) * 100);
        String words = 'Rupees ' + convertNumber(amountLong);
        if (paise > 0) {
            words += ' and ' + convertNumber(paise) + ' Paise';
        }
        return words + ' Only/-';
    }
    
    private static String convertNumber(Long n) {
        if (n == 0) return '';
        String[] units = new String[]{ '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'};
            String[] tens = new String[]{ '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'};
                String str = '';
        if (n >= 10000000) { str += convertNumber(n / 10000000) + ' Crore '; n = Math.mod(n, 10000000); }
        if (n >= 100000) { str += convertNumber(n / 100000) + ' Lakh '; n = Math.mod(n, 100000); }
        if (n >= 1000) { str += convertNumber(n / 1000) + ' Thousand '; n = Math.mod(n, 1000); }
        if (n >= 100) { str += convertNumber(n / 100) + ' Hundred '; n = Math.mod(n, 100); }
        if (n > 0) {
            if (n < 20) { str += units[n.intValue()]; } 
            else { str += tens[(Integer)(n / 10)]; if (Math.mod(n, 10) > 0) str += ' ' + units[Math.mod(n, 10).intValue()]; }
        }
        return str.trim();
    }
}