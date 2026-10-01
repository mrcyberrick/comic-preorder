-- STATUS: PENDING | staging=PENDING | prod=PENDING | findings=F135

-- F135 S1: give the weekly pull-feed BUILD a way to read one week's shipment
-- without holding a Supabase service-role key.
--
-- The build is moving out of the laptop's import.js and into a GitHub Actions
-- job in the PUBLIC repo mrcyberrick/weekly-pull-feed (docs/f135-decouple-feed-
-- publish.md, decision D2 = A, Rick 2026-10-01). A public repo must not hold the
-- production service_role key (full RLS bypass), so the job reads through this
-- narrow anon-callable RPC instead -- the same SECURITY DEFINER shape already
-- used by resolve_tenant_by_slug, get_popular_series() and is_maintenance_mode().
--
-- What the builder actually reads (plan § 10.2, measured from build-pull-feed.js
-- 2026-10-01): ONE table, weekly_shipment, plus a left join to catalog for
-- series_name. Nothing else. This function returns exactly that projection.
--
--   RETURNS: title, cover_url, series_name, on_sale_date
--   NEVER:   quantity, price_usd, item_code, upc, catalog_id, tenant_id, id
--
-- EXPOSURE, stated plainly: any caller holding the (public) anon key who knows a
-- tenant slug can read that tenant's shipment TITLES / COVERS / SERIES for any
-- single 7-day window. That is wider than the newsletter, which publishes one
-- week, but it is the same kind of data the public newsletter, the RSS feed and
-- the distributors' own catalogs already show, and it excludes quantities and
-- prices (the business-sensitive columns). The window is fixed at 7 days so the
-- function cannot be used to dump the table in one call.
--
-- Design points carried in from S0 (plan § 4.4):
--   * Returns EVERY row of the week, including rows with a NULL cover_url: the
--     builder derives its "skipped / collapsed" warning and the customer-facing
--     "titles arriving" count from the RAW row count.
--   * catalog is LEFT-joined (the PostgREST embed it replaces is a left join):
--     a shipment row with no catalog match still comes back, series_name NULL.
--     The join also requires the same tenant, so a cross-tenant catalog_id (the
--     F164 shape) can never leak another tenant's series name.
--   * ORDER BY covers every output column, so the output is fully deterministic
--     (F162's lesson: an RPC read without an explicit order is not stable).
--   * Takes the tenant SLUG, not the UUID, so no tenant UUID has to live in a
--     public repo.
--
-- Rollback: additive and unreferenced until S2 ships. To remove:
--   DROP FUNCTION public.get_pull_feed_week(text, date);
--
-- Run order: STAGING first (rehearsal -- staging's tenant slug is
-- 'raysandjudys', so its parity row reads that), then PRODUCTION. The builder
-- reads PRODUCTION data (there is no staging newsletter), so production is the
-- one that matters.

-- =====================================================================
-- PRE-FLIGHT (read-only) -- ONE statement, because the SQL Editor shows only
-- the last statement's result.
-- =====================================================================
SELECT
  (SELECT count(*) FROM pg_proc
   WHERE pronamespace = 'public'::regnamespace
     AND proname = 'get_pull_feed_week')                           AS name_taken,
  (SELECT count(*) FROM public.weekly_shipment)                    AS shipment_rows,
  (SELECT string_agg(slug, ', ' ORDER BY slug) FROM public.tenants) AS tenant_slugs;
-- EXPECTED: name_taken = 0 (the name is free); shipment_rows > 0;
--   production tenant_slugs = 'comicstore, rjbookstop'; staging = 'raysandjudys'
--   (plus any pw-* fixture tenants).
-- STOP if name_taken > 0: something already uses this name and the
-- CREATE OR REPLACE below would silently change it instead of creating it.

-- =====================================================================
-- MIGRATION
-- =====================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.get_pull_feed_week(p_slug text, p_week_start date)
  RETURNS TABLE (title text, cover_url text, series_name text, on_sale_date date)
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path = public, pg_temp
  AS $$
    SELECT ws.title, ws.cover_url, c.series_name, ws.on_sale_date
    FROM   public.tenants t
    JOIN   public.weekly_shipment ws ON ws.tenant_id = t.id
    LEFT   JOIN public.catalog c
           ON c.id = ws.catalog_id AND c.tenant_id = ws.tenant_id
    WHERE  t.slug = p_slug
      AND  ws.on_sale_date >= p_week_start
      AND  ws.on_sale_date <= p_week_start + 6
    ORDER  BY ws.on_sale_date, ws.title, ws.cover_url, c.series_name;
  $$;

REVOKE ALL ON FUNCTION public.get_pull_feed_week(text, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_pull_feed_week(text, date) TO anon, authenticated;

COMMIT;

-- =====================================================================
-- VERIFY -- ONE statement returning ONE row, last in the paste, so what the
-- SQL Editor shows is the verdict. Every structural check can fail and says
-- which one did. Read the `verdict` column first.
--
--   EXPECTED: verdict starts with 'OK - '. On production TODAY (2026-10-01,
--   before the Oct 2 import) slug = rjbookstop, week_start = 2026-09-28,
--   rpc_rows = table_rows = 71. After the Oct 2 import the latest week moves;
--   what must hold is rpc_rows = table_rows > 0.
--   On staging, an 'OK (structure) - parity NOT exercised' verdict is fine if
--   staging holds no shipment rows.
--   FAILURE: any verdict starting 'FAIL - ', or error 42883 (function does not
--   exist: the transaction above did not land).
-- =====================================================================
SELECT
  f.fn_count, f.definer_ok, f.search_path_ok, f.anon_exec, f.authenticated_exec,
  f.public_revoked, f.columns_ok,
  p.slug, p.week_start, p.rpc_rows, p.table_rows,
  CASE
    WHEN f.fn_count <> 1          THEN 'FAIL - function missing or duplicated'
    WHEN NOT f.definer_ok         THEN 'FAIL - not SECURITY DEFINER (anon would hit the table-permission wall)'
    WHEN NOT f.search_path_ok     THEN 'FAIL - search_path not pinned to public'
    WHEN NOT f.anon_exec          THEN 'FAIL - anon cannot EXECUTE (the Actions job would get 401)'
    WHEN NOT f.authenticated_exec THEN 'FAIL - authenticated cannot EXECUTE'
    WHEN NOT f.public_revoked     THEN 'FAIL - PUBLIC still holds EXECUTE (REVOKE did not take)'
    WHEN NOT f.columns_ok         THEN 'FAIL - projection is not exactly title, cover_url, series_name, on_sale_date'
    WHEN p.slug IS NULL           THEN 'OK (structure) - parity NOT exercised: no weekly_shipment rows in this database'
    WHEN p.table_rows = 0         THEN 'FAIL - latest week resolved to zero table rows (check the week arithmetic)'
    WHEN p.rpc_rows <> p.table_rows THEN 'FAIL - RPC row count differs from the table for the latest week'
    ELSE 'OK - F135 week RPC present, SECURITY DEFINER, anon-callable, projection exact, parity holds'
  END AS verdict
FROM (
  SELECT
    (SELECT count(*) FROM pg_proc
      WHERE pronamespace = 'public'::regnamespace
        AND proname = 'get_pull_feed_week')::int                                AS fn_count,
    COALESCE((SELECT prosecdef FROM pg_proc
      WHERE oid = to_regprocedure('public.get_pull_feed_week(text,date)')), false) AS definer_ok,
    COALESCE((SELECT array_to_string(proconfig, ';') ~ 'search_path=public' FROM pg_proc
      WHERE oid = to_regprocedure('public.get_pull_feed_week(text,date)')), false) AS search_path_ok,
    COALESCE(has_function_privilege('anon',
      to_regprocedure('public.get_pull_feed_week(text,date)'), 'EXECUTE'), false)         AS anon_exec,
    COALESCE(has_function_privilege('authenticated',
      to_regprocedure('public.get_pull_feed_week(text,date)'), 'EXECUTE'), false)         AS authenticated_exec,
    -- PUBLIC is grantee 0 in aclexplode. A NULL proacl means "default ACL",
    -- which DOES include PUBLIC, so a NULL proacl is a failure, not a pass.
    COALESCE((SELECT proacl IS NOT NULL
                AND NOT EXISTS (SELECT 1 FROM aclexplode(proacl) a WHERE a.grantee = 0)
              FROM pg_proc
              WHERE oid = to_regprocedure('public.get_pull_feed_week(text,date)')), false) AS public_revoked,
    COALESCE((SELECT pg_get_function_result(oid)
                = 'TABLE(title text, cover_url text, series_name text, on_sale_date date)'
              FROM pg_proc
              WHERE oid = to_regprocedure('public.get_pull_feed_week(text,date)')), false) AS columns_ok
) f
LEFT JOIN LATERAL (
  SELECT l.slug,
         l.wk AS week_start,
         (SELECT count(*) FROM public.get_pull_feed_week(l.slug, l.wk)) AS rpc_rows,
         (SELECT count(*) FROM public.weekly_shipment w
           WHERE w.tenant_id = l.id
             AND w.on_sale_date BETWEEN l.wk AND l.wk + 6)               AS table_rows
  FROM (
    SELECT t.id, t.slug, date_trunc('week', max(ws.on_sale_date))::date AS wk
    FROM   public.weekly_shipment ws
    JOIN   public.tenants t ON t.id = ws.tenant_id
    GROUP  BY t.id, t.slug
    ORDER  BY max(ws.on_sale_date) DESC
    LIMIT  1
  ) l
) p ON true;

-- =====================================================================
-- FUNCTIONAL CHECK (gate V1) -- from a REAL anon caller, not the SQL Editor.
-- The Editor runs as postgres and SECURITY DEFINER runs as its owner whoever
-- calls it, so neither context exercises the anon EXECUTE grant. The only
-- real test is an anon-key HTTP call. The agent runs this after you apply
-- the migration and records the output in the plan doc:
--
--   POST {SUPABASE_URL}/rest/v1/rpc/get_pull_feed_week
--   headers: apikey: <anon key>, Content-Type: application/json
--   body:    {"p_slug":"rjbookstop","p_week_start":"2026-09-28"}
--   EXPECTED: 200, a JSON array of 71 objects with exactly four keys
--             (title, cover_url, series_name, on_sale_date).
--
--   GET  {SUPABASE_URL}/rest/v1/weekly_shipment?select=title&limit=1   (anon)
--   EXPECTED: denied or an empty array -- the table stays closed to anon.
--             (Either is correct; what must NOT happen is rows coming back.)
-- =====================================================================
