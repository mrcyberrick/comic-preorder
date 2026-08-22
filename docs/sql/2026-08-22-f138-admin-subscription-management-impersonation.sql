-- STATUS: COMPLETE | staging=APPLIED 2026-08-22 | prod=APPLIED 2026-08-22 | findings=F138 (reverses F128)
--
-- F138: grant admins write access to `subscriptions` so impersonation can
-- fully manage a customer's subscriptions (subscribe + unsubscribe).
--
-- F128 (2026-08-10) deliberately left `subscriptions` with NO admin write
-- policy — Rick's call at the time was "no" and the doc said "do not add
-- an admin write policy to subscriptions later." Rick requested the
-- reversal 2026-08-22: admin impersonation should manage a customer's
-- subscriptions the same way it already manages their preorders.
--
-- This mirrors the existing `admins manage tenant preorders` ALL policy
-- (current_user_is_admin() AND tenant_id = current_tenant_id(), identical
-- predicate for USING and WITH CHECK) and consolidates the current
-- SELECT-only `admins view tenant subscriptions` PERMISSIVE policy into one
-- ALL policy, so `subscriptions` keeps the same 4-policy shape as
-- `preorders` (1 user ALL + 1 admin ALL + 2 F127 RESTRICTIVE) instead of
-- carrying two overlapping admin PERMISSIVE policies.
--
-- Run on STAGING first. Do not run on production until staging V1-V4 in
-- docs/technical-reference.md § 13 F138 are green and Rick confirms
-- promotion via /promote-prod.

-- =====================================================================
-- PRE-FLIGHT (read-only) — confirm current policy shape before changing
-- it, and capture preorders' admin-policy role list so the new policy's
-- TO clause matches it exactly instead of guessing {public} vs
-- {authenticated}.
-- =====================================================================
SELECT tablename, policyname, permissive, roles, cmd, qual, with_check
FROM   pg_policies
WHERE  schemaname = 'public'
  AND  tablename IN ('preorders', 'subscriptions')
ORDER  BY tablename, policyname;

-- STOP AND COMPARE before proceeding:
--   - subscriptions should show exactly 4 rows: 'users manage own
--     subscriptions' (ALL), 'admins view tenant subscriptions' (SELECT),
--     'blocked accounts cannot create subscriptions' (RESTRICTIVE INSERT),
--     'blocked accounts cannot change subscriptions' (RESTRICTIVE UPDATE).
--     If this doesn't match, STOP — technical-reference.md § 7.1 is stale
--     against live and this migration's assumptions may not hold.
--   - Note the `roles` value on preorders' 'admins manage tenant
--     preorders'. If it is not {authenticated}, edit the TO clause in the
--     CREATE POLICY below to match before running it.

-- =====================================================================
-- MIGRATION
-- =====================================================================
BEGIN;

DROP POLICY "admins view tenant subscriptions" ON subscriptions;

CREATE POLICY "admins manage tenant subscriptions"
  ON subscriptions
  FOR ALL
  TO authenticated
  USING (current_user_is_admin() AND tenant_id = current_tenant_id())
  WITH CHECK (current_user_is_admin() AND tenant_id = current_tenant_id());

COMMIT;

-- =====================================================================
-- POST-CHECK (read-only) — must show exactly 4 policies again, with
-- 'admins manage tenant subscriptions' (ALL) replacing the old SELECT-only
-- one. Check policyname and cmd, not just row count — a check whose output
-- can't distinguish success from failure is not a verification step
-- (CLAUDE.md).
-- =====================================================================
SELECT tablename, policyname, permissive, roles, cmd
FROM   pg_policies
WHERE  schemaname = 'public'
  AND  tablename = 'subscriptions'
ORDER  BY policyname;
-- EXPECTED (4 rows):
--   admins manage tenant subscriptions           | PERMISSIVE  | ALL
--   blocked accounts cannot change subscriptions | RESTRICTIVE | UPDATE
--   blocked accounts cannot create subscriptions | RESTRICTIVE | INSERT
--   users manage own subscriptions                | PERMISSIVE  | ALL
-- FAILURE: 'admins view tenant subscriptions' still present, or the new
-- policy absent/misnamed — the transaction did not land as expected.

-- =====================================================================
-- FUNCTIONAL CHECK (optional, requires a real admin session + impersonated
-- customer — cannot be simulated from the SQL Editor since it runs as the
-- `postgres` superuser and bypasses RLS entirely). Do this from the app:
-- impersonate a customer on subscriptions.html, subscribe to a series,
-- confirm the row lands with the CUSTOMER's user_id (not the admin's), then
-- unsubscribe and confirm the row is actually gone (not a silent no-op —
-- the exact failure mode F128 fixed for unsubscribe alone).
-- =====================================================================
