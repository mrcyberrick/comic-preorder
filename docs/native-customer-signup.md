# Native In-App Customer Self-Registration (PLAN)

**Status:** **In progress** (opened 2026-07-23).
Standalone pre-Phase-6 workstream; its own session, full
staging→prod discipline. **Not** a phase sub-deploy (Phase 5 closed 2026-07-15; Phase 6 not started).
**Author context:** Written 2026-07-23 (Rick + planning session) after the founding tenant's MailerLite
self-registration path broke (see § Trigger). Direction and the two gating decisions were settled with
Rick in the opening session — see § Settled decisions.
**Execution gate:** Do **not** open execution until the apex sub-deploy's 24-hour soak has closed
(`docs/apex-landing-tenant-subdomains.md` S6.5 — armed 2026-07-22T17:13:46Z, elapses
2026-07-23T17:13:46Z / ~1:13 PM ET). This work edits `index.html` (the tenant login branch the apex
work just shipped); do not touch that file while it is soaking.
**Cleared 2026-07-23T21:41Z** — soak window fully clock-elapsed (~4.5h past); Rick confirmed no
login-related issues on either `pulllist.app` or `comicstore.pulllist.app` during the soak. Note:
`apex-landing-tenant-subdomains.md` § Status / § S6.6 closeout had not yet been formally ticked at
the time this gate was checked — Rick's live confirmation was taken as satisfying the gate rather
than blocking on that paperwork; the apex plan's own closeout remains a separate, outstanding task.
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
4. **Abuse gate = Turnstile + honeypot + dedup, no rate-limit table for now** (confirmed at plan open,
   2026-07-23). Matches the plan's lead recommendation in § The hard design question. A `signup_attempts`
   table is added later only if abuse actually shows up in practice, not built speculatively.
5. **Endpoint shape = adapt `register-customer` in place** (confirmed at plan open, 2026-07-23). A
   direct-POST `{email, name, slug, turnstileToken, honeypot}` branch is added alongside the existing
   MailerLite webhook shape; tenant resolves from the posted `slug` instead of `?secret=`. The MailerLite
   webhook path stays present but harmlessly dead until § S5 removes it. No new `signup` function.
6. **Turnstile public site key is hardcoded in `index.html`** (confirmed at plan open, 2026-07-23) —
   Turnstile site keys are designed to be embedded client-side, like the Supabase anon key; no
   `config.js` edit needed. The `TURNSTILE_SECRET_KEY` stays server-side only, set by Rick as a Supabase
   Edge Function secret (unchanged from the original plan).

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
- **Future: weekly-shipment broadcast emails (not transactional).** Rick's forward note — the Brevo
  platform may later drive automated weekly-shipment emails, developed as part of `import.js`. **Confirmed
  scope (Rick, 2026-07-23): a mailing-list broadcast** ("this week's shipment is in") to the funnel list,
  **not** per-customer transactional mail — so it needs **no PULLLIST→Brevo data path** and stays fully
  within Brevo's separate track. **Yet to be developed; not scoped here.**

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
- [x] `rjbookstop.pulllist.app` provisioned, TLS active, resolves to founding, renders branded login —
      **Rick confirmed Active + SSL enabled 2026-07-23; HTTP 200 + valid TLS + byte-identical static
      bundle to the apex confirmed by curl; live-browser render confirmed green by Rick same day.**
- [x] Native signup endpoint live (S2, staging, 2026-07-23): `register-customer` adapted in place
      (`feature/native-customer-signup`, `458dbc0`) — throwaway self-registration created a founding-tenant
      pending row (`tenant_id` = `72e29f67-…`, correct); resubmit hit `already_exists` dedup; honeypot
      absorbed silently with zero rows created; legacy webhook path unchanged (bogus secret still 401).
      Turnstile verified against Cloudflare's documented "always passes" test keypair (Rick approved) —
      **real widget keys still needed from Rick for S3's live UI**, at which point `TURNSTILE_SECRET_KEY`
      swaps from the test value to the real one. Fixtures torn down; live SELECT = 0 rows (both test
      emails). Magic-link + MailerSend tail is byte-identical shared code with the already-proven webhook
      path (`provisionPendingCustomer`), not independently re-verified.
- [x] "Create account" UI on the founding branded login (S3, staging, 2026-07-23) — `index.html`
      `3da71e4` (+ fix `6020a5c`, see below). Real-browser-verified desktop + mobile via request
      interception under staging's real founding subdomain (`raysandjudys.pulllist.app`;
      `scripts/playwright/native-signup-verify.mjs`, local-only, 23/23 checks green): trigger shown
      only for founding; no horizontal overflow at 1440/390; JS-disabled degrades to today's unchanged
      login card. Real Turnstile widget (site key `0x4AAAAAAD8S0ONolq3newIs`, Rick's widget) renders
      correctly — screenshot review caught it defaulting to Cloudflare's light theme against the app's
      dark UI; fixed with `theme: 'dark'`. Turnstile pass/fail itself not asserted under headless
      automation (expected — that's exactly the traffic pattern Turnstile flags); real human pass/fail
      is S4's job.
      **Bug caught by the pre-push smoke gate (`6020a5c`):** the original founding-check compared
      `TenantContext.current().id` against `FOUNDING_TENANT.id`, which falls back to founding whenever
      `resolve_tenant_by_slug()` misses for the current hostname's slug — true for any slug absent from
      an env's DB, including both `rjbookstop` and `comicstore` on staging (comicstore is prod-only,
      the 5.5 asymmetry). That silently broke the pre-existing `12-apex-front-door.spec.ts` comicstore
      case (expects "Contact the shop" visible; got hidden). Fixed by comparing
      `tenantSlugFromHostname()` directly against `FOUNDING_TENANT.slug` — a pure client-side check
      with no RPC dependency, and more correct in production too (a broken/unresolvable non-founding
      subdomain now never falls back to showing founding's signup form).
- [x] Auth-callsite count in `index.html` unchanged before/after (`setSession` ×1, `verifyOtp` ×2,
      `token_hash` ×1, `access_token` ×1 — identical pre/post via grep count, re-verified after the
      fix too). Full Playwright suite incl. tenant isolation (F15/F20) — **green.** Run three times
      total (pre-fix/pre-push: 1 real bug caught + 7 F91 noise; post-fix/pre-push: 0 real failures, 14
      F91-flaky; post-fix/deployed: 0 real failures, 13 F91-flaky). Every single `Error:` line across
      all three runs traced to the filed F91 `bad_jwt` signature (`grep -c` confirmed zero exceptions
      each time) — none novel. Spec 12 (all 4 tests, incl. the fixed comicstore case) green in every
      run. 30/30 import unit tests green throughout.
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

## Deploy log

### S0 — Readiness gate — Complete 2026-07-23

`resolve_tenant_by_slug('rjbookstop')` live on prod and `resolve_tenant_by_slug('raysandjudys')` live
on staging both resolved correctly; `comicstore.pulllist.app` → 200 OK (regression baseline intact).

### S1 — Provision `rjbookstop.pulllist.app` — Domain/TLS complete 2026-07-23; live-browser check pending

Rick added the custom domain via the Cloudflare dashboard (comicstore procedure, no wildcard);
confirmed **Active** with **SSL enabled**. Verified by curl: HTTP 200, valid TLS, byte-identical static
bundle to `pulllist.app` (Cloudflare Pages serves one file set to every host, per the load-bearing
architectural fact). **Still needed:** Rick to open it in a real browser and confirm it renders the
founding branded login (not apex marketing) — curl can't execute the JS that sets
`data-front-door`/branding.

### S2 — Native signup endpoint — Complete on staging 2026-07-23

**Branch:** `feature/native-customer-signup` (off `staging`, not yet merged). **Commit:** `458dbc0`.

**Files:** `supabase/functions/register-customer/index.ts` (+287/−172) — refactored the shared
account-create/profile-insert/magic-link/MailerSend tail into `provisionPendingCustomer()`, called
verbatim by both the untouched legacy MailerLite webhook path (`?secret=`) and the new native
direct-POST path (`{email, name, slug, turnstileToken, honeypot}`, no `?secret=`). Added
`verifyTurnstile()` (Cloudflare siteverify call). No rate-limit table (per Gate 1a decision).

**Incident during this step (filed F93):** the Supabase CLI silently used workdir `C:\Users\richa`
instead of this repo for `deploy`/`list`/`download` — that directory is a separate, stale
(February 2026, pre-multitenancy) local Supabase project linked to the **production** project ref.
Two early `deploy` calls (without `--workdir`) pushed that stale code to **staging**, overwriting the
correct F34-resolved baseline; caught via behavioral testing, fixed within the session by redeploying
with an explicit `--workdir "<repo path>"` and byte-verifying the result matched the repo source. All
`--project-ref` values used were staging throughout — production was never touched. Full detail:
`technical-reference.md` § 13 F93. Mitigation adopted for the rest of this workstream: every Supabase
CLI function command passes an explicit `--workdir`.

**Verification (staging, `puoaiyezsreowpwxzxhj`):**
- Legacy webhook path unchanged: bogus `?secret=` → 401 `Unauthorized`, same as before the edit.
- Native path: no body → 400 `Invalid request body`; missing fields → 400 `email, name, and slug are
  required`; unset `TURNSTILE_SECRET_KEY` → 503 (fails closed, does not silently skip verification).
- Honeypot filled → 200 `{success:true}`, **zero rows created** (confirmed by live SELECT on
  `user_profiles`).
- `TURNSTILE_SECRET_KEY` set to Cloudflare's publicly-documented "always passes" test value
  (`1x0000...AA` — not a real secret; Rick approved setting this on staging) to exercise the full path
  without a live browser solving a real challenge.
- Full valid signup → `200 {success:true, user_id}`; live SELECT confirmed the `user_profiles` row:
  `status=pending`, `is_admin=false`, `tenant_id=72e29f67-…` (correct founding tenant, staging).
- Resubmit with the same email → `200 {success:true, note:"already_exists"}` — dedup confirmed, no
  duplicate row.
- Teardown: `auth.users` DELETE via GoTrue Admin API hit the filed **F91** intermittent `bad_jwt`
  rejection on the first attempt; succeeded on retry (200, then 404 on further retries confirming
  gone). Live SELECT for both test emails (`s2-throwaway-test-…@example.com`, `bot-test@example.com`)
  → `[]`, zero rows.
- Magic-link generation + MailerSend send were **not** independently re-verified — that code is
  byte-identical shared logic with the already-proven webhook path (`provisionPendingCustomer`), not
  new behavior introduced by S2.

**Left for S3:** real Turnstile widget (site key + secret key) from Rick — `TURNSTILE_SECRET_KEY` on
staging needs to swap from the test value to the real one before/at S3; the "Create account" UI on
`index.html`'s tenant branch, wired to the real site key (hardcoded per Gate 1 decision).

### S3 — "Create account" UI on the founding branded login — Complete on staging 2026-07-23

**Branch:** `feature/native-customer-signup` → `--ff-only` → `staging`, pushed (`6020a5c`), deployed to
`https://staging.pulllist.pages.dev/`.

**Files:** `index.html` (S3 build `3da71e4`, +163/-1; S3 fix `6020a5c`, +8/-3).
`scripts/playwright/native-signup-verify.mjs` (S3, new — local-only, never committed to any repo).

**Rick, in session:** created the real Turnstile widget (Cloudflare dashboard → Turnstile → Add Widget,
Managed mode, hostname `pulllist.app` — confirmed via Cloudflare's own hostname-management docs that
this automatically covers `rjbookstop.pulllist.app` as a subdomain, no need to add it separately);
site key `0x4AAAAAAD8S0ONolq3newIs` pasted to chat (public by design); secret key set directly as
`TURNSTILE_SECRET_KEY` on the staging Supabase project via the dashboard (never pasted to chat, per
the F73/F74 lesson), replacing S2's Cloudflare test value.

**Build.** The sign-in card's "Don't have an account?" line gained a third branch
(`#tenant-no-account-signup`) alongside the existing apex/tenant split, revealed only for the founding
subdomain. A new `#signup-form` (name, email, an `aria-hidden` off-screen honeypot, a lazy-loaded
Turnstile widget) toggles against `#sign-in-form` the same way `#set-password-form` already does, and
posts to `register-customer`'s S2 native path. Success shows a new "check your email" state
(`#signup-success-state`) rather than the existing auto-redirect success state, since this call returns
no session. Site key hardcoded per the Gate 1 decision.

**Bug caught by the pre-push smoke gate, fixed same session (`6020a5c`)** — see the completion-criteria
entry above for full detail: the founding check originally compared `TenantContext.current().id`
(RPC-resolved, falls back to founding on any DB miss) instead of the hostname-derived slug, which broke
the pre-existing comicstore front-door spec on staging. Fixed to compare `tenantSlugFromHostname()`
against `FOUNDING_TENANT.slug` directly — no RPC dependency, more correct in production too.

**Second bug, caught by Rick's real-browser test on deployed staging, fixed same session (`58905a4`).**
The site's CSP (`_headers`, A11 2026-07 review) locks `script-src` to `'self' 'unsafe-inline'` only —
Turnstile's `api.js` was outright blocked (`Refused to load the script... violates... script-src`).
**The local interception harnesses are structurally blind to this class of bug**: `route.fulfill()`
replaces the entire HTTP response including headers with a locally-controlled minimal set, bypassing
`_headers` entirely — the widget rendered perfectly in every automated check while being completely
broken on the real deployed site. Real-browser verification against the actual deployment is load-
bearing beyond CSS (the project's existing rule, two prior incidents) — this is the same lesson for
security headers. Fixed: added `https://challenges.cloudflare.com` to `script-src`, a new `frame-src`
directive carrying the same origin (the widget renders in an iframe; with no `frame-src` at all it
falls back to `default-src 'self'`, which would have blocked the iframe next), and to `connect-src` as
a precaution. Verified live: `curl -I https://staging.pulllist.pages.dev/` shows the updated CSP header
deployed. **Rick retried and confirmed the fix**: `api.js` loads, the widget mounts and renders
correctly (dark theme). The widget itself then returned Turnstile client error **110200 ("domain not
authorized")** — expected, not a bug: the widget's Hostname Management only has `pulllist.app`
registered (covers `rjbookstop.pulllist.app` as a subdomain, per Cloudflare's own docs), and
`staging.pulllist.pages.dev` is an unrelated Cloudflare-owned domain, not a subdomain of it. **Rick's
call: defer the real human-pass/fail test to S4 on prod**, where `rjbookstop.pulllist.app` is already
covered by the widget's hostname config — the originally-planned path (plan § R4). Everything short of
that one platform-scoped step is now confirmed working end-to-end on staging.

**Verification** (see completion criteria above for full detail): local interception harness 23/23
green (targeting staging's real founding slug `raysandjudys.pulllist.app`, not the prod-only
`rjbookstop.pulllist.app` — a distinction that mattered once the founding check became hostname-based).
Screenshot review caught the Turnstile widget rendering in Cloudflare's default light theme against the
app's dark UI; fixed with `theme: 'dark'`. Full Playwright suite green across three runs (pre-fix,
post-fix pre-push, post-fix deployed) — every failure across all three traced to the filed F91 GoTrue
flakiness, zero novel failures each time; spec 12 (incl. the fixed comicstore case) clean in every run.
Auth-callsite count unchanged. Real Turnstile human pass/fail deferred to S4 (live browser, prod).

**Left for S4:** Rick's prod EF deploy (`plgegklqtdjxeglvyjte`) + prod promotion (standard flow, F59
diff assertion, `config.js` checkout) + `TURNSTILE_SECRET_KEY` set on prod + live write-smoke on
`rjbookstop.pulllist.app` (self-register a throwaway founding customer → pending row w/ correct
founding `tenant_id` → magic link → admin approve → tear down) + 24-hour soak.

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
