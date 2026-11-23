# Top Picks: smarter picks, picks in emails, and a notification settings page

**STATUS:** IN PROGRESS — S0 DONE; S1 and S2 DONE ON STAGING 2026-11-17 (S1 SQL applied by Rick, parity harness 109/0; S2 `4a2434c`, harnesses 19/19 and 46/46, full suite 170/1/0); S1 SQL APPLIED ON PRODUCTION 2026-11-17 (two passes, § 6); S2 PROMOTED TO PRODUCTION 2026-11-17 (PR #190, merge `01b1a08`; served bytes verified, Rick's write-smoke read back from the log, § 6); S3 DONE ON STAGING 2026-11-17 (`473d98b` + `8e2da2f`, § 6); S4 DONE ON STAGING 2026-11-17 (`072d9fe`; the `email-preferences` function is deployed to staging, its secret set there only, § 6); S5 BUILT AND VERIFIED ON STAGING 2026-11-18 (`c18b865`, `7525dc3`, `33e067a`; both mail functions deployed to staging; Rick's real-inbox check done 2026-11-18: arrived in the Gmail Inbox, footer link present, DKIM over the new headers not yet confirmed, § 6); paid-shop link addresses built the same day (`baedd98`, staging only); S6 IN PROGRESS: the client PR (#191, merge `b6edb5d`) merged 2026-11-21, Rick's write-smoke read back green, and the three functions are deployed to production; `EMAIL_PREFS_SECRET` is NOT set yet, so no email has changed (§ 6, "S6 on production"); readiness re-checked 2026-11-22 (secret generated into the scripts `.env` only, set and check scripts written and rehearsed, Tuesday forecast 10 emails all with picks, § 6 "S6 readiness") · planned 2026-11-17 · every decision D1-D10 and O1 answered by Rick 2026-11-17 (D6, D9, D10: "defaults"); O2 open · staging=2026-11-17 (S1, S2) · prod=2026-11-17 (S1, S2) · PR=#190 · findings=— (none consumed by this work; F183 filed the same day for the arrivals schedule, found while checking this work leaves it alone; F184 and F185 filed 2026-11-18 from this work's observations, F186 next free)

Rick's request (2026-11-17): the catalog's **Top picks for you** rail should (1) surface **New #1 series
starting this month** when there is no history to build from, and (2) never show a title the customer has
already reserved. The same picks then go into the two customer emails, the **new-catalog email**
(`notify-customers`, sent at the monthly import) and the **Tuesday arrivals email** (`notify-arrivals`),
each pick reservable from the email. Because that is promotional, each email gets an opt-out link, and
every customer gets a **profile settings page** with notification toggles.

---

## 1. What exists today (read from code and staging, 2026-11-17)

**The rail** (`catalog.html` `loadTopPicks()`, `app.js` `Recommendations.getTopPicks()`), desktop only:
two tiers, *personal* (series the customer has reserved before, from `reservation_history` plus
`preorders`) and *popular* (`get_popular_series()`), **alternated, personal first** (Rick, 2026-10-09).
A row is dropped when it is already reserved **by exact catalog id**, past FOC, not a standard cover,
hidden by the store's catalog visibility settings, or a second title from a series already picked.
So request (2) already holds on the rail. Rick (2026-11-17): keep that rule as it is and apply the same
rule in the emails (D4).

**The ranking runs in the browser.** The emails run in two Edge Functions (Deno, service role, many
customers per run). Copying the JavaScript into both would give three copies of one rule. § 3 moves the
pick rule into one SQL function all three callers use.

**The two emails:**

| | `notify-customers` (new catalog) | `notify-arrivals` (Tuesday) |
|---|---|---|
| Sent by | the import script (service key), or an admin | the weekly cron, or an admin |
| Recipients | every non-admin, non-paper profile (**no status filter**: pending and paused get it) | active, non-paper, `email_arrivals` on |
| Opt-out today | **none** | "turn it off on My List" (sign-in needed) |
| Postal address | yes, both tiers (Q13; a free shop with no `tenants.location` is not sent) | **paid tier only** |
| Already promotional? | yes (Q13 called it "the one promotional email") | no, a service notice |

Two consequences: the catalog email already lacks the opt-out a promotional email needs, and the
arrivals email becomes partly promotional once picks are added, so it then needs a postal address on
both tiers (§ 3.5).

**No catalog deep link.** `catalog.html` reads no query parameter; a link cannot open one title. The
subscriptions page's `?series=` (S6b) and `PostAuthRedirect` (S6c, one-shot, 1-hour TTL in
`localStorage`) are the patterns to reuse.

**Measured on staging (2026-10 catalog, 2,234 rows, read-only):**

- `issue_number` **cannot identify a #1.** On Lunar it is `1` on 607 rows, including trade paperbacks,
  hardcovers and T-shirts. On **PRH it is not the issue number at all**: "Zorro Annual #1 Cover A" stores
  `0`, and "AMAZING SPIDER-MAN: SYMBIE #1 COVER E ... 1:25 VARIANT" stores `14`. The `#1` must come from
  the **title**.
- Format separates comics from the rest: Lunar `Periodical` (1,050), PRH `Comic Book` (495).
- **Comics only, then compared** (Rick asked whether limiting `issue_number` to comics helps). Standard
  covers only: on **Lunar** comics, `issue_number = 1` gives 73 rows and `#1` in the title gives 56; all 56
  have `issue_number = 1`, and the 17 extra are Dynamic Forces signed or exclusive copies of other issues
  (`DF HARLEY QUINN #66 ...`, `DF ABSOLUTE BATMAN #23 ...`) that Lunar stamps with 1. On **PRH** comics,
  `issue_number = 1` finds **1** of the 26 titles with `#1` in the title; the others store `0` (Zorro
  Annual, Fantastic Four: First Foes, Amazing Spider-Man: Symbie). So comics-only helps on Lunar and does
  not rescue PRH, whose Marvel #1s would all be missed.
- Standard cover + format `Periodical`/`Comic Book` + `#1` in the title (not `#10`-`#19`) = **82 rows**;
  dropping DC Start Here bundles, `(NET)`, facsimiles, Dynamic Forces `DF ...` and `SIGNED` editions,
  `2ND PTG`/printings, `BLANK` and `VIRGIN` leaves **61 rows, 59 distinct series (Lunar 36, PRH 23)**.
  One noisy row survived ("RETURN LIVING DEAD #1 ... MORE BRAINS LIMITED EDITION"). Production's
  2026-11 catalog is unmeasured (S0).

---

## 2. Decisions

| # | Decision | Status |
|---|---|---|
| D1 | **Reserve from the email = a link that opens that title on the Catalog page with its Reserve button.** A signed-out customer signs in and lands back on the title. Every existing reserve rule applies unchanged. No link reserves by itself: mail scanners (Outlook Safe Links and similar) open every link before the customer does, and the store orders each reservation for that customer. | **Rick, 2026-11-17** |
| D2 | **Three toggles:** new-catalog email, weekly arrivals email, and "Include Top Picks in my emails". The email's opt-out link opens these settings without signing in (D9). | **Rick, 2026-11-17** |
| D3 | **Priority: personal over store, popular over New #1.** New #1 is the default only when no history can be used. Read as: personal and popular keep alternating, personal first (Rick's 2026-10-09 rule, unchanged); **New #1s fill only the slots the two history tiers leave empty**, so they appear for a shop with no reservation history at all, and as a top-up when history runs short (late in the month, when most history titles are past FOC). | **Rick, 2026-11-17** (the alternation and the top-up are this plan's reading of his answer; he did not correct it when it was put to him the same day) |
| D4 | "Already reserved" stays **the exact row**, the rail's existing rule (Rick's 2026-10-09 rail), unchanged, and the emails use the same rule. A different cover of an issue the customer reserved can still be a pick. | **Rick, 2026-11-17** |
| D5 | **New #1 rule: comics only** (Rick: "not interested in trades and T-shirts"): format `Periodical` (Lunar) or `Comic Book` (PRH); standard cover; **`#1` read from the title**, not followed by a digit, because PRH's `issue_number` is `0` on 25 of its 26 #1 comics (§ 1); title does not match `FACSIMILE`, `BUNDLE`, `(NET)`, a leading `DF`, `SIGNED`, `BLANK`, `VIRGIN`, `PTG`/`PRINTING`; FOC not passed; passes the store's visibility settings; one per series. One-shots count. On Lunar the title test and `issue_number = 1` agree once `DF` copies are dropped. | **Rick, 2026-11-17** (comics only); the title test is the measured consequence |
| D6 | **Emails carry 4 picks**, only for an account that is active, not paper, and has Top Picks on. Fewer than 4 eligible picks shows what there is; none omits the section. | **Rick, 2026-11-17** (default) |
| D7 | The arrivals toggle **moves** from My List to the profile page; My List keeps a "Email settings" link in its place, so one setting has one control. The arrivals email's "turn it off on My List" line is replaced by the opt-out link. | **Rick, 2026-11-17** (default) |
| D8 | The profile page is **`account.html`, "My Account"**, reached by making the nav greeting's name a link (desktop bar and phone drawer). It joins the nav sync set as its **eighth** page. Name and email are shown read-only (changing an email is F126, out of scope). | **Rick, 2026-11-17** (default) |
| D9 | **Opt-out:** each email footer links to a **preferences page that needs no sign-in** (a signed token in the link), showing the three toggles. Each email also carries `List-Unsubscribe` + `List-Unsubscribe-Post` headers; the one-click unsubscribe a mail client offers turns off **that** email. The link only opens the page; nothing changes until the customer presses a button (scanners again). | **Rick, 2026-11-17** (default) |
| D10 | "See more" on the rail still opens the Recommended For You view (its own ranking in `app.js`). When the rail holds only New #1s, "See more" is hidden, since that view has nothing matching to show. | **Rick, 2026-11-17** (default) |

**Answered, and open:**
- **O1, answered (Rick, 2026-11-17): "not promotional, should remain transactional only".** Pending and
  paused accounts keep getting the catalog email exactly as today (`notify-customers` filters on
  `is_admin` only), and **never with Top Picks**: picks go to active accounts only. The footer settings
  link (D9) is on every send, theirs included, since it is how anyone turns an email off and is not
  promotional.
- **O2, open.** Should a series the customer **subscribes to** be excluded from picks? Auto-reserve normally
  reserves its standard cover at import, so D4 already hides that row; it matters only when a
  subscription was added after the import. Not built unless asked.

---

## 3. Design

### 3.1 One pick rule, in SQL: `get_top_picks(p_user_id uuid, p_limit int)`

`SECURITY DEFINER`, `search_path = public`. EXECUTE granted to `authenticated` and `service_role`,
revoked from `anon` and `PUBLIC` (F124's lesson: a new function is executable by `anon` until revoked).

- **Who may ask for whom:** an authenticated caller may ask only for itself, or, as an admin, for a
  customer in its own tenant (the rail's impersonation path, `AdminContext.resolveUserId()`). The service
  role may ask for anyone. Tenant is always taken from the target's own profile, never a parameter.
- **Month:** the tenant's latest `catalog_month`.
- **Tiers:** personal (`reservation_history` + `preorders` series keys), popular (the same aggregate
  `get_popular_series()` computes), New #1 (D5). Alternate personal/popular, personal first, one per
  series across all tiers; New #1 fills what is left (D3).
- **Drops:** reserved by this customer, exact row (D4), FOC passed, not a standard cover, and the store's
  `catalog_filters` rules, read the way `CatalogFilters.load()`/`.hides()` read them: hidden publisher,
  standard covers switched off, the restricted-ratio rules (`coverClassOf()` calls a standard cover with a
  ratio "restricted"; measured 0 such rows, copied anyway), the FOC rule in either mode, zero price
  (`Number(null) === 0`, so a missing price counts as zero, as in JS).
- **Order, defined here because the JavaScript left it to chance** (S1):
  - within a series, the eligible row with the **soonest FOC** (JS took the first by UUID);
  - personal series by **how often this customer reserved them**, then the store's count, then name (JS
    used whatever order the database returned the history in);
  - popular series by the store's count, **then name**: `get_popular_series()` has no tie-breaker, so
    today's rail can reorder tied series between page loads;
  - New #1s by soonest FOC, then title.
- **Returns** `pick_id uuid, pick_tier text ('personal'|'popular'|'new1'), pick_rank integer`, rank order;
  `p_limit` defaults to 20, capped at 500.
- **Date:** "today" for FOC is `CURRENT_DATE` (UTC). The import may run in the evening Eastern, after the
  UTC date has turned, which drops a title whose FOC is that same day a few hours early. Conservative,
  accepted.

The rail, `notify-customers` and `notify-arrivals` all call this. `app.js`'s `getTopPicks()` is retired;
`getCatalogIds()` stays for the Recommended For You view (D10).

### 3.2 Catalog deep link: `catalog.html?pick=<catalog_id>&ref=<source>`

On load, a `pick` parameter fetches that catalog row and opens its modal (works on a phone too; the rail
is desktop-only but the modal is not). Signed out: `initNav()` already stashes the URL through
`PostAuthRedirect` and returns to it after sign-in. Already reserved, past FOC, or paused: the modal
shows its normal state. An unknown or other-tenant id opens nothing (RLS hides it) and shows a short
toast. `ref` is `email-catalog` or `email-arrivals`; opening logs one `pick_opened` usage event
(`{source, catalog_id}`), so Analytics can count email picks opened against `reserve` events.

### 3.3 Settings: three columns and the guard

`user_profiles.email_catalog boolean NOT NULL DEFAULT true` and
`user_profiles.email_picks boolean NOT NULL DEFAULT true` (`email_arrivals` exists). **The F182
self-update guard trigger allowlists the columns a customer may change on their own profile**
(`has_seen_welcome`, `email_arrivals` today; S3b had to widen it, see
`docs/sql/2026-11-14-s3b-email-arrivals-opt-out-and-notices.sql`). It must be widened to the two new
columns in the same SQL file, or every customer's save fails with `42501`.

### 3.4 Preferences without sign-in

- **Token:** HMAC-SHA256 over `v1|<user_id>` with a new secret `EMAIL_PREFS_SECRET` (both projects). No
  expiry (an opt-out link must keep working). It authorizes changing that customer's three email
  toggles and nothing else.
- **Edge Function `email-preferences`** (public, `--no-verify-jwt`; the token is the gate): `GET ?u=&s=`
  returns the three toggles as JSON; `POST` sets them; a `POST` with body `List-Unsubscribe=One-Click`
  and `?k=catalog|arrivals` turns that one email off (RFC 8058). A bad token gets one generic refusal.
- **Page `email-preferences.html`** (static, anonymous, like `forgot-password.html`; no nav): reads the
  token from the URL, shows the three toggles, saves on press. The page is static because Supabase is
  understood to serve an Edge Function's HTML as plain text on its own domain (verify in S4).
- **As built (S4, details in § 6):** the token is 64 lowercase hex characters, minted and checked by one
  block of code (`mintPrefsToken` / `verifyPrefsToken`, marked `BEGIN` / `END` in the function) that S5's two
  mail functions copy byte-identically with a grep gate, as the F72 identity block is. The function never
  returns HTML: a GET from a browser (`Accept: text/html`) is **redirected** to the static page, so the
  address that goes in `List-Unsubscribe` also works when a person simply clicks it. The one-click POST is
  honoured for **every** account state (a mail client has already shown "unsubscribed"); the page's own
  switches follow My Account's rule (a pending or paused account sees none). No `usage_events` row is written,
  because an event attributed to the customer would move their "last seen".

### 3.5 The email section

- Up to 4 picks (D6), as a table layout (mail clients ignore most CSS): cover image (the catalog's
  `cover_url`, distributor-hosted; many clients block remote images by default, so the title and price
  carry the card without it), title, price, a **Reserve** button linking per § 3.2. Heading "Top picks
  for you", the same caption rule as the rail.
- Placed **after** the email's own purpose (the catalog announcement; the arrivals table), so the service
  content leads.
- Footer: "Email settings or unsubscribe" link (§ 3.4) on every send, picks or not.
- **Postal address:** a send that includes picks carries the shop's postal address on both tiers, the
  rule `notify-customers` already follows (Q13). A free shop with no `tenants.location` gets its arrivals
  email **without** picks rather than not at all. (The store-contact plan's S2 will move this onto the new
  `tenants.postal_address`; until then `location` is the field.)
- Links use the shop's own address for a paid shop and the apex otherwise, the `Tier.publicUrl()` rule.
- Cost: one `get_top_picks` call per recipient. `notify-customers` already loops per recipient (F148);
  about 0.3 s each, roughly 30 s for 100 customers. Measure in S5 against the Edge Function time limit
  before assuming.

---

## 4. Build sequence

Each session is staging first; production is a separate, explicitly requested promotion.

| Session | What | Gate |
|---|---|---|
| **S0** | Read-only on production: New #1 yield for 2026-11 under D5; how many active customers have no personal history; current rail picks for three accounts (Rick's choice of accounts). | numbers recorded here |
| **S1** | SQL (`docs/sql/<date>-top-picks-rpc-and-email-prefs.sql`): `get_top_picks()`, the two columns, the widened guard. Staging. | **parity harness:** for 10+ staging accounts, run today's `getTopPicks()` (the real `app.js`, in a browser, unlimited) and the RPC (limit 500): the **series in each tier are identical**, every RPC row passes the rules on its own data, and New #1 rows appear only after both history tiers run out (D3/D5). Rank order and the row chosen within a series are compared to § 3.1's new rules, not to JS (which left both to chance); anon refused (`42501`); a customer cannot ask for another customer; an admin cannot ask across tenants; a negative control per rule seen red |
| **S2** | Client: the rail calls the RPC; New #1 caption; D10; `?pick=` deep link + `pick_opened` event. | spec updates (local suite) + the full suite after push; a real deep-link click signed in and signed out |
| **S3** | `account.html` (eighth nav page), the three toggles, the greeting link, D7 on My List, a `privacy.html` sentence. **The settings gear self-gates on `#search` being absent**, so a new page without a search box would show it; gate it on the page explicitly. | nav and footer hashes identical across eight pages; toggles round-trip; the F182 guard accepts the two new columns and still refuses everything else |
| **S4** | `email-preferences` Edge Function + `email-preferences.html` + the secret. | bad and missing token refused; good token reads and sets; one-click POST turns off only its own email; no other profile column writable through it; GET never changes anything |
| **S5** | Both mail functions: picks section (active accounts only, O1), footer link, `List-Unsubscribe` headers, `email_catalog` honored, the postal-address rule. Deploy to staging reading live `verify_jwt` first (F93; `notify-customers` and `notify-arrivals` are both OFF). | a fake-network template harness (opted-out customer gets no picks; a pending or paused account gets the email without picks; free shop without address gets no picks; HTML escaped); then Rick's real inbox, **headers only**: picks render, links open the title, unsubscribe works |
| **S6** | Production: SQL first, then the client PR (`app.js` carries `merge=ours`: assert its merge result), then the three Edge Functions and the secret. | served bytes equal `main`; a real send read back; a write-smoke, since the catalog reserve path changes |

S1 + S2 alone are a useful first promotion (the better rail) and can ship before the emails. S3 and S4
must land before S5: no promotional content is sent until the opt-out it points to exists.

---

## 5. Not in scope

Changing a customer's email or name from the profile page (F126). A picks section on the weekly
newsletter (Brevo, `weekly-pull-feed`). A phone version of the rail. Reserving without signing in (D1).
Resend's 100-per-day limit (F148) is unchanged by this work: picks add no sends.

---

## 6. Build record

### S0, 2026-11-17: production counts (read-only, service role, GET only)

Script kept in the session scratchpad, not committed. "Today" = 2026-11-17; the store's
`catalog_filters` applied; customer ids not printed.

| | `rjbookstop` (pro), month 2026-11 | `comicstore` (free), month 2026-06 |
|---|---|---|
| Catalog rows with a series | 1,925 | 2 |
| New #1 series under D5, FOC still open | **42** (Lunar 24, PRH 18) | 0 |
| Non-admin profiles | 33: 21 active, 12 paper, 0 pending, 0 suspended | 1 active |
| Active customers with **no personal history** | **8 of 21** | 0 |
| Popular series this month | 68 | 1 |
| History-based picks available per active customer (distinct series, FOC open) | min **41**, median 68, max 69 | 1 |
| Customers short of 4 (an email) / short of 20 (the rail) | 0 / 0 | 1 / 1 |

**What it means for D3.** Every active Ray & Judy's customer has at least 41 history-based picks today,
so with "popular over New #1" **New #1s will not appear at Ray & Judy's** in the rail or the emails; the 8
customers with no history of their own get the store's popular titles. New #1s fill in only for a shop
with no reservation history (a new tenant) or one whose history titles are all past FOC. Reported to
Rick the same day; the priority is one line in `get_top_picks()` if he wants New #1s mixed in instead.

New #1 sample (production): HIDE NOR HAIR #1 (OF 6) CVR A, Barbie #1 (CVR A), Dr Syn #1 Cover A, DC ALL
IN SAGA THE NEW GODS #1 (ONE SHOT) CVR A, AVENGERS: INCURSIONS #1 COVER A, Vampire Hunter D: Fortress of
Blood #1 (CVR A).

### S1, 2026-11-17: SQL written, applied on staging, gate green

`docs/sql/2026-11-17-top-picks-rpc-and-email-prefs.sql`: STEP 0 pre-check (halts if the F182 guard is not
the S3b body or `get_popular_series()` no longer counts rows), one transaction (two columns, the widened
guard, `get_top_picks()`, grants), a VERDICT that reads differently before and after, and a SMOKE per
tenant with no customer ids. `get_popular_series()`'s body was taken from the 2026-06-10 production
schema dump (`COUNT(*)`, tenant-filtered, no tie-breaker); STEP 0 confirms it is still that shape.
*(This read "**Next:** Rick runs it on staging; then the parity harness" until the run below.)*

**Staging, 2026-11-17.** Rick ran the file on staging and pasted the SMOKE only:
`raysandjudys` 19 active customers, all 19 with picks, fewest 11, most 12; tiers summed personal 1,
popular 19, new1 190. Staging's catalog is still 2026-10 (production is on 2026-11), so most of its
history titles are past FOC: each customer had 1-2 history picks and about 10 New #1s filled the rest.
That is D3's top-up doing its job, and the only place it can be seen today (S0: production never
reaches it). **STEP 0 and the VERDICT were not pasted**, so their claims were checked by behaviour.

**Gate: `playwright/top-picks-rpc-parity.mjs`** (scripts repo working tree, local-only). As a
throwaway admin in a real browser (UTC, so "today" matches `CURRENT_DATE`), for 12 customers (throwaway
A with 12 seeded history series and one reservation, throwaway B with nothing, 10 real staging
customers) it runs the deployed `app.js` `getTopPicks()` unlimited and `get_top_picks()` at 500. For the
run it hides one publisher (Scholastic, the publisher of one of A's series) and restores the exact
original `catalog_filters` value afterwards (`updated_at` unchanged, checked).

- **109 passed, 0 failed:** the series in each history tier identical for all 12 (A: 10 personal + 1
  popular, after its reserved series and the hidden publisher's series dropped out); every history pick
  in `app.js`'s own eligible list; every New #1 passes the real `CatalogFilters.hides()` and reserve /
  FOC / cover rules on its own row; one per series; each history pick its series' soonest-FOC row;
  personal/popular alternate, personal first; New #1s only after both history tiers, all D5 comics from
  series neither tier holds; ranks 1..n. Who may ask: anon refused by the grant (401, `42501`); a
  customer gets their own picks, cannot ask for another (403); an admin can ask within their shop, not
  for another shop's customer (403); the service role can ask for anyone. Columns: both present, 0
  non-default rows; a customer can switch both new toggles off and on, and the guard still refuses their
  own `full_name` (403, `42501`). D4: reserving a customer's rank-1 pick removes it.
- **Negative controls, each red on the series it should be:** `--control=noreserved` (the `app.js` side
  ignores reservations) failed P1 on A's reserved series (Strange Pictures TP); `--control=nocfg` (the
  `app.js` side ignores the store's settings) failed P1 on the hidden publisher's series (Baby Sitters
  Club TP).
- **Harness errors caught on the way (mine, not the function's):** the first run checked New #1 picks
  against `app.js`'s ranked list, which never contains them (12 false failures, one per customer, each
  equal to that customer's New #1 count); and it ran the two throwaways twice, because the "real
  customers" query found them.

**Not verified:** production (SQL still PENDING there); the staging popular tier holds only 1-2 series,
so popular-tier parity rests on few rows; personal-tier ORDER is checked as "alternating", not against
each customer's own counts.

### S2, 2026-11-17: the rail on `get_top_picks()` and the `?pick=` link, on staging

Staging code `4a2434c` (`app.js`, `catalog.html`; branch `feature/top-picks-s2-rail-rpc-and-deep-link`,
fast-forwarded). **What changed:** `loadTopPicks()` calls `db.rpc('get_top_picks', { p_user_id:
AdminContext.resolveUserId(user.id), p_limit: 20 })` (the function applies the reserved rule and the
store's settings itself); the caption adds ", plus New #1s starting this month" when New #1s are on the
rail, and reads "New #1 series starting this month" when nothing else is; "See more" is hidden by
`visibility` when the rail holds only New #1s (D10; `display` would slide the Hide button, since the link
carries `margin-left: auto`). `catalog.html?pick=<id>&ref=<source>` fetches that row, opens its modal,
strips both parameters (`history.replaceState`), and logs `pick_opened` `{source, catalog_id}` for a real
customer (not an admin, not while viewing as a customer); a malformed id or one this shop cannot see
shows a toast. `app.js`: `UsageEvents.pickOpened()` added; `Recommendations.getTopPicks()` removed (the
Recommended For You view keeps `getCatalogIds()`).

**Verified on the deployed bytes** (served `catalog.html` and `app.js` hashed equal to the commit first):
- **`playwright/top-picks-s2-verify.mjs` (local-only) 19/19:** the rail shows `get_top_picks(…, 20)`
  in rank order (20 of 20) with the matching caption and "See more"; with the history publishers hidden
  for the run, a no-history customer's rail is New #1s only, captioned "New #1 series starting this
  month", "See more" hidden (screenshot inspected: Hide stays at the right edge). The link: opens the
  title's modal signed in; removes the parameters; logs one `pick_opened` with the right source, title and
  shop; Reserve in that modal writes the reservation (right shop, qty 1); a reload neither reopens nor
  logs again; the reserved title leaves the rail; works at 390 px; signed out, the sign-in page keeps the
  link (`PostAuthRedirect`) and after sign-in the customer lands on the title; an admin sees the modal and
  nothing is logged; a malformed id and an unknown id each show their toast and no modal.
  `catalog_filters` restored exactly. **One harness error of mine, fixed:** the event checks first read
  the table straight after the modal opened and then closed the browser, which can abort the app's
  fire-and-forget insert (L10 read 1 of 2); the checks now wait up to 10 s.
- **`playwright/catalog-top-picks-verify.mjs` (the rail's original harness) 46/46** on groups v3, unpin,
  collapse, memory, par, cls, nav. One check, **B3**, failed first by design: a no-history customer's
  caption is now "The store's most popular reservations, plus New #1s starting this month" (staging's
  popular tier is short, so D3's top-up applies); its expectation was updated to the new contract, with
  the old wording kept in a comment. Layout shift 0.0098 desktop, 0.0115 mobile.
- **Full suite on the deployed bytes: 170 passed, 1 skipped, 0 failed, 28.5 min, exit 0** (the log's own summary line), the same as the 2026-11-15 baseline. No committed spec covers the rail or the link; the evidence for them is the two harnesses above.

**Not verified:** a real browser on a real phone; WebKit; the admin view-as-customer rail in a browser
(the function's admin path is proven by the S1 harness, Z4); production (needs the S1 SQL there first).
**Its old harness's negative controls** that patch `getTopPicks()` text in `app.js` no longer apply.

### S1 on production, 2026-11-17 (Rick, two passes)

The first pass landed only `get_top_picks()` and its grants: Rick's SMOKE read `rjbookstop` 21 active, all 21
with 20 picks, personal 63, popular 357, new1 0 (exactly S0's prediction) and `comicstore` 1/1, but selecting
either new column returned `42703`. The main block is one transaction, so most likely only part of it was
selected. STEP 0 then read: columns false, guard = the S3b body, function present. A re-run of the main block
failed `42723` (the function exists) and rolled back whole, changing nothing. The file's new COMPLETION
section (C1: the two columns with `IF NOT EXISTS` and the widened guard, no function) then landed; C0 run
afterwards read columns true, guard widened, function present, production. Read-only checks afterwards: both
columns readable, 0 of 37 profiles non-default, an anonymous call refused `42501`. **Not read:** the VERDICT
row itself, so `authenticated_can_execute` is inferred (its GRANT ran in the pass whose REVOKE is confirmed);
the S2 promotion exercises it as a signed-in customer.

**Found on the way, separately (F183):** while confirming this work leaves the arrivals schedule alone, its
first run (15:00 UTC the same day) was found to have failed because `pg_net` was not installed. Fixed the same
day; this week's email sent by hand (9 of 9). See `docs/technical-reference.md` § 13 F183.

### S2 on production, 2026-11-17 (PR #190)

Rick's `/promote-prod`; promotion commit `ab1d222` (parents `033c5c6` main + `012986a` staging tip), merge
`01b1a08`, merged 18:50:44Z by Rick. **Code: `app.js` and `catalog.html` only**; the PR is 10 files, the rest
docs and SQL records. No `config.js`, nothing under `supabase/`.

**Gates.** Step 0: no SQL pending (S1 already on production). The merge RESULT of `app.js` and
`catalog.html` equalled staging's copy (`merge=ours` discarded nothing); every other page identical on both
branches; `config.js` == `origin/main`; `supabase/migrations/` 2 files; GitHub's own file list 10 files,
MERGEABLE. Rick's own look at staging was not reported before the PR opened; the PR body said so.

**Verified after the merge.** On BOTH `pulllist.app` and `rjbookstop.pulllist.app`: `app.js`
(`f095c966fa061938`), `catalog.html` (`9d21ae0624988596`), `config.js`, `mylist`, `arrivals`, `admin`,
`subscriptions`, `settings`, `analytics` and `style.css` byte-identical to `origin/main`, and the two code
hashes equal the bytes staging served when the harnesses and the full suite ran. Markers: `get_top_picks` x2
in `catalog.html` (the call and its comment), `pickOpened` x1 and `getTopPicks` x0 in `app.js`; `config.js`
prod ref x1, staging ref x0. **Write-smoke (Rick): "Top Picks show and Reserved and canceled a title"**, read
back from the production log: a `reserve` at 22:27:34Z and a `cancel` at 22:27:58Z, both on `rjbookstop`.
Since the rail itself is loaded by `get_top_picks()`, his report that it showed is the first production
proof that a signed-in customer can call the function (the grant inferred in the S1 entry above).

**Not verified:** a `pick_opened` event on production (no email carries a pick link yet, so nothing on
production makes one until S5); the rail as an admin viewing as a customer on production; WebKit or a real
phone; whether the reserved title came from a rail card or the grid (the log does not say).

### S3 on staging, 2026-11-17 (`473d98b`, switch fix `8e2da2f`; `account.html`, `app.js`, `style.css`, seven nav pages, `mylist.html`, `privacy.html`)

**What changed.** `account.html` ("My Account", the eighth nav page): name and email read-only; three switches
(new-catalog email, weekly arrivals email, Include Top Picks in my emails) that save as they are switched, straight
to `user_profiles`. The save asks for the row back (`.select('id')`), so a write the server refuses with an empty
answer reverts the switch and says so, instead of reading as success. No switches while an admin views as a customer
(it would be the admin's own row), or for a pending or paused account (the catalog notice stays an account notice,
O1, so a switch there would promise something the emails do not do); a column the profile read does not return hides
only its own row; all three missing shows a message. The nav greeting's name is a link to it, in the desktop bar and
the phone drawer (the same two lines on all seven existing pages). `initNav()` keeps the drawer's name link out of the
active-page loop and marks both links `aria-current` on the page. **The gear opt-out** is `<body data-nav-gear="none">`:
`NavSettingsLink` then renders an empty 44px spacer for everyone, admins included (the plan's "gate it on the page").
**D7:** the arrivals switch left My List; an "Email settings" link to `account.html#email-settings` is in its place
(hidden while viewing as a customer). `privacy.html` has two sentences that are true with S3 alone (the picks and
the email-footer link are not mentioned until S5 makes them true). No SQL: S1 already added the columns and widened
the F182 guard on both environments.

**Verified on the deployed bytes** (served files equal the commit first, three consecutive samples):
- **`playwright/account-s3-verify.mjs` (local-only) 43/43:** the eight pages carry one nav block (2,750 chars) and
  one footer; the page reflects the database (arrivals set OFF beforehand shows OFF); each switch saves and the other
  two are untouched; a reload shows the saved state; the Top Picks hint appears with both emails off and hides when
  one is back on; a PATCH answered with no row, and one answered 500, each revert the switch with an error toast and
  leave the database unchanged; keyboard focus shows a ring on the slider; layout shift 0.0095; all three tracks are
  44x24 on desktop and on a 390 px phone; the name links work (desktop bar and phone drawer, both marked current on the
  page, no page link highlighted, drawer link has no pill or padding and wraps); the gear is an empty 44x44 spacer for
  a customer and an admin on My Account, an admin on Settings still gets the gear link (control), and the logo sits at
  the same x on My Account and the Catalog; My List has no old switch and a working "Email settings" link, hidden while
  viewing as a customer, and the print header still reads the name; pending, paused and view-as-customer show a
  message and no switches; a stripped column fails open for its own row only, all stripped shows the message; signed
  out is sent to sign-in with the page remembered; and **the F182 guard**: the two new columns are accepted from the
  customer's own browser, while `full_name`, `is_admin`, a different `status`, and a mixed write are all refused (403)
  with nothing reaching the row. Teardown re-read 0 leftover profiles.
- **Negative controls, each seen red on the check it targets** (by serving a deliberately broken copy of `/account`;
  the working tree is untouched): `--control=noreadback` fails D5 (the refused write left the switch wrong); 
  `--control=noimpersonation` fails S2; and the page run against the previous staging bytes (before the push) fails
  P1-P3 and cannot load. **D10 (switch width) was seen red on the deployed first build** (tracks 24, 25 and 19 px on
  the phone) and green after the fix.
- **A defect found by LOOKING, not by the harness, and fixed:** a phone screenshot showed the switch tracks squeezed
  to about 24 px with the knob sticking out, because the shared `.toggle-switch` is a flex item beside a wrapping
  description. Fixed page-scoped (`.acct-row .toggle-switch { flex: none; }`, `8e2da2f`); D10 added; the retaken
  screenshot shows round, whole switches. Screenshots of desktop, phone, the open drawer and My List's toolbar were
  inspected.
- **Harness errors of mine, caught and corrected before being believed:** D7 failed because `page.unroute` was given a
  new function each time, so the 500 handler from D6 was still active (fixed with one shared matcher); F4 failed
  because it wrote `status: 'active'` to an account that is already active, a no-op the guard rightly allows (now
  writes a different value).
- **Full suite on the deployed bytes: 170 passed, 1 skipped, 0 failed, 26.8 min, `EXIT=0`** (the log's own summary
  line, not the launcher's notice; the same as the 2026-11-17 baseline). It ran on `473d98b`, before the switch fix,
  which changes only `account.html` (no spec loads that page) plus a comment; the harness above was rerun on the final
  bytes. Spec 18 (the nav) is in that run.

**Not verified:** WebKit or a real phone (Chromium emulation only); the page as a paid versus free tenant's customer
(the shop name in "ask <shop>" comes from `data-tenant-name`); Maintenance Mode on this page (the check is the same
two lines the other customer pages use, not exercised); production; Rick has not looked at it on staging.

**For S4 and S5.** (1) The anonymous preferences page (S4) should follow the same rule as this one: a pending or
paused account sees no switches there either, or S5 must say plainly what the footer link does for them. (2) **The
live Tuesday arrivals email (`notify-arrivals`, line 461) says "Turn it off on My List, next to Email My List".** Once
S3 is on production that still leads to the right place (My List now has an "Email settings" link in that spot), but
the sentence is stale; S5 replaces it with the footer link (D7). (3) `privacy.html` needs the picks and footer-link
sentences when S5 ships; its "Effective October 29, 2026" date was left alone (Rick's call whether two clarifying
sentences move it).

**Promotion.** S3 stands alone (no SQL, no Edge Function); a promotion needs Rick's `/promote-prod`, `app.js` carries
`merge=ours` (assert its merge RESULT), and a write-smoke is warranted: the nav changed on every page and `mylist.html`
changed, though the reserve path did not.

### S4, 2026-11-17: the `email-preferences` function and the no-sign-in page (BUILT AND VERIFIED ON STAGING, `072d9fe`)

**Production untouched.** Edge Function `supabase/functions/email-preferences/index.ts` (new) and the static page
`email-preferences.html` (new, no nav, so the nav sync set stays at eight). No SQL, no `app.js`, `style.css`,
`config.js`, `_headers` or existing page changed.

- **Deployed to staging only,** `--no-verify-jwt` (a NEW function, so there was no live setting to preserve;
  confirmed by behaviour: an unauthenticated call returns the function's own `{"error":"This link is not valid."}`,
  not the gateway's message). `EMAIL_PREFS_SECRET` was generated locally (96 hex characters, never printed), set on
  the staging project with `supabase secrets set`, and saved as `EMAIL_PREFS_SECRET_STAGING` in the scripts `.env`
  (gitignored) so the harness can mint tokens independently. **Production has no secret and no function yet (S6),
  and its value must be different.**
- **As built:** GET reads and changes nothing; a browser navigation (`Accept: text/html`) is redirected to the page
  at `APP_BASE_URL` (fixed destination, parameters re-encoded, not an open redirect); POST JSON sets only the three
  switches (booleans, the three keys, all-or-nothing, 2 KB cap); POST `List-Unsubscribe=One-Click` with `?k=catalog`
  or `?k=arrivals` turns that one email off (`picks` is deliberately not offered; one line to add). Every token
  failure (missing, malformed, wrong signature, another secret, another customer's token, wrong version tag,
  truncated, a customer that no longer exists) is one identical 403. A missing or short (< 32) secret fails closed
  with 503. Nothing is written to `usage_events`.
- **Decisions made while building (mine, defaults, say if you disagree):** (1) the one-click POST is honoured for
  pending and paused accounts too, because a mail client has already told the person they are unsubscribed; the
  page's own switches still follow My Account's rule (O1). This means S5's `notify-customers` must honour
  `email_catalog = false` for **every** recipient, pending and paused included. (2) A browser opening the function's
  own address is sent to the page (the address in `List-Unsubscribe` therefore works for a plain click as well as
  the one-click button). (3) The page is not gated by Maintenance Mode: an opt-out must keep working, and it writes
  three booleans on one profile.
- **Page:** the three switch rows copied from My Account; saves on press and trusts the stored value the server
  read back, not the click (a refused or failed save puts the switch back); a "not valid" message, a "once your
  account is active" message for pending and paused accounts; arriving from an Unsubscribe link (`?k=`) names that
  email and highlights its switch, and changes nothing until it is pressed. `noindex`, `referrer: no-referrer`
  (the address carries the token), no `app.js`, no Supabase client.
- **Verified, two harnesses (both local-only, in the scripts repo's `playwright/` folder):**
  - `email-prefs-s4-logic.mjs`: the REAL function source run in Node against a fake PostgREST (Node 24 strips the
    types; Deno is not installed here). **65/65 checks** (refusals, GET, saves, one-click, account states, failure
    handling) plus three fail-closed secret cases, and **12 deliberately broken copies, each turning its named
    checks red** (token not verified, any key accepted, GET writes, one-click may turn picks off, unknown user
    answered differently, pending may write, short secret accepted, one-click needs no body, no size cap, write
    result not checked, shop name not blanked) and one harmless change that correctly turns nothing red.
  - `email-prefs-s4-verify.mjs`: the DEPLOYED function, the real staging database and the page in Chromium.
    **56/56**, including whole-row comparisons (not just the columns I thought of) for every write that must change
    exactly one column and every write that must change none; tokens minted by an independent HMAC; the redirect
    landing on staging's own page; the function address opened in a browser; a failed save and a lying server both
    leaving the switch on the stored value; no Referer carrying the token to any other origin; phone width with no
    horizontal scroll and 44 x 24 switch tracks; layout shift under 0.05 (0.001 measured). Three page-side controls
    each seen RED on their own check: `--control=trustclick` (F12), `--control=squeeze` (F24, tracks of 25, 26 and
    21 px), `--control=noreserve` (F6b). Teardown re-read: 0 throwaway profiles.
  - Screenshots of the desktop page, the phone page, the phone page arriving from an Unsubscribe link and a pending
    account's page were inspected.
- **My errors, caught before they were believed:** the first refusal list used a destructuring default, so "no
  token" would have been refilled with a good one (found by reading, before the first run); a Playwright route
  callback that threw inside its own event loop skipped my teardown and left five `pw-eprefs-*` users, which I
  deleted after listing them by prefix, and the harness now removes them on any uncaught exception; a first control
  (`noreserve`) turned nothing red because the first-paint reservation does not affect layout shift, so the check
  was replaced with one that holds the settings request open and asserts the switches stay hidden (F6b); and the
  first referrer check failed because Google's font files carry the stylesheet's address as Referer, so it now asks
  the question that matters (nothing carries this page's address or token).
- **One failure I could not explain:** in the run with `--control=squeeze`, check A3 (a write with a bad token is
  refused and the row is untouched) failed once; it passed in the four full runs straight after and in every later
  run, and the check now prints the statuses and any changed column if it fails again. Probably a transient
  platform response, but not established.
- **Not verified:** a real inbox and a real mail client's one-click POST (the S5 gate: RFC 8058 specifies a form post
  with that exact body, which is what the harness sends, but no real mail client has been observed doing it); the
  fail-closed secret check live (it was proved against the real source locally, and staging's secret was not
  disturbed to test it); production, including that its `APP_BASE_URL` is `https://pulllist.app` (staging's was
  confirmed to be the staging site by check B5); Safari or a real phone; the full Playwright suite (not run: no
  existing page, script or style changed, and no spec loads the new page).

**For S5.** (1) Copy the token block (`BEGIN` / `END` markers in the function) byte-identically into
`notify-customers` and `notify-arrivals` and add a grep gate; mint with the same `EMAIL_PREFS_SECRET`. (2) The
footer link goes to the **page** (`<base>/email-preferences.html?u=<id>&s=<token>`); the `List-Unsubscribe` header
carries the **function** address (`<SUPABASE_URL>/functions/v1/email-preferences?u=&s=&k=catalog` or `k=arrivals`)
and `List-Unsubscribe-Post: List-Unsubscribe=One-Click`. Resend's `headers` field must be confirmed to carry both
before building. (3) Honour `email_catalog = false` for every recipient, because one-click is honoured for every
account state. (4) Replace the arrivals email's "Turn it off on My List, next to Email My List" line (D7).
(5) `privacy.html` still needs the picks and footer-link sentences.

**For S6.** Set a different `EMAIL_PREFS_SECRET` on production first, deploy `email-preferences` with
`--no-verify-jwt` and read it back by behaviour, and confirm the redirect check (B5's twin) lands on
`https://pulllist.app`. The page ships with the client PR; it needs nothing but `config.js`.

**Finding-ID disposition, in words: no finding ID consumed (feature build, not a defect). F184 remains the next
free finding ID.**

### S5, 2026-11-18: picks, the settings link and List-Unsubscribe in the two mail functions (BUILT AND VERIFIED ON STAGING, `c18b865`, `7525dc3`, `33e067a`)

**Production untouched.** `notify-customers` and `notify-arrivals` are deployed to staging only (`--no-verify-jwt`,
read by behaviour before and after: both answer with their own error body, so unchanged; deployed artifacts hashed
equal to the committed source). Also `privacy.html` (one sentence on Top Picks and the opt-out link). No SQL, no
`app.js`, `config.js` or other page.

- **What each email now does.** A "Top picks for you" section after the email's own purpose: up to 4 picks read per
  recipient from `get_top_picks()` and then `catalog`, each a cover (when it has one), title, publisher and price, and a
  Reserve button to `catalog.html?pick=<id>&ref=email-catalog` (arrivals: `email-arrivals`); the caption uses the
  rail's wording. Only for an active, non-paper account with Top Picks on (O1: pending and paused accounts keep the
  catalog notice, without picks). An "Email settings or unsubscribe" footer link and `List-Unsubscribe` +
  `List-Unsubscribe-Post: List-Unsubscribe=One-Click` headers go on **every** send, signed with `EMAIL_PREFS_SECRET`.
  `notify-customers` skips anyone with `email_catalog = false`, whatever their account state (S4's decision), and
  reports `with_picks` and `skipped_catalog_off`; `notify-arrivals` reports `with_picks` (so the cron's logged
  response shows whether picks went out). The arrivals email's stale "Turn it off on My List" sentence is gone.
- **Safe by construction.** The token block is byte-identical in `email-preferences`, `notify-customers` and
  `notify-arrivals`, and the picks block in the two mail functions (the harness compares them by hash; compare again
  after any edit). With no `EMAIL_PREFS_SECRET` (or under 32 characters) the email goes out **exactly as before S5**
  (proved byte for byte against the pre-S5 sources), except that the arrivals email then says "Open My Account (your
  name at the top of any page) and switch it off". Any failure reading picks sends the email without them. A free
  shop with no `tenants.location` gets its arrivals email without picks (not skipped); `notify-customers` still
  refuses without one (422). Pick titles and covers are escaped for text and for attributes, and a cover address that
  is not plain http(s) is dropped.
- **Deviation from § 3.5, mine, say if you disagree:** links use `APP_BASE_URL` (what both functions already used),
  not the shop's own address for a paid shop. Reason: staging's founding shop is `pro` but its hostname is not
  provisioned (F145), so a per-shop link would be dead there; production's founding shop would link to its own
  hostname. It can be added in S6 if you want it.
- **Verified:**
  - `email-prefs-s5-logic.mjs` (local-only): the REAL sources against a fake Supabase and a fake Resend, with the
    PRE-S5 sources (`b00bbfc`) run in the same worlds as a regression anchor. notify-customers 22/22, notify-arrivals
    15/15, the shared blocks identical, the pre-S5 sources shown to FAIL the new checks, and 21 deliberately broken
    copies each turning its named checks red (catalog switch ignored, picks to pending accounts, picks switch ignored,
    no footer link, no header, titles not escaped, any cover scheme allowed, short secret accepted, more than four
    picks, a link minted for the wrong customer, a picks failure stopping the email, picks counted wrongly, no address
    rule, no address line, stale sentence kept, dry run reading picks).
  - `email-prefs-s5-staging.mjs` (local-only): the DEPLOYED functions, the real database, the real `get_top_picks()`
    and the **real Resend API**, for a throwaway free shop whose customers are Resend's own `delivered+...@resend.dev`
    test addresses (nothing reaches a real inbox). **14/14, twice** (before and after the layout fix below): the real
    RPC returns picks and the columns the email reads carry data; the catalog email goes to the five customers who want
    it (the one with the catalog email off is skipped), none rejected by Resend, picks in exactly two; the arrivals
    email goes to four, a notice recorded for each and for no one else, picks in three; a second run sends nothing; a
    free shop with no address still gets all four emails without picks; `notify-customers` still refuses it (422); a
    paid shop gets picks again; the one-click address the email carries turns the arrivals email off for that
    customer and the next run skips them. Teardown re-read: none left. **Timing measured:** 0.7 to 1.0 s per recipient
    in 4 to 5 recipient runs, picks included, so 90 recipients (the arrivals cap, and Resend's own 100 a day) is
    roughly 60 to 90 s; I believe the Edge limit on this plan is about 150 s but did not re-check it.
  - **Rendered, and looked at:** the real email HTML in Chromium at 760 and 390 px, six variants (catalog and
    arrivals, free and paid, with and without picks), real cover art. **A defect found this way, not by any check:** a
    pick with no cover had two table cells where the others have three, so its text column collapsed and its Reserve
    button sat in a different place. Fixed (`33e067a`, in the shared block, both files), and a re-render shows aligned
    rows and no horizontal overflow on a phone.
- **Not verified, stated plainly:** a **real inbox** (that is the S5 gate's last step and is Rick's: whether DKIM
  signs the `List-Unsubscribe` headers, whether Gmail offers its Unsubscribe button, inbox versus spam, F152), how
  Outlook and Gmail render the layout (Chromium only), the no-secret path live (proved only against the fake
  backend), 100 or more recipients, and production (secret, deploy, `APP_BASE_URL`). About 40 emails went to Resend
  test addresses across the runs, against the shared 100-a-day limit (F148).
- **Follow-up, same day (Rick's report: a Top Pick link from the Resend dashboard preview "shows the full catalog",
  not one title).** Cause, read from data: that was one of the live gate's emails (`email-prefs-s5-staging.mjs`,
  customer "S5 r6", covers `https://example.com/s5-cover.jpg`), whose throwaway shop the gate tears down when it
  ends. A read of staging found none of its four pick titles and no recipient profile, so the page did exactly what
  it is built to do for a title this shop cannot see: the full catalog and a short "That title is no longer in the
  catalog." message. **Not a defect in the link.** The Resend dashboard keeps these emails after the data is gone, so
  its previews of gate emails can never open a title; only an email from `email-prefs-s5-inbox.mjs` (its shop stays
  until `--teardown`) can. The same session ran the link as the email writes it (`catalog.html?pick=<id>&ref=email-arrivals`,
  which redirects to `/catalog?...` and keeps the query, read from the response) with a local-only harness,
  `top-picks-email-link-verify.mjs`: **10/10, twice, against the deployed staging bytes** (a real throwaway customer,
  a real pick from `get_top_picks()`): signed in, the title's modal opens, the address is cleaned, one `pick_opened`
  event (source `email-arrivals`) is logged and nothing is reserved; **signed out, through the real sign-in form
  (not an injected session), the customer lands back on that title**; a deleted title and another shop's title (read
  as the customer: 0 rows) each leave the full catalog with the message and log nothing; an admin sees the modal and
  logs nothing. **Gaps in my own earlier record, stated:** S2's harness only requested `/catalog?pick=` (never
  `catalog.html?...`, the form the email carries) and faked the sign-in with an injected session. Two of this
  harness's first-run failures were its own timing (it read the page before the handler had run, and E4b assumed one
  event where E1 and E2b had each logged one); the product behaved the same on every run. **Still not verified:** a
  link followed from a real mail client's inbox, and a customer on a phone through the sign-in form. **One thing a
  customer can hit that Rick's report shows is easy to miss:** an email link to a title the NEXT catalog month's
  import has purged (the import deletes unreserved past-month rows) gets the same quiet message, so an old email's
  Reserve button can land on the plain catalog. Unfiled, Rick's call.
- **Rick's real-inbox check, 2026-11-18 (`email-prefs-s5-inbox.mjs --to`, one customer, both emails through the real
  functions and the real Resend, `with_picks` 1 each).** His report: he followed the link as the throwaway customer
  "and it performs as expected". **That is his report; he pasted no headers**, so DKIM over the new
  `List-Unsubscribe` headers, inbox versus spam (F152), and Gmail's Unsubscribe button are NOT confirmed, and his
  words do not say which of the footer link, the switches and the covers he exercised. Two things his test showed:
  (1) signed in as his own Ray & Judy's account, the throwaway shop's title is invisible (RLS), so the link shows the
  full catalog and the message; the customer must arrive as the recipient. (2) **Signed out, the link lands on the
  platform marketing page** (`data-front-door="apex"`, the sign-in form hidden behind a small Sign in button, the
  return path kept). Measured read-only the same day: `rjbookstop.pulllist.app` shows the shop's sign-in form at
  once (`data-front-door="tenant"`), `pulllist.app` shows the marketing page. Signing in from that page still lands
  on the title (verified in a real browser as the throwaway customer, his exact link). **This is the cost of my
  deviation from § 3.5 (links use `APP_BASE_URL`, not the shop's own address);** the existing "View catalog" and
  "See My List" links already land the same way. **Recommended for S6, not built, Rick's call:** a paid shop's links
  use its own address (`<slug>.pulllist.app`, the `Tier.publicUrl()` convention), a free shop's stay on the apex (S1a),
  gated by a production-only setting because no staging shop has a provisioned address (F145), so staging can prove
  only how the links are BUILT, not the branded landing.
- **Observed, not fixed, ~~not filed~~ FILED AS F184 later the same day:** `notify-customers` builds its email lookup from one
  `auth/v1/admin/users?per_page=1000` read. That list is every user of the project across all tenants, newest first, so
  once a project holds more than 1000 users the OLDEST customers get no catalog email and nothing says so. Staging held
  **999** users on 2026-11-18. The seventh instance of the unbounded-read class (F82, F113, F139, F140, F156, F162);
  `notify-arrivals` looks each user up individually and is not affected. Your call whether to file it.

**Rick's real-inbox check (headers only).** `node email-prefs-s5-inbox.mjs --to you+s5@example.com` (use an address
that is NOT already a staging account; a plus address works with most providers; add `--paid` to see the paid layout)
creates a throwaway shop with one customer at that address and sends both emails through the real functions. It
prints a sign-in (that customer's address and a random password) so the Reserve links can be followed.
`node email-prefs-s5-inbox.mjs --teardown` removes everything. Check: (1) both emails arrive, and where (inbox or
spam); (2) in "Show original": `From`, `Subject`, `List-Unsubscribe`, `List-Unsubscribe-Post` and the `dkim=`, `spf=`,
`dmarc=` results, pasting **headers only** with any link replaced by `[link]` (the settings link carries a token that
never expires); (3) the picks section and the footer link; (4) Reserve opens the title after signing in; (5) the
footer link opens the settings page and a switch saves; (6) if your mail client shows an Unsubscribe button, that it
turns that one email off.

**For S6.** Production needs, in this order: a DIFFERENT `EMAIL_PREFS_SECRET`; `APP_BASE_URL` confirmed to be
`https://pulllist.app` (the S4 redirect check lands on it); the client PR (S3 My Account, the nav greeting link, the
`email-preferences.html` page, `privacy.html`; `app.js` carries `merge=ours`, so assert its merge result, and the
nav changed on every page, so run a write-smoke); then `email-preferences`, `notify-customers` and `notify-arrivals`
deployed `--no-verify-jwt` (read the two existing ones' live setting first). Two timing facts: the arrivals cron fires
Tuesdays 15:00 UTC, so deploying before the 2026-11-24 run means that run (F183's first unattended one) is also the
first send with picks, and the December catalog import will be the first catalog email with them. `privacy.html`'s
effective date (October 29, 2026) is left unchanged on purpose; it should move on the day this reaches production.

**Finding-ID disposition, in words: no finding ID consumed (feature build, not a defect). F184 remains the next free
finding ID.** *(Written 2026-11-18; F184 and F185 were filed later the same day, see below, and F186 is now next free.)*

### S5 follow-ups, 2026-11-18 (later): Rick's inbox result, link addresses built, F184 and F185 filed

**Rick's real-inbox result (his report).** The email **landed in the Gmail Inbox, not spam**, and the "Email settings or
unsubscribe" link was present. **Not confirmed: DKIM over the new `List-Unsubscribe` headers** (he asked how to check).
How: open the message in Gmail, three-dot menu, **Show original**. The summary at the top gives SPF, DKIM and DMARC. Then
find the `DKIM-Signature:` header whose `d=` is `pulllist.app` and read its `h=` list of signed headers: RFC 8058 wants
`list-unsubscribe` and `list-unsubscribe-post` in it. Paste only the `d=`, `s=` and `h=` parts, never a link.

**Rick's decisions on my four items:** (1) the throwaway shop, titles, customer and login are removed (his
`--teardown`; a fresh read of staging 2026-11-18 found none left: 0 `S5` tenants, 0 profiles for that address, 0 `S5`
titles, 0 auth users); (2) build the signed-out landing: below; (3) prepare S6: below; (4) file the two unfiled
observations: **F184** and **F185** (`technical-reference.md` § 13). **Reading of "file this", mine:** the pair my item 4
listed (the purged-title link and the 1,000-user lookup); say so if he meant something else.

**Link addresses, built (`baedd98`, `notify-customers` and `notify-arrivals`; § 3.5's own line, "links use the shop's
own address for a paid shop and the apex otherwise", which my S5 build had deliberately not followed).** A signed-out
customer who follows a link to the shared apex lands on the platform's marketing page; a shop's own address shows the
shop's sign-in at once (measured read-only on `rjbookstop.pulllist.app` and `pulllist.app`). A paid shop's app links
(Browse the Catalog, See My List, every pick) now use `https://<slug>.pulllist.app`, **only** where `APP_BASE_URL`'s host
is exactly `pulllist.app` and the slug is a valid DNS label; a free shop stays on `APP_BASE_URL` (S1a), staging is
unchanged (no shop there has a provisioned address, F145, so a per-shop link would be dead), and the settings-page link
and the List-Unsubscribe address are unchanged. **`EMAIL_SHOP_LINKS=off` reverts it with no deploy.** The block is
byte-identical in both functions (hash-gated by the harness); the tenant-identity block shared by six functions is
untouched. `notify-customers` reads the shop's slug with one extra query, only for a paid shop; `notify-arrivals` already
had it. **Verified:** `email-prefs-s5-logic.mjs` now has a link-address suite, **16/16**, and the earlier suites are
unchanged (22/22, 15/15, the pre-S5 regression anchor); **35 deliberately broken copies each turn their named checks
red**. Two of those first stayed green and were corrected rather than accepted: M22 did not fail because
`notify-customers` guards a free shop twice (the block's `isPaid` test, and no slug read at all), so the mutation now
removes both layers, and the single-layer copy is kept as an "informational, must stay green" line; M29 never reached the
`catch` it breaks because my fake database returned an HTTP error and not a thrown request, so the fake now has a
throwing mode. Deployed to staging only, `verify_jwt` read by behaviour before and after (OFF, unchanged), deployed
artifacts hash-equal to the commit (`5f332d7d…`, `28f9b2a2…`). **Not verified, stated plainly:** the branded landing
itself can only be seen on a provisioned hostname, so staging proves only how the links are BUILT; the first look at the
real thing is production after S6. No staging email was sent for this change (Resend's 100 a day: 42 at last report).
**A tradeoff, for Rick:** a browser keeps its sign-in per address, so a customer who normally signs in at `pulllist.app`
will be asked to sign in once at `rjbookstop.pulllist.app` the first time they follow one of these links, and not again on
that device; customers who use the printed address (`rjbookstop.pulllist.app`) already have a session there. It is the
price of the branded landing; the off switch undoes it.

**Filed:** **F184** (`notify-customers` reads emails from one page of 1,000 users across every shop; production holds 37
profiles) and **F185** (an email link to a title that is no longer in the catalog lands on the plain catalog with a brief
message). **F186 is next free.**

### S6, production rollout: PREPARED 2026-11-18, NOT STARTED (needs Rick's explicit go)

**Read-only facts gathered 2026-11-18.** (1) Production's secrets, by name and digest (`supabase secrets list --project-ref
plgegklqtdjxeglvyjte`, values never shown): `APP_BASE_URL`, `ARRIVALS_CRON_SECRET`, `FOUNDING_TENANT_ID`,
`MAIL_FROM_EMAIL`, `MAIL_FROM_NAME`, `RESEND_API_KEY` are present; **`EMAIL_PREFS_SECRET` and `EMAIL_SHOP_LINKS` are not.**
(2) **`APP_BASE_URL`'s digest equals the SHA-256 of `https://pulllist.app`** (checked against that string, with and
without a trailing slash and two other candidates), so it IS the production apex and the shop-link rule will fire there.
(3) `/promote-prod` step 0 lists two files, `2026-11-14-s3b-notify-arrivals-cron.sql` and
`2026-11-14-s5-paper-claim-codes.sql`: **both are `prod=APPLIED`**; the gate reads only a file's first STATUS line and
their `prod=` sits on a continuation line, so these are false alarms, not blockers. No unapplied SQL. (4) What staging
would carry to production (raw `main..staging`, code only, 12 commits ahead): `account.html` and `email-preferences.html`
(new), `privacy.html`, `app.js`, `style.css`, the nav pages (`admin`, `analytics`, `arrivals`, `catalog`, `mylist`,
`settings`, `subscriptions`: the greeting link), and the sources of `email-preferences` (new), `notify-customers` and
`notify-arrivals`; plus docs. The raw diff also shows `config.js` (per-branch, restored to `origin/main`'s at step 2) and
`supabase/migrations/` as deleted (F125, never touch): neither belongs in the PR.

**Timing, Rick's choice.** The arrivals cron fires **Tuesdays 15:00 UTC** (next: Tue 2026-11-24), and Tue 24 Nov is also
the first unattended run since F183. **Option 1 (matches "next week we can include these changes"):** do steps 1-5 by
Mon 23 Nov, set the secret (step 6) that evening after the zero-send checks, so Tuesday's run is the first with picks;
rollback up to 15:00 UTC Tuesday is one command (unset the secret). **Option 2:** do steps 1-5 now, leave the secret unset
(emails then go out as before S5 apart from the shop-address links and the one replaced arrivals sentence), set it after
Tuesday's run is read clean; the first picks then go out on Tue 1 Dec or with the December catalog email. Resend's 100 a
day is shared with staging: do not run staging gates on the day.

**Steps (each production step is Rick's call; the agent prepares and verifies).**
1. **Privacy date.** On `staging`, set `privacy.html`'s effective date to the day of promotion (it reads October 29, 2026);
   commit, push, confirm served.
2. **Client PR, `/promote-prod` steps 0-4.** Branch from `origin/main` (`git checkout -B feat/top-picks-emails-prod
   origin/main`), `git merge origin/staging --no-commit --no-ff`, `git checkout origin/main -- config.js`. **`app.js` carries
   `merge=ours`: assert the merge RESULT equals staging's copy** (the driver has dropped it three times). Branch-tree
   assertions: `supabase/migrations/` still 2 files, `config.js` carries `plgegklqtdjxeglvyjte`, the PR file list read on
   GitHub equals the scope above (no `config.js`, nothing under `supabase/migrations/`).
3. **After Rick merges:** served bytes on BOTH `pulllist.app` and `rjbookstop.pulllist.app` byte-identical to `origin/main`
   for `app.js`, `account.html`, `email-preferences.html`, `privacy.html`, `style.css` and the nav pages, `config.js` prod
   ref x1 and staging ref x0; markers named from the diff at the time (the nav name link in `app.js`, the switch rows in
   `account.html`). **Write-smoke (the nav changed on every page): Rick reserves and cancels one title on production;
   read back the `reserve` and `cancel` events and the `tenant_id`.** Note that `account.html` and `email-preferences.html`
   are live from here, harmlessly: the page needs a token that does not yet exist.
4. **Rollback copies first.** Download the CURRENT production `notify-customers` and `notify-arrivals` (`supabase functions
   download <name> --project-ref plgegklqtdjxeglvyjte --workdir <empty scratch dir>`) and keep them until the rollout is
   closed out.
5. **Functions, from a worktree of `origin/main`** (Edge Functions deploy from the CLI tree, not from the merge): read the
   live `verify_jwt` of `notify-customers` and `notify-arrivals` by behaviour (their own error body = OFF) before and after;
   deploy `email-preferences` (new), `notify-customers` and `notify-arrivals` with `--no-verify-jwt`; download each artifact
   and hash it equal to `origin/main`'s source. **Zero-send checks, no secret yet:** `email-preferences` answers 503 (no
   secret, fails closed); `notify-arrivals` dry run through the job's own stored command with `{"dry_run": true}`
   (Rick-run SQL, as in F183) returns 200 with `would_email` and sends nothing.
6. **The secret (switches the emails on).** Generate it locally without printing it (PowerShell: 32 bytes from
   `[Security.Cryptography.RandomNumberGenerator]` as hex), `supabase secrets set EMAIL_PREFS_SECRET=... --project-ref
   plgegklqtdjxeglvyjte`, keep a copy in the scripts `.env` as `EMAIL_PREFS_SECRET_PROD` (never in a repo or in chat), and
   confirm by `supabase secrets list` that its digest differs from staging's. **Losing or changing it later breaks every
   link already sent**, so it is not rotated casually.
7. **Checks with Rick's own production account only (no customer data touched):** `email-preferences` with a bad token is 403;
   with a token minted for his own admin account the GET returns his three switches, a POST of the same values reads back
   unchanged, and the page `https://pulllist.app/email-preferences.html?u=...&s=...` opens in a browser.
8. **First real send (Tue 24 Nov under Option 1).** Read the run: `net._http_response` for the job's call (the F183 query)
   shows `sent`, `failed` and **`with_picks`**; `arrival_notices` gains one row per recipient; Resend's dashboard shows no
   bounces or complaints for that batch. Ask one real recipient, if Rick can, whether the Reserve link opened the title.
9. **Close out** (`/promote-prod` step 6): a "Last completed work" entry in `CLAUDE.md` with both SHAs and the PR, what was
   verified and how, and the finding-ID disposition in words (expected: no finding ID consumed, a feature build).

**Rollback, cheapest first.** (a) `supabase secrets unset EMAIL_PREFS_SECRET --project-ref plgegklqtdjxeglvyjte`: the next
send is the pre-S5 email (no picks, link or header), proven byte for byte by the harness. (b) `EMAIL_SHOP_LINKS=off`:
links back on the shared address. (c) Redeploy the two saved function copies from step 4. (d) Revert the client PR (the
pages are inert without the secret). Emails already sent cannot be recalled.

**Known gaps going in:** the first production picks email goes to real customers (no safe way to send one production email
to one person: both functions send to the whole eligible list). **Admins:** `notify-customers` excludes them
(`is_admin=eq.false`, line 409), but `notify-arrivals` does NOT (its eligibility is active, not paper, opted in), so
Rick's own admin account receives the arrivals email if it holds a reservation that matches that week's shipment. Whether
it does is not established; if it does, that copy is the production check for step 8 (headers only). DKIM over the new headers is
unconfirmed (Rick's Show-original check above); O2 (whether a subscribed series is excluded from picks) is still unbuilt;
F184 and F185 are open and not blockers (production holds 37 profiles).

### S6 on production, 2026-11-21 (runbook steps 1 to 5 DONE; the secret, step 6, is NOT set)

- **Step 1 (privacy date):** committed on staging as `ebae078` ("Effective November 18, 2026"), the day the PR was cut. **It went live on 2026-11-21** (the merge was 2026-11-22T00:29:19Z, Rick's evening), so the date reads three days early; Rick's call whether to correct it in the next promotion.
- **Step 2 (client PR):** PR #191, branch `feat/top-picks-emails-prod` (`d84e610`, parents `01b1a08` main and `ebae078` staging tip), 18 files read on GitHub, merge result == staging's copy for 15 code files (`app.js` included), `config.js` == `origin/main`, migrations 2 files, **full suite 170 passed, 1 skipped, 0 failed, 28.4 min on the deployed staging bytes**. Merged by Rick as `b6edb5d`.
- **Step 3 (after merge):** served bytes on both hostnames, 12 of 13 files byte-identical to `origin/main`, `privacy.html` equal after Cloudflare's `mailto:` rewrite (diffed line by line), `config.js` prod ref x1 and staging ref x0, `account.html` and `email-preferences.html` 200. **Write-smoke (Rick: "Smoke is green"), read back from the production log:** `reserve` 00:32:16Z and `cancel` 00:32:27Z, `rjbookstop`, IMMORTAL SOLDIERS #1 COVER A.
- **Step 4 (rollback copies):** the two existing functions as production ran them, downloaded before the deploy and kept in the session scratchpad only; their hashes (`9ef4e9e7f0e1562f`, `086469e6018799d7`) equal `01b1a08`'s sources, so the real rollback copy is `git show 01b1a08:supabase/functions/<name>/index.ts`.
- **Step 5 (functions):** `email-preferences` (new), `notify-customers`, `notify-arrivals`, deployed from a worktree of `origin/main` with `--no-verify-jwt`. `verify_jwt` read by behaviour before and after: both existing functions answer with their own error body (OFF), unchanged. Downloaded artifacts hash-equal to source (`cf3bab7735115905`, `5f332d7de40804a5`, `28f9b2a20f19f5db`). **`email-preferences` with no secret answers 503 to a GET, an empty POST and a POST with a made-up token: fails closed, accepts nothing (read live).**
- **Not yet done:** the zero-send dry run of `notify-arrivals` through the job's own command (Rick-run SQL, `docs/sql/2026-11-17-f183-pg-net-arrivals-cron-fix.sql` STEP 4; `would_email` is expected to be 0 or a handful, because the 9 eligible customers were notified for the week of 2026-11-16 on 2026-11-17 and a notified customer is excluded; what matters is 200, `timed_out` false, `dry_run` true); the secret; step 7 (Rick's own account); step 8 (the first real send, Tue 2026-11-24 15:00 UTC).
- **State of the emails right now:** unchanged except two things that take effect at the next send even with no secret: a paid shop's app links use `<slug>.pulllist.app`, and the arrivals email's stale sentence reads "Open My Account ... and switch it off". Nothing else (no picks, settings link or header) until the secret is set.

### S6 readiness, 2026-11-22 (Sun evening ET; the secret is generated locally, NOT set on production)

Read-only unless stated. Production was not written.

- **Production state, re-read:** `supabase secrets list` shows no `EMAIL_PREFS_SECRET` and no `EMAIL_SHOP_LINKS`; `APP_BASE_URL`'s digest still equals the SHA-256 of `https://pulllist.app` (`c413bbb560a71d9f`). The three deployed functions, downloaded again, hash equal to `origin/main` and to `origin/staging` and to the 2026-11-21 deploy (`cf3bab7735115905`, `5f332d7de40804a5`, `28f9b2a20f19f5db`), so nothing was redeployed since. `email-preferences` with no token answers 503 to GET and POST; `account.html` and `email-preferences.html` answer 200.
- **The picks call works for the service role on production** (never exercised there before; S2 proved only a signed-in customer's call): a service-role POST to `rpc/get_top_picks` for the founding tenant's one admin account returned HTTP 200 with 4 rows, tiers personal, popular, personal, popular. Before this, a missing grant would have meant Tuesday's email going out with no picks and no error (`fetchPicks` returns `[]` on any failure).
- **Forecast of Tue 2026-11-24's run**, read at 02:33 UTC Monday with `notify-arrivals`' own rules (shipment rows for the week, `arrivals_this_week_digest()`, active non-paper opted-in profiles, `arrival_notices` exclusion, at least one available title, `email_picks`, then `get_top_picks()` per recipient). Counts only: `comicstore` skipped (0 shipment rows); `rjbookstop` 160 digest rows, 18 customers matched, 0 already notified, **would email 10, all 10 with picks on, all 10 would get picks**, and **the founding tenant's admin account (Rick's) is one of the 10**, so his own copy is step 8's production check. Reservations made or cancelled before Tuesday can move these numbers.
- **The secret is generated** (32 random bytes, 64 hex characters) and stored in the scripts `.env` as `EMAIL_PREFS_SECRET_PROD`; never printed. Its digest (`67ee22ee8c956bdf`) differs from staging's (`c3e10ad1f1be8a53`). `.env` is untracked.
- **Step 6 script:** `playwright/email-prefs-s6-secret.mjs` (scripts folder, local-only). No flag = check only; `--set` hands the value to `supabase secrets set` through a temporary `--env-file` that is deleted in `finally`, then reads the digest back and refuses if production already holds a different value; `--unset` is rollback (a). Check mode run: all checks pass, production "not set".
- **Step 7 script:** `playwright/email-prefs-s6-prod-check.mjs` (local-only). Production only, the founding tenant's single admin account only (stops if there is not exactly one), token minted locally and never printed. `--before`: every call 503, row unchanged. No flag: malformed, wrong-secret, staging-secret, wrong-user and no-account tokens all 403; GET 200 with the shop's name and the three stored switches; a browser navigation 302s to `https://pulllist.app/email-preferences.html`; a POST of the account's own current values reads back the same and the whole row is unchanged; the page in Chromium shows the stored switches, saves nothing on load, sends no Referer carrying the token. **Rehearsed on staging** (`--staging`, throwaway admin, torn down, profiles 0, auth 404): 15/15. **Negative control** `--control=wrongsecret`: exactly G1, G3, W1 and P1 red. **Production `--before` run: 3/3** (503 with a correctly minted token, row unchanged).
- **Next, in order:** (1) Rick runs the dry run, `docs/sql/2026-11-17-f183-pg-net-arrivals-cron-fix.sql` STEP 4 and its read, any time before Tuesday (it previews the 11-23 week now): expect 200, `timed_out` false, `dry_run` true, `would_email` 10 or close, `by_shop` "rjbookstop: 10 | comicstore: 0 (skipped: ...)". The dry run reports no picks count; that is in the forecast above. (2) With Rick's go: `node email-prefs-s6-secret.mjs --set`, then `node email-prefs-s6-prod-check.mjs` (expect all pass). (3) Tue 2026-11-24 after 15:05 UTC, the read below. **`net._http_response` keeps rows only about 6 hours (pg_net's default TTL), so read it by about 21:00 UTC (4 PM ET).** (4) Rick's own copy: Gmail "Show original", headers only, for DKIM over `List-Unsubscribe`, plus whether Gmail shows its Unsubscribe link.
- **Rollback before Tuesday 15:00 UTC:** `node email-prefs-s6-secret.mjs --unset`; the next send is then the pre-S5 email. After a send, links in sent emails stop working if the secret is removed or changed.
- **Heads-up, not a blocker:** once the secret is set, the December new-month catalog email (`notify-customers`, sent when the import's Step 7 prompt is answered `y`) also carries picks and the settings link: the first production run of that function's S5 path. Resend's 100 a day is shared with staging, so run no staging mail gates on Tuesday or on the import day.

**Tuesday's read (Rick, production SQL Editor, after 15:05 UTC, counts only):**

```sql
SELECT d.status, d.start_time, d.end_time, left(d.return_message, 120) AS cron_message
  FROM cron.job_run_details d JOIN cron.job j ON j.jobid = d.jobid
 WHERE j.jobname = 'notify-arrivals-weekly'
 ORDER BY d.start_time DESC LIMIT 1;

SELECT r.status_code, r.timed_out, r.error_msg, r.created,
       CASE WHEN r.content LIKE '{%' THEN (r.content::jsonb) ->> 'sent' END       AS sent,
       CASE WHEN r.content LIKE '{%' THEN (r.content::jsonb) ->> 'with_picks' END AS with_picks,
       CASE WHEN r.content LIKE '{%' THEN (r.content::jsonb) ->> 'failed' END     AS failed,
       (SELECT count(*) FROM public.arrival_notices
         WHERE week_start = DATE '2026-11-23')                                     AS notices_this_week
  FROM net._http_response r
 WHERE r.created >= TIMESTAMPTZ '2026-11-24 15:00:00+00'
 ORDER BY r.created ASC LIMIT 1;
```

Expected: the cron row `succeeded`; status_code 200, timed_out false, sent about 10, with_picks equal to sent (or close), failed 0, notices_this_week equal to sent. If timed_out is true but notices_this_week equals sent, the emails went and only the wait ran out (60 s). If no `_http_response` row exists, `arrival_notices` (permanent) and the function log ("notify-arrivals: N sent (M with picks)") still answer.

Gate scheduled (2026-11-22): the arrivals job fires Tue 2026-11-24 15:00 UTC and its response row expires about 6 hours later; reminder: cloud routine `trig_01QEWtZeoeGtBi5bsfzPoUBu` (one-shot, reminds only, no connectors) and Google Calendar event `eeb22rhnegi5j0a9ek8089qcuo`, both 10:30 AM ET (15:30 UTC), popup at the time and email 30 minutes before.
