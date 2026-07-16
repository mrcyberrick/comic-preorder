# Analytics v2 — Engagement Dashboard (full redesign, ungated)

**Status:** Complete — 2026-07-16. Implemented on `feature/analytics-v2`,
merged to staging ff-only (`b3f942b`); a snapshot-consistency/ordering bug in
the `usage_events` ranged fetch was found by Rick's first V4 pass and fixed
(`7e4d327`); a computed total was added to the Event Breakdown card to make
the V4 total-events cross-check a direct read (`7098270`). All re-verified
after the fixes. V1–V5 all green — see § 5. Rick confirmed the full V3
checklist and all V4 SQL cross-checks match, 2026-07-16. Promoted to
production via PR [#81](https://github.com/mrcyberrick/comic-preorder/pull/81)
(`bf85c08`/`495a7ff`), same day.

**Post-promotion follow-ups (prod, 2026-07-16):**
- Rick reported a live formatting bug from a prod screenshot: `.v2-grid.cols-3`
  used bare `1fr` columns (≡ `minmax(auto, 1fr)`), so a card with a long
  unbreakable (`white-space:nowrap`) bar-label title forced its column wide,
  squeezing "Most Subscribed Series" into an unreadable word-wrapped sliver.
  Reproduced with a standalone Playwright harness (687/265/687px), fixed with
  `minmax(0, 1fr)` (verified 546/546/546px), shipped staging → prod via PR
  [#82](https://github.com/mrcyberrick/comic-preorder/pull/82) (`ce468c3`/`f9fcac8`).
  A second symptom in the same screenshot (an empty bordered box next to the
  Logins KPI tile) could not be reproduced from the shipped code in isolation;
  Rick confirmed on 2026-07-16 it no longer appears after the grid fix, so no
  separate finding was filed for it.
- Rick requested the Recent Events card default to collapsed with an expand
  toggle. Implemented by reusing the existing `details.data-view` pattern
  already on this page (the DAU trend's "View as table" toggle) — no new CSS,
  no JS change. Shipped staging → prod via PR
  [#83](https://github.com/mrcyberrick/comic-preorder/pull/83) (`bd21eef`/`cfa658d`).
  Confirmed working on prod by Rick, 2026-07-16.
**Target:** staging only (standard flow; prod promotion is a separate explicit request)
**Design reference:** `docs/analytics-v2-mockup.html` (committed copy of the approved
mockup, v3 layout — SAMPLE DATA ONLY) · artifact: https://claude.ai/code/artifact/ad0cfbd8-ef28-42ca-8d88-0b22ff039297
**Scope decision:** Rick, 2026-07-16 — full dashboard in one pass, **no premium
gating** (no plan/tier concept exists in the schema; gating deferred to Phase 6
when self-service tenants make tiers real). Plan-doc + CLI-handoff process.

---

## 1. Goal

Rebuild `analytics.html` from the current counts-only page into the approved
two-section engagement dashboard: core activity counts, plus the derived
engagement layer (WAU/MAU stickiness, 30-day return rate + weekly cohorts,
session frequency, feature depth, AOV uplift, daily-active trend, win-back
list) — with an admin-activity filter applied everywhere, defaulting ON.

## 2. Current state — verified 2026-07-16

- `analytics.html` is admin-only (`Auth.requireAdmin`), queries `usage_events`
  directly via PostgREST, aggregates client-side. Panels: 7 summary pills,
  top reserved/cancelled/subscribed bars, event breakdown, Customer Activity
  table, Recent Events feed. Time windows 7/30/90/all.
- **Admin self-actions ARE logged** — `UsageEvents._log()` (app.js §
  `UsageEvents`) only short-circuits on `AdminContext.isActive()`
  (impersonation). The code comment at app.js:636 and technical-reference.md
  §4.8 claim admins aren't logged; both are wrong. Filed as **F87 candidate**
  (doc correction — filing decision still open with Rick; do NOT change
  `_log()` behavior in this session).
- `usage_events` retention is **90 days** (`purge_old_usage_events`, called
  with `90` on every import). Nothing on this page may claim to see further
  back. The "All time" window is therefore removed in v2.
- **Silent 1000-row truncation risk:** PostgREST returns max 1000 rows by
  default. The current page's un-ranged selects likely already truncate
  silently once event volume grows. v2 must fetch with an explicit high
  range/limit (count-first; remember `range()` 416s on empty sets).
- Schema (all verified in technical-reference.md): `usage_events` §4.8
  (event types: reserve, cancel, subscribe, unsubscribe, catalog_view,
  page_view, login, logout; `metadata` jsonb carries title/series/price_usd/
  page), `user_profiles` §4.9 (`is_admin`, `is_paper`, `status`, `email`),
  `preorders` §4.4, `catalog` §4.3 (`price_usd`, `catalog_month`),
  `subscriptions` §4.7. Admin RLS SELECT policies exist for all of these.

## 3. Scope

### IN
- Full rewrite of `analytics.html` (single tracked file; keep the page
  self-contained: inline styles + inline page script, same as today).
- Toolbar: 7 / 30 / 90-day windows (drop "All time"); **Hide admin activity**
  toggle, default ON; retention note line.
- Core section (KPI tiles + charts + tables) and Advanced section (all
  panels visible to admins — no gating): per-panel spec in Step 2 below.
- Layout: explicit `cols-3` / `cols-2` grids + `span-2` Customer Activity
  (no orphaned grid cells at full width) — markup/CSS in the mockup copy.
- Validated chart palette constants (see § 6).
- Fix the 1000-row truncation risk with explicit ranged fetches.

### OUT — stop and ask
- Premium/free gating, plan columns, any `tenants` schema change (Phase 6).
- Any change to `UsageEvents._log()` (admin logging behavior stays as-is).
- New event instrumentation (`session_id`), retention changes, RLS changes,
  Edge Function changes.
- Sending email from the win-back list (copy-to-clipboard / CSV only).
- New Playwright specs for analytics (manual checklist gates this page).
- The F87 doc correction (separate finding + doc-only commit if Rick approves).

## 4. Runbook

### Step 0 — Pre-flight
Run `/preflight`. Confirm branch `staging` clean + synced, then:

```powershell
git checkout -b feature/analytics-v2
```

Re-read from disk before editing: `analytics.html`, `app.js` (the `UsageEvents`,
`Catalog`, `DateUtils` helpers — reuse the existing current-catalog-month and
week-range patterns; do not invent new ones), `docs/analytics-v2-mockup.html`.

### Step 1 — Data layer (one fetch pass per load)
1. `user_profiles`: `select id, full_name, email, is_admin, is_paper, status`
   (single fetch, reused by every panel; build `adminIds` Set).
2. `usage_events`: `select event_type, user_id, catalog_id, metadata,
   created_at` for the **trailing 90 days regardless of selected window**
   (count first, then explicit `.range()` — the win-back list, return rate,
   and deltas need more history than the selected window). All panels derive
   from this one in-memory array; window/admin filtering is client-side.
3. AOV only: `preorders` embedded with `catalog(price_usd, catalog_month)`
   filtered to the current catalog month (reuse the exact month-resolution
   pattern the app already uses — read it from app.js/mylist.html first),
   plus `subscriptions` `select user_id` for the subscriber set.

**Admin filter semantics (single rule):** when ON, events whose `user_id ∈
adminIds` are excluded from every metric, chart, and table; when OFF they are
included and their table rows get an "Admin" badge + highlight. Toggle
re-renders all panels from the cached arrays — no refetch.

### Step 2 — Panels and formulas
Visual target is the mockup copy; formulas are normative here:

| Panel | Definition |
|---|---|
| WAU / MAU | distinct filtered `user_id` with ≥1 event in trailing 7 / 30 days (fixed trailing windows, independent of the selected display window) |
| Stickiness | WAU ÷ MAU, shown as % |
| KPI deltas | same metric over the equal-length window immediately before the selected one; at 90 days show "—" (no prior window inside retention) |
| Return Rate (30 d) | cohort = users active in [now−60 d, now−30 d); returned = % of cohort with ≥1 event in [now−30 d, now] |
| Cohort card | last 4 Mon–Sun weeks (`DateUtils.weekRange`); per week: % of that week's active users with any event within 30 days after the week's end; open windows marked `*` |
| Sessions | per user, events sorted ascending; new session when gap > 30 min; Session Frequency = total sessions ÷ distinct active users ÷ (window ÷ 7) |
| Feature Depth | distinct core-action buckets per session — catalog (`catalog_view`), reserve/cancel, my-list (`page_view` metadata.page='mylist'), subscriptions (`subscribe`/`unsubscribe` or page_view 'subscriptions'), arrivals (page_view 'arrivals'); report mean + share of sessions at depth 1 / 2 / 3+ |
| AOV uplift | per-customer sum of reserved `price_usd` for the current catalog month, averaged over subscribers vs non-subscribers; uplift = subs ÷ non-subs − 1 |
| DAU trend | daily distinct filtered users, selected window; SVG line+area with crosshair tooltip and "view as table" fallback (crib the mockup's SVG code) |
| Win-back | profiles with `status='active'`, not admin: no event in 30+ days or none in retention, most-recently-lapsed first; `is_paper` rows labeled invite-to-app candidates; suggested play: paper → invite; 30–45 d → nudge; >45 d / none → personal call |

### Step 3 — Local verification
`node --check` is N/A (inline script) — open the page locally is not possible
(needs Supabase), so: paste the page script through a syntax check
(`node -e` with the script body as a function, or a scratch `.js`), then
deploy the branch preview via the normal staging push in Step 4 and verify
there. No `console.error` on load; every panel renders or shows its
empty-state.

### Step 4 — Gates + merge to staging
`/deploy-staging`: ff-only merge, smoke suite (regression — existing specs
must stay green), push `origin staging`.

### Step 5 — Manual staging checklist (V3)
On https://staging.pulllist.pages.dev/analytics.html as admin:
- [x] All panels render with real staging data; no console errors
- [x] Admin toggle ON→OFF visibly changes KPI numbers and reveals badged rows
- [x] Non-admin account is blocked from the page (requireAdmin unchanged)
- [x] Spot-check 3 numbers against SQL Editor superuser counts (staging):
      total events in window, distinct MAU users, win-back row count —
      queries in § 7. Client numbers (admin filter OFF) must match exactly.
      Confirmed match by Rick 2026-07-16 (against `7098270`, post-fix).
- [x] Second-tenant isolation (V5) — satisfied via inherited RLS coverage, not
      a comicstore click-through (no standing staging second tenant exists;
      see § 5 V5 note). Rick's call 2026-07-16.

## 5. Verification gates

| Gate | What | Pass condition | Result |
|---|---|---|---|
| V1 | Page-script syntax check | parses clean | ✅ green 2026-07-16 |
| V2 | Playwright smoke suite | all existing specs green | ✅ green 2026-07-16 (30 unit + 19 Playwright, 0 fail) |
| V3 | Manual staging checklist (Step 5) | every box ticked | ✅ green 2026-07-16 (confirmed by Rick) |
| V4 | SQL cross-check | 3/3 numbers match superuser counts | ✅ green 2026-07-16 (3/3 match, confirmed by Rick against `7098270`) |
| V5 | Isolation spot check | 0 cross-tenant rows visible | ✅ satisfied 2026-07-16 (see note) |

**V5 note:** the checklist's original wording ("comicstore admin sees only
comicstore events") assumed a standing second tenant on staging. There isn't
one — `comicstore` was onboarded on production only (5.5); staging's second-
tenant coverage is the synthetic tenant `07-tenant-isolation.spec.ts`
provisions and tears down per run (green in V2, 5/5 isolation specs).
`analytics.html` adds no new tables, RPCs, or service-role calls — it reads
`usage_events`/`user_profiles`/`preorders`/`subscriptions`/`catalog` through
the same anon-key `db` client as every other page, so it inherits the RLS
isolation that suite already proves. Rick's call 2026-07-16: treat V5 as
satisfied by that inherited coverage rather than standing up a canary tenant
for this page specifically.

## 6. Chart palette (validated 2026-07-16, dataviz validator, surface #181818)

| Role | Hex | Note |
|---|---|---|
| Lunar entity | `#1d5cd6` | replaces `--lunar` **in charts only** — the CSS token pair `#3b82f6`/`#a855f7` fails CVD separation (deutan ΔE 0.9); do not change the global tokens |
| PRH entity | `#9878eb` | CVD ΔE 10.5 vs Lunar — full pass |
| Single data hue | `#3987e5` | magnitude charts, trend line |
| Ordinal ramp | `#86b6ef` / `#3987e5` / `#184f95` | feature-depth segments, light→dark |

## 7. SQL cross-check queries (staging SQL Editor, superuser)

```sql
-- total events, trailing 30 days (compare: page total with admin filter OFF)
select count(*) from usage_events
where tenant_id = '72e29f67-39f7-42bc-a4d5-d6f992f9d790'
  and created_at >= now() - interval '30 days';

-- MAU (compare: MAU tile, admin filter OFF)
select count(distinct user_id) from usage_events
where tenant_id = '72e29f67-39f7-42bc-a4d5-d6f992f9d790'
  and created_at >= now() - interval '30 days' and user_id is not null;

-- win-back count (compare: win-back rows, admin filter ON)
select count(*) from user_profiles up
where up.tenant_id = '72e29f67-39f7-42bc-a4d5-d6f992f9d790'
  and up.is_admin is not true and up.status = 'active'
  and not exists (
    select 1 from usage_events ue
    where ue.user_id = up.id and ue.tenant_id = up.tenant_id
      and ue.created_at >= now() - interval '30 days');
```

## 8. Completion criteria

- [x] `analytics.html` rewritten; V1–V5 all green
- [x] Admin filter defaults ON and covers every panel
- [x] No "All time" window; retention note visible
- [x] Ranged fetches (no silent 1000-row truncation) — plus deterministic
      order + snapshot-consistent count/range bound (`7e4d327`)
- [x] No schema/RLS/Edge Function/`_log()` changes in the diff
- [x] Merged to staging ff-only; smoke suite green; pushed
- [x] This doc's Status line flipped to Complete + date; CLAUDE.md
      out-of-scope pointer line removed/updated

## 9. Rollback

Single-file page with no schema changes: `git revert` the merge commit on
staging (or redeploy prior commit). No data migration to unwind.

## References

- `docs/analytics-v2-mockup.html` — approved visual target (sample data)
- `docs/technical-reference.md` §4.3, §4.4, §4.7, §4.8, §4.9, §6.5
- F87 candidate: admin-logging doc/code contradiction (filing pending)
- F72 (deferred): founding-branded email template — relevant only if a
  future session adds "email the win-back list" (out of scope here)
