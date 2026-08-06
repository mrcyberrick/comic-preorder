-- ============================================================================
-- order_submissions — signed quantity (F117) + zero-quantity rejection (F108
-- § 4.4) + get_ordered_codes() rework
-- Prepared 2026-08-06 (order-loop-closure-f108.md, Session B).
-- Plan: docs/order-loop-closure-f108.md § 4.4, § 6 Session B step 2.
-- Run: STAGING first. Verify (gates V-B2, V-B5 below). THEN production.
-- Operator: Rick (Supabase SQL Editor, runs as postgres superuser).
--
-- WHY THIS MIGRATION EXISTS (two problems, one fix):
--   1. F108 § 3.6 — "zero-quantity Mark Ordered records a rejection." The
--      supplier sometimes rejects a submitted title outright. Recording that
--      as quantity 0 is how the loop closes on it (Rick: "the import process
--      simply accepts it"). CHECK quantity >= 1 rejects a zero row outright.
--   2. F117 — a corrected (reduced) supplier order has no way to be recorded.
--      Rick corrected the real PRH order for 75960621668000111 from 12 down
--      to 8 on 2026-08-05, and chose (of three options) to append a
--      correcting row once the schema allows it, NOT to edit the original
--      7/26 row — that row's quantity (7) is the evidence that established
--      F102's over-order in the first place. A downward correction needs a
--      NEGATIVE quantity, which needs the same CHECK relaxed further than
--      zero alone.
--
-- CONSEQUENCE — THE LEDGER IS NOW SIGNED, EVERY READER MUST SUM, NOT COUNT:
--   Before this migration, "a row exists for this code" and "this code is on
--   order" were the same fact. After it, they are not — a code can have rows
--   and still be net <= 0 (rejected, or corrected away). Every consumer that
--   used to test `matches.length > 0` now tests `SUM(quantity) > 0`. This
--   file only touches the database side (the CHECK and the RPC); the client
--   consumers (admin.html, mylist.html, app.js) are a separate, non-DDL
--   change landing in the same commit as this file.
--
-- WHAT THIS FILE DOES NOT DO:
--   Does not touch the existing 857 rows on either environment — this is a
--   widening (fewer things rejected), so every existing row stays valid.
--   Does not insert the real -4 adjustment for 75960621668000111 — that is a
--   separate, explicit step AFTER this migration is verified (§ 6 step 4;
--   the outstanding 2026-08-05 correction). Do not fold it into this file.
-- ============================================================================

-- Pre-check: confirm current constraint shapes before changing them.
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'public.order_submissions'::regclass
  AND contype = 'c';
-- Expected (pre-migration):
--   order_submissions_distributor_check: CHECK (distributor = ANY (ARRAY['Lunar','PRH']))
--   order_submissions_order_type_check:  CHECK (order_type = ANY (ARRAY['monthly','adhoc']))
--   order_submissions_quantity_check:    CHECK (quantity >= 1)

BEGIN;

-- 1. Quantity: drop the lower bound entirely. Zero (rejection, F108 § 3.6)
--    and negative (downward adjustment, F117) are both legitimate now.
--    No replacement bound — an order_submissions row is a signed delta, not
--    a physical count, so there is no natural floor or ceiling to enforce.
ALTER TABLE public.order_submissions
  DROP CONSTRAINT order_submissions_quantity_check;

-- 2. order_type: add 'adjustment' alongside the existing 'monthly'/'adhoc'.
--    A correcting row (F117) is neither a monthly cycle submission nor a
--    fresh ad-hoc order — it is a standalone correction against history.
ALTER TABLE public.order_submissions
  DROP CONSTRAINT order_submissions_order_type_check;
ALTER TABLE public.order_submissions
  ADD CONSTRAINT order_submissions_order_type_check
  CHECK (order_type = ANY (ARRAY['monthly', 'adhoc', 'adjustment']));

-- 3. get_ordered_codes() rework — RETURNS TABLE shape is changing (adding
--    order_state), so CREATE OR REPLACE cannot be used (Postgres rejects a
--    return-type change on REPLACE); DROP + CREATE, then re-apply grants,
--    since a fresh CREATE resets privileges to the type default (no EXECUTE
--    for anyone until granted).
--
--    Aggregates per (distributor, order_code) rather than returning distinct
--    rows: a code with net quantity > 0 is 'ordered'; a code with ledger rows
--    but net <= 0 is 'unavailable' (rejected, or corrected down to nothing) —
--    this is the F108 § 4.4 point 2 requirement ("must stop lying"), and it
--    is the single change that makes V-B2 pass: a zero-only code must not
--    read "Order placed" on My List. Still exposes no quantities, dates, or
--    titles — same admin-only-quantities design as the original (§ "WHY THIS
--    EXISTS" in get-ordered-codes-rpc.sql).
DROP FUNCTION IF EXISTS public.get_ordered_codes();

CREATE FUNCTION public.get_ordered_codes()
RETURNS TABLE(distributor text, order_code text, order_state text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT distributor, order_code,
         CASE WHEN SUM(quantity) > 0 THEN 'ordered' ELSE 'unavailable' END AS order_state
  FROM order_submissions
  WHERE tenant_id = current_tenant_id()
  GROUP BY distributor, order_code;
$$;

GRANT EXECUTE ON FUNCTION public.get_ordered_codes() TO authenticated;
REVOKE ALL ON FUNCTION public.get_ordered_codes() FROM PUBLIC, anon;

COMMIT;

-- ----------------------------------------------------------------------------
-- Post-DDL verification (run these before telling the agent to proceed —
-- BEGIN + SET LOCAL + ROLLBACK has failed in this editor before with 25P02,
-- per feedback_supabase_sql_editor_set_local; these are plain SELECTs).
-- ----------------------------------------------------------------------------

-- 1. Constraint shapes now permit zero/negative quantity and 'adjustment'.
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'public.order_submissions'::regclass
  AND contype = 'c';
-- Expected: no order_submissions_quantity_check row at all; order_type_check
-- now reads CHECK (order_type = ANY (ARRAY['monthly','adhoc','adjustment']))

-- 2. Existing 857 rows untouched (count unchanged from your pre-migration note).
SELECT count(*) FROM public.order_submissions;

-- 3. A zero-quantity row now inserts cleanly (throwaway probe — delete it
--    immediately after confirming, it is not real data).
--    Replace <TENANT_ID> with the environment's founding tenant UUID.
-- INSERT INTO public.order_submissions
--   (tenant_id, distributor, order_code, quantity, order_type, submitted_on)
-- VALUES ('<TENANT_ID>', 'PRH', 'ZZ_PROBE_ZERO', 0, 'adhoc', CURRENT_DATE)
-- RETURNING id;
-- DELETE FROM public.order_submissions WHERE order_code = 'ZZ_PROBE_ZERO';

-- 4. A negative-quantity row now inserts cleanly (same probe-and-delete shape).
-- INSERT INTO public.order_submissions
--   (tenant_id, distributor, order_code, quantity, order_type, submitted_on)
-- VALUES ('<TENANT_ID>', 'PRH', 'ZZ_PROBE_NEG', -4, 'adjustment', CURRENT_DATE)
-- RETURNING id;
-- DELETE FROM public.order_submissions WHERE order_code = 'ZZ_PROBE_NEG';

-- 5. get_ordered_codes() grants are correct (unchanged from before the rework).
SELECT grantee, privilege_type
FROM information_schema.routine_privileges
WHERE routine_name = 'get_ordered_codes';
-- Expected: authenticated=EXECUTE only (no anon, no PUBLIC)

-- 6. Shape check: the function now returns three columns, not two. Run as
--    postgres this returns 0 (current_tenant_id() is NULL outside a real
--    authenticated session — see the original file's own note); this call is
--    only confirming the column list, not exercising real tenant scoping.
SELECT * FROM public.get_ordered_codes() LIMIT 0;
