# F115 — persist the reservation arrival outcome (Option B), bundled with the September import pre-flight

**STATUS:** IN PROGRESS | staging=S2 migration APPLIED 2026-08-18 (docs/sql/f115-arrival-outcome.sql, verified: column + CHECK constraint + all-NULL confirmed live) | prod=— | findings=F115,F110,F122,F123
**Session note (2026-08-18):** September catalog files not yet present (entry condition (b) —
see session prompt). This pass does S2/S3/S4/S7 only; S1/S5/S6 (the real import pre-flight,
live run, and backfill) are held for the ~Sept 7–10 import window.

**Decision record.** Decided 2026-08-18 in `docs/f92-policy-audit-and-f115-arrival-truth.md`
Part B, then scoped 2026-08-18 with Rick's four implementation answers:

1. **Option B — persist the outcome.** Not A (an arrival check inside
   `auto_fulfill_past_on_sale()`, which trades a visible wrong "arrived" for an invisible stuck
   "still coming"), not C (customer-copy-only).
2. **Tri-state**, not boolean — `arrived` / `not_arrived` / `unknown`.
3. **My List is unchanged.** The customer sees exactly what they see today. Only the internal
   record improves. "Never arrived" is staff-only.
4. **Backfill the 28/23 as `unknown`.**
5. **Bundled with the September import pre-flight** — one session, because both touch `import.js`
   Step 9 and the September import is the first new-month run for F110/F122/F123.

**Supersedes** the scoping-only version of this document (2026-08-18). § 2's open questions are now
answered and appear as § 3 design.

---

## 1. The mechanism this replaces

Full diagnosis: `docs/technical-reference.md` § 13 F115 — not restated here. In one paragraph:
`auto_fulfill_past_on_sale()` marks a reservation `fulfilled = true` once its on-sale date passes,
with no arrival check. A title never ordered and never arrived is closed on schedule,
indistinguishable from one that arrived. `reportUnverifiedFulfillments()` (2026-08-04) prints the
at-risk titles at import time and **nothing persists it**.

---

## 2. Why bundling is right, and the one risk it carries

Both halves touch `import.js` / `import-staging.js` Step 9, and the ~Sept 7–10 import is the first
genuinely-new-month run for **F110** withdrawal detection (gated on `isNewMonth`, never yet fired
on real data), **F123**'s key-shape fix, and **F122**'s drift classifier. Shipping F115 separately
would mean editing Step 9 twice in three weeks and another full cycle of unrecorded outcomes.

**The risk this creates, stated plainly:** the monthly import is the highest-consequence recurring
operation in the system, and this bundles a *new write* into the same cycle as three fixes having
their first real run. If something goes wrong it will be harder to attribute. **Mitigation is
sequencing, not hope** — § 4 runs the pre-flight verification of F110/F122/F123 **first**, on a dry
run, and only then adds the F115 write. If the pre-flight is not clean, **F115 does not ship this
cycle** and the import proceeds without it. Do not let the bundle become a reason to rush either half.

---

## 3. Design

### 3.1 Schema — tri-state, on `preorders`

A nullable column on `preorders`, not a side table: the fact is one-per-reservation, has no history
worth keeping, and every consumer already loads `preorders`. A side table would add a join to the
admin gather that F113 just finished paginating.

```
arrival_outcome  text NULL  CHECK (arrival_outcome IN ('arrived','not_arrived','unknown'))
```

**NULL means "not yet judged"** and is distinct from `'unknown'`, which means "judged, and the
evidence does not settle it." That distinction is the whole point of the tri-state — do not collapse
them. Every row is NULL until an import judges it.

**Verify column names against § 4.5 before writing any SQL** (CLAUDE.md § SQL authoring rules).
Migration goes in `docs/sql/` with a `-- STATUS:` line, per F105.

### 3.2 Import — Step 9 writes instead of printing

`reportUnverifiedFulfillments()` becomes a write. For each reservation the auto-fulfil pass is about
to close:

- shipment evidence present (the F76 three-key match, as `hasShipmentEvidence()` already does) →
  `'arrived'`
- no shipment evidence → **`'unknown'`**, never `'not_arrived'`

**`'not_arrived'` is never written by the import.** A missing `weekly_shipment` row is not proof of
non-arrival (F84's label-inversion history; invoices that miss a line; books handed over the
counter). The value exists for a human to set deliberately once someone has actually established it.
Writing it automatically would recreate F115 with a new label — an untrue statement, persisted.

Keep the printed report as well as the write. It is how the operator sees the cycle.

### 3.3 Admin surface — reuse F116's existing state

`admin.html`'s `computeBackorderRisk()` already renders a staff-facing "Never arrived" state. Feed it
from the column instead of recomputing, and leave the label alone. Staff-only is the existing
precedent and matches decision 3.

### 3.4 Customer surface — deliberately nothing

`mylist.html` is **not changed**. Decision 3: the customer sees exactly what they see today.
Record this in the plan's completion criteria as a *deliberate no-change* so a later session does
not read the silence as an oversight and "finish" it.

### 3.5 One-time production backfill — `unknown`

The 28 reservations / 23 titles F115 measured get `arrival_outcome = 'unknown'`. Not `'not_arrived'`
— the shipment gap is an upper bound, not a confirmed failure count, and asserting otherwise in the
database is the exact defect being fixed. **Re-measure the set at execution time; do not reuse the
2026-08-04 numbers.** F122's repairs and three imports have run since, so the count will differ —
if it comes back wildly different (say < 15 or > 45), stop and ask rather than proceeding.

---

## 4. Runbook

Sequenced so the import pre-flight can pass or fail **before** anything new is added to it.

**S1 — pre-flight the September import, no F115 code in the tree.** Dry run (`--no-write`) against
the real September files. Confirm: F123's key-shape fix holds (a real run upserts every record, no
`PGRST102`, no "N failed"); F110's withdrawal detection fires on `isNewMonth` and its set difference
returns a *plausible* list, read by eye; F122's `classifyReservedDateDrift()` separates corrected
from stranded. **Gate V1.** If any of this is not clean, **stop — F115 waits for the next cycle**
and the import proceeds on its own.

**S2 — schema.** Migration file in `docs/sql/`, run on **staging** first. > **PAUSE → Rick** for
both environments. Additive and nullable, so it is safe to land ahead of the code.

**S3 — import write.** `reportUnverifiedFulfillments()` writes per § 3.2, in both scripts. Extract
the judgement into a pure function and **unit-test it in the scripts repo** — the suite is at 172
and this is exactly the shape that suite is good at. **Gate V2.**

**S4 — admin surface.** Feed F116's existing state from the column. **Gate V3.**

**S5 — the real September import.** Run it for real, with the write live. **Gate V4.**

**S6 — backfill.** Re-measure, then set `unknown` on the surviving set. Staging, then
> **PAUSE → Rick** for production. **Gate V5.**

**S7 — Playwright.** Coverage for the admin state. Targeted while iterating; full suite once as the
gate (~17 min, 126 tests baseline). **Gate V6.**

---

## 5. Verification gates

| Gate | Assertion | Why this one |
|---|---|---|
| **V1** | Sept dry run clean on all three of F110 / F122 / F123 | The bundle's precondition. A red here means F115 does not ship this cycle |
| **V2** | The judgement function returns `arrived` **only** on a three-key shipment match, and `unknown` otherwise — **never `not_arrived`** | The single most important assertion here: it is the guard against persisting an untrue statement |
| **V3** | A seeded `unknown` row renders the staff "Never arrived" state; an `arrived` row does not | The surface actually reads the column |
| **V4** | After the real import, spot-check ≥ 3 rows against the printed report — the column agrees with what the operator was shown | Report and record must not diverge; two sources of truth is how F115 started |
| **V5** | Backfilled set is **re-measured**, count stated, all set to `unknown`, zero set to `not_arrived` | § 3.5 |
| **V6** | `mylist.html` byte-unchanged | § 3.4's deliberate no-change, provable rather than asserted |
| **V7** | Full suite green; counts recorded | Standard |

---

## 6. Scope

### IN
Schema migration (both environments) · import write in both scripts + unit tests · admin surfacing ·
one-time backfill · Playwright coverage · the September import pre-flight (F110/F122/F123).

### OUT — stop and ask
- **Any `mylist.html` change.** Decision 3. If it looks like it needs one, that is a finding.
- Writing `'not_arrived'` anywhere automatically.
- Changing `auto_fulfill_past_on_sale()` itself — Option A was **rejected**; the function keeps
  closing on schedule and the column records what actually happened. Do not "improve" this.
- F108's reconciliation question. The column may one day feed it; that is not this session.

---

## 7. Completion criteria

- [ ] V1–V7 green, each with recorded output
- [ ] Migration applied to both environments, `-- STATUS:` line filled in
- [ ] Both import scripts updated, committed **and pushed** to the scripts repo (verify with
      `git log origin/main`; a commit that only exists locally has bitten this project before)
- [ ] Backfill count re-measured and stated; zero rows set to `not_arrived`
- [ ] `mylist.html` unchanged, verified by diff
- [ ] § 13 F115 flipped to RESOLVED with the date; CLAUDE.md's open-findings row removed
- [ ] This doc's STATUS token flipped — **check it before closing; the last three sessions all
      forgot** (`/preflight` check 7's findings cross-check now catches exactly this)
- [ ] `/wrap-up` produced

---

## 8. Rollback

Additive nullable column — drop it, or leave it unread. The import write is revertible in the
scripts repo. The backfill is a single UPDATE over a known id set; capture those ids **before**
running it so the reverse is exact. Nothing customer-facing changes, so a rollback is invisible to
customers by construction.

---

## References

- `docs/technical-reference.md` § 13 — **F115** (diagnosis, measurement, mitigation history),
  **F116** (the staff state this feeds), **F84** (why absent shipment evidence is not proof of
  non-arrival), **F110**/**F122**/**F123** (the pre-flight), **F76** (the three-key match),
  **F105** (why the migration carries a STATUS line).
- `docs/f92-policy-audit-and-f115-arrival-truth.md` § 3 — the decision interview.
- `CLAUDE.md` § Monthly Import Script Behavior, § SQL authoring rules.
