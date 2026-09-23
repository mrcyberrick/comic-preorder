-- STATUS: staging=N/A | prod=N/A  (READ-ONLY measurement pack — nothing to apply)
-- (F105) N/A is the correct token here: this file creates, alters and writes
-- NOTHING. Every statement is a SELECT. There is no applied state to record.
-- ============================================================================
-- S0 — Admin Settings catalog-visibility BASELINE MEASUREMENTS
-- Plan: docs/admin-settings-catalog-visibility.md § 4 S0 (BLOCKING gate).
-- Prepared 2026-09-23. Run: BOTH ENVIRONMENTS. Operator: Rick (SQL Editor).
--
-- Purpose: replace this plan's estimates with figures, and confirm or refute
-- F160 before anything is built on it.
--
-- ⚠️⚠️ RUN THESE ONE AT A TIME. The Supabase SQL Editor displays only the
-- LAST statement's result, so pasting the whole file shows you Q8 and silently
-- discards Q1-Q7. Highlight one query, run it, record the answer, move on.
--
-- ⚠️ The editor runs as `postgres` and BYPASSES RLS. That is deliberate here —
-- every query is explicitly scoped and GROUPED BY tenant so all tenants are
-- visible at once, and no uuid needs substituting anywhere in this file.
--
-- Each query states its EXPECTED shape before it runs. A result outside that
-- shape is a signal to re-verify, NOT to start fixing something (§ Anti-Drift:
-- "A surprising query result triggers re-verification, not immediate
-- remediation").
-- ============================================================================


-- ════════════════════════════════════════════════════════════════════════════
-- Q1 — TENANT INVENTORY + THE F160 PREDICTION.  Run this one first.
-- ════════════════════════════════════════════════════════════════════════════
-- Replicates the Print Catalog's two hardcoded filters (admin.html:5329-5330)
-- in SQL and predicts the printed row count per tenant.
--
-- EXPECTED, stated before running:
--   * production `rjbookstop`  -> publishers_passing_bar ~= 14,
--                                 predicted_print_rows ~= 1,534, pages ~= 34
--   * staging    `raysandjudys`-> publishers_passing_bar ~= 4,
--                                 predicted_print_rows ~= 638,   pages ~= 15
--   * staging    `demoshop`    -> month_rows ~= 2,288 BUT
--                                 publishers_passing_bar = 0 and
--                                 predicted_print_rows = 0   <-- THIS IS F160
--   * production `comicstore`  -> unknown; may hold no catalog rows at all
--
-- ⚠️ WHY THIS IS NOT CIRCULAR. This SQL reimplements the client filter, so it
-- cannot validate the client. It is validated BY the client: the 1,534 / 34
-- figures came from a real print on 2026-08-24. If the founding-tenant row
-- lands on them, the model is sound and the demoshop prediction of 0 can be
-- trusted. If it does NOT, stop — the discrepancy matters more than F160 does.
-- (Reserve history has grown since 08-24, so small drift is expected. A large
-- divergence is not.)
WITH latest AS (
  SELECT tenant_id, max(catalog_month) AS m FROM catalog GROUP BY tenant_id
),
reserved AS (
  SELECT tenant_id, k, sum(n)::bigint AS n
  FROM (
    SELECT rh.tenant_id, lower(btrim(rh.publisher)) AS k, count(*)::bigint AS n
    FROM reservation_history rh
    WHERE btrim(COALESCE(rh.publisher, '')) <> ''
    GROUP BY 1, 2
    UNION ALL
    SELECT p.tenant_id, lower(btrim(c.publisher)) AS k, count(*)::bigint AS n
    FROM preorders p
    JOIN catalog c ON c.id = p.catalog_id
    WHERE btrim(COALESCE(c.publisher, '')) <> ''
    GROUP BY 1, 2
  ) u
  GROUP BY 1, 2
),
passing AS (
  SELECT tenant_id, k FROM reserved WHERE n >= 7   -- MIN_RESERVED, admin.html:5249
)
SELECT
  t.slug,
  t.plan,
  l.m AS catalog_month,
  (SELECT count(*) FROM catalog c
     WHERE c.tenant_id = t.id AND c.catalog_month = l.m)                 AS month_rows,
  (SELECT count(DISTINCT lower(btrim(c.publisher))) FROM catalog c
     WHERE c.tenant_id = t.id AND c.catalog_month = l.m
       AND btrim(COALESCE(c.publisher, '')) <> '')                       AS month_publishers,
  (SELECT count(*) FROM reserved r WHERE r.tenant_id = t.id)             AS publishers_with_any_history,
  (SELECT count(*) FROM passing pa WHERE pa.tenant_id = t.id)            AS publishers_passing_bar,
  (SELECT count(*) FROM catalog c
     WHERE c.tenant_id = t.id AND c.catalog_month = l.m
       AND btrim(COALESCE(c.publisher, '')) <> ''
       AND lower(btrim(c.publisher)) IN (SELECT k FROM passing pa WHERE pa.tenant_id = t.id)
       AND (c.foc_date IS NULL OR to_char(c.foc_date, 'YYYY-MM') > l.m)) AS predicted_print_rows,
  ceil(
    (SELECT count(*) FROM catalog c
       WHERE c.tenant_id = t.id AND c.catalog_month = l.m
         AND btrim(COALESCE(c.publisher, '')) <> ''
         AND lower(btrim(c.publisher)) IN (SELECT k FROM passing pa WHERE pa.tenant_id = t.id)
         AND (c.foc_date IS NULL OR to_char(c.foc_date, 'YYYY-MM') > l.m))::numeric / 46
  )                                                                      AS predicted_print_pages
FROM tenants t
LEFT JOIN latest l ON l.tenant_id = t.id
ORDER BY t.slug;


-- ════════════════════════════════════════════════════════════════════════════
-- Q2 — PUBLISHER RESERVE COUNTS: the settings page's own data.
-- ════════════════════════════════════════════════════════════════════════════
-- This is exactly what get_publisher_reserve_counts() will return, computed
-- here with an explicit tenant grouping instead of current_tenant_id().
--
-- EXPECTED: roughly 78 rows per founding tenant; `demoshop` returns rows only
-- where month_title_count > 0 and reserved_count = 0 throughout (no history).
-- Read the top ~25 — the shape matters more than the tail.
-- ⚠️ Watch for near-miss publishers (reserved_count 5 or 6) carrying a large
-- month_title_count: those are the self-reinforcement cases the settings page
-- exists to make visible. On production 2026-08 the mockup predicted Viz Media
-- at 6 reserved with ~214 titles — confirm or correct that here.
WITH latest AS (
  SELECT tenant_id, max(catalog_month) AS m FROM catalog GROUP BY tenant_id
),
reserved AS (
  SELECT tenant_id, k, sum(n)::bigint AS n
  FROM (
    SELECT rh.tenant_id, lower(btrim(rh.publisher)) AS k, count(*)::bigint AS n
    FROM reservation_history rh
    WHERE btrim(COALESCE(rh.publisher, '')) <> '' GROUP BY 1, 2
    UNION ALL
    SELECT p.tenant_id, lower(btrim(c.publisher)) AS k, count(*)::bigint AS n
    FROM preorders p JOIN catalog c ON c.id = p.catalog_id
    WHERE btrim(COALESCE(c.publisher, '')) <> '' GROUP BY 1, 2
  ) u GROUP BY 1, 2
),
month_pubs AS (
  SELECT c.tenant_id,
         lower(btrim(c.publisher)) AS k,
         min(btrim(c.publisher))   AS display,
         count(*)::bigint          AS n
  FROM catalog c
  JOIN latest l ON l.tenant_id = c.tenant_id AND l.m = c.catalog_month
  WHERE btrim(COALESCE(c.publisher, '')) <> ''
  GROUP BY 1, 2
)
-- The key universe is the UNION of "has titles this month" and "has reserve
-- history", so a publisher in either set appears exactly once.
-- ⚠️ Deliberately NOT a FULL OUTER JOIN here. The RPC can use one because both
-- of its CTEs are already single-tenant; adding the tenant dimension to a FULL
-- OUTER breaks it — unmatched right-side rows carry a NULL tenant, so a
-- publisher with history but no current-month titles gets dropped, which is
-- precisely the row this query exists to show.
keys AS (
  SELECT tenant_id, k FROM month_pubs
  UNION
  SELECT tenant_id, k FROM reserved
)
SELECT t.slug,
       COALESCE(mp.display, ky.k) AS publisher,
       COALESCE(r.n, 0)           AS reserved_count,
       COALESCE(mp.n, 0)          AS month_title_count,
       CASE WHEN COALESCE(r.n, 0) >= 7 THEN 'shown today' ELSE 'HIDDEN today' END AS print_status
FROM keys ky
JOIN tenants t      ON t.id = ky.tenant_id
LEFT JOIN month_pubs mp ON mp.tenant_id = ky.tenant_id AND mp.k = ky.k
LEFT JOIN reserved   r  ON r.tenant_id  = ky.tenant_id AND r.k  = ky.k
ORDER BY t.slug, 3 DESC, 2;


-- ════════════════════════════════════════════════════════════════════════════
-- Q3 — COVER-CLASS POPULATIONS for the current month, and whether the three
--      classes are actually disjoint in real data.
-- ════════════════════════════════════════════════════════════════════════════
-- Classification precedence, matching the plan § 3.2: restricted first
-- (order_requirement present), then standard (variant_type null / 'Standard' /
-- 'Primary Title'), else variant.
--
-- EXPECTED: standard is the largest class (~60-70% of the month), variant next,
-- restricted ~10%. The mockup used 1,586 / 552 / 261 against 2,399 — replace
-- those with what comes back.
-- ⚠️ `standard_with_ratio` is the one to look at. If it is > 0, the three
-- classes OVERLAP and precedence genuinely matters — the settings UI must then
-- say which rule wins. If it is 0, they are naturally disjoint and precedence
-- is academic.
WITH latest AS (
  SELECT tenant_id, max(catalog_month) AS m FROM catalog GROUP BY tenant_id
)
SELECT t.slug,
       l.m AS catalog_month,
       count(*)                                                              AS month_rows,
       count(*) FILTER (WHERE c.order_requirement IS NOT NULL)               AS restricted,
       count(*) FILTER (WHERE c.order_requirement IS NULL
                          AND (c.variant_type IS NULL
                               OR c.variant_type IN ('Standard', 'Primary Title'))) AS standard,
       count(*) FILTER (WHERE c.order_requirement IS NULL
                          AND c.variant_type IS NOT NULL
                          AND c.variant_type NOT IN ('Standard', 'Primary Title'))  AS variant_no_ratio,
       count(*) FILTER (WHERE c.order_requirement IS NOT NULL
                          AND (c.variant_type IS NULL
                               OR c.variant_type IN ('Standard', 'Primary Title'))) AS standard_with_ratio,
       count(*) FILTER (WHERE c.order_requirement IS NOT NULL
                          AND c.order_requirement !~ '^[0-9]+:[0-9]+$')       AS ratio_malformed
FROM catalog c
JOIN latest l  ON l.tenant_id = c.tenant_id AND l.m = c.catalog_month
JOIN tenants t ON t.id = c.tenant_id
GROUP BY t.slug, l.m
ORDER BY t.slug;


-- ════════════════════════════════════════════════════════════════════════════
-- Q4 — DISTINCT ALLOCATION RATIOS. Drives the ratio-threshold dropdown.
-- ════════════════════════════════════════════════════════════════════════════
-- EXPECTED: a SMALL enumerable set — the mockup assumed 1:5 / 1:10 / 1:25 /
-- 1:50 / 1:100 / 1:500. This is what makes the threshold an `.in()` of short
-- strings rather than numeric parsing (plan § 3.2). If this returns dozens of
-- distinct values, or values not of the form N:M, that design changes.
SELECT t.slug,
       c.order_requirement,
       count(*)                                                    AS rows_all_months,
       count(*) FILTER (WHERE c.catalog_month = l.m)               AS rows_current_month,
       (c.order_requirement ~ '^[0-9]+:[0-9]+$')                   AS well_formed
FROM catalog c
JOIN tenants t ON t.id = c.tenant_id
LEFT JOIN (SELECT tenant_id, max(catalog_month) AS m FROM catalog GROUP BY tenant_id) l
       ON l.tenant_id = c.tenant_id
WHERE c.order_requirement IS NOT NULL
GROUP BY t.slug, c.order_requirement, 5
ORDER BY t.slug,
         -- order by the ratio's denominator so the list reads 1:5, 1:10, 1:25…
         CASE WHEN c.order_requirement ~ '^[0-9]+:[0-9]+$'
              THEN split_part(c.order_requirement, ':', 2)::int ELSE 999999 END;


-- ════════════════════════════════════════════════════════════════════════════
-- Q5 — PRICE: zero vs NULL vs priced. Two different cases, one filter each.
-- ════════════════════════════════════════════════════════════════════════════
-- EXPECTED: `priced` is nearly everything; `zero_price` a handful (free promos
-- and publisher bundles — the mockup assumed 27); `no_price_set` a handful
-- (missing import data, assumed 9). These are kept as SEPARATE toggles in the
-- plan precisely because one is a giveaway and the other is a data defect.
-- ⚠️ If no_price_set is large, that is an import-quality finding of its own,
-- not a filter requirement. Say so rather than absorbing it into this feature.
WITH latest AS (
  SELECT tenant_id, max(catalog_month) AS m FROM catalog GROUP BY tenant_id
)
SELECT t.slug,
       l.m AS catalog_month,
       count(*)                                              AS month_rows,
       count(*) FILTER (WHERE c.price_usd > 0)                AS priced,
       count(*) FILTER (WHERE c.price_usd = 0)                AS zero_price,
       count(*) FILTER (WHERE c.price_usd IS NULL)            AS no_price_set,
       count(*) FILTER (WHERE c.price_usd < 0)                AS negative_price_should_be_zero
FROM catalog c
JOIN latest l ON l.tenant_id = c.tenant_id AND l.m = c.catalog_month
JOIN tenants t ON t.id = c.tenant_id
GROUP BY t.slug, l.m
ORDER BY t.slug;


-- ════════════════════════════════════════════════════════════════════════════
-- Q6 — THE Q2 DECISION'S COST: how many titles the customer catalog would
--      newly stop showing under "hide past FOC on both surfaces".
-- ════════════════════════════════════════════════════════════════════════════
-- Rick approved hiding past-FOC on BOTH surfaces (plan § 7 Q2). The print
-- already hides them; catalog.html does not. So this is the size of a
-- customer-visible change, and it should be known before it ships.
--
-- Two definitions, because the plan offers both (§ 4 S3 / mockup group 3):
--   foc_passed_today      : foc_date < CURRENT_DATE            (literal "past")
--   foc_in_month_or_before: to_char(foc_date,'YYYY-MM') <= m   (the print's rule,
--                           stricter — it drops the whole current month)
--
-- EXPECTED: foc_in_month_or_before is the LARGER number. The important column
-- is `newly_hidden_from_customers` — rows that pass the publisher filter (so
-- they are visible today) and would be dropped by the FOC rule.
-- ⚠️ `protected_by_reservation` is the reservation exemption (plan § 3.3) at
-- work: those rows stay visible to the customer holding them no matter what.
-- If newly_hidden is large and protected is small, consider staging the FOC
-- change separately from the rest so its effect is observable on its own.
WITH latest AS (
  SELECT tenant_id, max(catalog_month) AS m FROM catalog GROUP BY tenant_id
),
reserved AS (
  SELECT tenant_id, k, sum(n)::bigint AS n FROM (
    SELECT rh.tenant_id, lower(btrim(rh.publisher)) AS k, count(*)::bigint AS n
    FROM reservation_history rh WHERE btrim(COALESCE(rh.publisher,'')) <> '' GROUP BY 1,2
    UNION ALL
    SELECT p.tenant_id, lower(btrim(c.publisher)) AS k, count(*)::bigint AS n
    FROM preorders p JOIN catalog c ON c.id = p.catalog_id
    WHERE btrim(COALESCE(c.publisher,'')) <> '' GROUP BY 1,2
  ) u GROUP BY 1,2
),
passing AS (SELECT tenant_id, k FROM reserved WHERE n >= 7)
SELECT t.slug,
       l.m AS catalog_month,
       count(*)                                                        AS month_rows,
       count(*) FILTER (WHERE c.foc_date IS NULL)                      AS no_foc_date_kept,
       count(*) FILTER (WHERE c.foc_date < CURRENT_DATE)               AS foc_passed_today,
       count(*) FILTER (WHERE to_char(c.foc_date, 'YYYY-MM') <= l.m)   AS foc_in_month_or_before,
       count(*) FILTER (WHERE to_char(c.foc_date, 'YYYY-MM') <= l.m
                          AND lower(btrim(c.publisher))
                              IN (SELECT k FROM passing pa WHERE pa.tenant_id = t.id))
                                                                       AS newly_hidden_from_customers,
       count(*) FILTER (WHERE to_char(c.foc_date, 'YYYY-MM') <= l.m
                          AND EXISTS (SELECT 1 FROM preorders p
                                       WHERE p.catalog_id = c.id AND p.fulfilled = false))
                                                                       AS protected_by_reservation
FROM catalog c
JOIN latest l ON l.tenant_id = c.tenant_id AND l.m = c.catalog_month
JOIN tenants t ON t.id = c.tenant_id
GROUP BY t.slug, l.m, t.id
ORDER BY t.slug;


-- ════════════════════════════════════════════════════════════════════════════
-- Q7 — STORAGE: settle the 100-tenant projection with a measurement.
-- ════════════════════════════════════════════════════════════════════════════
-- Plan § 8 estimates `catalog` at 280-660 MB for 100 tenants from row counts
-- alone, against Supabase free tier's 500 MB. That estimate must NOT be planned
-- on. This replaces it.
--
-- EXPECTED: on production, total_pretty in the tens of MB today. The column
-- that matters is `projected_100_tenants_pretty` — if it lands comfortably
-- under 500 MB the concern was overstated; if it exceeds it, a Supabase Pro
-- upgrade ($25/mo, 8 GB) becomes a line item to plan, not a redesign.
-- NOTE: the projection multiplies the FOUNDING tenant's row count by 100, which
-- is the right basis — demoshop/comicstore are not representative of a real
-- shop's retained months.
WITH sz AS (
  SELECT pg_total_relation_size('public.catalog') AS total_bytes,
         pg_relation_size('public.catalog')        AS heap_bytes,
         pg_indexes_size('public.catalog')          AS index_bytes,
         (SELECT count(*) FROM catalog)             AS total_rows
),
founding AS (
  SELECT count(*) AS rows_founding
  FROM catalog c
  JOIN tenants t ON t.id = c.tenant_id
  WHERE t.slug IN ('rjbookstop', 'raysandjudys')
)
SELECT pg_size_pretty(sz.total_bytes)                       AS total_pretty,
       pg_size_pretty(sz.heap_bytes)                        AS heap_pretty,
       pg_size_pretty(sz.index_bytes)                       AS indexes_pretty,
       sz.total_rows,
       f.rows_founding,
       round(sz.total_bytes::numeric / NULLIF(sz.total_rows, 0), 0) AS bytes_per_row,
       pg_size_pretty(
         (sz.total_bytes::numeric / NULLIF(sz.total_rows, 0) * f.rows_founding * 100)::bigint
       )                                                    AS projected_100_tenants_pretty
FROM sz CROSS JOIN founding f;


-- ════════════════════════════════════════════════════════════════════════════
-- Q8 — F160's POPULATION, stated directly.
-- ════════════════════════════════════════════════════════════════════════════
-- Any tenant with catalog rows and no reserve history is standing on F160
-- right now: its Print Catalog renders blank, silently.
--
-- EXPECTED: at least `demoshop` on staging. If this returns ZERO rows on both
-- environments, F160 is real in code but has no live instance yet — which is
-- still worth knowing, and should be recorded in § 13 F160 as such rather than
-- left implying an affected tenant exists.
SELECT t.slug,
       t.plan,
       (SELECT count(*) FROM catalog c WHERE c.tenant_id = t.id)              AS catalog_rows,
       (SELECT count(*) FROM preorders p WHERE p.tenant_id = t.id)            AS live_reservations,
       (SELECT count(*) FROM reservation_history rh WHERE rh.tenant_id = t.id) AS archived_reservations,
       'BLANK PRINT CATALOG — F160'                                           AS diagnosis
FROM tenants t
WHERE (SELECT count(*) FROM catalog c WHERE c.tenant_id = t.id) > 0
  AND (SELECT count(*) FROM preorders p WHERE p.tenant_id = t.id) = 0
  AND (SELECT count(*) FROM reservation_history rh WHERE rh.tenant_id = t.id) = 0
ORDER BY t.slug;
