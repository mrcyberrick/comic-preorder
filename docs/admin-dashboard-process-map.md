# Admin Dashboard — Process Map (F121)

**Status:** Planning — § 1–4 complete (code-derived, 2026-08-07). **§ 5 blocked on
the workflow interview with Rick.** No code changes proposed yet, by design.
**Last verified against live code:** `admin.html` @ `40cc0e8`, 2026-08-07.

**Finding:** `docs/technical-reference.md` § 13 **F121**. Also in scope for the
structural decision: **F122** (fix direction 2 depends on how the page models a
title across catalog months).

**Why this doc exists.** F121's fix direction is explicit that this is *not* a UI
patch — "patching individual labels is what produced the current state." So the
first deliverable is an inventory, not a change list: every element on the page
attributed to a data source, a time scope, a counting unit, and a business
cadence. That attribution is entirely derivable from code, and it is done below.
What is *not* derivable from code is which real-world job each element serves —
that is § 5, and only Rick can answer it.

---

## 1. The page as built — complete element inventory

`admin.html` is 4,208 lines: page chrome, 8 tabs, 3 modals, and 4 print/export
surfaces. Every element below was read from the file, not recalled.

### 1.1 Page chrome (always visible, above the tabs)

| Element | Backing data | Time scope | Counting unit | Cadence |
|---|---|---|---|---|
| Header subtitle | `currentCatalogMonth` | Current catalog month | — | Monthly |
| **Invite Customer** btn | Edge fn | None | — | Continuous |
| **Order Deadline** input | `app_settings.order_deadline` | Sets the cycle edge | — | Monthly |
| **Maintenance Mode** toggle | `app_settings.maintenance_mode` | None | — | Ops / ad-hoc |
| Stat: Total Copies | `allPreorders` | Current catalog month | **Copies** (Σ qty) | Monthly |
| Stat: Customers | `allPreorders` | Current catalog month | **Distinct users** | Monthly |
| Stat: Lunar Copies | `allPreorders` | Current catalog month | **Copies** | Monthly |
| Stat: PRH Copies | `allPreorders` | Current catalog month | **Copies** | Monthly |
| Stat: Est. Order Value | `allPreorders` | Current catalog month | **Dollars** | Monthly |
| Stat: Pending Approval | `Users.getPending()` | **None** | **Accounts** | **Continuous** |
| Stat: Fulfilled (excl. exports) | `allPreorders` | Current catalog month | **Reservation rows** | Monthly |
| Scope caption | — | states the month | — | — |
| **Order Follow-Up panel** | `gatherCollapsed` | **All catalog months** | **Titles** (+ copies) | Monthly / ad-hoc |
| **Withdrawn panel** | `gatherCollapsed` | **All catalog months** | **Titles** | Ad-hoc |
| Export All (CSV) | `allPreorders` | Current catalog month | Reservation rows | Monthly |
| ↓ Lunar Order Sheet | → Order Builder | **FOC cycles, all months** | **Export lines** | Monthly |
| ↓ PRH Order Sheet | → Order Builder | **FOC cycles, all months** | **Export lines** | Monthly |

### 1.2 Tabs

| Tab | Backing data | Time scope | Counting unit | Cadence |
|---|---|---|---|---|
| By Customer | `allPreorders` | Current catalog month | Reservation rows / customer | Monthly |
| **By Distributor** | `distributorRows()` | **A selected catalog month** | Titles, with copies | Monthly |
| All Reservations | `allPreorders` | Current catalog month | Reservation rows | Monthly |
| **This Week** | own query | **Mon–Sun calendar week, all months** | Reservation rows / customer | **Weekly** |
| Subscriptions | `Subscriptions.getAllAdmin()` | **None** | Series, subscribers | Continuous |
| Top Series | `get_popular_series()` RPC | Current catalog month | `reservation_count` — **unit unverified**, see § 3.4 | Monthly |
| Pending | `Users.getPending()` | **None** | Accounts | Continuous |
| Paper Orders | own queries | **None** (order building) | Reservation rows | Continuous |

### 1.3 Print / export surfaces — six, each with its own scope

| Surface | Where | Scope |
|---|---|---|
| Export All (CSV) | Export bar | Current catalog month reservations |
| Order Builder → order file | Export bar | Selected FOC cycles, **across catalog months** |
| Print / Save Report | By Distributor tab | **The selected** catalog month |
| Print Bagging List | This Week tab | Mon–Sun calendar week |
| Print (Top Series) | Top Series tab | Current catalog month |
| **Print Lunar/PRH Order Sheet** | **Paper Orders tab** | Current-month **catalog** rows whose **FOC is in a later month**, filtered to publishers with ≥5 all-time reservations — **contains no customer reservations at all** |

### 1.4 Modals

| Modal | Scope | Writes |
|---|---|---|
| Order Builder | Selected FOC cycles across all months | `order_submissions` (on confirm) |
| Mark Order Submitted | One title, filed under its own `catalog_month` | `order_submissions` |
| Invite Customer | None | Edge function |

### 1.5 Tally

**Six** distinct time-scoping models, not four as F121 recorded:

1. Current catalog month (`allPreorders`) — 5 stat tiles, 3 tabs, 1 export
2. All catalog months, collapsed (`gatherCollapsed`) — 2 panels, Order Builder
3. A *selected* catalog month (`distributorRows()`) — By Distributor + its report
4. Mon–Sun calendar week — This Week + Bagging List
5. **No time scope** — Subscriptions, Pending, Paper Orders, Invite, Maintenance
6. **Current-month catalog with FOC in a *later* month** — the two Paper Orders
   print buttons (the shelf-copy suggested order). Forward-looking, and the only
   surface on the page that reasons about titles nobody has reserved.

**Five** counting units, not three: copies, titles/distributor codes, reservation
rows, distinct customers, and dollars — plus accounts and series on the
continuous surfaces.

---

## 2. What the page's own header claims, versus what it does

The header reads *"Customer pre-orders for {Month}"* (set by `loadData()`).

Directly beneath it, before any tab is chosen, sit **two cross-month panels**
(Order Follow-Up, Withdrawn) and **two export buttons that gather across
months**. So the page states a single-month scope in its subtitle and then
contradicts it four times in the next 60 pixels of chrome — before the operator
has even picked a tab.

This is the whole of F121 in one screenful, and it is the reason the reconcile
attempts happened. The header is a promise the page does not keep.

---

## 3. Coherence defects found while mapping

These are **live today** and were not recorded in F121. None is a wrong
calculation; all four are the same class — a surface whose meaning cannot be
determined from what is on screen. Filing/fixing them is Rick's call (§ 6).

### 3.1 A page-level control is disabled by a tab-level control, and the reason is hidden

`applyCycleViewLock()` (`admin.html:1127`) disables **`btn-export-lunar`** and
**`btn-export-prh`** — which live in the page-level **Export Bar** (`:192–196`,
above the tabs) — based on `#bd-month`, the **catalog-month selector inside the
By Distributor tab** (`:228`).

The explanatory note it writes, `#bd-month-note` (`:232`), is **also inside the
By Distributor tab**.

So: select a past cycle on By Distributor, switch to By Customer, and two
always-visible buttons are greyed out with their explanation on a tab you are no
longer looking at. The `title` tooltip carries the reason, but a tooltip is not
a visible explanation. The lock itself is correct and deliberate (F111 — the
builder would build from live cycles while the table shows history); its
*placement* is what breaks.

### 3.2 Four buttons, two names, two unrelated jobs

| Button | Location | What it actually produces |
|---|---|---|
| ↓ **Lunar Order Sheet** | Export bar | Order Builder → the file submitted to Lunar, from customer reservations |
| ↓ **PRH Order Sheet** | Export bar | Order Builder → the file submitted to PRH |
| Print **Lunar Order Sheet** | Paper Orders tab | A **blank shelf-copy browsing sheet** — catalog titles with a *future* FOC, no reservations |
| Print **PRH Order Sheet** | Paper Orders tab | Same, PRH |

Two of these carry real money to a distributor. Two are a printed browsing aid.
They differ by the words "↓" and "Print", and by which tab you are on.

### 3.3 The stats bar still mixes units after the 2026-08-07 relabel

The relabel made five tiles say **Copies**. Sitting in the same bar, unchanged:

- **Pending Approval** — accounts, **no time scope at all**, from a different
  query than every other tile. It is a continuous-cadence number in a
  monthly-cadence bar.
- **Fulfilled (excl. exports)** — `allPreorders.filter(p => p.fulfilled).length`,
  i.e. **reservation rows**, displayed beside three tiles that now explicitly say
  "Copies". Same array, different unit, no label distinguishing them.

The relabel did what it set out to do and stopped exactly at the tiles that were
compared that day. That is the F121 mechanism operating *inside the fix for
F121*.

### 3.4 Top Series' unit is not determinable from anywhere available

The column header says **"Reservations"**. The RPC returns `reservation_count`.
`docs/technical-reference.md` § 6.4 documents the signature but not the
aggregate — whether it is `COUNT(*)` (rows) or `SUM(quantity)` (copies) is
recorded nowhere, so the number cannot be reconciled against any other tile on
the page without reading the live function definition.

**Also: § 6.4 is stale.** It states the body has *"No tenant filter"* and *"no
SET search_path"*. Both were fixed — F20 via `CREATE OR REPLACE` and F23/C5 via
`ALTER FUNCTION`, both verified at Phase 4.1 (`phase-4.1-soak-log.md` V7.3:
founding 16 / canary 0). This is an instance of the already-filed **F92**
(technical-reference.md carrying pre-Phase-5 claims), not a new finding — but
the live definition must be read before § 5 settles Top Series' vocabulary.

---

## 4. Load cost — why the page is slow, and why it is the same problem

The user's second concern ("one of the slower pages") is not separate from
F121. The page is slow *because* of the scope drift, and the structural decision
will largely determine the fix.

**Everything below fires before the first tab is usable.** `loadData()`
(`:1029`) is `await`ed at `:1152`, and `loadPendingAccounts()` (`:3140`) is
unconditional.

| # | Request | Bounded by | Grows with |
|---|---|---|---|
| 1 | `TenantContext.resolve()` RPC | — | — |
| 2 | Auth session + profile (`initNav`) | — | — |
| 3 | `Settings.isMaintenanceMode()` | — | — |
| 4 | `Catalog.getLatestMonth()` | — | — |
| 5 | `preorders` count (head) | — | — |
| 6 | `preorders` paged ×⌈n/1000⌉ | **nothing** | every reservation ever made |
| 7 | `user_profiles` (all) | **nothing** | every customer |
| 8 | `order_submissions` count + paged | **nothing** | ~180 rows/month, forever |
| 9 | `weekly_shipment` count + paged | **nothing** | every shipment row, forever |
| 10 | `Settings.getOrderDeadline()` | — | — |
| 11 | `Users.getPending()` | — | — |

**≈14–16 round trips**, four of them unbounded full-table reads that grow
monotonically and are never filtered by date, month, or anything else.
Production held 2,004 `preorders` and 857 `order_submissions` at last
measurement (F113, F116).

**The specific waste, and it is structural.** `fetchAllPreorders()` (`:993`)
requests a **24-column `catalog` embed including `cover_url`** for **every
reservation in every catalog month**. But `cover_url` is rendered only by
`renderByDistributor()` (`:1536`) and `renderMiniTable()` (`:1663`) — both
**month-scoped**, ~101 rows on production. The other ~1,900 rows exist solely to
feed `gatherCollapsed`, which needs roughly ten narrow fields and no images.

That shape is a direct artifact of the drift: F111 correctly widened the *rows*
fetched to all months and left the *column shape* as designed for the
month-scoped rendering surfaces. One fetch now serves two consumers with
opposite needs — which is § 1.5's problem, expressed as bytes.

**Not proposing a fix here.** If § 5 concludes the monthly and weekly jobs belong
on separate surfaces, the fix is to split the fetch along the same line, and
doing it before that decision would be work done twice.

**Owed:** a real measurement (DevTools timing + transfer size against production,
admin session) to replace this static analysis. Static reading gives the shape;
it does not give the number.

---

## 5. The workflow interview — OPEN, blocked on Rick

Not derivable from code. F121's own evidence for doing this: the five-step
walkthrough on 2026-08-06 took minutes and immediately exposed the
confirm-on-export timing flaw (`docs/order-loop-closure-f108.md` § 8).

Questions are in the chat handoff. Answers land here as § 5.1 (monthly ordering),
§ 5.2 (weekly bagging), § 5.3 (continuous admin), then § 6 becomes decidable.

---

## 6. Decisions owed (cannot be settled before § 5)

1. **Page structure** — one page with labelled cadence sections, or a split
   (e.g. Ordering / Bagging / Accounts). F121 is deliberately neutral.
2. **One vocabulary** for copies vs titles vs reservation rows, applied to every
   tile, header, panel and print surface at once.
3. **Whether § 3.1–3.4 are fixed inside this session** or filed as their own
   finding(s) — per CLAUDE.md § Stop and ask, this is Rick's call, not the
   agent's.
4. **F122's fix direction** (judge on newest catalog row vs carry manual
   reservations forward) — F122 § "Fix direction" defers this here explicitly.
5. **Load-cost fix scope** — follows from decision 1.

---

## 7. Out of scope

- Any change to `allPreorders`' month scoping without an explicit decision —
  F111 § 4.4 is emphatic that it has 15+ correctly-scoped consumers.
- `isFocPast` / `isFocLocked` — byte-unchanged through F110/F111 and staying so.
- The Order Builder's confirm-on-export split — already scoped to its own
  session (`docs/order-loop-closure-f108.md` § 8).
- Analytics (`analytics.html`) — a separate page with its own cadence work,
  closed 2026-07-19.

---

## 8. Deploy log

*(empty — no code changes proposed)*
