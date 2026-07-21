# Apex Marketing Page + Universal Login (PLAN)

*(Formerly "Apex Landing + Founding-Tenant Subdomain." Re-centered 2026-07-20: the **marketing page
drives this development**; provisioning the founding tenant's own subdomain is **deprioritized/
deferred** — the founding tenant simply stays on the apex.)*

**Status:** **In progress** (opened 2026-07-21) — **S2 (apex marketing + universal login) executing on
staging.** Standalone sub-deploy; **not** bundled with any other work. Its own session, full
staging→prod discipline.
**F86 gating (revised 2026-07-21, Rick — supersedes the earlier "not during the F86 watch" line):**
the **staging build MAY proceed during the F86 legacy-key watch.** It is staging-side static
frontend (`index.html`/CSS/assets) and shares no surface with the production key toggle — different
environment, different layer; staging keys were already rotated 2026-07-15. **The production
promotion is gated on F86/F88 closure.** Rationale: F88 predicts the F86 toggle will 401 every Edge
Function's auto-injected service-role key (broad function-layer outage). Do not put a freshly
refactored prod login page into that window — one failure, one obvious cause.
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
| S0 | **Readiness gate (no writes)** | Re-read resolver + allowlist from disk; confirm founding slug resolves via RPC on both envs; confirm Cloudflare access to the `pulllist.app` Pages project; confirm `comicstore` custom domain still Active (regression baseline). (No finding to file — the single-`APP_BASE_URL` behavior is intentional; see § Blocking dependency.) |
| S1 | **Per-tenant auth-redirect base URL — optional premium (deferrable)** | Make invite/recovery/magic-link redirect base per-tenant (option (a) or (b)); staging EF deploy → verify; prod EF deploy → verify. Bundle with F72 body-branding. **Not required for the free-tier apex** — defer unless bundling premium email this session. |
| S2 | **Apex marketing + universal login (hostname-aware `index.html`)** | Build the apex marketing page **with a persistent universal sign-in**; branch presentation by host; keep the full auth-token path on both branches. Staging-verify both branches via host stub + `?t=`. |
| S3 | **Optional premium redirect (skippable)** | *(Premium only.)* Apex app-paths → tenant subdomain, token/query preserved (client-side or CF Redirect Rule per verified mechanics). The free tier keeps working at the apex without it. |
| S4 | **(Deferred) Provision `rjbookstop.pulllist.app`** | *Deprioritized 2026-07-20 — founding stays on the apex.* If/when wanted: manual CF custom domain + TLS (5.5 procedure). Not part of the driving marketing-page work. The same manual flow provisions any *premium* tenant's subdomain. |
| S5 | **Supersede the 5.2 invariant + specs** | Update 5.2 doc + `technical-reference.md`; rewrite the founding-invariant / isolation Playwright specs to the new contract; full suite green. |
| S6 | **Prod promotion + soak + closeout** | Standard workflow (F59 diff assertion, `config.js` checkout, post-deploy write-smoke on the founding subdomain); short soak; verify an outstanding-magic-link redirect end-to-end; tick completion criteria. |

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
- [ ] Playwright founding-invariant / tenant-isolation specs updated to the revised contract and
      green; full suite green. — **Green half done (S2, 2026-07-21):** full suite 40/40 green against
      the deployed staging change, including tenant isolation (F15/F20). **No spec needed changing** —
      every spec authenticates via magic link on the apex host and asserts post-login app state, which
      the Hybrid preserves exactly. The "updated to the revised contract" half (asserting the apex now
      shows marketing pre-login) is still **S5** work.
- [ ] Post-deploy write-smoke on the apex as the founding tenant (reserve → correct founding
      `tenant_id` → cancel) clean; short soak clean.
- [ ] F72 disposition updated; no new finding filed for the single-`APP_BASE_URL` behavior
      (confirmed intentional).
- [ ] Deferred items noted: founding subdomain (`rjbookstop.pulllist.app`) and premium enhancements
      (per-tenant redirect URLs, F72 email branding, apex→subdomain redirect) — built only if
      explicitly bundled, else explicitly deferred.
- [ ] This plan's status → Complete; `CLAUDE.md` updated; Phase 6 stub notes the satisfied precursor.

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
- **CTA destination** — `Start free` / `Get started` anchor to a new `#contact` section showing the
  shop phone **973-586-9182**. Self-service signup is Phase 6; a `mailto:` was declined.
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

**Known cosmetic nit, not fixed:** the sign-in card's pre-existing "Don't have an account? Contact
the shop and we'll get you set up." is ambiguous on the apex ("which shop?"). Left as-is — it is
pre-existing copy and out of this step's scope. Worth a copy pass at S5/S6.

**Left for later steps:** S5 (supersede the 5.2 founding-apex invariant in the 5.2 doc +
`technical-reference.md`, grep-sweep, add specs asserting the marketing branch) and S6 (prod
promotion + write-smoke + soak) — **S6 stays blocked on F86/F88.** S1/S3/S4 remain deferred/premium.

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
- Findings: `docs/technical-reference.md` § 13 — **F72** (email body branding, deferred). No new
  finding for the single-`APP_BASE_URL` behavior — it is intentional (see § Blocking dependency).
  Next free ID unchanged: **F91**.
- Phase 6 (successor front door this precedes): `docs/phase-6-self-service-signup.md`.
- Anti-drift / plan-when-its-turn-comes / document-integrity: `CLAUDE.md`.

---

**Last updated:** 2026-07-21 (**F86 gating revised** — staging build may proceed during the watch;
**prod promotion** gated on F86/F88 closure. Design captured in
`docs/apex-marketing-page-design.md`. 2026-07-20: re-centered on the **marketing page as the
driver**; founding subdomain **deprioritized/deferred** — founding stays on the apex; adopted the
Hybrid tiering model (apex = marketing + universal login = free tier; branded subdomain = premium);
per-tenant redirect downgraded blocking→optional; single-`APP_BASE_URL` confirmed not-a-defect, no
F91. Status: Planning — not started)
