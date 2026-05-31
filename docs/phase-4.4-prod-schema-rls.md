# Phase 4.4 — Prod schema: RLS + functions + default removal

**Status:** Planning — plan drafted 2026-05-31; runbook ready (`phase-4.4-runbook.md`)
**Parent plan:** `docs/phase-4-production-migration.md` (sub-deploy row 4.4)
**Branch (migration artifact):** `feat/phase-4-prod-cutover` (production repo; committed, **held for the 4.6 PR — not pushed to `origin main`**)
**Branch (docs):** `staging` (doc-only commits go to `staging` directly per `CLAUDE.md` § Document Integrity)
**Cutover-window slot:** Sat afternoon (`apply 4.4 + smoke gate`)
**Execution model:** CLI-orchestrated, Rick-in-the-loop. The CLI writes the migration artifact and runs all repo/doc steps itself; every **production-database** step is handed to Rick to run in the Supabase **prod** SQL Editor, pausing for pasted results before continuing. Self-contained — no chat context required.

---

## Goal

Bring the production database to post-Phase-3 staging parity for the RLS / function / default layer, fronted by `app_settings.maintenance_mode = true` (already ON since the 4.2 pre-flight; **stays ON** — toggled off in 4.6 part 2, not here).

Prod is pre-tenant at this layer: policies use the old `is_admin()` with **no** `current_tenant_id()` scoping; the catalog/reservation functions are the 2-arg pre-tenant versions; the two helper functions and the two newer functions don't exist on prod. 4.4 converts all of it to the staging-target shape.

---

## In scope (six parent-plan items, as reconciled against live captures)

| # | Parent-plan item (line ref) | 4.4 action | Source of truth |
|---|---|---|---|
| 1 | Phase 1.3 RLS + helpers + 3 function signature migrations (146) | Create `current_tenant_id()` + `current_user_is_admin()`; DROP+CREATE the 3 functions with `p_tenant_id uuid` first param; full RLS rewrite | Staging live defs (captured 2026-05-31) |
| 2 | Phase 3.3 column-default removal (147) | **Verify-only** — prod has zero `tenant_id` defaults; defensive `DROP DEFAULT` included | Live capture: no rows |
| 3 | Phase 3.4 analytics view tenant retrofit (148) | **CARVED OUT — see Finding F55.** No staging target exists | — (blocked) |
| 4 | Phase 3.5 `purge_old_usage_events` (149) | CREATE (absent on prod) | Staging live def |
| 5 | Phase 3.6 `auto_fulfill_past_on_sale` (150) | CREATE (absent on prod); `SECURITY DEFINER`, `search_path=public`, `EXECUTE` to `service_role` only | Staging live def + parent plan |
| 6 | 3.8-era F4/F15/F16/F20/F34 (151) | F15 + F16 **subsumed** by the RLS rewrite; F20 = `get_popular_series` `CREATE OR REPLACE`; **F34 → 4.6 (Edge Function); F4 → 4.6 app-code + post-cutover data drop** | Staging live defs |
| EN2 | 4.3 carry-forward: staging policy-drift verification | Done (see below); reconciliation = Decision A | This document |

New functions (items 4, 5) carry the F23 `SET search_path = public` hardening the parent plan requires (line 175).

---

## Decisions

**Decision A — RLS role targeting: NORMALIZE to `{authenticated}` (applied in the runbook).**
Staging policies are a mix of `{public}` and `{authenticated}` with no consistent principle. Mirroring `{public}` on prod would reverse your 4.3 Option A (all prod policies upgraded to `{authenticated}`) on the very same tables and re-import the drift EN2 exists to catch. Normalizing prod to `{authenticated}` is functionally identical (every qual depends on `auth.uid()`-derived helpers, which resolve false for `anon`) and consistent with 4.3. **Companion task (staging-only, outside the cutover window):** normalize staging's `{public}` policies to `{authenticated}` so the Phase-level `pg_policies` parity check (parent plan line 190) passes. SQL block in the runbook appendix.

**Decision B — RESOLVED 2026-05-31 against `admin.html` + `app.js`; splits by table.**
- **`catalog` → match staging (read-only).** Every authenticated-client `.from('catalog')` call in both files is `.select(...)` (counts, listings, publisher facets, popular-series aggregation). No insert/update/upsert/delete via the authenticated key; catalog writes are service-role import-script only. Prod's `Admins can modify catalog` (ALL) is dead surface area — **dropped, not recreated.**
- **`user_profiles` → RETAIN admin-write (intentional divergence from staging; filed F58).** `Users.suspend` (`app.js:914`, UPDATE status) and `Users.deleteProfile` (`app.js:923`, DELETE, invoked at `admin.html:1608`) are admin mutations through the **authenticated** client, not service-role. (`has_seen_welcome` at `app.js:1168` is a self-write, covered by `users update own profile`.) Staging's captured policy set has no authenticated-key admin-write on `user_profiles`; mirroring that omission on prod would break the admin Users tab with an RLS violation. The runbook keeps `admins manage tenant profiles`. This is a deliberate exception to "match staging" — the live code is the higher authority. Staging must be audited (F58) to learn whether it routes these through an unseen Edge Function or is itself latently broken.

**Decision C — scope item 6 (resolved):** F15 + F16 via the RLS rewrite; F20 via `get_popular_series`; F34 routed to 4.6; F4 routed to 4.6 + post-cutover. No objection expected; flagged for explicit sign-off.

---

## EN2 result (4.3 carry-forward, closed)

The recursive `EXISTS (SELECT 1 FROM user_profiles …)` anti-pattern F46 was created for is **absent from every staging policy** — the worst-case drift is clean. The only residual drift is the `{public}`/`{authenticated}` role inconsistency, reconciled by Decision A. EN2 is closed.

---

## Findings filed (next-available ID confirmed = F55; this session files F55–F58)

- **F55 — production has 5 `analytics_*` views with no staging counterpart.** Prod has `analytics_daily_events`, `analytics_top_cancelled`, `analytics_top_reserved`, `analytics_top_subscribed`, `analytics_user_activity` as plain, untenanted views. Staging has none of them in any object form (only `admin_preorders`). The parent plan's "retrofit to match staging" (line 148) is not executable — there is no staging target. Resolution requires `analytics.html`/`app.js` (how staging serves analytics) + a drop-vs-retrofit decision. **Blocks scope item 3 only; carved out of the 4.4 runbook.**
- **F56 — `claim_paper_account(uuid, uuid)` still present on production.** Dropped on staging 2026-05-26 (Phase 4.1 C3, per F33). Prod retains it. Dead-code cleanup, out of scope for 4.4; would be caught by the Phase-level structural-diff completion criterion. Catalog for a post-cutover cleanup pass.
- **F57 — `generate_invite_link(text, text)` present on production, absent on staging.** `SECURITY DEFINER`, no staging counterpart. Same disposition as F56 — surfaced, not touched in 4.4.
- **F58 — staging RLS lacks an authenticated-key admin-write policy on `user_profiles`, but the app requires one.** `Users.suspend` (UPDATE) and `Users.deleteProfile` (DELETE) run via the authenticated client from the admin UI. The staging policy capture (2026-05-31) shows only `admins view tenant profiles` (SELECT), `users view own profile`, `users update own profile` — no admin ALL/UPDATE/DELETE. Either staging routes these through an unseen service-role Edge Function, or staging's admin suspend/delete is latently broken. **4.4 keeps the policy on prod** (so prod is correct); staging needs an audit to reconcile, after which the Phase-level `pg_policies` parity check (line 190) is expected to show this one intentional prod-extra until staging is fixed. Open.

---

## Completion criteria (4.4)

- [ ] `current_tenant_id()` and `current_user_is_admin()` exist on prod, `SECURITY DEFINER`, `STABLE`, `search_path=public`, bodies match staging
- [ ] `archive_stale_reservations`, `delete_dropped_catalog_items`, `purge_stale_catalog` exist on prod with `p_tenant_id uuid` first param, `SECURITY DEFINER`, `search_path=public`; old 2-arg signatures gone
- [ ] `purge_old_usage_events`, `auto_fulfill_past_on_sale` created; `auto_fulfill_past_on_sale` EXECUTE granted to `service_role` only
- [ ] `get_popular_series` body includes `AND c.tenant_id = current_tenant_id()` + `search_path=public` (F20)
- [ ] Every tenant-scoped table's RLS matches the staging-target policy set, role-normalized to `{authenticated}` (Decision A); `tenants` has RLS enabled + its 2 policies
- [ ] F15 (weekly_shipment `true` → tenant) and F16 (preorders OR-pattern → split) verified gone from prod
- [ ] Default-removal verify: zero `tenant_id` defaults on prod
- [ ] Tenant-isolation smoke gate green (founding-tenant session sees only founding-tenant rows; service-role import RPCs resolve)
- [ ] Decision B resolved (kept-and-flagged, or dropped-to-match-staging) and recorded
- [ ] Migration artifact committed to `feat/phase-4-prod-cutover` (held for 4.6 PR)
- [ ] Parent-plan 4.4 row → Complete + date; `CLAUDE.md` active-sub-deploy pointer → 4.5; F55–F57 in `technical-reference.md` § 13
- [ ] Analytics (item 3 / F55) dispositioned: either re-folded into a 4.4 addendum once unblocked, or explicitly re-scoped in the parent plan

---

## Rollback (Tier-1 / Tier-2 per parent plan; complexity = Medium)

Exact reverse SQL is in the runbook appendix — recreate the captured prod policies, DROP the 3-arg functions and recreate the captured 2-arg bodies, drop the 4 new functions + 2 helpers, revert `get_popular_series`. Because 4.4 applies with maintenance mode ON and no customer traffic, a failed smoke gate is Tier-1: roll back 4.4 SQL only, prior sub-deploys stay applied, window aborts.

---

## References

- Parent plan: `docs/phase-4-production-migration.md` (4.4 row; in-scope lines 146–151; out-of-scope line 174–175)
- Prior sub-deploy: `docs/phase-4.3-prod-schema-constraints.md`
- Findings: `docs/technical-reference.md` § 13 (F15, F16, F20 fixes 2026-05-10; F45 archive DEFINER; new F55–F57)
- Captures (staging target + prod current): chat session 2026-05-31
- Runbook: `docs/phase-4.4-runbook.md`
