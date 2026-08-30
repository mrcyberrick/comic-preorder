# Pre-Phase-6 Consolidation — September 2026

**STATUS:** SUPERSEDED 2026-08-30 by `docs/pre-phase-6-consolidation-wave-2.md` | staging=— | prod=— | findings=F115,F135,F130,F133,F145,F146,F72,F99,F131

> **⚠️ SUPERSEDED — read `docs/pre-phase-6-consolidation-wave-2.md` for the live plan.** This document
> was never formally approved and has been overtaken twice. **C1 (F115's S6 production backfill) is
> DONE** (2026-08-28/29) and the **F146 close-out is DONE on staging** (2026-08-29); items C2–C8
> carried forward into Wave 2, where Rick answered all eight open questions on 2026-08-29 and
> trimmed the scope — **C2/F135 is now DEFERRED**, C6 and C7 are deferred, and the direction is
> “small features for now,” not Phase 6 and not the Founding Partner launch.
>
> **Kept, not deleted, for one reason worth naming:** § 3.3 C1 holds the full reasoning trail for
> the S6 predicate decision — how the definition drifted between design and staging's execution,
> why that was 28 rows on staging and 859 on production, why the broader “classify retroactively”
> option was recommended and then **withdrawn**, and the five reasons behind the final call. That is
> the most carefully-argued decision in the project's recent history and re-deriving it would cost
> a session.
>
> *(Its token read `PROPOSED` while two of its listed findings had gone RESOLVED. `/preflight`'s
> findings cross-check flagged it correctly on 2026-08-30 — the doc-only-session blind spot that
> rule was written for, working as intended.)*

**Status:** **Proposed, not approved.** Written 2026-08-28 by a planning pass. This is a plan for a
*workstream*, not a phase sub-deploy and not Phase 6. It needs Rick's sign-off on § 5 before an
executor opens item C1.
**Predecessor:** Phase 5 — Second-Tenant Onboarding (`docs/phase-5-second-tenant-onboarding.md`),
Complete 2026-07-15.
**Successor:** Phase 6 — Open Self-Service Tenant Signup (`docs/phase-6-self-service-signup.md`),
STUB, gated on its own S0. **This workstream produces the S0 answer (item C6) but does not open
Phase 6.**
**Precedent for the shape:** `docs/phase-5.0-pre-phase-5-housekeeping.md` — "housekeeping before
features," the same reasoning applied one phase later.
**Branch base:** `staging` throughout. Production promotions per `CLAUDE.md` § Standard Deployment
Workflow only where an item explicitly says so.
**Next free finding ID:** **F148** *(was F146 when this was written; F146 and F147 were both consumed on 2026-08-28)*.

---

## 1. Current State Summary

### 1.1 Migration phase state

| Layer | State |
|---|---|
| Phases 1–4 | Complete. Production carries the multi-tenant schema, tenant-scoped RLS, tenant-aware Edge Functions and import script (Phase 4 closed 2026-06-10). |
| Phase 5 | **Complete 2026-07-15.** All six sub-deploys 5.0–5.5 marked Complete with dates; every Phase Completion Criterion ticked. Two tenants live on production (`rjbookstop` founding, `comicstore` pilot/seeded). Deferred-DDL Register: both items (F64 item 5, F64 item 8) **closed**. |
| Phase 6 | **STUB, not started.** `docs/phase-6-self-service-signup.md`, last updated 2026-06-16. Gated on **S0 — a wildcard DNS + wildcard TLS spike for `*.pulllist.app`.** F145 (filed 2026-08-27) measured that gate and confirmed it is **genuinely still closed**. |
| Active phase | **None.** Active sub-deploy: **none.** |

**Everything shipped since 2026-07-15 has been non-phase work** — standalone feature and finding
sessions run at a fast cadence against the founding tenant (apex marketing page, native customer
signup, weekly-pipeline hardening, the F101→F120 order-export/order-ledger chain, the six-session
admin restructure, analytics v2, the Lighthouse sweep, F132/F139/F140/F142/F143/F144). The
migration program itself has been idle for six weeks. That is the most important fact in this
summary: **there is no phase in flight, so the choice of what comes next is genuinely open.**

### 1.2 Most recent completed work

| Work | Staging | Production | Evidence |
|---|---|---|---|
| **F115 — September import, both environments** | **staging FULLY RESOLVED 2026-08-28** (S1–S7, V1–V7 green) | **real Sept import RAN 2026-08-28**; write confirmed live (`arrived=212, unknown=6, not_arrived=0`) — **S6 backfill still owed** | `docs/f115-arrival-truth-persistence.md` |
| **F147 — withdrawal detection flagged 33% of open reservations** | fix in scripts repo `main` `e4f968d` | **filed + fully RESOLVED 2026-08-28**; 519 prod marks cleared and independently re-verified | § 13 F147 |
| **F146 — false withdrawal flags never self-clear** | fix in scripts repo `main` `415bb38` | **OPEN** — fix shipped, awaiting a fresh-CSV re-pull to verify the clear | § 13 F146 |
| **F143 + F144 — ordering-side rejection handling** | 2026-08-27 (`fff78f2` F144, `54126c8` F143) | 2026-08-27, **PR #141** (`a1e8a8d`) | `docs/f143-f144-ordering-side-rejections.md` — STATUS: COMPLETE, both environments |
| Print "View Online" CTA | 2026-08-27 (`55b9ba8`) | 2026-08-27, **PR #140** (`334b5ad`) | `CLAUDE.md` § Current Migration Phase; no plan doc (feature build) |
| Customer phone number | 2026-08-26 | 2026-08-26, **PR #139** | `docs/sql/2026-08-26-user-profiles-phone.sql` (APPLIED both envs) |
| F142 — Held Back panel ledger check | 2026-08-26 | 2026-08-26, **PR #138** | § 13 F142 |

### 1.3 Staged-but-not-promoted

**Nothing.** Verified 2026-08-28 by direct comparison:

```
git log --oneline origin/main..origin/staging
  5cd93b5 docs: F143 + F144 promoted to production (PR #141, both environments)
```

One **doc-only** commit. The only non-doc paths differing between the branches are the two expected
structural asymmetries — `config.js` (per-branch by design) and `supabase/migrations/**` (present
only on `main`, F125). **No application code is sitting on staging unpromoted.**

**No unapplied SQL either.** Every file in `docs/sql/` carries a `-- STATUS:` line reading APPLIED
on both environments (or N/A where prod-only/staging-only by design). The one outstanding database
action in the repo is F115's production backfill, which is a data correction, not a migration.

### 1.4 What reads as open or not-yet-closed

**Plan docs not at COMPLETE** (read from each file's own `**STATUS:**` token, which `CLAUDE.md`
says to trust over narrative):

| Doc | Token | What it means |
|---|---|---|
| `docs/f115-arrival-truth-persistence.md` | **IN PROGRESS** | staging S2/S3/S4/S7 done 2026-08-18; prod migration APPLIED 2026-08-20; **S1/S5/S6 held for the September import** |
| `docs/f135-decouple-feed-publish.md` | **NOT STARTED** | Full runbook written 2026-08-21, direction settled with Rick, interim mitigation live |
| `docs/weekly-pipeline-consolidation-plan.md` | **NOT STARTED** | Scoping only, 2026-07-08; owner Rick; three artifacts outstanding. Adjacent to F135 but a much larger surface |
| `docs/interim-deployment-work-instructions.md` | **IN PROGRESS** | Written 2026-06-11 as a bridge "until post-5.5." 5.5 closed six weeks ago. Stale by its own terms; see § 4.6 |
| `docs/native-customer-signup.md` | **COMPLETE** — but **four completion boxes are unticked** | **A genuine conflict. See § 1.6.** |

**Findings open in § 13** (pointer only — full detail lives in `docs/technical-reference.md` § 13;
read each status line's *last clause*, not its first word, per `CLAUDE.md`'s own warning):

| ID | Severity | One line | State |
|---|---|---|---|
| F115 | Medium | never-arrived titles auto-fulfil, so My List tells a customer "✓ Order placed" for a book that never came | half built, gated on the September import |
| F135 | Medium | pull-feed publish welded to shipment import; an ad-hoc import mails a stale newsletter week | planned, not started; interim mitigation live |
| F131 | Medium scaling / **High continuity** | catalog import is a single-operator dependency, and every tenant's catalog comes from one shop's distributor access | open, no plan doc |
| F130 | Low | 197 orphaned GoTrue auth users in staging from Playwright fixtures | deferred to a test-infra session; **its stated fix plan is invalid** (§ 3.3 C5) |
| F133 | Low | date-dependent specs flip red with no code involved; variant (b) makes **targeted runs untrustworthy** | deferred, no plan doc |
| F145 | Low today, Medium if acted on | no wildcard DNS on `pulllist.app`; two docs said otherwise | items 1/2/4 done at filing; **item 3 still owed** |
| F72 | — | `register-customer` email template stays founding-branded after the F34 un-pin | deferred; design **with** F99 |
| F99 | Low defect / Medium decision | transactional and marketing mail split across two sender domains on two DNS providers | DMARC gate **read and clear** 2026-08-20; scoping unblocked |
| F89 | Low | paper→app conversion unmeasurable — a claim deletes the paper rows and nothing logs it | deferred |
| F90 | Low | `usage_events` 90-day purge forecloses adoption-trend analytics | deferred |
| F126 | Medium (product gap) | residual: profile **email** editing unreachable outside the Supabase console (needs an Edge Function, F25); paused-customer reservation handling undecided | deferred, Rick's call to schedule |

**F141 and F132 are resolved on both environments** and are not open work, notwithstanding that
`CLAUDE.md`'s pointer table still carries rows for them. F141 leaves one *unmeasured* residual: the
same CLS shape is plausible on `mylist.html` / `arrivals.html` and has never been measured.

The five findings the technical reference's own header calls out as HIGH or dormant-HIGH — **F4,
F15, F16, F20, F34** — are **all resolved on both environments.** That header text is a
Phase-4-era artifact; do not read it as a live risk list. See § 4.4 for what genuinely activates
with tenant N+1 today.

### 1.5 The F115 import-window constraint, and where it falls

**The rule, as `CLAUDE.md` § Current Migration Phase states it:** whatever lands next on **admin
ordering surfaces** must land *and promote* **before** F115's ~**Sept 7–10** import window opens,
or wait until after it closes. Two sessions must not touch admin ordering surfaces across an
import.

**Why the window exists at all.** F115's remaining steps are import-run steps and cannot be
simulated:

- **S1** — dry run (`--no-write`) against the real September files. This is the **first genuinely
  new-month run** for F110's withdrawal detection (gated on `isNewMonth`, never yet fired on real
  data), F123's key-shape fix, and F122's drift classifier. **Gate V1. If S1 is not clean, F115
  does not ship this cycle** and the import proceeds without it.
- **S5** — the real September import with the `arrival_outcome` write live. **Gate V4.**
- **S6** — re-measure, then backfill the surviving never-arrived set as `unknown`. Staging, then
  **PAUSE → Rick** for production. **Gate V5.**

**Where it falls relative to today: ⚠️ UPDATED 2026-08-28 — the window is HERE, ~10 days earlier
than the ~Sept 7–10 estimate this plan was written against.** Rick reports he is prepared to load a
new month. This answers § 5 Q1 and makes **C1 the active item now**, not a scheduled one. Two
consequences, both acted on below: the **admin-ordering freeze (§ 4.1) starts immediately**, and
**C5 is no longer sequenced ahead of C1** — see the correction in C5.

**Entry condition (b) — measured 2026-08-28, and it is NOT yet met on disk.** The newest files in
`catalogs\` are `2026_08_PRH_metadata_full_active.csv` and `Lunar_Product_Data_0826.csv`, both
dated Aug 21; there is no `2026_09_PRH_metadata_full_active.csv` and no
`Lunar_Product_Data_0926.csv`. This is the identical condition that held S1/S5/S6 on 2026-08-18.
**S1 cannot start until the September files are physically in `catalogs\`.** Note also that
`monthly-catalog-refresh.md` **Step 3** requires a *second, separate* download — the previous 1–2
**still-open months'** Lunar file(s), re-pulled for the revision sweep — which is easy to overlook
when gathering "the new month's files."

### 1.6 Two conflicts found while reading, flagged rather than resolved

**(a) `docs/native-customer-signup.md` says COMPLETE; its own completion criteria say otherwise.**
The `**STATUS:**` token reads `COMPLETE | staging=2026-07-23 | prod=2026-07-24 (PR #95)`. Four
boxes in its Completion Criteria are unticked, including:

- [ ] Prod write-smoke green … 24-hour soak elapsed and clean
- [ ] **MailerLite retired for founding: webhook path removed/dead, exposed secret rotated**
- [ ] Docs updated: `register-customer` contract in `technical-reference.md`; `CLAUDE.md`
- [ ] This plan's status → Complete; `CLAUDE.md` updated

**The second one is verifiable, and it is not done.** `supabase/functions/register-customer/index.ts`
still carries the full MailerLite webhook path — the `?secret=` branch (~line 199), the tenant
lookup against `tenants.settings->>'mailerlite_webhook_secret'` (~line 210), the webhook body parser
(~line 227), and a header comment (lines 4–12) saying the path is "retained harmlessly until
MailerLite is retired for the founding tenant (see native-customer-signup plan § S5)." So S5 has
not run.

This matters beyond bookkeeping: **F99's `p=quarantine` decision is triggered by "MailerLite
retirement (not a date)"** (`CLAUDE.md` open-findings table). An unfinished S5 is silently holding
an unrelated finding's gate closed. This is the same stale-status pattern F132 / F138 / F139 / F145
are all instances of. **Item C3 owns it.** Per `CLAUDE.md` § Definition of Done, a plan with
unticked completion boxes is not done — the token is what is wrong here, not the boxes.

**(b) The founding tenant's front door changed, and the tiering doc does not record it.**
`docs/apex-landing-tenant-subdomains.md` § Goal / § Strategic direction states the founding tenant
**stays on the apex**, that `rjbookstop.pulllist.app` is **deferred**, and that a branded subdomain
is the **premium tier** lever. Since then: the hostname was provisioned (date unrecovered, F145),
`native-customer-signup.md` S1 un-deferred it, and as of 2026-08-27 the print CTA puts
`rjbookstop.pulllist.app` **on paper handed to customers**. F145 corrected S4's "deferred" line at
filing, but nothing has revisited the *tiering* claim — the founding tenant is now sitting on the
premium front door and printing it. Not a defect; an unrecorded product-state change.
**Question for Rick, § 5 Q5.**

---

## 2. Strategic Assessment

### 2.1 The situation, stated plainly

Three things are simultaneously true:

1. **The migration program has no active phase**, and its declared successor (Phase 6) is gated on
   an infra spike nobody has run.
2. **There is a hard calendar event ~10 days out** (the September import) that is the only window in
   which the most customer-facing open finding can be closed.
3. **The commercially load-bearing next step is neither of those.** Per the
   `hybrid_frontdoor_premium_tiering` memory, Founding Partner pricing was decided 2026-08-19 — five
   free-year slots for new tenants, then $39-capped — and it is gated on **F72 + F99**, an email
   sender-identity problem, not on Phase 6 and not on the import.

So "what's next" has three plausible answers, and they are not variations of each other.

### 2.2 Shape A — open Phase 6 with the S0 spike

Run the wildcard-DNS/TLS spike, price wildcard-subdomain vs Cloudflare-for-SaaS, then open 6.1
(`tenants.status` + takedown tooling), 6.2 (public signup + eligibility gate), 6.3 (onboarding
wizard), 6.4 (abandoned-tenant sweep).

- **Gets:** the self-service roadmap unblocked; the "~6 minutes, no operator" promise becomes
  buildable; a real answer to a cost question currently guessed at.
- **Costs:** Phase 6 proper is the largest remaining body of work in the program — public signup,
  Turnstile, rate limiting, slug denylist/profanity filtering, a tenant lifecycle state machine,
  hostname reclamation, an abuse soak. It delivers value only when there is demand for tenants
  N+1, and **no such demand signal is recorded anywhere in the repo today** (two tenants, one a
  demo). Meanwhile the September window passes unused and F115 stays open another month.
- **Also:** Phase 6's eligibility gate has an **undecided verification method** (§ 4.5), which is a
  Rick scoping interview, not an executor task. Opening 6.2 without it means opening a sub-deploy
  whose central design question is unresolved.

**The spike itself, though, is cheap** — dashboard reading, DNS probes, published pricing, a written
answer. Half a day. There is no reason it must wait for the rest of Phase 6.

### 2.3 Shape B — consolidation: close what is open, half-built, and time-gated

F115 at the September window; F135's decoupling (which needs two *observed unattended Tuesday
cycles*, so it must start now to finish this month); the native-signup S5 that is silently gating
F99; F145's owed runbook record; the test-infra findings that currently make targeted spec runs
untrustworthy; and — folded in as a small, non-blocking item — the Phase 6 S0 spike, so its answer
exists when the next decision is taken.

- **Gets:** the September window *used* rather than missed. The finding register genuinely drained
  rather than perpetually pointer-tabled. The test suite trustworthy again — F133 variant (b)
  currently means a green targeted run proves nothing, which undercuts the measured, documented
  iteration workflow the project adopted on 2026-08-09. F99's gate unstuck. And the Phase 6 go/no-go
  input in hand.
- **Costs:** no new customer-facing product surface ships. Phase 6 stays closed another ~4 weeks.
  Some of it is unglamorous (a doc correction, a runbook line, a test-infra session).

### 2.4 Shape C — go-to-market: F72 + F99 email identity, then Founding Partner launch

Consolidate the sending identity onto `pulllist.app`, build per-tenant email branding, then open the
Founding Partner cohort.

- **Gets:** the business step Rick has already priced. Removes the last recorded blocker on a launch
  decision that is otherwise ready.
- **Costs:** highest blast radius of the three — two DNS providers, six Edge Function `from:` sites,
  DKIM/Return-Path provisioning, with the failure mode being *customers stop receiving magic links*.
  Both findings say explicitly they must be **designed together**, and F99 needs a scoping
  interview. Its own step-(2) prerequisite chain runs through the MailerLite retirement, which is
  item C3 of Shape B. **Shape C cannot cleanly start until part of Shape B has run.**

### 2.5 Recommendation — my reasoned opinion

**Take Shape B, and treat it as a bounded, named workstream rather than a phase.**

Three reasons, in order of weight:

1. **One item has a deadline and the others do not.** The September import is the only work in the
   picture that a decision to defer actually *destroys* — everything else is merely delayed. F115 is
   also the only open finding where the system tells a customer something untrue. Spending the next
   ten days on anything that does not clear the runway for that window is spending them badly.
2. **Shape C is downstream of Shape B whether we plan it that way or not.** F99's own recorded
   trigger is the MailerLite retirement. Doing C3 first is not deferring the go-to-market track; it
   is that track's first step, and it happens to be small.
3. **Shape A's expensive half has no demand pulling it, and its cheap half fits inside Shape B.** The
   S0 spike is a half-day investigation. Folding it in (C6) means the Phase-6-vs-Founding-Partner
   priority call in § 5 Q6 gets made **with the cost model in hand** rather than against the guess in
   the stub.

**What this explicitly defers, and why:**

| Deferred | Why |
|---|---|
| Phase 6 sub-deploys 6.1–6.4 | Gated on S0's answer (C6) *and* on the undecided eligibility-verification method. No demand signal recorded. |
| F72 + F99 **execution** | Blast radius; both findings require joint design. Their **scoping interview** is item C7 — that much is in scope. |
| F89 / F90 (analytics instrumentation) | Genuinely low; both want a schema + import-script session, which collides with the September import window by construction. |
| F126 residual (email editing) | Needs an Edge Function (F25). Rick's call to schedule; no forcing function. |
| `weekly-pipeline-consolidation-plan.md` | Much larger surface than F135, owned by Rick, three artifacts still outstanding. F135 is its sharp edge and is separately planned. |
| F141's unmeasured residual (`mylist`/`arrivals` CLS) | A measurement, not a fix. Cheap enough to add opportunistically; not worth a slot. |
| F131's structural fix (authed upload → EF → tenant-scoped write) | Volume question unanswered (~11,700 rows against Edge Function limits) and ~1,400 lines of hard-won normalizer logic to port. Its **interim, no-code mitigations** are item C8. |

---

## 3. Proposed Next Phase — Pre-Phase-6 Consolidation

### 3.1 Goal / what "done" looks like

**Every open item that is time-gated, half-built, or silently blocking another item is closed or
explicitly re-dispositioned — and the two decision inputs for what comes next (Phase 6 serving-model
cost; F72/F99 design scope) exist in writing.**

Concretely, at the end of this workstream:

- F115 is **RESOLVED**, not "mitigated" — the September import ran with the write live, and the
  production backfill is done.
- F135 is **RESOLVED** — the feed publish is triggered from the weekly send workflow, resolved from
  the database, and `resolveFeedWeek()` no longer exists.
- `docs/native-customer-signup.md` is genuinely complete, the MailerLite webhook path is retired, the
  exposed webhook secret is dead config, and F99's trigger has fired.
- The Playwright suite's date-dependent and shared-panel failures are fixed, so a **targeted run
  means something again**.
- `docs/phase-6-self-service-signup.md` § S0 carries a written, measured answer instead of a gating
  question.
- Rick has a scoped F72+F99 plan doc to say yes or no to.

### 3.2 Scope boundaries

**IN**
- F115 S1/S5/S6 (the September import).
- F135 S1–S5 (decouple the pull-feed publish).
- Native-signup S5 (retire MailerLite for founding) + its doc/token corrections.
- F145 fix item 3 (record the two live hostnames as durable infrastructure).
- F133 + F130 (one test-infra session, in that order).
- Phase 6 S0 spike — **investigation and a written answer only.**
- F72/F99 **scoping** — a plan doc, not an implementation.
- F131 interim mitigations (a)/(c) — documentation and framing, no code.

**OUT — stop and ask before touching (per `CLAUDE.md` § Anti-Drift Rules)**
- Any Phase 6 sub-deploy 6.1–6.4, any public `/signup` page, `tenants.status`, Turnstile work beyond
  what already exists.
- F72/F99 **implementation** — no Edge Function `from:` change, no DKIM/Return-Path provisioning, no
  `p=quarantine` publish.
- F89, F90, F126 residual, F141 residual measurement, `weekly-pipeline-consolidation-plan.md`.
- F131's structural fix.
- **Any change to admin ordering surfaces during the import window** — see § 4.1.
- `config.js`, on any branch, for any reason.

### 3.3 Work breakdown

Sizes are **my opinion**, calibrated against this repo's recent sessions (a "small" is a single
focused session; "large" spans multiple sessions or real elapsed calendar time).

---

#### C1 — F115: complete the arrival-truth persistence at the September import

**Delivers:** the September catalog import runs with the `arrival_outcome` write live, and the
production never-arrived set is backfilled — closing the one finding where the app tells a customer
something untrue.

- **Owner doc:** `docs/f115-arrival-truth-persistence.md` (§ 4 runbook S1/S5/S6, § 5 gates V1/V4/V5).
- **Touches:** `import.js` / `import-staging.js` **in the private scripts repo** (Step 9 — the write
  already shipped 2026-08-18, so S5 runs existing code); a new backfill file under `docs/sql/`;
  `docs/f115-arrival-truth-persistence.md` (§ 7 completion criteria + STATUS token);
  `docs/technical-reference.md` § 13 F115; `CLAUDE.md` § Current Migration Phase.
  **No `comic-preorder` application code changes.**
- **Gating:** hard-gated on the **~Sept 7–10 window** and on the September catalog files actually
  being present — that entry condition already held this work once (2026-08-18). **S1 gates S5:** if
  the dry run is not clean, F115 does not ship this cycle and the import proceeds without it. S6's
  production half is **PAUSE → Rick**.
- **Do first, before touching anything:** re-measure the production never-arrived set. The
  28 reservations / 23 titles figure was measured **2026-08-04** and the entry itself calls it an
  upper bound, not a confirmed failure count. Do not backfill against a four-week-old number.
- **Size:** **Large** — not in code volume (most shipped in August) but in consequence: the monthly
  import is the highest-stakes recurring operation in the system, and this cycle is also the first
  real new-month run for F110/F122/F123.

**✅ SUPERSEDED 2026-08-28 (evening) — C1 LARGELY EXECUTED. What follows replaces the runbook
detail above, which is retained only as the record of what was planned.**

Rick loaded the September files and ran both imports the same day. Outcome:

| Piece | State |
|---|---|
| **Staging** | **FULLY RESOLVED** — S1–S7 done, V1–V7 all green |
| **Production — S5 (the real import)** | **RAN.** Write confirmed live on real data: `arrived=212, unknown=6, not_arrived=0` — **V2's never-`not_arrived` invariant holds in production**, not just in unit tests |
| **Production — V1/V4** | **Not formally exercised.** Attention that day went to F147. V4's *substance* is confirmed (the counts above); the formal pass was not done |
| **Production — S6 backfill** | **NOT DONE.** The one remaining piece of F115 |
| **Two new findings** | **F147** filed + fully resolved same day (519 production marks cleared, independently re-verified). **F146** filed, fix shipped, **still open** pending a fresh-CSV re-pull |

**F115 remains OPEN overall** solely because production's S6 backfill has not landed.

**⚠️ And S6 needs a decision before it runs — its definition drifted between design and execution,
and on production the difference is 28 rows versus 859.**

**The drift, stated precisely:**

- **§ 3.5 of the owner doc (as designed)** scopes S6 to the *never-arrived subset*: "the 28
  reservations / 23 titles F115 measured get `arrival_outcome = 'unknown'`."
- **Staging's V5 (as executed)** used a different predicate — `fulfilled=true AND arrival_outcome
  IS NULL` — and set **all 32** to `'unknown'`. That is the *whole orphan population*, not the
  never-arrived subset.
- **The owner doc's production line now carries the executed predicate forward: "859 rows."**

**On staging the two predicates were nearly the same thing. On production they are not.**
Re-measured live 2026-08-28T23:55Z, read-only (22 GETs, 0 writes), post-import:

```
S6 orphan population (fulfilled=true, arrival_outcome IS NULL) : 859
  ├─ HAVE shipment evidence (they demonstrably arrived)        : 771
  └─ no shipment evidence                                      :  88
       ├─ outside the evidence window (absence = missing history) : 11
       └─ inside the window                                       : 77
            ├─ net-positive ledger (ordered; F116's case)         : 49
            ├─ recorded rejection (net <= 0)                      :  2
            └─ no ledger at all — genuinely unproven              : 26
```

**Backfilling all 859 to `'unknown'` would assert "judged, and the evidence does not settle it" on
771 rows where the evidence settles it completely.** That is ~90% of the set, and it is the same
category of false statement F115 exists to remove — merely pointed the other way. It would also
render `arrival_outcome` useless as a field for any future consumer.

*(Why staging didn't reveal this: staging's 32 orphans are small test data with little real shipment
history, so "whole population" and "never-arrived subset" nearly coincided there. Production has
975 real shipment rows. **This is the third time in this one workstream that staging's small dataset
hid a production-scale problem** — F147 was 16 on staging versus 519 on production, and CLAUDE.md's
print-catalog "measurement trap" note records the same shape a third time. Worth treating as a
standing rule, not three coincidences.)*

**Three options — Rick's call, § 5 Q11:**

| | What it writes | Assessment |
|---|---|---|
| **(a) § 3.5 as designed** | 28 → `unknown`; 831 stay NULL | Faithful to the design. Leaves 771 rows NULL that could correctly read `arrived` |
| **(b) Whole population** — what the doc now says | 859 → `unknown` | **Recommend against.** Writes an untrue judgement on 771 rows |
| **(c) Classify retroactively** | 771 → `arrived`, § 3.5's 28 → `unknown`, remaining 60 NULL | Tempting, and **initially recommended — withdrawn on review**, see below |

**DECISION (recommended 2026-08-28 evening): (a), narrowed to 26.** Write `arrival_outcome =
'unknown'` on the **26 genuinely-unproven rows only**. Everything else — including all 771 with
shipment evidence — **stays NULL**.

**I recommended (c) earlier in this session and am withdrawing it.** The reasoning that changed it:

1. **(c) does not serve F115's purpose.** The finding exists to make *never-arrived* cases visible
   to staff. The 771 that arrived were never the problem; marking them `arrived` is data tidiness,
   not the goal.
2. **NULL is inert and honest, not a gap.** `neverArrivedFromFulfilled()` deliberately excludes NULL
   — its own comment says "NULL means *not yet judged*, not *judged unknown*." Those 771 genuinely
   were never judged, because the write path did not exist when they were fulfilled. Leaving them
   NULL costs nothing: no surface reads them, and no consumer of the field exists today.
3. **(c) exceeds the approved scope.** Rick's 2026-08-18 decision was "the 28/23 already marked
   fulfilled get a one-time correction." (c) is a 30× larger write than that.
4. **It would rest 771 retroactive `arrived` assertions on what is effectively a single key.**
   Measured this session: `weekly_shipment` carries `upc` on 974/975 rows but `catalog_id` on only
   351 and `item_code` on 345 — so the "three-key" F76 match is UPC-only in practice. The *import*
   accepts that standard going forward, one cycle at a time, where a mistake is visible and
   correctable. Betting 771 historical rows on it in a single UPDATE, for no present benefit, is a
   different risk with the same evidence.
5. **The 2 recorded rejections stay NULL too** (Q10's principle, F143's rationale): the ledger
   already records the rejection and F120 already tells the customer. Writing `unknown` on top says
   *less* than what is already recorded, and `neverArrivedFromFulfilled()`'s `ledgerRejected()` exit
   filters them out either way.

**So: 26 rows, re-measured immediately before the write, ids captured first (§ 8 Rollback).** § 3.5's
own guard applies — if the fresh count lands outside 15–45, stop and ask rather than proceeding.

Under **(c)** the 60 left NULL are the honest residue: 49 ordered-but-no-shipment-record (**F116**'s
case, not a never-arrived) and 11 outside the evidence window (absence there is missing history, not
evidence). NULL correctly means "not yet judged" for both.

**Also folded in — the Q10 refinement:** of the 28, **2 are already-recorded rejections** and 26 are
genuinely unproven. Under any option, consider leaving those 2 NULL per F143's principle that the
ledger rejection and the arrival judgement are separate statements.

**Small, low-priority follow-on:** staging's V5 wrote `'unknown'` to all 32 orphans under predicate
(b). If any of those 32 had shipment evidence, staging's data carries the same overstatement. Test
data, so low stakes — worth a check when C5 is in that environment anyway, not a separate task.

**✅ DONE 2026-08-28/29 — C1 fully CLOSED.** Rick ran the Rick-gated production write via
`f115-s6-backfill-unknown.js` (same pattern as `clear-f147-withdrawn.js`): re-measured live
immediately before writing (859 orphans → 771 shipment-evidenced / 49 net-positive ledger / 2
recorded rejections, all left NULL → **26 reservations / 23 titles**, the genuinely-unproven set,
written to `'unknown'`), ids captured before the write, independently re-verified after with fresh
queries — orphan count 859→833 (exactly -26), `not_arrived` still 0 tenant-wide, 3 ids spot-checked.
**F115 is now RESOLVED on both environments.** Full detail: `docs/f115-arrival-truth-persistence.md`
§ 7 and `docs/technical-reference.md` § 13 F115.

#### C2 — F135: decouple the pull-feed publish from shipment import

**Delivers:** `import.js` stops publishing the newsletter; the weekly send workflow builds the feed
from the database immediately before sending, so an ad-hoc shipment import can never mail a stale
week again.

- **Owner doc:** `docs/f135-decouple-feed-publish.md` (§ 5 runbook S1–S5, § 6 gates V1–V5). Full
  runbook already written 2026-08-21; direction settled with Rick.
- **Touches:** private scripts repo (`import.js` — the publish block ~line 1931 and
  `resolveFeedWeek()` ~line 1510, plus its export and unit tests) and the
  `mrcyberrick/weekly-pull-feed` repo's send workflow. **No `comic-preorder` change.**
- **Gating and the sequencing collision — read this before scheduling:**
  - S3 and S5 each require **one observed unattended Tuesday cycle**, so the item spans ~2–3 calendar
    weeks and must **start now** to finish this month.
  - **C2 and C1 both edit `import.js`.** C2's **S4 (remove the publish + delete `resolveFeedWeek()`)
    must not land between C1's S1 dry run and C1's S5 live import.** Recommended split: **S1+S2+S3
    before** the import window; **S4+S5 after** it closes. An import that fails mid-window with two
    workstreams' edits in the same file is a diagnosis nobody wants.
  - Order within C2 is itself load-bearing: **the new trigger must be proven (S3) before the old one
    is removed (S4)**, or the failure mode flips from loud to silent.
- **Size:** **Medium** in effort, **Large** in elapsed time (calendar-bound).

---

#### C3 — Retire the MailerLite webhook path for founding (native-signup S5)

**Delivers:** the dead `?secret=` webhook branch removed or disabled, the exposed webhook secret
rotated to dead config, every doc surface corrected — and F99's stated trigger fired.

- **Owner doc:** `docs/native-customer-signup.md` § S5 + Completion Criteria (four unticked boxes,
  § 1.6(a) above).
- **Touches:** `supabase/functions/register-customer/index.ts` (the `?secret=` branch, tenant lookup,
  webhook body parser, and the header comment block at lines 4–12 — **re-read from disk; do not
  trust these line numbers**); `docs/technical-reference.md` § 11 Edge Function inventory and § 13
  F34/F72 notes; `CLAUDE.md` § Edge Functions; `docs/tenant-onboarding-runbook.md` **Step 4** (which
  currently instructs the operator to configure a MailerLite webhook for new tenants);
  `docs/native-customer-signup.md` (tick the boxes **or** correct the token — they must agree).
- **Gating:** none on the import window (does not touch admin ordering surfaces). **Blocks C7.**
- **Open question first — § 5 Q3:** remove the path entirely, or leave it present-but-dead? The plan
  doc says "removed/dead"; the function's own comment says "retained harmlessly." The mechanism is
  **per-tenant**, not founding-specific, so removing it removes it for `comicstore` and every future
  tenant too. That is a scope decision, not an executor judgement call.
- **Verify, don't assume:** confirm against live that the founding tenant's MailerLite webhook is
  genuinely dead before removing the receiving end, and establish whether the prod write-smoke box
  (also unticked) was in fact satisfied — PR #95's deploy log records S4 as "Complete 2026-07-24;
  soak in progress" and nothing recorded the soak closing.
- **Size:** **Small–Medium.** Edge Function deploy on both projects + doc sweep.

---

#### C4 — F145 item 3: record the tenant hostnames as durable infrastructure

**Delivers:** `rjbookstop.pulllist.app` and `comicstore.pulllist.app` recorded as individually
provisioned Cloudflare Pages custom hostnames, with an explicit note that the first appears on
**printed customer material** and must not be retired without reprinting.

- **Owner doc:** `docs/technical-reference.md` § 13 F145 fix item 3 (items 1, 2 and 4 are already
  done or explicitly no-action).
- **Touches:** `docs/tenant-onboarding-runbook.md` (Step 3 already documents *how* to provision one;
  what is missing is an inventory of which exist); `docs/technical-reference.md` § 13 F145 (tick item
  3). Optionally `docs/apex-landing-tenant-subdomains.md` § Strategic direction, if Rick answers § 5
  Q5.
- **Gating:** **needs Rick's Cloudflare-side inventory** — F145 deliberately left this open rather
  than infer an infrastructure record from two `curl` results, and that reasoning still holds.
- **Size:** **Small** (doc-only, one commit to `staging`).

---

#### C5 — Test-infrastructure session: F133 then F130, in that order

**Delivers:** date-dependent specs that no longer flip on the calendar, panel assertions scoped to
their own seeded rows, and a classified — not bulk-deleted — auth-user orphan set.

- **Owner findings:** `docs/technical-reference.md` § 13 **F133** and **F130**. Natural template:
  `docs/test-infra-maintenance-f91-f95-f103.md`.
- **Touches:** the **local-only, never-committed** Playwright suite at
  `catalogs\scripts\playwright\` — `tests/15-order-export-ledger.spec.ts` (`focThisMonthFuture()` and
  its three callers), `tests/06-admin-this-week-bagging.spec.ts`,
  `tests/21-arrival-resolution.spec.ts:136`, `fixtures/auth.ts` (`deleteUser`). **No repo file
  changes**, other than updating the two findings entries in `docs/technical-reference.md` § 13.
- **F133 has two variants and a fix for one does not touch the other:**
  - **(a)** a fixture FOC crossing *past* a live `order_deadline` — closed by making
    `focThisMonthFuture()` deadline-aware.
  - **(b)** a *lapsed* deadline re-admitting **real** catalog rows into `#backorder-risk-panel` —
    needs assertions scoped to the seeded row, not `toContainText` against the whole panel. This
    variant also exposes an **undeclared spec-order dependency**: spec 21 passes in the full suite
    only because spec 15 ran first and left the state it needs. Until (b) is fixed, **a green
    targeted run is not evidence.**
- **F130's recorded fix plan is invalid as stated** — do not follow it. Date-bucketing against F95's
  2026-08-02 fix cannot distinguish an *intended* `pw-pending-*` decline survivor (F64 item 5 Option
  A) from a teardown miss. **Classify by originating spec/prefix first**, fix the teardown paths that
  skip the auth call, and only then delete what remains. The auth DELETE itself was measured working
  2026-08-24 (6/6, 0 remained) — these are deletes never *attempted*, not deletes that failed.
- **Gating:** none.
- **⚠️ Corrected 2026-08-28 — this item does NOT gate C1, and the original plan implied otherwise.**
  § 3.4 first sequenced C5 ahead of C1 "so the September session has a suite it can trust." That
  overstated the dependency. **F115's three remaining gates are all import-side** — V1 (dry run), V4
  (spot-check the persisted column against the printed report), V5 (re-measured backfill). The two
  Playwright gates, **V3 and V7, already ran green on 2026-08-18** and are ticked in the owner doc's
  § 7. The Playwright suite is therefore *not* a gate for C1, and with the window open early, **C1
  goes first.** C5 moves to after the import — where it is also cheaper, because the Order Deadline
  gets reset at refresh Step 7, which changes the ambient value F133 variant (a) trips over.
- **Size:** **Medium.**

---

#### C6 — Phase 6 S0: wildcard DNS + TLS serving-model spike

**Delivers:** a written, measured answer to the question gating all of Phase 6 — can a freshly-claimed
slug serve at `<slug>.pulllist.app` instantly with zero per-tenant DNS work, and what does each
serving model cost?

- **Owner doc:** `docs/phase-6-self-service-signup.md` § "Gating prerequisite (Phase 6 S0)".
- **What to establish** (the stub already frames the two models; this item measures them):
  1. Whether a `*.pulllist.app` wildcard DNS record + wildcard TLS cert can terminate at the
     Cloudflare **Pages** project as currently configured — *tested*, not read off a docs page.
  2. If not, what does: Cloudflare for SaaS / Custom Hostnames (<100 free, ~$0.10/hostname after), a
     Worker in front, or per-tenant Pages custom domains (**the model actually in force today** —
     F145 measured exactly this: `foo.pulllist.app` and `zzz-does-not-exist-9182.pulllist.app` both
     return **NXDOMAIN**).
  3. The cost curve for each under abuse, and whether hostname provisioning can be deferred to tenant
     *activation* and reclaimed by the abandoned-tenant sweep via API.
- **Touches:** `docs/phase-6-self-service-signup.md` (§ S0 gains a Findings/Answer subsection);
  possibly a new finding if the measurement contradicts something recorded. **No code.**
- **Gating:** none. Deliberately placed **late or in parallel** — its output is a *decision input* for
  § 5 Q6, not a dependency of any other item here.
- **Verification discipline:** F145's lesson applies directly — **probe a hostname nobody
  provisioned.** Checking a known-good hostname confirms nothing about a wildcard.
- **Size:** **Small** (half a day: dashboard + DNS probes + published pricing).

---

#### C7 — F72 + F99 joint scoping interview → plan doc

**Delivers:** `docs/email-sender-consolidation-f72-f99.md` — a scoped plan Rick can approve or reject,
covering the sender-identity consolidation and per-tenant email branding **together**.

- **Owner findings:** § 13 **F99** (fix direction steps 1–5; step 1 done 2026-07-25; the DMARC gate
  was **read 2026-08-20** — 13 messages, 100% pass, 3 senders, all known — so step 2's prerequisite is
  satisfied) and **F72**.
- **Touches:** creates one new doc. Records the flat-`noreply@pulllist.app`-vs-per-tenant-subdomain
  decision (F99 recommends per-tenant; Brevo already sends from `rjbookstop.pulllist.app`), the six
  Edge Function `from:` sites, the MailerSend DKIM/Return-Path provisioning that must happen **in
  Cloudflare**, and the `p=quarantine` publish decision (currently **held**, trigger = MailerLite
  retirement).
- **Gating:** **blocked on C3.** Also needs Rick — both findings say so explicitly ("design together
  with F72 — needs a scoping interview").
- **Explicitly not in scope here:** implementing any of it.
- **Size:** **Small** as a session; the work it scopes is Large.

---

#### C8 — F131 interim mitigations (no code)

**Delivers:** the catalog-import continuity risk reduced from "one person, undocumented" to "one
person, documented and recoverable."

- **Owner finding:** § 13 **F131**, interim mitigations (a)/(b)/(c).
- **(a) is mostly already done** — `docs/monthly-catalog-refresh.md` is current (updated 2026-08-22
  with F136's Step 3 revision sweep) and is a genuine end-to-end runbook. The gap is that it assumes
  the operator already holds credentials and portal access. Add a "what a second operator needs"
  preamble.
- **(b) is Rick-only** — `.env` contents and Lunar/PRH portal access being recoverable by someone
  other than the operator. An agent cannot do this and should not pretend to.
- **(c)** — frame operator-run import to Founding Partner tenants as an explicit, time-boxed cohort
  perk rather than a standing service, so the expectation matches the roadmap. Belongs wherever the
  Founding Partner offer is written down.
- **Touches:** `docs/monthly-catalog-refresh.md`, `docs/technical-reference.md` § 13 F131.
- **Gating:** none. Naturally pairs with C1 (same subject matter, same week).
- **Size:** **Small.**

### 3.4 Suggested sequence

**⚠️ REVISED TWICE 2026-08-28. The import has now RUN — the admin-ordering freeze is LIFTED.**
C1 is down to one Rick-gated production UPDATE (§ 3.3 C1). Everything previously queued behind the
freeze is unblocked, including **C2's S4** and **C5**. Revised ordering:

```
NOW
 ├── C1 — DONE 2026-08-28/29 (§ 5 Q11 decided: option (a) narrowed to 26; Rick ran the write)
 ├── F146 close-out — fresh Lunar CSV re-pull + re-import to verify the clear fires
 │      (NEW, not in the original eight; owner § 13 F146)
 ├── C5  test-infra — now unblocked, and order_deadline was just reset by the import,
 │      which is the ambient value F133 variant (a) needs
 ├── C2  S1+S2+S3, then S4+S5   (S4 no longer blocked — C1 no longer edits import.js)
 ├── C3  small; unblocks C7
 ├── C4, C8  doc-only
 ├── C6  read-only probes
 └── C7  after C3
```

~~Superseded ordering (freeze live, C1 first):~~
The original ordering (below, struck) assumed ~Sept 7–10 and put the cheap items ahead of the
anchor. With the window here, the anchor goes first and everything else fills in behind it.

```
NOW ─────────────────────────── import complete ──────────────── after
 ┌───────────────────────────┐
 │  C1 — F115 S1/S5/S6       │   ← ADMIN ORDERING FREEZE IS LIVE
 │  (interleaved with the    │      nothing else touches admin.html
 │   monthly refresh, C1's   │      Ordering mode until this closes
 │   table above)            │
 └─────────────┬─────────────┘
               │   safe to run in parallel — none of these
               │   touch admin ordering surfaces or import.js:
               ├── C4  doc-only, needs Rick's CF inventory
               ├── C8  doc-only (pairs naturally with C1 — same week,
               │        gaps are most visible while importing)
               ├── C6  read-only probes, no dependency
               └── C3  small; unblocks C7
                             │
                             └──► C5  test-infra (now AFTER the import —
                             │        also cheaper post-Step-7 deadline reset)
                             ├──► C2  S1+S2+S3, then S4+S5
                             │        ⚠️ S4 edits import.js — must not land
                             │        until C1 is fully closed out
                             └──► C7  after C3
```

~~Original ordering: C5 → C3 → C2 S1-S3 → [import window: C1] → C2 S4-S5.~~ Superseded; the
premise (a ~10-day runway before the window) no longer holds.

**The one rule that does not move:** C2's S4 removes the publish block from `import.js`. It must not
land until C1 is fully closed out, or an import failure has two candidate causes.

### 3.5 Completion criteria

- [x] **C1 — DONE 2026-08-28/29.** § 13 F115 status reads **RESOLVED**, both environments; V1/V4/V5
      green; `docs/f115-arrival-truth-persistence.md` STATUS token → COMPLETE with dates; production
      backfill run against a **freshly re-measured** set (26 reservations / 23 titles, narrowed from
      859 orphans per the DECISION above), with Rick's explicit approval recorded (he ran the write
      himself, `y/n` confirmation in the script's own transcript).
- [ ] **C2:** F135 V1–V5 green, including **one unattended Tuesday cycle** read from the
      **campaign's observed status**, not from a green Actions run; `resolveFeedWeek()` gone from
      `import.js` and from its unit tests; exactly **one** Pages deployer remains (F100).
- [ ] **C3:** `register-customer` no longer accepts the MailerLite webhook path (or accepts it only
      as explicitly-dead code, per Rick's Q3 answer); webhook secret rotated to dead config;
      `docs/native-customer-signup.md` token and checkboxes **agree**; § 11 / § 13 / `CLAUDE.md` /
      `tenant-onboarding-runbook.md` Step 4 all updated.
- [ ] **C4:** both live hostnames recorded in `docs/tenant-onboarding-runbook.md` with the
      printed-material caveat; § 13 F145 item 3 ticked.
- [ ] **C5:** full `run-smoke.ps1` green **and** each previously-affected spec green in a **targeted**
      run (that is the assertion that proves variant (b) is fixed); F130 orphans classified by
      originating prefix, teardown gaps fixed, remainder dispositioned.
- [ ] **C6:** `docs/phase-6-self-service-signup.md` § S0 carries a measured answer and a cost model;
      the answer was reached by probing an **unprovisioned** hostname, not a known-good one.
- [ ] **C7:** `docs/email-sender-consolidation-f72-f99.md` committed to `staging`, covering both
      findings jointly, with the sender-shape decision recorded.
- [ ] **C8:** second-operator preamble in `docs/monthly-catalog-refresh.md`; § 13 F131 interim
      mitigations updated with what was and was not done.
- [ ] `CLAUDE.md` § Current Migration Phase updated: last-completed-work block, open-findings pointer
      table, next-free-finding-ID pointer.
- [ ] This plan's STATUS token advanced with dates.
- [ ] Every doc touched has a `**STATUS:**` token that matches its own completion boxes — the
      § 1.6(a) defect is not re-introduced anywhere.

---

## 4. Risks & Dependencies

### 4.1 The September import window (~Sept 7–10) — the binding constraint

`CLAUDE.md` § Current Migration Phase: whatever lands next on **admin ordering surfaces** must land
**and promote** before the window opens, or wait until after it closes. Two sessions must not touch
admin ordering surfaces across an import.

- **In practice, for this workstream:** C1 is the only item that may touch import behaviour during
  the window. **C2's S4 is the specific hazard** — it edits the same file (`import.js`) as C1's
  steps, and landing it mid-window means an import failure has two candidate causes.
- **Admin ordering surfaces** = `admin.html`'s Ordering mode: Order Builder, Order Follow-Up, By
  Distributor, the backorder-risk panel, the paper-orders prints. Nothing in C2–C8 touches them,
  which is why they are safe to run alongside. **Verify that claim per item rather than trusting this
  sentence.**
- If the September files arrive late, C1 slips a month by construction. That is the risk § 3.4's
  ordering is designed to absorb: everything else finishes regardless.

### 4.2 `config.js` promotion rule

`config.js` is **tracked per branch with different values on each branch** — production `main` holds
the prod anon key, `staging` holds the staging anon key. The promotion flow uses
`git checkout main -- config.js` during the staging→main merge, and **`config.js` must not appear in
any promotion PR's diff.** The agent never edits it and never proposes credential values. A committed
anon key is not a finding — RLS is the security boundary, not key secrecy.

Only C3 in this workstream is likely to reach production at all (an Edge Function deploy plus doc
changes), and Edge Functions deploy outside the branch flow — but the rule holds for any promotion.

### 4.3 The F125 promotion-branch trap

`main` is **not** "staging + prod `config.js`": `supabase/migrations/` (two files, 438 lines) exists
only on `main`. Any promotion that rebuilds `main`'s tree *from* `staging` — a squash, a rebase, a
`git checkout staging -- .`, a `git reset --hard staging`, **or a promotion branch accidentally cut
from ambient HEAD while HEAD is on `staging`** — silently deletes them **and** overwrites `config.js`
with the staging anon key. That fifth trigger was hit for real on 2026-08-24 and caught one step
before the merge button; per-file spot checks all *passed*. **The check that works is
`git diff --stat origin/main <branch>`** against the remote base. Create promotion branches from an
explicit ref: `git checkout -B <branch> origin/main`.

### 4.4 Dormant-HIGH findings that activate with a second tenant

**Stated honestly: the original dormant-HIGH set is closed.** `docs/technical-reference.md` § 13's
header names **F4, F15, F16, F20, F34** as the four HIGH plus one dormant-HIGH that "activate when a
second tenant onboards" — **all five are resolved on both environments**, and a second tenant
(`comicstore`) has been live on production since 2026-07-15 without them firing. That header is
Phase-4-era text and should not be read as a live risk list. *(Worth an editorial pass at some point;
not filed as a finding here — it is accurate about history, only misleading about the present.)*

**What genuinely activates with tenant N+1 today is a different, shorter list:**

| ID | What activates |
|---|---|
| **F72** | A self-serve or real-customer tenant's `register-customer` emails arrive **founding-branded**. Already flagged in `docs/tenant-onboarding-runbook.md` as a tenant-2 **real-customer go-live prerequisite** — and `comicstore` has stayed pilot/seeded precisely so it has not fired. |
| **F131** | Every tenant's catalog is sourced from **one shop's** Lunar/PRH portal access, and the import is one operator on one machine with a service-role key that cannot be distributed. Invisible at one paying tenant; at five it is the product. Includes an unanswered terms-of-use question about populating other retailers' systems from one retailer account's download — **flagged, not researched, not claimed**. |
| **F145** | Each tenant subdomain is an **individually provisioned** Cloudflare Pages custom hostname. Fine at two; it is not self-service, and it is why Phase 6 S0 is still a real gate. |

### 4.5 The Phase 6 eligibility gate is undecided

The stub records the eligibility requirement (a PRH **or** Lunar retailer account) as settled, and the
**verification method as an open question** with three options — self-attestation (lowest friction,
weakest), manual operator review (strongest, reintroduces a human, contradicts "6-minute
self-serve"), and automated verification (ideal but "likely infeasible — no known public
retailer-verification API; confirm during Phase 6"). The stub's own recommended hybrid — instant
signup → email verify → branded trial site, with **going-live and first catalog import gated on
eligibility** — is a recommendation, not a decision.

**Consequence for planning:** Phase 6 sub-deploy 6.2 cannot be written until this is answered, and
answering it is a Rick scoping call. It is **not** a blocker for C6, which only measures serving
model and cost.

### 4.6 Other things that could bite

- **F133 variant (b) means a green targeted run is not evidence.** Until C5 lands, any executor using
  the documented "targeted while iterating, full suite as the gate" workflow may be reading a pass
  that only holds because of spec ordering. **This directly undercuts the iteration workflow** the
  project adopted after measuring it on 2026-08-09.
- **Green ≠ verified, structurally.** The suite covers only what has specs. Two production defect
  clusters shipped through green suites in July/August because the paths had no coverage at all. For
  anything new, the cheap high-yield check is probing the deployed thing and reading what comes back.
- **The smoke suite tests the *deployed* site.** A pre-push `run-smoke.ps1` exercises the **previous**
  build for any `app.js`/`*.html`/`style.css` change. Push, confirm the new bytes are served at the
  **plain URL** (a cache-busted query string is a different Cloudflare cache key), then run the suite.
- **A verification step that cannot fail is not a verification step.** Before asking Rick to run any
  check, state what its output looks like when the thing has **failed**.
- **`.ps1` BOM stripping.** Any agent edit to a PowerShell script must restore the UTF-8 BOM, or
  PowerShell 5.1 silently swallows later code into string literals with no parse error —
  `run-smoke.ps1` skipped its entire Playwright stage and exited 0 this way on 2026-07-16.
- **F91 / F107 auth noise.** GoTrue intermittently rejects `sb_secret_` keys and rate-limits magic
  links on repeated full runs. Expect flaky-looking auth failures that are neither the code nor the
  test.
- **`docs/interim-deployment-work-instructions.md` is stale by its own terms** — written 2026-06-11 as
  a bridge "until post-5.5," and 5.5 closed 2026-07-15. It says `CLAUDE.md` wins on any disagreement,
  so it is not dangerous, but it is a NOT-COMPLETE doc that will surface in every status sweep. Worth
  a disposition (retire, or re-token as COMPLETE) — **not scoped here**; raised for Rick.
- **The GH Pages legacy rollback surface** (`mrcyberrick.us/comic-preorder/`) is still warm past its
  original "until 5.5 closes" gate. Phase 5's completion criteria flagged that no explicit retirement
  disposition exists and deliberately did not retire it unilaterally. Still true. § 5 Q8.

---

## 5. Open Questions for Rick

Marked **[BLOCKING]** where an executor cannot proceed on that item without an answer.

1. ~~**[BLOCKING for C1]** Is the September import still expected in the **~Sept 7–10** window…~~
   **✅ ANSWERED 2026-08-28 — Rick: the window is here now and he is prepared to load a new month.**
   § 1.5, § 3.3 C1, § 3.4 and § 3.3 C5 all revised accordingly; C1 is the active item and the
   admin-ordering freeze is live. **One open sub-item remains:** as of the 2026-08-28 check the
   September files were **not yet in `catalogs\`** (newest are the 2026-08 pair, dated Aug 21), and
   Step 3's revision sweep needs a *separate* re-download of the still-open months' Lunar file(s).
   Confirm both sets are in hand before S1 starts.

2. **[PARTLY ANSWERED — data now in hand; the decision is still yours]** The re-measure is done
   (2026-08-28, read-only, § 3.3 C1's baseline block): **28 reservations across 25 titles**, with the
   full title list captured. The reservation count matches August's but **the membership has
   churned**, so it must still be re-captured at S6 rather than reused from this run. Two things to
   confirm: (i) do you want to eyeball the 25-title list before the UPDATE runs, and (ii) do you
   agree the backfill filters `arrival_outcome IS NULL` so it can never overwrite a judgement you
   already recorded through F134's resolve controls? *(Finding (a) in that block: production is
   **not** "column but no write" as this plan first assumed — 111 rows already read `arrived` and 2
   read `unknown`, written by those controls since 2026-08-21.)*

3. **[BLOCKING for C3]** For the MailerLite webhook path in `register-customer`: **remove it entirely,
   or leave it present-but-dead?** The plan doc says "removed/dead"; the function's own comment says
   "retained harmlessly." It is a **per-tenant** mechanism, so removing it removes it for `comicstore`
   and every future tenant — and `tenant-onboarding-runbook.md` Step 4 still tells an operator to
   configure it. Related: was PR #95's **prod write-smoke + 24-hour soak** actually completed? Its box
   is unticked and the deploy log stops at "soak in progress."

4. **[BLOCKING for C4]** Can you confirm the Cloudflare custom-hostname inventory for the
   `pulllist.app` Pages project — which hostnames exist, and (if the audit log still has it) when
   `rjbookstop.pulllist.app` was provisioned? F145 deliberately left this for your confirmation rather
   than infer infrastructure state from two `curl` results.

5. **Which is the founding tenant's canonical front door now — the apex, or
   `rjbookstop.pulllist.app`?** `apex-landing-tenant-subdomains.md` says founding stays on the apex and
   a branded subdomain is the **premium tier** lever. Since then the hostname was provisioned, native
   signup shipped on it, and the print CTA now puts it on **paper handed to customers**. The tiering
   doc has not been revisited. This is a product-positioning answer, not a technical one.

6. **Priority after this workstream: Phase 6, or the Founding Partner launch (F72+F99)?** They are
   independent tracks and both read as "next." Phase 6 has no recorded demand signal (two tenants, one
   a demo); the Founding Partner offer is priced and waiting on an email-identity fix. C6 is designed
   to put the Phase 6 cost model in your hands before you answer.

7. **F135's two observation cycles take 2–3 calendar weeks** (S3 and S5 each need one unattended
   Tuesday). Is that acceptable, or would you rather the interim `.env` mitigation stand indefinitely
   and F135 be deferred? The mitigation works, but it depends on a human remembering to comment out a
   variable before every ad-hoc import.

8. **The legacy GitHub Pages rollback surface** — retire it, or keep it warm? Open since 5.5 S6
   (2026-07-15), where your call was "keep warm and revisit in a future session, not tied to a phase
   boundary." This is that future session asking.

9. ~~**[TIME-SENSITIVE]** Four reservations will be stamped `unknown`…~~ **✅ ANSWERED 2026-08-28 by
   Rick, and verified against the ledger: all four were ALREADY recorded as rejected.** Each carries
   a `monthly` order plus a same-magnitude negative `adjustment` dated 2026-08-13, netting to exactly
   0 → `get_ordered_codes()` state `unavailable`. **Nothing is owed before the import; it can run
   as-is.** What this surfaced instead is item 10.

10. **[NEW 2026-08-28 — a judgement call, NOT a blocker; the import runs fine either way]**
    `classifyArrivalOutcomes()` in `import.js` is the **only** arrival-related consumer that does not
    consult the order ledger. Three read surfaces each learned to — `computeBackorderRisk()`'s
    `ledgerRejected()` exit (F129), the Held Back panel (F142), and `neverArrivedFromFulfilled()`'s
    own `ledgerRejected()` exit (F134 Part 1) — but the **writer** never did. So the import will
    stamp `arrival_outcome = 'unknown'` on rows the store has already decided were rejected.
    **Impact today is nil and this was verified, not assumed:** all three surfaces filter on the
    ledger, which is the stronger source, so no row re-appears as a nag and nothing false is asserted
    about arrival (`'unknown'` ≠ `'arrived'`). It is a redundant, slightly-weaker record, not a
    contradiction. Two separate decisions:
    - **(a) S6 backfill — free to get right, no code, decide this cycle.** Of the 28 rows, **26 are
      genuinely unproven (no ledger rows at all) and 2 are recorded rejections** (`Power Rangers
      Green #1 I 1:25 INCV`, `Power Rangers Unlimited #2 G 1:25 INCV` — both PRH, both net 0).
      **Recommend backfilling 26, leaving those 2 NULL**, matching F143's stated principle that the
      ledger rejection and the arrival judgement are different statements. It is a hand-run UPDATE
      you control, so accuracy costs nothing.
    - **(b) The import writer itself — do NOT touch it now.** Changing `classifyArrivalOutcomes()`
      is a scripts-repo code change during the import window, on the single highest-consequence
      recurring operation in the system, to fix something no surface displays. File it (F146 is free)
      or ignore it — but after the import, not during. This is the § Anti-Drift "stop and ask, don't
      fix inline" case.

11. **[NEW 2026-08-28 evening — BLOCKING for the S6 backfill, the last piece of F115]**
    **Which S6 predicate?** Its definition drifted between § 3.5 (never-arrived subset) and what
    staging actually executed (whole orphan population), and on production that is **28 rows versus
    859**. Backfilling all 859 to `'unknown'` writes an untrue judgement onto the **771** that have
    shipment evidence. **RECOMMENDATION MADE — see § 3.3 C1: option (a), narrowed to 26 rows.**
    Write `unknown` on the 26 genuinely-unproven rows only; everything else stays NULL, including
    the 771 evidenced ones and the 2 already-recorded rejections. *(I recommended the broader
    "classify retroactively" option earlier in this session and withdrew it — full reasoning in
    C1.)* **Still yours to approve, because it is a production write.** *Related, low priority:*
    staging's V5 used the wide predicate too — worth a spot check when C5 is in that environment.

12. **[NEW 2026-08-28 evening]** **F146 is open and needs an operational step, not code.** The fix
    shipped (scripts repo `415bb38`) but cannot be verified with the CSV already used for the
    import — it needs a **fresh Lunar re-pull** followed by a re-import, on staging first. The 16
    staging marks are still set. **RECOMMENDATION: staging, on any day from 2026-08-29 onward —
    practically, tomorrow.** Reasoning and method:
    - **It can only be done on staging.** Production currently holds **zero** withdrawn marks
      (measured live 2026-08-28: `withdrawn_at NOT NULL` = 0, after F147's 519 were cleared), so the
      clear path has nothing to act on there. Production's next real opportunity is **October's
      new-month import**, when the mark half runs again with F147's FOC fix in place.
    - **The export refreshes nightly**, so any pull at least one day after the one already imported
      is a genuinely different snapshot. No need to wait longer than that.
    - **Named positive control — this is what makes it a check that can fail.** F146 confirmed
      `0826AB0593` (DAREDEVIL MY MIGHTY MARVEL FIRST BOOK HC) live on the distributor's site *while
      marked withdrawn*. So: **in the fresh CSV and its mark clears → fix verified. In the CSV and
      it does not clear → fix is broken. Not in the CSV → the export had not refreshed; nothing was
      learned, pull again later.** Do not read "0 cleared" as success without checking which branch
      you are in.
    - **Method:** `--no-write` dry run first, then the real run with **`--skip-autoreserve`**.
      Verified in `import-staging.js`: `skipAutoReserve = skipAutoReserveFlag || isOlderMonth`, and a
      *same-month* refresh is neither new- nor older-month, so auto-reserve would otherwise run. It
      is safe (it skips existing reservations) but there is no reason to have it inside a
      withdrawal-clearing verification.
    - **No deadline pressure** — staging-only, independent of every other item. Sooner is better
      only because 16 false positives are sitting there.

---

## 6. Suggested Next Steps

Concrete, and none of them need an answer to § 5 first.

1. **Commit this document to `staging`, doc-only.** `CLAUDE.md` § Document Integrity: planning
   artifacts are committed on creation, before the next session begins — an uncommitted planning doc
   is a known drift source and is treated as not-yet-real.
2. **Run `/preflight`.** It cross-checks every `docs/*.md` STATUS token and `docs/sql/*.sql`
   `-- STATUS:` line against git. It should independently surface the § 1.6(a) conflict; if it does
   not, that is worth knowing about `/preflight` too.
3. **Re-measure the F115 production set now, read-only** (service-role, no writes) — past-on-sale
   reservations marked `fulfilled` with no `weekly_shipment` row and no `order_submissions` row,
   restricted to the window where shipment data actually exists. Gives C1 S6 a current number weeks
   before it is needed, and costs nothing.
4. **Reproduce F133 variant (b)** — run `21-arrival-resolution` targeted, then in the full suite, and
   confirm the pass/fail disagreement still holds. That disagreement *is* the finding; confirming it
   still reproduces is the first step of C5.
5. **Draft the C3 change** against `supabase/functions/register-customer/index.ts` (read from disk, not
   from this doc's line numbers) plus the doc-token correction in `docs/native-customer-signup.md` —
   ready to apply the moment Q3 is answered.
6. **Do C6's probes** — read-only, need nobody's approval, and they turn a gating question into a
   written answer. Probe a hostname nobody provisioned.
7. **Add the second-operator preamble to `docs/monthly-catalog-refresh.md`** (C8 part (a)) while the
   September import is fresh in mind — it is the one week of the month when the gaps are obvious.

---

## References

- `CLAUDE.md` — § Current Migration Phase (the F115 window rule, the open-findings pointer table),
  § Standard Deployment Workflow, § Credential Safety, § Anti-Drift Rules, § Smoke Test Suite.
- `docs/technical-reference.md` — canonical schema; **§ 13 is the only record of finding detail**
  (last verified against live **2026-08-18**; § 4 / § 6 / § 7 / § 8 catalog reads were run directly in
  the Supabase SQL Editor on both projects that day, closing F92).
- `docs/phase-5-second-tenant-onboarding.md` — predecessor, COMPLETE 2026-07-15.
- `docs/phase-6-self-service-signup.md` — successor STUB; § S0 is what C6 answers.
- `docs/f115-arrival-truth-persistence.md` — C1's runbook (§ 4 S1/S5/S6, § 5 gates).
- `docs/f135-decouple-feed-publish.md` — C2's runbook (§ 3 interim mitigation, § 5 S1–S5, § 6 gates).
- `docs/native-customer-signup.md` — C3's owner (§ S5 + Completion Criteria).
- `docs/tenant-onboarding-runbook.md` — C4's target (Step 3 hostnames, Step 4 MailerLite).
- `docs/monthly-catalog-refresh.md` — C8's target; current as of 2026-08-22.
- `docs/test-infra-maintenance-f91-f95-f103.md` — the template for C5.
- `docs/phase-5.0-pre-phase-5-housekeeping.md` — the precedent for this workstream's shape.

---

**Last updated:** 2026-08-28 — revised three times the same day, the last after execution
overtook the plan. (3) Rick loaded the September files and ran both imports: **staging F115 fully
resolved, production's real import ran, two new findings (F146 open, F147 filed+resolved) came out
of it.** C1 is now ~90% done and its remaining piece is one Rick-gated UPDATE; the admin-ordering
freeze is **lifted**; § 3.4 re-sequenced; **§ 5 Q11 added — S6's predicate drifted between design
and execution and on production that is 28 rows vs 859**, re-measured live read-only; Q12 added for
F146's outstanding verification; next free finding ID corrected to **F148**. (2) Added the
pre-import production baseline and Q9/Q10. (1) Revised for the window opening early.
