-- ============================================================================
-- get_ordered_codes() — minimal customer-facing read of order_submissions
-- Prepared 2026-08-02 (F101/F102 session, scope extension approved by Rick
-- mid-session — see § 13 F101/F102 closeout for the "why").
-- Run: STAGING. Operator: Rick (Supabase SQL Editor).
--
-- WHY THIS EXISTS:
--   order_submissions RLS is deliberately admin-only (docs/sql/order-
--   submissions.sql — "admins read tenant order_submissions"). Rick's
--   direction: My List's existing "✓ Order placed" status/lock (currently
--   driven only by preorders.fulfilled) should ALSO trigger once the store
--   has recorded an order for that code via the new "Mark Ordered" action —
--   independent of fulfilled (fulfilled stays arrival-only per the § 4.6
--   additive decision). A regular customer session cannot SELECT
--   order_submissions directly, so this SECURITY DEFINER function exposes
--   the one fact customers need (which codes are on order) without exposing
--   quantities, submission dates, or titles — the full ledger stays
--   admin-only.
--
-- Tenant scope is derived from current_tenant_id() internally, never from a
-- client-supplied parameter (same pattern as every other RLS-adjacent
-- function — see technical-reference.md § "Why exposing tenant id is safe").
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_ordered_codes()
RETURNS TABLE(distributor text, order_code text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT DISTINCT distributor, order_code
  FROM order_submissions
  WHERE tenant_id = current_tenant_id();
$$;

GRANT EXECUTE ON FUNCTION public.get_ordered_codes() TO authenticated;
REVOKE ALL ON FUNCTION public.get_ordered_codes() FROM PUBLIC, anon;

-- Verify: grants are correct
SELECT grantee, privilege_type
FROM information_schema.routine_privileges
WHERE routine_name = 'get_ordered_codes';
-- Expected: authenticated=EXECUTE only (no anon, no PUBLIC)

-- Smoke: run as postgres superuser, should return the 857-row backfill's
-- distinct code count (expect count > 0 after S5)
SELECT count(*) FROM public.get_ordered_codes();
