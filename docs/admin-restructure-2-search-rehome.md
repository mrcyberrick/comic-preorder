# Admin Restructure — Session 2: search rehome, All Reservations retired

**Parent:** `docs/admin-dashboard-process-map.md` (F121) § 5.7.2 **P3** and § 5.7.4.
**Decision:** Rick, 2026-08-07 — *"Accepted as recommended"*: **rehome the
search, retire the list.**

**Status:** Planned 2026-08-08.
**Target:** **staging only.**
**Branch:** `feature/admin-search-rehome`
**Last verified against live code:** `admin.html` @ `592b2e0`, 2026-08-08.

---

## 1. Why

Rick rated All Reservations below By Customer and By Distributor for reviewing
orders (§ 5.4) — but the tab holds **the page's only search box**. Deleting it
outright would delete the search with it. The value is *finding a title fast*,
not *a flat list of every row*, so the search moves and the list goes.

---

## 2. Scope

### IN
1. Move the search input onto **By Customer**.
2. `renderByCustomer(search)` — filter, and **auto-expand** matching groups so a
   hit is visible without a second click.
3. Delete the All Reservations tab, its section, and `renderAllItems()`.

### OUT — stop and ask
| Not touched | Why |
|---|---|
| **`renderMiniTable()`** | **Shared** — `renderByCustomer()` (`:1391`) and `renderAllItems()` (`:1583`). Deleting it with the tab breaks By Customer. Same trap shape as session 1's shared CSS. |
| `renderThisWeek()` | Emits its own `.customer-group` / `.customer-group-meta` for the bagging card. Spec 06 asserts on it. Different renderer — must not be touched. |
| Default (unsearched) rendering | Must stay behaviourally identical: spec 07 (tenant isolation) asserts `#customer-groups .customer-group` renders. |

---

## 3. Design

### 3.1 Match predicate — extracted, not duplicated

`renderAllItems()` matched on `customer_name`, `title`, `series_name`,
`publisher`, `item_code`. That predicate is **extracted to
`matchesSearch(p, lc)`** and reused, rather than retyped into the new caller —
this modal-adjacent codebase has already produced three separate
rows-vs-titles bugs from exactly that kind of careful copy (F121 § 3.3).

### 3.2 Filtered groups auto-expand, and rows narrow to the hits

Searching filters to customers with ≥1 matching reservation, **and shows only
the matching rows within each**. Finding the customer but still hunting inside
their list is not "finding a reservation".

### 3.3 The header keeps FULL totals, and says so

A filtered group's header shows the customer's **complete** totals — not the
filtered subset — with an explicit `showing N of M` when a search is active.

Showing filtered totals would read as *"this customer has 1 item"* when they
have twelve. **That is exactly the F121 defect class this whole workstream
exists to remove**, so it must not be reintroduced by the fix for it.

---

## 4. Changes — `admin.html` only

| # | Location | Change |
|---|---|---|
| 1 | `:233–243` | Delete the All Reservations `<div class="admin-section">` |
| 2 | `:177` | Delete the tab button |
| 3 | `:187` | Add the search toolbar above `#customer-groups` |
| 4 | `:1358` | `renderByCustomer(search = '')` — filter, auto-expand, `showing N of M` |
| 5 | **new** | `matchesSearch(p, lc)` extracted from `renderAllItems()` |
| 6 | `:1571–1585` | Delete `renderAllItems()` |
| 7 | `:1078` | Delete the `renderAllItems()` call in `loadData()` |
| 8 | `:1650–1651` | Re-point the debounced listener at `renderByCustomer` |

**`renderMiniTable()` (`:1587`) stays.** Client-only, no DB change.

---

## 5. Gates

Run **after** push + plain-URL byte confirmation.

| Gate | Pass condition |
|---|---|
| **V1** | Typing a title on By Customer filters to customers holding it, group **auto-expanded**, only matching rows shown |
| **V2** | A non-matching customer is absent |
| **V3** | Header shows the customer's **full** totals plus `showing N of M` |
| **V4** | Clearing the box restores every group, collapsed — identical to today |
| **V5** | **Shared-helper gate.** All Reservations tab and `#admin-search`'s old home are gone; By Customer still renders its table via `renderMiniTable()` |
| **V6** | Spec 07 (tenant isolation) and spec 06 (bagging `.customer-group-meta`) still green — the two existing tests that touch these class names |
| **V7** | Full suite green |

Fixtures torn down, **verified by live SELECT returning zero rows.**

---

## 6. Completion criteria

- [ ] § 4 applied, every range re-verified against disk first
- [ ] V1–V7 green
- [ ] Fixtures gone, confirmed by SELECT
- [ ] Real-browser check by Rick
- [ ] Parent § 5.7.4 session index updated

---

## 7. Rollback

Single feature branch, client-only, no DB change. `git revert` the merge.

---

## 8. Deploy log

*(empty — not started)*
