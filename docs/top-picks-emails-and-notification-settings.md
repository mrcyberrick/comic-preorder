# Top Picks: smarter picks, picks in emails, and a notification settings page

**STATUS:** IN PROGRESS — S0 DONE; S1 and S2 DONE ON STAGING 2026-11-17 (S1 SQL applied by Rick, parity harness 109/0; S2 `4a2434c`, harnesses 19/19 and 46/46, full suite 170/1/0); production untouched (S1 SQL PENDING there); S3-S6 not started (§ 6) · planned 2026-11-17 · every decision D1-D10 and O1 answered by Rick 2026-11-17 (D6, D9, D10: "defaults"); O2 open · staging=— · prod=— · PR=— · findings=— (no ID consumed; F183 next free)

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
