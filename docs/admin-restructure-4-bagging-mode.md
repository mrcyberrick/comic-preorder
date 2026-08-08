# Admin Restructure — Session 4: the mode switch, proved on Bagging

**Parent:** `docs/admin-dashboard-process-map.md` (F121) § 5.7.2 **P4**, § 5.7.4.
**Decision:** Option B, built as **modes within one `admin.html`** — Rick, 2026-08-07.

**Status:** **COMPLETE on staging 2026-08-08** — four commits (`de52328`, `a1e406a`, `2189b09`, `b2c65be`). Not promoted.
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

**As shipped** (revised from the plan's original after Rick's feedback — order
is continuous → weekly → monthly, which is also how often each is used):

| Mode | Contains |
|---|---|
| **Customers** *(default)* | By Customer · Subscriptions · Pending |
| **Bagging** | This Week |
| **Ordering** | By Distributor · Paper Orders |

### OUT — stop and ask
| Not touched | Why |
|---|---|
| ~~**Page chrome** stays always-visible~~ | **CHANGED DURING EXECUTION.** Chrome now follows its mode. Not a scope grab: Bagging does not load `gatherCollapsed`, so an always-visible Order Builder button there opens a modal reporting *nothing to export*. A control must not outlive the data behind it, so § 5.7.1's allocation arrived one session early. See § 7.2. |
| **Splitting Paper Orders** (§ 5.7.2 P2 — bulk entry → Ordering, Manage → Customers) | Real work, and unnecessary to prove the pattern. The tab sits under Ordering whole for now. |
| Ordering / Customers fetch isolation | Sessions 5–6. Only Bagging's is proved here. |
| `renderThisWeek()` itself | Byte-unchanged. Only *when* its data loads changes. |

---

## 3. Design

### 3.1 Default mode — planned Ordering, shipped Customers

**Planned** as Ordering, on the reasoning that it kept the default path's load
behaviour unchanged and so concentrated risk on the Bagging path.

**Rick overruled it, correctly** (2026-08-08): the continuous work — pending
accounts, By Customer — is what he opens the dashboard for; Ordering is a
monthly visit. The original choice optimised for the agent's risk management,
not the operator's workflow.

Landing on Customers also does a full load, so the Order Follow-Up and Withdrawn
detail is present on arrival anyway.

### 3.2 P1's cross-surface alert — partly delivered, and partly proved unnecessary

§ 5.7.2 P1 asked for the order alerts to stay visible from every surface. This
session delivered that as **attention dots on the mode buttons** rather than a
count badge — and measurement then cut three dots to two (§ 7.4).

The Bagging-mode gap remains by design: computing an Ordering alert needs
`gatherCollapsed`, the exact fetch Bagging exists to avoid. Since Bagging's own
dot was removed for having no signal at all, the practical consequence is only
that the *Ordering* dot is not computed while sitting in Bagging. Landing on
Customers (a full load) means it is accurate in the normal flow.

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

- [x] § 2 applied, ranges re-verified against disk first
- [x] V1–V6 green (7/7 mode gates); V7 full suite in § 7.6
- [x] No fixtures seeded — every gate ran against existing staging data
- [x] **Real-browser check by Rick 2026-08-08** — *"the UI looks good"* (§ 7.5)
- [x] Parent § 5.7.4 index updated

---

## 6. Rollback

Single feature branch, client-only, no DB change. `git revert` the merge.

---

## 7. Deploy log

**Staging only, 2026-08-08.** Client-only; no DB change.

| Commit | What |
|---|---|
| `de52328` | Mode switch + Bagging's light load |
| `a1e406a` | Fix: defer initial tab load past the temporal dead zone |
| `2189b09` | Rick's feedback — nav to top, land on Customers, attention dots |
| `b2c65be` | Drop the Bagging dot; re-scope Ordering from state to action |

### 7.1 V2 — what the session actually bought

Landing in Bagging issues **no `fetchAllPreorders()` and no `weekly_shipment`
read**, while This Week still renders with customer names and unavailable
flags. **V2b is its control** — Ordering *does* still fetch, so V2 cannot pass
by the fetch having been deleted or the selector being wrong.

The mode is remembered in `localStorage`, which is what makes that real rather
than theoretical: if every visit started in a full-loading mode, Bagging's
cheap path would never execute.

### 7.2 Three bugs the gates caught, all agent-introduced

1. **Temporal dead zone.** `applyMode()` runs at ~L1300 and called
   `renderThisWeek()`, but `let weekAnchorMonday` is not initialised until
   ~L2760. The call threw a `ReferenceError` inside an async function nobody
   awaits — it failed **completely silently** and the tab just looked empty.
   Split into selection (`applyMode`) and data load (`runInitialTabLoad()`, the
   last statement in the script). Chosen over `setTimeout(0)`, which would have
   worked for the same reason but left nothing explaining it.
2. **Chrome outliving its data.** Bagging does not load `gatherCollapsed`, so
   leaving the Order Builder buttons visible there would have opened a modal
   reporting **nothing to export** — silently wrong, worse than an error. Chrome
   now follows its mode, pulling § 5.7.1's allocation forward one session
   because it removes a bug class rather than adding a feature.
3. **Restoring chrome cannot assume `display:''`.** The alert panels carry
   inline `display:none` while empty; restoring to `''` would reveal an empty
   box on every return to Ordering. The exact prior value is saved and restored.

### 7.3 The instructive failure

V2's first run passed its network check and failed on rendering; the second run
did the opposite. Both were correct. The predicate matched on `cover_url`,
which **This Week's own query also selects** (the bagging list shows covers). In
run 1 the TDZ bug meant This Week never queried at all, so the bad predicate had
nothing to catch — **the first bug was masking the bad test.** The real
discriminator is `writer`, which only `fetchAllPreorders()` selects.

### 7.4 Rick's feedback, and what measuring it changed

Landing mode → **Customers**; order → **Customers · Bagging · Ordering**
(continuous, weekly, monthly); mode nav moved **above** the alert panels, which
had been pushing the primary navigation down the page.

Attention dots were requested for all three modes. **Measurement cut that to
two**, and the measurement is the point:

| Mode | Measured on production 2026-08-08 | Outcome |
|---|---|---|
| Customers | 0 pending now, non-zero at other times | **kept** — genuinely intermittent |
| Bagging | 117 arriving this week, **0 withdrawn, 0 codes net ≤ 0 in the whole 860-row ledger** | **removed** — could never fire |
| Ordering | 6 backordered, ~98 at risk | **re-scoped** — would have been permanently red |

Rick predicted the Bagging one unprompted. Checking it exposed the Ordering dot
as the same defect wearing the opposite mask: **an always-on dot carries exactly
as much information as a never-on one**, and is the more dangerous of the two
because it trains the operator to ignore it — how F96's alarm stopped being
believed. Ordering now means *action*: red = never-arrived (a customer is
already let down), amber = At Risk with FOC inside 7 days (still preventable).

A fourth agent bug was caught here by reading a return shape instead of
assuming it: `computeBackorderRisk()` returns entries **grouped by export code**
carrying `.catalog` directly, not raw `{ p }` wrappers. The filter destructured
`{ p }` and would have read `undefined` on every row — the amber dot would never
have fired, looking exactly like "nothing is at risk".

### 7.5 Not a bug: landing on Ordering right after the change

Rick saw Ordering on his first load after the default changed. That is
`localStorage` working as designed — a **remembered** mode deliberately outranks
the default, and he had been on Ordering while testing the previous build. It
self-corrected as soon as he chose Customers. Recorded so a later session does
not "fix" it.
