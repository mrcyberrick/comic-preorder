# Admin Restructure — Session 1: Removals

**Parent plan:** `docs/admin-dashboard-process-map.md` (F121). Structure decided
2026-08-07 — **Option B, as modes within one `admin.html`** (parent § 5.7).
**Finding:** `docs/technical-reference.md` § 13 **F121**.

**Status:** Planned 2026-08-07, not started.
**Target:** **staging only.** Production promotion only on Rick's explicit request
after staging verification.
**Branch:** `feature/admin-removals`
**Last verified against live code:** `admin.html` / `style.css` / spec 15 @ `40cc0e8`, 2026-08-07.

---

## 1. Why this is session 1

It is the only piece of the restructure that removes work rather than moving it,
so every later session has less to relocate. It introduces **no new UI**, needs
**no design decision**, and depends on nothing. If it is the only thing that ever
ships, the page is still better.

---

## 2. Scope

### IN

1. **Delete the stats bar** — all seven tiles and the scope caption.
2. **Delete Export All (CSV)** — button, listener, and its now-orphaned
   `makeExportRows()` helper.
3. **Delete the two spec blocks that assert on them.**

### OUT — explicitly, and each for a reason

| Not touched | Why |
|---|---|
| `.stats-bar` / `.stat` / `.stat-value` / `.stat-label` **CSS** | **Used by five pages** — `admin`, `arrivals`, `catalog`, `mylist`, `subscriptions`. Deleting it is a cross-page visual regression. Only the admin markup goes. |
| `exportToCsv()` in `app.js` | Shared with `mylist.html:1160`. Only the admin-local `makeExportRows()` is orphaned. |
| The **Pending tab badge** (`#pending-badge`) | Survives. The pending *count* is not lost — only the duplicate tile. |
| Top Series | Moves to `analytics.html` in **session 3**, not deleted. Separate work, separate session. |
| All Reservations | Retired in **session 2**, after its search is rehomed. Deleting it now would delete the page's only search. |
| Order Follow-Up / Withdrawn panels | Stay. They are alerts with a real job (parent § 5.7.2 P1). |

---

## 3. Changes, with verified locations

Line numbers are from the verification above and **must be re-checked against
disk at execution** — read the range before every edit, halt if it does not match.

### 3.1 `admin.html` — stats bar markup

| Range | Content |
|---|---|
| `139–147` | The 2026-08-07 relabel comment block |
| `148–177` | `<div class="stats-bar">` and all seven `.stat` children |
| `178–179` | `<div id="stats-scope-note">` |

### 3.2 `admin.html` — `renderStats()`

| Range | Content |
|---|---|
| `1154–1195` | `// ── Stats ──` header comment through the close of `renderStats()` |
| `1083` | Its **only** call site, inside `loadData()` — remove the line |

### 3.3 `admin.html` — Export All

| Range | Content |
|---|---|
| `193` | `<button … id="btn-export-all">` |
| `1704–1735` | `// ── Exports ──` comment + `makeExportRows()` (verify the closing brace before the `makeOrderSheetRows` comment block at `1730`) |
| `1770–1778` | The `btn-export-all` click listener |

Keep the `// ── Exports ──` section header if `makeOrderSheetRows()` still sits
under it — check at execution rather than assuming.

### 3.4 ⚠ `admin.html` — four UNGUARDED writes that will throw

**This is the trap in this session.** `#stat-pending` and `#stat-pending-wrap` are
written from the Pending flow with **no null guard**. Removing the tiles without
removing these throws a `TypeError` inside the approve and decline handlers —
which is a *silent* failure: the account action itself has already succeeded, so
the operator sees a working button and a half-updated page.

| Line | Statement | Action |
|---|---|---|
| `2994–2995` | `const statWrap` / `const statEl` in `loadPendingAccounts()` | Remove both, and the `statWrap.style.display` / `statEl.textContent` writes at `2999–3003` |
| `3089`, `3092` | `statEl` in the **approve** handler | Remove |
| `3095` | `getElementById('stat-pending-wrap').style.display` — **unguarded** | Remove |
| `3130` | `getElementById('stat-pending').textContent` — **unguarded** | Remove |
| `3133` | `getElementById('stat-pending-wrap').style.display` — **unguarded** | Remove |

The badge logic in the same `if/else` blocks **stays**. Only the `stat-*` writes go.

### 3.5 `style.css` — one dead selector, nothing else

`240`: `body.printing-this-week .stats-bar,` inside the `@media print` block
becomes dead. Remove **that one line only** — the surrounding print rule and the
`.stats-bar` class definition at `812–836` both stay (§ 2 OUT).

### 3.6 Playwright suite — two blocks

Local-only, untracked (`CLAUDE.md` § What's tracked vs local-only).

- `tests/15-order-export-ledger.spec.ts` **`1420–1448`** — the entire
  `test.describe('Admin dashboard — stat tiles state unit and scope (2026-08-07)')`
  block, plus its preceding comment.
- No other spec references `.stats-bar`, `#stat-*`, `#btn-export-all`,
  `#top-series`, `#all-items`, or `#admin-search` — verified by grep across
  `tests/` and the suite root.

> **Worth recording.** That spec block was written **on 2026-08-07**, the same day
> as the tile relabel, and it locks in labels on a bar this session deletes. It is
> F121's own thesis in miniature: the tile-by-tile fix got test coverage, which
> made it look finished and correct, while nobody asked whether the bar had a job
> at all. **A green suite asserts behaviour, not whether the behaviour should
> exist.** See `CLAUDE.md` § "Green is not the same as verified".

---

## 4. Verification gates

Run **after** pushing to staging and confirming the new bytes are served — the
Playwright suite loads the deployed site and cannot see the working tree
(`CLAUDE.md` § Smoke-test ordering). Check the **plain** URL, not a cache-busted
one.

| Gate | Check | Pass condition |
|---|---|---|
| **V1** | `node --check` equivalent: page loads with no console error | Zero uncaught errors on `admin.html` load |
| **V2** | Stats bar gone | No `.stats-bar` element on `admin.html`; **`.stats-bar` still renders on `mylist.html`** (the shared-CSS regression check) |
| **V3** | Export All gone | No `#btn-export-all`; **`↓ Lunar Order Sheet` / `↓ PRH Order Sheet` still open the Order Builder** |
| **V4** | **Pending approve path** — approve a seeded pending account | Account approves, badge decrements, **no console error**. This is § 3.4's trap; a passing V1 does not cover it because the handler only runs on click. |
| **V5** | **Pending decline path** — decline a seeded pending account | Row removed, badge decrements, no console error |
| **V6** | Bagging List print | `Print Bagging List` still produces a correct sheet — the § 3.5 print rule was edited |
| **V7** | Full suite | Green, with the § 3.6 block removed. Record the count; it should drop by exactly 1 test. |

**V4 and V5 are the gates that matter.** Everything else is visible on load; those
two are only reachable by clicking, on a path that currently has no coverage.

Seeded pending accounts must be torn down afterwards and **verified gone by a live
SELECT returning zero rows**, not by "the teardown ran" (`CLAUDE.md` § Definition
of Done).

---

## 5. Completion criteria

- [x] § 3.1–3.5 applied; every range re-verified against disk before editing
- [x] § 3.6 spec block removed
- [x] V1–V7 all green (§ 7)
- [x] Test fixtures torn down, **confirmed by live SELECT returning 0 rows** —
      not by "the teardown ran". Two orphans from a failed run were found and
      removed; see § 7.3.
- [ ] **Real-browser check by Rick on staging** — the page is *shorter*, and
      nothing he uses has moved. **Owed — this is Rick's, not the agent's.**
- [x] Parent plan § 5.7.4 session index updated: session 1 → Complete
- [x] `technical-reference.md` § 13 F121 + `CLAUDE.md` F121 line updated

---

## 6. Rollback

Single feature branch, client-only, **no database change and no schema change**.
Revert the merge commit on `staging`; nothing else to undo. Production is
untouched unless separately promoted.

---

## 7. Deploy log

**Executed 2026-08-07 → 08. Staging only. Production untouched.**

Branch `feature/admin-removals` → `staging` ff-only, commit **`1ec32a7`**.
**132 lines deleted, 23 added** across `admin.html` + `style.css`.

### 7.1 Applied

| Change | Result |
|---|---|
| Stats bar markup + `#stats-scope-note` | Removed, replaced by a comment recording why and noting the CSS is shared |
| `renderStats()` + its call in `loadData()` | Removed |
| `Export All (CSV)` button + listener + `makeExportRows()` | Removed |
| Four unguarded `#stat-pending` / `#stat-pending-wrap` writes | Removed; badge logic kept |
| `body.printing-this-week .stats-bar` print selector | Removed (dead) |
| Spec 15 stat-tile `describe` block (30 lines) | Removed |

### 7.2 Gates

| Gate | Evidence |
|---|---|
| **V1** | `node --check` on the extracted inline script: parses. Full suite load-time: zero console errors |
| **V2** | `.stats-bar` absent from served `admin.html`; **still served in `style.css`**; `mylist.html` markup intact |
| **V3** | `btn-export-all` absent; `btn-export-lunar` + `btn-export-prh` present and still open the Order Builder |
| **V4** | **PASS** — approve click: row removed, badge updated, **zero console/page errors** |
| **V5** | **PASS** — decline click: row removed, profile deleted, **zero console/page errors** |
| **V6** | Print rule keeps `.export-bar`, drops the dead `.stats-bar` line |
| **V7** | **86 passed (10.7m), exit 0**, clean stderr, synthetic tenant torn down |

**Orphan grep (the exhaustive check):** zero remaining code references to
`stat-total` / `stat-customers` / `stat-lunar` / `stat-prh` / `stat-value` /
`stat-pending` / `stat-fulfilled` / `stats-scope-note` / `btn-export-all` /
`makeExportRows` / `renderStats` in `admin.html`. The only hits are the two
explanatory comments this session added.

### 7.3 Three things worth carrying forward

1. **The shared-CSS check was more load-bearing than the plan knew.** The plan
   said five pages use the stats CSS. Measured: **four** now that admin's markup
   is gone — `catalog` / `mylist` / `subscriptions` carry `class="stats-bar"`,
   but **`arrivals.html` uses `.stat-value` / `.stat-label` with no wrapper**
   (7 and 5 occurrences). A `class="stats-bar"`-only grep would have missed it
   and the deletion would have silently broken the arrivals page.

2. **Confirming the served bytes took two attempts.** The first fetch of the
   plain URL returned the *old* build. Running the suite on that first response
   would have tested the previous deploy and reported a meaningless green. This
   is exactly the failure `CLAUDE.md` § Smoke-test ordering describes, and it
   fired on the first try.

3. **V4/V5 needed a purpose-built spec, and both of its first two failures were
   the test's fault, not the code's.**
   - Run 1 reported failure because the runner was invoked as
     `.\run-smoke.ps1 2>&1` — PowerShell 5.1 wraps a native executable's stderr
     in an ErrorRecord and forces a non-zero result **even on exit 0**. The only
     captured line was a `NO_COLOR` warning. Re-running through Bash gave the
     real result. **Never pipe `2>&1` from `run-smoke.ps1`.**
   - V4 then failed on `toBeHidden` because **approve is also behind a
     `confirm()`** (`admin.html:2954`) and Playwright auto-dismisses unhandled
     dialogs — the handler returned early and the row never moved, which looks
     identical to a broken handler. A dialog handler was already present on V5
     and missing on V4.

   Neither was a defect in the shipped change, but both would have been reported
   as one by a less careful read.

### 7.4 Open — Rick's call

- **`tests/zz-tmp-v4v5-pending.spec.ts` is still in the suite.** It was written
  as a temporary gate. The approve/decline click paths had **zero** coverage
  before it, and this session showed that gap matters. **Keeping it is a scope
  addition, so it is Rick's decision** — rename it to a permanent number, or
  delete it. Left in place meanwhile (local-only, untracked, reversible).
  Note it stubs `approve-customer` deliberately: the real function emails, and
  a fake `@example.test` address hard-bounces on the live MailerSend sender
  domain (F99).
- **Real-browser check on staging** — the one completion criterion still open.
