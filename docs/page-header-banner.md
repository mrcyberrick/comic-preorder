# Page header banner — brandable art beside the title on the four customer pages

**STATUS:** IN PROGRESS | staging=2026-10-02 (the follow-ups in sections 9, 10 and 11 are on staging only) | prod=2026-10-02 (PR #166, merge dc94e29: the first banner build, with the v1 art, the bolt on the art's edge and the old catalog subtitle) | findings=— (feature build, not a defect; **F169 is the next free finding ID**). Section 9-11 follow-ups NOT promoted; live write-smoke on production still owed by Rick; see CLAUDE.md.

**Last verified against live: 2026-10-02** (production serving PR #166's bytes, verified byte-identical to `origin/main` on both hostnames).

## 1. What this is

Each customer page's header (title + one subtitle line) leaves the right half of its row empty. This
fills it with a banner image, and lets the store change it.

- **Pages:** Catalog, My List, Subscriptions, This Week. **Not** Admin, Analytics or Settings (staff
  tools). One setting governs all four, so the storefront reads as one brand.
- **Default art** is cut from the apex page's hero (`assets/hero-v2.webp`: the caped figure on the
  skyline at sunset), so the app reads as the same product as pulllist.app.
- **Custom branding** follows the project's tier rule (`docs/f72-multi-tenant-branding.md` § 0.1): a
  *free* tenant gets platform defaults, a *paid* (`plan = 'pro'`) tenant can use its own image.
- **Settings ▸ Branding ▸ Page banner** is where an admin chooses: Default artwork / Custom image /
  No banner, with a live preview and its own Save.

## 2. Design decisions (and why)

| Decision | Choice | Why |
|---|---|---|
| Scope | The four customer pages, one setting | **Rick, 2026-10-01.** All four share the same header (h1 + one subtitle line, nothing on the right), so the banner fills existing empty space and adds no height. |
| Name | `page_banner` / `PageBanner` / `#page-banner` | It began as `catalog_*` and was widened **before** anything was saved or promoted, the only time the key renames for free. |
| Where it is stored | `app_settings` key `page_banner`, JSON text `{ v, mode, imageUrl }` | The only admin-writable per-tenant store. `tenants.branding` is operator-only, and the ask was "changeable in Settings". **No schema, RLS or Edge Function change**: `app_settings` has no key allowlist and its admin write policies already apply. |
| Absent row means | The default art (**banner on**) | **Rick, 2026-10-01: "On by default".** |
| Custom image tier | Paid only; a stored `custom` on a free tenant resolves to the **platform** art | Same direction as `Tier`: the free render is always the safe one. Free tenants may still pick *No banner*. |
| Custom image source | An `https://` address the admin hosts | **Rick, 2026-10-01: "Address only is fine".** No image storage exists in this project. The address is checked to actually load **before** it is saved. |
| A custom image that will not load | Shows **nothing**, never the platform art | Platform art on a store that chose its own would be the wrong shop's identity on its page. |
| Accent colour | The lightning bolt where the art begins uses `var(--accent)` | `Branding.apply()` already overrides `--accent` from `branding.primary_color`, so the banner follows it with no new mechanism. |
| Layout | Absolutely positioned, behind the text, `pointer-events: none` | Takes **no** flow space. These pages carry the F141/F161/F166 CLS work; nothing here may move content. The art arrives late (settings read + image fetch), so it fades in from opacity 0. |
| Subscriptions subtitle | **Wraps to two lines** (three at tablet width) clear of the art, via the opt-in `.page-header--wrap-sub` | **Rick, 2026-10-01.** Its ~115-character subtitle would otherwise run under the art and across the slash. **Opt-in, not global:** My List and This Week rewrite their subtitles after load, and a width cap on text that changes length would re-wrap and shift the page. |
| Tablet (641-900px) | Art narrows to 40% (`--banner-w`) | Leaves room for This Week's data-driven subtitle without capping it. |
| Phone (≤640px) | Behind the title block, 72% wide, dimmed to 0.5, **no bolt**, soft halo on the subtitle | A real 393px screenshot showed the original slash cutting through the title; the same reasoning keeps the bolt off a phone. |
| Print | **Hidden in all print output** (`@media print { .brand-banner { display: none !important } }` in the shared CSS) | **Rick, 2026-10-01.** My List's print rules hide only the subtitle, not the header, so the banner would have printed as a dark fading image on white paper. Global, so any later page is covered too. |
| One module owns the contract | `PageBanner` in `app.js` (shape, URL rule, tier rule, render) | The pages (readers) and `settings.html` (writer + preview) must not disagree about "default": that is exactly the `CatalogFilters` bug. Settings holds no second copy. |
| Read | `.maybeSingle()`, not `Settings.get()` | `get()` uses `.single()`, which answers HTTP 406 for no row. A tenant that never saved a banner is the normal case, so it would log a failed request on every page load. |
| Security | `imageUrl` goes to an `<img src>` only, must be `https:`, ≤ 2,048 chars | Never CSS or `innerHTML`; `http:` and `javascript:` are rejected on read and on write. |

## 3. Files

| File | Change |
|---|---|
| `assets/banner-v3.webp` | **The default art** (§ 9, re-encoded in § 11): 1280 × 278, 14 KB, the redesigned scene fitted to the art slot. **`-v3` is load-bearing** (immutable for a year): re-exporting REQUIRES `-v4` and updating `PageBanner.DEFAULT_SRC`, the four preload links and the `_headers` line together. `banner-v2.webp` (19 KB) existed on staging only and was deleted. |
| `assets/banner-v1.webp` | The first cut (1100 × 256, 11 KB, a tight waist-up crop). **No longer referenced**; kept in the repo and `_headers` only because browsers may hold it for a year. Safe to delete later. |
| `_headers` | `/assets/banner-v1.webp` and `/assets/banner-v3.webp` in the immutable group. |
| `style.css` | `.page-header--banner`, `.brand-banner`, `--banner-w`, `.page-header--wrap-sub`, plus tablet / phone / reduced-motion / **print** rules. Shared, because the Settings preview reuses the real classes. |
| `app.js` | `PageBanner` (`KEY`, `defaults`, `cleanUrl`, `load`, `parse`, `resolve`, `mount`, **`show`**, `test`). **`app.js` carries `merge=ours`**, see § 5. |
| `catalog.html`, `mylist.html`, `arrivals.html`, `subscriptions.html` | Header gets the class and an empty `#page-banner` host; `<link rel="preload" as="image">` for the default art in the head; **one `PageBanner.show(host)` call as the first line of the page's init** (see § 5). Subscriptions also gets `page-header--wrap-sub`. |
| `settings.html` | Branding ▸ Page banner panel, live preview, own Save/Discard; rail item "Branding" is a link (was "Soon"). |

The nav and footer blocks are untouched, so the seven-page sync set is unaffected.

## 4. Verification (staging backend)

`playwright/page-banner-verify.mjs` (local-only, `f149-maintenance-verify.mjs` convention; set
`BASE_URL=https://staging.pulllist.pages.dev` to test the **deployed** bytes instead of the working
tree). Throwaway paid admin (founding tenant), free admin (`demoshop`) and a non-admin customer:

- stored `default` / `off` / `custom` / dead URL / malformed JSON / unknown mode / `http:` /
  `javascript:` all resolve as § 2 says; the free tenant never shows a stored custom image;
- Settings: nothing is written until Save; empty, malformed, `http:` and dead addresses are refused; a
  good address previews and saves; the pages then show exactly what Settings saved; Discard works;
- tenant isolation: a free-tenant save leaves the paid tenant's row untouched (read by service role);
- **each of the four pages, as a customer, at 1350 / 700 / 393 px:** art shown, absolutely positioned
  behind the text, header height and the next block's position **identical with the banner removed**,
  Subscriptions subtitle wraps to two lines clear of the art, other subtitles untouched, no horizontal
  overflow added, **hidden in print on every page**, no banner on `admin.html`;
- layout shift, banner on vs off, no shift source inside any header: catalog 0.0185 vs 0.0186, My
  List 0.0119 vs 0.0089 (see the note below), Subscriptions 0.0364 vs 0.0364, This Week 0.0023 vs
  0.0023 (all unthrottled);
- `prefers-reduced-motion` removes the fade (with a control showing it fades otherwise);
- teardown re-read: every throwaway user gone (auth 404), every `page_banner` row removed.

**My List's shift is bimodal and unrelated to the banner.** Its same page shifts land either in one
burst (0.0119) or three (0.0059), and which one happens flips run to run. A 6-run alternating A/B
with the sources named measured **0.0069 with the banner vs 0.0069 without**, and the 0.0119 outcome
occurred in both configurations. The sources are the page's own content (`list-container`, `btn-print`,
`btn-email-list`, nav). The harness therefore compares each side's best run, not the mean.

## 5. Performance: the art became the LCP element, and how that was reduced

**Found by measurement, not assumed.** `lighthouse-auth.mjs` on staging, same throwaway account, banner on
vs off (`page_banner` row set to `off`). On pages with **no cover grid** the 11 KB art is the largest
paint, so its arrival time *is* the page's LCP, and it was arriving at the end of the whole init chain
(auth, tenant, maintenance check, settings read, image fetch). Catalog and This Week were unaffected
because their covers are the LCP anyway.

| Page, banner **on** (off in brackets) | First build | + preload + parallel read | + paint on config (`show`) |
|---|---|---|---|
| My List, mobile | **94**, LCP 2.9 s | 97, LCP 2.4 s | **98**, LCP 2.2 s  *(100, 1.5 s)* |
| My List, desktop | **98**, LCP 1.1 s | 99, LCP 0.8 s | **100**, LCP 0.7 s  *(100, 0.4 s)* |
| Subscriptions, mobile | **96**, LCP 2.5 s | 97, LCP 2.4 s | **98**, LCP 2.1 s  *(99, 1.4 s)* |

What changed, in order:
1. `<link rel="preload" as="image">` for the default art, so the fetch starts at HTML parse.
2. The settings read starts at the top of each page's init, in parallel with auth and tenant resolution.
3. `PageBanner.show()` paints `default` and `off` the moment the read returns: they need **no tenant**
   (`resolve()` consults `Tier` only for `custom`). `custom` is the paid tier's and still waits for the
   tenant, and if the tenant never resolves (~12 s) it shows **nothing**, because a null tenant would read
   as free and paint the platform art on a store that chose its own.

**Residual, stated plainly:** about **+0.7 s mobile LCP** (1-2 score points) on My List and Subscriptions
remains. It is the floor of "read a setting, then fetch and paint an image". Going further would mean
caching the last-known decision in `localStorage` for first paint, which adds a stale-config and
cross-user hazard for a decorative element; not done. These are cold-cache lab numbers; a returning
visitor has the art in the immutable cache.

**Not caused by this work:** Subscriptions desktop scores **78-79 with the banner on AND off** (CLS 0.512,
identical both ways). It is the F141 Pattern B family, measured here on a brand-new empty account
(F141's own caveat: an empty account is not representative). Not investigated, not filed.

## 6. Honest limits / when promoting

- **Chromium only.** Not WebKit, not a real iPhone. The bolt uses `clip-path`, the fade uses
  gradients; both are broadly supported, but unverified on Safari.
- **The harness's CLS is unthrottled**, so it is a floor; the Lighthouse figures in § 5 are the throttled ones.
- **No committed spec asserts the banner** (the Playwright suite is gitignored anyway). The evidence
  is the local harness; a green suite says only that nothing else broke.
- **Admin impersonation on Subscriptions:** the page replaces its long subtitle with a short one, so
  its header shrinks a line after load. Staff-only, and it is the price of the two-line wrap.
- **Promotion touches `app.js`**, which has `merge=ours`. `/promote-prod` step 2 must assert the merge
  RESULT for `app.js` (the driver has dropped it three times). A full merge also needs
  `assets/banner-v3.webp` and the `_headers` lines to travel with it.
- No production `app_settings` row is needed: absent means default art.

## 7. The header as a card (added after Rick's review, 2026-10-01)

**The ask:** *"The header that has the Monthly Catalog title is not defined from the background. Please use
the newsletter to incorporate contrasting colors."* The header sat on the same `#0f0f0f` as the page with
only a hairline under it, so nothing separated it.

**The recipe**, read from the weekly newsletter's header band (`mrcyberrick.us/weekly-pull-feed/newsletter.html`),
which already uses this app's tokens:

| Newsletter | Token | On `.page-header--banner` |
|---|---|---|
| page `#0f0f0f` | `--bg` | unchanged |
| header band `#222222` | `--bg-elevated` | the header's background |
| `1px solid #2e2e2e` | `--border` | the header's edge (was a bottom hairline only) |
| `border-radius: 8px` | `--radius-lg` | corners; `overflow: hidden` clips the art to them |
| `box-shadow: 0 4px 24px rgba(0,0,0,.5)` | `--shadow` | the lift |

**What follows from it:**
- **The art fades into the band colour** (`rgba(34,34,34,...)`), not the page colour, or it would show a dark
  seam against the new background. The phone subtitle halo uses the band colour for the same reason.
- **Scope: all four customer pages**, because the header is one shared component (`.page-header--banner`);
  a card on the catalog alone would make the other three look unfinished. Admin, analytics and settings
  headers are untouched (they do not carry the class). Scoping it back to the catalog is one selector.
- **Print flattens it** (no background, border, shadow or padding). My List prints its title in black, and a
  dark `#222` box behind it would be unreadable wherever "background graphics" is on.
- **Settings preview** drops its own frame styling and inherits the real card, so it matches what customers see.
- Spacing: `padding: 32px 28px 28px` and `margin-top: 20px` on desktop, `26px 20px 22px` and `16px` on a phone.
  The header is about 13 px taller than before; it is static CSS in the HTML, so it cannot shift after paint.

**Verified:** `page-banner-verify.mjs` now **120 checks** (16 new): on each of the four pages the header
computes `rgb(34,34,34)` on the `rgb(15,15,15)` page, a `1px rgb(46,46,46)` edge, 8px corners, the
`0 4px 24px` shadow and `overflow: hidden`; title and subtitle colours are unchanged; and in print emulation
the card is flattened on every page. The existing no-layout, subtitle-clearance, tablet and phone checks still
pass with the 1px border (two geometry tolerances were loosened from 0/1 to 1/2 px for it). Screenshots
inspected at 1350, 700 and 393 px.

## 8. The bolt (added after Rick's review, 2026-10-01)

> **Superseded in placement by § 9 (2026-10-02):** the bolt described here lived on the art's left edge; it is now a small mark
> on the title. The polygon and the accent-colour behaviour carry over. Kept as the record of what shipped in PR #166.

**The ask:** *"Change the red line into a lightning bolt on the header image."*

The red line was one `clip-path` polygon on `.brand-banner::after`. It is now a seven-point bolt polygon in the
same `var(--accent)` (so it still follows `branding.primary_color`), at the same spot where the art begins:

```
polygon(34px 0, 60px 0, 45px 42%, 64px 42%, 20px 100%, 35px 57%, 14px 57%)
```

- **Still CSS only:** no image, no request, nothing for the store to upload.
- **x in px, y in %**, so it stretches with the header's height (one subtitle line or two) without distorting
  its width.
- **The art loses its slanted cut.** Its left edge is hidden by the fade into the header band, so the slash had
  been the only thing showing it; the bolt marks the start of the art instead.
- **Hidden on a phone**, as the slash was: there the art sits behind the title, and a bright shape would land on
  the words.
- Chosen from three candidates rendered in an isolated mock (a thin classic bolt, a larger and steeper one, and the
  steeper one with a glow). The steeper one reads best; the glow was not visible enough to justify extra markup.

**Verified:** `page-banner-verify.mjs` **124 checks**: on all four pages the accent mark is a 7-point polygon and the
art itself is unclipped. Layout shift with and without the banner is unchanged (catalog 0.0182 vs 0.0183, My List
0.0058 vs 0.0058, Subscriptions 0.0363 vs 0.0363, This Week 0.0022 vs 0.0022).

**One harness comparison was loosened, with the evidence.** My List's own shifts land either in one burst (about
0.0115) or in three (about 0.0057), and which one happens flips from run to run **in both banner states**. A
6-run alternating A/B on the deployed card build measured **0.0067 with the banner vs 0.0067 without**, and the
higher outcome occurred once in each. The check therefore asks that the best banner-on run not exceed the *worst*
banner-off run (3 runs each), rather than the best-versus-best form that could fail on a coin flip.

## 9. Reframed art, a bolt on the title, a warmer subtitle (2026-10-02)

> **Item 1 below (the bolt on the title) was superseded the same day by § 10**: the bolt is gone and the accent is now a hard
> offset shadow on the title. Items 2 (the `banner-v2.webp` art) and 3 (the subtitle) stand.

**The ask.** Rick reviewed a redesigned default banner (a mockup with the title, bolt and subtitle baked into one
image) and agreed three changes, keeping the concept: (1) a smaller bolt that supports the branding instead of
competing with the title, (2) the superhero reframed with a little more space, (3) a more inviting subtitle.

**Why the mockup was adapted, not dropped in.** Used as-is it would put its baked "Monthly Catalog" on My List,
Subscriptions and This Week and collide with each page's real title; its navy left side (`#0e1820`) clashes with the
app's neutral `#222` band; its bolt was a fixed darker red rather than the store's accent; and at 5.4:1 it does not
match our header (about 8.8:1 on desktop), so `object-fit: cover` would crop the figure's head or feet.

**What was built (header height unchanged: 141 / 141 / 164 / 141 px, asserted):**
1. **The bolt is a brand mark on the title** (`h1::after`), not a shape on the art. It sits right after the title text,
   sized in `em` (`.44em × 1.28em`) so it scales with the title on every page and width, in `var(--accent)` so it still
   follows `branding.primary_color`. The `h1` is `display: table` so it shrink-wraps to its text (the bolt can follow the
   last line) while a long title, such as an impersonated customer's name, still wraps at the card's width; the bolt is
   absolutely positioned so it adds no height. Visible on a phone (it is part of the title now, not of the art); hidden in
   print. The old rule on the art (`.brand-banner::after`) and the art's slanted cut are gone.
2. **`assets/banner-v2.webp`** (re-encoded smaller as `banner-v3.webp` in § 11; v2 is deleted): the mockup's scene only (right of x≈900, no text, no bolt), scaled to the art slot's
   height so the whole figure, the skyline and the sun show, with the empty left side blended row-by-row into the band
   colour (`#222`), so there is no seam. 1280 × 278, 19 KB. Where the slot is narrower (tablet, phone) `object-fit: cover`
   anchored right keeps the figure.
3. **The catalog subtitle reads "October 2026 · Browse and reserve your comics"**, replacing "Catalog for 2026-10 — browse
   and reserve items". **It is written in three places in `catalog.html`** (the initial load and both branches of
   `updateReservedStat()`), so all three go through one `monthLabelOf()`; changing only the first would have let the first
   reserve click revert the header. The admin impersonation line gets the same month format ("October 2026 · Managing
   <name>"). The Settings preview reads the same way. **My List, Subscriptions and This Week keep their own subtitles.**

**Verified:** `page-banner-verify.mjs` **141 checks** on the working tree (new: the bolt is a 7-point polygon on the title,
absolutely positioned, in the accent colour; the art carries no accent shape; the room after the last letter is `.86em`;
header height equals the previous build's on all four pages; the catalog subtitle matches `Month YYYY · Browse and reserve
your comics`; the title and its bolt stay inside the card on a phone; the bolt is hidden in print). Screenshots inspected.

**Staging evidence for § 9:** full Playwright suite **151 passed** (24.0 min) on the deployed build; `page-banner-verify.mjs` **141/141** against the deployed bytes.

**Performance, measured on staging (Lighthouse, authenticated, cold cache), against the build before this change:**

| Page | Before (banner v1) | After (banner v2) |
|---|---|---|
| My List, mobile | 98, LCP 2.2 s | 98 / 97 / 98, LCP 2.3-2.4 s |
| My List, desktop | 100, LCP 0.7 s | 100, LCP 0.7 s |
| Subscriptions, mobile | 98, LCP 2.1 s | **96, LCP 2.5 s, three runs in a row** |
| Subscriptions, desktop | 79 (CLS 0.512, pre-existing) | 79 (CLS 0.513, unchanged) |

**Stated plainly:** My List is unchanged. **Subscriptions mobile is about 2 points and 0.4 s of LCP worse, and it reproduced
three times**, so it is not a one-off. The art grew by 7.5 KB (11 KB to 19 KB), which is only about 40 ms on Lighthouse's
simulated connection, so the size alone does not explain 0.4 s; lab conditions on a busy machine (its TBT also read
100-120 ms in the repeats against 0-40 ms before) may account for part of it. **It was not isolated**: that needs the old
and new art measured in the same window, and the old art was not redeployed for it. If the 2 points matter, the cheapest
lever is re-encoding `banner-v2.webp` at a lower quality (about 13 KB at q60) as `banner-v3.webp`. **Done in § 11, which measured how much of the gap it recovers.**

## 10. The title accent: from a bolt to a hard red offset shadow (2026-10-02)

**The path, in order** (each step was seen on staging or in an isolated mock before the next was chosen):
1. A red slash on the art's edge, then a full-height bolt there (shipped to production in PR #166).
2. A small bolt on the title (§ 9, staging).
3. Rick pasted a recommendation to remove the bolt and put a subtle red shadow on the title instead (fewer competing
   elements, the red of the cape echoed in the type). Three treatments were rendered in an isolated mock against the real
   header CSS: a soft glow, a hard offset, and a glow with a thin red edge.
4. **Rick chose the soft glow**; it was built and deployed to staging (suite 151 passed).
5. **After seeing it live he chose the hard offset instead.** This is the final state.

**What is there now:** the title (`.page-header--banner h1`) carries `text-shadow: 2px 2px 0` at 55% of the accent: a crisp,
zero-blur offset, the look of a comic title printed with a misregistered spot-colour plate. It applies to all four customer
pages and the Settings preview.
- **It follows the store's brand colour.** A `color-mix(in srgb, var(--accent) 55%, transparent)` version sits inside
  `@supports`, with the plain platform red as the default. **They are separate rules on purpose:** a declaration containing
  `var()` is accepted at parse time even where `color-mix()` is unsupported, and then computes to `none` instead of falling back.
- **A fixed 2px at every size** (desktop and phone), the look chosen from the mock. Whole pixels keep the edge sharp; why an
  em-based offset would soften on the smaller phone title is reasoned, not measured.
- **Print: `text-shadow: none`**, so a red offset does not sit behind printed black text.
- **No layout:** a shadow takes no space, so header heights are unchanged (141 / 141 / 164 / 141 px, asserted).
- **The bolt is gone entirely:** the `h1` is an ordinary block again (no `display: table`, no `padding-right`, no `::after`).

**One thing to know for a store with its own accent:** the shadow takes that colour. A very dark accent will barely show on the
`#222` band, and a very light one will be bright; the title text itself stays cream either way.

**Verified:** `page-banner-verify.mjs` **145 checks** on the working tree and on the deployed staging bytes, including: 2px
right, 2px down, **zero blur**, about 55% strength; the shadow **follows a changed `--accent`** (set to `#1d4ed8`, read back as
that blue); no bolt scaffolding remains on the title; the art carries no accent shape; print has no shadow; the title stays
inside the card on a phone. Full Playwright suite **151 passed** (22.9 min) on the deployed build. Screenshots inspected at
1350, 700 and 393 px.

**A process note worth keeping:** the first attempt at the glow patch searched for its end marker from the start of the file,
matched an earlier identical `@media` line, and duplicated about 130 lines of CSS. It was caught because the diff said
`+143` for a change that should have been about `+20`, and the file was restored from git before it was committed.

## 11. The default art re-encoded smaller: `banner-v3.webp` (2026-10-02)

Rick's request, after § 9's note that Subscriptions on a phone had lost about 2 points and 0.4 s of LCP: "deploy smaller banner".

**What was done.** `banner-v3.webp` is **14.2 KB, down from 19.2 KB (-26%)**, same 1280 × 278 geometry. It was re-fitted **from the
lossless scene source** (the same crop, resize and row-by-row blend into `#222` as § 9) at WebP quality 50, **not** by
re-compressing `banner-v2.webp`, which would have stacked a second lossy pass on a first. Quality was chosen from a measured
ladder on the same source: 60 = 16.1 KB, 55 = 15.1 KB, 50 = 14.2 KB, 45 = 13.5 KB, 40 = 12.3 KB. **The plan's "about 13 KB at q60"
was wrong for this source** (q60 is 16 KB); that figure came from re-compressing v2 and does not hold for the lossless route.
Judged by eye on a side-by-side of the figure at 1:1 pixels (the art is shown at 640 CSS px from a 1280 px file, so 1:1 is
a 2x screen), v2, q55, q50 and q45 are hard to tell apart; **PSNR against the lossless fit is 36.2 dB for v2 and 34.7 dB for
the chosen q50**, i.e. a small measured loss, stated rather than hidden. q50 was picked as the last step before the
ladder's returns shrink (q45 saves 0.7 KB more).

**What moved together** (the `-vN` rule): `PageBanner.DEFAULT_SRC` in `app.js` (and the comment above it), the
`rel="preload"` link in all four customer pages, and the `_headers` immutable entry. `banner-v2.webp` was **deleted** (it was
never promoted, so production never held it); `banner-v1.webp` stays because production still references it. After the deploy,
`banner-v2` appears nowhere in `app.js`, the four pages or `_headers` (0 hits), but **Cloudflare's edge still served the orphaned
v2 file (19,212 bytes) for a while**, the same behaviour the 2026-08-24 performance sweep recorded for a deleted favicon: harmless,
since nothing links it.

**Measured, Lighthouse on staging, authenticated, cold cache, Subscriptions mobile, three runs on the new art:**

| Build | Performance | LCP |
|---|---|---|
| banner v1 (11 KB), before § 9 | 98 | 2.1 s |
| banner v2 (19 KB), § 9 | 96 (three runs) | 2.50 s |
| **banner v3 (14 KB), this section** | **97, 97, 97** | **2.39, 2.41, 2.41 s** |

**Stated plainly:** it recovered **about 1 point and 0.1 s, not the whole gap.** That is consistent with the size
arithmetic in § 9 (a few KB is tens of milliseconds on Lighthouse's simulated connection), and it means **the rest of the
+0.3 s against v1 is not explained by file size** and was not isolated. TBT read 0 / 0 / 59 ms across the three runs against 42
for the v2 reference, i.e. the lab noise is as large as some of the differences, so read the LCP column and treat the last
decimal as noise. **My List and Subscriptions desktop were NOT re-measured for this change**; only the one metric that
had regressed was re-run. Going further would mean a smaller image still (a narrower file loses sharpness on a 2x screen) or
caching the banner decision in `localStorage` (rejected in § 5 for its stale-config and cross-user hazard); neither was done.

**Verified:** `node --check` clean on `app.js` and the inline script of all four pages; `page-banner-verify.mjs` **145/145
against the deployed staging bytes** (it now asserts `assets/banner-v3.webp`, `1280px wide, opacity 1`); the served image is
14,240 bytes with `Cache-Control: public, max-age=31536000, immutable`; full Playwright suite **151 passed, 0 failed
(22.4 min)**, exit 0, from the log's own summary line (a background launcher's "completed, exit 0" notice arrived within
seconds of the start and was the launcher shell, not the run); teardown restored `catalog_filters` (167 bytes), deleted its
synthetic tenant (re-read: gone), and left Rick's `page_banner` row on the founding tenant in place with its value unchanged
(`updated_at` moves each time the harness restores it).
