-- STATUS: staging=APPLIED 2026-08-20 | prod=APPLIED 2026-08-21
--         Staging verified live (Rick, SQL Editor): pre-check confirmed the
--         constraint was still the original tri-state before this ran; DDL
--         applied clean; row-count check showed 54 null / 2 arrived / 0
--         damaged / 0 not_arrived (no row touched by the widening); a
--         'damaged' write succeeded inside a rolled-back transaction; a
--         bogus value was rejected 23514 on "preorders_arrival_outcome_check"
--         (DETAIL line confirmed the founding tenant id, i.e. this really ran
--         against staging).
--         Production verified live (Rick, SQL Editor, 2026-08-21): a bogus
--         value rejected 23514 (DETAIL line carried tenant_id
--         20941129-c35a-476d-ae21-44b8f77af89c, the PRODUCTION founding
--         tenant — confirms the run happened in the prod project, same
--         cross-check F115's own prod migration used) — but a bogus-value
--         rejection alone cannot distinguish the widened constraint from
--         the original tri-state, since 'bogus' fails either way. The
--         constraint-definition query was run as the actual proof:
--         CHECK ((arrival_outcome = ANY (ARRAY['arrived'::text,
--         'not_arrived'::text, 'damaged'::text, 'unknown'::text]))) —
--         confirmed 'damaged' is now in the allowed set on production.
--         Client promotion (admin.html/app.js/mylist.html to main) is a
--         SEPARATE, later step — this file only covers the DB half.
-- ============================================================================
-- preorders: widen the arrival_outcome CHECK to add 'damaged'
-- Prepared 2026-08-21 (F134 arrival-resolution session, Part 2a).
-- Plan: docs/f134-arrival-resolution.md § 4.1, gate V3.
-- Run: STAGING first (this file targets staging). Production is a separate,
--      later run at Rick's explicit call — not part of this run.
-- Operator: Rick (Supabase SQL Editor, runs as postgres superuser).
--
-- WHY THIS WIDENING EXISTS:
--   F115's tri-state ('arrived','not_arrived','unknown') has no way to
--   express "arrived, but unusable". A damaged book DID arrive, so
--   'not_arrived' is false; the customer cannot have it, so 'arrived' is a
--   lie. Squashing it into either state is exactly the false confidence the
--   tri-state was built to avoid (F134 § 4.1). 'damaged' is a deliberate
--   fourth state, not a convenience default.
--
--   This migration also, for the first time, gives 'not_arrived' a writer:
--   F134 Part 2b adds an admin-only resolve control (Received / Didn't
--   arrive / Damaged) that writes this column directly. Before Part 2b ships,
--   'not_arrived' remains unreachable exactly as it was before this file ran
--   — widening the CHECK alone writes nothing and changes no existing row.
--
-- DESIGN NOTES:
--   - Additive to the VALUE SET only — no column type, nullability, or
--     default changes. Every existing row (all currently 'arrived',
--     'unknown', or NULL — 'not_arrived' has never been written) continues
--     to satisfy the widened CHECK unmodified. Safe to land ahead of the
--     client that will start writing 'damaged' and 'not_arrived'.
--   - Implemented as DROP + re-ADD of the same-named CHECK, the only way to
--     widen a CHECK's allowed set in Postgres — there is no ALTER CHECK.
--     Constraint name (`preorders_arrival_outcome_check`) confirmed live via
--     pg_constraint in the F115 migration's own post-DDL verification
--     (docs/sql/f115-arrival-outcome.sql, step 2) — not guessed.
--   - No RLS change: same admin/self-service write paths F115 already
--     covers (technical-reference.md § 7.1) — this widens what value those
--     existing policies may write, not who may write it.
-- ============================================================================

-- Pre-check: confirm the CURRENT (pre-widen) constraint definition, so the
-- diff below is provable rather than assumed.
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'public.preorders'::regclass
  AND contype = 'c'
  AND conname = 'preorders_arrival_outcome_check';
-- Expected: 1 row — CHECK ((arrival_outcome = ANY (ARRAY['arrived'::text, 'not_arrived'::text, 'unknown'::text])))

BEGIN;

ALTER TABLE public.preorders
  DROP CONSTRAINT preorders_arrival_outcome_check;

ALTER TABLE public.preorders
  ADD CONSTRAINT preorders_arrival_outcome_check
  CHECK (arrival_outcome IN ('arrived', 'not_arrived', 'damaged', 'unknown'));

COMMIT;

-- ----------------------------------------------------------------------------
-- Post-DDL verification (run these, confirm the shapes below before telling
-- the agent to proceed — feedback_supabase_sql_editor_set_local records that
-- BEGIN + SET LOCAL + ROLLBACK has failed here before with 25P02, so these are
-- plain superuser SELECTs, not a transactional probe).
-- ----------------------------------------------------------------------------

-- 1. CHECK constraint now includes 'damaged'
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'public.preorders'::regclass
  AND contype = 'c'
  AND conname = 'preorders_arrival_outcome_check';
-- Expected: 1 row — CHECK ((arrival_outcome = ANY (ARRAY['arrived'::text, 'not_arrived'::text, 'damaged'::text, 'unknown'::text])))

-- 2. No existing row was affected — same non-null/total counts as before this
--    migration ran (compare against the live count you see, not a recorded
--    figure — this file makes no claim about what that count should be).
SELECT
  arrival_outcome, count(*) AS n
FROM public.preorders
GROUP BY arrival_outcome
ORDER BY arrival_outcome NULLS FIRST;
-- Expected: no 'damaged' rows yet (nothing has written one); every other
-- bucket's count identical to before this migration ran.

-- 3. 'damaged' is now accepted (run in a throwaway transaction, then roll
--    back — do NOT commit this one)
BEGIN;
UPDATE public.preorders SET arrival_outcome = 'damaged' WHERE id = (SELECT id FROM public.preorders LIMIT 1);
-- Expected: UPDATE 1, no error
ROLLBACK;

-- 4. A bogus value is still rejected (gate V3's other half — widening must
--    not have accidentally opened the column to arbitrary text)
BEGIN;
UPDATE public.preorders SET arrival_outcome = 'bogus' WHERE id = (SELECT id FROM public.preorders LIMIT 1);
-- Expected: ERROR 23514 check constraint "preorders_arrival_outcome_check" violated
ROLLBACK;
