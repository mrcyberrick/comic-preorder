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
-- EXPECTED: authenticated = EXECUTE, and nothing else. No anon, no PUBLIC.
-- F124 records that only four functions may legitimately carry an anon grant
-- (current_tenant_id, current_user_is_admin, get_popular_series,
-- resolve_tenant_by_slug); this is not one of them.
SELECT grantee, privilege_type
FROM information_schema.routine_privileges
WHERE routine_name = 'get_publisher_reserve_counts';


-- ── VERIFY: security mode and search_path survived CREATE OR REPLACE ────────
-- EXPECTED: prosecdef = true, proconfig contains search_path=public,
-- and exactly ONE row (a second row would mean a stray overload -- the
-- DEFAULT makes get_publisher_reserve_counts() and (text) the same function,
-- so two rows here means something else was created).
SELECT p.proname,
       pg_get_function_identity_arguments(p.oid) AS args,
       p.prosecdef,
       p.proconfig
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'get_publisher_reserve_counts';


-- ── SMOKE (run as postgres in the SQL Editor) ───────────────────────────────
-- ⚠️ The SQL Editor runs as `postgres` superuser, so current_tenant_id()
-- resolves via auth.uid() and will be NULL here -- the function will return
-- ZERO ROWS in the editor. That is expected and is NOT a failure. Run the
-- smoke below, which substitutes an explicit tenant, and do the real
-- end-to-end check from a signed-in admin browser session (plan § 5 V2).
--
-- Founding tenant ids: staging 72e29f67-39f7-42bc-a4d5-d6f992f9d790;
-- production is in the gitignored scripts/phase-4-prod-tenant-uuid.txt.
-- Substitute below.
WITH tid AS (SELECT '00000000-0000-0000-0000-000000000000'::uuid AS t),  -- <<< EDIT
hist AS (
  SELECT lower(btrim(rh.publisher)) AS k, count(*)::bigint AS n
  FROM reservation_history rh CROSS JOIN tid
  WHERE rh.tenant_id = tid.t AND btrim(COALESCE(rh.publisher, '')) <> ''
  GROUP BY 1
),
live AS (
  SELECT lower(btrim(c.publisher)) AS k, count(*)::bigint AS n
  FROM preorders p JOIN catalog c ON c.id = p.catalog_id CROSS JOIN tid
  WHERE p.tenant_id = tid.t AND btrim(COALESCE(c.publisher, '')) <> ''
  GROUP BY 1
),
reserved AS (
  SELECT u.k, sum(u.n)::bigint AS n
  FROM (SELECT * FROM hist UNION ALL SELECT * FROM live) u GROUP BY u.k
)
SELECT count(*)                                        AS publishers_with_any_history,
       count(*) FILTER (WHERE n >= 7)                  AS publishers_at_or_above_bar,
       sum(n)                                          AS total_reservation_records
FROM reserved;
--
-- EXPECTED, stated BEFORE running so a surprise triggers re-verification
-- rather than remediation (the print's own measured figures, 2026-08-24):
--   staging    publishers_at_or_above_bar ~= 4   (printed 638 rows / 15 pages)
--   production publishers_at_or_above_bar ~= 14  (printed 1,534 rows / 34 pages)
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
