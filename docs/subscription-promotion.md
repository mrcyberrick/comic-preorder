# Subscription Promotion — catalog banner + post-reserve prompt

**Status:** **Complete — live in production, 2026-07-17.** All steps done,
V1–V5 green, Rick's staging visual sign-off received, prod-promoted via
PR #86 (`107fc0a`), post-deploy write-smoke passed, banner enabled with
final copy on both staging and production founding tenants (verified live
via `resolve_tenant_by_slug`, not just SQL Editor output).
**Target:** staging first (standard flow), then explicitly promoted to
production the same session at Rick's request.
**Perk/copy decision:** resolved 2026-07-17 — Rick confirmed the informational
copy ("Subscribe to a series and never miss an issue — auto-reserved every
month.") as final; no separate discount/perk needed. The mechanics were built
and merged **dark** first (banner config absent ⇒ nothing renders) before
that decision, per the original plan.
**Origin:** July 2026 engagement analysis (report artifact:
https://claude.ai/code/artifact/2b826ea1-67ea-42c9-aa81-40e165dee877 — Action 2)
plus the 2026-07-17 discoverability finding: subscribe is invisible on the
catalog's primary flow (see § 2).

---

## 1. Goal

Raise subscription adoption (currently **0 of 5** reserving customers; the one
existing subscriber reserves $10.98/mo vs $213.66/mo à-la-carte average) by
fixing discoverability at the two highest-leverage points:

1. **Pinned promo banner** on the catalog page announcing the subscription
   value proposition — per-tenant, dismissible, config-driven, ships disabled.
2. **Post-reserve subscribe prompt** — when a customer reserves a standard
   cover, offer one-tap "Subscribe to {series}" at the moment of demonstrated
   intent.

Explicitly rejected alternative: subscribe buttons on catalog cards (mobile
real-estate clutter, equal-weight placement of a standing commitment next to a
one-month action, and per-card inconsistency since only standard covers
qualify).

## 2. Current state — verified 2026-07-17

Line refs verified this date; **re-verify byte-exact at execution** (File
Drift Prevention).

- The subscribe control exists **only** in the catalog detail modal
  (`#modal-subscribe`, catalog.html:202). Eligibility gate (catalog.html:1096–1097):
  `comic.series_name && !AdminContext.isActive() && isStandardCoverItem && !isPending`
  where standard = `variant_type` null / `'Standard'` / `'Primary Title'`.
  Subscription key: `` `${series_name}||${distributor}` `` (catalog.html:1098);
  `mySubscriptions` loaded near catalog.html:471.
- Card-grid reserve is one-tap (`.btn-reserve` → `toggleReserve()`,
  catalog.html:897; success toast at catalog.html:938). A customer can reserve
  every month **without ever opening the modal**, so subscribe is invisible on
  the primary flow.
- `toast(message, type)` (app.js:1279) is text-only, 3.5 s, no action button.
- The write is `Subscriptions.subscribe(user.id, series_name, distributor,
  format || null)` (called at catalog.html:1115). `UsageEvents.subscribe`
  (app.js:685–687) logs event_type `subscribe` with `{series_name,
  distributor}` metadata. **Pre-flight must locate the exact caller** of
  `UsageEvents.subscribe` (Subscriptions API vs page code) before adding the
  `source` field.
- `tenants.branding` (jsonb, default `{}`) is per-tenant and **public by
  design** — returned by the slug→id RPC and rendered by `Branding.apply()`
  since 5.3 (technical-reference.md § slug→id RPC; "branding is intentionally
  public"). Founding tenant branding is `{}` on both environments.
- `app_settings` was considered and **rejected** as the config home: its PK on
  `key` alone is the F6 multi-tenant collision trap, and banner content is
  public display data — exactly what `branding` exists for. Using `branding`
  means **zero schema change**.
- The FOC deadline banner renders near catalog.html:422; the promo banner
  slots directly below it.
- July analytics journey: 6 browse → 6 reserve → 5 manage list → **0 subscribe**.

## 3. Scope

### IN

1. **`toastAction()` helper** (app.js, beside `toast()`): message + one action
   button + Dismiss, configurable duration (default ~8 s), both themes,
   keyboard-focusable action, `prefers-reduced-motion` respected. Styles in
   style.css.
2. **Catalog promo banner**, driven by `tenants.branding.promo_banner`:
   ```json
   { "enabled": true, "id": "sub-promo-1", "text": "…perk copy…",
     "link_text": "Learn more", "link_href": "subscriptions.html" }
   ```
   - Absent key or `enabled: false` ⇒ nothing renders (ships dark).
   - Dismissible; dismissal persisted in localStorage keyed by tenant slug +
     `id` (changing `id` re-shows a new campaign).
   - Hidden for users who already have ≥1 active subscription.
   - Hidden during admin impersonation.
   - Placed below the FOC deadline banner; styled for both themes; no layout
     shift for the card grid (banner occupies normal flow, not overlay).
3. **Post-reserve prompt**: on a successful **reserve** (never cancel) of an
   item passing the same eligibility gate as the modal subscribe button, and
   where the series is not already subscribed:
   - Replace the standard "Reserved!" toast with a `toastAction`:
     "Reserved! Subscribe to {series} and never miss an issue?" → [Subscribe].
   - Accept calls `Subscriptions.subscribe` with the same args as the modal
     path, updates `mySubscriptions`, refreshes the modal button state if the
     modal is open, and shows the standard subscribed toast.
   - Frequency guards: max **one prompt per page load**; a declined/ignored
     series is remembered per device (localStorage set) and never re-prompted;
     applies to both card-grid and modal reserve paths.
4. **Attribution**: subscribe usage events carry `source:
   'post_reserve_prompt'` vs `'modal'` in metadata (no new event_type — the
   analytics event breakdown is untouched).
5. **Playwright specs** (local suite, never committed): banner
   show/dismiss/persist/re-show-on-new-id; prompt appears on standard-cover
   reserve, absent on variant/cancel/already-subscribed, accept subscribes,
   decline is remembered.
6. Docs: this plan's status upkeep + CLAUDE.md pointer line.

### OUT — stop and ask

- The perk itself (pricing/policy — Rick's decision; plan is copy-agnostic).
- Admin UI for editing banner content (v1 is SQL-only via `branding` update).
- Email/notification-based promotion (F72 email-branding territory).
- Banner/prompt **impression** logging (would add new event_types; measure v1
  via the `source` field + subscription counts; revisit if data is needed).
- Subscribe buttons on catalog cards (rejected — § 1).
- Any schema change, Edge Function change, or tenant-2 (`comicstore`)
  enablement.
- Any change to `UsageEvents._log()` behavior (F87-candidate territory).

## 4. Runbook

### Step 0 — Pre-flight
- `/preflight`; branch `feature/subscription-promotion` off up-to-date staging.
- Re-verify every § 2 anchor byte-exact (`Select-String` / view before any
  `str_replace`); halt on mismatch.
- Locate the `UsageEvents.subscribe` call site; confirm `Branding.apply()`
  exposes the branding object (or where `TenantContext` caches it) so the
  banner can read `promo_banner` without a second fetch.
- Confirm how `mySubscriptions` is populated and whether banner render must
  await it (hide-if-subscribed rule) — if it renders earlier, hide reactively.

### Step 1 — `toastAction()` + styles
app.js (beside `toast()`, app.js:1279) + style.css. Both themes; focus-visible
state on the action button.

### Step 2 — Promo banner
catalog.html: render after tenant/branding resolution, below the FOC banner
block (catalog.html:~422). Dismissal wiring + localStorage. Gating per § 3.2.

### Step 3 — Post-reserve prompt
catalog.html `toggleReserve()` success path (reserve branch only,
catalog.html:~938): eligibility + frequency guards per § 3.3; accept path
mirrors the modal handler (catalog.html:1103–1125).

### Step 4 — Attribution
Thread `source` through to the subscribe usage-event metadata (call site found
in Step 0). Modal path logs `'modal'`, prompt path `'post_reserve_prompt'`.

### Step 5 — Local verification
- New Playwright specs (§ 3.5) added to the local suite; full
  `.\run-smoke.ps1` green (do not edit any `.ps1`; if one is touched anyway,
  apply the BOM-restore rule from CLAUDE.md).
- Manual browser pass: both themes, 375 px mobile width, banner + prompt +
  card grid layout, FOC banner unaffected.

### Step 6 — Staging enable + gates
- **DB step (Rick-in-the-loop, `/sql-check` first):** on staging, set a TEST
  `promo_banner` on the founding tenant's `branding` jsonb (merge, don't
  overwrite existing keys). Verify via the live staging site, not just SQL.
- Run V1–V5. All green ⇒ `/deploy-staging` (ff-only; smoke gate inside).
- Update this doc's status + deploy log; tick completion boxes as earned.

**Prod promotion is not part of this plan's scope** — separate explicit
request via `/promote-prod`, plus a prod `branding` SQL step with the final
perk copy, plus post-deploy write-smoke including one prompt-driven subscribe
→ verify row + `source` metadata → unsubscribe.

## 5. Verification gates

- **V1 — banner matrix:** absent config ⇒ nothing; enabled ⇒ renders below FOC
  banner; dismiss ⇒ gone; reload ⇒ still gone; new `id` ⇒ reappears;
  subscribed user ⇒ hidden; admin impersonation ⇒ hidden; both themes; 375 px.
  **GREEN 2026-07-17** — `09-promo-banner.spec.ts`, 5/5 tests, against the
  per-run synthetic tenant. 375px viewport not separately asserted (existing
  `.deadline-banner`-style flex layout with no fixed widths; same pattern
  already relied on elsewhere in the app) — flagged here rather than silently
  assumed.
- **V2 — prompt matrix:** standard-cover reserve ⇒ prompt; variant reserve ⇒
  none; cancel ⇒ none; already-subscribed series ⇒ none; declined series,
  later reserve ⇒ none; second eligible reserve same page load ⇒ none;
  admin impersonation ⇒ none.
  **GREEN 2026-07-17** — `10-post-reserve-prompt.spec.ts`, all matrix cases
  covered as separate tests, 9/9 passing.
- **V3 — accept path:** subscription row lands with correct `tenant_id`,
  series, distributor, format; `usage_events` subscribe row carries `source`;
  modal shows ★ Subscribed if opened after; unsubscribe still works.
  **GREEN 2026-07-17** — `10-post-reserve-prompt.spec.ts` "accept path" test;
  DB-verified via direct PostgREST reads (not just UI), polled to avoid a
  read-before-write race against the fire-and-forget `usage_events` insert.
- **V4 — regression:** full existing smoke suite green; reserve/cancel toasts
  unchanged when prompt doesn't fire; no card-grid layout shift.
  **GREEN 2026-07-17** — full `run-smoke.ps1`: 30 unit tests + 32 Playwright
  tests (specs 01–10), 0 failures.
- **V5 — staging live check:** TEST banner visible on
  https://staging.pulllist.pages.dev/ catalog; Rick visual pass both themes.
  **GREEN 2026-07-17.** Rick ran the SQL (founding tenant `branding` merge
  confirmed clean — only `promo_banner` added, no other keys touched).
  Initial check found the banner hidden: his staging test account had 5
  active subscriptions, correctly triggering the hide-if-subscribed rule
  (confirmed via a live browser-console diagnostic reading `TenantContext`/
  `AdminContext`/`Subscriptions.getAll` directly — not guessed). After
  temporarily clearing subscriptions via the Subscriptions page, the banner
  rendered — but visually competed with the red FOC deadline banner directly
  above it (same accent-red tint/border on both). Fixed by switching
  `.promo-banner` to a neutral `bg-elevated`/`border` card (commit
  `60dadd5`); the "Learn more" link keeps `var(--accent)` so per-tenant
  branding color is still reflected there. Rick confirmed the fix looks
  right on staging. `09-promo-banner.spec.ts`'s custom-color test was
  retargeted from the banner border to the link color to match.

## 6. Completion criteria

- [x] Steps 0–6 complete; all § 2 anchors re-verified at execution (2026-07-17,
      byte-exact — all matched, no drift found)
- [x] V1–V5 all green (evidence noted in this doc)
- [x] Playwright specs added to local suite; full run green — 32/32
      (`run-smoke.ps1`, 2026-07-17: 30 import-script unit tests + specs 01–10,
      including new 09-promo-banner.spec.ts [5 tests] and
      10-post-reserve-prompt.spec.ts [9 tests])
- [x] Merged to staging `--ff-only`; pushed; CF Pages staging deploy verified
      (commit `4b4da8f`, verified live via `promo-banner` DOM marker +
      `toastAction` in deployed app.js; follow-up styling fix `60dadd5`
      pushed and verified live after Rick's V5 visual pass)
- [x] Staging TEST banner enabled and verified live — Rick ran the SQL and
      confirmed the fix visually on 2026-07-17 (see V5 above)
- [x] This doc's status updated; CLAUDE.md pointer line updated
- [x] Out-of-scope discoveries filed — see § Session notes below (README.md
      staleness noted, not filed as an F-number; too minor/local for the
      formal findings index)
- [x] Promoted to production — PR #86 merged (`107fc0a`), CF Pages prod
      deploy verified live, post-deploy write-smoke passed (Rick), banner
      enabled with final copy on both environments (see § Production
      promotion below)

### Production promotion (2026-07-17)

Rick decided the informational copy was final (no perk/discount needed) and
requested prod promotion directly. Followed `/promote-prod`:
- Merge `staging` → `main` with `git checkout main -- config.js` (prod
  credentials preserved, confirmed not in PR diff); F59 check clean —
  `app.js` differs from main as expected, `mylist.html`/`arrivals.html`/
  `admin.html` correctly identical (this feature never touched them).
- PR #86 → merged by Rick → `107fc0a` on `main`.
- Prod deploy verified live via `promo-banner` DOM marker + `toastAction` in
  the deployed `app.js` (`https://pulllist.app/`).
- Post-deploy write-smoke: Rick reserved + cancelled one item on prod as a
  real user — passed.
- Banner SQL: staging `[TEST]` prefix stripped, campaign id finalized to
  `sub-promo-1`; same real copy added to the **production** founding tenant
  (`20941129-c35a-476d-ae21-44b8f77af89c`) — that `branding` key didn't exist
  there before. Both verified **live** (not just SQL Editor output) via the
  public `resolve_tenant_by_slug` RPC — staging slug `raysandjudys`, prod
  slug `rjbookstop` (these differ; see technical-reference.md § 13 F71
  history — same gotcha rediscovered and confirmed against live data rather
  than assumed).

### Deploy sequencing note (2026-07-17)

Discovered mid-session: `playwright.config.ts`'s `baseURL` is hardcoded to
`https://staging.pulllist.pages.dev/` with no local-preview override, so
brand-new Playwright specs (09, 10) cannot pass until their target code is
actually deployed — the generic "smoke gate before push" ordering in
CLAUDE.md's Standard Deployment Workflow assumes the suite already covers
what's being pushed, which doesn't hold for genuinely new UI. Precedent:
spec 08 (`branding-unit`) was added in Phase 5.3 S5, after `Branding.apply()`
was already live from an earlier S in that sub-deploy.

Resolution (confirmed with Rick): pushed the merged code to staging first
(low-risk, staging iteration is explicitly encouraged), then wrote and ran
the new specs against the now-live code, then re-ran the full suite as the
real gate. New Playwright DB fixtures (`mergeTenantBranding`,
`getTenantBranding` in `fixtures/tenant.ts`; `seedSubscription`,
`getSubscription`, `getLatestUsageEvent` in `fixtures/catalog.ts`) only ever
write to the per-run synthetic tenant, never the founding tenant, per the
suite's existing rule in `playwright/README.md`.

### "Both themes" clarification (confirmed with Rick, 2026-07-17)

PULLLIST has one theme (dark editorial, single `:root` variable set — no
toggle exists anywhere in the codebase). "Both themes" in this plan's V1/V2
gates means: default `--accent` vs. a tenant's custom
`branding.primary_color` override (which `Branding.apply()` applies site-wide
since 5.3). All new CSS uses `var(--accent)` etc. so it inherits branding
automatically; `09-promo-banner.spec.ts`'s last test asserts the "Learn more"
link color follows a custom `primary_color` (retargeted from the banner's own
border after the neutral-card styling fix — see § 6 V5 evidence).

### Session notes / out-of-scope discoveries

- `playwright/README.md` line 19 (`STAGING_REDIRECT_URL` example) still shows
  the retired GitHub Pages URL; the actual `.env` value is already correct
  (`https://staging.pulllist.pages.dev/catalog`). Doc-only staleness in a
  local, never-committed file — noted here rather than filed as a
  technical-reference.md finding.

## 7. Rollback

Client-code + data only; no schema, no Edge Functions, no config.js.
- Banner off (either environment): SQL `enabled: false` (or remove the
  `promo_banner` key) on that environment's `tenants.branding` — no deploy
  needed. Staging and prod are independent — toggling one does not affect
  the other.
- Full code rollback: revert the merge — on `staging` for the pre-prod state,
  or via a new PR reverting `107fc0a` on `main` for production (prod is a
  protected branch via PR flow, same as the original promotion).
- Subscriptions created via the prompt are **real customer intent — never
  mass-delete** as part of rollback, on either environment (production now
  carries real customer data for this feature going forward).

## References

- Engagement report (Action 2 + ranking): artifact link in header
- `docs/analytics-v2-engagement-dashboard.md` — plan-format + process precedent
- `docs/technical-reference.md` — § slug→id RPC / branding (5.3), § 13 F6
  (app_settings PK trap), § 13 F72 (email branding, OUT here)
- CLAUDE.md — deployment workflow, merge gate, SQL authoring rules
