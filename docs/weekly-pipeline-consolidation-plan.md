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

## 3. Migration strategy — parallel run

1. Build the four replacement outputs while the Google path keeps running.
2. Run both for 2–4 consecutive weeks; diff outputs each week (feed items,
   newsletter contents, sheet rows) until byte-level trust is established.
3. Cut rjbookstop.com over to the new feed URL; retire the Drive upload and
   the App Script; keep the Sheet read-only for one further month as rollback.

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
4. **The manual promo-removal rule** — ⏳ one confirm left (Rick): is the
   hand-strip only `Retail = 0.00` lines on the Lunar (Format B) invoice, or
   are promo items also removed from the PRH (Format A) delivery file (which
   has no price column to filter on)? `weekly_shipment` inherits `import.js`'s
   `Retail = 0.00` filter, so parity holds if the answer is "Lunar only."
5. **rjbookstop.com consumption** — bounded: the producer swap reproduces the
   feed shape from the same generator logic, so the consumer never sees a
   format change. (Live-feed diffing in the parallel run covers the rest.)

## 6. Build session checklist (ready to execute)

1. `build-pull-feed.js` in the private scripts repo: query `weekly_shipment`
   for the target week (title, cover_url; promo rows already filtered) →
   port the three template builders + thumbnail cache/purge from CODE.GS →
   commit artifacts to `weekly-pull-feed` via GitHub Contents API
   (`GITHUB_TOKEN_PULL_FEED` in `.env`, contents:write scoped).
2. Wire an optional "Publish weekly feed? (y/n)" prompt at the end of
   `import.js`'s shipment step (or keep standalone invocation).
3. In-app printable store report: admin-gated print view on `arrivals.html`
   (This Week) rendering the full week's shipment — replaces the Google
   Sheet printout (normal staging → smoke → promote flow).
4. Parallel run 2–4 weeks: diff `rss.xml` / `newsletter.html` /
   `newsletter-email.html` against the Apps Script outputs weekly.
5. Cutover: stop running `processNewShipments()`; Sheet/Drive/Apps Script
   retired (leave read-only for one month as rollback).

## 6. Effort estimate

1–3 weeks elapsed (small sessions): feed + sheet ≈ 2–3 days, newsletter ≈
2–3 days, parallel-run diffing ≈ 30 min/week for 2–4 weeks, cutover ≈ 1 day.
