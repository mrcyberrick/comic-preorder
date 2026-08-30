# Pre-Phase-6 Consolidation — Wave 2 (post-September-import)

**STATUS:** APPROVED (scope trimmed) 2026-08-29 | staging=— | prod=— | findings=F133,F130,F145,F131,F72,F99,F141

**Status:** **Approved with a trimmed scope, 2026-08-29.** Rick answered all eight § 5 questions the
same day; see **§ 0** — the direction changed materially and **§ 2.6's recommendation is
superseded.** Written 2026-08-29 by a planning pass. Successor to
`docs/pre-phase-6-consolidation.md` (PROPOSED 2026-08-28, never formally approved, **C1 and the
F146 close-out both now DONE**). This document re-derives the remaining work against live repo and
branch state, not against that plan's narrative, and re-sequences it around the two things that
changed since it was written: the September import **ran** (both environments), and F146's staging
verification **closed** (2026-08-29).
**Predecessor:** `docs/pre-phase-6-consolidation.md` — items C1 ✅ and the F146 close-out ✅ are
retired from this plan; C2–C8 carry forward, renumbered W3–W10.
**Successor:** Phase 6 (`docs/phase-6-self-service-signup.md`, STUB) **or** the Founding Partner
go-to-market track — **that choice is Rick's and is § 5 Q3 below.** This plan produces the cost
input (W8) but does not make the call.
**Branch base:** `staging` throughout. Production promotions per `CLAUDE.md` § Standard Deployment
Workflow only where an item explicitly says so.
**Next free finding ID:** **F148.**

---

## 0. Decisions — Rick, 2026-08-29

All eight § 5 questions answered the same day the plan was written. **These override § 2.6.**

| # | Question | Rick's answer | Effect on this plan |
|---|---|---|---|
| Q1 | MailerLite webhook path — remove or leave dead? | **Remove it** | **W5 unblocked**, full removal (not present-but-dead). Removes it for `comicstore` and every future tenant → onboarding-runbook Step 4 and its Step 7 checklist line must go too |
| Q2 | Is production open to customers? | **Yes, prod is serving customers** | **W1 collapses to a doc correction** (done 2026-08-29). One sub-item survives: whether **Step 7** (`order_deadline`) was run is still unconfirmed — see W1 |
| Q3 | Phase 6, Founding Partner, or keep shipping small features? | **Small features for now** | **The big one. Shape D is chosen.** W8 (Phase 6 S0 spike) and W10 (F72+F99 scoping) are **deferred** — their whole justification was informing this decision, and it is made. **W2 and W4 are promoted**, because a continuous small-feature cadence is exactly the mode that depends on a doc record and on trustworthy targeted spec runs |
| Q4 | Canonical front door? | **The apex is the landing page for all tenants** (`rjbookstop.pulllist.app` is the founding tenant's own door) | The *premium-tier lever* framing in `apex-landing-tenant-subdomains.md` is **dead** — per-tenant subdomains are convenience/branding, not a paid tier. Recorded in W6 |
| Q5 | `weekly-pipeline-consolidation-plan.md` still live? | **"Done for now"** | **Closed 2026-08-29** with items 1–3 marked shipped and 4–5 explicitly dispositioned. Folded into W7 |
| Q6 | Cloudflare hostname inventory? | **"To be explored (please advise)"** | **W6 stays 🔴** but now carries a concrete how-to — see W6 § "How to gather it" |
| Q7 | F135 — build the decoupling, or keep the `.env` mitigation? | **Keep the mitigation** | **W3 is DEFERRED.** It was this plan's #1 recommendation and its 48-hour clock is stood down. `docs/f135-decouple-feed-publish.md` re-tokened **DEFERRED** with the accepted residual risk stated |
| Q8 | Legacy GitHub Pages surface — retire or keep warm? | **Keep warm if free, otherwise close** | **Measured: it is free → keep warm.** `mrcyberrick/comic-preorder` is a **public** repo, so GitHub Pages hosting costs nothing; `mrcyberrick.us` is a pre-existing registration independent of this. **But see the caveat in W7** — what is being kept warm is not quite what the docs describe |

**Net effect on the workstream:** W1 done, W3/W8/W10 deferred, W5 unblocked, W2/W4 promoted to the
front, W6 unblocked-with-guidance, W7 grew two items. **The active list is W2, W4, W5, W6, W7, W9,
W11.**

---

## 1. Current State Summary

### 1.1 Phase state

| Layer | State |
|---|---|
| Phases 1–4 | Complete. |
| Phase 5 | **Complete 2026-07-15**, every completion criterion ticked, Deferred-DDL Register closed. Two tenants live on production (`rjbookstop` founding, `comicstore` pilot/seeded). |
| Phase 6 | **STUB, not started.** Gated on S0 — wildcard DNS + TLS for `*.pulllist.app`. **F145 measured that gate 2026-08-27 and confirmed it is genuinely still closed.** |
| Active phase / sub-deploy | **None / none.** |

**The migration program has had no phase in flight for six weeks.** Everything shipped since
2026-07-15 has been standalone feature and finding work against the founding tenant, at a fast
cadence — including three separate production promotions **today**. That is the single most
important framing fact in this document, and § 2 treats it as such rather than as background.

### 1.2 What shipped since the predecessor plan was written (2026-08-28 → today)

All verified from git, not from doc narrative.

| Work | Staging | Production | Doc record |
|---|---|---|---|
| **F115 S6 production backfill** — 26 genuinely-unproven rows → `'unknown'`, 859→833 orphans, independently re-verified | n/a | **2026-08-28** | ✅ `07100da`; § 13 F115 = RESOLVED both envs |
| **F146 staging close-out** — all 16 false withdrawal marks cleared, DB-verified | **2026-08-29** | n/a (prod holds 0 marks) | ✅ `86c7d29`, `e5ed727` |
| **This Week bagging list — rejected/withdrawn moved to a separate note** (`admin.html`, +25/−14) | `56fafc5` | **PR #142** `961c48b` | ❌ **none** |
| **F132 restriction badge on the admin store shipment grid** (`arrivals.html`, +17/−1) | `a60469b` | **PR #143** `c04eff1` | ❌ **none** |
| **Restriction badge in the reconciliation exceptions list** (`arrivals.html`, +16/−2) | `bcbbfb3` | **PR #144** `69eaa9f` | ❌ **none** |
| `/deploy-staging` skill: pre-push baseline uses `-SkipPlaywright` | `c632ec4` | n/a | ✅ in `CLAUDE.md` |

**The three ❌ rows are a live documentation-integrity gap.** Three changes reached production
today. Neither `CLAUDE.md` § Current Migration Phase nor `docs/technical-reference.md` § 13
mentions any of them, and no plan doc covers them. This is the inverse of the stale-status pattern
that consumed F132 / F138 / F139 / F145: not a status written and never revisited, but **no status
written at all**. The `admin.html` This Week change in particular is behavioural — a bagging list an
employee physically pulls stock against — and whether it is a defect fix owing a finding ID or a
feature build owing none is a judgement nobody has recorded. **Item W2.**

### 1.3 Staged-but-not-promoted — verified against branch diff, not doc claims

```
git log --oneline origin/main..origin/staging
  e5ed727 docs(F146): RESOLVED on staging — corrected re-test cleared all 16 marks, DB-verified
  86c7d29 docs(F146): record 2026-08-29 verification halt

git diff --stat origin/main origin/staging
  CLAUDE.md | 15 +-        docs/technical-reference.md | 17 +-
  config.js | 10 +-        supabase/migrations/*.sql   | 438 -----   (F125, expected)
```

**Nothing.** Two doc-only commits on staging. **No application file differs between the branches** —
`admin.html`, `arrivals.html`, `app.js` and `style.css` are byte-identical, so today's three
features are present on both. The only non-doc asymmetries are the two documented, expected ones:
`config.js` (per-branch by design) and `supabase/migrations/` (present only on `main`, F125).

**No unapplied SQL either.** All 20 files in `docs/sql/` carry a `-- STATUS:` line reading APPLIED
on both environments, or N/A where deliberately single-environment. Zero pending.

### 1.4 What genuinely reads as open

**Plan docs not at COMPLETE** (from each file's own `**STATUS:**` token):

| Doc | Token | Real state |
|---|---|---|
| `docs/f135-decouple-feed-publish.md` | **NOT STARTED** | Full runbook written 2026-08-21, direction settled with Rick, interim mitigation live. **Genuinely not started.** → W3 |
| `docs/weekly-pipeline-consolidation-plan.md` | **NOT STARTED** | Items 1–3 of its § 6 checklist are ✅ done (producer built, auto-publish wired, print report shipped and promoted). Only items 4–5 (parallel run, Apps Script retirement) remain — and **F135 largely subsumes their risk** by moving the producer's trigger. See § 5 Q5. |
| `docs/interim-deployment-work-instructions.md` | **IN PROGRESS** | Written 2026-06-11 as a bridge "until post-5.5." 5.5 closed 2026-07-15. Stale by its own terms; it defers to `CLAUDE.md` on any disagreement, so it is noisy rather than dangerous. → W7 |
| `docs/pre-phase-6-consolidation.md` | **PROPOSED** | Never approved. C1 + the F146 close-out are done; C2–C8 carry into this plan. Token needs advancing either way. → W7 |
| `docs/native-customer-signup.md` | **COMPLETE**, four boxes unticked | **Still a genuine conflict — re-verified from source this session.** `supabase/functions/register-customer/index.ts` still carries the whole MailerLite webhook path: header comment (lines ~4–14), `url.searchParams.get('secret')` (~line 199), the `?secret=` branch (~line 204), the tenant lookup against `tenants.settings->>'mailerlite_webhook_secret'` (~line 210). **S5 has not run.** → W5 |
| `docs/phase-6-self-service-signup.md` | **STUB** | Correct; gated on S0. → W8 |

**Findings genuinely open** (pointer only — detail lives ONLY in `docs/technical-reference.md`
§ 13; read each status line's *last clause*, not its first word):

| ID | Severity | State | Owner item |
|---|---|---|---|
| **F135** | Medium | planned, not started; interim `.env` mitigation live and depends on a human remembering it | **W3** |
| **F133** | Low (test-infra) | open. Variant (b) means **a green targeted run is not evidence** | **W4** |
| **F130** | Low (test-infra) | open, 197 orphaned staging auth users; **its recorded fix plan is invalid as stated** | **W4** |
| **F145** | Low today, Medium if acted on | items 1/2/4 done at filing; **item 3 still owed** | **W6** |
| **F131** | Medium scaling / **High continuity** | open, no plan doc; interim mitigations only | **W9** |
| **F72 + F99** | — / Low defect, Medium decision | deferred; must be **designed together**; F99's DMARC gate read clear 2026-08-20; **F99's own trigger is the MailerLite retirement, i.e. W5** | **W10** (scoping only) |
| **F89, F90** | Low | deferred — analytics instrumentation; wants a schema + import-script session | not scoped here |
| **F126 residual** | Medium (product gap) | profile **email** editing unreachable outside the Supabase console (needs an Edge Function, F25); paused-customer reservation handling undecided | not scoped here |
| **F141 residual** | — | resolved on `catalog.html`; the same CLS shape on `mylist.html` / `arrivals.html` is **unmeasured** | **W11** (opportunistic) |

**F115, F146 (staging), F147, F142, F143, F144, F132, F141, F136, F137, F138, F139 and F140 are
resolved** and are not open work. **F4 / F15 / F16 / F20 / F34 — the five the § 13 header still
calls HIGH or dormant-HIGH — are all resolved on both environments.** That header is Phase-4-era
text: accurate about history, misleading about the present. Do not read it as a live risk list.
§ 4.4 states what actually activates with tenant N+1 today.

### 1.5 The F115 import window — CLOSED, and what that means

The window is **closed**, not pending. Production ran its real September import 2026-08-28
(`catalog_month` 2026-08 → 2026-09); staging ran the same day. **The admin-ordering freeze is
lifted** and nothing in this plan is blocked by it. The constraint is dormant until **October's
import** opens the next one.

**October's import is a real watch item, not a formality.** Two fixes get their first-ever live
production exercise there:

- **F147's FOC check** — the corrected `narrowWithdrawalCandidates()`. Its *mark* half could not be
  re-exercised this cycle (flipping `catalog_month` to `2026-09` closed the new-month window the
  moment the run finished), so it has been verified only retrospectively against the 519 real rows
  and by unit test. October is the first live run.
- **F146's unconditional clear half** — production currently holds **0** withdrawn marks, so there
  is nothing there for the clear path to act on until marking runs again.

Both were High / Medium-High severity, both have only ever fired once, and both fired wrong.
Schedule October's import as an attended session with those two behaviours explicitly watched
(`/schedule-gate` exists for this).

### 1.6 One operational residual that outranks every engineering item here

`CLAUDE.md` § Current Migration Phase, written 2026-08-28 (`ccb6712`) and **untouched by any of the
four staging commits since**:

> **Residual, not yet done:** production's Maintenance Mode is still **ON** and `order_deadline` is
> still cleared (Step 7/8 of `docs/monthly-catalog-refresh.md`) — both need action before the store
> reopens to customers.

**If that is still true, the production store is closed to customers right now.** I could not
verify it from this session and will not assert either way: `app_settings` is not readable with the
anon key on either environment (production returns `[]` under RLS, staging returns `42501 permission
denied` — see § 4.6), so the value needs Rick or a service-role read.

It is a one-day-old claim and Rick shipped three production features today, so it may already be
done. **It is item W1 because the cost of assuming it is done and being wrong is a closed store,
and the cost of checking is one query.**

---

## 2. Strategic Assessment

### 2.1 The situation, stated plainly

The predecessor plan framed the choice as three shapes — open Phase 6 (A), consolidate (B), run the
go-to-market track (C) — and picked B on the strength of one item having a **deadline**: the
September import. **That deadline is gone. It was met. The argument that selected Shape B no longer
exists**, so this plan has to re-make the case rather than inherit it.

Re-made, it still holds, but for a different and weaker reason — and there is a fourth shape the
predecessor never named, which is what the project has actually *been doing*.

### 2.2 Shape D — the unnamed status quo: continuous small features for one store

Twenty-plus standalone sessions since 2026-07-15; three production promotions today alone; every one
a small, sharp improvement to how **Ray & Judy's Book Stop** runs its week. No phase, no workstream,
no plan doc for most of them — and, as § 1.2 shows, increasingly no doc record either.

- **Gets:** the highest observed rate of real value delivery in the project's history, to the one
  customer who is actually paying. Rick is evidently good at this and enjoys it.
- **Costs:** the finding register drains slower than it fills; plan docs drift from reality (three
  instances today); and the migration program's declared successor never opens.
- **It is not a mistake — it may be exactly right — but it is currently happening by default rather
  than by decision.** Naming it is the most useful thing this planning pass can do.

### 2.3 Shape A — open Phase 6 (S0 spike, then 6.1–6.4)

- **Gets:** the self-service roadmap unblocked.
- **Costs:** the largest remaining body of work in the program — public signup, Turnstile, rate
  limiting, slug denylist and profanity filtering, a tenant lifecycle state machine, hostname
  reclamation, an abuse soak.
- **Blocked twice over:** S0 is unanswered (F145 confirmed the gate is genuinely closed), and 6.2's
  **eligibility-verification method is undecided** (§ 4.5) — a Rick scoping call, not an executor
  task. **And there is no recorded demand signal anywhere in the repo:** two tenants, one of which
  (`comicstore`) is explicitly demo/test and "never a real customer."
- **But its cheap half is genuinely cheap.** The S0 spike is half a day of dashboard reading, DNS
  probes and published pricing. Nothing requires it to wait for the rest of the phase.

### 2.4 Shape B — finish the consolidation (predecessor C2–C8, here W3–W10)

- **Gets:** F135 closed — the ad-hoc-import-mails-a-stale-newsletter defect, currently mitigated
  only by a human remembering to comment out an `.env` line; a **trustworthy test suite** (F133
  variant (b) means a green targeted run currently proves nothing, which silently undercuts the
  measured iteration workflow adopted 2026-08-09); F99's gate unstuck; the Phase 6 cost model in
  hand.
- **Costs:** no new customer-facing surface ships. Some of it is unglamorous.
- **One item is calendar-bound, and that is now the forcing function** (§ 2.6).

### 2.5 Shape C — go-to-market: F72 + F99, then the Founding Partner cohort

- **Gets:** the business step already priced (2026-08-19: five free-year slots for new tenants, then
  $39-capped, $39 locked for life, live counter required).
- **Costs:** the highest blast radius of any option — two DNS providers, six Edge Function `from:`
  sites, DKIM/Return-Path provisioning, and a failure mode of **customers stop receiving magic
  links**.
- **Structurally downstream of W5.** F99's own recorded trigger for publishing `p=quarantine` is
  "MailerLite retirement (not a date)" — which is W5. Doing W5 first is not deferring Shape C; it is
  Shape C's first step, and it is small.

### 2.6 Recommendation — my opinion, and the reasoning behind it

> **⚠️ SUPERSEDED by § 0 (Rick, 2026-08-29).** Rick chose **Shape D** (Q3: "small features for now")
> and **declined W3** (Q7: keep the `.env` mitigation). So the recommendation below — Shape B with
> W3 started inside 48 hours — did **not** carry, and its two load-bearing arguments are both
> stood down. **Point 2 survives the change and gets stronger, not weaker:** a continuous
> small-feature cadence depends *more* on trustworthy targeted spec runs than a phase cadence
> does, which is why W4 moved to the front rather than off the list. Retained below as the record
> of what was argued and on what evidence.

**Take Shape B again, but re-ordered around elapsed time rather than around a deadline — and start
W3 (F135) within 48 hours, because it is the only item where waiting costs a week.**

In order of weight:

1. **W3's cost is mostly waiting, and the clock only starts when it starts.** F135's S3 and S5 each
   need **one observed unattended Tuesday cycle**. Today is **Saturday 2026-08-29**; the next
   Tuesdays are **Sep 1, Sep 8, Sep 15**. Land S1+S2 by Monday and S3 observes Sep 1, S4 lands
   midweek, S5 observes Sep 8 — **F135 closes ~Sep 9**. Miss Monday and every gate slides a full
   week to ~Sep 16. Nothing else here has that property. **Start the waiting first, then do the work
   that fits inside the wait.** (The predecessor sequenced C2 fourth; that was right while a freeze
   was live and is wrong now.)
2. **The test suite is currently not trustworthy, and this is the cheapest week to fix it.** F133
   variant (a) trips on the ambient `order_deadline`, which Step 7 of the refresh just cleared or is
   about to reset. Until W4 lands, every "I ran the targeted spec, it's green" in this project is a
   claim with a known counterexample.
3. **Shape C is downstream of Shape B whether or not it is planned that way** (§ 2.5).
4. **Shape A's expensive half has no demand pulling it, and its cheap half fits inside Shape B**
   (W8). Folding the spike in means the Phase-6-vs-Founding-Partner call gets made with the cost
   model in hand instead of against the stub's guess.

**Where I am genuinely uncertain, stated as uncertainty:** the tiebreaker between Shape B and Shape
D is not a technical judgement and cannot be made from the repo. If Rick's actual next objective is
the Founding Partner launch, then W5 → W10 → Shape C is the spine and W3/W4 are overhead on the way.
If the objective is "keep making the Book Stop's week better," Shape D is already correct and this
plan should be trimmed to **W1, W2 and W3** — reopen the store, record what shipped, close the one
finding that can mail a wrong newsletter. **§ 5 Q3 is that question, and it can change everything
below it.**

**Explicitly deferred, and why:**

| Deferred | Why |
|---|---|
| Phase 6 sub-deploys 6.1–6.4 | Gated on W8's answer **and** on the undecided eligibility-verification method. No demand signal recorded. |
| F72 + F99 **execution** | Blast radius; joint design required; blocked on W5. Their **scoping** is W10. |
| F89 / F90 | Genuinely low; want a schema + import-script session. |
| F126 residual | Needs an Edge Function (F25). Rick's call to schedule; no forcing function. |
| `weekly-pipeline-consolidation-plan.md` items 4–5 | F135 subsumes most of the remaining risk. See § 5 Q5 before spending a session on it. |
| F131's structural fix | Volume question unanswered (~11,700 rows vs Edge Function limits); ~1,400 lines of hard-won normalizer logic to port. Interim mitigations only (W9). |

---

## 3. Work Breakdown

Sizes are **my opinion**, calibrated against this repo's recent sessions: *small* = one focused
session; *medium* = a session plus a verification pass; *large* = multiple sessions or real elapsed
calendar time.

**Items flagged 🔴 need a Rick decision or a Rick action before an executor can start.**

---

### W1 ✅ **DONE 2026-08-29** — Confirm production is open to customers

**Answered by Rick (§ 0 Q2): production is serving customers.** Step 8 (Maintenance Mode OFF) is
done. The stale "Residual, not yet done" paragraph was removed from `CLAUDE.md` § Current Migration
Phase the same day, with the correction noted in place rather than silently overwritten.

**One sub-item survives and is NOT closed:** whether **Step 7** (set `order_deadline`) was run is
still unconfirmed. A live store with a cleared deadline is not broken, but per F108's
order-deadline-supersedes rule it changes what the At-Risk / Backorder panels classify, and it is
the ambient value **F133**'s date-dependent specs trip over — so **W4 must read the live value
rather than assume either state.** `app_settings` is not anon-readable on either environment
(§ 4.6), so this needs a service-role read or a look at the admin Settings screen. **One query;
do it before W4.**

*Original item retained below for the record.*

**Delivers:** certainty about whether the production store is currently serving customers.

- **Why first:** `CLAUDE.md` claims Maintenance Mode is **ON** and `order_deadline` **cleared** as of
  2026-08-28 (§ 1.6). Unverifiable from an agent session — `app_settings` is not anon-readable on
  either environment.
- **Do:** read `app_settings` on production with the service-role key, or simply check the admin
  toggle in the UI. If Maintenance Mode is on, run **Step 7** (set Order Deadline) then **Step 8**
  (toggle Maintenance Mode off) of `docs/monthly-catalog-refresh.md`, **in that order** — a live
  store with no order deadline changes what the At-Risk / Backorder panels classify.
- **Then:** delete the "Residual, not yet done" sentence from `CLAUDE.md` § Current Migration Phase
  and record the deadline date chosen. A residual note that outlives the residual is the same defect
  class as F132 / F138 / F139 / F145.
- **Touches:** production `app_settings` (Rick), `CLAUDE.md`.
- **Size:** **Small** (minutes) — **but it is Rick's action, not an executor's.**
- **Done when:** production Maintenance Mode is off, `order_deadline` holds a real date, and
  `CLAUDE.md` says so with the date.

---

### W2 — Record the three 2026-08-29 production promotions

**Delivers:** the three changes that reached production today (§ 1.2) have a doc record, and the one
behavioural change among them has a recorded disposition.

- **Do:**
  1. Add a "Last completed work" entry to `CLAUDE.md` § Current Migration Phase covering PR **#142**
     (This Week bagging list — rejected/withdrawn moved to a separate "not arriving" note,
     `admin.html`), PR **#143** (F132 restriction-ratio badge on the admin store shipment grid,
     `arrivals.html`) and PR **#144** (the same badge in the reconciliation exceptions list,
     `arrivals.html`) — each with its staging commit, its PR number, and what was verified
     post-deploy.
  2. **Decide and record whether #142 owes a finding ID.** Read `git show 56fafc5` first. If the old
     behaviour was *wrong* — a rejected or withdrawn title printed on a bagging list an employee
     pulls stock against — it is a defect and owes **F148** via `/file-finding`. If it is a
     presentation improvement to already-correct behaviour, it owes none; record that judgement
     explicitly the way the print-CTA and phone-number entries do ("**No finding ID consumed**
     (feature build, not a defect)"). **Do not leave it unstated.**
  3. If #143/#144 extend F132's surface, add a line to § 13 F132 noting the arrivals-side reach
     (F144 already covers the Order Builder half).
- **⬆️ PROMOTED by § 0 Q3 — and it should grow one step.** "Small features for now" means this
  record gap is not a one-off to patch; it is a **weekly** gap that will keep reopening. The
  three-promotion write-up closes today's instance. **The step that stops it recurring:** add a
  required step to the `/promote-prod` skill — *after* the PR merges, write the `CLAUDE.md`
  § Current Migration Phase entry (PR number, staging commit, what was verified post-deploy, and an
  explicit finding-ID yes/no) before the skill reports success. The project already encodes its
  promotion gates as skill steps (`/preflight`, the F59 merge-result check, the F125 tree-integrity
  assertions); this is the same move applied to the one gate that is currently a habit rather than
  a step. **Cheap, and it is the difference between fixing this once and fixing it every week.**
- **Touches:** `CLAUDE.md`; possibly `docs/technical-reference.md` § 13; the `/promote-prod` skill
  definition.
- **Gating:** none. Doc-only, commit direct to `staging`.
- **Size:** **Small.**
- **Done when:** every production promotion in the last 7 days has a `CLAUDE.md` record; the
  finding-ID question for #142 is answered in writing; and `/promote-prod` will not report success
  without the record.

---

### W3 ⛔ **DEFERRED 2026-08-29** — F135: decouple the pull-feed publish from shipment import

**Rick's decision (§ 0 Q7): keep the `.env` interim mitigation; do not build the decoupling.** The
48-hour clock below is stood down and the Sep 1 / Sep 8 Tuesday windows are not being used.
`docs/f135-decouple-feed-publish.md` has been re-tokened **DEFERRED** with the accepted residual
risk written into its status block, so a future session does not re-propose it as new work.

**The residual risk, stated once so it is not lost:** the mitigation is *"comment out
`GITHUB_TOKEN_PULL_FEED` in the scripts `.env`, run the ad-hoc import, restore it."* It depends on
a human remembering, **every time**, and F134's one-off shipment path made ad-hoc imports routine.
Forgetting it republishes a past newsletter week, purges the current week's thumbnails, and lets
the next Brevo cron mail the stale issue — the measured 2026-08-11 incident, reproduced by
accident.

**Cheap hardening that stays inside Rick's decision** (no decoupling, no code): make the pre-step
impossible to miss where an operator actually looks — a bold pre-flight line in
`docs/monthly-catalog-refresh.md` and wherever the F134 one-off shipment path is documented, not
only inside F135's own plan doc, which nobody opens before an ad-hoc import. **Fold into W9**,
which is already editing that runbook.

*Original item retained below — the runbook is complete and correct, and should be executed
unchanged if this is ever picked up.*

**Delivers:** `import.js` stops publishing the newsletter; the weekly send workflow builds the feed
from the database immediately before sending, so an ad-hoc shipment import can never mail a stale
week again.

- **Owner doc:** `docs/f135-decouple-feed-publish.md` — § 5 runbook S1–S5, § 6 gates V1–V5. The
  runbook is complete and the direction was settled with Rick 2026-08-21. **Follow it; do not
  redesign it.**
- **Touches:** the **private scripts repo** (`catalogs/scripts` working tree — `import.js`'s publish
  block ~line 1931 and `resolveFeedWeek()` ~line 1510, plus its export and unit tests) and the
  `mrcyberrick/weekly-pull-feed` repo's send workflow. **No `comic-preorder` change at all.**
  Re-read both files from disk; the line numbers above were last verified 2026-08-21.
- **Sequencing — this is the whole point of the item:**
  - **S1 + S2 must land by Monday 2026-08-31** so S3 observes **Tue 2026-09-01**. Slipping past
    Monday costs a full week per gate.
  - **S3 before S4, always.** The new trigger must be proven before the old one is removed, or the
    failure mode flips from loud (wrong week mailed) to silent (nothing published, nobody notices) —
    exactly the trade § 4.1 of the owner doc exists to avoid.
  - S4 → S5 observes **Tue 2026-09-08**; F135 closes ~2026-09-09.
- **Precondition not in the owner doc — add it before trusting S3:** confirm a shipment import has
  run recently enough that the committed `newsletter-email.html` carries a fresh
  `<!-- pull-feed-generated: YYYY-MM-DD -->` stamp. `send-brevo-campaign.js` fail-closes at
  `STALE_MAX_DAYS=6`. If the stamp is stale, Tuesday's observation is of an **abort**, not of a
  build, and proves nothing about the new step. **Read the stamp before Tuesday, not after.**
- **Two designed-around risks (owner doc § 4.3) — re-check both:** (a) **F100** — exactly one GitHub
  Pages deployer must remain after S2; adding a build step must not reintroduce a second. (b) token
  placement — a build running inside `weekly-pull-feed`'s own Actions should use that repo's
  credentials, not a copy of `GITHUB_TOKEN_PULL_FEED` from the scripts `.env`.
- **Test note:** `resolveFeedWeek` is exported and likely unit-covered. Run `npm test` in
  `catalogs/scripts` after S4 and expect the count to move (it stood at 279/279 after F147).
- **Size:** **Medium** in effort, **Large** in elapsed time (calendar-bound, ~2 weeks).
- **Done when:** V1–V5 green, including **one unattended Tuesday cycle read from the Brevo
  campaign's observed status** — not from a green GitHub Actions run (F96: three consecutive weeks
  ran green while every campaign sat suspended with zero recipients); `resolveFeedWeek()` gone from
  `import.js` and from its tests; exactly one Pages deployer remaining.

---

### W4 — Test-infrastructure session: F133 then F130, in that order

**Delivers:** date-dependent specs that no longer flip on the calendar, panel assertions scoped to
their own seeded rows, and a **classified** — not bulk-deleted — auth-user orphan set.

- **Owner findings:** `docs/technical-reference.md` § 13 **F133**, **F130**. Template:
  `docs/test-infra-maintenance-f91-f95-f103.md`.
- **Touches:** the **local-only, never-committed** Playwright suite at
  `catalogs\scripts\playwright\` — `tests/15-order-export-ledger.spec.ts` (`focThisMonthFuture()`
  and its three callers), `tests/06-admin-this-week-bagging.spec.ts`,
  `tests/21-arrival-resolution.spec.ts:136`, `fixtures/auth.ts` (`deleteUser`). **The only repo
  changes are the two § 13 finding entries.**
- **F133 has two variants; fixing one does not touch the other.**
  - **(a)** a fixture FOC crossing *past* a live `order_deadline` — closed by making
    `focThisMonthFuture()` deadline-aware (read the live value; cap against it).
  - **(b)** a *lapsed or cleared* deadline re-admitting **real** catalog rows into
    `#backorder-risk-panel` — needs assertions scoped to the seeded row (`data-catalog-id`), not
    `toContainText` against the whole panel. **This variant also exposes an undeclared spec-order
    dependency:** spec 21 passes in the full suite only because spec 15 ran first and left the state
    it needs.
  - **Reproduce (b) before fixing it:** run `21-arrival-resolution` targeted, then in the full suite,
    and confirm the pass/fail disagreement still holds. **That disagreement is the finding.**
  - **Timing:** W1 sets a fresh `order_deadline`. Do W4 *after* W1 and re-read the live value rather
    than assuming it is still cleared.
- **F130's recorded fix plan is invalid as stated — do not follow it.** Date-bucketing against F95's
  2026-08-02 fix cannot distinguish an *intended* `pw-pending-*` decline survivor (F64 item 5 Option
  A) from a teardown miss. **Classify by originating spec/prefix first**, fix the teardown paths that
  skip the auth call, and only then delete what remains. The auth DELETE itself was measured working
  2026-08-24 (6/6 deleted, 0 remained) — these are deletes never *attempted*, not deletes that
  failed.
- **Expect F91/F107 noise:** GoTrue intermittently rejects `sb_secret_` keys and rate-limits magic
  links on repeated full runs. A flaky-looking auth failure on a third consecutive full run is
  neither the code nor the test.
- **Size:** **Medium.**
- **Done when:** full `run-smoke.ps1` green **and** each previously-affected spec green in a
  **targeted** run — that second assertion is what proves variant (b) is fixed; F130's orphans
  classified by originating prefix, teardown gaps fixed, remainder dispositioned in § 13.

---

### W5 ✅ **UNBLOCKED 2026-08-29** — Retire the MailerLite webhook path (native-signup S5)

**Delivers:** the dead `?secret=` webhook branch removed or explicitly disabled, the exposed webhook
secret rotated to dead config, every doc surface corrected — and **F99's stated trigger fired**,
which is what unblocks W10 and Shape C.

- **Owner doc:** `docs/native-customer-signup.md` § S5 and its four unticked Completion Criteria.
- **✅ UNBLOCKED — § 0 Q1 answered 2026-08-29: REMOVE IT ENTIRELY.** Not present-but-dead. Delete
  the branch, do not comment it out. **This removes the mechanism platform-wide**, not just for the
  founding tenant — `comicstore` and every future tenant lose it too, which is the intended
  consequence and is why it needed Rick rather than an executor.
- **Because removal is platform-wide, the surface is wider than the Edge Function.** Sweep all of
  these, and do not stop at the first one:
  1. `supabase/functions/register-customer/index.ts` — the `?secret=` branch **and** the header
     comment block that documents "two entry paths" (it becomes wrong the moment the branch goes).
  2. `docs/tenant-onboarding-runbook.md` **Step 4** ("Configure MailerLite webhook") — **delete the
     step**, do not just annotate it; an operator following a runbook does what it says.
  3. The same runbook's **Step 7 go-live checklist**, which carries a `- [ ] MailerLite webhook
     configured (Step 4)` line. A checklist item pointing at a deleted step is worse than either.
  4. `tenants.settings->>'mailerlite_webhook_secret'` — the column stays (it is a jsonb key, not a
     schema object), but the secret is now dead config. **Rotate or clear it** and say which was
     done.
  5. `register-tenant` (Phase 5.4 S3) **issues** that per-tenant secret. Check whether it still
     should. If it keeps minting a secret nothing consumes, say so explicitly rather than leaving
     the next reader to work it out.
- **Touches:** `supabase/functions/register-customer/index.ts` (header comment ~lines 4–14, the
  `secret` read ~line 199, the `?secret=` branch ~line 204, the tenant lookup ~line 210 — **re-read
  from disk**); `docs/technical-reference.md` § 11 Edge Function inventory and § 13 F34/F72 notes;
  `CLAUDE.md` § Edge Functions; `docs/tenant-onboarding-runbook.md` **Step 4 and its Step 7 go-live
  checklist line**; `docs/native-customer-signup.md` (tick the boxes **or** correct the token — they
  must agree, per `CLAUDE.md` § Definition of Done).
- **Verify, don't assume, two things:** (i) that the founding tenant's MailerLite webhook is genuinely
  dead before removing the receiving end; (ii) whether PR #95's **prod write-smoke + 24-hour soak**
  ever completed — that box is also unticked and the deploy log stops at "soak in progress." If it
  did not, either run it or re-disposition the box explicitly.
- **Deploy note:** Edge Functions deploy outside the branch flow, on both Supabase projects, so this
  item touches production without a promotion PR. The `config.js` rule still holds; nothing here goes
  near it.
- **Gating:** none on any import window. **Blocks W10.**
- **Size:** **Small–Medium.**
- **Done when:** `register-customer` no longer accepts the webhook path (or accepts it only as
  explicitly-dead code, per Q1); the secret is rotated to dead config; the plan doc's token and
  checkboxes **agree**; § 11 / § 13 / `CLAUDE.md` / onboarding-runbook Steps 4 and 7 all updated.

---

### W6 ✅ **DONE 2026-08-30** — F145 item 3: record the tenant hostnames as durable infrastructure

**Rick supplied the inventory 2026-08-30** (Pages Custom-domains list + a full `pulllist.app` zone
export + an audit-log entry). Delivered: `docs/tenant-onboarding-runbook.md` **Step 3a**, § 13 F145
item 3 ticked, and `apex-landing-tenant-subdomains.md`'s premium-tier framing superseded per § 0 Q4.

**Three things the inventory changed that the item did not anticipate:**

1. **`rjbookstop.pulllist.app` has a second, heavier dependency than the printed paper.** It is a
   **mail-authentication domain** — the zone carries `brevo1`/`brevo2._domainkey` CNAMEs, an SPF
   record (`include:spf.brevo.com`), and a `brevo-code:` verification TXT, all scoped to that
   subdomain. The weekly newsletter authenticates as it. Retiring or renaming it breaks DKIM/SPF
   for customer marketing mail — and that failure appears as deliverability decay, not as an error.
2. **The wildcard's absence is now confirmed configuration-side**, not just by NXDOMAIN: the zone
   export has no `*` record, and all three custom domains CNAME to the same Pages project. This is
   the better kind of evidence and it makes W8's gate finding firmer, not weaker.
3. **The audit-log entry does not date the hostname.** It is `Create Subdomain` on
   `/accounts/…/workers/subdomain` — the account's **workers.dev** subdomain (2026-06-11), not a
   Pages custom domain. **Provisioning date stays unrecovered**, per F145's own instruction not to
   infer one.

*Original item retained below, including the how-to, which worked.*

#### (original) W6 — F145 item 3: record the tenant hostnames as durable infrastructure

**Delivers:** `rjbookstop.pulllist.app` and `comicstore.pulllist.app` recorded as individually
provisioned Cloudflare Pages custom hostnames, with an explicit note that the first appears on
**printed customer material** and must not be retired without reprinting.

- **Owner:** `docs/technical-reference.md` § 13 F145 fix item 3 (items 1, 2 and 4 are done or
  explicitly no-action).
- **Touches:** `docs/tenant-onboarding-runbook.md` — Step 3 already documents *how* to provision one;
  what is missing is an **inventory of which exist**. Plus § 13 F145 (tick item 3). Optionally
  `docs/apex-landing-tenant-subdomains.md` § Strategic direction, **only if** Rick answers § 5 Q4.
- **🔴 Gating:** still needs **Rick's Cloudflare-side inventory**. F145 deliberately declined to
  infer infrastructure state from two `curl` results and that reasoning still holds — an NXDOMAIN
  tells you a name does not resolve, not what the account is configured to serve.

**How to gather it — § 0 Q6, "to be explored (please advise)."** Three places, ~5 minutes, all
read-only. **Change nothing while you are in there.**

1. **The authoritative list — Pages project → Custom domains.**
   Cloudflare dashboard → **Workers & Pages** → the Pages project serving `pulllist.app` → the
   **Custom domains** tab. This is the list W6 needs: every custom hostname attached to the
   project, each with a status (Active / Pending / Error). **Capture the whole list verbatim, not
   just the two we know about** — the entire point is finding out whether there are others.
2. **The DNS side — the `pulllist.app` zone.**
   Cloudflare → **Websites** → `pulllist.app` → **DNS** → **Records**. Confirm the records backing
   `rjbookstop` and `comicstore`, and — the one that matters for Phase 6 — confirm **no `*`
   wildcard record exists**. F145 inferred its absence from NXDOMAIN; this confirms it from the
   configuration side, which is a different and better kind of evidence.
3. **The provisioning date — Audit Log (best effort).**
   Cloudflare → **Manage Account** → **Audit Log**, filtered to the Pages/zone resource, looking
   for the `rjbookstop.pulllist.app` add event. **Retention is limited and this may simply not be
   there.** If it is not, record *"provisioning date unrecovered"* — F145 already says exactly
   that, and a guessed date in an infrastructure record is worse than an honest gap.

**What to write down for each hostname:** the hostname, its status, which Pages project (and
branch/environment) it maps to, and whether it is a Pages custom domain or a plain zone DNS record.
Then W6 is a ten-minute doc edit.

**Two things to note while you are there, both from § 0:**
- **Q4 changed the positioning.** The apex is the landing page for all tenants; a per-tenant
  subdomain is convenience and branding, **not a premium tier**. `apex-landing-tenant-subdomains.md`
  § Strategic direction still frames the branded subdomain as the premium-tier lever — correct that
  while W6 is open.
- **`rjbookstop.pulllist.app` is on printed paper** (the View Online CTA, PR #140). Whatever the
  inventory turns up, that hostname does not get retired without a reprint. That caveat is the
  single most important line W6 adds to the runbook.

- **Size:** **Small** (doc-only, one commit to `staging`) once the inventory is in hand.

---

### W7 — Doc-status hygiene (3 of 4 done 2026-08-29) + the Q8 legacy-surface record

**Delivers:** `/preflight`'s STATUS-token sweep stops reporting known-stale docs as open work.

- **Do:**
  1. `docs/interim-deployment-work-instructions.md` — **IN PROGRESS** since 2026-06-11, written as a
     bridge "until post-5.5"; 5.5 closed 2026-07-15. **Retire it, or re-token it COMPLETE with a
     superseded-by line.** It defers to `CLAUDE.md` on any disagreement, so it is noisy rather than
     dangerous; an executor may pick "re-token COMPLETE, superseded by `CLAUDE.md` § Standard
     Deployment Workflow" and say so in the commit.
  2. `docs/pre-phase-6-consolidation.md` — advance its token to reflect that **C1 and the F146
     close-out are DONE** and that C2–C8 have moved to this document. **Do not delete it** — it holds
     the reasoning trail for the S6 predicate decision, which is the most carefully-argued call in
     the project's recent history.
  3. **This document's** token — ✅ done 2026-08-29 (APPROVED, scope trimmed).
  4. ✅ **Done 2026-08-29** — `docs/weekly-pipeline-consolidation-plan.md` **CLOSED** per § 0 Q5,
     with § 6 items 1–3 recorded as shipped and items 4–5 explicitly dispositioned rather than left
     implying unfinished work.
  5. ✅ **Done 2026-08-29** — `docs/f135-decouple-feed-publish.md` re-tokened **DEFERRED** per § 0
     Q7, with the accepted residual risk written into the status block.
  6. **Still to do — record the Q8 decision on the legacy GitHub Pages surface, and the caveat that
     came with it.** See below; this is the only remaining piece of W7.

**Q8's answer, and the measurement behind it (2026-08-29).** Rick: *"keep warm if there is no cost
otherwise close."*

- **There is no cost → keep it warm.** `mrcyberrick/comic-preorder` is a **public** repo, so GitHub
  Pages hosting is free with no bandwidth billing; `mrcyberrick.us` is a pre-existing domain
  registration independent of this decision. Both surfaces are live: `mrcyberrick.github.io/…`
  **301**s to `mrcyberrick.us/comic-preorder/`, which returns **200**.
- **⚠️ But what is being kept warm is not what the docs describe, and this is new information.**
  Measured, not assumed: the legacy surface is **not a frozen snapshot** — it auto-deploys from
  `main` and is currently serving the **2026-08-24 Lighthouse-sweep build** with the **production**
  `config.js` (prod Supabase ref `plgegklqtdjxeglvyjte`, prod founding-tenant UUID). And because
  `tenantSlugFromHostname()` finds no tenant slug in `mrcyberrick.us`, the pre-paint script sets
  `data-front-door="apex"` — so the legacy URL renders the **platform marketing page**, not Ray &
  Judy's branded sign-in.
- **Why that is a caveat rather than a defect:** the apex carries universal login, and the script's
  `token_hash`/`access_token` handling still opens the sign-in panel — so a magic link landing
  there **does** work. Nothing is broken and no customer is pointed at it (the print CTA points at
  `rjbookstop.pulllist.app`). What is lost in a rollback scenario is the *branded* first
  impression, not access.
- **What to record:** in whichever doc claims the surface is "kept warm as a rollback surface," add
  that it is a **live auto-deploying mirror of production on the apex front door**, not a
  point-in-time rollback target, and that a real rollback would land customers on the marketing
  page. **No finding filed** — nothing is broken and nobody is routed there; this is a
  documentation accuracy fix. Raise it if Rick wants it treated otherwise.

- **Touches:** `docs/interim-deployment-work-instructions.md`,
  `docs/phase-5-second-tenant-onboarding.md` (its completion criteria flag the missing retirement
  disposition), `CLAUDE.md` § Project Overview (the "Legacy prod URL" line).
- **Gating:** none.
- **Size:** **Small.**

---

### W8 ⛔ **DEFERRED 2026-08-29** — Phase 6 S0: the wildcard DNS + TLS serving-model spike

**Rick chose “small features for now” (§ 0 Q3), so the decision this spike existed to inform is
made.** Its entire justification in § 2.6 was *“put the Phase 6 cost model in your hands before you
answer Q3”* — answered. Deferring it is the honest consequence, not an oversight.

**It stays recorded as Phase 6's entry gate**, unchanged and still closed (F145). When Phase 6 is
next considered, this is step one and the item below is ready to run as written — half a day, no
approvals, no code. *Do not run it speculatively in the meantime; a measurement nobody is going to
act on is just a doc that will go stale.*

*Original item retained below.*

#### (original) W8 — Phase 6 S0: the wildcard DNS + TLS serving-model spike

**Delivers:** a written, measured answer to the question gating all of Phase 6 — can a freshly-claimed
slug serve at `<slug>.pulllist.app` instantly with zero per-tenant DNS work, and what does each
serving model cost under abuse?

- **Owner:** `docs/phase-6-self-service-signup.md` § "🚩 Gating prerequisite (Phase 6 S0)". The stub
  already frames the two models; this item **measures** them.
- **Establish, in order:**
  1. Whether a `*.pulllist.app` wildcard DNS record + wildcard TLS cert can terminate at the
     Cloudflare **Pages** project as currently configured — **tested, not read off a docs page.**
  2. If not, what does: Cloudflare for SaaS / Custom Hostnames (<100 free, ~$0.10/hostname after), a
     Worker in front, or per-tenant Pages custom domains (**the model actually in force today** —
     F145 measured exactly this: `foo.pulllist.app` and `zzz-does-not-exist-9182.pulllist.app` both
     return NXDOMAIN).
  3. The cost curve for each under abuse, and whether hostname provisioning can be deferred to tenant
     **activation** and reclaimed by an abandoned-tenant sweep via API.
- **Verification discipline — this is the part that matters:** **probe a hostname nobody
  provisioned.** `curl https://rjbookstop.pulllist.app` returns 200 and confirms **nothing** about a
  wildcard. F145 found the defect precisely by probing a name nobody had ever created. A check that
  cannot fail is not a check.
- **Touches:** `docs/phase-6-self-service-signup.md` (§ S0 gains a Findings/Answer subsection);
  possibly a new finding if a measurement contradicts something recorded. **No code.**
- **Gating:** none. Its output is a **decision input** for § 5 Q3, not a dependency of any other item.
- **Size:** **Small** (half a day).

---

### W9 — F131 interim mitigations (no code)

**Delivers:** the catalog-import continuity risk moved from "one person, undocumented" to "one
person, documented and recoverable."

- **Owner:** § 13 **F131** interim mitigations (a)/(b)/(c).
- **(a) mostly done already** — `docs/monthly-catalog-refresh.md` is current (updated 2026-08-22 with
  F136's Step 3 revision sweep) and is a genuine end-to-end runbook. **The gap is that it assumes the
  operator already holds credentials and portal access.** Add a "what a second operator needs"
  preamble: `.env` variables by name, which distributor portals, which accounts, where the CSVs land.
- **(b) is Rick-only** — making `.env` contents and Lunar/PRH portal access recoverable by someone
  other than the operator. An agent cannot do this and should not pretend to.
- **(c)** — frame operator-run import for Founding Partner tenants as an explicit, **time-boxed
  cohort perk** rather than a standing service, so the expectation matches the roadmap. Belongs
  wherever the Founding Partner offer is written down.
- **Fold in the F146 lesson while the runbook is open** — this is new, and it cost a session on
  2026-08-29: **"re-pull the new month, fresher" can never clear a Lunar-coded withdrawal mark.**
  Lunar mints item codes from the solicitation month (`0826…`; measured 100% self-prefixing across
  three consecutive monthly files), so a title marked withdrawn always carries the *prior* month's
  permanent code and cannot appear in any subsequent month's file — at any freshness, ever. The
  working verification path is a re-pull of the mark's **own** month, imported as an older-month
  backfill with `--skip-autoreserve`, which is what § Step 3's Revision Sweep already prescribes for
  a different reason. PRH codes are issue-scoped, which fails the same way for a related reason.
- **Touches:** `docs/monthly-catalog-refresh.md`, `docs/technical-reference.md` § 13 F131.
- **Fold in the deferred-W3 hardening (§ 0 Q7).** Rick kept the F135 `.env` mitigation, so the
  pre-step *“comment out `GITHUB_TOKEN_PULL_FEED` before an ad-hoc shipment import”* is now a
  standing operational requirement rather than a temporary note — and it currently lives only
  inside F135's plan doc, which nobody opens before running an import. **Put it where the operator
  actually looks:** a bold pre-flight line in `docs/monthly-catalog-refresh.md` and alongside the
  F134 one-off shipment path. Comment the line out; do not export an empty shell variable (dotenvx
  override behaviour is version-dependent). This is the single highest-value line in W9.
- **Gating:** none for (a)/(c); (b) is Rick's.
- **Size:** **Small.**

---

### W10 ⛔ **DEFERRED 2026-08-29** — F72 + F99 joint scoping interview → plan doc

**Deferred with W8, and for the same reason:** it is the first step of the Founding Partner
go-to-market track (Shape C), which § 0 Q3 did not select.

**One thing still happens, and it is worth knowing:** **W5 fires F99's trigger anyway.** F99's
recorded condition for publishing `p=quarantine` is “MailerLite retirement (not a date)” — which
is W5, which is going ahead. So after W5, **F99 is unblocked but unscheduled**, which is a
legitimate state as long as § 13 says so rather than continuing to describe it as gated. **Update
F99's entry when W5 lands** — that is a one-line edit inside W5's own doc sweep, not a revival of
this item.

*Original item retained below.*

#### (original) W10 — F72 + F99 joint scoping interview → plan doc

**Delivers:** `docs/email-sender-consolidation-f72-f99.md` — a scoped plan Rick can approve or reject,
covering sender-identity consolidation and per-tenant email branding **together**.

- **Owner findings:** § 13 **F99** (fix direction steps 1–5; step 1 done 2026-07-25; **DMARC gate read
  2026-08-20** — 13 messages, 100% pass, 3 senders, all known, so step 2's prerequisite is satisfied)
  and **F72**.
- **Must record:** the flat-`noreply@pulllist.app` vs per-tenant-subdomain decision (F99 recommends
  per-tenant; Brevo already sends from `rjbookstop.pulllist.app`); the six Edge Function `from:`
  sites; the MailerSend DKIM/Return-Path provisioning that must happen **in Cloudflare**; and the
  `p=quarantine` publish decision (currently **held**, trigger = MailerLite retirement = W5).
- **🔴 Gating:** **blocked on W5**, and needs Rick — both findings state explicitly that they require
  a scoping interview and must be designed together.
- **Explicitly not in scope here:** implementing any of it. No `from:` change, no DKIM provisioning,
  no `p=quarantine` publish.
- **Size:** **Small** as a session; the work it scopes is **Large**.

---

### W11 — Opportunistic: measure F141's unmeasured residual

**Delivers:** a number instead of a guess for whether `mylist.html` and `arrivals.html` carry the same
CLS shape F141 fixed on `catalog.html` (desktop 75 → 98, CLS 0.636 → 0.02).

- **Do:** run `playwright/lighthouse-auth.mjs` (local-only, in the scripts repo working tree — it
  creates a staging user, signs in via magic link, runs Lighthouse against the live session, and
  tears the user down) against both pages. **Measure the authenticated page** — a private-window run
  of `/catalog` is not signed in, `requireAuth()` redirects, and Lighthouse scores the marketing page
  instead. That exact mismeasurement cost real time on 2026-08-24.
- **Then:** record the numbers on § 13 F141's residual line. Fix only if the number warrants it —
  this item is a **measurement**, not a fix.
- **Gating:** none. Genuinely opportunistic; drop it if any other item needs the time.
- **Size:** **Small.**

---

### Recommended sequence — REVISED 2026-08-29 after § 0

```
DONE 2026-08-29
 ├── W1  ✅ prod confirmed serving customers; CLAUDE.md residual line corrected
 └── W7  ✅ 3 of 4 tokens: this doc, weekly-pipeline (closed), F135 (deferred)

NEXT — nothing here is blocked, and nothing here is time-critical
 ├── W2  record the three 2026-08-29 promotions   (small, doc-only) ◀ do first
 ├── W6  ✅ DONE 2026-08-30 — inventory recorded, F145 item 3 ticked
 ├── W4  test-infra F133 → F130                   (read order_deadline live first)
 ├── W5  ✅ unblocked — remove the MailerLite path, platform-wide
 ├── W7  finish — the Q8 legacy-surface record + its caveat
 └── W9  F131 second-operator preamble + the F146 Lunar-code lesson
          + the W3 hardening (make the .env pre-step unmissable)


OPPORTUNISTIC
 └── W11 measure F141's residual on mylist/arrivals

DEFERRED — recorded, not lost
 ├── W3  F135 decoupling      (Q7 — .env mitigation stands)
 ├── W8  Phase 6 S0 spike     (Q3 — Phase 6 not next)
 └── W10 F72+F99 scoping      (Q3 — Founding Partner not next)

WATCH — schedule it, do not rely on memory
 └── October's catalog import: F147's FOC fix and F146's clear half each get their
     FIRST real production exercise. Attended session. Use /schedule-gate.
```

**Two ordering rules, revised after § 0:**

- ~~W3's S3 before S4.~~ **Moot** — W3 is deferred. It still governs if W3 is ever picked up, and it
  is recorded in the item and in F135's own plan doc.
- **Live now: read `order_deadline` before starting W4.** § 0 Q2 confirmed the store is open but
  **not** whether Step 7 ran, and F133 variant (a) is defined against whatever that value currently
  is. Starting W4 on an assumption about it is how F133 was created in the first place.

---

## 4. Risks & Dependencies

### 4.1 The F115 import window is CLOSED — and the next one is a real gate

No admin-ordering-surface work is blocked today. **October's import is not routine:** it is the first
live run of F147's corrected FOC check (its mark half could not be re-exercised this cycle) and the
first production exercise of F146's unconditional clear (production holds 0 withdrawn marks today).
Both findings' only prior real runs produced wrong answers at scale — 519 and 16. Treat October as
attended, and re-open the admin-ordering freeze for it.

### 4.2 `config.js`

Tracked **per branch** with different values on each: production `main` holds the prod publishable
key and prod founding-tenant UUID; `staging` holds staging's. The promotion flow uses
`git checkout main -- config.js`, and **`config.js` must never appear in a promotion PR's diff.** The
agent never edits it and never proposes credential values. A committed publishable/anon key is **not**
a finding — RLS is the security boundary, not key secrecy. Only W5 reaches production in this plan,
and it does so via Edge Function deploys outside the branch flow.

### 4.3 F125 — and a live instance of it sitting in the working tree right now

`main` is **not** "staging + prod `config.js`": `supabase/migrations/` (2 files, 438 lines) exists only
on `main`. Any promotion that rebuilds `main`'s tree *from* `staging` — squash, rebase,
`git checkout staging -- .`, `git reset --hard staging`, **or a promotion branch cut from ambient HEAD
while HEAD is on `staging`** — deletes them and overwrites `config.js` with the staging key.

**Measured this session, and it is sharper than the general warning:**

- **Local `main` is diverged: 2 ahead, 61 behind `origin/main`.** Its two "ahead" commits carry **no
  unique content** — verified: `_headers` is byte-identical to `origin/main`, and the CSP fix they
  contain is already on `origin/main` via PR #136. **But a promotion branch cut from *local* `main`
  without pulling would delete** `docs/pre-phase-6-consolidation.md` (991 lines),
  `docs/f143-f144-ordering-side-rejections.md` (316 lines) and
  `docs/sql/2026-08-26-user-profiles-phone.sql`, **and revert `app.js` and `arrivals.html`.**
- **30 of 33 local branches are fully merged into `origin/main`**, twelve of them named `*-prod` and
  sitting at stale commits. That thicket is the substrate the 2026-08-24 near-miss grew in.

**Mitigations, both cheap:** create every promotion branch from an explicit remote ref
(`git checkout -B <branch> origin/main`, never from ambient HEAD), and assert
`git diff --stat origin/main <branch>` against the **remote** base before pushing — per-file spot
checks all passed on 2026-08-24 and the scope diff is what caught it. Pruning the 30 merged local
branches and realigning local `main` is a five-minute hygiene task **for Rick**, not an agent's
unilateral `reset --hard`.

### 4.4 What actually activates with tenant N+1

The original dormant-HIGH set (F4, F15, F16, F20, F34) is **closed**, and `comicstore` has been live
on production since 2026-07-15 without any of them firing. The § 13 header saying otherwise is
Phase-4-era text. **What genuinely activates today is a shorter, different list:**

| ID | What activates |
|---|---|
| **F72** | A real-customer tenant's `register-customer` emails arrive **founding-branded**. Already a documented tenant-2 real-customer go-live prerequisite in `tenant-onboarding-runbook.md` — `comicstore` has stayed pilot/seeded precisely so this has not fired. |
| **F131** | Every tenant's catalog comes from **one shop's** Lunar/PRH portal access, on one machine, with a service-role key that cannot be distributed. Invisible at one paying tenant; at five it *is* the product. Carries an unresearched terms-of-use question about populating other retailers' systems from one retailer account's download — **flagged, not researched, not claimed.** |
| **F145** | Each tenant subdomain is an **individually provisioned** Cloudflare Pages custom hostname. Fine at two; not self-service — which is why Phase 6 S0 is still a real gate. |

### 4.5 Phase 6's eligibility gate is undecided

The stub records the *requirement* (a PRH **or** Lunar retailer account) as settled and the
**verification method as open**, with three options: self-attestation (lowest friction, weakest),
manual operator review (strongest, reintroduces a human, contradicts "6-minute self-serve"), and
automated verification (ideal but "likely infeasible — no known public retailer-verification API").
The stub's recommended hybrid is a **recommendation, not a decision**. **Sub-deploy 6.2 cannot be
written until this is answered, and answering it is a Rick scoping call.** It does **not** block W8,
which measures serving model and cost only.

### 4.6 Environment asymmetry at the grant layer — known, benign, and worth remembering

Measured this session across three tables (`app_settings`, `catalog`, `preorders`): an anon
publishable-key read returns **`[]` HTTP 200 on production** (table SELECT granted to `anon`; RLS
filters every row) and **`42501 permission denied` HTTP 401 on staging** (no table-level SELECT grant
at all). **Neither leaks data** — § 13 already documents exactly this for `tenants` and records both
as safe. The planning consequence: **staging is stricter than production at the grant layer, so a
staging test of anon posture does not prove production's.** That matters the moment Phase 6 adds an
anon-callable surface (`check_slug_available`), and it is why W1's `app_settings` check needs a
service-role read.

### 4.7 Testing discipline that has already cost this project real time

- **F133 variant (b) means a green targeted run is not evidence.** Until W4 lands, any executor using
  the documented "targeted while iterating, full suite as the gate" workflow may be reading a pass
  that only holds because of spec ordering.
- **The smoke suite tests the *deployed* site.** Stage [2/2]'s `baseURL` is
  `https://staging.pulllist.pages.dev/`, so a pre-push run exercises the **previous** build for any
  `app.js` / `*.html` / `style.css` change. Push, confirm the new bytes at the **plain** URL (a
  cache-busted query string is a different Cloudflare cache key — that produced a false green on
  2026-08-06), then run the suite. Use `-SkipPlaywright` for the pre-push baseline.
- **Green ≠ verified.** The suite covers only what has specs. Two production defect clusters shipped
  through green suites in July/August because the paths had no coverage at all. For anything new,
  probe the deployed thing and read what comes back.
- **A verification step that cannot fail is not a verification step.** Before asking Rick to run any
  check, state what its output looks like when the thing has **failed**. W8 is the item most exposed
  to this.
- **`.ps1` BOM stripping.** Any agent edit to a PowerShell script must restore the UTF-8 BOM, or
  PowerShell 5.1 silently swallows later code into string literals with no parse error —
  `run-smoke.ps1` skipped its entire Playwright stage and exited 0 this way on 2026-07-16.

### 4.8 Staging's small dataset hides production-scale problems — three instances; treat it as a rule

F147 (16 marks on staging vs **519** on production), F115's S6 predicate (32 vs **859**, where
staging's whole-population and never-arrived-subset predicates nearly coincided while production's
differ by ~90%), and the print-catalog page-count trap (staging 4 publishers / 638 rows / 15 pages vs
production 14 / 1,534 / 35). **A count measured on staging says nothing about production.** Re-measure
against the environment you actually mean, immediately before any write.

---

## 5. Questions for Rick

> **✅ ALL EIGHT ANSWERED 2026-08-29 — see § 0 for the answers and their effect on the plan.**
> Retained below as written, because the *reasoning* behind each question is what a future session
> needs in order to know whether a decision still applies or its premises have moved.

Each of these can change the plan. **[BLOCKING]** marks the ones where an executor cannot start that
item without an answer.

1. **[BLOCKING for W5]** For the MailerLite webhook path in `register-customer`: **remove it
   entirely, or leave it present-but-dead?** The plan doc says "removed/dead"; the function's own
   comment says "retained harmlessly." It is a **per-tenant** mechanism, so removing it removes it for
   `comicstore` and every future tenant — and `tenant-onboarding-runbook.md` Step 4 still tells an
   operator to configure it. Related: was PR #95's **prod write-smoke + 24-hour soak** actually
   completed? That box is unticked and the deploy log stops at "soak in progress."

2. **Is production currently open to customers?** `CLAUDE.md` says Maintenance Mode is still ON and
   `order_deadline` cleared as of 2026-08-28, and it cannot be verified from an agent session. If it
   is already done, W1 collapses to a one-line doc correction; if not, it is the most urgent item
   here.

3. **After this workstream: Phase 6, the Founding Partner launch — or neither, and we keep shipping
   small features for the Book Stop?** Three independent tracks; all three read as "next." Phase 6
   has **no recorded demand signal** (two tenants, one explicitly demo). The Founding Partner offer is
   priced (2026-08-19) and waiting on an email-identity fix. And the project's actual behaviour for
   six weeks has been the third option. W8 exists to put the Phase 6 cost model in your hands before
   you answer — **but this answer determines whether W4–W11 are worth doing at all.**

4. **Which is the founding tenant's canonical front door now — the apex, or
   `rjbookstop.pulllist.app`?** `apex-landing-tenant-subdomains.md` says founding stays on the apex
   and a branded subdomain is the **premium tier** lever. Since then the hostname was provisioned,
   native signup shipped on it, and the print CTA puts it on **paper handed to customers**. The
   tiering doc has not been revisited. Product positioning, not a technical question.

5. **Is `weekly-pipeline-consolidation-plan.md` still a live workstream, or should it be closed as
   superseded?** Its § 6 items 1–3 are done; F135 (W3) moves the producer's trigger into the send
   workflow, which removes most of what items 4–5 were protecting against. If the Apps Script path is
   already dormant in practice, the honest move is to retire the doc rather than carry a NOT-STARTED
   token indefinitely.

6. **[BLOCKING for W6]** Can you confirm the Cloudflare custom-hostname inventory for the
   `pulllist.app` Pages project — which hostnames exist, and (if the audit log still holds it) when
   `rjbookstop.pulllist.app` was provisioned?

7. **F135's two observation cycles take ~2 calendar weeks** (S3 and S5 each need one unattended
   Tuesday). Acceptable, or would you rather the interim `.env` mitigation stand indefinitely and F135
   be deferred? The mitigation works, but it depends on a human remembering to comment out a variable
   before every ad-hoc import.

8. **The legacy GitHub Pages rollback surface** (`mrcyberrick.us/comic-preorder/`) — retire it, or
   keep it warm? Open since 5.5 S6 (2026-07-15), where your call was "keep warm and revisit in a
   future session." This is that future session asking, again.

---

## 6. Suggested Next Steps — REVISED 2026-08-29 after § 0

Nothing here is blocked and nothing is time-critical. Rough order of value:

1. **Write W2** — the three-promotion doc record, with an explicit yes/no on whether PR #142 owes
   finding **F148**. Then add the `CLAUDE.md`-entry step to `/promote-prod` so the gap stops
   reopening every week. Doc-only, direct to `staging`.
2. **Read `order_deadline` live** (service-role, or the admin Settings screen). § 0 Q2 confirmed the
   store is open but not whether Step 7 ran, and W4 is defined against that value.
3. **Reproduce F133 variant (b)** — run `21-arrival-resolution` targeted, then in the full suite,
   and confirm the pass/fail disagreement still holds. That disagreement *is* the finding, and
   confirming it is step one of W4.
4. **Draft W5** against `supabase/functions/register-customer/index.ts` (read from disk, not from
   this doc's line numbers) plus the four other surfaces the item lists. Q1 is answered, so this is
   executor work now, not a decision.
5. **Gather the Cloudflare inventory** (W6's three-step how-to) whenever Rick has ten minutes in the
   dashboard — read-only, changes nothing.
6. **Schedule October's import** as an attended session with F147's mark half and F146's clear half
   named as the two things to watch (`/schedule-gate`). This is the one genuinely dated item left in
   the whole plan.

*(Steps 2, 3, 5 and 7 of the original list are superseded: W1 is done, W3 and W8 are deferred.)*

---

## References

- `CLAUDE.md` — § Current Migration Phase (open-findings pointer table; the Maintenance Mode
  residual), § Standard Deployment Workflow, § Credential Safety, § Anti-Drift Rules, § Smoke Test
  Suite, § F125.
- `docs/technical-reference.md` — canonical schema; **§ 13 is the only record of finding detail**
  (last verified against live 2026-08-18).
- `docs/pre-phase-6-consolidation.md` — predecessor; its C1 S6-predicate reasoning trail is worth
  keeping.
- `docs/f135-decouple-feed-publish.md` — W3's runbook (§ 3 interim mitigation, § 5 S1–S5, § 6 gates).
- `docs/native-customer-signup.md` — W5's owner (§ S5 + Completion Criteria).
- `docs/tenant-onboarding-runbook.md` — W5's Steps 4/7 and W6's target (Step 3 hostnames).
- `docs/monthly-catalog-refresh.md` — W1's Steps 7/8 and W9's target.
- `docs/phase-6-self-service-signup.md` — W8's target (§ S0).
- `docs/weekly-pipeline-consolidation-plan.md` — § 5 Q5's subject.
- `docs/test-infra-maintenance-f91-f95-f103.md` — W4's template.
- `docs/phase-5.0-pre-phase-5-housekeeping.md` — the precedent for this workstream's shape.

---

**Last updated:** 2026-08-29 — written as a planning pass, then revised the same day after Rick
answered all eight § 5 questions (§ 0). Re-derived from live repo and branch state rather than from
the predecessor's narrative; three undocumented production promotions and a diverged local `main`
were found in the process. **Direction as of this revision: Shape D — small features for the
founding tenant — with W2/W4/W5/W6/W7/W9/W11 as the supporting cleanup and W3/W8/W10 deferred but
recorded.**
