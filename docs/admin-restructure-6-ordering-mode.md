# Admin Restructure — Session 6: Ordering mode + the Paper Orders split

**Parent:** `docs/admin-dashboard-process-map.md` (F121) § 5.7.1, § 5.7.2 **P2**, § 5.7.4 row 6.
**Decision:** Option B, built as **modes within one `admin.html`** — Rick, 2026-08-07.

**Status:** **COMPLETE ON STAGING 2026-08-09** (`a6a7fbc`) — 103/103,
`PLAYWRIGHT_EXIT=0`. **Rick's real-browser check and production promotion both
owed.**
**Target:** **staging only.**
**Branch:** `feature/admin-ordering-mode`
**Last verified against live code:** `admin.html` @ `851c897`, 2026-08-09 — every
line range below was read from disk this session, not recalled.

---

## 1. Why this is the last one, and what is actually left

Session 4 built the mode switch and allocated the *existing* tabs to modes. It
explicitly deferred one thing (§ 2 OUT):

> **Splitting Paper Orders** (§ 5.7.2 P2 — bulk entry → Ordering, Manage →
> Customers). Real work, and unnecessary to prove the pattern. The tab sits
> under Ordering whole for now.

That deferral is this session. **Ordering's chrome is already correct** — read
from disk: `#btn-export-lunar`/`#btn-export-prh` carry `data-chrome="ordering"`
(`:184`), `.deadline-group` and `.maint-group` likewise (`:118`, `:128`), and
`by-distributor` / `paper-orders` already carry `data-mode="ordering"`
(`:196–197`). So this is **not** a chrome-allocation session. It is the Paper
Orders split, plus the two collisions that the split makes worse.

### 1.1 One correction to § 5.7.1 carried in

§ 5.7.1's allocation table still lists the **Withdrawn panel** under Ordering.
Session 4 § 8.2 moved both alert panels to **Customers**, on Rick's reasoning
that the panel triggers an *ad-hoc* order and ad-hoc means outside the monthly
cycle — which also matches process map § 5.3, listing FOC watching as a
*continuous* activity. **§ 8.2 is the settled answer; both panels stay on
Customers and this session does not touch them.** § 5.7.1 is stale on that row.

---

## 2. Scope

### IN

1. **Split the Paper Orders tab** along § 5.7.2 P2's cut.
2. **Rename the paper print pair** — Rick 2026-08-09 (§ 3.2 / process map § 6
   decision 3).
3. **Fix § 3.1** — the cycle-view lock's explanation moves to the control it
   explains — Rick 2026-08-09.
4. Update the specs the restructure invalidates, **found by grep before writing
   code** (§ 5.3), not after.

### OUT — stop and ask

| Not touched | Why |
|---|---|
| **Hiding paper surfaces for online-only tenants** (§ 5.6, `is_paper`) | Rick 2026-08-09: **not this session.** Hiding on a zero count would also hide the *Add* form from a store that wants to start using paper — a chicken-and-egg needing its own thought, and Phase 6 has not started. The split is written so a single `hasPaper` check could gate both tabs later. |
| Ordering **fetch isolation** | Deferred by session 4 to "sessions 5–6", but it buys nothing today and doing it would be work done twice. See § 4. |
| Both alert panels | § 1.1 — settled by session 4 § 8.2. |
| `renderPendingOrders()`, `printOrderSheet()`, `buildOrderSheetHtml()` table body, the submit path | Byte-unchanged except the two rename strings. Only *where* the UI lives and *when* its data loads changes. |
| The distributor pair's names (`↓ Lunar/PRH Order Sheet`) | Rick chose "rename the paper pair" over "rename both". The Order Builder buttons keep their names. |
| `allPreorders` month scoping | Process map § 7 / F111 § 4.4 — 15+ correctly-scoped consumers. |

---

## 3. Design

### 3.1 The cut

`#tab-paper-orders` (`:346–436`) holds four blocks. Three stay, one moves.

| Block | Lines | Destination | Why |
|---|---|---|---|
| Print Lunar/PRH order sheets | `:348–366` | **Ordering** | Monthly step 8 — prints the paper catalog |
| **Add Paper Customer** | `:371–385` | **Ordering** | Rick 2026-08-09 — see below |
| Add Title to Order + Pending Order + Submit | `:387–421` | **Ordering** | Monthly step 2 — the keying-in job |
| **Paper Customers list** (Manage · Claim) | `:423–434` | **Customers**, new tab | Continuous #4 |

**Add Paper Customer goes with the entry flow, not the list** (Rick's call). A
new paper customer appears at exactly one moment: they hand in their first
written sheet, mid-entry, at monthly step 2. Putting the create form on
Customers would break that flow to switch modes. The Customers-side list then
*manages* paper customers — Manage opens their pull list, Claim merges them when
they go digital — neither of which implies creation.

**Result:** Ordering keeps a `Paper Orders` tab (create + entry + print);
Customers gains a `Paper Customers` tab (list + Manage + Claim).

### 3.2 `paperCusts` is shared, so the load must be, too

Both halves read the same array (`:3439`). The Ordering entry pane needs it for
the per-title customer dropdowns (`renderPendingOrders` → `paperCusts.find`
`:3582`, `availCusts` `:3617`); the Customers list needs it for
`renderPaperCustomerList()` (`:3717`).

`initPaperOrdersTab()` (`:3442`) currently does all three jobs at once behind a
`dataset.loaded` flag parked on `#paper-customer-list` (`:4554–4559`) — **the
very element that moves**. So the guard has to move off it regardless.

Replaced by one idempotent loader plus two thin tab entry points:

```
ensurePaperCusts()      // load once per page, guarded on its own flag
  ├─ paper-orders tab click     → ensurePaperCusts() → renderPendingOrders()
  └─ paper-customers tab click  → ensurePaperCusts() → renderPaperCustomerList()
```

Same shape as session 4's `ensureFullData()` / `ensureBaggingData()`, for the
same reason: switching back and forth must not refetch.

**Cross-tab writes keep working and do not need reordering.** Both halves stay
in the DOM at all times — a hidden `.admin-section` is hidden, not absent — so
`paper-create-btn`'s existing `renderPaperCustomerList()` call (`:3474`) and
`paper-claim-btn`'s `renderPendingOrders()` (`:3787`) still hit live elements.
Adding a customer on Ordering repaints the Customers list you are not looking
at, which is correct: switch modes and it is already right.

### 3.3 One copy string breaks on the move

`renderPaperCustomerList()`'s empty state reads *"No paper customers yet. Add
one above."* (`:3720`). After the split the Add form is **not above it** — it is
in another mode. Corrected to name where it lives. A small string, recorded
because it is exactly the class of thing a restructure silently falsifies.

### 3.4 The rename (§ 3.2 of the process map, decision 3)

Four buttons, two names, two unrelated jobs — and after this split **both pairs
sit in Ordering mode**, so the collision gets worse, not better. Rick's call:
rename the paper pair, leave the distributor pair.

| | Before | After |
|---|---|---|
| Export bar (real money → distributor) | `↓ Lunar Order Sheet` | **unchanged** |
| Paper Orders tab (blank qty box → customer writes on it) | `Print Lunar Order Sheet` | `Print Lunar Catalog` |

**The printed artifact is renamed too, not just the button.** Its `<title>`
(`:3974`) and header (`:4146`) both say *"{distributor} Order Sheet"*. Renaming
the button and leaving the paper saying "Order Sheet" would move the collision
rather than remove it — the sheet is the thing that ends up in a customer's
hands. Both become *"{distributor} Catalog"*. Element **IDs are unchanged**
(`btn-print-lunar-order` / `btn-print-prh-order`); `printOrderSheet()` looks them
up by ID (`:4176–4178`) and churning them buys nothing.

### 3.5 § 3.1 — the reason travels with the control

`applyCycleViewLock()` (`:1166`) disables the two export-bar buttons, then writes
its explanation into `#bd-month-note` (`:239`) — **inside the By Distributor
tab**. Both are in Ordering mode now, but they are on different *tabs*: switch to
Paper Orders and you get two dead buttons with their reason on a tab you left.
The lock is correct (F111); its placement is not, and it does **not** dissolve
under the mode restructure.

**Fix: one note, in the export bar, beside the buttons it disables.**
`#bd-month-note` is deleted; `#cycle-lock-note` is added inside `.export-bar`
(already `data-chrome="ordering"`, so it is visible from every Ordering tab).

The text also **gains the month**, which it never carried:

> ⚠ Viewing the closed **June 2026** cycle on By Distributor — order-sheet
> exports disabled. Recording an order is still allowed.

Naming the month and the source tab is what makes it readable from a tab that
shows neither. Not two notes: a second copy is a second thing to keep true.

---

## 4. Ordering fetch isolation — deliberately not done, and why

Session 4 § 2 listed this for "sessions 5–6". It is **not** done here, and this
is a decision rather than an omission.

Session 4 § 9.1 already recorded that **every visit lands on Customers**, which
does a full load. Customers needs `allPreorders` *and* `gatherCollapsed` (for the
two alert panels and the dot), and `gatherCollapsed` is built from
`allPreordersAllMonths` — i.e. the big paged `preorders` read. So by the time any
route reaches Ordering, everything Ordering wants is already in memory. An
Ordering-specific fetch path would be **dormant on arrival**, exactly like
Bagging's is.

The unlock is the same one § 9.1 named: a cheap alert-count query, so the dot can
be computed without the full gather. Until that exists, splitting Ordering's
fetch is work whose effect is unobservable. Recorded here so a later session does
not read the § 2 OUT row as unfinished business.

---

## 5. Gates

| Gate | Check | Pass condition |
|---|---|---|
| **V1** | The split renders | Ordering ▸ Paper Orders shows create + entry + print, and **no** customer list; Customers ▸ Paper Customers shows the list with Manage/Claim, and **no** entry form |
| **V2** | **The point of the session** — the shared array survives the split | Add a paper customer on Ordering → it appears in the Ordering per-title dropdown **and** in the Customers list, without a page reload |
| **V3** | No double-fetch | Switching Ordering ▸ Paper Orders ↔ Customers ▸ Paper Customers repeatedly issues **one** `PaperCustomers.list()` for the page session |
| **V4** | Entry path unchanged | Search → add title → assign customer + qty → Submit still writes reservations correctly |
| **V5** | Rename is complete | Both buttons and the **printed page's** `<title>` and header read "Catalog"; the export-bar pair still reads "Order Sheet"; zero "Print … Order Sheet" left in `admin.html` |
| **V6** | § 3.1 fixed | Select a closed cycle on By Distributor → switch to Paper Orders → the buttons are disabled **and** the reason is on screen, naming the month. Return to the current month → note gone, buttons live |
| **V7** | Nothing else moved | By Distributor (cycle selector, search, Print/Save Report, Mark Ordered), Order Builder, both alert panels on Customers, Bagging all behave as today |
| **V8** | Full suite | Green, with spec 15's `#bd-month-note` assertions repointed and spec 17 extended for the new tab |

**V2 and V6 are the gates that matter.** V1/V4/V7 are "nothing broke". V2 is the
only one that proves the split did not quietly create two views of one array, and
V6 is the only one that proves the § 3.1 fix works from the tab where the bug
was visible.

### 5.3 Spec fallout — grepped before writing code

Session 4 § 7.6's lesson, applied ahead of time rather than after: *"a UI
restructure invalidates spec helpers by construction… grepping the suite for
affected selectors belongs in the session that moves the UI."*

Grep run this session, before any edit:

| Selector | Hits | Action |
|---|---|---|
| `#bd-month-note` | `15-order-export-ledger.spec.ts:1588, 1589, 1600` | **Repoint to `#cycle-lock-note`** — this is the one that would have failed |
| `data-tab="paper-orders"` | **none** | nothing to fix |
| `btn-print-*-order` / "Order Sheet" | **none** | nothing to fix |
| `.admin-tab` in spec 17 | 6, all **named** selectors, no hard tab counts | adding a Customers tab is safe; extend rather than repair |

---

## 6. Completion criteria

- [x] § 3 applied, every range re-verified against disk immediately before edit
- [x] V1–V8 green, with Playwright's **own** exit code captured (session 4 § 7.6)
- [x] No fixtures seeded, or seeded and verified torn down by live SELECT
- [ ] **Real-browser check by Rick on staging** — owed
- [x] Parent § 5.7.4 index row 6 updated
- [x] `CLAUDE.md` F121 line advanced

---

## 7. Rollback

Single feature branch, client-only (`admin.html`), no DB change, no schema
change, no Edge Function change. `git revert` the merge.

---

## 8. Deploy log

**Staging only, 2026-08-09.** Client-only (`admin.html`, `style.css`); no DB
change, no schema change, no Edge Function change.

| Commit | What |
|---|---|
| `71e6152` | This plan (doc-only, direct to staging) + two stale-status corrections |
| `a6a7fbc` | The split, the rename, and the § 3.1 note move |

**Suite: 103 passed / 103 declared, `PLAYWRIGHT_EXIT=0`, 13.9 min, zero
failures, zero flaky.** 99 before this session + 4 new.

| Gate | Evidence |
|---|---|
| V1 | spec 17 — each half visible on its own surface and **hidden on the other**; both directions asserted |
| V2 | spec 17 — create on Ordering → name present in the Customers list **with no reload** |
| V3 | spec 17 — 4 tab visits, **1** `is_paper=eq.true` request |
| V4 | spec 15 + existing paper coverage unchanged and green |
| V5 | spec 17 — paper pair reads "Catalog", export-bar pair still reads "Order Sheet", and neither paper button contains "Order Sheet" |
| V6 | spec 15 `closed cycle:…` — extended to switch to Paper Orders and assert the buttons are **still disabled and the reason still on screen** |
| V7 | full suite green; specs 06/15/16/17 cover By Distributor, the Order Builder, By Customer and Bagging |
| V8 | 103/103 |

### 8.1 Fixture teardown — verified by SELECT, not by the `finally` block

V2 creates a real paper customer through the **real UI**, which means the
`create-paper-customer` Edge Function makes a real auth user. Torn down with
`deleteUser()` in a `finally`, then **confirmed by live query against staging**
(URL asserted staging before running): `TEST_PW_Paper%` profiles = **0**, and
staging's 9 genuine paper customers untouched.

That check is not ceremony. F95 is the case where a teardown helper that never
checked `res.ok` orphaned **292** profiles before anyone looked.

### 8.2 What the pre-emptive grep caught

Session 4 § 7.6's lesson — *"a UI restructure invalidates spec helpers by
construction… grepping belongs in the session that moves the UI"* — was applied
**before** the first edit rather than after the first red run.

It found `#bd-month-note` asserted three times in spec 15. Left alone, those
would have failed *after* the code was pushed, and the session-4 log records how
expensive that shape of failure was to read correctly. Cost this time: one grep.

The same grep also **ruled things out**, which is the half that usually goes
unrecorded: no spec referenced `data-tab="paper-orders"`, the print buttons, or
the "Order Sheet" strings, and spec 17's six `.admin-tab` assertions are all
**named selectors with no hard counts** — so adding a Customers tab needed no
repair, only extension.

### 8.3 Two things checked rather than assumed

- **Print leakage (the F119 shape).** F119 was a panel printing on the Bagging
  List because it sat outside the print CSS's tab-scoped hide rule. The new
  `#cycle-lock-note` is inside `.export-bar`, which that rule already hides
  (`style.css:240`), and both report prints open their own `window.open`
  document, so page CSS does not reach them. **No new print surface.**
- **`.admin-section` really is hidden when inactive** (`style.css:973`), which
  is what makes V1's four `toBeHidden()` assertions meaningful rather than
  vacuous. Read before relying on it.

### 8.4 One test deleted for asserting nothing

The first draft of V2 also probed a `window.__paperCustNames?.()` hook that does
not exist, guarded so that a missing hook silently skipped the check. It would
have passed forever without testing anything — a green assertion that is really
an absent one, which is the F96/F115 shape in miniature. Removed rather than
made to work: the DB read plus the cross-mode render already prove the array is
shared, and the create handler rendering the *other* surface is what proves it.
