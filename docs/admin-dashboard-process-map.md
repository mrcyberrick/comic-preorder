# Admin Dashboard — Process Map (F121)

**Status:** **In execution.** § 5 is Rick's own walkthrough and is the authority
where it and the code disagree. **Structure DECIDED 2026-08-07 — Option B, as
modes within one `admin.html` (§ 5.7).** **Sessions 1–3 and W2/W3 are LIVE IN
PRODUCTION as of 2026-08-08** (PR #109, merge `9552ee6`, write-smoke passed —
§ 5.7.6). **Session 4 (the mode switch) is COMPLETE on staging 2026-08-08, not yet promoted.** Sessions 5–6 not started. Remaining decisions in § 6.

> ⚠ **§ 1–§ 4 are a snapshot of the page as it was on 2026-08-07, before any of
> this shipped.** They are kept deliberately, because they are the evidence the
> decisions were made from — but they are **no longer a description of the live
> page**. The dashboard is now **6 tabs, not 8**; the stats bar, Export All,
> All Reservations and Top Series are gone; the search lives on By Customer.
> **Read § 5.7.4's session index for current state; re-read `admin.html` before
> relying on any inventory line below.**

**Last verified against live code:** `admin.html` @ `40cc0e8`, 2026-08-07 — i.e.
**stale by design** for § 1–§ 4, per the warning above.

**Visual companion:** the process map, the two undrawn loops, and the option
comparison are rendered as diagrams at
<https://claude.ai/code/artifact/4e5686c4-160a-49fa-a237-401076d6bcf9>
(private artifact; this document is canonical where the two differ).

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
| Print **Lunar Order Sheet** | Paper Orders tab | **An in-store paper catalog** — future-FOC titles, each row carrying a **blank quantity box** for a customer to write in (`buildOrderSheetHtml()`, `:3673`) |
| Print **PRH Order Sheet** | Paper Orders tab | Same, PRH |

Two of these submit real money to a distributor. Two are a **customer-facing
browsing catalog**. They differ by the words "↓" and "Print", and by which tab
you are on.

**Corrected 2026-08-07 from Rick's walkthrough** (§ 5.1 step 8): the second pair
was first characterised here as a "shelf-copy browsing sheet". That was wrong on
both counts. Shelf-copy seeding is the **Suggest Shelf Order** button on
`mylist.html` (`docs/shelf-copy-suggested-order.md`), a different feature on a
different page. These two buttons print *"a physical version of the catalog"* for
the store — and the blank qty box is what customers write their orders in. It is
a **paper order form**, which is where the Paper Orders tab's input comes from
the following cycle (§ 5.4 W7). Named "Order Sheet", it is the one thing on the
page that is genuinely an order form for a *customer* rather than a distributor.

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

## 5. The workflows, as Rick performs them

Captured verbatim from Rick 2026-08-07. This is the authority for every
attribution below; where the code and this section disagree, this section is
what the store actually does.

### 5.1 Monthly — the ordering cycle

Rick's note: *"Not all steps need to go in the same order."*

| # | Step | Surface |
|---|---|---|
| 1 | **Order deadline signals a new catalog is coming.** Download catalog files + any shipping files from the distributor sites | *(external)* — the deadline is read as a **cue**, not set here |
| 2 | Enter paper orders — search each reserved title, add each paper customer, save. Then **as the admin, use Suggest Shelf Order to seed inventory**; review and adjust both | `admin.html` **Paper Orders** + **`mylist.html` Suggest Shelf Order** |
| 3 | **Maintenance Mode ON.** Export/download the Lunar and PRH Order Sheets | Header toggle + **Export bar** → Order Builder |
| 4 | Copy/paste the order-sheet lines into the distributor site and submit. **This is where a few titles come back rejected** for failing order requirements | *(external)* — **no app surface receives this** |
| 5 | **Print the By Distributor report** to share with the store | By Distributor → Print / Save Report |
| 6 | **Clear the order deadline** to review the new catalog before setting a new one. **Run the full import** with email notification = **N**. Commonly ~a week before the month changes | Header deadline ✕ + `import.js` |
| 7 | **Maintenance Mode OFF.** The deadline is considered now and set quietly. The **next weekly import** sets notification = **Y** to announce the new catalog and deadline | Header toggle + header deadline |
| 8 | **Print the Paper Orders report** — *"a physical version of the catalog"* for the store | Paper Orders → Print Lunar/PRH Order Sheet |

### 5.2 Weekly — the bagging cycle

| # | Step | Surface |
|---|---|---|
| 1 | Download shipping files (usually **Friday**) | *(external)* |
| 2 | Run the import, notification = **Y**, to promote interest | `import.js` |
| 3 | Print the **store report for This Week** | This Week (current anchor) → Print |
| 4 | Print the **Bagging Report for NEXT week** — not shipped yet | This Week (**Next →** anchor) → Print |
| 5 | Provide both reports to the store | — |
| 6 | Sometimes post the HTML shipping-report link to Facebook | `weekly-pull-feed` (separate repo) |

### 5.3 Continuous

| # | Activity | Surface |
|---|---|---|
| 1 | Monitor site activity | **`analytics.html`** — *"useful to determine what is working and what is not"* |
| 2 | Check for pending accounts | Pending tab |
| 3 | View orders | **By Customer** |
| 4 | Manage a customer to see upcoming titles | Paper Orders → Manage (impersonation) |
| 5 | Check This Week arrivals show shipping | **`arrivals.html`** |
| 6 | Watch for expiring FOC dates | **Order Follow-Up panel** — *"now visible as Order Follow-Up"*, previously done by scanning By Distributor |

### 5.4 Acts on vs glances at — Rick's own split

**Acts on:** expiring FOC → ad-hoc order · This Week bagging list → email inactive
customers who have arrivals · Print Bagging List · By Distributor (review orders,
print reports, verify paper orders).

**Glances at:** Subscriptions, Top Series, *sometimes* All Reservations —
*"All Reservations is not as useful as By Customer and By Distributor for
reviewing orders."*

**Never mentioned, in any of the 20 steps above or in either list:** the entire
**stats bar** (7 tiles), the **Withdrawn panel**, and **Export All (CSV)**.

### 5.5 What the walkthrough exposes

Ten mismatches between the page and the process. W2–W3 are time-critical; the
rest are structural.

- **W1 — The stats bar serves no step of any workflow.** Seven tiles, the most
  visually prominent element on the page, appearing in zero of twenty steps and
  in neither the acts-on nor the glances-at list. The bar whose tiles were
  reconciled against the Order Builder three times in one day (F121) is a bar
  with **no job**. The reconcile attempts happened *because it is there and looks
  authoritative*, not because a decision depended on it.
- **W2 — Step 3's buttons are the Order Builder, and Rick has never used it.**
  *"I have yet to use the order builder."* Since 2026-08-03 the export-bar
  buttons **are** the Order Builder (F101/F102) — so his next monthly cycle is
  the first real one, against a modal his step-3 mental model ("export/download")
  does not describe. Two known defects are waiting for it:
  - **confirm-on-export asks at step 3; rejections arrive at step 4.** Already
    filed (`docs/order-loop-closure-f108.md` § 8) as a design flaw; his
    walkthrough now confirms it against the real sequence.
  - **`order_type: 'adhoc'` and `catalog_month: currentCatalogMonth` are both
    hardcoded** (`admin.html:2206`, `:2208`). The monthly cycle therefore files
    as ad-hoc, and titles gathered cross-month (F111) file under the *wrong*
    month. `classifyForExport()` routes `adhoc` matches away from the "already
    ordered — your call" bucket, so **F102's remainder-defaulted quantity
    control silently drops on the following cycle** — the exact control that
    exists because of the 12-against-7 surplus.
  - Note the two ledger writers disagree: Mark Ordered files under the title's
    **own** `catalog_month` (`:2243`), the Order Builder under the **current**
    one. One table, two conventions.
- **W3 — The rejection route Rick believes he has does not exist.** *"I now have
  a way to flag them in the order builder from what I understand."* The Order
  Builder has **no rejection path**. Zero-quantity rejection is the **Mark
  Ordered** modal on the By Distributor tab (F108 Session B). At step 4 today,
  the only route from "PRH rejected these three" into the app is per-title,
  on a different surface, after the modal he was just in has closed.
- **W4 — The monthly cycle is a procedure, and the page models it as tabs.**
  Eight ordered steps bracketed by a Maintenance Mode window. The sequence
  exists, is stable, and lives entirely in Rick's head; nothing in the software
  knows the order or which step is current.
- **W5 — Order Deadline and Maintenance Mode are cycle-phase markers, not
  settings.** The deadline does **three** jobs: the customer-facing catalog
  banner, the At Risk / ad-hoc edge (`missesOrderCycle()`), and — per step 1 —
  Rick's own *"a new catalog is coming"* signal, cleared at step 6 and reset at
  step 7 as a phase marker. Its tooltip describes only the first. Maintenance
  Mode brackets steps 3–7 and is presented as a standalone toggle.
- **W6 — Both workflows span pages the dashboard does not link to.** Monthly
  needs `mylist.html` (Suggest Shelf Order, step 2); weekly needs
  `arrivals.html` (continuous 5) and the `weekly-pull-feed` repo. The admin
  dashboard is one surface in a workflow, not the workflow.
- **W7 — The paper loop closes across two monthly cycles.** Step 8 prints a
  catalog with a blank qty box → customers write orders on it in-store → the
  *next* cycle's step 2 keys them in. The two ends of that loop are a print
  button on the Paper Orders tab and a search box on the Paper Orders tab, and
  nothing on either says they are the same loop.
- **W8 — All Reservations may be valued for the wrong reason.** Rick rates it
  below By Customer and By Distributor for reviewing orders — but it holds the
  page's **only search box**. Its worth may be *search*, not *a flat list*.
- **W9 — Weekly is two prints from one tab at two anchors.** Current week (store
  report) and next week (bagging, not yet shipped). The print header does carry
  the week range (`:2706`), so the output is unambiguous — but the tab is named
  for its default anchor rather than its job.
- **W10 — Analytics is used, valued, and already a separate page.** The one
  continuous-cadence surface that was split out is the one Rick volunteers
  praise for. That is the strongest available evidence that separating by
  cadence works here.

---

## 5.6 Product constraint — the process map is one tenant's process

Raised by Rick 2026-08-07, on reading the § 5.5 options: *"moving off paper orders
is a choice many stores will want to make for the best ROI. I do not want to bake
this into the order process if we run fully online."*

**This is a binding constraint on any structural change, and it is wider than
paper.** § 5.1–5.3 is the process of *one* store. Phase 5 put a second tenant on
production; Phase 6 opens self-service signup to stores whose processes nobody
has seen. Any design that hardcodes this walkthrough makes every process
difference a code change.

**Paper is a leaf, not the trunk.** Of the eight monthly steps, **1.5 are
paper-specific**:

| Step | Paper-coupled? |
|---|---|
| 1 · download catalog + shipping files | No — universal |
| 2a · **enter paper orders** | **Yes** |
| 2b · Suggest Shelf Order | **No** — every store orders shelf copies for walk-ins |
| 3 · maintenance on + export order sheets | No |
| 4 · submit at distributor, rejections return | No |
| 5 · print By Distributor for the store | No |
| 6 · clear deadline + full import | No |
| 7 · maintenance off | No |
| 8 · print paper catalog | **Partly** — see below |

Two consequences:

- **Step 2 bundles two unrelated jobs** and should be split regardless of this
  question. Paper entry is transitional; shelf-copy ordering is permanent.
- **Step 8 is not strictly paper-coupled.** Its role in *Rick's* loop (§ 5.5 W7)
  is to feed next month's step 2 — but a printed browsing catalogue is a
  discovery tool for walk-ins, which an online-only shop with a physical store
  may still want. **Do not delete it as part of removing paper.**

**The capability check already exists in data.** `user_profiles.is_paper`
(boolean, default `false`; set by `create-paper-customer`, § 4.x) means a tenant
with zero `is_paper = true` rows is an online-only store. **No config flag, no
per-tenant setting, no migration** is required to detect this — and nothing
should be added. A settings toggle would be a second source of truth for
something the data already answers.

### What this rules in and out

- **Rules OUT** any guided run built as a fixed list of N steps ("step 3 of 8").
  That is the shape that forces a fork per tenant and breaks at Phase 6.
- **Rules IN** a design where **cycle phases are fixed and the tasks inside a
  phase are data-driven.** Phases are industry structure, not store structure —
  a monthly catalogue, an FOC cycle, weekly shipments. Which tasks appear in a
  phase follows from what the tenant actually has (`is_paper` rows, subscriptions,
  distributors in use).
- **Option B is unaffected** — Ordering / Bagging / Accounts are universal
  cadences.
- **Option C is slightly strengthened, with a higher execution bar.** Its value
  was never enforcing a sequence; it is (a) the app knowing the cycle phase and
  (b) giving step 4's rejections somewhere to land. **W5 already shows Rick
  running a phase machine by hand** — Order Deadline as the "new catalog coming"
  cue, cleared at step 6, set at step 7, with Maintenance Mode bracketing
  steps 3–7. C done correctly formalises state that already exists rather than
  inventing a procedure.

**Desirable property this produces:** a tenant's dashboard gets *simpler* as they
convert off paper. The ROI decision the operator makes is rewarded by the
software rather than ignored by it.

---

## 5.7 DECIDED 2026-08-07 — Option B, separate surfaces by cadence

**Rick:** *"B fits better as the order is not all fixed."*

Option C is **rejected on its merits, not deferred** — the monthly step order is
genuinely flexible, so a guided run would fight the operator every cycle. Do not
revisit C in a later session without new information; the person who performs the
process has answered the question C depended on.

### 5.7.1 Surface allocation

| Surface | Cadence | Contents |
|---|---|---|
| **Ordering** | Monthly | Order Deadline · Maintenance Mode · Order Builder (both distributors) · By Distributor + cycle selector + Print/Save Report + Mark Ordered · Paper Orders **bulk entry** + **catalog print** · Withdrawn panel |
| **Bagging** | Weekly | This Week + week nav + Print Bagging List (both anchors) · link out to `arrivals.html` for the shipping check |
| **Customers** | Continuous | Pending · By Customer · Invite Customer · Paper customer list + **Manage** · Subscriptions |

**Removed from the dashboard entirely:**

| Element | Disposition |
|---|---|
| Stats bar — 7 tiles | **Delete.** Zero workflow steps (§ 5.5 W1). Resolves § 3.3 by removal. |
| Export All (CSV) | **Delete.** No named job in any of the twenty steps. |
| Top Series | ~~Move to `analytics.html`.~~ **CORRECTED 2026-08-08 at implementation, Rick approving: DELETE.** See § 5.7.5. |
| All Reservations | **Delete the tab; rehome the search** — see § 5.7.2 P3. |

### 5.7.2 Three problems B opens, with recommendations

**P1 — Order Follow-Up is continuously monitored but monthly-acted-on.** Rick
watches it between cycles (§ 5.3 #6) and acting on it means placing an ad-hoc
order. Putting it only on Ordering hides the alarm behind a surface he is not on.
**Recommendation: it is an alert, not a workspace.** Persist a count badge on the
Ordering nav item from every surface, with the detail panel on Ordering. Keeps
one job on screen without muting the signal. Same treatment for Withdrawn.

**P2 — Paper Orders splits cleanly, which de-risks B's main cost.** The option-B
sketch warned it *"has to be split or duplicated"*. It does not — the cut is
clean, because the two halves are already different UI:
- **bulk entry + catalog print → Ordering** (monthly step 2 / step 8)
- **paper customer list + Manage → Customers** (continuous #4)

**P3 — All Reservations holds the page's only search box** (§ 5.5 W8). Deleting
the tab deletes the search. **Recommendation: rehome the search rather than the
list** — a search on Customers that finds a reservation and jumps to its customer.
Confirm with Rick before deleting, since the search may be the part he uses.

**P4 — File count vs. the nav-sync drift source.** `CLAUDE.md` § Files That Must
Stay in Sync records the nav block across five HTML files as a known drift source.
Three admin pages makes it seven. **Recommendation: keep ONE `admin.html` and
make the three surfaces top-level modes**, each with its own lazy fetch, replacing
the eight-tab strip with a three-mode switch. This is **B in behaviour** — one job
on screen, and each mode fetches only its own slice (§ 4) — while touching no new
files, adding nothing to the sync set, and allowing one surface to ship at a time.
A genuine page split can follow later if it earns itself; the reverse is far
harder.

### 5.7.3 Both remaining questions answered — 2026-08-07

Rick accepted both § 5.7.2 recommendations as put:

- **P3** — **rehome the search, retire the list.** All Reservations' flat table
  goes; a search lands on Customers that finds a reservation and jumps to its
  customer.
- **P4** — **one `admin.html`, three top-level modes.** Not three files. B in
  behaviour (one job on screen, per-mode lazy fetch), with nothing added to the
  nav-sync set and one surface shippable at a time.

### 5.7.5 Top Series — the "move it" decision was wrong, corrected at implementation

**Recorded 2026-08-08. § 5.7.1 originally said "move to `analytics.html` — not
a deletion, a correct home." Reading both ends at session 3 showed that was
wrong, and Rick approved deleting it instead.**

| | Analytics Operations cards | Top Series |
|---|---|---|
| Source | `usage_events` | `preorders JOIN catalog` |
| Question | what people **did** | what is **reserved right now** |
| Scope | rolling **30 / 90 days** | **one catalog month** |
| Examples | *"reserve events, last 30 days"*, *"net subscribers, last 30 days"*, *"share of reserves, last 90 days"* | *"reservations in the August catalog"* |

**Dropping a state-based, one-month card into a row of event-based, 30-day
cards would have recreated F121's own defect on the analytics page** —
similar-sounding numbers at different scopes with nothing on screen to
distinguish them. A workstream that exists to remove that pattern must not
plant it somewhere else.

Three further facts pointed the same way:

- **Rick only glances at it** (§ 5.4) — it is in neither acts-on list.
- **Its counting unit remains undeterminable** (§ 3.4). An attempt to settle it
  empirically at session 3 returned nothing, because F20 correctly pins
  `get_popular_series` to `current_tenant_id()` and a service-role probe
  carries no tenant claim. A number nobody acts on, whose unit nobody can
  state, is a poor candidate for careful preservation.
- **The job it half-did is already done properly.** "What should I stock" is
  the shelf-copy suggested order, which computes per-title demand from real
  reservations and writes it (`docs/shelf-copy-suggested-order.md`). Top Series
  was a ranked list to read and act on by hand.

**`get_popular_series` stays in the database** — `app.js`'s
`Recommendations._getPopularSeries` still uses it for the customer catalog
page. Only the admin surface is gone.

**This is the sixth correction this workstream has made to its own plan at
implementation time**, and the pattern is consistent: the map is right about
*what exists*, and reading the actual code is what settles *what to do about
it*.

### 5.7.6 Promoted to production 2026-08-08 — PR #109, merge `9552ee6`

**Sessions 1–3 and the W2/W3 Order Builder work are LIVE ON PRODUCTION.**
Client-only (`admin.html`, `style.css`); no schema change, no migration.

Pre-flight that mattered: **production was verified to already hold 859
`order_type = 'monthly'` rows** before merging. Had its CHECK constraint not
accepted `'monthly'`, every *Record submitted order* click would have failed
with a 400 **after the real order was already placed with the supplier** — the
worst possible moment to find out. Confirmed against the live database rather
than inferred from the staging result.

Post-deploy verification (read-only): production serves the new build; the
shared `.stats-bar` CSS survived and `mylist.html` / `arrivals.html` still use
it; both order-sheet buttons intact; `preorders` 2,005 / `order_submissions`
860 / `catalog` 11,724 all reading normally; ledger distribution unchanged.

**Write-smoke PASSED** — confirmed by Rick 2026-08-08. Run by hand rather than
by the agent: it needs a real browser session on production, the Playwright
runner aborts on a prod `SUPABASE_URL` by design, and a service-key insert
would bypass both the client code and RLS — proving nothing about what the
smoke exists to test.

**Sessions 1–3 and W2/W3 are therefore fully closed.** Remaining F121 work is
sessions 4–6 (Bagging → Customers → Ordering modes).

### 5.7.4 Session index

| # | Session | Scope | Plan | Status |
|---|---|---|---|---|
| — | **W2/W3 Order Builder fixes** | `order_type` hardcode, confirm-on-export timing, rejection route | `docs/order-builder-record-split.md` | **LIVE IN PRODUCTION 2026-08-08** (staging `ff13d0f` → PR #109, merge `9552ee6`) — V1–V7 green, 89/89, write-smoke passed. `catalog_month` deliberately left to Rick (that plan § 7). |
| **1** | **Removals** | Stats bar, Export All (+ `makeExportRows`), and the spec asserting them | `docs/admin-restructure-1-removals.md` | **COMPLETE on staging 2026-08-08** (`1ec32a7`) — V1–V7 green, 86/86 suite. **LIVE IN PRODUCTION 2026-08-08** (PR #109). |
| 2 | Search rehome + All Reservations retire | Search built on By Customer (filters, auto-expands, keeps full totals); tab deleted | `docs/admin-restructure-2-search-rehome.md` | **COMPLETE on staging 2026-08-08** (`649a4b6`) — V1–V7 green, 91/91, spec 16 added. **LIVE IN PRODUCTION 2026-08-08** (PR #109). |
| 3 | ~~Top Series → `analytics.html`~~ **Top Series deleted** | Decision corrected at implementation (§ 5.7.5) — moving it would have recreated F121's defect on the analytics page | — (§ 5.7.5) | **COMPLETE on staging 2026-08-08** (`6845326`) — 176 lines removed; `get_popular_series` kept for the customer catalog page. **LIVE IN PRODUCTION 2026-08-08** (PR #109). |
| 4 | **Mode switch** | 3-mode nav (Customers · Bagging · Ordering), chrome follows its mode, one attention dot, always lands on Customers | `docs/admin-restructure-4-bagging-mode.md` | **COMPLETE on staging 2026-08-08** — 98/98 suite, `PLAYWRIGHT_EXIT=0`; two rounds of Rick's feedback folded in (§ 8, § 9). Bagging's light load is **dormant** by design — see § 9.1. **Not promoted.** |
| 5 | **Customers** mode | Pending · By Customer (+ search from session 2) · Invite · paper customers + Manage · Subscriptions | not written | Not started |
| 6 | **Ordering** mode | Largest and most consequential; goes last so the W2/W3 fixes settle first | not written | Not started |

**Sequencing rationale.** W2/W3 is dated and independent of all of this. Session 1
removes rather than moves, so every later session has less to relocate. Sessions
4–6 run smallest-first so the mode pattern is proven on the surface where a
mistake is cheapest.

---

## 6. Decisions owed

**Sequencing recommendation:** decision 1 is time-critical and should not wait
for the structural work. Decisions 2–3 are cheap and independent. Decision 4 is
the actual F121 session.

1. **Fix the Order Builder before Rick's first monthly use (W2/W3).** Real money,
   a known-wrong `order_type`, and a rejection route that does not exist. Already
   has a home: `docs/order-loop-closure-f108.md` § 8 ("decoupling record from
   download"). The walkthrough turns that from a design concern into a dated one.
2. **Delete or reduce the stats bar (W1).** Zero workflow steps, and the direct
   cause of the reconcile attempts. The cheapest large win available, and it
   removes § 3.3 rather than fixing it.
3. **Rename the Paper Orders print buttons (§ 3.2 / W7)** — two strings, and it
   stops two pairs of buttons sharing a name across two unrelated jobs.
4. ~~**Page structure (W4/W10).**~~ **DECIDED 2026-08-07 — Option B**, built as
   modes within one `admin.html` (§ 5.7). Remaining sub-decision: **P3**, whether
   All Reservations' search is rehomed or dropped.
5. **One vocabulary** for copies / titles / reservation rows — applied to every
   tile, header, panel and print surface at once, not tile by tile (§ 3.3 is what
   tile-by-tile produces).
6. **Whether § 3.1 and § 3.4 are fixed here or filed** — per CLAUDE.md
   § Stop and ask. Note § 3.1 and § 3.2 may dissolve on their own under
   decision 4.
7. **F122's fix direction** (judge on newest catalog row vs carry manual
   reservations forward) — F122 defers this here explicitly.
8. **Load-cost fix scope (§ 4)** — follows from decision 4.

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
