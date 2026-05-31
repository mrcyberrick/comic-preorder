-- Phase 4.4 migration artifact
-- Applied to production via Supabase SQL Editor (Rick-in-the-loop), 2026-05-31
-- Blocks appended in execution order: Step 1 → Step 2 → Step 3 → Step 4 → Step 5 → Step 6 → Step 7
-- Held on feat/phase-4-prod-cutover — not pushed to origin/main until the 4.6 PR.
-- Rollback SQL: docs/phase-4.4-runbook.md Appendix R

-- =============================================================================
-- Step 1: Helper functions
-- =============================================================================

CREATE OR REPLACE FUNCTION public.current_tenant_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT tenant_id FROM user_profiles WHERE id = auth.uid()
$function$;

CREATE OR REPLACE FUNCTION public.current_user_is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(is_admin, false)
  FROM user_profiles
  WHERE id = auth.uid()
$function$;

-- =============================================================================
-- Step 2: Migrate 3 catalog/reservation functions (DROP old 2-arg + CREATE 3-arg)
-- =============================================================================

DROP FUNCTION IF EXISTS public.archive_stale_reservations(date, text);
CREATE OR REPLACE FUNCTION public.archive_stale_reservations(p_tenant_id uuid, cutoff_date date, current_month text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE archived_count integer;
BEGIN
  INSERT INTO reservation_history (
    tenant_id, user_id, series_name, publisher, distributor, title, catalog_month, on_sale_date
  )
  SELECT DISTINCT ON (p.user_id, c.series_name, c.distributor, c.catalog_month)
    p_tenant_id, p.user_id, c.series_name, c.publisher, c.distributor, c.title, c.catalog_month, c.on_sale_date
  FROM preorders p
  JOIN catalog c ON c.id = p.catalog_id
  WHERE p.tenant_id = p_tenant_id
    AND c.catalog_month != current_month
    AND c.on_sale_date < cutoff_date
    AND c.series_name IS NOT NULL
  ORDER BY p.user_id, c.series_name, c.distributor, c.catalog_month
  ON CONFLICT (user_id, series_name, distributor, catalog_month) DO NOTHING;
  GET DIAGNOSTICS archived_count = ROW_COUNT;
  RETURN archived_count;
END;
$function$;

DROP FUNCTION IF EXISTS public.delete_dropped_catalog_items(text, text[]);
CREATE OR REPLACE FUNCTION public.delete_dropped_catalog_items(p_tenant_id uuid, p_catalog_month text, p_item_codes text[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE deleted_count integer;
BEGIN
  DELETE FROM catalog
  WHERE tenant_id = p_tenant_id
    AND catalog_month = p_catalog_month
    AND item_code != ALL(p_item_codes);
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$function$;

DROP FUNCTION IF EXISTS public.purge_stale_catalog(date, text);
CREATE OR REPLACE FUNCTION public.purge_stale_catalog(p_tenant_id uuid, cutoff_date date, current_month text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE deleted_count integer;
BEGIN
  DELETE FROM catalog
  WHERE tenant_id = p_tenant_id
    AND catalog_month != current_month
    AND on_sale_date < cutoff_date
    AND id NOT IN (
      SELECT DISTINCT catalog_id FROM preorders WHERE tenant_id = p_tenant_id
    );
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$function$;

-- =============================================================================
-- Step 3: Two new functions + service_role-only grant on auto_fulfill_past_on_sale
-- =============================================================================

CREATE OR REPLACE FUNCTION public.purge_old_usage_events(p_tenant_id uuid, p_retention_days integer)
 RETURNS integer
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH deleted AS (
    DELETE FROM public.usage_events
    WHERE tenant_id  = p_tenant_id
      AND created_at < now() - make_interval(days => p_retention_days)
    RETURNING 1
  )
  SELECT count(*)::integer FROM deleted;
$function$;

CREATE OR REPLACE FUNCTION public.auto_fulfill_past_on_sale(p_tenant_id uuid)
 RETURNS integer
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH updated AS (
    UPDATE preorders p
       SET fulfilled    = true,
           fulfilled_at = now()
      FROM catalog c
     WHERE p.catalog_id = c.id
       AND p.tenant_id  = p_tenant_id
       AND p.fulfilled  = false
       AND c.on_sale_date < CURRENT_DATE
     RETURNING p.id
  )
  SELECT COUNT(*)::integer FROM updated;
$function$;

-- Supabase auto-grants anon+authenticated on new functions; revoke all three to isolate to service_role.
REVOKE EXECUTE ON FUNCTION public.auto_fulfill_past_on_sale(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.auto_fulfill_past_on_sale(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.auto_fulfill_past_on_sale(uuid) FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.auto_fulfill_past_on_sale(uuid) TO service_role;

-- =============================================================================
-- Step 4: F20 — tenant-filter get_popular_series (signature unchanged, OR REPLACE)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_popular_series(p_catalog_month text)
 RETURNS TABLE(series_name text, distributor text, reservation_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT
    c.series_name,
    c.distributor,
    COUNT(*)::bigint AS reservation_count
  FROM preorders p
  JOIN catalog c ON c.id = p.catalog_id
  WHERE c.catalog_month = p_catalog_month
    AND c.series_name IS NOT NULL
    AND c.tenant_id = current_tenant_id()
  GROUP BY c.series_name, c.distributor
  ORDER BY reservation_count DESC;
$function$;

-- =============================================================================
-- Step 5: RLS rewrite — all tenant-scoped tables (Decision A: normalize to authenticated)
-- Decision B: catalog read-only (no admin-write); user_profiles retains admins manage (F58)
-- Fixes: F15 (weekly_shipment qual true→tenant), F16 (preorders OR→split)
-- =============================================================================

-- ===== app_settings =====
DROP POLICY IF EXISTS "Admins can insert settings"   ON app_settings;
DROP POLICY IF EXISTS "Admins can update settings"   ON app_settings;
DROP POLICY IF EXISTS "Anyone can read settings"     ON app_settings;
CREATE POLICY "users read tenant app_settings"    ON app_settings FOR SELECT TO authenticated
  USING (tenant_id = current_tenant_id());
CREATE POLICY "admins insert tenant app_settings" ON app_settings FOR INSERT TO authenticated
  WITH CHECK ((tenant_id = current_tenant_id()) AND current_user_is_admin());
CREATE POLICY "admins update tenant app_settings" ON app_settings FOR UPDATE TO authenticated
  USING ((tenant_id = current_tenant_id()) AND current_user_is_admin());
CREATE POLICY "admins delete tenant app_settings" ON app_settings FOR DELETE TO authenticated
  USING ((tenant_id = current_tenant_id()) AND current_user_is_admin());

-- ===== catalog =====
DROP POLICY IF EXISTS "Admins can modify catalog"          ON catalog;
DROP POLICY IF EXISTS "Logged in users can view catalog"   ON catalog;
CREATE POLICY "users read tenant catalog" ON catalog FOR SELECT TO authenticated
  USING (tenant_id = current_tenant_id());

-- ===== preorders ===== (F16: collapse OR-pattern into split policies)
DROP POLICY IF EXISTS "Admins can view all preorders"   ON preorders;
DROP POLICY IF EXISTS "Users can manage own preorders"  ON preorders;
DROP POLICY IF EXISTS "admins update all preorders"     ON preorders;
CREATE POLICY "users manage own preorders" ON preorders FOR ALL TO authenticated
  USING ((auth.uid() = user_id) AND (tenant_id = current_tenant_id()));
CREATE POLICY "admins manage tenant preorders" ON preorders FOR ALL TO authenticated
  USING (current_user_is_admin() AND (tenant_id = current_tenant_id()))
  WITH CHECK (current_user_is_admin() AND (tenant_id = current_tenant_id()));

-- ===== reservation_history =====
DROP POLICY IF EXISTS "admins view all history" ON reservation_history;
DROP POLICY IF EXISTS "users view own history"  ON reservation_history;
CREATE POLICY "users view own history" ON reservation_history FOR SELECT TO authenticated
  USING ((auth.uid() = user_id) AND (tenant_id = current_tenant_id()));
CREATE POLICY "admins view all history" ON reservation_history FOR SELECT TO authenticated
  USING (current_user_is_admin() AND (tenant_id = current_tenant_id()));

-- ===== settings ===== (legacy table, empty per F4 — policies rewritten for parity)
DROP POLICY IF EXISTS "admins update settings"            ON settings;
DROP POLICY IF EXISTS "authenticated users read settings" ON settings;
CREATE POLICY "users read tenant settings" ON settings FOR SELECT TO authenticated
  USING (tenant_id = current_tenant_id());
CREATE POLICY "admins update tenant settings" ON settings FOR UPDATE TO authenticated
  USING ((tenant_id = current_tenant_id()) AND current_user_is_admin());

-- ===== subscriptions =====
DROP POLICY IF EXISTS "admins view all subscriptions"   ON subscriptions;
DROP POLICY IF EXISTS "users manage own subscriptions"  ON subscriptions;
CREATE POLICY "users manage own subscriptions" ON subscriptions FOR ALL TO authenticated
  USING ((auth.uid() = user_id) AND (tenant_id = current_tenant_id()));
CREATE POLICY "admins view tenant subscriptions" ON subscriptions FOR SELECT TO authenticated
  USING ((tenant_id = current_tenant_id()) AND current_user_is_admin());

-- ===== tenants ===== (prod had NO policies — enable RLS, add 2)
ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users read own tenant" ON tenants FOR SELECT TO authenticated
  USING (id = current_tenant_id());
CREATE POLICY "admins update own tenant" ON tenants FOR UPDATE TO authenticated
  USING ((id = current_tenant_id()) AND current_user_is_admin());

-- ===== usage_events =====
DROP POLICY IF EXISTS "admins read all events"      ON usage_events;
DROP POLICY IF EXISTS "users insert own events"     ON usage_events;
CREATE POLICY "users insert own usage events" ON usage_events FOR INSERT TO authenticated
  WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY "admins read tenant usage events" ON usage_events FOR SELECT TO authenticated
  USING ((tenant_id = current_tenant_id()) AND current_user_is_admin());

-- ===== user_profiles =====
DROP POLICY IF EXISTS "Admins can manage profiles"     ON user_profiles;
DROP POLICY IF EXISTS "Admins can view all profiles"   ON user_profiles;
DROP POLICY IF EXISTS "Users can view own profile"     ON user_profiles;
DROP POLICY IF EXISTS "admins delete profiles"         ON user_profiles;
DROP POLICY IF EXISTS "admins update all profiles"     ON user_profiles;
CREATE POLICY "users view own profile" ON user_profiles FOR SELECT TO authenticated
  USING ((auth.uid() = id) AND (tenant_id = current_tenant_id()));
CREATE POLICY "users update own profile" ON user_profiles FOR UPDATE TO authenticated
  USING (auth.uid() = id);
CREATE POLICY "admins view tenant profiles" ON user_profiles FOR SELECT TO authenticated
  USING ((tenant_id = current_tenant_id()) AND current_user_is_admin());
-- DECISION B: retain admin-write (intentional prod divergence — F58)
-- Users.suspend (app.js UPDATE) and Users.deleteProfile (admin.html DELETE) run via
-- the authenticated client; dropping this breaks the admin Users tab.
CREATE POLICY "admins manage tenant profiles" ON user_profiles FOR ALL TO authenticated
  USING ((tenant_id = current_tenant_id()) AND current_user_is_admin())
  WITH CHECK ((tenant_id = current_tenant_id()) AND current_user_is_admin());

-- ===== weekly_shipment ===== (F15: qual was `true`)
DROP POLICY IF EXISTS "authenticated users read weekly_shipment" ON weekly_shipment;
CREATE POLICY "authenticated users read weekly_shipment" ON weekly_shipment FOR SELECT TO authenticated
  USING (tenant_id = current_tenant_id());

-- =============================================================================
-- Step 6: Default-removal verify (Phase 3.3, no-op — prod had zero tenant_id defaults)
-- =============================================================================
-- SELECT table_name, column_default FROM information_schema.columns
-- WHERE column_name='tenant_id' AND table_schema='public' AND column_default IS NOT NULL;
-- Result: no rows (confirmed 2026-05-31)

-- =============================================================================
-- Step 7: Tenant-isolation smoke gate (verified 2026-05-31)
-- =============================================================================
-- postgres context: catalog count=6399, tenant_count_visible=1, purge_old_usage_events()=0
-- get_popular_series() executed without error.
-- SET LOCAL role authenticated smoke did not resolve auth.uid() in SQL Editor (known
-- Supabase limitation). Authenticated-path tagged as 4.6 hard gate: admin UI login
-- before first prod import write confirms current_tenant_id() resolves for real JWTs.
-- Step 3 deviation: Supabase auto-granted anon+authenticated EXECUTE on
-- auto_fulfill_past_on_sale; required explicit REVOKE for both (added to Step 3 above).


