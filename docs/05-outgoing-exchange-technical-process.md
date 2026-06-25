# ISB-6099 Outgoing Exchange — Technical Process Document

**Module**: International Exchange — Outgoing Students  
**Platform**: Salesforce Education Cloud (Org B)  
**API Version**: 62.0  
**Date**: 17-Jun-2026

---

## 1. End-to-End Process Flow

```
┌────────────────────────────────────────────────────────────────────────┐
│                    OUTGOING EXCHANGE LIFECYCLE                          │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  ┌──────────────┐    ┌──────────────┐    ┌────────────────────────┐   │
│  │   Registro    │───▶│  SF REST API │───▶│  Case Created          │  │
│  │  API Sync     │    │  INT-05      │    │  RT = Outgoing_Exchange │  │
│  │  (⏸ Parked)  │    │  (⏸ Parked) │    │  Status = ASA In Prog. │   │
│  └──────────────┘    └──────────────┘    └────────────────────────┘   │
│                                                  │                     │
│               ┌──────────────────────────────────┘                    │
│               ▼                                                        │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │                OUTGOING CASE LIFECYCLE                           │  │
│  │                                                                  │  │
│  │  ASA In Progress ──▶ RO Review ──▶ Transcript Check             │  │
│  │        ──▶ Student Credit Check ──▶ Closed                      │  │
│  │                                                                  │  │
│  │  Gate 1 (→ RO Review):      Finance_Cleared = Cleared            │  │
│  │                             + ALL 5 dept clearance flags = true  │  │
│  │                                                                  │  │
│  │  Gate 2 (→ Transcript Chk): Partner_Transcript_Received → true   │  │
│  │                                                                  │  │
│  │  Gate 3 (→ Credit Check):   Grading_Scale_Uploaded = true        │  │
│  │                             + Course_Confirmation_Form = true    │  │
│  │                                                                  │  │
│  │  Gate 4 (→ Closed):         Ready_for_Graduation_Audit → true    │  │
│  │                             → stamps Closed_Date__c              │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Component Architecture

### 2.1 Apex Layer

```
┌────────────────────────────────────────────────────────────┐
│ TRIGGER LAYER (Single trigger per object)                   │
├────────────────────────────────────────────────────────────┤
│ CaseTrigger.trigger (modified — 1 line added)               │
│   └─▶ CaseTriggerHandler.stampExchangeDepartmentClearance()  │
│   └─▶ CaseTriggerHandler.ensureGeneralSupportRejectedOwner()│
│   └─▶ IncomingExchangeCaseHandler.handleBeforeUpdate() [EX] │
│   └─▶ OutgoingExchangeCaseHandler.handleBeforeUpdate() [NEW]│
│   └─▶ CaseTriggerHandler.handleAfterUpdate()                │
│   └─▶ CaseTriggerHandler.handleStatusChange()               │
│   └─▶ CaseTriggerHandler.createGraduationEligibilityOnCase()│
└────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────┐
│ SERVICE LAYER                                               │
├────────────────────────────────────────────────────────────┤
│ OutgoingExchangeCaseHandler.cls                             │
│   ├── OUTGOING_EXCHANGE_RT_ID (static constant)             │
│   └── handleBeforeUpdate(newCases, oldMap)                  │
│         ├── Gate 1: ASA In Progress → RO Review             │
│         ├── Gate 2: RO Review → Transcript Check            │
│         ├── Gate 3: Transcript Check → Student Credit Check │
│         └── Gate 4: Student Credit Check → Closed           │
│                      + stamps Closed_Date__c                │
│                                                             │
│ OutgoingExchangePortalController.cls                        │
│   ├── @AuraEnabled(cacheable=true)                          │
│   │   getExchangeCourses(programEnrollmentId)               │
│   │   → List<Exchange_Course__c>                            │
│   └── @AuraEnabled(cacheable=true)                          │
│       getOutgoingCaseForContact(contactId)                  │
│       → Case (Outgoing_Exchange RT, Status != Closed)       │
└────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────┐
│ INTEGRATION LAYER (⏸ PARKED — Phase 4)                     │
├────────────────────────────────────────────────────────────┤
│ OutgoingExchangeRegistroIntegration.cls (to be built)       │
│   └── @RestResource /v1/outgoing-exchange-sync              │
│       @HttpPost syncOutgoingStudents()                      │
│                                                             │
│ OutgoingExchangeLMSStatusPush.cls (to be built)             │
│   └── @future(callout=true) pushStatus(contactId)           │
│       POST to callout:LMS_Endpoint/exchange-status          │
│                                                             │
│ ExchangeSchoolSyncIntegration.cls (to be built)             │
│   └── @RestResource /v1/exchange-school-sync                │
│       @HttpPost syncExchangeSchools()                       │
└────────────────────────────────────────────────────────────┘
```

### 2.2 Data Model

```
Account (Partner University)
  │
  ├── Exchange_School_Cohort__c ──▶ AcademicTerm
  │   (Lookup, Restrict delete)     (Lookup, Restrict delete)
  │
  └── Case (Outgoing_Exchange RT)
        │  └── Exchange_School_Partner__c (Lookup to Account)
        │
        └── ProgramEnrollment (linked via ContactId → Contact)
              │
              └── Exchange_Course__c
                    (Lookup → ProgramEnrollment, required, Restrict delete)
                    Fields: Course_Code__c, Course_Name__c,
                            Partner_Credits__c, Contact_Hours__c,
                            ISB_Credits__c, Partner_Grade__c,
                            Letter_Grade__c, Status__c
```

**Relationship note:** `Exchange_Course__c` links to `ProgramEnrollment` (not Case directly). Reporting traversal: `Exchange_Course__c → ProgramEnrollment → Case`.

### 2.3 LWC Layer

```
outgoingExchangePortalTab/
├── outgoingExchangePortalTab.html   (exchange school, terms, courses datatable)
├── outgoingExchangePortalTab.js     (@wire getRecord + getExchangeCourses)
├── outgoingExchangePortalTab.css
└── outgoingExchangePortalTab.js-meta.xml
    targets: lightningCommunity__Page, lightningCommunity__Default

Student Portal View (read-only):
  ├── Exchange School Name + Coordinator Name/Email
  ├── From Term / To Term (existing Case fields)
  ├── Case Status badge
  ├── Exchange Courses datatable:
  │     Course Name | Code | Contact Hours | ISB Credits | Status
  └── Transcript dispatch notification (when Transcript_Dispatched__c = true)

Hidden from student: Finance section, Clearance flags, Graduation Audit notes,
                     Dispatch_Notes__c, Exception/Withdrawal fields
```

### 2.4 Flow Layer

```
┌─────────────────────────────────────────────────────────────────┐
│ RECORD-TRIGGERED FLOWS (on Case — Before Save)                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Outgoing_Clearance_AutoStamp_Flow                               │
│     Superseded by Apex (`CaseTriggerHandler.stampExchangeDepartmentClearance`) │
│     Recommendation: Deactivate to avoid duplicate ownership        │
│                                                                  │
│  Outgoing_Transcript_Dispatch_Stamp_Flow                         │
│     Filter: RecordType.DeveloperName = 'Outgoing_Exchange'       │
│     └── Transcript_Dispatched__c → true                          │
│           → Stamp Dispatch_Date__c, Dispatched_By__c             │
│     └── Partner_Transcript_Received__c → true                    │
│           → Stamp Partner_Transcript_Upload_Date__c              │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│ RECORD-TRIGGERED FLOW (on Case — After Save)                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Outgoing_Case_Closure_Flow                                      │
│     Filter: RecordType.DeveloperName = 'Outgoing_Exchange'       │
│             AND Status changed to 'Closed'                       │
│     └── Send closure notification email to Case Owner            │
│         Subject: "Outgoing Exchange Case Closed: {CaseNumber}"   │
│         Body: "The Outgoing Exchange case for {Student} has been  │
│                closed."                                          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Detailed Process Steps

### Step 1 — Registro Sync → Case Creation (INT-05 — Parked)

**Actor**: System (Registro calls Salesforce)  
**Component**: `OutgoingExchangeRegistroIntegration.cls` (to be built in Phase 4)

**Process (design complete, implementation parked):**
1. Registro POST to `/services/apexrest/v1/outgoing-exchange-sync`
2. Payload: student PGID, school code/name, coordinator, dates, exchange details, courses array
3. Resolve PGID → ProgramEnrollment → Contact (bulk query)
4. Upsert Account by `School_Code__c` External ID (INT-07 inline)
5. V-OUT-03 duplicate guard: query existing open Outgoing Exchange Case for Contact
6. Create Case: RT = Outgoing_Exchange, Status = ASA In Progress, all Registro fields pre-filled
7. Create Exchange_Course__c records (bulk insert) linked to ProgramEnrollment
8. Enqueue `OutgoingExchangeLMSStatusPush.pushStatus()` via `@future(callout=true)`
9. Return `List<ResultResponse>` per student

---

### Step 2 — ASA In Progress Stage

**Actor**: ASA Student Affairs (Manual updates)  
**Component**: Case fields, `CaseTriggerHandler.stampExchangeDepartmentClearance`

**Process:**
1. ASA reviews auto-populated Case (from Registro sync) — Exchange School, Coordinator, Dates, Exchange Details, Nomination/Visa/Loan flags
2. ASA verifies and updates Exit Date fields: `Planned_Exit_Date__c`, `Confirmed_Exit_Date__c`
3. V-OUT-10: Exchange_School_Partner__c must be populated (always true from Registro sync)
4. V-OUT-06: Planned + Confirmed Exit Dates required to advance past this stage
5. Department clearance flags updated by respective teams; each flag flip auto-stamps date/by
6. Finance team sets `Finance_Cleared__c` = Cleared
7. **Auto-transition to RO Review** (OutgoingExchangeCaseHandler): fires when ALL conditions true:
   - `Finance_Cleared__c = 'Cleared'`
   - `ASA_SA_Cleared__c = true`
   - `Operations_Cleared__c = true`
   - `IT_Cleared__c = true`
   - `LRC_Cleared__c = true`

---

### Step 3 — RO Review Stage

**Actor**: Registrar Office  
**Component**: Case fields

**Process:**
1. RO receives partner transcript from the exchange university
2. RO checks `Partner_Transcript_Received__c` = true
3. `Outgoing_Transcript_Dispatch_Stamp_Flow` auto-stamps `Partner_Transcript_Upload_Date__c`
4. V-OUT-04 (gate): Student Credit Check is blocked without Partner Transcript
5. **Auto-transition to Transcript Check** (OutgoingExchangeCaseHandler): fires when `Partner_Transcript_Received__c` flips to true

---

### Step 4 — Transcript Check Stage

**Actor**: Registrar Office  
**Component**: Case fields, Exchange_Course__c records

**Process:**
1. RO uploads the grading scale document: checks `Grading_Scale_Uploaded__c` = true
2. RO confirms course confirmation form received: checks `Course_Confirmation_Form__c` = true
3. RO maps partner university grades to ISB Letter Grades on Exchange_Course__c records
4. RO optionally adds `Dispatch_Notes__c` for transcript handling notes
5. RO checks `Transcript_Dispatched__c` when ISB transcript is sent to partner university
6. **Auto-transition to Student Credit Check** (OutgoingExchangeCaseHandler): fires when BOTH:
   - `Grading_Scale_Uploaded__c = true`
   - `Course_Confirmation_Form__c = true`

---

### Step 5 — Student Credit Check Stage

**Actor**: Registrar Office  
**Component**: Case fields, Exchange_Course__c records

**Process:**
1. RO conducts graduation audit — verifies ISB credits for exchange courses
2. RO sets `ISB_Credits__c` on each `Exchange_Course__c` record
3. RO sets `Graduation_Audit_Date__c` and adds `Graduation_Audit_Notes__c`
4. RO marks `Ready_for_Graduation_Audit__c` = true when credit check is complete
5. **Auto-transition to Closed** (OutgoingExchangeCaseHandler): fires when `Ready_for_Graduation_Audit__c` flips to true
   - Also stamps `Closed_Date__c = System.now()`
6. `Outgoing_Case_Closure_Flow` (After Save) sends closure notification to Case Owner

---

### Step 6 — Case Closure

**Actor**: System (Automatic via trigger)  
**Component**: `OutgoingExchangeCaseHandler`, `Outgoing_Case_Closure_Flow`

**Process:**
1. Stage = Closed set automatically in Step 5
2. `Closed_Date__c` stamped by trigger handler (Before Update fires before After Save flow)
3. Closure notification email sent to Case Owner by `Outgoing_Case_Closure_Flow`
4. V-OUT-07: permanently blocks any Status change from Closed (no reopening)
5. `ProgramEnrollment.Sub_Status__c` should be updated to reflect completion (via INT-05 when unparked)

---

## 4. Stage Gate Summary

| Stage | Gate Condition | Enforcement |
|-------|---------------|-------------|
| → RO Review | Finance_Cleared = Cleared + all 5 dept flags | OutgoingExchangeCaseHandler (trigger) auto-transitions |
| → Transcript Check | Partner_Transcript_Received flips to true | OutgoingExchangeCaseHandler (trigger) auto-transitions |
| → Student Credit Check | Grading_Scale_Uploaded = true AND Course_Confirmation_Form = true | OutgoingExchangeCaseHandler (trigger) auto-transitions |
| → Closed | Ready_for_Graduation_Audit flips to true | OutgoingExchangeCaseHandler (trigger) auto-transitions + stamps Closed_Date__c |
| V-OUT-04 (Validation) | Student Credit Check requires Partner Transcript | Fires if status = Student Credit Check and Partner_Transcript_Received = false |
| V-OUT-05 (Validation) | Finance gate | Blocks if status not ASA In Progress and Finance_Cleared != Cleared |
| V-OUT-06 (Validation) | Exit dates required | Blocks if status != ASA In Progress and exit dates blank |
| V-OUT-07 (Validation) | No reopening | Blocks if old status = Closed and new status != Closed |

---

## 5. Integration Endpoints (Phase 4 — Design Complete, Implementation Parked)

| Endpoint | URL | Method | Direction | Notes |
|----------|-----|--------|-----------|-------|
| Outgoing Student Sync (INT-05) | `/services/apexrest/v1/outgoing-exchange-sync` | POST | Registro → SF | Creates Case + Exchange_Course__c records |
| LMS Status Push (INT-06) | `callout:LMS_Endpoint/exchange-status` | POST | SF → LMS | Async @future; status-only (no course mapping) |
| Exchange School Sync (INT-07) | `/services/apexrest/v1/exchange-school-sync` | POST | Registro → SF | Upserts Account + Exchange_School_Cohort__c |

---

## 6. Error Handling Strategy

| Scenario | Handling |
|----------|----------|
| Stage auto-transition gate not met | Handler skips transition; no error — user manually drives the field update to meet the gate |
| V-OUT-03 (duplicate case) | Currently inactive; will be enforced in INT-05 integration handler (Phase 4) |
| Lookup delete constraint | Parent record deletion blocked (Restrict) if Exchange_Course__c or Exchange_School_Cohort__c child records exist |
| Clearance stamp failure | Stamps are now in Apex before-update logic; if trigger context fails, save is blocked and DML rollback occurs |
| Closure notification email failure | After Save flow failure does not roll back the closure (email is best-effort) |
| Validation rule blocks save | Standard Salesforce VR error message displayed to user; no partial save |

---

## 7. Security Considerations

- **CRUD/FLS**: All Apex classes use `with sharing`; FLS enforced via Permission Sets
- **No hard-coded IDs**: Record Type resolved by DeveloperName (`'Outgoing_Exchange'`); no org-specific IDs in code
- **Lookup Restrict delete**: Parent ProgramEnrollment and Account cannot be deleted while Exchange_Course__c / Exchange_School_Cohort__c children exist
- **Custom Permission gate**: `Outgoing_Exchange_ASA_User` custom permission controls ASA-specific actions (referenced in permission set; future validation rule enforcement once unparked)
- **Record locking**: V-OUT-07 prevents any Status change from Closed on Outgoing Exchange Cases
- **Portal LWC**: Student sees only read-only fields — Finance, Clearance, Audit, Notes sections excluded from LWC rendering

---

## 8. Deployment Sequence

The `outgoing_exchange_package.xml` deploys components in this logical order (Salesforce SOAP API handles sequencing within a deployment; the package type ordering assists):

1. `StandardValueSet` (CaseStatus) — adds 4 new Status values
2. `CustomObject` — deploys Exchange_Course__c + Exchange_School_Cohort__c
3. `CustomField` — deploys all new fields (Case, ProgramEnrollment, Exchange objects)
4. `BusinessProcess` (Case.Outgoing Exchange) — requires Status values to exist
5. `CustomPermission` — Outgoing_Exchange_ASA_User
6. `RecordType` (Case.Outgoing_Exchange) — requires BusinessProcess
7. `ApexClass` — OutgoingExchangeCaseHandler, OutgoingExchangePortalController, Test
8. `ApexTrigger` (CaseTrigger) — requires Apex class to compile
9. `Flow` — 3 outgoing flows
10. `ValidationRule` — 6 rules (1 inactive)
11. `PermissionSet` — 4 permission sets (requires objects/fields/classes/customPermission deployed first)
12. `LightningComponentBundle` — outgoingExchangePortalTab (requires Apex controller)

---

*Technical Process Document | ISB-6099 Outgoing Exchange | 17-Jun-2026*
