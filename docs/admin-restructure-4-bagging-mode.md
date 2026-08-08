# Admin Restructure — Session 4: the mode switch, proved on Bagging

**Parent:** `docs/admin-dashboard-process-map.md` (F121) § 5.7.2 **P4**, § 5.7.4.
**Decision:** Option B, built as **modes within one `admin.html`** — Rick, 2026-08-07.

**Status:** Planned 2026-08-08.
**Target:** **staging only.**
**Branch:** `feature/admin-bagging-mode`
**Last verified against live code:** `admin.html` @ `43191b6`, 2026-08-08.

---

## 1. Why Bagging first

This is the **first structural change** of the restructure; sessions 1–3 only
removed things. Bagging is the cheapest place to prove the pattern because
`renderThisWeek()` is **already self-contained** — verified against live code, it
reads only:

- its own week-scoped `preorders` query (`catalog!inner`, all catalog months)
- `profileMap` (from `user_profiles`)
- `ledgerRejected()` → `orderLedger` (from `order_submissions`)
- `exportCode()` — a pure helper from `app.js`

It touches **none** of `allPreorders`, `allPreordersAllMonths`, `gatherCollapsed`,
or the shipment-evidence sets. So Bagging mode can skip `fetchAllPreorders()`
entirely — the 2,004-row paged fetch carrying a 24-column `catalog` embed
*including `cover_url`* — plus the whole `weekly_shipment` read.

**That is the load-cost win B was chosen for** (§ 4 of the process map), and it
lands here first.

---

## 2. Scope

### IN
1. Replace the 6-tab strip with a **3-mode switch**: Ordering · Bagging · Customers.
2. Allocate the existing tabs to modes (below). No tab is split or rewritten.
3. **Bagging loads light** — only what `renderThisWeek()` actually needs.
4. Ordering and Customers keep today's full load, unchanged.

### Allocation

| Mode | Contains |
|---|---|
| **Ordering** *(default)* | By Distributor · Paper Orders |
| **Bagging** | This Week |
| **Customers** | By Customer · Subscriptions · Pending |

### OUT — stop and ask
| Not touched | Why |
|---|---|
| **Page chrome** — Order Deadline, Maintenance Mode, Invite Customer, Order Builder buttons, Order Follow-Up and Withdrawn panels | Stays always-visible. Relocating chrome is sessions 5–6; doing it here would make the first structural change the largest one. |
| **Splitting Paper Orders** (§ 5.7.2 P2 — bulk entry → Ordering, Manage → Customers) | Real work, and unnecessary to prove the pattern. The tab sits under Ordering whole for now. |
| Ordering / Customers fetch isolation | Sessions 5–6. Only Bagging's is proved here. |
| `renderThisWeek()` itself | Byte-unchanged. Only *when* its data loads changes. |

---

## 3. Design

### 3.1 Default mode is Ordering, deliberately

The page currently lands on By Customer with everything loaded. Landing on
**Ordering** keeps load behaviour essentially unchanged for the default path,
which keeps this session's risk in the one place it belongs — the Bagging path.

It also keeps the **Order Follow-Up and Withdrawn panels visible on arrival**,
since they stay in chrome (§ 2 OUT).

### 3.2 What Bagging deliberately does not show

In Bagging mode the order alerts are not computed, because computing them needs
`gatherCollapsed` — i.e. the exact fetch this mode exists to avoid. Loading it
for a badge would defeat the change.

**Accepted, and it is a real trade-off worth naming:** § 5.7.2 P1 says the alerts
should stay visible from every surface via a count badge. That needs either the
full gather or a dedicated count query. **Deferred to session 6**, when Ordering's
own fetch is isolated and the cheap-count question is on the table anyway. Until
then the alerts are visible in the two modes that load fully, and Bagging is a
deliberate destination you switch to for a weekly task.

### 3.3 Idempotent loaders

`loadData()` currently runs unconditionally at init. It becomes
`ensureFullData()` — same body, guarded so it runs at most once — plus
`ensureBaggingData()`, which loads only `user_profiles` and `order_submissions`.
Switching modes calls the right one; switching back does not refetch.

---

## 4. Gates

| Gate | Check | Pass condition |
|---|---|---|
| **V1** | Mode switch renders | Three controls; exactly one mode's sections visible at a time |
| **V2** | **The point of the session** — Bagging loads light | On a fresh load into Bagging, **no request for the big `preorders` fetch and none for `weekly_shipment`**; This Week still renders correctly with customer names and unavailable flags |
| **V3** | Ordering unchanged | By Distributor, its month selector, Print/Save Report and the Order Builder all behave as today |
| **V4** | Customers unchanged | By Customer (incl. the session-2 search), Subscriptions, Pending all work |
| **V5** | No double-fetch | Switching modes repeatedly issues no duplicate loads |
| **V6** | Bagging correctness preserved | Week nav, Print Bagging List, rejected/withdrawn badges all still correct |
| **V7** | Full suite | Green — specs 06 and 16 exercise This Week and By Customer |

**V2 is the gate that matters.** Everything else is "nothing broke"; V2 is the
only one that proves the restructure bought anything.

---

## 5. Completion criteria

- [ ] § 2 applied, ranges re-verified against disk first
- [ ] V1–V7 green
- [ ] Fixtures torn down, confirmed by live SELECT
- [ ] Real-browser check by Rick
- [ ] Parent § 5.7.4 index updated

---

## 6. Rollback

Single feature branch, client-only, no DB change. `git revert` the merge.

---

## 7. Deploy log

*(empty — not started)*
