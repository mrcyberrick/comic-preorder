# Import.js Maintenance Session — F75 (key rotation) + F78 (historical dedup) + F85 (cross-month carry-forward root fix)

**Status:** Planning
**Plan written:** 2026-07-15
**Not a phase sub-deploy** — standalone maintenance session. Touches only the **private scripts repo** (`comic-preorder-scripts`, working tree `catalogs\scripts\`) plus one-time prod/staging data cleanup. No `app.js`/`*.html`/`config.js`/Edge-Function changes in this repo.
**Target:** land before the early-August 2026 monthly import (the same import cycle that would otherwise reproduce F85).
**Authoritative inputs read during planning (2026-07-15):** `CLAUDE.md`, `docs/technical-reference.md` § 13 (F75/F76/F78/F80/F84/F85), `catalogs\scripts\security-findings-local.md` (F75 full detail, local-only), current `import.js` / `import-staging.js` (read from disk 2026-07-15 — do not trust older summaries of these files).

---

## 1. Goal

Close out three related, `import.js`-local defects before the early-August 2026 catalog rollover:

1. **F75** — rotate the exposed service-role key values (staging + prod). The code-level hardcoding fix already landed 2026-07-08 — this session finishes the job.
2. **F78** — reconcile historical duplicate `catalog` rows created before the F84 distributor-label fix (2026-07-09). The row-creation mechanism itself is already fixed by F84; this is a one-time cleanup of pre-existing bad data.
3. **F85** — fix the root cause so a re-listed `item_code` carries a subscriber's reservation forward to the new month's catalog row instead of minting a duplicate preorder.

## 2. Why bundle these three

All three are local-only changes to `import.js`/`import-staging.js` (or one-time cleanup of data those scripts wrote). F78 and F85 both touch the monthly catalog-rollover path, so one careful end-to-end staging import re-run verifies both at once — bundling avoids paying that verification cost twice. This is the disposition already recorded against all three findings in `docs/technical-reference.md` § 13.

## 3. Current state — re-verified 2026-07-15, do not trust older summaries

Two of the three findings turned out to be **partially resolved already** by unrelated later work. Confirm this against live source again at execution time (files may have moved further since this plan was written) — do not just trust this section.

- **F75 Part 1 (credential refactor) is DONE.** Scripts-repo commit `c2e37c6` (2026-07-08, "bring import scripts under version control, credentials extracted to .env"). Verified 2026-07-15: both scripts call `loadDotEnv()`/`requireEnv()`, load from a gitignored `.env`, hard-fail on a missing var, and assert `SUPABASE_URL` targets the correct project (`import.js:57-71`, `import-staging.js:57-64`). Zero hardcoded literal remains in either script.
  **NOT yet done:** the actual key **rotation** (the local note's steps 2–4) — the values exposed in the 2026-06-19 CLI transcript may still be live. This is the real remaining risk and the reason F75 stays open.
- **F78's original "harden the upsert key" fix idea is superseded.** F84 (2026-07-09) found the real root cause was an *inverted* distributor label in `normalizeShipment` (not a genuine cross-distributor channel split), and fixing that label removes F78's row-duplication mechanism going forward — F84's own text: "no *new* \[duplicate rows\] are produced" on a corrected import. What's left for F78 is **purely historical**: duplicate `catalog` rows written *before* 2026-07-09 still exist and need reconciling. (An upsert-key hardening as defense-in-depth is optional, not required — see § 4 IN, optional item.)
- **F85 is fully open.** `autoReserveSubscriptions()` in both scripts (`import.js:486-586`, parallel in `import-staging.js`) builds `existingSet` from preorders scoped to **only the current month's catalog ids** (`import.js:543` / `import-staging.js:542`, keyed `${user_id}||${catalog_id}`). It has no cross-month awareness, so a returning subscriber's prior-month reservation on a re-listed `item_code` is invisible to this check, and a new (duplicate) preorder gets inserted every time the item is re-listed.
- **F85's one-time prod data cleanup already ran** (2026-07-10, ~45 pairs consolidated, 0 remain per the 2026-07-15 post-import re-verification). **Do not re-run that cleanup.** This session's F85 work is the **code fix** to stop it recurring.
- **F78's historical reconciliation has NOT been done.** Needs its own detection + cleanup (§ 5 Step 3) — a different table (`catalog`, not `preorders`) and a different cause than F85's cleanup.

## 4. Scope

### IN
- **F75:** rotate the staging current-generation API key; migrate the prod legacy full-access JWT → a new current-generation key (then disable the legacy key); confirm both scripts authenticate against the new values; confirm the old values are dead.
- **F78:** detect historical duplicate `catalog` rows (pre-2026-07-09, same `tenant_id`+`item_code`+`catalog_month`, differing `distributor`); consolidate any `preorders`/`reservation_history`/`usage_events` rows pointing at a loser onto a chosen survivor; delete loser rows; re-run detection to confirm 0 groups remain. Both envs.
- **F78 (optional, defense-in-depth — do only if time remains, do not let it block F75/F85):** a fallback in the catalog upsert or a pre-insert dedup keyed on `upc`/`item_code`, mirroring how F76's distributor-agnostic display match was kept post-F84. Not required.
- **F85:** modify `autoReserveSubscriptions()` in both scripts so a subscriber's existing reservation for the same `item_code` (any prior month) is **carried forward** (`UPDATE` the existing preorder's `catalog_id`, preserving `created_at`) instead of inserting a new row. Add unit test(s) to the scripts repo's node-test suite. End-to-end staging import re-run verifying: (a) UUID preservation for untouched preorders, (b) a re-listed-`item_code` case carries forward correctly with `created_at` retained, (c) no new duplicates minted for unrelated items.
- **Findings closeout:** update F75/F78/F85 in `docs/technical-reference.md` § 13 to resolved (or accurately re-dispositioned if something doesn't land); update the local `security-findings-local.md` F75 entry; update `CLAUDE.md` § Open findings.

### OUT — stop and ask
- Any change to this repo's `app.js`/`*.html`/`config.js`/Edge Functions. F85's own finding text is explicit that no web-app change is required for the root fix.
- Re-running F85's already-complete 2026-07-10 prod preorder cleanup.
- Letting the optional F78 upsert-key hardening grow into a restructuring of `buildCatalogIdMap` that risks reopening F84 — if it looks like more than a small addition, stop and ask rather than push it through.
- Any Phase 5/5.5/Phase 6 scope — Phase 5 closed 2026-07-15; this session is unrelated maintenance.
- Rotating or touching any other secret (`TENANT_PROVISION_SECRET`, MailerLite webhook secrets, etc.) — different secrets, different findings, not in scope here.

## 5. Runbook

### Step 0 — Pre-flight
- Read `CLAUDE.md` in full; confirm no active phase/sub-deploy conflicts (Phase 5 closed 2026-07-15; Phase 6 not started).
- Read this plan in full.
- Read `catalogs\scripts\security-findings-local.md` F75 entry (full detail; local-only, never committed to this repo).
- Read `docs/technical-reference.md` § 13 F75/F78/F84/F85 entries.
- In the scripts repo (`catalogs\scripts\`): `git status` → clean; `git log --oneline -5` → confirm at or after `01a90b6`.
- Confirm `.env` exists with the documented vars (never print values).
- Re-check `docs/technical-reference.md` § 13 for the next free finding ID before assuming it's still F86.

### Step 1 — F75: rotate the staging key
1. > **PAUSE → Rick (Supabase dashboard, STAGING project `puoaiyezsreowpwxzxhj`)** — API Keys: revoke the current-generation key backing `IMPORT_SERVICE_KEY`; create a new one. **Paste:** confirmation only, never the value.
2. Rick updates `.env`'s `IMPORT_SERVICE_KEY` directly — the agent never edits `.env` or handles the value.
3. Dry-run `node import-staging.js --no-write <args>` → confirms auth + correct project targeting. **STOP if auth fails.**

### Step 2 — F75: migrate the prod key
1. > **PAUSE → Rick (Supabase dashboard, PROD project `plgegklqtdjxeglvyjte`)** — API Keys: create a new current-generation key. **Do not revoke the legacy full-access JWT yet** — sequencing matters (see footgun). **Paste:** confirmation only.
2. Rick updates `.env`'s `IMPORT_SERVICE_KEY_PROD`.
3. Dry-run `node import.js --no-write <args>` → confirms auth against the new key.
4. Only after the dry-run succeeds: > **PAUSE → Rick** — revoke/disable the legacy full-access JWT in the prod dashboard. **Paste:** confirmation.
5. **Footgun (from the local F75 note):** rotating before the `.env` update lands breaks the script — it hard-fails loudly via `requireEnv()` (the safe failure mode), but don't let that surprise you mid-session. Land the `.env` update first, verify, then revoke the old key.

### Step 3 — F78: historical duplicate-row detection + reconciliation
1. Detection query (run by Rick in each env's SQL Editor — never by the agent on prod):
   ```sql
   SELECT tenant_id, item_code, catalog_month, COUNT(*) AS n,
          array_agg(id) AS catalog_ids, array_agg(distributor) AS distributors
   FROM catalog
   WHERE catalog_month < '2026-07'   -- rows written before the F84 fix (2026-07-09)
   GROUP BY tenant_id, item_code, catalog_month
   HAVING COUNT(*) > 1;
   ```
2. For each group: choose a survivor (prefer the row whose `distributor` matches the item's actual catalog listing; if ambiguous, prefer the row with existing `preorders`). Re-point `preorders`/`reservation_history`/`usage_events` rows referencing the loser(s) onto the survivor. Delete the loser `catalog` row(s).
3. Re-run the detection query → expect 0 rows.
4. Staging first, verify, then prod. Every write is Rick-in-the-loop (prod SQL Editor).

### Step 4 — F85: root fix
1. In both scripts' `autoReserveSubscriptions()`: add `item_code` to the `CATALOG_URL` select; add a query for prior-month `catalog` rows sharing this month's `item_code`s (same tenant); fetch `preorders` against those older ids; build a cross-month existing-reservation map keyed `${user_id}||${item_code}`. In the match loop, a cross-month hit becomes an `UPDATE` (`catalog_id` → this month's `match.id`, `created_at` untouched) instead of an `INSERT`; the current insert-if-not-reserved-this-month logic stays for everything else.
2. Add unit test(s) to the scripts repo's node-test suite: prior-month reservation on a re-listed `item_code` → carry-forward (`UPDATE`, not `INSERT`), `created_at` preserved; a genuinely new `item_code` still inserts normally.
3. `node --check` both scripts.
4. `--no-write` dry run against staging showing carry-forward candidates without writing.
5. > **PAUSE → Rick** — a real staging import re-run (synthetic or real re-listed `item_code`) to verify end-to-end: unrelated preorder UUIDs unchanged; the carry-forward case updates `catalog_id` and retains `created_at`; no new duplicate preorder created. **Paste:** results.

### Step 5 — Findings closeout
1. `docs/technical-reference.md` § 13: F75 → resolved (sanitized past-tense entry replacing the placeholder, no key values) if rotation is fully confirmed; F78 → resolved (historical rows reconciled; cross-reference F84 as the root-cause fix, don't re-describe it); F85 → resolved (root fix + verification summary).
2. Update (not delete — historical record) the local `security-findings-local.md` F75 entry to reflect full resolution.
3. `CLAUDE.md` § Open findings line: remove resolved items from the "bundled into the `import.js` session" callout; leave anything that didn't land with an accurate status.
4. Doc-only commit to `staging` (this repo) for `technical-reference.md`/`CLAUDE.md`; a separate commit in the scripts repo for the script + test changes.

## 6. Verification gates

- **V1** — `node --check` both scripts, clean.
- **V2** — new F85 unit tests pass; full existing scripts-repo suite still green (29+ tests as of 2026-07-08).
- **V3** — F75: dry run confirms new-key auth on both envs; old key confirmed revoked/disabled (Rick attestation).
- **V4** — F78: detection query returns 0 duplicate groups on both envs after cleanup.
- **V5** — F85: staging import re-run shows correct carry-forward behavior (`UPDATE` not `INSERT`, `created_at` preserved) and zero new duplicates for unrelated items.
- **V6** — Preorder UUID preservation: spot-check a sample of untouched preorders before/after the staging import re-run — same UUIDs.

## 7. Completion criteria

- [ ] F75: staging + prod keys rotated; old values confirmed dead; both scripts verified against new keys
- [ ] F78: 0 duplicate `catalog`-row groups on both envs (detection query re-run); consolidation preserved all referencing rows
- [ ] F85: root fix landed in both scripts; unit tests added and green; staging import re-run verifies carry-forward behavior
- [ ] All three findings updated in `docs/technical-reference.md` § 13 (resolved or accurately re-dispositioned)
- [ ] `CLAUDE.md` § Open findings line updated
- [ ] Scripts-repo changes committed (own repo, own commit); main-repo doc changes committed to `staging`
- [ ] Landed before the early-August 2026 monthly import

## 8. Rollback

- **F75:** the old key stays valid until explicitly revoked (steps sequenced so revocation is last) — reverting `.env` to the old value is an immediate rollback if the new key misbehaves; retry rotation after.
- **F78:** consolidation is destructive (row deletion) — capture a pre-cleanup export of each group before deleting so a bad survivor choice can be reconstructed. Run staging first and let it sit before touching prod.
- **F85:** the code change is a plain `git revert` in the scripts repo; the fix performs no data migration itself (only future imports behave differently), so reverting is clean.

---

## References

- `docs/technical-reference.md` § 13 — F75 (placeholder + partial-fix note), F76, F78 (as corrected 2026-07-15), F80 (same cross-month family), F84 (root cause of F78, superseding its original fix), F85.
- `catalogs\scripts\security-findings-local.md` — full F75 detail (local-only, never committed to this repo).
- `CLAUDE.md` § What's tracked vs local-only — scripts-repo boundary, `.env` handling, SQL authoring rules.
- Verification precedent for a similar bundled local-script session: `docs/phase-4.5-prod-import-merge.md` (patch-inventory + verification-gate structure this plan mirrors).
