# Weekly Pipeline Consolidation — Plan (pre-scoping)

**Status:** Draft — blocked on inputs (§ 5). Written 2026-07-08 from the
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

## 2. Target state

`weekly_shipment` (already the richer dataset: catalog joins, covers,
reservation counts) becomes the single source. The Google path's four outputs
are regenerated from it:

| Output | Replacement | Sketch |
|---|---|---|
| RSS feed for rjbookstop.com | Public Edge Function `shipment-feed` returning RSS XML for the current week | Read-only, tenant-scoped, cacheable; promo rows already excluded by the import's `Retail = 0.00` filter |
| Standalone arrivals site | Either point at the feed consumer, or a public no-auth arrivals view | Decide with input #2 |
| Newsletter template | Edge Function or script rendering the weekly HTML from `weekly_shipment` | Reuse the existing MailerSend template idioms |
| Printed store sheet | Print-styled page in the app (admin → This Week already has print CSS) or PDF attached to the Monday store-packet email | Pairs with the review's § 9 #5 automation |

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

## 5. Blocking inputs (gather before the build session)

1. **The Google Apps Script source** — what exactly it computes (grouping,
   ordering, formatting), so the replacements are faithful.
2. **The rjbookstop.com integration contract** — the exact RSS shape the site
   consumes (element names, GUID behavior, item limit) and who controls the
   consuming widget.
3. **Newsletter delivery path** — whether the template is pasted into
   MailerLite or sent via MailerSend, and its required markup constraints.
4. **The manual promo-removal rule** — confirm it is fully captured by the
   `Retail = 0.00` filter, or enumerate what else gets stripped by hand.

## 6. Effort estimate

1–3 weeks elapsed (small sessions): feed + sheet ≈ 2–3 days, newsletter ≈
2–3 days, parallel-run diffing ≈ 30 min/week for 2–4 weeks, cutover ≈ 1 day.
