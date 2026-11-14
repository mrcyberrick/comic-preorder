-- STATUS: staging=PENDING | prod=PENDING
-- ============================================================================
-- Customer engagement S3b (docs/customer-engagement-paper-to-app.md § S3b)
-- Prepared 2026-11-14. Operator: Rick (Supabase SQL Editor, runs as postgres).
-- Run: STAGING first, then PRODUCTION, both BEFORE the notify-arrivals Edge
--      Function or any client code that reads these. The cron job itself is
--      a SEPARATE, later, production-only file (2026-11-14-s3b-notify-arrivals-cron.sql)
--      so a staging-only N/A on it never blocks /promote-prod step 0.
--
-- Four changes, one transaction:
--   (a) user_profiles.email_arrivals boolean NOT NULL DEFAULT true — the
--       opt-out (D5). A customer toggles it themselves on My List.
--   (b) public.arrival_notices (tenant_id, user_id, week_start, sent_at),
--       UNIQUE on the first three — the no-double-send guard. Written only by
--       notify-arrivals (service role); admins can read it, nobody else.
--   (c) public.arrivals_this_week_digest(tenant, week_start, week_end): the
--       read notify-arrivals calls. Matches open reservations to this week's
--       weekly_shipment rows the SAME three-key way auto_fulfill_past_on_sale()
--       does (docs/sql/auto_fulfill_past_on_sale.sql) — never by on_sale_date
--       alone, which is exactly the "it's here" false the F115 S3b note warns
--       against. Classifies each matched row withdrawn / ledger-rejected /
--       admin-marked the same way admin.html's This Week tab and the ledger
--       helpers in app.js already do (exportCode(), ledgerRejected()) — this
--       is that logic moved server-side so the Edge Function does not
--       re-derive it in TypeScript. service_role only; no client ever calls it.
--   (d) ⚠️ WIDENS THE F182 FIX. The self-update guard trigger on
--       user_profiles (user_profiles_guard_self_update, security-sensitive,
--       details in the operator's local-only security notes) default-denies
--       any column a customer tries to change on their OWN profile except an
--       explicit allowlist — today just has_seen_welcome. Adding (a) without
--       this would make every customer's own toggle write fail 42501,
--       silently, because the column exists and the client's UPDATE would
--       look correct. This block widens the allowlist to
--       {has_seen_welcome, email_arrivals} and nothing else — it does NOT
--       reopen is_admin/status/tenant_id/id, which stay admin-only.
-- ============================================================================

-- ── PRE-CHECK (run on its own first; the SQL Editor shows only the last result)
SELECT
  EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'user_profiles'
      AND column_name = 'email_arrivals')                          AS column_already_exists,
  to_regclass('public.arrival_notices') IS NOT NULL                AS table_already_exists,
  EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'arrivals_this_week_digest'
    AND pronamespace = 'public'::regnamespace)                     AS rpc_already_exists,
  (SELECT pg_get_functiondef(oid) FROM pg_proc
    WHERE proname = 'user_profiles_guard_self_update'
      AND pronamespace = 'public'::regnamespace)                   AS current_guard_body,
  (SELECT string_agg(slug, ',' ORDER BY slug) FROM public.tenants
    WHERE slug NOT LIKE 'pw-%')                                    AS tenants_here;
-- Expected: column_already_exists = false, table_already_exists = false,
-- rpc_already_exists = false.
-- current_guard_body should contain exactly `- 'has_seen_welcome'` (singular,
-- one key) — if it already mentions email_arrivals, or looks different from
-- that shape, STOP and read it in full before proceeding; this block assumes
-- the single-key form and replaces it wholesale.
-- tenants_here: staging = demoshop,raysandjudys,riverside-comics ; production = comicstore,rjbookstop

-- ── THE CHANGE (run as one block) ──────────────────────────────────────────
BEGIN;

ALTER TABLE public.user_profiles
  ADD COLUMN email_arrivals boolean NOT NULL DEFAULT true;

CREATE TABLE public.arrival_notices (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id  uuid        NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  user_id    uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  week_start date        NOT NULL,
  sent_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, user_id, week_start)
);

ALTER TABLE public.arrival_notices ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admins read tenant arrival notices" ON public.arrival_notices
  FOR SELECT TO authenticated
  USING (current_user_is_admin() AND tenant_id = current_tenant_id());

REVOKE ALL ON public.arrival_notices FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.arrival_notices TO authenticated;
GRANT ALL ON public.arrival_notices TO service_role;

-- (c) The per-customer "what's arriving, what isn't" read notify-arrivals
-- calls, one tenant and one Mon-Sun week at a time. Three-key shipment match
-- identical to auto_fulfill_past_on_sale(); withdrawn/ledger-rejected/
-- admin-marked classification identical to admin.html's renderThisWeek() +
-- app.js's exportCode()/ledgerRejected(). c.tenant_id is checked again even
-- though catalog_id implies it, as a second guard against the F164 cross-
-- tenant catalog_id shape (filed, not yet closed by a database trigger).
CREATE OR REPLACE FUNCTION public.arrivals_this_week_digest(
  p_tenant_id  uuid,
  p_week_start date,
  p_week_end   date
)
RETURNS TABLE (
  user_id            uuid,
  catalog_id         uuid,
  title              text,
  series_name        text,
  publisher          text,
  distributor        text,
  price_usd          numeric,
  quantity           integer,
  is_unavailable     boolean,
  unavailable_reason text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH ledger AS (
    SELECT distributor, order_code, SUM(quantity) AS net
      FROM order_submissions
     WHERE tenant_id = p_tenant_id
     GROUP BY distributor, order_code
  ),
  shipment AS (
    SELECT DISTINCT catalog_id, item_code, upc
      FROM weekly_shipment
     WHERE tenant_id = p_tenant_id
       AND on_sale_date BETWEEN p_week_start AND p_week_end
  ),
  coded AS (
    -- exportCode(c, distributor) from app.js, in SQL: PRH tries isbn first,
    -- everyone else tries item_code first, both falling through to the
    -- other two keys. NULLIF so an empty string behaves like NULL, matching
    -- the JS `||` chain exactly.
    SELECT p.*, c.id AS c_id, c.tenant_id AS c_tenant_id, c.title AS c_title,
           c.series_name AS c_series_name, c.publisher AS c_publisher,
           c.distributor AS c_distributor, c.price_usd AS c_price_usd,
           c.withdrawn_at AS c_withdrawn_at,
           CASE WHEN c.distributor = 'PRH'
                THEN COALESCE(NULLIF(c.isbn,''), NULLIF(c.item_code,''), NULLIF(c.upc,''))
                ELSE COALESCE(NULLIF(c.item_code,''), NULLIF(c.upc,''), NULLIF(c.isbn,''))
           END AS export_code
      FROM preorders p
      JOIN catalog c ON c.id = p.catalog_id
      JOIN shipment s
        ON  s.catalog_id = c.id
        OR (c.upc       IS NOT NULL AND s.upc       = c.upc)
        OR (c.item_code IS NOT NULL AND s.item_code = c.item_code)
     WHERE p.tenant_id = p_tenant_id
       AND c.tenant_id  = p_tenant_id
       AND p.fulfilled  = false
  )
  SELECT
    cd.user_id,
    cd.c_id,
    cd.c_title,
    cd.c_series_name,
    cd.c_publisher,
    cd.c_distributor,
    cd.c_price_usd,
    cd.quantity,
    (cd.c_withdrawn_at IS NOT NULL
      OR cd.arrival_outcome IN ('not_arrived', 'damaged', 'not_available')
      OR (cd.arrival_outcome IS DISTINCT FROM 'arrived'
          AND EXISTS (SELECT 1 FROM ledger l WHERE l.distributor = cd.c_distributor
                        AND l.order_code = cd.export_code AND l.net <= 0))
    ) AS is_unavailable,
    CASE
      WHEN cd.c_withdrawn_at IS NOT NULL      THEN 'Withdrawn by the distributor'
      WHEN cd.arrival_outcome = 'not_available' THEN 'The store could not get this title'
      WHEN cd.arrival_outcome = 'not_arrived'   THEN 'Did not arrive'
      WHEN cd.arrival_outcome = 'damaged'       THEN 'Arrived damaged'
      WHEN EXISTS (SELECT 1 FROM ledger l WHERE l.distributor = cd.c_distributor
                     AND l.order_code = cd.export_code AND l.net <= 0)
                                               THEN 'Rejected by the supplier'
      ELSE NULL
    END AS unavailable_reason
  FROM coded cd;
$$;

REVOKE ALL ON FUNCTION public.arrivals_this_week_digest(uuid, date, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.arrivals_this_week_digest(uuid, date, date) TO service_role;

-- (d) Widen the F182 self-update guard's allowlist from one key to two.
-- SET search_path and the admin/role short-circuits are unchanged from the
-- live function — only the allowlist set grows, from a single `- 'text'` key
-- removal to a `- text[]` multi-key removal (both are valid jsonb operators).
CREATE OR REPLACE FUNCTION public.user_profiles_guard_self_update()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  -- f182 guard, widened for S3b's customer-toggleable email_arrivals column
  IF current_user NOT IN ('anon', 'authenticated') THEN RETURN NEW; END IF;
  IF public.current_user_is_admin() IS TRUE THEN RETURN NEW; END IF;
  IF (to_jsonb(NEW) - ARRAY['has_seen_welcome', 'email_arrivals'])
     IS DISTINCT FROM (to_jsonb(OLD) - ARRAY['has_seen_welcome', 'email_arrivals']) THEN
    RAISE EXCEPTION 'That part of a profile can only be changed by a shop admin' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END $$;

COMMIT;

-- ── VERDICT (run on its own after the block; reads differently before/after)
SELECT
  EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'user_profiles'
      AND column_name = 'email_arrivals')                          AS column_now_exists,
  (SELECT count(*) FROM public.user_profiles WHERE email_arrivals IS NOT true) AS non_default_rows,
  (SELECT relrowsecurity FROM pg_class
    WHERE oid = to_regclass('public.arrival_notices'))             AS rls_enabled,
  (SELECT count(*) FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'arrival_notices')  AS policies,
  (SELECT count(*) FROM information_schema.role_table_grants
    WHERE table_schema = 'public' AND table_name = 'arrival_notices'
      AND grantee IN ('anon', 'PUBLIC'))                            AS anon_grants,
  (SELECT string_agg(privilege_type, ',' ORDER BY privilege_type)
     FROM information_schema.role_table_grants
    WHERE table_schema = 'public' AND table_name = 'arrival_notices'
      AND grantee = 'authenticated')                                AS authenticated_grants,
  (SELECT pg_get_functiondef(oid) LIKE '%email_arrivals%' FROM pg_proc
    WHERE proname = 'user_profiles_guard_self_update'
      AND pronamespace = 'public'::regnamespace)                    AS guard_widened,
  EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'arrivals_this_week_digest'
    AND pronamespace = 'public'::regnamespace)                      AS rpc_now_exists,
  (SELECT count(*) FROM information_schema.role_routine_grants
    WHERE routine_schema = 'public' AND routine_name = 'arrivals_this_week_digest'
      AND grantee IN ('anon', 'authenticated', 'PUBLIC'))            AS rpc_anon_authenticated_grants,
  (SELECT string_agg(slug, ',' ORDER BY slug) FROM public.tenants
    WHERE slug NOT LIKE 'pw-%')                                     AS tenants_here;
-- Expected: column_now_exists = true, non_default_rows = 0 (every existing
-- row defaulted to true, nobody is pre-opted-out), rls_enabled = true,
-- policies = 1, anon_grants = 0, authenticated_grants = SELECT,
-- guard_widened = true, rpc_now_exists = true, rpc_anon_authenticated_grants = 0
-- (service_role only — anon/authenticated must NOT be able to call this, it
-- has no tenant check against the CALLER, only the passed-in p_tenant_id),
-- tenants_here names the project you meant to run it on.
-- Before the block runs this returns false / NULL / NULL / 0 / 0 / NULL /
-- false / false / NULL / NULL, so a run that did not land cannot read as a pass.
