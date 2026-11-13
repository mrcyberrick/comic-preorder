-- STATUS: staging=APPLIED 2026-11-13 | prod=APPLIED 2026-11-13
--         Applied by Rick on STAGING and then PRODUCTION in the same sitting, 2026-11-13, before any
--         code that reads these columns merged (docs/customer-engagement-paper-to-app.md S1, "SQL
--         sequencing"). Both pasted result rows read verdict 'OK - 2 nullable columns present, no
--         default, authenticated can read them', authenticated_can_update_new_columns = true, and no
--         triggers on user_profiles. The own-profile UPDATE policy read live as documented in
--         technical-reference.md section 7.1 (row-level, USING auth.uid() = id), so a customer can
--         write these two columns on their OWN row; low stakes, not narrowed. Production's
--         `admins manage tenant profiles` carries an explicit WITH CHECK, staging's does not
--         (the benign divergence already recorded in section 13).
-- (F105) /promote-prod step 0 matches prod=(APPLIED|N/A): while this reads PENDING it blocks every
-- production promotion, so do not leave it that way.
-- ============================================================================
-- Paper-customer conversion: user_profiles.converted_from_paper_at, user_profiles.signup_source
--
-- Plan: docs/customer-engagement-paper-to-app.md, step S1 item 1. Prepared 2026-11-13.
-- Run: STAGING FIRST, then PRODUCTION, same sitting. Operator: Rick (Supabase SQL Editor).
-- Paste the WHOLE file and press Run once: the Editor shows only the LAST statement's result,
-- so the file ends with ONE result row that covers everything above it.
--
-- WHY: converting a paper customer to an app customer (the new Invite... button) needs a durable
--   record that it happened. Today a conversion leaves no trace (F89), and usage_events are purged
--   at 90 days (F90), so the stamp has to live on the profile. signup_source is the second half of
--   the same measurement: where a new account came from. S1 only writes converted_from_paper_at
--   (and leaves signup_source NULL); S2 starts filling signup_source.
--
-- WHAT IT DOES: adds two NULLABLE columns, no default, so every existing row reads NULL and no
--   row is rewritten. converted_from_paper_at timestamptz; signup_source text (free text for now,
--   no CHECK: S2 owns the allowlist).
-- WHAT IT DOES NOT DO: no RLS change (the existing `admins manage tenant profiles` ALL policy
--   already covers every column), no grant change (the phone column was added the same way,
--   2026-08-26, with none), no function, no data change.
--
-- ONE THING TO READ FROM THE RESULT (the plan's "check at execution" item): the existing
--   `users update own profile` policy is documented as UPDATE where auth.uid() = id, with no column
--   restriction. If that is true, a customer can write these two columns on THEIR OWN row. The stakes
--   are low (it can only falsify their own conversion stamp and source), and it is NOT narrowed here.
--   The result row below prints the live UPDATE-capable policies, the triggers on the table and the
--   column-level UPDATE privilege, so the question is answered from the live database and not from
--   the doc's snapshot. (This file was written before that live read; the doc was the only source.)
-- ============================================================================

BEGIN;

ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS converted_from_paper_at timestamptz,
  ADD COLUMN IF NOT EXISTS signup_source           text;

COMMIT;

-- ROLLBACK, if ever needed (nothing reads the columns until the S1 code ships):
--   ALTER TABLE public.user_profiles DROP COLUMN IF EXISTS converted_from_paper_at,
--                                    DROP COLUMN IF EXISTS signup_source;


-- ── RESULT (the one row to paste back) ──────────────────────────────────────
-- One aggregate row, so a missing column cannot read as "Success. No rows returned".
-- `verdict` is the pass/fail. The other columns are information to paste back, not checks.
--
-- Nothing below names a new column outside a branch that only runs once both exist, so if the
-- ALTER above did not land this still returns a readable PROBLEM row instead of an error.
--
-- EXPECTED: verdict = 'OK - 2 nullable columns present, no default, authenticated can read them'
WITH cols AS (
  SELECT column_name, data_type, is_nullable, column_default
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'user_profiles'
    AND column_name IN ('converted_from_paper_at', 'signup_source')
), pol AS (
  SELECT string_agg(
           policyname || ' [' || cmd || ' to ' || array_to_string(roles, '/') || '] USING '
             || coalesce(qual, '-') || ' CHECK ' || coalesce(with_check, '-'),
           ' ;; ' ORDER BY policyname) AS s
  FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'user_profiles' AND cmd IN ('UPDATE', 'ALL')
), trg AS (
  SELECT coalesce(string_agg(tgname, ', ' ORDER BY tgname), '(none)') AS s
  FROM pg_trigger
  WHERE tgrelid = 'public.user_profiles'::regclass AND NOT tgisinternal
)
SELECT
  CASE
    WHEN (SELECT count(*) FROM cols) <> 2
      THEN 'PROBLEM - expected 2 new columns, found ' || (SELECT count(*) FROM cols) || '. Re-run this file from the top.'
    WHEN (SELECT count(*) FROM cols WHERE is_nullable = 'YES' AND column_default IS NULL
            AND ((column_name = 'converted_from_paper_at' AND data_type = 'timestamp with time zone')
              OR (column_name = 'signup_source'           AND data_type = 'text'))) <> 2
      THEN 'PROBLEM - a new column has the wrong type, is NOT NULL, or has a default'
    WHEN NOT has_column_privilege('authenticated', 'public.user_profiles', 'converted_from_paper_at', 'SELECT')
      OR NOT has_column_privilege('authenticated', 'public.user_profiles', 'signup_source', 'SELECT')
      THEN 'PROBLEM - authenticated cannot SELECT a new column (a select that names it would fail)'
    ELSE 'OK - 2 nullable columns present, no default, authenticated can read them'
  END AS verdict,
  CASE WHEN (SELECT count(*) FROM cols) = 2 THEN
    has_column_privilege('authenticated', 'public.user_profiles', 'converted_from_paper_at', 'UPDATE')
    AND has_column_privilege('authenticated', 'public.user_profiles', 'signup_source', 'UPDATE')
  END AS authenticated_can_update_new_columns,
  (SELECT s FROM pol) AS update_capable_policies_on_user_profiles,
  (SELECT s FROM trg) AS triggers_on_user_profiles;


-- ── SMOKE ───────────────────────────────────────────────────────────────────
-- Not runnable here: the Editor runs as postgres and bypasses RLS. Behavioural checks run as real
-- signed-in users outside the Editor, from the local harness convert-paper-s1-verify.mjs: an admin
-- converts a paper customer and both columns read back; a customer's own-row write of the two
-- columns is tried and its result recorded in the plan's section 6.
