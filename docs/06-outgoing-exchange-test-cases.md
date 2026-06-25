# ISB-6099 Outgoing Exchange — UAT Test Cases

**Module**: International Exchange — Outgoing Students  
**Test Phase**: UAT (User Acceptance Testing)  
**Platform**: Salesforce Education Cloud — Org B  
**Date**: 17-Jun-2026  
**Total Test Cases**: 62

---

## Test Execution Guide

**Personas Required for Testing:**
- ASA Student Affairs user (with `Outgoing_Exchange_ASA` permission set + `Outgoing_Exchange_ASA_User` custom permission)
- Registrar Office user (with `Outgoing_Exchange_RO` permission set)
- Finance user (with `Outgoing_Exchange_Finance` permission set)
- Program Office user (with `Outgoing_Exchange_ProgramOffice` permission set)
- System Admin (for setup verification and edge cases)
- Student portal user (for LWC testing)

**Prerequisites:**
- `CaseStatus` StandardValueSet deployed — verify `ASA In Progress`, `RO Review`, `Transcript Check`, `Student Credit Check` exist in Setup → Picklist Value Sets
- At least 1 Contact with an active `ProgramEnrollment` exists (to create test Cases against)
- At least 1 Account exists to use as Exchange School Partner
- An `AcademicTerm` record exists (for `Exchange_School_Cohort__c` tests)
- All 4 Outgoing Exchange permission sets assigned to test users
- Integration (INT-05) is parked — Cases must be created manually in UAT by System Admin with RT = Outgoing_Exchange and Status = ASA In Progress

---

## Happy Path Testing Guide (End-to-End Positive Tests)

This section summarizes the end-to-end positive lifecycle and configuration verifications, focusing on successful creations and auto-transitions.

### Phase 1: Case Creation & Initial State
**(Persona: System Admin)**
1. **Create the Case (TC-OUT-001, TC-OUT-004):** As the **System Admin**, create a new Case with Record Type `Outgoing Exchange`. Select a Contact, populate `Program_Enrollment__c` (ensuring the linked PE has an Exchange School), and verify the Status defaults to `ASA In Progress`.
2. **Verify Case Status Values (TC-OUT-002):** Confirm available stages are: *ASA In Progress, RO Review, Transcript Check, Student Credit Check, Closed*.
3. **Verify Exit Dates Validation Pass (TC-OUT-030):** Fill out `Planned_Exit_Date__c` and `Confirmed_Exit_Date__c` fields. Save the Case.

### Phase 2: Transitioning to "RO Review" (Gate 1)
**(Personas: ASA Student Affairs user, Finance user)**
1. **Trigger Department Clearances (TC-OUT-010 to TC-OUT-013):** As the **ASA user** (or respective dept users), check `ASA_SA_Cleared__c`, `Operations_Cleared__c`, `IT_Cleared__c`, and `LRC_Cleared__c`. As the **Finance user**, ensure `Finance_Cleared__c` is set to `Cleared`.
2. **Verify Auto-Transition & Stamps (TC-OUT-006):** Save the Case. Verify Status automatically changes to `RO Review` and all corresponding `Cleared_Date__c` and `Cleared_By__c` fields are automatically stamped.

### Phase 3: Transitioning to "Transcript Check" (Gate 2)
**(Persona: Registrar Office (RO) user)**
1. **Receive Partner Transcript (TC-OUT-014):** As the **RO user**, check `Partner_Transcript_Received__c` and save.
2. **Verify Auto-Transition & Stamps (TC-OUT-015):** Verify Status automatically changes to `Transcript Check` and `Partner_Transcript_Upload_Date__c` is stamped.

### Phase 4: Transitioning to "Student Credit Check" (Gate 3)
**(Persona: Registrar Office (RO) user)**
1. **Upload Documents (TC-OUT-018):** As the **RO user**, check `Grading_Scale_Uploaded__c` and `Course_Confirmation_Form__c`. Save the Case.
2. **Verify Auto-Transition:** Verify Status automatically changes to `Student Credit Check`.
3. **Test Transcript Dispatch Stamp (TC-OUT-020):** Check `Transcript_Dispatched__c` and save. Verify `Dispatch_Date__c` and `Dispatched_By__c` are populated.

### Phase 5: Case Closure (Gate 4)
**(Persona: Registrar Office (RO) user)**
1. **Trigger Graduation Audit (TC-OUT-023):** As the **RO user**, check `Ready_for_Graduation_Audit__c` and save.
2. **Verify Auto-Closure & Stamps (TC-OUT-024 & TC-OUT-025):** Verify Status automatically changes to `Closed`, `Closed_Date__c` is populated, and the Closure notification email is sent successfully.

### Phase 6: Custom Objects & Portals
**(Personas: System Admin, RO user, Student Portal user)**
1. **Create Exchange Course (TC-OUT-031, TC-OUT-036):** As the **RO user**, create a new `Exchange_Course__c` record linked to a valid `ProgramEnrollment__c`. Set `Status__c` and save.
2. **Update PE Grade (TC-OUT-037):** As the **RO user**, update `Letter_Grade__c` on the linked ProgramEnrollment.
3. **Create Exchange School Cohort (TC-OUT-034):** As the **System Admin**, create a new `Exchange_School_Cohort__c` linking a valid `Account__c` and `Academic_Term__c`.
4. **Verify Portal Rendering (TC-OUT-048, TC-OUT-049):** Log in to Experience Cloud as a **Student** with an active Outgoing Exchange Case. Verify the `outgoingExchangePortalTab` component renders successfully with Exchange School name, Terms, Case Status, and Exchange Courses datatable.
5. **Verify Transcript Dispatch Banner (TC-OUT-052):** As the **Student**, verify that a dispatch notification is visible on the student's portal view.

---

## Section 1 — Case Creation & Record Type (Phase 3) — 5 Test Cases

### TC-OUT-001: Manual case creation with Outgoing_Exchange RT
| Field | Value |
|-------|-------|
| **Precondition** | System Admin logged in |
| **Steps** | 1. Create new Case 2. Select Record Type = Outgoing Exchange 3. Fill Contact, Program_Enrollment__c (with Exchange_School__c populated), Status = ASA In Progress 4. Save |
| **Expected Result** | Case created successfully with RT = Outgoing Exchange and Status = ASA In Progress |
| **Priority** | Critical |

### TC-OUT-002: Business Process stages available on Case
| Field | Value |
|-------|-------|
| **Steps** | On a new Outgoing Exchange Case, inspect the Status picklist |
| **Expected Result** | Available values include: ASA In Progress, RO Review, Transcript Check, Student Credit Check, Closed |
| **Priority** | Critical |

### TC-OUT-003: V-OUT-10 — Exchange School Required
| Field | Value |
|-------|-------|
| **Steps** | Create Outgoing Exchange Case with a Program_Enrollment__c that has a blank Exchange_School__c; try to save |
| **Expected Result** | Validation error: Exchange School (Partner University) is required on Outgoing Exchange Cases |
| **Priority** | Critical |

### TC-OUT-004: Default status is ASA In Progress
| Field | Value |
|-------|-------|
| **Steps** | Create new Outgoing Exchange Case — check default Status |
| **Expected Result** | Status defaults to "ASA In Progress" |
| **Priority** | High |

### TC-OUT-005: Non-Outgoing RT cases unaffected by handler
| Field | Value |
|-------|-------|
| **Precondition** | A General Support case exists |
| **Steps** | Update any field on the General Support Case; save |
| **Expected Result** | Stage does not change; OutgoingExchangeCaseHandler does not fire for non-Outgoing RT |
| **Priority** | High |

---

## Section 2 — Stage Gate 1: ASA In Progress → RO Review — 8 Test Cases

### TC-OUT-006: Auto-transition fires when all gates met
| Field | Value |
|-------|-------|
| **Precondition** | Outgoing Exchange Case at Status = ASA In Progress |
| **Steps** | 1. Set Finance_Cleared__c = Cleared 2. Set ASA_SA_Cleared__c, Operations_Cleared__c, IT_Cleared__c, LRC_Cleared__c = true 3. Save |
| **Expected Result** | Status auto-changes to RO Review (trigger fires before save completes) |
| **Priority** | Critical |

### TC-OUT-007: Gate blocked — Finance not Cleared
| Field | Value |
|-------|-------|
| **Precondition** | Case at ASA In Progress; all 5 clearance flags = true; Finance_Cleared__c = Open |
| **Steps** | Save the record |
| **Expected Result** | Status remains ASA In Progress (Finance gate not met; no auto-transition) |
| **Priority** | Critical |

### TC-OUT-008: Gate blocked — one dept flag missing
| Field | Value |
|-------|-------|
| **Precondition** | Finance = Cleared; only 4 of 5 dept flags = true (LRC unchecked) |
| **Steps** | Save |
| **Expected Result** | Status remains ASA In Progress |
| **Priority** | High |

### TC-OUT-009: V-OUT-05 — Finance gate validation rule
| Field | Value |
|-------|-------|
| **Precondition** | Case already auto-transitioned to RO Review |
| **Steps** | Manually change Finance_Cleared__c back to Open; attempt to save |
| **Expected Result** | Validation error: Finance must be Cleared past ASA In Progress |
| **Priority** | Critical |

### TC-OUT-010: ASA_SA Clearance auto-stamps date and by
| Field | Value |
|-------|-------|
| **Steps** | Check ASA_SA_Cleared__c on an Outgoing Exchange Case; save |
| **Expected Result** | ASA_SA_Cleared_Date__c = current datetime; ASA_SA_Cleared_By__c = current user (stamped by Apex before-update logic) |
| **Priority** | High |

### TC-OUT-010A: Simultaneous department clearances stamp all fields in one save
| Field | Value |
|-------|-------|
| **Precondition** | Outgoing case at `ASA In Progress`; all relevant clearance fields currently unset |
| **Steps** | In one save, set `ASA_SA_Cleared__c`, `Operations_Cleared__c`, `IT_Cleared__c`, `LRC_Cleared__c` = true and set `Finance_Cleared__c` = Cleared |
| **Expected Result** | All `*_Cleared_By__c` and `*_Cleared_Date__c` fields are populated for ASA/Operations/IT/LRC, and `Finance_Cleared_Date__c` is populated in the same transaction |
| **Priority** | Critical |

### TC-OUT-011: Operations Clearance auto-stamp
| Field | Value |
|-------|-------|
| **Steps** | Check Operations_Cleared__c; save |
| **Expected Result** | Operations_Cleared_Date__c + Operations_Cleared_By__c populated |
| **Priority** | High |

### TC-OUT-012: IT Clearance auto-stamp
| Field | Value |
|-------|-------|
| **Steps** | Check IT_Cleared__c; save |
| **Expected Result** | IT_Cleared_Date__c + IT_Cleared_By__c populated |
| **Priority** | High |

### TC-OUT-013: LRC + Finance Clearance auto-stamp
| Field | Value |
|-------|-------|
| **Steps** | Check LRC_Cleared__c; set Finance_Cleared__c = Cleared; save |
| **Expected Result** | LRC_Cleared_Date__c + LRC_Cleared_By__c populated; Finance_Cleared_Date__c populated |
| **Priority** | High |

---

## Section 3 — Stage Gate 2: RO Review → Transcript Check — 4 Test Cases

### TC-OUT-014: Auto-transition on Partner Transcript Received
| Field | Value |
|-------|-------|
| **Precondition** | Case at Status = RO Review |
| **Steps** | Check Partner_Transcript_Received__c = true; save |
| **Expected Result** | Status auto-changes to Transcript Check |
| **Priority** | Critical |

### TC-OUT-015: Partner Transcript upload date auto-stamped
| Field | Value |
|-------|-------|
| **Steps** | Check Partner_Transcript_Received__c = true; save |
| **Expected Result** | Partner_Transcript_Upload_Date__c = current datetime (stamped by Outgoing_Transcript_Dispatch_Stamp_Flow) |
| **Priority** | High |

### TC-OUT-016: No auto-transition if flag not changed
| Field | Value |
|-------|-------|
| **Precondition** | Case at RO Review; Partner_Transcript_Received__c already = true from a previous save |
| **Steps** | Save another field update (e.g., Dispatch_Notes__c) |
| **Expected Result** | Status remains RO Review (flag not changed, transition does not re-fire) |
| **Priority** | High |

### TC-OUT-017: V-OUT-04 — Student Credit Check blocked without transcript
| Field | Value |
|-------|-------|
| **Precondition** | Case has Partner_Transcript_Received__c = false |
| **Steps** | Manually try to set Status = Student Credit Check; save |
| **Expected Result** | Validation error: Partner Transcript must be received before Student Credit Check |
| **Priority** | Critical |

---

## Section 4 — Stage Gate 3: Transcript Check → Student Credit Check — 5 Test Cases

### TC-OUT-018: Auto-transition when both grading flags set
| Field | Value |
|-------|-------|
| **Precondition** | Case at Transcript Check |
| **Steps** | Set Grading_Scale_Uploaded__c = true AND Course_Confirmation_Form__c = true; save |
| **Expected Result** | Status auto-changes to Student Credit Check |
| **Priority** | Critical |

### TC-OUT-019: Gate blocked — only one flag set
| Field | Value |
|-------|-------|
| **Precondition** | Case at Transcript Check; Grading_Scale_Uploaded__c = true; Course_Confirmation_Form__c = false |
| **Steps** | Save |
| **Expected Result** | Status remains Transcript Check |
| **Priority** | High |

### TC-OUT-020: Transcript Dispatched auto-stamp
| Field | Value |
|-------|-------|
| **Steps** | Check Transcript_Dispatched__c = true on a Transcript Check Case; save |
| **Expected Result** | Dispatch_Date__c = current datetime; Dispatched_By__c = current user |
| **Priority** | High |

### TC-OUT-021: Exchange Course grade entry by RO
| Field | Value |
|-------|-------|
| **Precondition** | At least one Exchange_Course__c record linked to the student's ProgramEnrollment |
| **Steps** | As RO, open Exchange_Course__c record; set Partner_Grade__c + Letter_Grade__c + ISB_Credits__c |
| **Expected Result** | Record saves successfully; grades visible on the case's related list |
| **Priority** | High |

### TC-OUT-022: Exchange Course status update
| Field | Value |
|-------|-------|
| **Steps** | Set Exchange_Course__c Status__c = Completed |
| **Expected Result** | Status picklist shows: Registered / Completed / Dropped; saves successfully |
| **Priority** | Medium |

---

## Section 5 — Stage Gate 4: Student Credit Check → Closed — 5 Test Cases

### TC-OUT-023: Auto-transition on Ready for Graduation Audit
| Field | Value |
|-------|-------|
| **Precondition** | Case at Student Credit Check |
| **Steps** | Check Ready_for_Graduation_Audit__c = true; save |
| **Expected Result** | Status auto-changes to Closed |
| **Priority** | Critical |

### TC-OUT-024: Closed_Date stamped on closure
| Field | Value |
|-------|-------|
| **Precondition** | Case transitions to Closed |
| **Steps** | Inspect Closed_Date__c |
| **Expected Result** | Closed_Date__c = current datetime (stamped by OutgoingExchangeCaseHandler) |
| **Priority** | Critical |

### TC-OUT-025: Closure notification email sent
| Field | Value |
|-------|-------|
| **Steps** | After case closes, check email logs |
| **Expected Result** | Email sent to Case Owner with subject "Outgoing Exchange Case Closed: {CaseNumber}" |
| **Priority** | High |

### TC-OUT-026: V-OUT-07 — No reopening after Closed
| Field | Value |
|-------|-------|
| **Precondition** | Case Status = Closed |
| **Steps** | Attempt to change Status to any other value |
| **Expected Result** | Validation error: Closed Outgoing Exchange Cases cannot be reopened |
| **Priority** | Critical |

### TC-OUT-027: V-OUT-07 — Admin cannot reopen either
| Field | Value |
|-------|-------|
| **Steps** | As System Admin, attempt to change Status from Closed on an Outgoing Exchange Case |
| **Expected Result** | Same validation error fires for Admin (VR applies to all profiles) |
| **Priority** | Critical |

---

## Section 6 — Exit Date Validation (V-OUT-06) — 3 Test Cases

### TC-OUT-028: V-OUT-06 — Exit dates required past ASA In Progress
| Field | Value |
|-------|-------|
| **Precondition** | Case at RO Review; Planned_Exit_Date__c and Confirmed_Exit_Date__c are blank |
| **Steps** | Attempt to save any field update on the Case |
| **Expected Result** | Validation error: Planned Exit Date and Confirmed Exit Date are required |
| **Priority** | Critical |

### TC-OUT-029: V-OUT-06 — No validation at ASA In Progress
| Field | Value |
|-------|-------|
| **Precondition** | Case at ASA In Progress; exit dates blank |
| **Steps** | Save any field update |
| **Expected Result** | Saves without error (exit dates optional at ASA In Progress stage) |
| **Priority** | High |

### TC-OUT-030: V-OUT-06 — Passes when both exit dates present
| Field | Value |
|-------|-------|
| **Precondition** | Case past ASA In Progress; both exit dates filled |
| **Steps** | Save any field update |
| **Expected Result** | Saves without exit date validation error |
| **Priority** | High |

---

## Section 7 — Custom Objects (Phase 1) — 7 Test Cases

### TC-OUT-031: Exchange_Course__c creation linked to ProgramEnrollment
| Field | Value |
|-------|-------|
| **Steps** | Create a new Exchange_Course__c record; set ProgramEnrollment__c to a valid PE |
| **Expected Result** | Record saves; appears in ProgramEnrollment's Exchange Courses related list |
| **Priority** | Critical |

### TC-OUT-032: Exchange_Course__c required ProgramEnrollment field
| Field | Value |
|-------|-------|
| **Steps** | Try to create Exchange_Course__c without ProgramEnrollment__c |
| **Expected Result** | Required field error: Program Enrollment is required |
| **Priority** | Critical |

### TC-OUT-033: Exchange_Course__c delete constraint on ProgramEnrollment
| Field | Value |
|-------|-------|
| **Precondition** | A ProgramEnrollment has 1+ Exchange_Course__c child records |
| **Steps** | Attempt to delete the ProgramEnrollment |
| **Expected Result** | Delete blocked (Restrict delete constraint): cannot delete ProgramEnrollment while Exchange Courses exist |
| **Priority** | High |

### TC-OUT-034: Exchange_School_Cohort__c creation
| Field | Value |
|-------|-------|
| **Steps** | Create Exchange_School_Cohort__c: set Account__c (partner university) + Academic_Term__c + Cohort_Name__c |
| **Expected Result** | Record saves successfully |
| **Priority** | Critical |

### TC-OUT-035: Exchange_School_Cohort__c Account delete constraint
| Field | Value |
|-------|-------|
| **Precondition** | An Account (partner university) has 1+ Exchange_School_Cohort__c records |
| **Steps** | Attempt to delete the Account |
| **Expected Result** | Delete blocked (Restrict delete constraint) |
| **Priority** | High |

### TC-OUT-036: Exchange Course Status picklist values
| Field | Value |
|-------|-------|
| **Steps** | Open Exchange_Course__c; inspect Status__c picklist |
| **Expected Result** | Values: Registered, Completed, Dropped |
| **Priority** | Medium |

### TC-OUT-037: Letter_Grade__c on ProgramEnrollment
| Field | Value |
|-------|-------|
| **Steps** | As RO user, edit ProgramEnrollment.Letter_Grade__c |
| **Expected Result** | Field is editable; saves successfully |
| **Priority** | Medium |

---

## Section 8 — Permission Sets & Access Control — 10 Test Cases

### TC-OUT-038: ASA user — Case CRUD access
| Field | Value |
|-------|-------|
| **Steps** | As ASA user (Outgoing_Exchange_ASA), create and edit an Outgoing Exchange Case |
| **Expected Result** | Case creation and edit work; exchange school, exit dates, nomination fields editable |
| **Priority** | Critical |

### TC-OUT-039: ASA user — Finance section read-only
| Field | Value |
|-------|-------|
| **Steps** | As ASA user, attempt to edit Finance_Notes__c or Total_Refund_Amount__c |
| **Expected Result** | Finance fields are read-only for ASA user |
| **Priority** | High |

### TC-OUT-040: ASA user — Transcript section read-only
| Field | Value |
|-------|-------|
| **Steps** | As ASA user, attempt to edit Grading_Scale_Uploaded__c |
| **Expected Result** | Field is read-only for ASA user (owned by RO) |
| **Priority** | High |

### TC-OUT-041: RO user — full Case CRUD
| Field | Value |
|-------|-------|
| **Steps** | As RO user (Outgoing_Exchange_RO), edit all sections of an Outgoing Exchange Case |
| **Expected Result** | All RO-owned fields editable: transcript fields, graduation audit, ready for audit flag, case closure |
| **Priority** | Critical |

### TC-OUT-042: RO user — Exchange_Course__c CRUD
| Field | Value |
|-------|-------|
| **Steps** | As RO user, create/edit/delete Exchange_Course__c records |
| **Expected Result** | Full CRUD access on Exchange Course |
| **Priority** | High |

### TC-OUT-043: Finance user — only finance section editable
| Field | Value |
|-------|-------|
| **Steps** | As Finance user (Outgoing_Exchange_Finance), open Outgoing Exchange Case; attempt to edit ASA fields |
| **Expected Result** | Only Finance section fields editable (Refund fields, Finance_Cleared__c, Finance_Notes__c); all other fields read-only |
| **Priority** | Critical |

### TC-OUT-044: Finance user — no Exchange_Course__c edit
| Field | Value |
|-------|-------|
| **Steps** | As Finance user, attempt to edit an Exchange_Course__c record |
| **Expected Result** | Record is read-only for Finance user |
| **Priority** | High |

### TC-OUT-045: Program Office user — read-only on everything
| Field | Value |
|-------|-------|
| **Steps** | As Program Office user (Outgoing_Exchange_ProgramOffice), navigate to Outgoing Exchange Case |
| **Expected Result** | Case visible; all fields read-only; no Edit, Create, or Delete button |
| **Priority** | High |

### TC-OUT-046: Program Office user — Contact and PE visible
| Field | Value |
|-------|-------|
| **Steps** | As Program Office user, navigate to the linked Contact and ProgramEnrollment |
| **Expected Result** | Both records visible with read-only access |
| **Priority** | Medium |

### TC-OUT-047: No access without permission set
| Field | Value |
|-------|-------|
| **Precondition** | User without any Outgoing_Exchange_* permission set |
| **Steps** | Attempt to access Outgoing Exchange Case |
| **Expected Result** | Object not visible or insufficient access error (depending on profile) |
| **Priority** | High |

---

## Section 9 — Student Portal LWC (Phase 11) — 6 Test Cases

### TC-OUT-048: LWC renders for student with active case
| Field | Value |
|-------|-------|
| **Precondition** | Student has an Outgoing Exchange Case (Status != Closed) |
| **Steps** | Log in as portal student; navigate to page with outgoingExchangePortalTab |
| **Expected Result** | Component renders; shows Exchange School name, From/To Term, Case Status |
| **Priority** | Critical |

### TC-OUT-049: Exchange courses datatable displayed
| Field | Value |
|-------|-------|
| **Precondition** | Exchange_Course__c records exist linked to student's ProgramEnrollment |
| **Steps** | View portal tab |
| **Expected Result** | Course datatable shows: Course Name, Code, Contact Hours, ISB Credits, Status |
| **Priority** | High |

### TC-OUT-050: Finance section NOT visible to student
| Field | Value |
|-------|-------|
| **Steps** | Inspect portal LWC as student |
| **Expected Result** | No Finance fields (Refund, Finance_Cleared__c, Finance_Notes__c) rendered |
| **Priority** | High |

### TC-OUT-051: Clearance flags NOT visible to student
| Field | Value |
|-------|-------|
| **Steps** | Inspect portal LWC as student |
| **Expected Result** | No clearance flags, clearance dates, or Graduation Audit section visible |
| **Priority** | High |

### TC-OUT-052: Transcript dispatch notification shown
| Field | Value |
|-------|-------|
| **Precondition** | Transcript_Dispatched__c = true on the Case |
| **Steps** | View portal tab |
| **Expected Result** | Transcript notification/banner visible to student |
| **Priority** | Medium |

### TC-OUT-053: No case — empty state handled
| Field | Value |
|-------|-------|
| **Precondition** | Student has no active Outgoing Exchange Case |
| **Steps** | View portal tab |
| **Expected Result** | Component renders without error; shows appropriate "No active exchange" message |
| **Priority** | Medium |

---

## Section 10 — Complete Lifecycle End-to-End — 3 Test Cases

### TC-OUT-054: Full lifecycle from ASA In Progress to Closed
| Field | Value |
|-------|-------|
| **Steps** | 1. Admin creates Case (RT=Outgoing Exchange, Status=ASA In Progress) 2. ASA sets exit dates + all clearance flags + Finance=Cleared → auto-transitions to RO Review 3. RO checks Partner_Transcript_Received → auto-transitions to Transcript Check 4. RO sets Grading_Scale_Uploaded + Course_Confirmation_Form → auto-transitions to Student Credit Check 5. RO checks Ready_for_Graduation_Audit → auto-transitions to Closed |
| **Expected Result** | All 4 stage transitions fire; Closed_Date__c populated; closure email sent; case locked |
| **Priority** | Critical |

### TC-OUT-055: Finance clearance workflow with refund
| Field | Value |
|-------|-------|
| **Steps** | As Finance user: 1. Set Refund_Type__c 2. Fill Accommodation_Refund_Amount__c + Other_Adjustment_Amount__c 3. Set Finance_Cleared__c = Cleared 4. Save |
| **Expected Result** | All finance fields save; Finance_Cleared_Date__c auto-stamped |
| **Priority** | High |

### TC-OUT-056: Exception tracking
| Field | Value |
|-------|-------|
| **Steps** | As ASA user: set Exception_Type__c = Visa Delay; set Withdrawal_Flag__c = true; set Withdrawal_Date__c |
| **Expected Result** | All exception fields save without error |
| **Priority** | Medium |

---

## Section 11 — Data Quality & Edge Cases — 6 Test Cases

### TC-OUT-057: Outgoing and Incoming Cases coexist for same Contact
| Field | Value |
|-------|-------|
| **Precondition** | A Contact has both an Incoming Exchange and an Outgoing Exchange Case |
| **Steps** | Verify both cases exist; update the Incoming Case |
| **Expected Result** | Cases independent; OutgoingExchangeCaseHandler does not fire on Incoming Case update; IncomingExchangeCaseHandler does not fire on Outgoing Case update |
| **Priority** | High |

### TC-OUT-058: Clearance auto-stamp fires only for Outgoing_Exchange RT
| Field | Value |
|-------|-------|
| **Precondition** | A General Support Case has ASA_SA_Cleared__c field (shared Case field) |
| **Steps** | Set ASA_SA_Cleared__c = true on General Support Case |
| **Expected Result** | Apex clearance stamping does NOT apply on General Support case; no clearance By/Date auto-stamp occurs because logic is scoped to Incoming/Outgoing exchange record types only |
| **Priority** | High |

### TC-OUT-059: Bulk update — 200 Outgoing Cases trigger handled
| Field | Value |
|-------|-------|
| **Steps** | Via DataLoader, update 200 Outgoing Exchange Cases with all gates met |
| **Expected Result** | All 200 cases transition stages without governor limit errors |
| **Priority** | High |

### TC-OUT-060: Exchange_School_Cohort__c both lookups required
| Field | Value |
|-------|-------|
| **Steps** | Create Exchange_School_Cohort__c without Academic_Term__c |
| **Expected Result** | Required field error |
| **Priority** | Medium |

### TC-OUT-061: Case Status does not show new outgoing values on General Support RT
| Field | Value |
|-------|-------|
| **Steps** | Create a General Support Case; inspect Status picklist |
| **Expected Result** | "ASA In Progress", "RO Review", "Transcript Check", "Student Credit Check" do NOT appear (Business Process filtering ensures they're Outgoing Exchange only) |
| **Priority** | High |

### TC-OUT-062: V-OUT-03 (inactive) — no runtime error
| Field | Value |
|-------|-------|
| **Steps** | Create a second Outgoing Exchange Case for the same Contact |
| **Expected Result** | Case creates without validation error (V-OUT-03 is inactive — duplicate guard not enforced until Phase 4) |
| **Priority** | Medium |

---

## Test Execution Tracker

| Section | Total Cases | Passed | Failed | Blocked | Not Run |
|---------|-------------|--------|--------|---------|---------|
| 1. Case Creation & RT | 5 | | | | |
| 2. Gate 1 (→ RO Review) | 8 | | | | |
| 3. Gate 2 (→ Transcript Check) | 4 | | | | |
| 4. Gate 3 (→ Student Credit Check) | 5 | | | | |
| 5. Gate 4 (→ Closed) | 5 | | | | |
| 6. Exit Date Validation | 3 | | | | |
| 7. Custom Objects | 7 | | | | |
| 8. Permission Sets & Access | 10 | | | | |
| 9. Student Portal LWC | 6 | | | | |
| 10. End-to-End Lifecycle | 3 | | | | |
| 11. Data Quality & Edge Cases | 6 | | | | |
| **TOTAL** | **62** | | | | |

---

## Integration Test Cases (Phase 4 — Parked, to be added when unparked)

The following test sections will be added when INT-05, INT-06, INT-07 are built:

| Section | # Planned | Covers |
|---------|-----------|--------|
| INT-05: Registro Sync | ~8 | Case creation, PGID resolve, course bulk insert, duplicate guard, error handling |
| INT-06: LMS Status Push | ~4 | Status payload, callout mock, failure non-rollback |
| INT-07: Exchange School Sync | ~4 | Account upsert, cohort creation, partial success |

---

## Defect Severity Guidelines

| Severity | Definition | Example |
|----------|-----------|---------|
| **Critical** | Core process broken; no workaround | Stage auto-transition not firing; V-OUT-07 not blocking reopening |
| **High** | Feature not working but workaround exists | Clearance auto-stamp not populating (can be set manually) |
| **Medium** | Minor UI/cosmetic or edge case | Portal LWC doesn't show empty state message |
| **Low** | Enhancement suggestion | "Would be nice if..." |

---

*Test Cases Document | ISB-6099 Outgoing Exchange | 17-Jun-2026 | 62 Test Cases*
