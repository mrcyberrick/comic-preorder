# Top Picks: smarter picks, picks in emails, and a notification settings page

**STATUS:** PLANNED, NOT STARTED · planned 2026-11-17 · D1-D3 answered by Rick 2026-11-17, D4-D10 proposed defaults awaiting his read · staging=— · prod=— · PR=— · findings=— (no ID consumed; F183 next free)

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
So request (2) already holds for the exact row; the gap is a **different row of the same issue**, and
the emails, which do not exist yet, must apply the same rule server-side.

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
| D3 | **Priority: personal over store, popular over New #1.** New #1 is the default only when no history can be used. Read as: personal and popular keep alternating, personal first (Rick's 2026-10-09 rule, unchanged); **New #1s fill only the slots the two history tiers leave empty**, so they appear for a shop with no reservation history at all, and as a top-up when history runs short (late in the month, when most history titles are past FOC). | **Rick, 2026-11-17** (the alternation and the top-up are this plan's reading of his answer; correct here if not) |
| D4 | "Already reserved" widens from the exact row to **the same issue**: same `series_name` + distributor + the `#N` parsed from the title, in the current month. A title with no `#N` (a trade, a one-off) falls back to the exact row. A second issue of the same series in the same month (a twice-monthly book) is still a pick. | proposed |
| D5 | **New #1 rule:** standard cover; format `Periodical` or `Comic Book`; `#1` in the title, not followed by a digit; title does not match `FACSIMILE`, `BUNDLE`, `(NET)`, a leading `DF`, `SIGNED`, `BLANK`, `VIRGIN`, `PTG`/`PRINTING`; FOC not passed; passes the store's visibility settings; one per series. One-shots count. | proposed |
| D6 | **Emails carry 4 picks**, only for an account that is active, not paper, and has Top Picks on. Fewer than 4 eligible picks shows what there is; none omits the section. | proposed |
| D7 | The arrivals toggle **moves** from My List to the profile page; My List keeps a "Email settings" link in its place, so one setting has one control. The arrivals email's "turn it off on My List" line is replaced by the opt-out link. | proposed |
| D8 | The profile page is **`account.html`, "My Account"**, reached by making the nav greeting's name a link (desktop bar and phone drawer). It joins the nav sync set as its **eighth** page. Name and email are shown read-only (changing an email is F126, out of scope). | proposed |
| D9 | **Opt-out:** each email footer links to a **preferences page that needs no sign-in** (a signed token in the link), showing the three toggles. Each email also carries `List-Unsubscribe` + `List-Unsubscribe-Post` headers; the one-click unsubscribe a mail client offers turns off **that** email. The link only opens the page; nothing changes until the customer presses a button (scanners again). | proposed |
| D10 | "See more" on the rail still opens the Recommended For You view (its own ranking in `app.js`). When the rail holds only New #1s, "See more" is hidden, since that view has nothing matching to show. | proposed |

**Open, not decided here:**
- **O1.** `notify-customers` emails **pending and paused** accounts too (it filters on `is_admin` only).
  This plan sends picks to active accounts only and does not change who gets the email itself. Whether
  pending and paused accounts should get the catalog email at all is Rick's call (a one-line filter).
- **O2.** Should a series the customer **subscribes to** be excluded from picks? Auto-reserve normally
  reserves it at import, so D4 already hides it; it matters only when a subscription was added after the
  import. Not built unless asked.

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
- **Drops:** reserved by issue (D4), FOC passed, not a standard cover, and the store's `catalog_filters`
  rules that can apply to a standard cover: hidden publisher, standard covers switched off, zero price.
  (Variant and ratio rules cannot touch a standard cover; past-FOC is already dropped.)
- **Returns** `catalog_id, tier ('personal'|'popular'|'new1')` in rank order.
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
| **S1** | SQL (`docs/sql/<date>-top-picks-rpc-and-email-prefs.sql`): `get_top_picks()`, the two columns, the widened guard. Staging. | **parity harness:** for 10+ staging accounts the RPC's picks equal today's `getTopPicks()` except where D3/D4/D5 apply, each difference explained; anon refused (`42501`); a customer cannot ask for another customer; an admin cannot ask across tenants; a negative control per rule seen red |
| **S2** | Client: the rail calls the RPC; New #1 caption; D10; `?pick=` deep link + `pick_opened` event. | spec updates (local suite) + the full suite after push; a real deep-link click signed in and signed out |
| **S3** | `account.html` (eighth nav page), the three toggles, the greeting link, D7 on My List, a `privacy.html` sentence. **The settings gear self-gates on `#search` being absent**, so a new page without a search box would show it; gate it on the page explicitly. | nav and footer hashes identical across eight pages; toggles round-trip; the F182 guard accepts the two new columns and still refuses everything else |
| **S4** | `email-preferences` Edge Function + `email-preferences.html` + the secret. | bad and missing token refused; good token reads and sets; one-click POST turns off only its own email; no other profile column writable through it; GET never changes anything |
| **S5** | Both mail functions: picks section, footer link, `List-Unsubscribe` headers, `email_catalog` honored, the postal-address rule. Deploy to staging reading live `verify_jwt` first (F93; `notify-customers` and `notify-arrivals` are both OFF). | a fake-network template harness (opted-out customer gets no picks; free shop without address gets no picks; HTML escaped); then Rick's real inbox, **headers only**: picks render, links open the title, unsubscribe works |
| **S6** | Production: SQL first, then the client PR (`app.js` carries `merge=ours`: assert its merge result), then the three Edge Functions and the secret. | served bytes equal `main`; a real send read back; a write-smoke, since the catalog reserve path changes |

S1 + S2 alone are a useful first promotion (the better rail) and can ship before the emails. S3 and S4
must land before S5: no promotional content is sent until the opt-out it points to exists.

---

## 5. Not in scope

Changing a customer's email or name from the profile page (F126). A picks section on the weekly
newsletter (Brevo, `weekly-pull-feed`). A phone version of the rail. Reserving without signing in (D1).
Resend's 100-per-day limit (F148) is unchanged by this work: picks add no sends.
