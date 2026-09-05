-- STATUS: staging=APPLIED 2026-09-05 (Rick) | prod=PENDING (F156, written 2026-09-05)
-- (F105) This line is the applied-state record. A gate that lives only in
-- prose gets missed -- F6 sat unapplied on production for 13 days because
-- nothing machine-readable said so. Update it the moment you run this file.
--
-- F156 -- backfill `catalog.order_requirement` for Lunar rows imported before
-- F132's derivation existed.
--
-- WHY THIS EXISTS. Lunar has no OrderRequirement column of its own; it stores
-- the allocation ratio directly in VariantType. F132 added
-- parseLunarVariantRestriction() to import.js on 2026-08-20 to derive
-- `order_requirement` from it. Rows imported BEFORE that date keep the ratio
-- in `variant_type` and carry `order_requirement = NULL` permanently, because
-- an older catalog month is never re-pulled (the same never-re-pull
-- assumption F155 is about, hitting a different column).
--
-- The consequence is silent and customer-facing, not merely cosmetic. The
-- column drives FOUR surfaces, all of which simply render nothing:
--   * app.js:1906        -- the customer's catalog-card "Restricted" badge
--   * catalog.html:1261  -- the customer's detail-modal restriction notice
--   * admin.html:1126    -- the Order Builder's per-cycle restricted count
--   * arrivals.html:1278 -- the This Week reconciliation exceptions pill
--     and arrivals.html:1339, the store-shipment grid card badge
-- Found 2026-09-05 by Rick, from a production screenshot of the last of
-- these: five SPAWN 77 incentive variants (1:25 through 1:500) sitting in
-- "Not in shipment" with no badge, beside PRH rows that had one.
--
-- WHY THIS IS A REPLAY, NOT A GUESS. The predicate below is exactly
-- parseLunarVariantRestriction()'s own rule: a strict `^[0-9]+:[0-9]+$`
-- match, which is why 'Open Order' / 'OPEN ORDER' / 'Standard' / 'BLANK' /
-- 'Unlock' / NULL are all left alone -- F132 deliberately does not flag
-- 'BLANK' or 'Unlock' (real values, different concepts from a per-shop
-- ratio). Measured 2026-09-05: **0** Lunar rows anywhere carry
-- `order_requirement` WITHOUT a matching ratio in `variant_type`, so this
-- direction is the only one that has ever diverged.
--
-- NOT TENANT-SCOPED, deliberately. The derivation is a property of Lunar's
-- own data format, not of any tenant, so every tenant's Lunar rows should
-- follow the identical rule. The pre-check below breaks the affected rows
-- down by tenant anyway, so the scope is visible before anything is written.
--
-- Idempotent: re-running touches nothing, since `order_requirement IS NULL`
-- no longer holds for the rows it just set.
--
-- Every consumer of this column is read-only display. The only behavioural
-- change is that badges start appearing. No schema change, no RLS change, no
-- code deploy required.

-- ── PRE-CHECK ─────────────────────────────────────────────────────────────
-- Run this FIRST, on its own, and match the count against the environment
-- you are actually connected to. This check CAN fail: a number that is not
-- 67 (production) or 66 (staging) means the data moved since 2026-09-05 and
-- you should stop and re-measure rather than write.
SELECT t.slug,
       c.catalog_month,
       COUNT(*) AS rows_to_backfill
  FROM public.catalog c
  JOIN public.tenants t ON t.id = c.tenant_id
 WHERE c.distributor       = 'Lunar'
   AND c.variant_type      ~ '^[0-9]+:[0-9]+$'
   AND c.order_requirement IS NULL
 GROUP BY t.slug, c.catalog_month
 ORDER BY t.slug, c.catalog_month;

-- ⚠ CORRECTED 2026-09-05, from Rick's real production pre-check. The block
-- that stood here read "2026-06 = 5, 2026-07 = 58 -- total 67". Those two sum
-- to 63, not 67: the TOTAL was right (it came from an all-months query) but the
-- per-month breakdown beside it was incomplete, because the survey that
-- produced it swept 2026-05..2026-09 by hand instead of deriving the months
-- from the data. Two numbers written side by side that contradict each other,
-- and neither was reconciled against the other. Re-derived below with no month
-- filter at all.
--
-- PRODUCTION (rjbookstop), measured 2026-09-05 — matches Rick's pre-check exactly:
--   2026-03 =  1   (of   1 ratio rows)
--   2026-04 =  3   (of   3)
--   2026-05 =  0   (of  10)
--   2026-06 =  5   (of  36)
--   2026-07 = 58   (of 175)
--   2026-08 =  0   (of 166)
--   2026-09 =  0   (of 164)
--   TOTAL   = 67   (of 555)  ->  after the run, lunar_with_requirement = 555
--
-- STAGING (raysandjudys): total 66. APPLIED 2026-09-05; per-month split never
-- measured there and is not restated here rather than guessed.
--
-- The stale window is therefore OLDER than "2026-06/07": it reaches back to
-- 2026-03. 2026-05 sitting clean between stale neighbours is unexplained and
-- most likely a post-fix older-month re-import; it does not affect the fix,
-- which keys on the column being NULL rather than on any month.
--
-- Of production's 67, exactly 6 carry live unfulfilled reservations — all in
-- 2026-06/07, unchanged by this correction (the four 2026-03/04 rows carry
-- ZERO reservations; they are long-lead hardcovers and bundles):
--   0626DE0825 (1:10)  VAMPIRELLA VS RED SONJA RED CITY #1 CVR G
--   0726IM0315 (1:25)  SPAWN 77 #1 (OF 3) CVR F
--   0726IM0316 (1:50)  SPAWN 77 #1 (OF 3) CVR G
--   0726IM0317 (1:100) SPAWN 77 #1 (OF 3) CVR H
--   0726IM0318 (1:250) SPAWN 77 #1 (OF 3) CVR I
--   0726IM0319 (1:500) SPAWN 77 #1 (OF 3) CVR J

-- ── REVERT LIST ───────────────────────────────────────────────────────────
-- Capture this BEFORE the write if you want exact revertibility (the same
-- discipline clear-f147-withdrawn.js and f115-s6-backfill-unknown.js follow).
-- Every affected row goes back to NULL, and nothing else is touched.
--   SELECT id FROM public.catalog
--    WHERE distributor = 'Lunar'
--      AND variant_type ~ '^[0-9]+:[0-9]+$'
--      AND order_requirement IS NULL;
-- Revert:
--   UPDATE public.catalog SET order_requirement = NULL WHERE id IN (<ids>);

-- ── THE WRITE ─────────────────────────────────────────────────────────────
-- RETURNING is deliberate: the row list is the receipt. Do not trust a bare
-- "UPDATE 67" line as the verification -- run the post-check below, which
-- reads the state back independently.
UPDATE public.catalog
   SET order_requirement = variant_type
 WHERE distributor       = 'Lunar'
   AND variant_type      ~ '^[0-9]+:[0-9]+$'
   AND order_requirement IS NULL
RETURNING item_code, catalog_month, variant_type, order_requirement;

-- ── POST-CHECK ────────────────────────────────────────────────────────────
-- Two numbers, read fresh. This CAN fail, which is the point (§ "A
-- verification step that cannot fail is not a verification step"):
--   still_null   MUST be 0      -- nothing was missed
--   inconsistent MUST be 0      -- nothing was set to a non-ratio value
-- If either is non-zero, the write did not do what this file claims.
SELECT
  COUNT(*) FILTER (
    WHERE variant_type ~ '^[0-9]+:[0-9]+$' AND order_requirement IS NULL
  ) AS still_null,
  COUNT(*) FILTER (
    WHERE order_requirement IS NOT NULL AND order_requirement !~ '^[0-9]+:[0-9]+$'
  ) AS inconsistent,
  COUNT(*) FILTER (
    WHERE order_requirement IS NOT NULL
  ) AS lunar_with_requirement
  FROM public.catalog
 WHERE distributor = 'Lunar';

-- ⚠ CORRECTED 2026-09-05, after the staging run. The two lines that stood here
-- quoted the FOUNDING-TENANT counts (555 / 554) against a query that carries NO
-- tenant filter, so the real staging result came back 718 and looked like a
-- failure when the run was in fact perfect. An expected value that disagrees
-- with its own query is the same class of defect as a check that cannot fail:
-- it manufactures a false alarm instead of hiding a real one. Both are stated
-- explicitly now.
--
-- still_null and inconsistent MUST be 0 on both environments — those are the
-- assertions. lunar_with_requirement is a scale reading, not a pass/fail, and
-- it is DB-WIDE because this query is:
--
--   STAGING, measured after the run (2026-09-05):
--     still_null = 0, inconsistent = 0, lunar_with_requirement = 718
--       = raysandjudys 554  (488 before the run, +66 — exactly as predicted)
--       + demoshop     164  (the F72 demo tenant, whose catalog was copied
--                            from the founding tenant — it carries Lunar rows
--                            of its own and the unscoped UPDATE fixed those
--                            too, which is intended: the derivation is a
--                            property of Lunar's data format, not of a tenant)
--
--   PRODUCTION, measured before the run (2026-09-05, still pending):
--     still_null = 67, inconsistent = 0, lunar_with_requirement = 488
--     Expect afterwards: still_null = 0, inconsistent = 0,
--                        lunar_with_requirement = 555.
--     Production's second tenant (comicstore) holds no Lunar rows with a
--     ratio, so DB-wide and founding-tenant figures coincide there. That is
--     precisely why the mismatch only showed up on staging.
--
-- Verified end-to-end on staging after the run, not inferred: a live browser
-- check (playwright/f156-reject-surfaces-verify.mjs, V24) seeded a reservation
-- on 0726DC0016 (LEGION OF SUPER-HEROES #1 CVR I INC 1:25, catalog_month
-- 2026-07 — one of the stale months) and read "⚠ 1:25" back out of
-- arrivals.html's "Not in shipment" list: the exact surface, and the exact
-- missing badge, that was reported.
