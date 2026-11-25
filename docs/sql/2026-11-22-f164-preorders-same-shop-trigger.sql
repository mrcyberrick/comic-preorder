-- STATUS: staging=APPLIED 2026-11-22 | prod=APPLIED 2026-11-22
-- (F105) This line is the applied-state record. A gate that lives only in prose gets missed: update it the
-- moment you run this file. It is kept on ONE line so /promote-prod step 0 reads both tokens. *(Between S2a and S2b
-- the production token was PENDING, deliberately: production was session S2b, and /promote-prod step 0 listed the
-- file on every promotion in that window.)* Production was applied by Rick later the same day (S2b); see the
-- production evidence note below. The write-smoke (T8) and the next production import (T9) were still outstanding
-- when this line was changed; plan § 9 records them as they are read.
-- EVIDENCE NOTE (staging, 2026-11-22). Operator-pasted (Rick, SQL Editor): P1 all 0; P2a / P2b; the BEFORE probe
-- read "F164 FAIL 1"; V1 (two triggers, the new one BEFORE INSERT OR UPDATE OF catalog_id,tenant_id,user_id, ROW,
-- enabled; F109's delete trigger unchanged); V2 (anon false, authenticated false, SECURITY DEFINER true,
-- search_path=public); V3 (= P1) all 0; and the AFTER probe, "F164 PASS: checks 1 2 3 4 passed" (check 3, the
-- other-shop-customer check, ran, so staging holds a second-shop customer). Independently observed by the agent
-- against the deployed staging database (harnesses in the scripts repo's playwright folder, local-only): the trigger
-- refuses the G-D shapes with HTTP 400 / 23514 for a customer JWT, an admin JWT and the service role, and every
-- legitimate write still lands (see plan § 9).
-- EVIDENCE NOTE (PRODUCTION, 2026-11-22, S2b). Operator-pasted (Rick, SQL Editor, production project; the agent never
-- writes to production and did not see the blocks run): S0 (tenants = comicstore, rjbookstop, so the project is
-- production); P1 all 0; P2a (catalog, preorders, user_profiles: owner postgres, RLS on, not forced) and P2b (postgres,
-- rolbypassrls true); the BEFORE probe read "F164 FAIL 1" (seen red); then the migration, V1 (two triggers: F109's
-- delete trigger unchanged; the new one BEFORE, insert and update, update_columns catalog_id,tenant_id,user_id, ROW,
-- enabled), V2 (anon false, authenticated false, SECURITY DEFINER true, search_path=public), V3 (= P1) all 0, and the
-- AFTER probe "F164 PASS: checks 1 2 3 4 passed" (check 3, the other-shop customer, ran, so production holds a
-- second-shop customer). NOT independently observed by the agent: nothing on production was read or written by the
-- agent in S2b. T8, Rick's write-smoke through the app on production (2026-11-22; a reserve then a cancel of MAGNETO: END
-- OF DAYS #1 COVER A, "green", minutes before he reported it), is HIS REPORT: the agent's read-back of the `reserve` and
-- `cancel` events from production was refused by the session's permission check and not worked around, so it is not
-- independently observed. NOT yet in this record: T9 (the next production import, Step 5 with no "Auto-reserve batch
-- failed"). The probe runs as the SQL Editor's role, so it exercises the trigger, not RLS or a real customer JWT; T8 is
-- the only check so far that went through the app's own session.
-- =====================================================================
-- F164 (session G-I, S2): a same-shop trigger on public.preorders
-- Plan: docs/f164-g-i-same-shop-guard.md § 6 (D1 = yes, answered 2026-11-11: the trigger checks the listing's shop
-- AND the customer's shop). Finding: docs/technical-reference.md § 13 F164 (Medium, OPEN until S2b).
--
-- WHAT THIS FIXES. Nothing in the database relates preorders.catalog_id (or user_id) to preorders.tenant_id. The
-- policies check only `tenant_id = current_tenant_id()` (profile-derived) and the only trigger on preorders is F109's
-- BEFORE DELETE. Measured 2026-10-06 (G-D, staging, a real customer JWT): POST preorders with the founding tenant_id
-- and a demoshop catalog_id returned 201; PATCH catalog_id on the customer's own row returned 200. The service-role
-- import wrote the two real rows (fixed at the source by S1, scripts repo e437c4f). This trigger closes the database.
--
-- ORDER OF OPERATIONS (S2a = staging; S2b = production, a separate session, on or after Sat 2026-11-21):
--   1. P1, then P2a, then P2b, each as its OWN run (the SQL Editor shows only the LAST statement's result).
--   2. The § 6.2 probe BEFORE applying. It must read   F164 FAIL 1   (that is the probe seen red).
--   3. The migration (§ 6.3).
--   4. V1, V2, V3 (= P1 again), then the probe AGAIN: it must read   F164 PASS: checks 1 2 3 4 passed .
-- Every outcome of the probe is an error, so it always rolls back and writes nothing.
--
-- ROLLBACK is at the bottom. Dropping the TRIGGER alone restores prior behaviour at once and needs no deploy.
-- =====================================================================


-- =====================================================================
-- P1. Existing rows. PASS: all four 0.   (read-only, BOTH environments, BEFORE applying)
-- FAIL: any non-zero. Halt: the trigger would not refuse those rows (it only checks new writes), but the data is
-- wrong and must be understood first.
-- =====================================================================
SELECT
  (SELECT count(*) FROM public.preorders p JOIN public.catalog c ON c.id = p.catalog_id
    WHERE c.tenant_id <> p.tenant_id)                                                    AS catalog_other_shop,
  (SELECT count(*) FROM public.preorders p JOIN public.user_profiles u ON u.id = p.user_id
    WHERE u.tenant_id <> p.tenant_id)                                                    AS customer_other_shop,
  (SELECT count(*) FROM public.preorders p
    WHERE NOT EXISTS (SELECT 1 FROM public.catalog c WHERE c.id = p.catalog_id))         AS catalog_missing,
  (SELECT count(*) FROM public.preorders p
    WHERE NOT EXISTS (SELECT 1 FROM public.user_profiles u WHERE u.id = p.user_id))      AS customer_missing;


-- =====================================================================
-- P2a. Can the trigger function see every shop's rows? It runs as its owner (SECURITY DEFINER).
-- Run P2a and P2b as two separate runs.
-- =====================================================================
SELECT c.relname, pg_get_userbyid(c.relowner) AS owner, c.relrowsecurity AS rls_on, c.relforcerowsecurity AS rls_forced
FROM pg_class c
WHERE c.relnamespace = 'public'::regnamespace AND c.relname IN ('catalog', 'user_profiles', 'preorders');

-- P2b.
SELECT current_user, rolbypassrls FROM pg_roles WHERE rolname = current_user;

-- PASS for P2: rls_forced false on all three, and either `owner` equals current_user or rolbypassrls is true.
-- FAIL: otherwise HALT. The function's lookups would be filtered by RLS, and because the trigger fails closed, every
-- reservation would be refused.


-- =====================================================================
-- THE PROBE (writes nothing; run BEFORE applying, then AFTER)
-- Every outcome is an error, so the DO block always rolls back. Before the trigger it must read `F164 FAIL 1`
-- (that is the probe seen red); after, `F164 PASS: checks 1 2 3 4 passed`. Any other text is a fail.
-- `F164 PASS: checks 1 2 4 passed` means no second-shop customer exists to test the owner check (likely on
-- production): say so, do not call it a pass of check 3.
-- If it errors with a not-null or other constraint message before any F164 text, the probe's insert is missing a
-- required column: fix the PROBE (technical-reference.md § 4.4), never the trigger.
-- =====================================================================
DO $$
DECLARE
  v_home uuid; v_pid uuid; v_user uuid; v_cat uuid;
  v_foreign_cat uuid; v_foreign_user uuid;
  v_ran text := '';
BEGIN
  SELECT tenant_id INTO v_home FROM preorders GROUP BY tenant_id ORDER BY count(*) DESC LIMIT 1;
  SELECT id INTO v_pid FROM preorders WHERE tenant_id = v_home ORDER BY id LIMIT 1;
  SELECT user_id INTO v_user FROM preorders WHERE id = v_pid;
  SELECT c.id INTO v_cat FROM catalog c
   WHERE c.tenant_id = v_home
     AND NOT EXISTS (SELECT 1 FROM preorders p WHERE p.user_id = v_user AND p.catalog_id = c.id)
   ORDER BY c.id LIMIT 1;
  SELECT id INTO v_foreign_cat  FROM catalog       WHERE tenant_id <> v_home ORDER BY id LIMIT 1;
  SELECT id INTO v_foreign_user FROM user_profiles WHERE tenant_id <> v_home ORDER BY id LIMIT 1;

  IF v_foreign_cat IS NULL THEN
    RAISE EXCEPTION 'F164 PROBE CANNOT RUN: no listing from a second shop';
  END IF;

  -- 1. A reservation on another shop's listing must be refused.
  BEGIN
    INSERT INTO preorders (tenant_id, user_id, catalog_id, quantity) VALUES (v_home, v_user, v_foreign_cat, 1);
    RAISE EXCEPTION 'F164 FAIL 1: a reservation on another shop''s listing was ACCEPTED (rolled back)';
  EXCEPTION WHEN check_violation THEN v_ran := v_ran || ' 1';
  END;

  -- 2. Moving a reservation onto another shop's listing must be refused.
  BEGIN
    UPDATE preorders SET catalog_id = v_foreign_cat WHERE id = v_pid;
    RAISE EXCEPTION 'F164 FAIL 2: moving a reservation onto another shop''s listing was ACCEPTED (rolled back)';
  EXCEPTION WHEN check_violation THEN v_ran := v_ran || ' 2';
  END;

  -- 3. (D1) A reservation for another shop's customer must be refused.
  IF v_foreign_user IS NOT NULL THEN
    BEGIN
      INSERT INTO preorders (tenant_id, user_id, catalog_id, quantity) VALUES (v_home, v_foreign_user, v_cat, 1);
      RAISE EXCEPTION 'F164 FAIL 3: a reservation for another shop''s customer was ACCEPTED (rolled back)';
    EXCEPTION WHEN check_violation THEN v_ran := v_ran || ' 3';
    END;
  END IF;

  -- 4. Negative control: a same-shop reservation must be accepted.
  INSERT INTO preorders (tenant_id, user_id, catalog_id, quantity) VALUES (v_home, v_user, v_cat, 1);
  v_ran := v_ran || ' 4';

  RAISE EXCEPTION 'F164 PASS: checks% passed; nothing was written (this error rolls the probe back)', v_ran;
END $$;


-- =====================================================================
-- THE MIGRATION (§ 6.3). Run as ONE run.
-- =====================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.preorders_require_same_tenant()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- F164 (G-I). A reservation must point at a listing of its own shop and belong to a customer of its own shop.
  -- SECURITY DEFINER: the caller's RLS hides other shops' rows, and a hidden row must not read as "absent".
  -- Fails closed: no matching row (another shop's, or no such row) refuses the write.
  -- No service-role exemption: the service-role import wrote the two rows F164 found.
  IF NOT EXISTS (SELECT 1 FROM catalog WHERE id = NEW.catalog_id AND tenant_id = NEW.tenant_id) THEN
    RAISE EXCEPTION 'A reservation must reference a listing of its own shop'
      USING ERRCODE = 'check_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM user_profiles WHERE id = NEW.user_id AND tenant_id = NEW.tenant_id) THEN
    RAISE EXCEPTION 'A reservation must belong to a customer of its own shop'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$function$;

-- F124: invoked by the trigger, not by any role. Revoke explicitly (REVOKE FROM PUBLIC alone does not strip
-- Supabase's defaults). Same as F109.
REVOKE ALL ON FUNCTION public.preorders_require_same_tenant() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.preorders_require_same_tenant() FROM anon;
REVOKE ALL ON FUNCTION public.preorders_require_same_tenant() FROM authenticated;

DROP TRIGGER IF EXISTS trg_preorders_require_same_tenant ON public.preorders;
CREATE TRIGGER trg_preorders_require_same_tenant
  BEFORE INSERT OR UPDATE OF catalog_id, tenant_id, user_id ON public.preorders
  FOR EACH ROW EXECUTE FUNCTION public.preorders_require_same_tenant();

COMMIT;

-- Design notes, so nobody re-derives them: `UPDATE OF` fires when a listed column is in the SET list even if its
-- value is unchanged, so PostgREST upserts fire it (and pass); quantity, fulfilment, arrival_outcome, notes-only and
-- unavailable_dismissed_at updates do not. A missing listing or customer now raises 23514 instead of the foreign
-- key's 23503; nothing legitimate sends one. check_violation reaches the app as HTTP 400. A future shared-catalog
-- model (one listing used by several shops) would have to revisit this trigger.


-- =====================================================================
-- VERIFICATION (each states its failing output)
-- =====================================================================

-- V1. Triggers on preorders.
SELECT t.tgname,
       CASE WHEN t.tgtype & 2 = 2 THEN 'BEFORE' ELSE 'AFTER' END AS timing,
       (t.tgtype & 4  = 4)  AS on_insert,
       (t.tgtype & 8  = 8)  AS on_delete,
       (t.tgtype & 16 = 16) AS on_update,
       CASE WHEN t.tgtype & 1 = 1 THEN 'ROW' ELSE 'STATEMENT' END AS level,
       CASE WHEN t.tgenabled = 'O' THEN 'enabled' ELSE 'DISABLED' END AS status,
       (SELECT string_agg(a.attname, ',' ORDER BY a.attname)
          FROM pg_attribute a
         WHERE a.attrelid = t.tgrelid AND a.attnum = ANY (t.tgattr::int2[])) AS update_columns
FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
WHERE c.relname = 'preorders' AND c.relnamespace = 'public'::regnamespace AND NOT t.tgisinternal
ORDER BY t.tgname;
-- PASS: two rows. trg_preorders_block_ordered_delete: BEFORE, on_delete true, ROW, enabled (F109, unchanged).
--       trg_preorders_require_same_tenant: BEFORE, on_insert true, on_update true, on_delete false, ROW, enabled,
--       update_columns 'catalog_id,tenant_id,user_id'.
-- FAIL: the second row absent, AFTER, STATEMENT, DISABLED, or a different column list.

-- V2. Grants and definer settings.
SELECT has_function_privilege('anon', 'public.preorders_require_same_tenant()', 'EXECUTE')          AS anon_exec,
       has_function_privilege('authenticated', 'public.preorders_require_same_tenant()', 'EXECUTE') AS authenticated_exec,
       p.prosecdef AS security_definer, p.proconfig AS config
FROM pg_proc p WHERE p.oid = 'public.preorders_require_same_tenant()'::regprocedure;
-- PASS: false, false, true, {search_path=public}.   FAIL: any EXECUTE true, security_definer false, config empty.

-- V3 = P1 again (still all 0).   V4 = the probe above (`F164 PASS`).


-- =====================================================================
-- § R: ROLLBACK (staging, or production if S2b fails)
-- =====================================================================
-- BEGIN;
-- DROP TRIGGER IF EXISTS trg_preorders_require_same_tenant ON public.preorders;
-- DROP FUNCTION IF EXISTS public.preorders_require_same_tenant();
-- COMMIT;
