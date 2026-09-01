-- STATUS: COMPLETE | staging=APPLIED 2026-08-31 | prod=APPLIED 2026-09-01 | findings=F149

-- F149: give the two anonymous-visitor pages (index.html's registration
-- submit, forgot-password.html's reset submit) a way to read
-- app_settings.maintenance_mode.
--
-- Confirmed live before writing this (curl, anon key, staging):
--   GET .../rest/v1/app_settings?key=eq.maintenance_mode
--   -> 401 {"code":"42501","message":"permission denied for table app_settings"}
-- `app_settings`'s only SELECT policy is `TO authenticated`
-- (docs/technical-reference.md § 4.4/§13) and there is no anon GRANT at all
-- — this is a hard table-level denial, not an RLS row filter returning zero
-- rows. Settings.isMaintenanceMode() (app.js) therefore cannot be reused
-- as-is from either page: called anonymously it would silently always
-- return false regardless of the real value.
--
-- Fix: a narrow SECURITY DEFINER RPC that returns ONLY the maintenance_mode
-- boolean for one tenant — never the raw app_settings row, never any other
-- key (order_deadline etc). This is the same shape already used twice in
-- this codebase for exactly this reason (anon cannot read the underlying
-- table directly): resolve_tenant_by_slug (docs/phase-5.2-slug-id-routing-rpc.md
-- § 1.5) and get_popular_series (subscription-reserved-suggestions work,
-- CLAUDE.md 2026-08-31 entry). Same minimal-projection / explicit-grant
-- discipline as resolve_tenant_by_slug's own § 1.5 contract.
--
-- Run on STAGING only for this session. Do not run on production until
-- Rick explicitly requests a promotion per CLAUDE.md § Staging Only.

-- =====================================================================
-- PRE-FLIGHT (read-only) — confirm the function name is free and that
-- app_settings' current grant shape matches what this migration assumes.
-- =====================================================================
SELECT proname, pronargs
FROM   pg_proc
WHERE  pronamespace = 'public'::regnamespace
  AND  proname = 'is_maintenance_mode';
-- EXPECTED: 0 rows (name is free). If a row comes back, STOP — something
-- already uses this name and the CREATE OR REPLACE below would silently
-- change it instead of creating something new.

SELECT grantee, privilege_type
FROM   information_schema.role_table_grants
WHERE  table_schema = 'public'
  AND  table_name   = 'app_settings'
  AND  grantee IN ('anon', 'authenticated');
-- EXPECTED: 'authenticated' rows only (matching the `TO authenticated`
-- SELECT policy), no 'anon' rows at all — matching the live 401 confirmed
-- above. If anon already has a grant here, STOP — the premise of this
-- migration (anon cannot read app_settings) doesn't hold and the fix
-- direction needs rethinking, not just running this file anyway.

-- =====================================================================
-- MIGRATION
-- =====================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.is_maintenance_mode(p_tenant_id uuid)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path = public, pg_temp
  AS $$
    SELECT COALESCE(
      (SELECT value = 'true'
       FROM   public.app_settings
       WHERE  tenant_id = p_tenant_id
         AND  key       = 'maintenance_mode'),
      false
    );
  $$;

REVOKE ALL ON FUNCTION public.is_maintenance_mode(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_maintenance_mode(uuid) TO anon, authenticated;

COMMIT;

-- =====================================================================
-- POST-CHECK (read-only) — must show the function present with EXECUTE
-- granted to anon and authenticated, and nobody else.
-- =====================================================================
SELECT proname, prosecdef AS security_definer, proconfig
FROM   pg_proc
WHERE  pronamespace = 'public'::regnamespace
  AND  proname = 'is_maintenance_mode';
-- EXPECTED: 1 row, security_definer = true, proconfig contains
-- 'search_path=public,pg_temp'.
-- FAILURE: 0 rows (transaction didn't land), or security_definer = false
-- (would run as the caller and hit the same permission-denied wall this
-- migration exists to fix).

SELECT grantee, privilege_type
FROM   information_schema.routine_privileges
WHERE  routine_schema = 'public'
  AND  routine_name   = 'is_maintenance_mode';
-- EXPECTED: exactly 'anon' and 'authenticated', privilege_type EXECUTE.
-- FAILURE: PUBLIC still listed (REVOKE didn't take), or anon missing
-- (client-side calls from the two anonymous pages would then 401 exactly
-- like the direct table read this RPC is meant to replace).

-- =====================================================================
-- FUNCTIONAL CHECK (do this from a real anon caller, not the SQL Editor —
-- SQL Editor runs as the postgres superuser and SECURITY DEFINER functions
-- execute with the definer's privileges regardless of caller, so neither
-- context actually exercises the anon EXECUTE grant this migration adds.
-- The only real test is an anon-key HTTP call):
--
--   curl -s -X POST \
--     ".../rest/v1/rpc/is_maintenance_mode" \
--     -H "apikey: <staging anon key>" \
--     -H "Content-Type: application/json" \
--     -d '{"p_tenant_id":"72e29f67-39f7-42bc-a4d5-d6f992f9d790"}'
--
-- EXPECTED: 200, body `false` (maintenance mode is off at time of writing).
-- FAILURE: 401/permission denied (grant didn't take), or a 5xx/parse error
-- (function body issue) — either is a halt-and-report per CLAUDE.md, not
-- something to work around inline.
-- =====================================================================
