# F136 — catalog_month integrity: stale-date detection + duplicate-row cleanup

**STATUS:** IN PROGRESS | staging=2026-08-22 (S1+S2, code+DB) | prod=— | findings=F136,F137,F122,F110,F115
**Status:** **S1 COMPLETE 2026-08-22** — Part A (all three entry guards) + Part C(1) (widened
`unreserved` drift list) + F137 (own commit) + `f136-audit.js` all shipped to the scripts repo
`main` (`f1f90be`), staging code only, no DB migration, no production touch. Gates V0-V4 all
green — see § 11. **S2 COMPLETE 2026-08-22** — the `dedupe_catalog_months()` RPC
(`docs/sql/f136-dedupe-catalog-months.sql`) applied to staging by Rick and wired into
`refreshCatalog()`'s new-month branch (scripts repo `main` `7a8d6a1`). Gates V5-V6 green — see
§ 11. **S3** (prod repoints + prod dedupe) stays Rick-gated, next. Originally written 2026-08-21 in a planning session that
also **identified the root cause F136 was filed without** (§ 2) and **corrected two statements in
the filed finding** (§ 3). All measurements in §§ 2-4 are the *original* read-only GETs from
2026-08-21 against live staging *and* live production; § 11's are S1's own, from 2026-08-22.
**Target:** `catalogs/scripts` (private scripts repo) — `import.js` / `import-staging.js` — plus
one new `docs/sql/` migration. **No `comic-preorder` app change.**
**Last verified against live:** 2026-08-21 — every count in §§ 2–4 measured this session; see
§ 9 for the diagnostic scripts that produce them.

> **Read § 8 before scheduling.** This plan touches `import.js`, and so do F115 S1/S5/S6, which
> are already held for the ~Sept 7–10 import window. They collide. Sequencing is a decision, not
> a discovery to make on the day.

---

## 1. What F136 actually is

Two separable defects, filed together because one investigation found both.

**Part 1 — a distributor's post-solicitation date revision is invisible on an unreserved row.**
Lunar re-issues a month's Product Data file with revised FOC/in-store dates for items still open.
Nothing triggers a re-fetch of an older still-open month, and the one existing detector,
`reportReservedInStoreDateChanges()` (built for F122), only diffs titles that are **currently
reserved**. A stale date on an unreserved row has no detection path at all — and it becomes
customer-facing the moment anyone reserves that row.

**Part 2 — duplicate `(item_code, distributor)` rows across `catalog_month`.** `preorders.catalog_id`
pins a reservation to one specific row. When two rows exist for the same physical product, a
reservation can sit on the one the monthly cycle will never touch again — so a future date
correction reaches the other row and the customer never sees it. Same failure as Part 1, arrived
at structurally.

---

## 2. Root cause — identified 2026-08-21 (this was open when F136 was filed)

The filed finding said: *"not fully identified … consistent with one systemic event … but this has
not been confirmed against import history."* It is now confirmed, and the mechanism is named.

### 2a. Neither distributor's monthly file overlaps months — so normal operation cannot create a duplicate

Measured on the CSVs currently on disk:

| Overlap | Shared codes |
|---|---|
| Lunar `0626` ∩ `0726` | **0** |
| Lunar `0726` ∩ `0826` | **0** |
| Lunar `0626` ∩ `0826` | **0** |
| PRH `2026_06` ∩ `2026_07` | **0** |
| PRH `2026_07` ∩ `2026_08` | **0** |
| PRH `2026_06` ∩ `2026_08` | **0** |

And every Lunar row carries a self-describing MMYY prefix, one prefix per file, 100% coverage:
`Lunar_Product_Data_0626.csv` → 1,395 rows, all `0626`. Same for `0726` (1,516) and `0826` (1,514).

**Consequence:** one import per month per file cannot produce a duplicate. A duplicate can only
exist if **the same file was imported under two different `catalog_month` values.**

### 2b. Production proves exactly that happened

`catalog` rows on production, Lunar only, broken down by `catalog_month` × `item_code` MMYY prefix:

```
2026-03:  0326=41
2026-04:  0426=181
2026-05:  0626=1353   0526=423     <-- the JUNE file, written under month 2026-05
2026-06:  0626=1561   0526=340
2026-07:  0726=1591
2026-08:  0826=1515
```

**1,353 rows carrying June solicitation codes are stored under `catalog_month=2026-05`.** Their
`created_at` dates are `2026-05-31` (2,302 rows) and `2026-06-01` (1,018). The same June file was
then imported again, correctly, as `2026-06` on `2026-06-02` (1,311) and `2026-06-05` (1,354).

That one straddling-the-month-boundary session is the 2,621-pair `{2026-05, 2026-06}` cluster.

### 2c. The three things that let it happen and kept it

1. **`catalog_month` is filename-derived, not data-derived.** `inferCatalogMonth()`
   (`import.js:212`) parses the filename, and **falls back to the current calendar month** when it
   finds nothing parseable (`import.js:228-229`). Run on 2026-05-31 against a generically-named June
   download, it silently returns `2026-05`. The operator presses Enter to confirm.
2. **Neither existing guard fires on this case.** Guard (a) compares the Lunar filename's inferred
   month to the PRH filename's — if both fall back, both agree, no mismatch. Guard (b) only warns
   when the month is **more than one** month from the calendar month; here the delta is **0**.
3. **`purge_stale_catalog` cannot clean it up.** Its predicate is
   `catalog_month != current_month AND on_sale_date < cutoff_date AND not reserved` — so every
   duplicate whose on-sale date is still in the future survives every subsequent import, forever.

Nothing here is per-item drift. It is one operator-invisible month assignment, made permanent by a
purge that was never designed to deduplicate.

---

## 3. Corrections to the filed F136 (§ 13 updated in the same commit as this doc)

**(a) "Root cause not identified"** → identified, § 2.

**(b) "PRH's item codes carry no equivalent signal, so (b) needs a different resolution method
there before any cleanup can run against PRH rows."** True about the codes — but the cleanup does
**not** need a per-distributor canonical rule, because a simpler rule is universally safe:

> **The highest `catalog_month` row in a duplicate group is the one the live cycle maintains.
> Every lower-month row in that group that holds no `preorders` reference at all is safe to delete
> outright** — it is unreferenced data that any legitimate re-import would recreate.

That rule needs no knowledge of which file was mis-monthed, works identically for both
distributors, and cannot orphan a reservation because it refuses to touch a referenced row.
Measured, it clears almost everything:

| | Duplicate pairs | Rows deletable under the rule | Rows blocked (hold a preorder) |
|---|---|---|---|
| **Production** | 2,666 | **2,667** | **29** |
| **Staging** | 977 | **997** | **1** |

**(c) "staging not yet checked at this depth"** → checked. **Staging has 977 duplicate pairs, all
PRH**, dominant set `{2026-04, 2026-06}` (919). **Staging has zero Lunar duplicates**, so it is a
valid rehearsal surface for the bulk dedup and the PRH half, but it **cannot** rehearse the Lunar
half — that must be validated by construction and by dry run, not by a staging repeat.

**(d) The genuinely hard subset is two rows, exactly as filed.** Of production's 1,049 unfulfilled
reservations, 165 sit on a duplicate-group row, and of those **2** sit on a row that is *not* the
maintained one:

```
PRH   82771403150804031  "TMNT: Saturday Morning Adventures #40 Variant C (Hazouri)"
        reserved row month=2026-05, maintained month=2026-06   both 2026-08-26
Lunar 0626DC0190          "ACTION COMICS #1 FACSIMILE EDITION CVR A JOE SHUSTER (2026)"
        reserved row month=2026-05, maintained month=2026-06   both 2026-08-26
```

Neither is wrong **today** — both rows in each pair hold identical dates. Both are structurally
unable to receive a future correction. Staging's equivalent count is **0**.

*(A related number worth carrying into the work but not acting on: 48 live production reservations
sit on duplicate groups whose rows **already disagree** on `on_sale_date`. All 48 sit on the
maintained row, so they are being corrected normally. They are the reason the bulk dedup must
delete the **stale** side and never the maintained one.)*

---

## 4. Fix shape

Four parts, in dependency order. **A and C are prevention and detection and go first**; B and D
touch data.

### Part A — make a wrong month impossible to enter silently *(code, both scripts)*

1. **`inferCatalogMonth()` stops guessing.** Return `null` instead of the current calendar month
   when the filename carries no parseable month. The caller then **requires** an explicit
   `YYYY-MM` at the prompt rather than accepting Enter. A silent correct-looking default is what
   caused this; a prompt that cannot be dismissed is the cheapest possible fix.
2. **Lunar MMYY cross-check — the real guard.** Before the upsert, compare every Lunar record's
   `item_code` MMYY prefix against `confirmedMonth`. If they disagree, print the counts by prefix
   and **abort** unless the operator types `yes`. On the 2026-05-31 session this would have
   printed `0626=1353 vs confirmed 2026-05` and stopped it dead.
3. **Cross-month collision pre-check — covers PRH, where no code signal exists.** Before the
   upsert, fetch existing rows for the incoming `(item_code, distributor)` set that sit under a
   *different* `catalog_month`. If the count exceeds a threshold (suggest: 5% of the incoming
   record count), report and require confirmation. This is distributor-agnostic and catches the
   failure regardless of cause.

4. **Scope the Step 3 month-detection query by tenant (F137).** Add `tenant_id=eq.${TENANT_ID}`
   to the `monthRes` fetch in both scripts — `import.js` ~1789, `import-staging.js` ~1781. One
   line each, its own commit, F137 in the message. Full reasoning in § 7 and § 13 F137.

> **Rejected: deriving `catalog_month` per-record from the Lunar prefix.** It is the "correct"
> model, and it is out of proportion to the defect — `catalog_month` is load-bearing for
> `isNewMonth`, `purge_stale_catalog`'s `current_month`, `delete_dropped_catalog_items`,
> auto-reserve, the order-export cycle, and My List's month scoping. A guard achieves the same
> prevention with a blast radius of one prompt. If it is ever revisited, it is its own finding.

### Part B — make the bloat self-healing *(new `docs/sql/f136-dedupe-catalog-months.sql`)*

A new `dedupe_catalog_months(p_tenant_id uuid)` RPC implementing the § 3(b) rule: delete rows that
share `(tenant_id, item_code, distributor)` with a row under a strictly-greater `catalog_month`
**and** are referenced by no `preorders` row. Called from the new-month branch of `refreshCatalog()`
immediately after `purge_stale_catalog`, reporting its delete count.

This is deliberately a **separate** function rather than a widened `purge_stale_catalog`: the purge
is date-driven and this is not, and F110's history is a warning about overloading one function's
month scope.

### Part C — detect a stale date on an unreserved row *(code, both scripts + one runbook edit)*

1. **Widen the drift report from reservation-scoped to catalog-scoped.** `classifyReservedDateDrift()`
   keeps its current two lists (they are correct and unit-tested); add a third, **`unreserved`** —
   incoming records whose `on_sale_date` differs from the existing row for the same
   `(item_code, distributor, catalog_month)` but which carry no reservation. Report it as a
   **count plus the first N titles**, not a full dump: on a re-pull this is the "what the
   distributor changed since solicitation" number, and it is the signal that has never existed.
2. **Add the revision sweep to the monthly runbook.** Detection without a trigger is inert — the
   file for an older still-open month is only re-read if somebody re-supplies it. Add an explicit
   monthly step to `docs/monthly-catalog-refresh.md`: **re-pull the previous 1–2 still-open months
   from the Lunar portal and re-import them oldest-to-newest as backfills before the new month's
   import.** This is exactly the sequence Rick ran on 2026-08-21 to find and fix the 49 stale
   production titles; the work here is turning a one-off rescue into a documented recurring step.

### Part D — clean up what exists *(runbook, staging rehearsal then prod, Rick-gated)*

1. Repoint the **2** production reservations in § 3(d) from the `2026-05` row to the `2026-06` row.
   Two `UPDATE preorders SET catalog_id = …` statements with explicit before/after SELECTs.
2. Run `dedupe_catalog_months()` — staging first (997 rows), then production (2,667 rows).
3. Re-run the § 9 scan on both and confirm the duplicate-pair count is 0 and the live-stranded
   count is 0.

---

## 5. Session split

**One sub-deploy per session (CLAUDE.md § Anti-Drift).** Three sessions.

| Session | Scope | Gate to the next |
|---|---|---|
| **S1** | Part A (incl. the F137 one-liner) + Part C(1) — guards and the widened report, both scripts, `npm test` extended | V0–V4 green |
| **S2** | Part B — the dedupe RPC, applied and run on **staging only** | V5–V6 green |
| **S3** | Part C(2) + Part D — runbook edit, the 2 prod repoints, prod dedupe | Rick-gated, prod |

**The new CLI session being handed off is S1.** It is code-only, staging-only, touches no
production data, and needs no DB migration — which is what makes it safe to run while the F132 prod
migration gate (§ 8) is still open.

---

## 6. Verification gates

Every gate below states **what its output looks like when the thing has failed** — CLAUDE.md
§ "A verification step that cannot fail is not a verification step."

**S1**

- **V0 — F137: month detection is tenant-scoped.** Constructed, because live data cannot fail it.
  On staging, seed **one** catalog row for a secondary tenant (`pw-56132e92`) at a
  `catalog_month` one month ahead of `raysandjudys` — e.g. `2026-09` — then run the Step 3
  detection path. It must report the **importing tenant's** month (2026-08) and classify a
  `2026-09` import as a new month. *Failure looks like:* `currentDbMonth` comes back `2026-09`
  and the import announces "♻️ Same month — upsert refresh only". **Delete the seed row and
  confirm with a live SELECT returning zero rows** (CLAUDE.md § Definition of Done — fixture
  teardown is verified, not assumed). Run this check **against the unfixed code first** and observe
  it fail; a V0 that was only ever run after the fix proves nothing.

- **V1 — `inferCatalogMonth()` no longer guesses.** Unit test: a path with no parseable month
  returns `null`. *Failure looks like:* it returns the current calendar month string.
- **V2 — the Lunar MMYY guard fires on the real historical case.** Unit test over
  `classifyLunarMonthMismatch(records, '2026-05')` with fixture records carrying `0626` codes:
  returns a mismatch with `{ '0626': n }`. *Failure looks like:* empty result / no mismatch.
  Then a **live** dry check: run `import-staging.js` against
  `Lunar_Product_Data_0826.csv` and type `2026-07` at the prompt — it must refuse to proceed
  without a typed `yes`. *Failure looks like:* the import continues straight to the upsert.
- **V3 — the collision pre-check counts correctly against real data.** Run `import-staging.js`
  against the `0826`/`2026_08` pair confirming `2026-08` — the collision count must be **0** (files
  do not overlap, § 2a). Then confirm `2026-07` — it must report a **large** collision count
  (~1,500) and stop. *Failure looks like:* zero in both cases, i.e. the check is not reading
  existing rows.
- **V4 — the widened report shows unreserved changes.** Re-import the **already-imported**
  `2026-07` pair on staging, unchanged: `corrected`/`stranded`/`unreserved` must all be **0**.
  Then re-import the `2026-06` pair (a genuine older-month backfill of a file whose dates were
  revised): `unreserved` must be **> 0**. *Failure looks like:* `unreserved` is 0 on the backfill —
  which is precisely today's blind spot, so a 0 there means the change did nothing.

**S2**

- **V5 — the dedupe refuses referenced rows.** On staging, `dedupe_catalog_months()` returns
  **997** and the 1 reservation-holding duplicate row still exists afterwards.
  *Failure looks like:* a count of 998, or that row gone.
- **V6 — reservations are intact.** Staging unfulfilled-preorder count identical before and after,
  and the § 9 scan reports 0 duplicate pairs. *Failure looks like:* any drop in the count.

**S3**

- **V7 — the 2 prod repoints landed.** Post-`UPDATE` SELECT shows both reservations on the
  `2026-06` row. *Failure looks like:* either still on `2026-05`.
- **V8 — prod dedupe.** Returns **2,667**, prod unfulfilled-preorder count unchanged at **1,049**,
  § 9 scan reports 0 duplicate pairs and 0 live-stranded. *Failure looks like:* any preorder count
  change, at all.

---

## 7. Out of scope — and one thing to file first

**Not in this plan:** anything in `comic-preorder` (no app change); F115's arrival-truth work;
F132's prod migration; partial-fulfillment representability.

**⚠️ Discovered while writing this plan — now filed as F137, and Rick's call 2026-08-22 is that
its fix rides in S1 as its own commit.** Recorded here because the reasoning is F136's:
`import.js:1789` and `import-staging.js:1781`, the Step 3 month-detection query, are **not scoped
by tenant**:

```js
`${SUPABASE_URL}/rest/v1/catalog?select=catalog_month&order=catalog_month.desc&limit=1`
```

Every other catalog query in both files passes `tenant_id=eq.${TENANT_ID}`. The service-role key
bypasses RLS, so this reads the newest `catalog_month` **across all tenants**. If any secondary
tenant is ever a month ahead of the importing tenant, `isNewMonth` computes **false** for a
genuinely new month and **`archive_stale_reservations`, `purge_stale_catalog`, and
`delete_dropped_catalog_items` all silently skip.**

Measured 2026-08-21 — latent today, not currently biting, and the second tenants are small but real:

| Env | Tenants | Max `catalog_month` | Unfiltered read |
|---|---|---|---|
| Production | `rjbookstop` (12,087 rows), `comicstore` (2 rows) | 2026-08 / 2026-06 | 2026-08 ✅ |
| Staging | `raysandjudys` (9,951), `pw-56132e92` (1), `pw-fc2e3fc7` (0) | 2026-08 / 2026-08 | 2026-08 ✅ |

This is one line, in the same two functions S1 already edits, and it is in F136's own failure class
(the purge not running is *why* duplicates accumulate). **Filed as F137 on 2026-08-22
(`docs/technical-reference.md` § 13); Rick approved folding the one-line fix into S1 the same day,
as a separate commit carrying the F137 ID.** It is therefore IN scope for S1 — see § 4 Part A(4),
gate V0, and § 10.

**F137 needs a constructed verification, not a live one.** Today's data passes the check both
before and after the fix, on both environments, because the importing tenant happens to hold the
newest month everywhere. A gate that cannot fail is not a gate (CLAUDE.md). See V0.

---

## 8. Scheduling — this collides with F115, deliberately flag it

`import.js` currently has **two** claims on the ~Sept 7–10 catalog import window:

- **F115 S1/S5/S6** — the import pre-flight, live run, and prod backfill, explicitly held for it.
- **F136 Part C(2)** — the revision sweep, which is a *change to how that same import is run*.

They are compatible in substance and hostile in sequencing: both edit the same file, and F115's S5
is a **production** run. Suggested order, for Rick to confirm:

1. **S1 now** (code-only, staging, no DB) — well ahead of the window.
2. **S2 shortly after** (staging DB only).
3. **F115 S1/S5/S6 in the window, unchanged**, with the F136 revision sweep folded in as the
   pre-step to S5 rather than as separate work.
4. **S3's prod dedupe after** the import settles — not during it.

**Also open and prod-blocking, unrelated but same window:** F132's
`docs/sql/f132-order-requirement.sql` must run on production **before the next production import**
or `import.js` 400s on every catalog upsert. That gate is not F136's to close, but S3 cannot run
before it.

---

## 9. Diagnostics used, and how to re-run them

Three read-only Node scripts were written this session. They perform **GETs only** — no write path
exists in any of them — and each takes `--prod` to target production, defaulting to staging:

| Script | Answers |
|---|---|
| `f136-dupe-scan.js` | duplicate pairs, distributor split, month-set histogram, date agreement |
| `f136-forensics.js` | `catalog_month` × MMYY-prefix matrix, `created_at` clustering per month |
| `f136-live-scope.js` / `f136-final.js` | live reservations on duplicate rows, stranded count, bulk-dedup safe/blocked counts |

They currently live in this session's scratchpad. **S1's first task is to move them into
`catalogs/scripts/` as a single committed `f136-audit.js`** so V6/V8 are reproducible by anyone —
a verification gate that only one session can run is not a gate.

---

## 10. Completion criteria

- [x] S1 — **F137**: Step 3 month-detection query scoped by `tenant_id` in both scripts, own commit (`3a1bede`)
- [x] S1 — V0 green, observed failing against the unfixed code first, seed row torn down and verified
- [x] S1 — `inferCatalogMonth()` returns `null` on no match; prompt requires explicit month
- [x] S1 — Lunar MMYY mismatch guard aborts without a typed `yes`
- [x] S1 — cross-month collision pre-check reports and gates
- [x] S1 — `classifyReservedDateDrift()` returns a third `unreserved` list; report prints it
- [x] S1 — both scripts changed identically; `node --check` clean; `npm test` extended and green (269/269)
- [x] S1 — V1–V4 green, evidence pasted into § 11
- [x] S1 — `f136-audit.js` committed to the scripts repo (`f1f90be`)
- [x] S2 — `docs/sql/f136-dedupe-catalog-months.sql` written, applied to staging, V5–V6 green
- [x] S2 — RPC wired into the new-month branch, reports its count
- [ ] S3 — `docs/monthly-catalog-refresh.md` carries the revision-sweep step
- [ ] S3 — 2 prod reservations repointed, V7 green
- [ ] S3 — prod dedupe run, V8 green
- [ ] § 13 F136 status advanced; CLAUDE.md open-findings row updated or removed

---

## 11. Verification evidence

### S1 — 2026-08-22, staging (`puoaiyezsreowpwxzxhj`), scripts repo `main` `f1f90be`

**Note on live-run tooling.** `import.js`/`import-staging.js`'s sequential prompts use a fresh
`readline.createInterface` per question. Piping multi-line answers in one shot
(`printf 'a\nb\n' | node import-staging.js ...`) delivers ALL lines to the FIRST prompt's listener
in one stdin `data` event — only the first line is consumed, the rest are parsed and discarded
internally by that one interface's own buffer before any later `question()` call exists to receive
them. This is a stdlib `readline` behavior that only bites piped/scripted input (a human typing
at a real terminal never hits it, since each line arrives well after the previous prompt's listener
attached) — not a defect in the scripts. Confirmed with a byte-for-byte minimal repro before
concluding this, and again after switching to a single persistent interface (same result either
way — confirms it's not the create-per-question pattern specifically). Worked around with a
throwaway Node driver (not committed) that waits for each prompt's own text to appear in the
child's output before writing the next answer — timing-independent, no fixed delays.

**V0 — F137, constructed.** Seeded one `catalog` row for `pw-56132e92`
(`93b65c8d-b858-4b5b-beb9-6204752830c8`) at `catalog_month=2026-09` (staging's real max was
2026-08 for every tenant, confirmed before seeding). Ran the literal Step 3 query text from both
the unfixed (git HEAD, no tenant filter) and fixed (working tree, `tenant_id=eq.<raysandjudys>`)
versions directly against live staging:
  - Unfixed: `catalog?select=catalog_month&order=catalog_month.desc&limit=1` → `2026-09` (poisoned
    by the seed — `isNewMonth` would compute `false` for a real September import: the exact FAIL
    condition).
  - Fixed: `catalog?tenant_id=eq.72e29f67-...&select=catalog_month&order=catalog_month.desc&limit=1`
    → `2026-08` (correct; `isNewMonth` computes `true`).
  Seed row deleted; teardown confirmed via live SELECT on `item_code=eq.F136-V0-SEED-DELETE-ME`
  returning `[]`, and the global max confirmed back at `2026-08`. **GREEN.**

**V1 — unit.** `inferCatalogMonth('no-month-here.csv') === null` (and three more no-match
filenames); ISO- and MMYY-shaped filenames still parse correctly (regression guard). **GREEN**
(`test/catalog-month-guards.test.mjs`).

**V2 — unit + live.** Unit: `classifyLunarMonthMismatch(records, '2026-05')` over 1,353
`0626`-prefixed fixture records returns `{ '0626': 1353 }`; full-agreement and mixed-batch cases
also pass. **Live:** ran `import-staging.js` against `Lunar_Product_Data_0826.csv` paired with
`2026_07_PRH_metadata_full_active.csv` (chosen so guard (a)'s filename-mismatch check does NOT
fire, isolating the new guard), typed `2026-07` at the month prompt, then `no` at the Lunar
mismatch prompt:
```
⚠️  LUNAR ITEM CODE / CONFIRMED MONTH MISMATCH:
   Confirmed catalog month: 2026-07
   • item codes prefixed "0826": 1514 record(s)
Aborted on Lunar item-code / month mismatch.
```
Exit code 1, no upsert attempted. **GREEN.**

**V3 — live, both cases.** Pair: `Lunar_Product_Data_0826.csv` + `2026_08_PRH_metadata_full_active.csv`.
  - Confirming **2026-08** (the real matching month): collision check reported **4** incoming
    items already existing under a different `catalog_month` — not the plan's literal "0", but
    well under the 5% threshold (120 of 2,390), so the gate correctly did not fire. The 4 are
    consistent with pre-existing incidental overlap in staging's already-documented duplicate
    population (977 pairs) rather than a defect in the check itself. Full run (`--no-write`)
    completed cleanly end to end: upsert (mocked), shipment import declined, notification email
    declined.
  - Confirming **2026-07** (deliberately wrong): passed guard (a) and guard (c) with `yes`, then
    the collision pre-check reported:
    ```
    ⚠️  CROSS-MONTH COLLISION: 2393 of 2390 incoming record(s)
       already exist in the catalog under a DIFFERENT catalog_month than "2026-07"
       (threshold: 120, ~5%).
    ```
    (2393 > 2390 because a single incoming item can match more than one existing duplicate-month
    row — staging already carries known duplicate groups spanning 3 months. Exceeds the plan's
    rough "~1,500" estimate, but the assertion that matters — large count, gate fires — holds.)
    Answered `no` → `Aborted on cross-month collision.`, exit 1, no upsert attempted. **GREEN.**

**V4 — live, both cases, plus one constructed fixture.**
  - Re-imported the **already-imported 2026-07 pair** unchanged (`Lunar_Product_Data_0726.csv` +
    `2026_07_PRH_metadata_full_active.csv`, confirmed `2026-07`): report printed
    `📅 No in-store-date changes on reserved titles.` — the branch that only fires when
    `corrected`, `stranded`, AND `unreserved` are all empty. **corrected/stranded/unreserved = 0,
    0, 0 — matches expectation exactly.**
  - Re-imported the **2026-06 pair** (`Lunar_Product_Data_0626.csv` + `2026_06_PRH_metadata_full_active.csv`,
    a genuine older-month backfill): same "No in-store-date changes" result — **`unreserved` read
    0, not > 0.** Investigated rather than declared green: the 2026-08-21 manual backfill
    (referenced in this doc's own root-cause section) ran this exact file through a REAL (non-dry-run)
    import, which unconditionally upserts every incoming record's `on_sale_date` regardless of
    reservation status. So the natural blind spot this session's C1 work targets had *already*
    been closed by that prior real import — there was no live drift left on disk to detect,
    which is a fact about the current data, not a defect in the new code.
    **Constructed the case instead** (same pattern as V0, and for the same reason — "a check that
    can't fail proves nothing"): identified a genuinely unreserved 2026-06 catalog row
    (`A MISCHIEF OF MAGPIES #2 CVR A`, id `cce7bd86-...`, confirmed via a `preorders` lookup that
    it holds zero reservations), manually set its `on_sale_date` to a deliberately stale
    `2026-07-01` (real value: `2026-09-23`), then re-ran the same 2026-06 import:
    ```
    📌 1 unreserved title(s) changed in-store date on re-pull (F136):
       • A MISCHIEF OF MAGPIES #2 CVR A MATIAS BERGARA: 2026-07-01 → 2026-09-23
    ```
    Exactly the seeded row, exactly the seeded from/to dates. Reverted the `on_sale_date` back to
    `2026-09-23` and confirmed via live SELECT. **GREEN, via the constructed fixture** — the
    natural-data case is legitimately 0 today given what the 2026-08-21 backfill already did, not
    a failure of this session's change.

**Test suite.** 269/269 green (63 new: 44 in `catalog-month-guards.test.mjs` +
`reserved-date-drift.test.mjs`'s extension, 18 in `f136-audit.js`'s new suite, plus 1 export-parity
check). `node --check` clean on `import.js`, `import-staging.js`, `f136-audit.js`.

**Commits (scripts repo, `feature/f136-s1-catalog-month-guards` → `main` --ff-only, pushed):**
- `3a1bede` — `fix(F137): scope Step 3 catalog-month detection query by tenant_id`
- `e3c15e5` — `feat(F136): catalog-month entry guards (Part A) + unreserved drift detection (Part C1)`
- `f1f90be` — `feat(F136): consolidated read-only catalog_month integrity audit tool`

**Out-of-band discovery, reported not fixed:** `f136-audit.js`'s first live run found **1** live
stranded reservation on staging (0 recorded on 2026-08-21) — a real reservation on "Disney Tim
Burton's The Nightmare Before Christmas: All Hail the Pumpkin King #2" (`64557390089200211`, PRH)
landed on the stale `2026-04` duplicate row instead of the maintained `2026-06` row sometime in
the intervening day. This is a fresh, real instance of this finding's own Part 2 failure mode —
not a new finding, not fixed here (repointing is Part D/S3, Rick-gated). Logged in
`technical-reference.md` § 13 F136 "Where" and CLAUDE.md's F136 row.

### S2 — 2026-08-22, staging (`puoaiyezsreowpwxzxhj`)

**Pre-run baseline**, `f136-audit.js` re-run fresh at the start of this session (not trusted from
S1's snapshot): **977 duplicate pairs, all PRH**, dominant set `{2026-04,2026-06}` (919); **997
safe / 1 blocked** under the § 3(b) rule; 9,951 total catalog rows for the tenant; preorders
56 total / 22 unfulfilled / 34 fulfilled.

**B1 — `docs/sql/f136-dedupe-catalog-months.sql` written.** `dedupe_catalog_months(p_tenant_id
uuid)`, `LANGUAGE sql SECURITY DEFINER`, matching `purge_old_usage_events.sql`'s precedent
(closest sibling: tenant-scoped, service-role-only, bulk DELETE-and-count) rather than
`purge_stale_catalog`'s older `plpgsql` shape. Grants: `service_role` only, `anon`/`authenticated`
explicitly revoked (F124 — Supabase auto-grants both on function creation; `REVOKE … FROM PUBLIC`
alone does not remove them). File structured as four watched steps (create, dry-run preview,
invoke, post-verify) rather than one pasteable block, per CLAUDE.md's "a verification step that
cannot fail is not one" — the dry-run preview runs the identical predicate as the DELETE so it
cannot silently drift from what Step 3 actually does.

**B2 — applied to staging by Rick**, Supabase SQL Editor, 2026-08-22. Step 1 (CREATE FUNCTION +
grants) ran clean. Step 3 (the invocation) ran against the staging `raysandjudys` tenant.

**B3 — wired into `refreshCatalog()`'s new-month branch**, both scripts, immediately after the
`purge_stale_catalog` call inside the `isNewMonth` block, reporting its delete count the same way
purge's is reported. Deliberately a separate call, not folded into purge (plan § 4 Part B
rationale — purge is date-driven, this isn't). Commit `7a8d6a1` (scripts repo, `feature/f136-s2-
dedupe-catalog-months` → `main`, `--ff-only`), pushed.

**B4 — unit suite extension: none, correctly.** Checked first per the handoff's own conditional:
no existing test covers `purge_stale_catalog`'s call-site shape or its `isNewMonth` gating to
mirror — `refreshCatalog()` is not exported from either script and nothing in `test/` mocks
`writeFetch`. 269/269 green, unchanged from S1. `node --check` clean on both scripts.

**V5 — the dedupe refuses referenced rows. GREEN.** Confirmed two independent ways:
1. Rick's Step 3 invocation and post-verify, staging SQL Editor.
2. This session's own fresh `f136-audit.js` run immediately after, read-only against live
   staging: catalog rows for the tenant went **9,951 → 8,954, delta exactly 997** — matching the
   pre-run "safe" count precisely, not approximately. Duplicate pairs went **977 → 1**; the one
   surviving pair is the pre-existing blocked group (`64557390089200211`, PRH — Nightmare Before
   Christmas #2), confirmed still present at both its `2026-04` (referenced) and `2026-06`
   (maintained) rows. Safe/blocked went **997/1 → 0/1** — the blocked count is unchanged, exactly
   as expected: the maintained row is never a delete candidate, and the blocked row's own group had
   exactly one deletable sibling once, which is now the only survivor's month-pair `{2026-04,
   2026-06}` — i.e. dedup correctly left the referenced row's entire group alone beyond removing
   nothing else in it, because there was nothing else in it to remove.
   *Failure would have looked like:* a delta other than 997, a duplicate-pair count other than 1,
   or either of the two named catalog rows missing. None occurred.

**V6 — reservations are intact. GREEN.** Preorder counts for the tenant, before and after Step 3,
identical: **56 total / 22 unfulfilled / 34 fulfilled** (Rick, SQL Editor post-verify; independently
re-confirmed by this session's `f136-audit.js` re-run, which also fetches the full `preorders` set
and found the same 56 rows). *Failure would have looked like:* any of the three numbers moving.

**Confirming the plan doc's own handoff reasoning against the live result (§ S2 handoff note):**
correct as predicted — dedupe alone does not un-strand a REFERENCED row. Post-dedupe, the Nightmare
Before Christmas reservation shows **0** duplicate-group siblings deleted under it (there were none
to delete — its group's only other member is the one blocked row itself, which the DELETE's own
predicate excludes), and it remains exactly as stranded as before: `f136-audit.js` still reports it
under "STRANDED (not on the maintained/highest-month row)". Repointing it is Part D/S3, still
untouched, still Rick-gated.

**Commits:**
- `29780a8` (comic-preorder, `staging`) — `docs(F136): S2 dedupe_catalog_months() RPC — staging
  migration, not yet applied` (written before Rick ran it; superseded by this section)
- `7a8d6a1` (scripts repo, `main`) — `feat(F136): wire dedupe_catalog_months() into
  refreshCatalog's new-month branch`
