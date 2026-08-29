# F115 — persist the reservation arrival outcome (Option B), bundled with the September import pre-flight

**STATUS:** COMPLETE, both environments | staging=2026-08-28 (S1–S7 all done, V1–V7 all green — see § 7) | prod=2026-08-28 (S5, real September import, write confirmed live) + 2026-08-28/29 (S6 backfill: 26 reservations / 23 titles, freshly re-measured against live production — not the stale 28/23 or 859 figures — ids captured before the write, independently verified after: orphan count dropped by exactly 26, `not_arrived` still exactly 0 tenant-wide, 3 ids spot-checked fresh) | findings=F115,F110,F122,F123. **F115 is RESOLVED, both environments** (§ 13). V1/V4 were not formally exercised against production as a separate pass (attention that day went to **F147**, found during the same import) but their substance is confirmed live either way — see § 5.
**Prod migration pulled forward to 2026-08-20**, out of the S5/S6 window and ahead of the import, at Rick's call. It is additive/nullable and no production code reads the column, so it is inert — but it **clears the promotion block** (`admin.html` on staging selects `arrival_outcome`; without the column any staging→main merge would 400 the entire admin gather — `/promote-prod` step 0b) and removes a dependency from the September session. Verified live on production with the file's own four checks; the 23514 DETAIL carried the production founding tenant_id, confirming the right project. **S5 ran 2026-08-28 (real import); S6 ran 2026-08-28/29 (backfill) — both now DONE on production, see § 7.**
**Session note (2026-08-18):** September catalog files not yet present (entry condition (b) —
see session prompt). This pass did S2/S3/S4/S7 only; S1/S5/S6 (the real import pre-flight,
live run, and backfill) are held for the ~Sept 7–10 import window. F115 is NOT resolved yet —
see § 7 for exactly what ran and what didn't. A TDZ bug in the S4 admin.html change was
introduced, caught, and fixed within this same session (staging `3dcf521` → `f61487a`) by the
full Playwright run against deployed staging — see git log for detail.
**Session note (2026-08-28) — S1/S5/S6 completed on staging, ~10 days ahead of the ~Sept 7–10
estimate.** Rick ran `import-staging.js` for real against the September files (no separate
`--no-write` dry run — the live run's own console output serves as S1's evidence instead, cross-
checked line-by-line against the database rather than trusted at face value):
- **V1 — all three preconditions confirmed clean.** F123: console-reported row counts (Lunar 1377,
  PRH 911) match both the source CSV line counts and the post-import DB counts exactly, and
  `Upserted 2288/2288` with zero failures. F110: `detectWithdrawals()` fired on `isNewMonth` and
  marked 16 titles, every one satisfying the narrowing rule (`on_sale_date >= today`, an
  unfulfilled reservation); DB state matches the console list exactly, 16-for-16. F122: console
  printed `📅 No in-store-date changes on reserved titles` — the drift classifier ran and found no
  case to separate this cycle (a clean run, not a skipped check).
- **V4 — the persisted write matches the printed report.** Only 1 reservation crossed its on-sale
  date this run (staging's dataset is small): CONAN THE BARBARIAN #34, console-reported
  "1 preorder(s) about to be auto-fulfilled; 0 with no shipment record", DB shows
  `arrival_outcome='arrived'` on exactly that row — independently cross-checked against a real
  matching `weekly_shipment` row (same `item_code`/`upc`/`catalog_id`), not just trusted.
- **V5 — backfill done and re-measured, not reusing the 2026-08-04 numbers.** Fresh count:
  **32 reservations / 30 distinct titles** with `fulfilled=true AND arrival_outcome IS NULL`
  (comparable magnitude to the original 28/23, within the doc's own "stop and ask if <15 or >45"
  bound). All 32 ids captured before writing (exact revert set, scratchpad-local, not committed).
  PATCHed to `arrival_outcome='unknown'`, verified post-write: `arrived=3, unknown=32,
  not_arrived=0`, zero `fulfilled=true` rows remain with a NULL outcome.
- **New, unrelated to F115 directly — filed as F146.** Of the 16 F110 marks, at least one
  (0826AB0593, DAREDEVIL MY MIGHTY MARVEL FIRST BOOK HC) was confirmed still live on the
  distributor's own site at the moment it was marked withdrawn — a same-month CSV-lag false
  positive, not a real withdrawal. `detectWithdrawals()`'s clear-on-reappearance half is gated
  behind `isNewMonth` alongside the mark half and doesn't need to be, so these 16 will NOT
  self-correct on any same-month refresh. See `docs/technical-reference.md` § 13 F146 — does not
  block this entry's gates, which describe the F110 *mark* mechanism working exactly as designed.
- **Residual, not yet done:** `order_deadline` was cleared for the new cycle (expected new-month
  behavior) and has not been re-set — Step 7 of `docs/monthly-catalog-refresh.md` is still owed on
  staging. Maintenance Mode is already back off (confirmed live, `false`).

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

### 3.4 Customer surface — deliberately nothing ⚠️ SUPERSEDED 2026-08-21

> **SUPERSEDED by F134 (`docs/f134-arrival-resolution.md` § 4.3).** This section and its gate **V6**
> were correct for F115's own scope — an *auto-judged* `'unknown'` should not reach a customer, and
> still does not. But F134 adds **human-confirmed** `not_arrived` and `damaged` values, and Rick
> decided 2026-08-21 that those **do** surface on My List. The rule that now governs both:
> *the customer sees human-confirmed outcomes; auto-judged `'unknown'` stays staff-only.*
> **Do not "restore" the byte-unchanged constraint below** — it describes a decision that has been
> revisited, not one that was missed.


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

| Gate | Assertion | Why this one | Status |
|---|---|---|---|
| **V1** | Sept dry run clean on all three of F110 / F122 / F123 | The bundle's precondition. A red here means F115 does not ship this cycle | ✅ **Staging 2026-08-28** — no separate dry run; verified against the real run's console + DB cross-check instead (§ status note above). All three clean |
| **V2** | The judgement function returns `arrived` **only** on a three-key shipment match, and `unknown` otherwise — **never `not_arrived`** | The single most important assertion here: it is the guard against persisting an untrue statement | ✅ 2026-08-18, scripts-repo unit suite |
| **V3** | A seeded `unknown` row renders the staff "Never arrived" state; an `arrived` row does not | The surface actually reads the column | ✅ 2026-08-18, Playwright |
| **V4** | After the real import, spot-check ≥ 3 rows against the printed report — the column agrees with what the operator was shown | Report and record must not diverge; two sources of truth is how F115 started | ✅ **Staging 2026-08-28** — only 1 row crossed on-sale this run (small dataset); spot-checked and independently confirmed against real `weekly_shipment` evidence, not just the printed report |
| **V5** | Backfilled set is **re-measured**, count stated, all set to `unknown`, zero set to `not_arrived` | § 3.5 | ✅ **Staging 2026-08-28** — 32/30, re-measured fresh, 0 `not_arrived` |
| **V6** | ~~`mylist.html` byte-unchanged~~ **— SUPERSEDED 2026-08-21 by F134, do not re-apply** | § 3.4's deliberate no-change, provable rather than asserted | ✅ 2026-08-18 |
| **V7** | Full suite green; counts recorded | Standard | ✅ 2026-08-18, 127/127 (1 confirmed-flaky retry) |

**All seven gates are green on staging as of 2026-08-28.** Production ran its real September import the same day (`catalog_month` now `2026-09`); V4's substance is confirmed live there too (`arrived=212, unknown=6, not_arrived=0`), though V1 was not formally exercised as a separate pass (attention went to F147, found during that run). **V5 is now also green on production, 2026-08-28/29**: the 859 pre-existing orphaned rows were re-measured (not reused from any prior figure), narrowed to the 26 genuinely-unproven rows per the C1 DECISION in `docs/pre-phase-6-consolidation.md` § 3.3 (771 with shipment evidence, 49 net-positive ledger, 2 recorded rejections all deliberately left NULL — see that doc for the full reasoning), backfilled to `'unknown'`, and independently re-verified: orphan count dropped by exactly 26 (859→833), `not_arrived` still exactly 0 tenant-wide, 3 ids spot-checked fresh. **F115 is now fully RESOLVED on both environments.**

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

**2026-08-18 session — entry condition (b): September catalog files not yet present.** Covered
S2/S3/S4/S7 only, per the session's own timing gate. S1/S5/S6 remained, held for the ~Sept 7–10
import window.

- [x] V2, V3, V6, V7 green, each with recorded output (2026-08-18 session)
  - V2: 186/186 scripts-repo unit tests green, incl. the explicit "never produces `not_arrived`"
    assertion (scripts repo `b629cda`)
  - V3: Playwright — a seeded `fulfilled=true, arrival_outcome='unknown'` row reads "Never arrived"
    (`data-state="neverArrived"`); a seeded `arrival_outcome='arrived'` row does not appear
    (`15-order-export-ledger.spec.ts`, test added this session)
  - V6: `mylist.html` byte-unchanged, confirmed via `git diff` before AND after this session's
    admin.html changes
  - V7: full suite **127 tests, 126 passed + 1 flaky** (`18-mobile-nav.spec.ts` mylist mobile
    search — timed out at 60s, passed in 5.1s on an isolated re-run; unrelated to this session's
    changes, `mylist.html` untouched) — scripts unit suite 186/186
- [x] Migration applied to **staging**, `-- STATUS:` line filled in (`docs/sql/f115-arrival-outcome.sql`,
      staging `9eeee0d`) — **production not yet run**
- [x] Both import scripts updated, committed **and pushed** to the scripts repo — verified via
      `git log origin/main` (`b629cda`)
- [x] Backfill count re-measured and stated; zero rows set to `not_arrived` — **DONE 2026-08-28,
      staging**: 32/30, re-measured fresh (not reusing the 28/23 figure), `arrived=3, unknown=32,
      not_arrived=0` post-write
- [x] `mylist.html` unchanged, verified by diff
- [x] **V1, V4, V5 green — DONE 2026-08-28, staging.** See § status note and § 5 gates table.
      **Staging halves of S1/S5/S6 are complete.**
- [x] **Production's real September import RAN 2026-08-28, later the same session** (`node
      import.js`, `catalog_month` 2026-08 → 2026-09). This surfaced **F147** (F110's mark logic
      flagging 519/1,571 open reservations, found and fixed same day — see technical-reference.md
      § 13) — attention went there instead of a formal V1/V4 pass against production, so those two
      gates were not explicitly exercised there the way they were on staging. **V4's substance is
      still true on production**, confirmed directly: `arrived=212, unknown=6, not_arrived=0`
      post-import — the never-`not_arrived` invariant (V2) holds live, not just in unit tests.
- [x] **Production S6 backfill — DONE 2026-08-28/29.** § 3.3 C1 of
      `docs/pre-phase-6-consolidation.md` found the predicate had drifted between design (the
      never-arrived subset, ~28 rows) and staging's executed version (the whole orphan population,
      859 rows) — on production those are not the same thing, because production carries 975 real
      `weekly_shipment` rows against staging's near-empty history. **DECISION (Rick, via the
      consolidation plan): narrow to the genuinely-unproven rows only.** Re-measured live
      immediately before the write (not reusing the 859 figure, the 28/23 figure, or any prior
      snapshot): of the 859 orphans, 771 have real shipment evidence and 51 have an order-ledger
      row (49 net-positive/ordered, 2 recorded rejections) — all 822 correctly **stay NULL**. The
      remaining **26 reservations across 23 titles** have no shipment evidence and no ledger row
      at all — these were set to `arrival_outcome = 'unknown'`. Ids captured to a local file
      *before* the write (exact revert set, per § 8). Independently re-verified afterward with
      fresh queries (not the write script's own printed output): orphan count 859 → 833 (exactly
      -26), `arrival_outcome = 'not_arrived'` still **0** tenant-wide, 3 individual ids spot-checked
      fresh. **F115's own tri-state distribution on production, post-backfill:** arrived 212,
      unknown 32 (6 from the live import + 26 from this backfill), not_arrived 0, damaged 0,
      NULL 2,404 (the 771 shipment-evidenced + 51 ledgered + rows not yet past on-sale) — sums to
      the tenant's full 2,648 preorders.
- [x] This doc's STATUS token flipped — see line 3 (**COMPLETE, both environments**)
- [x] `/wrap-up` produced this session, three times (2026-08-18 build session; 2026-08-28 session
      covering the real Sept imports on both environments plus F146/F147; this 2026-08-28/29
      session closing production's S6 backfill)

**Nothing remaining.** F115 is fully resolved on both environments.

**Gate scheduled (2026-08-18), now moot:** the S1/S5/S6 wait-for-September-files gate had no
elapsed-time condition, only an event condition (catalog files landing) — files arrived
2026-08-28, ~10 days ahead of the ~Sept 7 estimate, and staging's S1/S5/S6 ran the same day. The
one-time cloud routine `trig_01QwSJJf65mYTy2mNkTYsSKk` (was set to fire 2026-09-07) is now
superseded by this update; no action needed on it, it will simply find the work already done when
it fires.

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
