# Apex Marketing Page — Design Reference

**Status:** **Design approved (2026-07-20/21). Implemented on staging 2026-07-21** — see
`docs/apex-landing-tenant-subdomains.md` § Deploy log → S2 for what was built, the execution
decisions (sign-in overlay, `Sample dashboard` caption, `#contact` phone CTA, Bebas Neue display
type, tenant-neutral apex copy), the deviations from the mockup, and the verification evidence.
Not promoted to production (F86/F88 gate). The § 8 handoff prompt below is spent.
**Purpose:** Durable capture of the design work done in the mockup sessions, so the visual
direction, decisions, assets, and hard-won implementation gotchas survive to whenever the build
actually happens. **Revisit this file when implementation opens** — the ready-to-use handoff
prompt is in § 8.
**Parent plan (scope/sequencing/completion criteria):** `docs/apex-landing-tenant-subdomains.md`
— this design covers that plan's **S2 (apex marketing + universal login)**.

> This file is a *design reference*, not a runbook. It records what was decided and why. The
> plan doc owns scope and completion criteria; it is the authority if the two ever disagree.

---

## 1. What exists (committed here)

| Artifact | Path / URL | Notes |
|---|---|---|
| Self-contained mockup | `docs/mockups/apex-marketing-page-draft.html` | Opens offline in any browser. Assets embedded as data URIs — **this is the visual source of truth.** |
| Hero source image | `docs/mockups/assets/hero.png` | 1717×916, 1.70 MB. AI-generated, prompted by Rick — **we own it**; no third-party rights issue. |
| Logo source (dark bg) | `docs/mockups/assets/dark-bg-pulllistlogo.png` | 1536×1024 with large transparent margin; genuinely transparent. |
| Live mockup (may expire) | https://claude.ai/code/artifact/041f8bac-2d65-4d4d-84b7-853a5c40cd4f | Convenience only — the committed HTML above is the durable copy. |
| Front-door comparison mockup | https://claude.ai/code/artifact/bc5e646a-975e-4346-8f14-b4be3fcd3fcc | Shows apex vs branded-subdomain side by side (the Hybrid decision aid). |

The originals also sit in the untracked `scratchpad/` folder; the copies above are the tracked ones.

---

## 2. Locked design decisions

- **Single committed dark theme** ("comic-noir"). Tokens are set on `:root` for *all*
  `data-theme` values so a viewer's light/dark toggle can never drop it into an unstyled light
  mode. This is a deliberate one-world design, not an omission.
- **Headline: "YOUR PRE-ORDER SUPERPOWER"** — `SUPERPOWER` in red. Chosen to align with the
  caped-hero hero image. (Earlier "Take the pain out of pre-orders" was retired as off-image,
  but the pain-relief framing survives in the sub-headline and the "monthly grind" idea.)
- **Full-bleed cinematic hero photo**, headline + CTAs + stats card overlaid on the darker left
  under a scrim; figure sits right.
- **The apex KEEPS a universal sign-in** (the Hybrid model — see the plan's § Strategic
  direction). The page is marketing **and** login; it never becomes login-less.
- **No "New Releases" cover carousel.** Removed at Rick's call for copyright reasons. **Do not
  reintroduce** real cover art, real comic titles, or publisher logos.
- **No "trusted by <publisher>" logo wall.** That would imply endorsements we don't have. The
  integration strip instead states something true: *reads the catalogs you already order —
  Lunar · PRH*.
- **Pricing present but understated** — a small two-tier block low on the page, not a hero.
- **Audience: comic *and* book shops** (broad), spoken to as shop owners/operators.

---

## 3. Design system

**Palette** (from the mockup; vermilion is the existing PULLLIST brand accent):

| Token | Value | Role |
|---|---|---|
| `--bg` / `--bg2` | `#0B0908` / `#0F0B0A` | page grounds (warm near-black) |
| `--surface` / `--surface2` | `#16100E` / `#1E1613` | cards, elevated |
| `--line` / `--line2` | `#2A201C` / `#3B2C26` | hairlines |
| `--ink` / `--slate` / `--muted` | `#F6EFEA` / `#B7A79D` / `#7C6C62` | text ramp |
| `--red` / `--red-br` / `--red-deep` | `#E8321C` / `#FF3A29` / `#A81C0D` | accent, bright, pressed |

**Type:** heavy system-sans for display (uppercase, weight 900, tight tracking) + a mono utility
face for eyebrows, labels, stats, and URL chrome. **The mockup has no webfont** — artifacts block
font CDNs. The reference visual (a heavy *condensed* grotesque) needs a real embedded face;
**production is not CSP-restricted, so a licensed condensed display font can and should be
embedded** for a closer match.

**Layout:** sticky translucent header (logo · pill nav · Login/Get started) → full-bleed hero →
integration strip → six-tile feature grid → 01/02/03 how-it-works → two-tier pricing → closing
CTA → footer.

---

## 4. Page sections and copy status

| Section | Status |
|---|---|
| Header (logo, pill nav, Login, Get started) | Final layout; nav links are placeholders |
| Hero (badge, headline, sub, 2 CTAs, microtrust, glass stats card) | **Copy final**; stats numbers illustrative |
| Integration strip (Lunar · PRH) | Final, factually accurate |
| Features (6 tiles) | Final |
| How it works (01/02/03) | Final |
| Pricing (Free / Branded) | Structure final; **price is a placeholder** |
| Closing CTA + footer | Final |

**Placeholders to resolve before build:** the Branded-tier price (`$—`); the hero stats-card
numbers (illustrative, not claims); nav/FAQ/Contact destinations; "Explore all features" target.

---

## 5. Implementation gotchas (hard-won — read before building)

1. **One Cloudflare Pages project serves EVERY hostname.** All hosts get byte-identical files.
   The apex-vs-subdomain difference must be driven **client-side** from
   `window.location.hostname`. Any "put a different file at the apex" approach is wrong.
2. **The mockup embeds images as base64 data URIs only because artifacts block external images.**
   Production has no such restriction — reference real files (`<img src="…">` /
   `background-image: url(…)`), do **not** carry the data URIs over.
3. **Compress the hero for the web.** The 1.70 MB PNG was resized to a 1600 px-wide JPEG at
   quality 82 → **132 KB** with no visible loss. Do the equivalent in production.
4. **Hero mobile crop.** `object-fit: cover` + `object-position` keeps the figure in frame:
   `62%` desktop, `80%` ≤900 px, `85%` ≤620 px, with a stronger scrim on mobile for headline
   legibility. These three numbers are the only tuning knobs.
5. **Logo:** the first `logo.png` had a *baked black background* (bad on the translucent header);
   `dark-bg-pulllistlogo.png` is properly transparent — **use that one**. It ships on a large
   canvas with wide transparent margins, so **trim to the artwork** before use or it renders tiny
   in its box. Mockup sizes after trim: header `141×56`, footer `106×42` (aspect ≈ 2.515).
6. **CSS `var()` does NOT resolve inside SVG presentation attributes** (`stroke="var(--x)"`
   silently fails). Use literal hex in inline SVG. This cost a debug cycle.
7. **Auth is load-bearing on this page.** `index.html` today handles invite / recovery /
   magic-link tokens (`token_hash`, `access_token`, `verifyOtp`, `setSession`). The token handler
   must run **first**, on both host branches. Count the auth callsites *before* refactoring and
   assert the same count after.
8. **Verify CSS in a real browser at mobile widths** — never "folded into a manual pass." Two
   production incidents came from skipping this (analytics banner 2026-07-17, subscriptions
   mobile clip 2026-07-19).

---

## 6. Assets → production

| Source | Production treatment |
|---|---|
| `docs/mockups/assets/hero.png` | resize to ~1600 px wide, JPEG q≈82 (~130 KB), serve from the web root |
| `docs/mockups/assets/dark-bg-pulllistlogo.png` | trim transparent margin, export at ~2× display size, keep PNG for transparency |

Final production paths are an implementation decision — not pre-empted here.

---

## 7. References

- Scope, sequencing, risks, completion criteria: `docs/apex-landing-tenant-subdomains.md`
- Host model + non-tenant allowlist + RPC contract: `docs/phase-5.2-slug-id-routing-rpc.md` §1.3, §1.5
- Per-tenant branding render: `docs/phase-5.3-per-tenant-branding.md`
- Design skill available for the build: `frontend-design@claude-code-plugins`
  (installed user-scope 2026-07-21; invoke as `/frontend-design:frontend-design`)

---

## 8. Handoff prompt — use when implementation opens

Copy the block below into a fresh session. It assumes nothing from this session's context.

```
SESSION: Build the apex marketing page + universal login (step S2) for PULLLIST, from the
committed plan and the committed design reference. Staging only.

FIRST ACTION: invoke /frontend-design:frontend-design before writing any markup or CSS.

REQUIRED READING (in order, from disk — never from memory of prior sessions):
1. CLAUDE.md (in full)
2. docs/apex-landing-tenant-subdomains.md          <- scope, sequencing, completion criteria
3. docs/apex-marketing-page-design.md              <- approved design + implementation gotchas
4. docs/mockups/apex-marketing-page-draft.html     <- open in a browser; visual source of truth
5. docs/phase-5.2-slug-id-routing-rpc.md  §1.3 (host model + allowlist), §1.5 (RPC contract)
6. app.js — the TenantContext block (resolve(), tenantSlugFromHostname(), NON_TENANT_HOSTS)
7. index.html — the current sign-in + invite/recovery/magic-link token flow
8. style.css

SCOPE — IN:
- Apex marketing page + a PERSISTENT universal sign-in, via a hostname-aware index.html
  presentation branch (plan § Approach decisions #2).
- Auth-token handling must run FIRST and stay intact on BOTH host branches. The apex KEEPS
  login; it does not become login-less.
- Bring the hero + logo into the repo as real files (NOT data URIs) per design ref § 6.

SCOPE — OUT (stop and ask before touching):
- Founding subdomain rjbookstop.pulllist.app (deferred; founding stays on the apex)
- Per-tenant auth-redirect URLs, F72 email branding, apex->subdomain redirect (premium, deferred)
- Any production promotion, config.js, import scripts, DB/DDL, Edge Functions
- F86 legacy-key work
- Anything not on the IN list.

GATED STEPS (a failed verification is halt-and-report, never improvise):
G0  /preflight. Confirm branch=staging, clean tree, HEAD==origin/staging. Halt on mismatch.
G1  Invoke /frontend-design:frontend-design. No markup/CSS before this.
G2  Re-read index.html + app.js TenantContext from disk. COUNT the auth callsites
    (token_hash|access_token|verifyOtp|setSession) BEFORE editing. Halt if the structure
    differs from the design ref's description.
G3  Add hero + logo to the repo (compressed per design ref § 6). Verify every referenced
    path resolves; no scratchpad/ or data: URI references remain.
G4  Implement the hostname-aware index.html:
      apex / www / *.pages.dev / localhost -> marketing + universal sign-in
      <slug>.pulllist.app                  -> branded login (today's behavior, unchanged)
    Verify the auth-callsite count from G2 is unchanged.
G5  REAL-BROWSER verification (mandatory, never "folded into a manual pass"): desktop AND
    mobile widths. Confirm (a) marketing renders, (b) sign-in works, (c) no horizontal page
    overflow, (d) hero crop keeps the figure in frame on mobile.
G6  cd <scripts>\playwright ; .\run-smoke.ps1 -> full suite green INCLUDING tenant-isolation
    (F15/F20). Stop on any failure; do not push.
G7  Commit on feature/apex-marketing-page -> git merge --ff-only to staging -> push origin
    staging. DO NOT promote to production.

ENVIRONMENT FACTS:
- Branch staging; feature branch feature/apex-marketing-page off staging.
- Staging only (https://staging.pulllist.pages.dev/). No prod, no PR to main.
- The staging build MAY run during the F86 legacy-key watch (different environment/layer).
  The PRODUCTION PROMOTION is gated on F86/F88 closure — see the plan's § Status. If F86/F88
  are still open, stop after G7 and report; do not promote.
- PowerShell primary; no && chaining; Select-String not grep; quote paths containing parentheses.
- Vanilla HTML/CSS/JS, no build step, no npm for the web app.
- LOAD-BEARING: Cloudflare Pages serves EVERY hostname from ONE project; the apex-vs-subdomain
  split is CLIENT-SIDE ONLY via window.location.hostname.
- No DB steps. If a DB change seems needed, stop and ask.
- The agent never edits config.js.

COMPLETION CRITERIA: use the plan's § Completion criteria verbatim
(docs/apex-landing-tenant-subdomains.md). THIS session covers criteria 1, 2 and the
Playwright-green half of 4. Criteria 3, 5, 7, 8 belong to later steps (S5/S6) — leave unchecked.

ON OPENING: set the plan's Status from "Planning — not started" to "In progress".
ON CLOSING: run /wrap-up and produce the standard status update.
```

---

**Last updated:** 2026-07-21 (design approved and captured; mockup + assets committed;
implementation not started — see § 8 to begin)
