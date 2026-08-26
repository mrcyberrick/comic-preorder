-- STATUS: COMPLETE | staging=APPLIED 2026-08-26 (24 total / 0 with_phone) | prod=APPLIED 2026-08-26 (30 total / 0 with_phone) | findings=none (feature build, not a defect)
--
-- Add an editable phone number to customer accounts, per Rick's request
-- 2026-08-26. Displayed + edited on admin.html Customers > Accounts (the
-- Edit Account modal); no other page reads or writes it.
--
-- No RLS change needed: `user_profiles` already carries the
-- `admins manage tenant profiles` ALL policy (F58, both environments), which
-- covers UPDATE of any column on the table, this one included. Verify that
-- assumption below before running the ALTER, rather than trusting this
-- comment against a live system that may have drifted.
--
-- Run on STAGING first. Do not run on production until the client code
-- (app.js Users.setProfile, admin.html Edit Account modal) is verified via
-- run-smoke.ps1 and Rick confirms promotion via /promote-prod.

-- =====================================================================
-- PRE-FLIGHT (read-only) — confirm the column doesn't already exist and
-- confirm the admin ALL policy this migration relies on is actually present.
-- =====================================================================
SELECT column_name FROM information_schema.columns
WHERE  table_schema = 'public' AND table_name = 'user_profiles'
ORDER  BY ordinal_position;
-- EXPECTED: no `phone` row yet.

SELECT policyname, cmd, roles FROM pg_policies
WHERE  schemaname = 'public' AND tablename = 'user_profiles'
ORDER  BY policyname;
-- STOP AND COMPARE: must include 'admins manage tenant profiles' with
-- cmd = ALL. If absent, this migration is safe to run (ADD COLUMN itself
-- needs no policy), but the app's admin-write path (Users.setProfile) will
-- fail until that policy exists — see F58.

-- =====================================================================
-- MIGRATION
-- =====================================================================
BEGIN;

ALTER TABLE user_profiles ADD COLUMN phone text;

COMMIT;

-- =====================================================================
-- POST-CHECK (read-only) — must show the new column, nullable, no default,
-- and every existing row NULL (an ADD COLUMN with no DEFAULT never
-- backfills existing rows in Postgres, so this is not a maybe).
-- =====================================================================
SELECT column_name, data_type, is_nullable, column_default
FROM   information_schema.columns
WHERE  table_schema = 'public' AND table_name = 'user_profiles' AND column_name = 'phone';
-- EXPECTED: phone | text | YES | (null)

SELECT count(*) AS total, count(phone) AS with_phone
FROM   user_profiles;
-- EXPECTED: with_phone = 0 immediately after this migration on both
-- environments (no prior data source for phone numbers exists).
