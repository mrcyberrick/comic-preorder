# Catalog redesign: hero, search + filter toggle, Top picks rail

**STATUS:** NOT STARTED | staging=— | prod=— | findings=— (feature build; one pre-existing defect found while planning, § 6, proposed as F172, NOT yet filed)

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

### 3.4 Nav (`style.css` only)

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
- [ ] Search row, panel, rail and nav built (no hero, D2) on a feature branch, merged `--ff-only` to `staging`, pushed
- [ ] V1-V6 green (V7 if D10 stands), each with its evidence recorded in this doc
- [ ] Specs 10, 20, 24 updated for D1 and passing; full suite green post-push
- [x] § 6 filed or explicitly declined by Rick (2026-10-09: "Fix without an ID"; see § 6 Disposition)
- [ ] This doc's STATUS token and CLAUDE.md updated (finding-ID disposition stated: none consumed unless § 6 is filed)
