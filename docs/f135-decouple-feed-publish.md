# F135 — decouple the pull-feed publish from shipment import

**STATUS:** NOT STARTED | staging=— | prod=— | findings=F135,F134
**Status:** **PLANNED — not started.** Written 2026-08-21. Direction settled with Rick the same
day: **decouple**, do not add an ad-hoc mode.
**Target:** two repos — `catalogs/scripts` (private scripts repo) and
`mrcyberrick/weekly-pull-feed`. **No `comic-preorder` app change.**
**Interim mitigation is live and needs no code** — see § 3. Ad-hoc shipment imports are safe today
if that step is followed, so this is not a blocker on F134's operational path, only on making it
routine.
**Last verified against live:** 2026-08-21 — publish block read at `import.js` ~1931,
`resolveFeedWeek()` at ~1510, guard confirmed at `if (!process.env.GITHUB_TOKEN_PULL_FEED)`.

---

## 1. The defect

The publish is welded inside the shipment-import block and fires unconditionally:

```js
// Automatic whenever a shipment ran — no prompt (decision 2026-07-09).
const feedDate = resolveFeedWeek(allShip);
await publishPullFeed({ refDate: feedDate });
```

`resolveFeedWeek()` infers the week from **the rows just imported**. An ad-hoc file holds a handful
of rows for books that **already went on sale** — that is why they are being chased — so its
dominant `on_sale_date` is a **past** week. The publish then republishes that past issue, the
orphan purge deletes the current week's thumbnails, and the next Brevo cron mails the stale issue.

**This is not hypothetical.** `resolveFeedWeek()`'s own comment records it, measured on production
2026-08-11 from the earliest-wins bug:

> *"the feed republished 19 already-shipped titles, purged the 50 correct thumbnails as orphans,
> and the Tue 08-11 Brevo send mailed that stale issue. The 08-12 week was never previewed at all."*

An ad-hoc import reproduces that incident deliberately.

**Why the 2026-07-09 decision no longer holds.** "Always publish, no prompt" was right when the only
shipment import was the weekly one. F134's one-off path breaks that premise — the same way the
2026-08-03 removal of Mark Fulfilled predated `arrival_outcome` existing.

---

## 2. Why decouple rather than add a flag

1. **`import.js` becomes data-only and uniform** — no ad-hoc branch that can be forgotten, no mode
   to pass wrongly. This was Rick's stated goal.
2. **The week gets resolved from the database, not from one file.** `build-pull-feed.js` already
   falls back to `resolveLatestShipmentWeek()` when `resolveFeedWeek()` returns null. That fallback
   sees *all* shipments rather than whichever rows were in the file being imported — it is the
   better source, and decoupling **promotes the fallback to primary**.
3. **`resolveFeedWeek()` is deleted.** A file-content inference whose own comment is a twenty-line
   post-mortem of it being wrong stops existing rather than being patched again.
4. Most of the machinery exists: `publishPullFeed()` is already exported, and
   `node build-pull-feed.js --publish` is already the documented recovery route.

---

## 3. Interim mitigation — available now, no code

`upsertShipment()` runs **before** the publish block, and the publish is guarded:

```js
} else if (!process.env.GITHUB_TOKEN_PULL_FEED) {
  console.warn('   ⚠️  GITHUB_TOKEN_PULL_FEED missing from .env — skipping feed publish.');
}
```

**Comment out `GITHUB_TOKEN_PULL_FEED` in the scripts `.env`, run the ad-hoc import, restore it.**
The shipment lands; the publish is skipped with a warning.

**Comment the line — do not export an empty shell variable.** The `.env` loads through dotenvx and
whether it overrides an already-present empty key is version-dependent; commenting is unambiguous.
Rehearse once on staging before relying on it for a real receiving decision.

---

## 4. Design

### 4.1 Move the trigger — do not remove it

**The coupling exists to guarantee the publish happens.** Making it a manual step trades a **loud**
failure (wrong week mailed) for a **quiet** one (nothing published, nobody notices). Quiet failures
are this system's documented weakness: **F96** ran three consecutive weeks of Brevo sends green in
GitHub Actions while every campaign sat suspended with zero recipients — found by eye, by no alarm.

So the trigger **moves**. A cron replaces the coupling; no human is added to the loop.

### 4.2 Target shape

```
mrcyberrick/weekly-pull-feed — Tue 22:00 UTC:
  1. build-pull-feed     (week resolved from the DATABASE)
  2. send-brevo-campaign
```

- `import.js` no longer publishes anything, ever.
- `resolveFeedWeek()` is removed, along with its export.
- `node build-pull-feed.js --publish` remains the manual / recovery path.
- Build and send become adjacent, closing a gap that exists today: the build currently happens at
  import time and the send fires Tuesday, so the feed can go stale in between.

### 4.3 Two risks to design around

- **F100 — one deployer, not two.** F98 was caused by two independent GitHub Pages deployers with
  no ordering guarantee, resolved by deleting `deploy-pages.yml`. Adding a build step to that repo's
  workflow must not reintroduce a second deployer.
- **Token placement.** `GITHUB_TOKEN_PULL_FEED` lives in the scripts `.env` today. A build running
  inside that repo's Actions should use the repo's own credentials rather than a copied secret —
  fewer places for a token to rot.

---

## 5. Runbook

**S1 — prove the interim mitigation** (§ 3) on staging. Confirm the shipment upserts and the publish
is skipped. This is what makes ad-hoc imports safe while the rest of this ships. **Gate V1.**

**S2 — add the build step** to the `weekly-pull-feed` send workflow, ahead of the send, resolving
the week from the database. Verify one deployer remains (§ 4.3). **Gate V2.**

**S3 — observe one full unattended cycle** with both the old and new paths capable of running, but
`GITHUB_TOKEN_PULL_FEED` still present, so the import path is the one in force. Confirms the new
step produces an identical feed before anything is removed. **Gate V3.**

**S4 — remove the publish from `import.js`** and delete `resolveFeedWeek()` + its export. Scripts
repo, unit tests updated (`resolveFeedWeek` is exported and likely covered). **Gate V4.**

**S5 — observe one cycle with the import path gone.** **Gate V5.** Only after this is green does the
finding close.

Order matters: **the new trigger must be proven before the old one is removed.** Doing S4 before S3
creates a window where nothing publishes and the failure is silent — the exact trade § 4.1 exists to
avoid.

---

## 6. Verification gates

| Gate | Assertion | Why |
|---|---|---|
| **V1** | Ad-hoc import with `GITHUB_TOKEN_PULL_FEED` commented: shipment rows land, **no** publish, warning printed | The mitigation F134 depends on |
| **V2** | Build step runs in the send workflow; exactly **one** Pages deployer exists afterwards | F100 |
| **V3** | New build produces a feed **identical** to the import-triggered one for the same week | Proves equivalence before removal |
| **V4** | `import.js` contains no publish call and no `resolveFeedWeek()`; unit suite green | The removal |
| **V5** | One unattended Tue cycle: feed built from DB, correct week, thumbnails intact, Brevo send delivered | The only evidence that counts |

V5 must be read from the **campaign's observed status**, not from a green Actions run — that
distinction is F96 and F106 exactly.

---

## 7. Completion criteria

- [ ] V1–V5 green, each with recorded output
- [ ] `import.js` publishes nothing; `resolveFeedWeek()` deleted; scripts repo committed **and
      pushed** (verify `git log origin/main` — a local-only commit has bitten this before)
- [ ] `weekly-pull-feed` workflow builds then sends, one deployer, repo-native credentials
- [ ] `GITHUB_TOKEN_PULL_FEED` removed from the scripts `.env` if no longer used, or its remaining
      purpose documented
- [ ] § 13 F135 flipped to RESOLVED; CLAUDE.md row removed
- [ ] This doc's STATUS token flipped
- [ ] `/wrap-up`

---

## 8. Rollback

S4 is the only irreversible-feeling step and it is a `git revert` in the scripts repo. Until S4, both
paths can coexist — which is why S3 exists. If the new trigger misbehaves after S4, revert S4 and the
import-time publish returns.

---

## References

`docs/technical-reference.md` § 13 — **F135**, **F134** (what makes ad-hoc imports routine),
**F98**/**F100** (publish ordering, two-deployer history), **F96**/**F106** (why a quiet failure is
worse), **F84** (label inversion in the same import path).
`docs/weekly-pipeline-hardening.md` · `docs/weekly-pipeline-consolidation-plan.md`.
