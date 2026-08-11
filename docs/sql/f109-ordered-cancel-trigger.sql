-- STATUS: staging=APPLIED 2026-08-10 | prod=APPLIED 2026-08-11
--         Staging: gates V7/V8/V9/V10 + full suite all green.
--         Production: run by Rick 2026-08-11. V7 reported the trigger present
--         as BEFORE / DELETE / ROW / enabled.
--         EVIDENCE NOTE, stated so nobody over-reads this line: that V7 result
--         comes from the operator's pasted output and was NOT independently
--         re-read -- pg_trigger is unreachable over PostgREST. V8, V9 and V10
--         have NOT been observed on production either: each needs a real
--         customer DELETE against seeded ledger and withdrawn rows, which is
--         not something to run against live customer data. The behavioural
--         evidence for this trigger is the staging run, where all three passed.
-- (F105) This line is the applied-state record. A gate that lives only in
-- prose gets missed -- F6 sat unapplied on production for 13 days because
-- nothing machine-readable said so. Update it the moment you run this file.
-- =====================================================================
-- F109 — move the ordered-cancel guard into the database
-- Session 2 of docs/preorders-authorization-boundary-f127-f109.md
--
-- Rick authorised the trigger 2026-08-10 (having been offered, and declined,
-- both "accept as client-side" and "defer entirely").
--
-- RUN ON **STAGING** FIRST, and only after F127's Session 1 is verified.
-- Supabase SQL Editor.
--
-- WHAT THIS FIXES, measured not inferred: the guard in `Preorders.cancel()`
-- is client-side only. `preorders` RLS permits a user to DELETE their own
-- row, so a hand-crafted PostgREST DELETE with a real customer token
-- returned **HTTP 204** against a reservation the store had already ordered.
-- Found by the guard's own end-to-end test.
--
-- WHY A TRIGGER AND NOT A POLICY: the condition needs a JOIN (catalog for the
-- distributor code, order_submissions for the net quantity). RLS policy
-- expressions cannot express that cleanly, and F109's own entry established
-- the trigger as the fix direction.
-- =====================================================================


-- ---------------------------------------------------------------------
-- STEP 1 — the trigger function.
--
-- Read the numbered comments before changing anything. Every branch is here
-- because omitting it breaks something real that has already happened.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.preorders_block_ordered_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_dist      text;
  v_code      text;
  v_withdrawn timestamptz;
  v_net       integer;
BEGIN
  -- (1) END-USER SESSIONS ONLY. This exemption is not a loophole; without it
  --     this trigger breaks four things that are all legitimate:
  --       - the Playwright fixtures, which DELETE preorders as service role
  --         and THROW on any failure (that throw is F95's own fix, and spec
  --         15 deliberately seeds already-ordered NON-withdrawn rows);
  --       - tenant teardown, since preorders.tenant_id -> tenants is ON
  --         DELETE CASCADE and a BEFORE DELETE trigger fires per cascaded row;
  --       - the SQL Editor, i.e. any hand repair;
  --       - Rick's own F122 production repair on 2026-08-10, which deleted an
  --         F85 cross-month duplicate for a code that CARRIED ledger rows.
  --     Service role bypasses RLS but NOT triggers, so this must be explicit.
  --
  --     `IS TRUE`, never `IF NOT ...` — current_user_is_admin() returns NULL,
  --     not false, for a caller with no identity. That exact shape left a gate
  --     OPEN in F126.
  IF auth.uid() IS NULL THEN RETURN OLD; END IF;
  IF current_user_is_admin() IS TRUE THEN RETURN OLD; END IF;

  -- (2) Resolve the distributor order code the SAME WAY the app does.
  --     Mirrors exportCode() at app.js:1462-1466 exactly:
  --       PRH   -> isbn      || item_code || upc
  --       other -> item_code || upc       || isbn
  --     JS `||` is falsy-coalescing, so an EMPTY STRING falls through to the
  --     next candidate. Plain SQL COALESCE would NOT — it stops at '' because
  --     '' is not NULL. Hence NULLIF(x, '') on every term. Get this wrong and
  --     the guard silently matches nothing, which is a decorative guard.
  SELECT c.distributor,
         CASE WHEN c.distributor = 'PRH'
              THEN COALESCE(NULLIF(c.isbn, ''), NULLIF(c.item_code, ''), NULLIF(c.upc, ''))
              ELSE COALESCE(NULLIF(c.item_code, ''), NULLIF(c.upc, ''), NULLIF(c.isbn, ''))
         END,
         c.withdrawn_at
    INTO v_dist, v_code, v_withdrawn
    FROM catalog c
   WHERE c.id = OLD.catalog_id;

  -- (3) WITHDRAWN OVERRIDES THIS GUARD. F110's deliberate exception: a
  --     withdrawn title can never arrive, so the customer must be able to
  --     cancel it even though the store ordered it. Checked BEFORE the ledger
  --     lookup so the exception cannot be reached around. Mirrors app.js:863.
  IF v_withdrawn IS NOT NULL THEN RETURN OLD; END IF;

  -- (4) No resolvable code, or no catalog row at all — nothing to match on,
  --     so do not block. Failing closed here would strand reservations whose
  --     catalog row was purged.
  IF v_code IS NULL THEN RETURN OLD; END IF;

  -- (5) The ledger is SIGNED since F117 — SUM, never EXISTS. A code whose rows
  --     net to <= 0 was rejected by the distributor, or corrected away by an
  --     adjustment row, and MUST stay cancellable. An EXISTS check here would
  --     lock customers out of titles the store no longer has on order. Same
  --     rule get_ordered_codes() uses for 'ordered' vs 'unavailable'.
  SELECT COALESCE(SUM(quantity), 0) INTO v_net
    FROM order_submissions
   WHERE tenant_id   = OLD.tenant_id
     AND distributor = v_dist
     AND order_code  = v_code;

  IF v_net > 0 THEN
    RAISE EXCEPTION
      'Cannot cancel: the store has already ordered this title from the distributor'
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN OLD;
END;
$function$;


-- ---------------------------------------------------------------------
-- STEP 2 — grants (F124). The function is invoked BY THE TRIGGER, not by any
-- role, so no role needs EXECUTE. Grant nothing; revoke explicitly, because
-- REVOKE ... FROM PUBLIC alone does not strip Supabase's defaults.
-- ---------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.preorders_block_ordered_delete() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.preorders_block_ordered_delete() FROM anon;
REVOKE ALL ON FUNCTION public.preorders_block_ordered_delete() FROM authenticated;


-- ---------------------------------------------------------------------
-- STEP 3 — the trigger.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_preorders_block_ordered_delete ON public.preorders;

CREATE TRIGGER trg_preorders_block_ordered_delete
  BEFORE DELETE ON public.preorders
  FOR EACH ROW EXECUTE FUNCTION public.preorders_block_ordered_delete();


-- ---------------------------------------------------------------------
-- SCOPE NOTE — `fulfilled` is deliberately NOT in this trigger.
-- F109 offers it as optional. It is left out because F115 and F122 have BOTH
-- shown `fulfilled` to be an unreliable signal — it has twice been set true
-- on titles that never arrived (28 reservations / 23 titles measured on
-- production under F115). Adding it later is additive; if wanted, it belongs
-- AFTER step (3) so the withdrawn exception still overrides it, exactly as
-- app.js:896 orders them.
-- ---------------------------------------------------------------------


-- =====================================================================
-- VERIFICATION — each states its FAILING output
-- =====================================================================

-- V7. The trigger exists and is BEFORE DELETE, FOR EACH ROW.
SELECT t.tgname,
       CASE WHEN t.tgtype & 2  = 2  THEN 'BEFORE' ELSE 'AFTER'     END AS timing,
       CASE WHEN t.tgtype & 8  = 8  THEN 'DELETE' ELSE 'other'     END AS event,
       CASE WHEN t.tgtype & 1  = 1  THEN 'ROW'    ELSE 'STATEMENT' END AS level,
       CASE WHEN t.tgenabled = 'O'  THEN 'enabled' ELSE 'DISABLED' END AS status
FROM   pg_trigger t
JOIN   pg_class c ON c.oid = t.tgrelid
WHERE  c.relname = 'preorders' AND NOT t.tgisinternal;
-- PASS: one row — BEFORE / DELETE / ROW / enabled.
-- FAIL: zero rows (trigger absent), or status DISABLED, or AFTER/STATEMENT.
--       An AFTER trigger cannot prevent the delete; a STATEMENT trigger has
--       no OLD row. Both read visibly different from PASS.

-- V8. THE BLOCK PATH — the whole point. As a REAL CUSTOMER with its own JWT
--     (not the SQL Editor, which is exempt by design at step 1), issue a
--     direct DELETE against a reservation whose code nets > 0 in the ledger.
--       BEFORE: HTTP 204, row gone.
--       AFTER:  HTTP 4xx carrying the 'Cannot cancel' message, row still present.
--     Re-SELECT the row afterwards. "The request errored" is not proof the
--     row survived; look at it.

-- V9. THE WITHDRAWN EXCEPTION — the regression most likely to slip through,
--     because it only shows up on data nobody seeds by habit. As a real
--     customer, cancel a reservation whose catalog row has withdrawn_at SET
--     and which ALSO carries ledger rows netting > 0 (the real MIDNIGHT
--     X-MEN #2 shape). MUST SUCCEED — HTTP 204. If it blocks, step (3) is
--     ordered wrong and F110's deliberate exception has been silently
--     reverted.

-- V10. THE NETTING RULE. A code whose ledger rows net to <= 0 (e.g. F117's
--      real 5 + 7 - 4 pattern, or a rejection) MUST stay cancellable.
--      If this blocks, step (5) is using EXISTS semantics somewhere.

-- V11. TEARDOWN PATHS, proved rather than assumed:
--      (a) The Playwright suite runs green end to end. Its fixtures DELETE
--          preorders as service role and throw on failure, so a regression
--          here surfaces as a red suite, not a subtle one. Run the FULL
--          suite once as the gate — this change touches a path many specs
--          depend on, so a targeted run is not sufficient here.
--      (b) Tenant-cascade teardown still works: deleting a disposable
--          synthetic tenant that holds preorders must succeed, since the
--          trigger fires once per cascaded row.
--      Both rely on the step (1) exemption. V11 is what turns that from an
--      assumption into evidence.

-- V12. Non-regression: an ordinary customer cancelling an ordinary
--      NOT-ordered reservation still works through the real UI.


-- =====================================================================
-- § R — ROLLBACK
-- =====================================================================
-- DROP TRIGGER IF EXISTS trg_preorders_block_ordered_delete ON public.preorders;
-- DROP FUNCTION IF EXISTS public.preorders_block_ordered_delete();
--
-- Drop the TRIGGER first, then the function. Dropping the trigger alone is
-- enough to restore prior behaviour immediately and is the right emergency
-- move if customers report being unable to cancel — it needs no code deploy.
