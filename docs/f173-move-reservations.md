# F173 — Move reservations to another listing (admin control for a distributor product-code change)

**STATUS:** IN PROGRESS — BUILT on a feature branch 2026-10-11; staging SQL `PENDING` (Rick runs it), staging code not yet deployed or tested; production not started. Findings: F173 (owner, `docs/technical-reference.md` § 13). No new finding ID consumed.

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

*(Not run yet.)*

## 6. Sequencing and promotion

Staging first. **The SQL reaches production BEFORE the client code** (F105): the page calls the function, and a missing function fails only when the button is pressed, which is the worst time to find out. Because the file reads `prod=PENDING`, `/promote-prod` step 0 will refuse every promotion until Rick applies it on production; that is the gate working as designed, and the function is inert until the page calls it, so applying it early costs nothing. Production promotion only on Rick's explicit `/promote-prod`.

## 7. Follow-up wired to this work

`docs/import-sop.md` Run D gains a D2 route "Move the reservation" (store admin, screens only) once this is verified on staging; until then Run D describes the Pattern 1 / Pattern 2 workarounds and D4 (operator SQL). Not edited yet.
