# Admin Settings — catalog visibility filters

**STATUS:** IN PROGRESS — S0 MEASURED BOTH ENVIRONMENTS, S1 WRITTEN NOT APPLIED · staging=— · prod=— · PR=— · findings: **F160 (filed + confirmed 2026-09-23, fixed by S4(a))**
**Q1–Q5 ANSWERED 2026-09-23 (Rick)** — see § 7. **The shaping decision is Q4: DELETE the ≥7 publisher bar** (§ 2.1), which collapsed a three-way fork, deleted S3, made F160's fix a deletion, and made the default state "store nothing". **Q5: store publisher EXCLUSIONS, never inclusions** (§ 3.2.1). S1 SQL: `docs/sql/2026-09-23-publisher-reserve-counts-rpc.sql`, STATUS `staging=PENDING | prod=PENDING`. **No code written, nothing applied to either database.**

**Type:** Feature build, Rick's request 2026-09-23. **One new page, one new RPC, one new
`app_settings` key. No schema change to any existing table, no RLS change, no Edge Function.**

**Mockup:** https://claude.ai/artifact/2jeBZrDNnjkhbHCqnEXHNs — four artboards (desktop, mobile,
nav rework, placeholder shell). The desktop board's filter logic is live and its counts recompute,
so it is a behavioural sketch, not only a visual one.

---

## 0. What this is, in one paragraph

An admin settings page that controls which catalog titles are visible, by publisher, cover type,
allocation ratio, FOC state and price. It governs **two** surfaces from one rule: the customer
Monthly Catalog (`catalog.html`) and the Print Catalog on Ordering ▸ Paper Orders.

**The reframe that matters: this is not a new filter layer.** Both filters already exist, hardcoded,
on one of the two surfaces. `MIN_RESERVED = 7` (`admin.html:5249`) drops any publisher with fewer
than 7 all-time reservations from the printed sheet, and `admin.html:5330` drops anything whose FOC
is not in a later month. `catalog.html` applies neither. So **the paper catalog and the web catalog
show different title sets today**, and nothing in the product says so. This work makes the rule
explicit, editable, and shared.

---

## 1. What is already true — measured 2026-09-23, not assumed

### 1.1 The two surfaces, and where they diverge

All figures below are **production, catalog month 2026-09, measured 2026-09-23** (S0 Q1/Q6).

| | Monthly Catalog (`catalog.html`) | Print Catalog (Paper Orders) |
|---|---|---|
| Publisher filter | none — all **72** | **≥ 7 all-time reservations** → 14 of 72 |
| Past-FOC filter | none | hides FOC ≤ current catalog month → −109 of the 14's rows |
| Cover / ratio / price filter | none | none |
| **Titles shown** | **2,302** | **1,507** (33 pages @ 46 rows) |

*(This table read "all 78 / 14 of 78 / 2,399 / 1,534 / 34 pages" from the 2026-08-24 print record
until production was measured. **72 publishers, not 78** — that figure is per-environment and
per-month and must not be treated as a constant. The 14 publishers matched exactly.)*

Per-customer filters on `catalog.html` (distributor, publisher, reserved, variants, plus the
📌 Pin) are **a different thing** and are untouched by this work — they are one customer's view
preference in `localStorage`. This page sets the tenant-wide floor those filters operate within.

### 1.2 Storage and RLS — the feature needs no migration

- `app_settings` is `(tenant_id, key)` → `value text`, PK on `(tenant_id, key)`, with
  `updated_at` / `updated_by` already present (so "last changed by" is free).
- RLS: `users read tenant app_settings` is **SELECT, `TO authenticated`**, scoped
  `tenant_id = current_tenant_id()`. **Every signed-in customer can already read it** — no new RPC
  and no policy change is needed for `catalog.html` to read the config.
- Writes are admin-only (`admins insert/update/delete tenant app_settings`). Correct as-is.
- `Settings.get()` / `Settings.set()` (`app.js:914-934`) are the existing accessors. A JSON blob
  under one new key (`catalog_filters`) fits without touching either.

### 1.3 The columns each filter reads

| Filter | Column | Notes |
|---|---|---|
| Publisher | `catalog.publisher` | text, nullable; `idx_catalog_publisher` exists |
| Standard cover | `catalog.variant_type` | NULL / `'Standard'` (Lunar) / `'Primary Title'` (PRH) |
| Allocation ratio | `catalog.order_requirement` | PRH's `OrderRequirement`; **Lunar's ratio is in `variant_type` itself** and is derived into this column at import by `parseLunarVariantRestriction()` |
| Past FOC | `catalog.foc_date` | date, nullable. **NULL has no cutoff — keep it** |
| Promotional | `catalog.price_usd` | numeric, nullable. **⚠️ MEASURED 2026-09-23: `= 0` is FOUR titles and `IS NULL` is ZERO** — see § 3.7 |

`current_tenant_id()` is `STABLE`, so RLS is evaluated once per query, not per row.

### 1.4 The standard-cover test is duplicated in seven places

`app.js:778-780`, `catalog.html:470`, `catalog.html:1342`, `admin.html:5408`, `admin.html:5815`,
`subscriptions.html:472`, `subscriptions.html:849`. This work must **not** add an eighth. Where a
standard-cover test is needed, reuse or extract — the F143/F156 single-writer reasoning applies to
predicates too.

### 1.5 The single chokepoint on the print side

`fetchAllCatalogForDistributor()` (`admin.html:5286`) is called exactly twice, both from the
combined print (`:5685`, `:5687`). Both filters live in its `return items.filter(...)` at
`:5329-5330`. **That is the only place the print side needs to change.**

---

## 2. ⚠️ BLOCKING — a brand-new tenant's Print Catalog is empty, and that is live today

`getReservedPublishers()` (`admin.html:5251`) builds its set from `reservation_history` +
`preorders`, then keeps only publishers with `>= MIN_RESERVED`. **A tenant with no reservation
history produces an empty set**, and `:5329` then filters out every row. There is no fallback in
that path.

This is **not** a consequence of the new feature. It is a latent defect in shipped code, invisible
because only the founding tenants have reserve history. The gradient, all measured 2026-09-23 except
the last historical row:

| tenant | publishers passing | rows | pages |
|---|---|---|---|
| production `rjbookstop` | 14 of 72 | 1,507 | 33 |
| staging `raysandjudys` | 5 of 72 | 688 | 15 |
| production `comicstore` (1 reservation) | **0 of 1** | **0** | **0** |
| staging `demoshop` (no history, 2,288 rows) | **0 of 72** | **0** | **0** |

*(The 2026-08-24 real print recorded 14 → 1,534 → 34 on production and 4 → 638 → 15 on staging, on
the previous catalog month. Both validated the prediction model before its zeroes were trusted.)*

**Consequences for this plan — ✅ ALL RESOLVED 2026-09-23 by deleting the bar (§ 2.1):**

1. ~~The default for a tenant with no history must be show-all, not "reserved ≥ 7".~~ **Moot.** There
   is no bar, so there is no default to get wrong.
2. Absence of a config row means **show all**, both surfaces (§ 3.4). Unchanged, and now simpler.
3. ~~The founding tenant must be seeded explicitly (S3) so turning this on changes nothing.~~
   **S3 deleted** — nothing to preserve, nothing to seed.

**F160's fix is the deletion itself**, in § 4 S4(a) — not the fail-open floor originally proposed
below. The floor would have patched a heuristic that is being removed.

**Filed as F160 and CONFIRMED LIVE ON STAGING, both 2026-09-23** — see `docs/technical-reference.md`
§ 13 F160. S0 Q1, run by Rick: **`demoshop` holds 2,288 catalog rows across 72 publishers, 0 with
any reserve history, 0 passing the bar, 0 predicted print rows.** The model was validated first
(staging founding returned 15 pages against the real 2026-08-24 print's 15), so that zero is
trustworthy. **The affected tenant is the demo one** — the very tenant F72 S1a built to show
prospects. **Production confirmed the same day** — `comicstore`: 2 catalog rows, 1 reservation,
0 publishers passing, 0 print rows. And the finding's **definition needed widening**: the trigger is
*no publisher clears the bar*, not *zero reserve history*, so any tenant whose reservations are
spread thinly is exposed (§ 13 F160).

**Staging's exclusion is worse than production's: 67 of 72 publishers (93%) hidden, against 58 of 72
(81%)** — with only 17 of 72 holding any reserve history and 12 sitting between 1 and 6
reservations. That near-miss band is the population the settings page exists to make visible.

**F160's fix is S4(a)'s deletion of the bar**, not a standalone floor. *(This paragraph previously
read "F160's own fix is a one-line fail-open floor that can land independently of this plan — worth
doing if this plan does not ship soon." Superseded 2026-09-23: with the bar deleted there is nothing
to floor, so the fix is no longer separable from S4.)* If F160 needs closing ahead of the rest,
deleting the bar **is** the standalone change — it touches only
`fetchAllCatalogForDistributor()` — at the cost of a 45-page sheet until the settings page ships.

### 2.1 ⚠️ SECOND BLOCKING RESULT — unification is not free, and the publisher bar is the expensive half

Measured on staging 2026-09-23 (S0 Q1/Q6). **S3 as originally written — "seed the founding tenants
reproducing today's effective print behaviour" — would silently cut the customer catalog by 70%.**

| | customer catalog today | under today's print config | change |
|---|---|---|---|
| staging `raysandjudys` | **2,302** titles, 72 publishers | **688** titles, 5 publishers | **−70%** |
| production `rjbookstop` | **2,302** titles, 72 publishers | **1,507** titles, 14 publishers | **−34.5%** |

*(Production measured 2026-09-23, replacing this row's earlier ~2,399 / ~1,534 / −36% estimate. Both
environments hold 2,302 rows for 2026-09 across the same 72 publishers — the same import.)*

**On production the split is 686 rows to the publisher bar and 109 to the FOC rule** (Q6). The
publisher bar is the expensive half on both environments.

**⚠️ THE STRONGEST ARGUMENT FOR THIS FEATURE IS NOW MEASURED, ON REAL RESERVE HISTORY.** Staging's
counts were test data; production's are three years of a real shop. What the bar hides there:

| Publisher | Reserved | Titles this month | |
|---|---|---|---|
| Seven Seas Entertainment | 0 | **81** | hidden |
| Oni Press | 0 | **67** | hidden |
| Yen Press | 0 | **52** | hidden |
| BAD IDEA | 0 | 38 | hidden |
| Viz Media | **2** | 37 | hidden |
| Vault Comics | 0 | 29 | hidden |
| Prana Publishers | 0 | 29 | hidden |
| Ignition Press | 0 | 28 | hidden |
| Kodansha Comics | 0 | 24 | hidden |
| Papercutz | **1** | 22 | hidden |
| Random House Worlds | 0 | 22 | hidden |
| — | — | — | |
| Abrams | **9** | 27 | **shown** |

**Abrams clears the bar on 9 reservations and 27 titles while Oni Press, with 67 titles, is invisible
because it has 0.** That is the self-reinforcement loop the 2026-08-24 session described and declined
to file, now with real numbers attached: a publisher nobody can see earns no reservations, so it
stays invisible. Every manga and indie publisher CLAUDE.md named — Oni, Viz, Yen Press, Seven Seas,
Vault — is confirmed excluded on production.

**The FOC rule I flagged under Q2 is the small half.** Of staging's 1,614-row reduction, the
past-FOC rule accounts for **54** rows (Q6 `newly_hidden_from_customers`, of which 7 are held by the
reservation exemption) and the **publisher bar accounts for ~1,560**. I had the proportions
backwards when I raised Q2 as the decision to think about.

**✅ RESOLVED 2026-09-23 (Rick): DELETE THE ≥7 BAR. The problem dissolves rather than being
traded off.**

This section originally posed a three-way fork — print's behaviour wins (customers lose 34.5%),
catalog's wins (sheet grows), or per-surface lists — and recommended a per-surface default. **Rick's
question cut through it: the bar only exists on the print, so deleting it changes nothing for
customers at all.**

| | effect of deleting the bar |
|---|---|
| Customer catalog | **no change** — it never had the bar; still 2,302 |
| Print catalog | **33 → 45 pages** (2,068 FOC-eligible rows ÷ 46) |

That is the entire cost: **+12 pages, 1.36×, on the print only.** *(An earlier draft of this section
said "~50 staging / ~54 production" — sloppy arithmetic, corrected: both environments converge on 45
because both hold the same 2,302-row catalog.)*

**Consequences, all simplifications:**

- **The default state stores nothing at all**, so there is nothing to go stale and nothing to break.
  Every customer sees every publisher; any filtering is something the admin added deliberately.
- **§ 3.4's per-surface default table is gone** — replaced by plain show-everything.
- **S3 disappears.** Its whole purpose was seeding a config to stop S4 changing behaviour; with no
  bar there is no behaviour to preserve.
- **F160 is resolved by deletion, not by the fail-open floor** § 2 proposed. No bar means an empty
  reserve history cannot produce an empty sheet. The floor was a patch on a heuristic that is going.
- **The per-surface idea is withdrawn.** The asymmetry is real — hiding a publisher from the *web*
  costs a sale, hiding it from *paper* costs only discovery — but one list plus the page-count
  readout gets the same outcome for half the UI. Revisit only if 45 pages proves too long and
  trimming publishers turns out to hurt the web side.

**The three queries reconcile exactly, which is why these numbers can be trusted.** Q2's five
passing publishers hold `314 + 288 + 102 + 27 + 11 = 742` current-month titles; Q6 says 54 of those
fail the FOC rule; `742 − 54 = 688`, which is Q1's `predicted_print_rows` to the row. Three
independently-written queries agree, so the model is not merely self-consistent — it is
cross-checked.

**⚠️ But staging's reserve counts are TEST DATA** (24 archived + 64 live, per CLAUDE.md's own note),
so the *ranking* is meaningless here — "Image Comics has 0 reservations" is a staging artifact, not a
fact about comics. Production Q2 is the only source for real popularity. What *is*
environment-independent is the shape: **Abrams clears the bar on 27 titles while Image Comics, with
246, does not.**

**This validates the mockup's two-number impact bar as load-bearing, not decorative.** "Customers
will see X" and "printed sheet Y pages" move in *opposite directions* as the publisher list widens,
so an admin editing one list needs both numbers in front of them. A single "titles visible" readout
would have hidden exactly this trade.

---

## 3. Architecture decisions

### 3.1 A separate `settings.html`, not a fourth admin mode — decided on performance

`admin.html` is 318,300 bytes, of which **264,170 is inline `<script>`** and only 54,130 is markup
(277 elements — the DOM is small; the weight is script). Two structural facts decide this:

- **HTML is uncacheable across deploys, by deliberate policy.** `_headers` names `app.js`,
  `config.js`, `vendor/` and the artwork, and names **no `.html` file** — every page falls to
  Pages' default `max-age=0, must-revalidate`. Because the settings code would be *inline*, every
  settings tweak would re-download ~348 KB for every admin. As its own file, a settings deploy
  leaves `admin.html`'s ETag untouched → 304.
- **The script is one sequential IIFE with a documented silent-failure hazard.** `applyMode()` runs
  at `:1791`, ~4,300 further lines evaluate, and `runInitialTabLoad()` (`:1769`) must stay last —
  its own comment records that calling it earlier hits a temporal dead zone where the
  ReferenceError "fails **SILENTLY** and the tab just renders empty." A mode adds `let`s to that
  body. Boot already makes two *sequential* `app_settings` reads (`:3836`, `:3868`); a mode would
  want a third.

**The counter-cost, stated honestly:** a page navigation costs ~4 serialized round trips of fixed
boot overhead — `user_profiles` is read **three times** (`app.js:327` via `requireAdmin`,
`app.js:76` via `TenantContext.resolve`, `app.js:567` via `initNav`), none memoized across each
other, plus one `tenants` read. A mode switch costs zero network.

**Frequency settles it.** `admin.html` is opened constantly (daily bagging, weekly shipment,
monthly ordering); settings is configuration, opened rarely and deliberately. Paying ~200-400 ms on
the rare path to spare the constant one is the right direction.

**Cost accepted:** `settings.html` becomes the **seventh** member of the nav-sync set
(§ Files That Must Stay in Sync). That is a correctness risk, not a performance one — `analytics.html`
was missing from that list until 2026-08-15 — and it is mitigated by listing it, not by avoiding it.

### 3.2 Filters are query predicates, not a client-side pass

This determines whether the feature makes the customer catalog faster or slower, for identical UI.

`catalog.html`'s boot is already 6+ serialized steps, two of them multi-page: `Catalog.getPublishers()`
(`app.js:794`) pages the whole month's `publisher` column (2,399 rows → 3 round trips) purely to fill
a dropdown, and the Reserved / Unreserved / FOC-this-month paths deliberately "fetch ALL matching"
rows (`catalog.html:799-820`).

- **Server-side** — those paths fetch 1,534 rather than 2,399 rows, 3 round trips become 2, and
  pagination depth drops. Publisher filtering is **already** server-side via `.eq()` at
  `catalog.html:636` and `:818`, so `.in()` is a drop-in. Net: **faster than today.**
- **Client-side** — fetch everything, then hide. Strictly slower than today.

Mechanics:
- Publisher → **always `.not('publisher','in',hidden)`. Store EXCLUSIONS, never inclusions.**
  See § 3.2.1 — this is a correctness requirement, not an optimization, and it reverses what this
  line originally said.
- Ratio threshold → **no numeric parsing**, but the set is larger than assumed. **Measured
  2026-09-23: 22 distinct values on staging** (1:1, 1:2, 1:3, 1:4, 1:5, 1:7, 1:10, 1:15, 1:20, 1:25,
  1:30, 1:40, 1:50, 1:60, 1:75, 1:100, 1:125, 1:200, 1:250, 1:300, 1:500, 1:1000), 18 on
  `demoshop`, **all well-formed** — zero rows fail `^[0-9]+:[0-9]+$`. So `.in()` still works and is
  still ~150 characters of URL, but two design consequences follow:
  **(a) the mockup's fixed six-option dropdown misrepresents the data** and must be built from the
  distinct values actually present (or replaced with a numeric "denominator ≤ N" input);
  **(b) 1:1 and 1:2 are barely restrictions at all** — 1:1 means order one, get one — so grouping
  them under "allocation-restricted" is questionable labelling worth revisiting in S2.
  Current-month ratio rows sum to exactly **332**, reconciling with § 1.3's cover-class total, so
  the data is internally consistent.
- Cover class, price, FOC → plain predicates.
- **The reservation exemption (§ 3.3) cannot be a predicate** — it needs the customer's own reserved
  set, which is already in memory as `reservedIds`. It is a client-side union applied after the fetch.

### 3.2.1 ⚠️ Store publisher EXCLUSIONS, not inclusions — Rick, 2026-09-23

**Raised by Rick, and it identifies a failure mode this design would have introduced that the
current code does not have.** Today's ≥7 bar is *computed* from reserve history on every load —
nothing is persisted, so there is no snapshot to go stale. A stored publisher list is a snapshot of
values **the distributor controls**.

**The source is already inconsistent, measured:** `Titan` and `Titan Comics` coexist in the *same*
catalog month (§ 8). So this is not drift over time — the export is non-canonical today.

| stored | on a rename | result |
|---|---|---|
| allowlist (shown) | old name stops matching | **that publisher's titles silently vanish** from catalog *and* print |
| **blocklist (hidden)** | old name stops matching | **titles reappear** |

**Exclusions fail in the harmless direction.** A publisher appearing unexpectedly is a one-click fix;
a publisher you sell disappearing silently is the F155-shaped harm — invisible until a customer
complains. It also matches real use: hide the handful you do not want rather than enumerating the 14
you do, so the stored list is normally **short**, not 58 entries.

**This reverses advice given earlier in this plan** — "store whichever list is shorter, `in` with 14
shown, `not.in` with 58 hidden." That was an optimization applied to a decision that is not about
size: which direction you store determines the failure mode, so exclusions win even when they are the
longer list and the URL is longer.

**And it re-scopes the "Reserved ≥ 7" preset (§ 7 Q3).** It cannot be a *living* rule. A persistent
threshold recomputes each load, which looks immune — but a renamed publisher's history does not
follow the new name, so it reads as 0 reservations and **the rule hides it**, reintroducing the exact
failure through the back door. The preset must therefore be a **one-time list-populator**: clicking
it writes today's under-7 publishers in as explicit exclusions, and from then on it is a curated list
that fails open. Honest about what it is.

**Prevention is not complete, so detection stays** (§ 8): the settings page surfaces "N publishers in
your configuration no longer match this month's catalog" and flags near-duplicate names, which
catches a rename that quietly un-hid something.

### 3.3 The reservation exemption is locked on

**A title the customer has already reserved is never hidden.** Without this the feature recreates
F155's stranding exactly: present in the database, absent from every surface the customer can reach.
It is not a preference and gets no toggle — the impact bar states how many titles it is keeping
visible so the admin can see it working.

### 3.4 Fail open — and with the bar deleted, "open" is simply everything

**Missing key, malformed JSON, unparseable blob, or an empty exclusion list → show everything, on
both surfaces.** `app_settings.value` is untyped text with no CHECK constraint, so a bad blob must
never be able to empty a surface.

*(This section has been revised twice. It first said plain "show everything", which was right in
spirit but assumed the ≥7 bar stayed, so the print would have jumped to 45 pages unasked. It was then
rewritten as a per-surface table preserving each surface's current behaviour. **Deleting the bar
(§ 2.1) makes both of those moot** — there is no legacy print behaviour left to preserve, and the
default is genuinely "everything" on both sides. The intermediate table is dropped; the reasoning is
kept so a reader does not re-derive it.)*

Two properties worth stating plainly:

- **The default state persists nothing.** No `catalog_filters` row exists until an admin saves one,
  so there is no snapshot to go stale and no spelling to mismatch (§ 3.2.1).
- **Direction, not value, is what matters.** This mirrors
  `Settings.isMaintenanceModePublic()`'s fail-open and is the deliberate **inverse** of `Tier`, which
  fails closed because *free* is its safe render. Here the safe render is everything, because an
  empty catalog is a broken store and an over-long print is only paper.

⚠️ **S4 is therefore NOT a no-op any more** — deleting the bar takes the print from 33 to 45 pages
on its first run. That is the one visible change in the whole sequence, it is intended, and § 4 S4
carries the timing note.

### 3.5 Do NOT materialize a `catalog_visible` column

Tempting as a scale answer, and it is the **F132/F156 shape**: `order_requirement` is a derived
column that sits permanently NULL on 67 production rows because older catalog months are never
re-pulled. A visibility flag derived from config drifts identically the moment the config changes
and some rows are not rewritten. Keep it a predicate evaluated at read time.

### 3.6 Publisher counts come from an RPC, not from paging the tables

`getReservedPublishers()` pages the **entire** `reservation_history` *and* `preorders` tables to
compute counts it then discards, keeping only a Set. Production is ~3,100 rows / 4 round trips today;
a three-year tenant is 10-15 round trips of 1,000 rows to render 78 numbers. This is the same
unbounded-read shape as F82 / F113 / F139 / F140 / F156.

New RPC — **`get_publisher_reserve_counts(p_catalog_month text DEFAULT NULL)`**, `LANGUAGE sql
STABLE SECURITY DEFINER SET search_path = public`, returning
`(publisher text, reserved_count bigint, month_title_count bigint)`. Written:
`docs/sql/2026-09-23-publisher-reserve-counts-rpc.sql`. Precedent: `get_ordered_codes()` and
`get_popular_series()` are the same shape. **This also makes the existing Print Catalog cheaper, so
it pays for itself outside this feature.**

**⚠️ Two corrections this file originally had wrong, kept visible per convention.**

1. **It specified `get_publisher_reserve_counts(p_tenant_id uuid)`. That is a cross-tenant leak.**
   The grant is to `authenticated`, so any signed-in customer could have passed another tenant's
   uuid and read its reserve history. Tenant scope comes from `current_tenant_id()` **in the body**,
   never from a caller-supplied parameter — the pattern every other RLS-adjacent function here
   already follows.
2. **It returned only `reserved_count`, which is not enough to render the page.** The settings list
   needs each publisher's title count for the month as well (the mockup's second column), and a
   publisher present this month with *no* reserve history must still be listed — so the count cannot
   come from a reservations-only aggregate. The RPC now `FULL OUTER JOIN`s month publishers against
   all-time reserve counts, which means it **also retires `Catalog.getPublishers()`'s own full-month
   paging** (`app.js:794`, 3 round trips at 2,399 rows) for this caller.

**Grant: `authenticated` only**, with `REVOKE ALL … FROM PUBLIC, anon`. F124 records the only four
functions that may legitimately carry an `anon` grant; this is not one of them.

**Do not "improve" the counting rule inside this function.** It must reproduce
`getReservedPublishers()` exactly — every row of both tables, all catalog months, regardless of
`fulfilled`, keyed `lower(btrim(publisher))` to match the JS `pub.trim().toLowerCase()` — so that a
V2 discrepancy means a real difference rather than a deliberate one.

---

### 3.7 The promotional group shrinks to one toggle — measured, 2026-09-23

S0 Q5, both staging tenants: **`price_usd = 0` is 4 titles. `price_usd IS NULL` is 0. Negative
prices are 0.** The mockup assumed 27 and 9.

**Ship one toggle, not two.** "Priced $0.00 — 4 titles" is worth having; a toggle governing zero
rows is clutter that implies a population that does not exist.

**The no-price case becomes a data-quality signal, not a visibility filter**, which is what this
file's own S0 comment predicted: *"If no_price_set is large, that is an import-quality finding of its
own, not a filter requirement."* It measured zero, so it is not a filter requirement. Keep the
filter *model* able to express it — a future import can produce NULLs, exactly as F156's
`order_requirement` did — but surface a non-zero count as a warning rather than a switch.

⚠️ **Four titles is small enough to question the group's existence at all.** Kept because it is
nearly free once the section scaffolding is there, and because a free promotional bundle is exactly
the kind of row `0726DC0300` (F155's stale DC Connect bundle) shows up as. Rick's call if he would
rather drop it from v1.

---

## 4. Work breakdown

Each step is independently safe and independently revertible. **S2 writes a config nothing reads;
S4 is the only step that changes what anyone sees.**

### S0 — Measure (read-only, both environments). BLOCKING. ✅ QUERIES WRITTEN 2026-09-23

**File: `docs/sql/2026-09-23-s0-catalog-visibility-baseline.sql`** — eight queries, Q1–Q8, every one
a `SELECT`. STATUS `N/A` on both environments, which is the correct token: the file creates, alters
and writes nothing.

**⚠️ Run them ONE AT A TIME.** The Supabase SQL Editor shows only the last statement's result, so
pasting the whole file displays Q8 and silently discards Q1–Q7. Each query states its expected shape
*before* it runs, so a surprise triggers re-verification rather than remediation.

**Q1 is the one to run first, and it is self-validating.** It replicates the print's two hardcoded
filters in SQL and predicts each tenant's printed row count. That SQL cannot validate the client —
but the client validates *it*: the 1,534 rows / 34 pages figure came from a real print on
2026-08-24. If the founding-tenant row lands there, the model is sound and Q1's `demoshop` prediction
of **0** can be trusted, which confirms F160 without printing anything. If it does not land there,
that discrepancy matters more than F160 and everything stops.

No code. Confirms § 2 and replaces this plan's estimates with figures.

1. **Confirm the cold start.** Print the Paper Orders catalog for staging's `demoshop`
   (2,288 copied catalog rows). Expect a blank sheet. Also read `comicstore` on production.
2. Per-tenant reserve counts by publisher (service-role `GROUP BY`) — the real numbers the settings
   page will show, both environments.
3. Real cover-class populations for the current month: standard / variant-no-ratio /
   allocation-restricted, and the distinct `order_requirement` values with counts.
4. `price_usd = 0` and `price_usd IS NULL` counts.
5. `SELECT pg_total_relation_size('public.catalog')` — § 8's storage estimate is derived from row
   counts and **must not be planned on until measured**.

### S1 — `get_publisher_reserve_counts()` RPC (DB only) — ✅ WRITTEN 2026-09-23, NOT APPLIED

**File: `docs/sql/2026-09-23-publisher-reserve-counts-rpc.sql`**, STATUS line
`staging=PENDING | prod=PENDING`. Rick runs it; staging first, production before S4 deploys there
(F105 — the RPC lands **before** any client code that calls it, never after).

The file carries, in order: a **pre-check** on the five columns it depends on (§ 4 of the technical
reference was last re-read from live 2026-08-10 and columns have been added to `catalog` since —
expected 6 rows, and fewer means stop), the function, the grant plus revoke, a grants verification,
a `prosecdef`/`proconfig`/overload check that `CREATE OR REPLACE` did not drop `SECURITY DEFINER` or
leave a stray signature, a smoke with **its expected values stated before it runs**, and a rollback
line.

**⚠️ The smoke cannot run as written in the SQL Editor and the file says so.** The editor runs as
`postgres`, so `current_tenant_id()` resolves through `auth.uid()` and returns NULL — the function
returns **zero rows**, which is correct behaviour and not a failure. The file therefore ships a
second query that substitutes an explicit tenant id for the smoke, and defers the real check to V2
in a signed-in browser.

### S2 — `settings.html`, nav rework, gear activation (client only, zero behaviour change)

- New `settings.html`, admin-gated via `Auth.requireAdmin()`. Nav + footer blocks copied from the
  most-recently-touched page; script load order Supabase → `config.js` → `app.js` → page script.
- **Add it to CLAUDE.md § Files That Must Stay in Sync as the seventh page, in the same commit.**
- Desktop nav: Admin / Analytics / Settings collapse into one `Admin ▾` disclosure.
- Mobile: `NavSettingsPlaceholder` (`app.js:528`) becomes a real link. **Delete the
  `aria-hidden="true"` and `tabindex="-1"` at `app.js:539-540`** — otherwise the only mobile route
  to Settings is invisible to a screen reader and unreachable by keyboard. Note it self-gates on
  `#search`'s *absence*, so it renders on admin / analytics / settings and **not** on the four
  customer pages; an admin on `catalog.html` reaches Settings via the hamburger. That is accepted.
- Writes `app_settings.catalog_filters`. **Nothing reads it yet.**
- Left rail carries `Branding` and `Email Templates` as disabled "Soon" entries (§ 6).

### S3 — ~~Seed the founding tenants~~ — ❌ DELETED 2026-09-23

**This step is gone, and the reason is worth keeping.** It originally said: write a
`catalog_filters` reproducing today's effective print behaviour for `raysandjudys` and
`rjbookstop`. S0 measured that as a **34.5% cut to the customer catalog** (§ 2.1) — it would have
shipped that silently as a routine data step.

It was then rewritten as optional, to accompany § 3.4's per-surface default. **Deleting the ≥7 bar
removes its purpose entirely**: there is no legacy behaviour to preserve, so there is nothing to
seed. The default is no config row at all.

**Nothing replaces it.** The founding tenants get no seeded config; Rick's first save on the settings
page is the first stored config that has ever existed, made with the impact bar in front of him.

### S4 — Delete the ≥7 bar and apply the config (client only — the behaviour change)

**Two things, and the first is the one that changes what anyone sees.**

**(a) Delete the publisher bar** — `MIN_RESERVED` (`admin.html:5249`), `getReservedPublishers()`
(`:5251`) and the `reserved.has(...)` clause at `:5329`. The FOC clause at `:5330` **stays** for now
and becomes config-driven in (b). The counts the settings UI needs come from S1's RPC, so nothing
else needs that function.

- **This is F160's fix.** No bar means an empty reserve history cannot produce a blank sheet. The
  fail-open floor § 2 proposed is not built — it was a patch on the thing being removed.
- **Print goes 33 → 45 pages on its first run** (§ 2.1). Intended, and the only visible change in
  the sequence.
- **Sweep before deleting.** `getReservedPublishers()` is memoized and shared; confirm no other
  caller exists (`grep` showed 2 call sites, both in the combined print, 2026-09-23 — re-verify at
  build time). Per CLAUDE.md's own rule, sweep the suite for references before deleting anything
  with an id or a name.

**(b) Apply the config where one exists.**

- `catalog.html`: read `catalog_filters`, fold the read into an existing parallel batch rather than
  adding a 7th serialized step, apply as predicates per § 3.2 — **publisher as `.not(...in...)` per
  § 3.2.1** — and apply the reservation exemption per § 3.3.
- `admin.html`: the same config inside `fetchAllCatalogForDistributor()`, the single chokepoint.
- **No config row → everything, both surfaces** (§ 3.4).

**⚠️ Timing.** The page-count change lands on the next print. The **2026-09-25 October import is
already an attended gate** carrying F146's and F147's first-ever live production exercise, and a
paper change should not share that window. Either land S4 on production after that gate is verified
green, or before it with Rick explicitly expecting a 45-page sheet.

Deploy staging → verify → **production promotion is a separate, explicitly requested step.**

---

## 5. Verification gates

| Gate | Assertion |
|---|---|
| V1 | ✅ **DONE 2026-09-23, both environments.** S0 confirmed § 2's cold start and corrected its definition — the trigger is "no publisher clears the bar", not "zero reserve history" (§ 13 F160) |
| V2 | RPC returns the same publisher set as today's `getReservedPublishers()` at threshold 7, on both environments — proven by comparing against the old paging implementation, not assumed. **Must run BEFORE S4 deletes that function**, or there is nothing left to compare against (§ 5.1) |
| V3 | With no `catalog_filters` row, both surfaces show **everything** (§ 3.4) — tested by deleting the key, not by reasoning |
| V4 | **REPLACES the old "print unchanged at 1,534 / 34" assertion, which the bar deletion makes false.** After S4 with no config row, the production print is **2,068 rows / 45 pages**; with the "Reserved ≥ 7" preset clicked it returns to **1,507 / 33**. Both asserted, because the second is what proves the preset reproduces the old behaviour rather than approximating it |
| V4a | **Publisher exclusions survive a rename in the safe direction** (§ 3.2.1): with a publisher excluded, rewrite its `catalog.publisher` value on a scratch row and confirm the row **reappears** rather than staying hidden. Negative-control the assertion by confirming it fails if the config is inverted to an allowlist |
| V5 | A reserved title stays visible to its customer with its publisher hidden (§ 3.3), asserted in a real browser |
| V6 | Publisher filtering is confirmed to reach the **query**, not the client — assert the request's `publisher` param, and that the row count fetched drops |
| V7 | Malformed JSON in `catalog_filters` shows everything and logs, rather than emptying the catalog |
| V8 | `node --check` clean on every touched inline `<script>`; nav + footer blocks on `settings.html` hash-identical to the other six |
| V9 | Full Playwright suite green against deployed staging bytes **post-push**. Current baseline **147 passed** |
| V10 | New spec asserting V3, V4a, V5 and V7 — the suite has **zero** coverage of any of this today, so a green run otherwise proves only that nothing else broke |
| V12 | **`getReservedPublishers` and `MIN_RESERVED` return ×0** in the served `admin.html` after S4, and `06-admin-this-week-bagging` / `17-admin-modes` are swept for references before the deletion (CLAUDE.md's rule after the single-catalog-print session turned the suite red by deleting a classed element) |
| V11 | Post-deploy: served bytes verified with `curl -L` (the documented 302 trap), positive **and** negative assertions |

### 5.1 V2 in full — the parity gate, and why it is a browser check and not SQL

The RPC must reproduce `getReservedPublishers()` exactly. **Checking it with SQL that reimplements
the same rule would be circular** — "a verification step that cannot fail is not a verification
step" (§ Smoke Test Suite). So V2 runs *both implementations in one signed-in admin session* and
diffs them. The old one goes through PostgREST under RLS; the new one is a single `GROUP BY`. Two
independent paths, same session, same data.

`db` is a top-level `const` in `app.js`, loaded as a classic script, so it resolves from the console's
global scope. Paste this on the deployed admin page, signed in as an admin:

```js
(async () => {
  const MIN = 7;

  // ── OLD — byte-faithful copy of getReservedPublishers() (admin.html:5251) ──
  const counts = new Map();
  async function collect(table, selectExpr, extract) {
    const countRes = await db.from(table).select('*', { count: 'exact', head: true });
    const total = countRes.count ?? 0;
    if (!total) return;
    const batches = [];
    for (let from = 0; from < total; from += 1000) {
      batches.push(db.from(table).select(selectExpr).range(from, Math.min(from + 999, total - 1)));
    }
    const results = await Promise.all(batches);
    results.flatMap(r => r.data || []).forEach(row => {
      const pub = extract(row);
      if (pub) {
        const key = pub.trim().toLowerCase();
        counts.set(key, (counts.get(key) || 0) + 1);
      }
    });
  }
  await Promise.all([
    collect('reservation_history', 'publisher', r => r.publisher),
    collect('preorders', 'catalog(publisher)', r => r.catalog?.publisher),
  ]);
  const oldSet = new Set([...counts].filter(([, n]) => n >= MIN).map(([k]) => k));

  // ── NEW — the RPC ──
  const { data, error } = await db.rpc('get_publisher_reserve_counts');
  if (error) { console.error('RPC failed', error); return; }
  const newSet = new Set(
    data.filter(r => Number(r.reserved_count) >= MIN)
        .map(r => r.publisher.trim().toLowerCase())
  );

  // ── DIFF ──
  const onlyOld = [...oldSet].filter(k => !newSet.has(k));
  const onlyNew = [...newSet].filter(k => !oldSet.has(k));
  const mismatch = data
    .map(r => ({ k: r.publisher.trim().toLowerCase(), rpc: Number(r.reserved_count) }))
    .filter(r => (counts.get(r.k) || 0) !== r.rpc);

  console.log('old >= 7:', oldSet.size, ' new >= 7:', newSet.size);
  console.log('only in OLD:', onlyOld);
  console.log('only in NEW:', onlyNew);
  console.log('per-publisher count mismatches:', mismatch);
  console.log(!onlyOld.length && !onlyNew.length && !mismatch.length
    ? 'V2 PASS — identical' : 'V2 FAIL — investigate above');
})();
```

**Negative-control it before believing a pass**, per this project's standing practice: change `MIN`
to `6` on the `newSet` line only, re-run, and confirm the diff reports publishers "only in NEW". If
it still says PASS, the comparison is vacuous and the real result is unknown.

**Two expected non-failures, so neither is mistaken for a defect.** Publishers with `reserved_count`
0 appear in the RPC output and not in the old Map — `counts.get(k) || 0` makes those compare equal,
by design, because the settings page must list a publisher that has titles this month and no
history. And a publisher with history but no titles this month comes back with its *lowercased* key
as its display name, since there is no current row to take canonical casing from.

---

## 6. Out of scope — stop and ask

- **Moving Order Deadline / Maintenance Mode onto this page.** They stay on Admin ▸ Ordering.
  `17-admin-modes.spec.ts` asserts them there; moving them is its own change with its own spec sweep.
  The left rail *links* to them, deliberately.
- **Branding and Email Templates.** Placeholder entries only. Both are F72's live backlog — five of
  the six mail functions still greet every tenant's customers as the founding tenant, and
  `rjbookstop.com` still has no backing field (F72 S3 Q2).
- **The 3× `user_profiles` read per page load** (§ 3.1). Collapsing it would cut ~2 round trips off
  *every* page in the app and directly reduce this plan's only real cost. Real, out of scope, not filed.
- **A shared catalog with per-tenant overlay** (§ 8). Much larger than this feature.
- **F131** — the single-operator catalog-import SPOF. Still the real gate on tenant growth.

---

## 7. Open decisions — Rick

**Q1 — ANSWERED 2026-09-23 (Rick): filed as F160.** The § 2 cold start is a genuine shipped defect,
not a design choice. Filed ahead of S0's live confirmation rather than after it, with that limit
stated in the finding itself.

**Q2 — ANSWERED 2026-09-23 (Rick): hide past-FOC on BOTH surfaces.** This is the one place the two
surfaces cannot both keep today's behaviour — one rule now governs both, so unification necessarily
moves one of them. Rationale for the direction taken: a title past FOC is already unreservable, since
`isFocLocked` → `isFocPast` blocks new reservations *and* cancellations, so showing it in the
customer catalog advertises something that cannot be ordered.

**⚠️ This is a customer-visible change and S3's seed must encode it deliberately.** Customers stop
seeing rows they see today. The print sheet is unaffected — it already hides them — so V4's
"unchanged at 1,534 / 34" still holds. Measure the customer-side delta in S0 (how many current-month
titles have a passed FOC) so the size of the change is known before it ships, not after.

**Q3 — REVERSED 2026-09-24 (Rick): the "Reserved ≥ 7" preset is REMOVED, not kept.** Rick saw it on
the staging page and said *"I thought we would remove this."* He is right, and **my answer to this
question went stale the moment Q4 was decided** — the two came in that order and I did not
re-examine the first.

**Why it had to go.** Q3 was answered "keep it" on the rationale that *it reproduces today's
behaviour in one click*, which was a virtue while the plan still preserved today's behaviour. Q4
then decided today's behaviour is the defect. So the button's one function became **reconstructing
in a single click the exact hardcoded bar this change exists to delete** — hiding 58 of 72
publishers, including Oni Press (67 titles), Seven Seas (81) and Yen Press (52). Its label also kept
a deleted mechanism alive by name, which is how a removed rule creeps back.

**Nothing replaces it.** Sorting by "Most reserved" already puts the least-reserved publishers at
the bottom with their title counts beside them, so trimming the sheet stays possible — as a
deliberate act, with the page count moving in the impact bar as you go. That is curation informed by
data, which is the entire point of the page; a preset is the opposite.

*(The earlier re-scoping argument is kept because it remains true and is the reason no future version
of this should be a live rule: a persistent threshold recomputes each load and looks immune to
spelling drift, but a renamed publisher's history does not follow the new name, so it reads as 0
reservations and the rule hides it — reintroducing the silent-disappearance failure § 3.2.1 exists to
prevent. If a trim helper is ever wanted, it must populate a list, never persist as a rule.)*

**Q4 — ANSWERED 2026-09-23 (Rick): delete the ≥7 publisher bar** rather than encode it. See § 2.1 —
this is the decision that collapsed § 2.1's three-way fork, deleted S3, and turned F160's fix into a
deletion. Cost: the print goes 33 → 45 pages; customers are unaffected.

**Q5 — ANSWERED 2026-09-23 (Rick, by raising it): store publisher EXCLUSIONS, not inclusions.**
See § 3.2.1.

*Provenance note: Rick's reply numbered these "Q1, agree - Q2, agree" against the two decisions
raised in conversation (past-FOC, then the preset), which are this doc's Q2 and Q3. Q1 was already
closed by the F160 filing earlier in the same session. Recorded this way so the mapping is visible
if it needs correcting.*

**Q6 — Does the page-vs-mode decision hold?** Settled on performance in § 3.1; recorded here because
it is the decision most likely to be revisited. *(Was Q4 until 2026-09-23; renumbered when the bar
deletion and exclusion storage took Q4/Q5.)*

**Q7 — ANSWERED by measurement 2026-09-23: § 8's storage estimate is no longer derived.** Production
Q7 returned **2,001 bytes/row**, putting the free-tier ceiling at roughly **20 tenants**. Infrastructure
spend can now be planned on it. *(Was Q5.)*

---

## 8. Scaling notes — 100+ tenants

**The feature itself is O(1) in tenant count.** Everything is RLS-scoped; there is no cross-tenant
fan-out. 100 tenants is 100 `app_settings` rows of ~2 KB, and one PK seek per catalog load.

What does scale, and how it is handled here:

| Concern | At 100 tenants | Handled by |
|---|---|---|
| Publisher counts | O(each tenant's whole history) — 10-15 round trips for a mature tenant | § 3.6 RPC |
| Cold start | **every** new tenant starts with an empty catalog | § 2 + § 4 S3 |
| Filter predicates | `publisher` indexed; `variant_type`, `order_requirement`, `price_usd` are not | wants a `(tenant_id, catalog_month, publisher)` composite index — measure in S0 |
| `.in()` URL length | ≤ 39 names worst case, per-tenant | not a scale-out issue |

**Two multi-tenant fragilities worth carrying forward:**

1. **The config is keyed on free text the distributor controls — ⚠️ NO LONGER HYPOTHETICAL,
   MEASURED 2026-09-23.** Allowlists store publisher names, normalized `trim().toLowerCase()`. This
   section originally speculated *"if Lunar re-spells BOOM! Studios…"*. S0 Q2 shows the same
   publisher already present under two names **today**:

   | | |
   |---|---|
   | `Titan Comics` 95 titles · `Titan` 1 title | same publisher, two rows |
   | `Kodansha Comics` 24 · `Kodansha USA` 7 | |
   | `Fantagraphics` 11 · `Fantagraphics Underground` 1 | arguably distinct imprints |
   | `Random House Children's Books` 8 · `…Publishing Group` 3 · `…Worlds` 22 | three |
   | `Penguin Publishing Group` 6 · `Penguin Young Readers Group` 10 | |
   | `Disney - RHCB` 1 · `Disney Publishing Group` 3 | |

   Note also that the founding tenant's Boom is **`Boom Entertainment`**, not the `BOOM! Studios`
   this plan and the mockup both assumed — so "78 publishers" and the mockup's publisher names were
   both invented rather than read.

   **Two consequences were predicted. Production Q2 confirms one and REFUTES the other.**

   **(a) CONFIRMED, live on production.** `Titan Comics` (167 reserved, 95 titles) is shown; `Titan`
   (2 reserved, 1 title) is **hidden**. One real title is dropped from the printed sheet because it
   is filed under the short spelling. Tiny, but real, and it is on paper today.

   **(b) REFUTED — do NOT file it.** I predicted that split counts would push a publisher below the
   bar: "4 + 4 never clears the 7 that 8 would have." Checked against every near-duplicate pair on
   production, it does not happen. `Titan Comics` clears the bar on its own 167, so merging changes
   nothing; every other pair sums to less than 7 either way (Kodansha 0+0, Fantagraphics 0+0, the
   three Random House entries 3+0+0, Penguin 0+0, Disney 0+0). **The mechanism is real and its
   harmful case is absent from the data.** Recorded because a prediction that fails is worth as much
   as one that holds — and because the arithmetic would change the moment a second spelling starts
   accumulating reservations.

   **The structural fix is § 3.2.1: store EXCLUSIONS, not inclusions**, so a rename fails by making
   titles reappear rather than vanish. That is prevention, and it is the reason this fragility is no
   longer load-bearing.

   **S2 requirements, still mandatory as detection:** surface "N publishers in your configuration no
   longer match this month's catalog", *and* flag near-duplicate publisher names in the list so the
   admin can see `Titan` sitting beside `Titan Comics` instead of scrolling past it. With exclusions
   stored, the case these catch is a rename that quietly **un-hid** something — annoying, not
   harmful, but worth seeing.
2. **Catalog rows are copied per tenant — ✅ MEASURED 2026-09-23, and the threshold is much nearer
   than 100 tenants.** `demoshop` was created with 2,288 rows copied from the founding tenant. S0 Q7
   on staging: `catalog` is **20 MB across 13,071 rows = 1,633 bytes per row** — **2.3–5× my
   300–700 estimate**, which was wrong in magnitude while right in direction.

   **Production, measured the same day, is heavier still: 22 MB across 11,276 rows = 2,001 bytes per
   row**, and Q7's 100-tenant projection there is **2,151 MB**. At ~22.6 MB of `catalog` per real
   tenant, **the free tier's 500 MB is exhausted at roughly 22 tenants** — and that is `catalog`
   alone, before `preorders`, `reservation_history`, `usage_events`, `order_submissions` and
   `weekly_shipment`, so the practical ceiling is **under 20**.

   *(Staging measured 1,633 bytes/row and ~28–30 tenants. Production's 2,001 is the number to plan
   against — it has the real retained-month profile.)*

   *(The original estimate is kept above rather than deleted. It was derived from row counts with a
   guessed row width; the row width was the part that was wrong.)*

   **So the binding constraint arrives at roughly 20 tenants, and it is Supabase storage, not
   email** — reversing the standing assumption that MailerSend's 500/month cap was the near-term
   ceiling (that was formed at two tenants, and email has since moved to Resend at 3,000/month).
   Supabase Pro is 8 GB at $25/month total, which at $39–50/tenant is covered many times over by the
   20th tenant's own subscription. **A line item to plan, not a redesign — and not this feature's
   problem or fix.** Worth noting against the Founding Partner plan's "next 5 free-year slots": the
   ceiling sits close enough that it lands inside the first cohort's growth, not beyond it.

---

## 9. Completion criteria

- [x] S0 queries written — `docs/sql/2026-09-23-s0-catalog-visibility-baseline.sql` (2026-09-23)
- [x] S0 run on **STAGING** 2026-09-23 — F160 CONFIRMED (Q1/Q8), storage measured (Q7), ratios and cover classes measured (Q3/Q4), FOC cost measured (Q6). Three results changed the plan: § 2.1, § 3.2 ratios, § 8 storage
- [x] S0 Q2 + Q5 run on staging 2026-09-23 — three-way arithmetic reconciliation confirmed (§ 2.1); publisher fragmentation measured (§ 8); promotional group cut to one toggle (§ 3.7)
- [x] S0 run on **PRODUCTION** 2026-09-23 — F160 confirmed there too and its definition corrected (§ 13 F160); model validated (14 publishers, matching the real print exactly); reconciliation held on independent data (1,616 − 109 = 1,507); real reserve history obtained (§ 2.1); storage threshold revised to ~20 tenants (§ 8). **Q5 still owed on production**
- [x] **§ 2.1's unification decision made by Rick 2026-09-23: DELETE the ≥7 bar.** Collapsed the three-way fork, deleted S3, turned F160's fix into a deletion, and made the default "store nothing"
- [x] Q1–Q5 answered by Rick and recorded in § 7 (2026-09-23) — incl. Q4 bar deletion and Q5 exclusion storage; Q6/Q7 renumbered
- [x] S1 SQL written — `docs/sql/2026-09-23-publisher-reserve-counts-rpc.sql` (2026-09-23)
- [ ] S1 RPC applied to staging, verified by **V2 — which must run BEFORE S4 deletes `getReservedPublishers()`**, or the comparison has no baseline
- [x] **S2 merged to `staging` `--ff-only` and pushed 2026-09-23** (`cd88153`) — `settings.html` + the nav link on all six existing pages + `app.js` + `style.css`; `settings.html` added to CLAUDE.md § Files That Must Stay in Sync **in the same commit**, as required
- [x] `aria-hidden` / `tabindex` removed from the gear — `NavSettingsPlaceholder` → `NavSettingsLink`, admin branch renders a real `<a href="settings.html">`
- [x] **Gates green on S2.** `node --check` clean on `app.js` + all 7 inline scripts; unit **321/321**; **Playwright 147 passed, 0 failed, exit 0, 20.0m** against deployed staging bytes post-push, with the test count present in the log (the only trustworthy figure — § Smoke Test Suite records a false GREEN at exit 0 with no tests run); nav **and** footer blocks hash identically across all seven pages; served bytes confirmed on the plain URL with `NavSettingsPlaceholder` at ×0
- [ ] **S2b — the `Admin ▾` dropdown grouping.** Deliberately NOT in `cd88153`: the nav still carries seven flat links. Split out so an 874-line new page and a restructure of the app's most-shared surface are reviewable apart. Spec dependencies already swept — `.nav-links`, `.nav-links a.active`, `#nav-hamburger` and `.nav-links .nav-bubble` must survive; nothing references `#nav-admin` or `#nav-analytics`
- [ ] **Follow-on, not S2:** migrate the seven inline copies of the standard-cover test onto `app.js`'s new `isStandardCoverType()` (§ 1.4). Deliberately deferred — they sit on customer-facing reserve paths
- [ ] ~~S3 seed applied~~ — **step deleted, nothing to seed**
- [ ] S4 merged to `staging` — bar deleted (a) and config applied (b); V3, V4, V4a, V5, V6, V7, V12 green
- [ ] V8, V9 (147+ baseline), V10 green
- [ ] Production promotion: **separate, explicitly requested.** S1's RPC lands on production **before**
      S4's client code (F105). **Sequence S4 clear of the 2026-09-25 October import gate** — that
      window already carries F146/F147's first live exercise and should not also carry a paper change
- [ ] V11 green against production's served bytes
- [ ] This doc's STATUS token updated; CLAUDE.md § Current Migration Phase advanced

---

## 10. Reference

- Mockup: https://claude.ai/artifact/2jeBZrDNnjkhbHCqnEXHNs
- `admin.html:5249` `MIN_RESERVED`, `:5251` `getReservedPublishers()`, `:5286`
  `fetchAllCatalogForDistributor()`, `:5329-5330` the two hardcoded filters, `:5685`/`:5687` callers
- `admin.html:1769` `runInitialTabLoad()` + its temporal-dead-zone note, `:1791` `applyMode()`
- `catalog.html:636` / `:818` publisher `.eq()` — the drop-in points for `.in()`
- `app.js:68` `TenantContext.resolve()`, `:306` `getProfile()`, `:324` `requireAdmin()`, `:528`
  `NavSettingsPlaceholder`, `:539-540` the two attributes to delete, `:794` `Catalog.getPublishers()`,
  `:914-934` `Settings.get`/`set`
- `_headers` — why no `.html` file is cached
- `docs/technical-reference.md` § 4.2 `app_settings`, § 4.3 `catalog`, § 13 F132/F155/F156 (derived-column
  drift), F141 (admin CLS Pattern B)
- Related open findings: **F72** (branding/email — § 6), **F131** (import SPOF — § 6), **F157**
  (zero-row catalog guard)
