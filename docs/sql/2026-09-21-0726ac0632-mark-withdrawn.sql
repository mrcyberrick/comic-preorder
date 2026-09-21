-- STATUS: staging=N/A (production data fix) | prod=APPLIED 2026-09-21
--         Run by Rick 2026-09-21. INDEPENDENTLY VERIFIED by a fresh
--         service-role read afterwards, not taken from the write's own output:
--         withdrawn_at = 2026-09-21T17:08:30.709731+00:00,
--         withdrawn_last_seen_month = '2026-07'. Confirmed in the UI too — the
--         title now renders in admin.html's "Withdrawn by Distributor" panel.
--
-- 0726AC0632 — LIFE WITH ARCHIE #1 FACSIMILE CVR A HARRY LUCEY TERRY SZENICS
-- Lunar lists this title as CANCELLED. Our catalog row does not know that.
--
-- WHY IT IS NOT ALREADY WITHDRAWN. F110's withdrawal detection only fires at a
-- NEW-MONTH import, by set-difference against the distributor's current file.
-- This row is catalog_month 2026-07, and an older month is never re-pulled — so
-- the cancellation is real on Lunar's site and permanently invisible to us.
-- That is F155's never-re-pull assumption hitting a THIRD column, after
-- on_sale_date (F155) and order_requirement (F156).
--
-- WHY withdrawn_at AND NOT arrival_outcome. Measured 2026-09-21:
--   * 'not_arrived' copy reads "⚠ Did not arrive — contact the store", which
--     implies "this time" — a short-ship or a delay. A cancelled title is never
--     coming. withdrawn_at reads "⚠ No longer available — withdrawn by the
--     distributor. This title cannot arrive." (mylist.html), which is the fact.
--   * withdrawn_at is on the CATALOG row, so it is true for every customer who
--     reserved it, now and later. arrival_outcome is per-reservation, so a
--     later reservation would silently get no notice at all.
--   * F109's trg_preorders_block_ordered_delete permits a customer DELETE on a
--     withdrawn row (its step 3). This code's ledger nets +1, so without
--     withdrawn_at the customer CANNOT remove it — verified live against
--     staging 2026-09-21: the server returns 400 / check_violation. Setting
--     this column is what gives the customer a way to clear it.
--
-- arrival_outcome='not_arrived' on the reservation is deliberately LEFT AS IS.
-- It is not false (the title did not arrive), and it is belt-and-braces: if
-- withdrawn_at is ever cleared (see the F146 caveat below), that value is the
-- only thing still keeping the row off Order Follow-Up.
--
-- ⚠ F146 CAVEAT, stated so it is not a surprise. monthly-catalog-refresh.md
-- item 6 records that F146's withdrawal-CLEARING half reverts a hand-set
-- withdrawn_at if the title reappears in a later catalog file. Low risk here
-- (the title is cancelled, and 2026-07 is never re-pulled), but it is a real
-- documented trap and this write is a hand-correction of exactly that kind.

-- ── PRE-CHECK ── expect exactly 1 row, withdrawn_at NULL ──────────────
SELECT id, item_code, title, catalog_month, on_sale_date, withdrawn_at
  FROM public.catalog
 WHERE tenant_id  = '20941129-c35a-476d-ae21-44b8f77af89c'
   AND item_code  = '0726AC0632';

-- ── WRITE ──
UPDATE public.catalog
   SET withdrawn_at              = now(),
       withdrawn_last_seen_month = '2026-07'
 WHERE tenant_id  = '20941129-c35a-476d-ae21-44b8f77af89c'
   AND item_code  = '0726AC0632'
   AND withdrawn_at IS NULL;
-- Expect: UPDATE 1

-- ── POST-CHECK ── withdrawn_at must now be non-NULL ──────────────────
-- This is deliberately a DIFFERENT query from the pre-check's shape: it
-- returns a boolean that is FALSE before the write and TRUE after, so its
-- output cannot look identical either side of the change (the "a verification
-- step that cannot fail is not a verification step" rule).
SELECT item_code,
       withdrawn_at IS NOT NULL AS is_withdrawn,
       withdrawn_last_seen_month
  FROM public.catalog
 WHERE tenant_id = '20941129-c35a-476d-ae21-44b8f77af89c'
   AND item_code = '0726AC0632';
-- Expect: 1 row, is_withdrawn = true, withdrawn_last_seen_month = 2026-07

-- ── ROLLBACK, if ever needed ──
-- UPDATE public.catalog SET withdrawn_at = NULL, withdrawn_last_seen_month = NULL
--  WHERE tenant_id = '20941129-c35a-476d-ae21-44b8f77af89c' AND item_code = '0726AC0632';
