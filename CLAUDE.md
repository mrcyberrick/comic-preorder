# CLAUDE.md — Project Instructions for PULLLIST

This file provides persistent context for Claude when working on the PULLLIST
comic pre-order system. **Read this file in full at the start of every session.**

---

## 🚨 Current Migration Phase

**Active phase:** none. Phase 5 closed 2026-07-15 (all sub-deploys 5.0–5.5 complete; see
`docs/phase-5-second-tenant-onboarding.md`). Phase 6 — open self-service tenant signup — is a
**stub only** (`docs/phase-6-self-service-signup.md`), not started, gated on a wildcard-DNS/TLS
spike.
**Active sub-deploy:** none.
**Last completed work:** **Lighthouse performance sweep** RESOLVED on staging 2026-08-24 —
triggered by Rick asking why Performance scored consistently below 80 on both mobile and desktop.
Five items, **no finding ID filed** (fixed in-session rather than deferred, Rick's call — **F141 is
still free**). Measured against live production first, which localised three of Lighthouse's four
categories onto specific files instead of generic advice.

**Artwork (items 1, 2, 5).** Three assets were bitmaps in formats that could not compress them, two
of them wrapped in SVG: `favico.svg` was an Inkscape export around a 1254×1254 RGBA PNG — **931 KB
(710 KB brotli'd), linked from all eight pages and refetched on every load**, to be painted into a
16–32px tab slot; `comic-cover-fallback.svg` was 203 KB of SVG around a 300×450 base64 PNG for a
slot CSS renders at 150×225; `assets/hero.jpg` was a 1600×854 JPEG served full-size to phones.
Re-encoded in-session with Pillow (no GIMP/Inkscape round-trip needed) to `icon-192-v2.png`
(3,162 B) + `apple-touch-icon-v2.png` (2,939 B — new; iOS previously had no home-screen icon),
`comic-cover-fallback-v2.webp` (10,764 B), and `hero-v2.webp` (71,166 B) + `hero-mobile-v2.webp`
(31,784 B). Per page: **866,187 B → 13,926 B** on catalog/mylist/arrivals/etc., **845,694 B →
74,328 B** desktop / **34,946 B** mobile on the apex page.

**Fonts (item 4).** `style.css` opened with an `@import` of the Google Fonts CSS. An `@import` is
invisible to the preload scanner, so first paint waited on three strictly serialized round trips
across two cold origins (`style.css` → parse → `fonts.googleapis.com` → parse →
`fonts.gstatic.com`) — Lighthouse's 1,610 ms mobile / 510 ms desktop render-block. Replaced with
`preconnect` + a direct `<link>` in all eight heads; the `_headers` CSP already allowed both
origins, so no policy change was needed. **Do not reintroduce the `@import`** — a comment sits at
its old location in `style.css` saying so.

**Caching (item 3).** `_headers` only ever *shortened* lifetimes (`no-cache` on
`app.js`/`config.js`/vendor, for the F79 skew reason); everything else fell to Cloudflare Pages'
default `max-age=0, must-revalidate`. Added long lifetimes for static artwork in two groups.
**The `-vN` filename suffix is load-bearing:** files served `immutable` for a year carry it, and
re-exporting one REQUIRES bumping N and updating every reference — a year-long immutable cache on a
stable filename is a trap. `style.css` is deliberately in neither group: unfingerprinted and
deploy-variable, so the F79 reasoning that governs `app.js` governs it too.

**Verified 2026-08-24**: `node --check` clean on `app.js`, `shelf-order.js` and all 10 extracted
inline `<script>` blocks; full `run-smoke.ps1` — **269 unit + 139 Playwright, 0 failures, exit 0**,
both stages present in the log; every `_headers` path resolves to a real file; HTML diffs confined
to `<head>`, so the six-page nav/footer sync set is untouched. **Because essentially none of this
is spec-covered** — no spec asserts font rendering, cache headers or favicons — a separate
real-browser check against deployed staging confirmed what a green suite could not:
`document.fonts.check()` true for both families (no silent fallback to `sans-serif`), **exactly one
hero request per viewport** (so the `matchMedia` preload agrees with the stylesheet — no
double-download), and zero requests for the three deleted assets. Standalone perf work, not scoped
to any active sub-deploy. **Promoted to production 2026-08-24 via PR #132.** Prod verified
directly after deploy: all five new assets return 200 with `max-age=31536000, immutable`,
`style.css` no longer carries the `@import`, and every page's live `<link>` tags point at
`icon-192-v2.png` / `apple-touch-icon-v2.png`. *(A `favico.svg` string still greps in each head —
that is the explanatory comment, not a reference; the file is deleted and origin returns the
not-found fallback. Cloudflare's edge kept serving the orphaned object for a while under Pages'
7-day `s-maxage`, harmless since nothing links it.)* Production apex now scores **89 mobile / 98
desktop**, with `cache-insight` at **0 KiB** (was 1,576 KiB desktop / 555 KiB mobile) and
`image-delivery-insight` at **18 KiB** (was 1,223 / 477 KiB).

**The F59 assertion was extended during this promotion, and the extension is worth keeping.**
`.gitattributes` sets `app.js merge=ours`. The documented check compares branch *tips*, so it
reports "ok: differs" even in the exact case the `ours` driver would silently keep `main`'s copy —
it cannot detect the failure it is named for, on the one file carrying that attribute. The merge
*result* and git's index were asserted directly instead. (A first attempt at that assertion falsely
reported three FAILs by combining `[regex]::Escape()` with `-SimpleMatch` in PowerShell, which
searches for literal backslashes — verified with `grep` before concluding anything. A check that
can falsely fail aborts a good promotion just as surely as a check that cannot fail passes a bad
one.)

**Calibration lesson — worth more than the sweep itself.** The opening question was about
Lighthouse **scores**; the three lines quoted were **Insights**. "Use efficient cache lifetimes"
and "Improve image delivery" are **diagnostics that contribute nothing to the Performance score**,
which is only TBT 30% / LCP 25% / CLS 25% / FCP 10% / SI 10%. This sweep closed both diagnostics
almost entirely and the scores barely moved — exactly what that weighting predicts. Two further
mismeasurements cost real time the same day: (1) Lighthouse run against `/catalog` **in a private
window is not signed in**, so `requireAuth()` redirects and it scores the marketing page reached
via a discarded catalog load — 21 requests, ~554 KiB, precisely where the "555 KiB" figure came
from; (2) the raw byte sizes of our own assets were assumed to map onto the audit totals, when on
the **authenticated** catalog every single cache and image item is a third-party
`media.lunardistribution.com` cover. **Measure the authenticated page, and check whether an audit
is actually scored before optimising for it.** `playwright/lighthouse-auth.mjs` (local-only, in the
scripts repo working tree) does the former — it creates a staging user, signs in via magic link,
runs Lighthouse against the live session, and tears the user down.

Prior work (2026-08-24): **F140** fully RESOLVED (both environments) — promoted to
production same day as the staging fix (PR #131, `2acc78d`/`26a2c80`), per Rick's explicit
`/promote-prod` request. New production bytes confirmed served; both high-risk findings
re-verified directly against live production data post-deploy — the current catalog month
(`2026-08`) genuinely had **2,399 rows**, past the old hardcoded 2,000-row ceiling, and the fixed
loop now correctly retrieves all 2,399 (1000/1000/399); the Book Stop admin account's `preorders`
total had grown to **1,345**, and the fixed `Recommendations._getUserSignal()` pagination now
correctly retrieves the full 1,345 across 2 pages, matching the exact DB count. Both were
confirmed genuinely live-broken before this promotion, not just theoretical risk. See
`docs/technical-reference.md` § 13 F140.

An audit follow-up to F139, triggered by Rick asking "do we have other areas where pagination is
causing issues?" Swept every Supabase
query in the app for the same unbounded-select-no-`.range()` shape and found six more live
instances — the third occurrence of this defect class overall (after F82, F113). Two judged
plausibly already live-broken in production: `catalog.html`'s Reserved/Unreserved and
FOC-Expiring-This-Month filters were hardcoded to exactly two 1000-row batches (a fixed 2,000-row
ceiling, re-capped instead of unbounded — the same shape F82 fixed, at a higher threshold); `app.js`
`Recommendations._getUserSignal()` had the identical unbounded shape as F139's `getMyIds()`/`getMy()`
in a different function that fix missed. Also fixed: `Subscriptions.getAllAdmin()`,
`admin.html`'s three `user_profiles` fetches + This Week bagging query, `analytics.html`'s
`user_profiles`/`subscriptions`/current-month-preorders fetches, `mylist.html`'s shelf-copy demand
query — all now paginated, reusing each file's existing helper where one exists (`app.js`'s
`Preorders._fetchAllRows` generalized to a shared top-level `fetchAllRows()`; `admin.html`'s
`fetchPaged()`; `analytics.html`'s `countRows()`/`fetchRanged()`) or a local count-first+loop
matching the file's convention otherwise. Also added `id` tiebreakers to three paginated `ORDER BY`
clauses that sorted on non-unique columns (a page-boundary tie risk with no prior symptom, since it
only matters once a query is paginated at all). **Verified 2026-08-24**: `node --check` clean on
`app.js` and every extracted inline `<script>` block; full `run-smoke.ps1` — 269 unit + 139
Playwright, 0 failures, exit 0, no log-capture ambiguity this run. Standalone audit/fix, not
scoped to any active sub-deploy. Promotion details above.

Prior work (2026-08-23): **F139** fully RESOLVED (both environments) — a live customer-
reported catalog bug (a real reservation showing unreserved, omitted from the Reserved filter, and
hitting a 23505 on re-reserve) traced to `Preorders.getMyIds()`/`getMy()` having no pagination
against PostgREST's default 1000-row cap on unbounded selects. Diagnosed against live production
data (confirmed the row was correct in the DB before touching any code — no RLS gap, no data
corruption), fixed with a new `Preorders._fetchAllRows()` range()-based pagination loop in `app.js`,
no schema change. Verified on staging via full `run-smoke.ps1` (269 unit + 139 Playwright, 0
failures) and a targeted 37/37 rerun of every reserve/My List/subscriptions/arrivals spec; promoted
to production same day (PR #130) and re-verified directly against live prod data post-deploy — the
account that surfaced the bug (1,223 preorders as of the recheck) now correctly returns the
previously-dropped reservation via the fixed pagination. See `docs/technical-reference.md` § 13
F139. Standalone bug fix, not scoped to any active sub-deploy.

Prior work, same day: **F138** RESOLVED on staging 2026-08-22 (reverses F128, Rick's explicit
request) — admin impersonation gets full write access to `subscriptions` (subscribe **and**
unsubscribe on a customer's behalf), matching how `preorders`' admin policy already works. New
`admins manage tenant subscriptions` RLS policy (`docs/sql/2026-08-22-f138-admin-subscription-management-impersonation.sql`)
run on staging and verified via `pg_policies`; three impersonation guards removed from
`subscriptions.html` (reserved-suggestions Subscribe, main-table Unsubscribe, series-search input);
two write-target bugs fixed in the process (reserved-suggestions subscribe + its Undo handler were
writing to the admin's own `user_id`, not the impersonated customer's — harmless only while the
buttons were disabled). **V1–V4 all green**: V1 the live `pg_policies` read, V2/V3 a rewritten
Playwright test in local spec `11-reserved-suggestions.spec.ts` that subscribes and unsubscribes on
a customer's behalf during impersonation and DB-verifies both the correct `user_id` and the actual
row deletion (not F128's silent no-op), V4 the full `run-smoke.ps1` — 269 unit + 139 Playwright, 0
failures. Branch `feature/f138-admin-subscription-management-impersonation` merged to `staging`
`--ff-only` and pushed. **Promoted to production 2026-08-22** — RLS migration applied same day,
client code via PR #129 (`f1364a785`). **F138 fully RESOLVED, both environments.** *(This section
previously read "Not promoted to production" after the promotion had already completed — the same
stale-doc pattern as F132 below; corrected 2026-08-23, found while promoting F139.)* See
`docs/technical-reference.md` § 13 F138.

Prior work, same day: **F136** fully RESOLVED 2026-08-22 — S1, S2, and S3 all shipped the same day
(`docs/f136-catalog-month-integrity.md`). S3 (an earlier session that same day): created
`dedupe_catalog_months()` on **production** (S2's migration was staging-only); added the Part C(2)
revision-sweep runbook step to `docs/monthly-catalog-refresh.md`; re-measured live production fresh
rather than trusting the 2026-08-21 snapshot (2,666 duplicate pairs / 2,667 safe / 29 blocked,
unchanged — of the 29 blocked, only 2 are unfulfilled, matching § 3(d) exactly, the other 27
historical/fulfilled); repointed the 2 unfulfilled reservations (Alex Alvarez / TMNT #40 Variant C,
Brian Moss / Action Comics #1 Facsimile) from `2026-05` to the maintained `2026-06` rows; ran the
production dedupe. **Gates V7–V8 green**, confirmed three independent ways — production catalog
rows **12,087 → 9,418 (delta exactly 2,669)** matching the dry-run preview precisely, preorder
counts unchanged (**2,021/1,049/972** total/unfulfilled/fulfilled), duplicate pairs **2,666 → 27** /
safe-blocked **2,667/29 → 0/27** (the 27 survivors are the historical rows Rick chose to leave
blocked — zero customer risk, permanent minor bloat, accepted). Staging's one residual (Nightmare
Before Christmas #2) confirmed `fulfilled = true`, same accepted category. **Also fixed in-session:**
CLAUDE.md's and `technical-reference.md`'s F132 findings both still read "production not yet run"
when the DB half had actually been `APPLIED` 2026-08-21 — corrected (commit `7d4df83`), found while
confirming F136 S3 wasn't blocked by that gate. **No further F136 sessions planned.**

Prior work, same day: **F136 S2** — the `dedupe_catalog_months()` RPC applied to **staging**, wired
into `refreshCatalog()`'s new-month branch in both `import.js`/`import-staging.js` (scripts repo
`main` `7a8d6a1`, which is why S3 needed no additional code change — the wiring already covered
production). **F136 S1** — Part A (catalog-month entry guards: `inferCatalogMonth()` no longer
silently guesses, requires an explicit typed month; Lunar MMYY-vs-confirmed-month cross-check;
distributor-agnostic cross-month collision pre-check) + Part C(1) (`classifyReservedDateDrift()`
gains a third `unreserved` list) + **F137** (Step 3's month-detection query scoped by `tenant_id`,
**fully RESOLVED**) + `f136-audit.js`. Merged to `main` in the scripts repo (`f1f90be`).
2026-08-22.
**Next free finding ID:** **F142**. **F141 filed 2026-08-24** (desktop CLS
0.636 — the catalog grid fills after first paint with no reserved space;
found re-measuring Lighthouse against *authenticated* staging after the
performance sweep, which itself consumed no ID — see table below and
`docs/technical-reference.md` § 13). **F140 filed
2026-08-24 and RESOLVED on both environments the same day** (six more
unbounded-query pagination gaps, found auditing F139 — see table below and
`docs/technical-reference.md` § 13). *(This pointer read "RESOLVED on staging"
for a few hours after the prod promotion had already landed — corrected
2026-08-24.)* **F139 filed and
RESOLVED on both environments 2026-08-23** (`Preorders.getMyIds()`/`getMy()`
silently truncated at PostgREST's 1000-row cap — see table below and
`docs/technical-reference.md` § 13). **F138 filed 2026-08-22** (reverses F128
at Rick's request — see table below and `docs/technical-reference.md` § 13).

Every `docs/*.md` plan doc carries a machine-readable `**STATUS:**` token (state · staging/prod
dates · PR · findings) as the first line after its title. Trust that token — not narrative
elsewhere, including this section — for whether a specific piece of work has shipped.
`/preflight` cross-checks these tokens (and every `docs/sql/*.sql` `-- STATUS:` line) against git
and flags any doc claiming NOT STARTED / IN PROGRESS whose branch is already merged to `main`.

**Open findings — full detail lives ONLY in `docs/technical-reference.md` § 13. This table is a
pointer, not a record; do not duplicate finding narrative here or let it drift from § 13.**
When re-deriving this table from § 13, **do not grep for the word "open"**: F115 went missing from
every open-work surface for a week because its status reads *"Mitigated"*, and F127 sat listed as
*"PARTLY RESOLVED"* for a week after both halves shipped (both corrected 2026-08-18). Read each
status line's **last clause**, not its first word — and treat any finding that delegates its
residual to another finding as open until that other finding demonstrably absorbed it.

| ID | One line | Next step |
|---|---|---|
| F141 | **Medium** — the catalog grid under-reserved its own height: `renderSkeletons(10, …)` against `PAGE_SIZE = 50`, and a skeleton shorter than a real card. **Desktop CLS 0.636** (good is < 0.1) — essentially the whole gap between the authenticated catalog's desktop score of **75** and a passing one | Owner: `docs/technical-reference.md` § 13 F141. **Fully RESOLVED 2026-08-24, both environments** (staging `a2a2583`, prod **PR #133**) — desktop **75 → 98** (CLS 0.636 → 0.02), mobile **86 → 93** (CLS 0.097 → 0.008), full `run-smoke.ps1` green, prod verified post-deploy. Same shape is plausible on `mylist.html`/`arrivals.html`, **unmeasured** |
| F115 | **Medium** — a never-arrived title is auto-fulfilled on schedule, so My List tells the customer "✓ Order placed" for a book that never came. Persistence built on staging (S2-S4/S7) but **not yet exercised by a real import**; prod has the column (2026-08-20) but not the write or the backfill | Owner: `docs/f115-arrival-truth-persistence.md` (IN PROGRESS — staging built+tested 2026-08-18; **prod migration APPLIED 2026-08-20**, pulled forward to clear the promotion block; **S1/S5/S6 held for the ~Sept 7-10 catalog import**, then prod backfill, Rick-gated) |
| F135 | **Medium** — the pull-feed publish is welded to shipment import and fires unconditionally, so an **ad-hoc** shipment import republishes a *past* newsletter week, purges the current week's thumbnails, and the next Brevo cron mails the stale issue — the measured 2026-08-11 incident, reproduced deliberately | Owner: `docs/f135-decouple-feed-publish.md`. Direction settled: **decouple**, move the build into the weekly send workflow (DB-resolved week), delete `resolveFeedWeek()`. **Interim, no code:** comment out `GITHUB_TOKEN_PULL_FEED` in `.env` for ad-hoc runs |
| F131 | **Medium scaling / High continuity** — catalog import is a single-operator dependency: no self-service path exists (service-role key makes the script undistributable), and **every tenant's catalog is sourced from one person's Lunar/PRH portal access**, so losing that access stales every tenant at once. Not a defect — a structural SPOF no test can surface | open, no plan doc. Blocks nothing today; becomes load-bearing the moment the Founding Partner cohort onboards. **Interim, no code:** document the runbook for a second operator + make `.env`/portal access recoverable. Fix shape = authed upload → EF → tenant-scoped write (volume, not architecture, is the open question) |
| F130 | **Low** — 197 orphaned GoTrue **auth users** in staging from Playwright fixtures. **Measured 2026-08-24: the auth DELETE works (6/6 deleted, 0 remained) — these are deletes never *attempted*, not failed ones**, and 7 of 11 same-day orphans are `pw-pending-*` where a surviving auth row is *intended* (F64 item 5 Option A). Test-infra only, no live app impact | deferred — dedicated test-infra session. **The bulk-delete-after-date-bucketing plan is invalid as stated**: bucketing cannot tell an intended decline survivor from a teardown miss. Classify by originating spec/prefix first, fix the teardowns that skip the auth call, then delete only what remains. See § 13 F130 |
| F133 | **Low** — date-dependent specs flip red with zero code involved, via the live `order_deadline` (2026-08-21). **Two variants, not one:** (a) a fixture FOC crossing *past* the deadline (2026-08-20, three specs); (b) **the deadline having LAPSED** re-admits *real* catalog rows into `#backorder-risk-panel`, breaking any spec that assumes the panel holds only its fixture — **recurred 2026-08-24 in a fourth spec** (`21-arrival-resolution:136`) — **but only in a TARGETED run; it passes in the full suite**, because spec 15 runs first and leaves the state it needs. Test-infra only | deferred — no plan doc. **The entry's prediction that a lapse would end this was wrong — a lapse started variant (b).** Also exposes an **undeclared spec-order dependency**: spec 21 is green by ordering luck, so **targeted runs of these specs are not trustworthy**. Fix: deadline-aware helper closes (a) only; (b) needs panel assertions scoped to the seeded row. See § 13 F133 |
| F72 | `register-customer` email template stays founding-branded post-un-pin | design together with F99 — needs a scoping interview |
| F99 | transactional (MailerSend/GoDaddy) and marketing (Brevo/Cloudflare) mail split across two sender domains | **DMARC gate READ 2026-08-20 — inventory complete, 13 msgs / 100% pass / 3 senders, all known.** `p=quarantine` **held**, trigger = MailerLite retirement (not a date). Scoping now unblocked — design together with F72, and **sequence with MailerLite retirement** (`native-customer-signup.md` § S5) |
| F89 | paper→app conversion is unmeasurable — claim deletes the paper rows, nothing logs it | deferred — future instrumentation session |
| F90 | `usage_events` 90-day purge forecloses adoption-trend analytics | deferred — future schema + import-script session |
| F126 | profile email-editing unreachable outside the Supabase console (needs an Edge Function, F25); paused-customer reservation handling undecided | deferred — Rick's call to schedule |
| F132 | **Medium** — a title restricted to a distributor allocation ratio (e.g. `1:10`) carries no signal at reservation time; customer only learns via the retrospective F117/F120 rejected badge. **Both distributors** — corrected same-day, Lunar carries the ratio in `variant_type` (562 rows, staging), not absent as first measured | Owner: `docs/order-restriction-alert-badge.md` (staging V1-V7 all GREEN 2026-08-21 — migration, real import, hover-stacking fix, mobile Learn More via the detail modal, 210/210 unit + 6/6 Playwright. **Gate V8 — DB half APPLIED to production 2026-08-21** (verified 0 non-null/11,726, Rick) — the `import.js` 400 risk this was blocking is cleared; **client code half (app.js/catalog.html/style.css via `/promote-prod`) still not promoted**, in progress) |

Before proposing any work, read the active phase docs and confirm the proposed change is in
scope. **If something seems related but isn't on the IN scope list in the active sub-deploy plan,
stop and ask** rather than fixing it inline.

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
  index.html                       ← sign-in / landing
  catalog.html                     ← ┐
  mylist.html                      ← │ the SIX nav+footer pages that must
  arrivals.html                    ← │ stay in sync (see § Files That Must
  subscriptions.html               ← │ Stay in Sync)
  admin.html                       ← │
  analytics.html                   ← ┘ admin-gated nav link — but it DOES
                                   ←   carry the shared nav+footer blocks
  forgot-password.html             ← linked from the index.html sign-in footer
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

### ⚠️ `main` is NOT simply "staging + prod config.js" (F125)

**`supabase/migrations/` exists only on `main` and has never existed on `staging`.**
Two files, both committed directly to `main` during the Phase 4 cutover window
(which § Staging Only expressly permits for a named cutover sub-deploy):

| File | Commit | Sub-deploy |
|---|---|---|
| `20260531030927_phase_4_3_prod_constraints.sql` | `9111412` | Phase 4.3 |
| `20260531150558_phase_4_4_prod_rls_functions.sql` | `3ecb6b0` | Phase 4.4 |

Nothing else differs structurally — verified 2026-08-10, these are the only two
paths present on `main` and absent from `staging`.

**Why this matters when designing a promotion flow.** The documented
`git merge staging --no-ff` flow is immune: staging never held these paths, so
there is no deletion in its history to replay, and both files have survived
every promotion to date. But **any promotion that rebuilds `main`'s tree *from*
`staging` rather than merging into it** — a squash promotion, a rebase-based
flow, `git checkout staging -- .`, or a `git reset --hard staging` used to
tidy a messy `main` — would silently delete the only in-repo copies of that
production DDL. The knowledge survives in `docs/phase-4.3-*.md` / `4.4-*.md`
(on both branches) and the DDL is live in production, so a loss is
repo-history only. That is why this is a documented trap, not a defect.

**Do not "fix" this by deleting them from `main`**, and **do not copy them onto
`staging`** — that would put prod-cutover DDL on a branch that must never run
it. Every migration since has gone to `docs/sql/` instead, which is the correct
convention and is already followed; these two are pre-convention residue.
(`docs/sql/` tracks forward normally — staging runs ahead of main between
promotions, which is expected and is not this asymmetry.)

**A fifth trigger, hit for real on 2026-08-24 and caught one step before the
merge button: a promotion branch accidentally cut from `staging` instead of
`main`.** The listed triggers above are all deliberate acts (squash, rebase,
`checkout staging -- .`, `reset --hard`). This one is an accident, which makes
it more dangerous. A cherry-pick promotion was branched with
`git checkout -b <branch>` from *ambient HEAD* while a second person was
committing in the same working tree; HEAD had moved to `staging` in between, so
the branch inherited staging's tree. The resulting PR would have **deleted both
`supabase/migrations/` files AND overwritten `config.js` with the staging anon
key**, pointing production at the staging Supabase project. PR closed unmerged,
branch deleted, `main` never touched.

**Why the usual checks did not catch it.** Per-file checks all *passed* —
`ls supabase/migrations/` showed two files, `grep` found no barcode markers,
`config.js` was not in `git status`. They were reading a working tree that was
correct at that instant, on a branch that was not. **The check that caught it
was `git diff --stat origin/main <branch>`** — scope of the whole diff against
the *remote* base, not spot-checks against local state.

**So, for any promotion branch:** create it from an explicit ref
(`git checkout -B <branch> origin/main`), never from ambient HEAD, and assert
the full diff before pushing — exactly one expected scope, `supabase/migrations/`
still at 2 files, and `config.js` still carrying the prod project ref
`plgegklqtdjxeglvyjte`. Assume HEAD can move under you: this repo has more than
one actor in it.

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

# Optional pre-push baseline — see "Smoke-test ordering" below for why this
# does NOT test your change. Its value is confirming staging was already green,
# plus stage [1/2], which does run against local files.
cd C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts\playwright
.\run-smoke.ps1

git push origin staging
# CF Pages auto-deploys the staging preview at https://staging.pulllist.pages.dev/
# (Do NOT run: git push staging staging:main — retired as of 5.1)

# Wait for the build, then CONFIRM the new bytes are actually served before
# trusting any test result (~30-60s; note -L, without it the redirect yields
# an empty body that looks like a stale build):
#   curl.exe -s -L "https://staging.pulllist.pages.dev/style.css"
# and match a marker string your change introduced.
#
# CHECK THE PLAIN URL, NOT A CACHE-BUSTED ONE (corrected 2026-08-07). This
# line previously appended "?cb=$(Get-Random)". A query string is a DIFFERENT
# Cloudflare cache key, so it can fetch the new build while the plain URL a
# browser (and Playwright) actually requests is still serving the old one —
# a green "new bytes served" check followed by a test failing against stale
# bytes. That happened on 2026-08-06: a spec asserting a brand-new CSS class
# failed with 0 elements, looked like a code defect, and was neither. Verify
# what the browser will get. Cache-busting is for forcing a fresh read when
# you WANT to bypass the edge, which is the opposite of this check's purpose.

# THEN run the authoritative smoke pass — this one exercises your change:
.\run-smoke.ps1
# Stop and fix (or revert the push) if anything fails.

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

### Smoke-test ordering (corrected 2026-07-28)

**`run-smoke.ps1`'s two stages test different things, and only one of them can
see unpushed work:**

- **[1/2] `npm test`** — the scripts repo's import-script unit suite, run against
  **local files**. Genuinely pre-push, and the stage that matters when the change
  is to `import.js` / `import-staging.js`.
- **[2/2] Playwright** — `baseURL` is `https://staging.pulllist.pages.dev/`
  (`playwright.config.ts`), i.e. the **deployed** site. It loads the web app over
  HTTP and **cannot see the working tree at all.**

So for any change to `app.js` / `*.html` / `style.css`, a pre-push run exercises
the **previous** build. This section previously read "Run smoke tests before
deploying / Stop if anything fails — do not push", which cannot work as written
for app changes: a green pre-push result says nothing about the code being pushed.

Push first, confirm the new bytes are served, then run the suite. Keep the
pre-push run if you want a baseline — knowing staging was already green makes a
post-push failure attributable — but it is a baseline, not a gate.

**This is the second time this was found.** `docs/subscription-promotion.md`
§ "Deploy sequencing note (2026-07-17)" records the same discovery and Rick
confirming the same resolution — push to staging first, then run the suite as
the real gate. That note stayed in a feature plan doc and CLAUDE.md was never
corrected, so the stale ordering survived here and in `/deploy-staging` and cost
the rediscovery on 2026-07-27. The 2026-07-17 framing was also narrower than the
truth: it read as applying to *genuinely new UI* whose specs did not exist yet.
It applies to **every** web-app change, because the suite always loads the
deployed build over HTTP — new specs or old.

**Green is not the same as verified.** The suite only covers what has specs.
The catalog **info-card** reserve path had **no coverage at all**, which is how
four defects shipped there unnoticed in July 2026 — closed by spec 14
(2026-08-02, see F103). The **order-export / order-ledger** path shipped to
production the same way on 2026-08-03 and was closed by spec 15 the same day.
Both are cautionary: in each case the gap was noticed only *after* the code was
live, and in both cases the fix was cheap once someone looked. Check whether
your change is actually covered before treating a pass as verification; if it
isn't, a real-browser check is the only evidence you have — and adding the spec
is usually an hour, not a project.

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
- **Full admin write access during impersonation (F138, 2026-08-22, reverses
  F128/§ 4c's earlier disabled-button design).** On `subscriptions.html`,
  admins can subscribe and unsubscribe on the impersonated customer's behalf
  — reserved-suggestions list, series search, and the main subscriptions
  table all write through `AdminContext.resolveUserId(user.id)`, backed by a
  new `admins manage tenant subscriptions` RLS policy mirroring `preorders`'.
  **Live on staging 2026-08-22 (V1–V4 green); not yet promoted to
  production.** See `docs/technical-reference.md` § 13 F138 for status
  before relying on this in production contexts.
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

Do NOT touch any of the below in agentic sessions without explicit approval.

**Genuinely still open or deferred:** Partial fulfillment is not representable (product decision,
deferred until product scoping — no finding ID). Everything else currently open is F72, F89, F90,
F99, and F126's residual — see the open-findings table in § Current Migration Phase; full
detail lives only in `docs/technical-reference.md` § 13. **F92 closed 2026-08-18, F136+F137 closed
2026-08-22** — see § 13.

**Closed work — kept here as a "don't re-open without asking" index only. Each doc's own
`**STATUS:**` token and `docs/technical-reference.md` § 13 are the evidence; this table is not:**

| Work | Doc | Key findings closed |
|---|---|---|
| Order-export FOC window + order state | `order-export-foc-window-and-order-state.md` | F101, F102 |
| Order-export follow-through (withdrawals, cross-month FOC, distributor model) | `order-export-followthrough-f110-f111-f112.md` | F110–F114 |
| Closing the ad-hoc order loop | `order-loop-closure-f108.md` | F108, F117–F120 |
| Order Builder record/download split | `order-builder-record-split.md` | — |
| Admin restructure — Sessions 1–6 | `admin-dashboard-process-map.md` + per-session docs | F121, F122, F124 |
| Admin Accounts tab + account lifecycle | `admin-accounts-tab.md`, `admin-account-lifecycle-f126.md` | F126 (partial — residual open), F127 |
| `auto_fulfill_past_on_sale()` current-schedule fix | `f122-auto-fulfill-current-schedule.md` | F122, F124 |
| `preorders` authorization boundary (status gate + ordered-cancel trigger) | `preorders-authorization-boundary-f127-f109.md` | F127, F109 |
| Phase 5 — second-tenant onboarding (all sub-deploys) | `phase-5-second-tenant-onboarding.md` | F105 |
| Test-infrastructure maintenance | `test-infra-maintenance-f91-f95-f103.md` | F91, F95, F103, F107 |
| Catalog-month integrity — stale-date detection + duplicate-row cleanup (S1-S3) | `f136-catalog-month-integrity.md` | F136, F137 |
| `import.js` maintenance (key rotation, historical dedup, cross-month fix) | `import-js-maintenance-f75-f78-f85.md` | F75, F78, F85 |
| F86 prod legacy API key retirement | `f86-anon-key-migration.md` | F86, F88 |
| Mobile thumb-reach tab bar + live-review follow-up | `mobile-nav-tab-bar.md` | — |
| Analytics cycle-alignment | `analytics-cycle-alignment.md` | — |
| Analytics v2 engagement dashboard | `analytics-v2-engagement-dashboard.md` | — |
| Catalog info-card reserve-sync fix (no plan doc — direct bug fix, PR #99) | — | F103 (coverage gap it exposed) |
| `Preorders` pagination past PostgREST's 1000-row cap (no plan doc — direct bug fix, PR #130) | — | F139 |
| Six more unbounded-query pagination gaps, app-wide audit (no plan doc — direct bug fix, PR #131) | — | F140 |
| Admin write access to `subscriptions` during impersonation (no plan doc — direct fix, PR #129) | — | F138 (reverses F128) |
| Subscription reserved-suggestions | `subscription-reserved-suggestions.md` | — |
| Subscription promotion | `subscription-promotion.md` | — |
| Apex marketing page + universal login | `apex-landing-tenant-subdomains.md`, `apex-marketing-page-design.md` | — |
| Native in-app customer self-registration | `native-customer-signup.md` | F94 |
| Weekly pipeline hardening (Brevo send verification, single-commit publish) | `weekly-pipeline-hardening.md` | F96, F98, F100, F106 |

All doc paths above are relative to `docs/`. If a session needs to touch any of the above, **stop
and confirm**.

*(Rewritten 2026-08-18 in the doc-status truth pass — this section was 375 lines of narrative that
duplicated each closed feature's own plan doc and `technical-reference.md` § 13, the same drift
source the pass exists to remove. The removed narrative is not lost: it is in git history on this
branch, and in fuller, more current form in the docs this table points to.)*

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

The nav block must be identical across **six** pages: `catalog.html`,
`mylist.html`, `arrivals.html`, `subscriptions.html`, `admin.html`, and
**`analytics.html`**. When updating nav, copy from the most recently-updated
file — the canonical version is whichever HTML file was last touched.

**`analytics.html` was omitted from this list until 2026-08-15**, and this
section plus § Repository Structure both described it as having no shared nav
block. That was wrong — measured, not assumed: all six nav blocks hash
identically (`66C5139EF8AD97147227FB7A7EB38F56`), all six footer blocks hash
identically (`EB2513E8ED474B3CE5251F2540A69852`), all six load
`vendor/supabase.min.js` → `config.js` → `app.js`, and all six call
`initNav()`. `analytics.html` is a full member of the sync set on every
contract in this section. Found while planning `docs/mobile-nav-tab-bar.md`,
where a five-file nav edit would have silently skipped it.

The footer block must be identical across all six pages, placed immediately
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
isolation (F15, F20), per-tenant branding unit spec, catalog info-card reserve
(spec 14, added after F103), and the **order-export / order-ledger path**
(spec 15, added 2026-08-03 — see below). `run-smoke.ps1` runs the scripts
repo's committed unit suite (`npm test`, step [1/2]) before Playwright; the old
local `node-tests/` copy was retired 2026-07-16. **56 Playwright tests as of
2026-08-03.**

**Spec 15 — `15-order-export-ledger.spec.ts` (F101/F102).** Covers the path
that shipped to production on 2026-08-03: the Order Builder opens with a
multi-select FOC-cycle list rather than downloading instantly; a title outside
the selected cycle is excluded **and** surfaced in the held-back panel (V3); an
already-ordered code is flagged with its prior quantity and defaulted to the
remainder, never auto-suppressed (V4); the Status-column button reflects
ordered-vs-reserved (`Mark Ordered` / `Add (n of m)` / `Over (n of m)` /
`Ordered (n)` disabled); the backorder-risk panel separates At risk,
Backordered and cleared-by-ledger (V7); and My List shows "Order placed" driven
by the ledger with `fulfilled` still false.
**Writing specs against this path: staging carries 857 real backfilled ledger
rows**, so seeded rows share every panel with production-shaped data. Assert on
a seeded title or `data-catalog-id` — never `.first()` and never an exact
count. A `.first()` assertion in the initial draft failed against a real
staging title, which is how this got caught.

### How to run it — targeted while iterating, full suite once as the gate

**Do NOT run the full suite after every change.** It is `workers: 1`,
`fullyParallel: false` (specs share staging state — spec 15 mutates
`app_settings.order_deadline` globally), so a full pass is **~16 minutes**. A
single spec is **~17 seconds**.

```powershell
# While iterating — run only what you touched
npx playwright test 17-admin-modes --grep "V1 — get_account_activity"
npx playwright test 15-order-export-ledger

# Once, before promotion — this is the gate
.
un-smoke.ps1
```

**Measured, 2026-08-09** (Rick asked whether the suite was earning its keep —
a fair question, and the numbers said *barely*). Seven full runs, ~100 minutes
of wall clock, which caught **2 real feature defects**, **4 of the agent's own
broken tests**, and **1 unexplained flake**. Five of those seven runs should
have been targeted; doing so would have saved ~70 minutes and caught the
identical two defects.

### What this suite is actually good at — and what it is not

Calibrate expectations before deciding a green run means anything:

- **Good at regression.** Did a change break something that already worked.
  Every UI restructure this year was caught this way.
- **Good at invariants you state explicitly.** The Accounts partition
  assertion (`the parts sum to the whole`) caught two defects **on a build
  whose real-browser check had already passed** — admins visible in one view
  and absent from another, and a filter matching a *type* while rows displayed
  a *state*. Neither was visible on screen. Four lines of assertion.
- **Bad at brand-new paths**, because a test written alongside the code
  inherits the code's wrong assumption. On 2026-08-09 the two defects that
  mattered most — an open SQL gate and a filter keyed on a column that
  defaults to `true` — were both found by **probing the deployed thing and
  reading what came back**, not by the suite. Purpose-built fixtures passed
  under both the wrong predicate and the right one.

**So: a green suite says the assertions hold, not that the feature is right.**
For new work, the cheap high-yield checks are (a) call the deployed endpoint
and read the response, and (b) look at what a new query or filter *returns on
real data* — not merely whether it runs.

### A verification step that cannot fail is not a verification step

Filed the same day, from a SQL file whose final statement reported the
function's **return signature** — identical before and after the fix it was
meant to confirm. The Supabase SQL Editor shows the last statement's result, so
the operator pasted the same meaningless output three times while the gate was
still open. **Before asking anyone to run a check, ask what its output looks
like when the thing has FAILED.** If that is the same, it is decoration.

**Rules:**
- Local-only. Never committed. Never runs against production.
- `SUPABASE_URL` in `.env` must be staging; runner aborts if it's prod
- All `goto()` calls use paths without a leading slash

Canonical detail: `docs/phase-3.7-playwright-smoke-tests.md`
