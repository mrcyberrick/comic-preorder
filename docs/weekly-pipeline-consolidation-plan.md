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
| Brevo send | Unchanged — existing Node send script + freshness stamp contract (the new builder must emit the same `pull-feed-generated` comment) | |
| Printed store sheet | Unchanged near-term; pairs with the review's § 9 #5 store-packet automation later | |

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

## 5. Blocking inputs — status 2026-07-09

1. **Code.gs** — ✅ main file received (transcript truncated mid-file).
   **Still needed:** the tail of `uploadMailerLiteTemplate()` (Brevo edition)
   and the full `uploadRssFeed()` — the RSS builder is the critical contract
   (Rick: the feed drives rjbookstop.com and the newsletter flow).
2. **CsvImporter.gs** — ❌ not yet seen. Needed to confirm how sheet rows are
   derived from invoice CSVs (cover-URL construction, title normalization,
   any filtering beyond promos) so `weekly_shipment`-sourced rows are
   equivalent.
3. **Newsletter delivery path** — ✅ answered: Brevo `htmlContent` via a
   separate **Node send script** with a fail-closed freshness-stamp guard.
   **Still needed:** that send script (name/location/schedule), so the new
   builder preserves its contract exactly.
4. **The manual promo-removal rule** — ❌ still to confirm vs the import's
   `Retail = 0.00` filter.
5. **rjbookstop.com consumption** — how the site ingests `rss.xml` (embedded
   widget? which elements does it render?). May become moot if the feed is
   reproduced byte-compatibly, but knowing it bounds the diff tolerance.

## 6. Effort estimate

1–3 weeks elapsed (small sessions): feed + sheet ≈ 2–3 days, newsletter ≈
2–3 days, parallel-run diffing ≈ 30 min/week for 2–4 weeks, cutover ≈ 1 day.
