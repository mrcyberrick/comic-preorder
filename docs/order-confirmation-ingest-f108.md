# Order-Confirmation Ingest — closing F108, and making the Order Follow-Up panel mean something

**Status:** **Planning — not started.** Session A is specification-only and produces no code.
**Plan written:** 2026-08-04.
**Follows:** `docs/order-export-foc-window-and-order-state.md` (F101/F102 — built the ledger), `docs/order-export-followthrough-f110-f111-f112.md` (F110/F111/F113 — cross-month gather + withdrawal), and the 2026-08-04 panel-triage work (F115/F116 — arrival-evidence clearing). All three are **live on production**.
**Unblocks:** **F108**, whose entry has read *"needs sample PRH/Lunar order-confirmation files before it can be specified"* since 2026-08-02. **Those samples now exist** — see § 2.6.
**Environments:** staging first throughout. Production promotion is Rick's explicit call, per session.

**Authoritative inputs read during planning (2026-08-04):** live production `catalog`, `preorders`, `order_submissions`, `weekly_shipment` (read-only, service role); `admin.html` `computeBackorderRisk()`/`renderBackorderRiskPanel()` as deployed; `docs/technical-reference.md` § 4.11, § 13 (F101, F102, F108, F110, F112, F115, F116); two operator screenshots of the **Lunar Distribution** order view (order `1804145`) and the **PRH** order/cart view.

---

## 1. Goal

**The Order Follow-Up panel currently reports the shape of our own record-keeping, not the risk it claims to report.** On production on 2026-08-04 it showed four titles as BACKORDERED. All four had in fact been ordered. Precision was **0 of 4**.

This is not a defect in the panel's logic — the logic is correct given its inputs. The input is missing: `order_submissions` is written only by a manual **Mark Ordered** click, and that click **has never been used on production** (§ 2.2). The ledger therefore knows about exactly three monthly submissions and nothing else.

The goal is to feed the ledger from the distributors' own order confirmations, so that:

1. A title the store ordered stops being reported as un-ordered.
2. "No record" becomes **evidence of absence** rather than absence of evidence — which is the property that makes the panel worth reading.
3. The richer state the suppliers already publish (shipped / processing / expected date) becomes available to the admin, and eventually to the customer.

---

## 2. Evidence established 2026-08-04 — read this before designing anything

### 2.1 All four "BACKORDERED" titles were ordered

| Panel row | Supplier record |
|---|---|
| ACTION COMICS #1101 (`0626DC0116`) | Lunar order **1804145**, placed **6/2/2026** — **Shipped**, shipment `864180`, ship date **7/31**, in-store **8/12** |
| ACTION COMICS #1 FACSIMILE (`0626DC0190`) | Same Lunar order — **Processing**, in-store **8/26** |
| TMNT #21 Cover A (`82771403315102111`) | PRH order — est. delivery **Aug 17**, on sale **Aug 19** |
| TMNT SMA #40 Variant C (`82771403150804031`) | PRH order — est. delivery **Aug 24**, on sale **Aug 26** |

Our on-sale dates match both suppliers **exactly** on all four, and the two Lunar FOC dates match too. **The catalog import is accurate; only order state is missing.** Nothing about this plan should touch catalog ingestion.

### 2.2 The manual path is not being used, and that is the finding

Measured on production 2026-08-04:

- `order_submissions` total: **857**
- Rows created after the 2026-08-03 backfill — i.e. by a real **Mark Ordered** click: **0**
- `order_type` distribution: **857 `monthly`, 0 `adhoc`**
- Distinct `submitted_on` values: **exactly three** — `2026-05-24`, `2026-06-27`, `2026-07-26`

So the entire ledger is backfill. **Building more manual affordances is the wrong direction** — an affordance that has been available for a day and used zero times will not become the source of truth. This is the single strongest argument for ingest over UI work.

### 2.3 Off-cycle orders are structurally invisible

Lunar order `1804145` is dated **6/2/2026**. That is **not** one of the three backfilled monthly dates. It is an off-cycle order placed directly on the Lunar website — and `order_type` has **zero** `adhoc` rows, so nothing like it has ever been recorded.

F101's § 2 already established that ad-hoc orders exist and must be excluded from the monthly order. This is the same fact from the other side: **they also need to be *recorded*, and no current path does it.**

### 2.4 One order, three lines, two outcomes — the cleanest demonstration

Lunar order `1804145` contains three lines:

| Code | Title | On the panel? | Why |
|---|---|---|---|
| `0626DC0202` | AVENGERS JLA #4 FACSIMILE | **No — cleared** | has a ledger row (`submitted_on 2026-06-27`, from the backfill) |
| `0626DC0190` | ACTION COMICS #1 FACSIMILE | **BACKORDERED** | no ledger row |
| `0626DC0116` | ACTION COMICS #1101 | **BACKORDERED** | no ledger row |

Same supplier order, same day, same distributor. The difference is **which archived order file the backfill happened to cover**. Verified: AVENGERS' absence is a correct clear, not a bug.

### 2.5 Arrival evidence cannot close this gap — the lag is ~10 weeks

F116 (2026-08-04) added clearing on `weekly_shipment` evidence, which is what removed Sonic #88 from the panel. **It does not help these four**, and the reason is structural:

- Lunar shows ACTION COMICS #1101 as **Shipped on 7/31**.
- `weekly_shipment` has **zero** rows for it, because that table is populated from the **weekly invoice at the street week** (8/12).
- Order placed **6/2** → arrival evidence exists **~8/12**. For that whole window a correctly-ordered title reads BACKORDERED.

**Arrival evidence clears stale false alarms; only order evidence clears in-flight ones.** Both are needed and they are not substitutes.

### 2.6 The blocker on F108 is gone

F108 has been deferred since 2026-08-02 pending sample confirmation files. From the screenshots:

- **Lunar** exposes a per-order view with a **`CSV Download`** link, an order number (`1804145`), per-line **Retail / Price / Qty**, per-line **Due Date / FOC / In-Store** dates, a per-line status dot (**Shipped / Partially Shipped / Processing**), and a **Shipments** table with shipment id and ship date.
- **PRH** exposes an order/cart view with per-line **Est Delivery**, on-sale date, unit price and discount, carton quantity, and a publisher-supplied code matching our `upc`-style key.

**What is NOT known: the actual column names and layout of either export.** Nobody has opened the Lunar CSV, and it is unconfirmed whether PRH offers a downloadable confirmation at all or only this web view. **§ 6 Session A exists solely to resolve that, and no parser may be written before it.**

### 2.7 The terminology collision is live on screen

PRH's own banner reads *"These titles will be **backordered** unless removed before Checkout"* — meaning *ordered, will fill late*. Our panel labels the same two TMNT titles **BACKORDERED** — meaning *never ordered*. F112 recorded this collision; it is now visible in two windows side by side, and any ingest that copies a vendor status string verbatim will import the ambiguity. **Vendor status values must be mapped into our vocabulary, never passed through.**

### 2.8 Customer impact today: none, and the reason matters

All four are prior-catalog-month rows (`2026-05`/`2026-06`; production is on `2026-08`), so they never enter My List's current-month table where the FOC-lock copy lives. Verified across all of production: **zero** reservations are showing "FOC passed — contact the store". Customers see a normal Upcoming Arrivals card.

**This is why the work is a priority-not-emergency.** The damage is operator trust and wasted checking, not a broken customer promise — yet. The customer-facing half (§ 4.4) is where that changes, and it is deliberately last.

---

## 3. Current state — verified against live code and data 2026-08-04

### 3.1 `order_submissions` (§ 4.11)

| Column | Notes |
|---|---|
| `id`, `tenant_id`, `distributor`, `order_code`, `item_code`, `title`, `quantity`, `order_type`, `foc_date`, `catalog_month`, `submitted_on`, `created_at` | as built by F101/F102 |

- **No unique constraint on `order_code`** — deliberate; re-ordering a code is legitimate and the ledger records history.
- **No supplier-side identifier at all.** There is no column for a supplier order number, no line status, no expected date. Every ingest design below needs at least one new column, so **this plan requires schema change** and cannot be done in the client alone.
- Indexes: `(tenant_id, distributor, order_code)` lookup; `(tenant_id, submitted_on)`.

### 3.2 Who writes it

| Writer | Status |
|---|---|
| `openMarkOrderedModal()` → Mark Ordered (admin.html) | live; **used 0 times on production** |
| `docs/sql/order-submissions-backfill-PROD.sql` | one-time, 857 rows, three dates |
| Order Builder export | **writes nothing** — deliberate (F101 § 4.2: "written manually, not on export click") |

### 3.3 Who reads it

`ledgerMatchesFor()` → `computeBackorderRisk()` (panel), `classifyForExport()` (Order Builder duplicate surfacing), the By Distributor status button, and `get_ordered_codes()` → My List's "Order placed" lock. **Anything that changes ledger semantics touches the customer-visible lock**, which is why § 4.4 is gated.

---

## 4. Design

> **Everything in § 4.1–4.2 is provisional until Session A reports the real file shapes.** It is written as a set of questions with proposed answers, not as a specification. The F110/F112 precedent is explicit: reading the vendor material first corrected two wrong fix directions before either reached code, and *assuming* file behaviour is what produced them.

### 4.1 Idempotency and the double-count trap — the highest-risk decision

Ingest must be safely re-runnable. The ledger has **no unique constraint on `order_code` by design**, so nothing at the database level prevents a re-ingest from doubling every quantity.

**This is an F102-shaped hazard pointing at money.** F102's whole finding was that Lunar orders *ADD* to existing quantities; a ledger that double-counts a confirmation would tell the panel a title is over-ordered when it is not — or, worse, suppress a genuine re-order.

Proposed (to be confirmed at Session A):

- Add **`supplier_order_id`** (text, nullable) and **`supplier_line_ref`** (text, nullable).
- Dedup key: `(tenant_id, distributor, supplier_order_id, order_code)` as a **partial unique index** where `supplier_order_id IS NOT NULL` — leaving the 857 manual/backfilled rows (all NULL) untouched and still duplicate-legal.
- **Nullable, partial, additive** — matching the Session A precedent from the F110 work, which is the pattern this codebase has had success with.

**The overlap problem, stated plainly:** the backfill already covers `2026-05-24`, `2026-06-27` and `2026-07-26`. If the operator downloads confirmations for those same cycles, ingest **will** double-count them, because the existing rows carry no `supplier_order_id` to match against. Options — **Rick's call at Session A**:

- (a) ingest only confirmations dated **after** a cutoff, and never re-ingest history;
- (b) reconcile against existing rows on `(distributor, order_code, submitted_on)` and skip matches;
- (c) delete and re-ingest the three backfilled cycles from authoritative confirmations.

(c) is the cleanest long-term and the most dangerous to execute. (a) is the safest and leaves history slightly wrong. **Do not choose this in code review — it is a data decision.**

### 4.2 Richer state — map, never pass through

Lunar publishes per line: **Shipped / Partially Shipped / Processing**, a **ship date**, an **in-store date**, and a **Due Date**. PRH publishes **Est Delivery**. Ours is binary.

Proposed additive columns: **`supplier_status`** (our vocabulary, not theirs), **`expected_date`** (date), **`status_as_of`** (date — when the supplier last said so).

Two constraints:

- **Map vendor vocabulary into ours** (§ 2.7). A vendor "backordered" is *ordered, filling late* and must never land in a column our UI renders next to our own "Backordered".
- **`Partially Shipped` is a state we cannot currently represent anywhere.** It is the long-deferred *"partial fulfillment not representable"* item in `CLAUDE.md` § Known Out-of-Scope. Lunar is already telling us. **Ingesting the value is in scope; teaching the app to reason about partial quantities is not** — that stays a product decision, and the plan must not smuggle it in.

### 4.3 What the panel becomes

Once ingest exists, `computeBackorderRisk()` gains a genuinely new capability: **"no record" becomes meaningful.** Today it means "we didn't write it down". After ingest it means "the supplier has no order for this", which is the thing the panel has always claimed to say.

Panel changes (small, deliberately):

- A row cleared by an *ingested* confirmation can show its expected date — *"Ordered · expected Aug 12"* — instead of vanishing silently, so the operator can distinguish "handled" from "never happened".
- The **At risk** bucket stays exactly as-is; it is already correct and is the panel's most valuable output (both current At risk rows, FOC 8/31, are real).
- **Precision becomes measurable.** Record it at the first two ingests, the same way F110 § 2.4 required recording the set-difference noise rate.

### 4.4 Customer-facing status — last, and gated

The payoff: My List could read **"Ordered — expected Aug 12"** instead of a silent Upcoming Arrivals card.

**Deliberately last, and requires an explicit product decision**, because it converts an internal record into a **promise to a customer**. An expected date sourced from a supplier feed will sometimes be wrong, and a wrong promise is worse than silence. Open questions for Rick, not for the agent:

- Show a date, or only "Ordered"?
- What happens visually when a supplier date slips?
- Does this interact with the F110 withdrawn flag and the F72 email-branding thread?

---

## 5. Scope

### IN
- **Session A:** obtain and characterise both suppliers' confirmation exports; produce the field mapping and the idempotency decision. **No code.**
- **Session B:** additive schema + ingest into `order_submissions`, idempotent, unit-tested, dry-runnable.
- **Session C:** panel reads ingested state; expected dates surfaced to the admin.
- **Session D:** customer-facing status — only after § 4.4's product decisions are answered.

### OUT — stop and ask
- **Reasoning over partial quantities** (§ 4.2). Ingest the value; do not build fulfilment maths.
- **Any change to `isFocPast`/`isFocLocked`**, or to the FOC lock's customer semantics.
- **Automating order *placement*.** This ingests confirmations of orders a human placed; it never submits anything.
- **Re-ingesting the three backfilled cycles** unless Rick explicitly picks option (c) at § 4.1.
- **Catalog ingestion** — § 2.1 confirms it is accurate; leave it alone.
- **F72, F89, F90, F92, F93, F104, F105, F107, F109.** Phase 6. `config.js`, credentials, Edge Functions.

---

## 6. Runbook

### Session A — obtain and characterise (specification only, no code)

**The entire session is "read the vendor material first".** It exists because the F110 and F112 fix directions were both wrong until someone opened the actual files.

1. **Operator step (Rick):** download the Lunar `CSV Download` for order `1804145` and at least one monthly cycle order; save to `catalogs/order-confirmations/`. Determine whether PRH offers a comparable export — and if it does not, say so explicitly, because that changes Session B's shape from "parse two files" to "parse one file and handle PRH some other way".
2. Record, **from the files rather than the screenshots**: exact column names, date formats, the code column and how it maps to our `exportCode()` fallback chain per distributor, the order-number field, the status vocabulary, and whether quantities are per-line or aggregated.
3. Check whether a re-downloaded confirmation for the same order is **byte-stable** — if it is not, the dedup key cannot rely on file content.
4. Decide § 4.1's idempotency key and the § 4.1 overlap option. > **PAUSE → Rick.**
5. Write the findings into this document as a new § 2.9 **before** any Session B work. Commit doc-only to `staging`.
6. **Gate V-A1:** every field Session B intends to write is traceable to a named column in a real file, with a real example value quoted. No field may be specified from a screenshot.

### Session B — ingest (schema + scripts repo)

1. `docs/sql/order-submissions-supplier-fields.sql` — additive nullable columns + the partial unique index (§ 4.1). > **PAUSE → Rick** to run on staging, then production.
2. Parser as **pure exported functions**, unit-tested against the real sample files, in the private scripts repo. Follow the `findUnverifiedFulfillments` / `parseInitialOrderDue` precedent: pure, exported, tested both scripts, parity-checked.
3. Idempotent upsert. **Gate V-B1:** ingesting the same confirmation twice produces the same row count and the same total quantity. This is the money-safety gate.
4. **Gate V-B2:** ingesting Lunar order `1804145` on staging clears exactly the two ACTION COMICS titles from the panel and leaves AVENGERS' existing row untouched (no duplicate).
5. **Gate V-B3:** `--no-write` prints what it would ingest and writes nothing.
6. Record the § 4.3 precision measurement before and after.

### Session C — surface (client)

1. Panel shows expected date / supplier state on cleared rows; "no record" wording updated to reflect that it now means something.
2. Extend **spec 15**. **Gate V-C1:** a title cleared by ingested confirmation renders its expected date; a title with genuinely no supplier record still reads Backordered.
3. `/deploy-staging` — push first, then run the suite (CLAUDE.md § Smoke-test ordering).

### Session D — customer-facing (gated on § 4.4 answers)

Not specified here. Do not start without the § 4.4 product decisions recorded in this document.

---

## 7. Verification gates

| Gate | Session | Assertion | Why this one |
|---|---|---|---|
| **V-A1** | A | Every planned field traces to a real column in a real file, with an example value | Screenshots are not a schema — the F110/F112 lesson |
| **V-B1** | B | Double-ingest ⇒ identical row count **and** total quantity | The F102 double-count hazard, pointed at money |
| **V-B2** | B | Ingesting `1804145` clears both ACTION COMICS rows and does not duplicate AVENGERS | The exact live case this plan exists for |
| **V-B3** | B | `--no-write` writes nothing | Every import path in this codebase has this property |
| **V-C1** | C | Cleared-by-confirmation shows a date; genuinely-unordered still reads Backordered | Proves the panel gained information rather than just going quiet |

---

## 8. Completion criteria

### Session A
- [ ] Real confirmation files obtained for **both** distributors, or PRH's absence explicitly recorded
- [ ] § 2.9 written from files, not screenshots; **V-A1** green
- [ ] § 4.1 idempotency key and overlap option decided by Rick and recorded
- [ ] Committed doc-only to `staging`

### Session B
- [ ] Additive columns live on staging **and** production, all nullable, existing 857 rows untouched
- [ ] Parser pure, exported, unit-tested against real files; parity across both scripts
- [ ] **V-B1**, **V-B2**, **V-B3** green
- [ ] Precision measurement recorded before/after

### Session C
- [ ] Panel surfaces ingested state; spec 15 extended; **V-C1** green; full suite green
- [ ] Fixtures torn down, verified by live SELECT returning zero rows

### Session D
- [ ] § 4.4 product decisions answered **before** any code

---

## 9. Rollback

- **Schema:** additive and nullable; leaving the columns in place is a safe rollback for the script change. The partial unique index is the only piece that can *reject* a write — drop it first if ingest misbehaves.
- **Ingested rows:** identifiable by `supplier_order_id IS NOT NULL`, so a bad ingest is deletable without touching the 857 manual/backfilled rows. **This is the main reason for the nullable-column design.**
- **Client:** `git revert` on `staging`; Session C is read-side rendering only.
- **Genuinely irreversible:** option (c) at § 4.1 (delete and re-ingest history). If chosen, capture the 857 rows to a file first.

---

## 10. Interim mitigation, and why it is weak

Until Session B lands, the only way to clear a false alarm is to click **Mark Ordered** on the affected rows. Worth doing for the four current ones — it takes a minute and makes the panel honest today.

**But it is not the fix, and the data says so:** the button has existed since 2026-08-03 and has been used **zero** times (§ 2.2), and the orders that caused this were placed **directly on the vendors' websites** off-cycle (§ 2.3), where PULLLIST is not in the loop at all. A manual step that must be remembered *after* leaving the app to do the real work is exactly the step that gets skipped. Ingest is the fix because it does not depend on anyone remembering anything.

---

## 11. Out-of-session operational items

**Unchanged and still outstanding:** PRH holds **12 copies** of `75960621668000111` (MIDNIGHT X-MEN #1) against **7** reservations, FOC **2026-08-31**. Reminder armed for 2026-08-24. Nothing in this plan changes it.

**Live and time-boxed:** the two **At risk** rows — `SIMPSONS COMIC STRIP CAVALCADE HC` (`0826AB0610`) and `DICK TRACY COLLECTION TP 1962` (`0826CP0687`) — both FOC **2026-08-31**. These are the panel's correct output and need an ordering decision before the 31st, independent of this plan.

---

## References

- `docs/technical-reference.md` § 4.11 (`order_submissions`), § 13 — **F108** (this plan closes it), **F101**/**F102** (built the ledger; the double-count hazard), **F115**/**F116** (the panel triage this extends), **F110**/**F112** (the read-the-vendor-material-first precedent, and the terminology collision), **F106** (alarm fatigue), **F9** (unique-key care).
- `docs/order-export-foc-window-and-order-state.md`; `docs/order-export-followthrough-f110-f111-f112.md`.
- `CLAUDE.md` § Smoke-test ordering; § "Green is not the same as verified"; § SQL authoring rules; § Stop and ask.
- Live: `admin.html` `computeBackorderRisk()`; `import.js` / `import-staging.js` (private scripts repo).
- Production `plgegklqtdjxeglvyjte`; staging `puoaiyezsreowpwxzxhj`.
