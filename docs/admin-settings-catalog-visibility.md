# Admin Settings — catalog visibility filters

**STATUS:** NOT STARTED · staging=— · prod=— · PR=— · findings: **F160 (filed 2026-09-23, see § 2)**

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

| | Monthly Catalog (`catalog.html`) | Print Catalog (Paper Orders) |
|---|---|---|
| Publisher filter | none (all 78) | **≥ 7 all-time reservations** (14 of 78 on prod) |
| Past-FOC filter | none | **hides FOC ≤ current catalog month** |
| Cover / ratio / price filter | none | none |
| Titles shown, prod 2026-08 | 2,399 | **1,534** (34 pages @ 46 rows) |

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
| Promotional | `catalog.price_usd` | numeric, nullable. `0` and `NULL` are different cases |

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
because only one tenant has reserve history. The gradient is already measurable:

- production, 14 publishers pass → 1,534 rows → 34 pages
- staging, 4 publishers pass → 638 rows → 15 pages
- a tenant with zero history → **0 publishers pass → 0 rows → blank sheet**

**Consequences for this plan:**

1. The default configuration for a tenant with no history must be **show all**, not "reserved ≥ 7".
2. Absence of a config row must mean **show all** (§ 3.4, fail-open).
3. The founding tenant must be seeded explicitly (§ 4 S3) so that turning this on changes nothing
   for it.

**Filed as F160, 2026-09-23** (Rick's instruction, same session) — see `docs/technical-reference.md`
§ 13 F160. **The filing is honest about its own limit: it is derived from reading the code path end
to end, and is NOT yet confirmed against a live zero-history tenant.** S0 item 1 is that
confirmation and still owed. F160's own fix is a one-line fail-open floor that can land
independently of this plan — worth doing if this plan does not ship soon, because exposure begins
at the next tenant onboarding rather than at this plan's schedule.

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
- Publisher → `.in('publisher', shown)` or `.not('publisher','in',hidden)`, **whichever list is
  shorter** (≤ 39 names worst case at 78 publishers).
- Ratio threshold → **no numeric parsing.** `order_requirement` holds a small enumerable set of
  strings, so it is `.in('order_requirement', ['1:5','1:10'])`.
- Cover class, price, FOC → plain predicates.
- **The reservation exemption (§ 3.3) cannot be a predicate** — it needs the customer's own reserved
  set, which is already in memory as `reservedIds`. It is a client-side union applied after the fetch.

### 3.3 The reservation exemption is locked on

**A title the customer has already reserved is never hidden.** Without this the feature recreates
F155's stranding exactly: present in the database, absent from every surface the customer can reach.
It is not a preference and gets no toggle — the impact bar states how many titles it is keeping
visible so the admin can see it working.

### 3.4 Fail open, never closed

Missing key, malformed JSON, unparseable blob → **show everything**. `app_settings.value` is untyped
text with no CHECK constraint. Failing closed means a store with an empty catalog and no visible
cause. This mirrors `Settings.isMaintenanceModePublic()`'s fail-open, and is the deliberate
**inverse** of `Tier`, which fails closed because *free* is its safe render — here the safe render is
everything.

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

New RPC — `get_publisher_reserve_counts(p_tenant_id uuid)`, `STABLE SECURITY DEFINER
SET search_path = public`, returning `(publisher text, reserved_count bigint)` from a `GROUP BY`
union of both sources. Precedent: `get_popular_series()` is the same shape. **This also makes the
existing Print Catalog cheaper, so it pays for itself outside this feature.**

---

## 4. Work breakdown

Each step is independently safe and independently revertible. **S2 writes a config nothing reads;
S4 is the only step that changes what anyone sees.**

### S0 — Measure (read-only, both environments). BLOCKING.

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

### S1 — `get_publisher_reserve_counts()` RPC (DB only)

`docs/sql/<date>-publisher-reserve-counts.sql`, with the `-- STATUS:` line. Explicit
`anon`/`authenticated` EXECUTE grant decision: **`authenticated` only** — this is an admin-facing
aggregate and there is no anon caller. Staging first; production before S4 deploys there.
Per F105: the RPC lands **before** any client code that calls it.

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

### S3 — Seed the founding tenants (data step, Rick)

Write an explicit `catalog_filters` for staging's `raysandjudys` and production's `rjbookstop`
reproducing **today's effective print behaviour** — the publishers that currently clear the ≥7 bar,
all cover types shown, past-FOC per Q2's answer, promos shown. Must land **before** S4 on each
environment, or the fail-open default briefly widens the print sheet.

### S4 — Apply the config (client only — the behaviour change)

- `catalog.html`: read the config, fold the read into an existing parallel batch rather than adding
  a 7th serialized step, apply as predicates per § 3.2, apply the reservation exemption per § 3.3.
- `admin.html`: replace the two hardcoded filters at `:5329-5330` with the config, inside
  `fetchAllCatalogForDistributor()` — the single chokepoint. `MIN_RESERVED` and the bare
  `getReservedPublishers()` Set are retired; the RPC feeds the settings UI instead.
- Deploy staging → verify → production promotion is a **separate, explicitly requested** step.

---

## 5. Verification gates

| Gate | Assertion |
|---|---|
| V1 | S0 confirms or refutes § 2's cold start on a real zero-history tenant. **If refuted, re-derive § 2 and § 4 S3 before proceeding.** |
| V2 | RPC returns the same publisher set as today's `getReservedPublishers()` at threshold 7, on both environments — proven by comparing against the old paging implementation, not assumed |
| V3 | With no `catalog_filters` row, both surfaces show **everything** (fail-open, § 3.4) — tested by deleting the key, not by reasoning |
| V4 | With the S3 seed applied, the production Print Catalog's row and page counts are **unchanged** from today's 1,534 / 34 |
| V5 | A reserved title stays visible to its customer with its publisher hidden (§ 3.3), asserted in a real browser |
| V6 | Publisher filtering is confirmed to reach the **query**, not the client — assert the request's `publisher` param, and that the row count fetched drops |
| V7 | Malformed JSON in `catalog_filters` shows everything and logs, rather than emptying the catalog |
| V8 | `node --check` clean on every touched inline `<script>`; nav + footer blocks on `settings.html` hash-identical to the other six |
| V9 | Full Playwright suite green against deployed staging bytes **post-push**. Current baseline **147 passed** |
| V10 | New spec asserting V3, V5 and V7 — the suite has **zero** coverage of any of this today, so a green run otherwise proves only that nothing else broke |
| V11 | Post-deploy: served bytes verified with `curl -L` (the documented 302 trap), positive **and** negative assertions |

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

**Q2 — Seeding the past-FOC rule, which is the one place the two surfaces cannot both keep today's
behaviour.** One rule now governs both, so unification necessarily moves one of them.
*Recommend: hide past-FOC on both.* A title past FOC is already unreservable for new customers —
`isFocLocked` → `isFocPast` blocks it — so showing it in the customer catalog advertises something
that cannot be ordered. The cost is that customers stop seeing rows they see today. The alternative
(show past-FOC on both) instead makes the printed sheet **longer**, which is paper.

**Q3 — Keep "Reserved ≥ 7" as a one-click preset?** *Recommend: yes.* It reproduces today's
behaviour in one click and is a sane starting point for an established tenant — as an explicit
choice rather than a constant.

**Q4 — Does the page-vs-mode decision hold?** Settled on performance in § 3.1; recorded here because
it is the decision most likely to be revisited.

**Q5 — § 8's storage estimate is derived, not measured.** S0 item 5 settles it. Do not plan
infrastructure spend on it before then.

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

1. **The config is keyed on free text the distributor controls.** Allowlists store publisher names,
   normalized `trim().toLowerCase()`. If Lunar re-spells "BOOM! Studios", that publisher silently
   drops from *every* tenant's allowlist at once — one upstream edit, N stores affected. Mitigation:
   the settings page surfaces "N publishers in your configuration no longer match this month's
   catalog" rather than failing quietly. **Build this in S2, not later.**
2. **Catalog rows are copied per tenant.** `demoshop` was created with 2,288 rows copied from the
   founding tenant. At ~9,400 steady-state rows per tenant (production post-F136 dedupe, 2026-08-22),
   100 tenants is ~940,000 rows across 33 text-heavy columns and 8 indexes. At an estimated
   300-700 bytes/row that is roughly 280-660 MB before indexes, against Supabase free tier's 500 MB.
   **This is an estimate from row counts, not a measurement** — S0 item 5. If it holds, the binding
   constraint at 100 tenants is **Supabase storage, not email**, reversing the standing assumption
   that MailerSend's 500/month cap was the near-term ceiling (formed at two tenants; email has since
   moved to Resend at 3,000/month). Supabase Pro is 8 GB at $25/month total — a line item at
   $39-50/tenant pricing, not a redesign. **Not this feature's problem, and not this feature's fix.**

---

## 9. Completion criteria

- [ ] S0 measured on both environments; § 2 confirmed or refuted; § 8's storage figure replaced with a real one
- [ ] Q1-Q3 answered by Rick and recorded in § 7
- [ ] S1 RPC applied to staging, verified by V2
- [ ] S2 merged to `staging` `--ff-only`; `settings.html` added to CLAUDE.md § Files That Must Stay in Sync in the same commit
- [ ] `aria-hidden` / `tabindex` removed from the gear (`app.js:539-540`)
- [ ] S3 seed applied to staging, V4 green there
- [ ] S4 merged to `staging`; V3, V5, V6, V7 green
- [ ] V8, V9 (147+ baseline), V10 green
- [ ] Production promotion: **separate, explicitly requested.** S1 RPC and S3 seed land on production
      **before** S4's client code (F105)
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
