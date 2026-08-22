-- STATUS: staging=APPLIED 2026-08-22 | prod=NOT STARTED
--         F136 S2. Steps 1-3 run by Rick on staging 2026-08-22. V5/V6 GREEN,
--         confirmed independently via a fresh f136-audit.js run: catalog rows
--         9,951 -> 8,954 (delta 997, exact match to the pre-run "safe" count);
--         duplicate pairs 977 -> 1 (only the pre-existing blocked group
--         remains); safe/blocked 997/1 -> 0/1 (blocked row untouched, exactly
--         as stranded as before -- dedupe does not un-strand a REFERENCED
--         row, see plan § 11 S2). Preorder counts unchanged, 56/22/34 total/
--         unfulfilled/fulfilled before and after (Rick, SQL Editor). Prod run
--         is Part D/S3, Rick-gated, not this file's scope. (F105) A gate
--         that lives only in prose gets missed — F6 sat unapplied on
--         production for 13 days because nothing machine-readable said so.
-- ============================================================================
-- dedupe_catalog_months(p_tenant_id uuid) — F136 Part B
-- Prepared 2026-08-22 (F136 S2 build session).
-- Plan: docs/f136-catalog-month-integrity.md § 4 Part B, § 6 (V5-V6).
-- Run: STAGING ONLY. Operator: Rick (Supabase SQL Editor). Do NOT run against
-- production — this file has no prod branch and F136 S3 (prod repoints + prod
-- dedupe) is a separate, later, Rick-gated session.
--
-- WHAT THIS FIXES:
--   F136 Part 2 — catalog carries 2,666 (prod) / 977 (staging) (item_code,
--   distributor) pairs with more than one catalog_month row, almost all from
--   one operator-invisible month-assignment mistake (§ 2 of the plan doc).
--   preorders.catalog_id pins a reservation to ONE specific row, so a
--   reservation sitting on the non-maintained duplicate can never receive a
--   future distributor date correction — the same failure class as F136
--   Part 1, arrived at structurally. This function is the self-healing
--   cleanup: called from refreshCatalog()'s new-month branch (Part B3, wired
--   in the same commit as this file lands) so the bloat cannot silently
--   reaccumulate the way it did the first time.
--
-- THE RULE (plan § 3(b), re-derived, not re-copied):
--   Within one tenant, group catalog rows by (item_code, distributor). The
--   row carrying the HIGHEST catalog_month in that group is the one the live
--   monthly cycle maintains going forward. Every OTHER row in the group is
--   safe to delete UNLESS it is referenced by any preorders row, in ANY
--   fulfilled state — a fulfilled HISTORICAL preorder still holds a NOT NULL
--   FK to catalog.id (preorders.catalog_id, F10, ON DELETE NO ACTION), so
--   deleting a referenced row would break that FK regardless of whether the
--   reservation is still open. This needs no per-distributor canonical rule
--   and cannot orphan a reservation, because it refuses to touch a row
--   preorders still points at.
--
-- WHY A SEPARATE FUNCTION, NOT A WIDENED purge_stale_catalog:
--   purge_stale_catalog's predicate is date-driven (on_sale_date < cutoff);
--   this rule is not date-driven at all — a duplicate can be perfectly
--   "current" (on-sale date in the future) and still need deleting. F110's
--   history (delete_dropped_catalog_items originally overloaded past its
--   single-month scope) is the standing warning against folding two
--   different deletion rules into one function's mandate.
--
-- catalog_month is `text` in `YYYY-MM` shape (docs/technical-reference.md
-- line 504), so MAX()/`<` on it sort correctly as calendar order — the same
-- assumption import.js's `confirmedMonth > currentDbMonth` string comparison
-- already relies on (import.js ~1984) and f136-audit.js's
-- classifyDedupSafety() re-derives independently via
-- `.sort().at(-1)`. This function's predicate and that JS function's
-- predicate must keep agreeing — that agreement is V5's evidence.
--
-- Grants: service_role only. This is called exclusively from the import
-- scripts' service-role path (refreshCatalog(), same call site pattern as
-- purge_stale_catalog immediately above it), never from the browser client.
-- Supabase auto-grants EXECUTE to anon AND authenticated on function
-- creation (ALTER DEFAULT PRIVILEGES) — REVOKE ... FROM PUBLIC alone does
-- NOT remove either (F124). Both are revoked explicitly below, matching
-- purge_old_usage_events.sql's precedent (the closest sibling: also
-- tenant-scoped, also service-role-only, also a bulk DELETE-and-count).
-- ============================================================================

-- ── STEP 1 — create the function (the migration proper) ────────────────────
CREATE OR REPLACE FUNCTION public.dedupe_catalog_months(p_tenant_id uuid)
RETURNS integer
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH max_month AS (
    SELECT item_code, distributor, MAX(catalog_month) AS max_catalog_month
    FROM public.catalog
    WHERE tenant_id = p_tenant_id
    GROUP BY item_code, distributor
    HAVING COUNT(*) > 1
  ),
  deleted AS (
    DELETE FROM public.catalog c
    USING max_month m
    WHERE c.tenant_id = p_tenant_id
      AND c.item_code = m.item_code
      AND c.distributor = m.distributor
      AND c.catalog_month < m.max_catalog_month
      AND c.id NOT IN (
        SELECT catalog_id FROM public.preorders WHERE tenant_id = p_tenant_id
      )
    RETURNING 1
  )
  SELECT count(*)::integer FROM deleted;
$$;

REVOKE ALL ON FUNCTION public.dedupe_catalog_months(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.dedupe_catalog_months(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.dedupe_catalog_months(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.dedupe_catalog_months(uuid) TO service_role;

-- STOP HERE. Confirm this block ran with no error before continuing — the
-- rest of this file reads as a script but is meant to be run as separate,
-- watched steps, not pasted and executed all at once.


-- ── VERIFY grants ────────────────────────────────────────────────────────
SELECT grantee, privilege_type
FROM information_schema.routine_privileges
WHERE routine_name = 'dedupe_catalog_months';
-- EXPECTED: service_role = EXECUTE, and nothing else. If `anon` or
-- `authenticated` appears, the REVOKEs above did not take — stop and re-run
-- them before Step 3.


-- ── STEP 2 — dry-run preview (read-only, safe to run any number of times) ──
-- Same predicate as the DELETE inside the function body above — if you ever
-- edit the function, update this preview to match or it stops meaning
-- anything. Shows what Step 3 will delete, without deleting it.
WITH max_month AS (
  SELECT item_code, distributor, MAX(catalog_month) AS max_catalog_month
  FROM public.catalog
  WHERE tenant_id = '72e29f67-39f7-42bc-a4d5-d6f992f9d790'  -- staging raysandjudys
  GROUP BY item_code, distributor
  HAVING COUNT(*) > 1
)
SELECT count(*) AS would_delete
FROM public.catalog c
JOIN max_month m
  ON c.item_code = m.item_code AND c.distributor = m.distributor
WHERE c.tenant_id = '72e29f67-39f7-42bc-a4d5-d6f992f9d790'
  AND c.catalog_month < m.max_catalog_month
  AND c.id NOT IN (
    SELECT catalog_id FROM public.preorders
    WHERE tenant_id = '72e29f67-39f7-42bc-a4d5-d6f992f9d790'
  );
-- EXPECTED (measured 2026-08-22 via f136-audit.js, re-check before trusting
-- this number — it drifts with every import): would_delete = 997.
-- If this does not match a FRESH f136-audit.js "safe" count run the same
-- day, STOP and re-derive rather than proceeding on a stale expectation.


-- Confirm the one known-blocked row is correctly EXCLUDED from the preview
-- (it must NOT appear — it is referenced by a live preorder):
WITH max_month AS (
  SELECT item_code, distributor, MAX(catalog_month) AS max_catalog_month
  FROM public.catalog
  WHERE tenant_id = '72e29f67-39f7-42bc-a4d5-d6f992f9d790'
  GROUP BY item_code, distributor
  HAVING COUNT(*) > 1
)
SELECT c.id, c.catalog_month, c.title
FROM public.catalog c
JOIN max_month m
  ON c.item_code = m.item_code AND c.distributor = m.distributor
WHERE c.tenant_id = '72e29f67-39f7-42bc-a4d5-d6f992f9d790'
  AND c.catalog_month < m.max_catalog_month
  AND c.id = '93ef9327-cfa0-44c1-ae7b-2d0bb387b622';  -- Nightmare Before Christmas #2, 2026-04 row
-- EXPECTED: ZERO ROWS. If this returns a row, the blocked row would be
-- deleted by Step 3 — STOP, do not proceed, something has changed (e.g. the
-- reservation was cancelled since 2026-08-22, which would make deletion
-- correct but means V5's "1 blocked" expectation is stale and needs
-- re-deriving before continuing).


-- ── STEP 3 — THE ACTUAL DEDUPE (DESTRUCTIVE — deletes rows) ────────────────
-- Only run this after Step 2's preview count matches a freshly-measured
-- f136-audit.js "safe" number and the blocked-row check above returned zero
-- rows. This is the write step V5/V6 verify against.
SELECT public.dedupe_catalog_months('72e29f67-39f7-42bc-a4d5-d6f992f9d790') AS deleted_count;
-- EXPECTED: 997 (or whatever Step 2's fresh preview just showed — they MUST
-- match exactly; the function and the preview run the identical predicate).
-- FAIL = any other number. Report and halt — do not re-run to "fix" it.


-- ── POST-VERIFY (V5) — the blocked row survived ─────────────────────────────
SELECT id, catalog_month, title
FROM public.catalog
WHERE id IN (
  '93ef9327-cfa0-44c1-ae7b-2d0bb387b622',  -- blocked: 2026-04, referenced
  'a8870e97-2704-46b5-9ae5-887a57866556'   -- maintained: 2026-06
);
-- EXPECTED: BOTH rows still present, 2 rows total. FAIL = either row missing
-- (the blocked row means a live reservation just lost its FK target; the
-- maintained row should never be a delete candidate at all, so its absence
-- means the predicate logic itself is wrong).


-- ── POST-VERIFY (V6) — reservations are intact ──────────────────────────────
SELECT
  count(*) FILTER (WHERE true)            AS total_preorders,
  count(*) FILTER (WHERE fulfilled = false) AS unfulfilled,
  count(*) FILTER (WHERE fulfilled = true)  AS fulfilled
FROM public.preorders
WHERE tenant_id = '72e29f67-39f7-42bc-a4d5-d6f992f9d790';
-- EXPECTED — identical to the pre-Step-3 baseline (measured 2026-08-22,
-- RE-CONFIRM this baseline was captured immediately before Step 3 ran, not
-- from this comment, before treating a match as evidence):
--   total_preorders = 56, unfulfilled = 22, fulfilled = 34.
-- FAIL = any of the three numbers differs. A DELETE that touched a
-- referenced catalog row would either fail outright (NO ACTION FK) or, if
-- the predicate above is wrong, silently succeed while leaving a preorder
-- row pointing at nothing — these counts would not move in that second case
-- either, which is WHY V5's per-row check above is the one that actually
-- catches it. V6 catches a different failure: a bug that deleted or
-- otherwise mutated a preorders row directly, which nothing in this
-- function's body does, but which this counts-must-match check exists to
-- rule out rather than assume.


-- After Step 3 and both post-verifies read green, run `node f136-audit.js`
-- fresh from the scripts folder and confirm:
--   - "Total duplicate pairs: 0"
--   - "1 reservation(s) sit on a duplicate-group row" is now the ONLY
--     survivor (the Nightmare Before Christmas one) and "0 of those are
--     STRANDED" is WRONG to expect — see the S2 handoff note: dedupe alone
--     does not un-strand a REFERENCED row, so this reservation should still
--     show as STRANDED afterward. Confirm that reasoning against the actual
--     output rather than assuming it; if it reads differently, STOP and
--     report rather than reconciling it silently.
--   - "0 row(s) safe to delete" and "1 row(s) BLOCKED" (blocked count
--     unchanged — repointing is Part D/S3, not this session).


-- ── ROLLBACK ────────────────────────────────────────────────────────────────
-- The DELETE in Step 3 is not reversible from inside this file (no backup
-- table taken here — the rows are unreferenced by definition, so nothing
-- else in the app depended on them; the maintained row for every affected
-- item_code/distributor pair is untouched). If Step 1's CREATE needs
-- reverting before Step 3 is ever run:
--   DROP FUNCTION IF EXISTS public.dedupe_catalog_months(uuid);
-- Once Step 3 has run, there is nothing to roll back — the function itself
-- can still be dropped, but the deleted duplicate rows are gone by design.
