# ISB-6082 Incoming Exchange — UAT Test Cases (Updated Lifecycle)

**Module**: International Exchange — Incoming Students  
**Test Phase**: UAT (Delta + Regression)  
**Platform**: Salesforce Education Cloud — Org B  
**Date**: 24-Jun-2026

---

## 1. Scope of This Update

These cases validate the newly implemented flow and owner-routing behavior for incoming exchange exit clearance.

---

## 2. Lifecycle & Owner Routing (Critical)

### TC-INC-NEW-001: Auto-create case with new initial status
| Field | Value |
|-------|-------|
| **Precondition** | Incoming ProgramEnrollment has `PGID__c` populated |
| **Steps** | Let `Incoming_Case_AutoCreate_Flow` execute |
| **Expected Result** | Case created with RT = Incoming Exchange Exit Clearance and `Status = Exit Case Initiated` |
| **Priority** | Critical |

### TC-INC-NEW-002: Owner assigned from ASA Case Team role
| Field | Value |
|-------|-------|
| **Precondition** | Incoming Team case team template has an active user for role `Student Affairs` |
| **Steps** | Create qualifying PE and inspect Case owner |
| **Expected Result** | `OwnerId` matches the template member configured for role `Student Affairs` |
| **Priority** | Critical |

### TC-INC-NEW-003: Exchange school mapped from ProgramEnrollment
| Field | Value |
|-------|-------|
| **Precondition** | PE has `Exchange_School__c` lookup to Account |
| **Steps** | Trigger case creation |
| **Expected Result** | `Case.Exchange_School_Home__c` equals source Account Name |
| **Priority** | High |

### TC-INC-NEW-004: Exit date prefilled from check-out
| Field | Value |
|-------|-------|
| **Precondition** | PE has `Check_Out_Date__c` |
| **Steps** | Trigger case creation |
| **Expected Result** | `Case.Expected_Exit_Date__c = PE.Check_Out_Date__c` |
| **Priority** | High |

### TC-INC-NEW-005: Stage 1 transition
| Field | Value |
|-------|-------|
| **Precondition** | Case in `Exit Case Initiated` |
| **Steps** | Set `Operations_Cleared__c = true`, `IT_Cleared__c = true`, `LRC_Cleared__c = true` |
| **Expected Result** | Status auto changes to `Finance Processing` |
| **Priority** | Critical |

### TC-INC-NEW-005A: Simultaneous department clearances stamp all fields
| Field | Value |
|-------|-------|
| **Precondition** | Case in `Exit Case Initiated`; all department cleared flags are currently false |
| **Steps** | In a single edit, set `Operations_Cleared__c`, `IT_Cleared__c`, and `LRC_Cleared__c` to true, then save |
| **Expected Result** | All 3 pairs are stamped in one transaction: `Operations_Cleared_By__c/Date__c`, `IT_Cleared_By__c/Date__c`, `LRC_Cleared_By__c/Date__c`; status transitions to `Finance Processing` |
| **Priority** | Critical |

### TC-INC-NEW-005B: Incoming upload gender mapping to SAP code
| Field | Value |
|-------|-------|
| **Precondition** | Incoming upload file includes new `Gender` column |
| **Steps** | Upload three rows with `Gender` values `Male`, `Female`, `Other` |
| **Expected Result** | Contacts are created/updated with `SAP_Gender_Code__c` mapped as Male->1, Female->2, Other->0 |
| **Priority** | Critical |

### TC-INC-NEW-006: Stage 2 transition
| Field | Value |
|-------|-------|
| **Precondition** | Case in `Finance Processing` |
| **Steps** | Set `Finance_Cleared__c = Cleared` |
| **Expected Result** | Status auto changes to `ASA Processing` |
| **Priority** | Critical |

### TC-INC-NEW-007: Stage 3 transition + owner handoff
| Field | Value |
|-------|-------|
| **Precondition** | Case in `ASA Processing`, with Case Team member present for role `RO` |
| **Steps** | Set `ASA_SA_Cleared__c = true` |
| **Expected Result** | Status = `Grades Awaited` and owner changes to Case Team member with role `RO` |
| **Priority** | Critical |

### TC-INC-NEW-008: Grades to transcript processing
| Field | Value |
|-------|-------|
| **Precondition** | Case in `Grades Awaited` with blank CGPA |
| **Steps** | Populate `CGPA__c` |
| **Expected Result** | Status auto changes to `Transcript Processing` |
| **Priority** | Critical |

### TC-INC-NEW-009: Transcript dispatch auto-closes case
| Field | Value |
|-------|-------|
| **Precondition** | Case in `Transcript Processing` |
| **Steps** | Check `Transcript_Dispatched__c` |
| **Expected Result** | Status = `Closed` and `Closed_Date__c` stamped |
| **Priority** | Critical |

---

## 3. Backward Compatibility

### TC-INC-NEW-010: Old cases remain valid
| Field | Value |
|-------|-------|
| **Precondition** | Existing case with legacy status (`Draft`/`Finance Review Incoming`/`Dept Clearance`) |
| **Steps** | Open and save non-status edit |
| **Expected Result** | Record remains editable per existing rules; no forced migration |
| **Priority** | High |

---

## 4. Manifest Sanity

### TC-INC-NEW-011: Deploy package resolves all dependencies
| Field | Value |
|-------|-------|
| **Precondition** | Use `manifest/package_2026_06_24.xml` |
| **Steps** | Perform check-only/manual deployment |
| **Expected Result** | No missing metadata errors for statuses, business process, flow, or class |
| **Priority** | Critical |

---

## 5. Regression Note

Run previously approved incoming UAT suites for upload, PGID generation, Registro sync, transcript stamping, and permission controls after deploying this change.

---

*Test Cases Document | ISB-6082 Incoming Exchange | 24-Jun-2026*
