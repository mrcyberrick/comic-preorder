-- STATUS: staging=APPLIED 2026-11-10 | prod=APPLIED 2026-11-10
--         STAGING: applied by Rick 2026-11-10; his pasted verdict read 'OK - columns present and
--         readable, 1 definition, SECURITY DEFINER, search_path pinned, S1 body, authenticated only'.
--         Behaviour checked the same day by playwright/store-contact-verify.mjs (local-only): anon
--         refused (401), signed-in non-admin refused (403, 42501), admin write read back, another
--         shop's row untouched, over-cap value refused (22001).
--         PRODUCTION: applied by Rick 2026-11-10, before the settings.html promotion. A names check
--         run first already read both columns and the function as present (so the file had run
--         before that check); the verdict query alone, run afterwards, read the same OK string as
--         staging. Anonymous probe the same day: the function exists with this four-argument
--         signature and anon is refused by the grant ('permission denied for function', 401).
--         Production rows at that time: rjbookstop contact_phone and location both null.
-- (F105) This line is the applied-state record. Update it the moment you run this file, with the REAL
-- state and no qualifier the regex cannot see: /promote-prod step 0 matches prod=(APPLIED|N/A).
-- ============================================================================
-- Store contact details: tenants.postal_address, tenants.website, and
-- admin_set_store_contact(p_phone, p_postal_address, p_town, p_website) -> void
--
-- Plan: docs/store-contact-and-colors.md, step S1. Prepared 2026-11-10.
-- Run: STAGING FIRST. Operator: Rick (Supabase SQL Editor). Paste the WHOLE file
-- and press Run once: the Editor shows only the LAST statement's result, so the
-- file ends with ONE verdict row that covers everything above it.
-- Production BEFORE the settings.html panel reaches it (F105): the panel reads the
-- two new columns and calls the function.
--
-- WHY: the shop's phone, street address, town and website are hardcoded to
--   Ray & Judy's in six mail functions and about 20 page and print spots, and no
--   screen can set them. This adds the two missing columns and the one write
--   path the Settings ▸ Store contact panel uses. Nothing READS the new columns
--   until steps S2 (mail) and S3 (pages); the existing columns contact_phone and
--   location are already read by notify-customers (location, free shops only).
--
-- WHAT THE FUNCTION DOES: updates exactly four columns (contact_phone,
--   postal_address, location, website) plus updated_at, on the caller's OWN shop
--   only. The shop is derived from current_tenant_id() inside the function, never
--   from a parameter. Blank or whitespace-only input stores NULL.
-- WHAT IT REFUSES (raises; nothing written): not a signed-in admin (42501); any
--   value over its length cap (22001).
-- WHAT IT CANNOT TOUCH: plan, slug, display_name, branding, settings, or any
--   other shop's row.
-- ============================================================================

BEGIN;

ALTER TABLE public.tenants
  ADD COLUMN IF NOT EXISTS postal_address text,
  ADD COLUMN IF NOT EXISTS website        text;

-- Readable by a signed-in user of the shop (RLS still limits them to their own
-- row). Redundant if authenticated already holds table-level SELECT on tenants;
-- needed if tenants' SELECT is column-level. These are public business details.
GRANT SELECT (postal_address, website) ON public.tenants TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_set_store_contact(
  p_phone          text,
  p_postal_address text,
  p_town           text,
  p_website        text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tenant uuid := public.current_tenant_id();
BEGIN
  -- store-contact S1 (docs/store-contact-and-colors.md)
  IF v_tenant IS NULL OR NOT public.current_user_is_admin() THEN
    RAISE EXCEPTION 'Only a signed-in admin can change the store contact details' USING ERRCODE = '42501';
  END IF;
  IF length(coalesce(p_phone, '')) > 40
     OR length(coalesce(p_postal_address, '')) > 200
     OR length(coalesce(p_town, '')) > 80
     OR length(coalesce(p_website, '')) > 120 THEN
    RAISE EXCEPTION 'A value is too long (phone 40, address 200, town 80, website 120 characters)' USING ERRCODE = '22001';
  END IF;

  UPDATE public.tenants SET
    contact_phone  = NULLIF(btrim(p_phone), ''),
    postal_address = NULLIF(btrim(p_postal_address), ''),
    location       = NULLIF(btrim(p_town), ''),
    website        = NULLIF(btrim(p_website), ''),
    updated_at     = now()
  WHERE id = v_tenant;
END
$$;

REVOKE ALL ON FUNCTION public.admin_set_store_contact(text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_store_contact(text, text, text, text) TO authenticated;

COMMIT;


-- ── VERDICT (the one result to paste back) ──────────────────────────────────
-- One aggregate row, so a missing function or column cannot read as
-- "Success. No rows returned". Checks: both columns exist; authenticated can
-- SELECT them; exactly one definition; SECURITY DEFINER; search_path pinned;
-- this body (marker); authenticated can EXECUTE; anon and PUBLIC cannot.
--
-- EXPECTED: verdict = 'OK - columns present and readable, 1 definition, SECURITY DEFINER, search_path pinned, S1 body, authenticated only'
WITH f AS (
  SELECT p.oid, p.prosecdef, p.proconfig, p.prosrc
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'admin_set_store_contact'
), c AS (
  SELECT count(*) AS n FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'tenants'
    AND column_name IN ('postal_address', 'website')
), g AS (
  SELECT
    count(*) FILTER (WHERE grantee = 'authenticated')     AS auth_n,
    count(*) FILTER (WHERE grantee IN ('anon', 'PUBLIC')) AS open_n
  FROM information_schema.routine_privileges
  WHERE routine_schema = 'public' AND routine_name = 'admin_set_store_contact'
)
SELECT
  CASE
    WHEN (SELECT n FROM c) <> 2 THEN 'PROBLEM - expected 2 new columns, found ' || (SELECT n FROM c) || '. Re-run this file from the top.'
    WHEN NOT has_column_privilege('authenticated', 'public.tenants', 'postal_address', 'SELECT')
      OR NOT has_column_privilege('authenticated', 'public.tenants', 'website', 'SELECT')
      THEN 'PROBLEM - authenticated cannot SELECT the new columns'
    WHEN (SELECT count(*) FROM f) = 0 THEN 'MISSING - the function was not created. Re-run this file from the top.'
    WHEN (SELECT count(*) FROM f) > 1 THEN 'PROBLEM - ' || (SELECT count(*) FROM f) || ' definitions exist; a stray overload was left behind'
    WHEN (SELECT bool_and(prosecdef) FROM f) IS NOT TRUE THEN 'PROBLEM - not SECURITY DEFINER'
    WHEN (SELECT bool_and(array_to_string(proconfig, ',') LIKE '%search_path%') FROM f) IS NOT TRUE
      THEN 'PROBLEM - search_path is not pinned'
    WHEN (SELECT bool_and(prosrc LIKE '%store-contact S1%') FROM f) IS NOT TRUE
      THEN 'PROBLEM - body is not the S1 version. Re-run this file from the top.'
    WHEN (SELECT auth_n FROM g) = 0 THEN 'PROBLEM - authenticated has no EXECUTE; the GRANT did not run'
    WHEN (SELECT open_n FROM g) > 0 THEN 'PROBLEM - anon or PUBLIC can execute this (F124 violation)'
    ELSE 'OK - columns present and readable, 1 definition, SECURITY DEFINER, search_path pinned, S1 body, authenticated only'
  END AS verdict;


-- ── SMOKE ───────────────────────────────────────────────────────────────────
-- Not runnable here: the Editor runs as postgres, auth.uid() is NULL, so the
-- function refuses. Behavioural checks run as real signed-in users outside the
-- Editor: playwright/store-contact-verify.mjs (local-only) -- anon refused, a
-- signed-in non-admin refused, an admin's save read back, another shop's row
-- untouched, teardown re-read.


-- ── ROLLBACK ────────────────────────────────────────────────────────────────
-- Safe at any time before S2/S3 ship (nothing else reads the new columns):
-- DROP FUNCTION IF EXISTS public.admin_set_store_contact(text, text, text, text);
-- ALTER TABLE public.tenants DROP COLUMN IF EXISTS postal_address, DROP COLUMN IF EXISTS website;
-- After S2/S3 ship, drop only the function; the columns are then read.
