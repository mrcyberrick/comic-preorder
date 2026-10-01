# Catalog header banner — brandable art beside the "Monthly Catalog" title

**STATUS:** IN PROGRESS | staging=BUILT 2026-10-01, awaiting Rick's review | prod=NOT PROMOTED | findings=— (feature build, not a defect; **F169 is the next free finding ID**)

**Last verified against live: 2026-10-01** (staging; production untouched).

## 1. What this is

The catalog page's header (`Monthly Catalog` + subtitle) leaves the right half of its row empty. This
fills it with a banner image, and lets the store change it.

- **Default art** is cut from the apex page's hero (`assets/hero-v2.webp`: the caped figure on the
  skyline at sunset), so the catalog reads as the same product as pulllist.app.
- **Custom branding** follows the project's tier rule (`docs/f72-multi-tenant-branding.md` § 0.1): a
  *free* tenant gets platform defaults, a *paid* (`plan = 'pro'`) tenant can use its own image.
- **Settings ▸ Branding ▸ Catalog banner** is where an admin chooses: Default artwork / Custom image
  / No banner, with a live preview and its own Save.

## 2. Design decisions (and why)

| Decision | Choice | Why |
|---|---|---|
| Where it is stored | `app_settings` key `catalog_banner`, JSON text `{ v, mode, imageUrl }` | The only admin-writable per-tenant store. `tenants.branding` is operator-only (no admin write path), and the ask was "changeable in Settings". **No schema, RLS or Edge Function change**: `app_settings` has no key allowlist and its admin write policies already apply. |
| Absent row means | The default art (**banner on**) | So the view is visible without anyone configuring it. The alternative is "ships dark" like `branding.promo_banner`. **Open question for Rick**, see § 6. |
| Custom image tier | Paid only; a stored `custom` on a free tenant resolves to the **platform** art | Same direction as `Tier`: the free render is always the safe one. Free tenants may still pick *No banner*. |
| Custom image source | An `https://` address the admin hosts | There is no image storage in this project (no Supabase Storage). The address is checked to actually load **before** it is saved. |
| A custom image that will not load | Shows **nothing**, never the platform art | Platform art on a store that chose its own would be the wrong shop's identity on its page. |
| Accent colour | The slash on the cut edge uses `var(--accent)` | `Branding.apply()` already overrides `--accent` from `branding.primary_color`, so the banner follows it with no new mechanism. |
| Layout | Absolutely positioned, behind the text, `pointer-events: none` | Takes **no** flow space. The catalog carries the F141 CLS work; nothing here may move the grid. Art fades in (it arrives after a settings read and an image fetch). |
| Phone | Behind the title block, 72% wide, dimmed to 0.5, **no slash**, soft halo on the subtitle | A real 393px screenshot showed the slash cutting through the title and subtitle. |
| One module owns the contract | `CatalogBanner` in `app.js` (shape, URL rule, tier rule, render) | `catalog.html` (reader) and `settings.html` (writer + preview) must not disagree about "default": that is exactly the `CatalogFilters` bug. Settings holds no second copy. |
| Read | `.maybeSingle()`, not `Settings.get()` | `get()` uses `.single()`, which answers HTTP 406 for no row. A tenant that never saved a banner is the normal case, so it would log a failed request on every catalog load. |
| Security | `imageUrl` goes to an `<img src>` only, must be `https:`, ≤ 2,048 chars | Never CSS or `innerHTML`; `http:` and `javascript:` are rejected on read and on write. |

## 3. Files

| File | Change |
|---|---|
| `assets/banner-v1.webp` | New. 1100 × 256, 11 KB, cut from the hero. **`-v1` is load-bearing** (immutable for a year): re-exporting REQUIRES `-v2` and updating `CatalogBanner.DEFAULT_SRC`. |
| `_headers` | `/assets/banner-v1.webp` added to the immutable group. |
| `style.css` | `.page-header--banner`, `.brand-banner` (+ phone and reduced-motion rules). Shared, because the Settings preview reuses the real classes. |
| `app.js` | `CatalogBanner` (`KEY`, `defaults`, `cleanUrl`, `load`, `parse`, `resolve`, `mount`, `test`). **`app.js` carries `merge=ours`**, see § 5. |
| `catalog.html` | Header gets the class and an empty `#catalog-banner` host; one fire-and-forget `CatalogBanner.load().then(mount)`. |
| `settings.html` | Branding panel, live preview, own Save/Discard; rail item "Branding" is now a link (was "Soon"). |

The nav and footer blocks are untouched, so the seven-page sync set is unaffected.

## 4. Verification (staging backend, working tree served locally)

`playwright/catalog-banner-verify.mjs` (local-only, `f149-maintenance-verify.mjs` convention): **51
checks, all pass**, Chromium only. A paid admin (founding tenant) and a free admin (`demoshop`):

- default / off / custom / dead URL / malformed JSON / unknown mode / `http:` / `javascript:` all
  resolve as § 2 says, on the catalog page;
- the free tenant never shows a stored custom image;
- Settings: nothing is written until Save; empty, malformed, `http:` and dead addresses are refused;
  a good address previews and saves; the catalog then shows exactly what Settings saved; Discard works;
- tenant isolation: a free-tenant save leaves the paid tenant's row untouched (read by service role);
- no layout: header height and grid top identical with the banner removed; **mean CLS 0.0204 with it vs
  0.0202 without** over 3 runs each, and no layout-shift source is inside the header;
- phone (393) and tablet (700): no overflow added; the subtitle text clears the art at 700;
- `prefers-reduced-motion` removes the fade (with a control showing it fades otherwise);
- teardown re-read: both throwaway admins gone (auth 404), every `catalog_banner` row removed.

## 5. Honest limits / when promoting

- **Chromium only.** Not WebKit, not a real iPhone. The slant uses `clip-path`, the fade uses
  gradients; both are broadly supported, but unverified on Safari.
- **CLS is unthrottled**, so it is a floor, not a Lighthouse figure. Re-run `lighthouse-auth.mjs` on
  staging before promoting; the catalog is LCP-bound and this adds one small image.
- **No committed spec asserts the banner** (the Playwright suite is gitignored anyway). The evidence
  is the local harness; a green suite says only that nothing else broke.
- **Promotion touches `app.js`**, which has `merge=ours`. `/promote-prod` step 2 must assert the merge
  RESULT for `app.js` (the driver has dropped it three times). A full merge also needs
  `assets/banner-v1.webp` and the `_headers` line to travel with it.
- No production `app_settings` row is needed: absent means default art.

## 6. Open questions for Rick

1. **Banner on by default for every tenant, or ship dark** until a tenant opts in? (§ 2 row 2.)
2. **Custom image hosting.** Address-only is the minimum that fits the stack. If paid tenants will
   expect to upload, that needs Supabase Storage (new bucket, policies): a separate decision.
3. **Should the same slot offer a second layout** (tagline text over the art)? Not built.
