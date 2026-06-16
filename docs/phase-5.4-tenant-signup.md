# Phase 5.4 — Tenant Signup

**Status:** **Planning** — plan written 2026-06-15; not yet executed. Active sub-deploy.
**Parent plan:** `docs/phase-5-second-tenant-onboarding.md` (sub-deploy row 5.4)
**Predecessor:** Phase 5.3 — Per-Tenant Branding — **Complete 2026-06-15** (`resolve_tenant_by_slug` 4-col both projects; `Branding.apply()` override layer live; `FOUNDING_TENANT` in per-env `config.js`; F71 resolved).
**Branches:** This sub-deploy is **backend-only** — Edge Function source (`supabase/functions/**`, tracked) + database data/DDL + docs. **No `app.js` / `*.html` / `config.js` / `style.css` change is in scope** (no public signup *page* is built — the tenant-creation surface is a gated operator Edge Function, not a customer-facing screen; see § 1.6). Doc commits → `staging` directly. EF source edits ride `feature/5.4-tenant-signup` off `staging` → `--ff-only` merge → staging deploy + smoke → prod EF redeploy per § Standard Deployment Workflow's Edge-Function path. Because no `config.js` key is added, the prod promotion does **not** need the per-branch `config.js` dance — but it **does** need per-project Edge-Function secret setup and a per-env founding-tenant data migration (§ S6).
**Execution model:** **CLI-orchestrated, Rick-in-the-loop.** A Claude Code CLI (Sonnet) session runs this file top to bottom. It executes every repo / doc / local-script / Playwright step itself, and **pauses at every database step (staging *and* prod), every Supabase dashboard / CLI platform action (Edge-Function deploy, secret setting, JWT-verify toggle), every GoTrue admin-API call that writes auth users, and the prod EF promotion** — handing Rick the exact SQL / clicks / curl / values and **waiting for pasted results before continuing**. **Self-contained — no chat context required.**
**Rollback complexity:** **Medium** (parent table) — signup writes real `tenants` rows + auth users + `user_profiles`. An FK-ordered teardown (the Phase 4.1 canary procedure, `docs/phase-4.1-canary-procedure.md`) **must exist and be exercised before the flow is reachable** — it is, in S4, with a verifying 0-row SELECT. The `register-customer` un-pin and the new `register-tenant` function are independently revertible (redeploy prior source). The S0 prod FK realignment is a one-time DDL, revertible by re-adding the prior constraint shape (pre-captured).

> **Steps Claude never runs itself.** (1) Any Supabase **SQL Editor** statement — staging *or* prod (S0 prod FK DDL; the founding webhook-secret migration; teardown). (2) Any **Edge-Function deploy** or **secret/JWT-verify** dashboard/CLI action (staging *and* prod). (3) Any **GoTrue admin-API** call that creates/deletes `auth.users` (canary admin + customers). (4) The S6 prod EF promotion. Each appears below as a **`PAUSE → Rick … → paste result → match expected → continue / STOP`** block. The agent edits EF source, runs local verification (`Select-String`, `curl.exe` against staging with the staging anon key), and the Playwright suite.

> **5.4 may span multiple sittings.** The durable state is the **Deploy Log (§ 8)**: every session appends one row per completed step. A resuming session reads the log, re-verifies the last recorded step against live state (a recorded EF deploy is re-verified by probing the endpoint; a recorded DB migration by re-running the SELECT; the canary teardown by the 0-row SELECT), and continues from the next unexecuted step. Every doc edit is committed before the session ends.

> **Founding-tenant invariant (parent completion criterion for every 5.x sub-deploy) — and how 5.4 satisfies it.** 5.4 changes *how a new customer's tenant is resolved* (`register-customer`) and *adds* a tenant-creation path — it must not alter the founding tenant's behavior. The un-pin is sequenced so the **founding tenant's webhook secret is migrated into its own `tenants` row (S1) BEFORE** the un-pinned function deploys (S2): there is no window in which the founding MailerLite webhook stops resolving to the founding tenant. No customer-visible founding surface (catalog/mylist/arrivals/subscriptions/admin/index) changes at all. Every gate runs the full Playwright suite including the tenant-isolation specs (F15/F20); the founding register flow is additionally smoke-verified (a founding-secret webhook call still lands the customer in the founding tenant) at S2 (staging) and S6 (prod).

---

## 0. Pre-flight (run at the top of every 5.4 session; halt on any mismatch)

### 0.1 Read before doing anything
- `CLAUDE.md` in full; confirm § Current Migration Phase active sub-deploy = **5.4**. Note § Edge Functions (off-plus-in-body-auth pattern; `register-customer` is the deliberate public exception; `FOUNDING_TENANT_ID` secret on both projects), § Credential Safety (service-role keys local-only; agent never edits `config.js` — **not touched here anyway**), § Standard Deployment Workflow, § Anti-Drift Rules.
- `docs/phase-5-second-tenant-onboarding.md` — Sub-Deploys row 5.4; § In Scope **5.4**; § Deferred-DDL Register (F64 item 5 — **the hard prerequisite, landed as S0**); § Approach Decisions ("signup before onboarding (5.4 before 5.5), onboarding gated"); § Phase Completion Criteria (the `register-customer no longer hard-pinned` box); § Rollback row 5.4 ("teardown must exist before the flow opens"); § Out of Scope (**multi-tenant email branding / per-tenant MailerSend identities are explicitly OUT of Phase 5** — see § 1.5 / § 3).
- This file in full — including the Deploy Log (§ 8): if any rows exist, this is a resume session.
- `docs/technical-reference.md`: § 4.1 (`tenants` table — columns, `tenants_slug_format_check` DNS-safe regex, `branding`/`settings` jsonb defaults `{}`, "**No INSERT or DELETE RLS policy: tenant creation is service-role-only**"); § 13 **F34** (`register-customer` residual founding-tenant pin — the un-pin target), **F64 item 5** (the exact prod FK DDL — § S0), the `resolve_tenant_by_slug` contract note, and § 1.x Edge-Function inventory / auth model.
- `supabase/functions/register-customer/index.ts` — **read the actual current source from disk** (anti-drift: do not infer from this plan). Note the header F34 comment (~20–27), the `FOUNDING_TENANT_ID` env read (~46), the `?secret=` gate against `MAILERLITE_WEBHOOK_SECRET` (~52–58), the group filter (~68–83), and the `user_profiles` insert pinning `tenant_id: FOUNDING_TENANT_ID` (~136–155).
- `docs/phase-4.1-canary-procedure.md` — the spin-up + FK-ordered **teardown** template reused in S4 (and again by 5.5). The teardown delete order is load-bearing.
- One existing in-body-auth function for the house pattern (e.g. `supabase/functions/create-paper-customer/index.ts` or `invite-customer/index.ts`) — `register-tenant` (new, S3) follows the established structure (CORS, env reads, service-role REST/GoTrue calls, JSON error shapes).

### 0.2 Gates (halt if any fail)
- `git rev-parse --abbrev-ref HEAD` → `staging`; `git status` → clean (the known-stray untracked `docs/status-slide.html` is acceptable; anything else, stop and ask).
- `git pull origin staging` → up to date (or fast-forward) before any edit.
- `docs/technical-reference.md` § 13: confirm the highest filed finding ID. At planning time the next free ID is **F72** (5.3 filed none). **5.4 files F72** (register-customer email template still founding-branded post-un-pin — deferred, see § 1.5). New *additional* defects discovered during 5.4 are filed from **F73** — never guessed or reused.
- **Re-verify the planning-time audits in § 1 against the current tree and live DBs** (anti-drift: never trust a prior session's grep/read). Re-read `register-customer/index.ts` from disk before any edit; re-query the live prod `preorders_user_id_fkey` shape before the S0 DDL (confirm it is still `auth.users` CASCADE on prod, `user_profiles` NO ACTION on staging).
- **S0 is a gate on everything else.** No S1+ feature work begins until S0 is green (F64 item 5 prod FK realigned, `confdeltype = a` verified). If S0 cannot complete, STOP.

### 0.3 Commit discipline
- Each S-step's doc update (contract notes, finding statuses, deploy-log row) is its own doc-only commit to `staging` with the finding ID(s) where relevant — exact messages inline.
- EF source changes ride `feature/5.4-tenant-signup`, never `staging` directly. **`register-customer` un-pin (S2) is its own commit; the new `register-tenant` function (S3) is its own** — so each is independently revertible.
- `config.js` is **not touched** by this sub-deploy (no new client key). If execution discovers a real need for one, **STOP and ask** — it would be a scope change (and Rick, not the agent, edits `config.js` per branch).
- Push `origin staging` after each commit; the Deploy Log row lands in the same commit as the step it records.

### 0.4 Files / surfaces touched by this sub-deploy

| File / target | Change | Branch / actor |
|---|---|---|
| Production DB (`public` schema) | **S0:** `preorders_user_id_fkey` DROP + re-ADD → `user_profiles` NO ACTION (F64 item 5; removes `auth.users` target + CASCADE) | Rick, prod SQL Editor |
| Staging DB (`public.tenants`) | **S1:** write the founding tenant's existing MailerLite webhook secret into `tenants.settings->>'mailerlite_webhook_secret'` (data, no DDL) | Rick, staging SQL Editor |
| Production DB (`public.tenants`) | **S6:** same founding webhook-secret migration on prod (before prod EF promotion) | Rick, prod SQL Editor |
| `supabase/functions/register-customer/index.ts` | **S2 (F34 residual):** resolve `tenant_id` from a per-tenant webhook secret (DB lookup) instead of the `FOUNDING_TENANT_ID` pin; update header F34 note → resolved; **email template unchanged** (founding-branded — F72 deferral) | `feature/5.4-tenant-signup` |
| `supabase/functions/register-tenant/index.ts` | **S3 (new, 9th EF):** gated operator function — claim slug, create tenant row + first admin + seeded settings/branding; service-role writes; operator-secret gate; generates the tenant's webhook secret | `feature/5.4-tenant-signup` |
| Supabase Edge-Function **secrets** | **S3/S6:** `TENANT_PROVISION_SECRET` (operator gate for `register-tenant`) set on **both** projects | Rick, dashboard/CLI (staging S3, prod S6) |
| Edge-Function **deploys** | **S2/S3 staging; S6 prod:** deploy `register-customer` (updated) + `register-tenant` (new) | Rick, dashboard/CLI |
| Playwright suite (local-only, never committed) | New negative-path specs (reserved/duplicate slug rejected; un-pin routes a customer to the correct tenant; teardown leaves founding intact); existing tenant-isolation (F15/F20) unchanged in intent | Claude, direct edit |
| Canary scratch (`phase-4.1-canary-uuids.txt`, local-only) | **S4:** regenerated for the 5.4 dry-run; canary created **through** `register-tenant`, torn down per § 4.1 procedure | Claude + Rick (GoTrue/SQL steps) |
| `docs/technical-reference.md` | § 13 **F34 → resolved** (residual un-pinned); **F64 item 5 → resolved** (S0 DDL landed); **F72 filed** (email-branding deferral); new `register-tenant` contract + `register-customer` per-tenant-secret note; § 1.x EF inventory → 9 functions; § 4.1 tenants note (per-tenant webhook secret in `settings`) | `staging` (doc-only) |
| `docs/phase-5-second-tenant-onboarding.md` | Row 5.4 → Complete; Deferred-DDL Register F64 item 5 → closed; Carry-Forward F34 row ticked | `staging` (doc-only) |
| `CLAUDE.md` | § Current Migration Phase pointer → 5.5; § Edge Functions inventory → 9 (add `register-tenant`; `register-customer` un-pinned); § Known Out-of-Scope signup line → Complete; open-findings line (F34/F64-5 resolved; F72 filed) | `staging` (doc-only) |

**Not touched:** `app.js` / `*.html` / `config.js` / `style.css` (no client/UI change — no public signup page in 5.4); `import.js` / `import-staging.js`; the other 7 Edge Functions (email/invite/approve/etc. — their tenant resolution was already fixed at F34 / Phase 4.6); the `register-customer` **email template** (founding-branded — multi-tenant email branding is OUT of Phase 5, F72); `tenants` RLS (no INSERT/DELETE policy is the intended design — `register-tenant` writes via service-role).

---

## 1. Planning-time design (2026-06-15) — re-verify at execution

### 1.1 S0 — the F64 item 5 hard prerequisite (prod FK realignment)
Decision already made (5.0 S3, 2026-06-11): **Option A — profile-first, preorder-blocking; staging shape canonical.** `preorders_user_id_fkey` must reference `public.user_profiles(id)` NO ACTION on **both** envs. Staging already does; **prod still references `auth.users(id) ON DELETE CASCADE`** (F64 item 5; § 13). The handoff makes this a *gating predecessor* — 5.4 feature work must not begin against the unaligned prod FK. **Placement (Rick, 5.4 planning 2026-06-15): S0 pre-flight gate** — a single prod-DDL block at the top of the runbook; S1+ blocked until it is green.

Exact prod DDL (from § 13 F64 item 5):
```sql
ALTER TABLE public.preorders DROP CONSTRAINT preorders_user_id_fkey;
ALTER TABLE public.preorders ADD CONSTRAINT preorders_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES public.user_profiles(id);   -- removes auth.users target + CASCADE
```
Pre-flight: confirm **0 blocking rows** (preorders whose `user_id` has no matching `user_profiles.id`) before the re-add, or the ADD fails. Post-verify: `confdeltype = 'a'` (NO ACTION) and the referenced relation is `user_profiles`.

### 1.2 S2 — `register-customer` un-pin: per-tenant webhook secret
**Decision (Rick, 5.4 planning 2026-06-15): per-tenant webhook secret stored in the tenant row.** `register-customer` is the one intentionally-public endpoint; its only trustworthy tenant signal is the webhook URL. Today every founding-tenant MailerLite webhook carries `?secret=<MAILERLITE_WEBHOOK_SECRET>` and the function pins `tenant_id = FOUNDING_TENANT_ID`. The un-pin: **the incoming `?secret=` both authenticates *and* selects the tenant** — the function looks up the tenant whose stored secret matches.

- **Storage:** `tenants.settings->>'mailerlite_webhook_secret'` (jsonb; `settings` is service-role-only — never exposed by `resolve_tenant_by_slug`, no anon/authed read path). No DDL needed (column exists). A dedicated indexed `webhook_secret` column or a hashed secret is a future hardening — **file, don't build** if raised (5.4 keeps the change to data + function logic).
- **Resolution (service-role, inside the function):**
  ```sql
  -- conceptually: SELECT id, slug, display_name FROM tenants
  --   WHERE settings->>'mailerlite_webhook_secret' = <provided secret> LIMIT 1
  ```
  via service-role PostgREST: `GET /rest/v1/tenants?settings->>mailerlite_webhook_secret=eq.<secret>&select=id,slug,display_name`.
- **Gate semantics:** empty/absent `?secret=` → `401` immediately (no NULL-match). No matching tenant → `401`. A caller can register a pending customer **only** into the tenant whose secret they hold → **no cross-tenant injection**. (Even a leaked secret only creates a *pending* `user_profiles` row in that one tenant + an email; the user can do nothing until that tenant's admin approves — but the per-tenant secret removes the shared-secret blast radius entirely.)
- **Sequencing (founding invariant):** the founding secret is migrated into `tenants.settings` in **S1**, *before* the un-pinned function deploys in **S2**. The founding MailerLite webhook URL is **unchanged** (same `?secret=` value), so it keeps resolving to the founding tenant with zero webhook-config change. The `FOUNDING_TENANT_ID` env pin is removed from `register-customer`'s insert path (the env secret stays set — other functions / the F34 fallback elsewhere use it — but `register-customer` no longer reads it for tenant assignment).
- **`MAILERLITE_WEBHOOK_SECRET` env var:** after the un-pin, `register-customer` no longer compares against it (the per-tenant DB lookup replaces it). Leave the secret set during 5.4 for safety; its removal from the function's logic is the actual change. The group filter (`'Monthly Comics'`) and all other behavior are unchanged.

### 1.3 S3 — `register-tenant`: gated operator Edge Function (new, 9th EF)
**Decision (Rick, 5.4 planning 2026-06-15): a gated service-role Edge Function, operator-initiated (not open public self-serve).** No INSERT RLS on `tenants` (service-role only by design); no customer-facing signup page is built in 5.4 (open self-serve is a larger abuse surface — slug squatting, spam tenants — and is **out of scope**; file if raised). Matches the parent's "onboarding gated" decision.

- **Auth gate:** JWT-off at the platform layer (house pattern) + an **operator secret** check in-body/header — `TENANT_PROVISION_SECRET` (new per-project EF secret). Tenant provisioning is a *platform-operator* action, distinct from any tenant's admin role, so it is gated by an operator secret rather than reusing a tenant-admin's in-body identity. (Alternative considered: gate by "caller is the founding tenant's admin" via the in-body `/auth/v1/user` → profile pattern. Operator-secret is recommended — it does not conflate founding-admin with platform-operator and needs no founding session. If Rick prefers founding-admin identity at execution, it is a drop-in swap; note it in the Deploy Log.)
- **Input:** `{ slug, display_name, admin_email, contact_email?, contact_phone?, location?, branding? }`.
- **Slug-claim contract (§ 1.4).** Validate before insert; rely on the DB unique constraint as the final collision authority.
- **Steps (service-role; document the non-atomicity honestly):**
  1. Validate operator secret → else `401`.
  2. Validate `slug` against `^[a-z0-9][a-z0-9-]*[a-z0-9]$` (or single char) **and** the reserved-slug denylist (§ 1.4) → else `400`.
  3. Generate a cryptographically-random per-tenant webhook secret (for `register-customer`).
  4. `INSERT` the `tenants` row (service-role REST): `slug`, `display_name`, `plan='free'`, `branding` (input or `{}`), `settings` seeded with `{ "mailerlite_webhook_secret": "<generated>" }`. On `23505` (unique violation on `slug`) → `409 { error: 'slug_taken' }`. On `23514` (`tenants_slug_format_check`) → `400`.
  5. Create the first admin auth user via **GoTrue admin API** (`POST /auth/v1/admin/users`, `email_confirm:true`, no password) — same approach as `register-customer` / the canary procedure. **Do not** direct-INSERT `auth.users`.
  6. `INSERT` the admin `user_profiles` row: `id = <new auth user id>`, `full_name`, `is_admin=true`, `status='approved'` (re-derive the exact approved/active status value from the live `user_profiles` shape at execution), `tenant_id = <new tenant id>`.
  7. (Optional, recommend defer) generate a magic link + send an onboarding email to the admin. **Email branding is OUT of Phase 5 (F72)** — if an onboarding email is sent in 5.4, keep it minimal/neutral or defer it to 5.5. Recommended: 5.4 returns the magic-link/credentials to the operator and does **not** send a branded email.
  8. Return `{ tenant_id, admin_user_id, slug, webhook_secret }` so the operator can configure that tenant's MailerLite webhook URL.
  9. **Compensation (non-atomic):** an Edge Function cannot wrap GoTrue + PostgREST in one transaction. On a failure *after* a partial write, attempt best-effort cleanup in reverse FK order (delete the just-created profile, then the auth user, then the tenant row) and return `500`. Any residue is fully removable via the § 4.1 FK-ordered teardown (which S4 exercises). State this limitation in the function header and § 6.
- **F23 note:** `register-tenant` is a Deno Edge Function, not a SQL `SECURITY DEFINER` function, so the `SET search_path` hardening (parent § Out of Scope carve-out for *new* SQL functions) does not apply. 5.4 adds **no** new SQL function.

### 1.4 Slug-claim contract
- **Format:** lowercase DNS-safe — enforced by the DB `tenants_slug_format_check` (`slug ~ '^[a-z0-9][a-z0-9-]*[a-z0-9]$'` OR single `[a-z0-9]`); `register-tenant` pre-validates the same regex for a friendly `400` before hitting the DB.
- **Uniqueness:** `tenants_slug_key` (unique) is the authority — `register-tenant` catches `23505` → `409 slug_taken`. (No TOCTOU window: the constraint, not a pre-check SELECT, is the gate.)
- **Reserved denylist (function-level — not a DB constraint):** at minimum `www, app, api, admin, staging, prod, mail, ftp, blog, dev, test, canary, pulllist`, plus the founding slugs `raysandjudys` and `rjbookstop`. Reject with `400 slug_reserved`. (Re-confirm/extend the list at execution; document the final list in the function + § 13 contract note.)
- **Case/whitespace:** trim + lowercase the input before validation; reject if it then fails the regex.

### 1.5 Out-of-scope boundary: email branding (F72)
After the un-pin, a customer registered via a **non-founding** tenant's webhook lands (correctly) in that tenant's `user_profiles`, **but the `register-customer` email template is still hardcoded to "Ray & Judy's Book Stop" / PULLLIST founding copy** (lines ~193–256). **Multi-tenant email branding / per-tenant MailerSend identities are explicitly OUT of Phase 5** (parent § Out of Scope). 5.4 therefore un-pins the *data assignment* but leaves the *email copy* founding-branded. This is a real residual — **file F72** so it is findable when tenant 2's email needs are real (5.5 may act on it). Until then, the un-pin is correct for the founding tenant (its email *is* the right brand) and data-correct for any future tenant (right `tenant_id`), with the email copy as the documented gap.

### 1.6 No client/UI surface in 5.4
5.4 builds **no** public signup page and changes **no** `app.js` / `*.html` / `config.js` / `style.css`. The founding customer surface is byte-identical to 5.3. The tenant-creation entry point is the operator-gated `register-tenant` Edge Function, invoked by curl in 5.5's onboarding runbook (and in the S4 staging dry-run). This is what keeps the founding invariant trivially true and removes any `config.js` per-branch handling from the prod promotion.

---

## 2. In scope

1. **S0** — **F64 item 5 (hard prerequisite gate):** prod `preorders_user_id_fkey` → `user_profiles` NO ACTION (drop CASCADE + `auth.users` target). Confirm 0 blocking rows; verify `confdeltype='a'`. Resolve **F64 item 5**; close the parent Deferred-DDL Register row. **No S1+ work until green.**
2. **S1** — **Founding webhook-secret migration (staging):** write the founding tenant's existing `?secret=` value into `tenants.settings->>'mailerlite_webhook_secret'`; verify a service-role lookup by that secret returns the founding tenant. (Precedes S2 so the founding webhook never breaks.)
3. **S2** — **`register-customer` un-pin (F34 residual):** resolve `tenant_id` from the per-tenant webhook secret (DB lookup) instead of `FOUNDING_TENANT_ID`; header note → resolved; email template unchanged (**file F72**). Deploy to staging; verify founding webhook still routes to founding, bad/empty secret → 401. Feature branch → staging.
4. **S3** — **`register-tenant` Edge Function (new):** gated operator function (operator-secret; slug validation + reserved denylist; service-role tenant insert with seeded `settings`/`branding`; GoTrue admin user; admin `user_profiles` insert; best-effort compensation; returns tenant/admin/webhook-secret). Set `TENANT_PROVISION_SECRET` on staging; deploy. Feature branch → staging.
5. **S4** — **Staging canary dry-run + verified teardown (end-to-end):** create a canary tenant **through** `register-tenant`; configure its webhook secret; call `register-customer` with the canary secret → customer lands in the **canary** tenant (proves the un-pin); run full Playwright incl. tenant-isolation (F15/F20) with two tenants present; tear down via the § 4.1 FK-ordered procedure; **verify 0 rows** (canary gone, founding intact).
6. **S5** — **Staging verification consolidation:** negative-path specs (reserved-slug `400`, duplicate-slug `409`, malformed-slug `400`, missing operator-secret `401`, partial-failure compensation); founding register flow unchanged; full Playwright green.
7. **S6** — **Prod promotion (Rick's window):** set `TENANT_PROVISION_SECRET` on prod; migrate prod founding's webhook secret into prod `tenants.settings`; deploy `register-customer` (updated) + `register-tenant` (new) to prod; verify prod founding webhook still routes to founding (register-customer 200 → founding `tenant_id`); confirm `register-tenant` rejects without the operator secret (401); **optional** prod canary create→immediate-teardown smoke (verified 0 rows); founding write-smoke. **No real tenant 2 created here — that is 5.5.**
8. **S7** — **Closeout:** § 5 boxes ticked; § 13 statuses (F34 residual → resolved; F64 item 5 → resolved; F72 filed; new contracts); EF inventory → 9; parent row 5.4 → Complete + Deferred-DDL Register closed; `CLAUDE.md` pointer → 5.5; end-of-session status update.

## 3. Out of scope (stop and ask before touching)

- **Open public self-serve tenant signup page** — 5.4 builds only the gated operator Edge Function. A customer-facing signup screen (and its abuse hardening) is a larger surface; **file, don't build**.
- **Multi-tenant email branding / per-tenant MailerSend identities** — explicitly OUT of Phase 5 (parent § Out of Scope). `register-customer`'s email copy stays founding-branded (**F72**); `register-tenant` sends no branded email in 5.4 (returns credentials to the operator).
- **Subdomain / DNS provisioning for a new tenant** — onboarding (slug→subdomain wiring on Cloudflare) belongs to 5.5.
- **Wiring the Decline button to a GoTrue auth-user delete** (the F64 item 5 Option-A follow-on noted in § 13 / `bug_decline_action`) — a separate later sub-deploy; not 5.4.
- **`tenants` INSERT/DELETE RLS policy** — the absence is intentional (service-role-only creation). Do not add one.
- **Any `app.js` / `*.html` / `config.js` / `style.css` change** — 5.4 is backend-only. If a client change seems needed, **STOP and ask** (scope change; `config.js` is Rick's per-branch edit).
- **Any `import.js` / `import-staging.js` change.**
- **The other 7 Edge Functions** — their tenant resolution is already correct (F34 / Phase 4.6).

---

## 4. Runbook

Execution order: **S0 (prod FK gate) → S1 (founding secret migration, staging) → S2 (register-customer un-pin) → S3 (register-tenant) → S4 (canary dry-run + teardown) → S5 (negative-path verification) → S6 (prod promotion, Rick's window) → S7.** S0 gates everything. S1 precedes S2 so the founding webhook never breaks. S4 must complete (incl. verified teardown) before S6 — the teardown is proven before any path opens.

### S0 — F64 item 5 prod FK realignment (hard prerequisite gate)

1. **Re-confirm divergence (Claude, read-only):** from § 13 F64 item 5 + the live shape — staging `preorders_user_id_fkey` already `→ user_profiles` NO ACTION; prod still `→ auth.users` CASCADE. If a prior session already landed this (Deploy Log shows S0 green, or the prod constraint already targets `user_profiles`), record and skip to S1.
2. > **PAUSE → Rick (PROD SQL Editor `plgegklqtdjxeglvyjte`) — pre-capture + blocking-row check:**
   > ```sql
   > -- pre-capture current constraint (for rollback):
   > SELECT conname, confrelid::regclass AS references, confdeltype
   > FROM pg_constraint WHERE conname = 'preorders_user_id_fkey';
   > -- blocking rows: preorders whose user_id has no matching user_profiles.id
   > SELECT COUNT(*) AS blocking_rows
   > FROM public.preorders p
   > LEFT JOIN public.user_profiles up ON up.id = p.user_id
   > WHERE p.user_id IS NOT NULL AND up.id IS NULL;
   > ```
   > **Paste:** both. **Expected:** constraint references `auth.users`, `confdeltype = 'c'` (CASCADE); **`blocking_rows = 0`**. **STOP if** `blocking_rows > 0` (the ADD will fail — report the rows; do not force) or the constraint already targets `user_profiles` (already done — record + skip).
3. > **PAUSE → Rick (PROD SQL Editor) — run the realignment + verify:**
   > ```sql
   > ALTER TABLE public.preorders DROP CONSTRAINT preorders_user_id_fkey;
   > ALTER TABLE public.preorders ADD CONSTRAINT preorders_user_id_fkey
   >   FOREIGN KEY (user_id) REFERENCES public.user_profiles(id);
   > SELECT conname, confrelid::regclass AS references, confdeltype
   > FROM pg_constraint WHERE conname = 'preorders_user_id_fkey';
   > ```
   > **Paste:** the final SELECT. **Expected:** `references = user_profiles`, **`confdeltype = 'a'`** (NO ACTION). **STOP if** anything else.
4. **Record (Claude):** § 13 **F64 item 5 → resolved** (prod realigned to `user_profiles` NO ACTION; staging shape now canonical on both envs; pre-capture + verify in Deploy Log). Parent § Deferred-DDL Register F64-item-5 row → **closed**. Deploy Log row. Commit:
   ```
   docs: 5.4 S0 — F64 item 5 resolved (prod preorders_user_id_fkey → user_profiles NO ACTION); Deferred-DDL Register closed
   ```

### S1 — Founding webhook-secret migration (staging)

1. > **PAUSE → Rick (STAGING SQL Editor `puoaiyezsreowpwxzxhj`) — migrate + verify (Rick supplies the live secret value he already holds; it never enters chat/repo):**
   > ```sql
   > -- write the founding tenant's existing MailerLite webhook secret into its settings:
   > UPDATE public.tenants
   >   SET settings = settings || jsonb_build_object('mailerlite_webhook_secret', '<MAILERLITE_WEBHOOK_SECRET value Rick holds>')
   >   WHERE id = '72e29f67-39f7-42bc-a4d5-d6f992f9d790';
   > -- verify the lookup the function will use returns exactly the founding tenant:
   > SELECT id, slug FROM public.tenants
   >   WHERE settings->>'mailerlite_webhook_secret' = '<same value>';
   > ```
   > **Paste:** the SELECT (redact the secret). **Expected:** exactly one row — founding `72e29f67-…` / `raysandjudys`. **STOP if** zero or multiple rows (multiple ⇒ a secret collision; investigate before proceeding).
2. **Record (Claude):** § 13 — add a `register-customer` per-tenant-secret contract note (storage in `tenants.settings`, lookup semantics, founding migrated). Deploy Log row. Commit:
   ```
   docs: 5.4 S1 — founding webhook secret migrated to tenants.settings (staging); per-tenant-secret contract noted
   ```

### S2 — `register-customer` un-pin (F34 residual)

1. **Branch:** `git checkout -b feature/5.4-tenant-signup` off current `staging` (pulled).
2. **File-drift gate (Claude):** re-read `supabase/functions/register-customer/index.ts` from disk; confirm the `FOUNDING_TENANT_ID` env read (~46), the `?secret=` gate (~52–58), and the `tenant_id: FOUNDING_TENANT_ID` profile insert (~136–155) match before editing. **HALT on mismatch** — re-derive; do not force.
3. **Edit (Claude):**
   - Replace the `?secret=` gate's "compare to `MAILERLITE_WEBHOOK_SECRET`" logic with a **service-role tenant lookup by the provided secret**: `GET ${SUPABASE_URL}/rest/v1/tenants?settings->>mailerlite_webhook_secret=eq.<secret>&select=id,slug,display_name` (service-role headers). Empty/absent secret → `401`; no row → `401`. Capture the resolved `tenantId` (and `slug`/`display_name` if useful for logging).
   - Replace `tenant_id: FOUNDING_TENANT_ID` in the `user_profiles` insert with `tenant_id: tenantId`.
   - Remove the `FOUNDING_TENANT_ID`-as-tenant logic from the insert path (the env may stay declared but is no longer the tenant source). Update the header F34 note (~20–27): the function now resolves tenant from the per-tenant webhook secret; **F34 residual resolved**. Leave the group filter, GoTrue user creation, magic link, and **email template** unchanged (email branding deferred — F72).
4. **Verification (Claude):**
   - `Select-String -Path supabase/functions/register-customer/index.ts -Pattern "tenant_id: FOUNDING_TENANT_ID"` → **0**.
   - `Select-String -Path supabase/functions/register-customer/index.ts -Pattern "mailerlite_webhook_secret"` → **≥1** (the lookup).
   - `git diff` confined to the gate + insert + header comment.
5. > **PAUSE → Rick (deploy `register-customer` to STAGING + confirm JWT-verify OFF):** deploy the updated function to the staging project; confirm platform **Verify JWT: OFF** (public webhook — F68 pattern). **Paste:** deploy confirmation.
6. **Staging probes (Claude, `curl.exe` — `test-magic-link.ps1` pattern; `Invoke-RestMethod` mangles JSON):**
   - **Founding still routes to founding** — POST a minimal `subscriber.created`-shaped body to `.../functions/v1/register-customer?secret=<FOUNDING staging secret>` with a fresh `+alias` test email → `200`; verify (Rick or service-role SELECT) the new pending `user_profiles` row has `tenant_id = 72e29f67-…`. **Then delete the test auth user + profile** (GoTrue admin + SQL) so staging stays clean. *(MailerLite `subscriber.created` only fires for new emails — use a fresh `+alias`; see F69 operational note.)*
   - **Bad/empty secret rejected** — `?secret=` omitted → `401`; `?secret=not-a-real-secret` → `401`.
   - **HALT** if founding does not route to founding, or a bad secret is accepted.
7. **Commit + deploy to staging branch (Claude):**
   ```
   git add supabase/functions/register-customer/index.ts
   git commit -m "feat(register-customer): resolve tenant from per-tenant webhook secret, un-pin from founding (F34 residual, 5.4 S2)"
   git checkout staging
   git pull origin staging
   git merge --ff-only feature/5.4-tenant-signup
   git push origin staging
   ```
8. **Record (Claude):** § 13 **F34 → resolved** (residual un-pinned; per-tenant secret); **file F72** (register-customer email template still founding-branded — deferred; multi-tenant email branding OUT of Phase 5). Deploy Log row. Commit:
   ```
   docs: 5.4 S2 — F34 residual resolved (register-customer un-pinned); F72 filed (email branding deferral)
   ```

### S3 — `register-tenant` Edge Function (new, gated operator)

1. **Pattern read (Claude):** re-read an existing in-body-auth function (`create-paper-customer` or `invite-customer`) from disk for the house structure (CORS, env reads, service-role REST + GoTrue calls, error JSON). Re-derive the live `user_profiles` approved/active `status` value (do not assume).
2. **Create `supabase/functions/register-tenant/index.ts` (Claude)** per § 1.3:
   - Operator-secret gate (`TENANT_PROVISION_SECRET`) → `401` on mismatch/absent.
   - Input parse + slug validation (regex + reserved denylist § 1.4) → `400` on bad/reserved; trim+lowercase.
   - Generate per-tenant webhook secret (crypto-random).
   - Service-role `INSERT tenants` (slug, display_name, plan='free', branding, settings seeded with the webhook secret); map `23505`→`409 slug_taken`, `23514`→`400`.
   - GoTrue admin user create (email_confirm, no password) → first admin.
   - Service-role `INSERT user_profiles` (is_admin=true, status=<approved value>, tenant_id=new).
   - Best-effort compensation on partial failure (delete profile → auth user → tenant, reverse FK order) → `500`.
   - Return `{ tenant_id, admin_user_id, slug, webhook_secret }`.
   - Header comment: purpose, gate, non-atomicity caveat + pointer to the § 4.1 teardown, F23 note (Deno EF, not SQL DEFINER).
3. **Verification (Claude):** `Select-String` confirms the operator-secret gate, the reserved denylist, the `23505→409` map, and the GoTrue create are present; lint/type-check locally if the toolchain allows.
4. > **PAUSE → Rick (STAGING):** set `TENANT_PROVISION_SECRET` in the staging project's Edge-Function secrets (Rick generates the value — never in chat/repo); deploy `register-tenant`; confirm platform **Verify JWT: OFF** (the operator-secret in-body check is the gate, per the house pattern). **Paste:** deploy confirmation + "secret set".
5. **Staging gate probe (Claude, `curl.exe`):** POST to `.../functions/v1/register-tenant` **without** the operator secret → `401`; with a malformed slug → `400`; with a reserved slug (`admin`) → `400`. (Do **not** create a real tenant here — the end-to-end create is S4 with full teardown.) **HALT** if the gate accepts an unauthenticated call.
6. **Commit + deploy to staging branch (Claude):**
   ```
   git add supabase/functions/register-tenant/index.ts
   git commit -m "feat(register-tenant): gated operator EF — claim slug, create tenant + first admin + seeded settings (5.4 S3)"
   git checkout staging
   git pull origin staging
   git merge --ff-only feature/5.4-tenant-signup
   git push origin staging
   ```
7. **Record (Claude):** § 13 — `register-tenant` contract note (gate, slug rules, reserved denylist, seeded webhook secret, non-atomic compensation); § 1.x EF inventory → 9 functions. Deploy Log row. Commit:
   ```
   docs: 5.4 S3 — register-tenant gated operator EF added; EF inventory → 9; contract recorded
   ```

### S4 — Staging canary dry-run (end-to-end) + verified teardown

**This step proves both 5.4 features end-to-end AND that the FK-ordered teardown works — before any path opens.** Reuses `docs/phase-4.1-canary-procedure.md` (teardown delete order is load-bearing).

1. **Regenerate canary scratch (Claude):** new UUIDs per the § 4.1 Step 1 procedure into `phase-4.1-canary-uuids.txt` (local-only).
2. > **PAUSE → Rick (STAGING) — create the canary tenant *through* `register-tenant` (the dry-run's whole point):** curl `register-tenant` with the operator secret and `{ slug: 'canary54', display_name: 'Canary 5.4 Bookshop', admin_email: 'canary-admin@example.invalid' }`. **Paste:** the response. **Expected:** `200` with `{ tenant_id, admin_user_id, slug:'canary54', webhook_secret }`. Save all four to the scratch file. **STOP** on non-200 (and run compensation/teardown before retrying).
3. **Verify tagging (Claude / Rick SQL):** `SELECT id, slug, settings->>'mailerlite_webhook_secret' AS has_secret FROM tenants WHERE slug='canary54';` → one row, secret present. `SELECT full_name, is_admin, tenant_id FROM user_profiles WHERE tenant_id = '<canary tenant id>';` → one admin row, `tenant_id = canary`.
4. > **PAUSE → Rick (STAGING) — prove the un-pin routes to the *canary*, not founding:** call `register-customer?secret=<canary webhook_secret>` with a fresh `+alias` `subscriber.created` body → `200`. **Paste:** confirmation. **Claude/Rick verify:** the new pending `user_profiles` row has `tenant_id = <canary tenant id>` (**not** founding). This is the un-pin's headline proof.
5. **Tenant-isolation suite (Claude):** `.\run-smoke.ps1` — full Playwright incl. F15/F20 with two tenants (founding + canary) present → all green. Branding/signup must not widen any read or cross tenants.
6. > **PAUSE → Rick (STAGING SQL Editor + GoTrue) — FK-ordered teardown per § 4.1, then verify 0 rows:** run the § 4.1 Teardown block scoped to `<canary tenant id>` (usage_events → reservation_history → preorders → subscriptions → weekly_shipment → catalog → app_settings → user_profiles → auth.users [canary admin + canary customer ids] → tenants), then:
   > ```sql
   > SELECT COUNT(*) AS canary_tenant_rows FROM tenants WHERE id = '<canary tenant id>'::uuid;
   > SELECT COUNT(*) AS canary_profiles    FROM user_profiles WHERE tenant_id = '<canary tenant id>'::uuid;
   > SELECT tenant_id, COUNT(*) FROM user_profiles GROUP BY tenant_id;  -- founding intact
   > ```
   > **Paste:** all three. **Expected:** `canary_tenant_rows = 0`, `canary_profiles = 0`, founding tenant present and unchanged. **STOP if** any canary row survives (the teardown — a 5.5 dependency — is not proven until this is 0).
7. **Record (Claude):** Deploy Log row (canary created via `register-tenant`, un-pin routed customer to canary, isolation suite green, teardown → 0 rows verified). Doc commit:
   ```
   docs: 5.4 S4 — staging canary dry-run green (create→customer-route→isolation→teardown 0 rows)
   ```

### S5 — Negative-path verification (staging)

1. **`register-tenant` negative specs (Claude, `curl.exe` against staging — no standing tenant created; any accidental create is torn down per § 4.1):**
   - Missing/invalid operator secret → `401`.
   - Reserved slug (`admin`, `www`, `raysandjudys`) → `400 slug_reserved`.
   - Malformed slug (`Bad_Slug`, `-leadinghyphen`, `UPPER`) → `400`.
   - Duplicate slug (`raysandjudys` — already exists) → `409 slug_taken` (or `400` reserved, whichever guard fires first; document which).
   - Partial-failure compensation: simulate a profile-insert failure (e.g. a deliberately bad admin payload after a tenant insert) → `500` **and** verify (SELECT) no orphan tenant row survives.
2. **`register-customer` negative specs (Claude):** empty/bad `?secret=` → `401`; founding secret still → founding `tenant_id` (re-confirm S2 result; delete the test row after).
3. **Full Playwright (Claude):** `.\run-smoke.ps1` — all green incl. tenant-isolation (F15/F20). Founding register flow unchanged.
4. **Record (Claude):** Deploy Log row (negative-path matrix results). Doc commit:
   ```
   docs: 5.4 S5 — negative-path matrix green (reserved/duplicate/malformed slug, operator-gate, compensation); founding flow unchanged
   ```

### S6 — Prod promotion (Rick's chosen window)

**Order is load-bearing: the prod founding webhook secret must be in `tenants.settings`, and `TENANT_PROVISION_SECRET` must be set on prod, before the un-pinned `register-customer` deploys — or the founding webhook breaks.** No `config.js` / app.js change in 5.4, so no F59 diff assertion or `config.js` checkout is needed; the prod promotion is EF redeploy + secret/data setup only.

1. > **PAUSE → Rick (PROD SQL Editor `plgegklqtdjxeglvyjte`) — migrate prod founding's webhook secret (before the un-pinned deploy):**
   > ```sql
   > UPDATE public.tenants
   >   SET settings = settings || jsonb_build_object('mailerlite_webhook_secret', '<PROD MAILERLITE_WEBHOOK_SECRET value Rick holds>')
   >   WHERE id = '20941129-c35a-476d-ae21-44b8f77af89c';
   > SELECT id, slug FROM public.tenants
   >   WHERE settings->>'mailerlite_webhook_secret' = '<same value>';
   > ```
   > **Paste:** the SELECT (redact secret). **Expected:** one row — prod founding `20941129-…` / `rjbookstop`. **STOP if** zero/multiple. *(Use the **prod** webhook secret — rotated 2026-06-11 per F69, the value Rick holds, distinct from staging's.)*
2. > **PAUSE → Rick (PROD) — set `TENANT_PROVISION_SECRET` on the prod project** (Rick's value; may differ from staging). **Paste:** "prod operator secret set".
3. > **PAUSE → Rick (PROD) — deploy both functions to the prod project + confirm JWT-verify OFF:** deploy `register-customer` (updated) and `register-tenant` (new); confirm **Verify JWT: OFF** on both (public webhook / operator-secret-in-body). **Paste:** deploy confirmations.
4. **Prod verification (Claude + Rick, `curl.exe` with prod values):**
   - **Founding still routes to founding** — POST a fresh `+alias` `subscriber.created` body to prod `register-customer?secret=<PROD founding secret>` → `200`; verify the new pending `user_profiles` row has `tenant_id = 20941129-…`; **delete the test user + profile** after. **HALT** if it does not route to founding.
   - **`register-tenant` gated** — POST without the operator secret → `401`; malformed slug → `400`. (Do **not** create a standing prod tenant — that is 5.5.)
   - **(Optional, recommended) prod create→immediate-teardown smoke:** with the prod operator secret, `register-tenant` a throwaway `canary54p` tenant → `200`; immediately run the § 4.1 teardown on prod scoped to it; verify `canary_tenant_rows = 0`. This is the only way to prove prod provisioning end-to-end before 5.5; it writes + removes within the window, verified 0. **If Rick prefers zero prod tenant writes in 5.4, skip — note the skip honestly in the Deploy Log** (5.5 then carries the first real prod create).
5. **Founding write-smoke (Rick):** reserve one item on `pulllist.app` as a test customer → row lands in prod `preorders` with founding `tenant_id` → cancel it. (Regression guard — confirms the S0 FK realignment + EF changes broke nothing on the founding write path.)
6. **Record (Claude):** Deploy Log row (prod founding secret migrated + verified, operator secret set, both EFs deployed, founding routes to founding, register-tenant gated, optional prod canary teardown result or honest skip, write-smoke). Doc commit:
   ```
   docs: 5.4 S6 — prod promotion (register-customer un-pin + register-tenant) verified; founding write-smoke clean
   ```

### S7 — Closeout (run once, when every § 5 box is ticked)

1. Tick the § 5 boxes with inline result notes (5.3 pattern).
2. This file: Status line → **Complete** + date; Last-updated line.
3. Parent (`phase-5-second-tenant-onboarding.md`): row 5.4 → **Complete** + date; row 5.5 → **Planning** only when its plan file exists (next session writes it); § Deferred-DDL Register F64-item-5 row → closed (S0); § Carry-Forward F34 row → addressed; § Phase Completion Criteria `register-customer no longer hard-pinned` box tickable.
4. `docs/technical-reference.md`: § 13 **F34 → resolved** (residual), **F64 item 5 → resolved** (S0 DDL), **F72 filed**; `register-customer` per-tenant-secret + `register-tenant` contract notes; § 1.x EF inventory → 9 (`register-tenant` added); § 4.1 tenants note (per-tenant webhook secret in `settings`).
5. `CLAUDE.md` § Current Migration Phase: active sub-deploy → **5.5 (plan not yet written)**; last-completed → 5.4; § Edge Functions → 9 functions (add `register-tenant`; `register-customer` un-pinned, resolves tenant from per-tenant webhook secret); § Known Out-of-Scope "Self-service tenant signup" line → Complete (5.4); open-findings line updated (F34 residual + F64 item 5 resolved; F72 filed; next free ID **F73**).
6. Commit:
   ```
   docs: close Phase 5.4 (tenant signup); advance pointer to 5.5 planning
   ```
7. End-of-session status update per `CLAUDE.md` § Anti-Drift Rules (changed / verified / left / filed / new IDs).

---

## 5. Completion criteria (all must be checked before parent row 5.4 → Complete)

- [ ] **S0:** prod `preorders_user_id_fkey` references `public.user_profiles(id)` with `confdeltype='a'` (NO ACTION) — `auth.users` target + CASCADE removed; pre-flight confirmed 0 blocking rows; **F64 item 5 resolved**; parent Deferred-DDL Register row closed. (Gate — landed before any S1+ work.)
- [ ] **S1:** founding tenant's webhook secret lives in `tenants.settings->>'mailerlite_webhook_secret'` on staging; a service-role lookup by that secret returns exactly the founding tenant (one row).
- [ ] **S2 (F34 residual):** `register-customer` resolves `tenant_id` from the per-tenant webhook secret (DB lookup) — `Select-String "tenant_id: FOUNDING_TENANT_ID"` → 0; founding webhook still routes a new customer to the founding tenant on staging; empty/bad secret → 401; **F34 resolved**, **F72 filed** (email branding deferral); email template unchanged.
- [ ] **S3:** `register-tenant` deployed on staging behind `TENANT_PROVISION_SECRET`; unauthenticated call → 401; reserved/malformed slug → 400; creates tenant + first admin + seeded `settings`/`branding` via service-role; **EF inventory → 9**.
- [ ] **S4:** a canary tenant created **through** `register-tenant` on staging; `register-customer` with the canary secret routes a customer to the **canary** tenant (un-pin proof); full Playwright incl. tenant-isolation (F15/F20) green with two tenants present; FK-ordered teardown executed; **`canary_tenant_rows = 0` and founding intact** verified by SELECT.
- [ ] **S5:** negative-path matrix green (operator-gate 401; reserved-slug 400; duplicate-slug 409; malformed-slug 400; partial-failure compensation leaves no orphan tenant); founding register flow unchanged; full Playwright green.
- [ ] **S6:** prod founding webhook secret migrated to `tenants.settings` and verified (one row, prod founding UUID) **before** the un-pinned deploy; `TENANT_PROVISION_SECRET` set on prod; both EFs deployed (JWT-verify OFF); prod founding webhook still routes to founding; `register-tenant` rejects without the operator secret; optional prod canary create→teardown verified 0 (or honest skip noted); founding write-smoke passed.
- [ ] **Founding-tenant behavior unchanged** (parent invariant): full Playwright incl. tenant-isolation green at the S2/S3/S4/S5 staging gates and the S6 prod write-smoke; no `app.js`/`*.html`/`config.js` change; founding customer surface byte-identical to 5.3.
- [ ] **Teardown proven before the flow opens** (parent rollback row 5.4): the § 4.1 FK-ordered teardown exercised in S4 with a verifying 0-row SELECT.
- [ ] § 13 updated (**F34 → resolved**, **F64 item 5 → resolved**, **F72 filed**, `register-customer` + `register-tenant` contracts, EF inventory → 9); Deploy Log complete (one row per executed step); all doc changes committed to `staging`; parent row 5.4 → **Complete** + date; `CLAUDE.md` pointer advanced to 5.5 planning.

---

## 6. Rollback (per step; pre-captures taken before every change)

- **S0 (prod FK realignment):** re-add the prior constraint from the pre-capture: `ALTER TABLE public.preorders DROP CONSTRAINT preorders_user_id_fkey; ALTER TABLE public.preorders ADD CONSTRAINT preorders_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;`. (Unlikely — this only aligns prod to the already-canonical staging shape; the decision is made.)
- **S1 (founding secret migration):** `UPDATE tenants SET settings = settings - 'mailerlite_webhook_secret' WHERE id = '72e29f67-…';`. Harmless to leave in place even on a feature rollback (the old function ignored it).
- **S2 (register-customer un-pin):** redeploy the prior `register-customer` source (revert the `feature/5.4-tenant-signup` S2 commit + redeploy). The founding secret in `tenants.settings` (S1) is harmless to the old pinned function. **Pair the redeploy with leaving S1 in place** — the old function reads `FOUNDING_TENANT_ID`, unaffected.
- **S3 (register-tenant):** revert the S3 commit + remove the deployed function (or leave it deployed but unreachable — it is gated by `TENANT_PROVISION_SECRET`, which can be unset to disable it). Additive; nothing else depends on it.
- **S4 (canary dry-run):** the canary is torn down in-step (verified 0 rows). No standing change. If a sitting ends mid-dry-run, run the § 4.1 teardown before closing and record it.
- **S5:** verification only — any accidental tenant create is torn down per § 4.1; no standing change.
- **S6 (prod):** redeploy the prior prod EF sources; unset `TENANT_PROVISION_SECRET` to disable `register-tenant`; the prod founding secret in `tenants.settings` is independent and stays. The optional prod canary is torn down in-step. The S0 FK realignment is a one-time alignment and is **not** rolled back with the feature (it is correct independent of 5.4).
- **Customer-data note:** 5.4 creates no real second tenant (only the in-step-torn-down canary). Tenant 2 with real customer writes is 5.5 — the parent's one-way-after-real-writes rollback tier does **not** apply within 5.4.

---

## 7. References

- Decision (F64 item 5 placement): Rick, 5.4 planning 2026-06-15 — **5.4 S0 pre-flight gate** (single prod-DDL block; S1+ blocked until green). DDL + decision in § 13 F64 item 5; parent § Deferred-DDL Register.
- Decision (register-customer un-pin model): Rick, 5.4 planning 2026-06-15 — **per-tenant webhook secret in the tenant row** (`tenants.settings`); the incoming `?secret=` both authenticates and selects the tenant; no cross-tenant injection; founding secret migrated before the un-pinned deploy.
- Decision (tenant-registration surface): Rick, 5.4 planning 2026-06-15 — **gated operator Edge Function** (`register-tenant`, operator-secret); no open public self-serve page in 5.4 (out of scope; file if raised).
- Decision (5.4 depth): Rick, 5.4 planning 2026-06-15 — **flow + staging canary dry-run + verified teardown**; real tenant 2 onboarded in 5.5.
- Parent: `docs/phase-5-second-tenant-onboarding.md` (row 5.4; § In Scope 5.4; § Deferred-DDL Register; § Approach Decisions "signup before onboarding, onboarding gated"; § Out of Scope email branding; § Rollback row 5.4; founding-invariant completion criterion).
- Shape mirror: `docs/phase-5.3-per-tenant-branding.md` (execution model, PAUSE→Rick pause-block format, Deploy-Log resume protocol, per-step commit discipline, completion-criteria style).
- Canary spin-up + FK-ordered teardown (reused S4; reused again by 5.5): `docs/phase-4.1-canary-procedure.md`.
- Findings: `docs/technical-reference.md` § 13 — **F34** (`register-customer` residual founding pin — this sub-deploy resolves it), **F64 item 5** (prod FK realignment — S0), the `resolve_tenant_by_slug` contract note; § 1.x EF inventory + off-plus-in-body-auth model; § 4.1 `tenants` schema (slug format check, service-role-only creation). **Next free ID at planning: F72** (5.4 files it for the email-branding deferral; further defects from F73).
- Code (re-read from disk at execution): `supabase/functions/register-customer/index.ts` (header F34 note ~20–27; `?secret=` gate ~52–58; `FOUNDING_TENANT_ID` insert ~136–155; email template ~193–256); an existing in-body-auth function for the house pattern (`create-paper-customer` / `invite-customer`).
- Projects: staging `puoaiyezsreowpwxzxhj`, prod `plgegklqtdjxeglvyjte`. Founding tenant UUID (staging) `72e29f67-39f7-42bc-a4d5-d6f992f9d790`; prod founding `20941129-c35a-476d-ae21-44b8f77af89c` / slug `rjbookstop` (also in `catalogs\scripts\phase-4-prod-tenant-uuid.txt`, local-only).
- Curl pattern for tenant-aware Supabase calls: `test-magic-link.ps1` (`curl.exe --data-binary @file`; `Invoke-RestMethod` mangles JSON — `CLAUDE.md` § Known Issues).
- **Carry-forward to 5.5:** the `register-tenant` function + the per-tenant webhook-secret mechanism are 5.5's onboarding tools; the § 4.1 teardown (proven in S4) is 5.5's rollback-prep; the email-branding gap (**F72**) may be acted on when tenant 2's email needs are real.

---

## 8. Deploy log (filled during execution)

| Date | Step | Result | Notes |
|---|---|---|---|
| 2026-06-16 | S0 | Green | Prod `preorders_user_id_fkey` realigned → `user_profiles` NO ACTION. Pre-flight: `blocking_rows=0`, prior shape confirmed `auth.users`/CASCADE. Post-verify: `references=user_profiles`, `confdeltype='a'`. F64 item 5 resolved; Deferred-DDL Register closed. |
| | S1 | | |
| | S2 | | |
| | S3 | | |
| | S4 | | |
| | S5 | | |
| | S6 | | |
| | S7 | | |

---

**Last updated:** 2026-06-15 (plan written — 5.4 Planning; not yet executed)
