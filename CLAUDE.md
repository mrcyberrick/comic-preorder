# CLAUDE.md — Project Instructions for PULLLIST

This file provides persistent context for Claude when working on the PULLLIST
comic pre-order system. **Read this file in full at the start of every session.**

---

## 🚨 Current Migration Phase

**Active phase:** **Phase 5 Complete** (closed 2026-07-15). Successor Phase 6 has not started — see below.
**Successor phase (stub):** Phase 6 — Open self-service tenant signup — `docs/phase-6-self-service-signup.md` (stub 2026-06-15; not started; gated on a wildcard-DNS/TLS spike). Phase 5's close (2026-07-15) satisfies the "begins only after Phase 5 closes" precondition; the wildcard-DNS/TLS spike gate remains open.
**Phase 3 status:** Complete — 3.1–3.7 closed 2026-05-13; 3.8 hardening closed 2026-05-15 (one-day soak clean)
**Phase 4 status:** **Complete** — 4.0–4.8 closed 2026-05-26 → 2026-06-10; completion audit closed 2026-06-10 (all Phase Completion Criteria ticked; recovery anchors verified — see `pre-multitenancy-state.md` § Phase 4 Completion)
**Phase 5 status:** **Complete — 2026-07-15.** All sub-deploys 5.0–5.5 closed; second tenant (`comicstore`, `comicstore.pulllist.app`) live on production, pilot/seeded; two-tenant soak passed (2026-06-20 → 2026-07-15, one full monthly import cycle 2026-07-08→10 elapsed, post-import isolation re-verification = 0 cross-tenant in both directions); onboarding generalized into `docs/tenant-onboarding-runbook.md`. Full completion evidence: `docs/phase-5-second-tenant-onboarding.md` § Phase Completion Criteria; `docs/phase-5.5-second-tenant-onboarding.md` § 5 / Deploy Log; `docs/phase-5.5-soak-log.md` § S4 close.
**Active sub-deploy:** none. Phase 6 not started (stub only, gated on the wildcard-DNS/TLS spike).
**Plan (Phase 5 parent):** `docs/phase-5-second-tenant-onboarding.md`
**Plan (Phase 4 parent):** `docs/phase-4-production-migration.md`
**Plan (Phase 3 parent):** `docs/phase-3-tenant-resolution.md`
**Last completed sub-deploy:** Phase 5.5 — Second-tenant onboarding + soak (Complete 2026-07-15) — `docs/phase-5.5-second-tenant-onboarding.md`. Tenant 2 (`comicstore`) live on prod via `register-tenant`; dedicated `comicstore.pulllist.app` custom domain + TLS; branding set; zero cross-tenant leakage verified (S3, re-confirmed post-import at S4 close); two-tenant soak passed across one full import cycle; onboarding runbook generalized (S5). Also corrected a stale F34-residual doc claim discovered during S6 verification (see `technical-reference.md` § 13 F34) — `create-paper-customer`/`invite-customer` were never actually hard-pinned post-2026-05-10; three docs (technical-reference.md, soak log, runbook) had carried the stale pre-fix description forward.
**Last completed phase:** Phase 5 — second tenant live on production with a verified two-tenant soak; onboarding is now operational, not an engineering phase
**Phase 2 reference:** `docs/phase-2-completion.md`
**Phase 1 reference:** `docs/phase-1-schema-migration.md`, `docs/pre-multitenancy-state.md` (§ 2/§ 4 superseded by `docs/production-baseline-2026-05-28.md`)

**Phase 5 sub-deploy index:** 5.0 housekeeping → 5.1 hosting migration → 5.2 slug→id routing RPC → 5.3 per-tenant branding → 5.4 tenant signup (incl. `register-customer` un-pin) → 5.5 second-tenant onboarding + soak. All Complete. Sequencing rationale and completion criteria in the parent plan.
**Open findings:** F72 — `register-customer` email template stays founding-branded (deferred; multi-tenant email branding out of Phase 5 scope; re-confirmed deferred at Phase 5 close — now a prerequisite for tenant-2's real-customer go-live, per `docs/tenant-onboarding-runbook.md`). F89 — paper→app conversion is unmeasurable: `claim-paper-customer` deletes the paper rows on success and no usage_event records claims or invites (filed 2026-07-19; deferred to a future instrumentation session; see § 13 F89). F90 — `usage_events` 90-day purge forecloses adoption-trend analytics; needs a per-tenant monthly rollup snapshot written at import (filed 2026-07-19; deferred to a future schema + import-script session; see § 13 F90). F91 — **RESOLVED 2026-08-02.** GoTrue Admin API intermittently rejected new-generation `sb_secret_` keys with a JWT-parse error, breaking the local Playwright suite's auth fixtures (filed 2026-07-22 during the apex-marketing S5.3 gate; test-infra only, no live app impact). Fixed in the test-infrastructure maintenance session: `fixtures/auth.ts`'s three GoTrue Admin calls now go through a bounded-retry helper on their own header constant, retrying only on `403 bad_jwt`; verified across 6 consecutive full-suite runs with zero occurrences. See § 13 F91. F92 — `technical-reference.md` carries pre-Phase-5 claims outside the tenant-resolution contract (stale "no second tenant"/"GH Pages warm"/import-script-hardcodes claims; filed 2026-07-22 at apex-marketing S5.7; deferred to a dedicated re-audit session; see § 13 F92). F93 — **RESOLVED 2026-08-10.** Stray Supabase CLI workdir `C:\Users\richa\supabase` was linked to the **production** project ref and holds stale Edge Function code — a silent-deploy-to-prod hazard if a bare `supabase functions deploy` was ever run without an explicit `--workdir`/`--project-ref` (filed 2026-07-23 during native-customer-signup S2; caused one accidental stale redeploy to staging that session, fixed same-session). Unlinked by deleting **two** pinning files, not one: `.temp/project-ref` and `.temp/pooler-url` (the latter a production Postgres connection string that would also have steered `supabase db` commands); verified no production ref remains anywhere in the workdir. **Two corrections to the original filing, from measurement:** the code is **not** Feb-2026 (mtimes span 2026-05-10 → 2026-07-23; February was the date of the `.temp` *link* files, not the code) and **not** pre-multitenancy (it is tenant-aware but hard-pinned to founding — the pre-F34-residual version, so a misfire would have broken **tenant-2 signup** and reverted F47/F50/F51/F54 hardening, not leaked cross-tenant data). Staleness confirmed regardless: `register-customer` is 248 lines vs the repo's 393 and still carries the retired `MAILERLITE_WEBHOOK_SECRET`; **7 of 8 functions differ from the repo**. **Residual, Rick's call:** the stale tree still exists and is inert while unlinked, but a future `supabase link` there would restore the hazard — deleting the directory is the durable fix. Keep the `--workdir` discipline either way. See § 13 F93. F94 — Cloudflare Turnstile intermittently stuck "Verifying..." → "Verification failed" for the first several real-human attempts on `rjbookstop.pulllist.app` right after the widget went live, resolving on retry (filed 2026-07-24 during native-customer-signup S4 write-smoke; no code defect found, abuse gate worked correctly throughout; root cause unconfirmed between edge-propagation timing and browser fingerprinting; informational, monitor during the soak; see § 13 F94). F95 — **RESOLVED 2026-08-02.** The local Playwright suite's `deleteUser()` never checked `res.ok`, and specs called it before `cleanupTestRows()`, so the `preorders` FK (`ON DELETE NO ACTION`, F10) rejected the profile delete with a silent 409 — 292 orphaned test profiles had accumulated in the staging founding tenant by the time of the fix (up from 87 at filing on 2026-07-25). Fixed in the test-infrastructure maintenance session: `deleteUser()` now clears the user's `preorders` first (order-independent by construction — the dominant orphaning path was the per-test fixture teardown, which no amount of afterAll reordering alone could reach) and throws on any failure; the one-time cleanup removed all 292 rows, recount confirmed 0 and held across 6 further full-suite runs. See § 13 F95. F96 — **RESOLVED 2026-07-27.** `send-brevo-campaign.js` (separate repo `mrcyberrick/weekly-pull-feed`) reported `Campaign sent successfully` ~0.5s after `sendNow` returned 2xx and never read campaign status, so three consecutive Tuesday sends (2026-07-07/14/21) passed green in GitHub Actions while every campaign was Suspended in Brevo with 0 recipients — 18 days of zero delivery, found by eye not by alarm. Fix deployed 2026-07-26 (`34074c3e`: pre-send zero-recipient abort + bounded post-send status polling). Closed 2026-07-27 on **observed** evidence, not stubs: gate V4 (run `30275663163`) turned the Action red at the pre-send guard with `sendNow` never reached and **GitHub emailed the failure**; gate V5 (run `30271641770`) confirmed a healthy send still passes (`queued`→`in_process`→`sent`, campaign 21 delivered, 30/30 images 200). Residual recorded in § 13: the post-send assertion has never been observed rejecting a genuinely suspended campaign — unreachable from a zero-recipient state — so it rests on the live healthy-path run plus 9/9 stubbed scenarios. Marketing-funnel list only, no PULLLIST customer data; see § 13 F96. F99 — transactional mail (MailerSend, `noreply@mrcyberrick.us`, GoDaddy DNS) and marketing mail (Brevo, `previews@rjbookstop.pulllist.app`, Cloudflare DNS) are split across two sender domains on two DNS providers; consolidating the sending identity onto `pulllist.app` is the branding-consistency direction, and the tenant-slug shape Brevo already uses is exactly what F72 needs — so **the two must be designed together, not sequenced independently**, or sender domains get provisioned twice (filed 2026-07-25 at the close of the F97 fix; direction only, no plan doc, not started; its one blocker — `pulllist.app`'s DMARC `rua=` pointing cross-domain with no RFC 7489 §7.1 authorization record, so its aggregate reports had never been delivered — was **fixed same-session 2026-07-25** with a `v=DMARC1` TXT at `pulllist.app._report._dmarc` in the **GoDaddy** zone (not Cloudflare — the name's parent zone is `mrcyberrick.us`), verified at three resolvers; both domains now observable, and two one-time reminder gates are armed for the report read (2026-07-30 plumbing check, 2026-08-20 full read + `p=quarantine` decision); deferred; see § 13 F99). F100 — `weekly-pull-feed` publishes to GitHub Pages from **two** independent deployers with no ordering guarantee between them (GitHub's built-in builder, `build_type: legacy`, which fires on every push to `main` ignoring path filters; plus the repo's own `deploy-pages.yml` running `deploy-pages@v4`), and **this — not the cancelled Actions runs F98 blamed — is what broke F98**: the `/deployments` list shows the tip deployed at 14:26:11 and 14:26:34, then a **mid-burst** commit (`aa794c02`) deployed *last* at 14:27:50, leaving the live site serving a tree captured partway through the thumbnail sequence (filed 2026-07-26 at the opening of the weekly-pipeline hardening session while verifying F98's mechanism before rewriting the publish path; nothing left broken — F98's single-commit fix makes both deployers publish the identical tree, so their ordering stops mattering; a `branches: [main]` filter was added to `deploy-pages.yml` same-session as a V2 prerequisite, commit `604cfaec`; choosing which deployer to keep is deferred — Rick's call 2026-07-26 was not to change a live publishing surface inside the hardening session; see § 13 F100). F101 — the Lunar/PRH order exports carry **no FOC window**: `allPreorders` is scoped to `currentCatalogMonth` and `makeOrderSheetRows` filters only on `!fulfilled`, but a catalog month legitimately mixes several FOC cycles (PRH/Marvel advance-solicit with ~3-month leads, flagged `TBD ARTIST`), so titles one or more cycles out are submitted to the distributor and rejected — MIDNIGHT X-MEN #2 Cover A/B (`75960621668000211`/`…0221`, `catalog_month 2026-07`, FOC **2026-10-12** on a cycle whose FOC is 8/31) came back **UNKNOWN** from PRH with 8 copies queued, and PRH has since withdrawn the #2 records upstream entirely (the 2026-07-25 re-pull carries ten MIDNIGHT X-MEN rows, all issue #1) (filed 2026-07-27 during a title-reconcile question; production; caught by eye at order entry, not by any alarm; no code changed; ****RESOLVED 2026-08-03 — live on staging AND production** (PR #100, merge `5951a30`) — `docs/order-export-foc-window-and-order-state.md`, executed together with F102**; see § 13 F101, incl. a 2026-08-02 domain correction: a catalog month carries **13** FOC cycles, there is no derivable month→band rule, and `app_settings.order_deadline` is the **customer** cutoff and cannot anchor the export; ad-hoc orders also exist and must be excluded from the monthly order; and **"Backordered"** is the store's term for a reservation whose FOC passed with no order placed — worse than it looks, because the FOC lock is a hard cutoff that blocks cancellations too, so the customer is committed to a title that cannot arrive, hence an admin backorder-risk panel is in scope). F102 — `fulfilled` is an **arrival** flag, not an order flag, and is keyed per `catalog_id`, so a long-lead title re-listed in a later catalog month is re-exported to the distributor on every cycle until it physically arrives, with nothing anywhere recording that a code was ever ordered — MIDNIGHT X-MEN #1 (`75960621668000111`) was pushed back nine weeks by PRH and re-listed across `2026-05`/`-06`/`-07`, and `Orders Archived/prh-order-2026-06-27.txt` shows **5 copies submitted** on the June cycle and the July cycle submitted **7 more** against the identical code — **PRH did not roll or cancel the June order; Rick confirmed 2026-07-27 the supplier holds an order for 12 copies against 7 reservations, i.e. 5 surplus** (filed 2026-07-27 alongside F101; production; **realized cost exposure, not hypothetical**; a same-day sweep of all 268 June-submitted codes against all 437 July-reserved codes found **exactly one** overlap, so the mechanism is general but the trigger — a distributor re-dating a title *after* its FOC and re-listing it — is rare, and the initially-filed "systematic" severity was corrected down to Medium; **interim safeguard, no code needed: intersect each cycle's order file against the previous cycle's archived one before submitting**; ****RESOLVED 2026-08-03 — live on staging AND production** (PR #100, merge `5951a30`) — `docs/order-export-foc-window-and-order-state.md`, executed with F101; **the 12-against-7 surplus is now visible in prod's ledger as an over-order, but adjusting that PRH order down before FOC 8/31 remains operational** (reminder set 2026-08-24)**; see § 13 F102, incl. a 2026-08-02 correction: `fulfilled` is *already used* to mean "ordered" via the By Distributor "Mark Fulfilled" button, so the record exists but is mislabelled and keyed on `catalog_id`, which does not survive a re-listing — the order ledger must be keyed on the **distributor code**, and the duplicate check must **surface, not auto-suppress** (auto-suppression would have ordered 0 where 2 was correct). F102's own "per-reservation `ordered_at`" hedge names the option that does not work). F108 — no order-invoice reconciliation: rejections are invisible because reconciliation runs off **shipping reports**, where a rejected title and an unshipped one produce identical evidence (nothing) — PRH returned UNKNOWN on the two MIDNIGHT X-MEN #2 codes and has since withdrawn them upstream, and 8 reservations still point at a title that can never arrive; filed 2026-08-02 from the F101/F102 planning interview, scoped OUT of that session by Rick, needs sample PRH/Lunar order-confirmation files before it can be specified; deferred; see § 13 F108. **The weekly-pipeline hardening session ran 2026-07-26 — plan: `docs/weekly-pipeline-hardening.md`. All three items are live: S1 newsletter CTA → `rjbookstop.pulllist.app` (verified 0 apex / 3 founding hrefs on the served page), S2 single-commit publish (F98 **resolved** — live publish `24c3035b` produced exactly 1 commit, 1 Pages build, 1 deployment; 30/30 images 200 with no manual rebuild), S3 send-status assertion (deployed, F96 open pending observation). Also landed: `604cfaec` Pages-deploy branch guard, `808cae4` feed-week default fix (a bare `--publish` targeted the week containing *today* instead of the upcoming shipment — it would have replaced next week's newsletter with already-shipped titles and purged all 29 live thumbs; found at gate V2), and CODE.GS formally retired. Still owed before the plan closes: V4/V5 send tests, `BREVO_LIST_ID` restore re-check, and the real-browser signup-affordance check.** **The `import.js` maintenance session (F75 key rotation + F78 historical dedup + F85 cross-month root fix) closed 2026-07-15 — plan: `docs/import-js-maintenance-f75-f78-f85.md`.** **The F86 prod legacy API key retirement session (config.js publishable-key migration + legacy-toggle flip; incl. F88, surfaced and resolved mid-session) closed 2026-07-22 — plan: `docs/f86-anon-key-migration.md`.** F103 — **RESOLVED 2026-08-02.** The local Playwright suite's `seedCatalogRow()` defaulted `catalog_month` to the **calendar** month (`thisCatalogMonth()`), but the catalog page scopes its grid to `Catalog.getLatestMonth()` — the newest month present *in data* — so every founding-tenant seed landed in a month the page never rendered (filed 2026-07-27; test-infra only, staging only, no live app impact). Fixed in the test-infrastructure maintenance session: `seedCatalogRow()` now defaults to a data-derived latest-`catalog_month` read (mirroring `Catalog.getLatestMonth()`, cached per tenant per run), falling back to `thisCatalogMonth()` only when the tenant has no rows; specs 02/03/07 verified green (founding and synthetic-tenant assertions both) across 6 full-suite runs. Also added first coverage for the catalog info-card reserve path (`tests/14-catalog-info-card-reserve.spec.ts`), previously at zero. See § 13 F103. F104 — **RESOLVED 2026-08-10.** The `guard-git` secret scanner's five blind spots are closed and verified **14/14** against a synthetic matrix (fabricated keys only). `config.js` is no longer excluded wholesale — it is scanned under a narrower rule permitting an `anon` JWT / `sb_publishable_` while blocking `sb_secret_` and any JWT decoding to `"role":"service_role"`; `add` and `push` are now scanned (push over `--branches --not --remotes`, i.e. what would actually leave the machine); key shapes are widened with a **digit requirement** in the value, which is load-bearing — without it the pattern matches this repo's own `process.env.SUPABASE_SERVICE_KEY` references and `your_service_role_key_here` placeholders; and it now **fails closed** on unparseable input, but only after sniffing the raw text for a git-write shape, so an unrelated Bash call still passes (blocking every `ls` would get the hook disabled, which is worse than the gap). **Added-lines-only is deliberately RETAINED** as an accepted trade-off — scanning context lines is what false-positived on security docs in July; do not "fix" it. Also fixed, previously unfiled: Guard 2 ran `git diff --cached` with no `-C`/`cd` awareness, so a commit via `-C <dir>` was scanned in the **wrong repo**, found nothing, and allowed. **The standing sync trap was live** — the only versioned copy (scripts repo `claude-config/hooks/guard-git.ps1`) was **stale at 6,432 bytes against the live 18,845**, so a restore would have reverted every fix; re-synced hash-identical and committed (`54d79fa`). Nothing enforces that sync; it is by hand after every hook edit. The hook itself stays local-only and untracked in this public repo. See § 13 F104. **F128** — impersonated unsubscribe silently no-ops and reports success: `subscriptions` has **no admin write policy** (only `users manage own subscriptions` + an admin **SELECT**), while `subscriptions.html` wires `.unsub-btn` with **no impersonation guard**, so the DELETE carries the admin's JWT against the customer's `user_id`, RLS filters it to zero rows, and PostgREST returns success with `error === null` — the UI toasts *"Unsubscribed from X"* and the row survives a refresh (filed 2026-08-10 while reading the page to verify F127's unverified claim; **Low** — admin-only, no data loss; the *subscribe* buttons on the same page **are** correctly disabled during impersonation, so this is an oversight in an otherwise-considered design, not an unconsidered surface; same silent-no-op shape as **F58**; **read from code, NOT probed** — confirm empirically before fixing, especially as § 7 was independently found stale for `preorders` the same day; the client half is cheap but the real question is a **product decision** — should an admin be able to unsubscribe on a customer's behalf at all? if yes the table needs an admin write policy and the button should be *enabled*; do not add that policy without deciding, it widens admin write authority on a table that currently has none; see § 13 F128). F105 — a blocking pre-flight gate went unmet and Phase 5.5 closed anyway with its completion criteria recorded as ticked: `docs/sql/f6-app-settings-pk-rekey.sql` required the prod `app_settings` PK re-key **before tenant 2**, staging ran 2026-07-08, `comicstore` went live on prod 2026-07-15, and the prod run did not happen until 2026-07-28 — a 13-day exposure found by a findings-index audit, not by any alarm (filed 2026-07-28 while closing F6; **no damage** — prod held `rjbookstop` with both keys and `comicstore` with none, so the collision never fired; the gate was invisible because it lived in a SQL file rather than in the plan's Completion Criteria, was stated as prose rather than a checkbox, and CLAUDE.md had already stopped listing F6 as open; process finding, no code or schema fix; deferred; see § 13 F105). **Open structural findings (Phase-1 audits, knowingly accepted, no owner — listed so this file stops implying they are resolved):** **F10** — `preorders` FKs are `ON DELETE NO ACTION` (this is what causes F95's orphaned test profiles). **F13** — `reservation_history.user_id` cascades on auth-user delete, intent never resolved. **F25** — `user_profiles.email` denormalized from `auth.users.email` with no sync trigger. **F27** — both `pgcrypto` and `uuid-ossp` installed. **F30** — `Preorders.getAll`'s `auth_users` embed is unenforced by FK. These five are documented and dormant, not a backlog anyone is working — but they are **open**, and the previous wording ("all other findings through F102 are resolved") asserted otherwise. (**F9** was a sixth until 2026-07-28, when its `weekly_shipment` unique key was rebuilt as `(tenant_id, distributor, upc, on_sale_date)` on both environments and both import scripts were updated — filed→resolved in one session; see § 13 F9.) That blanket claim is what let F6's production gate sit unmet for 13 days: a session-opening read of this file signalled F6 needed no attention while § 13 still said "Prod run pending" (corrected 2026-07-28; the mechanism is filed as F105). All other findings through F102 are resolved — full entries and statuses live in `docs/technical-reference.md` § 13 (canonical findings index; the F76 distributor-agnostic display match remains as defense-in-depth post-F84; **F97 resolved 2026-07-25** — `_dmarc.mrcyberrick.us` published at GoDaddy and verified live at three resolvers, with a 2–4 week aggregate-report read owed before considering `p=quarantine`). F106 — **RESOLVED 2026-07-29 (same session).** F96's own status assertion failed a campaign Brevo delivered at **100%**: `STATUS_HEALTHY` carried camelCase `inProcess` while the API returns snake_case `in_process`, so a send still legitimately in flight at poll-window close matched neither the broken nor the healthy list and hit the catch-all "unrecognized status" fail (run `30406602527`, campaign 24, 9 recipients, Action red after 42s). No delivery impact — the damage was to the alarm, which would have cried wolf **every Tuesday** until the operator stopped believing it. The bad literal came from this repo's own S3 spec in `docs/weekly-pipeline-hardening.md` (corrected same session): a wrong value in a planning artifact propagates into code and survives review, because review compares code *to the doc*. Gate V5 missed it because a **one-contact** list reached `sent` inside the window — the second time in this workstream a single-contact list gave misleading green. Fixed in `95d5eec8` (both spellings accepted; `ATTEMPTS` 6→10), unit-tested 8/8 against the deployed constants; live multi-recipient proof OBTAINED on the Tue 2026-08-04 run (`30958741925`) and **F106 is now fully closed**: list 7 carried **10 subscribers**, not the one-contact list that gave misleading green twice before, and the poll read `queued`×5 → **`in_process`** → `sent` — the snake_case spelling F106 fixed, accepted by the deployed code against a real Brevo response, which is the exact thing that had never been observed. See § 13 F106. **The test-infrastructure maintenance session (F91 + F95 + F103) ran 2026-08-02 — plan: `docs/test-infra-maintenance-f91-f95-f103.md`. All three resolved and verified (V1–V5 green); one-time staging cleanup removed 292 orphaned test profiles; optional info-card reserve coverage added (S4). Note: the suite itself lives outside any repo (untracked, machine-local per § What's tracked vs local-only) — only this plan and the findings closeout are committed.** F107 — Playwright suite hit a Supabase GoTrue `429 over_request_rate_limit` on the 3rd run of two separate back-to-back-triple gate-verification sequences during the same session; likely an artifact of running the full suite six times in ~45 minutes rather than a defect in normal (single-run) usage; not reproduced under normal conditions; informational, no plan doc; see § 13 F107. **The order-export correctness session (F101 FOC window + F102 order state) ran 2026-08-02→03 — plan: `docs/order-export-foc-window-and-order-state.md`. CLOSED AND LIVE IN PRODUCTION** (PR #100, merge `5951a30`). *(Corrected 2026-08-03: this block previously read "CLOSED ON STAGING; NOT PROMOTED" and listed a promotion as owed, contradicting the F101/F102 entries and § Known Out-of-Scope Items in this same file. The promotion happened the same day the stale text was written. This is the F105 mechanism — a session-opening read of this file signalled that work was outstanding when it was already done.)* Shipped: an Order Builder modal replacing both direct exports (explicit multi-select FOC cycles, held-back panel with Backordered visually distinct, duplicate surfacing that never auto-suppresses, ad-hoc exclusion); a code-keyed `order_submissions` ledger with admin-only RLS, seeded with 857 real rows from the May/June/July archived order files; a backorder-risk dashboard panel (At risk vs Backordered, cleared by ledger); and a per-title order-state button on By Distributor (`Mark Ordered` → `◐ Add (n of m)` → `⚠ Over (n of m)` → `✓ Ordered (n)`, disabled on exact match). Gates V1–V8 green; full suite green on every deploy; real-browser check confirmed by Rick. **Three scope changes Rick made mid-session, all live:** (a) My List's "Order placed" status + cancel lock is now driven by the ledger **independent of `fulfilled`**, via a new `get_ordered_codes()` SECURITY DEFINER RPC (`order_submissions` is admin-only, so customers cannot read it directly); (b) **"Mark Fulfilled" was removed entirely** — manual fulfillment tracking is meaningless without POS integration, so `fulfilled` is now set *only* by the automatic `auto_fulfill_past_on_sale()` job (column, RLS and `Preorders.setFulfilledByCatalogId()` all untouched for a future POS path); (c) Mark Ordered defaults to `adhoc`. **Production promotion COMPLETED 2026-08-03**, in this order: `docs/sql/order-submissions.sql`, `docs/sql/get-ordered-codes-rpc.sql`, the **production** backfill `docs/sql/order-submissions-backfill-PROD.sql` (857/857 codes matched, zero NULL titles — **never run the staging backfill file on prod**, it hardcodes the staging tenant UUID in all 857 rows and will FK-violate), then the client via PR #100. Full deploy log: that plan's § 8. **The realized cost is still on production and is not fixed by shipping code:** PRH holds 12 copies of `75960621668000111` against 7 reservations, FOC **2026-08-31** — adjusting that order down before 8/31 is operational and worth doing regardless.** F109 — the order-ledger cancel guard in `Preorders.cancel()`, like the pre-existing `fulfilled` guard it mirrors, is **client-side only**: `preorders` RLS permits a user to DELETE their own row, so a hand-crafted PostgREST call bypassing `Preorders.cancel()` can still cancel a reservation the store has already ordered (filed 2026-08-03 at the close of the F101/F102 session; found by the guard's own end-to-end test, which issued a direct DELETE with a real customer token and got HTTP 204; **Low** — not reachable through the UI and not a new hole, but the same guard shape now covers money rather than tidiness; fix direction is a `BEFORE DELETE` trigger, **not** a narrower RLS policy, since the condition needs a join; see § 13 F109). F110 — distributor withdrawals cannot be detected from the catalog files as downloaded: the PRH file the store pulls is the **active-only** export (`*_full_active.csv` — measured 871/871 and 1280/1280 rows `IP / Active`), so a withdrawn title is **absent rather than flagged**, and Lunar has no status column at all (`O/A` uniformly `N` across 1,511 rows). Detection is a **set difference**, not a column read — a code present in a prior import, gone from the current one, still holding unfulfilled reservations. **Corrects a wrong fix direction proposed the same day** (capture PRH `SalesStatus`), which would return `Active` forever. This is the mechanism behind F101's open customer-facing thread and the cheaper half of F108 (filed 2026-08-03 from PRH/Lunar vendor docs read at Rick's request; **Session A (detection) RESOLVED 2026-08-03, live on staging and production** — `docs/order-export-followthrough-f110-f111-f112.md` § 6 Session A; **Session B (surfacing) RESOLVED 2026-08-03 — live on staging, 63/63 Playwright tests green incl. two mobile-width (375px) checks; **since promoted to production** by a later staging→main merge — verified live 2026-08-09 (`#withdrawn-panel`, `allPreordersAllMonths`, `gatherCollapsed`, and the My List withdrawn surfacing, all served on `pulllist.app`); this previously read "production promotion is Rick's call, not yet requested" and was stale — **the F105 mechanism again**.** Mid-session, the withdrawn-cancel exception was found to reach only My List's current-month table, not the read-only "Upcoming Arrivals" grid where the real prior-month case actually lives (Rick: fix it same session) — both now carry the withdrawn flag + a working Remove. Fixing that surfaced a second, genuinely pre-existing bug (Upcoming Arrivals never cleared stale DOM on a shrink-to-empty render) — filed and fixed same-session as **F114**; see § 13 F110). **Two things settled at planning:** the PRH Monthly/Delta file was **decided against** (it gives PRH a structured signal but nothing for Lunar, so the set difference is needed regardless), and **F110's filed fix direction #1 was found wrong and corrected** — it proposed reusing `delete_dropped_catalog_items()`'s array, but that function compares *within* a single `catalog_month` and, per F66, **matches zero rows on every run**; the set difference must be computed explicitly across months, with the prior-month catalog read paged (F82/F113). Rick also settled the customer-facing half: **"Admin + customer flag"** — withdrawn titles are flagged on My List and **cancellation is re-enabled** despite the FOC lock (a deliberate call-site exception; `isFocPast`/`isFocLocked` stay untouched), and it must override the **ordered** lock too, since the MIDNIGHT X-MEN #2 codes carry ledger rows. F111 — the Order Builder gathers reservations within `currentCatalogMonth`, but a distributor FOC cycle legitimately spans several catalog months (PRH: "FOC 03/23/2026 · 204 items · **4 catalogs**", and PRH updates four months nightly). **Measured on production: of 483 future-FOC titles outside the current month, 481 were already in the ledger — only 2 titles / 2 copies genuinely fell through**, because the store's ordering cadence matches the catalog cadence. Not a regression (the pre-fix export scoped identically) but the held-back panel now projects a "nothing dropped silently" confidence that holds only within the month it can see (filed 2026-08-03; enhancement; **RESOLVED 2026-08-03 — same plan, Session B; live on staging; **since promoted to production** by a later staging→main merge — verified live 2026-08-09 (`#withdrawn-panel`, `allPreordersAllMonths`, `gatherCollapsed`, and the My List withdrawn surfacing, all served on `pulllist.app`); this previously read "production promotion is Rick's call, not yet requested" and was stale — **the F105 mechanism again****; see § 13 F111). **The live worked example resolved during planning:** `ACTION COMICS #1 FACSIMILE CVR A` (`0626DC0190`, Lunar, catalog `2026-05`, reserved 2026-06-02, **never ordered**) hit FOC **2026-08-03** and crossed into Backordered without ever appearing on any surface — production's current month is `2026-08`. Its sibling CVR C *was* ordered on the June cycle, which is the 481-of-483 case in miniature. Settled at planning: de-dup collapses **export consolidation by `exportCode`** and **reservations by `(user_id, order_code)`** on newest month (F85's survivor rule), **both surfaced, never silent**; the backorder panel **adopts the same widening** (Rick); and **`allPreorders` must NOT be widened** — it has 15+ correctly month-scoped consumers, so the fix adds a second array and re-points only four. F112 — two distributor-model facts the app does not represent: Lunar publishes **`InitialOrderDue`** in its product file (1,505/1,511 rows = `8/27/2026`), which **qualifies § 2.2's "no derivable submission deadline" conclusion for Lunar** though not for PRH, and it is unread by the import along with `TitleNote` (carrying "Allocations may occur" ×31 and "Previously offered through Diamond. Never fulfilled." ×16); and **a passed FOC is recoverable on Lunar but terminal on PRH**, which the § 4.5 backorder panel does not distinguish. Also records the terminology collision — Lunar's "backordered" means *ordered after FOC, may not fill*, ours means *FOC passed, never ordered* — and the vendor's own confirmation of F102: *"All orders placed on the Lunar site … will ADD to any previously existing order quantity"* (filed 2026-08-03; see § 13 F112). **Half planned, half withdrawn (2026-08-03):** (a) `InitialOrderDue` + `TitleNote` reads are **RESOLVED 2026-08-03, live on staging and production** — two additive nullable columns, read by both import scripts' Lunar normalizer, with a window parse guard rejecting the 2027/2028 typos (verified: exactly 2 rejected against the real 08/26 file) and **never aggregating** to a per-file deadline; (b) **the Lunar-vs-PRH severity split is OVERRULED and withdrawn** — Rick, who places the orders: *"Backorders are treated the same for PRH and Lunar — they both can be ordered after the FOC date but availability can not be guaranteed. I do not want to distinguish them as such."* Both can hold: the FOC *cart* closes, but a new order can still be placed against remaining stock. **The real distinction the vendor docs obscured is late ≠ withdrawn** — a Backordered title is still orderable; a **withdrawn** one (F110) is not, and cannot arrive. **Consequence: shipped copy is wrong** — the backorder panel, that plan's § 2.4, and § 13 F101 all say a Backordered title "cannot arrive," which is accurate only for withdrawn; the wording fix is scoped into Session B. F113 — **`admin.html:679–693` fetches `preorders` with no `.range()`, so PostgREST caps it at 1,000 and production holds 2,004** — the admin dashboard reads half the table (filed 2026-08-03 while checking whether F111 was implementable; **no wrong output today** — every consumer is month-scoped and all 101 current-month rows sit inside the newest-1,000 window, which reaches back to 2026-06-26 — but it is a **silent cliff** as monthly volume grows (250→340→476→**764**→…) and it **hard-blocks F111**, because the widening needs exactly the 1,004 discarded prior-month rows and F111's own worked example was reserved 2026-06-02, outside the cap; same class as F82; **RESOLVED 2026-08-03, Session B step 1 as scheduled — live on staging; **since promoted to production** by a later staging→main merge — verified live 2026-08-09 (`#withdrawn-panel`, `allPreordersAllMonths`, `gatherCollapsed`, and the My List withdrawn surfacing, all served on `pulllist.app`); this previously read "production promotion is Rick's call, not yet requested" and was stale — **the F105 mechanism again****; see § 13 F113). F115 — **`auto_fulfill_past_on_sale()` has no arrival check**, and the backorder panel's exit condition is `!fulfilled`, so a title that was never ordered and never came leaves the panel on schedule, indistinguishable from one that arrived — and My List then tells the customer **"✓ Order placed"** (filed 2026-08-04 from a live triage question; **measured on production: 28 reservations / 23 titles marked fulfilled with no shipment record and no ledger row, 4.2% of past-on-sale reservations** — an upper bound, since a missing shipment row is not proof of non-arrival; **MITIGATED 2026-08-04**, not resolved: a Step 9 pre-flight report now prints these at the point of destruction in both import scripts — reports, never blocks — and the client gained a distinct "Never arrived" state, but nothing yet persists the outcome or tells the customer, which stays **F108**'s job; also corrects an assumption made and disproved the same day: auto-fulfill is **not** a cron job, it runs only at Step 9 of `import.js`, so the flag flips at the next import and a sold title can sit on the panel accruing "days overdue" for a full weekly cycle; see § 13 F115). F116 — the order panel could not distinguish **"ordered but never recorded"** from **"never ordered"**, so its loudest row was routinely a false alarm: `Sonic the Hedgehog #88` read "Backordered, 36 days overdue" on production the day before it went on sale, having shipped — it was ordered on the **April** cycle, which predates the ledger's May start, so no `order_submissions` row exists or ever will (the caveat F111 already recorded, surfacing as a permanent false alarm) (filed and **RESOLVED 2026-08-04, same session** — the panel now also clears on **shipment evidence** via the F76 three-key match, labels and sorts by **on-sale proximity** rather than days-past-FOC, and `loadOrderLedger()` was **paginated** before production's 857 rows cross PostgREST's 1,000 cap and start silently un-clearing ordered codes; **customer impact was nil** — all five backordered titles were prior-month and so never entered My List's current-month table, and zero reservations across production were showing the "FOC passed — contact the store" lock; live on staging, production promotion is Rick's call; see § 13 F116). F117 — **`order_submissions` cannot record a downward adjustment**, so a corrected supplier order leaves the ledger knowingly wrong: the table conflates a *submission event* with the *current quantity on order*, and `CHECK quantity >= 1` rejects any correcting row (**verified against production 2026-08-05: a `-4` insert returns HTTP 400 / `23514`; the probe was rejected so nothing was written, 857 rows unchanged**). Live instance: `75960621668000111` (MIDNIGHT X-MEN #1) — ledger holds 5 + 7 = **12**, true demand is **8** (6 customers after collapsing F85 cross-month duplicates), and **Rick corrected the PRH order to 8 on 2026-08-05**, closing F102's surplus operationally with no way to say so. **Invisible today** (the title's catalog months are `2026-05`/`-06`/`-07`, current is `2026-08`, and By Distributor is month-scoped) but surfaces as a false `⚠ Over (12 of 8)` the moment PRH re-lists it — likely before Session B, since FOC is 2026-08-31. **Rick chose to wait for Session B and append a `-4` adjustment row rather than edit the 7/26 row down to 3** — so the 12 is *deliberate* and must not be "fixed" by rewriting history; that row's 7 is what evidenced F102 in the first place. **Folded into Session B of `docs/order-loop-closure-f108.md`, widening a change already planned there:** the CHECK must permit **negatives**, not just the `>= 0` that rejections needed, `order_type` gains `adjustment`, and every consumer must handle **signed** quantities (button maths, `ledgerMatchesFor()` consumers, the `get_ordered_codes()` aggregate). See § 13 F117 — **RESOLVED 2026-08-06, live on staging AND production** (PR #104, merge `2029e70`); the real `-4` landed on both environments, closing the F102 surplus in the ledger itself. F118 — **RESOLVED 2026-08-06, same session, live on staging AND production.** The By Distributor "Print / Save Report" Status column never read the order ledger (it predates `order_submissions` by five weeks), so a title reading "✓ Ordered" on the tab still printed as "Open"; found by Rick reviewing staging, fixed same session — see § 13 F118. F119 — **RESOLVED 2026-08-06, same session, live on staging AND production.** "Print Bagging List" also printed the Order Follow-Up and Withdrawn panels (both sit outside the print CSS's tab-scoped hide rule — persistent, tab-independent, added to `admin.html` after the print rule was written); found by Rick reviewing staging minutes after F118, fixed same session with a two-selector CSS addition — see § 13 F119. F120 — **RESOLVED 2026-08-06, same session, live on staging AND production.** A rejected title was invisible on both the Bagging List (showed as an ordinary item to pick up, counted in totals) and My List (no badge on any of the three rendering paths); found by Rick reviewing the F119 fix, fixed same session — badge-only on the customer side, no FOC/ordered-lock override (Rick's explicit scope call), reusing F110's withdrawn-row/withdrawn-notice surface — see § 13 F120. All four (F117-F120) promoted together via PR #104; post-deploy write-smoke passed. F121 — **RESOLVED 2026-08-09 (status corrected 2026-08-10 — § 13's entry had gone stale claiming sessions 2–6 were not started while all six were in production; the F105 mechanism, second instance in eight days). Process-mapping session DONE 2026-08-07; restructure COMPLETE and live in production — plan `docs/admin-dashboard-process-map.md`.** Verified independently 2026-08-10: `admin.html` is byte-identical on `origin/main` and `origin/staging`, the three-mode markup is present on `main`, and the retired All Reservations tab survives only as comments. Rick's three workflows are captured at § 5.1–5.3 (his own walkthrough — **authoritative over the code where they disagree**). **Structure DECIDED: Option B, separate surfaces by cadence, built as three modes within ONE `admin.html`** (§ 5.7) — a guided-run option was rejected on its merits (the monthly step order is genuinely flexible), so do not revisit it without new information. **Bounded by § 5.6:** this is one tenant's process — phases may be fixed, task lists must be data-driven off `user_profiles.is_paper`, and **no "step N of 8" may be hardcoded** (Phase 6 opens signup to stores nobody has met). **Six sessions indexed at § 5.7.4. Sessions 1 and 2 COMPLETE on staging 2026-08-08, neither promoted to production.** Session 1 (`1ec32a7`) deleted the stats bar + Export All (V1–V7 green, 86/86). Session 2 (`649a4b6`) rehomed the search onto By Customer — it filters, auto-expands the matching groups, and keeps each customer's **full** totals with a `showing N of M` note rather than misleading filtered subtotals — and retired the All Reservations tab (V1–V7 green, 91/91, new spec 16; `renderMiniTable()` deliberately kept, it is shared). Session 3 (`6845326`) **deleted the Top Series tab rather than moving it to `analytics.html` as originally planned** — a decision corrected at implementation with Rick's approval and recorded at § 5.7.5: analytics' Operations cards are all **event**-based over rolling 30/90-day windows, Top Series is **state**-based for one catalog month, so moving it would have recreated F121's own defect on the analytics page. `get_popular_series` is **kept** in the database (`app.js`'s `Recommendations._getPopularSeries` still uses it for the customer catalog page); only the admin surface is gone. **Sessions 1–4 are LIVE IN PRODUCTION (PR #109 `9552ee6`, then PR #110 `de0d7ca`, both 2026-08-08). The admin dashboard is no longer a tab strip at all — it is THREE MODES on three cadences: Customers (ongoing, the landing mode) · Bagging (weekly) · Ordering (monthly), each owning its tabs and its page chrome.** The Order Follow-Up and Withdrawn panels live on **Customers** (Rick: an ad-hoc order is by definition outside the monthly cycle), with one attention dot there — red when a customer is already affected, amber for work still preventable. Session 4's Bagging light-load path is **dormant by design**: landing on Customers loads fully, so the 2,000-row skip never fires; kept because a cheap alert-count query would make it live again. **Session 5a is LIVE IN PRODUCTION 2026-08-08** (PR #111, merge `f031916`) — By Distributor groups titles by **publisher** in collapsible sections with a search box, and the **printed report is grouped to match** (Rick's constraint: the print decides the cut). Also fixed a problem older than the session: **`style.css` had no `overflow-x` anywhere**, so no table in the app had a scroll container — By Customer had the same latent issue and is fixed by the same rule. The Publisher *column* was dropped from the distributor table, since publisher is now the group header. Four print-only follow-ups are also **LIVE IN PRODUCTION 2026-08-09** (PR #112, merge `d0b817b`): the trailing space Rick marked on the printed report was a **phantom 9th column** (the report has 8; session 5a's publisher band spanned `colspan="9"`), and the band's grey fill was replaced by **rules and typography** because browsers do not print background fills unless the operator enables them. **General rule for that report: anything that must survive printing belongs in weight, size, rules or spacing — never a background.** **5b — search across catalog months — is LIVE IN PRODUCTION 2026-08-09** (staging `60035df`, 99/99 suite; promoted via PR #113, merge `d12921e`). Its three rules shipped as gates, not intentions: every result row carries its catalog month, the group header never describes one month while rows from three sit beneath it, and on By Distributor the search states that it overrides the cycle selector. Built as: a `.month-tag` shown only when a row's month differs from the surface's own scope; By Customer keeping its current-month totals plus `showing N of M · K from other months`; publisher bands appending `N other months`; and an inline notice that the cycle selector is ignored while searching. **No toggle — always cross-month.** `allPreorders` was NOT widened (F111 § 4.4). **Session 6 — Ordering mode + the Paper Orders split — LIVE IN PRODUCTION 2026-08-09** (staging `a6a7fbc` → PR #114, merge `54d0dc3`; V1–V8 green, **103/103**, `PLAYWRIGHT_EXIT=0`, zero flaky; V2's real paper customer torn down and **verified gone by live SELECT**; real-browser check and **post-deploy write-smoke both PASSED**, Rick 2026-08-09). Plan `docs/admin-restructure-6-ordering-mode.md`. **This closes F121's restructure — all six sessions plus W2/W3 are live.** Shipped: `Ordering ▸ Paper Orders` = create + entry + catalog print, `Customers ▸ Paper Customers` = list + Manage + Claim, both reading one `paperCusts` array behind an idempotent `ensurePaperCusts()`; the paper print pair renamed to **Catalog** *including the printed page's own title and header* (the export-bar pair deliberately unchanged — it submits real money); and the cycle-view lock's explanation moved from inside By Distributor to `#cycle-lock-note` in the export bar, now naming the month. **Two things a later session should not re-derive:** (a) Ordering fetch isolation is **deliberately not done** — every visit lands on Customers, which already loads everything, so an Ordering-specific path would be dormant on arrival exactly as Bagging's is (plan § 4); it becomes real work only once a cheap alert-count query lets the dot be computed without the full gather. (b) **`main` carries two `supabase/migrations/*.sql` files (`phase_4_3`, `phase_4_4`) that have never existed on `staging`** — merges handle it correctly and both were verified present after PR #114, but the branches are **not** a clean superset relationship and no doc recorded that; surfaced to Rick 2026-08-09, not filed as a finding without his call. Ordering's chrome was already allocated by session 4, so session 6 is § 5.7.2 P2's deferred cut (create form + bulk entry + catalog print → Ordering; customer list + Manage/Claim → a new Customers tab) plus the two collisions the split worsens — the § 3.2 four-buttons/two-names clash (Rick: rename the **paper** pair, and the printed sheet with it, not the distributor pair) and § 3.1's cycle-view lock, whose explanation lives inside the By Distributor tab while the buttons it disables sit in page-level chrome. Rick's four scope calls 2026-08-09: Add Paper Customer goes with **Ordering** (a new paper customer appears mid-entry at monthly step 2); rename the paper pair only; fix § 3.1 here rather than file it; and **§ 5.6's `is_paper` hiding is NOT this session** (hiding on a zero count would also hide the Add form from a store wanting to start using paper). Ordering fetch isolation is deliberately **not** done — every visit lands on Customers, which already loads everything, so an Ordering-specific path would be dormant on arrival exactly as Bagging's is (plan § 4). Real-browser check confirmed by Rick before promotion; post-deploy read-only verification passed (new build served; the shared `.stats-bar` CSS survived and `mylist.html`/`arrivals.html` still use it; both order-sheet buttons intact; prod row counts normal). **Post-deploy write-smoke PASSED** (Rick, 2026-08-08) — run by hand, since it needs a real browser session on production and the Playwright runner is deliberately barred from prod. Sessions 4–6 (Bagging → Customers → Ordering modes) not started; they are the actual restructure and the first structural change after three subtractive ones. **W2/W3 (the Order Builder fixes) are LIVE IN PRODUCTION 2026-08-08 (PR #109, merge `9552ee6`)** — `docs/order-builder-record-split.md`, commit `ff13d0f`: confirm-on-export removed and replaced by a two-step modal (Generate & Download, then Record submitted order with per-title ticked=ordered / unticked=rejected), and `order_type` now writes `'monthly'` so `classifyForExport()` stops routing monthly cycles into the auto-excluded bucket and silently dropping F102's remainder quantity control. V1–V7 green, 89/89 suite. Real-browser check confirmed by Rick; **promoted to production 2026-08-08 in PR #109 alongside F121 sessions 1–3.** Production was verified to already hold 859 `order_type = 'monthly'` rows before merge, so the new value was known-accepted. **Post-deploy write-smoke PASSED** (Rick, 2026-08-08). Original finding text follows: The Admin Dashboard has accumulated **four time-scoping models** (current catalog month / all months / a selected month / calendar week) and **three counting units** (copies / titles / reservation rows) on one page, so numbers that were never meant to agree get compared — Rick tried to reconcile the dashboard tile against the Order Builder's export count three times in one day (67v70, 66v67, 35v36), all individually correct. No single decision was wrong: each scope came from a correctly-scoped finding session (F111's cross-month gather, F115/F116's arrival triage, the 2026-08-06 cycle selector); none re-asked what the page's model is. Working hypothesis: the page serves three cadences at once (monthly ordering / weekly bagging / continuous account admin). **Do not patch this with more labels** — that is what produced it. See § 13 F121. F122 — **RESOLVED 2026-08-08 on BOTH environments** (Option 1, Rick's choice — `docs/f122-auto-fulfill-current-schedule.md`): `auto_fulfill_past_on_sale()` now judges against the **newest listing's** on-sale date rather than the reservation's joined catalog row. Verified by execution — production returned **0** where the old body returned **3**; the 3 hand-repaired reservations are now durably unfulfilled. **A THIRD MANIFESTATION was found 2026-08-10 and folded into F122 (Rick's call, no new ID): Option 1 fixed auto-fulfilment, but every *read* surface still resolves through the reservation's pinned row, so `arrivals.html`'s shipment reconciliation dragged MIDNIGHT X-MEN #1 into the Aug 3–9 week on its superseded 2026-08-05 date while `mylist.html` showed it to nobody** — a reservation pinned to a past-dated superseded row is in neither the current-month table nor Upcoming Arrivals. Jay Underhill could see it and Mike Neubauer could not purely because Jay held an F85 cross-month duplicate on the good row. **Swept all 2,005 production preorders: exactly 4 affected rows / 2 titles** (MIDNIGHT X-MEN #1 — 5 copies, 3 customers, hidden; Grendel Sedition #3 CVR B — 2 copies, wrong date but visible). MIDNIGHT X-MEN #1 **repaired on production 2026-08-10** to 6 rows / 8 copies / 6 customers, matching F117's true demand and the PRH order Rick corrected to 8. **Grendel repaired the same day** on Rick's instruction — identical shape, one Book Stop reservation of 2 on the `2026-06` row with no duplicate on the newest, so a pure repoint with no delete; its ledger already held net 2 against 2 reserved. **A full production re-sweep after both repairs returns ZERO stranded reservations.** **Also fixed, in both import scripts:** `reportReservedInStoreDateChanges()` was scoped `catalog_month=eq.<month being imported>`, so it compared July against July and printed *"No in-store-date changes on reserved titles"* while the book moved nine weeks — it now reads every unfulfilled-reserved catalog row across all months (paged, F113) and separates **corrected** (same month, self-healing) from **stranded** (older month, needs hand repointing), ignoring newer-month rows so an `isOlderMonth` backfill cannot invert the advice. Diff extracted to a pure `classifyReservedDateDrift()` and unit-tested (suite **129 → 151**), because the old version was network-bound and could only be checked by running a real import — which is how the blind spot survived. **Note the diagnostic split that matters for triage: only 1 of the 11 "not in shipment" titles was this defect; the other 10 were all ordered on the 2026-06-27 cycle, never shipped, and are F108's problem.** Scripts-repo change is **pushed** — `f9df045` on `origin/main`, alongside `5bc7461` and `4b83ae3` (all three verified as ancestors of `origin/main` 2026-08-10). The `guard-git` block that had queued these was a **hook bug, not policy** — fixed 2026-08-10, see § 13 F104. **Option 3, the catalog-upsert root fix Rick raised (one row per physical comic), remains OPEN by decision** — it would dissolve F122, F102's mechanism, F85's duplicates and the 12-against-8 phantom in one change, but `catalog_month` currently doubles as the By Distributor cycle selector's permanent record; see § 13 F122 Fix direction. **F124 — RESOLVED 2026-08-08, same session:** verifying F122's grant gate found DEFINER execute grants were not least-privilege, because **`REVOKE … FROM PUBLIC` does not remove Supabase's default `anon`/`authenticated` role grants** — corrected on both environments and in-repo; see § 13 F124. Original F122 text: `auto_fulfill_past_on_sale()` reads `on_sale_date` from **whichever catalog row a reservation points at**, so a re-dated title is closed on its **superseded** schedule. Live instance from the 2026-08-07 production import: MIDNIGHT X-MEN #1 (`75960621668000111`), pushed back nine weeks by PRH (May/June rows say on-sale 2026-08-05; the July re-listing says **2026-10-07**), so 5 copies / 3 customers pinned to the old rows were marked fulfilled for a book that has never shipped and is not due until October — and past-on-sale auto-hide would then have **removed it from their My List entirely**. **Distinct from F115** (that is "no arrival check"; this is "wrong date, because the reservation points at a stale row" — F102's mechanism one function over, and F85's carry-forward gap for *manual* reservations is the direct cause). Swept: exactly 3 reservations affected across all of production, all this title; repaired same hour by service-role PATCH and verified. See § 13 F122. F123 — **RESOLVED 2026-08-07, same session** (scripts repo `4b83ae3`, **committed but not pushed** — `guard-git` blocks the agent, so it queues behind `5bc7461`; the on-disk scripts are already correct). F112(a) added `initial_order_due`/`title_note` to the **Lunar** normalizer only, and `refreshCatalog()` upserts `[...lunar, ...prh]` in batches of 100 — PostgREST requires one key shape per bulk insert, so **the single batch straddling the Lunar→PRH boundary failed on every import from 2026-08-03**, silently dropping 100 catalog records each time (`PGRST102 All object keys must match`; observed live as "2290 ok, 100 failed"). Today that only meant stale rows; **on a new-month import those ~100 titles would be absent and unreservable.** PRH now emits both keys as explicit nulls (not `undefined`, which JSON-drops); normalizers exported and a key-shape regression suite added (129/129 green, and a real dry run now upserts 2390/2390). Caught only because Rick pasted the full import log — see the detection-gap note in § 13 F123. F125 — **`main` and `staging` are not a superset relationship**: `supabase/migrations/` (two files, `phase_4_3_prod_constraints` + `phase_4_4_prod_rls_functions`, commits `9111412`/`3ecb6b0`) exists **only on `main`** and has never been on `staging`, so the model the § Standard Deployment Workflow implies — *main = staging + prod `config.js`* — has been false since Phase 4.4 and no doc recorded it (filed 2026-08-09 during the F121 session-6 promotion, PR #114; **Low — nothing broken, nothing at risk**, and it has survived six promotions because `git merge staging --no-ff` cannot drop paths staging never held; both files verified present after that merge). Committing them straight to `main` was **legitimate** at the time — CLAUDE.md § Staging Only exempts Phase 4 cutover-window sub-deploys — the finding is the unrecorded asymmetry, not the commits. **Where it would bite:** any promotion that rebuilds `main`'s tree *from* `staging` rather than merging into it (squash, rebase, `git checkout staging -- .`, `git reset --hard staging`) silently deletes the only in-repo copies of that production DDL. Knowledge survives in `docs/phase-4.3-*.md`/`4.4-*.md` and the DDL is live in prod, so a loss is repo-history only — which is what holds it at Low. Every migration since went to `docs/sql/` instead (**9 files, identical on both branches**), so the replacement convention is already correct; these two are pre-convention residue. **RESOLVED 2026-08-10** via the chosen fix — documentation. § Repository Structure now carries a dedicated *"`main` is NOT simply staging + prod `config.js`"* subsection naming both files, their commits, why the documented `--no-ff` merge flow is immune, which promotion styles would silently delete them, and the two things not to do (**do not delete them from `main`**, and do not copy them onto `staging` — that puts prod-cutover DDL on a branch that must never run it). Re-verified against both remotes first: those two files are the only paths on `main` and absent from `staging`. No repo-state change; the asymmetry is deliberate and stays. See § 13 F125. F126 — **no user-management surface**: no screen anywhere edits a `user_profiles` row (name, email, `is_admin`), and the account lifecycle stops at "approved" — filed 2026-08-09 from Rick's Accounts-tab direction and **deferred by his explicit choice** (*"a real need but can be logged for a future change"*), **scoped OUT of the Accounts session**, which renders **no Edit control at all** rather than a disabled one. Half the machinery already exists unwired: `status` CHECK allows `'suspended'`, `Users.suspend()` writes it, and it has **zero call sites** — noticed and recorded at 5.0 S3 (2026-06-11) as *"no admin UI entry point… (no Users tab)"*, which is exactly the tab now being built. **Narrowed 2026-08-09 to editing only — the pause half is SETTLED and ships in the Accounts session.** Rick answered the status question better than either option offered: **`'suspended'` exists as its own status but carries the same permission impact as `'pending'`** — correct semantics *and* existing enforcement, by widening the check rather than reusing the state, costing one line at `catalog.html:245` (read by 8 sites in that one file). **F126 PARTLY RESOLVED 2026-08-10 — LIVE IN PRODUCTION** (PR #116, merge `aa35d7f`): `get_account_activity()` RPC, a sortable **Last seen** column, a **Never signed in** filter (which lists exactly one person on production — `Ronald Burke`, invited 2026-03-17, never confirmed — **called by Rick 2026-08-10, closed**), **Edit → `full_name`**, and pause's confirm stating existing reservations stand. **Still open in F126:** editing **email** (needs an Edge Function per F25) and **`is_admin`** (cut as a privilege-escalation surface; stays a Supabase-console task). **Two plan corrections found by probing, not reading:** the RPC gate was written `IF NOT current_user_is_admin()` and was OPEN (that function returns NULL, not false, for a caller with no identity — fixed to `IS NOT TRUE`), and the filter could not be called "unanswered invite" because `created_by_admin` **defaults to true** and `register-customer` never sets it. Plan/scoping detail follows. **F126 WAS SCOPED AND PLANNED — `docs/admin-account-lifecycle-f126.md` (2026-08-09, not started).** Rick's three answers removed a schema migration, an Edge Function and a status collision, leaving **one DB object**: a `get_account_activity()` SECURITY DEFINER RPC. (a) **Edit = `full_name` ONLY; email READ-ONLY and `is_admin` CUT** — `user_profiles.email` is a denormalized copy of `auth.users.email` with no sync trigger (**F25**) and `auth.users.email` is the *login identity*, so editing the profile copy would look like it worked and silently not move the login; doing it properly needs GoTrue admin → service role → an Edge Function, which is OUT. **`is_admin` editing was planned and then CUT (Rick 2026-08-09) in favour of keeping it a Supabase-console task** — it is a **privilege-escalation surface** whose only protections would have been client-side (the F127 shape), and revoking your own admin locks you out of the surface needed to undo it. The database already permits any admin to PATCH `is_admin` on anyone via the `admins manage tenant profiles` ALL policy, so cutting it does not close a hole — it declines to open a door to one. Rendered **absent, not disabled**. (b) **Pause leaves existing reservations untouched** — already the shipped behaviour, so that half is documentation, not code; avoids any F109/F117 money interaction. (c) **Unanswered invites are DERIVED, no `'invited'` status** — `created_by_admin AND last_sign_in_at IS NULL`, which sidesteps widening the CHECK and re-teaching every status consumer a fourth value. **The RPC's gate must be in its BODY, not its grant**: admins are `authenticated` too, so there is no role to grant that excludes customers — `current_user_is_admin()` inside, `anon`/`PUBLIC` revoked explicitly per F124. **Also folded into F126 2026-08-09 (Rick's call): a sortable "Last seen" column and an unanswered-invite filter.** `auth.users.last_sign_in_at` exists but is **not reachable from the admin client** — there is no `public.auth_users` view (service-role read returns **404 `PGRST205`**), so it needs a SECURITY DEFINER RPC on the `get_ordered_codes()` pattern, subject to F124's grant lesson. **The cheap proxy was tested and fails — do not retry it:** `has_seen_welcome` agrees with `last_sign_in_at` only **8/12 on production** and would falsely flag four signed-in customers. **The real cause is not the missing column:** `invite-customer` sets `status:'active'` the instant an invite is sent (`:136`) while `register-customer` sets `'pending'`, so an unanswered invite is indistinguishable from a real active customer; an `'invited'` state would need the status CHECK widened and must be decided **together** with the pause work, not after it. **Measured on production: exactly one — `Ronald Burke`, invited 2026-03-17, never confirmed, never signed in, ~5 months. Called by Rick 2026-08-10; closed.** See § 13 F126. F127 — **account `status` is not an authorization boundary: the pending gate is client-side only** (filed 2026-08-09 while scoping Accounts; **Low–Medium — authorization gap, not data exposure**; no cross-tenant read, nothing newly readable, and it needs an account that self-registered and confirmed email but was never approved). **Measured on staging, not inferred:** a `status='pending'` user signed in as itself and `POST /rest/v1/preorders` returned **HTTP 201, row persisted** (fixture torn down, profile rows = 0). **No `preorders` policy references `status` at all** — the whole gate is `catalog.html:245` and 8 UI sites reading it; `subscriptions.html` has no status check whatsoever, so a pending user can subscribe by ordinary use of the page. Same shape as **F109**. **Consequence: `'suspended'` inherits this by construction**, so *paused is a UI block, not a hard one, and must not be described as more than that* — a deliberate, informed trade (Rick's call: parity now, file the gap so it is visible rather than assumed closed) taken over widening the Accounts session into an RLS change on the policy set **F16** already flags. Fix direction is its own session: a status predicate on `users manage own preorders`, built so it does not break **AdminContext impersonation** (the admin is the authenticated user while writing a customer's row) or the import's service-role writes, and via a SECURITY DEFINER helper rather than an inline `user_profiles` subquery, which is how RLS recursion was caused before. Deferred; see § 13 F127. **F92 — narrowed to one residual 2026-08-10, when the live-DB pass finally ran.** Everything PostgREST can reach was re-read from **both** live databases and § 1–§ 12 corrected. The consequential catch: **§ 6.4 `get_popular_series()` claimed a live *"customer-facing cross-tenant analytics leak"* that did not exist** — the tenant filter has been in the body since F20 on 2026-05-10, and tenant 2 onboarded 2026-06-19, so for **seven weeks** the canonical reference announced an emergency that wasn't there. A stale doc that manufactures a false alarm is the same defect class as F105's hidden gate, failing the other way. Also found: **`is_admin()` is alive on PRODUCTION and absent from staging** — F19/F23 record it "dropped, confirmed absent from pg_proc" with **no environment qualifier**, but that drop was staging-only (Phase 4.1 was the pre-cutover *staging* pass); verified twice independently (prod HTTP 200, staging 404 `PGRST202`). It is dead code lacking `SET search_path`; **dropping the prod residual is Rick's call.** The § 6 inventory was wrong three ways (nine functions claimed; live is **11 staging / 12 production**, with `resolve_tenant_by_slug` and `get_account_activity` live with *no entry at all*), the four F110/F112 `catalog` columns had been live a week undocumented, and § 2 undercounted tables (10→11) and Edge Functions (8→**9**, `register-tenant` missing). **What remains owed is only what PostgREST structurally cannot read** — `pg_constraint`, `pg_policies`, `pg_proc`, `pg_class`, `information_schema` — i.e. column types/nullability/defaults, CHECK constraints and FKs, **RLS policy bodies**, index lists, and function bodies/`prosecdef`/EXECUTE grants. That needs Rick in the SQL Editor; the two that matter most are the policy bodies (an authorization surface) and the DEFINER grants (F124 showed `REVOKE … FROM PUBLIC` does not do what it looks like). See § 13 F92.

**F16 is CLOSED on both environments — settled definitively 2026-08-10, and the doc that said otherwise was the problem.** `technical-reference.md` § 7 documented `preorders` as carrying **4** policies including `admins write tenant preorders`, whose tenant check is on the *admin's profile* rather than the row — i.e. a live HIGH-severity cross-tenant write hole — while F16's own status said both extra policies were dropped in May. Five independent proofs (three from contemporaneous live `pg_policies` captures, two arithmetic reconciliations of recorded policy totals) establish **2 policies, not 4**, on both environments. Production was fixed **separately** from staging — by the Phase 4.4 migration on 2026-05-31, not the 2026-05-10 staging hot-fix — which is exactly why the two could have differed and why this was worth checking rather than assuming. **§ 7's stale table had already propagated into F127's own root-cause analysis** (filed three months later, reproducing all four rows rather than re-reading the database): the **F106 mechanism**, second confirmed instance. Full evidence: `docs/preorders-authorization-boundary-f127-f109.md` § 2.1. **§ 7's `preorders` subsection is still uncorrected in the reference** — deliberately left to a single owner rather than edited by two sessions at once; it is listed in F92's owed SQL.

**F127 + F109 are PLANNED — `docs/preorders-authorization-boundary-f127-f109.md` (2026-08-10, not started).** Both are the same shape: a guard that lives in client code and not in the database. Measured, not inferred: a `status='pending'` user signed in as itself and `POST /rest/v1/preorders` returned **HTTP 201**; a direct DELETE with a real customer token against an already-ordered reservation returned **HTTP 204**. F127's previously-unverified sub-claim was **confirmed true** — `subscriptions.html` consults exactly one profile field (`is_admin`) across all 744 lines, so a pending user can subscribe **by ordinary button click, no crafted request needed**, which makes it the more urgent half. `mylist.html` is likewise ungated (its quantity stepper is an UPDATE). **Three things the code settled that assumption would have got wrong:** (1) **impersonation is already safe** — `AdminContext` substitutes the customer's id into the request *body* while the request carries the *admin's* JWT, so `auth.uid() ≠ user_id` and those writes have always gone through the admin policy; a predicate on `users manage own preorders` cannot reach them. (2) **An unconditional F109 trigger breaks teardown** — the Playwright fixtures DELETE `preorders` as service role and *throw* on failure (that throw is F95's own fix), and the same mechanism would have blocked Rick's F122 production repair on 2026-08-10; the trigger must exempt `auth.uid() IS NULL` and admins. (3) The withdrawn-title cancel exception (**F110**) must survive, so the trigger checks it **first**. Design is additive-only — one DEFINER helper, four **RESTRICTIVE** policies, one `BEFORE DELETE` trigger — so no existing policy is edited and every step rolls back with a single `DROP`. The predicate gates **`WITH CHECK` only, never `USING`**: a blocked customer keeps seeing and cancelling their own reservations, because anything else makes Pause destructive and contradicts F126's shipped confirm text. **Live measurement, both environments: zero preorders and zero subscriptions are held by any non-active profile**, and production has no pending or suspended accounts at all — so the awkward case (an account blocked after accumulating reservations) exists nowhere today, which makes this a good moment to close the gap. Rick's three confirmations are in that plan's § 3.

Next free finding ID: **F129**.

Before proposing any work, read the active phase docs and confirm the proposed
change is in scope. **If something seems related but isn't on the IN scope list
in the active sub-deploy plan, stop and ask** rather than fixing it inline.

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
- **Edge Functions follow off-plus-in-body-auth.** JWT verification disabled at
  the platform level is the recommended pattern; in-body `Authorization` header
  verification (`/auth/v1/user` → profile lookup) is the actual gate. JWT-off is
  not a misconfiguration. The exception is `register-customer` and any other
  intentionally-public endpoint.
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
**Legacy prod URL:** https://mrcyberrick.us/comic-preorder/ (GitHub Pages — kept warm as a rollback surface past the original "until 5.5 closes" gate; Rick's call 2026-07-15 at 5.5 S6 was to keep it warm and revisit retirement in a future session, not tied to any phase boundary; redirects to `/` via `_redirects`)

---

## Repository Structure

```
comic-preorder/                    ← production repo (github.com/mrcyberrick/comic-preorder)
  index.html                       ← sign-in / landing
  catalog.html                     ← ┐
  mylist.html                      ← │ the five nav+footer pages that must
  arrivals.html                    ← │ stay in sync (see § Files That Must
  subscriptions.html               ← │ Stay in Sync)
  admin.html                       ← ┘
  analytics.html                   ← admin-gated nav link; no shared nav block
  forgot-password.html             ← linked from the index.html sign-in footer
  app.js
  style.css
  config.js                        ← tracked per branch; never edited by agent
  CLAUDE.md                        ← this file
  README.md
  supabase/functions/              ← all 8 Edge Functions (post-4.1 Session 1)
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
- **Email:** MailerSend via Supabase Edge Functions
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

# Optional pre-push baseline — see "Smoke-test ordering" below for why this
# does NOT test your change. Its value is confirming staging was already green,
# plus stage [1/2], which does run against local files.
cd C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts\playwright
.\run-smoke.ps1

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
post-push failure attributable — but it is a baseline, not a gate.

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
- Hidden in admin impersonation context — **exception (2026-07-19):** the
  reserved-suggestions list on `subscriptions.html` stays visible during
  impersonation (it shows the impersonated customer's unsubscribed reserved
  series) with its subscribe buttons disabled, per Rick's explicit decision
  in `docs/subscription-reserved-suggestions.md` § 4c
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

All 8 functions are in the repo at `supabase/functions/*` (post-4.1 Session 1).
Tenant-aware as of Phase 2 + 4.1 hardening:
- `notify-customers` — in-body admin auth (F47); recipient list scoped to caller's tenant
- `create-paper-customer` — in-body auth; JWT-off platform setting (post-4.1 C13)
- `invite-customer` — in-body auth; explicit `tenant_id` + inline HTML template
- `register-customer` — explicit `tenant_id` (intentionally pinned to founding;
  Phase 5 will revisit for self-service signup)
- `send-my-list` — in-body auth + caller identity check (F51, F54); tenant-scoped queries
- `claim-paper-customer` — in-body auth; PATCHes tenant-scoped (F50)
- `approve-customer` — PATCH-only on existing rows; tenant inherited from row
- `reset-password` — public endpoint by design

`FOUNDING_TENANT_ID` secret must be set in Supabase staging → Edge Functions →
Secrets for tenant-aware functions to work.

---

## Known Out-of-Scope Items

Pending or deferred work — do NOT touch in agentic sessions without explicit
approval.

### Deferred — feature not in active use
- **Partial fulfillment not representable** — product decision, deferred until
  product scoping

### Deferred — separate future session
- **Analytics conversion instrumentation (F89)** — log claims/invites so
  paper→app conversion is measurable (Edge Function touch). See
  `docs/technical-reference.md` § 13 F89.
- **Analytics monthly rollup (F90)** — per-tenant monthly snapshot written at
  import so adoption trends survive the 90-day purge (schema + import
  script). See `docs/technical-reference.md` § 13 F90.
- **Closing the ad-hoc order loop (F108)** — **Session A COMPLETE AND LIVE IN
  PRODUCTION 2026-08-04** (PR #103, merge 22:29 UTC; **V-A2 verified on live
  data — At Risk went 2 → 0**, four Backordered rows correctly remaining for
  Session B). **Session B COMPLETE AND LIVE IN PRODUCTION 2026-08-06** (PR
  #104, merge `2029e70`; comic-preorder `095d051`..`b301a67` on staging first,
  then promoted). The signed-quantity SQL migration
  (`docs/sql/order-submissions-signed-quantity.sql`) and the real `-4`
  adjustment for `75960621668000111` both ran and were verified on
  **production** ahead of the client code (staging 5+7−4=8, production
  5+7−4=8 — production's first migration attempt silently no-opped, caught
  by re-checking `pg_constraint` rather than the grants query, which looks
  identical either way; the second attempt succeeded). Post-deploy
  write-smoke passed: reserved `ACTION COMICS #1103 CVR A CHRIS BRUNNER` as
  "Book Stop" through the live production app, confirmed correct tenant_id,
  cancelled, confirmed removed. Also promoted in the same PR and resolved
  same-session: **F118** (Print/Save Report ledger blindness), **F119**
  (Bagging List printed the Order Follow-Up/Withdrawn panels), **F120**
  (rejected titles invisible on Bagging List and My List — badge-only fix).
  Scripts repo commit `5bc7461` (`isNewMonth` import confirmation +
  `order_deadline` clear) is **pushed** — verified an ancestor of
  `origin/main` 2026-08-10. The `guard-git` push block was a hook bug, not
  policy (fixed 2026-08-10, § 13 F104). Session C not started. Plan: `docs/order-loop-closure-f108.md` § 8 Session B for full
  evidence.
  **Session B follow-on, COMPLETE AND LIVE IN PRODUCTION 2026-08-06** (PR
  #105, merge `93caca0`; staging `ec98f54`+`40203d2`): a **catalog-month
  selector on the By Distributor tab**, so a closed cycle stays reviewable
  and printable after the next import moves `currentCatalogMonth` on —
  Rick's monthly process prints the reserved-titles report as a cycle's
  permanent record, and a cycle's order state is not final until after the
  ordering is done. Mark Ordered stays **enabled** on a closed cycle (late
  recording is the point; its write now files under the title's own
  `catalog_month`); order-sheet exports are **disabled** there with an
  inline reason (the Order Builder is FOC-cycle-scoped and cross-month per
  F111, so it would build a live sheet while the table shows history).
  Shipped with it: the **Order Builder cycle list now breaks out
  already-ordered / withdrawn counts**, so the checkboxes reconcile with
  the "N titles ready to export" summary — a cycle reading "1 title" beside
  a summary reading "0 ready" was correct but opaque. 81/81 Playwright
  green; client-only, no DB change.
  **Order Builder readability follow-on, LIVE IN PRODUCTION 2026-08-07**
  (PR #106 merge `93caca0`-successor, PR #107 merge `01cfb67`; 85/85
  Playwright green, client-only): the Already Ordered panel is **scoped to
  the selected FOC cycles** and **collapses exact matches** behind a count
  (it was carding 350 titles on production PRH, ~345 with nothing to
  decide); **one collapse rule now governs the whole modal** — expanded =
  may need action this export, collapsed = accounted for; FOC-passed cycles
  state the **consequence** ("ordering now backorders, availability not
  guaranteed") and sit collapsed below the live ones while staying
  selectable (F112(b)). **The consequential one:** the export summary
  counted reservation ROWS while the file groups by distributor code, and
  ignored approved already-ordered overrides — "70 titles ready to export"
  against a file of 58 lines, measured on production. Both now share one
  `buildExportRows()`. **That was the third rows-vs-titles slip in this one
  modal** (cycle counts, held-back headers, summary), each caught by Rick's
  arithmetic on the live screen rather than by the suite — a green suite
  asserts behaviour, not coherence between numbers on a page.
  **DEFERRED to its own session — decoupling "record the order" from
  "download the file".** Rick's walkthrough exposed a timing flaw in
  confirm-on-export (§ 4.2, shipped the same day): the export produces a
  *file*, but the order — and which titles the supplier rejected — happens
  after that, so the prompt asks before the answer is knowable. This is
  F101 § 4.2's original principle ("generating a file is not proof of
  submission") reasserting itself; the § 3.4 reversal holds for ad-hoc and
  not for the monthly cycle. Agreed direction: split the Order Builder into
  "Generate & Download" and a separate "Record submitted order", the latter
  being the export set with per-title checkboxes where **ticked = ordered,
  unticked = rejected**. **Also owed in that session:** confirm-on-export
  hardcodes `order_type: 'adhoc'`, but Rick uses the Order Builder for the
  **monthly** cycle — and `classifyForExport()` routes `adhoc` matches away
  from the "Already ordered — your call" bucket, silently dropping F102's
  remainder-defaulted quantity control on the next cycle. See the plan's
  § 8 for both.
  **Session A shipped:** `order_deadline` now **supersedes** the
  in-current-month rule instead of adding to it, and a **lapsed deadline is
  treated as absent** so the in-month rule takes over automatically rather
  than At Risk going silent. Both the follow-up panel and the Order
  Builder's held-back panel route through one shared `missesOrderCycle()`
  helper — `classifyForExport()` was found mid-session to carry its own copy
  of the expression with the same `OR` bug, so fixing one would have left
  two surfaces disagreeing. Treating a lapsed deadline as absent is **not a
  new convention**: `catalog.html`'s customer banner has always self-hidden
  on a passed date, so this makes the admin side consistent with shipped
  behaviour. **V-A1 and V-A3 green; 67/67 suite, zero flaky**; `order_deadline`
  restored to its pre-test value and fixtures verified gone by SELECT.
  **V-A2 (panel shows 0 At Risk) is a production-data observation** and is
  owed read-only after promotion. **Carried to Session B:** clearing the
  stored `order_deadline` at `isNewMonth` (scripts repo). **Settled 2026-08-04:**
  `order_deadline` also drives the customer catalog banner (which already
  self-hides on a passed date, so customers are unaffected); the admin *input
  field* will show an expired date until Session B's `isNewMonth` clear lands,
  and **Rick's call is to leave it — no "expired" hint.** Considered and
  declined, not overlooked; do not add one in a later session. **DIRECTION CHANGED
  2026-08-04: file ingest is DROPPED, not deferred.** Rick's binding
  constraint — *"I do not want to download multiple files to feed the import
  every week… The pulllist app should not be a chore to maintain."* The plan
  is now **capture-in-flow**: (1) **confirm-on-export** for ad-hoc orders
  (explicit confirmation after the Order Builder download, deliberately
  reversing F101 § 4.2 with the operator's agreement); (2) **confirm at
  new-catalog import**, gated on `isNewMonth` so a same-month refresh never
  re-confirms; (3) **zero-quantity Mark Ordered records a supplier
  rejection** — which needs `CHECK quantity >= 1` relaxed to `>= 0` and
  **`get_ordered_codes()` reworked, or it will tell the customer "✓ Order
  placed" for a rejected title**; (4) a rejected title **reuses F110's
  generic unavailable surface** (Rick's call), though *not* by writing to
  `catalog.withdrawn_at` — that is a property of the title, a rejection is a
  property of our order. The customer's arrival date comes from
  `catalog.on_sale_date`, verified to match both distributors exactly, so no
  supplier feed is needed. **Second live defect found the same day:
  `order_deadline` must SUPERSEDE the in-current-month rule and the shipped
  code has it as `OR`** — verified on production (`order_deadline
  = 2026-08-21`), the two At Risk rows (FOC `2026-08-31`, i.e. after the
  deadline) should not be showing. **Combined with the four false
  Backordered rows, the panel's precision on 2026-08-04 was 0 of 6.**
  **Both open decisions were answered 2026-08-04 — the plan is fully
  specified and ready to execute:** a **stale deadline resets to blank**
  (Rick's call, better than either option offered — it self-heals into the
  in-month fallback instead of going silent, and the empty field is itself
  the prompt to set the next cycle), implemented as read-path
  treat-as-absent plus a clear at `isNewMonth`, with **no write-on-page-
  load**; and the import confirmation is **reviewed for now**, built so that
  becoming blind later is a flag rather than a rewrite. Real exports from both
  distributors are in `catalogs/order-confirmations/` (local, uncommitted)
  and are characterised at that plan's § 2.9. **Match feasibility measured
  against live production: PRH 28/31 (90%), Lunar 137/149 (92%)**, misses
  categorised and benign; ~180 ledger rows per monthly ingest. **Reading the
  real files corrected the plan twice before any code existed** — (1) the
  rich supplier state (Shipped/Processing, ship + in-store + est-delivery
  dates) is **screen-only and absent from both exports**, so three planned
  columns were cut and the customer-facing "expected Aug 12" is not
  deliverable from these files; (2) **Lunar's order number is in the
  filename, not the file**, and Lunar supplies no order date at all while
  `submitted_on` is NOT NULL. **Blocking implementation fact: the Lunar
  export contains negative-quantity lines and `order_submissions` has CHECK
  `quantity >= 1`** — a row-per-line ingest aborts the import, so netting by
  code (skip net-0, halt on net-negative) is mandatory. **PRH's `Order
  Status` is the F110 trap repeated: 31/31 rows read `Backordered`** — a
  column that never varies is not a signal, and it collides verbatim with
  our own opposite-meaning label, so it must never be ingested or shown.
  **Three decisions are owed from Rick before Session B can start** (Lunar
  order-number source, Lunar `submitted_on` source, and the
  backfill-overlap option — plan § 4.1). **Why it matters:** on 2026-08-04 the production
  Order Follow-Up panel showed 4 titles BACKORDERED and **all 4 had actually
  been ordered** (precision 0 of 4). The cause is the input, not the logic —
  **Mark Ordered has been used zero times on production**; all 857 ledger
  rows are backfill across exactly three cycle dates, and the orders in
  question were placed off-cycle directly on the vendor sites. F116's
  arrival-evidence clearing cannot fix it: order → arrival is ~10 weeks, so
  arrival evidence clears *stale* false alarms while only order evidence
  clears *in-flight* ones. Customer impact today is **nil** (all four are
  prior-month rows that never reach the FOC-lock surface — verified), so
  this is priority-not-emergency, and the customer-facing half is sequenced
  last behind a product decision. Carries an F102-shaped double-count hazard
  that must not be resolved casually — see the plan § 4.1.
  See `docs/technical-reference.md` § 13 F108.
- **Order-ledger cancel guard is client-side only (F109)** — moving it into
  a `BEFORE DELETE` trigger on `preorders` is the only version that holds
  against a hand-crafted request. Low priority, not reachable through the
  UI. See `docs/technical-reference.md` § 13 F109.
### COMPLETE ON STAGING — Sessions A and B both closed; production promotion is Rick's call

**Plan: `docs/order-export-followthrough-f110-f111-f112.md`** (written 2026-08-03,
planning session). Covers **F110**, **F111**, **F112**, **F113**, and **F114**
(a bug found and fixed during Session B). Each session has its own runbook,
gates and completion criteria; see `docs/technical-reference.md` § 13 for full
evidence per finding.

**Session A — detect and record — COMPLETE 2026-08-03, live on staging AND
production, no longer pending.** Four additive nullable `catalog` columns
(`initial_order_due`, `title_note`, `withdrawn_at`, `withdrawn_last_seen_month`)
landed on both environments via `docs/sql/catalog-withdrawal-and-lunar-fields.sql`.
F110 withdrawal detection (the corrected cross-month set difference, § 3.3) and
F112(a)'s `InitialOrderDue`/`TitleNote` reads are implemented in both
`import.js`/`import-staging.js`, unit-tested (39 new tests, 85/85 suite green),
and verified against real staging data and a torn-down synthetic fixture (gates
V-A1/V-A2/V-A3, all green). **Detection does not run until the next monthly
import** — it is gated on `isNewMonth`. Full evidence:
`docs/technical-reference.md` § 13 F110/F112; `docs/order-export-followthrough-f110-f111-f112.md`
§ 8 Session A.

**Session B — surface and act — COMPLETE 2026-08-03, live on staging; not yet
promoted to production (Rick's call, not yet requested).** F113 pagination
landed first (count-first, paged `fetchAllPreorders()`, gate V-B1 green on
staging). F111's cross-month gather (`allPreordersAllMonths` + a collapsed
`gatherCollapsed`, re-pointing only `distinctFocDates()`, `classifyForExport()`,
`computeBackorderRisk()`, and the Order Builder consolidation — `allPreorders`
and its other 15+ consumers untouched) is live, both collapses (export
consolidation by `exportCode`; same-customer cross-month duplicates to the
newest-month survivor at max qty) surfaced in the held-back panel, gates
V-B2/V-B3 green. F110's admin `#withdrawn-panel`, My List flag, and cancel
exception (overriding both the FOC lock and the "already ordered" lock,
`isFocPast`/`isFocLocked` byte-unchanged) are live, gate V-B4 green — **and
reach the read-only "Upcoming Arrivals" grid, not just the current-month
table**, after a mid-session scope gap was found and Rick chose to fix it same
session (see F110 below). The F112(b) "cannot arrive" copy correction is
applied to the panel and both docs. Cancellations on an already-ordered
withdrawn title are logged via `UsageEvents.cancel(..., { withdrawn: true,
cancelled_after_order_submitted })` (Rick's call). Spec 15 extended (V3/V4/V7
plus new V-B2/V-B3/V-B4 coverage, two dedicated 375px mobile-width tests) —
**63/63 Playwright tests green on staging.** All seeded fixtures torn down,
reverified by live SELECT returning zero rows. Full deploy log and evidence:
`docs/technical-reference.md` § 13 F110/F111/F113/**F114**.

**All three original findings were filed 2026-08-03 from the PRH and Lunar
vendor documentation, read at Rick's request before extending the
order-export work — deliberately, to avoid designing against assumed
distributor behaviour. That read corrected one wrong fix direction (F110)
and one wrong severity assumption (F111) before either reached code. The
planning session then corrected two more things before code:** F110's
*replacement* fix direction was also wrong (it reused a function that
matches zero rows — see F66), and **F112(b)'s severity split was overruled
by Rick outright.** Reading the vendor docs was worth it; trusting them
without asking the operator was not. **Session B corrected a fifth thing
mid-execution:** the plan's own citation for the My List cancel exception
covered only the current-month table, not the prior-month case (the real
MIDNIGHT X-MEN #2 shape) that actually lives in the read-only Upcoming
Arrivals grid — found by implementation, not by planning, and fixed the
same session at Rick's explicit choice.

### Operational, not code — new 2026-08-03
- **`ACTION COMICS #1 FACSIMILE EDITION CVR A`** (`0626DC0190`, Lunar, 1 copy)
  reached FOC **2026-08-03** unordered and is now Backordered. Per F112(b)'s
  overrule it is **still orderable**, availability unguaranteed. No surface in
  the app will show it until F111 lands, so it needs a manual decision now.

### Operational, not code — outstanding
- ~~**PRH holds 12 copies of `75960621668000111` against 7 reservations**~~ —
  **CLOSED 2026-08-05. Rick corrected the PRH order down to 8 copies**, against
  a re-measured true demand of **8** (6 customers; raw rows read 11 because
  Jay Underhill and Book Stop each re-reserved when the title was re-listed —
  the F85 cross-month duplicate). FOC was **2026-08-31**; the surplus is gone.
  **What remains is a data task, not an operational one:** the ledger still
  reads **12** and cannot record the correction, because `CHECK quantity >= 1`
  rejects a `-4` adjustment row (**F117**, filed 2026-08-05). Rick's call was
  to wait for Session B's signed-quantity change and append the adjustment
  rather than edit the 7/26 row down — so **the 12 is deliberate; do not
  "fix" it by rewriting history.** The 2026-08-24 reminder (routine
  `trig_01D8pWAMP5uuLqqb62gDjGrY` + calendar event) is now **partly stale** —
  the phone call is done; only the ledger row is owed. See § 13 F117.

The order-export correctness session (F101 FOC window + F102 order state)
closed 2026-08-03 and is **live in production** (PR #100, merge `5951a30`) —
no longer listed here. Production carries `order_submissions` + RLS,
`get_ordered_codes()`, and an 857-row backfill of the real May/June/July order
history. See `docs/order-export-foc-window-and-order-state.md` § 8 for the full
deploy log and `docs/technical-reference.md` § 13 F101/F102/F109.

Phase 5 (all sub-deploys 5.0–5.5, incl. the slug→id RPC, per-tenant branding,
self-service tenant signup, and second-tenant onboarding) closed 2026-07-15 —
no longer listed here. See `docs/phase-5-second-tenant-onboarding.md` for the
full closed scope and `docs/technical-reference.md` § 13 for any findings
carried forward.

The test-infrastructure maintenance session (F91 GoTrue-admin key flakiness,
F95 orphaned staging test profiles, F103 the seed-month false-red) closed
2026-08-02 — no longer listed here. All three resolved; see
`docs/test-infra-maintenance-f91-f95-f103.md` for the full closed scope and
`docs/technical-reference.md` § 13 F91/F95/F103 for the resolution detail.
Filed F107 (a GoTrue rate-limit observation under repeated-run gate-verification
pressure, not reproduced under normal usage) — see § 13 F107. The Playwright
suite changes themselves are **not** committed anywhere (untracked in every
repo, per § What's tracked vs local-only) — only this plan and the doc
updates are.

The `import.js` maintenance session (F75 key rotation, F78 historical dedup,
F85 cross-month root fix) closed 2026-07-15 — no longer listed here. See
`docs/import-js-maintenance-f75-f78-f85.md` for the full closed scope.

The F86 prod legacy API key retirement session (staging rehearsal, prod
`config.js` migrated to a publishable key via PR #80, one weekly shipment
cycle quiet window, prod legacy-key toggle flipped, both old legacy keys
confirmed dead) closed 2026-07-22 — **live in production**, no longer listed
here. F88 (edge functions' own service-role calls breaking post-toggle) was
surfaced and resolved within the same session — verified false on staging
(`notify-customers`) and prod (`create-paper-customer` against the real
founding tenant) both before and after the toggle flip; no Edge Function
code changes were needed. Closes the F75 residual. See
`docs/f86-anon-key-migration.md` for the full closed scope and evidence.

The analytics cycle-alignment session (cycle-anchored deltas on Executive +
Operations KPIs, "This Cycle vs Last" overlay chart, New Customers tile)
closed 2026-07-19 — **live on production**, no longer listed here. V1–V5
all green; merged ff-only to staging (`d6ee227`); promoted via PR #90
(`e250281`) 2026-07-19; post-deploy write-smoke passed (reserve → correct
prod `tenant_id` → cancel → row deleted). See
`docs/analytics-cycle-alignment.md` for the full closed scope.

The Analytics v2 engagement dashboard (full redesign of `analytics.html`,
ungated) closed 2026-07-16 — no longer listed here. See
`docs/analytics-v2-engagement-dashboard.md` for the full closed scope; F87
candidate (admin-logging doc/code contradiction) remains a separate open
filing decision, not part of this closure.

The catalog info-card reserve-sync fix (`catalog.html` + `style.css`; four
defects on the modal reserve path) closed 2026-07-27 — **live in
production**, promoted via PR #99 (`d08d10d`) at Rick's explicit request the
same session; production build verified serving all four changes; Rick
confirmed green in a real browser both on staging and post-deploy. Three of
the four shared one root cause — `toggleReserve()` assumed its `btn`
argument always lived in a grid card, so the modal call site silently lost
the `Qty:` badge (`closest('.comic-card')` → null), and the card's reserved
state was patched on a 300 ms `setTimeout` race that lost whenever the
round-trip ran long. Replaced with `syncCardState()` / `syncModalState()`,
which repaint each surface from `reservedIds` after the write settles. The
fourth was the native number-input spinner drawn over the custom `−`/`+`
controls, hidden via CSS scoped to `.qty-stepper`. **No plan doc** — this was
a direct bug-fix request outside any sub-deploy. **Note for anyone touching
this path: it has zero Playwright coverage** (no spec references
`#modal-reserve`, `#modal-qty`, or `.reserved-indicator`), which is why the
defects shipped unnoticed and why a green suite does not exercise it; see
F103.

The subscription reserved-suggestions feature (always-on "Series you're
already reading" one-click subscribe list with Undo on `subscriptions.html`;
Popular section removed; admin impersonation sees a read-only list) closed
2026-07-19 — **live in production**, all V1–V5 green; promoted via PR #91
(`5167ab4`) at Rick's explicit request the same session; post-deploy
write-smoke passed. Subscribe paths on the page now carry `source`
attribution (`reserved_suggestion` / `series_search`).
`app_settings.popular_series` is now unused by the app (left in place, no
DB change, both environments). See
`docs/subscription-reserved-suggestions.md` for the full closed scope.

The subscription promotion feature (catalog banner + post-reserve subscribe
prompt) closed 2026-07-17 — **live in production**, no longer listed here.
All V1–V5 gates green; promoted via PR #86 (`107fc0a`) at Rick's explicit
request the same session; post-deploy write-smoke passed; final copy (no
separate perk/discount — Rick confirmed the informational copy as-is) live
on both staging (`raysandjudys`) and production (`rjbookstop`) founding
tenants, verified via the public `resolve_tenant_by_slug` RPC. See
`docs/subscription-promotion.md` for full scope and evidence.

If a session needs to touch any of the above, **stop and confirm**.

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

The nav block must be identical across `catalog.html`, `mylist.html`,
`arrivals.html`, `subscriptions.html`, `admin.html`. When updating nav, copy from
the most recently-updated file — the canonical version is whichever HTML file
was last touched.

The footer block must be identical across all five pages, placed immediately
before `<div id="toast-container"></div>`.

The `<script>` load order must be the same on every page: Supabase UMD bundle
→ `config.js` → `app.js` → page-specific code.

---

## Smoke Test Suite (local)

**Location:** `C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts\playwright\`
(local-only; never committed)

```powershell
cd C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts\playwright
.\run-smoke.ps1                              # full suite
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
.un-smoke.ps1
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

**Rules:**
- Local-only. Never committed. Never runs against production.
- `SUPABASE_URL` in `.env` must be staging; runner aborts if it's prod
- All `goto()` calls use paths without a leading slash

Canonical detail: `docs/phase-3.7-playwright-smoke-tests.md`
