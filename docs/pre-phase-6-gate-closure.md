# Pre-Phase-6 gate closure — readiness re-check and session plan

**STATUS:** IN PROGRESS — G-A DONE 2026-10-06 (SQL only: `tenants_plan_check` and the F151 row cleanup applied on both environments; the F150 revoke deliberately NOT run, deferred by Rick); G-B runbook written 2026-10-06 (§ 2b), NOT STARTED; G-C..G-H NOT STARTED | staging=G-A 2026-10-06 | prod=G-A 2026-10-06 (SQL only, Rick-run) | findings=F150,F151,F153,F72,F164,F165,F169,F157,F170

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
| G-B | **Engine to production** — `register-tenant` stops minting the webhook secret (closes F151), then deploy `register-tenant` (F153 invite) + `register-customer` (F72 S2a) to production | rest of G7a, engine half of G3 | after G-A (**done**); `/promote-prod` needs Rick's explicit request. **Runbook: § 2b** | 1 session |
| G-C | **S0 serving-model spike** — wildcard `*.pulllist.app` + TLS on Pages; price (a) wildcard vs (b) CF-for-SaaS | G1 | none technically; **PAUSE before any DNS change** | 1 session, Rick in Cloudflare dashboard |
| G-D | **F164 creation-path trace** (read-only investigation) | G8 | none; can run in parallel with anything | ½ session |
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

## 2b. Session G-B — runbook (engine to production; written 2026-10-06, NOT STARTED)

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

- [ ] Step 0 re-measure matched; Step 1 rollback artifacts saved and hashed
- [ ] `register-tenant` edited; `grep webhook` shows only comments; committed via `--ff-only` to `staging`
- [ ] Harness control observed **red** on staging v22, then **green** after the staging deploy; invite harness `invite_sent` true; 0 orphaned auth users
- [ ] Staging `verify_jwt` OFF before and after; deployed artifact hash == committed source
- [ ] Runbook + technical-reference updated; F151 recorded
- [ ] `/promote-prod` run on Rick's explicit request, PR = `register-tenant/index.ts` + docs only (or explicitly not requested — then F151 stays staging-only and Steps 5–6 are carried forward)
- [ ] Production `register-tenant` and `register-customer` deployed from `origin/main`'s tree; `verify_jwt` OFF before/after both; artifact hashes == `origin/main`
- [ ] 6a and 6b run with teardown verified by fresh read, or each recorded as a skipped residual with Rick's reason
- [ ] Docs, CLAUDE.md and status token updated; `/wrap-up` produced

### Rollback

- Staging: `git revert` the fix commit and redeploy (`--no-verify-jwt`); nothing else depends on the field.
- Production functions: redeploy from Step 1's downloaded v10 / v33 with `--no-verify-jwt`.
- Production test rows from Step 6: the runbook's FK-ordered teardown.

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
