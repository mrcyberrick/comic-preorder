-- STATUS: staging=APPLIED 2026-10-11 | prod=APPLIED 2026-10-11
--         STAGING: applied by Rick 2026-10-11. His pasted definition verdict read 'OK - 1 definition,
--         SECURITY DEFINER, search_path pinned, F173 body present'. The pre-check and grants verdicts
--         were NOT pasted; the grants were instead verified BEHAVIOURALLY by the harness
--         playwright/f173-move-verify.mjs (anon refused with 42501, a signed-in non-admin refused, a
--         signed-in admin allowed), 50/50 on 2026-10-11.
--         PRODUCTION: applied 2026-10-11 by Rick, INFERRED from his second paste of the same definition
--         verdict ('OK - 1 definition, SECURITY DEFINER, search_path pinned, F173 body present'), which
--         carried no project name. Independently confirmed the same day by an anonymous probe of
--         production's REST endpoint: the function exists and anon is refused (42501, HTTP 401).
--         NOT verified on production: the pre-check and grants verdicts, that the body there is the F173
--         body (only Rick's paste says so), and the admin path (none was used when this was written;
--         it was run once on 2026-10-11, a move-and-back read back from the database: see
--         docs/f173-move-reservations.md § 5).
--         The admin.html control is NOT on production yet; the SQL went first, as F105 requires.
-- (F105) This line is the applied-state record. A gate that lives only in
-- prose gets missed -- F6 sat unapplied on production for 13 days because
-- nothing machine-readable said so. Update it the moment you run this file.
-- ⚠️ Write the REAL state here, with no qualifier the regex cannot see:
--    /promote-prod step 0 matches prod=(APPLIED|N/A) and returned CLEAN for
--    F155 against a line reading "prod=APPLIED (pre-F155 body)". Do not
--    repeat that.
-- ============================================================================
-- admin_move_reservations(p_from_catalog_id uuid, p_to_catalog_id uuid,
--                         p_move_order boolean DEFAULT false)  -> jsonb
--
-- F173 (docs/technical-reference.md § 13; plan docs/f173-move-reservations.md).
-- Prepared 2026-10-11. Run: STAGING FIRST. Operator: Rick (Supabase SQL Editor).
-- Production BEFORE the admin.html control reaches it, never after (F105): the
-- client calls this function, and a page that calls a missing function fails
-- only when the button is pressed.
--
-- WHY THIS EXISTS:
--   When a distributor replaces a title's product code, nothing in the app links
--   the old listing to the new one, and no screen can repoint a reservation
--   (Hyde Street #14 CVR A, 0526IM0377 -> 0726IM0466, 2026-10-11, was repaired
--   by hand-written SQL). This is the manual control Rick asked for: move the
--   still-open reservations from one listing to another, and optionally carry
--   the order record across, in ONE transaction that either completes or
--   changes nothing.
--
-- WHAT IT DOES
--   1. Moves every UNFULFILLED reservation on the FROM listing to the TO listing.
--      A fulfilled reservation is history and stays where it is.
--   2. Clears arrival_outcome and unavailable_dismissed_at on the moved rows:
--      both are statements about the OLD listing ("did not arrive", "cleared by
--      an admin") and would be false on a listing nobody has judged yet.
--   3. Appends an audit line to preorders.notes (a column no screen reads or
--      writes today), so the move is traceable after the fact.
--   4. If p_move_order is true AND the old order code nets above zero in
--      order_submissions: adds a -N 'adjustment' under the old code and a +N
--      'adjustment' under the new code, where N = least(old net, quantity
--      moved). The ledger is append-only; nothing is edited or deleted.
--
-- WHAT IT REFUSES (raises; nothing is written)
--   not a signed-in admin of this tenant; same listing twice; either listing
--   missing or in another tenant; different distributors; target marked
--   withdrawn; nothing open to move; a moved customer ALREADY holds a
--   reservation on the target (UNIQUE (user_id, catalog_id) would reject it
--   anyway -- this says so in words and names the count).
--
-- WHAT IT DELIBERATELY DOES NOT DO
--   It does not touch the target's dates. The weekly recheck (check-dates.js)
--   corrects a listing that holds a reservation, and after this move the target
--   does. Until that run the target may carry a stale FOC / on-sale date; the
--   admin dialog says so. (Rick, 2026-10-11: "Hold until recheck as this is
--   cleaner.")
--
-- TENANT SCOPE is derived from current_tenant_id() inside the function, never
--   from a parameter -- the pattern F20 / get_publisher_reserve_counts use.
--   Both catalog ids are re-checked against that tenant, so a forged id from
--   another tenant is "not found" rather than moved (F164's lesson: the
--   preorders policies check only the row's own tenant_id, never the catalog
--   row's).
--
-- ORDER CODE rule below reproduces app.js exportCode(c, distributor) exactly:
--   PRH   -> isbn  || item_code || upc || ''
--   other -> item_code || upc || isbn || ''
--   with JS `||` semantics (null AND empty string both fall through), hence
--   COALESCE(NULLIF(x, ''), ...).
-- ============================================================================


-- ── PRE-CHECK ───────────────────────────────────────────────────────────────
-- technical-reference.md § 4 is older than some columns (arrival_outcome,
-- unavailable_dismissed_at were added later). Confirm every column this
-- function names actually exists before creating anything.
-- EXPECTED: verdict = 'OK - all 29 columns present'
SELECT
  CASE WHEN count(*) = 29 THEN 'OK - all 29 columns present'
       ELSE 'PROBLEM - expected 29 columns, found ' || count(*)
            || '. The schema moved: STOP, do not create the function, re-audit § 4 against live.'
  END AS verdict,
  count(*) AS columns_found
FROM information_schema.columns
WHERE table_schema = 'public'
  AND (   (table_name = 'preorders'         AND column_name IN ('id', 'user_id', 'catalog_id', 'tenant_id', 'quantity', 'fulfilled', 'notes', 'arrival_outcome', 'unavailable_dismissed_at'))
       OR (table_name = 'catalog'           AND column_name IN ('id', 'tenant_id', 'distributor', 'item_code', 'upc', 'isbn', 'title', 'foc_date', 'catalog_month', 'withdrawn_at'))
       OR (table_name = 'order_submissions' AND column_name IN ('tenant_id', 'distributor', 'order_code', 'item_code', 'title', 'quantity', 'order_type', 'foc_date', 'catalog_month', 'submitted_on')) );


-- ── FUNCTION ────────────────────────────────────────────────────────────────
-- Plain LANGUAGE plpgsql with explicit variable names (v_*) that collide with
-- no column, so no reference needs disambiguating.
CREATE OR REPLACE FUNCTION public.admin_move_reservations(
  p_from_catalog_id uuid,
  p_to_catalog_id   uuid,
  p_move_order      boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant     uuid := current_tenant_id();
  v_from       catalog%ROWTYPE;
  v_to         catalog%ROWTYPE;
  v_ids        uuid[];
  v_count      integer;
  v_qty        integer;
  v_conflicts  integer;
  v_changed    integer;
  v_old_code   text;
  v_new_code   text;
  v_old_net    integer := 0;
  v_adj        integer := 0;
BEGIN
  -- F173: the caller must be a signed-in admin of a resolvable tenant.
  IF auth.uid() IS NULL OR v_tenant IS NULL OR current_user_is_admin() IS NOT TRUE THEN
    RAISE EXCEPTION 'Only a signed-in admin can move reservations' USING ERRCODE = '42501';
  END IF;

  IF p_from_catalog_id IS NULL OR p_to_catalog_id IS NULL OR p_from_catalog_id = p_to_catalog_id THEN
    RAISE EXCEPTION 'Choose two different listings';
  END IF;

  SELECT * INTO v_from FROM catalog WHERE id = p_from_catalog_id AND tenant_id = v_tenant;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'The listing to move reservations FROM was not found in this store';
  END IF;
  SELECT * INTO v_to FROM catalog WHERE id = p_to_catalog_id AND tenant_id = v_tenant;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'The listing to move reservations TO was not found in this store';
  END IF;

  IF v_from.distributor IS DISTINCT FROM v_to.distributor THEN
    RAISE EXCEPTION 'Both listings must be from the same distributor (% vs %)', v_from.distributor, v_to.distributor;
  END IF;
  IF v_to.withdrawn_at IS NOT NULL THEN
    RAISE EXCEPTION 'The listing to move TO is marked withdrawn; it cannot take reservations';
  END IF;

  -- Lock the open reservations on the FROM listing for the rest of the
  -- transaction (the FOR UPDATE is in a subquery so the aggregate is legal).
  SELECT array_agg(s.id), count(*)::integer, COALESCE(sum(s.quantity), 0)::integer
    INTO v_ids, v_count, v_qty
  FROM (
    SELECT p.id, p.quantity
    FROM preorders p
    WHERE p.catalog_id = v_from.id
      AND p.tenant_id  = v_tenant
      AND p.fulfilled  = false
    FOR UPDATE
  ) s;

  IF v_count = 0 THEN
    RAISE EXCEPTION 'There are no open reservations on the listing to move FROM';
  END IF;

  -- A customer who already reserved the target cannot also have this one.
  SELECT count(*)::integer INTO v_conflicts
  FROM preorders t
  WHERE t.catalog_id = v_to.id
    AND t.user_id IN (SELECT m.user_id FROM preorders m WHERE m.id = ANY (v_ids));
  IF v_conflicts > 0 THEN
    RAISE EXCEPTION '% customer(s) already have a reservation on the listing to move TO. Remove or settle those first.', v_conflicts;
  END IF;

  v_old_code := CASE WHEN v_from.distributor = 'PRH'
      THEN COALESCE(NULLIF(v_from.isbn, ''), NULLIF(v_from.item_code, ''), NULLIF(v_from.upc, ''), '')
      ELSE COALESCE(NULLIF(v_from.item_code, ''), NULLIF(v_from.upc, ''), NULLIF(v_from.isbn, ''), '')
    END;
  v_new_code := CASE WHEN v_to.distributor = 'PRH'
      THEN COALESCE(NULLIF(v_to.isbn, ''), NULLIF(v_to.item_code, ''), NULLIF(v_to.upc, ''), '')
      ELSE COALESCE(NULLIF(v_to.item_code, ''), NULLIF(v_to.upc, ''), NULLIF(v_to.isbn, ''), '')
    END;

  UPDATE preorders
     SET catalog_id               = v_to.id,
         arrival_outcome          = NULL,
         unavailable_dismissed_at = NULL,
         notes = concat_ws(' | ', NULLIF(notes, ''),
                   'Moved from ' || v_old_code || ' (' || COALESCE(v_from.catalog_month, '?') || ') to '
                   || v_new_code || ' (' || COALESCE(v_to.catalog_month, '?') || ') on ' || current_date::text)
   WHERE id = ANY (v_ids)
     AND tenant_id = v_tenant;
  GET DIAGNOSTICS v_changed = ROW_COUNT;
  IF v_changed <> v_count THEN
    RAISE EXCEPTION 'Expected to move % reservation(s) but changed %; nothing was saved', v_count, v_changed;
  END IF;

  -- Optional: carry the order record across. Only what the old code actually
  -- holds, and never more than the quantity that moved.
  IF p_move_order AND v_old_code <> '' AND v_new_code <> '' AND v_old_code <> v_new_code THEN
    SELECT COALESCE(sum(o.quantity), 0)::integer INTO v_old_net
    FROM order_submissions o
    WHERE o.tenant_id   = v_tenant
      AND o.distributor = v_from.distributor
      AND o.order_code  = v_old_code;

    v_adj := LEAST(GREATEST(v_old_net, 0), v_qty);
    IF v_adj > 0 THEN
      INSERT INTO order_submissions
        (tenant_id, distributor, order_code, item_code, title, quantity, order_type, foc_date, catalog_month, submitted_on)
      VALUES
        (v_tenant, v_from.distributor, v_old_code, v_from.item_code, v_from.title, -v_adj, 'adjustment', v_from.foc_date, v_from.catalog_month, current_date),
        (v_tenant, v_to.distributor,   v_new_code, v_to.item_code,   v_to.title,    v_adj, 'adjustment', v_to.foc_date,   v_to.catalog_month,   current_date);
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'moved',        v_count,
    'quantity',     v_qty,
    'order_moved',  v_adj,
    'old_order_net', v_old_net,
    'from_code',    v_old_code,
    'to_code',      v_new_code
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_move_reservations(uuid, uuid, boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_move_reservations(uuid, uuid, boolean) FROM PUBLIC, anon;


-- ── VERIFY: grants ──────────────────────────────────────────────────────────
-- Aggregated into a single verdict row: a zero-row result must not be able to
-- read as a pass. F124: only four functions may legitimately carry an anon
-- grant (current_tenant_id, current_user_is_admin, get_popular_series,
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
WHERE routine_name = 'admin_move_reservations';


-- ── VERIFY: does it exist, and did CREATE OR REPLACE keep its properties ────
-- An AGGREGATE, so it always returns exactly ONE row with a spelled-out
-- verdict. A plain SELECT ... WHERE proname = ... returns ZERO rows when the
-- function is absent, which the editor shows as "Success. No rows returned" --
-- indistinguishable from a pass. The F173 marker is what proves THIS body
-- landed rather than some other function of the same name.
--
-- EXPECTED: verdict = 'OK - 1 definition, SECURITY DEFINER, search_path pinned, F173 body present'
SELECT
  CASE
    WHEN count(*) = 0 THEN 'MISSING - the CREATE did not run. Re-run this file from the top.'
    WHEN count(*) > 1 THEN 'PROBLEM - ' || count(*) || ' definitions exist; a stray overload was left behind'
    WHEN bool_and(p.prosecdef) IS NOT TRUE THEN 'PROBLEM - not SECURITY DEFINER'
    WHEN bool_and(array_to_string(p.proconfig, ',') LIKE '%search_path%') IS NOT TRUE
      THEN 'PROBLEM - search_path is not pinned (F23/Pattern E footgun)'
    WHEN bool_and(p.prosrc LIKE '%F173%') IS NOT TRUE
      THEN 'PROBLEM - body is not the F173 version. Re-run this file from the top.'
    ELSE 'OK - 1 definition, SECURITY DEFINER, search_path pinned, F173 body present'
  END                                                   AS verdict,
  count(*)                                              AS definitions,
  COALESCE(string_agg(pg_get_function_identity_arguments(p.oid), ' | '), '-') AS signatures,
  COALESCE(string_agg(array_to_string(p.proconfig, ','), ' | '), '-')         AS settings
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'admin_move_reservations';


-- ── SMOKE ───────────────────────────────────────────────────────────────────
-- The SQL Editor runs as `postgres`, so auth.uid() is NULL here and the function
-- would REFUSE ("Only a signed-in admin can move reservations", SQLSTATE 42501).
-- So the Editor cannot exercise it and this file deliberately does not try: a
-- smoke whose expected result is an error cannot be read at a glance, and an
-- unexpected success would be indistinguishable in the Editor.
--
-- The behavioural checks are made as a REAL signed-in admin, outside the Editor:
--   playwright/f173-move-verify.mjs (local-only): throwaway admin and customers,
--   seeded ZZTEST173 listings, then every guard in the "WHAT IT REFUSES" list
--   above, the happy path, the order-record carry, an anon call (must be
--   refused), teardown and a fresh re-read. Then one live click in the admin
--   dialog.
--
-- What the Editor CAN usefully show is the two verdicts above. If either does
-- not read OK, stop; do not test the control.


-- ── ROLLBACK ────────────────────────────────────────────────────────────────
-- Safe at any time: nothing else calls the function until the admin.html
-- control ships, and dropping it does not undo any move already made (moved
-- reservations carry an audit line in preorders.notes beginning 'Moved from').
-- DROP FUNCTION IF EXISTS public.admin_move_reservations(uuid, uuid, boolean);
