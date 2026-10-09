# Catalog redesign: hero, search + filter toggle, Top picks rail

**STATUS:** COMPLETE ON STAGING, NOT PROMOTED | staging=2026-10-09 (commits `95022b2`, `1f6fae1`, `9b59773`, `fcf9500`, then Rick's round two `3781c4b`: DESKTOP ONLY, blended picks, deadline message over the banner; then round three `f15ba8b` + `aab315d`: the rail collapses while a search or filter is active, and a collapsed rail leaves only "Show top picks"; then `504c07d`: unpinning resets the Filters badge; then `3d77722`: the rail remembers a hand open/close per situation (round four, § 12); full record in § 9 to § 12) | prod=NOT PROMOTED (a separate, explicitly requested `/promote-prod`; see § 9.6 for what to assert) | findings=none consumed (feature build; the pre-existing defect in § 6 was fixed without an ID, Rick 2026-10-09; **F172 remains the next free finding ID**)

**Last verified against live: 2026-10-09** (read from `origin/staging`; `catalog.html`, `style.css` and `app.js` are byte-identical on `origin/main` and `origin/staging`, so nothing unpromoted sits under this work).

**Source design:** `scratchpad/design_handoff_catalog_top_picks/README.md` + `Catalog.dc.html` (local only, untracked; a design reference, never shipped). The README names the repo `comic-preorder-staging`; that repo has not been a deploy target since 5.1. **Work goes on the `staging` branch of `origin`.**

---

## 1. What the design asks for, against what already exists

Much of the design is already built in some form. The plan changes what exists rather than adding a parallel copy.

| Design item | Already in the app | Plan |
|---|---|---|
| Hero banner with art on the right | `.page-header--banner` + `PageBanner` (`app.js:1484`), shared by catalog, My List, Subscriptions, This Week and the Settings preview; art is tenant-wide, set in Settings > Branding | Catalog-only modifier `.page-header--hero` (§ 3.1). Art stays `PageBanner`, not per-month (D3) |
| Deadline notice inside the hero | `#deadline-banner`, a separate row below the header, filled async by `Settings.getOrderDeadline()` | Move the node into the hero; same text, same tooltip (§ 3.1) |
| Large search + filter toggle | `#search` + `#btn-filter-toggle` (shown only <=640px, beside the results count) | One toggle beside search at every width (§ 3.2) |
| Collapsible filter panel | `#filter-panel`, always open on desktop, `.open` class on mobile | Collapsed by default at every width (D1) |
| Count line | `#results-count` + `visibilityNote()` already prints "· filtered by store settings" | Restyle only |
| Top picks rail | Nothing. `Recommendations.getCatalogIds()` ranks the month (personal series, then popular) for the "Recommended For You" filter | New section above the grid, fed by an extended `Recommendations` (§ 3.3) |
| Nav centred, Admin chevron | Admin ▾ is already a dropdown (S2b, PR #164) with its own chevron | Centre the links only; **no horizontal scroll** (D4) |
| Catalog grid | `.catalog-grid` / `.comic-card` | Unchanged (gap stays 8px; the mock's 14px is not a requested change) |

## 2. Decisions (Rick answered D1, D2, D5, D6 and D10 on 2026-10-09; D3, D4, D7, D8 and D9 are the planning defaults, not overridden)

**Rick, 2026-10-09: "D1= Yes, D2= use existing hero(s), D5= ISBN, D6= drop 'You subscribe', 'Next in series' and 'Trending'. 'Staff pick' and the other three, D10= Yes".** How each answer is read, and where it changed the plan:

- **D1 yes:** as written below.
- **D2 "use existing hero(s)": NO hero work.** The catalog keeps the shared `.page-header--banner` card and `#deadline-banner` exactly as they are on all four pages. § 3.1 is withdrawn; D3 and the hero half of D9 no longer apply. The four-page match (PR #166) is preserved.
- **D5 ISBN:** as written below.
- **D6 read as "no reason chips at all":** all seven reasons are dropped (the three the data supports and the four it does not). The rail is ranked by `Recommendations` but its cards carry no chip. *If Rick meant something else, this is the one reading to re-confirm; the change is confined to `opts.reason` in § 3.3.*
- **D10 yes:** the § 6 fix lands in the execution session as its own commit. Whether § 6 also takes a finding ID (F172) is still asked at the start of that session.

The original decision text follows, kept for the record; D2, D3, D6 and the hero half of D9 are superseded by the answers above.

- **D1 Filter panel collapsed by default on desktop too**, as designed. The toggle keeps its active-filter count badge (the mock has none, but pinned filters would otherwise be invisible and silent). Open/closed state persists per user in `localStorage` (`pulllist_filters_open_<userId>`), wrapped in try/catch.
- **D2 The hero is catalog-only.** My List, Subscriptions and This Week keep the current header card. This knowingly breaks the four-page visual match PR #166 created; restyling all four is a separate decision. The title keeps its red offset shadow (Rick's 2026-10-02 choice); the mock does not show it, and dropping it would be an unrequested reversal.
- **D3 Hero art comes from `PageBanner` as today** (tenant-wide default `assets/banner-v3.webp`, paid-tier custom image). "Configurable per month" needs a new settings shape and is out of scope.
- **D4 Nav: centre the links (`margin: 0 auto` at >=641px) and nothing else.** The mock's `overflow-x: auto` on `.nav-links` would clip the Admin ▾ panel, which is absolutely positioned inside `.nav-links` (an `overflow-x` other than `visible` forces `overflow-y` to `auto`). The 641-760px overflow stays the separate, unfiled item it already is.
- **D5 Placeholder keeps "ISBN"**: `Search titles, series, writers, UPC, ISBN, item code…`. The README flags "ISBI" as unconfirmed, and the search does query the `isbn` column.
- **D6 Rail reasons, v1, only what existing data supports:** "You subscribe" (series in `mySubscriptions`), "Next in series" (series in the user's reservation history or live preorders), "Trending" (popular tier from `get_popular_series`). "Staff pick", "New issue", "Like your list" and "Preorder" need a backend source that does not exist; they are out.
- **D7 No Reserve button in the rail** (Rick's stated preference). A card click opens the existing modal, which reserves.
- **D8 "See more ›"** sets `#filter-reserved` to `recommended`, runs the existing change path (`maybeResavePin(); syncFilterBadge(); loadCatalog(1)`) and scrolls to the grid.
- **D9 Phone (<=640px):** the design is desktop-only. The rail shows as a swipe row (cards 140px), arrows hidden; the hero stacks the deadline notice under the title; the header otherwise behaves as today.
- **D10 Fix the § 6 defect in the same session as its own commit**, because the rail needs the same fields. If Rick says file-only, the rail still widens its own select and the Recommended view is left as is.

## 3. Build

### 3.1 Hero (`catalog.html`, `style.css`) — WITHDRAWN (D2, Rick 2026-10-09: use the existing hero)

**Do not build this section.** No change to `.page-header--banner`, `#page-banner`, `#catalog-subtitle` or `#deadline-banner`. The text below is the withdrawn design, kept so a later session does not re-derive it.

- Markup: keep `.page-header page-header--banner` (the blocked-account banner is inserted `afterend` of `.page-header`, `catalog.html:348`) and add `page-header--hero`. Keep `#page-banner`, `#catalog-subtitle` and the preload link. Move `#deadline-banner` inside the header, after the title block, and give it class `hero-deadline` in place of `deadline-banner`. Leave the JS that fills it (`catalog.html:676-701`) alone apart from what the move needs.
- `.page-header--hero` (scoped, never the shared class): `--bg-card` background, 1px `--border`, radius 10px, min-height 140px, flex row, `align-items: center`, gap 32px, margin-bottom 20px, padding 0. Title block padding 26px 28px; h1 48px Bebas, .04em, margin-bottom 12px; subtitle 14px `--text-secondary`.
- Art: `--banner-w: 46%` for this modifier; the fade overlay (right 30%, width 24%, `linear-gradient(to right, var(--bg-card), transparent)`) becomes this modifier's `.brand-banner::before`. Print rules already hide `.brand-banner` and flatten the card.
- Deadline notice: rgba(30,14,12,0.88) background, 1px rgba(232,50,28,0.4), radius 7px, padding 12px 16px, max-width 520px, 13px, flex `align-items: baseline; flex-wrap: wrap; gap: 8px`. The "What's this?" span keeps `.foc-label .foc-label--below` (tooltip behaviour unchanged), styled 11px/600, dotted underline, `nowrap`.
- **CLS:** the notice arrives after an await. It must not change the hero's height at any width. At >=901px it sits beside the title and fits in 140px. At 641-900px and <=640px reserve its line (stack it under the title with a `min-height` slot that exists from first paint, empty until filled) or accept that the old banner shifted the grid too and measure. Gate V5 decides.

### 3.2 Search row, toggle, panel (`catalog.html`, `style.css`)

- `.toolbar-header`: input wrapper flex 1, plus `#btn-filter-toggle` moved here (50x50, radius 10px, sliders icon 20px, `aria-expanded`, `aria-controls="filter-panel"`, `aria-label="Filters"`). Keep `#filter-active-count` inside the button as a small corner badge. Hover border `--border-accent`, open border `--accent`. Move its inline styles to `style.css`.
- Input: keep `id="search"` and class `search-input` (the tab bar magnifier and specs use them). Scoped rule on the catalog (e.g. `.toolbar-header .search-input`): `--bg-elevated`, radius 10px, padding 15px 52px 15px 24px, 16px, focus border `--border-accent`. Search icon on the right, 20px inset, 17px. 16px also stops iOS zooming on focus.
- `#results-count` stays in `.results-toolbar` below (12px, `--text-muted`, margin 0 0 18px 4px); the toolbar no longer holds the button.
- `#filter-panel`: delete the two `@media` rules at `catalog.html:57-84` that force it open on desktop and hide the toggle; one rule set for all widths: hidden unless `.open`; open = `--bg` background, 1px `--border`, radius 10px, padding 14px, margin -6px 0 22px, flex wrap gap 10px. Min-widths 240/200/150 on publisher/items/covers at >=641px; the existing full-width column layout at <=640px stays.
- JS: the existing toggle handler stays; add restore-from-`localStorage` on load and save on toggle. `syncFilterBadge()` is unchanged.
- **Every filter control stays in the panel** (distributor, publisher, items, covers, admin "Manage customer…", Pin). For an admin this hides the customer selector behind the toggle; that is what the design says.

### 3.3 Top picks rail

**Data (`app.js`, `Recommendations`):**
- Widen `getCatalogIds()`'s light select to `id, series_name, distributor, variant_type, publisher, foc_date, order_requirement, price_usd` and return them on each item, plus `tier: 'personal' | 'popular'`. Additive: the Recommended path keeps working and gains correct visibility filtering (§ 6).
- Memoise per `(userId, month)` for the page's lifetime so the rail and the Recommended filter do not fetch twice.
- New `Recommendations.getTopPicks(userId, month, { reservedIds, cfg, limit = 20 })` returning an ordered `id[]` (no reason, D6): rank from `getCatalogIds()`; drop reserved ids, FOC-past rows (`isFocLocked`), non-standard covers (`isStandardCover`, the existing helpers), and rows `CatalogFilters.apply` hides; **one item per series** (first in rank).
- Caller fetches full rows for the picked ids with one `.in('id', ids)` and restores order (the same two-step as the Recommended path).

**Render (`app.js` + `catalog.html`):**
- `buildComicCard(comic, qty, focLocked, opts = {})` gains an optional `opts`: `{ rootClass, hideActions }` (no `reason`: D6 dropped the chips). Default call sites are byte-for-byte unchanged in output. **The rail card's root class is `pick-card`, NOT `comic-card`** (the same reason `renderSkeletons()` avoids it: specs use `.comic-card` as "the grid has loaded" and locate cards by it; a second `.comic-card` per title breaks `.first()` and strict locators). `.pick-card` joins the `.comic-card` box rule and hover rule in `style.css`.
- ~~Reason chip~~ **Not built (D6, Rick 2026-10-09).** The card's existing badges (distributor, Restricted) stay.
- Markup in `catalog.html`, between `#filter-panel` and `#catalog-grid`: `<section class="top-picks" id="top-picks">` with header (h2 "Top picks for you" 26px Bebas, caption "Based on your reservations and subscriptions" 13px muted, "See more ›" 14px/600 accent, `margin-left: auto`), a relative wrapper, the track `#top-picks-track`, the right-edge fade, and two arrow buttons (`aria-label` "Previous"/"Next").
- Track CSS per the README (flex, gap 14px, `overflow-x: auto`, `scroll-snap-type: x proximity`, padding 4px 0 6px, scrollbar hidden both ways); cards `flex: 0 0 178px; scroll-snap-align: start`; arrows 36px circles at top 42%, left/right -14px, hover accent. <=640px: cards 140px, arrows `display: none`.
- Paging and arrow visibility: port `page()` / `sync()` from `Catalog.dc.html` verbatim in logic (pitch = card width + 14; steps = max(1, floor(clientWidth*0.85/pitch)); snap, clamp, smooth `scrollTo`; 700ms target accumulation; clear on `wheel`/`pointerdown`/`touchstart`; atStart <= 8, atEnd >= max - 12). Read the pitch from the first card's measured width so the phone size works. Run `sync()` on scroll and once after render.
- Clicks: a delegated listener on the track opens `openModal(id)`. `openModal()` and `toggleReserve()` look up `allItems` (the current grid page) only, so keep a `pickItems` Map and fall back to it in both lookups. After a reserve, remove that card from the rail (it no longer qualifies) and re-run `sync()`; `syncCardState()` stays grid-scoped.
- Images: same `loaded` fade as `attachGridEvents()`; `loading="lazy"` stays.

**Loading order and CLS (the main risk; F141 Pattern B is exactly "a section revealed above content"):**
- The section is in the HTML from first paint, with its height reserved by 8 placeholder cards (reuse the skeleton look at 178px wide). Never `display: none` -> shown.
- Start the picks fetch **after** the first `loadCatalog()` has resolved, so the grid's own requests are not delayed (`getCatalogIds()` pages the whole month, about 3 requests for 2,215 rows, plus the user signal, which is paginated and runs to 1,345+ rows on the heaviest account).
- If picks come back empty: remove the section. That shift is accepted as rare (a tenant with no reservation history at all, e.g. `demoshop`); state it in the result.
- While impersonating, show the impersonated customer's picks (`AdminContext.resolveUserId(user.id)`), matching the Recommended filter; reload it on admin customer switch.
- Blocked (pending/paused) users: show the rail; the modal already blocks reserving.
- Hidden in print.

### 3.4 Nav (`style.css` only) — NOT BUILT: measured to be a no-op (Rick, 2026-10-09: "Skip (d)")

**Execution-session finding, and the reason nothing was built.** The rule below changes nothing. `.nav-inner` is already `justify-content: space-between` with three flex children, and for three items that places the links exactly midway between the logo and the user block, which is what `margin: 0 auto` does too. Measured on the live bytes (authenticated, `/catalog`): the gap from the logo to the links and from the links to the user block were **equal at every width tested: 274.8 / 184.8 / 84.8 / 24.0 px at 1350 / 1100 / 900 / 700 px**. What looks off is different: the user block ("Welcome, name" plus Sign Out) is wider than the logo, so the links' centre sits **65.1 px left of the page's true centre** at 900 to 1350 px (25.9 px at 700). The design's own mock (`justify-content: space-between` plus `margin: 0 auto`) has the same offset. Centring on the page instead would be a visible change the design did not ask for, would need a narrow-width guard so it cannot worsen the unfiled 641-760px overflow, and would put one more risk on the seven-page nav; Rick chose to skip rather than ship it or dead CSS. No nav CSS changed, so the seven-page hash check is unchanged by construction (V2 still run: all seven pages read nav `6888702FB15A`, footer `94D490107E55`). The original text follows, kept for the record.

`@media (min-width: 641px) { .nav-links { margin: 0 auto; } }`. No markup change, so the seven-page nav hash check must still read identical. Verify the Admin ▾ panel still opens unclipped at 641, 900 and 1280px.

## 4. Conflicts and warnings (pending work and recorded decisions)

1. ~~**Shared header card (PR #166).**~~ **Resolved by D2 (2026-10-09): the existing header is kept, so the four pages still match.**
2. **Admin ▾ dropdown vs the mock's nav scroll** (D4). Applying `overflow-x: auto` to `.nav-links` would make the shipped S2b dropdown unreachable.
3. **The nav is a seven-page contract.** CSS-only here, but it lands on all seven pages; run the nav/footer hash check.
4. **CLS history.** Catalog desktop CLS is 0.02 after F141 (was 0.636). With the deadline move withdrawn (D2), the rail above the grid is the one way this work can regress it. Gate V5.
5. **Playwright specs (local, gitignored) break on D1.** `selectOption('#filter-variants', …)` and `#filter-publisher` reads in specs 10, 20 and 24 (about 8 call sites) need the panel open first; Playwright waits for visibility and will time out. Add a small `openFilters(page)` helper and update those specs. Sweep with `grep -rn` via Bash (the Grep tool skips the gitignored folder).
6. **`app.js` carries `merge=ours`.** Any `/promote-prod` of this work must assert the merge RESULT for `app.js` (the driver has dropped it three times). **G-K (the F171 fix, next in the pre-Phase-6 plan) also edits `app.js`** (`TenantContext`, a different region). Land one, promote it, then the other, or promote together; either way, assert `app.js` against staging's copy.
7. **Unfiled overlapping-load race in `loadCatalog()`** (no out-of-order guard; found in spec 24's V10 work). "See more" is one more trigger. Not fixed here; do not let it be mistaken for a rail defect.
8. **Performance.** The rail adds the Recommended ranking (catalog month + user signal) to every catalog load. Deferred until after the grid, but measure Lighthouse before/after on staging (`lighthouse-auth.mjs`, `MSYS_NO_PATHCONV=1`), desktop and mobile; F161's lesson is to name the account measured.
9. **No pending promotion conflicts**: the three files are identical on `main` and `staging` today. Phase 6 is not active and no sub-deploy is open.

## 5. Verification gates

- **V1** `node --check app.js`; every inline `<script>` in `catalog.html` extracted and `node --check`ed.
- **V2** Nav and footer hashes identical across the seven pages (CLAUDE.md § Files That Must Stay in Sync).
- **V3** Local harness `playwright/catalog-top-picks-verify.mjs` (local-only, password-grant session as in `f149-maintenance-verify.mjs`), against the DEPLOYED staging bytes, confirmed served on the plain URL first: the header and `#deadline-banner` are unchanged (same classes, same position before `#promo-banner`); toggle closed by default, opens the panel, `aria-expanded` flips, state survives a reload; filter badge counts; rail renders N `.pick-card`, no `.pick-card` carries `.comic-card`, no `.pick-card` has a reason chip or a `.btn-reserve`, no reserved id appears, one card per series; arrows: Prev hidden at start, Next hidden at end, three rapid Next clicks land on a snapped multiple of the pitch; card click opens the modal for that id; reserving from it removes the card; "See more" selects `recommended`; Admin ▾ opens unclipped at 641/900/1280; at 390px the rail swipes and arrows are hidden. Each new assertion observed red once (negative control) before trusting green.
- **V4** Full Playwright suite once, after the push, against the deployed bytes, with specs 10/20/24 updated for D1. Read the log's own `N passed` line.
- **V5** CLS, catalog, desktop and mobile, with and without a deadline set: no worse than 0.05 (today 0.02 desktop / 0.008 mobile). Lighthouse Performance not lower than today's baseline by more than 2 points; record both.
- **V6** Inspected screenshots at 1350, 900, 700, 393 and 320px; print preview shows no rail, no art.
- **V7** (D10 = yes): on staging, save a `catalog_filters` config that hides one publisher, choose "Recommended For You", and confirm no title from that publisher appears (red on the current bytes, green after). Restore the config's original value afterwards (the suite's teardown refuses if `updated_at` moved; restore by hand and re-read).

## 6. Pre-existing defect found while planning (proposed F172, not filed)

**Disposition (Rick, 2026-10-09, asked at the start of the execution session): "Fix without an ID".** Not filed; **F172 stays the next free finding ID.** The fix still lands as its own commit (a), the `Recommendations` select widening; V7 is still run as the red-then-green reproduction, and its result is recorded here. *(The heading above still reads "proposed F172, not filed" because that was true when written and is still true; only the question of whether to file is now answered.)*

`Recommendations.getCatalogIds()` selects `id, series_name, distributor, variant_type` and returns only `{ id, variant_type }`. The Recommended path then runs `applyVisibility(rankedItems)`, and `CatalogFilters.hides()` reads `publisher`, `foc_date`, `order_requirement` and `price_usd`, none of which those rows carry. So **with "Recommended For You" selected, hidden publishers, past-FOC titles, restricted-ratio rules and zero-price hiding are not applied** (cover class is only partly judged, from `variant_type` alone). Inferred from the code, not reproduced live; V7 is the reproduction. Severity likely Low-Medium (a customer-chosen view, tenant settings silently ignored). Filing is Rick's call (`/file-finding`); the fix is the select widening in § 3.3.

## 7. Out of scope

Per-month hero art; staff picks or any new recommendation backend; the other three pages' headers; the 641-760px nav overflow; the `loadCatalog()` race; any schema, RLS or Edge Function change; production promotion (a separate, explicitly requested `/promote-prod`).

## 8. Completion criteria

- [x] D1-D10 confirmed or overridden by Rick before execution (2026-10-09, § 2; D6's reading to be re-confirmed if in doubt)
- [x] Search row, panel and rail built (no hero, D2) on feature branches, merged `--ff-only` to `staging`, pushed. **Nav (§ 3.4) NOT built: measured to be a no-op, Rick chose "Skip".**
- [x] V1-V6 green (V7 too, D10 stood), each with its evidence recorded in this doc (§ 9.5). **V5 failed once, was diagnosed and fixed (§ 9.3), then met.**
- [x] Specs 10, 20, 24 updated for D1 and passing; full suite green post-push (161 passed on the first build and again on the final bytes, § 9.7)
- [x] § 6 filed or explicitly declined by Rick (2026-10-09: "Fix without an ID"; see § 6 Disposition)
- [x] This doc's STATUS token and CLAUDE.md updated (finding-ID disposition: none consumed; F172 remains the next free ID)

## 9. Execution record (2026-10-09, STAGING ONLY)

### 9.1 What shipped to staging, and what did not

| Commit | What |
|---|---|
| `95022b2` (a) | **§ 6 fix.** `Recommendations.getCatalogIds()` selects and returns `publisher, foc_date, order_requirement, price_usd` too, so `CatalogFilters.hides()` finally has the fields it reads. Own commit, as D10 required. |
| `1f6fae1` (b) | Search row with the Filters toggle beside it at every width, collapsed panel (D1) remembered per user in `localStorage`, ISBN placeholder (D5). |
| `9b59773` (c) | The Top picks rail: `getTopPicks`, memoised ranking, `buildComicCard(…, opts)`, markup, paging, modal and "See more" wiring. |
| `fcf9500` (e) | **CLS fix found by gate V5** (§ 9.3). |
| (d) nav | **Not built.** The rule was measured to be a no-op (§ 3.4); Rick: "Skip". |

Files: `app.js`, `catalog.html`, `style.css` (+ this doc). No SQL, no `config.js`, no Edge Function, no `assets/`, no other page. The header card, `#page-banner`, `#catalog-subtitle` and `#deadline-banner` are untouched: the diff contains no line mentioning them, and V3 H1/H2 assert it.

Two questions were put to Rick this session and answered: § 6 "**Fix without an ID**" (F172 stays free) and § 3.4 "**Skip (d)**".

### 9.2 Baseline (step 1), measured before any edit

Lighthouse via `lighthouse-auth.mjs --path=/catalog`, authenticated, against the staging bytes that were deployed before this work. **Account: a brand-new throwaway "Lighthouse Probe" customer on the founding tenant, no reservations, no subscriptions** (a fresh account is the shape of the 0.02 catalog reading in § 5; it is NOT Rick's heavy account). A first attempt failed for a tooling reason (a Git-Bash `/c/...` output path handed to a Windows Node process) and wrote nothing; it is not a result.

| Run | Mobile score | LCP | TBT | CLS | Desktop score | CLS |
|---|---|---|---|---|---|---|
| 1 | 90 | 3.1 s | 210 ms | 0.018 | 100 | 0.025 |
| 2 | 93 | 3.1 s | 30 ms | 0.018 | 100 | 0.025 |

The mobile score has a 3-point noise band on this probe that comes from TBT alone (CLS and LCP were identical across the runs).

### 9.3 V5 FAILED the first time, and the cause was the rail's own placement

The first deployed build scored **CLS 0.064 desktop / 0.117 mobile** (stable across four runs; mobile score 76 to 95 because of TBT noise on top), against the 0.05 gate. The Lighthouse report named the element: **`section#top-picks` moving twice**. A layout-shift probe (harness group `cls`) named the cause and the pixels: `#top-picks` moved **+70 px and +71 px** on desktop and **+23 / +87 / +107 px** on a phone, i.e. the **order deadline banner** (revealed after `Settings.getOrderDeadline()`) and then the **subscription promo banner** (revealed after the subscriptions load), both above the rail.

This is F141 Pattern B again, from the other side. Section 3.3 forbade `display: none` to shown for the rail itself but did not account for what sits above it. Before the rail existed nothing visible sat below those banners: the grid was an empty, unpainted `div` until its skeletons rendered, after both banners had landed, so their arrival shifted nothing that was scored. **The plan's "in the HTML from first paint with placeholders" is therefore superseded:** the section keeps its space from first paint but is `visibility: hidden` (`data-pending`) until the deadline read has settled (bounded at 3 s) and the promo banner has rendered, and is revealed just before the first `loadCatalog()`, the same moment the grid's own skeletons appear. `visibility` keeps layout and an unpainted element's movement is not a shift. Result: `#top-picks` no longer appears in any shift; only `.search-block` moves, as it did before this work.

### 9.4 V5, after the fix (deployed bytes, same probe, same account shape)

| Run | Mobile score | LCP | TBT | CLS | Desktop score | CLS |
|---|---|---|---|---|---|---|
| deadline set, 1 | 97 | 2.4 s | 90 ms | 0.022 | 100 | 0.018 |
| deadline set, 2 | 97 | 2.4 s | 30 ms | 0.022 | 99 | 0.018 |
| deadline set, 3 | 97 | 2.5 s | 20 ms | 0.022 | 100 | 0.018 |
| **no deadline** (cleared, then restored) | 98 | 2.4 s | 10 ms | 0.010 | 100 | 0.011 |
| 30 reservations seeded, deadline set | 98 | 2.2 s | 20 ms | 0.022 | 100 | 0.018 |

Gate: CLS at most 0.05 on both form factors, with and without a deadline: **met** (worst 0.022). Performance not more than 2 points below baseline: **met** (mobile 97 to 98 against 90 to 93; desktop 99 to 100 against 100). **Mobile CLS is 0.004 above its baseline (0.022 against 0.018) while desktop is 0.007 below (0.018 against 0.025)**; both far inside the gate. `order_deadline` was cleared for the no-deadline run and put back, then re-read: **value and `updated_at` identical** (`2026-10-23`, `2026-10-02T10:46:57.456+00:00`). (A first V5 runner's clear step failed on a path error and changed nothing, which I verified by re-reading the row before trusting any "no deadline" figure; that run was a duplicate of the with-deadline runs and is discarded.)

### 9.5 Gates

| Gate | Result | Evidence |
|---|---|---|
| **V1** syntax | green | `node --check app.js` and the one inline `<script>` of `catalog.html`, on the merged tree, twice (before the first push and again for the CLS fix). `buildComicCard`'s default output is byte-identical to the old function (8 old-vs-new comparisons). |
| **V2** nav + footer | green | All seven pages hash to nav `6888702FB15A` and footer `94D490107E55` (one distinct value each); the six other pages are not in the diff. |
| **V3** harness, deployed bytes | **22 of 22**, then 28 of 28 with the extras | `playwright/catalog-top-picks-verify.mjs` against the served bytes (served `app.js`, `catalog.html`, `style.css`, `config.js` hashed equal to the committed blobs first, on the plain URL). H1-H2 header and deadline banner unchanged; T1-T5 toggle, panel, badge, persistence; R1-R7 rail; A1-A3 arrows and paging (run at 1100 px so three pages are not clamped to the end: 2304 px landed, 2304 expected); M1-M2 modal and reserve (a pick that is NOT on the grid page; the row lands with the right `tenant_id`); S1 See more; P1 phone. Plus N1 (Admin ▾ unclipped at 641 / 900 / 1280) and PRINT (no rail, no art), and C1-C2 (CLS probe, 0.017 desktop / 0.023 mobile). |
| **V4** suite | see § 9.7 | Specs 10, 20 and 24 updated for D1 (one shared `openFilters(page)` helper in `fixtures/catalog.ts`, 6 call sites). **Negative control: spec 20 with the calls removed fails with "`#filter-variants` element is not visible"**, so the edit was necessary. |
| **V5** | met after one fix | § 9.3 and § 9.4. |
| **V6** screenshots | inspected | 1350 / 900 / 700 / 393 / 320 px, closed, rail and open states, from the deployed bytes; print emulation shows no rail and no art. |
| **V7** § 6 reproduction | **RED on the old bytes, GREEN on the new** | Hiding "Marvel" in `catalog_filters` and choosing Recommended For You: old bytes showed **4 of 5** cards from the hidden publisher (under a "filtered by store settings" note); new bytes show **0 of 1**. `catalog_filters` was restored after every run and re-read: **167 bytes, `updated_at 2026-09-29T14:54:40.858`, identical.** |

### 9.6 Negative controls (each new assertion seen red before it was trusted)

`--mutate=<name>` serves a COPY of the tree with one deliberate fault and requires the named check to go red. **All went red**: R2 `rail-uses-comic-card`, R3 `rail-keeps-actions`, R4 `rail-many-per-series`, R5 `rail-ignores-reserved`, R6 `rail-allows-variants`, R7 `rail-ignores-visibility`, T1 `panel-open-by-default`, T2 `toggle-inert`, T3 `panel-not-remembered`, T4 `badge-blind-to-covers`, A1 `prev-arrow-always-on`, A2 `paging-no-accumulate`, A3 `next-arrow-always-on`, M1+M2 `modal-ignores-picks`, S1 `see-more-no-select`, P1 `arrows-on-phone`, R3b `rail-title-unpinned`, H1 `header-class-changed`, H2 `deadline-banner-moved`, N1 `nav-links-scroll` (the design's `overflow-x: auto` on `.nav-links` clips the Admin ▾ panel, as § 3.4 warned), C1+C2 `rail-painted-early` (reproduces 0.0623 / 0.1326 exactly), V7b (old bytes).

**Three controls did not go red the first time, and each was a flaw in my check or mutation, not in the app:** R5 and A3 each have TWO layers that do the same job (`getTopPicks` and a re-check after the row fetch; `syncPicksArrows` and the immediate set in `pagePicks`), so breaking one proved nothing; both mutations now break both. **R3b was vacuous**: it compared card heights inside the rail, which a flex row stretches equal whatever the titles are; it now compares the rail's height with placeholders against its height with real cards (369.05 px both; without the two-line title pin 353.45 against 369.05, a 15.6 px shift). **Not given a dedicated mutation, stated plainly:** T5 (closed state remembered, nearly trivial because closed is the default), R1 (existence), PRINT, V7a.

### 9.7 V4 final run

Full suite, run directly with `npx playwright test --reporter=line` (not `run-smoke.ps1`), against the deployed final bytes. The first full run, on the build before the CLS fix, was **161 passed, 26.1 min, exit 0**; because the fix changes `catalog.html` and `style.css` the suite was run again on the final bytes: **161 passed, 25.0 min, exit 0, 0 failed, 0 flaky** (the run's own summary line; its teardown restored `catalog_filters`, 167 bytes, and deleted its synthetic tenant). Afterwards all four `app_settings` rows I touch or depend on (`catalog_filters`, `order_deadline`, `page_banner`, `maintenance_mode`) were re-read: values and `updated_at` identical to before the session, and no harness or Lighthouse user was left.

### 9.8 Deviations from the plan as written

1. **The search row, count and toggle share one CSS grid** (`.search-block`, with the two old wrappers `display: contents`). The plan moved the toggle into `.toolbar-header`, but on a phone the search box is hidden in favour of the header magnifier, which would have left the toggle alone on its own line; the grid keeps count and toggle on one line as before.
2. **The phone toggle is icon-only (44 px)**; before this it was a labelled "Filters" pill. The plan specified the 50 px icon button with an `aria-label`; the label text is gone on phones too.
3. **`.order('id')` added** to `getCatalogIds()`'s paged select (the F140 tiebreaker rule), so "the first standard cover of each series" is the same on every load. Not in the plan.
4. **`Recommendations.invalidate()`** is called after every reserve or cancel (the memoised ranking holds the customer's signal).
5. **The caption reads "Popular with other customers"** when no pick came from the customer's own history, instead of claiming reservations they do not have. The ranking uses reservations and history only, not subscriptions; the design's wording is used when at least one pick is personal.
6. `getTopPicks` returns `[{ id, tier }]`, not `id[]` (the caption needs the tier).
7. The empty-picks case **hides** the section (`hidden`) rather than removing it, so an admin switching to a customer who has picks can bring it back.
8. **§ 9.3:** the rail's placeholders are not painted from first paint; see above.
9. **§ 3.4 not built.**

### 9.9 Not verified, and known limits

- **Chromium only.** No WebKit, no real phone. The phone swipe was exercised with `scrollBy`, not a real touch gesture.
- **A staging customer with no history gets one or two picks** (the popular list is short there); the 20-card rail was exercised with seeded `reservation_history`. **Production's popular data and a 1,345-row signal were not measured**; the 30-reservation account above is the heaviest measured.
- **A returning customer who left the filter panel open** gets one shift when the page restores it (it is restored before the first fetch but after sign-in). V5 measured the closed default only.
- **Not exercised:** a pending or paused account, the admin customer switch (`loadTopPicks()` on change), keyboard navigation of the rail (cards are not focusable, as the grid's are not).
- **The 641-760 px nav overflow is untouched.** An admin at 700 px shows a horizontal scroll in the nav probe; nav CSS and markup are not in the diff (V2), and CLAUDE.md already records the overflow as pre-existing and unfiled.
- **Nothing in git asserts any of this.** The Playwright suite and the harness are gitignored local files; the harness and its 21 mutations live only in `catalogs/scripts/playwright/`.
- **A harness run killed mid-flight** (while I restarted the negative-control batch) skipped its own cleanup: one throwaway `pw-ctp-` user was left and deleted by hand, and `catalog_filters` was re-read and found intact.

### 9.10 For the promotion (a separate, explicitly requested `/promote-prod`)

- **`app.js` carries `merge=ours`**; its merge RESULT must be asserted equal to staging's copy (the driver has dropped it three times). **G-K, the F171 fix, also edits `app.js`** (a different region, `TenantContext`); land one and promote it, then the other, or promote together, and assert `app.js` either way.
- Scope is exactly `app.js`, `catalog.html`, `style.css` plus docs. **Write-smoke is warranted**: this touches `catalog.html` and `app.js` on the reserve path, and reserving from the rail's modal is a new route into `toggleReserve()` (reserve one title as a real customer, confirm the row and its `tenant_id`, cancel).
- ~~A staging customer's catalog now has a new **collapsed** filter panel and an icon-only toggle on phones; worth Rick looking at on a real phone before production.~~ **Superseded by § 10: phones are back to the previous view.** Worth Rick looking at a real phone all the same, now to confirm it is unchanged.

## 10. Round two: desktop only, blended picks, deadline message over the banner (Rick, 2026-10-09, after § 9)

Rick's instruction, verbatim: **"Restore previous mobile view. This change is for desktop view only. Top Picks should Based on reservations and most popular reservations for the store. Move Reserve by message centered over banner."** Commit `3781c4b`, staging only, not promoted.

### 10.1 How each point was read, and what was built

| Point | Reading | Built |
|---|---|---|
| "Restore previous mobile view. This change is for desktop view only." | "Mobile" is the 640 px line the codebase already uses; "desktop" is 641 px and up. **Everything in § 9 is desktop only**: the search row, the collapsed panel and its memory, the rail. | The pre-redesign phone CSS is now the **base** (copied from the old inline block) and the redesign sits wholly inside `@media (min-width: 641px)`, so a phone cannot be reached by it. The labelled "Filters" pill is back beside the count (its DOM home, `.results-toolbar`); the panel is closed until tapped and **not remembered**; the rail is `display: none` and `loadTopPicks()` returns early, so **a phone never fetches it**; the pre-first-render wait for the deadline read is desktop-only too, so a phone's load order is what it was. |
| "Top Picks should [be] based on reservations and most popular reservations for the store." | The rail blends the customer's own reservations (history plus this month's) with the store's most-reserved series (`get_popular_series`). The old order drained the personal list first, so anyone with a real history never saw a popular title (the 20-card test rail was 20 personal, 0 popular). | `getTopPicks()` **alternates**, personal first, one per series across both lists; whichever runs dry, the other fills the rest. Caption: "Based on your reservations and the store's most popular reservations"; no history: "The store's most popular reservations"; personal only: "Based on your reservations". **1:1 is my choice of ratio** (the instruction does not give one), one line in `getTopPicks` to change. |
| "Move Reserve by message centered over banner." | The order-deadline message ("Reserve by October 23 to lock in your … picks. What's this?") moves **onto** the page banner, centred. | A second element, `#deadline-hero`, inside the banner, centred on its box (`left`/`top` 50%), out of flow. Shown at **>= 1101 px**; the original row under the header is untouched and is what phones and widths up to 1100 px keep. |

**Why 1101 px.** The title block is about 330 px wide, so a pill centred on the card clears it only when (card width - pill width) / 2 exceeds that; the pill wraps to two lines down to 1101 px (12 px clear of the title there, 40 px at 1350). Below that it would sit on the title. **If Rick wants the message on the banner at narrower desktop widths too, that is a design question** (smaller type, or the pill beside rather than over the art), not a bug.

### 10.2 Evidence (deployed staging bytes, served files hashed equal to the commit first)

| Check | Result |
|---|---|
| **PAR1-PAR3, the phone against the pre-redesign build** | The commit before any of this work (`6ef128d`: `catalog.html`, `style.css`, `app.js`) is served next to the current build, same user and data. **Every element box (nav, header, deadline row, promo, toolbar rows, count, pill, panel, grid, first card) and the pill's computed style (padding, radius, colours, font, gap, size, label text), the badge, the count and the panel's style are EQUAL** at 393 and 320 px, in three states: closed, open, a non-default filter chosen. |
| **PAR4, phone layout shift** | **Equal**, shift by shift: 0.0016, 0.0076, 0.0093 = 0.0185 in both builds (unthrottled probe). |
| D1, D2 | At 1350 and 1101 px the pill is inside the banner, **dx 0, dy 0**, 40 / 12 px clear of the title text, and the row below the header is hidden; at 1100, 900, 700 and 393 px the row shows and the pill is hidden. |
| B1-B3 | 18 personal + 2 popular on the 20-card test rail, order **P Q P Q …**; both captions exact. |
| P1 (rewritten) | At 390 px: rail `display: none`, **no rail request made**, the "Filters" pill (8 px 13 px padding, 4 px radius) on the count line, panel closed, **not remembered after a reload**. |
| Harness, whole | **37 of 37** on the deployed bytes. |
| Lighthouse, final bytes | **Mobile 93 and 93, LCP 3.1 to 3.2 s, CLS 0.018**, the original baseline (90 and 93, 3.1 s, 0.018). **Desktop 100 and 100, CLS 0.011** (baseline 100, 0.025; the centred message is out of flow, which also removes the shift the row below caused). |
| Negative controls | **18 new, every one went red** (blend stacked, both captions, rail shown on a phone, rail fetched on a phone, panel remembered on a phone, icon-only pill, wrapper box, hero not centred, hero shown when narrow, old row kept on desktop, and re-runs of the reserved / variants / visibility / panel / toggle / T3 / badge controls). A pre-flight that every mutation target still exists **caught three old mutations pointing at code I had rewritten** (they would have been silent no-ops); retargeted. |
| Full suite, final bytes | **161 passed, 24.9 min, exit 0, 0 failed, 0 flaky** (the run's own summary line; teardown restored `catalog_filters`, 167 bytes, and deleted its synthetic tenant). Afterwards `catalog_filters`, `order_deadline`, `page_banner` and `maintenance_mode` were re-read: values and `updated_at` identical to the start of the session, no harness or Lighthouse user left, no temp tree left. |

### 10.3 What the work found in its own earlier work

1. **A first draft of the phone layout was NOT equal.** The new `.search-block` wrapper, a plain block on a phone, made the layout-shift metric blame the wrapper (whose box includes the 10 px of empty `.toolbar-header` spacing above the count) instead of `.results-toolbar`: identical movement (23 / 87 / 107 px), scored **27% higher** (0.0235 against 0.0185). Found by PAR4, fixed with `display: contents` on a phone, after which every individual shift matches.
2. **A second draft's pill stacked the clock on its own line** above the sentence (a flex row too narrow for both); rendered as flowing text with the clock inline.
3. The phone's "wait for the deadline read before the first grid render" (needed on desktop for the rail) was **gated to desktop** so a phone's load order is exactly what it was.

### 10.4 Superseded by this round

§ 3.3 D9 and the phone half of § 9.5 P1 (the 140 px swipe row); § 9.8 deviation 2 (the icon-only phone toggle); § 9.9's "swipe exercised with `scrollBy`" (there is no phone rail); the "Based on your reservations and subscriptions" and "Popular with other customers" captions. § 9.3's reasoning stands, but the deadline message no longer shifts anything at >= 1101 px (out of flow); the row below the header still does at 641 to 1100 px, which is why the rail is still held back until it has settled.

### 10.5 Not verified

**Chromium only**: no WebKit, no real phone (the phone claim is "equal to the pre-redesign build in Chromium at 393 and 320 px", which is strong but is not an iPhone). The **hover tooltip** on "What's this?" in the banner was inspected in screenshots only; a tooltip's pseudo-element cannot be asserted. A **desktop window narrowed across 641 / 1101 px** swaps the two message elements by CSS only, no JS, and was measured at fixed widths, not by dragging. The 641 to 1100 px "row under the header" view is unchanged from before this whole effort, but its pairing with the new rail above the grid at those widths was only screenshotted at 900 px.

## 11. Round three: the rail collapses while a search or filter is active (Rick, 2026-10-09, after § 10)

Rick, verbatim: **"Okay I see the the search/filter runs on desktop and the rail is still visiable I would like it to hide or collapse when search or filter is active. I am leaning to collapse since you can pin a filter."** Then, on seeing the first build: **"TOP PICKS FOR YOU title is still visiable when collapsed."** Commits `f15ba8b` (the collapse) and `aab315d` (the title), staging only, not promoted.

### 11.1 What was built

- **Collapse, not hide**, as Rick leaned, for his own reason: a filter can be pinned, so a hidden rail would stay hidden under it for good; a collapsed one can always be opened.
- **Active** = search text, or any filter other than the defaults (distributor, publisher, the view select, covers; the four the Filters badge counts). **"See more" sets the view to Recommended, which is a filter, so it collapses the rail too**: the grid is then showing it.
- **The rule acts on transitions, not on every keystroke.** It collapses when something becomes active and opens when nothing is. A rail opened by hand (the **Hide / Show top picks** button) stays open until the next transition, so typing another letter does not shut it again.
- **Search collapses the rail on the first character**; the grid reload is debounced 350 ms and the rail does not wait for it. Every other trigger (filters, a pin reset, "See more") comes through `loadCatalog()`, which now syncs first.
- **A pinned filter loads collapsed**, applied right after the pins are restored and before the rail is first painted (no flash of the open rail; measured CLS 0.015 on a pinned load).
- **Collapsed means out of the way.** The first build kept the whole header row (title, caption, "See more", "Show") and removed only the cards, which Rick rejected. Collapsed now hides the cards **and** the title, caption and "See more", leaving one quiet, borderless **"Show top picks"** control under the results count. It cannot disappear entirely: under a pinned filter the rail is collapsed on every visit and that control is the only way to open it. **If Rick wants nothing at all there, say so, but a pinned filter then hides the rail permanently.**
- Desktop only, as in § 10: on a phone the rail is `display: none` and the new logic only toggles a class on it. PAR1-PAR4 still show the phone equal to the pre-redesign build.

### 11.2 Evidence (deployed staging bytes, served files hashed equal to the commit)

| Check | Result |
|---|---|
| RC1 | No search or filter: open, with title, caption, "See more", cards and "Hide" offered. |
| RC2 | Typing collapses on the first character (cards, **title, caption and "See more" all gone**, only "Show top picks"); clearing it opens it again. |
| RC3 | A non-default filter collapses it; returning to the defaults opens it. |
| RC4 | Opened by hand, it stays open while the search keeps changing, and the rule resumes at the next transition. |
| RC5 | "See more" collapses it. |
| RC6, RC7 | A pinned filter loads already collapsed and unpinning opens it; the pinned load shifts nothing (CLS 0.0146, unthrottled probe). |
| Harness, whole | **44 of 44** (PAR1-PAR4, D1-D2, B1-B3, C1-C2, V7 and the rest all still green). |
| Negative controls | **10 new, every one went red**: rail never collapses, search not counted, filters not counted, manual choice clobbered, Hide/Show button inert, pinned load not collapsed (two layers, both broken), collapse waiting for the debounce, and the title / caption / "See more" left visible when collapsed. |
| Full suite, interim build (`f15ba8b`) | 160 passed + **1 flaky**, exit 0. The first attempt of `15-order-export-ledger:479` failed in its `adminPage` fixture's TEARDOWN with `deleteUser auth: 502 Bad Gateway` from Supabase's admin API (an infrastructure fault in an admin-page test; its assertions had not failed) and passed on retry. The 502 left one orphaned `pw-admin-` auth user (profile 0, reservations 0), which I classified by prefix and creation time and deleted (fresh read 404); the four `pw-pending-` users are the documented intended survivors and were left. |
| **Full suite, final bytes (`aab315d`)** | **161 passed, 25.1 min, exit 0, no flaky, no retries**; teardown restored `catalog_filters` (167 bytes) and deleted its synthetic tenant. Afterwards `catalog_filters`, `order_deadline`, `page_banner` and `maintenance_mode` read identical (values and `updated_at`), and no harness or Lighthouse user remains. |

### 11.3 Choices I made that the instruction did not specify

1. The transition rule (above), rather than "always follow the filters", so a hand-opened rail is not fought. ~~**The hand-open choice is not remembered across visits**, so a pinned filter means a click on "Show top picks" every visit.~~ *(Superseded the same day: Rick asked for it to be remembered, see § 12.)*
2. "See more" collapses the rail.
3. Labels: "Hide" / "Show top picks".
4. Collapse is instant, with no animation.

### 11.4 Observed, then FIXED the same day at Rick's report (`504c07d`)

**RESOLVED.** Rick: "when I set a filter and unpin it the badge count is not reset until the page is refreshed." The cause below was right; the fix is one `syncFilterBadge()` call in the unpin path, applied **at every width** (the phone's layout is unchanged, PAR1-PAR4 still pass; only this bug is fixed there too). Check **UN1 (desktop) and UN2 (phone)** reproduce his exact steps with no reload: set a filter, pin it, unpin it. **Red on the deployed bytes before the fix** (controls all defaults, button still `has-filters` with a "1" badge, at both widths), green after, red again with the call removed (negative control `unpin-badge-not-synced`). Harness 46 of 46 on the deployed bytes; **full suite on the final bytes 161 passed (27.0 min), exit 0, no retries**, and afterwards the four staging settings rows are identical and no harness user remains. No finding ID consumed. The text below is the earlier "observed, not fixed" note, kept as written.

**Unpinning leaves the Filters button claiming a filter is active.** The unpin path resets the controls and reloads without re-running `syncFilterBadge()`. Measured on the deployed bytes: after an unpin the controls read `|||standard` (all defaults) while the button still has its accent border and a **"1" badge**. It is pre-existing (the original inline-style code behaved the same) and it is on every width. It was left alone on purpose: one added call fixes it, but would change the phone view that Rick asked to have restored exactly. It does not affect the rail (its rule reads the controls directly; RC6 passes). Options: fix it everywhere (a small improvement on the phone too), file it as F172, or leave it.

### 11.5 Not verified

Chromium only. The collapse has no animation, so there is no motion to check. Keyboard operation of the Hide / Show button was exercised by a script click, not a real keypress. A window resized across 641 px with the rail collapsed was not exercised (the rail is simply `display: none` below it).

---

## 12. Round four: the rail remembers a hand choice (Rick, 2026-10-09, after § 11)

I asked whether a hand open/close should be remembered, because with a pinned filter the rail loads collapsed on every visit (§ 11.3 item 1). Rick answered **"Yes, remember it (build it first)"** and, in the same message, asked for the production promotion with it included. Commit `3d77722` (`catalog.html` only, +31/-3), staging only until the promotion.

### 12.1 What was built

- **Two situations, remembered separately:** *active* (a search or any non-default filter is on) and *inactive* (neither). Stored per user in `localStorage` under `pulllist_picks_open_<userId>` as `{ "active": true|false, "inactive": true|false }`. A situation with nothing stored keeps the automatic rule from § 11 (collapsed while active, open otherwise).
- **Saved when the customer presses Hide / Show top picks**, under whichever situation they are in at that moment. **Applied when the situation changes** (including the first paint, once pinned filters are restored), in place of the automatic rule. Between changes nothing is applied, so a hand choice is still not fought (RC4).
- **Desktop only.** On a phone there is no rail and no button, and the code returns before reading or writing, so a phone's storage is unchanged. Every storage access is wrapped in try/catch; a failure falls back to the automatic rule.
- **"See more" now follows the remembered *active* choice,** because it makes the Recommended view a filter: a customer who left the rail open under filters sees it stay open there. Say so if that is not wanted.

### 12.2 Evidence

| Check | Result |
|---|---|
| MEM1 | Under a pinned filter: collapsed by default, a hand-open survives a reload, and so does a hand-close. |
| MEM2 | With no filter: open by default, a hand-close survives a reload. |
| MEM3 | The two situations are independent (active: open, inactive: collapsed). |
| MEM4 | A second customer in the same browser starts from the default, not the first customer's choice. |
| MEM5 | On a phone nothing is written, even when the hidden button is pressed from script (a check that nothing is written would pass trivially if nothing could ever call the writer). |
| RC4 | **Changed with this round:** a rail opened by hand stays open while the search changes, and the choice is **remembered** at the next transition (it used to snap back to the automatic rule). RC5 and RC6 clear the stored choice first, so they still test the automatic rule. |
| Negative controls | **5, every one went red on the checks it should:** choice not saved (MEM1-MEM3), not applied (MEM1-MEM3), one slot for both situations (MEM3), key not per user (MEM4), written on a phone (MEM5). |
| Harness, working tree | collapse + memory groups **12 of 12**. |
| Harness, whole, deployed bytes (served `catalog.html` hashed equal to the commit first) | **50 of 51.** The one failure was **PAR4** (phone layout shift equals the pre-redesign build): old 0.0185, new 0.0206. The three `results-toolbar` shifts matched exactly; the extra 0.002 was two `nav-logo` shifts (a `#text -3px` and a `0px`), i.e. a web-font swap landing inside the probe. **Run down rather than waved through:** four more deployed runs passed (0.0185, 0.0191, 0.0191, 0.0191), and four local runs, where old and new are served the same way, passed (0.0185, 0.0191, 0.0185, 0.0185) **and the OLD build showed the same 0.0005 `nav-logo` shift in one of them**. The memory code returns before doing anything on a phone and touches no layout. Not fully explained: the larger two-shift version was seen once and not reproduced. |
| Full suite, deployed bytes | **161 passed, 25.5 min, exit 0, no failure, no flaky line** (the log's own summary; run directly with `npx playwright test --reporter=line`, not through `run-smoke.ps1`). The suite's teardown printed `catalog_filters restored (167 bytes)` and deleted its synthetic tenant. **No separate sweep for orphaned `pw-` auth users was run afterwards.** |

### 12.3 Not verified

Rick has not seen the remembered behaviour on staging. Layout shift and Lighthouse were **not re-measured** for the new case a remembered-open rail under a pinned filter makes possible (the open rail is painted from first paint in the space already reserved for it, so no shift is expected, but that is reasoning, not a measurement). The storage-throws path (private windows) is wrapped but not exercised by a script. The memory is per browser and per user, so a customer on a second device starts from the automatic rule. Chromium only.
