-- STATUS: staging=APPLIED 2026-08-18 | prod=APPLIED 2026-08-20
--         F115 tri-state arrival_outcome column on preorders.
--         Staging verified live: column text/nullable/no-default, CHECK
--         constraint matches (ARRAY['arrived','not_arrived','unknown']),
--         bogus-value UPDATE correctly rejected 23514 then rolled back clean.
--         PRODUCTION verified live 2026-08-20, same four checks: pre-check 0
--         rows; column text/YES/null; CHECK present; 0 non-null over 2,020
--         rows; bogus UPDATE rejected 23514 on constraint
--         "preorders_arrival_outcome_check". The 23514 DETAIL carried
--         tenant_id 20941129-... (the PRODUCTION founding tenant), which
--         independently confirms the run happened in the prod project and
--         not in an already-open staging tab -- the one real risk here.
--         Run EARLY, ahead of the September import session, deliberately:
--         admin.html on staging selects this column, so until production had
--         it, ANY staging->main promotion would 400 the whole admin gather
--         (see /promote-prod step 0b). Applying it early is inert -- every
--         row reads NULL and no production code reads the column yet -- and
--         it both clears that block and removes a dependency from S5/S6.
-- (F105) This line is the applied-state record. A gate that lives only in
-- prose gets missed -- F6 sat unapplied on production for 13 days because
-- nothing machine-readable said so. Update it the moment you run this file.
-- ============================================================================
-- preorders: one additive nullable column, arrival_outcome
-- Prepared 2026-08-18 (F115 arrival-truth-persistence session, S2).
-- Plan: docs/f115-arrival-truth-persistence.md § 3.1, § 4 S2.
-- Run: STAGING first (this file targets staging). Production is a separate,
--      later run at Rick's explicit call -- not part of this run.
-- Operator: Rick (Supabase SQL Editor, runs as postgres superuser).
--
-- WHY THIS COLUMN EXISTS:
--   auto_fulfill_past_on_sale() (docs/sql/auto_fulfill_past_on_sale.sql) sets
--   fulfilled = true for every preorder past its on_sale_date, with no arrival
--   check -- a title that never showed up is marked identically to one that
--   did (F115). This column lets the import record, at the moment it makes
--   that judgement, WHETHER shipment evidence backed it up:
--     'arrived'      -- F76 three-key shipment match found (catalog_id / upc
--                        / item_code) -- the fulfillment is evidenced.
--     'unknown'      -- no shipment evidence at judgement time. NOT proof the
--                        book never came (F84: label inversions, invoices
--                        missing a line, books handed over the counter) --
--                        just that nothing on file confirms it either way.
--     'not_arrived'  -- reserved for a human who has actually established
--                        non-arrival. NEVER written by the import. Writing it
--                        automatically would recreate F115 with a nicer label.
--
-- DESIGN NOTES:
--   - Additive, nullable, no default, no backfill in this file -- every
--     existing row reads NULL after this migration. NULL means "not yet
--     judged" and is DISTINCT from 'unknown' ("judged, evidence does not
--     settle it") -- do not collapse the two. S6 is the separate, later step
--     that backfills the historical 28/23 rows to 'unknown', not this one.
--   - CHECK constraint enforces the tri-state at the database level, not just
--     in application code -- a stray write of anything else fails loud.
--   - No RLS change: mutation continues through the existing `admins manage
--     tenant preorders` (service-role / admin) and `users manage own
--     preorders` policies already on this table (technical-reference.md
--     § 7.1) -- this is a plain additive column on an existing table, no new
--     policy needed for the import (service-role) or admin-panel (admin
--     policy) write paths this column needs.
-- ============================================================================

-- Pre-check: confirm the column does not already exist
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'preorders'
  AND column_name = 'arrival_outcome';
-- Expected: 0 rows

BEGIN;

ALTER TABLE public.preorders
  ADD COLUMN arrival_outcome text
  CHECK (arrival_outcome IN ('arrived', 'not_arrived', 'unknown'));

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
WHERE table_schema = 'public' AND table_name = 'preorders'
  AND column_name = 'arrival_outcome';
-- Expected: 1 row -- arrival_outcome | text | YES | (null)

-- 2. CHECK constraint is present and matches the tri-state
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'public.preorders'::regclass
  AND contype = 'c'
  AND pg_get_constraintdef(oid) ILIKE '%arrival_outcome%';
-- Expected: 1 row -- CHECK ((arrival_outcome = ANY (ARRAY['arrived'::text, 'not_arrived'::text, 'unknown'::text])))

-- 3. Every existing row reads NULL (no backfill happened in this migration)
SELECT
  count(*) FILTER (WHERE arrival_outcome IS NOT NULL) AS non_null_arrival_outcome,
  count(*) AS total_rows
FROM public.preorders;
-- Expected: non_null_arrival_outcome = 0; total_rows = the live row count

-- 4. A bad value is rejected (run in a throwaway transaction, then roll back --
--    do NOT commit this one)
BEGIN;
UPDATE public.preorders SET arrival_outcome = 'bogus' WHERE id = (SELECT id FROM public.preorders LIMIT 1);
-- Expected: ERROR 23514 check constraint "preorders_arrival_outcome_check" violated
ROLLBACK;
