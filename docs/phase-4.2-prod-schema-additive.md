# Phase 4.2 — Production Schema, Additive

**Parent plan:** `docs/phase-4-production-migration.md` (sub-deploy 4.2)
**Baseline (authoritative):** `docs/production-baseline-2026-05-28.md`
**Status:** Planning → ready for cutover-window execution (Friday evening)
**Branch:** `feat/phase-4-prod-cutover` off `main` (production repo). 4.2 itself is SQL-Editor work; no app-code changes land in 4.2.
**Target:** Production Supabase `plgegklqtdjxeglvyjte.supabase.co`
**Rollback complexity:** Easy (`DROP COLUMN` / `DROP INDEX` / `DROP TABLE`; backfill is re-runnable)

---

## Goal

Land the **additive half** of the multi-tenant schema on production: create the `tenants` table
and the founding-tenant row, and add a nullable `tenant_id` column (backfilled to the founding
tenant) plus a `tenant_id` index to **all 9 existing base tables**. No constraints, no `NOT NULL`,
no RLS, no view or function changes — those are 4.3 and 4.4.

This is the Friday-evening step of the coordinated 4.2–4.6 cutover window. Maintenance mode is
ON for the entire window; no customer writes occur while 4.2 runs.

---

## Premise correction (read before executing)

This plan was **rewritten against the live production baseline** (`production-baseline-2026-05-28.md`),
which superseded the stale "production has 7 tables" assumption in the parent plan and `CLAUDE.md`.

**Confirmed live:** production has **9 base tables** — `app_settings` and `usage_events` already
exist (since well before the 2026-04-29 snapshot; see baseline PB6), as do all 6 views and a full
RLS policy set. The documented "create `app_settings` / `usage_events`" line item **does not
apply** — both are handled exactly like the other seven tables.

The only genuinely-missing objects 4.2 creates are `tenants` and the `tenant_id` columns.

---

## Decisions

| # | Decision | Resolution |
|---|---|---|
| D1 | Scope of `app_settings` / `usage_events` | Already exist on prod; treat like every other table (add `tenant_id`). No `CREATE TABLE` for them. |
| D2 | `tenant_id` index placement | `idx_*_tenant` indexes land in **4.2** (additive, `DROP INDEX`-reversible). |
| D3 | `tenant_id` FK placement | `tenant_id → tenants(id)` FKs deferred to **4.3** with `NOT NULL` promotion. 4.2 stays purely additive. |
| D4 | `tenants.slug` format CHECK | Deferred to **4.3** per parent plan line 143. 4.2 creates `tenants` with PK + `UNIQUE(slug)` only. |
| D5 | Founding slug / display_name | `slug = 'rjbookstop'`, `display_name = 'Ray & Judy''s Book Stop'`. |
| D6 | Founding UUID source | Fresh v4 UUID from `scripts/phase-4-prod-tenant-uuid.txt` (gitignored). **Not** the staging UUID. Pasted into the INSERT once; all backfills derive the id by slug subquery. |
| D7 | Backfill idempotency | All backfills are `UPDATE … WHERE tenant_id IS NULL`; all DDL uses `IF NOT EXISTS` / `ON CONFLICT`. Safe to re-run mid-failure. |
| D8 | Doc corrections + baseline commit | Handled as a **housekeeping** doc-only commit to `staging` (see § Housekeeping). Non-blocking for the prod SQL. |

---

## In scope

- `CREATE TABLE tenants` (PK, `UNIQUE(slug)`, no format CHECK; **no** redundant `idx_tenants_slug` — ships clean, F14)
- Founding-tenant `INSERT` (UUID from scratch file; slug `rjbookstop`)
- `ADD COLUMN tenant_id uuid` (nullable) to: `user_profiles`, `catalog`, `preorders`,
  `subscriptions`, `reservation_history`, `weekly_shipment`, `settings`, `app_settings`,
  `usage_events`
- Backfill each to the founding tenant id (by slug subquery)
- `CREATE INDEX idx_<table>_tenant` on each `tenant_id`

## Out of scope (do not do in 4.2)

- Any `NOT NULL` promotion, any FK, any unique-key change, the `tenants` slug CHECK → **4.3**
- `admin_preorders` recreation, RLS recursion fix → **4.3**
- RLS policy changes, `current_tenant_id()` / `current_user_is_admin()` functions, RPC signature
  changes, analytics-view retrofits, default removal, `auto_fulfill_past_on_sale`,
  `purge_old_usage_events` → **4.4**
- The missing PRH `weekly_shipment` partial index (baseline PB4) → **4.5/4.6**
- Dropping `claim_paper_account` (baseline PB5) → deferred housekeeping
- Any `import.js` change → **4.5**

---

## Pre-flight gates (all must pass before any SQL runs)

- **PF1 — Maintenance mode ON.** `SELECT value FROM app_settings WHERE key = 'maintenance_mode';`
  returns `'true'`. (Normal toggle path works — `app_settings` exists on prod.)
- **PF2 — Fresh prod snapshot taken** this evening, stored alongside the 2026-04-29
  `pre-multitenancy-v1` backup.
- **PF3 — UUID scratch file present and valid.** `scripts/phase-4-prod-tenant-uuid.txt` exists,
  contains one v4 UUID, and is **not** `72e29f67-39f7-42bc-a4d5-d6f992f9d790` (staging).
- **PF4 — Founding admin confirmed.** `734bfd7e-23a6-4c23-ba35-1f64843603c0` present,
  `is_admin = true`, `status = active`. (Verified during baseline audit Q8.)
- **PF5 — Baseline committed.** `production-baseline-2026-05-28.md` is committed to `staging`
  (housekeeping step done).
- **PF6 — Live matches baseline.** Re-run baseline Q1 (table inventory); confirm 9 base tables,
  no `tenants`, no `tenant_id` anywhere. If live disagrees with the baseline, **stop** and
  re-baseline before proceeding.

---

## Changes

Each block is idempotent. Run in order. Verify after each before proceeding. Rollback SQL is
per-block; the full-rollback order is in § Rollback.

### C1 — Create `tenants`

```sql
CREATE TABLE IF NOT EXISTS public.tenants (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug          text NOT NULL UNIQUE,
  display_name  text NOT NULL,
  contact_email text,
  contact_phone text,
  location      text,
  plan          text NOT NULL DEFAULT 'free',
  branding      jsonb DEFAULT '{}'::jsonb,
  settings      jsonb DEFAULT '{}'::jsonb,
  created_at    timestamptz DEFAULT now(),
  updated_at    timestamptz DEFAULT now()
);
-- Note: no separate idx_tenants_slug. The UNIQUE(slug) constraint already creates its own
-- backing index; a standalone slug index is redundant (F14). Prod ships clean. This produces
-- a known, intentional one-index parity-diff vs staging (which still carries the redundant
-- idx_tenants_slug) — recorded as the F14 cleanup, to be removed from staging project-wide.
```

**Verify:** `SELECT to_regclass('public.tenants');` → `tenants` (not null).
**Rollback:** `DROP TABLE IF EXISTS public.tenants;` (only after all `tenant_id` columns are dropped — no FKs exist in 4.2, but drop columns first for tidiness).

### C2 — Insert founding tenant

> Replace `<<PROD_TENANT_UUID>>` with the exact UUID from `scripts/phase-4-prod-tenant-uuid.txt`.
> The guard `SELECT` below refuses to proceed if the placeholder was left in.

```sql
INSERT INTO public.tenants (id, slug, display_name)
VALUES ('<<PROD_TENANT_UUID>>', 'rjbookstop', 'Ray & Judy''s Book Stop')
ON CONFLICT (slug) DO NOTHING;
```

**Verify:**
```sql
SELECT id, slug, display_name FROM public.tenants WHERE slug = 'rjbookstop';
-- Expect exactly 1 row; id must equal the scratch-file UUID.
```
**Rollback:** `DELETE FROM public.tenants WHERE slug = 'rjbookstop';`

### C3–C11 — Add `tenant_id`, backfill, index (one block per table)

The pattern is identical for all nine tables. The founding id is resolved by slug subquery so the
UUID literal appears only in C2.

```sql
-- TEMPLATE (do not run; see per-table blocks below)
ALTER TABLE public.<TABLE> ADD COLUMN IF NOT EXISTS tenant_id uuid;
UPDATE public.<TABLE>
   SET tenant_id = (SELECT id FROM public.tenants WHERE slug = 'rjbookstop')
 WHERE tenant_id IS NULL;
CREATE INDEX IF NOT EXISTS idx_<TABLE>_tenant ON public.<TABLE> (tenant_id);
```

Per-table, in execution order (table → expected backfill row count from the pre-cutover snapshot):

| Block | Table | Index name | Backfill rows |
|---|---|---|---|
| C3 | `user_profiles` | `idx_user_profiles_tenant` | 19 |
| C4 | `catalog` | `idx_catalog_tenant` | 6399 |
| C5 | `preorders` | `idx_preorders_tenant` | 680 |
| C6 | `subscriptions` | `idx_subscriptions_tenant` | 3 |
| C7 | `reservation_history` | `idx_reservation_history_tenant` | 81 |
| C8 | `weekly_shipment` | `idx_weekly_shipment_tenant` | 443 |
| C9 | `settings` | `idx_settings_tenant` | 2 |
| C10 | `app_settings` | `idx_app_settings_tenant` | 2 |
| C11 | `usage_events` | `idx_usage_events_tenant` | 373 |

**Per-block verify (run for each `<TABLE>`):**
```sql
SELECT
  (SELECT count(*) FROM public.<TABLE> WHERE tenant_id IS NULL)  AS null_tenant_rows,   -- expect 0
  (SELECT count(*) FROM public.<TABLE>)                          AS total_rows,         -- expect snapshot count
  to_regclass('public.idx_<TABLE>_tenant')                       AS index_present;      -- expect non-null
```

**Per-block rollback:** `ALTER TABLE public.<TABLE> DROP COLUMN IF EXISTS tenant_id;`
(dropping the column drops `idx_<TABLE>_tenant` automatically).

---

## Execution sequence

```
PF1–PF6 pre-flight gates  →  C1  →  C2  →  C3 … C11 (verify after each)  →  V1–V5 + smoke gate
```

Stop on the first verification that doesn't match expected. A failed apply or verify is **Tier 1
rollback** per the parent plan: roll back the in-flight block, leave prior blocks applied,
maintenance mode stays ON, abort the window, post-mortem before retry.

---

## Post-execution verification (V-gates — all green to pass 4.2)

```sql
-- V1: founding tenant exactly once, id == scratch file
SELECT count(*) AS tenant_rows FROM public.tenants;                       -- expect 1
SELECT id FROM public.tenants WHERE slug = 'rjbookstop';                  -- expect scratch UUID

-- V2: tenant_id column present on all 9 tables
SELECT table_name FROM information_schema.columns
WHERE table_schema = 'public' AND column_name = 'tenant_id'
ORDER BY table_name;                                                      -- expect the 9 tables

-- V3: zero unbackfilled rows across all 9 tables
SELECT 'user_profiles' t, count(*) FROM public.user_profiles WHERE tenant_id IS NULL
UNION ALL SELECT 'catalog',             count(*) FROM public.catalog             WHERE tenant_id IS NULL
UNION ALL SELECT 'preorders',           count(*) FROM public.preorders           WHERE tenant_id IS NULL
UNION ALL SELECT 'subscriptions',       count(*) FROM public.subscriptions       WHERE tenant_id IS NULL
UNION ALL SELECT 'reservation_history', count(*) FROM public.reservation_history WHERE tenant_id IS NULL
UNION ALL SELECT 'weekly_shipment',     count(*) FROM public.weekly_shipment     WHERE tenant_id IS NULL
UNION ALL SELECT 'settings',            count(*) FROM public.settings            WHERE tenant_id IS NULL
UNION ALL SELECT 'app_settings',        count(*) FROM public.app_settings        WHERE tenant_id IS NULL
UNION ALL SELECT 'usage_events',        count(*) FROM public.usage_events        WHERE tenant_id IS NULL;
-- expect 0 for every row

-- V4: all 9 tenant indexes exist
SELECT indexname FROM pg_indexes
WHERE schemaname = 'public' AND indexname LIKE 'idx_%_tenant'
ORDER BY indexname;                                                       -- expect the 9 indexes

-- V5: row counts unchanged vs pre-cutover snapshot (additive only — no data movement)
SELECT 'user_profiles' t, count(*) FROM public.user_profiles
UNION ALL SELECT 'catalog',             count(*) FROM public.catalog
UNION ALL SELECT 'preorders',           count(*) FROM public.preorders
UNION ALL SELECT 'subscriptions',       count(*) FROM public.subscriptions
UNION ALL SELECT 'reservation_history', count(*) FROM public.reservation_history
UNION ALL SELECT 'weekly_shipment',     count(*) FROM public.weekly_shipment
UNION ALL SELECT 'settings',            count(*) FROM public.settings
UNION ALL SELECT 'app_settings',        count(*) FROM public.app_settings
UNION ALL SELECT 'usage_events',        count(*) FROM public.usage_events;
-- expect: 19 / 6399 / 680 / 3 / 81 / 443 / 2 / 2 / 373
```

**Smoke gate (manual, maintenance mode still ON):** load the prod site as admin — pages render,
no console errors, maintenance banner shows for non-admin. No customer-facing behavior change is
expected from 4.2 (additive columns only).

---

## Completion criteria

- [ ] PF1–PF6 all passed
- [ ] C1–C11 applied without error
- [ ] V1: `tenants` has exactly 1 row; id matches scratch file
- [ ] V2: `tenant_id` present on all 9 tables
- [ ] V3: zero `tenant_id IS NULL` rows across all 9 tables
- [ ] V4: all 9 `idx_*_tenant` indexes present
- [ ] V5: row counts match the pre-cutover snapshot exactly
- [ ] Smoke gate green
- [ ] Parent-plan Sub-Deploys table: 4.2 row → status updated for the window checkpoint
- [ ] Proceed to 4.3 (constraints) — next window step

---

## Housekeeping (doc-only commit to `staging`, non-blocking for prod SQL)

Bundle as one doc-only commit to `staging` (not the cutover branch), before the window:

1. Commit `docs/production-baseline-2026-05-28.md`.
2. `CLAUDE.md` line 19 — confirm the baseline filename reference matches the committed name.
3. `CLAUDE.md` — replace "production has 7 tables" phrasing with "9 base tables; only `tenants`
   and `tenant_id` columns missing."
4. `phase-4-production-migration.md` § In Scope line 142 — rewrite "create `app_settings` /
   `usage_events`" → "add `tenant_id` to all 9 existing tables (both already exist on prod)."
5. `phase-4-production-migration.md` carry-forward item 9 — mark corrected (the table gap does
   not exist).
6. `phase-4-production-migration.md` § In Scope line 148 — note analytics views and
   `admin_preorders` already exist; 4.4 retrofits rather than creates.

---

## Carry-forward (into 4.3 / 4.4 / 4.5)

- **4.3:** `tenant_id → tenants(id) ON DELETE CASCADE` FKs (all 9); `NOT NULL` promotion (all 9);
  tenant-aware unique keys on `catalog` and `subscriptions`; `tenants_slug_format_check`;
  `admin_preorders` recreation; RLS recursion fix across **7** policies (baseline PB3, broader
  than the parent plan's single-policy mention); reconcile `is_admin()` vs
  `current_user_is_admin()` — **fetch `is_admin()` body live** before drafting.
- **4.4:** analytics views already exist → retrofit with `current_tenant_id()`, not create
  (baseline PB2); fetch live bodies/signatures of `archive_stale_reservations`,
  `delete_dropped_catalog_items`, `purge_stale_catalog` before drafting the signature changes.
- **4.5/4.6:** create the missing PRH `weekly_shipment` partial unique index before the first
  real prod import (baseline PB4); set `import.js` `TENANT_ID` to the scratch-file UUID.
- **F14:** prod 4.2 ships **without** `idx_tenants_slug` (redundant with `UNIQUE(slug)`). Staging
  still carries it — a known, intentional one-index parity-diff. Cleanup = drop it from staging
  project-wide (deferred, post-cutover).

---

## Reference

- Baseline: `docs/production-baseline-2026-05-28.md`
- Parent plan: `docs/phase-4-production-migration.md`
- Staging schema (parity target): `docs/technical-reference.md` § 4
- Runbook (mechanical execution): `docs/phase-4.2-runbook.md`
- Founding UUID (prod): `scripts/phase-4-prod-tenant-uuid.txt` (gitignored)
- Founding admin: `734bfd7e-23a6-4c23-ba35-1f64843603c0` ("Book Stop")
