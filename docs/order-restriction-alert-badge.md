# Ordering-restriction alert + badge — warn customers before they reserve a limited-ratio variant

**STATUS:** IN PROGRESS | staging=code built, migration PENDING (Rick-gated, see § 7 runbook S1) | prod=N/A | findings=F132

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

---

## 2. Schema

New nullable column on `catalog` (33 columns today per `technical-reference.md` § 4.3 — verify against
live before writing the migration, per CLAUDE.md SQL authoring rules):

```
order_requirement  text  NULL
```

Stores the raw ratio string (`'1:10'`, `'1:25'`, …) when PRH's `OrderRequirement` is present and not
`'Order All'`; `NULL` otherwise — including for every Lunar row (no equivalent field, so Lunar always
writes explicit `null`, same pattern as `initial_order_due` for PRH rows — **F123's key-shape rule
applies**: every batch in one upsert call needs the same key set present, or PostgREST's one-key-shape
rule breaks the batch). Additive/nullable, so — like F115's `arrival_outcome` — it's safe to land ahead
of the import-script change and inert until something reads it.

Migration goes in `docs/sql/` with a `-- STATUS:` line, staging first, Rick-gated for production.

---

## 3. Import — both scripts, PRH only

`normalizePRH()` (name approximate — verify against current scripts-repo source before editing) reads
`OrderRequirement`: write `null` when the value is blank or exactly `'Order All'`, else the literal
string. Unit-test the normalizer function directly (scripts repo suite is at 186 tests as of F115,
this is exactly its shape) — assert `'Order All'` → `null`, a ratio string → passthrough, and a
Lunar-sourced record never sets the field to anything but `null`.

**No backfill planned.** Unlike F115's `arrival_outcome` (a fact about a past reservation), this is
advisory catalog metadata tied to the *live* offering — it populates naturally on the next PRH import
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
  hover); revisit if that turns out to matter in practice.
- **Surface scope: catalog page only.** `buildComicCard()` is used exclusively by `catalog.html`
  (verified — `mylist.html`/`arrivals.html` render their own inline markup, not this function), so
  this was free: no `mylist.html`/`arrivals.html` change needed to honor the decision.
- **Finding ID: F132 claimed** — `docs/technical-reference.md` § 13, `CLAUDE.md` § Open findings.
- **No backfill confirmed** — advisory catalog metadata tied to the live offering, populates
  naturally on the next PRH import. Not challenged during scoping.
- **Lunar `title_note` follow-on: separate finding, not folded in.** Left as the doc originally
  proposed — a real gap, but its own text-classification scope, not part of F132.

---

## 6. Scope

### IN — final, per § 5
`catalog.order_requirement` migration · PRH import parsing (both scripts) + unit tests · badge (native
tooltip, no separate alert) on the shared card renderer, catalog page only · Playwright coverage.

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
Production is a separate, later, explicitly-requested run. **Gate V1.**

**S2 — import.** `parseOrderRequirement()` + normalizer wiring, both scripts (`import.js`,
`import-staging.js`, private scripts repo). PRH passes through a real ratio, `'Order All'`/blank
→ `null`; Lunar writes explicit `null` (F123 key-shape rule). Unit-tested in
`test/catalog-key-shape.test.mjs` (186 → 198 tests, both scripts green). **Built and committed
(`e57ade4`) 2026-08-20 — inert until S1 lands; do not run either script against staging/prod before
then, per the commit message's own warning.** **Gate V2.**

**S3 — UI.** `buildComicCard()` (`app.js:1748`) reads `comic.order_requirement`, renders
`.restriction-badge` (bottom-left of the cover, amber, native `title=` tooltip carrying Rick's exact
copy + the ratio). `.restriction-badge` CSS in `style.css`. Catalog-only by construction (§ 5).
**Built 2026-08-20 — inert client-side until S1 lands: `comic.order_requirement` reads `undefined`
on any row from a pre-migration `select('*')`, so the badge simply never renders. Safe to deploy to
staging ahead of the migration if convenient**, same shape as F115. **Gate V3.**

**S4 — Playwright.** `20-restricted-variant-badge.spec.ts` (local-only, scripts repo) — seeds a
restricted PRH row (`order_requirement: '1:10'`) and an unrestricted one, asserts the badge/tooltip
render only on the restricted card, and that reserving the item doesn't clobber or hide the badge.
`seedCatalogRow()` fixture extended with an `orderRequirement` option. **Written 2026-08-20 —
CANNOT RUN until S1 lands** (`seedCatalogRow`'s insert 400s with `undefined_column` against a
catalog table that doesn't have the column yet). **Gate V4.**

**S5 — the real September import.** The ~Sept 7–10 cycle is the first PRH import to actually write
non-null `order_requirement` values from production data. Spot-check a handful of the known-restricted
item codes against the live catalog page afterward. **Gate V5.**

---

## 8. Verification gates

| Gate | Assertion | Status |
|---|---|---|
| **V1** | `order_requirement` column live on staging, matching `docs/sql/f132-order-requirement.sql`'s post-DDL checks (type/nullability, no CHECK, zero non-null rows) | **PENDING — Rick** |
| **V2** | Both import scripts' unit suite green with the F132 additions; PRH/Lunar key-shape parity holds | **GREEN 2026-08-20** — 198/198, `e57ade4` |
| **V3** | Badge renders only when `comic.order_requirement` is truthy; tooltip carries Rick's exact copy + the ratio; does not collide with `reserved-indicator`/`foc-locked-indicator`/`distributor-badge` | Built, not yet real-browser-verified (needs V1 first — see spec 20) |
| **V4** | Spec 20 green (3/3): restricted card shows badge, unrestricted card doesn't, badge survives a reserve | **BLOCKED on V1** |
| **V5** | September import: spot-check ≥ 3 real restricted item codes against the live catalog page | Held for the ~Sept 7–10 window |

---

## 9. Completion criteria

- [ ] V1 — migration applied and verified live on staging (Rick)
- [x] V2 — import-script unit suite green (198/198, `e57ade4`)
- [ ] V3 — real-browser check of the badge/tooltip on staging (needs V1)
- [ ] V4 — Playwright spec 20 green (needs V1)
- [ ] V5 — September import spot-check
- [ ] `docs/technical-reference.md` § 4.3 `order_requirement` note updated from "Not yet live" once V1 lands
- [ ] `CLAUDE.md` § Open findings F132 line updated once V1–V4 close
- [ ] This doc's `**STATUS:**` line advanced to COMPLETE with the date

**Not done today.** This session built and committed the client + import-script halves (S2/S3, both
inert-safe) and wrote the migration + Playwright spec (S1/S4, both blocked on Rick applying the
migration). Production is out of scope for this doc entirely until staging V1–V5 are all green and
Rick explicitly asks for a promotion.
