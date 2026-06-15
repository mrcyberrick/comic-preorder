# Phase 5.2 — Slug→id Routing RPC

**Status:** **Planning** — plan written 2026-06-15; not yet executed.
**Parent plan:** `docs/phase-5-second-tenant-onboarding.md` (sub-deploy row 5.2)
**Predecessor:** Phase 5.1 — Hosting migration → Cloudflare Pages — **Complete 2026-06-14** (prod live at `pulllist.app`; staging at `staging.pulllist.pages.dev`).
**Branches:** Database + EF + doc changes do their work via the SQL Editor / Supabase dashboard (doc commits → `staging` directly). The `app.js` changes ride `feature/5.2-slug-rpc` off `staging` → `--ff-only` merge → staging smoke → prod promotion PR per `CLAUDE.md` § Standard Deployment Workflow (F59 diff assertion + `config.js` checkout + post-deploy write-smoke). The F67 EF work (§ S5, **adjacent**) follows the Edge-Function deploy procedure, **staging project first, prod project after staging verify**.
**Execution model:** **CLI-orchestrated, Rick-in-the-loop.** A Claude Code CLI session runs this file top to bottom. It executes every repo / doc / local-script / Playwright / `curl.exe` step itself, and **pauses at every database step (staging *and* prod), every Supabase dashboard action (RPC create via SQL Editor, EF secrets, EF deploy), and the prod promotion merge** — handing Rick the exact SQL / clicks / values and **waiting for pasted results before continuing**. **Self-contained — no chat context required.**
**Rollback complexity:** Easy (parent table) — the RPC is additive; subdomain parsing is additive and defaults to the founding tenant; `TENANT_SLUG_MAP` removal is the **last** code commit and individually revertible; the staging index drop (F14) is re-creatable; F67 EF changes revert to the captured constants. No customer-write dependency anywhere in 5.2.

> **Steps Claude never runs itself.** (1) Any Supabase **SQL Editor** statement — staging *or* prod (RPC create, index drop). (2) Any Supabase **dashboard** action — Edge Functions → Secrets, Edge Functions → Deploy, JWT settings. (3) The S7 prod promotion merge/PR approval — Claude prepares it; Rick reviews and merges. Each appears below as a **`PAUSE → Rick … → paste result → match expected → continue / STOP`** block. Claude prepares the exact inputs, the expected result, and the stop condition around every pause.

> **5.2 may span multiple sittings.** S1–S3 (RPC on staging + app.js wiring + verification) fit one sitting; S5 (F67) needs a staging-then-prod EF-deploy window; S7 (prod promotion incl. the prod RPC create) waits for Rick's chosen window. The durable state is the **Deploy Log (§ 8)**: every session appends one row per completed step. A resuming session reads the log, re-verifies the last recorded step against live state (a recorded RPC create is re-verified by calling it before trusting it), and continues from the next unexecuted step. Every doc edit is committed before the session ends.

> **Founding-tenant invariant (parent completion criterion for every 5.x sub-deploy).** 5.2 changes the tenant-resolution path — the single most behavior-sensitive surface in the app. The hard invariant: **on `pulllist.app` (apex), `staging.pulllist.pages.dev`, `pulllist.pages.dev`, `localhost`, and any `*.pages.dev` preview, resolution lands on the founding tenant, identically to today.** Every gate runs the full Playwright suite including the tenant-isolation specs (F15/F20). A subdomain-parser bug that misreads `staging` as a tenant slug would misroute the founding tenant — § 1.3 specifies the non-tenant-host allowlist that prevents exactly this, and S3 verifies it.

---

## 0. Pre-flight (run at the top of every 5.2 session; halt on any mismatch)

### 0.1 Read before doing anything
- `CLAUDE.md` in full; confirm § Current Migration Phase active sub-deploy = **5.2**.
- `docs/phase-5-second-tenant-onboarding.md` — Sub-Deploys row 5.2, § Approach Decisions ("hosting before subdomain routing"; subdomain resolution waits for 5.1 — now satisfied), § Deferred-DDL Register (F64 item 8 disposition lands here; **F64 item 5 is NOT 5.2 scope** — see § 3), § Out of Scope (the new RPC is a SECURITY DEFINER function and **must** carry the `SET search_path` hardening per the F23 carve-out).
- This file in full — including the Deploy Log (§ 8): if any rows exist, this is a resume session.
- `docs/technical-reference.md` § 13 — F14, F64 (item 8), F67. Also the `tenants` table definition (§ schema, lines ~280–294 at planning) and the indexes/grants prose (~1034–1041).
- `app.js` `TenantContext` block (lines ~12–125 at planning) and `initNav()` `await TenantContext.resolve()` (line ~190).

### 0.2 Gates (halt if any fail)
- `git rev-parse --abbrev-ref HEAD` → `staging`; `git status` → clean (the known-stray untracked `docs/status-slide.html` is acceptable; anything else, stop and ask).
- `git pull origin staging` → up to date (or fast-forward) before any edit.
- `docs/technical-reference.md` § 13: confirm the highest filed finding ID (**F70** at planning time; **next free = F71**). New defects discovered during 5.2 are filed from F71 — never guessed or reused.
- **Re-verify the planning-time audits in § 1 against the current tree and live DBs** (anti-drift: never trust a prior session's grep). In particular: re-read the `TenantContext` block from disk before any `app.js` edit (the line numbers in § 1.1 are planning-time positions); re-query the live `tenants` indexes (§ 1.2) before the F14 drop; re-grep the EF URL constants (§ 1.4) before touching F67.

### 0.3 Commit discipline
- Each S-step's doc update (RPC disposition, F14/F64-8 resolution, F67 resolution, deploy-log row) is its own doc-only commit to `staging` with the finding ID(s) in the message — exact messages inline.
- The `app.js` changes ride `feature/5.2-slug-rpc`, never `staging` directly. **`TENANT_SLUG_MAP` removal is its own final code commit (S6)** so it is independently revertible (parent § Rollback Notes).
- F67 EF source changes are their own commits with `F67` in the message; staging-deploy and prod-deploy are recorded as distinct Deploy Log rows.
- Push `origin staging` after each commit; the Deploy Log row lands in the same commit as the step it records.

### 0.4 Files / surfaces touched by this sub-deploy

| File / target | Change | Branch / actor |
|---|---|---|
| Staging DB (`public` schema) | `CREATE FUNCTION resolve_tenant_by_slug` (S1); `DROP INDEX idx_tenants_slug` (S4, F14) | Rick, staging SQL Editor |
| Production DB (`public` schema) | `CREATE FUNCTION resolve_tenant_by_slug` (S7, before app.js prod promotion); **no index DDL** (F64 item 8 dispositioned no-op — see § 1.2) | Rick, prod SQL Editor |
| `app.js` | `TenantContext`: anon slug lookups → RPC; new `tenantSlugFromHostname()` subdomain resolver; `TENANT_SLUG_MAP` removal (S6) | `feature/5.2-slug-rpc` |
| Supabase Edge Functions (both projects) | `APP_BASE_URL` secret added; 5 hardcoded URL constants → `Deno.env.get('APP_BASE_URL')` (S5, **F67, adjacent**) | Rick (secrets + deploy), Claude (source edits) |
| Playwright suite (local-only, never committed) | New/updated spec for subdomain + RPC resolution; existing tenant-isolation specs unchanged in intent | Claude, direct edit |
| `docs/technical-reference.md` § 13 | F14 → resolved; F64 item 8 → dispositioned; F67 → resolved; `tenants` index prose updated | `staging` (doc-only) |
| `docs/phase-5-second-tenant-onboarding.md` | Row 5.2 → Complete; § Deferred-DDL Register F64-8 row closed | `staging` (doc-only) |
| `CLAUDE.md` | § Current Migration Phase pointer advance; § Known Out-of-Scope `TENANT_SLUG_MAP` line removal; open-findings line updated | `staging` (doc-only) |

**Not touched:** `config.js`, `import.js` / `import-staging.js`, `style.css`, the `*.html` files (resolution is all in `app.js`), `tenants.branding` / `tenants.settings` rendering (sub-deploy 5.3), `register-customer` founding-tenant pin (sub-deploy 5.4), the F64 item 5 FK realignment (Deferred-DDL Register; owner pre-5.4 — **§ 3**).

---

## 1. Planning-time audit results (2026-06-15) — re-verify at execution

### 1.1 The hardcoded mapping and its only callers
`app.js` `TenantContext` (planning-time lines):

- `FOUNDING_TENANT` const (lines ~28–32): `{ id: '72e29f67-…', slug: 'raysandjudys', display_name: "Ray & Judy's Book Stop" }`.
- `TENANT_SLUG_MAP` const (lines ~34–37): `{ raysandjudys: FOUNDING_TENANT }` — the object 5.2 replaces.
- `TenantContext.resolve()` (lines ~43–105) has four resolution branches:
  1. **Authenticated profile** (lines ~46–72): `db.from('user_profiles').select('tenant_id')` → `db.from('tenants').select('id, slug, display_name').eq('id', …)`. **Uses RLS, not the map — unchanged by 5.2.** (Authenticated users can SELECT their own tenant via the `users read own tenant` policy.)
  2. **`?t=<slug>` query** (lines ~74–89): looks up `TENANT_SLUG_MAP[fromQuery]`. **→ RPC.**
  3. **sessionStorage** (lines ~90–96): re-derives from `TENANT_SLUG_MAP[fromStorage]`. **→ RPC (store the slug, re-resolve).**
  4. **Founding default** (lines ~101–104). **Unchanged.**

`TENANT_SLUG_MAP` is referenced **only** inside `resolve()` (branches 2 and 3). Confirm at execution: `Select-String -Path app.js -Pattern "TENANT_SLUG_MAP"` → exactly the definition + the two read sites (3 lines total at planning). If more, re-scope before editing.

### 1.2 The index contradiction — F14 vs F64 item 8 (resolved: no-op F64-8, drop staging index)
`tenants.slug` is **UNIQUE** on both environments (`tenants_slug_key`, the constraint's backing btree). Staging additionally carries a **redundant non-unique** `idx_tenants_slug` on the same column (F14: "the non-unique one is dead — it cannot serve a query better than the unique constraint's backing index"). The Phase-4 completion audit filed F64 item 8 as "add `idx_tenants_slug` to prod (slug routing will want it)" — but the slug→id RPC's lookup is a single-row equality (`WHERE slug = $1`), which `tenants_slug_key` already serves optimally on **both** envs. **F64 item 8's premise is therefore unfounded: no second index is needed.**

**Disposition (Rick, planning 2026-06-15 — the index choice has no security dimension; minimize surface):**
- **F64 item 8 → no-op.** Do **not** add `idx_tenants_slug` to prod. Record in § 13 + the parent § Deferred-DDL Register that the unique constraint already serves the RPC.
- **F14 → resolve by dropping the redundant index on STAGING** (`DROP INDEX idx_tenants_slug;`) for downward structural parity (prod never had it; staging now matches). Trivial, additive-inverse, re-creatable.

> **DDL flagged for Rick-in-the-loop:** S4 = one `DROP INDEX` on **staging only**. **No prod index DDL in 5.2.** S1 (RPC create) and S7 (prod RPC create) are the other two Rick-in-the-loop SQL steps.

Re-verify at execution before the drop:
```sql
SELECT indexname, indexdef FROM pg_indexes
WHERE schemaname = 'public' AND tablename = 'tenants' ORDER BY indexname;
```
Expected staging: `tenants_pkey`, `tenants_slug_key`, `idx_tenants_slug`. Expected prod: `tenants_pkey`, `tenants_slug_key` (no `idx_tenants_slug`). If prod unexpectedly has `idx_tenants_slug`, STOP — the divergence premise changed.

### 1.3 Subdomain resolution — host model and the non-tenant allowlist
Post-5.1 hosting topology (5.1 Deploy Log): prod apex `pulllist.app`; staging preview `staging.pulllist.pages.dev`; prod Pages URL `pulllist.pages.dev`; CF preview deploys `*.pages.dev`. A real second tenant's subdomain (`<slug>.pulllist.app`) does not exist until 5.5 — **5.2 ships and unit-tests the parser; it does not provision a live second subdomain** (that is 5.5 + CF wildcard/custom-domain infra).

The parser must treat the founding/infra hosts as **non-tenant** (→ founding default) and only read a slug from a true subdomain of the production apex:

- **Non-tenant hosts (→ founding/default):** `pulllist.app`, `www.pulllist.app`, `pulllist.pages.dev`, `staging.pulllist.pages.dev`, `localhost`, `127.0.0.1`, and **any** host ending in `.pages.dev` (all CF previews).
- **Tenant host:** `<label>.pulllist.app` where `<label>` is a single DNS label, not `www`, not empty → `<label>` is the candidate slug, resolved via the RPC (the RPC, not the parser, decides whether the slug is real).

This guards the founding invariant: `staging.pulllist.pages.dev`'s first label `staging` must **never** be read as a tenant slug — the `.pages.dev` rule catches it before any label extraction.

### 1.4 F67 — Edge Function hardcoded app URLs (adjacent; full detail in § 13 F67)
Five functions embed hardcoded app URLs; owner assigned at 5.1 S1 = "5.2-adjacent housekeeping commit; must land before 5.5." Folded into this plan as **S5**, kept distinct from the core RPC work (separate branch-free EF deploy, separate commits). The fix (from § 13 F67): add an `APP_BASE_URL` Edge-Function secret per project (staging `https://staging.pulllist.pages.dev`, prod `https://pulllist.app`) and replace all five constants/inline values with `Deno.env.get('APP_BASE_URL')`. Re-verify the five sites against deployed source at execution (5.1 S1 captured them; deployed copies may have changed):

| Function | Lines (planning) | Current value |
|---|---|---|
| `approve-customer` | `index.ts:13–15` | `STAGING_BASE='https://mrcyberrick.github.io/comic-preorder-staging'` |
| `register-customer` | `index.ts:29–31` | same |
| `invite-customer` | `index.ts:1–3` | same |
| `reset-password` | `index.ts:1–2` | `STAGING_BASE='https://mrcyberrick.us/comic-preorder-staging'` (anomalous host) |
| `notify-customers` | `index.ts:163` | `https://mrcyberrick.us/comic-preorder/catalog.html` (inline) |

S5 resolving F67 also clears three **pre-existing prod defects** (approve/register/invite magic links pointing at the staging Supabase project; reset-password 404) — noted but not the driver; the driver is removing the GH-Pages teardown blocker before 5.5.

### 1.5 The RPC contract (security-load-bearing — the part that actually matters)
Anon cannot `SELECT` from `tenants` (RLS: only `users read own tenant`). The RPC is the controlled anon read. Contract:

```sql
CREATE OR REPLACE FUNCTION public.resolve_tenant_by_slug(p_slug text)
  RETURNS TABLE (id uuid, slug text, display_name text)
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path = public, pg_temp
  AS $$
    SELECT t.id, t.slug, t.display_name
    FROM public.tenants t
    WHERE t.slug = p_slug;
  $$;

REVOKE ALL ON FUNCTION public.resolve_tenant_by_slug(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_tenant_by_slug(text) TO anon, authenticated;
```

Security properties (each verified at S1):
- **Minimal projection.** Returns only `id, slug, display_name`. **Never** `branding` / `settings` jsonb (config-leak surface; also 5.3's job), `created_at`, or any other column.
- **`SET search_path = public, pg_temp`** — the SECURITY DEFINER hardening the parent § Out of Scope mandates for new functions (F23 carve-out).
- **`STABLE`**, read-only; no write path.
- **Explicit grants** — `REVOKE ALL FROM PUBLIC` then `GRANT EXECUTE TO anon, authenticated` (mirrors the F64-item-1 `admin_preorders` grant-tightening; counters Supabase's default-privilege auto-grant).
- **Exact equality only** — no `LIKE`/`ILIKE`/regex, so no enumeration oracle beyond what is already public (a tenant's existence is observable from its subdomain; `display_name` is public branding).
- **Exposing the tenant `id` (UUID) to anon is safe.** Writes are gated by `WITH CHECK (tenant_id = current_tenant_id())`, where `current_tenant_id()` derives from the authenticated profile — never from a client-supplied id. For anon, `current_tenant_id()` is NULL → all writes blocked. Knowing a tenant UUID grants no write capability. (Record this rationale in § 13 so it is not re-litigated.)
- **No status filter needed today** — `tenants` has no `status`/`active` column at planning. If one is added later, the RPC must filter to active tenants; noted as a forward-consideration in § 13, not built now.

---

## 2. In scope

1. **S1** — Create `resolve_tenant_by_slug` on **staging**; verify the security contract (minimal columns, anon EXECUTE works, branding/settings absent, unknown slug → empty). RPC **design/disposition gate** (contract confirmed). Resolve nothing yet; record the contract in § 13.
2. **S2** — `app.js`: replace the two `TENANT_SLUG_MAP` anon read sites with RPC calls; add `tenantSlugFromHostname()` and wire subdomain resolution into `resolve()`. **`TENANT_SLUG_MAP` retained as a synchronous fallback through S2** (removed in S6). Feature branch → staging deploy → full Playwright.
3. **S3** — Subdomain + founding-invariant verification: parser unit coverage; `pulllist.app` / `staging.pulllist.pages.dev` / `*.pages.dev` all resolve to founding; `?t=raysandjudys` and a known-bad `?t=` slug behave correctly via the RPC. Full Playwright incl. tenant-isolation specs.
4. **S4** — Index disposition (DDL flagged): **staging** `DROP INDEX idx_tenants_slug` (resolve **F14**); **F64 item 8 → no-op** (no prod index). Verify live index set on both envs.
5. **S5** — **F67 (adjacent):** `APP_BASE_URL` secret + five constants → `Deno.env.get('APP_BASE_URL')`; staging EF deploy → verify → prod EF deploy → verify. Resolve **F67**.
6. **S6** — Remove `TENANT_SLUG_MAP` from `app.js` (final code commit on the feature branch); full Playwright; confirm only the founding default + RPC remain.
7. **S7** — Prod promotion: create `resolve_tenant_by_slug` on **prod** (before app.js lands), promote the `app.js` changes via the standard workflow (F59 diff assertion, `config.js` checkout), post-deploy write-smoke + founding-resolution check.
8. **S8** — Closeout: § 5 boxes ticked, § 13 statuses, parent row 5.2 → Complete + Deferred-DDL Register F64-8 closed, `CLAUDE.md` pointer → 5.3 planning, end-of-session status update.

## 3. Out of scope (stop and ask before touching)

- **Per-tenant branding rendering** (`tenants.branding` / `settings` jsonb) — sub-deploy 5.3. The RPC deliberately does **not** return these columns.
- **`register-customer` founding-tenant un-pin** (F34 residual) — sub-deploy 5.4.
- **F64 item 5 DDL** (`preorders_user_id_fkey` → `user_profiles` NO ACTION on prod) — Deferred-DDL Register; owner was "5.1-adjacent housekeeping, must land before 5.4." It did **not** land in 5.1 and is **not** 5.2's named scope. **Flag to Rick:** it still needs a home before 5.4 (5.3 or an explicit housekeeping commit). Do not absorb it into 5.2 without explicit sign-off.
- **Provisioning a live second subdomain / CF wildcard or custom-domain setup** — 5.5. 5.2 ships the parser and tests it against the founding hosts only.
- **Adding a `tenants.status`/active concept** — not built now; noted as a forward-consideration in the RPC (§ 1.5).
- **Any `*.html` / `style.css` / `config.js` / import-script change.**

---

## 4. Runbook

Execution order: **S1 → S2 → S3 (one sitting if possible) → S4 (staging SQL, same or next sitting) → S5 (F67 EF deploy window, staging then prod) → S6 (final map removal) → S7 (prod promotion, Rick's window) → S8.** S5 (F67) is independent of S2–S4/S6 and may run in its own window; it must complete before 5.5 regardless. The prod RPC (S7 step 1) must exist **before** the app.js prod promotion (S7 step 2) or anon resolution on prod would fall through to the founding default for any `?t=`/subdomain slug.

### S1 — Create `resolve_tenant_by_slug` on staging + verify the security contract

1. **Pre-capture (Rick, STAGING SQL Editor `puoaiyezsreowpwxzxhj`):**
   > ```sql
   > -- confirm no same-named function exists, and the tenants RLS surface anon sees
   > SELECT proname, pg_get_function_identity_arguments(oid) AS args
   > FROM pg_proc WHERE proname = 'resolve_tenant_by_slug';
   > SELECT policyname, cmd, roles FROM pg_policies
   > WHERE schemaname='public' AND tablename='tenants' ORDER BY policyname;
   > ```
   > **Paste:** both. **Expected:** zero rows for the function; `tenants` policies include `users read own tenant` (SELECT, `{authenticated}`) and `admins update own tenant` — **no anon SELECT policy** (this is why the RPC is needed). **STOP if** a `resolve_tenant_by_slug` already exists — reconcile before creating.
2. > **PAUSE → Rick (STAGING SQL Editor):** run the § 1.5 `CREATE OR REPLACE FUNCTION` + `REVOKE` + `GRANT` block verbatim, then verify:
   > ```sql
   > -- definition carries SECURITY DEFINER + hardened search_path + minimal columns:
   > SELECT pg_get_functiondef('public.resolve_tenant_by_slug(text)'::regprocedure);
   > -- grants: anon + authenticated EXECUTE, not PUBLIC:
   > SELECT proacl FROM pg_proc WHERE proname='resolve_tenant_by_slug';
   > ```
   > **Paste:** both. **Expected:** definition shows `SECURITY DEFINER`, `SET search_path TO 'public', 'pg_temp'`, and selects exactly `id, slug, display_name`; `proacl` lists `anon=X` and `authenticated=X` and **not** `=X` (PUBLIC). **STOP if** any extra column appears or PUBLIC retains EXECUTE.
3. **Anon-path verification (Claude, `curl.exe` with the staging anon key — the real anon surface, not the SQL Editor superuser):**
   - `POST .../rest/v1/rpc/resolve_tenant_by_slug` body `{"p_slug":"raysandjudys"}` with `apikey:<staging anon>` → `200`, body = one object `{id, slug, display_name}` with the founding UUID `72e29f67-…`; **assert the response JSON has exactly three keys** (no `branding`/`settings`/`created_at`).
   - Same with `{"p_slug":"definitely-not-a-tenant"}` → `200`, body `[]` (empty — no leak, no error detail).
   - Direct anon `GET .../rest/v1/tenants?select=*` → still RLS-blocked (empty/forbidden) — confirms the RPC is the *only* anon read path. (`test-magic-link.ps1` has the `curl.exe --data-binary @file` pattern; `Invoke-RestMethod` mangles JSON — § Known Issues.)
   - **HALT** if the three-key assertion fails or unknown-slug returns anything but empty.
4. **Record (Claude):** § 13 — add the RPC contract + the "exposing tenant UUID to anon is safe" rationale + the "no status filter today" forward-note (do not yet mark F14/F64-8 resolved — that is S4). Deploy Log row. Commit:
   ```
   docs: 5.2 S1 — resolve_tenant_by_slug created on staging; anon contract verified (3-col, hardened)
   ```

### S2 — app.js: RPC-backed anon resolution + subdomain parser (map retained as fallback)

1. **Branch:** `git checkout -b feature/5.2-slug-rpc` off current `staging` (pulled).
2. **File-drift gate (Claude):** re-read the `TenantContext` block from disk; confirm the § 1.1 branch structure byte-exactly (`Select-String -Path app.js -Pattern "TENANT_SLUG_MAP"` → 3 lines; the `?t=`/sessionStorage sites match lines ~74–96). **HALT on mismatch** — re-derive line targets from disk; do not force.
3. **Edit A — RPC helper + subdomain parser** (add near the `TenantContext` definition, after `FOUNDING_TENANT`):
   ```js
   // Hostnames that are NOT per-tenant subdomains → resolve to the founding tenant.
   const NON_TENANT_HOSTS = new Set([
     'pulllist.app', 'www.pulllist.app',
     'pulllist.pages.dev', 'staging.pulllist.pages.dev',
     'localhost', '127.0.0.1',
   ]);
   const TENANT_APEX = 'pulllist.app';            // <slug>.pulllist.app ⇒ slug

   function tenantSlugFromHostname() {
     try {
       const host = window.location.hostname.toLowerCase();
       if (NON_TENANT_HOSTS.has(host)) return null;
       if (host.endsWith('.pages.dev')) return null;          // all CF previews
       const suffix = '.' + TENANT_APEX;
       if (host.endsWith(suffix)) {
         const label = host.slice(0, -suffix.length);
         if (label && !label.includes('.') && label !== 'www') return label;
       }
       return null;
     } catch (_) { return null; }
   }

   async function lookupTenantBySlug(slug) {
     try {
       const { data, error } = await db.rpc('resolve_tenant_by_slug', { p_slug: slug });
       if (error) { console.warn('resolve_tenant_by_slug failed', error); return null; }
       return (data && data[0]) || null;
     } catch (err) {
       console.warn('resolve_tenant_by_slug threw', err);
       return null;
     }
   }
   ```
4. **Edit B — wire subdomain resolution + RPC into `resolve()`.** After the authenticated-profile branch (branch 1, unchanged) and before the `?t=` branch, insert a subdomain branch; convert the `?t=` and sessionStorage branches to RPC lookups (keeping `TENANT_SLUG_MAP[...]` as a synchronous fallback *only if the RPC returns null*, so a transient RPC failure still resolves the founding tenant on its own subdomain/apex):
   ```js
   // 1.5 Subdomain (e.g. <slug>.pulllist.app) — anon canonical signal post-5.1
   try {
     const subSlug = tenantSlugFromHostname();
     if (subSlug) {
       const tenant = (await lookupTenantBySlug(subSlug)) || TENANT_SLUG_MAP[subSlug];
       if (tenant) {
         sessionStorage.setItem('pulllist.tenant_slug', subSlug);
         this._current = tenant; this._source = 'subdomain';
         return this._current;
       }
       console.warn('TenantContext: unknown tenant subdomain', subSlug);
     }
   } catch (err) { console.warn('TenantContext: subdomain lookup failed', err); }
   ```
   - `?t=` branch: `const tenant = (await lookupTenantBySlug(fromQuery)) || TENANT_SLUG_MAP[fromQuery];` (rest of the branch unchanged; `_source = 'query'`).
   - sessionStorage branch: `const tenant = (await lookupTenantBySlug(fromStorage)) || TENANT_SLUG_MAP[fromStorage]; if (tenant) { this._current = tenant; this._source = 'session'; return this._current; }`.
   - The founding default (branch 4) is unchanged. **Net precedence:** profile → subdomain → `?t=` → sessionStorage → founding default. (Exact `old_str`/`new_str` derived from disk at execution; the above is the shape.)
5. **Verification greps (Claude):**
   - `Select-String -Path app.js -Pattern "resolve_tenant_by_slug"` → **2 lines** (the `db.rpc(...)` call; the warn message). *(Adjust to the literal count of the final edit — derive from `new_str`, never estimate.)*
   - `Select-String -Path app.js -Pattern "tenantSlugFromHostname"` → **2 lines** (definition + the call in `resolve()`).
   - `Select-String -Path app.js -Pattern "TENANT_SLUG_MAP"` → still present (definition + the three fallback sites) — removed in S6, not here.
   - `git diff` shows **no** change outside the `TenantContext` region.
6. **Smoke (Claude):** `cd C:\Users\richa\…\catalogs\scripts\playwright` → `.\run-smoke.ps1` — full suite green on `staging.pulllist.pages.dev` (the host hits the `staging.pulllist.pages.dev` non-tenant rule → founding tenant → all existing specs behave identically). **Stop on any failure.**
7. **Commit + deploy to staging (Claude):**
   ```
   git add app.js
   git commit -m "feat(tenant): RPC-backed anon tenant resolution + subdomain parser (5.2 S2)"
   git checkout staging
   git pull origin staging
   git merge --ff-only feature/5.2-slug-rpc
   git push origin staging
   ```
8. **Record (Claude):** Deploy Log row (greps, suite result). Doc commit:
   ```
   docs: 5.2 S2 — app.js wired to resolve_tenant_by_slug + subdomain parser; staging green
   ```

### S3 — Subdomain + founding-invariant verification

1. **Parser unit coverage (Claude, local-only Playwright/Node):** assert `tenantSlugFromHostname()` against a host table — `pulllist.app`→null, `www.pulllist.app`→null, `staging.pulllist.pages.dev`→null, `foo.pages.dev`→null, `localhost`→null, `raysandjudys.pulllist.app`→`raysandjudys`, `tenant2.pulllist.app`→`tenant2`. (Pure function; testable without a live second subdomain.)
2. **Live resolution checks (Claude, against the staging alias):**
   - Load `staging.pulllist.pages.dev/catalog` (no `?t=`) → `TenantContext.source()` = `default` or `profile`; `current().id` = founding `72e29f67-…`. **Founding invariant holds.**
   - Load `…/catalog?t=raysandjudys` (anon/incognito) → `source()` = `query`, founding tenant, resolved **via the RPC** (network panel shows the `rpc/resolve_tenant_by_slug` call). 
   - Load `…/catalog?t=bogus-tenant` → unknown slug warning; resolution falls through to founding default (no crash, no leak).
   - (Subdomain branch can't be exercised live on staging — no `<slug>.pulllist.app` host exists; covered by step-1 unit test + the S7 prod founding-apex check. Note this gap honestly in the Deploy Log.)
3. **Full Playwright (Claude):** `.\run-smoke.ps1` — 15/15 incl. tenant-isolation specs (F15/F20). The RPC path must not widen any anon read; isolation specs are the guard.
4. **Record (Claude):** Deploy Log row (unit table result, the three live checks, the honest subdomain-live gap). Doc commit:
   ```
   docs: 5.2 S3 — subdomain parser unit-verified; founding invariant + RPC path green on staging
   ```

### S4 — Index disposition (DDL flagged: staging-only DROP; F64 item 8 no-op)

1. **Pre-capture (Rick, STAGING SQL Editor):** run the § 1.2 `pg_indexes` query. **Paste.** **Expected:** staging has `tenants_pkey`, `tenants_slug_key`, `idx_tenants_slug`. **STOP if `idx_tenants_slug` is absent** (already dropped — record and skip the DROP).
2. > **PAUSE → Rick (STAGING SQL Editor):**
   > ```sql
   > DROP INDEX public.idx_tenants_slug;
   > -- verify:
   > SELECT indexname FROM pg_indexes
   > WHERE schemaname='public' AND tablename='tenants' ORDER BY indexname;
   > ```
   > **Paste:** result. **Expected:** two rows — `tenants_pkey`, `tenants_slug_key` (now matching prod). **STOP if** the drop errors or the unique `tenants_slug_key` is somehow affected.
3. **Prod confirmation (Rick, PROD SQL Editor `plgegklqtdjxeglvyjte`):** run the same `pg_indexes` query. **Paste.** **Expected:** `tenants_pkey`, `tenants_slug_key`, **no** `idx_tenants_slug` — confirming F64 item 8 needs no action (the RPC's slug lookup is already served). **No prod DDL.**
4. **Record (Claude):** § 13 — **F14 → resolved** (redundant index dropped on staging; parity with prod); **F64 item 8 → dispositioned no-op** ("`tenants_slug_key` already serves the slug→id RPC; no second index added"); update the `tenants` index prose (lines ~287 / ~1039). Parent § Deferred-DDL Register F64-8 row → closed (no-op). Deploy Log row. Commit:
   ```
   docs: resolve F14 (drop redundant staging idx_tenants_slug); F64 item 8 → no-op (5.2 S4)
   ```

### S5 — F67 (adjacent): Edge Function `APP_BASE_URL` (staging deploy → prod deploy)

1. **Re-verify the five sites (Claude):** `Select-String -Path supabase\functions\*\index.ts -Pattern "mrcyberrick|STAGING_BASE|comic-preorder"` → confirm the § 1.4 set byte-exactly; **HALT** if any function's constant moved or changed (re-derive). Confirm `git show main:supabase/functions/<fn>/index.ts` matches `staging` for each (5.1 S1 found them identical — re-confirm).
2. **Edit (Claude, on `feature/5.2-slug-rpc` or a dedicated `feature/f67-app-base-url` — Rick's call; F67 is independent of the RPC code, a separate branch keeps rollback clean):** in each of the five functions, replace the hardcoded constant/inline literal with `const APP_BASE = Deno.env.get('APP_BASE_URL');` (and use `APP_BASE` where the constant was). For `notify-customers:163`, replace the inline `https://mrcyberrick.us/comic-preorder/catalog.html` with `` `${APP_BASE}/catalog.html` ``. Preserve each function's existing path suffixes.
3. > **PAUSE → Rick (Supabase dashboard — STAGING project first):** Edge Functions → Secrets → add `APP_BASE_URL = https://staging.pulllist.pages.dev`. Then deploy each of the five functions (dashboard or `supabase functions deploy`). **Paste:** secret set confirmation + deploy results. **Expected:** five green deploys.
4. **Staging verify (Claude + Rick):** trigger one email path that uses a base URL (e.g. invite or reset-password via the staging app) → **Rick pastes** the received link → **Expected:** host = `staging.pulllist.pages.dev` (not `mrcyberrick.github.io`, not the anomalous `mrcyberrick.us/...`). `verifyOtp` succeeds on the new URL. **STOP if** any link still carries an old host (secret not picked up / a missed site).
5. > **PAUSE → Rick (Supabase dashboard — PROD project, after staging verify):** Secrets → `APP_BASE_URL = https://pulllist.app`; deploy the same five functions. **Paste:** confirmations. Then **Rick** exercises one prod email path (e.g. password reset for a test account) → link host = `https://pulllist.app`, `verifyOtp` succeeds (this also clears the pre-existing prod magic-link-points-at-staging defect). **STOP if** any prod link still carries an old host.
6. **Record (Claude):** § 13 **F67 → resolved** (secret values per project, five functions, staging+prod deploy confirmations, the cleared pre-existing defects). Deploy Log rows (staging deploy, prod deploy as separate rows). Commit:
   ```
   fix(edge): replace hardcoded app URLs with APP_BASE_URL env (F67, 5.2 S5)
   ```
   ```
   docs: resolve F67 — APP_BASE_URL secret set + 5 functions deployed both projects (5.2 S5)
   ```

### S6 — Remove `TENANT_SLUG_MAP` (final code commit)

1. **Pre-check (Claude):** S2–S3 green; the RPC path is proven on staging. Only now remove the map (parent § Rollback Notes: "TENANT_SLUG_MAP removal is the last commit and revertible").
2. **Edit (Claude, on `feature/5.2-slug-rpc`):** delete the `TENANT_SLUG_MAP` const (lines ~34–37) and the three `|| TENANT_SLUG_MAP[...]` fallbacks added in S2, leaving the RPC result as the sole source and the founding default as the only hardcoded fallback. Update the block comment (lines ~22–25) — the "hardcoded here … replaced with an RPC in a later sub-deploy" note is now satisfied; rewrite to describe the RPC + subdomain model.
3. **Verification greps (Claude):**
   - `Select-String -Path app.js -Pattern "TENANT_SLUG_MAP"` → **0 lines**.
   - `Select-String -Path app.js -Pattern "resolve_tenant_by_slug"` → still 2 lines.
   - `Select-String -Path app.js -Pattern "FOUNDING_TENANT"` → still present (the safety fallback stays).
4. **Smoke (Claude):** `.\run-smoke.ps1` — full suite green with the map gone (proves the RPC path carries all anon resolution; founding default still covers RPC-unavailable). Re-run the S3 live checks (`?t=raysandjudys`, no-param, bad slug).
5. **Commit + deploy to staging (Claude):**
   ```
   git add app.js
   git commit -m "refactor(tenant): remove hardcoded TENANT_SLUG_MAP — RPC is sole slug source (5.2 S6)"
   git checkout staging
   git pull origin staging
   git merge --ff-only feature/5.2-slug-rpc
   git push origin staging
   ```
6. > **PAUSE → Rick (browser, staging):** load `staging.pulllist.pages.dev`, log in, catalog → reserve → My List → cancel; confirm normal behavior with the map removed. **Paste:** "staging verified".
7. **Record (Claude):** Deploy Log row. Doc commit:
   ```
   docs: 5.2 S6 — TENANT_SLUG_MAP removed; RPC is the sole anon slug source; staging green
   ```

### S7 — Prod promotion (Rick's chosen window)

**Order is load-bearing: prod RPC must exist before the app.js prod promotion.**

1. > **PAUSE → Rick (PROD SQL Editor `plgegklqtdjxeglvyjte`):** run the § 1.5 `CREATE OR REPLACE FUNCTION` + `REVOKE` + `GRANT` block verbatim (identical to staging S1). Verify with the S1-step-2 queries. **Paste:** definition + `proacl`. **Expected:** `SECURITY DEFINER`, hardened search_path, three columns; `anon`+`authenticated` EXECUTE, not PUBLIC.
2. **Prod anon-contract check (Claude, `curl.exe` with the PROD anon key):** `rpc/resolve_tenant_by_slug` `{"p_slug":"raysandjudys"}` → `200`, one object, **exactly three keys**, prod founding UUID (from `scripts/phase-4-prod-tenant-uuid.txt`); unknown slug → `[]`; direct anon `GET /tenants?select=*` → RLS-blocked. **HALT** on any mismatch — do not promote app.js against an unverified prod RPC.
3. **App.js prod promotion (standard workflow — Claude prepares, Rick merges):**
   ```
   git checkout main
   git pull origin main
   git merge staging --no-commit --no-ff
   git checkout main -- config.js
   # F59 diff assertion — app.js MUST differ (this promotion changes it):
   foreach ($f in @('app.js','mylist.html','arrivals.html','admin.html')) {
     $d = git diff "main:$f" "staging:$f" 2>$null
     if ($f -eq 'app.js' -and -not $d) { Write-Host "ERROR: app.js identical to main — 5.2 must change it"; }
     elseif ($d) { Write-Host "ok: $f differs" } else { Write-Host "WARN: $f identical (verify expected)" }
   }
   git commit -m "feat(tenant): slug→id RPC routing + subdomain resolution (5.2 prod)"
   git checkout -b feat/5.2-slug-rpc-prod
   git push origin feat/5.2-slug-rpc-prod
   ```
   Open PR `feat/5.2-slug-rpc-prod → main`. **Rick verifies `config.js` is NOT in the diff and merges.** CF Pages auto-deploys `main` at `pulllist.app`.
4. **Post-deploy verification (Claude + Rick):**
   - `curl.exe -s https://pulllist.app/app.js` → contains `resolve_tenant_by_slug`, does **not** contain `TENANT_SLUG_MAP`.
   - **Founding-apex invariant (Rick, browser):** `pulllist.app` (no `?t=`) loads normally as the founding tenant; `TenantContext.current().id` = prod founding UUID; `tenantSlugFromHostname()` returns null for the apex.
   - **Write-smoke (Rick):** reserve one item as a test user → row lands in prod `preorders` with the correct founding `tenant_id` → cancel it.
   - `?t=raysandjudys` on prod resolves via the RPC (network panel) to the founding tenant.
5. **Record (Claude):** Deploy Log row (prod RPC verified, PR #, prod commit, write-smoke row). Doc commit:
   ```
   docs: 5.2 S7 — prod RPC created + app.js promoted; founding-apex invariant + write-smoke verified
   ```

### S8 — Closeout (run once, when every § 5 box is ticked)

1. Tick the § 5 boxes with inline result notes (5.0/5.1 pattern).
2. This file: Status line → **Complete** + date; Last-updated line.
3. Parent (`phase-5-second-tenant-onboarding.md`): row 5.2 → **Complete** + date; § Deferred-DDL Register F64-8 row → closed (no-op disposition); row 5.3 → **Planning** only when its plan file exists (next session writes it); § Carry-Forward / Phase Completion Criteria "`TENANT_SLUG_MAP` removed" box tickable.
4. `CLAUDE.md` § Current Migration Phase: active sub-deploy → **5.3 (plan not yet written)**; last-completed → 5.2; § Known Out-of-Scope Items: remove the "Slug→id RPC — `TENANT_SLUG_MAP` hardcoded — sub-deploy 5.2" line; open-findings line updated (F14/F64-8/F67 resolved; remaining open: F64 item 5 pre-5.4; next free ID **F71** unless 5.2 filed one).
5. Commit:
   ```
   docs: close Phase 5.2 (slug→id routing RPC); advance pointer to 5.3 planning
   ```
6. End-of-session status update per `CLAUDE.md` § Anti-Drift Rules (changed / verified / left / filed / new IDs).

---

## 5. Completion criteria (all must be checked before parent row 5.2 → Complete)

- [ ] S1: `resolve_tenant_by_slug` live on **staging**; `pg_get_functiondef` shows `SECURITY DEFINER` + `SET search_path` + exactly `id, slug, display_name`; `proacl` = `anon`+`authenticated` EXECUTE, not PUBLIC; anon `curl.exe` returns a three-key object for `raysandjudys` and `[]` for an unknown slug; direct anon `tenants` SELECT still RLS-blocked.
- [ ] S2: `app.js` resolves the `?t=`/sessionStorage paths via the RPC and adds `tenantSlugFromHostname()`; `TENANT_SLUG_MAP` retained only as fallback; full Playwright green on the staging alias; diff confined to `TenantContext`.
- [ ] S3: parser unit table passes (founding/infra hosts → null; `<slug>.pulllist.app` → slug); `pulllist.app`/`staging.pulllist.pages.dev`/`*.pages.dev` resolve to founding; `?t=` resolves via the RPC; bad slug falls through cleanly; full Playwright incl. tenant-isolation green; live-subdomain gap noted honestly.
- [ ] S4: **F14 resolved** — `idx_tenants_slug` dropped on staging; live `pg_indexes` on staging = `{tenants_pkey, tenants_slug_key}`; prod confirmed already lacking `idx_tenants_slug`; **F64 item 8 dispositioned no-op** (no prod index); index prose updated; Deferred-DDL Register row closed.
- [ ] S5 (F67, adjacent): `APP_BASE_URL` set in both projects (staging `https://staging.pulllist.pages.dev`, prod `https://pulllist.app`); all five functions redeployed; a staging email link and a prod email link both carry the correct host and `verifyOtp` succeeds; **F67 resolved** in § 13.
- [ ] S6: `TENANT_SLUG_MAP` removed (`Select-String` → 0 lines); RPC is the sole anon slug source with the founding default as the only hardcoded fallback; full Playwright green; Rick staging-verified.
- [ ] S7: prod `resolve_tenant_by_slug` live and anon-verified (three-key, prod founding UUID) **before** app.js promotion; app.js promoted via the standard workflow (`config.js` not in PR diff; F59 assertion confirms app.js changed); founding-apex invariant verified on `pulllist.app`; write-smoke passed (reserve → correct founding `tenant_id` → cancel).
- [ ] Founding-tenant behavior unchanged (parent invariant): full Playwright incl. tenant-isolation green at the S2/S3/S6 staging gates and the S7 prod write-smoke.
- [ ] F14, F64 item 8, F67 → resolved/dispositioned in § 13; any new defect filed from **F71**+ resolved or deferred-with-owner.
- [ ] Deploy Log complete (one row per executed step); all doc changes committed to `staging`; parent row 5.2 → **Complete** + date; `CLAUDE.md` pointer advanced to 5.3 planning.

---

## 6. Rollback (per step; pre-captures taken before every change)

- **S1 (staging RPC):** `DROP FUNCTION public.resolve_tenant_by_slug(text);` — nothing references it until S2's app.js lands. Additive; no data surface.
- **S2/S3 (app.js wiring):** revert the `feature/5.2-slug-rpc` commit on `staging` — `TENANT_SLUG_MAP` is still present and synchronous, so the app reverts to map-based resolution with zero RPC dependency.
- **S4 (F14 index drop):** `CREATE INDEX idx_tenants_slug ON public.tenants (slug);` — re-creates the dropped redundant index (only as a true rollback; redundancy is the thing being removed).
- **S5 (F67):** revert the EF source commit and re-deploy the five functions with the captured constants; the `APP_BASE_URL` secret may stay (inert if unused). Per-function deploy is independent — a single bad function reverts alone.
- **S6 (map removal):** revert the removal commit — restores `TENANT_SLUG_MAP` + the `|| TENANT_SLUG_MAP[...]` fallbacks; this is precisely why removal is the last, isolated commit.
- **S7 (prod):** app.js — re-deploy the prior `main` commit via the standard path. Prod RPC — `DROP FUNCTION` once app.js is rolled back (or leave it; harmless and unused). The founding default in `app.js` means even an orphaned/absent RPC resolves the founding tenant on `pulllist.app`.
- Nothing in 5.2 touches customer data; Tier-3 forward-fix pressure does not apply.

---

## 7. References

- Decision (index): Rick, 5.2 planning 2026-06-15 — index choice has no security dimension; chose minimal-surface (no-op F64 item 8; drop redundant staging `idx_tenants_slug` to close F14). The security work lives in the RPC contract (§ 1.5), not the index.
- Parent: `docs/phase-5-second-tenant-onboarding.md` (row 5.2; § Approach Decisions "hosting before subdomain routing"; § Deferred-DDL Register F64-8; § Out of Scope SECURITY DEFINER hardening mandate).
- Shape mirror: `docs/phase-5.0-pre-phase-5-housekeeping.md` and `docs/phase-5.1-hosting-migration.md` (execution model, pause-block format, deploy-log resume protocol, F59 diff-assertion + `config.js` checkout on prod promotion).
- Findings: `docs/technical-reference.md` § 13 — **F14** (redundant index), **F64 item 8** (parent register), **F67** (EF hardcoded URLs). **Next free ID at planning: F71.**
- Code: `app.js` `TenantContext` (lines ~12–125 at planning); `initNav()` `await TenantContext.resolve()` (~190). RLS: `users read own tenant` is the only authenticated `tenants` SELECT path; no anon SELECT — the reason the RPC exists.
- Hosting (post-5.1): prod apex `pulllist.app`; staging alias `staging.pulllist.pages.dev`; prod Pages URL `pulllist.pages.dev`; CF previews `*.pages.dev`. Live second-tenant subdomain provisioning is 5.5.
- Curl pattern for tenant-aware Supabase calls: `test-magic-link.ps1` (`curl.exe --data-binary @file`; `Invoke-RestMethod` mangles JSON — § Known Issues).
- Projects: staging `puoaiyezsreowpwxzxhj`, prod `plgegklqtdjxeglvyjte`. Founding tenant UUID (staging) `72e29f67-39f7-42bc-a4d5-d6f992f9d790`; prod founding UUID in `catalogs\scripts\phase-4-prod-tenant-uuid.txt` (local-only) — needed at S2 fallback const sanity and S7 write-smoke/RPC checks.
- **Flagged for Rick (out of 5.2 scope):** F64 item 5 DDL (`preorders_user_id_fkey` → `user_profiles` NO ACTION on prod) still has no landed owner and must execute before 5.4.

---

## 8. Deploy log (filled during execution)

| Date | Step | Result | Notes |
|---|---|---|---|
| 2026-06-15 | S1 | ✅ Green | `resolve_tenant_by_slug` created on staging. `pg_get_functiondef` confirms STABLE SECURITY DEFINER + hardened search_path + 3-col projection. `proacl`: anon+authenticated EXECUTE, no PUBLIC. Anon curl: raysandjudys → 200, 3-key object (72e29f67-…); unknown slug → 200, []; direct tenants SELECT → permission denied. |
| 2026-06-15 | S2 | ✅ Green | `app.js`: `lookupTenantBySlug()` + `tenantSlugFromHostname()` added; subdomain branch (1.5) inserted; `?t=`/sessionStorage branches converted to RPC-backed with TENANT_SLUG_MAP fallback retained. Greps: resolve_tenant_by_slug=3, tenantSlugFromHostname=2, TENANT_SLUG_MAP=4 (fallback present). 15/15 Playwright green incl. F15/F20. Merged feature/5.2-slug-rpc → staging (077d37a) --ff-only; pushed. |
| 2026-06-15 | S3 | ✅ Green | Parser unit table: 11/11 (all founding/infra hosts → null; raysandjudys.pulllist.app → "raysandjudys"; tenant2.pulllist.app → "tenant2"; multi-label → null). Live: RPC resolves raysandjudys → 72e29f67-…; bogus slug → []; deployed app.js on staging.pulllist.pages.dev contains resolve_tenant_by_slug + tenantSlugFromHostname. 15/15 Playwright green. Gap noted: live subdomain branch untestable (no <slug>.pulllist.app host exists until 5.5); covered by parser unit test + S7 prod apex check. |
| 2026-06-15 | S4 | ✅ Green | Staging pre-capture: idx_tenants_slug + tenants_pkey + tenants_slug_key confirmed. DROP INDEX executed; post-drop pg_indexes = {tenants_pkey, tenants_slug_key}. Prod pg_indexes confirmed identical (no idx_tenants_slug) — F64 item 8 no-op verified. F14 → resolved; F64-8 → dispositioned; § 13 + index prose + parent Deferred-DDL Register updated. |
| 2026-06-15 | S5 (staging) | ✅ Green | APP_BASE_URL secret set (staging.pulllist.pages.dev); 5 EFs deployed. Staging verify: invite email link → redirect_to=https://staging.pulllist.pages.dev/index.html ✅ |
| 2026-06-15 | S5 (prod) | ✅ Green | APP_BASE_URL secret set (pulllist.app); 5 EFs deployed. reset-password had JWT verification ON (same as F68) — set to OFF (public endpoint by design). Prod verify: reset-password email link → https://pulllist.app/forgot-password ✅. F67 resolved. |
| 2026-06-15 | S6 | ✅ Green | TENANT_SLUG_MAP removed (0 grep hits); block comment updated to describe RPC model; FOUNDING_TENANT remains as sole hardcoded fallback. 15/15 Playwright green. Rick staging-verified (reserve → cancel normal). Committed 823b748. |
| | S7 | | |
| | S8 | | |

---

**Last updated:** 2026-06-15 (plan written; not yet executed — Status: Planning)
