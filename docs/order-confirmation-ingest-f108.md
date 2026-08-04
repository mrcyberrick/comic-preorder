# Order-Confirmation Ingest — closing F108, and making the Order Follow-Up panel mean something

**Status:** **Planning. Session A substantially COMPLETE 2026-08-04** — real confirmation exports obtained from both distributors and characterised against live production data (§ 2.9). Sessions B–D not started.
**Plan written:** 2026-08-04; **materially revised the same day** once the real files arrived. **Two things the screenshots implied turned out to be false, and both were load-bearing** — see § 2.9.4 and § 2.9.5. This is the third time in this workstream that reading the actual vendor material corrected a design before it reached code (cf. F110's `SalesStatus`, F112's severity split).
**Sample files:** `catalogs/order-confirmations/` (local, alongside the catalog CSVs — not committed).
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

### 2.9 The real files, measured 2026-08-04 — this supersedes every screenshot-derived assumption above

Two genuine exports were obtained and parsed with an RFC4180 parser (both need one — see § 2.9.6), then feasibility-tested against the live production catalog (11,713 rows, read-only).

| | **PRH** `order-detail-0006099880-0599580000.csv` | **Lunar** `Order_1853046.csv` |
|---|---|---|
| Shape | header block (12 key/value rows) + blank row + line table | single flat table |
| Line columns | `Line, Description, ISBN, Warehouse, Price, Discount %, Net Value, Qty, Net Amount, Order Status` | `Code, Title, Qty, Retail, Discount, Discounted Price, Total, UPC` |
| Lines | 31 | 152 (**149 distinct codes**) |
| Order number | **in file** — `Order Number 0006099880` | **filename only** — not in the content |
| Order date | **`Order Create Date 2026-08-04`, ISO** | **absent** |
| Status column | present but **31/31 `Backordered`** | **absent** |
| Negative quantities | none | **3** |
| Code column | `ISBN` — but **30/31 are 17-digit UPC-style**, 1 real ISBN-13 | `Code` (our `item_code` shape) **plus** a separate `UPC` |
| Catalog-month span | n/a | **4 months in one order** — `0626`×129, `0526`×19, `0426`×3, `0326`×1 |

**Match feasibility against the production catalog — the number that decides whether this is worth building:**

- **PRH: 28 / 31 lines matched (90%).** The three misses are real comics not in our catalog (Magic: The Gathering — Jace #4, MARVEL KNIGHTS #6 ×2) — titles ordered outside the pull-list catalog.
- **Lunar: 137 / 149 codes matched (92%).** The misses are almost entirely **promo posters, ashcans and free bundles** (`…DC8606 BATMAN BAD SEEDS PROMO POSTER`, `LAST DRIVER #1 ASHCAN PROMO`, …) — items that correctly do not exist in a customer-facing catalog.
- **Of the matched lines, 28/31 (PRH) and 122/149 (Lunar) correspond to a title with an *open founding-tenant reservation*** (measured against 1,343 open reservations / 1,190 distinct reserved keys). These orders are overwhelmingly customer-driven, which is precisely why ingesting them removes so much panel noise.
- **Volume:** roughly **180 ledger rows per monthly ingest** (31 + 149). Against 857 today, ~2,200/year. `loadOrderLedger()` was paginated on 2026-08-04 (F116) — that fix is now load-bearing rather than precautionary.

#### 2.9.1 Netting is mandatory, and the schema will reject the raw file

Lunar carries **3 negative-quantity lines**, and each cancels an earlier positive line for the same code:

| Code | Net | Title |
|---|---|---|
| `0626DC0232` | **0** | DC CONNECT #75 OPT-IN BUNDLES OF 25 (FREE) (NET) |
| `0526IM0377` | **0** | HYDE STREET #14 CVR A IVAN REIS & DANNY MIKI **Cancelled** |
| `0626DE0825` | **0** | VAMPIRELLA VS RED SONJA RED CITY #1 CVR G … VIRGIN VAR |

`order_submissions` has **CHECK `quantity >= 1`**. A row-per-line ingest therefore **fails outright** on the first negative line — not silently, but the import breaks. **Ingest must net by code within a file before writing, and skip codes whose net is 0.** Writing a `1` for a cancelled title would be worse than the current false alarm: it would tell the panel a cancelled book is on order.

#### 2.9.2 Cancellation is signalled in free text, not a column

Two Lunar lines carry the word **`Cancelled` appended to the title**. There is no status column to read it from. Netting (§ 2.9.1) catches these correctly *without* parsing the title, which is the robust path — **do not build a title-text matcher**; it is a fragile signal that happens to agree with the arithmetic here.

#### 2.9.3 PRH's `Order Status` is the F110 trap, exactly repeated

**31 of 31 lines read `Backordered`.** This is the same shape as F110's discovery that `*_full_active.csv` was 871/871 `IP / Active`: **a status column that never varies is not a signal.** It is also the F112 collision in its most dangerous form — the literal string `Backordered`, meaning *ordered and awaiting fulfilment*, one column away from our own `Backordered`, meaning *never ordered*. **This column must not be ingested, stored, or displayed.**

#### 2.9.4 Correction — the rich supplier state is screen-only

§ 4.2 was written from the web UIs, which show Lunar's per-line **Shipped / Partially Shipped / Processing**, ship date, in-store date and Due Date, and PRH's **Est Delivery**. **None of that is in either export.** The Lunar CSV has no dates and no status at all; PRH has no date column in its line table.

**Consequence: `supplier_status`, `expected_date` and `status_as_of` have no source and are cut from Session B** (§ 4.2, rewritten). Anything that depends on them — including the customer-facing *"Ordered — expected Aug 12"* in § 4.4 — is **not deliverable from these files** and needs a separately-sourced feed before it can be planned. Had Session A been skipped, Session B would have built three columns with nothing to populate them.

#### 2.9.5 Correction — Lunar's order number is not in the file

The natural key proposed at § 4.1 assumed a supplier order id available per line. **Lunar's export contains no order number**; it exists only in the filename `Order_1853046.csv`. PRH's is properly in the header (`Order Number`, and a distinct `Purchase Order Number`). So the two distributors need **different key-derivation strategies**, and Lunar's depends on a filename the operator could rename. See § 4.1, rewritten.

Related: **Lunar supplies no order date**, yet `submitted_on` is **NOT NULL**. PRH supplies `Order Create Date` in ISO form and needs no help.

#### 2.9.6 Parsing hygiene, all confirmed against the real bytes

- The PRH file begins with a **UTF-8 BOM**.
- Its `Bill To` / `Ship To` header values contain **embedded newlines inside quoted fields** — a line-splitting parser corrupts the file. A real RFC4180 parser is required, not `split('\n')`.
- The PRH file is **two tables in one**: locate the row beginning `Line,Description,ISBN` and parse the line items from there; treat everything above it as header key/values.
- PRH `Line` numbers are **not monotonic** (200 precedes 170) — never infer ordering from them.
- Lunar has **3 UPCs with a trailing `x`** (`70985304127601411x`), and **14 zero-retail** promo/bundle rows with an **empty-string** `Discount` field.
- Lunar's `Code` matches our `item_code` shape; its `UPC` column carries real ISBN-13s for trade paperbacks. **Both distributors therefore need the F76 three-key match** (`item_code` / `upc` / `isbn`) — a single-column join on PRH's misleadingly-named `ISBN` field would silently under-match.

#### 2.9.7 Independent corroboration of F111

One Lunar order spans **four catalog months** (`0626`, `0526`, `0426`, `0326`). F111 was derived from our own reservation data; the supplier's own order file shows the same structure from the other side. Nothing to do — it simply confirms the cross-month gather shipped on 2026-08-03 was modelling reality.

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

> **Revised 2026-08-04 against the real exports (§ 2.9).** The pre-file version of § 4.2 and § 4.4 was written from the vendors' web UIs and specified three columns that have **no source in either export**. Those are cut. What remains is smaller, fully sourced, and therefore buildable with confidence.

### 4.1 Idempotency and the double-count trap — the highest-risk decision

Ingest must be safely re-runnable. The ledger has **no unique constraint on `order_code` by design**, so nothing at the database level prevents a re-ingest from doubling every quantity.

**This is an F102-shaped hazard pointing at money.** F102's whole finding was that Lunar orders *ADD* to existing quantities; a ledger that double-counts a confirmation would tell the panel a title is over-ordered when it is not — or, worse, suppress a genuine re-order.

- Add **`supplier_order_id`** (text, nullable) and **`supplier_source`** (text, nullable — the filename ingested, for audit).
- Dedup key: `(tenant_id, distributor, supplier_order_id, order_code)` as a **partial unique index** where `supplier_order_id IS NOT NULL` — leaving the 857 manual/backfilled rows (all NULL) untouched and still duplicate-legal.
- **Nullable, partial, additive** — the pattern this codebase has had success with (F110 Session A).

**Where `supplier_order_id` comes from differs by distributor (§ 2.9.5), and Lunar's is weak:**

| | Source | Robustness |
|---|---|---|
| PRH | `Order Number` in the header block | **Strong** — inside the file |
| Lunar | parsed from the **filename** `Order_1853046.csv` | **Weak** — a rename breaks it |

> **PAUSE → Rick.** Lunar's key rests on a filename. Options: (i) require the operator not to rename downloads and fail loudly if the pattern does not match `Order_<digits>.csv`; (ii) derive a content hash as the key instead; (iii) prompt for the order number at ingest. **(i) with a hard failure is recommended** — it is honest, and a silent wrong key here corrupts money data. A content hash sounds safer but breaks the moment Lunar re-exports the same order with a trivial difference, which would then double-count.

**`submitted_on` is NOT NULL and Lunar supplies no date** (§ 2.9.5). PRH's `Order Create Date` is ISO and usable directly. For Lunar the same PAUSE applies — prompt, or take the file's modification time (fragile across copies), or require it as a CLI argument. **A CLI argument is recommended: explicit, auditable, and it fails closed.**

**The overlap problem, unchanged and still Rick's call:** the backfill already covers `2026-05-24`, `2026-06-27` and `2026-07-26`. Confirmations for those cycles **will** double-count, because the existing rows carry no `supplier_order_id` to match against. Options:

- (a) ingest only confirmations dated **after** a cutoff, and never re-ingest history;
- (b) reconcile against existing rows on `(distributor, order_code, submitted_on)` and skip matches;
- (c) delete and re-ingest the three backfilled cycles from authoritative confirmations.

(c) is the cleanest long-term and the most dangerous to execute. (a) is the safest and leaves history slightly wrong. **Do not choose this in code review — it is a data decision.**

### 4.2 Netting — mandatory, and it replaces the cut "richer state"

**What was here is withdrawn.** `supplier_status`, `expected_date` and `status_as_of` were specified from the web UIs; § 2.9.4 establishes that **neither export carries status or dates we can use**. Lunar's CSV has none at all; PRH's `Order Status` is 31/31 `Backordered` — the F110 uniform-column trap, wearing the F112 collision's exact vocabulary. **Nothing about supplier status or expected dates is ingested.**

What takes its place is the requirement the files actually imposed:

**Net quantities by `(distributor, order_code)` within a file before writing.** Lunar's export contains positive and negative lines for the same code (§ 2.9.1), and `order_submissions` has **CHECK `quantity >= 1`** — so a naive row-per-line ingest does not merely mis-count, it **aborts the import** on the first negative line.

- Sum all lines per code; write **one row per code**.
- **Net 0 ⇒ skip entirely.** This is the ordered-then-cancelled case (3 of 149 in the sample). Writing `1` for a cancelled title is worse than the false alarm it replaces.
- **Net < 0 ⇒ do not write; report and halt that file.** It means the file is an amendment against a prior order, which is a case this design does not handle and must not guess at.
- Do **not** parse `Cancelled` out of the title (§ 2.9.2) — netting already handles it, and free-text matching is the fragile path.

**Partial fulfilment remains out of scope and is now also out of reach** — Lunar's `Partially Shipped` exists only on screen. The long-deferred `CLAUDE.md` item stands unchanged; this plan neither advances nor blocks it.

### 4.3 What the panel becomes

Once ingest exists, `computeBackorderRisk()` gains a genuinely new capability: **"no record" becomes meaningful.** Today it means "we didn't write it down". After ingest it means "the supplier has no order for this", which is the thing the panel has always claimed to say.

Panel changes (small, deliberately — and smaller than first drafted, since there is no expected date to show):

- A row cleared by an *ingested* confirmation can name the supplier order — *"Ordered · Lunar 1853046"* — instead of vanishing silently, so the operator can distinguish "handled" from "never happened" and has something to look up. **This replaces the "expected Aug 12" idea, which has no source (§ 2.9.4).**
- The **At risk** bucket stays exactly as-is; it is already correct and is the panel's most valuable output (both current At risk rows, FOC 8/31, are real).
- **Precision becomes measurable.** Record it at the first two ingests, the same way F110 § 2.4 required recording the set-difference noise rate.
- **Expect the panel to get much quieter, and verify that is honest rather than assumed.** ~180 rows land per ingest and 28/31 + 122/149 of them match open reservations (§ 2.9). A panel that empties out is the intended outcome *and* the classic symptom of an over-broad clearing rule — so the first ingest must be checked against a title known to be genuinely un-ordered.

### 4.4 Customer-facing status — deferred, and now blocked on a source that does not exist

The original payoff was My List reading **"Ordered — expected Aug 12"**.

**§ 2.9.4 removes the date half of that.** Neither export carries an expected-delivery date; Lunar's in-store date and PRH's Est Delivery are visible only in the browser. So the deliverable shrinks to **"Ordered"**, with no date — which is worth something, but far less, and it is worth deciding whether that alone justifies touching a customer surface.

Still requires an explicit product decision, because it converts an internal record into a **promise to a customer**:

- Is a bare *"Ordered"* (no date) worth showing at all?
- If a date is genuinely wanted, where does it come from? Our own `catalog.on_sale_date` is already accurate (§ 2.1 — it matched both suppliers exactly on all four titles), so *"Ordered · expected on sale Aug 12"* could be sourced entirely from data we already hold, with no supplier feed at all. **That is probably the better answer, and it does not depend on this plan.**
- Interaction with the F110 withdrawn flag and the F72 email-branding thread.

---

## 5. Scope

### IN
- **Session A:** obtain and characterise both suppliers' confirmation exports; produce the field mapping and the idempotency decision. **No code.**
- **Session B:** additive schema + ingest into `order_submissions`, idempotent, unit-tested, dry-runnable.
- **Session C:** panel reads ingested state; expected dates surfaced to the admin.
- **Session D:** customer-facing status — only after § 4.4's product decisions are answered.

### OUT — stop and ask
- **Supplier status and expected dates.** Cut 2026-08-04 — **no source exists in either export** (§ 2.9.4). Do not reintroduce them from the web UIs.
- **Reasoning over partial quantities.** Out of scope and now also out of reach — `Partially Shipped` is screen-only.
- **Parsing `Cancelled` out of title text** (§ 2.9.2). Netting handles it; free-text matching is the fragile path.
- **Any change to `isFocPast`/`isFocLocked`**, or to the FOC lock's customer semantics.
- **Automating order *placement*.** This ingests confirmations of orders a human placed; it never submits anything.
- **Re-ingesting the three backfilled cycles** unless Rick explicitly picks option (c) at § 4.1.
- **Catalog ingestion** — § 2.1 confirms it is accurate; leave it alone.
- **F72, F89, F90, F92, F93, F104, F105, F107, F109.** Phase 6. `config.js`, credentials, Edge Functions.

---

## 6. Runbook

### Session A — obtain and characterise — **SUBSTANTIALLY COMPLETE 2026-08-04**

Both exports were obtained and characterised; findings are recorded at **§ 2.9**, and **V-A1 is green** — every field Session B will write traces to a named column in a real file with a quoted example. The session did its job: it cut three unsourceable columns (§ 2.9.4) and corrected the key design (§ 2.9.5) before either reached code.

**Still open, and all three are Rick's calls — Session B cannot start without them:**

1. **Lunar's order-number source** (§ 4.1) — filename parsing with a hard failure, content hash, or prompt. *Recommended: filename + hard failure.*
2. **Lunar's `submitted_on`** (§ 4.1) — CLI argument, prompt, or file mtime. *Recommended: CLI argument.*
3. **The backfill-overlap option** (§ 4.1) — (a) cutoff, (b) reconcile, or (c) delete-and-re-ingest. *Recommended: (a).*

**Also still unverified, and worth one minute when the next confirmation is downloaded:** whether re-downloading the *same* order yields a byte-identical file. It only matters if option (ii) — content hashing — is chosen for #1; the recommended filename approach does not depend on it.

### Session B — ingest (schema + scripts repo)

1. `docs/sql/order-submissions-supplier-fields.sql` — additive nullable `supplier_order_id`, `supplier_source` + the partial unique index (§ 4.1). > **PAUSE → Rick** to run on staging, then production.
2. Parsers as **pure exported functions** in the private scripts repo, unit-tested against the two real sample files. Follow the `findUnverifiedFulfillments` / `parseInitialOrderDue` precedent: pure, exported, present in both scripts, parity-checked. **Must include an RFC4180-capable reader** — the PRH file has a BOM and multi-line quoted header fields, so `split('\n')` corrupts it (§ 2.9.6).
3. **Net by code before writing** (§ 4.2): one row per code, skip net-0, halt on net-negative.
4. Idempotent upsert. **Gate V-B1** (money safety): ingesting the same confirmation twice produces the same row count **and** the same total quantity.
5. **Gate V-B2** (netting): ingesting `Order_1853046.csv` writes **149 − 3 = 146** rows, with `0626DC0232`, `0526IM0377` and `0626DE0825` **absent**, and no row violating `quantity >= 1`.
6. **Gate V-B3** (match rate): the ingest reports its match rate and it is **≥ 90%**, with every miss listed. Regression alarm — a sudden drop means a code-format change, which is how F84 and F110 both began.
7. **Gate V-B4:** `--no-write` prints the full plan and writes nothing.
8. Record the § 4.3 precision measurement before and after the first real ingest.

### Session C — surface (client)

1. Panel names the supplier order on rows cleared by ingest (§ 4.3); "no record" wording updated to reflect that it now means something. **No expected date — there is no source for one (§ 2.9.4).**
2. Extend **spec 15**. **Gate V-C1:** a title cleared by an ingested confirmation renders its supplier order reference; a title with genuinely no supplier record still reads Backordered.
3. `/deploy-staging` — push first, then run the suite (CLAUDE.md § Smoke-test ordering).

### Session D — customer-facing (gated on § 4.4 answers)

Not specified here. Do not start without the § 4.4 product decisions recorded in this document.

---

## 7. Verification gates

| Gate | Session | Assertion | Why this one |
|---|---|---|---|
| **V-A1** ✅ | A | Every planned field traces to a real column in a real file, with an example value | Screenshots are not a schema — the F110/F112 lesson. **Green 2026-08-04**; it cut three unsourceable columns |
| **V-B1** | B | Double-ingest ⇒ identical row count **and** total quantity | The F102 double-count hazard, pointed at money |
| **V-B2** | B | `Order_1853046.csv` writes **146** rows; the three net-0 codes absent; no `quantity < 1` | Netting is mandatory — the raw file otherwise violates the CHECK and aborts (§ 2.9.1) |
| **V-B3** | B | Reported match rate **≥ 90%**, every miss listed | Measured baseline is 90% PRH / 92% Lunar; a drop means a code-format change, which is how F84 and F110 began |
| **V-B4** | B | `--no-write` writes nothing | Every import path in this codebase has this property |
| **V-C1** | C | Cleared-by-confirmation names its supplier order; genuinely-unordered still reads Backordered | Proves the panel gained information rather than just going quiet |

---

## 8. Completion criteria

### Session A — substantially complete 2026-08-04
- [x] Real confirmation files obtained for **both** distributors (`catalogs/order-confirmations/`)
- [x] § 2.9 written from the files, not screenshots; **V-A1** green
- [x] Match feasibility measured against live production — 90% PRH / 92% Lunar, misses categorised
- [x] Committed doc-only to `staging`
- [ ] § 4.1 Lunar order-number source decided by Rick
- [ ] § 4.1 Lunar `submitted_on` source decided by Rick
- [ ] § 4.1 backfill-overlap option decided by Rick

### Session B
- [ ] Additive columns live on staging **and** production, all nullable, existing 857 rows untouched
- [ ] RFC4180 reader handles the BOM and multi-line quoted header fields (§ 2.9.6)
- [ ] Netting implemented: one row per code, net-0 skipped, net-negative halts (§ 4.2)
- [ ] Parsers pure, exported, unit-tested against the real sample files; parity across both scripts
- [ ] **V-B1**, **V-B2**, **V-B3**, **V-B4** green
- [ ] Precision measurement recorded before/after the first real ingest

### Session C
- [ ] Panel surfaces ingested state; spec 15 extended; **V-C1** green; full suite green
- [ ] Fixtures torn down, verified by live SELECT returning zero rows

### Session D
- [ ] § 4.4 product decisions answered **before** any code — including whether a bare "Ordered" is worth showing at all, given the expected-date source does not exist

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
