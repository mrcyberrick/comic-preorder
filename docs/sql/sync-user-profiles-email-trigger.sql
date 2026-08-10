-- ============================================================================
-- Keep user_profiles.email in sync with auth.users.email  (F25, durable half)
-- Prepared 2026-08-10. Run: STAGING FIRST, then PRODUCTION.
-- Operator: Rick (Supabase SQL Editor).
--
-- RUN THE BACKFILL FIRST — docs/sql/backfill-user-profiles-email.sql.
-- This trigger only fires on future changes; it does not repair existing rows.
--
-- WHY:
--   F25 has specified this fix since it was filed: "add a trigger on auth.users
--   UPDATE that syncs to user_profiles.email". The backfill repairs today's six
--   rows; without this, drift returns the next time a customer changes their
--   address, and the analytics win-back list starts silently dropping people
--   again (see F25's table).
--
-- ── ONE DECISION IS BAKED IN HERE, AND IT IS RICK'S TO OVERRULE ─────────────
--   This trigger does NOT swallow errors. If the sync fails, the auth.users
--   UPDATE fails with it, and the customer's email change is refused.
--
--   The alternative — EXCEPTION WHEN OTHERS THEN RETURN NEW — keeps the auth
--   path bulletproof but re-creates the exact failure mode being fixed: the
--   copy drifts and nothing says so. That is the F96/F115 shape, and it is what
--   this finding is about.
--
--   Judgement: a refused email change is RARE, VISIBLE and RECOVERABLE. Silent
--   drift is none of those. If a failing trigger ever does block a customer,
--   drop it (see ROLLBACK) and we fix the cause rather than hide it.
--
-- NOTE ON auth SCHEMA TRIGGERS: this is a documented Supabase pattern, but the
--   auth schema is platform-managed. If a Supabase upgrade ever removes it,
--   the symptom is silent — F25 simply reopens. Re-check the trigger exists
--   (VERIFY 1) if profile emails start going stale again.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.sync_user_profile_email()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- No-op when the profile row does not exist yet: auth.users is created
  -- before user_profiles by every signup path, so an UPDATE matching zero
  -- rows is normal and must not raise.
  UPDATE public.user_profiles
  SET    email = NEW.email
  WHERE  id = NEW.id;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.sync_user_profile_email() FROM PUBLIC, anon, authenticated;
-- F124: Supabase's default privileges GRANT EXECUTE to anon and authenticated
-- on every new function in public, and REVOKE ... FROM PUBLIC does not remove
-- them. Nothing should call this directly — only the trigger fires it.

DROP TRIGGER IF EXISTS sync_profile_email ON auth.users;

CREATE TRIGGER sync_profile_email
AFTER UPDATE OF email ON auth.users
FOR EACH ROW
WHEN (OLD.email IS DISTINCT FROM NEW.email)
EXECUTE FUNCTION public.sync_user_profile_email();
-- UPDATE only, not INSERT: every signup path (register-customer,
-- invite-customer, create-paper-customer) writes the profile WITH its email
-- immediately after creating the auth user, and at INSERT time the profile row
-- does not exist yet. The gap this closes is CHANGES, not creations.


-- ── VERIFY 1: the trigger exists and is enabled ─────────────────────────────
SELECT tgname,
       tgenabled,                       -- 'O' = enabled
       pg_get_triggerdef(oid) AS def
FROM pg_trigger
WHERE tgname = 'sync_profile_email';
-- EXPECTED: one row, tgenabled = 'O'.
-- ZERO ROWS means the CREATE did not take — do not move on.


-- ── VERIFY 2: it actually syncs. THIS IS THE ONE THAT MATTERS ───────────────
-- Reading the trigger definition proves it exists, not that it works — the
-- same trap that cost three round-trips on get_account_activity, where a
-- correct-looking signature hid an open gate. So change an address and look.
--
-- Pick a disposable STAGING user first. Replace the email below with a real
-- one from: SELECT id, email FROM auth.users ORDER BY created_at DESC LIMIT 5;
--
--   -- before
--   SELECT u.email AS auth_email, p.email AS profile_email
--   FROM auth.users u JOIN public.user_profiles p ON p.id = u.id
--   WHERE u.email = '<disposable@example.test>';
--
--   UPDATE auth.users SET email = '<disposable+sync@example.test>'
--   WHERE email = '<disposable@example.test>';
--
--   -- after: both columns must show the NEW address
--   SELECT u.email AS auth_email, p.email AS profile_email
--   FROM auth.users u JOIN public.user_profiles p ON p.id = u.id
--   WHERE u.email = '<disposable+sync@example.test>';
--
-- EXPECTED: auth_email = profile_email = the new address.
-- If profile_email still shows the old one, the trigger is not firing.
--
-- DO NOT run this probe against a real customer on production.


-- ── VERIFY 3: no drift remains ──────────────────────────────────────────────
SELECT count(*) AS mismatched
FROM public.user_profiles p
JOIN auth.users u ON u.id = p.id
WHERE p.email IS DISTINCT FROM u.email;
-- EXPECTED: 0, once the backfill has also been run.


-- ── ROLLBACK ────────────────────────────────────────────────────────────────
--   DROP TRIGGER IF EXISTS sync_profile_email ON auth.users;
--   DROP FUNCTION IF EXISTS public.sync_user_profile_email();
-- Dropping the trigger cannot lose data — it only stops future syncing, which
-- returns the system to exactly the F25 state it is in today.
