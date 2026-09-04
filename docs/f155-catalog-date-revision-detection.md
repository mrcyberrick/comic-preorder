# F155 — Catalog date-revision detection

**STATUS:** NOT STARTED · staging=— · prod=— · PR=— · findings: F155

Owner doc for F155. Full finding narrative lives in `docs/technical-reference.md` § 13 F155;
this doc is the execution plan.

---

## 0. Why this exists

A distributor revises a title's in-store date after solicitation. Our catalog keeps the original.
Once that stale date passes, three things happen in order, all silent:

1. **The customer loses sight of it first.** `mylist.html:937` scopes the My List table to
   `catalog_month === currentMonth`, and `mylist.html:884` scopes Upcoming Arrivals to
   `on_sale_date >= today`. A title from an older month whose stale date has just passed is in
   **neither**. `classifyReservedDateDrift()` already names this exact state — its `stranded`
   list carries a `hidden` flag whose comment reads *"the customer cannot see it at all."*
2. **It never reaches a bagging list.** This Week is keyed on `on_sale_date`. The stale week has
   passed; the real week will never match.
3. **It is marked fulfilled.** `auto_fulfill_past_on_sale()` sets `fulfilled = true` at the next
   import, and F115 writes `arrival_outcome = 'unknown'`. Only *now* does it surface, in Never
   Arrived — after the customer has been told "Order placed" for a book that has not shipped.

Found live by Rick, 2026-09-04: **DNX #1 [HIDDEN/DOUBLE COVER]** (PRH `75960621519500111`),
solicited 2026-05 with in-store 2026-09-02, revised by PRH to **2026-09-16**. Two reservations.
PRH's website and the order invoice both show 09/16; **no file we can download does.**

---

## 1. What was measured (2026-09-04, production, read-only)

Load-bearing facts. Do not re-derive; re-measure if this date is stale.

### 1.1 Both distributors revise dates in place — while a catalog is live

Freshly-downloaded files vs. live production `catalog` rows:

| File | Titles whose in-store date differs from the DB |
|---|---|
| PRH 2026-07 | **108** (4 with open reservations) |
| PRH 2026-06 | 27 |
| PRH 2026-08 | 19 |
| PRH 2026-09 | 4 |
| PRH **2026-05** | **0 of 1,078** |
| Lunar (All Products) | **13** across 2026-07 / 2026-08 |

Revisions move in **both directions**. `FIRE AND ICE #5` (Lunar `0826DE0733`) moved
**2026-10-28 → 2026-09-30** — a month *earlier*. That direction is operationally worse: the book
arrives before the bagging list expects it.

### 1.2 PRH freezes a catalog ~2 months before its last titles ship

- May master data: **byte-identical MD5** (`438958a0b69b961ab140ab63c9b3f3bf`) across two
  downloads 44 minutes apart, and **0 of 1,078 rows** differ from what was imported in May.
- May's Weekly Change Reports run **2026-04-24 → 2026-07-31 and stop.** Rick holds the final one;
  DNX #1 does not appear in it (0 occurrences, grepped).
- **84 May titles are still future-dated today.** PRH stops maintaining the catalog while a tenth
  of it has yet to ship.
- No re-listing channel: **0 of 5,123** PRH `MainIdentifier`s appear in more than one monthly file,
  so `auto_fulfill_past_on_sale()`'s newest-listing logic (F122) can never rescue a PRH title.

**Consequence, and it is the pivot of this whole plan: for a frozen PRH catalog, no data channel
exists.** DNX #1's real date is unreachable from any PRH export. Detection cannot solve it; only
the guard (S3) can.

### 1.3 Lunar's All-Products export is one file and covers everything

`Lunar Available Products - <MMDDYYYY>.csv`, from Resources → **All Products CSV Order Form**:

- **17,490 rows**, catalog months back to at least 2025-08
- Columns: `Code, Qty, Title, Retail, Due Date, FOC, In-Store, UPC, ISBN, EAN, Category,
  Publisher, Notes, Imprint, CountryOfOrigin, TitleNote`
- Covers **559 of 568 (98.4%)** distinct Lunar codes holding open reservations
- One download. No code lists, no paste batches, no per-month navigation.

The 9 uncovered codes (7× 2026-07, 2× 2026-06) are the file's one limit: it lists *available*
products, so sold-out and withdrawn items drop out. `0726DC0300` (DC CONNECT #76 bundle, past
on-sale) is one of them. **Those belong to the guard, not to detection.**

### 1.4 Guard load is small

- F115's real September production import classified **arrived=212, unknown=6**.
- Today, **7 titles** would be affected by S3's deferral.
- **0 titles** currently show shipment evidence against a future DB date — the early-arrival case
  is real per § 1.1 but has no live instance, so it is handled in S2's report, not the guard.

### 1.5 The runbook actively tells the operator not to look

`docs/monthly-catalog-refresh.md:130-132`:

> *"Repeat for PRH's still-open months **if** its active-export file has been re-downloaded; PRH's
> export omits withdrawn titles rather than revising dates in place (see F110), so **this step
> matters most for Lunar**."*

Measurably false — § 1.1. This is why PRH months have never been re-pulled, and it is the finding
proper.

---

## 2. Scope

**IN**
- S1 — correct the runbook line (doc-only)
- S2 — `check-dates.js`: a weekly, targeted date re-check reusing `classifyReservedDateDrift()`
- S3 — bounded deferral in `auto_fulfill_past_on_sale()` + the admin panel change that keeps
  deferred rows visible

**OUT — deliberately**
- **Recovering frozen PRH catalogs.** Measured impossible (§ 1.2). Not a scoping choice.
- **A sticky "manually corrected" column.** Re-importing a frozen month restores the stale date.
  v1 answer is the runbook note in S1; a schema-level override is separate work.
- **Notifying customers when a date moves.** Rick, 2026-09-04: *"Even late corrections help reset
  expectations with in-store dates."* Worth doing; not this plan.
- **Changing what `auto_fulfill_past_on_sale()` does once evidence exists.** Unchanged.
- **`import.js`'s monthly Step 3 sweep.** S2 complements it; it is not replaced.

---

## 3. S1 — runbook correction (doc-only, ship first)

Rewrite `docs/monthly-catalog-refresh.md` Step 3 item 4 to state:

- PRH **does** revise `OnSaleDate` in place in master data, for as long as the catalog is live
  (§ 1.1) — and its website agrees with the file, confirmed by Rick 2026-09-04 against
  `82771403586500111` / `82771403545200211`, so **master data is authoritative for a live catalog**
- PRH master data **freezes** ~3 months past the catalog date, and change reports stop with it
  (§ 1.2) — past that point the month is unrecoverable and only S3 protects it
- Lunar publishes only **three** monthly files, but the All-Products export covers every month
  (§ 1.3) — prefer it
- **Re-importing an older month restores whatever that file says**, so any hand-corrected date is
  silently reverted by the F146 withdrawal-clearing sweep. Re-run S2 after any older-month import.

No code. Ships independently of S2/S3.

---

## 4. S2 — `check-dates.js` (detection)

New script in the **scripts repo**, alongside `f136-audit.js` / `reconcile-shipment.js`.
Deliberately **not** a flag on `import.js`: that script archives, purges, upserts a whole month and
auto-reserves, and none of that may happen here.

### 4.1 Operator workflow — 2 files, 3 actions, Friday/Saturday

Cadence set by Rick 2026-09-04: he pulls shipment files Friday/Saturday, arrivals land Monday,
fulfilment runs Wednesday. Corrections therefore land **four days ahead** of the run that would
otherwise mis-fulfil them.

1. Lunar → Resources → **All Products CSV Order Form** → save to the re-check folder
2. PRH → the live catalog the script names → **Master Data** → save to the same folder
3. `node .\check-dates.js`

Per Rick's *"limit number of steps when possible"*: **one command, one inline prompt**, matching
`import.js`'s own convention. No dry-run/`--write` two-step.

### 4.2 Behaviour

- Reads every CSV in the folder; detects Lunar-vs-PRH by header shape (`Code`/`In-Store` vs
  `MainIdentifier`/`OnSaleDate`)
- Matches DB `catalog.item_code` to Lunar `Code` / PRH `MainIdentifier`
- Feeds `classifyReservedDateDrift()` (`import.js:517`) — **reused, not reimplemented**, so the
  `corrected` / `stranded` / `unreserved` split and the `hidden` flag come for free
- **Reports both directions**, and flags *earlier* moves separately — a title pulled forward misses
  its bagging week, which no existing surface catches (§ 1.1)
- Names which PRH catalogs to pull next run, from open-reservation counts, so the operator never
  has to work it out
- Hashes each PRH master file and warns when a catalog's master data stops changing — *"2026-06
  master unchanged for 3 weeks; that catalog is freezing"* — turning § 1.2's boundary from
  something the operator must track into something the script says
- Writes **only** `on_sale_date` / `foc_date` on rows that already exist. Never inserts, archives,
  purges, or auto-reserves.
- Honours `--no-write`, like every other write in this codebase

### 4.3 Scope of what gets re-checked

Codes with **open (unfulfilled, not withdrawn) reservations** whose on-sale date has passed or
falls within 30 days. Measured 2026-09-04: 223 Lunar / 184 PRH. Nothing falls through permanently —
every title passes through the 30-day window before its on-sale date.

---

## 5. S3 — bounded deferral (the guard)

### 5.1 This reverses a recorded decision. Deliberately, and here is the argument.

`docs/f115-arrival-truth-persistence.md:209` records Option A — giving `auto_fulfill_past_on_sale()`
an arrival check — as **rejected**. `import.js`'s own `findUnverifiedFulfillments()` docblock states
the reason in the code:

> **REPORTS, NEVER BLOCKS.** Absence of a shipment row is not proof of non-arrival … so gating
> fulfillment on this would trade a silent miss for a silent stall.

**That objection was correct and still is.** So S3 does not block. It **defers, bounded**, and
guarantees visibility during the deferral:

- Shipment evidence present → fulfil immediately. **Unchanged** (212 of 218 rows, § 1.4).
- No evidence → defer until `on_sale_date + GRACE_DAYS`, then fulfil exactly as today, with
  `arrival_outcome = 'unknown'`.

Nothing stalls forever. The deferral buys precisely the window S2 needs to correct a stale date, or
the next invoice needs to land. **`GRACE_DAYS = 14`** — two full shipment cycles on Rick's
Friday/Monday/Wednesday rhythm.

### 5.2 The half that makes the deferral safe

A deferred row is `fulfilled = false`, so `neverArrivedFromFulfilled()` (`admin.html:1724`) does
**not** pick it up — it requires `p.fulfilled`. It falls instead to `computeBackorderRisk()`, whose
very first test is:

```js
if (ledgerNetQty(c.distributor, code) > 0) return;   // ordered — cleared
```

**Ordered ⇒ invisible.** That is exactly why DNX #1 surfaced on no panel, and why Rick found the
Mark Ordered button correctly `disabled` (ledger 2 = reserved 2, nothing left to order) with no
other control to reach for.

So S3(b): in `computeBackorderRisk()`, move the past-on-sale test **above** the ledger exit, so a
released title with no arrival record reaches Never Arrived whether or not it was ordered. The
existing F134/F143 resolve controls then apply unchanged.

**Without S3(b), S3(a) recreates the exact silent stall F115 rejected.** They ship together.

### 5.3 Files

| File | Change |
|---|---|
| `docs/sql/auto_fulfill_past_on_sale.sql` | grace window; `s.on_sale_date < CURRENT_DATE` becomes evidence-aware |
| `admin.html` | `computeBackorderRisk()` test order (§ 5.2) |

---

## 6. Verification gates

| Gate | What | Passes when |
|---|---|---|
| **V1** | S1 doc accuracy | Every claim in the rewritten Step 3 traces to a § 1 measurement |
| **V2** | `check-dates.js` parses both formats | Lunar 17,490 rows and a PRH master file both read; header detection picks the right branch |
| **V3** | Reproduces the known answer | Run against 2026-09-04's files: **13** Lunar and **108** PRH 2026-07 drifted titles, matching § 1.1 |
| **V4** | `classifyReservedDateDrift()` reused, not forked | `git diff` shows no second date-diff implementation |
| **V5** | Write scope | `--no-write` run touches nothing; real run updates only `on_sale_date`/`foc_date`; `catalog` row count unchanged before/after |
| **V6** | Direction-awareness | `FIRE AND ICE #5` (`0826DE0733`, 10-28 → 09-30) appears, flagged as *earlier* |
| **V7** | Guard defers, never blocks | Unit test: no evidence + `on_sale_date + 15d` → fulfils. Same row at `+13d` → deferred |
| **V8** | Guard preserves today's behaviour where evidence exists | Re-run against September's real import shape: the 212 arrived rows still fulfil |
| **V9** | Deferred rows are visible | A deferred, **ordered** row appears in Never Arrived with resolve controls — negative-control tested by reverting S3(b) and confirming it disappears |
| **V10** | No regression | `npm test` green; full Playwright suite 143 passed, 0 failed, against deployed staging bytes post-push |
| **V11** | Live | One real `check-dates.js` run on staging, changes verified by an independent fresh DB read — not the script's own output |

V3, V6 and V9 are the ones that can actually fail. V9 must be negative-control tested: assert it
red with S3(b) reverted before trusting it green.

---

## 7. Open questions

| # | Question | Status |
|---|---|---|
| Q1 | `GRACE_DAYS = 14` — right number? | Proposed. Two shipment cycles. Rick's call |
| Q2 | Sticky override so a re-import can't revert a hand-fix | **Deferred**, § 2 OUT. Revisit if it bites |
| Q3 | Tell the customer when a date moves | **Deferred**, § 2 OUT. Rick has said it has value |
| Q4 | The 9 Lunar codes absent from All-Products | Accepted — guard covers them |
| Q5 | Does the freeze boundary move? | S2's hash warning measures it over time rather than guessing |

---

## 8. Completion criteria

- [ ] S1 committed; every Step 3 claim traces to a § 1 measurement
- [ ] S2 built, V2–V6 green
- [ ] S3(a) + S3(b) shipped **together**, V7–V9 green, V9 negative-control tested
- [ ] V10 full suite green against deployed staging bytes post-push
- [ ] V11 one real staging run, independently verified
- [ ] The 3 exposed titles (§ 9) corrected and confirmed
- [ ] `docs/technical-reference.md` § 13 F155 status updated
- [ ] `CLAUDE.md` findings row updated
- [ ] Production promotion **not** attempted without an explicit request

---

## 9. Exposed today (production, 2026-09-04)

Unfulfilled, on-sale passed, no shipment evidence, actually ordered:

```
PRH   75960621519500111  on-sale 2026-09-02  ordered 2  reserved 2  DNX #1 [HIDDEN/DOUBLE COVER]
PRH   75960621519500122  on-sale 2026-09-02  ordered 1  reserved 1  DNX #1 JIM LEE HIDDEN GEM VARIANT
Lunar 0726DC0300         on-sale 2026-09-02  ordered 1  reserved 1  DC CONNECT #76 BUNDLES
```

Plus the **13 Lunar titles** in § 1.1 whose dates are already known-stale.

**These do not need this plan.** They are hand-fixable now, and should be — the two DNX #1 rows are
still `fulfilled = false`, so the false fulfilment has not happened yet. The next import fires it.
