# ISB-6099 Outgoing Exchange Module — Combined Summary

**Epic**: ISB-6081 — International Exchange Students Module  
**Parent Story**: ISB-6099 — International Exchange - Outgoing Students  
**Platform**: Salesforce Education Cloud — Org B (ISB Success Portal)  
**Date**: 17-Jun-2026  
**Status**: Development Complete — Ready for Deployment & UAT

---

## 1. Executive Overview

The Outgoing Exchange module manages the complete lifecycle of ISB students going to partner universities — from Registro API sync (auto-creating the Case) through Registrar Office closure after transcript and credit check. It covers 4 workflow stages, 2 new custom objects, 33 new Case fields, 5 validation rules, 3 automation flows, and 4 persona-based permission sets.

**Key Capabilities Delivered:**
- Registro API-driven Case creation (no manual ASA upload — outgoing is system-initiated)
- `Exchange_Course__c` object linked to ProgramEnrollment — tracks partner university course enrollment, grades, and credit mapping
- `Exchange_School_Cohort__c` junction object linking Partner University (Account) to AcademicTerm for cohort management
- 4-stage workflow with Apex-enforced auto-transitions: ASA In Progress → RO Review → Transcript Check → Student Credit Check → Closed
- Clearance auto-stamping is now handled in Apex (`CaseTriggerHandler.stampExchangeDepartmentClearance`) for all 5 department flags
- Transcript dispatch and partner transcript receipt auto-stamp flows
- Graduation audit gate before case closure
- 6 validation rules enforcing stage gates, finance clearance, exit dates, and no-reopening
- Role-based access control via 4 dedicated permission sets
- Student portal LWC (`outgoingExchangePortalTab`) exposing exchange school, terms, and course details (read-only)

---

## 2. Ticket Coverage

| # | Story | Ticket | Phase | Status |
|---|-------|--------|-------|--------|
| 1 | International Exchange - Outgoing (Parent) | ISB-6099 | — | ✅ Built |
| 2 | Custom Objects (Exchange Course, School Cohort) | ISB-6099 | Phase 1 | ✅ Built |
| 3 | New Case Fields (33 fields) | ISB-6099 | Phase 2 | ✅ Built |
| 4 | Outgoing Exchange Record Type + Business Process | ISB-6099 | Phase 3 | ✅ Built |
| 5 | Registro Integration (INT-05) | ISB-6099 | Phase 4 | ⏸ Parked |
| 6 | LMS Status Push (INT-06) | ISB-6099 | Phase 4 | ⏸ Parked |
| 7 | Exchange School Sync (INT-07) | ISB-6099 | Phase 4 | ⏸ Parked |
| 8 | OutgoingExchangeCaseHandler.cls (Stage Auto-Transitions) | ISB-6099 | Phase 5 | ✅ Built |
| 9 | OutgoingExchangePortalController.cls | ISB-6099 | Phase 5 | ✅ Built |
| 10 | CaseTrigger modification (1 line) | ISB-6099 | Phase 6b | ✅ Built |
| 11 | Outgoing Clearance AutoStamp Flow | ISB-6099 | Phase 6 | ✅ Built |
| 12 | Outgoing Transcript Dispatch Stamp Flow | ISB-6099 | Phase 6 | ✅ Built |
| 13 | Outgoing Case Closure Flow | ISB-6099 | Phase 6 | ✅ Built |
| 14 | Validation Rules (V_OUT_04 to V_OUT_10) | ISB-6099 | Phase 7 | ✅ Built |
| 15 | Page Layout (Case-Outgoing Exchange) | ISB-6099 | Phase 8 | ⏸ Parked |
| 16 | FlexiPage (Outgoing_Exchange_Case_Record_Page) | ISB-6099 | Phase 9 | ⏸ Parked |
| 17 | Permission Sets (4: ASA, RO, Finance, ProgramOffice) | ISB-6099 | Phase 10 | ✅ Built |
| 18 | Student Portal LWC (outgoingExchangePortalTab) | ISB-6099 | Phase 11 | ✅ Built |

---

## 3. Personas & Access Control

| Persona | Permission Set | Key Access |
|---------|----------------|------------|
| ASA Student Affairs | `Outgoing_Exchange_ASA` | Owns exit date fields, clearance flags, exception/withdrawal, nomination fields; Custom Permission `Outgoing_Exchange_ASA_User` |
| Registrar Office (RO) | `Outgoing_Exchange_RO` | Full Case + Exchange_Course__c CRUD; owns transcript, grading scale, graduation audit, case closure |
| Finance | `Outgoing_Exchange_Finance` | Case edit for Finance section only: refund type, amounts, Finance_Cleared__c |
| Program Office | `Outgoing_Exchange_ProgramOffice` | Read-only on Case, Exchange_Course__c, Contact, ProgramEnrollment |
| Outgoing Student | Experience Cloud Portal | Read-only view via `outgoingExchangePortalTab` LWC — exchange school, terms, course details |

---

## 4. Object & Data Model Summary

### New Custom Objects

| Object | Relationship | Purpose |
|--------|-------------|---------|
| `Exchange_Course__c` | Lookup → ProgramEnrollment (required, Restrict delete) | Tracks partner university courses, credits, grades per student exchange |
| `Exchange_School_Cohort__c` | Lookup → Account + Lookup → AcademicTerm (both required, Restrict delete) | Junction linking partner university to an academic term cohort |

### Modified Standard Objects

| Object | New Fields | Existing Fields Reused |
|--------|-----------|----------------------|
| Case | 33 new | `Finance_Cleared__c`, `ASA_SA_Cleared__c`, `Operations_Cleared__c`, `IT_Cleared__c`, `LRC_Cleared__c`, `Transcript_Dispatched__c`, `Dispatch_Date__c`, `Dispatched_By__c`, `Closed_Date__c`, `From_Term__c`, `To_Term__c` |
| ProgramEnrollment | 1 new (`Letter_Grade__c`) | `Sub_Status__c` (existing — Outgoing value already present) |
| CaseStatus (StandardValueSet) | 4 new values added | All existing 34 values preserved |

### Case Record Type — `Outgoing_Exchange`
- **Business Process**: "Outgoing Exchange" — 5 stages
- **Stages**: ASA In Progress (default) → RO Review → Transcript Check → Student Credit Check → Closed

---

## 5. Workflow Stages & Auto-Transitions

| From Stage | To Stage | Gate Condition | Enforced By |
|-----------|---------|---------------|------------|
| ASA In Progress | RO Review | `Finance_Cleared__c = 'Cleared'` AND all 5 dept flags true | `OutgoingExchangeCaseHandler` (Apex trigger) |
| RO Review | Transcript Check | `Partner_Transcript_Received__c` flips to true | `OutgoingExchangeCaseHandler` (Apex trigger) |
| Transcript Check | Student Credit Check | `Grading_Scale_Uploaded__c = true` AND `Course_Confirmation_Form__c = true` | `OutgoingExchangeCaseHandler` (Apex trigger) |
| Student Credit Check | Closed | `Ready_for_Graduation_Audit__c` flips to true; also stamps `Closed_Date__c` | `OutgoingExchangeCaseHandler` (Apex trigger) |

---

## 6. Validation Rules (5 Active + 1 Inactive)

| Rule ID | API Name | Purpose | Status |
|---------|----------|---------|--------|
| V-OUT-03 | `V_OUT_03_One_Active_Case` | Duplicate Case guard (one active Outgoing case per student) | **Inactive** — EXISTS() not supported in VR formula; enforced in INT-05 (Phase 4, parked) |
| V-OUT-04 | `V_OUT_04_Partner_Transcript_Gate` | Partner transcript required before Student Credit Check | Active |
| V-OUT-05 | `V_OUT_05_Finance_Gate` | Finance must be Cleared past ASA In Progress | Active |
| V-OUT-06 | `V_OUT_06_Exit_Dates_Required` | Planned + Confirmed Exit Dates mandatory past ASA In Progress | Active |
| V-OUT-07 | `V_OUT_07_No_Reopening` | Closed Outgoing Exchange Cases cannot be reopened | Active |
| V-OUT-10 | `V_OUT_10_Exchange_School_Required` | Exchange School Partner (Account) is mandatory | Active |

---

## 7. Automation (Flows — 3 New)

| Flow | Type | Trigger | Purpose |
|------|------|---------|---------|
| `Outgoing_Clearance_AutoStamp_Flow` | Record-Triggered (Before Save) | Any clearance flag flips to true on Outgoing_Exchange Case | Superseded by Apex stamping in `CaseTriggerHandler`; deactivate to avoid dual ownership |
| `Outgoing_Transcript_Dispatch_Stamp_Flow` | Record-Triggered (Before Save) | `Transcript_Dispatched__c` or `Partner_Transcript_Received__c` flips to true | Stamps `Dispatch_Date__c` + `Dispatched_By__c`; stamps `Partner_Transcript_Upload_Date__c` |
| `Outgoing_Case_Closure_Flow` | Record-Triggered (After Save) | Status changes to Closed on Outgoing_Exchange Case | Sends closure notification email to Case Owner |

---

## 8. Integrations

| Integration | Direction | Component | Status |
|-------------|-----------|-----------|--------|
| INT-05: Registro → Salesforce (Student sync) | Registro → SF | `OutgoingExchangeRegistroIntegration.cls` — `@RestResource /v1/outgoing-exchange-sync` | ⏸ Parked (Phase 4) |
| INT-06: Salesforce → LMS (Status push) | SF → LMS | `OutgoingExchangeLMSStatusPush.cls` — `@future(callout=true)` via `callout:LMS_Endpoint` | ⏸ Parked (Phase 4) |
| INT-07: Registro → Salesforce (Exchange School sync) | Registro → SF | `ExchangeSchoolSyncIntegration.cls` — `@RestResource /v1/exchange-school-sync` | ⏸ Parked (Phase 4) |

---

## 9. Implementation Architecture

| Category | New Files | Modified Existing Files |
|----------|-----------|------------------------|
| Apex Classes | 3 new | 0 |
| Apex Triggers | 0 new | 1 modified (CaseTrigger — 1 line added) |
| Custom Objects | 2 new | 0 |
| Case Fields | 33 new | 0 |
| PE Fields | 1 new | 0 |
| StandardValueSet | 0 new | 1 modified (CaseStatus — 4 values added) |
| Record Type + Business Process | 2 new | 0 |
| Custom Permission | 1 new | 0 |
| Validation Rules | 6 new (1 inactive) | 0 |
| Flows | 3 new | 0 |
| Permission Sets | 4 new | 0 |
| LWC | 1 new (4 files) | 0 |
| Deployment Manifest | 1 new | 0 |
| **Total** | **~57 new** | **1 modified** |

### New Apex Classes:
- `OutgoingExchangeCaseHandler.cls` — stage auto-transitions via CaseTrigger
- `OutgoingExchangePortalController.cls` — `@AuraEnabled` methods for portal LWC
- `OutgoingExchangeCaseHandlerTest.cls` — unit tests for all 4 stage transitions

### Modified Existing:
- `CaseTrigger.trigger` — added `OutgoingExchangeCaseHandler.handleBeforeUpdate()` call in `isBefore && isUpdate` block

---

## 10. Open Items / Parked Work

| # | Open Item | Blocks | Owner |
|---|-----------|--------|-------|
| OI-OUT-01 | INT-05: Registro API authentication for outgoing sync | Phase 4 full deployment | Registro Team |
| OI-OUT-02 | INT-06: LMS exchange status push payload confirmation | Phase 4 | LMS Team |
| OI-OUT-03 | INT-07: Exchange school sync endpoint spec | Phase 4 | Registro Team |
| OI-OUT-04 | Page Layout (Case-Outgoing Exchange) | Phase 8 — parked pending field confirmation + UAT | ISB/Gurpreet |
| OI-OUT-05 | FlexiPage assignment for Outgoing Exchange RT | Phase 9 — parked (depends on Phase 8) | ISB |
| OI-OUT-06 | V-OUT-03 duplicate case guard (active enforcement) | Currently inactive; activate after INT-05 built | Dev Team |
| OI-OUT-07 | `Total_Refund_Amount__c` — formula vs. manual entry | Finance sign-off needed | Gurpreet/Finance |
| OI-OUT-08 | `Refund_Type__c` picklist values confirmation | Finance sign-off needed | Gurpreet/Finance |

---

## 11. Pre-Deployment Manual Steps (DEVSLCM)

Before running the deployment, verify in DEVSLCM org:
1. **Case Status values** — `ASA In Progress`, `RO Review`, `Transcript Check`, `Student Credit Check` are added via `CaseStatus` StandardValueSet (included in package).
2. **Named Credential** — `callout:LMS_Endpoint` exists (used by parked INT-06; verify it exists from Incoming Exchange sprint).
3. **Custom Permission** — `Outgoing_Exchange_ASA_User` deploys via package (included as `CustomPermission` metadata type).

---

## 12. Deployment Command

```bash
sfdx force:source:deploy -x manifest/outgoing_exchange_package.xml -l NoTestRun
# For production (with tests):
sfdx force:source:deploy -x manifest/outgoing_exchange_package.xml --testlevel RunSpecifiedTests --runtests OutgoingExchangeCaseHandlerTest
```

**Validated (check-only):** 70/70 components, 0 errors — 2026-06-17

---

*Generated: 17-Jun-2026 | Module: ISB-6099 Outgoing Exchange*
