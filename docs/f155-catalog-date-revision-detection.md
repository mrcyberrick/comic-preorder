# F155 — Catalog date-revision detection

**STATUS:** STAGING COMPLETE (S1 + S2 + S3 both halves) · staging=2026-09-05 · prod=— · PR=— · findings: F155
**S3 APPROVED by Rick, 2026-09-04** — see § 5.1. **§ 9 remediation script delivered** — see § 10.

Owner doc for F155. Full finding narrative lives in `docs/technical-reference.md` § 13 F155;
this doc is the execution plan.

---

## 0. Why this exists

A distributor revises a title's in-store date after solicitation. Our catalog keeps the original.
Once that stale date passes, three things happen in order, all silent:

1. **The customer loses sight of it first.** `mylist.html:937` scopes the My List table to
   `catalog_month === currentMonth`, and `mylist.html:884` scopes Upcoming Arrivals to
   `on_sale_date >= today`. A title from an older month whose stale date has just passed is in
   **neither**. `classifyReservedDateDrift()` already names this exact state — its `stranded`
   list carries a `hidden` flag whose comment reads *"the customer cannot see it at all."*
2. **It never reaches a bagging list.** This Week is keyed on `on_sale_date`. The stale week has
   passed; the real week will never match.
3. **It is marked fulfilled.** `auto_fulfill_past_on_sale()` sets `fulfilled = true` at the next
   import, and F115 writes `arrival_outcome = 'unknown'`. Only *now* does it surface, in Never
   Arrived — after the customer has been told "Order placed" for a book that has not shipped.

Found live by Rick, 2026-09-04: **DNX #1 [HIDDEN/DOUBLE COVER]** (PRH `75960621519500111`),
solicited 2026-05 with in-store 2026-09-02, revised by PRH to **2026-09-16**. Two reservations.
PRH's website and the order invoice both show 09/16; **no file we can download does.**

---

## 1. What was measured (2026-09-04, production, read-only)

Load-bearing facts. Do not re-derive; re-measure if this date is stale.

### 1.1 Both distributors revise dates in place — while a catalog is live

Freshly-downloaded files vs. live production `catalog` rows:

| File | Titles whose in-store date differs from the DB |
|---|---|
| PRH 2026-07 | **108** (4 with open reservations) |
| PRH 2026-06 | 27 |
| PRH 2026-08 | 19 |
| PRH 2026-09 | 4 |
| PRH **2026-05** | **0 of 1,078** |
| Lunar (All Products) | **13** across 2026-07 / 2026-08 |

Revisions move in **both directions**. `FIRE AND ICE #5` (Lunar `0826DE0733`) moved
**2026-10-28 → 2026-09-30** — a month *earlier*. That direction is operationally worse: the book
arrives before the bagging list expects it.

### 1.2 PRH freezes a catalog ~2 months before its last titles ship

- May master data: **byte-identical MD5** (`438958a0b69b961ab140ab63c9b3f3bf`) across two
  downloads 44 minutes apart, and **0 of 1,078 rows** differ from what was imported in May.
- May's Weekly Change Reports run **2026-04-24 → 2026-07-31 and stop.** Rick holds the final one;
  DNX #1 does not appear in it (0 occurrences, grepped).
- **84 May titles are still future-dated today.** PRH stops maintaining the catalog while a tenth
  of it has yet to ship.
- No re-listing channel: **0 of 5,123** PRH `MainIdentifier`s appear in more than one monthly file,
  so `auto_fulfill_past_on_sale()`'s newest-listing logic (F122) can never rescue a PRH title.

**Consequence, and it is the pivot of this whole plan: for a frozen PRH catalog, no data channel
exists.** DNX #1's real date is unreachable from any PRH export. Detection cannot solve it; only
the guard (S3) can.

### 1.3 Lunar's All-Products export is one file and covers everything

`Lunar Available Products - <MMDDYYYY>.csv`, from Resources → **All Products CSV Order Form**:

- **17,490 rows**, catalog months back to at least 2025-08
- Columns: `Code, Qty, Title, Retail, Due Date, FOC, In-Store, UPC, ISBN, EAN, Category,
  Publisher, Notes, Imprint, CountryOfOrigin, TitleNote`
- Covers **559 of 568 (98.4%)** distinct Lunar codes holding open reservations
- One download. No code lists, no paste batches, no per-month navigation.

The 9 uncovered codes (7× 2026-07, 2× 2026-06) are the file's one limit: it lists *available*
products, so sold-out and withdrawn items drop out. `0726DC0300` (DC CONNECT #76 bundle, past
on-sale) is one of them. **Those belong to the guard, not to detection.**

### 1.4 Guard load is small

- F115's real September production import classified **arrived=212, unknown=6**.
- Today, **7 titles** would be affected by S3's deferral.
- **0 titles** currently show shipment evidence against a future DB date — the early-arrival case
  is real per § 1.1 but has no live instance, so it is handled in S2's report, not the guard.

### 1.5 The runbook actively tells the operator not to look

`docs/monthly-catalog-refresh.md:130-132`:

> *"Repeat for PRH's still-open months **if** its active-export file has been re-downloaded; PRH's
> export omits withdrawn titles rather than revising dates in place (see F110), so **this step
> matters most for Lunar**."*

Measurably false — § 1.1. This is why PRH months have never been re-pulled, and it is the finding
proper.

---

## 2. Scope

**IN**
- S1 — correct the runbook line (doc-only)
- S2 — `check-dates.js`: a weekly, targeted date re-check reusing `classifyReservedDateDrift()`
- S3 — bounded deferral in `auto_fulfill_past_on_sale()` + the admin panel change that keeps
  deferred rows visible

**OUT — deliberately**
- **Recovering frozen PRH catalogs.** Measured impossible (§ 1.2). Not a scoping choice.
- **A sticky "manually corrected" column.** Re-importing a frozen month restores the stale date.
  v1 answer is the runbook note in S1; a schema-level override is separate work.
- **Notifying customers when a date moves.** Rick, 2026-09-04: *"Even late corrections help reset
  expectations with in-store dates."* Worth doing; not this plan.
- **Changing what `auto_fulfill_past_on_sale()` does once evidence exists.** Unchanged.
- **`import.js`'s monthly Step 3 sweep.** S2 complements it; it is not replaced.

---

## 3. S1 — runbook correction (doc-only, ship first)

**DONE, staging, 2026-09-04.** `docs/monthly-catalog-refresh.md` Step 3 rewritten: item 4 corrected
(the wrong sentence is preserved verbatim inside the correction note, per this project's convention
of recording what a doc used to claim); new item 5 records the PRH freeze; new item 6 records the
re-import-reverts trap; the old item 5 renumbered to 7. Item 1 also gained Lunar's three-month
publishing limit and an explicit warning that the All-Products export is a **different schema** and
**cannot** be fed to `import.js` — it is `check-dates.js` input, not re-import input.

What it now states:

- PRH **does** revise `OnSaleDate` in place in master data, for as long as the catalog is live
  (§ 1.1) — and its website agrees with the file, confirmed by Rick 2026-09-04 against
  `82771403586500111` / `82771403545200211`, so **master data is authoritative for a live catalog**
- PRH master data **freezes** ~3 months past the catalog date, and change reports stop with it
  (§ 1.2) — past that point the month is unrecoverable and only S3 protects it
- Lunar publishes only **three** monthly files, but the All-Products export covers every month
  (§ 1.3) — prefer it
- **Re-importing an older month restores whatever that file says**, so any hand-corrected date is
  silently reverted by the F146 withdrawal-clearing sweep. Re-run S2 after any older-month import.

No code. Ships independently of S2/S3.

---

## 4. S2 — `check-dates.js` (detection)

**BUILT 2026-09-04** — scripts repo `main` `f2d31ec`, allowlisted in `.gitignore` alongside
`reconcile-shipment.js` / `f136-audit.js` (it is a recurring tool, not a one-off remediation).
**Not yet run with writes against production** — the `--no-write` pass is recorded in § 6.

New script in the **scripts repo**, alongside `f136-audit.js` / `reconcile-shipment.js`.
Deliberately **not** a flag on `import.js`: that script archives, purges, upserts a whole month and
auto-reserves, and none of that may happen here.

### 4.1 Operator workflow — 2 files, 3 actions, Friday/Saturday

Cadence set by Rick 2026-09-04: he pulls shipment files Friday/Saturday, arrivals land Monday,
fulfilment runs Wednesday. Corrections therefore land **four days ahead** of the run that would
otherwise mis-fulfil them.

1. Lunar → Resources → **All Products CSV Order Form** → save to the re-check folder
2. PRH → the live catalog the script names → **Master Data** → save to the same folder
3. `node .\check-dates.js`

Per Rick's *"limit number of steps when possible"*: **one command, one inline prompt**, matching
`import.js`'s own convention. No dry-run/`--write` two-step.

### 4.2 Behaviour

- Reads every CSV in the folder; detects Lunar-vs-PRH by header shape (`Code`/`In-Store` vs
  `MainIdentifier`/`OnSaleDate`)
- Matches DB `catalog.item_code` to Lunar `Code` / PRH `MainIdentifier`
- Feeds `classifyReservedDateDrift()` (`import.js:517`) — **reused, not reimplemented**, so the
  `corrected` / `stranded` / `unreserved` split and the `hidden` flag come for free
- **Reports both directions**, and flags *earlier* moves separately — a title pulled forward misses
  its bagging week, which no existing surface catches (§ 1.1)
- Names which PRH catalogs to pull next run, from open-reservation counts, so the operator never
  has to work it out
- Hashes each PRH master file and warns when a catalog's master data stops changing — *"2026-06
  master unchanged for 3 weeks; that catalog is freezing"* — turning § 1.2's boundary from
  something the operator must track into something the script says
- Writes **only** `on_sale_date` / `foc_date` on rows that already exist. Never inserts, archives,
  purges, or auto-reserves.
- Honours `--no-write`, like every other write in this codebase

### 4.3 Scope of what gets re-checked

Codes with **open (unfulfilled, not withdrawn) reservations** whose on-sale date has passed or
falls within 30 days. Measured 2026-09-04: 223 Lunar / 184 PRH. Nothing falls through permanently —
every title passes through the 30-day window before its on-sale date.

---

## 5. S3 — bounded deferral (the guard)

**CLIENT HALF SHIPPED to staging 2026-09-04** (`b5ad0e4`, merged `--ff-only`, pushed, new bytes
confirmed served on the plain URL). **SQL HALF IS PENDING — Rick must apply
`docs/sql/auto_fulfill_past_on_sale.sql` to staging.** The file's own `-- STATUS:` line says so, and
production still runs the pre-F155 body.

**Sequencing is client-first here, deliberately, and it is the reverse of F149's.** S3(b) calls
nothing new, so it is safe standing alone — it only widens what the Never Arrived panel shows. S3(a)
without S3(b) would defer rows that no panel displays, which is precisely the silent stall F115
rejected. So the client change must land first, and the SQL file says as much in its own header.

### 5.1 This reverses a recorded decision. Deliberately, and here is the argument.

`docs/f115-arrival-truth-persistence.md:209` records Option A — giving `auto_fulfill_past_on_sale()`
an arrival check — as **rejected**. `import.js`'s own `findUnverifiedFulfillments()` docblock states
the reason in the code:

> **REPORTS, NEVER BLOCKS.** Absence of a shipment row is not proof of non-arrival … so gating
> fulfillment on this would trade a silent miss for a silent stall.

**That objection was correct and still is.** So S3 does not block. It **defers, bounded**, and
guarantees visibility during the deferral:

- Shipment evidence present → fulfil immediately. **Unchanged** (212 of 218 rows, § 1.4).
- No evidence → defer until `on_sale_date + GRACE_DAYS`, then fulfil exactly as today, with
  `arrival_outcome = 'unknown'`.

Nothing stalls forever. The deferral buys precisely the window S2 needs to correct a stale date, or
the next invoice needs to land. **`GRACE_DAYS = 14`** — two full shipment cycles on Rick's
Friday/Monday/Wednesday rhythm.

### 5.2 The half that makes the deferral safe

A deferred row is `fulfilled = false`, so `neverArrivedFromFulfilled()` (`admin.html:1724`) does
**not** pick it up — it requires `p.fulfilled`. It falls instead to `computeBackorderRisk()`, whose
very first test is:

```js
if (ledgerNetQty(c.distributor, code) > 0) return;   // ordered — cleared
```

**Ordered ⇒ invisible.** That is exactly why DNX #1 surfaced on no panel, and why Rick found the
Mark Ordered button correctly `disabled` (ledger 2 = reserved 2, nothing left to order) with no
other control to reach for.

So S3(b): in `computeBackorderRisk()`, move the past-on-sale test **above** the ledger exit, so a
released title with no arrival record reaches Never Arrived whether or not it was ordered. The
existing F134/F143 resolve controls then apply unchanged.

**Without S3(b), S3(a) recreates the exact silent stall F115 rejected.** They ship together.

**APPROVED — Rick, 2026-09-04**, on being shown the reversal explicitly rather than having it
assumed. F115 Option A's rejection stands as written for *blocking*; this is a bounded deferral with
a guaranteed visibility surface, which is a different mechanism, not a reversal of the reasoning.
Record this approval in `docs/f115-arrival-truth-persistence.md` when S3 lands, so a future reader
of that doc's "Option A was rejected" line finds the follow-up rather than re-deciding it.

### 5.3 Files

| File | Change |
|---|---|
| `docs/sql/auto_fulfill_past_on_sale.sql` | grace window; `s.on_sale_date < CURRENT_DATE` becomes evidence-aware |
| `admin.html` | `computeBackorderRisk()` test order (§ 5.2) |

---

## 6. Verification gates

| Gate | What | Passes when |
|---|---|---|
| **V1** | S1 doc accuracy | Every claim in the rewritten Step 3 traces to a § 1 measurement |
| **V2** | ✅ **GREEN 2026-09-04** — PRH 1,308 rows and Lunar 17,490 both parsed, header detection correct on both |
| **V3** | ⚠️ **SUPERSEDED, and honestly so.** It cannot be re-run as written: the 13 Lunar in-store drifts it names were already corrected by `fix-stale-dates-f155.js` before S2 existed, so the script now correctly finds **zero** Lunar in-store drift — which is itself an independent confirmation that the remediation landed. What it *did* find on the same files: **4 stranded PRH titles with open reservations** (Godzilla Vs. America ×2, The Horror of Godzilla ×2, moved 7 and 3 weeks) and **11 Lunar FOC-only** changes. Replace this gate with a staging fixture rather than pretending the original number is still reproducible |
| **V4** | ✅ **GREEN** — `check-dates.js:61` requires `classifyReservedDateDrift` from `import.js`; no second date-diff implementation exists |
| **V5** | ✅ **GREEN, both halves** — the `--no-write` run reported 15 pending writes and applied none; the real run applied 15/15, confirmed by the script's own fresh re-read **and** independently afterwards (4 Godzilla rows at 10-28/11-11, three FOC spot-checks correct). Only `on_sale_date`/`foc_date` were touched; no inserts |
| **V6** | ⚠️ **IMPLEMENTED, NOT DEMONSTRATED through this script.** The `dirOf()` helper flags EARLIER vs later on stranded/corrected rows, and `fix-stale-dates-f155.js` did surface `0826DE0733` as `[EARLIER]`. But because Lunar in-store drift is now zero, `check-dates.js` has not yet printed an EARLIER in-store move on live data. Needs a staging fixture |
| **V7** | ✅ **VERIFIED LIVE 3/3 on staging, 2026-09-05**, after Rick applied the SQL — not merely predicted. Three discriminating fixtures, then a real `auto_fulfill_past_on_sale()` call: **A** (on-sale −2d, no evidence) stayed `fulfilled=false` — **the old body would have fulfilled it**; **B** (−20d, no evidence) fulfilled, grace elapsed; **C** (−2d, with evidence) fulfilled, path unchanged. **The RPC returned `2`, not `3`** — that number is the whole proof. Pre-flight confirmed 0 real staging rows were in scope, so it acted on the fixtures alone. Teardown verified: 0 fixture rows, 0 orphaned auth users. Also measured read-only pre-apply per the F122 precedent: production OLD **131** / NEW **124** / **7 deferred**; staging 0/0/0 |
| **V8** | ✅ **MEASURED** — 124 of 131 (**95%**) are unaffected; the shipment-evidence path carries them, consistent with F115's own 212-of-218 September production numbers |
| **V9** | ✅ **GREEN 3/3** — new local spec `23-f155-arrival-guard.spec.ts` (uncommitted, same convention as 21/22), run against deployed staging bytes. Positive: an ordered, released, evidence-free row renders with `data-state="neverArrived"` and its own resolve controls. **Two discriminating controls**: an ordered but *unreleased* title stays cleared (the ordered exit is still right pre-release), and an ordered+released title *with* shipment evidence stays cleared (settled outcomes still win). ✅ **Observed RED against the pre-fix code, 2026-09-05** — see below the table |
| **V10** | ✅ **GREEN** — `npm test` **279/279**; full Playwright **143 passed, 0 failed, 21.3 min, exit 0**, run directly (not via `run-smoke.ps1`, per the 2026-08-30 note) against deployed staging bytes post-push. Zero regressions from S3(b) |
| **V11** | Live | One real `check-dates.js` run on staging, changes verified by an independent fresh DB read — not the script's own output |

**⚠️ V9's honest limit.** Its three assertions pass, and a first draft was **found weak and
strengthened before being trusted**: it used `panel.locator('.arrival-resolve-actions').first()`,
which staging's own real Never Arrived rows would have satisfied whether or not the seeded row had
controls — an assertion that cannot fail is decoration (F105). It now scopes to
`.backorder-risk-row` by seeded title, asserts `toHaveCount(1)` and `data-state="neverArrived"`, and
both control tests carry a non-vacuity guard (the panel must contain the positive fixture before
anything is asserted absent from it).

**V7, by contrast, now HAS a red-capable assertion.** Fixture A is the case where the two SQL
bodies disagree: under the pre-F155 body it fulfils, under this one it defers. It came back
deferred, and the RPC's own return value (`2`, where the old body returns `3`) is independent
corroboration. That is an assertion that can fail, and did not.

**V9 WAS OBSERVED RED, 2026-09-05 — and staging never carried the reverted code.**

`staging.pulllist.pages.dev` is a Cloudflare Pages **branch alias**, so any pushed branch gets its
own preview at `<branch>.pulllist.pages.dev`. A throwaway branch `f155red` carrying only the
pre-F155 `computeBackorderRisk()` ordering was pushed, Playwright's `baseURL` temporarily repointed
at `f155red.pulllist.pages.dev`, spec 23 run against it, then the config restored and the branch
deleted from both remote and local. **`staging`'s tip never moved** (`bb1eb05` before and after) and
its served bytes were re-confirmed carrying the fix afterwards. This is a reusable technique for any
future negative control: it costs one branch push and needs no window where staging is wrong.

**The failure was the right one, checked from the artifact rather than inferred from "3 failed":**

```
V9 — Error: expect(locator).toHaveCount(expected) failed
     locator('#backorder-risk-panel').locator('.backorder-risk-row')
       .filter({ hasText: 'PW F155 Ordered Released NoEvidence …' })
     Expected: 1
     Received: 0
```

The seeded ordered / released / evidence-free row is **absent from the panel entirely** under the
old ordering — DNX #1's exact symptom, reproduced deterministically rather than argued.

**All three tests went red, and that is correct, not collateral.** Controls A and B each open with
the non-vacuity guard `expect(panel).toContainText(positiveTitle)`; under the pre-fix code the panel
does not contain it, so the guard fires first. The guards are doing precisely what they were added
for. Re-run against staging afterwards: **3/3 green**.

**Fixture hygiene verified rather than assumed** (F130's own failure mode): after the run, 0 F155
catalog rows, 0 F155 ledger rows and **0 orphaned auth users** remained. One `TEST_PW_` row survives
on staging from 2026-08-12 — a `PW-ISO-B` tenant-isolation fixture on a different tenant, F130's
already-documented `pw-iso` bucket, pre-existing and deliberately not touched here.

---

## 7. Open questions

| # | Question | Status |
|---|---|---|
| Q1 | `GRACE_DAYS = 14` — right number? | Proposed. Two shipment cycles. Rick's call |
| Q2 | Sticky override so a re-import can't revert a hand-fix | **Deferred**, § 2 OUT. Revisit if it bites |
| Q3 | Tell the customer when a date moves | **Deferred**, § 2 OUT. Rick has said it has value |
| Q4 | The 9 Lunar codes absent from All-Products | Accepted — guard covers them |
| Q5 | Does the freeze boundary move? | S2's hash warning measures it over time rather than guessing |

---

## 8. Completion criteria

- [x] S1 committed; every Step 3 claim traces to a § 1 measurement — 2026-09-04
- [x] S2 built — scripts repo `f2d31ec`, 2026-09-04. V2/V4/V5 green; **V3 superseded and V6 not yet
      demonstrated** (see § 6) — both need a staging fixture, neither is reproducible on production
      now that the remediation has landed
- [x] S3(b) client shipped to staging (`b5ad0e4`); V7/V8 measured read-only pre-apply
- [x] S3(a) SQL applied to staging by Rick, 2026-09-05 — **functionally verified live 3/3**, not taken on report
- [x] V9 green 3/3 (`23-f155-arrival-guard.spec.ts`), assertions strengthened after a weak first
      draft, teardown verified clean
- [x] V9 observed RED against pre-fix code, 2026-09-05, via a CF Pages preview branch — staging never carried the revert
- [x] V10 full suite green — 279 unit + 143 Playwright, 0 failed, 21.3 min, exit 0
- [ ] V11 one real staging run, independently verified
- [x] The 3 exposed titles (§ 9) corrected and confirmed — **15/15 applied to production
      2026-09-04** by Rick via `fix-stale-dates-f155.js`, verified by the script's own fresh re-read
      **and** independently afterwards (DNX #1 pair both `2026-09-16`; `0826DE0733` `2026-09-30`).
      `0726DC0300` deliberately **not** corrected — no authoritative source
- [ ] `docs/technical-reference.md` § 13 F155 status updated
- [ ] `CLAUDE.md` findings row updated
- [ ] Production promotion **not** attempted without an explicit request

---

## 9. Exposed today (production, 2026-09-04)

Unfulfilled, on-sale passed, no shipment evidence, actually ordered:

```
PRH   75960621519500111  on-sale 2026-09-02  ordered 2  reserved 2  DNX #1 [HIDDEN/DOUBLE COVER]
PRH   75960621519500122  on-sale 2026-09-02  ordered 1  reserved 1  DNX #1 JIM LEE HIDDEN GEM VARIANT
Lunar 0726DC0300         on-sale 2026-09-02  ordered 1  reserved 1  DC CONNECT #76 BUNDLES
```

Plus the **13 Lunar titles** in § 1.1 whose dates are already known-stale.

**These do not need this plan.** They are hand-fixable now, and should be — the two DNX #1 rows are
still `fulfilled = false`, so the false fulfilment has not happened yet. The next import fires it.

---

## 10. Remediation script (delivered 2026-09-04, pre-plan)

`scripts/fix-stale-dates-f155.js` — a one-off, matching `clear-f147-withdrawn.js` /
`f115-s6-backfill-unknown.js` conventions: production-only env guard, live re-derivation (never a
stored snapshot), before-state JSON log written *before* any write, sanity band, single y/n, and an
**independent fresh re-read** as the success check rather than its own status codes.

**Why it exists before the plan does:** `auto_fulfill_past_on_sale()` runs **weekly** — measured
2026-08-07 / 08-14 / 08-20 / 08-28 — and the last run was 2026-08-28. The next one is overdue, and
it fires the false fulfilment on § 9's titles. This could not wait for S2.

**Dry run, 2026-09-04 — 15 corrections across 1,068 catalog rows holding open reservations:**

- **13 Lunar**, derived live from the All-Products export. Includes `0826DE0733` FIRE AND ICE #5
  moving 2026-10-28 → **2026-09-30**, the *earlier* direction (§ 1.1).
- **2 PRH**, from the declared `MANUAL_PRH` table — the DNX #1 pair, 2026-09-02 → 2026-09-16,
  provenance recorded in the script (PRH site + invoice, Rick 2026-09-04). There is no downloadable
  source; the table must never be extended from a guess.
- **9 Lunar codes reported and deliberately skipped** — absent from the export because it lists
  *available* products. Mostly 1:25–1:500 incentive variants, plus `0726DC0300`, the only one whose
  on-sale date has passed. No authoritative date, so no write.

The script is idempotent and re-runnable. **It must be re-run after any older-month import**, which
restores whatever that distributor file says — the stale date, for a frozen PRH month.

---

## 11. What S2's first run found (2026-09-04, `--no-write`, production reads)

Run against the Lunar All-Products export plus PRH 2026-07 master data:

- **4 STRANDED PRH titles with open reservations**, none previously known — Godzilla Vs. America:
  New York City (Cover A + Variant B) moved **2026-09-23 → 2026-11-11**, and The Horror of Godzilla
  #2 (Cover A + Variant B) moved **2026-10-07 → 2026-10-28**. 7 reservations, 8 copies between them.
  These are live 2026-07 catalog rows; the remediation script never touched PRH beyond the declared
  DNX #1 pair, so S2 found these on its own.
- **11 Lunar FOC-only changes** — in-store already corrected, FOC still stale. Includes
  `FIRE AND ICE #5` FOC moving 2026-10-05 → **2026-09-07**, a month earlier.
- **Zero Lunar in-store drift** — independent confirmation that `fix-stale-dates-f155.js` landed.
- **1 genuinely at-risk code**, `0726DC0300`, matching § 9's known residual exactly.

**A real reporting defect was found and fixed during this run, before trusting the output.** The
absent-codes list originally flagged 3 codes as at-risk; two of them — DAREDEVIL #6 and VENOM #261 —
had in fact **shipped** (10 and 7 copies), and were flagged only because their catalog month had not
been supplied. The report now splits *"catalog not pulled"* (no signal) from *"catalog pulled and
the code is gone"* (real), and checks shipment evidence before raising anything. 3 alarms → 1 true
one. Left unfixed, this would have cried wolf every week and trained the operator to ignore it.

**15 corrections are pending and NOT applied** — 4 PRH in-store, 11 Lunar FOC. Production writes are
Rick's to run.

---

## 12. S2's first real run — applied 2026-09-04, and it paid for itself immediately

Rick applied the 15 corrections (4 PRH in-store, 11 Lunar FOC). Verified by the script's own fresh
re-read **and** independently afterwards. **30 production date corrections total today**, across
both scripts.

**The finding that justifies the whole exercise, surfaced by correcting a FOC date nobody was
watching:**

```
0826DE0733  FIRE AND ICE #5 CVR A JOSEPH MICHAEL LINSNER
            FOC  2026-10-05 → 2026-09-07   (pulled FOUR WEEKS earlier)
            NOT ORDERED — the window closes in 3 days
```

**✅ ORDERED AND CLOSED OUT by Rick, 2026-09-05** — verified by an independent ledger read, not
taken on report: `order_submissions` now carries qty **2**, `order_type = 'adhoc'`, `submitted_on`
2026-09-05, filed against `foc_date` **2026-09-07** — i.e. against the *corrected* date. Rick:
*"It was a real miss that we caught."*

**This is the first end-to-end proof of the whole F155 chain**, and it is worth more than any of the
gates: a revision nobody could see (S2's detection) → a corrected date (S2's write) → a surface that
made the consequence legible → a real order placed inside a window that had two days left. Every
prior piece of evidence in this doc is a measurement; this is an outcome.

Before this correction the system believed there was a month of ordering runway. There were three
days, and the title has no `order_submissions` row. Nothing in the app would have said so: the
Order Follow-Up panels classify against `foc_date`, and `foc_date` was wrong. **This is the
*earlier*-direction case (§ 1.1) doing real damage in the ordering lane rather than the arrival
lane** — a class this plan identified but had not yet seen bite.

Checked across all 11 FOC corrections: everything else is either already ordered or has 59 days of
runway. FIRE AND ICE #5 was the only one at risk, and only because its FOC moved backwards — and it
is now ordered. **No FOC-driven exposure remains from this batch.**

**Carry into S2's next iteration:** the report should rank FOC changes by *how much ordering runway
is left after the correction*, and shout when a pulled-forward FOC lands inside the current ordering
window on an unordered title. Today that had to be derived by hand after the run.

---

## 13. Follow-on — the "no surface" half now has controls (2026-09-05, staging)

§ 0 records that no admin panel caught DNX #1 because `computeBackorderRisk()`
(`admin.html:1749`) clears any code with `ledgerNetQty > 0` before every other test, while Mark
Ordered was correctly `disabled`. **S3(b) fixes the test order. It does not give the admin a
control, and its deferral is 14 days past on-sale** — so the earliest S3 can surface a title is
about two weeks after the customer was told "Order placed."

Rick hit the identical collision from a different direction on 2026-09-05: the **This Week
reconciliation panel**, which lists titles reserved for the week and absent from the imported
invoice. That is the *earliest* honest signal — it exists on the day the shipment is imported — and
the panel's own footnote already told the operator to go "check the invoice for shorts, or a
distributor rejection at order time" with nothing on the page to check against and no way to act.

Measured on production, `0726IM0319` (SPAWN 77 #1 CVR J, 1:500):

| | |
|---|---|
| ledger | one `monthly` row, qty 1, submitted 2026-07-26 → **net 1** |
| reserved | 1 → `orderMatched` → **"✓ Ordered (1)", `disabled`** |
| `fulfilled` | `false` → `neverArrivedFromFulfilled()` cannot see it |
| `computeBackorderRisk()` | cleared by the `ledgerNetQty > 0` exit |

**What shipped.** F143's write was split into `recordSupplierRejection(btn)` — one writer — and
given two more entry points: the admin distributor-table **Status column** (offered when
`ledgerNetQty > 0` **and** `!hasShipmentEvidence(c)`), and the **arrivals recon exceptions list**,
which also now states each row's order state. The shipment-evidence guard is the load-bearing half:
recording a rejection for a title that actually arrived would flip F120's customer-facing rejected
badge on a book the customer can collect.

**Verified** 18/18 against deployed staging (`playwright/f156-reject-surfaces-verify.mjs`,
local-only; it must SEED, because every recon exception row on staging has ledger net 0), plus the
full suite at 146 passed / 0 failed. **No finding ID consumed** — this advances F155.

---

## 13. The production run of 2026-09-04 — the case S3 exists for, observed live

Measured 2026-09-05, the day after. Production's weekly import ran on **2026-09-04** and
auto-fulfilled **131** reservations — exactly the number § 6 V7 had predicted for the pre-F155 body.
Seven of those had **no shipment evidence** and are precisely the rows S3(a) would have deferred:

```
75960621630700116  BLACK PANTHER/NAMOR: DOOMED #1 …          arrival_outcome=unknown
75960621146301517  CAPTAIN AMERICA #15 AKA VARIANT [ARM]     arrival_outcome=unknown
75960621146301516  CAPTAIN AMERICA #15 ALEX ROSS … (×2)      arrival_outcome=unknown
75960621122701616  FANTASTIC FOUR #16 ALEX ROSS … (×2)       arrival_outcome=unknown
0726DC0300         DC CONNECT #76 BUNDLES                    arrival_outcome=not_arrived
```

**F115's safety net held, and that is the honest framing.** Six carry `arrival_outcome = 'unknown'`,
so `neverArrivedFromFulfilled()` surfaces them in Never Arrived with resolve controls; the seventh
had already been resolved `not_arrived` by hand. Nothing was lost and nobody has to go looking.
What did happen is that six customers were told "Order placed" for books with no arrival evidence,
which is the state F115 exists to make *recoverable* and S3 exists to make *avoidable*.

**This is why the October-gate sequencing recommendation was revised.** The earlier advice — hold S3
until after 2026-09-25 so F146/F147 get a clean first exercise — was written before it was visible
that this failure fires **weekly**, not monthly. Three more weekly runs land before the gate. And
S3 is no longer the unproven change that reasoning assumed: it has a live 3/3 functional test whose
fixture A fails against the old body, plus a genuine observed red on the panel half (§ 6). Promoting
it now gives it three weeks of production soak *before* October rather than making October its first
outing.
