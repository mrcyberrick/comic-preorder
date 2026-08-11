-- STATUS: staging=N/A | prod=PENDING
--         PART A drops a PRODUCTION-ONLY function (staging dropped it 2026-05-26, F19).
--         PARTS B and C are READ-ONLY and safe to run anywhere, any time.
-- (F105) This line is the applied-state record. A gate that lives only in
-- prose gets missed -- F6 sat unapplied on production for 13 days because
-- nothing machine-readable said so. Update it the moment you run this file.
-- =====================================================================
-- 2026-08-10 — Supabase SQL Editor worksheet
--
-- Three independent parts. Run in the SQL Editor, which executes as the
-- `postgres` superuser and therefore bypasses RLS (CLAUDE.md § Supabase
-- platform facts) — that is required here, since every query below reads
-- the Postgres catalog, which PostgREST cannot reach at all.
--
--   PART A — DROP the production-only `is_admin()`        [WRITE — prod only]
--   PART B — F92 residual: the catalog reads PostgREST cannot do  [READ-ONLY]
--   PART C — V0 pre-flight for the F127/F109 plan               [READ-ONLY]
--
-- Parts B and C are read-only and safe to run anywhere, any time.
-- PART A is the only statement in this file that changes anything.
--
-- Environments:
--   production  plgegklqtdjxeglvyjte
--   staging     puoaiyezsreowpwxzxhj
-- =====================================================================


-- =====================================================================
-- PART A — drop the production-only `is_admin()`   (Rick's call, 2026-08-10)
-- =====================================================================
-- Context: F19 recorded this function "dropped; confirmed absent from
-- pg_proc" on 2026-05-26 with NO environment qualifier. That drop was
-- STAGING ONLY — Phase 4.1 was the pre-cutover staging hardening pass — so
-- an unhardened dead duplicate of `current_user_is_admin()` has been live on
-- production ever since. Verified 2026-08-10 from two directions:
-- `POST /rest/v1/rpc/is_admin` returns HTTP 200 `false` on production and
-- 404 `PGRST202` on staging.
--
-- Code-side deadness was verified before writing this: zero callers in
-- app.js, any *.html, any Edge Function, or either import script.
--
-- RUN A1-A3 ON **PRODUCTION**. On staging A1 returns zero rows and there is
-- nothing to do — that is the expected staging result, not a problem.

-- ---------------------------------------------------------------------
-- A1. Capture what is about to be dropped. KEEP THIS OUTPUT — it is the
--     rollback. `pg_get_functiondef` emits a complete CREATE statement.
-- ---------------------------------------------------------------------
SELECT p.oid::regprocedure          AS signature,
       p.prosecdef                  AS is_security_definer,
       p.proconfig                  AS config_settings,   -- NULL = no search_path hardening
       pg_get_functiondef(p.oid)    AS rollback_ddl
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname = 'is_admin';
-- EXPECT on production: exactly 1 row. Save `rollback_ddl` before continuing.
-- EXPECT on staging:    0 rows (already dropped 2026-05-26). Stop; nothing to do.
-- If production returns 0 rows, STOP — something else already dropped it and
-- this worksheet is out of date.

-- ---------------------------------------------------------------------
-- A2. Dependency check. This is the gate: if ANYTHING references the bare
--     `is_admin(`, do not drop.
--
--     The regex deliberately excludes `current_user_is_admin(` — a plain
--     LIKE '%is_admin%' matches that too, and would produce a false
--     positive on every policy in the database, which is the kind of
--     always-fires check that teaches an operator to ignore the output.
-- ---------------------------------------------------------------------
SELECT 'policy' AS object_kind,
       tablename || '.' || policyname AS object_name,
       coalesce(qual, '') || ' | ' || coalesce(with_check, '') AS reference_text
FROM   pg_policies
WHERE  schemaname = 'public'
  AND (coalesce(qual, '')       ~ '(^|[^_[:alnum:]])is_admin[[:space:]]*\(' OR
       coalesce(with_check, '') ~ '(^|[^_[:alnum:]])is_admin[[:space:]]*\(')

UNION ALL

SELECT 'function', p.oid::regprocedure::text, 'body references is_admin('
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname <> 'is_admin'
  AND  pg_get_functiondef(p.oid) ~ '(^|[^_[:alnum:]])is_admin[[:space:]]*\('

UNION ALL

SELECT 'view', c.relname, 'definition references is_admin('
FROM   pg_class c
JOIN   pg_namespace n ON n.oid = c.relnamespace
WHERE  n.nspname = 'public'
  AND  c.relkind IN ('v','m')
  AND  pg_get_viewdef(c.oid) ~ '(^|[^_[:alnum:]])is_admin[[:space:]]*\(';
-- EXPECT: ZERO ROWS. That is the go signal.
-- ANY row returned = STOP, do not run A3. A returned row names the exact
-- dependent object, so the two outcomes cannot be confused.
--
-- Belt-and-braces: A3 uses plain DROP, never CASCADE. Postgres records
-- policy→function dependencies in pg_depend, so even if A2 somehow missed
-- one, the DROP fails with "cannot drop ... because other objects depend
-- on it" rather than silently removing a live authorization check.
-- **NEVER add CASCADE to A3.**

-- ---------------------------------------------------------------------
-- A3. The drop.  ← the only writing statement in this file
-- ---------------------------------------------------------------------
DROP FUNCTION public.is_admin();

-- ---------------------------------------------------------------------
-- A4. Verify. Run on BOTH environments afterwards.
-- ---------------------------------------------------------------------
SELECT count(*) AS is_admin_still_present,
       CASE WHEN count(*) = 0 THEN 'PASS — gone'
            ELSE                   'FAIL — still present' END AS verdict
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public' AND p.proname = 'is_admin';
-- PASS = 0 / 'PASS — gone'.  FAIL = 1 / 'FAIL — still present'.
-- The count changes between the two outcomes, so this check can actually fail.
--
-- Rollback if ever needed: re-run the `rollback_ddl` captured in A1.


-- =====================================================================
-- PART B — F92 residual: the catalog reads PostgREST cannot do  [READ-ONLY]
-- =====================================================================
-- Run on BOTH environments and diff the two outputs. F64 catalogued eight
-- prod↔staging divergences and `is_admin()` turned out to be a ninth it
-- missed, so "both environments" is the point of this part, not a formality.
--
-- Everything else in technical-reference.md was re-read from live on
-- 2026-08-10. These four queries are the entire remaining gap.

-- ---------------------------------------------------------------------
-- B1. RLS policy bodies — the highest-value read here, because this is an
--     authorization surface and § 7 was independently found stale for
--     `preorders` on this same date.
-- ---------------------------------------------------------------------
SELECT tablename, policyname, cmd, permissive, roles::text,
       qual        AS using_expr,
       with_check  AS check_expr
FROM   pg_policies
WHERE  schemaname = 'public'
ORDER  BY tablename, policyname;
-- Compare against technical-reference.md § 7 table by table. Expect the
-- documented per-table counts; § 7's `preorders` subsection is KNOWN STALE
-- (claims 4 policies, actual is 2) and is the one entry already proven
-- wrong — see docs/preorders-authorization-boundary-f127-f109.md § 2.1.

-- ---------------------------------------------------------------------
-- B2. SECURITY DEFINER functions: mode, search_path hardening, and grants.
--     Grants matter because F124 established that `REVOKE ... FROM PUBLIC`
--     does NOT strip Supabase's default anon/authenticated grants — so a
--     function can look revoked and not be.
-- ---------------------------------------------------------------------
SELECT p.oid::regprocedure AS signature,
       p.prosecdef         AS security_definer,
       p.proconfig         AS config,          -- expect {search_path=public} on DEFINER fns (F23)
       coalesce(p.proacl::text, 'NULL = owner-only default') AS execute_grants
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
ORDER  BY p.prosecdef DESC, p.proname;
-- Flag any row where security_definer = true AND config IS NULL (F23), and
-- any DEFINER function granting EXECUTE to `anon` that should not (F124).

-- ---------------------------------------------------------------------
-- B3. Constraints — CHECKs, FKs and their delete actions.
--     F10 (preorders FKs NO ACTION), F117 (order_submissions signed
--     quantity), F6 (app_settings composite PK) and F9 (weekly_shipment
--     unique key) all live in this output.
-- ---------------------------------------------------------------------
SELECT rel.relname AS table_name,
       con.conname AS constraint_name,
       CASE con.contype WHEN 'c' THEN 'CHECK'  WHEN 'f' THEN 'FOREIGN KEY'
                        WHEN 'p' THEN 'PRIMARY KEY' WHEN 'u' THEN 'UNIQUE'
                        ELSE con.contype::text END AS kind,
       CASE con.confdeltype WHEN 'a' THEN 'NO ACTION' WHEN 'c' THEN 'CASCADE'
                            WHEN 'n' THEN 'SET NULL'  WHEN 'r' THEN 'RESTRICT'
                            WHEN 'd' THEN 'SET DEFAULT' ELSE NULL END AS on_delete,
       pg_get_constraintdef(con.oid) AS definition
FROM   pg_constraint con
JOIN   pg_class     rel ON rel.oid = con.conrelid
JOIN   pg_namespace n   ON n.oid   = rel.relnamespace
WHERE  n.nspname = 'public'
ORDER  BY rel.relname, con.contype, con.conname;

-- ---------------------------------------------------------------------
-- B4. Indexes.
-- ---------------------------------------------------------------------
SELECT tablename, indexname, indexdef
FROM   pg_indexes
WHERE  schemaname = 'public'
ORDER  BY tablename, indexname;


-- =====================================================================
-- PART C — V0 pre-flight for the F127/F109 plan               [READ-ONLY]
-- =====================================================================
-- Gate V0 of docs/preorders-authorization-boundary-f127-f109.md.
-- Confirms live what five lines of repo evidence already established:
-- F16 is CLOSED, and technical-reference.md § 7's "4 policies" is stale.
-- Run on BOTH environments BEFORE any of that plan's DDL.

SELECT tablename,
       count(*) AS total_policies,
       count(*) FILTER (
         WHERE policyname NOT IN (
           'users manage own preorders',
           'admins manage tenant preorders',
           'users manage own subscriptions',
           'admins view tenant subscriptions'
         )
       ) AS unexpected_policies,
       string_agg(policyname || ' [' || cmd || ' ' || permissive || ' ' || roles::text || ']',
                  E'\n  ' ORDER BY policyname) AS policy_list
FROM   pg_policies
WHERE  schemaname = 'public'
  AND  tablename IN ('preorders', 'subscriptions')
GROUP  BY tablename
ORDER  BY tablename;
--
-- SUCCESS (F16 closed, as expected): two rows, each total_policies = 2 and
--   unexpected_policies = 0, policy_list naming only the four expected
--   policies, all PERMISSIVE.
--
-- FAILURE (F16 actually open): `preorders` reads total_policies = 4 and
--   unexpected_policies = 2, and policy_list PRINTS BY NAME
--   `admins write tenant preorders` and `admins view tenant preorders`.
--   In that case STOP and re-open F16 — its fix must land before the
--   F127 predicate is added to a policy set that is already wrong.
--
-- The counts differ AND the offending names are printed, so the success and
-- failure outputs cannot be mistaken for each other. (CLAUDE.md: "a
-- verification step that cannot fail is not a verification step" — that
-- lesson came from a check whose final statement returned an identical
-- return-signature before and after the fix it was meant to confirm.)
--
-- NOTE: `subscriptions` having no admin WRITE policy is CORRECT and
-- deliberate — Rick's call 2026-08-10 (F128). Do not "fix" it.
