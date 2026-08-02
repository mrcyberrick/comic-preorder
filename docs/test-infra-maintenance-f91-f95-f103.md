# Test-Infrastructure Maintenance Session — F91 (GoTrue admin-key flakiness) + F95 (orphaned test profiles) + F103 (seed-month false-red)

**Status:** Planning
**Plan written:** 2026-08-02
**Not a phase sub-deploy** — standalone maintenance session. Phase 5 closed 2026-07-15; Phase 6 not started.
**Target surface:** the **local-only Playwright suite** at `catalogs\scripts\playwright\` — plus a one-time staging data cleanup (F95) and the findings closeout in this repo.
**Authoritative inputs read during planning (2026-08-02):** `CLAUDE.md`; `docs/technical-reference.md` § 13 (F10, F91, F95, F103); live `playwright/fixtures/auth.ts`, `playwright/fixtures/catalog.ts`, `playwright/tests/*.spec.ts`, `playwright/run-smoke.ps1`; `catalogs\scripts\.gitignore`.

---

## 1. Goal

Make the local Playwright suite a **trustworthy gate** again. `CLAUDE.md`'s Definition of Done requires a green full-suite run before a sub-deploy merges, but today the suite:

1. **fails intermittently for reasons unrelated to the code under test** (F91) — so green is not repeatable and red is not diagnostic;
2. **leaves a growing residue of orphaned profiles in the staging founding tenant** (F95) — 87 as of 2026-07-25 and accumulating every run since 2026-06-11;
3. **produces a standing false-red on every founding-tenant row-visibility assertion** whenever the imported catalog month runs ahead of the calendar month (F103) — which is the *normal* state for most of any month.

Together these mean a session running the suite currently cannot distinguish "my change broke something" from "the harness is broken." That is the actual defect being fixed.

## 2. Why bundle these three

All three are local-only fixture defects in the same two files (`fixtures/auth.ts`, `fixtures/catalog.ts`), all three are staging-only with no production or live-app exposure, and all three are verified by the same artifact: a repeatable green full-suite run. `docs/technical-reference.md` § 13 independently reaches this conclusion in all three entries — F95 *"F91 … a future test-infrastructure session could take both together"*; F103 *"all three are local-only fixture defects and a single test-infrastructure session should take them together."* This plan is that session.

## 3. Current state — verified against live code 2026-08-02

Line numbers were read from disk on 2026-08-02. **Re-verify before editing** — the suite is edited directly with no version control (§ 3.1), so it can drift between sessions with no commit trail.

### 3.1 The suite is untracked in *any* repo — this changes how verification works
`catalogs\scripts\.gitignore` is an **allowlist** (`*` then explicit `!` re-includes); `playwright/` is not re-included, and `git ls-files playwright/` returns empty. Confirmed 2026-08-02.

Consequences the executing session must internalize:
- **No `git diff` verification, no rollback-by-revert, no commit trail.** Take a manual copy of `fixtures/auth.ts` and `fixtures/catalog.ts` before editing (§ 8) — that copy *is* the rollback.
- The only committed artifacts from this session are **this plan** and the **findings closeout** in `docs/technical-reference.md` + `CLAUDE.md` (doc-only, to `staging`).
- Verification is **running the suite**, not inspecting a diff.

### 3.2 F91 — GoTrue Admin API vs. new-generation secret keys
`fixtures/auth.ts:10–14` builds one `supaHeaders` object from `SUPABASE_SERVICE_KEY` and uses it for **both** GoTrue Admin calls and PostgREST calls. The three GoTrue Admin endpoints are:
- `createUser` → `POST /auth/v1/admin/users` (line 22)
- `generateMagicLink` → `POST /auth/v1/admin/generate_link` (line 66)
- `deleteUser` → `DELETE /auth/v1/admin/users/:id` (line 60)

The intermittent `403 bad_jwt` ("unrecognized JWT kid `<nil>` for algorithm ES256") hits only these; PostgREST calls with the same key are unaffected. F91's verified diagnosis: GoTrue is trying to parse the presented new-generation secret key *as a JWT* and intermittently failing, whereas F88 established that the Edge Functions' auto-injected key — which stays JWT-shaped underneath — authenticates reliably against the same endpoints.

**Tension the executing session must weigh, not silently resolve:** F91's fix option (b) is "revert these two calls to a legacy-format full-access JWT." That runs directly against the direction of travel — the F86 session retired the **production** legacy keys and flipped the legacy-key toggle on 2026-07-22. Reintroducing a legacy key on staging is defensible as test-only scaffolding, but it is a deliberate step backwards and should be a **recorded decision**, not a default. Prefer (a) confirm current Supabase behaviour, then (c) bounded retry, and fall to (b) only with Rick's explicit sign-off.

### 3.3 F95 — `deleteUser()` swallows its failures, and there are three call paths, not one
`fixtures/auth.ts:56–63` — **neither** fetch checks `res.ok`. Both are fire-and-forget.

Three distinct paths reach it, and a fix that only addresses the `afterAll` one is incomplete:
1. **Fixture teardown (the dominant path).** `authenticatedPage` (line 90) and `adminPage` (line 100) call `deleteUser(userId)` when the fixture tears down — **per test**. Any spec whose `cleanupTestRows()` runs in `afterAll` therefore deletes the profile *before* the preorders are gone, on every single test.
2. **Spec `afterAll` (the path F95 names).** Verified in `tests/06-admin-this-week-bagging.spec.ts:37–40` and `tests/13-arrivals-reconciliation.spec.ts:85–89` — both call `deleteUser(...)` then `cleanupTestRows(FOUNDING)`, in that order. Seven specs call `deleteUser` in total: `04`, `06`, `07`, `09`, `10`, `11`, `13`.
3. **`createUser`'s compensation path.** Line 50 calls `deleteUser(userId)` to roll back a failed profile insert — also unchecked, so a failed compensation is invisible.

Root mechanism is F10: `preorders.user_id → user_profiles.id` is `ON DELETE NO ACTION`, so the delete returns **409 / 23503** while a preorder still references the row. F10 stays open and is **not** in scope here — this session works with the constraint, not around it.

**Cleanup-predicate correction (found during planning, 2026-08-02).** F95's fix direction proposes `DELETE FROM user_profiles WHERE tenant_id = '<staging founding>' AND full_name LIKE 'PW %'`. That predicate is **incomplete**: only three specs pass an explicit `fullName` (`'PW Bagging Customer'`, `'PW Recon Customer'`, `'PW Second Reserver'`). Every user created through the `authenticatedPage`/`adminPage` fixtures takes `auth.ts`'s default — **`'Playwright Test'`** — and would survive that DELETE. The reliable discriminator is the **email pattern**, which every fixture user carries: `pw-<uuid8>@example.test` / `pw-admin-<uuid8>@example.test`. Count both classes before deleting anything.

### 3.4 F103 — seed month is date-derived, page scope is data-derived
`fixtures/catalog.ts:14–17` — `thisCatalogMonth()` returns the **calendar** month. Line 45 — `catalog_month: opts.catalogMonth ?? thisCatalogMonth()`. The catalog page scopes its grid to `Catalog.getLatestMonth()` (newest month **in data** for that tenant). Founding-tenant seeds therefore land in a month the page never renders whenever imports run ahead of the wall clock — which is the normal case. The synthetic per-run tenant is immune because its only row *is* the seeded one, which is why `07-tenant-isolation` shows user-A failing and user-B passing on the same assertion.

**Do not** fix this by pinning a hardcoded month — that relocates the same drift. Make the default **data-derived** with a `thisCatalogMonth()` fallback for tenants with no rows, which preserves synthetic-tenant behaviour exactly.

## 4. Scope

### IN
- **F91:** determine whether new-generation secret keys are supported against GoTrue Admin endpoints; implement the chosen remedy in `fixtures/auth.ts` (separate header set for the three admin calls, and/or bounded retry-with-backoff); record the decision and its rationale.
- **F95:** (a) reorder teardown so preorder/subscription rows are gone before the profile delete — in **both** the fixture teardown and the spec `afterAll`s; (b) make `deleteUser()` check `res.ok` and throw (the silent-failure habit is the actual finding); (c) one-time staging cleanup of accumulated orphans using the corrected predicate (§ 3.3), counted before deleted.
- **F103:** make `seedCatalogRow()`'s `catalog_month` default data-derived (one PostgREST read mirroring `getLatestMonth()`), falling back to `thisCatalogMonth()` when the tenant has no rows; keep `thisCatalogMonth()` available as an explicit opt-in for specs that deliberately test month scoping.
- **Optional, only if the three above are green and time remains:** add coverage for the catalog **info-card** reserve path (`#modal-reserve`, `#modal-qty`, `.reserved-indicator`) — the gap F103 flags, and the reason four defects shipped there unnoticed in July 2026.
- **Findings closeout:** F91/F95/F103 in `docs/technical-reference.md` § 13; `CLAUDE.md` § Open findings.

### OUT — stop and ask
- **F10** (`ON DELETE NO ACTION` FKs). It is the mechanism behind F95 but it is an open *structural* finding with unresolved intent, and changing it alters production delete semantics. Work with it; do not "fix" it here.
- Any change to `app.js` / `*.html` / `style.css` / `config.js` / Edge Functions / the import scripts. If a fixture fix appears to require an application change, that is a finding, not a scope expansion.
- Any production database touch. This session is **staging-only**; the one-time cleanup runs against staging exclusively.
- Rotating, replacing, or editing any credential value, or editing `.env`. If F91's remedy needs a different key, Rick provisions it and updates `.env` — the agent never sees or writes key values.
- Rewriting the suite's architecture, upgrading Playwright, or restructuring specs beyond the teardown-ordering change.
- Retiring or re-pointing `run-smoke.ps1`'s stages (its `[2/2]` Playwright stage runs against the **deployed** staging site — see `CLAUDE.md` § Smoke-test ordering; that ordering is correct and settled).

## 5. Runbook

Order matters: **F91 first**, because until the suite stops failing for unrelated reasons, no subsequent verification is trustworthy.

### S0 — Pre-flight
1. Read `CLAUDE.md` in full. Confirm no active sub-deploy, and re-read § Smoke-test ordering and § Known Issues (the `.ps1` BOM trap — see S5).
2. Read this plan in full, then `docs/technical-reference.md` § 13 entries for **F10, F91, F95, F103**.
3. Re-read from disk: `playwright/fixtures/auth.ts`, `playwright/fixtures/catalog.ts`, and the `afterAll` blocks of specs `04/06/07/09/10/11/13`. **Confirm the § 3 line numbers still match** — the suite is untracked and may have drifted.
4. **Take the rollback copy** (§ 3.1): copy `fixtures/auth.ts` and `fixtures/catalog.ts` to the session scratchpad before any edit.
5. Confirm `.env`'s `SUPABASE_URL` is **staging** (`puoaiyezsreowpwxzxhj`) — `run-smoke.ps1` aborts on prod, but check before running anything ad hoc.
6. Re-check § 13 for the next free finding ID (**F107** at planning time).
7. **Baseline run:** `.\run-smoke.ps1`, and record the exact failure set. This is the before-picture every later gate is measured against. Expect F103-shaped failures on founding-tenant specs and possibly F91-shaped `403 bad_jwt` failures. Distinguish them by error signature — they are different findings and must not be conflated.

### S1 — F91: GoTrue admin-key reliability
1. **Establish the current contract (Claude, read-only):** check Supabase's current documentation on whether new-generation secret keys are supported against `/auth/v1/admin/*`, versus PostgREST/Storage only. Record what the docs actually say, with a link and date — this is the fact the remedy choice turns on. If the documentation is silent or ambiguous, say so plainly rather than inferring.
2. **Choose the remedy and record it:**
   - If admin endpoints are documented as supported → the failure is transient; implement **bounded retry-with-backoff** around the three admin calls (option c).
   - If unsupported or undocumented → implement retry as mitigation **and** surface the legacy-key question (option b) to Rick as an explicit decision, noting the F86 tension (§ 3.2). **Do not adopt a legacy key unilaterally.**
3. **Implement** in `fixtures/auth.ts`: give the three GoTrue Admin calls their own header set / helper so they are separable from PostgREST calls, and wrap them in the chosen retry. Retries must be bounded and must **fail loudly** when exhausted — never silently continue.
4. > **PAUSE → Rick** if and only if step 2 concludes a credential change is needed. Rick provisions and updates `.env`; **paste confirmation only, never a key value.**
5. **Gate V1:** run the full suite **three consecutive times**. Expect **zero** `bad_jwt`/`403` failures across all three. One occurrence means not fixed — F91 is an intermittent finding and a single green run never proved anything about it.

### S2 — F95: teardown ordering, loud failures, and the one-time cleanup
1. **Make `deleteUser()` strict (`fixtures/auth.ts:56–63`):** check `res.ok` on the `user_profiles` DELETE and throw with status + body on failure. Keep the GoTrue delete's own check consistent. Note the interaction with `createUser`'s compensation path (line 50) — a throw there must not mask the original error; wrap it so the *original* failure is what surfaces.
2. **Fix the ordering in both paths:**
   - Fixture teardown (`auth.ts:90`, `:100`) — the per-test path, and the one F95's write-up under-weights.
   - Spec `afterAll`s — `06:37–40` and `13:85–89` call `deleteUser` before `cleanupTestRows`; swap them. Audit the other five (`04/07/09/10/11`) for the same shape.
   - Either reverse the order, or have `deleteUser()` clear the user's `preorders`/`subscriptions` first. Prefer whichever leaves teardown correct **regardless of call order**, since the fixture path and the `afterAll` path interleave.
3. **Count before deleting (Rick, staging SQL Editor):**
   ```sql
   -- Staging only. Count both orphan classes before removing anything.
   SELECT full_name, COUNT(*)
   FROM user_profiles
   WHERE tenant_id = '72e29f67-39f7-42bc-a4d5-d6f992f9d790'
     AND (email LIKE 'pw-%@example.test' OR full_name LIKE 'PW %' OR full_name = 'Playwright Test')
   GROUP BY full_name ORDER BY COUNT(*) DESC;
   ```
   Expect > 87 (87 was the 2026-07-25 count; runs have continued since). **Sanity-check that no row here is a real staging customer** before proceeding.
4. > **PAUSE → Rick (staging SQL Editor)** — delete the counted rows, then re-run the count. **Expected:** 0. Any non-zero means a preorder still references a profile — investigate rather than forcing.
5. **Gate V2:** run the full suite, then re-run the count query. **Expected:** 0 new orphans. This is the assertion that actually proves F95 fixed — a green suite alone does not.

### S3 — F103: data-derived seed month
1. In `fixtures/catalog.ts`, add a helper that reads the target tenant's newest `catalog_month` (`?tenant_id=eq.<id>&select=catalog_month&order=catalog_month.desc&limit=1`), mirroring `Catalog.getLatestMonth()`. Cache per tenant per run — this runs on every seed.
2. Change `seedCatalogRow()`'s default (line 45) to that value, falling back to `thisCatalogMonth()` when the tenant has no rows. Keep `thisCatalogMonth()` exported for explicit opt-in.
3. **Gate V3:** run specs `02`, `03`, `07` specifically. **Expected:** the founding-tenant (user-A) assertions that failed in the S0 baseline now pass, and the synthetic-tenant (user-B) assertions still pass — the split F103 identifies as its own proof must disappear in one direction without breaking the other.

### S4 — Optional: info-card reserve coverage
Only if V1–V3 are green and time remains. Add a spec covering the catalog info-card reserve path (`#modal-reserve`, `#modal-qty`, `.reserved-indicator`): open the card, reserve, assert the qty badge and reserved indicator update on **both** the modal and the underlying grid card, then cancel. If this is not reached, say so plainly in the status update and leave the F103 coverage-gap note standing in § 13.

### S5 — Verification and closeout
1. **Gate V4:** three consecutive full `.\run-smoke.ps1` runs, all green, with the orphan count still 0 afterwards.
2. **If any `.ps1` was edited** (not expected): restore the UTF-8 BOM and confirm the script still reaches its last stage — `CLAUDE.md` § Known Issues documents a silent stage-skip that exits 0. Do not skip this check on the assumption the edit was trivial.
3. Update `docs/technical-reference.md` § 13: F91, F95, F103 → resolved, each recording what was actually done (for F91, the documented Supabase behaviour and the remedy chosen). If any is only partially resolved, say so with the residual named — do not round up to resolved.
4. Update `CLAUDE.md` § Open findings.
5. Doc-only commit to `staging`. **The suite changes themselves are not committable** (§ 3.1) — note in the status update that they live only on this machine.
6. `/wrap-up`.

## 6. Verification gates

| Gate | Assertion | Why this and not a weaker one |
|---|---|---|
| **V1** (F91) | 3 consecutive full runs, **0** `bad_jwt`/`403` | F91 is intermittent — one green run is not evidence |
| **V2** (F95) | Post-run orphan count = **0** | A green suite does not detect orphans; only the count does |
| **V3** (F103) | Founding-tenant assertions in `02`/`03`/`07` pass; synthetic-tenant ones still pass | The tenant split is F103's own proof; both directions must hold |
| **V4** (all) | 3 consecutive full green runs, orphan count still 0 | The actual goal: a *repeatably* trustworthy gate |
| **V5** | § 13 + `CLAUDE.md` updated; plan committed to `staging` | Document Integrity |

## 7. Completion criteria

- [ ] S0 baseline recorded, with F91-shaped and F103-shaped failures distinguished by signature
- [ ] Rollback copies of both fixture files taken before any edit
- [ ] **F91:** Supabase's current admin-endpoint contract established and recorded; remedy implemented; any legacy-key decision explicitly signed off by Rick, never defaulted into
- [ ] **F95:** `deleteUser()` checks `res.ok` and throws; teardown ordering fixed in the fixture path *and* the spec `afterAll`s; staging orphans counted, deleted, re-counted to 0
- [ ] **F103:** seed month data-derived with a no-rows fallback; `02`/`03`/`07` founding-tenant assertions pass without breaking synthetic-tenant ones
- [ ] V1–V5 green
- [ ] § 13 and `CLAUDE.md` updated; doc-only commit pushed to `staging`
- [ ] Status update notes explicitly that the suite changes are **uncommitted and machine-local**
- [ ] Any new defect filed from **F107** (verify the next free ID at execution — do not assume)

## 8. Rollback

- **Fixture edits:** restore the S0 scratchpad copies of `fixtures/auth.ts` / `fixtures/catalog.ts`. There is no git history for these files — the manual copy is the only rollback, which is why S0 step 4 is not optional.
- **F95 one-time cleanup:** destructive and irreversible. The counted-and-reviewed SELECT before the DELETE is the safeguard; capture the row list before deleting so anything removed in error can be identified.
- **F91 credential change (if any):** the previous key stays valid until explicitly revoked — do not revoke anything in this session.
- **Doc commits:** normal `git revert` on `staging`.

---

## References

- `docs/technical-reference.md` § 13 — **F91** (admin-key flakiness, full diagnosis), **F95** (orphaned profiles, reproduction), **F103** (seed-month false-red, tenant-split proof), **F10** (the `NO ACTION` FKs — out of scope, the mechanism behind F95), **F88** (why the Edge Functions' auto-injected key authenticates reliably where a manually-configured one does not), **F86** (prod legacy-key retirement — the tension F91 option (b) runs against).
- `CLAUDE.md` § Smoke-test ordering (the suite tests the **deployed** site — a pre-push run exercises the previous build); § Known Issues (the `.ps1` BOM trap); § What's tracked vs local-only (the suite is in no repo).
- `docs/phase-3.7-playwright-smoke-tests.md` — the suite's canonical design detail.
- Suite files (local-only, untracked, re-read before editing): `catalogs\scripts\playwright\fixtures\auth.ts`, `fixtures\catalog.ts`, `tests\*.spec.ts`, `run-smoke.ps1`.
- Staging founding tenant: `72e29f67-39f7-42bc-a4d5-d6f992f9d790`. Staging project `puoaiyezsreowpwxzxhj` (prod `plgegklqtdjxeglvyjte` — **not touched by this session**).
