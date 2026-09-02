# F99 — Resend discovery session (evaluate before committing)

**STATUS:** PLANNED — not started | **Q1 ANSWERED 2026-09-02 (Rick): per-tenant `noreply@<slug>.pulllist.app`, FREE TIER PRIORITIZED, flat `noreply@pulllist.app` is the reconsideration point — § 3** | staging=n/a | prod=untouched by design | findings=F99,F72,F148,F145

**What this is:** a **discovery** session to decide whether Resend becomes PULLLIST's transactional
provider. It produces a **measured yes/no**, not a migration. Written 2026-09-02 after Brevo was
evaluated and rejected (`f99-sender-domain-consolidation.md` § 9) and Rick set Resend as the
direction (§ 10).

**Everything currently recorded about Resend is RESEARCH, not measurement.** No account exists, no
send has been made, no header has been read. This session's entire job is to replace that research
with evidence — the same standard § 9 applied to Brevo.

---

## 0. The governing principle: cheapest kill test first

**Brevo died on Test C — link rewriting — and Test C could have been run before anything else.**
Three sends, a domain already authenticated, and a header read all happened *before* the one check
that actually decided the outcome.

This plan is sequenced so the disqualifiers are tested **before any DNS is published, before any
domain is verified, and before any decision is made.** Resend lets you send from its own
`onboarding@resend.dev` sandbox with **zero DNS work**, which means:

> **Phase 1 can disqualify Resend in about ten minutes, with no DNS record published, no domain
> verified, and nothing to roll back.**

Phase 2 — the DNS and alignment work — runs **only if Phase 1 passes**.

---

## 1. Kill criteria — stated BEFORE the tests, deliberately

Written down first so the result is read honestly rather than rationalised. **Any one of these ends
the evaluation**, exactly as link rewriting ended Brevo's.

| # | If this is true | Verdict |
|---|---|---|
| **K1** | Links in transactional mail are rewritten through a tracking redirector by default **and** it cannot be turned off | **WALK.** Identical to Brevo's disqualifier (§ 9) |
| **K2** | `List-Unsubscribe` / `List-Unsubscribe-Post` is injected into transactional sends and cannot be suppressed | **WALK.** A one-click unsubscribe on a password reset |
| **K3** | An open-tracking pixel is injected and cannot be turned off | **WALK** — same class, same reasoning |
| **K4** | DKIM cannot be aligned to the sending domain (`d=` matching the `From` domain) | **WALK.** DMARC would rest on nothing |
| **K5** | Verifying the sender domain requires **modifying** the existing apex SPF record in a way that could break MailerSend's current `spf=pass` | **STOP AND ASK.** Not automatically fatal, but it reintroduces exactly the live-mail risk this provider was chosen to avoid |
| **K6** | The free tier's real sending ceiling is **worse** than MailerSend's today (500/month, 100 API req/day) | **RECONSIDER** — the migration would be a downgrade |

**K1–K3 are all testable in Phase 1 with no DNS.** That is the whole design.

---

## 2. What is known vs. what is merely researched

Honest accounting, so the session knows what it is actually verifying.

| Claim | Source | Status |
|---|---|---|
| Open/click tracking **off by default** | Resend docs, read 2026-09-02 | **RESEARCH — this is K1/K3, test it** |
| Send API injects no `List-Unsubscribe` (Broadcasts do) | Resend docs | **RESEARCH — this is K2, test it** |
| Free: 3,000/month, **100/day**, 1 domain | Third-party summaries | **RESEARCH — read the live dashboard** |
| Subdomains need **separate** verification | Resend docs | **RESEARCH — and it drives cost; measure it** |
| Pro $20/mo → 10 domains | Third-party | **RESEARCH** |
| Request shape keeps `Authorization: Bearer` and `html`; `from` is a **string** not an object | Resend docs | **RESEARCH — confirm from a real 200/201** |
| `<slug>.pulllist.app` authenticates with strict DKIM alignment | **MEASURED 2026-09-02** (via Brevo, § 9) | **Provider-independent asset — carries over** |
| A different provider needs no parallel-run purchase | **MEASURED 2026-09-02** (§ 9) | **Established** |

---

## 3. Sender shape — DECIDED: per-tenant subdomain, free tier prioritized

This is a **decision, not a discovery**, and it changes what Phase 2 costs. Carried forward from
`f99-sender-domain-consolidation.md` § 10.

| | Flat `noreply@pulllist.app` | Per-tenant `noreply@<slug>.pulllist.app` |
|---|---|---|
| Domain slots needed | **One, forever, at any tenant count** | **One per tenant** (Resend verifies subdomains separately) |
| Resend cost | **Free tier sufficient** | Free covers **tenant #1 only**; Pro **$20/mo** at tenant #2 |
| Reputation segmentation | Shared across tenants | Per tenant |
| F72 branding | **Unaffected** — branding is the `from` **name** + body copy, secret-driven since S1 | Unaffected |
| F145 interaction | None — no new hostname | Each sending subdomain is another individually-provisioned name |

**The `<slug>` shape was originally recommended because Brevo was already sitting there** (§ 13 F99,
now flagged REASSESS). That particular reason is gone. A per-tenant sending *domain* is not required
for per-tenant *branding* — it buys reputation segmentation.

### ✅ DECIDED 2026-09-02 (Rick): start with `noreply@<slug>.pulllist.app`; **prioritize the free tier**

**Flat `noreply@pulllist.app` is the reconsideration point, not the starting point.** Recorded
verbatim so it is not re-litigated: *"Start with `noreply@<slug>.pulllist.app` and reconsider at
`noreply@pulllist.app` — prioritize the free tier."*

**These two instructions are compatible today and collide at tenant #2**, which is worth stating
plainly rather than discovering later. One real sending tenant exists (`rjbookstop`; `comicstore` is
demo/test, never a real customer), so **one domain slot is enough right now** — free either way. The
collision arrives only when a second real tenant needs its own sending identity.

**This makes D7 the pivotal test of the session, not a curiosity.** Everything depends on one
unmeasured question: *does verifying the parent `pulllist.app` authorize sending from
`<slug>.pulllist.app`?*

| D7 outcome | What it means for Rick's instruction |
|---|---|
| **Parent covers subdomains** | **Best case, and both instructions hold forever.** One free slot carries per-tenant senders at any tenant count. Nothing to reconsider, ever |
| **Parent does NOT cover subdomains** (what research predicts) | Free covers **tenant #1 only**. At tenant #2: either Pro at **$20/mo**, or switch to flat. **"Prioritize the free tier" resolves this toward flat** unless Rick says otherwise at the time |

**So verify the PARENT domain in Phase 2, not the subdomain** — strictly more informative, and it
costs nothing extra. Verifying `pulllist.app` tests the free-forever hypothesis *and* leaves the flat
fallback already working in the same slot. Verifying `rjbookstop.pulllist.app` directly would answer
neither question and would spend the one free slot on the narrower option. **D4/D5 are written
accordingly.**

**The honest cost of starting with the subdomain**, recorded so it is a known trade rather than a
surprise: if D7 comes back negative and tenant #2 later forces the switch to flat, customers will
have seen the sending domain change **twice** (`mrcyberrick.us` → `<slug>.pulllist.app` →
`pulllist.app`), and the DNS + verification work is done twice. That is the price of deferring the
decision, and deferring is a legitimate choice at one tenant — but it is not free.

**Standing rule from "prioritize the free tier": do NOT auto-upgrade to Pro.** If the discovery
finds the chosen shape needs a paid plan, that is a **stop-and-ask**, not a purchase.

Brevo's marketing sender stays at `rjbookstop.pulllist.app` regardless; nothing about that changes.

---

## 4. Work breakdown

### PHASE 1 — Disqualifiers, no DNS, nothing to roll back

#### D1 — Account + real limits (~10 min, no send)

Create a Resend account. **Read the live dashboard**, do not trust § 2's researched row:

- domains allowed on free; emails per day; emails per month; API rate limit
- whether a Pro trial is offered
- whether the daily cap counts **emails** or **API requests** (this decides F148's shape under
  Resend — MailerSend's cap is *requests*, which is why `notify-customers`' per-recipient loop binds)

> **Do not add a domain yet.** D2 must run on the sandbox sender first.

**→ V1**

#### D2 — The three kill tests, on Resend's sandbox sender (~15 min)

Send to `rssedivec@gmail.com` from `onboarding@resend.dev` — **no domain verification, no DNS**.
Mirror § 9's Test C exactly, since that is the test that decided Brevo.

1. **Plain send** — a body with no links. Baseline; confirms the API works and the account sends.
2. **Link send** — a body carrying two links, one shaped like a real reset URL
   (`https://pulllist.app/forgot-password.html?token_hash=FAKE_NOT_REAL&type=recovery`) and one
   plain CTA.

**Then read the delivered message in Gmail via `Show original`** — never the API's `201`, per § 2 of
the parent plan and the standard the S3 rollback used. Check, in this order:

| Check | Kill criterion | What a failure looks like |
|---|---|---|
| Are the `href`s still `pulllist.app`? | **K1** | rewritten to a tracking host |
| Is there a `List-Unsubscribe` header? | **K2** | present, especially with `-Post: One-Click` |
| Is there an injected `<img>` beacon in the body? | **K3** | a 1×1 pixel our HTML never contained |

**If K1, K2 or K3 trips: STOP. Record the result, close Resend, and report.** Do not proceed to
Phase 2, do not publish DNS. That is the entire point of this ordering.

**→ V2** *(the gate that decides whether the rest of the session happens at all)*

#### D3 — Confirm the real request shape (~5 min)

From the successful D2 calls, record the **exact** working payload — `from` as string vs object,
field names, auth header, success response. § 10 of the parent plan states this from research and
explicitly flags it unconfirmed. The migration will be written against whatever this records.

**→ V3**

---

### PHASE 2 — Only if Phase 1 passed

#### D4 — DNS reconnaissance, before publishing anything (~20 min)

**Add the PARENT domain `pulllist.app`** — not `rjbookstop.pulllist.app`, per § 3's reasoning — and
**read the records Resend demands without publishing them.** Then, for each requested record, resolve the name live against an external resolver
(`dns.google`) — the S2 method, which catches both collisions and Cloudflare proxying:

- **Collision check.** Is the name NXDOMAIN today, or does something already live there? S2's own
  three names were all NXDOMAIN, which is why publishing was safe.
- **The K5 question, and it is the important one:** does Resend want a **new** record (e.g. scoped
  under a `send.` subdomain), or does it want the **apex SPF modified**? The live apex SPF is
  `v=spf1 include:_spf.mailersend.net include:spf.efwd.registrar-servers.com ~all` — **2 lookups,
  and MailerSend's live `spf=pass` depends on it.** A new record is additive and safe; editing that
  one is the only genuinely risky act in this whole session.
- **MX interaction.** `pulllist.app` already has MX records (Namecheap forwarding — parent plan
  § 8 Q5). If Resend asks for an MX on a subdomain, confirm it does not disturb them.
- **SPF lookup budget** if the apex must change: currently 2 of a maximum 10.

**Halt and ask if K5 trips.** Do not edit the apex SPF inside a discovery session.

**→ V4**

#### D5 — Publish DNS + verify in Resend (~15 min + propagation)

**Rick publishes in Cloudflare** — the established pattern for anything touching live
infrastructure, matching how DB migrations run. Additive records only.

Verify **externally** via `dns.google`, not the Cloudflare dashboard — a proxied CNAME looks correct
in the UI and does not expose the real target to an outside query (the S2 lesson). Then confirm
Resend's dashboard reports the domain verified.

**→ V5**

#### D6 — Send from our own domain + read alignment (~15 min)

Repeat D2's sends, now from the verified domain, plus one address-coverage test:

1. `noreply@pulllist.app` — the verified parent itself. **This is the flat FALLBACK identity**, not
   the intended one (§ 3); proving it works is what makes the fallback real rather than assumed.
2. **An address never registered as a sender** — does domain verification cover arbitrary local
   parts? (It did on Brevo; MailerSend's `#MS42207` is precisely the failure where it did not.)

Read delivered headers and record: `dkim=pass` with **`d=` matching the From domain** (K4),
`spf=pass` and **whether the Return-Path is aligned**, and `dmarc=pass`.

> **Set the expectation now so the result is not over-read:** Brevo passed DMARC on **DKIM alone**,
> SPF unaligned. That is acceptable — DMARC needs one aligned mechanism. MailerSend today has
> **both** aligned. If Resend also lands DKIM-only, that is a real but tolerable reduction in
> margin, not a failure. **Record which it is; do not treat DKIM-only as a kill.**

**→ V6**

#### D7 — ⭐ THE PIVOTAL TEST: does the parent cover `<slug>.pulllist.app`? (~10 min)

**This is the test the session exists to run**, because § 3's decision rests entirely on it. Send
from **`noreply@rjbookstop.pulllist.app`** — the identity Rick chose — with **only the parent
`pulllist.app` verified** and that subdomain never separately added to Resend.

- **Delivers, DKIM aligned** → **best case.** One free domain slot carries per-tenant senders at any
  tenant count. Rick's chosen identity and "prioritize the free tier" both hold permanently, and the
  flat reconsideration never has to happen. Check `d=` in the header — delivery alone is not enough;
  it must be **aligned to the subdomain or its parent**, or K4 is in play.
- **Rejected** → research confirmed. Per-tenant subdomains cost **one slot each**, so tenant #2 means
  Pro at **$20/mo** or a switch to flat. Per § 3's standing rule, that is a **stop-and-ask**, not an
  upgrade. `noreply@pulllist.app` (proven in D6) is the free fallback, and the parent stays verified
  in the one slot either way — so **nothing is wasted by this outcome.**

**Record the exact rejection text if it fails** — `#MS42207` taught that a provider's own error
string is the most useful artifact when a send is refused, and the S3 session had to reconstruct it
afterwards.

**→ V7**

#### D8 — F148 under Resend, with numbers (~10 min)

- Confirm from D1 whether the daily cap counts emails or requests.
- Check whether a **batch endpoint** exists, whether it is on the free tier, and how it is metered.
  MailerSend's per-request cap is what makes `notify-customers`' serial loop a ceiling at ~100
  recipients; if Resend caps *emails*, batching changes rate-limit pressure but not the ceiling.
- Measure **real current volume** from production: recipient count for a monthly blast, plus
  password resets and registrations per month.

Output: one sentence stating F148's actual shape under Resend, with numbers. **Do not fix F148
here** — different finding, different session.

**→ V8**

---

## 5. Verification gates

| Gate | Assertion | How it fails |
|---|---|---|
| **V1** | Free-tier limits recorded **from the live dashboard**, and § 2's researched row marked confirmed or corrected | A limit is quoted from research rather than read |
| **V2** | **K1, K2, K3 all measured from delivered headers** on a sandbox send | Any of the three trips → session ends here, by design |
| **V3** | A real, working request payload recorded verbatim | Shape still inferred from docs |
| **V4** | Every requested DNS name resolved live; collisions enumerated; **explicit yes/no on whether the apex SPF must change** | Any name unchecked, or K5 unanswered |
| **V5** | Domain verified in Resend **and** records confirmed at an external resolver | Verified only in the Cloudflare UI |
| **V6** | `dkim=pass` with `d=` aligned to the From domain, read from a delivered header; SPF alignment recorded either way | Trusting the API's success response |
| **V7** | **Parent-covers-subdomain answered by a real send from `noreply@rjbookstop.pulllist.app` with only the parent verified** — and, if it delivered, `d=` confirmed aligned. This gate decides whether § 3's chosen identity stays on the free tier | Answered from documentation; or delivery accepted without reading `d=` |
| **V8** | F148's shape under Resend stated with measured numbers | Stated as a general claim |

**A verification step that cannot fail is not a verification step.** Before running each, ask what
its output looks like when the thing has *failed* — the discipline CLAUDE.md records from the
SQL-gate incident. V2's failure mode is a rewritten `href`; V6's is a `d=` that does not match.

---

## 6. Risk and rollback

**This session cannot break production, and that is structural rather than careful.**

| Step | Touches production? | Rollback |
|---|---|---|
| D1–D3 | **No.** New account, sandbox sender, no DNS | Delete the account |
| D4 | **No.** Reads only | — |
| D5 | **Additive DNS only.** New names MailerSend does not consult | Delete the records |
| D6–D8 | **No.** Sends from a domain nothing in production uses | — |

**MailerSend is not touched at any point** — not its domain, not its API token, not the
`MAIL_FROM_EMAIL` / `MAIL_FROM_NAME` secrets, not the six Edge Functions. Production continues
sending from `noreply@mrcyberrick.us` throughout, exactly as it does today.

**Maintenance Mode is NOT needed.** S3 required it because the cutover removed the working sender;
this session adds a second, unused provider alongside. **If a step in this plan seems to need
Maintenance Mode, that step has escaped the plan — stop and ask.**

The one exception is **K5**: if Resend requires modifying the apex SPF, that single act touches a
record MailerSend's live `spf=pass` depends on. It is a stop-and-ask, not a discovery step.

---

## 7. Open questions for Rick

1. ~~**Flat `noreply@pulllist.app` or per-tenant `noreply@<slug>.pulllist.app`?**~~ — ✅ **ANSWERED
   2026-09-02 (Rick): start with the per-tenant subdomain; flat is the reconsideration point;
   prioritize the free tier.** See § 3 for the decision, the tenant-#2 collision it defers, and why
   D7 is now the pivotal test. *(This plan had recommended flat; Rick chose otherwise and the
   reasoning is recorded rather than re-argued.)*
2. **Publish DNS for a provider not yet committed to?** D5 asks for real Cloudflare records for
   something that may still be rejected. They are additive and deletable, and nothing consults them
   until an Edge Function changes — but it is live infrastructure, so it is Rick's call, not an
   assumption. *(Phase 1 needs none of this, so this question can wait until V2 is green.)*
3. **Budget ceiling — partly answered.** "Prioritize the free tier" (Q1) sets the default: **do not
   auto-upgrade.** Still open, and only if D7 comes back negative: at tenant #2, is **Pro at $20/mo**
   worth keeping per-tenant senders, or does the free tier win and the identity goes flat? **Not
   needed for this session** — it is a tenant-#2 decision, and D7 may make it moot.
4. **Timing.** The **October catalog import gate is Fri 2026-09-25** and is an attended session with
   an admin-ordering freeze. This session is independent of it and low-risk, but it should not be
   run *during* that window. Before or well after.
5. **Does this replace S3, or defer it?** If Resend passes, F99's S3/S4 become Resend steps and the
   MailerSend `#MS42207` mystery is abandoned unresolved — which is fine, but it should be a
   decision rather than a drift. If Resend fails, S3's paid-tier path (§ 8 Q7, **$35 Starter**) is
   still there.

---

## 8. Out of scope — stop and ask

- **Any Edge Function change.** The six `from:` sites are already secret-driven (S1). This session
  writes no code.
- **Any secret change.** `MAIL_FROM_EMAIL` / `MAIL_FROM_NAME` stay exactly as they are.
- **Any MailerSend change** — domain, token, or plan. It keeps serving production untouched.
- **The migration itself.** A green result produces a *decision and a follow-up plan*, not a cutover.
- **F148's fix.** D8 measures its shape; fixing it is separate work.
- **F72's body-copy substitution.** Unchanged by provider choice.
- **Retiring `mrcyberrick.us`.** Only the sending identity is ever in question (parent plan § 6).

---

## 9. Expected outcome

**~1–1.5 hours if Phase 1 passes; ~25 minutes if it does not** — and the fast failure is a success
of this plan's ordering, not a wasted session.

The session produces one of:

- **GREEN** — Resend measured clean on K1–K4, domain verified, alignment recorded, subdomain
  coverage and F148 shape known. Output: update this doc to COMPLETE, update the parent plan's § 10
  from *direction* to *decision*, and write the migration plan as a new F99 sub-step.
- **RED** — a kill criterion tripped. Output: record it here with the same rigour § 9 gave Brevo,
  update the parent plan's § 10, and fall back to § 8 Q7 (MailerSend Starter, $35 for one month).

**Either way the result gets written down before the session closes.** A negative result that is not
recorded gets re-tested — which is exactly why § 9 exists.

---

## 10. Completion criteria

**A discovery session is done when the question is answered and written down — not when the tests
pass.** A RED result that is fully recorded is a complete session; a GREEN result left in scrollback
is not.

- [ ] **V1–V8 recorded**, each with its measured value — *or* the session ended early at **V2** with
      the tripped kill criterion and its evidence recorded
- [ ] **Every § 2 row marked RESEARCH** is now either **confirmed** or **corrected** against a live
      measurement, and § 2 updated in place
- [ ] **K1–K6 each explicitly evaluated**, or marked "not reached" with the reason
- [ ] **D7's answer recorded** — the delivered `d=` value if it sent, or the provider's **exact
      rejection string** if it did not
- [ ] **This doc's STATUS token** updated to `COMPLETE` or `REJECTED` with the date and outcome
- [ ] **Parent plan `f99-sender-domain-consolidation.md` § 10** updated from *direction* to
      *decision*
- [ ] **`CLAUDE.md` F99 row** updated, and a "Last completed work" entry added
- [ ] **If GREEN:** the migration plan is written as a **new** F99 sub-step doc — **not started, not
      executed, in this session**
- [ ] **If RED:** the fallback is recorded (parent plan § 8 Q7 — MailerSend Starter, $35/mo)
- [ ] **Production confirmed untouched** — MailerSend domain, API token, `MAIL_FROM_EMAIL` /
      `MAIL_FROM_NAME` secrets, and all six Edge Functions verified unchanged
- [ ] **`/wrap-up` run** (CLAUDE.md § Anti-Drift Rules)

---

## Reference

- **`docs/f99-sender-domain-consolidation.md`** — the parent plan. **§ 9** (Brevo evaluated and
  rejected, with the three tests and their headers) and **§ 10** (provider selection, the Resend
  direction) are prerequisites for this session. **§ 4 S3** records the failed MailerSend cutover.
- **F99** (`docs/technical-reference.md` § 13) — the finding. Its per-tenant-subdomain
  recommendation is flagged **REASSESS**; § 3 above is where that gets settled.
- **F148** — the daily-cap ceiling on `notify-customers`; D8 re-derives its shape.
- **F72** — per-tenant email branding. Unaffected by provider choice; relevant to § 3.
- **F145** — no wildcard DNS on `pulllist.app`; each hostname is individually provisioned. **Now
  directly relevant, since per-tenant sending subdomains won Q1 — but do not over-apply it.** F145 is
  about **web** hostnames (Cloudflare Pages custom hostnames serving a tenant front door). A
  **sending** subdomain needs only DNS records (DKIM/SPF/Return-Path); it does **not** need a Pages
  custom hostname, and no web front door has to exist for mail to authenticate. Conflating the two
  would invent per-tenant provisioning work that mail does not require.
- `CLAUDE.md` § Current Migration Phase — the 2026-09-25 October import gate (Q4).

**Last updated:** 2026-09-02 — written. Not started.
