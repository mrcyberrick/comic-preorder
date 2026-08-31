# F99 — consolidate the transactional sending identity onto `pulllist.app`

**STATUS:** PLANNED — S0 gate OPEN, no work started | staging=— | prod=— | findings=F99,F72,F148,F145

**Status:** **Planned, not started. S0 is a blocking question, not a task** — its answer selects
between two materially different architectures, and no other step can be sized until it is answered.
Written 2026-08-31 during a multi-tenant onboarding spec review.

> **This is not a new plan. It is F99's own recorded fix direction, steps (3)–(5).** Steps (1) and (2)
> are already **done**: the DMARC reporting-authorization record was published 2026-07-25, and the
> 4-week aggregate-report read completed 2026-08-20 (13 messages, 100% pass, three major receivers,
> every sending source identified). F99 § "Fix direction" explicitly requires that read to happen
> *before* any `from:` address changes. **That prerequisite is satisfied.** Do not re-derive it.

---

## 0. Why this is worth doing now

Three things converged that were not all true when F99 was filed on 2026-07-25:

1. **F99's blocker cleared.** `p=quarantine` was held pending MailerLite retirement; that trigger
   **fired 2026-08-30** when the webhook path was removed platform-wide (native-signup § S5). F99 is
   unblocked and unscheduled.
2. **A second tenant is being scoped**, and transactional email is one of its two hard blockers (the
   other is F131's import path). Every customer-facing email currently hardcodes
   `noreply@mrcyberrick.us` with the founding tenant's name, street address and phone.
3. **A free-tier constraint was measured 2026-08-31 that F99 never considered** — and it may
   invalidate F99's own recommendation. See § 1.

**F99's recorded design decision, which this plan inherits rather than re-opens:** per-tenant
subdomain sender (`<slug>.pulllist.app`), **not** flat `noreply@pulllist.app`. Its reasoning: Brevo's
marketing sender already sits at `rjbookstop.pulllist.app` and is fully authenticated, so the
tenant-slug shape is established; and F72's per-tenant email branding requires a per-tenant sending
identity anyway. *"A flat apex sender would have to be torn out and redone when F72 lands."*

---

## 1. The new constraint — MailerSend free tier (measured 2026-08-31)

| Limit | Value | Consequence here |
|---|---|---|
| **Domains** | **1** | **The binding constraint. See S0.** |
| Emails / month | 500 | Founding tenant is ~50–150. Roughly 3 tenants of that size. |
| **Daily API requests** | **100** | Binds *before* the monthly cap — **F148**, filed 2026-08-31. |
| Extra usage | **None** | No overage billing. Quota exhaustion is a hard stop, not a cost. |
| Templates | 1 | **Moot** — verified 2026-08-31 that no function uses MailerSend templates; all six POST inline HTML. The one hosted template was unused, drifted from production, and has been deleted. |
| Activity retention | 1 day | Cannot investigate a delivery complaint older than 24h. |
| User seats | 1 | No tenant admin can ever hold their own login — an F131-shaped single-operator dependency. |

**The tension this creates with F99's recommendation.** One verified domain and a per-tenant
subdomain scheme are in direct conflict at tenant #2: if the single slot is spent on
`rjbookstop.pulllist.app`, a second tenant has **no sending identity at all**.

---

## 2. S0 — the blocking question (a dashboard check, not a build)

> **Does MailerSend's single verified domain authorize *subdomains* as `From` addresses?**

Verify `pulllist.app`, then attempt a send as `noreply@rjbookstop.pulllist.app`. Read the **received
message headers**, not the API's HTTP status.

**This must be checked, not reasoned about.** DKIM selectors are per-domain and ESPs differ on
whether a verified organizational domain covers its subdomains. Both answers are plausible.

> ⚠️ **A 200 from the API proves nothing.** F99's own 2026-08-20 probe records this trap: a
> `reset-password` call returns `{"success":true}` unconditionally so it never leaks whether an
> address exists. **Only the delivered headers settle it** — `dkim=pass`, `spf=pass`, `dmarc=pass`.
> Same lesson as F105 ("a verification step that cannot fail is not a verification step").

### Decision tree

| S0 answer | Architecture | Verdict |
|---|---|---|
| **Subdomains covered** | Verify `pulllist.app` once. Send as `noreply@<slug>.pulllist.app` per tenant. | **Best case.** F99's per-tenant direction works on the free tier and scales to N tenants on one slot. |
| **Subdomains NOT covered** | One slot = one identity. Either `rjbookstop.pulllist.app` (founding only, blocks tenant 2) or flat `noreply@pulllist.app` with per-tenant **display names**. | **F99's recommendation becomes a paid-tier feature.** Flat apex + display name is the free-tier answer, and F99's "would have to be torn out later" warning is then an accepted, priced cost — not an oversight. |

**Do not proceed past S0 without an answer.** Everything below is written for the covered case and
flagged where the uncovered case diverges.

---

## 3. The cutover constraint — there is no parallel run

With one domain slot, `mrcyberrick.us` must be **removed** from MailerSend before the replacement can
be added (unless the account permits holding a second domain unverified — **check during S0**).
Between removal and a working new sender, **all transactional mail is down**: magic links, invites,
approvals, password resets.

**F99's step (4) as written — "update the six `from:` sites, staging first, then promote" — would put
a code deploy inside that outage window.** This plan does not do that.

### The fix: parameterize before you migrate

Make the sender an Edge Function **secret**, not a literal, and deploy that change *while the old
domain is still live and verified*. The domain switch then becomes a secret flip with **no code
deploy in the risk window**, and it is instantly reversible.

**This is also the first step of F72**, which needs exactly the same six files to read tenant context
instead of literals. One edit, two findings advanced. That is why the founding tenant is the right
place to start: with the secret set to today's values, the founding tenant's email must come out
**byte-identical to current production** — a built-in regression control.

---

## 4. Work breakdown

### S0 — Serving-model gate (no writes, no code)

Answer § 2's question against the live MailerSend account. Confirm whether a second domain can be
held unverified. **HALT and re-plan if subdomains are not covered.**

### S1 — Parameterize the sender (code, no behavior change)

Replace the six hardcoded `from:` literals with values read from Edge Function secrets
(`MAIL_FROM_EMAIL`, `MAIL_FROM_NAME`), defaulting to today's values so nothing changes:

| Function | Line |
|---|---|
| `approve-customer/index.ts` | 163 |
| `invite-customer/index.ts` | 109 |
| `notify-customers/index.ts` | 187 |
| `register-customer/index.ts` | 143 |
| `reset-password/index.ts` | 72 |
| `send-my-list/index.ts` | 243 |

Deploy to staging, verify a real delivered message is unchanged, then production. **Fully reversible
and independently useful** — it stands on its own even if S2/S3 never run.

### S2 — Pre-publish DNS in Cloudflare (no MailerSend change)

Add the DKIM + Return-Path records the new domain will need, **before** touching MailerSend, so
verification is near-instant when the slot frees. Mirrors what `mrcyberrick.us` carries today
(`mlsend2._domainkey`, Return-Path `mta` → `mailersend.net`), adapted to the chosen domain.

> ⚠️ **The zone trap, from F99 and worth repeating because it already cost a session.** The DMARC
> reporting-authorization record lives at `pulllist.app._report._dmarc.mrcyberrick.us` — its parent
> zone is **`mrcyberrick.us` (GoDaddy)**, not `pulllist.app` (Cloudflare). Adding a record like that
> in Cloudflare produces something that *looks* right in the UI and does nothing. Check which zone
> each record's parent actually belongs to.

### S3 — Cutover window (the only risky step)

Remove `mrcyberrick.us` from MailerSend → add the new domain → confirm verified → flip the two
secrets. No code deploy. Keep the old DNS records in place for rollback.

> ⛔ **Do not schedule this inside a catalog import window.** `import.js` Step 7 calls
> `notify-customers`; a migration mid-import means the monthly notification silently fails. **The next
> import gate is Fri 2026-09-25** (October catalog, `trig_01FQesEHRh9XdRXgwASFJoh7`). Cut over well
> clear of it.

### S4 — Verify alignment, then consider `p=quarantine`

Confirm the new domain authenticates on **both** mechanisms before retiring anything. **Publish
`p=quarantine` only after alignment is proven** — doing it during a sender migration risks
quarantining the store's own mail. F99 also requires a separate DNS check first: `litesrv._domainkey`
gone from `mrcyberrick.us`, MailerSend its sole sender there.

---

## 5. Verification gates

| Gate | Assertion | How |
|---|---|---|
| **V1** | S0 answered from **delivered headers**, not an API status | Send to a real mailbox; read `Authentication-Results` |
| **V2** | S1 changes nothing observable | Deliver a staging `reset-password`; `From` byte-identical to pre-change |
| **V3** | All six functions read the secret; **zero** `mrcyberrick.us` literals remain in `supabase/functions/` | `grep -rn "mrcyberrick" supabase/functions/` returns 0 |
| **V4** | New domain verified in MailerSend before any secret flip | Dashboard state + a test send |
| **V5** | `dkim=pass` **and** `spf=pass` **and** `dmarc=pass` on the new domain | Received headers, Gmail + one Microsoft mailbox |
| **V6** | Brevo's existing `rjbookstop.pulllist.app` signing still passes | Trigger/inspect one newsletter send; **F98 thumbnails unaffected** |
| **V7** | A real magic-link login completes end-to-end post-cutover | Sign in on staging, then production |
| **V8** | Founding-tenant email body unchanged | Visual diff against a pre-cutover copy |

**V6 is not optional.** MailerSend and Brevo would both sign for `rjbookstop.pulllist.app`. Different
DKIM selectors make that fine in principle — but F99 records that **DKIM is the sole load-bearing
mechanism for Brevo** (no aligned SPF, no margin), so it gets checked rather than assumed.

---

## 6. Out of scope — stop and ask

- **Retiring `mrcyberrick.us` as a domain.** F99 is explicit: only the *sending identity* moves. It
  remains the GitHub Pages rollback surface at `/comic-preorder/` and serves F98 newsletter
  thumbnails at `/weekly-pull-feed/`. `index.html:273`'s `pulllist@mrcyberrick.us` contact address is
  a **mailto, not a sender** — a separate decision.
- **F72's body-copy substitution** (name / address / phone per tenant). S1 enables it; this plan does
  not do it.
- **F148's bulk-endpoint change.** Same account, different problem.
- **Brevo / marketing mail.** Already on `rjbookstop.pulllist.app` and authenticated.
- **Paid-tier migration.** Revisit after this work, per Rick 2026-08-31.

---

## 7. Rollback

S1 is a normal revert. S3 is the only step needing a real plan: keep `mrcyberrick.us`'s DNS records
published throughout, so rollback is re-adding it in MailerSend and flipping the secrets back — no
deploy, no DNS wait. **Do not delete the old records until S4 has been green for at least one full
monthly cycle.**

---

## 8. Open questions for Rick

1. **S0's answer** — the whole shape depends on it.
2. If subdomains are **not** covered: accept flat `noreply@pulllist.app` with per-tenant display
   names on free tier, or price the paid tier now?
3. Cutover window preference, given it must clear 2026-09-25.
4. `p=quarantine` — publish at S4, or hold until after a second tenant is live?

---

## Reference

- **F99** (`docs/technical-reference.md` § 13) — the finding this executes; steps (1)–(2) done, the
  2026-08-20 sender inventory, the GoDaddy-zone trap, the reputation note (no warm-up concern).
- **F72** — per-tenant email branding; S1 is its shared first step.
- **F148** — the daily-API-cap limit on the same account.
- **F145** — no wildcard DNS on `pulllist.app`; each hostname is individually provisioned. Relevant
  if per-tenant sending subdomains are chosen.
- `CLAUDE.md` § Current Migration Phase — the 2026-09-25 October import gate.

**Last updated:** 2026-08-31 (written; S0 not yet run)
