-- STATUS: staging=APPLIED 2026-10-05 (Rick; pre-flight already_present 0, preorders_columns 10; post-check unavailable_dismissed_at | timestamp with time zone | YES | null, total_preorders 97, cleared 0) | prod=PENDING
--         F163 follow-up: an admin can CLEAR a card from My List's "No longer coming" section without
--         deleting the reservation. mylist.html (on staging) reads and writes this column and FAILS OPEN
--         if it is absent, so deploy order cannot break the page, but /promote-prod step 0 blocks until
--         prod=APPLIED, which is the intended gate: without it the Clear button does nothing on production.
-- (F105) This line is the applied-state record. Update it the moment you run this on production, with the
--         post-check numbers (production read 3,573 preorders on 2026-10-04; cleared must be 0).
-- Design and the decisions behind it: docs/f163-never-arrived-customer-surface.md § 16.
-- Pre-flight (3) on staging listed get_publisher_reserve_counts (a read-only count RPC) and the admin_preorders view
-- (explicit column list, no caller); neither copies preorders rows wholesale, and archive_stale_reservations was NOT
-- flagged. Re-run the pre-flight on production: it is not the same database.
-- ============================================================================
-- preorders: one additive nullable column, unavailable_dismissed_at   (F163 follow-up, prepared 2026-10-05)
-- Run on STAGING first, in the Supabase SQL Editor (postgres superuser). Production is a separate, later run.
--   NULL          = not cleared (every existing row; the card shows if it otherwise qualifies)
--   a timestamptz = an admin cleared the notice at that moment; the card is hidden
-- Additive, nullable, NO default, NO backfill: a metadata-only change in Postgres (no rewrite), every row reads NULL.
-- PURELY PRESENTATIONAL: nothing but mylist.html will read it. No RLS change (`admins manage tenant preorders` is the
-- admin write path; `users manage own preorders` is also ALL, so a hand-crafted customer request could set or clear it
-- on their own rows: the F127 "UI gate" class, accepted).

-- ===== PRE-FLIGHT (read-only). Run as one paste; each result set is shown. =====
-- (1) The column must NOT already exist.
SELECT count(*) FILTER (WHERE column_name = 'unavailable_dismissed_at') AS already_present,
       count(*)                                                        AS preorders_columns
FROM   information_schema.columns
WHERE  table_schema = 'public' AND table_name = 'preorders';
-- EXPECTED: already_present = 0. If 1, STOP: it was already run; go to the POST-CHECK.

-- (2) The two write paths must exist.
SELECT policyname, cmd FROM pg_policies
WHERE  schemaname = 'public' AND tablename = 'preorders' ORDER BY policyname;
-- EXPECTED: includes 'admins manage tenant preorders' (ALL) and 'users manage own preorders' (ALL).

-- (3) Anything that copies preorders rows WHOLESALE would pick up (or choke on) a new column.
SELECT 'function' AS kind, p.proname AS name
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public' AND p.prokind = 'f'
  AND  pg_get_functiondef(p.oid) ~* '\mpreorders\M'
  AND  pg_get_functiondef(p.oid) ~* '(\mp\.\*|\mpreorders\.\*|select\s+\*|row_to_json|to_jsonb)'
UNION ALL
SELECT 'view', c.relname
FROM   pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE  n.nspname = 'public' AND c.relkind IN ('v', 'm') AND pg_get_viewdef(c.oid) ~* '\mpreorders\M'
ORDER  BY 1, 2;
-- EXPECTED: review each row. STOP AND REPORT if any copies a preorders row into another table without an explicit
-- column list (archive_stale_reservations is the one to look at). Empty, or only functions that merely READ, is clean.

-- ===== MIGRATION =====
BEGIN;
ALTER TABLE public.preorders ADD COLUMN unavailable_dismissed_at timestamptz;
COMMENT ON COLUMN public.preorders.unavailable_dismissed_at IS
  'F163: set when an admin clears this reservation''s notice from the customer''s My List "No longer coming" section. Presentational only: hides the card, changes nothing else. NULL = not cleared.';
COMMIT;

-- ===== POST-CHECK (read-only) =====
-- (1) Exists, nullable, no default.
SELECT column_name, data_type, is_nullable, column_default
FROM   information_schema.columns
WHERE  table_schema = 'public' AND table_name = 'preorders' AND column_name = 'unavailable_dismissed_at';
-- EXPECTED: unavailable_dismissed_at | timestamp with time zone | YES | (null).  ZERO rows = the ALTER did not land.
-- (2) Nothing backfilled, no rows lost.
SELECT count(*) AS total_preorders, count(unavailable_dismissed_at) AS cleared FROM public.preorders;
-- EXPECTED: cleared = 0, and total_preorders equals what it was before (production read 3,573 on 2026-10-04).
