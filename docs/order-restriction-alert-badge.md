# Ordering-restriction alert + badge — warn customers before they reserve a limited-ratio variant

**STATUS:** STAGING COMPLETE 2026-08-21 | staging=V1-V7 ALL GREEN — real import run 2026-08-21 populated `order_requirement` for both distributors from live data; a hover-stacking bug found the same day (badge + tooltip both broken on `.comic-card:hover`) was root-caused and fixed; the native-tooltip mobile gap flagged in § 5 (revisit if it matters) turned out to matter — the detail modal now carries the same disclosure, tap-accessible everywhere | prod=N/A, not requested | findings=F132, F133 (unrelated test-infra bug surfaced while verifying this)

**Origin:** Rick's request, 2026-08-20. Today a title PRH restricts (`OrderRequirement != 'Order All'`,
shown in the UI as a ratio like `1:10`) can be reserved by any number of customers with no signal
that the store may not actually get a copy. If the distributor doesn't allocate one, the title ends
up `rejected` at order time (existing F117/F108 mechanism) — the customer finds out only after the
fact, via the same badge used for ordinary rejections. This doc scopes a **proactive** warning at
reservation time, ahead of that outcome, per Rick's two asks:

1. Alert PRH titles with ordering restrictions ("availability subject to distributor restrictions").
2. Badge restricted/incentive variants in the catalog, with a "Learn more" link surfacing: *"This is
   a restricted variant. Your reservation is noted, but fulfillment depends on distributor rules."*

Started as a scoping doc only, no code. **§ 5 records the scoping decisions Rick made 2026-08-20**
(alert style, tooltip vs. popover, surface scope, finding ID); § 7 is the runbook that followed in
the same session. Nothing here is committed to a sub-deploy — CLAUDE.md's Current Migration Phase is
"none" (Phase 5 closed, Phase 6 stub-only) — so this doc is what makes the work real enough to
execute, per the Session Opening Protocol.

---

## 1. What's actually in the data (measured 2026-08-20, not assumed)

**PRH — the field exists and is clean.** `2026_08_PRH_metadata_full_active.csv` (879 rows), column 35
`OrderRequirement`:

| Value | Rows |
|---|---|
| `Order All` | 746 |
| `1:25` | 44 |
| `1:10` | 36 |
| `1:50` | 24 |
| `1:20` | 13 |
| `1:100` | 6 |
| `1:15` | 5 |
| `1:5` | 3 |
| `1:250` / `1:40` | 1 each |

**133 / 879 rows (15%) carry a real restriction.** All 133 checked: `VariantType = 'Variant Title'` in
every case (never `'Primary Title'`), and the companion column `OrderRequirementUPC` is **empty in
all 133** — the restriction is self-contained on the variant's own row, not a pointer to another row.
That simplifies the design a lot: no cross-row lookup, just a per-row flag. `MaxOrderQuantity` is
`'No Limit'` on every sampled restricted row — a separate PRH concept, out of scope here.

**Lunar has no equivalent structured field.** No `OrderRequirement`-shaped column exists in
`Lunar_Product_Data_0826.csv`. The closest signal is free-text `TitleNote` (78/1,514 rows non-blank),
which **already lands in `catalog.title_note`** via the F110/F112 import work — but that column is
**written and never read**: `Select-String`/grep across `app.js`, `catalog.html`, `mylist.html`,
`arrivals.html` finds it nowhere outside the import scripts and technical-reference.md. Its values are
also overloaded — allocation warnings ("Allocations may occur.", "Limited to 350 copies Allocations
May Occur"), discount terms ("40% discount."), territory restrictions, and returnability notices all
share the one free-text field. Treating any non-blank `title_note` as "restricted" would misflag
discount/territory/returnability notes that have nothing to do with allocation risk.

**Decision this doc proposes: PRH structured ratio only for V1.** Lunar's allocation-note case is a
real, related gap (`title_note` is dead data today) but needs its own text-classification pass to
separate allocation warnings from the other three note types — that's scope creep on this feature,
not a natural extension of it. Flag it as a follow-on, don't fold it in.

**CORRECTED 2026-08-20, same day, before production was ever touched.** The paragraph above is
**wrong** and is kept verbatim rather than silently edited, per CLAUDE.md's document-integrity rule.
Rick found a live restricted Lunar variant on staging (`DETECTIVE #1 (OF 2) CVR G INC 1:20 DAVID
LAPHAM B&W VAR`) showing no badge, which prompted a re-measurement. **Lunar's `VariantType` field IS
the structured signal** — the survey above checked only for a separate `OrderRequirement`-named
column and never looked at what `VariantType` itself actually contained for Lunar. Measured against
all 4,799 Lunar rows on staging (paged past PostgREST's 1,000-row default — the first pass without
paging undercounted):

| Pattern | Rows | Meaning |
|---|---|---|
| `null` | 2,375 | standard cover |
| `Open Order` / `OPEN ORDER` / `Open order` (3 castings) | 1,832 | Lunar's own "no restriction" marker — the direct equivalent of PRH's `'Order All'` |
| a ratio (`1:10`, `1:20`, … `1:1000`) | **562** | a real, live allocation restriction — **over 4x PRH's 133** |
| `BLANK` | 19 | almost certainly a blank-sketch cover (comics convention), not a restriction concept |
| `Unlock` | 10 | an industry-wide preorder-threshold incentive, a different mechanic from a per-shop ratio |
| `Standard` | 1 | explicit standard-cover marker |

**Fix shipped same session** (scripts repo `0f5d9ae`): `parseLunarVariantRestriction()` derives
`order_requirement` from `VariantType` (case-insensitive `'open order'` → null, a `\d+:\d+` pattern →
passthrough), without touching `variant_type` itself — so nothing else that reads it (subscribe
eligibility, the existing variant badge) is affected. `BLANK` and `Unlock` are deliberately **not**
flagged — real values, neither is a per-shop ratio, and mislabeling either "Order ratio Unlock" would
be actively wrong. Both remain follow-on questions, same status as the `title_note` follow-on below.
**§ 6 scope is updated accordingly — this is no longer PRH-only.**

---

## 2. Schema

New nullable column on `catalog` (33 columns today per `technical-reference.md` § 4.3 — verify against
live before writing the migration, per CLAUDE.md SQL authoring rules):

```
order_requirement  text  NULL
```

Stores the raw ratio string (`'1:10'`, `'1:25'`, …) — from PRH's `OrderRequirement` when present and
not `'Order All'`, or from Lunar's `VariantType` when it matches a `\d+:\d+` pattern (§ 1 correction,
both distributors write this key on every upsert — **F123's key-shape rule applies**: every batch in
one upsert call needs the same key set present, or PostgREST's one-key-shape rule breaks the batch).
`NULL` otherwise. Additive/nullable, so — like F115's `arrival_outcome` — it's safe to land ahead of
the import-script change and inert until something reads it.

Migration goes in `docs/sql/` with a `-- STATUS:` line, staging first, Rick-gated for production.

---

## 3. Import — both scripts, both distributors (corrected 2026-08-20 — see § 1)

`normalizePRHCatalog()` reads `OrderRequirement`: write `null` when the value is blank or exactly
`'Order All'`, else the literal string (`parseOrderRequirement()`). `normalizeLunarCatalog()` reads
`VariantType`: write `null` when it's blank, `'Standard'`, or case-insensitively `'Open Order'`, else
the literal string if it matches a `\d+:\d+` ratio pattern — else `null` (covers `'BLANK'`/`'Unlock'`,
deliberately excluded per § 1) (`parseLunarVariantRestriction()`). Both unit-tested directly in
`test/catalog-key-shape.test.mjs` (210 tests as of this correction, both scripts green) — PRH: `'Order
All'` → `null`, a ratio string → passthrough, blank/missing → `null`; Lunar: all three `'open order'`
castings → `null`, a ratio → passthrough (and `variant_type` itself provably untouched), `'BLANK'`/
`'Unlock'`/`'Standard'`/blank → `null`.

**No backfill planned.** Unlike F115's `arrival_outcome` (a fact about a past reservation), this is
advisory catalog metadata tied to the *live* offering — it populates naturally on the next import
(the ~Sept 7–10 cycle) with no historical gap that matters. Confirm this reasoning with Rick during
scoping rather than assuming it's uncontroversial.

---

## 4. UI — three surfaces, not yet designed in detail

### 4.1 Badge
`buildComicCard()` in `app.js:1748` is the single shared card renderer (used by `catalog.html`; check
whether `mylist.html`/`arrivals.html` render restricted items through the same function or their own
markup before assuming the badge appears everywhere for free). Add a small pill — visually distinct
from the existing F120 "Rejected" badge (`mylist.html`), since these are different signals: this one is
**predictive** (shown before any order is placed), F120's is **retrospective** (shown after the
distributor actually rejected it). Conflating the two visually would misrepresent a live reservation as
already-failed.

### 4.2 Alert at reserve time
Open question for scoping, not decided here: a blocking confirm (adds friction to every restricted
reserve) vs. a non-blocking toast (reuses `toast()`, `app.js:1595`) vs. relying on the badge alone.
Recommend starting with the non-blocking toast — consistent with the app's existing interaction
weight — but this is Rick's call, not a default to build against silently.

### 4.3 "Learn more"
Surfaces Rick's exact copy: *"This is a restricted variant. Your reservation is noted, but fulfillment
depends on distributor rules."* Recommend including the actual ratio (e.g. "Order ratio 1:10") since
the badge alone doesn't carry that detail and it's already on the row. No modal system exists in this
codebase today for this kind of disclosure — decide during scoping whether this is a `title=` native
tooltip (cheapest, matches the existing FOC-lock badge pattern at `app.js:1764`) or a small custom
popover (better on mobile, where hover tooltips don't work at all).

---

## 5. Scoping decisions (resolved 2026-08-20)

- **Alert style: badge only, no separate reserve-time alert.** Neither the blocking confirm nor the
  non-blocking toast from § 4.2 ships in V1 — the catalog-card pill is the whole signal. Simpler
  than the doc's own recommendation (toast), Rick's call.
- **"Learn more": native `title=` tooltip**, not a custom popover — matches the existing FOC-lock
  badge pattern (`app.js:1764`). Accepted knowingly that this is non-functional on mobile tap (no
  hover); revisit if that turns out to matter in practice. **Revisited 2026-08-21, same session —
  it mattered.** Rick flagged the mobile gap directly. Didn't build the custom popover this note
  anticipated — reused the existing detail modal instead (opens on real click/tap already, both
  mobile and desktop), which needed no new UI component. See § 7 S7.
- **Surface scope: catalog page only.** `buildComicCard()` is used exclusively by `catalog.html`
  (verified — `mylist.html`/`arrivals.html` render their own inline markup, not this function), so
  this was free: no `mylist.html`/`arrivals.html` change needed to honor the decision.
- **Finding ID: F132 claimed** — `docs/technical-reference.md` § 13, `CLAUDE.md` § Open findings.
- **No backfill confirmed** — advisory catalog metadata tied to the live offering, populates
  naturally on the next import. Not challenged during scoping.
- **Lunar `title_note` follow-on: still separate, not folded in.** Unchanged by the § 1 correction —
  `title_note` (allocation-note free text, overloaded with discount/territory/returnability info) is
  a different, still-real gap from `VariantType` (the structured ratio field, now in scope). Both are
  "Lunar," but they're not the same problem.
- **§ 1 correction (2026-08-20, same day): Lunar IS in scope, via `VariantType`, not `title_note`.**
  The original "PRH structured ratio only for V1" decision was based on a data survey that missed
  Lunar's real structured signal — see § 1's correction block. `BLANK` and `Unlock` (both real
  `VariantType` values, neither a per-shop ratio) remain deliberately unflagged, same follow-on
  status as `title_note`.

---

## 6. Scope

### IN — final, per § 5, corrected § 1
`catalog.order_requirement` migration · import parsing, **both distributors**, both scripts + unit
tests (PRH via `OrderRequirement`, Lunar via `VariantType`'s ratio pattern) · badge (native tooltip,
no separate alert) on the shared card renderer, catalog page only · Playwright coverage.

### OUT — stop and ask
- Blocking or non-blocking reserve-time alert — decided against in § 5, badge is the whole signal.
- Any surface outside `catalog.html` (`mylist.html`, `arrivals.html`) — decided against in § 5.
- A custom popover for "Learn more" — decided against in § 5, native tooltip only.
- Lunar `title_note` classification (§ 1) — related gap, not this feature.
- Any change to the existing F117/F120 rejected-badge mechanism — this is a new, earlier signal, not a
  replacement.
- Partial-fulfillment semantics — explicitly deferred per CLAUDE.md, product-scoping call, no finding ID.
  This feature doesn't touch fulfillment state, only pre-reservation awareness; keep it that way.

---

## 7. Runbook

**S1 — schema.** `docs/sql/f132-order-requirement.sql` — additive nullable `catalog.order_requirement
text`, no CHECK (open-set distributor values, not an app enum). > **PAUSE → Rick**, staging only.
Production is a separate, later, explicitly-requested run. **APPLIED 2026-08-20 (Rick)** — verified
live: 0 non-null rows over 9,589 total, matching "no backfill" by design. **Gate V1 GREEN.**

**S2 — import.** `parseOrderRequirement()` + `parseLunarVariantRestriction()`, both scripts
(`import.js`, `import-staging.js`, private scripts repo). PRH passes through a real ratio, `'Order
All'`/blank → `null`. **Lunar corrected same day** (§ 1) — passes through a `VariantType` ratio,
`'open order'` (any casing)/`'Standard'`/`'BLANK'`/`'Unlock'`/blank → `null`; `variant_type` itself
untouched. Unit-tested in `test/catalog-key-shape.test.mjs` (186 → 198 → 210 tests across the two
commits, both scripts green). **Built and committed (`e57ade4`, then `0f5d9ae` for the Lunar
correction) 2026-08-20.** **Gate V2 GREEN.**

**S3 — UI.** `buildComicCard()` (`app.js:1748`) reads `comic.order_requirement`, renders
`.restriction-badge` (bottom-left of the cover, amber, native `title=` tooltip carrying Rick's exact
copy + the ratio). `.restriction-badge` CSS in `style.css`. Catalog-only by construction (§ 5).
**Built 2026-08-20, real-browser-verified same day (spec 20, below) — badge renders with the correct
tooltip copy + ratio, no badge on an unrestricted card, and it coexists with `reserved-indicator`
without clobbering it.** **Gate V3 GREEN.**

**S4 — Playwright.** `20-restricted-variant-badge.spec.ts` (local-only, scripts repo) — seeds a
restricted PRH row (`order_requirement: '1:10'`) and an unrestricted one, asserts the badge/tooltip
render only on the restricted card, and that reserving the item doesn't clobber or hide the badge.
`seedCatalogRow()` fixture extended with an `orderRequirement` option. **3/3 GREEN 2026-08-20**,
after one fixture-side fix found on the first post-migration run: the restricted seed row correctly
uses `variant_type: 'Variant Title'` (matching every one of the 133 real restricted PRH rows, § 1)
— but `catalog.html`'s `#filter-variants` defaults to "Standard Covers," which hides it. Not a
product bug; the spec now selects "All Covers" before searching, same real UI a customer would use
to see restricted variants at all. **Gate V4 GREEN.**

**S5 — the real import.** Moved up from the original ~Sept 7–10 estimate. Rick ran
`import-staging.js` **2026-08-21** against the existing catalog files (skipping shipment files —
catalog-refresh step only, which is the step that writes `order_requirement`). **Confirmed live**:
real restricted rows now carry the ratio (e.g. `ARCHIE VS THE TERMINATOR #1 CVR L INC 1:10 BILL
GALVAN PENCILS VAR`, Lunar, `order_requirement: '1:10'`) — verified by direct query, not assumed.
**Gate V5 GREEN.**

**S6 — hover-stacking fix (found via Rick's real-browser test, same day).** Rick reported the badge
"hides when mouse hovers over title box" and no tooltip appearing. Root-caused with data, not
theory: `document.elementFromPoint()` at the badge's screen position returned the `<img>`, not the
badge, during hover — confirmed visually with before/after screenshots. `.comic-card:hover
.comic-cover img { transform: scale(1.03) }` creates a new stacking context on hover; with no
`z-index` on the badges, the (later-in-DOM) image painted above them, which explains **both** of
Rick's reports as one mechanism — the image visually covered the badge, and it also captured the
hover, so the badge's `title=` tooltip never triggered. Fixed with `z-index: 2` on
`.distributor-badge`/`.reserved-indicator`/`.restriction-badge` (`style.css`, commit `3b345bf`) —
pre-existing on all three, not introduced by F132, just surfaced by it. Re-verified after the fix:
`elementFromPoint` now returns the badge itself. Playwright regression added (spec 20, 4th test) so
this can't silently regress again. **Gate V6.**

**S7 — mobile "Learn more" (§ 5's flagged revisit, triggered same day).** Rick: the native tooltip
"does not work on mobile touch screens" — exactly the gap § 5 accepted knowingly and flagged for
revisit. Fix reuses the existing detail modal (`openModal()`, `catalog.html`) rather than building a
new popover: it already opens on a real click/tap on both mobile and desktop. Added
`#modal-restriction-notice` (shown when `comic.order_requirement` is set, same copy as the tooltip)
and `.restriction-notice` CSS matching the existing amber "restricted" color language. Commit
`704820e`. Playwright coverage added (spec 20, 5th/6th tests): notice shows with correct copy+ratio
on a restricted title, hidden on an unrestricted one. Regression-checked against specs 02/14 (the
other modal-heavy paths) — no impact. **Gate V7.**

---

## 8. Verification gates

| Gate | Assertion | Status |
|---|---|---|
| **V1** | `order_requirement` column live on staging, matching `docs/sql/f132-order-requirement.sql`'s post-DDL checks (type/nullability, no CHECK, zero non-null rows) | **GREEN 2026-08-20 (Rick)** — 0 non-null / 9,589 total |
| **V2** | Both import scripts' unit suite green with the F132 additions; PRH/Lunar key-shape parity holds | **GREEN 2026-08-20** — 210/210, `0f5d9ae` |
| **V3** | Badge renders only when `comic.order_requirement` is truthy; tooltip carries Rick's exact copy + the ratio; does not collide with `reserved-indicator`/`foc-locked-indicator`/`distributor-badge` | **GREEN 2026-08-20** — real-browser check via spec 20 |
| **V4** | Spec 20 green (3/3): restricted card shows badge, unrestricted card doesn't, badge survives a reserve | **GREEN 2026-08-20** — 3/3 |
| **V5** | Real import run: non-null `order_requirement` count > 0 on real data | **GREEN 2026-08-21 (Rick)** — confirmed via direct query on real restricted rows |
| **V6** | Badge stays visually on top AND reachable (native tooltip fires) during `.comic-card:hover` | **GREEN 2026-08-21** — root-caused, fixed (`3b345bf`), re-verified, Playwright regression added (spec 20, 4/4) |
| **V7** | Detail modal shows the restriction disclosure (tap-accessible) when `order_requirement` is set, hidden otherwise | **GREEN 2026-08-21** — commit `704820e`, spec 20 6/6, regression-checked against specs 02/14 |

---

## 9. Completion criteria

- [x] V1 — migration applied and verified live on staging (Rick, 2026-08-20)
- [x] V2 — import-script unit suite green (210/210, `0f5d9ae`, includes the Lunar correction)
- [x] V3 — real-browser check of the badge/tooltip on staging (spec 20, 2026-08-20)
- [x] V4 — Playwright spec 20 green (3/3, 2026-08-20)
- [x] V5 — real import spot-check (Rick, 2026-08-21 — real restricted rows confirmed live)
- [x] V6 — hover-stacking bug found via real-data testing, root-caused, fixed, re-verified (2026-08-21)
- [x] V7 — mobile "Learn more" via the detail modal, § 5's flagged revisit, triggered (2026-08-21)
- [x] `docs/technical-reference.md` § 4.3 `order_requirement` note updated from "Not yet live"
- [x] `CLAUDE.md` § Open findings F132 line updated
- [x] This doc's `**STATUS:**` line advanced to STAGING COMPLETE (not COMPLETE — no production run
      requested; that stays a separate, later, explicit decision)

**Staging build + verification done 2026-08-20–21**, including a same-day data-survey correction
(§ 1, Lunar), a same-day UI bug found by Rick testing real data and fixed same session (§ 7 S6), and
§ 5's explicitly-flagged mobile-tooltip revisit, also triggered the same session (§ 7 S7).
V1–V7 all green: migration applied, both distributors' halves built, real import run confirms real
data, hover-stacking bug fixed and covered by regression. Production is out of scope for this doc
entirely until Rick explicitly asks for a
promotion.
