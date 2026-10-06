# F163 — A confirmed-terminal reservation keeps a lasting place on the customer's My List (design)

**STATUS:** COMPLETE, BOTH ENVIRONMENTS — PROMOTED TO PRODUCTION 2026-10-05 (PR #168, merge `fcba6ba`; build `9fbb71b`, admin Clear `6583a6c`, `mylist.html` only; its SQL `prod=APPLIED` the same day). **Follow-ups PROMOTED 2026-10-06: PR #169 (merge `95ff4d2`; supplier-rejected Remove and the "store is handling it" wording, §§ 18, 20) and PR #170 (merge `b5be5d7`; an empty main list shows the section inside the empty-state block, `4e2b0ea`, §§ 19, 21).** · staging=2026-10-06 · prod=2026-10-06 · PR=#168, #169, #170 · findings: F163 (closed; owner record in `docs/technical-reference.md` § 13). *(This token read "COMPLETE except one human check" until Rick reported his own count on 2026-10-06, and earlier "IN PROGRESS — BUILT AND VERIFIED ON STAGING ... NOT promoted" until the promotion.)*

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
  for an empty, non-impersonated list. **(REVERSED 2026-10-06, see § 19.) Stopped and asked Rick; ANSWERED: accept, the section stays below
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
- [x] `/promote-prod` only on Rick's explicit request after that validation; V12 recorded (§ 17). **Open inside V12: Rick's own My List count against the replay's 14.** *(Closed 2026-10-06: Rick reported 11, equal to that day's replay; § 21.)*
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

## 16. Addendum: an admin can CLEAR a card (Rick, 2026-10-05). BUILT AND VERIFIED ON STAGING 2026-10-05; PROMOTED TO PRODUCTION 2026-10-05 (PR #168). *(This heading read "NOT promoted" until 2026-10-06.)*

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


## 17. Production (2026-10-05): V12 recorded

Rick asked for the promotion ("2) promote Prod") after approving the copy. **PR #168, merge `fcba6ba`** (parents `5fc1b6c` main and `0f0b321`; the staging tip it carried was `cc88ced`). Gates, the served-bytes verification on both hostnames, the markers and the read-only replay are recorded in CLAUDE.md § Current Migration Phase ("PROMOTED TO PRODUCTION 2026-10-05 -- F163"). In this doc's terms:
- **V12, served bytes:** `mylist.html` byte-identical to `origin/main` on `pulllist.app` and `rjbookstop.pulllist.app` (also `app.js`, `config.js`, `arrivals.html`, `admin.html`, `catalog.html`, `style.css`). Positive markers present; the old guard as a STATEMENT x0 (the string itself reads x1 because a comment quotes it, as § 15 predicted).
- **V12, replay:** a GET-only service-role replay of § 4's predicate against production's database: **48 eligible rows, 10 accounts**, Rick's own account **14**, real customers 9 / 8 / 4 / 2 / 1. Identical to § 1.3 and § 1.5, so nothing has drifted.
- **V12, human check, ~~NOT YET REPORTED~~ REPORTED 2026-10-06: Rick's count is 11** (§ 21; the replay's 14 was 10-05's figure and three of his rows have since aged out of the window, so 11 is the expected value that day). Original text: Rick opens his own production My List; the "No longer coming" badge should read **14**. Until he says so, the finding is fixed and promoted but not confirmed by eye.
- **Day one, as predicted in § 12:** 0 customers newly see the section, 4 of the 5 who already had it get more cards (+19 rows, worst 9), Rick's own account goes 0 -> 14, and the printed list loses a block that had been printing. Nothing was written to production data by this promotion; the one schema change (the nullable column) was applied by Rick beforehand and holds 0 cleared rows.

## 18. Addendum: supplier-rejected cards stop prompting calls, and the customer can Remove them (Rick, 2026-10-05). BUILT AND VERIFIED ON STAGING 2026-10-05; PROMOTED TO PRODUCTION 2026-10-06 (PR #169). *(This heading read "NOT promoted" until the promotion.)*

**The ask.** Right after the promotion: "The store doesn't need a lot of phone calls if the answer is that the supplier
rejected it." **Measured on production's 48 eligible rows (2026-10-05):** 33 are supplier-rejected, of which 5 are open (these
have Remove) and **28 are rejected and already closed**, which show "Contact store" with no Remove; the other 15 are
did-not-arrive. So 43 of 48 cards invited a call, and most of them for an outcome that needs no conversation. **This is a side
effect of F163 itself:** before it, a rejected reservation that auto-fulfilled was hidden entirely. Asked how to fix it, Rick chose
**"Reword and let customers Remove them"** over reword-only and over leaving it.

**What changes.**
1. **A customer may Remove a supplier-rejected card even when it is closed (fulfilled).** This REVERSES § 2 decision X ("no Remove
   for fulfilled rows") for rejected rows only. Withdrawn rows already had it. **The database already permits it:** the F109 delete
   trigger blocks only a ledger that nets above zero and never reads `fulfilled`, and `users manage own preorders` is ALL. The
   only thing refusing it is the app's `Preorders.cancel()` guard, so the allowance goes **inside `Preorders.cancel()`** (`app.js`),
   the F110 pattern (`mylist.html` and the guard must agree, and one copy of a safeguard beats two): a fulfilled row is
   cancellable when its code is supplier-rejected (the ledger has rows and nets to <= 0, i.e. `get_ordered_codes()` state
   `unavailable`) **and** its `arrival_outcome` is not `arrived` (a book on the shelf is never "rejected"). The delete query's
   defensive `fulfilled = false` race guard is skipped under the same condition.
2. **`mylist.html`:** `canRemove = isWithdrawn || isRejected` (the `&& !item.fulfilled` goes). Every supplier-rejected or withdrawn
   card now has Remove; **"Contact store" remains only on did-not-arrive and damaged cards** (15 of 48 today), and the admin "Clear"
   remains for exactly those.
3. **Copy (PROPOSED; SUPERSEDED the next day by the wording follow-up at the end of this section):** the section note became "The store has confirmed these will not be
   coming to you, so there is nothing to collect or pay for. Remove clears an item from your list. If an item didn't arrive or
   arrived damaged, contact the store." The chip title and the Remove confirm are unchanged.

**Side effects, stated so they are decisions and not discoveries.** (a) Removing deletes the reservation row, so the record of what
that customer was promised is gone; Rick chose that knowingly over a hide flag for the customer side. (b) `UsageEvents.cancel` is
logged for these removals, which nudges the analytics cancel count slightly. (c) `Preorders.cancel()` is shared: on `catalog.html`
a closed, rejected, not-arrived current-month reservation can now be un-reserved, which it could not before; consistent, and the
full suite is the check. (d) **`app.js` carries `merge=ours`**: the promotion must assert the merge RESULT for `app.js` (the driver
has dropped it three times); today `main`'s copy equals staging's, so it only bites if both sides change before then.

**Not changing:** schema (none), the did-not-arrive / damaged wording, the withdrawn panel, the admin Clear, the 180-day window.

**Plan:** harness first against the current bytes (the new assertions RED), then the change in `app.js` + `mylist.html`, harness
green on the working tree, negative controls, push, deployed-bytes harness, full suite, teardown re-read; production only on Rick's
explicit `/promote-prod`. **No finding ID consumed (feature build; F170 stays next free).**


**Build record (2026-10-05, staging only).** Commit `57cc20a` (`app.js` and `mylist.html`, +50/-34 in total; both served byte-identical to the commit on the plain URL: `app.js` `883d34292426afad`, `mylist.html` `e3863603511f433b`). `Preorders.cancel()` reads the signed ledger ONCE, up front, and a closed row is cancellable when the code is `unavailable` (rejected) and `arrival_outcome` is not `arrived`; `mylist.html` has `canRemove = isWithdrawn || isRejected` and the reworded note ("...so there is nothing to collect or pay for. Remove clears an item from your list. If an item didn't arrive or arrived damaged, contact the store."). **Copy is PROPOSED: Rick approves it at his staging validation.**
- **Harness** (`mylist-no-longer-coming-verify.mjs`, which now also serves a working-tree `app.js`): **RED first** against the then-current staging bytes (7 named failures, 0 crashes: PV2b, VG2, VO, V9f, PD2, VG3, VG4), then **82/82 on the working tree** and **86 PASS / 0 FAIL on the deployed bytes** (its own final line). New checks: G (closed, rejected) HAS Remove and shows no chip; O (closed, rejected AND not_arrived) reads "Rejected by the supplier" and has Remove; **VG3 Remove genuinely deletes the closed rejected row as the customer (the database permits it, as read from the F109 trigger before building)**; VH3 `Preorders.cancel` still refuses a closed rejected row whose outcome is `arrived`; VC3 it still refuses an open row whose code the store ordered.
- **Negative controls, 5/5 red, repo files' sha256 unchanged:** drop the allowance -> VG3/VG4; drop the `arrived` exclusion -> VH3 (the row was actually deleted); drop the ordered-code guard -> VC3; restore the old `canRemove` -> PV2b/VG2/VO/PD2/VG3/VG4; restore the old note -> V9f. **One control FAILED to go red the first time, and that is the useful finding:** with the client's ordered-code guard disabled, VC3 still passed, because the **F109 database trigger refused the delete anyway** (defence in depth), so "it errored and the row stayed" could not tell the client guard from the database. Only a console 400 gave it away. VC3 was tightened to assert the **client's own message** ("already been placed"), baseline re-run 82/82, and the control then went red. The client guard is therefore redundant with the trigger for safety and exists for the friendly message and to avoid a wasted round trip; both are real, neither is a second line of defence a test can see without checking the message.
- **Full suite: 159 passed (24.1 min)**, 0 failed, from the log's own line (158 + the new local-spec V8). Spec sweep before pushing: no existing spec expects a CLOSED rejected row to be refused; specs 03 and 15 exercise the main table (rejected rows stay badge-only there, untouched) and open rows. **Layout shift unchanged (0.006 / 0.005).** Teardown re-read from the database: nothing this session created is left; the four August `pw-*` tenants and one `TEST_PW_` catalog row (F130 family) are untouched.
- **Production impact if promoted, from the 2026-10-05 replay:** of 48 eligible rows, 33 are supplier-rejected and ALL get Remove (5 already had it; **28 closed ones newly do**); the 15 did-not-arrive cards keep "Contact store", and the admin Clear applies to exactly those 15.

**Side effects to remember (decided, not discovered).** Removing deletes the reservation row, so the record of what that customer was promised is gone (Rick chose that over a customer-side hide flag). `UsageEvents.cancel` is logged for these. `Preorders.cancel()` is shared, so on `catalog.html` a closed, rejected, not-arrived current-month reservation can now be un-reserved; no spec covers that. **`app.js` carries `merge=ours`: when this is promoted, assert the merge RESULT for `app.js`.** Today `main`'s `app.js` equals the pre-change staging copy, so the driver only bites if both sides change first. **Not tested:** a real phone, WebKit, production. Feature build, **no finding ID consumed** (F170 stays next free).


**Wording follow-up (Rick, 2026-10-06): did-not-arrive and damaged cards must not prompt a call either. BUILT AND VERIFIED ON STAGING; NOT promoted.**
- **The point, in his words:** for an item that did not arrive or arrived damaged, the store has a way of claiming it with the supplier, already knows the status, and may have ordered replacements that could result in a backorder. So "contact the store" invites calls about something already in hand.
- **What the system can and cannot say.** A search of the app code and schema found **nothing that records a supplier claim or a replacement order**; the only signals are the `arrival_outcome` of `not_arrived` / `damaged` and the order ledger, which cannot say whether a replacement was ordered. So the wording states the store's general process and promises nothing about a specific book (no "is following up on this one", no "a replacement will arrive"; some of these cards are months old). Per-item information would need a new admin-set field ("replacement on order") and was **not built**.
- **One consequence worth keeping:** a replacement attaches to the reservation, so these cards deliberately have NO customer Remove (the store still holds an order against the code; F109).
- **The two changes (`mylist.html` only, commit `483f843`; served byte-identical on the plain URL, sha256 prefix `ae34e6c214680fd1`).** Section note: "The store has confirmed these will not be coming to you, so there is nothing to collect or pay for. Remove clears an item from your list. If an item didn't arrive or arrived damaged, the store already knows and handles it with the supplier. A replacement, if one is ordered, may take longer, and you don't need to do anything." Chip on those cards: **"Store is handling this"** (was "⚠ Contact store"), hover text "The store already knows about this and handles it with the supplier. Any replacement may take longer. Nothing for you to do." **Styling decision I made, flagged:** the chip is NEUTRAL grey instead of the red alarm style (nothing for the customer to do) and wraps to two lines, because the label is longer than the card's 100px.
- **Verified:** harness **RED first** (exactly the three expected failures, V7d / VF2 / V9f, 0 crashes), **82/82 on the working tree**, **86 PASS / 0 FAIL on the deployed bytes** (its own final line); chips fit their cards at desktop and 390 px; screenshots inspected; layout shift unchanged (0.006 / 0.005). **Three negative controls, each observed red, the repo file's sha256 unchanged:** old chip label -> V7d, old hover text -> VF2, old note -> V9f. **Full suite 159 passed (24.2 min)**, 0 failed; teardown re-read from the database: nothing this session created is left.
- **Two bugs in my OWN tests, found and fixed, not page defects:** V9f first failed because `textContent` keeps the HTML's line break in "already⏎ knows", which the browser renders as one space (the test now matches on whitespace-collapsed text); and control 3's multi-line anchor first failed to match because the file on disk has CRLF line endings (the scratch copy is now LF-normalised; the repo file is never written).
- **ALIGNED the same day (Rick: "align the wording - if we have one damaged item when 6 were ordered, I do not want six phone calls for this"). Commit `a601283`, `mylist.html` only; served byte-identical, sha256 prefix `2a837dae7ac8d8a1`.** The eight spots: the desktop table's two visible lines ("⚠ Did not arrive — contact the store." / "⚠ Arrived damaged — contact the store.") and two chip hover texts, and the mobile cards' same two lines and two hover texts. The line now reads "...the store already knows and handles it with the supplier. Any replacement may take longer."; the hover text matches the section's. The opening words ("Did not arrive", "Arrived damaged") are unchanged because spec 21 asserts them. **The mobile notice line is single-line with an ellipsis by default and was ALREADY cutting the OLD text off in the harness ("contact the  tore."), so those two lines got `white-space:normal` and wrap.** **Deliberately NOT changed:** "FOC passed — contact the store" and the "Locked" chip (there the customer genuinely cannot change the order), and the Upcoming Arrivals cards (they say only "Did not arrive", no call to action). My earlier code comment saying the main table still said "contact the store" was rewritten to match.
- **Verified:** a new current-month damaged fixture (P) beside the existing did-not-arrive one (E), with MT1 (desktop rows), MT2 and MT3 (mobile cards at 390 px, asserting the line fits and is not truncated). **RED observed against the old page, then 85/85 on the working tree and 89 PASS / 0 FAIL on the deployed bytes** (its own final line). **Four negative controls, each red, the repo file's sha256 unchanged:** old desktop line -> MT1; old mobile line -> MT3; **removing the wrap -> MT3, which proves the "not cut off" check really detects truncation**; old chip hover text -> MT1. Spec 25 gained V9 (a current-month did-not-arrive and damaged row in the MAIN list say the store already knows and never "contact the store"). **Full suite 160 passed (23.9 min)**, 0 failed; teardown re-read from the database: nothing this session created is left. Layout shift unchanged (0.006 desktop / 0.005 mobile); screenshots inspected (the longer lines wrap to two lines in the table and fit on the mobile cards).
- **A bug in my OWN harness, found and fixed (not a page defect):** two regexes lost a backslash in the shell step that wrote them (`/s+/g` instead of `/\s+/g`), so the test deleted every letter "s" from the text and could never match "already knows". The first RED run used that buggy test, so the RED was **re-observed after the fix** against the old page, where the old text is visible in the log ("⚠ Did not arrive — contact the store."), confirming the failures were about the page.
- **Production:** unchanged. It still shows "Contact store" on the 28 closed rejected cards (until the supplier-rejected build above is promoted) and on the 15 did-not-arrive cards.

## 19. Addendum: an empty main list shows "No longer coming" inside the empty-state block (Rick, 2026-10-06). BUILT AND VERIFIED ON STAGING 2026-10-06; PROMOTED TO PRODUCTION 2026-10-06 (PR #170). *(This heading read "NOT promoted" until the promotion.)*

**The ask.** Rick, after PR #168 went live, with a production screenshot (impersonating a real customer whose main list is empty):
"Your list is empty, when shown has the NO LONGER COMING much further down before visible." This is the case § 7 flagged and § 7
recorded as ACCEPTED on 2026-10-05 (2.39 viewport heights down on desktop, 4.22 on a phone, measured for a non-impersonated
customer; the impersonated case was only inferred, not measured). Seen live, he asked to revisit it, and chose **"Inside the
empty-state block"** over "above the list for empty lists" and over leaving it. It reverses § 7's accepted placement for the
empty-main-list case ONLY. The customer who most needs this notice is the one whose list is empty *because* the items are not coming.

**Why it is far down.** When the main list is empty, `renderList()` keeps the F141 `.loading-reserve` hold (a full viewport) on the
empty-state block so nothing shrinks (measured: dropping it scored 0.613 -> 1.048 CLS), and the section sits after `#list-container`.

**The design.** When the list itself is empty (`allItems` is empty, NOT a filter with no matches), move the existing
`#unavailable-section` element INSIDE the `.empty-state` block, under the "Your list is empty" message and the Browse Catalog
button. It then fills space that is already reserved (the block is at least a viewport tall), so the page height does not change
and nothing shifts. In every other case it stays where it is (directly after `#list-container`).
- **The one real hazard, and the reason for the plan:** `renderList()` rewrites `container.innerHTML`. If the section lives inside
  the container's old content when that happens, **the element is destroyed** (its cards, handlers and the toggle with it). So the
  section is "parked" back at its home position BEFORE every rewrite, and "seated" in the empty block AFTER one that is empty. It
  re-renders on every search keystroke and filter change, so this runs often.
- **Text alignment:** `.empty-state` centres its text; the section needs `text-align: left` there or the cards' text would centre.
- Not changed: the section's content, copy, Remove / Clear rules, the 180-day window, print (it is still hidden), `app.js`, schema.
- A **no-matches search** on a non-empty list also shows the full-screen block; the section deliberately stays below the list there
  (the list is not empty; the customer has reservations).

**Checks (harness, RED first):** the section is inside the empty-state block and within ~450 px of that block's top, on desktop and a
phone; left-aligned; **survives a search re-render with all its cards**; the impersonated empty list (the screenshot's case) puts it
in the same place; a no-matches search leaves it below the list with its cards intact; and **layout shift for an empty-list account
with the section is within 0.01 of the same account without it**. Negative controls: do not seat it; do not park it before a rewrite
(the destroy hazard, expected to show as lost cards after a search); drop the left-align.

**Scope and promotion.** `mylist.html` only, staging first, a **separate follow-up** to PR #169 (which is reviewed as it stands). No
finding ID consumed (feature change to F163's own surface; F170 stays next free).


**Build record (2026-10-06, staging only; `mylist.html` only, commit `4e2b0ea`, served byte-identical on the plain URL, sha256 prefix `2c0e97400f3c491a`).** When the main list is genuinely empty, `#unavailable-section` is moved into the `.empty-state` block under the message and the Browse Catalog button; otherwise it stays directly after `#list-container`. `parkUnavailableSection()` runs FIRST in `renderList()` and before the load-error rewrite; `seatUnavailableSection()` runs only after an empty write; `.empty-state #unavailable-section { text-align: left; }`.
- **Measured (harness, staging): section top 2.39 -> 0.80 viewport heights on desktop, 4.22 -> 1.07 on a phone, 0.76 for the impersonated empty list (the production screenshot's case).** On a phone it still sits just past the first screen because the page header, notice, stats and toolbar stack above the list; it is one short scroll away instead of four screens. Not changed: the empty block's own 64 px top padding, which would gain a little more on a phone.
- **Verified:** RED first (12 named failures, 0 crashes: PV9a/b/c/e/f on both widths, PV9d on desktop, PV9g impersonated); **100/100 on the working tree; 108 PASS / 0 FAIL on the deployed bytes** (its own final line). New checks: the section is inside the block and within 450 px of its top, left-aligned, inside the FIRST desktop viewport, survives a search re-render with all 3 cards (and again once cleared), the impersonated empty list agrees, a NO-MATCHES search on a non-empty list leaves it BELOW the list with every card (PE1/PE1b), and **layout shift for an empty-list account with the section is the same as without it (0.006 desktop / 0.005 mobile; PV5e)**. Spec 25 gained V10 (10 tests). Screenshots inspected (desktop, impersonated, phone).
- **Negative controls, 3/3 red, the repo file's sha256 unchanged:** never seat it -> PV9a/b/d/g (and c/e/f); drop the park call -> PS1; drop the left-align rule -> PV9c (text-align computes to `center`, so that hazard is real).
- **ONE INVARIANT IS ONLY CHECKED STATICALLY, and I am saying so:** "park before every container rewrite". Only `loadList()` after a seated render (the admin Shelf Order Apply) rewrites a seated container with non-empty content, and no UI path in the harness reaches it. PS1 reads the page's own served script and asserts each of the 3 `container.innerHTML =` writes has a `parkUnavailableSection()` earlier in its function. It proves the call is present, not that a rewrite would be survived at runtime. Note too that the "destroyed" hazard is a DETACH, not a loss of the JS object: after an empty -> empty rewrite the old element could simply be re-appended, so a search re-render alone would NOT have caught a missing park, which is why PV9e passing does not prove the park exists.
- **Two bugs in my OWN harness, found and fixed:** the first RED run **crashed** (not a valid RED) because the filter input is hidden behind the magnifier on a phone-width page, so `locator.fill()` timed out; the harness now sets the value and fires the page's own `input` event (`setSearch`), and the RED was re-run to completion. (And earlier the same day a regex lost a backslash, recorded in the § 18 wording record.)
- **Full suite: 160 passed + 1 FLAKY (24.2 min), not "161 passed".** The flaky test is spec 15 "Order Builder opens with a multi-select FOC-cycle list…": its first attempt failed on `net::ERR_NAME_NOT_RESOLVED` while the `adminPage` fixture navigated to the Supabase magic link (a DNS failure on the test machine before any page loaded, the same signature recorded 2026-09-30), and it passed on retry. Unrelated to this change. **That failed attempt leaked one auth user**: `adminPage` creates the user and then `signInVia` threw before `use()`, so its teardown never ran. I classified it (exact `pw-admin-<8 hex>@example.test` shape, created 17:31Z, 0 preorders, exactly one candidate), deleted it and re-read: auth user 404, profile 0 rows. Everything else this session created is gone; the four August `pw-*` tenants and one `TEST_PW_` catalog row (F130 family) are untouched. The fixture leak path is NOT fixed and NOT filed (test-infra, Rick's call).
- **Stated plainly:** Chromium only; staging only; nothing in git asserts any of it (suite and harness are gitignored); a real phone has not been used. ~~**Not promoted:** Rick's explicit `/promote-prod` is required, `mylist.html` only (no `app.js`, so no `merge=ours` question this time).~~ **PROMOTED the same day: PR #170 (§ 21).** Feature change, **no finding ID consumed** (F170 stays next free).

## 20. Production (2026-10-06): PR #169 verification record

Rick requested the promotion ("/promote-prod") and merged **PR #169 (merge `95ff4d2`**, parents `fcba6ba` and `997b6a5`) at 16:53Z. It carried the supplier-rejected Remove (§ 18), the section wording and the main-list alignment (§ 18's wording follow-ups). Gates, the served-bytes verification and the replay are in CLAUDE.md § Current Migration Phase ("PROMOTED TO PRODUCTION 2026-10-06 -- F163 follow-ups"). In this doc's terms:
- **Served bytes:** `app.js` (`883d34292426afad`), `mylist.html` (`2a837dae7ac8d8a1`) and five other files byte-identical to `origin/main` on `pulllist.app` and `rjbookstop.pulllist.app`; the new markers present, the old text x0, the staging-only § 19 code absent (it shipped later the same day, PR #170, § 21).
- **Replay (read-only, 2026-10-06):** 45 eligible rows, 10 accounts: **30 supplier-rejected, all with Remove (25 newly), 15 did-not-arrive**. **Rick's own account reads 11 (it read 14 on 10-05; three of his older rows crossed the 180-day window).** The § 12 "day one" figures are therefore a day old and drift by a few rows a week at the window's edge, as § 9 B1 predicted.
- **Not verified:** a real cancel on production (the diff changes `Preorders.cancel()`; the evidence is staging's harness, VG3 / VC3 / VH3, and the suite); WebKit or a real phone; ~~Rick's own count~~ (reported 2026-10-06: 11, § 21).

## 21. Production (2026-10-06): PR #170 verification record, and the own-count check closed

Rick requested the promotion (`/promote-prod`, adding "My List is 11") and merged **PR #170 (merge `b5be5d7`**, parents `95ff4d2` and `4d862d4`) at 18:03Z. It carried § 19 only: an empty main list shows the section inside the empty-state block (`mylist.html`, +26 lines; staging code `4e2b0ea`, staging tip `c32b36a`). Gates, the served-bytes verification and the finding-ID disposition are in CLAUDE.md § Current Migration Phase ("PROMOTED TO PRODUCTION 2026-10-06 -- F163 follow-up: an empty My List ..."). In this doc's terms:
- **Served bytes:** `mylist.html` (`2c0e97400f3c491a`, the same bytes staging served when the harness ran 108/108 and the suite 160 passed + 1 flaky), `app.js` (`883d34292426afad`, unchanged), `config.js`, `catalog.html`, `arrivals.html`, `admin.html` and `style.css` byte-identical to `origin/main` on `pulllist.app` and `rjbookstop.pulllist.app`; `parkUnavailableSection` x3, `seatUnavailableSection` x2, the conditional seat call x1, the left-align rule x1; the earlier markers still present.
- **V12 human check closed:** Rick reported "My List is 11". The read-only replay's figure for his own account on 2026-10-06 is 11 (14 on 10-05, before three rows crossed the 180-day window), so the two agree. His words do not say which element he read, so this is a count match rather than a visual check of the empty-list placement.
- **Not verified:** the empty-list placement as rendered on production (the screenshot that prompted it was the before state); WebKit or a real phone; the park-before-rewrite invariant at runtime (static check only, § 19); nothing in git asserts any of it.
- **Write-smoke:** skipped; `mylist.html` only, with no `app.js`, `Preorders` or reserve/cancel path in the diff.
- **Disposition:** feature change, no finding ID consumed (F170 stayed next free until later the same day, when an unrelated test-infra finding, the Playwright fixture leak, took it; F171 is now next). F163 has nothing left open on this surface.

## References

`docs/technical-reference.md` § 13 **F163** (owner record), **F115** (what `arrival_outcome` means),
**F134** (§ 4.3: the customer sees human-confirmed outcomes only), **F143** (the rejection write),
**F120** (the rejected badge this keeps from being transient), **F155** (the stranding and the 14-day
deferral), **F161** and **F141** (the layout rules), **F109/F110** (the delete guards), **F162/F139/F140**
(pagination), **F28** (local dates); `docs/f115-arrival-truth-persistence.md`; commit `c514c79`;
PR #159 (how it reached production).
