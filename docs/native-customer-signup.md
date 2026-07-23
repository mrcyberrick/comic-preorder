# Native In-App Customer Self-Registration (PLAN)

**Status:** **Planning — not started.** Standalone pre-Phase-6 workstream; its own session, full
staging→prod discipline. **Not** a phase sub-deploy (Phase 5 closed 2026-07-15; Phase 6 not started).
**Author context:** Written 2026-07-23 (Rick + planning session) after the founding tenant's MailerLite
self-registration path broke (see § Trigger). Direction and the two gating decisions were settled with
Rick in the opening session — see § Settled decisions.
**Execution gate:** Do **not** open execution until the apex sub-deploy's 24-hour soak has closed
(`docs/apex-landing-tenant-subdomains.md` S6.5 — armed 2026-07-22T17:13:46Z, elapses
2026-07-23T17:13:46Z / ~1:13 PM ET). This work edits `index.html` (the tenant login branch the apex
work just shipped); do not touch that file while it is soaking.
**Next free finding ID at planning:** **F93** (verify before filing — enumerate `#### F<n>` in
`technical-reference.md` § 13).

> This is a **design + scope + sequence** plan at the altitude of a phase parent plan, not an
> execution runbook. Byte-exact `old_str`/`new_str`, exact SQL/DNS, and the abuse-gate wiring are
> written when the sub-deploy opens and its target files are re-read from disk. Everything marked
> **(verify at execution)** is a live-state or platform-behavior claim to re-confirm before relying on it.

---

## Trigger (context, not scope)

The founding tenant's self-registration path went dark on 2026-07-23, two independent breaks at once:
1. **The MailerLite subscribe form was deleted.** MailerLite's free plan now caps sites at one; Rick
   deleted a site, taking the rjbookstop.com subscribe form with it. → "the website does not accept
   subscribers."
2. **The `register-customer` webhook ("PROD APP ONBOARDING") auto-disabled** after exceeding
   MailerLite's failed-delivery limit. → even a working form would create no accounts.

**What still works:** admin-initiated onboarding (`invite-customer`, `create-paper-customer`) is
untouched — it never used MailerLite. Only *customer-initiated self-service* is down.

We are **not** diagnosing the webhook-disable root cause or restoring MailerLite: this workstream
**retires MailerLite for the founding tenant** in favour of native in-app signup. (The root cause is
moot once the path is removed.) The pasted webhook secret from the incident report should be treated
per the F73/F74 precedent — **rotate it after this workstream lands**, not before, so it doesn't
disturb any diagnosis if we ever need one; but with MailerLite retired it simply becomes dead config.

**Not Phase 6.** Phase 6 is self-service *tenant* signup (a new shop onboards itself). This is
self-service *customer* signup **within an existing tenant** — a different surface entirely.

---

## Goal

Move customer self-registration **into the app**, on the founding tenant's own branded front door, and
retire the external MailerLite form + webhook. Keep MailerSend as the transactional sender (unchanged).

**End state (founding tenant):**
- `rjbookstop.pulllist.app/` → the founding tenant's branded login **plus a "Create account" path**
  that self-registers a customer directly (pending account + magic link + MailerSend "browse while we
  review" email), resolving the tenant from the host — no MailerLite, no webhook, no per-tenant secret.
- `rjbookstop.com` → Rick's **separate Brevo marketing funnel** (its own project, **no PULLLIST data
  connection**). Not wired to `register-customer`; at most a plain **link** to the
  `rjbookstop.pulllist.app` signup as one of the shop's services. See § Adjacent.
- MailerLite is retired for founding; `register-customer`'s webhook path is left dead/harmless or removed.

**Interim (during the build):** self-service is admin-only — the login card's existing "Contact the
shop and we'll get you set up" copy already routes customers to `invite-customer`. No external bridge.

---

## Settled decisions (Rick, 2026-07-23)

1. **Native signup, no external signup platform.** The MailerLite form "just triggered signup," so
   nothing of value is lost by removing it — signup goes fully native. **Brevo is not wired to PULLLIST**;
   it is Rick's separate rjbookstop.com marketing funnel (§ Adjacent), decoupled from this work.
2. **Founding front door = `rjbookstop.pulllist.app`** (a provisioned custom subdomain), **not**
   rjbookstop.com-on-the-app. Cheapest unblock, auto-resolves, zero resolver change — see § Why the
   subdomain is the cheap unblock. rjbookstop.com stays external and points at it.
3. **Interim = admin invites**, no Brevo bridge.

---

## Why the subdomain is the cheap unblock (verify at execution)

The blocker Rick named — "founding has a slug but no custom domain" — is small, not the Phase-6
wildcard lift:
- **`rjbookstop.pulllist.app` is one manual Cloudflare Pages custom domain, TLS auto-issued — the exact
  `comicstore` procedure, no wildcard** (`docs/apex-landing-tenant-subdomains.md` Approach #1 / S4).
- **Zero resolver code change.** `rjbookstop` is already a slug and is **not** in `NON_TENANT_HOSTS`
  (`app.js:32-36`), so `tenantSlugFromHostname()` (`app.js:39-51`) returns `rjbookstop`, and
  `TenantContext.resolve()` (`app.js:99-111`) resolves it to the founding tenant via the
  `resolve_tenant_by_slug` RPC on an **unauthenticated** page load (`_source = 'subdomain'`). Verified
  by reading the resolver 2026-07-23.
- **The apex work already branch-renders it.** `index.html`'s hostname split renders the **branded
  login** (not apex marketing) for any tenant subdomain — so `rjbookstop.pulllist.app` shows the
  founding login today, the moment the domain exists.

This un-defers the apex plan's S4 (founding subdomain), whose only stated reason to defer was "little
near-term value." Native signup **is** that value. Under the apex Hybrid model this is founding
"graduating" to the branded-subdomain tier that model already designed for.

The Phase-6 wildcard-DNS/TLS spike is **only** for arbitrary self-serve slugs and is untouched here —
this adds exactly one named custom domain.

---

## The hard design question — tenant resolution + abuse gate for a secret-less public signup

Native signup **loses the two things the MailerLite chain silently provided**: the per-tenant `?secret=`
that both authenticated the caller and selected the tenant, and MailerLite's double-opt-in / bot
filtering. Replacing both is the real engineering content of this workstream.

**Tenant selection (client already knows it).** On `rjbookstop.pulllist.app`, `TenantContext.current()`
resolves to founding client-side, unauthenticated, purely from the host. The signup form posts the
resolved **slug** (`TenantContext.current().slug`) to the endpoint; the endpoint resolves slug→id
server-side (service-role, or the `resolve_tenant_by_slug` RPC). A client can post any slug — but the
**worst case is a *pending* row in the wrong tenant, which that tenant's admin declines** (the approval
state machine is the real access gate; access is never granted by signup alone). Same low-severity
posture the F34 discussion reached — acceptable, but state it explicitly and pair it with rate limiting.

**Abuse gate (lead recommendation — confirm at plan open):** **Cloudflare Turnstile.** We are already on
Cloudflare Pages, so a Turnstile widget in the form + server-side token verification in the function is
a near-zero-friction, free bot gate that replaces MailerLite's filtering directly. Layer:
- **Honeypot** hidden field (cheap first filter).
- **Turnstile** token, verified in the endpoint before any account/email work.
- **Dedup** — `register-customer` already returns `already_exists` and sends no second email for a known
  address (`index.ts:142-148`); keep that (bounds email-reflection spam to one message per address).
- **Rate limiting** — Supabase Edge Functions have no built-in limiter. Options to settle at plan open:
  (a) Turnstile alone may suffice for the volume; (b) a small `signup_attempts` table with a
  service-role insert + windowed count. Lead: start with Turnstile + honeypot + dedup; add (b) only if
  needed.
- **Consider** a confirm-your-email step (true double-opt-in) as a follow-up if reflection spam appears;
  not required for v1 given dedup + Turnstile + admin approval.

**Endpoint shape (proposed — confirm at plan open):** add a native direct-POST branch to
`register-customer` (detect `{email, name, slug, turnstileToken, honeypot}` vs. the MailerLite webhook
shape; resolve tenant from `slug` instead of `?secret=`), **or** a new `signup` function sharing the
account-create/magic-link/email logic. Lead: **adapt `register-customer` in place**, keep the (now
unused) MailerLite webhook path harmlessly until § S5 removes it — smallest surface, reuses the tested
account-create/magic-link/MailerSend code verbatim.

**F72 stays clear for founding.** `buildPendingEmail()` is founding-branded, which is **correct** for
`rjbookstop`. Native signup for a *non-founding* tenant (e.g. comicstore) would send the wrong brand —
so **comicstore native signup is out of scope here and gated on F72** (`technical-reference.md` § 13
F72). Founding-first sidesteps it.

---

## Provisional sub-deploy shape (illustrative — finalized at plan open)

| #  | Title | Notes |
|----|-------|-------|
| S0 | **Readiness gate (no writes)** | After the apex soak closes. Re-read resolver + `NON_TENANT_HOSTS` from disk; confirm founding slug `rjbookstop` resolves via `resolve_tenant_by_slug` live (prod + staging); confirm Cloudflare access to the `pulllist.app` Pages project; confirm `comicstore.pulllist.app` still Active (regression baseline). |
| S1 | **Provision `rjbookstop.pulllist.app`** | Manual Cloudflare custom domain, TLS auto-issued (the `comicstore` procedure, no wildcard). **Prod-only** — a tenant custom domain cannot exist on `*.pages.dev` (the 5.5 asymmetry). Verify it resolves to founding + renders the branded login. |
| S2 | **Native signup endpoint** | Adapt `register-customer` for the direct-POST path: tenant from `slug`, Turnstile + honeypot + dedup, MailerSend email unchanged (founding-branded — correct for founding). Deploy staging → verify with a throwaway signup, torn down (live SELECT = 0 rows). |
| S3 | **"Create account" UI on the branded login** | Add the signup form to `index.html`'s **tenant branch** (founding login). Wire Turnstile. Staging-verify via host stub / `?t=` / request interception (comicstore-style — no live tenant host on `*.pages.dev`). Real-browser check at desktop + mobile widths (per the CSS-in-real-browser rule). |
| S4 | **Prod promotion + write-smoke + soak** | Standard flow (F59 diff assertion, `config.js` checkout). Live end-to-end: self-register a throwaway founding customer on `rjbookstop.pulllist.app` → pending row with correct founding `tenant_id` → magic link works → admin approves → tear down. 24-hour soak. |
| S5 | **Retire MailerLite for founding + docs** | Remove/disable the dead webhook path; update `register-customer` contract in `technical-reference.md` (§ 3.6 EF inventory, § 13 F34/F72 notes) + `CLAUDE.md`; rotate the exposed webhook secret (now dead config). (rjbookstop.com's Brevo funnel is Rick's separate track — see § Adjacent — at most an optional link to the signup, not a wiring.) |

---

## In scope
- Provision the founding subdomain `rjbookstop.pulllist.app` (owns the apex plan's deferred S4 for the
  founding tenant).
- A native, in-app customer self-registration path on the founding branded login, with an abuse gate,
  replacing the MailerLite form + webhook for founding.
- Retiring MailerLite for the founding tenant; doc + contract updates.

## Out of scope (stop and ask before touching)
- **Non-founding (comicstore) native signup** — gated on F72 (email branding); founding-first here.
- **Phase 6 self-service *tenant* signup** and the wildcard-DNS/TLS spike — different surface entirely.
- **F72 multi-tenant email branding** itself — deferred; this workstream stays within founding branding.
- Any `config.js` / import-script change; billing; the apex marketing page (its own closed work).
- rjbookstop.com's Brevo marketing funnel — Rick's **separate project**, decoupled from PULLLIST (no
  `register-customer` / webhook wiring). Out of scope here; see § Adjacent. (Migrating MailerLite *into*
  PULLLIST is explicitly not the direction — signup goes native.)

---

## Adjacent / out-of-band (Rick's separate track — not this workstream)

- **rjbookstop.com → a Brevo marketing funnel.** Rick is migrating rjbookstop.com to Brevo as its **own
  project, with no PULLLIST data connection at this time** — a lead-generation funnel exposing potential
  customers to Ray & Judy's Book Stop services. It is **not** the account-creation trigger MailerLite
  was; native signup owns that now. The only (optional, non-integration) touchpoint is a plain **link**
  from the funnel to the `rjbookstop.pulllist.app` signup.
- **Future: automated weekly-shipment customer emails.** Rick's forward note — the Brevo platform may
  later drive automated weekly-shipment emails, developed as part of `import.js`. **Yet to be developed;
  not scoped here.** Caveat for whoever picks it up: per-customer "your reserved book arrived" mail needs
  PULLLIST reservation data, for which there is no PULLLIST→Brevo path today; a general "this week's
  shipment is in" broadcast to the funnel list would not. Settle that distinction when it's scoped.

---

## Risks
- **R1 — Public endpoint abuse.** A secret-less public signup can be spammed (junk pending rows,
  MailerSend cost, email reflection). Mitigation: Turnstile + honeypot + dedup + admin-approval gate;
  rate-limit table if needed. This is the primary risk and the § "hard design question" owns it.
- **R2 — Cross-tenant pending-row injection.** A caller posting another tenant's slug creates a pending
  row there. Low severity (approval gate; that admin declines). Mitigation: state the posture; monitor.
- **R3 — `index.html` regression.** Editing the tenant login branch could disturb the just-shipped apex
  split. Mitigation: start only after the apex soak closes; re-count auth callsites before/after (per
  the apex work's own gate); full Playwright suite incl. tenant isolation; real-browser mobile check.
- **R4 — Staging can't host the live subdomain.** `rjbookstop.pulllist.app` is prod-only (5.5
  asymmetry). Mitigation: verify the UI branch on staging via host stub/interception; verify the live
  domain at S4 on prod, same as `comicstore` was.
- **R5 — F91 GoTrue flakiness** intermittently 403s the Playwright auth fixtures. Known/filed; not a
  blocker but expect noise in the smoke gate — trace every failure to the filed cause before treating
  the suite as red.

---

## Completion criteria (finalized at plan open)
- [ ] `rjbookstop.pulllist.app` provisioned, TLS active, resolves to founding, renders branded login.
- [ ] Native signup endpoint live: throwaway self-registration creates a founding-tenant pending row +
      magic link + MailerSend email; abuse gate (Turnstile + honeypot + dedup) verified; fixtures torn
      down (live SELECT = 0 rows).
- [ ] "Create account" UI on the founding branded login, real-browser-verified desktop + mobile, no
      horizontal overflow; JS-disabled degradation unchanged.
- [ ] Auth-callsite count in `index.html` unchanged before/after; full Playwright suite green incl.
      tenant isolation (F15/F20).
- [ ] Prod write-smoke green: live self-register → correct founding `tenant_id` → magic link → admin
      approve → torn down; 24-hour soak elapsed and clean.
- [ ] MailerLite retired for founding: webhook path removed/dead, exposed secret rotated to dead config.
      (rjbookstop.com's Brevo funnel is Rick's separate track — an optional link to the signup, not a
      wiring; see § Adjacent.)
- [ ] Docs updated: `register-customer` contract in `technical-reference.md`; `CLAUDE.md` Edge Function
      notes; F72 disposition re-confirmed (comicstore native signup still gated on it); any finding filed
      from F93.
- [ ] This plan's status → Complete; `CLAUDE.md` updated.

---

## References
- `docs/apex-landing-tenant-subdomains.md` — the hostname-aware `index.html` front door this builds on;
  its deferred S4 (founding subdomain) is un-deferred here; the 5.5 prod-only-custom-domain asymmetry.
- `supabase/functions/register-customer/index.ts` — the endpoint adapted here (current MailerLite
  webhook + `?secret=` tenant resolution).
- `app.js:13-167` — `TenantContext` / `tenantSlugFromHostname()` / `NON_TENANT_HOSTS` (how the client
  knows its tenant, unauthenticated, from the host).
- `docs/technical-reference.md` § 13 — F72 (email branding, gates comicstore native signup), F34
  (per-tenant resolution history), F73/F74 (webhook-secret rotation precedent), F89/F90 (conversion /
  adoption analytics, related).
- `docs/tenant-onboarding-runbook.md` — where F72 is flagged as a tenant-2 real-customer prerequisite.
- `CLAUDE.md` § Credential Safety, § Standard Deployment Workflow, § Edge Functions.
