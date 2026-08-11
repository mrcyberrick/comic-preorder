-- STATUS: staging=APPLIED 2026-08-10 | prod=PENDING
--         Gates V1/V2/V3/V4 + full suite + real-browser green on staging. Promotion is Rick's call.
-- (F105) This line is the applied-state record. A gate that lives only in
-- prose gets missed -- F6 sat unapplied on production for 13 days because
-- nothing machine-readable said so. Update it the moment you run this file.
-- =====================================================================
-- F127 — make account `status` an authorization boundary
-- Session 1 of docs/preorders-authorization-boundary-f127-f109.md
--
-- Rick authorised the full DDL 2026-08-10 (having been offered, and
-- declined, the cheaper "accept it as a UI-level guard" option).
--
-- RUN ON **STAGING** FIRST. Production promotion is a separate decision.
-- Supabase SQL Editor (runs as `postgres`, bypasses RLS — required here).
--
-- WHAT THIS FIXES, measured not inferred: a `status='pending'` user signed
-- in as itself and `POST /rest/v1/preorders` returned **HTTP 201, row
-- persisted**. No policy on `preorders` references `status` at all; the
-- entire gate is client-side. `subscriptions` is worse — that page has no
-- status check whatsoever, so it needs no crafted request at all.
--
-- ADDITIVE ONLY. No existing policy is altered or dropped. Rollback is one
-- DROP per object, in § R.
-- =====================================================================


-- ---------------------------------------------------------------------
-- STEP 0 — PRE-FLIGHT. Run gate V0 in
-- docs/sql/2026-08-10-is-admin-drop-and-f92-catalog-reads.sql PART C first.
--
-- It must show `preorders` with exactly 2 policies and 0 unexpected. If it
-- shows 4, **STOP**: F16 is actually open, and adding a predicate on top of
-- a policy set that already permits cross-tenant admin writes fixes the
-- smaller problem while leaving the larger one. F16's fix sequences first.
-- ---------------------------------------------------------------------


-- ---------------------------------------------------------------------
-- STEP 1 — the helper.
--
-- Every property below is deliberate and traceable to something that has
-- already gone wrong in this project:
--
--   SECURITY DEFINER  — mirrors current_user_is_admin(). Its internal read of
--                       user_profiles runs as owner and bypasses RLS, so no
--                       policy on user_profiles must permit it and there is no
--                       recursion path (CLAUDE.md § Known Issues; F46).
--   SET search_path   — F23.
--   STABLE            — it reads a table, so not IMMUTABLE.
--   DOUBLE COALESCE   — this is the F126 hazard, and it is the whole reason
--                       this function is not a one-liner:
--                         inner: `is_admin` is NULLABLE, and `NULL OR false`
--                                evaluates to NULL, not false;
--                         outer: a caller with no matching profile row (no
--                                identity, deleted profile) yields NO ROW, so
--                                the scalar subquery is NULL.
--                       Both must land on FALSE. F126 shipped a gate written
--                       `IF NOT current_user_is_admin()` that was OPEN for
--                       exactly this reason.
--   POSITIVE predicate — `status = 'active'` passes. A future fourth status
--                       therefore BLOCKS by default rather than silently
--                       passing. 'suspended' and 'pending' both block, which
--                       is the settled decision (F126/F127), not a new one.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.current_user_is_active()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    (SELECT COALESCE(is_admin, false) OR status = 'active'
       FROM user_profiles
      WHERE id = auth.uid()),
    false)
$function$;


-- ---------------------------------------------------------------------
-- STEP 2 — grants (F124).
--
-- `REVOKE ... FROM PUBLIC` does NOT strip Supabase's default anon/
-- authenticated grants. Here `authenticated` MUST KEEP EXECUTE: the policies
-- below are `TO authenticated`, so that role evaluates this function during
-- RLS. Revoking it would break the policies the way F124 warns revoking
-- current_user_is_admin() would.
--
-- 2a. Read what the established sibling actually has, and mirror it rather
--     than trusting this file:
-- ---------------------------------------------------------------------
SELECT p.proname,
       coalesce(p.proacl::text, 'NULL = owner-only default') AS execute_grants
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('current_user_is_admin', 'current_tenant_id', 'current_user_is_active');

-- 2b. Intended end state, stated explicitly rather than assumed:
REVOKE ALL ON FUNCTION public.current_user_is_active() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.current_user_is_active() FROM anon;
GRANT EXECUTE ON FUNCTION public.current_user_is_active() TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_user_is_active() TO service_role;

-- 2c. Re-run 2a. `current_user_is_active` must now show EXECUTE for
--     authenticated and service_role, and must NOT show anon.


-- ---------------------------------------------------------------------
-- STEP 3 — the policies.
--
-- RESTRICTIVE, not a rewrite of `users manage own preorders`. Restrictive
-- policies are ANDed with the permissive set, so the working policy is never
-- touched and rollback is one DROP rather than re-creating a load-bearing
-- policy from a script under time pressure.
--
-- INSERT and UPDATE only — deliberately NOT SELECT or DELETE. A blocked
-- customer keeps SEEING and CANCELLING their own reservations. Anything else
-- makes Pause destructive and contradicts the confirm text F126 already
-- shipped ("existing reservations stand").
--
-- `USING (true)` on the UPDATE policies is stated rather than omitted, so the
-- policy provably constrains only the RESULTING row and never which rows are
-- visible or updatable.
-- ---------------------------------------------------------------------
CREATE POLICY "blocked accounts cannot create preorders"
  ON public.preorders AS RESTRICTIVE FOR INSERT TO authenticated
  WITH CHECK (public.current_user_is_active());

CREATE POLICY "blocked accounts cannot change preorders"
  ON public.preorders AS RESTRICTIVE FOR UPDATE TO authenticated
  USING (true)
  WITH CHECK (public.current_user_is_active());

CREATE POLICY "blocked accounts cannot create subscriptions"
  ON public.subscriptions AS RESTRICTIVE FOR INSERT TO authenticated
  WITH CHECK (public.current_user_is_active());

CREATE POLICY "blocked accounts cannot change subscriptions"
  ON public.subscriptions AS RESTRICTIVE FOR UPDATE TO authenticated
  USING (true)
  WITH CHECK (public.current_user_is_active());


-- =====================================================================
-- VERIFICATION — each states its FAILING output, not just its passing one
-- =====================================================================

-- V1. The four policies exist and are RESTRICTIVE.
SELECT tablename, policyname, cmd, permissive,
       CASE WHEN permissive = 'RESTRICTIVE' THEN 'PASS' ELSE 'FAIL — permissive!' END AS verdict
FROM   pg_policies
WHERE  schemaname = 'public' AND policyname LIKE 'blocked accounts%'
ORDER  BY tablename, policyname;
-- PASS: 4 rows, all RESTRICTIVE, cmds INSERT/UPDATE across both tables.
-- FAIL: fewer than 4 rows, or any row reading PERMISSIVE — a permissive
--       policy would WIDEN access instead of narrowing it, i.e. the exact
--       opposite of the intent. Different row count AND different text.

-- V2. The NULL hazard (F126). This is the check that matters most.
--     Each case must be FALSE except the active/admin ones.
SELECT 'no identity (auth.uid() IS NULL)' AS case_name,
       public.current_user_is_active()     AS result,
       CASE WHEN public.current_user_is_active() IS FALSE
            THEN 'PASS' ELSE 'FAIL — NULL or TRUE for an unidentified caller' END AS verdict;
-- Run in the SQL Editor, auth.uid() is NULL, so this exercises the OUTER
-- COALESCE. PASS = false. FAIL = NULL or true.
--
-- The other four cases need real profile rows and are covered by the plan's
-- gate V2 with a seeded fixture (active / pending / suspended / admin-with-
-- NULL-is_admin). Do not skip the admin-with-NULL-is_admin case: it is the
-- one that fails if the INNER COALESCE is dropped, and it looks fine in
-- every other test.

-- V3. Behavioural proof — the ONLY evidence that actually counts.
--     Repeat the exact probe that filed F127: create a `status='pending'`
--     user, sign in AS THAT USER, and POST /rest/v1/preorders with its own
--     JWT and the browser (publishable) key.
--     BEFORE this migration: HTTP 201, row persisted.
--     AFTER:                 HTTP 403, new row count unchanged.
--     A 201 here means the gate did not take. Tear the fixture down and
--     confirm profile rows = 0 by SELECT, not by "we ran the teardown".

-- V4. Non-regression, and the one most likely to be forgotten:
--     an ACTIVE customer must still be able to reserve and subscribe, and a
--     BLOCKED customer must still be able to SELECT and DELETE its own rows.
--     If a blocked customer can no longer cancel, the predicate reached
--     USING/DELETE and must be corrected — see § R.

-- V5. Admin impersonation must be unaffected. AdminContext puts the
--     customer's id in the request BODY while the request carries the
--     ADMIN's JWT, so auth.uid() is the admin and these writes have always
--     gone through `admins manage tenant preorders`, not the user policy.
--     Verified from app.js:502-588. Confirm empirically anyway.

-- V6. The import script must be unaffected. It writes as service_role,
--     which bypasses RLS entirely; the policies are `TO authenticated`
--     besides. Run a `--no-write` dry run, then a real staging import.


-- =====================================================================
-- § R — ROLLBACK. Each object drops independently; no ordering required
--       beyond dropping the policies before the function they call.
-- =====================================================================
-- DROP POLICY "blocked accounts cannot create preorders"     ON public.preorders;
-- DROP POLICY "blocked accounts cannot change preorders"     ON public.preorders;
-- DROP POLICY "blocked accounts cannot create subscriptions" ON public.subscriptions;
-- DROP POLICY "blocked accounts cannot change subscriptions" ON public.subscriptions;
-- DROP FUNCTION public.current_user_is_active();
--
-- Nothing pre-existing was modified, so rollback restores the exact prior
-- state. That is the reason for the RESTRICTIVE approach.
