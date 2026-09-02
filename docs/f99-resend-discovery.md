# F99 — Resend discovery session (evaluate before committing)

**STATUS:** **COMPLETE — GREEN, 2026-09-02.** Resend measured clean on K1–K6; `pulllist.app` verified (parent domain, DKIM+SPF both aligned); D7 answered **NO** (parent does not cover subdomains on Resend — the opposite of MailerSend's S0 result); **addressing DECIDED same day: flat `noreply@pulllist.app`** (§ 3 reconsideration triggered immediately by D7, not deferred to tenant #2 as originally assumed). Migration plan written: `docs/f99-resend-migration.md` (not started, not executed). | ~~Q1: per-tenant subdomain~~ **SUPERSEDED by D7 — see § 3** | staging=n/a, no code touched | **prod=untouched, confirmed** — MailerSend domain/token/secrets/Edge Functions all unchanged | findings=F99,F72,F148,F145 (no ID consumed — external platform evaluation)

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
| Open/click tracking **off by default** | Resend docs, read 2026-09-02 | **CONFIRMED, with a nuance research missed.** Not literally "off" — it doesn't exist at all unless a `tracking_subdomain` is explicitly configured (`open_tracking`/`click_tracking` API fields "only applied if a `tracking_subdomain` is configured"). D2's sandbox send tripped K1+K3 because `resend.dev` — Resend's own domain — already has one configured; D6 on our own domain, with no tracking subdomain set, came back completely clean. |
| Send API injects no `List-Unsubscribe` (Broadcasts do) | Resend docs | **CONFIRMED** — absent on every send, sandbox and real domain alike (D2, D6) |
| Free: 3,000/month, **100/day**, 1 domain | Third-party summaries | **CONFIRMED** — live dashboard read (D1) showed exactly `3,000` monthly / `100` daily; domain count confirmed behaviorally by D7 (a second, unverified domain is flatly rejected) |
| Subdomains need **separate** verification | Resend docs | **CONFIRMED — this is D7, the pivotal test.** `noreply@rjbookstop.pulllist.app` rejected with `403 validation_error: "The rjbookstop.pulllist.app domain is not verified"`, parent `pulllist.app` verified throughout. Opposite of MailerSend's S0 result. Drove the addressing decision — see § 3 |
| Pro $20/mo → 10 domains | Third-party | **Not independently re-confirmed this session** (not needed — flat addressing was chosen, see § 3) |
| Request shape keeps `Authorization: Bearer` and `html`; `from` is a **string** not an object | Resend docs | **CONFIRMED from a real 200 (D2) and the docs (D3)** — `POST https://api.resend.com/emails`, `Authorization: Bearer re_...`, body `{from, to, subject, html}`, `from` a plain string, success response `{"id": "<uuid>"}` |
| `<slug>.pulllist.app` authenticates with strict DKIM alignment | **MEASURED 2026-09-02** (via Brevo, § 9) | **Provider-independent asset — carries over.** (Moot for Resend's own migration now that addressing is flat, but the underlying DNS/alignment mechanics it demonstrated generalize.) |
| A different provider needs no parallel-run purchase | **MEASURED 2026-09-02** (§ 9) | **Established, and reconfirmed this session** — the whole Phase 1/2 probe ran on Resend's free tier with MailerSend serving production throughout, zero downtime |
| Daily/monthly cap is metered in requests (like MailerSend) or emails | not previously researched | **NEW, measured 2026-09-02 (D8): emails, not requests.** Docs: *"Both sent and received emails count towards these quotas."* Corroborated by the existence of a 100-email batch endpoint that would trivially bypass a request-based cap if the metering worked that way. Consequence: batching would ease Resend's 10 req/sec rate limit but does **not** raise the 100/day ceiling — different lever than MailerSend's request-based cap |
| Pay-as-you-go overage ($0.90/1,000 emails) available on Free tier | Rick, from Resend's pricing page, 2026-09-02 | **CORRECTED 2026-09-02** — verified against `resend.com/pricing`: overage billing is a **paid-tier (Pro/Scale) feature only**, not available on Free. Real and worth keeping for whenever F148 is fixed for real (metered cost beats a hard wall), but doesn't change today's free-tier picture |

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

> ### ✅ RESOLVED 2026-09-02 — D7 came back negative, and the collision this section predicted for
> **tenant #2 turned out to be immediate, not deferred**
>
> § 3's table above was written assuming D7 might land either way, and its "collide at tenant #2"
> framing implicitly assumed the free case ("one domain slot is enough right now, free either way")
> held regardless of D7's answer. **It doesn't.** D7 (§ 4) sent from
> `noreply@rjbookstop.pulllist.app` with only the parent verified and got a flat rejection —
> `403 validation_error: "The rjbookstop.pulllist.app domain is not verified."` Resend does **not**
> cover subdomains under a verified parent (the opposite of MailerSend's S0 result this whole
> per-tenant design was modeled on).
>
> **Consequence: sending as `noreply@rjbookstop.pulllist.app` today, at tenant #1, would need a
> SECOND verified domain — unavailable on the free tier's single slot** — not a tenant-#2 problem
> deferred into the future. The collision is now, not later.
>
> **Decision (Rick, 2026-09-02): ship flat `noreply@pulllist.app`.** Already proven clean in D6 —
> `dkim=pass` exact match (`d=pulllist.app`), **SPF also aligned** (a bonus neither §3 nor the K4
> criterion required), `dmarc=pass`, and domain verification covers arbitrary local parts (D6 test
> 2). Per-tenant subdomains remain available later as a **paid** choice (Pro, $20/mo) whenever the
> reputation segmentation is worth it — not spent today with one real tenant that doesn't need it.
> This is the standing "prioritize the free tier, don't auto-upgrade" rule doing exactly what it was
> written to do.

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

> ✅ **MEASURED 2026-09-02 (Rick, live dashboard).** Free tier: **3,000/month, 100/day** — confirmed
> exactly as researched (dashboard showed `3 / 3,000` monthly, `3 / 100` daily after the first three
> sends). Domain count confirmed **behaviorally, not from a dedicated dashboard read**: D7 shows a
> second, unverified domain is flatly rejected, consistent with 1. Daily-cap unit resolved at D8, from
> documentation rather than the dashboard: **emails, not requests** (`"Both sent and received emails
> count towards these quotas"`). Pro-trial offer and the exact Pro/domain-count figures were **not**
> independently re-confirmed this session — not needed, since the addressing decision (§ 3) landed on
> flat, free-tier `noreply@pulllist.app`.

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

> ⚠️ **MEASURED 2026-09-02 — K1 and K3 BOTH TRIPPED ON THE SANDBOX, read from delivered Gmail
> headers (Show original), not the API's `{"id":...}`.**
>
> | Check | Result |
> |---|---|
> | K1 — link rewriting | **TRIPPED.** Both `href`s (including the fake reset URL) rewritten through `vw9jhtlx.r.us-east-1.awstrack.me/L0/...` — an **Amazon SES** click-tracking redirector, visible via `d=amazonses.com` DKIM, the `amazonses.com` Return-Path, and `X-SES-Outgoing` (Resend sends over AWS SES under the hood) |
> | K2 — List-Unsubscribe | **Not tripped.** Absent from both messages |
> | K3 — tracking pixel | **TRIPPED.** A `1×1 display:none` beacon injected into **both** messages, including the "plain, no links" baseline that never had an `<img>` in its source HTML |
>
> **This did not end the session — it triggered a re-verification, not an immediate remediation
> (CLAUDE.md's own discipline).** The trip was traced to `resend.dev` — Resend's own shared sandbox
> domain — having a tracking subdomain already configured, something only the domain owner can set
> up. Confirmed three independent ways before proceeding to Phase 2: (1) Resend's own API docs state
> `open_tracking`/`click_tracking` are **"only applied if a `tracking_subdomain` is configured"**;
> (2) the live Add Domain screen for `pulllist.app` showed the Tracking Subdomain field **empty**,
> with both tracking checkboxes **greyed out/disabled** while empty; (3) D6 — the real test, sending
> from our own verified domain with no tracking subdomain ever configured — came back **completely
> clean**, no rewritten links, no pixel. **K1/K3 do not trip on our own domain.** Full reasoning
> below this callout, kept for the record since it was a real mid-session judgment call, not a
> foregone conclusion.

#### D3 — Confirm the real request shape (~5 min)

From the successful D2 calls, record the **exact** working payload — `from` as string vs object,
field names, auth header, success response. § 10 of the parent plan states this from research and
explicitly flags it unconfirmed. The migration will be written against whatever this records.

**→ V3**

> ✅ **CONFIRMED 2026-09-02, from a real `200`.** `POST https://api.resend.com/emails`,
> `Authorization: Bearer re_...`, `Content-Type: application/json`, body
> `{"from": "...", "to": "...", "subject": "...", "html": "..."}` — `from` a plain string exactly as
> research predicted, no object shape. Success response: `{"id": "<uuid>"}`. Matches § 10's research
> exactly; nothing to correct.

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

> ✅ **MEASURED 2026-09-02 — clean, K5 does NOT trip.** Domain added via the dashboard (a
> Sending-scoped API key can't manage domains — `401 restricted_api_key` — a real, documented
> permission-scoping trap, same class as MailerSend's domain-scoped tokens but self-explaining here).
> Tracking Subdomain left blank. Resend returned three records, all scoped to **new names**, none
> touching the apex:
>
> | Record | Name | Value | External resolution before publish |
> |---|---|---|---|
> | DKIM | `resend._domainkey` | TXT, raw `p=` public key (not a CNAME, unlike MailerSend's `ms1`/`ms2` pair) | **NXDOMAIN** |
> | Return-Path/SPF | `send` (MX) | `feedback-smtp.us-east-1.amazonses.com`, priority 10 | **NXDOMAIN** |
> | Return-Path/SPF | `send` (TXT) | `v=spf1 include:amazonses.com ~all` | **NXDOMAIN** |
>
> All three resolved via `dns.google` before publishing — no collisions. **K5: apex SPF
> untouched, confirmed both before and after (D5).** Apex TXT re-read at D4:
> `v=spf1 include:_spf.mailersend.net include:spf.efwd.registrar-servers.com ~all` — byte-identical
> to what's on file; Resend's SPF requirement lands entirely on `send.pulllist.app`, a name that
> didn't exist. **MX interaction: none** — the apex's 5 existing Namecheap-forwarding MX records
> (`eforward1-5.registrar-servers.com`) are a different name than Resend's `send.pulllist.app` MX.
> SPF lookup budget: N/A to the apex (separate name, separate evaluation context); the new record's
> own single `include:amazonses.com` is a standard, well-tested AWS SES include.

#### D5 — Publish DNS + verify in Resend (~15 min + propagation)

**Rick publishes in Cloudflare** — the established pattern for anything touching live
infrastructure, matching how DB migrations run. Additive records only.

Verify **externally** via `dns.google`, not the Cloudflare dashboard — a proxied CNAME looks correct
in the UI and does not expose the real target to an outside query (the S2 lesson). Then confirm
Resend's dashboard reports the domain verified.

**→ V5**

> ✅ **MEASURED 2026-09-02 — both halves green.** Rick published all three records in Cloudflare
> (DNS-only — TXT/MX records carry no proxy toggle by nature). Re-resolved externally via
> `dns.google` post-publish: all three return exactly the values requested, apex SPF re-confirmed
> byte-identical and untouched. Resend's dashboard independently reported: **"Domain verified: Your
> domain is ready to send emails."**

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

> ✅ **MEASURED 2026-09-02 — BOTH mechanisms aligned, beating the plan's own stated expectation.**
> Two real sends read from Gmail `Show original`:
>
> 1. `noreply@pulllist.app` (the flat identity): `dkim=pass header.i=@pulllist.app header.s=resend`,
>    `DKIM-Signature: ... d=pulllist.app` — **exact match** to the From domain, not merely aligned.
>    `spf=pass smtp.mailfrom=...@send.pulllist.app` — `send.pulllist.app`'s organizational domain is
>    `pulllist.app`, so this is **also aligned** under DMARC's relaxed mode (`_dmarc.pulllist.app`
>    carries no `adkim=`/`aspf=`, confirmed earlier in the parent plan's own S0 work). `dmarc=pass
>    (p=NONE)`.
> 2. `f99-coverage-check@pulllist.app` (never registered as a sender): identical signing, **delivered
>    successfully** — domain verification covers arbitrary local parts, same as Brevo, unlike
>    MailerSend's `#MS42207`.
>
> **No tracking artifacts in either message** — real-world confirmation of the D2/D4 hypothesis: with
> no tracking subdomain configured, nothing is injected. **K1/K3 do not apply to this domain.**
>
> This matches MailerSend's current double-mechanism margin (K4 satisfied, plus bonus SPF alignment
> the criterion didn't even require) rather than settling for Brevo's DKIM-only result.

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

> ⚠️ **MEASURED 2026-09-02 — REJECTED, research confirmed, and unlike `#MS42207` this is not a
> mystery.** Exact response:
> ```
> HTTP 403 — validation_error
> "The rjbookstop.pulllist.app domain is not verified. Please, add and verify your domain on
> https://resend.com/domains"
> ```
> **The parent does NOT cover the subdomain.** Opposite of MailerSend's S0 result. Consequence,
> worked through in § 3: sending as `noreply@rjbookstop.pulllist.app` would need a **second**
> verified domain, unavailable on the free tier's single slot — the collision § 3 originally expected
> at tenant #2 turns out to be immediate. **Decision (Rick, 2026-09-02): ship flat
> `noreply@pulllist.app`** — already proven clean in D6 — and treat per-tenant subdomains as a future
> paid-tier (Pro, $20/mo) choice, not a default. See § 3's resolution block for the full reasoning.

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

> ✅ **MEASURED 2026-09-02, from documentation (dashboard doesn't expose the metering unit
> directly).** Resend's daily/monthly cap is metered in **emails**, not API requests — docs state
> *"Both sent and received emails count towards these quotas,"* corroborated by the existence of a
> 100-email `/emails/batch` endpoint that would trivially blow through a request-based cap if the
> metering worked that way. **F148's one-sentence shape under Resend:** with `notify-customers`'
> code unchanged (one email per request), the numeric daily ceiling stays **~100/day — the same as
> today under MailerSend, F148 is NOT dissolved** — but the monthly ceiling rises **500 → 3,000
> (6×)**, and batching (were it ever built) would ease Resend's 10-req/sec rate limit without raising
> the 100/day wall itself, a different lever than it would have been under MailerSend's request-based
> cap. At today's real volume (~30 founding-tenant customers, ~50–150 emails/month per the parent
> plan § 1), neither cap binds under either provider. **Bonus fact, verified against Resend's own
> pricing page, not Free-tier-relevant today but useful for whenever F148 is actually fixed:**
> pay-as-you-go overage ($0.90/1,000 emails) exists, but only on paid (Pro/Scale) tiers — not Free.

---

## 5. Verification gates

| Gate | Assertion | How it fails | Result |
|---|---|---|---|
| **V1** | Free-tier limits recorded **from the live dashboard**, and § 2's researched row marked confirmed or corrected | A limit is quoted from research rather than read | ✅ **GREEN** — 3,000/month, 100/day confirmed live |
| **V2** | **K1, K2, K3 all measured from delivered headers** on a sandbox send | Any of the three trips → session ends here, by design | ⚠️ **K1+K3 tripped on sandbox**, traced to `resend.dev`'s own tracking-subdomain config, resolved by D6 re-test on our own domain (clean). K2 never tripped |
| **V3** | A real, working request payload recorded verbatim | Shape still inferred from docs | ✅ **GREEN** — confirmed from a real `200` |
| **V4** | Every requested DNS name resolved live; collisions enumerated; **explicit yes/no on whether the apex SPF must change** | Any name unchecked, or K5 unanswered | ✅ **GREEN** — 3/3 names NXDOMAIN pre-publish; **apex SPF: NO, does not need to change** |
| **V5** | Domain verified in Resend **and** records confirmed at an external resolver | Verified only in the Cloudflare UI | ✅ **GREEN** — both confirmed |
| **V6** | `dkim=pass` with `d=` aligned to the From domain, read from a delivered header; SPF alignment recorded either way | Trusting the API's success response | ✅ **GREEN, exceeds expectation** — DKIM exact match AND SPF aligned (Brevo only had DKIM) |
| **V7** | **Parent-covers-subdomain answered by a real send from `noreply@rjbookstop.pulllist.app` with only the parent verified** — and, if it delivered, `d=` confirmed aligned. This gate decides whether § 3's chosen identity stays on the free tier | Answered from documentation; or delivery accepted without reading `d=` | ⚠️ **REJECTED** — `403 validation_error`, exact text recorded (§ 4 D7). Addressing decision changed to flat as a direct result (§ 3) |
| **V8** | F148's shape under Resend stated with measured numbers | Stated as a general claim | ✅ **GREEN** — emails-metered, ~100/day unchanged, 500→3,000/month, batching doesn't raise the daily wall |

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

> ✅ **ACTUAL OUTCOME 2026-09-02: GREEN, ~1.5 hours, both phases run.** Cleaner than either prior
> candidate — MailerSend blocked on an unexplained `#MS42207`, Brevo rejected on link rewriting,
> Resend delivered with **stronger measured alignment than Brevo achieved** (DKIM+SPF both aligned,
> not DKIM-only) and an **explicit, self-explaining** answer at the one place it said no (D7's
> subdomain rejection names exactly what's wrong, unlike MailerSend's unresolved mystery). One
> mid-session correction, handled by re-verification rather than either blind acceptance or a
> premature RED: K1/K3 tripped on the sandbox, traced to `resend.dev`'s own tracking-subdomain setup,
> and confirmed clean on our own domain in D6. One real design consequence: D7's rejection forced § 3's
> addressing decision from *direction* to *committed*, immediately rather than at a deferred tenant-#2
> milestone — landing on flat `noreply@pulllist.app`, per the standing "prioritize the free tier"
> rule.

---

## 10. Completion criteria

**A discovery session is done when the question is answered and written down — not when the tests
pass.** A RED result that is fully recorded is a complete session; a GREEN result left in scrollback
is not.

- [x] **V1–V8 recorded**, each with its measured value — session did **not** end early; K1/K3 tripped
      at V2 but were re-verified as sandbox-specific and resolved before Phase 2, per the CLAUDE.md
      "surprising result triggers re-verification, not immediate remediation" discipline
- [x] **Every § 2 row marked RESEARCH** is now either **confirmed** or **corrected** against a live
      measurement, and § 2 updated in place — one correction (tracking's real trigger condition) and
      one net-new row (daily-cap unit, D8) added beyond what was originally researched
- [x] **K1–K6 each explicitly evaluated** — K1/K2/K3 clean on our own domain (D6); K4 exceeded
      (DKIM+SPF both aligned); K5 does not trip (D4/D5, apex SPF untouched, confirmed externally
      before and after); K6 does not trip (monthly 6× better, daily a wash)
- [x] **D7's answer recorded** — rejected; exact text: `403 validation_error — "The
      rjbookstop.pulllist.app domain is not verified. Please, add and verify your domain on
      https://resend.com/domains"`
- [x] **This doc's STATUS token** updated to `COMPLETE — GREEN, 2026-09-02`
- [x] **Parent plan `f99-sender-domain-consolidation.md` § 10** updated from *direction* to
      *decision*
- [x] **`CLAUDE.md` F99 row** updated, and a "Last completed work" entry added
- [x] **GREEN — migration plan written as a new F99 sub-step doc**: `docs/f99-resend-migration.md` —
      **not started, not executed, in this session**
- [ ] ~~If RED: fallback recorded~~ — N/A, result is GREEN
- [x] **Production confirmed untouched** — nothing in this session touched Supabase, any Edge
      Function, MailerSend's dashboard/domain/token, or the `MAIL_FROM_EMAIL`/`MAIL_FROM_NAME`
      secrets. Every action was against a brand-new Resend account and Cloudflare DNS additions on
      names MailerSend never consults
- [x] **`/wrap-up` run** (CLAUDE.md § Anti-Drift Rules)

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

- **`docs/f99-resend-migration.md`** — new, written this session. The GREEN result's follow-up plan:
  not started, not executed.

**Last updated:** 2026-09-02 — **session run end to end, GREEN.** All 8 work items (D1–D8) executed
live against a real Resend account, `pulllist.app` verified, alignment measured, addressing decided
(flat, § 3). Production never touched. Migration plan written as a new sub-step doc, not started.
