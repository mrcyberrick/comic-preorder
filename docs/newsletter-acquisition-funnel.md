# Weekly newsletter — acquisition funnel repair

**STATUS:** NOT STARTED 2026-09-08 | staging=— | prod=— | findings=none (feature build)

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

### S1 — cover links point at the app, not the distributor CDN

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

`Auth.requireAuth()` (`app.js:264`) redirects an unauthenticated visitor to `index.html` and
**discards the requested URL** — there is no `?next=` return path. And no page in the app reads a
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

### S2 — rewrite the CTA for someone who has never used the app

Two builders carry the promo block and must stay consistent: `buildEmailHtml()` (~lines 1404-1476)
and `buildNewsletterHtml()` (~lines 984-1064).

Replace the account-presuming copy. The newcomer framing needs to carry: **it is free**, it takes
under a minute, and what it does for them (never miss an issue / we hold it behind the counter).
"Reserve Your Comics" may stay as secondary copy for existing users, but must not be the primary
button.

Exact wording is Rick's call — this plan deliberately does not pre-write his shop's voice.

### S3 — attribution, so a working campaign is distinguishable from a broken one

Append `?ref=newsletter` to all app links (the 3 existing plus the 65 from S1).

**Verified safe:** the client reads only `?t=` (`app.js:115`), so unknown query params are inert and
cannot disturb `TenantContext` resolution or any page's init.

This makes Brevo's click report per-title and per-placement. **It does not close the loop to
signups** — that needs app-side capture, which is **S5** (§ 3).

### S1x — the size guard, shipped WITH S1, not after

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

## 3. Out of scope — named so they are not re-derived

| Item | Why deferred |
|---|---|
| **S4** — catalog deep-link plus a `requireAuth()` return path, so a click survives signup and lands on the actual comic | A PULLLIST client change and a deploy. This is what unlocks the real conversion; sequence it after S1 proves the link change is safe. |
| **S5** — app-side capture of `?ref=` so signups attribute to the newsletter | Client change, likely a `usage_events` row. Needed to answer "did this work", but S3's Brevo-side data is the cheaper first read. |
| Double opt-in confirmation deliverability | **Do this first anyway — a 2-minute manual check, not a code change.** See § 5. |
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

## 5. Do this before the session — it is free

**Sign up at `rjbookstop.com/news/` with a Gmail address and an Outlook address, and confirm the
double opt-in email actually reaches the inbox.**

The form's success state reads *"Almost there — check your inbox to confirm."* If that confirmation
lands in spam, every signup dies silently — no bounce, no error, no list entry, no signal. That
failure mode alone would produce a 10-person list.

It is plausible here: **F152** records a real production send from the sibling `pulllist.app` domain
landing in Microsoft's spam folder, and the newsletter's sending domain has even less reputation
history.

**Keep double opt-in either way** — with a domain this new, a clean list is protective. Just confirm
the confirmation arrives.

---

## 6. Sequencing

S1–S3 are one session and are independent of the October catalog import gate (2026-09-25). They
touch no import-path code, no withdrawal logic and no catalog write, so they neither help nor
endanger that gate and can land before or after it without interaction.
