-- STATUS: staging=APPLIED 2026-11-14 | prod=PENDING
-- ⚠️ Originally written prod=N/A because notify-arrivals had not reached
-- production yet. That reasoning no longer holds: the main migration this
-- file corrects (2026-11-14-s3b-email-arrivals-opt-out-and-notices.sql) was
-- applied to PRODUCTION on 2026-11-14, and that file's own RPC body is the
-- UNFIXED one (this file was never folded back into it — see that file's
-- own note). So production's arrivals_this_week_digest() has the same
-- NULL-vs-false bug staging had before this file ran there. Not yet
-- customer-visible (nothing on production calls the RPC — notify-arrivals
-- isn't deployed there), but run this file now, before it is.
-- ============================================================================
-- Customer engagement S3b — same-day follow-up fix (docs/customer-engagement-paper-to-app.md § S3b).
-- Prepared 2026-11-14, same day as the S3b migration this corrects. Operator:
-- Rick (Supabase SQL Editor). STAGING ONLY for now — this corrects a function
-- that has not yet reached production (notify-arrivals is not deployed there),
-- so there is nothing to fix on production yet; that file will simply be
-- written correctly from the start when S3b promotes.
--
-- Caught by the gate harness (s3b-gates.mjs, local-only scratchpad), BEFORE
-- any promotion and before any real customer was ever exposed to it:
-- arrivals_this_week_digest()'s is_unavailable column returned NULL instead
-- of false for a title with no withdrawal, no admin-marked outcome and no
-- ledger rejection — classic SQL three-valued logic. The expression OR'd
-- together `arrival_outcome IN (...)` (NULL when arrival_outcome IS NULL,
-- not false) with two other clauses; when every clause is false-or-null and
-- none is definitively true, `FALSE OR NULL OR FALSE` evaluates to NULL, not
-- FALSE.
--
-- NOT customer-visible today: notify-arrivals buckets rows with
-- `row.is_unavailable ? unavailable : available`, and JS treats null as
-- falsy exactly like false, so the row still landed in the right bucket in
-- the harness's real send (confirmed: title_count=2, split correctly). This
-- is a latent contract defect, not a shipped symptom — the column is
-- declared `boolean` and a boolean column that can silently read NULL is
-- wrong regardless of who happens to be null-safe about reading it today.
--
-- THE CHANGE: wrap the whole expression in COALESCE(..., false), the same
-- "collapse three-valued logic to the intended two" pattern the function's
-- OWN `arrival_outcome IS DISTINCT FROM 'arrived'` clause already uses for
-- exactly this reason. Nothing else in the function changes.
-- ============================================================================

-- ── PRE-CHECK (run on its own first)
-- ⚠️ v1 of this check used `LIKE '%COALESCE(%cd.c_withdrawn_at IS NOT NULL%'`,
-- which false-positived on the UNFIXED body too: the function already has an
-- unrelated COALESCE( earlier (in the export_code CASE), and LIKE's %...% is
-- satisfied by ANY COALESCE( appearing anywhere before the later text,
-- however far away. It read already_coalesced=true before this file had ever
-- run (caught by probing the live RPC directly with a throwaway row, not by
-- trusting this query). Replaced with a regex anchoring COALESCE( immediately
-- against the is_unavailable clause's own first condition, which only the
-- FIXED body contains at that adjacency.
SELECT
  EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'arrivals_this_week_digest'
    AND pronamespace = 'public'::regnamespace)                     AS rpc_exists,
  (SELECT pg_get_functiondef(oid) ~ 'COALESCE\s*\(\s*cd\.c_withdrawn_at IS NOT NULL'
     FROM pg_proc WHERE proname = 'arrivals_this_week_digest'
    AND pronamespace = 'public'::regnamespace)                     AS already_coalesced;
-- Expected: rpc_exists = true, already_coalesced = false (if true, this file
-- already ran — stop and verify rather than re-running).

-- ── THE CHANGE ───────────────────────────────────────────────────────────────
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
    COALESCE(
      cd.c_withdrawn_at IS NOT NULL
        OR cd.arrival_outcome IN ('not_arrived', 'damaged', 'not_available')
        OR (cd.arrival_outcome IS DISTINCT FROM 'arrived'
            AND EXISTS (SELECT 1 FROM ledger l WHERE l.distributor = cd.c_distributor
                          AND l.order_code = cd.export_code AND l.net <= 0)),
      false
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

-- ── VERDICT (run on its own after)
SELECT
  (SELECT pg_get_functiondef(oid) ~ 'COALESCE\s*\(\s*cd\.c_withdrawn_at IS NOT NULL'
     FROM pg_proc WHERE proname = 'arrivals_this_week_digest'
    AND pronamespace = 'public'::regnamespace)                     AS now_coalesced,
  (SELECT count(*) FROM information_schema.role_routine_grants
    WHERE routine_schema = 'public' AND routine_name = 'arrivals_this_week_digest'
      AND grantee IN ('anon', 'authenticated', 'PUBLIC'))          AS rpc_anon_authenticated_grants;
-- Expected: now_coalesced = true, rpc_anon_authenticated_grants = 0 (unchanged
-- — this file only replaces the function body, grants are reasserted but were
-- already correct).
