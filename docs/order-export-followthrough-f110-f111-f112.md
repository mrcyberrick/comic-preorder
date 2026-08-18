# Order-Export Follow-Through — F110 (withdrawals) + F111 (FOC across months) + F112 (distributor model)

**STATUS:** COMPLETE | staging=2026-08-03 | prod=2026-08-04 (PR #101) | findings=F110,F111,F112,F113,F114

**Status:** **Both sessions COMPLETE, live in production.** Session A (detection) — 2026-08-03.
Session B (surfacing) — complete on staging 2026-08-03, live in production 2026-08-04 via PR #101
(merge `303c255`, a general staging→main promotion that carried it along), re-verified live
2026-08-09 by serving-build markers (`#withdrawn-panel`, `allPreordersAllMonths`, `gatherCollapsed`).
See § 8 Completion criteria and `docs/technical-reference.md` § 13 F110/F111/F112/F113 for full
evidence. *(Corrected 2026-08-18 — this line previously read "Session B — PLANNED, not started,"
stale for two weeks; found via `git log --merges --ancestry-path` to PR #101, not by re-reading
this file — the F105 mechanism, restated in CLAUDE.md's own F110/F111/F113 entries on 2026-08-09.)*
**Plan written:** 2026-08-03 (planning session; execution handed to fresh CLI sessions).
**Follows:** `docs/order-export-foc-window-and-order-state.md` (F101/F102) — **complete and live in production** 2026-08-03 (PR #100, merge `5951a30`). Nothing in that work is broken. All three findings here are gaps that reading the PRH and Lunar vendor documentation exposed.
**Not a phase sub-deploy** — standalone correctness/enhancement work. Phase 5 closed 2026-07-15; Phase 6 not started.
**Environments:** staging first in both sessions. Production promotion is Rick's explicit call, per session.

**Authoritative inputs read during planning (2026-08-03, all from disk):** `CLAUDE.md` in full; `docs/technical-reference.md` § 4.3, § 4.11, § 6.2, § 6.8, § 12, and § 13 (F66, F80, F82, F85, F101, F102, F108, F109, F110, F111, F112); `docs/order-export-foc-window-and-order-state.md` in full; live `admin.html`, `app.js`, `mylist.html`, `import-staging.js`; the live Lunar CSV header. **Plus a decision interview with Rick on 2026-08-03** — recorded in § 2, because two of his rulings *overturn* what § 13 currently records.

**Live production reads performed during planning (read-only, service role):** the `ACTION COMICS #1 FACSIMILE` disposition (§ 2.3), and the `preorders` row-count measurement that produced **F113** (§ 2.5). No writes, no DDL.

---

## 1. Goal

Close the three gaps the vendor-documentation read exposed, in the order that makes each one honest:

1. **A withdrawn title is invisible** (F110). The distributor stops publishing a code; the app never notices; reservations keep pointing at a book that cannot arrive. Eight MIDNIGHT X-MEN #2 copies are in this state on production right now.
2. **The Order Builder can only see one catalog month** (F111), but a distributor FOC cycle spans several. The panel it shipped with projects a "nothing dropped silently" confidence that holds only inside the month it can see.
3. **Two facts the app doesn't represent** (F112): Lunar publishes an `InitialOrderDue` deadline and a `TitleNote` risk field, both sitting unread in a file already on disk.

And one defect found while planning:

4. **The admin dashboard reads half the `preorders` table** (F113, filed this session). 2,004 rows on production, no `.range()`, PostgREST caps at 1,000. Harmless today; hard-blocks F111.

---

## 2. Decisions and domain facts established 2026-08-03 (Rick) — read this before the runbook

**Two of these overturn what `docs/technical-reference.md` § 13 currently says.** They are recorded here in full and § 13 was corrected the same day.

### 2.1 F112(b) is OVERRULED — Backordered is *not* worse on PRH than on Lunar

§ 13 F112 asserts, on the strength of PRH's own documentation (*"Carts must be confirmed before their FOC date… Any unconfirmed quantities will not be included"*), that **a passed FOC is terminal on PRH and recoverable on Lunar**, and that the backorder-risk panel therefore overstates severity for Lunar titles.

**Rick, 2026-08-03:** *"Backorders are treated the same for PRH and Lunar — they both can be ordered after the FOC date but availability can not be guaranteed. I do not want to distinguish them as such."*

The operator places these orders; the vendor doc describes the *cart* mechanism, not the whole relationship. Both can be true: the FOC cart closes, and a **new** order can still be placed afterward against whatever stock remains. **So there is no Lunar/PRH asymmetry to build.** § 13 F112's (b) half is withdrawn.

**The important distinction the vendor docs obscured is a different one — late ≠ withdrawn:**

| | Can it still be ordered? | Will it arrive? |
|---|---|---|
| **FOC passed, never ordered** ("Backordered") | **Yes**, both distributors | Maybe — availability not guaranteed |
| **Withdrawn upstream** (F110) | **No** — the code no longer exists | **No** |

This makes F110 the finding that actually matters here, and it means existing copy is wrong.

**Consequence — a copy correction is now in scope for Session B.** The shipped panel and `docs/order-export-foc-window-and-order-state.md` § 2.4 both say a Backordered title is one that **"cannot arrive"** and where the customer is committed to a book that will never come. Per Rick that is too strong: it *may* arrive. The phrase that *is* accurate is "cannot arrive" applied to a **withdrawn** title. Fix the wording; do not weaken the urgency — an unordered title past FOC is still a failure, just a recoverable one.

### 2.2 F110 — the customer is told, and cancellation is re-enabled

Rick's ruling, 2026-08-03: **"Admin + customer flag."** A reservation on a withdrawn title:

- is surfaced to the admin (import console output + a dashboard panel), **and**
- is marked on **My List** as no longer available, **and**
- **becomes cancellable again**, despite the FOC lock.

**This is a deliberate, Rick-authorized exception to the FOC lock**, which the session brief scoped OUT. It is in scope now because he chose the option that says so explicitly. **Implement it at the call sites, not in the primitive** — `isFocPast()` / `isFocLocked()` (`app.js:1373–1385`) stay byte-for-byte untouched; the *consumers* gain a "withdrawn overrides the lock" condition. Those primitives are used across `catalog.html`, `mylist.html` and `admin.html`, and changing them would alter the lock everywhere.

**The exception must also override the *ordered* lock, not just the FOC lock.** On My List today (`mylist.html:904–907`) the state is `isOrdered = fulfilled || isCodeOrdered(c)` and `isLocked = focLocked || isOrdered`. The MIDNIGHT X-MEN #2 codes **were submitted on the July cycle**, so they carry `order_submissions` rows and currently render "✓ Order placed" with no Remove button. If withdrawal only overrode `focLocked`, the exact case Rick asked to fix would stay locked.

> **Stated consequence, for the record.** Re-enabling cancellation on a withdrawn-but-ordered title means a customer can walk away from a copy the store may already have committed to. That is the intended trade — the alternative is a customer permanently bound to a book that cannot arrive. Two mitigations are built in: the withdrawn flag **clears automatically** if the code reappears in a later import (§ 4.2), and the admin panel lists every affected title. If Rick wants cancellations on withdrawn titles logged for follow-up, that is a small addition to name at S-B4, not an assumption to make here.

### 2.3 F111's live case — resolved on production during planning, and it fails today

`ACTION COMICS #1 FACSIMILE EDITION CVR A` (`0626DC0190`, **Lunar**), read from production 2026-08-03:

| Fact | Value |
|---|---|
| Catalog months present | `2026-05`, `2026-06` |
| Reservation | qty 1, unfulfilled, reserved **2026-06-02**, against the **`2026-05`** row |
| FOC | **2026-08-03 — today** |
| On sale | 2026-08-26 |
| `order_submissions` rows | **zero — never ordered** |
| Current production catalog month | **`2026-08`** |

So the reservation sits two catalog months behind the current one. The Order Builder and the backorder-risk panel are both scoped to `2026-08` and **cannot see it**. `isFocPast()` is strictly-before-today (`app.js:1373–1378`), so it is "at risk" for the rest of today and becomes **Backordered at midnight**, having never appeared on any surface in the app.

Its sibling `0626DC0192` (CVR C, catalog `2026-06`) **was** ordered — qty 1, `monthly`, submitted 2026-06-27. That is the 481-of-483 case from F111's measurement: ordered while its month was current.

**Use this pair as the plan's worked example.** One title demonstrates both the mechanism and why the measured exposure is small.

### 2.4 F110 — set difference only; do not add the PRH Delta file

The decision the brief asked for. **Set difference at import, and nothing else.**

PRH's *Monthly Catalog CSV* / *Weekly Catalog Delta* downloads do carry a structured `PP–Postponed` signal, and the store's current pull (`*_full_active.csv`) does not — it is the active-only export, so a withdrawn title is **absent, never flagged** (§ 13 F110, measured: 871/871 and 1280/1280 rows `IP / Active`). But:

- **Lunar has no status column at all** (`O/A` uniformly `N` across 1,511 rows), so the set difference is required regardless of what PRH offers.
- Adding a second PRH file means a new download step in a monthly manual process, a new parser, and a new failure mode — for a signal the set difference already produces.

**Revisit only if the set difference proves too noisy on PRH in practice.** Record the noise rate at the first two real imports.

### 2.5 F113 — the admin dashboard reads half the `preorders` table

Found while checking whether F111's widening was even implementable. `admin.html:679–693` fetches `preorders` with `.order('created_at', { ascending: false })` and **no `.range()`**, so PostgREST's default row cap applies.

Measured on production 2026-08-03:

| | |
|---|---|
| `preorders` rows (founding tenant) | **2,004** |
| Rows the page actually receives | **1,000** |
| Oldest row inside the cap | **2026-06-26** |
| Current-month (`2026-08`) rows | 101 true / **101 received — 0 missed** |
| Per-month totals | 03: 73 · 04: 250 · 05: 340 · 06: 476 · **07: 764** · 08: 101 |

**Nothing is visibly wrong today** — every consumer of `allPreorders` is month-scoped, and the newest-1000 window reaches back ~5 weeks, comfortably covering the current month. Two reasons it is still a defect:

1. **Silent cliff.** Monthly reservation volume is growing 250 → 340 → 476 → 764. The first month to cross ~1,000 starts truncating the *current* month — including both order exports — with no error anywhere.
2. **It hard-blocks F111.** The widening needs prior-month rows: exactly the 1,004 the query discards. `ACTION COMICS CVR A` was reserved **2026-06-02**, *outside* the cap. Widening the gather without paginating first would leave the one worked example F111 exists to catch still invisible, while the panel newly claimed to have looked for it. **That is worse than the honest gap it replaces.**

Same class as **F82** (fixed two-batch fetches capped at 2,000 rows), different call site. Rick's ruling: **fix it as Session B's first step**, before the widening.

### 2.6 Session split — confirmed A → B

Confirmed by Rick 2026-08-03, with one adjustment forced by § 2.2: F110's customer-facing half is client work, so it lands in B.

- **Session A — detect and record.** Import scripts (private scripts repo) + additive `catalog` columns. F110 detection, F112(a).
- **Session B — surface and act.** Client (`admin.html`, `mylist.html`, `app.js`). F113 pagination, F111 widening, F110's admin panel + My List flag + cancel exception, the § 2.2 copy correction.

A first: B's surfaces read columns A creates, and there is nothing to render until A has run at least once.

---

## 3. Current state — verified against live code 2026-08-03

Read from disk on 2026-08-03. **Re-verify every line number before editing** (`CLAUDE.md` § File Drift Prevention).

### 3.1 Client (`admin.html`, `app.js`, `mylist.html`)

| What | Where | Behaviour today |
|---|---|---|
| Preorder fetch | `admin.html:679–693` | no `.range()` → capped at 1,000 rows (**F113**) |
| Month scoping | `admin.html:709–710` | `allPreorders` filtered to `catalog.catalog_month === currentCatalogMonth` |
| FOC cycle list | `admin.html:608–622` | `distinctFocDates()` — reads `allPreorders`, so current month only |
| Export classification | `admin.html:630–669` | `classifyForExport()` — reads `allPreorders` |
| Backorder risk | `admin.html:769–789` | `computeBackorderRisk()` — reads `allPreorders` |
| Order sheet consolidation | `admin.html:1147–1179` | `makeOrderSheetRows()` — **groups by `catalog.id`** |
| Order Builder | `admin.html:1211–1224` | `openOrderBuilder()` — default = earliest not-yet-passed FOC |
| FOC primitives | `app.js:1373–1397` | `isFocPast` (strictly before today), `isFocLocked` (alias), `isFocThisMonth` |
| Export code | `app.js:1406–1410` | `exportCode()` — PRH `isbn‖item_code‖upc`, Lunar `item_code‖upc‖isbn` |
| My List lock | `mylist.html:904–907`, `:940–944` | `isLocked = focLocked ‖ isOrdered`; Remove button hidden when either is true |

**`allPreorders` has 15+ consumers** (`admin.html:609, 631, 736–742, 770, 848, 895–896, 1039, 1183, 1291, 1346, 1401, 1438, 1443, 3214, 3237`) — stats, By Customer, By Distributor, search, the reserved-titles report, This Week. **Widening that array globally would silently change every one of them.** See § 4.4.

### 3.2 Import (`import-staging.js` / `import.js`, private scripts repo)

| What | Where | Behaviour today |
|---|---|---|
| Lunar normalizer | `import-staging.js:166–196` | 24 mapped fields; **`InitialOrderDue` and `TitleNote` not read** |
| PRH normalizer | `import-staging.js:198–228` | 24 mapped fields |
| Catalog upsert | `:440–464` | `on_conflict=tenant_id,item_code,distributor,catalog_month`, batch 100 |
| Dropped-item call | `:466–482` | `delete_dropped_catalog_items(p_tenant_id, catalog_month, newItemCodes)`, **only when `isNewMonth`** |

**Lunar CSV columns confirmed against the live file** (`Lunar_Product_Data_0826.csv`, 59 columns): `InitialOrderDue` at index 18, `FOCDate` at 19, `TitleNote` at 58.

### 3.3 **Correction — F110's filed fix direction #1 does not work as written**

§ 13 F110 says:

> `import.js` already computes the current month's `item_codes` array for `delete_dropped_catalog_items()`. The codes it would drop but cannot (because reservations block deletion) are precisely the withdrawal candidates — surface them instead of discarding them.

**That array is the wrong set, and the function drops nothing.** Two independent reasons, both verified:

1. **`delete_dropped_catalog_items` compares within a single month.** Its body is `DELETE FROM catalog WHERE tenant_id = … AND catalog_month = … AND item_code != ALL(p_item_codes)` (§ 6.2; body quoted in § 13 **F66**). It never looks at the prior month, so a code present in July and absent from August is not in its scope at all.
2. **It matches zero rows on every run.** F66 established this precisely: the script calls it only when `isNewMonth`, and `isNewMonth` guarantees no rows existed for that month before the just-completed upsert — so every surviving row's `item_code` is already in `p_item_codes`.

The `id NOT IN (SELECT catalog_id FROM preorders …)` guard F110 alludes to belongs to **`purge_stale_catalog`** (§ 6.2), a different function. F110's *other* claim is correct and still holds: because that guard exists and `preorders.catalog_id` is `ON DELETE NO ACTION` (F10), **a withdrawn title with reservations keeps its catalog row.** The row survives; nothing interprets its absence.

**The set difference must therefore be computed explicitly, across months** — see § 4.2. § 13 F110 was corrected the same day.

---

## 4. Design

### 4.1 F112(a) — read `InitialOrderDue` and `TitleNote` (Session A)

**Two additive `catalog` columns, not JSONB.** Nothing in the schema uses JSONB and `catalog` is 29 flat columns; a JSONB blob would be a new pattern for two scalar values and would need unpacking at every read.

```
ALTER TABLE catalog ADD COLUMN initial_order_due date;
ALTER TABLE catalog ADD COLUMN title_note        text;
```

Both nullable, no default, no backfill. PRH rows leave both NULL (PRH publishes neither).

**Parse guard — the decision the brief asked for.** `InitialOrderDue` has known-bad values in the source: four rows `8/10/2026`, one `8/27/2027`, one `8/27/2028` against a file whose 1,505 other rows read `8/27/2026`.

- Parse with the existing `parseDate()`, then **reject anything outside `[first-of-catalog_month − 31 days, first-of-catalog_month + 92 days]`**, writing NULL instead.
- On the 08/26 file this keeps `8/27/2026` and `8/10/2026` (both plausible — an earlier deadline for some titles is not obviously wrong) and rejects `8/27/2027` and `8/27/2028`.
- **Print a count of rejected values** at import. A rising count means Lunar changed something.
- **Store per row. Never aggregate to a single per-file deadline** — a min/max over this column is exactly what the bad values would poison, and § 13 F112 warns about it directly.

`TitleNote` is stored verbatim (trimmed, empty → NULL). It is free text; nothing reasons over it this session. It exists so the allocation warnings (*"Allocations may occur"* ×31, *"Previously offered through Diamond. Never fulfilled."* ×16) are queryable — the cheap half of F108, from a file already on disk.

**Neither column drives behaviour in this plan.** Reading them is the whole scope. What the app *does* with `initial_order_due` is a later decision, and § 2.2's ruling means it is not a severity input.

### 4.2 F110 — withdrawal detection as an explicit cross-month set difference (Session A)

**Two additive `catalog` columns:**

```
ALTER TABLE catalog ADD COLUMN withdrawn_at            timestamptz;
ALTER TABLE catalog ADD COLUMN withdrawn_last_seen_month text;
```

`withdrawn_at IS NULL` means "not withdrawn" — so every existing row is correct with no backfill. `withdrawn_last_seen_month` records the last `catalog_month` in which the code was published, which is what the admin panel and My List need to explain *when* it vanished.

**The algorithm, run at import when `isNewMonth` is true, after the catalog upsert:**

1. `priorMonth` = `max(catalog_month)` in this tenant **strictly less than** the month being imported. *Not* the calendar-previous month — imports can skip.
2. `priorCodes` = distinct `(distributor, item_code)` in `catalog` for this tenant at `priorMonth`. **Page this read until a short page** — `catalog` is ~7,200 rows and the PostgREST default is 1,000. This is F82's trap and it is what corrupted the F101/F102 backfill generator; the same session's `.sql` generator hit it and reported most of the catalog as unmatched.
3. `currentCodes` = distinct `(distributor, item_code)` from the records just upserted. **Compare on the pair, not on `item_code` alone** — the catalog unique key is `(tenant_id, item_code, distributor, catalog_month)`, so the code is only unique per distributor.
4. `candidates` = `priorCodes − currentCodes`.
5. **Narrow to genuine withdrawals.** A candidate qualifies only if its surviving prior-month rows:
   - still hold **at least one unfulfilled `preorders` row**, and
   - have **`on_sale_date >= today`**.

   The second filter is what keeps the signal clean: a title legitimately leaves the catalog once it has shipped, and a past-on-sale title that never arrived is the *arrivals* problem, not a withdrawal. Both live cases pass it — MIDNIGHT X-MEN #2 on sale 2026-11-18, ACTION COMICS on sale 2026-08-26.
6. **Mark** the qualifying prior-month rows: `withdrawn_at = now()`, `withdrawn_last_seen_month = priorMonth`. Mark the rows the orphaned reservations actually point at — those are the prior-month rows, by construction.
7. **Clear on reappearance.** Any `(distributor, item_code)` in `currentCodes` that has a non-NULL `withdrawn_at` on any row for this tenant gets `withdrawn_at = NULL, withdrawn_last_seen_month = NULL`. Distributors re-list withdrawn titles; a permanent mark would be a lie and would strand the § 4.5 cancel exception open forever.
8. **Print** the marked and cleared codes with title and copy count. `--no-write` must print without writing.

**Why this cannot ride on `delete_dropped_catalog_items`:** § 3.3.

**Ordering constraint:** this runs *after* the upsert (so `currentCodes` is real) and *after* `purge_stale_catalog` (so surviving prior rows are genuinely reservation-held), but it must not be gated behind the `delete_dropped_catalog_items` call, which is a no-op (§ 3.3) and should be left exactly as it is.

### 4.3 F113 — paginate the preorder fetch (Session B, first)

Replace the unbounded `db.from('preorders').select(...)` at `admin.html:679–693` with a **count-first, paged** read, following the pattern already in this file at `:2690` and `:2741` (`.range(from, Math.min(from + 999, total - 1))`).

- Count first with `{ count: 'exact', head: true }`, then page 1,000 at a time until covered.
- **Do not use `range()` on a possibly-empty set without the count** — `CLAUDE.md` § Known Issues: Supabase `range()` returns **416** on empty results. The count-first shape avoids it.
- **PowerShell note for anyone verifying from the shell:** `@($raw | ConvertFrom-Json)` counts **1** regardless of row count in PS 5.1 — the deserialized array arrives as one pipeline object. Assign, then wrap. This cost the F101/F102 session a wrong pagination read and cost this planning session one too.

**Gate V-B1** proves the fix on data: after the change, `allPreordersAllMonths.length` on staging equals the exact `preorders` count, and on production (post-promotion, read-only check) equals 2,004+.

### 4.4 F111 — gather by FOC date across months (Session B)

**The single most important implementation constraint: do not widen `allPreorders`.** It has 15+ consumers (§ 3.1) covering stats, By Customer, By Distributor, search, the reserved-titles report and This Week, all of which are correctly month-scoped and were deliberately left that way by the F101/F102 session (§ 5 OUT of that plan, "accepted divergence").

Instead:

- `loadData()` keeps `allPreorders` exactly as it is — the paged result, filtered to `currentCatalogMonth`.
- Add **`allPreordersAllMonths`** — the same paged result, unfiltered.
- Point **only these four** at the new array: `distinctFocDates()`, `classifyForExport()`, `computeBackorderRisk()`, and the Order Builder's consolidation path.

**This costs zero extra network.** The fetch already retrieves every month and discards the rest at line 709; the widened array is data already in memory. (True only once F113 is fixed — before that, "every month" means "the newest 1,000 rows".)

**De-duplication — the rule the brief asked for.** Two distinct collapses are needed, and conflating them is the trap:

1. **Export consolidation collapses by `exportCode`, not by `catalog.id`.** `makeOrderSheetRows()` currently keys on `c.id` (`admin.html:1152`). Within one month that is equivalent to keying on the code; **across months it is not** — a re-listed title has one catalog row per month, so the same code would emit two lines in a `code,qty` order file. Group by `exportCode(c, distributor)` and sum. This is the identity `order_submissions` is keyed on (§ 4.11) and the identity the distributor recognises.

2. **Reservation gathering collapses `(user_id, order_code)` to one row.** A customer can hold reservations against both the May row and the June row for the same code — that is exactly F85's cross-month duplicate. F85's carry-forward fix (2026-07-15) closes this for subscriber auto-reserves but **not** for manual reservations. Keep the row with the **newest `catalog_month`**, tie-broken by latest `on_sale_date` — the same survivor rule F85's one-time production cleanup used, so the two agree.

   **Surface the collapse; never silently pick.** Any code where a collapse occurred gets a line in the held-back panel ("also reserved in 2026-05"). Silently choosing a row is precisely how F80 and F85 stayed hidden for months.

**The backorder-risk panel adopts the same widening** (Rick, § 2.6). `computeBackorderRisk()` reads `allPreordersAllMonths` and applies the same `(user_id, order_code)` collapse. **Expect the panel to get louder on first run** — prior-month strays that were structurally invisible all surface at once. That is the point, but say so before Rick sees it, and expect the first render to include real backlog rather than a clean slate.

**The V2 regression gate from F101/F102 no longer holds by construction**, and must be restated rather than quietly dropped: the widened gather *can* legitimately add titles the old export never contained. The replacement assertion is in § 6 (**V-B3**) — byte-identical output when the gather is artificially restricted to the current catalog month, proving the widening is the *only* difference.

### 4.5 F110 — surfacing (Session B)

**Admin.** A dashboard panel, sibling to the backorder-risk panel and following its shape (`admin.html:791–843`): hidden when empty, one row per withdrawn code with title, code, distributor, last-seen month, customer count and copy count. Visually distinct from Backordered — these are the two states that look similar and mean opposite things (§ 2.1).

**My List.** For a reservation whose `catalog.withdrawn_at` is non-NULL:

- Replace the status line with **"No longer available — withdrawn by the distributor"** and explanatory copy that this title cannot arrive.
- **Re-enable Remove.** At `mylist.html:904–907`, `isWithdrawn` overrides **both** `focLocked` **and** `isOrdered` (§ 2.2 — the MIDNIGHT X-MEN #2 codes carry ledger rows, so overriding only the FOC lock would leave them locked).
- `isFocPast` / `isFocLocked` in `app.js` stay **untouched**. The exception is a call-site condition.
- Add `withdrawn_at` (and `withdrawn_last_seen_month`) to the `catalog(...)` embed in **every** query feeding these surfaces — `admin.html:687–691` and My List's own preorder select. A missing field here fails silently as "not withdrawn", which is the wrong direction to fail.

**`Preorders.cancel()`** (`app.js:835–875`) gains a matching allowance so the client guard agrees with the UI. Note this remains **client-side only** — **F109** governs, and this change neither fixes nor worsens it.

### 4.6 The § 2.2 copy correction (Session B)

Wherever the shipped UI or docs say a Backordered title **"cannot arrive"** or that the customer is committed to a book that will never come, correct it to reflect § 2.1: still orderable, availability not guaranteed. Keep the urgency. Apply to the backorder-risk panel copy, `docs/order-export-foc-window-and-order-state.md` § 2.4, and § 13 F101's Backordered definition.

---

## 5. Scope

### IN — Session A (private scripts repo + schema)
- Four additive `catalog` columns: `initial_order_due`, `title_note`, `withdrawn_at`, `withdrawn_last_seen_month` (§ 4.1, § 4.2). Staging then production.
- Lunar normalizer reads `InitialOrderDue` (with the § 4.1 window guard) and `TitleNote`, in **both** `import.js` and `import-staging.js`.
- Withdrawal set-difference detection + marking + clear-on-reappearance + console output (§ 4.2), in both scripts.
- Unit tests in the scripts repo's committed suite for the pure functions (set difference, parse guard).
- Closeout: § 13 F110 / F112, `CLAUDE.md`.

### IN — Session B (main repo client)
- **F113 pagination first** (§ 4.3).
- `allPreordersAllMonths` + the four re-pointed consumers (§ 4.4).
- Export consolidation collapsed by `exportCode`; reservation collapse by `(user_id, order_code)`; both surfaced.
- Backorder-risk panel widened (§ 4.4).
- Withdrawn admin panel; My List flag + cancel exception; `Preorders.cancel()` allowance (§ 4.5).
- § 2.2 copy correction (§ 4.6).
- **Spec 15 extended** — mandatory, see § 6.
- Closeout: § 13 F110 / F111 / F113, `CLAUDE.md`.

### OUT — stop and ask
- **F108 invoice reconciliation.** Still blocked on sample PRH/Lunar order-confirmation files. F110 is deliberately the cheaper half.
- **F109** (moving the cancel guard into a `BEFORE DELETE` trigger). § 4.5 touches the same guard and must not be read as fixing it.
- **The PRH Monthly/Delta catalog file** (§ 2.4). Decided against; revisit only on measured noise.
- **Any change to `isFocPast` / `isFocLocked` themselves** (`app.js:1373–1385`). § 4.5 is a call-site exception; the primitives do not change.
- **Widening `allPreorders` itself**, or changing the reserved-titles report / Paper Orders tab / This Week / stats. The month-scoped divergence is accepted and recorded (F101/F102 plan § 5 OUT).
- **Acting on `initial_order_due`** — read and stored this session; what it drives is a later decision.
- **F72, F89, F90, F92, F93, F104, F105, F107.** Phase 6.
- **`config.js`**, credentials, Edge Functions.

---

## 6. Runbook

### Session A — detect and record (import scripts + schema)

**S-A0 — Pre-flight**
1. `/preflight`. Read `CLAUDE.md` in full; re-read § SQL authoring rules and § What's tracked vs local-only (**the import scripts live in the private scripts repo, not this one**).
2. Read this plan, then § 13 **F110, F112, F66, F82, F85** and § 4.3, § 6.2, § 12.
3. Re-read `import-staging.js` at every range in § 3.2 and confirm they match. Halt if not.
4. `/sql-check` before writing any SQL.
5. Confirm the next free finding ID (**F114** after F113 is filed by this planning session).

**S-A1 — Schema (staging)**
1. Write `docs/sql/catalog-withdrawal-and-lunar-fields.sql` — the four `ALTER TABLE … ADD COLUMN` statements, all nullable, no defaults, no backfill.
2. > **PAUSE → Rick (staging SQL Editor).** Run it. Verify with a live SELECT that all four columns exist and every existing row reads NULL.
3. No RLS change is needed — `catalog` has no INSERT/UPDATE/DELETE policy and is service-role-only (§ 4.3 Notes). **Confirm that is still true rather than assuming it.**

**S-A2 — Lunar field reads (§ 4.1)**
1. Add `initial_order_due` and `title_note` to `normalizeLunarCatalog()` in **both** scripts. PRH normalizer unchanged.
2. Implement the window guard as a **pure exported function** so it is unit-testable, and print the rejected count.
3. `node --check` both scripts; add unit tests to the scripts-repo suite (`npm test`).
4. **Gate V-A1:** a `--no-write` dry run against the real `Lunar_Product_Data_0826.csv` reports `title_note` populated on the expected rows and **exactly 2 rejected `InitialOrderDue` values** (the 2027 and 2028 rows). If the count differs, **halt and report** — do not adjust the window to make the number match.

**S-A3 — Withdrawal detection (§ 4.2)**
1. Implement the set difference as **pure exported functions** (prior/current code-pair sets → candidates), called from the new-month path after the upsert.
2. **Page the prior-month catalog read until a short page.** F82's trap; assert it in a test.
3. Implement marking and clear-on-reappearance. Both must be no-ops under `--no-write`, printing only.
4. Unit tests: a withdrawn code with unfulfilled reservations is a candidate; one with no reservations is not; one with a past `on_sale_date` is not; a reappearing code clears; codes are compared per `(distributor, item_code)`.
5. **Gate V-A2:** `--no-write` run of `import-staging.js` against the 08/26 files prints a withdrawal candidate list. **Gate V-A3:** seed a synthetic staging case — a prior-month catalog row with an unfulfilled reservation and a future `on_sale_date`, whose code is absent from the current file — then a real run marks exactly that row; re-running with the code present clears it. Tear down and **verify by live SELECT returning zero rows**.

**S-A4 — Production**
1. > **PAUSE → Rick.** Run the same `.sql` on production. The columns must exist on prod **before Session B promotes**, because the client reads them.
2. `import.js` changes ship with the schema but take effect at the **next monthly import**. Say so explicitly in the status update — S-A3's detection does not run until then.

**S-A5 — Closeout**
1. Update § 13 **F110** (incl. the § 3.3 correction) and **F112**. Update `CLAUDE.md`.
2. Commit to the **scripts repo** (`main`) and doc-only to this repo's `staging`, `--ff-only`.
3. `/wrap-up`.

### Session B — surface and act (client)

**S-B0 — Pre-flight**
1. `/preflight`. Read `CLAUDE.md` in full; re-read § Smoke-test ordering (**the Playwright suite tests the deployed site — a pre-push run cannot see your change**).
2. Read this plan, then § 13 **F111, F113, F110, F109, F101, F102, F80, F85**.
3. **Confirm Session A is complete and the four `catalog` columns exist on staging AND production.** Halt if not — B renders data A produces.
4. Re-read every line range in § 3.1 from disk. Halt on drift.

**S-B1 — F113 pagination (§ 4.3)**
1. Convert the `admin.html:679–693` fetch to count-first + paged, following `:2690` / `:2741`.
2. **Gate V-B1:** `allPreordersAllMonths.length` equals the exact `preorders` count for the tenant. Assert on staging; re-assert read-only on production after promotion.

**S-B2 — F111 widening (§ 4.4)**
1. Add `allPreordersAllMonths`; leave `allPreorders` and its 15+ consumers untouched.
2. Re-point `distinctFocDates()`, `classifyForExport()`, `computeBackorderRisk()`, and the Order Builder consolidation.
3. Collapse export consolidation by `exportCode`; collapse reservations by `(user_id, order_code)` on newest `catalog_month`; **surface both collapses** in the held-back panel.
4. **Gate V-B2:** with the staging equivalent of the ACTION COMICS shape seeded (a reservation in a prior catalog month with a future FOC and no ledger row), it appears in the Order Builder and in the backorder panel. **Gate V-B3** (replaces F101/F102's V2): with the gather artificially restricted to the current catalog month, both exports are **byte-identical** to the pre-change build — proving the widening is the only behavioural difference.

**S-B3 — F110 surfacing (§ 4.5)**
1. Admin withdrawn panel, visually distinct from Backordered.
2. My List flag; `isWithdrawn` overrides **both** `focLocked` and `isOrdered`; `Preorders.cancel()` allowance.
3. Add the two new columns to **every** `catalog(...)` embed feeding these surfaces.
4. **Gate V-B4:** seed a withdrawn title with an unfulfilled reservation **and an `order_submissions` row**, and confirm My List shows the withdrawn copy and an **enabled** Remove that succeeds. The ledger row is the point — without it the test passes for the wrong reason.

**S-B4 — Copy correction (§ 4.6) and the logging question**
1. Apply the § 2.2 wording fix to the panel and the two docs.
2. > **PAUSE → Rick.** Ask whether cancellations on withdrawn titles should be logged for follow-up (§ 2.2). Small either way; do not assume.

**S-B5 — Spec 15 + deploy**
1. **Extend `tests/15-order-export-ledger.spec.ts`** — mandatory, not optional. New coverage: cross-month gather (V-B2), the `exportCode` collapse, the withdrawn My List state with an enabled Remove (V-B4), and the widened backorder panel.
   **Trap, recorded in `CLAUDE.md` § Smoke Test Suite:** staging carries **857 real backfilled ledger rows**, so seeded fixtures share every panel with production-shaped data. **Assert on a seeded title or `data-catalog-id` — never `.first()`, never an exact count.** A `.first()` assertion in spec 15's first draft failed against a real staging title.
2. `/deploy-staging`. **Push first, confirm the new bytes are served, then run the suite.**
3. **Gate V-B5:** full `run-smoke.ps1` green **plus a real-browser check** of the widened panel, the withdrawn panel and the My List withdrawn state, **including at mobile width** (memory: `feedback_verify_css_visibility_real_browser`; two production incidents).
4. Tear down every seeded fixture; **verify by live SELECT returning zero rows**.

**S-B6 — Closeout**
1. Update § 13 **F110, F111, F113**. Update `CLAUDE.md`.
2. Commit to `staging`, `--ff-only`.
3. **Production promotion is Rick's explicit call** (`/promote-prod`). Raise it — the ACTION COMICS case and the 8 MIDNIGHT X-MEN copies are on production — but do not promote unasked.
4. `/wrap-up`.

---

## 7. Verification gates

| Gate | Session | Assertion | Why this and not a weaker one |
|---|---|---|---|
| **V-A1** | A | Dry run rejects **exactly 2** `InitialOrderDue` values | Pins the guard to the known-bad rows; a different count means the file changed, not the guard |
| **V-A2** | A | `--no-write` prints a withdrawal candidate list | Proves detection runs before anything writes |
| **V-A3** | A | Synthetic withdrawn row is marked; reappearance clears it | Clear-on-reappearance is the half that rots silently if untested |
| **V-B1** | B | Fetched row count equals the exact `preorders` count | The whole of F113; a spot-check cannot see a 1,000-row cliff |
| **V-B2** | B | A prior-month, future-FOC, unordered reservation appears in both surfaces | The ACTION COMICS case — the one F111 exists to catch |
| **V-B3** | B | Gather restricted to current month ⇒ **byte-identical** exports | Replaces F101/F102's V2, which the widening invalidates by construction |
| **V-B4** | B | Withdrawn + **ledger row** ⇒ My List shows withdrawn, Remove enabled and working | Without the ledger row the test passes for the wrong reason (§ 2.2) |
| **V-B5** | B | Full suite green **and** a real-browser check at mobile width | New UI; a green suite is not evidence on paths it does not cover |
| **V-B6** | B | Spec 15 extended and green | This path shipped to production with zero coverage once already |

---

## 8. Completion criteria

### Session A — all complete 2026-08-03
- [x] § 3.2 line ranges re-verified against disk before any edit
- [x] Four `catalog` columns live on staging **and production**, all nullable, existing rows NULL
- [x] `catalog` confirmed still service-role-only (no new RLS needed) — single `SELECT`-only policy (`users read tenant catalog`, `TO authenticated`) confirmed on both envs
- [x] Lunar normalizer reads `InitialOrderDue` + `TitleNote` in **both** scripts; window guard is a pure exported function; **V-A1** green (exactly 2 rejected values against the real 08/26 file)
- [x] Withdrawal set difference implemented as pure exported functions, prior-month read **paged**; **V-A2** and **V-A3** green
- [x] Unit tests added to the scripts-repo suite; `npm test` green (85/85); `node --check` clean on both scripts
- [x] Synthetic fixtures torn down, verified by live SELECT returning zero rows
- [x] § 13 F110 (incl. the § 3.3 correction) + F112 updated; `CLAUDE.md` updated
- [x] Status update states plainly that detection **does not run until the next monthly import**

### Session B
- [ ] Session A confirmed complete; four columns confirmed present on **both** environments
- [ ] § 3.1 line ranges re-verified against disk before any edit
- [ ] F113 pagination landed; **V-B1** green on staging and re-asserted on production post-promotion
- [ ] `allPreorders` **unchanged**; only the four named consumers re-pointed
- [ ] Export consolidation collapses by `exportCode`; reservation collapse by `(user_id, order_code)`; **both surfaced**, neither silent
- [ ] Backorder panel widened; first-run volume increase reported to Rick before he sees it
- [ ] **V-B2**, **V-B3** green
- [ ] Withdrawn admin panel + My List flag + cancel exception; `isFocPast`/`isFocLocked` **byte-unchanged**; **V-B4** green
- [ ] § 2.2 copy correction applied to the panel and both docs
- [ ] § 2.2 cancellation-logging question put to Rick and answered
- [ ] Spec 15 extended; **V-B5**, **V-B6** green; fixtures torn down and verified by SELECT
- [ ] § 13 F110 / F111 / F113 updated; `CLAUDE.md` updated

---

## 9. Rollback

- **Session A schema:** all four columns are **additive and nullable**. Nothing pre-existing reads them, so leaving them in place is a safe rollback for the script change. `DROP COLUMN` only if the design is abandoned — and **not** while Session B is live, since the client reads two of them.
- **Session A scripts:** `git revert` in the private scripts repo. The catalog upsert path is otherwise untouched, and the marking step is additive UPDATEs.
- **Withdrawal marks already written:** `UPDATE catalog SET withdrawn_at = NULL, withdrawn_last_seen_month = NULL WHERE withdrawn_at IS NOT NULL` — capture the affected rows first.
- **Session B client:** `git revert` on `staging`. All of B is read-side rendering plus one guard relaxation; it persists nothing of its own.
- **The cancel exception is the one genuinely irreversible piece** — a customer who cancels a withdrawn reservation is gone from `preorders` and a revert does not bring them back. This is inherent to Rick's § 2.2 decision, not a defect. If that matters, the § 2.2 logging question is the mitigation, and it should be answered *before* B promotes to production rather than after.

---

## 10. Out-of-session operational items

**Unchanged and still outstanding:** PRH holds **12 copies** of `75960621668000111` (MIDNIGHT X-MEN #1) against **7** reservations, FOC **2026-08-31**. Reminder armed for 2026-08-24 (routine `trig_01D8pWAMP5uuLqqb62gDjGrY` + calendar). Nothing in this plan changes it.

**New, and worth a look before Session B ships:** `ACTION COMICS #1 FACSIMILE EDITION CVR A` (`0626DC0190`, Lunar, 1 copy) reached FOC **2026-08-03** unordered and is now Backordered. Per § 2.1 it is **still orderable** with availability unguaranteed. No surface in the app will show it until F111 lands, so it needs a manual decision now.

---

## References

- `docs/technical-reference.md` § 13 — **F110** (withdrawal detection; fix direction corrected here at § 3.3), **F111** (cross-month FOC), **F112** (distributor model; (b) overruled here at § 2.1), **F113** (preorder fetch truncation, filed 2026-08-03), **F66** (why `delete_dropped_catalog_items` is a no-op), **F82** (the truncated-fetch precedent), **F85** / **F80** (cross-month reservations and month-scoped silent failures), **F101** / **F102** (the completed session this follows), **F108** (invoice reconciliation — still blocked), **F109** (the cancel guard is client-side only).
- `docs/technical-reference.md` § 4.3 `catalog`, § 4.11 `order_submissions`, § 6.2 catalog management, § 6.8 `get_ordered_codes`, § 12 import script.
- `docs/order-export-foc-window-and-order-state.md` — the completed F101/F102 session; § 2 domain interview, § 8 production deploy log.
- `CLAUDE.md` § Smoke-test ordering; § "Green is not the same as verified"; § SQL authoring rules; § Stop and ask; § Definition of Done.
- Live files: `admin.html`, `app.js`, `mylist.html`; `import.js` / `import-staging.js` (private scripts repo); `catalogs/Lunar_Product_Data_0826.csv`.
- Staging founding tenant `72e29f67-39f7-42bc-a4d5-d6f992f9d790`, project `puoaiyezsreowpwxzxhj`. Production `plgegklqtdjxeglvyjte`.
