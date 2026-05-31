# Phase 4.3 — Production Schema Constraints + View Recreation + RLS Recursion Fix — RUNBOOK

**Sub-deploy:** 4.3 (cutover-window, Sat-morning slot per parent plan § Cutover sequencing)
**Environment:** **PRODUCTION** — Supabase `plgegklqtdjxeglvyjte` (`https://plgegklqtdjxeglvyjte.supabase.co`)
**Execution model:** CLI-orchestrated, Rick-in-the-loop — see § OPERATING MODEL (the CLI session never reaches the prod database itself; all DB SQL is run by Rick in the Supabase SQL Editor)
**Repo branch (SQL artifact):** `feat/phase-4-prod-cutover` off `main` in the **production** repo
**Repo branch (doc):** `staging` (doc-only commit, per `CLAUDE.md` § Document Integrity)
**Rollback tier:** Tier 1 (fails-to-apply / smoke-fail-before-traffic). Per-section reverse SQL provided. Maintenance mode stays ON throughout. Full recoverability — no customer writes occur in this window.

**Founding tenant (prod):** `id = 20941129-c35a-476d-ae21-44b8f77af89c`, `slug = rjbookstop`
**Founding admin (prod):** `734bfd7e-23a6-4c23-ba35-1f64843603c0`

**Status:** COMPLETE — 2026-05-31. All PF/V/SG gates green. SQL artifact committed on `feat/phase-4-prod-cutover`.

---

## Execution Notes (deviations from plan, recorded 2026-05-31)

### EN1 — PF3: 5 NULL `usage_events` rows (backfill re-run required)
`usage_events` had 5 NULL `tenant_id` rows written after the 4.2 backfill ran (likely from app/Edge Function activity before maintenance mode was fully effective). HALT triggered; the following backfill was run before PF3 re-check:
```sql
UPDATE public.usage_events SET tenant_id = '20941129-c35a-476d-ae21-44b8f77af89c' WHERE tenant_id IS NULL;
```
Result: `UPDATE 5`. PF3 re-check confirmed 0 NULLs on all 9 tables. Carry-forward: for any future cutover window, check `usage_events` for post-backfill NULLs as a pre-flight step.

### EN2 — PF5: 5 of 7 recursive policies had `roles = {public}`, not `{authenticated}`
The policies on `preorders`, `reservation_history`, `settings`, `subscriptions`, and `usage_events` used `TO public` (the Postgres default when no role is specified). Only the two `user_profiles` policies already used `TO authenticated`. The PF5 halt condition (c) fired. Rick approved **Option A**: all 7 recreated `TO authenticated` (aligns with staging shape; functionally equivalent since all USING clauses check `auth.uid()`). Carry-forward: the staging analog (staging F46) only covers one policy — 4.4 should verify staging's other policies don't have the same `{public}` drift.

### EN3 — PF5: all 7 `with_check` were NULL
The three UPDATE policies (`preorders`, `settings`, `user_profiles`) had `with_check = null`. The `WITH CHECK (is_admin())` lines in S7 blocks 7.1, 7.3, and 7.7 were omitted accordingly.

### EN4 — SG2: SQL Editor cannot run multiple SELECT statements in one batch
The SQL Editor combined the SELECT statements rather than returning individual result sets. SG2 was restructured as two scripts: one using scalar subqueries to return all 5 counts in a single row, one for the UPDATE test.

---

## OPERATING MODEL — CLI-orchestrated, Rick-in-the-loop

A single Claude Code CLI session runs this runbook **top to bottom** and is the orchestrator of record. This document is **self-contained**: it requires no chat history. Everything the session needs is below.

**The CLI session cannot reach the production database.** It owns and directly performs only repo, doc, and local-file actions. Every production-database action is handed to Rick, who runs it in the **Supabase SQL Editor** and pastes the result back; the session validates the paste against the step's **Expected** before continuing.

### The loop (applies to every DB step — every fenced ```sql block below)
1. **PAUSE.** Present the exact SQL block to Rick with its step ID and a one-line "what this does / what I expect back."
2. **WAIT.** Do nothing else until Rick pastes the SQL Editor output. Never run it, never assume it, never fabricate or "expect-ahead" a result.
3. **VALIDATE.** Compare the pasted output to the step's **Expected**.
   - Match → record it and proceed to the next step.
   - Mismatch, error, or empty/ambiguous paste → **HALT**, state the divergence, and stop. Do not improvise or proceed. (A failed pre-check is a halt-and-report.)
4. For capture steps (PF4–PF7), the pasted output **feeds later steps** (drop mechanism, S7 clause shape, rollback bodies). Hold it in the session and, where noted, ask Rick to also save it to the named gitignored scratch file.

### Actor legend
- **[Rick — SQL Editor]** — a DB step. CLI pauses, hands the SQL, waits for the pasted result, validates.
- **[Rick — browser]** — a manual prod UI action (SG1). CLI pauses, waits for Rick's confirmation/observation.
- **[CLI]** — the session performs it directly (git, file save, doc edit). No DB access; no pause needed except where it consumes a prior paste.

### Actor map (every step)
| Step | Actor | Notes |
|---|---|---|
| PF1–PF3 | [Rick — SQL Editor] | gates; HALT on any miss |
| PF4 | [Rick — SQL Editor] → [CLI] | paste decides DROP CONSTRAINT vs DROP INDEX in S2/S3 |
| PF5 | [Rick — SQL Editor] → [CLI] | paste is the S7 shape gate **and** S7 rollback source; CLI asks Rick to save to `scripts/phase-4.3-policy-capture.txt` |
| PF6 | [Rick — SQL Editor] → [CLI] | paste is S6 rollback source; CLI asks Rick to save to `scripts/phase-4.3-admin-preorders-capture.txt` |
| PF7 | [Rick — SQL Editor] | confirms D1 precondition |
| S1–S7 apply blocks | [Rick — SQL Editor] | CLI presents the (PF-resolved) SQL; Rick runs; pastes back |
| V1–V7 | [Rick — SQL Editor] | CLI validates each paste vs Expected before the next S-section |
| SG1 | [Rick — browser] | load prod `admin.html`; Rick reports load + console/log state |
| SG2–SG3 | [Rick — SQL Editor] | rolled-back txns; Rick pastes counts/outcome |
| POST step 1 | [CLI] | assemble + commit SQL migration on `feat/phase-4-prod-cutover` (no push) |
| POST step 2–3 | [CLI] | doc + doc-corrections commit to `staging`; push staging |
| POST step 4 | [CLI] | advance parent plan + `CLAUDE.md` (only after all gates green) |
| POST step 5 | [CLI] | prepare 4.4 carry-forward; the listed capture SQL is run next session, not now |

**Section order is the execution order.** Do not batch DB steps ahead or run a later section before the prior one's V-gate paste has been validated. The S7 `WITH CHECK` lines and the S2/S3 drop form are **not** final until PF5/PF4 pastes are in hand.

## Decisions baked in (signed off in planning)

- **D1 — admin check:** The 7 recursion fixes de-recurse onto the **already-present `is_admin()`** (`SECURITY DEFINER STABLE`, bypasses RLS on its `user_profiles` read → kills recursion). `current_user_is_admin()` does **not** exist on prod until 4.4. Standardizing all admin policies onto `current_user_is_admin()` + adding `AND tenant_id = current_tenant_id()` is **4.4**, which rewrites these same policies anyway.
- **D2 — FKs ×9:** `tenant_id → tenants(id) ON DELETE CASCADE` on all 9 tables is **in 4.3** (baseline § 2.1 + per-table table + staging parity). Parent-plan line 143's omission of FKs is a doc inaccuracy → corrected in the doc-correction step below.
- **D3 — slug:** Prod founding slug `rjbookstop` was deliberate (diverges from staging `raysandjudys`). It satisfies the 4.3 slug check. Logged as **PB7**; S5 verification asserts against the live value.

## Issues addressed

- **PB3** — 7 RLS policies use the recursive `EXISTS (SELECT 1 FROM user_profiles ...)` anti-pattern (the `CLAUDE.md` § Known Issues RLS-recursion footgun; staging analog F46, single policy).
- Phase 1.2 constraints (NOT NULL ×9, tenant-aware unique on `catalog` + `subscriptions`, `tenants_slug_format_check`).
- D2 FKs ×9.
- `admin_preorders` recreation to the post-F49 staging shape (tenant_id column, `security_invoker = true`, tightened grants). Staging-side findings: **F26**, **F49**.

---

## PRE-FLIGHT

### Files to read first (from prod repo working tree on `feat/phase-4-prod-cutover`)
- `CLAUDE.md`
- `docs/phase-4-production-migration.md`
- `docs/production-baseline-2026-05-28.md`
- `docs/technical-reference.md` (canonical staging shapes — §§ 3.1, 5.1, 6.1, and the unique-key/FK lines)

### Files NOT to touch in 4.3
`app.js`, any `*.html`, `style.css`, `config.js`, `supabase/functions/**`, `import.js`, `import-staging.js`. 4.3 is SQL-only. Any change to these is out of scope (see § Out of Scope).

### Environment notes confirmed in planning
- PowerShell on Windows. No `&&`; git commands on separate lines.
- SQL Editor runs as `postgres` superuser → **bypasses RLS**. RLS behavior is verified by simulating an authenticated session inside a transaction (`SET LOCAL role` + `request.jwt.claims`), per `CLAUDE.md` § Supabase platform facts.
- 4.2 is Complete (additive schema + backfill + 9 `idx_*_tenant` indexes; V1–V5 green).

### Hard gates — run all, in order. Any failure ⇒ HALT, do not proceed to S1.

**PF1 — Maintenance mode ON**
```sql
SELECT key, value FROM public.app_settings WHERE key = 'maintenance_mode';
```
Expected: one row, value truthy (`true`/`'true'`). If OFF → HALT (window not open).

**PF2 — 4.2 landed: tenants table + founding row**
```sql
SELECT id, slug, display_name, plan FROM public.tenants;
```
Expected: founding row `id = 20941129-c35a-476d-ae21-44b8f77af89c`, `slug = rjbookstop`. (Any other/extra row → HALT; no canary on prod.)

**PF3 — Zero NULL tenant_id on all 9 tables (re-verify, do not trust 4.2 report)**
```sql
SELECT 'app_settings' AS t, count(*) AS nulls FROM public.app_settings        WHERE tenant_id IS NULL
UNION ALL SELECT 'catalog',             count(*) FROM public.catalog             WHERE tenant_id IS NULL
UNION ALL SELECT 'preorders',           count(*) FROM public.preorders           WHERE tenant_id IS NULL
UNION ALL SELECT 'reservation_history', count(*) FROM public.reservation_history WHERE tenant_id IS NULL
UNION ALL SELECT 'settings',            count(*) FROM public.settings            WHERE tenant_id IS NULL
UNION ALL SELECT 'subscriptions',       count(*) FROM public.subscriptions       WHERE tenant_id IS NULL
UNION ALL SELECT 'usage_events',        count(*) FROM public.usage_events        WHERE tenant_id IS NULL
UNION ALL SELECT 'user_profiles',       count(*) FROM public.user_profiles       WHERE tenant_id IS NULL
UNION ALL SELECT 'weekly_shipment',     count(*) FROM public.weekly_shipment     WHERE tenant_id IS NULL;
```
Expected: `nulls = 0` for all 9 rows. Any non-zero → HALT (NOT NULL promotion will fail; re-run 4.2 backfill).

**PF4 — Resolve drop mechanism for the two unique keys being swapped**
```sql
SELECT conname FROM pg_constraint
 WHERE conname IN ('catalog_item_code_distributor_month_unique',
                   'subscriptions_user_id_series_name_distributor_key');
SELECT indexname FROM pg_indexes
 WHERE schemaname = 'public'
   AND indexname IN ('catalog_item_code_distributor_month_unique',
                     'subscriptions_user_id_series_name_distributor_key');
```
Decision rule per key: if the name appears in **pg_constraint** → drop with `ALTER TABLE ... DROP CONSTRAINT`. If it appears **only** in pg_indexes → drop with `DROP INDEX`. S2/S3 give both forms; use the one PF4 selects. (Index dump from planning shows both as `CREATE UNIQUE INDEX`; that does not by itself reveal constraint-backing — PF4 is authoritative.)

**Actual result (2026-05-31):** Both appeared in `pg_constraint` → `ALTER TABLE DROP CONSTRAINT` used for both.

**PF5 — Capture exact bodies of the 7 recursive policies (GATE for S7)**
```sql
SELECT tablename, policyname, cmd, roles, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND (tablename, policyname) IN (
    ('preorders',           'admins update all preorders'),
    ('reservation_history', 'admins view all history'),
    ('settings',            'admins update settings'),
    ('subscriptions',       'admins view all subscriptions'),
    ('usage_events',        'admins read all events'),
    ('user_profiles',       'admins delete profiles'),
    ('user_profiles',       'admins update all profiles')
  )
ORDER BY tablename, policyname;
```
**Save this output verbatim** to a local scratch file (`scripts/phase-4.3-policy-capture.txt`, gitignored) — it is the S7 rollback source.

**Actual result (2026-05-31):** 7 rows returned. `qual` bodies matched canonical form. `with_check = null` for all 7. 5 of 7 had `roles = {public}` (HALT triggered); Rick approved Option A (all recreated `TO authenticated`). See EN2/EN3 above.

**PF6 — Capture admin_preorders current definition + dependents (GATE for S6)**
```sql
SELECT pg_get_viewdef('public.admin_preorders'::regclass, true);

SELECT n.nspname, c.relname, c.relkind
FROM pg_depend d
JOIN pg_rewrite r ON r.oid = d.objid
JOIN pg_class   c ON c.oid = r.ev_class
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE d.refobjid = 'public.admin_preorders'::regclass
  AND c.relname <> 'admin_preorders';
```
**Save the viewdef verbatim** to `scripts/phase-4.3-admin-preorders-capture.txt` (gitignored) — S6 rollback source.

**Actual result (2026-05-31):** Pre-Phase-1 viewdef confirmed; zero dependents.

**PF7 — Confirm is_admin() body matches the approved D1 target**
```sql
SELECT pg_get_functiondef('public.is_admin'::regproc);
```
Expected: `LANGUAGE sql`, `STABLE SECURITY DEFINER`, body `SELECT EXISTS (SELECT 1 FROM user_profiles WHERE id = auth.uid() AND is_admin = true)`.

**Actual result (2026-05-31):** Confirmed exact match.

---

## S1 — NOT NULL promotion ×9

**Change:** promote `tenant_id` to `NOT NULL` on all 9 tenant-scoped tables. Gated by PF3 = 0 nulls.

```sql
ALTER TABLE public.app_settings        ALTER COLUMN tenant_id SET NOT NULL;
ALTER TABLE public.catalog             ALTER COLUMN tenant_id SET NOT NULL;
ALTER TABLE public.preorders           ALTER COLUMN tenant_id SET NOT NULL;
ALTER TABLE public.reservation_history ALTER COLUMN tenant_id SET NOT NULL;
ALTER TABLE public.settings            ALTER COLUMN tenant_id SET NOT NULL;
ALTER TABLE public.subscriptions       ALTER COLUMN tenant_id SET NOT NULL;
ALTER TABLE public.usage_events        ALTER COLUMN tenant_id SET NOT NULL;
ALTER TABLE public.user_profiles       ALTER COLUMN tenant_id SET NOT NULL;
ALTER TABLE public.weekly_shipment     ALTER COLUMN tenant_id SET NOT NULL;
```

**V1 — verify**
```sql
SELECT table_name, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' AND column_name = 'tenant_id'
ORDER BY table_name;
```
Expected: 9 rows, all `is_nullable = NO`. **Result (2026-05-31): ✓**

**Rollback S1**
```sql
ALTER TABLE public.app_settings        ALTER COLUMN tenant_id DROP NOT NULL;
ALTER TABLE public.catalog             ALTER COLUMN tenant_id DROP NOT NULL;
ALTER TABLE public.preorders           ALTER COLUMN tenant_id DROP NOT NULL;
ALTER TABLE public.reservation_history ALTER COLUMN tenant_id DROP NOT NULL;
ALTER TABLE public.settings            ALTER COLUMN tenant_id DROP NOT NULL;
ALTER TABLE public.subscriptions       ALTER COLUMN tenant_id DROP NOT NULL;
ALTER TABLE public.usage_events        ALTER COLUMN tenant_id DROP NOT NULL;
ALTER TABLE public.user_profiles       ALTER COLUMN tenant_id DROP NOT NULL;
ALTER TABLE public.weekly_shipment     ALTER COLUMN tenant_id DROP NOT NULL;
```

---

## S2 — `catalog` tenant-aware unique key

**Change:** replace `(item_code, distributor, catalog_month)` with `(tenant_id, item_code, distributor, catalog_month)`. Matches staging `catalog_tenant_item_distributor_month_unique` and the import-script `on_conflict` key. No duplicate risk: single tenant_id ⇒ 4-col uniqueness follows from existing 3-col uniqueness.

```sql
ALTER TABLE public.catalog DROP CONSTRAINT catalog_item_code_distributor_month_unique;

ALTER TABLE public.catalog
  ADD CONSTRAINT catalog_tenant_item_distributor_month_unique
  UNIQUE (tenant_id, item_code, distributor, catalog_month);
```

**V2 — verify**
```sql
SELECT indexname, indexdef FROM pg_indexes
WHERE schemaname = 'public' AND tablename = 'catalog' AND indexname LIKE '%unique%';
```
Expected: `catalog_tenant_item_distributor_month_unique` on `(tenant_id, item_code, distributor, catalog_month)`; old name absent. **Result (2026-05-31): ✓**

**Rollback S2**
```sql
ALTER TABLE public.catalog DROP CONSTRAINT catalog_tenant_item_distributor_month_unique;
ALTER TABLE public.catalog
  ADD CONSTRAINT catalog_item_code_distributor_month_unique
  UNIQUE (item_code, distributor, catalog_month);
```

---

## S3 — `subscriptions` tenant-aware unique key

**Change:** replace `(user_id, series_name, distributor)` with `(tenant_id, user_id, series_name, distributor)`. Matches staging `subscriptions_tenant_user_series_unique`.

```sql
ALTER TABLE public.subscriptions DROP CONSTRAINT subscriptions_user_id_series_name_distributor_key;

ALTER TABLE public.subscriptions
  ADD CONSTRAINT subscriptions_tenant_user_series_unique
  UNIQUE (tenant_id, user_id, series_name, distributor);
```

**V3 — verify**
```sql
SELECT indexname, indexdef FROM pg_indexes
WHERE schemaname = 'public' AND tablename = 'subscriptions' AND indexname LIKE '%unique%';
```
Expected: `subscriptions_tenant_user_series_unique` on `(tenant_id, user_id, series_name, distributor)`; old name absent. **Result (2026-05-31): ✓**

**Rollback S3**
```sql
ALTER TABLE public.subscriptions DROP CONSTRAINT subscriptions_tenant_user_series_unique;
ALTER TABLE public.subscriptions
  ADD CONSTRAINT subscriptions_user_id_series_name_distributor_key
  UNIQUE (user_id, series_name, distributor);
```

---

## S4 — Foreign keys ×9 (`tenant_id → tenants(id) ON DELETE CASCADE`)

**Change:** add the tenant FK on all 9 tables. All rows reference the founding tenant (exists from 4.2) ⇒ validation passes. Default Postgres FK naming `<table>_tenant_id_fkey` (matches staging defaults).

```sql
ALTER TABLE public.app_settings        ADD CONSTRAINT app_settings_tenant_id_fkey        FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;
ALTER TABLE public.catalog             ADD CONSTRAINT catalog_tenant_id_fkey             FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;
ALTER TABLE public.preorders           ADD CONSTRAINT preorders_tenant_id_fkey           FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;
ALTER TABLE public.reservation_history ADD CONSTRAINT reservation_history_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;
ALTER TABLE public.settings            ADD CONSTRAINT settings_tenant_id_fkey            FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;
ALTER TABLE public.subscriptions       ADD CONSTRAINT subscriptions_tenant_id_fkey       FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;
ALTER TABLE public.usage_events        ADD CONSTRAINT usage_events_tenant_id_fkey        FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;
ALTER TABLE public.user_profiles       ADD CONSTRAINT user_profiles_tenant_id_fkey       FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;
ALTER TABLE public.weekly_shipment     ADD CONSTRAINT weekly_shipment_tenant_id_fkey     FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;
```

**V4 — verify**
```sql
SELECT conrelid::regclass AS tbl, conname, confdeltype
FROM pg_constraint
WHERE contype = 'f' AND conname LIKE '%\_tenant\_id\_fkey'
ORDER BY tbl;
```
Expected: 9 rows, `confdeltype = c` (CASCADE) on each. **Result (2026-05-31): ✓**

**Rollback S4**
```sql
ALTER TABLE public.app_settings        DROP CONSTRAINT app_settings_tenant_id_fkey;
ALTER TABLE public.catalog             DROP CONSTRAINT catalog_tenant_id_fkey;
ALTER TABLE public.preorders           DROP CONSTRAINT preorders_tenant_id_fkey;
ALTER TABLE public.reservation_history DROP CONSTRAINT reservation_history_tenant_id_fkey;
ALTER TABLE public.settings            DROP CONSTRAINT settings_tenant_id_fkey;
ALTER TABLE public.subscriptions       DROP CONSTRAINT subscriptions_tenant_id_fkey;
ALTER TABLE public.usage_events        DROP CONSTRAINT usage_events_tenant_id_fkey;
ALTER TABLE public.user_profiles       DROP CONSTRAINT user_profiles_tenant_id_fkey;
ALTER TABLE public.weekly_shipment     DROP CONSTRAINT weekly_shipment_tenant_id_fkey;
```

---

## S5 — `tenants_slug_format_check`

**Change:** add the DNS-safe slug check (two-branch staging form, incl. single-char branch). Live founding slug `rjbookstop` satisfies it (D3).

```sql
ALTER TABLE public.tenants
  ADD CONSTRAINT tenants_slug_format_check
  CHECK (slug ~ '^[a-z0-9][a-z0-9-]*[a-z0-9]$' OR slug ~ '^[a-z0-9]$');
```

**V5 — verify**
```sql
SELECT id, slug,
       (slug ~ '^[a-z0-9][a-z0-9-]*[a-z0-9]$' OR slug ~ '^[a-z0-9]$') AS slug_ok
FROM public.tenants;
```
Expected: founding row `slug = rjbookstop`, `slug_ok = true`. **Result (2026-05-31): ✓**

**Rollback S5**
```sql
ALTER TABLE public.tenants DROP CONSTRAINT tenants_slug_format_check;
```

---

## S6 — Recreate `admin_preorders` (post-F49 staging shape)

**Change:** drop the pre-Phase-1 view; recreate with `tenant_id` in the projection, `security_invoker = true`, and grants tightened to `authenticated` + `service_role`. Gated by PF6 (no dependents; body captured for rollback).

```sql
DROP VIEW IF EXISTS public.admin_preorders;

CREATE VIEW public.admin_preorders WITH (security_invoker = true) AS
  SELECT
    p.id          AS preorder_id,
    p.tenant_id,
    p.created_at  AS reserved_at,
    p.quantity,
    p.notes       AS customer_notes,
    up.full_name  AS customer_name,
    c.distributor, c.item_code, c.title, c.series_name, c.publisher,
    c.format, c.issue_number, c.price_usd,
    c.price_usd * p.quantity AS line_total,
    c.foc_date, c.on_sale_date, c.catalog_month, c.cover_url
  FROM public.preorders p
    JOIN public.user_profiles up ON up.id = p.user_id
    JOIN public.catalog c        ON c.id = p.catalog_id
  ORDER BY up.full_name, c.on_sale_date;

REVOKE ALL ON public.admin_preorders FROM anon;
GRANT SELECT ON public.admin_preorders TO authenticated, service_role;
```

**V6 — verify**
```sql
SELECT pg_get_viewdef('public.admin_preorders'::regclass, true);
SELECT reloptions FROM pg_class WHERE relname = 'admin_preorders';
SELECT grantee, privilege_type FROM information_schema.role_table_grants
WHERE table_schema = 'public' AND table_name = 'admin_preorders' ORDER BY grantee;
```
Expected: tenant_id present in body; `reloptions = {security_invoker=true}`; grants limited to `authenticated` + `service_role` (no `anon`). **Result (2026-05-31): ✓** (`authenticated` also held INSERT/UPDATE/DELETE from Supabase default privileges — no-ops on a non-updatable view; `anon` absent.)

**Rollback S6:** `DROP VIEW public.admin_preorders;` then recreate from the PF6-captured body (default options, original grants) saved in `scripts/phase-4.3-admin-preorders-capture.txt`.

---

## S7 — RLS recursion fix (7 policies → `is_admin()`)

**Gated by PF5.** PF5 resolutions applied: `TO authenticated` for all 7 (Option A); `WITH CHECK` omitted in 7.1, 7.3, 7.7 (all `with_check` null).

```sql
-- 7.1 preorders / UPDATE
BEGIN;
DROP POLICY "admins update all preorders" ON public.preorders;
CREATE POLICY "admins update all preorders" ON public.preorders
  FOR UPDATE TO authenticated
  USING (is_admin());
COMMIT;

-- 7.2 reservation_history / SELECT
BEGIN;
DROP POLICY "admins view all history" ON public.reservation_history;
CREATE POLICY "admins view all history" ON public.reservation_history
  FOR SELECT TO authenticated
  USING (is_admin());
COMMIT;

-- 7.3 settings / UPDATE
BEGIN;
DROP POLICY "admins update settings" ON public.settings;
CREATE POLICY "admins update settings" ON public.settings
  FOR UPDATE TO authenticated
  USING (is_admin());
COMMIT;

-- 7.4 subscriptions / SELECT
BEGIN;
DROP POLICY "admins view all subscriptions" ON public.subscriptions;
CREATE POLICY "admins view all subscriptions" ON public.subscriptions
  FOR SELECT TO authenticated
  USING (is_admin());
COMMIT;

-- 7.5 usage_events / SELECT
BEGIN;
DROP POLICY "admins read all events" ON public.usage_events;
CREATE POLICY "admins read all events" ON public.usage_events
  FOR SELECT TO authenticated
  USING (is_admin());
COMMIT;

-- 7.6 user_profiles / DELETE
BEGIN;
DROP POLICY "admins delete profiles" ON public.user_profiles;
CREATE POLICY "admins delete profiles" ON public.user_profiles
  FOR DELETE TO authenticated
  USING (is_admin());
COMMIT;

-- 7.7 user_profiles / UPDATE
BEGIN;
DROP POLICY "admins update all profiles" ON public.user_profiles;
CREATE POLICY "admins update all profiles" ON public.user_profiles
  FOR UPDATE TO authenticated
  USING (is_admin());
COMMIT;
```

**V7 — verify**
```sql
SELECT tablename, policyname, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND (tablename, policyname) IN (
    ('preorders','admins update all preorders'),
    ('reservation_history','admins view all history'),
    ('settings','admins update settings'),
    ('subscriptions','admins view all subscriptions'),
    ('usage_events','admins read all events'),
    ('user_profiles','admins delete profiles'),
    ('user_profiles','admins update all profiles'))
ORDER BY tablename, policyname;

SELECT tablename, policyname
FROM pg_policies
WHERE schemaname = 'public'
  AND (qual ILIKE '%FROM user_profiles%' OR with_check ILIKE '%FROM user_profiles%');
```
Expected: 7 rows with `qual = is_admin()`, `with_check = null`; recursion sweep = 0 rows. **Result (2026-05-31): ✓**

**Note:** Run as two separate queries in the SQL Editor (see EN4).

**Rollback S7:** per policy, `DROP POLICY` then recreate the exact body from the PF5 capture in `scripts/phase-4.3-policy-capture.txt`.

---

## SMOKE GATE (maintenance mode stays ON)

**SG1 — Admin UI loads. [Rick — browser]** Load production `admin.html` as founding admin. **Result (2026-05-31): ✓ — dashboard rendered; clean logs.**

**SG2 — Simulated-authenticated RLS exercise (admin). [Rick — SQL Editor]**

Note: run as two separate scripts (see EN4).

Script 1 — Read counts:
```sql
BEGIN;
SET LOCAL role authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"734bfd7e-23a6-4c23-ba35-1f64843603c0","role":"authenticated"}';
SELECT
  (SELECT count(*) FROM public.preorders)           AS preorders,
  (SELECT count(*) FROM public.reservation_history) AS history,
  (SELECT count(*) FROM public.subscriptions)       AS subscriptions,
  (SELECT count(*) FROM public.usage_events)        AS usage_events,
  (SELECT count(*) FROM public.admin_preorders)     AS admin_preorders;
ROLLBACK;
```

Script 2 — UPDATE test:
```sql
BEGIN;
SET LOCAL role authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"734bfd7e-23a6-4c23-ba35-1f64843603c0","role":"authenticated"}';
UPDATE public.preorders SET quantity = quantity
  WHERE id = (SELECT id FROM public.preorders LIMIT 1);
ROLLBACK;
```

**Result (2026-05-31): ✓ — counts: preorders=680, history=81, subscriptions=3, usage_events=379, admin_preorders=680. UPDATE succeeded; ROLLBACK confirmed.**

**SG3 — Non-admin scoped. [Rick — SQL Editor]** **Result (2026-05-31): ✓ — non-admin count = 0 (own rows only; not 680).**

---

## VERIFICATION GATE SUMMARY

| Gate | Covers | Result |
|---|---|---|
| PF1–PF7 | pre-flight | ✓ (PF3 required backfill re-run; PF5 triggered role-mismatch HALT → Option A approved) |
| V1 | S1 — NOT NULL ×9 | ✓ |
| V2 | S2 — catalog 4-col unique | ✓ |
| V3 | S3 — subscriptions 4-col unique | ✓ |
| V4 | S4 — FKs ×9, CASCADE | ✓ |
| V5 | S5 — slug check | ✓ |
| V6 | S6 — view tenant_id + security_invoker + grants | ✓ |
| V7 | S7 — 7 policies on is_admin(); recursion sweep = 0 | ✓ |
| SG1–SG3 | smoke | ✓ |

---

## OUT OF SCOPE (do NOT do in 4.3)

- Creating `current_tenant_id()` / `current_user_is_admin()`, and re-pointing policies onto `current_user_is_admin()` — **4.4**.
- Adding tenant scoping (`AND tenant_id = current_tenant_id()`) to any policy — **4.4**.
- Dropping `is_admin()` (staging F19) — deferred; on prod `is_admin()` is load-bearing until 4.4 finishes the rename.
- Tenant-prefixing the `reservation_history` (F7) or `weekly_shipment` (F9) unique keys — staging hasn't fixed these; parity = leave as-is.
- The PRH partial unique index on `weekly_shipment` (PB4) — **4.5/4.6**.
- Adding the redundant `idx_tenants_slug` (F14) for parity — do not add; it's scheduled for DROP on staging.
- Any `app.js` / `*.html` / Edge Function / `import.js` change — **4.4/4.5/4.6**.
- Analytics-view retrofits — **4.4**.
- Toggling `app_settings.maintenance_mode = false` — **4.6 part 2**, after first real import verifies.
