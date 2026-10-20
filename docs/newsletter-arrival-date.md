# Weekly newsletter: show the on-sale date beside "This Week's Releases"

**STATUS:** NOT STARTED · staging n/a · prod n/a · PR none · findings none (feature, no ID)

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

| # | Question | Recommendation |
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

## 5. How to build and verify (execution session, after F135 closes)

1. Read the Tue 10-20 run (F135 S5) and close F135 first. If it failed, this waits.
2. Unit test `formatOnSale()`: `2026-10-21` gives `Wednesday, October 21, 2026`;
   a Thursday date gives Thursday; and run it under `TZ=America/Los_Angeles` and
   `TZ=UTC` to prove no day shift. Watch it fail before the helper exists.
3. Local build, nothing published:
   `node scripts/build-pull-feed.js --local --week=2026-10-21` (needs
   `SUPABASE_URL` and `SUPABASE_ANON_KEY` set; the anon key is public by design)
   writes to `scripts/pull-feed-out/`. Open both HTML files at desktop and phone
   width and read `rss.xml`. Check the date line, the preheader and the
   description wording.
4. Point a copy of `rjbookstop.com/news/index.html` at the local `rss.xml` and
   confirm the cards read "Oct 21, 2026" (D3), in a browser set to Eastern time.
5. Commit to `weekly-pull-feed` `main` before Tue 10-27; the 21:00Z cron
   publishes and sends it. Optional rehearsal first: `--publish --branch=scratch`
   (the builder's own documented rehearsal), which commits to a scratch branch
   that Pages never serves and sends nothing.
6. After the 10-27 send: read the delivered email, the live web page,
   `rjbookstop.com/news` and Flipboard's view (D3's open question), and record
   the result in this doc's STATUS line.
