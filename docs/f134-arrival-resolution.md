# F134 — resolving "Never arrived": panel exits, and an admin resolution control

**STATUS:** NOT STARTED | staging=— | prod=— | findings=F134,F115
**Status:** **PLANNED — not started.** Written 2026-08-21 from the first production run of the
F115 panel and Rick's ground truth on all five rows.
**Target:** staging first. Production on Rick's explicit call, per session.
**Two parts, deliberately separable.** Part 1 is a one-line bug fix with no schema and no product
decisions — it can ship on its own, today. Part 2 carries a migration, an admin control and a
customer-facing surface. **Do not let Part 2's size delay Part 1.**
**Last verified against live:** 2026-08-21 — all five panel rows confirmed
`fulfilled=true, arrival_outcome='unknown'` on production; `0626AC0537` confirmed to have **zero**
`weekly_shipment` rows by UPC, item code and both catalog ids; 369/2,021 reservations multi-copy.

---

## 1. What happened

The first production import to write `arrival_outcome` produced five Never Arrived rows. None of
them could be cleared by any action available in the app. Rick's ground truth:

| Title | Code | Reality | System knows? |
|---|---|---|---|
| SILVER SURFER #6 FACSIMILE VARIANT | `75960621489100116` | **rejected** (restricted variant) | **yes** — ledger |
| Star Trek: Last Starship #10 RI (10) | `82771403458501031` | **rejected** (restricted variant) | **yes** — ledger |
| TMNT #21 Cover A | `82771403315102111` | arrived — **one-off shipment, never imported** | no |
| Avengers: Secret Wars Premier | `9781302970291` | arrived — **one-off shipment, never imported** | no |
| ARCHIE COMICS DIGEST #7 | `0626AC0537` | believed shipped; **no shipment row anywhere** | no |

Two of five were already known to the system and still nagged. That is the bug. Three of five were
known only to Rick, with no way to tell the system. That is the missing feature.

---

## 2. Root cause

`neverArrivedFromFulfilled()` has no exits:

```js
.filter(p => p.fulfilled && p.arrival_outcome === 'unknown'
             && p.catalog?.foc_date && !p.catalog?.withdrawn_at)
```

The *unfulfilled* path directly above it has three — `ledgerNetQty(...) > 0`, `ledgerRejected(...)`
(F129), `hasShipmentEvidence(...)`. The fulfilled path inherited none of them. Consequences:

- a recorded rejection does not clear the row
- a later-imported invoice does not clear the row
- **the import never re-judges it** — `reportUnverifiedFulfillments()` selects `fulfilled=eq.false`
- nothing in the app writes `arrival_outcome`, so **`'not_arrived'` is unreachable**

The design note says the column is read rather than recomputed because "there is nothing later to
reconcile it against." A subsequently-imported invoice is exactly such a thing, and it is three of
the five cases here.

---

## 3. Part 1 — the exits (ships alone)

```js
.filter(p => p.fulfilled && p.arrival_outcome === 'unknown'
             && p.catalog?.foc_date && !p.catalog?.withdrawn_at
             && !hasShipmentEvidence(p.catalog)
             && !ledgerRejected(p.catalog.distributor, exportCode(p.catalog, p.catalog.distributor)))
```

Reuses existing helpers, no new logic, no schema. Clears the two rejected titles immediately and
makes a later invoice import clear the other three automatically — which is what makes F135's
import path work retroactively at all.

**Do not also add a `ledgerNetQty > 0` exit here.** On the unfulfilled path it means "ordered, so
not yet a failure." On a *fulfilled* row it would mean "we ordered it, therefore it arrived", which
is precisely the false inference F115 exists to stop.

---

## 4. Part 2 — the resolution control

### 4.1 Schema

```sql
-- widen from ('arrived','not_arrived','unknown')
CHECK (arrival_outcome IN ('arrived','not_arrived','damaged','unknown'))
```

| Value | Meaning | Writer |
|---|---|---|
| `arrived` | confirmed received (the one-off-shipment case) | admin, manual |
| `not_arrived` | human-established non-arrival | admin, manual |
| `damaged` | arrived but unusable | admin, manual |
| `unknown` | no evidence at judgement time | import only |
| `NULL` | not yet judged | — |

**`'damaged'` is a deliberate addition, not a convenience.** A damaged book *did* arrive, so
`'not_arrived'` is false; the customer cannot have it, so `'arrived'` is a lie. Squashing it into
either is exactly the false confidence the tri-state was chosen over a boolean to avoid.

Migration goes in `docs/sql/` with a `-- STATUS:` line (F105). Widening a CHECK is additive — no
existing row can violate it — so it is safe to land ahead of the client.

### 4.2 The control

Admin-only, on the Order Follow-Up panel, on each Never Arrived row: **Received · Didn't arrive ·
Damaged**. Writes `arrival_outcome` and nothing else. Any value other than `'unknown'` drops the
row out of the filter, so no additional clearing logic is needed.

RLS already permits it — `admins manage tenant preorders` is an ALL policy checking the row's
`tenant_id` (§ 7.1), and F127's RESTRICTIVE policies gate on active status, which an admin passes.
No policy change.

### 4.3 Customer visibility — the settled rule

> **The customer sees human-confirmed outcomes. Auto-judged `'unknown'` stays staff-only.**

This reconciles Rick's two decisions rather than reversing either: an unresolved automatic
judgement is not something to tell a customer, but a fact a human established is. `not_arrived` and
`damaged` slot into `mylist.html`'s existing chain, above the ordered branch where `withdrawn` and
`rejected` already sit:

```
withdrawn → rejected → not_arrived / damaged → ordered → FOC-locked
```

`'arrived'` needs no copy — it falls through to the existing "✓ Order placed".

**This supersedes F115's gate V6 (`mylist.html` byte-unchanged).** That gate was correct for F115's
own scope. Mark it superseded in `docs/f115-arrival-truth-persistence.md` **in this session**, or a
future session will read it as binding and protect a decision already revisited.

### 4.4 The stated limit

A *state* cannot express "2 of 3 arrived", and **369 of 2,021 production reservations (18%) are
multi-copy** (236 of them 3+). So on those rows `'damaged'` means *some* damage, not all, and a
partial shortage is not representable at all — that is **partial fulfilment**, still deliberately
out of scope (CLAUDE.md § Known Out-of-Scope).

**Keep UI copy free of implied counts** — "Damaged", never "Damaged (1)" — for the same reason
`'unknown'` is not `'not_arrived'`. If quantities are ever wanted, that is `received_quantity` /
`damaged_quantity` and a real partial-fulfilment scoping session, not an enum widening.

---

## 5. Scope

### IN
Part 1 exits · CHECK widening migration · admin resolve control · My List copy for
`not_arrived`/`damaged` · F115 V6 marked superseded · Playwright coverage for both parts.

### OUT — stop and ask
- **Quantities.** No `received_quantity`, no `damaged_quantity`, no partial fulfilment.
- **Overage.** Extra copies belong to no customer — they are shelf stock, and recording them on a
  `preorders` row misattributes them. Overage belongs at shipment/ledger level (shelf-copy domain).
- **Any `arrival_outcome` write from the import beyond `'arrived'`/`'unknown'`.** The import must
  never write `'not_arrived'` or `'damaged'` — both require a human (F115 § 3.2).
- **Fixing the one-off-shipment import path.** That is **F135**.

---

## 6. Verification gates

| Gate | Assertion |
|---|---|
| **V1** | A fulfilled row whose code is `ledgerRejected()` does **not** appear in Never Arrived; the two real production titles clear |
| **V2** | A fulfilled `'unknown'` row gains a `weekly_shipment` row → disappears from the panel on next render, with no re-import and no manual action |
| **V3** | Widened CHECK: `'damaged'` accepted, a bogus value rejected **23514** |
| **V4** | Each control writes exactly its value and the row leaves the panel; no other column changes |
| **V5** | My List shows the `not_arrived` / `damaged` notice **above** the ordered branch — a fulfilled row with `damaged` must not read "✓ Order placed" |
| **V6** | A row at `'unknown'` shows the customer **nothing new** — staff-only, per § 4.3 |
| **V7** | Full suite green, counts recorded |

V1 and V2 are Part 1 and must be observed failing against the pre-fix code first — both are
reachable with a seeded fixture, and an assertion never seen red is decoration (F105).

---

## 7. Completion criteria

- [ ] V1–V7 green, each with recorded output
- [ ] Part 1 shipped (may precede Part 2)
- [ ] Migration applied both environments, `-- STATUS:` filled in
- [ ] F115 plan doc: **V6 marked superseded**, with the reason
- [ ] § 13 F134 flipped to RESOLVED; CLAUDE.md row removed
- [ ] This doc's STATUS token flipped
- [ ] `/wrap-up`

---

## 8. Rollback

Part 1 is a pure predicate change — `git revert`. The CHECK widening is additive; reverting requires
no `'damaged'` rows to exist, so revert before first use or not at all. Manual writes are ordinary
column updates, reversible by id.

---

## References

`docs/technical-reference.md` § 13 — **F134**, **F129** (same shape, other path), **F115** (created
this surface; V6 superseded here), **F116** (the label reused), **F117**/**F120** (ledger rejection
and the customer badge), **F132** (preventive half only), **F76**/**F84** (three-key match; absent
evidence is not proof), **F135** (the import path). `docs/f115-arrival-truth-persistence.md`.
