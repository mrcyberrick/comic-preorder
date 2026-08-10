# Technical Reference — PULLLIST

**Environment:** staging Supabase project `puoaiyezsreowpwxzxhj.supabase.co`
**Founding tenant UUID:** `72e29f67-39f7-42bc-a4d5-d6f992f9d790` (slug `raysandjudys`)
**Last verified:** **2026-07-28** — partial. § 4.2 (`app_settings` PK), § 4.10
(`weekly_shipment` unique index + distributor mapping), and § 13 statuses were
verified against the live production database and the live import scripts on
this date. **Every other section still dates to the post Phase 3.8 soak,
May 2026** and is two phases plus ~15 sub-deploys stale. Treat an unverified
section as a snapshot, not as authority: for production-touching work the live
database wins. Remaining stale claims are enumerated in § 13 **F92**, which
owns the full re-audit.

This document is the canonical schema and architecture reference for the
PULLLIST staging environment. Production diverges from staging until Phase 4
(production multi-tenancy migration); production-side state is out of scope
for this document.

> **Findings.** A discovery pass while writing this document surfaced 27
> findings — schema-level inconsistencies, dormant multi-tenancy bugs that
> activate when a second tenant onboards, and one active production-staging
> URL bug. They are listed in [Section 13](#13-findings--known-issues). Four
> are HIGH severity and one additional is dormant-HIGH; the HIGH set should
> be addressed before Phase 4.

---

## 1. Overview

PULLLIST is a comic pre-order system for independent bookstores. The staging
deployment serves a single founding tenant, Ray & Judy's Book Stop, with the
schema fully shaped for multi-tenancy after Phases 1, 2, and 3 (sub-deploys
3.1–3.8) of the migration program. **A second tenant is live:** `comicstore`
(`comicstore.pulllist.app`) was onboarded to production on **2026-07-15** at the
close of Phase 5.5, and is pilot/seeded — it holds no shipment rows and has not
run an import (verified 2026-07-28). The multi-tenancy plumbing is therefore
exercised by two tenants, though only the founding tenant carries real customer
traffic. *(Corrected 2026-07-28; this previously read "No second tenant exists
yet" — see § 13 F92.)*

The application is a static Cloudflare Pages site (vanilla HTML/CSS/JS, no build
step) that talks directly to a Supabase project. (Migrated from GitHub Pages in 5.1.
The legacy GH Pages surface is **still kept warm as a rollback target** — Rick's
call at 5.5 S6, 2026-07-15, was to keep it and revisit retirement in a future
session, so it is no longer tied to any phase boundary; the original "warm until
5.5 closes" framing is obsolete.) Eight Deno-based Supabase
Edge Functions handle email-sending and privileged operations that need the
service-role key. A local Node.js script imports monthly distributor catalogs
and weekly shipment invoices.

```
Browser (Cloudflare Pages — prod: pulllist.app / staging: staging.pulllist.pages.dev)
  ├── index.html         ← login + invite/recovery landing
  ├── catalog.html       ← browse and reserve monthly catalog
  ├── mylist.html        ← view and manage pull list
  ├── arrivals.html      ← this week's shipment + reserved arrivals
  ├── subscriptions.html ← series auto-reserve management
  ├── admin.html         ← admin dashboard (admins only)
  ├── analytics.html     ← admin analytics (admins only)
  ├── forgot-password.html ← password reset landing
  ├── app.js             ← shared logic; all Supabase API calls
  ├── style.css
  └── config.js          ← credentials (gitignored)
        │
        ▼
  Supabase staging (puoaiyezsreowpwxzxhj.supabase.co)
  ├── PostgreSQL (10 tables, 1 view, 9 functions)
  ├── Auth (email/password + invite + magic-link flows)
  ├── RLS (enabled on every public table)
  └── Edge Functions
        ├── notify-customers      ← monthly catalog notification
        ├── send-my-list          ← per-customer pull-list confirmation
        ├── invite-customer       ← admin-invited new account + email
        ├── register-customer     ← MailerLite webhook → pending account
        ├── approve-customer      ← admin approves pending → active
        ├── create-paper-customer ← admin creates walk-in placeholder
        ├── claim-paper-customer  ← merge paper account into real account
        └── reset-password        ← MailerSend-branded password reset

Local (runs each catalog cycle, never deployed)
  └── import-staging.js  ← Node — normalizes CSVs, upserts to Supabase
```

Tenant scoping flows through three independent mechanisms in lockstep:

1. **Database**: every tenant-scoped table has `tenant_id uuid NOT NULL` with
   `ON DELETE CASCADE` to `tenants.id`, and RLS policies that filter on
   `current_tenant_id()`.
2. **Web app** (`app.js`): the `TenantContext` module resolves the active
   tenant before any other API call. `app.js` writes pass `tenant_id`
   explicitly (Phase 3.2).
3. **Server-side helpers**: the import scripts load `TENANT_ID` from the
   scripts folder's gitignored `.env` (`IMPORT_TENANT_ID[_PROD]`), and hard-fail
   on a missing var or a `SUPABASE_URL` pointing at the wrong project;
   tenant-aware Edge Functions read `FOUNDING_TENANT_ID` from a Supabase secret.
   *(Corrected 2026-07-28 — this said the import script "hard-codes `TENANT_ID`
   to the founding tenant", true until the scripts were made credential-free on
   2026-07-08. See § 13 F92.)*

The mechanisms agree only by convention. The findings in
[Section 13](#13-findings--known-issues) include several places where one
mechanism diverges from the others.

---

## 2. Tech stack

| Layer | Technology |
|---|---|
| Frontend | Vanilla HTML/CSS/JS, no build step, served from Cloudflare Pages |
| Database | Supabase Postgres (15.x, with `pgcrypto`, `uuid-ossp`, `pg_stat_statements`, `supabase_vault`) |
| Auth | Supabase Auth (email/password, invite tokens, magic links, recovery tokens) |
| Edge Functions | Deno runtime on Supabase, hand-written TypeScript |
| Email | MailerSend (transactional) and MailerLite (subscriber webhooks) |
| Import | Node.js, run from local scripts folder, never committed |
| Hosting | Cloudflare Pages — prod: `https://pulllist.app/`; staging: `https://staging.pulllist.pages.dev/` (legacy GH Pages still warm as a rollback target, not tied to a phase gate — Rick's call 2026-07-15) |

`pgcrypto` provides `gen_random_uuid()` (used by newer tables); `uuid-ossp`
provides `uuid_generate_v4()` (used by `catalog` and `preorders`, predating
the move to `pgcrypto`). Both produce v4 UUIDs and are interchangeable for
this project's purposes; see finding F27.

`supabase_vault` is installed but no application code references it. The
`pg_stat_statements` extension is the standard Supabase performance-tracking
extension and is not used directly.

---

## 3. Multi-tenancy model

The schema treats every customer-facing table as tenant-scoped via a
`tenant_id uuid NOT NULL` column. The founding tenant on staging is
`72e29f67-39f7-42bc-a4d5-d6f992f9d790` (`raysandjudys`); on production it is
`20941129-c35a-476d-ae21-44b8f77af89c` (`rjbookstop`). **A second production
tenant, `comicstore`, has been onboarded** (2026-07-15, Phase 5.5) and is
pilot/seeded. *(Corrected 2026-07-28 — this previously read "no second tenant
has been onboarded" and named only the staging UUID while implying it was the
sole founding tenant. See § 13 F92.)*

### 3.1 Tenant resolution

**In the database**, two SECURITY DEFINER functions resolve the active
tenant and admin status from `auth.uid()`:

```sql
current_tenant_id()      → uuid     -- reads user_profiles.tenant_id
current_user_is_admin()  → boolean  -- reads user_profiles.is_admin
```

Both are `STABLE`, both `SET search_path = public`, both read the calling
user's profile row directly. RLS policies on tenant-scoped tables call
`current_tenant_id()` in their qual or with_check expressions to enforce
isolation.

**In the web app** (`app.js`), the `TenantContext` module resolves the
active tenant before any call that needs it. Resolution order:

1. Authenticated user's `user_profiles.tenant_id` (looked up on page load).
2. Subdomain — `<slug>.pulllist.app` via `tenantSlugFromHostname()` (5.2).
3. `?t=<slug>` query parameter (persisted to `sessionStorage` for the tab).
4. `sessionStorage` slug from earlier in the tab.
5. Founding tenant fallback.

Unauthenticated slug→id lookups go through the `resolve_tenant_by_slug`
SECURITY DEFINER RPC (5.2 S1; extended to 4 columns in 5.3), because the
`tenants` table is not readable by anon. The former hard-coded
`TENANT_SLUG_MAP` was **removed at 5.2 S6 (2026-06-15)**; the RPC is the sole
anon slug source and `FOUNDING_TENANT` (supplied per-branch by `config.js`)
is the only remaining hardcoded fallback.

`tenantSlugFromHostname()` returns `null` for every non-tenant host —
`pulllist.app`, `www.pulllist.app`, `localhost`, `127.0.0.1`, and **any**
`*.pages.dev` host — so those all fall through to the founding default.

**Front-door presentation (2026-07-21, `docs/apex-landing-tenant-subdomains.md`
S2) is a separate axis from resolution.** `index.html` branches on the same
host signal: a tenant subdomain renders the branded login; every other host
renders the apex front door — platform marketing plus a **universal**
sign-in that authenticates any tenant's customer into their own store via
the profile branch. This does **not** change resolution: the apex still
resolves to the founding tenant for anonymous visitors, and an authenticated
user always resolves to their own tenant by profile on any host. Cloudflare
Pages serves every hostname from one project, so the split is client-side
only — there is no per-host file.

**In the import script** (`import-staging.js`), tenant_id is a top-level
constant `TENANT_ID = '72e29f67-...'`. Catalog upserts, shipment upserts,
and auto-reserve inserts all carry this value explicitly. The three
tenant-aware SQL RPCs (`purge_stale_catalog`, `delete_dropped_catalog_items`,
`archive_stale_reservations`) all take `p_tenant_id uuid` as their first
argument.

**In the Edge Functions**, five of eight read `FOUNDING_TENANT_ID` from
Supabase secrets and use it for tenant filtering or for stamping new rows.
Three (`approve-customer`, `claim-paper-customer`, `reset-password`) do not
read tenant context at all; the first two perform admin-gated operations
without checking that the target user belongs to the admin's tenant
(see findings F33 and the cross-tenant aspect of F34's per-function notes).

### 3.2 Tenant-scoped vs global tables

Every public-schema table carries `tenant_id NOT NULL`:

```
tenants                ← root; id is the tenant_id everywhere else
user_profiles          ← tenant_id NOT NULL, CASCADE from tenants
catalog                ← tenant_id NOT NULL, CASCADE from tenants
preorders              ← tenant_id NOT NULL, CASCADE from tenants
subscriptions          ← tenant_id NOT NULL, CASCADE from tenants
reservation_history    ← tenant_id NOT NULL, CASCADE from tenants
usage_events           ← tenant_id NOT NULL, CASCADE from tenants
weekly_shipment        ← tenant_id NOT NULL, CASCADE from tenants
app_settings           ← tenant_id NOT NULL, CASCADE from tenants
settings               ← tenant_id NOT NULL, CASCADE from tenants (legacy)
```

Deleting a tenant cascades to every dependent row. There is no per-row
"global" or shared-across-tenants data in the public schema.

### 3.3 The `auth.users` ↔ `user_profiles` relationship

`user_profiles.id` is the same UUID as `auth.users.id`, and **a foreign key
enforces it**: `user_profiles_id_fkey`, `ON DELETE CASCADE`, present on both
environments (prod since before 2026-06-10; staging added 2026-06-11 under F64
item 7).

⚠️ **Corrected 2026-07-28.** This section previously asserted the opposite —
"**there is no foreign key between them**" — and justified it as *intentional*,
on the grounds that the paper-customer flow (`is_paper = true`) creates profiles
for walk-ins who never log in, with placeholder auth users sometimes deleted out
of order, so "a FK with CASCADE in either direction would break the
paper-customer flow." **That rationale is contradicted by the live schema**, which
has carried exactly such a CASCADE FK on production for months without breaking
the paper flow. Enforcement was proven on staging 2026-07-25 (insert with an
unmatched `id` → `23503`) while reproducing F95. Treat the old paragraph as
describing an intent that the schema does not implement; **do not restore it, and
do not use it as a reason to avoid adding FKs.** Whether the paper-customer flow
has a latent problem under CASCADE is a real question this correction does *not*
answer — see F92 and the `claim-paper-customer` note below.

Two implications:

- `auth.users` deletion **does** cascade to `user_profiles` via the FK above.
  The `claim-paper-customer` Edge Function nonetheless deletes both rows
  explicitly when merging a paper account into a real account — belt-and-braces
  now rather than the sole mechanism. *(Previously this bullet claimed deletion
  "does not automatically remove `user_profiles`", which followed from the
  no-FK premise and is wrong for the same reason.)*
- The `Preorders.getAll` admin query in `app.js` joins
  `auth_users:user_id ( email )` via PostgREST — this works because
  PostgREST infers the relationship from the by-convention UUID matching,
  but it is fragile (see F30).

### 3.4 RLS mental model & gotchas

Multi-tenancy correctness depends on every read-and-write path passing
through code that respects `current_tenant_id()`. Several patterns make
this easier to get wrong than expected. The list below is the mental model
to apply when reading or writing any new policy, function, or view:

**Pattern A — `qual = true` SELECT policy.** A SELECT policy with
`qual = true` and no other policies on the table returns every row to any
caller in the policy's `roles` set. Section 7's `weekly_shipment` policy is
exactly this shape (F15). Check: every SELECT policy on a tenant-scoped
table should have `qual` of the form `tenant_id = current_tenant_id()` or a
join that achieves the same.

**Pattern B — multiple PERMISSIVE policies OR together.** PostgreSQL
combines multiple PERMISSIVE policies on the same `cmd` with OR. If one
policy is properly tenant-scoped and another is not, the looser one wins.
The `preorders` admin policies (F16) demonstrate this: three admin-related
policies coexist; only one explicitly checks `tenant_id`. Check: if a table
has more than one ALL-or-write policy for the same role, every one must
either include the tenant check or be paired with a RESTRICTIVE policy that
does.

**Pattern C — SECURITY DEFINER functions bypass RLS entirely.** A function
declared `SECURITY DEFINER` runs with the function owner's privileges, so
RLS on referenced tables does not apply. If the function body does not
itself filter by `tenant_id` (or call `current_tenant_id()`), it reads
across all tenants. `get_popular_series()` is exactly this shape (F20):
DEFINER, queries `preorders JOIN catalog`, no tenant filter. Check: every
DEFINER function that reads tenant-scoped data must filter explicitly,
either via a `p_tenant_id` parameter or via `current_tenant_id()` in the
WHERE clause.

**Pattern D — views default to `security_invoker = false`.** A view created
without explicit `WITH (security_invoker = true)` runs with the view
owner's privileges (typically `postgres`), bypassing RLS on the underlying
tables. The view body then needs its own tenant filter, otherwise it leaks
across tenants. The `admin_preorders` view is shaped this way (F26),
though no application code currently queries it. Check: every public view
that joins tenant-scoped tables either needs `WITH (security_invoker =
true)` or its body needs an explicit `WHERE tenant_id = current_tenant_id()`.

**Pattern E — SECURITY DEFINER without `SET search_path` is a footgun.**
If a SECURITY DEFINER function does not pin its `search_path`, a malicious
caller can prepend a malicious schema and shadow the functions or tables
referenced in the body. Anthropic's hardening recommendation is
`SET search_path = public, pg_temp` for every DEFINER function. Several
functions in this project lack this pin (F23). Check: every new SECURITY
DEFINER function should include `SET search_path = public` in its
declaration.

These five patterns recur through this document's findings. They are not
exhaustive but cover what the discovery pass surfaced.

---

## 4. Tables

Eleven base tables in the `public` schema, on **both** environments as of 2026-08-03. Listed with `tenants` first as the
root of the cascade chain, then alphabetical. For each: purpose, columns
with types and nullability, constraints, foreign keys, indexes, and any
notable behavior.

### 4.1 `tenants`

Root of the multi-tenancy hierarchy. One row per tenant. Currently one row
exists (the founding tenant).

| Column | Type | Nullable | Default |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `slug` | text | NO | — |
| `display_name` | text | NO | — |
| `contact_email` | text | YES | — |
| `contact_phone` | text | YES | — |
| `location` | text | YES | — |
| `plan` | text | NO | `'free'` |
| `branding` | jsonb | YES | `'{}'::jsonb` |
| `settings` | jsonb | YES | `'{}'::jsonb` |
| `created_at` | timestamptz | YES | `now()` |
| `updated_at` | timestamptz | YES | `now()` |

**Constraints:**
- PK: `id`
- UNIQUE: `slug`
- CHECK `tenants_slug_format_check`: `slug ~ '^[a-z0-9][a-z0-9-]*[a-z0-9]$'` OR `slug ~ '^[a-z0-9]$'` (DNS-safe)

**Indexes:**
- `tenants_pkey` on `id`
- `tenants_slug_key` (unique) on `slug`
- ~~`idx_tenants_slug` on `slug`~~ — dropped on staging 2026-06-15 (F14 resolved); never existed on prod (F64 item 8 no-op — `tenants_slug_key` already serves the slug→id RPC)

**Notes:**
- Per-tenant `branding` jsonb is read by `Branding.apply()` (app.js) as of
  5.3 — an override layer applying `primary_color` / `display_name` / `logo_url`
  when present (founding `branding={}` ⇒ no-op ⇒ renders identically to today).
  Delivered to anon via `resolve_tenant_by_slug` (4-col) and to authed users via
  the `TenantContext` profile branch. `settings` jsonb remains reserved /
  never exposed (no client render path; never returned by the RPC).
- No INSERT or DELETE RLS policy: tenant creation is service-role-only.
  Authenticated users can SELECT only their own tenant; admins can UPDATE
  their own tenant.

### 4.2 `app_settings`

Canonical app-wide settings. Key/value with audit fields.

| Column | Type | Nullable | Default |
|---|---|---|---|
| `key` | text | NO | — |
| `value` | text | NO | — |
| `updated_at` | timestamptz | YES | `now()` |
| `updated_by` | uuid | YES | — |
| `tenant_id` | uuid | NO | — |

**Constraints:**
- PK: `(tenant_id, key)` — **both environments, verified by `pg_constraint`**
  (staging 2026-07-08, production 2026-07-28). F6 resolved. This section
  previously read "PK: `key` — see F6"; that was correct at authoring time and
  stale from 2026-07-08 onward.

**FKs:**
- `tenant_id` → `tenants.id` ON DELETE CASCADE

**Indexes:**
- `app_settings_pkey` on `(tenant_id, key)`
- `idx_app_settings_tenant` on `tenant_id` — **now redundant**, since the PK's
  leading column is `tenant_id` and serves the same lookups. Dropping it is a
  separate decision, deliberately not bundled into the F6 re-key; see
  `docs/sql/f6-app-settings-pk-rekey.sql` § OPTIONAL.

**Current keys in staging:**
- `maintenance_mode` — `'true'` / `'false'`; checked by `app.js`
  `Settings.isMaintenanceMode()`, redirects non-admin traffic to a holding
  page when on
- `order_deadline` — `'YYYY-MM-DD'` or empty; read by the catalog banner and
  by the `notify-customers` Edge Function for the email body

This is the table read and written by `app.js`'s `Settings` API. It is
**not** the same as the legacy `settings` table (4.8). See F4 for the
ongoing split.

### 4.3 `catalog`

Monthly distributor catalog items. The largest table by row count
(~7,200 rows in current staging).

| Column | Type | Nullable | Default |
|---|---|---|---|
| `id` | uuid | NO | `uuid_generate_v4()` |
| `distributor` | text | NO | — |
| `item_code` | text | NO | — |
| `alternate_code` | text | YES | — |
| `upc` | text | YES | — |
| `isbn` | text | YES | — |
| `title` | text | NO | — |
| `series_name` | text | YES | — |
| `series_number` | text | YES | — |
| `publisher` | text | YES | — |
| `imprint` | text | YES | — |
| `format` | text | YES | — |
| `comic_type` | text | YES | — |
| `variant_type` | text | YES | — |
| `variant_desc` | text | YES | — |
| `issue_number` | text | YES | — |
| `price_usd` | numeric | YES | — |
| `foc_date` | date | YES | — |
| `on_sale_date` | date | YES | — |
| `writer` | text | YES | — |
| `artist` | text | YES | — |
| `cover_artist` | text | YES | — |
| `description` | text | YES | — |
| `cover_url` | text | YES | — |
| `rating` | text | YES | — |
| `is_mature` | boolean | YES | `false` |
| `catalog_month` | text | NO | — |
| `created_at` | timestamptz | YES | `now()` |
| `tenant_id` | uuid | NO | — |

**Constraints:**
- PK: `id`
- UNIQUE `catalog_tenant_item_distributor_month_unique`: `(tenant_id, item_code, distributor, catalog_month)` — the upsert key for the import script

**FKs:**
- `tenant_id` → `tenants.id` ON DELETE CASCADE

**Indexes:**
- `catalog_pkey` on `id`
- `catalog_tenant_item_distributor_month_unique` (unique) on the four-column upsert key
- `idx_catalog_tenant` on `tenant_id`
- `idx_catalog_distributor` on `distributor`
- `idx_catalog_month` on `catalog_month`
- `idx_catalog_on_sale` on `on_sale_date`
- `idx_catalog_publisher` on `publisher`
- `idx_catalog_series` on `series_name`

**Notes:**
- `variant_type` distinguishes standard covers from variant covers. The
  app and import script treat NULL, `'Standard'` (Lunar), and
  `'Primary Title'` (PRH) as standard covers; everything else is a variant.
- `is_mature` is set by the import script's parsing of the Lunar `Mature`
  and `Adult` flags; PRH catalog rows always have `is_mature = false`.
- No INSERT/UPDATE/DELETE RLS policy: catalog mutations are
  service-role-only via the import script.

### 4.4 `preorders`

Customer reservations. Join row between a `user_profiles.id` and a
`catalog.id`.

| Column | Type | Nullable | Default |
|---|---|---|---|
| `id` | uuid | NO | `uuid_generate_v4()` |
| `user_id` | uuid | NO | — |
| `catalog_id` | uuid | NO | — |
| `created_at` | timestamptz | YES | `now()` |
| `notes` | text | YES | — |
| `quantity` | integer | NO | `1` |
| `fulfilled` | boolean | NO | `false` |
| `fulfilled_at` | timestamptz | YES | — |
| `tenant_id` | uuid | NO | — |

**Constraints:**
- PK: `id`
- UNIQUE: `(user_id, catalog_id)` — one reservation row per user per item

**FKs:**
- `user_id` → `user_profiles.id` ON DELETE NO ACTION (F10)
- `catalog_id` → `catalog.id` ON DELETE NO ACTION (F10)
- `tenant_id` → `tenants.id` ON DELETE CASCADE

**Indexes:**
- `preorders_pkey` on `id`
- `preorders_user_id_catalog_id_key` (unique) on `(user_id, catalog_id)`
- `idx_preorders_tenant` on `tenant_id`
- `idx_preorders_user` on `user_id`
- `idx_preorders_catalog` on `catalog_id`
- `preorders_fulfilled_idx` partial on `fulfilled` WHERE `fulfilled = false`

**Notes:**
- The `NO ACTION` delete behavior on `user_id` and `catalog_id` is what
  blocks naïve catalog row deletion: removing a `catalog` row referenced by
  any preorder fails, which is why `purge_stale_catalog()` filters
  `id NOT IN (SELECT catalog_id FROM preorders WHERE tenant_id = ...)`
  before deleting.
- `fulfilled` and `fulfilled_at` are set by admins via
  `Preorders.setFulfilled` and `Preorders.setFulfilledByCatalogId` (the
  latter marks every preorder for a catalog item at once, used when an
  entire title arrives). The partial index on `fulfilled = false` supports
  the admin's active-orders query.
- Phase 3.6 introduced automatic fulfillment: rows are marked
  `fulfilled = true` when `catalog.on_sale_date < CURRENT_DATE` via the
  `auto_fulfill_past_on_sale` function called from the weekly import.
  Manual fulfillment (pre-FOC rush orders) remains the exception path
  via `Preorders.setFulfilledByCatalogId()`.
- `Preorders.cancel` (app.js) refuses to delete fulfilled rows. The
  guard is a pre-DELETE row check plus a defensive
  `.eq('fulfilled', false)` filter on the DELETE itself. `mylist.html`
  hides the per-row Remove button for fulfilled rows, replacing it with
  an "✓ In hand" chip.

### 4.5 `reservation_history`

Append-only archive of past-month reservations. Populated by the
`archive_stale_reservations` SQL function during the import script's
new-month sequence.

| Column | Type | Nullable | Default |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `user_id` | uuid | YES | — |
| `series_name` | text | YES | — |
| `publisher` | text | YES | — |
| `distributor` | text | YES | — |
| `title` | text | YES | — |
| `catalog_month` | text | YES | — |
| `on_sale_date` | date | YES | — |
| `created_at` | timestamptz | YES | `now()` |
| `tenant_id` | uuid | NO | — |

**Constraints:**
- PK: `id`
- UNIQUE `reservation_history_user_series_month_unique`: `(user_id, series_name, distributor, catalog_month)` — see F7 (no `tenant_id` in the unique key; safe in practice but inconsistent)

**FKs:**
- `tenant_id` → `tenants.id` ON DELETE CASCADE
- `user_id` → `auth.users.id` ON DELETE CASCADE — see F13 (intent unclear; cascade defeats "preserve history past user deletion" if that was the goal)

**Indexes:**
- `reservation_history_pkey` on `id`
- `reservation_history_user_series_month_unique` (unique) on the four-column key
- `idx_reservation_history_tenant` on `tenant_id`

**Notes:**
- Read by `Recommendations._getUserSignal` in `app.js` to compute the
  user's series-affinity signal (along with current preorders) for the
  Tier 1 personalized recommendations on the catalog page.
- Has only SELECT policies (user-self and admin); inserts come exclusively
  through `archive_stale_reservations` called via service-role from the
  import script. See F24.

### 4.6 `settings` (legacy)

Older settings table that pre-dates `app_settings`. **Both tables are still
read by application code** — see F4. Treat `app_settings` as canonical
unless you specifically know you need `settings`.

| Column | Type | Nullable | Default |
|---|---|---|---|
| `key` | text | NO | — |
| `value` | text | YES | — |
| `tenant_id` | uuid | NO | — |

**Constraints:**
- PK: `key` — **still the original key-only shape.** F6 re-keyed `app_settings`
  to `(tenant_id, key)` on both environments (staging 2026-07-08, prod
  2026-07-28) but **deliberately excluded this table**, which is empty and dead
  (F4 emptied it; prod rows dropped 2026-05-31). Re-keying a dead table was
  judged pointless next to dropping it, and the drop is carried as a separate
  decision in `docs/sql/f6-app-settings-pk-rekey.sql` § OPTIONAL. So F6 reads
  "resolved" while this line still shows the old shape — that is intended, not
  drift. If this table is ever revived it must be re-keyed first.

**FKs:**
- `tenant_id` → `tenants.id` ON DELETE CASCADE

**Indexes:**
- `settings_pkey` on `key`
- `idx_settings_tenant` on `tenant_id`

**Current keys in staging:**
- `popular_series` — JSON array of admin-curated popular series, **read by
  `subscriptions.html`** to show the "Popular at Book Stop" panel to users
  with no subscriptions yet
- `maintenance_mode` — duplicated from `app_settings`, **not read by any
  code path**; orphan

**Notes:**
- RLS has only SELECT (authenticated, tenant-scoped) and UPDATE (admin) —
  no INSERT or DELETE policy. The `popular_series` row was inserted by a
  migration or by hand; there is no UI to edit it.
- The dynamic `get_popular_series()` SQL function (Section 6.4) computes
  popularity from preorder data; the static `popular_series` JSON is a
  separate admin-curated list. They serve different purposes despite the
  similar name.

### 4.7 `subscriptions`

Series-level auto-reserve subscriptions. The import script's auto-reserve
step inserts a `preorders` row for every active subscription whose series
appears in the new catalog month.

| Column | Type | Nullable | Default |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `user_id` | uuid | YES | — |
| `series_name` | text | NO | — |
| `distributor` | text | NO | — |
| `created_at` | timestamptz | YES | `now()` |
| `format` | text | YES | — |
| `tenant_id` | uuid | NO | — |

**Constraints:**
- PK: `id`
- UNIQUE `subscriptions_tenant_user_series_unique`: `(tenant_id, user_id, series_name, distributor)`

**FKs:**
- `user_id` → `user_profiles.id` ON DELETE CASCADE
- `tenant_id` → `tenants.id` ON DELETE CASCADE

**Indexes:**
- `subscriptions_pkey` on `id`
- `subscriptions_tenant_user_series_unique` (unique)
- `idx_subscriptions_tenant` on `tenant_id`

**Notes:**
- `user_id` is technically nullable but in practice never NULL because the
  FK is `ON DELETE CASCADE` (the row is deleted before user_id could
  become NULL).
- `format` is a recent addition. The import script's auto-reserve does an
  exact format match when `subscriptions.format` is set; for legacy or
  popular-series subscriptions where format is NULL, it falls back to
  `isComicFormat()` matching, which excludes Trade Paperbacks, Hardcovers,
  Omnibuses, Graphic Novels, Digests, Box Sets, and Albums.

### 4.8 `usage_events`

Fire-and-forget analytics event log. Events from `app.js`'s `UsageEvents`
helper, populated whenever a customer (not an admin, not an impersonated
session) takes a meaningful action.

| Column | Type | Nullable | Default |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `event_type` | text | NO | — |
| `user_id` | uuid | YES | — |
| `catalog_id` | uuid | YES | — |
| `metadata` | jsonb | YES | — |
| `created_at` | timestamptz | YES | `now()` |
| `tenant_id` | uuid | NO | — |

**Constraints:**
- PK: `id`

**FKs:**
- `user_id` → `auth.users.id` ON DELETE SET NULL
- `catalog_id` → `catalog.id` ON DELETE SET NULL
- `tenant_id` → `tenants.id` ON DELETE CASCADE

**Indexes:**
- `usage_events_pkey` on `id`
- `idx_usage_events_tenant` on `tenant_id`
- `usage_events_user_id_idx` on `user_id`
- `usage_events_catalog_id_idx` on `catalog_id`
- `usage_events_event_type_idx` on `event_type`
- `usage_events_created_at_idx` on `created_at DESC`

**Notes:**
- Event types currently emitted by `UsageEvents`: `reserve`, `cancel`,
  `subscribe`, `unsubscribe`, `catalog_view`, `page_view`, `login`,
  `logout`.
- RLS allows authenticated users to INSERT their own (with
  `tenant_id = current_tenant_id()`) and admins to SELECT their tenant's;
  no UPDATE or DELETE policy exists — events are append-only from the
  RLS perspective. The retention purge (see §6.6 — `purge_old_usage_events`)
  is the one sanctioned DELETE path and runs as `SECURITY DEFINER` via
  service-role from the import script.
- Admin-impersonated sessions skip event logging entirely
  (`AdminContext.isActive()` short-circuits `_log()`).

### 4.9 `user_profiles`

Per-user profile row. `id` matches `auth.users.id` and **is enforced by FK**
(`user_profiles_id_fkey`, `ON DELETE CASCADE`). *(Corrected 2026-07-28; this
said "by convention but is not enforced by FK" — see the FKs block below and
§ 13 F92.)*

| Column | Type | Nullable | Default |
|---|---|---|---|
| `id` | uuid | NO | — |
| `full_name` | text | NO | — |
| `is_admin` | boolean | YES | `false` |
| `created_by_admin` | boolean | YES | `true` |
| `notes` | text | YES | — |
| `created_at` | timestamptz | YES | `now()` |
| `status` | text | NO | `'active'` |
| `email` | text | YES | — |
| `has_seen_welcome` | boolean | YES | `false` |
| `is_paper` | boolean | YES | `false` |
| `tenant_id` | uuid | NO | — |

**Constraints:**
- PK: `id`
- CHECK `user_profiles_status_check`: `status IN ('active', 'pending', 'suspended')`

**FKs:**
- `tenant_id` → `tenants.id` ON DELETE CASCADE
- `id` → `auth.users.id` ON DELETE CASCADE (`user_profiles_id_fkey`) — **present
  and enforced on both environments.** Production has carried it since before
  the 2026-06-10 `pg_dump` comparison; staging gained it 2026-06-11 under F64
  item 7 (44 orphaned Playwright fixture rows were deleted first; verified
  `confdeltype = c`). Enforcement re-confirmed on staging 2026-07-25 while
  reproducing F95 — an insert with an `id` absent from `auth.users` is rejected
  with `23503`. *(Corrected 2026-07-28; this entry previously read "(No FK to
  `auth.users` — see Section 3.3)". See § 13 F92.)*

**Indexes:**
- `user_profiles_pkey` on `id`
- `idx_user_profiles_tenant` on `tenant_id`

**Notes:**
- `status` drives the invite/approval state machine. `register-customer`
  (called by MailerLite webhook) creates rows with `status = 'pending'`;
  `approve-customer` flips them to `'active'`; admin Suspend flips to
  `'suspended'`.
- `is_paper = true` marks placeholder profiles for walk-in customers who
  never log in. Used by `claim-paper-customer` to validate the merge
  source.
- `is_admin` is read directly by `current_user_is_admin()`, by
  `Auth.requireAdmin`, and by every Edge Function that needs an admin
  check.
- `email` is denormalized from `auth.users.email` (F25). No trigger keeps
  it in sync; population happens at registration time only.
- `has_seen_welcome` gates the first-login welcome modal in `app.js`
  (`WelcomeModal`). Dual-guarded with localStorage so the modal can't
  reappear before the DB write commits.

### 4.10 `weekly_shipment`

Per-shipment row representing one title arriving at the store on a given
on-sale date. Populated by the import script's optional shipment import
step (Format A delivery invoice or Format B code invoice).

| Column | Type | Nullable | Default |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `distributor` | text | NO | — |
| `item_code` | text | YES | — |
| `upc` | text | YES | — |
| `catalog_id` | uuid | YES | — |
| `title` | text | NO | — |
| `price_usd` | numeric | YES | — |
| `quantity` | integer | NO | `1` |
| `on_sale_date` | date | NO | — |
| `created_at` | timestamptz | NO | `now()` |
| `cover_url` | text | YES | — |
| `tenant_id` | uuid | NO | — |

**Constraints:**
- PK: `id`
- UNIQUE `weekly_shipment_tenant_unique`: `(tenant_id, distributor, upc, on_sale_date)` — **F9 resolved 2026-07-28 on both environments.** This is a plain unique **index**, not a table constraint; the object it replaced (`weekly_shipment_unique`, `(distributor, upc, on_sale_date)`) *was* a UNIQUE constraint, which is why removing it required `ALTER TABLE … DROP CONSTRAINT` rather than `DROP INDEX`. `pg_indexes` renders both kinds identically, so check `pg_constraint` before assuming. Verified post-drop on prod and staging: 0 unique constraints, 1 `weekly_shipment_tenant_unique`.

**FKs:**
- `tenant_id` → `tenants.id` ON DELETE CASCADE
- `catalog_id` → `catalog.id` ON DELETE SET NULL

**Indexes:**
- `weekly_shipment_pkey` on `id`
- `weekly_shipment_tenant_unique` (unique) on `(tenant_id, distributor, upc, on_sale_date)` — used by the Format A `on_conflict`
- `idx_weekly_shipment_tenant` on `tenant_id`
- `weekly_shipment_on_sale_date_idx` on `on_sale_date`

**Notes:**
- Either `item_code` or `upc` carries the catalog join key, not both.
  Format A (PRH delivery invoice) populates `upc` from the ISBN column;
  Format B (Lunar/PRH code invoice) populates `item_code` from the Code
  column. **Format A maps to `distributor = 'PRH'`, Format B to
  `distributor = 'Lunar'`** — i.e. the label now matches the distributor
  that issued the invoice.
- ⚠️ **Corrected 2026-07-28. This bullet previously stated the mapping the
  other way round** ("Format A maps to `Lunar`, Format B to `PRH`", with a
  parenthetical noting it was "opposite to which distributor issued the
  invoice"). That described **pre-F84** behavior. **F84 fixed the inversion
  at the source on 2026-07-09** (scripts repo `01a90b6`) and this section was
  never updated, so the canonical schema reference has carried a backwards
  `distributor` mapping for ~3 weeks. Anyone filtering
  `weekly_shipment.distributor` from this doc would have selected the wrong
  rows. **Verified against the live parsers 2026-07-28:** `import.js:262-269`
  (Format A, `distributor: 'PRH'`) and `import.js:296-301` (Format B,
  `distributor: 'Lunar'`); the doc-comment block at `import.js:228-247`
  agrees. Found while investigating F9, not by a targeted audit — see F92.
- **Related naming trap (code, not schema):** `import.js`'s
  `buildLunarShipmentRows` / `buildPrhShipmentRows` helpers and its
  `lunarRows` / `prhRows` variables are still named for the **pre-F84**
  mapping, so they read as inverted relative to the `distributor` values
  their rows actually carry. The behavior is correct — every `on_conflict`
  key and filter matches the real value — but do not "correct" those names
  or the `distributor=eq.Lunar` DELETE without re-reading the parsers. See
  F9 for the full check.
- `catalog_id` is nullable because the import script upserts shipment rows
  even when no catalog match is found. Unmatched rows still display on
  arrivals.html using the invoice's title and cover-URL fallbacks.
- The import script's PRH path uses **delete-then-insert** (not upsert)
  for items keyed by `item_code` because PostgREST's `on_conflict` doesn't
  support partial indexes. The Lunar path uses standard upsert on the
  full unique index.
- **F15: the SELECT RLS policy is `qual = true`.** Any authenticated user
  can read every row regardless of `tenant_id`. Currently dormant under
  one tenant.


### 4.11 `order_submissions`

Append-only ledger of what the store has actually submitted to a
distributor. Added 2026-08-03 by the F101/F102 order-export session
(`docs/sql/order-submissions.sql`). **Live on staging and production**
(production created 2026-08-03 and seeded with 857 rows of real May/June/July
order history — `docs/sql/order-submissions-backfill-PROD.sql`).

**Numbering note:** this table is 4.11 rather than slotting in
alphabetically between `catalog` and `preorders`, deliberately — renumbering
4.4–4.10 would break every existing `§ 4.x` cross-reference in this document
and in the plan docs. The § 4 preamble's "then alphabetical" describes the
original ten tables.

| Column | Type | Nullable | Default |
|---|---|---|---|
| `id` | uuid | NO | `uuid_generate_v4()` |
| `tenant_id` | uuid | NO | — |
| `distributor` | text | NO | — |
| `order_code` | text | NO | — |
| `item_code` | text | YES | — |
| `title` | text | YES | — |
| `quantity` | integer | NO | — |
| `order_type` | text | NO | — |
| `foc_date` | date | YES | — |
| `catalog_month` | text | YES | — |
| `submitted_on` | date | NO | — |
| `created_at` | timestamptz | YES | `now()` |

**Constraints:**
- PK: `id`
- CHECK `order_submissions_distributor_check`: `distributor = ANY (ARRAY['Lunar', 'PRH'])`
- CHECK `order_submissions_order_type_check`: `order_type = ANY (ARRAY['monthly', 'adhoc'])`
- CHECK `order_submissions_quantity_check`: `quantity >= 1`
- **No unique constraint on `order_code`** — deliberate. Re-ordering a code is
  legitimate (a customer may reserve after an order has gone out). The ledger
  records history; the *export* reasons over it.

**FKs:**
- `tenant_id` → `tenants.id` ON DELETE CASCADE

**Indexes:**
- `order_submissions_pkey` on `id`
- `idx_order_submissions_lookup` on `(tenant_id, distributor, order_code)` — the duplicate-check lookup
- `idx_order_submissions_submitted` on `(tenant_id, submitted_on)` — reading a cycle back

**Notes:**
- **`order_code` is the distributor code, and that is the whole point.**
  `preorders.fulfilled` could not serve as an order record because it is keyed
  on `catalog_id`, which does not survive a re-listing (a title re-solicited in
  a later month gets a new `catalog` row under the four-column upsert key,
  § 4.3, and new `preorders` rows that start unmarked). The distributor code is
  what stayed constant across `2026-05`/`-06`/`-07` in F102's live instance.
  `order_code` mirrors the export's own fallback chain — PRH `isbn || item_code
  || upc`, Lunar `item_code || upc || isbn` — via `exportCode()` in `app.js`.
- **Written manually**, from the By Distributor tab's "Mark Ordered" action,
  *after* an order is placed. Not written on export click: generating a file is
  not proof of submission. F108's invoice ingest is designed to populate the
  same table automatically later.
- `title` / `foc_date` / `catalog_month` are **descriptive only** — no code
  reads them for logic. The duplicate check and the backorder-risk panel both
  match on `order_code` alone. This is why the staging backfill's 708 NULL
  titles (§ 13 F102) are cosmetic rather than a defect — the production
  backfill, regenerated with a paginated catalog lookup, has none.
- Append-only: no UPDATE or DELETE policy, matching `reservation_history`'s
  posture. Corrections are service-role SQL, not an app path.
- Customer-facing reads go through the `get_ordered_codes()` RPC (§ 6.8), never
  directly — RLS here is admin-only.
---

## 5. Views

### 5.1 `admin_preorders`

Three-way join over `preorders`, `user_profiles`, and `catalog`,
denormalized for an admin dashboard layout. **No application code
currently queries this view.**

```sql
CREATE VIEW admin_preorders AS
  SELECT
    p.id AS preorder_id,
    p.tenant_id,
    p.created_at AS reserved_at,
    p.quantity,
    p.notes AS customer_notes,
    up.full_name AS customer_name,
    c.distributor, c.item_code, c.title, c.series_name, c.publisher,
    c.format, c.issue_number, c.price_usd,
    c.price_usd * p.quantity AS line_total,
    c.foc_date, c.on_sale_date, c.catalog_month, c.cover_url
  FROM preorders p
    JOIN user_profiles up ON up.id = p.user_id
    JOIN catalog c ON c.id = p.catalog_id
  ORDER BY up.full_name, c.on_sale_date;
```

`admin.html`'s loadData function builds the equivalent join client-side
using direct `preorders` and `user_profiles` queries; the view is
dead code at the application layer.

The view's `reloptions` is `null`, meaning it runs with the view owner's
privileges (`security_invoker = false` default). Combined with no
WHERE clause filtering by tenant, the view bypasses RLS on the three
underlying tables and would return rows from every tenant if queried.
Currently dormant on two axes: no caller, and only one tenant exists. See
F26.

---

## 6. Database functions

Nine functions in the `public` schema, on **both** environments as of 2026-08-03. Listed by category with signature,
security mode, and purpose.

### 6.1 Auth helpers

#### `current_tenant_id() → uuid`

```
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
```

Returns the calling user's tenant_id by reading
`user_profiles.tenant_id WHERE id = auth.uid()`. Called from RLS policies
across every tenant-scoped table.

#### `current_user_is_admin() → boolean`

```
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
```

Returns the calling user's is_admin flag (defaulting to false) by reading
`user_profiles WHERE id = auth.uid()`. Called from RLS policies on
`preorders`, `subscriptions`, `app_settings`, `usage_events`, and others.

#### `is_admin() → boolean`

```
LANGUAGE sql SECURITY DEFINER  -- no STABLE, no SET search_path
```

Functionally equivalent to `current_user_is_admin()` but worse: not
declared `STABLE` (can't be cached within a statement) and lacks
`SET search_path` hardening. **Not referenced by any RLS policy.** Dead
duplicate; see F19.

### 6.2 Catalog management (called by import script)

#### `purge_stale_catalog(p_tenant_id uuid, cutoff_date date, current_month text) → integer`

```
LANGUAGE plpgsql SECURITY DEFINER
```

Deletes catalog rows from previous months whose `on_sale_date < cutoff_date`
and which are not referenced by any preorder in the same tenant. Returns
the row count deleted. Called by the import script when a new catalog
month is detected.

The `id NOT IN (SELECT catalog_id FROM preorders WHERE tenant_id = p_tenant_id)`
subquery is the careful piece: without the tenant filter on the subquery,
a preorder in tenant B referencing the same catalog row would block
deletion in tenant A. Currently moot, but the function is correctly shaped
for multi-tenancy.

#### `delete_dropped_catalog_items(p_tenant_id uuid, p_catalog_month text, p_item_codes text[]) → integer`

```
LANGUAGE plpgsql SECURITY DEFINER
```

Removes items from `catalog` for the given tenant and month that are not
in the provided item_codes array. Used by the import script to drop
titles that have disappeared from this month's distributor catalog
between imports.

### 6.3 History archival

#### `archive_stale_reservations(p_tenant_id uuid, cutoff_date date, current_month text) → integer`

```
LANGUAGE plpgsql SECURITY INVOKER
```

Inserts deduplicated rows into `reservation_history` from the join of
`preorders` and `catalog` for the given tenant, where the catalog month is
not the current month and on_sale_date is before the cutoff. Called by
the import script before `purge_stale_catalog` so historical signal
survives the catalog purge.

INVOKER security model means it runs with the caller's privileges.
`reservation_history` has only SELECT policies (not INSERT), so this
function only succeeds when called by service-role (which bypasses RLS).
See F24.

### 6.4 Analytics

#### `get_popular_series(p_catalog_month text) → TABLE(series_name text, distributor text, reservation_count bigint)`

```
LANGUAGE sql STABLE SECURITY DEFINER  -- no SET search_path
```

Returns series ordered by reservation count for the given catalog month,
computed dynamically from `preorders JOIN catalog`. Two callers:
`admin.html`'s Top Series tab, and `app.js`'s
`Recommendations._getPopularSeries` (used to populate the Tier 2 popular
section of every customer's catalog page).

**No tenant filter in the body.** SECURITY DEFINER bypasses RLS, and the
WHERE clause filters only on `c.catalog_month = p_catalog_month`. Returns
counts unioned across every tenant. See F20 — dormant under one tenant,
becomes a customer-facing cross-tenant analytics leak when tenant 2
onboards.

### 6.5 Retention

#### `purge_old_usage_events(p_tenant_id uuid, p_retention_days integer) → integer`

```
LANGUAGE sql SECURITY DEFINER  SET search_path = public
```

Hard-deletes rows from `usage_events` where `tenant_id = p_tenant_id`
and `created_at < now() - make_interval(days => p_retention_days)`.
Returns the count of deleted rows.

**Caller:** `import-staging.js` Step 8, invoked at the end of every
import run with `TENANT_ID` and `90`. Failure is logged but non-fatal —
the import completes regardless.

**Grants:** EXECUTE granted only to `service_role`; REVOKE ALL FROM
PUBLIC plus explicit REVOKE from `anon` and `authenticated` (Supabase
auto-grants those on function creation). No customer code path can invoke
this function.

**Source:** `docs/sql/purge_old_usage_events.sql`.

### 6.6 Operational

#### `auto_fulfill_past_on_sale(p_tenant_id uuid) → integer`

Per-tenant operational function. Sets `fulfilled = true, fulfilled_at = now()`
on every `preorders` row that belongs to the given tenant, has
`fulfilled = false`, and whose joined `catalog.on_sale_date < CURRENT_DATE`.
Returns the count of rows updated.

- Mode: `SECURITY DEFINER`, `SET search_path = public`
- Grants: `EXECUTE` to `service_role` only
- Called by: `import-staging.js` end-of-run (one call per weekly invocation)
- Idempotent: a subsequent invocation with no new past-on-sale rows returns 0.
- The manual fulfill path via `Preorders.setFulfilledByCatalogId()` is
  unaffected — rows already marked fulfilled are left alone by the
  `fulfilled = false` filter in the WHERE clause.

**Source:** `docs/sql/auto_fulfill_past_on_sale.sql`.

### 6.7 Account merge (unused)

#### `claim_paper_account(paper_user_id uuid, real_user_id uuid) → void`

```
LANGUAGE plpgsql SECURITY INVOKER
```

Re-points all `preorders` and `subscriptions` from a paper account to a
real account, then deletes the paper user_profiles and auth.users rows.

**Not called by any application code.** The `claim-paper-customer` Edge
Function reimplements this logic in TypeScript via REST. See F33.

The function lacks defensive checks (no verification that
`paper_user_id` is actually `is_paper = true`, no tenant scoping, etc.)
and depends on the caller having `auth.users` DELETE rights, which means
it only succeeds when called via service-role. See F21.


### 6.8 Order ledger

#### `get_ordered_codes() → TABLE(distributor text, order_code text)`

```
LANGUAGE sql STABLE SECURITY DEFINER  SET search_path = public
```

Returns the DISTINCT `(distributor, order_code)` pairs in
`order_submissions` (§ 4.11) for the caller's own tenant. Added 2026-08-03
by the F101/F102 session (`docs/sql/get-ordered-codes-rpc.sql`). **Live on
staging and production** (production created 2026-08-03; `anon` confirmed
revoked there with `42501 permission denied for function`, and a real
authenticated non-admin session confirmed returning correct tenant-scoped
codes).

**Why it exists:** `order_submissions` RLS is admin-only, but My List needs
the "Order placed" status for ordinary customers. This function exposes the
one fact they need — *which codes are on order* — and nothing else: no
quantities, no submission dates, no titles. The full ledger stays admin-only.

**Tenant scope is derived internally** from `current_tenant_id()`, never from
a client-supplied parameter — the same pattern as every other RLS-adjacent
function here. For an anon caller `current_tenant_id()` is NULL, so the
result is empty.

**Grants:** `EXECUTE` to `authenticated`; `REVOKE ALL` from `PUBLIC` and
`anon`.

**Callers:** `app.js` `getOrderedCodes()` → `mylist.html` (drives the
"✓ Order placed" chip and its qty/cancel lock) and `Preorders.cancel()`
(refuses to cancel a code with a ledger row — see F109 for the limits of
that guard).

**Note when testing:** running `SELECT count(*) FROM get_ordered_codes()` in
the Supabase SQL Editor returns **0** even when the table is full. That is
correct, not a fault — the editor runs as `postgres` with no `auth.uid()`,
so `current_tenant_id()` is NULL. Verify with a real authenticated session
against PostgREST instead.
---

## 7. Row-level security

Every public-schema table has `rls_enabled = true` and
`rls_forced = false`. Service-role bypasses RLS (Supabase's default
behavior), which is how the import script and Edge Functions perform
privileged operations. The web app uses the anon key with the
authenticated session, which goes through RLS.

**Read [Section 3.4](#34-rls-mental-model--gotchas) before touching any
policy.** The patterns there explain why several tables in this section
have findings.

### 7.1 Per-table policy summary

#### `tenants`
- `users read own tenant` — SELECT, authenticated, where `id = current_tenant_id()`
- `admins update own tenant` — UPDATE, where `id = current_tenant_id() AND current_user_is_admin()`
- No INSERT or DELETE policy. Tenant creation is service-role-only.

#### `user_profiles`
- `users view own profile` — SELECT where `auth.uid() = id`
- `users update own profile` — UPDATE where `auth.uid() = id`
- `admins view tenant profiles` — SELECT where `tenant_id = current_tenant_id() AND current_user_is_admin()`
- `admins manage tenant profiles` — **ALL**, `TO authenticated`. Added to staging
  2026-06-11 (Phase 5.0 S3) to reach prod parity; production already had it. This
  is what makes admin-side Decline (`Users.deleteProfile`) and Pause
  (`Users.suspend`, `status = 'suspended'`) work from a browser session.

⚠️ **Corrected 2026-08-09.** This block previously listed only the three policies
above and asserted *"No INSERT or DELETE policy. Profile creation/deletion goes
through service-role (Edge Functions)."* That is **wrong for admins** and had been
since 5.0 S3 — the same session whose own § 13 entry records creating the ALL
policy, so the two halves of this document disagreed for two months.

**Verified by execution on staging 2026-08-09**, with the anon key and a real
admin JWT and **no service key in the request path**: `SELECT` over all tenant
profiles returned **200 / 25 rows**; `PATCH status='suspended'` on another user
returned **200** and persisted; `PATCH status='active'` restored it. Probe
fixtures torn down, 0 rows remaining.

Profile **creation** via Edge Function remains accurate — `create-paper-customer`
and `invite-customer` need service role to make the `auth.users` row, which no
client key can do. It is the *no admin write path* claim that was false. Instance
of **F92**; corrected here rather than filed as a new ID.

#### `catalog`
- `users read tenant catalog` — SELECT, authenticated, where `tenant_id = current_tenant_id()`
- No INSERT/UPDATE/DELETE policies. Catalog mutations are service-role-only.

#### `preorders` (4 policies; see F16)
- `users manage own preorders` — ALL where `auth.uid() = user_id AND tenant_id = current_tenant_id()`
- `admins manage tenant preorders` — ALL where `tenant_id = current_tenant_id() AND <user_profiles is_admin check>`
- `admins write tenant preorders` — ALL where `<user_profiles is_admin AND tenant_id = current_tenant_id()>` (note: tenant check is on the admin's profile, not the row being written)
- `admins view tenant preorders` — SELECT, redundant with the two ALL policies above

The "admins write" policy lacks a row-level tenant check. Because
PERMISSIVE policies OR together, the looser policy effectively allows
cross-tenant writes — see F16.

#### `subscriptions`
- `users manage own subscriptions` — ALL where `auth.uid() = user_id AND tenant_id = current_tenant_id()`
- `admins view tenant subscriptions` — SELECT where `tenant_id = current_tenant_id() AND current_user_is_admin()`
- No admin write policy. Subscriptions are user-managed only; admins use
  impersonation (`AdminContext`) to manage on behalf of users.

#### `reservation_history` (see F17)
- `users view own history` — SELECT where `auth.uid() = user_id`
- `admins view all history` — SELECT where `current_user_is_admin()`
- No INSERT/UPDATE/DELETE policies. Inserts come exclusively through
  `archive_stale_reservations` called via service-role.

Neither policy includes a tenant filter. The user policy is safe in
practice (a user's own history can only be from the user's tenant); the
admin policy allows cross-tenant SELECT. See F17.

#### `usage_events`
- `users insert own usage events` — INSERT with check `tenant_id = current_tenant_id()`
- `admins read tenant usage events` — SELECT where `tenant_id = current_tenant_id() AND current_user_is_admin()`
- No UPDATE/DELETE policies. Events are append-only.

#### `app_settings`
- `users read tenant app_settings` — SELECT, authenticated, where `tenant_id = current_tenant_id()`
- `admins insert tenant app_settings` — INSERT with check
- `admins update tenant app_settings` — UPDATE
- `admins delete tenant app_settings` — DELETE
  — All three admin policies properly check `tenant_id = current_tenant_id() AND current_user_is_admin()`.

#### `settings` (legacy)
- `users read tenant settings` — SELECT, authenticated, where `tenant_id = current_tenant_id()`
- `admins update tenant settings` — UPDATE where `tenant_id = current_tenant_id() AND current_user_is_admin()`
- No INSERT or DELETE policy. The fewer-policy footprint compared to
  `app_settings` is consistent with `settings` being the legacy
  half-migrated table (F4).

#### `weekly_shipment` (see F15)
- `authenticated users read weekly_shipment` — SELECT, authenticated, **`qual = true`**

The only policy. `qual = true` means every authenticated user reads every
row, regardless of tenant. **F15 — confirmed cross-tenant SELECT leak**,
dormant only because there is one tenant. The arrivals.html caller relies
on RLS to scope, and RLS doesn't scope here.

#### `order_submissions`
- `admins read tenant order_submissions` — SELECT, authenticated, where `tenant_id = current_tenant_id() AND current_user_is_admin()`
- `admins insert tenant order_submissions` — INSERT, authenticated, with check `tenant_id = current_tenant_id() AND current_user_is_admin()`

No UPDATE or DELETE policy — the ledger is append-only (§ 4.11). Both
policies carry an explicit `TO authenticated` rather than defaulting to
`public`, which is the shape phase-5.0 S2 had to backfill onto several older
policies; written that way here from the start.

Customer-facing access is deliberately **not** via these policies — the
`get_ordered_codes()` SECURITY DEFINER RPC (§ 6.8) exposes the minimum
subset non-admins need. **Verified by simulated-role test, not by
inspection** (2026-08-03): a real non-admin session sees 0 rows and is
refused INSERT; a second tenant's admin sees 0 rows and cannot INSERT even
when supplying the founding tenant's `tenant_id` explicitly; both positive
controls (founding admin reads own row, tenant-B admin inserts into own
tenant) pass. The SQL Editor bypasses RLS as superuser, so a plain SELECT
there proves nothing.

### 7.2 What the policies don't cover

INSERT/UPDATE/DELETE on tables with no write policy is locked entirely to
service-role. This is the intended behavior for `catalog`,
`weekly_shipment`, and most state-changing operations on `user_profiles`.
The pattern keeps customer-driven mutations narrow (preorders,
subscriptions, own profile updates, own usage_events inserts) and forces
everything else through audited Edge Functions.

---

## 8. Indexes

Every tenant-scoped table has a non-unique `idx_<table>_tenant` index on
`tenant_id`. Other indexes are listed inline in [Section 4](#4-tables);
this section only collects cross-cutting observations.

**Performance-shaped indexes worth knowing about:**
- `catalog`: separate indexes on `distributor`, `catalog_month`,
  `on_sale_date`, `publisher`, `series_name` — supports the catalog browse
  filters without compound index management
- `preorders`: partial index on `fulfilled` WHERE `fulfilled = false` —
  supports the admin's active-reservations queries
- `usage_events`: indexes on `user_id`, `catalog_id`, `event_type`, and
  `created_at DESC` — supports the analytics-shaped queries the analytics
  page presumably runs
- `weekly_shipment`: `on_sale_date` index supports the This Week page

**Convention:** every table that has a tenant-scoped unique constraint
puts `tenant_id` as the leading column. The exceptions are
`reservation_history` (F7) and `weekly_shipment` (F9), where the unique
key omits `tenant_id`.

**Redundant index (resolved):** `idx_tenants_slug` was dropped on staging 2026-06-15 (F14). It never existed on prod (F64 item 8 no-op). `tenants_slug_key` (unique) is the sole index on `slug` on both environments and serves the `resolve_tenant_by_slug` RPC equality lookup optimally.

---

## 9. Cascade chains and deletion behavior

Two roots: `tenants` and `auth.users`.

### 9.1 Tenant deletion

```
tenants (delete)
  └─ CASCADE → user_profiles
  └─ CASCADE → catalog
       ├─ NO ACTION → preorders.catalog_id   (would block, but…)
       └─ SET NULL → usage_events.catalog_id
       └─ SET NULL → weekly_shipment.catalog_id
  └─ CASCADE → preorders     (direct, before catalog cascade hits NO ACTION)
  └─ CASCADE → subscriptions
       └─ CASCADE → (already gone with user_profiles; no extra action)
  └─ CASCADE → reservation_history
  └─ CASCADE → usage_events
  └─ CASCADE → weekly_shipment
  └─ CASCADE → app_settings
  └─ CASCADE → settings
```

Deleting a tenant cleans up everything for that tenant. The order matters:
the direct `preorders.tenant_id` CASCADE removes preorders before the
catalog CASCADE runs into the `NO ACTION` blocker on `catalog_id`, so the
delete completes successfully.

### 9.2 Auth user deletion

```
auth.users (delete)
  ├─ SET NULL → usage_events.user_id
  └─ CASCADE  → reservation_history.user_id  (F13 — intent unclear)
  (no link to user_profiles.id — see Section 3.3)
```

Deleting an `auth.users` row does **not** cascade to `user_profiles`
because there is no FK between them. The expected cleanup path for a
customer who should be removed is to delete the `user_profiles` row (which
cascades through `subscriptions` but is blocked by `preorders` if any
exist) and separately delete the `auth.users` row. The
`claim-paper-customer` Edge Function does both deletes explicitly.

### 9.3 User profile deletion

```
user_profiles (delete)
  └─ CASCADE → subscriptions
  └─ NO ACTION → preorders.user_id  (blocks delete if any preorders exist)
```

Deleting a `user_profiles` row removes that user's subscriptions but is
blocked by any preorder. Either remove the user's preorders first or use
`claim-paper-customer` (for paper accounts) which moves preorders before
deleting the profile.

### 9.4 Catalog row deletion

```
catalog (delete)
  ├─ NO ACTION → preorders.catalog_id  (blocks delete if any preorders exist)
  ├─ SET NULL → usage_events.catalog_id
  └─ SET NULL → weekly_shipment.catalog_id
```

Direct catalog deletion is blocked if any preorder references the row.
This is why `purge_stale_catalog()` filters to
`id NOT IN (SELECT catalog_id FROM preorders WHERE tenant_id = ...)`
before issuing its DELETE. Without the filter the import script's
new-month sequence would fail when any past-month preorders exist.

---

## 10. Application API surface (`app.js`)

`app.js` is the single shared module loaded by every page. It exports
several namespaced API objects on `window` (or via direct const reference
within the page's inline script). Every method below is async unless
noted.

### 10.1 `TenantContext`

Resolves the active tenant for the current page load. Must be awaited
before any API call that needs `tenant_id`.

```javascript
TenantContext.resolve()       // → { id, slug, display_name }
TenantContext.current()       // → cached resolved tenant; throws if not resolved
TenantContext.source()        // → 'profile' | 'subdomain' | 'query' | 'session' | 'default'
```

Resolution order: authenticated profile → subdomain (`tenantSlugFromHostname()`)
→ `?t=<slug>` query param → sessionStorage → founding tenant fallback.

### 10.2 `Auth`

```javascript
Auth.getSession()             // → session
Auth.getUser()                // → user
Auth.getProfile(userId)       // → profile (full row from user_profiles)
Auth.requireAuth(redirectTo?) // → user; redirects to login if unauthenticated
Auth.requireAdmin(redirectTo?) // → { user, profile }; redirects if non-admin
Auth.signIn(email, password)  // → { data, error }; logs login event on success
Auth.signOut()                // → void; logs logout event, clears AdminContext
```

### 10.3 `Catalog`

```javascript
Catalog.getLatestMonth()      // → 'YYYY-MM'
Catalog.fetch({ month, distributor, publisher, search, hideVariants, page, pageSize })
                              // → { items, error, total }
Catalog.getPublishers(month)  // → string[] (deduplicated, sorted)
```

`Catalog.fetch` adds a `hideVariants` option (omitted from the prior
documentation) that filters to standard covers only. The `search` field
matches `title`, `series_name`, `writer`, `publisher`, `upc`, `isbn`, and
`item_code`. `getPublishers` reads in two batches (rows 0–999 and
1000–1999) to work around Supabase's 1000-row default limit.

### 10.4 `Preorders`

```javascript
Preorders.getMyIds(userId)            // → Map<catalogId, quantity>
Preorders.getMy(userId)               // → { items, error } with embedded catalog
Preorders.reserve(userId, catalogId, quantity?)
                                       // → { data, error }; passes tenant_id explicitly
Preorders.updateQuantity(userId, catalogId, quantity)
                                       // → { error }
Preorders.cancel(userId, catalogId)   // → { error }
Preorders.setFulfilled(preorderId, fulfilled)
                                       // → { error } (admin)
Preorders.setFulfilledByCatalogId(catalogId, fulfilled)
                                       // → { error } (admin batch)
Preorders.getAll()                    // → { items, error } (admin; embeds catalog + email)
```

`getAll` uses a PostgREST embedded join `auth_users:user_id ( email )`
that relies on the by-convention UUID match between `preorders.user_id`
and `auth.users.id`. The match has no FK enforcement; if PostgREST ever
fails to infer the relationship the email column silently becomes null.
See F30.

### 10.5 `Subscriptions`

```javascript
Subscriptions.getAll(userId)                        // → { items, error }
Subscriptions.isSubscribed(userId, series, distributor)
                                                    // → boolean
Subscriptions.subscribe(userId, series, distributor, format?, source?)
                                                    // → { data, error }; logs event.
                                                    // source: 'modal' | 'post_reserve_prompt' | null —
                                                    // attribution written to usage_events.metadata.source
                                                    // (subscription-promotion, 2026-07-17)
Subscriptions.unsubscribe(userId, series, distributor)
                                                    // → { error }; logs event
Subscriptions.getAllAdmin()                         // → { items, error } (admin)
```

The optional `format` arg supports format-aware auto-reserve in the
import script. Subscriptions inserted from the catalog page pass the
selected item's `format`; subscriptions inserted from the popular-series
panel (subscriptions.html) pass null (legacy behavior — the import script
falls back to `isComicFormat()` matching).

### 10.6 `Settings`

Reads/writes **`app_settings`** only. The legacy `settings` table is
**not** accessed through this API — see Section 4.6 and F4.

```javascript
Settings.get(key)             // → string | null
Settings.set(key, value)      // → { error }; passes tenant_id explicitly
Settings.isMaintenanceMode()  // → boolean
Settings.setMaintenanceMode(on)
                              // → { error }
Settings.getOrderDeadline()   // → 'YYYY-MM-DD' | null
Settings.setOrderDeadline(dateStr)
                              // → { error }
```

### 10.7 `UsageEvents`

Fire-and-forget event logging. Methods do not return promises (caller
never awaits). Skipped entirely when `AdminContext.isActive()` is true,
so admin actions and impersonated sessions don't pollute analytics data.

```javascript
UsageEvents.reserve(userId, catalogItem)
UsageEvents.cancel(userId, catalogItem)
UsageEvents.subscribe(userId, seriesName, distributor, source?)  // source → metadata.source if truthy
UsageEvents.unsubscribe(userId, seriesName, distributor)
UsageEvents.catalogView(userId, { catalogMonth, page, search, publisher, distributor })
UsageEvents.pageView(userId, page, metadata?)
UsageEvents.login(userId)
UsageEvents.logout(userId)
```

Tenant_id is resolved defensively from `TenantContext.current()` with a
fallback to `FOUNDING_TENANT.id` in case `TenantContext.resolve()`
hasn't completed (this can happen because UsageEvents fires from arbitrary
page lifecycle points). Phase 3.3 removed the `tenant_id` column default;
`FOUNDING_TENANT.id` is now the only safety net (F31 — fixed 2026-05-10).

### 10.8 `MyList`

```javascript
MyList.sendConfirmation(userId, sessionToken)
                              // → { data, error }; calls send-my-list Edge Function
```

### 10.9 `Users` (admin)

```javascript
Users.getPending()            // → { items, error }; status = 'pending'
Users.approve(userId, sessionToken)
                              // → { data, error }; calls approve-customer Edge Function
Users.suspend(userId)         // → { error }; status = 'suspended'
Users.deleteProfile(userId)   // → { error }; deletes user_profiles row only
```

### 10.10 `PaperCustomers` (admin)

```javascript
PaperCustomers.generateEmail(fullName)
                              // → 'name.timestamp@paper.pulllist.local'
PaperCustomers.create(name, sessionToken)
                              // → { data: { user_id, email }, error }; calls create-paper-customer
PaperCustomers.list()         // → { items, error }; is_paper = true
PaperCustomers.claim(paperUserId, realUserId, sessionToken)
                              // → { data, error }; calls claim-paper-customer
```

### 10.11 `Recommendations`

```javascript
Recommendations.getCatalogIds(userId, month)
                              // → { items: [{id, variant_type}], hasPersonal }
```

Returns catalog item IDs ordered for the personalized catalog view. Tier 1
is items from series the user has reserved before (union of
`reservation_history` and current preorders). Tier 2 is items from the
most-popular series via `get_popular_series()` RPC.

The `get_popular_series()` call surfaces F20 directly into the customer's
catalog page recommendations.

### 10.12 `AdminContext`

Admin impersonation state. Persisted in sessionStorage; cleared on tab
close.

```javascript
AdminContext.isActive()                 // → boolean
AdminContext.activeUserId               // → uuid | null
AdminContext.activeUserName             // → string | null
AdminContext.set(userId, userName)      // sets impersonation; renders banner
AdminContext.clear()                    // clears impersonation; removes banner
AdminContext.resolveUserId(ownUserId)   // → activeUserId || ownUserId
AdminContext.restore()                  // re-renders banner on page load
```

Impersonation is purely client-side — the admin's session token is still
used for every Supabase call. Authorization to read the impersonated
user's data depends on the admin's RLS policies (admin-view policies on
`preorders` etc.). Cross-tenant impersonation is theoretically blocked by
the tenant scoping on `user_profiles` SELECT, which constrains which
users an admin can even discover to impersonate.

### 10.13 `WelcomeModal`

```javascript
WelcomeModal.show(userId, profile)
                              // → void; shown once per user, dual-guarded by localStorage and has_seen_welcome
```

### 10.14 Helpers (top-level functions)

```javascript
toast(message, type?)         // 'success' | 'error' | 'info'
formatDate(dateStr)           // → 'Mon DD, YYYY' or '—'
isFocPast(dateStr)            // boolean — uses local date parts (correct)
isFocLocked(dateStr)          // alias of isFocPast
isFocThisMonth(dateStr)       // boolean — local date parts
formatPrice(price)
escapeHtml(str)
debounce(fn, delay)
renderSkeletons(count, container)
buildComicCard(comic, reservedQty, focLocked?)
exportToCsv(rows, filename)
checkMaintenanceMode(isAdmin)  // redirects non-admins to holding page if maintenance_mode = true
initNav()                      // nav setup; called from every page's inline script
```

### 10.15 Recurring patterns

**Supabase 416 workaround.** When `.range(from, to)` is used with a filter
that may return zero rows, Supabase returns HTTP 416. The fix is to fetch
the count first with `{ head: true }` and only fetch rows if count > 0.
Used in `Recommendations.getCatalogIds`, in `catalog.html`'s catalog
fetch, and in `Catalog.getPublishers`'s two-batch fetch.

**Local date parts for date math.** `formatDate`, `isFocPast`, and
`isFocThisMonth` all use `new Date().getFullYear()`/`getMonth()`/`getDate()`
to avoid the UTC-shift bug that occurs when `toISOString().split('T')[0]`
is used in negative-UTC-offset timezones (e.g., New Jersey).
**Counter-examples** in `app.js` `NavBubble.load` and in `mylist.html`'s
past-item filter use `toISOString()` directly — see F28.

**Tenant_id on writes.** `Preorders.reserve`, `Subscriptions.subscribe`,
`Settings.set`, and `UsageEvents._log` all pass `tenant_id` explicitly via
`TenantContext.current().id`. Phase 3.2 wired this. Page-level direct
inserts (e.g., `subscriptions.html` writing `popular_series` reads only,
`mylist.html` updating preorder quantity inline) inherit tenant from the
existing row's tenant_id.

---

## 11. Edge Functions

Nine Deno-based Edge Functions are deployed to staging (`register-tenant`
added 5.4 S3). All are written in TypeScript, all use Supabase service-role
for privileged operations, and all that send email use MailerSend with the
`noreply@mrcyberrick.us` sender.

### 11.1 Function inventory

| Function | Caller | Auth check | Tenant-aware |
|---|---|---|---|
| `notify-customers` | import script (post-import prompt) | none (admin context implied by service-role caller) | yes (filters by `FOUNDING_TENANT_ID`) |
| `send-my-list` | mylist.html | session token required (but does not match user_id — F36) | yes (catalog month filter) |
| `invite-customer` | admin.html | admin check | yes — `tenant_id` resolved from the caller's own profile (fixed 2026-05-10; falls back to FOUNDING_TENANT_ID only if the lookup fails) |
| `register-customer` | MailerLite webhook | per-tenant webhook secret in URL (5.4 S2) | yes — `tenant_id` resolved from the matching tenant's `settings->>'mailerlite_webhook_secret'` |
| `approve-customer` | admin.html | admin check (no tenant component) | no |
| `create-paper-customer` | admin.html | admin check | yes — `tenant_id` resolved from the caller's own profile (fixed 2026-05-10; falls back to FOUNDING_TENANT_ID only if the lookup fails) |
| `claim-paper-customer` | admin.html | admin check, plus `is_paper` source check | no |
| `reset-password` | forgot-password.html | none (anti-enumeration: always returns success) | no |
| `register-tenant` | operator (curl/internal tooling, not customer-facing) | `TENANT_PROVISION_SECRET` via `x-operator-secret` header (5.4 S3) | creates the tenant — seeds `branding`/`settings` (incl. a fresh per-tenant webhook secret) on the new row |

`invite-customer` and `create-paper-customer` resolve `tenant_id` from the
calling admin's own profile (fixed 2026-05-10; F34) — new users created by
a tenant-2 admin land in tenant 2, not the founding tenant.
`register-customer`'s residual was resolved in 5.4 S2 (see F34 status +
per-tenant-secret contract note, § 13).

**Post-Phase-5 (5.5 close, 2026-07-15):** the inventory stays at 9 EFs — no
new function added. Tenant 2 (`comicstore`) now exercises `register-customer`'s
per-tenant-secret resolution and the `register-tenant` operator EF in
production (not just staging), confirming both work against a *second* real
tenant, not just the founding one.

### 11.2 Required secrets

Set in Supabase → Edge Functions → Secrets:

| Secret | Used by |
|---|---|
| `SUPABASE_URL` | all |
| `SUPABASE_ANON_KEY` | all |
| `SUPABASE_SERVICE_ROLE_KEY` | all |
| `MAILERSEND_API_KEY` | every function that sends email (all except claim-paper-customer) |
| `MAILERLITE_WEBHOOK_SECRET` | register-customer — retained for diagnostics only (5.4 S2); no longer the auth/tenant-source check (replaced by the per-tenant `tenants.settings->>'mailerlite_webhook_secret'` lookup) |
| `FOUNDING_TENANT_ID` | notify-customers, send-my-list, create-paper-customer, invite-customer, register-customer (retained for diagnostics on register-customer post-5.4-S2) |
| `TENANT_PROVISION_SECRET` | register-tenant (operator gate, 5.4 S3) — never shared with tenant admins |

`FOUNDING_TENANT_ID` was added during Phase 2 to enable tenant-aware
filtering and writes from the Edge Functions. The web app reads tenant
through the database; the import script hard-codes it; Edge Functions
read it from this secret.

### 11.3 Per-function notes

**`notify-customers`**: monthly catalog notification email. Reads the
deadline from `app_settings.order_deadline` (filtered by tenant) and
the recipient list from `user_profiles WHERE is_admin = false` (filtered
by tenant), excluding `@paper.pulllist.local` placeholder addresses. The
catalog link in the email body is hardcoded to **production**
(`https://mrcyberrick.us/comic-preorder/catalog.html`), not staging — this
is intentional for staging since the function is invoked by the import
script's post-import prompt and links should send recipients to the live
site.

**`send-my-list`**: per-customer pull-list confirmation email. The
session-token check at the top of the function verifies that *some*
authenticated session exists, but does not verify that the session's
user_id matches the request body's user_id. Any authenticated user can
trigger an email to any other user. F36.

**`invite-customer`**: admin-only new-account creation. Generates an
invite link via the Supabase Admin API, sends a branded email via
MailerSend, and inserts a `user_profiles` row with
`status = 'active'`, `created_by_admin = true`, and `tenant_id` resolved
from the calling admin's own profile (`callerTenantId`, fixed 2026-05-10;
F34) — falls back to `FOUNDING_TENANT_ID` only if that lookup fails.

**`register-customer`**: called by MailerLite webhook when a subscriber is
added to the "Monthly Comics" group. URL parameter `secret` is looked up
against `tenants.settings->>'mailerlite_webhook_secret'` (service-role) —
the matching tenant's id is used for the insert (5.4 S2; see § 13 F34 and
the per-tenant-secret contract note). No match or missing `secret` → 401.
Creates an auth user (no password), inserts a `user_profiles` row with
`status = 'pending'` and the resolved `tenant_id`, and sends a "browse
while we review" email containing a magic link. Email branding is still
founding-only regardless of resolved tenant — tracked as F72.

**`register-tenant`** (new, 5.4 S3): gated operator function, not
customer-facing. Auth gate is `TENANT_PROVISION_SECRET` via the
`x-operator-secret` header — checked before any body parsing; mismatch
or absent → 401. Validates `slug` against a DNS-safe lowercase pattern
and a function-level reserved-word denylist (`www`, `admin`, both founding
slugs, etc.) → 400 on either failure. Service-role INSERT into `tenants`
(`plan = 'free'`, `settings` seeded with a fresh per-tenant
`mailerlite_webhook_secret`, `branding` from the request body or `{}`);
unique-slug violation (`23505`) → 409 `slug_taken`; check-constraint
violation (`23514`) → 400 `invalid_slug`. Creates the first admin via the
GoTrue admin API (no direct `auth.users` insert) and a matching
`user_profiles` row (`status = 'active'`, `is_admin = true`). The three
writes (tenant, auth user, profile) are not transactional; on a failure
after a partial write the function attempts best-effort compensation
(delete profile → auth user → tenant, reverse FK order) before returning
500. Any residue is fully removable via the FK-ordered teardown in
`docs/phase-4.1-canary-procedure.md` (exercised end-to-end in 5.4 S4).
Returns `{ tenant_id, admin_user_id, slug, webhook_secret }` on success.

**`approve-customer`**: admin-only state change from pending to active.
Verifies the caller is admin via service-role profile lookup, updates
the target's `user_profiles.status` to `'active'`, generates a fresh
magic link, and emails it. **No tenant check** — an admin in tenant A
could approve a pending user in tenant B if they had the user_id.
Currently moot.

**`create-paper-customer`**: admin-only walk-in placeholder creation.
Creates an auth user with a random password and the placeholder email
provided by the caller (`name.timestamp@paper.pulllist.local`), inserts
a `user_profiles` row with `is_paper = true, status = 'active'`, and
`tenant_id` resolved from the calling admin's own profile
(`callerTenantId`, fixed 2026-05-10; F34) — falls back to
`FOUNDING_TENANT_ID` only if that lookup fails.

**`claim-paper-customer`**: merges a paper account into a real account.
Verifies the source is `is_paper = true` for safety. Re-points
`preorders.user_id` and `subscriptions.user_id` from paper to real
(409 conflicts on duplicate preorders are tolerated and the duplicates
fall away with the paper profile delete). Deletes the paper
`user_profiles` row, then deletes the paper `auth.users` row via the
Admin API. Reimplements the same logic as the unused
`claim_paper_account` SQL function (F33).

**`reset-password`**: generates a Supabase recovery token and emails a
branded reset link. Always returns success regardless of whether the
email address exists, to prevent account-existence enumeration.

The `STAGING_BASE` constant in `reset-password` is set to
`'https://mrcyberrick.us/comic-preorder-staging'` — **this is wrong**.
Staging is now hosted at `https://staging.pulllist.pages.dev/` (migrated 5.1). The
reset link sent to customers in staging would 404. F35 / F67.

---

## 12. Import script

`import-staging.js` is run from a local scripts folder
(`C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts\`)
and is never committed to the repo. It uses the Supabase service-role
key to bypass RLS for catalog and shipment writes.

### 12.1 Invocation

```powershell
node .\import-staging.js <lunar_catalog> <prh_catalog> [<lunar_shipment>] [<prh_shipment>]
```

Example with catalog only:
```powershell
node .\import-staging.js "..\Lunar_Product_Data_0426.csv" "..\2026_04_PRH_metadata_full_active.csv"
```

Example with catalog plus shipment:
```powershell
node .\import-staging.js "..\Lunar_Product_Data_0426.csv" "..\2026_04_PRH_metadata_full_active.csv" "..\delivery-detail-LUNAR.csv" "..\Shipment_PRH.csv"
```

If shipment paths aren't passed, the script prompts interactively. Answer
"n" at the prompt to skip shipment import (e.g. at the start of a month
before invoices arrive).

### 12.2 Tenant configuration

Top of file:

```javascript
const TENANT_ID = '72e29f67-39f7-42bc-a4d5-d6f992f9d790';
```

Hard-coded. Every catalog upsert, shipment row, and auto-reserve carries
this tenant_id explicitly. Every RPC call passes `p_tenant_id: TENANT_ID`
as the first argument.

### 12.3 New-month detection

The script reads the latest `catalog_month` from the database. If the
about-to-import month is greater than the latest, it triggers the full
new-month sequence:

1. `archive_stale_reservations(p_tenant_id, today, current_month)` — copies
   distinct (user, series, distributor, month) tuples from preorders +
   catalog into reservation_history before the catalog purge wipes them.
2. `purge_stale_catalog(p_tenant_id, today, current_month)` — removes
   past-month catalog rows whose on_sale_date < today and which are not
   referenced by any preorder in this tenant.
3. Catalog upsert (described below).
4. `delete_dropped_catalog_items(p_tenant_id, current_month, item_codes)` —
   removes items from this month that disappeared from the new
   distributor catalog.

If the import month equals the latest, only step 3 runs ("mid-month
refresh"). This makes the script safe to re-run during the same month.

### 12.4 Catalog upsert

```
on_conflict=tenant_id,item_code,distributor,catalog_month
Prefer: resolution=merge-duplicates,return=minimal
Batch size: 100
```

Conflict key matches the table's unique constraint exactly. `tenant_id` is
the leading column. UUIDs are preserved across re-runs — critical because
preorders reference catalog rows by UUID.

### 12.5 Auto-reserve subscriptions

After catalog upsert, the script:

1. Fetches every subscription (across the whole tenant) with `user_id`,
   `series_name`, `distributor`, `format`.
2. Fetches the catalog month's standard-cover items (NULL or 'Standard'
   or 'Primary Title' variant_type), in two batches to clear the
   1000-row limit.
3. Fetches existing preorders for those catalog IDs, in 100-id chunks,
   to skip duplicates.
4. Format-aware match: if `subscriptions.format` is set, requires exact
   format match against `catalog.format`; otherwise falls back to
   `isComicFormat()` (true unless format contains "trade paperback",
   "hardcover", "omnibus", "graphic novel", "digest", "box set", or
   "album").
5. Batch-inserts the matched, not-yet-reserved preorder rows (each
   carrying `tenant_id: TENANT_ID`).

### 12.6 Optional shipment import

If shipment paths are provided (or accepted at the prompt), the script
auto-detects each file's format from the first line:

- **Format A** — first line starts with "Delivery Number". 9-line
  metadata header, column header on line 10, data from line 11. Key
  columns: ISBN (used as UPC), Title, On Sale, Quantity. Cover URL built
  from `https://images.penguinrandomhouse.com/cover/d/{ISBN}`. Tagged
  `distributor = 'Lunar'`.

- **Format B** — first line is a numeric shipment number. 4-line
  metadata header, column header on line 5, data from line 6. Key
  columns: Code, Title, Qty, Retail, UPC, In-Store Date. Cover URL built
  from `https://media.lunardistribution.com/images/covers/large/{Code}.jpg`.
  Rows with Retail = 0.00 are filtered as promos. Tagged
  `distributor = 'PRH'`.

The two distributor labels are flipped from the *invoice source*: PRH
delivery invoices arrive as Format A and get tagged `'Lunar'` because
they ship via Lunar; Lunar's code-formatted shipment of PRH titles
arrives as Format B and is tagged `'PRH'` because the items are PRH's.
This is confusing but matches how the catalog rows are tagged.

### 12.7 Shipment upsert

Two paths because the conflict keys differ:

- **Lunar rows** (`upc` populated): upsert via
  `on_conflict=distributor,upc,on_sale_date`, batched. Rows with the same
  (upc, on_sale_date) within a batch are pre-summed in the script
  (Format A delivery invoices sometimes split a single ISBN across
  multiple lines).
- **PRH rows** (`item_code` populated, `upc` may be NULL): delete-then-
  insert per on_sale_date. PostgREST's `on_conflict` doesn't support
  partial indexes, and a full unique constraint on `item_code` would
  conflict with Lunar rows that have `item_code = NULL`. Delete-then-
  insert is safe here because PRH Format B shipments are small and
  always fresh.

The script emits warnings for shipment rows that don't match a catalog
row — matching is performed via `weekly_shipment.upc → catalog.upc/isbn`
for Lunar rows, and `weekly_shipment.item_code → catalog.item_code`
(WHERE distributor='PRH') for PRH rows.

### 12.8 Notification prompt

After all imports complete the script prompts to send the catalog
notification email via the `notify-customers` Edge Function. Answer "y"
to send to every active customer in the founding tenant; "n" to skip.

### 12.9 Re-run safety

- Catalog upsert: in-place via merge-duplicates.
- Shipment upsert: in-place via merge-duplicates (Lunar) or
  delete-then-insert (PRH). Both safe to re-run for the same week.
- Auto-reserve: fetches existing preorders and skips duplicates.
- New-month sequence: only fires when the import month is greater than
  the latest in the database. Mid-month re-runs skip the
  archive/purge/delete-dropped steps.

The one caveat is the maintenance-mode flag. `app.js`'s
`Settings.isMaintenanceMode()` reads from `app_settings`; the script
does not flip the flag automatically. The convention is to flip
maintenance ON manually before a new-month import (admin → Settings),
and flip it OFF after the import completes successfully. The script's
final log line reminds the operator to do this when a new-month sequence
ran.

---

## 13. Findings & known issues

The discovery pass that produced this document surfaced 27 findings; 8 additional findings (F45–F52) were surfaced during the Phase 4.1 pre-cutover audit pass.
They are listed below in priority order: HIGH first, then medium, then
low/trivial/info. Each entry: severity, status, description, where it
manifests, recommended fix one-liner.

**Pre-Phase-4 audit pass indicated.** Five findings (F4, F15, F16, F20,
F34) are HIGH or dormant-HIGH. Four of the five are dormant only because
staging has a single tenant; they activate when a second tenant onboards.
The fifth (F4) is an active correctness issue today. **These five should
be addressed before Phase 4** (production multi-tenancy migration), as
Phase 4 will replicate the same dormant bugs into production.

The remaining findings are real but lower-priority. A handful are
dead-code observations (F19, F26, F33) that describe schema objects with
no caller — candidates for cleanup in a future pass. One is an active
production-staging URL bug unrelated to multi-tenancy (F35).

### HIGH

#### F4 — both `settings` and `app_settings` are actively used
- **Status:** fixed 2026-05-10 — (a) `popular_series` migrated to
  `app_settings` (same key, same JSON, founding-tenant scoped);
  (b) `subscriptions.html` updated to read via `Settings.get()`
  instead of direct `db.from('settings')` query; (c) orphan
  `settings.maintenance_mode` row deleted; (d) `settings.popular_series`
  deleted after staging smoke test confirmed the panel still renders.
  `settings` table is now empty. Table itself not yet dropped —
  separate dead-code cleanup pass.
  **Prod resolution 2026-05-31 (Phase 4.6):** app-code merge (§ 4) routes reads to `app_settings`; `settings` rows `popular_series` and `maintenance_mode` deleted (§ 8 data drop); `settings` table on production is now empty. F4 fully resolved on both environments.
- The legacy `settings` table holds `popular_series` (read by
  subscriptions.html) and `maintenance_mode` (orphan duplicate of the
  `app_settings.maintenance_mode` row). The modern `app_settings` table
  holds `maintenance_mode` (canonical, written by `Settings` API) and
  `order_deadline`.
- **Where:** subscriptions.html line ~297; `app.js` `Settings` API.
- **Fix:** migrate `popular_series` from `settings` to `app_settings`
  (with a column or key change to disambiguate from
  `get_popular_series()` if desired); update subscriptions.html to read
  through the `Settings` API; drop the orphan `settings.maintenance_mode`
  row; eventually drop the `settings` table after confirming no other
  callers exist.

#### F15 — `weekly_shipment` SELECT policy has no tenant scoping
- **Status:** fixed 2026-05-10 — `qual = true` replaced with
  `tenant_id = current_tenant_id()`; verified via probe row in
  synthetic tenant returning 0 rows to founding-tenant session.
- The only SELECT policy is `qual = true` for the `authenticated` role.
  Verified by direct policy inspection.
- **Where:** RLS policy `authenticated users read weekly_shipment`;
  surfaced in production code via arrivals.html's
  `db.from('weekly_shipment').select(...)` query.
- **Fix:** replace `qual = true` with
  `qual = (tenant_id = current_tenant_id())`.

#### F16 — `preorders` admin write policies OR-permit cross-tenant writes
- **Status:** fixed 2026-05-10 — dropped `admins write tenant preorders`
  and `admins view tenant preorders`; `admins manage tenant preorders`
  (ALL, checks row's tenant_id on both qual and with_check) is the sole
  surviving admin policy. Verified: admin INSERT into synthetic-tenant
  preorders fails with RLS violation.
- Three admin policies on `preorders` exist; PostgreSQL ORs PERMISSIVE
  policies together. The `admins write tenant preorders` policy only
  checks the admin's own tenant via the `user_profiles` join; it does
  not require the row's `tenant_id` to match.
- **Where:** RLS policies on `preorders`.
- **Fix:** consolidate the three admin policies into one that checks
  both `tenant_id = current_tenant_id()` on the row and
  `current_user_is_admin()`; drop the redundant `admins view tenant
  preorders` (covered by the consolidated ALL policy).

#### F20 — `get_popular_series()` returns counts across all tenants
- **Status:** fixed 2026-05-10 — added `AND c.tenant_id =
  current_tenant_id()` to the WHERE clause; SECURITY DEFINER kept.
  Verified: probe series inserted under synthetic tenant absent from
  results when queried as founding-tenant user.
- SECURITY DEFINER function with no `tenant_id` filter in the body.
  Bypasses RLS.
- **Where:** function body queries `preorders JOIN catalog`. Two
  callers: `admin.html`'s Top Series tab and `app.js`'s
  `Recommendations._getPopularSeries` (used in every customer's catalog
  recommendations).
- **Fix:** add `WHERE c.tenant_id = current_tenant_id()` to the WHERE
  clause; alternatively switch to `SECURITY INVOKER` and rely on RLS.

#### F34 — user-creation Edge Functions hard-pin to founding tenant
- **Status:** fixed 2026-05-10 (`invite-customer`/`create-paper-customer`); **residual resolved 2026-06-16 (5.4 S2)** — `register-customer` no longer pinned to `FOUNDING_TENANT_ID`. See per-tenant-secret contract note above. F34 fully resolved across all user-creation Edge Functions.
- `invite-customer` and `create-paper-customer` fetch `tenant_id` alongside
  `is_admin` from the caller's own profile
  (`user_profiles.tenant_id WHERE id = caller's auth.uid()`) and use
  `callerTenantId` for new profile inserts, falling back to
  `FOUNDING_TENANT_ID` only if that lookup fails. A tenant-2 admin's paper
  and invited customers land correctly in tenant 2 —
  **re-verified against deployed source 2026-07-15** (5.5 S6 closeout
  session). This supersedes an incorrect "do not use from tenant 2"
  caution that had propagated into the 5.5 S3 deploy log, the soak log,
  and `docs/tenant-onboarding-runbook.md`: those notes described
  pre-2026-05-10 behavior and were stale by the time 5.5 S3 ran; they are
  corrected in the same commit as this entry.
- `register-customer` (webhook, no admin context) resolves `tenant_id`
  from the per-tenant `tenants.settings->>'mailerlite_webhook_secret'`
  (5.4 S2) — see contract note below. `FOUNDING_TENANT_ID` is retained
  only as the last-resort fallback in `invite-customer`/
  `create-paper-customer`, and for diagnostics in `register-customer`.
- **Where:** `supabase/functions/invite-customer/index.ts`,
  `supabase/functions/create-paper-customer/index.ts`,
  `supabase/functions/register-customer/index.ts`.
- **Prod resolution 2026-05-31 (Phase 4.6):** `FOUNDING_TENANT_ID` secret set on prod project (§ 1); all 8 EFs redeployed from staging SHA `cab5dca` (§ 2). F34 fully resolved on production.
- **`register-customer` per-tenant-secret contract (5.4 S1, 2026-06-16):** the residual founding pin (un-pinned in S2) is replaced by a **per-tenant webhook secret** stored at `tenants.settings->>'mailerlite_webhook_secret'` (jsonb; `settings` is service-role-only, never returned by `resolve_tenant_by_slug`). Lookup: `GET /rest/v1/tenants?settings->>mailerlite_webhook_secret=eq.<secret>&select=id,slug,display_name` via service-role. Empty/absent `?secret=` → `401`; no matching tenant → `401`; exactly one matching tenant → that tenant's id is used for the `user_profiles` insert. **Founding migrated 2026-06-16 (staging):** `tenants.settings->>'mailerlite_webhook_secret' = 'pulllist-staging-2026'` for `72e29f67-…`; lookup verified to return exactly one row (founding). Prod migration is 5.4 S6.

### Medium

#### F6 — `app_settings` and `settings` PK on `key` alone
- **Status:** **resolved on both environments** — staging 2026-07-08, **production 2026-07-28**. `app_settings` PK re-keyed to `(tenant_id, key)` via `docs/sql/f6-app-settings-pk-rekey.sql` (Rick, SQL Editor, both runs). Verified post-DDL on each: `pg_constraint` returns `PRIMARY KEY (tenant_id, key)`. Both environments also passed the app-level smoke (admin maintenance toggle ON→OFF + order-deadline banner read, exercising `Settings.set()` upsert and `Settings.get()` through the new key) — staging 2026-07-08, **prod 2026-07-28**.
- **Smoke-reading note (prod, 2026-07-28):** the operator observed "maintenance banner not visible when on" and correctly queried it. **This is the designed admin bypass, not a defect** — `checkMaintenanceMode()` (`app.js:720-721`) opens with `if (isAdmin) return;` and never reads the setting, so an admin flipping the toggle cannot see the holding page from their own session. The smoke still passed in full: the toggle persisting ON exercises `Settings.set()`'s upsert against the new PK (the precise operation that would have captured founding's row under the old one), and the order-deadline banner rendering exercises `Settings.get()`. The non-admin holding-page render is unchanged by this re-key and was not re-verified on prod; it needs a non-admin session and is not owed by F6. The legacy `settings` table (empty, dead) intentionally left as-is; its drop and the now-redundant `idx_app_settings_tenant` drop remain separate decisions carried in the runbook.
- **The prod gate was missed, and the miss is the more useful record here.** The runbook marked this "must land before tenant 2 onboards"; `comicstore` went live on production **2026-07-15** and the re-key did not run until **2026-07-28** — a 13-day window discovered by a findings-index audit, not by any alarm. **No damage occurred**, confirmed by the pre-DDL diagnostic: prod held 2 tenants, `rjbookstop` held both `maintenance_mode` and `order_deadline`, and `comicstore` held `(NONE)`. The collision never fired only because the pilot tenant never wrote a setting.
- **Why it would have been silent had it fired.** `Settings.set()` (`app.js:601-610`) upserts with **no explicit `onConflict`**, so PostgREST resolves on the primary key. Under the old `(key)`-only PK a `comicstore` admin saving `maintenance_mode` would not have inserted a second row — it would have UPDATEd founding's row and rewritten its `tenant_id`, after which RLS hides that row from founding entirely. The setting is *captured*, not duplicated. Detection would then have depended on noticing an absence: `Settings.get()` (`app.js:591-598`) destructures only `{ data }` and discards `error`, returning `data?.value ?? null`, so `isMaintenanceMode()` reads `false` (maintenance silently un-engageable during an import) and the catalog's order-deadline banner just hides itself. No thrown error on any path.
- **Pre-DDL guard added 2026-07-28, not in the original runbook:** a check for FKs referencing `app_settings` (`confrelid = 'public.app_settings'::regclass AND contype = 'f'`), since `DROP CONSTRAINT` fails if a dependent FK exists and F64 catalogued eight prod↔staging DDL divergences. Returned zero rows on prod. Worth keeping in any future PK re-key.
- Both tables use `key` as the primary key, not `(tenant_id, key)`. Means
  one tenant can hold the value `'maintenance_mode'` and a second tenant
  cannot independently hold a different value for the same key.
- **Where:** primary key constraints on both settings tables.
- **Fix:** drop and re-add the PK as `(tenant_id, key)` on both tables.
  Coordinated with the F4 cleanup.

#### F10 — `preorders` FKs to `user_profiles` and `catalog` are NO ACTION
- **Status:** open
- Differs from the prior documentation, which described both as CASCADE.
  Means deleting a `user_profiles` row fails if any preorder references
  it, and deleting a `catalog` row fails if any preorder references it.
- **Where:** FK definitions; documented as the reason
  `purge_stale_catalog()` filters `id NOT IN (SELECT catalog_id FROM
  preorders WHERE tenant_id = ...)`.
- **Fix:** intent unclear — confirm whether NO ACTION is the desired
  behavior (preserve preorders as audit trail) or whether CASCADE was
  intended; align the FKs and the prior documentation.

#### F17 — `reservation_history` admin SELECT policy is unscoped
- **Status:** fixed 2026-05-26 (Phase 4.1 C2) — both policies dropped and recreated:
  admin now uses `current_user_is_admin() AND tenant_id = current_tenant_id()`;
  user now uses `auth.uid() = user_id AND tenant_id = current_tenant_id()`.
  Also fixed the recursive EXISTS admin pattern (F46 bundled with C2).
- Both `users view own history` (safe) and `admins view all history`
  (unsafe) lack `tenant_id` filters. Admins in tenant A could SELECT
  reservation_history from tenant B.
- **Where:** RLS policies on `reservation_history`.
- **Fix:** add `AND tenant_id = current_tenant_id()` to the admin
  policy.

#### F21 — `claim_paper_account()` SQL function lacks defensive checks
- **Status:** fixed 2026-05-26 (Phase 4.1 C3) — function dropped (see F33). Dead code removal resolves both F21 and F33.
- The function does not verify `is_paper = true` before re-pointing
  rows, and would happily merge any two accounts. SECURITY INVOKER label
  is misleading because the function requires `auth.users` DELETE
  rights, restricting effective callers to service-role.
- **Where:** function body.
- **Fix:** if keeping the function, add
  `IF NOT (SELECT is_paper FROM user_profiles WHERE id = paper_user_id)
  THEN RAISE EXCEPTION 'Source is not a paper account'; END IF;` and
  switch to SECURITY DEFINER with `SET search_path = public`.
  Alternatively drop the function since `claim-paper-customer` Edge
  Function does the work.

#### F35 — `reset-password` uses wrong staging URL
- **Status:** **resolved 2026-06-15 (5.2 S5, subsumed by F67)** — status line corrected 2026-07-28. It had read "confirmed, **active in staging right now**" for six weeks after the fix landed, presenting a closed defect as live.
- **Verification (2026-07-28, against deployed source):** `reset-password/index.ts:1` now reads
  `const FORGOT_PASSWORD_URL = ...Deno.env.get('APP_BASE_URL') ?? 'https://pulllist.app'.../forgot-password.html`.
  No `STAGING_BASE` constant remains anywhere in the file. `APP_BASE_URL` is set on both projects per F67 (staging → `https://staging.pulllist.pages.dev`, prod → `https://pulllist.app`), and F67 records the prod reset-password link verified live.
- **The description below is the pre-F67 record and is retained as history, not as current state.** Line 1 of `reset-password/index.ts` **formerly** read:
  `STAGING_BASE = 'https://mrcyberrick.us/comic-preorder-staging'`. The
  actual staging URL is now `https://staging.pulllist.pages.dev/` (migrated 5.1).
  Customers who request a password reset via staging receive a 404 link.
- **Where:** `reset-password` Edge Function source.
- **Fix:** subsumed by F67 — replace `STAGING_BASE` with `Deno.env.get('APP_BASE_URL')` and set the secret to `https://staging.pulllist.pages.dev` (staging) / `https://pulllist.app` (prod).

### Low

#### F7 — `reservation_history` unique key omits `tenant_id`
- **Status:** **closed won't-fix 2026-07-28** — cosmetic consistency only, no reachable defect. The entry's own analysis (below) establishes that cross-tenant collisions **cannot occur**: `reservation_history.user_id` scopes the key transitively through `user_profiles.tenant_id`, and one user belongs to exactly one tenant. Re-affirmed under two live tenants (`comicstore` onboarded 2026-07-15), which is the condition that would have activated it had the reasoning been wrong. Reopen only if a user is ever allowed to hold profiles in more than one tenant — that premise, not the index shape, is what this finding actually depends on.
- **Distinguish from F9,** which looks identical but is **not** closed: `weekly_shipment` has no user column, so it has no transitive tenant scope and its collision is real.
- `(user_id, series_name, distributor, catalog_month)` is the unique
  key. Tenant-scoping is implicit via `user_profiles.tenant_id` (one
  user belongs to one tenant), so cross-tenant collisions cannot
  actually happen — but the key is shaped inconsistently with `catalog`
  and `subscriptions`.
- **Fix:** rebuild the unique index as
  `(tenant_id, user_id, series_name, distributor, catalog_month)` for
  consistency.

#### F9 — `weekly_shipment` unique key omits `tenant_id`
- **Status:** **RESOLVED 2026-07-28 — both environments.** Unique key rebuilt as `(tenant_id, distributor, upc, on_sale_date)` and both import scripts updated to match. Final verification on prod **and** staging: `0` unique constraints on `weekly_shipment`, `1` `weekly_shipment_tenant_unique`. Filed→resolved inside one session, having first sat mis-described as "dormant under one tenant" for the 13 days after `comicstore` went live.
- **Residual, stated rather than glossed:** the **production import path has not yet been exercised against the final state.** Staging's was, with a real import (see step 3). Prod's `import.js` is byte-identical to that verified script, the index is confirmed present, and nothing else writes this table — but the next prod shipment import is the first run on the finished configuration. A mismatch would fail **loudly** with `42P10` at write time and is recoverable in one statement (`CREATE UNIQUE INDEX weekly_shipment_unique ON public.weekly_shipment (distributor, upc, on_sale_date);`), so this is a known-loud residual, not an open defect.
- **Dormancy history (why the old status was wrong):** the pre-fix line read "dormant under one tenant", which stopped being true on **2026-07-15** when `comicstore` went live. It remained dormant only for an **operational** reason — tenant 2 does not import shipments (prod 2026-07-28: `rjbookstop` **754** rows, `comicstore` **0**). That was a fact about current practice, not a property of the schema.
- **Severity (as it stood):** Medium-dormant. The two write paths failed differently — one silently, one loudly — which mattered more than the shared root cause.
- **Constraint state before the fix (production, 2026-07-28):** exactly one unique object besides the PK — `weekly_shipment_unique` on `(distributor, upc, on_sale_date)`, with no `tenant_id`. **It was a UNIQUE constraint, not a plain index** — `pg_indexes` renders both identically, so `DROP INDEX` would have failed; removal required `ALTER TABLE … DROP CONSTRAINT`. Prod and staging agreed on this, which is not something F64 lets us assume for free.
- **The two write paths behave differently under a cross-tenant collision:**

  | Path | Rows | Write method | Collision behavior |
  |---|---|---|---|
  | Format A (`distributor='PRH'`, always has `upc`) | `import.js` Lunar-named upsert, `~line 838` | `POST …?on_conflict=distributor,upc,on_sale_date` with `Prefer: resolution=merge-duplicates` | **Silent capture.** The payload carries `tenant_id`, so a merge UPDATEs founding's row and rewrites its `tenant_id` to the importing tenant. Identical mechanism to F6's `Settings.set()`. |
  | Format B (`distributor='Lunar'`, `upc` optional) | `import.js` PRH-named delete-then-insert, `~line 862` | tenant-scoped `DELETE …&tenant_id=eq.${TENANT_ID}` then plain `POST` | **Loud 409** for rows with a non-null `upc` — the DELETE is correctly tenant-scoped, so the INSERT collides with the other tenant's row and the batch fails visibly (this is the F83 failure mode). Rows with `upc = null` are unconstrained entirely, since Postgres unique indexes treat NULLs as distinct. |

- **Naming trap, checked and confirmed harmless 2026-07-28:** `buildLunarShipmentRows`/`buildPrhShipmentRows` and the `lunarRows`/`prhRows` variables are inverted relative to the `distributor` values their rows carry — `buildPrhShipmentRows` requires `item_code`, which only Format B sets, and Format B is tagged `'Lunar'`. Every `on_conflict` key and every filter nonetheless matches the actual distributor value, including the `distributor=eq.Lunar` DELETE. **This is a readability hazard from the pre-F84 labeling, not a defect** — verified against the parsers at `import.js:228-310` rather than inferred from the names. Do not "fix" it without re-reading those parsers.
- **Corrects a claim made while investigating:** `import.js:46-48` states the table "needs TWO unique indexes", including `weekly_shipment_prh_unique` on `(distributor, item_code, on_sale_date)`. That header comment is **stale** — the second index does not exist on production and is not wanted. The code's own comment at `~line 855` explains why it was abandoned: PostgREST `on_conflict` cannot use partial indexes, and a full unique constraint on `item_code` fails because other rows carry `item_code = null`. Delete-then-insert replaced it. **§ 4.10 of this document is therefore correct as written** and needs no change — a suspected doc gap that verification disproved.
- **Fix:** rebuild as `(tenant_id, distributor, upc, on_sale_date)` and update the Format A `on_conflict` clause in both `import.js` and `import-staging.js` to match. The Format B path needs no change — its DELETE is already tenant-scoped.
- **Rollout complete — all 5 steps, 2026-07-28.** Deliberately sequenced so the old and new unique objects coexisted throughout, meaning no window existed in which either script version was broken:

  | Step | State | Detail |
  |---|---|---|
  | 1. Staging `CREATE INDEX` | ✅ 2026-07-28 | `weekly_shipment_tenant_unique` on `(tenant_id, distributor, upc, on_sale_date)`, created alongside the existing `weekly_shipment_unique`. Cannot fail on data — the new key is strictly weaker than the old. |
  | 2. `import-staging.js` | ✅ 2026-07-28 | Scripts repo `e080ed4`. One functional line; `node --check` clean, `npm test` 46/46. |
  | 3. Staging verification | ✅ 2026-07-28 | Real shipment import (catalog `2026-08`, delivery `0088308379`): **18 Format A rows through the changed upsert path**, `29 rows upserted`, no `42P10`. All 539 rows under `72e29f67-…`. A wrong `on_conflict` would have failed loudly, so this is a positive result rather than an absence of complaint. |
  | 4. Prod index + `import.js` | ✅ 2026-07-28 | `weekly_shipment_tenant_unique` created on `plgegklqtdjxeglvyjte`, **then** the one-line change mirrored into `import.js` (scripts repo `1653e7d`). Index first by necessity — reversing the order breaks the next prod import with `42P10`. |
  | 5. Drop the old unique constraint (both) | ✅ 2026-07-28 | `ALTER TABLE public.weekly_shipment DROP CONSTRAINT weekly_shipment_unique` on staging and prod. Run **ahead of** the next import rather than after, so that import exercises the final configuration directly instead of a transitional one. Post-drop verify on both: `old_constraint = 0`, `new_index = 1`. |

- **Sequencing note worth reusing.** The original plan held the drop until *after* a verifying prod import. That was weaker: the import would have exercised the both-objects transitional state, leaving the final state unverified until the *following* import. Dropping first collapses that to one step — Rick's call, and the better one.
- ⚠️ **Nothing automated would have noticed a half-finished rollout.** The scripts repo's parity suite passed 46/46 *while `import.js` and `import-staging.js` genuinely disagreed on this conflict key*, because it covers the row builders and not the write URLs. Correct behavior during a staging-first rollout, but it means the suite is **not** a backstop: a stalled rollout looks exactly like a completed one to every automated check. Kept on the record because it is the F105 shape, and because the same blind spot applies to any future change to these write paths.
- **This is a gated precondition, and F105 is about exactly this class of gate going unchecked.** It must land **before any second tenant runs a shipment import** — the same shape as F6's "must land before tenant 2", which was missed by 13 days because it lived in prose rather than in a checklist. **Gate written 2026-07-28** as the first checkbox in `docs/tenant-onboarding-runbook.md` § Step 7, carrying the `pg_indexes` verification query and an explicit stop instruction. Noted there that its **trigger is the first shipment import, not go-live** — Step 7 is where checklists actually get walked, but the hazard can arrive earlier, so the item says so rather than relying on the step's position. This is F105's fix direction applied to its own live test case.
- **Related:** **F6** — same capture mechanism, same class of gate, resolved 2026-07-28. **F105** — the process finding this precondition is the live test case for. **F83** — the Format B duplicate-UPC batch abort, which is the loud half of this table's collision behavior. **F7** — looks identical, closed won't-fix; the difference is that `reservation_history` has a `user_id` giving it transitive tenant scope and `weekly_shipment` has no such column.

#### F13 — `reservation_history.user_id` cascades on auth user delete
- **Status:** open, intent unclear
- FK is `ON DELETE CASCADE`. If the table's purpose is to preserve
  history past user deletion, this defeats it. Could also be a mistake
  — SET NULL would preserve history while detaching from the deleted
  user.
- **Fix:** confirm intent. If preservation is desired, change to SET
  NULL.

#### F19 — `is_admin()` is a dead duplicate of `current_user_is_admin()`
- **Status:** fixed 2026-05-26 (Phase 4.1 C4) — function dropped; confirmed absent from pg_proc and confirmed no RLS policy referenced it.
- Same logical result as `current_user_is_admin()`, but lacks `STABLE`
  and lacks `SET search_path`. No RLS policy references it.
- **Fix:** drop the function.

#### F23 — several DEFINER functions lack `SET search_path` hardening
- **Status:** fixed 2026-05-26 (Phase 4.1 C5) — `purge_stale_catalog`, `delete_dropped_catalog_items`, and `get_popular_series(text)` all given `SET search_path = public` via ALTER FUNCTION. `is_admin` dropped (F19/C4). All 8 DEFINER functions now have `search_path=public` confirmed via pg_proc.
- `purge_stale_catalog`, `delete_dropped_catalog_items`,
  `get_popular_series`, and `is_admin` are all SECURITY DEFINER but lack
  `SET search_path = public`. Standard PostgreSQL DEFINER hardening
  recommendation.
- **Fix:** add `SET search_path = public` to each function definition.

#### F24 — `archive_stale_reservations` INVOKER but no INSERT policy on `reservation_history`
- **Status:** fixed 2026-05-26 (Phase 4.1 C12) — promoted to SECURITY DEFINER with `SET search_path = public` via two-step ALTER. Verified: prosecdef=true, proconfig=["search_path=public"]. See also F45.
- INVOKER security model means the function only succeeds when called
  by a role that has INSERT privilege on `reservation_history`. RLS
  policies on the table only grant SELECT; only service-role bypasses
  RLS. Effectively service-role-only by accident.
- **Fix:** if keeping INVOKER, document as service-role-only. If
  preferred, switch to SECURITY DEFINER with `SET search_path = public`.

#### F25 — `user_profiles.email` is denormalized from `auth.users.email`
- **Status:** open, but **materially re-scoped 2026-08-10 — the stated mechanism has never fired and has no code path to fire through.**
- **As originally filed:** "No trigger keeps it in sync. If a user changes their auth email, the profile email drifts." **Fix: add a trigger on `auth.users` UPDATE, or remove the column and join.**

**Re-measured 2026-08-10, and the original framing is wrong in a way that matters.**
Rick spotted em-dashes in the new Accounts tab's Email column. On **production, 6
of 27 profiles** had `email` NULL while `auth.users` held a good address —
Albert Abaunza, Alex Alvarez, Book Stop, Brian Moss, Mike Neubauer, Rick
Sedivec. All non-paper.

**Those are NOT drift.** They are `NULL`, not stale-but-different: never
populated, not populated-then-diverged. Three checks establish the difference:

| Question | Answer |
|---|---|
| Any code path that changes `auth.users.email`? | **None.** Both `db.auth.updateUser()` call sites (`index.html:767`, `forgot-password.html:267`) pass `{ password }`. The three `auth/v1/admin/users/` calls are two DELETEs (`claim-paper-customer`, `register-tenant`) and one GET (`send-my-list`). |
| Do all creation paths set `user_profiles.email`? | **Yes** — `register-customer`, `invite-customer`, `create-paper-customer` all set it. Every new row is correct. |
| Were the 6 NULLs drift? | **No.** NULL, never populated. Historical rows predating the column's population. |

**So the drift half of this finding is theoretical.** Email is effectively
**immutable** in this application — which is not an accident, it is the design:
the Accounts Edit control states it on screen, *"Email cannot be changed here —
it is their login address. To move it, re-invite them."* A denormalized copy of
an immutable value is a legitimate cache, not a defect.

**A sync trigger was written and then WITHDRAWN (Rick, 2026-08-10).** His
objection was correct and worth recording: it would have added a trigger to the
platform-managed `auth` schema, with a failure mode that could block a
customer's email change, to defend against a scenario the application prevents
by design. *"Correcting a problem that we created in an effort to make something
that does not match the system's configuration."*

**The real defect, and its actual consequence:**

| Surface | Reads | Effect of the NULLs |
|---|---|---|
| `admin.html` Accounts | `user_profiles.email` | An em-dash. Cosmetic — and the only reason anyone noticed. |
| **`analytics.html` win-back list** | `user_profiles.email` | **`winbackRows.map(r => r.email).filter(Boolean)` SILENTLY DROPS them.** A marketing list missing 6 of 27 customers with nothing on screen saying so. **This predates the Accounts tab entirely** and is the whole cost of the finding. |
| `notify-customers` | **`auth.users` directly** (`index.ts:129`) | **Unaffected.** Customer notifications have always reached the right addresses. |

The silent-drop is the **F96 shape** — an absent signal indistinguishable from
"there was nothing to send". Noted here rather than filed separately (Rick's
call, 2026-08-10): it is a consequence of this finding, not a second defect.

**APPLIED 2026-08-10 to BOTH environments.** staging 1 row, production **6 rows** (Rick Sedivec, Albert Abaunza, Alex Alvarez, Mike Neubauer, Brian Moss, Book Stop). Post-check on both: `still_null = 0`, profile/auth mismatches = **0**, row counts unchanged (19 / 27). **The analytics win-back list went from drawing on 6 of 12 non-paper customers to 12 of 12** — the actual point of the fix, and it doubled.

Applied via PostgREST with `email=is.null` as the request filter rather than by pasting the file, so an already-populated row **could not match**: the no-overwrite guarantee is structural, not a promise in a WHERE clause someone might edit.

**Fix — one file, and it is sufficient:**
`docs/sql/backfill-user-profiles-email.sql`. Fills NULLs only, never overwrites.
Because every creation path already populates the column and nothing ever
changes it, **the backfill closes this finding for all practical purposes.**

**Residual, stated so nobody re-derives it:** an email changed **manually in the
Supabase console** would still drift, since no trigger exists. That is an
out-of-band admin action, not an application path, and it is not worth a trigger
on `auth.users` to defend against. If self-service email change is ever built,
**this finding reopens properly** and the sync must be built with it.

#### F28 — `toISOString()` used for date math in two places
- **Status:** **resolved 2026-05-14 (Phase 3.8) — retained deliberately as a standing anti-pattern record, not an open defect.** Verdict line added 2026-07-28; the paragraph below previously carried the disposition with no status verdict, which left the entry ambiguous to anyone counting open findings.
- All callsites closed in phase 3.8 (2026-05-14). The two
  date-math callsites (`NavBubble.load`, `mylist.html` past-item filter)
  now use `DateUtils.todayLocal()` and `DateUtils.weekRange()`. The four
  filename-label callsites (`mylist.html` export, three `admin.html`
  export handlers) also migrated to `DateUtils.todayLocal()` while in the
  area — same anti-pattern, milder symptom (UTC-labeled download
  filenames). F28 stays in the findings index as documentation of the
  anti-pattern; reviewers should flag any new `toISOString()` use in
  date-string contexts.
- `app.js` `NavBubble.load` (lines 262-263) and `mylist.html` past-item
  filter (line 696) both used `new Date().toISOString().split('T')[0]`
  for "today". Per the documented anti-pattern: in negative-UTC-offset
  timezones (New Jersey is UTC-4/-5), `toISOString()` after 8 PM local
  returns tomorrow's date. Off-by-one for late-evening users.
- **Fix:** replaced with `DateUtils.todayLocal()` and
  `DateUtils.weekRange()` (new helpers in `app.js`, phase 3.8).

#### F30 — `Preorders.getAll` join `auth_users:user_id ( email )` is fragile
- **Status:** open
- PostgREST embedded join relies on the by-convention UUID match
  between `preorders.user_id` and `auth.users.id`. There is no FK to
  enforce the relationship. Silent failure mode: email column becomes
  null without erroring.
- **Fix:** read `user_profiles.email` (which is denormalized from
  auth.users) instead, or query auth.users separately and join
  client-side as `admin.html` already does for the per-customer view.
- **Measured 2026-08-09, and it changes the fix: `Preorders.getAll` has ZERO
  call sites.** Grepped across every `.html` and `.js` in the repo — nothing
  calls it. And the relation it embeds **does not exist**: a service-role read
  of `public.auth_users` returns **404 `PGRST205`**, so the join would not
  degrade to a null email as this entry predicted — it would fail outright the
  moment anything invoked it. **Revised fix: delete the function.** Rewriting a
  fragile join in dead code is work with no consumer. Noticed while scoping the
  Accounts tab's "last seen" question (**F126**), which needed to know whether
  any `auth.users` exposure already existed. It does not.

#### F31 — stale comment in `UsageEvents._log`
- **Status:** fixed 2026-05-10 — comment rewritten to name
  `FOUNDING_TENANT.id` as the safety net and to note that Phase 3.3
  removed the column default. No behavior change.
- Lines 531-532 said "The DB column default is the final safety net" but
  Phase 3.3 removed all `tenant_id` column defaults including
  `usage_events.tenant_id`. The fallback to `FOUNDING_TENANT.id`
  (line 536) is now the actual safety net.
- **Fix:** update the comment.

#### F36 — `send-my-list` does not verify request user matches session user
- **Status:** **resolved 2026-05-27 (Phase 4.1 — fixed under the duplicate filing F54)** — status line corrected 2026-07-28. It had read bare "confirmed" for fourteen months of calendar entries, leaving the canonical findings index advertising an open authorization bypass that had in fact been closed. F36 and F54 are the **same defect filed twice**; F54 carries the fix record.
- **Verification (2026-07-28, against deployed source):** `send-my-list/index.ts:52–71` calls `/auth/v1/user` with the caller's JWT and returns 403 `"Forbidden — can only request your own list"` when `callerUser.id !== user_id`. An admin bypass was added later under F62 (admin "books are in" email) — an admin caller is permitted after an `is_admin` lookup, which is intended behavior, not a residual of this finding.
- The function *formerly* checked that only *some* session token was present, then trusted
  the `user_id` from the request body. An authenticated user can call
  this with any other user's user_id; the email goes to that other user
  (not the caller), so it's an annoyance/spam attack rather than data
  exfiltration, but it's still wrong.
- **Fix:** verify that the JWT's `sub` claim matches `user_id` in the
  body before sending.

### Trivial / info

#### F14 — redundant `idx_tenants_slug` index
- **Status:** **Resolved 2026-06-15** — `DROP INDEX public.idx_tenants_slug` executed on staging (5.2 S4). Prod never had this index (confirmed via `pg_indexes` 2026-06-15 — F64 item 8 no-op). Both environments now have only `tenants_pkey` + `tenants_slug_key` on `tenants`.
- Both `tenants_slug_key` (unique) and `idx_tenants_slug` (non-unique) indexed `tenants.slug`. The non-unique one could not serve a query better than the unique constraint's backing index.
- **Fix executed:** `DROP INDEX public.idx_tenants_slug;` on staging. No prod DDL needed.

#### F26 — `admin_preorders` view bypasses RLS but has no caller
- **Status:** fixed 2026-05-26 (Phase 4.1 C11) — view dropped and recreated with `security_invoker = true`; same column list, JOINs, and ORDER BY preserved. Grants tightened: `authenticated` SELECT only, `service_role` SELECT only, `anon` no grants. See also F49.
- `reloptions = null` means `security_invoker = false` default; view
  runs as owner and bypasses RLS on the underlying tables. View body
  has no tenant filter. **No application code currently queries the
  view** (admin.html uses direct `preorders` queries with an embedded
  catalog join).
- **Fix:** drop the view. If reinstated later,
  `CREATE VIEW admin_preorders WITH (security_invoker = true) AS ...` is
  the safe form.

#### F27 — both `pgcrypto` and `uuid-ossp` installed
- **Status:** open
- `catalog.id` and `preorders.id` use `uuid_generate_v4()` (uuid-ossp);
  every newer table uses `gen_random_uuid()` (pgcrypto). Both produce v4
  UUIDs. uuid-ossp is essentially legacy at this point.
- **Fix:** as part of any future schema migration touching `catalog` or
  `preorders`, change the column default to `gen_random_uuid()` and
  drop `uuid-ossp` once unused.

#### F29 — Supabase 416 workaround pattern recurs
- **Status:** **informational — never a defect; closed as an observation 2026-07-28.** Verdict clarified from the bare "doc-only" label, which read as an unfinished disposition.
- **Superseded in part by F82 (2026-07-08/09):** two of the three callsites named below — `Catalog.getPublishers()` and `Recommendations.getCatalogIds()` — no longer use the fixed count-first pattern at all. F82 replaced them with 1,000-row batch pagination that loops until a short read, because the fixed two-batch shape silently capped at 2,000 rows once the July 2026 catalog reached 2,776. The duplication this finding noted was therefore resolved by a correctness fix, not by the helper it proposed.
- The count-first-then-fetch pattern was repeated in
  `Recommendations.getCatalogIds`, `Catalog.getPublishers`, and
  `catalog.html`'s catalog fetch. Not a bug; just noteworthy that the
  pattern recurred without being encapsulated in a helper.
- **Fix (as filed):** if a fourth instance appears, factor into a
  `fetchWithRangeFallback` helper. Still reasonable guidance for any *new*
  paginated fetch; see F82 for the shape to copy.

#### F32 — CLAUDE.md page inventory missing two pages
- **Status:** **resolved 2026-07-28** — CLAUDE.md § Repository Structure now lists all 8 HTML files, each annotated with why it is or is not part of the shared-nav set.
- **Drifted further before it was fixed.** As filed the gap was 2 pages (6 listed / 8 real). By 2026-07-28 the block listed only **5** and the repo held **8** — `index.html` had joined `analytics.html` and `forgot-password.html` as unlisted. Verified by `ls *.html` against the block, not from memory.
- **Deliberately not "just add three lines":** the same file's § Files That Must Stay in Sync correctly names exactly 5 pages, because only those carry the shared nav and footer blocks. Listing all 8 flat would have implied the nav invariant applies to `index.html`, `analytics.html`, and `forgot-password.html`, which it does not. The inventory now marks the five-page sync set explicitly so the two lists can no longer be read as contradicting each other.
- **Original fix note (superseded):** out of scope for this document. Update CLAUDE.md's page
  inventory in a future session.

#### F33 — `claim_paper_account()` SQL function is unused
- **Status:** fixed 2026-05-26 (Phase 4.1 C3) — function dropped; confirmed absent from pg_proc. See also F21.
- The `claim-paper-customer` Edge Function reimplements the merge logic
  in TypeScript via REST. The SQL function has no caller in any code
  path read during this discovery pass.
- **Fix:** drop the function, or wire `claim-paper-customer` to call it
  via RPC for consistency.

#### F37 — Customer could DELETE fulfilled preorders via `Preorders.cancel`
- **Status:** fixed 2026-05-11 — added pre-DELETE fulfilled-check in
  `Preorders.cancel` (app.js) plus a defensive `.eq('fulfilled', false)`
  filter on the DELETE statement; `mylist.html` cancel button replaced
  with an "✓ In hand" chip on fulfilled rows.
- The original `Preorders.cancel` was an unconditional DELETE on the
  composite `(user_id, catalog_id)` key with no fulfilled-state check. A
  customer pressing Remove on a fulfilled row would destroy the audit
  trail (`fulfilled_at` timestamp). Surfaced during Phase 3.2 smoke
  testing; deferred to Phase 3.6 because the auto-fulfill rollout meant
  many more rows would carry `fulfilled = true` than before.
- **Where:** `Preorders.cancel` in `app.js`; cancel button render in
  `mylist.html`.
- **Fix:** as described in Status.

#### F38 — admin.html had labelless form inputs (DevTools a11y warning)
- **Status:** fixed 2026-05-11 — six inputs received `<label for="...">`
  associations (`deadline-input`, `admin-search`, `paper-new-name`,
  `paper-catalog-search`, `invite-name`, `invite-email`); a
  `.visually-hidden` utility class added to `style.css` for inputs whose
  visible cue was only a placeholder.
- Pre-existing accessibility gap. Cumulative DevTools warning of "No
  label associated with a form field" across the admin dashboard.
- **Where:** `admin.html`.
- **Fix:** as described in Status.

#### F39 — `arrivals` "this week" semantic mismatch (resolved in 3.8)

- **Severity:** HIGH (customer-visible)
- **Surface:** `app.js` `NavBubble.load`, `arrivals.html`, `admin.html` This Week tab
- **Discovered:** 2026-05-14 (post-3.7 soak)
- **Resolved:** Phase 3.8 — `docs/phase-3.8-pre-phase-4-hardening.md`

The three "this week" surfaces implemented three different rules:

| Surface | Pre-3.8 rule |
|---|---|
| `NavBubble.load` | 7-day rolling window (today → today + 7) |
| `arrivals.html` | Single Wednesday (`.eq` on `getThisWednesday()`) |
| `admin.html` This Week tab | Mon-Sat anchored on next Wednesday |

Customer-visible symptom: a reservation dated for next Wednesday caused the
nav badge to show "1" while `arrivals.html` showed "Nothing reserved this
week" — the badge counted next Wednesday's item as in-window; arrivals did
not. The same reservation was also out-of-window for the admin bagging tab.

Fix (phase 3.8): canonical rule is the Mon-Sun calendar week containing
today's local date. Shared `DateUtils.weekRange()` helper in `app.js`. All
three surfaces query the same `(start, end)` range. F28's callsites closed
as a side effect (no more `toISOString()` in date-math contexts).

Smoke pinned in `playwright/tests/04-arrivals-this-week.spec.ts` with
boundary-day seeds and a badge↔arrivals consistency assertion.

### Phase 4.1 findings (F45–F52)

Surfaced during the pre-cutover audit pass (2026-05-26). See `docs/phase-4.1-audit-findings.md` for full triage notes and raw SQL output.

#### F45 — `archive_stale_reservations` deployed as SECURITY INVOKER
- **Status:** fixed 2026-05-26 (Phase 4.1 C12) — promoted to SECURITY DEFINER + `SET search_path = public`. See F24.
- Inconsistent with sibling tenant-aware DEFINER functions. Likely Phase 1.3 / Phase 3.3 inline-patch oversight.
- **Where:** `archive_stale_reservations(uuid, date, text)` in pg_proc.
- **Fix:** two-step `ALTER FUNCTION ... SECURITY DEFINER; ALTER FUNCTION ... SET search_path = public`.

#### F46 — `preorders` admin policy uses recursive EXISTS subquery
- **Status:** fixed 2026-05-26 (Phase 4.1 C9) — EXISTS replaced with `current_user_is_admin()`.
- `admins manage tenant preorders` used `EXISTS (SELECT 1 FROM user_profiles WHERE id = auth.uid() AND is_admin = true)` — the documented anti-pattern from CLAUDE.md known issues (RLS recursion risk). The 2026-05-10 F16 hot-fix added `tenant_id` scoping but did not convert the EXISTS pattern.
- **Where:** RLS policy `admins manage tenant preorders` on `preorders`.
- **Fix:** replace EXISTS clause with `current_user_is_admin()`.

#### F47 — `notify-customers` Edge Function has no caller authentication check
- **Status:** fixed 2026-05-27 (Phase 4.1 C10a) — in-body auth added; platform JWT flipped OFF; callerTenantId scopes both tenant filters.
- Any HTTP request could trigger a bulk email blast to all founding-tenant customers. Severity HIGH (platform JWT was ON but in-body auth was absent; blast scoped to founding tenant regardless of caller).
- **Where:** `notify-customers/index.ts`.
- **Fix:** hoisted env vars to function scope; added `/auth/v1/user` JWT verify + admin profile check + callerTenantId resolution before any data operation. Both tenantFilter constructions now use callerTenantId.

#### F48 — `reservation_history` and `user_profiles` user SELECT policies lack tenant scope
- **Status:** fixed 2026-05-26 — `reservation_history` fixed in C2 (both policies); `user_profiles` fixed in C9 (user SELECT policy).
- `users view own history` and `users view own profile` filtered by `auth.uid()` only. Defense-in-depth gap: low practical risk under single-tenant (auth UUIDs globally unique), but inconsistent with multi-tenant hygiene.
- **Where:** RLS policies on `reservation_history` and `user_profiles`.
- **Fix:** add `AND tenant_id = current_tenant_id()` to both user-facing SELECT policies.

#### F49 — `admin_preorders` VIEW present on staging contrary to pre-multitenancy-state.md § 4
- **Status:** fixed 2026-05-26 (Phase 4.1 C11) — view rebuilt with `security_invoker = true`; grants tightened. See F26.
- Pre-multitenancy-state.md § 4 claimed staging lacked this view. View existed with default `security_invoker = false` and full grants to `anon` / `authenticated`. No tenant WHERE clause in view body.
- **Where:** `admin_preorders` VIEW; `pre-multitenancy-state.md` § 4 doc discrepancy.
- **Fix:** recreate with `security_invoker = true`; grant SELECT to `authenticated` and `service_role` only. Doc discrepancy flagged for review during 4.2 pre-flight.

#### F50 — `claim-paper-customer` PATCH operations not scoped by tenant
- **Status:** fixed 2026-05-27 (Phase 4.1 C10b) — both PATCH URLs now include `&tenant_id=eq.${callerTenantId}`.
- PATCH to `preorders` and `subscriptions` filtered by `user_id` only. Service-role key bypasses RLS. A canary-tenant admin could merge a founding-tenant paper account cross-tenant.
- **Where:** `claim-paper-customer/index.ts`.
- **Fix:** added `tenant_id` to admin profile select; extracted callerTenantId; appended `&tenant_id=eq.${callerTenantId}` to both PATCH URLs.

#### F51 — `send-my-list` catalog month query uses hardcoded `FOUNDING_TENANT_ID`
- **Status:** fixed 2026-05-27 (Phase 4.1 C10c) — catalog and preorders queries now use callerTenantId resolved from user profile.
- Catalog month and preorders queries both hard-pinned to founding tenant. Canary-tenant user would receive founding-tenant content.
- **Where:** `send-my-list/index.ts`.
- **Fix:** added `tenant_id` to profile select; callerTenantId extracted with FOUNDING_TENANT_ID fallback; both queries scoped by callerTenantId.

#### F52 — 5 of 8 Edge Functions not committed to the repo
- **Status:** resolved 2026-05-27 (Phase 4.1 Session 2) — all 5 EF sources committed to repo. All 8 EFs now tracked.
- `approve-customer`, `claim-paper-customer`, `notify-customers`, `reset-password`, and `send-my-list` existed only in Supabase staging deployment. 4.6 tagged-commit redeploy prerequisite now met.
- **Where:** repo `supabase/functions/`.
- **Fix:** committed all 5 missing EF sources in Session 2 opening commit. Deploy workflow documented: patch in repo → copy to `C:\Users\richa\supabase\functions\` → deploy from CLI project root.

#### F53 — `create-paper-customer` JWT verification ON despite having in-body auth
- **Status:** fixed 2026-05-27 (Phase 4.1 C13) — JWT verification flipped OFF via Supabase dashboard. In-body auth (lines 42–68) is the sole gate.
- Redundant platform JWT + in-body auth; JWT ON means the platform intercepts before in-body check runs, making the check unreachable for unauthenticated requests.
- **Where:** Supabase dashboard → Edge Functions → `create-paper-customer` → JWT verification toggle.
- **Fix:** dashboard toggle only; no source changes.

#### F54 — `send-my-list` authorization gap: any authenticated user can request any user's list
- **Status:** fixed 2026-05-27 (Phase 4.1, separate commit before C10c) — `/auth/v1/user` call added with caller's JWT; `callerUser.id !== user_id` returns 403.
- Auth check verified session token present but used service key to look up user_id — did not verify the caller IS that user. Any logged-in user could trigger a pull-list email to any other user's address.
- **Where:** `send-my-list/index.ts`.
- **Fix:** added `SUPABASE_ANON_KEY` env var; call `/auth/v1/user` with caller's JWT; assert `callerUser.id === user_id` before proceeding.

### Phase 4.4 findings (F55–F58)

Surfaced during the 4.4 cutover sub-deploy (2026-05-31).

#### F55 — production has 5 `analytics_*` views with no staging counterpart
- **Status:** resolved — dropped on production 2026-06-10 (Phase 4.8 H1, drop branch). `analytics.html` queries `usage_events` directly via PostgREST; no view reference anywhere in the codebase. Views were dead code predating the client-side analytics implementation.
- Prod had `analytics_daily_events`, `analytics_top_cancelled`, `analytics_top_reserved`, `analytics_top_subscribed`, `analytics_user_activity` as plain untenanted views. All 5 dropped; `pg_views` verify returned zero rows; `analytics.html` renders post-drop.
- **Where:** production database `public` schema; parent plan line 148.
- **Fix:** dropped (drop branch confirmed by 4.8 § 1.1 audit). Structural-diff criterion (parent plan line 190) no longer blocked by this finding.

#### F56 — `claim_paper_account(uuid, uuid)` still present on production
- **Status:** resolved — dropped on production 2026-06-10 (Phase 4.8 H2). `pg_proc` verify returned zero rows.
- The `claim-paper-customer` Edge Function reimplements the merge logic in TypeScript. SQL function had no caller; only reference was a comment at `app.js:945`.
- **Where:** production `public.claim_paper_account(uuid, uuid)` in pg_proc.
- **Fix:** `DROP FUNCTION public.claim_paper_account(uuid, uuid);` executed 4.8 H2.

#### F57 — `generate_invite_link(text, text)` present on production, absent on staging
- **Status:** resolved — dropped on production 2026-06-10 (Phase 4.8 H3). `pg_proc` verify returned zero rows. Invite flow (via `invite-customer` Edge Function) verified working post-drop.
- `SECURITY DEFINER` function; no caller in any current code path. Used pre-multitenancy `is_admin()` helper and hardcoded the staging URL in the invite link — confirmed dead code predating the current invite flow.
- **Where:** production `public.generate_invite_link(text, text)` in pg_proc.
- **Fix:** `DROP FUNCTION public.generate_invite_link(text, text);` executed 4.8 H3.

#### F58 — staging RLS lacks an authenticated-key admin-write policy on `user_profiles`
- **Status:** **resolved 2026-06-11 (5.0 S3) — Branch A.** Code-path audit confirmed `Users.suspend` (`app.js:916`) and `Users.deleteProfile` (`app.js:925`) are authenticated-client PostgREST calls with no EF in path; `admin.html:1608` Decline calls `deleteProfile` directly. Staging pre-fix had 3 SELECT/UPDATE policies on `user_profiles` — no admin write policy — causing Decline to silently no-op. `admins manage tenant profiles` (ALL, `TO authenticated`, same definition as prod) created on staging. Functional verify: Decline on a disposable pending account — row removed and stays gone on reload (pre-fix: silently reappeared). `Users.suspend` has no admin UI entry point in current `admin.html` (no Users tab); the ALL policy covers the UPDATE path by definition. Playwright 15/15 green after; `current_user_is_admin()` gate confirmed not to widen non-admin access. Staging `user_profiles` policy surface now at prod parity.
- **Note:** post-Decline, the `auth.users` row survives (no cascade in profile→auth direction); declined user can sign in via forgot-password and sees a blank shell. Full cleanup requires a separate auth-user delete via GoTrue admin API. This is the intended behavior under F64 item 5 Option A (profile-first, preorder-blocking) — see F64 item 5 disposition.
- **Where:** staging RLS on `user_profiles`; `app.js` `Users.suspend` and `Users.deleteProfile`; `admin.html` line 1608.
- **Fix:** add `admins manage tenant profiles` ALL policy to staging — executed 5.0 S3.

### Phase 4.7 findings (F59–F62)

Surfaced during the 4.7 soak (2026-06-01 / 2026-06-02).

#### F59 — Customer reservation cohort lost during Phase-4 cutover window (recovered)
- **Status:** closed — data recovered 2026-06-01; prevention added to deployment workflow.
- **Severity:** high — store-wide data loss (330 reservations across 9 customers).
- Customer reservations created ~2026-04-29 → 2026-05-28 failed to persist to production `preorders`. Root cause: PR #49 (`staging → main` three-way merge) kept `main:app.js` at the pre-Phase-3 regressed version (43 KB) instead of the staging version (49 KB with `TenantContext`). Merge base `cab5dca` already contained staging's `app.js`; the three-way merge saw no delta on that side and silently kept the regressed copy. The deployed app did not write tenant-aware reservations (no `tenant_id`), so all INSERTs failed silently at the NOT-NULL constraint without a visible error to customers. Hotfix `554aec1` corrected `app.js` 2026-05-30; gap-period data was not carried forward.
- **Recovery (2026-06-01):** source = 2026-05-30 DBeaver per-table export (`backups/pulllist/dump-postgres-202605302059.backup`). Parsed `preorders` COPY data; filtered 330 in-window rows (2026-04-29 → 2026-05-28); re-resolved each stale `catalog_id` to current prod catalog via ItemCode (all 330 RESOLVED, 0 unresolved); re-stamped `tenant_id` to founding UUID; preserved original `created_at`. Brian Moss spot-check oracle (23 Jul/Aug rows) confirmed. App-side: Brian's My List shows 23 items; 44 upcoming arrivals correct.
- **Prevention:** post-merge app-file diff assertion + post-deploy write-smoke added to `CLAUDE.md` § Standard Deployment Workflow and `docs/phase-4.6-edge-functions-cutover.md` §4.
- **Where:** production `preorders` table; PR #49 merge; `app.js` TenantContext regression.

#### F60 — `notify-customers` rejects service-role callers from import script (resolved)
- **Status:** closed — fixed and redeployed 2026-06-02.
- **Severity:** medium — June catalog notification not sent on first post-recovery Tuesday import; admin workaround available (send from admin UI).
- **Root cause:** `notify-customers` authenticates callers by calling `/auth/v1/user` with the provided Bearer token. `import.js` uses `Authorization: Bearer <service_role_key>` for all Supabase calls (required for RLS bypass on catalog/shipment writes). A service-role JWT is not a user session token, so `/auth/v1/user` returns 401 and the function returned `{"error":"Invalid auth"}`. This was always broken for the import→EF notification path but was never exercised (4.6 first import answered `n` to notifications).
- **Fix:** Added a JWT role-claim bypass in `notify-customers/index.ts`: decode the Bearer token's payload and check `payload.role === 'service_role'`. If true, skip the user auth check and resolve `callerTenantId = FOUNDING_TENANT_ID`. The user-JWT path (admin UI calls) is unchanged. Safe because platform JWT verification is ON for this function — only Supabase-signed tokens reach the body.
- **Also fixed:** platform JWT verification for `notify-customers` was ON (inconsistent with project pattern); left ON because it makes the role-claim check safe.
- **Where:** `supabase/functions/notify-customers/index.ts` lines 26–44; `C:\Users\richa\supabase\functions\notify-customers\index.ts` (CLI deploy source).
- **Commits:** `2488c8c` (key-comparison attempt), `2e924d8` (JWT role-claim approach, the effective fix).

#### F62 — `send-my-list` F54 identity check blocks admin "books are in" email (resolved)
- **Status:** fixed 2026-06-10 (Phase 4.7 soak, separate commit).
- **Severity:** medium — admin "This Week" bagging tab send-email button returned 403 for all customers; admin workaround was none.
- **Root cause:** F54 fix added `callerUser.id !== user_id → 403`. When an admin sends the email from `admin.html`, the bearer token is the admin's session but `user_id` is the target customer's id — the check always trips.
- **Fix:** `send-my-list/index.ts` — on identity mismatch, fetch caller's `user_profiles.is_admin`; allow if `true`, otherwise retain 403. Own-list path (mylist.html) is unchanged.
- **Where:** `supabase/functions/send-my-list/index.ts` lines 48–68.

#### F61 — Brave/iOS suppresses `window.confirm()` on mylist.html Remove button (resolved)
- **Status:** resolved — in-page modal deployed to prod 2026-06-10 (Phase 4.8 H5). Staging commit `3c212ff`; prod promotion `92bf7dc`. Verified on Brave Mobile; prod write-smoke passed. `mylist.html:1081` (unsubscribe guard, same defect class) deferred per Rick — tracked as F65.
- **Severity:** low — Brave/iOS users cannot cancel reservations via My List; other browsers unaffected; no data integrity impact.
- **Root cause:** Brave on iOS suppresses native `window.confirm()` dialogs in some contexts (treated as unwanted popups). The cancel-guard in `mylist.html` used `if (!confirm("Remove this reservation?")) return;` — this silently returns `false` on Brave/iOS, blocking all removals.
- **Fix:** Replaced `window.confirm()` with a promise-based in-page modal (reuses existing `.modal-overlay`/`.modal` CSS; `confirmDialog()` helper added page-local). The unsubscribe guard at `mylist.html:1081` was deferred; file F65 as a follow-up.
- **Where:** `mylist.html` — Remove button click handler (line 947 post-fix).

### Phase 4.8 findings (F63–F65)

Surfaced during the 4.8 H4 structural diff and H5 review (2026-06-10).

#### F63 — Staging RLS policies missing `TO authenticated` role qualifier
- **Status:** **resolved 2026-06-11 (5.0 S1)** — all 14 staging policies altered to `TO authenticated`; pre-capture confirmed 21 rows (14 `{public}`, 7 `{authenticated}`); post-capture confirmed 21 rows all `{authenticated}`; full Playwright suite 15/15 green including tenant-isolation specs. Staging `pg_policies` now at parity with prod (minus the F58 row, scheduled S3).
- **Assessment (2026-06-10):** Adding `TO authenticated` is strictly more restrictive — it removes the policy's applicability to `anon` (and other roles), never widens it. Every affected policy's USING/WITH CHECK clause already requires an authenticated session (`current_tenant_id()`, `current_user_is_admin()`, or `auth.uid()` all return NULL/false without one), so no behavior change is expected for any existing flow; no anon code path touches the affected table/verb combinations. Prod is the correct side of this divergence — the fix direction is staging→prod parity, so the Phase-4 criterion (prod posture correct) is satisfiable with this finding annotated. Fix session pre-flight: capture staging `pg_policies` before/after; run full Playwright suite after.
- **14** staging `CREATE POLICY` statements lack the `TO authenticated` role clause and therefore apply to the `public` role (all roles including `anon`). Prod policies all explicitly include `TO authenticated`. Systematic divergence across **8** tables, not an isolated omission. *(Counts corrected 2026-06-10 Phase 5 planning: originally filed as "13 across 9 tables"; the 2026-06-10 staging dump enumerates 14 policies across the 8 tables listed below — the affected-policies list was already correct and complete.)* Functional impact in current single-tenant setup is low — `anon` users cannot satisfy `current_tenant_id()` USING clauses without a valid session — but the missing qualifier means staging's security posture differs from prod.
- **Affected policies (staging lacks `TO authenticated` while prod has it):** `app_settings` (admins delete, admins update), `preorders` (admins manage, users manage), `reservation_history` (admins view, users view), `settings` (admins update), `subscriptions` (admins view, users manage), `tenants` (admins update), `usage_events` (admins read), `user_profiles` (admins view, users update, users view own profile).
- **Where:** staging `CREATE POLICY` DDL for 9 tables; visible in 2026-06-10 `pg_dump --schema-only` output.
- **Fix:** add `TO authenticated` to the 14 staging policies that lack it, bringing staging into parity with prod. Verify no functional regression (all existing tests pass after; anon-role access to affected tables should remain blocked by `current_tenant_id()` returning NULL).

#### F64 — Pre-Phase-4 DDL structural divergences (prod vs staging)
- **Status:** **resolved 2026-07-28 — all 8 items closed; rollup line advanced.** Every item below reached a terminal disposition between 2026-06-11 and 2026-06-16 (items 1–3, 6, 7 on 06-11 at 5.0 S2; item 4 on 06-11 at 5.0 S4; item 8 no-op 06-15 at 5.2 S4; item 5 on 06-16 at 5.4 S0), but this parent status was never advanced from "open" — a bookkeeping residue, not outstanding work. No new verification was performed on 2026-07-28; this flip rests entirely on the per-item evidence already recorded below, each of which cites its own `pg_constraint` / `information_schema` check.
- **Original assessment (2026-06-10, Phase 4 completion audit):** **no item blocks Phase 4 closure** (all 8 pre-date Phase 4 and none affects the migrated multi-tenant surface). Dispositions below. **Scheduled (2026-06-10 Phase 5 planning):** items 1–3/6/7 → 5.0 S2; item 4 → 5.0 S4 (with F66); item 5 → decision at 5.0 S3, DDL deferred to the parent § Deferred-DDL Register; item 8 → sub-deploy 5.2 (`phase-5.0-pre-phase-5-housekeeping.md`, `phase-5-second-tenant-onboarding.md`).
- **Per-item dispositions (2026-06-10 assessment):**
  1. `catalog.price_usd` precision — **closed 2026-06-11 (5.0 S2).** Altered staging → `numeric(6,2)`. Note: required DROP + recreate of `admin_preorders` view (view depends on `price_usd`); view recreated with `security_invoker=true` and grants restored to SELECT-only for `authenticated`/`service_role` (Supabase default-privilege machinery auto-grants ALL on new views — REVOKE ALL then selective GRANT required). Verified: `information_schema.columns` precision `6,2`; view and grants confirmed.
  2. `catalog_distributor_check` — **closed 2026-06-11 (5.0 S2).** Constraint added to staging; pre-flight confirmed exactly `{Lunar, PRH}`; verified via `pg_constraint`.
  3. `preorders_quantity_check` — **closed 2026-06-11 (5.0 S2).** Constraint added to staging; pre-flight confirmed 0 bad rows; verified via `pg_constraint`.
  4. `preorders_catalog_id_fkey` cascade — **closed 2026-06-11 (5.0 S4).** Prod FK dropped and re-added as `REFERENCES public.catalog(id)` (NO ACTION, matching staging). Pre-flight confirmed 0 orphaned catalog references. Verified `confdeltype = a`. Paired with F66 guard in same sitting — silent-deletion risk eliminated on prod.
  5. `preorders_user_id_fkey` target — **resolved 2026-06-16 (5.4 S0).** Decision (5.0 S3, 2026-06-11): **Option A — profile-first, preorder-blocking (staging shape is canonical).** Prod DDL executed 2026-06-16: pre-flight confirmed `blocking_rows = 0` (no preorders with an orphaned `user_id`); `DROP CONSTRAINT preorders_user_id_fkey; ADD CONSTRAINT preorders_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.user_profiles(id);` executed on prod; verified `confdeltype = 'a'` (NO ACTION), `references = user_profiles`. Both envs now canonical. Rationale: profile DELETE fails loudly if the customer has open preorders — this is an intentional guard, not a bug. Admin must cancel preorders first, then Decline. Auth.users row cleanup remains a separate GoTrue admin API step (can be wired to the Decline button in a later sub-deploy).
  6. `app_settings_updated_by_fkey` — **closed 2026-06-11 (5.0 S2).** FK added to staging; pre-flight confirmed 0 orphaned `updated_by` values; verified via `pg_constraint`.
  7. `user_profiles_id_fkey` → `auth.users` ON DELETE CASCADE — **closed 2026-06-11 (5.0 S2).** Pre-flight found 44 orphaned `user_profiles` rows — all Playwright test fixtures (`pw-*@example.test`, founding tenant, 0 dependent preorders/subscriptions); deleted inline. FK then added; verified `confdeltype = c`. Post-add: future Playwright teardown auth-user deletes will cascade automatically.
  8. `idx_tenants_slug` — **dispositioned no-op 2026-06-15 (5.2 S4).** The `resolve_tenant_by_slug` RPC uses a single-row equality lookup (`WHERE slug = $1`) that `tenants_slug_key` (the unique constraint's backing btree) already serves optimally on both envs. Adding a second index would be redundant. Staging `idx_tenants_slug` dropped (F14 resolved); prod never had it.
- **Enumerated differences (prod vs staging) from 2026-06-10 pg_dump:**
  1. `catalog.price_usd`: prod `numeric(6,2)` vs staging `numeric` (no precision/scale)
  2. `catalog`: prod has `CONSTRAINT catalog_distributor_check CHECK (distributor = ANY (ARRAY['Lunar', 'PRH']))` — staging does not
  3. `preorders`: prod has `CONSTRAINT preorders_quantity_check CHECK ((quantity >= 1) AND (quantity <= 99))` — staging does not
  4. `preorders_catalog_id_fkey`: prod `ON DELETE CASCADE`; staging default (NO ACTION)
  5. `preorders_user_id_fkey`: **prod** `REFERENCES auth.users(id) ON DELETE CASCADE`; **staging** `REFERENCES public.user_profiles(id)` (different target table, no ON DELETE) — most material difference: different cascade path on user delete
  6. `app_settings_updated_by_fkey`: prod has `FOREIGN KEY (updated_by) REFERENCES auth.users(id)`; staging does not
  7. `user_profiles_id_fkey`: prod has `FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE`; staging does not
  8. `idx_tenants_slug`: staging has index on `tenants(slug)`; prod does not
- **Note on F19:** `is_admin()` function is also prod-only (pre-existing F19 finding); included for completeness but tracked under F19.
- **Where:** pg_dump `--schema-only` output for both environments, 2026-06-10.
- **Fix:** assess each item individually; most are additive prod constraints staging lacks (safe to add). Item 5 FK target requires careful analysis — cascade behaviour differs between environments for user deletes.

#### F65 — `subscriptions.html` unsubscribe guard uses `window.confirm()` (Brave/iOS suppression)
- **Status:** **resolved 2026-06-11 (5.0 S6).** In-page `confirmDialog()` modal deployed to both `subscriptions.html` (CSS + overlay HTML + helper + call site) and `mylist.html:1081` (call-site conversion only — modal infrastructure already present from F61). Staging commit `acf7981`; Playwright 15/15 green (updated spec 05 clicks `#confirm-overlay.open #confirm-ok`); staging verified by Rick. Prod PR #56 merged; prod commit `88c0e02`. Write-smoke passed on Brave iOS: subscriptions unsubscribe modal confirmed. Zero native `confirm(` remaining in either file.
- **Severity:** low — Brave/iOS users cannot unsubscribe via the Subscriptions page; other browsers unaffected; no data integrity impact.
- **Root cause:** `subscriptions.html:419` uses `if (!confirm(\`Unsubscribe from "${btn.dataset.series}"?\`)) return;` — Brave/iOS suppresses native confirm dialogs, silently blocking the unsubscribe action.
- **Fix:** replace with in-page modal (same `confirmDialog()` pattern applied in F61 fix on `mylist.html`). Scope: `subscriptions.html` (CSS + overlay + helper + call site) **and** `mylist.html:1081` (call-site conversion only — modal infrastructure already on the page from F61); no `app.js` change needed.
- **Where:** `subscriptions.html:419` and `mylist.html:1081` — Unsubscribe button click handlers.

### Phase 4 completion audit findings (F66)

Surfaced during the Phase 4 completion audit (2026-06-10).

#### F66 — `delete_dropped_catalog_items` lacks preorder guard (latent silent reservation deletion on prod)
- **Status:** **resolved 2026-06-11 (5.0 S4).** Guard line `AND id NOT IN (SELECT catalog_id FROM preorders WHERE tenant_id = p_tenant_id)` added via `CREATE OR REPLACE` on both staging and prod. Pre-captures confirmed bodies were identical and matched § 1.3 (staging confirmed clean; prod re-confirmed after editor-switching incident). Post-apply verify on both envs: body contains exactly the one added line; `proacl` unchanged. Prod `preorders_catalog_id_fkey` aligned to NO ACTION (F64 item 4, same sitting) — silent-deletion risk via CASCADE removed.
- **Severity:** low today (unreachable), high if activated — silent customer-reservation data loss on prod.
- **Root cause:** Function body (verified identical on prod and staging via `pg_proc`, 2026-06-10) is `DELETE FROM catalog WHERE tenant_id = … AND catalog_month = … AND item_code != ALL(p_item_codes)` with **no** `id NOT IN (SELECT catalog_id FROM preorders …)` guard — unlike `purge_stale_catalog`, which has one. On prod, `preorders_catalog_id_fkey` is `ON DELETE CASCADE` (F64 item 4), so an unguarded catalog delete silently removes the referencing reservations; on staging (`NO ACTION`) the same delete would fail loudly with an FK violation.
- **Why it is currently unreachable:** the import script calls the function only when `isNewMonth` is true (`import-staging.js` `refreshCatalog`, same in prod `import.js` post-4.5), and `isNewMonth = confirmedMonth > max(catalog_month)` guarantees no rows for `confirmedMonth` existed before the just-completed upsert — every surviving row's `item_code` is in `p_item_codes`, so the DELETE matches zero rows. Auto-reserve runs after the call, so no reservations exist on the target month at delete time either.
- **Activation risk:** wiring the function into same-month refreshes — which is what its description in § 6.2 ("drop titles that have disappeared from this month's distributor catalog between imports") implies it was meant for — would make every weekly re-import a silent-deletion opportunity for reserved-then-dropped titles on prod.
- **Fix (scheduled with F64 item 4, pre-Phase-5 housekeeping):** add the preorder guard (`AND id NOT IN (SELECT catalog_id FROM preorders WHERE tenant_id = p_tenant_id)`) to the function on both envs, and align prod `preorders_catalog_id_fkey` to `NO ACTION` to match the documented design (§ preorders Notes).
- **Where:** `public.delete_dropped_catalog_items(uuid, text, text[])` on both databases; call site `import-staging.js` / `import.js` `refreshCatalog()`.

---

### Phase 5.1 findings (F67–F69)

#### F67 — Edge Function hardcoded app URLs — hosting-migration continuity
- **Status:** **Resolved 2026-06-15 (5.2 S5).** `APP_BASE_URL` secret set on both projects (staging: `https://staging.pulllist.pages.dev`; prod: `https://pulllist.app`). All five functions updated to `Deno.env.get('APP_BASE_URL') ?? 'https://pulllist.app'` and redeployed. Staging verify: invite email link → `redirect_to=https://staging.pulllist.pages.dev/index.html` ✅. Prod verify: reset-password email link → `https://pulllist.app/forgot-password...` ✅. **Also fixed during prod deploy:** `reset-password` had JWT verification ON on prod (same issue as F68/`register-customer`) — set to OFF; function is a public endpoint by design. Source committed to repo at `de982e5`.
- **Severity:** High (approve-customer, register-customer, invite-customer — prod magic-link emails point at staging Supabase project; token generated by prod project fails `verifyOtp` against staging client — pre-existing live defect). High (reset-password — `redirect_to` uses an anomalous host path that 404s — pre-existing live defect). Low (notify-customers — current URL correct today; becomes stale after `pulllist.app` domain migration).
- **Functions and values (staging branch = main branch; both projects confirmed identical at S1 — Rick paste 2026-06-11):**

  | Function | Lines | Value | Impact |
  |---|---|---|---|
  | `approve-customer` | `index.ts:13–15` | `STAGING_BASE = 'https://mrcyberrick.github.io/comic-preorder-staging'` | Prod approval email magic links point at staging GH Pages (different Supabase project); `verifyOtp` fails for real prod customers |
  | `register-customer` | `index.ts:29–31` | same | Prod welcome/pending email magic links non-functional for prod customers |
  | `invite-customer` | `index.ts:1–3` | same | Prod invite email links non-functional for prod customers |
  | `reset-password` | `index.ts:1–2` | `STAGING_BASE = 'https://mrcyberrick.us/comic-preorder-staging'` | Anomalous host — `/comic-preorder-staging/` does not exist under `mrcyberrick.us`; all password reset emails send a link that 404s |
  | `notify-customers` | `index.ts:163` | `https://mrcyberrick.us/comic-preorder/catalog.html` (hardcoded inline) | Correct for current prod URL; becomes stale after `pulllist.app` domain migration if not updated |

- **Evidence:** Repo `staging` and `main` branch values confirmed identical (`git show main:…` 2026-06-11). Deployed prod sources confirmed matching staging branch values (Rick paste, 2026-06-11, S1). Pre-existing defects — not introduced by 5.1.
- **5.1 continuity:** EF source changes are out of scope for 5.1 per parent plan (§ 3 Out of scope). GH Pages kept warm until 5.5 — frozen staging copy at `mrcyberrick.github.io/comic-preorder-staging/` continues serving (hits staging Supabase project; token mismatch for prod customers remains). `_redirects` on `pulllist.app` covers legacy bookmark paths. Reset-password 404 is pre-existing and independent of this migration.
- **Fix:** Add `APP_BASE_URL` secret to each Supabase project's Edge Functions → Secrets (staging project: `https://staging.pulllist.pages.dev`; prod project: `https://pulllist.app`). Replace all five hardcoded constants/inline values with `Deno.env.get('APP_BASE_URL')`. Staging deploy first; prod after staging smoke passes.
- **Where:** `supabase/functions/approve-customer/index.ts:13–15`, `register-customer/index.ts:29–31`, `invite-customer/index.ts:1–3`, `reset-password/index.ts:1–2`, `notify-customers/index.ts:163`.

#### F68 — `register-customer` Supabase cron webhook returning 401 (prod)
- **Status:** **Resolved 2026-06-11** — JWT verification turned OFF in Supabase prod dashboard; MailerLite webhook confirmed 200.
- **Severity:** Medium — MailerLite → `register-customer` webhook ("PROD APP ONBOARDING") was failing 401 on every call; new customer self-registration emails were not being sent.
- **Root cause:** JWT verification was **ON** for `register-customer` in the Supabase prod project, so Supabase's platform layer rejected all MailerLite webhook POSTs with `UNAUTHORIZED_NO_AUTH_HEADER` before the function code ran. The function's own `?secret=` query-parameter auth is the correct gate; platform-level JWT must be OFF (off-plus-in-body-auth pattern per CLAUDE.md).
- **Fix:** Supabase prod dashboard → Edge Functions → `register-customer` → **Verify JWT: OFF**. Confirmed: probe `curl -X POST ...?secret=<MAILERLITE_WEBHOOK_SECRET>` returned `{"error":"No valid email in payload"}` (400, past the auth gate); MailerLite test webhook → 200. Pre-existing defect — not caused by 5.1.
- **Where:** Supabase prod project → Edge Functions → `register-customer` → JWT verification setting.
- **Staging parity confirmed 2026-06-11:** unauthenticated empty-body POST to the staging `register-customer` endpoint returned the function's own `{"error":"Unauthorized"}` (401 from the in-function `?secret=` gate at `index.ts:56–58`) rather than the platform's `{"msg":"Missing authorization header"}` — the function code ran, so platform JWT verification is OFF on staging too. Both environments match the off-plus-in-body-auth pattern.

#### F69 — MailerLite webhook secret committed to public repo (F68 doc entry)
- **Status:** **Resolved 2026-06-11** — secret rotated in Supabase prod + MailerLite webhook URL; burned value confirmed rejected (401 probe); end-to-end re-verified same session: landing page (`yunzoi.subscribepage.io`) → MailerLite `subscriber.created` → prod `register-customer` → 200, auth user + pending `user_profiles` row created (test user `9777c8e4-bdea-4e30-b4e4-ad27e764880a`, deleted post-test). Filed 2026-06-11 (discovered during 5.1 soak-prep verification, out of 5.1 scope; Rick approved filing).
- **Severity:** High — the live `MAILERLITE_WEBHOOK_SECRET` value was committed in this file's F68 entry (line ~2220, commits `ea41fc9` / `a30a8ae`, 2026-06-11) and pushed to the **public** `mrcyberrick/comic-preorder` repo (`staging` branch). With `register-customer` platform JWT verification OFF (correct per F68), the query-param secret is the *only* gate: anyone holding it can POST crafted MailerLite-style payloads to the prod endpoint, creating auth users + `user_profiles` rows in the founding tenant and triggering magic-link emails.
- **Exposure scope:** Working-tree occurrence redacted (commit `8559396`), but the literal value remains in public git history (`ea41fc9`, `a30a8ae`) — treat the value as burned. Not present on `main` (F68 docs not yet promoted). **Staging confirmed on a different secret value** (burned-value probe against staging → 401 at the gate, 2026-06-11) — no staging rotation needed.
- **Fix (executed 2026-06-11):** New secret generated by Rick (never entered chat/repo) → Supabase prod → Edge Functions → Secrets → `MAILERLITE_WEBHOOK_SECRET` updated → MailerLite webhook "PROD APP ONBOARDING" URL updated → verified: curl with new secret reached email validation (400 past gate); burned secret → 401; full e2e signup created prod account. Never commit the secret value anywhere; docs reference it only as `<MAILERLITE_WEBHOOK_SECRET>`.
- **Operational notes (debugging detour, recorded for next time):** MailerLite `subscriber.created` fires only for *new* subscriber records — re-submitting the landing-page form with an already-known email fires nothing (no webhook call, no function log). Test with fresh `+alias` emails or delete the subscriber first. A second MailerLite webhook ("Application onboarding") points at the **staging** `register-customer`; webhook active/deactivated states were being toggled for testing during this session — final intended state: prod webhook Active, staging webhook per Rick's testing needs.
- **Where:** Supabase Edge Functions Secrets (prod `plgegklqtdjxeglvyjte`, staging `puoaiyezsreowpwxzxhj` if shared); MailerLite webhook "PROD APP ONBOARDING"; this file's F68 entry (redacted 2026-06-11).

### Phase 5.2 findings (F71)

#### `resolve_tenant_by_slug` RPC — contract and security rationale (S1, 2026-06-15; extended to 4-col 5.3 S1)
- **Status:** Created on staging 2026-06-15 (5.2 S1); extended to 4-col on staging 2026-06-15 (5.3 S1); prod RPC to be extended at 5.3 S6. Staging 4-col anon-contract verified (see below).
- **Contract (as of 5.3):** `RETURNS TABLE (id uuid, slug text, display_name text, branding jsonb)` `LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp` — returns `id, slug, display_name, branding`. `REVOKE ALL FROM PUBLIC; GRANT EXECUTE TO anon, authenticated`. **`settings` is never returned.**
- **Why `branding` is returned (5.3 decision):** Branding is public display data — name, colors, and logo are exactly what an anon visitor's landing page must render. The config-leak concern from 5.2 applies to `settings` only; `branding` is intentionally public.
- **Why `settings` is never returned:** `settings` may carry non-public config; it has no client render path and is not branding. The projection is `id, slug, display_name, branding` and nothing else.
- **Why exposing tenant `id` (UUID) to anon is safe:** Writes are gated by `WITH CHECK (tenant_id = current_tenant_id())`, where `current_tenant_id()` derives from the authenticated user profile — never from a client-supplied id. For anon callers, `current_tenant_id()` returns NULL → all writes blocked. Knowing a tenant UUID grants no write capability.
- **No status filter today:** `tenants` has no `status`/`active` column. If one is added, the RPC must filter to active tenants only.
- **Verified 2026-06-15 (staging, 5.2 S1 — 3-col):** `pg_get_functiondef` shows `STABLE SECURITY DEFINER`, `SET search_path TO 'public', 'pg_temp'`, exactly three columns. `proacl = {postgres=X/postgres, anon=X/postgres, authenticated=X/postgres, service_role=X/postgres}` — no bare `=X` (PUBLIC). Anon `curl.exe` → `raysandjudys` → one object, exactly keys `{id, slug, display_name}`, founding UUID `72e29f67-…`. Unknown slug → `[]`. Direct anon `GET /tenants?select=*` → `permission denied` (RLS holds).
- **Verified 2026-06-15 (prod, 5.2 S7 — 3-col):** Same 3-col contract confirmed via anon `curl.exe` with `rjbookstop` → `{id: 20941129-…, slug: rjbookstop, display_name: "Ray & Judy's Book Stop"}`.
- **Verified 2026-06-15 (staging, 5.3 S1 — 4-col):** DROP + CREATE (single-quote body, no dollar-quote); REVOKE re-run after CREATE to clear Postgres default PUBLIC grant. `pg_get_functiondef` → 4 cols (`t.id, t.slug, t.display_name, t.branding`), `STABLE SECURITY DEFINER`, `SET search_path TO 'public', 'pg_temp'`. `proacl = {postgres=X/postgres, anon=X/postgres, authenticated=X/postgres, service_role=X/postgres}` — no bare `=X`. Anon `curl.exe` → `raysandjudys` → `{id, slug, display_name, branding}` (exactly 4 keys), `branding: {}`, founding UUID `72e29f67-…`. Unknown slug → `[]`. Direct anon `GET /tenants?select=*` → `permission denied` (RLS holds).
- **Verified 2026-06-15 (prod, 5.3 S6 — 4-col):** DROP + CREATE + REVOKE + GRANT on prod; `proacl` clean (no PUBLIC). Anon `curl.exe` → `rjbookstop` → `{id, slug, display_name, branding}` (exactly 4 keys), `branding: {}`, prod founding UUID `20941129-…`. Unknown slug → `[]`. Direct anon `GET /tenants?select=*` → `[]` (RLS row-filtered on prod — `current_tenant_id()` NULL for anon → no rows; vs staging's no-SELECT-grant `permission denied`; both safe, no anon-readable tenant data).

#### F71 — `FOUNDING_TENANT` const in app.js carries staging UUID and slug

- **Status:** Resolved 2026-06-15 (5.3 S2 staging; S6 prod). `app.js` reads `const FOUNDING_TENANT = window.FOUNDING_TENANT`; hardcoded staging UUID/slug removed. Staging `config.js` carries staging values (`72e29f67-…` / `raysandjudys`); `main` `config.js` carries prod values (`20941129-…` / `rjbookstop`) — added before the 5.3 S6 promotion and verified live at `pulllist.app/config.js` post-deploy (and `app.js` confirmed free of `72e29f67`). Playwright smoke (15/15) green after staging deploy; prod founding-apex invariant + write-smoke clean.
- **Decision:** Option B — move const to per-env `config.js` (Rick, 5.3 planning 2026-06-15). Idiomatic: same mechanism as `SUPABASE_ANON_KEY`; fixes both id and slug; per-env branding delivered naturally from each env's own DB via RPC/profile path.
- **Severity:** Low-dormant — only the unauthenticated fallback (branch 4) ever reads the const; authenticated users resolve via profile lookup (branch 1) and never hit it.
- **Detail:** `FOUNDING_TENANT = { id: '72e29f67-39f7-42bc-a4d5-d6f992f9d790', slug: 'raysandjudys', … }` in `app.js` contained the **staging** founding tenant's UUID and slug. Prod founding tenant has id `20941129-c35a-476d-ae21-44b8f77af89c`, slug `rjbookstop`. Discovered when S7 anon-contract check initially tested `raysandjudys` against prod and received `[]` (correctly — that slug doesn't exist on prod).
- **Why pre-existing:** The const held staging values since Phase 3.1. The old `TENANT_SLUG_MAP` only mapped `raysandjudys` — fallback behavior was unchanged from before 5.2.

### Phase 5 enhancement-batch findings (F70)

#### F70 — `import-staging.js` carries the production founding-tenant UUID
- **Status:** Resolved 2026-06-14 — `import-staging.js` line 63 updated to `72e29f67-39f7-42bc-a4d5-d6f992f9d790`; comment corrected. Live DB checks confirmed no ghost tenant and no bad rows (FK blocked all wrong-UUID writes; all catalog rows were under `72e29f67-…`). June 2026 import ran successfully immediately after fix: 2325 records upserted, 1 auto-reserve, 3 past-on-sale fulfilled.
- **Severity:** Medium (resolved) — local-only script; FK protection prevented any data corruption.
- **Detail:** `import-staging.js` line 63 previously read `const TENANT_ID = '20941129-c35a-476d-ae21-44b8f77af89c';` — the production founding tenant, copy-pasted from `import.js` with only `SUPABASE_URL` reverted. The `catalog.tenant_id → tenants(id)` FK silently blocked all staging imports run under that UUID, leaving staging on the May 2026 catalog.
- **Where:** `C:\Users\richa\…\catalogs\scripts\import-staging.js:63` (local-only, no repo).

#### F72 — `register-customer` email template stays founding-branded after the F34 un-pin
- **Status:** filed 2026-06-16 (5.4 S2), open — disposition: deferred. Multi-tenant email branding / per-tenant MailerSend identities are explicitly OUT of Phase 5 (parent § Out of Scope); revisit when tenant 2's real email needs exist. **Re-confirmed deferred at Phase 5 close (5.5 S6, 2026-07-15)** — tenant 2 (`comicstore`) stayed pilot/seeded through the soak with no real `register-customer` customers, so F72 never surfaced live; it becomes a **prerequisite to evaluate at tenant-2's real-customer go-live** (post-Phase-5 operational step) per `docs/tenant-onboarding-runbook.md`.
- **Severity:** Low (documented gap, not a defect) — the un-pin (F34 residual) is data-correct: a customer registered via a non-founding tenant's webhook secret lands in that tenant's `user_profiles` with the right `tenant_id`. But `buildPendingEmail()` (register-customer/index.ts ~line 215+) hardcodes "Ray & Judy's Book Stop" / PULLLIST founding copy and the `from` name, regardless of which tenant the customer resolved to.
- **Where:** `supabase/functions/register-customer/index.ts` — `buildPendingEmail()` and the MailerSend `from`/`subject` fields in the main handler.
- **Fix (deferred):** when multi-tenant email branding is in scope, parameterize the email template + `from` identity by the resolved tenant's `branding`/`display_name` (and per-tenant MailerSend sender identity if needed).

#### F73 — Staging `MAILERLITE_WEBHOOK_SECRET` value pasted into a CLI chat transcript (5.4 S1)
- **Status:** **resolved 2026-06-17 (5.4 S6 pre-flight)** — staging founding webhook secret rotated; MailerLite staging webhook URL updated.
- **Severity:** Low–Medium — staging-only secret; same leak class as F69. Gates only the public `register-customer` webhook; bounded blast radius.
- **Detail:** During 5.4 S1 (founding webhook-secret migration), Rick pasted the literal staging `MAILERLITE_WEBHOOK_SECRET` value into the chat transcript. Rotation was deferred until S2 verification was complete to avoid breaking the in-flight verification; rotated 2026-06-17 ahead of S6.
- **Where:** 5.4 S1 chat transcript, 2026-06-16. Fix applied: staging `tenants.settings->>'mailerlite_webhook_secret'` updated + MailerLite staging webhook URL `?secret=` updated 2026-06-17.

#### F74 — Prod founding `mailerlite_webhook_secret` value pasted into a CLI chat transcript (5.4 S6)
- **Status:** **resolved 2026-06-17 (5.4 S6)** — prod founding webhook secret rotated after S6 founding-routes-to-founding verification passed; MailerLite prod webhook URL updated.
- **Severity:** Low–Medium — prod founding webhook secret; same leak class as F69 (resolved) and F73 (resolved). Bounded blast radius.
- **Detail:** During 5.4 S6 step 1 verification, Rick pasted the full SELECT result including the `has_secret` column value. Rotation was deferred until founding-routes-to-founding verification completed; rotated 2026-06-17 after S6 verification green.
- **Where:** 5.4 S6 chat transcript, 2026-06-17. Fix applied: prod `tenants.settings->>'mailerlite_webhook_secret'` updated + MailerLite prod webhook URL `?secret=` updated 2026-06-17.

#### F75 — Service-role keys hardcoded in local import scripts, surfaced into a CLI transcript
- **Status:** filed 2026-06-19, **resolved 2026-07-15** (sanitized past-tense entry replacing the placeholder — no key values, no exploitable specifics; full historical detail remains in the local-only operator note).
- **Fix:** (1) both scripts refactored to load credentials via `loadDotEnv()`/`requireEnv()` from a gitignored `.env`, hard-failing on a missing var and asserting `SUPABASE_URL` targets the correct project — landed 2026-07-08 (scripts repo `c2e37c6`). (2) Staging current-generation key rotated 2026-07-15: new key created, verified via a `--no-write` dry run against staging, old key deleted. (3) Prod: a new current-generation key was created and verified via a `--no-write` dry run against prod — both scripts now authenticate with current-generation keys, not the original hardcoded literals.
- **Residual:** the prod legacy `service_role` JWT (the actual credential from the original 2026-06-19 exposure event) could not be disabled — Supabase's prod project only exposes a single combined toggle covering both the legacy `service_role` and the legacy `anon` key that `config.js` depends on. The JWT stays live/unused pending a coordinated future `config.js` migration. Tracked as **F86** — this is not a reopening of F75; the exposure risk this finding tracked (hardcoded literals + an unrotated key) is closed, and F86 tracks the separate platform-level cleanup constraint. **Residual closed 2026-07-22:** F86's coordinated migration disabled prod's legacy keys entirely; the exposed `service_role` JWT is now confirmed dead (`401 "Legacy API keys are disabled"` against a live endpoint). See F86 below for the full resolution.
- **Where:** `import.js` / `import-staging.js` (scripts repo, credential loading); Supabase dashboard (key rotation, both envs). New findings are numbered from **F76**.

#### F76 — Shipment↔reservation match key is `catalog_id` OR `upc` OR `item_code` (distributor-agnostic)
- **Status:** filed 2026-06-22, **resolved — live on production** (`feature/f76-arrivals-shipment-match-key`): `Preorders.getMy` now selects `catalog.upc`; `arrivals.html` `isReserved` and the orphan filter both match on `catalog_id OR upc OR item_code`.
- **Prod status corrected 2026-07-28.** The line above read "fix landed on staging" long after the change had been promoted, understating deployment state in the opposite direction from F35/F36. Verified 2026-07-28: `git diff main staging -- arrivals.html app.js` returns empty, so `main` (production) and `staging` carry byte-identical copies of both files. Retained as **defense-in-depth** post-F84 — F84 fixed the inverted distributor labels at the source, which removes the *cause* of the null `catalog_id`, while this match key tolerates any that already exist or recur.
- **Severity:** Medium (customer-facing display) — a reserved title could render twice on the This Week arrivals page (once in the store-shipment split, once as a false orphan), and admin reservation↔shipment reconciliation overcounted "reserved but not shipped."
- **Root cause:** a title can be **catalogued under one distributor and shipped under another** (real channel split — e.g. CONAN THE BARBARIAN #32: `catalog.distributor = Lunar`, `weekly_shipment.distributor = PRH`, **same UPC**). The import wires `weekly_shipment.catalog_id` via *distributor + upc/item_code*, so cross-distributor titles get a **null `catalog_id`**. Any `catalog_id`-only reconciliation then falsely orphans them. Distributor must **not** be part of the match key (the two tables disagree on it for these titles); `upc` (Lunar) and `item_code` (PRH) mirror the import's own conflict keys (`import.js` §30-31).
- **Secondary defect (fixed here):** `Preorders.getMy` did not select `catalog.upc`, so `arrivals.html`'s `myReservedUpcs` was always empty — the in-app UPC match was dead, leaving `isReserved` effectively `catalog_id`-only.
- **Evidence:** naive `catalog_id`-only orphan count for the 2026-06-22 week was 15; correcting the key to `catalog_id OR upc OR item_code` reduced it to 4 genuine non-shipped titles (CONAN #32 CVR D foil var — A/B/C/E arrived, D did not; DICK TRACY #18 CVR A & B — absent from shipment; Starship Godzilla — absent). See also [[consider-rejected-titles-partial-fulfillment]] (memory) — PRH order-time rejections are a distinct, expected source of the residual.
- **Where:** `app.js` `Preorders.getMy`; `arrivals.html` `isReserved` + `orphanReserved`.

#### F77 — Paper orders: duplicate typeahead results + quantity changes silently dropped on resubmit
- **Status:** filed 2026-06-25, **resolved** — fix landed on staging in the same session.
- **Severity:** Medium (admin UX + data) — two symptoms, related root cause (the duplicate-catalog-row family from F76).
- **Symptom A — duplicate typeahead results:** searching for a title in the Paper Orders "Add Title to Order" typeahead returned two visually identical entries for the same comic. Root cause: titles with a null `catalog_id` (cross-distributor, same root as F76) bypass the upsert unique key during import and produce two DB rows with the same `item_code` but different UUIDs. `renderCatalogTypeahead()` rendered both rows without deduplication.
- **Symptom B — "submitting clears but is not recorded":** the submit handler used `Preorders.reserve()` (a bare `INSERT`). When a customer already had the item (`preorders` unique key `(user_id, catalog_id)`), the insert failed with `23505`/`409 Conflict` and the handler **skipped** it. An admin editing a quantity (e.g. Store Inventory 1 → 2) saw the form clear with no recorded change — the new quantity was silently dropped — and the console logged `409 (Conflict)`.
- **Fix A:** `admin.html` `renderCatalogTypeahead()` — deduplicate items by `item_code || isbn || upc || id` before rendering; reassigns `items` in-place so all downstream references (border logic, click handlers) use the deduped array.
- **Fix B:** new `Preorders.upsertReservation(userId, catalogId, quantity)` in `app.js` — `.upsert(..., { onConflict: 'user_id,catalog_id' })` so a resubmit updates the quantity instead of conflicting. The admin submit handler calls it instead of `reserve()`, counts only `succeeded`/`failed` (no more `23505` skip), and reports "N reservations saved". This both records the intended quantities and eliminates the `409` console noise. The customer-facing `reserve()` (catalog.html reserve/cancel toggle) is untouched — it keeps insert-only semantics and its "Already reserved" soft error.
- **Where:** `admin.html` `renderCatalogTypeahead()` + submit handler; `app.js` `Preorders.upsertReservation()`. (No `style.css` change — an earlier amber-toast approach was superseded by the upsert fix.)

#### F78 — Import script produces duplicate `catalog` rows for cross-distributor (null-`catalog_id`) titles
- **Status:** filed 2026-06-25, **resolved 2026-07-15** — root cause fixed 2026-07-09 by F84; historical reconciliation (this session) found **0 duplicate groups on either env**, so no consolidation was needed.
- **Severity:** Low–Medium (data hygiene) — duplicate rows are mostly invisible to customers (F77 dedups the admin typeahead; F76 dedups the arrivals match), but they inflate catalog counts, can split a customer's reservations across two UUIDs for the same physical comic.
- **Root cause (as understood 2026-06-25, before F84):** the monthly import's `catalog` upsert conflict key is `(tenant_id, item_code, distributor, catalog_month)` (verified live in both scripts 2026-07-15, `import.js:433` / `import-staging.js:432`). A title catalogued under one distributor label but shipped/listed under a different (wrong) label — the cross-distributor mismatch documented in F76 — would not collide on this key even though it's the same physical comic, producing a second row.
- **Root cause superseded 2026-07-09 (F84):** F84 found the *actual* mechanism was not a genuine "cross-distributor channel split" but an **inverted distributor label** in `normalizeShipment` (Format A tagged `'Lunar'` when it should be `'PRH'` and vice versa). F84's fix corrects the labels at the source. Per F84's own cross-reference: **"removes \[F76/F78's\] root cause... no *new* \[duplicate rows\] are produced"** on a corrected import. **F78's original "Fix (deferred): make the upsert key resilient to null catalog_id" prescription is therefore superseded as a *required* change** — it predates the F84 diagnosis and targets a symptom-level workaround for a bug that's now fixed at the source. It may still be worth doing as defense-in-depth (mirroring how the F76 distributor-agnostic display match was kept post-F84), but it is no longer blocking.
- **Historical reconciliation (closed 2026-07-15):** the detection query below (grouping `(tenant_id, item_code, catalog_month)` for `catalog_month < '2026-07'` with `COUNT(*) > 1`) was run against both staging and prod in the `import.js` maintenance session and returned **zero rows on both envs** — no duplicate groups existed to consolidate. Most likely explanation: the routine monthly rollover (`archive_stale_reservations` → `purge_stale_catalog`) had already cleared the pre-2026-07-09 catalog rows this query targets, ahead of this session running it.
  ```sql
  SELECT tenant_id, item_code, catalog_month, COUNT(*) AS n,
         array_agg(id) AS catalog_ids, array_agg(distributor) AS distributors
  FROM catalog
  WHERE catalog_month < '2026-07'
  GROUP BY tenant_id, item_code, catalog_month
  HAVING COUNT(*) > 1;
  ```
- **Where:** local-only `import.js` / `import-staging.js` (catalog upsert key, `buildCatalogIdMap`; not in any repo — see `CLAUDE.md` § What's tracked vs local-only) for the now-superseded hardening idea; live prod/staging `catalog`/`preorders` data for the historical reconciliation (closed, see above).
- **Disposition:** closed via the **`import.js` maintenance session** alongside F75 (key rotation) and F85 (cross-month carry-forward root fix) — see `docs/import-js-maintenance-f75-f78-f85.md`.

#### F79 — Asset cache skew: freshly-served HTML pairs with a stale cached `app.js`/`config.js`
- **Status:** filed 2026-06-25, **resolved** — `_headers` file added (staging → prod via normal promotion).
- **Severity:** Medium (recurring prod breakage) — surfaced after the F77 deploy as `Uncaught TypeError: Preorders.upsertReservation is not a function` in prod admin; the same class breaks **any** deploy that adds/renames an `app.js` symbol referenced by a freshly-served HTML page.
- **Root cause:** on Cloudflare Pages, HTML is served `Cf-Cache-Status: DYNAMIC` (always current), but `app.js` was served `Cache-Control: public, max-age=14400, must-revalidate` (**4-hour browser cache**) with **no cache-busting query** on the `<script src="app.js">` tag. After a deploy, a returning admin's browser fetched the **new** `admin.html` (which calls a new `app.js` symbol) while still using its **4-hour-cached old `app.js`** (without that symbol) → runtime `is not a function`. Staging preview deploys serve `app.js` no-cache, so staging never skewed — which is why "prod didn't behave like staging."
- **Fix:** added a root `_headers` file (Cloudflare Pages) setting `Cache-Control: no-cache` on `/app.js` and `/config.js`. Both already emit `ETag`, so `no-cache` (revalidate-before-use) costs a cheap `304` when unchanged and picks up a new bundle instantly on deploy. HTML pages were already DYNAMIC and need no rule; the Supabase UMD bundle is a versioned jsdelivr URL and is unaffected. `config.js` is included because it is per-branch (prod vs staging keys) and carries the same stale-after-change risk.
- **Immediate mitigation (pre-promotion):** a hard refresh (Ctrl+Shift+R) on the affected machine forces an `app.js` refetch; all browsers self-heal within the 4-hour revalidation window even without it.
- **Where:** `_headers` (new, repo/Pages root, alongside `_redirects`). No HTML/JS source change — the cache-busting is handled entirely by the header rule, avoiding a manual per-deploy `?v=` bump across all five HTML files.

#### F80 — Paper Orders typeahead not scoped to current catalog month → reservation lands in a stale month, invisible in the admin view ("silent failure")
- **Status:** filed 2026-06-26, **resolved** — typeahead scoped to `currentCatalogMonth`.
- **Severity:** Medium (admin data/UX) — the paper-order submit **succeeded** (rows written) but against a prior-month catalog row, so the reservation was absent from the current-month admin views (By Customer / order sheets / stats), presenting as a "submitting clears but is not recorded" silent failure. This is what was misdiagnosed as caching/RLS during the F77 prod follow-up; prod was in fact running the correct upsert code.
- **Root cause:** a title solicited in consecutive months has **one `catalog` row per `catalog_month`** (monthly snapshots — expected, distinct from the F78 null-`catalog_id` duplicates). The Paper Orders typeahead called `Catalog.fetch({ search, pageSize: 8 })` with **no `month` filter**, so it searched across all months and could surface a prior-month row (e.g. ABSOLUTE FLASH #18 existed as both `afac6068…`/`2026-05` and `de0461e4…`/`2026-06`, same `item_code`/`upc`). The F77 `item_code` dedup then collapsed the two to whichever the query returned first — sometimes the stale 2026-05 row. Reserving against it wrote a valid preorder in a month the admin (scoped to the latest month) never sees. Staging lacked the cross-month rows, so it never reproduced — the "works on staging, not prod" signal.
- **Fix:** pass `month: currentCatalogMonth` to the typeahead's `Catalog.fetch` (`Catalog.fetch` already supported the `month` filter — `app.js` line ~445). This matches the rest of the Paper Orders tab (print order sheets already `.eq('catalog_month', currentCatalogMonth)`), guarantees reservations land in the viewed month, and excludes cross-month duplicates; the F77 `item_code` dedup still handles any same-month duplicates.
- **Data cleanup (prod): done 2026-07-09.** Note: the live stray rows were `25409a1a…` (qty 1) and `fc5f9167…` (qty 2) — the ids originally recorded here (`9671effe…`/`3668775e…`) were stale; identification was re-confirmed on the stronger keys instead (both on `catalog_id = afac6068…` / 2026-05, same two users and quantities as the correct 2026-06 rows `a12493fc…`/`d2d89ec6…`, created 2026-06-26T02:20 in the misfire window). Both strays deleted via service-role with `return=representation`; post-checks: zero preorders remain on `afac6068…` (row becomes purgeable at the next new-month run) and both correct 2026-06 rows intact. Broader sweep confirmed no other misfire-window strays — the remaining 2026-05-month preorders are legitimate forward reservations (comics are solicited 2–3 months ahead), not F80 artifacts.
- **Where:** `admin.html` Paper Orders catalog-search typeahead handler.

#### F81 — README + `monthly-catalog-refresh.md` described the pre-migration system, including destructive manual clear-out SQL
- **Status:** filed 2026-07-08, **resolved** — both documents rewritten in the same session (surfaced by the 2026-07-07 full architecture review, observation A17).
- **Severity:** High (operational hazard, documentation) — `docs/monthly-catalog-refresh.md` still instructed a manual `DELETE FROM preorders` / `DELETE FROM catalog` before each monthly import (its Steps 3–4), predating the automated new-month sequence (`archive_stale_reservations` → `purge_stale_catalog` → upsert → `delete_dropped_catalog_items`). Following the stale doc would have destroyed the month's `reservation_history` archive (recommendation signal) and the fulfillment audit trail, from a document that looked authoritative. `README.md` compounded the drift: retired GitHub Pages URLs, "Hosting: GitHub Pages", and — directly contradicting the actual per-branch policy in `CLAUDE.md` — "`config.js` (gitignored — never commit)".
- **Root cause:** both docs were written pre-Phase-1 and never re-audited as the import script absorbed the manual steps (Phase 4.0/4.5) and hosting migrated (5.1). Neither carried a "last verified against live" line, so nothing flagged them as snapshots.
- **Fix:** `monthly-catalog-refresh.md` rewritten around the automated sequence with an explicit F81 warning banner against older copies; manual DELETE steps removed; verification queries retained; F80 month-confirmation and F78 duplicate-watch checks added. `README.md` corrected (URLs, Cloudflare Pages, per-branch `config.js` section, current repo structure, deployment summary deferring to `CLAUDE.md`).
- **Where:** `README.md`; `docs/monthly-catalog-refresh.md`.

#### F82 — fixed two-batch fetches cap at 2,000 rows; July 2026 (2,776 rows) crossed the ceiling
- **Status:** **fully resolved** — app-side fixed 2026-07-08 (staging commit `6e126dd`): `Catalog.getPublishers()` and `Recommendations.getCatalogIds()` paginate in 1,000-row batches until a short read. Import-side fixed 2026-07-09 (scripts repo `17378e2`): the auto-reserve catalog fetch pages until a short read and skips auto-reserve entirely on any page failure (a partial catalog must never silently match). Verified via `--no-write` dry run: `Catalog rows fetched: 2776` (was capped at 2,000) with identical match results.
- **Severity:** Medium (customer-visible UI gap + latent auto-reserve data risk).
- **Evidence (prod, 2026-07-08, read-only queries):** the 2026-07 catalog month is **2,776 rows** — past the 2,000-row ceiling of the fixed two-batch pattern. Confirmed live effects: publishers sorted past row 2,000 (Vault Comics, Viz Media, Wake Entertainment, Wattpad WEBTOON Book Group, Yen Press) were absent from the catalog filter dropdown; recommendations were blind to 776 rows; the `--no-write` import dry run logged its auto-reserve catalog fetch at exactly 2,000 rows. All 3 live subscriptions were individually verified — **no auto-reserve was actually missed in July** (both matchable titles sat under the cap and were already reserved; the third series has no July standard cover).
- **Root cause:** the Supabase 1,000-row page limit was worked around with fetches hard-sized to a ~1,900-row month (`range(0,999)` + `range(1000,1999)`). Predicted as observation A3 in the 2026-07-07 architecture review; first month over 2,000 rows activated it silently — no error, rows simply absent.
- **Where:** `app.js` `Catalog.getPublishers()`, `Recommendations.getCatalogIds()` (fixed); local `import.js`/`import-staging.js` subscription catalog fetch (open).
- **Longer-term:** replace `getPublishers`' paging with a `SELECT DISTINCT publisher` RPC (~80 rows returned instead of the whole month); same option for the recommendations id list.

#### F83 — Format B (PRH) shipment path fails wholesale on split invoice lines
- **Status:** filed 2026-07-09, **resolved same session** — scripts repo commit `dc92b91`; prod data restored by the operator's re-run.
- **Severity:** Medium-high (weekly operational) — one duplicate line in a Format B invoice rejected the **entire** PRH shipment batch, and because that path is delete-then-insert, the failed run left **zero** PRH rows for the on-sale date (2026-07-08): the This Week page and bagging list were missing all 16 PRH-shipped items until the re-run.
- **Root cause:** Format B invoices can list the same item on multiple lines (shipment 846349 listed `0526DE0666` and `0526MA0928` twice). `buildLunarShipmentRows` has pre-summed duplicate (upc, date) lines since the Format A split-line fix, but `buildPrhShipmentRows` did not — and the 16 rows go to PostgREST as one atomic POST, so the intra-batch duplicate on `weekly_shipment_unique (distributor, upc, on_sale_date)` (UPC `72513036535402011`) aborted all 16. Not catchable by a `--no-write` dry run (the constraint only evaluates on a real insert).
- **Fix:** `buildPrhShipmentRows` now collapses rows on `(upc || item_code, on_sale_date)` and sums quantities — mirroring the Lunar builder. Two regression specs added to the local node-test suite (shared-UPC merge; null-upc fallback key). Verified: 7/7 unit tests; `--no-write` dry run shows 16 raw lines → 14 rows, single batch.
- **Where:** local scripts repo (`comic-preorder-scripts`) — `import.js` / `import-staging.js` `buildPrhShipmentRows()`; tests in local `playwright/node-tests/`.

#### F84 — Shipment distributor labels inverted at the source (root cause of F76 and F78)
- **Status:** filed 2026-07-09, **fix landed in the scripts repo same session** (`comic-preorder-scripts` `01a90b6`); verified on staging with a real import. Prod: tomorrow's import uses the fixed script; a one-time current-week cleanup is optional (see below).
- **Severity:** Medium-high — every direct-market comic was mislabeled and left with a null `catalog_id`. Surfaced by the new distributor-grouped store poster (arrivals.html), which made the wrong grouping visible (Lunar comics under a "PRH" heading).
- **Root cause:** `normalizeShipment` tagged **Format A** (PRH delivery invoice — `Delivery Number` header, ISBN→`upc`, penguinrandomhouse covers) as `distributor = 'Lunar'`, and **Format B** (Lunar code invoice — numeric shipment #, `Code`→`item_code`, lunardistribution covers) as `distributor = 'PRH'`. That is inverted from reality and from the catalog: DC/Image/Titan direct-market comics ship via **Lunar** and are catalogued `distributor = 'Lunar'`; the PRH channel is book-trade + Dynamite/Disney, catalogued `'PRH'`. Compounding it, `buildCatalogIdMap`'s code-stream lookup filtered `distributor=eq.PRH`, so the (really-Lunar) code-invoice items never matched their `'Lunar'` catalog rows → **null `catalog_id` for the entire direct-market shipment every week**. This is precisely the null-`catalog_id` condition F76 (false orphans / distributor-agnostic display match) and F78 (duplicate catalog rows) were built to work *around* — prior sessions rationalized it as a "channel split." It is not a split; it is a label inversion.
- **Fix:** (1) swap the two labels in `normalizeShipment` (Format A → `'PRH'`, Format B → `'Lunar'`); (2) route the two shipment streams by **identifier** (`item_code` vs `upc`), not by the now-corrected label, so each still reaches its correct matcher/upsert path; (3) code-stream catalog match → `distributor=eq.Lunar` (this is what resolves `catalog_id`); (4) code-stream delete-then-insert → `distributor=eq.Lunar`; (5) corrected operator console messages and the format-doc comments. `weekly_shipment` unique indexes are on columns `(distributor, upc/item_code, on_sale_date)` and are agnostic to the distributor *value*, so no index change was needed.
- **Verification (staging, real import):** the 9 code-invoice items that previously reported `PRH: 0/9 matched` now report `Lunar (code/item): 9/9 matched`; all landed `distributor = 'Lunar'` with `catalog_id` resolved (0 null). 7/7 import unit tests; both scripts `node --check` clean.
- **Impact on F76 / F78:** removes their root cause. Catalog and shipment distributor now agree and `catalog_id` resolves for direct-market items, so the F76 false-orphan condition and the F78 null-`catalog_id` duplicate-row mechanism no longer arise on a corrected import. The F76 distributor-agnostic display match stays as harmless defense-in-depth. F78's *existing* duplicate catalog rows (created under the old behavior) are separate historical data to reconcile in the `import.js` catalog-upsert session, but no *new* ones are produced.
- **Data migration:** rows written before the fix carry the old (inverted) labels. Staging was purged (`on_sale_date >= 2026-07-01`) and re-imported clean. **Prod:** next week's import lands correctly with no collision (that date has no prior rows); the current week's already-imported rows stay mislabeled until the week rolls over — swap them in place if reprinting this week's poster: `UPDATE weekly_shipment SET distributor = CASE WHEN distributor='Lunar' THEN 'PRH' ELSE 'Lunar' END WHERE tenant_id = <prod founding> AND on_sale_date = '<current week Wed>';` (label-only; `catalog_id` on the now-`Lunar` rows stays null until a re-import, and the arrivals display handles null via F76).
- **Where:** scripts repo `import.js` / `import-staging.js` — `normalizeShipment`, the shipment split, `buildCatalogIdMap`, `upsertShipment`.

#### F85 — Cross-month duplicate preorders: a re-listed item_code gets a second reservation against the new month's catalog row
- **Status:** filed 2026-07-10; **resolved 2026-07-15** — prod duplicates cleaned 2026-07-10 (consolidation applied — detection query re-run returns 0 pairs; bagging list shows each comic once), and the root fix landed in both scripts this session, verified end-to-end on staging.
- **Severity:** Medium (customer-facing + operational) — surfaced on the This Week **bagging list**: a customer's comic appears **twice** (same `item_code`, two catalog UUIDs). Inflates Total Items / Est. Value on the week header, and the store would bag two copies of one comic. ~45 duplicate pairs across ~7 customers as of 2026-07-10 (detection query below).
- **Distinct from F84/F78:** these are **not** null-`catalog_id` rows. Both catalog rows are valid; they differ only in `catalog_month` (mostly `2026-05` + `2026-06`, one `2026-03`). A comic solicited one month with a later on-sale date is **re-listed** in the next month's catalog CSV, so the monthly import creates a **second catalog row** for the same `item_code` (catalog snapshots are per-month). The `preorders` unique key is `(user_id, catalog_id)`, so a reservation against each month's row does not collide — the customer ends with two preorder rows for one physical comic. Reservations arrive via the monthly auto-reserve (standard covers for subscribers) and via manual re-reserve (the month-scoped catalog view shows the new-month row as un-reserved because the prior reservation is against a different `catalog_id`). Same **cross-month family as F80** (which only fixed the paper-orders typeahead).
- **Root fix (landed 2026-07-15):** `autoReserveSubscriptions()` in both `import.js` and `import-staging.js` now builds a cross-month carry-forward map (`buildCarryForwardMap`, pure function) from prior-month `catalog` rows sharing this month's `item_code`s and the `preorders` pointing at them, keyed `${user_id}||${item_code}`. The match/decision logic (`matchSubscriptions`, also extracted as a pure function) checks this map before deciding to insert: a hit becomes a `PATCH` of the existing preorder's `catalog_id` onto this month's row — `created_at` is never touched, so the original reserved date survives automatically — instead of a new `INSERT`. Both functions are exported from each script for testing; the existing-reservation check (`existingSet`, keyed `${user_id}||${catalog_id}`) still takes precedence, so an already-reserved-this-month hit is skipped rather than carried forward. 8 new unit tests added to the scripts-repo suite (37/37 passing) covering the carry-forward case, a genuinely-new `item_code` still inserting normally, and the already-reserved precedence case.
- **Verification (staging, real import re-run, 2026-07-15):** a real subscriber's July preorder was temporarily repointed (via a synthetic June clone of the same `item_code`) to simulate a stale cross-month reservation, then a real (non-`--no-write`) `import-staging.js` run was executed. Result: `Carried forward: 1`, 0 new inserts; the preorder's `catalog_id` was patched back to the July row, `created_at` remained exactly unchanged from before the test, and exactly one preorder row existed afterward for that user+item_code (no duplicate). The synthetic test row was deleted after verification. No web-app change was required — the fix is entirely within the import scripts.
- **One-time prod cleanup (applied 2026-07-10):** consolidated each `(user_id, item_code)` group onto the survivor = the **newest-`catalog_month` row** (most recent on-sale date), set its `created_at` to the group's **earliest** (retain the original reserved date), took `MAX(quantity)`, and marked `fulfilled` if **either** row was; deleted the superseded rows (~45 pairs). Detection query re-run afterward returned 0 rows. Window-function `UPDATE` (survivor `rn=1`) + `DELETE` (`rn>1`) partitioned by `(user_id, item_code)`, ordered `catalog_month DESC, on_sale_date DESC, created_at DESC`.
- **Where:** scripts repo `import.js` / `import-staging.js` — `buildCarryForwardMap()` + `matchSubscriptions()` (new pure functions) called from `autoReserveSubscriptions()`; previously manifested in `admin.html` This Week bagging list (`renderThisWeek`, which correctly renders one row per preorder — no web-app defect, then or now).

#### F86 — Prod legacy API keys (anon + service_role) can only be disabled as a single unit — blocks full F75 remediation without a coordinated `config.js` migration
- **Status:** filed 2026-07-15, **resolved 2026-07-22** — coordinated migration executed end-to-end across a multi-sitting F86 execution session; full runbook + evidence: `docs/f86-anon-key-migration.md`.
- **Severity:** Low–Medium as filed (bounded residual risk, not a new exposure) — closed cleanly, no incident.
- **Detail (as filed):** F75's prod remediation created a new current-generation `sb_secret_` key for `import.js`, but could not disable the old legacy `service_role` JWT — prod's Supabase dashboard exposes only **one** combined "Disable legacy API keys" toggle covering both the `anon` (public, `config.js`-consumed) and `service_role` (secret) legacy keys together. Flipping it while `config.js` still used the legacy `anon` key would have broken the live app.
- **Resolution:** (1) staging rehearsal — flipped staging's toggle first (staging's `config.js` was already on a publishable key), full Playwright suite green pre- and post- a 24h soak (amended from a planned 48h at Rick's call, confirmed genuinely elapsed), and a throwaway-fixture exercise of `create-paper-customer` + `register-customer` proved the platform-injected `SUPABASE_SERVICE_ROLE_KEY`/`SUPABASE_ANON_KEY` env vars kept working post-toggle — no Edge Function code migration needed. (2) Prod `config.js` migrated from the legacy `anon` JWT to a new publishable key (Rick created the key and edited the one line himself; agent verified the diff shape only, never read the value) via PR #80 → `main`, live-verified (login/catalog/reserve-cancel write-smoke, both tenant domains). (3) A full weekly shipment cycle elapsed cleanly on the new key. (4) **F88** surfaced mid-session (edge functions' own downstream service-role calls might break) — verified false on both staging (`notify-customers`, the function F87 had already proven fragile) and prod (`create-paper-customer` against the real founding tenant) before and immediately after the toggle flip; see F88 below. (5) Rick flipped prod's toggle; live verification green on both tenant domains. (6) Confirmed dead: both the F75-exposed legacy `service_role` JWT and the legacy `anon` key now return `401 "Legacy API keys are disabled"` against a live prod endpoint (disable timestamp `2026-07-22T14:34:11 UTC`) — **this closes the F75 residual below.**
- **Where:** Supabase dashboard prod project settings; `config.js` (`main`, one-line value change, PR #80 `415f742`); no Edge Function code changes.

#### F87 — `notify-customers` rejects the import script's service-role call after the F75 key rotation → monthly catalog email silently not sent ("Invalid auth")
- **Status:** filed 2026-07-17; **resolved 2026-07-17.** Capability-probe fix deployed to staging (`notify-customers` v23) and prod (v33), both with `--no-verify-jwt` (verify_jwt-off preserved). Admin-API probes on both envs confirmed the gate: real service key → 200, forged `role=service_role` token → 401, garbage → 401. Prod July catalog email **sent successfully** on the import re-run. Landed on staging in `1772a4b`; source promoted to `main` via PR #87. Regression from F75; related to F86 (the legacy JWT being left live is why the function's *own* service calls are unaffected).
- **Severity:** Medium (customer-facing, non-corrupting) — the July 2026 catalog notification blast did not send. No data impact; the import otherwise completed cleanly. Recurs every month until fixed.
- **Symptom:** `import.js` Step 7 prints `❌ Notification error: {"error":"Invalid auth"}`; zero customers emailed.
- **Root cause:** `notify-customers` detects a service-role caller by manually base64-decoding the bearer token as a 3-segment JWT and checking `payload.role === 'service_role'` (`index.ts:30-38`). F75 rotated `IMPORT_SERVICE_KEY_PROD` from the legacy `service_role` JWT to a new current-generation `sb_secret_…` secret key, which is **not a JWT** — the decode hits `parts.length !== 3` → `isServiceRole = false`. The call then falls into the user-JWT branch, `/auth/v1/user` rejects the secret key, and the function returns `{ error: 'Invalid auth' }` (`index.ts:49-51`). The key is a valid service-role credential — the run's RLS-bypassing catalog/shipment/auto-fulfill writes (all PostgREST) succeeded; only the manual JWT decode fails to recognize the new format.
- **Also a pre-existing weakness (not just the F75 regression):** `verify_jwt` is **off** for this function (the off-plus-in-body-auth pattern — confirmed because the `sb_secret_` request reached the function's *own* line-50 error rather than a platform 401). The decode performs **no signature check**, so a crafted `role=service_role` bearer would also have set `isServiceRole = true` and triggered a founding-tenant email blast. The fix therefore had to be spoof-proof, not merely new-key-aware.
- **Scope:** Prod confirmed (2026-07-17 run). Staging reproduces (staging key was rotated in the same F75 session; `import-staging.js` → staging `notify-customers` is identical code). `notify-customers` is the **only** edge function the import script calls (every other write path is a PostgREST RPC, which accepts the `sb_secret_` key). No other trigger exists — `notify-customers` is not wired to any admin-UI button (only an `app.js` comment references it), so there is no non-import send path today.
- **Fix (implemented 2026-07-17, branch `fix/f87-notify-customers-probe`):** detect a service-role caller by **proving the key** instead of decoding a claim — the function now uses the caller's token against the admin-only `/auth/v1/admin/users` endpoint; only a genuine service key (legacy JWT **or** new `sb_secret_`) returns 200, so it is format-agnostic **and** spoof-proof, and it also closes the pre-existing bypass above. Deliberately **not** `token === SUPABASE_SERVICE_ROLE_KEY` equality (that env still resolves to the legacy JWT per F86, ≠ the new import key). **Staging API-probe verification (2026-07-17):** real staging service key → 200; forged unsigned `role=service_role` token → 401; garbage token → 401. **Still pending:** deploy the function to the staging Supabase project, run a real (non-`--no-write`) `import-staging.js` notify to confirm it authorizes and sends, then ff-merge to `staging`; prod promotion (deploy prod function + re-send the July blast) gated on Rick's OK.
- **Comment contradiction (reconciled in the fix):** the header comments previously disagreed on platform JWT verification (one said disabled, one said ON). `verify_jwt` is **off** (see the pre-existing-weakness bullet); the fix rewrites the header to state that accurately and to explain why the probe is needed.
- **Where:** `supabase/functions/notify-customers/index.ts` — the caller-auth block (`isServiceRole`, ~lines 17-42 post-fix). Related: F75 (root — key rotation), F86 (legacy keys still live).

#### F88 — Disabling prod legacy API keys (F86 Step 5) will break every edge function's *own* service-role calls (the auto-injected `SUPABASE_SERVICE_ROLE_KEY` is the legacy JWT)
- **Status:** filed 2026-07-17; **resolved — prod-confirmed 2026-07-22 (F86 Step 5, V6)**. Predicted failure mode did not reproduce on staging or prod.
- **Severity:** High if confirmed; **did not materialize.** No data corruption; the prod toggle flip caused no function-layer outage.
- **Predicted root cause:** every edge function reads `Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')` — Supabase's auto-injected **legacy** `service_role` JWT — for its own privileged REST/Auth-admin calls (confirmed example: `notify-customers` lines ~80-83 read `app_settings`/`user_profiles`, ~116-119 recipients, ~126-129 `/auth/v1/admin/users`). F86's single "Disable legacy API keys" toggle disables the legacy `anon` + `service_role` JWTs together. New-generation secret keys are injected under a **different** variable (e.g. `SB_SECRET_KEY`) rather than replacing `SUPABASE_SERVICE_ROLE_KEY`, so once legacy keys are off the auto-injected env is expected to point at a now-dead key → those calls start returning 401. Distinct from F86's existing scope (the `config.js` **anon/client** side); this is the **service-role/server** side.
- **Interaction with F87:** F87 fixed only caller *detection* (probe the admin API with the presented `sb_secret_` key). The function's *downstream* service calls still ride the legacy-JWT env, so the F86 toggle would silently re-break the July catalog email fixed 2026-07-17.
- **Staging verification (2026-07-17, F86 execution session — corrects this finding's original "staging appears unaffected... its legacy JWT looks still live" assumption):** staging's legacy-key toggle was in fact genuinely and durably disabled at the time of filing (flipped in the F86 session's Step 1.1, confirmed via a Playwright suite re-run 24h+ later with no intervening re-enable) — it was not an un-flipped toggle. Two independent tests against the real deployed staging functions, both post-toggle: (1) `create-paper-customer` + `register-customer` (F86 plan V2) — both HTTP 200, exercising `Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')` against `/auth/v1/admin/users` (POST) and `/rest/v1/user_profiles` (POST/DELETE). (2) `notify-customers` itself (this finding's flagged example) — a throwaway-fixture test (synthetic tenant + one non-admin customer with a fake `@example.com` address, so no real person was emailed) exercised its full downstream path: `app_settings` read, `user_profiles` read, `/auth/v1/admin/users?per_page=1000` read, MailerSend send — all via the same injected `SUPABASE_SERVICE_ROLE_KEY`. Result: HTTP 200, `{"success":true,"sent":1,"failed":0}`. All test fixtures torn down, live SELECT confirmed 0 rows remaining. **Conclusion: on staging, the auto-injected `SUPABASE_SERVICE_ROLE_KEY` continues to authenticate successfully post-toggle** — the predicted "new-gen keys land under a different var, legacy env goes dead" mechanism did not manifest for any of the 3 functions tested (covering every downstream call pattern — `/rest/v1/*` GET/POST/DELETE and `/auth/v1/admin/*` GET/POST — that all 9 functions use).
- **Prod verification (2026-07-22, F86 Step 5, V6):** Rick flipped prod's "Disable legacy API keys" toggle (project `plgegklqtdjxeglvyjte`). Manual live check: pulllist.app login/catalog/reserve/cancel write-smoke green; `comicstore.pulllist.app` loads correctly. Scripted check: a throwaway-fixture test exercised `create-paper-customer` against the **real prod founding tenant** (not a synthetic one) — same pattern as the staging V2 test: throwaway admin test user → session token → real deployed function call. Result: HTTP 200, paper customer created successfully via the function's own injected `SUPABASE_SERVICE_ROLE_KEY`. Both test fixtures deleted immediately after; live SELECT confirmed 0 rows remaining.
- **Conclusion:** the predicted mechanism (new-gen secret keys landing under a separate env var, leaving `SUPABASE_SERVICE_ROLE_KEY` pointed at a dead legacy JWT) did not occur on either project. Whatever Supabase does internally when legacy keys are disabled, the auto-injected `SUPABASE_SERVICE_ROLE_KEY` continued to authenticate successfully on both staging and prod. No Edge Function code changes were needed (F86 plan's Step 1-C contingency was correctly skipped).
- **Where:** all `supabase/functions/*/index.ts` (each reads `SUPABASE_SERVICE_ROLE_KEY`); `notify-customers` and `create-paper-customer` are the two confirmed examples (staging + prod respectively).

#### F89 — Paper→app conversion is unmeasurable: a successful claim deletes the paper rows and no event records it

- **Status:** filed 2026-07-19; **open — deferred to a future instrumentation session** (explicitly OUT of the planned analytics cycle-alignment session, which is client-only — see `docs/analytics-cycle-alignment.md`). Related: F33 (claim EF reimplements the unused `claim_paper_account` RPC), F72 (invite email branding), F90 (rollup would make conversions survive retention).
- **Severity:** Low as a defect (no correctness or security impact) — but it blocks measuring one of the store's primary adoption goals (converting paper customers to app users).
- **Symptom:** neither `analytics.html` nor any SQL can count paper→app conversions. On success, `claim-paper-customer` deletes the paper `user_profiles` row and its placeholder `auth.users` row (`index.ts` ~lines 167–191; same destructive-merge design as §6.7). A shrinking `is_paper` count is therefore indistinguishable from admin deletions. `usage_events` has no `claim`/`invite`/`signup` event type (§4.8), and `UsageEvents._log()` is client-side only — the claim happens inside the Edge Function, so nothing is logged. Invites (`invite-customer`) are likewise unrecorded.
- **Root cause:** conversion was designed as a destructive merge with no durable audit record; observability was never in scope for the claim/invite flows.
- **Scope:** staging + prod (identical function code).
- **Fix direction (future session):** smallest viable — log a `claim` usage_event from `claim-paper-customer` on success (prior paper id in `metadata`) and an `invite_sent` event from `invite-customer`; or persist a `converted_from_paper_at` timestamp on the surviving profile. Any variant touches Edge Functions (and possibly §4.8's event-type list) → own scoped session with runbook. Pairs naturally with F90 so conversion counts survive the 90-day purge.
- **Where:** `supabase/functions/claim-paper-customer/index.ts`, `supabase/functions/invite-customer/index.ts`; §4.8 event-type note.

#### F90 — `usage_events` 90-day retention forecloses adoption-trend analytics; a monthly rollup snapshot is needed

- **Status:** filed 2026-07-19; **open — deferred to a future schema + import-script session** (candidate to bundle with F89's instrumentation). Related: §6.6 (`purge_old_usage_events`), F89, `docs/analytics-cycle-alignment.md` (client-only session; explicitly excludes this).
- **Severity:** Low — the data loss is by design (retention policy), but it caps every trend question at the ~2–3 catalog cycles that fit in 90 days.
- **Symptom:** `analytics.html` can never answer "is adoption growing quarter over quarter." `purge_old_usage_events(90)` runs at every import and erases the history the question needs; deltas can only ever compare against the immediately-prior cycle. No new-signups / MAU / paper-count / conversion trend beyond ~90 days is derivable from live data.
- **Root cause:** `usage_events` is the only engagement record; no aggregate survives the purge.
- **Scope:** staging + prod (same retention design).
- **Fix direction (future session):** a small per-tenant monthly rollup table (e.g. `analytics_monthly`: `tenant_id`, `catalog_month`, `new_signups`, `mau`, `paper_count`, `claims`, `reserve_events`, `reserved_value_usd`) written by the import scripts at month-close via service-role **before** the purge, with admin-read RLS. Unlocks 12-month trend lines in `analytics.html`. Schema + RLS + `import.js`/`import-staging.js` + doc changes → own sub-deploy-style session with Rick-in-the-loop DB steps.
- **Where:** new table (schema TBD), `import.js` / `import-staging.js`, later a trend panel in `analytics.html`.

#### F91 — GoTrue Admin API intermittently rejects new-generation `sb_secret_` keys with a JWT-parse error, breaking Playwright auth fixtures

- **Status:** filed 2026-07-22, **resolved 2026-08-02** in the test-infrastructure maintenance session (`docs/test-infra-maintenance-f91-f95-f103.md`). Discovered during the apex-marketing sub-deploy's S5.3 gate (`docs/apex-landing-tenant-subdomains.md`); unrelated to that sub-deploy's actual diff (an `index.html` copy change + a new committed Playwright spec, both of which were unaffected across every run).
- **Resolution (2026-08-02):** Supabase's docs are silent on this specific admin-endpoint interaction (`migrating-to-new-api-keys` names no admin-API caveat), but `self-hosted-auth-keys` confirms the mechanism by design: the gateway inspects `Authorization: Bearer sb_...` and rewrites it to "the internal pre-signed ES256 JWT that corresponds to the role" before GoTrue verifies it — consistent with the observed `unrecognized JWT kid <nil>` error being that translation's own kid lookup missing, not an unsupported key type. `supabase/supabase-js#1568` reproduces the identical `403 bad_jwt` symptom against `admin.createUser()` with no maintainer resolution as of this date. Given that ambiguity, the remedy chosen was **(c) bounded retry**, not (b) a legacy-JWT revert (which would have cut against F86's legacy-key retirement) — implemented in `fixtures/auth.ts`: the three GoTrue Admin calls (`createUser`, `deleteUser`, `generateMagicLink`) now go through a `fetchGotrueAdmin()` helper on its own `gotrueHeaders` constant (separable from the PostgREST `supaHeaders`), retrying up to 3 attempts with linear backoff specifically on `403` + `bad_jwt`, and failing loudly (throwing) when attempts are exhausted. **Verified:** 6 consecutive full-suite runs (3 immediately after the fix, 3 more at the final V4 gate) — **zero** `bad_jwt`/403 occurrences across all six. No legacy-key credential change was needed, so no Rick sign-off was required per the plan's decision gate.
- **Severity:** Medium — test-infrastructure reliability, not a live application defect. No customer/data impact, but it makes the local Playwright smoke suite an unreliable gate (`CLAUDE.md`'s Definition of Done requires full-suite-green) and will recur for any future session running the suite until resolved.
- **Symptom:** `scripts/playwright/fixtures/auth.ts`'s `createUser()` and `generateMagicLink()` call Supabase's GoTrue Admin API directly (`POST /auth/v1/admin/users`, `POST /auth/v1/admin/generate_link`) using `SUPABASE_SERVICE_KEY` as both the `apikey` and `Bearer` header. Two consecutive full local smoke-suite runs (`run-smoke.ps1`) each produced intermittent `403` errors: `{"code":403,"error_code":"bad_jwt","msg":"invalid JWT: unable to parse or verify signature, token is unverifiable: error while executing keyfunc: unrecognized JWT kid <nil> for algorithm ES256"}`. A different specific test failed on each run (specs 07/09/10/11 on run 1; specs 04/07/09/10/11 on run 2) — never the same test twice, and run 2 had strictly more failures than run 1 (worsening, not settling).
- **Diagnosis (verified, not theorized):** a local format-only check (no secret value exposed) confirmed `SUPABASE_SERVICE_KEY` in `scripts/.env` is the new-generation `sb_secret_`-prefixed key (41 chars, not JWT-shaped) corresponding to the Supabase dashboard's "magic_link_tooling" named secret key — i.e., the fixture is correctly wired to the intended, current key; this is not a stale/wrong credential. Yet GoTrue's error explicitly describes JWT parsing/kid-lookup failure, meaning GoTrue is attempting to verify the presented `sb_secret_` token as a JWT rather than recognizing it as an opaque API key, and intermittently failing that attempt. This is consistent with F88's finding that Edge Functions' auto-injected `SUPABASE_SERVICE_ROLE_KEY` (which stays JWT-shaped under the hood per F88's own investigation) is what reliably authenticates against `/auth/v1/admin/*` — a manually-configured new-generation secret key used directly against those same endpoints, as this fixture does, is evidently a different and less reliable code path on Supabase's side.
- **Scope:** local `scripts/playwright` suite only (`fixtures/auth.ts`). Does not affect the deployed app, any Edge Function, or the import scripts (`IMPORT_SERVICE_KEY` is a separate `sb_secret_` key, "import_staging_2026_07", used only for PostgREST/RPC calls via `import.js`/`import-staging.js`, never GoTrue Admin API calls).
- **Fix direction (future session):** either (a) confirm with Supabase support/docs whether new-generation `sb_secret_` keys are supported at all against GoTrue Admin endpoints (vs. only PostgREST/Storage), or (b) revert `fixtures/auth.ts` to a legacy-format `service_role` JWT specifically for these two admin-API calls if `sb_secret_` keys are confirmed unsupported there, or (c) add retry-with-backoff in the fixture if this proves to be a transient edge-node propagation issue rather than a hard incompatibility.
- **Where:** `scripts/playwright/fixtures/auth.ts` (`createUser`, `generateMagicLink`); `scripts/.env` (`SUPABASE_SERVICE_KEY` / "magic_link_tooling").

#### F92 — `technical-reference.md` carries pre-Phase-5 claims outside the tenant-resolution contract

- **Status:** filed 2026-07-22 (apex-marketing sub-deploy, S5.7). **Open — substantially reduced 2026-07-28; a live-DB pass is still owed.** Every inventory item that could be settled from repo evidence, established session facts, or the live import scripts was corrected on 2026-07-28 during the § 13 cleanup session (see **Swept 2026-07-28** below). What remains is the part that genuinely needs a database: a section-by-section verification of the schema tables against live `information_schema` / `pg_constraint` on **both** environments. The header's "Last verified" line now states this split explicitly rather than implying whole-document authority.
- **Swept 2026-07-28 (all verified before editing, not assumed):**
  - Header "Last verified: post Phase 3.8 soak, May 2026" → now states which sections were verified 2026-07-28 and that everything else remains May-2026 stale.
  - § 1 "No second tenant exists yet" → corrected; `comicstore` live on prod since 2026-07-15, pilot/seeded, 0 shipment rows.
  - § 1 + § 2 "GH Pages warm until 5.5 closes" → corrected; 5.5 closed and Rick's 2026-07-15 call untied it from any phase gate.
  - § 1 "the import script hard-codes `TENANT_ID`" → corrected; `.env`-driven and hard-failing since 2026-07-08, verified against the live scripts.
  - § 3 "no second tenant has been onboarded" → corrected, and the section now names **both** founding UUIDs (it previously gave only staging's while implying it was the sole one).
  - § 3.3 + § 4.9 `user_profiles` ↔ `auth.users` FK → corrected in all three places. **This one was worse than filed:** § 3.3 did not merely omit the FK, it asserted there was none *and argued the absence was intentional* to protect the paper-customer flow. The live schema has carried a CASCADE FK on prod for months without breaking that flow, so the rationale is disproved, and the correction says so explicitly to stop it being restored.
  - § 4.10 `weekly_shipment` distributor mapping → **corrected; it was backwards.** The doc said Format A → `Lunar` / Format B → `PRH`; the live parsers (`import.js:262-269`, `:296-301`) do the reverse. F84 fixed this inversion at the source on 2026-07-09 and the doc was never updated, so the canonical reference gave a wrong `distributor` filter for ~3 weeks. Found while investigating F9 — an unrelated question — which is exactly the discovery mode this finding exists to replace.
  - § 4.2 `app_settings` PK, § 4.6 legacy `settings` PK, § 4.10 unique-index list → verified against live prod and corrected/confirmed under F6 and F9 the same day.
- **Still owed (needs the live-DB pass):** every remaining § 4 table's columns, constraints, and index list; § 5–§ 12 generally; and confirmation that staging and prod agree per section. F64 is the precedent for why "both environments" matters — it catalogued eight divergences.
- **Original status text:** open — deferred to a dedicated `technical-reference.md` re-audit session. S5 fixed the tenant-resolution contract (§ 3.1, § 10.1 — the `TENANT_SLUG_MAP` / subdomain / `source()` enum drift, see the entries above them), but the same document carries other stale claims outside that specific contract, deliberately left unfixed there to keep S5 scoped — this finding gives them a real owner. Related: F81 (project-memory precedent for this exact failure mode — a stale reference doc trusted as current).
- **Severity:** Medium — documentation drift in the canonical reference document. No live defect; the risk is a future session trusting a stale snapshot instead of verifying against live state.
- **Inventory (all verified 2026-07-22):**
  - Header, line 5: "Last verified: post Phase 3.8 soak, May 2026" — two phases and roughly 15 sub-deploys stale; the doc is the canonical reference, so the date understates both its authority and its risk.
  - § 1, ~line 26: "No second tenant exists yet" — `comicstore` has been live on prod since Phase 5.5 (2026-07-15).
  - § 1, ~line 31: "GH Pages warm until 5.5 closes" — 5.5 closed; Rick's 2026-07-15 call was to keep GH Pages warm and revisit retirement in a future session, not tied to any phase boundary.
  - § 2, Hosting row (~line 97): "(GH Pages warm until 5.5)" — same stale claim.
  - § 3, ~lines 113–115: "one founding tenant …; no second tenant has been onboarded" — same as § 1.
  - § 1, ~lines 77–79: "the import script hard-codes `TENANT_ID` to the founding tenant" — both `import.js` and `import-staging.js` have been `.env`-driven and credential-free since 2026-07-08.
  - § 3.1, ~lines 144–149: "tenant_id is a top-level constant `TENANT_ID = '72e29f67-...'`" — same as above.
  - **Added 2026-07-25 (found while reproducing F95 on staging):** § 4.9 `user_profiles` states "(No FK to `auth.users` — see Section 3.3)" and § 3.3 says the `id` match is "by convention but not enforced by FK". **Staging contradicts this:** inserting a `user_profiles` row with an `id` absent from `auth.users` is rejected with `{"code":"23503", "message":"insert or update on table \"user_profiles\" violates foreign key constraint \"user_profiles_id_fkey\""}`. The constraint exists and is enforced on staging. **Prod question answered 2026-07-28 without a live query — the answer was already inside § 13:** F64 item 7 records the 2026-06-10 `pg_dump` comparison as "prod has `FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE`; staging does not", and its disposition adds the FK to staging on 2026-06-11 (verified `confdeltype = c`). So **both** environments carry the constraint, and prod has carried it the longer of the two — the § 3.3 / § 4.9 "no FK" claim is wrong about production *more* squarely than about staging, not less. This sub-item needs only the § 3.3 + § 4.9 text correction; no environment audit remains for it. The other inventory items above are unaffected and still require the live pass.
  - **Added 2026-07-28 (found while closing F6 on production) — scope extends beyond this file.** Four references across two *closed feature-plan* docs cite F6's key-only `app_settings` PK as a **live** constraint. It is not: the PK is `(tenant_id, key)` on staging since 2026-07-08 and prod since 2026-07-28. None of the affected decisions change, but the stated reasoning is void and reads as current:
    - `docs/subscription-promotion.md:65-66` — `app_settings` "was considered and **rejected** as the config home: its PK on `key` alone is the F6 multi-tenant collision trap". The decision to use `tenants.branding` stands on its own merits (banner content is public display data, and `branding` needs zero schema change), but the collision half of the rationale no longer applies. This is the reference most likely to mislead, since `branding` vs `app_settings` is a live architectural choice a future session could revisit.
    - `docs/subscription-reserved-suggestions.md:225`, `:249`, `:302`, `:333` — the "F6 trap" is given as why a Playwright spec writing `popular_series` would clobber founding-tenant staging data, and therefore why that case was moved from the spec suite to a manual V5 check. **Under a per-tenant PK a synthetic-tenant spec can no longer collide with founding**, so the constraint that pushed it out of the suite is gone. Moot in practice — the Popular section and its `popular_series` read were removed 2026-07-19 — but recorded because the *reason* is what a future reader would carry forward.
  - **Correctly excluded from this inventory, do not "fix":** § 4.6 (legacy `settings`) still documents a key-only PK, which is accurate — F6 deliberately left that dead table alone. `docs/production-baseline-2026-05-28.md:99` and the `phase-4.1-*` planning notes describe F6 as open, which is correct as-of-date for dated snapshots.
- **Fix direction (future session):** a dedicated re-audit — live-DB pass across every section, refreshed "last verified" line, all stale claims above corrected in one sweep. Not a drive-by edit alongside an unrelated front-door sub-deploy. **Note the scope grew on 2026-07-28:** the last inventory item is in *other* documents, so the sweep is "claims about live state across `docs/**`", not this file alone.
- **Where:** `docs/technical-reference.md` (header line 5; § 1 around lines 26, 31, 77–79; § 2 around line 97; § 3 around lines 113–115; § 3.1 around lines 144–149).

#### F93 — Stray Supabase CLI workdir `C:\Users\richa\supabase` is linked to the PRODUCTION project ref and holds stale Edge Function code — a silent-deploy-to-prod hazard

- **Status:** filed 2026-07-23 (native-customer-signup workstream, S2). **RESOLVED 2026-08-10** — the workdir is unlinked from production. Two files pinned it, not one: `.temp/project-ref` (`plgegklqtdjxeglvyjte`) **and** `.temp/pooler-url`, which carried a production Postgres connection string and would have steered `supabase db` commands as well as function deploys. Both removed (backed up first); verified by `grep -rl plgegklqtdjxeglvyjte C:\Users\richa\supabase\` returning **nothing**. A bare `supabase functions deploy` run there now has no project to deploy to, which is the whole of the hazard. The stale function code is deliberately left in place — it is inert once unlinked, and the directory is listed as an additional working directory in active sessions, so deleting it outright was not taken unasked. **Residual: if anyone re-runs `supabase link` there, the hazard returns.**
- **Two factual corrections to this entry's own text, from measurement 2026-08-10 — the original characterization was wrong in a way that would have caused it to be priced incorrectly:**
  - **The code is not "Feb-2026".** Function `index.ts` mtimes span **2026-05-10 → 2026-07-23** (`register-customer` is the newest, touched during this finding's own filing session). February 2026 is the date of the `.temp/` **link** files, not the code — the original entry conflated the two.
  - **The code is not "pre-multitenancy".** The stray `register-customer` carries `tenant_id` ×2 and `FOUNDING_TENANT_ID` ×5 — it is tenant-*aware*, but hard-pinned to the founding tenant, i.e. the **pre-F34-residual** version superseded on 2026-06-16 (5.4 S2). So a misfire would not leak cross-tenant data; it would revert the F34 un-pin (**breaking tenant-2 signup**) and the F47/F50/F51/F54 auth hardening. Still serious, different failure mode. The staleness itself is confirmed: **248 lines vs the repo's 393**, and it still carries `MAILERLITE_WEBHOOK_SECRET` ×3, an env var the repo baseline no longer references at all. **7 of the 8 functions differ from the repo** (`send-my-list` by 526 changed lines, `register-customer` 443, `notify-customers` 422); only `claim-paper-customer` is byte-identical.
- **Severity:** Medium–High — latent, not yet triggered against production, but a single missed flag away from deploying stale pre-multitenancy code to a live customer-facing endpoint.
- **Symptom:** every `supabase functions deploy/list/download` command run from this repo silently used workdir `C:\Users\richa` instead of the repo directory — printed as `Using workdir C:\Users\richa` in the CLI's own output, easy to miss. That directory has its own `supabase/config.toml` and `functions/` tree dated February 2026: pre-multitenancy, a single hardcoded `MAILERLITE_WEBHOOK_SECRET` env var, no per-tenant secret resolution — materially different (278 vs 248 lines) from the current repo baseline for `register-customer`.
- **Root cause:** this repo's own `supabase/` directory has no `config.toml`, so the Supabase CLI falls back to a workdir it discovers elsewhere — in this case `C:\Users\richa\supabase`, apparently created by an old `supabase init`/`supabase link` run from the home directory rather than the repo. `cat C:\Users\richa\supabase\.temp\project-ref` confirms it is linked to `plgegklqtdjxeglvyjte` — **production** (per § Database project URLs above).
- **Impact this session:** all commands explicitly passed `--project-ref puoaiyezsreowpwxzxhj` (staging), so nothing reached production. But the deploy *source* still came from the stale directory: two `deploy register-customer` calls (without `--workdir`) pushed the stale Feb-2026 code to **staging**, overwriting the correct F34-resolved baseline. Caught via behavioral testing (every request returning the old code's unconditional 401), root-caused by diffing `supabase functions download` output against both the stray directory's file (byte-identical match) and the repo's committed baseline (wholesale different). **Fixed within the same session** by redeploying with an explicit `--workdir "<repo path>"` flag and byte-verifying the redeployed content matched the repo source exactly.
- **Standing risk:** any *future* bare `supabase functions deploy <name>` run from `C:\Users\richa` (or that directory itself) with no explicit `--project-ref` would silently deploy the stale code straight to **production**, with no warning beyond the easy-to-miss "Using workdir" line.
- **Fix applied 2026-08-10:** "re-link it to nothing" — the second of the three options below. `.temp/project-ref` and `.temp/pooler-url` deleted; the remaining `.temp/` files are CLI version caches and pin nothing. The `--workdir` discipline the native-customer-signup workstream adopted is still **good practice and should be kept**, but it is no longer the only thing standing between a bare deploy and production.
  - Original options, for the record: delete the directory, re-link it to nothing, or otherwise ensure it can't be an accidental deploy target.
  - **Not done, and a judgement call worth revisiting:** the directory and its stale code still exist. Deleting it is the durable fix — the repo at `supabase/functions/` is canonical and the stray tree has no value — but it is outside any git repo, so nothing would recover it, and it is an active additional working directory. **Rick's call.**
- **Where:** `C:\Users\richa\supabase\` (outside any git repo, local-only, not tracked by any repo); discovered while deploying `supabase/functions/register-customer/index.ts`.

#### F94 — Cloudflare Turnstile intermittently stuck "Verifying..." → "Verification failed" on the first several real-human attempts against a freshly-deployed widget, resolving on retry

- **Status:** filed 2026-07-24 (native-customer-signup workstream, S4 write-smoke), **open — informational, monitor during/after the 24-hour soak. No code defect found; no fix action pending unless it recurs.**
- **Severity:** Low–Medium. No data-integrity or security issue — `register-customer`'s abuse gate correctly refused every unverified submission (client-side "Please complete the verification," no fetch ever sent; confirmed via live SELECT that zero rows were created by the failed attempts). But it is customer-facing: a real prospective customer hitting this on a first attempt could bounce before retrying.
- **Symptom:** during the live prod write-smoke on `rjbookstop.pulllist.app` (real Turnstile widget, real human), the first submission attempt returned a 500 from `register-customer` itself (response body not captured before Rick retried); a retry then succeeded end-to-end (pending row, correct founding `tenant_id`, magic link, admin approve, login all worked). Several subsequent attempts in the same normal browser window got stuck on the Turnstile widget's own "Verifying..." state, eventually surfacing Cloudflare's own "Verification failed" / Troubleshoot prompt. An incognito Chrome window and a private Brave tab both eventually succeeded.
- **Root cause:** unconfirmed, two candidates considered and neither ruled out: (a) Cloudflare edge-propagation timing — the widget's hostname authorization and/or the `_headers` CSP fix (same session) may not have been fully propagated to every edge node in the first few minutes after deploy, consistent with all successes coming later in the session; (b) Brave's Shields (built-in fingerprinting protection, active even in private/incognito windows, unlike a conventional extension) interfering with Turnstile's non-interactive verification — weakened as the sole explanation by Chrome incognito also needing a retry to succeed. Rick's own read: "likely network propagation related."
- **Fix direction (deferred, only if it recurs):** (a) a client-side "having trouble? try a different browser" hint after N failed Turnstile attempts, or (b) escalate to Cloudflare support with HAR captures if a real (non-test) customer pattern emerges.
- **Where:** `index.html` (`doSignup()`, Turnstile widget wiring); `supabase/functions/register-customer/index.ts` (native path's Turnstile gate) — informational only, no code changed for this finding.

#### F95 — Playwright `deleteUser()` silently fails to remove test profiles, orphaning them in the staging founding tenant

- **Status:** filed 2026-07-25 (surfaced during the arrivals shipment-reconciliation work), **resolved 2026-08-02** in the test-infrastructure maintenance session (`docs/test-infra-maintenance-f91-f95-f103.md`). Unrelated to that feature's diff; noticed only because the reconciliation panel reads `user_profiles` for customer names, which put the leftover rows in view.
- **Resolution (2026-08-02):** `deleteUser()` (`fixtures/auth.ts`) now clears the user's `preorders` by `user_id` first and checks `res.ok` at every step, throwing with status + body on failure — `subscriptions` needs no separate clear since `user_profiles` deletion cascades to it automatically (§ 9.3). This makes the delete **order-independent by construction**, which is what actually fixes the dominant path: the per-test `authenticatedPage`/`adminPage` fixture teardown fires immediately after each test, long before a spec's once-at-the-end `afterAll` ever runs `cleanupTestRows()`, so no amount of reordering those two calls relative to each other could have closed that path — only making `deleteUser()` self-sufficient does. `createUser()`'s compensation-path call to `deleteUser()` (on a failed profile insert) is now wrapped so a cleanup failure appends to, rather than masks, the original error. As defense-in-depth (and to satisfy the letter of the plan's completion criterion), teardown order was also corrected in the specs that had it backwards — `06`, `07`, `10`, `11`, `13` (audited per the plan; `04` was already correct; `09` never had the bug, since no preorder is ever created for either of its tracked users). **One-time staging cleanup:** count query (predicate: `email LIKE 'pw-%@example.test' OR full_name LIKE 'PW %' OR full_name = 'Playwright Test'`) found **292** orphaned rows (up from 87 at filing on 2026-07-25) — `Playwright Test` ×197, `PW Bagging Customer` ×77, `PW Recon Customer` ×9, `PW Second Reserver` ×7, plus one each of two rows sharing full_name `Barry Allen`/`Hal Jordan` with real `pw-shot-...@example.test` fixture emails. Sanity-checked first: a *third*, unrelated `Barry Allen` row (`test@mrcyberrick.us`, created 2026-05-04) shares the name but matches none of the three predicate clauses and was correctly left untouched, confirming the email-pattern discriminator holds even when `full_name` collides. Rick ran the DELETE in the staging SQL Editor; no FK violation; recount returned 0 rows. **Verified:** recount stayed at 0 after 6 additional full-suite runs during V1/V3/V4 gate verification.
- **Residual, NOT a regression (recorded 2026-08-08):** a single orphan, `pw-f5871cc8@example.test`, was found during F121 session 2's teardown check — profile created **2026-08-06T18:30 UTC**, i.e. after this fix landed. **It does not mean the fix regressed, and it should not be read that way.** The fix makes `deleteUser()` throw on any failure, so a genuine delete failure surfaces as a **red test**. A *silent* orphan means teardown never ran at all — the process was killed (Ctrl-C, crash, timeout) between fixture setup and teardown, most likely during the 2026-08-06 F117–F120 session. **No in-process teardown design can protect against that**, so it is an inherent limitation rather than a defect. Deleted 2026-08-08 (F95 order: preorders → profile → auth user, every response checked); recount **0**. **Practical consequence:** a periodic `email=like.pw-*` sweep is worth running after any interrupted suite run — the count is the signal, and a non-zero result after a *clean* run would be a real regression.
- **Severity:** Low–Medium — test-infrastructure hygiene, not a live application defect. Staging only; production untouched. But the residue accumulates monotonically, pollutes the staging founding tenant's customer list and anything counted from `user_profiles`, and will eventually make staging admin screens noisy or skew a staging analytics check.
- **Symptom:** **87 orphaned `PW *` profiles** in the staging founding tenant as of 2026-07-25, created continuously from **2026-06-11 through 2026-07-25** — effectively every suite run since the preorder-seeding specs landed. None retains any `preorders` row, which is what initially made the cause look unclear.
- **Diagnosis (verified against staging, not theorized):** `fixtures/auth.ts` `deleteUser()` issues `DELETE /rest/v1/user_profiles?id=eq.<id>` and **never checks `res.ok`**. Specs call it from `afterAll` *before* `cleanupTestRows()`, so the user's `preorders` rows still exist at that moment, and `preorders.user_id → user_profiles.id` is `ON DELETE NO ACTION` (F10). A controlled reproduction on staging (seed auth user → profile → catalog row → preorder, then replay the fixture's exact order) produced:
  - `DELETE user_profiles` while the preorder exists → **HTTP 409**, `{"code":"23503","details":"Key (id)=(…) is still referenced from table \"preorders\""}`; the profile survives and the fixture discards the status.
  - `cleanupTestRows()` then removes the preorder, stranding the profile with no preorders — exactly the state of all 87 observed rows.
  - The same `DELETE` issued *after* the preorder is gone → **HTTP 200**.
  The GoTrue `auth.users` row does get deleted (that call is unaffected), so each orphan is a `user_profiles` row whose `auth.users` parent no longer exists.
- **Fix direction (future session):** (a) reverse the teardown order so `cleanupTestRows()` runs before `deleteUser()`, or have `deleteUser()` clear the user's `preorders`/`subscriptions` first; **and** (b) check `res.ok` in `deleteUser()` and throw — the silent-failure habit is what let this run six weeks unnoticed. Then (c) one-time cleanup of the existing rows (staging only, verify the count first): `DELETE FROM user_profiles WHERE tenant_id = '<staging founding>' AND full_name LIKE 'PW %'`.
- **Where:** `scripts/playwright/fixtures/auth.ts` (`deleteUser`), plus every spec whose `afterAll` calls `deleteUser()` before `cleanupTestRows()` (06, 13, others). Local-only suite — never committed, so the fix lives outside any repo.
- **Related:** F10 (the `ON DELETE NO ACTION` FKs that block the delete); F91 (the other open Playwright test-infra finding — a future test-infrastructure session could take both together).

#### F96 — `send-brevo-campaign.js` reports success on API acceptance and never verifies the campaign sent — three weeks of suspended sends passed as green

- **Status:** filed 2026-07-25 (surfaced while investigating an unrelated Pages build failure plus Rick's report that Brevo campaigns were being suspended). The *underlying* send failure was root-caused and fixed the same session (see Root cause below); the **detection gap is what this finding tracks**. Fix deployed 2026-07-26 (weekly-pull-feed commit `34074c3e`). **RESOLVED 2026-07-27** — the gap was observed closing on the real thing, both directions, against the live Brevo API:
  - **Negative (gate V4, run `30275663163`):** with the target list emptied, the pre-send guard printed `List 8 ("test - Weekly Pull List"): 0 subscriber(s), 0 blocklisted`, then `ERROR: List 8 has 0 valid recipients … The list is empty. (F96)` and `exit code 1`. Run conclusion **failure**, and a grep for `Creating campaign|Campaign created|sendNow accepted` returned **0 matches** — it aborted before creating anything. **GitHub emailed the failure** ("Send Weekly Newsletter / send — Failed in 12 seconds"), confirmed in Rick's inbox. Under the pre-fix script this identical state produced a *green* run and silent non-delivery.
  - **Positive (gate V5, run `30271641770`):** a healthy send still passes — campaign 21 polled `queued → queued → queued → in_process → sent`, logged `Campaign 21 confirmed SENT`, and the email arrived with 0 apex / 3 founding-subdomain hrefs and 30/30 images HTTP 200.
  - **Residual, stated rather than glossed:** the **post-send status assertion has never been observed rejecting a genuinely suspended campaign.** It cannot be reached from a zero-recipient state — the pre-send guard exits first — and Brevo cannot be made to suspend on demand for a reputation or content reason. What *is* observed is the assertion running against real API responses on a healthy send (including three transient `queued` reads it correctly declined to treat as terminal), plus 9/9 stubbed scenarios covering `suspended`/`draft`/unreadable/unknown. The pre-send guard — the one proven live — is also the one that would have caught this specific outage. Closing on that basis is a judgement call, recorded here so a future session can reopen it rather than rediscover the limit.
  - **Method note:** V4 emptied the list rather than re-blocklisting the contact. The guard fires on `subscribers === 0` alone (`blocklisted` only selects the explanatory string), so both routes exercise the identical branch, and emptying leaves no account-level flag that could silently persist and re-create the original outage 32 hours before an unattended cron.
- **Severity:** Medium. No data-integrity or security exposure, and no PULLLIST customer data is involved (the Brevo list is the separate rjbookstop.com marketing funnel). But it is a silent-failure defect on an outbound customer-facing channel: the pipeline's only health signal reports success unconditionally, so a total delivery outage is indistinguishable from a normal week. It went **18 days undetected** and was found by eye in the Brevo UI, not by any alarm.
- **Symptom:** three consecutive scheduled Tuesday sends — campaigns **#16 (2026-07-07)**, **#17 (07-14)**, **#18 (07-21)** — each logged `Campaign sent successfully` and completed green in GitHub Actions, while every one was **Suspended in Brevo with 0 recipients**. Zero emails were delivered across the entire period. Brevo's Deliverability Center showed **no data at all**, which was the tell: a genuine reputation suspension happens *after* a sample is delivered and would have produced data.
- **Diagnosis (verified against live run logs, not theorized):** `scripts/send-brevo-campaign.js` step 5 issues `POST /v3/emailCampaigns/{id}/sendNow`, and its `brevo()` helper checks only `res.ok` on that HTTP call before the script prints success and exits. Run `29874944032` log timestamps: `Campaign created with ID 18` at `22:47:10.283Z`, `Campaign sent successfully` at `22:47:10.770Z` — **~0.5s**, with no status read in between. Brevo returns 2xx on `sendNow` acceptance; the campaign's actual disposition is only observable via a subsequent `GET /v3/emailCampaigns/{id}`, which the script never issues.
- **Root cause of the underlying outage (resolved 2026-07-25, not part of this finding):** the sole contact in Brevo lists **7** (`rjbookstop - Weekly Pull List`) and **8** (a throwaway test list created during this investigation) was **blocklisted account-wide**. Brevo blocklisting is a per-contact, account-level property rather than a per-list one, so a brand-new test list reproduced the failure exactly. Every campaign therefore resolved to 0 valid recipients and Brevo suspended it at submission. Confirmed via `GET /v3/contacts/lists/{7,8}` → `totalSubscribers=0, totalBlacklisted=1` on both. Unblocklisting the contact produced an immediate successful send with 1 recipient and a received email. **Note the sender domain was investigated first and was a red herring** — `SENDER_EMAIL` was repointed from the Brevo-noncompliant `hello@mrcyberrick.us` to the fully-authenticated `previews@rjbookstop.pulllist.app` (a correct change, retained), but a test send from the compliant sender still suspended, which is what ruled it out.
- **Fix direction (as filed):** after `sendNow`, poll `GET /v3/emailCampaigns/{id}` and assert `status` is `sent`/`inProcess`, exiting non-zero on `suspended`/`draft` so the Action fails loudly and GitHub emails a failure — the same fail-closed posture the existing staleness guard already takes. Optionally also assert a non-zero recipient count *before* calling `sendNow`, which would have caught this specific cause pre-send rather than post-send.
- **Fix implemented (2026-07-26, weekly-pull-feed `34074c3e`) — both gates, including the optional one:**
  1. **Pre-send:** `GET /contacts/lists/{id}`, abort if `totalSubscribers` is 0, with the message naming account-level blocklisting as the likely cause (and that removing/re-adding to the list will not clear the flag). This is the gate that would have caught *this* outage before burning a send. Grounded in the observed failing state (`totalSubscribers=0, totalBlacklisted=1`), not guessed.
  2. **Post-send:** poll `GET /emailCampaigns/{id}` up to 6× at 5 s, bounded so the Action cannot hang. `suspended`/`draft`/`archive` → exit 1; `sent`/`inProcess`/`queued` → pass; an **unrecognized** status also fails closed, on the reasoning that an unconfirmable send is precisely what hid this for 18 days.
  - R2 (false alarms) addressed in code: polls rather than reading once, accepts `queued` as legitimately transient, and status reads use a **non-fatal** helper so a transient 5xx while *reading* cannot turn a successful send red. `DRY_RUN` keeps preview semantics — it warns on an empty list instead of failing.
  - **Verified locally against a stubbed fetch, 9/9 scenarios:** `suspended`/`draft` → exit 1; zero recipients → exit 1 **with `sendNow` never called**; `queued` forever → exit 0; transient 502 then `sent` → exit 0; unreadable status → exit 1; unknown status → exit 1; healthy → exit 0; `DRY_RUN` on an empty list → exit 0 with a warning. The harness lives in the session scratchpad, not in either repo — `weekly-pull-feed` is a Pages **publish target** whose root is served, so test files do not belong in it. Worth parking in the private scripts repo if it is wanted as a regression suite.
  - **What is still unobserved (why this stays open):** the real Brevo status value on a genuinely suspended campaign, and that GitHub actually emails the failure. Note **2026-07-28 22:00 UTC is the first unattended cron run of this script**; if it misbehaves it fails closed — a missed week rather than a silent one.
- **Where:** **separate public repo `mrcyberrick/weekly-pull-feed`** — `scripts/send-brevo-campaign.js` (step 5, after the `sendNow` call) and `.github/workflows/send-newsletter.yml` (cron Tue 22:00 UTC). No file in this repo changes. Pipeline is documented in `docs/weekly-pipeline-consolidation-plan.md`.
- **Related:** F97 (the DMARC gap surfaced in the same investigation). Also note the doc tension flagged during this session: `docs/native-customer-signup.md` § Adjacent describes Brevo weekly-shipment mail as "yet to be developed," while `docs/weekly-pipeline-consolidation-plan.md` documents this live previews sender — possibly two different things (arrival broadcast vs. previews newsletter); reconcile whenever either is next touched. Candidate for the F92 doc re-audit.

#### F97 — `mrcyberrick.us` has no DMARC record while serving as the transactional sender domain for all Edge Function email

- **Status:** filed 2026-07-25 (surfaced during the F96 Brevo investigation, from Brevo's sender-compliance panel), **resolved 2026-07-25** — record published at GoDaddy the same day and verified live at three resolvers (see Resolution). DNS-only change; no code touched. Follow-through owed: read aggregate reports for 2–4 weeks before considering `p=quarantine`.
- **Severity:** Low–Medium today, rising. **Not breaking currently:** PULLLIST's transactional volume is far below the >5,000/day threshold at which Gmail, Yahoo, and Microsoft enforce DMARC for bulk senders, and SPF is present. But the affected mail includes **magic-link logins** — the login path for every customer — so a future deliverability regression here is a customer-facing outage with no in-app signal, and the app cannot detect it.
- **Symptom:** Brevo's Senders panel flags `hello@mrcyberrick.us` as **"Not Compliant — Your sender domain is not authenticated"**, with DKIM shown as `Default` and DMARC as `DMARC policy is not available`. Independent DNS verification the same day (`Resolve-DnsName -Type TXT`):
  - `_dmarc.mrcyberrick.us` → **no record (NXDOMAIN)**
  - `_dmarc.pulllist.app` → `v=DMARC1; p=none; rua=mailto:hello@mrcyberrick.us` (present)
  - `_dmarc.rjbookstop.pulllist.app` → no record, but correctly **inherits** `pulllist.app`'s policy per RFC 7489 organizational-domain fallback
  - SPF on `mrcyberrick.us` **is** present: `v=spf1 include:dc-3cb1d11d42._spfm.mrcyberrick.us include:dc-b48c5c7534._spfm.mrcyberrick.us include:dc-db9e4b7a04._spfm.mrcyberrick.us ~all` (softfail)
- **Scope:** **both environments.** Every Edge Function that sends mail does so from `noreply@mrcyberrick.us` via MailerSend — six `from:` sites across `supabase/functions/`. The Brevo-side DKIM `Default` flag is Brevo-specific and does *not* imply MailerSend's DKIM is missing (MailerSend requires its own DKIM to send at all; that was **not** verified when this finding was filed, but **was** verified before the fix — see Resolution); the **DMARC absence is domain-level and therefore affects MailerSend equally**.
- **Root cause:** not established. `pulllist.app` has a DMARC record while `mrcyberrick.us` — which predates it as the mail domain — never got one and was not revisited when `pulllist.app` was configured.
- **Fix direction (future session):** first confirm MailerSend's DKIM is published and aligned for `mrcyberrick.us`, then add a TXT record at `_dmarc.mrcyberrick.us` starting at **`p=none`** with `rua=` reporting, mirroring the existing `pulllist.app` policy. Review aggregate reports for a few weeks before considering `p=quarantine`. `p=none` is monitor-only and cannot cause legitimate mail to be rejected, so the change is safe to make immediately.
- **Resolution (2026-07-25, verified against live DNS):** the DKIM prerequisite was checked first and **passed** — `mlsend2._domainkey.mrcyberrick.us` CNAMEs to `mlsend2._domainkey.mailersend.net` resolving a valid `v=DKIM1;t=s;p=MIGf…` key, and `mta.mrcyberrick.us` CNAMEs to `mailersend.net`, so MailerSend's custom Return-Path is in place. That combination matters: DKIM signs `d=mrcyberrick.us` (exact match to the `noreply@` From) **and** the bounce domain is a subdomain of the From domain, so both SPF and DKIM align under DMARC's default relaxed mode. The policy was published over mail that already authenticates, not over mail about to start failing. **Zone is GoDaddy** (`ns77`/`ns78.domaincontrol.com`) — *not* Cloudflare; only `pulllist.app` moved to Cloudflare in 5.1, and this distinction is the easiest way to publish the record to the wrong zone. Record added by Rick and verified the same day — identical at the authoritative nameserver and at both `8.8.8.8` and `1.1.1.1`, single record, no duplicate: `_dmarc.mrcyberrick.us TXT "v=DMARC1; p=none; rua=mailto:hello@mrcyberrick.us"`. Aggregate reports land at `hello@mrcyberrick.us` (receives via `mx1`/`mx2.privateemail.com`) as daily gzipped XML; same-domain `rua=` needs no external authorization record, unlike `pulllist.app`'s — see F99. The `p=quarantine` decision is **gated on a report read scheduled for Thu 2026-08-20** (reminder routine `trig_01F3RNgQEVgEES8A7XEWx3Kk`; see F99 § Gates scheduled) — do not tighten the policy before reading the reports.
- **Where:** DNS only — no repo file changes. Sender addresses live at `supabase/functions/*/index.ts` (`from: { email: 'noreply@mrcyberrick.us', … }`).
- **Related:** F96 (same investigation). **F72** (multi-tenant email branding) — whenever per-tenant sending domains land, each needs its own DKIM/DMARC and must not inherit this gap; worth resolving F97 first so the founding domain is a correct template. **F99** — filed at this fix's close: the full sender-domain picture verified here showed transactional and marketing mail split across two domains and two DNS providers, and `pulllist.app`'s own DMARC reporting is undeliverable.

#### F98 — `build-pull-feed.js` publishes ~30 sequential commits, racing the GitHub Pages build — the last ~10 newsletter thumbnails 404 on the live site after every import

- **Status:** filed 2026-07-25 (surfaced minutes after the F96 fix, when the first newsletter ever actually delivered arrived with visible gaps), **resolved 2026-07-26** in the weekly-pipeline hardening session — see Resolution. ⚠️ **The Diagnosis below is wrong and is kept only as the record of what was believed at filing time; F100 carries the corrected mechanism.** The cancelled Actions runs cited here were a *symptom* of the 30-commit burst, not its cause: two independent Pages publishers raced, and a deployment of a mid-burst commit landed 76 s after the tip had already been deployed.
- **Severity:** Medium. Customer-facing on an outbound marketing channel; no data-integrity or security exposure, and no PULLLIST customer data involved. Aggravated by being **silent** — see Related.
- **Symptom:** the 2026-07-25 newsletter rendered 20 of 30 images; the final 10 were broken placeholders (alt text and links intact). Verified by resolving every `<img src>` in the published `newsletter-email.html`: all 30 point at `mrcyberrick.github.io/weekly-pull-feed/thumbs/<md5>.webp`, which 301s to `mrcyberrick.us/weekly-pull-feed/...`. Images **1–20 returned 200; images 21–30 returned 404** — a contiguous tail. Not a WebP/email-client issue: the working and broken images share the same format, host, and redirect chain.
- **Diagnosis (verified against live APIs, not theorized):** the files are **in git but not served**. `GET /repos/.../contents/thumbs` returned 29 thumbnails, and all 10 of the 404ing hashes were present at the deployed commit; `GET /repos/.../pages/builds/latest` reported `status=built` at the repo tip `eba83678`. Cause is the publish shape: `build-pull-feed.js` commits **each thumbnail as its own commit** through the Contents API — roughly 30 commits in ~30 seconds — and every commit triggers a Pages build. The 2026-07-25 workflow list for `14:25:54–14:26:09` shows the `Upload optimized thumbnail: <md5>` runs **cancelled by the Pages concurrency group**, and the cancelled hashes map exactly onto the 404 set (`76c14cb1`, `4522e284`, `78bb5f18`, `a26458ae`, `4a789a08`, `a51921e1`, `3e16c90b`, plus the three immediately preceding). The final build reported the tip commit but its deployed artifact omitted the tail — whatever commits last, loses the race.
- **Workaround (applied 2026-07-25, must be repeated after every import until fixed):** force a rebuild with no new commits — `gh api -X POST repos/mrcyberrick/weekly-pull-feed/pages/builds` — then re-verify. Post-rebuild recheck returned **30/30 → 200**. Because the email **hot-links** images rather than embedding them, the already-delivered message repaired itself in recipients' inboxes with no resend.
- **Fix direction (as filed):** replace the per-file Contents API commits with a **single Git Data API commit** — create blobs, build one tree, one commit, one ref update — so an import produces exactly one commit and one Pages build. That removes the race rather than masking it, and also eliminates the ~30 cancelled workflow runs per import.
- **Resolution (2026-07-26, live and verified):** implemented as filed, in `build-pull-feed.js` (private scripts repo, commit `b727912`). Blobs → one tree → one commit → one ref update, covering the three artifacts and every thumbnail add/remove together. The tree is built on **`base_tree`**, so untouched paths (`index.html`, `images/`, `scripts/`, `.github/`, every cached thumbnail) are inherited rather than re-enumerated — the rewrite cannot strand a file it does not know about. Orphan purges are `sha: null` entries in that same tree, making a thumbnail swap atomic with the newsletter that references it. Preserved semantics: MD5 cache-skip (now against one tree snapshot instead of a per-file probe, so the cache check and the purge planner agree by construction), the orphan purge hashing the same normalized `row[0]`, and the `DEFAULT_IMAGE` fallback on wsrv failure or >100 KB. Added a `verifyPublishedTree()` post-condition (every referenced file present, every purged path gone, all three artifacts there) and a truncated-tree guard.
  - **Rehearsed first (gate V2)** on scratch branch `f98-verify`, created from `main` and deleted afterwards (absence verified): tree diff vs `main` showed 36 thumbs added, 29 removed, 3 artifacts modified and **zero changes outside `thumbs/` and those artifacts**, all in **one** commit instead of ~68. A second consecutive publish reported **36 cached, 0 staged, 0 purged** — both halves of the re-upload/strand risk holding on real data. No workflow run, no legacy build and no deployment fired for the scratch branch.
  - **Live publish** of week 2026-07-27 (commit `24c3035b`): 29 cached, 0 staged, 0 purged, **exactly 1 commit, 1 legacy Pages build, 1 deployment**, and the single commit touched only the two files that actually changed (`newsletter.html` came out byte-identical and was left alone). Live image sweep: **30/30 `<img src>` returned 200 with no manual `pages/builds` rebuild.**
  - **Honest limitation:** that live publish added **zero** new thumbnails, so it did not re-create and then defeat the 404-tail scenario. The 36-new-thumb case was proven at tree level on a branch that was never served. One commit ⇒ one build ⇒ no ordering window is a structural argument, not an empirical one; **the first import bringing genuinely new covers is the true end-to-end confirmation.**
  - **Two defects were found by *running* V2 rather than by reading the diff**, both fixed in the same commit: the post-`PATCH` ref check re-read the ref with a follow-up `GET` and was served a pre-update sha from a replica, aborting a publish that had in fact succeeded; and the "no commit if unchanged" path almost never fires, because `rss.xml` stamps `<pubDate>`/`<lastBuildDate>` with the build time (both newsletters were byte-identical across back-to-back runs). A third, separate defect surfaced at the same gate and was fixed in `808cae4` — see Related.
- **Where:** no file in this repo. Generator `build-pull-feed.js` (the `PREORDER_URL` constant sits at line 921 in the same file) lives in the **private scripts repo** working tree at `C:\Users\richa\…\catalogs\scripts\`; publish target is the separate public repo `mrcyberrick/weekly-pull-feed`. Pipeline documented in `docs/weekly-pipeline-consolidation-plan.md`.
- **Related:** **F100** — the corrected mechanism; read it instead of the Diagnosis above. **F96** — same pipeline, and the two compounded badly: F96 meant the Action reported success unconditionally, F98 meant images failed without any error, so a broken newsletter produced no signal anywhere. Both were fixed in the same pass on 2026-07-26, as intended; F96 remains open only pending its observation gate. **Wrong-week default (fixed 2026-07-26, `808cae4`, no finding ID assigned — caught and closed inside the same session):** a bare `node build-pull-feed.js --publish` defaulted the target week to the one containing *today*, but the newsletter previews the *upcoming* shipment, so any run after the current week's on-sale date targeted already-shipped comics. Run on 2026-07-26 it would have replaced the live preview of week 2026-07-27 with week 2026-07-20's shipped titles and purged all 29 live thumbnails. `import.js` was never affected (it passes the shipment's earliest `on_sale_date`), but the recovery hint it prints on failure is exactly that bare command. Now derived from `max(on_sale_date)` in `weekly_shipment`, deliberately data-derived rather than weekday-derived since `on_sale_date` is not always a Wednesday.

#### F99 — transactional and marketing mail are split across two sender domains on two DNS providers; consolidate the sending identity onto `pulllist.app`

- **Status:** filed 2026-07-25 at the close of the F97 fix, while the complete sender-domain picture was verified in front of us. **Open — deferred to a dedicated session; not started.** Direction only, no plan doc yet. **Must be designed together with F72, not sequenced ahead of it.**
- **Severity:** Low as a defect — nothing is broken, nothing is blocked, no data or security exposure. Medium as a **decision**: the split is customer-visible (a customer receives marketing mail from `rjbookstop.pulllist.app` and magic-link logins from `mrcyberrick.us`, a domain carrying no PULLLIST branding), it spreads email authentication across two DNS providers, and deferring it past F72 means provisioning sender domains **twice**.
- **Current state (verified against public DNS 2026-07-25):**

  | | `mrcyberrick.us` | `pulllist.app` |
  |---|---|---|
  | DNS provider | **GoDaddy** (`ns77`/`ns78.domaincontrol.com`) | **Cloudflare** (`morgan`/`tia.ns.cloudflare.com`; registrar is Namecheap — registrar ≠ DNS host) |
  | Web | GitHub Pages (`185.199.111.153`) | Cloudflare Pages (`172.67.160.220`) |
  | MailerSend (transactional) | ✓ DKIM `mlsend2._domainkey`, Return-Path `mta` → `mailersend.net` | **absent — nothing provisioned** |
  | Brevo (marketing) | — | ✓ on `rjbookstop.pulllist.app`: SPF `include:spf.brevo.com`, DKIM `brevo1`/`brevo2` CNAMEs both resolving valid keys, `brevo-code` verification TXT |
  | DMARC | ✓ `p=none` (F97, 2026-07-25) | present, but **reports undeliverable** — see blocker below |

- **The design decision this finding exists to force:** flat `noreply@pulllist.app` versus per-tenant `<slug>.pulllist.app`. **Recommend the per-tenant subdomain.** Brevo's sender already sits at `rjbookstop.pulllist.app` — set ad hoc during the F96 incident when `SENDER_EMAIL` was repointed off the noncompliant `hello@mrcyberrick.us` — so the tenant-slug shape is already established and fully authenticated. It is also precisely what **F72** needs, since per-tenant email branding requires a per-tenant sending identity. Branding consistency and multi-tenancy then fall out of one structure. A flat apex sender would have to be torn out and redone when F72 lands.
- **Blocker on the destination domain — RESOLVED 2026-07-25, same session as filing:** `_dmarc.pulllist.app` publishes `rua=mailto:hello@mrcyberrick.us` — a **cross-organizational-domain** reporting address — with **no** RFC 7489 §7.1 authorization record at `pulllist.app._report._dmarc.mrcyberrick.us` (verified **NXDOMAIN** at the authoritative nameserver, 2026-07-25). Conformant reporters (Google, Microsoft, Yahoo) must discard those reports, so `pulllist.app` has never delivered a single aggregate report despite carrying a policy since ~2026-06-11 — and it now has a live sending subdomain under that policy. This is exactly the telemetry needed **during** a sender migration to confirm the new domain authenticates. Fix is one TXT record, name `pulllist.app._report._dmarc`, value `v=DMARC1`, **in the GoDaddy zone** — the name's parent zone is `mrcyberrick.us`, not `pulllist.app`, so adding it in Cloudflare produces an inert `…_dmarc.pulllist.app` record that looks correct in the UI and does nothing. **Rick published the record in GoDaddy the same day**; verified live at the authoritative nameserver and at both `8.8.8.8` and `1.1.1.1`: `pulllist.app._report._dmarc.mrcyberrick.us TXT "v=DMARC1"`. Both domains are now observable. Never given its own finding ID — it was raised, decided, and fixed inside this entry's filing session.
- **Fix direction (dedicated session):** (1) ~~publish the reporting-authorization record above so both domains become observable~~ — **done 2026-07-25**; (2) let 2–4 weeks of aggregate reports accumulate and read them **before** changing any sender address — they are a free, accurate inventory of everything currently sending as either domain, which is hard to reconstruct any other way; (3) verify the chosen sending domain in MailerSend and add its DKIM + Return-Path CNAMEs **in Cloudflare**; (4) update the six `from:` sites, staging first, then promote through the standard workflow; (5) re-verify DMARC alignment on the new domain before retiring the old sender identity. **`mrcyberrick.us` is not being retired as a domain** — it remains the GitHub Pages rollback surface at `/comic-preorder/` and serves the F98 newsletter thumbnails at `/weekly-pull-feed/`. Only the sending identity moves.
- **Reputation note:** no warm-up concern. The F96 campaigns were suspended at submission with zero recipients, so no delivery ever occurred and no reputation signal — good or bad — was generated on either domain; the cause was a per-contact account-level blocklist flag, not domain reputation. A new sending domain likewise starts with no reputation, which only matters to senders above a few thousand messages/day. PULLLIST is orders of magnitude below that.
- **Gates scheduled (2026-07-25):** DMARC report accumulation opened 2026-07-25; two one-time reminder routines armed, both 8:00 AM ET, both auto-disabling after they fire. **(1) Plumbing check — Thu 2026-07-30** (`trig_01FQyE78dntEjDhoWtzuds7L`): confirm aggregate reports are actually arriving at `hello@mrcyberrick.us` for **both** domains, spam folder included — a mail filter eating the gzipped XML is the likeliest silent failure, and catching it at day 5 rather than day 28 is the whole point of this being a separate boundary. **(2) Full read + `p=quarantine` decision — Thu 2026-08-20** (`trig_01F3RNgQEVgEES8A7XEWx3Kk`): read ~4 weeks of reports, which serves F97's follow-through *and* step (2) above. Dates are Thursdays deliberately: the natural 2–3 day and 4-week marks land on Tue/Wed (shipment + bagging) or on 2026-08-08, which is both a Saturday and inside the early-August import week.
- **Where:** six `from:` sites — `supabase/functions/{approve-customer,invite-customer,notify-customers,register-customer,reset-password,send-my-list}/index.ts` — across **both** staging and production. DNS: `pulllist.app` in Cloudflare, `mrcyberrick.us` in GoDaddy. Provider dashboards: MailerSend (transactional), Brevo (marketing).
- **Related:** **F72** (multi-tenant email branding) — the coupling is the point of this finding; design them together. **F97** (resolved 2026-07-25) — fixing it produced the verified picture above. **F96** — the `SENDER_EMAIL` repoint to `previews@rjbookstop.pulllist.app` was effectively step one of this consolidation, done ad hoc under incident pressure rather than by design.

#### F100 — `weekly-pull-feed` publishes to GitHub Pages from two independent deployers with no ordering guarantee between them; this, not cancelled Actions runs, is what broke F98

- **Status:** filed 2026-07-26 at the opening of the weekly-pipeline hardening session, while verifying F98's recorded mechanism before rewriting the publish path. **Open — deferred; nothing left broken.** The F98 single-commit fix neutralizes the harm on the import path (one commit ⇒ both deployers publish the *identical* tree, so their ordering stops mattering), so this finding tracks the residual structural hazard, not an active outage.
- **Severity:** Low as long as publishing stays single-commit; Medium the moment anything pushes `main` more than once in quick succession. No data-integrity or security exposure and no PULLLIST customer data involved — the blast radius is the marketing newsletter's served assets.
- **Symptom:** none directly observable. This is the mechanism *behind* F98's contiguous tail of 404ing thumbnails.
- **Diagnosis (verified against the live Pages, Deployments, and Actions APIs — this corrects F98):** the repo deploys to the `github-pages` environment from **two** independent publishers that neither coordinate nor share a concurrency group:
  1. **`pages-build-deployment`** — GitHub's built-in builder. `GET /repos/mrcyberrick/weekly-pull-feed/pages` reports **`build_type: legacy`**, source `main` / `/`. It fires on **every push to `main` regardless of path**, and it is what `POST /pages/builds` (the F98 workaround) drives.
  2. **`Deploy GitHub Pages`** — the repo's own `.github/workflows/deploy-pages.yml`, running `upload-pages-artifact` + `deploy-pages@v4` under `concurrency: pages` with `cancel-in-progress: true`. It genuinely deploys: its last run's `Deploy to GitHub Pages` step succeeded and the deployment appears in `/deployments`.

  The decisive evidence is the **deployment** list, not the workflow list. During the 2026-07-25 burst: `14:26:11 → eba83678` (tip), `14:26:34 → eba83678` (tip), then **`14:27:50 → aa794c02`** — a **mid-burst** commit (its legacy build ran at `14:25:48`), deployed *last*, roughly 76 seconds after the tip had already been deployed twice. The live site was therefore left serving a tree captured partway through the thumbnail sequence, which is exactly a contiguous-tail-of-missing-thumbs. Rick's manual rebuild at `22:17:12` redeployed the tip and produced 30/30. Corroborating: of ~30 legacy builds in that window, ~28 report `status=errored` with `duration=0ms`, and the two clean builds of the *same* commit `eba83678` took **18,704 ms** (14:26:08, during the burst) versus **33,658 ms** (22:16:48, the quiet manual rebuild) — the burst-time build did materially less work.
- **What F98 got wrong:** F98 attributed the tail-404s to the `Upload optimized thumbnail: <md5>` workflow runs being cancelled by the `concurrency: pages` group, noting the cancelled hashes mapped exactly onto the 404 set. That observation was accurate but **causally inverted** — the cancelled Actions runs and the errored legacy builds are both *symptoms* of the same 30-commit burst, not the cause. The cause is that a stale-tree deployment won the race. This matters beyond bookkeeping: it means eliminating the cancellations alone would not have fixed anything, and it means an F98 completion criterion phrased as "one Pages build, no cancelled `Upload optimized thumbnail` runs" counts the wrong artifact. **Assert one deployment of the tip commit via `/deployments`, plus one `/pages/builds` entry.**
- **Related hazard (not yet acted on):** because the built-in builder ignores path filters entirely, the custom workflow's path list is decorative with respect to what actually serves. Worse, `actions/configure-pages` can flip `build_type` from `legacy` to `workflow`; if that ever happens, which deployer owns the live site changes silently, and `POST /pages/builds` — the documented F98 workaround — stops working.
- **Fix direction (future session):** settle on **one** publisher. Either (a) delete `deploy-pages.yml` and let the built-in legacy builder own publishing (matches today's `build_type`, keeps the `pages/builds` workaround working; risk: a later switch to `build_type: workflow` silently stops publishing), or (b) switch Pages to `build_type: workflow` so the custom workflow is the sole deployer with real concurrency control and meaningful path filters (cleanest end state; breaks the `pages/builds` workaround). Rick's call 2026-07-26 was to file rather than change a live publishing surface inside the hardening session — see § Related.
- **Partial hardening already applied (2026-07-26, commit `604cfaec` in `weekly-pull-feed`):** `deploy-pages.yml`'s `push` trigger had path filters but **no branch filter**, so a push to *any* branch touching those paths would have deployed that branch's tree over the live site. A `branches: [main]` filter was added, which was a prerequisite for running the F98 rewrite's scratch-branch tree-diff gate (V2) safely. The built-in builder only ever builds its configured source branch, so it was never the scratch-branch risk; the custom workflow was.
- **Where:** no file in this repo. `mrcyberrick/weekly-pull-feed` — `.github/workflows/deploy-pages.yml` plus the repo's Pages configuration (Settings → Pages, `build_type`). Pipeline documented in `docs/weekly-pipeline-consolidation-plan.md`; session plan `docs/weekly-pipeline-hardening.md`.
- **Related:** **F98** — this finding corrects its diagnosis; F98's fix remains correct and is what makes this one non-urgent. **F96** — same pipeline, same silent-failure family: F96 is the send reporting success it never verified, F98/F100 the publish failing with no signal at all.

#### F101 — distributor order exports carry no FOC window: any title in the current catalog month is ordered regardless of which order cycle its FOC belongs to

- **Status:** filed 2026-07-27 during a title-reconcile question about two PRH codes rejected as UNKNOWN. **RESOLVED 2026-08-03 — live on staging AND production** (promoted via PR #100, merge `5951a30`; production verified byte-identical to `main` and post-deploy smoke passed). Plan: `docs/order-export-foc-window-and-order-state.md` (executed together with F102).
- **Resolution (2026-08-03, staging):** both order exports now go through an **Order Builder** modal on the By Distributor tab instead of downloading immediately. It lists every distinct `foc_date` among that distributor's unfulfilled current-month reservations with per-cycle title/copy counts, **multi-select**, defaulting to the earliest not-yet-passed FOC date. Everything held back is shown, grouped by reason — **Backordered** (FOC passed, never ordered), *At risk*, *Outside selected cycle*, *Ad-hoc ordered*, *no-FOC* (included regardless, matching `admin.html`'s existing null-FOC convention), and a fulfilled count — with Backordered and "outside selected cycle" visually distinct, per this entry's own "surface, never silently drop" requirement. Null-FOC handling follows the in-file precedent at the shelf-copy suggested-order path rather than reinventing it.
- **S1 band measurement (2026-08-03) — the default is empirical, not invented.** Intersected the archived order files against production `catalog.foc_date`: the May 24 cycle spans **8** distinct PRH FOC dates (5/25 → 7/13) and 6 Lunar; the June 27 cycle spans **8** PRH (6/22 → 8/17) and 8 Lunar; July's covered 8/10–8/31. **No stable offset exists** between submission date and FOC band, confirming § 2.2's ruling that `order_deadline` cannot anchor the export. The preselected default is therefore the earliest not-yet-passed FOC date, stated as a convenience the operator overrides — never a derived rule.
- **Backorder-risk panel (§ 4.5) shipped** as a persistent admin-dashboard panel above the export bar, hidden when empty. It reuses `isFocThisMonth()` and `isFocPast()` from `app.js` rather than reimplementing date logic (F28's precedent), reads `Settings.getOrderDeadline()` for the second trigger, and classifies **At risk** / **Backordered** / cleared-by-ledger. A code with any `order_submissions` row drops off the list regardless of date — proven by gate V7(c), which is the assertion that distinguishes "reads the ledger" from "only reads the date".
- **Verification:** V2 (byte-identical export on a clean slate — empty ledger + all cycles selected reproduces the pre-fix sheet exactly, asserted against the real staging dataset through the unmodified `makeOrderSheetRows`), V3 (a two-cycles-out title excluded **and** listed under *outside selected cycle*), V7 (all three backorder states) — 22 logic assertions total, run against the **actual functions extracted from `admin.html`/`app.js` by line range**, not reimplementations. Full `run-smoke.ps1` green (46 unit + 50 Playwright) on every deploy. Real-browser check confirmed by Rick 2026-08-03. All seeded fixtures torn down and verified by live SELECT returning zero rows.
- **Accepted divergence (recorded per the plan's § 5 OUT):** the **reserved-titles report** and the **Paper Orders tab** remain **month-scoped** and now legitimately **disagree with the export**, which is FOC-cycle-scoped. This was Rick's explicit scoping call, not an oversight — but it means the two surfaces answer different questions and should not be reconciled against each other. Anyone changing either should decide deliberately whether to adopt the FOC window there too.
- **~~Still open, inherited by F108~~ — now planned (2026-08-03):** a reservation pointing at a withdrawn advance record (the MIDNIGHT X-MEN #2 case that surfaced this finding) has no customer-facing or admin-facing signal. This session warned *before* the FOC lock bites; it does not detect a title the distributor rejected or withdrew. **That thread now belongs to F110, not F108** — detection is a set difference over the catalog files already on disk and does **not** need the order-confirmation samples F108 is blocked on. Rick settled the customer-facing half on 2026-08-03 ("Admin + customer flag", incl. re-enabling cancellation on withdrawn titles). Plan: `docs/order-export-followthrough-f110-f111-f112.md`.
- **Domain correction (2026-08-02, from a planning interview with Rick) — the fix direction below is under-specified:** a catalog month carries **many** FOC cycles (July 2026 had **13** distinct FOC dates, 07/20 → 11/09), and there is **no derivable rule** mapping a catalog month to an order band. Critically, `app_settings.order_deadline` — which already exists (`app.js:622–631`, `admin.html:1048–1086`) and was 7/24 for July — is the **customer** reservation cutoff, **not** the submission date, and cannot anchor the export window: July's sheet reached PRH covering FOC **8/10–8/31**, with nothing at 07/27 or 08/03. The band is driven by the distributor's own cycle dates. The plan therefore makes cycle selection **explicit** (multi-select over the FOC dates present in the data) rather than derived. Also newly recorded: **ad-hoc orders exist** — when a title's FOC locks before the monthly order goes out, it is ordered separately and **must be excluded from the monthly order**, which is a second, independent route to F102's duplicate failure. None of this was visible from the code.
- **"Backordered" — the store's term, and the state the FOC lock exists to prevent (2026-08-02, Rick).** A reservation whose FOC passed **without an order having been placed** is *Backordered*. Use this term in code, UI and docs. Why it is worse than it first appears: the FOC lock (`isFocLocked` → `isFocPast`, `app.js:1358–1370`) is a **hard** cutoff that blocks new reservations **and cancellations** — `catalog.html:1217–1218` treats an already-reserved locked title as *committed*. So the lock commits the **customer** independently of whether the **store** ordered. **Wording corrected 2026-08-03:** this entry originally continued *"…and that cannot arrive."* Per Rick (§ 13 F112(b), overruled the same day), a Backordered title **can still be ordered on either distributor, with availability unguaranteed** — so "cannot arrive" is too strong here and is accurate only for a title **withdrawn** upstream (**F110**). The failure is real and still urgent; it is recoverable rather than terminal. Rick's stated intent is to actively avoid this state, so the plan adds an **admin backorder-risk panel** (at-risk vs Backordered) triggered when a reserved title's `foc_date` falls in the current calendar month **and/or** on-or-before `app_settings.order_deadline`. Note `isFocThisMonth()` (`app.js:1375+`) already computes that first condition and is already in customer-side use at `catalog.html:601` — reuse it; reimplementing the date logic is how F28 recurs.
- **Severity:** Medium — real money and real customer expectations. Titles are submitted to the distributor one or more cycles before they are orderable; the distributor rejects them, and the rejection is caught only by reading the order confirmation by eye. No data-integrity or security exposure. Both environments (same client code).
- **Symptom:** codes present on the PULLLIST order sheet come back **UNKNOWN** from PRH at order entry, while the same codes resolve to correct titles inside the app. Presents as a code↔title mapping fault; it is not one.
- **Live instance (production, verified 2026-07-27):** `75960621668000211` (MIDNIGHT X-MEN #2 COVER A, `Primary Title`) and `75960621668000221` (#2 COVER B, `Variant Title`), both `catalog_month = 2026-07`, both **`foc_date = 2026-10-12`**, on sale `2026-11-18`. Every other title on the same cycle's sheet has an FOC of 8/10–8/31. **8 copies** were queued against them — Cover A ×7 (Jay Underhill, Mike Bieksha, Book Stop ×3, Brian Moss, Albert Abaunza), Cover B ×1 (Book Stop). PRH rejected both.
- **Diagnosis:** `allPreorders` is scoped to `currentCatalogMonth` (`admin.html` ~486) and nothing downstream narrows further. `makeOrderSheetRows` (`admin.html` ~837–868) filters on `!p.fulfilled` only; the Lunar (~884–901) and PRH (~907–924) exports add a `distributor` filter and nothing else. **Catalog month is not an order cycle.** A monthly distributor file legitimately contains advance records whose FOC falls one, two, or more cycles out — Marvel/PRH routinely solicit with 3-month leads, flagged by `TBD ARTIST` in the title — so a single catalog month mixes several FOC cycles, and the export ships all of them.
- **Corroborating (why the codes then vanish):** advance records are provisional and get withdrawn or re-issued. The July PRH feed re-pulled 2026-07-25 carries ten MIDNIGHT X-MEN rows, **all issue #1**; the August feed (pulled 2026-07-26) carries none. So the #2 records PULLLIST imported in early July no longer exist upstream at all — the app is faithfully reporting what PRH published and then retracted. This is expected distributor behaviour, not a feed defect, and it is why an FOC window (not a data fix) is the remedy.
- **Fix direction (future session):** filter both order exports to the FOC cycle being ordered rather than the catalog month — derive the target FOC window and exclude rows outside it, with the excluded set surfaced in the UI rather than dropped silently (an admin must be able to see that a title was held back, or this trades one silent failure for another). Decide whether the reserved-titles report and the Paper Orders tab adopt the same window; they are currently month-scoped and consistent with each other, and changing only the export would make the two disagree.
- **Customer-facing consequence to settle in the same session:** a reservation against a withdrawn advance record is left pointing at a title that can no longer be ordered, with no signal to the customer or the admin. Related to **F89**/**F90** (nothing records order or claim outcomes), and to the open product question of representing partial fulfilment.
- **Where:** `admin.html` — `makeOrderSheetRows` (~837–868), `btn-export-lunar` handler (~884–901), `btn-export-prh` handler (~907–924); month scoping at ~486. Both staging and production.
- **Related:** **F102** — same export path, independent mechanism; both were found in the same reconcile and a session touching the export should read both. **F80** — the other case of catalog-month scoping producing a silent wrong-month result. **F85** — cross-month duplicate reservations, the same root tension between catalog months and physical titles.

#### F102 — `fulfilled` is an arrival flag, not an order flag, so a re-listed long-lead title is re-exported to the distributor on every cycle until it physically arrives

- **Status:** filed 2026-07-27 alongside F101, from the same production reconcile. **RESOLVED 2026-08-03 — live on staging AND production** (promoted via PR #100, merge `5951a30`). Plan: `docs/order-export-foc-window-and-order-state.md` (executed together with F101). **The realized 12-against-7 surplus is now recorded in production's own ledger** and shows on the By Distributor tab as an over-order — but **the surplus itself is still outstanding**: adjusting that PRH order down before FOC 2026-08-31 is operational, not something code fixes (reminder scheduled 2026-08-24).
- **Resolution (2026-08-03, staging) — a code-keyed ledger, exactly as § 2.6 required:** new table **`order_submissions`** (`docs/sql/order-submissions.sql`), keyed on the **distributor code** (`order_code`) so it survives a re-listing, with `tenant_id` FK CASCADE, CHECK constraints on `distributor` (`Lunar`/`PRH`) and `order_type` (`monthly`/`adhoc`), two indexes, and admin-only RLS (SELECT + INSERT, both `tenant_id = current_tenant_id() AND current_user_is_admin()`, explicit `TO authenticated`). **No unique constraint on `order_code`** — re-ordering is legitimate; the ledger records history and the export reasons over it. Append-only: no UPDATE/DELETE policy, matching `reservation_history`'s posture.
- **Write path:** a **"Mark Ordered"** action on the By Distributor tab (modal: quantity, `monthly`/`adhoc`, submitted-on date), written **manually after ordering** — not on export click, since generating a file is not proof of submission. **Defaults to `adhoc`** (Rick, 2026-08-03).
- **Duplicate surfacing (§ 4.3) — surfaces, never auto-suppresses.** At export time each code is looked up in the ledger; hits appear in an **"Already ordered"** panel with prior quantity, date, cycle and order type, each with an include/exclude checkbox and an editable quantity **pre-filled with the remaining amount** (reserved − already-ordered). On the live MIDNIGHT X-MEN shape this suggests **2**, which is the correct action — not 7 (what happened) and not 0 (what auto-suppression would have done). Gate **V4** asserts the row is flagged with prior qty and is *not* auto-suppressed.
- **Per-title order state, added 2026-08-03 after Rick's real-browser review:** the By Distributor **Status column is a single button** whose label and colour carry the state — `Mark Ordered` (nothing on the ledger) → `◐ Add (n of m)` (ordered < reserved, amber) → `⚠ Over (n of m)` (ordered > reserved, red, **still clickable** — surface, never block) → `✓ Ordered (n)` (exact match, **disabled**). This is what makes the F102 failure mode visible *per title, at a glance*, rather than only inside the export flow. **The over-order state is the one this finding exists for** and it is now impossible to look at the tab and not see it.
- **Ad-hoc exclusion (§ 4.4):** a ledger row with `order_type = 'adhoc'` excludes that code from the monthly export and lists it as excluded (gate **V5**) — closing the second, independent route to the same duplicate failure.
- **Customer-facing consequence (scope extension, Rick 2026-08-03):** "Order placed" on **My List** is now driven by the ledger, **independent of `fulfilled`** — Rick's words: *"The fulfilled status is not relevant as Marked Ordered should show the Order placed status."* Because `order_submissions` is admin-only under RLS, a new SECURITY DEFINER RPC **`get_ordered_codes()`** (`docs/sql/get-ordered-codes-rpc.sql`) exposes only `(distributor, order_code)` pairs — no quantities, dates, or titles — tenant-scoped via `current_tenant_id()` internally, never a client parameter; `EXECUTE` to `authenticated` only. `Preorders.cancel()` gained a matching second guard refusing to cancel a code with any ledger row, and `exportCode()` moved from `admin.html`-local into `app.js` so the cancel guard, My List and the exports share one fallback chain. **Verified end-to-end** with real throwaway staging users: the RPC returns correct tenant-scoped rows for a non-admin session, and the guard refuses an ordered code while permitting a non-ordered one (positive *and* negative control).
- **"Mark Fulfilled" removed (Rick, 2026-08-03):** rather than the § 4.6 relabel, Rick's call was that manual fulfillment tracking is meaningless without POS integration (out of scope), so the manual toggle and its handler are gone. **`fulfilled` itself is untouched** — same column, same RLS, still set automatically by `auto_fulfill_past_on_sale()` at import, and `Preorders.setFulfilledByCatalogId()` is left in `app.js` unused for a future POS path. This supersedes the § 4.6 decision gate, which had been answered "additive" earlier the same session.
- **Ledger seeded (§ 4.7 / S5) — the feature is not inert.** 857 rows backfilled from the real archived order files (`docs/sql/order-submissions-backfill-may-june-july.sql`): May 24 (93 PRH + 55 Lunar), June 27 (131 + 137), July 26 (212 + 229). The July files did not exist in `Orders Archived/` when the backfill was first drafted and were added by Rick mid-session; **they confirm this finding directly** — `prh-order-2026-07-26.txt` carries `75960621668000111,7`, which against June's `,5` is the 12-against-7 surplus. **Caveat (cause corrected 2026-08-03):** 708 of the 857 staging rows have NULL `title`/`foc_date`. That was first attributed to staging's catalog lacking the history; the larger cause was a defect in the one-off generator script — its catalog lookup was **silently truncated at PostgREST's 1000-row default**, the same class as **F82**, so it saw a fraction of the catalog and reported the rest as unmatched. Fixed by paging until a short read. Harmless either way (no FK; the duplicate check and the panel both match on `order_code` alone, and nothing reads `title`/`foc_date`), so the staging rows were left as-is rather than re-run. **The production backfill was regenerated with the paginated lookup and matched 857/857 — zero NULLs** (`docs/sql/order-submissions-backfill-PROD.sql`).
- **Residual — the cancel guard is client-side only.** `Preorders.cancel()`'s ledger check, like the pre-existing `fulfilled` check it mirrors, lives in application code; `preorders` RLS lets a user delete their own row, so a client bypassing `Preorders.cancel()` could still cancel an ordered reservation. Pre-existing posture, now covering a money-relevant guard — filed as **F109** rather than left implicit.
- **Production promotion — COMPLETED 2026-08-03,** in this order: (1) `docs/sql/order-submissions.sql`; (2) `docs/sql/get-ordered-codes-rpc.sql`; (3) `docs/sql/order-submissions-backfill-PROD.sql` (857 rows, **857/857 codes matched** production's catalog, zero NULL titles); (4) client via PR #100 (merge `5951a30`). **Verified on production before promoting:** RLS denies anon with all 857 rows present, and `get_ordered_codes()` returns correct tenant-scoped codes to a real authenticated non-admin session (throwaway fixture, torn down, 0 rows remaining). **Verified after:** `admin.html` byte-identical to `main`, and Rick's post-deploy write-smoke passed.
- **Still outstanding, and code does not fix it:** PRH holds 12 copies of `75960621668000111` against 7 reservations, FOC **2026-08-31**. The ledger now *shows* it (the By Distributor row reads as an over-order) but adjusting the order down is an operational call to PRH. Reminder scheduled for 2026-08-24 (routine `trig_01D8pWAMP5uuLqqb62gDjGrY` + calendar).
- **Automated coverage added 2026-08-03 (`tests/15-order-export-ledger.spec.ts`, 6 tests).** This path shipped to production with none, exactly as the info-card path did in July (F103). Covers V3 (excluded *and* surfaced), V4 (flagged with prior qty, remainder-defaulted, not auto-suppressed), the four Status-button states, V7 (At risk / Backordered / cleared-by-ledger), and My List reading "Order placed" from the ledger with `fulfilled` still false. Suite total 50 → 56. **Note for anyone extending it:** staging carries the 857 backfilled rows, so seeded fixtures share every panel with production-shaped data — assert on a seeded title or `data-catalog-id`, never `.first()` and never an exact count. The first draft did use `.first()` and failed against a real staging title, which is the useful version of that mistake.
- **Ledger cross-cycle scan, run on production 2026-08-03 once the backfill landed:** **12** codes appear on more than one cycle, not the 1 that this entry's original sweep found. Eleven are Lunar codes ordered on the May cycle (qty 2–3) and again on the June cycle at **exactly qty 1** — the shape of a later customer reservation topping up an existing order, which is legitimate and is precisely why `order_submissions` carries no unique constraint on `order_code`. The twelfth is MIDNIGHT X-MEN #1, where July re-sent the **full** reservation count (7) rather than a top-up — the re-export signature, and the real surplus. **Caveat:** the ledger does not record how many were reserved at each submission, so the top-up reading is a strong inference from the quantity shape, not proof. Worth re-checking against memory or invoices if any of the eleven look wrong. All twelve would have been surfaced in the "Already ordered" panel for a human call, which is the designed behaviour.
- **Correction (2026-08-02, from a planning interview with Rick) — this entry's headline claim is true of the code but not of the practice.** *"`fulfilled` is an arrival flag, not an order flag"* describes what the code means. In actual use, a reserved title is treated as **ordered** when it is manually set via **"Mark Fulfilled"** on the By Distributor tab (`admin.html:666`, `:699` → `Preorders.setFulfilledByCatalogId`) — Rick's words: *"not the best description of what is happening."* So an order record does exist; it is mislabelled, and — the part that actually causes the duplicate — **keyed on `catalog_id`**, which does not survive a re-listing. **Consequence for the fix:** this entry's *"per-reservation (or per-code-per-cycle) `ordered_at`"* hedge names the wrong option first. A `preorders.ordered_at` column inherits **exactly** the flaw this entry diagnoses in `fulfilled` — a re-listed title gets a new `catalog` row (upsert key `(tenant_id, item_code, distributor, catalog_month)`, § 4.3) and new `preorders` rows that start unmarked. Only a ledger keyed on the **distributor code** works; that is the identity that persisted across `2026-05`/`-06`/`-07` in the live instance. Also settled: the duplicate check must **surface, not auto-suppress** — auto-suppression would have ordered **0** copies where **2** were correct (12 held, 7 reserved, 5 already on order). Finally, reconciliation today runs off **shipping reports**, which cannot surface a rejection (a rejected title simply never ships); Rick's assessment is that **invoice reconciliation is the more accurate source** — filed separately as **F108**.
- **Severity:** Medium — a duplicate-ordering path with direct, realized cost exposure, but a **rare trigger**. The mechanism is general; firing it requires the uncommon combination of (a) submitted on an earlier cycle, (b) still unarrived so never marked `fulfilled`, and (c) re-listed by the distributor in a later catalog month under the same code — which in practice means the publisher re-dated the book *after* its FOC. Measured incidence: **1 of 268** codes submitted on the June cycle reappears on the July sheet (sweep below). No data-integrity or security exposure. Both environments. *(Filed initially as "Medium-to-High … systematic rather than specific to one title"; the sweep corrected that — general in mechanism, rare in practice.)*
- **Symptom:** none in the app. A title already submitted to the distributor on an earlier cycle reappears on a later cycle's order sheet, indistinguishable from a title never ordered.
- **Diagnosis:** the order exports exclude a reservation only when `p.fulfilled` is true (`makeOrderSheetRows`, `admin.html` ~838). `fulfilled` is set by the admin **at arrival** — `Preorders.setFulfilledByCatalogId` is documented "used when an entire title arrives" (`app.js` ~876–885) — so a title ordered in June but on sale in October stays unfulfilled for months and remains eligible for export the entire time. Two compounding factors: (a) `fulfilled` is keyed to a specific `catalog_id`, so when a title is re-listed the following month the carried-forward reservations point at a **new** catalog row that starts unfulfilled regardless of the previous row's state; (b) nothing anywhere records that a code was ever sent to a distributor — the order `.txt` files are generated, downloaded, and forgotten. There is no order state in the schema at all.
- **Live instance (production) — CONFIRMED REALIZED 2026-07-27:** `75960621668000111` (MIDNIGHT X-MEN #1) exists as three catalog rows — `2026-05` and `2026-06` both at FOC `2026-07-06` / on sale `2026-08-05`, and `2026-07` at FOC **`2026-08-31`** / on sale **`2026-10-07`**. PRH pushed the book back nine weeks and re-listed it under the identical code. The archived June submission `Orders Archived/prh-order-2026-06-27.txt` contains **`75960621668000111,5`**; the July cycle submitted **7 more** against the same code. **PRH did not roll or cancel the June order — Rick confirmed the supplier now holds an order for 12 copies.** Against **7** current reservations (Jay Underhill, Mike Bieksha, Book Stop ×3, Brian Moss, Albert Abaunza) that is **5 surplus copies**, exactly the June quantity. Remediation window: FOC `2026-08-31` had not passed at time of filing, so the order was still adjustable downward.
- **Scope sweep (2026-07-27) — how much else is exposed:** intersected every code submitted on the June cycle (`prh-order-2026-06-27.txt` + `lunar-order-2026-06-27-excl-fulfilled.txt`, 268 codes) against every code on the July reserved sheet (`Reserved Titles — July 2026.pdf`, 437 codes). **Exactly one overlap: `75960621668000111`.** So the realized damage is this title alone, not a standing backlog. This is the number to re-measure after any future cycle rather than assuming the rate holds — the trigger is publisher behaviour, not ours, and a month with several post-FOC re-dates would produce several duplicates with no more warning than this one gave.
- **Fix direction (future session):** record order state, not just arrival state. Minimum viable is a per-reservation (or per-code-per-cycle) `ordered_at` written when an order export is generated, with the exports excluding already-ordered codes and the admin able to see and override. This is a schema change plus an export change, so it pairs naturally with **F90**'s import-time snapshot work rather than being bolted onto the client alone. Re-dated titles need an explicit decision: when a distributor re-lists an already-ordered code under a new FOC, the correct behaviour is probably to surface it for a human call, not to auto-suppress or auto-reorder.
- **Interim safeguard until the fix lands (no code required):** before submitting each cycle's order, intersect the new order file against the previous cycle's archived `prh-order-*.txt` / `lunar-order-*.txt`. Any code in both is a re-listed title already on order and needs a human decision. On Git Bash this is one line — `comm -12 <(cut -d, -f1 <prev>.txt | sort -u) <(cut -d, -f1 <new>.txt | sort -u)` — and it is exactly the sweep that found the 1-of-268 above. This is worth doing every cycle regardless of when the code fix arrives, because it is the only check that does not depend on anyone remembering a specific title.
- **Detection gap worth noting:** like **F96**, the failure produced no signal — the June order and the July sheet are both individually correct, and only holding the two archived files side by side reveals the overlap. It was caught because a *different* symptom (F101's UNKNOWN rejections on the #2 codes) sent someone into the same data. Nothing would have surfaced it otherwise, and the surplus would have shown up as five unexplained copies in an October shipment. Any fix should be judged on whether it would have made this visible without someone going looking.
- **Where:** `admin.html` — `makeOrderSheetRows` (~837–868) and both export handlers (~884–924); `app.js` — `Preorders.setFulfilled` / `setFulfilledByCatalogId` (~862–885) for the `fulfilled` semantics. Schema: `preorders` (no order-state column). Both staging and production.
- **Related:** **F101** — same export path, found together, independent fixes. **F85** — cross-month duplicate reservations; the multi-month catalog rows that make this finding possible are the same structure. **F90** — schema + import-script session that this should probably ride along with. **F89** — the same absence of outcome instrumentation, on the claim/invite path.

#### F103 — Playwright `seedCatalogRow()` dates seeds by the calendar month while the catalog page scopes to the newest month *in data*, so founding-tenant seeds are invisible whenever the imported catalog runs ahead of the wall clock

- **Status:** filed 2026-07-27 (surfaced running the smoke suite to verify the `catalog.html` info-card reserve fix, commit `fdb5f52` — since promoted to production 2026-07-28 via PR #99, `d08d10d`). **Resolved 2026-08-02** in the test-infrastructure maintenance session (`docs/test-infra-maintenance-f91-f95-f103.md`). Unrelated to that commit's diff; see *Not caused by the change under test* below.
- **Resolution (2026-08-02):** `seedCatalogRow()` (`fixtures/catalog.ts`) now defaults `catalog_month` to a data-derived value — a `defaultCatalogMonth()` helper reads the target tenant's newest `catalog_month` via one PostgREST call mirroring `Catalog.getLatestMonth()` (`?tenant_id=eq.<id>&select=catalog_month&order=catalog_month.desc&limit=1`), cached per tenant per run so every default-seeded row in a spec lands in the same month regardless of how many seeds that spec makes. Falls back to `thisCatalogMonth()` only when the tenant has no rows yet, which preserves the synthetic per-run tenant's existing behaviour exactly (its first seed becomes its only, and therefore latest, row). `thisCatalogMonth()` remains exported for specs that deliberately opt into calendar-month behaviour (`07`'s RPC month param, `13`'s explicit cross-month seeding) — untouched. **Verified (V3):** specs `02`, `03`, `07` all passed on every run, founding-tenant and synthetic-tenant assertions alike, across all 6 runs during V1/V3/V4 gate verification. Note the fix landed on a date (2026-08-02) where the calendar month happened to coincide with the founding tenant's latest imported month, so these runs alone could not distinguish "fixed" from "coincidentally not exercising the bug" — the fix's correctness rests on mirroring the app's own query and the explicit fallback-when-empty behavior, not on this session's particular run dates.
- **Coverage gap closed:** the info-card reserve path this entry's diagnosis flagged as having zero spec coverage now has some — `tests/14-catalog-info-card-reserve.spec.ts` (2 tests, added same session as the optional S4 step): modal reserve at qty>1 repaints both the modal and the underlying grid card (`.reserved-indicator`, `.btn-reserve`), and a grid-reserved item opens the modal already reflecting that state. Not exhaustive (no FOC-locked-modal case, no admin-impersonation case), but no longer zero.
- **Severity:** Low–Medium — test-infrastructure only, staging only, no live application defect and no production exposure. Raised above Low because the failure mode is a **red suite that looks like a product regression**: four specs fail with "element(s) not found" on a card that was seeded successfully, which invites exactly the wrong diagnosis, and it will recur on most runs.
- **Symptom:** 4 failures (8 including retries) in the 2026-07-27 run, all the same shape — `expect(locator).toBeVisible()` timing out on a `.comic-card` / `.col-title` matching a just-seeded title:
  - `02-catalog-reserve-mylist` → `reserve from catalog shows row in mylist` (line 30, *before* the reserve click on line 32)
  - `03-mylist-cancel-guards` → `cancel removes row; FOC-locked shows chip + disabled qty; …` (line 35, on `mylist.html`)
  - `07-tenant-isolation` → `user A catalog sees only tenant A rows` (line 70) and `user A mylist excludes tenant B preorders` (line 103)
  44 tests passed, including all synthetic-tenant specs.
- **Diagnosis (verified against live staging, not theorized):** `fixtures/catalog.ts` `thisCatalogMonth()` returns the **calendar** month (`new Date()` → `YYYY-MM`) and `seedCatalogRow()` uses it as the default `catalog_month`. The catalog page scopes its grid to `Catalog.getLatestMonth()` (`app.js` ~432–440), which is `SELECT catalog_month ORDER BY catalog_month DESC LIMIT 1` — the newest month **present in data for that tenant**, not the current date. Queried live on 2026-07-27:
  - founding tenant latest `catalog_month` = **`2026-08`** (the August catalog has been imported)
  - `thisCatalogMonth()` would seed = **`2026-07`**
  Every founding-tenant seed therefore lands in a month the page never renders. The **synthetic per-run tenant is immune** because the seeded row is the only row it has, so its newest month *is* the seeded month.
- **The tenant split is the proof, and `07-tenant-isolation` contains it in one file:** `TENANT_A = FOUNDING_TENANT_ID` and tenant B is the synthetic tenant. `user A catalog sees only tenant A rows` **failed** while `user B catalog sees only tenant B rows` **passed** — the same assertion, the same code path, differing only in which tenant was seeded. Across the whole run the correlation is exact with no exceptions: every founding-tenant row-visibility assertion failed, every synthetic-tenant one passed.
- **Not caused by the change under test (`fdb5f52`, catalog info-card reserve sync):** (a) all four failures fire at row-visibility assertions that precede any interaction with the changed code — spec 02 dies on line 30, the reserve click is line 32; (b) spec 03 fails entirely on `mylist.html`, which that commit does not touch (its diff is `catalog.html` + `style.css` only); (c) the changed functions `syncCardState`/`syncModalState` execute only inside `toggleReserve()` after a DB write returns, and cannot affect whether a seeded row renders; (d) the specs that *do* exercise the reserve path (`10-post-reserve-prompt`, 8 tests incl. reserve and cancel; `11-reserved-suggestions`) all passed.
- **Why it started failing now:** the defect is latent whenever the imported catalog month equals the calendar month and active otherwise. Catalog imports run **ahead** of the wall clock (the August catalog was loaded during July), so the *normal* state for most of any month is broken, and the suite self-heals misleadingly for the stretch where they happen to coincide. This is a standing false-red, not a one-off.
- **Fix direction (future session):** make the seed month data-derived rather than date-derived — have `seedCatalogRow()` default `catalogMonth` to the target tenant's actual newest `catalog_month` (one PostgREST read, mirroring `getLatestMonth()`), falling back to `thisCatalogMonth()` only when the tenant has no rows, which preserves current synthetic-tenant behaviour exactly. Keeping `thisCatalogMonth()` as an explicit opt-in is fine for specs that deliberately test month scoping. **Do not** "fix" this by pinning the fixture to a hardcoded month — that just relocates the same drift.
- **Coverage gap noted while diagnosing (related but distinct):** no spec references `#modal-reserve`, `#modal-qty`, or `.reserved-indicator` — the catalog **info-card** reserve path has no automated coverage at all, which is why the four defects fixed in `fdb5f52` shipped unnoticed and why a green suite would not have verified that fix either. (The `.qty-minus-btn` assertions in spec 03 are `mylist.html`'s own stepper, a different control.) Worth adding alongside the fixture fix.
- **Where:** `scripts/playwright/fixtures/catalog.ts` — `thisCatalogMonth()` (~14–17) and `seedCatalogRow()` default `catalog_month` (~45). Affected specs: `02`, `03`, `07` (user-A cases). Local-only suite — never committed, so the fix lives outside any repo. Staging only.
- **Related:** **F91** and **F95** — the other two open Playwright test-infra findings; all three are local-only fixture defects and a single test-infrastructure session should take them together. **F80** — the other case of catalog-month scoping producing a silent wrong-month result.

#### F104 — the `guard-git` commit-time secret scanner excludes `config.js` entirely, so a service-role key pasted there would commit clean

- **Status:** filed 2026-07-28 (noticed while reading `.claude/hooks/guard-git.ps1` to assess whether it was safe to publish in the public repo — see the tracking decision in `.gitignore`). **Open — deferred; low priority.** No plan doc. **This entry's own subject (the `config.js` exclusion) is UNCHANGED and still open.** A *separate, unrelated* defect in the same hook was fixed 2026-08-10 — see the Guard 1 note below.
- **Guard 1 path-resolution bug — FIXED 2026-08-10 (separate defect, same file, recorded here because this entry is where the hook's blind spots are catalogued).** Guard 1 resolves the target repo from the command text, then runs `git -C $dir remote get-url origin`. The Bash tool issues **POSIX** paths (`cd "/c/Users/.../scripts"`), which git cannot resolve when the hook runs under PowerShell, so the lookup failed, `$origin` came back empty, and the deliberate fail-closed branch blocked the push as *"unresolvable repo"* — **including pushes to `comic-preorder-scripts`, which the hook's own message states are allowed.** It stranded three scripts-repo commits (`5bc7461`, `4b83ae3`, `f9df045`) and was misread in two documents as policy rather than a bug. Fixed with a leading drive-token translation (`^/([A-Za-z])/(.*)$` → `X:/…`); anything unmatched falls through unchanged and still fails closed. **Verified old-vs-new across four cases:** scripts-repo→main went BLOCK→ALLOW (the bug), comic-preorder→main stayed BLOCK, →staging stayed ALLOW. The guard was not weakened — only the case it was never meant to catch changed. BOM confirmed intact and the file re-parsed with 0 errors afterwards (§ Known Issues & Gotchas: agent edits strip the UTF-8 BOM from `.ps1`).
- **Guard 1 entry-gate bypass — FIXED 2026-08-10 (found by the test written for the bug above).** The gate read `$cmd -match 'git\s+push'`, requiring `git` and `push` to be **adjacent**, while the path extractor immediately below it allowed an optional `-C <path>` between them. Two expressions describing the same thing, disagreeing — so **`git -C <repo> push origin main` never entered Guard 1 at all**, and a direct push to production `main` in that form was entirely unguarded. That is the exact form used to push to another repo without changing directory. Fixed by hoisting **one** `$pushRe` used by both the gate and the extractor, so they cannot drift apart again. Deliberately **not** widened to `git\s+.*push`, which would match `git config push.default` and block legitimate commands.
  - **Regression suite, 8 cases, run against the original and fixed hooks** (`scratchpad/hook-test.ps1`, local-only): bash-`cd`→scripts/main **BLOCK→ALLOW**; bash-`cd`→comic-preorder/main **BLOCK** both; →staging **ALLOW** both; `git -C <win comic-preorder>`→main **ALLOW→BLOCK** *(this fix)*; `git -C <win scripts>`→main and `git -C <posix scripts>`→main **ALLOW** both; `git config push.default` **ALLOW** both *(false-positive guard)*; legacy `push staging staging:main` **BLOCK** both. **All 8 pass on the fixed hook.** Note the two `-C <scripts>` cases passed on the *original* hook **by accident** — the gate never fired, so they were allowed rather than correctly cleared; only on the fixed hook is the repo actually resolved and discriminated.
  - **Live confirmation, unplanned:** the first attempt to run this suite as an inline command was itself **blocked by the newly-widened hook**, because the test *data* contained a `-C … push origin main` string. Correct behaviour, and a reminder that Guard 1 matches command **text**, so any command merely quoting a push-to-main is caught. The suite was moved into a file.
- **Guard 1 chained-`cd` misresolution — FIXED 2026-08-10 (third Guard 1 defect that day; found when the hook blocked a legitimate two-repo commit-and-push).** When the push carries no `-C`, the hook infers the working directory from the last `cd`/`Set-Location`/`Push-Location` before it. That regex's leading alternation was `(?:^|;)` — start-of-string or semicolon only. **The Bash tool chains with `&&`,** so in `cd A && git add x && cd B && git push origin main` only `cd A` was recognised (it sits at `^`) and `cd B` was invisible, leaving `$dir` pointing at **the repo the push does not run in**. Fixed to `(?:^|;|&&|\|\|)`, and `&` added to the unquoted-path branch's exclusion set so `cd /path&&git push` cannot swallow the separator into `$dir`.
  - **Why it survived: it fails closed.** The misresolved path was a POSIX one git could not read, so `$origin` came back empty and the push was **blocked**. It denied legitimate work rather than permitting a bad push — the same shape as the POSIX-path bug above, and the same reason nobody noticed. **Every Guard 1 defect found on 2026-08-10 was a false negative or a false block, never a false permit** — except the `-C` bypass, which was a genuine hole.
  - **Suite extended to 11 cases:** chained `cd CP && … && cd scripts && push origin main` went **BLOCK→ALLOW** (resolves to the last directory, correctly clearing the scripts repo); the reverse chain and a `;`-separated chain both stay **BLOCK**. All 11 pass on the fixed hook. Two cases (`-C <scripts>`, and the reverse chain) had "passed" on the original **by accident**, reaching the right verdict through a failed path lookup rather than correct discrimination — worth stating, because a green result from a broken mechanism is not evidence.
  - **The tracked backup must be synced by hand.** The live hook is untracked in this public repo by design; `comic-preorder-scripts` holds the only versioned copy at `claude-config/hooks/guard-git.ps1`, and its `.gitignore` says plainly *"Keep them in sync by hand; nothing enforces it."* It was found **stale** after the first fix on 2026-08-10 — restoring from it would have silently reintroduced the bug — and was re-synced after each of the three fixes (BOM verified, 0 parse errors, hash-identical each time). **This is a standing trap: any future hook edit must be copied across, and nothing will remind you.**
  - **Still open in this entry:** all three 2026-08-10 fixes were to **Guard 1** (push blocking). **Guard 2, the secret scanner that is this finding's actual subject, is untouched** — `config.js` remains excluded wholesale, so a service-role key pasted into the one file where a key-shaped value is expected would still commit clean.
- **Severity:** **Low.** This is a defence-in-depth gap, not a live exposure. Nothing is currently leaked, and three independent things have to fail before it matters: someone must put a service-role key in `config.js` (which the agent is forbidden to edit at all, per CLAUDE.md § Credential Safety), no human must notice it in the diff, and the commit must reach the public repo. Recorded because the *reason* for the exclusion is sound and will otherwise look deliberate-and-therefore-fine to a future reader who does not check what it costs.
- **Symptom:** none observed. No key has been committed; this is a latent hole in a guard, found by reading the guard rather than by any failure.
- **Diagnosis:** Guard 2 in `.claude/hooks/guard-git.ps1` runs `git diff --cached -- . ':(exclude)config.js'`, then matches three patterns (`sb_secret_[A-Za-z0-9]{16,}`, `sb_publishable_[A-Za-z0-9]{16,}`, `eyJhbGciOi[A-Za-z0-9_\-]{20,}`) against **added lines only**. The `config.js` exclusion is deliberate and correct in intent — that file legitimately carries the public anon/publishable key, and scanning it would block every legitimate config commit. The cost is that `config.js` is the one file in the repo where a secret-shaped value is *expected*, so it is also the one file where a wrong one is invisible to the guard.
- **Other blind spots in the same guard, recorded together rather than as separate findings:** (a) fires on `git commit` only — `git add` and `git push` are unguarded, so a key already committed by another route is never re-checked; (b) added lines only (`^\+`), which is the correct trade-off documented in the hook's own comments but does mean a pre-existing line is never re-examined; (c) only three key shapes — a MailerSend/Brevo/GoDaddy credential, a `.env` file, or a base64/line-wrapped key would not match; (d) the hook `exit 0`s (fails **open**) when stdin is empty or the JSON payload will not parse, whereas Guard 1 deliberately fails **closed** on an unresolvable origin. The asymmetry looks unintentional.
- **Why it is not urgent:** the anon/publishable key in `config.js` is public by design (RLS is the security boundary), the agent never edits `config.js`, and service-role keys live only in the gitignored scripts-folder `.env`. The guard's primary job — catching an *accidental* commit by a well-intentioned agent — is unaffected, since accidents do not route around exclusions on purpose.
- **Fix direction (future session, low priority):** rather than dropping the exclusion (which would false-positive on every legitimate `config.js` change), scan `config.js` with a **narrower** rule — allow `sb_publishable_` / `eyJhbGciOi…` values whose decoded role is `anon`, block `sb_secret_` and any JWT whose payload carries `"role":"service_role"`. That distinguishes the key that belongs there from the key that does not. Separately, consider failing closed on an unparseable payload for symmetry with Guard 1.
- **Where:** `.claude/hooks/guard-git.ps1`, Guard 2 (the `git diff --cached` line and the `$patterns` array). **Local-only and intentionally untracked in the public repo** — `.gitignore` tracks `.claude/skills/` but excludes `settings.json` and `hooks/`, because publishing the scanner documents its blind spots. Versioned in the private scripts repo instead. Both environments (the hook is machine-level, not per-branch).
- **Related:** **F75** / **F86** — the key-rotation and legacy-key-retirement work this guard exists to protect. **F103**, **F91**, **F95** — the other open local-only tooling findings; this one is *not* Playwright, so it does not have to ride along with them.

#### F105 — a blocking pre-flight gate went unmet and Phase 5.5 closed anyway with its completion criteria recorded as ticked; the gap survived 13 days and was found by an unrelated audit

- **Status:** filed 2026-07-28 (surfaced while closing F6 on production, during a § 13 findings-index cleanup). **Open — process finding, no code or schema fix.** No plan doc.
- **Severity:** **Medium.** No damage occurred in the instance that exposed it — but the mechanism is a gate that reports itself satisfied while unsatisfied, and it recurs on every future tenant onboarding. Severity reflects the mechanism, not this instance's luck.
- **Symptom:** `docs/sql/f6-app-settings-pk-rekey.sql` carried an explicit, unambiguous gate — *"Run: STAGING first, verify, then PRODUCTION as part of 5.5 pre-flight"* and *"WHY THIS MUST LAND BEFORE TENANT 2"*. Staging ran 2026-07-08. Tenant 2 (`comicstore`) went live on production **2026-07-15**. The production run did not happen until **2026-07-28**, 13 days later, and only because a findings-index audit re-read F6's status line and noticed its precondition had a date attached that had already passed. Phase 5.5 and Phase 5 were both recorded Complete on 2026-07-15 with Phase Completion Criteria described as all ticked.
- **What made it invisible, in order:**
  1. **The gate lived in a SQL file, not in the plan's completion criteria.** `docs/phase-5.5-second-tenant-onboarding.md` § Phase Completion Criteria is what gets walked at close. Nothing in the F6 runbook wrote itself into that checklist, so walking the checklist honestly still produced a green result.
  2. **The finding's own status line was the only tracker,** and it stated the dependency in prose — "must land before tenant 2 onboards" — rather than as a checkable item. Prose preconditions are not checked by anything.
  3. **CLAUDE.md had already stopped listing F6 as open** (its § Open findings line names F72, F89–F96, F99–F104; F6 is absent, covered by the blanket "all other findings through F102 are resolved"). So the session-opening read of CLAUDE.md actively signalled that F6 needed no attention, while § 13 still said "Prod run pending".
  4. **Nothing failed at runtime.** The collision needs a second tenant to *write* a setting; `comicstore` is pilot/seeded and never touched the admin settings panel. Silence was indistinguishable from correctness — see F6 for why the failure, had it fired, would also have been silent.
- **Scope:** process/documentation. Production was exposed but undamaged (verified 2026-07-28: `rjbookstop` held both keys, `comicstore` held none). Applies to both environments and to any future phase using the same close procedure.
- **Why this is not just "F6 was late":** the same shape exists wherever a runbook states a precondition that no checklist enforces. The `CLAUDE.md` § Definition of Done merge gate is written for *sub-deploys* and asks whether the plan's boxes are ticked — it has no way to notice a gate that was never made into a box. **"Most of the work looks done" is not done** is already the stated rule; this is its sibling failure, where the work genuinely looks done because the unmet item was never enumerated.
- **Fix direction (future session, no code):** at minimum, a close-time rule that any runbook or SQL file carrying a "must land before X" precondition gets that precondition copied into the gated plan's Completion Criteria as a checkbox at the moment the precondition is written — not at close, when the person walking the list has no reason to go looking. Worth considering alongside it: a close-time grep for pending-state phrases ("prod run pending", "must land before", "gated on") across `docs/**` and § 13, since all three of this instance's tells were greppable strings sitting in the repo the whole time. The `/schedule-gate` skill already exists for *time*-gated steps; this is the *dependency*-gated equivalent and has no equivalent mechanism.
- **Where:** `docs/phase-5.5-second-tenant-onboarding.md` § Phase Completion Criteria; `docs/phase-5-second-tenant-onboarding.md` § Phase Completion Criteria; `CLAUDE.md` § Definition of Done — Merge Gate and § Current Migration Phase; `docs/sql/f6-app-settings-pk-rekey.sql` (the gate's origin).
- **First application, same day it was filed:** **F9** carried an identical prose precondition ("must land before tenant 2 runs a shipment import") sitting in exactly the place this finding says preconditions get lost. It was written into `docs/tenant-onboarding-runbook.md` § Step 7 as a checkbox on 2026-07-28, with its verification query and a stop instruction inline. Two things that worked out here and are worth repeating: the item states its **real trigger** (first shipment import) rather than inheriting the step's position, because a gate filed under the wrong trigger is the same failure in a new place; and it went in the list that is actually **walked**, not the finding that is merely *read*. The distinction between those two is the whole finding.
- **Related:** **F6** — the instance that exposed this, and the source of the 13-day window. **F9** — the first precondition converted under this finding's fix direction. **F92** — the adjacent failure mode (a canonical doc trusted while stale); both are cases of a written record diverging from live state with nothing checking. **F81** — the project-memory precedent for stale docs being trusted as current. **F103** — filed the previous day, likewise found by an audit rather than by an alarm.

#### F106 — F96's own status assertion failed a campaign Brevo delivered at 100%: `STATUS_HEALTHY` carried camelCase `inProcess` while the API returns `in_process`

- **Status:** filed **and resolved 2026-07-29**, same session — surfaced by the first unattended cron run of the rewritten send script. Fix live in `mrcyberrick/weekly-pull-feed` commit **`95d5eec8`**.
- **Severity:** Medium. **No delivery impact** — the newsletter reached all recipients. The damage is to the alarm: this would have fired **every Tuesday**, and an alarm that cries wolf weekly is one the operator learns to ignore, which would quietly undo the entire point of F96. Worse over time, since more recipients means longer in `in_process`.
- **Symptom:** the scheduled send on 2026-07-28 (run `30406602527`, campaign **24**, 9 recipients) reported **100% delivery in Brevo** and still turned the Action red after 42s:
  ```
  [4/6] status=in_process sent=0
  [5/6] status=in_process sent=0
  [6/6] status=in_process sent=0
  ERROR: Campaign 24 returned an unrecognized status "in_process". Failing closed…
  ```
- **Diagnosis:** `const STATUS_HEALTHY = ["sent", "inProcess", "queued"]` — camelCase. Brevo's API returns snake_case **`in_process`**. A campaign still legitimately in flight when the poll window closed therefore matched neither `STATUS_BROKEN` (correctly) nor `STATUS_HEALTHY` (incorrectly) and fell through to the catch-all "unrecognized status" failure. **The design was already right and the branch already existed** — the tail reads `"accepted and in flight, not suspended … which is normal for larger lists"` and exits 0. It was simply unreachable. A pure literal defect, not a logic one.
- **Provenance — a doc propagated the wrong value into code:** the S3 spec in `docs/weekly-pipeline-hardening.md` said *assert `status` ∈ {`sent`, `inProcess`}*, written from memory of Brevo's API conventions rather than checked against a live response. The implementation faithfully followed the plan. Both the S3 spec and the R2 mitigation line in that doc were corrected the same session. **A wrong literal in a planning artifact is as harmful as one in code, and harder to spot, because review compares code *to the doc*.**
- **Why gate V5 did not catch it:** V5 sent to **one** recipient and reached `sent` on poll 5 of 6 — inside the window — so `in_process` was only ever a transient value passed through, never the value present at window close. Nine recipients did not finish in time. **A one-contact list cannot exercise this timing path.** This is the *second* time in this workstream a single-contact list produced misleading confidence (see F96's own residual), and the standing lesson is that a gate must be run against a representative list size, not merely a non-empty one.
- **Fix (`95d5eec8`):** `STATUS_HEALTHY` now `["sent", "in_process", "inProcess", "queued"]` — both spellings, since the camelCase form does appear in parts of Brevo's own documentation and one vendor inconsistency has already cost a false alarm. `ATTEMPTS` also raised 6 → 10 (~50s) so a typical send still reaches a definitive `confirmed SENT` rather than the weaker in-flight message. Verified by unit-testing the decision cascade against the **deployed** constants (parsed out of the live file, not retyped): 8/8 cases correct — `in_process`/`inProcess`/`queued` pass as in-flight, `sent` passes as confirmed, `suspended`/`draft`/`archive` still fail as broken, an unknown status still fails closed.
- **Does not weaken the guard:** every suspension actually observed in this workstream was applied **at submission** and surfaced immediately as `suspended`, never after a prolonged `in_process`. Nothing that previously failed now passes.
- **Residual:** the fix is proven by unit test against the real constants, but **not yet by a live multi-recipient send** — that is the scheduled run on **Tue 2026-08-04**. Recorded rather than glossed, for the same reason as F96's residual.
- **Where:** separate public repo `mrcyberrick/weekly-pull-feed` — `scripts/send-brevo-campaign.js` (`STATUS_HEALTHY`, `ATTEMPTS`). No file in this repo. Plan: `docs/weekly-pipeline-hardening.md`.
- **Related:** **F96** — this is a defect *in F96's fix*, found on its first unattended run. F96's own closure stands: the script did verify and did fail closed, which is exactly what it was built to do; it simply failed closed on the wrong input.

#### F107 — Playwright suite hit a Supabase GoTrue `429 over_request_rate_limit` on the 3rd run of two separate back-to-back-triple gate-verification sequences

- **Status:** filed 2026-08-02 during the test-infrastructure maintenance session's V1/V4 gate verification (`docs/test-infra-maintenance-f91-f95-f103.md`). **Open — informational, not reproduced under normal (single-run) conditions.** No plan doc.
- **Severity:** Low, tentative. Observed exactly twice, both times on the *third* run of a rapid three-consecutive-full-suite sequence executed for gate verification (6 full runs total across ~45 minutes), never on a sequence's first or second run. A normal pre-push workflow runs the suite once, not six times in under an hour, so this has not been shown to affect ordinary usage of the suite.
- **Symptom:** `10-post-reserve-prompt.spec.ts` → `declined series is never re-prompted on a later page load` flaked twice (Playwright auto-retried and the overall suite still exited 0 both times):
  - Run 3 of the first triple (immediately after the F91 fix, V1 gate): `page.fill: Test timeout of 60000ms exceeded … waiting for locator('#search')`, no root cause visible in the captured snapshot.
  - Run 3 of the second triple (V4 gate, after adding the new spec `14`): identical `#search` timeout, but this time the captured page snapshot shows the actual page content at failure time was raw JSON: `{"code":429,"error_code":"over_request_rate_limit","msg":"Request rate limit reached"}` — i.e. the magic-link redirect hit Supabase's own rate limiter instead of completing, so the app never loaded and `#search` never appeared.
- **Diagnosis (partial — not confirmed beyond the visible page snapshot):** each full run creates on the order of a few dozen users and generates a matching number of magic links via `fixtures/auth.ts`'s `createUser()`/`generateMagicLink()`. Running the suite six times in under 45 minutes for this session's gate verification is a request-volume pattern a normal single pre-push run would not produce, and the failure correlates exactly with the third run of each triple — consistent with a per-project GoTrue rate limit (magic-link generation and/or OTP-verify redirect) being approached cumulatively rather than tripped by any single run. Not confirmed against Supabase's documented rate-limit thresholds; that check was not done this session.
- **Distinguishing this from F91:** different HTTP status (429 vs 403), different `error_code` (`over_request_rate_limit` vs `bad_jwt`), and a different Supabase subsystem (request-volume throttling vs the JWT/key-verification path F91's fix addresses) — F91's bounded retry (`fetchGotrueAdmin`) only retries on `403`+`bad_jwt` and would not fire, let alone add request volume, in response to a 429. The two should not be conflated even though both are GoTrue-admin-adjacent and both surfaced during the same session's gate runs.
- **Scope:** local Playwright suite only (`fixtures/auth.ts` magic-link path); staging only. No live-application or production exposure.
- **Fix direction (future session, if it recurs):** first reproduce under a single normal run or a deliberately-spaced sequence before treating this as actionable — two occurrences under artificial repeated-run pressure, both self-resolving on Playwright's built-in retry, are not yet evidence of a defect in the suite itself. If it does recur under normal conditions, likely directions are spacing out gate-verification runs (documented in `docs/test-infra-maintenance-f91-f95-f103.md`'s own methodology for next time) or checking Supabase's dashboard-configurable auth rate limits for the staging project.
- **Where:** `scripts/playwright/fixtures/auth.ts` (`generateMagicLink`, the `page.goto(link)` redirect it feeds); observed in `tests/10-post-reserve-prompt.spec.ts`.
- **Related:** **F91** — the other GoTrue-admin-adjacent test-infra finding surfaced in the same session; distinct mechanism, see above.

#### F108 — no order-invoice reconciliation: distributor rejections are invisible because reconciliation runs off shipping reports, where a rejected title is indistinguishable from one not yet shipped

- **Status:** filed 2026-08-02 during the planning interview for the F101/F102 session (`docs/order-export-foc-window-and-order-state.md`). **UNBLOCKED and PLANNED 2026-08-04 — not started.** Plan: `docs/order-loop-closure-f108.md`. Explicitly scoped OUT of the F101/F102 session by Rick on 2026-08-02, on the grounds that stopping the duplicate-order bleed comes first and this needs sample invoice files before it can be planned concretely. **The sample-file blocker is now gone:** operator screenshots on 2026-08-04 confirmed Lunar exposes a per-order view with a **`CSV Download`** link (order `1804145`), per-line status (**Shipped / Partially Shipped / Processing**), ship date, in-store date and Due Date; PRH exposes an order view with per-line **Est Delivery**. The files themselves have still not been *opened* — the plan's Session A is specification-only and forbids writing a parser from screenshots, per the F110/F112 precedent where reading the real vendor material corrected two wrong fix directions before either reached code.
- **Why this became urgent 2026-08-04:** the Order Follow-Up panel showed **4 titles BACKORDERED on production and all 4 had actually been ordered** — precision 0 of 4. Root cause is not the panel's logic but its input: `order_submissions` is written only by a manual **Mark Ordered** click, and that click has been used **zero times on production** (all 857 rows are backfill, covering exactly three `submitted_on` dates: `2026-05-24`, `2026-06-27`, `2026-07-26`; `order_type` is 857 `monthly` / **0 `adhoc`**). The two ACTION COMICS titles sit on Lunar order `1804145` dated **6/2/2026** — off-cycle, placed directly on the vendor site, so it was never in any archived monthly file. **Cleanest demonstration:** that one order has three lines; `0626DC0202` (AVENGERS JLA #4) is correctly cleared because the backfill happened to cover its 6/27 cycle, while `0626DC0190` and `0626DC0116` read BACKORDERED — same order, same day, same distributor, differing only by which file the backfill caught.
- **F116's arrival-evidence clearing does not close this**, and the reason is structural: Lunar showed `0626DC0116` as **Shipped on 7/31**, but `weekly_shipment` has no row for it because that table is populated from the weekly invoice at the **street week** (8/12). Order placed 6/2 → arrival evidence ~8/12: for roughly ten weeks a correctly-ordered title reads BACKORDERED. **Arrival evidence clears stale false alarms; only order evidence clears in-flight ones.** They are complements, not substitutes.
- **Highest-risk design decision, recorded so it is not made casually:** `order_submissions` has **no unique constraint on `order_code`** by design (re-ordering is legitimate), so nothing at the database level stops a re-ingest from doubling every quantity — an **F102-shaped hazard pointing at money**. The plan proposes nullable `supplier_order_id` / `supplier_line_ref` with a **partial** unique index where `supplier_order_id IS NOT NULL`, leaving all 857 existing rows untouched and duplicate-legal. It also flags an overlap trap needing Rick's decision: the backfill already covers three cycles, and re-ingesting those confirmations would double-count them because the existing rows carry no supplier identifier to match on.
- **Session A COMPLETE 2026-08-04 — real exports obtained and characterised, and they corrected the plan twice before any code was written.** Samples live in `catalogs/order-confirmations/` (local, uncommitted). Measured against the live production catalog (11,713 rows): **PRH 28/31 lines matched (90%)**, misses being real comics absent from our catalog; **Lunar 137/149 distinct codes matched (92%)**, misses being almost entirely promo posters, ashcans and free bundles. Of the matched lines, **28/31 (PRH) and 122/149 (Lunar) correspond to a title with an open founding-tenant reservation** — these orders are overwhelmingly customer-driven, which is why ingesting them removes so much panel noise. Volume: ~**180 ledger rows per monthly ingest** (31 + 149) against 857 today, making F116's `loadOrderLedger()` pagination load-bearing rather than precautionary. **Two corrections, both load-bearing:** (1) **the rich supplier state is screen-only** — the Lunar CSV carries *no dates and no status whatsoever*, and PRH's line table has no date column, so `supplier_status` / `expected_date` / `status_as_of` have **no source** and were cut; had Session A been skipped, Session B would have built three columns with nothing to populate them, and the customer-facing *"Ordered — expected Aug 12"* is likewise not deliverable from these files. (2) **Lunar's order number is not in the file** — it exists only in the filename `Order_1853046.csv`, while PRH's sits properly in its header block, so the two distributors need different key-derivation strategies and Lunar's rests on a filename the operator could rename. Related: Lunar supplies no order date at all, yet `submitted_on` is NOT NULL.
- **The blocking discovery for implementation: netting is mandatory or the import aborts.** The Lunar export contains **3 negative-quantity lines**, each cancelling an earlier positive line for the same code (`0626DC0232`, `0526IM0377` "…Cancelled", `0626DE0825` — all netting to **0**). `order_submissions` has **CHECK `quantity >= 1`**, so a row-per-line ingest does not merely mis-count, it **fails outright** on the first negative line. Ingest must net by `(distributor, order_code)` within a file, write one row per code, **skip net-0**, and **halt on net-negative**. Cancellation is also signalled by the word `Cancelled` appended to the **title text** rather than any column — but netting catches it arithmetically, so a title-text matcher must **not** be built. **PRH's `Order Status` is the F110 trap exactly repeated: 31 of 31 lines read `Backordered`** — a column that never varies is not a signal, and it carries the F112 collision's literal vocabulary one column away from our own opposite-meaning `Backordered`. It must not be ingested, stored or displayed. Parsing hygiene confirmed against the real bytes: the PRH file has a **UTF-8 BOM**, **multi-line quoted header fields** (so `split('\n')` corrupts it — an RFC4180 reader is required), is **two tables in one**, and its `Line` numbers are **not monotonic**; Lunar has 3 UPCs with a trailing `x`, 14 zero-retail promo rows with an empty-string `Discount`, and its `UPC` column carries real ISBN-13s for trade paperbacks — so **both** distributors need the F76 three-key match, and PRH's misleadingly-named `ISBN` column (30/31 values are 17-digit UPCs) would silently under-match on a single-column join. Independent corroboration of **F111**: one Lunar order spans **four catalog months** (`0626`×129, `0526`×19, `0426`×3, `0326`×1).
- **DIRECTION CHANGED 2026-08-04 (Rick) — file ingest is DROPPED, not deferred; the plan is now capture-in-flow.** Plan rewritten and renamed to `docs/order-loop-closure-f108.md`. Rick's binding constraint: *"I do not want to download multiple files to feed the import every week because this adds more manual tasks. The pulllist app should not be a chore to maintain."* Any recurring manual step is disqualified — and § 2.2's measurement (Mark Ordered used **zero** times in a day) is the proof that a remember-it-afterwards affordance does not survive a real week. The confirmation files would have added a download, needed per-distributor parsers plus netting, and delivered **only** what two zero-cost capture points now provide: **(1) confirm-on-export** for ad-hoc orders (an explicit confirmation after the Order Builder download — deliberately reversing F101 § 4.2's "not on export click", with the operator's agreement), and **(2) confirm at new-catalog import**, gated on `isNewMonth` so a same-month refresh never re-confirms (the same gate F110's withdrawal detection uses). Together the ledger fills itself as a by-product of work already done. **Rejections are captured by a zero-quantity `Mark Ordered`** (Rick: *"log a zero qty effectively closing the loop on what was actually ordered. The import process simply accepts it"*) — which requires relaxing `CHECK quantity >= 1` to `>= 0`, and **reworking `get_ordered_codes()`, which would otherwise tell the customer "✓ Order placed" for a rejected title**: it must aggregate (`HAVING SUM(quantity) > 0`) and return a *state* rather than a quantity, preserving its deliberate admin-only-quantities design. A rejected title then **reuses F110's generic unavailable surface** (Rick: *"Reusing a generic unavailable status is reasonable"*) — same My List flag, same cancel exception, same admin panel — but is **not** merged into `catalog.withdrawn_at`, since that column is a property of the *title* while a rejection is a property of *our order*. The customer-facing arrival date comes from **`catalog.on_sale_date`**, verified to match both distributors exactly, so no supplier feed is needed at all.
- **A second live defect found the same day, in the same panel: `order_deadline` must SUPERSEDE the in-current-month rule, and the shipped code has it as `OR`.** Rick: *"The order_deadline supersedes the date logic of FOC in-current-month. If order_deadline is missing it reverts back to the logic of an FOC date in-current-month."* At Risk answers *"does this title fit the regular monthly order cycle?"*, and the deadline — not the month boundary — is the cycle's edge. `computeBackorderRisk()` reads `past || isFocThisMonth(foc) || (orderDeadline && foc <= orderDeadline)`, so `isFocThisMonth` fires regardless of the deadline. **Verified on production** (`order_deadline = 2026-08-21`): the two At Risk rows (both FOC `2026-08-31`, i.e. *after* the deadline, so covered by the monthly order placed on the 21st) **should not be showing at all**. Corrected logic is `past || (orderDeadline ? foc <= orderDeadline : isFocThisMonth(foc))`. **Combined with the four false Backordered rows, the production panel's precision on 2026-08-04 was 0 of 6.** One open risk recorded in the plan § 4.1: superseding makes At Risk go *silent* if the deadline is never rolled forward — the opposite failure to F96, and the worse one. Incidental correction: `app_settings` is a **key/value** table, so `select=order_deadline` returns an empty object; an earlier read of it as `null` was wrong and never reached a document.
- **Also recorded:** the F112 terminology collision is now visible on screen — PRH's own order page says *"These titles will be **backordered** unless removed before Checkout"*, meaning *ordered, will fill late*, directly beside our panel calling the same two titles BACKORDERED, meaning *never ordered*. Any ingest that stores a vendor status verbatim imports that ambiguity; vendor vocabulary must be **mapped**, never passed through. Lunar's **Partially Shipped** is a state the app cannot represent at all — it is the long-deferred "partial fulfillment not representable" item in `CLAUDE.md` § Known Out-of-Scope; the plan ingests the value but explicitly does **not** build fulfilment maths.
- **Customer impact as of 2026-08-04: none, verified.** All four affected titles are prior-catalog-month, so they never enter My List's current-month table where the FOC-lock copy renders; zero reservations across production were showing "FOC passed — contact the store". The damage is operator trust and wasted manual checking, not a broken customer promise — which is why the customer-facing half of the plan (expected dates on My List) is sequenced last and gated on a product decision.
- **Severity:** Medium. No data-integrity or security exposure. But it is a silent-failure gap on the path where the store's money actually moves: a title the distributor **rejected** and a title that has simply **not shipped yet** produce identical evidence — nothing. The customer keeps a reservation against a title that can never arrive, and neither they nor the admin gets any signal.
- **Symptom (the live instance that exposed it):** MIDNIGHT X-MEN #2 Covers A and B (`75960621668000211` / `…0221`) were submitted to PRH on the July cycle and came back **UNKNOWN**, with 8 copies queued behind them. PRH has since withdrawn the #2 records upstream entirely (the 2026-07-25 re-pull carries ten MIDNIGHT X-MEN rows, all issue #1). **Nothing in the app knows any of this.** It was caught by Rick reading the PRH order confirmation by eye. The 8 reservations still point at a title that no longer exists to order.
- **Diagnosis:** reconciliation is driven by **weekly shipment invoices** (`weekly_shipment`, § 4.10; import script § 12), i.e. by what *arrived*. There is no ingest of the **order** invoice/confirmation the distributor returns at order entry, so the app never learns which submitted codes were accepted, rejected, substituted, or short-allocated. Rick's own assessment (2026-08-02): *"there are no checks against an order invoice to surface rejected titles… invoice reconciliation seems to be more accurate vs shipping reports."*
- **Scope:** both environments (same client code and same operational process). Production is where the exposure is real.
- **Fix direction (future session):** ingest the distributor order confirmation/invoice and reconcile it against the submitted order — marking each code accepted / rejected / short-allocated, writing the outcome to the `order_submissions` ledger that the F101/F102 session creates (that table is designed to be populated by this path later, not only by hand). Then decide the **customer-facing** behaviour, which is the harder half: what a reservation should show when its title was rejected or withdrawn upstream. Needs sample PRH and Lunar order-confirmation files before it can be specified — the shipment path's Format A/B history (F83, F84) is a warning that assuming a format from memory is expensive here.
- **Related:** **F101** — its UNKNOWN rejections are what surfaced this, and its "customer-facing consequence to settle" thread is inherited by this finding. **F102** — creates the `order_submissions` ledger this would populate. **F89** / **F90** — the same absence of outcome instrumentation, on the claim/invite and analytics paths. **F84**, **F83** — prior evidence that distributor file formats must be read, not assumed. Partial fulfillment (`Known Out-of-Scope Items`) is the adjacent product question.

#### F109 — the order-ledger cancel guard (like the pre-existing `fulfilled` guard it mirrors) lives in client code, not RLS, so a client bypassing `Preorders.cancel()` can still cancel an ordered reservation

- **Status:** filed 2026-08-03 at the close of the F101/F102 order-export session, which is what made the gap worth naming. **Open — deferred, low priority.** No plan doc.
- **Severity:** **Low.** Not a new hole — `Preorders.cancel()`'s original `fulfilled` guard has always had exactly this property and was never filed. Recorded now because the same guard shape was extended to cover **order state**, where the consequence is money rather than tidiness: a cancelled-after-ordering reservation leaves the store holding a copy nobody wants, and the store has no signal that it happened. Requires a deliberately hand-crafted PostgREST call with the user's own JWT — not reachable through the app's UI, which hides and disables the control.
- **Symptom:** none observed. Found by writing the end-to-end verification for the new guard: the test deliberately issued a direct `DELETE /rest/v1/preorders?...` with a real customer token, bypassing `Preorders.cancel()` entirely, and it returned **HTTP 204**. The row was gone despite an `order_submissions` row existing for its code.
- **Diagnosis:** `preorders` RLS grants `users manage own preorders` — `ALL` where `auth.uid() = user_id AND tenant_id = current_tenant_id()` (§ 7.1). DELETE is therefore permitted on any row the user owns. Both cancellation guards — the original `fulfilled` check and the new `get_ordered_codes()` ledger check — are pre-flight lookups inside `Preorders.cancel()` in `app.js`, and the defensive `.eq('fulfilled', false)` on the DELETE only narrows the *fulfilled* case. Nothing at the database layer knows about the ledger. The FOC lock (`isFocLocked`) is likewise client-side.
- **Scope:** both environments (same client code, same policy set). Staging today; production once the F101/F102 work is promoted.
- **Fix direction (future session, low priority):** the honest options are (a) accept and document it as a UI-level guard, which is what it has always been, or (b) move enforcement into the database — a `BEFORE DELETE` trigger on `preorders` rejecting a delete when a matching `order_submissions` row exists (and, if wanted, when `fulfilled = true`), which is the only version that actually holds against a crafted request. **Do not** narrow the RLS policy itself to express this; the condition depends on a join against another table and belongs in a trigger, not a policy `USING` clause. Worth weighing against how reachable this is in practice: customers are magic-link authenticated and the app never exposes the call.
- **Where:** `app.js` — `Preorders.cancel()` (both guards); `docs/sql/get-ordered-codes-rpc.sql`; `preorders` RLS policy `users manage own preorders` (§ 7.1). Related client-side-only guard: `isFocLocked` / `isFocPast`.
- **Related:** **F102** — created the ledger guard that prompted this filing. **F10** — the other `preorders` FK/deletion-behaviour finding; both concern what the database does or does not enforce about preorder deletion. **F104** — the adjacent "a guard's blind spot is worth recording even when nothing has gone wrong" precedent.

#### F110 — distributor withdrawals are undetectable from the catalog files as downloaded, because the "active" export omits withdrawn titles rather than flagging them

- **Status:** filed 2026-08-03 while reviewing PRH's *Direct Market Catalogs and FOC Pages* documentation and both distributors' live catalog files at Rick's request, specifically to avoid designing against assumed behaviour. **Session A (detection) — RESOLVED 2026-08-03, live on staging AND production.** Plan: `docs/order-export-followthrough-f110-f111-f112.md` § 4.2, § 6 Session A. Four additive nullable `catalog` columns (`initial_order_due`, `title_note`, `withdrawn_at`, `withdrawn_last_seen_month`) landed on both environments via `docs/sql/catalog-withdrawal-and-lunar-fields.sql`; all four read NULL on every pre-existing row on both envs. The corrected cross-month set-difference (§ 3.3 below) is implemented in both `import.js`/`import-staging.js` as pure exported functions — `computeWithdrawalCandidates`, `narrowWithdrawalCandidates`, `computeReappearedRows`, and the paged `pageAllRows` (F82/F113-shaped) — plus a `detectWithdrawals()` orchestrator wired into the new-month path after the catalog upsert (not gated behind the no-op `delete_dropped_catalog_items` call). Verified: a `--no-write` dry run against real staging data (paged the real ~2,382-row prior-month catalog) correctly computed and narrowed candidates with zero writes attempted (gate V-A2); a synthetic staging fixture (throwaway auth user + a prior-month catalog row with a future `on_sale_date` + an unfulfilled preorder) was correctly marked withdrawn and then correctly cleared on reappearance via real writes, then torn down and reverified by live SELECT returning zero rows (gate V-A3). 39 new unit tests added to the scripts-repo suite (`test/withdrawal-and-lunar-fields.test.mjs`); 85/85 green; `node --check` clean on both scripts. **Detection does not run until the next monthly import** — it is gated on `isNewMonth`, which only fires on a real new-catalog-month transition. **Session B (surfacing) — RESOLVED 2026-08-03, live on staging; **since PROMOTED TO PRODUCTION** by a later staging→main merge — verified live on `pulllist.app` 2026-08-09 by serving-build markers. This previously read "production promotion is Rick's call, not yet requested" and was **stale**: no one requested it, but a subsequent promotion carried it anyway, because `git merge staging` moves everything on the branch, not only the session that prompted the merge. **The F105 mechanism** — and the reason to verify a promotion claim against the live site rather than against whether anyone remembers asking.** Plan § 4.5, § 6 Session B. An admin `#withdrawn-panel` (sibling to the backorder-risk panel, grey not red/amber so the two never look interchangeable) lists every withdrawn code with title, last-seen month, customer/copy counts, and an "already submitted" flag when the ledger also carries the code. My List flags a withdrawn reservation ("No longer available — withdrawn by the distributor. This title cannot arrive.") and re-enables Remove, overriding **both** `focLocked` and `isOrdered` — `isFocPast()`/`isFocLocked()` are byte-unchanged; the exception lives entirely at the call sites (`mylist.html`, `Preorders.cancel()` in `app.js`). **Mid-session correction to the plan's own scope:** the plan's citation of `mylist.html:904–907` covers only the current-month table (`allItems`); the real MIDNIGHT X-MEN #2 shape (prior catalog_month, future on-sale date) lives in the **read-only** "Upcoming Arrivals" grid (`allUpcoming`), which had no action controls at all. Flagged to Rick mid-session; he chose to fix it the same session — `.month-arrival-card` now gets the same withdrawn badge + a `.cancel-btn-arrival` Remove button, wired through the identical `Preorders.cancel()` path. Fixing this surfaced a second, genuinely pre-existing latent bug — `renderArrivingThisMonth()`'s empty-state branch never cleared `grid.innerHTML`, so a shrink-to-empty transition left a stale card in the DOM — filed and fixed same-session as **F114**. Cancellations on an already-ordered withdrawn title are logged via `UsageEvents.cancel(..., { withdrawn: true, cancelled_after_order_submitted })` (Rick's call, asked directly rather than assumed) so the store can find and reconcile the distributor order. Verified: gate V-B4 green (withdrawn + ledger row → My List shows withdrawn copy, Remove enabled and *working* — the actual DELETE succeeds, not just that the button renders); the admin panel test confirms it lists the title and stays distinct from the backorder panel; two dedicated mobile-width (375px) tests confirm no horizontal overflow and a tappable, working Remove on both the mobile card and the admin panel (V-B5). Full spec 15 extension: 63/63 Playwright tests green on staging. All seeded fixtures torn down and reverified by live SELECT returning zero rows.
- **Severity:** Medium. No data-integrity or security exposure, but it is the mechanism behind F101's still-open customer-facing thread: reservations left pointing at a title that can never arrive, with no signal to anyone.
- **This entry corrects a wrong fix direction proposed the same day.** The initial suggestion was to capture PRH's `SalesStatusCode` / `SalesStatus` fields, on the strength of PRH's documentation: *"Withdraw Notifications occur when an item may become postponed, canceled, or otherwise made inactive… Sales Status Code and Sales Status fields will reflect the appropriate inactive status, e.g. PP– Postponed."* **That does not work for the files this store actually downloads.** Measured against the live files: `2026_08_PRH_metadata_full_active.csv` is 871 rows, **871 of them `IP / Active`**; `2026_07_..._full_active.csv` is 1,280 rows, **1,280 of them `IP / Active`**. The filename is the tell — **`_full_active`** is the active-only export, so a withdrawn title is **absent**, never present-and-flagged. Reading the column would return `Active` for everything, forever.
- **Corroborating (this is exactly F101's live instance):** the July PRH feed re-pulled 2026-07-25 carried ten MIDNIGHT X-MEN rows, all issue #1; the August feed carries none. The #2 records did not change status — they disappeared.
- **Lunar has no equivalent field at all.** Its 59-column product file (`Lunar_Product_Data_0826.csv`, 1,511 rows) carries no status column. The three candidates were checked and all rejected: `O/A` is uniformly `N` (1,511/1,511, zero signal); `OrderFormNotes` carries returnability and territory text; `TitleNote` carries merchandising notes. So for Lunar the set-difference approach is the *only* available mechanism, not merely the better one.
- **Diagnosis:** detection is a **set difference, not a column read** — a code present in a prior import, absent from the current one, and still holding unfulfilled reservations, has been withdrawn upstream. Note the app cannot currently *lose* such a row silently: `purge_stale_catalog()` filters `id NOT IN (SELECT catalog_id FROM preorders …)` and `preorders.catalog_id` is `ON DELETE NO ACTION` (F10), so a withdrawn title with reservations keeps its catalog row. The row survives; nothing interprets its absence from the new feed.
- **Fix direction — CORRECTED 2026-08-03 during planning; the original path 1 below does not work as written.**
  1. ~~**Set difference at import.** `import.js` already computes the current month's `item_codes` array for `delete_dropped_catalog_items()`. The codes it would drop but cannot (because reservations block deletion) are precisely the withdrawal candidates — surface them instead of discarding them.~~ **Wrong on both halves, verified against the live code and § 13 F66:** (a) `delete_dropped_catalog_items` compares **within a single `catalog_month`** (`DELETE … WHERE tenant_id = … AND catalog_month = … AND item_code != ALL(p_item_codes)`, § 6.2), so a code present in July and absent from August is never in its scope; (b) it **matches zero rows on every run** — F66 established that the script calls it only when `isNewMonth`, which guarantees no rows existed for that month before the just-completed upsert, so every surviving row's `item_code` is already in the array. The preorder guard alluded to belongs to **`purge_stale_catalog`**, a different function. **The set difference must be computed explicitly and across months**: prior-month `(distributor, item_code)` pairs minus the current import's pairs, narrowed to codes still holding unfulfilled reservations with a future `on_sale_date`. The prior-month `catalog` read must be **paged** (~7,200 rows vs PostgREST's 1,000 default — see **F82**, **F113**). Full design: `docs/order-export-followthrough-f110-f111-f112.md` § 4.2, with the correction written up at its § 3.3.
  2. **Pull a different PRH file** — **decided against 2026-08-03.** PRH's documentation describes *Monthly Catalog CSV* / *Weekly Catalog Delta* downloads that do carry `PP–Postponed` and similar, which would give a structured signal for PRH — but **not for Lunar**, which has none, so path 1 is required regardless. Adding a second PRH download means a new step in a monthly manual process, a new parser and a new failure mode for a signal path 1 already produces. Revisit only if the set difference proves too noisy on PRH in practice; record the noise rate at the first two real imports.
- **The customer-facing half was settled 2026-08-03 (Rick): "Admin + customer flag."** A reservation on a withdrawn title is surfaced to the admin (import output + dashboard panel), marked on My List as no longer available, **and becomes cancellable again despite the FOC lock** — a deliberate, authorized exception implemented at the call sites, leaving `isFocPast`/`isFocLocked` untouched. It must override the **ordered** lock too, not only the FOC lock: the MIDNIGHT X-MEN #2 codes carry `order_submissions` rows from the July cycle, so overriding only the FOC lock would leave the exact case unfixed. This closes F101's long-open customer-facing thread. See the plan § 2.2 and § 4.5.
- **Scope:** both environments, both distributors. Production is where the exposure is real (8 MIDNIGHT X-MEN #2 reservations still point at a withdrawn title).
- **Where:** `import.js` / `import-staging.js` — `normalizePRHCatalog()` (~200–225), `normalizeLunarCatalog()` (~175–199), and the `delete_dropped_catalog_items()` call; the catalog files in `catalogs/`.
- **Related:** **F108** — invoice reconciliation, the adjacent gap; this is the cheaper half and does not need sample order-confirmation files to specify. **F101** — its "customer-facing consequence to settle" thread is what this would close. **F84**, **F83** — prior evidence that distributor file formats must be read, not assumed; this entry is another instance of exactly that.

#### F111 — the Order Builder gathers reservations within the current catalog month, but a distributor FOC cycle legitimately spans several catalog months

- **Status:** filed 2026-08-03 from PRH's *Direct Market Catalogs and FOC Pages* documentation, verified against live production data. **RESOLVED 2026-08-03 — live on staging; **since PROMOTED TO PRODUCTION** by a later staging→main merge — verified live on `pulllist.app` 2026-08-09 by serving-build markers. This previously read "production promotion is Rick's call, not yet requested" and was **stale**: no one requested it, but a subsequent promotion carried it anyway, because `git merge staging` moves everything on the branch, not only the session that prompted the merge. **The F105 mechanism** — and the reason to verify a promotion claim against the live site rather than against whether anyone remembers asking.** `docs/order-export-followthrough-f110-f111-f112.md` § 4.4, Session B, unblocked by F113 (below) landing first in the same session. `admin.html` now builds `allPreordersAllMonths` (the same paged fetch, unfiltered) and a collapsed `gatherCollapsed` array once per `loadData()`; `distinctFocDates()`, `classifyForExport()`, `computeBackorderRisk()`, and the Order Builder consolidation path (`makeOrderSheetRows`, the "already ordered" cards, the extra-rows generator) all re-point to it. `allPreorders` and its other 15+ month-scoped consumers are untouched — verified by diff, not just by intent. Both de-duplications shipped as designed: export consolidation now groups by `exportCode()` rather than `catalog.id` (`groupByExportCode`, `groupBucketByCode`), and same-customer cross-month duplicate reservations collapse to the newest-`catalog_month` survivor at **MAX** quantity (`collapseCrossMonthReservations`, matching F85's own one-time cleanup rule) — both collapses are surfaced in the held-back panel ("Cross-month duplicate reservations collapsed"), never picked silently. Withdrawn titles (F110) are excluded from both the backorder panel and the Order Builder's exportable buckets regardless of ledger status, since a withdrawn code cannot be re-submitted. **Verified:** gate V-B2 (a seeded ACTION-COMICS-shaped fixture — prior catalog month, future FOC, no ledger row — appears in both the backorder-risk panel and the Order Builder's FOC-cycle list and held-back panel); a dedicated collapse test (same customer/code across two months collapses to one row at qty 5, not 7, with the collapse note present); V-B3 held by construction and re-confirmed by every pre-existing single-month test (V3/V4/V7/Status-button) still passing unchanged post-refactor, since within one month `exportCode` grouping is equivalent to `catalog.id` grouping. **Not yet measured on staging:** the "expect the panel to get louder on first run" volume increase this entry called for — staging's data doesn't have production's cross-month backlog, so this is a production-promotion-time observation, not a staging one; flag it to Rick before he sees it if/when promoted.
- **Severity:** **Low as measured, Medium as a mechanism.** Quantified on production the day it was filed: of 483 titles with a future FOC whose catalog row sits outside the current catalog month, **481 (1,212 copies) were already in the order ledger** — ordered on an earlier cycle while their month was current. Only **2 titles / 2 copies** were genuinely un-ordered and invisible. The month-scoped model works *because the store's ordering cadence matches the catalog cadence*; it is not the systemic hole it first appears to be.
- **The two live cases at filing:** `ACTION COMICS #1 FACSIMILE EDITION CVR A` (catalog `2026-05`, FOC **2026-08-03 — locking that same day**, qty 1) and `DEADLY TALES OF THE GUNSLINGER SPAWN #20 CVR A` (catalog `2026-04`, FOC 2026-10-12, qty 1). Caveat on both: the ledger only covers the May/June/July cycles, so "absent from the ledger" is not proof they were never ordered — an April-cycle order would leave no row.
- **ACTION COMICS CVR A — disposition confirmed on production 2026-08-03, and it is the finding's worked example.** Code `0626DC0190`, **Lunar**; catalog rows in `2026-05` and `2026-06`; the reservation (qty 1, unfulfilled) was made **2026-06-02 against the `2026-05` row**; FOC `2026-08-03`; on sale `2026-08-26`; **zero `order_submissions` rows — never ordered.** Production's current catalog month is `2026-08`, so both the Order Builder and the backorder-risk panel are structurally blind to it, and `isFocPast()` being strictly-before-today means it crossed into **Backordered at midnight on 2026-08-03** without ever appearing on any surface. Its sibling `0626DC0192` (CVR C, catalog `2026-06`) **was** ordered — qty 1, `monthly`, submitted `2026-06-27` — which is the 481-of-483 case in miniature. **One title demonstrates both the mechanism and why the measured exposure is small.** Per **F112(b)**'s overrule it is still orderable today, so it needs a manual decision independent of when the fix lands.
- **Newly discovered dependency (2026-08-03): this cannot be implemented correctly until F113 is fixed.** `admin.html`'s preorder fetch is capped at 1,000 rows and production holds 2,004; the oldest row inside the cap is dated `2026-06-26`, so **ACTION COMICS CVR A's 2026-06-02 reservation is outside it.** Widening the gather first would leave the finding's own worked example invisible *while the held-back panel newly claimed to have looked across all months* — trading an honest gap for a false assurance. See **F113**.
- **Diagnosis:** `allPreorders` is filtered to `currentCatalogMonth` in `loadData()`, and every downstream consumer — `distinctFocDates()`, `classifyForExport()`, `computeBackorderRisk()` — inherits that scope. PRH's model is the inverse of the one the plan assumed: a catalog month contains **many FOCs** (April 2026: "327 items · **10 FOCs**"; July 2026: 13), *and* a single FOC page draws from **many catalogs** ("FOC 03/23/2026 · 204 items · **4 catalogs**"). PRH updates four catalog months nightly — current, newest future, and two prior — so several months carry live FOCs simultaneously. A reservation made **after** its catalog month stops being current, on a title never re-listed, is therefore unreachable by the export.
- **Why this is not a regression:** the pre-fix export had the identical scoping (F101's own diagnosis: *"`allPreorders` is scoped to `currentCatalogMonth` … and nothing downstream narrows further"*). The F101/F102 work neither introduced nor widened it. **What did change is the confidence it projects:** the held-back panel asserts that nothing is dropped silently, and that claim is true only *within* the month it can see. Rows excluded by the month filter never reach classification at all.
- **Fix direction — settled 2026-08-03:** gather the Order Builder's candidate set by **`foc_date` across all catalog months** rather than by `catalog_month`, which is what PRH's FOC page already does. The two open questions are answered: **(a) de-duplication** happens at two distinct levels — export consolidation collapses by **`exportCode`** rather than `catalog.id` (`makeOrderSheetRows` currently keys on `c.id`, which is equivalent *within* a month but emits two lines for one code *across* months), and reservation gathering collapses **`(user_id, order_code)`** to the newest `catalog_month` (F85's survivor rule, so the two agree), with **both collapses surfaced in the held-back panel, never silent** — silently picking a row is how F80 and F85 stayed hidden. **(b) the backorder-risk panel adopts the same widening** (Rick, 2026-08-03), so it can finally see a reservation whose FOC locks today from a prior month. **Critical implementation constraint: do not widen `allPreorders` itself** — it has 15+ consumers (stats, By Customer, By Distributor, search, reserved-titles report, This Week) that are correctly month-scoped by deliberate decision; add a second unfiltered array and re-point only the four export/backorder consumers. **F101/F102's V2 byte-identical gate is invalidated by construction** and is replaced by an equivalent that restricts the gather to the current month. Plan: `docs/order-export-followthrough-f110-f111-f112.md` § 4.4.
- **Scope:** both environments (same client code). Production data was used for the measurement above.
- **Where:** `admin.html` — `loadData()` month filter, `distinctFocDates()`, `classifyForExport()`, `computeBackorderRisk()`.
- **Related:** **F101** — established explicit cycle selection; this extends the same idea to the row-gathering step. **F85** — cross-month duplicate reservations; its carry-forward fix (2026-07-15) narrows this window for subscriber auto-reserves but not for manual reservations. **F80** — the other case of catalog-month scoping producing a silently wrong result.

#### F112 — two distributor-model facts the app does not represent: Lunar's `InitialOrderDue` deadline, and the fact that a passed FOC is recoverable on Lunar but terminal on PRH

- **Status:** filed 2026-08-03 from Lunar's ordering FAQ and its live product file, read alongside PRH's documentation. **(a) RESOLVED 2026-08-03 — live on staging AND production.** `initial_order_due` and `title_note` are now read by `normalizeLunarCatalog()` in both `import.js`/`import-staging.js` (PRH normalizer untouched — PRH publishes neither field); the window guard (`parseInitialOrderDue()`, `docs/order-export-followthrough-f110-f111-f112.md` § 4.1) is a pure exported function that rejects `InitialOrderDue` values outside `[first-of-catalog_month − 31d, +92d]` and is unit-tested against the real known-bad rows. **Gate V-A1 verified against the live `Lunar_Product_Data_0826.csv`: exactly 2 values rejected** (the `8/27/2027` and `8/27/2028` typo rows), while the real `8/27/2026` (1,505 rows) and `8/10/2026` (4 rows) values are both accepted. Stored per row, never aggregated, per the design note below. `TitleNote` is stored verbatim (trimmed, empty → NULL) — nothing reasons over it yet. (b) the Lunar-vs-PRH severity split is **overruled and withdrawn** — see below; the product decision it asked for was put to Rick the same day and answered "do not distinguish."
- **Severity:** Low–Medium. No incorrect behaviour today, but the backorder-risk panel currently states a severity it cannot justify for half the catalog, and a deadline the store needs is sitting unread in a file it already downloads.
- **(a) `InitialOrderDue` is published in the Lunar file and ignored.** `Lunar_Product_Data_0826.csv` carries an `InitialOrderDue` column: **1,505 of 1,511 rows read `8/27/2026`**. This is the distributor's own monthly initial-order deadline, described in Lunar's FAQ (*"All of those items are orderable as an initial order where the deadline is 01/26/2023"*). **This materially qualifies § 2.2 of the F101/F102 plan**, which concluded there was no derivable source for the submission deadline and that only `app_settings.order_deadline` — the *customer* cutoff — existed. That conclusion holds for PRH but is wrong for Lunar: the distributor deadline is in the file. `import.js` does not read the column. **Data-quality warning if anything ever parses it:** four rows read `8/10/2026` and two read `8/27/`**2027** and `8/27/`**2028** — near-certain Lunar typos that would produce a nonsense deadline if taken as a minimum or maximum.
- **(b) ~~A passed FOC is not equally fatal on both distributors.~~ — OVERRULED 2026-08-03 by Rick; this half of the finding is withdrawn.** The original claim, from the vendor documentation: Lunar's FAQ says *"items ordered after the FOC date will be sent in the next scheduled shipment… the items may not all fill in the release week"* (recoverable but not guaranteed), while PRH's says *"Carts must be confirmed before their FOC date… Any unconfirmed quantities will not be included"* (terminal) — so the § 4.5 panel was said to overstate severity for Lunar. **Rick, who places these orders, ruled otherwise:** *"Backorders are treated the same for PRH and Lunar — they both can be ordered after the FOC date but availability can not be guaranteed. I do not want to distinguish them as such."* Both statements can hold: the FOC **cart** closes, and a **new** order can still be placed afterward against remaining stock. **There is no Lunar/PRH asymmetry to build, and the panel must not distinguish them.** This is the second time in this workstream that a vendor document described a mechanism narrower than the working relationship (cf. § 13 F102's correction, where the code's meaning of `fulfilled` differed from the operator's use of it) — read vendor docs for mechanism, ask the operator for practice.
- **What the vendor docs *did* obscure is a different distinction — late ≠ withdrawn.** A title whose FOC passed unordered ("Backordered") **can still be ordered**, on either distributor, with availability unguaranteed. A title **withdrawn upstream** (**F110**) cannot be ordered at all and cannot arrive, because the code no longer exists. **Consequence: existing copy is wrong.** The shipped backorder-risk panel, `docs/order-export-foc-window-and-order-state.md` § 2.4, and F101's Backordered definition all say a Backordered title "cannot arrive" and that the customer is committed to a book that will never come. That is too strong for Backordered and is accurate only for **withdrawn**. Correcting the wording is scoped into `docs/order-export-followthrough-f110-f111-f112.md` § 4.6 — fix the phrasing without weakening the urgency, since an unordered title past FOC is still a failure, just a recoverable one.
- **Terminology collision worth recording:** Lunar uses "backordered" to mean *ordered after FOC, may not fill*. This project uses "Backordered" (§ 2.4, Rick's term) to mean *FOC passed and no order was ever placed*. These are different states and the words are identical — a future session reading a Lunar invoice or FAQ alongside this document will otherwise conflate them.
- **Also unread, same file:** `TitleNote` carries free-text fulfillment risk — *"Allocations may occur"* (31 rows) and *"Previously offered through Diamond. Never fulfilled."* (16 rows). Unstructured, but it is the short-allocation half of **F108** available from a file already on disk, without waiting for order-confirmation samples.
- **Structural note for anyone touching the export:** Lunar is a **two-tier** model — a monthly *initial order* (deadline `InitialOrderDue`) that auto-fills at release unless adjusted, plus weekly *FOC adjustments*. PRH is **per-FOC-cart**, each confirmed independently. The current month-scoped export maps naturally onto Lunar's initial order and less naturally onto PRH's carts (see **F111**).
- **The vendor states F102's mechanism explicitly**, which is worth quoting because it settles the cross-cycle question: *"All orders placed on the Lunar site by any of these methods will **ADD to any previously existing order quantity. Make sure that you don't potentially double up on orders.**"* This confirms the 11 cross-cycle Lunar codes in the ledger genuinely accumulated (2+1 = 3 copies), and that F102's duplicate check guards against a hazard Lunar documents.
- **Fix direction — settled 2026-08-03:** read `InitialOrderDue` and `TitleNote` into `catalog` as **two additive nullable columns** (not JSONB — nothing in this schema uses JSONB and `catalog` is 29 flat columns). `InitialOrderDue` is parsed with the existing `parseDate()` and then **rejected if it falls outside `[first-of-catalog_month − 31d, first-of-catalog_month + 92d]`**, which keeps `8/27/2026` and `8/10/2026` and rejects the `2027`/`2028` typos; the rejected count is printed at import. **Stored per row and never aggregated** — a min/max over this column is exactly what the bad values would poison. `TitleNote` is stored verbatim; nothing reasons over it yet. **The panel does not distinguish Lunar from PRH** (overruled, above). Plan: `docs/order-export-followthrough-f110-f111-f112.md` § 4.1, Session A.
- **Where:** `import.js` / `import-staging.js` — `normalizeLunarCatalog()` (~175–199); `admin.html` — `computeBackorderRisk()` / `renderBackorderRiskPanel()`; `docs/technical-reference.md` § 4.3 (`catalog` columns).
- **Related:** **F102** — the Lunar FAQ's "orders ADD" warning is this finding's most load-bearing quote. **F101** § 2.2 — qualified, not overturned, by `InitialOrderDue`. **F108** — `TitleNote` is a partial, cheaper substitute for its allocation half. **F111** — the other distributor-model mismatch found in the same review.

#### F113 — `admin.html` fetches `preorders` with no `.range()`, so PostgREST caps it at 1,000 rows; production holds 2,004

- **Status:** filed 2026-08-03 during the planning session for `docs/order-export-followthrough-f110-f111-f112.md`, while checking whether F111's cross-month widening was implementable at all. **RESOLVED 2026-08-03 — live on staging; **since PROMOTED TO PRODUCTION** by a later staging→main merge — verified live on `pulllist.app` 2026-08-09 by serving-build markers. This previously read "production promotion is Rick's call, not yet requested" and was **stale**: no one requested it, but a subsequent promotion carried it anyway, because `git merge staging` moves everything on the branch, not only the session that prompted the merge. **The F105 mechanism** — and the reason to verify a promotion claim against the live site rather than against whether anyone remembers asking.** Session B's first step, as scheduled. `admin.html`'s `fetchAllPreorders()` now counts first (`{ count: 'exact', head: true }`) then pages in 1,000-row batches via `.range()`, ordered `created_at desc, id desc` (the `id` tiebreaker keeps page boundaries deterministic since `created_at` is not unique) — mirrors the existing precedent at `getReservedPublishers()`/`fetchAllCatalogForDistributor()` in the same file. **Gate V-B1 verified on staging:** fetched row count (49) equals the exact `preorders` count for the founding tenant, confirmed via a direct PostgREST `Content-Range` probe before the fix (baseline) and the app's own fetch after. Staging's volume is too low to exercise the actual 1,000-row pagination boundary — the real proof is production's 2,004 rows, which this entry's own measurement above already establishes as the target; **re-assert `allPreordersAllMonths.length === 2004` read-only on production if/when this promotes**, per the plan's own gate wording.
- **Severity:** **Medium.** No incorrect output *today*, and no data-integrity or security exposure — but it is a silent truncation on the path that generates the distributor order, and it is the reason F111 cannot be implemented honestly until it is fixed.
- **Diagnosis:** `admin.html:679–693` issues `db.from('preorders').select(…).order('created_at', { ascending: false })` with **no `.range()`** and no count. PostgREST's default row cap therefore applies, silently. The same file already does this correctly elsewhere (`:2690`, `:2741` — count-first, then `.range(from, Math.min(from + 999, total - 1))`), so the pattern exists and was simply not used here.
- **Measured on production 2026-08-03:** `preorders` holds **2,004** rows for the founding tenant; the page receives **1,000**. The oldest row inside the cap is dated **2026-06-26**. Per-month totals: `2026-03` 73, `-04` 250, `-05` 340, `-06` 476, `-07` **764**, `-08` 101.
- **Why nothing is visibly wrong yet:** every consumer of `allPreorders` is scoped to `currentCatalogMonth` (`admin.html:709–710`), and the newest-1,000 window reaches back roughly five weeks — comfortably covering the current month. All **101** current-month rows are inside the cap; **zero** are missed. Stats, By Customer, By Distributor, the exports and the reserved-titles report are all correct as of this date.
- **Why it is still a defect — two reasons:**
  1. **Silent cliff.** Monthly reservation volume is growing (250 → 340 → 476 → 764). The first month that crosses ~1,000 begins truncating the *current* month, including both order exports, with no error and no visible symptom — the sheet would simply be short.
  2. **It blocks F111.** The cross-month widening needs prior-month reservations: precisely the 1,004 rows this query discards. The live worked example — `ACTION COMICS #1 FACSIMILE CVR A`, reserved **2026-06-02** — falls *outside* the cap. Widening the gather first would leave that reservation invisible while the held-back panel newly claimed to have looked across all months, which is worse than the honest gap it replaced.
- **Fix direction:** count-first, paged read following the in-file precedent at `:2690` / `:2741`. **Do not** use `range()` without the count — Supabase `range()` returns **416** on an empty result set (`CLAUDE.md` § Known Issues). Verification must assert the fetched length equals the exact table count; a spot-check cannot see a 1,000-row cliff.
- **Scope:** both environments (same client code). Only production has enough rows to be affected — staging holds 49.
- **Where:** `admin.html:679–693` (`loadData()`). Correct precedent in the same file at `:2690` and `:2741`.
- **Related:** **F82** — the same truncated-fetch class, on the catalog path, and the precedent that this is a recurring shape in this codebase rather than a one-off. **F102** — its backfill generator hit the identical PostgREST 1,000-row default and silently reported most of the catalog as unmatched. **F111** — blocked by this. **F110** — its detection step reads `catalog` (~7,200 rows) and must page for the same reason.

#### F114 — `mylist.html`'s Upcoming Arrivals grid never cleared its stale DOM on a shrink-to-empty render, because nothing had ever re-rendered it with fewer items before

- **Status:** filed and **RESOLVED same-session, 2026-08-03**, during the F110 Session B implementation (`docs/order-export-followthrough-f110-f111-f112.md` § 6 Session B, S-B3/S-B5). Found by the new Playwright spec, not by eye — `toHaveCount(0)` on a removed card kept finding it 24× over a 10s retry window.
- **Severity:** Low as filed — no data-integrity or security exposure, and (before this session) structurally unreachable, so it never manifested in production. Recorded because it is a real, general defect shape (see Root cause) that a future feature touching this render path could hit again if the reason it was unreachable isn't understood.
- **Root cause:** `renderArrivingThisMonth()` (`mylist.html`, "Upcoming Arrivals" — the read-only, all-future-months card grid, `allUpcoming`) has always had an early-return branch: `if (!arriving.length) { section.style.display = 'none'; return; }`. That branch never touched `grid.innerHTML`. This was invisible because, before F110 Session B, **nothing in this codebase ever called `renderArrivingThisMonth()` a second time with a smaller `allUpcoming` than the first** — it ran exactly once, at page load, and no action available anywhere on the page (the grid had zero interactive controls) could shrink `allUpcoming` afterward. A non-empty-to-empty transition was therefore dead code, reachable only by a future page reload (which rebuilds the DOM from scratch anyway, masking the bug).
- **What made it reachable:** F110 § 2.2's cancel exception is the **first** action ever added to this grid (a withdrawn title's Remove button, `.cancel-btn-arrival`). Cancelling the *last* upcoming-arrival item transitions `allUpcoming` from length 1 to 0 within the same page session, hits the early-return branch, and leaves the just-removed card's DOM node behind — hidden from a human (the whole section is `display:none`), but still present and matching for anything that queries the DOM directly, including Playwright's `toHaveCount()`.
- **Fix:** one line — `grid.innerHTML = '';` added to the early-return branch, alongside `section.style.display = 'none'`.
- **Verification:** the same Playwright test (`tests/15-order-export-ledger.spec.ts`, "prior-month withdrawn reservation surfaces in Upcoming Arrivals … with a working Remove") that caught it went green immediately after the fix, on both the initial run and a full-suite re-run (63/63). No separate reproduction was needed — the failing assertion was the reproduction.
- **Where:** `mylist.html` — `renderArrivingThisMonth()`.
- **Related:** **F110** — the feature whose implementation surfaced this. General shape worth remembering: any render function with an "early return when empty" branch should be audited for whether it clears previously-rendered content, not just whether it correctly skips rendering new content — the two are easy to conflate when the function has only ever been called once per page load in practice.

#### F115 — `auto_fulfill_past_on_sale()` closes never-arrived titles on schedule, so the backorder panel's failures leave it looking identical to successes

- **Status:** filed 2026-08-04 from a live triage question about a specific panel row ("Sonic the Hedgehog #88 is 36 days overdue — what does the customer see?"). **Mitigated 2026-08-04 — live on staging (client) and committed to the scripts repo (import). **since PROMOTED TO PRODUCTION** by a later staging→main merge — verified live on `pulllist.app` 2026-08-09 by serving-build markers. This previously read "production promotion is Rick's call, not yet requested" and was **stale**: no one requested it, but a subsequent promotion carried it anyway, because `git merge staging` moves everything on the branch, not only the session that prompted the merge. **The F105 mechanism** — and the reason to verify a promotion claim against the live site rather than against whether anyone remembers asking.** Not fully *resolved*: the detection is now reported, but nothing yet records or tracks the outcome — that remains **F108**'s job.
- **Severity:** **Medium.** No data-integrity or security exposure, and the measured rate is low — but it is the only state in the whole order pipeline where a customer is told something untrue, and it was structurally unobservable.
- **Diagnosis — three mechanisms stacked:**
  1. `auto_fulfill_past_on_sale()` (`docs/sql/auto_fulfill_past_on_sale.sql`) sets `fulfilled = true` for every preorder with `c.on_sale_date < CURRENT_DATE`, **with no arrival check whatsoever**.
  2. `computeBackorderRisk()` filters on `!p.fulfilled`. So a title that was never ordered and never arrived **exits the panel on schedule**, indistinguishable from one that arrived.
  3. `mylist.html` renders `isOrdered = fulfilled || isCodeOrdered(c)` as **"✓ Order placed"**. So after the sweep, the customer is actively reassured about a book that may never have come. The prior-month past-on-sale auto-hide then removes it from their list entirely.
- **It is not a cron job — this was assumed and was wrong.** `auto_fulfill_past_on_sale()` is called only at **Step 9 of `import.js`**, at the end of a run. So the flag flips at the *next import*, not on the release date, and the gap is a full weekly cycle. Consequence for the panel: a title stays listed, with its "days overdue" counter climbing, for up to a week **after it has already been sold and handed over** — the counter's peak value tracks import cadence, not anything about the title. That is what made Sonic #88 read as the worst row on the panel the day before it went on sale.
- **Measured on production 2026-08-04**, restricted to the window where `weekly_shipment` data actually exists (`2026-04-08` → `2026-08-05`, 805 rows) so that "no shipment row" is meaningful evidence rather than missing history: of **661** past-on-sale reservations, **28 reservations across 23 titles** were marked fulfilled with **no shipment record and no ledger row** — **4.2%**. Largest single case: *Star Wars: The High Republic Adventures — Pathfinders #4*, 5 copies across 3 customers, on sale 2026-07-29. **Upper bound, not a confirmed failure count** — a missing shipment row is not proof of non-arrival (F84's label-inversion history, invoices that miss a line, books handed over the counter).
- **Mitigation shipped (two halves, two repos):**
  - **Detection, at the point of destruction** — `reportUnverifiedFulfillments()` runs immediately *before* the RPC in Step 9 of both `import.js` and `import-staging.js`. Step 6 already loaded the week's shipments, so everything needed is in hand. It prints the titles about to be marked fulfilled with no shipment evidence, collapsed one line per title with copy and customer counts. **Reports, never blocks** — gating fulfillment on absent evidence would trade a silent miss for a silent stall. Read-only, so it prints under `--no-write`, and wrapped so a failed diagnostic can never fail an import. Pure helper `findUnverifiedFulfillments()` is exported and unit-tested (16 new tests across both scripts, 101/101 green). **Gate:** verified against real staging data with a seeded past-on-sale unfulfilled fixture — reported when no shipment row existed, correctly cleared once one was added, torn down and reverified by SELECT returning zero rows.
  - **Surfacing, in the client** — the panel gained a distinct **"Never arrived"** state (on-sale passed, no ledger row, no shipment evidence), visually escalated above Backordered, because ordering can no longer help. See **F116** for the sibling clearing rule shipped with it.
- **Still owed (this is why the status is "mitigated", not "resolved"):** the report is console output on a monthly/weekly manual job. Nothing persists it, nothing tracks resolution, and nothing tells the affected customer. Persisting the outcome is **F108**'s scope, and this entry's measurement (23 titles) is the audit list F108 can start from without waiting for the order-confirmation samples it is otherwise blocked on.
- **Where:** `docs/sql/auto_fulfill_past_on_sale.sql`; `import.js` / `import-staging.js` Step 9 + `findUnverifiedFulfillments()` / `reportUnverifiedFulfillments()`; `admin.html` `computeBackorderRisk()`; `mylist.html` `isOrdered` rendering.
- **Related:** **F108** — the reconciliation this hands off to; that entry's "a rejected title and an unshipped one produce identical evidence" is this same blindness one step earlier. **F116** — shipped in the same pass, the other half of the same triage. **F101**/**F102** — the panel and ledger this corrects. **F84** — why absent shipment data is not proof of non-arrival.

#### F116 — the order panel could not tell "ordered but never recorded" from "never ordered", so its loudest row was noise

- **Status:** filed and **RESOLVED 2026-08-04, same session** — live on staging, **since PROMOTED TO PRODUCTION** by a later staging→main merge — verified live on `pulllist.app` 2026-08-09 by serving-build markers. This previously read "production promotion is Rick's call, not yet requested" and was **stale**: no one requested it, but a subsequent promotion carried it anyway, because `git merge staging` moves everything on the branch, not only the session that prompted the merge. **The F105 mechanism** — and the reason to verify a promotion claim against the live site rather than against whether anyone remembers asking.
- **Severity:** Low-Medium (operational trust). No incorrect data — the panel was reporting exactly what it was asked to. The cost was that its most prominent row was routinely a false alarm, which is how an alarm stops being believed.
- **The live instance, and what made it diagnosable:** `Sonic the Hedgehog #88 Cover A (Kim)` (`82771401521808811`, PRH) showed on the production panel as **Backordered, 36 days overdue**. Read from production: catalog month `2026-04`, FOC `2026-06-29`, on sale `2026-08-05`, **zero `order_submissions` rows** — but a **`weekly_shipment` row exists** (qty 2, `catalog_id` matched). It was ordered and it physically arrived; the panel simply had no way to know. The cause is the ledger's history horizon: the 857-row backfill covers the **May/June/July** archived order files, so an **April**-cycle order leaves no row and never will. This is the caveat F111 already recorded ("an April-cycle order would leave no row"), showing up in production as a permanent false alarm rather than a one-off.
- **Customer impact: none for this shape, and the reason matters.** All five Backordered titles were prior-catalog-month, so they never enter My List's current-month table where the lock copy lives — the customer saw only a normal Upcoming Arrivals card (cover, title, price, filed under the on-sale date). Verified across all of production on 2026-08-04: **zero** reservations were showing "🔒 FOC passed — contact the store". The alarming lock state requires *current*-month **and** FOC-passed, which nothing currently satisfies. The panel noise was admin-facing only.
- **Fix — clear on arrival evidence, not just ledger rows.** `computeBackorderRisk()` now also clears a code when a `weekly_shipment` row matches its `catalog_id`, `upc`, **or** `item_code` — the **F76** three-key match, identical to `arrivals.html`'s `isCoveredByShipment()` (`catalog_id` alone under-matches: shipment rows can carry a null `catalog_id` with a valid upc/item_code). Measured effect on production data: removes 1 of 5 Backordered rows — the loudest one.
- **Two changes shipped alongside it:**
  - **Urgency is now on-sale proximity, not days-past-FOC**, for both the label and the sort. Days-past-FOC keeps climbing after the outcome is settled and its magnitude tracks import cadence (see **F115**), which is precisely why Sonic looked worst while being fine. Sorting soonest-on-sale-first puts the genuinely actionable row on top — on the production data that is *ACTION COMICS #1101*, on sale in 8 days, not the 36-day-old headline.
  - **`loadOrderLedger()` is now paginated.** It was a single unbounded `select()`; production holds **857** `order_submissions` rows against PostgREST's **1,000** default and grows by roughly a cycle's worth each month. On crossing, ledger rows silently stop clearing and **already-ordered titles begin appearing as false Backordered** — the same defect class as **F113**, on the query that decides this panel's correctness. Fixed before it could land.
- **Verification:** two new Playwright assertions in spec 15 — a shipped-but-unledgered title is absent from the panel (with a control asserting an unshipped one still shows, so the test proves the clearing rule rather than an empty panel), and a released-with-no-record title reads **"Never arrived"** with `data-state="neverArrived"` while a pre-release FOC-passed title still reads `data-state="backordered"`. Full suite **65/65 green, zero flaky**; scripts suite 101/101; fixtures torn down and reverified by SELECT.
- **Where:** `admin.html` — `computeBackorderRisk()`, `renderBackorderRiskPanel()`, `loadShipmentEvidence()`, `hasShipmentEvidence()`, `loadOrderLedger()`, `fetchPaged()`, `daysUntil()`.
- **Related:** **F115** — the other half of the same triage, filed together. **F111** — its "an April-cycle order would leave no row" caveat is exactly what surfaced here. **F113**/**F82** — the pagination class the ledger fix belongs to. **F76** — the three-key shipment match reused here.

#### F117 — `order_submissions` cannot record a downward adjustment, so a corrected supplier order leaves the ledger knowingly wrong

- **Status:** filed 2026-08-05, the moment a real correction was made and found unrecordable. **RESOLVED 2026-08-06, folded into Session B of `docs/order-loop-closure-f108.md`** (PR #104, merge `2029e70`) — live on staging and production. The real `-4` adjustment landed on both: staging 5+7−4=8 (row count 858→859), production 5+7−4=8 (row count 857→858), closing the F102 surplus in the ledger as well as operationally. Production's first migration attempt silently no-opped (the constraint check — not the grants check, which looks identical either way — is what caught it); the second attempt succeeded and was reverified before anything else proceeded.
- **Severity:** **Low–Medium.** No incorrect output today (§ "why it is invisible" below) and no data-integrity or security exposure — but it is a **money-relevant record that is now deliberately inaccurate**, and it becomes a visible false alarm on a predictable trigger.
- **Diagnosis:** `order_submissions` conflates two different things — a **submission event** ("we sent 7 on 7/26") and the **current quantity on order** ("PRH holds 8"). Those are identical until an order is revised downward, at which point the table can express the first but not the second. `CHECK order_submissions_quantity_check` is **`quantity >= 1`**, so a correcting row is rejected outright.
- **Verified against production 2026-08-05**, not inferred: a probe insert of `quantity = -4` returned **HTTP 400, PostgreSQL `23514`** (check-constraint violation). The probe was rejected, so nothing was written — `order_submissions` remained at 857 rows, re-confirmed by count afterwards.
- **Live instance, and the reason this was filed:** `75960621668000111` (MIDNIGHT X-MEN #1). Ledger holds **5 copies submitted 2026-06-27 + 7 submitted 2026-07-26 = 12**, against **8 copies of true customer demand** (6 customers, after collapsing the F85 cross-month duplicates — Jay Underhill and Book Stop each reserved twice when the title was re-listed). **Rick corrected the PRH order down to 8 on 2026-08-05**, closing the F102 surplus operationally. The ledger still reads 12 and there is no way to say so.
- **Why it is invisible today, and exactly when it stops being:** the title's catalog rows are `2026-05`/`-06`/`-07`; production's current catalog month is `2026-08`. The By Distributor tab is month-scoped (`allPreorders`), so the title is not rendered there at all. **The moment PRH re-lists it into the current catalog month, the Status button reads `⚠ Over (12 of 8)`** — flagging an over-order that has already been fixed. With FOC `2026-08-31` and the next catalog load due late August, that is likely to happen before Session B lands.
- **Decision recorded (Rick, 2026-08-05):** of the three options offered — (1) leave it, (2) edit the 7/26 row down to 3 so the total reads 8, (3) wait for Session B and append a `-4` adjustment row — **Rick chose (3)**. So the ledger's 12 is **deliberate and must not be "corrected" by editing history**: the 7/26 row really does record 7 copies submitted that day, and that history is precisely what evidenced F102's duplicate ordering in the first place. Option (2) would have bought current-state accuracy by making the ledger lie about the past.
- **Fix direction — folded into Session B, and it widens a change already planned there:** Session B was going to relax the CHECK from `>= 1` to `>= 0` so a **zero**-quantity row could record a supplier rejection (plan § 4.4). It must go further and permit **negatives**, with an `adjustment` value added to the `order_type` CHECK. Consequences that must land with it: every path that sums the ledger has to handle **signed** quantities rather than assume monotonic accumulation — `ledgerMatchesFor()` consumers, the By Distributor `Over/Add/Ordered` button maths, and the `get_ordered_codes()` aggregate (which Session B is already reworking to `HAVING SUM(quantity) > 0`; that same aggregate correctly resolves an adjusted-to-zero code to *unavailable*, so the two changes reinforce each other).
- **Scope:** both environments (same schema and client). Production is where the inaccurate row lives.
- **Where:** `docs/sql/order-submissions.sql` (the CHECK), `admin.html` — `openMarkOrderedModal()` / the By Distributor status button / `ledgerMatchesFor()` consumers, `docs/sql/get-ordered-codes-rpc.sql`.
- **Related:** **F102** — created this ledger *and* the over-order this correction closes; the surplus it recorded is the very thing that could not be written down once fixed. **F101** — same export path. **F85** — its cross-month duplicates are why raw reservation rows (11) overstate true demand (8) for this code. **F108** / `docs/order-loop-closure-f108.md` — the plan this is folded into.

#### F118 — the By Distributor "Print / Save Report" Status column never read the order ledger, so a title reading "✓ Ordered" on the tab still printed as "Open"

- **Status:** filed and **RESOLVED 2026-08-06, same session** — found by Rick reviewing staging during the order-loop-closure Session B deploy, fixed same session, live on staging (comic-preorder `0f33900`) and **production** (PR #104, merge `2029e70`).
- **Severity:** Low-Medium — no data-integrity or security exposure, but the printed report is a paper artifact used away from the screen (calling in orders, checking off arrivals), and it was silently telling the operator less than the live tab already knew. The failure mode is quiet: the report doesn't say anything is wrong, it just says less.
- **Symptom:** on the By Distributor tab, a title's Status **button** correctly read "✓ Ordered (n)" / "◐ Add (n of m)" / "⚠ Over (n of m)" / "⊘ Rejected — none ordered" (driven by `order_submissions`, F101/F102 then order-loop-closure Session B's signed-quantity rework). The same title's Status **column** on the "Print / Save Report" popup — a separate, print-optimized rendering of the same current-month reservations — read only "Open" / "Partial N/M" / "Fulfilled", with no way to represent any ordered state at all.
- **Diagnosis:** `buildReservedReportHtml()` / `printReservedReport()` (`admin.html`) was introduced 2026-06-26 (`b3f99e0`) — over five weeks **before** `order_submissions` existed (created 2026-08-03, F101/F102). Its Status column was correct and complete for its time: `fulfilled`/`fulfilledCount` were the only order-adjacent facts in the schema. When F101/F102 later wired the ledger into the By Distributor tab's own Status button, and order-loop-closure Session B extended that to signed quantities, neither session touched this separate report-generation function — it is a genuinely distinct code path (a new popup window with its own HTML/CSS, not a re-render of the tab's DOM), so nothing about editing the tab's rendering logic could have surfaced this by inspection; it had to be **used** to be seen. Textbook instance of the same shape as F103 (a path with zero visibility into a change made on an adjacent, more-visited surface).
- **Fix:** `buildReservedReportHtml()`'s per-row status now branches on the same `ledgerNetQty()`-derived sum `renderDistTable()`'s Status button already computes (reused, not re-derived — a second independent copy of this logic is exactly how the two surfaces drifted apart the first time) when the title is not fulfilled/partially-fulfilled: `Open` (no ledger rows) → `Ordered` (net quantity == reserved) → `Order N/M` (net < reserved) → `Over N/M` (net > reserved) → `Rejected` (net ≤ 0 with ledger rows present). Fulfilled/Partial-fulfilled still take precedence over order state, matching the button's own posture — once a title has physically arrived, its order-state history along the way stops being the operative fact. Four new CSS classes (`st-ordered`, `st-order-partial`, `st-over`, `st-rejected`) added alongside the pre-existing `st-done`/`st-partial`/`st-open`.
- **Verification:** new Playwright coverage (`tests/15-order-export-ledger.spec.ts`, local-only suite) — a seeded ordered title prints "Ordered", a seeded unordered title still prints "Open", asserted against the actual popup window (`page.waitForEvent('page')`, not a mock). Run in isolation first specifically to rule out `window.print()` hanging Playwright's headless Chromium (it doesn't — the call is a no-op there) before trusting it in the full run. Full suite: **73/73 green** on deployed staging, zero flaky. Fixtures torn down, reverified by live SELECT.
- **Where:** `admin.html` — `buildReservedReportHtml()`, `printReservedReport()` (Status column computation + `.st-*` CSS rules).
- **Related:** **F101**/**F102** — created the ledger this report now reads. **F108** / `docs/order-loop-closure-f108.md` — the session during which this was found and fixed (Session B). **F103** — the earlier instance of the same "adjacent surface with zero coverage" shape.

#### F119 — "Print Bagging List" also printed the Order Follow-Up and Withdrawn panels, which sit outside the print CSS's tab-scoped hide rule

- **Status:** filed and **RESOLVED 2026-08-06, same session** — found by Rick reviewing staging immediately after F118, fixed same session, live on staging (`307b5ab`) and **production** (PR #104, merge `2029e70`).
- **Severity:** Low — no data-integrity or security exposure, purely a print-output correctness issue. But it is a **paper artifact used away from the screen** (bagging up customer pulls), so extra unrelated content at the top of every page is a real, if minor, operational annoyance.
- **Symptom:** clicking "Print Bagging List" on the This Week tab printed the live **Order Follow-Up** panel (`#backorder-risk-panel`) and, when applicable, the **Withdrawn** panel (`#withdrawn-panel`) above the actual bagging list content, whenever either was visible on screen.
- **Diagnosis:** "Print Bagging List" (`btn-print-this-week`, `admin.html`) prints the live admin page in place — it toggles a `body.printing-this-week` class and calls `window.print()` directly, relying on a global `@media print` rule (`style.css` lines 236–256) to hide everything except the bagging-list content. That rule hides other tab content via `.admin-section:not(#tab-this-week) { display: none }` — but `#backorder-risk-panel` and `#withdrawn-panel` (`admin.html:172`/`:178`) sit **above** `.admin-tabs` in the DOM: they are persistent, tab-independent panels shown on every tab (rendered once per `loadData()`, not scoped to any `.admin-section`). Neither is caught by the tab-exclusion selector, and neither was ever added to the print rule's explicit hide-list — because both post-date it: the print CSS is Phase 3.6-era, the panels are F101/F110-era (2026-08-03+). Nobody revisited the print rule when the panels were added, because printing and the panels are two unrelated-looking features that only interact through a shared, unscoped position in the DOM.
- **Note on "Print Top Series" already having solved this class of bug:** that button's own code comment reads *"Opens a focused print window containing only the Top Series table — avoids fighting with the dark-mode admin UI in a global @media print rule."* — i.e., a prior session already migrated away from the fragile shared-stylesheet approach for exactly this reason, but only for that one surface. "Print / Save Report" (the By Distributor tab's report, unrelated to this finding) uses the same popup-window pattern. Bagging List is the one remaining surface using the older, harder-to-keep-correct shape.
- **Fix:** added `body.printing-this-week #backorder-risk-panel` and `body.printing-this-week #withdrawn-panel` to the existing hide-list in `style.css` — same pattern as every other hidden element there. Minimal fix chosen over migrating Bagging List to the popup-window pattern (Rick's call, given for a two-selector fix).
- **Verification:** new Playwright coverage (`tests/06-admin-this-week-bagging.spec.ts`, local-only suite) — seeds an at-risk title and a withdrawn title, confirms both panels are genuinely visible on screen first (control), then asserts both are hidden after engaging `printing-this-week` + `page.emulateMedia({ media: 'print' })` — print-media emulation rather than the real `window.print()` button, so the test can assert on computed visibility afterward. Run in isolation first (12.4s, clean), then full suite green with zero regressions. Fixtures torn down, reverified by live SELECT.
- **Where:** `style.css` (`@media print` hide-list); `admin.html` (`#backorder-risk-panel`, `#withdrawn-panel`, `btn-print-this-week` handler — unchanged, only the CSS moved).
- **Related:** **F118** — found in the same staging review, minutes apart; same root shape (a page-level surface added after an older feature, with nobody revisiting the older feature's assumptions). **F101**/**F110** — introduced the two panels this print rule now also hides.

#### F120 — a rejected title was invisible on both the Bagging List and My List, with nothing distinguishing it from a title that will actually arrive

- **Status:** filed and **RESOLVED 2026-08-06, same session** — found by Rick reviewing the F119 fix on staging ("a rejected title was shown as arriving for the scheduled week"), fixed same session, live on staging (`56da34c`) and **production** (PR #104, merge `2029e70`).
- **Severity:** Medium — unlike F118/F119 (paper-artifact correctness only), this one has real operational and customer-facing consequence: staff would search a shipment for a book that was never ordered, and the customer's own reservation list gave no hint that a title they're expecting will never show up.
- **Symptom:** a rejected title (`order_submissions` net quantity ≤ 0) whose `on_sale_date` fell in the current week appeared on the admin Bagging List as an ordinary checkbox row — no different from a title genuinely arriving — and counted toward that week's item/dollar totals. The same title showed no different from any other reservation on the customer's My List (current-month table, mobile card, or Upcoming Arrivals), which is the reverse of F119's discovery: F119 found the *panels* leaking into a printout that shouldn't have them; this is the *reservation itself* carrying no signal at all, on either the admin or customer side.
- **Diagnosis:** two independent gaps, same root cause (the order ledger, added by F101/F102/F108, was never wired into either surface):
  1. `renderThisWeek()` (Bagging List, `admin.html`) is a pure schedule query — `catalog.on_sale_date BETWEEN weekStart AND weekEnd` — with no reference to `fulfilled`, `weekly_shipment`, `order_submissions`, or `catalog.withdrawn_at`. It answers "what's scheduled," not "what will physically be in the box."
  2. `mylist.html`'s row rendering (desktop table, mobile card, Upcoming Arrivals) already checked `catalog.withdrawn_at` (F110) and `order_state === 'ordered'` (this session's own V-B2 fix, which correctly stops a rejected code from reading "Order placed") — but a rejected code that is neither `'ordered'` nor withdrawn falls through every branch to the default case: an entirely ordinary-looking row. Absence of a false positive (V-B2) is not the same as presence of a warning, and nothing supplied the latter.
- **Scope decision (Rick, 2026-08-06):** flag both surfaces, badge-only on the customer side — **no FOC/ordered-lock override**, unlike withdrawn (F110). Rick's reasoning: *"this may not land on My List long enough for the customer to take action on anyway"* (a rejected title is often already close to or past its FOC/on-sale window by the time the supplier's rejection is known), and the raw signal has standalone value for future reporting regardless of whether the customer can act on it. This is a deliberate, narrower design than F110's full "generic unavailable" treatment (§ 4.5 of the order-loop-closure plan), not an oversight — a title can be `isRejected` without being cancellable, where a withdrawn title is always both.
- **Fix:**
  - `admin.html`: new `ledgerRejected()` helper (ledger rows present, net ≤ 0). `renderThisWeek()`'s query gained `isbn`/`upc`/`withdrawn_at`; every row is classified `isUnavailable` (withdrawn OR rejected) at load time and excluded from the header stats (Customers/Total Titles/Total Items/Est. Value) and each customer card's own item-count/$ meta. An unavailable row renders struck-through with its reason, no checkbox — flagged, never silently dropped, matching every other fix in this session.
  - `mylist.html`: new `rejectedCodeSet`, built from the *same* `get_ordered_codes()` call `isCodeOrdered()` already makes (`order_state === 'unavailable'` instead of `'ordered'` — no new query). All three customer-facing rendering paths (desktop table, mobile card, Upcoming Arrivals) gained an `isRejected` branch, reusing F110's `withdrawn-row`/`withdrawn-notice` CSS (the plan's own "reuse the generic unavailable status" instruction, § 3.7) with rejected-specific copy. No change to `Preorders.cancel()` or the FOC-lock logic — confirmed unnecessary, since the FOC lock was always client-side only.
- **Verification:** new Playwright coverage — `tests/06-admin-this-week-bagging.spec.ts` (Bagging List: struck-through, no checkbox, excluded from totals, sharing a card with a normal available title as a control) and `tests/15-order-export-ledger.spec.ts` (My List current-month table with a past FOC — confirms the badge shows *and* the row stays locked, proving badge-only; Upcoming Arrivals — confirms the badge shows with no Remove button, unlike withdrawn's). All 3 new tests green in isolation, then zero regressions across a full suite run (75 passed / 1 unrelated pre-existing environmental failure, confirmed non-reproducing in isolation — see this entry's own session note below). Fixtures torn down, reverified by live SELECT.
- **Session note — the 4th consecutive full-suite run this session hit a transient `ConnectTimeoutError`** reaching Supabase's GoTrue admin API during `createUser()`, in `09-promo-banner.spec.ts` (completely unrelated to this fix). Re-run of that spec alone: 5/5 green. Consistent with **F107**'s already-documented "repeated full-suite runs stress GoTrue-admin-adjacent calls" pattern, though a different symptom (raw connection timeout vs F107's 429/403) — recorded here rather than as a new finding, since a single non-reproducing occurrence doesn't yet clear F107's own bar for a distinct entry.
- **Where:** `admin.html` — `renderThisWeek()` (query + row rendering + header/card totals), `ledgerRejected()`. `mylist.html` — `rejectedCodeSet`, `isCodeRejected()`, the three row-rendering paths.
- **Related:** **F119** — found minutes earlier in the same staging review, which is what led Rick to look at the reservation data itself rather than just the panels. **F110** — the "generic unavailable" surface and CSS this reuses. **F117**/**F108** § 4.4/§ 4.5 — the signed ledger and the customer-facing design this is a scoped-down, badge-only slice of. **F107** — the unrelated environmental flake hit during verification.

#### F121 — the Admin Dashboard has accumulated four time-scoping models and three counting units on one page, and no session ever re-asked what the page's model is

- **Status:** filed 2026-08-07, raised by Rick after a day of Order Builder work: *"I am getting concerned about the Admin Dashboard losing its focus. Originally it was geared to the monthly catalog but now I see some other elements seeping in… Maybe we are ready to introduce a process mapping session."* **The process-mapping session ran 2026-08-07 — plan: `docs/admin-dashboard-process-map.md`.** Rick's three workflows are captured there (§ 5.1–5.3, his own walkthrough, authoritative over the code where they disagree); the element inventory found **six** time-scoping models and **five** counting units, not the four and three first recorded here. **Structure DECIDED — Option B, separate surfaces by cadence, built as three modes within one `admin.html`** (§ 5.7; a guided-run option was rejected on its merits — the monthly step order is genuinely flexible). Bounded by a tenant-neutrality constraint Rick raised (§ 5.6): phases may be fixed, task lists must be data-driven off `user_profiles.is_paper`, and no "step N of 8" may be hardcoded. **Six sessions indexed at § 5.7.4. RESOLVED 2026-08-09 — ALL SIX SESSIONS PLUS W2/W3 ARE LIVE IN PRODUCTION.** The finding's own closing condition was *"stays OPEN until the restructure lands"*; it has landed. Promoted via **PR #109 (`9552ee6`), #110 (`de0d7ca`), #111 (`f031916`), #112 (`d0b817b`), #113 (`d12921e`), #114 (`54d0dc3`)** — all six merges verified present on `origin/main`. The dashboard is no longer a tab strip: it is **three modes on three cadences** — Customers (ongoing, the landing mode) · Bagging (weekly) · Ordering (monthly) — each owning its tabs and page chrome, with one attention dot on Customers (red when a customer is already affected, amber for work still preventable). Session 6 closed with V1–V8 green, **103/103** Playwright, `PLAYWRIGHT_EXIT=0`, zero flaky; real-browser check and post-deploy write-smoke both passed (Rick, 2026-08-09).
  - **Verified independently 2026-08-10, not taken from CLAUDE.md:** `admin.html` is **byte-identical between `origin/main` and `origin/staging`**; the three-mode markup is present on `main` (`admin-modes` container, three `admin-mode` entries, the `mode-dot`); and the retired *All Reservations* tab survives only as five explanatory comments, no live surface.
  - **This entry was two days stale and said the opposite** — *"session 1 is COMPLETE on staging… Sessions 2–6 not started"* — while all six were in production. A session-opening read of the **canonical findings index** would therefore have concluded the restructure had barely begun. That is precisely the **F105** mechanism, this time in § 13 rather than in CLAUDE.md, and it is the second instance found in eight days. Corrected 2026-08-10.
- **Severity:** **Medium.** Nothing computes a wrong answer — every surface is correctly scoped *for its own purpose*. The cost is comprehension: the operator cannot tell from the page which question any given number answers, and has now tried three times in one day to reconcile numbers that were never meant to agree (dashboard PRH tile vs Order Builder export count: 67v70, 66v67, 35v36). Each time the numbers were individually correct. A dashboard whose figures cannot be cross-checked by the person acting on them is a slower, more error-prone dashboard even when every figure is right.
- **Measured 2026-08-07 — four distinct time-scoping models on `admin.html`:**
  | Scope | Backing array | Surfaces |
  |---|---|---|
  | Current catalog month | `allPreorders` | stats bar, By Customer, All Reservations, Top Series |
  | **All** catalog months | `gatherCollapsed` | Order Follow-Up panel, Withdrawn panel, Order Builder cycle list, `classifyForExport()` |
  | A **selected** catalog month | `distributorRows()` | By Distributor, Print/Save Report, Mark Ordered — **added 2026-08-06**, newest layer |
  | Mon–Sun calendar week | own query | This Week / bagging list |
  Plus surfaces with **no** time scope: Subscriptions, Pending Accounts, Paper Orders.
- **And three counting units, unlabelled until 2026-08-07:** **copies** (stats bar — sums `quantity`), **titles/distributor codes** (Order Builder, held-back panels, order sheets), **reservation rows** (By Customer groupings, and until this date the Order Builder summary itself — see F120's sibling fix). The tiles were relabelled to say "Copies" the same day, which stops them misdescribing themselves but does not make them reconcilable with the builder, and was never going to.
- **Diagnosis — no single decision was wrong, which is the point.** Every scope was introduced by a finding-driven session that scoped correctly for *its* problem: **F111** widened the order panels cross-month because a distributor FOC cycle genuinely spans catalog months; **F115**/**F116** added arrival-evidence triage; the 2026-08-06 cycle selector exists so a closed cycle stays printable after the next import. None re-asked whether the page as a whole still had one model. That is how drift accrues in a codebase whose own process rule is "one sub-deploy per session, stop and ask before touching anything else" — the rule that prevents scope creep also prevents anyone stepping back.
- **Working hypothesis for the session (not a conclusion):** the dashboard serves **three different cadences** at once — **monthly** (ordering: By Distributor, Order Builder, exports), **weekly** (bagging/arrivals: This Week), and **continuous** (pending accounts, subscriptions, paper orders). Different jobs, different rhythms, one screen. Whether the answer is separate pages, clearly-labelled scoped sections, or something else is exactly what the session should decide rather than assume.
- **Evidence the exercise pays:** Rick's five-step walkthrough of his monthly process on 2026-08-06 took minutes and immediately exposed a real design flaw — confirm-on-export asks whether to record the order *before the supplier has said which titles were rejected* (see `docs/order-loop-closure-f108.md` § 8, "decoupling record from download"). A full pass over the weekly and monthly workflows would likely surface several more of that kind.
- **Fix direction:** a process-mapping session — map the real weekly and monthly workflows, attribute every dashboard element to a workflow and cadence, settle one vocabulary for copies/titles/reservations, then decide the page structure. Deliberately **not** a UI patch; patching individual labels is what produced the current state.
- **Where:** `admin.html` throughout — `allPreorders` / `gatherCollapsed` / `distributorRows()` / `renderThisWeek()`; the stats bar; every tab.
- **Related:** **F111** (introduced the cross-month gather, correctly), **F115**/**F116** (arrival triage panels), **F120** (the rows-vs-titles confusion that made the unit drift visible), **F101**/**F102**/**F108** (the order-workflow findings whose sessions built most of these surfaces). **F103** and the "green is not the same as verified" note in `CLAUDE.md` — the adjacent lesson that a passing suite says nothing about whether a screen is coherent.

#### F122 — `auto_fulfill_past_on_sale()` reads the on-sale date of whichever catalog row a reservation points at, so a re-dated title is closed on its SUPERSEDED schedule

- **Status:** filed 2026-08-07. **RESOLVED 2026-08-08 on BOTH environments** via **Option 1** (Rick's choice) — `docs/f122-auto-fulfill-current-schedule.md`. `auto_fulfill_past_on_sale()` now judges against the on-sale date of the **newest listing** for that `(tenant_id, item_code, distributor)`, not the reservation's joined row. Verified by execution: on production the function returned **0** where the old body would have returned **3**, and the three reservations repaired by hand on 2026-08-07 (`fe56b7ae`/`b346fb36`/`f0b8e7b9` — 5 copies, 3 customers) remain `fulfilled = false`. **The manual repair is now durable; before this the next weekly import would have silently undone it.** Impact was measured read-only on both environments before any DDL: 3 rows stop being auto-fulfilled, **0 start**. Gate V1 of that plan failed for a pre-existing reason and became **F124**. **Option 3 (the catalog-upsert root fix) remains open by decision** — see Fix direction below. **A third manifestation was found 2026-08-10 on the *display* surfaces (`arrivals.html` reconciliation + `mylist.html`), folded into this entry at Rick's direction rather than filed separately — production repaired, and the import's month-scoped date-change report widened so the next occurrence is reported instead of discovered by a customer. See "THIRD MANIFESTATION" below.**
- **Severity:** **Medium-High.** Customer-facing and wrong while it lasts, and silent in both directions: nothing alerts, and the affected reservations then *disappear* from the customer's list. Contained today (1 title / 3 reservations / 5 copies / 3 customers) only because re-datings are uncommon — the same import auto-fulfilled 117 preorders, any of which could have hit this.
- **Distinct from F115, which is why it needs its own entry.** F115 is *"no arrival check, so a never-arrived title closes on schedule."* This is: the function reads `catalog.on_sale_date` **from the row the preorder is joined to**, and for a re-listed title that row is superseded. The book is not late and not missing — **it was rescheduled, and the app closed it against the old schedule.** F115's mitigation (the Step 9 pre-flight report) *does* surface these, which is how it was caught — but it reports them as "no shipment evidence", which reads as *might not have arrived* rather than *is not due for two months*.
- **Live instance:** `75960621668000111` MIDNIGHT X-MEN #1. PRH pushed it back nine weeks — solicited `2026-05`/`2026-06` with on-sale **2026-08-05**, re-listed `2026-07` with on-sale **2026-10-07** (Rick confirmed from the PRH record: `FOC 08/31/2026 | On Sale 10/07/2026 | Catalog: July 2026`). Reservations made from the May/June rows stayed pinned to them, so the 2026-08-05 date went past on 2026-08-05 and the 2026-08-07 import marked them fulfilled. Zero `weekly_shipment` rows: it has never arrived and is not due until October.
  - Fulfilled in error: Jay Underhill (1), Mike Neubauer (1), Book Stop (3) — **5 copies, 3 customers**.
  - Correctly untouched: the five reservations pointing at the `2026-07` row (on-sale 2026-10-07).
  - **Jay Underhill held the same physical comic in both states at once** — one copy "fulfilled", one pending — which is F85's cross-month duplicate making the split visible.
- **Why the customer impact is worse than a wrong badge:** `mylist.html` hides past-on-sale items from previous months. So the affected reservations do not merely read *"✓ Order placed"* — they **vanish from My List entirely**. The customer is told it is handled, and then it disappears, for a book arriving in October.
- **Root mechanism is F102's, one function over.** `preorders.catalog_id` does not survive a re-listing: a re-solicited title gets a new `catalog` row under the four-column upsert key (§ 4.3), and existing reservations keep pointing at the old one. **F85's carry-forward closes this for subscriber auto-reserves only** — manual reservations are never moved — so a manually-reserved re-dated title is guaranteed to be judged on its stale date.
- **Blast radius, swept across all of production 2026-08-07:** reservations fulfilled against a superseded row, where a newer row for the same `(distributor, item_code)` still has a future on-sale date and no shipment evidence exists — **exactly 3, all MIDNIGHT X-MEN #1**. No other title affected.
- **Repair applied 2026-08-07** (service-role PATCH; there is deliberately no UI path since "Mark Fulfilled" was removed on 2026-08-03): preorders `fe56b7ae…`, `f0b8e7b9…`, `b346fb36…` set `fulfilled = false`, `fulfilled_at = null`. Verified after: all 8 reservations for the code read `fulfilled = false`, and the ledger's net 8 means My List correctly shows *"✓ Order placed"* — true, since the store does have 8 on order.
- **Fix direction — Option 1 CHOSEN by Rick 2026-08-08; Option 3 filed the same day as the root fix, deferred:**
  1. **Judge on the newest row, not the joined row** — **CHOSEN.** `auto_fulfill_past_on_sale()` compares against the on-sale date of the newest *listing* for that `(tenant_id, item_code, distributor)` rather than the reservation's own catalog row. SQL written 2026-08-08 (`docs/sql/auto_fulfill_past_on_sale.sql`); plan and gates at `docs/f122-auto-fulfill-current-schedule.md`. **Newest listing, not `MAX(on_sale_date)`** — the two agree when a title is pushed back but not when one is pulled forward, where `MAX` would keep judging against the old later date and the title would never auto-fulfil. **Measured read-only on both environments before any DDL: production 3 reservations stop being auto-fulfilled (exactly the rows repaired by hand on 2026-08-07), 0 start; staging 0 and 0.**
  2. **Carry manual reservations forward on re-listing** — extend F85's carry-forward beyond subscriber auto-reserves. **Not chosen.** Broader than Option 1, but still a workaround for the same underlying split, and it touches the import's reservation handling against F85's own survivor rules.
  3. **Change the catalog upsert key so one physical comic is one row — THE ROOT FIX. Filed 2026-08-08, raised by Rick, deferred to its own session.** *"[It] was never invoiced by the supplier in previous months, it simply shifted to the new FOC and On-Sale date so the upsert on import could address this."* Correct, and **verified against production the same day**: the three `75960621668000111` listings are field-identical except `on_sale_date`/`foc_date` (and a title-string refinement, `MIDNIGHT X-MEN #1` → `… COVER A`) — same `price_usd`, `variant_type`, `publisher`, and `cover_url`. **The May and June rows carry no information the July row does not**, beyond the historical fact of having appeared in those catalogs. Dropping `catalog_month` from the upsert key `(tenant_id, item_code, distributor, catalog_month)` would give one row per physical comic, so a re-listing updates FOC/on-sale **in place** and `preorders.catalog_id` keeps pointing at a row carrying the current schedule. **That dissolves F122, F102's `catalog_id`-does-not-survive mechanism, F85's cross-month duplicates, and the 12-copies-against-8-demand phantom, in one change.**
     - **Cost, and why it is not a config tweak:** `catalog_month` is doing two jobs — the upsert key *and* the scoping key for 15+ consumers. Collapsing rows silently redefines it from *"which catalog this listing came from"* to *"month of the most recent listing"*. The sharpest casualty is the **By Distributor catalog-month selector** (2026-08-06, PR #105), which exists so a closed cycle stays reviewable and printable as a permanent record: if a row can move its `catalog_month`, *"what was in the June catalog"* becomes retroactively unanswerable.
     - **Middle path worth costing:** one catalog row per physical comic **plus a child table recording which catalogs it appeared in** — `catalog_id` becomes stable while cycle history survives. A real schema change, not a key swap.
     - **Measure first, before committing:** the change is safe only if *same `item_code` + same distributor = same physical comic, always*. The case that would break it is **a code that already shipped reappearing in a later `catalog_month`** (a restock/reorder listing), where merging would drag a delivered book's on-sale date forward. Directly countable: codes with a `weekly_shipment` row that also appear in a later catalog month. **Not yet measured.**
  Options 1 and 2 both treat symptoms; **Option 3 is the cause**. Option 1 ships first because it is surgical, measured and reversible, and because without it the next weekly import silently undoes the 2026-08-07 manual repair. Option 3 belongs with **F121**'s remaining sessions — *one physical comic represented as several catalog rows* is the theme under F85, F102, F122 and the phantom demand alike.
- **THIRD MANIFESTATION — the DISPLAY surfaces, found 2026-08-10. Folded in here rather than filed separately (Rick's call): same root, same title, third surface.** Option 1 fixed *auto-fulfilment* judging on the stale row. It did not, and could not, stop every read-side surface from doing the same thing — a reservation still points at the superseded row, so anything scoping by `catalog.on_sale_date` or `catalog.catalog_month` reads the old schedule.
  - **How it surfaced:** Rick asked why `arrivals.html`'s shipment reconciliation listed **11 titles "not in shipment"** for Mon 2026-08-03 – Sun 2026-08-09, MIDNIGHT X-MEN #1 among them despite an October on-sale date. **Only 1 of the 11 was this defect.** The other 10 (plus 1 zero-price "not tracked") had *consistent* dates across every listing, were all ordered on the **2026-06-27** cycle in quantities exactly matching their reservations, and have never appeared in any imported shipment from 2026-04-08 through 2026-08-12 — genuinely outstanding, **F108**'s problem, not this one. One of those (`75960621273600131`, X-MEN OF APOCALYPSE OMEGA #1 Madureira variant) is in the **2026-08-12** shipment: it slipped a week, and because PRH never re-listed it there is no newer row to learn the new date from — the F110 "absent rather than flagged" shape.
  - **Mechanism on the read side:** `arrivals.html` selects reconciliation preorders by `catalog.on_sale_date` within the week ([arrivals.html:954-955](../arrivals.html#L954)), so a reservation pinned to a superseded row is dragged into the *stale* row's week. Worse, `mylist.html` scopes its main table to `catalog_month === currentMonth` and `allUpcoming` to `on_sale_date >= today` ([mylist.html:821-825](../mylist.html#L821)) — once the stale date goes past, the reservation is in **neither**, so it is invisible to the customer. This is the same "vanishes from My List" consequence recorded above, reached without auto-fulfilment being involved at all.
  - **Why the customer split looked arbitrary:** Jay Underhill saw the title and Mike Neubauer did not, for the same book. Jay and Book Stop each held an **F85 cross-month duplicate** — one row on `2026-06`, one on `2026-07` — so the `2026-07` row kept them visible while the `2026-06` row sat dead. Mike Neubauer held only the `2026-06` row, so for him the title was simply gone. The reconciliation panel showed all three names on one line because it collapses by `item_code` ([arrivals.html:1043](../arrivals.html#L1043)) — that grouping is correct; the underlying rows were not.
  - **Blast radius, swept across all 2,005 production preorders 2026-08-10** (unfulfilled rows pinned to a superseded row whose `on_sale_date` disagrees with the newest listing): **exactly 4 rows, 2 titles.** MIDNIGHT X-MEN #1 — Book Stop (3), Mike Neubauer (1), Jay Underhill (1), all hidden; and `76156801424200321` **Grendel: Devil's Crucible–Sedition #3 CVR B** — Book Stop (2), showing 2026-09-23 instead of 2026-10-07, wrong but still visible. Context: 2,652 of 9,040 distinct titles appear in more than one `catalog_month`, so re-listing is routine — **only a re-listing that also changes the date does damage.**
  - **Repair applied 2026-08-10** (service-role, reversal script captured first): Jay's and Book Stop's redundant `2026-06` rows deleted (`fe56b7ae…`, `b346fb36…`), Mike Neubauer's repointed to the `2026-07` row (`f0b8e7b9…` → `ec6eaef1…`). The UPDATE was run **before** the DELETEs so a `preorders_user_id_catalog_id_key` violation would have failed harmlessly. Verified after: **6 rows, 8 copies, 6 customers, all on the `2026-07` listing, zero stale-month rows** — matching **F117**'s measured true demand of 8 and the PRH order Rick corrected to 8 on 2026-08-05. **Grendel repaired the same day** on Rick's instruction: identical three-row shape (`2026-05`/`2026-06` say 2026-09-23, `2026-07` says 2026-10-07), a single Book Stop reservation of 2 on the `2026-06` row and **no duplicate on the newest row**, so it was a pure repoint (`f8576651…` → `9ac21f72…`) with no delete. The PATCH was filtered on the *expected* `catalog_id` so a state change since the read would have matched zero rows and written nothing, rather than repointing something unexamined. Its ledger already held net 2 against 2 reserved, so nothing downstream moved. **A full re-sweep of production after both repairs returns zero stranded reservations.**
  - **The import's own warning was blind to this, and that is fixed.** `reportReservedInStoreDateChanges()` fetched `catalog_month=eq.<month being imported>`, so it compared July against July, found nothing, and printed **"No in-store-date changes on reserved titles"** while the book moved nine weeks. Widened 2026-08-10 in both scripts: it now reads every catalog row holding an **unfulfilled** reservation across all months (reservation-first and paged via `pageAllRows`, so it stays bounded and does not hit the 1,000-row cap of **F113**) and splits the result into **corrected** (same month — the upsert overwrites in place, self-healing) and **stranded** (older month — the upsert *cannot* reach it, needs repointing by hand), reporting reservation and copy counts and whether the stale date has already passed. Rows in a **newer** month than the import are deliberately ignored: that is an `isOlderMonth` backfill, where the incoming record is the stale side and flagging it would send the operator to repoint reservations onto old data. The diff was extracted into a pure `classifyReservedDateDrift()` and unit-tested (**10 cases × 2 scripts + 2 parity checks; suite 129 → 151**) precisely because the old version was network-bound and so could only ever be checked by running a real import — which is how the blind spot survived. Verified against live production: the classifier reports the Grendel row and nothing else, agreeing exactly with the independent sweep above.
  - **This does not fix the underlying pin** — it makes it *visible at import time* instead of discoverable only when a customer notices. Option 3 below remains the only fix that removes the class.
- **Where:** `docs/sql/auto_fulfill_past_on_sale.sql` (the `c.on_sale_date < CURRENT_DATE` predicate); `import.js` / `import-staging.js` Step 9, `findUnverifiedFulfillments()`, and `classifyReservedDateDrift()` / `reportReservedInStoreDateChanges()`; `mylist.html` past-on-sale auto-hide and `allUpcoming`; `arrivals.html` shipment reconciliation.
- **Related:** **F115** — same function, different defect; its Step 9 report is what surfaced this, and its text should not be read as covering this case. **F102** — the `catalog_id`-does-not-survive-re-listing mechanism, same live title. **F85** — the carry-forward that would have prevented it, and whose gap for manual reservations is the direct cause. **F116** — arrival-evidence clearing, which cannot help here because the book genuinely has not arrived yet. **F121** — the structural session both belong in.

#### F123 — the Lunar and PRH catalog normalizers emitted different key sets, so one 100-record batch failed on every import for four days

- **Status:** filed and **RESOLVED 2026-08-07, same session** — surfaced by the production monthly import Rick ran that evening and read the output of. Fixed in the scripts repo (commit `4b83ae3`, both `import.js` and `import-staging.js`). **The fix is committed AND pushed** — `4b83ae3` verified an ancestor of `origin/main` 2026-08-10, alongside `5bc7461` and `f9df045`. *(This line read "committed but NOT pushed" until 2026-08-10. The `guard-git` block that stranded it was a **hook bug, not policy** — Guard 1 could not resolve POSIX paths and failed closed; fixed 2026-08-10, see F104.)* The working copies on disk were correct throughout, so every import since has benefited.
- **Severity:** **Medium-High**, and higher than the observed damage suggests. On 2026-08-07 the cost was only stale data — the 100 records already existed from an earlier August run, so they simply were not refreshed. **On a new-month import the same batch failure would leave those ~100 titles absent from the catalog entirely**, unreservable by customers, with no error beyond one line in the import log.
- **Symptom, from the live run:**
  ```
  ❌ Catalog batch 1500–1600 failed: {"code":"PGRST102", …
     "message":"All object keys must match"}
     Upserted 2290/2390
     ⚠️  Catalog upsert done with errors: 2290 ok, 100 failed.
  ```
- **Diagnosis:** `refreshCatalog()` upserts `[...lunarCatalogNorm, ...prhCatalogNorm]` in batches of `BATCH_SIZE` (100). PostgREST requires every object in a bulk insert to have the same key set. **F112(a) (2026-08-03) added `initial_order_due` and `title_note` to the Lunar normalizer only** — PRH's feed carries neither column, so its records lacked both keys. Every batch is therefore shape-homogeneous *except* the single one straddling the Lunar→PRH boundary, which fails and takes all 100 of its rows with it. Deterministic, exactly once per import, on every import from 2026-08-03 onward. Verified against the normalized file: 2,390 records in exactly **two** key shapes, split at index 1513 (Lunar 1513 records / PRH 877), with the batch boundary at 1500 cutting across it.
- **Which records were lost on 2026-08-07:** indices 1500–1599 — the last **13 Lunar** titles (the alphabetical tail: `ZATANNA (2026) #7` covers A–E, the Zenescope one-shots, `YUMI 00EX #3`) and the first **87 PRH**. The set is not stable month to month: the failing batch is whichever one contains the boundary, so it moves with the Lunar row count. Any *new* title landing in that window would simply never be inserted.
- **Fix:** the PRH normalizer now emits `initial_order_due: null` and `title_note: null`. Explicit nulls, **not** `undefined` — an undefined value is dropped from the serialized JSON body and would reintroduce the mismatch, which is why the regression test asserts key **presence** (`'initial_order_due' in prh`) rather than value.
- **Regression coverage (`test/catalog-key-shape.test.mjs`, 4 assertions per script + export parity):** identical key sets between the normalizers; a mixed Lunar+PRH array resolving to exactly one shape (the array `refreshCatalog()` actually posts); PRH carrying both keys as explicit nulls; and Lunar still reading its own `InitialOrderDue`/`TitleNote` values so F112(a) is not regressed. `normalizeLunarCatalog`/`normalizePRHCatalog` were exported from both scripts to make this testable — the first extraction called for in `test/README.md`'s standing TODO. **A behavioural test could not have caught this**: each normalizer was individually correct; only comparing their *shapes* finds it.
- **Test-writing note worth keeping:** the first draft of that spec used `ItemCode` as the Lunar fixture's code column, but Lunar's `item_code` comes from **`Code`** (PRH's from `MainIdentifier`). The fixture rows failed the normalizers' own `.filter(r => r.title && r.item_code)`, so two assertions passed **vacuously** against empty arrays. Every test in the file now asserts its fixtures survived normalization first. A test that passes because it tested nothing is worse than no test.
- **Verified:** 129/129 scripts unit suite; and a `--no-write` dry run against the real `Lunar_Product_Data_0826.csv` + `2026_08_PRH_metadata_full_active.csv` now reports `Catalog upsert complete — 2390 records` with **zero** batch failures, against tonight's `2290 ok, 100 failed`. The regenerated `normalized_catalog.json` resolves to exactly 1 key shape.
- **Detection gap this exposes:** the import prints the failure and carries on — by design, since a partial catalog refresh is better than an aborted one. But `⚠️ Catalog upsert done with errors` is a warning in a long, otherwise-green log, and nothing downstream notices that 100 titles are stale. It went unremarked for four days and was caught only because Rick pasted the whole run output. Same shape as **F96** (a green CI run over a broken send) and **F102** (no signal at all). Worth considering whether a non-zero `failed` count should be a louder, end-of-run summary line rather than an inline warning.
- **Where:** `import.js` / `import-staging.js` — `normalizePRHCatalog()` (the two added keys), `normalizeLunarCatalog()` (F112(a)'s originals), `refreshCatalog()` (the `BATCH_SIZE` loop), `module.exports`. Private scripts repo. Both environments — staging carried the identical defect, unobserved only because nobody ran a staging import in the window.
- **Related:** **F112(a)** — added the two Lunar-only fields; correct in itself, and the direct cause here. **F82**/**F113** — the other "a silent limit truncates a bulk operation" class. **F96** — a failure that logged green. **F115** — the other defect surfaced by reading this same import's output.

#### F124 — SECURITY DEFINER execute grants were not least-privilege; `REVOKE … FROM PUBLIC` alone does not achieve it

- **Status:** filed and **RESOLVED 2026-08-08, same session, on BOTH environments.** Surfaced while verifying gate V1 of the F122 fix (`docs/f122-auto-fulfill-current-schedule.md`) — a routine "did the grants survive the replace?" check, not a targeted audit.
- **Severity:** **Medium.** A maintenance-only class of function was executable by roles that had no need for it. Corrected on both environments the same day, verified by execution; **no evidence of misuse, and no data affected** — the only rows ever written during investigation were purpose-seeded staging fixtures, since deleted.
- **The generalisable fact, which is the reason this entry exists:** Supabase bootstraps `ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated`. **Every new function in `public` therefore starts with those two role grants, and `REVOKE ALL … FROM PUBLIC` does not remove them** — a role grant is not the PUBLIC grant. A file that revokes only PUBLIC looks correct in review, passes any read of the SQL, and leaves both roles able to execute. **To lock a maintenance function down, `anon` and `authenticated` must be named explicitly.**
- **How it went unnoticed — the files disagreed with each other.** Each function's grants were written in a different session to a different standard, so the two environments faithfully reflected different files applied on different dates:
  | File | Revoked from |
  |---|---|
  | `docs/sql/purge_old_usage_events.sql` | PUBLIC + `anon` + `authenticated` ✅ |
  | `docs/sql/get-ordered-codes-rpc.sql` | PUBLIC + `anon` (`authenticated` intentional) ✅ |
  | `docs/sql/auto_fulfill_past_on_sale.sql` | PUBLIC only ❌ |
  The result was **drift in opposite directions** — staging had one function locked and another open; production had exactly the reverse. Neither environment was fully covered, and **the gap was invisible from either side alone**; it only appeared when both were listed side by side.
- **Resolution:** a signature-safe `DO` block over `oid::regprocedure` (structurally immune to the **F45** class of error, where a hand-written signature missed the real argument list) revoked `PUBLIC, anon, authenticated` from the maintenance-only DEFINER functions and re-granted `service_role` explicitly — the re-grant deliberately not assumed, in case any function's service access had itself come via PUBLIC. `docs/sql/auto_fulfill_past_on_sale.sql` was also corrected in-repo, so it cannot re-open the gap on a fresh environment (a rebuild, or a new tenant's project).
- **Verified by execution on both environments, not by reading ACLs:** every maintenance function returns `401 / 42501 permission denied` to a browser-key caller; `service_role` still executes (the weekly import is unaffected); and the client-facing set — `current_tenant_id`, `current_user_is_admin` (both invoked during **RLS policy evaluation**, so revoking them would break RLS itself), `get_popular_series`, `get_ordered_codes`, `resolve_tenant_by_slug` — confirmed **unchanged** with their grants intact.
- **Residual, deliberately not fixed here:** **`archive_stale_reservations`, `purge_stale_catalog` and `delete_dropped_catalog_items` have no file in `docs/sql/` at all** — they predate it, and their definitions exist only in the live databases. Nothing in the repo would recreate them correctly. Capturing them is worth a future session. Separately, **`is_admin` exists on production only**, is called by no application code, and is now locked; whether it should exist at all is an open question, not a defect.
- **Where:** `docs/sql/auto_fulfill_past_on_sale.sql` (grant block). Live function privileges on both environments.
- **Related:** **F122** — the fix whose verification surfaced this. **F45** — the signature-precision lesson the remediation was built to avoid repeating. **F23** — the earlier `search_path` hardening pass over the same function set, which addressed a different property of the same objects.

#### F125 — `main` and `staging` are not a superset relationship: `supabase/migrations/` exists only on `main`, and no doc says so

- **Status:** filed 2026-08-09, during the F121 session-6 production promotion (PR #114). **RESOLVED 2026-08-10** via the chosen fix direction — documentation. CLAUDE.md § Repository Structure now carries a dedicated *"`main` is NOT simply staging + prod config.js"* subsection naming both files, their commits and sub-deploys, why the documented merge flow is immune, which promotion styles would silently delete them, and the two things not to do (don't delete from `main`, don't copy to `staging`). **Re-verified against both remotes before writing:** `git ls-tree -r origin/main -- supabase/migrations/` returns exactly those two files, `origin/staging` returns nothing, and a full tree diff confirms they are the **only** paths present on `main` and absent from `staging`. No code or repo-state change — the asymmetry is deliberate and stays.
- **Severity:** **Low.** A latent trap in the promotion flow, not a defect. It has survived at least six promotions (PR #109–#114) without incident, because the documented flow happens to be immune to it.
- **The fact.** `git ls-tree -r main -- supabase/migrations/` returns two files; the same command against `staging` returns **nothing**. The directory has never existed on `staging` — `git log --all` shows each file touched by exactly one commit, both on `main`:
  | File | Commit | Sub-deploy |
  |---|---|---|
  | `20260531030927_phase_4_3_prod_constraints.sql` | `9111412` | Phase 4.3 |
  | `20260531150558_phase_4_4_prod_rls_functions.sql` | `3ecb6b0` | Phase 4.4 |
- **This was legitimate when it happened.** CLAUDE.md § Staging Only permits direct commits to `main` *"inside an explicitly-named Phase 4 cutover-window sub-deploy"*, which is exactly what 4.3 and 4.4 were. The finding is not that the commits were wrong; it is that they left a **structural asymmetry nobody wrote down**, and the mental model the deployment workflow implies — main = staging + prod `config.js` — has been false ever since.
- **Why it is currently harmless.** `git merge staging --no-commit --no-ff` cannot drop them: staging never held these paths, so there is no deletion in its history to replay. The `git checkout main -- config.js` step touches one file by name. Both files were confirmed present on disk after PR #114's merge.
- **Where it would bite.** Any promotion that reconstructs `main`'s tree from `staging` rather than merging into it — a squash promotion, a rebase-based flow, `git checkout staging -- .`, or a `git reset --hard staging` used to "fix" a messy main. Each would silently delete the only in-repo copies of the Phase 4.3/4.4 production DDL. It also quietly falsifies the reasoning *"staging is ahead of main"*, which is otherwise true and is the model the § Standard Deployment Workflow reads as.
- **What would actually be lost, measured rather than assumed:** the executable SQL. The *knowledge* survives — `docs/phase-4.3-prod-schema-constraints.md` and `docs/phase-4.4-prod-schema-rls.md` are on both branches and describe the work — and the DDL is applied in the live production database, so a loss would be a repo-history loss, not an outage. That is what keeps this at Low rather than Medium.
- **Note the asymmetry with `docs/sql/`,** which is where every migration since has gone: 9 files and identical on both branches *at filing*; **10 on `main` / 11 on `staging` as of 2026-08-10**, the one-file gap being an unpromoted migration moving forward normally. That ordinary lead is not this finding — the point is that `docs/sql/` flows through the promotion path, and `supabase/migrations/` never did. So the convention that replaced this one is already correct and already followed; these two files are the residue of an earlier, pre-convention moment, not an ongoing practice.
- **Fix direction (not applied, Rick's call):** the cheap and sufficient fix is **documentation** — one line in CLAUDE.md § Repository Structure recording that `supabase/migrations/` is main-only and why, so the next person to design a promotion flow knows before they design it. Copying the two files onto `staging` would also work and would make the superset claim true, but it puts prod-cutover DDL on a branch that must never run it, which is a worse trade. **Do not "fix" this by deleting them from `main`** — they are the only in-repo record of that DDL.
- **How it was found:** a pre-flight `git diff --name-only main staging` during PR #114, run to confirm `config.js` was the only expected difference. The two `.sql` paths appeared in that list and had to be traced by hand, because no doc could answer whether they were expected. That hand-tracing is the cost this entry exists to remove.
- **Related:** **F105** — the same class of failure, where a gate lived in a SQL file rather than in a plan's completion criteria and went unmet for 13 days. Both are cases of **real state recorded nowhere a session-opening read would find it**. **F59** — the merge-base regression check in the promotion flow, which is the other guard against a promotion silently producing the wrong tree.

#### F126 — no profile-editing surface: name, email and `is_admin` are unreachable outside the Supabase console

- **PARTLY RESOLVED 2026-08-10, live in production** (PR #116, merge `aa35d7f`) — `docs/admin-account-lifecycle-f126.md`. Shipped: `get_account_activity()` (SECURITY DEFINER, admin-gated in its **body** because admins are `authenticated` too), a sortable **Last seen** column, a **Never signed in** filter, **Edit → `full_name`**, and pause's confirm stating that existing reservations stand. **On production the filter lists exactly one person: `Ronald Burke`** — invited 2026-03-17, never confirmed, never signed in.
- **What REMAINS open in this entry:** editing **email** (needs an Edge Function — `user_profiles.email` is a denormalized copy and `auth.users.email` is the login identity, **F25**) and editing **`is_admin`** (**cut by Rick 2026-08-09** as a privilege-escalation surface whose only guards would be client-side; stays a Supabase-console task, rendered *absent* rather than disabled, with a spec asserting the absence).
- **Two corrections this session made to its own plan, both found by probing rather than reading:** the RPC's gate was written `IF NOT current_user_is_admin()` and was **open** — that function returns NULL, not false, for a caller with no identity, so the IF was never taken and it returned `[]` only because `current_tenant_id()` was also NULL (fixed to `IS NOT TRUE`); and the filter was planned as `created_by_admin AND never signed in`, which **cannot** mean "invited" because that column **defaults to true** and `register-customer` never sets it — it matched a self-registered account on staging, and the label was corrected to what the data supports.

- **Status:** filed 2026-08-09 from Rick's Accounts-tab direction; **narrowed the same day to editing only** — the pause half was settled and moved into the Accounts session (see below). **Deferred by Rick's explicit choice** — *"The edit feature is a real need but can be logged for a future change."* **Scoped OUT of the Accounts session**, which renders **no Edit control at all** rather than a disabled one.
- **Severity:** **Medium as a product gap, not a defect.** Nothing is broken; a capability the data model already supports has no way to be reached.
- **What is missing.** There is no surface anywhere in the app that edits a `user_profiles` row. A customer's name or email cannot be corrected, and `is_admin` cannot be granted or revoked, except in the Supabase console. Rick's ask adds a second, operationally-driven need: **pause a customer who stops collecting their reservations**, returning them to Pending until they re-engage.
- **Half the machinery already exists and has never been wired up:**
  | Piece | State |
  |---|---|
  | `user_profiles.status` CHECK | `IN ('active', 'pending', 'suspended')` — all three legal |
  | `Users.suspend(userId)` (`app.js`) | writes `status = 'suspended'` — **zero call sites in any HTML or JS** |
  | `'suspended'` status | **no UI reads it, no UI writes it, no code branches on it** |
  | `'pending'` status | fully wired — `catalog.html` blocks reserving and subscribing on it |
  This was noticed and recorded at **5.0 S3 (2026-06-11)**: *"`Users.suspend` has no admin UI entry point in current `admin.html` (no Users tab)."* The Accounts tab is precisely the entry point that entry anticipated, more than a year of sessions ago.
- **SETTLED 2026-08-09, and the pause half MOVED OUT of this entry.** The design question below was put to Rick, who answered it better than either option offered: **`'suspended'` exists as its own status but carries the same permission impact as `'pending'`.** That takes `'suspended'`'s correct semantics *and* `'pending'`'s existing enforcement, because the enforcement check is widened to cover both rather than the state being reused. **Pause therefore ships in the Accounts session, not here** — this entry now covers **profile editing only** (name, email, `is_admin`).
  The question as posed, kept because the reasoning still governs any later change:
  - **`'pending'`** — already enforced, restorable via the existing Approve button, but it **collides with the meaning of the Pending list** (*self-registered, never yet approved*). A paused long-standing customer appearing there is a different thing wearing the same label — the conflation F121 exists to remove.
  - **`'suspended'`** — semantically correct and already in the CHECK, but **enforced nowhere**, so choosing it alone means implementing the block, not just the button.
  Rick's answer takes the first option's enforcement and the second's vocabulary, and costs one line (`catalog.html:245`, read by 8 sites in that file).
- **Enforcement caveat that rides along, and must not be glossed:** that parity is **client-side only**, because `'pending'` itself is — measured, not assumed. See **F127**. "Paused" is a UI block, not a hard one, and must not be described as more than that.
- **Still open here, and genuinely undecided:** whether a paused customer's existing reservations are cancelled, held, or left to the FOC/ordered locks. Untouched by the Accounts session; it has real money attached once a title is ordered (**F109**, **F117**).
- **ALSO FOLDED IN 2026-08-09 — "Last seen", and surfacing invites nobody answered.** Rick, on reviewing the Accounts tab: *"Does last login exist as this would let me sort unanswered invites?"* His call was to fold it here rather than run it as its own session, since this entry already owns the account lifecycle and one session beats three touching the same rows.
  - **It exists — `auth.users.last_sign_in_at` — but it is NOT reachable from the admin client.** There is no `public.auth_users` view: a service-role read returns **404 `PGRST205 Could not find the table 'public.auth_users'`**. Only the GoTrue admin API can read it, and the admin client must never hold a service key. **Fix shape: a SECURITY DEFINER RPC** returning `(id, last_sign_in_at, email_confirmed_at)`, tenant-scoped via `current_tenant_id()` internally and admin-only — the `get_ordered_codes()` pattern, and subject to **F124**'s grant lesson (name `anon` and `authenticated` explicitly; `REVOKE … FROM PUBLIC` alone does not lock it).
  - **The cheap proxy was tested and FAILS — do not retry it.** `has_seen_welcome` is already fetched and looks like a free stand-in for "never signed in". Measured against `last_sign_in_at` on **production**: it agrees **8 of 12**. Brian Moss, Book Stop, Hector Gonzalez and The Comic Store Admin have all signed in but read `false` (they predate the welcome modal). Using it would flag four active customers as unanswered invites — a false positive is worse here than no column at all.
  - **Why an unanswered invite is invisible today, and it is not the missing column.** `invite-customer` sets `status: 'active'` at the moment the invite is sent (`supabase/functions/invite-customer/index.ts:136`), while `register-customer` sets `'pending'`. So an invited customer is indistinguishable from a real active one whether or not they ever respond. A third state (`'invited'`) would need the `user_profiles_status_check` CHECK widened, and collides with this entry's own pause work — **decide the two together, not one then the other.**
  - **Measured scale — production, 2026-08-09: exactly ONE.** `Ronald Burke`, invited **2026-03-17**, `status = 'active'`, email **never confirmed**, **never signed in** — almost five months. 12 non-paper profiles, 1 never signed in. Small, but it is a real customer who fell through with nothing on any screen to show it. **Operational, ahead of any code — and DONE: Rick called him 2026-08-10.** Worth keeping as the shape of the finding: the software's job was to make him *visible*; it was never going to be the fix.
- **Related:** **F121** — the restructure that surfaced this by giving accounts a home. **F13**/**F25** — `user_profiles` denormalisation and cascade questions that an edit path would have to respect (`email` is copied from `auth.users` with **no sync trigger**, so an email edit writes to one of two places and silently diverges them). **F10** — `preorders` FK is `ON DELETE NO ACTION`, which is why profile deletion already fails loudly and why any "remove" affordance here needs care.

#### F127 — account `status` is not an authorization boundary: the pending gate is client-side only

- **Status:** filed 2026-08-09 while scoping the Accounts tab. **Open, deferred** — Rick's call the same day: ship `'suspended'` at **parity** with `'pending'` (a one-line client change) and file the enforcement gap **as its own finding so it is visible rather than assumed closed**, instead of widening the Accounts session into a `preorders` RLS change.
- **Severity:** **Low–Medium.** Authorization gap, **not** data exposure: no cross-tenant read, no credential exposure, nothing readable that was not already readable. It requires an account that has self-registered and confirmed its email but **not yet been approved by an admin**, and the effect is that such an account can create reservation rows early. Same *shape* as **F109** — a guard that exists in the client and not in the database.
- **Measured, not inferred.** Confirmed on **staging** 2026-08-09 by a throwaway probe: create an auth user → insert its profile at `status = 'pending'` → sign in **as that user** → `POST /rest/v1/preorders` with its own JWT and the browser key. **Result: HTTP 201, row persisted.** Fixture fully torn down; profile rows remaining = 0, which also evidences the preorder was cleared (F10's `ON DELETE NO ACTION` would have blocked the profile delete otherwise). The probe was written only after a doc read suggested this, precisely because CLAUDE.md § Verify before escalating requires a live check for a security claim — and the doc read alone would have been filed as fact.
- **Root cause.** No policy on `preorders` references `status` at all:
  | Policy | Condition |
  |---|---|
  | `users manage own preorders` | `auth.uid() = user_id AND tenant_id = current_tenant_id()` |
  | `admins manage tenant preorders` | tenant + admin |
  | `admins write tenant preorders` | tenant + admin (see **F16**) |
  | `admins view tenant preorders` | SELECT, redundant |
  The entire pending gate is `catalog.html:245` — `const isPending = !profile?.is_admin && profile?.status === 'pending'` — read by 8 sites in that one file, all of which hide or disable UI. Nothing downstream re-checks.
- **Consequence for the account lifecycle being built (F126).** Because `'suspended'` is shipping at parity with `'pending'`, **it inherits this gap by construction.** A paused customer is paused in the UI. That is a deliberate, informed trade — the alternative was a production RLS change on the app's busiest table, whose policy set already carries F16's cross-tenant write defect — but it means **"paused" must not be described to anyone as a hard block.**
- **Also unenforced, same cause:** `subscriptions.html` has **no status check at all**, so a pending or suspended user can subscribe by ordinary use of the page — no crafted request needed. Worth confirming empirically before any fix, the same way this entry was.
- **Fix direction (not applied).** Add a status predicate to the `users manage own preorders` policy (and the equivalent on `subscriptions`), e.g. requiring the caller's profile to be `'active'`. **Do this as its own session with its own gates:** it touches the policy set F16 already flags, it must not break admin impersonation (`AdminContext` writes preorders on a customer's behalf while the *admin* is the authenticated user), and the import script's service-role writes must remain unaffected. A `SECURITY DEFINER` helper mirroring `current_user_is_admin()` is the likely shape, since a subquery against `user_profiles` inside a `user_profiles`-adjacent policy is how **RLS recursion** was caused before (see § Known Issues).
- **Related:** **F109** (client-side-only cancel guard — same shape, and the entry that established the fix direction is a trigger/policy rather than more client code). **F126** (the lifecycle work that inherits this). **F16** (the `preorders` policy defect any fix here must not compound). **F10** (the FK that made the teardown self-verifying).

Next free finding ID: **F128**.

---

*End of document.*
