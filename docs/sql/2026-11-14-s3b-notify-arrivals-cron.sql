-- STATUS: staging=N/A (staging never gets the schedule — test fixtures with made-up
--                      addresses would bounce and hurt the pulllist.app sender, F152;
--                      exercised by hand there with dry_run and a stubbed Resend)
--         ⚠️ F183 (2026-11-17): pg_net was NOT installed by this file's run, so the first scheduled
--         run failed; fixed by docs/sql/2026-11-17-f183-pg-net-arrivals-cron-fix.sql (prod=APPLIED).
--         prod=APPLIED 2026-11-14 (jobid 1, schedule '0 15 * * 2', active true,
--                      verified by reading cron.job directly, not assumed)
-- ============================================================================
-- Customer engagement S3b (docs/customer-engagement-paper-to-app.md § S3b)
-- Prepared 2026-11-14. Operator: Rick (Supabase SQL Editor, runs as postgres).
-- PRODUCTION ONLY. Run AFTER docs/sql/2026-11-14-s3b-email-arrivals-opt-out-and-notices.sql
-- has landed on production, and AFTER notify-arrivals is deployed and has
-- passed its own dry_run check (plan § S3b Gates) — this job calls it live.
--
-- ⚠️ Neither pg_cron nor pg_net has been used anywhere in this project before.
-- The PRE-CHECK below is the actual gate, not a formality: it tells you
-- whether they exist on the plan at all before this file tries to touch
-- anything. If either comes back unavailable, STOP — do not attempt to
-- enable it — and use the plan's documented fallback instead: a scheduled
-- GitHub Actions workflow holding ARRIVALS_CRON_SECRET, posting to
-- notify-arrivals on the same Tuesday 15:00 UTC schedule. GitHub's own cron
-- has started up to 3h20m late in this project (F135's newsletter cron),
-- which is acceptable for this email and not for anything time-critical.
--
-- One job, in the `cron` schema pg_cron creates: Tuesday 15:00 UTC (10 or
-- 11 AM Eastern depending on DST), one POST to notify-arrivals covering
-- every shop in one call — the function itself loops tenants, this job does
-- not pass a tenant.
-- ============================================================================

-- ── PRE-CHECK (run on its own first; the SQL Editor shows only the last result)
-- ⚠️ v1 of this query referenced cron.job directly in an EXISTS subquery,
-- which Postgres must resolve at PLAN time regardless of how conditionally
-- it looks wrapped — if the cron schema doesn't exist yet (pg_cron not
-- installed), the whole statement fails to parse with 42P01 before any
-- availability check even runs. Caught by Rick's first real run on
-- production, not by me catching it first. Fixed with to_regclass(), the
-- same null-safe existence check already used elsewhere in this plan's own
-- S3b pre-check (arrival_notices) — it returns NULL for a relation that
-- doesn't exist (even in a schema that doesn't exist) instead of erroring.
SELECT
  EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_cron')  AS pg_cron_available,
  EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron')          AS pg_cron_installed,
  EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_net')   AS pg_net_available,
  EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net')           AS pg_net_installed,
  (to_regclass('cron.job') IS NOT NULL)                                  AS cron_job_table_exists;
-- STOP if pg_cron_available or pg_net_available is false — neither extension
-- can be enabled on this plan/project, and the fix direction is the GitHub
-- Actions fallback above, not this file.
-- If *_available is true but *_installed is false, the CREATE EXTENSION
-- statements below will install it (both are expected to need a superuser
-- or the Supabase dashboard's own "enable extension" toggle — if the CREATE
-- EXTENSION statement below is refused with a permissions error, enable both
-- from the Supabase dashboard's Database > Extensions page instead, then
-- re-run from "THE CHANGE" with the CREATE EXTENSION lines removed).
-- cron_job_table_exists = false simply means pg_cron has never scheduled
-- anything here yet (expected, first use) — it does NOT mean pg_cron is
-- unavailable; that is the *_available columns' job. If it reads true,
-- run this as a follow-up BEFORE scheduling anything:
--   SELECT jobid, jobname FROM cron.job WHERE jobname = 'notify-arrivals-weekly';
-- STOP if that returns a row — do not double-schedule.

-- ── THE CHANGE ──────────────────────────────────────────────────────────────
-- Not wrapped in BEGIN/COMMIT: CREATE EXTENSION and cron.schedule() are each
-- their own top-level statement in Supabase's own documented pattern for
-- these two extensions, and cron.schedule() is not transactional in the
-- usual sense (it writes to the cron.job table directly). Run the three
-- statements below one at a time, reading each result, rather than pasting
-- the whole block — if the CREATE EXTENSION lines are refused, see the note
-- above and use the dashboard toggle instead.

CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- The secret lives in this statement only (SQL Editor history, not the repo).
-- Replace <ARRIVALS_CRON_SECRET> with the exact value set as the Edge
-- Function's own secret (supabase secrets set ARRIVALS_CRON_SECRET=...) —
-- they must match, or notify-arrivals refuses every scheduled call with 401.
SELECT cron.schedule(
  'notify-arrivals-weekly',
  '0 15 * * 2',  -- Tuesday 15:00 UTC
  $$
  SELECT net.http_post(
    url     := 'https://plgegklqtdjxeglvyjte.supabase.co/functions/v1/notify-arrivals',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-arrivals-cron-secret', '<ARRIVALS_CRON_SECRET>'
    ),
    body    := '{}'::jsonb
  );
  $$
);

-- ── VERDICT (run on its own after the change)
SELECT jobid, schedule, command, active
  FROM cron.job WHERE jobname = 'notify-arrivals-weekly';
-- Expected: one row, schedule = '0 15 * * 2', active = true. The command
-- text will show the secret in plaintext in this one read — that is
-- inherent to how pg_cron stores a job, not a new exposure (only an
-- operator with SQL Editor / superuser access can read cron.job).
--
-- To unschedule, if ever needed: SELECT cron.unschedule('notify-arrivals-weekly');
