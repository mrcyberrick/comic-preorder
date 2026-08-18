# Mobile nav regression coverage — spec 18, and retiring the temp spec

**STATUS:** NOT STARTED | staging=— | prod=N/A (test-only) | findings=F103
**Status:** **PLANNED — not started.** Written 2026-08-18.
**Target:** the **local Playwright suite only**. No repo app code, no DDL, no production.
**Last verified against live:** 2026-08-18 — `origin/staging` `13a95e1`, `origin/main` `47d42dd`,
working tree clean. The suite is 113 Playwright tests across 18 files (incl. one temp spec).

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

## References

- `docs/mobile-nav-tab-bar.md` § 8 — what shipped, and the two defects named in § 2.
- `docs/phase-3.7-playwright-smoke-tests.md` — canonical suite detail.
- `docs/technical-reference.md` § 13 **F103** (why zero-coverage paths ship defects), **F115** (the
  alternative use of this slot).
- `CLAUDE.md` § Smoke Test Suite (targeted-vs-full discipline; what the suite is and isn't good at),
  § Files That Must Stay in Sync (the six-page set, incl. `analytics.html`).
