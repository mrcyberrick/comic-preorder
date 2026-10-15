# Subscribe promo banner: editable in Settings, tracked in Analytics

**STATUS:** IN PROGRESS · staging: 2026-10-15 (code `b464471` S1, `7bd1a5d` S2, `daed27d` S3, `5b9bba0` S4; docs `3c54071`; follow-up fix `47946d9` after Rick's report, § 8.4; built and verified, § 8) · prod: — (NOT promoted; needs Rick's explicit `/promote-prod`) · PR: — · findings: — (feature build, not a defect; no finding ID consumed)

Plan written 2026-10-15 (planning session, Rick's request). Builds on `docs/subscription-promotion.md`
(the banner itself, live on both environments since 2026-07-17), whose § 3 OUT list deferred exactly
these two things: "Admin UI for editing banner content (v1 is SQL-only)" and "Banner/prompt
impression logging". This plan brings both in.

**Last verified against live: 2026-10-15** (anon `resolve_tenant_by_slug` reads, both environments; see § 1).

---

## 0. What Rick asked for

1. The catalog's closable banner ("Subscribe to a series and never miss an issue — auto-reserved
   every month. Learn more") becomes a setting on the **Settings** page.
2. An admin can **edit** it and **reset** it.
3. **Analytics** shows when customers close it.

**Decisions taken in planning (Rick, 2026-10-15):**

- **D1, Reset = two buttons.** "Restore default text" puts the shipped wording and link back.
  "Show it again to everyone" brings the banner back for customers who already closed it.
- **D2, tracking = shown AND closed.** One `shown` event per customer per campaign plus each close,
  so Analytics can show a close rate and how many of those who saw it went on to subscribe.

**Decisions taken by this plan (Rick may overrule at execution start):**

- **D3, storage moves to `app_settings.promo_banner`**, the same table and save path the Page banner
  uses (`Settings.set`, `admins update tenant app_settings`). `tenants.branding.promo_banner` stays
  as a **read fallback** so nothing changes on deploy and no SQL is needed. Reasons in § 2.1.
- **D4, the link target is a dropdown of app pages**, not a free URL. An admin-editable `href` would
  need URL validation (a `javascript:` link is the obvious hazard); a fixed list removes that.
- **D5, available on both tiers.** It is the shop's own message, not platform identity, so it is not
  `Tier`-gated (unlike the custom Page banner image).
- **D6, no "Learn more" click tracking, no subscribe attribution.** Not asked for. "Subscribed after
  seeing it" (§ 3.4) is the approximation. Easy follow-up if wanted.

---

## 1. Current state (measured 2026-10-15)

**Config** — `tenants.branding.promo_banner`, read through `TenantContext.current().branding`
(no fetch of its own). Live values, read with the anon `resolve_tenant_by_slug` RPC:

| Env | Tenant | `promo_banner` |
|---|---|---|
| staging | `raysandjudys` | `{id:"sub-promo-1", enabled:true, text:"Subscribe to a series and never miss an issue — auto-reserved every month.", link_text:"Learn more", link_href:"subscriptions.html"}` |
| prod | `rjbookstop` | identical to staging |
| prod | `comicstore` | absent (banner off) |

**Render** — `renderPromoBanner()`, `catalog.html:834-881` (re-check the range; it moves):

- returns early when impersonating, when config is absent / `enabled:false` / missing `id` or `text`,
  and when the customer has **any** subscription (`mySubscriptions.size > 0`);
- dismissal is `localStorage` key `pulllist_promo_dismissed_${slug}_${id}` (per browser), so a new
  `id` re-shows it — that is the mechanism "Show it again to everyone" will use;
- text and link are set with `textContent` (no HTML injection surface). Keep it that way.
- Called after `mySubscriptions` loads. **The Top picks rail stays `visibility:hidden` until the
  promo banner has rendered** (`docs/catalog-top-picks-redesign.md` § 9.x, CLS fix). Any new read
  this plan adds must not delay that moment more than the subscriptions load already does.

**Events** — `UsageEvents._log()` (`app.js:1128`) inserts `{user_id, event_type, metadata,
tenant_id}`; skips while impersonating; `event_type` is free text (no CHECK). Analytics loads every
`usage_events` row in the last 90 days (`analytics.html:~642-675`) and `countByType()`
(`analytics.html:~727`) **ignores types it does not list**, so new types do not disturb existing
counts. The 90-day purge (F90) applies: there is no lifetime count.

**Settings** — `settings.html` has a **Branding** section with one panel, **Page banner**
(`#banner-panel`, `settings.html:~484-550`, logic `~992-1140`), with its own draft, preview and Save
writing `app_settings.page_banner` through `PageBanner` in `app.js`. That is the template.

---

## 2. Design

### 2.1 Storage (D3)

New `app_settings` row, key `promo_banner`, value JSON:

```json
{ "v": 1, "enabled": true, "id": "sub-promo-1",
  "text": "Subscribe to a series and never miss an issue — auto-reserved every month.",
  "link_text": "Learn more", "link_target": "subscriptions" }
```

Resolution order in the client: **`app_settings.promo_banner` row → else `tenants.branding.promo_banner`
(legacy; map its `link_href` to a `link_target`) → else nothing.** So:

- On deploy nothing changes for either store (no row exists yet, the branding value applies).
- The first Save from Settings writes the row, which then wins. The branding key stays in place
  untouched (do NOT delete it in this work; it is the rollback).
- Spec 09 (`09-promo-banner.spec.ts`) seeds `branding` on a synthetic tenant with no `app_settings`
  row, so it keeps exercising the fallback path and must stay green unchanged.

Why not keep writing `tenants.branding`: the tenants UPDATE policy is row-level
(`admins update own tenant`), and a Settings save there would rewrite a jsonb that also carries
`primary_color` / `logo_url` (a merge bug away from wiping a tenant's branding). `app_settings` is a
dedicated key, its admin write path is already exercised by two Settings panels, and it has an
`updated_at` the panel can show.

**No SQL migration.** `app_settings` already exists with tenant-scoped admin INSERT/UPDATE and
authenticated SELECT. Confirm both policies by reading `docs/technical-reference.md` (§ app_settings,
~line 1840) before building; if an INSERT policy for admins is missing, stop and ask.

### 2.2 Shared helper in `app.js`: `PromoBanner`

Mirror `PageBanner`'s shape so the catalog, Settings preview and Analytics cannot drift:

- `KEY = 'promo_banner'`, `DEFAULTS` (the shipped text, `Learn more`, `subscriptions`, `enabled:true`).
- `TARGETS` — fixed map `{ subscriptions: 'subscriptions.html', catalog: 'catalog.html',
  mylist: 'mylist.html', arrivals: 'arrivals.html' }`. Unknown target → no link.
- `parse(raw)` — tolerant: bad JSON / wrong shape → `null`; trims text; caps `text` at 200 and
  `link_text` at 40 characters.
- `fromLegacy(branding)` — maps the old `{link_href}` to a target (`subscriptions.html` →
  `subscriptions`; anything else → no link).
- `async load(tenant)` — reads the row (`maybeSingle()`, not `Settings.get()`, whose `.single()`
  logs a 406 on a missing row), falls back to `fromLegacy(tenant.branding?.promo_banner)`. Never
  throws; on a read error falls back to legacy.
- `mount(host, cfg, { onDismiss, preview })` — builds the existing DOM (same classes, same
  `textContent` rule) so the Settings preview is the real thing.
- `newCampaignId()` — `sub-promo-<yyyymmdd-hhmmss>` (local time).
- Events: `UsageEvents.promoBannerShown(userId, id)` and `promoBannerDismissed(userId, id)` →
  event types **`promo_banner_shown`** / **`promo_banner_dismissed`**, metadata `{ banner_id }`.
  Add them to `UsageEvents` beside `subscribe`; do not change `_log()`.

### 2.3 Catalog (`catalog.html`)

- Start `PromoBanner.load(tenant)` **in parallel** with the subscriptions load (kick off the promise
  early, await it where `renderPromoBanner()` is called now). It must not add a serial round trip
  before the rail is revealed.
- `renderPromoBanner()` keeps every existing gate (impersonation, enabled, already subscribed,
  dismissed key) and renders through `PromoBanner.mount()`.
- **`shown`**: log once per customer per campaign per browser — guard with localStorage key
  `pulllist_promo_shown_${slug}_${id}`; set it after logging. Wrap every storage access in
  try/catch; if storage throws, do not log (under-count rather than log every page load, the
  `UsageEvents.visit()` rule).
- **`dismissed`**: log on the close click, then keep the existing dismiss behaviour.
- Admins viewing their own catalog can see it and would log events; Analytics excludes admin
  user ids (§ 3.4), the catalog does not need a special case.

### 2.4 Settings (`settings.html`) — new panel under **Branding**, below Page banner

`<section class="set-panel" id="promo-panel">`, heading **"Subscribe banner"**, one-line help:
*"The closable message at the top of the Catalog. Customers who already subscribe to a series never
see it."*

Controls (a draft, applied by one **Save**, like the Page banner panel):

1. **On / Off** toggle (`enabled`).
2. **Message** — textarea, 200-character limit with a live counter.
3. **Link label** — text input, 40 characters (default "Learn more"); empty label = no link.
4. **Link goes to** — select: Subscriptions / Catalog / My List / This Week.
5. **Live preview** — `PromoBanner.mount()` into a preview host, with the close button inert.
6. **Restore default text** — fills message, label and target from `DEFAULTS` into the draft (does
   not save, does not touch On/Off or the campaign).
7. **Show it again to everyone** — a checkbox, *"Show it again to customers who closed it"*, applied
   on Save by assigning `PromoBanner.newCampaignId()`. Unticked, an edit keeps the current `id`, so a
   typo fix does not re-show the banner to everyone. Save asks `confirm()` only when it is ticked.
8. Status line: *"Live campaign started <date> · last saved <date>"* (the date is parsed from the
   id when it is the new format; `sub-promo-1` shows "original campaign").

Save writes `Settings.set('promo_banner', JSON.stringify(cfg))` and reports errors with a toast, the
Page banner panel's pattern. Before the first save the panel shows the legacy branding value (or
defaults-but-Off when there is none, e.g. `comicstore`).

No nav, footer or `#search` change on `settings.html` (the seven-page sync set and the gear rule are
untouched; re-hash the nav block to prove it).

### 2.5 Analytics (`analytics.html`)

A new card **"Subscribe banner"** in the Subscription section (new row beneath "Subscription
Opportunity" / "Customers Needing Attention"), for the **live campaign** (`banner_id` = the current
config's `id`; the config is read with `PromoBanner.load()`):

- **Saw it** — distinct non-admin customers with a `promo_banner_shown` event.
- **Closed it** — distinct non-admin customers with a `promo_banner_dismissed` event, plus
  **close rate** = closed ÷ saw (shown as "12 of 30 · 40%").
- **Subscribed after seeing it** — distinct customers whose first `subscribe` event is later than
  their first `promo_banner_shown` for this campaign.
- **Recent closes** — the last 10 closes: customer name (via `profileName()`) and local date/time.
  This is the "when" Rick asked for.
- **Off / no data states:** banner Off → "The banner is off (Settings → Branding)". No events yet →
  "No customer has seen this campaign yet. Counts start from <deploy date>."
- Footnote: per browser, so one customer on two devices counts once (distinct users) but may see it
  twice; only customers with no subscription are shown it; 90-day window.

Add a definition to the page's definitions list (`analytics.html:~480-550`), source
"usage_events (promo_banner_shown / promo_banner_dismissed) + subscribe".

**Check before building:** grep `analytics.html` for any metric that counts "any event" per user
(active users, habit, retention, cohorts). The new events fire on a catalog page load that already
logs `catalog_view`, so they should not inflate those, but confirm each by reading it; if one counts
all event types, exclude the two new types there.

---

## 3. Steps

Each step is its own commit on `feature/promo-banner-settings` off `staging`.

- **S0 — Pre-flight.** `/preflight`. Re-read `catalog.html` `renderPromoBanner()` and its call site,
  `settings.html`'s Page banner panel, `app.js` `PageBanner` + `UsageEvents`, `analytics.html`'s
  load + Subscription card. Confirm the `app_settings` policies (§ 2.1). Re-read the live config on
  both environments with the anon RPC (as in § 1) and halt if it changed.
- **S1 — `PromoBanner` + the two `UsageEvents` helpers** in `app.js` (additive only).
- **S2 — Catalog** reads through `PromoBanner.load()` in parallel, renders via `mount()`, logs
  shown/dismissed.
- **S3 — Settings panel.**
- **S4 — Analytics card + definition.**
- **S5 — Verify (§ 4), `/deploy-staging`, update this STATUS + CLAUDE.md.**

---

## 4. Verification gates

Local harness `catalogs/scripts/playwright/promo-banner-settings-verify.mjs` (local-only, the
`f149-maintenance-verify.mjs` convention; password grant + `addInitScript`, not magic links). Run it
against the **deployed** staging bytes after confirming the new bytes are served on the plain URL.
**Snapshot staging's `app_settings.promo_banner` row (probably absent) first and restore it exactly
at teardown**; never leave a row on the founding tenant, and delete every throwaway user (re-read 0).

- **V1 fallback:** no row → catalog renders the legacy branding text exactly as before (byte-equal
  text, link to `subscriptions.html`). Spec 09 green unchanged.
- **V2 edit:** save new text / label / target in Settings → a customer with no subscriptions sees
  it on the catalog; the row's JSON matches; the link resolves to the chosen page.
- **V3 off:** On/Off off → nothing renders; the Top picks rail still reveals.
- **V4 restore default:** after an edit, Restore + Save → text, label, target equal `DEFAULTS`;
  `id` unchanged.
- **V5 show again:** close the banner as a customer → gone on reload; save with the box ticked → it
  reappears for that customer; saved unticked → it stays closed.
- **V6 events:** first catalog load logs exactly one `promo_banner_shown` with the right `banner_id`
  and `tenant_id`; a reload logs none; close logs one `promo_banner_dismissed`; impersonation logs
  none and shows no banner; a subscribed customer sees nothing and logs nothing.
- **V7 analytics:** with seeded events for two throwaway customers (one closed), the card reads
  "1 of 2 · 50%", the recent-closes list names the closer, and the existing tiles' numbers are
  unchanged against a read taken before seeding (except anything that legitimately counts the
  throwaway users' `catalog_view`).
- **V8 safety:** a message containing `<img src=x onerror=alert(1)>` renders as literal text in both
  the catalog and the Settings preview; an over-long message is refused at 200 characters.
- **V9 layout:** catalog layout shift with the banner shown is no worse than before (Lighthouse via
  `lighthouse-auth.mjs`, desktop + mobile, compare to a pre-change run); Settings and Analytics at
  390 px have no horizontal scroll (inspect screenshots).
- **V10 regression:** full suite once, post-push (`npx playwright test --reporter=line > log`, read
  the `N passed` line). Unit suite unchanged (no import-script code).
- **Negative controls:** observe at least V1, V5 and V6 red against a deliberate break (e.g. skip
  the shown-guard, skip the new-id assignment) before trusting green.

## 5. Promotion notes (for a later, explicitly requested `/promote-prod`)

- No SQL. `app.js` carries `merge=ours`: assert its merge RESULT equals staging's copy.
- Production keeps showing the branding value until Rick saves from Settings on production.
- Write-smoke is warranted: `catalog.html` and `app.js` are on the reserve path.

## 6. Out of scope — stop and ask

- Deleting `tenants.branding.promo_banner` on either environment.
- The post-reserve subscribe prompt (`toastAction`), its frequency rules, its events.
- "Learn more" click tracking and subscribe attribution (D6).
- More than one banner, scheduling (start/end dates), per-customer targeting.
- Any change to `UsageEvents._log()` or the 90-day purge (F90).
- Any `tenants` RLS change (see the observation in § 7).

## 7. Observed during planning

Filed as **F176** (2026-10-15, security-sensitive, details held locally; see § 13). This plan never
writes `tenants`, so it does not depend on F176's outcome. Do not touch `tenants` RLS or grants in
this work.

---

## 8. Build record (2026-10-15, STAGING ONLY, production untouched)

Built in one session on `feature/promo-banner-settings`, merged `--ff-only` to `staging` and pushed
(`3c54071`). **No SQL, no schema, no RLS, no Edge Function, no `config.js`, no nav or footer change.**
Four code files: `app.js` +197 / -0 (purely additive), `catalog.html`, `settings.html` +264,
`analytics.html` +120 / -3.

| Step | Commit | What |
|---|---|---|
| S1 | `b464471` | `PromoBanner` (beside `PageBanner`) and `UsageEvents.promoBannerShown` / `promoBannerDismissed`. `_log()` untouched. |
| S2 | `7bd1a5d` | `catalog.html` reads through `PromoBanner.load()`, started before the serial `getMyIds` -> `loadCurrentMonthQty` -> `Subscriptions.getAll` chain and awaited only at the render call; renders via `mount()`; logs shown / dismissed. |
| S3 | `daed27d` | Settings > Branding > **Subscribe banner** panel (toggle, message with a 200-character counter, link label, link target, live preview, Restore default text, Show it again, own Save / Discard). |
| S4 | `5b9bba0` | Analytics **Subscribe Banner** card (Saw it, Closed it with rate, Subscribed after seeing it, Recent closes) and a definitions entry. |

### 8.1 Evidence, and how it was obtained

- **Harness `promo-banner-settings-verify.mjs`** (local-only, the `page-banner-verify.mjs` convention; password
  grant + `addInitScript`): **86 / 86 against the unpushed working tree, and 86 / 86 against the DEPLOYED staging
  bytes** (served `app.js`, `catalog.html`, `settings.html`, `analytics.html` equal to the committed files on 5 of 5
  consecutive samples first). Covers V1-V9 and: the stalled-read fallback (the catalog's rail revealed after 5.6 s with
  the read held for 12 s), a read that FAILS disabling the Settings controls and Save, the free tier (`demoshop`) editing
  and saving, tenant isolation of rows AND events, the shown-guard when storage throws, a hostile stored
  `link_target` (`javascript:alert(1)`, `constructor`) rendering no link, and the 200 / 201 and 40 / 41 character
  boundaries. Teardown re-read: both tenants' `promo_banner` rows restored exactly (founding was absent), 0 throwaway
  profiles, 0 stray events, all 16 auth users 404.
- **Negative controls, all seen RED** (the local server applies one deliberate fault to the response only, so the
  working tree is never touched): `nofallback` -> V1 red (3 checks); `noshownguard` -> V6 red, a reload logs a second
  `promo_banner_shown`; `nonewid` -> V5 red (id stays `sub-promo-1`, status stays "Original campaign", the customer who
  closed it does NOT see it again); `innerhtml` -> V8 red, **the injected `onerror` actually ran** (flag 1, an `img`
  element in both the preview and the catalog); `nosplit` -> V7 red, **Customer Engagement Score moved 90 -> 88**, two
  extra rows appeared in Customer Activity and the segment counts changed.
- **Spec 09 unchanged (file untouched since 2026-07-17) and green, 5 / 5**, against the deployed bytes; it exercises
  the legacy-fallback path through the new code on its synthetic tenant.
- **V9 layout.** Lighthouse, authenticated `/catalog`, deployed staging, before (the previous bytes) vs after, two runs:
  desktop **100 / CLS 0.011** before and in both runs after; mobile **86** (CLS 0.019, TBT 290 ms) before, **91** and
  **88** (CLS 0.016 and 0.018, TBT 180 and 260 ms) after; FCP and LCP identical. No regression; the mobile spread is the
  probe's TBT noise floor. Settings, Analytics and the catalog banner at 390 px: no horizontal scroll; screenshots inspected.
- **Unit suite 333 / 333** (unchanged: no import-script code).
- **Full Playwright suite, once post-push, against the deployed bytes: 161 passed, 0 failed, 0 flaky, exit 0, 27.8 min**
  (the log's own summary line; `globalTeardown` restored `catalog_filters` and deleted its synthetic tenant). **It took two
  runs, and that is stated rather than smoothed over:** the first was **160 passed, 1 failed** (28.9 min). The failure was
  spec 15 V4's fixtures getting **HTTP 504 Gateway Timeout from Supabase on three different endpoints** (auth admin
  `createUser`, a REST insert, a REST delete), so it never reached an assertion, and `cleanupTestRows()` then threw on the
  504 body. Spec 15 alone then passed **36 / 36** (6.8 min) on the same bytes, and the full suite was run again clean.
  **The failed fixtures leaked two `pw-ordexp-*` users** (auth + profile, created 18:11-18:12Z inside the run, 0 dependent
  rows); after classifying them by prefix and time window they were deleted (re-read: auth 404, 0 profiles). That is F170's
  mechanism (a fixture that fails leaks its user), already filed, so nothing new was filed. Left alone on purpose: the
  `pw-pending-*` auth rows (an intended survivor, F64 item 5) and one `TEST_PW_` catalog row dated 2026-08-12.

### 8.2 Deviations from §§ 2-3, each deliberate

1. **The shown key includes the user id** (`pulllist_promo_shown_<slug>_<id>_<userId>`, not the plan's per-browser
   `..._<slug>_<id>`), so two customers on one browser each log their own impression. The dismissed key is unchanged.
2. **The shown guard is written BEFORE the event is logged**, not after. The plan's own rule is "if storage throws, do not
   log"; writing first is what makes that true (a throwing `setItem` then logs nothing, where log-then-set would have
   logged on every load).
3. **Analytics excludes the two types once, at load** (they are split out of `state.events` into `state.promoEvents`),
   not metric by metric. The pre-check found metrics that count events of ANY type per customer (active customers,
   cohorts, session clustering, Last Seen, win-back, the event breakdowns) and two raw `state.events` reads outside
   `filteredEvents()`, so a per-metric patch could have missed one. `nosplit` shows the cost of missing it.
4. **The card honours the page's staff toggle** (default: customers only) instead of hard-excluding admins, like every
   other panel on the page.
5. **`fromLegacy()` maps all four app-page hrefs**, not only `subscriptions.html`, so a legacy link to any of the four
   keeps working ("nothing changes on deploy"). Anything else becomes "no link" (D4), as planned.
6. **The catalog read has a 4 s bound** (falls back to the legacy value), and `loadWithMeta()` reports a FAILED read
   separately from an absent row so Settings can refuse to save over a row it could not read. The plan did not ask for
   either; both are in the render path or the write path.
7. **The empty-state wording has no "<deploy date>"**: the card says "Counts begin when customers load the Catalog after
   the banner tracking went live", because that date differs per environment and nothing records it.
8. **A "No link" option appears in the target list only when the stored `link_target` is empty** (a legacy value whose href
   was not one of the four pages). Otherwise the select would silently show Subscriptions while customers see no link.
9. Every `localStorage` access in the catalog's banner code is now try/catch (a throwing `getItem` used to abort the
   catalog's init).
10. **A deviation from a DECISION, not just from the plan's text, and one I did not flag at the time (corrected in § 8.4).**
    D1 said "Reset = two buttons"; § 2.4 item 7 described the second as a tick-box applied on Save, and the first build
    followed § 2.4. It is now a button, as D1 said. (§ 2.4 item 7 above still reads "a checkbox"; it is superseded by
    this item and left in place, per the project's convention of marking rather than deleting.)

### 8.3 Not verified, stated plainly

- **Chromium only**: no WebKit, no real phone. Rick has used the Settings panel on staging (and found the restore
  problem in § 8.4, which is fixed but not yet retried by him); **his visual pass on the Analytics card is still owed.**
- **Nothing was run against production data.** The Analytics card has only seen throwaway users' events; production has
  no `promo_banner_*` events until the feature ships there, and its numbers on real traffic are unseen.
- **No committed spec asserts any of it** (the harness is local-only and the Playwright folder is gitignored). The full
  suite says nothing else broke; the evidence for the feature itself is the harness.
- Lighthouse was measured on the catalog only (a customer page, throwaway account with no subscriptions, so the banner
  was shown in both readings); the Settings and Analytics pages were checked for horizontal scroll, not scored.
- "Subscribed after seeing it" is the approximation D6 describes (no click attribution), and counts per browser.
- The write path from Settings was exercised on staging only. **A production save has never been run.**

### 8.4 Follow-up, same day: "Cannot restore a closed message from the admin settings screen" (Rick)

**Fixed on staging `47946d9` (`settings.html` only, +49 / -25); production untouched.** What happened, in order:

- **A plan conflict I did not flag.** D1 (Rick's decision) said **"Reset = two buttons"**: "Restore default text" and **"Show it again to everyone"**. § 2.4 item 7 described the second as a **checkbox applied on Save**, and I built § 2.4 without noting that it contradicted D1. A tick-box that needs a second click on Save, in the last row, is a poor stand-in for a button, and it was not what Rick had decided.
- **My first reproduction passed, and that was a gap in my testing, not evidence of "works".** With real clicks as an admin on the deployed bytes, ticking the box and saving brought the banner back, but only with the banner **switched On**. My harness had the same blind spot (it only exercised the box with the banner On).
- **The root cause was in the data Rick's attempt left behind.** The staging row read `enabled:false` with a **new-format campaign id** and his own placeholder wording. A new id is only assigned when "Show it again" is ticked, so he pressed it while the banner was **Off**. The old code accepted that, saved a new campaign and showed nothing, **and the status line then read "Live campaign started ..." for a banner nobody could see.** That, plus a no-op "Restore default text" (a click that visibly did nothing when the wording was already the default), is what "cannot restore" looked like.
- **Fix.** "Show it again to everyone" is now a **button** (available with no edits; confirms; saves the controls as they stand, so unsaved edits go with it; with the banner Off it says why and saves nothing). A banner that is switched Off is reported as **"Switched off - customers see nothing"**, never as a live campaign. "Restore default text" says so, and points at the right button, when there is nothing to restore. One shared `pbSave(again, btn)` serves both buttons; the id-assignment line is unchanged.
- **Evidence.** Harness **90 / 90 on the unpushed tree and 90 / 90 on the deployed bytes** (served `settings.html` equal to the committed file on 4 consecutive samples first), with Rick's pre-existing staging row snapshotted and restored exactly each time. **Negative controls, each seen RED on its own check:** `nonewid` (V5), `againneedsedit` (V5, "available with no edits": the gate that made the old control unusable), `silentrestore` (V4), and `livewhileoff` (V3, the status read "Live campaign started Oct 15, 2026" for an Off banner, the exact misleading text). Two of my own test errors were caught and fixed on the way: a patch script that ate the backslashes in a regex (the check could never match), and a control stopped one section too early so the check it targeted never ran (it passed, which proved nothing; rerun correctly it went red). Screenshots inspected at 1350 and 390 px.
- **Not verified.** Rick has not retried it. **No committed spec loads `settings.html`**, so the full suite was not rerun (it would exercise nothing this change touches); the nav and footer blocks are unchanged. **The staging banner is currently OFF with Rick's placeholder wording**, because that is the row his attempt saved and the harness restores it exactly; to see it again on staging, switch it On and Save (or press the new button with it On).

### 8.5 Promotion (a separate, explicitly requested step)

`/promote-prod`: no SQL; `app.js` carries `merge=ours`, so assert its merge RESULT equals staging's copy. Production keeps
showing the legacy branding value until someone saves from Settings on production. A write-smoke (reserve then cancel) is
warranted because `catalog.html` and `app.js` are on the reserve path. The branding key is the rollback and stays in place.
