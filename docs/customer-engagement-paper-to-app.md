# Customer engagement: paper customers to app users

**STATUS:** NOT STARTED · planned 2026-11-13, decisions D1-D9 answered the same day · staging=— · prod=— · PR=— · findings=F89 (closes at S2); no new ID consumed (F182 next free)

Owner: Rick. One session per step (S1 to S5). Each step ships on its own: staging first, production
only on Rick's `/promote-prod`. Database steps are Rick-run.

Related records: `docs/technical-reference.md` § 13 F89 (conversion is not measured), F13 (history is
lost when an account is deleted), F181 (`claim-paper-customer` shop check), F148 (email daily limit),
F152 (Outlook spam placement); `docs/newsletter-acquisition-funnel.md`; `docs/store-contact-and-colors.md`
(S2 and S3 there edit the same mail functions and print headers as this plan).

---

## 1. Why

Rick, 2026-11-13: shop owners spend a lot of time processing preorders by hand; the newsletter and
the notification emails are not bringing customers to the app; printed catalogs and bag lists carry
the address but have little effect. Goal: move paper customers into the app and bring app users back.

Rick chose five ideas from the brainstorm: **#1** invite a paper customer from their row (go),
**#4** measure conversion, **#5** an automatic "your books this week" email, **#2** a personal QR
code on the bag slip, **#13** QR codes on the store poster and shelf tags for new #1 issues.
**#10 (a public "this week" page) is already covered by `rjbookstop.com/news`** and is out of scope.

## 2. What exists today (read from code 2026-11-13; production was not read)

- **A paper customer is already a full account.** `create-paper-customer` makes a real auth user with
  a placeholder address (`<name>.<stamp>@paper.pulllist.local`, `app.js:2302-2309`) and a profile with
  `is_paper = true`, `status = 'active'`. Their reservations, subscriptions and history hang off that
  user id.
- **The only way to convert one is Claim**, which asks the admin to paste a user UUID "from Supabase →
  Authentication → Users" (`admin.html:5613-5617`). A shop owner cannot do that. Claim also moves rows
  to a second account and deletes the paper one, which loses its `reservation_history` (F13) and has
  the open shop-check gap (F181).
- **Nothing records a conversion** (F89). `usage_events` are purged at 90 days (F90).
- **Emails a customer gets without asking:** the monthly "pull list is live" email
  (`notify-customers`, skips `@paper.pulllist.local`) and the Brevo newsletter (10 recipients in the
  2026-09-08 export; the list is separate from app accounts).
- **"Your books are in" already exists, one customer at a time.** The Bagging list has an Email button
  per customer card (`admin.html:5065`, current week only) that calls `send-my-list` in week mode.
  The customer's own "Email My List" button is the other caller. There is no send-to-everyone and no
  schedule. *(My first summary said only the customer's button existed; that was wrong.)*
- **Prints carry text only.** Bagging slips and the Print Catalog say "View Online: <store address>".
  No QR code exists anywhere in the app, and `vendor/` holds only `supabase.min.js`.
- **The store poster points newcomers at the wrong door.** Its call to action is hardcoded
  "Reserve online at pulllist.app" and "Start now → pulllist.app" (`arrivals.html:574`, `:595`). The
  bare `pulllist.app` shows the platform page for shop owners, and "Create one" is revealed only on a
  store's own address (`index.html:578`). So a new customer following the poster reaches a page with
  no sign-up. Read from code, not tested in a browser. Fixed in S4; not filed.
- **Privacy Statement wording** (`privacy.html:42`) lists account emails as "sign-up confirmation,
  approval, password resets, and your list when you ask for it". An automatic weekly email is not
  "when you ask for it", so S3 updates that sentence.
- **`rjbookstop.com/news`** (fetched 2026-11-13): a "Pull List" nav link to `rjbookstop.pulllist.app`,
  a newsletter sign-up form, and the weekly feed loaded by script. No change planned here.

## 3. Decisions — ANSWERED 2026-11-13

Rick: "Defaults - except #5, omit the email everyone button and allow individual's email buttons to
be active in past weeks. Include a Tuesday schedule." So D1-D3 and D5-D9 stand as written and **D4 is
replaced** (the row below shows the new answer; the first draft's default was "an Email everyone
button first, a Tuesday schedule after two clean weeks").

| # | Question | Answer |
|---|---|---|
| D1 | What state is a paper customer in after the admin invites them (S1)? | **Active.** The admin typed the address at the counter, same trust as today's Invite. |
| D2 | The typed email already belongs to an account in this shop | **Offer the existing Claim, with a pick-list of the shop's accounts in place of the UUID prompt** (client-only change in S1). |
| D3 | `claim-paper-customer` is redeployed in S2 to log its event. Fix F181 in the same deploy? | **Yes, as its own commit** (read both profiles with the caller's shop, tenant-filter the deletes). |
| D4 | How does the weekly email go out (S3)? | **A Tuesday schedule, limited to titles on that week's invoice. No "Email everyone" button. The existing per-customer Email button on the Bagging list also works for past weeks** (Rick, 2026-11-13). |
| D5 | Can a customer turn the weekly email off? | **Yes: a toggle on My List, on by default for everyone.** No one-click unsubscribe link (that needs a public endpoint). |
| D6 | A customer claims their list from a bag slip (S5). Active at once, or approved first? | **Pending, then the admin approves** in the existing Pending Accounts panel. A slip can be picked up by someone else. |
| D7 | How long does a slip code last? | **60 days, one live code per paper customer, reprinted on each slip until used.** |
| D8 | Also put a store QR on the Print Catalog (the paper order form)? | **Yes, QR only, no new wording.** |
| D9 | Shelf tag size | **8 per letter page with cut lines.** |

## 4. Steps

Order is by dependency and risk: S1 removes the blocker, S2 makes results visible, S3 is the weekly
reason to open the app, S4 is client-only printing, S5 is the largest and has a public endpoint.

### S0. Baseline (Rick-run, read-only, both projects, counts only)

```sql
SELECT t.slug,
       count(*) FILTER (WHERE COALESCE(p.is_paper, false))                                   AS paper_accounts,
       count(*) FILTER (WHERE NOT COALESCE(p.is_paper, false) AND NOT COALESCE(p.is_admin, false)) AS app_accounts,
       count(*) FILTER (WHERE COALESCE(p.is_paper, false) AND EXISTS (
         SELECT 1 FROM public.preorders o WHERE o.user_id = p.id AND NOT o.fulfilled))        AS paper_with_open_reservations,
       count(*) FILTER (WHERE COALESCE(p.is_paper, false) AND EXISTS (
         SELECT 1 FROM public.subscriptions s WHERE s.user_id = p.id))                        AS paper_with_subscriptions
FROM public.user_profiles p
JOIN public.tenants t ON t.id = p.tenant_id
GROUP BY t.slug
ORDER BY t.slug;
```

Paste the result into § 6. It is the "before" number for every later step. Also note the current
Brevo list size.

### S1. Invite a paper customer from their row (#1, approved)

**What the shop sees:** an **Invite…** button on each paper customer in Customers ▸ Accounts. The
admin types the customer's email (phone optional), confirms, and the customer gets a sign-in link.
The account they open already holds their reservations, subscriptions and history.

**How:** convert in place. Nothing moves between accounts, so F13's history loss and F181 do not apply.

1. **SQL first, both environments, before any code that reads it** (the F115 lesson: selecting a
   column production lacks fails the whole read). New file
   `docs/sql/2026-11-xx-paper-conversion-columns.sql`: `user_profiles.converted_from_paper_at
   timestamptz NULL` and `user_profiles.signup_source text NULL`. No RLS change (covered by `admins
   manage tenant profiles`). Check at execution whether a customer's own-profile UPDATE policy lets
   them write these two, and record the answer (done 2026-11-13: see § 6 and F182).
2. **New Edge Function `convert-paper-customer`** (admin only, in-body auth as in
   `create-paper-customer`; deploy `--no-verify-jwt`, stated explicitly per F93):
   - caller must be an admin; the paper profile is read **with the caller's `tenant_id` and
     `is_paper = true`**, 404 otherwise;
   - validate the email; change the auth user's email with the admin API (`email_confirm: true`). If
     the address is taken, change nothing and return 409; when the existing account is in the same
     shop, return its id and name so the page can offer Claim (D2);
   - update the profile: `email`, `is_paper = false`, `converted_from_paper_at = now()`, `phone` if given;
   - generate a sign-in link with type **`recovery`** (F153: `invite` fails with `email_exists` for a
     user that already exists) and send it through Resend with the invite layout and wording that
     says the list is already there ("Your pull list is online: N reservations and M subscriptions
     are waiting"). Carries the shared tenant-identity block; the F72 G-F grep gate then covers six
     copies, and `store-contact-and-colors.md` S2 must include this function;
   - insert `usage_events` rows `paper_converted` (`metadata: { via: 'admin' }`) and `invite_sent`,
     with `tenant_id` explicit;
   - if the email send fails, the account stays converted and the response says `invite_sent: false`;
     the page offers **Resend** (the same function with `resend: true`, allowed only for a profile in
     the caller's shop with `converted_from_paper_at` set).
   - **Confirm the admin update-user call and the `recovery` link against the live staging project
     before writing the rest.** F153 found an assumed link type wrong.
3. **`app.js`:** `PaperCustomers.convert(paperUserId, { email, phone }, token)`. `app.js` carries
   `merge=ours`, so the promotion asserts its merge result.
4. **`admin.html`:** the Invite… button and a small modal in the Edit Account style; the Claim prompt
   becomes a pick-list of the shop's non-paper accounts (D2). The bagging Email button stays as is.

**Effects to expect:** the customer starts receiving the monthly catalog email (it filters on the
placeholder address), leaves the Paper filter, and sees the welcome message on first sign-in.

**Gates:** local harness on staging with a throwaway admin and paper customer: same user id before and
after; reservation, subscription and history counts unchanged; `is_paper` false; stamp set; both events
written with the right `tenant_id`; taken email returns 409 and changes nothing; another shop's paper
id returns 404; a non-admin gets 403; each new assertion seen red once; teardown re-read 0. Full suite
once after the push. Rick reads one delivered invite (headers only, link replaced by `[link]`).

**Tell the counter staff:** the invite may land in spam for Outlook addresses (F152).

**SQL sequencing:** the two columns are nullable and nothing reads them until this step's code, so
Rick applies the file on staging **and production** in the same sitting, before the code merges. The
file is then never left `prod=PENDING`, which would block every other `/promote-prod` at step 0.

**S1 completion criteria**

- [ ] The live staging check of the admin update-user call and the `recovery` link is recorded in § 6
- [ ] `docs/sql/` file for the two columns written, with a verdict query whose output differs when it has failed
- [ ] SQL applied by Rick on staging and on production; STATUS line reads `APPLIED` for both
- [ ] `convert-paper-customer` deployed to staging with `--no-verify-jwt`; deployed source downloaded and hashed equal to the commit
- [ ] `PaperCustomers.convert` in `app.js`; Invite… button and modal in `admin.html`; Claim uses a pick-list (D2)
- [ ] Harness gates green on the deployed staging bytes, each new assertion seen red once, teardown re-read 0
- [ ] Full Playwright suite run once after the push; its own `N passed` line recorded
- [ ] Rick has read one delivered invite (headers only) and used the button once on staging
- [ ] § 6 of this plan, the STATUS line and `CLAUDE.md` § Current Migration Phase updated
- [ ] Production: NOT part of S1's session. It needs Rick's `/promote-prod`, then the function deployed to production from a worktree of `origin/main`

### S2. Measure it (#4; closes F89)

- **`signup_source`:** the sign-in page keeps a `?ref=` value (allowlist: `poster`, `shelf`, `slip`,
  `catalog-print`, `newsletter`, `news`) the same way `PostAuthRedirect` keeps the return path;
  `doSignup()` sends it; `register-customer` stores it on the new profile. Deploy with `verify_jwt`
  read first.
- **Events from the other paths:** `invite_sent` from `invite-customer`; `paper_claimed` from
  `claim-paper-customer` on success (plus the F181 fix, D3).
- **Analytics card "Paper to app":** paper customers now; converted (from `converted_from_paper_at`,
  so it survives the 90-day purge); invited but never signed in; sign-ups by source. Follows the
  page's existing rule of excluding admins.
- **Gates:** harness check that each path writes its event and that `signup_source` lands; card
  numbers reconcile against a service-role count; spec 18 still green.
- F90 (monthly rollup) stays open; the column covers conversions only.

### S3. "Your books this week", sent every Tuesday (#5)

Two parts (D4): a scheduled Tuesday email, and the existing per-customer Email button opened up to
past weeks. There is no send-to-everyone button.

**S3a. The per-customer Email button works for past weeks** (`admin.html` only)

- Today the button is disabled unless the Bagging list shows the current week (`admin.html:4821`,
  `:5067`). Change: enabled for the current week and any past week; still disabled for a future week,
  with the tooltip saying why.
- The confirm names the week ("Send <name> their list for the week of <dates>?"), so a past-week send
  is never mistaken for this week's.
- It keeps calling `send-my-list` in week mode, unchanged. **Known limits of that email, not changed
  here:** it lists every title the customer reserved for that week, including ones already collected
  (`fulfilled` cannot tell "collected" from "closed by the import"), and it does not leave out titles
  marked as not arriving. The confirm says so in one line. **Rick, 2026-11-13: "Past-week button can
  reuse email for now."**
- Local spec 06 asserts the button is visible and enabled on the current week (lines 61-62); nothing
  asserts the disabled state. Add one check each for a past week (enabled) and a future week (disabled).

**S3b. The Tuesday schedule**

- **New Edge Function `notify-arrivals`** (deploy `--no-verify-jwt`; the caller must present a
  dedicated `ARRIVALS_CRON_SECRET` header or be a signed-in admin, in which case it runs for that
  admin's shop only). For the Mon-Sun week containing the run date, per shop:
  - **only titles on that week's invoice:** open reservations whose title has a `weekly_shipment` row
    in the week, matched the way `auto_fulfill_past_on_sale()` matches (read
    `docs/sql/auto_fulfill_past_on_sale.sql` and reuse its three keys). Wording: "on this week's
    shipment, ready from Wednesday";
  - **a shop with no `weekly_shipment` rows for the week gets nothing sent**, and the response says so
    (the shipment import has not run; an email built from dates alone would repeat F115's false
    "it's here");
  - skips paper, pending and paused accounts, customers who turned it off, and customers with nothing
    on the invoice;
  - titles the customer reserved for the week that will not arrive (withdrawn, supplier-rejected,
    marked didn't arrive, damaged or can't get it) go in a short "Not arriving this week" note;
  - one email per customer through Resend, reusing `send-my-list`'s table, with a **See my list** link
    to `mylist.html` and a line saying where to turn the email off;
  - `dry_run: true` returns who would be emailed and with how many titles, and sends nothing.
- **No double sends:** new table `arrival_notices (tenant_id, user_id, week_start, sent_at)`, unique
  on the first three; a second run in the same week sends only to customers not yet sent. Admin-read
  only.
- **Opt-out (D5):** `user_profiles.email_arrivals boolean NOT NULL DEFAULT true`, a toggle on My List
  beside Email My List. Read fail-open in its own small query so a missing column never breaks My List.
- **The trigger: Tuesday 15:00 UTC (10 or 11 AM Eastern), production only.** Recommended: `pg_cron`
  with `pg_net` inside the production Supabase project, one job that posts to `notify-arrivals` with
  the secret header and covers every shop in one run. **Neither extension has been used in this
  project; confirm both are available on the free plan and enabled before building on them.**
  Fallback: a scheduled GitHub Actions workflow holding the secret (GitHub's cron has started up to
  3h20m late here, which is acceptable for this email).
- **Staging gets the function but never the schedule.** Staging accounts are test fixtures with
  made-up addresses; a weekly send there would bounce and hurt the `pulllist.app` sender (F152).
  Staging is exercised by hand, with `dry_run` and with Resend stubbed.
- **Limits:** Resend's free tier is 100 emails a day and the function sends one request per customer
  (F148). The function refuses to start above 90 recipients across all shops and says why.
- **Also in this step:** `privacy.html:42` gains "and a weekly note when your reserved books arrive".
- **SQL** (`docs/sql/`, staging then production, before the code): the column, the table, and (production
  only, last) the cron job. The cron statement goes in its own file so step 0 of `/promote-prod` is not
  blocked by a staging `N/A`.
- **Gates:** harness on staging with four throwaway customers (titles on the invoice; reserved but not
  on the invoice; opted out; paused) and one unavailable title: `dry_run` names exactly the first
  customer; the real call makes exactly one email request with the right titles and the unavailable
  one in the note; a second run sends 0; a week with no shipment rows sends 0 and says why; a call
  with no secret and no admin session is refused. Then on production: one `dry_run` read by Rick
  before the first Tuesday, and the first scheduled run read from the function's response and one
  delivered email (headers only).
- **Two weeks after the first scheduled send:** compare Visits on Tuesday and Wednesday with the two
  weeks before (Analytics), and record it in § 6.

### S4. QR on the store poster, shelf tags and Print Catalog (#13)

Client-only. Brings the QR library that S5 reuses.

- **Library:** vendor one small MIT-licensed QR generator into `vendor/` (pin the version, record the
  source and licence in the commit, add a `no-cache` line in `_headers`). The CSP already allows
  same-origin scripts. Render as inline SVG so it prints sharp.
- **Store poster** (`arrivals.html`): replace the hardcoded `pulllist.app` in both lines with the
  shop's own address (`Tier.publicUrl()`), and add a QR to `https://<store address>/?ref=poster`.
- **Shelf tags for new #1s:** a "Print #1 shelf tags" button on the admin store view for the selected
  week. One tag per series whose shipment row links to a catalog row with `issue_number = '1'` and a
  standard cover: title, "New series. Never miss an issue.", QR to
  `subscriptions.html?series=<name>&ref=shelf` on the store address. Rows with no catalog link are
  skipped and counted on screen.
- **Print Catalog (D8):** the same store QR beside "View Online", `ref=catalog-print`.
- **Known limit:** a new sign-up waits for approval, and the series search is disabled until then, so
  a shelf-tag scan by a newcomer ends at "account pending".
- **Gates:** decode every generated QR in the harness and compare with the expected URL; print preview
  inspected at letter size; **Rick scans a real laser print with a phone at arm's length** (the
  2026-08-24 barcode trial failed on the shop's scanner, so paper is the test that counts); nav and
  footer hashes unchanged.

### S5. Personal QR on the bag slip (#2)

Paper customers only. Needs S1 (conversion) and S4 (QR library).

- **Table `paper_claim_codes`** (`code` primary key, random, 12 characters from an unambiguous
  alphabet; `tenant_id`; `paper_user_id` cascade; `created_at`; `expires_at`; `used_at`). RLS on, no
  customer policy.
- **Admin function `admin_get_paper_claim_codes(user_ids uuid[])`** (admin only, shop derived inside,
  `REVOKE` from `anon` and `PUBLIC` in the same transaction, F124): returns each paper customer's live
  code or makes one (D7).
- **Bagging slip:** for a paper customer the print header gains a QR to
  `https://<store address>/?claim=<code>` and the line "Your pull list is online. Scan to claim it."
- **Sign-in page:** `?claim=` opens a small "Claim your pull list" panel: email and the Turnstile check.
- **Public path:** a code mode on `convert-paper-customer` (honeypot and Turnstile as in
  `register-customer`). A valid code converts the account in place with `status = 'pending'` (D6),
  `signup_source = 'slip'`, marks the code used and logs `paper_converted` (`via: 'slip_code'`). The
  admin approves in the Pending Accounts panel, and `approve-customer` sends the sign-in link. An
  invalid, used or expired code and a taken email all get the same "ask at the counter" answer.
- **Check before building:** a pending account's reservations must stay on the Bagging list and the
  order export while the admin has not yet approved. If any admin view filters on `status`, D6 changes
  to active.
- **Gates:** valid code converts once and only once; expired, used and other-shop codes change
  nothing; the pending account still appears on the Bagging list; anon cannot read the table or call
  the admin function (probe both); Rick scans a real slip.

## 5. Out of scope

- #10, a public "this week" page: `rjbookstop.com/news` does this.
- Benefit wording on the printed catalog (#3), deadline reminders (#6), arrival and not-coming emails
  per title (#7), Add to Home Screen (#8), win-back nudge (#9), pending accounts building a list (#11),
  newsletter opt-in on sign-up (#12), social links (#14). Not chosen on 2026-11-13.
- Changing the newsletter or Brevo.
- Fixing F13 or F90.

## 6. Baseline and results

*(S0 output goes here, then one line per step as it ships.)*

### S1, gated step 1: the two GoTrue calls, tried live on staging (2026-11-13)

Local probe `convert-paper-s1-probe.mjs` (scripts repo playwright folder, never committed), staging only
(`puoaiyezsreowpwxzxhj`), throwaway users in the `demoshop` shop. Nothing secret is printed: tokens,
`hashed_token`, `email_otp` and `action_link` are replaced by markers. **Final run 36 passed, 0 failed.**

| Call | What came back |
|---|---|
| `PUT /auth/v1/admin/users/<id>` body `{ email, email_confirm: true }` on a paper user | **200.** Same `id`; `email` is the new address; `email_confirmed_at` set; no pending `new_email`; `user_metadata.full_name` kept. A fresh `GET` agrees. |
| `POST /auth/v1/admin/generate_link` body `{ type: 'recovery', email: <new>, redirect_to }` | **200**, same user id, `verification_type: 'recovery'`, an `action_link` of the form `<project>/auth/v1/verify?token=…&type=recovery&redirect_to=…`. Following it once (no redirect) gave **303** to the redirect URL with a session in the fragment (`access_token`, `refresh_token`, `type=recovery`). |
| the same link with `redirect_to = https://staging.pulllist.pages.dev/index.html` | **Lands on `/index.html`** (not GoTrue's Site URL), so the function's own redirect target is on the allow-list. Staging's `APP_BASE_URL` secret digest equals `sha256("https://staging.pulllist.pages.dev")`. |
| **email already taken:** `PUT` the same user's email to another user's address | **HTTP 500**, body `{ code: "23505", message: "duplicate key value violates unique constraint \"users_email_partial_key\"", detail }`. The user is left unchanged. The same address **upper-cased** is refused the same way, so uniqueness is case-insensitive. |

**What this changed in the build (S1 item 2):**

1. **My first guess was wrong, and the first probe run failed on it.** I asserted a 4xx, expecting F153's `422 email_exists`.
   The real answer is a 500 with a Postgres code. The function therefore must not key on a 4xx or on `error_code`: it
   recognises `code === '23505'` or a message naming `users_email_partial_key` / "duplicate" as "email taken" (409), and
   treats any other failure as a real error. A second, earlier check looks for the address in `user_profiles` (case-insensitive,
   wildcards escaped) so the same-shop case can return the existing account's id and name for D2; an account in another shop
   is answered with a bare 409 and no name.
2. **The change is atomic for the user.** A refused update leaves the auth user as it was (read back), so the function can
   change the auth email first and the profile second.
3. **The profile copy does not move by itself** (F25: no trigger). The profile still read the paper address after the auth
   change, so the function must write `user_profiles.email` itself.
4. **`auth.identities` keeps the old address.** After the update `identities[].identity_data.email` still held the paper
   placeholder. It does not break sign-in: with the **new** address a magic link gave a session and a password grant returned
   200 for the same user id; with the **old** placeholder the password grant was refused. Not verified: anything else that reads
   `identity_data.email` (this app uses only email-and-password and magic links).
5. **Trap, not used here:** a `magiclink` request for an address that has no user **creates** one. The probe's first full run
   leaked such a user (the old placeholder address); found by a scan of all 990 auth users, classified by its `probe.paper.<stamp>`
   name and this run's stamp, deleted, fresh read 404. The probe now deletes it itself (re-run: 989 users before and after).
   The function must only ever use `recovery` for an existing user.

**Not verified at this step:** a delivered email (that is step 10); the set-password page itself (the link was followed at the
GoTrue level only, not through a browser); production (never touched).

### S1, steps 3 to 8: SQL applied, function and screens built and verified on STAGING (2026-11-13)

**Not promoted. Production has the two columns (Rick ran the SQL) and nothing else.** Code `5980dc5` on `staging`; docs
`b5125f9`, `3469996`. **F182 was filed during this work** (security-sensitive, found by the check in step 3 below, not caused by S1's
code; details held locally); **F183 is next free.**

- **Step 3, SQL.** Rick ran `docs/sql/2026-11-13-paper-conversion-columns.sql` on staging, then production, the same sitting.
  Both pasted rows read `OK - 2 nullable columns present, no default, authenticated can read them`,
  `authenticated_can_update_new_columns = true`, no triggers on `user_profiles`. STATUS now `staging=APPLIED | prod=APPLIED`.
  The result row also printed the live policies and privileges on `user_profiles`, which answered the plan's "can a customer write
  these two columns?" check. **That answer led to F182, which is security-sensitive: its details are held in the operator's local
  security notes, not in this repo.** Nothing about those two columns is narrowed by S1.
- **Step 4, the function** `supabase/functions/convert-paper-customer/index.ts` (new; convert and resend modes). Built from the
  probe above. Checks: the shared tenant-identity block hashes `5dfc44bc878611bb` in **six** files (the G-F gate's own method:
  marker lines included, trailing newline, LF; a one-byte change to the new copy hashes differently). **`deno` is not installed
  here**, so TypeScript was checked with Node's own TS parser plus a compile of the stripped output (both a JS-grammar and a
  TS-grammar break are caught); that is a syntax check, **not** a Deno type-check.
- **Step 5, deploy** to staging only (`--project-ref puoaiyezsreowpwxzxhj --no-verify-jwt`; Docker not running, so the CLI bundled
  through the API). Before: `NOT_FOUND`. After: an unauthenticated POST returns the function's own `{"error":"Unauthorized"}`; a
  garbage bearer token also reaches the function, while `approve-customer` (known `verify_jwt` ON) answers the same token with the
  gateway's `UNAUTHORIZED_INVALID_JWT_FORMAT`, so `verify_jwt` is OFF by behaviour. **Downloaded source == the working-tree file
  byte for byte (`32ab0d60a596847b`) and == the committed blob modulo CRLF** (Windows checks out CRLF, git stores LF).
- **Step 6, screens.** `app.js` `PaperCustomers.convert()` and `resendInvite()`; `admin.html` Invite… button and modal on paper rows,
  Resend invite on a converted account that has never signed in (read through its **own non-fatal query** of
  `converted_from_paper_at`, so a missing column can never break the Accounts tab), and the Claim UUID `prompt()` replaced by a
  pick-list of the shop's own non-paper, non-admin accounts (D2). An Invite on an address that belongs to a same-shop account
  names it and offers "Merge into <name>…", which opens the picker with it chosen. Syntax of `app.js` and every inline script
  checked, with a control that fails; nav and footer blocks unchanged against `HEAD` on all seven pages.
- **Step 7, deploy.** `ff-only` merge, pushed; served `admin.html` and `app.js` equal the commit on **five consecutive polls** of
  the plain URLs (poll 1 still served the old bytes, `796e093f…` and `85b25bbb…`, the hashes recorded for production).
- **Step 8, evidence.**
  - **Logic harness** `convert-paper-s1-logic.mjs` (fake `Deno` and fake network; local-only): **64/64**, and **six deliberate
    source breakages each turned the intended assertion red**: no LIKE escaping, no compensation, events attributed to the
    customer, the link logged, no shop filter on the paper read, no same-shop test. It covers what cannot be provoked live: a
    profile update failing after the auth email changed (the auth email is put back), Resend failing or its key missing
    (`invite_sent: false`, the account stays converted, no `invite_sent` event), the sign-in link failing, nothing token-shaped
    in the logs, no founding-tenant fallback.
  - **Live harness** `convert-paper-s1-verify.mjs` against the deployed function and the deployed `admin.html`, throwaway users in
    `demoshop` and the founding shop: **81/81**, teardown re-read 0 profiles, 0 auth users, 0 events, 0 rows (12 users). It
    covers: 401, 403 (a signed-in customer), 400s, **404 for another shop's paper customer (who is left untouched), an app
    customer and an unknown id**; **409 for a same-shop account (case-insensitive, with its id and name), another shop's
    account (no name leaked) and an auth user with no profile (GoTrue's live 500/23505 recognised)**; an underscore in the typed
    address is not a wildcard; the conversion keeping the **same auth user id** and the **reservation, subscription and history
    counts unchanged**, `is_paper` false, the stamp set, both events with the right `tenant_id`; the converted customer signing
    in with the new address and seeing their own 2 reservations and subscription through RLS while the old address no longer
    works; resend (200, and 404 or 403 where it must); the Invite and Claim modals in a real browser including the confirm text,
    the same-shop duplicate leading to the merge, a real claim through the new picker, no `prompt()` anywhere, and a 390 px
    fit check. **Every address that was actually emailed is a Resend test inbox (`delivered+label@resend.dev`)**, so no
    made-up domain reached the sender (F152).
  - **"Seen red" for the live harness, stated exactly:** the state assertions (14) are each shown able to fail by corrupting an
    in-memory snapshot (`SELFTEST=1`, no network); every status-code assertion is paired in the same run with the opposite case
    returning 200; the function's own logic is the six mutations above. **No assertion was seen red against the DEPLOYED function
    with a deliberately broken build**, and I did not deploy a broken copy.
  - **Three runs, two of my own errors, both in the harness, neither a product defect:** run 1 passed all 52 API checks and then
    stopped because my first click on the Accounts tab landed before the page's own init had wired the tab (fixed by clicking
    until the panel shows); run 2 failed two of my expectations (a customer I had signed in myself cannot be "never signed in",
    and a customer converted earlier is rightly in the Claim picker), both rewritten to read the truth from the database.
  - A scan of all 989 auth users and all profiles for anything the harnesses made found none left (989 before and after).
- **Decision beyond the plan, for Rick to overrule:** the two events are attributed to the **admin who acted**, with the
  customer's id in `metadata.target_user_id`. Attributed to the customer, Analytics (which tallies every non-promo event per
  user) and Accounts' "Last seen" (the newest event) would show a just-invited customer as active today.
- **Observed, deliberately not fixed or filed:** the sign-in page's recovery landing reads "Reset your password" for someone who
  never had one (`index.html`, out of scope; same as F153's admin invite); the identity block's own comment still says "five
  copies" in all six files (fixing it means editing five other functions); a debug load of `admin.html` as a fresh throwaway admin
  printed three HTTP 406 console errors (not investigated; the cause was not this change's new query, which does not use
  `.single()`, and the full harness run recorded no uncaught page errors).

## 7. Not verified when this plan was written

- Production and staging were not read: the number of paper customers, how many hold open
  reservations, and the newsletter list size are unknown until S0.
- The admin update-user call and the `recovery` link for a converted account were not tried.
- The poster's bare `pulllist.app` leading to a page with no sign-up was read from code only.
- Whether `pg_cron` and `pg_net` are available and enabled on the production project (S3b).
- How `auto_fulfill_past_on_sale()` matches a reservation to a shipment row; S3b must read it, not
  assume it.
- Whether a customer can write the two new profile columns through their own-profile policy. *(Answered 2026-11-13; see § 6 and F182.)*
- Whether any admin view drops pending accounts' reservations (S5's check).
- The QR library choice, its size and its licence.
