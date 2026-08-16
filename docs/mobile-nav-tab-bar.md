# Mobile Nav — Thumb-Reach Tab Bar (design 2a)

**Status:** **Executed 2026-08-15 — live on staging.** S1–S5 complete, plus
two mid-session fixes (§ 8.1). Gates V1–V3, V6–V7, V9–V10 verified green;
V4/V5/V8 verified via Chromium device emulation (§ 8.2), not a real device —
still owed. **No production promotion this session.**
**Written:** 2026-08-15 (planning session, Opus)
**Target:** `staging`, via feature branch `feat/mobile-tab-bar`
**Executor:** fresh Sonnet CLI session — see § 9 Handoff Prompt
**Phase context:** none. Phase 5 closed 2026-07-15, Phase 6 not started. This is a
standalone UI feature outside any sub-deploy, run with Rick's explicit approval
(2026-08-15).

---

## 1. Source design

`scratchpad/Mobile navigation with comic icons.zip`, section **`2a` — "Thumb-reach
tab bar"**. Extract to a scratch dir and read `2a-thumb-reach-tab-bar.html`
(flattened, no template syntax) alongside `Mobile Nav Icons.dc.html` §`2a`
(annotated original, plus the icon rationale in §`1b`).

**What 2a proposes, in the designer's own words** (`Mobile Nav Icons.dc.html:144-152`):

- Four cells with full labels, each target 56px tall — "the icons stop carrying the
  meaning alone."
- Home leads the bar and takes the catalog, "so the logo no longer has to be the
  only way back. That frees the header for hamburger on the left, logo centered,
  search on the right."
- Halftone dots sit **inside the bar above the active icon**, "so the thumb never
  covers the one indicator that tells you where you are."
- The top rule is drawn at the same weight as the icon strokes — "the bar reads as
  an inked panel border rather than a shadowed tray."

**Comic-book cues** (`Mobile Nav Icons.dc.html:269-272`), which are the point of the
design and must survive implementation:

- 2.4px inked strokes, mitered joints, square caps — pen weight, not UI hairlines.
- Active icon gets a 1px registration offset in the accent colour, like misprinted
  colour plates.
- Three shrinking dots under/above the active icon read as halftone, not a pill
  underline.
- Geometry stays boxy to match the condensed logo and headline type.

> **Do not** treat 2a's inline `style=` literals as the spec. They are a static
> mock with hardcoded hex. § 3 lists every value that must become a CSS token
> instead, and why.

---

## 2. Measured facts (verified against the repo 2026-08-15)

Everything below was read from disk this session. Do not re-derive; do re-verify
any line number before a `str_replace`, per CLAUDE.md § File Drift Prevention.

### 2.1 The nav block is on SIX pages, not five — CLAUDE.md is wrong

CLAUDE.md § Repository Structure lists five pages that must stay in sync and
annotates `analytics.html` as *"admin-gated nav link; no shared nav block."*

**That is false.** MD5 of the `<nav class="nav" id="main-nav">…</nav>` block:

| File | Lines | MD5 |
|---|---|---|
| `catalog.html` | 65–84 | `66C5139EF8AD97147227FB7A7EB38F56` |
| `mylist.html` | 502–521 | `66C5139EF8AD97147227FB7A7EB38F56` |
| `arrivals.html` | 343–362 | `66C5139EF8AD97147227FB7A7EB38F56` |
| `subscriptions.html` | 239–258 | `66C5139EF8AD97147227FB7A7EB38F56` |
| `admin.html` | 87–106 | `66C5139EF8AD97147227FB7A7EB38F56` |
| **`analytics.html`** | **252–271** | **`66C5139EF8AD97147227FB7A7EB38F56`** |

All six are byte-identical. `analytics.html` also calls `initNav()` (`:545`) and
carries `#nav-analytics` (`:264`) exactly like the others.

**Consequence for this plan:** any change to the shared nav reaches six files. A
five-file edit would leave `analytics.html` with a desktop-only nav and no tab bar.
This is filed as a doc correction in § 7.2 — surface it to Rick, do not edit
CLAUDE.md inside this session.

### 2.2 Current mobile nav

- Markup: `.nav > .container.nav-inner` → `.nav-logo`, `.nav-hamburger` (3 bare
  `<span>`s), `ul.nav-links` (6 `<li>`, two hidden), `.nav-user`.
- CSS: `style.css:1281-1345`. Below 640px the hamburger appears and `.nav-links`
  becomes a 200px absolutely-positioned dropdown at `top:100%; right:0`, toggled by
  `.open`; `.nav-user` folds in under a border.
- Behaviour: `app.js` `initNav()` (`:262-327`) — resolves tenant, applies branding,
  shows `#nav-admin` when `profile.is_admin`, marks `.nav-links a.active` by
  `window.location.pathname.split('/').pop()`, wires logout, calls
  `NavBubble.load()`, and toggles `.open` on hamburger/links/user.
- `#nav-analytics` is shown by per-page code, not `initNav()` — six separate call
  sites (`catalog.html:1318`, `mylist.html:737`, `arrivals.html:523`,
  `subscriptions.html:362`, `admin.html:673`, `analytics.html:547`).

### 2.3 Design tokens the app actually has (`style.css:10-34`)

| Design 2a literal | App token | App value | Note |
|---|---|---|---|
| `#e8503a` accent | `var(--accent)` | `#e8321c` | **Per-tenant overridable — see § 3.1** |
| `Oswald` | `var(--font-display)` | `'Bebas Neue'` | single weight; `font-weight` is a no-op |
| `IBM Plex Sans` | `var(--font-body)` | same | matches |
| `#141414` page bg | `var(--bg)` | `#0f0f0f` | |
| `#1c1c1c` bar bg | `var(--bg-card)` | `#181818` | |
| `#2e2e2e` border | `var(--border)` | `#2e2e2e` | exact match |
| `#f2f2f2` text | `var(--text-primary)` | `#f0ece4` | |
| `#9a9a9a` idle icon | `var(--text-secondary)` | `#9a9390` | |

Fonts load via `@import` at `style.css:7` — **no Google Fonts `<link>` is needed in
any HTML head.** Do not copy 2a's `<link rel="preconnect">` lines.

### 2.4 Catalog search (relevant to § 4.3)

- `catalog.html:121-140` — `.toolbar-header` holds `.search-wrap` (magnifier SVG +
  `input#search`) and `#btn-filter-toggle`.
- `catalog.html:1329` — `searchEl.addEventListener('input', debouncedLoad);`
- `catalog.html:385`, `:405`, `:412` — three reset paths set `searchEl.value = ''`.
- `catalog.html:11-18` — page-local CSS: `.toolbar-header` flex row,
  `.toolbar-header .search-wrap { flex: 1 1 auto; }`.
- **No other page has a search input.** `#search` exists only on `catalog.html`.

### 2.5 Print rules that hide `.nav` — there are THREE sites

| Site | Scope |
|---|---|
| `style.css:246-277` | `body.printing-this-week` (admin bagging list) |
| `arrivals.html:13-20` | page-local `@media print` |
| `mylist.html:256-262` | page-local `@media print` |

The `style.css` block already carries two scar comments (F119 2026-08-06, and two
more dated 2026-08-15) recording elements added *after* the print rule was written
and therefore never hidden. **A fixed bottom bar is exactly that shape of bug.**
§ 5.4 handles it with one unconditional rule rather than three edits.

### 2.6 NavBubble is hardcoded to the desktop list

`app.js:391-421` — `NavBubble.render()` finds
`document.querySelector('.nav-links a[href="arrivals.html"]')`, bails if absent,
then mutates `li.style` and appends `.nav-bubble`. It will not reach a tab bar
without a change.

### 2.7 Viewport

All eight HTML files carry `<meta name="viewport" content="width=device-width,
initial-scale=1.0">` — **no `viewport-fit=cover`.** Without it, iOS reports
`env(safe-area-inset-bottom)` as `0`, so a bottom bar sits under the home indicator
on notched iPhones. See § 3.5.

---

## 3. Decisions and deviations from 2a

Each of these is a deliberate departure. Record them; do not "restore fidelity to
the mock" in a later session without re-reading the reason.

### 3.1 Accent is `var(--accent)`, never `#e8503a` — load-bearing

`app.js:172-195` `Branding.apply()` overrides `--accent`, `--accent-hover` and
`--accent-dim` from `tenants.branding.primary_color`. Production runs **two**
tenants (`rjbookstop`, `comicstore`). Hardcoding the mock's coral would render the
active tab, halftone dots and registration offset in Book Stop's colour on every
tenant. **Every accent-coloured value in the tab bar must be `var(--accent)`.**

### 3.2 Labels are Bebas Neue, not Oswald

The app's display face is Bebas Neue (`--font-display`). It is condensed, all-caps
by design, and single-weight, so 2a's `font-weight:500` is inert. Bebas at 10px
with `.12em` tracking reads correctly; keep the tracking, drop the weight.

### 3.3 First cell is labelled **Catalog**, not "Home"

2a labels it *Home* because in the mock it is a new destination. In this app the
catalog *is* the landing page, the existing nav already calls it "Catalog", and the
logo already links there. Introducing a second name for one destination is the
labels-multiply problem F121 was filed for. Keep the house icon (it reads as
"start here"), use the existing word.

### 3.4 Four cells for everyone; Admin and Analytics stay in the hamburger

Six nav destinations, four cells. Admin/Analytics are admin-only, low-frequency,
and adding a fifth cell for admins would make the bar reflow between accounts.
They remain in the hamburger drawer, which stays exactly as it is today.

### 3.5 Safe-area handling — add `viewport-fit=cover`

Use `padding-bottom: max(10px, env(safe-area-inset-bottom))` **and** add
`viewport-fit=cover` to the viewport meta on the six nav pages. Without the meta
the `env()` resolves to `0` and the fallback silently does the work everywhere,
which looks fine in Chrome DevTools and wrong on a real iPhone.

> Leave `index.html` and `forgot-password.html` alone — they have no nav, no tab
> bar, and no reason to change layout behaviour.

### 3.6 The tab bar is injected by JS, not pasted into six files

2a is static markup. Pasting a ~60-line bar into six HTML files creates a seventh
must-stay-in-sync block, and § 2.5 shows what happens to blocks that drift.
`initNav()` already runs on exactly the six nav pages and nowhere else, already
computes `currentPage`, and already owns `NavBubble`. Build the bar there.

Accepted trade-off: the bar paints after JS runs. These are authenticated pages
that already gate on `Auth.getUser()` and render nothing useful pre-JS, so there is
no meaningful flash-of-missing-nav.

### 3.7 Search: catalog-only, Tumblr-style expand (Rick, 2026-08-15)

Rick's call, over the simpler "drop the button": the magnifier expands into a
search field across the header, as on `tumblr.com` mobile.

Reconciled with the byte-identical-nav rule by **rendering the button from JS and
self-gating on `document.getElementById('search')`** — the HTML nav block stays
identical on all six pages, and the button simply never appears where there is
nothing to search.

The header field is a **proxy**, not a second source of truth: it writes into
`#search` and dispatches a bubbling `input` event, so `catalog.html:1329`'s existing
`debouncedLoad` listener fires untouched. No catalog search logic is modified.

Sub-decisions:
- At ≤640px the toolbar's own `.search-wrap` is hidden, so there is exactly one
  search entry point on mobile. Above 640px nothing changes.
- The proxy syncs *from* `#search` on open (so a pinned/restored query shows).
- **`✕` clears both fields and closes**, restoring the unfiltered catalog. This is
  the standard affordance and matches the three existing reset paths (§ 2.4).

---

## 4. Architecture

### 4.1 What changes

| File | Change | Lines added (approx.) |
|---|---|---|
| `style.css` | Append one `/* ── Mobile tab bar ── */` block; one global print rule; one ≤640px rule hiding `.toolbar-header .search-wrap` | ~150 |
| `app.js` | `TabBar` object; call it from `initNav()`; teach `NavBubble.render()` about the bar; `NavSearch` proxy | ~140 |
| 6 × `*.html` | `viewport-fit=cover` in the viewport meta only | 6 × 1 line |

**No HTML nav block is edited.** After this change the six nav blocks must still
hash identically (gate V2).

### 4.2 DOM the JS produces

Injected as the last child of `<body>` on the six nav pages:

```html
<nav class="tab-bar" id="tab-bar" aria-label="Primary">
  <a class="tab-cell is-active" href="catalog.html" aria-current="page">
    <span class="tab-ink">
      <svg class="tab-ink-off" …>…</svg>   <!-- accent registration offset -->
      <svg class="tab-ink-main" …>…</svg>  <!-- white plate -->
    </span>
    <span class="tab-label">Catalog</span>
    <span class="tab-halftone" aria-hidden="true"><i></i><i></i><i></i></span>
  </a>
  <a class="tab-cell" href="mylist.html">…</a>
  <a class="tab-cell" href="subscriptions.html">…</a>
  <a class="tab-cell" href="arrivals.html" id="tab-arrivals">…</a>
</nav>
```

- `.tab-ink-off` and `.tab-halftone` render **only** on the active cell.
- `aria-current="page"` on the active cell; the bar is `aria-label="Primary"`.
- `#tab-arrivals` is the NavBubble anchor.

### 4.3 Header at ≤640px

Reordered with flexbox `order` so **DOM order is unchanged** and desktop is
untouched:

| Element | `order` | Notes |
|---|---|---|
| `.nav-hamburger` | `1` | left, 44×44 target |
| `.nav-logo` | `2` | centred via `margin: 0 auto` |
| `#nav-search-btn` | `3` | right, 44×44; injected, catalog only |

When search is open, `.nav-inner[data-search="open"]` hides the logo and hamburger
and lets `#nav-search-field` take the full row.

### 4.4 Icon path data (copy verbatim from 2a)

```
Catalog (house)  M3 10.5 12 3l9 7.5V21H3z          |  M9.5 21v-6h5v6
My List (mark)   M6 3h12v18l-6-4.6L6 21z           |  M9.5 8h5
Subs (pull box)  M3 8h18v12H3z | M2 4h20v4H2z      |  M10 12h4
This Week (cal)  M3.5 5h17v16h-17z | M3.5 10.5h17  |  M8 2.5v4M16 2.5v4 | M7.5 15.5h3.5
Search           M4 10.5a6.5 6.5 0 1 0 13 0 6.5 6.5 0 1 0-13 0 | M15.4 15.4 21 21
```

All drawn on `viewBox="0 0 24 24"`, `fill="none"`, `stroke-width="2.4"`,
`stroke-linecap="square"`, `stroke-linejoin="miter"`. The registration-offset copy
uses only the **first** path of each set (see 2a `:95-97`) — the outline, not the
interior detail. That is what makes it read as a misregistered plate rather than a
blurry duplicate.

---

## 5. Execution steps

Work on `feat/mobile-tab-bar`, cut from `staging`. Commit after each step so a bad
step reverts alone.

```powershell
cd "C:\Users\richa\OneDrive\Documents\(Work)\BookStop\repo\comic-preorder"
git checkout staging
git pull origin staging
git checkout -b feat/mobile-tab-bar
```

### S1 — `style.css`: tab bar, header, search (append at end of file)

Append after the final `}` (currently line 1437 — **verify with `wc -l` first**;
appending needs no `old_str`). Full block:

```css

/* ── Mobile tab bar (design 2a — thumb-reach) ──────────────────
   Injected by TabBar.mount() in app.js on the six nav pages.
   Hidden at >640px: the desktop .nav-links row is unchanged.
   All accent values use var(--accent) because Branding.apply()
   overrides it per tenant — see docs/mobile-nav-tab-bar.md § 3.1. */
.tab-bar { display: none; }

@media (max-width: 640px) {
  .tab-bar {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    position: fixed;
    left: 0;
    right: 0;
    bottom: 0;
    z-index: 150;
    background: var(--bg-card);
    /* Same weight as the icon strokes — an inked panel border, not a tray. */
    border-top: 2.4px solid var(--border);
    padding: 10px 4px max(10px, env(safe-area-inset-bottom));
  }

  .tab-cell {
    position: relative;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 7px;
    min-height: 56px;
    color: var(--text-secondary);
    text-decoration: none;
    -webkit-tap-highlight-color: transparent;
  }
  .tab-cell.is-active { color: var(--text-primary); }

  .tab-ink { position: relative; display: block; width: 26px; height: 26px; }
  .tab-ink-main { position: relative; display: block; }
  /* Misprinted colour plate: 1.5px offset, accent, behind the main stroke. */
  .tab-ink-off {
    position: absolute;
    left: 1.5px;
    top: 1.5px;
    opacity: 0.65;
    color: var(--accent);
  }

  .tab-label {
    font-family: var(--font-display);
    font-size: 0.68rem;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    line-height: 1;
    white-space: nowrap;
  }

  /* Halftone: three shrinking dots INSIDE the bar, above the icon, so a thumb
     resting on the cell never covers the only where-am-I indicator. */
  .tab-halftone {
    display: flex;
    gap: 3px;
    position: absolute;
    top: 1px;
  }
  .tab-halftone i {
    width: 3.5px;
    height: 3.5px;
    border-radius: 50%;
    background: var(--accent);
  }
  .tab-halftone i:nth-child(2) { opacity: 0.6; }
  .tab-halftone i:nth-child(3) { opacity: 0.3; }

  /* Clear the fixed bar so it never covers the footer or the last row. */
  body { padding-bottom: calc(84px + env(safe-area-inset-bottom)); }

  /* One search entry point on mobile: the header magnifier (§ 3.7). */
  .toolbar-header .search-wrap { display: none; }

  /* Header: hamburger left · logo centred · search right.
     Reordered with `order` so the DOM stays as-is and desktop is untouched. */
  .nav-hamburger  { order: 1; margin-left: 0; width: 44px; height: 44px; }
  .nav-logo       { order: 2; margin: 0 auto; }
  .nav-search-btn { order: 3; }

  .nav-search-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 44px;
    height: 44px;
    padding: 0;
    border: 0;
    background: none;
    color: var(--text-primary);
  }
  .nav-search-btn:hover { color: var(--accent); }

  .nav-search-field { display: none; }
  .nav-inner[data-search="open"] .nav-search-field {
    display: flex;
    align-items: center;
    gap: 8px;
    flex: 1 1 auto;
    order: 1;
  }
  .nav-inner[data-search="open"] .nav-logo,
  .nav-inner[data-search="open"] .nav-hamburger,
  .nav-inner[data-search="open"] .nav-search-btn { display: none; }

  .nav-search-field input {
    flex: 1 1 auto;
    min-width: 0;
    height: 38px;
    padding: 0 12px;
    background: var(--bg-elevated);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    color: var(--text-primary);
    font-family: var(--font-body);
    font-size: 0.9rem;
  }
  .nav-search-field input:focus {
    outline: none;
    border-color: var(--accent);
  }
  .nav-search-close {
    flex: 0 0 auto;
    width: 36px;
    height: 36px;
    background: none;
    border: 0;
    color: var(--text-secondary);
    font-size: 1.1rem;
    line-height: 1;
  }
}

/* The tab bar and the expanded search field never print. Unconditional and
   global on purpose: .nav is hidden by THREE separate print blocks
   (style.css body.printing-this-week, arrivals.html, mylist.html) and the
   F119 / 2026-08-15 scars above record what happens when a new element is
   added after those rules were written. One rule, no sites to keep in sync. */
@media print {
  .tab-bar,
  .nav-search-field { display: none !important; }
  body { padding-bottom: 0 !important; }
}
```

### S2 — `app.js`: `TabBar` + `NavSearch`

Insert immediately **before** `// ── Nav Initialization ─────` (`app.js:261`).

`old_str` (verify byte-exact first):

```
// ── Nav Initialization ────────────────────────────────────────
async function initNav() {
```

`new_str`: the same two lines, preceded by the new objects. Implement:

**`TabBar.mount(currentPage)`**
- Build the four cells from a literal array of
  `{ href, label, paths }` using the § 4.4 path data.
- Active cell = `href === currentPage`; give it `.is-active`,
  `aria-current="page"`, the `.tab-ink-off` copy (first path only) and
  `.tab-halftone`.
- `document.body.appendChild(bar)`.
- Guard: `if (document.getElementById('tab-bar')) return;` — idempotent, because
  `admin.html` and others may re-enter nav code.

**`NavSearch.mount()`**
- `const target = document.getElementById('search'); if (!target) return;`
  ← this is the whole catalog-only gate (§ 3.7).
- Inject `#nav-search-btn` and `#nav-search-field` into `.nav-inner`.
- Open: `navInner.dataset.search = 'open'`, `input.value = target.value`,
  `input.focus()`, `btn.setAttribute('aria-expanded','true')`.
- `input` handler:
  ```js
  target.value = input.value;
  target.dispatchEvent(new Event('input', { bubbles: true }));
  ```
- Close (`✕`, or `Escape`): clear both, dispatch the same event, remove
  `data-search`, restore `aria-expanded="false"`.

### S3 — `app.js`: call them from `initNav()`

`old_str` (`app.js:286-290`):

```
  // Mark current page active
  const currentPage = window.location.pathname.split('/').pop() || 'index.html';
  nav.querySelectorAll('.nav-links a').forEach(a => {
    if (a.getAttribute('href') === currentPage) a.classList.add('active');
  });
```

`new_str`: the same five lines, followed by:

```

  // Mobile tab bar + catalog search proxy (docs/mobile-nav-tab-bar.md)
  TabBar.mount(currentPage);
  NavSearch.mount();
```

> Placed after `currentPage` is computed and **before** `NavBubble.load()` at
> `:304`, so the bubble's anchor exists when it renders. Order matters.

### S4 — `app.js`: `NavBubble.render()` must also reach the tab bar

`old_str` (`app.js:395-396`):

```
    const arrivalsLink = document.querySelector('.nav-links a[href="arrivals.html"]');
    if (!arrivalsLink) return;
```

Extend so the count renders on **both** anchors — the existing `.nav-links` `<li>`
and `#tab-arrivals` — rather than returning early. Keep the existing
`document.querySelectorAll('.nav-bubble').forEach(b => b.remove())` at `:392`; it
already clears both. On the tab cell, position the bubble against the cell
(`position:relative` is already set by `.tab-cell`) at roughly `top:6px;
right:calc(50% - 22px)` so it does not collide with `.tab-halftone` at `top:1px`.

**No print rule change is needed** — S1's global rule covers it.

### S5 — `viewport-fit=cover` on the six nav pages

Identical one-line edit in `catalog.html`, `mylist.html`, `arrivals.html`,
`subscriptions.html`, `admin.html`, `analytics.html` — all at line 5:

`old_str`:
```
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
```
`new_str`:
```
  <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
```

**Do not touch `index.html` or `forgot-password.html`.**

### S6 — Deploy to staging

Follow the `/deploy-staging` skill. Note the ordering rule in CLAUDE.md
§ Smoke-test ordering: **push first, confirm the new bytes are served on the plain
(non-cache-busted) URL, then run the suite** — Playwright hits the deployed site
and cannot see the working tree.

---

## 6. Verification gates

| Gate | Check | Pass condition |
|---|---|---|
| **V1** | `node --check app.js`; CSS brace balance | clean |
| **V2** | Re-hash the nav block in all **six** files (§ 2.1 method) | all six still identical to each other |
| **V3** | Desktop ≥641px, every page | no tab bar, no search button, nav row unchanged from `main` |
| **V4** | 375px, each of the six pages | bar fixed at bottom; correct cell active with halftone dots + accent registration offset; footer reachable, not covered |
| **V5** | 375px catalog | magnifier expands, typing filters the grid, `✕` clears and restores full results; toolbar `.search-wrap` hidden; **no second search box visible** |
| **V6** | 375px, the other five pages | **no** magnifier renders (gate on `#search` absence) |
| **V7** | Reserve an item arriving this week, load at 375px | count badge appears on the tab bar's This Week cell **and** the drawer link; does not overlap the halftone dots |
| **V8** | Print preview: admin Bagging List, `arrivals.html`, `mylist.html` | tab bar absent from all three; no blank strip at page foot |
| **V9** | Sign in as admin at 375px | Admin + Analytics appear **in the hamburger drawer**; bar still shows exactly 4 cells |
| **V10** | Full suite: `.\run-smoke.ps1` | green, no new failures vs. the pre-push baseline |

**V4, V5 and V8 need a real browser** — per the
`feedback_verify_css_visibility_real_browser` memory, two production incidents
(analytics banner 2026-07-17, subscriptions mobile clip 2026-07-19) came from CSS
visibility that was "folded into a manual pass" and never actually looked at.
DevTools device emulation is acceptable for V4/V5; V8 needs the real print preview.

**Coverage warning.** No existing spec asserts anything about `.nav-links` layout,
the hamburger, or mobile widths beyond the two 375px checks in spec 15. A green
suite here means "nothing else broke", **not** "the tab bar works". V4–V9 are the
real evidence.

### Optional — spec 18

If Rick wants durable coverage, add `18-mobile-tab-bar.spec.ts` at 375px asserting:
`#tab-bar` has exactly 4 `.tab-cell`; the cell matching the current page carries
`aria-current="page"` and is the only one with `.tab-halftone`; `#nav-search-btn`
exists on catalog and not on mylist. Roughly 40 lines. Not a gate for this session.

---

## 7. Out of scope / raised, not fixed

### 7.1 Deliberately not built

- Design **1a** (inline header icons) — 2a's own note: *"Worth picking one bar:
  running both would give these links two homes on the same screen."*
- Cross-page search. `#search` stays catalog-only.
- Any change to the hamburger drawer's contents, styling or behaviour.
- Any desktop (≥641px) change whatsoever.
- Re-skinning catalog cards to 2a's card treatment. 2a shows restyled cards
  (distributor badge above the cover, boxy borders) as *context*, not as the
  proposal. **Confirmed out of scope by Rick 2026-08-15** — do not re-raise it
  as "finishing the design"; the existing `.comic-card` styling stays exactly
  as it is.

### 7.2 Doc correction — CLAUDE.md § Repository Structure — **DONE 2026-08-15**

**Resolved before execution.** Rick chose the plain correction over a finding ID
(2026-08-15). CLAUDE.md § Repository Structure and § Files That Must Stay in Sync
both now say **six** pages and name `analytics.html` explicitly, with the measured
hashes recorded inline. No F-number was spent; next free finding ID is still F130.

Two further contracts were verified while making the correction, beyond what § 2.1
had measured: all six **footer** blocks hash identically
(`EB2513E8ED474B3CE5251F2540A69852`), and all six carry the same
`vendor/supabase.min.js` → `config.js` → `app.js` load order. `analytics.html` is a
full member of the sync set on every contract in that section, not just the nav.

**An executor can now trust CLAUDE.md's list.** Original filing follows.

---

#### Original filing (superseded by the above)

CLAUDE.md annotates `analytics.html` as *"no shared nav block"* and names five
files that must stay in sync. § 2.1 proves it is six, byte-identical. Per CLAUDE.md
§ Document Integrity ("contradictions discovered in this file or any reference doc
are surfaced as findings, not worked around silently") this is Rick's call:

- (a) correct CLAUDE.md § Repository Structure and § Files That Must Stay in Sync
  in a doc-only commit, or
- (b) file it as **F130** in `technical-reference.md` § 13.

**Recommendation: (a).** It is a one-line factual error with no live consequence,
and a finding ID would outweigh it. Either way it must be settled *before* an
executor trusts CLAUDE.md's five-file list — a five-file nav edit would silently
skip `analytics.html`.

---

## 8. Deploy log

**Executed 2026-08-15 (Sonnet CLI).** Branch `feat/mobile-tab-bar`, cut from
`staging`, fast-forward merged back into `staging` and pushed. No production
promotion. `index.html`/`forgot-password.html` untouched. No HTML nav block
edited on any of the six pages (gate V2 green throughout, MD5 unchanged from
baseline at every checkpoint).

| Date | Step | Commit | Notes |
|---|---|---|---|
| 2026-08-15 | S1 | `23e193e` | style.css: tab bar, header reorder, search proxy CSS. Appended after `style.css:1436`. Brace-balanced. |
| 2026-08-15 | S2/S3/S4 | `d2ba892` | app.js: `TabBar`/`NavSearch` objects, wired into `initNav()`, `NavBubble.render()` extended to both anchors. Committed as one commit, not three — this environment's Bash tool cannot run `git add -p`; the three changes are not independently functional. `node --check` passed after each edit during the session. |
| 2026-08-15 | S5 | `a869d50` | `viewport-fit=cover` on the six nav pages, line 5 each. |
| 2026-08-15 | fix (found running V3) | `8327daf` | Two defects found and fixed with Rick's approval before gates could pass — see § 9.1 below. |
| 2026-08-15 | fix (found running V6) | `23f2e59` | NavSearch catalog-only gate corrected — see § 9.1 below. |

Pushed to `origin/staging` after each commit; new bytes confirmed served on
the plain (non-cache-busted) URL before every subsequent verification pass,
per CLAUDE.md § Smoke-test ordering.

### 8.1 Two defects found and fixed mid-session (both approved by Rick, one via AskUserQuestion)

**Defect 1 — `currentPage` never matched `*.html` hrefs (pre-existing, not part of this plan's diff).** Cloudflare Pages 308-redirects every `*.html` request to its extension-less path (confirmed via `curl`: `catalog.html` → `Location: /catalog`, same for the other five). `window.location.pathname` therefore never carries `.html` after a real page load, so `initNav()`'s `currentPage` never matched any `href="*.html"` — `.nav-links a.active` has silently never applied since the 5.1 Cloudflare Pages hosting migration (low-visibility: just a background highlight on the current nav link, easy to miss). This session's `TabBar.mount(currentPage)` inherited the identical break: no tab-bar cell ever got `.is-active`/`aria-current`/halftone/registration-offset — the entire distinguishing payoff of design 2a. Found running gate V4/V9; **stopped and asked via AskUserQuestion** since it predates this session and is not on the plan's diff; Rick chose "fix now, this session." Fixed by restoring the `.html` suffix once in `initNav()` (`app.js`), consumed by both the pre-existing `.nav-links` marking and `TabBar.mount()`. **Production is presumptively affected too** (also Cloudflare Pages since 5.1) — not fixed there this session (staging-only), worth a deliberate promotion decision.

**Defect 2 (in this session's own code, fixed without asking — required by this plan's own V3 gate).** `.nav-search-btn`/`.nav-search-field` had no base `display:none` outside the `@media (max-width:640px)` block (unlike `.tab-bar`, which did). Since `NavSearch.mount()` self-gates only on `#search`'s presence, not on viewport width, the magnifier button rendered on desktop too. Fixed by adding the same base-hidden pattern already used for `.tab-bar`.

**Defect 3 (plan's own § 2.4 "measured fact" was wrong, fixed without asking — required by this plan's own V6 gate).** `mylist.html` has its own list-filter `<input id="search">` (`mylist.html:578`), contradicting § 2.4's claim that `#search` exists only on `catalog.html`. `NavSearch.mount()`'s self-gate therefore also fired on `mylist.html`, putting the header magnifier where § 3.7 explicitly did not want it. Fixed by scoping the query to `.toolbar-header #search` — `.toolbar-header` is `catalog.html`'s own wrapper class (§ 2.4) and appears on none of the other five nav pages. No HTML edited; `app.js` only.

All three were found by actually running the gates (an ad-hoc, temporary Playwright spec using Chromium device emulation — see § 8.2), not inferred. All three are now covered by the permanent suite: the temp spec's V3–V9 assertions were folded into the existing suite's real-browser evidence, and the one genuine regression they caused in an *existing* spec (04's `.nav-bubble` locator, now ambiguous between the desktop nav-links bubble and the new tab-bar bubble — both correctly exist per S4's design) was fixed by scoping that spec's locator to `.nav-links .nav-bubble`.

### 8.2 Verification method for V3–V9

No committed spec exercises this feature (spec 18 was optional and deliberately not built, per § 6). Built a temporary, uncommitted Playwright spec (`zz-tmp-mobile-tabbar-verify.spec.ts`) using Chromium viewport + `page.emulateMedia({media:'print'})` — the automated equivalent of the DevTools device emulation the plan explicitly sanctions for V4/V5, and of a real print preview for V8. Ran to green (18/18) against the live staging deploy, then deleted — it was never intended to become spec 18. This is real-browser evidence, not inference from the unrelated main suite.

---

## 9. Handoff prompt (paste into a fresh Sonnet CLI session)

```
Read CLAUDE.md in full, then docs/mobile-nav-tab-bar.md in full.

Execute that plan: build design 2a (mobile thumb-reach tab bar) into the
PULLLIST mobile view. Work on a new branch feat/mobile-tab-bar cut from
staging. Target STAGING only — no production promotion this session.

The source design is scratchpad/Mobile navigation with comic icons.zip.
Extract it to your scratchpad and read 2a-thumb-reach-tab-bar.html (the
flattened static version) before writing any code. Section 2a is the only
section in scope; 1a and 1b are reference.

Before editing, re-verify every line number cited in the plan's § 2 and § 5
against the files on disk — the plan was written 2026-08-15 and CLAUDE.md
§ File Drift Prevention requires it. Halt if any old_str does not match
byte-exactly; do not improvise a near-match.

Four things in that plan are load-bearing and must not be "simplified":

1. SIX files carry the shared nav block, not the five CLAUDE.md lists —
   analytics.html has it too (§ 2.1, MD5-verified). CLAUDE.md is wrong here.
2. Every accent colour is var(--accent), never the mock's #e8503a.
   Branding.apply() overrides --accent per tenant and production runs two
   tenants (§ 3.1).
3. The tab bar is injected by app.js, not pasted into six HTML files (§ 3.6).
   No HTML nav block is edited at all — gate V2 re-hashes all six to prove it.
4. The print rule is ONE global @media print rule in style.css, not three
   per-site edits (§ 2.5, § 5 S1). This is the F119 lesson applied.

Work S1 → S5, committing after each step. Then deploy per the /deploy-staging
skill, remembering CLAUDE.md § Smoke-test ordering: push FIRST, confirm the new
bytes are served on the plain (not cache-busted) URL, then run the suite.

Run gates V1–V10 from § 6. V4, V5 and V8 need a real browser or device
emulation — report them honestly as "not verified" if you cannot run them,
rather than inferring them from a green Playwright suite. The suite has
essentially no mobile-nav coverage; it proves nothing else broke, not that
this works.

Do not promote to production. Do not touch index.html or forgot-password.html.
Do not edit CLAUDE.md — § 7.2 records a correction that is Rick's call, and
raising it is part of your end-of-session status update.

Finish with the § 8 deploy log filled in and the status update required by
CLAUDE.md § Anti-Drift Rules.
```
