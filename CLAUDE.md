# CLAUDE.md — Project Instructions for PULLLIST

This file provides persistent context for Claude when working on the PULLLIST
comic pre-order system. **Read this file in full at the start of every session.**

---

## 🚨 Current Migration Phase

**Active phase:** none. Phase 5 closed 2026-07-15 (all sub-deploys 5.0–5.5 complete; see
`docs/phase-5-second-tenant-onboarding.md`). Phase 6 — open self-service tenant signup — is a
**stub only** (`docs/phase-6-self-service-signup.md`), not started, gated on a wildcard-DNS/TLS
spike.
**Active sub-deploy:** none.
**Next scheduled work:** none pending. **Sequencing reminder — window CLOSED 2026-08-28:**
production ran its real September import this session (`catalog_month` 2026-08 → 2026-09) — the
transition this reminder existed to protect has already happened, both environments. The
constraint is dormant until October's import opens the next one; no admin-ordering-surface work is
currently blocked. ***Residual CLEARED 2026-08-29 — Rick confirms production is serving customers,
so Step 8 (Maintenance Mode OFF) is done.*** *(This paragraph previously read "Residual, not yet
done: production's Maintenance Mode is still ON…" — written 2026-08-28 and left standing for a day
after it stopped being true, which is the same stale-claim pattern as F132/F138/F139/F145.)*
**One sub-item is still unconfirmed, and it is small but not cosmetic:** whether **Step 7** (set
`order_deadline`) was run. A live store with a cleared deadline is not broken, but per F108's
order-deadline-supersedes rule it changes what the At-Risk / Backorder panels classify, and it is
the ambient value F133's date-dependent specs trip over. **Check the value before trusting either
surface** — `app_settings` is not anon-readable, so it needs a service-role read or the admin
Settings screen.

**⏰ GATE SCHEDULED: October catalog import — target Fri 2026-09-25 (Rick, 2026-08-30).** One-time
cloud reminder armed for 12:00 UTC / 8:00 AM ET that day (`trig_01FQesEHRh9XdRXgwASFJoh7`,
`run_once_at` verified set, enabled). The date sits one day after September's `order_deadline`
(Thu 2026-09-24), so September's orders close first; it is a Friday, clear of the Tue/Wed
shipment-and-bagging window. **The stale September reminder was disarmed the same day**
(`trig_01QwSJJf65mYTy2mNkTYsSKk`) — it was still armed for 2026-09-07 to prompt work that
actually completed on 2026-08-28, and would have sent Rick to redo a finished import.

**October's import is an attended-session gate, not a formality.** Two fixes get their first-ever
live production exercise there: **F147**'s corrected FOC check (its mark half could not be
re-exercised this cycle — flipping `catalog_month` to `2026-09` closed the new-month window the
moment the run finished) and **F146**'s unconditional clear half (production holds 0 withdrawn
marks today, so there is nothing for it to act on until marking runs again). Both findings have
only ever fired once each, and both fired wrong — 519 marks and 16. Re-open the admin-ordering
freeze for that window.

**S0 CLOSED OUT 2026-09-02, later the same session — the data fix landed, `register-tenant` deployed
to BOTH projects, and V11's server half found a real discrepancy that turned out to be in the TEST,
not the code.**

**V13 done (Rick):** `UPDATE public.tenants SET plan = 'pro' WHERE slug = 'rjbookstop'` on
production. **Independently verified by a service-role read afterwards, not taken on trust:**
`rjbookstop='pro'`, `comicstore='free'`, **both exact lowercase.** That exactness matters — see the
residual below.

**`register-tenant` deployed to BOTH projects at Rick's explicit request** (staging v19→v20,
production v9→v10). Two things were measured rather than assumed:

1. **`verify_jwt` was determined by BEHAVIOUR, not a dashboard label**, and the probe is reusable: an
   unauthenticated POST to the function returns its **own** `{"error":"Unauthorized"}` body when
   `verify_jwt` is OFF, versus the platform gateway's `{"code":401,"message":"Missing authorization
   header"}` when ON. Both projects returned the function's body before **and** after each deploy ⇒
   OFF, preserved. Deployed with `--no-verify-jwt` (the CLI defaults to JWT **on**, so a deploy that
   ignores the current setting silently flips it — the F93 hazard, avoided by measurement).
2. **The deployed artifact was read back**, not inferred from the CLI's success line:
   `supabase functions download --workdir <scratch>` on both projects, then sha256 — both
   `458f31b1c4f24ea0`, **byte-identical to local**. The repo tree was never touched by the download.

**⚠️ `main`'s source is now BEHIND production's runtime.** Production runs S0's `register-tenant`
while `main` still has the hardcoded `plan: 'free'`. This is the F99 M6 drift shape, entered
knowingly: the deploy was explicitly requested and Edge Functions deploy from the working tree, not
from a branch. **The promotion PR is owed** — the divergence is small and clean (`app.js` and
`register-tenant` are the only code; the rest is docs, plus `config.js`'s expected per-branch
difference and F125's `supabase/migrations/` asymmetry). Not opened unilaterally: CLAUDE.md requires
production promotions be explicitly requested.

**V11 server half (V11s) — 7/7 on staging, and the first run FAILED for the right reason.** Four
throwaway tenants created through the real deployed function, read back service-role, then torn down
FK-ordered per the runbook, with **zero orphaned auth users** confirmed by fresh read (F130's own
failure mode, checked rather than assumed). Measured: `' PRO '` → `pro`, `'pro'` → `pro`, omitted →
`free`, `'paid'` → `free`.

**The first run asserted `'Pro'` should be REJECTED to `free`, and it failed.** The code lowercases
*before* the allowlist, so it **normalises** case and whitespace rather than rejecting them. **The
code was right and the test was wrong** — normalising honours the operator's evident intent while
still guaranteeing the column can only hold a value `Tier.isPaid()` matches exactly. The assertion
was corrected rather than "fixing" working code to satisfy a bad test; the plan doc's own § 4.0.1
wording, which had implied rejection, was corrected too.

**⚠️ RESIDUAL, and it is the more useful half of this result: `register-tenant` is not the only
writer, and today it is not even the main one.** `tenants.plan` is set **manually** (§ 6), and a
hand-written `UPDATE tenants SET plan = 'Pro'` bypasses normalisation entirely. The column is `NOT
NULL` with **no CHECK constraint**, so `'Pro'` would persist and `Tier.isPaid()` — testing
`=== 'pro'` exactly — would read it **false**: the tenant silently renders free while the operator
believes they set it paid. Production's current values are exact, so nothing is wrong today; this is
about the *next* hand-typed UPDATE. **Fix, raised for Rick's call, NOT applied:**
`ALTER TABLE public.tenants ADD CONSTRAINT tenants_plan_check CHECK (plan IN ('free','pro'));`

**Three local-only harnesses** (gitignored playwright folder, `f149-maintenance-verify.mjs`
convention): `f72-s0-tier-verify.mjs` (anon), `f72-s0-authed-verify.mjs` (authenticated read),
`f72-s0-plan-allowlist.mjs` (the server allowlist + teardown).

**Last completed work: F155 filed + S1 shipped + 15 PRODUCTION date corrections applied,
2026-09-04** (`8700a65`, `0f4be33`, `2e2feac`, all doc-only on staging, pushed). **⚠️ PRODUCTION DATA
WAS CHANGED** — 15 `catalog.on_sale_date` values, applied by Rick, independently re-verified by a
fresh read afterwards, not taken from the write script's own output. No code, no schema, no deploy.

**Found by Rick from a live symptom, not an audit.** A reserved title (DNX #1 [HIDDEN/DOUBLE COVER],
PRH `75960621519500111`) had quietly stopped being visible to its two customers. Root cause: PRH
revised its in-store date 2026-09-02 → **2026-09-16** and nothing we download carries that.

**Three silent stages, in order — the first is the one that actually hurts.** Once the *stale* date
passes, the title is in **neither** half of My List: it fails `mylist.html:937`'s current-month
table filter *and* `:884`'s future-dated Upcoming Arrivals filter. Then it never matches a bagging
week again. **Only then** does `auto_fulfill_past_on_sale()` mark it fulfilled and F115 surface it
in Never Arrived — after the customer has been told "Order placed" for a book that never shipped.
`classifyReservedDateDrift()` already computes this exact state (`import.js:517`, its `stranded`
list carries a `hidden` flag whose comment reads *"the customer cannot see it at all"*) — it simply
never ran, because nothing re-reads an older month.

**Why no admin panel caught it, and it is two correct behaviours colliding.**
`computeBackorderRisk()` (`admin.html:1749`) clears any code with `ledgerNetQty > 0` *before* every
other test, so an **ordered** title is invisible to Order Follow-Up. And Mark Ordered was correctly
`disabled` — ledger 2 = reserved 2, nothing left to order. Rick reported exactly this: "the title
was in Ordered status which locked the button." Neither is a bug alone; together they leave no
surface at all.

**The finding proper is one sentence in a runbook.** `monthly-catalog-refresh.md` Step 3 item 4 read
*"PRH's export omits withdrawn titles rather than revising dates in place (see F110), so this step
matters most for Lunar."* **Measured false:** freshly-downloaded PRH master data carries **108**
revised in-store dates in 2026-07 alone, plus 27 / 19 / 4 in 2026-06 / 08 / 09. That sentence is why
PRH months had never been re-pulled. **S1 fixed it 2026-09-04** (old text preserved verbatim in the
correction note, per convention).

**⚠️ The larger result, and it is a hard limit, not a gap to close: for a FROZEN PRH catalog no data
channel exists at all.** Measured four ways — (1) two downloads of 2026-05 master data 44 minutes
apart are **byte-identical** (MD5 `438958a0b69b961ab140ab63c9b3f3bf`) and **0 of 1,078** rows differ
from the May import; (2) May's Weekly Change Reports run 2026-04-24 → **2026-07-31 and stop**, and
DNX #1 is absent from the final one; (3) **0 of 5,123** PRH `MainIdentifier`s ever appear in more
than one monthly file, so F122's newest-listing logic cannot rescue one; (4) yet **84 May titles
were still future-dated**. PRH abandons a catalog ~2 months before its last titles ship. Detection
cannot solve this — only F155's S3 guard limits the damage. **Two new runbook items (5 and 6) record
this**, item 6 being the trap that F146's own withdrawal-clearing backfill would silently revert any
hand-correction, which nothing had said anywhere.

**Lunar is the opposite, and better than the plan first assumed.** The *All Products CSV Order Form*
export is **one file, 17,490 rows, every catalog month back to 2025**, with an `In-Store` column —
covering **559 of 568 (98.4%)** codes holding open reservations in a single download. It surfaced
**13** already-stale dates immediately, including `0826DE0733` FIRE AND ICE #5 moved 2026-10-28 →
**2026-09-30**, i.e. a month *earlier* — the direction nothing watches, where a book arrives before
the bagging list expects it. **It is a DIFFERENT schema and cannot be fed to `import.js`** (item 1
now says so).

**The remediation ran ahead of the plan because `auto_fulfill_past_on_sale()` runs WEEKLY** —
measured 2026-08-07 / 08-14 / 08-20 / **08-28**, and the last run was a week overdue. Local one-off
`scripts/fix-stale-dates-f155.js` (untracked, matching `clear-f147-withdrawn.js` and
`f115-s6-backfill-unknown.js`, its two closest siblings): production-only guard, live re-derivation,
before-state JSON written *before* any write, sanity band, single y/n, independent fresh re-read as
the success check. 13 Lunar derived live + 2 PRH from a declared provenance table (PRH site +
invoice, Rick's own read — there is no file). **9 Lunar codes reported and deliberately SKIPPED** —
absent from the export because it lists *available* products (mostly 1:25–1:500 incentives); no
authoritative date, so no guess.

**⚠️ One known residual, not closed: `0726DC0300`** (DC CONNECT #76 bundle, on-sale 2026-09-02) is
still stale and **will be falsely fulfilled at the next weekly run.** No source exists for it. Low
impact (a free promotional bundle), but open rather than fixed.

**S3 APPROVED by Rick, 2026-09-04, and it knowingly revisits a recorded decision.** F115 Option A —
giving `auto_fulfill_past_on_sale()` an arrival check — was **rejected**, and `import.js`'s own
`findUnverifiedFulfillments()` docblock states why: *"REPORTS, NEVER BLOCKS … gating fulfillment on
this would trade a silent miss for a silent stall."* **That objection stands**, so S3 **defers,
bounded** (14 days) rather than blocking, and ships together with the `computeBackorderRisk()`
ordering fix that keeps deferred rows visible in Never Arrived. Without that second half S3 would
recreate the exact stall F115 rejected. **When S3 lands, record the approval in
`f115-arrival-truth-persistence.md` too**, so a reader of its "Option A was rejected" line finds the
follow-up instead of re-deciding it.

**Plan: `docs/f155-catalog-date-revision-detection.md`** (STATUS: IN PROGRESS — S1 done, S2/S3 not
started). **Nothing in it depends on a catalog load; all of it can be built before October's
import.** But the **2026-09-25 October gate already carries F146 and F147's first-ever live
production exercise** — both have fired exactly once each and both fired wrong (519 and 16) — so
**recommended, Rick's call: S1 + S2 to production before 09-25 (S2 actively de-risks it by cleaning
stale dates going in), S3 to staging now with its production promotion held until October is
verified green.** **F155 is the finding this consumed. F156 is the next free ID.**

**Prior work (2026-09-04, earlier): F72 S3 — print outputs tier-gated, GREEN on STAGING** (`b1e1445`,
merged `--ff-only`, pushed). Closes the last open item from this session's F72 work — every paper
output a customer or staffer could hold now follows the same rule S1a/S2a already established.

**Seven print surfaces across three files.** `mylist.html`'s personal-list header and
`arrivals.html`'s This Week header were both fully static markup carrying the founding tenant's
name and phone — unlike `print-title`/`print-subtitle`, nothing had ever made them dynamic.
Converted both to an empty `#print-store-info` container, populated via `textContent` (never
`innerHTML`) at print-click time, matching `Branding.apply()`'s own `[data-tenant-name]` convention
so there's no new HTML-escaping surface. `arrivals.html`'s store poster needed **zero new JS** — its
name was already dynamic, and the two static phone spots just needed `data-paid-only`, which
`Branding.apply()` already applies to every nav page at load time. `admin.html` carried three
separate print jobs — Bagging List, Print Catalog, and a staff-only Reserved Report — each now
tier-gated the same way, with the tier computed once per render rather than per row.

**`rjbookstop.com` (the tenant's own website) still has no backing field** — Q2 remains unresolved,
unchanged from the original 2026-09-01 inventory. Kept as a paid-only literal, matching the one
paid tenant's real value; free tier shows nothing for it.

**Verified against DEPLOYED staging bytes, and a real gap surfaced along the way — not the tier
logic, a test-fixture limitation.** `f72-s3-print-verify.mjs` drove both a FREE customer
(`demoshop`) and the PAID founding tenant through `mylist.html`'s print path: free correctly shows
no phone, no founding name, `View Online: pulllist.app`; paid is **unchanged** — phone and name
both still present, `View Online: raysandjudys.pulllist.app`. `arrivals.html`'s free branch first
came back empty, which traced to a **pre-existing, unrelated** early-return: the print handler only
attaches when the customer has a reservation arriving in the current calendar week — confirmed by
checking that even the *pre-existing* title/subtitle population (untouched by this work) also never
fires without one. Verified for real by temporarily shifting one catalog row's `on_sale_date` into
the current week, reserving it, checking, and restoring the original date — confirmed restored by
an independent fresh read afterward, not the harness's own printed claim.

**⚠️ Stated honestly, not glossed over: `arrivals.html`'s paid branch and all three `admin.html`
print surfaces were not independently live-clicked.** Each uses the identical `Tier.isPaid()`/
`Tier.publicUrl()` pattern already proven correct live elsewhere this session, and `node --check`
confirms every file's inline script is syntactically valid — but manufacturing a live "Bagging List
has cards" / "Print Catalog has rows" scenario for each was judged disproportionate to the risk for
simple ternary string construction reusing an already-proven mechanism. Worth a real click-through
before this is treated as fully closed.

**Gates.** `node --check` clean on all three files. Unit suite 279/279 (unchanged). **Full
Playwright suite: 143 passed, 0 failed, exit 0, 22.2 min** — run directly against deployed staging
bytes post-push. Zero regressions from this step.

**This closes F72's session-scoped work.** S1a (web), S2a (`register-customer` email), and now S3
(print) together mean a free-tier prospect walkthrough — signup, browse, reserve, print, my list,
arrivals, subscriptions — carries zero founding-tenant identity anywhere reachable in that flow.
**Still open, deliberately deferred, not forgotten:** the other five mail functions
(`approve-customer`, `invite-customer`, `notify-customers`, `reset-password`, `send-my-list`)
remain unconditionally founding-branded. **Production untouched. No finding ID consumed** — this
advances F72, which already owns the work.

**Last completed work: F72 S1a + S2a — free-tier-first resequence, GREEN on STAGING, 2026-09-03**
(`d7669b0`, `efadbf0`, both merged `--ff-only`, pushed). Rick's direction: *"ship free-tier-only
first — let's focus on this and get something we can leverage with potential customers."* Both
sub-steps are now doc'd byte-exact in `docs/f72-multi-tenant-branding.md` § 4.1a/§ 4.2a.

**A demo tenant exists on staging, reachable today with NO DNS work.** `demoshop` / "Capital City
Comics", `plan = 'free'`, 2,288 real catalog rows copied from the founding tenant's current month.
`TenantContext` already resolves `?t=<slug>` (pre-existing, `app.js:113-127`) — so
**`https://staging.pulllist.pages.dev/?t=demoshop`** reaches it. This means F145's no-wildcard-DNS
finding does **not** block a free-tier demo at all — only the *paid*-tier subdomain link does (§ 0.1
Q9, unchanged). **Decided the same session:** the apex marketing page stays the free-tier front
door — `?t=` does not flip to the branded sign-in — because free tier's own pricing copy already
promises *"the shared `pulllist.app` front door,"* and giving `?t=` a branded door would hand free
tier one of the two things "Branded" currently sells.

**S1a — every screen-flow page a prospect walks through is now clean.** `Branding.apply()` gained a
general `[data-paid-only]` hook (simpler than § 4.1's per-field design — omits entirely rather than
filling a value) applied to: the six nav-page footer localities, `mylist.html`'s pickup-notice
phone, and `index.html`'s tenant-logo block. The three JS-built pending/paused banners
(catalog/mylist/subscriptions) and the welcome modal now branch on `Tier.isPaid()` — free tier shows
the tenant's own resolved name and drops the phone; paid keeps today's exact copy. Two unwrapped
`index.html` literals (invite-banner greeting, trust-signal line) wrapped in the existing
`[data-tenant-name]` pattern.

**A found-during-the-work leak, not in the original inventory: `index.html`'s default tenant logo
IS Ray & Judy's actual logo file**, not a generic PULLLIST mark — and it's reachable *today* via
`comicstore.pulllist.app` (free tier, individually provisioned per F145). Image content, so a text
grep would never have caught it; found by reasoning about what `Tier.isPaid()=false` actually
reaches. Fixed by marking the whole logo wrapper `data-paid-only`.

**A real CSS trap found and fixed in the same mechanism:** `[hidden]` alone would have silently
failed on `index.html`'s logo wrapper, because that element carries its own inline
`style="display:flex"`, and an inline style outranks the UA stylesheet's un-`!important`
`[hidden]{display:none}`. `Branding.apply()`'s paid-only gate now sets `style.display = 'none'`
explicitly, not just `.hidden`.

**Verified against DEPLOYED staging bytes with a real browser, not a source grep — before: 7 of 7
demo-tenant pages leaked; after: 0 of 7.** Local uncommitted harness `f72-demo-leak-audit.mjs`
signed in as a real throwaway customer in both `pending` and `active` states and scanned rendered
`innerText` across catalog/mylist/arrivals/subscriptions for the founding tenant's identity. A
second harness (`f72-s1a-founding-verify.mjs`) confirmed the PAID branch is unaffected — Ray &
Judy's own footer locality and pickup-notice phone are both still **visible**.

**S2a — `register-customer` (the one email a demo prospect actually receives) is now
tenant-aware.** The tenant's own `display_name` now appears in the **from-name, subject and
greeting for every tenant, both tiers** — this was hardcoded to "Ray & Judy's Book Stop" for every
signup regardless of which shop the customer signed up for, which is F72's actual defect, not
merely a missing free/paid split. `isPaid` gates only the phone/address footer. A minimal
`escapeHtml()` was added — `display_name` is admin-set, not user-submitted, but this change is the
first time it reaches an HTML email body via interpolation, and closing that latent injection
surface cost four lines.

**Verification hit a real, documented limit and was rerouted rather than skipped.**
`register-customer` checks Turnstile **before** the tenant lookup, so a scripted signup cannot
reach this logic via HTTP — the same limitation `native-signup-verify.mjs` already records for this
exact function. Built `f72-s2-template-verify.mjs` instead: extracts `buildPendingEmail()` from
both the pre-edit original (`git show HEAD`) and the edited file, strips only the TS type
annotations, and runs both. **Result: the edited PAID-tier output is BYTE-IDENTICAL to the
original's unconditional output — proven by string equality, not eyeballed** (V6). Free-tier output
confirmed to carry the tenant's own name and the magic link, and none of the founding tenant's
name/phone/address/city. A hostile display_name (`Bob's <Comics> & Co`) confirmed HTML-escaped.
Negative-control tested.

**Deployed to staging with `--no-verify-jwt`, F93-preserved and hash-verified** — an unauthenticated
POST returns the function's own body-validation error before and after deploy (`verify_jwt` OFF,
confirmed by behaviour, correct for a public endpoint); deployed source read back via `functions
download --workdir` and hashed identical to committed source (`bb0a3a51599a12f4`).

**⚠️ Honest limit, left open rather than closed out: final delivered-inbox verification did not run
this session.** Every prior F99 email-header check in this project read a real inbox; this session
has none available. What's verified is that the function *constructs and would send* the correct
payload; what's *not* verified is real-client rendering or actual delivery. **Needs Rick** — same
gate every prior instance of this check required.

**Gates, both sub-steps.** `node --check` clean on `app.js` and every inline `<script>` block across
all seven touched HTML files. Unit suite 279/279 (unchanged — no import-script code touched). **Full
Playwright suite: 143 passed, 0 failed, exit 0, 22.0 min** — run directly (not through an agent
PowerShell tool, per the 2026-08-30 note), against deployed staging bytes post-push, after BOTH S1a
and S2a had landed. Zero regressions from either change.

**⚠️ Answering Rick's actual question directly: is the demo ready to show a prospect right now?**
**Yes, for a self-guided or screen-share walkthrough of signup → browse → reserve → my list →
arrivals → subscriptions**, all on `?t=demoshop`, zero founding-tenant leaks. **Not yet safe for:**
(1) the admin **approving** the demo signup — `approve-customer` is still unconditionally
founding-branded, so that email would say "Ray & Judy's Book Stop" to the prospect; (2) any of the
other four mail functions (`invite-customer`, `notify-customers`, `reset-password`,
`send-my-list`); (3) any print output (bagging list, catalog print, pickup slips) — unreachable from
a screen-share demo, but real if a physical handout is ever part of the pitch.

**Two things carried forward, both deliberate deferrals, not gaps found late:** `admin.html`'s print
outputs and the other five Edge Functions remain founding-branded — S1a/S2a intentionally shipped
the narrowest slice that makes a *screen-flow* demo clean, not the full S1/S2. **Production
untouched. No finding ID consumed** — this advances F72, which already owns the work. **F153
remains the next free finding ID.**

**Last completed work: F72 S0 — the tier mechanism, GREEN on STAGING, 2026-09-02** (`cadd35b`,
merged `--ff-only`, pushed). Later the same day as the F99 promotion below, Rick's explicit
direction to move toward *"a unique custom platform for new tenants… onboard new tenants based on
their branding and identify for a paid tier environment."*

**The plan was resequenced first, in the same session** (`9a87b73`, doc-only).
`docs/f72-multi-tenant-branding.md` went from three steps to four: **S0 is new and now first.**
§ 0.1 had named it only as *"implied, not yet written up as steps."* Two decisions were taken and
recorded as **Q10/Q11** — see that doc, which is the live record for all of F72. **Q10:** paid-tier
email means footer identity + a branded "View Online" link over a **flat sender for both tiers** —
no new DNS, no domain slot, F99's addressing decision untouched; its consequence is that
`index.html:247-262`'s *"customer emails from your shop"* pricing claim is now knowingly stale and
is an S4 edit. **Q11:** the tier check ships as six byte-identical Edge Function copies gated by a
grep (V10) rather than a new cross-function import convention — there is no `_shared/` folder and
**zero cross-function imports exist**, and F99 S1 set the precedent by duplicating its
`MAIL_FROM_*` constants six times.

**S0 deliberately changes no rendered byte on any surface**, and that is its headline property, not
a caveat: it makes the system able to *identify* a paid tenant without acting on that identity
anywhere. All 18 Tier-A client sites, 6 Tier-B footers and 6 email templates are untouched. **`Tier`
has zero call sites** — S1/S2/S3 are what consume it. Shipping the branch's *input* first turns
those three into mechanical edits against a proven helper; shipping it last would have meant
reopening every S1 site.

**What landed.** `app.js`: the authenticated tenant read widened to include `plan` (RLS already
permits it — row-level, no policy change, no RPC change), plus a new `Tier` helper (`isPaid`,
`publicUrl`) reusing the existing `TENANT_APEX`. **`resolve_tenant_by_slug` was deliberately NOT
widened**, so `plan` never reaches the anon path and no anon-reachable surface can tier-gate —
5.3 § 1.5's projection boundary preserved, and confirmed live (V12: an anon-resolved tenant's keys
are `id`/`slug`/`display_name`, with no `plan`).

**`Tier` fails CLOSED, and the direction is the whole design.** Unresolved tenant, missing `plan`,
mis-cased `'Pro'`, `'paid'`, `''`, and the anon path all read as **free**. Free is the safe render;
a wrong *paid* render emits `<slug>.pulllist.app`, and **F145 measured there is no wildcard DNS
behind that name** — an unprovisioned paid tenant would put a non-resolving URL on customer paper.

**A real gap found during the work, not previously recorded anywhere:**
`register-tenant/index.ts:148` hardcoded `plan: 'free'` and no runbook step set it afterwards — so
**there was no supported path to create a paid tenant at all.** It now takes an allowlisted `plan`
input (`'free'` default, `'pro'`); **allowlist, not pass-through**, because the column is `NOT NULL`
with **no CHECK constraint**, so a typo like `'Pro'` would persist and read as free forever while
looking paid to an operator inspecting the row.

**`tenant-onboarding-runbook.md` — four edits, one of which is a live bug fix.** `plan` added to
Step 0 inputs and the Step 1 body; Step 3's hostname provisioning marked **REQUIRED for
`plan = 'pro'`** with the consequence stated plainly; a plan-verification line added to the go-live
checklist. **Step 2's SQL was wrong** — it told operators to write `display_name` into the
`branding` jsonb, but `Branding.apply()` reads the `display_name` **column** (`app.js:186`) and
ignores the jsonb key entirely; production's `comicstore` still carries that ignored key today.

**Gates.** `node --check` clean; unit suite **279/279, exit 0** (unchanged — no import-script code
touched); **zero HTML files in the diff**; the only deletion in the entire `app.js` diff is the
select line it replaces. **V9/V11/V12 green — 11/11** in a local, uncommitted harness
(`playwright/f72-s0-tier-verify.mjs`, same convention as `f149-maintenance-verify.mjs`) run against
the **deployed staging bytes**, confirmed served on the plain URL first (not a cache-busted one).
**Three assertions were negative-control tested** by inverting them and observing red, then
reverted.

**V8 — the full suite came back 139 passed / 1 flaky / 3 FAILED (30.1m), and the three were run
down rather than waved through.** All three are **timeouts**, two of them explicitly `while setting
up "authenticatedPage"` — the fixture's own documented signature for magic-link pressure (**F107**)
— not assertion failures: `21-arrival-resolution:225`, `:254`, and
`22-f143-f144-ordering-rejections:203`. **A targeted re-run of both specs passed 10/10 in 1.8m.**

**S0 was exonerated positively, not by assuming it was innocent.** The only mechanism by which S0
could break an authenticated page is the widened `tenants` select — if `plan` were not readable by
the `authenticated` role that query would 400, and `TenantContext` would silently degrade. **The
first verification pass never tested this**: V9/V11/V12 all ran on the **anon** path, which never
selects `plan` — a real gap in the gate design, found only by taking the failures seriously instead
of pattern-matching them to a known-flaky story. A second local harness
(`playwright/f72-s0-authed-verify.mjs`) drove a real magic-link sign-in and measured it: **both
`/rest/v1/tenants` requests returned 200**, the authenticated tenant carries `plan`, zero console
errors, throwaway user torn down clean. **Staging's founding tenant is `plan = 'pro'`**, so
`Tier.publicUrl()` returns `raysandjudys.pulllist.app`.

**⚠️ Worth carrying into S3:** `raysandjudys.pulllist.app` is **not a provisioned hostname** — only
`rjbookstop` and `comicstore` are (F145). Harmless today (zero call sites), but the moment S3 prints
that link, staging's own founding tenant would emit a non-resolving URL. Decide there whether
staging gets a provisioned hostname or is treated as an explicit exception.

**Honest limit on the F107 attribution:** no 429 was observed directly. What is demonstrated is that
the failures are timeouts rather than assertions, that they do not reproduce on a targeted run, and
that S0's only causal mechanism is measured working. The failures are **not attributed to this
change**; the underlying full-suite fragility is test-infra, same bucket as F107/F130/F133.

**⚠️ OPEN, and it gates S1 rather than this step: production's `rjbookstop` is marked
`plan = 'free'` although it is the real paying tenant.** `UPDATE public.tenants SET plan = 'pro'
WHERE slug = 'rjbookstop';` — **Rick's step, not the agent's.** Safe to run now and it should be:
with `plan` read by zero lines on production, the UPDATE is inert until S1 lands, so doing it early
de-risks the sequence instead of making it a launch-day step. **Staging also needs a durable
`free`/`pro` tenant pair** for V3/V4 — the only `free` tenants today are the ephemeral `pw-*`
fixtures (F130). **`register-tenant` has NOT been redeployed** — its `plan` input is code-only until
Rick deploys it, and per F93 discipline its live `verify_jwt` must be **read from the dashboard
first** (the in-file docblock claims OFF; CLAUDE.md's own platform-facts line was wrong about
`verify_jwt` once already).

**S1/S2/S3 remain design-level and must NOT be executed from their current text** — they still owe
the free/paid-content-per-site pass. **Production untouched. No finding ID consumed** — S0 advances
F72, which already owns this work. **F153 remains the next free finding ID.**


**Last completed work: F99 Resend MIGRATION — M6/M7 GREEN on PRODUCTION, 2026-09-02.** Same day as
M1–M5 below, later, **Rick's explicit request** ("start M6/M7"). Promoted via **PR #148** (staging
`85ce9ce`/`162fd40`/`d5e6ea1` → production merge `4a4a475`, `/promote-prod` skill used end to end).

**A real surprise surfaced during the merge, not a formality: production's `main` had never actually
received F99 S1's parameterization.** Every prior promotion since 2026-08-31 (F149's, explicitly
recorded — "F99 S1's Edge Function changes deliberately excluded, confirmed byte-identical to
`main`" — and by the same pattern presumably the others) had deliberately restored the six mail
functions to their pre-S1 hardcoded-literal state after merging, mirroring `config.js`'s own
preservation step. So the merge conflicted on all six files — production still had
`{ email: 'noreply@mrcyberrick.us', name: "..." }` object literals, staging had moved through both
S1 (parameterized secrets) and this migration's M2 (Resend request shape). Resolved by taking
staging's side wholesale (`git checkout --theirs`), verified byte-identical to `origin/staging` by
hash before committing — this promotion is therefore the one that finally carries S1 to production
too, not only the Resend cutover. F125 tree-integrity checks all green: `supabase/migrations/` still
exactly 2 files, `config.js` still the prod ref, PR file list matched intent on GitHub itself (12
files — six functions + `CLAUDE.md` + 5 docs; no `config.js`, no migrations).

**Secrets set by Rick, one deliberate difference from staging:** `RESEND_API_KEY` **reused the same
key as staging** rather than a fresh dedicated one (staging's M1 had used a fresh key; production's
M6 didn't — his explicit call both times, digest-confirmed). `MAIL_FROM_EMAIL` →
`noreply@pulllist.app`, `MAIL_FROM_NAME` unchanged. All six functions deployed with `verify_jwt` read
live pre-deploy and preserved exactly (`approve-customer`/`send-my-list` ON, other four OFF — matches
staging and this doc's own record), re-confirmed identical post-deploy.

**M7 — real production send, authentication fully clean, but a real finding surfaced anyway.** A
`reset-password` send to a real Outlook address: `dkim=pass header.d=pulllist.app` (verified) **+**
`header.d=amazonses.com` (verified), `spf=pass smtp.mailfrom=send.pulllist.app`, `dmarc=pass
action=none`, and Microsoft's own **`compauth=pass reason=100`** — every technical check this gate
asks for passed. **The message landed in spam anyway.** Not a K1–K6 kill-criterion trip and not a
gate failure — filed as **F152** rather than either ignored or treated as blocking: reads as a
cold-start reputation cost specific to `pulllist.app`'s near-zero prior send history with Microsoft
(unlike `mrcyberrick.us`'s years of it), not confirmed as the sole cause. Gmail and a third-party
relay (`jellyfish.systems`/`privateemail.com`) both delivered cleanly earlier this session — only
this one Outlook send has been observed going to spam. Mitigated by `forgot-password.html:194`'s
**pre-existing** "Didn't get it? Check your spam folder, or send again" copy, verified in code, not
assumed — Rick's own read, confirmed accurate before accepting it. **Rick's explicit call: monitor
real customer traffic over the following days/weeks, do not act unless it doesn't self-resolve.**

**Write-smoke deliberately skipped** — this promotion's entire diff is six Edge Functions plus docs,
never `app.js`/HTML, never the customer reserve path; confirmed from the diff itself before deciding,
not assumed. **Both environments now fully cut over, serving from `noreply@pulllist.app` via
Resend.** MailerSend's credentials remain set on both projects, undeleted, as a dormant rollback path
(plan's optional M8, not scoped this session). **No finding ID consumed for the migration itself —
F152 is a separate, related discovery, filed not fixed.** See § 13 F99 and F152.

**Prior work (2026-09-02, earlier the same day): F99 Resend MIGRATION — M1–M5 GREEN on staging.**
`docs/f99-resend-migration.md` executed end to end: `RESEND_API_KEY` set
(fresh dedicated key, Rick's call over reusing the discovery session's key), all six Edge Functions
(`approve-customer`, `invite-customer`, `notify-customers`, `register-customer`, `reset-password`,
`send-my-list`) rewritten to Resend's exact request shape (endpoint, auth header, `from` as a
string, `to` as a plain email string), deployed with `verify_jwt` read live and preserved per
function (`approve-customer`/`send-my-list` ON, the other four OFF — unchanged). Staging's
`MAIL_FROM_EMAIL` flipped to `noreply@pulllist.app`, landed together with the code deploy so the
predicted loud-failure window never occurred; `MAIL_FROM_NAME` unchanged (brand name doesn't depend
on provider). **Two real sends confirmed clean from delivered headers, at two different receiving
MTAs:** `reset-password` (Gmail) and `invite-customer` (`jellyfish.systems`/`privateemail.com`,
triggered by Rick from the live admin panel, substituting for `register-customer` — that path needs
a live Cloudflare Turnstile token this session cannot produce, and staging has no real
tenant-hostname URL to reach its UI at all, confirmed in code: `*.pages.dev` is hard-coded to the
apex bucket in `index.html`'s pre-paint script. Accepted as a residual, Rick's explicit call, same
disposition F149 already established for this exact class of check). Both sends: `dkim=pass
header.i=@pulllist.app header.s=resend` (exact match), `spf=pass` aligned via `send.pulllist.app`,
`dmarc=pass`, correct `From:`, no rewritten links, no tracking pixel. **Magic-link auth path traced
in code, not assumed:** no separate Supabase-native mail path exists anywhere in the app
(`signInWithOtp`/`resetPasswordForEmail`/`inviteUserByEmail` are never called client-side) — this
migration already covers 100% of PULLLIST's outbound mail. Full regression suite green post-push:
279 unit + 143 Playwright, 0 failures, exit 0, 22.1 min. **Production untouched — MailerSend keeps
serving `mrcyberrick.us` unmodified; M6 (production promotion) requires Rick's explicit separate
request**, same as every other production promotion in this project. No finding ID consumed.

**Prior work (2026-09-02, earlier the same day): F99 Resend discovery — GREEN, provider DECIDED.**
Same day as the S3-B session below, later. `docs/f99-resend-discovery.md` executed end to end against a real,
brand-new Resend account: domain verified, real sends made and read from delivered Gmail headers
(never the API's own success response), K1–K6 all evaluated. **Production untouched throughout** —
no MailerSend domain/token/secret was touched, no Edge Function changed; everything ran on a new
Resend account and additive Cloudflare DNS on names MailerSend never consults.

**Phase 1 (no DNS) tripped K1+K3 on the sandbox sender, and that triggered re-verification, not an
immediate remediation.** Sending from Resend's shared `onboarding@resend.dev` came back with links
rewritten through an AWS-SES tracking redirector and an injected open-tracking pixel — on its face a
kill. Traced to `resend.dev` — Resend's own domain — already having a tracking subdomain configured,
something only a domain owner can set up, confirmed three ways: Resend's own API docs state
`open_tracking`/`click_tracking` are "only applied if a `tracking_subdomain` is configured"; the live
Add Domain screen showed that field empty with both tracking checkboxes greyed out; and the real
test — sending from our own verified domain with no tracking subdomain ever configured — came back
completely clean. **K1/K3 do not apply to `pulllist.app`.**

**Phase 2 verified `pulllist.app` (the parent, not a subdomain — deliberately, to test the
free-forever hypothesis) and measured alignment stronger than Brevo achieved.** `dkim=pass
d=pulllist.app` — exact match, not merely aligned — **and** `spf=pass` also aligned via
`send.pulllist.app`'s organizational domain; `dmarc=pass`. Domain verification covers arbitrary local
parts (same as Brevo, unlike MailerSend's `#MS42207`). The apex SPF MailerSend's `spf=pass` depends
on was never touched — every DNS record Resend requested (`resend._domainkey`, `send`) landed on new
names, confirmed via `dns.google` before and after publishing.

**D7 — the pivotal test — came back negative, and it changed the addressing decision immediately
rather than at a deferred tenant-#2 milestone.** Sending as `noreply@rjbookstop.pulllist.app` with
only the parent verified was rejected: `403 validation_error — "The rjbookstop.pulllist.app domain
is not verified."` The opposite of MailerSend's own subdomain-coverage result. Unlike MailerSend's
unresolved `#MS42207`, this error names exactly what's wrong. Consequence: per-tenant subdomains
would cost a second domain slot (Pro, $20/mo) starting **today**, not at some future tenant #2 — so,
per the standing "prioritize the free tier, don't auto-upgrade" rule, **Rick decided flat
`noreply@pulllist.app`** for the migration; per-tenant subdomains remain a future paid choice, not
the default.

**F148 measured, not fixed:** Resend's cap meters emails, not requests (the opposite of MailerSend's
shape) — `notify-customers`' code unchanged keeps the daily ceiling at ~100/day (unchanged from
today), but the monthly ceiling rises 500→3,000. Pay-as-you-go overage ($0.90/1,000) exists, verified
against Resend's own pricing page, but only on paid tiers — not Free.

**Two new doc-only artifacts, no code touched:** `docs/f99-resend-migration.md` — the actual cutover
plan (six Edge Functions, mechanical `from`/`to` shape diff measured from the live code, not
assumed), written and **not started**; and this session's updates to `docs/f99-resend-discovery.md`
(STATUS → COMPLETE), `docs/f99-sender-domain-consolidation.md` § 10 (direction → decision), and
`docs/technical-reference.md` § 13 F99. **No finding ID consumed** — external platform evaluation,
same disposition as every other step in this thread. **F152 remains the next free finding ID.**

**Prior work (2026-09-02, earlier the same day): F99 S3-B — Brevo transactional EVALUATED and
REJECTED; direction set to Resend.** Doc-only session (`1610328`, staging). No code, no DNS, no
MailerSend change — **production untouched throughout, and there is nothing to roll back.** Both of
Rick's alternatives to the failed S3 attempt were explored and closed on evidence.

**(1) Brevo transactional — REJECTED.** Rick's idea, and the reasoning was sound: Brevo already
sends the weekly newsletter, already has `rjbookstop.pulllist.app` authenticated, and moving there
would collapse *both* splits F99 names — domain **and** provider — with no parallel-run problem.
**Three live sends ran against the real Brevo account while MailerSend kept serving production**,
verified from **delivered Gmail headers**, never the API's own `201`. Test A (the newsletter's own
sender) and Test B (`noreply@`, never registered as a sender) both delivered — proving transactional
is active with no support ticket, and that domain authentication covers arbitrary addresses, with
**strict DKIM alignment (`d=rjbookstop.pulllist.app`)**. Two feared blockers were false alarms: no
"Sent with Brevo" free-tier sticker on any send, and no activation ticket required. **Test C killed
it:** Brevo rewrote **every link, password-reset links included**, through its own `sendibt2.com`
click redirector — and explicitly declines to disable it (*"Link tracking enables us to keep the
platform secure"*). **One root cause, not three:** Brevo does not distinguish transactional from
marketing on the API/SMTP interface, so transactional also inherits a one-click `List-Unsubscribe`
(on password resets) and an injected tracking pixel. **Recorded precisely: `reset-password`'s
`hashed_token` design still holds** (consumption is a client-side `verifyOtp`), so this is a
credential-handling and trust problem, not a functional break — still disqualifying, because a
one-time reset credential would transit and be stored by a third-party tracker, and the visible link
in a security email would point at a domain the customer has never seen.

**(2) A second free MailerSend account — CLOSED, an explicit ToS violation.** Terms of Use § 11.1
forbids multiple accounts by a natural person, § 11.2 requires all domains under one account, § 13.1
permits suspension. **The exposure is not the throwaway account — it is the EXISTING one, which
sends every password reset and registration confirmation to real customers.** It also most likely
would not have worked: the one-domain limit forced S3's *rollback* but did not cause the *send
failure*, whose leading hypothesis (token↔domain binding) a fresh single-domain account reproduces
exactly.

**Two durable results kept, worth more than the two options closed:** `<slug>.pulllist.app` sending
authenticates cleanly with **strict DKIM alignment** (SPF unaligned — confirming the plan's own
existing prediction, now measured rather than assumed), and **a swap to a DIFFERENT provider has no
parallel-run problem at all** — the single-domain-slot constraint that cost S3 ~50 minutes of real
outage exists only *within* one provider. That reframes the migration and is why the paid-tier
conclusion recorded below is now superseded.

**DIRECTION SET (Rick, 2026-09-02): pursue Resend**, a MailerSend competitor, as the intended
transactional provider. **A direction, not a commitment** — no account exists, nothing probed live,
no code changed. Resend disables link and open tracking **by default** (explicitly so inbox providers
don't classify transactional mail as marketing) and injects no unsubscribe header on its Send API. It
also beats MailerSend Starter *after* the migration, not only during it: Starter is a one-month
bridge back onto a 500/month, 100-req/day free tier, where Resend's free tier is 3,000/month.
**Honest caveat: Resend free is 100/day, so it does NOT dissolve F148** — only Brevo's 300/day would
have, and Brevo is out. **The next step is the probe, not code:** run the same three-test
send / delivered-headers / link-rewriting check against Resend from `pulllist.app` while MailerSend
keeps serving production. **Nothing is scheduled.** Full record:
`docs/f99-sender-domain-consolidation.md` § 9 (Brevo) and § 10 (provider selection). **No finding ID
consumed** — external platform product design, not a defect in our code, DNS or plan. **F152 remains
the next free finding ID.**

**Prior work (2026-09-01): F99 S3 ATTEMPTED and ROLLED BACK, same day as S2.** A real
production cutover attempt — Maintenance Mode ON, `mrcyberrick.us` removed from MailerSend,
`pulllist.app` added and **fully verified** (all four dashboard checks green) — then blocked by
MailerSend's own platform behavior, not anything in our code or DNS. **Read `docs/f99-sender-domain-consolidation.md`
§ 4 S3 in full before attempting S3 again** — this entry is the short version.

**Two real, unanticipated problems, found live.** (1) API tokens are scoped to a specific domain
("server"), not the account — the existing token died the moment `mrcyberrick.us` was removed
(`Unauthenticated`), fixed by generating a new Sending-access token. (2) **The one that forced the
rollback, and its CAUSE IS UNRESOLVED:** every send returned `#MS42207 — "The from.email domain must
be verified in your account to send emails"`, for **both** the subdomain and the exact bare verified
domain (`noreply@pulllist.app` failed identically), twice each, ~15–20 min past full verification.

***Corrected the same evening — this entry first named "MailerSend send-time activation delay" as
the cause. That was a tidy story stated beyond the evidence, and the rollback contradicts it:
`mrcyberrick.us` was re-added minutes later and sent on the first try.*** **Ruled out with reasons**
(so they aren't re-investigated): **Sender Identities** — read directly at Rick's prompting, it is an
agency feature for sending from *clients'* domains and is explicitly not required for a domain you
verified yourself; and **any subdomain or free-tier restriction** — S0's own probe already sent
successfully from `noreply@probe.mrcyberrick.us` on this same free account. **Live hypotheses, ranked:
(1) token↔domain binding mismatch** — MailerSend's docs say the FROM must match the domain the token
belongs to; never checked during the attempt, and it best fits a failure that persisted unchanged
regardless of waiting; **(2) cold-domain vs. known-domain state** — `pulllist.app` showed `0 Sent` and
had never existed in the account, unlike the instantly-working re-add; **(3) activation delay**,
weakest.

**Rollback executed and independently verified, not just trusted.** `pulllist.app` removed,
`mrcyberrick.us` re-added (its DNS was untouched throughout, so it re-verified instantly), a third
fresh API token generated (same domain-scoping issue applies in reverse), both secrets flipped back.
**Verified via real delivered email headers** (Outlook, `View message source`), not the API's own
unconditional `{"success":true}` (which the plan's own § 2 warns proves nothing): `spf=pass`,
`dkim=pass` (both `mrcyberrick.us` and `mailersend.net` signatures), `dmarc=pass`, `compauth=pass`,
`From:` reading `Ray & Judy's Book Stop <noreply@mrcyberrick.us>` — byte-identical to before the
attempt. **Maintenance Mode confirmed OFF via the direct anon RPC (F149)**, not the toggle's own UI
state, at both the start of the attempt (confirming it was genuinely ON) and the end (confirming it
was genuinely OFF). **Total outage window: ~50–55 minutes**, every transactional path down for real
customers — a deliberate, consented window, not an accident, but a real one, run the evening before
a comic-release day at Rick's explicit call to get it done beforehand rather than during.

**State left behind:** `pulllist.app`'s S2 DNS records (DKIM, Return-Path, merged SPF) are still
live in Cloudflare — untouched by the rollback, so **S2 does not need repeating** next attempt. The
`pulllist.app`-scoped API token is now dead (harmless, safe to delete whenever convenient).

***SUPERSEDED 2026-09-02 — see the 2026-09-02 entry above. The direction is now a DIFFERENT provider
(Resend), which needs no paid tier at all, because the single-domain-slot constraint exists only
within one provider: the incumbent keeps serving while the challenger is probed. Also repriced:
Hobby ($7/mo) is still ONE domain and buys no parallel run; **Starter ($35/mo) is the real price**,
not the "~$6" this paragraph's "still to be priced" implied. The reasoning below remains valid ONLY
if MailerSend is retained.*** **The strategic conclusion, and it changed the plan (Rick, 2026-09-01):
buy one month of MailerSend paid tier before retrying.** The free tier's single domain slot means the only way to test
`pulllist.app` is to remove the working sender first — so *every* diagnostic attempt costs a live
customer-facing outage, and this one bought exactly one error code for ~50 minutes of downtime. Two
simultaneous domains makes it a zero-downtime change with unlimited time to investigate. Rick's
framing: the risk is low at today's ~30 customers and *"as the site grows it can translate to a much
bigger issue."* Promoted from § 6 "out of scope, revisit later" to **§ 8 Q7**, still to be priced
(also worth checking whether paid tier lifts F148's 100/day API cap — same account, possibly two
problems for one month's spend). **Rick may retry later; no date set, nothing scheduled.** Also
recorded: he would accept **root-domain-only** (`noreply@pulllist.app`, deferring subdomains) as a
scope simplification — legitimate, and this plan's own documented fallback, but **it would not have
changed this outcome**, since the bare root domain failed identically.

**No finding ID consumed** — this is an external platform's undocumented behavior, not a defect in
our own code, DNS, or the plan's design; the plan doc's own thorough documentation (§ 4 S3) is the
record, matching how other operational/infra gotchas in this project are captured. **F150 remains
the next free finding ID.**

**Prior work (2026-09-01, earlier the same day): F99 S2 partially executed — DKIM + Return-Path
published in Cloudflare.** No code, no staging/prod distinction — pure DNS infrastructure, prepared
by the agent and added by Rick in Cloudflare's dashboard (the established pattern for anything
touching live infrastructure, matching how DB migrations run).

**A real discovery changed what S2 could actually do today, not just how it was sequenced.** Live DNS
reconnaissance against `mrcyberrick.us`'s own working MailerSend records (the dashboard itself is
unreachable for `pulllist.app` — confirmed earlier the same weekend that a second domain cannot be
added even unverified while the first occupies the one slot) showed the three record types S2 needs
split into two shapes: DKIM CNAMEs and the Return-Path CNAME both resolve to a **generic** target
(`<selector>._domainkey.mailersend.net`, `mailersend.net`) that doesn't depend on which domain is
being verified — safe to pre-publish. MailerSend's SPF include, by contrast, is a **per-domain unique
hash** (`dc-<hash>._spfm.<domain>` — `mrcyberrick.us` carries three), confirmed by reading its live
value, and genuinely cannot be known until `pulllist.app` is actually added to MailerSend at S3. **So
the SPF merge is a hard sequencing constraint the plan hadn't fully surfaced, not a scheduling
preference** — this session's plan-doc update makes that explicit for whoever runs S3.

**Published and independently verified**, all three previously NXDOMAIN (no collision risk):
`ms1._domainkey.pulllist.app` and `ms2._domainkey.pulllist.app` → `ms1`/`ms2._domainkey.mailersend.net`;
`mta.pulllist.app` → `mailersend.net`. Verified via an external resolver (`dns.google`), not the
Cloudflare dashboard — confirms both the value and that the records are genuinely unproxied (a
proxied CNAME would not expose the real target to an outside query). Also confirmed in passing:
`ms1`/`ms2._domainkey.mrcyberrick.us` are true NXDOMAIN, independently corroborating that S-1 really
was skipped as recorded.

**Not done, deliberately:** the SPF merge itself (blocked, see above — happens at S3 when the real
include value exists); MailerSend was not touched at all this step, per S2's own scope. **No finding
ID consumed** — infrastructure step advancing F99, not a feature or defect fix.

**Prior work (2026-09-01, earlier the same day): F149 fully RESOLVED, both environments — promoted to
production (PR #147, `36b79ff`; staging `ca8c481`).** Maintenance Mode now covers `index.html`'s
registration submit and `forgot-password.html`'s reset submit — the two paths an anonymous,
not-yet-authenticated visitor can reach, and exactly the ones F99 S3's future all-mail-down cutover
window exposes.

**Promotion required a real decision, not a mechanical merge.** Staging was 19 commits ahead of
`main`, and most of it was **F99 S1** — the six Edge Function sender-literal changes, which CLAUDE.md
records as staging-only and a separate, not-yet-requested promotion. A plain `git merge origin/staging`
would have carried F99 S1's `supabase/functions/*.ts` changes into `main`'s tree alongside F149.
Caught before committing (nothing had landed yet); Rick's call was to exclude it — the six files were
restored to `origin/main`'s version and confirmed byte-identical before the merge was committed. Doc
files (`CLAUDE.md`, `technical-reference.md`, the new `f99-sender-domain-consolidation.md`) were left
to sync wholesale, same as every promotion — they're inert project journal, not deployed behavior.

**The production RPC (`is_maintenance_mode()`) landed BEFORE the client code, not after.** F105's
unapplied-migration gate caught that the client already calls it; running the client first would have
meant a window where `Settings.isMaintenanceModePublic()` hit a missing function (fails open — nothing
would have broken — but the whole feature would have silently no-op'd until someone noticed). Rick ran
the migration on production via SQL Editor first; independently verified live before any code merged
(anon RPC call, `200/false`, matching staging's own result exactly).

**A real, unrelated surprise surfaced at the migration's own pre-flight, not a formality — filed as
F150, not fixed inline.** The file's pre-flight specifically checks `app_settings`'s grant shape
before creating anything; production came back with `anon` holding full table-level DML
(SELECT/INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER) — staging grants `anon` nothing at all on
the same table. Verified live before concluding anything: a real anon read against production
returns `200, []` — RLS still filters every row (only SELECT policy is `TO authenticated`), so no
data is actually exposed today, just a thinner defense-in-depth layer than staging. Rick's call:
file it (F150) and keep moving on F149 rather than fix it as part of this promotion. See § 13 F150.

**Post-deploy verified against the bytes `pulllist.app` actually serves, not inferred from the
merge:** `app.js`/`index.html`/`forgot-password.html` all confirmed carrying
`isMaintenanceModePublic`; `config.js` still carries the prod Supabase ref
(`plgegklqtdjxeglvyjte`); the RPC re-confirmed live post-deploy (`200/false`, identical to the
pre-merge read). **Write-smoke deliberately skipped** — same disposition PR #141/#145/#133 record:
this change never touches `preorders` or the customer reserve path. **A live toggle-ON test against
real production traffic was deliberately NOT run by the agent** — the code is byte-identical to what
got 12/12 automated verification on staging (screenshots included), and flipping Maintenance Mode ON
for real, even briefly, shows the holding-page banner to any actual customer on
catalog/mylist/arrivals/subscriptions during that window. Left as Rick's own optional call, not
something to do silently.

**PR file list verified on GitHub itself** (`gh pr diff --name-only`), not just local state — 7
files, `config.js` absent, none of the six Edge Function files present, matching intent exactly.

**A real blocker surfaced during implementation, not planning, and changed the fix's shape.** The
naive approach — call the existing `Settings.isMaintenanceMode()` from either anonymous page —
cannot work: `app_settings`'s only SELECT policy is `TO authenticated`, confirmed live (anon read
returns `42501 permission denied`, not an empty row), so it would have silently always returned
`false` under an anon session regardless of the real value. Fix needed a small anon-callable
SECURITY DEFINER RPC — same pattern as the pre-existing `resolve_tenant_by_slug` /
`get_popular_series()` — which the original filing didn't anticipate. Flagged to Rick before writing
it (a DB change beyond what was scoped), approved, then built.

**Three pieces.** (1) `docs/sql/2026-08-31-f149-maintenance-mode-anon-check.sql` — new
`is_maintenance_mode(p_tenant_id)` function, minimal projection (boolean only), explicit
`anon`+`authenticated` EXECUTE grant, applied to **staging only**. (2) `app.js` gains
`Settings.isMaintenanceModePublic(tenantId)` — additive, does not touch
`isMaintenanceMode()`/`setMaintenanceMode()`/`checkMaintenanceMode()` or the four existing gated
pages; fails **open** (false) on any RPC error. (3) Both pages gate their **submit path**, not the
whole page, per the filing's own fix direction: `index.html`'s `doSignup()` checks first, before
name/email/Turnstile, so a visitor isn't asked to solve a challenge just to hit a blocked message;
`forgot-password.html`'s `sendReset()` checks after the email-present check, and gets the same
friendly inline message as `index.html` rather than a full-page block (the filing's own open UX
question — resolved this session: this page's request-step already has an error slot, and a
four-page-style banner would be disproportionate). `forgot-password.html` never resolved
`TenantContext` before — added, needed only to know which tenant's flag to read; falls back to the
founding tenant like every other unresolvable case.

**Verified with real functional checks, not code review.** Existing Playwright coverage checked
first: zero existing coverage of registration, `forgot-password.html`, or plain sign-in in any
committed spec; magic-link completion is covered extensively but indirectly (nearly the whole
143-test suite drives a real `action_link` through `index.html`'s completion code via the
`authenticatedPage`/`authedUser`/`adminPage` fixtures). A local, uncommitted harness
(`playwright/f149-maintenance-verify.mjs`, same convention as `native-signup-verify.mjs`) drove the
real deployed staging site end to end — toggling the actual `admin.html` `#maint-toggle` via a
throwaway admin session (never a raw DB write), independently re-confirming the resulting state via
the anon RPC on both flips rather than trusting the UI. **12/12 checks green**: OFF-state
`reset-password` genuinely invoked (HTTP 200, real success message shown); OFF-state signup gate
does not misfire (pre-existing Turnstile validation still fires untouched); ON-state signup and
reset both blocked with the friendly message, both underlying Edge Functions confirmed **never**
called (network-observed); **ON-state plain email+password sign-in still completes**; **ON-state
magic-link completion still completes** — the two regressions the filing itself flagged as
highest-risk. Maintenance mode independently confirmed OFF at both start and end via a direct anon
RPC call, not the script's own exit code. **One piece deliberately not automated, matching this
codebase's own established precedent** (`native-signup-verify.mjs`'s documented reasoning that a
real Turnstile pass/fail token is untestable under headless Playwright): a live human click-through
of a genuinely completed registration was not driven by this session — the maintenance gate sits
before Turnstile in `doSignup()`, so what's verified is that the gate gets out of the way correctly
when off, and actual account creation is unchanged code this diff never touches.

**Gates green.** Unit suite 279/279 (unchanged — no import-script code touched). Full Playwright
suite run directly (not through an agent PowerShell tool, per the 2026-08-30 note below) against
deployed staging bytes post-push: **142 passed, 1 skipped, 0 failed**, exit 0, ~21 min — the one
skip is `15-order-export-ledger.spec.ts`'s own pre-existing `test.skip(monthEnd <= todayStr, …)`
(today, 2026-08-31, is the last day of the month), unrelated to this change. Maintenance mode
confirmed OFF on staging at session end.

**Doc updates landed alongside.** `docs/technical-reference.md` § 13 F149 status → RESOLVED on
staging with full fix/verification detail; this table's F149 row updated below.

**Not done, deliberately:** F99 S1's Edge Function changes stayed staging-only, excluded from this
promotion (above); F99 S2/S3 untouched; a genuine live Turnstile-gated registration submit was not
hand-verified by the agent (Rick can do this in ~30 seconds if wanted, not required for the fix
itself since Turnstile is unchanged code the gate runs ahead of); a live toggle-ON test against real
production traffic was left to Rick's own call rather than run by the agent (above). **F149 is the
finding this closes. F150 was consumed during this same promotion** (the `app_settings` anon-grant
divergence, filed not fixed — see § 13 F150). **F151 is the next free finding ID.**

**Prior work (2026-08-31, earlier the same day): F99 S1 — the six Edge Function sender literals are
now secret-driven, STAGING ONLY (`eff9793`).** `approve-customer`, `invite-customer`, `notify-customers`,
`register-customer`, `reset-password`, `send-my-list` no longer hardcode
`noreply@mrcyberrick.us` / "Ray & Judy's Book Stop" as the MailerSend `from:`. Each now reads
module-level `MAIL_FROM_EMAIL` / `MAIL_FROM_NAME` constants via `Deno.env.get()`, with a `??`
fallback to today's literal — deliberately, per the plan's own design: this makes S1 reversible and
lets a future domain cutover (S3) become a secret flip with no code deploy in the risk window.
Deployed to staging (`puoaiyezsreowpwxzxhj`) one function at a time, each preserving its live
`verify_jwt` setting.

**A real surprise surfaced at the verify_jwt read, not a formality.** CLAUDE.md's own § Supabase
platform facts claimed "all six JWT-off"; the live dashboard read (Rick) showed `approve-customer`
and `send-my-list` actually **ON**, the other four OFF. **The deploy preserved exactly what was
found, not what the doc claimed** — S1's whole purpose is zero behavior change, and re-deriving why
two admin/session-gated functions run JWT-on while `invite-customer` (also admin-only) doesn't is a
separate, unresolved question — a plausible but unconfirmed guess is recorded where the doc line was
fixed. **§ Supabase platform facts corrected the same session** (below this entry's date) — the line
no longer claims universal JWT-off.

**Gates green.** V3a: `grep -n "from:" supabase/functions/*/index.ts` — six hits, all reading
`MAIL_FROM_EMAIL`/`MAIL_FROM_NAME`, zero literal addresses; `mrcyberrick` still greps 6× (the
deliberate `??` fallbacks — going to 0 is V3b, S3's gate, not S1's). Staging's two secrets were set
to today's exact values (Rick, via `supabase secrets set`, confirmed present via `supabase secrets
list` — names only, the CLI shows digests not values) specifically so V2 exercises the real
`Deno.env.get()` path rather than only the fallback. **V2 green twice**: two independent live
`reset-password` sends (`test@mrcyberrick.us`, then `rssedivec@gmail.com`), delivered `From` read
directly from each inbox — `Ray & Judy's Book Stop <noreply@mrcyberrick.us>`, byte-identical both
times.

**Doc updates landed in the same commit.** `docs/technical-reference.md` § 11 intro now notes the
sender is secret-driven; § 11.2 gains `MAIL_FROM_EMAIL`/`MAIL_FROM_NAME` rows, plus `APP_BASE_URL`
(pre-existing, five functions, was simply missing from the table); § 11.3's `notify-customers` note
**corrected** — it claimed the catalog link was "hardcoded to production
(`https://mrcyberrick.us/comic-preorder/catalog.html`)", verified false against the actual file: the
code reads `Deno.env.get('APP_BASE_URL') ?? 'https://pulllist.app'`, no `mrcyberrick.us` literal
anywhere in it. `docs/f99-sender-domain-consolidation.md`'s own STATUS line and § 4 S1 updated to
DONE.

**Not done in this step, deliberately:** production untouched (separate, explicitly-requested step
per § Staging Only); no `reply_to` (§ 8 Q6, declined); no DNS (S2); `APP_BASE_URL`'s actual live
value was not read, only that the secret exists. **No new finding ID consumed** — infrastructure
step, not a feature or defect fix. **F149 remains free.**

**Prior work (2026-08-31, earlier the same day): subscriptions top-5 + store-popular fallback, and
admin's Order Follow-Up bounded — live on production (PR #146, `7dae9fc`; staging
`6a2f677`→`0a031da`).** The second half of the F141 CLS work, plus a product change Rick asked for on
its own merits.

**`subscriptions.html`.** The reserved-suggestions block rendered **one row per reserved series** —
**1,760px** for a 25-series customer, nearly two viewports of suggestions above the subscriptions
the page is actually for. Now capped at the **top 5**, ranked by issues reserved (stable sort, so
ties keep recency); block is ~451px. New **store-popular fallback** for a customer with no
qualifying reservations, via `get_popular_series()` — tenant-scoped since F20 and anon-callable
(SECURITY DEFINER), so it shows aggregate counts without RLS leaking anyone's rows; copy switches,
the per-series count is suppressed, and the usage event records `popular_suggestion`. It
deliberately excludes every series the customer has reserved, **which also keeps the section hidden
in exactly the two cases `11-reserved-suggestions` asserts it hidden** — no test was weakened to
fit the feature. The subscriptions table also gained its own heading and note (Rick: the
suggestions block is something you scroll *past*, and the destination had no title at all).

**`admin.html`.** Order Follow-Up measured **1,796px**, revealed from `display:none` **above** the
tab content. **Never Arrived** now renders in a capped scroll region (300px); **Backordered + At
Risk** collapse behind a summary naming what is inside. Never Arrived stays open and scrollable
rather than hidden **on purpose**: it carries the resolve controls (F134 + F143) staff use for
daily arrival triage. A first attempt collapsed the whole panel and turned **3 specs red** on
`toBeVisible()` — those were a real workflow cost, not stale tests. Hiding all but the first N was
also rejected: these rows sort by on-sale date and staging carries ~32, so a seeded title would
land outside the visible N unpredictably and specs 21/22 would go **flaky rather than cleanly red**.

**Verified on Rick's own signed-in account** (a synthetic probe diverged from his real readings
three times, so his DevTools number is the acceptance test): **subscriptions 0.80 → 0.32** with the
page read approved, **admin 0.90 → 0.17**. **Post-deploy, against the bytes `pulllist.app` serves:**
`subscriptions.html` carries `MAX_SUGGESTIONS` ×3, `buildPopularFallback` ×2, "Popular with other
customers" ×1 and the "Your subscriptions" heading ×1; `admin.html` carries `ofu-never-scroll` ×2
and `ofu-details` ×6. **Negative assertions all 0** — `suggestions-reserve` absent from both files
and `LoadingHeight` absent from `app.js` (both reverted attempts stayed reverted), `config.js` still
carrying only the prod ref. **Gate: 143 Playwright passed, 0 failures, exit 0**, and **specs 21/22
pass UNMODIFIED** — no assertion was edited to fit this code.

**Write-smoke deliberately skipped, with Rick's agreement:** neither file touches the customer
reserve path — `subscriptions.html` writes only to `subscriptions`, `admin.html` is staff-only —
the same disposition PR #141 records.

**No new finding ID consumed — this closes F141's Pattern B work.** (A defect fix: the pages were
visibly shifting, which is wrong behaviour, and F141 already owns it.) **F148 remains free.**

**Two residuals, both deliberate.** `analytics.html` (Pattern C, 0.49) is untouched — seven
independently-filling panels need a different design, and it is staff-only. Admin's remaining
height is a **data backlog, not code**: ~17 Never Arrived titles from the F115 S6 backfill await a
Received/Didn't-arrive/Damaged decision, and clearing them shrinks the panel at source.

**Last completed work: CLS first-paint height reservation — live on production 2026-08-30 (PR #145,
`f21cc56`; staging `6a2f677` + the two revert/refine commits on top).** `style.css` gains
`.loading-reserve { min-height: 100vh; }` and three loading placeholders gain the class —
**47 lines of code across four files, no JS, no schema.**

**Verified on a REAL signed-in account, and that distinction is the whole story of this work.**
Rick measured in DevTools as himself: **My List 0.53 → 0.05**, **Arrivals 0.81 → 0.09** (good is
< 0.1), with **Catalog unchanged at 0.02** as a positive control — same browser, same session,
same tool, one page already-fixed reading good while the others read poor, which is what ruled out
instrument bias. A synthetic probe diverged from his real account **three separate times**; do not
trust `lighthouse-auth.mjs` numbers as absolute values, only as a change detector.
**Post-deploy verification, against the bytes `pulllist.app` actually serves** (not inferred from
the merge): `style.css` carries the rule ×1; `mylist.html` ×4, `arrivals.html` ×2,
`subscriptions.html` ×2; and the negative assertions hold — `admin.html` ×0, `analytics.html` ×0,
`app.js` `LoadingHeight` ×0 (the reverted JS attempt), `config.js` still carrying only the prod
project ref. **Write-smoke deliberately skipped, and this is the reason:** the change is CSS plus
two loading placeholders and never touches the customer reserve path — same disposition PR #141
records. **Gate: 143 Playwright passed, 0 failures, exit 0** against deployed staging bytes, plus 9
targeted subscriptions tests.

**No new finding ID consumed — this closes F141's residual** for the two customer-facing pages.
(A defect fix, not a feature build: the pages were visibly shifting, which is wrong behaviour, and
F141 already owns it.) **F148 remains free.**

**Three things shipped in the same PR that are NOT the CLS fix**, recorded so a future reader is not
surprised: `subscriptions.html` took the same class and improved **0.80 → 0.53** — better, still
poor, because it has a *second* cause (`#reserved-suggestions` is revealed above the now-viewport-tall
list); the `register-customer` MailerLite removal, already deployed to both Supabase projects, so
`main` had been holding stale source for code already live; and this session's documentation.
**`admin.html` and `analytics.html` were deliberately excluded** — the pattern was applied there,
measured, and reverted, because their shifts have different causes. See § 13 F141.

**Last completed work: three admin-surface promotions, all live on production 2026-08-29 (PRs #142,
#143, #144).** *(Recorded 2026-08-30, a day late — all three reached production with no `CLAUDE.md`
or § 13 record at all, which is the same drift class as F132/F138/F139/F145 one step earlier, where
no status gets written rather than a written one going stale. `/promote-prod` step 6 was rewritten
the same day from a soft reminder into a required gate so this cannot recur silently.)*

- **PR #142** (staging `56fafc5`) — **This Week bagging list: rejected/withdrawn titles move to a
  separate "Not arriving this week" note.** Previously they were interleaved into the pick list as
  struck-through rows (F117/F108 § 4.5). Now the main list a staffer bags off of contains only books
  to actually bag, with the unavailable ones in an always-visible note below the totals. Deliberately
  **not** a `<details>` disclosure — a closed disclosure would hide, on the printed sheet, exactly
  what a staffer needs when a customer calls. **No finding ID consumed (feature build, not a
  defect):** the old behaviour was correct — the titles were surfaced, never dropped, and the totals
  already computed off `available`, not `items` — so nothing was miscalculated or hidden. This is a
  workflow preference, not a fix, notwithstanding the commit's `fix:` prefix. **F148 remains free.**
- **PR #143** (staging `a60469b`) — **F132's restriction-ratio badge on the admin store shipment
  grid** (`arrivals.html`, Store Manager view). A ratio-allocated title is the one most likely to
  have shipped short of what was reserved, which is the signal an admin scanning the actual shipment
  wants. Reuses `app.js`'s existing `.restriction-badge` class (already styled and positioned for a
  cover-card grid).
- **PR #144** (staging `bcbbfb3`) — **the same badge in the reconciliation exceptions list.** #143
  did not cover the recon panel's "Not in shipment" rows, and those are where the signal matters
  most: a restricted title appearing there is a likely *explanation* for the shortfall, not a
  coincidence. Found by Rick screenshotting the live exceptions list. Uses an inline ratio pill
  matching `admin.html`'s `restrictionBadge()` — the absolutely-positioned `.restriction-badge`
  class does not fit a flex text row.

**Verified 2026-08-30 against the bytes production actually serves** (not inferred from the merge):
`pulllist.app/admin.html` returns `bagging-not-arriving` ×1 and `Not arriving this week` ×1, with
`bagging-row-unavailable` at **×0** confirming the old struck-through row is genuinely gone;
`pulllist.app/arrivals.html` returns `order_requirement` ×8 and `restriction-badge` ×2. *(Fetch with
`curl -L` — `/admin.html` 302s to `/admin`, and without `-L` the empty body reads as a stale build.
That trap is documented in § Standard Deployment Workflow and it still caught a session on
2026-08-30.)* **Spec coverage checked, not assumed:** #142 removed the `.bagging-row-unavailable`
class, and per the "sweep the suite before deleting a classed element" rule
`06-admin-this-week-bagging.spec.ts:206-223` was confirmed already rewritten to assert
`.bagging-not-arriving` instead. No post-deploy write-smoke was run for any of the three — all are
admin-surface reads that never touch the customer reserve path, the same disposition PR #141
records.

**Production's Order Deadline is `2026-09-24`** (Rick, 2026-08-30 — Step 7 of
`docs/monthly-catalog-refresh.md`, confirmed set, closing the last open sub-item of the September
refresh). Worth recording rather than leaving to be re-derived: per F108's
order-deadline-supersedes rule this value decides what the At-Risk / Backorder panels classify, and
it is the ambient value **F133**'s date-dependent Playwright fixtures are measured against.

**F146 fully RESOLVED on staging, 2026-08-29.** A first verification attempt (fresh September
Lunar + PRH CSV pair, confirmed on disk 2026-08-29) ran clean but proved the "fresh re-pull of the
new month" method itself can never clear any of the 16 marks: Lunar's item codes are permanently
scoped to their solicitation month (0 of 1,377 September rows carry an `0826` prefix, confirmed
across three monthly files) and PRH's are issue-scoped. The real (write) run was withheld rather
than spent on a proven no-op. **Corrected re-test, same session:** Rick re-pulled the August files
fresh; all 16 codes confirmed present by direct grep; re-imported them as an older-month backfill
(`--skip-autoreserve`) per `monthly-catalog-refresh.md` § Step 3's Revision Sweep. Dry run and real
run both reported all 16 reappeared and cleared; independently re-verified against the live DB
(`withdrawn_at NOT NULL` count 16→0, `0826AB0593` and two others spot-checked individually).
**Production still holds 0 withdrawn marks** — its first real exercise of this path is October's
import. Full detail: `docs/technical-reference.md` § 13 F146.
**Last completed work:** **F115 fully RESOLVED, both environments — production S6 backfill closed,
2026-08-28 (later session).** The one remaining piece of F115 (see prior-work entry below) was the
production backfill of 859 pre-existing orphaned rows (`fulfilled=true, arrival_outcome IS NULL`).
A planning pass (`docs/pre-phase-6-consolidation.md` § 3.3 C1) caught that the predicate had
drifted between design and staging's execution — staging's V5 wrote `'unknown'` to its *whole*
orphan population (32/32) because on staging's small test dataset that nearly coincided with the
*never-arrived subset* the design actually called for, but production's 975 real `weekly_shipment`
rows and 1,404 real `order_submissions` rows make those two sets very different. **DECISION: narrow
to genuinely-unproven rows only.** Re-measured live immediately before writing: of the 859 orphans,
**771 have real shipment evidence** (they arrived) and **51 have an order-ledger row** (49
net-positive/ordered — F116's case; 2 net≤0 recorded rejections — F143's principle that a ledger
rejection and an arrival judgement are separate statements) — all 822 **deliberately left NULL**.
The remaining **26 reservations across 23 titles** have no shipment evidence and no ledger row at
all — these were set to `arrival_outcome = 'unknown'`. Guard held (26 is within the doc's own
15–45 bound). Ids captured to a local file *before* the write for exact revertibility. Rick ran the
write himself via a new local one-off script (`f115-s6-backfill-unknown.js`, same pattern as
`clear-f147-withdrawn.js` — re-derives the predicate live, refuses outside 15–45, explicit `y/n`).
**Independently re-verified afterward with fresh queries, not the write script's own printed
output:** orphan count dropped by exactly 26 (859→833); `arrival_outcome='not_arrived'` confirmed
still **0** tenant-wide (the V2 invariant); 3 individual ids spot-checked fresh; production's full
tri-state distribution sums correctly (arrived 212, unknown 32, not_arrived 0, damaged 0, NULL
2,404, total 2,648). **One real consequence, not a defect:** all 23 titles now surface in
`admin.html`'s Ordering ▸ Never Arrived panel needing a Received/Didn't arrive/Damaged decision —
checked directly against the panel's actual filter (all 23 catalog rows carry a `foc_date`, none
are withdrawn) rather than assumed. Full detail: `docs/f115-arrival-truth-persistence.md` § 7 and
`docs/technical-reference.md` § 13 F115.

**Prior work (2026-08-28, earlier the same day):** **Production's real September import + F147
(severe) + F146 — both found and fixed same session.** Rick ran `node import.js` for real against production
(`catalog_month` 2026-08 → 2026-09, archived 357 reservations, purged 2,467 stale rows). It
surfaced **F147**, more severe than anything found on staging earlier the same day: F110's
withdrawal detection — its first-ever real run anywhere, staging included — marked **519 of
production's 1,571 open reservations (33%)** "Withdrawn — cannot be ordered," and **every single
one** still had a future `foc_date` (example: BATMAN #14, FOC two weeks out, flagged anyway).
`narrowWithdrawalCandidates()` never checked FOC at all — root cause: a distributor's catalog file
lists a title once, in its solicitation month, so absence from a later month's file is the *normal*
state for anything not yet at its ordering deadline, not evidence of withdrawal. **Caught before it
reached anyone** — Maintenance Mode was on throughout, verified live before and after. Fixed same
day (scripts repo `main` `e4f968d`): `narrowWithdrawalCandidates()` now also requires a passed
`foc_date`; 6 new unit tests including BATMAN #14's real shape and MIDNIGHT X-MEN #2's shape (F110's
own original genuine-withdrawal case) as positive control; negative-control tested; full suite
279/279. **Production's 519 false marks were cleared and independently verified, 2026-08-28.** The
CLI session's own permission classifier blocked a direct write attempt (a bulk PATCH against
production) — correctly, by design. The local one-off script (`clear-f147-withdrawn.js`, ids
captured first for exact revertibility) was handed to Rick, who ran it himself: `519/519` cleared,
confirmed independently afterward with a fresh live query — `withdrawn_at IS NOT NULL` count is `0`
for the tenant, BATMAN #14 specifically confirmed clear. **Maintenance Mode remained ON throughout
— no customer ever saw any of the 519 marks.** Full detail: `docs/technical-reference.md` § 13
F147.
**F146** (found earlier the same day on staging, see "Prior work" below) was also fixed this
session (scripts repo `main` `415bb38`, before F147 was found) — `detectWithdrawals()`'s
clear-on-reappearance half no longer waits for a new-month import. Its own 16 staging false
positives are **not yet cleared** (need a fresh CSV re-pull); production's would-be F146 instances
were subsumed into the much larger F147 batch and cleared together.
See `docs/technical-reference.md` § 13 F146 and F147.

**Prior work (2026-08-28, earlier the same session):** **F115 staging completion + F146 filed.**
September catalog files arrived ~10 days ahead of the ~Sept 7–10 estimate; Rick ran
`import-staging.js` for real on staging first (`catalog_month` 2026-08 → 2026-09). F115's S1/S5/S6
runbook steps and V1/V4/V5 gates all confirmed green **against the live run** — cross-checked
line-by-line against the database (CSV row counts vs. DB counts, the 16 F110 marks vs. the printed
list, the 1 auto-fulfilled row vs. a real `weekly_shipment` match), not just trusted from the
console. S6 backfill (32 reservations / 30 titles, re-measured fresh, not the stale 28/23 figure)
applied and verified: `arrived=3, unknown=32, not_arrived=0`, zero stragglers. **F115 is RESOLVED on
staging; still OPEN overall** — production's own September import happened later this same session
(see "Last completed work" above) but S6's backfill re-measurement for production has not been done
yet. Full detail: `docs/f115-arrival-truth-persistence.md` § status note (2026-08-28) and
`docs/technical-reference.md` § 13 F115.

**Prior work (2026-08-27):** **F143 + F144 — ordering-side rejection handling** — fully RESOLVED both
environments 2026-08-27 (staging `admin.html` `fff78f2` F144 / `54126c8` F143; production **PR #141**
`a1e8a8d`, same day, Rick's explicit `/promote-prod` request; plan
`docs/f143-f144-ordering-side-rejections.md`, STATUS: COMPLETE both environments). One Sonnet CLI
session end to end. `admin.html` only, no schema change. Built F144 (read-only) first, verified
V1-V3 green against deployed staging, **before** F143 (writes `order_submissions`) landed on top —
two separate `--ff-only` merges to `staging`, each pushed and tested independently. Promotion gates
(`/preflight`, F59 merge-result hash check, F125 tree-integrity assertions) all green; PR file list
re-verified on GitHub matching intent exactly, `config.js` confirmed absent from the diff; production
bytes confirmed serving the new code directly off `pulllist.app` post-deploy. **Post-deploy
write-smoke deliberately skipped, Rick's explicit call** — this promotion is `admin.html` only and
never touches the customer reserve path the write-smoke exercises.

**F144** plumbs `catalog.order_requirement` — previously absent from `admin.html` entirely — into
the Order Builder: `fetchAllPreorders()`'s select, both row-object literals
(`makeOrderSheetRows()`/`buildExportRows()`'s `extraRows`, the "easy miss" the proposal itself
named), and a new scoped `restrictionBadge()` helper (deliberately not `app.js`'s customer-facing
`.restriction-badge` class — that one is absolutely positioned for a catalog cover and shares
`style.css` with every page). Badged in the record step (highest value, restricted titles grouped
ahead of the rest, distributor-aware copy — PRH actionable, Lunar advisory-only per its two-phase
rule), the cycle selector (a restricted count per FOC cycle, its own clause since a restricted
title is still included, not excluded), and the already-ordered/held-back panels. Reads the column
directly — does not parse any title string, per the proposal's own trap (two production PRH titles
carry a ratio with none visible in the title text). V3 (the distributor file byte-unchanged) was
confirmed via code-diff rather than a second live deploy cycle: the `order-builder-generate` click
handler's line-building code is byte-identical across the change, and no generic
`Object.keys()`-driven serializer exists anywhere in `admin.html` that could pull the new field
into the exported lines.

**F143** adds a fourth Order Follow-Up resolve-control option, **Rejected by supplier**, alongside
the three F134 buttons — a rejection discovered mid-cycle can now be recorded from the panel where
it surfaces, instead of correcting the ledger in a different tab. Writes a negative
`order_submissions` adjustment (`order_type: 'adjustment'`) netting the code to 0, payload shape
copied from the Mark Ordered insert; deliberately writes **no** `arrival_outcome` — the ledger
rejection and the import's arrival judgement are different statements, and writing both would let
them disagree. **PAUSE → Rick point (plan § 5.1), resolved this session:** before writing any
write-path code, production was measured live (service-role, read-only) for how many current Never
Arrived rows have `ledgerNetQty === 0` (nothing to negate). The answer was **0 of 0** — production's
Never Arrived panel held zero rows that day, both of its only two `fulfilled=true,
arrival_outcome='unknown'` rows already being recorded rejections. Rick's call: ship the
recommended v1 — offer the button only when `ledgerNetQty(distributor, code) > 0`; a title with no
ledger rows has nothing to reject, and "Didn't arrive" stays the honest control there.

**Gates:** V1-V7 all green (new local spec `22-f143-f144-ordering-rejections.spec.ts`, never
committed — 4/4 passing; every new assertion negative-control tested by temporarily inverting it,
observing 3 of 4 tests go red, then reverting and re-confirming 4/4 green). Full `run-smoke.ps1`
green: **269 unit + 143 Playwright, 0 failures**, run against deployed staging bytes post-push
(Playwright count raised from 139 → 143, the four new tests). **V8 — Rick drove the real flow live
on staging 2026-08-27**: ordered a title, clicked Rejected by supplier from Order Follow-Up,
confirmed By Distributor corrected and the customer-facing rejected badge (F120) appeared.

Prior work (2026-08-27): **Print "View Online" CTA** — fully RESOLVED both environments 2026-08-27
(staging `55b9ba8`, production **PR #140** `334b5ad`). Rick's request: paper that lands in a
customer's hands should carry a path back to an account — a short CTA reading "View Online:
rjbookstop.pulllist.app". Scoped with Rick to exactly two reports: **Print Catalog (Paper
Orders)** — added to the page-1 header and to the `@page` bottom-right footer margin box so it
repeats on every printed page — and **Print Bagging List (This Week)** — added as a second line
under the existing store name/phone/website line in the per-customer `bagging-print-header`.
`mylist.html`'s personal print and `arrivals.html`'s two print buttons were explicitly asked
about and confirmed OUT of scope. `rjbookstop.pulllist.app` verified live before any code was
written (curl 200, serves the tenant front door for the production founding-tenant slug
`rjbookstop`) despite `apex-landing-tenant-subdomains.md`'s 2026-07-20 note deprioritizing
dedicated subdomain provisioning. ***(Corrected 2026-08-27 — F145.* This sentence previously
continued "the wildcard `*.pulllist.app` front-door split already covers it, no dedicated work
needed," and **the wildcard half was false.** There is no wildcard record: `foo.pulllist.app` and
`zzz-does-not-exist-9182.pulllist.app` both return **NXDOMAIN**, while `rjbookstop` and
`comicstore` resolve because each is an **individually provisioned Cloudflare Pages custom
hostname**. The *front-door split* is real but is a different mechanism — a pre-paint inline
script setting `data-front-door` from the hostname, i.e. client-side branding, not DNS. This
matters because the CTA puts that hostname on **paper in customers' hands**, so it is now a
durable customer-facing dependency whose provisioning is recorded nowhere; and because **Phase 6's
S0 wildcard gate is therefore genuinely still closed**, not accidentally satisfied. See § 13
F145.)* **A real bug was caught pre-deploy**: the first draft used a CSS
`\00b7` escape inside the JS template literal that builds the print HTML — an illegal legacy-octal
escape inside a JS template string (confirmed via `node -e`; would have been a SyntaxError
breaking all of `admin.html`'s inline script), replaced with a literal `·` character. Full gate
green on both promotions: 269 unit + 139 Playwright, 0 failures, run against deployed bytes
post-push. Prod verified after deploy: `pulllist.app/admin.html` serves the marker string 3× and
`config.js` still carries the prod Supabase ref. **No finding ID consumed** (feature build, not a
defect).

Prior work (2026-08-26): **Customer phone number** — fully RESOLVED both environments 2026-08-26
(staging `627d411`/`00f2594`/`4185e5a`, production **PR #139**, merged and deployed same day).
Rick's request: an editable phone field on customer accounts. New `user_profiles.phone` column
(nullable text, no format constraint; `docs/sql/2026-08-26-user-profiles-phone.sql`, staging
post-check 24 total rows / 0 with_phone, production post-check 30 total / 0 with_phone — both
match the migration's expected POST-CHECK exactly, both applied by Rick before their respective
client-code deploys). No RLS change needed — covered by the existing `admins manage tenant
profiles` ALL policy (F58). Prod verified after deploy: `admin.html`/`app.js` serving the new
bytes (`edit-account-overlay`, `setProfile`) directly off `pulllist.app`, and Rick's post-deploy
write-smoke came back green. Client side:
`admin.html` Customers ▸ Accounts gained a Phone column plus a new **Edit Account** modal (Name +
Phone, styled like the existing Invite Customer modal) that replaces the old
`prompt()`-based rename-only Edit button; `app.js` `Users.setName` → `Users.setProfile(userId, {
fullName, phone })`, one combined write. **No finding ID consumed** (feature build, not a
defect).

**The Edit-button UI change broke an existing spec, and it was caught before merge, not after.**
`17-admin-modes.spec.ts` V6 asserted the old flow via a Playwright `dialog` event handler
(`adminPage.once('dialog', d => d.accept(after))`) — against the new modal, no native dialog ever
fires, so the handler would have silently no-op'd and the assertion would have failed against a
name that never changed. V6 was rewritten to drive the modal directly (fill `#edit-account-name`
/ `#edit-account-phone`, click `#edit-account-save-btn`) and extended to assert the phone value
lands on the row; V7's title and assertions were updated from "name only" to "name + phone" to
match the modal's two fields, while the `is_admin`-absent assertions (Rick 2026-08-09, still not
here) are unchanged. A negative control (temporarily asserting a value that couldn't be present)
confirmed the rewritten V6 assertion genuinely fails, not vacuously passes — same discipline the
F142/single-catalog-print sessions record as necessary whenever a test is edited to match its own
code. Full gate green: 269 unit + 139 Playwright, 0 failures, ~21 min, run against the deployed
staging bytes post-push (not a stale pre-push baseline).

Prior work (2026-08-24): **Single combined catalog print** — fully RESOLVED both environments
2026-08-24 (staging `56c97c9`/`c54cf88`/`d0a5f9d`, production **PR #137** `8ae9b2d`). Ordering ▸
Paper Orders had two per-distributor catalog prints; it now has one **Print Catalog** button
emitting a single banded document covering both distributors. Same rows, same filters, same column
and row geometry — the only addition is a distributor band. Prod verified after deploy: 1,534 rows
(Lunar 1,028 / PRH 506), 35 pages, rendered from the deployed bytes over live prod data; Rick
confirmed the physical print. **No finding ID consumed** (built to request, not a defect — F142 is
still free).

**A barcode variant was built, printed, tested against the shop's real scanner, and deliberately
dropped.** Rick's verdict: *"the scanner is working but resolution limitations make it less
useful."* The symbols were not the problem — they measured **in spec on paper** (145/117/98/89% of
nominal, inside the GS1 80–200% band, verified by decoding all 2,171 rendered SVGs with an
independently-written decoder). The limit is the scanning hardware against a laser print, so
**re-tuning the magnification will not change the outcome** — do not rebuild it on that assumption.
It also cost roughly twice the paper (0.384in/row against 0.219in). The whole UPC-A/EAN-13/Code-128
encoder is recoverable from `56c97c9` if that hardware is ever replaced.

**The measurement trap, which is the part worth carrying forward.** A page count for this sheet
**cannot be inferred from catalog size**, and two wrong numbers were quoted before that was
understood. `getReservedPublishers()`'s `MIN_RESERVED = 7` bar decides the length, and it cuts far
harder than the row count suggests. Both environments held ~2,400 rows across **78 publishers** for
`2026-08` and printed completely differently: **staging 4 publishers → 638 rows → 15 pages**,
**production 14 → 1,534 → 35**, because staging's reserve history is 24 archived + 64 live rows of
test data against production's 485 + 2,623. A count taken on staging says nothing about production,
and a count taken from a raw `normalized_catalog.json` (no publisher filter available offline) says
nothing about either — that last one produced a "49 pages" claim that never described a real print.
Measure against the environment you mean. The builder's own comment now records this.

**Also worth knowing: the publisher bar is self-reinforcing.** A publisher under 7 all-time
reservations never prints, so customers never see it, so it never earns reservations. On production
that excludes **64 of 78** publishers — Oni Press, Viz Media, Yen Press, Seven Seas and Vault among
them. Pre-existing and deliberate, not introduced here; surfaced because nobody had measured which
publishers it actually drops. **No finding filed** — Rick's call whether that trade is right.

**Two process corrections came out of this.** (1) The claim "this change has no spec coverage" was
**wrong** and nearly shipped a regression: the print *windows* have none, but
`17-admin-modes.spec.ts` V1/V5 assert the *buttons*, and deleting them turned the suite red. V1 used
`#btn-print-lunar-order` merely as a witness that the Paper Orders tab was on screen; V5's whole
subject was the two-button pair. Both were repaired to the new single button (V5 now also asserts
the three removed ids are `toHaveCount(0)`, making it stronger than before) and a negative control
confirmed the rewritten assertions can still fail — necessary discipline whenever a test is edited
to match one's own code. **Sweep the suite for references before deleting any element with an id.**
(2) `/promote-prod` steps 1+3 contradict each other — see the skill's own note, fixed same day.

Prior work (2026-08-24): **Lighthouse performance sweep** RESOLVED on staging 2026-08-24 —
triggered by Rick asking why Performance scored consistently below 80 on both mobile and desktop.
Five items, **no finding ID filed** (fixed in-session rather than deferred, Rick's call — **F141 is
still free**). Measured against live production first, which localised three of Lighthouse's four
categories onto specific files instead of generic advice.

**Artwork (items 1, 2, 5).** Three assets were bitmaps in formats that could not compress them, two
of them wrapped in SVG: `favico.svg` was an Inkscape export around a 1254×1254 RGBA PNG — **931 KB
(710 KB brotli'd), linked from all eight pages and refetched on every load**, to be painted into a
16–32px tab slot; `comic-cover-fallback.svg` was 203 KB of SVG around a 300×450 base64 PNG for a
slot CSS renders at 150×225; `assets/hero.jpg` was a 1600×854 JPEG served full-size to phones.
Re-encoded in-session with Pillow (no GIMP/Inkscape round-trip needed) to `icon-192-v2.png`
(3,162 B) + `apple-touch-icon-v2.png` (2,939 B — new; iOS previously had no home-screen icon),
`comic-cover-fallback-v2.webp` (10,764 B), and `hero-v2.webp` (71,166 B) + `hero-mobile-v2.webp`
(31,784 B). Per page: **866,187 B → 13,926 B** on catalog/mylist/arrivals/etc., **845,694 B →
74,328 B** desktop / **34,946 B** mobile on the apex page.

**Fonts (item 4).** `style.css` opened with an `@import` of the Google Fonts CSS. An `@import` is
invisible to the preload scanner, so first paint waited on three strictly serialized round trips
across two cold origins (`style.css` → parse → `fonts.googleapis.com` → parse →
`fonts.gstatic.com`) — Lighthouse's 1,610 ms mobile / 510 ms desktop render-block. Replaced with
`preconnect` + a direct `<link>` in all eight heads; the `_headers` CSP already allowed both
origins, so no policy change was needed. **Do not reintroduce the `@import`** — a comment sits at
its old location in `style.css` saying so.

**Caching (item 3).** `_headers` only ever *shortened* lifetimes (`no-cache` on
`app.js`/`config.js`/vendor, for the F79 skew reason); everything else fell to Cloudflare Pages'
default `max-age=0, must-revalidate`. Added long lifetimes for static artwork in two groups.
**The `-vN` filename suffix is load-bearing:** files served `immutable` for a year carry it, and
re-exporting one REQUIRES bumping N and updating every reference — a year-long immutable cache on a
stable filename is a trap. `style.css` is deliberately in neither group: unfingerprinted and
deploy-variable, so the F79 reasoning that governs `app.js` governs it too.

**Verified 2026-08-24**: `node --check` clean on `app.js`, `shelf-order.js` and all 10 extracted
inline `<script>` blocks; full `run-smoke.ps1` — **269 unit + 139 Playwright, 0 failures, exit 0**,
both stages present in the log; every `_headers` path resolves to a real file; HTML diffs confined
to `<head>`, so the six-page nav/footer sync set is untouched. **Because essentially none of this
is spec-covered** — no spec asserts font rendering, cache headers or favicons — a separate
real-browser check against deployed staging confirmed what a green suite could not:
`document.fonts.check()` true for both families (no silent fallback to `sans-serif`), **exactly one
hero request per viewport** (so the `matchMedia` preload agrees with the stylesheet — no
double-download), and zero requests for the three deleted assets. Standalone perf work, not scoped
to any active sub-deploy. **Promoted to production 2026-08-24 via PR #132.** Prod verified
directly after deploy: all five new assets return 200 with `max-age=31536000, immutable`,
`style.css` no longer carries the `@import`, and every page's live `<link>` tags point at
`icon-192-v2.png` / `apple-touch-icon-v2.png`. *(A `favico.svg` string still greps in each head —
that is the explanatory comment, not a reference; the file is deleted and origin returns the
not-found fallback. Cloudflare's edge kept serving the orphaned object for a while under Pages'
7-day `s-maxage`, harmless since nothing links it.)* Production apex now scores **89 mobile / 98
desktop**, with `cache-insight` at **0 KiB** (was 1,576 KiB desktop / 555 KiB mobile) and
`image-delivery-insight` at **18 KiB** (was 1,223 / 477 KiB).

**The F59 assertion was extended during this promotion, and the extension is worth keeping.**
`.gitattributes` sets `app.js merge=ours`. The documented check compares branch *tips*, so it
reports "ok: differs" even in the exact case the `ours` driver would silently keep `main`'s copy —
it cannot detect the failure it is named for, on the one file carrying that attribute. The merge
*result* and git's index were asserted directly instead. (A first attempt at that assertion falsely
reported three FAILs by combining `[regex]::Escape()` with `-SimpleMatch` in PowerShell, which
searches for literal backslashes — verified with `grep` before concluding anything. A check that
can falsely fail aborts a good promotion just as surely as a check that cannot fail passes a bad
one.)

**Calibration lesson — worth more than the sweep itself.** The opening question was about
Lighthouse **scores**; the three lines quoted were **Insights**. "Use efficient cache lifetimes"
and "Improve image delivery" are **diagnostics that contribute nothing to the Performance score**,
which is only TBT 30% / LCP 25% / CLS 25% / FCP 10% / SI 10%. This sweep closed both diagnostics
almost entirely and the scores barely moved — exactly what that weighting predicts. Two further
mismeasurements cost real time the same day: (1) Lighthouse run against `/catalog` **in a private
window is not signed in**, so `requireAuth()` redirects and it scores the marketing page reached
via a discarded catalog load — 21 requests, ~554 KiB, precisely where the "555 KiB" figure came
from; (2) the raw byte sizes of our own assets were assumed to map onto the audit totals, when on
the **authenticated** catalog every single cache and image item is a third-party
`media.lunardistribution.com` cover. **Measure the authenticated page, and check whether an audit
is actually scored before optimising for it.** `playwright/lighthouse-auth.mjs` (local-only, in the
scripts repo working tree) does the former — it creates a staging user, signs in via magic link,
runs Lighthouse against the live session, and tears the user down.

Prior work (2026-08-24): **F140** fully RESOLVED (both environments) — promoted to
production same day as the staging fix (PR #131, `2acc78d`/`26a2c80`), per Rick's explicit
`/promote-prod` request. New production bytes confirmed served; both high-risk findings
re-verified directly against live production data post-deploy — the current catalog month
(`2026-08`) genuinely had **2,399 rows**, past the old hardcoded 2,000-row ceiling, and the fixed
loop now correctly retrieves all 2,399 (1000/1000/399); the Book Stop admin account's `preorders`
total had grown to **1,345**, and the fixed `Recommendations._getUserSignal()` pagination now
correctly retrieves the full 1,345 across 2 pages, matching the exact DB count. Both were
confirmed genuinely live-broken before this promotion, not just theoretical risk. See
`docs/technical-reference.md` § 13 F140.

An audit follow-up to F139, triggered by Rick asking "do we have other areas where pagination is
causing issues?" Swept every Supabase
query in the app for the same unbounded-select-no-`.range()` shape and found six more live
instances — the third occurrence of this defect class overall (after F82, F113). Two judged
plausibly already live-broken in production: `catalog.html`'s Reserved/Unreserved and
FOC-Expiring-This-Month filters were hardcoded to exactly two 1000-row batches (a fixed 2,000-row
ceiling, re-capped instead of unbounded — the same shape F82 fixed, at a higher threshold); `app.js`
`Recommendations._getUserSignal()` had the identical unbounded shape as F139's `getMyIds()`/`getMy()`
in a different function that fix missed. Also fixed: `Subscriptions.getAllAdmin()`,
`admin.html`'s three `user_profiles` fetches + This Week bagging query, `analytics.html`'s
`user_profiles`/`subscriptions`/current-month-preorders fetches, `mylist.html`'s shelf-copy demand
query — all now paginated, reusing each file's existing helper where one exists (`app.js`'s
`Preorders._fetchAllRows` generalized to a shared top-level `fetchAllRows()`; `admin.html`'s
`fetchPaged()`; `analytics.html`'s `countRows()`/`fetchRanged()`) or a local count-first+loop
matching the file's convention otherwise. Also added `id` tiebreakers to three paginated `ORDER BY`
clauses that sorted on non-unique columns (a page-boundary tie risk with no prior symptom, since it
only matters once a query is paginated at all). **Verified 2026-08-24**: `node --check` clean on
`app.js` and every extracted inline `<script>` block; full `run-smoke.ps1` — 269 unit + 139
Playwright, 0 failures, exit 0, no log-capture ambiguity this run. Standalone audit/fix, not
scoped to any active sub-deploy. Promotion details above.

Prior work (2026-08-23): **F139** fully RESOLVED (both environments) — a live customer-
reported catalog bug (a real reservation showing unreserved, omitted from the Reserved filter, and
hitting a 23505 on re-reserve) traced to `Preorders.getMyIds()`/`getMy()` having no pagination
against PostgREST's default 1000-row cap on unbounded selects. Diagnosed against live production
data (confirmed the row was correct in the DB before touching any code — no RLS gap, no data
corruption), fixed with a new `Preorders._fetchAllRows()` range()-based pagination loop in `app.js`,
no schema change. Verified on staging via full `run-smoke.ps1` (269 unit + 139 Playwright, 0
failures) and a targeted 37/37 rerun of every reserve/My List/subscriptions/arrivals spec; promoted
to production same day (PR #130) and re-verified directly against live prod data post-deploy — the
account that surfaced the bug (1,223 preorders as of the recheck) now correctly returns the
previously-dropped reservation via the fixed pagination. See `docs/technical-reference.md` § 13
F139. Standalone bug fix, not scoped to any active sub-deploy.

Prior work, same day: **F138** RESOLVED on staging 2026-08-22 (reverses F128, Rick's explicit
request) — admin impersonation gets full write access to `subscriptions` (subscribe **and**
unsubscribe on a customer's behalf), matching how `preorders`' admin policy already works. New
`admins manage tenant subscriptions` RLS policy (`docs/sql/2026-08-22-f138-admin-subscription-management-impersonation.sql`)
run on staging and verified via `pg_policies`; three impersonation guards removed from
`subscriptions.html` (reserved-suggestions Subscribe, main-table Unsubscribe, series-search input);
two write-target bugs fixed in the process (reserved-suggestions subscribe + its Undo handler were
writing to the admin's own `user_id`, not the impersonated customer's — harmless only while the
buttons were disabled). **V1–V4 all green**: V1 the live `pg_policies` read, V2/V3 a rewritten
Playwright test in local spec `11-reserved-suggestions.spec.ts` that subscribes and unsubscribes on
a customer's behalf during impersonation and DB-verifies both the correct `user_id` and the actual
row deletion (not F128's silent no-op), V4 the full `run-smoke.ps1` — 269 unit + 139 Playwright, 0
failures. Branch `feature/f138-admin-subscription-management-impersonation` merged to `staging`
`--ff-only` and pushed. **Promoted to production 2026-08-22** — RLS migration applied same day,
client code via PR #129 (`f1364a785`). **F138 fully RESOLVED, both environments.** *(This section
previously read "Not promoted to production" after the promotion had already completed — the same
stale-doc pattern as F132 below; corrected 2026-08-23, found while promoting F139.)* See
`docs/technical-reference.md` § 13 F138.

Prior work, same day: **F136** fully RESOLVED 2026-08-22 — S1, S2, and S3 all shipped the same day
(`docs/f136-catalog-month-integrity.md`). S3 (an earlier session that same day): created
`dedupe_catalog_months()` on **production** (S2's migration was staging-only); added the Part C(2)
revision-sweep runbook step to `docs/monthly-catalog-refresh.md`; re-measured live production fresh
rather than trusting the 2026-08-21 snapshot (2,666 duplicate pairs / 2,667 safe / 29 blocked,
unchanged — of the 29 blocked, only 2 are unfulfilled, matching § 3(d) exactly, the other 27
historical/fulfilled); repointed the 2 unfulfilled reservations (Alex Alvarez / TMNT #40 Variant C,
Brian Moss / Action Comics #1 Facsimile) from `2026-05` to the maintained `2026-06` rows; ran the
production dedupe. **Gates V7–V8 green**, confirmed three independent ways — production catalog
rows **12,087 → 9,418 (delta exactly 2,669)** matching the dry-run preview precisely, preorder
counts unchanged (**2,021/1,049/972** total/unfulfilled/fulfilled), duplicate pairs **2,666 → 27** /
safe-blocked **2,667/29 → 0/27** (the 27 survivors are the historical rows Rick chose to leave
blocked — zero customer risk, permanent minor bloat, accepted). Staging's one residual (Nightmare
Before Christmas #2) confirmed `fulfilled = true`, same accepted category. **Also fixed in-session:**
CLAUDE.md's and `technical-reference.md`'s F132 findings both still read "production not yet run"
when the DB half had actually been `APPLIED` 2026-08-21 — corrected (commit `7d4df83`), found while
confirming F136 S3 wasn't blocked by that gate. **No further F136 sessions planned.**

Prior work, same day: **F136 S2** — the `dedupe_catalog_months()` RPC applied to **staging**, wired
into `refreshCatalog()`'s new-month branch in both `import.js`/`import-staging.js` (scripts repo
`main` `7a8d6a1`, which is why S3 needed no additional code change — the wiring already covered
production). **F136 S1** — Part A (catalog-month entry guards: `inferCatalogMonth()` no longer
silently guesses, requires an explicit typed month; Lunar MMYY-vs-confirmed-month cross-check;
distributor-agnostic cross-month collision pre-check) + Part C(1) (`classifyReservedDateDrift()`
gains a third `unreserved` list) + **F137** (Step 3's month-detection query scoped by `tenant_id`,
**fully RESOLVED**) + `f136-audit.js`. Merged to `main` in the scripts repo (`f1f90be`).
2026-08-22.
**Next free finding ID:** **F157**. **F156 filed 2026-09-05** (Lunar restricted-variant ratios never reached `catalog.order_requirement` on rows imported before F132 added the derivation 2026-08-20 — the ratio stays in `variant_type`, the derived column stays NULL forever because an older catalog month is never re-pulled, and **every** restriction surface therefore renders nothing: the customer's catalog badge (`app.js:1906`) and modal notice (`catalog.html:1261`), the Order Builder's restricted count (`admin.html:1126`), and both arrivals badges (`:1278`/`:1339`). Measured live: **67 production rows** (58 in `2026-07`, 5 in `2026-06`; staging 66), **6 with live unfulfilled reservations** — the exact unbadged rows Rick screenshotted. The reverse direction is clean (**0** Lunar rows carry `order_requirement` without a ratio), so the backfill replays the import's own rule rather than guessing. Backfill written, **not yet applied**: `docs/sql/2026-09-05-f156-lunar-order-requirement-backfill.sql`. See § 13 F156.) **F155 filed 2026-09-04** (the monthly-refresh runbook tells the operator PRH does not revise in-store dates in place, so PRH catalogs are never re-pulled and a revised date is never detected — measured false: **108** PRH 2026-07 titles carry a different `OnSaleDate` than the DB, plus 27/19/4 in 06/08/09. Found live by Rick: DNX #1 `75960621519500111`, in-store revised 2026-09-02 → **2026-09-16**, invisible to its two customers on every surface and about to be falsely fulfilled. **The larger result: for a FROZEN PRH catalog no data channel exists at all** — May master data is byte-identical across downloads, its change reports stop 2026-07-31, and 0 of 5,123 ids ever re-list. Lunar is the opposite: **one** All-Products file (17,490 rows) covers 98.4% of open codes and found 13 stale dates immediately. Filed not fixed — plan doc `docs/f155-catalog-date-revision-detection.md`, NOT STARTED. See § 13 F155.) **F154 filed AND RESOLVED, same session, 2026-09-03**
(`mylist.html`'s print header read *"Catalog for null"* for a tenant with zero catalog rows —
`Catalog.getLatestMonth()` correctly returns `null` pre-first-import, but the print handler
interpolated it unguarded while the normal page, six lines away, already guarded the identical
value. Found live by Rick, printing My List for `riverside-comics` — the first tenant created
through this session's newly-fixed invite flow, moments after creation. Not a branding leak; would
hit any tenant printing before their first import. Fixed with the same `||`-fallback shape
`getLatestMonth()` itself uses. See § 13 F154.) **F153 filed AND RESOLVED, same session, 2026-09-03**
(`register-tenant` created a new tenant's admin account with no password, no invite, no email of
any kind — zero automated way in, ever, despite `tenant-onboarding-runbook.md` Step 5 claiming
otherwise. Found while answering a plain question about first login, not a scoping session. Fixed
same session: the function now generates a GoTrue `recovery`-type link and sends a branded,
platform-identity ("PULLLIST", not the founding-tenant literal) invite via Resend, gated correctly
by `plan` for the link it prints — always the apex `?t=<slug>` URL, never an unprovisioned
`<slug>.pulllist.app` guess. A first attempt used `type: 'invite'`, matching `invite-customer`'s own
pattern; live-verified WRONG for this case (`422 email_exists`, since the admin user already exists
here) before landing on `recovery`. Response gained `invite_sent: boolean`. Runbook Step 5 corrected
in the same commit. See § 13 F153.) **F152 filed 2026-09-02** (a real production `reset-password`
send to an Outlook recipient landed in spam despite fully clean `dkim`/`spf`/`dmarc`/`compauth` —
found during F99 M7's post-cutover verification, right after production's Resend cutover. Not a
K1–K6 trip; likely a cold-start reputation cost for the brand-new `pulllist.app` sender identity with
Microsoft specifically, not confirmed as the sole cause. Gmail and a third-party relay both delivered
cleanly in this session; only this one Outlook send has been observed going to spam. Mitigated by
`forgot-password.html`'s pre-existing "check your spam folder" copy. Low severity — **Rick's call:
monitor, don't act.** See § 13 F152). **F151 filed 2026-09-01** (`tenants.settings` still stores
`mailerlite_webhook_secret` on **all three real tenant rows** — staging `raysandjudys`, production
`rjbookstop` and `comicstore`; only the four `pw-*` Playwright fixture tenants are clean. Measured
service-role, key names only — the value was never read. The secret is **inert** (the `?secret=`
path was removed from `register-customer` platform-wide 2026-08-30) and the read is **tenant-scoped**
— worst case is a customer reading their *own* shop's dead secret, never another tenant's — so
severity is Low. The gap is that `resolve_tenant_by_slug`'s careful "never return `settings`"
projection (5.3 § 1.5) is **bypassed** by the authenticated path, which reads `tenants` directly
(`app.js:82-86`); RLS filters rows, not columns, so that `select()` list is a client convention, not
a boundary. **Unconfirmed:** no probe was run with a real user JWT, and a column-level GRANT — if one
exists — would flip the conclusion. Fix direction: delete the dead key, no rotation needed. Found
while planning F72, filed per Rick's call rather than fixed inline. See § 13 F151). **F150 filed
2026-09-01** (production's `app_settings` grants
`anon` full table-level DML — staging grants none on the same table; RLS confirmed still blocking
real reads live, so no active exposure, but an unexplained prod/staging divergence. Found by F149's
own migration pre-flight during its production promotion, filed per Rick's call rather than fixed
inline. See § 13 F150). **F149 filed AND RESOLVED on staging, 2026-08-31** (Maintenance
Mode now covers `index.html`'s registration submit and `forgot-password.html`'s reset submit —
found while planning F99 S3's cutover risk, fixed the same session via a new anon-callable
`is_maintenance_mode()` RPC the naive fix turned out to need. Production untouched; S2/S3 themselves
untouched. See § 13 F149). **F148 filed 2026-08-31** (`notify-customers` sends one MailerSend API request **per recipient**, so the monthly blast is bounded by the free tier's **100 daily API requests**, not its 500/month email cap — the commonly-quoted number is the wrong one to plan against. ~30 customers today so there is real headroom, but it binds at ~100 on one tenant, and sooner across tenants since quotas are per-account and monthly imports cluster. Not a defect; a structural scaling limit no test can surface, same class as F131. See § 13 F148). **F147 filed AND fixed 2026-08-28** (withdrawal detection's
first-ever real run, on production, marked **519 of 1,571 open reservations (33%) "Withdrawn —
cannot be ordered"** — every single one still inside its own ordering window, `foc_date` not yet
passed. Example: BATMAN #14, FOC two weeks out, flagged anyway. Root cause:
`narrowWithdrawalCandidates()` never checked whether FOC had passed — a distributor's catalog file
lists a title once, in its solicitation month, so absence from a later month's file is the NORMAL
state for anything not yet at its ordering deadline, not evidence of withdrawal. Fixed same day
(scripts repo `main` `e4f968d`) — the check now requires `foc_date` present and passed; 6 new unit
tests including BATMAN #14's exact shape, negative-control tested, 279/279 green. Production's 519
false marks cleared (0 had a passed FOC, so 0 were withheld) via a local one-off script;
**Maintenance Mode was on throughout, no customer ever saw this.** See § 13 F147). **F146 filed AND
fixed 2026-08-28** (same-month catalog refreshes never
re-run withdrawal detection, so a title dropped mid-month from the distributor's export — but
still live on their site — stays incorrectly marked "Withdrawn — cannot be ordered" until the next
new-month import, if then; found live on staging, 16 false-positive titles including item code
`0826AB0593`, confirmed still active against the distributor's own site. The false flag lets a
customer irreversibly self-cancel a title the store is still getting, via the same `isWithdrawn`
override that legitimately unlocks cancellation on a real withdrawal — see table below and
`docs/technical-reference.md` § 13). **F145 filed 2026-08-27** (documentation defect + untracked
operational dependency — **there is no wildcard DNS on `pulllist.app`**; an arbitrary subdomain
returns NXDOMAIN, and `rjbookstop`/`comicstore` resolve only because each is an individually
provisioned Cloudflare Pages custom hostname. Two docs said otherwise. The print CTA now puts one
of those hostnames on customer paper; Phase 6's S0 wildcard gate is confirmed **still closed** —
see table below and `docs/technical-reference.md` § 13). **F144 filed 2026-08-26 and RESOLVED on
staging 2026-08-27 and promoted to production the same day (PR #141)** (restriction ratios reach
the Order Builder — see § Current Migration Phase above and `docs/technical-reference.md` § 13).
**F143 filed 2026-08-26, RESOLVED on staging 2026-08-27 and promoted to production the same day
(PR #141)** (Order Follow-Up's resolve control gains a fourth "Rejected by supplier" option —
order-invoice compare-and-report considered and **declined** at filing, not re-proposed — see
§ Current Migration Phase above and `docs/technical-reference.md` § 13). **F142 filed 2026-08-24 and fully
RESOLVED on both environments 2026-08-26** (Order Builder's own Held Back
panel never checked the ledger for a rejection, so a title an admin recorded
as rejected kept reappearing as "Backordered... never ordered" every time the
modal reopened — found live on production during Rick's first real Order
Builder reconciliation; staging fix `9e41e52`, promoted to production via
**PR #138** `ebcdbee1`, write-smoke and an F142-specific real-browser check
both green on production 2026-08-26 — see `docs/technical-reference.md`
§ 13). **F141 filed 2026-08-24** (desktop CLS
0.636 — the catalog grid fills after first paint with no reserved space;
found re-measuring Lighthouse against *authenticated* staging after the
performance sweep, which itself consumed no ID — see table below and
`docs/technical-reference.md` § 13). **F140 filed
2026-08-24 and RESOLVED on both environments the same day** (six more
unbounded-query pagination gaps, found auditing F139 — see table below and
`docs/technical-reference.md` § 13). *(This pointer read "RESOLVED on staging"
for a few hours after the prod promotion had already landed — corrected
2026-08-24.)* **F139 filed and
RESOLVED on both environments 2026-08-23** (`Preorders.getMyIds()`/`getMy()`
silently truncated at PostgREST's 1000-row cap — see table below and
`docs/technical-reference.md` § 13). **F138 filed 2026-08-22** (reverses F128
at Rick's request — see table below and `docs/technical-reference.md` § 13).

Every `docs/*.md` plan doc carries a machine-readable `**STATUS:**` token (state · staging/prod
dates · PR · findings) as the first line after its title. Trust that token — not narrative
elsewhere, including this section — for whether a specific piece of work has shipped.
`/preflight` cross-checks these tokens (and every `docs/sql/*.sql` `-- STATUS:` line) against git
and flags any doc claiming NOT STARTED / IN PROGRESS whose branch is already merged to `main`.

**Open findings — full detail lives ONLY in `docs/technical-reference.md` § 13. This table is a
pointer, not a record; do not duplicate finding narrative here or let it drift from § 13.**
When re-deriving this table from § 13, **do not grep for the word "open"**: F115 went missing from
every open-work surface for a week because its status reads *"Mitigated"*, and F127 sat listed as
*"PARTLY RESOLVED"* for a week after both halves shipped (both corrected 2026-08-18). Read each
status line's **last clause**, not its first word — and treat any finding that delegates its
residual to another finding as open until that other finding demonstrably absorbed it.

| ID | One line | Next step |
|---|---|---|
| F156 | **Medium, filed 2026-09-05, open — backfill written, NOT applied** — Lunar stores its allocation ratio in `variant_type`; `parseLunarVariantRestriction()` (`import.js:272`) derives `order_requirement` from it, but only since **2026-08-20**. Rows imported before that keep the ratio and carry a NULL derived column **permanently** — older months are never re-pulled (F155's own assumption, different column). So no restriction signal renders anywhere: not the customer's badge (`app.js:1906`) or modal notice (`catalog.html:1261`), not the Order Builder count (`admin.html:1126`), not either arrivals badge (`:1278`/`:1339`). **`arrivals.html` is not the defect** — it reads the column and never parses the title, exactly as F144 requires | Owner: § 13 F156 + `docs/sql/2026-09-05-f156-lunar-order-requirement-backfill.sql`. **Measured live 2026-09-05:** prod **67** rows (2026-07=58, 2026-06=5; 05/08/09 clean), staging **66**; **6 carry live unfulfilled reservations** — `0626DE0825` plus SPAWN 77 CVR F–J (`0726IM0315`–`0319`), i.e. every unbadged row in Rick's screenshot. `0726AC0632` is unbadged **correctly** (`variant_type` null — no ratio anywhere). **Safe because the reverse direction is empty:** 0 Lunar rows hold `order_requirement` without a `^[0-9]+:[0-9]+$` match, so the UPDATE replays the import's own predicate. Every consumer is read-only display — no schema, no RLS, no deploy. **Rick's step, both environments** |
| F155 | **Medium, filed 2026-09-04, open, not started** — `monthly-catalog-refresh.md:130-132` states PRH "omits withdrawn titles rather than revising dates in place… this step matters most for Lunar." **Measured false** (108 PRH 2026-07 titles differ from the DB), so the Revision Sweep has never run for PRH and a revised in-store date is never detected. Found live: DNX #1 `75960621519500111` revised 09-02 → **09-16**; once the stale date passed it left BOTH `mylist.html`'s current-month table (`:937`) and its future-dated Upcoming Arrivals (`:884`) — invisible to its two customers — and the next import marks it fulfilled. No panel caught it because `computeBackorderRisk()` (`admin.html:1749`) clears any code with `ledgerNetQty > 0` first, so an **ordered** title is invisible, and Mark Ordered was correctly `disabled` | Owner: `docs/f155-catalog-date-revision-detection.md` (STATUS: NOT STARTED) + § 13 F155. **The pivot: for a FROZEN PRH catalog there is NO channel** — May master data byte-identical across two downloads (MD5 `438958a0…`), 0 of 1,078 rows differ from the May import, change reports stop **2026-07-31**, **0 of 5,123** ids ever re-list (so F122 cannot help), yet **84 May titles are still future-dated**. Lunar inverts this: **one** All-Products file (17,490 rows, back to 2025) covers **559/568 (98.4%)** open codes and surfaced **13** stale dates at once — incl. `FIRE AND ICE #5` moved a month *earlier*, the direction nothing watches. Plan: S1 fix the doc, S2 weekly `check-dates.js` (2 files, 3 actions, Fri/Sat) reusing `classifyReservedDateDrift()`, S3 **bounded deferral** in `auto_fulfill_past_on_sale()` + panel-ordering fix. **S3 revisits F115 Option A** (rejected as "a silent miss for a silent stall") — hence *defer*, never block; needs Rick's explicit sign-off. **3 titles exposed on production today; the 2 DNX #1 rows are still `fulfilled=false`** |
| F154 | **Low, fully RESOLVED, staging, 2026-09-03** — `mylist.html`'s print header read literal *"Catalog for null"* for a tenant with zero catalog rows (a normal pre-first-import state). `Catalog.getLatestMonth()` correctly returns `null`; the print handler interpolated it unguarded while the same file's normal-page code, six lines away, already guarded the identical value. Found live by Rick printing `riverside-comics`' My List moments after creating it | Owner: § 13 F154. **Fixed same session**: `` `Catalog for ${currentMonth \|\| 'no catalog imported yet'}` `` — same fallback shape `getLatestMonth()` itself uses. `node --check` clean. **Not yet re-verified against a live print post-deploy** |
| F153 | **Medium, fully RESOLVED, staging, 2026-09-03** — `register-tenant` created a new tenant's admin auth user with `email_confirm:true` and **no password, no invite, no email of any kind** — zero automated first-login path ever existed, despite the onboarding runbook's Step 5 claiming an invite sent automatically. Found by answering a plain question, not a scoped audit | Owner: § 13 F153. **Fixed same session**: generates a GoTrue `recovery`-type link (a first attempt used `type:'invite'`, live-verified WRONG — `422 email_exists`, since the admin already exists here — before landing on `recovery`, matching `reset-password`'s own proven type) and sends a branded, platform-identity ("PULLLIST") invite via Resend. Response gained `invite_sent`. Link always points at the apex `?t=<slug>`, never an unprovisioned subdomain. Runbook Step 5 corrected in the same commit. Verified live end-to-end (7/7, zero orphaned auth users) and mechanically (template harness, 10/10) |
| F152 | **Low** — a real production `reset-password` send to an Outlook recipient landed in spam despite fully clean `dkim=pass d=pulllist.app`/`spf=pass`/`dmarc=pass`/`compauth=pass reason=100` — found during F99 M7's post-cutover production verification, right after the Resend cutover. Not a K1–K6 trip (link rewriting/tracking/alignment all clean); reads as a cold-start reputation cost for the brand-new `pulllist.app` sender identity specifically with Microsoft, not confirmed as the sole cause. Gmail and a third-party relay both delivered cleanly in this same session — only this one Outlook send has gone to spam so far | Owner: § 13 F152. **Open — Rick's explicit call: monitor, don't act.** Mitigated by `forgot-password.html:194`'s pre-existing "Didn't get it? Check your spam folder, or send again" copy — not added because of this finding. Watch real customer traffic (not test sends) over the following days/weeks as `pulllist.app` builds reputation with Microsoft; escalate only if it doesn't self-resolve |
| F151 | **Low, both environments** — `tenants.settings` still stores `mailerlite_webhook_secret` on all three **real** tenant rows (staging `raysandjudys`, prod `rjbookstop` + `comicstore`; the four `pw-*` fixture tenants are clean). Inert since 2026-08-30 (the `?secret=` path was removed platform-wide) and the read is **tenant-scoped** — a customer could read their *own* shop's dead secret, never another tenant's. The real point: `resolve_tenant_by_slug`'s deliberate "never return `settings`" projection (5.3 § 1.5) is **bypassed** by the authenticated path, which reads `tenants` directly at `app.js:82-86` — RLS filters rows, not columns | Owner: § 13 F151. **Open, not started — Rick's call (F72 plan § 8 Q5): file now, fix later.** **Verify first:** no probe was run with a real user JWT; a column-level GRANT on `tenants`, if one exists, flips the conclusion entirely. Fix direction: `UPDATE public.tenants SET settings = settings - 'mailerlite_webhook_secret';` on both environments — **no rotation needed**, the value authorizes nothing. Found while planning **F72** |
| F150 | **Low today, confirmed by a live test not inferred.** Production's `app_settings` grants `anon` full table-level DML (SELECT/INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER) — staging grants `anon` nothing on the same table (hard 401). Found by F149's own migration pre-flight, which halted exactly as designed. A live anon read against production returns `200, []` — RLS still filters every row (only SELECT policy is `TO authenticated`), so no data is actually exposed today, just a thinner defense-in-depth layer than staging | Owner: § 13 F150. **Open, not started — Rick's call: file now, fix later.** Still unconfirmed: whether RLS is actually *enabled* (`pg_class.relrowsecurity`) on this table vs. merely having zero anon-applicable policies (both give the same empty-read symptom); writes were not probed against production. Not investigated: how the divergence arose, or whether other tables share it |
| F149 | **Low today, directly relevant at F99 S3 — fully RESOLVED, BOTH ENVIRONMENTS, 2026-09-01.** Maintenance Mode (`checkMaintenanceMode()`) is still only called from `catalog.html`/`mylist.html`/`arrivals.html`/`subscriptions.html` — all four already-authenticated, untouched by this fix. `index.html`'s registration submit and `forgot-password.html`'s reset submit are now gated by a separate mechanism: a new anon-callable `is_maintenance_mode()` RPC (the naive "just call the existing method" fix couldn't work — `app_settings` returns a hard permission-denied to an anon read, confirmed live) plus `app.js Settings.isMaintenanceModePublic()`, additive, not touching the existing four-page pattern | Owner: § 13 F149. **Fixed:** `docs/sql/2026-08-31-f149-maintenance-mode-anon-check.sql`, `app.js`, `index.html` `doSignup()`, `forgot-password.html` `sendReset()` — staging `ca8c481`, **production PR #147 `36b79ff`**. **Verified staging**: 12/12 checks in a local Playwright harness — both submit paths blocked with their Edge Function confirmed never called while ON, plain sign-in and magic-link completion both confirmed still working while ON, full suite 142 passed/1 skipped (unrelated)/0 failed. **Verified production post-deploy**: served bytes confirmed carrying the fix, RPC re-confirmed live (`200/false`), `config.js` still prod ref, PR file list matched intent on GitHub itself (F99 S1's Edge Function changes deliberately excluded, confirmed byte-identical to `main`). Write-smoke skipped (doesn't touch the reserve path, same disposition as PR #141/#145/#133). Surfaced **F150** during the promotion's own pre-flight (filed, not fixed) |
| F148 | **Low today, Medium at ~100 customers, High at 2+ tenants** — `notify-customers` sends **one API request per recipient** in a serial loop, so a monthly blast costs N requests for N customers. MailerSend free allows **100 daily API requests** / 500 emails-per-month / **no overage** — so the *daily* cap binds first, and quotas are **per-account**, shared across tenants whose imports all land in the same window. Not a defect; works as designed and is ~3x under cap today | Owner: § 13 F148. **Open, not started.** Fix direction: MailerSend's bulk endpoint (many messages, one request) — **free-tier availability unverified, confirm against the live account first**. Cheaper mitigation regardless: make `import.js` Step 7 *prompt* on a non-zero `failed` count instead of logging it behind a green check. Sequence with **F99**/**F72** — same MailerSend account. **⚠️ 2026-09-02: the bulk-endpoint fix direction assumes MailerSend is RETAINED.** F99's direction is now **Resend** (its plan doc § 10), whose free tier is 3,000/month but still **100/day** — so a provider move raises the monthly ceiling and does **not** dissolve this finding. Re-derive the fix against whichever provider is actually chosen |
| F147 | **High, fully RESOLVED 2026-08-28** — F110's first-ever real run, on production, marked **519 of 1,571 open reservations (33%)** withdrawn — every one still inside its own ordering window (`foc_date` not yet passed; example BATMAN #14, FOC two weeks out). `narrowWithdrawalCandidates()` never checked FOC at all | **Fixed, scripts repo `main` `e4f968d`** — now requires `foc_date` present and passed; 6 new tests incl. BATMAN #14's real shape, negative-control tested, 279/279 green. **Production data corrected and independently re-verified** — Rick ran `clear-f147-withdrawn.js`, 519/519 cleared, confirmed via a fresh live query afterward (count 0, BATMAN #14 spot-checked). **Maintenance Mode was ON throughout — no customer ever saw it.** See § 13 F147 |
| F146 | **Medium–High, fix shipped 2026-08-28, fully RESOLVED on staging 2026-08-29** — same-month catalog refreshes never re-ran withdrawal detection's clear half, so a title dropped mid-month from the distributor's export but still live on their site stayed incorrectly marked "Withdrawn — cannot be ordered" until the next new-month import, if ever. **16 false positives found on staging's September import** (e.g. `0826AB0593`, confirmed live on the distributor's site); the false flag let a customer **irreversibly** self-cancel via the override that legitimately unlocks cancellation on a real withdrawal | **Code fixed, scripts repo `main` `415bb38`**, unit tested + negative-control tested, 273/273 green. **A first verification attempt (fresh September re-pull) was correctly halted**: Lunar item codes are permanently scoped to their solicitation month and PRH's are issue-scoped, so none of the 16 marks could ever clear that way, at any freshness. **Corrected re-test, same day: re-imported August's own files (fresh re-pull) as an older-month backfill (`--skip-autoreserve`)** — dry run and real run both reported all 16 reappeared and cleared; independently re-verified against the live DB (`withdrawn_at NOT NULL` count 16→0, 3 titles spot-checked including `0826AB0593`). **Staging: RESOLVED, 16/16 cleared.** Production still holds 0 withdrawn marks; its first real exercise of this path is October's import. See § 13 F146 |
| F145 | **Low today, Medium if acted on** — **there is no wildcard DNS on `pulllist.app`.** `foo.pulllist.app` and `zzz-does-not-exist-9182.pulllist.app` both return **NXDOMAIN**; `rjbookstop` and `comicstore` resolve only because each is an individually provisioned Cloudflare Pages custom hostname. `CLAUDE.md` claimed a wildcard covered it, and `apex-landing-tenant-subdomains.md` S4 still calls that hostname "deferred" — while the print CTA now puts it on **paper in customers' hands** | **Doc + one operational record, no code.** CLAUDE.md **and** `apex-landing-tenant-subdomains.md` S4 both corrected 2026-08-27 at filing. **Still owed (one item):** record both hostnames in `tenant-onboarding-runbook.md` as durable infra, noting `rjbookstop.pulllist.app` appears on printed material — held for Rick's Cloudflare-side inventory rather than inferred from two `curl` results. Provisioning date unrecovered (Cloudflare audit log). **Leave Phase 6 S0 as-is — it is correct, and this measurement confirms that gate is still closed** |
| F141 | **Medium** — the catalog grid under-reserved its own height: `renderSkeletons(10, …)` against `PAGE_SIZE = 50`, and a skeleton shorter than a real card. **Desktop CLS 0.636** (good is < 0.1) — essentially the whole gap between the authenticated catalog's desktop score of **75** and a passing one | Owner: `docs/technical-reference.md` § 13 F141. **Fully RESOLVED 2026-08-24, both environments** (staging `a2a2583`, prod **PR #133**) — desktop **75 → 98** (CLS 0.636 → 0.02), mobile **86 → 93** (CLS 0.097 → 0.008), full `run-smoke.ps1` green, prod verified post-deploy. **Pattern A LIVE ON PRODUCTION (PR #145); Patterns B/C on staging or open. The residual was APP-WIDE and is THREE defects, not one.** Rick measured all six shared-nav pages on his own account; catalog **0.02** (already fixed) was the positive control. **A — placeholder replaced by taller content:** `.loading-reserve{min-height:100vh}` on the placeholder, in **static CSS** (it must exist at first paint — CLS sums per shift, so a JS reservation splits one shift into two; reserving *more* scored *worse*, reverted `979eb7d`). mylist **0.53→0.05**, arrivals **0.81→0.09**, LIVE. **B — a `display:none` section revealed ABOVE content:** subscriptions **0.80→0.32** (capped the suggestions block to top 5 — it was 1,760px; a slot reservation on top made it *worse*, 0.33→0.55, reverted), admin **0.90→0.17** (Never Arrived open in a capped scroll region since it carries the resolve controls; Backordered + At Risk collapsed — specs pass **unmodified**). **C — analytics** (seven independently-filling panels) 0.49, untouched. **Admin's residual is a DATA backlog, not code:** ~17 Never Arrived titles from the F115 backfill; triaging them should take it under 0.1. **Staging-only, not promoted:** the subscriptions and admin work. Old note: RESOLVED on staging 2026-08-30 for the three customer-facing pages; the residual was APP-WIDE.** Rick measured all six shared-nav pages on his own account: catalog **0.02** (already fixed — the positive control) vs mylist 0.53, arrivals 0.81, subscriptions 0.80, admin 0.90, analytics 0.49. Fix = `.loading-reserve{min-height:100vh}` on each **loading placeholder** in **static CSS** — it must exist at first paint, because **CLS sums an impact fraction per shift** and a JS-applied reservation splits one shift into two (reserving *more* scored *worse*: 620px→0.347 vs viewport→0.578; reverted `979eb7d`). Results: mylist 0.969→0.038, arrivals 0.966→0.003, subscriptions →0.003, empty-account mylist 0.613→0.013. **143 Playwright passed, 0 failures.** **admin.html and analytics.html were tried, measured and REVERTED** — admin's shifts are `display:none` panels being revealed and pushing content down; analytics has seven independently-filling panels. Both staff-only, both need different designs. **LIVE ON PRODUCTION 2026-08-30, PR #145** — accepted on Rick's own account (mylist 0.53→0.05, arrivals 0.81→0.09, catalog 0.02 control) and re-verified against the served prod bytes. **Still open:** `subscriptions.html` 0.80→0.53 (a second cause — `#reserved-suggestions` revealed above the list), plus `admin.html` and `analytics.html`, all scoped as separate work. Old note: measurement INVALIDATED 2026-08-30 — the My List numbers describe a brand-new user's empty-list discovery grid (`first-issues` present, `list-table` absent in the Lighthouse JSON), not a customer's pull list. A fix was built, measured 620px→0.347 / viewport→0.578 (reserving *more* scored *worse*), found to also break the empty-state branch, and **reverted** (`979eb7d`; files byte-identical to pre-change). Same class as the 2026-08-24 wrong-page measurement, one step further in — authenticated, but not a *representative* user. `arrivals.html`'s 0.966 is likely closer to real (the store grid renders regardless of reservations) but unconfirmed. **Open question is now “is there a problem on a real customer's page at all”, not “how do we fix it”.** Two mechanical facts kept: Lighthouse runs a cold profile so any per-viewer memory is unmeasurable by it, and an unthrottled Playwright load reads CLS 0.000 — measure under throttling. Old text: it is real on both — `arrivals.html` desktop CLS **0.966** (score 75) and `mylist.html` **0.613** (score 78), against authenticated staging.** For scale, the defect this finding fixed on `catalog.html` was 0.636, so **arrivals is worse than the original**. Mobile is fine on both. **Not fixed — new work item, Rick's call.** Read each page's shift culprits before assuming catalog's fix transfers |
| F115 | **Medium, fully RESOLVED, both environments, 2026-08-28.** A never-arrived title used to auto-fulfil on schedule, so My List told the customer "✓ Order placed" for a book that never came — now `arrival_outcome` persists what actually happened. Staging: S1/S5/S6 ran for real, V1/V4/V5 all green, 32/30 backfilled. Production: real Sept import ran (`arrived=212, unknown=6, not_arrived=0`), then **S6 backfill closed 2026-08-28** — 859 orphans re-measured, narrowed to 26 genuinely-unproven rows (771 shipment-evidenced + 51 ledgered correctly left NULL), written and independently re-verified (859→833, `not_arrived` still 0) | Owner: `docs/f115-arrival-truth-persistence.md` (STATUS: COMPLETE). **Not open work.** One residual, not a defect: writing `'unknown'` surfaced all 23 backfilled titles in `admin.html`'s Never Arrived panel — real triage, staff-only, expected. See § 13 |
| F135 | **Medium** — the pull-feed publish is welded to shipment import and fires unconditionally, so an **ad-hoc** shipment import republishes a *past* newsletter week, purges the current week's thumbnails, and the next Brevo cron mails the stale issue — the measured 2026-08-11 incident, reproduced deliberately | Owner: `docs/f135-decouple-feed-publish.md`. Direction settled: **decouple**, move the build into the weekly send workflow (DB-resolved week), delete `resolveFeedWeek()`. **Interim, no code:** comment out `GITHUB_TOKEN_PULL_FEED` in `.env` for ad-hoc runs |
| F131 | **Medium scaling / High continuity** — catalog import is a single-operator dependency: no self-service path exists (service-role key makes the script undistributable), and **every tenant's catalog is sourced from one person's Lunar/PRH portal access**, so losing that access stales every tenant at once. Not a defect — a structural SPOF no test can surface | open, no plan doc. Blocks nothing today; becomes load-bearing the moment the Founding Partner cohort onboards. **Interim, no code:** document the runbook for a second operator + make `.env`/portal access recoverable. Fix shape = authed upload → EF → tenant-scoped write (volume, not architecture, is the open question) |
| F130 | **Low, but the number was wrong — re-measured 2026-08-30 as 893, not 197**, with explicit pagination (the 197 was taken by an unrecorded method; GoTrue's admin list defaults to a small page size, the same unpaginated-read class as F82/F113/F139/F140 — five times now). **Classification done**, which is what the finding asked for: 5 prefixes hold 737/893, and `10-post-reserve-prompt` + `11-reserved-suggestions` each call `createUser` 9× against `deleteUser` 2× — users made *inside* tests are never torn down (383 orphans, the fix target). `pw-iso` (207) is balanced 2×/2× and is a **different, undiagnosed** cause. `pw-pending` (70) must NOT be bulk-deleted — those survivors are intended (F64 item 5 Option A). Read-only pass; nothing deleted. Old text follows: 197 orphaned GoTrue **auth users** in staging from Playwright fixtures. **Measured 2026-08-24: the auth DELETE works (6/6 deleted, 0 remained) — these are deletes never *attempted*, not failed ones**, and 7 of 11 same-day orphans are `pw-pending-*` where a surviving auth row is *intended* (F64 item 5 Option A). Test-infra only, no live app impact | deferred — dedicated test-infra session. **The bulk-delete-after-date-bucketing plan is invalid as stated**: bucketing cannot tell an intended decline survivor from a teardown miss. Classify by originating spec/prefix first, fix the teardowns that skip the auth call, then delete only what remains. See § 13 F130 |
| F133 | **Low — variant (a) RESOLVED 2026-08-30; variant (b) re-dispositioned, its diagnosis does not match the code.** (a) fixed by `ensureDeadlineCovers()`/`restoreDeadline()` in the Playwright fixtures — the describe block that depends on the At-risk classification now **owns** `order_deadline` instead of hoping the ambient value cooperates. Reproduced **deterministically** first (forced past deadline → `06:148 toContainText(atRiskTitle)` fails), then negative-control tested (guard removed → 1 failed; restored → 9 passed). (b) **does not reproduce**: spec 21 passes targeted 6/6, its assertions all target unique stamped titles, and the panel has no row cap — so “assumes the panel holds only its fixture” is not what they do. **Its claim that targeted runs are untrustworthy is not currently demonstrable.** Needs a real captured failure before anyone “fixes” it. Original entry retained — the date-dependence was real | Owner: § 13 F133. Old text follows: date-dependent specs flip red with zero code involved, via the live `order_deadline` (2026-08-21). **Two variants, not one:** (a) a fixture FOC crossing *past* the deadline (2026-08-20, three specs); (b) **the deadline having LAPSED** re-admits *real* catalog rows into `#backorder-risk-panel`, breaking any spec that assumes the panel holds only its fixture — **recurred 2026-08-24 in a fourth spec** (`21-arrival-resolution:136`) — **but only in a TARGETED run; it passes in the full suite**, because spec 15 runs first and leaves the state it needs. Test-infra only | deferred — no plan doc. **The entry's prediction that a lapse would end this was wrong — a lapse started variant (b).** Also exposes an **undeclared spec-order dependency**: spec 21 is green by ordering luck, so **targeted runs of these specs are not trustworthy**. Fix: deadline-aware helper closes (a) only; (b) needs panel assertions scoped to the seeded row. See § 13 F133 |
| F72 | `register-customer` email template stays founding-branded post-un-pin | design together with F99 — needs a scoping interview |
| F99 | transactional (MailerSend/GoDaddy) and marketing (Brevo/Cloudflare) mail split across two sender domains | **Plan doc: `docs/f99-sender-domain-consolidation.md`. S0 ANSWERED 2026-08-31** — MailerSend signs a subdomain `From` under its one verified parent domain, so `pulllist.app` verified once covers every `<slug>.pulllist.app`; F99's per-tenant-subdomain direction is viable on the free tier. **S1 DONE on staging 2026-08-31 (`eff9793`)** — the six sender-email `from:` literals are now `MAIL_FROM_EMAIL`/`MAIL_FROM_NAME` secrets with a `??` fallback to today's values (zero behavior change); staging's secrets set to those same values and proven via two live `reset-password` sends, `From` byte-identical both times. **Surfaced during S1, code left as-is, doc corrected:** `approve-customer` and `send-my-list` actually run `verify_jwt` **ON** on staging — CLAUDE.md § Supabase platform facts claimed universal JWT-off and was wrong; the deploy preserved the live setting rather than matching the doc (S1's job is no behavior change), and the platform-facts line itself was corrected the same session (2026-08-31) to state the real, non-universal pattern. **S2 (DNS) DONE 2026-09-01** — DKIM + Return-Path CNAMEs published in Cloudflare and externally verified; SPF merged at cutover time with the real MailerSend value (`include:_spf.mailersend.net`, generic — not the per-domain hash originally expected), confirmed 2 DNS lookups, well under the 10-lookup ceiling. **S3 (cutover) ATTEMPTED 2026-09-01, ROLLED BACK — full production cutover run for real** (Maintenance Mode ON, domain swapped, fully verified in MailerSend's dashboard) but blocked by two MailerSend platform behaviors neither the plan nor MailerSend's own docs anticipated: API tokens are domain-scoped (fixed, generated a new one) and `#MS42207` rejected every send — for the bare verified domain as well as the subdomain — **cause UNRESOLVED**. Ruled out with reasons: Sender Identities (agency feature, not required for your own verified domain) and any subdomain/free-tier restriction (S0's probe already sent from a subdomain on this same free account). Top live hypothesis: **token↔domain binding, never checked**. Rolled back cleanly, verified via real delivered headers — production unchanged, back to `noreply@mrcyberrick.us`. **Total real outage: ~50–55 min.** No finding ID consumed — external platform behavior, not a defect in our code/DNS/plan. ~~**Next attempt should buy one month of paid tier first (§ 8 Q7)**~~ — **SUPERSEDED 2026-09-02.** **S3-B: Brevo transactional EVALUATED and REJECTED 2026-09-02 (§ 9)** — three live sends, zero downtime, production untouched. Transactional is active and domain auth covers arbitrary addresses with **strict DKIM alignment**, but Brevo rewrites **every link, password-reset links included**, through its own `sendibt2.com` click redirector and declines to disable it (one root cause: it does not separate transactional from marketing on the API, so it also injects a one-click `List-Unsubscribe` and a tracking pixel). `reset-password`'s `hashed_token` design still holds — a trust/credential-handling problem, not a functional break, still disqualifying. **A second free MailerSend account is CLOSED — an explicit ToS violation** (§ 11.1/11.2; the exposure is the *existing* account). **Key reframe: a swap to a DIFFERENT provider needs no paid tier at all** — the single-domain-slot constraint exists only within one provider. **DIRECTION SET (Rick, 2026-09-02): Resend** — a direction, not a commitment; nothing probed live, no code changed (§ 10). **Repriced:** Hobby ($7) is still ONE domain; Starter ($35) is the real parallel-run price. **Next step is the probe, not code** — **discovery session PLANNED 2026-09-02, not started: `docs/f99-resend-discovery.md`.** Kill criteria (K1–K6) stated up front; sequenced so Resend's sandbox sender tests the disqualifiers — link rewriting, unsubscribe injection, tracking pixel — **before any DNS is published**, so Phase 1 can disqualify it in ~10 min with nothing to roll back. Production untouched at every step; **Maintenance Mode is NOT needed** (S3 needed it because the cutover removed the working sender; this adds a second, unused provider alongside). **S4 not started.** Read `docs/f99-sender-domain-consolidation.md` § 4 S3, § 9 and § 10 before retrying. Design together with F72. **✅ RESEND DISCOVERY COMPLETE — GREEN, 2026-09-02, same day.** `docs/f99-resend-discovery.md` ran both phases against a real account: `pulllist.app` verified, K1–K6 all clear on our own domain (an early sandbox K1/K3 trip traced to `resend.dev`'s own pre-configured tracking subdomain, confirmed clean on ours before concluding anything), alignment **stronger than Brevo** (DKIM exact-match + SPF aligned, not DKIM-only), apex SPF confirmed untouched throughout. **D7 (parent-covers-subdomain) came back negative** — opposite of MailerSend's S0 — forcing the addressing decision immediately: **flat `noreply@pulllist.app` DECIDED** (not per-tenant subdomains), per "prioritize the free tier." **Provider selection is now DECIDED, not a direction** — see `docs/f99-sender-domain-consolidation.md` § 10. **Migration plan written, not started: `docs/f99-resend-migration.md`** — six Edge Functions, mechanical `from`/`to` shape diff measured from live code. F148 measured (D8): not dissolved (~100/day unchanged), monthly ceiling improves 500→3,000; paid-tier pay-as-you-go overage ($0.90/1,000) confirmed real but Free-tier-inapplicable. No finding ID consumed. **✅ MIGRATION M1–M5 COMPLETE ON STAGING, GREEN, 2026-09-02, same day.** `docs/f99-resend-migration.md` executed end to end: `RESEND_API_KEY` set (fresh key), all six functions cut to Resend's exact request shape, `verify_jwt` preserved per function, `MAIL_FROM_EMAIL` flipped to `noreply@pulllist.app` on staging (landed with M1, before the code deploy). Two real sends (`reset-password`, `invite-customer`) confirmed clean from delivered headers at two different receiving MTAs — `dkim=pass d=pulllist.app` exact match, `spf=pass` aligned, `dmarc=pass`, no rewritten links, no tracking pixel. `register-customer`'s live check is an accepted residual (Turnstile-gated, no real tenant-hostname URL exists on staging). Magic-link auth confirmed fully covered by this migration (no separate Supabase-native mail path exists in the app). Full suite green: 279 unit + 143 Playwright. **✅ MIGRATION PROMOTED TO PRODUCTION, GREEN, 2026-09-02, same day, Rick's explicit request.** PR #148 (merge `4a4a475`) — conflicted on all six functions because production had never received S1 (every prior promotion restored them to hardcoded literals, matching `config.js`'s preservation pattern), resolved by taking staging's tested code wholesale, verified byte-identical by hash; F125 checks green. Secrets set (Rick reused staging's `RESEND_API_KEY` rather than a fresh one), `verify_jwt` preserved and reconfirmed. Real production send: authentication fully clean (`dkim=pass d=pulllist.app` + `amazonses.com`, `spf=pass` aligned, `dmarc=pass`, `compauth=pass reason=100`) but landed in spam — filed **F152** (cold-start Microsoft reputation, not a defect; mitigated by an existing spam-folder prompt; Rick's call: monitor, don't act). Write-smoke skipped (never touches the reserve path). **Both environments now serving from `noreply@pulllist.app` via Resend.** No finding ID consumed for the migration itself |
| F89 | paper→app conversion is unmeasurable — claim deletes the paper rows, nothing logs it | deferred — future instrumentation session |
| F90 | `usage_events` 90-day purge forecloses adoption-trend analytics | deferred — future schema + import-script session |
| F126 | profile email-editing unreachable outside the Supabase console (needs an Edge Function, F25); paused-customer reservation handling undecided | deferred — Rick's call to schedule |
| F132 | **Medium** — a title restricted to a distributor allocation ratio (e.g. `1:10`) carries no signal at reservation time; customer only learns via the retrospective F117/F120 rejected badge. **Both distributors** — corrected same-day, Lunar carries the ratio in `variant_type` (562 rows, staging), not absent as first measured | Owner: `docs/order-restriction-alert-badge.md` (staging V1-V7 all GREEN 2026-08-21 — migration, real import, hover-stacking fix, mobile Learn More via the detail modal, 210/210 unit + 6/6 Playwright. **Gate V8 — DB half APPLIED to production 2026-08-21** (verified 0 non-null/11,726, Rick). **Client code half also LIVE on production — measured 2026-08-24 against the served bytes**, not inferred: `order_requirement` present in `app.js` (×3), `catalog.html` (×2) and `style.css` (×1), `restriction-badge` in `app.js`/`style.css`, the hover `z-index: 2` fix (×6) and the mobile "Learn more" disclosure all returned by `pulllist.app`. **F132 is fully RESOLVED, both halves, both environments.** This row read "still not promoted, in progress" for three days after it had shipped — found while scoping a promotion that would have carried the stale line onto `main`) |

Before proposing any work, read the active phase docs and confirm the proposed change is in
scope. **If something seems related but isn't on the IN scope list in the active sub-deploy plan,
stop and ask** rather than fixing it inline.

---

## 🚨 CRITICAL RULES — READ FIRST

### Staging Only
**All code changes, file generation, and deployment guidance target staging ONLY,**
except inside an explicitly-named Phase 4 cutover-window sub-deploy.
- Never suggest pushing directly to `origin main` outside a cutover sub-deploy
- Never open PRs to production unless the user explicitly requests a production
  promotion AND confirms staging tests have passed
- Every session assumes work starts on the `staging` branch
- Always remind the user to smoke test on staging before promoting to production

### Credential Safety
**`config.js` is tracked per-branch with different values on each branch.**
This is intentional: production `main` holds the prod anon key; `staging` holds
the staging anon key. The deployment workflow uses `git checkout main -- config.js`
during a staging→main merge to preserve the prod-branch values.

- The Supabase anon key is **public by design** and safe in committed client code.
  RLS is the security boundary, not key secrecy. Do not treat a committed anon
  key as a credential leak or propose `git rm --cached` on it.
- The agent never edits `config.js` and never proposes credential values.
- Service-role keys are different — they bypass RLS and **must** stay local-only,
  in the scripts folder, never in any repo.
- If a feature needs a new key in `config.js`, add it manually to both branches
  before any merge. The `git checkout` step preserves existing prod values; it
  does not propagate new keys.

### Document Integrity (the rule that prevents the most rediscovery)
**Planning artifacts (sub-deploy plans, runbooks, baseline docs) are committed
to the repo immediately on creation, before the next session begins.**
Uncommitted planning files in the working tree are a known drift source — they
get overwritten, reverted, or accidentally clobbered between sessions. Treat any
uncommitted planning doc as not-yet-real until it lands in git.

- Doc-only commits go to `staging` directly, never bundled into a feature branch
  for sub-deploy work
- Reference docs that describe live state (schema baselines, function inventories,
  finding statuses) include a "last verified against live: DATE" line. If that
  date is stale or absent, **re-audit against live before relying on the doc** —
  for production-touching work especially, the live database is authoritative,
  the doc is a snapshot
- Contradictions discovered in this file or any reference doc are surfaced as
  findings, not worked around silently

### File Drift Prevention
**Always work from actual current files, not from memory or earlier sessions.**
- In chat sessions: ask the user to upload any files that will be modified
- In agentic sessions: re-read files from disk at session start; `Select-String`
  or `view` the target range before any `str_replace`; halt if `old_str` does not
  match byte-exactly
- Never assume outputs from a previous session match what's currently in the repo
- After generating updated files, remind the user to copy them to the repo before
  committing — and to verify any live status cells haven't been advanced by a
  CLI session since the chat output was generated

### Definition of Done — Merge Gate
A sub-deploy is mergeable to `staging` **only when all of these are true**:
- Its plan's Completion Criteria checkboxes are all ticked
- Any soak period is fully elapsed (a 3-day soak means three calendar days, not
  "checks green so far at day 2")
- Verification gates (V1, V2, … V*N*) are all green
- Any canary tenant or test fixture is torn down (verify with a live SELECT
  returning zero rows — not "we ran the teardown SQL")
- The parent-plan status cell is updated to **Complete** with the date
- `CLAUDE.md` § Current Migration Phase active-sub-deploy pointer is advanced

**"Most of the work looks done" is not done.** Never merge a sub-deploy whose
plan still has unchecked completion boxes. Merges to `staging` use `--ff-only`
(clean linear history; no merge commits).

---

## 🚨 Environment Facts (stated once, never rediscovered)

### Shell
- **PowerShell is the primary shell; Claude Code also provides a separate Bash
  tool.** Use each tool with its own native syntax — never run PowerShell
  cmdlets through the Bash tool, and never invoke `powershell -Command` from
  Bash. Prefer PowerShell for Windows/git/deploy mechanics; Bash only for
  genuinely POSIX one-liners.
- In PowerShell use `Select-String` (not `grep`), `Measure-Object` (not `wc`),
  `Get-Content | Select-Object -Skip N -First M` (not `sed`)
- Quote paths containing parentheses: `cd "C:\Users\richa\OneDrive\Documents\(Work)\BookStop\..."`
- PowerShell does not support `&&` — run git commands on separate lines

### What's tracked vs local-only

| File / location | Tracked? | How edits happen | How edits verify |
|---|---|---|---|
| `app.js`, `*.html`, `style.css`, `config.js`, `docs/**`, `supabase/functions/**`, `CLAUDE.md`, `README.md` | Tracked per branch | `str_replace` + commit | `git diff` + smoke test |
| `import.js`, `import-staging.js` | **Private scripts repo** (`github.com/mrcyberrick/comic-preorder-scripts`; the `scripts/` folder is its working tree — since 2026-07-08) | `str_replace` + commit | `node --check` + `--no-write` dry run + `git diff` |
| `test-magic-link.ps1`, `test-this-week.ps1`, playwright suite, `.env`, canary scratch files, `phase-4-prod-tenant-uuid.txt`, `security-findings-local.md` | Local-only (allowlist `.gitignore` in the scripts repo enforces this) | Direct edit | Run-test |

The import scripts are credential-free as of 2026-07-08: service keys and
tenant UUIDs load from the scripts folder's gitignored `.env`
(`IMPORT_SERVICE_KEY[_PROD]`, `IMPORT_TENANT_ID[_PROD]`, `SUPABASE_URL[_PROD]`
— see `.env.example`), and each script hard-fails on a missing var or a URL
pointing at the wrong project. The `.env` and all scratch/schema/test files
remain local-only and must never be committed to any repo.

### Supabase platform facts
- **Anon key is public by design.** RLS is the security boundary. A committed
  anon key in `config.js` is not a finding.
- **Service-role key bypasses RLS.** Lives only in local scripts; never in
  client code or any committed file.
- **Edge Functions follow off-plus-in-body-auth — MOST of them.** JWT
  verification disabled at the platform level is the recommended pattern for a
  function that must also accept a non-user caller (a service-role key, e.g.
  `notify-customers` invoked by the import script) or no caller at all (a public
  endpoint like `register-customer`); in-body `Authorization` header
  verification (`/auth/v1/user` → profile lookup, or Turnstile/honeypot for the
  public case) is the actual gate there. JWT-off is not a misconfiguration.
  **This is not universal, corrected 2026-08-31 (F99 S1)** — the previous
  wording implied all Edge Functions are JWT-off; measured live against the
  staging dashboard, `approve-customer` and `send-my-list` actually run
  `verify_jwt = ON`. Both already forward the caller's own bearer token to
  `/auth/v1/user` themselves (in-body check, same as the off functions), so the
  platform-level check is additive, not their only gate — and a plausible
  reason they can afford it is that neither ever needs to accept a
  non-user-JWT caller the way `notify-customers` (service-role) or
  `register-customer` (anonymous) do. **That reasoning is inference, not
  independently confirmed** — no one has audited why these two specifically
  differ from `invite-customer` (also admin-only, but OFF). Read each
  function's live `verify_jwt` setting before assuming either state; do not
  deploy any of the six without explicitly preserving whatever the dashboard
  shows, per F93 discipline (`docs/f99-sender-domain-consolidation.md` § 4 S1).
- **Supabase SQL Editor runs as `postgres` superuser** — it bypasses RLS. To
  test RLS isolation, simulate an authenticated user with `SET LOCAL role
  authenticated` and `SET LOCAL "request.jwt.claims"` inside a transaction.

### Database project URLs
| Environment | URL | Project ref |
|---|---|---|
| Production | `https://plgegklqtdjxeglvyjte.supabase.co` | `plgegklqtdjxeglvyjte` |
| Staging | `https://puoaiyezsreowpwxzxhj.supabase.co` | `puoaiyezsreowpwxzxhj` |

**Founding tenant UUID (staging):** `72e29f67-39f7-42bc-a4d5-d6f992f9d790`
**Production founding tenant UUID:** generated during 4.2; lives in scratch file
`scripts/phase-4-prod-tenant-uuid.txt` (gitignored).

### SQL authoring rules (added 2026-07-15 after repeated schema-guess errors)
Before writing ANY SQL or PostgREST query, read `docs/technical-reference.md`
for every table touched — never write column names from memory. Traps that have
each cost a failed iteration: `catalog` uses `price_usd` (not `price`) and
requires `catalog_month`; the distributor enum is exact-case `Lunar` / `PRH`;
admin views match titles on `item_code` (`upc` is null for some titles); every
INSERT passes `tenant_id` explicitly. For multi-row seeds, dry-fit ONE row and
verify it before running the rest. (Local skill: `/sql-check`.)

---

## 🚨 Anti-Drift Rules for Agentic Sessions

These rules apply to any agentic session (Claude Code CLI, Claude in VS Code, etc.).

### One sub-deploy per session
A session targets exactly one sub-deploy from the active phase plan. Do not bundle
changes from multiple sub-deploys, even if they look related.

### Stop and ask, don't fix inline
If you discover a real bug out of scope for the active sub-deploy:
1. Stop work
2. Describe the bug
3. Ask whether to (a) fix it now as a separate commit, (b) file it for later, or (c) ignore it
4. Wait for explicit answer before proceeding

This applies even when the bug blocks your testing. The user decides scope expansion,
not the agent.

### Verify before escalating
Distinguish "I observe X" from "X is a problem requiring remediation."
- For platform-behavior or security claims, verify against the live system or
  official docs before proposing action
- For findings filed in `technical-reference.md` § 13, use the next-available
  finding ID — never guess or reuse. Check the highest existing ID first
- A surprising query result triggers re-verification, not immediate remediation

### Runbook construction standards
- `old_str`/`new_str` blocks must match the actual file content byte-exactly.
  Verify the target range via `view` or `Select-String` before applying
- Verification grep counts are derived by counting occurrences in the `new_str`
  literally, never estimated from memory
- Each finding fix is a separate commit with the finding ID(s) in the message
- A failed pre-check or verification is a halt-and-report, never an improvise

### Status update — end every session
Before the session closes, produce:
- What was changed (files + line ranges, or SQL run)
- What was verified (queries run, smoke tests passed)
- What is left for the next session
- Any out-of-scope discoveries that were filed rather than fixed
- New finding IDs assigned, if any

### Never assume previous-session state matches current state
At session start, re-read the relevant files from disk. Do not infer file contents
from earlier sessions, from this `CLAUDE.md`, or from any reference doc.

---

## Response Discipline (chat sessions)

These guide the planning-side agent (chat), not the CLI runbook execution.

- Lead with the decision or action. Rationale follows and is bounded. Full detail
  belongs in artifacts (plans, runbooks) and explicit requests, not every turn
- Edit documents in place with targeted changes. Never regenerate a full document
  to alter a few lines; surface changed sections plus a one-line summary of what
  changed
- Offer one recommended next step, not a menu of options, unless the user asks
  to choose
- Do not restate settled context or re-litigate settled decisions; point to where
  a decision was logged instead
- Only runbooks instruct the CLI. Chat content is for planning and exploration;
  chat speculation is never a directive. When uncertain, say so and give a
  verification step rather than a confident wrong direction

---

## Session Opening Protocol

At the start of every session:
1. Read this file in full
2. Read the active phase plan referenced in § Current Migration Phase
3. Read the active sub-deploy plan
4. State which sub-deploy is being executed and confirm with the user
5. List files that will be modified and read them from disk before proposing changes
6. Confirm staging target

If any step 2–5 cannot be completed (file missing, plan not yet written, ambiguous
scope), stop and ask before proceeding.

At the end of each session:
- Remind the user to copy output files to the repo
- Remind the user to push to staging and smoke test before promoting to production
- Note any production database changes needed
- Note any local script updates needed (`import.js`)
- Produce the status update described in Anti-Drift Rules

---

## Project Overview

**App:** PULLLIST — comic pre-order system for Ray & Judy's Book Stop
**Phone:** 973-586-9182
**Location:** Rockaway, NJ
**Production URL:** https://pulllist.app/
**Staging URL:** https://staging.pulllist.pages.dev/
**Legacy prod URL:** https://mrcyberrick.us/comic-preorder/ — **kept warm, decision closed 2026-08-29 (Rick): "keep warm if there is no cost, otherwise close." Measured: it is free**, because `mrcyberrick/comic-preorder` is a **public** repo (GitHub Pages hosting and bandwidth cost nothing there), and `mrcyberrick.us` is a pre-existing registration independent of this. `mrcyberrick.github.io/comic-preorder/` **301**s here; here returns **200**. This closes the retirement question left open at 5.5 S6 (2026-07-15) and again in Phase 5's completion criteria.
> **⚠️ What is kept warm is NOT a frozen rollback snapshot — measured 2026-08-29, not assumed.** It **auto-deploys from `main`** and currently serves the 2026-08-24 Lighthouse-sweep build with the **production** `config.js` (prod Supabase ref `plgegklqtdjxeglvyjte`, prod founding-tenant UUID). And because `tenantSlugFromHostname()` finds no tenant slug in `mrcyberrick.us`, the pre-paint script sets `data-front-door="apex"` — so this URL renders the **platform marketing page**, not Ray & Judy's branded sign-in.
> **Why that is a caveat and not a defect:** the apex carries universal login, and the same script's `token_hash`/`access_token` handling still opens the sign-in panel, so **a magic link landing here works**. Nothing is broken and no customer is routed here — the print CTA points at `rjbookstop.pulllist.app`. What a rollback would cost is the *branded* first impression, not access. **No finding filed.** Treat this as a live auto-deploying mirror of production on the apex front door, not as a point-in-time rollback target — and if a genuine frozen rollback is ever wanted, that is different work.

---

## Repository Structure

```
comic-preorder/                    ← production repo (github.com/mrcyberrick/comic-preorder)
  index.html                       ← sign-in / landing
  catalog.html                     ← ┐
  mylist.html                      ← │ the SIX nav+footer pages that must
  arrivals.html                    ← │ stay in sync (see § Files That Must
  subscriptions.html               ← │ Stay in Sync)
  admin.html                       ← │
  analytics.html                   ← ┘ admin-gated nav link — but it DOES
                                   ←   carry the shared nav+footer blocks
  forgot-password.html             ← linked from the index.html sign-in footer
  app.js
  style.css
  config.js                        ← tracked per branch; never edited by agent
  CLAUDE.md                        ← this file
  README.md
  supabase/functions/              ← all 9 Edge Functions (8 post-4.1 Session 1; register-tenant added 5.4 S3)
  docs/
    technical-reference.md         ← canonical schema + findings index § 13
    pre-multitenancy-state.md      ← § 1, § 3, § 5 still valid; § 2/§ 4 superseded
    production-baseline-2026-05-28.md  ← live audit; supersedes stale snapshot
    phase-*.md                     ← phase parent plans + sub-deploy plans
```

**Git remotes:**
- `origin` → production repo (`github.com/mrcyberrick/comic-preorder`)
- `staging` → staging repo (`github.com/mrcyberrick/comic-preorder-staging`) — **no longer a deploy target as of 5.1**; kept warm as rollback past the original "until 5.5 closes" gate — Rick's call 2026-07-15 at 5.5 S6 was to keep it warm and revisit retirement in a future session

### ⚠️ `main` is NOT simply "staging + prod config.js" (F125)

**`supabase/migrations/` exists only on `main` and has never existed on `staging`.**
Two files, both committed directly to `main` during the Phase 4 cutover window
(which § Staging Only expressly permits for a named cutover sub-deploy):

| File | Commit | Sub-deploy |
|---|---|---|
| `20260531030927_phase_4_3_prod_constraints.sql` | `9111412` | Phase 4.3 |
| `20260531150558_phase_4_4_prod_rls_functions.sql` | `3ecb6b0` | Phase 4.4 |

Nothing else differs structurally — verified 2026-08-10, these are the only two
paths present on `main` and absent from `staging`.

**Why this matters when designing a promotion flow.** The documented
`git merge staging --no-ff` flow is immune: staging never held these paths, so
there is no deletion in its history to replay, and both files have survived
every promotion to date. But **any promotion that rebuilds `main`'s tree *from*
`staging` rather than merging into it** — a squash promotion, a rebase-based
flow, `git checkout staging -- .`, or a `git reset --hard staging` used to
tidy a messy `main` — would silently delete the only in-repo copies of that
production DDL. The knowledge survives in `docs/phase-4.3-*.md` / `4.4-*.md`
(on both branches) and the DDL is live in production, so a loss is
repo-history only. That is why this is a documented trap, not a defect.

**Do not "fix" this by deleting them from `main`**, and **do not copy them onto
`staging`** — that would put prod-cutover DDL on a branch that must never run
it. Every migration since has gone to `docs/sql/` instead, which is the correct
convention and is already followed; these two are pre-convention residue.
(`docs/sql/` tracks forward normally — staging runs ahead of main between
promotions, which is expected and is not this asymmetry.)

**A fifth trigger, hit for real on 2026-08-24 and caught one step before the
merge button: a promotion branch accidentally cut from `staging` instead of
`main`.** The listed triggers above are all deliberate acts (squash, rebase,
`checkout staging -- .`, `reset --hard`). This one is an accident, which makes
it more dangerous. A cherry-pick promotion was branched with
`git checkout -b <branch>` from *ambient HEAD* while a second person was
committing in the same working tree; HEAD had moved to `staging` in between, so
the branch inherited staging's tree. The resulting PR would have **deleted both
`supabase/migrations/` files AND overwritten `config.js` with the staging anon
key**, pointing production at the staging Supabase project. PR closed unmerged,
branch deleted, `main` never touched.

**Why the usual checks did not catch it.** Per-file checks all *passed* —
`ls supabase/migrations/` showed two files, `grep` found no barcode markers,
`config.js` was not in `git status`. They were reading a working tree that was
correct at that instant, on a branch that was not. **The check that caught it
was `git diff --stat origin/main <branch>`** — scope of the whole diff against
the *remote* base, not spot-checks against local state.

**So, for any promotion branch:** create it from an explicit ref
(`git checkout -B <branch> origin/main`), never from ambient HEAD, and assert
the full diff before pushing — exactly one expected scope, `supabase/migrations/`
still at 2 files, and `config.js` still carrying the prod project ref
`plgegklqtdjxeglvyjte`. Assume HEAD can move under you: this repo has more than
one actor in it.

**Local scripts folder** (working tree of the **private scripts repo**
`github.com/mrcyberrick/comic-preorder-scripts` since 2026-07-08 — only the
import scripts, credential-free tests, and repo metadata are tracked; `.env`,
scratch state, and the Playwright suite stay local-only via the allowlist
`.gitignore`):
```
C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts\
  import.js                       ← production import script (tracked)
  import-staging.js               ← staging import script (tracked)
  test/                           ← credential-free unit suite (tracked; run: npm test)
  test-magic-link.ps1
  test-this-week.ps1
  phase-4-prod-tenant-uuid.txt    ← generated at 4.2 pre-flight
  phase-4.1-canary-uuids.txt      ← canary tenant identifiers (Session 2)
  phase-4.1-canary-teardown.sql   ← FK-ordered teardown for Session 3
  .env                            ← script credentials
  package.json
  playwright/                     ← local smoke suite
```

**Catalog CSV files:**
```
C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\
  Lunar_Product_Data_MMYY.csv
  YYYY_MM_PRH_metadata_full_active.csv
  normalized_catalog.json
```

---

## Tech Stack

- **Frontend:** Vanilla HTML/CSS/JS — no build step, no npm for the web app
- **Backend:** Supabase (PostgreSQL + Auth + Edge Functions + RLS)
- **Hosting:** Cloudflare Pages (static files only; migrated from GitHub Pages in 5.1)
- **Email:** Resend, both environments (F99 migration M1–M7, 2026-09-02 — see § Current Migration
  Phase), via Supabase Edge Functions. MailerSend's credentials remain set on both projects, dormant,
  as an undeleted rollback path (M8, optional, not scoped)
- **Import:** Node.js script run locally each month

Cloudflare Pages serves static files only — no SSR. All dynamic behavior is client-side
JS calling Supabase directly.

---

## Standard Deployment Workflow

Local skills `/deploy-staging` and `/promote-prod` encode this section's gates
step-by-step (plus `/preflight` for session-start checks) — prefer invoking
them over re-typing the flow.

```powershell
# Start a new feature
git checkout staging
git pull origin staging
git checkout -b feature/<description>

# Make changes, then commit
git add <files>
git commit -m "<type>: <description>"

# Merge to staging (fast-forward only — clean linear history)
git checkout staging
git pull origin staging
git merge --ff-only feature/<description>

# Optional pre-push baseline — see "Smoke-test ordering" below for why full
# Playwright here does NOT test your change. -SkipPlaywright (added 2026-08-29)
# runs just stage [1/2] (npm test, against local files, ~3s) and skips the
# ~16min Playwright stage, which would only exercise the OLD deployed build.
cd C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts\playwright
.\run-smoke.ps1 -SkipPlaywright

git push origin staging
# CF Pages auto-deploys the staging preview at https://staging.pulllist.pages.dev/
# (Do NOT run: git push staging staging:main — retired as of 5.1)

# Wait for the build, then CONFIRM the new bytes are actually served before
# trusting any test result (~30-60s; note -L, without it the redirect yields
# an empty body that looks like a stale build):
#   curl.exe -s -L "https://staging.pulllist.pages.dev/style.css"
# and match a marker string your change introduced.
#
# CHECK THE PLAIN URL, NOT A CACHE-BUSTED ONE (corrected 2026-08-07). This
# line previously appended "?cb=$(Get-Random)". A query string is a DIFFERENT
# Cloudflare cache key, so it can fetch the new build while the plain URL a
# browser (and Playwright) actually requests is still serving the old one —
# a green "new bytes served" check followed by a test failing against stale
# bytes. That happened on 2026-08-06: a spec asserting a brand-new CSS class
# failed with 0 elements, looked like a code defect, and was neither. Verify
# what the browser will get. Cache-busting is for forcing a fresh read when
# you WANT to bypass the edge, which is the opposite of this check's purpose.

# THEN run the authoritative smoke pass — this one exercises your change:
.\run-smoke.ps1
# Stop and fix (or revert the push) if anything fails.

# Test at: https://staging.pulllist.pages.dev/
# When staging tests pass, promote to production:
git checkout main
git pull origin main
git merge staging --no-commit --no-ff
git checkout main -- config.js   # preserve prod credentials (config.js is tracked per-branch)
# Assert critical app files actually changed (catches merge-base regression — see F59):
foreach ($f in @('app.js', 'mylist.html', 'arrivals.html', 'admin.html')) {
    $diff = git diff "main:$f" "staging:$f" 2>$null
    if ($diff) { Write-Host "ok: $f differs from main (will update)" }
    else { Write-Host "WARN: $f identical to main — verify this is expected, NOT a merge-base regression" }
}
git commit -m "<type>: <description>"
git checkout -b feat/<description>-prod
git push origin feat/<description>-prod
# Open PR: feat/<description>-prod → main
# Verify config.js is NOT in the diff before merging
# CF Pages auto-deploys production from main at https://pulllist.app/
# Post-deploy write-smoke: reserve one item through the live app as a test user, confirm
# the row lands in prod preorders with correct tenant_id, then cancel it.
```

### Smoke-test ordering (corrected 2026-07-28)

**`run-smoke.ps1`'s two stages test different things, and only one of them can
see unpushed work:**

- **[1/2] `npm test`** — the scripts repo's import-script unit suite, run against
  **local files**. Genuinely pre-push, and the stage that matters when the change
  is to `import.js` / `import-staging.js`.
- **[2/2] Playwright** — `baseURL` is `https://staging.pulllist.pages.dev/`
  (`playwright.config.ts`), i.e. the **deployed** site. It loads the web app over
  HTTP and **cannot see the working tree at all.**

So for any change to `app.js` / `*.html` / `style.css`, a pre-push run exercises
the **previous** build. This section previously read "Run smoke tests before
deploying / Stop if anything fails — do not push", which cannot work as written
for app changes: a green pre-push result says nothing about the code being pushed.

Push first, confirm the new bytes are served, then run the suite. Keep the
pre-push run if you want a baseline — knowing staging was already green makes a
post-push failure attributable — but it is a baseline, not a gate. Use
`run-smoke.ps1 -SkipPlaywright` for it (added 2026-08-29): stage [2/2] there
would only exercise the old deployed build anyway, so running it pre-push cost
~16 minutes for zero evidentiary value. `-SkipPlaywright` keeps stage [1/2]'s
real signal (~3s) and drops the part that couldn't tell you anything yet.

**This is the second time this was found.** `docs/subscription-promotion.md`
§ "Deploy sequencing note (2026-07-17)" records the same discovery and Rick
confirming the same resolution — push to staging first, then run the suite as
the real gate. That note stayed in a feature plan doc and CLAUDE.md was never
corrected, so the stale ordering survived here and in `/deploy-staging` and cost
the rediscovery on 2026-07-27. The 2026-07-17 framing was also narrower than the
truth: it read as applying to *genuinely new UI* whose specs did not exist yet.
It applies to **every** web-app change, because the suite always loads the
deployed build over HTTP — new specs or old.

**Green is not the same as verified.** The suite only covers what has specs.
The catalog **info-card** reserve path had **no coverage at all**, which is how
four defects shipped there unnoticed in July 2026 — closed by spec 14
(2026-08-02, see F103). The **order-export / order-ledger** path shipped to
production the same way on 2026-08-03 and was closed by spec 15 the same day.
Both are cautionary: in each case the gap was noticed only *after* the code was
live, and in both cases the fix was cheap once someone looked. Check whether
your change is actually covered before treating a pass as verification; if it
isn't, a real-browser check is the only evidence you have — and adding the spec
is usually an hour, not a project.

---

## Database Schema

The full current schema lives in `docs/technical-reference.md` — canonical source
of truth. Read it before making any schema-related claim.

**Do not infer schema details from this file or from earlier sessions.** The
schema changed materially in Phase 1 (multi-tenancy) and continues to evolve.

Quick orientation only:
- Multi-tenant via `tenants` table; every tenant-scoped table has `tenant_id`
  (staging post-Phase-1; production after 4.2 lands)
- RLS enforces tenant isolation via `current_tenant_id()` + `current_user_is_admin()`
- Import script uses service-role key (bypasses RLS); web app uses anon key
- Founding tenant UUIDs documented in § Environment Facts above

**Post-Phase-3.3 (staging):** `tenant_id` column defaults removed. Every INSERT
must pass `tenant_id` explicitly. The only exception is the defensive try/catch
in `UsageEvents._log()` which falls back to `FOUNDING_TENANT.id` if
`TenantContext.current()` is called before `resolve()` completes.

---

## app.js Structure

Source of truth: read `app.js` directly. Major API objects on `window`:
`Auth`, `Catalog`, `Preorders`, `Subscriptions`, `Settings`, `AdminContext`,
`NavBubble`, `TenantContext`, `Maintenance`. Read the file before making claims
about specific method signatures — this file deliberately does not duplicate
the API surface to avoid drift.

**Post-Phase-3.1:** `TenantContext` resolves the active tenant on page load.
`initNav()` calls `TenantContext.resolve()` before any other init.

**Post-Phase-3.2:** All `app.js` writes pass `tenant_id` explicitly using
`TenantContext.current().id`.

**Maintenance mode:** `Settings.isMaintenanceMode()` reads `app_settings.maintenance_mode`
on every authenticated page load. When true, `checkMaintenanceMode()` replaces
`document.body` with a holding-page banner and throws to halt page init for
non-admins. Write-blocking by construction. Admins always get through.

---

## Key Business Logic

### Catalog Month Scoping
- **My List table:** current catalog month reservations only
- **Upcoming Arrivals section:** all future reservations across all months
- **Admin dashboard:** stats + tabs scoped to current catalog month
- **This Week** (nav badge, arrivals page, admin bagging tab): Mon-Sun calendar
  week containing today's local date. Shared helper `DateUtils.weekRange()` in
  `app.js` is the single source of truth. Wednesday is not special; do not
  introduce Wednesday-anchored logic.

### Local Date Pattern
Always use local date parts (not `toISOString()`) to avoid UTC timezone shift.
Use `DateUtils.todayLocal()` for today's date and `DateUtils.weekRange()` for
the Mon-Sun window. Never reintroduce `toISOString()` for date comparisons or
date display — see F28 in `technical-reference.md` § 13.

### Past Item Auto-Hide
Items from previous months where `on_sale_date < today` are hidden from My List
(client-side filter in `mylist.html`).

### Series Subscriptions
- Subscribe button appears only on standard covers (`variant_type` null,
  `'Standard'`, or `'Primary Title'`)
- **Full admin write access during impersonation (F138, 2026-08-22, reverses
  F128/§ 4c's earlier disabled-button design).** On `subscriptions.html`,
  admins can subscribe and unsubscribe on the impersonated customer's behalf
  — reserved-suggestions list, series search, and the main subscriptions
  table all write through `AdminContext.resolveUserId(user.id)`, backed by a
  new `admins manage tenant subscriptions` RLS policy mirroring `preorders`'.
  **Fully RESOLVED, both environments, 2026-08-22** (staging V1–V4 green;
  production RLS migration same day + client code via PR #129 `f1364a785`).
  Re-verified 2026-08-24 against the served bytes: `pulllist.app`'s
  `subscriptions.html` calls `resolveUserId` ×6 and carries **zero**
  impersonation guards, and § 4.x records the `admins manage tenant
  subscriptions` policy as verified live on both environments.
  *(This line read "not yet promoted to production" until 2026-08-24 — the
  2026-08-23 correction fixed § Current Migration Phase and § 13 but missed
  this copy in § Key Business Logic. Same defect, third surface.)*
- Import script auto-reserves standard covers for subscribers each month
- `subscriptions.html` shows an always-on "Series you're already reading"
  one-click subscribe list built from the customer's own reservations; the
  hand-curated "Popular at Book Stop" section was removed 2026-07-19 and
  `app_settings.popular_series` is no longer read by the app

### Variant Type Handling
- Lunar standard: `variant_type = 'Standard'` or null
- PRH standard: `variant_type = 'Primary Title'` or null
- All others are variants — no subscribe button

---

## Monthly Import Script Behavior

The import script (`import.js` / `import-staging.js`) runs locally each month:

1. Reads Lunar + PRH CSV files
2. Normalizes records (post-Phase-1 includes `tenant_id`)
3. Detects new vs same vs older catalog month (post-4.0 staging)
4. On new month: archives reservation history, purges stale unreserved rows
5. **Upserts** catalog records (preserving UUIDs — critical for preorder integrity)
6. On new month: removes items dropped from distributor catalog since last import
7. Auto-reserves standard covers for subscribers (skipped on older-month backfills
   or with `--skip-autoreserve`)
8. Optionally imports weekly shipment invoices into `weekly_shipment`
9. Prompts to send customer notification emails

**Both scripts pass `tenant_id` everywhere** (upsert key, normalized records,
auto-reserve inserts, `p_tenant_id` to all RPC calls) and are tenant-aware and
credential-free (`.env`-driven since 2026-07-08; production was patched in
sub-deploy 4.5). Both are versioned in the private scripts repo, which carries
a credential-free unit suite (`npm test` in the scripts folder — shipment row
builders + prod↔staging parity; see `test/README.md` there).

Re-running either script on the same month is safe — upsert in place;
auto-reserve detects existing reservations and skips.

---

## Edge Functions

All **9** functions are in the repo at `supabase/functions/*` (8 landed post-4.1
Session 1; `register-tenant` was added at 5.4 S3, commit `0bdc55c`, whose own message
reads *"EF inventory -> 9"*). *(This line and § Repository Structure both read "8" until
2026-09-01 — a miscount, not a missing function: `register-tenant` is fully documented in
`docs/phase-5.4-tenant-signup.md`. Found while planning F72; corrected as a doc fix, no
finding consumed, per that plan's § 8 Q4.)*
Tenant-aware as of Phase 2 + 4.1 hardening:
- `notify-customers` — in-body admin auth (F47); recipient list scoped to caller's tenant
- `create-paper-customer` — in-body auth; JWT-off platform setting (post-4.1 C13)
- `invite-customer` — in-body auth; explicit `tenant_id` + inline HTML template
- `register-customer` — **public by design**; `tenant_id` resolved from the posted
  `slug` (F34 residual closed 5.4 S2 — no longer founding-pinned). Abuse gate:
  honeypot + server-verified Turnstile + `already_exists` dedup. **The MailerLite
  `?secret=` webhook path was removed 2026-08-30** (native-signup § S5) —
  platform-wide, so no tenant has it; `?secret=` is now inert and
  `tenants.settings->>'mailerlite_webhook_secret'` is dead config. **F72 is still
  open**: its confirmation email stays founding-branded for every tenant, which is
  the real gate on a second tenant taking real customers
- `send-my-list` — in-body auth + caller identity check (F51, F54); tenant-scoped queries
- `claim-paper-customer` — in-body auth; PATCHes tenant-scoped (F50)
- `approve-customer` — PATCH-only on existing rows; tenant inherited from row
- `reset-password` — public endpoint by design. **Holds no tenant reference at all** —
  the only one of the six mail-sending functions that does not (relevant to F72; see
  `docs/f72-multi-tenant-branding.md` § 4.2.2)
- `register-tenant` — **gated operator provisioning EF** (added 5.4 S3); service-role
  tenant creation behind an operator secret. Phase 6 reuses this engine unchanged in its
  core and layers public self-serve on top. See `docs/tenant-onboarding-runbook.md` Step 1

`FOUNDING_TENANT_ID` secret must be set in Supabase staging → Edge Functions →
Secrets for tenant-aware functions to work.

---

## Known Out-of-Scope Items

Do NOT touch any of the below in agentic sessions without explicit approval.

**Genuinely still open or deferred:** Partial fulfillment is not representable (product decision,
deferred until product scoping — no finding ID). Everything else currently open is F72, F89, F90,
F99, and F126's residual — see the open-findings table in § Current Migration Phase; full
detail lives only in `docs/technical-reference.md` § 13. **F92 closed 2026-08-18, F136+F137 closed
2026-08-22** — see § 13.

**Closed work — kept here as a "don't re-open without asking" index only. Each doc's own
`**STATUS:**` token and `docs/technical-reference.md` § 13 are the evidence; this table is not:**

| Work | Doc | Key findings closed |
|---|---|---|
| Order-export FOC window + order state | `order-export-foc-window-and-order-state.md` | F101, F102 |
| Order-export follow-through (withdrawals, cross-month FOC, distributor model) | `order-export-followthrough-f110-f111-f112.md` | F110–F114 |
| Closing the ad-hoc order loop | `order-loop-closure-f108.md` | F108, F117–F120 |
| Order Builder record/download split | `order-builder-record-split.md` | — |
| Admin restructure — Sessions 1–6 | `admin-dashboard-process-map.md` + per-session docs | F121, F122, F124 |
| Admin Accounts tab + account lifecycle | `admin-accounts-tab.md`, `admin-account-lifecycle-f126.md` | F126 (partial — residual open), F127 |
| `auto_fulfill_past_on_sale()` current-schedule fix | `f122-auto-fulfill-current-schedule.md` | F122, F124 |
| `preorders` authorization boundary (status gate + ordered-cancel trigger) | `preorders-authorization-boundary-f127-f109.md` | F127, F109 |
| Phase 5 — second-tenant onboarding (all sub-deploys) | `phase-5-second-tenant-onboarding.md` | F105 |
| Test-infrastructure maintenance | `test-infra-maintenance-f91-f95-f103.md` | F91, F95, F103, F107 |
| Catalog-month integrity — stale-date detection + duplicate-row cleanup (S1-S3) | `f136-catalog-month-integrity.md` | F136, F137 |
| Ordering-side rejection handling | `f143-f144-ordering-side-rejections.md` | F143, F144 |
| `import.js` maintenance (key rotation, historical dedup, cross-month fix) | `import-js-maintenance-f75-f78-f85.md` | F75, F78, F85 |
| F86 prod legacy API key retirement | `f86-anon-key-migration.md` | F86, F88 |
| Mobile thumb-reach tab bar + live-review follow-up | `mobile-nav-tab-bar.md` | — |
| Analytics cycle-alignment | `analytics-cycle-alignment.md` | — |
| Analytics v2 engagement dashboard | `analytics-v2-engagement-dashboard.md` | — |
| Catalog info-card reserve-sync fix (no plan doc — direct bug fix, PR #99) | — | F103 (coverage gap it exposed) |
| `Preorders` pagination past PostgREST's 1000-row cap (no plan doc — direct bug fix, PR #130) | — | F139 |
| Six more unbounded-query pagination gaps, app-wide audit (no plan doc — direct bug fix, PR #131) | — | F140 |
| Admin write access to `subscriptions` during impersonation (no plan doc — direct fix, PR #129) | — | F138 (reverses F128) |
| Subscription reserved-suggestions | `subscription-reserved-suggestions.md` | — |
| Subscription promotion | `subscription-promotion.md` | — |
| Apex marketing page + universal login | `apex-landing-tenant-subdomains.md`, `apex-marketing-page-design.md` | — |
| Native in-app customer self-registration | `native-customer-signup.md` | F94 |
| Weekly pipeline hardening (Brevo send verification, single-commit publish) | `weekly-pipeline-hardening.md` | F96, F98, F100, F106 |

All doc paths above are relative to `docs/`. If a session needs to touch any of the above, **stop
and confirm**.

*(Rewritten 2026-08-18 in the doc-status truth pass — this section was 375 lines of narrative that
duplicated each closed feature's own plan doc and `technical-reference.md` § 13, the same drift
source the pass exists to remove. The removed narrative is not lost: it is in git history on this
branch, and in fuller, more current form in the docs this table points to.)*

---

## Known Issues & Gotchas

- **PowerShell:** does not support `&&` — separate lines
- **PowerShell + Supabase:** `Invoke-RestMethod` mangles JSON quotes in argv and
  triggers 401s with `sb_secret_` keys. Use `curl.exe` with `--data-binary @file`
  for tenant-aware Supabase calls. See `test-magic-link.ps1`
- **OneDrive + PowerShell scripts:** OneDrive flags synced `.ps1` files as
  "downloaded from internet," blocking execution. Run `Unblock-File .\<script>.ps1`
  after each sync
- **Agent edits strip the UTF-8 BOM from `.ps1` files** — PowerShell 5.1 then
  reads the file as CP1252, and an em dash inside a double-quoted string decodes
  to `â€”` whose trailing `”` is a legal PS quote char: string boundaries silently
  shift and later code is swallowed into string literals with NO parse error
  (run-smoke.ps1 skipped its entire Playwright stage and exited 0, 2026-07-16).
  After ANY agent edit to a `.ps1`, restore the BOM and verify the script still
  reaches its last stage:
  `[IO.File]::WriteAllText($p, [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8), [Text.UTF8Encoding]::new($true))`
- **Supabase `range()`:** returns 416 on empty result sets — use count-first approach
- **UTC timezone shift:** never use `toISOString()` for date display — use local parts
- **Import script service key:** must be `service_role` (or `sb_secret_`), NOT
  anon — RLS blocks anon
- **`nav-hamburger`:** must be present in every HTML file's nav
- **RLS recursion:** admin policies referencing `user_profiles` via `EXISTS (SELECT
  ... FROM user_profiles)` cause infinite recursion → 500 errors. Use
  `current_user_is_admin()` SECURITY DEFINER. Already in place post-Phase-1
- **Supabase Auth admin `?email=` filter:** intermittent 500 ("Database error
  finding users"). Query `user_profiles` via PostgREST instead
- **`import-staging.js` was hot-patched 2026-05-08** for a `weekly_shipment`
  tenant_id NOT NULL violation — re-syncing from an earlier backup reintroduces
  the bug. See `phase-3-tenant-resolution.md` § Discovered During Soak

---

## Files That Must Stay in Sync

The nav block must be identical across **six** pages: `catalog.html`,
`mylist.html`, `arrivals.html`, `subscriptions.html`, `admin.html`, and
**`analytics.html`**. When updating nav, copy from the most recently-updated
file — the canonical version is whichever HTML file was last touched.

**`analytics.html` was omitted from this list until 2026-08-15**, and this
section plus § Repository Structure both described it as having no shared nav
block. That was wrong — measured, not assumed: all six nav blocks hash
identically (`66C5139EF8AD97147227FB7A7EB38F56`), all six footer blocks hash
identically (`EB2513E8ED474B3CE5251F2540A69852`), all six load
`vendor/supabase.min.js` → `config.js` → `app.js`, and all six call
`initNav()`. `analytics.html` is a full member of the sync set on every
contract in this section. Found while planning `docs/mobile-nav-tab-bar.md`,
where a five-file nav edit would have silently skipped it.

The footer block must be identical across all six pages, placed immediately
before `<div id="toast-container"></div>`.

The `<script>` load order must be the same on every page: Supabase UMD bundle
→ `config.js` → `app.js` → page-specific code.

---

## Smoke Test Suite (local)

**Location:** `C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts\playwright\`
(local-only; never committed)

```powershell
cd C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts\playwright
.\run-smoke.ps1                              # full suite (the real gate — run once, post-push)
.\run-smoke.ps1 -SkipPlaywright               # unit suite only, ~3s — pre-push baseline (added 2026-08-29)
.\run-smoke.ps1 -Headed                       # browser visible
npx playwright test 04-arrivals-this-week     # single spec
```

**Coverage:** magic-link auth, catalog reserve → mylist, cancel guards, arrivals
orphan-reserved rendering, subscriptions, admin bagging + week nav, tenant
isolation (F15, F20), per-tenant branding unit spec, catalog info-card reserve
(spec 14, added after F103), and the **order-export / order-ledger path**
(spec 15, added 2026-08-03 — see below). `run-smoke.ps1` runs the scripts
repo's committed unit suite (`npm test`, step [1/2]) before Playwright; the old
local `node-tests/` copy was retired 2026-07-16. **56 Playwright tests as of
2026-08-03.**

**Spec 15 — `15-order-export-ledger.spec.ts` (F101/F102).** Covers the path
that shipped to production on 2026-08-03: the Order Builder opens with a
multi-select FOC-cycle list rather than downloading instantly; a title outside
the selected cycle is excluded **and** surfaced in the held-back panel (V3); an
already-ordered code is flagged with its prior quantity and defaulted to the
remainder, never auto-suppressed (V4); the Status-column button reflects
ordered-vs-reserved (`Mark Ordered` / `Add (n of m)` / `Over (n of m)` /
`Ordered (n)` disabled); the backorder-risk panel separates At risk,
Backordered and cleared-by-ledger (V7); and My List shows "Order placed" driven
by the ledger with `fulfilled` still false.
**Writing specs against this path: staging carries 857 real backfilled ledger
rows**, so seeded rows share every panel with production-shaped data. Assert on
a seeded title or `data-catalog-id` — never `.first()` and never an exact
count. A `.first()` assertion in the initial draft failed against a real
staging title, which is how this got caught.

### How to run it — targeted while iterating, full suite once as the gate

**Do NOT run the full suite after every change.** It is `workers: 1`,
`fullyParallel: false` (specs share staging state — spec 15 mutates
`app_settings.order_deadline` globally), so a full pass is **~16 minutes**. A
single spec is **~17 seconds**.

```powershell
# While iterating — run only what you touched
npx playwright test 17-admin-modes --grep "V1 — get_account_activity"
npx playwright test 15-order-export-ledger

# Once, before promotion — this is the gate
.
un-smoke.ps1
```

**Measured, 2026-08-09** (Rick asked whether the suite was earning its keep —
a fair question, and the numbers said *barely*). Seven full runs, ~100 minutes
of wall clock, which caught **2 real feature defects**, **4 of the agent's own
broken tests**, and **1 unexplained flake**. Five of those seven runs should
have been targeted; doing so would have saved ~70 minutes and caught the
identical two defects.

### What this suite is actually good at — and what it is not

Calibrate expectations before deciding a green run means anything:

- **Good at regression.** Did a change break something that already worked.
  Every UI restructure this year was caught this way.
- **Good at invariants you state explicitly.** The Accounts partition
  assertion (`the parts sum to the whole`) caught two defects **on a build
  whose real-browser check had already passed** — admins visible in one view
  and absent from another, and a filter matching a *type* while rows displayed
  a *state*. Neither was visible on screen. Four lines of assertion.
- **Bad at brand-new paths**, because a test written alongside the code
  inherits the code's wrong assumption. On 2026-08-09 the two defects that
  mattered most — an open SQL gate and a filter keyed on a column that
  defaults to `true` — were both found by **probing the deployed thing and
  reading what came back**, not by the suite. Purpose-built fixtures passed
  under both the wrong predicate and the right one.

**So: a green suite says the assertions hold, not that the feature is right.**
For new work, the cheap high-yield checks are (a) call the deployed endpoint
and read the response, and (b) look at what a new query or filter *returns on
real data* — not merely whether it runs.

### A verification step that cannot fail is not a verification step

Filed the same day, from a SQL file whose final statement reported the
function's **return signature** — identical before and after the fix it was
meant to confirm. The Supabase SQL Editor shows the last statement's result, so
the operator pasted the same meaningless output three times while the gate was
still open. **Before asking anyone to run a check, ask what its output looks
like when the thing has FAILED.** If that is the same, it is decoration.

### ⚠️ Do not run `run-smoke.ps1` through an agent's PowerShell tool (2026-08-30)

**Run Playwright directly, capturing output yourself:**

```bash
npx playwright test --reporter=line > /tmp/pw.log 2>&1; echo "EXIT=$?" >> /tmp/pw.log
```

**Why.** `npx` writes a `NO_COLOR`/`FORCE_COLOR` warning to **stderr**. PowerShell 5.1 wraps any
native command's stderr line as a `NativeCommandError`, and under an agent tool that surfaces as
**exit 1 with 15 lines of output and not a single test result** — no pass count, no failure list,
nothing attributable. The script's own logic is fine: line 62 uses `$LASTEXITCODE`, not `$?`. The
failure is in the wrapper, not the runner, and it is indistinguishable from a real red suite
unless you notice the output is too short to contain any tests.

**This is the third time this script has produced an untrustworthy result, and it has now failed
in both directions:**

| Date | Symptom | Verdict it gave |
|---|---|---|
| 2026-07-16 | BOM stripped by an agent edit → PowerShell swallowed later code into a string literal, Playwright stage never ran | **exit 0** — false GREEN |
| 2026-08-30 | stderr warning wrapped as `NativeCommandError` | **exit 1** — false RED |

**So: a `run-smoke.ps1` result is only trustworthy if the output actually contains a test count.**
Check for `N passed` before believing either colour. A green with no test lines is the 2026-07-16
shape; a red with no test lines is this one.

**Rick's call, 2026-08-30: doc note, not a finding — F148 stays free.** It is agent-environment
friction rather than a product defect; running it from a normal terminal is unaffected.

**Rules:**
- Local-only. Never committed. Never runs against production.
- `SUPABASE_URL` in `.env` must be staging; runner aborts if it's prod
- All `goto()` calls use paths without a leading slash

Canonical detail: `docs/phase-3.7-playwright-smoke-tests.md`
