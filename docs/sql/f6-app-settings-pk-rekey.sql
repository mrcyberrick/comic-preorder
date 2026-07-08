-- ============================================================================
-- F6 — re-key app_settings PK from (key) to (tenant_id, key)
-- Prepared 2026-07-08 (from the 2026-07-07 architecture review).
-- Run: STAGING first, verify, then PRODUCTION as part of 5.5 pre-flight.
-- Operator: Rick (Supabase SQL Editor, runs as postgres superuser).
--
-- WHY THIS MUST LAND BEFORE TENANT 2:
--   With PK on (key) alone, a second tenant cannot hold its own
--   'maintenance_mode' or 'order_deadline' row — the INSERT collides with the
--   founding tenant's row. Settings.set() in app.js upserts on the PK, so
--   after this re-key each tenant upserts its own (tenant_id, key) row and
--   RLS scoping continues to return exactly one row per tenant to
--   Settings.get().
--
-- App compatibility (verified against app.js 2026-07-08):
--   - Settings.get(): .eq('key', k).single() — RLS already scopes to the
--     caller's tenant, so one row per tenant is returned. Unchanged.
--   - Settings.set(): .upsert({key, value, updated_at, tenant_id}) with no
--     explicit onConflict — PostgREST resolves conflicts on the PRIMARY KEY,
--     which becomes (tenant_id, key). Payload carries both columns. Unchanged.
--   - notify-customers EF reads order_deadline filtered by tenant. Unchanged.
-- ============================================================================

-- Pre-check: current PK shape and row inventory (expect PK on key alone,
-- and one tenant_id across all rows until tenant 2 exists)
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'public.app_settings'::regclass AND contype = 'p';

SELECT tenant_id, key FROM public.app_settings ORDER BY tenant_id, key;

-- Re-key (single transaction)
BEGIN;
ALTER TABLE public.app_settings
  DROP CONSTRAINT app_settings_pkey;
ALTER TABLE public.app_settings
  ADD CONSTRAINT app_settings_pkey PRIMARY KEY (tenant_id, key);
COMMIT;

-- Verify: PK is now (tenant_id, key)
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'public.app_settings'::regclass AND contype = 'p';
-- Expected: PRIMARY KEY (tenant_id, key)

-- Post-DDL smoke (staging): flip maintenance_mode ON and OFF from the admin
-- panel and confirm the catalog banner reads the order_deadline — this
-- exercises Settings.set() upsert + Settings.get() through the new PK.

-- ----------------------------------------------------------------------------
-- OPTIONAL (separate decision, do NOT bundle into the transaction above):
--
-- 1. idx_app_settings_tenant is now redundant — the new PK's leading column
--    is tenant_id and serves the same lookups:
--      DROP INDEX IF EXISTS public.idx_app_settings_tenant;
--
-- 2. The legacy `settings` table (empty since F4 prod resolution 2026-05-31)
--    has the same F6 PK shape but no remaining callers. Dropping it closes
--    the F4 dead-code remnant instead of re-keying a dead table:
--      -- confirm zero rows and zero grants in use first:
--      SELECT COUNT(*) FROM public.settings;
--      DROP TABLE public.settings;
-- ----------------------------------------------------------------------------
