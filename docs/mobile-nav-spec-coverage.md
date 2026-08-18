# Mobile nav regression coverage — spec 18, and retiring the temp spec

**STATUS:** COMPLETE | staging=2026-08-18 (local suite only) | prod=N/A (test-only) | findings=F103
**Status:** **COMPLETE — executed and gated green 2026-08-18.** Written 2026-08-18.
**Target:** the **local Playwright suite only**. No repo app code, no DDL, no production.
**Last verified against live:** 2026-08-18 — `origin/staging` `13a95e1`, `origin/main` `47d42dd`,
working tree clean at session start. The suite was 113 Playwright tests across 18 files (incl. one
temp spec) at session start; **126 tests across 19 files** (temp spec promoted, spec 18 added) at
session close — see § 7 V3 and § 9.

---

## 1. Goal and honest scope

Add **regression** protection to the mobile nav shipped 2026-08-16 (PR #123 plus its follow-up
cycle), and retire or promote the leftover temp spec.

**This session does not validate what shipped.** Rick verified the tab bar by eye on real devices
during both the original session and the follow-up cycle, and per CLAUDE.md's standing rule that is
the only evidence that counts for CSS legibility — Playwright asserts behaviour, not whether
something renders readably at 375px. The value here is catching a **future** break, and it is
insurance rather than urgent work.

**Deliberately narrow.** CLAUDE.md's measured note (2026-08-09) says the suite is weakest on
brand-new paths, because a spec written alongside the code inherits the code's assumptions — and a
spec written now, against code that already works, mostly locks in current behaviour. So this is
scoped to **the two defects that already occurred** plus the cheapest structural invariants, not a
broad "cover the tab bar" effort. Three or four assertions, not twenty.

---

## 2. Why these assertions and no others

`TabBar` and `NavSearch` are injected by `app.js` into **all six** nav pages, so a regression breaks
navigation across the whole app on the surface most customers use. Two real defects already bit this
code, and both are exactly what a test catches cheaply — neither throws, neither fails a page load,
and no existing spec would notice either:

| Defect (already shipped and fixed) | Why invisible | Assertion |
|---|---|---|
| `window.location.pathname` never carried `.html`, because Cloudflare Pages 308-redirects clean URLs — so `.nav-links a.active` **and** the tab bar's active-cell detection matched nothing at all | Page loads fine; nav simply never highlights | A1 |
| `.nav-user` had no explicit flex `order`, so opening the hamburger wrapped the entire header off-screen | Only manifests with the menu **open**, at narrow width | A3 |

The remaining two cover the structural invariants whose breakage would be silent and app-wide.

---

## 3. Assertions (all at 375px viewport unless stated)

- **A1 — active cell tracks the current page, through the redirect.** For each of the six nav pages,
  navigate and assert exactly one tab-bar cell carries the active state **and** it is the cell for
  that page. Navigate to the **clean URL** (no `.html`), because that is what a browser and
  Cloudflare Pages actually produce — asserting against `catalog.html` would pass while reproducing
  the original bug.
- **A2 — the tab bar exists on all six nav pages and nowhere it shouldn't.** Six-page presence check.
  `analytics.html` is a full member of the sync set (corrected 2026-08-15 — it was omitted from
  CLAUDE.md's list until then, and a five-file edit would have silently skipped it), so it must be in
  the loop.
- **A3 — opening the hamburger does not wrap the header.** With the menu open, assert the header's
  own bounding box stays within the viewport width and the user block has not been pushed to a new
  row. This is the `order: 4` regression; assert layout geometry, not the CSS property.
- **A4 — `NavSearch` proxies to each page's own filter.** On `catalog`, `mylist`, `subscriptions` and
  `arrivals`, type into the mobile search affordance and assert the page's result set responds.
  `subscriptions.html`'s input was renamed `#series-search` → `#search` in the follow-up cycle, and
  the `NavSearch` gate was once `#search`-only — which also matched `mylist.html`'s **own** filter
  input, and had to be fixed. Assert per page rather than assuming one selector.
- **A5 (optional, only if cheap) — `NavBubble` count reaches the tab bar.** Skip rather than
  contort the fixtures; it is the least likely of the five to regress silently.

---

## 4. The temp spec — a decision, not a chore

`tests/zz-tmp-v4v5-pending.spec.ts` (2 tests) is self-labelled *"TEMPORARY — delete after the gate
is recorded unless Rick chooses to keep it as permanent coverage."* Its own header records why
keeping it is tempting: **the approve/decline click paths had ZERO coverage before it**, and it
catches unguarded writes to removed DOM nodes that only throw *after* the account action has already
succeeded — the button looks like it worked while the page half-updates.

**Default: promote, do not delete** — rename to `19-admin-account-actions.spec.ts`, drop the
"TEMPORARY" header, keep the network stub on approve (it sends real email otherwise). **Rick's call**
if he would rather it go; say which was chosen in the closeout either way. Do not leave it as
`zz-tmp-*` a third session running.

**Decision taken 2026-08-18: promoted, per the stated default** (no explicit override from Rick
this session, and the default's own reasoning — zero pre-existing coverage on approve/decline —
held). Renamed to `tests/19-admin-account-actions.spec.ts`, "TEMPORARY" header replaced with a
promotion note, network stub on approve kept unchanged. Both tests (V4 approve, V5 decline) passed
in the full-suite gate (§ 7 V3). `zz-tmp-v4v5-pending.spec.ts` deleted.

---

## 5. Scope

### IN
- One new spec file (A1–A4, A5 if cheap).
- Promote or delete the temp spec per § 4.
- A closeout note in this doc's § 7 and the STATUS token flipped.

### OUT — stop and ask
- **Any change to `app.js`, `*.html`, `style.css`.** If an assertion fails, that is a **finding**,
  not a licence to edit app code in a test session: stop, describe it, ask (a) fix now as its own
  commit (b) file as F130 (c) ignore. A test session that edits the code under test to make itself
  green is worse than no session.
- Broadening into general mobile-layout coverage, catalog card layout, or anything the mobile plan
  marked out of scope.
- Running anything against **production**. The runner aborts if `SUPABASE_URL` is not staging; do not
  work around it.

---

## 6. Runbook

1. **`/preflight`** — including the new check 7 (doc-status consistency), which should come back clean
   after the 2026-08-18 truth pass. If it flags anything, report it rather than fixing it here.
2. Confirm what staging is actually serving. This session's own commits are doc-only, so the deployed
   build is the **2026-08-17 cover-fallback** build (`origin/staging` `13a95e1`, app files last
   changed at `450c062`). Check the **plain** URL, never a cache-busted one — a query string is a
   different Cloudflare cache key and can serve new bytes while the URL the browser requests is
   still stale. That exact mistake produced a false red on 2026-08-06.
3. Write the spec. **Assert on seeded rows or `data-*` attributes, never `.first()` and never an
   exact count** — staging carries real founding-tenant data (857 backfilled ledger rows, ~9.6k
   catalog rows), and a `.first()` assertion against a real title is how spec 15's first draft broke.
4. Iterate with **targeted runs**: `npx playwright test 18-mobile-nav` (~17s). Do **not** run the
   full suite between edits — it is `workers: 1`, `fullyParallel: false`, ~16 minutes. Seven full
   runs on 2026-08-09 cost ~100 minutes and five of them should have been targeted.
5. § 4's temp-spec decision.
6. **Full suite once, as the gate.** `.\run-smoke.ps1`. Read the **stage markers and counts**, not
   the exit code — `run-smoke.ps1` has previously skipped its entire Playwright stage and still
   exited 0 (the BOM/em-dash failure mode; re-check the BOM if you edit any `.ps1`).

---

## 7. Verification gates

| Gate | Assertion |
|---|---|
| **V1** | A1 fails when pointed at a deliberately broken active-cell check, then passes — the redirect bug specifically, proved reachable |
| **V2** | A3 fails against a copy with `order: 4` removed, then passes |
| **V3** | Full suite green, with counts recorded (expect 113 + new tests, ± the temp-spec decision) |
| **V4** | Zero repo app files modified — `git status` clean except the plan doc |
| **V5** | Any fixture created is torn down, verified by a live SELECT returning zero rows |

V1 and V2 are the point of the session: an assertion that has never been observed failing is
decoration, and both of these guard defects that actually shipped, so the broken-copy demo is cheap
and honest. Record both outputs here.

### V1 — recorded output (2026-08-18)

Demonstrated with a one-off, deleted-after-use spec (`zz-tmp-v1v2-demo.spec.ts`) rather than by
touching the deployed build — pushing a broken bundle to staging just to prove a local assertion
was rejected as disruptive for a test-only session. Instead the DOM was tampered with in-page via
`page.evaluate()` immediately after the real page load, reproducing exactly the state the redirect
bug would have left (`TabBar.mount()` never matching any cell), then the same assertion spec 18
uses was run against it:

```
BROKEN (is-active/aria-current stripped):
  Error: expect(locator).toHaveCount(expected) failed
  Locator:  locator('.tab-cell.is-active')
  Expected: 1
  Received: 0
  → FAILED, as required.

FIXED (same navigation, no tampering):
  → PASSED.
```

A1 is reachable.

### V2 — recorded output (2026-08-18)

Same demo file, real CSS never touched: `page.addStyleTag({ content: '.nav-user { order: 0 !important; }' })`
injected after page load reproduces "order:4 removed" without editing `style.css`.

```
BROKEN (.nav-user forced to order:0):
  console: BROKEN delta y: 66 navUser.y: <n> hamburger after.y: <n>
  Error: expect(received).toBeLessThan(expected)
  Expected: < 5
  Received:   66
  → FAILED, as required.

FIXED (real CSS, no override):
  console: FIXED delta y: 8 navUser.y: <n> hamburger after.y: <n>
  → PASSED.
```

A3 is reachable. The 66px-broken vs. 8px-natural-jitter spread is what calibrated spec 18's actual
threshold (20px — comfortably between the two, see `18-mobile-nav.spec.ts` A3 inline comment).
The first real run of A3 (pre-calibration, threshold 5) failed on the natural 8px jitter — a false
red on the *correct* CSS, not a caught defect — which is exactly why V2's broken-copy number was
needed before trusting a hardcoded threshold.

### V3 — recorded output (2026-08-18)

`.\run-smoke.ps1`, read for stage markers and counts, not exit code:

- **[1/2]** `npm test` (scripts repo unit suite): `172 pass, 0 fail` (was 151 at session baseline —
  unrelated to this session; the scripts repo suite runs independently of the Playwright count).
- **[2/2]** Playwright: **126 passed (17.1m)**, both stages actually executed (no BOM/skip failure
  mode). Baseline was 113 across 18 files (incl. the 2-test temp spec). Reconciles exactly:
  113 − 2 (removed `zz-tmp-v4v5-pending.spec.ts`) + 13 (new `18-mobile-nav.spec.ts`) + 2 (promoted
  `19-admin-account-actions.spec.ts`) = **126**.
- Final line: `All smoke tests passed. Safe to push.`

One real defect surfaced and was fixed during targeted iteration before this gate run (not a
finding — caught and fixed inside this test-only session, no app code touched): the first draft of
the mylist A4 assertion used a bare `getByText(title)` scoped to `#list-container`, which hit a
strict-mode violation — `mylist.html` renders the same item as BOTH a desktop `<table>` row
(`.col-title`) and a mobile card (`.mobile-card-title`) simultaneously in the DOM, one CSS-hidden
per breakpoint rather than absent. Rescoped to `.mobile-card-title` (the one actually visible at
375px). Recorded here because it is exactly the kind of real-DOM surprise CLAUDE.md's suite
philosophy section warns a spec written after the fact can still catch cheaply.

### V4 — recorded output (2026-08-18)

`git status` on the comic-preorder repo at session end: clean except this plan doc (see § 9 below).
`app.js`, `*.html`, `style.css` — zero diff. The Playwright suite itself lives in the private
scripts repo's untracked `playwright/` folder (allowlist-`.gitignore`'d), so its new/renamed spec
files never appear in `git status` for either repo, per design.

### V5 — recorded output (2026-08-18)

Live `SELECT`s (via the staging REST API, service-role key) after the full-suite run:

```
catalog rows (TEST_PW_18_* item_code): 0 row(s)
catalog rows (TEST_PW_18_* title): 0 row(s)
weekly_shipment rows (TEST_PW_18_*): 0 row(s)
user_profiles (pw-18-* test users): 0 row(s)
```

Not zero on the first check, though — worth recording honestly. The first (pre-fix) run of the
mylist A4 test failed on the strict-mode violation above, retried, and the retry then hit
Playwright's 60s test timeout while awaiting the failing assertion; the test's own `finally` block
(which calls `cleanupTestRows` + `deleteUser`) never got to run because the timeout aborted the test
mid-`await`. That left one orphaned `user_profiles` row + auth user (`pw-18-myl-a9cdeafe@example.test`,
id `e7675d2d-af0f-40cf-aebf-a035204eb955`) after `cleanupTestRows`'s own catalog/shipment cleanup
(which ran successfully, timing-wise, before the hang) had already gone through. Found by the same
live-SELECT check this gate requires, not assumed — deleted manually (preorders → profile → auth
user, in that order) and reverified at zero before recording this gate green. No lasting harm (a
single `@example.test` fixture user), but a real illustration of why V5 asks for a live SELECT and
not "the finally block ran."

---

## 8. Notes for whoever runs this

- **The suite is local-only and untracked in every repo** (`catalogs\scripts\playwright\`). Only this
  plan doc and its closeout get committed — same as the F91/F95/F103 test-infra session.
- Nothing here is time-gated. The only armed gate is the DMARC read (Thu 2026-08-20), which is Rick's
  and unrelated.
- **This session is optional and low-urgency.** If Rick would rather spend it on **F115** — a live
  Medium that tells a customer "✓ Order placed" for a book that never arrived, and which turned out
  on 2026-08-18 to have no owner after F108 closed without absorbing it — that is the better use of
  the slot and this plan can wait.

---

## 9. Closeout (2026-08-18, Sonnet CLI)

**Files changed:**
- `catalogs/scripts/playwright/tests/18-mobile-nav.spec.ts` — new, 13 tests (A1–A4; A5 skipped per
  plan default, nothing cheap enough surfaced). Local-only, untracked (scripts-repo allowlist
  `.gitignore`).
- `catalogs/scripts/playwright/tests/19-admin-account-actions.spec.ts` — new, promoted from
  `zz-tmp-v4v5-pending.spec.ts` (§ 4). Local-only, untracked.
- `catalogs/scripts/playwright/tests/zz-tmp-v4v5-pending.spec.ts` — deleted (promoted, not kept).
- This plan doc — STATUS token flipped to COMPLETE, § 4/§ 7 filled in with recorded decisions and
  outputs. The only tracked-repo change this session made.
- No `app.js`, `*.html`, or `style.css` touched, at any point, including during iteration (V4).

**What was verified:** see § 7 V1–V5 above, all green with real recorded output — active-cell
detection through the CF Pages redirect (A1, four tab-bar pages + admin/analytics hamburger-only
case), six-page tab-bar presence incl. `index.html`'s correct absence (A2), header-geometry survival
on hamburger-open calibrated against a measured 66px real break vs. 8px natural jitter (A3), and the
NavSearch proxy reaching all four real page filters — catalog grid, mylist list (both table and
mobile-card renders), subscriptions series search, and arrivals' orphan-reserved titles (A4). Full
suite: 172 unit + 126 Playwright, both green, counts reconciled exactly.

**Left for next time:** nothing outstanding on this plan's own scope. A5 (NavBubble count on the
tab bar) remains unwritten — the plan marked it optional-if-cheap and nothing cheap surfaced; a
future session could add it as one more assertion inside spec 18's A2/A4 fixtures rather than a new
file.

**Out-of-scope discoveries — filed or noted, not fixed:**
- The mylist dual-render (`.col-title` table row + `.mobile-card-title` card, both always in the
  DOM) is pre-existing app behavior, not a defect — just undocumented until this session's test
  hit it. No finding filed; noted in § 7 V3 for whoever next writes a mylist spec.
- One orphaned test-fixture user survived a timed-out retry mid-iteration (§ 7 V5) — found and
  cleaned by this session's own live-SELECT check, not a lasting issue, no finding warranted.
- `/preflight`'s new doc-status check (step 1 of this runbook) flagged `docs/weekly-pipeline-
  consolidation-plan.md`: its top-level `NOT STARTED` status token contradicts a checklist line
  inside the same doc claiming commit `f900247` ("Prod promotion pending, rides the next staging →
  main") — that commit is confirmed already an ancestor of `origin/main` (merged 2026-07-09, well
  before this session). Reported per the runbook's instruction to report rather than fix; this
  session did not touch that doc. Unrelated to mobile-nav scope — Rick's call whether to correct the
  doc or file it.

**New finding IDs:** none. Next free remains **F130**.

---

## References

- `docs/mobile-nav-tab-bar.md` § 8 — what shipped, and the two defects named in § 2.
- `docs/phase-3.7-playwright-smoke-tests.md` — canonical suite detail.
- `docs/technical-reference.md` § 13 **F103** (why zero-coverage paths ship defects), **F115** (the
  alternative use of this slot).
- `CLAUDE.md` § Smoke Test Suite (targeted-vs-full discipline; what the suite is and isn't good at),
  § Files That Must Stay in Sync (the six-page set, incl. `analytics.html`).
