-- STATUS: staging=PENDING | prod=PENDING
--         Admin Settings catalog-visibility S1. Plan:
--         docs/admin-settings-catalog-visibility.md § 3.6 / § 4 S1.
-- (F105) This line is the applied-state record. A gate that lives only in
-- prose gets missed -- F6 sat unapplied on production for 13 days because
-- nothing machine-readable said so. Update it the moment you run this file.
-- ⚠️ Write the REAL state here, with no qualifier the regex cannot see:
--    /promote-prod step 0 matches prod=(APPLIED|N/A) and returned CLEAN for
--    F155 against a line reading "prod=APPLIED (pre-F155 body)". Do not
--    repeat that.
-- ============================================================================
-- get_publisher_reserve_counts(p_catalog_month text DEFAULT NULL)
--   -> TABLE(publisher text, reserved_count bigint, month_title_count bigint)
--
-- Prepared 2026-09-23. Run: STAGING FIRST. Operator: Rick (Supabase SQL Editor).
-- Production before the S4 client code reaches it, never after (F105).
--
-- WHY THIS EXISTS:
--   admin.html's getReservedPublishers() (:5251) pages the ENTIRE
--   reservation_history table AND the ENTIRE preorders table, builds a
--   per-publisher count Map, then throws the counts away and keeps only a Set
--   of publishers clearing MIN_RESERVED = 7. Production is ~3,100 rows / 4
--   round trips today; a tenant with three years of history is 10-15 round
--   trips of 1,000 rows to produce ~78 numbers. That is the same unbounded-read
--   shape as F82 / F113 / F139 / F140 / F156.
--
--   This replaces that paging with one GROUP BY. It also returns each
--   publisher's title count for a catalog month, which is the second column the
--   settings page renders -- so it additionally retires Catalog.getPublishers()'s
--   own full-month paging (app.js:794, 3 round trips at 2,399 rows) for this
--   caller.
--
--   It makes the EXISTING Print Catalog cheaper too, so it pays for itself
--   independently of the settings page ever shipping.
--
-- TENANT SCOPE is derived from current_tenant_id() internally, never from a
--   client-supplied parameter -- same pattern as get_ordered_codes() and
--   get_popular_series(). An earlier draft of the plan specified
--   get_publisher_reserve_counts(p_tenant_id uuid); that would have let any
--   authenticated caller request another tenant's reserve history. Corrected
--   here and in the plan doc § 3.6.
--
-- WHAT IT COUNTS, and why it must match the old code exactly:
--   Every row in reservation_history plus every row in preorders is ONE
--   reservation record. Both are counted, all catalog months, regardless of
--   `fulfilled`. Keys are normalised lower(btrim(publisher)), reproducing the
--   JS `pub.trim().toLowerCase()`. Parity against the old implementation is
--   gate V2 -- see the plan doc § 5, which carries the browser-console diff.
--   Do NOT "improve" the counting rule here: a discrepancy must mean a real
--   difference, not a deliberate one.
-- ============================================================================


-- ── PRE-CHECK ───────────────────────────────────────────────────────────────
-- technical-reference.md § 4 was last re-read from live 2026-08-10; columns
-- have been added to `catalog` since. Confirm the five columns this function
-- depends on actually exist before creating anything.
-- EXPECTED: exactly 6 rows. Any fewer means the schema moved -- STOP, do not
-- create the function, and re-audit § 4 against live.
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND (   (table_name = 'reservation_history' AND column_name IN ('publisher', 'tenant_id'))
       OR (table_name = 'preorders'           AND column_name IN ('catalog_id', 'tenant_id'))
       OR (table_name = 'catalog'             AND column_name IN ('publisher'))
       OR (table_name = 'catalog'             AND column_name IN ('catalog_month')) )
ORDER BY table_name, column_name;


-- ── FUNCTION ────────────────────────────────────────────────────────────────
-- ⚠️ TRAP FOR WHOEVER EDITS THIS NEXT: in a LANGUAGE sql function, the
-- RETURNS TABLE column names (publisher, reserved_count, month_title_count)
-- are in scope as parameters inside the body. An UNQUALIFIED reference to a
-- real column also called `publisher` raises
--   ERROR: column reference "publisher" is ambiguous
-- Every publisher reference below is therefore table-qualified (rh.publisher,
-- c.publisher), the CTEs deliberately use short names (k, n, display) that
-- collide with nothing, and the final ORDER BY uses ORDINALS rather than
-- names. Keep all three properties if you touch this.
CREATE OR REPLACE FUNCTION public.get_publisher_reserve_counts(
  p_catalog_month text DEFAULT NULL
)
RETURNS TABLE(publisher text, reserved_count bigint, month_title_count bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  WITH m AS (
    -- NULL means "the tenant's latest catalog month", matching
    -- Catalog.getLatestMonth()'s behaviour on the client.
    SELECT COALESCE(
      p_catalog_month,
      (SELECT max(c.catalog_month) FROM catalog c WHERE c.tenant_id = current_tenant_id())
    ) AS month
  ),
  hist AS (
    SELECT lower(btrim(rh.publisher)) AS k, count(*)::bigint AS n
    FROM reservation_history rh
    WHERE rh.tenant_id = current_tenant_id()
      AND btrim(COALESCE(rh.publisher, '')) <> ''
    GROUP BY 1
  ),
  live AS (
    SELECT lower(btrim(c.publisher)) AS k, count(*)::bigint AS n
    FROM preorders p
    JOIN catalog c ON c.id = p.catalog_id
    WHERE p.tenant_id = current_tenant_id()
      AND btrim(COALESCE(c.publisher, '')) <> ''
    GROUP BY 1
  ),
  reserved AS (
    SELECT u.k, sum(u.n)::bigint AS n
    FROM (SELECT * FROM hist UNION ALL SELECT * FROM live) u
    GROUP BY u.k
  ),
  month_pubs AS (
    SELECT lower(btrim(c.publisher)) AS k,
           min(btrim(c.publisher))   AS display,
           count(*)::bigint          AS n
    FROM catalog c
    CROSS JOIN m
    WHERE c.tenant_id = current_tenant_id()
      AND c.catalog_month = m.month
      AND btrim(COALESCE(c.publisher, '')) <> ''
    GROUP BY 1
  )
  -- FULL OUTER so the result carries BOTH a publisher present this month with
  -- no reserve history (count 0 -- the settings page must still list it) AND a
  -- publisher with history but no titles this month (so an existing config
  -- entry is not silently dropped from the UI).
  SELECT COALESCE(mp.display, r.k)  AS publisher,
         COALESCE(r.n, 0)           AS reserved_count,
         COALESCE(mp.n, 0)          AS month_title_count
  FROM month_pubs mp
  FULL OUTER JOIN reserved r ON r.k = mp.k
  ORDER BY 2 DESC, 1;
$$;

GRANT EXECUTE ON FUNCTION public.get_publisher_reserve_counts(text) TO authenticated;
REVOKE ALL ON FUNCTION public.get_publisher_reserve_counts(text) FROM PUBLIC, anon;


-- ── VERIFY: grants ──────────────────────────────────────────────────────────
-- Aggregated into a single verdict row for the same reason as the check below:
-- a zero-row result must not be able to read as a pass.
-- F124 records that only four functions may legitimately carry an anon grant
-- (current_tenant_id, current_user_is_admin, get_popular_series,
-- resolve_tenant_by_slug); this is not one of them.
--
-- EXPECTED: verdict = 'OK - authenticated only'
SELECT
  CASE
    WHEN count(*) FILTER (WHERE grantee = 'authenticated') = 0
      THEN 'PROBLEM - authenticated has no EXECUTE; the GRANT did not run'
    WHEN count(*) FILTER (WHERE grantee IN ('anon', 'PUBLIC')) > 0
      THEN 'PROBLEM - anon or PUBLIC can execute this (F124 violation)'
    ELSE 'OK - authenticated only'
  END                                             AS verdict,
  COALESCE(string_agg(DISTINCT grantee, ', '), '(none)') AS grantees
FROM information_schema.routine_privileges
WHERE routine_name = 'get_publisher_reserve_counts';


-- ── VERIFY: does it exist, and did CREATE OR REPLACE keep its properties ────
-- Written as an AGGREGATE so it always returns exactly ONE row with a spelled-
-- out verdict. A plain `SELECT ... WHERE proname = ...` returns ZERO rows when
-- the function is absent, and the editor shows that as "Success. No rows
-- returned" -- indistinguishable from a pass to anyone not counting rows. That
-- ambiguity already produced one false conclusion this session (S0's Q8 read as
-- "production has no F160 instance" when it has one), so it is not repeated.
--
-- EXPECTED: verdict = 'OK - 1 definition, SECURITY DEFINER, search_path pinned'
SELECT
  CASE
    WHEN count(*) = 0 THEN 'MISSING - the CREATE did not run. Re-run this file from the top.'
    WHEN count(*) > 1 THEN 'PROBLEM - ' || count(*) || ' definitions exist; a stray overload was left behind'
    WHEN bool_and(p.prosecdef) IS NOT TRUE THEN 'PROBLEM - not SECURITY DEFINER'
    WHEN bool_and(array_to_string(p.proconfig, ',') LIKE '%search_path%') IS NOT TRUE
      THEN 'PROBLEM - search_path is not pinned (F23/Pattern E footgun)'
    ELSE 'OK - 1 definition, SECURITY DEFINER, search_path pinned'
  END                                                   AS verdict,
  count(*)                                              AS definitions,
  COALESCE(string_agg(pg_get_function_identity_arguments(p.oid), ' | '), '-') AS signatures,
  COALESCE(string_agg(array_to_string(p.proconfig, ','), ' | '), '-')         AS settings
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'get_publisher_reserve_counts';


-- ── SMOKE (run as postgres in the SQL Editor) ───────────────────────────────
-- ⚠️ The SQL Editor runs as `postgres` superuser, so current_tenant_id()
-- resolves via auth.uid() and will be NULL here -- calling the function
-- directly returns ZERO ROWS in the editor. That is expected and is NOT a
-- failure. This smoke replicates the aggregate with explicit tenant scoping
-- instead; the real end-to-end check is a signed-in admin browser session
-- (plan § 5.1 V2).
--
-- ⚠️⚠️ REWRITTEN 2026-09-23 BECAUSE THE FIRST VERSION WAS A FOOTGUN. It opened
-- `WITH tid AS (SELECT '00000000-0000-0000-0000-000000000000'::uuid ...)` with
-- a `-- <<< EDIT` marker and told the operator to substitute a founding-tenant
-- uuid from a gitignored scratch file. Run unedited it returns
--     publishers_with_any_history 0 | publishers_at_or_above_bar 0 | total null
-- which reads as a plausible "this tenant has no reserve history" answer rather
-- than "you did not edit the query" -- and that is exactly the failure this
-- file's own § Smoke Test Suite rule warns about: a check whose failing output
-- is indistinguishable from a real result. (`sum()` over zero rows giving NULL
-- was the only tell.) It happened on the first real run.
--
-- The version below needs NO EDITING: it groups by tenant and names each one,
-- so every tenant is visible at once, a missing substitution is impossible, and
-- an empty result would mean "this database has no tenants" -- which is
-- unmistakable. Same shape as S0's Q1, for the same reason.
WITH hist AS (
  SELECT rh.tenant_id, lower(btrim(rh.publisher)) AS k, count(*)::bigint AS n
  FROM reservation_history rh
  WHERE btrim(COALESCE(rh.publisher, '')) <> ''
  GROUP BY 1, 2
),
live AS (
  SELECT p.tenant_id, lower(btrim(c.publisher)) AS k, count(*)::bigint AS n
  FROM preorders p
  JOIN catalog c ON c.id = p.catalog_id
  WHERE btrim(COALESCE(c.publisher, '')) <> ''
  GROUP BY 1, 2
),
reserved AS (
  SELECT u.tenant_id, u.k, sum(u.n)::bigint AS n
  FROM (SELECT * FROM hist UNION ALL SELECT * FROM live) u
  GROUP BY 1, 2
)
SELECT t.slug,
       t.plan,
       COALESCE(count(r.k), 0)                              AS publishers_with_any_history,
       COALESCE(count(r.k) FILTER (WHERE r.n >= 7), 0)       AS publishers_at_or_above_bar,
       COALESCE(sum(r.n), 0)                                AS total_reservation_records
FROM tenants t
LEFT JOIN reserved r ON r.tenant_id = t.id
GROUP BY t.slug, t.plan
ORDER BY 5 DESC, 1;
--
-- EXPECTED, stated BEFORE running so a surprise triggers re-verification
-- rather than remediation. These are now MEASURED values, not the 2026-08-24
-- print record -- S0 ran on both environments 2026-09-23:
--   staging    raysandjudys -> 17 with history, 5 at/above bar
--               demoshop, riverside-comics, 4x pw-* -> all 0 / 0 / 0
--   production rjbookstop   -> 22 with history, 14 at/above bar
--               comicstore  -> 1 with history, 0 at/above bar
--
-- ⚠️ A row reading 0 / 0 / 0 is now a MEANINGFUL result, not a broken query:
-- it is F160's population. Every such tenant's Print Catalog renders blank.
--
-- ⚠️ This is CORROBORATION, not proof, and the direction is not guaranteed.
-- Counts are NOT strictly monotonic: archiving moves a row from preorders into
-- reservation_history (total unchanged), but a customer cancelling before the
-- archive removes it from preorders without ever adding it to history (total
-- falls). So a small drift either way is normal after a month. A LARGE
-- divergence from 4 / 14 means stop and find out why before proceeding.
--
-- The definitive parity gate is V2 in the plan doc § 5: run the OLD client
-- implementation and this RPC in the same signed-in browser session and diff
-- the two sets. Comparing this file's SQL against SQL that reimplements the
-- same rule would be circular -- a verification step that cannot fail is not a
-- verification step.


-- ── ROLLBACK ────────────────────────────────────────────────────────────────
-- Safe at any time while STATUS reads PENDING on the other environment: the
-- function has no callers until S4 ships, so dropping it is inert.
-- DROP FUNCTION IF EXISTS public.get_publisher_reserve_counts(text);
