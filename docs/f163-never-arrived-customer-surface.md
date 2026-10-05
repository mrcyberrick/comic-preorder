# F163 — A confirmed-terminal reservation keeps a lasting place on the customer's My List (design)

**STATUS:** IN PROGRESS — BUILT AND VERIFIED ON STAGING 2026-10-05 (`9fbb71b`, `mylist.html` only; harness 65/65 on the deployed bytes, full suite 156 passed, § 15); NOT promoted, pending Rick's validation on staging including approval of the copy; PLUS the admin "Clear" follow-up (`6583a6c`, § 16: harness 80/80 on the deployed bytes, full suite 158 passed), whose SQL is APPLIED on BOTH environments (production 2026-10-05, so step 0 no longer blocks on it) · staging=2026-10-05 · prod=— · PR=— · findings: F163 (advances; owner record in `docs/technical-reference.md` § 13). *(This token read "NOT STARTED — design written 2026-10-04 ... build next" until the build session.)*

Owner doc for the build of F163. **Design only: no app code, no SQL, no DB write, no deploy.** The only
database contact was a read-only, paginated, tenant-scoped service-role measurement on production
(§ 1). If Rick wants it built, that is a separate staging session against this doc (§ 9).

---

## 0. The premise F163 was filed on is half wrong, and that decides the design

F163 (filed 2026-09-29) says a never-arrived reservation is in **neither** My List section and
proposes "a third bucket." **That bucket already exists.** `c514c79` (2026-09-21, "surface
reservations the store confirmed will not arrive") added the **"No longer coming"** section
(`#unavailable-section`, `allUnavailable`, `renderUnavailable()` in `mylist.html`). It reached
production in **PR #159** (the 2026-09-29 full staging merge) and is served today on `pulllist.app`
and `rjbookstop.pulllist.app` (`unavailable-section` x3, `allUnavailable` x7, the open-only guard
x1, all read from the served bytes 2026-10-04). **No doc, § 13 entry or CLAUDE.md paragraph recorded
it**; a local harness (`mylist-no-longer-coming-verify.mjs`, staging, 323 lines) is its only coverage.

What it does, read from `mylist.html` on 2026-10-04: a stranded row (not in the current-month table,
not future-dated) appears in the section if it is **unfulfilled** and carries a human-confirmed
signal: `catalog.withdrawn_at`, a ledger code netting <= 0 (supplier-rejected), `arrival_outcome =
'not_arrived'` or `'damaged'`. **`if (i.fulfilled) return false;` was deliberate** (its comment, and
harness fixture F: "THIS FIXTURE EXISTS BECAUSE ITS ABSENCE SHIPPED A BUG"; the first cut selected 54
rows not 23, 31 of them closed rows, 24 cards on one list).

**The remaining gap is therefore narrower and different from the filing:** the section is a
**transient of about two weeks**. `auto_fulfill_past_on_sale()` closes a row ~14 days after on-sale
(F155 S3's bounded deferral, then the next weekly import), the row becomes `fulfilled = true`, and the
open-only guard drops it from the section **silently** — the same "visible only for a while, then gone
with no notice" shape the 2026-09-21 commit set out to fix for F120's badge. Every row the section
shows today is within 14 days of on-sale (§ 1.4); every confirmed row older than that is hidden.

Rick's decision (§ 2) is to **reverse the open-only rule for confirmed rows**, bounded by a window.
Everything below is an edit to the existing section, not a new surface.

## 1. Measured facts (production, read-only, 2026-10-04)

Method: service role, GET only, tenant-scoped (`IMPORT_TENANT_ID_PROD`), **paginated** (F139/F140;
`id` order, offset/limit 1000), each fetch checked against `Prefer: count=exact`. Keys never printed.
Local-only scripts: `playwright/f163-stranded-measure.mjs` and `playwright/f163-stranded-accounts.mjs`
(gitignored; re-run at build, § 9 B1). If they are lost, § 4's predicate and this method rebuild them.
Columns were taken from `technical-reference.md` § 4.3/4.4/4.9/4.11 and § 6.8 and **proven by the
select succeeding**: § 4.4's `preorders` table does not list `arrival_outcome`, which `Preorders.getMy`
selects and the live table carries (a stale doc line, not touched here).

**Written down before running (so a surprise triggers re-verification):** parts sum to the total; the
stranded count >= 1,602; "shown today" 0-3 rows; hidden-confirmed >= 15. **All held except "shown
today", which read 5** (the 09-29 grid had 3 open-`unknown` rows; two more rows passed on-sale since,
all five are ledger-rejected and within 14 days — explained, not a defect).

### 1.1 The universe, and the F163 set re-counted

| | 2026-09-29 (F163) | **2026-10-04** |
|---|---|---|
| Production preorders (fetched = exact count) | 3,494 | **3,573** (0 without a catalog row) |
| `order_submissions` rows (fetched = exact count) | n/a | 2,019 |
| Stranded: not in main table, not future-dated | 1,602 | **1,740** (page predicate = F163 predicate; 0 with NULL `on_sale_date`) |

Stranded `fulfilled` x `arrival_outcome` — **parts sum to 1,740 (OK)**:

| fulfilled / outcome | 09-29 | 10-04 |
|---|---|---|
| true / NULL | 939 | 940 |
| true / `arrived` | 621 | 754 (+133: the 10-02 shipment import) |
| true / `unknown` | 24 | 26 |
| true / `not_arrived` | 15 | 15 |
| false / `unknown` | 3 | 5 |
| **total** | **1,602** | **1,740** |

F163's "customer-relevant" count (outcome in `not_arrived`/`unknown`/`damaged`): **46 rows / 40
titles** (by `catalog_id` and by code both 40) against 42 / 36 on 09-29. By `catalog_month`:
2026-03 6, 04 4, 05 5, 06 12, 07 19 (= 46). `damaged` is still 0. Tenant-wide, for context:
F/NULL 1,823 · F/`unknown` 5 · T/NULL 950 · T/`arrived` 754 · T/`not_arrived` 15 · T/`unknown` 26 = 3,573.

### 1.2 What the shipped section shows today, and what it hides

| | rows |
|---|---|
| **Shown today** (unfulfilled AND confirmed) | **5**, all `unknown` + ledger-rejected, 5 customers, 1 each |
| **Confirmed but hidden because `fulfilled = true`** | **45** |
| of which supplier-rejected (ledger net <= 0): outcome `unknown` 26 + NULL 2 + **`arrived` 2** | 30 |
| of which `not_arrived` (no other signal) | 15 |
| `catalog.withdrawn_at` anywhere in the stranded set | 0 |
| `unknown` rows with **no** confirmed signal | **0** |

Two things in that table drive decisions. (1) **All 31 stranded `unknown` rows are also
supplier-rejected** (26 fulfilled + 5 open), so they already read "Rejected by the supplier," never
"Did not arrive." The 26 rows F115's S6 backfill wrote were **all later resolved by an admin** (12
`arrived`, 14 `not_arrived`); none is `unknown` any more. The 31 current `unknown` rows were written
by import auto-fulfil (`fulfilled_at`: 08-20 x2, 08-28 x4, 09-04 x6, 09-27 x12, 10-02 x2, plus the 5
still open). (2) **Two rows are ledger-rejected AND `arrival_outcome = 'arrived'`** (one title, two
accounts): shipment evidence says it arrived while the ledger nets <= 0. Telling a customer "Rejected
by the supplier" about a book that arrived would be false, so they are excluded (§ 4).

### 1.3 Who, per account (the proposed rule, 180-day window — § 4)

**48 eligible rows across 10 accounts** (45 hidden-confirmed - 2 contradiction rows + 5 shown today).

| account kind | section rows now -> proposed | open / fulfilled | main-table rows | upcoming | empty main list |
|---|---|---|---|---|---|
| real customer | 1 -> **9** | 1 / 8 | 29 | 104 | no |
| real customer | 1 -> **8** | 1 / 7 | 21 | 73 | no |
| real customer | 1 -> **4** | 1 / 3 | **0** | 123 | **YES** |
| real customer | 1 -> **2** | 1 / 1 | 26 | 63 | no |
| real customer | 1 -> **1** | 1 / 0 | 5 | 18 | no |
| admin (Rick's own account) | 0 -> **14** | 0 / 14 | 2 | 1,113 | no |
| paper (no login) x4 | 0 -> 5, 3, 1, 1 | 0 / 10 | 3, 4, 0, 0 | | 2 of 4 |

Real customers: **5**; with 1-3 main rows (F161's trigger range): **0**; with 4+: 4; with an **empty
main list: 1**. The worst single real-customer list is **9 cards**. (The 2026-09-21 first cut put "24
cards on a single list" per the harness comment; which account that was is not recorded, so that
rationale is cited, not reproduced.)

### 1.4 Age since on-sale, and what a window would do

| | 0-14d | 15-30d | 31-60d | 61-90d | >90d |
|---|---|---|---|---|---|
| shown today (5) | 5 | | | | |
| hidden-confirmed (45) | 0 | 14 | 17 | 2 | **12** (oldest **151 d**) |

Window effect on the 48 eligible rows (real-customer rows in brackets): 60 d 34 (13) · 90 d 36 (15) ·
120 d 39 (17) · **180 d 48 (24)** · none 48 (24). The 12 rows older than 90 days are all
did-not-arrive rows: 9 on real customers, 2 on your account, 1 on a paper account. Across all ages the
**15 `not_arrived` rows** are 11 on **3 real customers** (aged 81-151 d), 3 on your account and 1 on a
paper account: **those customers have never been shown anything about a title that never came, since
May.**

### 1.5 G0 re-measure at build (2026-10-05, read-only, production, GET only; § 9 B1)

Both local scripts re-run unchanged (`f163-stranded-measure.mjs`, `f163-stranded-accounts.mjs`; every fetch equals its
exact count: 3,573 `preorders`, 2,019 `order_submissions`; 0 preorders without a catalog row). **Halt conditions
checked and none tripped:** parts sum **1,740 = 1,740 (OK)**; eligible rows **48** (exactly the § 1.3 figure, so no
drift to explain); **withdrawn rows in the stranded set: 0** (so K, Remove-on-fulfilled-withdrawn, is still proven by
the harness only); `unknown` rows with no confirmed signal **0**. Shown today **5**, hidden-confirmed **45** (26 + 2 + 2
supplier-rejected, 15 `not_arrived`), 10 accounts (5 real customers), per-account section rows 14 / 9 / 8 / 5 / 4 / 3 / 2 /
1 / 1 / 1 (account kinds as § 1.3: admin 14, paper x4, real customers 9 / 8 / 4 / 2 / 1). Age of the 45 hidden rows:
15-30 d 14, 31-60 d 16, 61-90 d 3, **> 90 d 12**. Real customers: **1 with an empty main list**, 0 with 1-3 main rows, 4
with 4+. **Every figure the design rests on is unchanged from 2026-10-04**; it is the same population one day on.

## 2. Rick's decisions (2026-10-04, via AskUserQuestion; recommendation taken on every one)

| # | Question | Answer | Measured basis |
|---|---|---|---|
| R | Reverse the shipped open-only rule for confirmed rows? (this subsumes Q4: do aged-out supplier-rejected titles belong in the section) | **Yes: show all confirmed rows** (withdrawn, supplier-rejected unless the row also says `arrived`, did-not-arrive, damaged) | 45 hidden: 30 rejected + 15 not-arrived (§ 1.2) |
| Q1 | Show outcome `unknown`? | **No: keep it staff-only** (F134 § 4.3's rule stands) | 0 `unknown` rows lack a confirmed signal (§ 1.2); costs nothing today |
| Q2 | How long does a confirmed row stay? | **180 days after the on-sale date** | Shows all 48 eligible rows today; 90 d would hide the 12 oldest, which nobody has been shown (§ 1.4) |
| Q3 | Where does the section sit? | **Move it below the main list** | Today it is a `display:none` block above the list, F161's shift mechanism (§ 7) |
| Q5a | Printed My List | **Leave the section off the paper** | By CSS reading it prints today (§ 8); not rendered |
| Q5b | Admin impersonation | **Show it, as today** | 10 rows on paper accounts and 14 on Rick's own are readable only this way |
| X | Remove for fulfilled rows (cancel-path exception)? | **No: informational only** | `Preorders.cancel` refuses fulfilled rows; F109's trigger refuses did-not-arrive rows still netting > 0 |

## 3. Scope

**IN:** `mylist.html` only — the `allUnavailable` predicate, `renderUnavailable()` (Remove rule, chip
wording), the section's markup position and intro note, one print rule; a window constant; a local
harness extension and local spec; § 13 F163 and the CLAUDE.md row.

**OUT (stop and ask):** `app.js` (no query or helper change is needed, § 5), `Preorders.cancel()` and
any delete path (the F109 boundary), any DB write or schema change, a bare-`unknown` customer state
(Q1), a customer dismiss control, admin surfaces (Order Follow-Up's resolve control is cited, § 11),
F161's own fix (cited as a constraint only), `arrivals.html`, email or push notification, the main
table / Upcoming Arrivals / mobile-card render chains.

## 4. The bucket rule, as one predicate

```
visibleTerminal(row) :=
      row.catalog IS NOT NULL
  AND NOT inMainTable(row)        -- catalog_month = current month        (unchanged)
  AND NOT inUpcoming(row)         -- on_sale_date >= today                 (unchanged)
  AND ( on_sale_date IS NULL OR on_sale_date >= today - 180 days )         -- NEW (Q2)
  AND terminalSignal(row)

terminalSignal(row) :=
      catalog.withdrawn_at IS NOT NULL
   OR arrival_outcome IN ('not_arrived', 'damaged')
   OR ( ledgerState(code) = 'unavailable' AND arrival_outcome <> 'arrived' )   -- NEW exclusion
```

**Three changes against the shipped predicate (`mylist.html` ~:1009-1030):** (1) the
`if (i.fulfilled) return false;` guard is **removed** (R); (2) the 180-day window is **added** (Q2);
(3) `arrival_outcome <> 'arrived'` is **added to the ledger arm** (the 2 contradiction rows). An
undated row cannot be aged and is **kept** (measured 0 today; failing visible beats failing silent).
Dates are local-date strings: `DateUtils.fmtLocal()`/`todayLocal()` (F28: never `toISOString()`);
the cutoff is today minus 180 via `setDate`, compared as `'YYYY-MM-DD'` strings, held in one named
constant with its reason.

**Truth table** (every `fulfilled` x outcome x ledger x withdrawn combination that exists or can):

| fulfilled | outcome | ledger | withdrawn | within 180 d | in section? | card copy | Remove? |
|---|---|---|---|---|---|---|---|
| no | any | rejected | no | yes | yes | Rejected by the supplier | **yes** (unchanged) |
| no | `not_arrived`/`damaged` | any | no | yes | yes | Did not arrive / Arrived damaged | no |
| no | any | any | yes | yes | yes | Withdrawn by the distributor | yes |
| **yes** | `not_arrived`/`damaged` | any | no | yes | **yes (new)** | Did not arrive / Arrived damaged | no |
| **yes** | `unknown` or NULL | rejected | no | yes | **yes (new)** | Rejected by the supplier | **no** |
| **yes** | `arrived` | rejected | no | yes | **no (the contradiction)** | — | — |
| **yes** | `unknown` | none / ordered | no | yes | **no (Q1)** | — | — |
| yes | `arrived` or NULL | none / ordered | no | yes | no | — | — |
| **yes** | any | any | yes | yes | **yes (new)** | Withdrawn by the distributor | **yes** |
| any | any | any | any | **no (older)** | no | — | — |

**Remove rule** (replaces `canRemove = isWithdrawn || isRejected`): `canRemove = isWithdrawn ||
(isRejected && !item.fulfilled)`. It must mirror what the server and `Preorders.cancel()` permit, or
the button renders and the click fails with a misleading message: `Preorders.cancel` refuses a
**fulfilled** non-withdrawn row ("the order for this item has already been placed") and F109's
trigger refuses any code netting > 0. A withdrawn row is exempt from both (F110).

**Copy** (proposed, **Rick approves at build**): the non-removable chip keeps "⚠ Contact store" but its
`title` changes from *"The store has this on order — contact them"* (false for a supplier-rejected row)
to *"Confirmed by the store — contact them with questions"* (the main table's own chip wording). The
section intro note ("The store confirmed these will not arrive. Removing one only clears it from your
list…") is wrong for did-not-arrive/damaged rows and for rows with no Remove; proposed: *"The store
has confirmed these will not be coming to you. Where there is a Remove button it only clears your
list; otherwise contact the store with any questions."*

## 5. Query changes: none (proved, not assumed)

`Preorders.getMy()` (`app.js` ~:1624) already selects every column the predicate reads
(`fulfilled`, `fulfilled_at`, `arrival_outcome`, and from `catalog`: `catalog_month`, `on_sale_date`,
`withdrawn_at`, `distributor`, `item_code`, `upc`, `isbn`), is **paginated** by `fetchAllRows()`
(F139/F140, ordered `created_at` then `id`), and is scoped by `.eq('user_id', …)` plus RLS tenant
scope. `getOrderedCodes()` is paginated (F162). The window and the arrival exclusion are client-side
filters over rows already in memory. **No new request, no RPC, no `app.js` edit.** Impersonation
resolves through `AdminContext.resolveUserId()` exactly as the existing section does.

## 6. Render plan (reuse; edits only)

Anchors re-read 2026-10-04 (line numbers drift: re-read before editing).

| Where (`mylist.html`) | Change |
|---|---|
| `#unavailable-section` markup (~:641-661) | **Move** below `#list-container` (~:684-691), above the print footer; update the intro note |
| `allUnavailable` predicate (~:1009-1030) | § 4 |
| `renderUnavailable()` `canRemove` (~:1574) and chip (~:1594) | § 4 Remove rule and chip title |
| comment above `renderUnavailable()` (~:1512-1535) and the guard's comment (~:1012-1018) | **Rewrite, keeping the old wording visible as superseded** (the fulfilled exclusion was a recorded decision, now reversed by Rick 2026-10-04) |
| `@media print` (~:273-321) | add `#unavailable-section` to the hidden list (Q5a) |
| `loadList()` end (~:1031-1032) | `renderList(); renderUnavailable();` stay adjacent and synchronous (§ 7) |

Card markup, the short labels, the fade-in loop, the own-handler Remove (not the main list's
`.cancel-btn` wiring) and the `UsageEvents.cancel` call are **unchanged**. Precedence of copy stays
withdrawn -> rejected -> not_arrived -> damaged, identical to the main table, so a row cannot describe
itself one way here and another there.

## 7. Layout rule (F141 / F161): nothing may be inserted above content that is already visible

- F161's mechanism: a `display:none` section that sits **before** `#list-container` pops in above it
  while the list's 100vh placeholder (F141) collapses, shifting the page (0.46 desktop CLS for a 1-3 row
  account). The shipped section is exactly that shape. **Q3: move it below the list**, so the list
  never moves for it.
- **Do not add a `min-height` reservation for it.** F141 measured that reserving more scored worse
  (Pattern B: a slot reservation on top made subscriptions 0.33 -> 0.55). It stays `display:none` until
  it has content.
- Write it in the **same synchronous tick** as the list (`renderList(); renderUnavailable();`, no
  `await` between; a comment must forbid adding one), so list and section appear in one paint.
- **A known wrinkle, found by measurement (§ 1.3), not covered by the Q3 answer:** when a customer's
  main list is **empty**, `renderList()` keeps the F141 `.loading-reserve` hold (a full viewport) on the
  empty-state block (measured: dropping it scored 0.613 -> 1.048). A section placed after it starts
  **a screen down**. **1 of 5 real customers and 2 paper accounts are in this state today.** Default:
  accept it. If the harness (§ 10 V9) puts the section more than ~1.5 viewports from the top, the
  fallback is to emit the section inside the same synchronous write, **before** the empty-state hold,
  for the empty branch only. That edits the empty-state hold, which has regressed before: **stop and ask
  Rick** rather than choosing at build.
  **MEASURED AT BUILD 2026-10-05 (harness PV9), and the trigger FIRED:** for a non-impersonated customer
  with an empty main list and 3 section rows, the section's top is **2,246 px = 2.39 viewport heights on
  desktop (1350x940) and 3,476 px = 4.22 on a phone (412x823)**. It sits behind the full-viewport hold
  **and** the 24-cover "New #1 issues" discovery grid that `renderList()` loads into the same container
  for an empty, non-impersonated list. **Stopped and asked Rick; ANSWERED: accept, the section stays below
  the list for everyone** (alternatives offered and not built: above the list for the empty branch only;
  inside the empty-state block, above the discovery grid). **Not measured:** the impersonated empty-list
  case (the 2 paper accounts with an empty main list, readable only by impersonation), which skips the
  discovery grid and so should land nearer 1.5 viewports; that is an inference from the code, not a reading.
  Cost accepted: the one real customer with an empty main list (4 rows) reads their "No longer coming"
  notice about two screens down instead of at the top.
- The count badge, open-by-default and chevron toggle are unchanged.

## 8. Mobile, print, impersonation

- **Mobile (<= 640 px):** the section is a flex-wrap grid of 100 px cards and already renders at 390
  px (harness V12, no horizontal scroll). A 9-card list is about three rows. The chip must still fit its
  card (harness V7e: the shipped bug where it overflowed).
- **Print (Q5a):** by reading `style.css` and `mylist.html`, no print rule hides `.month-arrivals`
  (only `.btn`, `.qty-btn`, `.cancel-btn`, `.my-subs`, the toolbar and a few more), and the section is
  open by default, so **it already prints**, as covers and titles without buttons. **Not rendered:
  that is inferred from the CSS.** Add `#unavailable-section` to the existing `@media print` hidden list
  (the printout is the pickup-and-pay list; `.my-subs` is already hidden there). Gate V6 measures it.
- **Impersonation (Q5b):** unchanged. `AdminContext` is `sessionStorage` `admin_ctx_id` /
  `admin_ctx_name`; the section shows the customer's rows and Remove acts as the customer only where the
  server allows it. For the 4 paper accounts (10 rows) and Rick's own account (14) this is the only place
  the notice can be read.

## 9. Build plan (a separate staging session; Sonnet CLI; promotion only on Rick's `/promote-prod`)

- **B0.** `/preflight`; `git switch staging`; `git branch --show-current` (the bare ref is ambiguous);
  feature branch from `refs/heads/staging`.
- **B1. Re-measure before building** (G0): re-run both local scripts; record the date and numbers here.
  Halt if the parts do not sum, if "eligible rows" differs from 48 by more than the plausible drift (a
  few rows a week in, a few out at 180 days), or if a **withdrawn** row now appears (0 today, so the
  Remove-on-fulfilled-withdrawn path is untested by production data).
- **B2. Harness first, against the CURRENT staging bytes** (the natural negative control, the F155 V9
  technique): extend `mylist-no-longer-coming-verify.mjs` with § 10's fixtures; the new assertions must
  go **RED** on today's code, with the failure being the assertion, not a crash.
- **B3.** Implement in `mylist.html` only. Serve the working tree into the real staging page with
  `page.route` + `route.fetch()` (F166's method) and run the harness green **before** pushing.
- **B4.** Per-assertion negative controls (§ 10), each observed red, each reverted byte-identically
  (sha256 before and after).
- **B5.** Push; confirm the new bytes on the **plain** URL (not cache-busted); harness against the
  deployed bytes; full Playwright suite once (baseline **151 passed**, ~21-24 min; read the log's own
  `N passed` line, never the launcher's exit notice); teardown re-read.
- **B6.** Update § 13 F163, the CLAUDE.md row, this doc's STATUS; `/wrap-up`.
- **Rollback:** revert the one commit. No schema, no data, nothing written to production.
- **Stop and ask Rick:** the empty-list fallback (§ 7), the copy (§ 4), and any request to touch
  `Preorders.cancel`. (§ 13 item 1, the resolve control's confirm/undo, is **answered: do not add it**.)
- **Promotion is gated on Rick validating the build on staging** (his instruction, 2026-10-04). The
  build session ends at B6 with the work on staging and the harness/suite results recorded; it does
  not open a production PR.

## 10. Tests and negative controls

The Playwright suite is gitignored, so **nothing in git asserts any of this** (stated plainly, same as
F141/F166). Evidence is a **local harness**, plus a **local spec** so the full-suite run covers it.
Nearest neighbours: `mylist-no-longer-coming-verify.mjs` (extend it), spec 15 (ledger fixtures, "Order
placed"), spec 21 (`arrival_outcome` resolve controls), spec 23 (the bounded arrival guard), spec 03
(cancel guards). **Every new fixture is seeded on staging with a `PWNLC_` prefix and torn down; teardown
is re-read** (0 auth users, 0 profiles, 0 catalog rows, 0 ledger rows, 0 preorders).

Fixtures (A-E exist; **F flips**; G-N are new). Window rows use 170 / 190 days, **not** 179 / 181, so a
midnight race cannot make a boundary row flaky.

| Fixture | Expected | Replaces / guards |
|---|---|---|
| A-E | unchanged | existing V1-V5b |
| **F** fulfilled + `not_arrived` | **shown, no Remove, new chip title** | was V5c "must NOT appear": **inverted deliberately, cite Rick 2026-10-04** |
| G fulfilled + ledger-rejected + `unknown` | shown, **no Remove**, "Rejected by the supplier" | the 26-row production population |
| H fulfilled + ledger-rejected + `arrived` | **hidden** | the 2 contradiction rows |
| I fulfilled + `unknown`, no ledger, not withdrawn | **hidden** | Q1 |
| J fulfilled + `arrived` only | hidden | control |
| K fulfilled + withdrawn | shown, **Remove offered AND deletes** | `Preorders.cancel`'s withdrawn exemption |
| L not_arrived at -170 d / M at -190 d | shown / **hidden** | the window |
| N undated stranded + `not_arrived` | shown | undated rule |

## 11. Verification gates (each looks DIFFERENT on failure)

| Gate | Assertion | Failure signature |
|---|---|---|
| G0 | Re-measure (B1): parts sum; eligible ≈ 48 | a printed `DOES NOT SUM, HALT` or a count off by > drift |
| V1 | Every fixture shows/hides per § 10 | named `FAIL` line per fixture; **F, G, K, L red on today's bytes** |
| V2 | **Remove**: open rejected deletes the row (read back); G/F have **no** `.cancel-btn-unavailable`; server refuses a direct delete on the net > 0 row | a surviving row, or a present button |
| V3 | Count badge = rendered cards | `3 != 5` style mismatch |
| V4 | DOM order: `#list-container` precedes `#unavailable-section` (`compareDocumentPosition`) | `false` on today's bytes (the section is above) |
| V5 | **Layout shift**: seed an account with 4+ main rows and 5 confirmed fulfilled rows; browser layout-shift entries, desktop 1350x940 and mobile 412x823; CLS with the section within **0.01** of the same account without it | a CLS jump > 0.01. **Control:** the pre-move bytes with OPEN confirmed rows (the only kind they show) on the same shape; expected higher, so measure it rather than assume it |
| V6 | `emulateMedia({media:'print'})`: section computed `display: none`; on screen visible | computed `block` in print |
| V7 | Impersonation: set `admin_ctx_id`/`admin_ctx_name` as an admin; section lists the customer's rows | empty section or the admin's own rows |
| V8 | Mobile 390 px: no horizontal scroll; the chip fits its card | `scrollWidth > clientWidth` |
| V9 | Empty-main-list customer: record the section's top offset in viewport heights (§ 7 trigger) | a recorded number, not a pass/fail |
| V10 | No console or page errors; teardown leaves zero rows (re-read) | `N left` |
| V11 | Full suite 151 passed, 0 failed, from the log's `N passed` line | the line's absence = **not trustworthy** |
| V12 | **Production, after Rick promotes:** served bytes (positive: the window constant and the arrival exclusion; **negative: the old `if (i.fulfilled) return false` x0**) on both hostnames; a read-only service-role replay of § 4 equals § 1.3's per-account counts; **Rick opens his own My List and the count equals his replay row (14 today)** | a mismatch between replay and the page |

**Per-assertion negative controls** (each in a scratch copy served via `page.route`, observed red,
original untouched): restore the `fulfilled` guard (F, G red); drop the window (M red); drop
`!== 'arrived'` (H red); drop `!item.fulfilled` from `canRemove` (G's no-Remove red); remove the print
rule (V6 red); put the markup back above the list (V4 and V5 red).

## 12. Production blast radius, day one (numbers re-measured at build, § 9 B1)

**0 customers newly see the section** (all 5 already have it, 1 row each). **4 of the 5 get more cards**
(1 -> 9, 8, 4, 2; the fifth stays at 1): **+19 rows**, worst **9** cards. **Rick's own account goes 0 ->
14.** **4 paper accounts** (10 rows) change only through impersonation. **24 customer-visible rows
total** (from 5). Nothing is written. Printed lists lose a block that has been printing.

## 13. Residuals and items raised for Rick (items 1 and 2 ANSWERED 2026-10-04; the rest are notes, not decisions)

1. **The resolve control has no confirm and no undo** (recorded as a residual of PR #154 on
   2026-09-21 and never filed). Until now a mis-click on "Didn't arrive" for a stranded row changed
   nothing a customer could see. **After this build it tells the customer "Did not arrive" for up to 180
   days with no way to take it back.** Raised: does the build wait for an F143-style confirm on that
   control? Not scoped here and **no ID consumed** (F170 stays next free); it is the same gap, with a
   larger consequence. **ANSWERED (Rick, 2026-10-04): no. The build does NOT wait for a confirm or
   undo and does not add one.** Rick accepts the exposure above knowingly; it stays unfiled and
   unscoped. A build session must not add a confirm to the resolve control "while it is there".
2. **No customer is told proactively.** The section is read on the next visit. The 3 real customers
   with did-not-arrive rows (11 rows, 81-151 days old) learn nothing until the build ships, and then
   only if they open My List. Telling them in person is available today and costs nothing.
   **ANSWERED (Rick, 2026-10-04): no. No in-person notice now;** the section is how they find out.
3. **The 180-day window is a tunable, not a finding:** one constant. The expiry is silent, like the
   14-day one it replaces, just much later.
4. **`damaged` sits under a heading ("No longer coming") that fits it badly** (it arrived). Pre-existing
   in the shipped section; the proposed intro note softens it; not redesigned.
5. **Withdrawn rows:** 0 in the stranded set today, so K (fulfilled + withdrawn deletes) is proven by
   the harness only, never by production data.
6. **Reversal on record:** the 2026-09-21 open-only rule was a deliberate choice with a recorded
   rationale (54 vs 23 rows, 24 cards on one list). Rick reversed it knowing today's numbers (worst real
   customer 9, § 1.3). If the data later grows past that, the 180-day constant is the lever.

## 14. Completion criteria (for the BUILD; ticked 2026-10-05 except Rick's validation and the promotion)

- [x] G0 re-measure recorded in this doc (§ 1.5, 2026-10-05: parts sum, 48 eligible, 0 withdrawn)
- [x] harness extended; the new assertions observed **RED** on the pre-change bytes (§ 15: 20 named failures, 0 crashes)
- [x] implemented in `mylist.html` only; `git diff --stat` shows one code file (`9fbb71b`, +80/-39)
- [x] every § 10 negative control observed red, then reverted byte-identically (§ 15: 6/6; repo file sha256 unchanged)
- [x] harness green on the working tree AND on the deployed staging bytes; V5 numbers recorded (§ 15)
- [x] full suite: 156 passed, 0 failed (from the log's own line; 151 baseline + 5 new local-spec tests, which reconcile exactly); teardown re-read (§ 15: nothing of this session left; August F130 leftovers untouched)
- [x] § 13 item 1 answered (Rick 2026-10-04: no confirm/undo, do not wait) and item 2 answered (no in-person notice)
- [x] Rick validated the build on staging, including approving the copy (§ 4). **2026-10-05: Rick looked at the staging demo account (including the admin Clear) and said "Demo looks good - can clear"; when asked to approve the copy explicitly (the section note and the chip hover text, quoted to him) he answered "yes".** The demo account was torn down at his word and re-read as 0 rows. **Not covered by his words: a real phone, and the empty-main-list case (he had already accepted that placement).** The "No longer coming" copy as approved: note "The store has confirmed these will not be coming to you. Where there is a Remove button it only clears your list; otherwise contact the store with any questions."; chip title "Confirmed by the store — contact them with questions".
- [ ] `/promote-prod` only on Rick's explicit request after that validation; V12 recorded
- [x] § 13 F163, the CLAUDE.md row and this STATUS token advanced (2026-10-05, build session)

## 15. Build record (2026-10-05, staging only; the evidence behind § 14)

**Code:** `9fbb71b`, `mylist.html` only (+80/-39; pushed, served bytes byte-identical to the commit, sha256 prefix
`9923c2cb7f81a856`, confirmed on the plain URL). `docs/` and the local harness/spec are separate. No `app.js`, query,
schema, RLS or SQL; nothing written to production (B1's measurement was GET-only).

**Harness** (`mylist-no-longer-coming-verify.mjs`, local-only; the original is kept in the build session's scratch):
- **B2, pre-change bytes:** 20 named assertion failures and no crash; the plan's required RED set (F, G, K, L, the
  DOM-order check) all red, and the pre-existing V1-V14 baseline still green. The layout-shift gate's vacuous-pass guard
  (the section must render 5 cards) went red too: **on the old bytes "with" equals "without" trivially**, so without that
  guard PV5 would have passed on code that does nothing.
- **B3/B5, working tree and deployed bytes:** green on both; the deployed run is **65 PASS / 0 FAIL** (its own final line).
- **Fixtures G-N** behave per § 4's truth table, and **Remove on a fulfilled WITHDRAWN row genuinely deletes it** (K,
  read back from the database), while the server still refuses the net > 0 row (V8c).
- **PV5 layout shift** (Lighthouse-like throttling, 3 runs each, 5 main-table rows so the account stays out of F161's
  1-3-row range): with the section **0.006 desktop / 0.005 mobile**, identical to without. **Control, 5 OPEN confirmed rows
  (what the old bytes can show): pre-move bytes 0.131 desktop / 0.202 mobile, the same rows below the list 0.006 / 0.005.**
  So the section's old position cost about 0.125 / 0.197 of CLS, which is F161's mechanism measured directly.
- **PV9** is recorded in § 7.

**Negative controls** (each a single edit to a scratch copy served via `--serve=file:`, the edit asserted to match once,
the harness required to exit 1 with no crash; the repo file's sha256 `76c36dfea9a3faa8` identical before and after):
1 restore the `fulfilled` guard -> F, G, K, L, N red; 2 drop the window -> M red; 3 drop the `arrived` exclusion -> H red;
4 drop `!item.fulfilled` from `canRemove` -> the G no-Remove check red; 5 remove the print rule -> PV6 red; 6 put the
markup back above the list -> PV4, PV4b and both PV5 checks red (**CLS 0.133 / 0.210 against 0.006 / 0.005**).

**Full suite:** `npx playwright test --reporter=line` run directly, **156 passed (23.5 min)**, 0 failed, from the log's own
line. **Local spec** `25-mylist-no-longer-coming.spec.ts` (5 tests) is the part of this that the suite covers from now on;
it does not cover PV5, PV7 or PV9, which stay in the harness. Neither is committed (the suite is gitignored), so
**nothing in git asserts any of this**, same as F141 and F166.

**Spec sweep before pushing:** no spec referenced the section; every fulfilled seed in specs 03, 15, 21 and 22 is either a
current-month row (main table, excluded by the `inMainTable` test) or an `unknown`/`arrived` row with no confirmed signal,
so none could newly surface.

**Teardown re-read from the database (not the suite's own claim):** 0 `PWNLC_` catalog, ledger, preorder, profile or auth
rows; 0 auth users or profiles created since the suite started (excluding the intended `pw-pending` survivors, F64);
`catalog_filters` restored to its original 167 bytes. **Not zero, and not this session's:** one `TEST_PW_` catalog row and
its preorder (`PW-ISO-B-1786504586132`, created 2026-08-12 by the tenant-isolation fixtures) and the **four August
`pw-*` synthetic tenants** that CLAUDE.md already records as F130 territory. Left alone, per F130's own "classify first".

**Stated plainly.** (1) **Chromium only**, not WebKit, not a real phone. (2) The layout-shift numbers are a synthetic
profile on staging data, not Lighthouse and not production. (3) The copy (§ 4) is **proposed, not approved**: Rick approves
it as part of his staging validation. (4) § 4's truth table writes "Did not arrive" for fulfilled + `not_arrived` with ledger
"any"; the code's precedence (withdrawn -> rejected -> not_arrived -> damaged, identical to the main table) gives "Rejected
by the supplier" when the ledger also nets <= 0. No fixture and no production row exercises that overlap; the precedence
rule, not the table cell, is what governs. (5) **For V12 after promotion:** the plan's negative marker "the old
`if (i.fulfilled) return false` x0" cannot be used literally, because the explanatory comment now quotes it (it reads x1 in
the served bytes, as does the old chip title `The store has this on order`). Check the **statement** form instead: a line
matching `^\s+if \(i\.fulfilled\) return false;` must read x0 (it does on staging today). (6) Rick has **not** validated.

## 16. Addendum: an admin can CLEAR a card (Rick, 2026-10-05). BUILT AND VERIFIED ON STAGING 2026-10-05; NOT promoted

**The ask.** Rick, looking at the staging demo: "can the admin clear it from the list if they contact the store?" Measured
answer: **not from the app today**, except Remove on withdrawn and open-rejected cards. The section's Remove calls
`Preorders.cancel()`, which has no admin bypass (it refuses a fulfilled non-withdrawn row and an ordered code), and
`admin.html` has no delete-reservation action (Mark Fulfilled was removed). The fulfilled did-not-arrive and fulfilled
rejected cards could only age out at 180 days. The database would allow an admin delete (the F109 trigger exempts
admins; `admins manage tenant preorders` is ALL), but that deletes the only record of what the customer was promised.
**Rick chose a hide flag: "option 2 please".**

**Schema:** one additive nullable column, `preorders.unavailable_dismissed_at timestamptz`; no default, no backfill, no RLS
change, no `app.js` change. **The SQL is `docs/sql/2026-10-05-preorders-unavailable-dismissed.sql`** (moved out of this doc
into `docs/sql/` once the client that depends on it reached staging; the block that used to sit here was extracted from this
doc byte-for-byte, so what Rick ran is what that file holds). **STATUS: `staging=APPLIED 2026-10-05 | prod=APPLIED 2026-10-05`**. While it read `prod=PENDING`,
`/promote-prod` step 0 blocked, which was the intended gate: without the column the Clear button does nothing on production. It was NOT committed under `docs/sql/` while the client was unbuilt, because a `prod=PENDING`
file blocks every promotion (the F157 session's reasoning).

**Applied on staging by Rick, 2026-10-05.** Pre-flight: `already_present` 0, 10 existing `preorders` columns; policies
present: `admins manage tenant preorders` (ALL), `users manage own preorders` (ALL), plus F127's two RESTRICTIVE gates
(`blocked accounts cannot create/change preorders`, which test the ACTING user's status, so an active admin passes). Check
(3) listed two objects: `get_publisher_reserve_counts` (a read-only count RPC) and the `admin_preorders` view (explicit
column list, no caller). **Neither copies `preorders` rows wholesale, and `archive_stale_reservations` was NOT flagged**, so
the archive is unaffected on staging. Post-check: `unavailable_dismissed_at | timestamp with time zone | YES | null`,
97 `preorders`, 0 cleared. **Production is a different database: re-run the pre-flight there before applying.**

**Applied on PRODUCTION by Rick, 2026-10-05.** Pre-flight: `already_present` 0, 10 existing `preorders` columns, the same four policies, and
the same two objects from check (3) (`get_publisher_reserve_counts`, `admin_preorders`); `archive_stale_reservations` was not flagged.
Post-check: `unavailable_dismissed_at | timestamp with time zone | YES | null`, **3,574 `preorders`, 0 cleared** (3,573 were read on
2026-10-04). **Independently re-read afterwards, not taken from the paste:** a GET-only call through the production REST API reads the
column, 3,574 rows, 0 non-null. (Production's first run of an earlier migration, RPC v2 on 2026-09-29, once did not land, which is why
this was checked.) Rick asked whether the plan held a second script to run: it does not, only this file.

**The defaults (Rick confirmed all five on 2026-10-05, and said "build on F163"):**
1. **Admin-only**: the button shows when `profile.is_admin`, whether impersonating a customer or on the admin's own list
   (Rick's own account holds 14 of the 48 eligible rows). Customers never see it.
2. **Only on cards with no Remove button.** Remove already clears a card, by deleting the reservation, which is the
   established behaviour for withdrawn and open-rejected rows.
3. **A confirm dialog** (the page's existing `#confirm-overlay`) before the write, saying the reservation is kept and the
   customer stops seeing the notice. A mis-click would hide a notice from a customer, which is the harm this guards.
4. **Hidden for everyone once cleared**, customer and admin views alike; the badge count drops.
5. **No in-app undo**, consistent with Rick's 2026-10-04 answer on the resolve control. Restore is one line of SQL
   (`UPDATE preorders SET unavailable_dismissed_at = NULL WHERE id = '<preorder id>';`). A small admin-only
   "Cleared (N) · Restore" toggle is the obvious addition if wanted; not in the defaults.
6. **The client reads the flag in its own small paginated query in `mylist.html`**, not in `Preorders.getMy` and not in
   `app.js`, and **fails open**: if the column is missing the query errors and every card shows. A cleared card
   reappearing is the safe direction; a live card hidden is not. This is the F115 lesson (a client that selects a column
   production lacks 400s the whole page) applied up front. `/promote-prod` step 0 still blocks while the SQL reads
   PENDING for production.
7. **Purely presentational:** it changes no `fulfilled`, `arrival_outcome`, ledger row, Order Follow-Up row, bagging list
   or export.

**Known limit, stated plainly.** `users manage own preorders` is ALL, so a customer with a hand-crafted request could set
or clear the flag on their own rows. The admin-only gate is a UI gate, the F127 class. The worst case is a customer hiding
or re-showing a notice about their own reservation.

**Coupling, now real.** This sits in the same `mylist.html` as the F163 build above, which is staging-only and not yet
validated. A later full `staging` -> `main` promotion carries both, and the migration is now applied on production too
(2026-10-05), so step 0 no longer blocks on it. Rick chose to build on F163 rather than keep them separable.

**Build record (2026-10-05, staging only).** Code `6583a6c`, `mylist.html` only (+64/-2; served bytes byte-identical to the
commit, sha256 prefix `c616c0b86deec8e3`, plain URL). The client reads the cleared ids in its own paginated query (not
`Preorders.getMy`, so no `app.js` change), **fails open**, and judges the write by the returned ROW COUNT, not `error`.
- **Harness** (`mylist-no-longer-coming-verify.mjs`, local-only): **80 PASS / 0 FAIL on the deployed bytes** (its own final
  line), 76/76 on the working tree with the column present. New checks: PD1 a customer never sees Clear; PD2 an admin
  impersonating sees it on exactly the cards with no Remove (C F G L N) and on none of A B K; PD3 an admin on their OWN list
  gets it; PDF1/PDF2 **fail-open** (a copy whose cleared-ids query names a missing column still shows all 8 cards, no page
  error); PD4-PD13 the end-to-end flow: the confirm names the customer and says the reservation is kept, **Cancel writes
  nothing**, Clear stamps the row, **the reservation is kept with fulfilled and arrival_outcome unchanged**, the card
  leaves and the badge drops by one, **still gone after a reload**, and the CUSTOMER's own session no longer sees it but
  still sees the others and still has no Clear button.
- **Negative controls** (a single edit to a scratch copy, the repo file's sha256 unchanged each time): open the admin gate
  to customers -> PD1 red; close it to everyone -> PD2 and PD3 red; break fail-open (a failed read throws) -> PDF1 red, and
  that control shows what fail-open buys: **0 cards, the whole section gone, plus a page error**; drop the persisted filter ->
  PD10 and PD11 red; write nothing -> PD7 red; also clear `fulfilled` -> PD8 red. **One prediction was wrong and is recorded
  as such:** I expected PD9 to go red when the persisted filter was dropped. It stayed green, correctly, because PD9 only checks
  that the card leaves the page right after the click, which the click handler does on its own; PD10 (reload) and PD11
  (the customer's view) are the checks that catch it, and both went red.
- **NOT TESTED:** that a silently RLS-filtered zero-row update is reported as a failure. The harness cannot create a blocked
  admin, so the row-count check has no control; it is reasoned (F127's lesson), not observed. F127's UPDATE gate is a
  WITH CHECK, which raises rather than filters, so a true silent zero-row is less likely than it sounds.
- **Layout shift** unchanged by the extra query: **0.006 desktop / 0.005 mobile** with the section, identical to without.
- **Full suite: 158 passed (23.4 min)**, 0 failed, from the log's own line (156 + the two new local-spec tests, V6 and V7).
  Teardown re-read from the database: nothing this session created is left; the demo account was kept on purpose; the same
  four August `pw-*` tenants and one `TEST_PW_` catalog row remain (F130 family), untouched.
- **Spec 25** now has 7 tests; V7 needs the new column and fails loudly at the database read if it is missing.

**Stated plainly.** Chromium only; staging only; nothing in git asserts any of it (the suite and harness are gitignored); no
in-app undo (restore is one `UPDATE preorders SET unavailable_dismissed_at = NULL WHERE id = ...`); the customer-side gate is a
UI gate (F127 class). **Not done: production.** Rick has not validated the Clear button either. Feature build, **no finding ID
consumed** (F170 stays next free).

**An adjacent question Rick asked while validating, answered and left alone (2026-10-05).** The admin dashboard's "Withdrawn by
Distributor" panel has no action to close a row. That is the F110 § 4.5 design: it is read-only and lists unfulfilled
reservations on withdrawn titles. A row leaves it when the last customer removes their reservation (F110 re-enabled Remove),
when auto-fulfil closes the reservation, or when the mark clears on reappearance (F146). If customers do not remove and the
title is not yet fulfilled, an admin can only close it by impersonating each customer. Since F165 S1 nothing marks titles
withdrawn, and production last read 0 marks (2026-09-27), so the panel is empty there. **Rick: leave it as is.** A title-level
"remove these reservations" action, if ever wanted, belongs with F165 S3's confirm-to-mark design, because a false mark
(F165's 7) plus a bulk delete cannot be undone.

## References

`docs/technical-reference.md` § 13 **F163** (owner record), **F115** (what `arrival_outcome` means),
**F134** (§ 4.3: the customer sees human-confirmed outcomes only), **F143** (the rejection write),
**F120** (the rejected badge this keeps from being transient), **F155** (the stranding and the 14-day
deferral), **F161** and **F141** (the layout rules), **F109/F110** (the delete guards), **F162/F139/F140**
(pagination), **F28** (local dates); `docs/f115-arrival-truth-persistence.md`; commit `c514c79`;
PR #159 (how it reached production).
