# F122 — auto-fulfill on the title's current schedule, not the joined row

**STATUS:** COMPLETE | staging=2026-08-08 | prod=2026-08-08 | findings=F122,F124

**Finding:** `docs/technical-reference.md` § 13 **F122**.
**Decision:** Rick, 2026-08-08 — **Option 1** ("judge on the newest row").
Option 2 (carry manual reservations forward on re-listing) is **not** taken here.

**Status:** **COMPLETE — applied and verified on BOTH environments 2026-08-08.**
**Target:** staging first, then production. **DDL is Rick-in-the-loop** — the
agent cannot run it (PostgREST has no SQL endpoint; it needs the SQL Editor).
**Verified against live schema:** `catalog` § 4.3 — `item_code` NOT NULL,
`on_sale_date` NULLABLE, unique key `(tenant_id, item_code, distributor, catalog_month)`.

---

## 1. The defect

`auto_fulfill_past_on_sale()` read `c.on_sale_date` off **whichever catalog row
the reservation is joined to**. `preorders.catalog_id` does not survive a
re-listing — a re-solicited title gets a new `catalog` row under the four-column
upsert key, and existing reservations keep pointing at the old one. F85's
carry-forward moves subscriber auto-reserves; **manual reservations are never
moved**.

So a re-dated title is closed against its **superseded** schedule. Live case:
MIDNIGHT X-MEN #1 (`75960621668000111`, PRH), pushed back nine weeks — May/June
rows say on-sale **2026-08-05**, the July re-listing says **2026-10-07**. The
2026-08-07 import fulfilled 5 copies / 3 customers for a book that has never
shipped, and My List's past-on-sale auto-hide would then have removed it from
their lists entirely.

---

## 2. The fix, and the one judgement call inside it

Compare against the on-sale date of the **newest listing that carries one** for
that `(tenant_id, item_code, distributor)`.

**Newest listing, not `MAX(on_sale_date)`.** F122's wording ("the latest
`on_sale_date`") is ambiguous and the two differ:

| Scenario | `MAX(on_sale_date)` | Newest listing |
|---|---|---|
| Title pushed **back** (the observed case) | correct | correct |
| Title pulled **forward** | **wrong** — keeps judging against the old later date, so it never auto-fulfils | correct |

Newest-listing is the title's *actual current schedule*, which is what this
predicate is supposed to read. **No forward-pulled titles exist on either
environment today** (§ 3 measured 0), so this choice is currently unobservable —
recorded because it will matter the first time a distributor pulls a book in.

**NULL handling preserves today's behaviour exactly:** rows with a NULL
`on_sale_date` are ignored when picking the newest listing (so a newer,
date-less row cannot blank out a known date), and a title with no non-null date
anywhere is excluded by the join and never auto-fulfils — same as
`NULL < CURRENT_DATE` before.

**Not fixed here:** **F115** (no arrival check — a never-ordered, never-arrived
title still closes on schedule). Same function, different defect.

---

## 3. Measured impact — read-only, both environments, 2026-08-08

Computed by replaying both predicates over live data without touching anything.

| | Staging | Production |
|---|---|---|
| Catalog rows | 9,586 | 11,724 |
| Unfulfilled preorders | 21 | 1,230 |
| Would fulfil under **both** (unchanged) | 0 | 0 |
| **Stops** being auto-fulfilled — the F122 bug | 0 | **3** |
| **Starts** being auto-fulfilled — regression risk | 0 | **0** |

The 3 on production are exactly the MIDNIGHT X-MEN #1 reservations Rick repaired
by hand on 2026-08-07. **Zero rows start being fulfilled**, so the change cannot
close anything early.

**Consequence for testing: staging has no divergent title**, so the fix cannot
be demonstrated there on real data — gate V2 seeds one.

---

## 4. Apply — staging first

Run `docs/sql/auto_fulfill_past_on_sale.sql` in the **staging** SQL Editor
(`CREATE OR REPLACE`, so it replaces in place).

**Before replacing, confirm the live body is the one this replaces** — the file
is authoritative only if nothing was hot-patched since:

```sql
SELECT prosrc FROM pg_proc
 WHERE proname = 'auto_fulfill_past_on_sale';
```

Expect a body whose predicate is `c.on_sale_date < CURRENT_DATE`. **If it is
anything else, stop and report** — something was changed outside the repo.

---

## 5. Gates

| Gate | Check | Pass condition |
|---|---|---|
| **V1** | Grants survived the replace | `SELECT proacl FROM pg_proc WHERE proname='auto_fulfill_past_on_sale';` shows `service_role=X`, no PUBLIC |
| **V2** | **Seeded re-dating on staging** — one title, two catalog months, old month's date in the past, new month's in the future; one preorder pointing at the OLD row | Calling the function leaves that preorder `fulfilled = false`. Under the old body it would flip to `true`. |
| **V3** | Normal case still fulfils | A seeded single-month title with a past on-sale date and one preorder → `fulfilled = true` |
| **V4** | NULL-safe | A seeded title with `on_sale_date IS NULL` → untouched |
| **V5** | Idempotent | Second call returns 0 and changes nothing |
| **V6** | Fixture teardown | Live SELECT returns 0 seeded rows |
| **V7** | Production, after apply | Re-run the § 3 impact script: the 3 MIDNIGHT X-MEN rows still read `fulfilled = false`, and the "starts" column is still 0 |

**V2 is the gate that matters** — it is the only one that distinguishes the new
body from the old.

---

## 6. Rollback

`CREATE OR REPLACE` back to the previous body (kept in git history at
`5da0a28:docs/sql/auto_fulfill_past_on_sale.sql`). Read-path only — the function
writes, but reverting it writes nothing by itself.

**One-way risk:** if the new body is applied and an import runs before anyone
notices a problem, rows already flipped to `fulfilled = true` stay that way.
Given § 3 measured **0 new fulfils**, the realistic risk is the opposite — rows
that should close staying open for one extra cycle, which is visible and
harmless.

---

## 7. Also owed

- **`import.js` / `import-staging.js`** (private scripts repo): F115's Step 9
  pre-flight report and `findUnverifiedFulfillments()` describe these rows as
  *"no shipment evidence"*, which reads as *might not have arrived* rather than
  *is not due for two months*. **Not changed here** — scripts-repo work, and the
  agent's pushes to that repo are blocked by `guard-git`.
- **F122's entry** stays open until both environments are applied and V7 passes.

---

## 8. Deploy log

**Applied 2026-08-08 to staging, then production. Verified by execution on both.**

### 8.1 Gates

| Gate | Staging | Production |
|---|---|---|
| **Pre-flight** — live body is the one being replaced | ✅ `prosrc` byte-identical to the repo's prior version | ✅ same |
| **V1** grants | ✅ see § 8.3 | ✅ see § 8.3 |
| **V2** re-dated title NOT fulfilled | ✅ **measured before AND after** | ✅ the 3 real rows stayed `false` |
| **V3** normal title still fulfilled | ✅ | — (no fixture needed) |
| **V4** NULL `on_sale_date` untouched | ✅ returned 0, row untouched | — |
| **V5** idempotent | ✅ second call returned 0 | ✅ |
| **V6** fixtures torn down | ✅ SELECT returns 0 | n/a |
| **V7** live behaviour | ✅ | ✅ **`auto_fulfill_past_on_sale()` returned `0`; the old body would have returned `3`** |

### 8.2 The A/B that made V2 conclusive

The fixture was seeded and the **old** body was run against it first, establishing a
baseline rather than asserting the new behaviour in isolation:

| | Old body | Fixed body |
|---|---|---|
| Return value | `2` | `1` |
| Re-dated reservation | `fulfilled = true` ← bug reproduced | `false` ✅ |
| Normal reservation | `true` | `true` ✅ |

On production the same proof came from real data: the function returned **`0`** where
the old body would have returned **`3`**, and reservations `fe56b7ae` / `b346fb36` /
`f0b8e7b9` — 5 copies, 3 customers — remained `fulfilled = false`. **The 2026-08-07
manual repair is now durable**; before this, the next weekly import would have
silently undone it.

### 8.3 Gate V1 failed, and became its own finding

The grant check found the function executable by roles that had no need for it —
**pre-existing, not caused by this change**, and traced to a general fact about
`REVOKE … FROM PUBLIC`. Filed and resolved the same session as **F124**; this
plan's SQL file was corrected as part of it. Both environments verified by
execution afterwards, including that `service_role` still executes so the weekly
import is unaffected.

### 8.4 Still owed

- **Import scripts** (private scripts repo): F115's Step 9 pre-flight report and
  `findUnverifiedFulfillments()` describe these rows as *"no shipment evidence"*,
  which reads as *might not have arrived* rather than *is not due for two months*.
  Unchanged — scripts-repo work.
- **F122 Option 3** (the catalog-upsert root fix) remains open by decision — see
  `technical-reference.md` § 13 F122.
