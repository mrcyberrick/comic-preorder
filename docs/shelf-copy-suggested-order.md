# Shelf-Copy Suggested Order — My List store-inventory automation

**Status:** **Complete and promoted to production.** Execution session ran
2026-07-17, same day as planning. Both Open defaults confirmed as-is with
Rick at execution pre-flight (plan-default tier thresholds; plan-proposed
preview columns). All V1–V5 gates green on staging (evidence below); seed
fixture torn down and independently re-verified via a live SELECT (0 rows).
Merged `feature/shelf-copy-suggested-order` → `staging` (ff-only, commit
`68e9314`); promoted `staging` → `main` via PR #88 (merged 2026-07-18,
commit `1c5dfc0`) at Rick's explicit request. Live at https://pulllist.app/.
**Post-promotion correction (2026-07-18):** after seeing real production
demand numbers (71 of 123 reserved titles triggering a suggestion), Rick
identified the standard-cover-only demand filter as a subscription-feature
convention that didn't belong in shelf-copy — removed on staging (commit
`21a1645`), promoted via PR #89 (merged 2026-07-18, commit `72cb25a`).
**Confirmed on production**: preview now shows 123 of 123 titles considered,
reconciling exactly with the live "Reserved Titles" report total (no titles
currently fulfilled, FOC-locked, or admin-owned this cycle to be excluded —
expect "considered" to drop below the report total later in the month as
that changes). See § 3 IN item 1 for the corrected demand-query description.
**Target:** staging first (standard flow); production promotion only on
explicit request after staging verification.
**Origin:** 2026-07-17 planning discussion — shelf-copy ("store inventory")
ordering is currently a per-title guess. Rick orders extras for walk-ins on
gut feel (2–3 for popular titles, 1 for lesser-known). Goal: a suggested
order derived from real reservation demand, reviewed and edited in the
existing My List UI before order-sheet export.

---

## 1. Goal

Automate the store's shelf-copy ordering as far as the data allows:

1. **Baseline (zero new code):** the BookStop admin account subscribes to
   always-stock series. The existing auto-reserve step of the monthly import
   materializes those as qty-1 reservations the moment the new month lands.
2. **Suggested order (the feature):** an admin-only button on My List
   computes a suggested shelf quantity per title from open customer demand
   and bulk-writes the results as BookStop's own reservations. Rick then
   adjusts quantities with the existing steppers and removes lines with the
   existing Remove button. The order-sheet exports need **zero changes** —
   BookStop's rows already flow into them.

### Design decisions — settled with Rick, 2026-07-17

| Decision | Resolution |
|---|---|
| Representation | Store inventory = reservations under the **BookStop admin account** (not a paper account). Its analytics activity is easy to filter; it can already hold series subscriptions. |
| UI home | **My List**, not admin.html — the admin tab is already heavy (perf concern noted separately); My List has the full review/edit UX built. |
| FOC lock | **Respected — no admin bypass.** Suggestions omit FOC-locked titles entirely. Intentional: avoids back-orders. |
| Suggestion inputs | **Open reservations only**: `fulfilled = false` (preorders has no other status column — "open" maps exactly to this flag) AND title not FOC-locked. Fulfilled rows are already in hand and must not be re-ordered. |
| Sell-through audit | **OUT** — deferred until future POS integration (Rick, 2026-07-17). v1 suggestions run on reservation demand alone. |
| Merge rule | **Never lower.** Re-runs and hand edits: the button only inserts new rows or raises existing quantities to the suggestion; it never reduces a quantity or deletes a row. Protects hand edits and the auto-reserved subscription baseline (see § 2). Preview shown before any write. |

## 2. Current state — verified 2026-07-17

Line refs verified this date; **re-verify byte-exact at execution** (File
Drift Prevention).

- **Order sheets already include admin-account rows.** admin.html:485–490
  loads all current-month preorders with no `is_admin`/`is_paper` filter;
  `makeOrderSheetRows()` (admin.html:835–869) consolidates one row per title
  and excludes only `fulfilled` rows. The Lunar export emits
  `code,qty` order-entry lines (admin.html:884–899). BookStop reservations
  flow into distributor orders today with no changes.
- **My List edit UX exists.** Qty steppers (mylist.html:885–887 desktop,
  936–939 mobile) call `Preorders.updateQuantity()` (handler near
  mylist.html:965); Remove button per row (mylist.html:897). Steppers and
  Remove are disabled when `isLocked = focLocked || isFulfilled`
  (mylist.html:858–860, 909–911).
- **FOC lock boundary.** `isFocLocked()` (app.js:1357) = `isFocPast()` —
  hard cutoff, true when `foc_date < today` (local date parts). FOC day
  itself is still open; rows lock the day after.
- **`preorders` schema** (technical-reference.md § 4.4): no status column.
  Columns: `quantity` (int, default 1), `fulfilled` (bool, default false),
  `fulfilled_at`, `tenant_id` (NOT NULL, no default — every INSERT passes it
  explicitly). UNIQUE `(user_id, catalog_id)` — natural upsert key for the
  bulk write.
- **Auto-reserve** (import script, new-month sequence): inserts preorders
  for subscribers' standard covers. Believed qty 1 — **pre-flight must
  confirm** in `import.js` (private scripts repo).
- **Standard-cover test** (used by subscribe eligibility — `isStandardCover()`
  at catalog.html:395–398, inline duplicate at catalog.html:1211; the § 2
  line ref in earlier drafts of this doc, catalog.html:1096–1097, was stale
  and pointed at unrelated modal code): `variant_type` null / `'Standard'` /
  `'Primary Title'`. **No longer used by this feature's demand query** as of
  2026-07-18 — see § 3 IN item 1.
- **RLS:** admins SELECT all tenant preorders ("admins manage" policy);
  any user inserts/updates own rows. The aggregation query and the bulk
  upsert both run as the logged-in BookStop admin — no policy changes.
- **My List is current-catalog-month scoped** — same scope as the order
  sheets. No month mismatch.

## 3. Scope

### IN

1. **Suggestion computation** (client-side, My List page code):
   - Demand query: open preorders joined to catalog for the current
     catalog month — `fulfilled = false`, title not FOC-locked (client-side
     `isFocLocked` on `foc_date`), **excluding rows belonging to admin
     accounts** (`user_profiles.is_admin = true`). **Standard-cover-only
     was dropped 2026-07-18** (Rick, after seeing production numbers): it
     was borrowed from the Subscribe button's convention without
     independent justification for shelf-copy — that convention is a
     subscription-feature limitation, not a shelf-copy rule. Variant-cover
     reservations now count as demand, and variant titles are eligible for
     suggestions on the same tier rule as standard covers.
   - The admin exclusion is what prevents the self-count ratchet: without
     it, re-running the button counts the store's own shelf copies as
     demand and inflates forever. Filtering on `is_admin` (not a hardcoded
     account id) makes the feature work unchanged for tenant 2.
   - Note: auto-reserved subscriber rows are ordinary open preorders and
     correctly count as customer demand.
   - Tier rule (defaults below) maps total open customer qty per title →
     suggested shelf qty.
2. **Admin-only "Suggest shelf order" button** on My List — rendered only
   when the logged-in user's profile has `is_admin = true`. Hidden for all
   customers; no impersonation-context interaction (it operates on the
   admin's own list).
3. **Preview modal** before any write: one row per affected title —
   title, open customer qty, current store qty, suggested qty, action
   (insert / raise / no change). Apply / Cancel. Apply performs the writes;
   Cancel writes nothing.
4. **Bulk write:** upsert on `(user_id, catalog_id)`, passing `tenant_id`
   explicitly on every row (post-3.3: no column defaults). Never-lower rule
   enforced in the code that builds the upsert payload (rows where current ≥
   suggested are dropped from the payload, shown as "no change" in preview).
5. **Runbook update:** `monthly-catalog-refresh.md` Step 2 gains one line —
   populate/review the shelf order on My List (BookStop) **before**
   exporting the order sheets.
6. **Unit coverage** for the two pure functions (tier rule, merge/payload
   builder) in the scripts repo's committed suite or a page-level extraction
   — decided at execution; the functions must be pure and testable either way.

### Open defaults (confirm with Rick at execution pre-flight)

- **Tier thresholds** (v1 defaults, constants in code, marked adjustable):
  open customer qty 1–2 → suggest 1 · 3–4 → suggest 2 · 5+ → suggest 3 ·
  0 → no suggestion (baseline comes from subscriptions only). Mirrors
  Rick's stated practice (1 for lesser-known, 2–3 for popular).
- **Preview modal columns/copy** — final layout at execution.

### OUT — stop and ask

- **Sell-through / leftover audit** — deferred until POS integration
  (Rick, 2026-07-17). Do not build any sell-through capture.
- **FOC-lock admin bypass** — explicitly rejected (Rick, 2026-07-17). Do
  not loosen the lock for anyone.
- **Admin report filtering** (Top Series, reservation stats now including
  store copies): each preorders-based report needs a one-time
  include-or-filter decision — separate session, not v1.
- **admin.html performance investigation** — noted by Rick 2026-07-17 as
  getting bogged down; separate finding/session, not bundled here.
- **Per-subscription quantity** for auto-reserve (baseline > 1) — future
  import-script extension.
- **Any admin.html change, any schema change, any Edge Function change** —
  none are needed; if execution finds otherwise, halt and report.

## 4. Runbook (high level — execution session expands to byte-exact steps)

### Step 0 — Pre-flight
- Re-verify every line ref in § 2 against disk (File Drift Prevention).
- Confirm auto-reserve inserts `quantity: 1` in `import.js` (scripts repo).
- Confirm the BookStop admin account exists with `is_admin = true` on
  staging (and identify the staging test-admin equivalent for gates).
- Confirm tier thresholds and preview layout with Rick (§ 3 Open defaults).

### Step 1 — Pure helpers
Tier rule + upsert-payload builder (never-lower merge) as pure, exported
or extractable functions. Unit tests alongside.

### Step 2 — Demand query + button + preview modal
My List page code; button admin-gated; preview renders computed actions;
Cancel is a no-op.

### Step 3 — Apply path
Bulk upsert on `(user_id, catalog_id)` with explicit `tenant_id`; success
re-renders the list (existing render path); failure surfaces a toast and
writes nothing partial that the preview didn't show.

### Step 4 — Runbook line
`monthly-catalog-refresh.md` Step 2 addition (doc commit, may ride the
feature branch since it documents the feature's operational step).

### Step 5 — Verification gates on staging, then wrap-up
Run V1–V5 (§ 5). Standard `/deploy-staging` flow; production promotion only
on explicit request.

## 5. Verification gates

- **V1 — Suggestion correctness:** seeded staging state (customer
  reservations at known quantities across the tier boundaries, one
  FOC-locked title, one fulfilled row, one variant) produces exactly the
  expected preview: locked title absent, fulfilled row not counted, variant
  absent, tiers correct.
- **V2 — Self-exclusion:** with existing BookStop rows present, re-running
  the button shows those rows' quantities unchanged in the preview and the
  demand counts unchanged (no self-count ratchet).
- **V3 — Never-lower:** hand-raise one store quantity above suggestion,
  hand-add one store row for a zero-demand title; re-run + Apply changes
  neither.
- **V4 — Order-sheet integration:** after Apply, the admin Lunar/PRH
  order-sheet exports include the store rows at the applied quantities,
  consolidated with customer demand.
- **V5 — Access + isolation:** button absent for a non-admin customer;
  feature operates only on the caller's tenant (run once as tenant-2 admin
  on staging if a tenant-2 staging admin exists — otherwise assert the
  demand query carries no cross-tenant rows by RLS construction and record
  that in the gate log).

## 5a. Verification gate evidence — 2026-07-17 (staging)

Seed: 7 synthetic `ZZSHELF-*` catalog rows (founding tenant, `catalog_month =
'2026-07'`) + preorders spanning every case, per prepared seed SQL. Rick ran
the seed, worked the gates as the staging Test Admin, then ran teardown.

- **V1 — Pass.** Preview showed exactly the 4 expected rows — `ZZSHELF-TIER1`
  (open 2 → suggest 1, Insert), `ZZSHELF-TIER2` (open 4 → suggest 2, Insert —
  confirms cross-row summing across 2 customers), `ZZSHELF-TIER3` (open 5 →
  suggest 3, Insert), `ZZSHELF-FULFILL` (open 1 → suggest 1, Insert — confirms
  the fulfilled row is excluded from the sum). `ZZSHELF-FOCLOCK` and
  `ZZSHELF-VARIANT` were absent from the preview, as required. Screenshot
  evidence captured during the session.
- **V2 — Pass.** Re-running the button after Apply showed all 4 titles as "No
  change" at the same open-qty counts — no self-count ratchet from BookStop's
  own new rows.
- **V3 — Pass.** Hand-raised `ZZSHELF-TIER1` above its suggestion and
  hand-reserved `ZZSHELF-ZERODEMAND` (a title with zero customer demand);
  re-run + Apply changed neither.
- **V4 — Pass.** Order-sheet export included the `ZZSHELF-*` titles at
  BookStop's applied quantities, consolidated with customer demand.
- **V5 — Pass.** Button absent for a non-admin customer. No tenant-2 staging
  admin exists (checked live via service-role read, 2026-07-17), so
  cross-tenant isolation was asserted by RLS construction per the plan's
  accepted fallback: the demand query carries no explicit tenant filter and
  relies on the same admin RLS policy (`admins manage tenant preorders`)
  already proven by admin.html's identically-shaped preorders query.
- **Teardown — verified.** Rick ran the teardown SQL; independently
  re-confirmed via a live read-only SELECT (service-role) —
  `catalog` and `preorders` both return 0 rows for `item_code LIKE
  'ZZSHELF-%'`.

## 6. Completion criteria

- [x] All § 5 gates green on staging, evidence logged in this doc
- [x] Unit tests for tier rule + payload builder committed and passing (9
      tests, `test/shelf-order.test.mjs`)
- [x] `monthly-catalog-refresh.md` Step 2 updated
- [x] No admin.html, schema, or Edge Function diffs in the feature branch
      (diff touched only `app.js`, `mylist.html`, `shelf-order.js`,
      `test/shelf-order.test.mjs`, `docs/monthly-catalog-refresh.md`)
- [x] Playwright smoke suite green (`run-smoke.ps1`) before staging push (30
      unit + 32 Playwright specs, all passing)
- [x] This doc's Status updated; CLAUDE.md untouched — no findings filed this
      session

## 7. Rollback

Feature is additive client-side UI on mylist.html plus pure helpers —
rollback is a single revert commit on staging. Data written by Apply is
ordinary BookStop reservations, removable through the existing My List
Remove button (for FOC-open rows) or left to flow into the order as a
manual decision; no schema or RLS changes exist to unwind.

## References

- `docs/monthly-catalog-refresh.md` — Step 2 (order-sheet export ritual)
- `docs/technical-reference.md` § 4.4 (`preorders`), § 4.5
  (`reservation_history` — future signal, unused in v1)
- `docs/subscription-promotion.md` — house style + standard-cover
  eligibility refs
- admin.html:485–490, 835–869 (order-sheet path) · mylist.html:858–860,
  885–897 (edit UX + lock) · app.js:1357 (`isFocLocked`)
