# Weekly Pull-Feed Pipeline Hardening (PLAN)

**Status:** Planning — not started. Written 2026-07-25.
**Target:** the weekly newsletter pipeline only. **No PULLLIST app code, schema, or deploy is touched.**
**Repos involved:** private scripts repo (`github.com/mrcyberrick/comic-preorder-scripts`, working tree
`C:\Users\richa\…\catalogs\scripts\`) and the separate public publish target
`github.com/mrcyberrick/weekly-pull-feed`. Neither is this repo — only this plan doc lives here.

---

## Trigger (context, not scope)

On 2026-07-25 a Brevo investigation established that the weekly newsletter had **never once been
delivered**. Campaigns #16 (07-07), #17 (07-14) and #18 (07-21) were each suspended by Brevo with 0
recipients because the sole contact in the target list was blocklisted account-wide. That cause was
fixed the same session and delivery now works.

The first successfully delivered email then immediately exposed a second defect: 10 of 30 cover
thumbnails 404'd. Both defects had been running for weeks, and **neither produced any signal** — the
GitHub Action reported success every Tuesday throughout.

Full evidence: `docs/technical-reference.md` § 13 **F96** and **F98**.

---

## Goal

Make a broken newsletter *detectable*, remove the cause of the broken images, and point the
newsletter's call-to-action at a page that can actually convert a new reader.

The ordering matters: S1 adds traffic to a conversion path, S2 and S3 make failures on that path
visible. **Do not ship S1 alone** — driving signups through a channel with no health signal is the
situation this plan exists to end.

---

## Settled decisions (Rick, 2026-07-25)

1. **All three items ship in one session.** Each is small; the cost is the shared republish +
   verification cycle, which is identical for one item or three.
2. **CTA points at the founding subdomain**, `https://rjbookstop.pulllist.app` — not the apex.
   Verified in `index.html` (lines ~380–383): the apex front door renders *"Don't have an account?
   Your shop can set one up for you"* (a dead end), while the tenant front door renders *"Don't have
   an account? Create one →"*, opening the native signup form. Every newsletter recipient is a Book
   Stop prospect, so the multi-tenant apex is the wrong landing for this audience.
3. **All three links move together.** They derive from one constant, so this is not a per-link
   choice — see S1.
4. **Batching over retry/sleep** for F98. A single commit removes the race; adding delays between
   commits only narrows it.

---

## Sub-deploys

| # | Item | Change |
|---|---|---|
| **S1** | **CTA → founding subdomain** | `build-pull-feed.js:921` — `const PREORDER_URL = "https://pulllist.app";` → `"https://rjbookstop.pulllist.app"`. One line. Feeds **three** anchors in the generated email: the header wordmark, the hero image, and the "Reserve Your Comics" button. |
| **S2** | **F98 — single-commit publish** | Replace the per-file Contents API commits (~30 per import) with one **Git Data API** commit: create blobs → build one tree → one commit → one ref update. Covers thumbnails, `newsletter.html`, `newsletter-email.html`, and `rss.xml` together. Preserve the existing MD5 cache-skip and orphan-purge behaviour. |
| **S3** | **F96 — assert the send** | In `scripts/send-brevo-campaign.js` (weekly-pull-feed repo), after `POST /emailCampaigns/{id}/sendNow`, issue `GET /v3/emailCampaigns/{id}` and assert `status` ∈ {`sent`, `inProcess`}. Exit non-zero on `suspended`/`draft` so GitHub emails a failure — matching the fail-closed posture the staleness guard already uses. Optionally also assert recipient count > 0 *before* sending, which would have caught the original outage pre-send. |

---

## In scope

- The three changes above, their verification, and updating
  `docs/weekly-pipeline-consolidation-plan.md` to describe the new publish shape.
- Marking F96 and F98 resolved in `docs/technical-reference.md` § 13 and the `CLAUDE.md`
  § Open findings line, with the date.

## Out of scope (stop and ask before touching)

- **Any PULLLIST app change** — no `app.js`, no HTML, no Edge Function, no schema, no `config.js`.
- **F97** (missing `mrcyberrick.us` DMARC) — DNS-only, unrelated to this pipeline, its own task.
- **Brevo list growth / audience sourcing** — list 7 currently holds exactly one contact. That is
  Rick's separate rjbookstop.com funnel track, not engineering work.
- **F72** multi-tenant email branding.
- The newsletter's visual design, template layout, or copy beyond the S1 URL constant.
- Retiring or altering the `weekly-pull-feed` publish surface — `rjbookstop.com` and the Brevo sender
  consume those exact URLs; changing them re-introduces cutover risk this pipeline already avoided.

---

## Risks

- **R1 — Git Data API rewrite regresses the thumbnail cache or orphan purge.** The current logic
  skips unchanged MD5-keyed thumbs and reconciles orphans; a naive rewrite could re-upload everything
  weekly or strand old files. *Mitigation:* dry-run against a scratch branch first and diff the
  resulting tree against a known-good publish before pointing at `main`.
- **R2 — S3's status assertion fires falsely.** If Brevo reports a transient non-terminal status
  immediately after `sendNow`, a strict assertion could fail a send that actually succeeded.
  *Mitigation:* accept `inProcess` as well as `sent`, and poll briefly rather than reading once.
- **R3 — verification requires a real send.** A `DRY_RUN` draft does not exercise the suspension
  path, which is precisely why the original outage hid for 18 days. *Mitigation:* verify against a
  one-contact test list (list **8**, `test - Weekly Pull List`, already exists), and restore
  `BREVO_LIST_ID` to **7** before closing.
- **R4 — freshness guard blocks the test send.** `STALE_MAX_DAYS=6` against the
  `<!-- pull-feed-generated: YYYY-MM-DD -->` stamp. A test more than 6 days after the last publish
  needs a fresh `build-pull-feed.js` run first, not a raised limit.

---

## Completion criteria

- [ ] S1: generated `newsletter-email.html` contains **zero** `https://pulllist.app` hrefs and three
      `https://rjbookstop.pulllist.app` hrefs.
- [ ] S1: the CTA, header, and hero all resolve to the founding tenant login, and that page shows the
      **"Create one →"** signup affordance in a real browser (per the CSS-in-real-browser rule).
- [ ] S2: one import produces **exactly one** commit on `weekly-pull-feed` and **one** Pages build —
      no cancelled `Upload optimized thumbnail` runs in the workflow list.
- [ ] S2: **all** `<img src>` URLs in the published email return HTTP 200 with **no** manual
      `pages/builds` rebuild. Verify by resolving every image, not by spot-check — the failure mode is
      a contiguous tail, so checking the first few proves nothing.
- [ ] S3: a deliberately-suspended campaign (e.g. re-blocklist the test contact) makes the GitHub
      Action **fail**, and GitHub emails the failure. Confirmed by observation, not by reading code.
- [ ] S3: a healthy send still passes and reports the campaign status it observed.
- [ ] `BREVO_LIST_ID` restored to **7**; test list 8 emptied or deleted.
- [ ] F96 and F98 marked resolved with the date in `technical-reference.md` § 13 and `CLAUDE.md`.
- [ ] `docs/weekly-pipeline-consolidation-plan.md` updated to describe the single-commit publish.

---

## Verification gates

| Gate | Check |
|---|---|
| **V1** | `node --check build-pull-feed.js` and a `--no-write`-equivalent dry run before any publish. |
| **V2** | Scratch-branch publish: tree diff matches a known-good publish (R1). |
| **V3** | Live image sweep — every `<img src>` in the published email returns 200, no manual rebuild. |
| **V4** | Negative test — suspended campaign turns the Action red (S3). |
| **V5** | Positive test — real send to test list 8 lands in the inbox, images intact, CTA opens the tenant login with signup visible. |

---

## References

- `docs/technical-reference.md` § 13 — **F96** (send-status blindness), **F98** (publish race),
  F97 (DMARC, out of scope here)
- `docs/weekly-pipeline-consolidation-plan.md` — canonical pipeline description; update at close
- `docs/native-customer-signup.md` — the signup path S1 points traffic at; note the § Adjacent doc
  tension flagged in F96 (Brevo weekly-shipment mail described as "yet to be developed" while the
  previews sender is live) — reconcile if this session touches that doc
- `index.html` ~380–383 — apex vs tenant signup affordance, the evidence behind decision 2
