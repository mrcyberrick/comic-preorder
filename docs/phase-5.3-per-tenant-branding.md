# Phase 5.3 — Per-Tenant Branding

**Status:** In progress — S1 complete 2026-06-15.
**Parent plan:** `docs/phase-5-second-tenant-onboarding.md` (sub-deploy row 5.3)
**Predecessor:** Phase 5.2 — Slug→id routing RPC — **Complete 2026-06-15** (`resolve_tenant_by_slug` live both projects; `TENANT_SLUG_MAP` removed; F14/F64-8/F67 resolved).
**Branches:** Database (RPC) + doc changes do their work via the SQL Editor / dashboard (doc commits → `staging` directly). The `app.js` + `*.html` changes ride `feature/5.3-branding` off `staging` → `--ff-only` merge → staging smoke → prod promotion PR per `CLAUDE.md` § Standard Deployment Workflow (F59 diff assertion + `config.js` checkout + post-deploy write-smoke). **`config.js` is touched in this sub-deploy** (new `FOUNDING_TENANT` per-branch key, F71) — see § 1.5 and the credential-safety handling in every relevant step.
**Execution model:** **CLI-orchestrated, Rick-in-the-loop.** A Claude Code CLI session runs this file top to bottom. It executes every repo / doc / local-script / Playwright step itself, and **pauses at every database step (staging *and* prod), every Supabase dashboard action, every `config.js` edit (agent never edits `config.js` — Rick does, per branch), and the prod promotion merge** — handing Rick the exact SQL / clicks / values and **waiting for pasted results before continuing**. **Self-contained — no chat context required.**
**Rollback complexity:** Easy (parent table) — rendering-only; the founding tenant's `branding` is `{}`, the renderer treats absent keys as no-ops, so the founding default path renders **identically to today** by construction. The RPC extension is additive (`CREATE OR REPLACE`, revertible to the 3-col body). No customer-write dependency anywhere in 5.3.

> **Steps Claude never runs itself.** (1) Any Supabase **SQL Editor** statement — staging *or* prod (RPC re-create; the optional transient-branding override proof). (2) Any **`config.js`** edit — Rick adds the new `FOUNDING_TENANT` key to the `staging` branch (S2) and the `main` branch (S6) by hand; the agent never edits `config.js` and never proposes credential/UUID values into it beyond naming the key shape. (3) The S6 prod promotion merge/PR approval — Claude prepares it; Rick reviews and merges. Each appears below as a **`PAUSE → Rick … → paste result → match expected → continue / STOP`** block.

> **5.3 may span multiple sittings.** The durable state is the **Deploy Log (§ 8)**: every session appends one row per completed step. A resuming session reads the log, re-verifies the last recorded step against live state (a recorded RPC re-create is re-verified by calling it before trusting it; a recorded `config.js` key is re-verified by `Select-String`), and continues from the next unexecuted step. Every doc edit is committed before the session ends.

> **Founding-tenant invariant (parent completion criterion for every 5.x sub-deploy) — and how 5.3 satisfies it by construction.** The founding tenant's `tenants.branding` is `{}`. The branding renderer is an **override layer**: it applies a visual property **only if** the corresponding key is present in `branding`; an empty/missing key leaves the hardcoded HTML/CSS default untouched. Therefore an empty `branding` → zero overrides → the page renders **byte-identically to today**. The hard invariant ("founding renders identically to today by default") holds **regardless of which resolution branch the founding tenant takes**, because its branding payload is empty either way. Every gate runs the full Playwright suite including the tenant-isolation specs (F15/F20); the founding render is additionally asserted unchanged.

---

## 0. Pre-flight (run at the top of every 5.3 session; halt on any mismatch)

### 0.1 Read before doing anything
- `CLAUDE.md` in full; confirm § Current Migration Phase active sub-deploy = **5.3**.
- `docs/phase-5-second-tenant-onboarding.md` — Sub-Deploys row 5.3; § In Scope 5.3 ("name, colors, logo at minimum; founding tenant renders identically to today by default"); § Out of Scope (**multi-tenant email branding / per-tenant MailerSend identities are explicitly OUT of Phase 5** — 5.3 does **not** touch Edge Function email templates or invoice copy; the new branding render path is client-side only); § Approach Decisions (founding-tenant invariant is a completion criterion for every 5.x).
- This file in full — including the Deploy Log (§ 8): if any rows exist, this is a resume session.
- `docs/technical-reference.md` § 4.1 (`tenants` table — `branding` jsonb column, default `{}`), § 13 **F71** (the `FOUNDING_TENANT` staging-id/slug defect this sub-deploy resolves) and the `resolve_tenant_by_slug` contract note (the RPC 5.3 extends).
- `app.js`: `FOUNDING_TENANT` const (planning lines ~28–32), `TenantContext` block (~67–170) — the profile branch's `tenants` SELECT (~85–89) and the four anon resolution branches; `initNav()` and its `await TenantContext.resolve()` (~230–235).
- `index.html` init path — the **login/landing page has no `#main-nav`, so `initNav()` returns early there**; index.html resolves the tenant on its own and is the **primary anon-visible branding surface** (a tenant-2 subdomain visitor lands here). Confirm its resolve/init wiring from disk before adding the branding call.
- `style.css` `:root` block (planning lines ~10–34) — `--accent` / `--accent-hover` / `--accent-dim` are the brand-color custom properties the renderer overrides.

### 0.2 Gates (halt if any fail)
- `git rev-parse --abbrev-ref HEAD` → `staging`; `git status` → clean (the known-stray untracked `docs/status-slide.html` is acceptable; anything else, stop and ask).
- `git pull origin staging` → up to date (or fast-forward) before any edit.
- `docs/technical-reference.md` § 13: confirm the highest filed finding ID (**F71** at planning time; **next free = F72**). New defects discovered during 5.3 are filed from F72 — never guessed or reused.
- **Re-verify the planning-time audits in § 1 against the current tree and live DBs** (anti-drift: never trust a prior session's grep). Re-read the `FOUNDING_TENANT` const + `TenantContext` profile branch from disk before any `app.js` edit; re-query the live `resolve_tenant_by_slug` definition (§ 1.1) before the `CREATE OR REPLACE`.

### 0.3 Commit discipline
- Each S-step's doc update (RPC contract change, F71 resolution, deploy-log row) is its own doc-only commit to `staging` with the finding ID(s) where relevant — exact messages inline.
- The `app.js` + `*.html` changes ride `feature/5.3-branding`, never `staging` directly. **F71's `app.js` const-source change (S2) is its own commit; the `Branding` renderer (S3) is its own; the HTML data-hook pass (S4) is its own** — so each is independently revertible.
- `config.js` is **never** committed by the agent on a feature branch; Rick edits it per branch (S2 staging, S6 main) and those edits land via Rick's normal flow. The agent only verifies the key's presence via `Select-String`.
- Push `origin staging` after each commit; the Deploy Log row lands in the same commit as the step it records.

### 0.4 Files / surfaces touched by this sub-deploy

| File / target | Change | Branch / actor |
|---|---|---|
| Staging DB (`public` schema) | `CREATE OR REPLACE FUNCTION resolve_tenant_by_slug` → add `branding jsonb` to the projection (S1); optional transient founding-branding override for the live proof (S5) | Rick, staging SQL Editor |
| Production DB (`public` schema) | `CREATE OR REPLACE FUNCTION resolve_tenant_by_slug` → same 4-col body (S6, before app.js prod promotion) | Rick, prod SQL Editor |
| `config.js` | New per-branch `window.FOUNDING_TENANT = { id, slug, display_name }` (staging values on `staging`, prod values on `main`) — resolves **F71** | Rick (per branch: S2 staging, S6 main) |
| `app.js` | F71: `const FOUNDING_TENANT = window.FOUNDING_TENANT` (remove hardcoded staging object) (S2); new `Branding` module + `Branding.apply()` wired after each page's `resolve()` (S3); profile-branch `tenants` SELECT extended to include `branding` (S3) | `feature/5.3-branding` |
| `catalog.html`, `mylist.html`, `arrivals.html`, `subscriptions.html`, `admin.html`, `index.html` | Add `data-tenant-name` / `data-tenant-logo` hooks at the literal store-name/logo sites; index.html wires `Branding.apply()` on its anon landing path (S4) | `feature/5.3-branding` |
| Playwright suite (local-only, never committed) | New `Branding.apply()` pure-function unit spec (override-when-present / no-op-when-empty); existing tenant-isolation + founding-render specs unchanged in intent | Claude, direct edit |
| `docs/technical-reference.md` | § 4.1 branding note updated ("read by `Branding.apply()` as of 5.3"); § 13 **F71 → resolved**; RPC contract note updated (now returns `branding`; `settings` still never returned) | `staging` (doc-only) |
| `docs/phase-5-second-tenant-onboarding.md` | Row 5.3 → Complete | `staging` (doc-only) |
| `CLAUDE.md` | § Current Migration Phase pointer advance to 5.4; § Known Out-of-Scope branding line updated; open-findings line updated (F71 resolved) | `staging` (doc-only) |

**Not touched:** `import.js` / `import-staging.js`, the Edge Functions (email/invite/reset templates — **email branding is out of Phase 5 scope**), invoice copy in `admin.html` (out of scope — see § 3), `register-customer` founding-tenant pin (sub-deploy 5.4), the F64 item 5 FK realignment (Deferred-DDL Register; owner pre-5.4 — still **flagged to Rick**, see § 7), the `tenants.settings` jsonb (never exposed; not 5.3's surface).

---

## 1. Planning-time audit results (2026-06-15) — re-verify at execution

### 1.1 The RPC to extend
`resolve_tenant_by_slug` (created 5.2) returns exactly `id, slug, display_name` (3 cols), `STABLE SECURITY DEFINER SET search_path = public, pg_temp`, `anon`+`authenticated` EXECUTE, no PUBLIC. 5.3 extends the projection to **4 columns** by adding `branding jsonb`:

```sql
CREATE OR REPLACE FUNCTION public.resolve_tenant_by_slug(p_slug text)
  RETURNS TABLE (id uuid, slug text, display_name text, branding jsonb)
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path = public, pg_temp
  AS $$
    SELECT t.id, t.slug, t.display_name, t.branding
    FROM public.tenants t
    WHERE t.slug = p_slug;
  $$;

REVOKE ALL ON FUNCTION public.resolve_tenant_by_slug(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_tenant_by_slug(text) TO anon, authenticated;
```

Re-grant after `CREATE OR REPLACE` (Postgres preserves grants across `OR REPLACE`, but re-issuing `REVOKE … FROM PUBLIC` + `GRANT … TO anon, authenticated` is idempotent and guards against a default-privilege re-grant). Security properties carried forward from the 5.2 contract, with the one deliberate change:

- **`branding` is public display data — returning it to anon is intended.** Name, colors, and logo are exactly what an anon visitor's landing page must render. This is the one column 5.2 deferred to 5.3 ("config-leak surface; also 5.3's job") — 5.3 makes the call: branding **yes**, `settings` **never**.
- **`settings` jsonb is STILL never returned.** `settings` may carry non-public config; it is not branding and has no client render path. The projection is `id, slug, display_name, branding` and nothing else (no `settings`, no `created_at`, no `contact_*`).
- **`SET search_path = public, pg_temp`**, `STABLE`, exact-equality `WHERE slug = $1` — all unchanged (F23 carve-out hardening preserved).
- **Exposing the tenant UUID to anon remains safe** (writes gated by `current_tenant_id()` from the authenticated profile; anon → NULL → all writes blocked). Rationale already recorded in § 13; the 4-col change does not alter it.

### 1.2 The two delivery paths that must both carry branding
`TenantContext` produces the active tenant object via two shapes that must now both include `branding`:

1. **Authenticated profile branch** (`app.js` ~85–89): `db.from('tenants').select('id, slug, display_name')` → extend to `select('id, slug, display_name, branding')`. RLS already lets an authenticated user SELECT their own tenant (`users read own tenant`), so reading their own `branding` is permitted.
2. **Anon branches** (subdomain / `?t=` / sessionStorage): `lookupTenantBySlug()` → the 4-col RPC → object now carries `branding`.
3. **Founding default branch**: `this._current = FOUNDING_TENANT` — the config.js object carries **no** `branding` key → `Branding.apply()` no-ops → identical-to-today render. (The founding tenant's DB `branding` is `{}` anyway; even when founding resolves via the profile/RPC path, an empty `{}` is also a no-op. Both routes converge on "no override.")

After 5.3, `TenantContext.current()` may carry `branding` (object or undefined); `Branding.apply()` tolerates both.

### 1.3 The branding render contract (the override layer)
A new `Branding` module in `app.js`, applied once per page after `TenantContext.resolve()`:

```js
const Branding = {
  apply(tenant) {
    try {
      const b = (tenant && tenant.branding) || {};

      // 1. Brand color → override --accent (+ derived hover/dim). Absent ⇒ keep default.
      if (b.primary_color && /^#[0-9a-fA-F]{6}$/.test(b.primary_color)) {
        const root = document.documentElement;
        root.style.setProperty('--accent', b.primary_color);
        root.style.setProperty('--accent-hover', b.primary_color);   // simple; refine if a hover key is added
        root.style.setProperty('--accent-dim', this._dim(b.primary_color));
      }

      // 2. Display name → fill [data-tenant-name] text + document.title suffix. Absent ⇒ keep default.
      const name = (tenant && tenant.display_name) || null;
      if (name) {
        document.querySelectorAll('[data-tenant-name]').forEach(el => { el.textContent = name; });
      }

      // 3. Logo → swap [data-tenant-logo] img src. Absent ⇒ keep default markup.
      if (b.logo_url) {
        document.querySelectorAll('img[data-tenant-logo]').forEach(img => { img.src = b.logo_url; });
      }
    } catch (err) { console.warn('Branding.apply failed; rendering defaults', err); }
  },
  _dim(hex) {                                   // #RRGGBB → rgba(r,g,b,0.15)
    const n = parseInt(hex.slice(1), 16);
    return `rgba(${(n>>16)&255},${(n>>8)&255},${n&255},0.15)`;
  },
};
```

Contract properties (each verified at S5):
- **Override-only.** Every branch guards on key presence; `branding = {}` or `undefined` ⇒ zero DOM/CSS mutation ⇒ founding renders identically to today.
- **Validated color.** `primary_color` must match `^#[0-9a-fA-F]{6}$` before it's applied — a malformed value from the DB is ignored, never injected raw (defends against a bad branding row breaking the theme; the value sets a CSS custom property only, not arbitrary CSS).
- **Logo as `img src` only.** `logo_url` is assigned to `img.src` — not `innerHTML` — so it cannot inject markup. (A non-image/404 URL degrades to a broken image, not a render break.)
- **PULLLIST wordmark stays.** The `.nav-logo` "PULLLIST" mark is the **product** brand, not the tenant's — it is **not** given a `data-tenant-name` hook and is never overridden.
- **Failure is silent + safe.** Any throw inside `apply()` is caught and logged; the page keeps the default brand. Branding is cosmetic — it must never block page init.

### 1.4 The hardcoded branding surface (what gets `data-*` hooks)
Planning-time `Select-String` for `Ray & Judy's Book Stop` / `logo` / `--accent` across `*.html` + `style.css` found the literal store-name and logo sites. 5.3 adds **`data-tenant-name`** to the store-name text nodes and **`data-tenant-logo`** to the logo `<img>`, leaving the literal text as the in-markup default (so founding still renders it with zero JS). Re-grep at execution; the planning set:

| Surface | Files (planning lines) | Hook | In scope? |
|---|---|---|---|
| Footer "Service provided by Ray & Judy's Book Stop · Rockaway, NJ" | `catalog.html:216`, `arrivals.html:265`, `admin.html:369`, `analytics.html:354`, + `mylist.html`/`subscriptions.html` footers | `data-tenant-name` on the store-name span | **Yes** (shared footer — keep all five+ in sync per `CLAUDE.md` § Files That Must Stay in Sync) |
| Login tagline "Ray & Judy's Book Stop — Monthly Pre-Orders" + footer | `index.html:19`, `index.html:120` | `data-tenant-name` | **Yes** — primary anon landing surface |
| Login logo `<img src="bookstop_logo.png">` | `index.html:15` | `data-tenant-logo` | **Yes** |
| `--accent` brand color (all usages) | `style.css:19–21` + inline `var(--accent)` across pages | via CSS custom-property override (no per-usage hook needed) | **Yes** |
| Arrivals store-name block | `arrivals.html:205` | `data-tenant-name` | **Yes** |
| Approval/invite copy embedding the store name | `catalog.html:261`, `index.html:34/40` | — | **No** — transactional copy, not a branding slot; revisit if tenant 2 needs it (file, don't fix) |
| Invoice/bagging header "Ray & Judy's Book Stop · 973-586-9182" + `.store` line | `admin.html:1210/1449` | — | **No** — invoice/print copy; out of scope (§ 3) |
| Edge Function email templates | `supabase/functions/**` | — | **No** — email branding explicitly OUT of Phase 5 (parent § Out of Scope) |

> **Scope guard:** the data-hook pass touches **only** the store-name/logo slots in the table's "Yes" rows. If a literal store-name string sits in transactional/invoice/email copy ("No" rows), **leave it** and note it — do not expand the hook surface inline (anti-drift: stop and ask before scope growth).

### 1.5 F71 — `FOUNDING_TENANT` const moves to per-branch `config.js`
F71 (§ 13): the `app.js` `FOUNDING_TENANT` const hardcodes the **staging** id/slug (`72e29f67-…` / `raysandjudys`); prod founding is `20941129-c35a-476d-ae21-44b8f77af89c` / `rjbookstop`. Today this only mis-resolves the *anon apex fallback* on prod (harmless: anon writes RLS-blocked, no anon-readable tenant tables). 5.3 makes it matter — a wrong founding id would mean the wrong branding payload — so it is fixed here.

**Decision (Rick, 5.3 planning 2026-06-15): Option B — move `FOUNDING_TENANT` into `config.js`, which is already tracked per-branch with different values per environment** (the same mechanism as `SUPABASE_ANON_KEY`). "Prioritize efficiency; branding can differ across staging vs prod" — Option B is the idiomatic, zero-extra-round-trip fix and fixes **both** the id and the slug (Option A fixed only the slug and left the staging UUID in place; Option C added a network dependency to the synchronous safety fallback). Per-env branding is delivered naturally: each environment's `tenants.branding` is read from that environment's own DB via the RPC/profile path, so no branding values live in `config.js`.

Mechanics (per `CLAUDE.md` § Credential Safety — "if a feature needs a new key in `config.js`, add it manually to both branches before any merge; the `git checkout` step preserves existing prod values, it does not propagate new keys"):
- `config.js` gains `window.FOUNDING_TENANT = { id: '<env founding uuid>', slug: '<env slug>', display_name: "Ray & Judy's Book Stop" }`.
  - `staging` branch: `id = 72e29f67-…`, `slug = 'raysandjudys'`.
  - `main` branch: `id = 20941129-…`, `slug = 'rjbookstop'`.
- `app.js`: `const FOUNDING_TENANT = window.FOUNDING_TENANT;` (no hardcoded object). Script load order already guarantees `config.js` → `app.js` (`CLAUDE.md` § Files That Must Stay in Sync), so the global is defined before `app.js` reads it.
- **No `branding` key in the config object** — founding's branding is "the defaults," and `Branding.apply()` no-ops on an absent `branding` key.
- **Load-bearing for prod promotion:** the `main` branch `config.js` MUST already contain `FOUNDING_TENANT` **before** the S6 promotion, because `git checkout main -- config.js` preserves `main`'s file and does **not** propagate the new key from `staging`. S6 has an explicit pre-check for this; if absent, prod `app.js` reads `undefined` and the anon fallback breaks. **STOP and have Rick add it before merging.**

---

## 2. In scope

1. **S1** — Extend `resolve_tenant_by_slug` on **staging** to return `branding` (4-col); re-verify the security contract (branding present, `settings` absent, anon EXECUTE, no PUBLIC, unknown slug → empty). Record the contract change in § 13.
2. **S2** — **F71:** Rick adds `FOUNDING_TENANT` to **staging** `config.js`; `app.js` changes the const to read `window.FOUNDING_TENANT` (remove the hardcoded staging object). Resolve **F71**. Feature branch → staging smoke (founding still resolves).
3. **S3** — `app.js`: add the `Branding` module + `_dim()`; wire `Branding.apply(TenantContext.current())` after `resolve()` on every page path (`initNav()` for the 5 authed pages; index.html's own resolve path for the anon landing); extend the profile-branch `tenants` SELECT to include `branding`. Feature branch → staging smoke.
4. **S4** — HTML: add `data-tenant-name` / `data-tenant-logo` hooks at the § 1.4 "Yes"-row sites across `catalog.html`, `mylist.html`, `arrivals.html`, `subscriptions.html`, `admin.html`, `index.html` (footer kept in sync across all). Feature branch → staging smoke.
5. **S5** — Staging verification: `Branding.apply()` pure-function unit spec (override-when-present, no-op-when-empty, malformed-color ignored, logo-src-only); founding-render invariant (empty branding ⇒ identical to today, asserted); **optional** transient live override (Rick sets staging founding `branding` to a test value, confirms color/name/logo change, reverts to `{}` with a verifying SELECT); full Playwright incl. tenant-isolation (F15/F20).
6. **S6** — Prod promotion (Rick's window): pre-check `main` `config.js` has `FOUNDING_TENANT`; `CREATE OR REPLACE` the 4-col RPC on **prod** (before app.js lands); promote `app.js` + `*.html` via the standard workflow (F59 diff assertion, `config.js` checkout — **verify `config.js` not in the PR diff**); founding-apex invariant + write-smoke.
7. **S7** — Closeout: § 5 boxes ticked, § 13 statuses (F71 resolved; RPC contract updated), parent row 5.3 → Complete, `CLAUDE.md` pointer → 5.4 planning, end-of-session status update.

## 3. Out of scope (stop and ask before touching)

- **Edge Function email templates / per-tenant MailerSend identities** — explicitly OUT of Phase 5 (parent § Out of Scope). 5.3's branding path is **client-side render only**; no EF source changes.
- **Invoice / print / bagging-sheet store-name + phone copy** (`admin.html:1210/1449` etc.) — print artifacts, not a screen-branding slot; revisit if tenant 2 needs branded invoices (file from F72, don't fix inline).
- **Transactional/approval copy** that happens to embed the store name (`catalog.html:261`, `index.html:34/40`) — message copy, not a branding slot.
- **`tenants.settings` jsonb** — never exposed by the RPC; not a render surface in 5.3.
- **A branding *editor* / admin UI to set `branding`** — 5.3 *renders* branding; setting it is done by service-role at onboarding (5.5) or a future admin surface. Not built here.
- **`register-customer` founding-tenant un-pin** (F34 residual) — sub-deploy 5.4.
- **F64 item 5 DDL** (`preorders_user_id_fkey` → `user_profiles` NO ACTION on prod) — Deferred-DDL Register; still no landed owner; must execute before 5.4. **Flag to Rick** (§ 7); do not absorb into 5.3 without explicit sign-off.
- **Any `import.js` / `import-staging.js` change.**

---

## 4. Runbook

Execution order: **S1 → S2 → S3 → S4 → S5 (one or two sittings on staging) → S6 (prod promotion, Rick's window) → S7.** S2 (F71) is independent of S3/S4 but lands first so the founding fallback is correct before branding reads it. The prod RPC re-create (S6 step 2) must exist **before** the app.js prod promotion (S6 step 3), or anon `branding` reads on prod would return the old 3-col shape (no `branding` key → `Branding.apply()` no-ops → safe, but the feature would be dark on prod until the RPC lands).

### S1 — Extend `resolve_tenant_by_slug` to 4 columns on staging + re-verify contract

1. **Pre-capture (Rick, STAGING SQL Editor `puoaiyezsreowpwxzxhj`):**
   > ```sql
   > SELECT pg_get_functiondef('public.resolve_tenant_by_slug(text)'::regprocedure);
   > SELECT proacl FROM pg_proc WHERE proname='resolve_tenant_by_slug';
   > ```
   > **Paste:** both. **Expected:** the current 3-col body (`id, slug, display_name`), `SECURITY DEFINER`, `SET search_path TO 'public', 'pg_temp'`; `proacl` lists `anon=X` + `authenticated=X`, no bare `=X` (PUBLIC). **STOP if** the function is missing or already 4-col (already done — record and skip to step 3).
2. > **PAUSE → Rick (STAGING SQL Editor):** run the § 1.1 `CREATE OR REPLACE FUNCTION` + `REVOKE` + `GRANT` block verbatim, then re-verify:
   > ```sql
   > SELECT pg_get_functiondef('public.resolve_tenant_by_slug(text)'::regprocedure);
   > SELECT proacl FROM pg_proc WHERE proname='resolve_tenant_by_slug';
   > ```
   > **Paste:** both. **Expected:** definition now selects exactly `t.id, t.slug, t.display_name, t.branding` (4 cols, no `settings`/`created_at`), still `SECURITY DEFINER` + hardened `search_path`; `proacl` = `anon`+`authenticated` EXECUTE, not PUBLIC. **STOP if** `settings` or any extra column appears, or PUBLIC retains EXECUTE.
3. **Anon-path verification (Claude, `curl.exe` with the staging anon key — `test-magic-link.ps1` pattern; `Invoke-RestMethod` mangles JSON — § Known Issues):**
   - `POST .../rest/v1/rpc/resolve_tenant_by_slug` body `{"p_slug":"raysandjudys"}`, `apikey:<staging anon>` → `200`, one object; **assert exactly four keys** `{id, slug, display_name, branding}` (no `settings`/`created_at`); `id = 72e29f67-…`; `branding` is an object (founding = `{}`).
   - `{"p_slug":"definitely-not-a-tenant"}` → `200`, body `[]`.
   - Direct anon `GET .../rest/v1/tenants?select=*` → still RLS-blocked. (Confirms the RPC remains the only anon read path, now 4-col.)
   - **HALT** if the four-key assertion fails, `settings` appears, or unknown-slug returns anything but empty.
4. **Record (Claude):** § 13 — update the `resolve_tenant_by_slug` contract note (now returns `branding`; **`settings` still never returned**; rationale: branding is public display data). Deploy Log row. Commit:
   ```
   docs: 5.3 S1 — resolve_tenant_by_slug extended to return branding (4-col); anon contract re-verified
   ```

### S2 — F71: `FOUNDING_TENANT` → per-branch `config.js`

1. **Branch:** `git checkout -b feature/5.3-branding` off current `staging` (pulled).
2. > **PAUSE → Rick (edit `config.js` on the `staging` branch — agent never edits `config.js`):** add, alongside the existing `SUPABASE_*` globals:
   > ```js
   > window.FOUNDING_TENANT = {
   >   id: '72e29f67-39f7-42bc-a4d5-d6f992f9d790',
   >   slug: 'raysandjudys',
   >   display_name: "Ray & Judy's Book Stop",
   > };
   > ```
   > **Paste:** "staging config.js updated". (Rick commits `config.js` on `staging` via his normal flow, or hands it to the agent to commit as a `config.js`-only change — Rick's call; the agent does not author the values.)
3. **Verify the key is present (Claude):** `Select-String -Path config.js -Pattern "FOUNDING_TENANT"` → present with the staging id/slug. **HALT if absent** — `app.js` is about to depend on it.
4. **File-drift gate + edit (Claude, `app.js` on `feature/5.3-branding`):** re-read the `FOUNDING_TENANT` const (planning ~28–32) from disk; confirm byte-exact before replacing. Replace the hardcoded object with:
   ```js
   const FOUNDING_TENANT = window.FOUNDING_TENANT;
   ```
   Update the block comment (~12–26) — note the founding tenant now comes from per-env `config.js` (F71), not a hardcoded object.
5. **Verification greps (Claude):**
   - `Select-String -Path app.js -Pattern "72e29f67"` → **0 lines** (the staging UUID no longer literal in `app.js`).
   - `Select-String -Path app.js -Pattern "window.FOUNDING_TENANT"` → **1 line**.
   - `git diff` shows changes confined to the const + its comment.
6. **Smoke (Claude):** `cd …\playwright` → `.\run-smoke.ps1` — full suite green on `staging.pulllist.pages.dev` (founding still resolves via `window.FOUNDING_TENANT`; the staging config has the staging id). **Stop on any failure.**
7. **Commit + deploy to staging (Claude):**
   ```
   git add app.js
   git commit -m "refactor(tenant): FOUNDING_TENANT from per-env config.js, not hardcoded (F71, 5.3 S2)"
   git checkout staging
   git pull origin staging
   git merge --ff-only feature/5.3-branding
   git push origin staging
   ```
   (If Rick committed `config.js` separately on `staging`, ensure it's pulled before the merge so the deployed staging build has the key.)
8. **Record (Claude):** § 13 **F71 → resolved** (moved to per-env `config.js`; staging + main values; no hardcoded id in `app.js`). Deploy Log row. Commit:
   ```
   docs: resolve F71 — FOUNDING_TENANT moved to per-env config.js (5.3 S2)
   ```

### S3 — `Branding` module + branding-carrying resolution (app.js)

1. **File-drift gate (Claude):** re-read the `TenantContext` profile branch (planning ~85–89) and `initNav()` (~230–235) from disk; re-read `index.html`'s init/resolve path from disk (it has no `#main-nav`). **HALT on mismatch** — re-derive targets; do not force.
2. **Edit A — profile branch carries branding:** in `TenantContext.resolve()` branch 1, change `.select('id, slug, display_name')` → `.select('id, slug, display_name, branding')`.
3. **Edit B — add the `Branding` module** (the § 1.3 block) near `TenantContext`; expose it: `window.Branding = Branding;`.
4. **Edit C — wire `Branding.apply()` after resolve, on every page path:**
   - `initNav()`: immediately after `await TenantContext.resolve();`, add `Branding.apply(TenantContext.current());` (covers the 5 authed pages).
   - **index.html** (anon landing — no `initNav()`): after its own `await TenantContext.resolve()` (re-derive the exact site from disk), add `Branding.apply(TenantContext.current());`. If index.html does not currently call `resolve()` on the public path, add a minimal `await TenantContext.resolve(); Branding.apply(TenantContext.current());` in its init before first paint of brandable elements. (Confirm the exact shape from disk; the landing page is the headline anon-branding surface.)
5. **Verification greps (Claude):**
   - `Select-String -Path app.js -Pattern "Branding.apply"` → **≥1** (the call in `initNav()`; count derived from the final edit).
   - `Select-String -Path app.js -Pattern "const Branding ="` → **1**.
   - `Select-String -Path app.js -Pattern "display_name, branding"` → **1** (profile-branch SELECT).
   - `git diff` confined to `TenantContext`/`initNav`/the new `Branding` block.
6. **Smoke (Claude):** `.\run-smoke.ps1` — full suite green (founding `branding={}` ⇒ `apply()` no-ops ⇒ unchanged render). **Stop on any failure.**
7. **Commit + deploy to staging (Claude):**
   ```
   git add app.js
   git commit -m "feat(branding): Branding.apply() override layer + branding-carrying resolution (5.3 S3)"
   git checkout staging
   git pull origin staging
   git merge --ff-only feature/5.3-branding
   git push origin staging
   ```
8. **Record (Claude):** Deploy Log row. Doc commit:
   ```
   docs: 5.3 S3 — Branding module wired; profile branch carries branding; staging green
   ```

### S4 — HTML `data-*` hooks (store-name + logo slots)

1. **Re-grep the surface (Claude):** `Select-String -Path *.html -Pattern "Book Stop|bookstop_logo"` → confirm the § 1.4 "Yes"-row sites byte-exactly; **HALT** if a site moved/changed (re-derive). Touch **only** "Yes"-row slots.
2. **Edit (Claude, `feature/5.3-branding`):** add `data-tenant-name` to the store-name text element and `data-tenant-logo` to the logo `<img>` at each in-scope site. Keep the literal text/`src` as the default (founding renders it with zero JS). Example shapes (derive exact `old_str` from disk):
   - Footer: `Service provided by <span data-tenant-name>Ray &amp; Judy's Book Stop</span> &middot; Rockaway, NJ`
   - Login logo: `<img data-tenant-logo src="bookstop_logo.png" alt="Ray &amp; Judy's Book Stop" …>`
   - Login tagline / arrivals store-name block: wrap the store-name literal in `<span data-tenant-name>…</span>`.
   - **Footer must stay in sync across all five pages** (`CLAUDE.md` § Files That Must Stay in Sync) — apply the identical footer hook to `catalog.html`, `mylist.html`, `arrivals.html`, `subscriptions.html`, `admin.html`; copy from the last-touched canonical file.
3. **Verification greps (Claude):**
   - `Select-String -Path *.html -Pattern "data-tenant-name"` → one per in-scope store-name slot (count = sum of "Yes" rows; derive literally).
   - `Select-String -Path *.html -Pattern "data-tenant-logo"` → on `index.html`'s logo `<img>` (and any other in-scope logo).
   - Confirm **no** `data-tenant-*` on invoice/email/transactional copy ("No" rows untouched).
4. **Smoke (Claude):** `.\run-smoke.ps1` — full suite green; footer/nav still identical across pages (the must-stay-in-sync check). **Stop on any failure.**
5. **Commit + deploy to staging (Claude):**
   ```
   git add catalog.html mylist.html arrivals.html subscriptions.html admin.html index.html
   git commit -m "feat(branding): data-tenant-name/logo hooks at store-name + logo slots (5.3 S4)"
   git checkout staging
   git pull origin staging
   git merge --ff-only feature/5.3-branding
   git push origin staging
   ```
6. **Record (Claude):** Deploy Log row. Doc commit:
   ```
   docs: 5.3 S4 — HTML branding hooks added across pages; footer kept in sync; staging green
   ```

### S5 — Staging verification (unit + founding-invariant + optional live override)

1. **`Branding.apply()` unit spec (Claude, local-only Playwright/Node — pure-function, no DB):** build a test DOM with `[data-tenant-name]`, `img[data-tenant-logo]`, and read-back of `--accent`. Assert:
   - `apply({display_name:'X', branding:{primary_color:'#123456', logo_url:'https://e/x.png'}})` → `--accent` = `#123456`, `--accent-dim` = `rgba(18,52,86,0.15)`, every `[data-tenant-name]` text = `X`, every `img[data-tenant-logo]` src = the URL.
   - `apply({display_name:'Ray …', branding:{}})` → `--accent` unchanged from default, no DOM text/src mutation. **(Founding no-op.)**
   - `apply({branding:{primary_color:'not-a-color'}})` → malformed color ignored (`--accent` unchanged).
   - `apply({})` / `apply(null)` → no throw, no mutation.
2. **Founding-render invariant (Claude, staging alias):** load `staging.pulllist.pages.dev/catalog` (authed founding) and `index.html` (anon) → `--accent` resolves to `#e8321c` (the default), store-name text = "Ray & Judy's Book Stop", logo = `bookstop_logo.png`. **Identical to pre-5.3.** Capture a before/after note in the Deploy Log.
3. **Optional live override proof (Rick-in-the-loop — proves the override path with real data; fully reversible):**
   > **PAUSE → Rick (STAGING SQL Editor):**
   > ```sql
   > -- capture, then set a visible test branding on the founding tenant:
   > SELECT branding FROM public.tenants WHERE id = '72e29f67-39f7-42bc-a4d5-d6f992f9d790';
   > UPDATE public.tenants
   >   SET branding = '{"primary_color":"#1d4ed8","logo_url":"https://staging.pulllist.pages.dev/bookstop_logo.png"}'::jsonb
   >   WHERE id = '72e29f67-39f7-42bc-a4d5-d6f992f9d790';
   > ```
   > **Paste:** the captured original `branding` (should be `{}`). Then **Claude** loads the staging app (hard refresh) → confirms `--accent` is now blue (`#1d4ed8`) and the logo swapped. Then:
   > **PAUSE → Rick (STAGING SQL Editor):** revert:
   > ```sql
   > UPDATE public.tenants SET branding = '{}'::jsonb
   >   WHERE id = '72e29f67-39f7-42bc-a4d5-d6f992f9d790';
   > SELECT branding FROM public.tenants WHERE id = '72e29f67-39f7-42bc-a4d5-d6f992f9d790';
   > ```
   > **Paste:** post-revert SELECT → **must be `{}`**. **STOP if** branding is not back to `{}` (the founding-render invariant depends on it). Claude reloads and confirms the default red `--accent` + original logo are back.
   - *(If Rick prefers zero live data mutation, skip step 3 — the step-1 unit spec is the gating proof; note the skip honestly in the Deploy Log.)*
4. **Full Playwright (Claude):** `.\run-smoke.ps1` — all green incl. tenant-isolation (F15/F20). Branding rendering must not widen any read or cross tenants.
5. **Record (Claude):** Deploy Log row (unit-spec result, founding-invariant before/after, the live-override result or honest skip, suite result). Doc commit:
   ```
   docs: 5.3 S5 — Branding.apply unit-verified; founding-render invariant + override proof green on staging
   ```

### S6 — Prod promotion (Rick's chosen window)

**Order is load-bearing: `main` `config.js` must carry `FOUNDING_TENANT`, and the prod 4-col RPC must exist, before the app.js prod promotion.**

1. > **PAUSE → Rick (edit `config.js` on the `main` branch — before the promotion):** add the prod `FOUNDING_TENANT`:
   > ```js
   > window.FOUNDING_TENANT = {
   >   id: '20941129-c35a-476d-ae21-44b8f77af89c',
   >   slug: 'rjbookstop',
   >   display_name: "Ray & Judy's Book Stop",
   > };
   > ```
   > **Paste:** "main config.js updated". **Claude verifies:** `git show main:config.js | Select-String "FOUNDING_TENANT"` → present with the **prod** id/slug. **STOP if absent** — the `git checkout main -- config.js` step will otherwise preserve a `FOUNDING_TENANT`-less prod config, breaking the anon fallback.
2. > **PAUSE → Rick (PROD SQL Editor `plgegklqtdjxeglvyjte`):** run the § 1.1 `CREATE OR REPLACE FUNCTION` + `REVOKE` + `GRANT` block verbatim (identical to staging S1). Verify with the S1-step-2 queries. **Paste:** definition + `proacl`. **Expected:** 4-col body (`id, slug, display_name, branding`), `SECURITY DEFINER`, hardened search_path; `anon`+`authenticated` EXECUTE, not PUBLIC.
3. **Prod anon-contract check (Claude, `curl.exe` with the PROD anon key):** `rpc/resolve_tenant_by_slug` `{"p_slug":"rjbookstop"}` → `200`, one object, **exactly four keys** `{id, slug, display_name, branding}`, prod founding UUID `20941129-…`, `branding` = `{}`; unknown slug → `[]`; direct anon `GET /tenants?select=*` → RLS-blocked. **HALT** on any mismatch — do not promote app.js against an unverified prod RPC.
4. **App.js + HTML prod promotion (standard workflow — Claude prepares, Rick merges):**
   ```
   git checkout main
   git pull origin main
   git merge staging --no-commit --no-ff
   git checkout main -- config.js     # preserve prod config (incl. prod FOUNDING_TENANT from step 1)
   # F59 diff assertion — app.js + the HTML pages MUST differ (this promotion changes them):
   foreach ($f in @('app.js','mylist.html','arrivals.html','admin.html')) {
     $d = git diff "main:$f" "staging:$f" 2>$null
     if ($f -eq 'app.js' -and -not $d) { Write-Host "ERROR: app.js identical to main — 5.3 must change it"; }
     elseif ($d) { Write-Host "ok: $f differs" } else { Write-Host "WARN: $f identical (verify expected)" }
   }
   git commit -m "feat(branding): per-tenant branding render + FOUNDING_TENANT from config (5.3 prod)"
   git checkout -b feat/5.3-branding-prod
   git push origin feat/5.3-branding-prod
   ```
   Open PR `feat/5.3-branding-prod → main`. **Rick verifies `config.js` is NOT in the PR diff** (the prod `FOUNDING_TENANT` stays put via the checkout) **and merges.** CF Pages auto-deploys `main` at `pulllist.app`.
5. **Post-deploy verification (Claude + Rick):**
   - `curl.exe -s https://pulllist.app/app.js` → contains `window.FOUNDING_TENANT` + `Branding.apply`, does **not** contain `72e29f67`.
   - `curl.exe -s https://pulllist.app/config.js` → contains `FOUNDING_TENANT` with the **prod** id `20941129-…` / slug `rjbookstop`.
   - **Founding-apex invariant (Rick, browser):** `pulllist.app` (no `?t=`) loads as founding; `--accent` = `#e8321c`; store-name + logo = today's; `TenantContext.current().id` = `20941129-…`.
   - **Write-smoke (Rick):** reserve one item as a test user → row lands in prod `preorders` with the correct founding `tenant_id` → cancel it. (Regression guard; branding is read-only.)
6. **Record (Claude):** Deploy Log row (main config check, prod RPC verified, PR #, prod commit, write-smoke row). Doc commit:
   ```
   docs: 5.3 S6 — prod RPC extended + branding promoted; founding-apex invariant + write-smoke verified
   ```

### S7 — Closeout (run once, when every § 5 box is ticked)

1. Tick the § 5 boxes with inline result notes (5.2 pattern).
2. This file: Status line → **Complete** + date; Last-updated line.
3. Parent (`phase-5-second-tenant-onboarding.md`): row 5.3 → **Complete** + date; row 5.4 → **Planning** only when its plan file exists (next session writes it); § Carry-Forward / Phase Completion Criteria branding box tickable.
4. `docs/technical-reference.md`: § 4.1 branding note ("read by `Branding.apply()` as of 5.3"); § 13 **F71 → resolved**; RPC contract note reflects the 4-col branding-returning shape.
5. `CLAUDE.md` § Current Migration Phase: active sub-deploy → **5.4 (plan not yet written)**; last-completed → 5.3; § Known Out-of-Scope Items: update the "Per-tenant branding rendering" line to "Complete (5.3)"; open-findings line updated (F71 resolved; remaining open: F64 item 5 pre-5.4; next free ID **F72** unless 5.3 filed one). **Re-flag F64 item 5 to Rick** — must land before 5.4.
6. Commit:
   ```
   docs: close Phase 5.3 (per-tenant branding); advance pointer to 5.4 planning
   ```
7. End-of-session status update per `CLAUDE.md` § Anti-Drift Rules (changed / verified / left / filed / new IDs).

---

## 5. Completion criteria (all must be checked before parent row 5.3 → Complete)

- [ ] S1: `resolve_tenant_by_slug` on **staging** returns exactly `id, slug, display_name, branding` (4 cols, no `settings`/`created_at`); `pg_get_functiondef` shows `SECURITY DEFINER` + hardened `search_path`; `proacl` = `anon`+`authenticated`, not PUBLIC; anon `curl.exe` returns a four-key object for `raysandjudys` (branding `{}`) and `[]` for an unknown slug; direct anon `tenants` SELECT still RLS-blocked.
- [ ] S2 (F71): `FOUNDING_TENANT` lives in per-branch `config.js` (staging values on `staging`); `app.js` reads `window.FOUNDING_TENANT` with **no** hardcoded UUID (`Select-String "72e29f67"` → 0 in `app.js`); full Playwright green; **F71 resolved** in § 13.
- [ ] S3: `Branding` module present; `Branding.apply()` called after `resolve()` on `initNav()` and the index.html anon path; profile branch SELECTs `branding`; full Playwright green; founding render unchanged.
- [ ] S4: `data-tenant-name`/`data-tenant-logo` hooks added at the § 1.4 "Yes"-row store-name + logo slots across the six pages; footer identical across the five authed pages; no hooks on invoice/email/transactional copy; full Playwright green.
- [ ] S5: `Branding.apply()` unit spec passes (override-when-present; **no-op when `branding={}`/absent**; malformed color ignored; logo via `src` only; null-safe); founding-render invariant verified identical to pre-5.3; live override proof green **and reverted to `{}`** (or honestly skipped); full Playwright incl. tenant-isolation green.
- [ ] S6: `main` `config.js` carries the **prod** `FOUNDING_TENANT` before promotion; prod `resolve_tenant_by_slug` is 4-col and anon-verified (four-key, prod founding UUID, branding `{}`) **before** app.js promotion; app.js + HTML promoted via the standard workflow (`config.js` not in PR diff; F59 assertion confirms app.js changed); founding-apex invariant verified on `pulllist.app` (default `--accent`, default name/logo, prod founding UUID); write-smoke passed.
- [ ] Founding-tenant behavior unchanged (parent invariant): full Playwright incl. tenant-isolation green at the S2/S3/S4/S5 staging gates and the S6 prod write-smoke; founding render byte-identical to pre-5.3.
- [ ] F71 → resolved in § 13; RPC contract note updated (branding returned, `settings` never); any new defect filed from **F72**+ resolved or deferred-with-owner.
- [ ] Deploy Log complete (one row per executed step); all doc changes committed to `staging`; parent row 5.3 → **Complete** + date; `CLAUDE.md` pointer advanced to 5.4 planning.

---

## 6. Rollback (per step; pre-captures taken before every change)

- **S1 (staging RPC extend):** `CREATE OR REPLACE` back to the 3-col body (captured in the S1 pre-capture). Additive change; reverting it just removes the `branding` key from anon results — `Branding.apply()` then no-ops everywhere (safe). No data surface.
- **S2 (F71 / config.js):** revert the `app.js` commit (restores the hardcoded const) and/or remove the `config.js` key. Because `app.js` reverts to the prior hardcoded object, founding still resolves. (Keep `config.js` + `app.js` changes paired on revert to avoid an `undefined` `FOUNDING_TENANT`.)
- **S3 (Branding module):** revert the `feature/5.3-branding` S3 commit — removes `Branding.apply()` calls; pages render hardcoded defaults; the 4-col RPC is harmless (unused branding key).
- **S4 (HTML hooks):** revert the S4 commit — `data-tenant-*` attributes vanish; literal text/`src` remain (they were always the default).
- **S5:** verification only — the live override is reverted in-step (founding `branding` back to `{}` with a verifying SELECT). No standing change.
- **S6 (prod):** app.js/HTML — re-deploy the prior `main` commit via the standard path. Prod RPC — `CREATE OR REPLACE` back to 3-col (or leave 4-col; harmless and unused once app.js is rolled back). The per-env `FOUNDING_TENANT` in `main` `config.js` is independent and stays. The founding default + empty-branding no-op means even a fully rolled-back app renders founding correctly on `pulllist.app`.
- Nothing in 5.3 touches customer data; Tier-3 forward-fix pressure does not apply.

---

## 7. References

- Decision (F71): Rick, 5.3 planning 2026-06-15 — **Option B (per-env `config.js`)**; "prioritize efficiency; branding can differ across staging vs prod." Per-env branding is delivered from each env's own `tenants.branding` via the RPC; the `config.js` const carries only id/slug/display_name as the offline founding fallback.
- Decision (branding delivery): Rick, 5.3 planning 2026-06-15 — **extend `resolve_tenant_by_slug`** to return `branding` (single round-trip; branding is public display data); `settings` jsonb remains unexposed.
- Decision (branding surface): Rick, 5.3 planning 2026-06-15 — **color + name + logo** as an override layer; email/invoice copy out of scope (email branding is a parent § Out of Scope item).
- Parent: `docs/phase-5-second-tenant-onboarding.md` (row 5.3; § In Scope 5.3; § Out of Scope email branding; founding-invariant completion criterion).
- Shape mirror: `docs/phase-5.2-slug-id-routing-rpc.md` (execution model, pause-block format, deploy-log resume protocol, F59 diff-assertion + `config.js` checkout on prod promotion).
- Findings: `docs/technical-reference.md` § 13 — **F71** (`FOUNDING_TENANT` staging id/slug; this sub-deploy resolves it) and the `resolve_tenant_by_slug` contract note (this sub-deploy extends it to 4-col). **Next free ID at planning: F72.**
- Code: `app.js` `FOUNDING_TENANT` const (~28–32), `TenantContext` profile branch (~85–89) + `initNav()` resolve (~230–235); `index.html` anon landing init (re-derive from disk — no `#main-nav`, `initNav()` returns early there). `style.css` `:root` `--accent`/`--accent-hover`/`--accent-dim` (~19–21).
- Schema: `docs/technical-reference.md` § 4.1 `tenants.branding` jsonb (default `{}`; no app reads it pre-5.3).
- Curl pattern for tenant-aware Supabase calls: `test-magic-link.ps1` (`curl.exe --data-binary @file`; `Invoke-RestMethod` mangles JSON — § Known Issues).
- Projects: staging `puoaiyezsreowpwxzxhj`, prod `plgegklqtdjxeglvyjte`. Founding tenant UUID (staging) `72e29f67-39f7-42bc-a4d5-d6f992f9d790`; prod founding `20941129-c35a-476d-ae21-44b8f77af89c` / slug `rjbookstop` (also in `catalogs\scripts\phase-4-prod-tenant-uuid.txt`, local-only).
- **Flagged for Rick (out of 5.3 scope):** F64 item 5 DDL (`preorders_user_id_fkey` → `user_profiles` NO ACTION on prod) still has no landed owner and **must execute before 5.4**. Either give it a home in 5.4's plan or an explicit housekeeping commit; do not absorb into 5.3.

---

## 8. Deploy log (filled during execution)

| Date | Step | Result | Notes |
|---|---|---|---|
| 2026-06-15 | S1 | Green | Staging `resolve_tenant_by_slug` extended to 4-col (`id, slug, display_name, branding`). DROP + CREATE (single-quote body); REVOKE re-run after CREATE to clear Postgres default PUBLIC grant. `proacl` clean (no PUBLIC). Anon curl: `raysandjudys` → 4 keys + `branding: {}`; unknown slug → `[]`; direct tenants → permission denied. |
| | S2 | | |
| | S3 | | |
| | S4 | | |
| | S5 | | |
| | S6 | | |
| | S7 | | |

---

**Last updated:** 2026-06-15 (plan written; not yet executed — Status: Planning)
