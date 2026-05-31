# Phase 4.1 — Pre-Cutover Hardening + Canary Tenant Lifecycle

**Status:** Planning — plan written 2026-05-26; **locked 2026-05-26** (three open decisions resolved: 3-day soak, inline stop-and-ask gate, local-only teardown SQL)
**Parent plan:** `docs/phase-4-production-migration.md`
**Branch base:** `staging`
**Branch name:** `feature/4.1-pre-cutover-hardening`
**Estimated duration:** two extended sessions (largest sub-deploy in Phase 4; see § Execution Sequence for split options). Plus a multi-day soak with the canary tenant live before the canary teardown closes the sub-deploy.
**Customer impact:** none (staging-only). Canary tenant data lives on staging during the soak; never on production.

---

## Goal

Close the remaining cross-tenant correctness gaps on staging before the production cutover, and validate the closure under realistic two-tenant conditions by running a canary tenant alongside the founding tenant for the duration of the soak.

The 2026-05-10 hot-fix closed five HIGH findings (F4, F15, F16, F20, F34). 4.1 does three things those fixes did not:

1. **F16-class deep audit** — F16 fixed the `preorders` admin write policies. The same multi-PERMISSIVE OR-policy pattern may exist on other tenant-scoped tables; the 2026-05-10 fix only touched `preorders`. This sub-deploy audits every tenant-scoped table's policy set for the same pattern.
2. **F34-class deep audit** — F34 fixed `invite-customer` and `create-paper-customer`. `register-customer` was intentionally left pinned to `FOUNDING_TENANT_ID`. Every other Edge Function that reads or writes tenant-scoped data needs to be re-audited for similar latent pins, especially functions added since the 2026-05-10 sweep.
3. **Remaining open items** — F17 admin SELECT scoping; Finding E table-level grants on `usage_events` / `user_profiles` / other tenant-scoped tables; `claim_paper_account` SQL function tenant filtering; `upsertShipment` service-role PRH delete cross-tenant scope; `buildCatalogIdMap` catalog lookup cross-tenant scope.

The canary tenant turns dormant bugs into observable bugs. Binary Playwright fixtures answer "does isolation work for this query at this moment?" The canary answers "does isolation hold across a week of mixed traffic from two tenants doing different things?"

The canary is staging-only and torn down before 4.2 starts — production cutover runs against a clean single-tenant staging mirror.

---

## Approach Summary

| Decision | Choice | Rationale |
|---|---|---|
| Audit scope — F16-class | All tenant-scoped tables with multiple PERMISSIVE policies on the same role/action combo | F16's pattern is OR-permissive policies, not specific to `preorders`. The audit lists every policy set; the fix consolidates any matching pattern |
| Audit scope — F34-class | All 8 Edge Functions, including the 5 already updated in Phase 2 | Re-audit catches drift since 2026-05-10. `register-customer`'s intentional pin is re-confirmed with a header comment, not changed |
| Finding E remediation | Tighten grants on `usage_events`, `user_profiles`, **and every other tenant-scoped table**. Default new grants: `authenticated SELECT, INSERT, UPDATE, DELETE` per table (no TRUNCATE, no REFERENCES, no TRIGGER); `anon` revoked entirely; `service_role` unchanged (bypasses RLS by design) | The 3.4 finding noted that other tables likely share the shape; this audit covers all of them rather than just the two named |
| `claim_paper_account` decision | **Drop** (F33 confirms unused; F21 says defensive checks are insufficient anyway). The Edge Function `claim-paper-customer` reimplements the merge in TypeScript and is the only live caller | Cleaner than adding tenant filtering to a dead function. Removes attack surface. F33 closes; F21 becomes moot |
| `upsertShipment` PRH delete scope | Add `tenant_id=eq.<TENANT_ID>` to the DELETE filter alongside the existing `distributor=eq.PRH&on_sale_date=eq.<date>` filters | Service-role bypasses RLS, so the table-level scope must be explicit in the URL. Same TENANT_ID constant already in scope at the top of the file |
| `buildCatalogIdMap` lookup scope | Add `tenant_id=eq.<TENANT_ID>` to both Lunar UPC/ISBN and PRH item_code lookup URLs | Same reasoning; service-role catalog query is currently unscoped |
| F17 fix | Add `AND tenant_id = current_tenant_id()` to the `admins view all history` policy on `reservation_history` | Matches the F16 fix pattern. Verified via canary tenant probe |
| F19 (`is_admin()` dead duplicate) | **In scope** — drop the function. Small, mechanical, no caller | Surfaced during audit; trivial to close; reduces SECURITY DEFINER surface |
| F23 (DEFINER `search_path` hardening) | **In scope for the four functions named in F23** plus any new SECURITY DEFINER functions added since (`current_tenant_id`, `current_user_is_admin`, `auto_fulfill_past_on_sale`, `purge_old_usage_events`) | Cross-cutting hardening; trivial per-function; do it once across all DEFINER functions while we're in the area. Per parent plan Out of Scope item: "new functions added in 4.4 must include the hardening" — easier to retrofit all existing functions in 4.1 than to maintain mixed state |
| Canary tenant slug | `canary` | Memorable; not confusable with `raysandjudys`; safe to grep for during teardown |
| Canary admin email | `canary-admin@example.invalid` | Reserved TLD per RFC 2606; can't receive real mail; reduces accidental-email-blast blast radius |
| Canary customer emails | `canary-cust-1@example.invalid`, `canary-cust-2@example.invalid` | Same reasoning |
| Canary tenant teardown trigger | **Last task of 4.1** — completed before 4.1 marked Complete in the parent plan's Sub-Deploys table | Parent plan requires teardown before 4.2; binding the trigger to the sub-deploy completion makes the dependency explicit |
| Canary tenant re-spin during 4.7 | Out of scope for 4.1 plan; covered in 4.7 plan | Separate sub-deploy; this plan documents the teardown procedure that 4.7 will re-run after re-spinning |
| Canary teardown SQL location | **Local scripts folder, gitignored** (alongside other local-only operational scripts). Procedure documented in `docs/phase-4.1-canary-procedure.md` as a template for re-generation; the instantiated SQL file with concrete UUIDs never enters git | Decision locked 2026-05-26. Safer (no risk of accidentally running prod-pointed SQL from a committed file); discoverability handled by the committed procedure doc, which references the local file by path |
| Audit deliverable | A new `docs/phase-4.1-audit-findings.md` document committed alongside the code changes, capturing the audit-then-fix paper trail per finding | Mirrors the Phase 1 completion-notes pattern. Auditable artifact for the cutover decision |
| Audit triage gate | **Stop-and-ask inline during the CLI session** for every new finding the audit surfaces beyond the planned list. CLI session pauses; user decides bundle / defer / out-of-scope per finding; session resumes | Decision locked 2026-05-26. Preserves the anti-drift posture inside the session rather than batching decisions to async review. Trade-off accepted: longer session wall-clock time in exchange for tighter audit-to-decision loop |
| Anti-drift posture | Higher-than-usual stop-and-ask threshold — see Audit triage gate row | The audit will surface findings not on the planned list. Each new finding triggers stop-and-ask per the gate above |

---

## In Scope

### Audit (deliverable: `docs/phase-4.1-audit-findings.md`)

1. **F16-class audit** — For each tenant-scoped table (`user_profiles`, `preorders`, `subscriptions`, `weekly_shipment`, `reservation_history`, `usage_events`, `catalog`, `app_settings`, `settings`, `tenants`), query `pg_policies` and list every policy. For any table with multiple PERMISSIVE policies on the same `roles` × `cmd` combination, flag for review. Fix any flagged set the same way F16 was fixed: consolidate into a single ALL policy that checks both `tenant_id = current_tenant_id()` and (where relevant) `current_user_is_admin()`.

2. **F34-class audit** — For each of the 8 Edge Functions, read the source and answer:
   - Does the function write to any tenant-scoped table?
   - If yes, where does `tenant_id` come from? (Caller's profile lookup? Hard-coded constant? Request body? Implicit default?)
   - For functions that read from tenant-scoped tables: does the query filter by tenant explicitly, or rely on RLS?
   - Document the answer per function in the audit findings doc. Patch any function that picks up `tenant_id` from anywhere other than the caller's profile (with `register-customer` as the documented exception, header comment refreshed).

3. **Finding E grants audit** — For each tenant-scoped table, query `information_schema.role_table_grants` for `anon`, `authenticated`, `service_role`. Document the current grants per (table, role) pair. Tighten any grant wider than the table's actual usage. Default tightened state: `anon REVOKE ALL`; `authenticated SELECT, INSERT, UPDATE, DELETE`; `service_role` unchanged. Per-table exceptions documented in the audit findings doc.

### Code changes (staging repo)

4. **F17 fix on `reservation_history`** — `DROP POLICY admins view all history`; `CREATE POLICY admins view all history` with `qual = (current_user_is_admin() AND tenant_id = current_tenant_id())`. Plus `SET search_path = public` on any related DEFINER function touched.

5. **Drop `claim_paper_account(uuid, uuid)` SQL function** — `DROP FUNCTION claim_paper_account(paper_user_id uuid, real_user_id uuid);`. Verify no caller exists by greping `app.js`, all HTML pages, all Edge Function source. Close F21 and F33 in the findings index.

6. **`import-staging.js` `upsertShipment` PRH delete** — add `&tenant_id=eq.${TENANT_ID}` to the DELETE URL alongside the existing `distributor=eq.PRH&on_sale_date=eq.${date}` filters.

7. **`import-staging.js` `buildCatalogIdMap`** — add `&tenant_id=eq.${TENANT_ID}` to both Lunar lookup (UPC/ISBN OR filter) and PRH lookup (item_code IN-list) URLs. The catalog table itself has no column default for `tenant_id` (per Phase 1 — import-script-only writes), so cross-tenant catalog rows could exist; explicit scoping prevents lookups from matching the wrong tenant's rows.

8. **`is_admin()` SQL function drop** (F19) — `DROP FUNCTION is_admin();`. Confirm via `pg_policies` query that no policy still references it.

9. **F23 search_path hardening** — `ALTER FUNCTION <name> SET search_path = public;` for `purge_stale_catalog`, `delete_dropped_catalog_items`, `get_popular_series`, `archive_stale_reservations`, `current_tenant_id`, `current_user_is_admin`, `auto_fulfill_past_on_sale`, `purge_old_usage_events`. Verify with a `pg_proc` query showing the `proconfig` column populated for each.

10. **Edge Function patches** — per audit findings (item 2). Specific patches not pre-listed in this plan because the audit determines them; runbook will enumerate after the audit phase completes.

11. **RLS policy patches** — per audit findings (item 1). Same as above.

12. **Table grant tightening** — per audit findings (item 3). Same as above.

### Canary tenant lifecycle

13. **Spin up canary tenant** — INSERT into `tenants` with slug `canary`, display name `Canary Bookshop`, branding `{}`. Create canary admin via `invite-customer` (so the F34-fixed path is exercised), then mark `user_profiles.is_admin = true` for that user. Create two canary customers via `create-paper-customer` (each from the canary admin's session, exercising the post-F34 path that picks up `callerTenantId` from the caller's profile).

14. **Synthetic canary catalog import** — manually craft a small CSV pair (5–10 titles each) tagged for a fake catalog month (e.g. `2099-01`); run `import-staging.js` against them with the `--skip-autoreserve` flag (per 4.0); verify all rows land with `tenant_id = <canary-uuid>`; verify zero rows landed under the founding tenant's `tenant_id`.

15. **Two-tenant soak observations** (3 days — matches Phase 3 cadence; decision locked 2026-05-26):
    - Founding-tenant admin sessions: can they SELECT canary rows from any table? (Expected: zero rows returned.)
    - Founding-tenant customer sessions: do any UI surfaces show canary data? (Expected: nothing visible.)
    - Canary admin session: can they SELECT founding-tenant rows? (Expected: zero.)
    - Canary customer sessions: are catalog, mylist, arrivals, subscriptions all empty/scoped correctly? (Expected: yes.)
    - Analytics views: do any aggregate counts include canary data when queried as founding? (Expected: no.)
    - `get_popular_series()`: results are founding-only when queried as founding? canary-only when queried as canary? (Expected: yes per F20 fix.)
    - Email blast via `notify-customers`: scoped to one tenant per call? (Test: send-as-canary; only canary customers receive; founding-tenant customers do not.)
    - All 8 Edge Functions: every code path exercised at least once during soak; logs reviewed for any cross-tenant references in metadata.

16. **Canary tenant teardown** — at end of soak: DELETE canary rows from every tenant-scoped table (foreign-key-ordered: `preorders`, `subscriptions`, `reservation_history`, `usage_events`, `weekly_shipment` rows tagged canary, then `user_profiles`, `auth.users`, then `tenants`). Verify with row count delta against pre-canary baseline. The teardown script is committed to the local scripts folder (gitignored) so 4.7 can re-run it.

### Documentation

17. **`docs/phase-4.1-audit-findings.md`** — new file capturing all audit results; one section per audit (F16-class, F34-class, Finding E grants), each with a per-table or per-function findings table and a fix decision (in-4.1 / deferred / no-action).

18. **`docs/technical-reference.md` § 13** — update findings index: F17 fixed, F19 fixed, F21 closed (function dropped, so the "lacks defensive checks" concern is moot), F23 fixed for in-scope functions, F33 closed (function dropped); Finding E promoted to a numbered finding (next available ID, suggest **F40**) and marked fixed; plus any new findings the audit produced.

19. **`docs/phase-4-production-migration.md`** — 4.1 row → Complete with date; 4.2 row → Planning; update Carry-Forward block items 2–6 with "Resolved in 4.1".

20. **`CLAUDE.md`** — § Current Migration Phase → active sub-deploy 4.2; § Known Out-of-Scope Items → remove resolved items (Finding E, claim_paper_account, upsertShipment risk, F17, F19, F23); F16/F34 deep audit references removed.

## Out of Scope

Per anti-drift: discover → describe → ask → wait if any of these surface during execution.

- **F4 cleanup tail** — the orphan `settings` table still exists (empty since 2026-05-10). Dropping it is its own dead-code cleanup; not in 4.1
- **F6 PK on `(tenant_id, key)` for `settings` / `app_settings`** — would force `settings` table changes; bundle with the F4 tail cleanup
- **F10 FK behavior (`preorders` NO ACTION vs CASCADE)** — product/architectural decision; not a Phase 4 blocker
- **F14 redundant `idx_tenants_slug` index** — trivial; bundle with future schema cleanup
- **F25 `user_profiles.email` denormalization trigger** — separate work; not a multi-tenancy concern
- **F26 `admin_preorders` view** — production has it, staging doesn't (per `pre-multitenancy-state.md` § 4); 4.3 recreates with `security_invoker = true`. Not a 4.1 concern
- **F27 `uuid-ossp` vs `pgcrypto`** — schema modernization; not in scope
- **F30 `Preorders.getAll` fragile join** — app code refactor; out of multi-tenancy scope
- **F36 `send-my-list` JWT sub-claim verification** — security finding, but not a *cross-tenant* finding (the function still scopes correctly to the requested user_id; spam-attack risk is non-blocking for cutover). Catalog for separate work
- **`register-customer` Edge Function tenant resolution** — intentionally pinned per F34 status; revisit before tenant 2 onboards (Phase 5)
- **Production deploy** — staging-only sub-deploy by design
- **Cutover-window work** — every cutover task is in 4.2–4.6; nothing in 4.1 touches production
- **Branding rendering / hosting / slug-routing** — Phase 5 per parent plan

---

## Pre-flight Checks

### P1 — Clean tree on staging
```bash
git status
git fetch origin
git log staging..HEAD --oneline   # expect empty
```

### P2 — 4.0 closed and merged
```bash
grep "4.0" docs/phase-4-production-migration.md
# expect: row shows status Complete
```
If 4.0 is not Complete, **stop**. 4.1 depends on staging's `import-staging.js` having the `--skip-autoreserve` flag (used during canary catalog import).

### P3 — Capture baseline state for findings index updates
```bash
grep -n -E "^#### F(17|19|21|23|33)" docs/technical-reference.md
```
Capture exact line numbers and surrounding context for each finding the runbook will edit. Verify status strings match expected pre-state.

### P4 — Capture baseline RLS policy set
```sql
-- Run in Supabase SQL Editor, save output to scratch file
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;
```
This is the F16-class audit input. Save as `docs/phase-4.1-baseline-policies.txt` in the scratch buffer (not committed; reference only).

### P5 — Capture baseline grants
```sql
SELECT grantee, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND grantee IN ('anon', 'authenticated', 'service_role')
ORDER BY table_name, grantee, privilege_type;
```
Finding E audit input.

### P6 — Capture baseline DEFINER function inventory
```sql
SELECT proname, prosecdef, proconfig
FROM pg_proc
WHERE pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
  AND prosecdef = true
ORDER BY proname;
```
F23 audit input. `proconfig` containing `search_path=public` shows which functions are already hardened.

### P7 — Confirm canary admin can be created via `invite-customer`
```bash
# Read invite-customer source; confirm post-F34 caller-tenant lookup works
grep -n "callerTenantId\|FOUNDING_TENANT_ID" supabase/functions/invite-customer/index.ts
```
Expect: `callerTenantId` resolved from caller's profile; `FOUNDING_TENANT_ID` only as fallback. Confirms the canary-admin creation path is the production-cutover path being validated, not a side path.

### P8 — Confirm staging is on the founding-tenant-only baseline
```sql
SELECT tenant_id, COUNT(*) FROM user_profiles GROUP BY tenant_id;
SELECT tenant_id, COUNT(*) FROM preorders GROUP BY tenant_id;
SELECT tenant_id, COUNT(*) FROM subscriptions GROUP BY tenant_id;
```
Expect: every count under the founding-tenant UUID (`72e29f67-...`). If a stray tenant exists from prior testing, identify and clean up before canary spin-up.

### P9 — Confirm `config.js` is untouched and gitignored
Standard credential-safety check.

---

## Changes (file-by-file index)

Specific `str_replace` blocks for the audit-driven items (6, 10, 11, 12) cannot be pre-written — the audit defines them. The runbook for those items is built after the audit phase completes. The non-audit items have pre-spec'd diffs.

### C1 — Run the audit; produce `docs/phase-4.1-audit-findings.md`

Inputs: P4, P5, P6 baseline outputs.

Outputs: a new committed markdown file with three sections (F16-class, F34-class, Finding E), each with a findings table (Surface | Status | Severity | Decision | Notes) and a fix-list summary.

The audit happens **before any code change**. The audit doc is the source of truth for the subsequent C-items.

**Stop-and-ask gate**: as the audit surfaces each finding, the CLI session triages inline. Every finding not on the planned list pauses the session until the user decides bundle / defer / out-of-scope. The audit doc records each triage decision alongside the finding itself.

### C2 — F17 fix on `reservation_history`

SQL (run in Supabase SQL Editor, capture output):
```sql
DROP POLICY IF EXISTS "admins view all history" ON reservation_history;

CREATE POLICY "admins view all history"
ON reservation_history
FOR SELECT
TO authenticated
USING (current_user_is_admin() AND tenant_id = current_tenant_id());
```

Verification:
```sql
SELECT policyname, qual FROM pg_policies
WHERE tablename = 'reservation_history' AND policyname = 'admins view all history';
-- Expected: qual contains both current_user_is_admin() and tenant_id = current_tenant_id()
```

### C3 — Drop `claim_paper_account` (F21, F33)

Pre-check (must return empty):
```bash
grep -rn "claim_paper_account" app.js *.html supabase/functions/ scripts/
```
If any result is a live caller (not a doc reference), **stop**.

SQL:
```sql
DROP FUNCTION IF EXISTS claim_paper_account(paper_user_id uuid, real_user_id uuid);
```

Verification:
```sql
SELECT proname FROM pg_proc WHERE proname = 'claim_paper_account';
-- Expected: zero rows
```

### C4 — Drop `is_admin()` (F19)

Pre-check (must return empty for live use):
```sql
SELECT policyname, tablename FROM pg_policies WHERE qual LIKE '%is_admin()%' OR with_check LIKE '%is_admin()%';
```
Confirm zero rows; if any, **stop** — a policy still references it.

SQL:
```sql
DROP FUNCTION IF EXISTS is_admin();
```

### C5 — F23 search_path hardening

SQL (run as a single batch, capture output line per function):
```sql
ALTER FUNCTION purge_stale_catalog(uuid, date, text) SET search_path = public;
ALTER FUNCTION delete_dropped_catalog_items(uuid, text, text[]) SET search_path = public;
ALTER FUNCTION get_popular_series() SET search_path = public;
ALTER FUNCTION archive_stale_reservations(uuid, date, text) SET search_path = public;
ALTER FUNCTION current_tenant_id() SET search_path = public;
ALTER FUNCTION current_user_is_admin() SET search_path = public;
ALTER FUNCTION auto_fulfill_past_on_sale(uuid) SET search_path = public;
ALTER FUNCTION purge_old_usage_events(uuid, integer) SET search_path = public;
```

The CLI session must first confirm the exact argument signature of each function (P6 output). If a signature has drifted from the planned `ALTER`, halt and reconcile.

Verification (re-run P6):
```sql
SELECT proname, proconfig FROM pg_proc
WHERE pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
  AND prosecdef = true
ORDER BY proname;
-- Expected: every row's proconfig array contains 'search_path=public'
```

### C6 — `import-staging.js` `upsertShipment` PRH delete tenant scope

**str_replace** in `import-staging.js`. Pre-check exact text:
```bash
grep -n "weekly_shipment?distributor=eq.PRH" import-staging.js
```

`old_str`:
```javascript
      const delRes = await fetch(
        `${SUPABASE_URL}/rest/v1/weekly_shipment?distributor=eq.PRH&on_sale_date=eq.${date}`,
        { method: 'DELETE', headers: HEADERS }
      );
```

`new_str`:
```javascript
      const delRes = await fetch(
        `${SUPABASE_URL}/rest/v1/weekly_shipment?distributor=eq.PRH&on_sale_date=eq.${date}&tenant_id=eq.${TENANT_ID}`,
        { method: 'DELETE', headers: HEADERS }
      );
```

Verification:
```bash
grep "weekly_shipment?distributor=eq.PRH" import-staging.js
# expect: URL now includes &tenant_id=eq. clause
```

### C7 — `import-staging.js` `buildCatalogIdMap` Lunar lookup tenant scope

`old_str`:
```javascript
    const res = await fetch(
      `${SUPABASE_URL}/rest/v1/catalog?select=id,upc,isbn,cover_url,publisher,series_name&${filter}`,
      { headers: HEADERS }
    );
    if (!res.ok) { console.warn(`   ⚠️  Lunar UPC lookup batch failed: ${await res.text()}`); continue; }
```

`new_str`:
```javascript
    const res = await fetch(
      `${SUPABASE_URL}/rest/v1/catalog?select=id,upc,isbn,cover_url,publisher,series_name&${filter}&tenant_id=eq.${TENANT_ID}`,
      { headers: HEADERS }
    );
    if (!res.ok) { console.warn(`   ⚠️  Lunar UPC lookup batch failed: ${await res.text()}`); continue; }
```

### C8 — `import-staging.js` `buildCatalogIdMap` PRH lookup tenant scope

`old_str`:
```javascript
    const res = await fetch(
      `${SUPABASE_URL}/rest/v1/catalog?select=id,item_code,cover_url,publisher,series_name&${filter}`,
      { headers: HEADERS }
    );
    if (!res.ok) { console.warn(`   ⚠️  PRH code lookup batch failed: ${await res.text()}`); continue; }
```

`new_str`:
```javascript
    const res = await fetch(
      `${SUPABASE_URL}/rest/v1/catalog?select=id,item_code,cover_url,publisher,series_name&${filter}&tenant_id=eq.${TENANT_ID}`,
      { headers: HEADERS }
    );
    if (!res.ok) { console.warn(`   ⚠️  PRH code lookup batch failed: ${await res.text()}`); continue; }
```

### C9–C11 — Audit-driven patches

C9: F16-class policy consolidations identified in C1.
C10: F34-class Edge Function patches identified in C1.
C11: Finding E grant tightening identified in C1.

The runbook for C9–C11 is generated after C1 completes and the audit findings doc is committed. Each item gets its own discrete diff/SQL block with verification, exactly like C2–C8.

### C12 — Canary tenant spin-up

Manual procedure documented in `docs/phase-4.1-canary-procedure.md` (new file, committed). Captures:
- SQL to INSERT canary tenant row
- `curl` commands to invoke `invite-customer` then `create-paper-customer` from the canary admin's session
- CSV templates for the synthetic catalog (`canary-lunar.csv`, `canary-prh.csv`)
- `import-staging.js --skip-autoreserve` invocation with canary CSVs

### C13 — Soak observations log

A new file `docs/phase-4.1-soak-log.md` populated daily during the soak. One section per check from In Scope item 15; each check timestamped with the result. Committed at end of soak as part of the closing PR.

### C14 — Canary tenant teardown

Procedure documented in `docs/phase-4.1-canary-procedure.md` as a template (parameterized with placeholder UUIDs). At canary spin-up time, the CLI session instantiates the template with the actual canary UUIDs and writes the result to the **local scripts folder** as `phase-4.1-canary-teardown.sql` — **gitignored, never committed**. The committed procedure doc references the local file path so 4.7 knows where to re-run from after re-spinning.

SQL template is FK-ordered:
```sql
-- Local-only file: scripts/phase-4.1-canary-teardown.sql (gitignored)
-- Generated from template in docs/phase-4.1-canary-procedure.md
-- Run in Supabase SQL Editor; verify each row count before proceeding
DELETE FROM usage_events WHERE tenant_id = '<canary-uuid>';
DELETE FROM reservation_history WHERE tenant_id = '<canary-uuid>';
DELETE FROM preorders WHERE tenant_id = '<canary-uuid>';
DELETE FROM subscriptions WHERE tenant_id = '<canary-uuid>';
DELETE FROM weekly_shipment WHERE tenant_id = '<canary-uuid>';
DELETE FROM catalog WHERE tenant_id = '<canary-uuid>';
DELETE FROM app_settings WHERE tenant_id = '<canary-uuid>';
-- user_profiles row deletion cascades from auth.users delete:
DELETE FROM auth.users WHERE id IN (
  '<canary-admin-uuid>', '<canary-cust-1-uuid>', '<canary-cust-2-uuid>'
);
DELETE FROM tenants WHERE id = '<canary-uuid>';
```

When 4.7 re-spins a canary, it generates new UUIDs; the instantiated teardown SQL file is regenerated from the same template with the new IDs.

### C15 — Documentation updates

Per item 17–20 in § In Scope. Last in execution sequence so docs reflect the committed code state.

---

## Execution Sequence

The session may exceed one extended sitting. Two natural split points are flagged.

### Session 1 — Audit + non-audit code changes (no canary yet)

1. `git checkout -b feature/4.1-pre-cutover-hardening`
2. P1–P9 pre-flight
3. C1 — run audits; produce `docs/phase-4.1-audit-findings.md`; commit
4. **Decision gate (stop-and-ask inline):** for every new audit finding beyond the planned list, halt session and report to user. Each finding triaged interactively as bundle-into-4.1, defer-to-later-sub-deploy, or out-of-scope-for-Phase-4. Session resumes after each triage decision
5. C2 — F17 SQL
6. C3 — drop `claim_paper_account`
7. C4 — drop `is_admin()`
8. C5 — F23 search_path hardening
9. C6, C7, C8 — `import-staging.js` tenant scoping
10. C9, C10, C11 — audit-driven patches (if any)
11. Smoke test: existing Playwright suite must pass green; staging UI smoke per CLAUDE.md
12. Commit per logical group (one commit per finding fix); push branch

**Natural split point 1.** If the session is long, stop here. Resume Session 2 after the audit findings are reviewed and signed off.

### Session 2 — Canary spin-up and soak start

13. C12 — canary spin-up; verify all canary data lands under canary UUID, zero under founding
14. C13 — first day of soak observations; log to `docs/phase-4.1-soak-log.md`

**Natural split point 2.** Soak runs 3 days. Daily check-ins are short; no need for an extended session per day.

### Session 3 — Soak close, teardown, sub-deploy close

15. Final soak check; close out `docs/phase-4.1-soak-log.md`
16. C14 — canary teardown; verify row counts return to founding-tenant baseline
17. C15 — documentation updates (parent plan, CLAUDE.md, technical-reference, findings index)
18. Final smoke; Playwright suite green; manual UI smoke
19. Final commit; PR; user reviews and merges to `staging`

---

## Post-execution Verification

### V1 — All targeted findings closed in the index
```bash
grep -A2 "^#### F17 \|^#### F19 \|^#### F21 \|^#### F23 \|^#### F33 " docs/technical-reference.md
```
Expect: each Status line shows "fixed YYYY-MM-DD" or "closed YYYY-MM-DD" with appropriate date.

### V2 — Finding E promoted and closed
```bash
grep -B1 -A4 "^#### F40 \|Finding E " docs/technical-reference.md
```
Expect: numbered finding entry exists; status "fixed YYYY-MM-DD".

### V3 — Grants tightened
Re-run P5 query. Compare against the baseline scratch file. Expected diff: `anon` rows removed for tenant-scoped tables; `authenticated` rows show only the four CRUD privileges; `service_role` unchanged.

### V4 — Policies consolidated
Re-run P4 query. For each table flagged in the audit, the number of PERMISSIVE policies on the same `(role, cmd)` should be ≤ 1.

### V5 — DEFINER functions hardened
Re-run P6 query. Every row's `proconfig` includes `search_path=public`. `is_admin` row gone. `claim_paper_account` row gone.

### V6 — `import-staging.js` shipment writes scope correctly
After canary spin-up, run the synthetic canary catalog + a small synthetic shipment. Query:
```sql
SELECT tenant_id, COUNT(*) FROM weekly_shipment GROUP BY tenant_id;
SELECT tenant_id, COUNT(*) FROM catalog GROUP BY tenant_id;
```
Expect: canary rows under canary UUID; zero canary rows under founding UUID.

### V7 — Cross-tenant probes during soak (run daily, log to soak doc)
- As founding admin: `SELECT * FROM preorders WHERE tenant_id = '<canary-uuid>';` returns zero rows
- As canary admin: `SELECT * FROM preorders WHERE tenant_id = '<founding-uuid>';` returns zero rows
- Reverse for `user_profiles`, `subscriptions`, `reservation_history`, `usage_events`, `weekly_shipment`
- `get_popular_series()` as founding excludes canary series; as canary excludes founding series

### V8 — Edge Function exercise during soak
Each of the 8 Edge Functions invoked at least once from a canary session and at least once from a founding session. Logs reviewed for tenant_id assignments matching the caller's tenant.

### V9 — Canary teardown clean
Re-run P8 baseline queries. Counts match pre-canary baseline exactly. Zero canary-tagged rows remain in any table.

### V10 — Playwright suite green
```bash
npx playwright test
```
Expect: full suite passes. Two-tenant-fixture spec exercises both tenants; isolation assertions pass.

---

## Completion Criteria

Sub-Deploy 4.1 is complete when **all** of the following are true on staging:

- [ ] `docs/phase-4.1-audit-findings.md` committed with full F16-class, F34-class, and Finding E audit results
- [ ] F17 policy consolidated and verified (V4)
- [ ] `claim_paper_account` SQL function dropped (V5)
- [ ] `is_admin()` SQL function dropped (V5)
- [ ] All in-scope SECURITY DEFINER functions have `SET search_path = public` (V5)
- [ ] `import-staging.js` `upsertShipment` PRH delete and `buildCatalogIdMap` lookups all carry `tenant_id` scope (V6)
- [ ] All audit-driven RLS / Edge Function / grant patches landed and verified per the audit doc's fix list
- [ ] Canary tenant lived alongside founding for 3 days with zero cross-tenant leak observed (V7, V8)
- [ ] Canary tenant torn down cleanly; row counts back to founding baseline (V9)
- [ ] `docs/phase-4.1-canary-procedure.md` committed (spin-up + teardown documented for 4.7 reuse)
- [ ] `docs/phase-4.1-soak-log.md` committed with daily observations
- [ ] `docs/technical-reference.md` § 13 updated: F17, F19, F21, F23, F33 closed; Finding E promoted to F40 and closed
- [ ] `docs/phase-4-production-migration.md` Sub-Deploys table: 4.1 → Complete; 4.2 → Planning; Carry-Forward items 2–6 marked Resolved in 4.1
- [ ] `CLAUDE.md` § Current Migration Phase → active sub-deploy 4.2; § Known Out-of-Scope Items pruned of resolved entries
- [ ] Full Playwright suite green (V10)
- [ ] PR merged to `staging`

---

## Carry-forward / Notes

- **`register-customer` tenant pin** — intentional per F34. The 4.1 audit re-confirms with a refreshed header comment; the actual unpin is a Phase 5 task tied to self-service tenant signup
- **F4 / F6 settings cleanup** — orphan `settings` table drop and `(tenant_id, key)` PK migration are sequenced together as a future dead-code cleanup pass; not Phase 4
- **F36 `send-my-list` JWT sub-claim verification** — security finding caught during 4.1 audit reading (not a 4.1 fix); catalog for a separate sub-deploy
- **Canary teardown SQL** — instantiated to `scripts/phase-4.1-canary-teardown.sql` (local, gitignored). Template lives at `docs/phase-4.1-canary-procedure.md`. If 4.7 re-spins, it generates new UUIDs and the teardown SQL must be regenerated from the template for the new IDs
- **New findings surfaced during audit** — anything not bundled into 4.1 per the decision gate gets a new finding ID in `technical-reference.md` § 13 and a one-line entry in `CLAUDE.md` § Known Out-of-Scope Items for tracking

---

## Reference

- Parent plan: `docs/phase-4-production-migration.md`
- Anti-drift rules: `CLAUDE.md` § Anti-Drift Rules for Agentic Sessions
- Findings index: `docs/technical-reference.md` § 13
- F16 (closed 2026-05-10): `technical-reference.md` § 13 F16
- F17 (open, fixed in 4.1): § 13 F17
- F19 (dead code, dropped in 4.1): § 13 F19
- F21 (closed via function drop in 4.1): § 13 F21
- F23 (open, hardened in 4.1): § 13 F23
- F33 (closed via function drop in 4.1): § 13 F33
- F34 (closed 2026-05-10; re-audited in 4.1): § 13 F34
- Finding E (CLAUDE.md line 421–429; promoted to F40 in 4.1): § Known Out-of-Scope Items
- Sibling sub-deploy template (this plan mirrors shape): `docs/phase-3.6-admin-wednesday-tooling.md`
- 4.0 plan (must complete before 4.1): `docs/phase-4.0-backfill-parity.md`
- Founding tenant UUID (staging): `72e29f67-39f7-42bc-a4d5-d6f992f9d790`
- Canary tenant UUID (staging): generated during C12; captured in `docs/phase-4.1-canary-procedure.md`
- Production cutover: 4.2 onward; 4.1 is the last staging-only sub-deploy

---

**Plan written:** 2026-05-26
**Plan author session:** chat (Opus)
**Execution session target:** Claude Code CLI on staging repo (multi-session; see § Execution Sequence)
**Pending decisions before runbook generation:** none — all planning-phase decisions resolved in § Approach Summary. The audit findings doc (C1) will drive C9–C11 runbook generation as a second planning pass at the natural split point
