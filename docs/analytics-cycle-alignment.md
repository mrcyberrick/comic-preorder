# Analytics — Cycle-Aligned Comparisons + Cycle Overlay

**Status:** Complete — 2026-07-19. Merged to staging ff-only (`d6ee227`); V3 checklist correction doc commit (`fa2cff6`). V1–V5 all green.
**Target:** staging only (standard flow; prod promotion is a separate explicit request)
**Predecessor state:** the live `analytics.html` is the **3-tier redesign**
(Executive / Operations / Customer Intelligence), commits `fa8d4a5` +
`a151896` (2026-07-16/17). That redesign postdates
`docs/analytics-v2-engagement-dashboard.md` and has no plan doc of its own —
do NOT use the v2 doc's panel list as a description of the current page; read
`analytics.html` from disk. The v2 doc remains valid for the chart palette
(§ 6) and the V5 inherited-isolation precedent (§ 5).
**Related findings (filed 2026-07-19, both OUT of scope here):** F89
(conversion instrumentation), F90 (monthly rollup) —
`docs/technical-reference.md` § 13.
**Process:** plan-doc + CLI-handoff, same as analytics v2. Execution is one
session, one feature branch, single tracked file.

---

## 1. Goal

Remove the monthly-cycle confound from the engagement metrics, and make the
catalog cycle itself visible:

1. **Cycle-anchored deltas** — every "vs prior" comparison on the page
   compares *the same phase of the cycle* (day 1–N of this cycle vs day 1–N
   of last cycle) instead of rolling trailing windows anchored to the moment
   the page is opened.
2. **Cycle overlay chart** — a "This Cycle vs Last" line overlay (daily
   active customers by day-of-cycle) on the Executive tab.
3. **New Customers tile** — first acquisition metric on the page (profiles
   `created_at`, which never purges).

## 2. Problem (verified 2026-07-19)

All engagement metrics in `analytics.html` use rolling windows anchored to
`Date.now()` (`execMetrics()`, ~line 703: retention = active 30–60 d ago vs
0–30 d; habit = trailing WAU/MAU; visits/week = trailing 30 vs prior 30; ops
KPIs same pattern). Store activity is periodic around the catalog cycle: the
monthly import lands ~day 8–10 of the month (July: 2026-07-08→10), the notify
email triggers a burst of views/reserves, then activity decays toward the
order deadline and goes quiet until the next drop.

A trailing window slides across that wave, so the engagement score and every
delta oscillate with the **viewing date** even when customer behavior is
unchanged: opened just after a drop, everything reads up; opened just before
the next drop, the same store reads as decline — and "What Changed This
Month" narrates the artifact in confident prose. The one already-immune
metric is **Reserved This Month** (`reservedValueForMonth()`, anchored to
`metadata.catalog_month`); this session extends that anchoring to the rest.

## 3. Scope

### IN (single file: `analytics.html`)
- **Cycle-start resolution** in the data layer (two `limit(1)` PostgREST
  queries on `catalog.created_at` — § 5.1).
- **Cycle-anchored replacements** for the hero score/components, Executive
  KPI deltas, and Operations KPI deltas (§ 5.2). "What Changed" inherits via
  `execMetrics()`; adjust its "this month" copy to "this cycle" where needed.
- **Labels:** delta labels become "vs same point last cycle"; page subtitle
  becomes `Day {N} of the {Month} cycle`.
- **Overlay card** "This Cycle vs Last" on the Executive tab (§ 5.3): SVG
  line overlay, deadline marker, view-as-table fallback, empty states.
- **New Customers KPI tile** on the Executive row (§ 5.4); adds `created_at`
  to the existing `user_profiles` select.
- **Metric definitions** panel updated to match every changed formula.
- Existing validated `--viz-*` palette only — no new colors.

### OUT — stop and ask
- Single-window panels stay on trailing windows: journey funnel, title bars,
  publisher demand, activity table, segments, weekly cohorts, win-back.
  They state their window honestly and make no prior-period claim; changing
  their numbers Rick already watches is a separate decision.
- F89 (claim/invite instrumentation — Edge Function changes) and F90
  (monthly rollup — schema + import script). Filed; separate sessions.
- Any schema, RLS, Edge Function, or `UsageEvents._log()` change.
- New Playwright specs (manual checklist gates this page, per v2 precedent).
- Retention-period changes (90-day purge stays).

## 4. Current state facts the executor must not rediscover

- `catalog.created_at` (timestamptz, default `now()`) exists — tech-ref
  § 4.3. The import **upserts**; the update path does not touch
  `created_at`, and a new month's rows are fresh inserts → per-month
  `min(created_at)` ≈ that month's first import run. On month rollover the
  import purges **unreserved** prior-month rows only, so the prior month
  normally keeps ≥1 row (reserved ones). Known limitation: an older-month
  **backfill** import would insert prior-month rows with backfill-time
  `created_at`, skewing that month's cycle start — acceptable; the § 6 Step 0
  SQL check reveals the actual current state.
- `usage_events` columns/event types: tech-ref § 4.8. Only `reserve` events
  carry `metadata.catalog_month` — cycle starts come from `catalog`, not
  events, on purpose.
- `user_profiles.created_at` exists (§ 4.9); profiles are never purged, so
  the New Customers tile is exact (not 90-day-bounded).
- The admin toggle re-renders all panels from cached arrays without refetch;
  every new panel must follow that contract (`renderAll()` path).
- Local Date Pattern (CLAUDE.md): day bucketing and day counts use local
  date parts (`DateUtils`), never `toISOString()` — ISO strings remain fine
  for PostgREST `gte/lte` bounds only.
- The staff-activity warn banner relies on the `.warn-banner[hidden]` CSS
  override (`a151896`) — do not disturb it; it's a V3 regression check.

## 5. Normative design

### 5.1 Cycle resolution (data layer)

| Symbol | Definition |
|---|---|
| `M` | `Catalog.getLatestMonth()` (unchanged) |
| `cycleStart` | `min(created_at)` of catalog rows with `catalog_month = M` — via `db.from('catalog').select('created_at').eq('catalog_month', M).order('created_at', {ascending: true}).limit(1)` |
| `prevStart` | same query for `shiftMonth(M, -1)`; **null** if no rows survive |
| `N` | days elapsed in current cycle, local dates: `daysBetween(localDate(cycleStart), todayLocal()) + 1` (day 1 = import day); floor 1 for divisions |
| `prevLen` | `daysBetween(localDate(prevStart), localDate(cycleStart))`; the prior cycle's full length in days |
| `Nc` | `min(N, prevLen)` — phase cap for every prior-side window |
| `prevPrevStart*` | `prevStart − prevLen` days — **approximation** (the real month-before-prior catalog rows are typically purged; equal-cycle-length assumption is acceptable for a delta baseline and must be labeled in the defs panel) |

Fallbacks: `M` null → all existing empty states apply, overlay card shows
no-data. `prevStart` null → every cycle-anchored delta renders "—", overlay
draws the current line only with note "No prior cycle in the 90-day window".

### 5.2 Metric formulas (replacing `execMetrics()` internals)

| Metric | Current value | Prior baseline (delta) |
|---|---|---|
| Retention | cohort = distinct users active in `[prevStart, cycleStart)`; % active in `[cycleStart, now]` | cohort = active in `[prevPrevStart*, prevStart)`; % active in `[prevStart, prevStart + Nc]`. **null** ("—") if `prevPrevStart*` < NOW−90 d or cohort empty |
| Habit | unchanged: trailing WAU/MAU from NOW | WAU/MAU with both windows anchored at `T = prevStart + Nc` (trailing 7/30 d from T) |
| Visits/week | sessions over `[cycleStart, now]` ÷ users ÷ (N/7) | sessions over `[prevStart, prevStart + Nc]` ÷ users ÷ (Nc/7) |
| Actions/visit | mean session depth over `[cycleStart, now]` | same over `[prevStart, prevStart + Nc]` |
| Engagement score | same 40/25/20/15 blend | blend of the prior-baseline components; null if retention-prior or habit-prior is null |
| Ops KPI counts (reserves, cancels, subs, views, logins) | counts in `[cycleStart, now]` | counts in `[prevStart, prevStart + Nc]`; label "vs same point last cycle" |
| Reserved This Month | **unchanged** (already month-anchored) | unchanged |
| New Customers | non-admin, non-paper profiles with `created_at ≥ cycleStart` | same in `[prevStart, prevStart + Nc]` (exact — profiles never purge) |

Session clustering, `CORE_BUCKETS`, the 30-min gap rule, and the admin-filter
semantics are all unchanged — only the *windows* move.

### 5.3 Overlay card — "This Cycle vs Last"

- Placement: Executive tab, full-width card between the KPI row and the
  cols-2 grid.
- Series: per local day `d` (1-based day-of-cycle), distinct filtered
  `user_id` count with ≥1 event that day. Current cycle drawn for days
  `1..N` in `--viz-blue` `#3987e5` (with the subtle area fill); prior cycle
  for days `1..prevLen` in `--viz-seq-1` `#86b6ef`, no fill. Lighter = older
  is the validated ordinal-ramp use; **no new colors**.
- Markers: vertical dashed line at the order-deadline day offset (from
  `Settings.getOrderDeadline()`, already fetched) when it falls on the axis;
  end-dot on the current line at day N.
- Axis: x = day-of-cycle (tick every 7 days, extent `max(N, prevLen)`);
  y = customers, integer ticks from 0.
- Interaction: hover crosshair tooltip showing day + both values (crib the
  SVG approach from `docs/analytics-v2-mockup.html`), plus the
  `details.data-view` "View as table" fallback with one row per day.
- Legend: "July (current)" / "June" style, using `monthLabel()`.
- Respects the admin toggle via the same cached-array re-render.

### 5.4 Data-layer diff summary

1. `user_profiles` select adds `created_at` (same single fetch).
2. Two `limit(1)` catalog queries for `cycleStart` / `prevStart` (added to
   the existing `Promise.all`).
3. Everything else derives from the already-cached 90-day `state.events`.
   No new tables, RPCs, service-role calls, or Edge Functions — the page
   keeps reading through the anon-key `db` client, so RLS isolation
   coverage is inherited exactly as argued in v2 § 5 (V5 note).

## 6. Runbook

### Step 0 — Pre-flight
Run `/preflight`. Then verify the cycle-start assumption against live
staging **before writing any code** (Rick runs in SQL Editor, superuser):

```sql
select catalog_month, min(created_at) as cycle_start, count(*) as rows
from catalog
where tenant_id = '72e29f67-39f7-42bc-a4d5-d6f992f9d790'
group by catalog_month
order by catalog_month;
```

Expected: current month's `cycle_start` matches the known July import
(2026-07-08→10) and the prior month still has ≥1 row. If the prior month has
**zero** rows, the "—"/single-line fallback path is the visible launch state
— build and verify it first-class, and note it in the V3 checklist results.

```powershell
git checkout -b feature/analytics-cycle-alignment
```

Re-read from disk: `analytics.html` (full page script), `app.js`
(`DateUtils`, `Catalog.getLatestMonth`, `Settings.getOrderDeadline`),
`docs/analytics-v2-mockup.html` (SVG reference only).

### Step 1 — Implement
Data layer (§ 5.1, § 5.4) → metrics (§ 5.2) → labels/copy → overlay card
(§ 5.3) → New Customers tile → metric-definitions panel. Byte-exact
`old_str` verification before every edit, per CLAUDE.md runbook standards.

### Step 2 — Local verification (V1)
Extract the inline page script to a scratch file and syntax-check it
(`node --check` on a function-wrapped copy), same as v2 Step 3. No
`console.error` on load once deployed; every panel renders or shows its
empty state.

### Step 3 — Gates + merge (V2)
`/deploy-staging`: ff-only merge, unit + Playwright suite green (regression
only — no new specs), push `origin staging`.

### Step 4 — Manual staging checklist (V3)
On https://staging.pulllist.pages.dev/analytics.html as admin:
- [ ] Subtitle shows the correct day-of-cycle (cross-check against Step 0's
      `cycle_start`)
- [ ] Hero + KPI deltas read "vs same point last cycle"; any unavailable
      baseline shows "—", not 0
- [ ] Overlay: current + prior lines plausible (non-degenerate day-to-day
      shape, not all zero/flat). Burst timing is **not** expected to align
      to the same day offset across cycles — the notify-customers email
      that usually drives the visible spike can be suppressed on a given
      import (confirmed against real staging data 2026-07-19: June's
      cycle_start day-1 burst vs July's day-13/day-20 bursts), so the chart's
      job is a stable anchor, not a guaranteed aligned spike; deadline
      marker on the correct day; table fallback matches the lines
- [ ] New Customers tile present; count sane vs known recent signups
- [ ] Admin toggle ON→OFF changes the overlay and all cycle KPIs; staff
      banner still appears/disappears correctly (`a151896` regression)
- [ ] Tabs, hash routing, and the three unchanged-panel groups behave as
      before; no console errors
- [ ] Non-admin account still blocked (requireAdmin unchanged)

### Step 5 — SQL cross-check (V4, staging SQL Editor, superuser)
Client numbers taken with admin filter OFF must match exactly; queries
parameterized by the `cycle_start` values from Step 0 (`:cs` = current
cycle start, `:ps` = prior cycle start, `:nc` = Nc as computed on-page):

```sql
-- (a) one overlay point: distinct actives on a chosen local day D
select count(distinct user_id) from usage_events
where tenant_id = '72e29f67-39f7-42bc-a4d5-d6f992f9d790'
  and user_id is not null
  and created_at >= 'D 00:00:00-04'::timestamptz
  and created_at <  'D 00:00:00-04'::timestamptz + interval '1 day';

-- (b) retention numerator/denominator, phase-aligned
with cohort as (
  select distinct user_id from usage_events
  where tenant_id = '72e29f67-39f7-42bc-a4d5-d6f992f9d790'
    and user_id is not null
    and created_at >= :ps and created_at < :cs)
select
  (select count(*) from cohort) as cohort_size,
  (select count(*) from cohort c where exists (
     select 1 from usage_events ue
     where ue.user_id = c.user_id
       and ue.tenant_id = '72e29f67-39f7-42bc-a4d5-d6f992f9d790'
       and ue.created_at >= :cs)) as returned;

-- (c) new customers this cycle
select count(*) from user_profiles
where tenant_id = '72e29f67-39f7-42bc-a4d5-d6f992f9d790'
  and is_admin is not true and is_paper is not true
  and created_at >= :cs;
```

(Adjust the `-04` offset if DST has changed; the page buckets by local
days.) 3/3 must match.

### Step 6 — Close
Tick § 8, flip Status to Complete + date, update the CLAUDE.md
planned-session pointer, `/wrap-up`.

## 7. Verification gates

| Gate | What | Pass condition |
|---|---|---|
| V1 | Page-script syntax check | parses clean |
| V2 | Unit + Playwright regression | all existing specs green |
| V3 | Manual staging checklist (Step 4) | every box ticked, confirmed by Rick |
| V4 | SQL cross-check (Step 5) | 3/3 exact match, admin filter OFF |
| V5 | Isolation | inherited coverage — no new tables/RPCs/service calls in the diff (v2 § 5 precedent, Rick's 2026-07-16 call); confirm the diff introduces none |

## 8. Completion criteria

- [x] All deltas on Executive + Operations KPIs are cycle-anchored; no
      trailing-window comparison remains except panels listed OUT in § 3
- [x] Overlay card live with deadline marker, table fallback, empty states
- [x] New Customers tile live
- [x] Metric-definitions panel matches every changed formula (including the
      `prevPrevStart*` approximation label)
- [x] V1–V5 green
- [x] No schema/RLS/Edge Function/`_log()` changes in the diff
- [x] Merged to staging ff-only; pushed; this doc flipped to Complete;
      CLAUDE.md pointer updated

## 9. Rollback

Single-file page, no schema changes: revert the merge commit on staging (or
redeploy the prior commit). No data to unwind.

## References

- `analytics.html` — live 3-tier page (read from disk; `fa8d4a5` + `a151896`)
- `docs/analytics-v2-engagement-dashboard.md` — § 6 palette (validated), § 5
  V5 inherited-isolation precedent; panel list is STALE for the current page
- `docs/analytics-v2-mockup.html` — SVG chart reference only
- `docs/technical-reference.md` § 4.3, § 4.8, § 4.9, § 6.6, § 13 F89/F90
- CLAUDE.md — Local Date Pattern, SQL authoring rules, merge gate
