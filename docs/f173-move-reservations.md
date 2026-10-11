# F173 — Move reservations to another listing (admin control for a distributor product-code change)

**STATUS:** BUILT AND VERIFIED ON STAGING 2026-10-11 (staging SQL APPLIED, harness 50/50 on the deployed bytes; see § 5); NOT PROMOTED (the client is staging-only); the SQL is also applied on production as of 2026-10-11, confirmed by an anonymous probe that the function exists and refuses anon, the admin path there untested. Findings: F173 (owner, `docs/technical-reference.md` § 13). No new finding ID consumed.

Owner doc for the build of the manual control Rick asked for on 2026-10-11 ("A manual way to correct it would also be good since these are low volume issues", then "lets build it"). The problem, the measurements and the options considered are in § 13 F173; this file records what was built and the decisions taken at build time.

---

## 1. Decisions (Rick, 2026-10-11)

| # | Question | Decision |
|---|---|---|
| 1 | The recheck (`check-dates.js`) is run by the platform operator against one tenant (`IMPORT_TENANT_ID_PROD`), so a second tenant's listing dates are not corrected by their own admin. | Understood; **future changes will address this, acceptable for now.** |
| 2 | Should the move dialog also set the target's FOC and in-store dates? | **No date field.** "Hold until recheck as this is cleaner." The Friday recheck corrects the target once it holds a reservation. *(My reading of his answer, stated to him; not a separate instruction.)* |
| 3 | PRH catalogs older than about three months are frozen, so the recheck cannot correct them. | Accepted. The dialog says so for PRH. |

## 2. What was built

**One database function, one dialog.** No other table, policy, trigger or page changes.

### 2.1 `admin_move_reservations(p_from_catalog_id uuid, p_to_catalog_id uuid, p_move_order boolean DEFAULT false) -> jsonb`

File: `docs/sql/2026-10-11-f173-admin-move-reservations.sql` (STATUS `staging=PENDING | prod=PENDING`). `SECURITY DEFINER`, `search_path` pinned, `GRANT` to `authenticated` only, `REVOKE` from `PUBLIC` and `anon` (F124).

- **Who:** refuses unless `auth.uid()` is set, `current_tenant_id()` resolves and `current_user_is_admin()` is true. The tenant is derived inside the function, never passed in.
- **Both listings must belong to the caller's tenant** (F164: the `preorders` policies check only the row's own `tenant_id`, never the catalog row's, so a forged id would otherwise be accepted), be different, and be the **same distributor**. The target must not be withdrawn.
- **Moves** every **unfulfilled** reservation on the source (locked `FOR UPDATE`). Fulfilled ones are history and stay.
- **Clears** `arrival_outcome` and `unavailable_dismissed_at` on the moved rows: both are statements about the old listing.
- **Audit:** appends `Moved from <old code> (<month>) to <new code> (<month>) on <date>` to `preorders.notes`, a column no screen reads or writes (confirmed by grep of every `.html` and `.js`: the only mention is a `select` in `app.js`).
- **Refuses** if a moved customer already holds the target (it says how many; `UNIQUE (user_id, catalog_id)` would reject it anyway) or if nothing is open to move. Any failure rolls the whole call back.
- **Optional order record** (`p_move_order`): if the old order code nets above zero in `order_submissions`, adds `-N` under the old code and `+N` under the new, both `order_type = 'adjustment'`, `N = least(old net, quantity moved)`. Append-only; nothing is edited. Skipped when the two codes are equal (the record is already shared) or the old code nets to zero or less. The order code reproduces `app.js` `exportCode()` exactly (PRH `isbn || item_code || upc`, otherwise `item_code || upc || isbn`, JS `||` semantics).
- `submitted_on` is the database's `current_date` (UTC), not the browser's local date. Harmless; noted because the Mark Ordered dialog uses local time.

### 2.2 The dialog (`admin.html`)

- **Entry:** a small **Move reservations…** button in the Status column of Ordering → By Distributor, under *Mark Ordered* / *Rejected by supplier*, shown whenever at least one reservation on that listing is still open.
- **Works from a cross-month search result.** The source is looked up in `allPreordersAllMonths`, not the selected cycle. (`openMarkOrderedModal` looks only in the selected cycle, so Mark Ordered silently does nothing from a cross-month result: pre-existing, **not fixed here**, raised with Rick.)
- **Find the new listing:** a search box (title, product code, or UPC; at least three characters) that calls `Catalog.fetch({ search, distributor, pageSize: 30 })` with **no month**, so it searches every catalog month, this distributor only. Commas, brackets and `%` are stripped first because they are filter syntax inside that function's `.or()` list.
- **Choosing a listing** shows its title, code, month, FOC and in-store dates and any existing reservations, and **blocks the move in words** when the target is withdrawn or when named customers already hold it. It always states that the target's dates are not changed and the recheck corrects them; for PRH it adds the frozen-catalog caveat.
- **Order record checkbox**, shown only when the old code nets above zero and the codes differ, **unticked by default**, worded as "tick only if you have confirmed in the portal that the order carried over". It asserts something about the distributor's side that only the admin can know, and a wrong "yes" leaves the store believing a copy is ordered that is not.
- **On success** the page reloads its data, puts the admin back on the cycle they were viewing (when that month still has reservations), and toasts what moved. On failure the function's own sentence is shown and nothing was saved.

### 2.3 UPC is a suggestion, not the key (Rick's question, 2026-10-11)

Rick asked whether the UPC is a better identifier than Lunar's item code. **Measured read-only on production** (founding tenant, 9,641 catalog rows, script `upc-vs-code.js` in the session scratchpad, GET only):

- **Coverage.** Lunar: 5,617 rows, every one has an item code; 4,122 (73.4%) have a UPC (3,991 are the 17-digit form with the 5-digit issue and cover add-on), the other 1,495 carry an ISBN instead, so every Lunar row has a UPC or an ISBN. PRH: 4,024 rows, UPC on 2,536 (63.0%), ISBN on the rest, 0 duplicates.
- **Direction of the mapping.** No item code carries more than one UPC (code determines UPC), but the reverse fails: **12 Lunar UPCs sit under two codes.**
- **Six of the 12 are the same title under two codes in different catalog months, i.e. recode-shaped:** Hyde Street #14 CVR A and CVR B, W0RLDTR33 #22 CVR A, B and C, Big Bundle of Dinosaurs. **Only Hyde Street CVR A was confirmed as a genuine recode** (it is the one repaired by hand); the other five match on UPC, title and month pattern but were not checked on Lunar's site, so "recode" is the likely reading, not a verified one.
- **The other six are different products in the SAME month**: DC CONNECT #77, #78 and #79 (a PAID bundle at $6.25 and a FREE one at $0 under one UPC), two Batman art boxes (an 85-bundle pallet at $3,431.90 and a bundle of 5 at $42.50), and a resin statue listed under two prefixes. **Of the four shared-UPC pairs that hold reservations, three are these same-month distinct products and one is the Hyde Street recode.** A UPC-only key would merge a free bundle with a paid one.
- **The weekly invoice already matches by UPC** (1,544 of 1,545 shipment rows carry one, 676 an item code), which is why shipment matching does not break on a recode; the order record and Lunar's own order form use the item code.

**Built:** when the dialog opens it suggests listings from the same distributor with the same UPC (the ISBN when there is no UPC) in a **different** month, not withdrawn. Same-month matches are never suggested. It is a suggestion; the admin still picks and reads the dates. The rule sorts all 12 measured cases the way the titles and prices suggest (6 recode-shaped pairs suggested, 6 different-product pairs excluded), but 12 is a small sample and only one of the six was confirmed as a recode.

**Not built, and a decision for Rick:** keying reservations on UPC so a recode needs no move at all. It would touch `preorders`, My List, This Week, auto-fulfil, the order record and both import scripts, and the first two measurements above show UPC alone cannot be the key. A smaller step in the same direction: have the weekly recheck notice "reserved listing whose UPC now appears under a new code in a later month" and report it (or, with a confirm, perform this same move). That is F173 fix direction (a), not built.

## 3. What this does NOT do

- It does **not** edit the target's dates (decision 2).
- It does **not** find the new code for you. Nothing maps old to new; the admin supplies it by searching. If the new code has not been imported into any catalog month, it cannot be chosen (the dialog says so).
- It does **not** move fulfilled reservations, and it does **not** move reservations between distributors.
- It does **not** tell the customer. The customer simply sees the reservation on the new listing, with whatever dates it carries until the recheck.

## 4. Verification

Written as the plan; results go in § 5 when run.

- **V1 (SQL):** the pre-check, grants and definition verdicts in the SQL file all read OK on staging.
- **V2 (function, as a real signed-in admin, local harness `playwright/f173-move-verify.mjs`, gitignored):** seeded `ZZTEST173-` listings and throwaway users on staging; the happy path; every refusal in § 2.1 (non-admin, anon, same listing, other tenant's listing, different distributor, withdrawn target, nothing open, customer already on target); fulfilled rows stay; `arrival_outcome` cleared; `notes` appended; the order carry-over (+/-, capped, skipped for equal codes and for net zero); atomicity (a failing call changes nothing); teardown re-read to zero.
- **V3 (dialog, in a browser):** button present only with an open reservation; search across months; conflict and withdrawn blocking; checkbox visibility rules; success path updates the table; failure shows the message; works from a cross-month search result.
- **Negative controls:** each new assertion seen red against a deliberately broken function or page before it counts.
- **V4:** full Playwright suite on the deployed staging bytes; unit suite unaffected (no import-script code).

## 5. Results

**Harness `playwright/f173-move-verify.mjs` (local-only), 2026-10-11, against the deployed staging bytes and the applied staging function: 50 of 50 checks passed, teardown re-read 0 listings / 0 reservations / 0 ledger rows / 0 profiles / 0 auth users.** (An earlier run died before any check on a harness fault, PostgREST's "All object keys must match" on a bulk insert; fixed in the harness, no product change.)

- **Function, as real signed-in users:** R1 anon refused (401, permission denied), R2 a non-admin refused (403, "Only a signed-in admin"), R3 same listing, R4a/R4b another tenant's listing as target and as source ("not found in this store"), R5 different distributor, R6 withdrawn target, R7 a customer already on the target (whole move refused), R8 every refusal left the data identical.
- **Effects:** H0 to H9 (two reservations moved, the fulfilled one stayed, `not_arrived` and the admin-clear flag cleared, an audit line appended to `notes`, quantities unchanged, the order record untouched without the box, a second call finds nothing open); O1 to O6 (the order carry-over capped at the quantity moved: net 3, moved 2, so -2 and +2; the same code in two months leaves the record alone; an old code netting to zero carries nothing).
- **Dialog, in a real browser:** the button appears on a listing found by a cross-month search and not on one with only a fulfilled reservation; the dialog names the customer and quantity; the UPC suggestion appears before anything is typed and a same-UPC listing in the same month is not suggested; a too-short search, a conflicting customer and a withdrawn target are each blocked in words with Move disabled; the order-record box is offered and unticked; a successful Move updates the database, the order record and the table and shows a toast; a server refusal is shown in words with the dialog still usable; no uncaught page errors.
- **How "negative control" is meant here, stated plainly:** each effect assertion is evaluated on a snapshot taken BEFORE the call (it must be false) and on one taken AFTER (it must be true), and the harness reports a check as vacuous if it was already true before. **No deliberate break of the function or the page was made**, so these are before/after flips, not red runs against broken code.
- **Observed, not part of this work:** clicking **Mark Ordered** on a row found by the cross-month search does not open the dialog (`openMarkOrderedModal` looks only in the selected cycle). Pre-existing; the SOP now says to reach the row through the month selector.
- **Not verified:** the full Playwright suite on these bytes (see below), WebKit or a real phone, the dialog on a phone layout, a PRH listing end to end, the ISBN suggestion path, two admins moving at once, the function on production, and a real recode by a real store admin.


## 6. Sequencing and promotion

Staging first. **The SQL reaches production BEFORE the client code** (F105): the page calls the function, and a missing function fails only when the button is pressed, which is the worst time to find out. While the file read `prod=PENDING`, `/promote-prod` step 0 refused every promotion; that was the gate working as designed. **It now reads `prod=APPLIED 2026-10-11`** (Rick ran it; confirmed by an anonymous probe: the function exists on production and refuses anon with 42501). The function is inert until the page calls it, so applying it first cost nothing. Production promotion only on Rick's explicit `/promote-prod`.

## 7. Follow-up wired to this work

`docs/import-sop.md` Run D gains a D2 route "Move the reservation" (store admin, screens only) once this is verified on staging; until then Run D describes the Pattern 1 / Pattern 2 workarounds and D4 (operator SQL). Not edited yet.
