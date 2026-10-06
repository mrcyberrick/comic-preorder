-- STATUS: staging=APPLIED 2026-10-06 (Rick; PRE: plan free x6 / pro x1, no existing tenants_plan_check, 3 key carriers raysandjudys / demoshop / riverside-comics; POST: tenants_plan_check convalidated true, CHECK ((plan = ANY (ARRAY['free'::text, 'pro'::text]))), carriers remaining 0) | prod=APPLIED 2026-10-06 (Rick; PRE: plan free x1 / pro x1, no existing constraint, 2 key carriers comicstore / rjbookstop; POST: the same constraint row, convalidated true, carriers remaining 0; independently re-read through the production REST API with the service role: both tenants' settings keys empty, rjbookstop=pro and comicstore=free unchanged)
--         Pre-Phase-6 gate closure, session G-A (docs/pre-phase-6-gate-closure.md § 2 Steps 3 and 4): the two
--         tenant-table hygiene changes. (F105) This line is the applied-state record.
-- *** The F150 REVOKE (runbook Step 2) is deliberately NOT in this file and was NOT run. *** The Step 1 sweep
--         found production's anon grants differ from staging's on 9 of 11 tables, not only app_settings, so the
--         runbook's rule (revoke nothing this session) applied. Rick's PAUSE decision, 2026-10-06: skip Step 2,
--         defer F150 with its scope widened. Full diff: docs/technical-reference.md § 13 F150.
-- ============================================================================
-- (1) tenants.plan CHECK constraint (F72 S0 residual, raised 2026-09-02; gate G6 of docs/phase-6-self-service-signup.md)
--     register-tenant normalises plan (trim + lowercase, then an allowlist), but a hand-typed UPDATE bypasses it:
--     'Pro' would persist and Tier.isPaid() (=== 'pro') would read it as free. The constraint makes the database
--     reject that loudly. ADD CONSTRAINT validates every existing row, so any value other than free/pro aborts
--     the whole transaction; the PRE query below is how you know it will not.
-- (2) F151 row cleanup: delete the dead mailerlite_webhook_secret key from tenants.settings. Inert since 2026-08-30
--     (the ?secret= path was removed from register-customer platform-wide); no rotation needed. NEVER select the
--     value. F151 STAYS OPEN: register-tenant (index.ts, lines ~177/196/347 on 2026-10-06) still generates, stores
--     and returns the secret on every new tenant, so a tenant created after this runs carries the key again until
--     session G-B removes the writer.
-- Run on STAGING first, in the Supabase SQL Editor (postgres superuser). Production is a separate, later run.
-- Rollback: (1) ALTER TABLE public.tenants DROP CONSTRAINT tenants_plan_check;  (2) not reversible, not needed.

-- ===== PRE-FLIGHT (read-only). Run as one paste. =====
-- NOTE (accuracy): on 2026-10-06 Rick ran a larger "round 1" query on both projects that carried these same three
-- sections AND the F150 sweep (per-table anon grants, default ACLs). The query below is the subset that applies to
-- this file's two changes, kept here so the file is self-contained; its results are the round-1 results quoted in
-- the STATUS line. The change and the POST-CHECK below are exactly what was run.
SELECT 'plan value' AS section, plan AS name, count(*)::text AS a
FROM public.tenants GROUP BY plan
UNION ALL
SELECT 'constraint already present', conname::text, ''
FROM pg_constraint WHERE conrelid = 'public.tenants'::regclass AND conname = 'tenants_plan_check'
UNION ALL
SELECT 'F151 carrier slug', slug, ''
FROM public.tenants WHERE jsonb_exists(settings, 'mailerlite_webhook_secret')
ORDER BY 1, 2;
-- EXPECTED: plan values only 'free' and 'pro'; NO 'constraint already present' row (if there is one, STOP:
-- it was already run; go to the POST-CHECK); the carriers are slugs only. jsonb_exists(settings, 'k') is the
-- function form of the ? operator, used so the SQL Editor cannot mistake the ? for a parameter placeholder.

-- ===== THE CHANGE (one transaction: both or neither) =====
BEGIN;

ALTER TABLE public.tenants
  ADD CONSTRAINT tenants_plan_check CHECK (plan IN ('free', 'pro'));

UPDATE public.tenants
   SET settings = settings - 'mailerlite_webhook_secret'
 WHERE jsonb_exists(settings, 'mailerlite_webhook_secret');

COMMIT;

-- ===== POST-CHECK (read-only). The SQL Editor shows only the LAST statement's result, so this is one statement. =====
SELECT 'G6 constraint' AS section, conname::text AS name, convalidated::text AS a,
       pg_get_constraintdef(oid) AS b
FROM pg_constraint WHERE conrelid = 'public.tenants'::regclass AND conname = 'tenants_plan_check'
UNION ALL
SELECT 'F151 carriers remaining', count(*)::text, '', ''
FROM public.tenants WHERE jsonb_exists(settings, 'mailerlite_webhook_secret')
ORDER BY 1, 2;
-- EXPECTED (both must change from the PRE-FLIGHT, which is what makes this a check that can fail):
--   G6 constraint            | tenants_plan_check | true | CHECK ((plan = ANY (ARRAY['free'::text, 'pro'::text])))
--   F151 carriers remaining  | 0
