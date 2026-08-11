-- STATUS: staging=APPLIED 2026-08-03 | prod=APPLIED 2026-08-03
--         F101/F102 table + admin-only RLS.
-- (F105) This line is the applied-state record. A gate that lives only in
-- prose gets missed -- F6 sat unapplied on production for 13 days because
-- nothing machine-readable said so. Update it the moment you run this file.
-- ============================================================================
-- order_submissions — a distributor-code-keyed order ledger (F102)
-- Prepared 2026-08-02 (order-export correctness session, F101 + F102).
-- Plan: docs/order-export-foc-window-and-order-state.md § 4.2, § S2.
-- Run: STAGING first (this file targets staging). Production is a separate,
--      later run at Rick's explicit call — not part of this file.
-- Operator: Rick (Supabase SQL Editor, runs as postgres superuser).
--
-- WHY THIS TABLE EXISTS:
--   F102 confirmed a realized cost exposure: PRH holds 12 copies of
--   75960621668000111 (MIDNIGHT X-MEN #1) against 7 reservations because the
--   June order (5 copies) was never recorded anywhere, so the July export
--   re-submitted the same code as if it had never been ordered. The store's
--   own "order was placed" fact needs to survive a title being re-listed
--   under a new catalog_id in a later catalog_month — the existing
--   `preorders.fulfilled` flag cannot do this because it is keyed on
--   catalog_id, which does not survive a re-listing (plan § 2.5–2.6).
--   Keying this ledger on the distributor code (order_code) is what survives.
--
-- DESIGN NOTES (plan § 4.2):
--   - No unique constraint on order_code — re-ordering a code is legitimate
--     (a customer may reserve after an order has gone out). The ledger
--     records history; the export reasons over it at generation time.
--   - Written manually (By Distributor "Mark Fulfilled"-adjacent action),
--     not automatically on export click — clicking Export produces a file,
--     not proof of submission.
--   - No UPDATE/DELETE policy: append-only, same posture as
--     reservation_history. A miskeyed row is corrected by a service-role
--     SQL statement (Rick, SQL Editor), not by an app-level edit path —
--     there is no admin UI for editing a ledger row in this session's scope.
--   - RLS follows the app_settings shape (current_tenant_id() +
--     current_user_is_admin(), TO authenticated on every policy — the
--     explicit role grant that phase-5.0 S2 had to backfill onto several
--     older policies, so it is written explicitly here from the start).
-- ============================================================================

-- Pre-check: confirm the table does not already exist
SELECT to_regclass('public.order_submissions');
-- Expected: null

BEGIN;

CREATE TABLE public.order_submissions (
  id            uuid        NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id     uuid        NOT NULL,
  distributor   text        NOT NULL,
  order_code    text        NOT NULL,
  item_code     text,
  title         text,
  quantity      integer     NOT NULL,
  order_type    text        NOT NULL,
  foc_date      date,
  catalog_month text,
  submitted_on  date        NOT NULL,
  created_at    timestamptz DEFAULT now(),
  CONSTRAINT order_submissions_pkey PRIMARY KEY (id),
  CONSTRAINT order_submissions_tenant_id_fkey
    FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE,
  CONSTRAINT order_submissions_distributor_check
    CHECK (distributor = ANY (ARRAY['Lunar', 'PRH'])),
  CONSTRAINT order_submissions_order_type_check
    CHECK (order_type = ANY (ARRAY['monthly', 'adhoc'])),
  CONSTRAINT order_submissions_quantity_check
    CHECK (quantity >= 1)
);

CREATE INDEX idx_order_submissions_lookup
  ON public.order_submissions (tenant_id, distributor, order_code);

CREATE INDEX idx_order_submissions_submitted
  ON public.order_submissions (tenant_id, submitted_on);

ALTER TABLE public.order_submissions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admins read tenant order_submissions" ON public.order_submissions
  FOR SELECT
  TO authenticated
  USING (tenant_id = current_tenant_id() AND current_user_is_admin());

CREATE POLICY "admins insert tenant order_submissions" ON public.order_submissions
  FOR INSERT
  TO authenticated
  WITH CHECK (tenant_id = current_tenant_id() AND current_user_is_admin());

COMMIT;

-- ----------------------------------------------------------------------------
-- Post-DDL verification (run these, confirm the shapes below before telling
-- the agent to proceed — the agent's own V1 gate is a separate step run
-- against PostgREST with real throwaway user JWTs, not SET LOCAL in this
-- editor; feedback_supabase_sql_editor_set_local records that BEGIN +
-- SET LOCAL + ROLLBACK has failed here before with 25P02).
-- ----------------------------------------------------------------------------

-- 1. Table + columns exist as expected
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'order_submissions'
ORDER BY ordinal_position;

-- 2. RLS is enabled
SELECT relrowsecurity, relforcerowsecurity
FROM pg_class
WHERE oid = 'public.order_submissions'::regclass;
-- Expected: relrowsecurity = true, relforcerowsecurity = false (matches every
-- other table per technical-reference.md § 7)

-- 3. Both policies exist with the expected roles/quals
SELECT polname, polcmd, polroles::regrole[], pg_get_expr(polqual, polrelid) AS using_expr,
       pg_get_expr(polwithcheck, polrelid) AS check_expr
FROM pg_policy
WHERE polrelid = 'public.order_submissions'::regclass;
-- Expected: 2 rows — SELECT (using: tenant_id = current_tenant_id() AND
-- current_user_is_admin()) and INSERT (check: same expression), both
-- polroles = {authenticated}

-- 4. Indexes exist
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'order_submissions';

-- 5. Row count (expect 0 — nothing writes here yet)
SELECT count(*) FROM public.order_submissions;
