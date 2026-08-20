# Weekly Pull-Feed Pipeline Hardening (PLAN)

**STATUS:** COMPLETE | staging=2026-07-27 | prod=2026-07-27 | findings=F96,F98,F100,F106

**Status:** **COMPLETE — 2026-07-27.** All three items shipped and live; every completion
criterion ticked; V4 and V5 both observed against the live Brevo API, and the real-browser
signup check confirmed. Written 2026-07-25, executed 2026-07-26, closed 2026-07-27 —
~32 hours ahead of the first unattended cron run (Tue 2026-07-28 22:00 UTC).

| Item | State | Commit |
|---|---|---|
| S1 CTA → founding subdomain | **Live and verified on the served page** | `4582c12` (scripts) |
| S2 single-commit publish | **Live and verified: 1 commit, 1 build, 1 deploy** | `b727912` (scripts) |
| S3 send-status assertion | **Live. V4/V5 verified 2026-07-27; then false-alarmed on the first unattended run (2026-07-28, campaign 24, 100% delivered, Action red) — camelCase `inProcess` vs Brevo's `in_process`. Fixed, filed as F106** | `34074c3e`, fix `95d5eec8` (weekly-pull-feed) |

**Also landed this session** (both discovered *by* running the gates, not planned):
- `604cfaec` (weekly-pull-feed) — `branches: [main]` on `deploy-pages.yml`; V2 prerequisite,
  since that workflow really does deploy and would have published a scratch branch live.
- `808cae4` (scripts) — the feed week defaulted to *today's* week rather than the upcoming
  shipment, so a bare `--publish` would have replaced next week's newsletter with
  already-shipped titles. Found at V2. Rick approved fixing it in-session.
- **F100 filed** (`e864475`, comic-preorder staging) — F98's recorded mechanism was wrong.
  Two independent Pages publishers race; the cancelled Actions runs F98 blamed were a
  symptom. S2's single commit neutralizes it. CODE.GS also formally retired (Rick's call).

**All closure items done 2026-07-27:** V5 (run `30271641770`, campaign 21 delivered),
V4 (run `30275663163`, Action red + GitHub failure email), `BREVO_LIST_ID` restored to **7**
and its target re-verified healthy, real-browser signup check confirmed, F96 marked resolved.
See § Completion criteria for the evidence behind each.

**Gate scheduled (2026-07-26):** V4/V5 need a real send and must land before the **first
unattended cron run of the rewritten send script, Tue 2026-07-28 22:00 UTC**. Reminder set for
**Mon 2026-07-27, 8:00 AM ET** — routine `trig_01Lz3CREyTTUEWYUDhvuSg7w` (one-shot,
auto-disables after firing) plus Google Calendar event `k4kf2te64k8laoopi9r23us9es`
(popup at time, email 60 min prior). Monday chosen deliberately: it avoids Tue/Wed
(shipment + bagging) and leaves a full day of slack before the cron. Verified
`(Get-Date '2026-07-27').DayOfWeek` = Monday rather than assuming it.
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
| **S3** | **F96 — assert the send** | In `scripts/send-brevo-campaign.js` (weekly-pull-feed repo), after `POST /emailCampaigns/{id}/sendNow`, issue `GET /v3/emailCampaigns/{id}` and assert `status` ∈ {`sent`, `in_process`} **(corrected 2026-07-29 — this spec originally said `inProcess`; Brevo returns snake_case, and the camelCase literal shipped into the code and cost a false alarm on the first unattended send. See F106.)**. Exit non-zero on `suspended`/`draft` so GitHub emails a failure — matching the fail-closed posture the staleness guard already uses. Optionally also assert recipient count > 0 *before* sending, which would have caught the original outage pre-send. |

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
  *Mitigation:* accept `in_process` as well as `sent`, and poll briefly rather than reading once. **Outcome: the mitigation was right and the literal was wrong** — shipped as `inProcess`, so R2 fired anyway on 2026-07-28 (campaign 24, 100% delivered, Action red). Fixed in `95d5eec8`; filed as F106.
- **R3 — verification requires a real send.** A `DRY_RUN` draft does not exercise the suspension
  path, which is precisely why the original outage hid for 18 days. *Mitigation:* verify against a
  one-contact test list (list **8**, `test - Weekly Pull List`, already exists), and restore
  `BREVO_LIST_ID` to **7** before closing.
- **R4 — freshness guard blocks the test send.** `STALE_MAX_DAYS=6` against the
  `<!-- pull-feed-generated: YYYY-MM-DD -->` stamp. A test more than 6 days after the last publish
  needs a fresh `build-pull-feed.js` run first, not a raised limit.

---

## Completion criteria

- [x] S1: generated `newsletter-email.html` contains **zero** `https://pulllist.app` hrefs and three
      `https://rjbookstop.pulllist.app` hrefs. **Verified 2026-07-26 on the LIVE served page**
      (`mrcyberrick.us/weekly-pull-feed/newsletter-email.html`): 0 apex, 3 founding-subdomain.
      `newsletter.html` and `rss.xml` also carry zero apex hrefs.
- [x] S1: the CTA, header, and hero all resolve to the founding tenant login, and that page shows the
      **"Create one →"** signup affordance in a real browser (per the CSS-in-real-browser rule).
      **Verified 2026-07-27 by Rick in a real browser**, from the delivered V5 email: the CTA points
      to `rjbookstop.pulllist.app` and **"Create one" renders as expected**. Machine-side support:
      the page returns 200 and its served markup contains `Create one →` (and *not* the apex-only
      "can set one up for you" wording). The human check was genuinely load-bearing — the affordance
      ships as `style="display:none"` and is revealed client-side once `TenantContext` resolves the
      host, so served markup alone never proved visibility.
- [x] S2: one import produces **exactly one** commit on `weekly-pull-feed` and **one** Pages build.
      **Verified 2026-07-26** on the live publish of week 2026-07-27 (commit `24c3035b`): exactly 1
      commit added to `main`, 1 legacy Pages build, 1 deployment, 0 cancelled runs.
      *Criterion reworded per F100* — "no cancelled `Upload optimized thumbnail` runs in the workflow
      list" counted the wrong artifact, since those runs were a symptom rather than the cause. The
      assertion that matters is **one deployment of the tip commit** via `/deployments` plus one
      `/pages/builds` entry.
- [x] S2: **all** `<img src>` URLs in the published email return HTTP 200 with **no** manual
      `pages/builds` rebuild. **Verified 2026-07-26: 30/30 resolved 200**, every one, no rebuild.
      **Caveat, stated honestly:** that publish added **0 new thumbnails** (all 29 cached), so it did
      not re-create and then defeat the 404-tail scenario — it had nothing new to serve. The
      36-new-thumb case was proven at tree level on the V2 scratch branch, which was never served.
      The structural argument covers the gap (one commit ⇒ one build ⇒ no ordering window), but the
      first import that brings genuinely new covers is the true end-to-end confirmation.
- [x] **V4 — S3 negative gate.** A zero-valid-recipient state makes the GitHub Action **fail**, and
      GitHub emails the failure. Confirmed by observation, not by reading code.
      **Action-red half OBSERVED 2026-07-27** (run `30275663163`, list 8 emptied per Option A):
      guard printed `List 8 ("test - Weekly Pull List"): 0 subscriber(s), 0 blocklisted`, then
      `ERROR: List 8 has 0 valid recipients … The list is empty. (F96)`, `exit code 1`, run
      conclusion **failure**. Grep for `Creating campaign|Campaign created|sendNow accepted`
      returned **0 matches** — it aborted before creating anything, so `sendNow` was never reached.
      Under the old script this identical state produced a *green* run and silent non-delivery.
      **GitHub emailed the failure — confirmed 2026-07-27** in Rick's inbox: *"Send Weekly Newsletter
      / send — Failed in 12 seconds."* This was held as a blocker deliberately: the red run is the
      alarm, the email is the alarm *reaching a human*, and a red Action nobody is told about is
      still a silent failure — the exact defect class F96 documents.
      *Method note:* Option A (empty the list) was used instead of re-blocklisting. The guard fires
      on `subscribers === 0` alone — `blocklisted` only selects the explanatory string — so both
      routes exercise the identical branch, and Option A leaves no account-level flag that could
      silently persist and re-create the original outage.
- [x] **V5 — S3 positive gate.** A healthy send still passes and reports the status it observed.
      **Verified 2026-07-27** (run `30271641770`): `List 7…`→ list 8 showed `1 subscriber(s), 0
      blocklisted`; campaign **21** created; `sendNow accepted`; poll ran
      `queued → queued → queued → in_process → sent`, then `Campaign 21 confirmed SENT`.
      Rick confirmed inbox arrival, subject *"This Week's Comic Previews - July 27, 2026"*, with the
      CTA opening `rjbookstop.pulllist.app`. Independently re-verified on the sent email: **0 apex /
      3 founding** hrefs and **30/30 images HTTP 200**.
      **R2 vindicated:** three consecutive `queued` reads preceded `sent` — a single read straight
      after `sendNow` would have seen a non-terminal status and failed a healthy send. The polling
      design is load-bearing, not defensive padding.
- [x] `BREVO_LIST_ID` restored to **7**; test list 8 emptied or deleted. **Re-verified after the
      gates, 2026-07-27:** switched to 8 for V5/V4, restored to **7** and confirmed via
      `gh variable list`. List 8 is empty (Rick emptied it for V4 Option A).
      **Additional check not originally in the plan:** a `DRY_RUN=true` dispatch against list 7
      (run `30275745271`) confirmed **`List 7 ("rjbookstop - Weekly Pull List"): 1 subscriber(s),
      0 blocklisted`** — so Tuesday's cron will clear the pre-send guard rather than fail closed on
      an empty target. Worth keeping: restoring the variable proves *where* the send points, not
      that the destination is healthy. That dry run left draft campaign **22** in Brevo; delete it.
- [x] F96 and F98 marked resolved with the date in `technical-reference.md` § 13 and `CLAUDE.md`.
      **F98 resolved 2026-07-26** (fix live and verified). **F96 resolved 2026-07-27** — V4 showed
      the Action going red *and* GitHub delivering the failure notice, V5 showed a healthy send still
      passing. The § 13 entry records one residual rather than glossing it: the post-send status
      assertion has never been observed rejecting a genuinely *suspended* campaign, because that
      state is unreachable once the pre-send guard exits first. Closure rests on the pre-send guard
      — the one proven live, and the one that would have caught this exact outage — plus the
      live healthy-path poll and 9/9 stubbed scenarios.
- [x] `docs/weekly-pipeline-consolidation-plan.md` updated to describe the single-commit publish.

### Added at execution — worth carrying forward

- [x] **V2 must run before any live publish.** It caught four things a diff review would not:
      the wrong-week default, a stale-replica ref read that aborted a successful publish, the
      unreachable no-commit path, and the dual-publisher hazard. The scratch-branch rehearsal
      earned its place in the plan.
- [x] **Next Tuesday (2026-07-28 22:00 UTC) is the first unattended run of the new send script.**
      If S3 misbehaves it fails closed — no delivery, red Action — which is the intended posture but
      still a missed week. Running V5 before then is the cheap insurance.
      **Insurance taken 2026-07-27**, ~32 hours ahead of the cron: V5 exercised the full healthy
      path end to end against the real Brevo API, and V4 exercised the abort path. Both behaved as
      designed, so the unattended run is no longer the first real exercise of this code.

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
