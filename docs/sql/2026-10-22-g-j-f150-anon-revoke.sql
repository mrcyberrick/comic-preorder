-- STATUS: staging=APPLIED 2026-10-22 | prod=APPLIED 2026-10-22 (details below)
--         Staging (Rick; the first verdict read "FAIL - postgres default privileges ...
--         still grant anon", a defect in the VERDICT, which matched the functions row ('f') this file does not
--         touch; narrowed to tables/sequences, re-run reads "OK - ... 48 authenticated grants untouched"; agent
--         anon probe PASS: 401 on all 11 tables, the four anon RPCs 200; full Playwright suite after the revoke: 162 passed, 0 failed, 30.7 min, exit 0) | prod=APPLIED 2026-10-22 (Rick; verdict "OK - ... 78 authenticated grants untouched"; agent anon probe PASS: 401 on all 11 tables, the four anon RPCs 200; signed-out rjbookstop, apex and forgot-password: 0 page errors, 0 failed REST calls)
--         Pre-Phase-6 gate closure, session G-J (docs/pre-phase-6-gate-closure.md § 2h): F150 platform-wide
--         anon-grant hardening (Phase 6 gate G7b). Rick's go 2026-10-22. (F105) This line is the applied-state record.
--
-- WHAT IT DOES
--   Removes every table and sequence privilege the `anon` role holds in schema `public`, and stops new
--   tables created by `postgres` from re-gaining them. RLS already hides every row from anon (no policy on
--   either project applies to `anon` or `public`, G-A 2026-10-06), so this changes what anon gets back from
--   "200 []" to "401 permission denied" and nothing else.
--
-- WHY IT IS SAFE (precondition, checked 2026-10-22 from the code, see § 2h)
--   Nothing reads a table as anon. Before sign-in the client calls only the SECURITY DEFINER RPCs
--   `resolve_tenant_by_slug` and `is_maintenance_mode` (TenantContext reads `tenants` / `user_profiles` only
--   once a session exists); `weekly-pull-feed` (newsletter, preflight, Facebook) calls only
--   `get_pull_feed_week` and `get_pull_feed_spotlight` (both SECURITY DEFINER); every Edge Function sends the
--   anon key only as `apikey` beside the caller's own bearer token (role `authenticated`) or uses the service
--   role; the Playwright suite's only anon-key use is GoTrue's password grant (not PostgREST).
--   SECURITY DEFINER functions run as their owner, so they do not need anon's table grants. Function EXECUTE
--   grants are NOT touched.
--
-- ORDER: staging first, then the full Playwright suite, then production. Run the whole file in one go in
-- the Supabase SQL Editor; the editor shows only the LAST result, so the final SELECT is the verdict.

-- ── PRE (read-only; optional, for the record) ────────────────────────────────────────────────────────
-- SELECT table_name, string_agg(privilege_type, ',' ORDER BY privilege_type) AS anon_privs
-- FROM information_schema.role_table_grants
-- WHERE table_schema = 'public' AND grantee = 'anon' GROUP BY table_name ORDER BY table_name;
-- Expect: staging 2 tables (order_submissions, settings), production 11 tables, each with all seven privileges.
-- SELECT tableowner, count(*) FROM pg_tables WHERE schemaname = 'public' GROUP BY 1;
-- Expect: every table owned by postgres (if not, the default-privileges lines below do not cover that owner).

BEGIN;

REVOKE ALL ON ALL TABLES    IN SCHEMA public FROM anon;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon;

-- New tables / sequences created by postgres (the SQL Editor's role) will not grant anon by default.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON TABLES    FROM anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon;

COMMIT;

-- ── VERDICT (must read OK on both projects; it is a different string when anything is left) ─────────
SELECT CASE
  WHEN (SELECT count(*) FROM information_schema.role_table_grants
         WHERE table_schema = 'public' AND grantee = 'anon') > 0
    THEN 'FAIL - anon still holds table privileges in public: '
         || (SELECT string_agg(DISTINCT table_name, ', ') FROM information_schema.role_table_grants
              WHERE table_schema = 'public' AND grantee = 'anon')
  WHEN EXISTS (SELECT 1 FROM pg_default_acl d
                WHERE d.defaclrole = 'postgres'::regrole
                  AND d.defaclnamespace = 'public'::regnamespace
                  AND d.defaclobjtype IN ('r', 'S')   -- tables, sequences; NOT functions ('f'), left as-is
                  AND d.defaclacl::text LIKE '%anon=%')
    THEN 'FAIL - postgres default privileges in public still grant anon on tables or sequences'
  WHEN NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'is_maintenance_mode' AND prosecdef)
    THEN 'FAIL - is_maintenance_mode missing or not SECURITY DEFINER'
  ELSE 'OK - anon holds no table or sequence privileges in public; postgres defaults no longer grant anon; '
       || (SELECT count(*)::text FROM information_schema.role_table_grants
            WHERE table_schema = 'public' AND grantee = 'authenticated') || ' authenticated grants untouched'
END AS g_j_verdict;

-- ── ROLLBACK (only if an anon RPC or a page breaks; restores the pre-G-J state exactly) ──────────────
-- Production:  GRANT ALL ON ALL TABLES IN SCHEMA public TO anon;
--              GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon;
--              ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO anon;
--              ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
-- Staging:     GRANT ALL ON public.order_submissions, public.settings TO anon;
--              (plus the two ALTER DEFAULT PRIVILEGES ... GRANT lines above)
-- Note: tables created by supabase_admin (platform migrations) keep that role's own defaults; postgres
-- cannot alter them. The PRE owner query above shows whether any app table has another owner (not checked
-- live when this file was written).
