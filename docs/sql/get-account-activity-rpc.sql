-- ============================================================================
-- get_account_activity() — admin-only read of sign-in activity from auth.users
-- Prepared 2026-08-09 (F126 account-lifecycle session).
-- Run: STAGING FIRST. Operator: Rick (Supabase SQL Editor).
--
-- WHY THIS EXISTS:
--   Rick, reviewing the Accounts tab: "Does last login exist as this would let
--   me sort unanswered invites?" It does — auth.users.last_sign_in_at — but it
--   is NOT reachable from the admin client. There is no public.auth_users view
--   (a service-role read returns 404 PGRST205), and the admin browser session
--   must never hold a service key. So the one fact the Accounts tab needs is
--   exposed here, and nothing else.
--
--   Measured on production 2026-08-09: exactly ONE unanswered invite —
--   Ronald Burke, invited 2026-03-17, never confirmed, never signed in.
--   Invisible today because invite-customer sets status:'active' the moment
--   the invite is sent, so it looks identical to a real active customer.
--
-- WHY NOT A CHEAPER PROXY:
--   user_profiles.has_seen_welcome was tested as a free stand-in for "never
--   signed in" and FAILS — it agrees with last_sign_in_at only 8 of 12 on
--   production, falsely flagging four signed-in customers. Do not retry it.
--
-- ── THE ONE THING TO GET RIGHT: the gate is in the BODY, not the grant ──
--   get_ordered_codes() is the model for shape, but it GRANTs to
--   `authenticated` because every customer needs it. This function is
--   admin-only — and admins ARE `authenticated`, so there is no role to grant
--   that excludes customers. Revoking `authenticated` would lock out the only
--   intended caller. Hence current_user_is_admin() inside the function.
--
--   anon and PUBLIC are revoked EXPLICITLY, per F124: Supabase bootstraps
--   ALTER DEFAULT PRIVILEGES ... GRANT EXECUTE ON FUNCTIONS TO anon,
--   authenticated, so every new function in public starts with both role
--   grants, and REVOKE ... FROM PUBLIC does NOT remove them. A file that
--   revokes only PUBLIC looks correct in review and leaves anon able to call.
--
-- WHAT IT DELIBERATELY DOES NOT RETURN:
--   No email, no name, no raw_user_meta_data, no tokens. auth.users has never
--   been exposed to this app and must not start being by accident. Two
--   timestamps and the id to join on — that is the entire surface.
--
-- Tenant scope comes from current_tenant_id() INTERNALLY, never from a client
-- parameter — the rule every RLS-adjacent function here follows.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_account_activity()
RETURNS TABLE (
  id                 uuid,
  last_sign_in_at    timestamptz,
  email_confirmed_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT current_user_is_admin() THEN
    RAISE EXCEPTION 'get_account_activity: admin only'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
    SELECT u.id, u.last_sign_in_at, u.email_confirmed_at
    FROM auth.users u
    JOIN public.user_profiles p ON p.id = u.id
    WHERE p.tenant_id = current_tenant_id();
END;
$$;

-- Grants. authenticated is REQUIRED (admins are authenticated); the admin gate
-- is the function body. anon and PUBLIC are named explicitly — see F124.
GRANT EXECUTE ON FUNCTION public.get_account_activity() TO authenticated;
REVOKE ALL ON FUNCTION public.get_account_activity() FROM PUBLIC, anon;


-- ── VERIFY 1: grants are exactly what we intend ─────────────────────────────
SELECT grantee, privilege_type
FROM information_schema.routine_privileges
WHERE routine_name = 'get_account_activity';
-- EXPECTED: authenticated = EXECUTE, and nothing else.
--           If `anon` appears, the REVOKE did not take — stop and re-run it.


-- ── VERIFY 2: the function returns rows for the founding tenant ─────────────
-- Run as the SQL Editor's postgres superuser. current_user_is_admin() reads
-- user_profiles for auth.uid(), which is NULL here, so this is EXPECTED TO
-- RAISE 42501 — that is the gate working, not a failure.
--
--   SELECT * FROM public.get_account_activity();
--
-- Verify it properly from the APP instead (gate V1): an admin session gets
-- rows, a non-admin session gets 42501. Reading the SQL is not evidence —
-- F124 is the case where the SQL looked right and the grants were wrong.


-- ── VERIFY 3: nothing beyond the three columns is exposed ───────────────────
SELECT p.proname,
       pg_get_function_result(p.oid) AS returns
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'get_account_activity';
-- EXPECTED: TABLE(id uuid, last_sign_in_at timestamp with time zone,
--                 email_confirmed_at timestamp with time zone)


-- ── ROLLBACK ────────────────────────────────────────────────────────────────
-- Additive and read-only; nothing else references it.
--   DROP FUNCTION IF EXISTS public.get_account_activity();
