# Weekly newsletter — acquisition funnel repair

**STATUS:** IN PROGRESS — S2+S3 DONE (`6a8d4ec`); **S6a DONE (`f0189a8`)**, superseding S1's destination;
**S6b DONE ON STAGING (`68e3144`)**; S6c not started; S1x open |
staging=2026-09-08 (S6b) | prod=NOT PROMOTED — S6a publishes at the Fri 2026-09-11 import; S6b needs an
explicit promotion request | findings=none (feature build)

**Owner:** Rick. **Execution:** one dedicated session. **Repo: the private scripts repo only**
(`build-pull-feed.js`). **No PULLLIST deploy, no schema change, no Edge Function, no DNS.**

---

## 1. Why this exists

Rick's stated goal, 2026-09-08: *"The signup page is specifically to encourage people (many who are
comic customers) to use the app. The funnel's goal to increase visibility to the weekly shipments
through email and get new users to signup."*

The newsletter is therefore an **acquisition channel for PULLLIST**, not a retention channel for
existing app users. Measured against that goal, its structure works against it.

### 1.1 The measured campaign (Brevo, list "#7 rjbookstop - Weekly Pull List", 2026-09-08 export)

| Delivered | Opens | Clicks | Soft / hard bounce | Unsub | Complaints |
|---|---|---|---|---|---|
| **10** | 1 (10%) | 1 (10%) | 0 / 0 | 0 | 0 |

**At N=10 the open rate has a resolution of 10 percentage points.** No subject line, send time or
template change is measurable at this size. Delivery is clean — but note that "delivered" means the
receiving server *accepted* the message; spam-folder placement counts as delivered, so inbox
placement is neither confirmed nor refuted by this row.

The one recipient who opened also clicked. That is a single data point and proves nothing on its
own, but there is no evidence here that the content fails the people who see it.

### 1.2 The structural problem

Measured against the live published email (`newsletter-email.html`, generated 2026-09-04):
89,059 bytes, 72 links.

| Portion | Content | Where its links go |
|---|---|---|
| top 12% | title bar, hero, one CTA | **3 links → `rjbookstop.pulllist.app`** |
| bottom 88% | the 65-cover grid — the actual draw | **65 links → `media.lunardistribution.com`, `images.penguinrandomhouse.com`** |

**The most compelling element in the email — a comic the reader actually wants — routes the click to
a raw JPEG on a distributor's CDN.** No store, no app, no signup, no way back. For a retention
bulletin that is merely sloppy; for an acquisition funnel it is the central leak, repeated 65 times
per issue.

The single CTA reads **"Reserve Your Comics"**, over three feature lines (*"Browse the monthly
catalog / Auto-reserve your series / Know what arrives Wednesday"*). All four presume an account
already exists. Nothing addresses a newcomer, and nothing says the app is free.

**The destination itself is fine** — verified 2026-09-08 against the served bytes:
`rjbookstop.pulllist.app` offers a **Create Account** path alongside sign-in. The door is not
locked; the email simply rarely points at it.

---

## 2. In scope — S1, S2, S3

All three are edits to `build-pull-feed.js` in the scripts repo. Nothing here touches the PULLLIST
web app, its schema, its Edge Functions, or either Supabase project's data.

### S1 — cover links point at the app, not the distributor CDN — ✅ DONE 2026-09-08, ⚠️ DESTINATION SUPERSEDED BY S6

> **Read § 2a S6 before acting on this section.** S1's *mechanism* stands — the tuple append,
> the helper, the two changed builders. Its *destination* is wrong, and was measured wrong the
> next hour: `catalog.html` is month-scoped and **cannot contain a single title in the
> newsletter** (0 of 68). S6 replaces the destination; nothing here needs reverting first.

**Shipped:** scripts repo `main` `8836380`, pushed and verified on `origin/main`. Six functional
lines plus comment; `build-pull-feed.js` only.

**Two things were measured during execution that this plan had assumed wrongly, and both changed
the implementation:**

1. **The key is `item_code || upc`, not `item_code`.** Measured on the 2026-09-07 week: `item_code`
   covers only **40 of 68** rows — **PRH carries none at all** — so the plan's original `c=item_code`
   would have silently degraded 41% of covers to a bare catalog link. `item_code || upc` covers
   **68/68**, and is the project's own existing display chain rather than a new convention.
   `catalog_id` was the other candidate and was rejected: 64/68 coverage and 36 chars per link
   against a message already close to the clip line.
2. **The separator must be `&amp;`, not a bare `&`.** `MAPS_URL` (~line 1234) is the only other
   multi-param URL in these templates and already uses `&amp;` in production sends. Matching it.

**`buildRssXml` was left unchanged** — the § 2 table's open decision, resolved conservatively for
now. Nothing is lost by deciding it later; changing it is a one-line follow-up.

**Gates, run against a pre-change `--local` baseline (68 titles, production data, read-only):**

| Gate | Result |
|---|---|
| V1 | `node --check` clean, `--local` build completes |
| V2 | **0** CDN hrefs in both HTML surfaces — was **68 each** |
| V3 | 68/68 covers resolve to `rjbookstop.pulllist.app`, carry `ref=newsletter`, and every `c=` traces to a source row; 0 bare-`&` links |
| V5 | Date-normalised diff: **136 changed lines, all of them href lines**; `rss.xml` byte-identical |
| V6 | `npm test` **295/295** |
| **V4** | **NOT met — see S1x below. Deliberately not guessed.** |
| **V7** | **Owed — Rick's step. Deferred by decision to after the Fri 2026-09-11 import** (§ 5a), when the new links are live and the page can be checked as published rather than as a local build. |

#### Superseded plan text, kept for the record

**⚠️ Read the DONE note above, not this.** What follows is the pre-execution plan; two of its
specifics were measured wrong and corrected during the work — the key is `item_code || upc` (not
`item_code`), and the separator is `&amp;` (not a bare `&`). The RSS row's "Rick's call" is now
**closed: leave as-is.**

**The data is already there.** `weekly_shipment` carries `item_code`, `upc` and `catalog_id` (read
live from production 2026-09-08). `fetchWeekRows()` simply does not select them:

```js
// build-pull-feed.js:208 — current
`?select=title,cover_url&tenant_id=eq.${TENANT_ID}` +
```

Each cover cell then links to the cover image:

```js
const originalUrl = row[0] || "";
<a href="${originalUrl}" …>          // ← the leak
```

**⚠️ That link exists in THREE builders, not one** — confirmed by grep, and easy to miss because
the email is the only one anybody looks at:

| Line | Builder | Artifact | Decision |
|---|---|---|---|
| **1226** | `buildEmailHtml()` | `newsletter-email.html` — the Brevo send | **Change.** This is the campaign. |
| **629** | `buildNewsletterHtml()` | `newsletter.html` — the browser version | **Change.** Same dead end, same goal; it is the page a "view online" click reaches. |
| **1648** | RSS builder | `rss.xml` — drives rjbookstop.com | **Rick's call.** An RSS `<link>` is the item's canonical page, so pointing it at the app is defensible but is a different contract than the two HTML surfaces. Decide explicitly rather than by omission. |

**Change:** select `item_code` and `catalog_id` as well, and point each cover at
`${PREORDER_URL}/catalog.html?ref=newsletter&c=<item_code>`.

**⚠️ The `rows` shape is the main implementation risk.** `rows` is an array of `[url, title]`
2-tuples consumed by **three** builders — `buildEmailHtml()`, `buildNewsletterHtml()` and the RSS
builder. Append rather than reorder (or move to objects and update all three deliberately); index 0
and 1 must keep meaning exactly what they mean today, or the browser page and the feed break
silently.

**A null `item_code` must degrade**, not emit a broken link — omit the `c=` param and use the plain
catalog URL.

#### S1's honest limit, and why it still ships on its own

**The gate is `initNav()` (`app.js:508-511`), not `Auth.requireAuth()`** — corrected 2026-09-08 by
reading the code: `catalog.html` never calls `requireAuth` at all, and `Auth.requireAuth()`
(`app.js:264`) has exactly one caller, `requireAdmin`. Every nav page is gated by `initNav()`'s own
`const user = await Auth.getUser(); if (!user) { window.location.href = 'index.html'; }` — a bare
redirect that **discards the requested URL**. Same effect, different function; S4 must patch the
right one. And no page in the app reads a
title parameter: `app.js:115` is the *only* `URLSearchParams` call in the entire client, and it
reads `?t=` alone.

So today, for a logged-out reader, `catalog.html?c=X` resolves to the front door; for a logged-in
one it resolves to the generic catalog. **The specific comic is lost either way.**

S1 is still worth shipping alone because it:

- stops routing 65 clicks per issue out of the ecosystem entirely,
- lands every one of them on a page carrying **Create Account**,
- and yields per-title click data in Brevo for free, since each cover becomes a distinct tracked URL.

Making the click land on *the comic itself* is **S4** (§ 3) — an app change, deliberately not
smuggled into a scripts-only session.

### S2 — rewrite the CTA for someone who has never used the app — ✅ DONE 2026-09-08 (`6a8d4ec`)

**Direction chosen by Rick: free + low commitment.** Email now reads *Free — takes about a minute /
We hold your books behind the counter / Know what arrives Wednesday*, button **START YOUR PULL LIST
— FREE**, subtext *New here? Set it up online, pick up in store.*

**⚠️ Found during the work, worse than the email and not in this plan: the BROWSER page's only call
to action was "Ask Us About Online Reservations / Speak with a staff member today" plus a phone
number — on a page whose entire job is app signup there was NO app link in the CTA block at all.**
It now leads with **Create your free account**; the phone stays as a fallback, and the dismiss/
re-open tab's matching old framing follows.

**Its 5-feature explainer panel is deliberately unchanged** — that is feature description with its
own paragraphs, not the acquisition ask, and a visitor reading the page is served by it. A first
assertion wrongly demanded that copy be absent from both surfaces; **the code was right and the test
was over-broad**, so the assertion was scoped rather than the code changed.

**A second defect the gates caught:** an explanatory HTML comment sat *inside* a template literal,
so it was being emitted into the published page — bytes shipped to every reader, on a message
already near the clip line. Removed; rationale lives in the commit and here instead.

#### Superseded plan text, kept for the record

Two builders carry the promo block and must stay consistent: `buildEmailHtml()` (~lines 1404-1476)
and `buildNewsletterHtml()` (~lines 984-1064).

Replace the account-presuming copy. The newcomer framing needs to carry: **it is free**, it takes
under a minute, and what it does for them (never miss an issue / we hold it behind the counter).
"Reserve Your Comics" may stay as secondary copy for existing users, but must not be the primary
button.

Exact wording is Rick's call — this plan deliberately does not pre-write his shop's voice.

### S3 — attribution — ✅ DONE 2026-09-08 (`6a8d4ec`)

All four non-cover app links carry `ref=newsletter` plus a **placement**: `header`, `hero`, `cta`
(email) and `web-cta` (browser page). Covers already carried `ref` from S1. **Zero untagged app
links remain on either surface** — so the click report can separate "clicked the big red button"
from "clicked the logo", which say very different things about the copy.

#### Superseded plan text, kept for the record

Append `?ref=newsletter` to all app links (the 3 existing plus the 65 from S1).

**Verified safe:** the client reads only `?t=` (`app.js:115`), so unknown query params are inert and
cannot disturb `TenantContext` resolution or any page's init.

This makes Brevo's click report per-title and per-placement. **It does not close the loop to
signups** — that needs app-side capture, which is **S5** (§ 3).

### S1x — the size guard — ⏸ OPEN, and deliberately not guessed

**Measured after S1:** the built email is **89,909 bytes (87.8 KB)** with 72 tracked links. S1 added
**+800 bytes** to a pre-existing 87 KB problem, so it made the situation 0.9% worse rather than
creating it.

Against the ~102 KB clip line, the outcome depends entirely on how long Brevo's rewritten URLs are —
which is estimated here, never measured:

| assumed rewritten link length | resulting size | verdict |
|---|---|---|
| 180 chars | 95.1 KB | OK |
| 220 chars | 97.9 KB | OK |
| 260 chars | 100.7 KB | **over the 80 KB target, close to the clip line** |

**This plan originally said to cap the cover count and ship that with S1. That was not done, on
purpose.** Picking a cap now means choosing how many comics Rick shows his customers on the strength
of a guess about a third party's URL format. **V7 answers it for real in one send** — the true
rewritten length, and whether Gmail actually shows "[Message clipped]". Size the cap from that
measurement.

The original reasoning, still valid:

This is not optional housekeeping; S1 makes it worse.

| | bytes |
|---|---|
| current raw `htmlContent` | 89,059 (87.0 KB) |
| + Brevo rewriting 72 links through `sendibt2.com` (est. 180–260 chars each) | 95.0 – 100.6 KB |
| + Brevo's own footer, unsubscribe block and open pixel | pushes past |
| **Gmail clip threshold** | **~102 KB** |

Measured positions in the current file: unsubscribe at **97.2%** through the message, store phone at
**98.8%**, permission line at **99.6%**. Brevo appends its tracking pixel after all of it — so **the
open pixel sits in the clip zone**, and a clipped pixel is an open that is never recorded.

S1 adds `?ref=&c=` params to every cover link, costing roughly **+1.5–2 KB**.

**So S1 must land together with a size reduction.** Recommended: cap the grid at a curated subset
per issue — the count is Rick's call, and fewer, larger covers also tightens the pitch. A hard
assertion on the built file's size is gate V4 below.

---

## 2a. S6 — cover links drive series SUBSCRIPTION (supersedes S1's destination)

**STATUS: SCOPED 2026-09-08, not started.** Rick's idea, and better than any of the three options
this plan had reached on its own. **Rick's instruction: covers with no series are left unlinked.**

### Why S1's destination was wrong — measured, not argued

| Check | Result |
|---|---|
| This week's 68 arriving titles, by `catalog_month` | **2026-07: 55, 2026-06: 9, no catalog row: 4** |
| Current catalog month (`catalog.html` hard-scopes to it, `:634`) | **2026-09** |
| **Findable in `catalog.html`** | **0 of 68** |

The two surfaces are **disjoint by design**: the newsletter is `weekly_shipment` — what *arrives*
Wednesday, solicited two to three months ago — while the catalog is what you can *order now*, for
delivery in two months. A comic landing this week was ordered in July; the catalog is showing
November. They never overlap.

`arrivals.html` was the obvious next guess, and Rick rejected it correctly: it renders the same
`weekly_shipment` week the email already shows, so the click returns the reader to a list of the
covers they just looked at. **No new information — the click is meaningless.**

There is also no cheap third option: `catalog` and `weekly_shipment` are **both anon-denied**
(`42501 permission denied`, measured), so no public title page exists to land on without new DB work.

### Why subscribe is the right action

**Nothing in this newsletter can be ordered** — every title is past its FOC and already on the truck.
But *"I like this, get it for me every month from now on"* fits perfectly, and it is the app's core
loop (subscribe → the import auto-reserves standard covers each month).

It is also a far stronger signup pitch. *"Create a free account and never miss Teenage Mutant Ninja
Turtles"* beats *"create an account to browse a catalog"* — concrete intent, worth the friction.

**And it works for the exact reason the catalog did not.** `searchSeries()`
(`subscriptions.html:836-851`) queries `catalog` with **no `catalog_month` filter**, deliberately —
its own comment reads *"standard covers only across all catalog months"*. A June or July series is
findable today.

| Evidence | Result |
|---|---|
| Covers carrying a `series_name` | **58 of 68 (85%)** |
| Distinct series behind them | **30** — so subscribe-per-series is the meaningful unit, not per-cover |
| Series with a standard cover in the shipment | 29 of 30 |
| Series search month-scoped? | **No** |
| `Subscriptions.subscribe(userId, seriesName, distributor)` | already exists |
| Search panel already renders Subscribe buttons | yes (`subscriptions.html:~910`) |

**The 10 unlinked titles are semantically correct, not a compromise.** They are *Star Trek: 60th
Anniversary Special* (4 variants), *Star Trek: Deviations* (2), an *Archie vs the Terminator* ashcan
promo, a *Magic: The Gathering* one-shot, and two *Gunslinger Spawn* rows whose catalog row is
missing. **One-shots and specials have no next issue to subscribe to.**

### S6a — producer (scripts repo, `build-pull-feed.js`)

**One query, verified live against production (HTTP 200, 58/68 populated):**

```
select=title,cover_url,item_code,upc,catalog:catalog_id(series_name,distributor,variant_type)
```

- `row[2]` **becomes `series_name`**, replacing S1's `item_code || upc` key. Nothing else reads
  row[2], and carrying a dead key is worse than repurposing one. Same append-not-reorder discipline
  otherwise: rows [0] and [1] keep their meaning for all three builders.
- Cover links become `subscriptions.html?ref=newsletter&amp;series=<url-encoded>`.
- **No `series_name` → emit NO `<a>` at all.** The cover image and its title still render; they are
  simply not clickable.

**Decision taken: pass `series` only, not `distributor`.** The existing search dedupes by
`series_name||distributor` and shows both if a series exists under both — the reader picks. Passing
`d=` would need new filter logic in the page for a case that may never occur. Revisit if noisy.

**Known imprecision, accepted:** the search is `ilike %q%`, a substring match, so a short series name
surfaces its neighbours (a link for "Batman" also matches "Absolute Batman"). The results panel
handles that legibly. Exact-match-when-deep-linked is a refinement, not a blocker.

### S6b — `subscriptions.html` reads `?series=` — ✅ DONE ON STAGING 2026-09-08 (`68e3144`)

28 lines: read the param, set `#search`.value, call the existing `searchSeries()`. The panel, the
dedupe, the Subscribe buttons and the write path are all untouched, so a deep-linked result and a
typed one cannot diverge. **Honours `isBlocked`** — a pending or paused account already has its
search input disabled, and the deep link does not route around that gate. `ref` is deliberately not
read: any source may deep link, and the value exists only for the click report.

**Live and testable now:**
`https://staging.pulllist.pages.dev/subscriptions.html?ref=newsletter&series=Absolute%20Batman`

**✅ CONFIRMED BY RICK, 2026-09-08: "The URL works as expected when I signin first."** That is the
human gate, not just the harness — a real person, a real browser, a real session.

**The "when I signin first" qualifier is the finding, not an aside.** A logged-out visitor pasting
the same URL is bounced to the front door by `initNav()` with the URL discarded, and the page looks
broken when it is not. That is precisely **S6c**, and it is the half that serves acquisition —
a newcomer is by definition logged out.

**Gates — `playwright/s6b-series-deeplink-verify.mjs`, 11/11**, local-only, driving the deployed
staging bytes with a real browser (password grant + `addInitScript`, not a magic link — F107):

| Gate | Result |
|---|---|
| V1 | Search prefilled, panel displayed, series listed, Subscribe button offered |
| **V2** | The series lives **only** in older catalog months — the direct proof `catalog.html` could never have served this |
| V3 | Negative control — no param, search stays empty and panel hidden |
| V4 | Clicking Subscribe **wrote the row**, correct `user_id` and series |
| V5 | Unknown series → "No series found", not a broken page |
| V6 | Zero console errors across four page loads |
| V7 | Teardown clean — zero orphaned auth users, confirmed by a fresh read (F130's own failure mode) |

**Full regression: 146 passed, 0 failed, exit 0, 24.9 min**, run directly against the deployed
staging bytes post-push (not through `run-smoke.ps1` — 2026-08-30 note), after confirming the new
bytes were served on the **plain** URL.

**⚠️ V2 failed on the first run, and the fixture was wrong rather than the code.** The first pick,
*Absolute Green Lantern*, is an ongoing series present in **every** month including the current one,
so it discriminated nothing. Re-keyed to *Absolute Batman* (2026-05 → 08, absent from 2026-09).

That failure forced a measurement worth keeping: **1,470 of staging's 3,287 series (45%) are absent
from the current catalog month.** That is the scale of what the catalog destination could never have
shown, and it is now recorded in the harness.

### S6c — the return path (PULLLIST, the fiddly half)

`initNav()` (`app.js:508-511`) redirects an unauthenticated visitor to `index.html` and **discards
the URL**; `index.html` then hardcodes `window.location.href = 'catalog.html'` in **four** places
after successful auth (`:601`, `:661`, `:807`, `:852`). A newcomer's intent must be stashed before
the redirect and honoured at all four sites.

**This is what makes the acquisition case work end to end** — sign up, and land on the series that
made you sign up. It was not worth building when the destination was a catalog that could not show
the title. It is worth building now.

### What S6 does NOT do

**It does not close S1x.** Link count drops 72 → 62 (58 cover + 4 non-cover), which helps modestly.
Series names are longer than item codes, so the pre-rewrite file grows slightly while the
post-rewrite total falls a little. **The cover cap still needs a real send measurement.**

### Gates

| Gate | Check |
|---|---|
| **W1** | `node --check` clean; `--local` build completes |
| **W2** | Exactly **58** cover links, all to `subscriptions.html`, each carrying `ref=newsletter` and a URL-encoded `series` |
| **W3** | Exactly **10** covers render with **no `<a>` wrapper**, and their image and title still render. Assert the count, so a builder that was missed shows up as a shortfall rather than passing silently |
| **W4** | Every emitted `series` value traces back to a source row's `catalog.series_name` |
| **W5** | Date-normalised diff vs a pre-change baseline: only href/anchor lines changed; `rss.xml` byte-identical |
| **W6** | `npm test` still green (295/295) |
| **W7** | **Layout check in a real browser** — an unlinked cover cell must sit correctly beside linked ones, desktop and mobile widths |
| **W8** | S6b: **the URL half CONFIRMED by Rick 2026-09-08** (signed in, staging, real browser). The *click-from-the-email* half is **not yet testable**: the producer's `APP_BASE_URL` is `rjbookstop.pulllist.app` — **production** — so every cover in a local preview points at production, where S6b is not deployed. End-to-end newsletter → click → subscribe can only be exercised once S6b is promoted |

### Sequencing — and why S6a ships before Friday regardless

**Doing nothing is the worst option.** Friday's import publishes whatever is in the scripts repo,
and that is currently S1's catalog links — a destination that provably cannot show the title.

**S6a alone is still an improvement** even before S6b is promoted: the param is inert, so a
logged-in reader lands on the subscriptions page rather than the specific series. Topically right,
not yet precise. A logged-out reader's path is unchanged either way (front door).

Recommended: **S6a to the scripts repo before Friday; S6b and S6c to staging in parallel, promoted
on their own merits.** If S6b lands first, better — but do not hold S6a for it.

---

## 3. Out of scope — named so they are not re-derived

| Item | Why deferred |
|---|---|
| **S4** — catalog deep-link plus a `requireAuth()` return path, so a click survives signup and lands on the actual comic | A PULLLIST client change and a deploy. This is what unlocks the real conversion; sequence it after S1 proves the link change is safe. |
| **S5** — app-side capture of `?ref=` so signups attribute to the newsletter | Client change, likely a `usage_events` row. Needed to answer "did this work", but S3's Brevo-side data is the cheaper first read. |
| Double opt-in confirmation deliverability | **✅ CHECKED AND CLEAN, 2026-09-08 — not a live concern.** See § 5. Outlook half still unchecked, minor. |
| SPF alignment on `rjbookstop.pulllist.app` (20 of 20 sends unaligned) | Real, cheap, and not the bottleneck. Brevo custom Return-Path; `mail.rjbookstop.pulllist.app` is NXDOMAIN today. Verify plan availability first. |
| Growing the subscriber list from in-store traffic | Not a code change. The newsletter can only recruit people who already found `/news/`. |
| Inviting the existing 29 app customers onto the list | **Explicitly rejected** — they are already converted, so it would lift the open-rate number without serving the goal. |

---

## 4. Verification gates

Run the producer with `--local` throughout. **Never `--publish` while developing** — per **F135**
the producer is welded to shipment import and a publish purges the live week's thumbnails; the
interim mitigation is commenting out `GITHUB_TOKEN_PULL_FEED` in `.env`.

| Gate | Check |
|---|---|
| **V1** | `node --check build-pull-feed.js` clean; a `--local` build completes |
| **V2** | **Zero** hrefs to `media.lunardistribution.com` or `images.penguinrandomhouse.com` in the built `newsletter-email.html` **and** `newsletter.html` — the whole point of S1, as a grep assertion. (`rss.xml` only if § 2 S1 decided to change it.) |
| **V3** | Every cover href resolves to the `rjbookstop.pulllist.app` host and carries `ref=newsletter`; each `c=` matches its source row's `item_code`; a null `item_code` degrades to the plain catalog URL rather than a broken link. **Assert the count too** — one changed href per rendered cover, so a builder that was missed shows up as a shortfall rather than passing silently |
| **V4** | Built `newsletter-email.html` **under 80 KB raw**, leaving headroom for Brevo's rewriting against the ~102 KB clip line |
| **V5** | `rows`-shape regression check: diff all three artifacts against a pre-change `--local` build. `rss.xml` should be **byte-identical** unless S1 deliberately changed it; the two HTML files should differ **only** in the cover hrefs and the S2 copy. Any other delta means the tuple change leaked |
| **V6** | `npm test` still green (currently 295/295) |
| **V7** | **A real test send through Brevo to a seed address, opened in Gmail** — no "[Message clipped]" banner, covers render, and a cover click lands on the app |

V7 is the gate that matters most and the easiest to skip. Do not skip it.

---

## 5. Pre-session check — DONE, and it came back CLEAN

**✅ CLEARED 2026-09-08 (Rick): the double opt-in confirmation arrives, and NOT in Gmail spam.**

This was the highest-risk unknown, because the failure would have been invisible: the form's success
state reads *"Almost there — check your inbox to confirm."* A confirmation landing in spam kills
every signup silently — no bounce, no error, no list entry, no signal — and would on its own have
produced a 10-person list. **It is not happening.** Gmail is also the dominant provider on this
list (DMARC counts across the two observed sends: Gmail 6 and 9, versus 1 each for Yahoo and 1–2 for
Outlook), so this covers most of the audience.

**What this rules out, and what it therefore narrows to.** The signup mechanism works end to end.
So the list is small because **too few people reach the form**, not because the form or its
confirmation is broken. That moves the constraint upstream, to § 3's traffic item — see § 6.

**Residual, minor and not blocking:** the Outlook half was not checked. **F152** records a real
production send from the sibling `pulllist.app` domain landing in Microsoft's spam folder, so that
provider remains the plausible one. It is a small slice of this list, so this is worth a check when
convenient rather than before the session.

**Keep double opt-in** — with a sending domain this new, a clean list is protective, and it is now
demonstrated not to be costing signups at Gmail.

---

## 5a. S1 goes live at the next import — DECIDED: let it land naturally

There is no deploy button here. `build-pull-feed.js` is invoked by `import.js`, so **a shipment
import republishes `newsletter.html` and `newsletter-email.html` carrying the new links**, and the
Brevo cron then sends from them.

**Decision (Rick, 2026-09-08): the Tue 2026-09-08 send goes as-is — no pre-publish, no rush.**
That send therefore carried the **old** CDN links, from the feed stamped `2026-09-04`. Deliberate,
not an oversight.

**The new links land at the Fri 2026-09-11 weekly import**, which republishes all three artifacts.
Rick verifies the browser page after that import.

**A `--publish` was explicitly NOT run to preview.** It writes the live `weekly-pull-feed` Pages
repo — three artifacts plus thumbnail adds and orphan purges in one commit — and re-stamps the
`pull-feed-generated:` freshness marker the Brevo send script reads. That is the **F135** hazard.
`--local` produces byte-identical artifacts with none of it, and `pull-feed-out/newsletter.html`
was reviewed that way instead.

**Revert, if the published result is wrong:** `git revert 8836380` in the scripts repo, then the
following import republishes the old links. Nothing in the app, the database or Brevo needs
touching.

---

## 6. Sequencing, and an expectation worth setting

S1–S3 are one session and are independent of the October catalog import gate (2026-09-25). They
touch no import-path code, no withdrawal logic and no catalog write, so they neither help nor
endanger that gate and can land before or after it without interaction.

**Set the expectation honestly before doing the work.** App signups from this channel are the
product of two factors:

```
   signups  =  subscribers  ×  conversion per subscriber
                  (10)            (~0 today — clicks exit to a CDN)
```

**S1–S3 fix the right-hand factor only.** They are worth doing — a funnel that leaks 65 clicks an
issue to a distributor's image server cannot convert anyone, and § 5 has now shown the signup path
itself works. But 10 subscribers times a good conversion rate is still a small number.

The left-hand factor is **not a code change** and is the larger multiplier: getting store traffic to
`/news/` at all — in-store signage, a QR code at the register, the `rjbookstop.pulllist.app` CTA
already printed on bagging lists. Both factors matter; only one of them is in this plan. Do not read
a modest post-S3 result as S1–S3 having failed.
