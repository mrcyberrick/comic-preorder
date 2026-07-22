# CLAUDE.md — Project Instructions for PULLLIST

This file provides persistent context for Claude when working on the PULLLIST
comic pre-order system. **Read this file in full at the start of every session.**

---

## 🚨 Current Migration Phase

**Active phase:** **Phase 5 Complete** (closed 2026-07-15). Successor Phase 6 has not started — see below.
**Successor phase (stub):** Phase 6 — Open self-service tenant signup — `docs/phase-6-self-service-signup.md` (stub 2026-06-15; not started; gated on a wildcard-DNS/TLS spike). Phase 5's close (2026-07-15) satisfies the "begins only after Phase 5 closes" precondition; the wildcard-DNS/TLS spike gate remains open.
**Phase 3 status:** Complete — 3.1–3.7 closed 2026-05-13; 3.8 hardening closed 2026-05-15 (one-day soak clean)
**Phase 4 status:** **Complete** — 4.0–4.8 closed 2026-05-26 → 2026-06-10; completion audit closed 2026-06-10 (all Phase Completion Criteria ticked; recovery anchors verified — see `pre-multitenancy-state.md` § Phase 4 Completion)
**Phase 5 status:** **Complete — 2026-07-15.** All sub-deploys 5.0–5.5 closed; second tenant (`comicstore`, `comicstore.pulllist.app`) live on production, pilot/seeded; two-tenant soak passed (2026-06-20 → 2026-07-15, one full monthly import cycle 2026-07-08→10 elapsed, post-import isolation re-verification = 0 cross-tenant in both directions); onboarding generalized into `docs/tenant-onboarding-runbook.md`. Full completion evidence: `docs/phase-5-second-tenant-onboarding.md` § Phase Completion Criteria; `docs/phase-5.5-second-tenant-onboarding.md` § 5 / Deploy Log; `docs/phase-5.5-soak-log.md` § S4 close.
**Active sub-deploy:** none. Phase 6 not started (stub only, gated on the wildcard-DNS/TLS spike).
**Plan (Phase 5 parent):** `docs/phase-5-second-tenant-onboarding.md`
**Plan (Phase 4 parent):** `docs/phase-4-production-migration.md`
**Plan (Phase 3 parent):** `docs/phase-3-tenant-resolution.md`
**Last completed sub-deploy:** Phase 5.5 — Second-tenant onboarding + soak (Complete 2026-07-15) — `docs/phase-5.5-second-tenant-onboarding.md`. Tenant 2 (`comicstore`) live on prod via `register-tenant`; dedicated `comicstore.pulllist.app` custom domain + TLS; branding set; zero cross-tenant leakage verified (S3, re-confirmed post-import at S4 close); two-tenant soak passed across one full import cycle; onboarding runbook generalized (S5). Also corrected a stale F34-residual doc claim discovered during S6 verification (see `technical-reference.md` § 13 F34) — `create-paper-customer`/`invite-customer` were never actually hard-pinned post-2026-05-10; three docs (technical-reference.md, soak log, runbook) had carried the stale pre-fix description forward.
**Last completed phase:** Phase 5 — second tenant live on production with a verified two-tenant soak; onboarding is now operational, not an engineering phase
**Phase 2 reference:** `docs/phase-2-completion.md`
**Phase 1 reference:** `docs/phase-1-schema-migration.md`, `docs/pre-multitenancy-state.md` (§ 2/§ 4 superseded by `docs/production-baseline-2026-05-28.md`)

**Phase 5 sub-deploy index:** 5.0 housekeeping → 5.1 hosting migration → 5.2 slug→id routing RPC → 5.3 per-tenant branding → 5.4 tenant signup (incl. `register-customer` un-pin) → 5.5 second-tenant onboarding + soak. All Complete. Sequencing rationale and completion criteria in the parent plan.
**Open findings:** F72 — `register-customer` email template stays founding-branded (deferred; multi-tenant email branding out of Phase 5 scope; re-confirmed deferred at Phase 5 close — now a prerequisite for tenant-2's real-customer go-live, per `docs/tenant-onboarding-runbook.md`). F89 — paper→app conversion is unmeasurable: `claim-paper-customer` deletes the paper rows on success and no usage_event records claims or invites (filed 2026-07-19; deferred to a future instrumentation session; see § 13 F89). F90 — `usage_events` 90-day purge forecloses adoption-trend analytics; needs a per-tenant monthly rollup snapshot written at import (filed 2026-07-19; deferred to a future schema + import-script session; see § 13 F90). F91 — GoTrue Admin API intermittently rejects new-generation `sb_secret_` keys with a JWT-parse error, breaking the local Playwright suite's auth fixtures (filed 2026-07-22 during the apex-marketing S5.3 gate; test-infra only, no live app impact; deferred to a future test-infrastructure session; see § 13 F91). F92 — `technical-reference.md` carries pre-Phase-5 claims outside the tenant-resolution contract (stale "no second tenant"/"GH Pages warm"/import-script-hardcodes claims; filed 2026-07-22 at apex-marketing S5.7; deferred to a dedicated re-audit session; see § 13 F92). **The `import.js` maintenance session (F75 key rotation + F78 historical dedup + F85 cross-month root fix) closed 2026-07-15 — plan: `docs/import-js-maintenance-f75-f78-f85.md`.** **The F86 prod legacy API key retirement session (config.js publishable-key migration + legacy-toggle flip; incl. F88, surfaced and resolved mid-session) closed 2026-07-22 — plan: `docs/f86-anon-key-migration.md`.** All other findings through F92 are resolved — full entries and statuses live in `docs/technical-reference.md` § 13 (canonical findings index; the F76 distributor-agnostic display match remains as defense-in-depth post-F84). Next free finding ID: **F93**.

Before proposing any work, read the active phase docs and confirm the proposed
change is in scope. **If something seems related but isn't on the IN scope list
in the active sub-deploy plan, stop and ask** rather than fixing it inline.

---

## 🚨 CRITICAL RULES — READ FIRST

### Staging Only
**All code changes, file generation, and deployment guidance target staging ONLY,**
except inside an explicitly-named Phase 4 cutover-window sub-deploy.
- Never suggest pushing directly to `origin main` outside a cutover sub-deploy
- Never open PRs to production unless the user explicitly requests a production
  promotion AND confirms staging tests have passed
- Every session assumes work starts on the `staging` branch
- Always remind the user to smoke test on staging before promoting to production

### Credential Safety
**`config.js` is tracked per-branch with different values on each branch.**
This is intentional: production `main` holds the prod anon key; `staging` holds
the staging anon key. The deployment workflow uses `git checkout main -- config.js`
during a staging→main merge to preserve the prod-branch values.

- The Supabase anon key is **public by design** and safe in committed client code.
  RLS is the security boundary, not key secrecy. Do not treat a committed anon
  key as a credential leak or propose `git rm --cached` on it.
- The agent never edits `config.js` and never proposes credential values.
- Service-role keys are different — they bypass RLS and **must** stay local-only,
  in the scripts folder, never in any repo.
- If a feature needs a new key in `config.js`, add it manually to both branches
  before any merge. The `git checkout` step preserves existing prod values; it
  does not propagate new keys.

### Document Integrity (the rule that prevents the most rediscovery)
**Planning artifacts (sub-deploy plans, runbooks, baseline docs) are committed
to the repo immediately on creation, before the next session begins.**
Uncommitted planning files in the working tree are a known drift source — they
get overwritten, reverted, or accidentally clobbered between sessions. Treat any
uncommitted planning doc as not-yet-real until it lands in git.

- Doc-only commits go to `staging` directly, never bundled into a feature branch
  for sub-deploy work
- Reference docs that describe live state (schema baselines, function inventories,
  finding statuses) include a "last verified against live: DATE" line. If that
  date is stale or absent, **re-audit against live before relying on the doc** —
  for production-touching work especially, the live database is authoritative,
  the doc is a snapshot
- Contradictions discovered in this file or any reference doc are surfaced as
  findings, not worked around silently

### File Drift Prevention
**Always work from actual current files, not from memory or earlier sessions.**
- In chat sessions: ask the user to upload any files that will be modified
- In agentic sessions: re-read files from disk at session start; `Select-String`
  or `view` the target range before any `str_replace`; halt if `old_str` does not
  match byte-exactly
- Never assume outputs from a previous session match what's currently in the repo
- After generating updated files, remind the user to copy them to the repo before
  committing — and to verify any live status cells haven't been advanced by a
  CLI session since the chat output was generated

### Definition of Done — Merge Gate
A sub-deploy is mergeable to `staging` **only when all of these are true**:
- Its plan's Completion Criteria checkboxes are all ticked
- Any soak period is fully elapsed (a 3-day soak means three calendar days, not
  "checks green so far at day 2")
- Verification gates (V1, V2, … V*N*) are all green
- Any canary tenant or test fixture is torn down (verify with a live SELECT
  returning zero rows — not "we ran the teardown SQL")
- The parent-plan status cell is updated to **Complete** with the date
- `CLAUDE.md` § Current Migration Phase active-sub-deploy pointer is advanced

**"Most of the work looks done" is not done.** Never merge a sub-deploy whose
plan still has unchecked completion boxes. Merges to `staging` use `--ff-only`
(clean linear history; no merge commits).

---

## 🚨 Environment Facts (stated once, never rediscovered)

### Shell
- **PowerShell is the primary shell; Claude Code also provides a separate Bash
  tool.** Use each tool with its own native syntax — never run PowerShell
  cmdlets through the Bash tool, and never invoke `powershell -Command` from
  Bash. Prefer PowerShell for Windows/git/deploy mechanics; Bash only for
  genuinely POSIX one-liners.
- In PowerShell use `Select-String` (not `grep`), `Measure-Object` (not `wc`),
  `Get-Content | Select-Object -Skip N -First M` (not `sed`)
- Quote paths containing parentheses: `cd "C:\Users\richa\OneDrive\Documents\(Work)\BookStop\..."`
- PowerShell does not support `&&` — run git commands on separate lines

### What's tracked vs local-only

| File / location | Tracked? | How edits happen | How edits verify |
|---|---|---|---|
| `app.js`, `*.html`, `style.css`, `config.js`, `docs/**`, `supabase/functions/**`, `CLAUDE.md`, `README.md` | Tracked per branch | `str_replace` + commit | `git diff` + smoke test |
| `import.js`, `import-staging.js` | **Private scripts repo** (`github.com/mrcyberrick/comic-preorder-scripts`; the `scripts/` folder is its working tree — since 2026-07-08) | `str_replace` + commit | `node --check` + `--no-write` dry run + `git diff` |
| `test-magic-link.ps1`, `test-this-week.ps1`, playwright suite, `.env`, canary scratch files, `phase-4-prod-tenant-uuid.txt`, `security-findings-local.md` | Local-only (allowlist `.gitignore` in the scripts repo enforces this) | Direct edit | Run-test |

The import scripts are credential-free as of 2026-07-08: service keys and
tenant UUIDs load from the scripts folder's gitignored `.env`
(`IMPORT_SERVICE_KEY[_PROD]`, `IMPORT_TENANT_ID[_PROD]`, `SUPABASE_URL[_PROD]`
— see `.env.example`), and each script hard-fails on a missing var or a URL
pointing at the wrong project. The `.env` and all scratch/schema/test files
remain local-only and must never be committed to any repo.

### Supabase platform facts
- **Anon key is public by design.** RLS is the security boundary. A committed
  anon key in `config.js` is not a finding.
- **Service-role key bypasses RLS.** Lives only in local scripts; never in
  client code or any committed file.
- **Edge Functions follow off-plus-in-body-auth.** JWT verification disabled at
  the platform level is the recommended pattern; in-body `Authorization` header
  verification (`/auth/v1/user` → profile lookup) is the actual gate. JWT-off is
  not a misconfiguration. The exception is `register-customer` and any other
  intentionally-public endpoint.
- **Supabase SQL Editor runs as `postgres` superuser** — it bypasses RLS. To
  test RLS isolation, simulate an authenticated user with `SET LOCAL role
  authenticated` and `SET LOCAL "request.jwt.claims"` inside a transaction.

### Database project URLs
| Environment | URL | Project ref |
|---|---|---|
| Production | `https://plgegklqtdjxeglvyjte.supabase.co` | `plgegklqtdjxeglvyjte` |
| Staging | `https://puoaiyezsreowpwxzxhj.supabase.co` | `puoaiyezsreowpwxzxhj` |

**Founding tenant UUID (staging):** `72e29f67-39f7-42bc-a4d5-d6f992f9d790`
**Production founding tenant UUID:** generated during 4.2; lives in scratch file
`scripts/phase-4-prod-tenant-uuid.txt` (gitignored).

### SQL authoring rules (added 2026-07-15 after repeated schema-guess errors)
Before writing ANY SQL or PostgREST query, read `docs/technical-reference.md`
for every table touched — never write column names from memory. Traps that have
each cost a failed iteration: `catalog` uses `price_usd` (not `price`) and
requires `catalog_month`; the distributor enum is exact-case `Lunar` / `PRH`;
admin views match titles on `item_code` (`upc` is null for some titles); every
INSERT passes `tenant_id` explicitly. For multi-row seeds, dry-fit ONE row and
verify it before running the rest. (Local skill: `/sql-check`.)

---

## 🚨 Anti-Drift Rules for Agentic Sessions

These rules apply to any agentic session (Claude Code CLI, Claude in VS Code, etc.).

### One sub-deploy per session
A session targets exactly one sub-deploy from the active phase plan. Do not bundle
changes from multiple sub-deploys, even if they look related.

### Stop and ask, don't fix inline
If you discover a real bug out of scope for the active sub-deploy:
1. Stop work
2. Describe the bug
3. Ask whether to (a) fix it now as a separate commit, (b) file it for later, or (c) ignore it
4. Wait for explicit answer before proceeding

This applies even when the bug blocks your testing. The user decides scope expansion,
not the agent.

### Verify before escalating
Distinguish "I observe X" from "X is a problem requiring remediation."
- For platform-behavior or security claims, verify against the live system or
  official docs before proposing action
- For findings filed in `technical-reference.md` § 13, use the next-available
  finding ID — never guess or reuse. Check the highest existing ID first
- A surprising query result triggers re-verification, not immediate remediation

### Runbook construction standards
- `old_str`/`new_str` blocks must match the actual file content byte-exactly.
  Verify the target range via `view` or `Select-String` before applying
- Verification grep counts are derived by counting occurrences in the `new_str`
  literally, never estimated from memory
- Each finding fix is a separate commit with the finding ID(s) in the message
- A failed pre-check or verification is a halt-and-report, never an improvise

### Status update — end every session
Before the session closes, produce:
- What was changed (files + line ranges, or SQL run)
- What was verified (queries run, smoke tests passed)
- What is left for the next session
- Any out-of-scope discoveries that were filed rather than fixed
- New finding IDs assigned, if any

### Never assume previous-session state matches current state
At session start, re-read the relevant files from disk. Do not infer file contents
from earlier sessions, from this `CLAUDE.md`, or from any reference doc.

---

## Response Discipline (chat sessions)

These guide the planning-side agent (chat), not the CLI runbook execution.

- Lead with the decision or action. Rationale follows and is bounded. Full detail
  belongs in artifacts (plans, runbooks) and explicit requests, not every turn
- Edit documents in place with targeted changes. Never regenerate a full document
  to alter a few lines; surface changed sections plus a one-line summary of what
  changed
- Offer one recommended next step, not a menu of options, unless the user asks
  to choose
- Do not restate settled context or re-litigate settled decisions; point to where
  a decision was logged instead
- Only runbooks instruct the CLI. Chat content is for planning and exploration;
  chat speculation is never a directive. When uncertain, say so and give a
  verification step rather than a confident wrong direction

---

## Session Opening Protocol

At the start of every session:
1. Read this file in full
2. Read the active phase plan referenced in § Current Migration Phase
3. Read the active sub-deploy plan
4. State which sub-deploy is being executed and confirm with the user
5. List files that will be modified and read them from disk before proposing changes
6. Confirm staging target

If any step 2–5 cannot be completed (file missing, plan not yet written, ambiguous
scope), stop and ask before proceeding.

At the end of each session:
- Remind the user to copy output files to the repo
- Remind the user to push to staging and smoke test before promoting to production
- Note any production database changes needed
- Note any local script updates needed (`import.js`)
- Produce the status update described in Anti-Drift Rules

---

## Project Overview

**App:** PULLLIST — comic pre-order system for Ray & Judy's Book Stop
**Phone:** 973-586-9182
**Location:** Rockaway, NJ
**Production URL:** https://pulllist.app/
**Staging URL:** https://staging.pulllist.pages.dev/
**Legacy prod URL:** https://mrcyberrick.us/comic-preorder/ (GitHub Pages — kept warm as a rollback surface past the original "until 5.5 closes" gate; Rick's call 2026-07-15 at 5.5 S6 was to keep it warm and revisit retirement in a future session, not tied to any phase boundary; redirects to `/` via `_redirects`)

---

## Repository Structure

```
comic-preorder/                    ← production repo (github.com/mrcyberrick/comic-preorder)
  catalog.html
  mylist.html
  arrivals.html
  subscriptions.html
  admin.html
  app.js
  style.css
  config.js                        ← tracked per branch; never edited by agent
  CLAUDE.md                        ← this file
  README.md
  supabase/functions/              ← all 8 Edge Functions (post-4.1 Session 1)
  docs/
    technical-reference.md         ← canonical schema + findings index § 13
    pre-multitenancy-state.md      ← § 1, § 3, § 5 still valid; § 2/§ 4 superseded
    production-baseline-2026-05-28.md  ← live audit; supersedes stale snapshot
    phase-*.md                     ← phase parent plans + sub-deploy plans
```

**Git remotes:**
- `origin` → production repo (`github.com/mrcyberrick/comic-preorder`)
- `staging` → staging repo (`github.com/mrcyberrick/comic-preorder-staging`) — **no longer a deploy target as of 5.1**; kept warm as rollback past the original "until 5.5 closes" gate — Rick's call 2026-07-15 at 5.5 S6 was to keep it warm and revisit retirement in a future session

**Local scripts folder** (working tree of the **private scripts repo**
`github.com/mrcyberrick/comic-preorder-scripts` since 2026-07-08 — only the
import scripts, credential-free tests, and repo metadata are tracked; `.env`,
scratch state, and the Playwright suite stay local-only via the allowlist
`.gitignore`):
```
C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts\
  import.js                       ← production import script (tracked)
  import-staging.js               ← staging import script (tracked)
  test/                           ← credential-free unit suite (tracked; run: npm test)
  test-magic-link.ps1
  test-this-week.ps1
  phase-4-prod-tenant-uuid.txt    ← generated at 4.2 pre-flight
  phase-4.1-canary-uuids.txt      ← canary tenant identifiers (Session 2)
  phase-4.1-canary-teardown.sql   ← FK-ordered teardown for Session 3
  .env                            ← script credentials
  package.json
  playwright/                     ← local smoke suite
```

**Catalog CSV files:**
```
C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\
  Lunar_Product_Data_MMYY.csv
  YYYY_MM_PRH_metadata_full_active.csv
  normalized_catalog.json
```

---

## Tech Stack

- **Frontend:** Vanilla HTML/CSS/JS — no build step, no npm for the web app
- **Backend:** Supabase (PostgreSQL + Auth + Edge Functions + RLS)
- **Hosting:** Cloudflare Pages (static files only; migrated from GitHub Pages in 5.1)
- **Email:** MailerSend via Supabase Edge Functions
- **Import:** Node.js script run locally each month

Cloudflare Pages serves static files only — no SSR. All dynamic behavior is client-side
JS calling Supabase directly.

---

## Standard Deployment Workflow

Local skills `/deploy-staging` and `/promote-prod` encode this section's gates
step-by-step (plus `/preflight` for session-start checks) — prefer invoking
them over re-typing the flow.

```powershell
# Start a new feature
git checkout staging
git pull origin staging
git checkout -b feature/<description>

# Make changes, then commit
git add <files>
git commit -m "<type>: <description>"

# Merge to staging (fast-forward only — clean linear history)
git checkout staging
git pull origin staging
git merge --ff-only feature/<description>

# Run smoke tests before deploying
cd C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts\playwright
.\run-smoke.ps1
# Stop if anything fails — do not push

git push origin staging
# CF Pages auto-deploys the staging preview at https://staging.pulllist.pages.dev/
# (Do NOT run: git push staging staging:main — retired as of 5.1)

# Test at: https://staging.pulllist.pages.dev/
# When staging tests pass, promote to production:
git checkout main
git pull origin main
git merge staging --no-commit --no-ff
git checkout main -- config.js   # preserve prod credentials (config.js is tracked per-branch)
# Assert critical app files actually changed (catches merge-base regression — see F59):
foreach ($f in @('app.js', 'mylist.html', 'arrivals.html', 'admin.html')) {
    $diff = git diff "main:$f" "staging:$f" 2>$null
    if ($diff) { Write-Host "ok: $f differs from main (will update)" }
    else { Write-Host "WARN: $f identical to main — verify this is expected, NOT a merge-base regression" }
}
git commit -m "<type>: <description>"
git checkout -b feat/<description>-prod
git push origin feat/<description>-prod
# Open PR: feat/<description>-prod → main
# Verify config.js is NOT in the diff before merging
# CF Pages auto-deploys production from main at https://pulllist.app/
# Post-deploy write-smoke: reserve one item through the live app as a test user, confirm
# the row lands in prod preorders with correct tenant_id, then cancel it.
```

---

## Database Schema

The full current schema lives in `docs/technical-reference.md` — canonical source
of truth. Read it before making any schema-related claim.

**Do not infer schema details from this file or from earlier sessions.** The
schema changed materially in Phase 1 (multi-tenancy) and continues to evolve.

Quick orientation only:
- Multi-tenant via `tenants` table; every tenant-scoped table has `tenant_id`
  (staging post-Phase-1; production after 4.2 lands)
- RLS enforces tenant isolation via `current_tenant_id()` + `current_user_is_admin()`
- Import script uses service-role key (bypasses RLS); web app uses anon key
- Founding tenant UUIDs documented in § Environment Facts above

**Post-Phase-3.3 (staging):** `tenant_id` column defaults removed. Every INSERT
must pass `tenant_id` explicitly. The only exception is the defensive try/catch
in `UsageEvents._log()` which falls back to `FOUNDING_TENANT.id` if
`TenantContext.current()` is called before `resolve()` completes.

---

## app.js Structure

Source of truth: read `app.js` directly. Major API objects on `window`:
`Auth`, `Catalog`, `Preorders`, `Subscriptions`, `Settings`, `AdminContext`,
`NavBubble`, `TenantContext`, `Maintenance`. Read the file before making claims
about specific method signatures — this file deliberately does not duplicate
the API surface to avoid drift.

**Post-Phase-3.1:** `TenantContext` resolves the active tenant on page load.
`initNav()` calls `TenantContext.resolve()` before any other init.

**Post-Phase-3.2:** All `app.js` writes pass `tenant_id` explicitly using
`TenantContext.current().id`.

**Maintenance mode:** `Settings.isMaintenanceMode()` reads `app_settings.maintenance_mode`
on every authenticated page load. When true, `checkMaintenanceMode()` replaces
`document.body` with a holding-page banner and throws to halt page init for
non-admins. Write-blocking by construction. Admins always get through.

---

## Key Business Logic

### Catalog Month Scoping
- **My List table:** current catalog month reservations only
- **Upcoming Arrivals section:** all future reservations across all months
- **Admin dashboard:** stats + tabs scoped to current catalog month
- **This Week** (nav badge, arrivals page, admin bagging tab): Mon-Sun calendar
  week containing today's local date. Shared helper `DateUtils.weekRange()` in
  `app.js` is the single source of truth. Wednesday is not special; do not
  introduce Wednesday-anchored logic.

### Local Date Pattern
Always use local date parts (not `toISOString()`) to avoid UTC timezone shift.
Use `DateUtils.todayLocal()` for today's date and `DateUtils.weekRange()` for
the Mon-Sun window. Never reintroduce `toISOString()` for date comparisons or
date display — see F28 in `technical-reference.md` § 13.

### Past Item Auto-Hide
Items from previous months where `on_sale_date < today` are hidden from My List
(client-side filter in `mylist.html`).

### Series Subscriptions
- Subscribe button appears only on standard covers (`variant_type` null,
  `'Standard'`, or `'Primary Title'`)
- Hidden in admin impersonation context — **exception (2026-07-19):** the
  reserved-suggestions list on `subscriptions.html` stays visible during
  impersonation (it shows the impersonated customer's unsubscribed reserved
  series) with its subscribe buttons disabled, per Rick's explicit decision
  in `docs/subscription-reserved-suggestions.md` § 4c
- Import script auto-reserves standard covers for subscribers each month
- `subscriptions.html` shows an always-on "Series you're already reading"
  one-click subscribe list built from the customer's own reservations; the
  hand-curated "Popular at Book Stop" section was removed 2026-07-19 and
  `app_settings.popular_series` is no longer read by the app

### Variant Type Handling
- Lunar standard: `variant_type = 'Standard'` or null
- PRH standard: `variant_type = 'Primary Title'` or null
- All others are variants — no subscribe button

---

## Monthly Import Script Behavior

The import script (`import.js` / `import-staging.js`) runs locally each month:

1. Reads Lunar + PRH CSV files
2. Normalizes records (post-Phase-1 includes `tenant_id`)
3. Detects new vs same vs older catalog month (post-4.0 staging)
4. On new month: archives reservation history, purges stale unreserved rows
5. **Upserts** catalog records (preserving UUIDs — critical for preorder integrity)
6. On new month: removes items dropped from distributor catalog since last import
7. Auto-reserves standard covers for subscribers (skipped on older-month backfills
   or with `--skip-autoreserve`)
8. Optionally imports weekly shipment invoices into `weekly_shipment`
9. Prompts to send customer notification emails

**Both scripts pass `tenant_id` everywhere** (upsert key, normalized records,
auto-reserve inserts, `p_tenant_id` to all RPC calls) and are tenant-aware and
credential-free (`.env`-driven since 2026-07-08; production was patched in
sub-deploy 4.5). Both are versioned in the private scripts repo, which carries
a credential-free unit suite (`npm test` in the scripts folder — shipment row
builders + prod↔staging parity; see `test/README.md` there).

Re-running either script on the same month is safe — upsert in place;
auto-reserve detects existing reservations and skips.

---

## Edge Functions

All 8 functions are in the repo at `supabase/functions/*` (post-4.1 Session 1).
Tenant-aware as of Phase 2 + 4.1 hardening:
- `notify-customers` — in-body admin auth (F47); recipient list scoped to caller's tenant
- `create-paper-customer` — in-body auth; JWT-off platform setting (post-4.1 C13)
- `invite-customer` — in-body auth; explicit `tenant_id` + inline HTML template
- `register-customer` — explicit `tenant_id` (intentionally pinned to founding;
  Phase 5 will revisit for self-service signup)
- `send-my-list` — in-body auth + caller identity check (F51, F54); tenant-scoped queries
- `claim-paper-customer` — in-body auth; PATCHes tenant-scoped (F50)
- `approve-customer` — PATCH-only on existing rows; tenant inherited from row
- `reset-password` — public endpoint by design

`FOUNDING_TENANT_ID` secret must be set in Supabase staging → Edge Functions →
Secrets for tenant-aware functions to work.

---

## Known Out-of-Scope Items

Pending or deferred work — do NOT touch in agentic sessions without explicit
approval.

### Deferred — feature not in active use
- **Partial fulfillment not representable** — product decision, deferred until
  product scoping

### Deferred — separate future session
- **Analytics conversion instrumentation (F89)** — log claims/invites so
  paper→app conversion is measurable (Edge Function touch). See
  `docs/technical-reference.md` § 13 F89.
- **Analytics monthly rollup (F90)** — per-tenant monthly snapshot written at
  import so adoption trends survive the 90-day purge (schema + import
  script). See `docs/technical-reference.md` § 13 F90.
Phase 5 (all sub-deploys 5.0–5.5, incl. the slug→id RPC, per-tenant branding,
self-service tenant signup, and second-tenant onboarding) closed 2026-07-15 —
no longer listed here. See `docs/phase-5-second-tenant-onboarding.md` for the
full closed scope and `docs/technical-reference.md` § 13 for any findings
carried forward.

The `import.js` maintenance session (F75 key rotation, F78 historical dedup,
F85 cross-month root fix) closed 2026-07-15 — no longer listed here. See
`docs/import-js-maintenance-f75-f78-f85.md` for the full closed scope.

The F86 prod legacy API key retirement session (staging rehearsal, prod
`config.js` migrated to a publishable key via PR #80, one weekly shipment
cycle quiet window, prod legacy-key toggle flipped, both old legacy keys
confirmed dead) closed 2026-07-22 — **live in production**, no longer listed
here. F88 (edge functions' own service-role calls breaking post-toggle) was
surfaced and resolved within the same session — verified false on staging
(`notify-customers`) and prod (`create-paper-customer` against the real
founding tenant) both before and after the toggle flip; no Edge Function
code changes were needed. Closes the F75 residual. See
`docs/f86-anon-key-migration.md` for the full closed scope and evidence.

The analytics cycle-alignment session (cycle-anchored deltas on Executive +
Operations KPIs, "This Cycle vs Last" overlay chart, New Customers tile)
closed 2026-07-19 — **live on production**, no longer listed here. V1–V5
all green; merged ff-only to staging (`d6ee227`); promoted via PR #90
(`e250281`) 2026-07-19; post-deploy write-smoke passed (reserve → correct
prod `tenant_id` → cancel → row deleted). See
`docs/analytics-cycle-alignment.md` for the full closed scope.

The Analytics v2 engagement dashboard (full redesign of `analytics.html`,
ungated) closed 2026-07-16 — no longer listed here. See
`docs/analytics-v2-engagement-dashboard.md` for the full closed scope; F87
candidate (admin-logging doc/code contradiction) remains a separate open
filing decision, not part of this closure.

The subscription reserved-suggestions feature (always-on "Series you're
already reading" one-click subscribe list with Undo on `subscriptions.html`;
Popular section removed; admin impersonation sees a read-only list) closed
2026-07-19 — **live in production**, all V1–V5 green; promoted via PR #91
(`5167ab4`) at Rick's explicit request the same session; post-deploy
write-smoke passed. Subscribe paths on the page now carry `source`
attribution (`reserved_suggestion` / `series_search`).
`app_settings.popular_series` is now unused by the app (left in place, no
DB change, both environments). See
`docs/subscription-reserved-suggestions.md` for the full closed scope.

The subscription promotion feature (catalog banner + post-reserve subscribe
prompt) closed 2026-07-17 — **live in production**, no longer listed here.
All V1–V5 gates green; promoted via PR #86 (`107fc0a`) at Rick's explicit
request the same session; post-deploy write-smoke passed; final copy (no
separate perk/discount — Rick confirmed the informational copy as-is) live
on both staging (`raysandjudys`) and production (`rjbookstop`) founding
tenants, verified via the public `resolve_tenant_by_slug` RPC. See
`docs/subscription-promotion.md` for full scope and evidence.

If a session needs to touch any of the above, **stop and confirm**.

---

## Known Issues & Gotchas

- **PowerShell:** does not support `&&` — separate lines
- **PowerShell + Supabase:** `Invoke-RestMethod` mangles JSON quotes in argv and
  triggers 401s with `sb_secret_` keys. Use `curl.exe` with `--data-binary @file`
  for tenant-aware Supabase calls. See `test-magic-link.ps1`
- **OneDrive + PowerShell scripts:** OneDrive flags synced `.ps1` files as
  "downloaded from internet," blocking execution. Run `Unblock-File .\<script>.ps1`
  after each sync
- **Agent edits strip the UTF-8 BOM from `.ps1` files** — PowerShell 5.1 then
  reads the file as CP1252, and an em dash inside a double-quoted string decodes
  to `â€”` whose trailing `”` is a legal PS quote char: string boundaries silently
  shift and later code is swallowed into string literals with NO parse error
  (run-smoke.ps1 skipped its entire Playwright stage and exited 0, 2026-07-16).
  After ANY agent edit to a `.ps1`, restore the BOM and verify the script still
  reaches its last stage:
  `[IO.File]::WriteAllText($p, [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8), [Text.UTF8Encoding]::new($true))`
- **Supabase `range()`:** returns 416 on empty result sets — use count-first approach
- **UTC timezone shift:** never use `toISOString()` for date display — use local parts
- **Import script service key:** must be `service_role` (or `sb_secret_`), NOT
  anon — RLS blocks anon
- **`nav-hamburger`:** must be present in every HTML file's nav
- **RLS recursion:** admin policies referencing `user_profiles` via `EXISTS (SELECT
  ... FROM user_profiles)` cause infinite recursion → 500 errors. Use
  `current_user_is_admin()` SECURITY DEFINER. Already in place post-Phase-1
- **Supabase Auth admin `?email=` filter:** intermittent 500 ("Database error
  finding users"). Query `user_profiles` via PostgREST instead
- **`import-staging.js` was hot-patched 2026-05-08** for a `weekly_shipment`
  tenant_id NOT NULL violation — re-syncing from an earlier backup reintroduces
  the bug. See `phase-3-tenant-resolution.md` § Discovered During Soak

---

## Files That Must Stay in Sync

The nav block must be identical across `catalog.html`, `mylist.html`,
`arrivals.html`, `subscriptions.html`, `admin.html`. When updating nav, copy from
the most recently-updated file — the canonical version is whichever HTML file
was last touched.

The footer block must be identical across all five pages, placed immediately
before `<div id="toast-container"></div>`.

The `<script>` load order must be the same on every page: Supabase UMD bundle
→ `config.js` → `app.js` → page-specific code.

---

## Smoke Test Suite (local)

**Location:** `C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts\playwright\`
(local-only; never committed)

```powershell
cd C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts\playwright
.\run-smoke.ps1                              # full suite
.\run-smoke.ps1 -Headed                       # browser visible
npx playwright test 04-arrivals-this-week     # single spec
```

**Coverage:** magic-link auth, catalog reserve → mylist, cancel guards, arrivals
orphan-reserved rendering, subscriptions, admin bagging + week nav, tenant
isolation (F15, F20), per-tenant branding unit spec. `run-smoke.ps1` runs the
scripts repo's committed unit suite (`npm test`, step [1/2]) before Playwright;
the old local `node-tests/` copy was retired 2026-07-16.

**Rules:**
- Local-only. Never committed. Never runs against production.
- `SUPABASE_URL` in `.env` must be staging; runner aborts if it's prod
- All `goto()` calls use paths without a leading slash

Canonical detail: `docs/phase-3.7-playwright-smoke-tests.md`
