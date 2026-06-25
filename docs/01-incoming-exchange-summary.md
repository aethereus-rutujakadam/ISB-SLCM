# ISB-6082 Incoming Exchange Module — Combined Summary

**Epic**: ISB-6081 — International Exchange Students Module  
**Parent Story**: ISB-6082 — International Exchange - Incoming Students  
**Platform**: Salesforce Education Cloud — Org B (ISB Success Portal)  
**Date**: 24-Jun-2026  
**Status**: Updated for Upload + Clearance Stamping Changes

---

## 1. Executive Overview

Incoming Exchange now follows a case-team-driven Exit Clearance lifecycle with auto case creation on PGID generation, auto owner routing, and department/finance/ASA/RO stage progression.

**Key behavior now active:**
- Exit Clearance Case auto-created when `ProgramEnrollment.PGID__c` is populated
- Initial Case Status = `Exit Case Initiated`
- Case Owner resolved from Case Team template role mapping (Incoming Team, role = Student Affairs)
- Source stamping on case creation from Program Enrollment + Contact:
  - `Exchange_School_Home__c` from ProgramEnrollment Exchange School (Account name)
  - `Accomodation_Type__c`, `Check_In_Date__c`, `Check_Out_Date__c` from ProgramEnrollment
  - Home Institution contact details from Contact
  - `Expected_Exit_Date__c` auto-set = `Check_Out_Date__c`
- Incoming Excel upload now supports `Gender` and maps to `Contact.SAP_Gender_Code__c` as:
  - Male -> 1
  - Female -> 2
  - Other -> 0
- Department clearance stamps (By/Date) are now applied in Apex (`CaseTriggerHandler`) so simultaneous checkbox updates stamp all departments in one save
- Owner transfer to RO at ASA completion (Case Team role = RO)

---

## 2. Lifecycle (Current)

`Exit Case Initiated` → `Finance Processing` → `ASA Processing` → `Grades Awaited` → `Transcript Processing` → `Closed`

### Auto-transition logic
1. `Exit Case Initiated` → `Finance Processing` when `Operations_Cleared__c`, `IT_Cleared__c`, and `LRC_Cleared__c` are all true
2. `Finance Processing` → `ASA Processing` when `Finance_Cleared__c = Cleared`
3. `ASA Processing` → `Grades Awaited` when `ASA_SA_Cleared__c = true`, and owner switches to the case team member with role `RO`
4. `Grades Awaited` → `Transcript Processing` when `CGPA__c` is populated
5. `Transcript Processing`/`Grades Awaited` → `Closed` when `Transcript_Dispatched__c` is checked

---

## 3. Ownership Model

### Student Affairs owner at case creation
- Source: Incoming Team Case Team template
- Role: `Student Affairs`

### RO owner at handoff
- Source: Case Team members on the case
- Role: `RO`

---

## 4. Compatibility Note

Legacy statuses (`Draft`, `Finance Review Incoming`, `Dept Clearance`) are retained in status configuration so old records remain unchanged.

---

## 5. Deployment Package

Use manifest: `manifest/package_2026_06_24.xml`

This package includes:
- `IncomingExchangeCaseHandler.cls`
- `Incoming_Case_AutoCreate_Flow`
- Incoming Exchange business process update
- Case status value set updates (`Exit Case Initiated`, `Finance Processing`, `ASA Processing`)
- `Case.Department_Remarks__c`

---

*Updated: 24-Jun-2026 | Module: ISB-6082 Incoming Exchange*
