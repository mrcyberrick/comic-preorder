# Weekly Facebook post for Ray & Judy's Book Stop (PLAN + RUNBOOK DRAFT)

**STATUS:** IN PROGRESS 2026-10-14 — Rick signed off ("go"); **built and tested locally, NOT pushed** (`weekly-pull-feed` local branch `facebook-weekly-post` `2e1a1d1b`; SQL `docs/sql/2026-10-14-fb-spotlight-rpc.sql` staging=PENDING prod=PENDING); held until the F135 gate (Tue 10-20 run read); Rick's Meta setup (R1) and SQL runs owed; see § 8 | staging=— | prod=— | findings=none consumed
**Owner:** Rick. **Planning:** this doc. **Execution:** one Sonnet CLI session after sign-off, Meta steps Rick-in-the-loop.
**Repo touched by execution:** `mrcyberrick/weekly-pull-feed` only (public; where the newsletter runs). **No change to this repo's app code, no SQL, no Supabase change, no `config.js`.**
**Last verified against live:** 2026-10-14, read-only: `weekly-pull-feed` `origin/main` at `c0a423c5` (both workflows, `check-stamp.js`, `preflight-week.js`, the builder's exports), the live `rss.xml` and `newsletter.html` on GitHub Pages.

---

## 0. Summary in one breath

The weekly page this task asked to generate **already exists and is public**: `weekly-pull-feed` builds
`newsletter.html` and `rss.xml` from the database every Tuesday and publishes them to GitHub Pages
(F135, live since 2026-10-01). So the Facebook job does **not** generate a page. It is a small,
separate, read-only-on-the-repo workflow that runs after the newsletter, checks that this week's page
is published, checks the Page has not already been posted to this week, and makes one post that links
to that page (**the shop's own `rjbookstop.com/news/`, decided § 3b**, which renders the same feed). Dedupe is by **week**, not by RSS GUID, and the "state file" is the Facebook Page itself.
The post's picture is built fresh each week from the three covers the shop received the most copies
of (§ 3a), so there are no stock banners to maintain. That needs one new narrow database lookup (SQL
on staging, then production).

---

## 1. Findings (pre-work steps 1-3)

### 1.1 Conflicts between the task prompt and the repo (the repo wins)

| Prompt said | Repo says | Effect on this plan |
|---|---|---|
| "Supabase + GitHub Pages, mid-migration"; "production diverges until Phase 4 is complete" | Phase 4 closed 2026-05/06; Phase 5 (incl. 5.1, Cloudflare Pages) **closed 2026-07-15**; no active phase. The app is on Cloudflare Pages; production is live | No migration to wait for. "Staging-only" applies to the app repo; this work lives in `weekly-pull-feed`, which has one branch (`main`) and only reads **production** data (the builder refuses any non-production `SUPABASE_URL`) |
| "`config.js` is gitignored" | `config.js` is **tracked per branch** (CLAUDE.md § Credential Safety) | Not touched either way |
| "Generate a static this-week HTML page" | `newsletter.html` already is that page, rebuilt weekly by the Tuesday workflow | **No page generation.** Link to the existing page |
| "Covers, titles, prices, descriptions" | The page shows covers and titles only. The anon RPC `get_pull_feed_week` returns `title, cover_url, series_name, on_sale_date` and nothing else (deliberately narrow, F135) | Prices and descriptions are **out of scope for v1**: they need a widened RPC (SQL on both environments) and a page redesign. See § 3 Q7 |
| "Dedupe by feed GUID" | GUID = the full-size cover URL. The feed is **rebuilt whole every week**; items are not appended. Every item carries the same `pubDate` (the build time) | Dedupe on the **week** (Mon start date). Per-item GUIDs are the wrong unit for one post per week |
| "Store state in a small state file or table" | A file in `weekly-pull-feed` means a commit, which starts a Pages build (F98/F100 were caused by extra commits racing Pages builds). A table means SQL on production | **Neither.** The job reads the Page's recent posts and looks for this week's marker. No commit, no table |
| "Email an alert on failure" | The pipeline's convention is "a red run is GitHub's email to Rick" (both workflow headers) | Reuse it. No new mail path (F152 deliverability, F148 caps are not touched) |
| "Test in a test Page or private group" | Meta removed Groups API publishing (Graph API v19, removed 2024-04-22, per Meta developer threads and vendor notices) | **Test Page only.** Re-confirm against the current changelog in R1 |

### 1.2 Phase 5.1 and the newsletter cron

- **5.1 is done.** The app moved to Cloudflare Pages in July. The newsletter page did **not** move: it
  is served by GitHub Pages from `weekly-pull-feed` at
  `https://mrcyberrick.github.io/weekly-pull-feed/newsletter.html` (feed: `.../rss.xml`), and root paths
  are kept forever for the founding tenant (`weekly-newsletter-architecture.md` § 2, § 7).
- **The cron:** `weekly-pull-feed/.github/workflows/send-newsletter.yml`, `0 21 * * 2` (Tue 21:00 UTC),
  `concurrency: newsletter`, jobs `build` (tests, build, one commit, Pages check, thumbnails served) then
  `send` (stamp check, Brevo, verified). Starts run 2 to 3.3 hours late (measured +3h08m, +3h20m).
  Dispatch inputs default to the safest mode. Repo variables `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
  `BREVO_LIST_ID`; secrets `BREVO_API_KEY`, `SENDER_EMAIL`.
- **The Monday preflight** (`preflight-week.yml`, Mon 13:00 UTC, `contents: read`, no Brevo reference,
  its own concurrency group) is the pattern this job copies: read-only by construction, reuses the
  builder's week rule by `require`, logic injectable for tests.
- **A trap for this work:** the build job runs `node --test test/*.test.mjs` before every newsletter. A
  Facebook test file placed in `test/` would gate the newsletter on Facebook code. Put it in
  `test/facebook/` (not matched by that glob).

### 1.3 Findings in § 13 that touch scheduled jobs, secrets or alerts

| ID | Relevance |
|---|---|
| **F135** (open, S5 gate Tue 2026-10-20) | This job depends on the newsletter build. **Do not ship this before F135 closes**, and do not push to `weekly-pull-feed` on a Tuesday evening (W1.2 lesson: a push mid-build can fail its ref update) |
| **F96 / F106** | "Green must mean delivered": a send step must read back the result, not trust acceptance. Applied here: read the post back by id |
| **F98 / F100** | Extra commits racing Pages builds. Applied here: this job never commits |
| **F172** (open) | Free promo rows can appear on the page and inflate the count in the post |
| **F131** | Only Rick can load shipment rows; no import, no page, no post. The job must fail loud, not post last week |
| F148, F152, F99 | Email caps and deliverability; untouched because no email is sent |
| F72 / D3 | The newsletter direction (`weekly-newsletter-architecture.md` § 4) says the public page and feed are the **free** tier; a Facebook post fits that, and its config should later live in W2's `tenants.json` |

---

## 2. The open decisions

| Decision | Answer |
|---|---|
| Where the page is hosted | **Answered by the repo:** the existing GitHub Pages page. 5.1 is done and is about the app, not this page. Moving it is W2-W5 territory, not this job |
| Public or gated | **Answered:** public. It already is, and D3 (2026-10-14) made the public weekly page the free-tier product. A gated link from Facebook would hit a sign-in wall |
| URL shape | ~~**Answered:** link the existing root `.../newsletter.html`.~~ **Superseded 2026-10-14 by § 3b: link `https://rjbookstop.com/news/`.** (Old text: W2 adds `/t/<slug>/newsletter.html` and keeps the root as a permanent founding alias, so this link never breaks. Put the URL in a repo variable so W2 can switch it with no code change.) |

---

## 3. Questions only Rick can answer

| # | Question | What I found / recommend |
|---|---|---|
| Q1 | RSS URL | `https://mrcyberrick.github.io/weekly-pull-feed/rss.xml`, public. No answer needed |
| Q2 | Items per week, edits after publishing | Measured: 119 titles this week; earlier publishes 19 to 72. The whole feed is rebuilt each Tuesday; a re-dispatch with `week=` can republish a past week (deliberate). **Not an issue under week-based dedupe** |
| Q3 | Meta developer app? Are you an admin of the Ray & Judy's Page? | **Answered 2026-10-14: Rick is the Page admin.** The Meta developer app is created in R1 (no app yet assumed) |
| Q4 | Test Page? | A private group **cannot** be used (Groups API removed). Create a throwaway Page you admin, with no followers. Whether a brand-new or unpublished Page accepts API posts is checked in R1 |
| Q5 | Post when the feed updates, or a fixed day? | **DECIDED 2026-10-14 (Rick): Wednesday morning, cron 12:00 UTC** (8 AM ET in EDT, 7 AM in EST, plus GitHub's 2-3 h delay = mid-morning on new comic day). The newsletter already covers Tuesday evening. Your call |
| Q6 | Photo post, link post, or both? | **DECIDED: a photo post** (the composed top-picks image, § 3a; the link in the text). Meta ignores a custom image on link posts from the API unless the Page "owns" the linked domain (Graph API v2.9/v2.11 changelog), and `newsletter.html` has **no Open Graph tags**, so a link post would show a generic or scraped preview and a custom image cannot work. Trade-off: a link inside photo text is clickable but less prominent than a link card. Confirm in R1 |
| Q7 | Prices and descriptions on the page? | **Recommend no for v1.** It means widening the anon RPC (SQL on staging then production), a page redesign and 119 descriptions on one page. File separately if wanted |
| Q8 | Post wording | Draft in § 4.4. Approve or edit |
| Q9 | Banner images | ~~3 to 5 images, at least 1200 px wide, JPG or PNG under 4 MB. They go in a public repo~~ **Superseded by § 3a: no stock banners** |

### 3a. Decided 2026-10-14 (Rick, after the mockup)

Mockup: https://claude.ai/artifact/CLTK52kNhiMJZWiWe3tSTb (private; real covers from the Oct 12-18 week,
hand-picked as examples, not the real top three).

- **Q6 decided: a photo post with ONE composed image** (mockup layout B), not three separate photos
  (layout A: the feed crops two of three covers to squares).
- **Size: 1080x1350, 4:5 portrait.** Rick found the first draft (1200x630) "on the small side"; 4:5 is
  the tallest shape the feed shows uncropped, so it fills most of a phone screen.
- **The image shows this week's top 3 covers, ranked by copies the shop RECEIVED**
  (`weekly_shipment.quantity`, summed per title for the week). Not customer reservations.
- **The image says "In the spotlight", never "most ordered" or "top picks"** (Rick, 2026-10-14: "Spot Light" or similar), so the post does not suggest how the three were chosen. *(This read "Top picks" until the same day.)*
- **Rules that follow (my design, for review in the runbook):** one cover per series (this week had
  several AMAZING SPIDER-MAN #1001 covers that could take all three slots), preferring the standard
  cover; skip rows with no cover; fewer than three usable covers shows what there is (one or two);
  ties broken by title so the result is stable (F162). The three are then shown in title order (§ 3b).
- **Image source: the distributor's full-size cover, never the newsletter's thumbnail.** Measured
  2026-10-14: the newsletter's hosted thumbnails are about 198x300 (too soft); full-size PRH covers are
  1400x2123; this week's Lunar full-size cover (TRANSFORMERS #37) was only 450x692. In a 1080-wide
  image each cover is about 300 px wide, so even Lunar's small files are sharp enough.

### 3b. Landing page and the ranking risk (decided 2026-10-14)

**The post links to `https://rjbookstop.com/news/`, not the GitHub Pages newsletter.** Rick's
suggestion; measured the same day, and it is the better landing:

| | `rjbookstop.com/news/` | `.../weekly-pull-feed/newsletter.html` |
|---|---|---|
| Domain the customer sees | The shop's own | `mrcyberrick.github.io` |
| Content | The same feed: its script reads `mrcyberrick.us/weekly-pull-feed/rss.xml` | The feed's own page |
| Fresh on Wednesday morning? | **Yes:** 2026-10-14 the page's proxy (`rss-feed.rjbookstop.com`) served `lastBuildDate` Wed 14 Oct 00:08 GMT, 119 items, cached 5 minutes | Yes |
| Sign-up | **Has an email subscribe form** and a link to `rjbookstop.pulllist.app` (the funnel goal, D3) | Links to PULLLIST only |
| Query string (`?ref=facebook&w=...`) | Harmless (HTTP 200, checked) | Harmless |

**What it adds as a dependency, stated plainly:** the list is drawn in the visitor's browser by the
site's own script, through a Cloudflare Worker at `rss-feed.rjbookstop.com`, falling back to two outside
services (`allorigins`, `rss2json`). The site lives in Rick's local `rjbookstop` folder, outside both
repos' plans. If the Worker and both fallbacks fail, the page shows no titles. So the job's freshness
check (§ 4.2 step 3) reads the feed **through the Worker**, exactly as the page does, and fails red if
it is unreachable or stale. A Facebook visitor whose browser blocks the fallback services still depends
on the Worker; that is the site's existing behaviour, not something this job changes.

**The ranking risk, noted at Rick's request.** The spotlight wording keeps the **post** from
suggesting how the covers were chosen. It does **not** hide the ranking itself:
- The new database lookup (§ 4.6) is public by design (anon key, called from a public repo). Anyone who
  finds it can ask, for any week, which titles this shop received the most copies of, in order. It
  returns no counts or prices, but relative volume is new information that is not public today.
- Over many weeks the spotlight covers themselves form a visible pattern of what the shop stocks
  heavily. That is ordinary retail signalling, much like a shop window.
- **DECIDED 2026-10-14 (Rick: "close the gap and go with b&c"): mitigations (b) + (c).** *(This line
  listed (a) accept, (b) recent weeks only, (c) unordered, with (b) + (c) recommended, until Rick chose.)*
  - **(b) Recent weeks only.** The lookup answers only for the week containing today (UTC) and the
    week before; any other week raises an error naming the allowed range. History cannot be pulled.
  - **(c) No order.** It returns the three spotlight covers **sorted by title**, never by quantity, with
    no rank column. Sorting by title (not a random shuffle) keeps the result stable from run to run
    (F162) while saying nothing about volume. The image lays the covers out in that order.
  - **(c) needed one more change, found while recording it:** the draft took a `p_limit` argument, and a
    call with `p_limit = 1` (or 1 then 2) would reveal the #1 title anyway. **The count is now fixed at
    3, with no limit parameter.**
- **What remains exposed, accepted:** for the current or previous week, anyone can learn which three
  titles were spotlighted, which is exactly what the public post shows anyway. Nothing else.

---

## 4. Proposed design

### 4.1 Files (all in `weekly-pull-feed`)

| File | New/edit | Purpose |
|---|---|---|
| `scripts/post-facebook.js` | new | The job. Pure functions plus an injectable `run()`, like `preflight-week.js` |
| `test/facebook/post-facebook.test.mjs` | new | Unit tests; outside `test/*.test.mjs` so it never gates the newsletter |
| `.github/workflows/post-facebook.yml` | new | Schedule + dispatch |
| `scripts/facebook-image.html` | new | The 4:5 image as an HTML template (the mockup's layout B), filled per week and screenshotted |
| `fonts/` (Anton, Archivo `.woff2`) | new | Open Font License faces, kept in the repo so the screenshot never depends on a font download |

And in **this** repo: `docs/sql/<date>-fb-top-picks-rpc.sql` (the new lookup, § 4.6).

Nothing in `send-newsletter.yml`, `preflight-week.yml`, the builder or the send script changes.

**How the image is made, and why this way:** `weekly-pull-feed` has **no npm dependencies** today
(thumbnails come from the outside resizer `wsrv.nl`). Rather than add the first one (`sharp`, which also
draws text badly without system fonts), the job fills an HTML template and has the **Google Chrome
already installed on GitHub's Ubuntu runners** take a 1080x1350 screenshot in headless mode. Zero new
dependencies, and the result looks exactly like the template, fonts included. **R0 confirms Chrome is
present on `ubuntu-latest` and that headless `--screenshot` works**; if not, fall back to `sharp`
pinned with a lockfile, installed in the Facebook job only.

### 4.2 What one run does

1. **Week:** builder's `todayUTC` + `resolveTargetWeek` + `weekRange` (a `--week=` override for tests).
2. **Data:** preflight's `fetchRawWeek` (same anon RPC, same production guard). Zero rows: fail red
   ("the shipment import has not run"). On-sale date: builder's `dominantOnSaleDate`.
3. **Landing page shows this week:** fetch the feed **through the site's Worker**
   (`FEED_CHECK_URL`, `https://rss-feed.rjbookstop.com/rss.xml`, what `rjbookstop.com/news/` itself
   renders) and read `<lastBuildDate>`. It must fall inside `start..end`. If not, or the Worker is
   unreachable: fail red ("the news page does not show this week yet"). This stops a post that links to
   last week's list. *(This step read the `newsletter.html` stamp until the landing changed, § 3b.)*
4. **Count:** the number of `<item>` in that same feed (what the reader will see), cross-checked
   against the row count; a mismatch is a warning, not a failure.
5. **Already posted?** `GET /{page-id}/posts?fields=id,message&since=<start>`. If any message carries
   this week's marker (the link's `w=<start>` query value), exit 0 "already posted", no post. This is
   the dedupe and the idempotency check; reruns are safe.
6. **Image:** call the new lookup (§ 4.6) for the top 3; download each full-size cover into the
   runner's temp folder (a failed download drops that cover, it does not fail the run unless none
   remain); fill `facebook-image.html` (date, item count, covers, short titles, shop name and town);
   headless Chrome screenshots it to `fb-<week>.jpg`, 1080x1350. The image is **attached to the run as
   an artifact** so every week's picture can be reviewed, and nothing is committed.
7. **Post** (unless dry run): `POST /{page-id}/photos` as a multipart upload (`source=<the file>`,
   `caption=<message>`), so the image needs no public hosting. **Read back**
   `GET /{post-id}?fields=id,permalink_url,created_time`; only that makes the run green (F96).
8. **Log:** run log plus `$GITHUB_STEP_SUMMARY`: week, on-sale date, items, image, post id, permalink
   or "dry run" / "already posted". No file written to the repo.

### 4.3 Workflow shape

```yaml
name: Post to Facebook
on:
  schedule:
    - cron: "0 12 * * 3"   # Wed 12:00 UTC (Q5)
  workflow_dispatch:
    inputs:
      dry_run: { type: boolean, default: true }
      week:    { type: string, default: "" }
permissions:
  contents: read
concurrency:
  group: facebook
  cancel-in-progress: false
jobs:
  post:
    if: ${{ github.event_name == 'workflow_dispatch' || vars.FACEBOOK_ENABLED == 'true' }}
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps: checkout -> setup-node 22 -> node --test test/facebook/ -> node scripts/post-facebook.js
```

The schedule does nothing until the repo variable `FACEBOOK_ENABLED` is `true`, so merging is safe.

### 4.4 Post text (draft for Q8)

```
New comics this Wednesday, Oct 14! 119 new arrivals at Ray & Judy's Book Stop.

See every new title: https://rjbookstop.com/news/?ref=facebook&w=2026-10-12

Reserve yours online: https://rjbookstop.pulllist.app/?ref=facebook
```

(`w=` is the dedupe marker and harmless to GitHub Pages. The page's own cover links still say
`ref=newsletter`, so Facebook traffic past the page is not distinguishable; not fixed here.)

### 4.5 Configuration and secrets

| Name | Kind | Value |
|---|---|---|
| `FACEBOOK_PAGE_TOKEN` | **secret** | Page access token (non-expiring, derived from a long-lived user token) |
| `FACEBOOK_PAGE_ID` | variable | Test Page id first, the real Page id at go-live |
| `FACEBOOK_ENABLED` | variable | `false` until go-live |
| `FACEBOOK_GRAPH_VERSION` | variable | Pinned, e.g. `v25.0` (current per Meta's reference; confirm in R1) |
| `LANDING_URL` | variable | `https://rjbookstop.com/news/` (§ 3b) |
| `FEED_CHECK_URL` | variable | `https://rss-feed.rjbookstop.com/rss.xml` (the feed as the landing page reads it) |
| `STORE_NAME`, `STORE_APP_URL` | variable | `Ray & Judy's Book Stop`, `https://rjbookstop.pulllist.app/` |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | variable | Already exist |

The token never enters a chat, a file or a commit; Rick pastes it into GitHub's secret form himself.
Permissions needed on the token: `pages_manage_posts`, `pages_read_engagement`, `pages_show_list`.

### 4.6 The top-picks lookup (SQL, this repo, staging then production)

`get_pull_feed_week` deliberately returns no quantities, and that stays true. A **new** anon-callable
function returns the ranking without the numbers:

```
get_pull_feed_spotlight(p_slug text, p_week_start date)
  RETURNS TABLE (title text, cover_url text, series_name text)   -- at most 3 rows, sorted by title
```

Same shape as `get_pull_feed_week` (`docs/sql/2026-10-01-f135-pull-feed-week-rpc.sql`): `SECURITY
DEFINER`, `search_path` pinned, takes the slug, fixed 7-day window, catalog left-joined on the same
tenant (F164), `REVOKE ... FROM PUBLIC`, `GRANT EXECUTE TO anon, authenticated`, one-row verdict
query. Logic: sum `quantity` per (title, cover_url) for the week; drop rows with no `cover_url`; keep
one per series (`coalesce(series_name, title)`), preferring a standard cover (`catalog.variant_type`
null, `Standard` or `Primary Title`), then the highest quantity, then title; take the top **3**
(fixed; no limit argument, § 3b); **return them ORDER BY title** (§ 3b (c)). Refuse (raise) unless
`p_week_start` falls in the week containing `CURRENT_DATE` or the week before (§ 3b (b)), using the
same Monday-to-Sunday rule as `get_pull_feed_week`. **Returns NEVER: `quantity`, `price_usd`, a
rank, codes, ids.** *(Renamed from `get_pull_feed_top_picks`, which had a rank column and `p_limit`,
before anything was written.)*

**Exposure, stated plainly:** the order itself tells anyone with the public anon key which titles a
shop received the most of in a given week. No counts, but relative volume. Low sensitivity (the same
covers are on the public newsletter), but it is new information, so it is Rick's call at sign-off. **See § 3b for the
full risk note and two cheap mitigations (recent weeks only; unordered results).**

Written with `/sql-check` during execution, run by Rick in the SQL Editor (staging first, then
production; production is the one the job reads), `STATUS` line kept current so `/promote-prod` step 0
sees it. **F172:** a free promo row could in principle rank; it is filtered only if F172 decides so.

### 4.7 Alerts

A failed run (no rows, stale page, expired or revoked token, Graph error, read-back failure) exits 1,
and GitHub emails Rick, as with the newsletter. **One thing to verify (T3):** that GitHub's Actions
failure email actually reaches Rick for scheduled runs in this repo (it notifies the person who last
edited the cron line).

---

## 5. Runbook (for the execution session, after sign-off)

**Rules:** work on `weekly-pull-feed` `main` only. Never push between Tue 20:00 UTC and the end of the
Tuesday newsletter run. Never post to the real Page before R5. Every Meta step is Rick's; the agent
never handles the token.

### R0 — Pre-flight (agent)

1. `git -C weekly-pull-feed fetch origin && git status -sb`: the local clone was 16 commits behind on
   2026-10-14. `git pull --ff-only` and confirm tip is `c0a423c5` or later.
2. Confirm F135 is CLOSED (CLAUDE.md row + `weekly-newsletter-architecture.md` § 9 records the Tue
   2026-10-20 run read). **If not, stop.**
3. `node --test test/*.test.mjs` green (baseline: 49 tests on 2026-10-13).
4. A throwaway dispatch-only workflow on a branch (or the first R3 run in dry-run mode) confirms
   `google-chrome --version` exists on `ubuntu-latest` and that
   `google-chrome --headless --screenshot=x.jpg --window-size=1080,1350 file://...` writes a 1080x1350
   image. **If not, switch the image step to `sharp` (§ 4.1) before writing R2.**
5. Read `scripts/build-pull-feed.js` exports line (`module.exports`, ~737) and confirm
   `weekRange, todayUTC, resolveTargetWeek, dominantOnSaleDate` are exported; `preflight-week.js`
   exports `fetchRawWeek, readConfig`; `check-stamp.js` exports `readStamp`. **Halt on any mismatch.**

### R1 — Meta setup and discovery (Rick, no code; ~30-45 min)

1. Create the test Page (Q4). Note its id.
2. developers.facebook.com: create an app (type "Business" or the current equivalent). Add the Pages
   use case. Rick stays the app admin; leave the app in **Development** mode.
3. Graph API Explorer: user token with the three permissions (§ 4.5) → exchange for a long-lived user
   token → `GET /me/accounts` → copy the test Page's `access_token`. Debug it in the Access Token
   Debugger: `Expires: Never` expected.
4. **Discovery checks, each answered from what Meta returns, not docs:**
   - D1: `POST /{test-page}/photos` with an image URL and a caption containing a link succeeds in
     Development mode (no App Review). Expected: an `id` and `post_id`.
   - D2: the link in the caption is clickable on the post (open it in the Facebook app and on desktop).
   - D3: `GET /{test-page}/posts?fields=id,message` returns the caption text (dedupe depends on it).
   - D4: the current Graph API version string (pin it).
   - D5: Groups API is still unavailable (changelog), so the test-group option stays closed.
   **Any "no" here stops the session and returns to planning.** Delete the test posts afterwards.
5. Add `FACEBOOK_PAGE_TOKEN` (secret) and the variables in § 4.5 to `weekly-pull-feed`, with
   `FACEBOOK_PAGE_ID` = the **test** Page and `FACEBOOK_ENABLED` = `false`.
6. D1 is run with a **multipart upload** (`source=` a local JPEG), the way the job will post, not
   with an image URL.

### R1b — The top-picks lookup (agent writes, Rick runs)

1. Write `docs/sql/<date>-fb-top-picks-rpc.sql` in this repo per § 4.6, using `/sql-check` and the F135
   RPC file as the template (pre-flight `name_taken = 0`, one transaction, one-row verdict that FAILs if
   the projection is not exactly `title, cover_url, series_name`, if the function has more than two
   arguments, if anon cannot execute, if a series repeats, if more than 3 rows return, or if the rows
   are not in title order). **Negative checks in the verdict too:** a call for a week three weeks back
   must raise, not return rows (b).
2. Doc-only commit to `staging` with `STATUS: ... staging=PENDING | prod=PENDING`.
3. Rick runs it on **staging**, pastes the verdict; then on **production**; the agent re-verifies
   production independently with an anon POST to the function (expect up to 3 rows, no quantity field).
   Update the `STATUS` line after each.

### R2 — Script and tests (agent)

Create `scripts/post-facebook.js`. Sketch (the executing session writes it in full against R0's
confirmed exports, in the style of `preflight-week.js`):

```js
'use strict';
const { weekRange, todayUTC, resolveTargetWeek, dominantOnSaleDate } = require('./build-pull-feed.js');
const { fetchRawWeek, readConfig } = require('./preflight-week.js');
const { readStamp } = require('./check-stamp.js');

// Pure ---------------------------------------------------------------
function weekMarker(start) { return `w=${start}`; }
function usablePicks(picks) { return picks.filter(p => p && p.cover_url).slice(0, 3); }  // § 3a rules live in the SQL; this only guards
function stampProblem(stamp, start, end) {
  if (!stamp) return 'newsletter.html has no pull-feed-generated stamp';
  if (stamp < start || stamp > end) return `newsletter.html is stamped ${stamp}, outside ${start}..${end}: Tuesday's build did not publish this week`;
  return null;
}
function countItems(rssXml) { return (rssXml.match(/<item>/g) || []).length; }
function alreadyPosted(posts, start) { return posts.some(p => (p.message || '').includes(weekMarker(start))); }
function buildMessage({ onSale, count, store, pageUrl, appUrl, start }) { /* § 4.4 text; date as "Wednesday, Oct 14" */ }

// I/O, all injected ------------------------------------------------------
async function run({ argv, env, fetchImpl, now, listBanners, log, error, summary }) {
  // 1 week  2 rows (0 -> exit 1)  3 stamp (problem -> exit 1)  4 count
  // 5 GET posts since start (alreadyPosted -> log, exit 0)
  // 6 picks -> download covers -> renderImage()  7 dry run -> print message+image, exit 0; else POST /photos, then GET /{post_id}
  //   (no permalink_url -> exit 1)  8 summary
}
module.exports = { weekMarker, usablePicks, stampProblem, countItems, alreadyPosted, buildMessage, run };
if (require.main === module) run({ /* real deps */ }).then(c => process.exit(c));
```

Rules for the script: the token is read only from `FACEBOOK_PAGE_TOKEN` and sent only in the request
body or `Authorization` header, **never logged** (redact it from any error text); every Graph error
prints Meta's `error.message` and `error.code`; no retries on POST (a retry risks a double post; the
dedupe check covers reruns).

Create `test/facebook/post-facebook.test.mjs` covering at least: stamp in week / before / after /
missing; zero rows → exit 1; already posted → exit 0 with **no POST call**; dry run → no POST call;
zero usable picks -> exit 1; POST ok but read-back fails → exit 1; token absent from all
logged output (inject a token string and assert it never appears). **Negative controls:** break
`stampProblem`, `alreadyPosted` and the read-back check one at a time and see the intended tests go red,
then revert.

Also in R2: `scripts/facebook-image.html` (the mockup's layout B at 1080x1350, fonts from `fonts/`,
placeholders for date, count, three covers, titles, shop) and a `renderImage()` step in the script
(fill template, call headless Chrome, check the output is 1080x1350 and not blank). Tests add: one, two
and three covers render; a cover that fails to download is dropped; zero covers fails the run; the
caption never contains a quantity.

**Verify:** `node --test test/facebook/` green; `node --test test/*.test.mjs` still 49 and unchanged
(proves the newsletter's gate is not affected); `node --check scripts/post-facebook.js`.

### R3 — Workflow (agent)

Create `.github/workflows/post-facebook.yml` per § 4.3, steps passing `SUPABASE_URL`,
`SUPABASE_ANON_KEY`, `TENANT_SLUG: rjbookstop`, the § 4.5 variables, the token secret, `WEEK`, and
`DRY_RUN: ${{ github.event_name == 'workflow_dispatch' && inputs.dry_run && 'true' || 'false' }}`.
Header comment states: read-only on the repo, no Brevo reference, own concurrency group, schedule inert
until `FACEBOOK_ENABLED=true`.

**Commit** (one commit, pushed on a non-Tuesday):
`feat(facebook): weekly Facebook Page post linking to the published newsletter page`
**Verify:** the push starts one Pages build only (no workflow commits); the newsletter workflow file is
byte-unchanged (`git diff HEAD~1 -- .github/workflows/send-newsletter.yml` empty).

### R4 — Test sequence (Rick + agent, test Page only)

| Step | Action | Expected |
|---|---|---|
| T1 | Dispatch, `dry_run=true` | Green; log shows week, on-sale date, count, the three picks, full message; the run's attached `fb-<week>.jpg` is 1080x1350 and Rick approves how it looks; **no post on the test Page** |
| T2 | Dispatch, `dry_run=false` | Green; one photo post on the test Page; permalink in the summary; Rick checks image, text, link opens the right week |
| T3 | Dispatch `dry_run=false` again, same week | Green, "already posted", **no second post** |
| T4 | Dispatch `week=2030-01-09` | Red: no rows. Rick confirms the failure email arrived |
| T5 | Dispatch with `week=` set to NEXT week (whose feed is not built yet) | Red: the news page does not show that week; nothing posted |
| T6 | Set `FACEBOOK_ENABLED=true` with the **test** Page id | Two or three real Wednesday runs post to the test Page; Rick reviews each |

### R5 — Go-live (Rick, after T6 is reviewed)

1. Generate a Page token for the **real** Page (R1 step 3); replace the secret; set `FACEBOOK_PAGE_ID`.
2. One dispatch with `dry_run=true` against the real Page id: green, shows the week, posts nothing.
3. Leave `FACEBOOK_ENABLED=true`. Read the first scheduled run's log and the post.
4. Delete the test Page (or leave it; it costs nothing).

### Rollback

Set `FACEBOOK_ENABLED=false` (stops the schedule instantly), delete a bad post by hand on Facebook.
Revoke the token by removing the app from the Page's business integrations. Nothing else depends on
this job.

---

## 6. Out of scope

Prices and descriptions on the page (Q7); Open Graph tags on `newsletter.html` (only needed for a link
card); multi-tenant config (`tenants.json`, W2) beyond keeping values in variables; Instagram;
per-title posts; distinguishing Facebook traffic past the page; F172's promo rows; any change to the
newsletter build, send or preflight; any app, SQL or Supabase change; App Review / going public with
the Meta app (not needed to post to a Page you admin, if D1 holds).

## 7. Risks

| Risk | Mitigation |
|---|---|
| Posts while the news page shows last week | `lastBuildDate`-in-week check through the Worker (step 3) fails red |
| The news page's Worker breaks (outside these repos) | Step 3 fails red, so no post points at an empty page; fixing the site is separate work |
| The spotlight lookup reveals what the shop stocks most | No counts, no rank, fixed 3, title order, current and previous week only (§ 3b, decided) |
| Double post | Week marker read from the Page before posting; no POST retries |
| Token leak in a public repo's logs | Secret masking plus explicit redaction plus a unit test asserting the token never appears |
| Token silently invalidated (password change, admin removed) | Run goes red and emails Rick |
| Meta API changes (version sunset) | Pinned version variable; a red run on sunset |
| Facebook code blocks the newsletter | Separate workflow, separate test folder; newsletter files byte-unchanged (R3 verify) |
| F135 not yet closed | R0 step 2 halts |

## 8. Execution log

**2026-10-14, first session (Rick: "go"; test Page given; wording approved).**

- **Inputs from Rick:** test Page `https://www.facebook.com/profile.php?id=61595560673871` (its Graph
  Page id is read from `/me/accounts` in R1, expected to be `61595560673871`); post wording § 4.4
  approved; § 3b exposure decided (b) + (c).
- **R0:** `weekly-pull-feed` pulled to `c0a423c5`; newsletter suite 49/49; builder, preflight and
  stamp exports as expected. **F135 is NOT closed yet**, so nothing is pushed to `weekly-pull-feed`
  until the Tue 2026-10-20 run is read (a non-bot commit there would muddy that gate's check).
- **R1b (SQL), written, NOT run:** `docs/sql/2026-10-14-fb-spotlight-rpc.sql` (`staging` `00acb3d`).
  `get_pull_feed_spotlight(p_slug, p_week_start)`: top 3 series by copies received, standard cover
  preferred, returned in title order, this week or last only, no limit argument. **Dry-run on PGlite**
  (Postgres in WASM, scratch only) against a 12-row fixture: verdict `OK`; spotlight exactly as
  predicted (Spider-Man shown by its regular cover though variants had more copies; Transformers CVR A
  over CVR B; Batman 4th and excluded; the coverless, last-week and other-shop rows never appear);
  as `anon` the function works and the table read is refused. **Six negative controls**, each red
  with its own message: no week limit, rank order, no series dedupe, a limit argument, variant
  preferred over standard (this one first passed the verdict; a check was added). Not exercised:
  Supabase itself (PGlite is Postgres 17 without Supabase's roles and default grants).
- **R2/R3 (`weekly-pull-feed`, local branch `facebook-weekly-post`, `2e1a1d1b`, not pushed):**
  `scripts/post-facebook.js`, `scripts/facebook-image.html`, `fonts/` (Anton, Archivo, OFL licenses),
  `test/facebook/post-facebook.test.mjs` (22 tests), `.github/workflows/post-facebook.yml`. **22/22
  green; five negative controls** (no token redaction, no freshness check, no dedupe, no read-back,
  dry run not the default) each turned their intended test red, script restored byte-identical.
  Newsletter suite still 49/49 and its five files byte-unchanged. Workflow YAML parsed.
- **Local end-to-end dry run against LIVE production data:** real `get_pull_feed_week` (119 rows), the
  real news-page feed through `rss-feed.rjbookstop.com` (this week, 119 items), real full-size covers;
  only the not-yet-applied spotlight lookup was stood in by three hand-picked covers. Exit 0, no Graph
  call made, a 1080x1350 PNG (~950 KB) produced and inspected. One layout fix from the inspection
  (covers top-aligned so a two-line caption does not lift one cover; covers enlarged to 312x468).
- **Found and fixed during the build:** the template's own comment spelled a placeholder, which the
  leftover-placeholder guard correctly refused; a hand-built `file://` URL replaced with
  `pathToFileURL`; `node --test` needs a file glob, not a folder (the workflow uses the glob).

**Owed, in order:**
1. **Rick: run the SQL** on staging, then production (§ 5 R1b). Paste each verdict back.
2. **Rick: Meta setup (R1)** for the TEST Page, then add the secret and variables to
   `weekly-pull-feed` (`FACEBOOK_PAGE_TOKEN` secret; `FACEBOOK_PAGE_ID`, `FACEBOOK_ENABLED=false`).
   The other variables are optional; the script's defaults are the § 4.5 values.
3. **After the F135 gate is read (Wed 10-21):** rebase `facebook-weekly-post` onto `origin/main`,
   fast-forward and push (not on a Tuesday evening), then T1-T6 (§ 5 R4) on the test Page.
4. R5 go-live after T6 is reviewed.

## References

`docs/weekly-newsletter-architecture.md` · `docs/f135-decouple-feed-publish.md` ·
`docs/technical-reference.md` § 13 F96, F98, F100, F106, F131, F135, F172 · Meta: Graph API v2.11
changelog (link-post customisation), Groups API removal (v19, 2024-04-22).
