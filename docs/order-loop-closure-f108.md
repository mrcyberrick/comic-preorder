# Closing the Ad-Hoc Order Loop — making the Order Follow-Up panel tell the truth

**Status:** **Planning — rewritten 2026-08-04 after a decision interview with Rick. Not started.**
**Supersedes:** `docs/order-confirmation-ingest-f108.md` (same file, renamed). **That plan's central proposal — ingesting distributor order-confirmation files — is DROPPED, not deferred.** § 3.1 records why, in Rick's words. The evidence that produced it is kept at § 2.8 because it is what justifies dropping it.
**Closes:** **F108** — not by reconciliation after the fact, which is what F108 originally imagined, but by capturing the order at the moment it is placed (§ 3.5).
**Follows:** F101/F102 (built the ledger), F110/F111/F113 (cross-month gather + withdrawal), F115/F116 (arrival-evidence triage). All live on production.
**Environments:** staging first. Production promotion is Rick's explicit call, per session.

---

## 1. Goal

Three things, in priority order, all serving one workflow:

1. **Make At Risk correct.** It is the signal that drives the ad-hoc process, and it is currently mis-triggered (§ 2.10). A one-line change, and the highest-value item here.
2. **Capture what was ordered as a by-product of ordering it** — never as a task to remember afterwards.
3. **Answer the customer** — *"Ordered — arriving Sept 16"* — from data already held.

**Hard constraint, stated by Rick 2026-08-04, binding on every design below:**

> *"I do not want to download multiple files to feed the import every week because this adds more manual tasks. The pulllist app should not be a chore to maintain."*

Any proposal that adds a recurring manual step is disqualified regardless of its other merits. **The data already proves the constraint right:** the manual `Mark Ordered` button shipped 2026-08-03 and has been used **zero times** on production (§ 2.2).

---

## 2. Evidence established 2026-08-04

### 2.1 The panel is currently wrong on every row

| Bucket | Showing | Actually true |
|---|---|---|
| Backordered | 4 | **0** — all four were ordered (§ 2.3) |
| At Risk | 2 | **0** — both fit the monthly cycle (§ 2.10) |

**Precision: 0 of 6.** Not a noise problem — no true positives at all. Everything else follows from that.

### 2.2 The manual path is not used, and that is the finding

- `order_submissions`: **857 rows, all backfill**, across exactly three `submitted_on` dates (`2026-05-24`, `2026-06-27`, `2026-07-26`).
- Rows created since the backfill — i.e. by a real **Mark Ordered** click: **0**.
- `order_type`: **857 `monthly`, 0 `adhoc`** — despite ad-hoc orders demonstrably existing (§ 2.4).

An affordance requiring the operator to remember, *after* leaving the app to do the real work, does not get used. **This is the single most important design input in the document.**

### 2.3 The four "Backordered" titles were all ordered

| Panel row | Supplier record |
|---|---|
| ACTION COMICS #1101 (`0626DC0116`) | Lunar order **1804145** (6/2/26) — **Shipped** 7/31, in-store 8/12 |
| ACTION COMICS #1 FACSIMILE (`0626DC0190`) | same order — Processing, in-store 8/26 |
| TMNT #21 Cover A (`82771403315102111`) | PRH order — est. delivery Aug 17 |
| TMNT SMA #40 Variant C (`82771403150804031`) | PRH order — est. delivery Aug 24 |

Our on-sale dates matched both suppliers **exactly** on all four. The catalog import is accurate; only order state was missing.

**Cleanest demonstration** — Lunar order `1804145` has three lines: `0626DC0202` (AVENGERS JLA #4) is correctly cleared because the backfill happened to cover its 6/27 cycle; the two ACTION COMICS read BACKORDERED. Same order, same day, same distributor. The only variable is which file the backfill caught.

### 2.4 Off-cycle orders are structurally invisible

Lunar order `1804145` is dated **6/2/2026** — not one of the three backfilled dates. Placed directly on the vendor site, off-cycle. Nothing like it has ever been recorded.

### 2.5 Arrival evidence clears stale alarms, not in-flight ones

F116 clears a code when `weekly_shipment` shows it arrived; that removed Sonic #88. It **cannot** help the four above: Lunar showed `0626DC0116` as Shipped on 7/31, but `weekly_shipment` gets its row at the street week (8/12). Order placed 6/2 → arrival evidence ~8/12. **Ten weeks in which a correctly-ordered title reads BACKORDERED.**

### 2.6 Customer impact so far: none, verified

All four are prior-catalog-month rows, so they never reach My List's current-month table where the FOC-lock copy renders. **Zero** reservations across production were showing "FOC passed — contact the store". The damage is operator trust, not a broken promise — which is why the customer-facing piece (§ 4.6) is sequenced last rather than treated as an emergency.

### 2.7 `auto_fulfill_past_on_sale()` closes never-arrived titles on schedule

No arrival check; the panel filters `!fulfilled`; so a never-arrived title exits looking exactly like a success, and My List then reads "✓ Order placed". Measured: **28 reservations / 23 titles / 4.2%** of past-on-sale reservations fulfilled with no shipment record and no ledger row. Mitigated 2026-08-04 by the Step 9 pre-flight report (F115) — automatic, inside the existing import, adds no step.

### 2.8 The vendor exports cannot supply what was hoped — this is why ingest is dropped

Real exports from both distributors were obtained and parsed (`catalogs/order-confirmations/`, local):

- **Match feasibility is fine** — PRH 28/31 (90%), Lunar 137/149 (92%); misses are promo posters, ashcans and non-stocked titles.
- **But neither export carries status or dates worth having.** The Lunar CSV has **no dates and no status at all**; PRH's line table has **no date column**, and its `Order Status` is **31/31 `Backordered`** — the F110 uniform-column trap repeated, wearing the F112 collision's exact vocabulary.
- **Lunar's order number is only in the filename**, and Lunar supplies no order date at all, while `submitted_on` is NOT NULL.
- Lunar's export contains **negative-quantity lines** (3 of 152) and `order_submissions` has `CHECK quantity >= 1` — a row-per-line ingest **aborts**.

So the files would add a recurring download, need per-distributor parsers plus netting, and deliver **only** what §§ 4.2–4.3 now capture for free. **Dropped.**

### 2.9 Rejections happen at order time, and only the operator sees them

Rick, 2026-08-04: some titles are **rejected by the supplier when ordering**. Nothing in the system can currently represent that. This is what F108 was fundamentally about — and the operator observes it directly, which is strictly better evidence than reconstructing it from a file later.

### 2.10 `order_deadline` supersedes the in-month rule — the current code has it as `OR`

Rick, 2026-08-04:

> *"The order_deadline supersedes the date logic of FOC in-current-month. If order_deadline is missing it reverts back to the logic of an FOC date in-current-month. The admin sets the deadline which is the agreed upon date that orders will be processed and this is often before the month ends."*

`computeBackorderRisk()` currently reads:

```js
const trigger = past || isFocThisMonth(c.foc_date) || (orderDeadline && c.foc_date <= orderDeadline);
```

`isFocThisMonth` fires regardless of the deadline. **Verified on production** (`order_deadline = 2026-08-21`, founding tenant — note `app_settings` is a **key/value** table, not columns; an earlier read of `select=order_deadline` wrongly returned null):

| | Current `OR` | Corrected supersede |
|---|---|---|
| At Risk | **2** (both FOC 2026-08-31) | **0** |

Both have FOC **after** the Aug 21 deadline, so the monthly order placed on the 21st covers them. They fit the cycle and were never at risk.

**The semantic, precisely:** At Risk is not a countdown. It answers *"does this title fit the regular monthly order cycle?"* — and the deadline, not the month boundary, is the cycle's edge.

---

## 3. Decisions settled with Rick, 2026-08-04

### 3.1 Confirmation-file ingest is DROPPED
Not deferred. It violates § 1's constraint, and §§ 4.2–4.4 capture the same information with no recurring step. The sample files stay on disk as reference; **nothing in this plan reads them.**

### 3.2 No lead-time window
Proposed and **rejected**. Rick: *"A leadtime is not necessary because early FOC dates are not common and easier to manage. In short - no leadtime."* The catalog is loaded roughly a week early and alerts surface when the month turns. **Do not reintroduce a rolling window.**

### 3.3 The deadline supersedes; absent, fall back to in-month
§ 2.10. Fixes the two live false positives.

### 3.4 Confirm-on-export, for the ad-hoc process specifically
Rick: *"confirm-on-export (specifically is good for the ad-hoc process)."* This reverses F101 § 4.2's "written manually, not on export click" — deliberately, with the operator's agreement, and only as an **explicit confirmation after download**, never an automatic write.

### 3.5 The monthly cycle is confirmed at new-catalog import
Rick: *"The import process (when a new catalog is loaded not a past or current catalog refresh) is where the open orders get confirmed."* **Gated on `isNewMonth`** — a same-month or older refresh must never confirm, or the ledger doubles. Same gate F110's withdrawal detection uses.

### 3.6 Zero-quantity Mark Ordered records a rejection
Rick: *"…I can use the Ad Hoc process (By Distributor) list to 'zero' out the rejected items. The 'Mark Order' button can log a zero qty effectively closing the loop on what was actually ordered. The import process simply accepts it."* A zero-quantity row means **"we tried; nothing was ordered."** The import treats an existing zero as authoritative and never overwrites it.

### 3.7 A rejected title reuses the generic unavailable status
Rick: *"Reusing a generic unavailable status is reasonable."* From the customer's seat a **rejected** title and a **withdrawn** title (F110) are the same thing: *this cannot arrive*. F110's surface is reused rather than inventing a parallel concept.

### 3.8 A stale deadline resets to blank
Rick, 2026-08-04: *"I would prefer a stale deadline to drop (reset) to a blank deadline."*

This is better than either option offered. It **self-heals**: the moment the deadline lapses it stops being authoritative, the trigger falls back to in-month (§ 3.3), and the blank field is itself the signal that the next cycle's date needs setting. No silent alarm, no nagging banner. Design at § 4.1.

### 3.9 Import confirmation is reviewed — for now
Rick: *"Fine to review but may change this down the road."*

Build the review, but **structure it so becoming blind later is a flag, not a rewrite** (§ 4.3). Recorded because a future session finding a review step should know it was a deliberate starting point, not a permanent requirement.

---

## 4. Design

### 4.1 At Risk trigger — deadline supersedes (§ 2.10)

```js
const trigger = past || (orderDeadline
  ? c.foc_date <= orderDeadline          // the cycle's real edge
  : isFocThisMonth(c.foc_date));         // fallback when unset
```

`Backordered` is unchanged: `focPast && no order`.

**Stale-deadline handling — settled (§ 3.8): a lapsed deadline resets to blank.**

Superseding would otherwise introduce a silent-failure mode — once the deadline passes, `foc_date <= deadline` matches nothing in the future and At Risk goes empty until someone remembers to roll it forward. F96 was an alarm that cried wolf for 18 days; a *silent* alarm is the worse failure. Resetting to blank removes the failure mode entirely rather than papering over it: the fallback at § 3.3 takes over automatically, and the empty field is the prompt to set the next cycle's date.

Two places implement it, deliberately:

| Where | What | Why both |
|---|---|---|
| **Read path** (`admin.html`) | treat `order_deadline < today` as absent — **no write** | Behaviour is correct the instant it lapses, without depending on anything having run |
| **New-catalog import** (`isNewMonth`) | clear the stored value | The stored value and the UI field match reality; a new cycle genuinely has no deadline yet |

The read-path check is what makes it correct; the import clear is what makes the dashboard *look* correct. Doing only the second would leave a stale date on screen governing nothing. Doing only the first would leave the field showing an expired date indefinitely. **No write-on-page-load** — that would be a surprising side effect on a read.

### 4.2 Capture point 1 — confirm-on-export (ad-hoc, client)

After **Generate & Download** in the Order Builder, offer an explicit confirmation: *"Record these N titles as ordered?"* — writing one `order_submissions` row per exported code at the exported quantity, `order_type = 'adhoc'`.

- **Explicit, never automatic.** Exporting is not ordering.
- One interaction covers the whole export.
- Declining leaves the ledger untouched — current behaviour.

### 4.3 Capture point 2 — confirm at new-catalog import (monthly, scripts repo)

On `isNewMonth` only (§ 3.5), the import presents the closing cycle's open, unordered, non-withdrawn reservations and confirms them as the monthly order.

**Reviewed, not blind — settled (§ 3.9).** The import knows what was **reserved**, not what was **ordered**; they differ when a quantity is trimmed, a title skipped, or a code already covered ad-hoc. A blind write would record titles as ordered that were not, and **a false "Ordered" reaches the customer as a promise — worse than today's false "Backordered", which only wastes operator time.** So: present the list, allow lines to be dropped, then write. Still one interaction, no files, fails safe. The Step 9 report (F115) already establishes this shape.

**Build it so blind becomes a flag, not a rewrite** (§ 3.9 — Rick expects this may change). Keep the selection *set* and the *write* as separate steps: compute the confirmable list, optionally filter it interactively, write the result. Skipping the middle step must then be a single branch (`--auto-confirm`, or a setting) rather than an unpicking of the flow. Do not interleave prompting with writing.

Rules regardless:
- Skip codes that already have a ledger row for the cycle — no double-count.
- **Never overwrite an existing zero-quantity row** (§ 3.6).
- `--no-write` prints and writes nothing.

### 4.4 Zero quantity = rejected — three things must ship with it

Written from the existing **Mark Ordered** modal on By Distributor. All three are mandatory or it backfires:

1. **Relax the CHECK constraint.** `order_submissions_quantity_check` is `quantity >= 1`; a zero row is rejected by the database outright. → `quantity >= 0`.
2. **`get_ordered_codes()` must stop lying.** Currently `SELECT DISTINCT distributor, order_code` with **no quantity filter**, so a zero row would make My List show **"✓ Order placed"** and lock cancellation for a rejected title. It must aggregate — a code ordered 5 then zeroed still reads ordered; a code *only* ever zeroed does not. To preserve the RPC's deliberate privacy design (quantities stay admin-only, per its own header comment) it returns a **state**, not a number:

   ```sql
   RETURNS TABLE(distributor text, order_code text, order_state text)
   -- 'ordered'     when SUM(quantity) > 0
   -- 'unavailable' when rows exist and SUM(quantity) = 0
   ```
3. **The By Distributor button needs its own state.** `✓ Ordered (0)` is nonsense. Show *"Rejected — none ordered"*, and keep it clickable, since a rejection can be re-ordered later.

### 4.5 Generic unavailable status (§ 3.7)

Computed from **either** source, rendered by the single surface F110 already built:

| Source | Meaning |
|---|---|
| `catalog.withdrawn_at` set | distributor stopped publishing the code (F110) |
| ledger rows exist, `SUM(quantity) = 0` | supplier rejected our order |

Both ⇒ **unavailable**: flagged on My List, **cancellation re-enabled** despite the FOC and ordered locks, listed on the admin panel. `isFocPast`/`isFocLocked` stay byte-unchanged; the exception remains a call-site condition.

**Deliberately not merged into `catalog.withdrawn_at`** — that column is a property of the *title*; a rejection is a property of *our order*. Different grain, same derived state. Forcing one into the other misrepresents both.

### 4.6 "Ordered — arriving [date]" (customer, last)

From **`catalog.on_sale_date`**, which § 2.3 verified matches both distributors exactly. **No supplier feed required.** Gated behind § 4.5 landing, so "unavailable" and "ordered" can never both be claimed for the same reservation.

---

## 5. Scope

### IN
- § 4.1 At Risk trigger correction (client).
- § 4.2 confirm-on-export for ad-hoc (client).
- § 4.3 confirm-at-new-catalog-import (scripts repo, `isNewMonth` only).
- § 4.4 zero-quantity rejection: CHECK relaxation, `get_ordered_codes()` rework, button state.
- § 4.5 generic unavailable state reusing F110's surface.
- § 4.6 customer-facing ordered + arrival date.

### OUT — stop and ask
- **Order-confirmation file ingest.** Dropped (§ 3.1). Do not reintroduce.
- **Any rolling lead-time window.** Rejected (§ 3.2).
- **Changes to `isFocPast`/`isFocLocked` themselves.**
- **Automating order placement.** The app records orders; it never submits them.
- **Partial-fulfilment maths.** Still the deferred product decision it always was.
- **Catalog ingestion** — accurate (§ 2.3); leave it alone.
- **F72, F89, F90, F92, F93, F104, F105, F107, F109.** Phase 6. `config.js`, credentials, Edge Functions.

---

## 6. Runbook

### Session A — At Risk correctness (client, small)
1. § 4.1 supersede logic in `computeBackorderRisk()`.
2. § 4.1 stale-deadline reset — read-path treat-as-absent (client) **and** clear-on-`isNewMonth` (scripts repo). The script half can ship with Session B if it keeps Session A to one repo.
3. Extend spec 15. **Gate V-A1:** with `order_deadline` set, a title whose FOC is *after* it is **not** At Risk; with the deadline cleared, the same title **is**. Both assertions in one test — that pair is the whole semantic.
4. **Gate V-A2:** against production-shaped data the two Aug-31 titles show **0 At Risk** (§ 2.10).
5. **Gate V-A3:** a deadline dated in the past behaves exactly as a blank one (§ 3.8) — the self-healing property, and the one most likely to rot unnoticed since it only manifests after a date passes.

### Session B — capture (client + scripts repo)
1. § 4.2 confirm-on-export. **Gate V-B1:** confirming writes one row per exported code at the exported quantity; declining writes nothing.
2. § 4.4 schema: `docs/sql/order-submissions-allow-zero-qty.sql` (CHECK relaxation) + `get_ordered_codes()` rework. > **PAUSE → Rick** to run on staging, then production.
3. **Gate V-B2 (the false-promise gate):** a code with **only** a zero-quantity row does **not** read "Order placed" on My List; a code ordered 5 then zeroed still does.
4. § 4.3 import confirmation, gated on `isNewMonth`, **reviewed** (§ 3.9) with selection and write kept as separate steps. **Gate V-B3:** a same-month refresh confirms nothing. **Gate V-B4:** an existing zero-quantity row survives an import untouched.
5. Clear a lapsed `order_deadline` on `isNewMonth` (§ 4.1), if not already shipped with Session A.

### Session C — unavailable + customer (client)
1. § 4.5 generic unavailable state reusing F110's rendering, admin panel and cancel exception.
2. § 4.6 "Ordered — arriving [date]".
3. **Gate V-C1:** a rejected (zero-qty) title renders identically to a withdrawn one and is cancellable.
4. `/deploy-staging` — push first, then run the suite. Full suite green **plus** a real-browser check at mobile width.

---

## 7. Verification gates

| Gate | Assertion | Why this one |
|---|---|---|
| **V-A1** | Deadline set ⇒ later-FOC title not At Risk; deadline cleared ⇒ it is | The supersede semantic in one test |
| **V-A2** | The two Aug-31 titles show **0 At Risk** | The live false positives this fixes |
| **V-A3** | A past-dated deadline behaves exactly as a blank one | § 3.8's self-healing property — only manifests after a date passes, so it rots unnoticed without a test |
| **V-B1** | Confirm writes exactly the export; decline writes nothing | Export is not an order |
| **V-B2** | Zero-only code never reads "Order placed" | **A false promise reaches the customer — the worst failure available** |
| **V-B3** | Same-month refresh confirms nothing | Double-counting the ledger is an F102-shaped money error |
| **V-B4** | Zero-quantity row survives import | § 3.6 — the import accepts it, never overwrites |
| **V-C1** | Rejected renders and behaves as unavailable | § 3.7 — one surface, two sources |

---

## 8. Completion criteria

### Session A
- [ ] Supersede logic landed; `Backordered` unchanged
- [ ] Lapsed deadline treated as absent on the read path (no write-on-load)
- [ ] **V-A1**, **V-A2**, **V-A3** green; spec 15 extended

### Session B
- [ ] Confirm-on-export live; **V-B1** green
- [ ] CHECK relaxed and `get_ordered_codes()` reworked on staging **and** production
- [ ] **V-B2**, **V-B3**, **V-B4** green
- [ ] Import confirmation keeps selection and write as separate steps (§ 3.9)
- [ ] Lapsed `order_deadline` cleared on `isNewMonth`
- [ ] Ledger row count before/after first real use recorded

### Session C
- [ ] Unavailable state shared with F110; **V-C1** green
- [ ] Customer arrival date live; full suite green; real-browser check at mobile width
- [ ] Fixtures torn down, verified by live SELECT returning zero rows

---

## 9. Rollback

- **§ 4.1** is a pure predicate change — `git revert`.
- **CHECK relaxation** is widening; existing rows stay valid. Reverting requires no zero rows to exist, so revert *before* first use or not at all.
- **`get_ordered_codes()`** — `CREATE OR REPLACE` back to the prior body; read-only, no data risk.
- **Ledger rows written by confirmation** are ordinary rows, deletable by `created_at` window if confirmed in error.
- **Genuinely irreversible:** a customer who cancels via the § 4.5 unavailable path is gone from `preorders`. Inherent to F110's existing decision, not new here.

---

## 10. Open decisions

**None.** Both were answered 2026-08-04 and are recorded at § 3.8 (stale deadline resets to blank) and § 3.9 (reviewed confirmation, built so blind is a later flag). Sessions A–C are fully specified.

---

## 11. Out-of-session operational items

- **PRH holds 12 copies of `75960621668000111`** (MIDNIGHT X-MEN #1) against 7 reservations, FOC **2026-08-31**. Reminder armed 2026-08-24. **Not fixed by any code in this plan** — it needs a call to PRH before the 31st.
- The four § 2.3 titles are ordered and arriving; no action beyond the panel eventually reflecting it.
- ~~Post-deploy write-smoke for PR #102~~ — **confirmed by Rick 2026-08-04.** F115/F116 are live and verified on production.

---

## References

- `docs/technical-reference.md` § 4.11 (`order_submissions`), § 6.8 (`get_ordered_codes`), § 13 — **F108** (closed by this), **F101**/**F102**, **F110** (the unavailable surface reused at § 4.5), **F112**, **F115**/**F116**, **F96** (alarm credibility).
- `docs/order-export-foc-window-and-order-state.md`; `docs/order-export-followthrough-f110-f111-f112.md`.
- `CLAUDE.md` § Smoke-test ordering; § "Green is not the same as verified"; § SQL authoring rules; § Stop and ask.
- Live: `admin.html` `computeBackorderRisk()` / `openMarkOrderedModal()` / Order Builder; `mylist.html`; `import.js` / `import-staging.js` (private scripts repo).
- Reference only, **not read by any code**: `catalogs/order-confirmations/` (local).
- Production `plgegklqtdjxeglvyjte`; staging `puoaiyezsreowpwxzxhj`.
