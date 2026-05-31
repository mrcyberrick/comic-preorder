-- Phase 4.3 — Production schema constraints + view recreation + RLS recursion fix
-- Applied: 2026-05-31 (Sat morning cutover slot)
-- Environment: Production (plgegklqtdjxeglvyjte)
-- All gates green: PF1–PF7, V1–V7, SG1–SG3
--
-- PF4 resolution: both unique keys were constraints (ALTER TABLE DROP CONSTRAINT)
-- PF5 resolution: all 7 policies had roles={public} for 5, {authenticated} for 2;
--   Option A approved — all recreated TO authenticated. All with_check = null (omitted).
-- Pre-flight note: 5 usage_events rows had NULL tenant_id (written after 4.2 backfill);
--   backfilled to founding tenant before PF3 re-confirmed 0 NULLs on all 9 tables.

-- ============================================================
-- S1 — NOT NULL promotion x9
-- ============================================================

ALTER TABLE public.app_settings        ALTER COLUMN tenant_id SET NOT NULL;
ALTER TABLE public.catalog             ALTER COLUMN tenant_id SET NOT NULL;
ALTER TABLE public.preorders           ALTER COLUMN tenant_id SET NOT NULL;
ALTER TABLE public.reservation_history ALTER COLUMN tenant_id SET NOT NULL;
ALTER TABLE public.settings            ALTER COLUMN tenant_id SET NOT NULL;
ALTER TABLE public.subscriptions       ALTER COLUMN tenant_id SET NOT NULL;
ALTER TABLE public.usage_events        ALTER COLUMN tenant_id SET NOT NULL;
ALTER TABLE public.user_profiles       ALTER COLUMN tenant_id SET NOT NULL;
ALTER TABLE public.weekly_shipment     ALTER COLUMN tenant_id SET NOT NULL;

-- ============================================================
-- S2 — catalog tenant-aware unique key
-- ============================================================

ALTER TABLE public.catalog DROP CONSTRAINT catalog_item_code_distributor_month_unique;

ALTER TABLE public.catalog
  ADD CONSTRAINT catalog_tenant_item_distributor_month_unique
  UNIQUE (tenant_id, item_code, distributor, catalog_month);

-- ============================================================
-- S3 — subscriptions tenant-aware unique key
-- ============================================================

ALTER TABLE public.subscriptions DROP CONSTRAINT subscriptions_user_id_series_name_distributor_key;

ALTER TABLE public.subscriptions
  ADD CONSTRAINT subscriptions_tenant_user_series_unique
  UNIQUE (tenant_id, user_id, series_name, distributor);

-- ============================================================
-- S4 — Foreign keys x9 (tenant_id -> tenants(id) ON DELETE CASCADE)
-- ============================================================

ALTER TABLE public.app_settings        ADD CONSTRAINT app_settings_tenant_id_fkey        FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;
ALTER TABLE public.catalog             ADD CONSTRAINT catalog_tenant_id_fkey             FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;
ALTER TABLE public.preorders           ADD CONSTRAINT preorders_tenant_id_fkey           FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;
ALTER TABLE public.reservation_history ADD CONSTRAINT reservation_history_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;
ALTER TABLE public.settings            ADD CONSTRAINT settings_tenant_id_fkey            FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;
ALTER TABLE public.subscriptions       ADD CONSTRAINT subscriptions_tenant_id_fkey       FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;
ALTER TABLE public.usage_events        ADD CONSTRAINT usage_events_tenant_id_fkey        FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;
ALTER TABLE public.user_profiles       ADD CONSTRAINT user_profiles_tenant_id_fkey       FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;
ALTER TABLE public.weekly_shipment     ADD CONSTRAINT weekly_shipment_tenant_id_fkey     FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;

-- ============================================================
-- S5 — tenants_slug_format_check
-- ============================================================

ALTER TABLE public.tenants
  ADD CONSTRAINT tenants_slug_format_check
  CHECK (slug ~ '^[a-z0-9][a-z0-9-]*[a-z0-9]$' OR slug ~ '^[a-z0-9]$');

-- ============================================================
-- S6 — Recreate admin_preorders (post-F49 staging shape)
-- ============================================================

DROP VIEW IF EXISTS public.admin_preorders;

CREATE VIEW public.admin_preorders WITH (security_invoker = true) AS
  SELECT
    p.id          AS preorder_id,
    p.tenant_id,
    p.created_at  AS reserved_at,
    p.quantity,
    p.notes       AS customer_notes,
    up.full_name  AS customer_name,
    c.distributor, c.item_code, c.title, c.series_name, c.publisher,
    c.format, c.issue_number, c.price_usd,
    c.price_usd * p.quantity AS line_total,
    c.foc_date, c.on_sale_date, c.catalog_month, c.cover_url
  FROM public.preorders p
    JOIN public.user_profiles up ON up.id = p.user_id
    JOIN public.catalog c        ON c.id = p.catalog_id
  ORDER BY up.full_name, c.on_sale_date;

REVOKE ALL ON public.admin_preorders FROM anon;
GRANT SELECT ON public.admin_preorders TO authenticated, service_role;

-- ============================================================
-- S7 — RLS recursion fix (7 policies -> is_admin())
-- PF5: all roles upgraded to authenticated (Option A); all with_check omitted (null)
-- ============================================================

-- 7.1 preorders / UPDATE
BEGIN;
DROP POLICY "admins update all preorders" ON public.preorders;
CREATE POLICY "admins update all preorders" ON public.preorders
  FOR UPDATE TO authenticated
  USING (is_admin());
COMMIT;

-- 7.2 reservation_history / SELECT
BEGIN;
DROP POLICY "admins view all history" ON public.reservation_history;
CREATE POLICY "admins view all history" ON public.reservation_history
  FOR SELECT TO authenticated
  USING (is_admin());
COMMIT;

-- 7.3 settings / UPDATE
BEGIN;
DROP POLICY "admins update settings" ON public.settings;
CREATE POLICY "admins update settings" ON public.settings
  FOR UPDATE TO authenticated
  USING (is_admin());
COMMIT;

-- 7.4 subscriptions / SELECT
BEGIN;
DROP POLICY "admins view all subscriptions" ON public.subscriptions;
CREATE POLICY "admins view all subscriptions" ON public.subscriptions
  FOR SELECT TO authenticated
  USING (is_admin());
COMMIT;

-- 7.5 usage_events / SELECT
BEGIN;
DROP POLICY "admins read all events" ON public.usage_events;
CREATE POLICY "admins read all events" ON public.usage_events
  FOR SELECT TO authenticated
  USING (is_admin());
COMMIT;

-- 7.6 user_profiles / DELETE
BEGIN;
DROP POLICY "admins delete profiles" ON public.user_profiles;
CREATE POLICY "admins delete profiles" ON public.user_profiles
  FOR DELETE TO authenticated
  USING (is_admin());
COMMIT;

-- 7.7 user_profiles / UPDATE
BEGIN;
DROP POLICY "admins update all profiles" ON public.user_profiles;
CREATE POLICY "admins update all profiles" ON public.user_profiles
  FOR UPDATE TO authenticated
  USING (is_admin());
COMMIT;
