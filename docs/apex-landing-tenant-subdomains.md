# Apex Landing Page + Founding-Tenant Subdomain (PLAN)

**Status:** **Planning — not started.** Standalone sub-deploy; **not** during the F86 legacy-key
quiet-window watch, and **not** bundled with any other work. Its own session, full
staging→prod discipline.
**Type:** Front-door / hosting + tenant-resolution change (customer-impacting on the founding
production URL). Standalone, ahead of Phase 6 — a satisfied precursor to Phase 6's public
front door, **not** gated on the Phase 6 wildcard-DNS/TLS spike (see § Why not blocked on Phase 6).
**Author context:** Written 2026-07-20 in response to Rick's goal — *"potential SaaS customers land
on the apex (`pulllist.app`) landing page; individual store customers land on their tenant login
page mapped to their slug as a subdomain."*
**Predecessors reused:** 5.2 (slug→id RPC + `tenantSlugFromHostname()`), 5.3 (`Branding.apply()`),
5.5 (one-manual-custom-domain provisioning pattern for `comicstore.pulllist.app`).
**Next free finding ID at planning:** **F91**.

> This is a **design + scope + sequence** plan at the altitude of a phase parent plan, not an
> execution runbook. Byte-exact `old_str`/`new_str` and exact SQL/DNS steps are written when the
> sub-deploy actually opens and its target files are re-read from disk (project "plan-when-its-turn-
> comes" discipline). Everything below marked **(verify at execution)** is a live-state or
> platform-behavior claim to re-confirm before relying on it.

---

## Goal

Turn `pulllist.app` (the apex) into a **platform marketing landing page** for prospective store
owners, and move each store's customer front door to **`<slug>.pulllist.app`** — including the
founding tenant, which moves to **`rjbookstop.pulllist.app`** (prod) exactly the way tenant 2
already lives at `comicstore.pulllist.app`.

End state:
- `pulllist.app/` → marketing landing (no tenant app; no login form).
- `rjbookstop.pulllist.app/` → Ray & Judy's login (today's `index.html` behavior).
- `comicstore.pulllist.app/` → tenant 2 login (already live — unchanged).
- Existing founding customers (bookmarks, printed URL, outstanding magic links pointed at
  `pulllist.app/...`) keep working via a backward-compat redirect to the founding subdomain.

---

## What is already done (no work needed)

- **The founding tenant already has a slug** — prod `rjbookstop`, staging `raysandjudys` — and
  `resolve_tenant_by_slug` already resolves it (verified live at 5.2 S7). There is **no
  "implement the slug" work** at the data or RPC layer.
- **The app already resolves a tenant from its subdomain.** `app.js`
  `tenantSlugFromHostname()` (5.2) parses `<slug>.pulllist.app` → slug → RPC → tenant. Since
  `rjbookstop` is **not** in `NON_TENANT_HOSTS`, `rjbookstop.pulllist.app` will resolve to the
  founding tenant automatically the moment that custom domain is provisioned — **zero resolver
  code change** for the founding subdomain itself. (verify at execution: re-read the resolver +
  allowlist from disk.)

## The load-bearing architectural fact

**Cloudflare Pages serves every hostname from one project.** `comicstore.pulllist.app` is a
*custom domain on the same Pages project* as `pulllist.app` (5.5 S2). So **all hosts serve
byte-identical static files** — you cannot put "a different file at the apex vs a subdomain." The
apex-marketing-vs-tenant-login distinction **must be driven client-side by
`window.location.hostname`**, not by separate files. This drives the whole design below.

---

## Why not blocked on Phase 6

Phase 6's gating **wildcard**-DNS/TLS spike exists because *self-service signup* needs **arbitrary
new slugs** to serve instantly with zero manual DNS. This work does not have that problem — it
provisions **one known subdomain** (`rjbookstop.pulllist.app`), a single manual Cloudflare Pages
custom domain, identical to what 5.5 did for `comicstore`. No wildcard is required. This can
therefore run as a focused standalone sub-deploy now; it becomes a satisfied precursor when
Phase 6 opens (Phase 6's public `/signup` lives on the apex this work creates).

---

## 🚩 Blocking dependency — per-tenant auth-redirect base URL (extends F72)

**This is the real prerequisite, and it must land first or in lockstep.** Today the invite /
recovery / magic-link emails redirect to a **single per-project** `APP_BASE_URL` secret
(prod = `https://pulllist.app`, set in 5.2 S5). The moment the apex stops serving a login form,
**every founding-customer magic link that points at `pulllist.app/index.html` lands on a
marketing page with no way to finish auth.** So the auth-redirect base URL must become
**per-tenant**: founding links → `rjbookstop.pulllist.app`, comicstore links →
`comicstore.pulllist.app`.

- **Relation to F72:** F72 tracks the *email body branding* gap (`register-customer`'s
  founding-branded copy/`from` name). The **redirect-target** need here is adjacent but distinct
  — same "emails aren't tenant-aware" root, different symptom (a broken login vs. wrong branding).
  They should be sequenced together; F72's body-branding half can ride along or stay deferred, but
  the **redirect-URL half is non-negotiable for this work**.
- **Pre-existing latent defect discovered during planning (candidate F91):** tenant 2
  (`comicstore`) customer invite/reset emails **already** redirect to `pulllist.app` (the single
  `APP_BASE_URL`), not `comicstore.pulllist.app`. It "works" today only because auth is
  user-identity based and `TenantContext` then resolves the tenant from the authenticated
  `user_profiles.tenant_id` (profile branch, highest priority) even on the apex host — so the
  customer lands logged-in but on the *founding-branded* apex host. Under this work that link would
  land on marketing and break. **Recommend filing as F91 (or folding into F72) — Rick's call at
  plan open.** Not filed unilaterally in this planning step.
- **Design options for the base URL (verify at execution; settle at plan open):**
  - **(a)** EFs derive the base from the resolved tenant's slug: `https://<slug>.pulllist.app`
    (needs a canonical per-tenant host; slug is already in `tenants`). Lead recommendation —
    no new stored config, and it composes with future tenants automatically.
  - **(b)** Store a per-tenant `app_base_url` in `tenants.settings`; EFs read it. More explicit,
    supports future vanity domains, but another stored field to keep correct.

---

## Approach decisions (proposed — confirm at plan open)

1. **Provision `rjbookstop.pulllist.app`** as a single manual Cloudflare Pages custom domain on the
   project serving `pulllist.app`, TLS auto-issued — the exact 5.5 procedure, no wildcard.
2. **`index.html` becomes hostname-aware** (one file, per the one-project fact):
   - On a **tenant subdomain** (`tenantSlugFromHostname()` returns a slug) → render today's
     login / invite / recovery / magic-link flow, **unchanged in behavior**.
   - On the **apex** (`pulllist.app` / `www.pulllist.app`) → render the **marketing landing**.
   - Lead recommendation: keep the auth-token handling code path intact and branch *presentation*
     by host, so no auth logic is lost. (Alternative: split marketing into `index.html` and move
     login to `login.html`; rejected as lead because it repoints every magic link twice and
     duplicates the auth flow — but revisit if the marketing page grows heavy.)
3. **Apex deep app-paths redirect to the founding subdomain (backward-compat).** A request to
   `pulllist.app/catalog.html`, `/mylist.html`, `/index.html?token_hash=…` etc. → 301/redirect to
   `rjbookstop.pulllist.app/<same path + query>`, preserving tokens. **(verify at execution)**
   Cloudflare `_redirects` matches on **path, not host**, and all hosts share one project — so a
   host-scoped redirect needs either a **zone-level Cloudflare Redirect Rule** or a **client-side
   redirect in `app.js`** (apex + app-page → founding subdomain, preserving `location.search` /
   `location.hash`). Lead recommendation: client-side redirect (fully in our control, token-safe);
   confirm the CF-mechanics claim before choosing.
4. **The 5.2 founding-apex invariant is deliberately superseded.** 5.2 made "`pulllist.app`
   resolves to the founding tenant, identically to today" a hard invariant. This work intentionally
   reverses it: the apex serves marketing and resolves to **no** tenant app. Record the supersession
   explicitly in 5.2's doc + `technical-reference.md`; update the Playwright founding-invariant /
   tenant-isolation specs to assert the **new** contract (apex → marketing; founding →
   `rjbookstop.pulllist.app`). The `FOUNDING_TENANT` default in `resolve()` stays as a harmless
   safety fallback.
5. **Branding unchanged in mechanism** — `Branding.apply()` (5.3) already brands by resolved
   tenant; on `rjbookstop.pulllist.app` it renders founding branding exactly as the apex does today.

---

## Staging-vs-prod asymmetry (carried from 5.5)

A per-tenant custom domain **cannot be minted on `*.pages.dev`**, so the live founding subdomain
is **prod-only**. Staging verification uses the `?t=raysandjudys` query path + a
`tenantSlugFromHostname()` host-parse unit check + the apex-vs-subdomain presentation branch
exercised via a host stub — **not** a live `raysandjudys.pulllist.app`. Note this asymmetry in the
Deploy Log, same as 5.5 S1.

---

## Provisional sub-deploy shape (illustrative — finalized at plan open)

| #   | Title | Notes |
|-----|-------|-------|
| S0 | **Readiness gate (no writes)** | Re-read resolver + allowlist from disk; confirm founding slug resolves via RPC on both envs; confirm Cloudflare access to the `pulllist.app` Pages project; confirm `comicstore` custom domain still Active (regression baseline); settle the F91-filing decision. |
| S1 | **Per-tenant auth-redirect base URL (the blocking dependency)** | Make invite/recovery/magic-link redirect base per-tenant (option (a) or (b)); staging EF deploy → verify a founding link targets the founding host; then prod EF deploy → verify. Optionally resolve F72 body-branding in the same window. |
| S2 | **Marketing landing + hostname-aware `index.html`** | Build the apex marketing page; branch presentation by host; preserve the full auth-token path on the subdomain branch. Staging-verify both branches via host stub + `?t=`. |
| S3 | **Backward-compat redirect** | Apex deep app-paths → founding subdomain, token/query preserved (client-side or CF Redirect Rule per the verified mechanics). |
| S4 | **Provision `rjbookstop.pulllist.app`** | Manual CF custom domain + TLS (5.5 procedure); confirm Active + HTTPS + resolves to founding via the subdomain path. Prod-only. |
| S5 | **Supersede the 5.2 invariant + specs** | Update 5.2 doc + `technical-reference.md`; rewrite the founding-invariant / isolation Playwright specs to the new contract; full suite green. |
| S6 | **Prod promotion + soak + closeout** | Standard workflow (F59 diff assertion, `config.js` checkout, post-deploy write-smoke on the founding subdomain); short soak; verify an outstanding-magic-link redirect end-to-end; tick completion criteria. |

Order is load-bearing: **S1 (per-tenant redirect URL) must precede S4 (apex stops serving login)** —
otherwise the first founding magic link after S4 breaks.

---

## In scope

- Provision one manual custom domain `rjbookstop.pulllist.app` (+ TLS).
- Per-tenant auth-redirect base URL (invite/recovery/magic-link) — the blocking dependency.
- Apex marketing landing page + hostname-aware `index.html` presentation branch.
- Backward-compat redirect for apex deep app-paths → founding subdomain (token/query preserved).
- Deliberate supersession of the 5.2 founding-apex invariant + updated Playwright specs.

## Out of scope (stop and ask before touching)

- **Wildcard `*.pulllist.app` DNS/TLS + public `/signup`** — that is Phase 6. This work adds
  exactly one manual custom domain and a static marketing page, no self-serve provisioning.
- **F72 email *body* branding** — may ride S1's window but is not required; the redirect-URL half
  is the only non-negotiable piece.
- **Marketing-site content/design system beyond a first landing page** (copy, SEO, analytics
  pixels, multi-page marketing site) — scope the first landing page only; expansions are separate.
- **F86 legacy-key work** — unrelated; this sub-deploy does not run during that watch.
- Any `config.js` / import-script change; any second real tenant onboarding.

---

## Risks

- **R1 — Founding customer disruption (highest).** `pulllist.app` is the production URL on record
  (bookmarks, printed material, phone-answered site). If the backward-compat redirect (S3) or the
  per-tenant magic-link URL (S1) is wrong, live logins and outstanding invite/reset links break.
  Mitigation: S1 before S4; verify an end-to-end outstanding-link redirect at S6; short soak.
- **R2 — Cloudflare host-scoped redirect mechanics unverified.** `_redirects` is path-only; the
  host-scoped redirect needs a zone Redirect Rule or client-side handling. Mitigation: verify CF
  behavior at execution; lead toward the client-side redirect we fully control.
- **R3 — One-project/all-hosts confusion.** Any "put a file at the apex" instinct is wrong; the
  apex/subdomain split is client-side only. Mitigation: stated up front here; specs assert both
  branches from the same deployed file set.
- **R4 — Invariant-supersession drift.** 5.2's invariant is referenced across Phase 5 docs and the
  Playwright suite; missing one reference leaves a contradictory "apex → founding" claim.
  Mitigation: S5 grep-sweeps every reference before closeout.

---

## Completion criteria (finalized at plan open)

- [ ] `rjbookstop.pulllist.app` live (custom domain Active, TLS issued) and resolves to the
      founding tenant with founding branding.
- [ ] `pulllist.app/` serves the marketing landing (no login form); `comicstore.pulllist.app`
      unchanged and green.
- [ ] Per-tenant auth-redirect base URL live: a founding invite/recovery/magic-link email targets
      `rjbookstop.pulllist.app` and `verifyOtp` succeeds; a comicstore link targets
      `comicstore.pulllist.app`.
- [ ] Backward-compat redirect verified: `pulllist.app/catalog.html` and an outstanding
      `pulllist.app/index.html?token_hash=…` both land correctly on the founding subdomain,
      token/query preserved.
- [ ] 5.2 founding-apex invariant formally superseded in the 5.2 doc + `technical-reference.md`;
      no stale "apex → founding" claim remains (grep-swept).
- [ ] Playwright founding-invariant / tenant-isolation specs rewritten to the new contract and
      green; full suite green.
- [ ] Post-deploy write-smoke on `rjbookstop.pulllist.app` (reserve → correct founding
      `tenant_id` → cancel) clean; short soak clean.
- [ ] F91 filed-or-folded per Rick's S0 decision; F72 disposition updated.
- [ ] This plan's status → Complete; `CLAUDE.md` updated; Phase 6 stub notes the satisfied
      precursor.

---

## References

- Tenant resolution + RPC + `tenantSlugFromHostname()`: `docs/phase-5.2-slug-id-routing-rpc.md`;
  `app.js` `TenantContext` (re-read from disk at execution).
- One-manual-custom-domain provisioning pattern (comicstore): `docs/phase-5.5-second-tenant-onboarding.md`
  §§ S2/S3 (add `<slug>.pulllist.app` on the `pulllist.app` Pages project; TLS auto; no wildcard).
- Branding-by-resolved-tenant: `docs/phase-5.3-per-tenant-branding.md` (`Branding.apply()`).
- Email/redirect base URL secret: `docs/phase-5.2-slug-id-routing-rpc.md` § S5 (`APP_BASE_URL`).
- Findings: `docs/technical-reference.md` § 13 — **F72** (email body branding, deferred);
  candidate **F91** (comicstore emails already redirect to the apex). Next free ID: **F91**.
- Phase 6 (successor front door this precedes): `docs/phase-6-self-service-signup.md`.
- Anti-drift / plan-when-its-turn-comes / document-integrity: `CLAUDE.md`.

---

**Last updated:** 2026-07-20 (plan drafted; Status: Planning — not started; not during the F86 watch)
