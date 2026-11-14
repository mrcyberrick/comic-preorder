# Store contact details and store colors in Settings

**STATUS:** IN PROGRESS — S1 DONE on both environments (staging 2026-11-10 `330af30`; production 2026-11-10, PR #185, merge `cd264bd`); production data fill NOT yet done; S2, S3, S4 NOT STARTED · staging=2026-11-10 (S1) · prod=2026-11-10 (S1) · PR=#185 · findings=— (no ID consumed; F181 next free). *(Read "NOT STARTED ... next is S0" until the S1 promotion.)*

Replaces the Settings rail's **Email Templates "Soon"** entry. Since F72 G-F (2026-11-07) every
email already uses each shop's own name, so there is no template left to unblock. What is missing
is the shop's own **contact details** (and, asked for 2026-11-10, its **color**), which today are
either hardcoded to Ray & Judy's or settable only by the operator in SQL.

Owner records: `docs/f72-multi-tenant-branding.md` (§ 0.1 tier table, Q2 website), 
`docs/f72-g-f-mail-and-signup-gate.md` (Q13 catalog-email address, **Q14 paid footer literal**),
`docs/admin-settings-catalog-visibility.md` (the Settings page), `docs/technical-reference.md` § 4.1.

---

## 1. What exists today (measured 2026-11-10 unless noted)

### 1.1 Contact details are hardcoded for the paid tier

- **Emails:** all six mail functions carry `PAID_CONTACT_HTML = '40 W Main St. Rockaway, NJ 07866
  &middot; (973) 586-9182'` (`approve-customer:29`, `invite-customer:17`, `notify-customers:14`,
  `reset-password:16`, `send-my-list:14`) or the same text inline (`register-customer:311`, `:315`).
  Used for any `plan = 'pro'` shop. This was decision **Q14** ("keep the literal ... a second paid
  tenant then needs the database-driven footer in all six functions plus the `rjbookstop` data fill;
  record that in the onboarding runbook"). **The runbook note was never written** (added with this
  plan, `tenant-onboarding-runbook.md` Step 3).
- **Web and print:** about 20 places across 8 pages, all paid-only, all Ray & Judy's:
  - footer `· Rockaway, NJ` on the seven nav pages (`catalog.html:293`, `mylist.html:721`,
    `arrivals.html:609`, `subscriptions.html:346`, `admin.html:663`, `analytics.html:596`,
    `settings.html:642`);
  - phone in the pending / paused banners (`catalog.html:352`, `:380`; `mylist.html:862`, `:870`;
    `subscriptions.html:457`, `:465`), the pickup notice (`mylist.html:589`), the arrivals poster
    (`arrivals.html:563`, `:596`) and the print headers (`arrivals.html:1005`, `mylist.html:1507`,
    `admin.html:4996`);
  - `rjbookstop.com` on the prints (`admin.html:4996`, `:6423`, `:6707`; Q2, no field exists).
- **So a second paid shop would show and email Ray & Judy's address, phone and website.** Correct
  today only because Ray & Judy's is the only `pro` shop.

### 1.2 The columns half exist, and nothing in the app writes them

`tenants.contact_phone` and `tenants.location` exist (§ 4.1). Only `register-tenant` sets them, at
creation. Measured 2026-09-01 (not re-read): production `rjbookstop` has both **NULL**; staging
`raysandjudys` has `973-586-9182` / `Rockaway, NJ`; production `comicstore` `555-555-5555` /
`New Jersey`. There is no street-address or website column.

`notify-customers` (the catalog email) needs a postal address on both tiers (Q13): a free shop with
no `location` gets **422, nothing sent**, and no screen lets the shop fix it.

### 1.3 Colors

- One per-shop color exists: `tenants.branding.primary_color` (`#RRGGBB`). `Branding.apply()`
  (`app.js:241-260`) copies it into `--accent` and `--accent-dim`, and sets `--accent-hover` to the
  **same** value (so hover shows no change for a custom color). Every other color (backgrounds,
  text, Lunar blue, PRH purple, success, warning, error red) is fixed in `style.css:14-36`.
- **Set only by SQL.** No screen writes it.
- **Not tier-gated, contrary to the F72 tier table** (§ 0.1: free = "`primary_color`/`logo_url` are
  **never** applied") and the pricing copy (`index.html:261`: the paid plan gets "your logo and
  colors"). **Seen live 2026-11-10, production, signed out:** `comicstore.pulllist.app` (free)
  renders `--accent: #00FF00`. White button text on `#00FF00` is about 1.4:1.
- **The anon front door never knows the plan** (`resolve_tenant_by_slug` returns `id, slug,
  display_name, branding`; `plan` is kept off the anon path on purpose). So `[data-paid-only]` hides
  the logo for every shop there. **Seen live 2026-11-10: `rjbookstop.pulllist.app` signed out has
  its logo wrapper at `display: none`**, i.e. the paying shop's own sign-in page shows no logo. The
  code comment calls this the fail-closed direction; it is a cost, not a defect.
- **Readability, computed (WCAG contrast):** white text on the platform red `#e8321c` is **4.28:1**;
  `#e8321c` on the card background `#181818` is **4.15:1**. Amber `#f59e0b` on white 2.15, green
  `#22c55e` 2.28, yellow `#facc15` 1.53; dark blue `#1d4ed8` on `#181818` 2.65. A shop-picked color
  needs a floor, and 4.5:1 would reject the platform's own red.
- **Hardcoded reds** (`rgba(232,50,28,…)`, `#e8321c`): about 20. Some are **decoration** that
  should follow the accent (`style.css:372-373`, `:406`, `:601`, `:1282`; `mylist.html:59`, `:99-100`,
  `:131-132`; `settings.html:119`; `index.html:327`). Others mean **danger / risk / error** and must
  stay red whatever the accent (`admin.html:2290-2291`, `:3132`, `:3636`; `analytics.html:170`,
  `:207`, `:211`, `:217`; `style.css:1976` `.alert-error`). Emails keep platform colors on both
  tiers (F72 § 0.1). `app.js:95` is the PULLLIST mark, stays.

### 1.4 Settings page defects folded into S1

- **The page still opens with "Preview — these filters are not applied yet … Nothing you do here
  changes what anyone sees today"** (`settings.html:267`), served by production today. True at S2
  (2026-09-23), false since PR #159 (2026-09-29).
- **Page count assumes 46 rows per printed page** (`settings.html:330`, `:664`); the real print
  runs 44.0-44.3 (`admin-settings-catalog-visibility.md` § 5.2), so October predicts 49 pages for a
  50-page print.

---

## 2. Decisions

**All four ANSWERED 2026-11-10: Rick said "defaults", so each takes the recommended column.**

| # | Question | Recommended (default if Rick says "defaults") |
|---|---|---|
| **D1** | Is the color picker part of this work, and how many colors? | **Yes, one accent color.** Everything else stays platform-fixed |
| **D2** | Can a free shop pick a color? | **No, paid only** (pricing copy and F72 § 0.1). Consequence: `comicstore` (demo only) goes back to platform red |
| **D3** | Phone format | **One value, shown everywhere exactly as typed.** Ray & Judy's print sheets change from `973-586-9182` to `(973) 586-9182` (the emails already use the latter) |
| **D4** | Show a paid shop's logo and color on its signed-out sign-in page? | **Yes**, by having `resolve_tenant_by_slug` strip `primary_color` and `logo_url` for non-paid shops server-side (no `plan` exposed). Brings back Ray & Judy's logo there |

Defaults taken without asking (design rules):

- **Where it lives: `tenants` columns, written through admin RPCs.** The page already reads
  `tenants` on every load (`app.js:145`), so the footer and banners cost no extra request (an
  `app_settings` key would add one per page). The mail functions already read `tenants`.
  Writes go through narrow `SECURITY DEFINER` RPCs that touch only their own fields of the
  caller's own shop, never `plan` or `slug`, whatever the `tenants` UPDATE policy allows
  (the promo-banner plan avoided whole-row `tenants` writes for the same reason).
- **Fields:** phone (`contact_phone`), street address as printed on emails and sheets (new
  `postal_address`), town for the page footer (`location`, e.g. "Rockaway, NJ"), website (new
  `website`). **This supersedes Q2's `branding.website`** (a column the RPC writes and the
  functions can select; nothing on the anon path needs it).
- **Tier rules are unchanged:** paid shows phone, address, town, website; free shows the name, and
  the catalog email alone shows the address. A free shop may still enter all four (the catalog
  email needs the address); the panel says which ones its plan shows.
- **An empty field omits its line. Never fall back to Ray & Judy's text.**
- **No editor for email wording.** The sign-in and reset emails carry one-time links; shop-edited
  HTML is an injection and spam-filter risk for little gain.
- **Color readability floor: 3:1 against white (button text) AND against `#181818`** (cards).
  The platform red passes (4.28 / 4.15). Below the floor, Save is disabled with the reason shown.

---

## 3. Steps

Each step is its own staging build and its own `/promote-prod`. **Until S2 and S3 are on
production, do not set `plan = 'pro'` on any shop but Ray & Judy's** (runbook warning, Step 3).

### S0 — Read-only baseline (Rick-run, both projects, SQL Editor)

```sql
-- Q1: contact fields and branding keys per shop (public shop info, no secrets)
SELECT slug, plan, contact_phone, location,
       (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(COALESCE(branding, '{}'::jsonb)) AS k) AS branding_keys,
       branding->>'primary_color' AS primary_color
FROM public.tenants ORDER BY slug;

-- Q2: the names this plan adds are free (expect 0 rows each)
SELECT column_name FROM information_schema.columns
 WHERE table_schema = 'public' AND table_name = 'tenants' AND column_name IN ('postal_address', 'website');
SELECT proname FROM pg_proc
 WHERE pronamespace = 'public'::regnamespace AND proname IN ('admin_set_store_contact', 'admin_set_brand_color');

-- Q3: the live anon lookup body, so S4 edits what is actually deployed
SELECT pg_get_functiondef('public.resolve_tenant_by_slug(text)'::regprocedure);
```

Stop if Q2 returns any row.

**S0 results.** *Staging, 2026-11-10 (Rick-run; Q1 and Q2 as one combined query):* names free (0 / 0 on
every row). `raysandjudys` `pro`, phone `973-586-9182`, town `Rockaway, NJ`, branding keys
`promo_banner`, no color. `demoshop` `free`, `555-0100`, `Springfield, IL`, no branding.
`riverside-comics` and the four `pw-*` fixtures `free`; **`pw-2d3c4d60` and `pw-fc2e3fc7` carry
`primary_color` `#123456`** (Playwright fixtures; **at S4, check whether the local branding spec asserts
a FREE fixture's color applies, since D2 makes that false**; `#123456` also fails the 3:1 card floor).
Q3 body: `SELECT t.id, t.slug, t.display_name, t.branding FROM public.tenants t WHERE t.slug = p_slug`
(matches § 6.9). An unlabelled paste of the same Q3 output arrived too; it may be production's.
*Production, 2026-11-10 (Rick-run, the Q1+Q2 combined query):* `comicstore` `free`, `555-555-5555`,
`New Jersey`, branding keys `display_name`, `primary_color` (`#00FF00`); `rjbookstop` `pro`, phone and
town both **null**, branding keys `promo_banner`, no color. **The names check did NOT run before the S1
file:** it read `names_taken_cols` 2 and `names_taken_funcs` 1, so the S1 SQL had already been applied
on production when it ran. Run down, not assumed: an anonymous probe found `admin_set_store_contact` with
its four-argument signature refused by the grant (`permission denied for function`, 401) and no
`admin_set_brand_color`, and the S1 verdict query then read OK. So a pre-existing production object
using these names was never ruled out by the check itself; it is ruled out because the one function
present carries the S1 body marker and staging, which had the same history, read 0 / 0.

### S1 — Columns, the contact RPC, the Store contact panel, data fill (staging, then production)

**SQL** (file `docs/sql/<date>-store-contact.sql` at build time, STATUS line per F105; staging first):

```sql
BEGIN;
ALTER TABLE public.tenants
  ADD COLUMN IF NOT EXISTS postal_address text,
  ADD COLUMN IF NOT EXISTS website        text;

CREATE OR REPLACE FUNCTION public.admin_set_store_contact(
  p_phone text, p_postal_address text, p_town text, p_website text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_tenant uuid := public.current_tenant_id();
BEGIN
  IF v_tenant IS NULL OR NOT public.current_user_is_admin() THEN
    RAISE EXCEPTION 'not allowed' USING ERRCODE = '42501';
  END IF;
  IF length(coalesce(p_phone, '')) > 40 OR length(coalesce(p_postal_address, '')) > 200
     OR length(coalesce(p_town, '')) > 80 OR length(coalesce(p_website, '')) > 120 THEN
    RAISE EXCEPTION 'value too long' USING ERRCODE = '22001';
  END IF;
  UPDATE public.tenants SET
    contact_phone  = NULLIF(btrim(p_phone), ''),
    postal_address = NULLIF(btrim(p_postal_address), ''),
    location       = NULLIF(btrim(p_town), ''),
    website        = NULLIF(btrim(p_website), ''),
    updated_at     = now()
  WHERE id = v_tenant;
END $$;

REVOKE ALL ON FUNCTION public.admin_set_store_contact(text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_store_contact(text, text, text, text) TO authenticated;
COMMIT;
```

The SQL file adds a verdict query (one definition, `SECURITY DEFINER`, `search_path` pinned, both
columns present) that prints FAIL when the function or a column is missing, not a return signature.

**Client (`settings.html`, `app.js`):**
1. Rail: "Email Templates · Soon" becomes **Store contact** (live link). Branding keeps the page
   banner and catalog banner (and gains the accent color in S4).
2. Panel: four fields, Save / Discard like the banner panels, "last saved" from `tenants.updated_at`,
   per-field note of where it appears on this shop's plan, and a read-only preview of the page footer
   and the email footer as they will read. All rendering via `textContent` / `escapeHtml`.
   Client-side: phone accepts digits, spaces and `()+-.` only; website is stored without `https://`.
3. ~~`TenantContext`'s select (`app.js:145`) gains `contact_phone, location, postal_address, website`.~~
   **MOVED TO S3 (decided while building, 2026-11-10).** The panel reads the four columns itself, so
   S1 does not touch `app.js` at all. Widening `TenantContext` in S1 would have made EVERY signed-in
   page's tenant read fail on any environment where the S1 SQL had not yet run (a missing column is
   a 400), whereas the panel alone fails closed: it shows "could not be read" and disables Save.
4. **Separate commit:** remove the stale preview warning and its comment (`settings.html:264-272`) and fix
   the page estimate. ~~`ROWS_PER_PAGE = 44`~~ **44.5, not 44:** `ceil(rows / 44)` still gets four of the
   six measured prints wrong; any value from 44.31 to 44.95 matches all six, and the old 46 matched none.
   Label: "pages · about 44 rows each".

**Built 2026-11-10 on `feature/store-contact-s1`** (`6e1ab7c` the warning and estimate, `d1c64ac` the
panel and the SQL file). Local harness `playwright/store-contact-verify.mjs` (local-only): pre-SQL mode
11/11 on the working tree; negative control `emptyonfail` red on its three checks. ~~The full V1/V2 run
waits for the SQL on staging.~~

**S1 ON STAGING 2026-11-10 (merged `--ff-only`, staging tip `330af30`; NOT promoted).** The SQL was
applied by Rick (verdict OK; file STATUS `staging=APPLIED`). V1 + V2: harness **45/45 on the working tree
and 45/45 on the deployed bytes** (served `settings.html` equal to the committed blob on 3 consecutive
polls first): anon refused 401, signed-in non-admin refused 403 / 42501, admin write read back, plan /
slug / name untouched, the other shop's row untouched, over-cap refused 22001, blank stores NULL,
invalid phone / website block Save, Discard, hostile text shown as text, reload persists, the free-plan
view at 390 px with no horizontal scroll, both shops' fields and `updated_at` restored exactly, users
gone. **Negative controls, each red on its own gate:** `emptyonfail` (3), `innerhtml` (the injected
image was actually requested), `ignoreproblems` (2), `noclean` (red because an unclean
`https://…/` website then fails validation, so Save stays off and the run stopped early; teardown
re-read clean). A screenshot showed the "How it will read" heading at body size (the label rule
matched only `<label>`); fixed in `330af30`. **Full suite on the deployed bytes: 169 passed, 1 skipped,
0 failed, 28.4 min, `EXIT=0`** (the log's own summary line). ~~**Not yet done:** Rick's staging data fill
through the panel; production SQL and promotion.~~ **Staging data fill DONE 2026-11-10 (Rick, through the
panel), read back through the service role:** phone `973-586-9182` (**the dashed form, not D3's
`(973) 586-9182`**, which matters for S2's byte-identical footer gate V3), town `Rockaway, NJ`, street
address `40 W Main St. Rockaway, NJ 07866`, website `rjbookstop.com`, `updated_at` 2026-11-10T17:58:39Z.

**S1 ON PRODUCTION 2026-11-10 (PR #185, merge `cd264bd`, merged 22:13:50Z by Rick; promotion branch
parents `427df64` main + `5edc04b` staging tip).** Rick's `/promote-prod`. SQL applied on production
FIRST (verdict OK, see S0 production above; file STATUS `prod=APPLIED`). **Gates:** step 0 empty after
the STATUS update; merge result `settings.html` == staging's copy, `app.js` and every other page
identical on both branches, `config.js` == `origin/main` (prod ref x1, staging ref x0),
`supabase/migrations/` 2 files; PR file list read on GitHub: 7 files (`settings.html` plus docs),
MERGEABLE. **Verified post-deploy:** on BOTH `pulllist.app` and `rjbookstop.pulllist.app`,
`settings.html` (`2a733af7093cf612`, the same bytes staging served when the harness ran 45/45), `app.js`,
`config.js`, `catalog`, `mylist`, `admin`, `analytics` and `style.css` byte-identical to `origin/main`;
markers `admin_set_store_contact` x3, `id="contact-panel"` x1, `href="#store-contact"` x1,
`sc-rollout-note` x1, `ROWS_PER_PAGE = 44.5` x1, `preview-banner` x0; the one remaining
"Email Templates" is the panel's own code comment (the rail entry is gone). **Write-smoke skipped:**
admin-only Settings page, the diff never touches `Preorders` or the reserve path. **Not verified:** the
panel has not been used on production (no save there yet), Chromium only. **Still owed: the production
data fill** (Rick, through the panel), then a service-role read-back; Rick's phone-format choice for it
(D3's `(973) 586-9182` keeps S2's emails byte-identical to today's; the dashed form is what staging holds).

**Observed during S1, staging only, NOT changed (Rick's call pending):** the prints' "View Online"
reads `raysandjudys.pulllist.app` on staging, which does not resolve. `Tier.publicUrl()` is
`<slug>.pulllist.app`; production's slug is `rjbookstop`, which resolves (HTTP 200), and the print code
is identical on both branches, so production prints the right address. Pre-existing since F72 S3
(2026-09-04); F72 S0 had said "decide at S3 whether staging gets a provisioned hostname or is an
explicit exception", and no decision was recorded.

**Data fill, before anything reads the fields:** Rick enters Ray & Judy's values through the new
panel on each environment (this is also the panel's real test): phone `(973) 586-9182`, street
address `40 W Main St. Rockaway, NJ 07866`, town `Rockaway, NJ`, website `rjbookstop.com`. Read
back through the service role.

**Production order:** SQL → promote client → Rick fills the panel → read back.

### S2 — The six mail functions read the fields (staging, then production)

- `fetchTenantIdentity()` selects `display_name,plan,location,contact_phone,postal_address`
  (`register-customer:260` adds the same). Delete every `PAID_CONTACT_HTML` and the inline copy in
  `register-customer`.
- Paid footer = the escaped non-empty parts of `[postal_address, contact_phone]` joined with
  `' &middot; '`, so Ray & Judy's footer is **byte-identical** to today's literal after the data
  fill. `register-customer`'s "Questions? Call us at …" line appears only when a phone exists.
- `notify-customers`: postal address = `postal_address`, else `location` (today's behaviour), else
  422, for **both** tiers.
- Deploy one function at a time, `verify_jwt` read live first and preserved (F93); download each
  deployed artifact and hash it against the committed source.
- **Production order:** only after S1's data fill is read back on production.

### S3 — Web pages and prints read the fields (staging, then production)

- `TenantContext`'s select (`app.js:145`) gains `contact_phone, location, postal_address, website`
  (moved here from S1). Only after the S1 SQL is applied on that environment: a missing column makes
  every signed-in page's tenant read fail. `app.js` carries `merge=ours`, so assert its merge RESULT
  at promotion.
- Remove the Store contact panel's "Saved now, used soon" notice (`#sc-rollout-note`) in the same
  change, or it becomes the next stale claim.
- Footers: the `· Rockaway, NJ` span becomes a `[data-tenant-town]` hook filled by
  `Branding.apply()` (hidden when empty), keeping today's text as the default markup like
  `[data-tenant-name]`. **Change all seven footers in one commit and run the seven-page footer
  hash check.**
- Banners, pickup notice, poster, print headers: phone, address and website from
  `TenantContext.current()`; an empty value drops its line or clause.
- `rjbookstop.com` literals on the prints become `website`.

### S4 — Accent color (after D1-D4; staging, then production)

- **RPC `admin_set_brand_color(p_hex text)`**: admin-only, own shop, `^#[0-9a-fA-F]{6}$` or NULL
  (NULL clears to platform red), touches only `branding.primary_color` via `jsonb_set` /
  `branding - 'primary_color'`. With D2 = paid only, it refuses when `plan <> 'pro'`.
- **D4:** `resolve_tenant_by_slug` returns `branding - 'primary_color' - 'logo_url'` for a non-paid
  shop (edit the body read in S0 Q3, keep its grants). `Branding.apply()` then applies color and
  logo on the anon path as received, and on the signed-in path only when `Tier.isPaid()`.
  `[data-paid-only]` on the front-door logo wrapper is replaced by that rule.
- `--accent-hover` derived (lighter) instead of equal to the accent.
- Picker in Branding: color input plus hex field, live preview (a primary button, a link, the page
  header card), the 3:1 floor, "Use the platform color" to clear. Free shops see it locked with the
  same note style as the page-banner custom image.
- Decorative hardcoded reds (§ 1.3) become `--accent` mixes inside `@supports (color: color-mix(…))`
  with the red as fallback (the `var()` trap recorded at PR #167); danger reds stay red.
- **Data:** clear `comicstore`'s `#00FF00` (D2), or keep it if D2 changes.

---

## 4. Gates

| Gate | Step | Pass means |
|---|---|---|
| V1 | S1 | SQL verdict OK on the environment; anon call to the RPC refused (42501), a signed-in non-admin refused, an admin allowed (behavioural, like F173) |
| V2 | S1 | Harness: admin saves through the panel, a service-role read equals what was typed; blank clears to NULL; too long refused with a message; another shop's row unchanged; hostile text escaped in the preview; the stale warning gone; 44-row count |
| V3 | S2 | Template harness (the F72 V6 pattern): Ray & Judy's six footers byte-identical to the pre-change output after the data fill; a second paid fixture shows its own details and **no** Ray & Judy's text; paid with empty fields shows no contact line; free unchanged; `notify-customers` 422 rule |
| V4 | S3 | Ray & Judy's pages: rendered text identical before and after except the D3 phone format; a paid fixture shop shows its own details and zero Ray & Judy's strings (reuse `f72-demo-leak-audit.mjs`); seven footer hashes equal |
| V5 | S4 | Contrast floor blocks a failing color; free shop locked and RPC refuses; anon lookup strips free shops' color and logo; paid shop's color on the sign-in page and signed in; danger reds unchanged; layout shift unchanged |
| V6 | each | Full suite once on the deployed staging bytes before each promotion; write-smoke only where the reserve path is touched (S3 edits `catalog.html` / `mylist.html`) |

Each new assertion is seen red against the old bytes first.

## 5. Rollback

S1: the columns and RPC are additive (drop the function; leave the columns). S2: redeploy the
previous artifact (saved before each deploy). S3 / S4: revert the commit. S4's RPC change: re-run
the S0 Q3 body.

## 6. Out of scope

Editing email wording; colors other than the accent; a logo upload (logo stays operator-set);
moving Order Deadline / Maintenance Mode onto Settings; the 641-760 px nav overflow (F178).

## 7. Not verified when written

The 2026-09-01 contact values (re-read in S0); whether `tenants`' current UPDATE policy allows an
admin write (the RPCs do not depend on it); the logo and accent findings in § 1.3 were seen on
production signed out only, Chromium only.
