# ISB-6082 Incoming Exchange — Technical Process Document

**Module**: International Exchange — Incoming Students  
**Platform**: Salesforce Education Cloud (Org B)  
**API Version**: 60.0  
**Date**: 24-Jun-2026

---

## 1. End-to-End Process (Current)

1. ASA uploads incoming exchange students (Contact + ProgramEnrollment created)
2. PGID generation runs on qualifying Program Enrollment
3. User provisioning executes
4. Exit Clearance Case auto-creates via `Incoming_Case_AutoCreate_Flow`
5. Case follows new lifecycle via `IncomingExchangeCaseHandler`

---

## 2. Key Components Updated

### Apex
- `IncomingExchangeCaseHandler.cls`
  - New stage transition logic
  - Case-team-role-driven RO owner handoff on ASA clearance
  - Auto-close on transcript dispatch
- `InternationalExchangeController.cls`
  - Incoming Excel upload parser supports `Gender` column
  - Gender mapping to `Contact.SAP_Gender_Code__c`:
    - Male -> 1
    - Female -> 2
    - Other -> 0
- `CaseTriggerHandler.cls` + `CaseTrigger.trigger`
  - Department clearance stamp ownership moved to Apex before update
  - Independent stamping per flag (Ops/IT/LRC/ASA/Finance) supports simultaneous checkbox updates in one save

### Flow
- `Incoming_Case_AutoCreate_Flow`
  - Initial status = `Exit Case Initiated`
  - Owner set from case team template role (Student Affairs)
  - V-INC-03 active-case guard retained
  - Case field prefill from ProgramEnrollment + Contact

### Metadata
- Business process: Incoming Exchange
  - Added statuses: `Exit Case Initiated`, `Finance Processing`, `ASA Processing`
  - Kept legacy statuses for old records
- StandardValueSet: `CaseStatus`
  - Added corresponding status values
- New Case field: `Department_Remarks__c` (Long Text)

---

## 3. Exit Clearance Case Auto-Create (ISB-6086)

### Trigger condition
- Record-triggered after-save on `ProgramEnrollment`
- Fires when:
  - `PGID__c` is not blank
  - `Sub_Status__c = Incoming Exchange`

### Guard
- Checks active incoming exchange exit case for same contact
- If found, no duplicate case creation

### Case values on create
- `RecordTypeId` = `Incoming_Exchange_Exit_Clearance`
- `Status` = `Exit Case Initiated`
- `OwnerId` = Student Affairs member from `Incoming Team` case team template (Role = Student Affairs)
- `Program_Enrollment__c` = current ProgramEnrollment
- `PGID__c` = ProgramEnrollment PGID
- `Finance_Cleared__c` = `Open`
- `Expected_Exit_Date__c` = `Check_Out_Date__c`

### Source mapping used
- From ProgramEnrollment:
  - `Accomodation_Type__c`
  - `Check_In_Date__c`
  - `Check_Out_Date__c`
  - `Exchange_School__c` (resolved to Account Name → `Case.Exchange_School_Home__c`)
  - `Location__c` (resolved to Location Name → `Case.Campus__c`)
- From Contact:
  - `Home_Institution_Contact_Name__c`
  - `Home_Institution_Contact_Email__c`

---

## 4. Case Lifecycle Logic (Apex)

Implemented in `IncomingExchangeCaseHandler.handleBeforeUpdate()`:

1. **Exit Case Initiated → Finance Processing**  
   Condition: Ops + IT + LRC cleared

2. **Finance Processing → ASA Processing**  
   Condition: Finance Cleared = Cleared

3. **ASA Processing → Grades Awaited**  
   Condition: ASA SA Cleared = true  
  Side effect: Owner reassigned to the Case Team member with role `RO`

4. **Grades Awaited → Transcript Processing**  
   Condition: `CGPA__c` gets populated

5. **Transcript Dispatched → Closed**  
   Condition: `Transcript_Dispatched__c` changes false→true  
   Side effect: `Closed_Date__c` stamped

---

## 5. Ownership Resolution Rules

- Creation owner role key: `Student Affairs` (from `Incoming Team` case team template member)
- Handoff owner role key: `RO` (from `CaseTeamMember` records on current case)
- Resolver sequence:
  1. Resolve template and role for ASA at case creation
  2. Set owner to that template member's `MemberId`
  3. On ASA completion, query `CaseTeamMember` where `TeamRole.Name = 'RO'`
  4. Apply `OwnerId` when found

---

## 6. Deployment Notes

Manual deployment manifest: `manifest/package_2026_06_24.xml`

Important: deploy `CaseStatus.standardValueSet-meta.xml` with business process changes to ensure new status values are available.

Note: if your org still has active clearance auto-stamp flows (`ASA_SA_Clearance_AutoStamp_Flow`, `Operations_IT_LRC_Clearance_AutoStamp_Flow`), deactivate them after deploying Apex stamping to avoid duplicate ownership of the same fields.

---

*Technical Process Document | ISB-6082 Incoming Exchange | 24-Jun-2026*
