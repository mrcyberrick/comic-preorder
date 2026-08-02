# Order-Export Correctness Session — F101 (FOC window) + F102 (order state)

**Status:** Planned — 2026-08-02. Not started.
**Plan written:** 2026-08-02 (planning session; execution handed to a fresh CLI session)
**Not a phase sub-deploy** — standalone correctness session. Phase 5 closed 2026-07-15; Phase 6 not started.
**Target surface:** `admin.html` (order exports + By Distributor tab), one new table, `docs/technical-reference.md`.
**Environments:** staging first, then a production promotion at Rick's explicit request. **Production is where the damage is**, so this does not stop at staging.

**Authoritative inputs read during planning (2026-08-02):** `CLAUDE.md` in full; `docs/technical-reference.md` § 4.3 (`catalog`), § 4.4 (`preorders`), § 13 (F80, F85, F89, F90, F101, F102); live `admin.html` (lines cited in § 3, read from disk); live `app.js` (`Settings.getOrderDeadline`, `Preorders.setFulfilledByCatalogId`). **Plus a domain interview with Rick on 2026-08-02** — recorded in § 2, because three of its facts contradict or materially extend what § 13 records.

---

## 1. Goal

Stop the two ways the monthly distributor order goes out wrong:

1. **Titles are submitted one or more FOC cycles too early** (F101) — the distributor rejects them, and the rejection is caught only by reading the confirmation by eye.
2. **Titles already submitted on an earlier cycle are submitted again** (F102) — the distributor does not merge or cancel the earlier order, so the store pays for copies nobody reserved. **This has already happened: PRH holds 12 copies of MIDNIGHT X-MEN #1 against 7 reservations. Five surplus.**

Both are caused by the same wrong assumption in the same three functions: **one catalog month = one order.** It is not. A catalog month mixes many FOC cycles, and a title can survive across catalog months while a single order for it is still open.

---

## 2. Domain facts established 2026-08-02 (Rick) — read this before the runbook

These came from a planning interview, not from the code or from § 13. **Three of them contradict or materially extend the filed findings**, which is why they are recorded here in full rather than summarized. § 13 F101/F102 were annotated the same day to point here.

### 2.1 A catalog month spans many FOC cycles — thirteen, in July

The July 2026 catalog carried **13 distinct FOC dates**:

> 07/20, 07/27, 08/03, 08/10, 08/17, 08/24, 08/31, 09/07, 09/14, 09/21, 09/28, 10/19, 11/09

The full catalog is shown to customers, who may reserve against any of it. This is the structural fact behind F101: there was never a single "July order cycle" to scope to.

### 2.2 `order_deadline` is the **customer** cutoff, not the submission date — so it cannot anchor the export

`app_settings.order_deadline` already exists and is already tenant-scoped (`app.js:622–631`, `admin.html:101–103`, `:1048–1086`). July's was **7/24**. Today it drives exactly one thing: a customer-facing banner on the catalog page that hides itself once the date passes. **The exports never read it.**

The planning session's first instinct was to anchor the export window on it. **Rick ruled that out:** 7/24 is when customers must have their reservations in; the FOC band that actually goes to the distributor is driven by the distributor's own cycle dates, separately. The evidence agrees — July's deadline was 7/24 but the sheet that reached PRH covered **FOC 8/10–8/31**, with nothing at 07/27 or 08/03.

**Consequence for the design:** there is no derivable rule linking `order_deadline` to the order band, and the executing session **must not invent one**. The cycle is selected explicitly (§ 4.1).

### 2.3 Ad-hoc orders exist, and are excluded from the monthly order

When a title's FOC locks *before* the monthly order goes out (July: the 07/20 FOC dates, against a 7/24 deadline), a customer can still have reserved it. That title must be ordered **ad-hoc**, before its FOC passes. Ad-hoc orders are placed separately and are **excluded from the monthly order** — submitting them again is the same duplicate-order failure as F102, arrived at by a different route.

Nothing in the app models this today. Ad-hoc handling is entirely in Rick's head.

### 2.4 "Backordered" — the failure the FOC lock exists to prevent (Rick, 2026-08-02)

A reservation whose FOC passed **without an order having been placed** is **Backordered**. This is the store's own term; use it in code, UI and docs rather than inventing a synonym.

The FOC lock is already built and is deliberately hard (`isFocLocked` → `isFocPast`, `app.js:1358–1370`). Once FOC passes, the app blocks **both** new reservations **and cancellations** on that title — `catalog.html:1217–1218` treats an already-reserved locked title as *committed*, and `app.js:1436–1449` renders the locked state ("🔒 FOC Locked", disabled control, FOC badge).

**That is what makes a backorder bad, and it is easy to miss:** the lock commits the *customer* independently of whether the *store* ordered. A backordered title is therefore one where the customer cannot back out and the book cannot arrive. Rick's stated intent is to **actively avoid** this state, not merely to report it after the fact.

**Requirement (Rick, 2026-08-02):** notify admin users when a title is reserved whose FOC date falls **in the same month and/or precedes the order-deadline date** — i.e. while there is still time to place the ad-hoc order. See § 4.5.

**Reuse, do not reimplement:** `isFocThisMonth(dateStr)` (`app.js:1375+`) already computes exactly the "FOC within the current calendar month, including today and later this month" condition, using local date parts. It is already in customer-side use at `catalog.html:601`. Reimplementing this date logic is how F28 (`toISOString()` UTC shift) happens again.

### 2.5 `fulfilled` is already used to mean "ordered" — § 13 F102 understates this

F102 says *"`fulfilled` is an **arrival** flag, not an order flag."* That is true of the **code**. It is **not** how the flag is used. Rick's actual practice:

- A reserved title is treated as ordered when it is manually set via **"Mark Fulfilled"** on the By Distributor tab (`admin.html:666`, `:699` → `Preorders.setFulfilledByCatalogId`, `app.js:876`) — Rick's own words: *"not the best description of what is happening."*
- Or when a new catalog is loaded, which resets My List.

So the store *does* have an order record. It is mislabelled, and — the part that actually bites — **keyed wrong** (§ 2.6).

There are **no checks against an order invoice**, so rejected titles are never surfaced. Reconciliation currently runs off **shipping reports**; Rick's assessment is that **invoice reconciliation would be more accurate**, because a rejected title simply never ships and silence is indistinguishable from "not arrived yet." That is exactly how the MIDNIGHT X-MEN #2 UNKNOWNs went unnoticed.

True fulfillment status only becomes meaningful with POS integration, which is a future version.

### 2.6 Why renaming the flag would not have fixed anything

`setFulfilledByCatalogId` marks rows against a specific `catalog_id`. When a distributor re-lists a title in a later catalog month it becomes a **new `catalog` row** (the upsert key is `(tenant_id, item_code, distributor, catalog_month)` — § 4.3) with **new `preorders` rows** attached. June's mark does not carry to July's rows.

**Whatever records "ordered" must therefore be keyed on the distributor code, not on `catalog_id` or on a `preorders` row.** The code is what stayed constant in the live instance: `75960621668000111` across `2026-05`, `-06`, and `-07`.

This is the single most important technical constraint in this plan, and it is why § 13 F102's "per-reservation … `ordered_at`" hedge is the wrong half of its own suggestion — an `ordered_at` column on `preorders` inherits precisely the flaw F102 diagnoses in `fulfilled`.

### 2.7 Scope decision (Rick, 2026-08-02)

Invoice reconciliation is **out of this session** and filed as its own finding (**F108**) with its own future session. This session stops the duplicate-order bleed first.

Ad-hoc orders get **flag + exclude** — no dedicated ad-hoc export button. **Amended the same session:** the backorder-risk notification (§ 2.4, § 4.5) **is** in scope, superseding the earlier "no dashboard alarm" call, because the FOC lock commits the customer and the notification is what makes that lock safe rather than merely strict.

---

## 3. Current state — verified against live code 2026-08-02

Read from disk on 2026-08-02. **Re-verify every line number before editing** (`CLAUDE.md` § File Drift Prevention).

| What | Where | Behaviour today |
|---|---|---|
| Month scoping | `admin.html:485–486` | `allPreorders` filtered to `catalog.catalog_month === currentCatalogMonth` (`Catalog.getLatestMonth()`, `:454`) |
| Consolidation | `admin.html:837–869` | `makeOrderSheetRows` filters `!p.fulfilled` **only**; groups by `catalog.id`; sorts by item code |
| Lunar export | `admin.html:884–901` | adds `distributor === 'Lunar'`; emits `code,qty` using `ItemCode \|\| UPC \|\| ISBN` |
| PRH export | `admin.html:907–924` | adds `distributor === 'PRH'`; emits `code,qty` using `ISBN \|\| ItemCode \|\| UPC` |
| Order mark | `admin.html:666`, `:699` | "Mark Fulfilled" → `Preorders.setFulfilledByCatalogId` (`app.js:876`) |
| Order deadline | `app.js:622–631`; `admin.html:101–103`, `:1048–1086` | `app_settings.order_deadline`, customer banner only — **not read by any export** |
| FOC data | `catalog.foc_date` (date, nullable — § 4.3) | selected into the admin query at `admin.html:467`; carried into export rows at `:828`, `:859`; **never filtered on** |

**Neither export filters on `foc_date` at all.** That is F101 in one sentence.

**In-file precedent to follow, not reinvent:** `admin.html:2161–2169` (the shelf-copy suggested-order path) already does FOC-month windowing, with a comment explaining the string-prefix comparison and the deliberate decision to keep null-FOC rows. Match its style and its null handling.

**No order-state storage exists.** `preorders` (§ 4.4) has `fulfilled` / `fulfilled_at` and nothing else; there is no `ordered_at` column and no order table anywhere in the schema.

---

## 4. Design

### 4.1 F101 — explicit FOC-cycle selection at export

Because § 2.2 rules out deriving the band, the cycle is **chosen**, from the FOC dates actually present in the data.

- Add an **order-cycle selector** to the export area of the By Distributor tab. It lists every distinct `foc_date` among the current catalog month's **unfulfilled** reservations for that distributor, each with **(titles, total copies)** beside it.
- **Multi-select.** A monthly order spans several FOC dates — the observed July order covered four (8/10, 8/17, 8/24, 8/31).
- **Default:** the earliest not-yet-passed FOC date preselected. This is a **convenience, not a rule** — the selection governs. S1 may refine the default empirically; it must never silently widen it.
- **Null `foc_date` rows are included** (they have no cutoff to be past — matching `:2168`) but listed in the attention panel so they are visible.
- The export emits only the selected FOC dates.

**Everything held back is surfaced, never silently dropped** — this is F101's own stated requirement, and it is what stops the fix from trading one silent failure for another. After generating, show a panel grouping excluded rows by reason, with title, code, FOC date and copy count:

| Bucket | Meaning | Urgency |
|---|---|---|
| **Backordered** | FOC **passed**, never ordered (§ 2.4) | **Already failed.** Customer is committed and cannot cancel; the book cannot arrive |
| *At risk* | FOC not yet passed but locks before the monthly order | **Act now** — needs an ad-hoc order |
| *Outside selected cycle* | FOC later than the ticked dates | None — returns on a later cycle |
| *Already ordered* | in the ledger (§ 4.3) | Human call, quantity shown |
| *Ad-hoc ordered* | ledger row, `order_type = 'adhoc'` | None — handled separately |
| *Fulfilled* | existing `!p.fulfilled` filter | None |

**Backordered and "outside selected cycle" must be visually distinct.** They are the difference between *never* and *not yet*, and collapsing them into one "held back" list is how a backorder goes unnoticed.

### 4.2 F102 — a code-keyed order ledger

New table. Keyed on the **distributor code** so it survives re-listing (§ 2.5).

```
order_submissions
  id             uuid        PK, default uuid_generate_v4()
  tenant_id      uuid        NOT NULL → tenants.id ON DELETE CASCADE
  distributor    text        NOT NULL          -- exact case 'Lunar' | 'PRH'
  order_code     text        NOT NULL          -- the code actually submitted
  item_code      text                          -- catalog.item_code, for traceability
  title          text                          -- denormalized, for reading the ledger later
  quantity       integer     NOT NULL
  order_type     text        NOT NULL          -- 'monthly' | 'adhoc'
  foc_date       date                          -- the cycle it was ordered against
  catalog_month  text                          -- the month the export was generated from
  submitted_on   date        NOT NULL
  created_at     timestamptz DEFAULT now()
```

- **No unique constraint on `order_code`.** Re-ordering a code is legitimate — a customer may reserve after an order has gone out. The ledger records history; the *export* is what reasons over it.
- **Indexes:** `(tenant_id, distributor, order_code)` for the lookup; `(tenant_id, submitted_on)` for reading a cycle back.
- **RLS:** tenant-scoped via `current_tenant_id()`; admin-only read and write via `current_user_is_admin()`. Follow the existing policy shapes — **do not** write an `EXISTS (SELECT … FROM user_profiles)` policy (`CLAUDE.md` § Known Issues, RLS recursion).

**Written manually, not on export click.** Rick already marks titles by hand after ordering (§ 2.4); clicking Export produces a file, which is not proof of submission. The By Distributor mark writes the ledger. F108's invoice ingest later populates the same table automatically.

### 4.3 The duplicate check **surfaces, it does not auto-suppress**

Before generating, each code on the sheet is looked up in `order_submissions` for the same tenant + distributor. Any hit is shown in an **"Already ordered"** panel with the prior **quantity, date, cycle and order type**, and Rick decides per title: include the full quantity, include a reduced quantity, or exclude.

**Auto-suppressing would have been wrong on the live instance.** MIDNIGHT X-MEN #1: 5 already on order, 7 reservations — the correct action was to order **2**, not 7 (what happened) and not 0 (what auto-suppression would have done). § 13 F102 reaches the same conclusion independently: *"surface it for a human call, not to auto-suppress or auto-reorder."*

### 4.4 Ad-hoc orders — flag and exclude (§ 2.3, § 2.7)

A ledger row with `order_type = 'adhoc'` excludes that code from the monthly export, and it appears in the held-back panel under *ad-hoc ordered*. No separate export button and no dashboard alarm this session — Rick's explicit call.

### 4.5 Backorder-risk notification (§ 2.4)

The preventive half of this session. F101's FOC window stops the store ordering **too early**; this stops it failing to order **at all**.

**Trigger — a reservation is at risk when its title's `foc_date` satisfies either:**
- `isFocThisMonth(foc_date)` — FOC falls in the current calendar month (reuse `app.js:1375+`, do not reimplement); **or**
- `foc_date <= app_settings.order_deadline` — FOC locks on or before the customer cutoff, so the monthly order will not cover it.

Either condition means the FOC will lock before the monthly order goes out, so an **ad-hoc order is required**. Both are evaluated against unfulfilled reservations with no `order_submissions` row for that code.

**Three states, and they must be told apart:**

| State | Condition | What it means |
|---|---|---|
| **At risk** | trigger true, FOC **not** passed, not ordered | Actionable — place the ad-hoc order now |
| **Backordered** | FOC **passed**, not ordered | Already failed — customer committed, cannot cancel, book cannot arrive |
| *Cleared* | an `order_submissions` row exists for the code | Handled; drops off the list |

**Where:** a persistent panel on the admin dashboard, visible without navigating to a tab, listing at-risk and backordered reservations with title, code, FOC date, **days remaining**, customer count and total copies — sorted soonest-FOC first. Backordered rows are visually distinct and sort to the top.

**In-app, not email, in this session — and why.** Email means an Edge Function plus MailerSend, and the transactional sender identity is mid-reorganisation (F99: `noreply@mrcyberrick.us` on GoDaddy, consolidation onto `pulllist.app` pending an 2026-08-20 DMARC read; F72: per-tenant branding unresolved). Taking that dependency would couple a money-losing fix to an unrelated blocked workstream. A persistent in-app panel has no delivery dependency and cannot silently fail the way F96's send did.

> **If Rick wants a pushed notification (email/SMS) rather than an in-app panel, that is a deliberate follow-on**, not a change the executing session makes — it inherits the F99/F72 sender-domain question. Record the request; do not build it here.

**Coverage note:** this panel is new UI on a page with thin spec coverage. It needs a real-browser check (V6), not just a green suite.

### 4.6 The "Mark Fulfilled" relabel is a **decision gate, not a default**

The button is used to mean "ordered" (§ 2.4) while the code and the arrivals/shipment path treat `fulfilled` as arrival. Once a real order ledger exists these can finally be separated — but that changes what existing `fulfilled = true` rows mean, on production, in a live workflow.

> **PAUSE → Rick.** Present the options (repoint the button to write order state and let `fulfilled` revert to arrival-only; or leave `fulfilled` untouched and add the order mark alongside it) **with** a statement of what happens to existing `fulfilled = true` rows under each. **Do not choose unilaterally, and do not migrate existing rows without explicit approval.**

### 4.7 The feature is inert on day one unless the ledger is seeded

With an empty `order_submissions`, the duplicate check finds nothing and catches nothing — **and every reservation looks un-ordered, so § 4.5's panel will over-report backorder risk on first run.** The first real cycle after deploy is unprotected unless prior orders are loaded. Hence S5 — at minimum the June and July archived order files. Stated plainly here because it is the difference between shipping a safeguard and shipping the *appearance* of one.

---

## 5. Scope

### IN
- FOC-cycle selector + filtering on both exports (§ 4.1), with the held-back panel.
- `order_submissions` table + RLS + indexes (§ 4.2), staging then production.
- Duplicate surfacing at export time (§ 4.3).
- Ad-hoc flag + exclusion (§ 4.4).
- **Backorder-risk admin panel (§ 4.5)** — at-risk vs Backordered, in-app.
- The relabel decision (§ 4.6) — **presented**, applied only if approved.
- Backfill of archived order files (§ 4.7 / S5) — non-blocking.
- Closeout: § 13 F101/F102, `CLAUDE.md` § Open findings.

### OUT — stop and ask
- **Invoice reconciliation (F108).** Its own finding, its own session. Includes surfacing distributor rejections and the customer-facing consequence of a reservation pointing at a withdrawn title (F101's last open thread).
- **The reserved-titles report and the Paper Orders tab.** They stay month-scoped this session, which means they will **disagree with the export** — a known, accepted consequence, recorded in § 13 at closeout so it is not rediscovered as a bug. F101 flags the question; Rick scoped this session to the export path.
- **F90 / F89.** F102's fix direction suggests pairing with F90's import-time snapshot. Not here — one session, one scope.
- **F10** (`ON DELETE NO ACTION`). Untouched.
- **Pushed notifications (email/SMS) for backorder risk.** § 4.5 is in-app only; a push channel inherits the F99/F72 sender-domain question. Record the request, do not build it.
- **Changing the FOC lock itself** (`isFocPast` / `isFocLocked`, `app.js:1358–1370`). This session makes the lock *safer* by warning before it bites; it does not alter when it bites or the committed-cannot-cancel behaviour.
- **Changing `fulfilled` semantics or migrating existing rows** without the § 4.6 approval.
- **The import scripts.** No import-side change is needed; if one appears necessary, that is a finding, not a scope expansion.
- **`config.js`**, credentials, Edge Functions.

---

## 6. Runbook

### S0 — Pre-flight
1. `/preflight`. Read `CLAUDE.md` in full; confirm no active sub-deploy; re-read § Smoke-test ordering (**the Playwright suite tests the deployed site — a pre-push run cannot see your change**) and § SQL authoring rules.
2. Read this plan, then § 13 **F101, F102, F80, F85** and § 4.3 / § 4.4.
3. Re-read `admin.html` at every line range in § 3 and confirm they still match. Halt if not.
4. `/sql-check` before writing any SQL. `catalog` uses `price_usd`; the distributor enum is exact-case `Lunar` / `PRH`; every INSERT passes `tenant_id`.
5. Confirm next free finding ID (**F109** after F108 is filed by the planning session).

### S1 — Measure the real bands (read-only, informs the default only)
Intersect the archived order files in `Orders Archived/` against catalog `foc_date` values to see whether a stable band exists (the July sheet was 8/10–8/31 against a 7/24 deadline). **If a rule is evident, use it as the preselected default. If it is not, default to the earliest not-yet-passed FOC date and say so.** This step must never gate the fix, and must never widen the default beyond what the data shows. This is the same file-intersection method that found the 1-of-268 overlap in F102's sweep.

### S2 — Schema (staging)
1. Write `docs/sql/order-submissions.sql` — table, indexes, RLS policies (§ 4.2). Dry-fit against § 4 conventions before running.
2. > **PAUSE → Rick (staging SQL Editor).** Run it. Verify with a live SELECT that the table exists with the expected columns and that RLS is enabled.
3. **Gate V1** — tenant isolation, tested properly: inside a transaction, `SET LOCAL role authenticated` + `SET LOCAL "request.jwt.claims"` for a non-admin and for another tenant's admin, and confirm both are denied. **The SQL Editor runs as superuser and bypasses RLS — a plain SELECT proves nothing** (`CLAUDE.md` § Supabase platform facts). Note `feedback_supabase_sql_editor_set_local`: `BEGIN` + `SET LOCAL` + `ROLLBACK` has failed with 25P02 in this editor before; if it does, say so and use an alternative rather than declaring the gate green.

### S3 — Exports
1. Add the FOC-cycle selector and filtering (§ 4.1). Follow `admin.html:2161–2169` for null-FOC handling.
2. Add the held-back panel — every bucket in § 4.1's table, never a silent drop. **Backordered must be visually distinct from "outside selected cycle."**
3. Add the duplicate lookup and the "Already ordered" panel with per-title quantity control (§ 4.3). **Surface, never auto-suppress.**
4. Ad-hoc exclusion (§ 4.4).
5. **Gate V2 (inert-on-clean-slate):** with an empty ledger and all FOC dates selected, both exports must produce **byte-identical** output to the current build for the same data. This is the regression assertion that proves the change adds gates rather than altering the existing sheet.

### S3b — Backorder-risk panel (§ 4.5)
1. Build the admin-dashboard panel. **Reuse `isFocThisMonth()` (`app.js:1375+`) — do not reimplement the date logic** (§ 2.4; F28 is the precedent for why). Read `app_settings.order_deadline` via `Settings.getOrderDeadline()` (`app.js:624`) for the second trigger condition.
2. Render **At risk** and **Backordered** as visually distinct states, soonest-FOC first, Backordered on top. Show days remaining.
3. A code with any `order_submissions` row clears from the list.
4. **Gate V7 (backorder detection):** seed three staging reservations — (a) FOC later this month, unordered → **At risk**; (b) FOC already passed, unordered → **Backordered**; (c) FOC already passed **with** a ledger row → **absent**. All three must classify correctly. (c) is the one that proves the panel reads the ledger rather than only the date.

### S4 — The relabel decision
> **PAUSE → Rick** per § 4.6. Present both options and the consequence for existing `fulfilled = true` rows. Implement only what is approved; if deferred, say so plainly and leave the label alone.

### S5 — Seed the ledger (§ 4.7, non-blocking)
Load the archived June and July order files into `order_submissions` (`order_type = 'monthly'`, `submitted_on` from the filename date). **Count and show the rows before inserting**, per the F95 precedent — a bad backfill would suppress or misreport real titles on the next cycle. If this is not reached, **say so explicitly in the status update**, because § 4.7 means both the duplicate check and § 4.5's panel are unreliable until it happens.

### S6 — Verification
1. **Gate V3 (F101 reproduction):** seed a staging reservation whose FOC is two cycles out (the MIDNIGHT X-MEN #2 shape — `catalog_month` = current, `foc_date` ≈ +3 months). Assert it is **excluded** from the export and **appears** in the held-back panel under *outside selected cycle*.
2. **Gate V4 (F102 reproduction):** record a ledger row for a code, then seed the same code re-listed in a later `catalog_month` with fresh reservations. Assert the export **flags** it with prior quantity, date and cycle, and does **not** auto-suppress it.
3. **Gate V5 (ad-hoc):** mark a code `adhoc`; assert the monthly export excludes it and lists it as such.
4. `/deploy-staging`. **Push first, confirm the new bytes are served, then run the suite** — `CLAUDE.md` § Smoke-test ordering.
5. **Gate V6:** full `run-smoke.ps1` green **plus a real-browser check of the export UI and the § 4.5 panel**. Both are new UI on paths with no Playwright coverage — a green suite is not evidence here (`CLAUDE.md` § "Green is not the same as verified"; memory: `feedback_verify_css_visibility_real_browser`). Download both export files and inspect them; confirm the panel renders At risk and Backordered distinguishably, including at mobile width.
6. Tear down every seeded fixture; **verify with a live SELECT returning zero rows**, not "we ran the teardown."

### S7 — Closeout
1. Update § 13 F101 / F102 with what was actually done, and record the **accepted divergence** between the export and the month-scoped reserved-titles report / Paper Orders tab (§ 5 OUT).
2. Update `CLAUDE.md` § Open findings.
3. Doc + code commit to `staging`, `--ff-only`.
4. **Production promotion is Rick's explicit call** (`/promote-prod`). The realized cost exposure is on production, so raise it — but do not promote unasked.
5. `/wrap-up`.

---

## 7. Verification gates

| Gate | Assertion | Why this and not a weaker one |
|---|---|---|
| **V1** | RLS denies cross-tenant and non-admin access under a simulated `authenticated` role | The SQL Editor is superuser; a plain SELECT proves nothing |
| **V2** | Empty ledger + all cycles selected ⇒ **byte-identical** export to the current build | Proves the change adds gates rather than silently altering the sheet |
| **V3** | A two-cycles-out title is excluded **and** listed in the held-back panel | Exclusion alone would trade one silent failure for another |
| **V4** | A re-listed already-ordered code is **flagged with prior qty**, not auto-suppressed | Auto-suppression would have ordered 0 where 2 were correct |
| **V5** | An `adhoc` code is excluded from the monthly export and shown as excluded | § 2.3 — the second route to the same duplicate failure |
| **V6** | Full suite green **and** a real-browser check of both exports and the § 4.5 panel | Both are new UI with zero spec coverage |
| **V7** | At risk / Backordered / cleared-by-ledger all classify correctly | Proves the panel reads the ledger, not just the date |
| **V8** | § 13 + `CLAUDE.md` updated; plan committed to `staging` | Document Integrity |

---

## 8. Completion criteria

- [ ] § 3 line numbers re-verified against disk before any edit
- [ ] S1 band measurement run; default preselection stated as derived-or-not, never invented
- [ ] `order_submissions` live on staging with RLS; **V1** green by simulated-role test
- [ ] Both exports FOC-filtered with an explicit multi-select cycle; **V2** byte-identical on a clean slate
- [ ] Held-back panel shows every bucket in § 4.1's table; **Backordered visually distinct from "outside selected cycle"**; nothing dropped silently
- [ ] Duplicate surfacing live with per-title quantity control; **V4** confirms no auto-suppression
- [ ] Ad-hoc flag + exclusion live; **V5** green
- [ ] Backorder-risk panel live, reusing `isFocThisMonth()` rather than reimplementing it; **V7** green on all three states
- [ ] § 4.6 relabel decision **presented to Rick**; implemented only if approved, or recorded as deferred
- [ ] S5 backfill done — or its absence stated explicitly, with § 4.7's consequence repeated (the panel over-reports until it happens)
- [ ] **V3**/**V6**/**V8** green; all seeded fixtures torn down and verified by SELECT
- [ ] § 13 F101/F102 updated, incl. the accepted export ↔ reserved-titles-report divergence
- [ ] Production promotion raised with Rick (not performed unasked)

---

## 9. Rollback

- **Client:** `git revert` on `staging`. The exports are pure client code with no persisted state of their own.
- **Schema:** `order_submissions` is **additive** — nothing existing reads or writes it, so leaving the table in place is a safe rollback for the client change. Dropping it is only necessary if the design is abandoned.
- **Backfill (S5):** delete by `submitted_on` / `catalog_month`. Capture the inserted row list before inserting.
- **The § 4.6 relabel:** if approved and applied, this is the only genuinely hard-to-reverse piece, because it changes what `fulfilled` means to the humans using it. If it is applied, record the pre-change `fulfilled = true` row set first.
- **The § 4.5 panel** is read-only — it writes nothing and can be reverted with the rest of the client change.

---

## 10. Out-of-session operational item

**Independent of any code:** PRH holds **12 copies of `75960621668000111`** (MIDNIGHT X-MEN #1) against **7** reservations. FOC **2026-08-31**. The order was still adjustable downward at filing. **This is worth acting on before 8/31 regardless of when this plan executes** — the code fix prevents the next one, not this one.

Until the fix ships, F102's interim safeguard stands and needs no code: before submitting each cycle, intersect the new order file against the previous cycle's archived one.

```
comm -12 <(cut -d, -f1 prev.txt | sort -u) <(cut -d, -f1 new.txt | sort -u)
```

---

## References

- `docs/technical-reference.md` § 13 — **F101** (FOC window, live instance), **F102** (order state, confirmed 5-copy surplus, the 1-of-268 sweep), **F108** (invoice reconciliation — the follow-on), **F80** (the other catalog-month silent-wrong-month case), **F85** (cross-month duplicate reservations — same catalog-month/physical-title tension), **F90** (the import-time snapshot F102 suggests pairing with — deliberately not paired here), **F6** (`app_settings` PK is `(tenant_id, key)` on both environments since 2026-07-28).
- `docs/technical-reference.md` § 4.3 `catalog` (`foc_date`, the four-column upsert key that creates a new row on re-listing), § 4.4 `preorders`.
- `CLAUDE.md` § Smoke-test ordering; § "Green is not the same as verified"; § SQL authoring rules; § Supabase platform facts (SQL Editor is superuser); § Definition of Done.
- Live files: `admin.html`, `app.js`. Archived orders: `Orders Archived/prh-order-*.txt`, `lunar-order-*.txt`.
- Staging founding tenant `72e29f67-39f7-42bc-a4d5-d6f992f9d790`, project `puoaiyezsreowpwxzxhj`. Production `plgegklqtdjxeglvyjte`.
