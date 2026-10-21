# Weekly newsletter: show the on-sale date beside "This Week's Releases"

**STATUS:** IN PROGRESS · BUILT and pushed 2026-10-21 (`weekly-pull-feed` `main` `800f460d`, E0-E8 done), awaiting its first real send, the Tue 2026-10-27 cron (E9 open) · decisions D1-D5 ACCEPTED 2026-10-20 · F135 gate passed (E0) · repo `weekly-pull-feed` (no staging/prod split; `main` is live) · findings none (feature, no ID) · **one design call open for Rick: see § 6.3 (the date line is faint)**

Planned 2026-10-20. Rick's request: wherever a reader sees "This Week's Releases"
(the newsletter web page, the RSS feed that drives `rjbookstop.com/news`, and
probably the email), also say when the books land, for example
**"On sale / in store Wednesday, October 21, 2026"**.

**Nothing changes before F135 closes.** Tonight's cron (Tue 2026-10-20 21:00Z) is
F135 S5's closing observation, and this work edits the same builder. Read that run
first (reminder Wed 10-21), then build this for the **Tue 2026-10-27** issue.

---

## 1. What a reader sees today (measured 2026-10-20)

All three outputs come from one file, `weekly-pull-feed/scripts/build-pull-feed.js`,
built every Tuesday by the `Send Weekly Newsletter` workflow.

| Surface | Where the reader sees it | Date shown today | Problem |
|---|---|---|---|
| `newsletter.html` (web page) | `mrcyberrick.us/weekly-pull-feed/newsletter.html` | Masthead only: "Ray & Judy's Book Stop · October 21, 2026" (`:972`) | The section label "This Week's Releases" (`:1316`) has no date; the masthead has no weekday and no "on sale" |
| `newsletter-email.html` (Brevo email) | inbox | Same masthead (`:1556`); preheader says "on sale Wednesday" with no date (`:1499`) | Section label (`:1726`) has no date. **The subject uses the SEND date** (`send-brevo-campaign.js:122-133`), so tonight's reads "Weekly Previews - October 20, 2026" over a masthead reading October 21 ***(Corrected 2026-10-21: the email HTML has no `<title>`, so the send script has always used its fallback prefix, and the 10-20 subject read "This Week's Comic Previews - October 20, 2026", read from run `39516136199`. The two-dates mismatch is real; the "Weekly Previews" prefix quoted here was not.)*** |
| `rss.xml` | `rjbookstop.com/news` (the "Weekly Pull Feed" column), Flipboard, any RSS reader | Each item's `<pubDate>` = **the build time** (`:1825`). The live feed reads `Wed, 14 Oct 2026 00:08:16 GMT` | `rjbookstop.com/news` prints that date on **every card** (`news/index.html:1004`) and as "Updated Tue, Oct 13, 2026" in the header (`:918`). So last week's cards said **Oct 13**, the day before the books arrived. `buildRssXml()` is never given the on-sale date at all |

Also in the RSS: every item's description says the title "is now available ... and
is ready for pickup or delivery" (`:1848-1851`). On a Tuesday preview that is
untrue for a day.

**Where the date comes from.** `get_pull_feed_week` already returns `on_sale_date`
per row, and the builder already picks the week's date (`dominantOnSaleDate()`,
`:276`, the most common date, ties to the latest) and hands it to the web page and
email. Measured on production: the 10-12 week was 119 rows, all 2026-10-14; this
week is 133 rows, all 2026-10-21. **No database, RPC or app change is needed.**

## 2. The change

One date string, built once, used everywhere:

- `formatOnSale(onSaleDate)` returns e.g. `Wednesday, October 21, 2026`. Parsed
  from local date parts (the F28 rule, as the masthead code already does), and the
  **weekday comes from the date**, never hardcoded: CLAUDE.md says Wednesday is not
  special, and a holiday week can ship another day.
- **Web page and email, section label:** keep "This Week's Releases" as the
  heading and add one line under it:
  `On sale / in store Wednesday, October 21, 2026`, above the existing
  "One cover per series · 133 titles arriving" line.
- **Email preheader:** "133 new titles on sale Wednesday, Oct 21 ..." (the inbox
  preview line).
- **RSS:**
  1. Pass `{ onSaleDate }` into `buildRssXml()` (today it gets only the rows).
  2. Channel `<description>`: "This week's releases, on sale / in store
     Wednesday, October 21, 2026."
  3. Item description: replace "is now available ... ready for pickup" with
     "On sale / in store Wednesday, October 21, 2026 at Ray & Judy's Book Stop."
     (keep it over the 300 characters Flipboard wants).
  4. Item `<pubDate>`: see decision D3.

**Size:** the email is 72.8 KB at 119 titles against the script's 95 KB clipping
warning; one line adds about 200 bytes. Tonight's 133 titles will show the real
headroom; check it in the run log.

## 3. Decisions for Rick

**All five ACCEPTED as recommended, Rick, 2026-10-20** ("Accepted"): D1 email
included, D2 "On sale / in store", D3 RSS item date = on-sale date at noon
Eastern, D4 website header deferred (not in this work), D5 email subject uses the
on-sale date. Confirmed the same day that none of them blocks other project work.

| # | Question | Recommendation (accepted) |
|---|---|---|
| D1 | Include the email too, or only the web page and RSS? | **Include it.** Same function shape, same release, and the web page is the email's "view online" twin; changing one leaves them disagreeing |
| D2 | Wording | `On sale / in store Wednesday, October 21, 2026` (your example). Alternative: `In store Wednesday, October 21, 2026` |
| D3 | RSS item `<pubDate>`: keep the build time, or use the on-sale date (noon Eastern)? | **Use the on-sale date.** Every card on `rjbookstop.com/news` would then read "Oct 21, 2026" with no website change. Noon, not midnight: midnight UTC renders as the previous day in New Jersey. Cost: for about 20 hours the date is in the future. That is allowed by RSS; whether Flipboard hides future-dated items is **not verified** (check its view after the first issue). The channel `<lastBuildDate>` stays the real build time |
| D4 | Change the `rjbookstop.com/news` column header ("Updated Tue, Oct 13") to read the on-sale date? | **Later, optional.** It needs a website change, and that site is **not in git** (only `site.zip` beside it), so a change there has no history or rollback. D3 already puts the date on every card |
| D5 | Email subject: send date (Oct 20) or on-sale date (Oct 21)? | **On-sale date**, worded as "Weekly Previews - on sale Wednesday, October 21". A small edit in `send-brevo-campaign.js`; it fixes the existing two-dates mismatch. Skip if you prefer to keep the send script untouched |

## 4. Impact

- **Files:** `weekly-pull-feed/scripts/build-pull-feed.js` (four spots plus the
  helper); `send-brevo-campaign.js` only if D5 = yes; one new unit test file in
  `weekly-pull-feed/test/`. The workflow and the Monday preflight already run
  `node --test test/*.test.mjs`, so the test guards every future build.
- **Not touched:** the database and `get_pull_feed_week`, the PULLLIST app, Edge
  Functions, the workflow YAML, thumbnails and their retention, the Brevo list.
- **Existing safety unchanged:** a week with no rows still fails before anything
  is built (`checkWeek()`), so there is never a missing date in a published issue.
  The masthead's "today" fallback stays as it is.
- **RSS readers that already hold an item:** item GUIDs are the cover URLs, so a
  cover that repeats from an earlier week may not show the new wording in some
  readers. `rjbookstop.com/news` re-reads the whole feed, so it always shows it.
- **Multi-tenant work (W2-W5):** unaffected; the date comes from the data. The
  "Ray & Judy's Book Stop" text in the new RSS sentence is the same founding-tenant
  wording the masthead already uses, and moves to the tenant profile with W2.
- **Risk if wrong:** a wrong or missing date in one week's issue. The email cannot
  be recalled once sent, which is why section 5 builds it locally first.

## 5. Execution runbook (new CLI session, after F135 closes)

All work is in the **`weekly-pull-feed`** repo
(`C:\Users\richa\OneDrive\Documents\(Work)\BookStop\weekly-pull-feed`). Its `main`
is what the Tuesday cron builds and sends, so there is no staging step: the
local build (E5) and the scratch-branch rehearsal (E6) are the staging
equivalent. **Any failed check is a halt-and-report, not an improvise.** Line
numbers below were read 2026-10-20; re-read the file and locate each spot by its
anchor text before editing.

### E0. Gate: F135 is closed

Read the Tue 2026-10-20 `Send Weekly Newsletter` run log. It must show a
`github-actions[bot]` commit for the 2026-10-21 week, `N/N served` and
`Campaign <id> confirmed SENT`. Then close F135 S5 in
`docs/f135-decouple-feed-publish.md`, `docs/technical-reference.md` § 13 F135 and
`CLAUDE.md` (doc-only commit to `comic-preorder` `staging`). **If that run failed,
stop here:** F135 is not closed and this work waits.

Also: `git -C weekly-pull-feed pull`, confirm a clean tree, and run
`node --test test/*.test.mjs` once to record the starting count.

### E1. The date helper (in `build-pull-feed.js`, beside `dominantOnSaleDate()`)

- `formatOnSale(iso)` → `'Wednesday, October 21, 2026'`; `formatOnSaleShort(iso)`
  → `'Wed, Oct 21'`. Build the date from split parts
  (`new Date(+y, +m - 1, +d)`, the masthead's existing pattern, F28); weekday
  from the date; `null`/empty input → `null`.
- `onSaleNoonEasternRfc822(iso)` → the RFC-822 string for 12:00 noon
  America/New_York on that date (`Wed, 21 Oct 2026 16:00:00 GMT` in EDT,
  `17:00:00 GMT` in EST). Compute the offset for that date; do not hardcode -4.
- Export all three in the existing `module.exports` list.

### E2. Unit tests: write them first and watch them fail

New `test/on-sale-date.test.mjs` (the workflow and the Monday preflight run
`test/*.test.mjs`, so it guards every later build):
- `2026-10-21` → Wednesday, October 21, 2026; `2026-10-22` → Thursday;
  `2026-12-31` → Thursday, December 31, 2026 (year edge).
- The same results when run under `TZ=UTC` and `TZ=America/Los_Angeles`
  (spawn `node --test` with each, or assert inside via `process.env.TZ` and a
  child process). No day shift either way.
- Noon Eastern: `2026-10-21` → `16:00:00 GMT`; `2026-11-04` (after the DST
  change, 2026-11-01) → `17:00:00 GMT`; and `new Date(result)` read back in
  `America/New_York` is the same calendar date.
- `null` input → `null`, never a throw.
Run before E1 exists (red), then green after.

### E3. Web page and email (`buildNewsletterHtml()` and `buildEmailHtml()`)

Under the "This Week&rsquo;s Releases" label (anchors `:1316` page, `:1726`
email), add one line ABOVE the existing "One cover per series" line, same
styling as that line:
`On sale / in store ${formatOnSale(onSaleDate)}`. Omit the line entirely if the
helper returns null.

Email only:
- Preheader (`:1499`): `${shipmentCount} new titles on sale ${formatOnSaleShort(onSaleDate)}`
  followed by the existing "&mdash; stop in before your favorites are gone".
  Fall back to the current "on sale Wednesday" text if the date is null.
- Add a machine-readable stamp next to the existing one (`:1491`):
  `<!-- pull-feed-onsale: ${onSaleDate} -->` (only when the date exists). E7
  reads it.

Leave the masthead, the promo copy ("know what's coming Wednesday") and every
other line alone.

### E4. RSS (`buildRssXml()`)

1. Signature `buildRssXml(rows, thumbMap, meta = {})`; pass `{ onSaleDate }` at
   both call sites (`publishPullFeed()` and `buildLocal()`).
2. Channel `<description>`:
   `This week's releases, on sale / in store ${formatOnSale(onSaleDate)}. Weekly pull list with thumbnails and links to full-size cover images.`
3. Item description text: replace the "now available ... ready for pickup or
   delivery" sentences with
   `${safeTitle} is part of this week's pull list at Ray &amp; Judy's Book Stop, on sale / in store ${formatOnSale(onSaleDate)}. `
   plus the existing "Click the cover image ..." sentence, and keep the whole
   text over 300 characters (Flipboard). Assert the length in the test.
4. Item `<pubDate>` = `onSaleNoonEasternRfc822(onSaleDate)`. Channel
   `<pubDate>` and `<lastBuildDate>` stay the real build time.
5. If the date is null, keep today's behaviour for all four (unreachable in a
   publish, because `checkWeek()` fails first, but the local build can hit it).

### E5. Local build and inspection (nothing published)

```bash
cd "/c/Users/richa/OneDrive/Documents/(Work)/BookStop/weekly-pull-feed"
SUPABASE_URL=https://plgegklqtdjxeglvyjte.supabase.co SUPABASE_ANON_KEY=<prod anon key from comic-preorder origin/main:config.js> \
  node scripts/build-pull-feed.js --local --week=2026-10-21
```
(The anon key is public by design. Use the 10-21 week: it has real rows.)
Check in `scripts/pull-feed-out/`:
- Both HTML files at 1350 px and 390 px in a real browser (screenshots
  inspected, not inferred): the date line is under the label and reads
  "On sale / in store Wednesday, October 21, 2026"; no horizontal scroll.
- The email preheader text and the `pull-feed-onsale: 2026-10-21` stamp.
- `rss.xml`: parses as XML; every item's `<pubDate>` is
  `Wed, 21 Oct 2026 16:00:00 GMT`; descriptions carry the new sentence;
  `lastBuildDate` is now.
- Email size below the 95 KB warning (record it).
- **rjbookstop.com/news check:** copy `rjbookstop/news/index.html` to the
  scratchpad, point its `FEED_URL` at the local `rss.xml` (serve the folder
  with a local static server so `fetch` works), open it in a browser with the
  timezone set to America/New_York, and confirm every card reads
  "Oct 21, 2026". Do not edit the real site (D4).
- Diff against the published `newsletter.html` / `newsletter-email.html` /
  `rss.xml` on `main`: the only differences should be this change plus the
  week's content and timestamps.

### E6. Rehearsal on a scratch branch (optional, recommended)

`node scripts/build-pull-feed.js --publish --branch=scratch --week=2026-10-21`
(needs a `GITHUB_TOKEN` with repo write; Pages never serves `scratch` and
nothing is sent). Read the commit's tree, then delete the `scratch` branch.

### E7. Email subject (`send-brevo-campaign.js`, D5)

In the subject block (`:119-133`): read `pull-feed-onsale` from the HTML with the
same regex style as `check-stamp.js`'s `readStamp()`. When present, the subject is
`${title} - on sale ${formatOnSaleShort-style 'Wednesday, October 21'}` (e.g.
"Weekly Previews - on sale Wednesday, October 21"); when absent, keep today's
send-date subject exactly. Format from split parts, not `new Date(iso)`. Touch
nothing else in this script (the F96 send verification stays as it is). Verify
with a dry run that creates the Brevo draft without sending (the script's
dry-run mode; read how it is invoked locally before using it) and read the
subject it prints.

### E8. Commit and ship

- Full `node --test test/*.test.mjs` green; count = E0's count + the new tests.
- One commit to `weekly-pull-feed` `main` (message via `-F`/heredoc, not
  PowerShell `-m`), push, confirm on origin. **Land it by Mon 2026-10-26** so the
  Monday preflight (which runs the tests) proves it a day before the send.
- **Do not dispatch a send.** The Tue 10-27 21:00Z cron builds and sends it.

### E9. After the Tue 10-27 send (same or a later session)

Read the run log (green, `Campaign <id> confirmed SENT`), then check, and record
what was actually observed, separately from anything reported:
the delivered email (subject, preheader, date line; headers only if Rick pastes
it); the live `newsletter.html`; `rss.xml` item dates; `rjbookstop.com/news`
cards reading the on-sale date; and Flipboard's view of a future-dated item
(D3's open question). Then set this doc's STATUS to COMPLETE and add a dated
line to `CLAUDE.md` § Current Migration Phase.

**Rollback:** `git revert` the E8 commit on `weekly-pull-feed` `main` before the
next Tuesday. A sent email cannot be recalled, which is why E5 comes first.

---

## 6. Execution record (2026-10-21, E0-E8)

Written from the commands' own output, in the order they ran. **E9 is still open.**

### 6.1 What ran

| Step | Result | Evidence |
|---|---|---|
| E0 gate | PASS | Run `39516136199` (`schedule`): bot commit `17eaf1f2` for 2026-10-19..25, `55/55 served`, `Campaign 38 confirmed SENT`. The F135 close-out was already recorded (`f135-decouple-feed-publish.md` § 11.7, `technical-reference.md` § 13, CLAUDE.md; commits `d7d13b9`, `fe2fa1d`), so there was no new E0 doc commit. Start state: clean tree, `main` `17eaf1f2`, **49/49** tests |
| E2 red | PASS | 18 of 21 new tests failed before the helpers existed. The 3 that passed are the "no date = unchanged" guards, i.e. today's behaviour pinned as the baseline. The three builders were exported first with no behaviour change, so the builder tests failed on assertions (date line absent, 0 bytes added, wrong `pubDate`), not on "not a function" |
| E1, E3, E4 | PASS | Helpers, page, email and RSS built; format and offset tests run in child processes under five time zones (UTC, Los Angeles, New York, Honolulu, Auckland). **Negative controls:** three injected breakages (format via `new Date(iso)`, a hardcoded -4 offset, item `pubDate` = build time) each went red on the intended tests (8, 7 and 1 failures); file restored by hash each time |
| E5 local build | PASS | Week 2026-10-21, 133 rows (`2026-10-21x133`). Against the published files: the page differs by the one new line (4 added lines), the email by the new stamp, preheader and date block, and the RSS by **exactly 269 lines** (133 item `<p>`, 134 `<pubDate>`, `lastBuildDate`, channel `<description>`). `rss.xml` parses (Python `ElementTree`): 133 items, every item `Wed, 21 Oct 2026 16:00:00 GMT`, channel dates = build time, item text 364-462 characters. **Sizes:** email 74,964 B (73.2 KB, under the 95 KB warning; published blob 74,639), page 80,826 B (80,597), `rss.xml` 268,829 B (256,007, +5%) |
| E5 browser | PASS 24/24 | Chromium. Page and email at 1350 and 390 px: label, then date, then count line; same style as the count line; no horizontal scroll; no page errors. Scratch copy of `rjbookstop/news/index.html` with its **worker URL** repointed (it tries a Cloudflare Worker before `FEED_URL`, so changing `FEED_URL` alone would still have shown the live feed): all 133 cards read "Oct 21, 2026" in New York, Los Angeles and Honolulu. **Control:** the same harness on the published feed reads "Oct 20, 2026" on all 133. Screenshots inspected |
| E6 rehearsal | PASS | `scratch` created from `main`, `--publish --branch=scratch --week=2026-10-21`: one commit `a920b350`, 4 artifacts, 0 thumbnails uploaded, 326 files verified. Page and email **byte-identical** to the local build; `rss.xml` differs only in the channel's build-time seconds. `main` unchanged, `scratch` deleted (0 left). This is the only step that exercised `publishPullFeed()`'s `buildRssXml(...)` call site |
| E7 subject | PASS, with a limit | The real script driven against a **stub of Brevo's API** (no Brevo key exists outside the repo's GitHub secrets, so no real draft was created). Built email: `This Week's Comic Previews - on sale Wednesday, October 21`, identical under four time zones. With a `<title>Weekly Previews</title>`: `Weekly Previews - on sale Wednesday, October 21` (the plan's example). Stamp 2026-12-31: `... on sale Thursday, December 31`. **No stamp, and an impossible stamp (2026-02-31): identical to the pre-change script run on the same file.** Recorded POST: campaign name `weekly-pull-feed 2026-10-21`, 74,964 B body |
| E8 ship | PASS | **70/70** (49 + 21). Commit `800f460d` pushed to `weekly-pull-feed` `main`, local = `origin/main` = `ls-remote`. **No send dispatched.** Extra: the read-only `Newsletter Preflight` dispatched once (run `39607704459`, `workflow_dispatch`) at that commit: success on `ubuntu-latest` with Node 22, every new test `ok`, `OK: 133 shipment row(s) ... Tuesday's build has what it needs`. It holds no Brevo credentials and publishes nothing; it is the only way to run the tests on the platform that runs them on Tuesday |

### 6.2 Deviations from the plan

1. **Item text length.** The plan's replacement (the new sentence plus "Click the cover image ...") is about 220 characters, not over 300. The new test caught a 298-character worst case (a one-letter title). Added two neutral sentences about the newsletter itself ("This release is featured in the Weekly Previews, the shop's weekly look at the new comics and books arriving that week. Check back every week to see what is coming in."); shortest item on real data is now 364. No pickup or delivery claim.
2. **Subject prefix kept as it is** (see the correction in § 1). With no `<title>` in the email, the Tue 10-27 subject will read **"This Week's Comic Previews - on sale Wednesday, October 28"**, not "Weekly Previews - on sale ...". If Rick wants the latter, it is the fallback string in the subject block of `send-brevo-campaign.js`, one line, to land before Mon 10-26.
3. **E7 used a stub**, not a real Brevo draft (above).
4. `buildNewsletterHtml`, `buildEmailHtml` and `buildRssXml` are now exported, for the tests; no behaviour change.
5. The XML comment inside each RSS `<item>` was left as it was (it ships 133 times, so reword it only in the JS comment).

### 6.3 Open for Rick: the date line is faint

Built to the plan ("same styling as that line"): 10px `#5a5755` on `#222222`, about **2.2:1** contrast, the same grey as the count line under it. In the screenshots at both widths it is in the right place and correct, and hard to read: the one line that carries the point of this feature is the faintest thing in the section. A legible alternative was rendered (scratch files only): `font-size:12px; color:#9a9390` (about **5.3:1**, a colour the cover titles already use), still one line at 390 px, no horizontal scroll. It is a two-spot edit (the new date `<div>` in `buildNewsletterHtml()` and in `buildEmailHtml()`, each carrying `font-size:10px;color:#5a5755`), no test change. **Default if Rick does not decide: it ships as built.** The change can land any time before the Tue 10-27 cron; before Mon 10-26 lets the preflight cover it.

### 6.4 Not verified

- Flipboard's handling of an item dated about 20 hours after it is built (D3's open question) and the delivered email (subject, preheader, rendering, Gmail clip headroom): both are E9.
- `rjbookstop.com/news` on the live site: only a scratch copy was run. A reader far enough east (UTC+8 and beyond) would see the next calendar day on a card, since 16:00 GMT is already midnight there: inferred from the arithmetic, not tested; the shop's readers are in New Jersey.
- The first real cron with this code (Tue 10-27, on sale Wed 10-28); anything outside Chromium (no Outlook, Apple Mail or real phone).

### 6.5 Observed, not changed

`send-newsletter.yml` still carries a note to move the cron to 22:00 UTC when EST resumes; the cron stays 21:00Z (Rick's DST decision, 2026-10-13). Workflow YAML was out of scope.

**E9 remains:** after the Tue 10-27 send, read the run log and check the items listed in E9, record what was observed separately from anything reported, set STATUS to COMPLETE and add the dated line to CLAUDE.md.

Gate scheduled (2026-10-21): E9 cannot be read before the Tue 2026-10-27 21:00Z cron has sent (observed start delays +2 to +3 h, so the send lands late evening ET); earliest valid read is the next morning, Wed 2026-10-28 (day of week checked from the system). Reminder: cloud routine `trig_01Kpb3eVPBVbRg1AmgMsiAUs` (one-shot, reminds only) and Google Calendar event `li1lk2igq27mp398m4hjgot1ns`, both Wed 2026-10-28 8:00 AM ET. **No reminder was set for § 6.3** (the faint date line / subject prefix): it is a decision with a safe default (ships as built), not a gate, so Rick's own deadline for changing it is Mon 2026-10-26.
