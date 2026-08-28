# F143 + F144 — ordering-side rejection handling

**STATUS:** NOT STARTED | staging=— | prod=— | findings=F143,F144

**Type:** Feature build against two filed proposals. **No schema change. No migration. No Edge
Function change. `admin.html` only** (plus the local Playwright suite, which is never committed).
**Target:** `staging`, single feature branch `feature/f143-f144-ordering-side-rejections`.
**Execution model:** one Sonnet CLI session, start to finish, with **two PAUSE → Rick points**
(§ 5.1 and § 7 V8). Self-contained — no chat context required.
**Last verified against live code:** 2026-08-27 against `staging` @ `dedfb73`. Every line number
below was read from disk that day. **Re-read before editing — do not trust these numbers blind**
(CLAUDE.md § File Drift Prevention).

---

## 1. Why these two, together

They are the two halves of one idea: **make supplier rejections visible where the ordering work
actually happens.** Both were filed 2026-08-26 out of the same operational walkthrough with Rick,
both are display/control changes on the same two surfaces, both need no schema change, and both
lean on machinery that already exists and is already correct.

- **F143** closes the *recording* half — a rejection discovered mid-cycle can be written from the
  panel where it surfaces, instead of in a different tab.
- **F144** closes the *anticipating* half — the ratio that predicts a rejection is shown at the
  moment the operator decides.

They also split cleanly by risk, and the session should treat them that way:

| | Touches a write path? | Worst case if wrong |
|---|---|---|
| **F143** | **Yes** — inserts an `order_submissions` row | A wrong ledger row; corrigible via the existing Adjustment path, but it is real data |
| **F144** | **No** — renders an existing column | A badge in the wrong place |

**Build F144 first.** It is read-only, it forces the session to prove `order_requirement` reaches
the builder, and it leaves the write path untouched until the display half is green.

---

## 2. Entry conditions

- [ ] On `staging`, clean tree, `git pull origin staging` done.
- [ ] `/preflight` green.
- [ ] Confirm **F115 is not in its import window.** F115's S1/S5/S6 are held for the ~Sept 7-10
      catalog import. This work must land and be promoted *before* that window opens, or wait until
      after it closes — do not have two sessions touching admin ordering surfaces across an import.
- [ ] Read `docs/technical-reference.md` § 13 **F143** and **F144** in full. They carry Rick's
      operational reasoning, and two decisions in them are explicitly "do not re-propose."

---

## 3. What is already true — measured 2026-08-27, not assumed

Verified against `staging` @ `dedfb73` and against live production. Spot-check rather than
re-derive.

**The ledger helpers already do the work** (`admin.html`):

| Anchor | Line | Role here |
|---|---|---|
| `ledgerMatchesFor(distributor, code)` | 840 | rows for a code |
| `ledgerNetQty(distributor, code)` | 852 | **signed** sum — the number F143 negates |
| `ledgerRejected(distributor, code)` | 860 | `rows.length > 0 && net <= 0` — the exit that clears the row |
| `neverArrivedFromFulfilled()` | 1657 | already excludes `ledgerRejected()` codes |
| `computeBackorderRisk()` | 1665 | same exit again, line 1682 |
| resolve-control markup | 1751-1756 | the three existing buttons |
| `wireArrivalResolveActions(panel)` | 1816-1838 | the click handler |
| Mark Ordered `order_submissions` insert | 3056 | **the exact payload shape F143 must copy** |

**The rejection → clear chain is proven in production.** The two titles rejected 2026-08-21
(`75960621489100116`, `82771403458501031`) still read `arrival_outcome = 'unknown'` and correctly
do **not** appear in Never Arrived. F143 does not need to build that chain; it needs to reach it.

**A zero-quantity row already IS the rejection record.** The `ob-record-save` handler (line 2906)
writes `quantity: 0` for an unticked line, with the comment at 2927 stating exactly that. F143 is
not inventing a convention — it gives an existing convention a second, closer entry point.

**`order_requirement` is absent from `admin.html` — confirmed, 0 occurrences.** Present in `app.js`
(x3), `catalog.html` (x2), `style.css` (x1). Production carries it on 809 titles (Lunar 314 via
`variant_type`, PRH 495 parsed at import).

**The submitted distributor file cannot be polluted by F144 — verified.** `generateOrderExport`
(line 2769) builds each line as `code,TotalQty` explicitly. There is **no generic
`Object.keys()`-driven CSV serializer** anywhere in `admin.html` (the only two `Object.keys` uses
are at 1957 and 5020, neither related). All four consumers of `makeOrderSheetRows` /
`buildExportRows` read named fields. **Adding a field to the row object is safe.** Re-confirm with
a grep before relying on it.

---

## 4. Part B first — F144, restriction ratios on the ordering side (display only)

### 4.1 Plumb the column

Add `order_requirement` to the embedded `catalog (…)` select in `fetchAllPreorders()` —
`admin.html` **lines 1201-1205**, the list currently ending `withdrawn_at,
withdrawn_last_seen_month`.

**Do not** add it to the This Week bagging select at line 3437. That query feeds the bagging list,
which has no ordering role, and widening it costs bytes on the largest paged read in the file.

Then carry it onto the order-sheet row object in **two** places, which must stay in step or the
already-ordered rows render without a badge:

1. `makeOrderSheetRows()` — line 2331, the `map[key] = { … }` literal. Add `OrderRequirement:
   c.order_requirement` next to `VariantType`.
2. `buildExportRows()` — line 2736, the `extraRows` object literal at 2752-2760. **This is the easy
   miss.** It is a hand-written duplicate of the same shape for the already-ordered add-backs.

### 4.2 Render it

Per § 13 F144's own priority order:

1. **Record step (highest value)** — `renderRecordPanel()`, line 2813; the `.ob-rec-row` markup at
   2846-2856. Badge the ratio on each line that has one. This is the control where a PRH rejection
   is actually recorded, so the badge belongs next to the checkbox.
2. **Group restricted titles** (Rick's addition) — cluster them rather than leaving them scattered
   through a list sorted alphabetically by item code. A collapsible `Restricted (n)` group is the
   shape he described; **ordering restricted lines first within the existing list is the cheaper
   build and is acceptable for v1** if grouping fights the `recordSelections` keying. Either way
   the `data-code` attributes and the `.ob-rec-cb` / `.ob-rec-qty` selectors must not change —
   spec 15 (lines 987, 1039, 1058) drives them by `data-code`.
3. **Included list at cycle-selection time** — so the risk is visible before submission.
4. Held-back / already-ordered panels — free once the badge exists, lowest value. **Optional.**

Visual: reuse the *idea* of `app.js`'s `restriction-badge` (line 1844), but **do not reuse the
class name unmodified without checking `style.css`**. That class carries customer-facing styling
sized for a catalog card, and `style.css` is shared across all pages. A scoped admin variant is
safer than restyling a live customer element.

### 4.3 The trap, restated because it is the whole finding

**DO NOT PARSE THE TITLE.** The import already resolves ratios that appear nowhere in the title
string. Two production rows are `order_requirement = '1:25'` with no ratio in the title at all:
`WADE WILSON: DEADPOOL #9 TBD ARTIST VARIANT [BG]` and `PUNISHER SHOWDOWNS: BLACK WIDOW #1 JOE
JUSKO VARIANT`. Title-parsing would miss exactly the titles the feature exists to surface, while
appearing to work on the ones where the ratio *is* in the title. **Read the column.**

### 4.4 Honest value asymmetry — put it in the UI copy

- **PRH: actionable.** Rejections are knowable at order time; the badge sits next to the control
  that records them.
- **Lunar: advisory only.** Lunar rejections appear as negative quantities on the *order invoice*
  after processing; the *shipping* invoice the weekly import consumes shows only what shipped. A
  badge flags candidates for suspicion, never outcomes.

The record-step copy must not imply a Lunar operator can act on the badge. **Lunar's two-phase rule
is unchanged: record the full submitted order, untick nothing, correct later.**

---

## 5. Part A — F143, "Rejected by supplier" on the Order Follow-Up resolve control

### 5.1 The write — and the one open decision

Add a **fourth** button to the resolve control at `admin.html` 1751-1756, alongside Received /
Didn't arrive / Damaged. It does **not** follow the other three's code path.

**What it writes:** an `order_submissions` row that nets the code to 0, using the payload shape
copied from the Mark Ordered insert at line 3056 — `tenant_id: TenantContext.current().id`,
`distributor`, `order_code: exportCode(c, c.distributor)`, `item_code`, `title`, `quantity`,
`order_type`, `foc_date: c.foc_date || null`, `catalog_month: c.catalog_month ||
currentCatalogMonth`, `submitted_on: DateUtils.todayLocal()`.

**What it must NOT write: `arrival_outcome`.** Leave it `'unknown'`. § 13 F143 is explicit — the
ledger rejection is the fact; `arrival_outcome` records what the *import* judged about arrival.
They are different statements, and writing both creates two records that can later disagree. The
two production titles above already demonstrate the intended pattern. **The row clears through
F134 Part 1's `ledgerRejected()` exit with no `arrival_outcome` write at all.**

**🛑 PAUSE → Rick — the never-ordered case.** The Never Arrived panel also contains titles with
**no ledger rows at all** (never ordered, or ordered before the ledger's May-cycle history began).
For those `ledgerNetQty()` is 0 and there is nothing to negate — and the Mark Ordered modal's own
rule blocks a zero-quantity Adjustment as meaningless (lines 3044-3045).

- **Recommended v1: show the button only when `ledgerNetQty(distributor, code) > 0`.** A title with
  no order record has nothing to reject, and "Didn't arrive" remains the honest control there. This
  keeps the build entirely inside F143's stated fix shape.
- **The alternative** — writing a zero-quantity `adhoc` row to record a rejection on a never-ordered
  title — is *representable* (`ledgerRejected()` only needs `rows.length > 0 && net <= 0`) but it
  changes what the ledger asserts, and the `order_type` choice has downstream routing consequences
  in `classifyForExport()` (per the comment at 2915, `'adhoc'` matches route into the
  auto-excluded bucket rather than "already ordered — your call").

**Do not decide this alone. Measure first, then ask Rick:** count how many current Never Arrived
rows on production actually have `ledgerNetQty === 0`. If the answer is "essentially none," ship the
recommended v1 and note it. If it is a meaningful share, the button is half-useless without an
answer, and that is Rick's call, not the session's.

### 5.2 The rest is existing machinery

Once the row lands, per § 13 F143: net ≤ 0 → `ledgerRejected()` → the row clears through F134
Part 1's exit → **F120 surfaces the rejection to the customer** → By Distributor corrects →
`classifyForExport()` routes the code back to `included` when its cycle is ticked, which is the
re-offer behaviour F142's comment explicitly protects. Nothing new is needed downstream.

After the insert, follow `wireArrivalResolveActions()`'s existing pattern — disable the buttons,
reload, re-render. But note the existing handler calls `loadData()`, the heavier "reload
everything" path. Prefer the narrower `loadOrderLedger()` + `renderByDistributor()` +
`renderBackorderRiskPanel()` trio that `ob-record-save` uses (lines 2953-2955), since only the
ledger changed. **Confirm the panel actually re-renders and the row disappears** — a re-render that
reads a stale `orderLedger` leaves the row on screen and looks like the write failed.

### 5.3 Copy

Button label: **Rejected by supplier**. The success toast should name what happened to the order,
not just the panel — e.g. `Recorded as rejected — order corrected`. The three existing toasts are
at lines 1832-1834.

---

## 6. Traps carried in from prior sessions

1. **Sweep the suite before changing any element with an id or class** (the F142 lesson). Verified
   2026-08-27: spec 21 V4 targets `.arrival-resolve-btn[data-outcome="damaged"]` specifically, and
   spec 15 drives `.ob-rec-cb[data-code=…]` — so **adding** a fourth button and a badge breaks
   neither. Re-run the sweep after writing the code, not only before:
   `grep -rn "arrival-resolve\|data-outcome\|ob-rec-\|backorder-risk" tests/`.
2. **A test edited to match your own code must be proven able to fail** (F142 / customer-phone
   sessions). Every new assertion gets a negative control — temporarily assert a value that cannot
   be present, confirm red, revert.
3. **Push, then test.** Playwright's `baseURL` is the deployed staging site and cannot see the
   working tree; a pre-push run tests the *previous* build. Push → confirm new bytes are served at
   the **plain** URL (no `?cb=` — a query string is a different Cloudflare cache key) → then run
   the suite.
4. **JS syntax gate.** `admin.html` is one large inline script; a syntax error kills every tab.
   Extract and `node --check` the inline `<script>` blocks before pushing. The print-CTA session
   caught an illegal `\00b7` escape inside a template literal exactly this way.
5. **Spec 21 is order-dependent** (F133 variant b). A targeted run of it is not trustworthy on its
   own — spec 15 runs first and leaves state it needs. Judge spec 21 by the full-suite result.
6. **Do not re-propose order-invoice compare-and-report.** Declined by Rick 2026-08-26 — "more
   cumbersome than helpful." § 13 F143 records why, and why the analysis has genuinely moved since
   F108 without overriding the operator's judgement.

---

## 7. Verification gates

| Gate | What it proves | How |
|---|---|---|
| **V1** | `order_requirement` reaches the builder | On deployed staging, a title known to carry a ratio renders its badge in the record step. Assert on a **seeded** title or `data-code` — never `.first()`, never an exact count (staging carries 857 real backfilled ledger rows) |
| **V2** | Restricted titles are grouped/ordered as built | Real-browser check plus screenshot. Not spec-covered by default — CSS/layout needs a real browser (two prod incidents on this exact point) |
| **V3** | The submitted file is byte-unchanged | Generate an order sheet before and after the change with the same cycle selection; `diff` the two downloads. **Must be identical.** This is the gate protecting the distributor file |
| **V4** | The new button writes the right row | New Playwright spec: seed a fulfilled / `unknown` / net>0 title, click **Rejected by supplier**, then read `order_submissions` directly and assert distributor, `order_code`, `quantity === -net`, `order_type === 'adjustment'`, and `tenant_id` |
| **V5** | It does **not** write `arrival_outcome` | Same spec: read the `preorders` row after the click, assert `arrival_outcome` is still `'unknown'`. Model it on spec 21's V4, which already proves "exactly one column changed" |
| **V6** | The row leaves the panel, for the right reason | Assert `.backorder-risk-row` count 0 for that title **and** that V5 passed — i.e. `ledgerRejected()`'s exit cleared it, not an `arrival_outcome` write |
| **V7** | Nothing regressed | Full `run-smoke.ps1` — expect **269 unit** + Playwright at the current count, 0 failures, run **after** the push against deployed bytes. The new spec raises the Playwright count; record the new number |
| **V8** | 🛑 **PAUSE → Rick** | Rick drives the real flow on staging: order a title, mark it rejected from the panel, confirm By Distributor corrects and the customer-side badge appears. A green suite says the assertions hold, not that the feature is right |

---

## 8. Out of scope — do not drift into these

- **Any schema change.** F117 already permits negative quantities and `order_type = 'adjustment'`;
  `order_requirement` already exists and is already populated.
- **Order-invoice ingest, or compare-and-report** — declined (§ 6.6).
- **Changing what the distributor file contains** — V3 exists to prove this did not happen.
- **`arrival_outcome` semantics**, the F115 persistence work, or anything in the September import
  window.
- **Repointing Mark Fulfilled** — still the separately-approved follow-up it has always been.
- **The import scripts.** Neither finding needs an import change; both read data the import already
  writes correctly.
- **F141's unmeasured CLS on `mylist.html` / `arrivals.html`** — adjacent, not this.

---

## 9. Completion criteria

- [ ] F144: `order_requirement` selected, plumbed through **both** row-object literals, badged in
      the record step, restricted titles grouped or ordered-first, visible in the included list.
- [ ] F143: fourth button live; writes the netting row; writes **no** `arrival_outcome`; the
      never-ordered case resolved per § 5.1's PAUSE.
- [ ] V1-V7 green; V8 confirmed by Rick.
- [ ] New spec added to the local suite (never committed to the repo) and its assertions
      negative-control tested.
- [ ] `docs/technical-reference.md` § 13 F143 and F144 status lines updated to RESOLVED-on-staging
      with date and commit.
- [ ] This doc's `**STATUS:**` token updated.
- [ ] `CLAUDE.md` § Current Migration Phase "Last completed work" advanced, and the F143/F144 rows
      removed from the open-findings table.
- [ ] Merged to `staging` with `--ff-only`.
- [ ] Production promotion **only** on Rick's explicit request, via `/promote-prod`.

---

## 10. Reference

- `docs/technical-reference.md` § 13 — **F143**, **F144** (the specifications), **F134** (the
  resolve control and the `ledgerRejected()` exit), **F117** (the signed ledger), **F120** (the
  customer-facing rejected badge), **F142** (same defect class, resolved), **F132** (captured
  `order_requirement`; this is the ordering-side half it did not reach), **F102** (the remainder
  control the record step protects), **F133** (spec 21's order dependency).
- `docs/order-loop-closure-f108.md` § 4.4 / § 8 — why the ledger is signed, and why recording moved
  to step 2.
- `docs/f134-arrival-resolution.md` — the panel this extends.
- `CLAUDE.md` § Standard Deployment Workflow, § Smoke-test ordering, § Anti-Drift Rules.

---

**Written:** 2026-08-27 (planning session). **Execution:** one Sonnet CLI session, not yet run.
