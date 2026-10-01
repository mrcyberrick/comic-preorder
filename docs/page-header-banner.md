# Page header banner — brandable art beside the title on the four customer pages

**STATUS:** IN PROGRESS | staging=BUILT 2026-10-01 (catalog first, widened to all four customer pages and tuned for LCP the same day), awaiting Rick's review | prod=NOT PROMOTED | findings=— (feature build, not a defect; **F169 is the next free finding ID**)

**Last verified against live: 2026-10-01** (staging; production untouched).

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
| Accent colour | The slash on the cut edge uses `var(--accent)` | `Branding.apply()` already overrides `--accent` from `branding.primary_color`, so the banner follows it with no new mechanism. |
| Layout | Absolutely positioned, behind the text, `pointer-events: none` | Takes **no** flow space. These pages carry the F141/F161/F166 CLS work; nothing here may move content. The art arrives late (settings read + image fetch), so it fades in from opacity 0. |
| Subscriptions subtitle | **Wraps to two lines** (three at tablet width) clear of the art, via the opt-in `.page-header--wrap-sub` | **Rick, 2026-10-01.** Its ~115-character subtitle would otherwise run under the art and across the slash. **Opt-in, not global:** My List and This Week rewrite their subtitles after load, and a width cap on text that changes length would re-wrap and shift the page. |
| Tablet (641-900px) | Art narrows to 40% (`--banner-w`) | Leaves room for This Week's data-driven subtitle without capping it. |
| Phone (≤640px) | Behind the title block, 72% wide, dimmed to 0.5, **no slash**, soft halo on the subtitle | A real 393px screenshot showed the slash cutting through the title. |
| Print | **Hidden in all print output** (`@media print { .brand-banner { display: none !important } }` in the shared CSS) | **Rick, 2026-10-01.** My List's print rules hide only the subtitle, not the header, so the banner would have printed as a dark fading image on white paper. Global, so any later page is covered too. |
| One module owns the contract | `PageBanner` in `app.js` (shape, URL rule, tier rule, render) | The pages (readers) and `settings.html` (writer + preview) must not disagree about "default": that is exactly the `CatalogFilters` bug. Settings holds no second copy. |
| Read | `.maybeSingle()`, not `Settings.get()` | `get()` uses `.single()`, which answers HTTP 406 for no row. A tenant that never saved a banner is the normal case, so it would log a failed request on every page load. |
| Security | `imageUrl` goes to an `<img src>` only, must be `https:`, ≤ 2,048 chars | Never CSS or `innerHTML`; `http:` and `javascript:` are rejected on read and on write. |

## 3. Files

| File | Change |
|---|---|
| `assets/banner-v1.webp` | New. 1100 × 256, 11 KB, cut from the hero. **`-v1` is load-bearing** (immutable for a year): re-exporting REQUIRES `-v2` and updating `PageBanner.DEFAULT_SRC`. |
| `_headers` | `/assets/banner-v1.webp` added to the immutable group. |
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

- **Chromium only.** Not WebKit, not a real iPhone. The slant uses `clip-path`, the fade uses
  gradients; both are broadly supported, but unverified on Safari.
- **The harness's CLS is unthrottled**, so it is a floor; the Lighthouse figures in § 5 are the throttled ones.
- **No committed spec asserts the banner** (the Playwright suite is gitignored anyway). The evidence
  is the local harness; a green suite says only that nothing else broke.
- **Admin impersonation on Subscriptions:** the page replaces its long subtitle with a short one, so
  its header shrinks a line after load. Staff-only, and it is the price of the two-line wrap.
- **Promotion touches `app.js`**, which has `merge=ours`. `/promote-prod` step 2 must assert the merge
  RESULT for `app.js` (the driver has dropped it three times). A full merge also needs
  `assets/banner-v1.webp` and the `_headers` line to travel with it.
- No production `app_settings` row is needed: absent means default art.
