-- STATUS: staging=APPLIED 2026-08-20 | prod=APPLIED 2026-08-21
--         Staging verified: 0 non-null / 9,589, then populated live by a
--         real import 2026-08-21. Production verified: 0 non-null / 11,726
--         total (Rick, SQL Editor). Matches "no backfill" by design on both
--         — populates on the next import for each environment.
-- ============================================================================
-- catalog: one additive nullable column, order_requirement
-- Prepared 2026-08-20 (F132 order-restriction alert+badge scoping session).
-- Plan: docs/order-restriction-alert-badge.md § 2, runbook S1 (staging),
--       S8 (production).
-- Run: STAGING already applied 2026-08-20 (see STATUS). THIS RUN targets
--      PRODUCTION — same file, same DDL, different project. Confirm you are
--      in the production Supabase project (plgegklqtdjxeglvyjte) before
--      running, not an already-open staging tab — see the F115 migration's
--      note on exactly this risk.
-- Operator: Rick (Supabase SQL Editor, runs as postgres superuser).
--
-- WHY THIS RUN MATTERS BEYOND THE BADGE: production's import.js (scripts
-- repo, already updated with the F132 normalizer changes) will 400 with
-- PGRST204 "column not found" on EVERY catalog upsert -- not just the
-- restricted rows -- if it runs before this column exists on production.
-- This migration must land before the next production import, independent
-- of when the client-code promotion happens.
--
-- WHY THIS COLUMN EXISTS:
--   PRH's OrderRequirement column (879 rows, 2026-08-20 file) flags 133 rows
--   (15%) with a distributor allocation ratio like '1:10' -- the store is not
--   guaranteed to receive a copy for every reservation. Today nothing records
--   this at reservation time; the customer only learns via the retrospective
--   F117/F120 rejected-badge mechanism, after the distributor has already
--   declined the order. This column persists the raw ratio so the catalog
--   page can show a predictive badge ahead of that outcome (F132).
--
-- DESIGN NOTES:
--   - Additive, nullable, no default, no backfill in this file -- every
--     existing row reads NULL after this migration, and stays NULL until the
--     next PRH import writes it (~Sept 7-10 cycle). Inert until then: no app
--     code reads this column until the badge ships, and `.select('*')`
--     against a row missing the key simply omits it -- same additive-safe
--     shape as F115's arrival_outcome.
--   - No CHECK constraint. Unlike F115's tri-state, this stores PRH's raw
--     ratio string ('1:10', '1:25', ...) verbatim -- the values are open-set
--     and distributor-defined, not an app-owned enum.
--   - Lunar rows always write explicit NULL (no equivalent field in Lunar's
--     feed) -- per F123, the normalizer MUST still emit the key as an explicit
--     null, not omit it, or the batch spanning the Lunar/PRH boundary in one
--     upsert call fails PostgREST's one-key-shape rule.
--   - No RLS change: plain additive column on an existing table, covered by
--     catalog's existing read policies -- no new policy needed.
-- ============================================================================

-- Pre-check: confirm the column does not already exist
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'catalog'
  AND column_name = 'order_requirement';
-- Expected: 0 rows

BEGIN;

ALTER TABLE public.catalog
  ADD COLUMN order_requirement text;

COMMIT;

-- ----------------------------------------------------------------------------
-- Post-DDL verification (run these, confirm the shapes below before telling
-- the agent to proceed -- feedback_supabase_sql_editor_set_local records that
-- BEGIN + SET LOCAL + ROLLBACK has failed here before with 25P02, so these are
-- plain superuser SELECTs, not a transactional probe).
-- ----------------------------------------------------------------------------

-- 1. Column exists with the expected type/nullability/default
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'catalog'
  AND column_name = 'order_requirement';
-- Expected: 1 row -- order_requirement | text | YES | (null)

-- 2. No CHECK constraint was accidentally added (open-set values, not an enum)
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'public.catalog'::regclass
  AND contype = 'c'
  AND pg_get_constraintdef(oid) ILIKE '%order_requirement%';
-- Expected: 0 rows

-- 3. Every existing row reads NULL (no backfill happened in this migration)
SELECT
  count(*) FILTER (WHERE order_requirement IS NOT NULL) AS non_null_order_requirement,
  count(*) AS total_rows
FROM public.catalog;
-- Expected: non_null_order_requirement = 0; total_rows = the live PRODUCTION
-- row count (~11,724 as of 2026-08-10 per technical-reference.md SS 4.3 --
-- will differ, re-verify against whatever total_rows this query actually
-- returns, don't compare against the staging 9,589 figure from the S1 run)
