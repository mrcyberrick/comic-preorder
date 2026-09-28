-- STATUS: staging=PENDING | prod=PENDING
--         F162. This line is the applied-state record -- update it the
--         moment this runs on each environment (F105).
-- ============================================================================
-- get_ordered_codes() -- add a deterministic ORDER BY (F162)
-- Prepared 2026-09-27. Run: STAGING first, verify, then PRODUCTION.
-- Operator: Rick (Supabase SQL Editor, runs as postgres superuser).
--
-- WHY THIS EXISTS
-- ----------------
-- F162: a customer's My List can show a title as NOT ordered even though
-- admin.html's Order Builder correctly shows it "Ordered" -- confirmed live
-- 2026-09-27 against production's DICK TRACY #20 CVR B LEE WEEKS VAR
-- (item_code 0626MA0893): the order ledger holds a genuine net-3 order for
-- that exact code, but the customer-facing get_ordered_codes() RPC never
-- returned it.
--
-- Root cause: get_ordered_codes() is called from app.js with NO .range() --
-- a single, unbounded RPC call. PostgREST caps any response (a plain select
-- OR a function returning TABLE/SETOF, treated identically) at its
-- configured max-rows, measured live on production as exactly 1000 rows.
-- Production currently holds 1,895 distinct (distributor, order_code) pairs
-- in order_submissions -- comfortably past that cap -- so roughly 895 of them
-- were silently missing from every customer's "is this ordered" check. This
-- is the sixth instance of the exact defect class already on record in this
-- project (F82, F113, F139, F140, F156), just in a code path none of those
-- sessions touched.
--
-- The app.js fix (same commit) makes the client paginate this RPC the same
-- way fetchAllRows() already paginates every other unbounded query. THIS
-- file is the companion half: without an explicit ORDER BY, a GROUP BY's row
-- order is not a guaranteed, repeatable contract across two separate
-- paginated requests (page 1's LIMIT/OFFSET query and page 2's are two
-- independent executions) -- in practice Postgres will usually replay the
-- same plan and same order for an unchanged table, but "usually" is not a
-- correctness guarantee once a concurrent write (an admin recording a new
-- order, or the monthly import) can land between a customer's two page
-- requests. Ordering by the function's own GROUP BY key removes that risk
-- entirely: (distributor, order_code) is already the group's unique key, so
-- no additional tiebreaker column is needed.
--
-- Return type is UNCHANGED (still TABLE(distributor text, order_code text,
-- order_state text)), so CREATE OR REPLACE is safe -- no DROP needed, and
-- existing grants survive it.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_ordered_codes()
RETURNS TABLE(distributor text, order_code text, order_state text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT distributor, order_code,
         CASE WHEN SUM(quantity) > 0 THEN 'ordered' ELSE 'unavailable' END AS order_state
  FROM order_submissions
  WHERE tenant_id = current_tenant_id()
  GROUP BY distributor, order_code
  ORDER BY distributor, order_code;
$$;

-- Grants are untouched by CREATE OR REPLACE on an unchanged signature, but
-- re-asserted here so this file is a complete, standalone record.
GRANT EXECUTE ON FUNCTION public.get_ordered_codes() TO authenticated;
REVOKE ALL ON FUNCTION public.get_ordered_codes() FROM PUBLIC, anon;

-- ----------------------------------------------------------------------------
-- Post-DDL verification.
-- ----------------------------------------------------------------------------

-- 1. Grants unchanged.
SELECT grantee, privilege_type
FROM information_schema.routine_privileges
WHERE routine_name = 'get_ordered_codes';
-- Expected: authenticated=EXECUTE only (no anon, no PUBLIC) -- unchanged from
-- before this file ran.

-- 2. Shape unchanged (still three columns), and the function body now carries
--    an ORDER BY -- eyeball pg_get_functiondef rather than trusting the
--    editor's "success" message (F105's own lesson: a check that cannot fail
--    is not a check).
SELECT pg_get_functiondef('public.get_ordered_codes'::regprocedure);
-- Expected: body ends "GROUP BY distributor, order_code ORDER BY
-- distributor, order_code;"

-- 3. Row count and net-quantity totals are IDENTICAL to before this ran --
--    this migration changes ordering only, never which codes qualify as
--    'ordered'. Run as postgres (bypasses RLS, so current_tenant_id() is
--    NULL and this returns 0 -- confirming shape only, not real tenant
--    scoping, same caveat the original file records).
SELECT count(*) FROM public.get_ordered_codes();
-- Expected: 0 (superuser has no tenant context) -- this only confirms the
-- function still executes without error post-replace.
