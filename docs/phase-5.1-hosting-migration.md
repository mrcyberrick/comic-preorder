# Phase 5.1 — Hosting Migration (GitHub Pages → Cloudflare Pages)

**Status:** Planning — plan written 2026-06-11; not yet executed
**Parent plan:** `docs/phase-5-second-tenant-onboarding.md` (sub-deploy row 5.1)
**Predecessor:** Phase 5.0 — Pre-Phase-5 housekeeping — **Complete 2026-06-11**. Platform decision (Rick, 5.1 planning session 2026-06-11): **Cloudflare Pages** (Vercel not selected; parent row title updated).
**Branches:** Infra + docs only — **no `app.js` / HTML / CSS change anywhere in this sub-deploy.** Doc commits → `staging` directly. The one possible repo-content change is the `_redirects` file (S4, conditional on the S1 gate): rides `feature/5.1-redirects` off `staging` → `--ff-only` merge → staging verify → prod promotion per `CLAUDE.md` § Standard Deployment Workflow (F59 diff assertion; `config.js` checkout step).
**Execution model:** **CLI-orchestrated, Rick-in-the-loop.** A Claude Code CLI session runs this file top to bottom. It executes every repo / doc / local-script / Playwright / `curl.exe` verification step itself, and **pauses at every Cloudflare dashboard, DNS/registrar, Supabase dashboard, and GitHub settings action** — handing Rick the exact clicks and values and **waiting for pasted results before continuing**. **Self-contained — no chat context required.**
**Rollback complexity:** Easy–Medium (parent table) — serving switches back to GitHub Pages, which **stays warm until 5.5 closes**; no data surface anywhere in this sub-deploy.

> **Steps Claude never runs itself.** (1) Any **Cloudflare dashboard** action — Pages project creation, build settings, branch settings, custom domains, DNS zone import, redirect rules. (2) Any **registrar / DNS-host** change — records, nameservers. (3) Any **Supabase dashboard** action — Auth → URL Configuration; Edge Functions deployed-source view. (4) Any **GitHub repo settings** action. (5) The S4 prod-promotion PR merge — Claude prepares it; Rick reviews and merges. Each appears below as a **`PAUSE → Rick … → paste result → match expected → continue / STOP`** block. Claude prepares the exact inputs, the expected result, and the stop condition around every pause.

> **5.1 spans multiple sittings by construction.** S1–S3 (decisions + Cloudflare project + staging cutover) fit one sitting; S5's DNS change may wait for Rick's chosen low-traffic window; S7 is a **3-calendar-day soak** (three calendar days from the S5 cutover timestamp, not "checks green so far at day 2"). The durable state is the **Deploy Log (§ 8)**: every session appends one row per completed step. A resuming session reads the log, re-verifies the last recorded step against live state (a recorded cutover is re-verified with its `curl.exe` checks before trusting it), and continues from the next unexecuted step. Every doc edit is committed before the session ends.

> **Serving-path discipline.** S2–S3 touch only new, not-yet-canonical URLs — zero customer impact. **S5 changes what serves production** — it is the one customer-visible infrastructure change of Phase 5 before tenant 2 exists (parent header), and it gets a pre-captured DNS state, a post-cutover write-smoke, and the S7 soak. Nothing in 5.1 touches either database, `config.js`, or any Edge Function source (§ 1.4 / F67 governs the EF-URL question). GitHub Pages is **not torn down** in 5.1 — it is the warm rollback path until 5.5 closes.

---

## 0. Pre-flight (run at the top of every 5.1 session; halt on any mismatch)

### 0.1 Read before doing anything
- `CLAUDE.md` in full; confirm § Current Migration Phase active sub-deploy = **5.1**.
- `docs/phase-5-second-tenant-onboarding.md` — Sub-Deploys row 5.1, § Approach Decisions (hosting before subdomain routing), § Deferred-DDL Register (F64 items 5 and 8 — **not** 5.1 scope), § Out of Scope.
- This file in full — including the Deploy Log (§ 8): if any rows exist, this is a resume session.
- `docs/technical-reference.md` § 13 — F67 entry once filed (S1 files it); confirm no new hosting-touching findings landed since this plan was written.

### 0.2 Gates (halt if any fail)
- `git rev-parse --abbrev-ref HEAD` → `staging`; `git status` → clean (the known-stray untracked `docs/status-slide.html` is acceptable; anything else, stop and ask).
- `git pull origin staging` → up to date (or fast-forward) before any edit.
- `docs/technical-reference.md` § 13: confirm the highest filed finding ID (**F66** at planning time; **next free = F67** — S1 consumes it). New defects discovered during 5.1 are filed from the next free ID — never guessed or reused.
- **Re-verify the planning-time audits in § 1 against the current tree and live systems** (anti-drift: never trust a prior session's grep). In particular: re-grep the Edge Function URL constants (§ 1.4) and re-view `playwright.config.ts:21` (§ 1.3) before acting on either.

### 0.3 Commit discipline
- Each S-step's doc update (deploy-log row, decision record, F67 filing) is its own doc-only commit to `staging` — exact messages are given inline.
- The S4 `_redirects` change (if adopted) rides `feature/5.1-redirects`, never `staging` directly, and reaches `main` only via the standard promotion PR.
- Push `origin staging` after each commit; the Deploy Log row lands in the same commit as the step it records.

### 0.4 Files / surfaces touched by this sub-deploy

| File / target | Change | Branch / actor |
|---|---|---|
| Cloudflare account | Pages project (connected to `origin` repo); custom domain(s); possibly DNS zone for `mrcyberrick.us` (S1 Path decision) | Rick, CF dashboard |
| DNS for `mrcyberrick.us` | Pre-captured, then repointed per the S1 Path decision (S5) | Rick, registrar / DNS host |
| Supabase Auth (both projects) | URL Configuration → **additive** redirect-allow-list entries for the new origins (S2) | Rick, Supabase dashboard |
| `playwright.config.ts:21` (local-only, never committed) | `baseURL` → new staging URL (S3) | Claude, direct edit |
| `_redirects` (repo root, new file) | Legacy-path forwarding rule — **conditional on S1 Q3** (S4) | `feature/5.1-redirects` |
| `docs/technical-reference.md` | § 13 F67 filing (S1); hosting rows (lines 29/36/90/96 at planning time) updated at S6 | `staging` (doc-only) |
| `CLAUDE.md` | § Standard Deployment Workflow rewrite; § Project Overview URLs; § Repository Structure remotes note; § Current Migration Phase pointer (S6/S8) | `staging` (doc-only) |
| `docs/phase-5-second-tenant-onboarding.md` | Row 5.1 → Complete at S8 | `staging` (doc-only) |

**Not touched:** `config.js` (per-branch model already correct for CF Pages — § 1.2), `app.js`, any `*.html`, `style.css`, any Edge Function source (F67 owns the EF-URL follow-up unless Rick expands scope at the S1 gate), `import.js` / `import-staging.js`, either database, MailerSend configuration (DNS records that back it are carried intact through any zone move — S5 pre-capture covers them).

---

## 1. Planning-time audit results (2026-06-11) — re-verify at execution

### 1.1 No build step; subpath-safe assets
The app is vanilla HTML/CSS/JS served as static files. CF Pages settings are therefore: **Framework preset = None; Build command = blank; Build output directory = blank** (repo root is the site root). The app already serves correctly from a *subpath* today (`/comic-preorder/`, `/comic-preorder-staging/`) — its asset and link references are relative (the Playwright suite's "no leading slash in `goto()`" rule exists for the same reason) — so serving from a domain **root** on CF Pages requires no code change.

### 1.2 `config.js` per-branch model maps cleanly to one CF Pages project
CF Pages deploys each branch of the connected repo as-is. The `origin` repo's `staging` branch carries the staging anon key/URL in `config.js`; `main` carries prod. **One CF Pages project** connected to `origin` (`github.com/mrcyberrick/comic-preorder`), with production branch = `main` and preview deployments for `staging`, reproduces today's two-environment serving with **zero credential changes**. The agent never edits `config.js`. Note: the production `*.pages.dev` URL serves prod `config.js` from the moment the project exists — this is fine (anon key public by design; RLS is the boundary), not a finding.

### 1.3 Playwright — one line changes, guard survives
`C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts\playwright\playwright.config.ts` line 21:
`baseURL: 'https://mrcyberrick.github.io/comic-preorder-staging/'` — the **only** Playwright file needing a URL change (local-only, never committed). The safety guard checks `SUPABASE_URL.includes('puoaiyezsreowpwxzxhj')` — independent of the app URL; **no change to the guard**.

### 1.4 Edge Function URL audit — scope-premise correction (**file as F67 at S1**)
The planning premise "no Edge Function changes needed for 5.1" was derived from CORS (all 8 functions use `Access-Control-Allow-Origin: '*'` — confirmed; no origin work needed). A repo-wide grep (2026-06-11) shows the premise was **incomplete**: five functions embed app URLs in email links and magic-link `redirect_to` values:

| Function | Repo lines (staging branch) | Value |
|---|---|---|
| `approve-customer` | `index.ts:13–15` | `STAGING_BASE = 'https://mrcyberrick.github.io/comic-preorder-staging'` → `redirect_to`, email links |
| `register-customer` | `index.ts:29–31` | same |
| `invite-customer` | `index.ts:1–3` | same |
| `reset-password` | `index.ts:1–2` | `STAGING_BASE = 'https://mrcyberrick.us/comic-preorder-staging'` — **anomalous host** (neither current staging nor prod URL); verify deployed copy at S1 |
| `notify-customers` | `index.ts:163` | prod catalog URL `https://mrcyberrick.us/comic-preorder/catalog.html` hardcoded in email body |

Checked via `git show main:…` (2026-06-11): the `main`-branch copies are **identical** to staging's — i.e. these constants are **not** per-branch divergent like `config.js`. The *deployed* prod functions may differ from the repo copies; S1 captures the deployed sources before any decision.

**Consequences for 5.1:**
- EF source stays **out of scope** (per the parent scope sign-off) → after cutover, **emailed links keep pointing at the old URLs**. The old URLs must therefore keep resolving until the EF-URL migration lands — this constrains GitHub Pages warmth (already guaranteed until 5.5) and strengthens the `_redirects` recommendation (Q3).
- Continuity holds on **both** S1 paths: Path 1 (apex on CF + `_redirects`) serves old prod links via redirect with query strings preserved; Path 2 (subdomain) leaves the old prod URL on GH Pages, which **stays fresh** (it builds from `origin main`, which still receives every promotion). Old *staging* links land on the frozen staging GH Pages copy — functional, staging-only, acceptable until F67 lands.
- **F67** is filed at S1 with the live deployed-source capture and an owner (default recommendation: 5.2-adjacent housekeeping commit, since 5.2 already touches tenant-resolution surface; Rick may pull it into 5.1 at the gate — that is explicit scope expansion, his call).

### 1.5 Client-side auth surface
`index.html` consumes `token_hash` links (`verifyOtp` with `magiclink`/`recovery`/`invite` types) — links are built by the Edge Functions with explicit `redirect_to`; no client-built `emailRedirectTo` exists in `app.js`/HTML. So the auth-redirect surface = the EF `redirect_to` set (§ 1.4) + Supabase **Auth → URL Configuration** allow-lists. Adding the new origins to both projects' allow-lists is additive and harmless → S2. Site URL is left unchanged in 5.1 (it backs default templates; it moves with F67).

### 1.6 Current serving topology
- **Prod:** `origin main` → GitHub Pages project page, custom domain `mrcyberrick.us`, app at `/comic-preorder/`. The project-page-under-custom-domain shape implies the domain root is claimed by a user/org site — **whether other content actually lives at the root is pre-flight Q1**.
- **Staging:** separate repo (`staging` remote, `github.com/mrcyberrick/comic-preorder-staging`), deployed by `git push staging staging:main` → `mrcyberrick.github.io/comic-preorder-staging/`. After S3 this push step is retired; the staging GH Pages copy freezes at the cutover commit (kept warm).

### 1.7 Docs that go stale at cutover (updated at S6, not before)
`CLAUDE.md`: § Project Overview URLs, § Standard Deployment Workflow, § Repository Structure remotes note, § Smoke Test Suite (no URL inside — verify). `docs/technical-reference.md`: GitHub-Pages mentions at lines 29 / 36 / 90 / 96 (planning-time positions; re-locate by grep at S6).

---

## 2. In scope

1. **S1** — Pre-flight decision gate (Rick): Q1 domain topology + DNS host, Q2 staging URL strategy + CF project name, Q3 `_redirects`, Q4 F67 owner. Deployed EF source capture. **File F67.**
2. **S2** — Cloudflare Pages project creation (one project, both branches) + Supabase Auth allow-list additions (both projects). Claude verifies both deployments serve the correct `config.js` via `curl.exe`.
3. **S3** — Staging cutover: Playwright `baseURL` → new staging URL (local-only edit); full smoke green; Rick manual verify; `git push staging staging:main` retired operationally.
4. **S4** — `_redirects` file (conditional on Q3): feature branch → staging verify → prod promotion PR.
5. **S5** — Production custom-domain cutover per the Q1 path: DNS pre-capture → domain attach → DNS change → TLS + `curl.exe` verification → post-deploy write-smoke. MailerSend DNS records carried intact through any zone move.
6. **S6** — Deployment-workflow doc rewrite: `CLAUDE.md` § Standard Deployment Workflow + URLs + remotes note; `technical-reference.md` hosting rows.
7. **S7** — Soak: 3 calendar days of CF Pages serving production, daily checks logged.
8. **S8** — Closeout: § 5 boxes ticked, parent row 5.1 → Complete, `CLAUDE.md` pointer → 5.2 planning, end-of-session status update.

## 3. Out of scope (stop and ask before touching)

- **Any `app.js` / `*.html` / `style.css` change** — 5.1 is infra-only. (`_redirects` is a new static file, not app code.)
- **Subdomain-based tenant routing** and the slug→id RPC — sub-deploy 5.2. The Q1 answer feeds 5.2's design but no 5.2 decision is made here.
- **F64 item 5 DDL** and **F64 item 8** (`idx_tenants_slug` → prod) — Deferred-DDL Register; item 8 belongs to 5.2.
- **Edge Function source changes** — F67 owns the URL-constant migration; touching EF source in 5.1 requires Rick's explicit scope expansion at the S1 gate (Q4). CORS needs nothing.
- **Cloudflare Workers** — not needed until 5.2.
- **Tearing down GitHub Pages** (either repo), deleting the `staging` remote, or removing the GH Pages custom-domain configuration — warm rollback path until 5.5 closes.
- **MailerSend / email-DNS changes** — `noreply@mrcyberrick.us` SPF/DKIM/Return-Path records are *carried* through any zone move (S5), never modified.
- Either database, `config.js`, `import.js` / `import-staging.js`.

---

## 4. Runbook

Execution order: **S1 → S2 → S3 (one sitting if possible) → S4 → S5 (Rick's chosen window) → S6 (same sitting as S5) → S7 (3 calendar days) → S8.** S4 may run before or in parallel with S5 prep, but the `_redirects` file must be **live on prod via the promotion PR before** the Path-1 DNS cutover (it is what keeps old prod email links working on Path 1).

### S1 — Pre-flight decisions + deployed-EF capture + F67 filing

1. **Deployed-source capture** —
   > **PAUSE → Rick (Supabase dashboard, BOTH projects — staging `puoaiyezsreowpwxzxhj`, prod `plgegklqtdjxeglvyjte`):** Edge Functions → for each of `approve-customer`, `register-customer`, `invite-customer`, `reset-password`, `notify-customers` → view deployed source → **paste the URL-constant lines** (the `STAGING_BASE` / `APP_BASE_URL` / hardcoded-link lines).
   > **Expected:** staging deployments match the repo `staging`-branch values in § 1.4; prod deployments reveal whatever prod actually sends today (repo copies suggest they may also carry staging URLs — if prod's `approve-customer`/`register-customer`/`invite-customer` really redirect to the *staging* URL, that is a live prod defect, not just a migration concern). **STOP if:** any deployed source can't be retrieved — file and halt the step, not the sub-deploy.
2. **Q1 — Domain topology (Rick answers from registrar/DNS facts):**
   - Where is `mrcyberrick.us` DNS hosted (Cloudflare already, or third-party registrar/DNS)?
   - Does any content **other than PULLLIST** live at `mrcyberrick.us/` root (a GH Pages user site, another project)?
   - **Path 1 (recommended if the root is free):** apex `mrcyberrick.us` becomes the CF Pages custom domain. Requires the zone on Cloudflare DNS (apex CNAME needs CF's flattening — most third-party DNS can't do it); if the zone is elsewhere, S5 includes a zone move. `_redirects` then serves all old `/comic-preorder/*` links.
   - **Path 2 (root occupied or zone immovable):** new prod URL = a subdomain, e.g. `pulllist.mrcyberrick.us`, CNAME → the Pages project (works on third-party DNS). Old prod URL keeps serving from GH Pages (stays fresh — § 1.4). **Note:** Path 2 makes F67 a hard prerequisite for the 5.5 GH Pages teardown, and the soak reads "new canonical URL healthy" rather than "all traffic on CF."
   - **Path 2b (middle):** zone moves to Cloudflare but root content stays untouched (existing records carried); subdomain on Pages **plus** a CF Redirect Rule forwarding `mrcyberrick.us/comic-preorder/*` → the subdomain. Gets full link continuity without claiming the root.
   - **Record the chosen path + rationale in the Deploy Log row.**
3. **Q2 — Staging URL + project name:** CF Pages preview alias format is `<branch>.<project>.pages.dev`. **Option A (recommended):** use the automatic `staging.<project>.pages.dev` alias — zero DNS work, stable per branch. **Option B:** custom staging subdomain (e.g. `staging.pulllist.mrcyberrick.us`) — nicer URL, more setup; can wait for 5.2's subdomain work anyway. Rick also picks the **project name** here (it is baked into every `pages.dev` URL; e.g. `pulllist`).
4. **Q3 — `_redirects`:** **Recommended: yes** (one file, one rule: `/comic-preorder/* /:splat 301` — splat and query string preserved, so `?token_hash=…` links survive). On Path 1 it is what keeps old prod bookmarks *and* old EF email links working; on Path 2 it is future-proofing only (CF never sees the legacy path) and may be skipped. Rick decides.
5. **Q4 — F67 owner:** default = file F67 with owner "5.2-adjacent housekeeping commit"; Rick may instead pull the EF URL-constant updates into 5.1 as an explicit scope expansion (they would follow the EF deploy procedure, staging first — **not** covered by this runbook; a scope-expansion addendum would be written and committed first).
6. **Record (Claude):** file **F67** in `technical-reference.md` § 13 — title: "Edge Function hardcoded app URLs — hosting-migration continuity"; body: § 1.4 facts + step-1 deployed capture + decided owner; severity per the step-1 prod findings. Deploy Log row with all four decisions. Commit:
   ```
   docs: 5.1 S1 — pre-flight decisions recorded (path, staging alias, _redirects, F67 filed with owner)
   ```

### S2 — Cloudflare Pages project + Supabase Auth allow-lists

1. > **PAUSE → Rick (CF dashboard):** Workers & Pages → Create → Pages → **Connect to Git** → select `mrcyberrick/comic-preorder` (the `origin` repo — *not* the staging repo). Settings:
   > - Project name: per S1 Q2
   > - Production branch: **`main`**
   > - Framework preset: **None**; Build command: **blank**; Build output directory: **blank**
   > - No environment variables
   > - Preview deployments: enabled for `staging` (either "All non-Production branches" or include `staging` explicitly)
   >
   > **Paste:** the production URL (`https://<project>.pages.dev`) and the staging branch alias (`https://staging.<project>.pages.dev`) once both first deploys finish. **Expected:** both deploys green in the CF dashboard. **STOP if:** either build fails (with no build step, failure means repo-connection or settings error — fix settings, never add a build command to work around it).
2. **Verify (Claude, `curl.exe`):**
   - `curl.exe -s https://staging.<project>.pages.dev/config.js` → contains `puoaiyezsreowpwxzxhj` and **not** `plgegklqtdjxeglvyjte`.
   - `curl.exe -s https://<project>.pages.dev/config.js` → contains `plgegklqtdjxeglvyjte` and **not** `puoaiyezsreowpwxzxhj`.
   - `curl.exe -sI` both roots → `200`, and a page fetch shows the login page HTML.
   - **HALT if crossed or mixed** — the branch/credential mapping is the load-bearing fact of this migration (§ 1.2).
3. > **PAUSE → Rick (Supabase dashboard, BOTH projects):** Authentication → URL Configuration → **Redirect URLs** → **add** (do not remove anything):
   > - Staging project: `https://staging.<project>.pages.dev/**`
   > - Prod project: `https://<project>.pages.dev/**` **plus** the future canonical prod URL from S1 Q1 (`https://mrcyberrick.us/**` or `https://pulllist.mrcyberrick.us/**`)
   >
   > **Site URL: unchanged** in both projects (moves with F67). **Paste:** the resulting allow-lists. **Expected:** old entries intact + new entries present.
4. **Record (Claude):** Deploy Log row (project name, URLs). Commit:
   ```
   docs: 5.1 S2 — CF Pages project live on both branches; Supabase auth allow-lists extended
   ```

### S3 — Staging cutover

1. **File-drift gate (Claude):** `Select-String` line 21 of `playwright.config.ts` (local-only path in § 1.3); confirm it matches the § 1.3 value byte-exactly. **HALT on mismatch** — re-derive from disk.
2. **Edit (Claude, local-only — never committed):** `baseURL: 'https://mrcyberrick.github.io/comic-preorder-staging/'` → `baseURL: 'https://staging.<project>.pages.dev/'` (trailing slash retained; all specs use leading-slash-free paths, so the alias root works like the GH Pages subpath did).
3. **Smoke (Claude):** `cd C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts\playwright` → `.\run-smoke.ps1` → **full suite green against the new URL.** The `SUPABASE_URL` guard is untouched and still enforces staging-only.
4. > **PAUSE → Rick (browser):** load `https://staging.<project>.pages.dev/`, log in, click through catalog → reserve → My List → cancel. **Known-degraded note:** emailed links (magic link, invite) still point at the **old** staging URL until F67 lands — they land on the frozen GH Pages copy, which still works against staging Supabase; for a manual login on the *new* URL, copy the emailed link and substitute the host (the `token_hash` query survives). **Paste:** "staging verified on CF" + browser.
5. **Operational retirement:** from this step on, staging deploys are `git push origin staging` only — **do not** run `git push staging staging:main` again (the GH Pages staging copy freezes at the cutover commit as the warm fallback). The workflow *doc* rewrite happens at S6; this step changes behavior, S6 records it.
6. **Record (Claude):** Deploy Log row (old/new baseURL, suite result). Commit:
   ```
   docs: 5.1 S3 — staging serving cut over to CF Pages; Playwright re-pointed; smoke green
   ```

### S4 — `_redirects` (only if S1 Q3 = yes)

1. **Branch:** `git checkout -b feature/5.1-redirects` off current `staging` (pulled).
2. **Create `_redirects` (repo root, new file, exactly two lines):**
   ```
   /comic-preorder/* /:splat 301
   /comic-preorder-staging/* /:splat 301
   ```
   (Second rule is staging-symmetry for old staging bookmarks once 5.5 retires GH Pages; harmless on prod.)
3. **Verify on preview (Claude):** after `git push origin feature/5.1-redirects`, CF builds a branch preview — or merge to `staging` first and test the staging alias: `curl.exe -sI "https://staging.<project>.pages.dev/comic-preorder/catalog.html?x=1"` → `301` with `location: /catalog.html?x=1`.
4. **Merge + deploy (Claude):** `--ff-only` into `staging`; `git push origin staging`; re-verify on the staging alias.
5. **Prod promotion (standard workflow):** Claude prepares `git merge staging --no-commit --no-ff` on `main`, `git checkout main -- config.js`, the F59 diff-assertion loop (expect the four app files **identical** — this is an infra-only promotion; the only diff should be `_redirects` + docs), branch `feat/5.1-redirects-prod` + PR. **Rick verifies `config.js` is NOT in the diff and merges.** CF auto-deploys `main`.
6. **Record (Claude):** Deploy Log row. Commits:
   ```
   feat(hosting): add _redirects for legacy /comic-preorder/* paths (5.1 S4)
   ```
   ```
   docs: 5.1 S4 — _redirects live on staging + prod previews; legacy-path 301 verified
   ```
   (If Q3 = no: record the decision + rationale in the Deploy Log and skip; the completion criterion reads "decision executed or recorded.")

### S5 — Production custom-domain cutover (Rick's chosen window)

**Shared pre-capture, all paths:**

1. > **PAUSE → Rick (current DNS host):** export / screenshot the **complete** record set for `mrcyberrick.us` — every A/AAAA/CNAME/MX/TXT/etc., names, values, TTLs. **Paste:** the full set. **Expected:** the GH Pages records (A records to `185.199.108–111.153` or a CNAME to `mrcyberrick.github.io`) **and** the MailerSend records (SPF/TXT, DKIM, Return-Path CNAME) are identifiable. **STOP if:** the MailerSend records cannot be identified — email sending must not be put at risk by a zone move; resolve before any DNS change. This capture **is the rollback artifact** — it goes in the Deploy Log notes verbatim.

**Path 1 / 2b — zone move (skip if the zone is already on Cloudflare):**

2. > **PAUSE → Rick (CF dashboard + registrar):** Add site `mrcyberrick.us` to Cloudflare (Free plan is fine) → CF scans and imports records → **manually compare the imported set against the step-1 capture line-by-line** (CF's scan misses records; add any missing ones by hand, MX/TXT especially) → switch nameservers at the registrar → wait for the zone to go Active. **Paste:** the CF record list + zone status. **Expected:** record-for-record match with step 1; zone Active. **STOP if:** any record from the capture is absent.
3. > **PAUSE → Rick (MailerSend dashboard):** domain `mrcyberrick.us` still shows **verified** post-move. **Paste:** status. **STOP if not** — re-check the SPF/DKIM/Return-Path records against the capture before proceeding.

**Path 1 — apex cutover:**

4. > **PAUSE → Rick (CF dashboard):** Pages project → Custom domains → add `mrcyberrick.us` (and `www.mrcyberrick.us` if the step-1 capture shows `www` pointing at the site). CF creates/repoints the proxied records. Wait for the TLS certificate to go Active. **Paste:** custom-domain status. **Expected:** Active, cert issued.
5. **Verify (Claude):**
   - `curl.exe -sI https://mrcyberrick.us/` → `200`, `cf-ray` header present (CF serving).
   - `curl.exe -s https://mrcyberrick.us/config.js` → contains `plgegklqtdjxeglvyjte` (prod credentials at the canonical URL).
   - If S4 ran: `curl.exe -sI "https://mrcyberrick.us/comic-preorder/catalog.html?x=1"` → `301` → `/catalog.html?x=1` (old prod links + EF email links survive — § 1.4).

**Path 2 / 2b — subdomain cutover:**

4. > **PAUSE → Rick (DNS host or CF DNS):** add CNAME `pulllist` → `<project>.pages.dev`; then CF dashboard → Pages project → Custom domains → add `pulllist.mrcyberrick.us`; wait for TLS Active. **Path 2b additionally:** CF dashboard → Rules → Redirect Rules → `mrcyberrick.us/comic-preorder/*` → `https://pulllist.mrcyberrick.us/${1}` (301, preserve query string) — requires the `mrcyberrick.us` GH-Pages-pointing record to be **proxied** (orange-cloud) for the rule to fire; confirm root content still loads through the proxy afterward. **Paste:** custom-domain status + (2b) one redirected URL test.
5. **Verify (Claude):** `curl.exe -sI https://pulllist.mrcyberrick.us/` → `200` + `cf-ray`; `curl.exe -s …/config.js` → prod ref; old URL `https://mrcyberrick.us/comic-preorder/` still `200` (GH Pages on Path 2, CF redirect on Path 2b).

**All paths — write-smoke + soak start:**

6. > **PAUSE → Rick (live prod app at the new canonical URL, as a test user):** reserve one item → confirm the row lands in prod `preorders` with the correct `tenant_id` (SQL Editor read or admin view) → cancel it. Send-my-list or another email-sending action once, to confirm MailerSend still delivers post-DNS-change. **Paste:** results. **STOP if:** the write fails or email does not arrive — execute § 6 S5 rollback (DNS restore) and report.
7. **Soak clock starts now.** Record the cutover timestamp in the Deploy Log — S7's three calendar days count from it.
8. **Record (Claude):** Deploy Log row (path taken, DNS capture in notes, timestamps). Commit:
   ```
   docs: 5.1 S5 — prod cut over to CF Pages (path recorded); DNS pre-capture + write-smoke logged
   ```

### S6 — Deployment-workflow doc rewrite (same sitting as S5)

The docs must not lag live state (document-integrity rule) — this runs immediately after S5, not at closeout.

1. **`CLAUDE.md` edits (Claude, targeted — re-read each section from disk first):**
   - § Standard Deployment Workflow: staging deploy step becomes `git push origin staging` → "CF Pages auto-deploys the staging preview at <staging URL>"; **delete** the `git push staging staging:main` line; prod section: after PR merge, "CF Pages auto-deploys production from `main` at <canonical prod URL>". The F59 diff-assertion loop, `config.js` checkout, and write-smoke instructions are **unchanged**.
   - § Project Overview: Production URL / Staging URL lines → the new canonical URLs.
   - § Repository Structure: annotate the `staging` remote — "no longer a deploy target as of 5.1; kept warm as rollback until 5.5 closes."
2. **`docs/technical-reference.md` (Claude):** grep `GitHub Pages|github.io` → update the hosting rows/mentions (§ 1.7 listed lines 29/36/90/96 at planning) to Cloudflare Pages + new URLs, with a "GH Pages warm until 5.5" note where the serving path is described.
3. **Verification greps (Claude):** `Select-String -Path CLAUDE.md -Pattern "git push staging staging:main"` → **0 lines**; `Select-String -Path CLAUDE.md -Pattern "pages.dev|<canonical prod host>"` → expected count derived from the actual edits at execution time, not estimated.
4. **Record (Claude):** Deploy Log row. Commit:
   ```
   docs: rewrite Standard Deployment Workflow for Cloudflare Pages; retire staging-remote deploy step (5.1 S6)
   ```

### S7 — Soak (3 calendar days from the S5 timestamp)

Daily, each of the three days (Claude scripts the checks; Rick runs the browser/dashboard ones):

- `curl.exe -sI <canonical prod URL>` → `200` + `cf-ray` (Claude).
- CF dashboard → Pages project → deployment status green; no failed deploys (Rick, paste).
- Rick loads the prod app once as a normal user — pages render, catalog loads.
- Zero customer reports through the store (973-586-9182 / in-person — Rick's judgment).
- If a normal promotion happens mid-soak, it follows the **new** S6 workflow; a successful mid-soak promotion is a positive soak signal, not a violation.

One Deploy Log row per day. Commit (per day or batched at day 3):
```
docs: 5.1 S7 — soak day N checks recorded
```
**Any soak failure** (CF outage affecting the site, serving regression, customer-reported breakage traced to hosting) → STOP, execute § 6 S5 rollback if customer-facing, and report. The soak restarts from zero after a rollback-and-retry.

### S8 — Closeout (run once, when every § 5 box is ticked)

1. Tick the § 5 boxes with inline result notes (5.0 pattern).
2. This file: Status line → **Complete** + date; Last-updated line.
3. Parent (`phase-5-second-tenant-onboarding.md`): row 5.1 → **Complete** + date; row 5.2 → **Planning** only when its plan file exists (next session writes it).
4. `CLAUDE.md` § Current Migration Phase: active sub-deploy → **5.2 (plan not yet written)**; last-completed sub-deploy → 5.1; § Known Out-of-Scope Items: remove the "Hosting migration … sub-deploy 5.1" line; F67 noted under open findings with its owner.
5. Commit:
   ```
   docs: close Phase 5.1 (hosting migration); advance pointer to 5.2 planning
   ```
6. End-of-session status update per `CLAUDE.md` § Anti-Drift Rules (changed / verified / left / filed / new IDs).

---

## 5. Completion criteria (all must be checked before parent row 5.1 → Complete)

- [ ] S1: all four decisions (Q1 path, Q2 alias + project name, Q3 `_redirects`, Q4 F67 owner) recorded with rationale; deployed EF sources captured from **both** projects; **F67 filed** in § 13 with owner
- [ ] S2: CF Pages project live; production branch `main`, preview branch `staging`; Framework None / blank build / root output; `curl.exe` confirms staging alias serves the staging Supabase ref and the production URL serves the prod ref (no crossover)
- [ ] S2: Supabase Auth redirect allow-lists (both projects) extended with the new origins; no existing entry removed; Site URL unchanged
- [ ] S3: Playwright `baseURL` updated (local-only); full suite green against the new staging URL; Rick verified staging on CF; `git push staging staging:main` retired operationally
- [ ] S4: `_redirects` decision executed — file live on staging + prod with a verified `301` preserving path and query, **or** the skip decision + rationale recorded in the Deploy Log
- [ ] S5: DNS pre-capture stored verbatim in the Deploy Log; canonical prod URL serves from CF (`cf-ray`) with prod `config.js`; TLS active; MailerSend domain still verified (if zone moved); write-smoke passed (reserve → row with correct `tenant_id` → cancel) and one post-cutover email delivered
- [ ] Old-URL continuity: old prod URL (`mrcyberrick.us/comic-preorder/`) and old staging URL still resolve (redirect or warm GH Pages) — EF email links functional pending F67
- [ ] GitHub Pages **not** torn down (either repo); staging remote intact — warm rollback until 5.5
- [ ] S6: `CLAUDE.md` workflow rewritten (zero `git push staging staging:main` matches), URLs updated, remotes note added; `technical-reference.md` hosting mentions updated
- [ ] S7: 3 full calendar days elapsed from the S5 timestamp with all daily checks recorded; zero hosting-attributed customer reports
- [ ] Founding-tenant behavior unchanged (parent invariant): full Playwright suite green at the S3 and post-S5 gates; tenant-isolation specs included
- [ ] Deploy Log complete (one row per executed step + one per soak day); all doc changes committed to `staging`; parent row 5.1 → **Complete** + date; `CLAUDE.md` pointer advanced

---

## 6. Rollback (per step; pre-captures are taken before every change)

- **S2:** delete the CF Pages project — nothing references it yet. Supabase allow-list additions are inert and may stay.
- **S3:** revert `playwright.config.ts:21` to the § 1.3 value (local edit); resume `git push staging staging:main` (the staging GH Pages site is still configured and picks up where it left off).
- **S4:** revert the `_redirects` commit (staging); prod rolls back by re-deploying the prior commit via the standard path. No data dependency.
- **S5 (the real one):** restore the step-1 DNS capture at whichever DNS host is then authoritative — GH Pages resumes serving `mrcyberrick.us` (propagation is TTL-bound; the GH Pages custom-domain configuration was deliberately left in place). Prod GH Pages content is **current**, not stale — it builds from `origin main`, which received every promotion throughout. If a zone move happened, rollback does **not** require moving the zone back: restoring the GH Pages records inside Cloudflare DNS is sufficient and faster.
- **S6:** docs revert with the serving path — if S5 rolls back, revert the S6 commit so `CLAUDE.md` matches reality again (document-integrity rule cuts both ways).
- **S7 failure:** = S5 rollback if customer-facing; CF project is kept for the retry; soak restarts from zero.
- Nothing in 5.1 touches customer data; Tier-3 forward-fix pressure does not apply.

---

## 7. References

- Platform decision: Cloudflare Pages — Rick, 5.1 planning session 2026-06-11.
- Parent: `docs/phase-5-second-tenant-onboarding.md` (row 5.1; § Approach Decisions "hosting before subdomain routing"; § Rollback Notes 5.1 "GH Pages kept warm until 5.5 closes").
- Shape mirror: `docs/phase-5.0-pre-phase-5-housekeeping.md` (execution model, pause-block format, deploy-log resume protocol).
- Findings: `docs/technical-reference.md` § 13. **Next free ID at planning: F67** (consumed by S1).
- Planning-time grep evidence (§ 1.4): repo `staging` + `main` branches, 2026-06-11 — re-verify at execution.
- Playwright suite: `docs/phase-3.7-playwright-smoke-tests.md`; config at `C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts\playwright\playwright.config.ts` (local-only).
- Projects: staging `puoaiyezsreowpwxzxhj`, prod `plgegklqtdjxeglvyjte`. Founding tenant UUID (staging) `72e29f67-39f7-42bc-a4d5-d6f992f9d790`; prod UUID in `catalogs\scripts\phase-4-prod-tenant-uuid.txt` (local-only; needed only to eyeball the write-smoke row's `tenant_id` at S5).
- Recovery anchors: tags `phase-4-cutover-v1` / `phase-4-cutover-v1-staging`; `backups\2026-06-10-phase-4-close\` (no 5.1 step can need them — no data surface — listed for completeness).

---

## 8. Deploy log (filled during execution)

| Date | Step | Result | Notes |
|---|---|---|---|
| 2026-06-11 | S1 | Complete | **Q1:** Path 1 — apex domain `pulllist.app` (registered Namecheap, no existing DNS records; zone move to Cloudflare required at S5; no MailerSend records on this domain — MailerSend remains on `mrcyberrick.us` throughout 5.1). **Q2:** Option A — project name `pulllist`; staging alias `https://staging.pulllist.pages.dev/`; prod Pages URL `https://pulllist.pages.dev/`; canonical prod URL `https://pulllist.app/`. **Q3:** `_redirects` yes — `/comic-preorder/* /:splat 301` and `/comic-preorder-staging/* /:splat 301`. **Q4:** F67 owner = 5.2-adjacent housekeeping commit. **EF deployed sources (Rick paste 2026-06-11; both projects confirmed identical):** approve-customer / register-customer / invite-customer — `STAGING_BASE='https://mrcyberrick.github.io/comic-preorder-staging'` — live prod defect (High), magic-link emails non-functional for prod customers (pre-existing); reset-password — `STAGING_BASE='https://mrcyberrick.us/comic-preorder-staging'` — 404 on anomalous path, live prod defect (High, pre-existing); notify-customers — `https://mrcyberrick.us/comic-preorder/catalog.html` — correct today, breaks at domain migration (Low). **F67 filed** in `technical-reference.md` § 13. |
| 2026-06-11 | S2 | Complete | CF Pages project `pulllist` live: production branch `main` → `https://pulllist.pages.dev/` (prod ref `plgegklqtdjxeglvyjte` confirmed); staging preview → `https://staging.pulllist.pages.dev/` (staging ref `puoaiyezsreowpwxzxhj` confirmed). Both roots `200` + `cf-ray`. Zero credential crossover. Supabase Auth redirect allow-lists extended: staging project + `https://staging.pulllist.pages.dev/**`; prod project + `https://pulllist.pages.dev/**` and `https://pulllist.app/**`. Site URL unchanged in both projects. |

---

**Last updated:** 2026-06-11 (S1–S2 complete — CF Pages project live, both branches verified, auth allow-lists extended)
