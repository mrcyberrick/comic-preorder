# Subscription Promotion — catalog banner + post-reserve prompt

**Status:** Draft — planned 2026-07-17. Not started.
**Target:** staging only (standard flow; prod promotion is a separate explicit request)
**Blocking input:** the subscription perk/value decision (Rick — pricing/policy).
The mechanics below can be built and merged **dark** (banner config absent ⇒
nothing renders) before that decision; enabling the banner is a data-only SQL
step once copy is final.
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
- **V2 — prompt matrix:** standard-cover reserve ⇒ prompt; variant reserve ⇒
  none; cancel ⇒ none; already-subscribed series ⇒ none; declined series,
  later reserve ⇒ none; second eligible reserve same page load ⇒ none;
  admin impersonation ⇒ none.
- **V3 — accept path:** subscription row lands with correct `tenant_id`,
  series, distributor, format; `usage_events` subscribe row carries `source`;
  modal shows ★ Subscribed if opened after; unsubscribe still works.
- **V4 — regression:** full existing smoke suite green; reserve/cancel toasts
  unchanged when prompt doesn't fire; no card-grid layout shift.
- **V5 — staging live check:** TEST banner visible on
  https://staging.pulllist.pages.dev/ catalog; Rick visual pass both themes.

## 6. Completion criteria

- [ ] Steps 0–6 complete; all § 2 anchors re-verified at execution
- [ ] V1–V5 green (evidence noted in this doc)
- [ ] Playwright specs added to local suite; full run green
- [ ] Merged to staging `--ff-only`; pushed; CF Pages staging deploy verified
- [ ] Staging TEST banner enabled and verified live (or explicitly deferred
      with Rick's sign-off if copy is still pending)
- [ ] This doc's status updated; CLAUDE.md pointer line updated
- [ ] Out-of-scope discoveries filed via `/file-finding`, not fixed inline

## 7. Rollback

Client-code + data only; no schema, no Edge Functions, no config.js.
- Banner off: SQL `enabled: false` (or remove the `promo_banner` key) — no
  deploy needed.
- Full rollback: revert the merge on staging (standard flow).
- Subscriptions created via the prompt are **real customer intent — never
  mass-delete** as part of rollback.

## References

- Engagement report (Action 2 + ranking): artifact link in header
- `docs/analytics-v2-engagement-dashboard.md` — plan-format + process precedent
- `docs/technical-reference.md` — § slug→id RPC / branding (5.3), § 13 F6
  (app_settings PK trap), § 13 F72 (email branding, OUT here)
- CLAUDE.md — deployment workflow, merge gate, SQL authoring rules
