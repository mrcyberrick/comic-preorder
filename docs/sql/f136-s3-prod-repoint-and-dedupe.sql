-- STATUS: staging=N/A (prod-only file) | prod=APPLIED 2026-08-22
--         F136 S3, Part D. All six steps run by Rick on production
--         2026-08-22. V7/V8 GREEN, confirmed three independent ways: prod
--         catalog rows 12,087 -> 9,418 (delta exactly 2,669, matching the
--         Step 5 preview precisely); preorder counts unchanged, 2,021/1,049/
--         972 total/unfulfilled/fulfilled before and after; a fresh
--         f136-audit.js --prod re-run shows duplicate pairs 2,666 -> 27,
--         safe/blocked 2,667/29 -> 0/27 -- the 27 survivors are exactly the
--         historical fulfilled rows this session deliberately left blocked
--         (see plan § 11 S3). NOTE on this file's own Step 6 post-verify
--         comment below: it predicted 27 for a query that actually counts
--         PREORDER rows, not catalog rows -- the live result was 33, which
--         is correct (27 catalog rows referenced by 33 preorders, since a
--         few of the 27 titles carry more than one reservation). Comment
--         corrected in place rather than left wrong. (F105) A gate that
--         lives only in prose gets missed — F6 sat unapplied on production
--         for 13 days because nothing machine-readable said so.
-- ============================================================================
-- F136 S3 — production repoint + production dedupe
-- Prepared 2026-08-22. Plan: docs/f136-catalog-month-integrity.md § 4 Part D,
-- § 6 (V7-V8), § 5 (S3 = "Part C(2) + Part D — runbook edit, the 2 prod
-- repoints, prod dedupe").
-- Run: PRODUCTION. Operator: Rick (Supabase SQL Editor). This is the first
-- write this finding's fix makes against production data.
--
-- RE-MEASURED 2026-08-22 against LIVE production (not trusted from the plan
-- doc's 2026-08-21 snapshot) via `node f136-audit.js --prod`: 2,666 duplicate
-- pairs, 2,667 safe / 29 blocked under the § 3(b) rule. The 29 blocked split
-- by fulfilled state (queried directly, see chat record): only **2** are
-- unfulfilled — the exact same two the plan doc's § 3(d) named on 2026-08-21
-- (Alex Alvarez / TMNT #40 Variant C, Brian Moss / Action Comics #1
-- Facsimile) — confirming nothing has changed in the live-risk population.
-- The other 27 are fulfilled/historical (24 of them Book Stop's own past
-- shelf-copy reservations) and carry no future-correction risk. **Rick's
-- call 2026-08-22: repoint only the 2 unfulfilled ones, matching Part D.1 as
-- written.** The 27 historical rows stay permanently blocked (never deleted
-- by dedupe) — known, accepted, not this session's scope.
--
-- WHY THE FUNCTION IS CREATED HERE TOO: staging and production are separate
-- Supabase projects/databases. S2's docs/sql/f136-dedupe-catalog-months.sql
-- was explicitly staging-only (per its own header) and was never run here.
-- The import-script CODE wiring (Part B3 — refreshCatalog() calling the RPC
-- on the isNewMonth branch) is ALREADY live for production, because
-- import.js and import-staging.js share one repo/branch (confirmed by S1)
-- and S2's commit (scripts repo main @ 7a8d6a1) touched both files in one
-- push. So the ONLY production-side gap is the RPC not existing in
-- production's Postgres yet — Step 1 below closes that.
-- ============================================================================

-- ── STEP 1 — create dedupe_catalog_months() on PRODUCTION ──────────────────
-- Identical DDL to the staging function (docs/sql/f136-dedupe-catalog-months.sql
-- Step 1) — same § 3(b) rule, same grants. Copied here rather than referenced
-- because this is a separate database and needs its own CREATE.
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

-- STOP HERE. Confirm no error before continuing.


-- ── VERIFY grants ────────────────────────────────────────────────────────
SELECT grantee, privilege_type
FROM information_schema.routine_privileges
WHERE routine_name = 'dedupe_catalog_months';
-- EXPECTED: service_role = EXECUTE, and nothing else.


-- ── STEP 2 — baseline preorder counts (V8's before-number) ─────────────────
-- Capture this IMMEDIATELY before Step 4's repoint UPDATEs — paste the
-- result back before continuing. This is the number V8 checks stays
-- unchanged after the dedupe runs.
SELECT
  count(*) FILTER (WHERE true)              AS total_preorders,
  count(*) FILTER (WHERE fulfilled = false) AS unfulfilled,
  count(*) FILTER (WHERE fulfilled = true)  AS fulfilled
FROM public.preorders
WHERE tenant_id = '20941129-c35a-476d-ae21-44b8f77af89c';
-- Plan doc's 2026-08-21 snapshot said 1,049 unfulfilled — RE-CONFIRM against
-- this live number rather than trusting that figure; production has taken
-- ~300 more reservations since. Whatever this query returns IS the baseline.


-- ── STEP 3 — pre-flight: confirm the 2 repoints are still safe to run ──────
-- Checks two things per repoint: (a) the source preorder is still on the
-- expected stale row, unchanged since 2026-08-22's measurement, and (b) the
-- customer does NOT already hold a separate reservation on the target row
-- (preorders has UNIQUE(user_id, catalog_id) — if they do, the UPDATE below
-- will violate it and must not be attempted blind).
SELECT id, user_id, catalog_id, fulfilled, quantity
FROM public.preorders
WHERE id IN (
  '9f35b38c-5728-4da1-9d65-0459de5ce745',  -- Alex Alvarez / TMNT #40 Variant C
  'cc719321-c2c1-4214-bd5d-1f41314ea92f'   -- Brian Moss / Action Comics #1 Facsimile
);
-- EXPECTED: 2 rows, catalog_id = 9bf9c2c5-582c-42de-bb0b-08b610c8dbd0 and
-- 8cc7ea26-0902-476a-9ecc-525781ea6dfb respectively, fulfilled = false both.
-- If either has changed (different catalog_id, fulfilled now true, or the
-- row is gone), STOP — the situation has moved since this file was written
-- and the UPDATE below must be re-derived, not run blind.

SELECT p.id, p.user_id, p.catalog_id
FROM public.preorders p
WHERE p.tenant_id = '20941129-c35a-476d-ae21-44b8f77af89c'
  AND (
    (p.user_id = (SELECT user_id FROM public.preorders WHERE id = '9f35b38c-5728-4da1-9d65-0459de5ce745')
       AND p.catalog_id = '48abfbd3-6e59-4d1b-b5d9-60f58831b217')
    OR
    (p.user_id = (SELECT user_id FROM public.preorders WHERE id = 'cc719321-c2c1-4214-bd5d-1f41314ea92f')
       AND p.catalog_id = 'a0b707bc-d340-437d-8186-eeba16fbf132')
  );
-- EXPECTED: ZERO ROWS. If this returns a row, that customer ALREADY holds a
-- reservation on the target (maintained) catalog row — the UPDATE below
-- would violate preorders' UNIQUE(user_id, catalog_id) constraint and fail.
-- STOP and resolve manually (likely: delete the stale duplicate row's
-- preorder instead of repointing it, after confirming quantities/intent with
-- Rick) rather than forcing it.


-- ── STEP 4 — THE 2 REPOINTS (DESTRUCTIVE — updates live customer rows) ─────
-- Only run after Step 3's two checks both come back as expected (2 rows
-- matching, 0 rows for the collision check).
UPDATE public.preorders
SET catalog_id = '48abfbd3-6e59-4d1b-b5d9-60f58831b217'  -- target: 2026-06 maintained row
WHERE id = '9f35b38c-5728-4da1-9d65-0459de5ce745'          -- Alex Alvarez / TMNT #40 Variant C
  AND catalog_id = '9bf9c2c5-582c-42de-bb0b-08b610c8dbd0'; -- guard: only if still on the expected stale row

UPDATE public.preorders
SET catalog_id = 'a0b707bc-d340-437d-8186-eeba16fbf132'  -- target: 2026-06 maintained row
WHERE id = 'cc719321-c2c1-4214-bd5d-1f41314ea92f'          -- Brian Moss / Action Comics #1 Facsimile
  AND catalog_id = '8cc7ea26-0902-476a-9ecc-525781ea6dfb'; -- guard: only if still on the expected stale row
-- Each UPDATE should report "1 row affected" in the SQL Editor. FAIL = 0 rows
-- affected on either (means the WHERE guard didn't match — the pre-flight in
-- Step 3 should have caught this already, so 0 here means something changed
-- between Step 3 and Step 4; stop and re-run Step 3).


-- ── POST-VERIFY (V7) — the 2 repoints landed ────────────────────────────────
SELECT id, catalog_id,
  CASE catalog_id
    WHEN '48abfbd3-6e59-4d1b-b5d9-60f58831b217' THEN 'Alex Alvarez -> 2026-06 (correct)'
    WHEN '9bf9c2c5-582c-42de-bb0b-08b610c8dbd0' THEN 'Alex Alvarez -> STILL on 2026-05 (FAIL)'
    WHEN 'a0b707bc-d340-437d-8186-eeba16fbf132' THEN 'Brian Moss -> 2026-06 (correct)'
    WHEN '8cc7ea26-0902-476a-9ecc-525781ea6dfb' THEN 'Brian Moss -> STILL on 2026-05 (FAIL)'
    ELSE 'UNEXPECTED catalog_id -- investigate'
  END AS result
FROM public.preorders
WHERE id IN ('9f35b38c-5728-4da1-9d65-0459de5ce745', 'cc719321-c2c1-4214-bd5d-1f41314ea92f');
-- EXPECTED: both rows read "(correct)". FAIL = either "(FAIL)" or "UNEXPECTED".


-- ── STEP 5 — dry-run preview of the dedupe (safe, read-only) ───────────────
-- Same predicate as the DELETE inside dedupe_catalog_months()'s body — keep
-- this in sync with Step 1 if the function ever changes.
WITH max_month AS (
  SELECT item_code, distributor, MAX(catalog_month) AS max_catalog_month
  FROM public.catalog
  WHERE tenant_id = '20941129-c35a-476d-ae21-44b8f77af89c'
  GROUP BY item_code, distributor
  HAVING COUNT(*) > 1
)
SELECT count(*) AS would_delete
FROM public.catalog c
JOIN max_month m
  ON c.item_code = m.item_code AND c.distributor = m.distributor
WHERE c.tenant_id = '20941129-c35a-476d-ae21-44b8f77af89c'
  AND c.catalog_month < m.max_catalog_month
  AND c.id NOT IN (
    SELECT catalog_id FROM public.preorders
    WHERE tenant_id = '20941129-c35a-476d-ae21-44b8f77af89c'
  );
-- EXPECTED: 2669 — the 2,667 measured 2026-08-22 PLUS the 2 rows Step 4 just
-- freed up (each repointed row's old catalog_id now has zero references).
-- If this reads 2667 (not 2669), the repoints in Step 4 did not actually
-- free their old rows — STOP, do not proceed to Step 6, re-check Step 4's
-- result. If it reads anything else entirely, re-derive rather than assume.


-- ── STEP 6 — THE ACTUAL DEDUPE (DESTRUCTIVE — deletes rows) ────────────────
-- Only run after Step 5's preview matches expectation exactly.
SELECT public.dedupe_catalog_months('20941129-c35a-476d-ae21-44b8f77af89c') AS deleted_count;
-- EXPECTED: 2669 (or whatever Step 5 just showed — they MUST match exactly).
-- FAIL = any other number. Report and halt — do not re-run to "fix" it.


-- ── POST-VERIFY (V8, part 1) — preorder counts unchanged ───────────────────
SELECT
  count(*) FILTER (WHERE true)              AS total_preorders,
  count(*) FILTER (WHERE fulfilled = false) AS unfulfilled,
  count(*) FILTER (WHERE fulfilled = true)  AS fulfilled
FROM public.preorders
WHERE tenant_id = '20941129-c35a-476d-ae21-44b8f77af89c';
-- EXPECTED: identical total/unfulfilled/fulfilled to Step 2's baseline.
-- FAIL = any of the three numbers differs.


-- ── POST-VERIFY (V8, part 2) — the 27 historical-blocked rows survived ─────
-- Sanity check: dedupe must NOT have touched the 27 fulfilled/historical
-- rows this session deliberately left alone (Rick's call — see header).
SELECT count(*) AS still_blocked_as_expected
FROM public.preorders p
JOIN public.catalog c ON c.id = p.catalog_id
WHERE p.tenant_id = '20941129-c35a-476d-ae21-44b8f77af89c'
  AND c.tenant_id = '20941129-c35a-476d-ae21-44b8f77af89c'
  AND c.catalog_month < (
    SELECT MAX(c2.catalog_month) FROM public.catalog c2
    WHERE c2.tenant_id = '20941129-c35a-476d-ae21-44b8f77af89c'
      AND c2.item_code = c.item_code AND c2.distributor = c.distributor
  );
-- EXPECTED: 33, NOT 27 — this query counts PREORDER rows referencing a
-- below-maintained catalog row, not distinct catalog rows. 27 is the
-- catalog-row count (matches f136-audit.js's "blocked" metric and Step 5's
-- preview); several of those 27 titles carry more than one reservation
-- (Book Stop plus an individual customer, in a few cases), so the preorder
-- count is higher. 35 originally-stranded preorders minus the 2 repointed =
-- 33. CORRECTED 2026-08-22 after Rick's live run returned 33 and it was
-- reconciled against the original stranded-detail query rather than assumed
-- wrong — the first version of this comment said "EXPECTED: 27" and
-- conflated the two metrics. FAIL = 0 (the 27 catalog rows got deleted
-- despite being referenced) or any number that does NOT reconcile to 27
-- distinct catalog rows via a GROUP BY on (item_code, distributor).


-- After Step 6 and both post-verifies read green, run
-- `node f136-audit.js --prod` fresh and confirm:
--   - "Total duplicate pairs: 27" (NOT 0 — the 27 historical fulfilled rows
--     each still form a 2-row duplicate group with their own maintained
--     sibling; only their DELETABLE side is gone, and there's no deletable
--     side left because the referenced row itself is what's "extra")
--   - Actually check this reasoning against the live output rather than
--     assuming it: it is possible some of the 27 fulfilled rows' groups
--     collapse to a single surviving row if the ONLY other member of that
--     group was itself deleted as unreferenced (i.e. a 3+ month group where
--     only the referenced row and the maintained row survive). Read the
--     actual "Total duplicate pairs" and "blocked" numbers and reconcile
--     them against 27 rather than expecting an exact match blind.
--   - "0 row(s) safe to delete" (everything deletable is now gone)
--   - "27 row(s) BLOCKED" — down from 29, matching the 2 repoints


-- ── ROLLBACK ────────────────────────────────────────────────────────────────
-- Step 4 (the 2 repoints): reversible while you still have this file's
-- "before" catalog_ids recorded above (9bf9c2c5... and 8cc7ea26...) — but
-- only until Step 6 runs, since Step 6 deletes those now-unreferenced rows.
-- After Step 6, the old rows are gone by design; there is nothing to roll
-- back to.
-- Step 1 (function creation), if needed before Step 6 ever runs:
--   DROP FUNCTION IF EXISTS public.dedupe_catalog_months(uuid);
