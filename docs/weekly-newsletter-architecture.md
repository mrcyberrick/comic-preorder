# Weekly newsletter — decoupled, multi-tenant architecture (PLAN)

**STATUS:** IN PROGRESS 2026-10-13 — W0 DONE, W1.1 DONE (scripts repo `fc044f9`, on `origin/main`), W1.2 DONE (`weekly-pull-feed` `c0a423c`; red and green both observed), W1.3 DECIDED (cron left at 21:00Z); **W1 gate PASSED 2026-10-21: the Tue 2026-10-20 cron read from its log (§ 9), so W1 is DONE and F135 is RESOLVED**; W2-W5 NOT STARTED; **product direction decided 2026-10-14 (§ 4: D3 tiers, D7 invoice content, D8 two hidden providers, D9 self-service shipment upload first); **D10 decided 2026-10-22: measure by clicks and app events, not opens; W1b (newsletter attribution) added, NOT STARTED, before W2** | staging=— | prod=— | findings=F135 (finishes it),F131,F169,F72,F172
**Owner:** Rick. **Planning:** this doc. **Execution:** one session per W-step (§ 5), Sonnet CLI.
**Repos touched by execution:** `mrcyberrick/weekly-pull-feed` (public, where the newsletter now
runs), the private scripts repo (`catalogs/scripts`, only to remove the old path), and this repo
(docs, and later one SQL migration plus a Settings panel). **No change to the customer app until W4.**
**Last verified against live:** 2026-10-13. Read-only: `weekly-pull-feed` `main` (workflow, builder,
send script, run log `37551468895`), its repo variables and secret names, both copies of
`build-pull-feed.js`, the scripts repo `import.js`, and the local branch
`claude/newsletter-feed-decoupling-akur2e`.

---

## 0. What is true today, measured 2026-10-13. Read this first: the repo's own records are wrong

**The newsletter is already decoupled from the import, and has been since 2026-10-01.** CLAUDE.md,
`docs/f135-decouple-feed-publish.md` (on `staging`) and § 13 F135 all still say F135 is DEFERRED.
They are stale, because the record of the work never reached `staging`:

| Fact | Evidence |
|---|---|
| The build runs inside `weekly-pull-feed`'s send workflow, from the database, Tue 21:00 UTC | `send-newsletter.yml` on `main`, feature commit `ca8a7ed9` (2026-10-01) |
| It reads data through an anon RPC, `get_pull_feed_week(p_slug, p_week_start)`, returning only `title, cover_url, series_name, on_sale_date`. **Applied on both environments 2026-10-01** | `docs/sql/2026-10-01-f135-pull-feed-week-rpc.sql`, which exists **only** on the local branch below |
| The first unattended cron (Tue 2026-10-06, ran 10-07 00:20Z) was **green end to end**: 72 titles, one commit `cd1412bb`, 32/32 images served, stamp checked, Brevo campaign **35 confirmed SENT** to list 7 (12 subscribers) | run `37551468895` log |
| **The old path is still live too.** `import.js` still publishes at shipment-import time with Rick's PAT: commit `faf6feaf` (2026-10-10, 119 titles) was authored by `mrcyberrick`, not the Actions bot | `weekly-pull-feed` git log; `import.js:2260-2279` |
| **Two copies of `build-pull-feed.js` exist** (scripts repo 1,875 lines, `weekly-pull-feed` 1,927). The differences are infrastructure only (config, data path, week rule); the scripts copy's last edit was 2026-09-16, before the move, so the templates have not drifted **yet**. The `weekly-pull-feed` copy is canonical (its own header says so) | `diff`, 366 lines |
| **The F135 cutover record is on a local-only branch.** `claude/newsletter-feed-decoupling-akur2e` holds 9 doc commits; `origin` has only the first 4. The commit that says "cutover landed" (`2697545`) was never pushed. The branch was cut from `main`, not `staging` | `git branch -a --contains` |

So F135 is at **S3 done, S4 not started** in its own runbook's terms. That is the starting point for
this plan, not a blank page.

*(Updated 2026-10-13, same day, after W0 and W1.1: the cutover record row above is **fixed**, the 9
commits are on `staging` and the branch is deleted; and the "old path is still live" row is **fixed**
in the scripts repo (`fc044f9`, pushed): `import.js` and `import-staging.js` publish nothing and the
scripts-repo `build-pull-feed.js` is deleted. What still has to be observed is the first Tuesday
**without** an import-time publish (the closing gate, § 9). The table is left as written so the
before-state stays readable.)*

**Also open, from that branch's own § 11:** the Monday early-warning preflight was never built (Rick
had not ruled), the cron moves an hour when EST resumes (**Sun 2026-11-01**, the workflow's own
NOTE), and Brevo draft 34 was left from rehearsal.

---

## 1. Goal

One weekly pipeline that:

1. **Runs on its own clock from shipment records** — no laptop, no import side effect, no human in
   the loop to forget (F135 § 4.1: a quiet "nothing published" is worse than a loud failure).
2. **Builds the RSS feed and the newsletter from one rendering pass**, so they cannot disagree.
3. **Creates and sends a Brevo campaign**, and only reports green when Brevo says it was sent (F96).
4. **Can run for any tenant** whose shipment rows exist, with that tenant's identity, list and
   schedule, and with one tenant's failure never blocking another's.
5. **Can feed a third-party email service instead of Brevo**, so a shop that already has Mailchimp
   (or similar) can take the content without us holding its keys.

---

## 2. Target shape

```
          ┌──────────── per tenant ────────────┐
DATA      weekly_shipment ──► get_pull_feed_week(slug, week)        (exists, anon, F135)
PROFILE   tenant identity ──► get_newsletter_profile(slug)          (new, anon, public fields only)
ROUTING   delivery config ──► tenants.json in weekly-pull-feed      (new, operator-owned, no secrets)
                 │
RENDER    build-pull-feed.js: render(profile, rows) → artifacts      (pure; one source of truth)
                 │
PUBLISH   ONE commit for every tenant built this run  ──► GitHub Pages (one deployer, F100)
            /rss.xml, /newsletter*.html          ← founding, root paths kept forever (rjbookstop.com reads them)
            /t/<slug>/rss.xml, newsletter.html, newsletter-email.html, feed.json
            /thumbs/<md5>.webp                   ← one shared, content-addressed pool
                 │
DELIVER   adapter per tenant:
            brevo  → create campaign on the tenant's list in the platform Brevo account, send, verify
            pull   → nothing sent; the tenant's own ESP reads /t/<slug>/rss.xml or feed.json
            none   → feed only
```

**The four seams, and why each is separate:**

| Seam | Owns | Why separate |
|---|---|---|
| **Data** | which rows are this tenant's week | Already an RPC that returns only public columns. Multi-tenant by slug today |
| **Profile** | name, address, phone, app URL, CTA copy, enabled, schedule, timezone | Today it is ~15 string literals in two template functions (`build-pull-feed.js` 738, 920, 1238-1239, 1296-1302, 1350-1353, 1504, 1718-1733) and `SENDER_NAME` in the workflow. **The postal address is not decoration: CAN-SPAM requires it in every commercial email**, so each tenant's profile must carry one |
| **Render** | HTML and RSS from (profile, rows) | Must be a pure function so a byte-identical test can prove a refactor changed nothing |
| **Deliver** | getting the email to people | The only seam that differs by ESP. Keeping it behind one small interface is what makes "add-on to a third-party service" possible |

**Content-addressed thumbnails are already multi-tenant.** A thumbnail is `MD5(source cover URL)`,
and two shops receiving the same comic get the same cover URL, so a shared `thumbs/` pool
de-duplicates across tenants for free. The only change is that retention (14 days) must keep the
**union** of every tenant's references, not one tenant's.

**One commit per run, for all tenants.** F98/F100 were caused by many commits racing many Pages
builds. Per-tenant commits would bring that back in a new costume and also hit GitHub Pages' soft
limit of about 10 builds an hour. Build every due tenant, then publish once.

---

## 3. Delivery: Brevo first, third-party second

**Brevo, platform account (the default).** One Brevo account (Rick's, as today), one **list per
tenant**, campaign named `weekly-pull-feed <slug> <date>`. Sender: the tenant's name as display name.
Sender address: **one flat address on a dedicated marketing subdomain, e.g. `news.pulllist.app`,
authenticated in Brevo ONCE** (decided 2026-10-14, § 4 D8), with `replyTo` set to the shop's own
email. *(This read "one authenticated `pulllist.app` address (or the tenant's `<slug>.pulllist.app`,
which Brevo already authenticates for `rjbookstop`)". Per-tenant subdomains would mean per-tenant DNS
at every onboarding, and bare `pulllist.app` would share domain reputation with Resend's
transactional mail.)* `rjbookstop.pulllist.app` keeps working until the founding tenant is moved
over in W3. `BREVO_API_KEY` stays one repo secret. The
existing send script already does the hard part (pre-send zero-recipient abort, post-send status
poll, F96/F106); it gains a `slug` and reads list id and sender from `tenants.json`.

**Third-party ESP, pull model (the add-on).** We publish; their tool fetches. The tenant points
their ESP's RSS-to-email feature at `/t/<slug>/rss.xml`, or a developer reads `/t/<slug>/feed.json`
(new, structured: title, thumbnail, series deep link, on-sale date). **We hold no customer ESP
credentials**, so there is no per-tenant secret store to build, rotate or leak. Mailchimp, MailerLite
and Kit advertise RSS-to-email campaigns; **whether Brevo itself offers RSS campaigns, and how each
handles our image sizes and link tracking, is unverified** and is W5's discovery work, not an
assumption.

**Push to a tenant's own ESP (with their API key) is deliberately NOT planned.** It needs encrypted
per-tenant secrets, per-ESP send code and per-ESP failure handling. Revisit only if a paying tenant
asks for it and the pull model has been tried.

---

## 4. Decisions for Rick

| # | Question | Recommendation |
|---|---|---|
| **D1** | Reconcile the F135 records now (§ 5 W0)? | **Yes.** Cherry-pick the branch's 9 doc commits onto `staging` (it was cut from `main`, so a merge would drag `main`'s history in), then delete the branch. Doc-only |
| **D2** | Where does tenant identity live? | **Bootstrap in `weekly-pull-feed/tenants.json` (W2), move to the database when a second tenant exists (W4).** The file is public, which is fine: everything in it is already printed in every email. The DB home is `app_settings` key `newsletter`, edited on `settings.html`, read through an anon RPC returning only public fields. Delivery routing (list id, adapter) stays in the repo file either way: it is platform operations, not tenant identity |
| **D3** | Is the newsletter a paid-tier feature? | **Yes, as a paid add-on** (F72's `Tier` direction): a free tenant would carry its own name and address in mail sent from the platform's Brevo account, which is the "branded" thing the paid tier sells. Pull-model feeds could be free. **DECIDED 2026-10-14 (Rick): the managed email is the paid product; the public page and RSS feed are free. See the block below the table** |
| **D4** | Monday early-warning preflight (F135 § 4.5)? | **Build it in W1.** A read-only Monday run that fails if this week has no shipment rows turns a Tuesday-night miss into a Monday to-do; it costs one small workflow |
| **D5** | Per-tenant send time, or one Tuesday cron? | **A dispatcher**: an hourly Tuesday cron that sends each tenant whose local send time has arrived, from `schedule` + `timezone` in its profile. It also ends the twice-a-year DST edit. Until then (W1), move the cron for EST by 2026-11-01 |
| **D6** | F172: drop `(FREE)` 100%-discount promo rows from the feed? | Decide F172 first; if they belong out of the feed only, filter in the RPC, not the import |

---

**Rick's answers, 2026-10-13 (the W0/W1 session):** **D1 yes** (cherry-pick, then delete the branch). **D4
yes** (build the Monday preflight). **DST: leave the cron at `0 21 * * 2`** (D5's dispatcher remains the
long-term answer). Measured for that call: the 10-06 cron **started at 00:20Z on 10-07, 3 h 20 min after
its cron time**, past the 2 h 01 min the workflow header's table stops at, so a winter send starts at
4 PM ET plus the usual delay (roughly 4:30 to 7:20 PM ET). `send-newsletter.yml` was therefore **not
touched** in W1. If a winter arrival turns out too early or too late, the one-line edit is `"0 22 * * 2"`;
make it **after** the Oct 27 send and before Sun 11-01, not earlier, or it also moves the sends before the
DST change by an hour.

**Product direction, Rick, 2026-10-14 (a planning conversation; no code).** The newsletter is a
**funnel**: it shows customers what arrived and gets new people to sign up. The target owner is a
simple, non-technical shop, so the paid feature is a finished result, not a part to assemble.

- **D3 decided: tiers.** **Free:** a public "new this week at [shop]" page and its RSS feed, with a
  "Powered by PULLLIST" line (a third-party ESP can read the feed, supported by a how-to, not by
  engineering). **Paid:** the managed weekly email, sent in the shop's name to the shop's own
  subscribers, with nothing to configure beyond on/off, send day and time, an optional short store
  note and a preview. Its selling number is the sign-ups and reservations it brought in (the cover
  links already carry `ref=newsletter`). **Not built:** a template editor, segments, or a tenant's own
  ESP API key.
- **D7 decided: content comes from the shop's own shipment invoice, not the release schedule.** A
  release-schedule newsletter was considered as a default so a shop could start with no data, and
  **rejected by Rick**: it promotes books the shop does not have on hand, and it needs a full release
  catalog (both distributors, plus titles nobody reserved) that PULLLIST does not hold. The invoice is
  what makes the email worth sending.
- **D8 decided: two email providers, both invisible to the shop owner.** Resend stays the account-mail
  provider (no link rewriting, which a password reset needs; Brevo was rejected for that job on
  2026-09-02) and Brevo stays the newsletter provider (unsubscribe, bounce and click handling). The
  split also keeps newsletter complaints away from account-mail delivery. The friction to remove is
  per-shop setup, not the second provider: one sender on a dedicated subdomain (§ 3), sign-ups
  collected inside PULLLIST (opt-in at registration, an embeddable form, a counter QR code) and added
  to the shop's Brevo list behind the scenes. The owner never logs into either provider. Moving the
  newsletter to Resend's marketing product is possible but **untested** and would need an F99-style
  trial first; worth doing only if two accounts become a real burden.
- **D9 decided: self-service shipment upload is what the multi-shop newsletter waits on.** If the
  invoice is the content, the blocker is getting invoices in without Rick: a signed-in upload of the
  week's invoice files that feeds the bagging list, This Week, the reconciliation **and** the newsletter
  from one weekly step. Rick confirmed (2026-10-14) he is moving toward a self-service import process
  later, so this is aligned rather than new work. **Shipment upload is the light first slice of F131**:
  a weekly invoice is roughly 60 to 120 rows, against ~11,700 catalog rows for a monthly import, so
  F131's volume concern does not apply to it. POS integration is a later, automatic way to supply the
  same data.

**Open, not decided:** who owns a shop's subscriber list if it leaves, and how consent is recorded;
Brevo's free-plan daily send cap (300 a day when last checked, shared by every shop on the account)
and the paid plan the price must cover, **re-check current pricing**; whether an "expected this week"
fallback built from the order record is usable (not verified whether that record covers a shop's whole
order or only reserved titles and shelf-copy suggestions).

**D10 decided (Rick, 2026-10-22): measure the newsletter by clicks and what follows, not by opens.**
Rick saw it in Brevo's reports: opening the email recorded nothing, and only a click recorded both the
open and the click. Brevo counts an open only when the email loads a tracking image, so a mail app that
blocks images (Outlook by default, some Gmail and phone setups) never records one, while Apple Mail
preloads images and records opens nobody made. **No tool of ours can do better:** any open count is
the same kind of tracking image and is blocked or faked the same way, so an own-pixel was considered and
rejected. A click cannot be missed (the reader follows the link on purpose). **Found the same day:**
every cover link already carries `ref=newsletter` (S2/S3), but **nothing in the app reads it**
(`subscriptions.html` reads `series` only), so no visit, sign-up or reservation can be traced to the
newsletter today. That makes D3's selling number unmeasurable until W1b lands. The runbook step is
**W1b** (§ 5).

---

## 5. Runbook

Order is fixed by one rule carried from F135: **a new path is observed working before the old one is
removed.**

**W0 — doc truth (doc-only, ~30 min).** Cherry-pick `claude/newsletter-feed-decoupling-akur2e`'s 9
commits onto `staging`, resolving CLAUDE.md and § 13 conflicts in favour of the branch's content.
Record the Oct 6 cron result (§ 0). Flip the F135 CLAUDE.md row and § 13 status to "S3 done, S4
open". Delete the branch locally and on `origin`. **Gate:** `docs/sql/2026-10-01-f135-pull-feed-week-rpc.sql`
is on `staging` with `prod=APPLIED`, so `/promote-prod` step 0 sees it.

**W1 — finish F135 (scripts repo + `weekly-pull-feed`).**
1. S4: remove the publish block and `resolveFeedWeek()` (and its export and tests) from `import.js`
   and `import-staging.js`; delete `build-pull-feed.js` from the scripts repo; remove
   `GITHUB_TOKEN_PULL_FEED` from `.env` and revoke the PAT. Unit suite green; commit **and push**.
2. Monday preflight workflow (D4), negative-control tested (empty week → red).
3. DST: cron to `0 22 * * 2` before Sun 2026-11-01, or leave and accept 4 PM ET arrival (your call).
4. Delete Brevo draft 34.
**Gate (= F135 V5):** one Tuesday with no import-time publish: feed built from DB, correct week,
images served, campaign status `sent` read from the run log. **F135 closes here.**

**W1b — newsletter attribution (D10; added 2026-10-22, NOT STARTED).** Two repos, one app change.
1. **Builder (`weekly-pull-feed`):** add the issue's week to every app link, e.g.
   `ref=newsletter&w=YYYY-MM-DD` (the Monday of the issue), so a click names its issue. RSS links are
   unchanged unless Rick decides otherwise.
2. **App (`app.js` + the landing pages; `/deploy-staging`, then `/promote-prod`):** on any page load
   carrying `ref=newsletter`:
   - **signed in:** log one `usage_events` row (a new event type, e.g. `newsletter_click`, with the
     week and the series in its metadata), once per issue per browser;
   - **signed out:** keep `{ref, week, series}` in `localStorage` (bounded, e.g. 14 days) and carry it
     through sign-in or sign-up the way `PostAuthRedirect` carries `?series=`; when an account exists,
     log the event then, marked as a first visit. **The browser cannot write it while signed out:**
     since G-J (2026-10-22) `anon` holds no table privilege, so this is by design, not a workaround.
   - Every storage access wrapped (private windows throw), the same rule as the Catalog banner.
3. **Analytics (`analytics.html`):** a Newsletter card, built like the Catalog banner card: app clicks
   per issue, new accounts whose first visit came from the newsletter, reservations within 7 days of a
   newsletter click (labelled as following a click, not caused by it), and the most-clicked series. The
   new event type is split out of the page's other metrics at load, as the banner's events are.

**Limits, stated in the card:** counted per browser (a phone click and a laptop sign-up do not
connect); a signed-out click that never becomes an account is lost (Brevo's click count still sees
it); the 7-day window shows association only. **Gates:** an event row with the right `tenant_id`, week
and series for a signed-in click (read back from the database); a signed-out click followed by a
sign-in logs exactly one first-visit event; a reload logs nothing new; storage throwing logs nothing
and breaks nothing; the card's counts reconcile against a service-role count; each check seen red
first. **Sequencing:** do W1b BEFORE W2. W2's byte-identical gate must take its baseline from a build
that already has the new link parameter, or the comparison fails for a reason that has nothing to do
with the refactor.

**W2 — tenant profile, zero behaviour change (`weekly-pull-feed` only).**
Move every Book Stop literal (§ 2, Profile row) into `tenants.json` under `rjbookstop`, and make the
builder take `--tenant=<slug>`. Write output to both the root paths and `/t/rjbookstop/`.
**Gate:** the F135 V3 technique — for the same week, root `newsletter-email.html` and
`newsletter.html` **byte-identical** to the pre-refactor build, `rss.xml` identical except build
stamps; plus a test that a profile with a missing address **fails** (CAN-SPAM). Mutation-test it.

**W3 — orchestration (`weekly-pull-feed`).**
Matrix the build over enabled tenants in `tenants.json`, `fail-fast: false`; collect every tenant's
output and publish **one** commit; thumbnail retention over the union; send step per tenant with its
own list and an idempotency check (refuse if a campaign named for this slug and week already
exists). **Gate:** a rehearsal with a second, fake tenant pointed at Brevo test list 8: both build in
one commit, one deployment; a forced failure in the fake tenant leaves `rjbookstop`'s send green.
Then remove the fake tenant.

**W4 — profile in the database (when a second tenant is real).** `app_settings.newsletter`, an anon
`get_newsletter_profile(slug)` RPC (public fields only, `/sql-check`, staging then prod), a
Newsletter panel on `settings.html` (name, address, phone, send time, enabled, a preview link). This
is the first customer-app change and goes through `/deploy-staging` and `/promote-prod` normally.

**W5 — third-party pull + `feed.json`.** Publish `feed.json`; verify RSS-to-email on two real ESPs
(Mailchimp and one other) against `/t/<slug>/rss.xml`: images render, links survive their tracking,
Gmail clip under ~102 KB. Document it as a tenant-facing how-to. **Gate:** a real test campaign from
each ESP, read from the delivered message, not the ESP's dashboard.

---

## 6. What this plan does not solve — the real gates on tenant #2

The newsletter is downstream of shipment rows, and **only Rick can load shipment rows** today.

- **F131** — every tenant's catalog and shipments come from one operator's distributor portals.
- **F169** — the import cannot run for a one-distributor tenant at all.
- **F72 / F99** — the other transactional mail is still founding-branded.
- **Consent and list ownership** — each tenant's subscribers sit in Rick's Brevo account. Who owns
  that list if a tenant leaves, and how signups reach the right list, is a product decision before
  W4.

- **Self-service shipment upload (D9, added 2026-10-14)** — the shop uploads its own weekly invoice.
  This is the concrete form of the F131 gate for the newsletter, and the first slice of F131 to build.

So: **W0 and W1 are worth doing now** (they close F135 and remove a live dual-publish path). **W2 is
cheap and safe now** (its gate is byte-identical output). **W3-W5 wait for a real second tenant**,
which waits on F131 (starting with self-service shipment upload, D9) and F169.

---

## 7. Risks

| Risk | Mitigation |
|---|---|
| The two builder copies drift before W1 lands (someone edits the scripts copy) | Edit only `weekly-pull-feed`'s copy; W1 deletes the other. Called out in W0's CLAUDE.md update |
| Removing the import publish leaves no fallback if Tuesday's build breaks | `workflow_dispatch` `build-and-send` is the fallback and is proven (F135 § 11.4); `node scripts/build-pull-feed.js --publish` still runs locally |
| A refactor quietly changes the email | W2's byte-identical gate |
| A multi-tenant run double-sends | idempotency check on campaign name per slug and week (W3) |
| Root paths change and break rjbookstop.com | Root paths are a permanent alias for the founding tenant; never move them |
| GitHub Pages limits (repo ~1 GB soft, ~10 builds/hour) at many tenants | One commit per run; shared thumbnails; 14-day retention. Revisit hosting (e.g. an Edge Function serving feeds) only if a measured limit is approached |

---

## 8. Out of scope

Newsletter copy and visual design; Brevo list growth; transactional mail (Resend, F99); the import's
own data correctness (F172 is decided separately); pushing to a tenant's own ESP with their key.

## 9. Execution log

**2026-10-13, W0 + W1 session (Sonnet CLI).**

- **W0 done.** The 9 F135 doc commits were cherry-picked onto `staging` (no conflicts), the F135 row in
  CLAUDE.md and § 13 brought up to date from the Oct 6 run log (run `37551468895`: 72 titles, commit
  `cd1412bb`, 32/32 served, `Campaign 35 confirmed SENT`), and `claude/newsletter-feed-decoupling-akur2e`
  deleted locally and on origin after `git cherry` showed all 9 commits patch-equivalent on
  `origin/staging` and `git log origin/main..<branch>` showed exactly those 9 were unique to it. Gate
  read: `docs/sql/2026-10-01-f135-pull-feed-week-rpc.sql` line 1 on `origin/staging` is
  `-- STATUS: COMPLETE | staging=APPLIED 2026-10-01 | prod=APPLIED 2026-10-01 | findings=F135`.
- **W1.1 done** (scripts repo `fc044f9`, `origin/main`): publish block and `resolveFeedWeek()` out of
  both import scripts; `build-pull-feed.js`, `test/feed-week.test.mjs` (9) and
  `test/thumb-retention.test.mjs` (12) deleted, their coverage already in `weekly-pull-feed` (all 12
  retention test names present there). Unit suite **354 -> 333** (= -21 exactly). The grep gate returns
  0 lines. A `--no-write` dry run of `import-staging.js` with a Lunar + PRH shipment pair is
  **line-for-line identical** before and after (108 lines, exit 0). **Not verified:** `import.js`
  (production) was not dry-run; it was syntax-checked, unit-tested and diffed, and its removed regions
  mirror staging's. Its first real run is the next production shipment import.
- **W1.2 done** (`weekly-pull-feed` `c0a423c`): `scripts/preflight-week.js` +
  `.github/workflows/preflight-week.yml` ("Newsletter Preflight", Mon `0 13 * * 1` plus a `week` dispatch
  input) + `test/preflight-week.test.mjs` (14 tests; repo suite 35 -> 49; six mutations of the script each
  turned the intended tests red). Read-only by construction: `contents: read`, no Brevo reference, its own
  concurrency group, and the week rule and guards are *required from the builder*
  (`resolveTargetWeek`, `checkWeek`, `weekRange`, `todayUTC`), which was not edited. **Held until tonight's
  live send finished** (a push mid-build could have failed the build's ref update, and the build job runs
  every `test/*.test.mjs`). **Observed on the runner (Node 22), 2026-10-14 00:11Z:** RED, `workflow_dispatch`
  with `week=2030-01-09`, run `38488707429`: tests passed, then
  `No shipment rows for the week 2030-01-07 -> 2030-01-13. Run the weekly shipment import before Tuesday
  21:00 UTC...` and the run failed at that step. GREEN, default week, run `38488756358`:
  `OK: 119 shipment row(s) for 2026-10-12 -> 2026-10-18 (2026-10-14x119)`. **No commit, no Pages build, no
  send:** repo tip and the latest Pages build were `c0a423c5` before the first dispatch and after the
  second; the only runs created in between are the two preflights (the 00:10Z Pages build is the one my own
  push caused, before the baseline); the green run's steps are checkout, Node, tests and the check, nothing
  else. **Not verified:** Brevo's campaign list was not read (no Brevo key in this session); the evidence
  that no campaign was created is structural (no Brevo reference or secret in the workflow). The scheduled
  Monday 13:00Z trigger itself has not fired yet; its first fire is Mon 2026-10-19, and the gate reminder
  asks for that run to be checked.
- **Tonight's live send (Tue 2026-10-13 cron), read from its log:** run `38488388486`, `schedule`, started
  **2026-10-14 00:08Z, +3 h 08 min**; 119 titles for `2026-10-12 -> 2026-10-18`, one commit `4a56472b` by
  `github-actions[bot]`, `round 1: 52/52 served`, stamp built by this run, `Campaign 37 confirmed SENT`. A
  second start at ~3 h late (10-06 was +3 h 20 min). **This is NOT the S5 gate**: the import path was
  already removed in code, but no import has run since; the gate is the 10-20 cron after Rick's 10-16
  import.
- **W1.3 decided:** cron left at `0 21 * * 2` (§ 4). **Nothing was changed in `send-newsletter.yml`.**
- **Gate scheduled (2026-10-13):** the W1 closing gate (= F135 S5/V5, the Tue 2026-10-20 cron, the first
  Tuesday with no import-time publish) elapses with margin on **Wed 2026-10-21**; reminder: routine
  `trig_017vViYcKefTkoHgdLjC7ArP` and Google Calendar event `gihlvjlt0aregsctg1rvihtdog`, 8:00 AM ET.
  The reminder only reminds. Checks it lists: the Mon 10-19 preflight green; Rick's Fri 10-16 import
  published nothing; the Tuesday run is `schedule`, both jobs green, one `github-actions[bot]` commit for
  the right week, `N/N served`, `Campaign <id> confirmed SENT`. **F135 stays OPEN until that run is read.**
- **Rick-only, still owed:** delete `GITHUB_TOKEN_PULL_FEED` from the scripts `.env`; revoke that
  token on GitHub; delete Brevo draft campaign 34 (a dry-run rehearsal artifact).

**2026-10-21, W1 gate read (logs and commit list via `gh`, not the green tick).** All three checks pass;
full table in `docs/f135-decouple-feed-publish.md` § 11.7.

- **Mon 10-19 preflight:** run `39306709863`, `schedule`, green; started 18:56Z (the 13:00Z cron fired
  about +5 h 56 min late); `OK: 133 shipment row(s) for 2026-10-19 -> 2026-10-25`.
- **Fri 10-16 import published nothing:** the only `weekly-pull-feed` commit since 10-15 is `17eaf1f2`
  by `github-actions[bot]`; none by `mrcyberrick`.
- **Tue 10-20 send:** run `39516136199`, `schedule`, created 23:36Z (+2 h 36 min), `build` and `send`
  green; week `2026-10-19 → 2026-10-25`, 133 titles, ONE commit `17eaf1f2`, `55/55 served`,
  `Campaign 38 confirmed SENT.`
- **W1 DONE, F135 RESOLVED.** No send was dispatched by this session.
- **Rick-only clean-up DONE the same day:** the `.env` line is gone (checked), all three fine-grained
  PATs deleted and Brevo draft campaign 34 deleted (Rick's report). F135 has nothing left open.

## References

`docs/f135-decouple-feed-publish.md` (and the fuller version on branch
`claude/newsletter-feed-decoupling-akur2e`, `2697545`) · `docs/weekly-pipeline-hardening.md` ·
`docs/weekly-pipeline-consolidation-plan.md` · `docs/newsletter-acquisition-funnel.md` ·
`docs/f72-multi-tenant-branding.md` · `docs/technical-reference.md` § 13 F96, F98, F100, F106,
F131, F135, F169, F172.
