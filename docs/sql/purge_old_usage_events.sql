-- STATUS: staging=APPLIED | prod=APPLIED  (verified 2026-08-11)
--         Phase 3.5 era; the applied state was unverified until now. The
--         function is PRESENT on both environments -- read from each project's
--         PostgREST OpenAPI spec (`/rpc/purge_old_usage_events`), which lists
--         it WITHOUT invoking it. Deliberate: calling it would delete rows,
--         so existence was established from the spec rather than by running it.
--
--         RETENTION EVIDENCE, and the two environments do NOT agree:
--           production  1,448 rows, 0 older than 90 days  -> purge is running
--           staging     4,801 rows, 61 older than 90 days -> it is NOT
--         So the function being deployed does not mean it is being INVOKED.
--         Production is healthy and is what matters; staging's 61 stale rows
--         are analytics-only, on the environment nobody reports from, and are
--         recorded here rather than filed as a finding.
--
--         Note the distinction this line now makes: "APPLIED" means the DDL
--         exists, NOT that anything schedules it. Related: F90 (the 90-day
--         purge forecloses adoption-trend analytics -- production's 0 confirms
--         the purge really is destroying that history on schedule).
-- (F105) This line is the applied-state record. A gate that lives only in
-- prose gets missed -- F6 sat unapplied on production for 13 days because
-- nothing machine-readable said so. Update it the moment you run this file.
-- Phase 3.5 — per-tenant retention purge for usage_events.
-- Hard-deletes rows older than p_retention_days for the given tenant.
-- Returns the count of deleted rows.
-- Called by import-staging.js at the end of each weekly run.
--
-- SECURITY DEFINER is required: usage_events has no DELETE RLS policy
-- (the table is append-only by design). A named DEFINER function is
-- the controlled, auditable DELETE path, matching the pattern used by
-- purge_stale_catalog and archive_stale_reservations.

CREATE OR REPLACE FUNCTION public.purge_old_usage_events(
  p_tenant_id      uuid,
  p_retention_days integer
)
RETURNS integer
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH deleted AS (
    DELETE FROM public.usage_events
    WHERE tenant_id  = p_tenant_id
      AND created_at < now() - make_interval(days => p_retention_days)
    RETURNING 1
  )
  SELECT count(*)::integer FROM deleted;
$$;

REVOKE ALL ON FUNCTION public.purge_old_usage_events(uuid, integer) FROM PUBLIC;
-- Supabase auto-grants EXECUTE to anon and authenticated on function creation;
-- revoke them explicitly so only the service-role import path can call this.
REVOKE EXECUTE ON FUNCTION public.purge_old_usage_events(uuid, integer) FROM anon;
REVOKE EXECUTE ON FUNCTION public.purge_old_usage_events(uuid, integer) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.purge_old_usage_events(uuid, integer) TO service_role;
