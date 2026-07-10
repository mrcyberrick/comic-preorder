# Weekly Pipeline Consolidation — Plan

**Status:** Scoping — Apps Script main source received 2026-07-09 (§ 1.5);
three artifacts still outstanding (§ 5). Written 2026-07-08 from the
2026-07-07 architecture review (workflow finding: shipment data is processed
twice, by hand, into two disconnected systems).
**Owner:** Rick. **Execution:** future dedicated session(s), out of Phase 5.5
scope; no dependency on second-tenant onboarding.

---

## 1. Problem

Every week the same shipment invoices are processed twice:

1. **PULLLIST path** — invoices fed to the import script → `weekly_shipment`
   → arrivals page, admin This Week, bagging lists.
2. **Google path** — invoices manually stripped of promo items → uploaded to
   Google Drive → Sheets App Script → rjbookstop.com RSS feed + standalone
   site + newsletter template + printed store sheet.

Two sources of truth for "what arrived this week," duplicate manual work, a
weekly hand-edit of a data file (promo removal), and an App Script codebase
maintained outside any repo.

## 1.5 Decoded current architecture (from Code.gs, received 2026-07-09)

The Google path is more specific — and more replaceable — than § 1 assumed:

```
Shipment invoice CSVs → Google Drive → CsvImporter.gs (NOT YET SEEN)
  → Google Sheet "Sheet1" (col A = cover image URL, col B = title)
  → buildNewsletter() [Code.gs] which publishes THREE artifacts to the
    separate GitHub Pages repo mrcyberrick/weekly-pull-feed:
      • newsletter.html       — browser version (promo section, dismissible)
      • newsletter-email.html — Brevo htmlContent fragment (NOT MailerLite —
        function name is legacy); carries a machine-readable freshness stamp
        <!-- pull-feed-generated: YYYY-MM-DD --> read by a separate Node send
        script that aborts stale sends (fail-closed)
      • rss.xml               — per Rick: THE driver for rjbookstop.com and
        the newsletter flow
  + thumbnail pipeline: MD5(source URL).webp → GitHub thumbs/ cache →
    wsrv.nl proxy (300px WebP q80, ≤100KB validation) → GitHub Contents API
    upload; orphan purge each run. GITHUB_TOKEN in Script Properties
    (contents:write on weekly-pull-feed only).
```

**The key structural fact:** the sheet holds exactly `(cover_url, title)` —
two columns `weekly_shipment` already stores per row. The whole Google path
is a hand-fed projection of data PULLLIST now owns.

## 2. Target state (revised 2026-07-09)

**Keep the `weekly-pull-feed` publish surface; replace the producer.**
rjbookstop.com and the Brevo sender keep consuming the exact same GitHub
Pages URLs (`rss.xml`, `newsletter.html`, `newsletter-email.html`, `thumbs/`)
— zero consumer-side change, which removes most of the original plan's
cutover risk. What changes is who writes those files:

| Component | Replacement | Sketch |
|---|---|---|
| Sheet + CsvImporter.gs + manual Drive upload | **Nothing** — eliminated. The producer reads `weekly_shipment` (title, cover_url, on_sale_date) directly | Promo rows already excluded by the import's `Retail = 0.00` filter |
| Code.gs `buildNewsletter()` | `build-pull-feed.js` in the private scripts repo — Node, reuses `.env` (service key + a new `GITHUB_TOKEN_PULL_FEED`), ports the three template builders + thumbnail cache/purge logic ~verbatim | Run after the weekly import (or prompted by `import.js` post-shipment: "Publish weekly feed? (y/n)"); later schedulable |
| Brevo send | **Unchanged** — GitHub Action `send-newsletter.yml` (cron Tue 22:00 UTC) runs `scripts/send-brevo-campaign.js`: reads committed `newsletter-email.html`, fail-closed stale guard (`pull-feed-generated: YYYY-MM-DD` stamp, `STALE_MAX_DAYS=6`), `workflow_dispatch` dry-run creates a Brevo draft. New producer must commit the same file + stamp before Tuesday evening — the weekend/Monday weekly import satisfies this naturally | |
| Printed store sheet (Google Sheet printout) | **Replaced in-app (Rick, 2026-07-09):** an admin-only tailored printable report surfaced on `arrivals.html` (This Week) — full week's `weekly_shipment` (title, qty, cover), print-CSS like the existing admin bagging list. Receiving works from this instead of the Sheet printout | Pairs with § 9 #5 store-packet email later; admin gating via existing `is_admin` profile check |

## 3. Migration strategy — revised 2026-07-09 (build complete)

The original 2–4-week parallel run assumed two publish surfaces; there is
only one (`weekly-pull-feed`), so byte-level trust was established **up
front** instead: `build-pull-feed.js --local` output was diffed against the
live Apps-Script-generated artifacts for the same week —

- `rss.xml` (the rjbookstop.com contract): **zero non-date differences**
- both newsletters: differ only in build-date stamps and pre-existing
  comment-encoding mojibake in the live files (the Apps Script upload was
  mangling non-ASCII inside HTML comments; the Node port renders them
  correctly — the new output is strictly better)
- one data-level discrepancy found and shimmed: `import.js` writes PRH
  covers as `…/cover/{id}` vs the pipeline's `…/cover/d/{id}`; both serve
  identical images (verified); the builder normalizes to `/d/` so feed GUIDs
  and cached thumbnail hashes stay stable.

**Cutover model:** the new producer takes the surface at the next weekly
import (auto-publish hook). Rick stops running `processNewShipments()`;
CODE.GS + the Sheet + the Drive folder stay dormant-but-runnable as rollback
for one month, then retire. No real publish was run at build time — deliberately:
refreshing the freshness stamp mid-week would weaken the Brevo stale guard
for the following Tuesday if a weekend import were ever skipped. The first
real publish is the next shipment import.

**Post-cutover checks (first two weeks):** after each import, eyeball
`https://mrcyberrick.github.io/weekly-pull-feed/newsletter.html`, confirm
rjbookstop.com renders the feed, and confirm Tuesday's Brevo send goes out
(or correctly aborts if no shipment ran).

Nothing in this plan touches `weekly_shipment` writes, the import script, or
any customer-facing page — additive outputs only, so the risk profile is low.

## 4. Explicitly out of scope

- Changing how invoices are obtained (distributor portal automation is its
  own track — review § 9 #2).
- Any change to the bagging-list content or the store's paper workflow; paper
  remains a requirement, only its production is automated.
- Multi-tenant generalization of the feed (founding-tenant-only until 5.5+
  proves demand).

## 5. Blocking inputs — status 2026-07-09 (all but one resolved)

1. **Code.gs** — ✅ full source local (`catalogs/scripts/CODE.GS`).
   `uploadRssFeed()` contract captured: RSS 2.0 + atom/dc/media namespaces,
   Flipboard-tuned (300+ char descriptions, `dc:creator`, `category` =
   'Comics' if the cover URL contains `lunardistribution.com` else 'Books'),
   **`guid isPermaLink="true"` = the original cover-image URL**, `enclosure`
   = same URL, description CDATA = 300px thumb + boilerplate text, channel
   `ttl` 10080, hero image block. Item order = title A–Z (sheet sort).
2. **CsvImporter.gs** — ✅ full source local. Extracts only (Title,
   Code/ISBN) from the same two invoice CSVs `import.js` consumes; builds
   cover URLs with the **identical patterns** `import.js` uses for
   `weekly_shipment.cover_url` (`media.lunardistribution.com/images/covers/
   large/{Code}.jpg`, `images.penguinrandomhouse.com/cover/d/{ISBN}`);
   dedupes by URL; **no promo/price filtering at all** — which is exactly why
   the manual pre-upload promo strip exists on this path.
3. **Newsletter delivery** — ✅ fully captured: GitHub Action
   `send-newsletter.yml` in `weekly-pull-feed` (cron Tue 22:00 UTC EDT,
   `workflow_dispatch` with dry-run) → `scripts/send-brevo-campaign.js`
   (zero-dep Node 18+, Brevo API v3, `BREVO_API_KEY`/`BREVO_LIST_ID`/
   `SENDER_EMAIL` secrets, `EMAIL_HTML_PATH=newsletter-email.html`,
   stale guard `STALE_MAX_DAYS=6`, min-length guard). Untouched by this plan.
4. **The manual promo-removal rule** — ✅ confirmed by Rick 2026-07-09:
   promo items appear on the **Lunar (Format B) invoice only**. The import's
   automatic `Retail = 0.00` filter fully covers the manual strip; parity
   between `weekly_shipment` and the hand-prepared sheet is exact.
5. **rjbookstop.com consumption** — bounded: the producer swap reproduces the
   feed shape from the same generator logic, so the consumer never sees a
   format change. (Live-feed diffing in the parallel run covers the rest.)

## 6. Build session checklist

1. ✅ **Done 2026-07-09** (scripts repo `31fd4f7`): `build-pull-feed.js` —
   `weekly_shipment` week query (paginated), template builders extracted
   verbatim from CODE.GS, thumbnail cache/purge ported, `--local` /
   `--publish` modes, `/d/` cover-URL parity shim, `publishPullFeed()`
   export. Token verified (fine-grained, contents:write on
   `weekly-pull-feed` only).
2. ✅ **Done 2026-07-09** (same commit) — auto-publish, no prompt (Rick's
   decision): `import.js` publishes the
   feed automatically whenever shipment files were part of the run and the
   shipment upsert succeeded; no shipment files → no publish. Fail-soft
   (publish failure warns, never fails the import; skips with a warning if
   the token is absent; `[no-write]` aware). Duplication
   protection is inherent: fixed-path artifacts updated via SHA-based GitHub
   Contents API upsert, MD5-keyed thumbnails skipped when cached, orphan
   purge reconciles — a same-week re-run rewrites identical outputs. The
   refreshed `pull-feed-generated` stamp is harmless (the Brevo guard checks
   staleness only). Standalone `node build-pull-feed.js` retained for manual
   re-publish.
   **Setup prerequisite (Rick, one-time):** mint a fine-grained GitHub PAT
   scoped to contents:write on `weekly-pull-feed` only (same scoping rule as
   the Apps Script token) and add it to the scripts `.env` as
   `GITHUB_TOKEN_PULL_FEED`.
3. ✅ **Done on staging 2026-07-09** (commit `f900247`; 19/19 smoke green
   against the deploy): admin-gated "Print Store Report" on `arrivals.html`
   — full week's shipment grouped by distributor, A-Z titles, check-off box,
   qty, code/UPC, price, per-group + grand unit totals, received-by line.
   Customer print path unchanged. **Prod promotion pending** (rides the next
   staging → main).
4. Parallel run 2–4 weeks: diff `rss.xml` / `newsletter.html` /
   `newsletter-email.html` against the Apps Script outputs weekly.
5. Cutover: stop running `processNewShipments()`; Sheet/Drive/Apps Script
   retired (leave read-only for one month as rollback).

## 6. Effort estimate

1–3 weeks elapsed (small sessions): feed + sheet ≈ 2–3 days, newsletter ≈
2–3 days, parallel-run diffing ≈ 30 min/week for 2–4 weeks, cutover ≈ 1 day.
