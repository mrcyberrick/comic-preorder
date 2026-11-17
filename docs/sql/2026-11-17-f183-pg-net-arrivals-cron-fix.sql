-- F183 fix: install pg_net so the Tuesday arrivals schedule can make its call, give
-- that call an explicit timeout, prove it with a dry run, then send this week's
-- email once by hand (Rick, 2026-11-17: "Fix now", "Send today").
-- Finding: docs/technical-reference.md § 13 F183.
-- STATUS: staging=N/A (staging never gets the schedule, see the S3b cron file) | prod=APPLIED 2026-11-17
-- (Rick: STEP 4 dry run 200, dry_run true, would_email 9 (rjbookstop 9, comicstore skipped, no
-- shipment); STEP 5 200, sent 9, failed 0, notices_this_week 9. STEP 0 and the STEP 3 VERDICT were
-- not pasted, so whether STEP 2's 60 s timeout landed is NOT confirmed; the dry run proves pg_net
-- is installed and the job's command reaches the function with an accepted secret.)
--
-- PRODUCTION ONLY. Supabase SQL Editor (runs as postgres). Run each step ON ITS
-- OWN, in order, and read its result before the next. Every result query below
-- returns counts only: the function's dry-run answer lists customers by name,
-- and those are not read out here.
--
-- Why a hand-run send cannot reach anyone twice: today's scheduled run failed
-- before making any HTTP call (cron.job_run_details: 'schema "net" does not
-- exist'), and arrival_notices holds 0 rows. notify-arrivals also skips anyone
-- it has already written a notice for this week, so even an accidental second
-- run of STEP 5 sends nothing new.

-- ── STEP 0: PRE-CHECK (changes nothing) ─────────────────────────────────────
SELECT
  EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_net')          AS pg_net_available,
  EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net')                  AS pg_net_installed,
  to_regnamespace('net') IS NOT NULL                                             AS net_schema_exists,
  (SELECT count(*) FROM cron.job WHERE jobname = 'notify-arrivals-weekly')       AS arrivals_jobs,
  (SELECT bool_and(active) FROM cron.job WHERE jobname = 'notify-arrivals-weekly') AS job_active,
  (SELECT bool_or(command LIKE '%timeout_milliseconds%') FROM cron.job
    WHERE jobname = 'notify-arrivals-weekly')                                    AS job_sets_timeout,
  (SELECT count(*) FROM public.arrival_notices)                                  AS notices_ever,
  (SELECT string_agg(slug, ',' ORDER BY slug) FROM public.tenants
    WHERE slug NOT LIKE 'pw-%')                                                  AS tenants_here;
-- Expected: true, false, false, 1, true, false, 0, comicstore,rjbookstop.
-- STOP if pg_net_available is false (then the S3b cron file's GitHub Actions
-- fallback is the route, not this file), if arrivals_jobs is not 1, or if
-- tenants_here is not production. If pg_net_installed is already true, skip STEP 1.

-- ── STEP 1: install pg_net ──────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS pg_net;
-- If this is refused with a permissions error: Supabase dashboard > Database >
-- Extensions > enable "pg_net", then continue with STEP 2.

-- ── STEP 2: give the job's call an explicit 60-second timeout ───────────────
-- Edits the stored command in place, so the secret inside it is never retyped.
-- pg_net's default timeout is believed to be 5 s, and notify-arrivals sends one
-- email at a time, so a run with 9+ customers may take longer than that.
SELECT cron.alter_job(
  job_id  := j.jobid,
  command := regexp_replace(j.command,
               '(body\s*:=\s*''\{\}''::jsonb)',
               '\1, timeout_milliseconds := 60000')
)
FROM cron.job j
WHERE j.jobname = 'notify-arrivals-weekly'
  AND j.command NOT LIKE '%timeout_milliseconds%';
-- Expected: one row (alter_job returns nothing visible). Zero rows means the
-- command already had a timeout. The VERDICT shows whether the edit landed.

-- ── STEP 3: VERDICT (run on its own) ────────────────────────────────────────
SELECT
  EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net')                   AS pg_net_installed,
  EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'net' AND p.proname = 'http_post'
             AND pg_get_function_arguments(p.oid) LIKE '%timeout_milliseconds%') AS http_post_takes_timeout,
  (SELECT bool_and(command LIKE '%timeout_milliseconds := 60000%') FROM cron.job
    WHERE jobname = 'notify-arrivals-weekly')                                    AS job_sets_timeout,
  (SELECT bool_and(active) FROM cron.job WHERE jobname = 'notify-arrivals-weekly') AS job_active,
  (SELECT min(schedule) FROM cron.job WHERE jobname = 'notify-arrivals-weekly')  AS schedule;
-- Expected: true, true, true, true, '0 15 * * 2'. Before STEPS 1-2 this reads
-- false, false, false, true, so an install that did not land cannot read as a
-- pass. This still does not prove the job can CALL the function; STEP 4 does.

-- ── STEP 4: DRY RUN, through the job's own command ──────────────────────────
-- Runs the stored command once with body {"dry_run": true}: the function reads
-- who it WOULD email and sends nothing. pg_net sends the request after this
-- statement commits, so wait about 30 seconds, then run the read below it.
DO $$
DECLARE c text;
BEGIN
  SELECT regexp_replace(command, '''\{\}''::jsonb', '''{"dry_run": true}''::jsonb')
    INTO c FROM cron.job WHERE jobname = 'notify-arrivals-weekly';
  IF c IS NULL OR c NOT LIKE '%dry_run%' THEN
    RAISE EXCEPTION 'could not build the dry-run command; nothing was sent';
  END IF;
  EXECUTE c;
END $$;

-- Read the dry run's answer (counts only):
SELECT r.status_code, r.timed_out, r.error_msg, r.created,
       CASE WHEN r.content LIKE '{%' THEN (r.content::jsonb) ->> 'dry_run' END       AS dry_run,
       CASE WHEN r.content LIKE '{%' THEN (r.content::jsonb) ->> 'would_email' END   AS would_email,
       CASE WHEN r.content LIKE '{%' THEN (
         SELECT string_agg((t ->> 'tenant') || ': ' || jsonb_array_length(t -> 'recipients')
                           || COALESCE(' (skipped: ' || (t ->> 'skipped') || ')', ''), ' | ')
           FROM jsonb_array_elements((r.content::jsonb) -> 'by_tenant') t) END     AS by_shop,
       CASE WHEN r.content NOT LIKE '{%' THEN left(r.content, 200) END              AS non_json_body
  FROM net._http_response r ORDER BY r.created DESC LIMIT 1;
-- Expected: status_code 200, timed_out false, dry_run true, would_email 9 (or
-- close to it, if a customer reserved or changed since 18:05 UTC), by_shop
-- "rjbookstop: 9 | comicstore: 0 (skipped: no weekly_shipment rows ...)" or similar.
-- STOP if there is no row after a minute (then: SELECT count(*) FROM
-- net.http_request_queue; and report), if status_code is 401 (the secret in
-- the job does not match the function's ARRIVALS_CRON_SECRET), or if anything
-- else differs. Do not run STEP 5 on a doubtful dry run.

-- ── STEP 5: SEND THIS WEEK'S EMAIL, once ────────────────────────────────────
-- The job's command exactly as Tuesday's schedule will run it.
DO $$
DECLARE c text;
BEGIN
  SELECT command INTO c FROM cron.job WHERE jobname = 'notify-arrivals-weekly';
  IF c IS NULL THEN RAISE EXCEPTION 'no notify-arrivals-weekly job'; END IF;
  EXECUTE c;
END $$;

-- About a minute later, the result (counts only):
SELECT r.status_code, r.timed_out, r.error_msg, r.created,
       CASE WHEN r.content LIKE '{%' THEN (r.content::jsonb) ->> 'sent' END   AS sent,
       CASE WHEN r.content LIKE '{%' THEN (r.content::jsonb) ->> 'failed' END AS failed,
       (SELECT count(*) FROM public.arrival_notices
         WHERE week_start = DATE '2026-11-16')                                 AS notices_this_week
  FROM net._http_response r ORDER BY r.created DESC LIMIT 1;
-- Expected: status_code 200, timed_out false, sent = the dry run's would_email,
-- failed 0, notices_this_week = sent. If timed_out is true but notices_this_week
-- equals the dry run's would_email, the emails went and only the wait ran out.
