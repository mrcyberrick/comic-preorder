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

- [x] § 4 applied, every range re-verified against disk first
- [x] V1–V7 green (§ 8)
- [x] Fixtures gone, confirmed by live SELECT (0 rows)
- [ ] **Real-browser check by Rick — owed**
- [x] Parent § 5.7.4 session index updated

---

## 7. Rollback

Single feature branch, client-only, no DB change. `git revert` the merge.

---

## 8. Deploy log

**Executed 2026-08-08. Staging only — `649a4b6`. Production untouched.**
Branch `feature/admin-search-rehome` → `staging` ff-only.
**66 insertions, 44 deletions**, `admin.html` only.

### 8.1 Gates — all green, V1–V5 on the first run

| Gate | Evidence |
|---|---|
| **V1** | Search filters to the holding customer, group **auto-expanded**, only matching rows shown |
| **V2** | Non-matching customer absent (`toHaveCount(0)`) |
| **V3** | Header reads `5 items` (full) **plus** `showing 1 of 2` |
| **V4** | Clearing restores both groups, collapsed |
| **V5** | `[data-tab="all-items"]`, `#tab-all-items`, `#all-items-list` all gone; By Customer still renders `table.list-table` via `renderMiniTable()`; `#admin-search` now inside `#tab-by-customer` |
| **V6** | Specs 06 + 07 run directly: **9 passed** — the two that assert on `.customer-group-meta` and `#customer-groups` |
| **V7** | **91 passed, exit 0** (89 + spec 16's 2) |

Structure check: **7 tab buttons, 7 sections**, exactly paired — no orphaned
section, no dangling button.

### 8.2 New coverage — spec 16

`tests/16-admin-customer-search.spec.ts`. The search had **zero** coverage, so
the gates above could not otherwise be run. Every assertion is anchored to a
seeded title or customer name — never `.first()`, never an exact group count —
because staging carries real founding-tenant reservations that would satisfy a
loose assertion and prove nothing (spec 15's standing warning).

**V6 was nearly mis-reported.** The full-suite log is written by the `line`
reporter, which overwrites lines with carriage returns, so grepping it for the
two spec names returned **0 matches** even though both had run and passed.
Running them directly gave 9/9. *A grep over a progress-reporter log is not
evidence a test ran.*

### 8.3 Out of scope, found during teardown — one orphaned test profile

`pw-f5871cc8@example.test`, created **2026-08-06T18:30 UTC** — two days before
this session, so **not from this work**. This session's own fixtures verified
gone: `catalog`, `order_submissions`, and both `pw-scust*` / `pw-smini-*`
profiles all returned **0**.

It matches the `authenticatedPage` fixture's email shape, and **F95's fix
(2026-08-02) made `deleteUser()` throw on failure** — so a clean failure should
have surfaced as a test error rather than a silent orphan. Most likely an
interrupted run on 2026-08-06 (the F117–F120 session). **Left in place
deliberately, not deleted: it is the only evidence of how it got there**, and
whether F95 needs re-opening is Rick's call, not an inline fix.

Worth noting the near-miss in method: the first teardown query used
`&email.like.pw-%25` instead of `&email=like.pw-*`, which PostgREST ignored —
it returned **all 17** profiles and read as mass orphaning. The correct query
returns **1**.

### 8.4 Still open

- Real-browser check on staging — Rick's.
- The 2026-08-06 orphan above — file or ignore, Rick's call.
- **Not promoted to production.**
