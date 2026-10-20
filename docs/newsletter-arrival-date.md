# Weekly newsletter: show the on-sale date beside "This Week's Releases"

**STATUS:** NOT STARTED · decisions D1-D5 ACCEPTED 2026-10-20 · execution GATED on F135 close-out · target issue Tue 2026-10-27 · repo `weekly-pull-feed` (no staging/prod split; `main` is live) · findings none (feature, no ID)

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
| `newsletter-email.html` (Brevo email) | inbox | Same masthead (`:1556`); preheader says "on sale Wednesday" with no date (`:1499`) | Section label (`:1726`) has no date. **The subject uses the SEND date** (`send-brevo-campaign.js:122-133`), so tonight's reads "Weekly Previews - October 20, 2026" over a masthead reading October 21 |
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
