# Order Builder — decouple "record the order" from "download the file"

**Owning plan:** `docs/order-loop-closure-f108.md` § 8 *"Deferred to its own
session"* — the design there is settled (Rick, 2026-08-06) and is not reopened
here. This document adds only the runbook, gates and completion criteria that
the Definition of Done requires.

**Findings:** **F108** (§ 4.2 capture point), **F102** (the remainder quantity
control this protects), **F117** (signed ledger — zero = rejected).
Referenced from the F121 process map as **W2/W3**.

**Status:** Planned 2026-08-08.
**Target:** **staging only.** Production promotion on Rick's explicit request.
**Branch:** `feature/order-builder-record-split`
**Last verified against live code:** `admin.html` @ `ab23636`, 2026-08-08.

---

## 1. Why this is next, ahead of the F121 restructure

Rick has **never used the Order Builder for a monthly cycle** — the export-bar
buttons became the Order Builder on 2026-08-03, and his next monthly cycle is
its first real use. Two defects are waiting on that path, and one of them is
silent and costs money.

---

## 2. The two defects

### 2.1 `order_type` is hardcoded `'adhoc'` — silent, and it breaks the *next* cycle

`admin.html:2106` writes `order_type: 'adhoc'` for every code confirmed on
export. The comment above it states the assumption plainly: *"this is the ad-hoc
path, not the reviewed monthly-cycle confirmation"*. **That assumption is wrong
in practice** — Rick runs the monthly cycle through this modal.

The consequence is not cosmetic. `classifyForExport()` (`:931`) routes
`order_type === 'adhoc'` matches into `buckets.adhocOrdered`, which is
**auto-excluded**, rather than `buckets.alreadyOrdered`, which is the
"your call" bucket carrying **F102's remainder-defaulted quantity control**.

So: record a monthly cycle today, and next month every one of those codes is
silently dropped from the export decision — the exact control that exists
because PRH ended up holding 12 copies against 7 reservations.

**Fix:** the Order Builder writes `'monthly'`. Mark Ordered keeps `'adhoc'`
(genuine ad-hoc path). **No change to `classifyForExport()`** — the routing is
already correct; only the value written was wrong.

### 2.2 Confirm-on-export asks before the answer exists

The prompt fires immediately after the download. But the file is not the order:
Rick takes it to the distributor's site, pastes it, submits — **and only then**
learns which titles were rejected for failing order requirements. The prompt
asks *"record these as ordered?"* at a moment when the honest answer is "I don't
know yet."

This is F101 § 4.2's original principle reasserting itself — *generating a file
is not proof of submission*. § 3.4 reversed it for ad-hoc (one or two titles,
outcome known immediately); the reversal does not survive the monthly cycle.

**Fix (§ 8's agreed design):** split the action.
- **Generate & Download** — downloads, no prompt.
- **Record submitted order** — a second step showing the export set with
  per-title checkboxes. **Ticked = ordered at that quantity. Unticked =
  rejected**, writing the zero row F117 defined.

Semantically exact: everything in the set *was* submitted, so unticking means
the supplier refused it. It also produces every rejection row in one pass,
instead of a per-title Mark Ordered modal for each — which Rick assessed as
*"may not flow naturally"*.

**No persistence needed.** The export set is re-derivable from the cycle
selection the modal already computes, so coming back later and re-selecting the
same cycles reproduces it exactly.

---

## 3. Scope

### IN
1. `order_type: 'monthly'` at the Order Builder write site.
2. Two-step Order Builder: select/download → record.
3. Rejection rows (`quantity: 0`) written for unticked titles.
4. Playwright coverage for both.

### OUT — stop and ask
| Not touched | Why |
|---|---|
| `classifyForExport()` routing | Already correct; only the written value was wrong. Changing it would mask 2.1 rather than fix it. |
| Mark Ordered | Stays `'adhoc'` — the genuine ad-hoc path, per § 8. |
| `isNewMonth` import confirmation | The backstop, unchanged (scripts repo). |
| **`catalog_month` on Order Builder writes** | Hardcoded `currentCatalogMonth` while Mark Ordered files under the title's own month — the two writers disagree (F121 process map § 5.5 W2). **Deliberately deferred: for a code consolidated across months (F111) "the title's own month" is ambiguous, so picking one is a design decision that is Rick's, not the agent's.** Low harm today — `ledgerMatchesFor()` keys on distributor + code and ignores `catalog_month`. See § 7. |
| `get_ordered_codes()` | Unaffected — sums quantity, indifferent to `order_type`. |

---

## 4. Changes

`admin.html` only. **Client-only — no schema change, no migration, no RLS
change.** `order_submissions.order_type` already accepts `'monthly'`.

| # | Location | Change |
|---|---|---|
| 1 | Modal markup (~`477–481`) | Wrap the three existing panels in `#ob-step-select`; add `#ob-step-record`; split the footer into `#ob-foot-select` and `#ob-foot-record` |
| 2 | Builder state (~`1696`) | Add `builderStep` and `recordSelections` |
| 3 | `renderOrderBuilderResults()` | Unchanged output; called only in the select step |
| 4 | **New** `renderRecordPanel()` | Builds from `buildExportRows()` — the same function the file uses, so the record list and the file can never disagree |
| 5 | Generate handler (~`2052`) | Remove the `confirm()` + insert block entirely. Download only. |
| 6 | **New** record handler | Ticked → `quantity: qty`; unticked → `quantity: 0`. Both `order_type: 'monthly'`. |
| 7 | `closeOrderBuilder()` | Reset to the select step so a reopen never lands mid-flow |

---

## 5. Verification gates

Run **after** pushing and confirming the new bytes on the **plain** URL.

| Gate | Check | Pass condition |
|---|---|---|
| **V1** | Generate & Download | File downloads; **no `confirm()` appears**; ledger row count unchanged |
| **V2** | Record, all ticked | One row per export line, `quantity` = shown qty, **`order_type = 'monthly'`** |
| **V3** | Record, one unticked | That code gets `quantity: 0`; others positive; all `'monthly'` |
| **V4** | **The F102 regression this exists to prevent** | After V2, reopen the builder on the same cycle: those codes appear in **"Already ordered — your call"** with a remainder-defaulted qty, **not** silently auto-excluded |
| **V5** | Rejected code re-enters | After V3, the zero-row code is offered for export again (net 0 ⇒ falls through, `:918`) |
| **V6** | Mark Ordered unchanged | Still writes `'adhoc'` |
| **V7** | Full suite | Green |

**V4 is the gate that matters.** V1–V3 prove the mechanics; V4 proves the silent
failure is actually gone.

Fixtures torn down and **verified by live SELECT returning zero rows.**

---

## 6. Completion criteria

- [ ] § 4 changes applied, every range re-verified against disk first
- [ ] V1–V7 green
- [ ] Ledger fixtures removed, confirmed by live SELECT (0 rows)
- [ ] Real-browser check by Rick on staging
- [ ] `order-loop-closure-f108.md` § 8 updated: deferred block → Complete
- [ ] F121 process map W2/W3 marked resolved; `CLAUDE.md` line updated

---

## 7. Open — Rick's call

**`catalog_month` on Order Builder ledger writes.** Currently
`currentCatalogMonth` for every row, including codes gathered from other months
(F111). Mark Ordered files under the title's own month. Options: (a) leave —
`ledgerMatchesFor()` ignores it, so nothing reads it today; (b) newest month
among the grouped rows (F85's survivor rule); (c) the selected FOC cycle's
month. **Not decided here** — it is a real modelling choice, and § 8 did not
name it.

---

## 8. Rollback

Single feature branch, client-only, no DB change. `git revert` the merge.
Ledger rows written during testing are ordinary rows, deletable by
`created_at` window.

---

## 9. Deploy log

*(empty — not started)*
