# Next work — sequencing items 4–7 (F158 repoint, Admin Settings close-out + promotion, F161, F157)

**STATUS:** IN PROGRESS — A DONE 2026-09-29 (prod data, 1 row, Rick-run) · B DONE 2026-09-29 (staging; V2/V4/V10 closed, no app code) · C–E not started · planned 2026-09-29 · staging=— · prod=— · PR=— · findings: F158, F161, F157 (advances; none consumed), F164 (filed by Session B)

A sequencing plan, not a sub-deploy. It orders **five sessions** (A–E), one concern each, per
CLAUDE.md's one-sub-deploy-per-session rule. Session C carries its own plan doc
(`admin-settings-catalog-visibility.md`), and that doc governs it. This one only sets the order,
the decisions Rick owes first, and what each session is allowed to touch.

**Precondition, met 2026-09-29:** `october-import-closeout-and-doc-truth.md` is COMPLETE. The
October import ran on production 2026-09-27 and was clean, which lifts the hold on Admin Settings S4
and F157 (CLAUDE.md § Current Migration Phase).

---

## 0. Order, and why

| # | Session | When | Writes | Rick decides first |
|---|---|---|---|---|
| **A** | F158: repoint Albert Abaunza's CIMMERIAN reservation | **TODAY, before Wed 09-30 bagging** | 1 production row, **run by Rick** | Repoint (recommended) vs. leave |
| **B** | Admin Settings: close V2 / V4 / V10 on staging | Next | none to app code. Local harness/spec only | V10's fate if the auth fix doesn't stabilise it |
| **C** | Admin Settings: production promotion | After B is green | production RPC (Rick) + PR | **Promotion shape** (§ 3.1) |
| **D** | F161: which Lighthouse metric, and is it data volume? | Any time; independent | staging seed + teardown only | — |
| **E** | F157 distributor-scoping: **design only** | Last; implementation deferred | none | Confirm the deferral |

D touches nothing that A–C touch, so it can run alongside them. E is last on purpose (§ 5).

**Ambient, not in scope, stated so nobody trips on it:** production's `order_deadline` is **empty**.
The October import cleared it (value `''`, `updated_at` 2026-09-27T23:32Z), and Step 7 is Rick's
planned step after this week's shipment. Until it is set, the At-Risk and Backordered panels classify
without a deadline (F108), and F133's date-dependent specs have no ambient value. Neither affects
A–E; it only matters when reading those panels.

---

## 1. Session A — F158: Albert Abaunza's reservation will be missed at bagging (TODAY)

**Measured read-only 2026-09-29 (production, service-role):**

| `catalog` row | `catalog_month` | `on_sale_date` | its one reservation |
|---|---|---|---|
| `aa2ecf77-435f-43dd-bdee-ccb8d6fef4a9` (live) | 2026-05 | **2026-09-30** | the other customer, `fulfilled=true` at 2026-09-27T23:32 (the import; legitimate, see below) |
| `f9acb743-d0aa-4319-8131-1b88ff5d3ab8` (orphan, pre-F136) | 2026-06 | 2026-07-22 (dead) | **Albert**, `fulfilled=true` since 2026-06-12, `arrival_outcome` NULL |

**Why it is urgent, not just untidy.** `catalogs/Shipment-detail-LUNAR.csv` (the 09-27 shipment
import) lists **`0526AZ0504` CIMMERIAN CVR A, on-sale 9/30/2026**, so the book is physically arriving
Wednesday. The live row's re-fulfilment on 09-27 is therefore correct, not an F158 recurrence. But
the This Week bagging list selects on `catalog.on_sale_date` within the Mon–Sun week
(`admin.html:3946-3947`), and Albert's row carries 2026-07-22. **His copy arrives Wednesday with no
bag on the list.** The ledger is right (qty 2 ordered 2026-05-24), so the copy exists; only the
assignment is lost.

**Fix (recommended): repoint his reservation onto the live row.** This follows F136 S3's precedent,
which repointed two unfulfilled reservations the same way. It leaves `fulfilled=true`, now genuinely
backed by shipment evidence, and changes nothing else. The orphan row is left in place with zero
reservations, the same accepted category as F136's 27 historical survivors.

**Rick runs this in the production SQL Editor. The agent does not write to production.**

```sql
BEGIN;
-- PRE-CHECK: expect exactly 2 rows, two DIFFERENT user_ids (so the repoint cannot collide
-- with an existing reservation by the same user on the live row).
SELECT p.id, p.user_id, p.catalog_id, p.fulfilled
FROM public.preorders p
WHERE p.catalog_id IN ('aa2ecf77-435f-43dd-bdee-ccb8d6fef4a9',
                       'f9acb743-d0aa-4319-8131-1b88ff5d3ab8');

UPDATE public.preorders
SET    catalog_id = 'aa2ecf77-435f-43dd-bdee-ccb8d6fef4a9'
WHERE  catalog_id = 'f9acb743-d0aa-4319-8131-1b88ff5d3ab8'
RETURNING id, user_id, catalog_id, fulfilled;
-- EXPECT exactly 1 row returned. 0 or 2+ -> ROLLBACK; and stop.
COMMIT;
```

**What failure looks like, stated first so the check can fail:** the pre-check shows the same
`user_id` twice (a collision → ROLLBACK), or the UPDATE returns anything other than one row, or it
raises (a trigger on `preorders` → ROLLBACK and report; do not work around it).

**Verify, then record:**
- A fresh read shows 2 reservations on `aa2ecf77…` and 0 on `f9acb743…`.
- Admin → This Week lists **both** customers under CIMMERIAN CVR A. The staff surface is the real
  acceptance test.
- § 13 F158: append a dated line. The orphaned-duplicate decision is **resolved (repointed)**, and
  the 2026-09-27 re-fulfilment of the live row is explained as legitimate shipment evidence, so a
  later reader does not mistake it for a recurrence. Update the CLAUDE.md F158 row's last clause.
- **Out of scope:** the 60-row F158 triage (still parked), and deleting the orphan catalog row.

**If Rick prefers not to repoint:** the fallback is operational. Tell staff to bag one CVR A for
Albert by hand this week. Record that choice, because the defect then recurs on every surface that
reads `catalog.on_sale_date`.

---

## 2. Session B — Admin Settings: close V2, V4, V10 on staging

Governing doc: `docs/admin-settings-catalog-visibility.md` (§ 5 gates, § 5.1 V2 snippet, § 9 boxes).
Read it in full first. Staging only.

1. **V2 (parity).** Run § 5.1's self-contained browser snippet in a signed-in staging admin session.
   It reimplements the old `getReservedPublishers()` with `db` alone, so S4's deletion of that
   function does not block it (the plan's own correction, § 5 V2 row). PASS = identical publisher
   sets at threshold 7. Any difference is investigated, never waved through.
   **Note:** staging still reads `catalog_month` **2026-09** (October was not imported there). V2
   compares two implementations over the same data, so this does not matter, but state it in the
   result.
2. **V4 (print volume) — re-derive, do not reuse.** The row's figures (2,068 rows / 45 pages, and
   1,507 / 33) were measured against **September** production data. Production is now on **2026-10**.
   Re-measure read-only on production: FOC-eligible rows with no config, then with the 58
   formerly-under-bar publishers excluded. Record the October numbers as the ones Rick should
   expect on paper. The claim V4 actually has to prove is *"no config → nothing hidden except
   past-FOC"*. It does not depend on the month.
3. **V10: fix the harness's auth, not its assertions.** § 9 records that failures land in
   `settle()`, never in a filtering assertion, and names **F107 magic-link pressure** as a candidate.
   Every other harness in this project that hit that shape was fixed by switching to a
   **password grant + `addInitScript`** session (F156's harness; `admin-tab-counts-pending-verify.mjs`).
   Apply the same change to `playwright/tests/24-catalog-visibility.spec.ts`, then run it **three
   times** with no code change between runs. Land it only if all three pass (remove
   `describe.skip`).
   Negative-control **one** assertion: invert it, see it go red, restore it.
   **If it is still flaky after the auth change:** stop. Ask Rick whether to accept
   `s4-visibility-verify.mjs` (7/7, already green) plus a V4a case added to it as the standing
   evidence, and record V10 as not landed and why. Do not keep grinding.
4. **V4a**, if V10 lands: it is in V10. If not, add it to the `.mjs` harness.
5. Tick § 9's boxes only for what actually ran. Full suite once at the end
   (`npx playwright test --reporter=line > log`, then read the `N passed` line; CLAUDE.md
   § Smoke Test Suite).

**Out:** any `app.js` / HTML change. If V2 or V10 exposes a real defect, stop and ask.

---

## 3. Session C — Admin Settings: production promotion

Only after B is green and Rick explicitly requests it via `/promote-prod`.

### 3.1 The decision Rick owes before this session: promotion SHAPE

`staging` is **119 commits ahead of `main`** (measured 2026-09-29, counting this doc). The settings work (S2 + S4 + `71ce076`) touches
`app.js` (which carries `merge=ours`), **all seven nav pages**, `admin.html`, `catalog.html` and
`style.css`. Those same pages carry unpromoted F72 S1a/S3 edits on staging (`data-paid-only`,
`Tier`, `print-store-info`).

- **Option 1 — full `staging → main` merge (recommended).**
  - It ships everything already verified on staging: F72 S0–S3, F153, F154, the settings work, and
    the `register-tenant` / `register-customer` source. It also clears the owed "`main` behind
    production runtime" drift (CLAUDE.md, the S0 close-out).
  - The customer-visible risk is bounded. `rjbookstop` is `plan='pro'` (V13, verified), and F72's
    paid branch was proven byte-identical to today's render. `comicstore` is demo-only.
  - It is the documented `git merge staging --no-ff` flow, which is immune to F125. By contrast,
    every **cherry-pick** promotion across this divergence has had to hand-repair `app.js` (PRs
    #149, #152, and F162's direct edit), and this one would have to cherry-pick nav edits across
    seven files whose context has diverged.
- **Option 2 — cherry-pick the settings work only.** A smaller blast radius, at the highest
  mechanical risk this project has recorded. If chosen: stat-line comparison per commit, a
  `git apply` restore for `app.js`, and nav/footer hash verification across all seven pages on the
  **promotion branch**.

### 3.2 Sequence (either option)

1. **Production RPC first (F105).** Rick runs `docs/sql/2026-09-23-publisher-reserve-counts-rpc.sql`
   on production. *(2026-09-29: Rick applied **v1**; probed present. **v2**, with the F164 predicate, is owed on staging then production, and V2 is re-run between them.)* The agent confirms with the behavioural probe (PGRST202 → absent; anything else →
   present) and updates the file's STATUS line to `prod=APPLIED <date>`. No client merge before this.
2. `/promote-prod` end to end: `config.js` preserved, F59 merge-**result** assertion,
   `supabase/migrations/` still 2 files, PR file list re-read on GitHub.
3. **V11**, against the served bytes (`curl -L`), positive and negative: `CatalogFilters` present;
   `getReservedPublishers` ×0; `settings.html` returns 200; the prod ref ×1, the staging ref ×0.
4. **Tell Rick what customers and staff will see.** Past-FOC titles leave the customer catalog, and
   the printed catalog grows to the page count Session B measured for October. Neither should come
   as a surprise at the counter.
5. Write-smoke: **not** skippable this time. The diff touches `catalog.html` and `app.js`, which are
   on the reserve path.
6. Close § 9, the STATUS token, and the CLAUDE.md "Last completed work" entry. If Option 1 was
   chosen, also mark F72 S0–S3 / F153 / F154 as promoted in their own records. Each has its own
   STATUS/§ 13 line that will otherwise go stale (the F132/F138/F139/F145 pattern).

---

## 4. Session D — F161: which metric, and is it data volume?

Governing record: § 13 F161. Measurement only, with no fix in this session.

1. **Per-metric, on production, as Rick** (his DevTools reading is the acceptance instrument; a
   synthetic probe has diverged from his real account three times, per F141). My List, three runs.
   Record FCP / LCP / TBT / CLS / SI and the score. **Name the account and its preorder count.**
2. **Control 1:** the same three runs on production as a **small** account.
3. **Control 2, the discriminating one:** on **staging**, seed one throwaway customer with a
   production-sized reservation count (~1,300, `ZZTEST161-` style, tenant-scoped, `tenant_id` passed
   explicitly, dry-fit one row first per `/sql-check`). Measure My List as that user, then tear down
   FK-ordered and confirm zero rows and zero orphaned auth users by a fresh read.
   - Staging with a heavy account ≈ production heavy → **data volume**. Next step: a render/DOM fix.
   - Staging stays ~98 → **environment** (hosting, data shape, third-party covers).
4. Record in § 13 F161 and the CLAUDE.md row. **Reconcile each breakdown against its total**
   (F156's lesson).

---

## 5. Session E — F157 distributor-scoping: design now, implement later (recommended)

§ 13 F157's remaining half makes `delete_dropped_catalog_items` (an RPC with **no distributor
parameter**) and `computeWithdrawalCandidates()` distributor-scoped. **Recommendation: write the
design, defer the build.** Three reasons, each checkable:

1. **The reachable harm is already closed.** The 2026-09-07 zero-row guard refuses a file that
   normalises to nothing, and it behaved correctly on the real October run. What remains unguarded is
   a *legitimately* single-distributor import, which today is only a **single-distributor tenant**.
   That is Phase 6 territory, and Phase 6 is a stub.
2. **It rewrites code that has still never met a live candidate.** The October close-out recorded
   that F147's FOC narrowing "did not discriminate" (no candidate reached it) and F146's clear half
   saw 0 marks. Changing `computeWithdrawalCandidates()` now would stack an unexercised change on an
   unexercised fix, in the exact code that produced 519 false marks once.
3. **It is a cross-environment RPC signature change.** A new `p_distributor` on
   `delete_dropped_catalog_items` means a `docs/sql/` migration on both projects, in lock-step with
   both import scripts. It is worth doing once, deliberately, not squeezed in.

**Session E deliverable:** `docs/f157-distributor-scoping.md`, with STATUS NOT STARTED, containing
the RPC signature change (plus a backward-compatible default, so a stale script cannot break), the
`computeWithdrawalCandidates()` change, the unit-test cases (including a single-distributor tenant
import), the verification gates, and the **trigger to build it**: the first single-distributor
tenant, or Phase 6 S0, whichever comes first. Commit it doc-only. **If Rick overrides and wants it
built now,** that becomes a separate scripts-repo session against this doc.

---

## 6. Done when

- [x] A: Albert's reservation on the live row; This Week shows both customers; F158 records updated.
      (Or Rick's fallback choice recorded) — **DONE 2026-09-29**: Rick's UPDATE returned 1 row; fresh
      read = 2 on `aa2ecf77…` / 0 on `f9acb743…`; bagging-shaped query for 2026-09-28..10-04 returns
      Book Stop + Albert Abaunza. § 13 F158 and the CLAUDE.md row updated
- [x] B: V2 run and recorded; V4 re-measured on October data; V10 landed 3/3 **or** its
      disposition decided by Rick and recorded; § 9 boxes reflect only what ran — **DONE 2026-09-29**
      (record: `admin-settings-catalog-visibility.md` § 5.2). **V2:** threshold-7 sets identical (5 = 5); the
      snippet's stricter per-publisher gate printed `V2 FAIL`, fully explained by **F164** (2 staging preorders
      referencing `demoshop` catalog rows; production 0 of 3,495). **V4** (production, October, read-only):
      no config **2,038 rows → 46 pages**; 46 under-bar publishers hidden **1,546 → 35 pages**; page counts
      MEASURED on the real print (44.0-44.3 rows/page; the plan's ÷46 understated). **V10:** landed — 3
      consecutive runs 3/3, `--retries=0`; the recorded F107 diagnosis was wrong (an overlapping-load race in
      `settle()`); Rick approved one bounded attempt. **Two things Session C now owes Rick (both in § 9):**
      **Q8** (the default hides 177 still-orderable October titles) and the **F164 RPC-predicate** choice.
      **The first full-suite run was 146 passed / 4 failed** (all spec 20, from a settings-page save at 10:07:51
      mid-run that the suite's teardown then overwrote); **the rerun after Q8 is CLEAN: 151 passed, 0 failed, 0
      flaky, 23.2 min.** Rick's decisions 2026-09-29: Q8 = default "FOC earlier than today" (landed `e64f3d8`);
      F164 predicate = add it (written as RPC v2, `7c31e5c`, PENDING on both environments; v1 is deployed, and
      Rick applied it on production the same day). Session C is unblocked on Rick's side once v2 is applied and
      V2 re-run; see `admin-settings-catalog-visibility.md` § 5.2 and § 9
- [ ] C: Rick's promotion-shape choice recorded; prod RPC applied and probed; PR merged; V11 green;
      write-smoke green; every affected STATUS line updated
- [ ] D: per-metric numbers for three accounts/conditions recorded in F161, cause classified
- [ ] E: `docs/f157-distributor-scoping.md` committed (or Rick's override recorded)
- [ ] This doc's STATUS token → COMPLETE
