-- STATUS: staging=PENDING | prod=PENDING
-- ============================================================================
-- Customer engagement S5 (docs/customer-engagement-paper-to-app.md § S5)
-- Prepared 2026-11-14. Operator: Rick (Supabase SQL Editor, runs as postgres).
-- Run: STAGING first, then PRODUCTION, both BEFORE the convert-paper-customer
--      code-mode deploy or any client code that calls admin_get_paper_claim_codes
--      — the F115 lesson (selecting a column/calling an RPC production lacks
--      fails the whole read, not just the new feature).
--
-- Two changes, one transaction:
--   (a) public.paper_claim_codes (code, tenant_id, paper_user_id, created_at,
--       expires_at, used_at). RLS ON, ZERO policies — deliberately, not an
--       oversight. The only two legitimate access paths are (b) below
--       (SECURITY DEFINER, bypasses RLS) and the convert-paper-customer Edge
--       Function's service-role key (also bypasses RLS); nothing needs a
--       direct REST read or write, so a bare PostgREST call from ANY role,
--       admin included, sees zero rows and can write nothing. "No customer
--       policy" in the plan's own S5 wording, taken to its safest reading.
--   (b) admin_get_paper_claim_codes(user_ids uuid[]): admin-only, shop
--       derived from the CALLER's own session (current_tenant_id()), never
--       from a parameter — a shop admin cannot fetch another shop's codes
--       by passing its user ids. Returns each paper customer's live
--       (unused, unexpired) code, generating one on first call and REUSING
--       it on every later call until it is used or expires (D7: "one live
--       code per paper customer, reprinted on each slip until used"). A
--       user id that is not a paper customer in the caller's own shop is
--       silently skipped, not errored — the caller passes a batch of ids
--       (every paper row on screen) and some may not qualify.
--
-- Code shape: 12 characters from a 31-symbol unambiguous alphabet (digits
-- 0/1 and letters I/O/L dropped — easily confused when hand-typed off a
-- printed slip), ~59 bits of entropy. No DB-level uniqueness is enforced
-- beyond the code column's own PRIMARY KEY; "one LIVE code" is an invariant
-- this RPC's own logic maintains (look up a live row first, only insert if
-- none exists), the same single-writer reasoning F143/F156 already use
-- elsewhere in this project rather than a harder-to-express partial unique
-- index (a WHERE expires_at > now() predicate is not IMMUTABLE, so it can't
-- back a unique index at all).
-- ============================================================================

-- ── PRE-CHECK (run on its own first; the SQL Editor shows only the last result)
SELECT
  to_regclass('public.paper_claim_codes') IS NOT NULL               AS table_already_exists,
  EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'admin_get_paper_claim_codes'
    AND pronamespace = 'public'::regnamespace)                      AS rpc_already_exists,
  EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'current_tenant_id'
    AND pronamespace = 'public'::regnamespace)                      AS helper_current_tenant_id_exists,
  EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'current_user_is_admin'
    AND pronamespace = 'public'::regnamespace)                      AS helper_current_user_is_admin_exists,
  (SELECT string_agg(slug, ',' ORDER BY slug) FROM public.tenants
    WHERE slug NOT LIKE 'pw-%')                                     AS tenants_here;
-- Expected: table_already_exists = false, rpc_already_exists = false,
-- both helper columns = true (both are long-standing SECURITY DEFINER
-- functions this project already relies on — STOP and investigate if either
-- reads false, since the new RPC below depends on both existing).
-- tenants_here: staging = demoshop,raysandjudys,riverside-comics ; production = comicstore,rjbookstop

-- ── THE CHANGE (run as one block) ──────────────────────────────────────────
BEGIN;

CREATE TABLE public.paper_claim_codes (
  code          text        PRIMARY KEY,
  tenant_id     uuid        NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  paper_user_id uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at    timestamptz NOT NULL DEFAULT now(),
  expires_at    timestamptz NOT NULL,
  used_at       timestamptz
);

CREATE INDEX idx_paper_claim_codes_paper_user ON public.paper_claim_codes (paper_user_id);
CREATE INDEX idx_paper_claim_codes_tenant     ON public.paper_claim_codes (tenant_id);

ALTER TABLE public.paper_claim_codes ENABLE ROW LEVEL SECURITY;
-- No CREATE POLICY statements, deliberately — see the header. RLS enabled
-- with zero policies means every role, including authenticated/admin, gets
-- zero rows from a direct PostgREST call; both real callers bypass RLS.

REVOKE ALL ON public.paper_claim_codes FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.paper_claim_codes TO service_role;

-- (b) admin_get_paper_claim_codes — see header for the reuse-vs-generate and
-- skip-non-paper-rows reasoning.
CREATE OR REPLACE FUNCTION public.admin_get_paper_claim_codes(user_ids uuid[])
RETURNS TABLE (paper_user_id uuid, code text, expires_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant   uuid := current_tenant_id();
  v_user     uuid;
  v_code     text;
  v_expiry   timestamptz;
  v_alphabet text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
BEGIN
  IF NOT current_user_is_admin() THEN
    RAISE EXCEPTION 'Admin only' USING ERRCODE = '42501';
  END IF;

  FOREACH v_user IN ARRAY user_ids LOOP
    IF NOT EXISTS (
      SELECT 1 FROM public.user_profiles p
       WHERE p.id = v_user AND p.tenant_id = v_tenant AND p.is_paper = true
    ) THEN
      CONTINUE; -- not this admin's own paper customer — skip, don't error the batch
    END IF;

    v_code := NULL;
    SELECT c.code, c.expires_at INTO v_code, v_expiry
      FROM public.paper_claim_codes c
     WHERE c.paper_user_id = v_user AND c.tenant_id = v_tenant
       AND c.used_at IS NULL AND c.expires_at > now()
     ORDER BY c.created_at DESC
     LIMIT 1;

    IF v_code IS NULL THEN
      SELECT string_agg(substr(v_alphabet, (floor(random() * length(v_alphabet)) + 1)::int, 1), '')
        INTO v_code
        FROM generate_series(1, 12);
      v_expiry := now() + interval '60 days';
      INSERT INTO public.paper_claim_codes (code, tenant_id, paper_user_id, expires_at)
      VALUES (v_code, v_tenant, v_user, v_expiry);
    END IF;

    paper_user_id := v_user;
    code          := v_code;
    expires_at    := v_expiry;
    RETURN NEXT;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_get_paper_claim_codes(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_paper_claim_codes(uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_paper_claim_codes(uuid[]) TO service_role;

COMMIT;

-- ── VERDICT (run on its own after the block; reads differently before/after)
SELECT
  to_regclass('public.paper_claim_codes') IS NOT NULL                AS table_now_exists,
  (SELECT relrowsecurity FROM pg_class
    WHERE oid = to_regclass('public.paper_claim_codes'))              AS rls_enabled,
  (SELECT count(*) FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'paper_claim_codes')  AS policies,
  (SELECT count(*) FROM information_schema.role_table_grants
    WHERE table_schema = 'public' AND table_name = 'paper_claim_codes'
      AND grantee IN ('anon', 'authenticated', 'PUBLIC'))             AS non_service_grants,
  EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'admin_get_paper_claim_codes'
    AND pronamespace = 'public'::regnamespace)                        AS rpc_now_exists,
  (SELECT count(*) FROM information_schema.role_routine_grants
    WHERE routine_schema = 'public' AND routine_name = 'admin_get_paper_claim_codes'
      AND grantee IN ('anon', 'PUBLIC'))                              AS rpc_anon_grants,
  (SELECT count(*) FROM information_schema.role_routine_grants
    WHERE routine_schema = 'public' AND routine_name = 'admin_get_paper_claim_codes'
      AND grantee = 'authenticated')                                  AS rpc_authenticated_grant,
  (SELECT string_agg(slug, ',' ORDER BY slug) FROM public.tenants
    WHERE slug NOT LIKE 'pw-%')                                       AS tenants_here;
-- Expected: table_now_exists = true, rls_enabled = true, policies = 0,
-- non_service_grants = 0, rpc_now_exists = true, rpc_anon_grants = 0,
-- rpc_authenticated_grant >= 1 (EXECUTE), tenants_here names the project
-- you meant to run it on.
-- Before the block runs this returns false / NULL / NULL / NULL / false /
-- NULL / NULL / <tenants>, so a run that did not land cannot read as a pass.
