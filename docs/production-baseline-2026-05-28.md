# Production Baseline — PULLLIST (pre-4.2)

**Environment:** Production Supabase project `plgegklqtdjxeglvyjte.supabase.co` (ref `plgegklqtdjxeglvyjte`)
**Last verified against live:** 2026-05-28 (Q1–Q8 schema audit + I2/I3 provenance)
**Author:** Phase 4.2 planning session
**Status:** Authoritative for the 4.2–4.6 cutover window

## Purpose

This document records the **actual live state of production** immediately before the Phase 4
cutover window, established by direct SQL queries against the production database — not from
memory, the parent plan, or prior reference docs.

It **supersedes** `pre-multitenancy-state.md` § 2 (schema) and § 4 (staging comparison), both
of which were flagged stale, and it **gates**:

- the 4.2 additive-schema SQL runbook, and
- the re-scope of 4.3 (constraints / view / RLS recursion) and 4.4 (RLS / functions / analytics
  views), which were written against the same now-disproven "production is a near-blank slate"
  premise.

> **Headline.** Production is **not** the 7-table pre-multitenancy snapshot the planning
> artifacts describe. It has **9 base tables**, all 6 views, and a full set of RLS policies.
> The only things genuinely missing for multi-tenancy are the `tenants` table and `tenant_id`
> columns. See [§ Findings](#findings-surfaced-by-this-audit).

---

## 1. Live object inventory

### 1.1 Base tables (9)

`app_settings`, `catalog`, `preorders`, `reservation_history`, `settings`, `subscriptions`,
`usage_events`, `user_profiles`, `weekly_shipment`.

**`tenants` is absent.** No `tenant_id` column exists on any table.

### 1.2 Views (6)

`admin_preorders`, `analytics_daily_events`, `analytics_top_cancelled`, `analytics_top_reserved`,
`analytics_top_subscribed`, `analytics_user_activity`.

- `admin_preorders` carries the **pre-Phase-1 definition** (plain joins, no tenant column, no
  `security_invoker`). Matches the documented expectation; recreation is 4.3 scope.
- All 5 analytics views exist and query `usage_events`. They are functional today — they are
  **not** "to be created" in 4.4 as the parent plan implies; they are "to be retrofitted with a
  tenant filter."

### 1.3 Functions (7)

`archive_stale_reservations`, `claim_paper_account`, `delete_dropped_catalog_items`,
`generate_invite_link`, `get_popular_series`, `is_admin`, `purge_stale_catalog`.

Absent vs post-Phase-3 staging: `current_tenant_id()`, `current_user_is_admin()`,
`purge_old_usage_events()`, `auto_fulfill_past_on_sale()`. Production uses **`is_admin()`**, not
staging's `current_user_is_admin()`. The three tenant-aware RPCs present here
(`archive_stale_reservations`, `delete_dropped_catalog_items`, `purge_stale_catalog`) are the
**old signatures** (no leading `p_tenant_id uuid`). All of this is 4.4 scope; recorded here for
the re-scope.

### 1.4 Row counts (pre-cutover snapshot)

| Table | Rows |
|---|---|
| `catalog` | 6399 |
| `preorders` | 680 |
| `weekly_shipment` | 443 |
| `usage_events` | 373 |
| `reservation_history` | 81 |
| `user_profiles` | 19 |
| `subscriptions` | 3 |
| `app_settings` | 2 |
| `settings` | 2 |

These are the backfill target counts for 4.2 (`tenant_id IS NULL` should equal the table row
count before backfill, and `0` after).

### 1.5 Founding admin

`734bfd7e-23a6-4c23-ba35-1f64843603c0` — "Book Stop", `is_admin = true`, `status = active`.
Confirmed present. This is the tie-point for the founding tenant row.

---

## 2. Per-table state vs post-Phase-3 staging

Every base table is **structurally identical to staging minus `tenant_id`** (and minus the
tenant FK / tenant index / tenant-aware unique key). No column-shape surprises.

| Table | `tenant_id` present? | Other deltas vs staging | 4.2 action | Deferred |
|---|---|---|---|---|
| `user_profiles` | No | — | add `tenant_id` + backfill + `idx_user_profiles_tenant` | FK + NOT NULL → 4.3 |
| `catalog` | No | unique key is `catalog_item_code_distributor_month_unique` (no tenant) | add `tenant_id` + backfill + `idx_catalog_tenant` | tenant-aware unique + FK + NOT NULL → 4.3 |
| `preorders` | No | unique `(user_id, catalog_id)` matches staging | add `tenant_id` + backfill + `idx_preorders_tenant` | FK + NOT NULL → 4.3 |
| `subscriptions` | No | unique `(user_id, series_name, distributor)` (no tenant) | add `tenant_id` + backfill + `idx_subscriptions_tenant` | tenant-aware unique + FK + NOT NULL → 4.3 |
| `reservation_history` | No | unique `(user_id, series_name, distributor, catalog_month)` matches staging | add `tenant_id` + backfill + `idx_reservation_history_tenant` | FK + NOT NULL → 4.3 |
| `weekly_shipment` | No | `item_code` already present; **only the Lunar unique index exists** (see PB4) | add `tenant_id` + backfill + `idx_weekly_shipment_tenant` | FK + NOT NULL → 4.3; PRH index → 4.5/4.6 |
| `settings` (legacy) | No | PK on `key` only | add `tenant_id` + backfill + `idx_settings_tenant` | FK + NOT NULL → 4.3 |
| `app_settings` | No | PK on `key` only (F6 collision risk unchanged); FK `updated_by → auth.users` | add `tenant_id` + backfill + `idx_app_settings_tenant` | FK + NOT NULL → 4.3 |
| `usage_events` | No | FKs `user_id → auth.users` / `catalog_id → catalog`, both `ON DELETE SET NULL` (matches staging) | add `tenant_id` + backfill + `idx_usage_events_tenant` | FK + NOT NULL → 4.3 |

**`tenants` (to create in 4.2):** mirror staging §4.1 — `id` PK `gen_random_uuid()`, `slug`
NOT NULL UNIQUE, `display_name` NOT NULL, `contact_email`/`contact_phone`/`location` nullable,
`plan` NOT NULL default `'free'`, `branding` jsonb default `'{}'`, `settings` jsonb default
`'{}'`, `created_at`/`updated_at` timestamptz default `now()`. **The `tenants_slug_format_check`
CHECK is 4.3 scope per parent plan line 143** — create `tenants` without it in 4.2.

### 2.1 Index/FK placement decision (confirmed 2026-05-28)

- **4.2 (additive, reversible by `DROP COLUMN` / `DROP INDEX`):** nullable `tenant_id` columns,
  backfill, and the nine `idx_*_tenant` indexes.
- **4.3 (constraints):** `tenant_id → tenants(id) ON DELETE CASCADE` FKs, `NOT NULL` promotion,
  tenant-aware unique keys on `catalog` and `subscriptions`, `tenants_slug_format_check`.

---

## 3. RLS policy inventory (live)

RLS is enabled and populated on production. Two admin-check styles coexist, neither
tenant-aware:

| Table | Policy | Cmd | Admin check style |
|---|---|---|---|
| `app_settings` | Admins can insert settings | INSERT | `is_admin()` |
| `app_settings` | Admins can update settings | UPDATE | `is_admin()` |
| `app_settings` | Anyone can read settings | SELECT | `auth.role() = 'authenticated'` |
| `catalog` | Admins can modify catalog | ALL | `is_admin()` |
| `catalog` | Logged in users can view catalog | SELECT | `auth.role() = 'authenticated'` |
| `preorders` | Admins can view all preorders | SELECT | `is_admin()` |
| `preorders` | Users can manage own preorders | ALL | `auth.uid() = user_id OR is_admin()` |
| `preorders` | admins update all preorders | UPDATE | **recursive `EXISTS` subquery** |
| `reservation_history` | admins view all history | SELECT | **recursive `EXISTS`** |
| `reservation_history` | users view own history | SELECT | `auth.uid() = user_id` |
| `settings` | admins update settings | UPDATE | **recursive `EXISTS`** |
| `settings` | authenticated users read settings | SELECT | `true` |
| `subscriptions` | admins view all subscriptions | SELECT | **recursive `EXISTS`** |
| `subscriptions` | users manage own subscriptions | ALL | `auth.uid() = user_id` |
| `usage_events` | admins read all events | SELECT | **recursive `EXISTS`** |
| `usage_events` | users insert own events | INSERT | `auth.uid() = user_id` (with_check) |
| `user_profiles` | Admins can manage profiles | ALL | `is_admin()` |
| `user_profiles` | Admins can view all profiles | SELECT | `is_admin()` |
| `user_profiles` | Users can view own profile | SELECT | `auth.uid() = id` |
| `user_profiles` | admins delete profiles | DELETE | **recursive `EXISTS`** |
| `user_profiles` | admins update all profiles | UPDATE | **recursive `EXISTS`** |
| `weekly_shipment` | authenticated users read weekly_shipment | SELECT | `true` |

No policy references `current_tenant_id()`. **None of this is touched in 4.2** (4.2 adds no
policies). It is recorded so 4.3/4.4 can be re-scoped against reality rather than the
"create policies from scratch" premise.

---

## 4. Findings surfaced by this audit

New observations are prefixed `PB` (production-baseline) to avoid collision with the
`technical-reference.md` § 13 `F`-series. Where a PB maps to a known staging `F`, it is noted.

#### PB1 — Production already has `app_settings`, `usage_events`, and the analytics stack (BLOCKING for 4.2 as written)
- `CLAUDE.md` line 19, parent-plan carry-forward item 9, parent-plan § In Scope line 142, and
  the 4.2 handoff all state production has **7 tables** and must **create** `app_settings` and
  `usage_events` in 4.2. Live shows **9 base tables** including both, with PKs, FKs, RLS
  policies, **373 `usage_events` rows**, **2 `app_settings` rows**, and all 5 analytics views
  built on `usage_events`.
- **Effect on 4.2:** the "create two tables" line item is deleted. Those two tables are handled
  exactly like the other seven — add `tenant_id` + backfill + index.
- **Doc correction required** (see § 5).

#### PB2 — Analytics views and `admin_preorders` already exist on production
- Parent plan line 148 frames 4.4 analytics-view work as "rebuilds" implying creation; all five
  exist and are functional. `admin_preorders` exists with the pre-Phase-1 definition.
- **Effect:** 4.4 becomes "retrofit existing views with `current_tenant_id()` filtering," not
  "create." `admin_preorders` recreation remains 4.3 as planned. Not a 4.2 change.

#### PB3 — Production uses `is_admin()`, not `current_user_is_admin()`; 7 policies use the recursive `EXISTS` anti-pattern
- Maps to staging F46 (single policy) but is **broader on prod**: the recursive
  `EXISTS (SELECT 1 FROM user_profiles WHERE id = auth.uid() AND is_admin = true)` pattern —
  the documented RLS-recursion footgun in `CLAUDE.md` § Known Issues — appears on **7 policies**
  across `preorders`, `reservation_history`, `settings`, `subscriptions`, `usage_events`, and
  `user_profiles` (×2).
- **Effect:** 4.3's recursion fix is larger than the single `preorders` policy the parent plan
  names, and must reconcile the `is_admin()` vs `current_user_is_admin()` naming. Need the body
  of `is_admin()` (does it self-reference `user_profiles`?) before finalizing 4.3. Not 4.2.

#### PB4 — `weekly_shipment` is missing the PRH partial unique index
- Live `weekly_shipment_unique = UNIQUE (distributor, upc, on_sale_date)` — the **Lunar** key
  only. The import script requires a second index for PRH:
  `UNIQUE (distributor, item_code, on_sale_date) WHERE item_code IS NOT NULL`. It is absent.
- **Effect:** the first real prod import (4.6 part 2) will fail or mis-upsert PRH shipment rows
  if any are present. **Carry into 4.5/4.6 scope.** Not 4.2.

#### PB5 — `claim_paper_account()` SQL function still present on production
- Dropped on staging in 4.1 (C3 / F33) as redundant. Still exists on prod. Cleanup is already a
  deferred/out-of-scope item; recorded for completeness. Not 4.2.

#### PB7 — Production founding slug is `rjbookstop` (diverges from staging `raysandjudys`) (CONFIRMED 2026-05-31)
- The prod `tenants` row was inserted in 4.2 with `slug = rjbookstop` (deliberate; confirmed at 4.3
  PF2). Staging uses `raysandjudys`. Both satisfy the `tenants_slug_format_check` added in 4.3 S5.
- **Phase 5 implication:** `TENANT_SLUG_MAP` in `app.js` and any `?t=<slug>` routing must use
  `rjbookstop` for the prod tenant, not `raysandjudys`. Non-blocking for 4.3–4.6 (single-tenant;
  slug routing only matters when a second tenant exists).

#### PB6 — Documentation under-counted production; not undocumented drift (RESOLVED 2026-05-28)
- Production carrying `app_settings`, `usage_events`, the analytics views, and a populated RLS
  policy set contradicts the "prod never received the Phase-1 deviation" narrative across every
  planning doc.
- **Investigation (I2/I3, § 6) resolves it:** the objects **predate** the 2026-04-29 snapshot.
  `app_settings` is among the oldest tables (OID 17684, adjacent to the original
  `catalog`/`user_profiles`/`preorders` cluster); `usage_events` has been collecting events
  since **2026-04-13**, 16 days before the snapshot. This is a **documentation-accuracy failure
  in the 2026-04-29 snapshot record**, not an undocumented mutation of production.
- **Why this is the good outcome:** nothing changed prod behind the docs. The live audit in this
  document is the complete, authoritative picture. The 4.2 SQL proceeds unblocked.
- **Residual risk:** 4.3 and 4.4 were written against the same under-counted premise and must be
  (re)scoped against this live baseline before their runbooks are drafted. They additionally
  require the body of `is_admin()` (PB3) and the bodies/signatures of the three old-signature
  RPCs (`archive_stale_reservations`, `delete_dropped_catalog_items`, `purge_stale_catalog`),
  fetched live when their turn comes — not needed for 4.2.

---

## 5. Doc corrections required (doc-only commit to `staging`)

Per `CLAUDE.md` § Document Integrity, contradictions are corrected, not worked around:

1. `CLAUDE.md` line 19 — the parenthetical "(§ 2/§ 4 superseded by `production-baseline-...`)"
   is now satisfied by this file; confirm the referenced filename matches the committed name.
2. `CLAUDE.md` — any "production has 7 tables" phrasing → "production has 9 base tables
   (`app_settings` and `usage_events` already present); only `tenants` and `tenant_id` columns
   are missing."
3. `phase-4-production-migration.md` § In Scope line 142 — rewrite from "create `app_settings`
   and `usage_events`" to "add `tenant_id` to all 9 existing tables (incl. `app_settings`,
   `usage_events`); both already exist on prod."
4. `phase-4-production-migration.md` carry-forward item 9 — mark resolved/corrected: the table
   gap does not exist; the real gap is `tenant_id` columns + `tenants`.
5. `phase-4-production-migration.md` § In Scope line 148 — note analytics views and
   `admin_preorders` already exist; 4.4 retrofits rather than creates.

---

## 6. Short provenance investigation (PB6 — to run, then record below)

Lightweight, read-only. Run in the prod SQL Editor; paste results under "Conclusion."

```sql
-- I1: Supabase migration ledger — did anything run post-snapshot?
SELECT version, name FROM supabase_migrations.schema_migrations ORDER BY version;

-- I2: object creation order via OID (lower OID = created earlier)
SELECT relname, relkind, oid
FROM pg_class
WHERE relnamespace = 'public'::regnamespace
  AND relkind IN ('r','v')
ORDER BY oid;

-- I3: when were the "surprise" tables first written to?
SELECT 'usage_events' AS t, min(created_at), max(created_at) FROM usage_events
UNION ALL SELECT 'app_settings', min(updated_at), max(updated_at) FROM app_settings;

-- I4: confirm the 2026-04-29 snapshot's recorded table list (compare to live Q1)
--     (cross-check against pre-multitenancy-state.md § 2 and the snapshot dump)
```

**What the outcomes mean:**
- If I1 shows migrations dated after 2026-04-29 → an out-of-band migration applied them;
  recover its SQL, confirm it matches staging, and the additive-baseline assumption holds.
- If I3 shows `usage_events` rows predating the snapshot → the "7-table" snapshot record itself
  was wrong, and `pre-multitenancy-state.md` § 2 needs a stronger correction than a pointer.
- Either outcome is non-blocking for the 4.2 *SQL* (the live audit fully determines it), but it
  is blocking for **trusting the 4.3/4.4 premises** without an equivalent live re-audit.

**Conclusion (2026-05-28, from I2 + I3):** The undocumented objects **predate the 2026-04-29
snapshot** — this is a snapshot/documentation accuracy failure, not production drift.

- **I2 (OID order):** `app_settings` (OID 17684) is adjacent to the original
  `catalog`/`user_profiles`/`preorders` cluster (17457–17488) — one of the oldest tables, older
  than `subscriptions` (42430), `reservation_history` (46949), `weekly_shipment` (55890), and
  `settings` (55910). `usage_events` (57112) and the five analytics views (57137–57153) are the
  newest contiguous block but are established schema, not recent additions.
- **I3 (write history):** `usage_events` first write **2026-04-13** — 16 days before the
  snapshot; 373 rows since. `app_settings`' `updated_at` of 2026-05-28 reflects the
  maintenance-mode / order-deadline rows being touched during this window's prep, consistent
  with it being an old table (last-write floor, not creation date).
- **I1 not returned;** no longer required. Data predating the snapshot is decisive without the
  migration ledger. I1 would only characterize the creation mechanism (CLI vs hand SQL) and is
  optional for the record.

**Effect on the program:** 4.2 is unblocked — the live audit fully determines its SQL. 4.3 and
4.4 inherit the same under-counted premise and must be re-scoped against this baseline + the
live `is_admin()` and RPC bodies (PB3, PB6 residual) when drafted.

---

## 7. Open pre-flight value confirmations (for the 4.2 plan)

1. **Production founding tenant slug + display_name.** Staging slug is `raysandjudys`. Confirm
   the prod founding row's `slug` (proposed `raysandjudys`) and `display_name` (proposed
   `Ray & Judy's Book Stop`; admin profile `full_name` is "Book Stop"). Slug must satisfy the
   4.3 format check `^[a-z0-9][a-z0-9-]*[a-z0-9]$`.
2. **Fresh prod UUID.** Generated Friday pre-flight, written to
   `scripts/phase-4-prod-tenant-uuid.txt` (gitignored). **Not** the staging UUID. The 4.2 SQL
   reads it from that file; its existence is a hard pre-flight gate.

---

## 8. Gate statement

This baseline is committed to `staging` before the 4.2 SQL runbook is written. The 4.2 runbook,
and the re-scoped 4.3/4.4 plans, are written **against this document and the live database**,
not against `pre-multitenancy-state.md` or the pre-audit parent-plan assumptions. If the live
database and this document disagree at execution time, the database wins and the window stops
for re-baseline.
