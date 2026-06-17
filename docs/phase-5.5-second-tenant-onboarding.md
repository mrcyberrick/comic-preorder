# Phase 5.5 — Second-Tenant Onboarding + Two-Tenant Production Soak

**Status:** **Planning** — plan written 2026-06-17; not yet executed. Active sub-deploy.
**Parent plan:** `docs/phase-5-second-tenant-onboarding.md` (sub-deploy row 5.5 — the final Phase 5 sub-deploy)
**Predecessor:** Phase 5.4 — Tenant Signup — **Complete 2026-06-17** (`register-customer` un-pinned to per-tenant webhook secret; gated `register-tenant` operator EF live on **both** envs — 9th EF; per-tenant webhook secrets in `tenants.settings`; §4.1 FK-ordered teardown proven end-to-end in S4; F34/F64-item-5 resolved; F72 filed (email-branding deferral); F73/F74 resolved).
**Branches:** This sub-deploy is **operational + doc-only**. It writes **no `app.js` / `*.html` / `config.js` / `style.css` / Edge-Function source** — every engineering tool it needs already shipped in 5.1–5.4 (subdomain resolver + slug→id RPC from 5.2; `Branding.apply()` from 5.3; `register-tenant` + per-tenant webhook secret from 5.4). 5.5's work is: *invoke* those tools against a real second tenant, provision its Cloudflare custom domain, run the two-tenant isolation checklist + soak, and generalize the onboarding runbook. Doc commits (this plan, the soak log, the generalized runbook, the §13/parent/CLAUDE.md closeouts) → `staging` directly. **If 5.5 discovers a real need to change any source file, STOP and ask** — it is a scope change (likely a new finding, possibly a follow-on sub-deploy).
**Execution model:** **CLI-orchestrated, Rick-in-the-loop.** A Claude Code CLI (Sonnet) session runs this file top to bottom. It executes every repo / doc / local-script / Playwright / `curl.exe` step itself, and **pauses at every production database step, every Supabase dashboard / CLI platform action, every GoTrue admin-API call that writes auth users, every `register-tenant` invocation that creates a real prod tenant, and every Cloudflare dashboard action (custom-domain add, DNS, TLS)** — handing Rick the exact SQL / clicks / curl / values and **waiting for pasted results before continuing**. **Self-contained — no chat context required.**
**Rollback complexity:** **One-way once tenant 2 takes real customer writes** (parent table). 5.5 is deliberately sequenced so that does **not** happen inside the sub-deploy: tenant 2 is **pilot/seeded only** throughout the soak (decision: Rick, 5.5 planning 2026-06-17), so the §4.1 FK-ordered teardown remains a clean rollback for the entire 5.5 window. Opening tenant 2 to **real** customers is the **operational go-live that happens AFTER 5.5 closes** — that is the one-way step, guarded by the generalized runbook (§ S5) and the F72 email-branding check (§ 1.6). The staging full-dress rehearsal tenant (§ S1) is torn down in-step (verified 0 rows).

> **Steps Claude never runs itself.** (1) Any Supabase **SQL Editor** statement on **prod** (`plgegklqtdjxeglvyjte`) — tenant-2 verification SELECTs, branding UPDATE, soak isolation probes, any teardown. (2) Any **GoTrue admin-API** call that creates/deletes `auth.users` on prod (tenant-2 admin via `register-tenant`; the staging rehearsal admin + customers; any teardown). (3) Every **`register-tenant` invocation that creates a standing tenant** (staging rehearsal create *and* the prod tenant-2 create) — Claude prepares the exact curl + payload + the `<TENANT_PROVISION_SECRET>` placeholder; Rick substitutes the secret, runs it, and pastes the response. (4) Every **Cloudflare** dashboard action — the `<slug>.pulllist.app` custom-domain add, DNS record, TLS-cert confirmation. (5) Any Supabase **dashboard** platform action (none expected — no EF deploy/secret change in 5.5; if one becomes necessary, STOP and ask). Each appears below as a **`PAUSE → Rick … → paste result → match expected → continue / STOP`** block. Claude prepares the exact inputs, the expected result, and the stop condition around every pause. The agent itself runs only: read-only repo/doc work, `Select-String`/local verification, `curl.exe` *gate* probes against the deployed functions (no standing writes), the Playwright suite, and the staging-side rehearsal orchestration.

> **5.5 spans multiple sittings by design** — the soak (§ S4) is **one full monthly import cycle** (decision below) and cannot be compressed. The durable state is the **Deploy Log (§ 8)** plus the **Soak Log** (`docs/phase-5.5-soak-log.md`, committed, modeled on `docs/phase-4.1-soak-log.md`): every session appends one row per completed step / soak observation. A resuming session reads both logs, re-verifies the last recorded step against live state (a recorded tenant create is re-verified by a SELECT for the tenant row; a recorded custom-domain add by resolving the host; the rehearsal teardown by the 0-row SELECT), and continues from the next unexecuted step. Every doc edit is committed before the session ends.

> **Founding-tenant invariant (parent completion criterion for every 5.x sub-deploy) — and how 5.5 satisfies it.** 5.5 adds a *second* tenant alongside the founding tenant on production. The hard invariant: **the founding tenant's customer surface, admin surface, analytics, Edge-Function paths, and monthly import are byte-/behavior-identical to today throughout 5.5.** Because 5.5 changes **no source file**, the founding code path is literally unchanged; the only new variables are (a) a second `tenants` row + its data, (b) a new Cloudflare custom domain, (c) tenant-2 branding. Every gate runs the full Playwright suite including the tenant-isolation specs (F15/F20); the founding write-smoke on `pulllist.app` runs at S2 (tenant-2 live) and again after the soak's import cycle (S4). The zero-cross-tenant-leakage proof (§ S3) is run against the **real** tenant 2, not a synthetic canary — this is the parent's headline completion gate.

---

## 0. Pre-flight (run at the top of every 5.5 session; halt on any mismatch)

### 0.1 Read before doing anything
- `CLAUDE.md` in full; confirm § Current Migration Phase active sub-deploy = **5.5**. Note § Edge Functions (9 EFs; `register-tenant` operator-gated via `x-operator-secret` = `TENANT_PROVISION_SECRET`, live on **both** projects; `register-customer` resolves tenant from the per-tenant `tenants.settings->>'mailerlite_webhook_secret'`), § Credential Safety (service-role/operator secrets local-only; **agent never edits `config.js`** — not touched here anyway), § Standard Deployment Workflow, § Anti-Drift Rules, § Known Issues (`curl.exe --data-binary @file`; `Invoke-RestMethod` mangles JSON).
- `docs/phase-5-second-tenant-onboarding.md` — Sub-Deploys row 5.5; § In Scope **5.5**; § Approach Decisions ("signup before onboarding (5.4 before 5.5), onboarding gated"); § Phase Completion Criteria (**this sub-deploy must make every box tickable — 5.5 is the last one**); § Rollback row 5.5 (one-way after real customer writes); § Out of Scope (**multi-tenant email branding is OUT of Phase 5** — F72 stays deferred; § 1.6).
- This file in full — including the Deploy Log (§ 8). If any rows exist, this is a resume session.
- `docs/phase-5.5-soak-log.md` if it exists (created at S4 start) — the soak's durable state.
- `docs/phase-4.1-canary-procedure.md` — the FK-ordered **teardown** order is load-bearing; reused for the S1 rehearsal teardown and as the standing rollback for the real tenant 2 (clean only while tenant 2 is pilot/seeded).
- `docs/technical-reference.md`: § 4.1 (`tenants` table — `tenants_slug_format_check` DNS-safe regex; `branding`/`settings` jsonb; service-role-only creation, no INSERT/DELETE RLS); § 11.1–11.3 (9-EF inventory; **`register-tenant` contract** — `x-operator-secret` gate, slug rules + reserved denylist, `23505→409 slug_taken`, GoTrue admin user, `user_profiles status='active' is_admin=true`, non-atomic compensation, returns `{ tenant_id, admin_user_id, slug, webhook_secret }`; **`register-customer`** per-tenant-secret resolution; **F72** email-branding note); § 13 **F72** (open, deferred) and the highest filed finding ID (**next free = F75** at planning).
- `app.js` `TenantContext` — the `tenantSlugFromHostname()` subdomain resolver and the `?t=<slug>` / sessionStorage branches (5.2). **Read from disk; do not infer** — confirm the host→slug parse and the non-tenant-host allowlist before relying on `<slug>.pulllist.app` routing (§ 1.2).

### 0.2 Gates (halt if any fail)
- `git rev-parse --abbrev-ref HEAD` → `staging`; `git status` → clean (the known-stray untracked `docs/status-slide.html` is acceptable; anything else, stop and ask).
- `git pull origin staging` → up to date (or fast-forward) before any edit.
- **5.4 artifacts confirmed live on PROD before any 5.5 onboarding** (anti-drift — verify, don't trust the doc): `register-tenant` deployed on prod (probe: no `x-operator-secret` → 401); `register-customer` un-pinned on prod (5.4 S6 Deploy Log green); prod founding webhook secret in prod `tenants.settings` (5.4 S6). If any is not live, STOP — 5.5 has no foundation.
- `docs/technical-reference.md` § 13: confirm the highest filed finding ID. At planning the next free ID is **F75**. New defects discovered during 5.5 are filed from **F75** — never guessed or reused.
- **Tenant-2 onboarding inputs gathered from the operator** (decision: operator-supplied at execution — § 1.1). The chosen `slug` passes `tenants_slug_format_check` AND is not on the `register-tenant` reserved denylist (`www, app, api, admin, staging, prod, mail, ftp, blog, dev, test, canary, pulllist, raysandjudys, rjbookstop`). If the desired slug is reserved, STOP and ask the operator for an alternative.
- **Cloudflare access confirmed** for the Pages project serving `pulllist.app` (custom-domain add requires dashboard access). If not available, STOP — the chosen routing model (dedicated subdomain) cannot proceed; do not silently fall back to `?t=`.

### 0.3 Commit discipline
- Each S-step's doc update (Deploy Log row, soak-log entry, §13 / parent / CLAUDE.md closeouts) is its own doc-only commit to `staging`, with finding ID(s) where relevant — exact messages inline.
- **No feature branch, no source edit.** 5.5 touches only `docs/**` and `CLAUDE.md`. If a source change is ever required, STOP and ask (scope change).
- Push `origin staging` after each commit; the Deploy Log / Soak Log row lands in the same commit as the step it records.

### 0.4 Files / surfaces touched by this sub-deploy

| File / target | Change | Branch / actor |
|---|---|---|
| Production DB (`public.tenants`, `public.user_profiles`, etc.) | **S2:** the real tenant 2 row + first admin (via `register-tenant`, service-role + GoTrue); **S2:** tenant-2 `branding` UPDATE; **S1/S3/S4:** read-only verification SELECTs; **S1 teardown / rollback:** §4.1 FK-ordered deletes | Rick, prod SQL Editor + GoTrue (Claude prepares; Rick runs) |
| Staging DB (`public.tenants`, …) | **S1 rehearsal:** create tenant 2's shape via `register-tenant`, verify, **then tear down** (§4.1) — verified 0 rows | Rick, staging SQL Editor + GoTrue |
| `register-tenant` Edge Function (both projects) | **Invoked** (not modified) to create the rehearsal tenant (staging, S1) and the real tenant 2 (prod, S2) | curl: Claude prepares, Rick runs (creates auth users / prod rows) |
| Cloudflare Pages project (`pulllist.app`) | **S2:** add `<slug>.pulllist.app` as a single custom domain (manual; **no wildcard** — wildcard DNS/TLS is the Phase 6 gate); confirm DNS + TLS cert issued | Rick, Cloudflare dashboard |
| MailerLite (tenant 2) | **S2 (only if the pilot uses webhook registration):** configure tenant 2's MailerLite webhook URL with its `register-tenant`-generated `webhook_secret`. If the pilot does not use MailerLite registration during the soak, **defer + note** — register a pilot customer via `create-paper-customer` / admin invite instead | Rick (external service) |
| Playwright suite (local-only, never committed) | Run as-is at every gate (F15/F20 tenant-isolation with two tenants present); **no new specs required** (5.5 adds no code path) — optional ad-hoc two-tenant browser checks | Claude |
| Canary/rehearsal scratch (`phase-4.1-canary-uuids.txt`, local-only) | **S1:** regenerated for the staging full-dress rehearsal; rehearsal tenant created **through** `register-tenant`, torn down per §4.1 | Claude + Rick (GoTrue/SQL) |
| `docs/phase-5.5-soak-log.md` (**new, committed**) | **S4:** daily/periodic soak observations (modeled on `phase-4.1-soak-log.md`) | `staging` (doc-only) |
| `docs/tenant-onboarding-runbook.md` (**new, committed**) | **S5:** generalized, operational tenant-N+1 onboarding runbook (post-5.5 onboarding is operational, not an engineering phase) | `staging` (doc-only) |
| `docs/technical-reference.md` | **S6:** § 11 EF inventory unchanged at 9 (note tenant 2 now exercises the per-tenant secret + operator EF in production); F72 disposition re-confirmed (deferred — re-evaluate at tenant-2 real-customer go-live); any new findings F75+ | `staging` (doc-only) |
| `docs/phase-5-second-tenant-onboarding.md` | **S6:** row 5.5 → Complete; **Phase 5 Phase Completion Criteria all ticked**; parent Status → Phase 5 Complete | `staging` (doc-only) |
| `CLAUDE.md` | **S6:** § Current Migration Phase → Phase 5 Complete; active sub-deploy → none (Phase 6 not started, stub exists); last-completed phase → Phase 5; § Known Out-of-Scope updates; open-findings line | `staging` (doc-only) |

**Not touched:** `app.js` / `*.html` / `config.js` / `style.css` (no client/UI change — routing + branding already shipped 5.2/5.3); `import.js` / `import-staging.js` (**see § 1.5** — the soak's import-cycle anchor is the founding tenant's normal monthly import running clean with tenant 2 present; importing a full tenant-2 catalog would need import-script generalization, which is a **follow-on, not 5.5** — file if raised); all 9 Edge-Function **sources** (invoked, not modified); `tenants` RLS (no INSERT/DELETE policy is the intended design — `register-tenant` writes via service-role).

---

## 1. Planning-time design (2026-06-17) — re-verify at execution

### 1.1 Tenant-2 identity (operator-supplied at execution)
**Decision (Rick, 5.5 planning 2026-06-17): operator-supplied at execution.** This plan is written generically; the real second tenant's identity is provided when a real bookshop is ready. The onboarding inputs `register-tenant` needs (§ 11 contract):

| Input | Source | Constraint |
|---|---|---|
| `slug` | operator | lowercase DNS-safe (`^[a-z0-9][a-z0-9-]*[a-z0-9]$` or single char); not reserved (denylist § 0.2); becomes `<slug>.pulllist.app` |
| `display_name` | operator | the tenant's customer-facing name |
| `admin_email` | operator | a real, reachable mailbox the tenant's admin controls (the magic link / credentials go here) |
| `contact_email?` / `contact_phone?` / `location?` | operator | optional metadata |
| `branding?` | operator | jsonb: name / colors / logo override layer (`Branding.apply()`, 5.3). May be passed at create or set via a follow-up `tenants.branding` UPDATE (§ S2) |

5.5 **executes and completes when a real tenant exists.** If no real tenant is ready, 5.5 may run the **staging full-dress rehearsal (S1) only** and then pause at the S2 gate until the operator provides a real tenant — record the pause honestly in the Deploy Log; do not invent a tenant to "finish."

### 1.2 Routing — dedicated subdomain (manual, no wildcard)
**Decision (Rick, 5.5 planning 2026-06-17): dedicated subdomain `<slug>.pulllist.app`, provisioned as a single manual Cloudflare Pages custom domain.** Wildcard DNS/TLS is explicitly the **Phase 6** gate — 5.5 adds exactly **one** custom domain for the one real tenant, no wildcard.

- The resolver already exists: `app.js` `TenantContext.tenantSlugFromHostname()` (5.2) parses the host's leading label → slug → `resolve_tenant_by_slug` RPC → tenant. The non-tenant-host allowlist (5.2 § 1.3: apex `pulllist.app`, `staging.pulllist.pages.dev`, `pulllist.pages.dev`, `localhost`, `*.pages.dev` previews) ensures the founding tenant is unaffected.
- **Re-verify at execution (anti-drift):** read `tenantSlugFromHostname()` from disk; confirm `<slug>.pulllist.app` parses to exactly `<slug>` and that `<slug>` is not swallowed by the allowlist. This is the first time the subdomain path runs against a *real* tenant domain — S3 verifies routing explicitly.
- **Staging caveat (S1 rehearsal):** `*.pages.dev` cannot mint a per-tenant custom domain easily; the staging rehearsal verifies tenant-2 resolution via the `?t=<slug>` query path + a host-parse unit check, not a live staging subdomain. The live subdomain is exercised for real on **prod** at S2/S3. Note this asymmetry in the Deploy Log.
- TLS: Cloudflare auto-provisions the certificate for the added custom domain; S2 confirms the cert is issued and HTTPS resolves before routing is trusted.

### 1.3 Production isolation verification — the 4.1-style checklist against the REAL tenant 2
**This is the parent's headline completion gate** (§ Phase Completion Criteria: "Zero cross-tenant leakage … verified with the 4.1-style canary checklist against the *real* second tenant"). 5.5 reuses the Phase 4.1 V7 cross-tenant probe surface (`docs/phase-4.1-soak-log.md` § V7) but runs it against the real tenant 2 + founding on **prod**, with **pilot/seeded** tenant-2 data:

- **Data isolation (both directions, per table):** founding admin → tenant-2 rows = 0, and tenant-2 admin → founding rows = 0, across `preorders`, `user_profiles`, `subscriptions`, `catalog`, `weekly_shipment`, `reservation_history`, `usage_events`.
- **Analytics/RPC scoping:** `get_popular_series` (and any tenant-scoped RPC) returns only the caller's tenant rows.
- **Admin-surface scoping:** `admin.html` customer list, bagging tab, stats — each scoped to the caller's tenant.
- **Customer-page scoping:** `catalog` / `mylist` / `arrivals` / `subscriptions` for a tenant-2 pilot user show only tenant-2 data; founding user unaffected.
- **Edge-Function path scoping:** `notify-customers`, `send-my-list`, `register-customer` (per-tenant secret routes to tenant 2), `create-paper-customer`, `invite-customer`, `approve-customer`, `claim-paper-customer` — each scoped to the acting tenant (re-confirm the F34-residual behaviors against tenant 2).
- **Branding:** `<slug>.pulllist.app` renders tenant-2 branding; `pulllist.app` renders founding branding unchanged (5.3).

A non-zero in any cross-tenant probe is a **STOP** → file a finding (F75+) → do not proceed to soak.

### 1.4 Soak — one full import cycle, no buffer
**Decision (Rick, 5.5 planning 2026-06-17): one full monthly import cycle, no additional fixed-day buffer.** The parent floor is "not less than one full import cycle"; the import is monthly, so one cycle ≈ one catalog rollover.

- **Soak window:** begins when tenant 2 is live + isolation-verified on prod (end of S3); the close gate is satisfied when **(a)** at least one complete monthly prod import has run with both tenants present, **(b)** post-import isolation re-verification (§ 1.3 abbreviated) is green, **(c)** founding Playwright green and **(d)** no customer-reported regressions across the span. The **import boundary is the riskiest event** and the explicit anchor — the soak is not closeable before it; no extra buffer is added after it (per the decision).
- **Tenant 2 stays pilot/seeded for the entire soak** (rollback-tier decision) — no real customer writes — so the §4.1 teardown remains a clean rollback throughout. Real-customer go-live is the post-close operational step (§ S5 runbook + § 1.6 F72 check).

### 1.5 Import-cycle anchor — scope boundary (re-confirm at execution)
The prod `import.js` hard-codes the founding tenant id (`CLAUDE.md` § Monthly Import + § Environment Facts). **5.5 does not modify the import script** (no Phase 5 scope item authorizes multi-tenant import generalization). Therefore the soak's "one full import cycle" is satisfied by the **founding tenant's normal monthly import running with tenant 2 present**, proving:

- the founding import touches only founding rows (upsert key + all writes carry founding `tenant_id`);
- tenant 2's seeded catalog/data is **untouched** by the founding import (no cross-tenant bleed; auto-reserve scoped to founding subscribers only);
- post-import isolation probes (§ 1.3) remain zero in both directions.

A **full tenant-2 catalog import** (its own distributor data, its own monthly run) requires import-script generalization and is a **follow-on, not 5.5** — **file it (F75+) if the operator needs tenant 2 to have a live monthly import**, and surface it; do not extend scope inline. (Re-confirm at execution that `import.js` is still founding-pinned before relying on this boundary.)

### 1.6 Email-branding boundary (F72) — a go-live prerequisite, not a 5.5 fix
After the 5.4 un-pin, a customer registered via tenant 2's webhook lands correctly in tenant 2, **but `register-customer`'s email copy is still founding-branded** (F72, deferred; multi-tenant email branding is OUT of Phase 5). Because tenant 2 is **pilot/seeded** during the soak (no real `register-customer` customers), F72 does **not** surface to real tenant-2 customers inside 5.5. **F72 becomes a prerequisite to evaluate at tenant-2's real-customer go-live** (post-close) — the generalized runbook (§ S5) flags it, and Phase 6 / a dedicated email-branding sub-deploy may act on it. 5.5 re-confirms F72's deferred disposition in § 13; it does not fix it.

---

## 2. In scope

1. **S0** — **Readiness gate (no writes):** confirm 5.4 artifacts live on prod (`register-tenant` gated, `register-customer` un-pinned, prod founding webhook secret in `tenants.settings`); gather + validate operator-supplied tenant-2 inputs (slug passes format + not reserved); re-verify the §4.1 teardown vs live schema; confirm Cloudflare access; confirm `import.js` still founding-pinned (§ 1.5). HALT on any miss.
2. **S1** — **Staging full-dress rehearsal + verified teardown (end-to-end):** create tenant 2's shape on **staging** via `register-tenant`; verify branding renders (`Branding.apply()`); verify `?t=<slug>` + host-parse resolution; seed pilot catalog/customer data; run the full 4.1-style two-tenant isolation checklist (§ 1.3) + full Playwright (F15/F20) with founding + rehearsal tenant present; **then tear down per §4.1 — verify 0 rows, founding intact.** Proves the whole onboarding + isolation + teardown before any prod write.
3. **S2** — **Production onboarding (Rick's window):** create the **real** tenant 2 on **prod** via `register-tenant` (capture `tenant_id`, `admin_user_id`, `webhook_secret`); set tenant-2 `branding`; add `<slug>.pulllist.app` as a Cloudflare custom domain + confirm DNS/TLS; verify the subdomain routes to tenant 2 and `pulllist.app` still routes to founding; hand the admin magic link/credentials to the operator; (optional, if the pilot uses it) configure tenant 2's MailerLite webhook URL with its secret, else defer + note. Founding write-smoke on `pulllist.app`.
4. **S3** — **Production two-tenant isolation verification (real tenant 2):** run the full 4.1-style cross-tenant probe matrix (§ 1.3) against founding + the real tenant 2 on prod — **zero cross-tenant leakage** across every customer page, admin surface, analytics RPC, and Edge-Function path; branding correct per host; full Playwright green. **STOP + file** on any non-zero.
5. **S4** — **Two-tenant production soak (one full import cycle):** maintain the soak through ≥1 complete monthly prod import with both tenants present (§ 1.4/§ 1.5); periodic abbreviated isolation re-probes + founding Playwright; **post-import** isolation re-verification (the close gate); record every observation in `docs/phase-5.5-soak-log.md`. Tenant 2 pilot/seeded throughout.
6. **S5** — **Generalize the onboarding runbook:** write `docs/tenant-onboarding-runbook.md` — the repeatable operational steps for tenant N+1 (gather inputs → `register-tenant` → Cloudflare custom domain → branding → webhook → admin handoff → isolation spot-check → real-customer go-live incl. the **F72 email-branding check**). After 5.5, onboarding is operational, not an engineering phase.
7. **S6** — **Phase 5 closeout:** tick every § 5 box and **every Phase 5 Phase Completion Criteria box** (5.5 is the last sub-deploy); § 13 (F72 deferred-disposition re-confirmed; any F75+ filed); parent row 5.5 → Complete + Status → **Phase 5 Complete**; `CLAUDE.md` § Current Migration Phase → Phase 5 Complete (active sub-deploy → none; Phase 6 not started, stub exists); end-of-session status update.

## 3. Out of scope (stop and ask before touching)

- **Open public self-serve tenant signup page / wildcard DNS+TLS** — that is **Phase 6** (gated on the wildcard spike). 5.5 onboards exactly one operator-provisioned tenant via one manual custom domain.
- **Multi-tenant email branding / per-tenant MailerSend identities (F72)** — explicitly OUT of Phase 5. 5.5 re-confirms the deferral and flags it as a real-customer go-live prerequisite; it does **not** parameterize the email template.
- **Multi-tenant import-script generalization** (`import.js` running a full per-tenant catalog import) — a follow-on, not 5.5 (§ 1.5). File if the operator needs tenant 2 to have its own live monthly import.
- **Opening tenant 2 to real customer writes inside the soak** — the rollback-tier decision keeps tenant 2 pilot/seeded through 5.5; real-customer go-live is the post-close operational step. Flipping it early is a scope/rollback-tier change — STOP and ask.
- **Any `app.js` / `*.html` / `config.js` / `style.css` / Edge-Function source change** — 5.5 is operational + doc-only. If a source change seems needed, STOP and ask (it is almost certainly a finding or a follow-on sub-deploy).
- **Adding a second standing tenant to *staging*** — the S1 rehearsal tenant is torn down. A permanent staging second tenant (useful for ongoing isolation regression) is a reasonable idea but is **not** 5.5 scope — file it if raised.
- **`tenants` INSERT/DELETE RLS policy** — the absence is intentional (service-role-only creation). Do not add one.

---

## 4. Runbook

Execution order: **S0 (readiness gate) → S1 (staging full-dress rehearsal + teardown) → S2 (prod onboarding, Rick's window) → S3 (prod isolation verification, real tenant 2) → S4 (two-tenant soak, one import cycle) → S5 (generalize runbook) → S6 (Phase 5 closeout).** S1 must complete (incl. verified teardown) before any prod write. S3 must be green (zero cross-tenant leakage) before the soak begins. S4 cannot close before one full import cycle + post-import re-verification.

### S0 — Readiness gate (no writes)

1. **5.4-live-on-prod check (Claude probes + Rick confirms):**
   - `register-tenant` prod gate: `curl.exe -s -o /dev/null -w "%{http_code}"` POST to prod `.../functions/v1/register-tenant` **without** `x-operator-secret` → expect **401**. (Gate probe only; no body that would create anything.)
   - > **PAUSE → Rick:** confirm from the 5.4 S6 Deploy Log / prod dashboard that `register-customer` (un-pinned) and `register-tenant` are the deployed prod versions and the prod founding webhook secret is in prod `tenants.settings`. **Paste:** confirmation.
   - **STOP if** the gate probe is not 401 or Rick cannot confirm 5.4 prod state.
2. **Operator-input validation (Claude, against inputs Rick supplies):** confirm the chosen `slug` matches `^[a-z0-9][a-z0-9-]*[a-z0-9]$` (or single char) and is **not** on the reserved denylist (§ 0.2). Confirm `display_name`, `admin_email` (reachable mailbox), optional branding present. **STOP** if the slug is reserved/invalid — ask the operator for an alternative.
3. **Teardown-vs-schema re-verify (Claude, read-only):** read `docs/phase-4.1-canary-procedure.md` Teardown block; confirm the table list still matches the live tenant-scoped tables (anti-drift). Note any divergence; do not edit the procedure inline — flag it.
4. **Import-pin re-confirm (Claude, read-only, local script):** `Select-String` the prod `import.js` for the founding-tenant constant; confirm still founding-pinned (§ 1.5). Record.
5. **Cloudflare access (Rick):** > **PAUSE → Rick:** confirm dashboard access to the Pages project serving `pulllist.app` (custom-domain add). **Paste:** confirmation. **STOP if** unavailable.
6. **Record (Claude):** Deploy Log row (readiness gate green; slug validated; teardown/schema match; import founding-pinned; Cloudflare access). Commit:
   ```
   docs: 5.5 S0 — readiness gate green (5.4 live on prod, tenant-2 inputs validated, teardown/import boundaries re-confirmed)
   ```

### S1 — Staging full-dress rehearsal (end-to-end) + verified teardown

**Proves the entire onboarding (create → branding → routing → isolation → import-coexistence → teardown) on staging before any prod write.** Reuses `docs/phase-4.1-canary-procedure.md` (teardown order load-bearing).

1. **Regenerate rehearsal scratch (Claude):** new UUIDs per §4.1 Step 1 into `phase-4.1-canary-uuids.txt` (local-only).
2. > **PAUSE → Rick (STAGING) — create the rehearsal tenant *through* `register-tenant`:** Claude prepares the curl to staging `.../functions/v1/register-tenant` with `x-operator-secret: <TENANT_PROVISION_SECRET staging>` (Rick substitutes) and body `{ slug:'<rehearsal-slug>', display_name:'<…> (rehearsal)', admin_email:'rehearsal-admin@example.invalid', branding:{ … sample colors/name … } }`. **Paste:** the response. **Expected:** `200` `{ tenant_id, admin_user_id, slug, webhook_secret }`. Save all four to scratch. **STOP** on non-200 (run §4.1 compensation/teardown before retry).
3. **Branding render check (Claude):** confirm `tenants.branding` is seeded; load the staging app with `?t=<rehearsal-slug>` and verify `Branding.apply()` renders the rehearsal name/colors distinctly from founding.
4. **Routing check (Claude):** `?t=<rehearsal-slug>` resolves to the rehearsal tenant via `resolve_tenant_by_slug`; **host-parse unit check** — `tenantSlugFromHostname('<rehearsal-slug>.pulllist.app')` → `<rehearsal-slug>` and the allowlist does not swallow it (the live subdomain is prod-only — § 1.2; note the staging asymmetry).
5. **Seed pilot data + isolation checklist (Claude / Rick SQL):** seed a small pilot catalog + a pilot customer for the rehearsal tenant; run the full **4.1-style cross-tenant probe matrix (§ 1.3)** with founding + rehearsal tenant present → all cross-tenant probes **0**. Run `.\run-smoke.ps1` (full Playwright incl. F15/F20) → all green. Founding behavior unchanged.
6. > **PAUSE → Rick (STAGING SQL Editor + GoTrue) — FK-ordered teardown (§4.1) scoped to `<rehearsal tenant id>`, then verify 0 rows:**
   > ```sql
   > SELECT COUNT(*) AS rehearsal_tenant_rows FROM tenants WHERE id = '<rehearsal tenant id>'::uuid;
   > SELECT COUNT(*) AS rehearsal_profiles    FROM user_profiles WHERE tenant_id = '<rehearsal tenant id>'::uuid;
   > SELECT tenant_id, COUNT(*) FROM user_profiles GROUP BY tenant_id;  -- founding intact
   > ```
   > **Paste:** all three (after running the §4.1 delete order incl. the GoTrue auth-user deletes for the rehearsal admin + pilot customer). **Expected:** `rehearsal_tenant_rows = 0`, `rehearsal_profiles = 0`, founding present + unchanged. **STOP if** any rehearsal row survives (teardown not proven for this schema state).
7. **Record (Claude):** Deploy Log row (rehearsal created via `register-tenant`; branding + routing + isolation green; Playwright green; teardown → 0 rows). Commit:
   ```
   docs: 5.5 S1 — staging full-dress rehearsal green (create→branding→routing→isolation→teardown 0 rows)
   ```

### S2 — Production onboarding (Rick's chosen window)

**Order matters: create the tenant row + admin first, then branding, then the custom domain + TLS, then verify routing — and founding write-smoke last.**

1. > **PAUSE → Rick (PROD) — create the real tenant 2 *through* `register-tenant`:** Claude prepares the curl to prod `.../functions/v1/register-tenant` with `x-operator-secret: <TENANT_PROVISION_SECRET prod>` (Rick substitutes) and the operator-supplied body `{ slug, display_name, admin_email, contact_email?, contact_phone?, location?, branding? }`. **Paste:** the response. **Expected:** `200` `{ tenant_id, admin_user_id, slug, webhook_secret }`. **Save the four values to the local scratch file** (the `webhook_secret` is needed for MailerLite config; **do not paste secret values back into chat** — F73/F74 leak class). **STOP** on non-200 (run §4.1 compensation/teardown before retry; a `409 slug_taken` means the slug exists — pick another with the operator).
2. > **PAUSE → Rick (PROD SQL Editor) — set/refine tenant-2 branding (if not fully seeded at create):**
   > ```sql
   > UPDATE public.tenants
   >   SET branding = '<operator branding jsonb>'::jsonb
   >   WHERE id = '<tenant-2 id>'::uuid;
   > SELECT id, slug, display_name, branding FROM public.tenants WHERE id = '<tenant-2 id>'::uuid;
   > ```
   > **Paste:** the SELECT. **Expected:** one row, tenant-2 branding present.
3. > **PAUSE → Rick (Cloudflare dashboard) — add the custom domain + confirm TLS:** add `<slug>.pulllist.app` as a custom domain on the Pages project serving `pulllist.app`; add the DNS record Cloudflare requests; wait for **Active** + TLS cert **issued**. **Paste:** the custom-domain status (Active) + that HTTPS resolves. **STOP if** the cert does not issue (do not route traffic over an unverified cert).
4. **Routing verification (Claude):**
   - `https://<slug>.pulllist.app/` loads, resolves to tenant 2 (`tenantSlugFromHostname` → slug → RPC → tenant-2 id), and renders tenant-2 branding.
   - `https://pulllist.app/` still resolves to **founding** with founding branding (allowlist intact — § 1.2). **HALT** if the apex misroutes.
5. **Admin handoff (Rick):** deliver the magic link / credentials from the S2.1 `register-tenant` response to the tenant-2 admin (the `admin_email` mailbox). Confirm the admin can sign in to `<slug>.pulllist.app/admin.html` and sees an **empty, tenant-2-scoped** admin surface.
6. **MailerLite webhook (Rick — only if the pilot uses webhook registration):** configure tenant 2's MailerLite webhook URL `.../functions/v1/register-customer?secret=<tenant-2 webhook_secret>`. **If the pilot will not use MailerLite registration during the soak, DEFER and note it** (pilot customers are created via `create-paper-customer` / admin invite instead — both already tenant-scope correctly).
7. **Founding write-smoke (Rick):** reserve one item on `pulllist.app` as a test customer → row lands in prod `preorders` with founding `tenant_id` → cancel it. (Regression guard — confirms adding tenant 2 broke nothing on the founding write path.)
8. **Record (Claude):** Deploy Log row (tenant-2 id/admin created; branding set; custom domain Active + TLS; subdomain routes to tenant 2; apex routes to founding; admin sign-in OK; MailerLite configured or deferred; founding write-smoke clean — **no secret values recorded**). Commit:
   ```
   docs: 5.5 S2 — tenant 2 live on prod (register-tenant create, <slug>.pulllist.app custom domain + TLS, branding, admin handoff); founding write-smoke clean
   ```

### S3 — Production two-tenant isolation verification (real tenant 2)

**The parent's headline completion gate — zero cross-tenant leakage against the *real* tenant 2.**

1. **Seed pilot data (Rick/Claude):** seed a small pilot catalog + 1–2 pilot customers (via `create-paper-customer` / admin invite) for tenant 2, so isolation probes have non-empty tenant-2 data to prove separation against. (Pilot/seeded only — no real customers.)
2. > **PAUSE → Rick (PROD SQL Editor) — cross-tenant data-isolation matrix (both directions, per table):** Claude prepares the §1.3 probe SQL (founding admin → tenant-2 rows; tenant-2 admin → founding rows; for `preorders`, `user_profiles`, `subscriptions`, `catalog`, `weekly_shipment`, `reservation_history`, `usage_events`) using the `SET LOCAL role authenticated` + `request.jwt.claims` simulation (CLAUDE.md § Supabase facts). **Paste:** all counts. **Expected:** **every cross-tenant count = 0.** **STOP + file (F75+)** on any non-zero.
3. **Analytics + admin + customer-page scoping (Claude + Rick):** `get_popular_series` and any tenant-scoped RPC scoped to caller; `admin.html` (customer list / bagging / stats) scoped; `catalog`/`mylist`/`arrivals`/`subscriptions` for a tenant-2 pilot user show only tenant-2 data; founding user unaffected.
4. **Edge-Function path scoping (Claude curl + Rick verify):** confirm each EF scopes to the acting tenant — notably `register-customer?secret=<tenant-2 secret>` lands a (fresh `+alias`) pending customer in **tenant 2** (then delete the test row), and founding-secret still lands in founding. `notify-customers` / `send-my-list` scope to the acting tenant.
5. **Branding-by-host (Claude):** `<slug>.pulllist.app` → tenant-2 branding; `pulllist.app` → founding branding (re-confirm S2.4 after seeding).
6. **Full Playwright (Claude):** `.\run-smoke.ps1` → all green incl. F15/F20 with two tenants present on prod-equivalent data.
7. **Record (Claude):** Deploy Log row (full isolation matrix = 0 both directions; analytics/admin/customer/EF scoping verified; branding-by-host correct; Playwright green). Commit:
   ```
   docs: 5.5 S3 — prod two-tenant isolation verified against real tenant 2 (zero cross-tenant leakage; branding-by-host correct)
   ```

### S4 — Two-tenant production soak (one full import cycle)

**Begins after S3 green. Close gate = one complete monthly prod import with both tenants present + post-import isolation re-verification (§ 1.4/§ 1.5). Tenant 2 pilot/seeded throughout.**

1. **Open the soak log (Claude):** create `docs/phase-5.5-soak-log.md` (modeled on `docs/phase-4.1-soak-log.md`): soak start date, both tenant ids/slugs, the close gate, the rollback note (clean §4.1 teardown while pilot/seeded). Commit:
   ```
   docs: 5.5 S4 — two-tenant prod soak opened (close gate: one full import cycle + post-import isolation re-verify)
   ```
2. **Periodic observations (each soak session, Claude + Rick):** append a soak-log row — abbreviated cross-tenant probes (founding↔tenant-2 = 0 on the high-traffic tables), founding Playwright green, branding-by-host spot-check, any customer-reported issue (expected: none — tenant 2 is pilot/seeded). State drift in either direction is a STOP + investigation.
3. > **PAUSE → Rick — the monthly import (the soak anchor):** when the normal monthly prod import runs (founding tenant, founding-pinned `import.js` — § 1.5), **paste** the import summary. Then Claude prepares the **post-import isolation re-verification** (the §1.3 matrix, abbreviated) — **paste** counts. **Expected:** founding import touched only founding rows; tenant-2 seeded data unchanged; all cross-tenant counts = 0. **STOP + file** on any tenant-2 row touched by the founding import or any non-zero cross-tenant count.
4. **Founding write-smoke post-import (Rick):** reserve + cancel one item on `pulllist.app` → founding `tenant_id`. (Confirms the import + two-tenant coexistence broke nothing.)
5. **Close the soak (Claude):** when the import cycle + post-import re-verification are green and founding Playwright is green with no customer-reported regressions, mark the soak **passed** in the soak log with the elapsed window and the import date. Commit:
   ```
   docs: 5.5 S4 — two-tenant prod soak passed (one full import cycle elapsed; post-import isolation re-verified 0; founding unchanged)
   ```

### S5 — Generalize the onboarding runbook (tenant N+1 is operational)

1. **Write `docs/tenant-onboarding-runbook.md` (Claude)** — an operational, repeatable runbook (not a phase doc), distilled from S0–S3, for onboarding any future tenant N+1:
   - Gather inputs (slug/display_name/admin_email/branding); validate slug (format + reserved denylist).
   - Create the tenant via `register-tenant` (operator secret; capture `tenant_id`/`admin_user_id`/`webhook_secret`; **never paste secrets into chat/transcripts** — F73/F74 lesson).
   - Set branding (`tenants.branding`).
   - Add `<slug>.pulllist.app` Cloudflare custom domain + confirm TLS (note: **wildcard self-serve is Phase 6**; until then each tenant is a manual custom-domain add).
   - Configure MailerLite webhook with the tenant's secret (if used).
   - Admin handoff (magic link to `admin_email`).
   - Isolation spot-check (abbreviated §1.3 matrix) before announcing.
   - **Real-customer go-live checklist** incl. the **F72 email-branding decision** (founding-branded `register-customer` emails until multi-tenant email branding lands — Phase 6 / dedicated sub-deploy) and the **one-way rollback** note (clean §4.1 teardown ends once real customer writes begin).
   - Rollback: the §4.1 FK-ordered teardown (clean while pilot/seeded; forward-fix only after real customer writes).
2. **Record (Claude):** Deploy Log row. Commit:
   ```
   docs: 5.5 S5 — generalized tenant-onboarding runbook (tenant N+1 is operational, not an engineering phase)
   ```

### S6 — Phase 5 closeout (run once, when every § 5 box is ticked)

1. Tick the § 5 boxes with inline result notes (5.4 pattern).
2. **Walk the parent's Phase Completion Criteria and tick every box** (5.5 is the last sub-deploy): all sub-deploys Complete; second tenant live on prod (slug/branding/admin/customer flows verified); zero cross-tenant leakage verified against the real tenant 2; founding behavior unchanged (Playwright green; no soak regressions); `TENANT_SLUG_MAP` removed (5.2); `register-customer` un-pinned (5.4); hosting migrated (5.1); carried findings resolved/re-dispositioned (F58/F63/F64/F65/F66 closed in 5.0–5.4; **F72 re-confirmed deferred — § 1.6**); two-tenant soak passed (S4); `CLAUDE.md` updated + Phase 6 stub exists; all sub-deploy plan files committed.
3. This file: Status → **Complete** + date; Last-updated line.
4. Parent (`phase-5-second-tenant-onboarding.md`): row 5.5 → **Complete** + date; **Status line → Phase 5 Complete**; Phase Completion Criteria all ticked.
5. `docs/technical-reference.md`: § 11 — note tenant 2 exercises the per-tenant secret + operator EF in production (inventory stays 9); § 13 **F72 deferred-disposition re-confirmed** (re-evaluate at tenant-2 real-customer go-live); file any F75+ discovered during 5.5.
6. `CLAUDE.md` § Current Migration Phase: active phase → **Phase 5 Complete**; active sub-deploy → none (Phase 6 not started — stub `docs/phase-6-self-service-signup.md` exists, gated on the wildcard-DNS/TLS spike); last-completed phase → Phase 5; § Known Out-of-Scope "second-tenant onboarding" → Complete; open-findings line (F72 deferred; next free ID **F75** unless 5.5 filed more).
7. Commit:
   ```
   docs: close Phase 5.5 + Phase 5 (second tenant live on prod; two-tenant soak passed; onboarding generalized)
   ```
8. End-of-session status update per `CLAUDE.md` § Anti-Drift Rules (changed / verified / left / filed / new IDs).

---

## 5. Completion criteria (all must be checked before parent row 5.5 → Complete and Phase 5 → Complete)

- [ ] **S0:** 5.4 artifacts confirmed live on prod (`register-tenant` gated 401-without-secret; `register-customer` un-pinned; prod founding webhook secret in `tenants.settings`); operator tenant-2 inputs validated (slug passes format + not reserved); §4.1 teardown matches live schema; prod `import.js` confirmed founding-pinned; Cloudflare access confirmed.
- [ ] **S1:** staging full-dress rehearsal — tenant created **through** `register-tenant`; branding renders; `?t=<slug>` + host-parse resolution correct; full 4.1-style isolation matrix = 0 both directions with two tenants present; full Playwright (F15/F20) green; FK-ordered teardown executed; **`rehearsal_tenant_rows = 0` and founding intact** verified by SELECT.
- [ ] **S2:** real tenant 2 live on prod via `register-tenant` (tenant_id/admin/webhook_secret captured locally, **no secret in chat**); branding set; `<slug>.pulllist.app` custom domain **Active** with TLS issued; subdomain routes to tenant 2 and `pulllist.app` still routes to founding; tenant-2 admin signs in to an empty tenant-2-scoped admin surface; MailerLite webhook configured or deferred-with-note; founding write-smoke clean.
- [ ] **S3:** prod cross-tenant isolation matrix = **0 in both directions** across every tenant-scoped table; analytics/admin/customer-page/Edge-Function paths each tenant-scoped; `register-customer` with tenant-2 secret lands in tenant 2 (founding secret still → founding); branding correct per host; full Playwright green. (Parent headline gate.)
- [ ] **S4:** two-tenant prod soak passed — **at least one full monthly import cycle** elapsed with both tenants present; founding import touched only founding rows and tenant-2 seeded data was unchanged; **post-import** isolation re-verification = 0 both directions; founding Playwright green and no customer-reported regressions across the span; tenant 2 pilot/seeded throughout; soak log complete.
- [ ] **S5:** `docs/tenant-onboarding-runbook.md` written — repeatable tenant-N+1 onboarding incl. the F72 email-branding check and the one-way-after-real-writes rollback note.
- [ ] **Founding-tenant behavior unchanged** (parent invariant): no source file changed; full Playwright incl. tenant-isolation green at the S1/S3 gates and the S4 post-import write-smoke; `pulllist.app` byte-identical to 5.4.
- [ ] **Teardown clean throughout the soak** (rollback tier): tenant 2 pilot/seeded; the §4.1 FK-ordered teardown remains a clean rollback for the entire 5.5 window (real-customer go-live is post-close).
- [ ] **Phase 5 Phase Completion Criteria all ticked** (§ S6 step 2) — 5.5 is the final sub-deploy; parent Status → Phase 5 Complete; `CLAUDE.md` § Current Migration Phase advanced; F72 re-confirmed deferred; all plan files committed.

---

## 6. Rollback (per step; clean while tenant 2 is pilot/seeded)

- **S1 (staging rehearsal):** torn down in-step (verified 0 rows). No standing change. If a sitting ends mid-rehearsal, run the §4.1 teardown before closing and record it.
- **S2 (prod onboarding):** §4.1 FK-ordered teardown scoped to the tenant-2 id removes the tenant row + admin + seeded data cleanly (tenant 2 has no real customer writes); remove the `<slug>.pulllist.app` custom domain from Cloudflare; unset the tenant-2 MailerLite webhook if configured. Founding is untouched (no source change, no founding-data change beyond the in-step write-smoke which self-cancels).
- **S3 (isolation verification):** read-only + seeded pilot data; teardown per §4.1 removes the seed. A non-zero cross-tenant probe is a **STOP + file**, not a rollback — investigate before any further write.
- **S4 (soak):** tenant 2 stays pilot/seeded → the §4.1 teardown remains a clean rollback for the entire soak. The founding monthly import is the normal operation and is not rolled back. If isolation breaks at the import boundary, STOP + file + (if needed) teardown tenant 2 and forward-fix.
- **S5/S6 (runbook + closeout):** doc-only; revert the commit.
- **One-way boundary (post-5.5):** opening tenant 2 to **real** customers (the operational go-live after 5.5 closes) is the point past which the clean teardown no longer applies — forward-fix only (Phase 4 Tier-3 logic). The generalized runbook (§ S5) states this explicitly.

---

## 7. References

- Decision (soak duration): Rick, 5.5 planning 2026-06-17 — **one full monthly import cycle, no extra buffer** (§ 1.4); the import boundary is the explicit anchor (§ 1.5).
- Decision (routing): Rick, 5.5 planning 2026-06-17 — **dedicated subdomain `<slug>.pulllist.app`, single manual Cloudflare custom domain, no wildcard** (wildcard DNS/TLS is the Phase 6 gate) (§ 1.2).
- Decision (tenant-2 identity): Rick, 5.5 planning 2026-06-17 — **operator-supplied at execution** (§ 1.1); 5.5 may run the S1 rehearsal and pause at S2 until a real tenant exists.
- Decision (rollback tier): Rick, 5.5 planning 2026-06-17 — **tenant 2 pilot/seeded throughout the soak**; real-customer go-live is the post-close one-way operational step (§ 6 / § S5).
- Parent: `docs/phase-5-second-tenant-onboarding.md` (row 5.5; § In Scope 5.5; § Approach Decisions "onboarding gated"; § Phase Completion Criteria — **5.5 makes every box tickable**; § Rollback row 5.5; § Out of Scope email branding + the "5.5 may file findings against it" note).
- Predecessor: `docs/phase-5.4-tenant-signup.md` (the tools 5.5 consumes — `register-tenant`, per-tenant webhook secret, the proven §4.1 teardown; Deploy Log § 8 shows what is live on both envs).
- Canary spin-up + FK-ordered teardown (reused S1; standing rollback for tenant 2 while pilot/seeded): `docs/phase-4.1-canary-procedure.md`.
- Isolation probe surface (4.1-style V7 matrix, reused S1/S3/S4): `docs/phase-4.1-soak-log.md` § V7.
- Soak-log model: `docs/phase-4.1-soak-log.md` (5.5 creates `docs/phase-5.5-soak-log.md` at S4).
- Routing internals (re-read from disk at execution): `app.js` `TenantContext.tenantSlugFromHostname()` + the `?t=<slug>` / sessionStorage branches + the non-tenant-host allowlist (5.2 § 1.3).
- Branding: `Branding.apply()` reads `tenants.branding` (5.3); set at `register-tenant` create or a follow-up `tenants.branding` UPDATE.
- Findings: `docs/technical-reference.md` § 13 — **F72** (email-branding deferral, re-confirmed deferred — a real-customer go-live prerequisite, § 1.6). **Next free ID at planning: F75** (5.5 files from F75 if it discovers defects).
- Edge Functions: `docs/technical-reference.md` § 11.1–11.3 (9 EFs; `register-tenant` `x-operator-secret` gate; `register-customer` per-tenant-secret resolution).
- Curl pattern for tenant-aware Supabase calls: `test-magic-link.ps1` (`curl.exe --data-binary @file`; `Invoke-RestMethod` mangles JSON — `CLAUDE.md` § Known Issues). **Never paste secret values back into chat** (F73/F74 lesson).
- Projects: staging `puoaiyezsreowpwxzxhj`, prod `plgegklqtdjxeglvyjte`. Founding tenant UUID (staging) `72e29f67-39f7-42bc-a4d5-d6f992f9d790`; prod founding `20941129-c35a-476d-ae21-44b8f77af89c` / slug `rjbookstop` (also in `catalogs\scripts\phase-4-prod-tenant-uuid.txt`, local-only).
- Successor: `docs/phase-6-self-service-signup.md` (stub) — open self-serve signup + wildcard DNS/TLS; begins only after Phase 5 closes.

---

## 8. Deploy log (filled during execution)

| Date | Step | Result | Notes |
|---|---|---|---|
| | S0 | | |
| | S1 | | |
| | S2 | | |
| | S3 | | |
| | S4 | | |
| | S5 | | |
| | S6 | | |

---

**Last updated:** 2026-06-17 (plan written; Planning — not yet executed)
</content>
</invoke>
