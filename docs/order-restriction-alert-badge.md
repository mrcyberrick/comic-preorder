# Ordering-restriction alert + badge — warn customers before they reserve a limited-ratio variant

**STATUS:** NOT STARTED | staging=— | prod=— | findings=— (candidate: next free ID F132, not yet claimed)

**Origin:** Rick's request, 2026-08-20. Today a title PRH restricts (`OrderRequirement != 'Order All'`,
shown in the UI as a ratio like `1:10`) can be reserved by any number of customers with no signal
that the store may not actually get a copy. If the distributor doesn't allocate one, the title ends
up `rejected` at order time (existing F117/F108 mechanism) — the customer finds out only after the
fact, via the same badge used for ordinary rejections. This doc scopes a **proactive** warning at
reservation time, ahead of that outcome, per Rick's two asks:

1. Alert PRH titles with ordering restrictions ("availability subject to distributor restrictions").
2. Badge restricted/incentive variants in the catalog, with a "Learn more" link surfacing: *"This is
   a restricted variant. Your reservation is noted, but fulfillment depends on distributor rules."*

This is a scoping doc only — no code has been written. Nothing here is committed to a sub-deploy;
CLAUDE.md's Current Migration Phase is "none" (Phase 5 closed, Phase 6 stub-only), so this doc is
what makes the work real enough to execute in a dedicated session, per the Session Opening Protocol.

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

## 5. Open questions for the scoping session (not resolved here)

- Blocking vs. non-blocking alert (§ 4.2).
- Tooltip vs. popover for "Learn more," given mobile has no hover (§ 4.3).
- Does the badge/alert also belong on `mylist.html` and `arrivals.html`, or catalog-reserve-time only?
- Claim finding ID F132 for this gap, or leave it doc-only (no finding) like `subscription-reserved-
  suggestions.md`?
- Confirm the "no backfill" reasoning in § 3 explicitly with Rick before building.
- Lunar `title_note` follow-on (§ 1) — separate finding, or fold into a later phase of this feature?

---

## 6. Scope

### IN (once scoped)
`catalog.order_requirement` migration · PRH import parsing (both scripts) + unit tests · badge on the
shared card renderer · reserve-time alert · "Learn more" disclosure · Playwright coverage.

### OUT — stop and ask
- Lunar `title_note` classification (§ 1) — related gap, not this feature.
- Any change to the existing F117/F120 rejected-badge mechanism — this is a new, earlier signal, not a
  replacement.
- Partial-fulfillment semantics — explicitly deferred per CLAUDE.md, product-scoping call, no finding ID.
  This feature doesn't touch fulfillment state, only pre-reservation awareness; keep it that way.

---

## 7. Completion criteria

Not applicable yet — this is a scoping doc. A future execution session fills in a runbook (§-numbered
steps + verification gates, per the `f115-arrival-truth-persistence.md` template) once the open
questions in § 5 are answered.
