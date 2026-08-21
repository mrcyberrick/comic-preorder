# F136 — catalog_month integrity: stale-date detection + duplicate-row cleanup

**STATUS:** NOT STARTED | staging=— | prod=— | findings=F136,F122,F110,F115
**Status:** **PLANNED — not started.** Written 2026-08-21 in a planning session that also
**identified the root cause F136 was filed without** (§ 2) and **corrected two statements in the
filed finding** (§ 3). No code was changed. All measurements in this doc are read-only GETs run
2026-08-21 against live staging *and* live production.
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
| **S1** | Part A + Part C(1) — guards and the widened report, both scripts, `npm test` extended | V1–V4 green |
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

**⚠️ Discovered while writing this plan — needs its own finding ID before S1 starts.**
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
(the purge not running is *why* duplicates accumulate). **Recommendation: file it as F137 and fold
the one-line fix into S1** — but per CLAUDE.md § "Stop and ask, don't fix inline", that is Rick's
call, and S1's handoff must not assume it.

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

- [ ] S1 — `inferCatalogMonth()` returns `null` on no match; prompt requires explicit month
- [ ] S1 — Lunar MMYY mismatch guard aborts without a typed `yes`
- [ ] S1 — cross-month collision pre-check reports and gates
- [ ] S1 — `classifyReservedDateDrift()` returns a third `unreserved` list; report prints it
- [ ] S1 — both scripts changed identically; `node --check` clean; `npm test` extended and green
- [ ] S1 — V1–V4 green, evidence pasted into § 11
- [ ] S1 — `f136-audit.js` committed to the scripts repo
- [ ] S2 — `docs/sql/f136-dedupe-catalog-months.sql` written, applied to staging, V5–V6 green
- [ ] S2 — RPC wired into the new-month branch, reports its count
- [ ] S3 — `docs/monthly-catalog-refresh.md` carries the revision-sweep step
- [ ] S3 — 2 prod reservations repointed, V7 green
- [ ] S3 — prod dedupe run, V8 green
- [ ] § 13 F136 status advanced; CLAUDE.md open-findings row updated or removed

---

## 11. Verification evidence

*(empty — filled in by the executing sessions)*
