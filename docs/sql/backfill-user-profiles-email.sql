-- ============================================================================
-- Backfill user_profiles.email from auth.users.email
-- Prepared 2026-08-10. Run: STAGING FIRST, then PRODUCTION.
-- Operator: Rick (Supabase SQL Editor).
--
-- WHY:
--   user_profiles.email is a DENORMALIZED COPY of auth.users.email, populated
--   at registration only and kept in sync by nothing (F25). Six of the 27
--   production profiles have it NULL while auth.users holds a perfectly good
--   address — Albert Abaunza, Alex Alvarez, Book Stop, Brian Moss, Mike
--   Neubauer, Rick Sedivec.
--
--   Spotted by Rick as an em-dash in the Accounts tab's Email column, which is
--   the cosmetic half. The half that matters:
--
--   * analytics.html builds the WIN-BACK EMAIL LIST as
--     `winbackRows.map(r => r.email).filter(Boolean)` — so those six are
--     SILENTLY DROPPED from it. A list missing six of twenty-seven customers,
--     with nothing on screen saying so.
--   * notify-customers is UNAFFECTED: it fetches addresses from auth.users
--     directly (index.ts:129), so customer notifications have always gone to
--     the right place. Only the profile copy was wrong.
--
-- WHAT THIS IS NOT:
--   A fix for F25. This repairs today's rows; it does not keep them in sync.
--   The durable fix is a trigger on auth.users UPDATE (or dropping the column
--   and joining), which stays open under F25. Expect drift to return the next
--   time a customer changes their auth email.
-- ============================================================================

-- ── PRE-FLIGHT: what will change, before changing it ────────────────────────
SELECT p.id, p.full_name, p.is_paper, u.email AS auth_email
FROM public.user_profiles p
JOIN auth.users u ON u.id = p.id
WHERE p.email IS NULL
  AND u.email IS NOT NULL
ORDER BY p.full_name;
-- EXPECTED on production 2026-08-10: 6 rows, all is_paper = false.
-- If the count is wildly different, STOP and re-measure before writing.


-- ── THE BACKFILL ────────────────────────────────────────────────────────────
-- Only fills NULLs. Never overwrites an existing value, so a profile email
-- that has legitimately diverged is left alone for a human to judge rather
-- than silently reconciled.
UPDATE public.user_profiles p
SET    email = u.email
FROM   auth.users u
WHERE  u.id = p.id
  AND  p.email IS NULL
  AND  u.email IS NOT NULL;


-- ── VERIFY: none left, and nothing was clobbered ────────────────────────────
SELECT
  count(*) FILTER (WHERE email IS NULL)                        AS still_null,
  count(*) FILTER (WHERE email IS NOT NULL)                    AS have_email,
  count(*)                                                     AS total
FROM public.user_profiles;
-- EXPECTED on production: still_null = 0, total unchanged at 27.

-- And confirm the copy now agrees with the source everywhere it exists:
SELECT count(*) AS mismatched
FROM public.user_profiles p
JOIN auth.users u ON u.id = p.id
WHERE p.email IS DISTINCT FROM u.email;
-- EXPECTED: 0. A non-zero result here is pre-existing F25 drift, NOT caused by
-- this backfill (which only touched NULLs) — investigate before "fixing" it.


-- ── ROLLBACK ────────────────────────────────────────────────────────────────
-- There is no clean automatic rollback: the previous value was NULL, and
-- setting it back would re-break the analytics list. If this needs undoing,
-- undo it for named rows deliberately:
--   UPDATE public.user_profiles SET email = NULL WHERE id IN (...);
