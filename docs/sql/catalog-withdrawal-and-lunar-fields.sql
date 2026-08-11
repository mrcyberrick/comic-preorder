-- STATUS: staging=APPLIED 2026-08-03 | prod=APPLIED 2026-08-03
--         F110/F112 four additive nullable columns.
-- (F105) This line is the applied-state record. A gate that lives only in
-- prose gets missed -- F6 sat unapplied on production for 13 days because
-- nothing machine-readable said so. Update it the moment you run this file.
-- ============================================================================
-- catalog: four additive columns for withdrawal detection (F110) and Lunar
-- distributor-model fields (F112(a))
-- Prepared 2026-08-03 (order-export follow-through session, Session A).
-- Plan: docs/order-export-followthrough-f110-f111-f112.md § 4.1, § 4.2, § 6 S-A1.
-- Run: STAGING first (this file targets staging). Production is a separate,
--      later run at Rick's explicit call (S-A4) — not part of this run.
-- Operator: Rick (Supabase SQL Editor, runs as postgres superuser).
--
-- WHY THESE COLUMNS EXIST:
--   F112(a) — Lunar's product file carries an InitialOrderDue deadline and a
--     TitleNote free-text risk field, both currently read by nothing. Stored
--     per row, never aggregated (the file has known-bad InitialOrderDue typo
--     rows — see the import-script window guard). PRH publishes neither, so
--     PRH rows leave both NULL.
--   F110 — a title withdrawn upstream by the distributor is invisible today:
--     it is simply absent from next month's file, not flagged. withdrawn_at
--     records when the import script's cross-month set difference detected
--     the withdrawal; withdrawn_last_seen_month records which catalog_month
--     it was last present in, for the admin panel and My List (Session B).
--
-- DESIGN NOTES:
--   - All four columns are additive, nullable, no default, no backfill —
--     every existing row reads NULL after this migration and nothing existing
--     reads them yet (Session B is what adds consumers).
--   - withdrawn_at IS NULL means "not withdrawn" — this is why no backfill
--     is needed for correctness on existing rows.
--   - No RLS change: catalog has no INSERT/UPDATE/DELETE policy today
--     (service-role-only mutation via the import script per
--     technical-reference.md § 4.3 Notes) and these are plain additive
--     columns on an existing table, so the existing SELECT policy for
--     authenticated users already covers them with no new grant needed.
-- ============================================================================

-- Pre-check: confirm none of the four columns already exist
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'catalog'
  AND column_name IN ('initial_order_due', 'title_note', 'withdrawn_at', 'withdrawn_last_seen_month');
-- Expected: 0 rows

BEGIN;

ALTER TABLE public.catalog ADD COLUMN initial_order_due date;
ALTER TABLE public.catalog ADD COLUMN title_note text;
ALTER TABLE public.catalog ADD COLUMN withdrawn_at timestamptz;
ALTER TABLE public.catalog ADD COLUMN withdrawn_last_seen_month text;

COMMIT;

-- ----------------------------------------------------------------------------
-- Post-DDL verification (run these, confirm the shapes below before telling
-- the agent to proceed — feedback_supabase_sql_editor_set_local records that
-- BEGIN + SET LOCAL + ROLLBACK has failed here before with 25P02, so these are
-- plain superuser SELECTs, not a transactional probe).
-- ----------------------------------------------------------------------------

-- 1. All four columns exist with the expected types/nullability/defaults
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'catalog'
  AND column_name IN ('initial_order_due', 'title_note', 'withdrawn_at', 'withdrawn_last_seen_month')
ORDER BY column_name;
-- Expected: 4 rows —
--   initial_order_due         | date         | YES | (null)
--   title_note                | text         | YES | (null)
--   withdrawn_at               | timestamp with time zone | YES | (null)
--   withdrawn_last_seen_month  | text         | YES | (null)

-- 2. Every existing row reads NULL on all four (no backfill happened)
SELECT
  count(*) FILTER (WHERE initial_order_due IS NOT NULL)        AS non_null_initial_order_due,
  count(*) FILTER (WHERE title_note IS NOT NULL)               AS non_null_title_note,
  count(*) FILTER (WHERE withdrawn_at IS NOT NULL)              AS non_null_withdrawn_at,
  count(*) FILTER (WHERE withdrawn_last_seen_month IS NOT NULL) AS non_null_withdrawn_last_seen_month,
  count(*) AS total_rows
FROM public.catalog;
-- Expected: all four non_null_* counts = 0; total_rows = the live row count

-- 3. Confirm catalog is still service-role-only for mutations (no RLS change
--    needed — this just re-verifies the existing posture rather than assuming it)
SELECT relrowsecurity, relforcerowsecurity
FROM pg_class
WHERE oid = 'public.catalog'::regclass;

SELECT polname, polcmd, polroles::regrole[]
FROM pg_policy
WHERE polrelid = 'public.catalog'::regclass;
-- Expected: RLS enabled; policies present only for SELECT (authenticated) —
-- no INSERT/UPDATE/DELETE policy, matching technical-reference.md § 4.3 Notes.
