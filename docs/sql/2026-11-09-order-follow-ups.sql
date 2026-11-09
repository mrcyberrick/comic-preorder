-- STATUS: staging=PENDING | prod=PENDING
-- ============================================================================
-- Order Follow-Up redesign, S2 (docs/order-follow-up-redesign.md § 4 S2)
-- Prepared 2026-11-09. Operator: Rick (Supabase SQL Editor, runs as postgres).
-- Run: STAGING first. Production before the S3/S4 client is promoted
--      (/promote-prod step 0 blocks on a PENDING prod status).
--
-- Two changes, one transaction:
--   (a) preorders.arrival_outcome gains a fifth value, 'not_available': the
--       store could not get a title it never ordered ("Can't get it" on an
--       At risk / Backordered row, Rick's D2 + D5). Named not_available, not
--       unavailable, because app.js already uses orderState 'unavailable' for
--       a ledger rejection (plan C4). Additive to the value set only; every
--       existing row still satisfies the CHECK. Same DROP + ADD shape as
--       docs/sql/f134-arrival-outcome-widen.sql (there is no ALTER CHECK).
--   (b) public.order_follow_ups: one admin-only row per title (tenant,
--       distributor, order code = the panel's exportCode()), holding the
--       snooze date and note (D1) and the last Follow-Up action with who and
--       when (needed for "Turned up after all", D6, and Withdrawn
--       acknowledgement, D7). Not on preorders: customers can update their
--       own reservation rows (`users manage own preorders` is ALL), and a
--       per-reservation snooze would lapse when a new customer reserved the
--       title (plan C2). The import never reads or writes this table.
--
-- Grants: G-J (2026-10-22) removed anon's default privileges in public, so
-- anon gets nothing; authenticated is narrowed to the four DML privileges and
-- RLS limits it to the tenant's admins.
-- ============================================================================

-- ── PRE-CHECK (run on its own first; the SQL Editor shows only the last result)
SELECT
  (SELECT pg_get_constraintdef(oid) FROM pg_constraint
    WHERE conrelid = 'public.preorders'::regclass AND contype = 'c'
      AND conname = 'preorders_arrival_outcome_check')               AS current_check,
  to_regclass('public.order_follow_ups') IS NOT NULL                  AS table_already_exists,
  (SELECT string_agg(slug, ',' ORDER BY slug) FROM public.tenants
    WHERE slug NOT LIKE 'pw-%')                                       AS tenants_here;
-- Expected: current_check = CHECK ((arrival_outcome = ANY (ARRAY['arrived'::text,
--   'not_arrived'::text, 'damaged'::text, 'unknown'::text])))
-- table_already_exists = false
-- tenants_here: staging = demoshop,raysandjudys ; production = comicstore,rjbookstop
-- STOP if current_check differs or the table already exists.

-- ── THE CHANGE (run as one block) ──────────────────────────────────────────
BEGIN;

ALTER TABLE public.preorders
  DROP CONSTRAINT preorders_arrival_outcome_check;
ALTER TABLE public.preorders
  ADD CONSTRAINT preorders_arrival_outcome_check
  CHECK (arrival_outcome IN ('arrived', 'not_arrived', 'damaged', 'unknown', 'not_available'));

CREATE TABLE public.order_follow_ups (
  id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid        NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  distributor    text        NOT NULL CHECK (distributor IN ('Lunar', 'PRH')),
  order_code     text        NOT NULL,
  title          text,
  snoozed_until  date,
  note           text        CHECK (note IS NULL OR char_length(note) <= 300),
  last_action    text        CHECK (last_action IN ('arrived', 'not_arrived', 'damaged', 'rejected',
                                                    'not_available', 'snoozed', 'woken',
                                                    'acknowledged', 'moved')),
  last_action_at timestamptz,
  last_action_by uuid        REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, distributor, order_code)
);

ALTER TABLE public.order_follow_ups ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admins manage tenant follow ups" ON public.order_follow_ups
  FOR ALL TO authenticated
  USING      (current_user_is_admin() AND tenant_id = current_tenant_id())
  WITH CHECK (current_user_is_admin() AND tenant_id = current_tenant_id());

REVOKE ALL ON public.order_follow_ups FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.order_follow_ups TO authenticated;
GRANT ALL ON public.order_follow_ups TO service_role;

COMMIT;

-- ── VERDICT (run on its own after the block; reads differently before/after)
SELECT
  (SELECT pg_get_constraintdef(oid) LIKE '%not_available%' FROM pg_constraint
    WHERE conrelid = 'public.preorders'::regclass
      AND conname = 'preorders_arrival_outcome_check')                AS check_has_not_available,
  (SELECT relrowsecurity FROM pg_class
    WHERE oid = to_regclass('public.order_follow_ups'))               AS rls_enabled,
  (SELECT count(*) FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'order_follow_ups')   AS policies,
  (SELECT count(*) FROM information_schema.role_table_grants
    WHERE table_schema = 'public' AND table_name = 'order_follow_ups'
      AND grantee IN ('anon', 'PUBLIC'))                              AS anon_grants,
  (SELECT string_agg(privilege_type, ',' ORDER BY privilege_type)
     FROM information_schema.role_table_grants
    WHERE table_schema = 'public' AND table_name = 'order_follow_ups'
      AND grantee = 'authenticated')                                  AS authenticated_grants,
  (SELECT string_agg(slug, ',' ORDER BY slug) FROM public.tenants
    WHERE slug NOT LIKE 'pw-%')                                       AS tenants_here;
-- Expected: check_has_not_available = true, rls_enabled = true, policies = 1,
-- anon_grants = 0, authenticated_grants = DELETE,INSERT,SELECT,UPDATE,
-- tenants_here names the project you meant to run it on.
-- Before the block runs this returns false / NULL / 0 / 0 / NULL, so a run
-- that did not land cannot read as a pass.
