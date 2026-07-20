# Subscription Reserved-Suggestions — one-click subscribe from your own reservations

**Status:** **Complete — live in production, 2026-07-19.** Implemented
(`5451406`), amended per Rick's V5 feedback (`a3995fa`, § 4c: always-on
suggestions, Popular dropped, admin read-only view). V1–V5 all green under
the amended matrix (post-amendment full suite: 30 unit + 39 Playwright,
0 failures; spec 11 = 7 tests incl. the two inverted V5-amendment cases;
V5 = Rick's live pass, § 6). Promoted the same day at Rick's explicit
request via PR #91 — see § Production promotion below.
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

## 4c. V5 feedback amendments (2026-07-19, Rick — scope amended at his request)

Rick's V5 pass produced two change requests, both accepted after discussion:

1. **Suggestions are always-on; Popular section dropped entirely.** The
   suggestions section now renders for any customer with qualifying
   *unsubscribed* reserved series, regardless of subscription count — the
   original zero-subs gate and the § 3 OUT-scoped "v2 From your pull list"
   are superseded by this. The "exclude already-subscribed series" filter
   (§ 4b.4 called it unreachable) is now real and load-bearing. The
   ⭐ Popular at Book Stop section, its `app_settings.popular_series` read
   (this page's last F6-trap touch), the `'popular_series'` source, and the
   Popular-dedup logic are all removed. The `popular_series` key in
   `app_settings` simply becomes unused — no DB change made or needed. The
   `popular-series-*` CSS row classes are **kept** (now styling the
   suggestion rows only) to avoid selector churn in page + spec; the CSS
   comment is retitled and the unused `.popular-series-section` wrapper
   rule dropped. Placement stays above the table — CTA visible without
   scrolling, click targets stable.
2. **Admin impersonation shows the list, with subscribe disabled.**
   Explicit decision (AskUserQuestion): disabled button + "Unavailable
   while impersonating" tooltip, over subscribe-on-behalf (deferred; noted
   as a 3-line change if phone workflows want it) and over keep-hidden.
   The preorders fetch switches to `AdminContext.resolveUserId(user.id)`
   so the list reflects the impersonated customer. The section note gets
   an admin-context copy variant. This deliberately diverges from the
   catalog modal's hide-in-impersonation rule — CLAUDE.md § Series
   Subscriptions gets a clarifying line at close.

Gate impact: spec 11 tests 4 (has-sub) and 5 (admin) inverted to the new
behavior; V1's has-sub and admin rows re-earned under the amended matrix;
V4 full-suite re-run required; V5 re-check by Rick after deploy.

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
  **GREEN 2026-07-19** — `11-reserved-suggestions.spec.ts` tests 1–5.
  Not separately spec-asserted (same treatment as promo-banner V1): 375 px
  (flex rows, no fixed widths, CSS variables only — folded into V5 manual
  pass) and custom `primary_color` (all new CSS uses shared classes +
  `var(--accent)`-based button/badge styles). Popular-dedup case moved to
  V5 per § 4b.2 (F6 app_settings trap).
- **V2 — subscribe path:** click ⇒ row flips to ★ Subscribed in place;
  remaining rows persist; table renders above with the new subscription;
  DB row lands with correct `tenant_id`, series, distributor, **format from
  the deduped row**; `usage_events` subscribe row carries
  `source: 'reserved_suggestion'` (DB-verified via PostgREST, polled — the
  usage-event insert is fire-and-forget); a second suggestion subscribes
  independently (multi-subscribe).
  **GREEN 2026-07-19** — spec 11 test 6: flip in place, second row's button
  stays live, table renders the new sub, DB row carries `tenant_id` +
  `format: 'Comic Book'` (comic preferred over the also-reserved TPB),
  source polled. Multi-subscribe evidenced by the surviving live button +
  a successful re-subscribe after undo, not a literal second-series
  subscribe — noted, not glossed.
- **V3 — undo path:** Undo within the toast window ⇒ subscription row
  deleted (DB-verified), table updates (or returns to empty state if it was
  the only sub), suggestion row restores to ☆ Subscribe and works again;
  unsubscribe usage event logged.
  **GREEN 2026-07-19** — spec 11 test 6 (continued): DB row polled to null
  after Undo, row restored and re-subscribable, table back to the empty
  branch. Unsubscribe event logging is pre-existing
  `Subscriptions.unsubscribe` behavior (app.js), untouched by this feature
  — noted rather than re-asserted.
- **V4 — regression:** full `run-smoke.ps1` green; search and Popular
  subscribe flows unchanged except the new `source` metadata (spot-check
  one search subscribe carries `'series_search'`); no layout shift for the
  subscriptions table when the section is absent.
  **GREEN 2026-07-19** — full `run-smoke.ps1`: 30 unit tests + 38
  Playwright tests (specs 01–11), 0 failures, 0 retries. The
  `'series_search'` spot-check was then automated as spec 11 test 7
  (search-subscribe → usage event source polled — green; spec re-run 7/7).
  `'popular_series'` source is not spec-testable (F6 app_settings trap) —
  identical one-argument pattern, code-reviewed; check opportunistically at
  V5 if Popular is configured on the staging founding tenant.
- **V5 — staging live check:** Rick visual pass on live staging with a
  zero-subs account holding qualifying reservations (see Step 6 note);
  mobile width included.
  **GREEN 2026-07-19** — two rounds. Round 1 surfaced the two § 4c change
  requests (Popular below suggestions felt redundant and both vanished
  after the first subscribe; admin impersonation hid the list). Round 2,
  after the amendments were live (`a3995fa`): Rick confirmed the amended
  behavior ("looks good"). The original zero-subs account requirement
  dissolved with the always-on amendment — his regular test account
  exercises the section directly.

## 7. Completion criteria

- [x] Steps 0–6 complete; all § 2 anchors re-verified byte-exact at
      execution (2026-07-19 — all matched at the planned line numbers)
- [x] V1–V5 all green (evidence in § 6; V1/V4/V5 re-earned post-§ 4c
      amendments)
- [x] Playwright spec 11 added to local suite (7 tests, two amended per
      § 4c); post-amendment full run green — 30 unit + 39 Playwright
      (specs 01–11), 0 failures
- [x] Merged to staging `--ff-only` (`5451406`; amendments `a3995fa`);
      pushed; CF Pages staging deploy verified live (Rick visual +
      `curl -L` DOM-marker fetch)
- [x] This doc's status updated; CLAUDE.md updated at close (closure
      paragraph + Series Subscriptions impersonation clarification)
- [x] Out-of-scope discoveries filed, not fixed inline (none found; session
      notes below record process lessons only)

### Production promotion (2026-07-19)

Rick requested promotion via `/promote-prod` the same session, after V5
closure. Followed the skill:
- Merge `staging` → PR branch with `git checkout main -- config.js` (prod
  credentials preserved; `config.js` confirmed absent from the PR diff).
- F59 check clean — `subscriptions.html` differs as expected;
  `app.js`/`mylist.html`/`arrivals.html`/`admin.html` correctly identical
  (feature never touched them).
- Merge-base check: the two Phase-4 migration SQL files that appear as
  deletions in the raw `main..staging` diff are main-only additions
  outside the merge-base — merge leaves them untouched (verified via
  `git cat-file -e` against the merge-base before merging).
- PR #91 → merged by Rick → `5167ab4` on `main`. True merge commit
  (`47263b2`, parents = main tip + staging tip) preserved for future
  merge-bases. Process note: the first commit attempt hit the PowerShell
  5.1 embedded-double-quote native-arg bug (same as earlier in the
  session) and left an empty pushed branch; caught because
  `git checkout -b` had also silently dropped `MERGE_HEAD` — merge redone
  properly with a `-F` message file after verifying parents.
- Prod deploy verified live via `curl -L` DOM-marker fetch
  (`reserved-suggestions` container + impersonation tooltip string both
  present at https://pulllist.app/subscriptions.html).
- Post-deploy write-smoke: Rick, as a real user on prod — passed
  ("Green, pass").
- Bundling check: `main..staging` carried only this feature + doc-only
  commits. The shelf-copy feature, previously believed unpromoted, was
  confirmed already live on prod (PR #89) — the stale local memory note
  was corrected.

### Post-close fix: mobile clipping (2026-07-19)

Rick reported post-promotion that the Subscribe button was cut off on
mobile at https://pulllist.app/subscriptions.html. Root cause: the
suggestion row's fixed-width actions cluster (`flex-shrink: 0`) overflowed
the flex row on narrow screens and was clipped by `.popular-series-list`'s
`overflow: hidden`. This was V1's known soft spot — 375 px was "folded
into V5" and the visual pass missed it.

Fix (`282dd0b`): `@media (max-width: 640px)` — rows `flex-wrap: wrap`,
name shrinks (`min-width: 0`, `overflow-wrap: anywhere`), publisher
hidden, actions cluster right-aligned; applied to `.search-result-row`
too (same latent clipping pattern on the same page).

Verification: new spec 11 test 9 (375 px viewport — zero horizontal
overflow, every subscribe button's bounding box within viewport width,
end-to-end tap). The test **failed against the pre-fix deployed page
(button right edge at 525 px — reproducing the report) and passed 8/8
after the fix deployed**; full-page 375 px screenshot visually inspected
(worst case: long series name + format badge wraps cleanly). Pre-push
full suite: 39/40 with the only failure being this new test against the
pre-fix deployment, per the deploy-sequencing precedent. Prod promotion
of the fix: pending Rick's phone check on staging.

- **Deploy-verification gotcha:** `staging.pulllist.pages.dev` answers
  `/subscriptions.html` with an **HTTP 308** redirect to the extensionless
  path and an empty body. Status-blind `curl` polls therefore read as "old
  version" indefinitely — this session burned ~25 minutes on a phantom
  "stuck deploy / cache flapping" theory (including one harmless
  doc-commit retrigger push) before checking the status code. Rule: poll
  deploys with `curl -L` (or check `%{http_code}`) and inspect what the
  response actually is before theorizing.
- **Spec auth race:** navigating away from catalog immediately after the
  magic-link `waitForURL` lands can outrun Supabase session persistence —
  subscriptions.html then bounces to the login page (diagnosed from the
  failure screenshot, per the diagnose-with-data rule). Fix: helper waits
  for `networkidle` on catalog before `goto('subscriptions.html')`, plus a
  Loading-placeholder wait before assertions. Spec was 1-failed/1-flaky
  before the fix; 7/7 stable after, with the page code unchanged —
  confirming both failures were spec-side.
- Spec 11 grew beyond the planned V1–V3 matrix to 7 tests: test 7
  automates V4's `'series_search'` attribution spot-check.

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
