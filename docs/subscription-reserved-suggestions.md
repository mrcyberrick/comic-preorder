# Subscription Reserved-Suggestions — one-click subscribe from your own reservations

**Status:** Planned — 2026-07-19. Not started.
**Target:** staging only. Prod promotion is OUT — separate explicit request via
`/promote-prod` after staging sign-off.
**Origin:** Rick's request 2026-07-19; follow-on to the subscription-promotion
feature (live in production 2026-07-17 — `docs/subscription-promotion.md`).

---

## 1. Goal

When a signed-in customer with **zero subscriptions** but **≥1 qualifying
reservation** visits subscriptions.html, show a personalized "Series you're
already reading" list built from their own pull list. One click subscribes
(with an Undo toast). Converts demonstrated intent — the strongest signal we
have — instead of the generic Popular/catalog discovery paths.

Per the July 2026 engagement analysis, 5 of 6 reserving customers have zero
subscriptions; this targets exactly that cohort at the moment they visit the
subscriptions page.

## 2. Current state — verified 2026-07-19

Line refs verified this date; **re-verify byte-exact at execution** (File
Drift Prevention).

### subscriptions.html
- `loadSubs()` (344–355) → `renderSubs()` (357–481). Empty branch 365–428:
  renders the `sub-empty` block (390–400) plus the "⭐ Popular at Book Stop"
  section (368–388, gated `popularSeries.length && !AdminContext.isActive()`),
  wires `.pop-sub-btn` (403–425). The popular subscribe call passes **no
  format and no source**: `Subscriptions.subscribe(targetUserId, series,
  distributor)` (408–410).
- **Dead code:** `const subKeys = new Set(); // empty — no existing subs`
  (366) is never used in the empty branch — leftover from an earlier
  iteration; remove while rewriting this block.
- Series search: `searchSeries()` (498–600) with inline `isComicFormat()`
  helper (523–528) and comic-over-TPB dedup (529–538). Search subscribe path
  (571–599) passes `format` but **no source**, and swaps the row in place to
  "★ Subscribed" on success (594–597) — the exact in-place pattern the new
  section reuses.
- Containers: `#search-results-panel` (254), `#subs-container` (257).
- Admin impersonation: search disabled (493–496); popular section hidden;
  page-view logging gated (613–615).

### app.js
- `Preorders.getMy(userId)` (761–780) — joins `catalog` with every field the
  suggestions need: `series_name, distributor, variant_type, format,
  cover_url, publisher, title, issue_number, price_usd, on_sale_date,
  catalog_month`; ordered `created_at` desc already.
- `Subscriptions.getAll` (913–920); `Subscriptions.subscribe(userId,
  seriesName, distributor, format = null, source = null)` (939–953) — logs
  `UsageEvents.subscribe` with `source` at 951. `unsubscribe` (956–965) logs
  its own usage event.
- `toastAction(message, actionLabel, onAction, { duration = 8000, type =
  'success', onDismiss = null })` (1311) — shipped with subscription-promotion;
  `onAction` fires once on accept; `onDismiss` on explicit dismiss or timeout.

### Precedents
- mylist.html 812–860 — empty-state discovery section (`#first-issues-section`,
  "New #1 issues this month") is the async-append precedent; this plan
  deliberately deviates (see § 4 render order) to avoid copy-flicker and a
  dedup ordering problem.
- Eligibility gate ("qualifies to subscribe") is the shipped
  subscription-promotion rule: `series_name` non-null, standard cover
  (`variant_type` null / `'Standard'` / `'Primary Title'`), not already
  subscribed (key `` `${series_name}||${distributor}` ``), never in admin
  impersonation. Variant-only reservations do **not** qualify — variant
  collectors often specifically don't want the standard cover auto-reserved.

## 3. Scope

### IN

1. **Suggestions builder** (subscriptions.html page code): when
   `allSubs.length === 0` and not `AdminContext.isActive()`, fetch
   `Preorders.getMy(user.id)` and build suggestion rows:
   - Qualify: `item.catalog` present (orphan guard, same as mylist),
     `series_name` non-null, standard cover per § 2 gate.
   - Dedup by `` `${series_name}||${distributor}` ``, preferring comic format
     over TPB/HC via `isComicFormat()` — **hoist that helper out of
     `searchSeries()` to page scope** and reuse it in both places.
   - Carry per-series: reserved-issue count, `cover_url` (from the preferred
     row, falling back to any row that has one), `publisher`, `format`.
   - Sort by most recent reservation first (`created_at` desc — `getMy`'s
     existing order makes this free: first occurrence wins).
   - No cap — the list is bounded by the customer's own reserved series.
2. **Render**: new `#reserved-suggestions` container in static HTML between
   `#search-results-panel` and `#subs-container`, **outside** `renderSubs()`'s
   re-render target — so the list survives the table appearing after the
   first subscribe. Row layout mirrors `.popular-series-row` with a small
   cover thumbnail (36×54, mylist table pattern) prepended: cover, series
   name, publisher, "N issues reserved" (shown when N > 1), distributor
   badge, format badge when non-comic, `☆ Subscribe` button. Header
   "📚 Series you're already reading" + note "You've reserved these —
   subscribe and your copy is auto-reserved every month, no action needed."
   Styles in the page `<style>` block beside the popular-series styles, all
   colors via CSS variables (inherits per-tenant `primary_color` branding).
3. **Render order** (deviation from the mylist async-append precedent): when
   subs come back empty, **await** the preorders fetch and build suggestions
   *before* the first `renderSubs()` call. Rationale: (a) the empty-state
   copy swap (§ 3.5) renders right the first time, no flicker; (b) the
   Popular section can dedupe against suggestion keys (§ 3.6). One extra
   round trip only for the no-subs cohort; payload is a customer's own
   preorders — tiny.
4. **One-click subscribe + Undo**: button click →
   `Subscriptions.subscribe(user.id, series, distributor, format,
   'reserved_suggestion')` (button disabled while in flight; pass the
   deduped row's format). On success:
   - Flip the row in place to "★ Subscribed" (search-results pattern,
     § 2) — remaining suggestions stay visible for rapid multi-subscribe.
   - Push onto `allSubs` + `renderSubs()` so the table appears/updates above.
   - `toastAction('Subscribed to {series}!', 'Undo', …)` — Undo calls
     `Subscriptions.unsubscribe`, removes from `allSubs`, re-renders the
     table, and restores the row's Subscribe button. No confirm dialog:
     one-click forward, easy backward.
5. **Empty-state copy swap**: when suggestions exist, replace the "No
   subscriptions yet / Open any series in the catalog…" copy with framing
   that points down at the list (e.g. h3 "You're already reading these" /
   p "Subscribe below and never miss an issue — auto-reserved every
   month."), and demote Browse Catalog to `btn-secondary`. When no
   suggestions exist, current empty state renders unchanged.
6. **Popular dedup**: exclude from the Popular section any series already
   present in the suggestions list (same composite key) so a series never
   appears twice on the page. Suggestions render above Popular.
7. **Attribution completeness** (same file, serves this feature's
   measurement goal): pass `source` on the two existing subscriptions.html
   subscribe paths too — `'popular_series'` (408–410, now also passing
   explicit `null` format) and `'series_search'` (577–579). New section uses
   `'reserved_suggestion'`. No new event_types; metadata field only, exactly
   like the promotion feature's `'modal'` / `'post_reserve_prompt'`.
8. **Incidental tidy**: remove the dead `subKeys` line (366) while rewriting
   the empty branch.
9. **Playwright spec** (local suite, never committed):
   `11-reserved-suggestions.spec.ts` covering the § 6 V1–V3 matrix. Seed
   preorders/subscriptions via the existing DB fixtures against the per-run
   synthetic tenant (never the founding tenant, per `playwright/README.md`).
10. **Docs**: this plan's status upkeep; CLAUDE.md closed-scope note at
    completion (same pattern as prior features).

### OUT — stop and ask

- **v2 "From your pull list"** for users who already have ≥1 subscription
  (suggestions below the table). Deliberately deferred — the target cohort
  is the zero-subs majority; revisit with conversion data.
- Qualifying variant-only reservations (business rule stands: standard
  covers only).
- Any change to catalog.html, mylist.html, Edge Functions, schema,
  `app_settings`, `tenants.branding`, config.js, or import scripts. This
  feature is pure tenant-agnostic client code on one page — **zero DB
  steps**.
- Email promotion (F72 territory), impression logging (same rejection as
  the promotion plan — measure via `source` + subscription counts).
- Changes to `toastAction()` itself or `UsageEvents._log()`.

## 4. Runbook

### Step 0 — Pre-flight
- `/preflight`; branch `feature/subscription-reserved-suggestions` off
  up-to-date staging.
- Re-verify every § 2 anchor byte-exact (`Select-String` / view before any
  `str_replace`); halt on mismatch.
- Confirm the Playwright fixtures available for seeding preorders for the
  synthetic-tenant user (specs 02/03 reserve via UI; check
  `fixtures/catalog.ts` for a direct seed helper — add one there if absent,
  fixtures-only change, synthetic tenant only).

### Step 1 — Markup + styles
`#reserved-suggestions` container div; section styles beside the
popular-series block; hoist `isComicFormat()` to page scope (verify the
search path still passes after the hoist).

### Step 2 — Builder + render
Qualify → dedup → count → sort per § 3.1; render per § 3.2–3.3; empty-state
copy swap per § 3.5; Popular dedup per § 3.6; remove dead `subKeys`.

### Step 3 — Subscribe wiring
In-place flip, `allSubs` push + `renderSubs()`, `toastAction` Undo per
§ 3.4. In-flight button disable on both subscribe and undo.

### Step 4 — Attribution
`source` on all three page paths per § 3.7.

### Step 5 — Local verification
- New spec `11-reserved-suggestions.spec.ts`. **Deploy-sequencing
  precedent** (subscription-promotion, confirmed with Rick 2026-07-17):
  `playwright.config.ts` `baseURL` is hardcoded to staging, so the new spec
  cannot pass until the merged code is pushed to staging — push first (low
  risk, staging iteration encouraged), then write/run the new spec, then
  the full suite as the real gate.
- Full `.\run-smoke.ps1` green. Do not edit any `.ps1`; if one is touched
  anyway, apply CLAUDE.md's BOM-restore rule.
- Manual browser pass: 375 px mobile width; a synthetic tenant with custom
  `branding.primary_color` (badge/button/link colors follow it).

### Step 6 — Gates + staging deploy
- Run V1–V4. All green ⇒ `/deploy-staging` (ff-only; smoke gate inside).
- V5 with Rick on live staging. **Note:** Rick's staging test account had 5
  active subscriptions at promotion-V5 (2026-07-17) — seeing this feature
  requires a zero-subs account; either the same temporary clear-and-restore
  dance as last time, or a throwaway staging customer account with
  reservations only.
- Update this doc's status + completion boxes as earned.

## 4b. Execution deviations (recorded 2026-07-19, during implementation)

1. **§ 3.5 copy swap dropped — plan self-contradiction resolved.** § 3.2
   places the suggestions container *above* `#subs-container`, but § 3.5's
   swapped empty-state copy said "Subscribe **below**" — both can't hold.
   Resolution: § 3.2 placement kept (required for the list to survive
   re-renders; keeps click targets stable during multi-subscribe); instead
   of swapped copy, the `sub-empty` block is **suppressed entirely** when
   suggestions are showing — the section header carries the message and the
   toolbar already has a Browse Catalog button (`btn-secondary`, so the
   § 3.5 demote is moot). When no suggestions exist, the empty state renders
   byte-identical to before.
2. **Popular-dedup case moved from spec to manual V5.** Popular series live
   in `app_settings`, whose key-only PK is shared state (the F6 trap) — a
   Playwright spec writing `popular_series` would clobber founding-tenant
   staging data. The dedup is a pure client-side filter; it is verified by
   code review + the live V5 pass instead of spec 11.
3. **Fixture extension:** `seedCatalogRow` gained an optional `format`
   field (`fixtures/catalog.ts`, defaults unchanged) so spec 11 can assert
   comic-over-TPB format propagation. Synthetic-tenant-only, local suite.
4. **`buildSuggestions` has no subscribed-series exclusion check** — the
   plan's § 3.1 "not already subscribed" filter is structurally unreachable:
   the builder only runs when `allSubs.length === 0`. The `subscribed` flag
   on each suggestion (set on subscribe, cleared on undo) covers post-load
   state instead.

## 5. UX decisions (settled at planning, 2026-07-19)

- **One click + Undo toast, not a confirm dialog** — a confirm defeats the
  one-click goal; `toastAction` Undo keeps accidental taps recoverable.
- **List survives the first subscribe** — the biggest UX trap in the naive
  implementation (empty-branch-only render would wipe remaining suggestions
  the moment `allSubs` becomes non-empty). Own container outside
  `renderSubs()` solves it structurally.
- **No price on suggestion rows** — a subscription is a standing commitment,
  not a purchase of that issue; per-issue price adds clutter and implies the
  wrong mental model.
- **Personalized copy over generic** — "Series you're already reading" +
  reserved-issue counts; suggestions above Popular; Popular deduped.
- **Recency sort** — most recently reserved first; freshest intent on top.

## 6. Verification gates

- **V1 — visibility matrix:** zero subs + qualifying reservations ⇒ section
  renders above Popular, rows correct (dedup by series+distributor, comic
  preferred over TPB, counts right, variant-only and null-series
  reservations excluded, subscribed series excluded); zero subs + no
  reservations ⇒ current empty state + Popular unchanged; zero subs + only
  non-qualifying reservations ⇒ no section, current empty state; ≥1 sub ⇒
  no section; admin impersonation ⇒ no section, no preorders fetch; a
  series in both suggestions and Popular appears only in suggestions;
  375 px; custom `primary_color` tenant.
- **V2 — subscribe path:** click ⇒ row flips to ★ Subscribed in place;
  remaining rows persist; table renders above with the new subscription;
  DB row lands with correct `tenant_id`, series, distributor, **format from
  the deduped row**; `usage_events` subscribe row carries
  `source: 'reserved_suggestion'` (DB-verified via PostgREST, polled — the
  usage-event insert is fire-and-forget); a second suggestion subscribes
  independently (multi-subscribe).
- **V3 — undo path:** Undo within the toast window ⇒ subscription row
  deleted (DB-verified), table updates (or returns to empty state if it was
  the only sub), suggestion row restores to ☆ Subscribe and works again;
  unsubscribe usage event logged.
- **V4 — regression:** full `run-smoke.ps1` green; search and Popular
  subscribe flows unchanged except the new `source` metadata (spot-check
  one search subscribe carries `'series_search'`); no layout shift for the
  subscriptions table when the section is absent.
- **V5 — staging live check:** Rick visual pass on live staging with a
  zero-subs account holding qualifying reservations (see Step 6 note);
  mobile width included.

## 7. Completion criteria

- [ ] Steps 0–6 complete; all § 2 anchors re-verified byte-exact at
      execution
- [ ] V1–V5 all green (evidence noted in this doc)
- [ ] Playwright spec 11 added to local suite; full run green
- [ ] Merged to staging `--ff-only`; pushed; CF Pages staging deploy
      verified live
- [ ] This doc's status updated; CLAUDE.md updated at close (same pattern
      as subscription-promotion)
- [ ] Out-of-scope discoveries filed, not fixed inline

## 8. Rollback

Client-code only; no schema, no Edge Functions, no config.js, no
`branding`/`app_settings` data. Full rollback = revert the merge on
`staging`. Subscriptions created via the suggestions list are **real
customer intent — never mass-delete** as part of rollback.

## References

- `docs/subscription-promotion.md` — eligibility gate, `toastAction`,
  `source` attribution pattern, deploy-sequencing precedent, V5
  account-state gotcha
- `docs/technical-reference.md` — subscriptions/preorders/catalog schema;
  § 13 F72 (email branding, OUT here)
- CLAUDE.md — deployment workflow, merge gate, variant-type business rule
- mylist.html 812–860 — empty-state discovery precedent (pattern deviated
  from deliberately; § 3.3)
