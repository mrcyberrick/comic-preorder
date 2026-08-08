-- Phase 3.6 — automatic fulfillment for items whose on-sale date has passed.
-- Idempotent: only touches rows that are still unfulfilled.
-- Called by import.js / import-staging.js at the end of each weekly run (Step 9).
--
-- The manual fulfill path via Preorders.setFulfilledByCatalogId() remains
-- available for a future POS integration. ("Mark Fulfilled" was removed from
-- the UI on 2026-08-03 — this function is now the ONLY writer of `fulfilled`.)
--
-- ─────────────────────────────────────────────────────────────────────────
-- F122 FIX (2026-08-08) — judge on the title's CURRENT schedule, not on
-- whichever catalog row the reservation happens to point at.
--
-- The predicate used to be `c.on_sale_date < CURRENT_DATE`, reading the date
-- straight off the joined row. `preorders.catalog_id` does not survive a
-- re-listing: a re-solicited title gets a NEW catalog row under the
-- four-column upsert key (tenant_id, item_code, distributor, catalog_month),
-- and existing reservations keep pointing at the OLD one. F85's carry-forward
-- moves subscriber auto-reserves; MANUAL reservations are never moved.
--
-- So a re-dated title was closed against its SUPERSEDED schedule. Live case:
-- MIDNIGHT X-MEN #1 (75960621668000111, PRH) was pushed back nine weeks —
-- solicited 2026-05/2026-06 with on-sale 2026-08-05, re-listed 2026-07 with
-- on-sale 2026-10-07. The 2026-08-07 import marked 5 copies / 3 customers
-- fulfilled for a book that had never shipped and was not due until October,
-- and My List's past-on-sale auto-hide would then have removed it from their
-- lists entirely.
--
-- WHICH date counts, precisely: the on-sale date of the NEWEST LISTING that
-- carries one — i.e. greatest `catalog_month`, not `MAX(on_sale_date)`.
-- The two agree whenever a title is pushed BACK (the observed case) but not
-- when one is pulled FORWARD: `MAX()` would then keep judging against the old,
-- later date and the title would never auto-fulfil. Newest-listing is the
-- title's actual current schedule, which is what this is meant to read.
--
-- NULL handling is deliberate and preserves existing behaviour:
--   * rows with a NULL on_sale_date are ignored when choosing the newest
--     listing, so a newer row that has no date yet does not blank out a known
--     one;
--   * a title with NO non-null on_sale_date anywhere is excluded by the join
--     and never auto-fulfils — exactly as `NULL < CURRENT_DATE` behaved before.
--
-- Measured impact before deployment (read-only, both environments,
-- 2026-08-08): production — 3 reservations stop being auto-fulfilled (the 3
-- MIDNIGHT X-MEN #1 rows repaired by hand on 2026-08-07), **0 reservations
-- start**; staging — 0 and 0, no divergent titles present.
--
-- Does NOT fix: F115 (no arrival check — a title that was never ordered and
-- never came still closes on schedule). Different defect, same function.
-- ─────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.auto_fulfill_past_on_sale(
  p_tenant_id uuid
)
RETURNS integer
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH current_schedule AS (
    -- One row per physical comic: the newest catalog LISTING that carries an
    -- on-sale date. `catalog_month` is text 'YYYY-MM', so DESC string order is
    -- chronological. The four-column unique key guarantees at most one catalog
    -- row per (tenant, item_code, distributor, month), so this is unambiguous.
    SELECT DISTINCT ON (c.tenant_id, c.item_code, c.distributor)
           c.tenant_id,
           c.item_code,
           c.distributor,
           c.on_sale_date
      FROM catalog c
     WHERE c.tenant_id     = p_tenant_id
       AND c.on_sale_date IS NOT NULL
     ORDER BY c.tenant_id, c.item_code, c.distributor, c.catalog_month DESC
  ),
  updated AS (
    UPDATE preorders p
       SET fulfilled    = true,
           fulfilled_at = now()
      FROM catalog c
      JOIN current_schedule s
        ON  s.tenant_id   = c.tenant_id
        AND s.item_code   = c.item_code
        AND s.distributor = c.distributor
     WHERE p.catalog_id      = c.id
       AND p.tenant_id       = p_tenant_id
       AND p.fulfilled       = false
       AND s.on_sale_date    < CURRENT_DATE
     RETURNING p.id
  )
  SELECT COUNT(*)::integer FROM updated;
$$;

REVOKE ALL ON FUNCTION public.auto_fulfill_past_on_sale(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.auto_fulfill_past_on_sale(uuid) TO service_role;
