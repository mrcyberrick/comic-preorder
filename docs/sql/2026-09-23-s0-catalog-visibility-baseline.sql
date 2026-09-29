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
--
-- ██ MEASURED — PRODUCTION, 2026-09-23 (Rick). Q5 still owed there. ██
--
-- Q1  rjbookstop 2026-09  2,302 rows  72 pubs  22 w/history  14 passing
--                         1,507 rows -> 33 pages
--     ✅ 14 PUBLISHERS MATCHES THE 2026-08-24 PRINT EXACTLY (14 -> 1,534 ->
--        34 pages). Now 14 -> 1,507 -> 33, the delta being a different catalog
--        month. Model validated on production as well as staging.
--     comicstore 2026-06  2 rows  1 pub  1 w/history  0 passing  -> 0 rows
-- Q2  14 shown, 8 near-misses (1-6), 50 at zero. Real reserve history at last:
--        Marvel 1,759/314 · DC 755/288 · IDW 348/114 · Image 268/246
--        Titan Comics 167/95 · Boom 99/102 · DYNAMITE 79/208 · Dark Horse 37/49
--        Mad Cave 33/59 · Archie 20/6 · ABLAZE 14/11 · Massive 12/81
--        HarperCollins 11/16 · Abrams 9/27   <-- last one over the bar
--     ✅ RECONCILES: those 14 hold 1,616 current-month titles; Q6 says 109
--        fail the FOC rule; 1,616 - 109 = 1,507 = Q1's prediction, EXACTLY.
--        Same three-way agreement as staging, on independent data.
-- Q3  restricted 332 | standard 1,122 | variant_no_ratio 848 — IDENTICAL to
--     staging. standard_with_ratio 0, ratio_malformed 0. Classes are disjoint.
-- Q4  22 distinct ratios, all well-formed; current-month values identical to
--     staging and summing to exactly 332, reconciling with Q3.
-- Q5  NOT RUN on production (the query text came back instead of results).
-- Q6  no_foc 0 | passed_today 10 | in_month_or_before 234
--     newly_hidden 109 | protected_by_reservation 2
-- Q7  catalog = 22 MB / 11,276 rows / 2,001 BYTES PER ROW
--     projected 100 tenants = 2,151 MB
-- Q8  NO ROWS — and that is a FALSE NEGATIVE. See the Q8 note below.
--
-- ██ MEASURED — STAGING, 2026-09-23 (Rick). ██
--
-- Q1  raysandjudys 2026-09  2,302 rows  72 pubs  17 w/history  5 passing
--                           688 rows -> 15 pages  <-- PAGES MATCH THE REAL
--                                                     2026-08-24 PRINT. Model
--                                                     VALIDATED.
--     demoshop     2026-09  2,288 rows  72 pubs   0 w/history  0 passing
--                             0 rows ->  0 pages  <-- F160 CONFIRMED
-- Q2  raysandjudys: 5 publishers pass -- Marvel 25/314, DC 21/288,
--     Boom Entertainment 19/102, Abrams 14/27, ABLAZE 9/11.
--     12 near-misses (1-6 reserved), incl. Archie 6/6 -- ONE short of the bar --
--     Titan Comics 4/95, IDW 1/114, Dark Horse 1/49.
--     55 publishers at 0 reserved, incl. Image Comics 0/246 and
--     DYNAMITE 0/208.  demoshop: all 72 at 0.
--     ✅ THREE-WAY ARITHMETIC RECONCILIATION, which validates Q1/Q2/Q6
--        against each other: the 5 passing publishers hold
--        314+288+102+27+11 = 742 current-month titles; Q6 says 54 of those
--        fail the FOC rule; 742 - 54 = 688 = Q1's predicted_print_rows,
--        EXACTLY. Three independently-written queries agree.
--     ⚠️ STAGING RESERVE COUNTS ARE TEST DATA (24 archived + 64 live per
--        CLAUDE.md), so this is NOT a real popularity ranking. "Image Comics
--        has 0 reservations" is a staging artifact. Production Q2 is the only
--        source for real popularity. What IS environment-independent is the
--        SHAPE: a small-catalog publisher (Abrams, 27 titles) clears the bar
--        while a 246-title major (Image) does not.
-- Q3  raysandjudys  restricted 332 | standard 1,122 | variant_no_ratio 848
--     demoshop      restricted 332 | standard 1,117 | variant_no_ratio 839
--     standard_with_ratio = 0 and ratio_malformed = 0 on every tenant.
-- Q4  22 distinct ratios on raysandjudys, 18 on demoshop, ALL well-formed.
-- Q5  raysandjudys 2,302 rows: priced 2,298 | zero_price 4 | no_price_set 0
--     demoshop     2,288 rows: priced 2,284 | zero_price 4 | no_price_set 0
--     Negative prices: 0 on every tenant.
--     ⚠️ The promotional filter governs FOUR titles, and the no-price toggle
--        governs ZERO. The mockup assumed 27 and 9. Scope cut, see the plan.
-- Q6  raysandjudys  no_foc 0 | passed_today 10 | in_month_or_before 234
--                   newly_hidden 54 | protected_by_reservation 7
-- Q7  catalog = 20 MB / 13,071 rows / 1,633 BYTES PER ROW
--     projected 100 tenants = 1,679 MB
-- Q8  demoshop only. Exactly one live F160 instance on staging.
--
-- ⚠️ THREE RESULTS THAT CHANGED THE PLAN — full detail in the plan doc:
--
-- (1) THE PUBLISHER FILTER, NOT THE FOC RULE, IS THE EXPENSIVE ONE.
--     Customers see all 2,302 rows today. Seeding the founding tenant's
--     CURRENT PRINT CONFIG would cut that to 688 — a 70% reduction, 67 of 72
--     publishers gone. The FOC rule accounts for 54 of those rows; the
--     publisher bar accounts for ~1,560. Q6's `newly_hidden = 54` is real but
--     it is the small half. Plan § 3.4 and § 4 S3 both revised.
--
-- (2) 22 DISTINCT RATIOS, NOT ~6. 1:1 1:2 1:3 1:4 1:5 1:7 1:10 1:15 1:20
--     1:25 1:30 1:40 1:50 1:60 1:75 1:100 1:125 1:200 1:250 1:300 1:500
--     1:1000. The mockup's fixed six-option dropdown misrepresents this, and
--     1:1 / 1:2 are barely restrictions at all. Current-month ratio rows sum
--     to exactly 332, reconciling with Q3 — the data is internally consistent.
--
-- (3) 1,633 BYTES PER ROW, 2.3-5x my 300-700 estimate. So Supabase free tier's
--     500 MB is exhausted at roughly 28-30 tenants on `catalog` ALONE, not at
--     100. That is a much nearer and more actionable threshold.
--
-- (4) PUBLISHER-NAME FRAGMENTATION IS ALREADY IN THE DATA, not a future risk.
--     Plan § 8 raised this as hypothetical ("if Lunar re-spells BOOM!
--     Studios..."). Q2 shows it present TODAY:
--       "Titan Comics" (95 titles) AND "Titan" (1 title)      <-- same publisher
--       "Kodansha Comics" (24) AND "Kodansha USA" (7)
--       "Fantagraphics" (11) AND "Fantagraphics Underground" (1)
--       "Random House Children's Books" / "...Publishing Group" / "...Worlds"
--       "Penguin Publishing Group" / "Penguin Young Readers Group"
--       "Disney - RHCB" / "Disney Publishing Group"
--     Also note the founding tenant's Boom is "Boom Entertainment", NOT the
--     "BOOM! Studios" this plan and the mockup both assumed.
--     TWO consequences: (a) an admin ticking "Titan Comics" silently misses
--     the title filed under "Titan"; (b) the EXISTING print filter splits
--     reserve counts across spellings, so a publisher with 4+4 reservations
--     never clears the bar of 7 that 8 would have cleared. (b) is a candidate
--     defect in shipped code — but staging's counts are test data, so it must
--     be confirmed on PRODUCTION Q2 before being filed.
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
-- ✅ ACTUAL, STAGING, run by Rick 2026-09-23 (expectations above kept visible):
--   raysandjudys  2026-09  2,302 rows  72 pubs  17 with history  5 passing
--                          688 rows -> 15 pages   <-- PAGES MATCH THE REAL PRINT
--   demoshop      2026-09  2,288 rows  72 pubs   0 with history  0 passing
--                            0 rows ->  0 pages  <-- F160 CONFIRMED
--   Also present: 4 leftover pw-* fixture tenants (F130's recorded August set,
--   still exactly four) one of which holds 1 stray catalog row with a null
--   publisher; and `riverside-comics` with no catalog at all, consistent with
--   F154's "Catalog for null" print header.
--   Publishers 4->5 and rows 638->688 since 2026-08-24 = one publisher crossing
--   the bar on a month of added reserve history. Model VALIDATED.
--   ⚠️ month_publishers is 72 here, not the 78 this plan quotes from production
--   2026-08. That figure is environment- and month-specific; do not treat 78 as
--   a constant.
--   PRODUCTION NOT YET RUN.
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
-- exists to make visible. On staging Q1 says 12 publishers sit between 1 and 6
-- reservations — this query names them.
--
-- The pub_keys CTE below is the UNION of "has titles this month" and "has
-- reserve history", so a publisher in either set appears exactly once.
-- ⚠️ Deliberately NOT a FULL OUTER JOIN. The RPC can use one because both of
-- its CTEs are already single-tenant; adding the tenant dimension to a FULL
-- OUTER breaks it — unmatched right-side rows carry a NULL tenant, so a
-- publisher with history but no current-month titles gets dropped, which is
-- precisely the row this query exists to show.
--
-- ⚠️⚠️ SELECT FROM `WITH` TO THE SEMICOLON — this query is 5 CTEs and one
-- SELECT, ~45 lines, ONE statement. It failed twice on 2026-09-23: first on a
-- missing comma after month_pubs (my bug, fixed), then with
-- `syntax error at or near "pub_keys"`, which means the selection began
-- mid-query. There are now NO standalone comment blocks between the CTEs, so
-- the body is contiguous and a click-drag from `WITH` cannot land inside it.
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
),
pub_keys AS (
  SELECT tenant_id, k FROM month_pubs
  UNION
  SELECT tenant_id, k FROM reserved
)
SELECT t.slug,
       COALESCE(mp.display, ky.k) AS publisher,
       COALESCE(r.n, 0)           AS reserved_count,
       COALESCE(mp.n, 0)          AS month_title_count,
       CASE WHEN COALESCE(r.n, 0) >= 7 THEN 'shown today' ELSE 'HIDDEN today' END AS print_status
FROM pub_keys ky
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
-- environments, F160 is real in code but has no live instance yet.
--
-- ⚠️⚠️ THIS QUERY'S PREDICATE IS TOO NARROW AND PRODUCED A FALSE NEGATIVE.
-- Run on production 2026-09-23 it returned NO ROWS, which reads as "production
-- has no live F160 instance". That conclusion is WRONG. `comicstore` holds 2
-- catalog rows and ONE reservation, so it fails this query's
-- `archived_reservations = 0` test — but Q1 shows its publishers_passing_bar is
-- **0**, so its Print Catalog is blank all the same.
--
-- F160's real condition is "no publisher clears the bar", NOT "zero reserve
-- history". Zero history is merely the most obvious way to get there; 1-6
-- reservations spread thinly gets there too. **Q1's own
-- publishers_passing_bar column is the correct test** and this query is
-- redundant beside it.
--
-- Kept, not deleted, because the lesson is the point: I wrote a check whose
-- passing and failing outputs look identical to a reader who does not
-- cross-read Q1, and it would have shipped a false claim into § 13 F160 had
-- Q1 not been in front of it. Per § Smoke Test Suite — before asking anyone to
-- run a check, ask what its output looks like when the thing has FAILED.
--
-- CORRECTED TEST (use this instead): any tenant where Q1 reports
-- month_rows > 0 AND publishers_passing_bar = 0.
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
