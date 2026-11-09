# Order Follow-Up — marks that survive imports, actions for every section, and an SOP

**STATUS:** NOT STARTED (planned 2026-11-09) · staging: — · prod: — · PR: — · findings: F180 (filed 2026-11-09, open)

Owner of the defect record: `docs/technical-reference.md` § 13 F180. This doc is the plan.

---

## 1. Rick's report and the cause

**Report (2026-11-09, production).** *Sh\*t My President Says: The Illustrated Tweets of Donald J.
Trump* (`9781603096270`) was marked **Received** on Order Follow-Up and left the list. The next weekly
import put it back for another follow-up.

**Cause (read from the code; the production rows were not read, the session's permission check refused
it).** Step 9 of every import run, `reportUnverifiedFulfillments()` (`import.js:1517-1589`, identical in
`import-staging.js`), selects every reservation that is still open (`fulfilled = false`) and past its
on-sale date, decides `arrived` (an invoice line matches) or `unknown`, and writes that value onto all of
them (`writeArrivalOutcomes()`, `:1490`). It never reads the value already there, so an admin's mark is
replaced with `unknown`.

It repeats because, since F155 S3(a) (2026-09-05), `auto_fulfill_past_on_sale()` keeps a title with no
invoice line open for 14 days after on-sale. The row is still open at one or two later weekly imports and
is overwritten each time. After 14 days it closes, the import stops selecting it, and a second mark then
sticks.

**The customer-facing half.** "Didn't arrive" and "Damaged" are overwritten the same way. Those two
values are what put a reservation in My List's "No longer coming" section, so the customer's notice
disappears at the next import.

**Possible second cause, unconfirmed:** why no invoice line cleared this title in the first place. For a
PRH delivery the invoice row's `catalog_id` is whichever catalog listing the lookup returned first for that
UPC/ISBN (`buildCatalogIdMap()`, `import.js:1611-1612`), and every "did it arrive" check matches on
`catalog_id`, `upc` or `item_code`, never `catalog.isbn`. A reprinted book reserved on a different listing
would read as never arrived after it shipped. S0 checks this.

## 2. Decisions

**Rick, 2026-11-09 (answers to the scoping questions):**

| # | Question | Answer |
|---|---|---|
| D1 | A "waiting on the distributor" state | **Snooze with a date and a note, as an optional action.** Received means resolved; Snooze is for "still finding out". |
| D2 | Actions on Backordered and At risk rows (none today) | **Both: Mark Ordered from the row, and Can't get it.** |
| D3 | Tell customers directly when a title is marked Didn't arrive / Damaged | **No. My List only, as now.** No email. |
| D4 | Where the SOP lives | **One line under each section in the panel, plus a "How to handle these" help page.** |
| D5 | What a customer reads after Can't get it | **A new neutral line: "Not available — the store could not get this title."** Customer can remove it. Not "Rejected by the supplier", which blames the supplier when the store missed the cutoff. |
| D6 | A title marked Didn't arrive that later appears on an invoice | **Bring it back once**, labelled "On an invoice after it was marked Didn't arrive", with a Received button. |

**Calls made in planning (Rick can overturn any of them):**

- **C1. Received still writes only the arrival status.** It must not tick the reservation closed:
  `fulfilled` is the bagging list's "Picked up" checkbox (`admin.html:4505`). The 14-day auto-close runs
  as today.
- **C2. Snooze, notes and "who did what, when" live in a new admin-only table, `order_follow_ups`, one row
  per title** (tenant, distributor, order code). Not on `preorders`: customers can update their own
  reservation rows (`users manage own preorders` is an ALL policy, `technical-reference.md` § 7.1), and a
  per-reservation snooze would lapse the moment a new customer reserved the title. The import never
  touches this table.
- **C3. Can't get it gets a confirm**, like Rejected by supplier (Rick, 2026-09-05: no in-app recovery, so
  confirm). Received / Didn't arrive / Damaged stay one click with no confirm and no undo (Rick,
  2026-10-04). **Now that marks stick, a wrong mark stays wrong until the operator fixes it in the
  database.** The help page says so.
- **C4. The new status value is `not_available`, not `unavailable`.** `app.js` already uses
  `orderState === 'unavailable'` for a ledger rejection (`app.js:2026`); reusing the word would blur two
  different statements.
- **C5. The help page is a static page with no app nav** (`help-order-follow-up.html`, like `policy.html`),
  so the seven-page nav sync set stays at seven. It names no store, because other shops use the same
  panel. **It is the SOP:** there is no second Markdown copy to drift.
- **C6. Snoozed rows do not light the Customers attention dot.** A standing "N snoozed — Show them" line
  keeps them findable (the Pending Accounts "Hide" pattern, PR #153).

## 3. The list after this work

| Section | Appears when | Actions | What the customer sees after |
|---|---|---|---|
| **At risk** | Not ordered yet, and its final order cutoff (FOC) falls on or before this cycle's Order Deadline (set on the Admin dashboard), or within this month when no deadline is set | **Mark Ordered** · **Can't get it** · Snooze | Ordered: "Order placed". Can't get it: "Not available — the store could not get this title." (can remove) |
| **Backordered** | Its FOC has passed, it was never ordered, and it is not on sale yet | **Mark Ordered** · **Can't get it** · Snooze | Same as At risk |
| **Never arrived** | Its on-sale date has passed and no invoice line shows it came (ordered or not) | Received · Didn't arrive · Damaged · Rejected by supplier (only when an order is on record) · Snooze | Received: nothing changes. Didn't arrive / Damaged: "No longer coming", "Store is handling this" (cannot remove). Rejected: "Rejected by the supplier" (can remove) |
| **Turned up after all** *(new, inside Never arrived)* | Marked Didn't arrive, then an invoice line imported after the mark lists it | Received · Didn't arrive (keep) | Received clears "No longer coming"; keeping it records a new mark time, so it does not come back again |
| **Snoozed** *(hidden; "N snoozed — Show them")* | You snoozed it and the date has not come | Wake now · the section's own actions | Nothing changes |

Bold = new. A row also clears by itself when it is ordered (At risk / Backordered), an invoice line
matches, a supplier rejection is recorded, or the distributor withdraws the title (it moves to the
Withdrawn panel, which stays read-only by F110's design).

## 4. Sessions

One session each, in this order. S3 and S4 are built separately and promoted together, because Can't get
it (S3) is only safe once My List can show its result (S4).

### S0 — read-only data check (Rick, Supabase SQL Editor, production, about 5 minutes)

Confirms F180 on the real rows and sizes the second-cause question. SELECT only. Paste back the results.
The SQL Editor shows only the last statement's result, so run the two queries separately.

**Query 1, the example title:**

```sql
WITH t AS (SELECT id FROM tenants WHERE slug = 'rjbookstop'),
c AS (
  SELECT c.* FROM catalog c JOIN t ON c.tenant_id = t.id
  WHERE '9781603096270' IN (c.item_code, c.upc, c.isbn)
)
SELECT
  (SELECT json_agg(json_build_object('month', catalog_month, 'dist', distributor, 'item_code', item_code,
          'upc', upc, 'isbn', isbn, 'on_sale', on_sale_date)) FROM c) AS listings,
  (SELECT json_agg(json_build_object('month', c.catalog_month, 'qty', p.quantity, 'fulfilled', p.fulfilled,
          'fulfilled_at', p.fulfilled_at, 'outcome', p.arrival_outcome))
     FROM preorders p JOIN c ON p.catalog_id = c.id) AS reservations,
  (SELECT json_agg(json_build_object('week', w.on_sale_date, 'dist', w.distributor, 'item_code', w.item_code,
          'upc', w.upc, 'on_a_reserved_listing', w.catalog_id IN (SELECT id FROM c), 'qty', w.quantity))
     FROM weekly_shipment w JOIN t ON w.tenant_id = t.id
     WHERE w.catalog_id IN (SELECT id FROM c) OR '9781603096270' IN (w.item_code, w.upc)) AS invoice_lines,
  (SELECT json_agg(json_build_object('type', o.order_type, 'qty', o.quantity, 'on', o.submitted_on))
     FROM order_submissions o JOIN t ON o.tenant_id = t.id
     WHERE '9781603096270' IN (o.order_code, o.item_code)) AS order_lines;
```

Expected if F180 is the whole story: the reservation reads `outcome: "unknown"`. If `invoice_lines` is
non-empty but none is `on_a_reserved_listing: true` and the reserved listing's `upc` is null, the second
cause is confirmed too.

**Query 2, how many open or unknown reservations an ISBN key would clear:**

```sql
WITH t AS (SELECT id FROM tenants WHERE slug = 'rjbookstop'),
o AS (
  SELECT p.id, c.id AS cid, c.upc, c.item_code, c.isbn
  FROM preorders p JOIN catalog c ON c.id = p.catalog_id JOIN t ON p.tenant_id = t.id
  WHERE c.on_sale_date < CURRENT_DATE
    AND (p.fulfilled = false OR p.arrival_outcome = 'unknown')
    AND NOT EXISTS (SELECT 1 FROM weekly_shipment w WHERE w.tenant_id = p.tenant_id
          AND (w.catalog_id = c.id OR (c.upc IS NOT NULL AND w.upc = c.upc)
               OR (c.item_code IS NOT NULL AND w.item_code = c.item_code)))
)
SELECT count(*)                AS reservations_with_no_invoice_evidence,
       count(DISTINCT o.cid)   AS listings,
       sum(CASE WHEN o.isbn IS NOT NULL AND EXISTS (
             SELECT 1 FROM weekly_shipment w, t
             WHERE w.tenant_id = t.id AND (w.upc = o.isbn OR w.item_code = o.isbn))
           THEN 1 ELSE 0 END)  AS would_clear_with_isbn_key
FROM o;
```

If `would_clear_with_isbn_key` is above 0, file the second cause as **F181** and add S6.

### S1 — the F180 import fix (scripts repo), before Fri 2026-11-13's weekly run

The minimum change that fixes Rick's report. No schema, no app change.

- The pre-flight's reservation read adds `arrival_outcome` to its `select`.
- A new pure, exported function decides what to write: keep any row whose current value is `arrived`,
  `not_arrived`, `damaged` (or, after S2, `not_available`); classify a NULL row as today; let an
  `unknown` row become `arrived` when an invoice line now matches; skip a row whose value would not
  change.
- `writeArrivalOutcomes()`'s PATCH URL carries `&or=(arrival_outcome.is.null,arrival_outcome.eq.unknown)`,
  so a mark made between the read and the write still survives.
- The console report stops listing admin-marked titles as "about to be marked fulfilled with nothing
  showing they arrived", and prints one line: `N admin mark(s) kept`.
- Same change in `import.js` and `import-staging.js`; the parity test keeps them identical.
- Unit tests: each kept value; NULL classified; `unknown` raised to `arrived`; `unknown` left alone with
  no write. **Negative control:** remove the filter, see the keep tests go red, restore.
- **Not changed:** `auto_fulfill_past_on_sale()` (C1). A marked row still closes on the usual schedule.

### S2 — schema (Rick-run SQL, staging then production)

One file, `docs/sql/<date>-order-follow-ups.sql`, created at build time (a `PENDING` file blocks
`/promote-prod`), applied to staging first and to production before S3/S4 are promoted.

```sql
BEGIN;
-- (a) the new status value (same shape as docs/sql/f134-arrival-outcome-widen.sql)
ALTER TABLE public.preorders DROP CONSTRAINT preorders_arrival_outcome_check;
ALTER TABLE public.preorders ADD CONSTRAINT preorders_arrival_outcome_check
  CHECK (arrival_outcome IN ('arrived', 'not_arrived', 'damaged', 'unknown', 'not_available'));

-- (b) title-level follow-up state, admin-only
CREATE TABLE public.order_follow_ups (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  distributor    text NOT NULL CHECK (distributor IN ('Lunar', 'PRH')),
  order_code     text NOT NULL,
  snoozed_until  date,
  note           text CHECK (note IS NULL OR char_length(note) <= 300),
  last_action    text CHECK (last_action IN ('arrived','not_arrived','damaged','rejected',
                                             'not_available','ordered','snoozed','woken')),
  last_action_at timestamptz,
  last_action_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, distributor, order_code)
);
ALTER TABLE public.order_follow_ups ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admins manage tenant follow ups" ON public.order_follow_ups
  FOR ALL TO authenticated
  USING      (current_user_is_admin() AND tenant_id = current_tenant_id())
  WITH CHECK (current_user_is_admin() AND tenant_id = current_tenant_id());
REVOKE ALL ON public.order_follow_ups FROM PUBLIC, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.order_follow_ups TO authenticated;
COMMIT;
```

Pre-check at build time: read the live CHECK definition and confirm its name and current values first
(the F134 widen is the last recorded change). Post-checks: the CHECK lists five values; the table has one
policy; an anon request returns 401; a customer JWT reads 0 rows and cannot insert. `order_code` is the
same `exportCode()` value the panel groups by.

### S3 — the panel (staging, `admin.html`)

- **Every panel action stamps `order_follow_ups`** (upsert on tenant, distributor, order code; explicit
  `tenant_id`): `last_action`, `last_action_at`, `last_action_by`. Loaded once in `loadData()`.
- **Snooze…** on every row: a small dialog with a date (quick picks 3, 7 and 14 days; default 7) and an
  optional note. Hidden until the date, then back with "Snoozed 11/9 by Rick: emailed PRH". A "N snoozed
  — Show them" line lists them with **Wake now**. Snoozed rows do not count toward the attention dot.
- **Mark Ordered** on At risk and Backordered rows opens the existing dialog for that title
  (`openMarkOrderedModal()`, which looks across all months since F174).
- **Can't get it** on At risk and Backordered rows: a confirm naming the title and what the customer will
  read, then `arrival_outcome = 'not_available'` on every reservation the row collapsed (the same
  title-level write as Received), plus the stamp. No order entry is written, so it never reads as a
  supplier rejection. The panel's settled-outcome exit (`admin.html:1977`) clears it with no new logic.
- **Turned up after all:** a title whose stamp says `not_arrived`, with an invoice line whose
  `created_at` is later than the stamp, returns once at the top of Never arrived. The shipment load gains
  `created_at`. Marks made before S3 have no stamp and never resurface.
- **Section help:** one plain line under each section (the § 6 wording) and a "How to handle these" link
  to the help page (new tab). Replaces the current single footer line.
- **Bagging list:** a `not_available` title moves to "Not arriving this week" with the reason "The store
  could not get this title" (`admin.html:4388-4393`, next to withdrawn and rejected), so nobody hunts for
  a book that is not coming.

### S4 — the customer side and the help page (staging)

- **My List** (`mylist.html`): `not_available` joins "No longer coming" (`:1087-1089`) and the main
  table and phone cards (the same spots as Did not arrive), reading **"Not available — the store could
  not get this title."** with **Remove** allowed (`canRemove`).
- **`Preorders.cancel()`** (`app.js:2026`): allow removing a CLOSED `not_available` reservation, the same
  way a closed rejected one is allowed today. The F109 trigger already permits it (no order on record).
- **Help page** `help-order-follow-up.html`: the § 6 text, `style.css`, a back link to Admin, no store
  name, readable at 390 px. Signed-out access is fine: it holds process, not data.

### S5 — promotion

Rick checks it on staging, then `/promote-prod`. `app.js` carries `merge=ours`: assert its merge RESULT
equals staging's copy. A write-smoke is warranted (`app.js` and `mylist.html` are on the cancel path).
S2's SQL is applied to production first.

### S6 — only if S0 confirms the second cause

Add the ISBN key (`catalog.isbn` = invoice `upc` or `item_code`) to the arrival match everywhere it lives:
`hasShipmentEvidence()` (`admin.html:1095`), `isCoveredByShipment()` (`arrivals.html`),
`classifyArrivalOutcomes()` (both import scripts), `auto_fulfill_past_on_sale()` (Rick-run SQL) and
`check-dates.js`. Filed as F181 first.

## 5. Gates

| Gate | Session | Pass when |
|---|---|---|
| V0 | S0 | Query 1 shows the example's reservation at `unknown` (or explains otherwise); Query 2's count decides S6 |
| V1 | S1 | Unit suite green, the new keep tests red with the filter removed, the two scripts in parity |
| V2 | S1 | Staging: a seeded open, past-on-sale reservation marked `arrived` is reported as kept by `node import-staging.js --no-write`, and a direct PATCH with the new filter changes 0 rows; teardown re-read 0 |
| V3 | S1 | Production, Rick's next weekly run: prints `N admin mark(s) kept`; afterwards the example still reads `arrived` |
| V4 | S2 | Post-checks above, both environments |
| V5 | S3/S4 | Local harness on the deployed staging bytes: snooze hides and returns with its note; Show them / Wake now; dot not lit by a snoozed row; Mark Ordered opens for a row from another month; Can't get it: Cancel writes nothing, OK writes `not_available` on every collapsed reservation; customer sees the new line and can remove an open and a closed row; Turned up after all appears once and leaves after either action; a mark survives the S1 pre-flight run against staging; bagging list shows the reason; no horizontal scroll at 390 px. Each new check seen red first |
| V6 | S3/S4 | Specs that touch this path re-run (sweep with `grep -rn` in the Playwright folder; at least 06, 15, 21, 22, 25), then the full suite once on the deployed bytes |
| V7 | S5 | Served bytes on both production hostnames equal `origin/main`; write-smoke (reserve, cancel) observed |

## 6. The SOP (draft text for the help page and the panel lines)

*For Rick's review before S3. Plain wording; no store name.*

**One line under each section in the panel:**

- **Never arrived:** On sale, but no invoice shows it came. Check the shelf and the boxes, then mark what
  happened.
- **Turned up after all:** You marked it Didn't arrive, but a later invoice lists it. Check, then mark
  Received.
- **Backordered:** Its order cutoff has passed and it was never ordered. Order it late if the distributor
  allows, or mark Can't get it.
- **At risk:** Not ordered yet, and its order cutoff is before this cycle's Order Deadline. Order it, or
  mark Can't get it.

**Help page: "Order Follow-Up — how to handle these"**

> **What this list is for.** It shows reserved titles that need a decision, at the point where the
> decision still helps: before the order cutoff (At risk), after a missed cutoff (Backordered) and after
> the on-sale date (Never arrived). Handle a row and it leaves the list. Your choice stays put; the weekly
> import does not undo it.
>
> **At risk** — reserved, not ordered, and the order cutoff falls before this cycle's Order Deadline.
> - Going into this cycle's order? **Mark Ordered.** Customers see "Order placed".
> - The store won't stock it? **Can't get it.** Customers see "Not available — the store could not get
>   this title." and can remove it.
>
> **Backordered** — the order cutoff has passed and it was never ordered.
> - Ordered it late anyway? **Mark Ordered.**
> - Can't get it now? **Can't get it** (same customer message as above).
>
> **Never arrived** — on sale, and no invoice line shows it came.
> 1. Look on the shelf, in the boxes and on the counter. Invoices miss lines; a book handed over the
>    counter leaves no record.
> 2. Then mark one:
>    - **Received** — it is here. Customers see their reservation as normal.
>    - **Didn't arrive** — it never came. Customers see "No longer coming: the store already knows and
>      handles it with the supplier" and cannot remove it; it stays there for 180 days from on-sale.
>    - **Damaged** — it came damaged. Customers see the same, worded "Arrived damaged".
>    - **Rejected by supplier** — the distributor refused the order (shown only when an order is on
>      record). Customers see "Rejected by the supplier — this title will not arrive as scheduled." and
>      can remove it.
>
> **Turned up after all** — you marked it Didn't arrive, then a later invoice listed it. If it is here,
> mark **Received** so customers stop reading "No longer coming". If not, mark **Didn't arrive** again.
>
> **Still finding out?** Use **Snooze**: pick a date and add a note ("emailed PRH 11/9"). The row hides
> until that date, then comes back with your note if it is still open. Customers see nothing change.
> **Show them** lists snoozed rows; **Wake now** brings one back early.
>
> **Rows that clear themselves:** a title that gets ordered, shows up on an invoice, has a supplier
> rejection recorded, or is withdrawn by the distributor (it moves to the Withdrawn panel).
>
> **Mistakes.** Received, Didn't arrive and Damaged take effect at once and have no undo in the app. If you
> mark the wrong one, ask your PULLLIST operator to correct it. Can't get it and Rejected by supplier ask
> you to confirm first.
>
> **Customers are not emailed.** They see these messages on My List.

## 7. Not in scope, and known limits

- No email to customers (D3).
- No partial arrivals: a mark applies to every customer of the title (the known out-of-scope item).
- No undo for Received / Didn't arrive / Damaged (Rick, 2026-10-04).
- No change to when auto-close happens (C1) or to the Withdrawn panel.
- Marks made before S3 carry no stamp, so they never trigger "Turned up after all".
- **Interim until S1 lands:** a mark on a title less than 14 days past on-sale can be undone by the next
  import. Check the list after each import and re-mark if needed.

## 8. Open before building

- S0's two results (Rick).
- Rick's read of the § 6 wording.
