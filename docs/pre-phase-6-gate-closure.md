# Pre-Phase-6 gate closure — readiness re-check and session plan

**STATUS:** IN PROGRESS — G-A DONE 2026-10-06 (SQL only: `tenants_plan_check` and the F151 row cleanup applied on both environments; the F150 revoke deliberately NOT run, deferred by Rick); G-B DONE 2026-10-06 (`register-tenant` fixed, PR #171, `register-tenant` v11 and `register-customer` v34 deployed to production, both smokes run and torn down; F151 RESOLVED on both environments; result in § 2c); G-D runbook written 2026-10-06 (§ 2d), NOT STARTED; G-C, G-E..G-H NOT STARTED | staging=G-A 2026-10-06, G-B 2026-10-06 | prod=G-A 2026-10-06 (SQL only, Rick-run), G-B 2026-10-06 (PR #171 merge `3fadc00`, two Edge Function deploys) | findings=F150,F151,F153,F72,F164,F165,F169,F157,F170

**Written:** 2026-10-06, planning session (Rick asked: "Phase 6 readiness — check status, evaluate open
items that need closing before starting, plan the sessions, hand off").
**Parent:** `docs/phase-6-self-service-signup.md` § Readiness (gates G1–G8, assessed 2026-10-04).
**Branch base:** `staging` for everything; production only where a session says so.
**Next free finding ID at writing:** **F171**.

---

## 0. Verdict (re-checked 2026-10-06): still NOT READY — nothing moved in two days

Every gate that can be measured from here was measured today, not copied from the 10-04 table.
Since 10-04 only F163 work (PRs #168–#170) and the F170 filing landed; none of it touches a gate.

| Gate | 2026-10-06 measurement | State |
|---|---|---|
| **Q3 (strategic)** | `pre-phase-6-consolidation-wave-2.md` § 0 Q3 still reads "small features for now" (Shape D). Nothing reverses it | **Rick's decision — see § 3 D1** |
| G1 wildcard DNS/TLS | `dns.google`: a random `zzz-probe-*.pulllist.app` → **Status 3 (NXDOMAIN)**; `rjbookstop`/`comicstore` → 0 | Open, spike never run |
| G2 F165 | S1 + S2 landed 10-04. `check-dates-state.json` last written **2026-10-02**, so **no real S2 run has happened yet**; soak needs Rick's next two weekly runs | Open, time-gated |
| G3 F72 email + engine | `supabase functions list`: production `register-tenant` **v10, 2026-09-03 02:00Z** (the S0 build, **no F153 invite**); production `register-customer` **v33, 2026-09-02** (Resend M6, **pre-S2a**). Staging runs v22 / v36. Source on `origin/main` == `origin/staging` for both (blob `b0a649b9f6` / `e83ee5562d`), so **no promotion is needed to deploy what is already reviewed**. The other five mail functions are still founding-branded | Open |
| G4 F169 (+F157 scoped delete) | Design written (`f157-distributor-scoping.md` § 4.4), nothing built | Open |
| G5 F131 | Structural; product decision | **Rick — § 3 D2** |
| G6 `tenants.plan` CHECK | No SQL file exists for it; column is `text NOT NULL DEFAULT 'free'` (technical-reference § 4.1). Production values still exact (`rjbookstop="pro"`, `comicstore="free"`) | Open |
| G7a F151 | Production service-role read, **key names only**: both `comicstore` and `rjbookstop` still carry `mailerlite_webhook_secret`. **New finding about the fix:** `register-tenant/index.ts:177/196/347` still **generates, stores and returns** that secret on every new tenant, so deleting the key from today's rows alone would not close F151 | Open — wider than recorded |
| G7b F150 | Anon `GET /rest/v1/app_settings` on production → **HTTP 200** (staging: 401) | Open |
| G8 F164 | Creation path untraced | Open |

**Also confirmed closed, so not in the plan:** F145's owed runbook item is done —
`tenant-onboarding-runbook.md` Step 3a now carries the live hostname inventory (lines ~160–170),
including that `rjbookstop.pulllist.app` is printed on customer paper.

---

## 1. The sessions, in order

One concern per session (CLAUDE.md § Anti-Drift). **G-A, G-B and G-D are worth doing under Shape D
regardless of Q3** — they are security hygiene plus already-promoted code that is sitting undeployed —
so they do not wait on D1. G-C is the cheap information D1 actually needs. G-F, G-G and G-H are
Phase-6-motivated and wait on D1.

| # | Session | Closes | Gate / precondition | Size |
|---|---|---|---|---|
| **G-A** | **Tenant & settings hygiene (SQL only, both envs)** — F150 sweep + fix, `tenants_plan_check`, F151 row cleanup | G6, G7b, half of G7a | **DONE 2026-10-06 — see § 2a for the result.** Closed G6 and the F151 rows; **did NOT close G7b** (the sweep widened F150 and Rick deferred it) | 1 session, Rick runs SQL |
| G-B | **Engine to production** — `register-tenant` stops minting the webhook secret (closes F151), then deploy `register-tenant` (F153 invite) + `register-customer` (F72 S2a) to production | rest of G7a, engine half of G3 | after G-A (**done**); `/promote-prod` needs Rick's explicit request. **Runbook: § 2b. DONE 2026-10-06 — see § 2c for the result.** Closed G7a and the engine half of G3; the client signup gate and the other five mail functions are still open (§ 2c) | 1 session |
| G-C | **S0 serving-model spike** — wildcard `*.pulllist.app` + TLS on Pages; price (a) wildcard vs (b) CF-for-SaaS | G1 | none technically; **PAUSE before any DNS change** | 1 session, Rick in Cloudflare dashboard |
| G-D | **F164 creation-path trace** (read-only investigation) | G8 | none; can run in parallel with anything. **Runbook: § 2d** | ½ session |
| G-E | **F165 soak → V5 → S3 decision** (already CLAUDE.md's "next scheduled work") | G2 | Rick's next **two** real weekly `check-dates.js` runs (first ~Fri 10-09/Sat 10-10, second a week later) | V5 with Rick, then an S3 build session if chosen |
| G-F | **F72 email half** — the five remaining mail functions tenant-aware (`approve-customer`, `invite-customer`, `notify-customers`, `reset-password`, `send-my-list`) | G3 | after G-B (same deploy discipline proven); D1 | 1–2 sessions, real-inbox checks need Rick |
| G-G | **F169 single-distributor import mode + F157 scoped delete** (scripts repo + one migration) | G4 | **after the November new-month import** (late Oct), so F165 S1's first real exercise runs on unchanged import code; D1 | 1 session |
| G-H | **Open Phase 6: write the 6.x runbooks** | — | D1 reversed, G-A…G-G closed, D2–D4 answered | planning session |

**Not gates, but worth doing before any 6.x build:** **F170** (sign-in fixtures leak auth users when
sign-in throws). 6.x will lean on the full suite and create many throwaway users; a one-file `try/finally`
fix is cheap. F130, F152 (monitor) and F161 are unaffected by Phase 6 and stay where they are.

---

## 2. Session G-A — runbook (the execution session)

**Scope IN:** three database changes, staging first then production, all run by Rick in the Supabase SQL
Editor; one committed SQL file; doc updates. **Scope OUT:** any Edge Function change or deploy (G-B),
any client code, `register-tenant`'s secret generation (G-B), anything found by the F150 sweep beyond
`app_settings` (→ PAUSE).

### Step 0 — preflight and baselines (agent, read-only)

1. `/preflight`. Confirm `git branch --show-current` is `staging` (not detached; see Known Issues).
2. Re-measure, and **halt if any differs from § 0**:
   - production anon `GET /rest/v1/app_settings?select=key&limit=1` → `200`; staging → `401`
     (anon key from each branch's `config.js`; `git show origin/main:config.js` for production).
   - production and staging `tenants` key names: `select=slug,plan,settings`, print `Object.keys(settings)`
     only. **Never print or log a value.**
3. Read `docs/technical-reference.md` § 4.1 (`tenants`) and § 13 F150/F151 before writing any SQL
   (`/sql-check`).

### Step 1 — F150 sweep (read-only, Rick runs on BOTH projects, pastes results)

The 2026-09-01 filing compared one table. Supabase's own defaults grant `anon` on new `public` tables,
so production may be the *normal* state and staging the hardened one; the sweep decides which, across
every table, before anything is revoked.

```sql
-- F150 sweep — read-only. Run on staging AND production; paste both.
SELECT c.relname                                   AS table_name,
       c.relrowsecurity                            AS rls_enabled,
       coalesce(string_agg(DISTINCT g.privilege_type, ',' ORDER BY g.privilege_type), '-') AS anon_privs
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN information_schema.role_table_grants g
       ON g.table_schema = 'public' AND g.table_name = c.relname AND g.grantee = 'anon'
WHERE n.nspname = 'public' AND c.relkind = 'r'
GROUP BY c.relname, c.relrowsecurity
ORDER BY c.relname;

SELECT defaclrole::regrole AS owner, defaclnamespace::regnamespace AS schema,
       defaclobjtype AS objtype, defaclacl::text AS acl
FROM pg_default_acl ORDER BY 1, 2, 3;
```

Agent diffs the two results table by table. **⏸ PAUSE → Rick:**
- **If `app_settings` is the only table whose `anon_privs` differ, and `rls_enabled` is true on both** →
  proceed to Step 2 with the single-table revoke.
- **If other tables differ, or any `rls_enabled` is false, or the default ACLs differ** → do **not**
  revoke anything this session. Record the full diff in § 13 F150 and stop Step 1–2; widening the
  fix is a scope decision for Rick (it may be a new finding).

### Step 2 — F150 fix (production only, only if Step 1 cleared)

Matching staging is already proven safe: staging has denied anon on `app_settings` throughout, the
full suite passes there, and the only anon reader (`Settings.isMaintenanceModePublic`, F149) goes
through the `SECURITY DEFINER` RPC `is_maintenance_mode()`, which needs no table grant.

```sql
BEGIN;
REVOKE ALL ON public.app_settings FROM anon;
COMMIT;
-- POST (must change): expect zero rows
SELECT privilege_type FROM information_schema.role_table_grants
WHERE table_schema = 'public' AND table_name = 'app_settings' AND grantee = 'anon';
```

**Verification that can fail** (agent, after Rick's run): production anon `GET app_settings` →
**401/42501** (was 200), **and** the F149 RPC still answers anon:
`POST /rest/v1/rpc/is_maintenance_mode` with the founding tenant id → `200` + `false`.
If the RPC breaks, rollback is `GRANT SELECT ON public.app_settings TO anon;` and halt.

### Step 3 — G6: `tenants_plan_check` (staging, then production)

```sql
-- PRE: every value must already be 'free' or 'pro' (ADD CONSTRAINT aborts the transaction otherwise)
SELECT plan, count(*) FROM public.tenants GROUP BY plan ORDER BY plan;
SELECT conname FROM pg_constraint
WHERE conrelid = 'public.tenants'::regclass AND conname = 'tenants_plan_check';   -- expect 0 rows

BEGIN;
ALTER TABLE public.tenants
  ADD CONSTRAINT tenants_plan_check CHECK (plan IN ('free', 'pro'));
COMMIT;

-- POST (must change): expect exactly one row, definition CHECK ((plan = ANY (ARRAY['free'::text, 'pro'::text])))
SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint
WHERE conrelid = 'public.tenants'::regclass AND conname = 'tenants_plan_check';
```

Before staging: sweep the local Playwright fixtures for how test tenants are created
(`grep -rn "plan" <scripts>/playwright/fixtures` **via Bash**, not the Grep tool — it skips the
gitignored folder). A fixture writing any other value would break after this; expected: none set `plan`
(column default `'free'`). After staging, run the targeted specs that create tenants
(the `pw-*` tenant fixtures; at minimum spec 20 and the tenant-isolation specs) — targeted, not full.

### Step 4 — F151 row cleanup (staging, then production)

```sql
-- PRE (slugs only — never select the value)
SELECT slug FROM public.tenants WHERE settings ? 'mailerlite_webhook_secret' ORDER BY slug;

BEGIN;
UPDATE public.tenants
   SET settings = settings - 'mailerlite_webhook_secret'
 WHERE settings ? 'mailerlite_webhook_secret'
RETURNING slug;
COMMIT;

-- POST (must change): expect 0
SELECT count(*) FROM public.tenants WHERE settings ? 'mailerlite_webhook_secret';
```

No rotation: the value authorizes nothing since 2026-08-30. **F151 stays OPEN after this step** —
`register-tenant` re-adds the key to every new tenant until G-B removes the writer. Say so in § 13.

### Step 5 — record (agent)

- Write `docs/sql/2026-10-XX-pre-phase-6-tenant-hygiene.sql` holding Steps 2–4 exactly as run, with a
  `-- STATUS:` line. **Both environments must read `APPLIED` (or the F150 part `N/A`) before the session
  ends**: `/promote-prod` step 0 blocks every promotion on a `PENDING` file.
- § 13: F150 (sweep result + fix, or the PAUSE outcome), F151 (rows clean, writer still open → G-B),
  and the G6 constraint (no finding ID was ever assigned; record it under F72 S0's residual where it was
  raised). Update `phase-6-self-service-signup.md` § Readiness rows G6/G7 and this doc's STATUS.
- CLAUDE.md: the open-findings rows for F150/F151 and the Readiness line. Doc-only commit to `staging`.

### Completion criteria (G-A)

- [x] Step 1 sweep results recorded for both environments, and Rick's PAUSE decision recorded *(§ 13 F150; decision: skip Step 2, defer F150, scope widened, no new ID)*
- [x] ~~Production anon `app_settings` → 401~~, F149 RPC still `200/false` **or F150 explicitly deferred by Rick** *(the 401 was NOT achieved and is not claimed: production anon `GET app_settings` still reads 200. This box is ticked on its second branch only: Rick deferred F150 on 2026-10-06, and the F149 RPC re-read `200` / `false` on both projects)*
- [x] `tenants_plan_check` present on both (POST query returns the row on each) *(`convalidated` true on each)*
- [x] 0 tenants carry `mailerlite_webhook_secret` on both *(POST check 0 on each; independently re-read through the service role, every `settings` is `{}` on all 9 tenants)*
- [x] SQL file committed with both environments `APPLIED`/`N/A`; no `PENDING` left *(`docs/sql/2026-10-06-pre-phase-6-tenant-hygiene.sql`)*
- [x] Targeted tenant-creating specs green on staging after Step 3 *(07, 08, 09, 20: 21 passed in 2.3 min, exit 0, from the log's own summary; plus `f72-s0-plan-allowlist.mjs` 7/7)*
- [x] Docs updated; status update produced (`/wrap-up`)

### Rollback

- F150: `GRANT SELECT ON public.app_settings TO anon;` (restore only SELECT unless Rick asks for the full prior set).
- G6: `ALTER TABLE public.tenants DROP CONSTRAINT tenants_plan_check;`
- F151: not reversible and not needed — the value is dead config.

### 2a. Session G-A result (2026-10-06)

**Ran:** Step 0, Step 1, Step 3 and Step 4 on both environments (staging first), Step 5. **Did NOT run: Step 2.**

- **Step 0.** Every baseline matched § 0 (production anon `GET app_settings` 200, staging 401; production's two
  tenants carry the key). One difference worth knowing: **staging carried the key on THREE tenants**
  (`raysandjudys`, `demoshop`, `riverside-comics`), not the one the 2026-09-01 measurement recorded; the two
  newer ones were created through `register-tenant`, which is the writer G-B must fix.
- **Step 1, and the PAUSE.** The runbook's own branch applied: **9 of 11 tables differ, not only
  `app_settings`**, so nothing was revoked. Production anon holds all seven table privileges on all 11 `public`
  tables; staging holds none on 9 and the full set on `order_submissions` and `settings`. RLS is on for all 11 on
  both, default ACLs are identical (the platform default), and **no policy applies to `anon` or `public` on
  either project (28 policies each)**; anon sees 0 rows on every exposed table on both. **Rick (2026-10-06): skip
  Step 2, defer F150, scope widened, no new ID.** Full diff: § 13 F150. A cross-check I ran before Rick's paste
  (anon-key REST probes, `limit=0` plus a count header, no row data) predicted the branch and agreed with the SQL.
- **Step 3.** `tenants_plan_check` applied on staging, then production; `convalidated` true on both. Local
  Playwright fixtures were swept via Bash first: `fixtures/tenant.ts` inserts only `slug` and `display_name`
  (so `plan` takes the `'free'` default), and no spec or fixture writes another plan value. Staging afterwards:
  targeted specs **07, 08, 09 and 20: 21 passed (2.3 min), exit 0**; `f72-s0-plan-allowlist.mjs` 7/7 (the real
  `register-tenant` writer through the constraint, teardown 0 tenants / 0 profiles / 0 orphaned auth users).
- **Step 4.** The key was deleted on both; 0 carriers on both by Rick's POST check and by my service-role
  read-back (every `settings` is `{}` on all 9 tenants). **F151 stays OPEN**, because the writer is live.
- **Deviations from the runbook as written, all deliberate:** (1) one combined **round-1** read-only query per
  project carried the F150 sweep and the Step 3 and 4 PRE checks (the SQL Editor shows only the last
  statement's result, and Steps 3 and 4 do not depend on the pause); (2) the sweep gained a `has_table_privilege`
  column, because `information_schema.role_table_grants` only lists grants whose grantor or grantee is an
  enabled role; (3) `jsonb_exists(settings, 'k')` replaces `settings ? 'k'`, the same test without a `?` the
  editor might read as a placeholder; (4) Steps 3 and 4 ran in ONE transaction per project; (5) the POST query
  gained `convalidated`. One hiccup: Rick's first production paste lacked the `app_settings` policy rows (they
  sort first), which looked like "zero policies"; a follow-up policy query showed they were present and the top
  of the paste had been cut.
- **Not verified, stated plainly:** (a) a hand-typed `UPDATE ... SET plan = 'Pro'` being **refused** was not
  run (`convalidated` is the evidence); (b) **no anon write probe** was run against either project, so
  "nothing writable by anon" rests on the complete policy audit, not on an attempt; (c) the targeted specs, not
  the full suite, ran (by the runbook's design), and only on staging: nothing exercised `register-tenant` on
  production; (d) the REST cross-check scripts live in the session scratchpad and are not committed.
- **Hand-off to G-B.** Deleting the rows did not close F151: `register-tenant/index.ts` lines 177, 196 and 347
  (re-read this session) still generate, store and return the secret. G-B removes that, updates
  `tenant-onboarding-runbook.md` Step 1's expected response, and deploys `register-tenant` and
  `register-customer` to production. **A tenant created before G-B ships carries the key again**, and the
  cleanup SQL here is not worth re-running until the writer is gone.
- **New decision owed (Rick), not scheduled:** F150's platform-wide revoke. The fix direction and what is not
  yet established are in § 13 F150; it needs its own session. **It stays the open half of gate G7b** ("must be
  clean before strangers get admin accounts"), so Phase 6 cannot open until it is closed or explicitly
  waived; it is not urgent under Shape D, where no stranger gets an account.

---

## 2b. Session G-B — runbook (engine to production; written 2026-10-06; **DONE 2026-10-06, result in § 2c**)

**Goal.** `register-tenant` stops generating, storing and returning the dead `mailerlite_webhook_secret`
(closes **F151**), and production finally runs the reviewed `register-tenant` (F153 admin invite) and
`register-customer` (F72 S2a tenant-aware email) that have sat on `main` undeployed since 2026-09-03.

**Measured at planning (2026-10-06), so the session can check it has not moved:**

| Fact | Value |
|---|---|
| Production deployed versions | `register-tenant` **v10** (2026-09-03 02:00Z, S0 build, no invite); `register-customer` **v33** (2026-09-02, pre-S2a) |
| Staging deployed versions | `register-tenant` **v22** (2026-09-03 20:04Z); `register-customer` **v36** (2026-09-03 16:03Z) |
| Source | Last commits: `register-tenant` `d4d5250` (F153), `register-customer` `efadbf0` (S2a). Blobs identical on `origin/main` and `origin/staging` (`b0a649b9f6` / `e83ee5562d`) |
| Writer of the dead key | `register-tenant/index.ts:176-177` (generate), `:196` (`settings: { mailerlite_webhook_secret }`), `:347` (`webhook_secret` in the response); header docblock `:8` describes it |
| Consumers of `webhook_secret` | **None functional.** Local harnesses `f72-admin-invite-verify.mjs`, `f72-demo-tenant-setup.mjs`, `f72-s0-plan-allowlist.mjs` only redact or ignore it. Docs that describe it: `tenant-onboarding-runbook.md` (lines ~11, 38, 70, 73, 203-204) and `technical-reference.md` (~2368, 2378, and § 13 F151) |
| Production secrets present (names only) | `APP_BASE_URL`, `FOUNDING_TENANT_ID`, `MAIL_FROM_EMAIL`, `MAIL_FROM_NAME`, `RESEND_API_KEY`, `TENANT_PROVISION_SECRET`, `TURNSTILE_SECRET_KEY` — everything both functions read. Dormant, **out of scope**: `MAILERLITE_WEBHOOK_SECRET`, `MAILERSEND_API_KEY` (F99's optional M8) |
| Promotion shape | `origin/staging` is 4 commits ahead of `origin/main`; its only non-doc difference is the expected `config.js` + `supabase/migrations/` asymmetry (F125). Every `docs/sql` file reads `prod=APPLIED` or `N/A`, so `/promote-prod` step 0 is clear. **The promotion will carry exactly `register-tenant/index.ts` plus docs** |

**Scope IN:** the `register-tenant` edit; its staging deploy; the doc updates; one `/promote-prod`
(**only on Rick's explicit request in-session**); production deploys of `register-tenant` and
`register-customer`; the production smokes in Step 6 (each Rick's go).
**Scope OUT:** any other Edge Function (G-F), F150 (deferred), deleting dormant secrets, any client
or SQL change, any change to `register-customer`'s source. Stop and ask for anything else.

### Step 0 — preflight and re-measure (agent, read-only)

`/preflight`; `git branch --show-current` = `staging`. Re-run `supabase functions list` on both projects
and the blob comparison above; **halt if any version or blob differs from the table** (someone deployed
or edited in between). Re-confirm production `tenants` carry no `mailerlite_webhook_secret` key (service
role, key names only), so Step 6's "no key" result can be attributed to the new code.

### Step 1 — save the production rollback artifacts FIRST (agent, read-only)

```bash
supabase functions download register-tenant   --project-ref plgegklqtdjxeglvyjte --workdir <scratch>/rollback-prod
supabase functions download register-customer --project-ref plgegklqtdjxeglvyjte --workdir <scratch>/rollback-prod
```

Record each `index.ts` sha256. These are the **exact** v10 / v33 bytes production runs today and the
rollback source if Step 5 misbehaves (redeploy them with `--no-verify-jwt` from that workdir). Expected:
`register-customer` should match `git show efadbf0~1:supabase/functions/register-customer/index.ts`
and `register-tenant` should match `git show d4d5250~1:...`; **record, don't halt,** if they differ — the
download is authoritative. The repo tree must not be touched by the download (it goes to scratch).

### Step 2 — the code change (feature branch → staging)

`git checkout -B fix/f151-register-tenant-secret refs/heads/staging` (the bare `staging` refname is
ambiguous; see Known Issues). In `supabase/functions/register-tenant/index.ts`:
- delete the secret generation (`:176-177`);
- insert `settings: {}` in place of `settings: { mailerlite_webhook_secret: webhookSecret }` (`:196`) —
  keep the key explicit so a reader sees the choice; the column default is also `'{}'`;
- drop `webhook_secret: webhookSecret,` from the success response (`:347`);
- correct the header docblock (`:8`) so it no longer promises a webhook secret, naming F151.

`grep -n "webhook" supabase/functions/register-tenant/index.ts` afterwards must return **only** the new
explanatory comment(s). No other file in `supabase/` changes. Commit (`fix(F151): ...`, Bash heredoc),
`git merge --ff-only` into `staging`. **Do not push yet** — Step 3 needs the old deploy as its control.

### Step 3 — staging: control red, deploy, then green

1. **Extend `f72-s0-plan-allowlist.mjs`** (local-only harness) with two assertions per created tenant:
   the response object has **no `webhook_secret` key**, and the tenant's `settings` read back by service
   role has **zero keys**. Run it **now, against staging's current v22**: the two new assertions must go
   **red** (that is the negative control, for free) and every existing assertion stays green. Teardown
   must still leave 0 tenants / 0 profiles / 0 orphaned auth users.
2. **Measure `verify_jwt` by behaviour** before deploying: an unauthenticated `POST` to
   `/functions/v1/register-tenant` → the function's own `{"error":"Unauthorized"}` means **OFF**; the
   gateway's `{"code":401,"message":"Missing authorization header"}` means ON. Expected OFF.
3. Deploy: `supabase functions deploy register-tenant --project-ref puoaiyezsreowpwxzxhj --no-verify-jwt`
   (only if step 2 read OFF; otherwise halt — the CLI default is ON, the F93 hazard). Re-probe → still OFF.
4. **Read back the artifact:** `functions download` to scratch; sha256 must equal the committed
   `index.ts`.
5. Re-run the extended `f72-s0-plan-allowlist.mjs` → **all green** (7 original + the new ones);
   `f72-admin-invite-verify.mjs` → `invite_sent` true. Fresh read: 0 harness tenants, 0 orphaned auth users.
6. `git push origin staging`.

### Step 4 — docs (staging, doc-only commit)

- `tenant-onboarding-runbook.md`: Step 1's expected response becomes
  `{ tenant_id, admin_user_id, slug, invite_sent }`; the "save the first four values" line and the
  credential-rule lines (~11, 38, 73) stop referring to a `webhook_secret`; the § ~203 note says the field
  is gone as of this date (keep the old wording visible, per convention).
- `technical-reference.md`: `register-tenant` description (~2368) and return shape (~2378); § 13 F151 →
  **RESOLVED on staging** (production after Step 5), with the measurements.
- This doc: § 2c result (written at the end), STATUS token.

### Step 5 — promotion and production deploys

1. **⏸ PAUSE → Rick:** ask for an explicit `/promote-prod`. Without it, stop here with staging done.
2. `/promote-prod` as the skill runs it. Assertions specific to this one: the merge RESULT's
   `register-tenant/index.ts` == staging's; `register-customer/index.ts` unchanged and == staging's;
   `app.js` and every page identical on both branches; PR file list read **on GitHub itself** =
   `register-tenant/index.ts` + docs only, no `config.js`, nothing under `supabase/migrations/`.
   Write-smoke: **skipped** — the diff never touches `Preorders` or the reserve path (state it from the diff).
3. Deploy **from `origin/main`'s tree, not the working tree**: `git worktree add <scratch>/main-tree
   origin/main`, deploy with `--workdir <scratch>/main-tree`, remove the worktree after.
4. For **each** of `register-tenant` and `register-customer` on production (`plgegklqtdjxeglvyjte`):
   behaviour-probe `verify_jwt` (for `register-customer`, an unauthenticated `POST {}` → the function's
   own validation/Turnstile error = OFF; the gateway's message = ON); expected **OFF** for both; deploy with
   `--no-verify-jwt`; re-probe; `functions download` to scratch and sha256 == `origin/main`'s `index.ts`;
   `functions list` shows the version advanced.
5. **If any probe or hash fails:** redeploy that function from Step 1's rollback artifact and halt.

### Step 6 — production smokes (each one Rick's go; skipped ones are recorded as residuals)

- **6a `register-tenant` (recommended — first production run of the F153 invite and of G-A's constraint
  with the real writer).** Agent prepares the curl from the runbook; **Rick substitutes the operator
  secret and runs it**, creating a throwaway tenant (slug e.g. `gb-smoke-1006`, `plan` omitted, admin
  email a Rick-controlled inbox). Rick pastes the response; agent confirms the keys are exactly
  `tenant_id, admin_user_id, slug, invite_sent` and `invite_sent` is `true`. Service-role read: `settings`
  has zero keys, `plan` = `free`. Rick checks the inbox: invite arrived (and whether in spam — F152 is
  about Outlook), delivered headers show `From: PULLLIST <noreply@pulllist.app>` with `dkim=pass` for
  `pulllist.app`, the link lands on the apex set-password page (do not need to complete it). **Teardown**
  per `tenant-onboarding-runbook.md` § Rollback, FK-ordered, Rick-run; then a fresh read: 0 rows for that
  tenant id and the auth user gone (404).
- **6b `register-customer` free-tier email (recommended).** Rick signs up a test customer at
  `comicstore.pulllist.app` (the `free` tenant; never the real store, whose Pending panel staff watch) with a
  Rick-controlled inbox. The email's from-name, subject and greeting carry **comicstore's display name**;
  no Ray & Judy's name, phone or address anywhere. Then delete the pending profile and its auth user
  (service role, Rick's go), fresh read 0. The paid branch (`rjbookstop`) is **not** live-tested: S2a's
  harness proved its output byte-identical to the old template (V6), and a test signup there would land in
  the real store's Pending panel.

### Step 7 — record

§ 2c result here; § 13 F151 **RESOLVED both environments** (or staging-only if Step 5 did not run);
§ 13 F153 production half; F72 S2a deployed on production; CLAUDE.md: a promotion entry in the usual
shape (gates, served/deployed verification, what was NOT verified, finding-ID disposition: **closes F151,
no new ID**), the F151/F153 table rows, and the Readiness line; `phase-6-self-service-signup.md` G3/G7a
rows. Doc-only commit to `staging`, pushed. `/wrap-up`.

### Completion criteria (G-B)

- [x] Step 0 re-measure matched; Step 1 rollback artifacts saved and hashed
- [x] `register-tenant` edited; `grep webhook` shows only comments; committed via `--ff-only` to `staging` (`784a51c`)
- [x] Harness control observed **red** on staging v22 (8 of 8 new assertions), then **green** (15/15) after the staging deploy (v23); invite harness `invite_sent` true; 0 orphaned auth users
- [x] Staging `verify_jwt` OFF before and after; deployed artifact hash == committed source (`8748d2c0f19da63a`)
- [x] Runbook + technical-reference updated; F151 recorded
- [x] `/promote-prod` run on Rick's explicit request, PR #171 = `register-tenant/index.ts` + docs only (9 files, read on GitHub)
- [x] Production `register-tenant` (v10 to v11) and `register-customer` (v33 to v34) deployed from `origin/main`'s tree; `verify_jwt` OFF before/after both; artifact hashes == `origin/main`
- [x] 6a and 6b run with teardown verified by fresh read (neither skipped; see § 2c for the three 6a attempts and 6b's workaround)
- [x] Docs, CLAUDE.md and status token updated; `/wrap-up` produced (this commit)

### Rollback

- Staging: `git revert` the fix commit and redeploy (`--no-verify-jwt`); nothing else depends on the field.
- Production functions: redeploy from Step 1's downloaded v10 / v33 with `--no-verify-jwt`.
- Production test rows from Step 6: the runbook's FK-ordered teardown.

### 2c. Session G-B result (2026-10-06)

**Ran: every step, 0 through 7, neither smoke skipped. F151 is RESOLVED on BOTH environments. No new finding
ID consumed (F171 stays next free).** Rick requested the `/promote-prod` in-session and merged PR #171.

- **Step 0.** Matched the § 2b table exactly: production `register-tenant` v10 / `register-customer` v33,
  staging v22 / v36, blobs `b0a649b9f6` / `e83ee5562d` on both branches, and no tenant on either project
  carrying the key (names only). `/preflight` clean; one out-of-scope doc flag noted and left alone
  (`order-restriction-alert-badge.md` reads IN PROGRESS with F132 and F133 both resolved-looking; F133
  variant (b) was re-dispositioned rather than closed, so probably a false flag).
- **Step 1.** Production v10 / v33 downloaded to the session scratchpad before anything else. Hashes:
  `register-tenant` `f173bbf9be064cab`, `register-customer` `0fe8af2683fa011c`. Both equal the expected
  pre-F153 / pre-S2a sources (`d4d5250~1`, `efadbf0~1`) **modulo CR**: a download lands CRLF on this Windows
  tree, so compare modulo CR or against the working-tree file. **The scratchpad is session-temporary:** the
  rollback is re-derivable from git at those two refs (hash-equal), which is what a later session should use.
- **Step 2.** `784a51c`: secret generation removed, `settings: {}` explicit, response is
  `{ tenant_id, admin_user_id, slug, invite_sent }`, header docblock corrected; `grep -n webhook` hits the two
  comment lines only. The first wording of my own comment overstated F151's read claim ("readable by every
  authenticated user"); softened to "can be read ... (inferred, not yet probed with a real JWT)" before commit.
- **Step 3.** Extended `f72-s0-plan-allowlist.mjs` (two assertions per created tenant, key NAMES only): **red 8
  of 8 on staging v22** (response keys included `webhook_secret`, `settings` held `mailerlite_webhook_secret`),
  the seven original assertions green; **15/15 green on v23** after the deploy. `verify_jwt` read OFF by
  behaviour before and after (the function's own `{"error":"Unauthorized"}`). Deployed artifact byte-identical
  to the committed source (`8748d2c0f19da63a`). `f72-admin-invite-verify.mjs` 7/7, `invite_sent` true. Fresh read:
  0 harness tenants, profiles or auth users (967 auth users scanned, paginated).
- **Step 4.** Runbook and technical-reference updated (`4e5f7b6`), old wording kept visible.
- **Step 5.** **PR #171, merge `3fadc00`** (parents `b5be5d7` main + `08d1f4e`; staging tip `4e5f7b6`). Merge
  RESULT asserted per file: `register-tenant/index.ts` == staging; `register-customer/index.ts`, `app.js` and
  every page identical on both branches, so the `merge=ours` driver had nothing to discard; `config.js` ==
  `origin/main` (prod ref x1, staging ref x0); `supabase/migrations/` still 2 files; the eight docs == staging.
  PR file list read **on GitHub itself**: 9 files, no `config.js`, nothing under `supabase/migrations/`,
  `MERGEABLE`, Cloudflare check passed. **Write-smoke skipped, from the diff:** nothing in it touches `Preorders`
  or the reserve path. Production deploys from a worktree of `origin/main` (not the working tree): `register-tenant`
  **v10 to v11**, `register-customer` **v33 to v34**, each with `verify_jwt` probed by behaviour OFF before and
  after and deployed `--no-verify-jwt`; read-back hashes `8748d2c0f19da63a` (== staging v23) and `931c29e433431936`
  (CR-stripped `bb0a3a51599a12f4`, the S2a hash recorded 2026-09-03). The worktree's admin folder under `.git/`
  resisted removal once (a OneDrive reparse-point lock) and was then removed.
- **6a, `register-tenant` on production, three attempts, and the first two are worth keeping.** (1) The address first
  supplied (the operator's own Outlook address) already belongs to an **active `rjbookstop` customer**, so the function
  returned **409 `admin_email_exists`**. Checked by fresh read instead of assumed: **no tenant row was left**
  (the function creates the tenant first, so this exercised its compensation path for free), the existing
  customer's profile and auth user were untouched (compensation only deletes an auth user it created itself),
  and no email was sent (the invite follows the profile insert). (2) The operator submitted the address
  **with literal angle brackets**, copied from **my placeholder**, which returned a 500 `Failed to create admin user`;
  **reproduced on staging**: GoTrue itself answers `400 validation_failed: invalid format`, and a clean address on
  the same code returns 200. Production was unchanged. (3) A clean address succeeded: response keys exactly
  `admin_user_id, invite_sent, slug, tenant_id`, `invite_sent` true; service-role read: `plan` `free` (the real
  writer passed `tenants_plan_check` on production), `settings` `{}`, `branding` `{}`, one profile (`is_admin`,
  `active`); `settings` empty on all 3 tenants. **Delivered email:** From `PULLLIST <noreply@pulllist.app>`,
  `dkim=pass` `pulllist.app` (selector `resend`) plus `amazonses.com`, `spf=pass` via `send.pulllist.app`,
  `dmarc=pass`, links direct (no click tracker), no tracking pixel, shop link the apex `?t=<slug>` (not an
  unprovisioned subdomain). Rick ran the FK-ordered teardown; **fresh service-role read: tenant, profile, every
  tenant-scoped table 0, auth user 404, production back to exactly `comicstore` and `rjbookstop`.**
- **6b, `register-customer` free-tier email on production.** `comicstore.pulllist.app` shows **no "Create one"
  link, by design**: `index.html:573` reveals it only when the hostname slug is the founding tenant's. Reached
  the live path without any code change by revealing the link in DevTools (the click handler is bound
  unconditionally and the submit posts the page's resolved slug). **Email:** From `The Comic Store
  <noreply@pulllist.app>`, subject "The Comic Store — Your PULLLIST access is being set up", footer "The Comic
  Store · Sent via the PullList pre-order system" with **no phone and no address**, **no Ray & Judy's name,
  phone, address or city anywhere**, `dkim` / `spf` / `dmarc` all pass. The database agreed: one profile in
  `comicstore`, `pending`, non-admin, no preorders or subscriptions. Deleted with Rick's go by a guarded
  service-role script (exact address, exactly one pending non-admin `comicstore` profile, matching auth user, no
  preorders or subscriptions, else abort); **fresh read: 0 profiles, auth 404, 0 pending in `comicstore`.**
- **Two credential-in-the-paste events, both bounded.** The pasted email in 6a and again in 6b carried a live
  one-time link token. Neither was repeated anywhere, and deleting the auth user kills the token (done in both
  cases within the session). **For a future smoke, paste headers only (stop at the first blank line) and replace
  any link with `[link]`.** *(My 6b instruction asked for exactly that and the whole message came anyway; the
  instruction should say "do not paste the body".)*
- **Observed, deliberately NOT filed and NOT fixed (no ID consumed; Rick's call):** (1) **the client signup gate
  is still founding-only** (`index.html:573`), so although the server path and the free-tier email are now live on
  production, no non-founding customer can reach native signup; Phase 6 needs it relaxed, and it belongs with the
  rest of G3. (2) `register-tenant` validates the admin address only for an `@`, so a malformed address surfaces as
  a 500 rather than a 400 (operator-facing, and the tenant is compensated away); a stricter check is a small change.
- **NOT verified, stated plainly:** (a) the set-password link was **not clicked**, so the apex set-password page
  was not seen for a recovery link on production; (b) **inbox versus spam is not established** for either email
  (the headers do not say), and both went to a PrivateEmail-hosted mailbox, **not Microsoft, so F152's Outlook
  question is untouched**; (c) the `plan = 'pro'` path was not exercised on production (only `free`); (d) the paid
  branch of `register-customer`'s email was **not live-tested** (staging's V6 proved it byte-identical to the old
  template; a test signup on `rjbookstop` would land in the real store's Pending panel); (e) the full Playwright
  suite was **not run**: no web byte changed and the suite tests the deployed site, so the evidence is the harnesses
  above, not a green suite; (f) no reserve write-smoke (the diff never touches it); (g) a real Turnstile pass was
  done by Rick's hands in 6b, so that gate is exercised, but only once.
- **Hand-off.** **G7a (F151) closed.** **G3's engine half closed** (production runs F153's invite and S2a's
  tenant-aware email). **Still open in G3:** the client signup gate (observation 1), and the five other mail
  functions (`approve-customer`, `invite-customer`, `notify-customers`, `reset-password`, `send-my-list`), which are
  session G-F. **G7b (F150) is unchanged and still the open half of G7.** Verdict: **Phase 6 still NOT READY**
  (G1, G2, G4, G5, G8, the rest of G3 and G7b stand; Shape D stands). **Next in this plan that needs no Phase 6
  decision: G-D (F164 trace).**

---

## 2d. Session G-D — runbook (F164 creation-path trace; written 2026-10-06, NOT STARTED)

**Goal.** Answer the one question F164 left open, the one gate G8 asks: **can a client produce a
`preorders` row whose `catalog_id` belongs to another tenant?** If yes, F164 is Medium and needs a
database guard before tenant N+1 is public; if no, it closes as stray test data. **This session traces and
decides; it does not build a guard** (that would be its own session, F109's trigger as the precedent).

**Re-checked at planning (2026-10-06):** G-A and G-B are done (§ 2a, § 2c), so this is next in the order
that needs no Phase 6 decision. F165's soak has not started (`check-dates-state.json` still dated
2026-10-02), so G-E is not ready. F164's record (technical-reference § 13) gives the two staging rows:
`16bfdcb6…` (Power Rangers Unlimited #5, `84428401340605011`, non-admin test account, 2026-09-11 22:56Z)
and `ef0b74f3…` (Amazing Spider-Man #1004, `75960623001300411`, test admin, 22:55Z); both carry the
founding `tenant_id` and point at `demoshop` catalog rows. Production had 0 of 3,495 on 2026-09-29.
**Two cheap facts from planning:** no local harness or fixture mentions either item code or title, and
the fixtures' service-role catalog lookups all key on an id or the `ZZTEST` prefix, so no fixture is an
obvious culprit. The 22:55Z window falls the evening before the 2026-09-12 admin-badges commits, whose
Playwright runs raced and were interrupted (CLAUDE.md records it); that is a lead, not a finding.

**Scope IN:** read-only reads on both projects; one constructive reachability test on **staging only**
with a throwaway user, torn down; Rick-run read-only SQL for policy, function and trigger text; § 13 and
doc updates; deleting the two stale staging rows **only on Rick's go**. **Scope OUT:** any guard, trigger,
policy or RPC change; any production write; client code; F150. Stop and ask for anything else.

### Step 0 — preflight (agent)

`/preflight`; `git branch --show-current` = `staging`. Read technical-reference § 4.4 (`preorders`),
§ 7.1 (RLS), § 13 F164 and F109 (`/sql-check`).

### Step 1 — what the two rows and their users are (agent, service role, staging, read-only)

Read both `preorders` rows in full; their `catalog` rows (`tenant_id`, `catalog_month`, `created_at`);
both users' `user_profiles` (`tenant_id`, `is_admin`, `status`, `created_at`) and auth user `email` prefix
and `created_at`. **Do not print full emails**; the prefix (`pw-…`, `pw-admin-…`, a person) is what
identifies the source. Record whether either user still exists.

### Step 2 — the discriminating test: did the app write them?

`Preorders.add()` logs a `reserve` usage event through `UsageEvents.reserve()` (`app.js` ~1152; metadata
carries `title`, `distributor`, `catalog_month`, no catalog id). Query `usage_events` for each user,
`event_type = 'reserve'`, between 22:45Z and 23:05Z on 2026-09-11, and compare `metadata.title` and the
event's `tenant_id` with the row.
- **A matching `reserve` event** → the write came through the app's client path: go to Step 3 to find
  how the page got hold of a `demoshop` catalog id.
- **No event** → a service-role or direct REST write (a harness, a script, a hand query). Note it, then
  still run Step 3, because the question G8 asks is whether the client path **can**, not whether it **did**.
State plainly that the event write is fire-and-forget (`.catch(() => {})`), so its absence is strong
evidence, not proof.

### Step 3 — read the live boundary (Rick runs read-only SQL on staging AND production; paste results)

```sql
-- policies on the two tables that matter
SELECT tablename, policyname, cmd, roles::text, qual, with_check
FROM pg_policies WHERE schemaname = 'public' AND tablename IN ('preorders', 'catalog')
ORDER BY tablename, policyname;

-- what current_tenant_id() actually reads (profile row, JWT claim, ...)
SELECT pg_get_functiondef('public.current_tenant_id()'::regprocedure);

-- triggers on preorders (F109's ordered-cancel guard should be here; is anything checking catalog tenancy?)
SELECT tgname, pg_get_triggerdef(oid) FROM pg_trigger
WHERE tgrelid = 'public.preorders'::regclass AND NOT tgisinternal ORDER BY tgname;
```

Agent compares the two environments and records: does any INSERT/UPDATE `with_check` or trigger relate
`catalog_id` to the row's `tenant_id`? Is `catalog` SELECT tenant-scoped for `authenticated` (and, given
F150, is there any `anon` policy)? Expected from the docs: no check relates them.

### Step 4 — constructive reachability test (staging only, throwaway user)

The real boundary is the REST API with a user's JWT, not the page, so test that directly:
1. Create a throwaway **founding-tenant** customer (active, non-admin) with a password grant (F107; no
   magic link), the way `admin-tab-counts-pending-verify.mjs` does.
2. **Can it see a foreign catalog id?** With its JWT, `GET /rest/v1/catalog?select=id&tenant_id=eq.<demoshop>&limit=1`.
   Record the count. (If 0, an attacker must learn an id elsewhere: note where ids appear to a customer,
   e.g. URLs or anon-readable surfaces, without hunting further.)
3. **Can it write one?** Take a `demoshop` catalog id **from the service role** and, with the user's JWT,
   `POST /rest/v1/preorders` `{ user_id: <self>, catalog_id: <demoshop id>, tenant_id: <founding>, quantity: 1 }`.
   Also try the mirror (`tenant_id: <demoshop>`), which RLS should refuse.
4. **Negative control:** the same POST with a **founding** catalog id must succeed (so a refusal in 3 means
   the guard worked, not that the request was malformed).
5. Teardown: delete every row the test created (service role), then the user; fresh read 0 rows, auth 404.

**Result rule.** 3 succeeds → **reachable**: F164 becomes **Medium**, and a cross-tenant write needs
nothing more than a known catalog id. 3 refused while 4 succeeds → **not reachable** through the API
boundary; the two rows came from a privileged writer.

### Step 5 — sweep (read-only, both environments)

Cross-tenant references in every table with a `catalog_id`: `preorders`, `usage_events` (nullable),
`weekly_shipment` (nullable), plus `reservation_history` if it carries one (check § 4 first). Count rows
whose `catalog_id` resolves to a catalog row of a different `tenant_id`, paged with `content-range`
verified. Production is read-only. Expected: staging 2 in `preorders`; production 0.

### Step 6 — ⏸ PAUSE → Rick, then record

Present: which path wrote the rows, whether the API boundary allows it, the sweep, and the recommendation.
- **Reachable:** file the severity change in § 13 F164 (Medium), and write a guard design into this doc
  as a later session (a `BEFORE INSERT OR UPDATE OF catalog_id, tenant_id` trigger on `preorders` raising
  when `catalog.tenant_id <> NEW.tenant_id`, F109's shape; consider the same for `subscriptions` only if
  it references catalog rows). G8 stays open until that guard ships.
- **Not reachable:** F164 closes as stray privileged-writer data; G8 closes.
- **Either way, Rick's call:** delete the two staging rows (they still skew the pre-v2 parity check and
  will mislead the next reader). If yes, guarded delete by exact id, fresh read 0.

Record: § 13 F164 (trace, boundary text from both environments, test results, disposition), this doc's
§ 2e result and STATUS token, the Phase 6 Readiness G8 row, CLAUDE.md's F164 row. Doc-only commit to
`staging`, pushed. `/wrap-up`.

### Completion criteria (G-D)

- [ ] Both rows, their catalog rows and both users identified (email prefixes only)
- [ ] `reserve` usage-event check done for both rows, result stated with its limit
- [ ] Policies, `current_tenant_id()` and `preorders` triggers read on BOTH environments
- [ ] Reachability test run on staging with its negative control; test user and rows torn down, fresh read 0
- [ ] Cross-tenant sweep run on both environments for every `catalog_id` table
- [ ] Rick's disposition recorded (Medium + guard session planned, or closed); the two staging rows deleted or kept by his call
- [ ] § 13 F164, Readiness G8, CLAUDE.md row, this doc's STATUS updated; `/wrap-up` produced

---

## 3. Decisions only Rick can make (with recommendations)

| # | Decision | Recommendation |
|---|---|---|
| **D1** | Reverse Q3 (Shape D → open a Phase 6 track)? | **Not yet.** Run G-A, G-B, G-D now (they pay off under Shape D), then G-C, whose cost answer is the input Q3 actually lacks. Decide D1 with G-C's result in hand |
| D2 | G5 / F131 — the stub's goal says "no operator in the loop", but every catalog comes from one operator's portal access | Accept the operator for the first cohort explicitly and **reword the goal**: self-serve signup to a branded *trial* site; catalog import stays operator-run until F131 is solved. Matches the stub's own eligibility hybrid. Otherwise F131 blocks Phase 6 indefinitely |
| D3 | Eligibility verification method | Self-attest + operator-confirm for the first cohort (the stub's recommended hybrid); revisit automation later |
| D4 | Serving model | After G-C. Stub's lead: (a) wildcard subdomain, (b) vanity domains as paid opt-in later |

---

## 4. Notes for the later sessions (enough to plan them; each gets its own plan doc when its turn comes)

**G-B.** *(Superseded by the full runbook in § 2b, 2026-10-06; this paragraph was the planning sketch.)*
Remove `webhookSecret` (lines ~177/196/347 of `register-tenant/index.ts`): `settings: {}` on
insert, drop `webhook_secret` from the response; update `tenant-onboarding-runbook.md` Step 1's expected
response (it currently tells the operator to save `webhook_secret`). Grep the local Playwright folder
(via Bash) for consumers of `webhook_secret`. Deploy to staging after measuring `verify_jwt` **by
behaviour** (unauthenticated POST: the function's own `{"error":"Unauthorized"}` = OFF; the gateway's
`Missing authorization header` = ON), keep it, read the artifact back with `functions download` and
hash it. Verify with a throwaway tenant (the `f72-s0-plan-allowlist.mjs` V11s pattern): settings has no
key, `invite_sent: true`, FK-ordered teardown, 0 orphaned auth users by fresh read. Then Rick's explicit
`/promote-prod` (functions + docs only; F125 checks; config.js absent), then production deploy of
`register-tenant` **and** `register-customer` (S2a, already on `main`) with the same behaviour probe and
artifact hash against `origin/main`. Production end-to-end: `register-customer` is Turnstile-gated and
cannot be scripted; a real check is Rick signing up a test customer on `comicstore` and declining it
after — Rick's call, otherwise an accepted residual stated plainly. Closes F151 and F153's production half.

**G-C.** Questions, in order: (1) can a Pages project accept a wildcard custom domain at all, from
Cloudflare's current docs — do not assume; (2) if not, a Worker on route `*.pulllist.app/*` fronting
the Pages project with a proxied wildcard record, and whether Universal SSL's first-level wildcard
covers it; (3) Cloudflare for SaaS custom-hostname pricing for (b). Safety facts to verify, not assume:
explicit records (`rjbookstop`, `comicstore`, `send`, `mta`, `resend._domainkey`, `ms1/ms2._domainkey`)
take precedence over a wildcard, and a wildcard CNAME would answer **every record type** for
non-existent names (check DMARC/SPF lookups on random subdomains). A wildcard on `*.spike.pulllist.app`
is second-level and is **not** covered by Universal SSL, so it is not a free test label. **⏸ PAUSE before
publishing any record**; output is a decision record with prices, not code. `TenantContext`/pre-paint
script behaviour for an unknown slug (what `<new>.pulllist.app` renders before the tenant exists) is
part of the answer.

**G-D.** The two staging rows (founding `tenant_id`, `demoshop` `catalog_id`, test accounts,
2026-09-11). Hypothesis to test first: a user whose profile tenant differs from the URL tenant
(`?t=demoshop`) — the catalog is read under one tenant and `Preorders.add()` writes
`TenantContext.current().id` from another. Does RLS's `preorders` INSERT check pin `catalog_id` to the
same tenant? If a client path can produce it, F164 becomes Medium and needs a DB-side guard (trigger or
policy), which matters the day tenant N+1 is public.

**G-E.** Already planned: `docs/f165-withdrawal-detection-redesign.md` § 4, § 8. Offer `/schedule-gate`
for the second weekly run so the soak does not depend on memory.

**G-F.** Design source: `docs/f72-multi-tenant-branding.md` § 4.2 (S2) and § 0.1 (tier rules; Q10 flat
sender). `reset-password` holds no tenant reference at all (§ 4.2.2), so it needs a tenant lookup first.

**G-G.** Design source: `docs/f157-distributor-scoping.md` § 4.4 (F169) and the embedded migration
(DROP + CREATE in one transaction; REVOKE from `anon`/`authenticated`, F124). Verify the open question
there: does the shipment path still "require both invoices" since `f5fb6f0`?

---

## 5. Reference

`docs/phase-6-self-service-signup.md` (gates, stub) · `docs/pre-phase-6-consolidation-wave-2.md` § 0
(Q3) · `docs/technical-reference.md` § 4.1, § 13 · `docs/tenant-onboarding-runbook.md` ·
`docs/f72-multi-tenant-branding.md` · `docs/f157-distributor-scoping.md` ·
`docs/f165-withdrawal-detection-redesign.md`.
