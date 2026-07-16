# F86 — Prod Legacy API Key Retirement (config.js anon-key migration)

**Status:** In progress — Step 1 staging rehearsal complete (V1–V3 green); Step 2 (prod publishable key creation) next
**Plan written:** 2026-07-15 (planning session; no code, config, or dashboard changes made)
**Execution session opened:** 2026-07-15
**Not a phase sub-deploy** — standalone maintenance session, successor to the `import.js` maintenance session (F75/F78/F85, closed 2026-07-15). Closes F86 and the last F75 residual.
**Target:** no hard deadline; schedule the prod toggle flip on a quiet day — NOT a Tuesday/Wednesday (weekly shipment + bagging) and NOT during the early-August monthly import week.
**Authoritative inputs read during planning (2026-07-15):** `CLAUDE.md` (incl. § Credential Safety), `docs/technical-reference.md` § 13 F75/F86, `docs/import-js-maintenance-f75-f78-f85.md`, `config.js` on both branches (key **format** inspected only), `vendor/supabase.min.js` (both branches), all 8 `supabase/functions/*/index.ts`, `_headers`, Supabase official migration guide + GitHub issue supabase/supabase#37648.

---

## 1. Goal

Retire the prod legacy API keys (the combined `anon` + `service_role` legacy-JWT pair): migrate prod `config.js` from the legacy `anon` JWT to a new-generation publishable key, verify the live app, then flip prod's single "Disable legacy API keys" toggle — killing the legacy `service_role` JWT from F75's original 2026-06-19 exposure event. This is the coordinated migration F86's disposition calls for.

## 2. Current state — verified 2026-07-15, re-verify at execution time

Do not trust this section blindly at execution time; each fact below lists how it was verified so it can be re-checked cheaply.

- **Staging web app is ALREADY on a publishable key — and always has been.** `git show staging:config.js` → `SUPABASE_ANON_KEY = 'sb_publishable_…'`; true in **both** commits that ever touched staging `config.js` (`0047d25` 2026-03-06, `5d48579` 2026-06-15). Staging has therefore run the entire app (all phases, two-tenant soak, full Playwright suite) on a publishable key for 4+ months. **The staging branch's `config.js` needs NO change in this session.**
- **Prod `config.js` is the only legacy-JWT consumer in either repo tree.** `git grep -l 'eyJhbGciOi'` across the full `staging` and `origin/main` trees returns exactly one hit: `origin/main:config.js` (`SUPABASE_ANON_KEY = 'eyJ…'`). One line changes.
- **supabase-js compatibility is settled.** The client is self-hosted `vendor/supabase.min.js`, pinned **2.110.1**, byte-identical on both branches (same commit `9579ce1`). Staging's 4-month publishable-key history is the compatibility proof — no library change needed, no CDN involved (the F79-era "versioned jsdelivr URL" note is obsolete; `_headers` already serves the vendored bundle `no-cache`).
- **`import.js` is unaffected.** Already on a current-generation `sb_secret_` key since F75 (closed 2026-07-15).
- **The toggle is officially reversible.** Supabase migration guide: legacy keys can be re-activated after disabling "if you find a client you missed."
- **`_headers` serves `/config.js` `Cache-Control: no-cache`** (F79 fix) — a deployed key swap reaches every returning browser on next revalidation, and a rollback deploy does too. No 4-hour cache-skew window.
- **⚠️ NEW RISK found in planning — Edge Functions.** All 8 functions read the **platform-injected** `SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY` env vars (e.g. `create-paper-customer/index.ts:13-14`), which carry the **legacy** JWTs. Whether disabling legacy keys re-points these injected vars to new-generation values is **not documented**, and closed GitHub issue supabase/supabase#37648 reports they can keep the legacy JWTs → every function call fails with "Legacy API keys are disabled." Supabase also injects `SUPABASE_PUBLISHABLE_KEYS` / `SUPABASE_SECRET_KEYS` (JSON objects keyed by key name, e.g. `default`) as the supported successors. **This plan resolves the question empirically on staging (Step 1) before prod is touched.** If functions break, the contingency (Step 1-C) migrates them — a normal tracked-code change through the standard deploy flow.
- **Unknown at planning time (check live in Step 0):** whether the *staging* project's legacy keys are still enabled (assumed yes — nothing has ever flipped them), and whether Rick's local-only PS test scripts (`test-magic-link.ps1`, `test-this-week.ps1`) or any external caller (MailerLite webhook → Edge Function URL, no apikey expected) use a prod legacy key.

## 3. Scope

### IN
- Staging rehearsal: flip staging's "Disable legacy API keys" toggle; verify web app + Edge Functions end-to-end; short soak.
- **Conditional** (only if the staging rehearsal proves the injected env vars break): migrate the 8 Edge Functions' key loading to `SUPABASE_PUBLISHABLE_KEYS` / `SUPABASE_SECRET_KEYS` (with legacy fallback), deployed staging-first then prod through the normal flow.
- Prod: Rick creates a new publishable key; Rick edits `main`'s `config.js` (one line, value never seen by the agent); deploy via PR to `main`; live verification incl. a real reserve/cancel write-smoke; flip prod toggle; post-toggle verification; confirm both legacy keys are dead.
- Findings closeout: F86 → resolved; F75 residual note updated; `CLAUDE.md` § Open findings + § Known Out-of-Scope Items updated.

### OUT — stop and ask
- **The agent editing `config.js` or proposing/handling any credential value — in any step, ever.** Rick edits `config.js` by hand from values only he sees; the agent's runbook names the file and line, never a value (CLAUDE.md § Credential Safety).
- Renaming the `SUPABASE_ANON_KEY` constant in `config.js`/`app.js`. The publishable key is a drop-in value for the same variable (staging proves it); renaming would churn `app.js` for zero behavior change.
- Rotating any other secret (`FOUNDING_TENANT_ID`, `TENANT_PROVISION_SECRET`, MailerLite webhook secrets) — different findings.
- Any Phase 6 work; F72 email branding; anything else adjacent.

## 4. Runbook

### Step 0 — Pre-flight
1. Read `CLAUDE.md` in full; confirm no phase/sub-deploy conflict and that F86 is still open with next free finding ID F87.
2. Re-verify § 2's facts: key-format check on both branches' `config.js` (`git show <branch>:config.js` — inspect the **prefix** only, never paste a full value into the transcript); `git grep -l 'eyJhbGciOi'` on both trees; `vendor/supabase.min.js` identical on both branches.
3. > **PAUSE → Rick (Supabase dashboard, BOTH projects → Settings → API Keys):** confirm current state — legacy keys enabled/disabled per project, and which new-generation keys already exist. **Paste: descriptions only, never values.**
4. > **PAUSE → Rick:** check the two local PS test scripts' `.env`/inline keys — do any use a **prod legacy** key? If yes, note them for update at Step 4 (local-only, Rick edits).

### Step 1 — Staging rehearsal (answers the Edge Function question before prod)
Staging's `config.js` is already publishable, so flipping staging's toggle tests exactly what prod will experience — with zero prod risk.
1. > **PAUSE → Rick (staging project `puoaiyezsreowpwxzxhj`):** flip "Disable legacy API keys." **Paste: confirmation.**
2. Web-app verification: full Playwright suite (`.\run-smoke.ps1`) against staging — must be green.
3. Edge Function verification (the injected-env-var question): exercise **`create-paper-customer`** on staging with a throwaway test customer — it uses BOTH injected vars (`SUPABASE_ANON_KEY` for the in-body auth check, `SUPABASE_SERVICE_ROLE_KEY` for the write), so one call answers the question for the whole fleet. Then tear the test customer down (live SELECT returning zero rows). Also exercise `register-customer` (public, service-role-only path) with a throwaway signup, torn down the same way.
4. **If step 3 fails with a legacy-keys error → Step 1-C.** If it passes, record the evidence (functions keep working post-toggle) and skip 1-C.
5. Soak: leave staging's toggle disabled **≥ 24 hours** (amended from the original ≥48h — see § 6a Session 2, Rick's call) of normal staging use, then re-run the Playwright suite once. Green → proceed.

### Step 1-C — Contingency: Edge Function key-loading migration (only if Step 1.3 failed)
1. **Stop and confirm with Rick before starting** — this widens the session to tracked Edge Function code.
2. In all 8 functions, replace `Deno.env.get('SUPABASE_ANON_KEY')` / `Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')` with a small shared pattern: parse `SUPABASE_PUBLISHABLE_KEYS` / `SUPABASE_SECRET_KEYS` (JSON keyed by key name — confirm the actual key names live in the dashboard first) and fall back to the legacy vars if absent. No behavior change otherwise.
3. Deploy to staging (`supabase functions deploy`, staging project), re-run Step 1.3. Green → deploy the same code to prod **before** Step 5 (prod functions must be ready before prod's toggle flips). Commit through the normal staging→main flow.

### Step 2 — Prod publishable key creation
> **PAUSE → Rick (prod project `plgegklqtdjxeglvyjte` → Settings → API Keys):** create a new **publishable** key. **Do NOT flip the prod toggle yet.** **Paste: confirmation only, never the value.**

### Step 3 — Prod `config.js` migration + deploy
1. Branch off `main`: `git checkout main` → `git pull origin main` → `git checkout -b chore/f86-prod-publishable-key`. (The edit lands on a main-lineage branch, NOT via staging — the standard promote flow's `git checkout main -- config.js` step deliberately preserves main's `config.js` and would silently drop a key change routed through staging. CLAUDE.md § Credential Safety: config.js key changes are made manually per-branch; staging's copy already has its publishable key, so only main changes.)
2. > **PAUSE → Rick:** in `config.js` on this branch, replace the **value** of the `SUPABASE_ANON_KEY` constant (the `const SUPABASE_ANON_KEY = 'eyJ…'` line) with the new publishable key value. Nothing else changes — same variable name, same quoting. Commit it himself (`chore: migrate prod anon key to publishable (F86)`).
3. Agent verifies the diff **shape** without reading values: `git diff main --stat` → exactly one file (`config.js`); `git show` the diff and confirm the only change is that one constant's value, old prefix `eyJ`, new prefix `sb_publishable_`.
4. Push branch, open PR → `main`, merge after checks. CF Pages auto-deploys `main`.
5. Live verification at https://pulllist.app/ (hard refresh not required — `_headers` serves `config.js` no-cache, but do one anyway): real login page load, catalog loads, then the standard post-deploy **write-smoke** — reserve one item as a test user, confirm the row lands in prod `preorders` with correct `tenant_id`, cancel it.
6. **The legacy anon key is still enabled at this point** — if anything is wrong, rollback is a one-commit revert of the `config.js` change (Step 7). Do not proceed to Step 5 until 3.5 is fully green.

### Step 4 — Quiet window before the toggle
Let prod run on the publishable key through **at least one weekly shipment cycle (a Wednesday)** with no anon-key-related errors (browser console spot-check + admin flows during normal store use). Rick updates any local PS test scripts flagged in Step 0.4 during this window.

### Step 5 — Flip the prod toggle
1. Re-confirm: Step 3.5 green, Step 4 window elapsed, and (if 1-C ran) the migrated Edge Functions are deployed to prod.
2. > **PAUSE → Rick (prod project):** flip "Disable legacy API keys." **Paste: confirmation.**
3. Immediately verify: pulllist.app page load + login; one reserve/cancel write-smoke; one Edge Function exercise (same `create-paper-customer` + teardown pattern as Step 1.3, prod tenant); `comicstore.pulllist.app` page load (tenant 2 shares the same `config.js`).
4. If anything fails → re-enable legacy keys (reversible), diagnose, fix, retry. A failure here is a halt-and-report, not an improvise.

### Step 6 — Confirm the legacy keys are dead (closes the F75 residual)
> **PAUSE → Rick:** one PostgREST request against prod with the OLD legacy `service_role` JWT (the F75-exposed credential — using it to prove it's dead is the point) and one with the OLD legacy `anon` key → both must be rejected with the legacy-keys-disabled error. Use `curl.exe --data-binary @file` per the PowerShell/Invoke-RestMethod gotcha. **Paste: status/error text only.**

### Step 7 — Findings closeout
1. `docs/technical-reference.md` § 13: F86 → resolved (dates, verification summary); append a resolution note to F75's Residual line pointing at F86's closure.
2. `CLAUDE.md`: § Open findings (remove F86; F72 remains); § Known Out-of-Scope Items (remove the F86 entry).
3. This plan: tick Completion criteria, set Status: Complete + date.
4. Doc-only commit(s) to `staging`. (The `config.js` commit itself lives on main-lineage from Step 3; if 1-C ran, its function code went through the normal flow.)

## 5. Verification gates

- **V1** — Staging: full Playwright suite green with staging legacy keys disabled.
- **V2** — Staging: `create-paper-customer` (both injected vars) + `register-customer` (service-only) succeed post-toggle; test fixtures torn down (live SELECT = 0 rows). If 1-C ran: same result with the migrated functions, both envs.
- **V3** — Staging soak ≥ 24h post-toggle (amended from ≥48h, § 6a Session 2), suite re-run green.
- **V4** — Prod deploy diff: `config.js` only, one constant's value, `eyJ` → `sb_publishable_` (shape verified by agent, value never read).
- **V5** — Prod live on publishable key: page load + login + reserve/cancel write-smoke green, both tenant domains, BEFORE the toggle.
- **V6** — Prod post-toggle: page load + write-smoke + one Edge Function exercise green, both tenant domains.
- **V7** — Both prod legacy keys (anon + service_role) provably rejected (Step 6 attestation).

## 6. Completion criteria

- [x] Staging rehearsal complete: toggle flipped, V1–V3 green (staging toggle stays disabled permanently — it's the desired end state there too)
- [x] Edge Function injected-env-var question answered with recorded evidence; 1-C either skipped-with-evidence or landed on both envs
- [ ] Prod `config.js` on publishable key, deployed, V4–V5 green
- [ ] One weekly shipment cycle elapsed on the new key before the prod toggle (Step 4)
- [ ] Prod "Disable legacy API keys" flipped; V6 green
- [ ] V7: legacy `service_role` JWT (F75's exposed credential) and legacy `anon` key confirmed dead
- [ ] F86 resolved + F75 residual annotated in `technical-reference.md` § 13; `CLAUDE.md` § Open findings and § Known Out-of-Scope Items updated
- [ ] All doc changes committed (doc-only → `staging`); plan status set to Complete

## 6a. Execution log

**Session 1 — 2026-07-15:**
- **Step 0 complete.** Re-verified live: `staging:config.js` → `sb_publishable_1jCe5…`; `main:config.js` → `eyJhbGciOiJIUzI1NiIs…`; `git grep 'eyJhbGciOi'` on both trees — main tree's only hit is `config.js` (as predicted), staging tree's only hit is this plan doc's own prose (not a credential); `vendor/supabase.min.js` blob hash `df4539ad…` identical on both branches. Rick confirmed via dashboard: legacy keys enabled on both envs, no new-gen keys created yet (matches plan assumption). Rick confirmed neither local PS test script (`test-magic-link.ps1`, `test-this-week.ps1`) references a prod legacy key.
- **Step 1.1 done.** Rick flipped staging's "Disable legacy API keys" toggle (project `puoaiyezsreowpwxzxhj`).
- **V1 green.** Full Playwright suite (19/19) passed against staging post-toggle. Synthetic test tenant created + torn down cleanly by the suite's own fixtures.
- **V2 green.** Throwaway-fixture script (ephemeral admin test user → session token → real deployed-function calls; full teardown; scratch-only, never committed) confirmed **both** Edge Functions work post-toggle using the platform-injected env vars:
  - `create-paper-customer` → HTTP 200 (exercises both `SUPABASE_ANON_KEY` for the in-body `/auth/v1/user` check and `SUPABASE_SERVICE_ROLE_KEY` for the writes)
  - `register-customer` → HTTP 200 (service-role-only path, secret-gated)
  - All 3 synthetic test emails confirmed at 0 rows post-teardown (live SELECT).
  - **Conclusion: the platform-injected env vars are NOT stuck on legacy JWTs after the toggle flip.** supabase/supabase#37648's failure mode did not reproduce here.
- **Step 1-C skipped** — Step 1.3 passed outright, no Edge Function code migration needed.
- **Step 1.5 (soak) open, not yet elapsed.** Staging's toggle was flipped 2026-07-15; needs ≥48h elapsed before V3 (Playwright suite re-run) can run. **Next session:** confirm ≥48h has passed since the Step 1.1 toggle flip, re-run `.\run-smoke.ps1` for V3, then proceed to Step 2 (Rick creates the prod publishable key).

**Session 2:**
- **Soak window amended: ≥48h → ≥24h, Rick's explicit call.** Rick confirmed ≥24h had genuinely elapsed in real time since the Step 1.1 toggle flip (asked directly before treating any run as the V3 gate — see CLAUDE.md Definition of Done: a soak must be fully elapsed, never "checks green so far"). Runbook Step 1.5 and gate V3 updated above from 48h → 24h to match. Staging's toggle has remained disabled continuously since Session 1 with no intervening re-enable.
- **V3 green.** Full Playwright suite re-run post-soak: 19/19 passed. Synthetic test tenant created + torn down cleanly.
- **Step 1 (staging rehearsal) fully complete** — toggle flipped, V1/V2/V3 all green, staging's legacy-key toggle stays disabled permanently (desired end state). **Next: Step 2** — PAUSE → Rick creates the prod publishable key (dashboard, project `plgegklqtdjxeglvyjte`).
- **Out-of-scope discovery (filed, not fixed inline):** local `.env`'s `SUPABASE_SERVICE_KEY_PROD` (added 5.5 S2, 2026-06-19, per `docs/phase-5.5-second-tenant-onboarding.md` — a manual GoTrue rollback fallback for tenant-provisioning mishaps) is unused by any tracked script (confirmed via repo-wide grep) and was sourced *before* F75's 2026-07-15 rotation, which only touched the separate `IMPORT_SERVICE_KEY_PROD`. It is plausibly still a legacy JWT, which Step 5's combined prod toggle will kill regardless of rotation timing. **Rick's call: rotate it himself now** (dashboard + local `.env` edit, entirely his action — local-only file, no repo/plan impact, agent did not see or handle the value).
- **Step 2 done.** Rick confirmed a new prod publishable key was created (project `plgegklqtdjxeglvyjte`); legacy toggle left untouched. **Next: Step 3** — branch off `main`, Rick edits `config.js` by hand.

## 7. Rollback

- **Before the prod toggle (Steps 3–4):** the legacy anon key is still valid, so rollback is a single revert commit of the `config.js` change on `main` (CF Pages redeploys; `_headers` no-cache means browsers pick it up immediately). Trivially reversible by design — this is why the toggle is sequenced last.
- **After the prod toggle (Step 5+):** re-enable legacy keys in the dashboard (officially supported, immediate); the app keeps running on the publishable key regardless — re-enabling only resurrects the legacy pair while the failure is diagnosed.
- **Staging toggle:** same re-enable path if the rehearsal breaks something unexpected; nothing customer-facing depends on staging.
- **1-C function code:** plain `git revert` + redeploy; the legacy-fallback branch in the pattern means reverting is never load-bearing mid-migration.

---

## References

- `docs/technical-reference.md` § 13 — F86 (this finding), F75 (parent; residual this closes), F79 (`_headers` no-cache — why key swaps propagate instantly).
- `docs/import-js-maintenance-f75-f78-f85.md` — precedent session (structure, Rick-in-the-loop gating, key-rotation sequencing footgun).
- `CLAUDE.md` § Credential Safety (agent never edits `config.js`; per-branch tracking; the `git checkout main -- config.js` promote step), § Standard Deployment Workflow.
- Supabase: [Migrating to publishable and secret API keys](https://supabase.com/docs/guides/getting-started/migrating-to-new-api-keys) (order of operations; toggle reversibility); [supabase/supabase#37648](https://github.com/supabase/supabase/issues/37648) (injected env vars may keep legacy JWTs after disable — the Step 1/1-C question).
