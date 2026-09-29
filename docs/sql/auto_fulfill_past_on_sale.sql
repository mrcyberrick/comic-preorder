-- STATUS: staging=APPLIED 2026-09-05 (F155 S3a body) | prod=APPLIED 2026-09-05 (F155 S3a body)
--         Staging verified live 3/3 by seeding three discriminating fixtures and
--         calling the function: the RPC returned 2, not 3 -- the no-evidence,
--         recently-released row was held back, which the pre-F155 body fulfils.
--         Production applied 2026-09-05 by Rick, immediately after PR #150 merged
--         (client-first sequencing -- see the F155 S3(a) block below for why that
--         order is the reverse of the usual).
--
--         ⚠️ CORRECTED 2026-09-05. This line previously read
--         "prod=APPLIED 2026-08-08 (pre-F155 body)" with the caveat in prose
--         underneath. /promote-prod step 0 matches on `prod=(APPLIED|N/A)`, so it
--         returned CLEAN while production was missing this body entirely -- the
--         exact "gate that lives only in prose" failure F105 is named for,
--         reproduced by the very file that documents it. A qualifier the regex
--         cannot see is not a qualifier. Say PENDING until the new body is run.
-- (F105) This line is the applied-state record. A gate that lives only in
-- prose gets missed -- F6 sat unapplied on production for 13 days because
-- nothing machine-readable said so. Update it the moment you run this file.
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
-- ─────────────────────────────────────────────────────────────────────────
-- F155 S3(a) (2026-09-04) — BOUNDED DEFERRAL when nothing shows the title
-- actually arrived. Approved by Rick 2026-09-04.
--
-- WHY THIS EXISTS. F122 above fixed judging against a superseded schedule,
-- but it can only work when a NEWER listing exists to read. For PRH there is
-- never one: 0 of 5,123 MainIdentifiers appear in more than one monthly file,
-- and a PRH catalog's master data FREEZES roughly three months out (2026-05's
-- is byte-identical across re-downloads; its change reports stop 2026-07-31)
-- while a tenth of its titles have yet to ship. So a late revision — DNX #1
-- moving 2026-09-02 -> 2026-09-16 is the live case — is unreachable from
-- every distributor endpoint, and F122's newest-listing logic never fires.
-- The row is then fulfilled on a date that is simply wrong.
--
-- THIS IS NOT F115 OPTION A, AND THE DIFFERENCE MATTERS. Option A — gating
-- fulfilment on shipment evidence — was rejected, and import.js's own
-- findUnverifiedFulfillments() docblock states why: "REPORTS, NEVER BLOCKS.
-- Absence of a shipment row is not proof of non-arrival ... so gating
-- fulfillment on this would trade a silent miss for a silent stall."
--
-- That objection is correct and is preserved here. This does not block. It
-- DEFERS, by a bounded 14 days, and then fulfils exactly as before:
--
--   * shipment evidence present  -> fulfil immediately, behaviour UNCHANGED.
--     (F115's real September production import: 212 of 218 rows.)
--   * no evidence                -> wait until on_sale_date + 14 days, then
--     fulfil anyway, with F115's arrival_outcome = 'unknown' as today.
--
-- Nothing stalls forever. 14 days is two full shipment cycles on the store's
-- Friday-pull / Monday-arrival / Wednesday-fulfil rhythm, which is precisely
-- the window a corrected date (F155 S2's check-dates.js) or a late invoice
-- needs to land.
--
-- THE HALF THAT MAKES THE DEFERRAL SAFE IS NOT IN THIS FILE. A deferred row
-- is fulfilled = false, so admin.html's neverArrivedFromFulfilled() does NOT
-- pick it up — it requires p.fulfilled. It falls to computeBackorderRisk(),
-- whose first test used to be `ledgerNetQty > 0` — "ordered, cleared" — which
-- is exactly why DNX #1 appeared on no panel at all. That test order is
-- changed in the same commit as this file. **Do not apply this SQL without
-- that client change, or this recreates the silent stall F115 rejected.**
--
-- The grace window is a literal, not a parameter, deliberately: adding an
-- argument would change the signature, and CREATE OR REPLACE cannot do that —
-- it would leave a second overload behind while import.js kept calling the
-- one-argument version.
--
-- Does NOT fix: a title that never arrives at all still closes after the
-- grace window with arrival_outcome = 'unknown'. That is F115's design and is
-- unchanged — this only buys time for the date to be corrected first.
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
       -- F155 S3(a): defer, bounded. Either something shows it arrived, or
       -- the 14-day grace window has elapsed and we close it regardless.
       AND (
         EXISTS (
           -- The same three-key match classifyArrivalOutcomes() uses (F76):
           -- weekly_shipment.item_code is NULL on Lunar rows, where the code
           -- lands in `upc` instead, so all three keys are needed and each
           -- must guard against NULL = NULL never being true.
           SELECT 1
             FROM weekly_shipment w
            WHERE w.tenant_id = p_tenant_id
              AND (   w.catalog_id = c.id
                   OR (c.upc       IS NOT NULL AND w.upc       = c.upc)
                   OR (c.item_code IS NOT NULL AND w.item_code = c.item_code))
         )
         OR s.on_sale_date < CURRENT_DATE - 14
       )
     RETURNING p.id
  )
  SELECT COUNT(*)::integer FROM updated;
$$;

-- Least privilege: service_role only. This function is called by the import
-- script and by nothing else — no client code path reaches it.
--
-- `anon` and `authenticated` are named explicitly and deliberately. Supabase
-- bootstraps `ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON
-- FUNCTIONS TO anon, authenticated`, so every new function in `public` starts
-- with those two grants — and `REVOKE ... FROM PUBLIC` does NOT remove them,
-- because a role grant is not the PUBLIC grant. A file revoking only PUBLIC
-- therefore leaves both roles able to execute. Without these two names this
-- file re-opens that gap on any environment it is ever run against fresh
-- (a rebuild, or a new tenant's project). See F124.
REVOKE ALL ON FUNCTION public.auto_fulfill_past_on_sale(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.auto_fulfill_past_on_sale(uuid) TO service_role;
