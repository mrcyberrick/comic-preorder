# Apex Marketing Page + Universal Login (PLAN)

*(Formerly "Apex Landing + Founding-Tenant Subdomain." Re-centered 2026-07-20: the **marketing page
drives this development**; provisioning the founding tenant's own subdomain is **deprioritized/
deferred** — the founding tenant simply stays on the apex.)*

**Status:** **In progress** (opened 2026-07-21) — **S2 complete on staging 2026-07-21; S5 + S6 are
the remaining work.** Standalone sub-deploy; **not** bundled with any other work. Its own session,
full staging→prod discipline.
**F86/F88 gating — CLEARED 2026-07-22.** The earlier gate read: staging build may proceed during the
F86 legacy-key watch (staging-side static frontend, no shared surface with the production key
toggle), but **the production promotion is gated on F86/F88 closure**, because F88 predicted the F86
toggle would 401 every Edge Function's auto-injected service-role key — no freshly refactored prod
login page belongs in that window. **Both closed 2026-07-22:** F86's prod toggle flipped with V6/V7
green and both legacy keys confirmed dead; F88 verified false on staging *and* prod, before and
after the flip, with no Edge Function code change needed (`docs/f86-anon-key-migration.md`;
`technical-reference.md` § 13 F86/F88). **S6 is therefore unblocked** — it is now the only gate
S6 ever had, and it is satisfied.
**Execution model for S5/S6:** **CLI-orchestrated, Rick-in-the-loop.** A fresh Claude Code session
runs § S5/S6 Runbook top to bottom. It executes every repo / doc / Playwright step itself and
**pauses at the prod promotion merge** (§ S6 step 4) and at the two live-verification steps that
need a human browser. Self-contained — no chat context required.
**Type:** Front-door change — add a marketing page + keep a universal login on the apex. **Low
customer impact** (the apex never stops accepting logins). Standalone, ahead of Phase 6 — a
satisfied precursor to Phase 6's public front door, **not** gated on the Phase 6 wildcard-DNS/TLS
spike (see § Why not blocked on Phase 6).
**Author context:** Written 2026-07-20 (Rick). Goal evolved over the session to the **Hybrid tiering
model** (see § Strategic direction): apex = marketing + universal login (free tier); branded
`<slug>.pulllist.app` = premium, provisioned per paying tenant. The founding subdomain is no longer
a driving deliverable — the **final marketing page is what drives this work**.
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

Turn `pulllist.app` (the apex) into a **platform marketing page for prospective store owners that
also carries a universal sign-in** for existing customers. **The marketing page is the deliverable
that drives this work.** Branded per-store subdomains (`<slug>.pulllist.app`) stay a **premium**
option, provisioned per paying tenant the manual way — `comicstore.pulllist.app` is the existing
example. **The founding tenant keeps living on the apex; giving it its own subdomain is deferred**
(deprioritized 2026-07-20 — it adds migration/redirect work for little near-term value, and the apex
already serves the founding tenant well).

End state (**Hybrid** — chosen 2026-07-20; see § Strategic direction):
- `pulllist.app/` → platform marketing **plus a universal sign-in** that works for every tenant
  (a customer signs in here and lands in their own store via the profile branch). The **free-tier**
  front door.
- `rjbookstop.pulllist.app/` → **deferred** (a *future* premium branded front door for the founding
  tenant; not built now — founding stays on the apex).
- `comicstore.pulllist.app/` → tenant 2 branded login (already live — unchanged).
- Existing founding customers (bookmarks, printed URL, outstanding magic links pointed at
  `pulllist.app/...`) **keep working unchanged** — the apex never stops accepting logins, so there
  is no forced migration and no broken links.

---

## Strategic direction — subdomain as a premium tier (Rick, 2026-07-20)

The Hybrid is chosen deliberately as a **product tiering model**, not just a layout:
- **Free tier → apex.** Free tenants have no subdomain; their customers use the apex universal
  login (platform-branded pre-login; the tenant's own branding still applies *in-app* post-login
  via 5.3 `Branding.apply()`).
- **Premium tier → branded subdomain.** `<slug>.pulllist.app` — branded from first paint,
  marketing-free, the URL the shop promotes to its own customers — plus, as premium extras,
  per-tenant branded email links + sender identity (F72). A standard SaaS "custom/branded domain =
  paid plan" lever (Substack, Notion, Calendly, …).
- **Price on value, not cost.** Per Phase 6's own analysis a `*.pulllist.app` subdomain via a
  wildcard cert is ~free — so the premium justification is the *branded, marketing-free customer
  experience*, not cost-recovery.
- **It defers the hard infra.** Premium = low volume = keep provisioning subdomains the **manual**
  way (the 5.5 / comicstore custom-domain add); the Phase 6 wildcard-DNS/TLS + self-serve spike can
  wait until self-serve volume justifies it.
- **Free-tier-as-lead-gen (decide consciously).** Free tenants' customers see the apex platform
  pitch — a viral/acquisition surface and an upgrade nudge, at the cost of showing a free shop's
  customers "start your own shop." Deliberate call, not a defect.

**Out of scope here (deferred):** billing / plan enforcement / an upgrade flow — Phase 6 explicitly
defers billing. Until it exists, "premium" = a **manual, high-touch upsell** (operator provisions
the subdomain via the comicstore flow). This plan builds the *tier-agnostic front-door foundation*;
the paywall/tiering layer is later work.

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
new slugs** to serve instantly with zero manual DNS. The marketing-page + universal-login work does
not touch that at all — it's client-side presentation on the apex. And premium subdomains, when a
paying tenant wants one, are provisioned the **manual** way (one Cloudflare custom domain, exactly as
5.5 did for `comicstore`) — no wildcard required, low volume. So this can run as a focused standalone
sub-deploy now; it becomes a satisfied precursor when Phase 6 opens (Phase 6's public `/signup` lives
on the apex this work creates).

---

## Auth-redirect base URL — optional under the Hybrid (a premium branded-email feature)

**No longer blocking — the Hybrid keeps the apex a login surface, so nothing breaks.** Today the
invite / recovery / magic-link emails redirect to a **single per-project** `APP_BASE_URL` secret
(prod = `https://pulllist.app`, set in 5.2 S5, F67). Because the apex **retains** universal login
under the Hybrid, those links keep working exactly as today — the earlier "blocking dependency"
framing (from a draft where the apex *stopped* serving login) no longer applies. A per-tenant
redirect base URL is now an **optional premium enhancement**, not a prerequisite:
- **(i) Per-tenant redirect base URL** so a *premium* tenant's links target their own branded
  subdomain (founding → `rjbookstop.pulllist.app`, comicstore → `comicstore.pulllist.app`) instead
  of the apex. Ships with premium email branding; not needed for the free-tier apex experience.
- **(ii) Apex auth-completion is inherent** — the apex still runs the token handler, so outstanding
  links and pre-subdomain piloting keep working with zero new work.

- **Relation to F72:** F72 tracks the *email body branding* gap (`register-customer`'s
  founding-branded copy/`from` name). The redirect-target and body-branding halves share the same
  "emails aren't tenant-aware" root. Under the Hybrid **both are premium features**, bundled with
  the branded subdomain — neither is required for the free-tier apex experience.
- **The current single-`APP_BASE_URL` behavior is NOT a defect (corrected 2026-07-20 after Rick's
  review — an earlier draft wrongly flagged it as a candidate F91; no finding is filed).** Tenant 2
  (`comicstore`) invite/reset emails already redirect to the apex, not `comicstore.pulllist.app` —
  but this is **working, documented behavior**: `APP_BASE_URL` was introduced in 5.2 S5 only to
  de-hardcode URLs *per project* (F67), and multi-tenant email was explicitly deferred (F72). It
  has a genuinely useful property: because `TenantContext` resolves an authenticated user to their
  own tenant via the `user_profiles.tenant_id` profile branch (highest priority) on **any** host, a
  magic link landing on the apex still logs the user into the *correct* tenant. That means any
  tenant's users can complete auth via the apex **before that tenant's subdomain exists** — exactly
  the pre-subdomain piloting used for `comicstore`. **This plan must *preserve* that property (fix
  (ii)), not break it** — which is why the apex change is a conscious design decision, not a bug fix.
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
   - On the **apex** (`pulllist.app` / `www.pulllist.app`) → render **marketing + a universal
     sign-in** (the free-tier front door): platform pitch for prospective shops plus a persistent
     login that works for every tenant. Still run the auth-token handler first, so invite /
     recovery / magic-link tokens landing on the apex complete normally (covers outstanding links
     and pre-subdomain piloting). The apex **keeps** login — it does not become login-less.
   - Lead recommendation: keep the auth-token handling code path intact and branch *presentation*
     by host, so no auth logic is lost. (Alternative: split marketing into `index.html` and move
     login to `login.html`; rejected as lead because it repoints every magic link twice and
     duplicates the auth flow — but revisit if the marketing page grows heavy.)
3. **Apex deep app-paths keep working; a subdomain redirect is optional (premium polish).** Because
   the apex retains universal login and resolves authenticated users by profile, a founding customer
   hitting `pulllist.app/catalog.html` or an outstanding `pulllist.app/index.html?token_hash=…`
   **still works** with no redirect — nothing breaks. Optionally, a *premium* tenant may want its
   customers pushed to the branded subdomain: a host-scoped redirect (apex app-path →
   `<slug>.pulllist.app`, preserving `location.search` / `location.hash`) via a **zone-level
   Cloudflare Redirect Rule** or a **client-side redirect in `app.js`**. Note (**verify at
   execution**): Cloudflare `_redirects` matches on **path, not host**, and all hosts share one
   project, so `_redirects` alone cannot do a host-scoped redirect. Lead recommendation: skip for the
   free tier; add client-side for premium.
4. **The 5.2 founding-apex invariant is *partially* superseded.** 5.2 made "`pulllist.app` resolves
   to the founding tenant, identically to today" a hard invariant. Under the Hybrid the apex no
   longer *presents as* the founding tenant's app (pre-login it shows platform marketing/branding),
   but it **still accepts founding — and every tenant's — logins**, each resolving to its own tenant
   by profile. So the change is narrower than a full reversal: apex → marketing + universal login;
   the founding tenant additionally gets a branded home at `rjbookstop.pulllist.app`. Record the
   revised contract in 5.2's doc + `technical-reference.md`; update the Playwright founding-invariant
   / tenant-isolation specs accordingly. The `FOUNDING_TENANT` default in `resolve()` stays as a
   harmless safety fallback.
5. **Branding unchanged in mechanism** — `Branding.apply()` (5.3) already brands by resolved
   tenant; on `rjbookstop.pulllist.app` it renders founding branding exactly as the apex does today.

---

## Staging-vs-prod asymmetry (carried from 5.5 — only relevant if a subdomain is provisioned)

The marketing-page + universal-login work is testable **entirely on staging** (it's apex / host-branch
presentation — use a host stub + `?t=`). Separately, **if** a premium subdomain is ever provisioned,
a per-tenant custom domain **cannot be minted on `*.pages.dev`**, so a live subdomain is **prod-only**;
staging covers it via the `tenantSlugFromHostname()` host-parse unit check + a host stub, not a live
`<slug>.pulllist.app`. Note this asymmetry in the Deploy Log, same as 5.5 S1.

---

## Provisional sub-deploy shape (illustrative — finalized at plan open)

| #   | Title | Notes |
|-----|-------|-------|
| S0 | **Readiness gate (no writes)** | Re-read resolver + allowlist from disk; confirm founding slug resolves via RPC on both envs; confirm Cloudflare access to the `pulllist.app` Pages project; confirm `comicstore` custom domain still Active (regression baseline). (No finding to file — the single-`APP_BASE_URL` behavior is intentional; see § Auth-redirect base URL.) |
| S1 | **Per-tenant auth-redirect base URL — optional premium (deferrable)** | Make invite/recovery/magic-link redirect base per-tenant (option (a) or (b)); staging EF deploy → verify; prod EF deploy → verify. Bundle with F72 body-branding. **Not required for the free-tier apex** — defer unless bundling premium email this session. |
| S2 | **Apex marketing + universal login (hostname-aware `index.html`)** | Build the apex marketing page **with a persistent universal sign-in**; branch presentation by host; keep the full auth-token path on both branches. Staging-verify both branches via host stub + `?t=`. |
| S3 | **Optional premium redirect (skippable)** | *(Premium only.)* Apex app-paths → tenant subdomain, token/query preserved (client-side or CF Redirect Rule per verified mechanics). The free tier keeps working at the apex without it. |
| S4 | **(Deferred) Provision `rjbookstop.pulllist.app`** | *Deprioritized 2026-07-20 — founding stays on the apex.* If/when wanted: manual CF custom domain + TLS (5.5 procedure). Not part of the driving marketing-page work. The same manual flow provisions any *premium* tenant's subdomain. |
| S5 | **Supersede the 5.2 invariant + specs** | Revise the 5.2 founding-apex invariant (5.2 doc) + `technical-reference.md` § 3.1 / § 10.1 tenant-resolution contract; grep-sweep every restatement (R4); **add** a committed apex front-door spec — no existing spec needs rewriting (verified 2026-07-22, see runbook S5.0); branch the one unbranched sign-in line; file **F91**; full suite green. |
| S6 | **Prod promotion + soak + closeout** | Standard workflow (F59 diff assertion, `config.js` checkout, post-deploy write-smoke **on the apex as the founding tenant** — founding stays on the apex, there is no founding subdomain); **24-hour soak** (pinned 2026-07-22); verify an outstanding magic link end-to-end on prod; tick completion criteria. |

Order under the Hybrid is low-risk: the apex **keeps** login throughout, so nothing "flips" and no
outstanding link can break. With the founding subdomain deferred, the **driving work is essentially
just S2 (apex marketing + universal login)** plus the spec/doc updates (S5). S1, S3, and S4 are
deferred/premium and can land any time later, independently.

---

## In scope

- **The apex marketing page + a universal sign-in** (free-tier front door), via a hostname-aware
  `index.html` presentation branch. **This is the driving deliverable.**
- Partial supersession of the 5.2 founding-apex invariant + updated Playwright specs (the apex root
  now shows marketing pre-login).

**Deferred / not driving this work:**
- Provisioning the founding subdomain `rjbookstop.pulllist.app` — deprioritized; founding stays on
  the apex. (The manual 5.5 flow provisions any *premium* tenant's subdomain when one signs up.)
- Premium enhancements: per-tenant auth-redirect base URL + F72 email branding; optional
  apex→subdomain redirect. In scope only if explicitly bundled.

## Out of scope (stop and ask before touching)

- **Wildcard `*.pulllist.app` DNS/TLS + public `/signup`** — that is Phase 6. This work adds
  exactly one manual custom domain and a static marketing page, no self-serve provisioning.
- **Billing / plan enforcement / upgrade flow** — deferred (Phase 6 defers billing). "Premium" is a
  manual operator upsell until then (see § Strategic direction).
- **F72 email *body* branding + per-tenant redirect URLs** — premium enhancements; deferred unless
  explicitly bundled into this session. Not required for the free-tier apex experience.
- **Marketing-site content/design system beyond a first landing page** (copy, SEO, analytics
  pixels, multi-page marketing site) — scope the first landing page only; expansions are separate.
- **F86 legacy-key work** — unrelated; never bundle it into this sub-deploy. (The *staging build*
  may run during the F86 watch; only the **prod promotion** is gated — see § Status. Keeping Edge
  Functions out of scope is doubly important here, since that is exactly the layer F88 says is
  fragile around the toggle.)
- Any `config.js` / import-script change; any second real tenant onboarding.

---

## Risks

- **R1 — Founding customer disruption (much reduced under the Hybrid).** `pulllist.app` is the
  production URL on record. The Hybrid keeps the apex a login surface, so existing bookmarks,
  printed URLs, and outstanding invite/reset links **keep working unchanged** — the main disruption
  vector of the earlier (login-less-apex) design is gone. Residual risk is only in the `index.html`
  presentation refactor itself. Mitigation: S2 verifies both host branches green; short soak;
  write-smoke at S6.
- **R2 — Cloudflare host-scoped redirect mechanics unverified (only if the optional premium redirect
  is built).** `_redirects` is path-only; a host-scoped redirect needs a zone Redirect Rule or
  client-side handling. Mitigation: verify CF behavior at execution; lead toward the client-side
  redirect we fully control. Skippable for the free tier.
- **R3 — One-project/all-hosts confusion.** Any "put a file at the apex" instinct is wrong; the
  apex/subdomain split is client-side only. Mitigation: stated up front here; specs assert both
  branches from the same deployed file set.
- **R4 — Invariant-supersession drift.** 5.2's invariant is referenced across Phase 5 docs and the
  Playwright suite; missing one reference leaves a contradictory "apex → founding" claim.
  Mitigation: S5 grep-sweeps every reference before closeout.

---

## Completion criteria (finalized at plan open)

- [x] Apex `pulllist.app/` serves **marketing + a universal sign-in** that authenticates any
      tenant's customer into their own store (profile-resolved); `comicstore.pulllist.app` unchanged
      and green. — **Built and verified on staging 2026-07-21 (S2).** Universal/profile resolution
      proven by the tenant-isolation specs (tenant-B users authenticate via the apex host and land in
      tenant B). `comicstore.pulllist.app` cannot be exercised on staging (prod-only custom domain —
      the 5.5 asymmetry); its branch was verified by rendering the deployed file set under the real
      hostname via request interception, and its unchanged render asserted. **Re-verify live at S6.**
- [x] Existing founding front-door still works: an outstanding `pulllist.app/index.html?token_hash=…`
      completes auth at the apex, and `pulllist.app/catalog.html` loads for an authenticated founding
      customer (no forced migration; **founding remains on the apex**). — **Verified on staging
      2026-07-21:** spec 01 (magic-link arrival on the apex host → `catalog.html`, tenant source
      `profile`) green; live password sign-in through the apex overlay landed on `catalog.html`
      resolved to the founding tenant; an authenticated apex visit still forwards to the app.
- [ ] 5.2 founding-apex invariant contract revised (partial supersession) in the 5.2 doc +
      `technical-reference.md`; no stale/contradictory "apex → founding app" claim remains (grep-swept).
      — **S5.4 + S5.5 + S5.6.** Revise-in-place with a supersession banner; historical deploy-log rows
      and dated verification notes stay as written.
- [ ] Playwright founding-invariant / tenant-isolation specs updated to the revised contract and
      green; full suite green. — **Green half done (S2, 2026-07-21):** full suite 40/40 green against
      the deployed staging change, including tenant isolation (F15/F20). **No spec needed changing** —
      re-verified independently 2026-07-22: all 11 specs authenticate via magic link and assert
      post-login app state, which the Hybrid preserves exactly. **Resolved differently than planned:**
      rather than rewriting a spec, **S5.3 adds a committed `12-apex-front-door.spec.ts`**, because the
      apex front door otherwise has *zero* standing regression coverage — S2's `apex-verify.mjs`
      harnesses are not wired into `run-smoke.ps1`.
- [ ] The unbranched sign-in sign-up hint is branched per front door (`ax-when-apex` /
      `ax-when-tenant`), closing the S2 "known cosmetic nit" — **S5.2** (bundled at Rick's call
      2026-07-22).
- [ ] Post-deploy write-smoke on the apex as the founding tenant (reserve → correct founding
      `tenant_id` → cancel) clean; **24-hour soak** (pinned 2026-07-22) fully elapsed and clean.
- [ ] `comicstore.pulllist.app` verified live post-deploy as an unchanged branded login — **its first
      real test**, since a tenant custom domain cannot exist on staging (5.5 asymmetry).
- [ ] An outstanding prod magic link completes end-to-end at the apex: panel opens before the
      marketing page, auth completes, lands resolved to the correct tenant.
- [ ] F72 disposition updated; no new finding filed for the single-`APP_BASE_URL` behavior
      (confirmed intentional). **F91 filed** for the residual `technical-reference.md` drift outside
      the tenant-resolution contract; next free ID → **F92**.
- [ ] Deferred items noted: founding subdomain (`rjbookstop.pulllist.app`) and premium enhancements
      (per-tenant redirect URLs, F72 email branding, apex→subdomain redirect) — built only if
      explicitly bundled, else explicitly deferred.
- [ ] This plan's status → Complete; `CLAUDE.md` updated; Phase 6 stub notes the satisfied precursor
      (**precursor, not the gate** — Phase 6 stays blocked on the wildcard-DNS/TLS spike).

---

## Deploy log

### S2 — Apex marketing + universal login — **Complete on staging 2026-07-21**

**Branch:** `feature/apex-marketing-page` → `--ff-only` → `staging` (`250bb9a`), pushed; CF Pages
auto-deployed `https://staging.pulllist.pages.dev/`. **Not promoted to production** (gated on
F86/F88 per § Status).

**Files:** `index.html` (+321/−6), `apex.css` (new, 381 lines), `assets/hero.jpg` (new, 135 KB),
`assets/pulllist-logo.png` (new, 23 KB). No `config.js`, no `app.js`, no Edge Function, no DB.

**How the split works.** A pre-paint inline script in `<head>` sets `data-front-door` on `<html>`;
`app.js` re-asserts it from the canonical `tenantSlugFromHostname()` the moment it loads, so
`NON_TENANT_HOSTS` remains the single source of truth and the head copy only prevents a flash. All
apex CSS is namespaced `.ax-*` / `--ax-*` and scoped to `:root[data-front-door="apex"]`, so a tenant
subdomain renders exactly as before. **With JS disabled the page degrades to today's login card**
(marketing is hidden until the apex is positively identified).

**Auth integrity.** The token block is byte-identical — the diff removes only 6 presentation lines.
Callsite audit before/after: `db.auth.setSession` ×1, `db.auth.verifyOtp` ×2, `token_hash` read ×1,
`access_token` read ×1 — unchanged. One *new* read-only site: the head script's detection regex,
which opens the sign-in panel before first paint so an invite/recovery/magic-link token never lands
behind marketing. `#signin` is also a deep link into the panel.

**Execution decisions (Rick, in session):**
- **Sign-in presentation** — sticky-header `Sign in` opening a full-screen overlay, plus an
  "Already have an account? Sign in →" line in the hero. Chosen over an inline sign-in band so the
  approved hero composition is untouched. Overlay uses `inert` on the background, Esc/backdrop close,
  focus-in on open and focus-restore on close.
- **Hero stats card** — kept, with a `Sample dashboard` caption added. Unlabelled figures on a public
  page would read as real platform metrics; the design reference calls them illustrative.
- **CTA destination** — `Start free` / `Get started` anchor to a new `#contact` section.
  Self-service signup is Phase 6. *(Revised in the same session, `b38cde3`: the phone number was
  removed in favour of **pulllist@mrcyberrick.us**, set in mono because an address must be readable
  and copyable and Bebas is uppercase-only. Location stays town-level — **no street address is
  recorded anywhere in the repo**, so none was invented.)*
- **Display type** — **Bebas Neue** (already loaded by `style.css`), not the mockup's
  `system-ui` weight-900 stopgap. The design reference asks for an embedded condensed grotesque;
  Bebas is the app's own display face, so the marketing page and the app read as one product at zero
  extra network cost. Body stays IBM Plex Sans; mono utility stays the system stack.
- **Apex-branch copy is tenant-neutral.** Under a universal login the founding shop's name must not
  greet another tenant's invited customer, so the shop logo, `— Monthly Pre-Orders` tagline, shop
  footer and the invite banner's "Ray & Judy's Book Stop has set up an account for you" are all
  tenant-branch-only; the apex shows the PULLLIST mark and neutral wording. The tenant branch keeps
  the original strings verbatim.
- **Hero is a CSS `background-image`, not an `<img>`** — so a tenant subdomain, where the marketing
  block is `display:none`, never downloads the 135 KB photo. `object-position` → `background-position`
  keeps the design reference's three crop knobs (62% / 80% / 85%) exactly.

**Deviations from the mockup** (all deliberate, all noted): the unused `.releases` cover-carousel CSS
was dropped (already removed from the markup for copyright); `Explore all features →` and the `FAQ`
nav item were dropped as having no destination; the fake `EN ▾` language chrome was dropped; the six
feature tiles are a 3×2 grid (`auto-fit` gave a ragged 4+2 at full width); the dev-note placeholder
under the Branded price reads `Pricing on request`.

**Verification.**
- *Real-browser, both branches, local tree* — 36 checks green via request interception under the real
  hostnames `pulllist.app`, `www.pulllist.app`, `staging.pulllist.pages.dev`, `comicstore.pulllist.app`.
  Each host's branch was cross-checked against `app.js`'s own `tenantSlugFromHostname()` in-page, so
  the head script and the canonical resolver are proven to agree. Harness:
  `scripts/playwright/apex-verify.mjs` (local-only).
- *Real-browser, deployed staging* — 19 checks green including a **live password sign-in through the
  apex overlay** with a throwaway founding-tenant user → `catalog.html`, `TenantContext.source() ===
  'profile'`, correct founding `tenant_id`; user deleted and absence confirmed by live SELECT
  (`[]`). Harness: `scripts/playwright/apex-live-verify.mjs` (local-only).
- *No horizontal overflow* asserted at 1440 and 390 px on both branches, with the overlay open and
  closed — `scrollWidth === clientWidth` every time. Screenshots inspected at both widths.
- *Full smoke suite* — 40/40 Playwright + 30/30 import unit tests green **after** the deploy
  (exit 0), including tenant isolation F15/F20. Synthetic tenant torn down by `globalTeardown`.

**Two defects found by screenshot inspection and fixed before the merge** (both invisible to
assertions, per the "verify CSS in a real browser" rule): the founding shop's logo leaked onto the
platform sign-in panel because the card's inline `style="display:flex"` out-ranked the hide rule
(fixed with `!important` + `display: revert`); and the mobile header wrapped both buttons onto two
lines each while hero microcopy sat on bright sky (fixed with `white-space: nowrap`, hiding the
header's marketing CTA ≤620 px, and a full vertical scrim at ≤620 px).

**Follow-up pass (`b38cde3`, same session — Rick's review of the deployed page).** The six feature
tiles were bare icon+text and read as one undivided block next to the carded how-it-works steps, and
neither grid responded to the pointer. Changes: tiles became separated cards on the step card's
treatment, so both grids read as one system; the unicode glyphs (`↻ ✦ ★ ▤ ✉ ▣`) were replaced with
six stroked SVG icons that each depict the feature (import-to-tray, window + cursor, repeat cycle,
clipboard + check, envelope, shield + check), stroked with `currentColor` since `var()` does not
resolve in SVG presentation attributes; both grids now lift 3 px on hover with a warmed surface and
a red border, the feature icon tile scaling and its glow growing. The how-it-works step adds one
content-linked touch — the red segment under the step number runs the full rule width on hover
(32 px → 305 px, asserted). `prefers-reduced-motion: reduce` drops every transform while keeping the
colour and rule changes. Re-verified: 46 local checks + 19 live checks + 40/40 smoke, all green.

**Design-review pass (`b247796`, same session).** Rick removed the founding shop's
name/location from the contact block — on a *platform* page it read as PULLLIST's own address, and
no founding-shop string now remains anywhere in the marketing markup (asserted). A review at
1440/1180/834/390 then found: (a) **a regression from that removal** — the removed line was carrying
the gap, so the Sign in button touched the email's underline (spacing moved onto `.ax-email`, and the
≥16 px clearance is now asserted rather than eyeballed); (b) how-it-works collapsed to one column at
900 px, leaving three near-empty full-width cards with the rule stretched across dead space — now
collapses at 780 px so tablet keeps three columns; (c) the integration strip was one row of three
fragments with the closing sentence wrapping ragged — now a centred stacked statement; (d) pricing
cards were the only card grid ignoring the pointer — same hover, with the Branded card brightening
its red edge; (e) the footer was decorative — now two rows, wordmark + real nav (including sign-in)
over the tagline and payments disclaimer. No horizontal overflow at any of the four widths.

**Known cosmetic nit, not fixed:** the sign-in card's pre-existing "Don't have an account? Contact
the shop and we'll get you set up." is ambiguous on the apex ("which shop?"). Left as-is — it is
pre-existing copy and out of this step's scope. Worth a copy pass at S5/S6.

**Left for later steps:** S5 (supersede the 5.2 founding-apex invariant in the 5.2 doc +
`technical-reference.md`, grep-sweep, add specs asserting the marketing branch) and S6 (prod
promotion + write-smoke + soak) — **S6 stays blocked on F86/F88.** S1/S3/S4 remain deferred/premium.
*(F86/F88 both closed 2026-07-22 — S6 unblocked; see § Status.)*

### S5 — Supersede the 5.2 invariant + add front-door coverage — **Complete on staging 2026-07-22**

**Branch:** `feature/apex-invariant-supersession` → `--ff-only` → `staging`, pushed. Rebased twice
mid-session onto two doc-only commits that landed on `staging` first (F91, F92 — see below), keeping
history linear for the ff-only merge.

**Files:** `index.html` (S5.2, +2/−1 — see deviation note below), `docs/phase-5.2-slug-id-routing-rpc.md`
(S5.4, supersession banner), `docs/technical-reference.md` (S5.5, § 3.1/§ 10.1 tenant-resolution
contract), plus the two `F91`/`F92` doc-only commits landed directly on `staging`.
`scripts/playwright/tests/12-apex-front-door.spec.ts` (S5.3, new — local-only, never committed to
any repo).

**Deviations from the runbook, all verified against disk/live state, none blocking:**

1. **S5.2 verify-count arithmetic.** The runbook predicted `ax-when-tenant → 7 lines (was 6)` and
   `git diff --stat → +3/-1`. Actual, re-counted from disk against the byte-exact `old_str`/`new_str`
   substitution: `ax-when-tenant` → **6 lines** (baseline 5: 290/298/315/324/402, +1 new — matching the
   runbook's own footnote math, which the main verify line contradicted) and diff → **+2/-1** (the
   given `old_str`/`new_str` is unambiguously a 1-line-removed/2-line-added substitution). The edit
   itself matches the specified blocks byte-for-byte; only the runbook's predicted counts were off.
   `ax-when-apex → 5 (was 4)` and `'Contact the shop' → 1 line` both matched exactly as predicted.
2. **S5.3 gate — baseURL serves the *deployed* build, not local disk.** Finding 3 in the runbook's
   planning notes assumed marketing assertions needed no host stub since `staging.pulllist.pages.dev`
   is in `NON_TENANT_HOSTS`. True for branch *detection*, but S5.3 runs *before* S5.8's merge/deploy —
   so the live site still served the pre-S5.2 copy, and the spec's "Your shop can" assertion failed
   against real deployed content that didn't yet exist there. Fixed by extending the spec's request
   interception (already used for the tenant branch, lifted from `apex-verify.mjs`) to *all* relevant
   hosts including `staging.pulllist.pages.dev`, so the pre-merge gate tests local disk state
   consistently for both branches — matching how S2's own `apex-verify.mjs` worked. All 4 new tests
   green after the fix, repeatedly.
3. **F91 — GoTrue Admin API intermittently rejects new-gen `sb_secret_` keys (unrelated to this
   diff).** Two full `run-smoke.ps1` runs each surfaced intermittent `bad_jwt`/"unrecognized kid"
   403s from Supabase's Admin API in the shared `fixtures/auth.ts`, hitting a different spec each
   time (07/09/10/11 on run 1; 04/07/09/10/11 on run 2 — worsening, not settling). Spec 12 (this
   session's actual deliverable) passed clean in every run, all 4+ times it was executed. Confirmed
   via a format-only check (no secret value exposed) that `SUPABASE_SERVICE_KEY` is correctly the
   new-gen `sb_secret_` "magic_link_tooling" key (not a stale credential) — the GoTrue Admin API
   itself is what intermittently mishandles that key format, consistent with F88's finding that only
   Edge Functions' JWT-shaped auto-injected key reliably authenticates against those endpoints. Rick's
   call: file it (F91) and proceed once every failure across all runs traced to this one filed cause —
   verified via an isolated re-run of every previously-failed spec (0 non-F91 failures). **This bumped
   the F-number sequence:** F91 was reserved in this plan's § Status for S5.7's tech-reference-drift
   finding; since the GoTrue issue was discovered first and had to be filed to unblock the S5.3 gate,
   it claimed F91, and S5.7's finding became **F92** instead. Full entries: `technical-reference.md`
   § 13 F91/F92.

**Verification:**
- S5.0 pre-flight: all gates green (clean tree, F90 confirmed highest before either new finding,
  `TENANT_SLUG_MAP` → 0 in `app.js`, `_source = 'subdomain'` → 1, 11 pre-existing specs confirmed).
- S5.3 gate: full suite run 3 times total (2 full + 1 isolated re-run of every affected spec). Spec
  12 (4 tests) green every time. Every non-12 failure traced to F91 (confirmed via isolated re-run:
  4 failures, all `bad_jwt`, 0 other error types). Treated as gate-satisfied per Rick's explicit call.
- S5.5 grep verify: `TENANT_SLUG_MAP` → 2 lines total (not the predicted 1) — the second hit
  (`technical-reference.md` F71 entry, "Why pre-existing") is past-tense historical narrative about
  an already-resolved finding, not a live-contract claim; does not describe the map as currently
  existing. `'subdomain'` → 1 line and `tenantSlugFromHostname` → 3 lines both matched exactly.
- S5.6 R4 grep-sweep: re-ran both patterns fresh (not trusting the plan's prior list). Every hit
  beyond the two already revised in S5.4/S5.5 is dated/historical — deploy-log rows, ticked
  completion-criteria, dated verification notes from sub-deploys 5.1–5.5 (all closed 2026-06-14 →
  2026-07-15, predating this work) — describing what was verified *then*, not a claim about today's
  apex presentation. No additional live-contract claim found requiring revision.

**Left for S5.8/S6:** ff-only merge to staging + push + re-run smoke against the deployed build (S5.8,
next); S6 prod promotion + 24h soak + closeout, per plan.

---

## S5 / S6 Runbook (written 2026-07-22; execute in a fresh CLI session)

> **Read first:** `CLAUDE.md` in full; this file in full; `docs/phase-5.2-slug-id-routing-rpc.md`
> (the invariant S5 revises). **Re-read every target file from disk before editing** — the
> `old_str` blocks below were captured 2026-07-22 and are byte-exact as of that date. Any mismatch
> is a **halt**, not a nudge: re-derive the target from disk and report.
>
> **Scope fence.** S5 and S6 are the only steps in play. **S1, S3, S4 stay deferred/premium** — do
> not build a per-tenant redirect base URL, an apex→subdomain redirect, or a founding subdomain.
> **Founding stays on the apex.** If something looks related but is not listed below, stop and ask.

### Planning-time findings that shape these steps (verified against disk 2026-07-22)

1. **No existing Playwright spec needs rewriting** — independently re-verified, not taken from S2's
   note. All 11 specs in `tests/` authenticate via `generateMagicLink()` and assert **post-login**
   app state (`catalog.html`, `TenantContext.source()`, tenant isolation). None asserts the
   `index.html` **pre-login** presentation, which is the only thing the Hybrid changed. S2's claim
   holds.
2. **But the apex front door has zero standing regression coverage.** `run-smoke.ps1` runs
   `npm test` then `npx playwright test` over `tests/*.spec.ts` **only**. S2's harnesses
   (`apex-verify.mjs`, `apex-live-verify.mjs`) are *not* wired in — they were one-off runs. Nothing
   in the gate would catch an `index.html` edit that breaks the marketing/tenant split. **S5 closes
   this** by adding a committed spec (Rick's call, 2026-07-22).
3. **The suite's `baseURL` already renders the apex branch.** `playwright.config.ts` uses
   `https://staging.pulllist.pages.dev/`, which is in `NON_TENANT_HOSTS` →
   `tenantSlugFromHostname()` returns `null` → `data-front-door="apex"`. So marketing assertions
   need **no host stub**; only the *tenant* branch needs request interception.
4. **`technical-reference.md` is stale beyond the invariant.** § 3.1 still presents
   `TENANT_SLUG_MAP` as the live anon slug mechanism ("will be replaced with an RPC once a second
   tenant exists") — it was **removed at 5.2 S6, 2026-06-15** — and omits the subdomain branch
   entirely; § 10.1's `source()` enum omits `'subdomain'`. The doc header reads *"Last verified:
   post Phase 3.8 soak, May 2026."* **S5 fixes the tenant-resolution contract only; the rest of the
   drift is filed as F91** (Rick's call, 2026-07-22 — keeps S5 scoped, gives the rest a real owner).
5. **Next free finding ID = F91.** Confirmed by enumerating `#### F<n>` headings in
   `technical-reference.md` § 13 — highest filed is **F90**. Re-confirm before filing.

---

### S5 — Supersede the 5.2 invariant + add front-door coverage

**Nature of this step:** *not* doc-only. It carries one `index.html` copy change (the branch fix
below), so it rides a **feature branch**, not a direct `staging` commit. The doc commits are
separate commits on that same branch — split by subject, per § Commit discipline.

#### S5.0 — Pre-flight gates (halt on any mismatch)

```powershell
git rev-parse --abbrev-ref HEAD     # → staging
git status --short                  # → clean (untracked scratchpad/ is acceptable)
git pull origin staging
```

- Confirm `docs/technical-reference.md` § 13's highest finding is **F90** → next free **F91**:
  ```powershell
  Select-String -Path docs\technical-reference.md -Pattern '^#### F\d+' | Select-Object -Last 5
  ```
- Confirm the planning-time findings above still hold:
  ```powershell
  Select-String -Path app.js -Pattern 'TENANT_SLUG_MAP'          # → 0 lines (removed at 5.2 S6)
  Select-String -Path app.js -Pattern "_source = 'subdomain'"    # → 1 line
  (Get-ChildItem "C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts\playwright\tests\*.spec.ts").Count   # → 11
  ```
- **Halt** if `TENANT_SLUG_MAP` returns anything but 0 — the § 3.1 rewrite below would then be
  describing something other than live code.

#### S5.1 — Branch

```powershell
git checkout -b feature/apex-invariant-supersession
```

#### S5.2 — `index.html`: branch the one unbranched sign-in line

The sign-in card's sign-up hint renders on **both** front doors, so on the apex "the shop" has no
referent. Fix it in the established `ax-when-apex` / `ax-when-tenant` idiom already used at lines
297, 314 and 323. **The tenant string stays byte-identical**, including its `<br>`.

`index.html` — target captured 2026-07-22 at lines 378–381 (straight ASCII apostrophes, verified by
`od -c`; do **not** substitute typographic quotes):

`old_str`:
```
      <p style="margin-top:10px;font-size:0.78rem;color:var(--text-muted);
                text-align:center;line-height:1.6">
        Don't have an account? Contact the shop and<br>we'll get you set up.
      </p>
```

`new_str`:
```
      <p style="margin-top:10px;font-size:0.78rem;color:var(--text-muted);
                text-align:center;line-height:1.6">
        <span class="ax-when-apex">Don't have an account? Your shop can<br>set one up for you.</span><span
              class="ax-when-tenant">Don't have an account? Contact the shop and<br>we'll get you set up.</span>
      </p>
```

**Why this shape:** `.ax-when-apex` is `display:none !important` by default and only revealed under
`:root[data-front-door="apex"]` (`apex.css:59–61`), so the tenant branch is unchanged and the
**JS-disabled degradation still lands on the tenant login card** — the S2 property this must not
break. The two `<span>`s are butted together exactly as lines 314–315 do, so no whitespace text node
appears between them.

**Verify:**
```powershell
Select-String -Path index.html -Pattern 'ax-when-apex'    # → 5 lines (was 4)
Select-String -Path index.html -Pattern 'ax-when-tenant'  # → 7 lines (was 6)
Select-String -Path index.html -Pattern 'Contact the shop' # → 1 line, inside ax-when-tenant
git diff --stat index.html                                 # → 1 file, +3/-1
```
*(Counts derived by literally counting occurrences in `new_str` against the captured baseline —
`ax-when-apex` at 294, 297, 314, 323 + 1 new; `ax-when-tenant` at 290, 298, 315, 324, 402 + 1 new,
plus the class's own `apex.css` rule is **not** in this file. Re-count from disk if the baseline
grep differs.)*

Commit:
```
fix(apex): branch the sign-in sign-up hint per front door (S5)
```

#### S5.3 — Add the committed apex front-door spec

New file: `C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts\playwright\tests\12-apex-front-door.spec.ts`
(**local-only — the Playwright suite is never committed to any repo**; see `CLAUDE.md` § What's
tracked vs local-only).

It must assert, against the **deployed staging build**:

- **Apex branch** (plain `goto('/')`, no stub — `baseURL` *is* an apex host per finding 3):
  - `document.documentElement.dataset.frontDoor === 'apex'`
  - the marketing block is visible; the PULLLIST authmark renders and **no founding-shop string**
    appears anywhere in the markup (S2 asserted this after the design-review pass — keep it)
  - the sign-in panel is **closed** by default, and the new apex copy (`Your shop can`) is the
    variant present while `Contact the shop` is not rendered
  - `#signin` and a `?token_hash=` URL each open the panel **before first paint**
    (`data-signin="open"`) — this is the auth-integrity property, the most important assertion here
  - `scrollWidth === clientWidth` at 1440 and 390 px, panel open and closed
- **Tenant branch** (request interception under `comicstore.pulllist.app`, the S2 `apex-verify.mjs`
  technique — a real tenant host cannot exist on `*.pages.dev`, the 5.5 asymmetry):
  - `data-frontDoor === 'tenant'`; marketing hidden; the original login card renders
  - the `Contact the shop` variant is the one shown
- **Cross-check** (the guard that matters): in-page, assert the head script's decision equals
  `app.js`'s canonical `tenantSlugFromHostname()` result for that host — so the duplicated detection
  can never silently drift.

Lift the interception setup from `apex-verify.mjs` rather than reinventing it. Keep the harnesses in
place; this spec supersedes them **as the gate**, not as a debugging tool.

**Run the full suite** (this is the S5 gate):
```powershell
cd "C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts\playwright"
.\run-smoke.ps1
```
**Expected: exit 0, 30/30 import unit tests + all Playwright specs green, now including 12.** Stop
on any failure. Note the new total in the deploy log — do not write "40/40" from memory.

> **Do not edit `run-smoke.ps1`.** Adding a spec file needs no runner change, and the runner carries
> the BOM hazard that silently swallowed its entire Playwright stage on 2026-07-16 (`CLAUDE.md`
> § Known Issues). If it ever *is* edited, restore the BOM and verify the script still reaches its
> last stage.

#### S5.4 — Revise the 5.2 invariant

`docs/phase-5.2-slug-id-routing-rpc.md` — the blockquote at line 14. **Revise, do not delete:** 5.2's
invariant was correct when written and its deploy-log rows are history. Add the supersession inline.

`old_str` (the trailing sentence of the § Founding-tenant invariant blockquote):
```
> **Founding-tenant invariant (parent completion criterion for every 5.x sub-deploy).** 5.2 changes the tenant-resolution path — the single most behavior-sensitive surface in the app. The hard invariant: **on `pulllist.app` (apex), `staging.pulllist.pages.dev`, `pulllist.pages.dev`, `localhost`, and any `*.pages.dev` preview, resolution lands on the founding tenant, identically to today.**
```

`new_str`:
```
> **Founding-tenant invariant (parent completion criterion for every 5.x sub-deploy).** 5.2 changes the tenant-resolution path — the single most behavior-sensitive surface in the app. The hard invariant: **on `pulllist.app` (apex), `staging.pulllist.pages.dev`, `pulllist.pages.dev`, `localhost`, and any `*.pages.dev` preview, resolution lands on the founding tenant, identically to today.**
>
> **⚠️ PARTIALLY SUPERSEDED 2026-07-22** by `docs/apex-landing-tenant-subdomains.md` (S2/S5). The **resolution** half still holds exactly as written — those hosts still resolve to the founding tenant, and `tenantSlugFromHostname()` still returns `null` for every one of them. What changed is **presentation, not resolution**: the apex root now renders platform marketing + a *universal* sign-in pre-login, instead of presenting as the founding tenant's own branded login. Post-login behavior is unchanged — an authenticated user resolves to their own tenant by profile on any host, so founding customers, bookmarks and outstanding magic links keep working at the apex. The `FOUNDING_TENANT` default in `resolve()` remains as a safety fallback. **Read the revised contract as: apex → marketing + universal login → each user's own tenant by profile.**
```

The **rest of the 5.2 file is history and must not be rewritten** — the S3/S7 deploy-log rows and the
S7 "founding-apex invariant" checks record what was true and verified on 2026-06-15. The banner above
governs how they are read.

Commit:
```
docs: revise the 5.2 founding-apex invariant — presentation superseded, resolution intact (S5)
```

#### S5.5 — Revise the `technical-reference.md` tenant-resolution contract

Three edits. **Scope fence:** tenant-resolution contract *only*. The other stale claims in these same
sections go to F91 (S5.7) — do **not** fix them here.

**(a) § 3.1 — the resolution order + the dead `TENANT_SLUG_MAP` paragraph** (captured at lines
132–142):

`old_str`:
```
**In the web app** (`app.js`), the `TenantContext` module resolves the
active tenant before any call that needs it. Resolution order:

1. Authenticated user's `user_profiles.tenant_id` (looked up on page load).
2. `?t=<slug>` query parameter (persisted to `sessionStorage` for the tab).
3. Founding tenant fallback.

The slug-to-id mapping for unauthenticated lookups is hard-coded in
`TENANT_SLUG_MAP` because the `tenants` table is not readable by anon. This
is acknowledged scaffolding; the comment in `app.js` notes it will be
replaced with an RPC once a second tenant exists.
```

`new_str`:
```
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
```

**(b) § 10.1 — the `source()` enum** (captured at line 1136):

`old_str`:
```
TenantContext.source()        // → 'profile' | 'query' | 'session' | 'default'
```
`new_str`:
```
TenantContext.source()        // → 'profile' | 'subdomain' | 'query' | 'session' | 'default'
```

**(c) § 10.1 — the resolution-order restatement** (captured at lines 1139–1140):

`old_str`:
```
Resolution order: authenticated profile → `?t=<slug>` query param →
sessionStorage → founding tenant fallback.
```
`new_str`:
```
Resolution order: authenticated profile → subdomain (`tenantSlugFromHostname()`)
→ `?t=<slug>` query param → sessionStorage → founding tenant fallback.
```

**Verify (a)–(c):**
```powershell
Select-String -Path docs\technical-reference.md -Pattern 'TENANT_SLUG_MAP'
# → 1 line only, and it must be the new "was removed at 5.2 S6" sentence.
Select-String -Path docs\technical-reference.md -Pattern "'subdomain'"   # → 1 line (§ 10.1 enum)
Select-String -Path docs\technical-reference.md -Pattern 'tenantSlugFromHostname'  # → 3 lines
```
**Halt** if the first grep returns a line still presenting the map as live.

Commit:
```
docs: correct technical-reference tenant-resolution contract (post-5.2 RPC + subdomain, apex front door) (S5)
```

#### S5.6 — R4 grep-sweep (the step that actually closes Risk R4)

Sweep for any *live-contract* claim that the apex presents as the founding tenant's app. **Historical
records — deploy-log rows, completed completion-criteria, dated verification notes — are history and
must stay as written.** The distinction is: *does this sentence tell a future reader what the system
does today?* Only those get revised.

```powershell
cd "c:\Users\richa\OneDrive\Documents\(Work)\BookStop\repo\comic-preorder"
Select-String -Path docs\*.md, CLAUDE.md, README.md -Pattern 'founding-apex|apex.{0,80}founding|founding.{0,80}apex' -AllMatches
Select-String -Path docs\*.md, CLAUDE.md, README.md -Pattern 'invariant' -AllMatches
```

Planning-time sweep result (2026-07-22 — **re-run, do not trust this list**): the only *live-contract*
statements are the ones handled in S5.4 and S5.5. Everything else is historical:
`phase-5.3-per-tenant-branding.md` (S6 verification steps, dated 2026-06-15),
`phase-5.5-second-tenant-onboarding.md:208` (a 5.5-execution check),
`phase-5-second-tenant-onboarding.md:6,28` (Phase 5's own scope statement),
`phase-5.1/5.4` completion criteria, and `technical-reference.md:2293` (F71's dated status note).
`docs/tenant-onboarding-runbook.md:111` was checked specifically and is **fine** — it asserts
`https://pulllist.app/` returns `200` ("founding unaffected"), which remains true.

Record the sweep result in the deploy log — including anything found that this list did not predict.

#### S5.7 — File F91

Use the `/file-finding` skill. **F91 — `technical-reference.md` carries pre-Phase-5 claims outside
the tenant-resolution contract.** Inventory, all verified 2026-07-22:

| Location | Stale claim | Reality |
|---|---|---|
| Header, line 5 | "Last verified: post Phase 3.8 soak, May 2026" | Two phases and ~15 sub-deploys stale; the doc is the canonical reference, so the date understates its authority *and* its risk |
| § 1, ~line 26 | "No second tenant exists yet" | `comicstore` live on prod since 5.5 (2026-07-15) |
| § 1, ~line 31 | "GH Pages warm until 5.5 closes" | 5.5 closed; Rick's 2026-07-15 call was to keep it warm and revisit separately |
| § 2, line 97 (Hosting row) | "(GH Pages warm until 5.5)" | same |
| § 3, ~lines 113–115 | "one founding tenant …; no second tenant has been onboarded" | same as § 1 |
| § 1, ~lines 77–79 | "the import script hard-codes `TENANT_ID` to the founding tenant" | `.env`-driven and credential-free since 2026-07-08 |
| § 3.1, ~lines 144–149 | "tenant_id is a top-level constant `TENANT_ID = '72e29f67-...'`" | same |

Severity: **Medium** — documentation drift in the canonical reference. No live defect; the risk is a
future session trusting a snapshot, which is precisely the F81 failure mode. Disposition: **deferred
to a dedicated `technical-reference.md` re-audit session** — it wants a live-DB pass and a refreshed
"last verified" line, not a drive-by edit. Cross-link `[[F81]]` as the precedent.

Per the skill: write the § 13 entry, update `CLAUDE.md`'s open-findings line, and advance the next
free ID to **F92**.

#### S5.8 — Land on staging

```powershell
git checkout staging
git pull origin staging
git merge --ff-only feature/apex-invariant-supersession
git push origin staging
```
Then **re-run `.\run-smoke.ps1` against the deployed staging build** (the S5.3 run was pre-merge).
Record both results separately in the deploy log.

---

### S6 — Prod promotion + 24-hour soak + closeout

**Gate: S5 fully green and merged.** Prefer the `/promote-prod` skill, which encodes this flow.

#### S6.1 — Pre-flight

Run `/preflight`. Confirm `gh` is authenticated and `main` is clean. Re-confirm F86/F88 are closed in
`technical-reference.md` § 13 (they are, as of 2026-07-22 — this is a paranoia check, not an
expectation of change).

#### S6.2 — Build the promotion commit

```powershell
git checkout main
git pull origin main
git merge staging --no-commit --no-ff
git checkout main -- config.js   # preserve prod credentials — config.js is tracked per-branch
```

**F59 merge-base regression assertion.** `index.html` **must** differ — it is the whole deliverable:

```powershell
foreach ($f in @('index.html','app.js','mylist.html','arrivals.html','admin.html')) {
    $d = git diff "main:$f" "staging:$f" 2>$null
    if ($f -eq 'index.html' -and -not $d) {
        Write-Host "ERROR: index.html identical to main — this promotion MUST change it. HALT." -ForegroundColor Red
    } elseif ($d) { Write-Host "ok: $f differs from main (will update)" }
    else { Write-Host "WARN: $f identical to main — verify expected, NOT a merge-base regression" }
}
```
Also confirm the new assets are in the merge: `apex.css`, `assets/hero.jpg`,
`assets/pulllist-logo.png`. **Halt** if any is missing — the page would deploy unstyled.

```powershell
git commit -m "feat(apex): platform marketing page + universal login on the apex front door"
git checkout -b feat/apex-marketing-prod
git push origin feat/apex-marketing-prod
```

#### S6.3 — PR

Open `feat/apex-marketing-prod → main`.

> **PAUSE → Rick.** **Verify `config.js` is NOT in the PR diff**, then merge. CF Pages auto-deploys
> `main` at `https://pulllist.app/`. **Paste:** PR number + merge commit.

**Note:** `config.js` now carries a **publishable** key on `main` (F86, 2026-07-22). The
`git checkout main -- config.js` step above preserves it. If `config.js` appears in the diff, **halt
and do not merge** — that is the exact failure the step exists to prevent.

#### S6.4 — Post-deploy verification (all four required)

1. **Apex branch live:**
   ```powershell
   curl.exe -s https://pulllist.app/ | Select-String 'data-front-door'
   curl.exe -s -o /dev/null -w "%{http_code}" https://pulllist.app/apex.css   # → 200
   ```
   Browser: `https://pulllist.app/` renders marketing + the sticky `Sign in`; no founding-shop
   string; no horizontal scroll at 1440 and 390 px. **Inspect the rendered page, not just the
   assertions** — two prod incidents came from CSS that passed assertions and looked wrong
   (`CLAUDE.md` § Known Issues; the "verify CSS in a real browser" rule).
2. **Tenant branch live — the real regression risk.** `https://comicstore.pulllist.app/` must render
   **exactly today's branded login**, no marketing, no layout shift. This host could not be exercised
   on staging (the 5.5 prod-only asymmetry), so **this is its first live test.** **Halt and roll back
   if marketing leaks onto it.**
3. **Outstanding magic link, end-to-end** (the completion criterion, and the one thing no staging run
   could prove against prod tokens):
   > **PAUSE → Rick.** Trigger a password reset for a founding-tenant test account. The email link
   > lands on `https://pulllist.app/...` (per `APP_BASE_URL`, F67). Confirm: the sign-in panel opens
   > **immediately** — the token never sits behind the marketing page — auth completes, and the
   > browser lands in the app resolved to the founding tenant. **Paste:** the observed landing URL +
   > `TenantContext.source()`.
4. **Write-smoke on the apex as the founding tenant:** reserve one item through the live app →
   confirm the row lands in prod `preorders` with the founding `tenant_id`
   (`scripts/phase-4-prod-tenant-uuid.txt`) → cancel it → confirm the row is gone.

#### S6.5 — 24-hour soak (pinned 2026-07-22, Rick)

**24 hours** from the prod merge. Rationale: presentation-layer change only — no DB, no Edge
Function, no `config.js` — and the apex keeps accepting logins throughout, so the failure mode is
cosmetic or auth-entry, both of which surface immediately. Matches the F86 staging-soak precedent.

**A soak means 24 elapsed clock hours, not "green so far."** Arm the reminder with `/schedule-gate`
the moment the merge lands — do not leave the gate on human memory.

At close: re-check both hosts render correctly; confirm no login-related report from Rick.

#### S6.6 — Closeout

1. Tick every remaining § Completion criteria box with an inline result note (the 5.x pattern).
2. This file: **Status → Complete + date**; add S5/S6 deploy-log rows; update the Last-updated line.
3. `CLAUDE.md`:
   - § Current Migration Phase — record the apex work as closed and **live in production**, in the
     § Known Out-of-Scope "closed sessions" style used for F86 and the analytics work.
   - Open-findings line — add **F91**; next free ID → **F92**.
   - **Phase 6 precursor:** note that Phase 6's public front door now exists — `pulllist.app` is a
     platform marketing page with universal login, so Phase 6's `/signup` has a home. **Phase 6
     remains gated on the wildcard-DNS/TLS spike** — this satisfies a precursor, not the gate.
4. `docs/phase-6-self-service-signup.md`: one line in the stub recording the satisfied precursor and
   pointing at this plan.
5. Confirm **S1, S3, S4 are explicitly recorded as deferred**, not silently dropped (a completion
   criterion).
6. Run `/wrap-up` for the end-of-session status update.

---

## References

- **Approved design for S2 + ready-to-use implementation handoff prompt:**
  `docs/apex-marketing-page-design.md` (design decisions, palette/type, assets, implementation
  gotchas; § 8 holds the handoff prompt). Visual source of truth:
  `docs/mockups/apex-marketing-page-draft.html` (opens offline).
- Tenant resolution + RPC + `tenantSlugFromHostname()`: `docs/phase-5.2-slug-id-routing-rpc.md`;
  `app.js` `TenantContext` (re-read from disk at execution).
- One-manual-custom-domain provisioning pattern (comicstore): `docs/phase-5.5-second-tenant-onboarding.md`
  §§ S2/S3 (add `<slug>.pulllist.app` on the `pulllist.app` Pages project; TLS auto; no wildcard).
- Branding-by-resolved-tenant: `docs/phase-5.3-per-tenant-branding.md` (`Branding.apply()`).
- Email/redirect base URL secret: `docs/phase-5.2-slug-id-routing-rpc.md` § S5 (`APP_BASE_URL`).
- Findings: `docs/technical-reference.md` § 13 — **F72** (email body branding, deferred). No finding
  for the single-`APP_BASE_URL` behavior — it is intentional (see § Auth-redirect base URL). **F91**
  is filed at S5.7 for an unrelated matter: residual `technical-reference.md` drift outside the
  tenant-resolution contract. Next free ID after S5: **F92**.
- Phase 6 (successor front door this precedes): `docs/phase-6-self-service-signup.md`.
- Anti-drift / plan-when-its-turn-comes / document-integrity: `CLAUDE.md`.

---

**Last updated:** 2026-07-22 (**S5/S6 runbook written**; F86/F88 both closed → **S6 unblocked**.
Rick's calls this session: S5 fixes the `technical-reference.md` tenant-resolution contract only and
**files F91** for the residual drift; S5 **adds** a committed apex front-door spec rather than
rewriting any existing one (none needs it — independently re-verified); S6 soak pinned at
**24 hours**; the S2 sign-in copy nit is **bundled into S5**. Corrected the stale "write-smoke on the
founding subdomain" language in the S6 row — **founding stays on the apex**, there is no founding
subdomain. 2026-07-21: **F86 gating revised** — staging build may proceed during the watch;
**prod promotion** gated on F86/F88 closure. Design captured in
`docs/apex-marketing-page-design.md`. 2026-07-20: re-centered on the **marketing page as the
driver**; founding subdomain **deprioritized/deferred** — founding stays on the apex; adopted the
Hybrid tiering model (apex = marketing + universal login = free tier; branded subdomain = premium);
per-tenant redirect downgraded blocking→optional; single-`APP_BASE_URL` confirmed not-a-defect, so
**no finding was filed for it** — that decision stands. *(The 2026-07-20 note originally read "no
F91" because F91 was the next free ID at the time; F91 is now claimed by the unrelated
`technical-reference.md` drift filed at S5.7 — the two are not related.)* Status: In progress —
S2 complete on staging; S5/S6 remaining)
