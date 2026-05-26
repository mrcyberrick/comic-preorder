# Phase 4.1 — Audit Findings

**Parent plan:** `docs/phase-4-production-migration.md`
**Sub-deploy plan:** `docs/phase-4.1-pre-cutover-hardening.md`
**Audit run date:** 2026-05-26
**Audit run by:** Claude Code CLI session

This document captures the pre-cutover audit results for three classes of finding: F16-class (multi-PERMISSIVE OR-policy patterns), F34-class (Edge Function tenant resolution), and Finding E (overly-broad table grants). Per the locked decision gate at the parent-plan level, new findings surfaced during the audit are triaged inline with the user as bundle / defer / out-of-scope.

---

## A. F16-Class Audit — Multi-PERMISSIVE OR-Policy Pattern

**Audit input:** `pg_policies` query result (captured below)
**Audit run:** 2026-05-26
**Scope:** every tenant-scoped table in the staging schema

### A.1 Raw policy inventory

```
[paste pg_policies query output here]
```

### A.2 Per-table findings

| Table | Policies | Multi-PERMISSIVE risk? | Decision |
|---|---|---|---|
| (populated during audit) | | | |

### A.3 Fixes applied

(populated as fixes land)

---

## B. F34-Class Audit — Edge Function Tenant Resolution

**Audit input:** static read of `supabase/functions/*/index.ts`
**Audit run:** 2026-05-26
**Scope:** all 8 Edge Functions

### B.1 Per-function findings

| Function | Writes to tenant-scoped tables? | Where does tenant_id come from? | Reads scoped by tenant? | Risk? | Decision |
|---|---|---|---|---|---|
| approve-customer | | | | | |
| claim-paper-customer | | | | | |
| create-paper-customer | | | | | |
| invite-customer | | | | | |
| notify-customers | | | | | |
| register-customer | | | | | |
| reset-password | | | | | |
| send-my-list | | | | | |

### B.2 Fixes applied

(populated as fixes land)

---

## C. Finding E Audit — Table-Level Grants

**Audit input:** `information_schema.role_table_grants` query result (captured below)
**Audit run:** 2026-05-26
**Scope:** every tenant-scoped table

### C.1 Raw grants inventory

```
[paste role_table_grants query output here]
```

### C.2 Per-table findings

| Table | anon grants | authenticated grants | service_role grants | Tightening decision |
|---|---|---|---|---|
| (populated during audit) | | | | |

### C.3 Fixes applied

(populated as fixes land)

---

## D. DEFINER Function Inventory (F23 input)

**Audit input:** `pg_proc` query result for SECURITY DEFINER functions
**Audit run:** 2026-05-26

```
[paste pg_proc query output here]
```

### D.1 search_path hardening status

| Function | Current proconfig | Action |
|---|---|---|
| (populated during audit) | | |

---

## E. New Findings Surfaced During Audit

(populated as new findings emerge; each one triaged inline with user)

| Finding | Source query/inspection | Triage decision | Notes |
|---|---|---|---|

---

## F. Audit Run Log

Chronological log of audit steps for traceability.

| Time | Step | Result | Notes |
|---|---|---|---|
| 2026-05-26 | P1–P8 pre-flight | All passed (P1 required clean-up: restore phase-4-production-migration.md from committed state; commit phase-4.1-pre-cutover-hardening.md and .gitignore) | config.js isolation rule noted: enforced manually via merge procedure, not via .gitignore; CLAUDE.md doc discrepancy flagged for C15 |
| 2026-05-26 | P7 import-staging.js anchor check | All three lines at expected numbers (671, 515, 532) | No drift from 4.0 |
| 2026-05-26 | P8 baseline row counts | user_profiles=38, preorders=26, subscriptions=3, weekly_shipment=443; founding tenant only | Baseline captured for Session 3 canary teardown verification |
