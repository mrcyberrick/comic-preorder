# F99 — consolidate the transactional sending identity onto `pulllist.app`

**STATUS:** PLANNED — **S0 ANSWERED 2026-08-31**; **S1 DONE on staging 2026-08-31** (`eff9793`); **S2 DONE 2026-09-01** (DNS pre-published, SPF merged at cutover); **S3 ATTEMPTED 2026-09-01, ROLLED BACK, CAUSE UNRESOLVED — read § 4 S3 before retrying**; **Brevo transactional EVALUATED AND REJECTED 2026-09-02 (§ 9)**; **second free MailerSend account CLOSED — ToS violation (§ 8 Q9)**; **DIRECTION SET 2026-09-02: Resend, pending a live probe (§ 10)**; S4 not started | staging=`eff9793` | prod=`mrcyberrick.us` (unchanged — attempt rolled back) | findings=F99,F72,F148,F145,F149

**Status:** **S0 is CLOSED. The architecture is settled: verify `pulllist.app`, send per-tenant
`noreply@<slug>.pulllist.app`, on the single free-tier domain slot.** F99's recorded per-tenant
subdomain direction is viable on the free tier — no paid tier required, nothing to tear out later.
**S1 is the next step and has not started.** Written 2026-08-31 during a multi-tenant onboarding
spec review.

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
| **Domains** | **1** | **The binding constraint — CONFIRMED HARD in the dashboard 2026-08-31.** A second domain cannot be added even unverified, so there is **no parallel run** (§ 3) and verifying a per-tenant subdomain is never correct (§ 2). |
| Emails / month | 500 | Founding tenant is ~50–150. Roughly 3 tenants of that size. |
| **Daily API requests** | **100** | Binds *before* the monthly cap — **F148**, filed 2026-08-31. |
| Extra usage | **None** | No overage billing. Quota exhaustion is a hard stop, not a cost. |
| Templates | 1 | **Moot** — verified 2026-08-31 that no function uses MailerSend templates; all six POST inline HTML. The one hosted template was unused, drifted from production, and has been deleted. |
| Activity retention | 1 day | Cannot investigate a delivery complaint older than 24h. |
| User seats | 1 | No tenant admin can ever hold their own login — an F131-shaped single-operator dependency. |

**The tension this created with F99's recommendation — ✅ RESOLVED by S0, 2026-08-31.** The concern
was that one verified domain and a per-tenant subdomain scheme conflict at tenant #2. They do **not**,
because a verified *parent* domain covers its subdomains and signs with the parent (§ 2). **Verify the
apex `pulllist.app`; every `<slug>.pulllist.app` is then covered by that one slot.** The conflict only
existed under the assumption that each subdomain needed its own verification — which was measured
false.

---

## 2. S0 — the blocking question — ✅ **ANSWERED 2026-08-31: YES, subdomains are covered**

> ### ✅ S0 RESULT — measured, not inferred
>
> **MailerSend accepts a subdomain `From` under a verified parent domain, signs it with the PARENT
> domain, and it authenticates on both mechanisms.** Probe sent as
> `noreply@probe.mrcyberrick.us` under the verified `mrcyberrick.us`; delivered to Gmail; headers read
> directly:
>
> ```
> Authentication-Results: mx.google.com;
>   dkim=pass  header.i=@mrcyberrick.us   header.s=mlsend2;
>   dkim=pass  header.i=@mailersend.net   header.s=ms1;
>   spf=pass   smtp.mailfrom=bounce-…@mta.mrcyberrick.us;
>   dmarc=pass (p=NONE sp=NONE dis=NONE)  header.from=mrcyberrick.us
> ```
>
> **The decisive detail:** the actual `From:` was `noreply@probe.mrcyberrick.us`, yet Google reports
> `header.from=mrcyberrick.us` and `sp=NONE` — it found no DMARC record on the subdomain, walked up to
> the **organizational domain**, and applied its subdomain policy. Both mechanisms then aligned under
> relaxed matching:
>
> | | Signed / envelope domain | `From:` domain | Aligned? |
> |---|---|---|---|
> | DKIM | `d=mrcyberrick.us` (**parent**) | `probe.mrcyberrick.us` | ✅ org domain matches |
> | SPF | `mta.mrcyberrick.us` | `probe.mrcyberrick.us` | ✅ org domain matches |
>
> **Therefore:** one verified `pulllist.app` will sign for `rjbookstop.pulllist.app` and every future
> `<slug>.pulllist.app`, on the single free-tier slot. **F99's per-tenant direction is viable on the
> free tier.** § 8 Q2 (accept a flat sender, or pay?) is **moot**.
>
> **`p=quarantine` (S4) will not break this** — `adkim`/`aspf` are absent, so alignment is relaxed, and
> policy *strength* does not change alignment *mode*.
>
> **It also retroactively confirms skipping S-1 was right:** MailerSend actively signed with
> `mlsend2`, the very selector flagged as deprecated. It works.
>
> ⚠️ **One trap this probe hit, worth carrying:** the first attempt returned **422** and looked like a
> "not covered" answer. It was the placeholder recipient (`to.0.email`) left unreplaced — a *different*
> 422. **The status code alone could not distinguish the two; only the response body and then the
> delivered headers could.** A 422 was nearly recorded as an architectural finding.

*Original question and decision tree retained below for the reasoning trail.*

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

> ✅ **The domain to verify is `pulllist.app` in BOTH branches — settled 2026-08-31, one less
> decision.** The 1-domain limit is confirmed hard (dashboard, see § 1), and that makes verifying
> `rjbookstop.pulllist.app` **never correct**: it would spend the single slot on one tenant and leave
> every other tenant with no sending identity at all. **S0 therefore changes only how mail is
> addressed, not which domain is verified.**

| S0 answer | Addressing | Verdict |
|---|---|---|
| **Subdomains covered** | `noreply@<slug>.pulllist.app` per tenant, under the one verified `pulllist.app` | **Best case.** F99's per-tenant direction works on the free tier and scales to N tenants on one slot. |
| **Subdomains NOT covered** | Flat `noreply@pulllist.app` for all tenants, differentiated by per-tenant **display name** only | **F99's recommendation becomes a paid-tier feature.** Flat apex + display name is the free-tier answer, and F99's "would have to be torn out later" warning becomes an accepted, priced cost — not an oversight. |

**Do not proceed past S0 without an answer.** Everything below is written for the covered case and
flagged where the uncovered case diverges.

### How to answer it without touching production (2026-08-31)

**`mrcyberrick.us` is already verified, and subdomain authorization is a property of the platform,
not of a particular domain.** So probe it there: send with `from` = `noreply@probe.mrcyberrick.us`
via the raw API and read the result. **Nothing is removed, no outage window, and the destructive-test
problem this plan originally assumed simply does not arise.**

- `202 Accepted` → subdomains are covered.
- `422` (from.email domain must be verified) → they are not.
- This is the one place a raw API status *is* evidence — MailerSend's API returns real errors. The
  "success proves nothing" trap applies to **our** `reset-password` function, which swallows them by
  design. Confirm authentication separately in the delivered `Authentication-Results` header.
- ✅ **DMARC alignment is RELAXED — measured live 2026-08-31, one risk retired before the probe.**
  `_dmarc.pulllist.app` reads `v=DMARC1; p=none; rua=mailto:hello@mrcyberrick.us` — **no `adkim=`,
  no `aspf=`, no `sp=`**, so alignment defaults to relaxed and subdomains inherit `p=none`. That is
  precisely what lets parent-domain DKIM (`d=pulllist.app`) align with a subdomain `From`
  (`rjbookstop.pulllist.app`). **The covered case is therefore viable on the DNS side** — the only
  remaining unknown is whether MailerSend *accepts* the send. A strict (`s`) value would have forced a
  per-subdomain DMARC record; it does not apply.

### DNS providers — verified live 2026-08-31, because the registrar misleads

| Domain | Registrar | **Authoritative DNS (where records go)** |
|---|---|---|
| `pulllist.app` | **Namecheap** | **Cloudflare** — `morgan`/`tia.ns.cloudflare.com` |
| `mrcyberrick.us` | — | **GoDaddy** — `ns77`/`ns78.domaincontrol.com` |

**Registrar ≠ DNS host.** `pulllist.app` is *bought* at Namecheap but *served* by Cloudflare, so every
record in S2 goes in **Cloudflare**, not Namecheap. F99 recorded this in 2026-07-25 and it is
unchanged. (The apex SPF's `spf.efwd.registrar-servers.com` include is a Namecheap **forwarding**
service referenced from the Cloudflare-hosted zone — a service pointer, not evidence of where DNS
lives. See S2's open question.) S-1's DKIM CNAMEs are for `mrcyberrick.us` and **do** belong in
GoDaddy.

---

## 3. The cutover constraint — there is no parallel run

With one domain slot, `mrcyberrick.us` must be **removed** from MailerSend before the replacement can
be added. **Confirmed by Rick 2026-08-31: only one domain can exist at a time** — checked in the
dashboard the same day, a second domain cannot be held even unverified, so the hoped-for parallel
path does not exist. Between removal and a working new sender, **all transactional mail is down**:
magic links, invites, approvals, password resets.

> **Mitigation proposed by Rick 2026-08-31: toggle Maintenance Mode ON for the duration of the
> cutover window.** Checked against the actual code before relying on it — real, but partial.
> `checkMaintenanceMode()` covers `catalog.html`/`mylist.html`/`arrivals.html`/`subscriptions.html`
> (all four already-authenticated), but **not** `index.html`'s native registration flow
> (`register-customer`) or `forgot-password.html` (`reset-password`) — the two paths an anonymous
> visitor is most likely to hit during the window. Filed as **F149** (`docs/technical-reference.md`
> § 13); Rick's direction is to close that gap as its own scoped session before S3 leans on the
> toggle as a real safety net. Two things the toggle can't help with either way, worth remembering
> when S3 is scheduled: admin-triggered functions (`invite-customer`, `approve-customer`,
> `create-paper-customer`) bypass Maintenance Mode by design — the only control is not taking admin
> actions during the window — and `notify-customers` is import-triggered, unaffected by the toggle,
> already covered by "don't schedule inside an import window" below.

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

### S-1 — Update `mrcyberrick.us`'s DKIM to the current selectors — ⛔ **SKIP (Rick, 2026-08-31)**

> ⛔ **DO NOT DO THIS unless the migration is shelved for a quarter or more.** It was originally
> written "do this FIRST"; **Rick correctly challenged why we would fix DNS on a domain S3 removes**,
> and the risk math does not support it. Kept here, demoted, so the reasoning is not re-derived.
>
> **The measurements that decide it (live, 2026-08-31):**
> - `mlsend2._domainkey.mrcyberrick.us` is a **live CNAME** to `mlsend2._domainkey.mailersend.net` and
>   is signing today. DKIM is **not broken** — the dashboard's orange icon means "migrate to the new
>   selectors," not "you have no DKIM."
> - **`_dmarc.mrcyberrick.us` is `p=none`.** Receivers take no action even on a total DMARC failure.
> - SPF and Return-Path are green and aligned via `mta.mrcyberrick.us`, so **if `mlsend2` vanished
>   tomorrow, DMARC would still pass on SPF alone.**
>
> So skipping it costs *redundancy* on a domain being removed from MailerSend, under a policy that
> enforces nothing. **It is also NOT a prerequisite for the S0 probe** — the probe asks whether
> MailerSend accepts a subdomain `From`, which is independent of selector state, and the domain is
> verified and sending production mail regardless.
>
> **It would only matter if** this work is shelved long enough that `mrcyberrick.us` stays the live
> sender for months, *and* MailerSend retires `mlsend2` in that window, *and* SPF alignment also
> breaks. Compound and unlikely.
>
> *(A factual correction carried from the first draft: `mlsend2` is a **CNAME**, not a legacy TXT
> selector. MailerSend is moving from one selector to two — presumably for key rotation — not changing
> record type. The `ms1`/`ms2` shape below is still what a newly-added domain will be asked for, which
> is the part that matters for S2.)*

**Original item retained below.**

**Discovered in the dashboard 2026-08-31 and unrelated to this migration — it is a live issue on the
domain carrying every transactional email today.** SPF and Return-Path show green; **DKIM does not**:

```
⟳ DKIM — Your DKIM record needs updating.
   Add the two new CNAME records below. No need to delete your existing one.
   ms1._domainkey.mrcyberrick.us  →  ms1._domainkey.mailersend.net
   ms2._domainkey.mrcyberrick.us  →  ms2._domainkey.mailersend.net
```

**Why it is not merely housekeeping.** F99's 2026-08-20 report read established that the transactional
path is **the only sender aligned on both DKIM and SPF** — Brevo and MailerLite are DKIM-only with no
SPF fallback. That double alignment is the margin. "No need to delete your existing one" means nothing
is broken today, but the `mlsend2` TXT selector is visibly being deprecated by the vendor, on the one
path that has margin to lose. Losing it would drop transactional mail to SPF-only alignment — still
passing, but with no redundancy, and that matters if `p=quarantine` is ever published (S4).

Two CNAMEs in **GoDaddy** (`mrcyberrick.us`'s zone — not Cloudflare). Non-destructive and additive:
the existing record stays. **Do this before the S0 probe** so the probe measures a healthy domain.

### S0 — Serving-model gate (no writes, no code)

**This is now the FIRST step** — S-1 was skipped (see above), and it was never a prerequisite.
Answer § 2's question against the live MailerSend account, via the zero-risk probe in § 2. **HALT and
re-plan if subdomains are not covered** — the domain to verify is `pulllist.app` either way, but the
addressing scheme and everything F72 builds on top of it changes.

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

**Target shape** — module-level constants, defaulting to today's literals so an unset secret changes
nothing:

```ts
const MAIL_FROM_EMAIL = Deno.env.get('MAIL_FROM_EMAIL') ?? 'noreply@mrcyberrick.us'
const MAIL_FROM_NAME  = Deno.env.get('MAIL_FROM_NAME')  ?? "Ray & Judy's Book Stop"
// ...
from: { email: MAIL_FROM_EMAIL, name: MAIL_FROM_NAME },
```

**The fallback is deliberate and it is what makes S1 safe:** deploy first, set secrets later, and an
unset secret is byte-identical to today. At **S3** the secret must be set — if it is forgotten there,
MailerSend 422s on an unverified sender, which fails **loudly**, not silently. **No `reply_to`** (§ 8
Q6, declined).

#### Deployment — NOT the Cloudflare Pages flow

Edge Functions deploy to Supabase separately from the static site; `git push origin staging` does
**not** deploy them. **Staging project ref: `puoaiyezsreowpwxzxhj`.**

> ⚠️ **F93 discipline — pass BOTH flags explicitly, every time.** A stray Supabase CLI workdir in
> the user's home directory was once linked to **production** and silently deployed stale code to
> staging. It was unlinked 2026-08-10 so the production hazard is defused, **but F93's own entry says
> the `--workdir` discipline "is still good practice and should be kept."** This repo's `supabase/`
> has no `config.toml`, so the CLI will look elsewhere for a workdir if not told.
>
> ```
> supabase functions deploy <name> --project-ref puoaiyezsreowpwxzxhj --workdir "<repo path>"
> ```
>
> **Watch the CLI's own "Using workdir ..." line** — it is the tell, and it is easy to miss.

> ⚠️ **Preserve each function's `verify_jwt` setting — do not assume it.** Per `CLAUDE.md`
> § Supabase platform facts, these functions run **JWT-off at the platform level plus in-body auth**;
> that is the intended design, not a misconfiguration. With no `config.toml` in the repo, a deploy can
> reset it. **Record each of the six functions' current setting in the dashboard BEFORE deploying,
> deploy with the flag that preserves it (`--no-verify-jwt` where it is currently off), and re-check
> after.** Silently re-enabling JWT verification would break all six at once.

Secrets are set per project, never pasted into chat or any committed file:

```
supabase secrets set MAIL_FROM_EMAIL=<value> MAIL_FROM_NAME=<value> --project-ref puoaiyezsreowpwxzxhj
```

**STAGING ONLY.** Production deploy is a **separate, explicitly-requested step** per `CLAUDE.md`
§ Staging Only, and follows the `phase-4.6` **PAUSE → Rick runs → paste result** pattern: Claude
prepares the exact command text, Rick executes anything touching `plgegklqtdjxeglvyjte`.

#### Doc updates this step owes

- **§ 11.2 required-secrets table** — add `MAIL_FROM_EMAIL` / `MAIL_FROM_NAME` (names only).
- **§ 11 intro** — currently reads "all that send email use MailerSend with the
  `noreply@mrcyberrick.us` sender." After S1 the sender is secret-driven.
- **⚠️ § 11.3 carries a stale claim, found 2026-08-31 and NOT yet corrected:** it says
  `notify-customers`' catalog link is *"hardcoded to production
  (`https://mrcyberrick.us/comic-preorder/catalog.html`)"*. The code actually reads
  ``Deno.env.get('APP_BASE_URL') ?? 'https://pulllist.app'``. **Verify against the file and correct
  it** — doc-only, zero risk, and it sits in the section S1 is already editing. `APP_BASE_URL` is
  also absent from § 11.2's table.

**Fully reversible and independently useful** — it stands on its own even if S2/S3 never run.

> ✅ **S1 EXECUTED 2026-08-31, staging only — `eff9793` on `staging`.** All six files edited to the
> target shape exactly as specified; deployed to `puoaiyezsreowpwxzxhj` one at a time, each preserving
> its live `verify_jwt` setting (read from the dashboard before and after — **a real surprise
> surfaced here**: `approve-customer` and `send-my-list` are JWT **ON**, contradicting CLAUDE.md's
> "all six JWT-off" claim; the other four are OFF as expected. Preserved exactly as found either way
> — S1's job is zero behavior change, not conformance to the doc — and the discrepancy is flagged for
> CLAUDE.md correction, not fixed here). **V3a green**: `grep -n "from:" supabase/functions/*/index.ts`
> — six hits, all reading `MAIL_FROM_EMAIL`/`MAIL_FROM_NAME`, zero literal addresses;
> `grep -rn "mrcyberrick"` still returns 6 (the deliberate `??` fallbacks — V3b is S3's gate, not
> S1's). **Secrets set on staging to today's exact values** (Rick, via `supabase secrets set`),
> confirmed present via `supabase secrets list` (names only — CLI shows digests, not values). **V2
> green**: two independent real `reset-password` sends (staging), delivered `From` read directly from
> the inbox both times — `Ray & Judy's Book Stop <noreply@mrcyberrick.us>`, byte-identical. **Doc
> updates landed** in the same commit: `technical-reference.md` § 11 intro, § 11.2 (`MAIL_FROM_EMAIL`
> / `MAIL_FROM_NAME` rows added; `APP_BASE_URL` added too — pre-existing, was missing from the table),
> and § 11.3's `notify-customers` note corrected (the catalog link was never actually hardcoded to
> `mrcyberrick.us` — it reads `Deno.env.get('APP_BASE_URL') ?? 'https://pulllist.app'`, verified
> directly against the file). **Not done in this step, deliberately**: production untouched; no
> `reply_to`; no DNS; `APP_BASE_URL`'s actual live value was not read (only that the secret exists).

### S2 — Pre-publish DNS in Cloudflare (no MailerSend change)

Add the DKIM + Return-Path records the new domain will need, **before** touching MailerSend, so
verification is near-instant when the slot frees.

> ✅ **DKIM + Return-Path PUBLISHED and verified 2026-09-01 — the SPF piece is genuinely blocked
> until S3, not merely deferred by choice.** Live DNS reconnaissance against `mrcyberrick.us`'s own
> working records (not the dashboard, which can't be reached without adding the domain — see § 1's
> hard 1-domain limit) showed the three record types S2 needs split into two different shapes:
>
> | Record | Pattern confirmed live | Portable without MailerSend? |
> |---|---|---|
> | DKIM CNAMEs | `<selector>._domainkey.<domain>` → `<selector>._domainkey.mailersend.net` — generic target, same for every domain | **Yes** |
> | Return-Path | `mta.<domain>` → `mailersend.net` — same generic target | **Yes** |
> | SPF include | `dc-<hash>._spfm.<domain>` — the domain name AND a unique hash are baked into the *hostname*, one hash per domain (`mrcyberrick.us` carries three) | **No** — cannot be known until MailerSend actually issues one for `pulllist.app`, which cannot happen before S3 removes `mrcyberrick.us` and frees the slot |
>
> (Also confirmed in passing: `ms1`/`ms2._domainkey.mrcyberrick.us` are genuine NXDOMAIN — S-1 really
> was skipped, exactly as recorded above; only the legacy `mlsend2` CNAME is live there.)
>
> **Published in Cloudflare (`pulllist.app` zone), DNS-only/unproxied, all three externally verified
> post-publish (`dns.google` resolver, not the Cloudflare dashboard — confirms both correctness and
> that they're genuinely unproxied, since a proxied record would not expose the real CNAME chain to
> an outside resolver):**
> ```
> ms1._domainkey.pulllist.app  CNAME  ms1._domainkey.mailersend.net   (verified live)
> ms2._domainkey.pulllist.app  CNAME  ms2._domainkey.mailersend.net   (verified live)
> mta.pulllist.app             CNAME  mailersend.net                  (verified live)
> ```
> All three were NXDOMAIN before publishing (checked first — no collision risk).
>
> **The SPF merge stays exactly where § "The SPF merge" below describes it, done at S3, not before** —
> now confirmed as a hard sequencing constraint, not a scheduling preference. V0b (the 10-lookup
> ceiling check) therefore also happens at S3, once the real include value exists to count.

> ⚠️ **Do not copy `mrcyberrick.us`'s current DKIM shape — it is the legacy one.** Observed in the
> MailerSend dashboard 2026-08-31: MailerSend has moved from the legacy **`mlsend2._domainkey` TXT**
> selector to **two CNAMEs**, `ms1._domainkey.<domain>` → `ms1._domainkey.mailersend.net` and
> `ms2._domainkey.<domain>` → `ms2._domainkey.mailersend.net`. F99's § "Current state" table records
> the old selector and is now a stale template for this step. **MailerSend displays the exact records
> when a domain is added — use those, expect the ms1/ms2 CNAME shape.**

> 🚩 **The SPF merge, and it is the sharpest trap in this plan.** A domain may have **exactly one**
> SPF TXT record *per name*. Publishing a second does not append — it produces a PermError that fails
> SPF for *every* sender on that name.
>
> **Measured live 2026-08-31** (an earlier draft of this block named the wrong collision — SPF is
> per-name, so Brevo's subdomain record and an apex record coexist fine):
>
> | Name | Current TXT | Whose |
> |---|---|---|
> | `pulllist.app` | `v=spf1 include:spf.efwd.registrar-servers.com ~all` | **Namecheap email forwarding** |
> | `rjbookstop.pulllist.app` | `v=spf1 include:spf.brevo.com ~all` + `brevo-code:…` | Brevo — **untouched by this work** |
>
> **The apex already has an SPF record**, so whatever MailerSend asks for there must be **merged into
> that line**, never added as a second TXT.
>
> ✅ **ANSWERED 2026-08-31 (Rick) — KEEP the Namecheap include.** There is **no forwarding rule
> configured today**, but the infrastructure is provisioned and Rick intends to set one up (an
> `@mrcyberrick.us` mailbox is the likely destination). Measured live: `pulllist.app` carries
> **MX records** at `eforward1-4.registrar-servers.com` alongside the SPF include.
>
> So `include:spf.efwd.registrar-servers.com` is **inert today but not vestigial** — dropping it would
> silently break forwarding the moment a rule is created. **It stays in the merged record.** Cost: one
> DNS lookup of the ten available, spent deliberately.
>
> *(Note the distinction: the MX records handle **inbound**; the SPF include authorizes Namecheap to
> **re-send** forwarded mail as `pulllist.app`. With no rule configured, nothing is being re-sent —
> which is why the include is currently doing nothing.)*
>
> **Then count DNS lookups.** SPF hard-fails past **10**. `mrcyberrick.us`'s record already runs four
> includes — `_spf.mailersend.net` plus three `dc-*._spfm.<domain>` entries — each of which may nest
> further. **Count the resolved lookups before publishing, not after.**

> ⚠️ **The zone trap, from F99 and worth repeating because it already cost a session.** The DMARC
> reporting-authorization record lives at `pulllist.app._report._dmarc.mrcyberrick.us` — its parent
> zone is **`mrcyberrick.us` (GoDaddy)**, not `pulllist.app` (Cloudflare). Adding a record like that
> in Cloudflare produces something that *looks* right in the UI and does nothing. Check which zone
> each record's parent actually belongs to.

### S3 — Cutover window (the only risky step)

Remove `mrcyberrick.us` from MailerSend → add the new domain → confirm verified → flip the two
secrets. No code deploy. Keep the old DNS records in place for rollback.

> ✅ **Toggle Maintenance Mode ON before removing the old domain; OFF only after the new domain is
> verified, the secrets are flipped, and V2/V5 are green.** Per § 3's mitigation note — closes real
> exposure on the four authenticated pages, but **not** `index.html`/`forgot-password.html` until
> **F149** is fixed. Confirm F149 is resolved (or accept the residual and say so explicitly) before
> treating the toggle as sufficient cover for this step.

> ⛔ **Do not schedule this inside a catalog import window.** `import.js` Step 7 calls
> `notify-customers`; a migration mid-import means the monthly notification silently fails. **The next
> import gate is Fri 2026-09-25** (October catalog, `trig_01FQesEHRh9XdRXgwASFJoh7`). Cut over well
> clear of it.

> ⛔ **ATTEMPTED 2026-09-01, ROLLED BACK — read this before trying again.** Maintenance Mode ON,
> `mrcyberrick.us` removed from MailerSend, `pulllist.app` added and **fully verified** (all four
> dashboard checks green: domain, SPF, DKIM, Return-Path). Two real, unanticipated problems surfaced
> — neither was foreseeable from anything in this plan or MailerSend's own docs, both confirmed
> empirically, not guessed:
>
> 1. **MailerSend's API tokens are scoped to a domain ("server"), not the account.** The existing
>    `MAILERSEND_API_KEY` died the moment `mrcyberrick.us` was removed — first symptom was
>    `MailerSend error: {"message":"Unauthenticated."}`. Not documented anywhere obvious; discovered
>    by reading the error and confirming in the dashboard. **Fix for next attempt:** budget time to
>    generate a fresh token (Sending-access scope is sufficient — none of the six functions do
>    anything but `POST /v1/email`) immediately after adding the new domain, *before* attempting any
>    send.
 2. **The blocker that forced the rollback — and its cause is UNRESOLVED. Do not treat any
>    explanation below as established.** After fixing the token, every send attempt returned
>    `#MS42207 — "The from.email domain must be verified in your account to send emails"` — for
>    **both** the subdomain (`noreply@rjbookstop.pulllist.app`) **and the exact bare verified domain**
>    (`noreply@pulllist.app`), twice each, ~10 minutes apart, ~15–20 min total past full verification.
>
>    ⚠️ **An earlier version of this entry (written the same evening, corrected 2026-09-01) asserted
>    "MailerSend send-time activation delay" as the cause. That was a tidy story stated with more
>    confidence than the evidence carried, and it is contradicted by the rollback itself:
>    `mrcyberrick.us` was re-added minutes later and sent successfully on the first try.** A generic
>    newly-added-domain activation delay should have hit it too. (Confound: `mrcyberrick.us` had
>    prior history in the account, so re-activating a known domain may differ from cold-adding a new
>    one — which is itself hypothesis 2 below, not a defence of the delay theory.) Recording this
>    because writing an unverified cause into a permanent doc is the exact failure mode F132/F138/
>    F139/F145 all exist to catch.
>
>    **Ruled OUT, with reasons, so nobody re-investigates these:**
>    - **Sender Identities (premium feature) — NOT the cause.** Read directly 2026-09-01
>      (`mailersend.com/help/send-email-on-behalf-of-clients`, Rick's find). That feature exists to
>      send from *clients'* domains without those clients verifying; MailerSend's own page states it
>      is not required for a domain you have verified yourself, and that the parent domain must be
>      verified regardless. Starter-and-above, but it does not gate this work.
>    - **The subdomain design / a free-tier subdomain restriction — NOT the cause.** S0's own probe
>      (2026-08-31, § 2) sent successfully from `noreply@probe.mrcyberrick.us` under verified
>      `mrcyberrick.us` **on this same free account**, returning `dkim=pass`/`spf=pass`/`dmarc=pass`.
>      Subdomain sending demonstrably works here. And the bare root domain failed identically anyway.
>    - **A "Default email address" account setting** — chased from a web-search hint, no such setting
>      found in this account's UI. Dead end, not a finding.
>
>    **Live hypotheses, ranked by fit — check in this order next attempt:**
>    1. **Token↔domain binding mismatch (best fit).** MailerSend's own docs state the FROM address
>       must match the domain the *API token* belongs to. A token bound to the wrong domain produces
>       exactly this error, permanently, regardless of waiting. **Never verified during the attempt** —
>       the new token's domain binding was assumed correct, not confirmed. This is the first thing to
>       check, and it is checkable in seconds on the token's own page.
>    2. **Cold-domain vs. known-domain state.** `pulllist.app` showed `0 Sent` and had never existed
>       in this account; `mrcyberrick.us` re-added and worked instantly. That asymmetry is real and
>       unexplained — possibly a per-domain flag, review hold, or warm-up state distinct from DNS
>       verification.
>    3. **Send-time activation delay** (the original claim). Still possible, but weakest — see the
>       rollback contradiction above. If it is this, the true ceiling is unknown; 15–20 min is only a
>       measured floor.
>
> **Rollback executed and independently verified, ~20 min after the domain-check symptom first
> appeared:** `pulllist.app` removed from MailerSend, `mrcyberrick.us` re-added (its DNS was never
> touched, so it re-verified immediately), a **third** fresh API token generated (same
> domain-scoping issue applies on the way back), both secrets flipped back to
> `noreply@mrcyberrick.us` / "Ray & Judy's Book Stop". **A real send was confirmed via actual
> delivered headers** (Outlook, `View message source`), not just the API's own `{"success":true}`
> (which the plan itself warns proves nothing): `spf=pass`, `dkim=pass` (both `d=mrcyberrick.us` and
> `d=mailersend.net` signatures), `dmarc=pass`, `compauth=pass reason=100`, `From:` correctly reading
> `Ray & Judy's Book Stop <noreply@mrcyberrick.us>` — byte-identical to pre-attempt production.
> Maintenance Mode confirmed OFF afterward via the anon RPC (F149), not just the toggle's own UI
> state. **Total outage window: Maintenance Mode ON to OFF, roughly 50–55 minutes** — every
> transactional path was down for real customers that whole time (a deliberate, consented window,
> not an accident, but a real one).
>
> **State left behind, relevant to the next attempt:** `pulllist.app`'s S2 DNS records (DKIM,
> Return-Path, the merged SPF) are **still live in Cloudflare** — they were never MailerSend-specific
> in a way that removing the domain from MailerSend would invalidate, so **S2 does not need
> repeating**. The `pulllist.app`-scoped API token created during this attempt is now dead (its
> domain was removed) — harmless to leave, safe to delete in MailerSend's dashboard whenever
> convenient, not urgent.
>
> **Before attempting S3 again, in this order:**
> 1. **Strongly consider one month of paid tier first — see § 8 Q7.** Tonight proved the structural
>    trap: on the free tier's single domain slot, the *only* way to test `pulllist.app` is to remove
>    the working sender first, so every diagnosis costs a live customer-facing outage. Two
>    simultaneous domains converts this into a zero-downtime change with unlimited time to
>    investigate.
> 2. **Check the API token's domain binding** (hypothesis 1) — seconds to verify, best fit to the
>    evidence, and never checked during this attempt.
> 3. **Generate the new domain-scoped token as an explicit sub-step** immediately after adding the
>    domain, not as an afterthought — it is a *known* requirement now, not a surprise.
> 4. **Ask MailerSend support directly** what governs send-time readiness for a newly-added domain,
>    ahead of the window rather than discovering it inside one.
> 5. **Fix abort criteria in wall-clock terms before Maintenance Mode goes on** (e.g. "not sending by
>    T+15 → roll back"). This attempt improvised the wait ladder mid-incident; deciding it in advance
>    is free and removes judgement pressure from the worst moment to be exercising it.
> 6. **The rollback path itself worked cleanly and fast** — trust it rather than waiting past a second
>    reasonable check if the same symptom recurs.
>
> **A note on scope, from Rick 2026-09-01:** he would accept **root-domain-only**
> (`noreply@pulllist.app`, per-tenant display name only) for this task and defer subdomains. That is a
> legitimate simplification — it is this plan's own documented fallback (§ 2 decision tree, "uncovered"
> row) and costs only F72's per-tenant email branding later. **But it would not have changed tonight's
> outcome:** the bare root domain failed identically. Treat it as a design choice, not a fix.

### S4 — Verify alignment, then consider `p=quarantine`

Confirm the new domain authenticates on **both** mechanisms before retiring anything. **Publish
`p=quarantine` only after alignment is proven** — doing it during a sender migration risks
quarantining the store's own mail. F99 also requires a separate DNS check first: `litesrv._domainkey`
gone from `mrcyberrick.us`, MailerSend its sole sender there.

---

## 5. Verification gates

| Gate | Assertion | How |
|---|---|---|
| ~~**V0**~~ | ~~S-1 DKIM green~~ — **withdrawn 2026-08-31 with S-1.** `mrcyberrick.us` is `p=none` and SPF-aligned, so the gate guarded nothing enforceable on a domain S3 removes | — |
| **V0b** | The merged SPF record resolves within **10 DNS lookups**, and there is exactly **one** SPF TXT on the name | An SPF lookup-counter, before publishing — see § 4 S2 |
| **V1** | S0 answered from **delivered headers**, not an API status | Send to a real mailbox; read `Authentication-Results` |
| **V2** | S1 changes nothing observable | Deliver a staging `reset-password`; `From` byte-identical to pre-change |
| **V3a** (S1) | All six `from:` lines read `MAIL_FROM_EMAIL`/`MAIL_FROM_NAME`. The literal survives **only** as a `??` fallback — **6 occurrences expected, not 0** | `grep -n "from:" supabase/functions/*/index.ts` — six hits, none containing a literal address |
| **V3b** (S3, **not S1**) | Once the secrets are set and verified, the fallback literals may be removed | `grep -rn "mrcyberrick" supabase/functions/` returns 0 |
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
- **Brevo / marketing mail.** Already on `rjbookstop.pulllist.app` and authenticated — and it stays
  there, untouched. **Brevo's *transactional* product was evaluated for this migration on 2026-09-02
  and REJECTED (§ 9). That changes nothing about its marketing role.**
- ~~**Paid-tier migration.** Revisit after this work, per Rick 2026-08-31.~~ — **MOVED IN SCOPE
  2026-09-01, promoted to § 8 Q7.** That deferral was made when S3's outage was theoretical. After
  the failed attempt it is the leading approach, not a later question.

---

## 7. Rollback

S1 is a normal revert. S3 is the only step needing a real plan: keep `mrcyberrick.us`'s DNS records
published throughout, so rollback is re-adding it in MailerSend and flipping the secrets back — no
deploy, no DNS wait. **Do not delete the old records until S4 has been green for at least one full
monthly cycle.**

---

## 8. Open questions for Rick

1. ~~**S0's answer**~~ — ✅ **ANSWERED 2026-08-31: subdomains ARE covered.** See § 2.
2. ~~If subdomains are not covered: flat sender, or price the paid tier?~~ — **MOOT.** The covered
   answer means the free tier carries the per-tenant design.
3. Cutover window preference, given it must clear 2026-09-25.
4. `p=quarantine` — publish at S4, or hold until after a second tenant is live?
7. **One month of paid tier to buy a parallel run? — OPEN, and Rick is inclined toward yes
   (2026-09-01, after the failed S3 attempt).** Rick's reasoning, recorded so it is not re-derived:
   *"A one month's fee may offer some extra time to explore the issue and offer the buffer we need to
   migrate without risking an error on the end user side. The risk is still low now but as the site
   grows it can translate to a much bigger issue."*
   **Why this is now the leading approach rather than a deferred nicety:** the single free-tier domain
   slot means the only way to test `pulllist.app` at all is to remove the working sender first — so
   *every* diagnostic attempt costs a live, customer-facing mail outage, and tonight's cost ~50–55
   minutes to learn one error code. Two simultaneous domains removes that entirely: verify and fully
   exercise `pulllist.app` while `mrcyberrick.us` keeps serving customers, cut over only once proven,
   downgrade after. **The blast radius argument is the real one** — ~30 customers today makes a
   50-minute outage survivable; at several hundred, across multiple tenants, it is not, and the
   migration only gets harder to schedule the longer it waits.
   **PRICED 2026-09-02 — and the cheap tier does NOT buy this.** Read from MailerSend's own plans
   page: **Hobby ($7/mo) still allows only ONE sending domain.** It lifts the daily API cap 100 →
   1,000 (so it *does* close **F148**) but buys **no parallel run at all**. The parallel run needs
   **Starter, $35/mo** (10 domains, 100k API req/day, 7-day activity retention). **Q7's real price is
   $35, not ~$6.** **Check the advertised 14-day Professional trial first** — it claims access to all
   Professional features (1,000 domains); if this account is still eligible the parallel run is free.
   Still unpriced: whether a mid-cycle downgrade is clean.
   **Also note § 9's finding, which partly supersedes this question:** a swap to a *different*
   provider needs no paid tier at all, because the old provider keeps serving while the new one is
   tested.
5. ~~**Is there a live email-forwarding address on `pulllist.app`?**~~ — ✅ **ANSWERED 2026-08-31:
   none configured yet, but Rick intends to set one up, and MX records are already provisioned.
   The Namecheap SPF include therefore STAYS in the S2 merge.** See § 4 S2.
6. ~~**Should S1 also set `Reply-To` from `tenants.contact_email`?**~~ — ⛔ **DECLINED 2026-08-31 (Rick): stay with no-reply. Do not re-propose.** A monitored reply address is an ongoing operational commitment, and under multi-tenancy it would hand every future tenant a support inbox they never asked for. Nothing is misleading today: no live email invites a reply, and customers have the shop phone number and the app itself. **S1 sets `from` only.** Original reasoning retained: No
   function sets `reply_to` today and no live email invites a reply, so nothing is broken. But
   MailerSend defaults `Reply-To` to the `From` address, so a customer who hits Reply reaches an
   unmonitored `noreply@`. S1 already edits that exact block and `tenants.contact_email` already
   exists, making this nearly free — and per-tenant correct. **Scope creep on an otherwise tight
   plan; not folded in unasked.**
   *(Related: the MailerSend hosted template deleted 2026-08-31 carried the copy "Questions? Reply to
   this email or call the shop directly." It was never wired to any function, so no customer ever
   received it — but it would have black-holed if anyone had connected it.)*
8. ~~**Move transactional to Brevo, reusing the newsletter's existing `pulllist.app` sender?**~~ —
   ⛔ **EVALUATED AND REJECTED 2026-09-02. Do not re-propose without reading § 9 first.** Rick's
   proposal after S3's rollback, and the reasoning was sound: it would have collapsed *both* splits
   F99 names — domain **and** provider — with no parallel-run problem. Killed by Brevo rewriting
   every link in transactional mail through its own click-tracking redirector, password-reset links
   included, with no way to disable it. Full evidence in **§ 9**.
9. ~~**Open a second free MailerSend account holding `pulllist.app` in its own domain slot?**~~ —
   ⛔ **CLOSED 2026-09-02: this is an explicit ToS violation.** Rick's other proposal. MailerSend
   Terms of Use **§ 11.1**: *"Creating multiple accounts is forbidden. Therefore you, as a natural
   person, must not: create multiple users and / or; create different accounts with the same domain
   or different subdomains and / or; log in with different login credentials."* **§ 11.2**: *"The
   Customer, as a natural person, shall create only one account, where all the Customer's domains
   shall be maintained."* **§ 13.1** permits suspension where MailerSend *"reasonably believes that
   the Services are being used in violation of the Terms."* **The exposure is not the throwaway
   account — it is the EXISTING one, which sends every password reset and registration confirmation
   to real customers.**
   *Separately, it would most likely not have worked anyway.* The one-domain limit forced S3's
   **rollback**; it did not cause the **send failure**. `#MS42207`'s cause is unresolved and its
   leading hypothesis is token↔domain binding — which a fresh single-domain account reproduces
   exactly.

---

## 9. S3-B — Brevo transactional: EVALUATED AND REJECTED (2026-09-02)

**Verdict: do not migrate transactional mail to Brevo.** Closed on measured evidence, not preference.

Rick proposed it after S3's rollback on sound reasoning: Brevo already sends the weekly newsletter,
already has a `pulllist.app` subdomain authenticated, and moving there would collapse *both* splits
F99 names — the domain split **and** the provider split — with no parallel-run problem, since
MailerSend keeps serving untouched while a *different* provider is exercised. **That reasoning was
right. The product turned out to be wrong for the job.**

**No finding ID consumed** — an external platform's product design, not a defect in our code, DNS or
plan. Same disposition as S3's own record. **F152 remains the next free finding ID.**

### What was tested — three live sends, zero downtime, production untouched

All three ran against the real Brevo account **while MailerSend continued serving production**.
Verified from **delivered Gmail headers** (`Show original`), never the API's own `201` — the standard
§ 2 demands and the S3 rollback used.

| Test | Sender | Question | Result |
|---|---|---|---|
| **A** | `previews@rjbookstop.pulllist.app` (the newsletter's own sender) | Is transactional activated on this account? | **201, delivered** — active; no support ticket needed |
| **B** | `noreply@rjbookstop.pulllist.app` (never registered as a sender) | Does domain auth cover arbitrary addresses? | **201, delivered**, signed identically to A |
| **C** | `noreply@rjbookstop.pulllist.app`, body carrying links | Does Brevo rewrite links? | **201, delivered — EVERY link rewritten** |

**Two pre-flight worries were also closed cheaply, and both were false alarms.** The *"Sent with
Brevo"* free-tier sticker that several third-party sources report: **not present**, on the newsletter
or on any of the three sends. The transactional-activation support ticket Brevo's own help centre
describes as required for new accounts: **not required here** — already activated.

### The authentication result is good, and it is the part worth keeping

Identical across all three sends:

```
dkim=pass  header.i=@rjbookstop.pulllist.app  header.s=brevo2
spf=pass   smtp.mailfrom=bounces-…@ha.d.sender-sib.com
dmarc=pass (p=NONE sp=NONE dis=NONE)  header.from=pulllist.app
From: "Ray & Judy's Book Stop" <noreply@rjbookstop.pulllist.app>
```

**DKIM signs as the exact From domain — strict alignment**, and Test B proves domain authentication
genuinely covers addresses never registered as senders.

**SPF is NOT aligned.** It passes for Brevo's bounce domain (`ha.d.sender-sib.com`), not
`pulllist.app`, so **DMARC is passing on DKIM alone**. This **confirms § 4's existing prediction**
(*"Brevo and MailerLite are DKIM-only with no aligned SPF"*, and V6's *"no margin"*) — now measured
rather than assumed. Not itself a blocker, since DMARC needs only one aligned mechanism and
`p=quarantine` would still be safe; but it trades MailerSend's two independent aligned mechanisms
for one, with no fallback if DKIM ever breaks.

### Why it was rejected — one root cause, three symptoms

Brevo's stated reason for the first symptom explains all three: **they do not distinguish
transactional from marketing on the API/SMTP interface**, so everything sent through it inherits
marketing-mail behaviour.

| Injected into our transactional mail | Removable? |
|---|---|
| `List-Unsubscribe` + `List-Unsubscribe-Post: One-Click` — a one-click unsubscribe **on a password reset** | **No.** Brevo does not remove it from SMTP/API sends. The documented alternative (`list-help` instead) needs a support request **and**, per their help centre, an **Enterprise plan** |
| Open-tracking pixel injected into the body | **No.** Only *anonymous tracking* (Settings ▸ Automations ▸ Transactional emails ▸ Tracking), which anonymises the log entries — not the injection |
| **Every link rewritten through `bbfjjjaf.r.af.d.sendibt2.com/tr/cl/…`** | **No — explicitly declined.** Brevo's position: *"Link tracking enables us to keep the platform secure and prevent fraudulent sending"* |

**The link rewriting disqualifies it on its own.** Test C sent
`https://pulllist.app/forgot-password.html?token_hash=…&type=recovery`; it arrived as an opaque
`sendibt2.com/tr/cl/…` redirect. Three consequences:

1. **A one-time password-reset credential now transits and is stored by a third-party
   click-tracker**, mapped to the recipient. Brevo's own community carries an open thread raising
   exactly this.
2. **The visible link in a security email points at a domain the customer has never heard of.** That
   is the shape of a phishing mail, and it trains customers to click through unfamiliar redirectors.
3. **A new hard dependency on `sendibt2.com` for account recovery.** Corporate filters and DNS
   blocklists routinely block tracking redirectors — the reset would be dead while `pulllist.app` is
   perfectly fine.

It hits **every** action link, not only resets: `invite-customer`, `approve-customer`, the
`register-customer` confirmation, `notify-customers`' catalog CTA, `send-my-list`.

**Be precise about what does NOT break.** `reset-password`'s `hashed_token` design still holds —
token consumption happens through a client-side `verifyOtp`, so a scanner following the redirect does
not burn it. This is a **credential-handling and trust** problem, not a functional one. It is still
disqualifying.

**A second, independent concern, recorded because it nearly stood alone.** F96's own record states
Brevo blocklisting is *"a per-contact, account-level property rather than a per-list one."* If a
transactional unsubscribe writes to that same blocklist, a customer clicking Unsubscribe on a
"pull list is live" notice could silently lose password resets and registration confirmations too —
the exact silent-failure shape that went **18 days undetected** in F96. **NOT VERIFIED:** the
account-level blocklist is documented in our own repo, but that the transactional unsubscribe writes
to it is inference. Never tested — the link rewriting closed the question first. **Re-open this only
if someone revisits Brevo; do not treat it as established.**

### What this bought

Not a wasted session. It closed a genuinely promising option with hard evidence in ~20 minutes at
zero cost and zero downtime, and proved two things that outlive the rejection:

- **`<slug>.pulllist.app` sending authenticates cleanly with strict DKIM alignment**, verified from
  real delivered headers. Reusable whatever provider is chosen.
- **A swap to a DIFFERENT provider has no parallel-run problem at all.** The incumbent keeps serving
  on `mrcyberrick.us` while the challenger is exercised on `pulllist.app`. The constraint that made
  S3 cost a ~50-minute outage **only exists within a single provider's domain slot.** This is the
  most valuable thing learned this session and it reframes the whole migration — see § 10.

**Nothing was changed and there is nothing to roll back.** Brevo's `rjbookstop.pulllist.app` DNS is
untouched and still serving newsletters; the three sends were ordinary API calls.

---

## 10. Provider selection — DIRECTION: Resend (2026-09-02)

**Rick's call, 2026-09-02: pursue Resend — a competitor to MailerSend — as the intended
transactional provider.** Recorded as a **direction, not a commitment**: no account exists, nothing
has been probed live, and no code has changed. Whether to actually migrate stays open until the
three-test probe at the end of this section comes back green.

Both of Rick's earlier alternatives to S3 are closed (Brevo, § 9; the second free MailerSend
account, § 8 Q9). **None of this is urgent** — production is serving customers correctly from
`noreply@mrcyberrick.us` today, and the October import gate (2026-09-25) is the only fixed date
nearby.

### Requirements, derived from this session rather than assumed

1. **No link rewriting on transactional** — non-negotiable, per § 9.
2. **No unsubscribe-header injection on transactional.**
3. **Enough domain slots for the chosen sending design** — see the lever below.
4. **Free-tier headroom past MailerSend's 500/month and 100 API requests/day** (F148).
5. **A `from`/`to`/`subject`/`html` REST API** — all six functions POST an identical shape, so a
   provider swap is ~4 lines each plus a secret.

### Decide this lever FIRST: flat sender vs. per-tenant subdomain

F99 recorded per-tenant `<slug>.pulllist.app` as the direction and § 2 confirmed it viable. But that
choice was made partly **because Brevo was already sitting there** — and Brevo is now out.

**A flat `noreply@pulllist.app` needs exactly one domain slot forever, at any tenant count.** F72's
per-tenant branding lives in the `from` **name** and the body copy, both already secret-driven since
S1 — it does **not** require a per-tenant sending **domain**. The subdomain buys reputation
segmentation, not branding.

**This decides which free tiers are sufficient, so settle it before picking a provider.**

### Candidates — researched 2026-09-02, NOT yet tested live

| | **Resend** | **MailerSend Starter** | **Amazon SES** |
|---|---|---|---|
| Link rewriting | **Off by default**, opt-in per domain | Off | Opt-in via configuration sets |
| Unsubscribe injection | **None on the Send API** (Broadcasts only) | None | None |
| Free tier | 3,000/mo, **100/day**, 1 domain | 500/mo, 100 API req/day, 1 domain | $0.10/1,000; credits vary by account age |
| Subdomain coverage | **Separate verification per subdomain** | Parent covers subdomains (§ 2) | **DKIM inherits to subdomains** |
| Domains on relevant paid tier | Pro $20/mo → 10 | Starter $35/mo → 10 | effectively unlimited |
| Cost to close F148 | Pro $20/mo | Hobby $7/mo (1 domain; F148 only) | negligible |
| Operational overhead | Low | **Lowest — already integrated** | **High** — sandbox exit, bounce/complaint handling, IAM, region |

**Resend is the chosen direction (Rick, 2026-09-02).** It explicitly advises against tracking on
transactional mail *precisely so inbox providers don't classify it as marketing* — the opposite
posture to Brevo. Two further reasons it beat MailerSend Starter on the merits:

- **It is better AFTER the migration, not only during it.** MailerSend Starter is a one-month bridge
  that drops back onto a free tier of 500/month and 100 API requests/day — the F148 ceiling. Resend's
  free tier (3,000/month) is strictly better in both directions.
- **The code change is smaller than Brevo's would have been.** Resend keeps `Authorization: Bearer`
  and the `html` field name, so realistically only the endpoint URL and the `from` shape move (a
  string rather than an object). **Confirm the exact request shape against Resend's own docs at
  implementation time — this was read from research, not from a live call.**

**Honest caveat, recorded so it is not a surprise later: Resend's free tier is 100/day, so it does
NOT dissolve F148** — it lifts the monthly ceiling 500 → 3,000 but keeps roughly the same blast-day
ceiling. Only Brevo's 300/day would have closed F148 outright, and Brevo is out. Pro ($20/mo)
removes it.

**MailerSend Starter stays viable** and is the lowest-effort path, since the integration already
exists and works. $35 for one month is exactly what § 8 Q7 asks for.

**Amazon SES is cheapest at scale and by far the most work** — likely disproportionate for a
~30-customer shop, worth revisiting only at much larger volume.

### Recommended next step whenever this is picked up

**Do not write code first.** Settle the flat-vs-subdomain lever, then run **the same three-test probe
this session ran against Brevo** — send / delivered-headers / link-rewriting — against the chosen
provider's free tier, sending from `pulllist.app`, **while MailerSend keeps serving production**.
That probe cost 20 minutes and zero downtime here, and the equivalent check would have caught S3's
failure *before* the 50-minute outage rather than during it.

**PLANNED 2026-09-02 — `docs/f99-resend-discovery.md`** (STATUS: PLANNED, not started). It does
exactly this, sequenced on one lesson from § 9: **the disqualifiers are tested first.** Brevo died
on link rewriting, and that test could have run before the account work, the domain check and the
header reads that preceded it. Resend's sandbox sender needs no DNS at all, so **Phase 1 can
disqualify Resend in ~10 minutes with nothing published and nothing to roll back**; the DNS and
alignment work in Phase 2 only happens if Phase 1 passes. **Kill criteria K1–K6 are written down
before the tests**, deliberately, so the result is read honestly rather than rationalised.

---

## Reference

- **F99** (`docs/technical-reference.md` § 13) — the finding this executes; steps (1)–(2) done, the
  2026-08-20 sender inventory, the GoDaddy-zone trap, the reputation note (no warm-up concern).
- **F72** — per-tenant email branding; S1 is its shared first step.
- **F148** — the daily-API-cap limit on the same account.
- **F145** — no wildcard DNS on `pulllist.app`; each hostname is individually provisioned. Relevant
  if per-tenant sending subdomains are chosen.
- `CLAUDE.md` § Current Migration Phase — the 2026-09-25 October import gate.

**Last updated:** 2026-09-02 — **fifteenth pass: both of Rick’s alternatives to S3 evaluated and
CLOSED; provider selection is now the open decision.** Brevo transactional tested live (three sends,
zero downtime, production untouched) and **REJECTED** — it rewrites every link in transactional mail
through its own click-tracking redirector, password-reset links included, with no way to disable it.
New **§ 9** carries the full evidence and the delivered headers. A second free MailerSend account
**CLOSED as an explicit ToS violation** (§ 11.1/11.2 quoted) — new **§ 8 Q9**. **§ 8 Q7 repriced:**
Hobby ($7) is still ONE domain and buys no parallel run; **Starter ($35) is the real price**, and the
advertised 14-day Professional trial is worth checking first. New **§ 10** records the requirements,
the flat-vs-subdomain lever to settle before choosing, and three researched candidates (Resend
leading, not yet tested). **Two durable results kept from the rejection:** `<slug>.pulllist.app`
authenticates with strict DKIM alignment, and **a swap to a DIFFERENT provider has no parallel-run
problem at all** — the constraint that cost S3 ~50 minutes of outage exists only within a single
provider’s domain slot. No finding ID consumed; **F152 still free.**
Fourteenth pass, 2026-09-01 — same evening: the thirteenth pass's diagnosis was
CORRECTED.** It asserted "MailerSend send-time activation delay" as S3's cause; that is contradicted
by the rollback (`mrcyberrick.us` re-added minutes later and sent first try) and was stated with more
confidence than the evidence carried. § 4 S3 now records the cause as **unresolved**, with two
theories ruled out *with reasons* (Sender Identities — read directly, it is an agency feature not
required for your own verified domain, Rick's find; and any subdomain/free-tier restriction — S0's
own probe already sent from a subdomain on this same free account) and three ranked live hypotheses,
**token↔domain binding first** since it best fits the evidence and was never checked. Paid-tier
promoted from § 6 "out of scope, revisit later" to **§ 8 Q7**, with Rick's growth-risk reasoning
recorded. Thirteenth pass: S3 attempted and ROLLED BACK, same day as S2.
Full cutover sequence run for real (Maintenance Mode ON, domain swapped in MailerSend, SPF merged
with the real value, secrets flipped) and got as far as a fully-verified `pulllist.app` — then hit
two unanticipated MailerSend-side problems in sequence: API tokens are domain-scoped (the existing
key died with the old domain, fixed by generating a new one) and, more seriously, send-time
enforcement did not activate for 15–20+ minutes past full dashboard verification, for the verified
domain itself, not just the subdomain. Rolled back cleanly and independently verified via real
delivered headers (not just the API's own unconditional success response) — production is back to
exactly its pre-attempt state, `noreply@mrcyberrick.us`. See § 4 S3 for the full record and what to
do differently next attempt. Total real outage window: ~50–55 minutes, Maintenance Mode ON to OFF.
Twelfth pass: S2 partially executed — DKIM (`ms1`/`ms2._domainkey`)
and Return-Path (`mta`) CNAMEs published in Cloudflare and externally verified; discovered live (not
assumed) that DKIM/Return-Path targets are generic across domains but MailerSend's SPF include is a
per-domain hash that cannot be known before S3, so the SPF merge is a hard sequencing constraint, not
a preference. F149 added to the findings line (heavily referenced in § 3/§ 4 S3, was missing).
Eleventh pass: S3's Maintenance Mode mitigation recorded (§ 3, § 4
S3) — Rick confirmed the 1-domain-at-a-time constraint is real and proposed the toggle as a cutover
safety net; checked against the actual code, found a real gap (index.html/forgot-password.html
uncovered), filed as **F149**. Tenth pass: S1 EXECUTED on staging (`eff9793`) — all six files
parameterized and deployed, verify_jwt preserved (including the two-of-six JWT-ON surprise, flagged
not fixed), secrets set to today's values, V3a + V2 both green, owed doc updates landed. Ninth pass
(V3 split into V3a/V3b — the old wording was unpassable at S1 by design). Eighth pass (S1 execution
detail added ahead of CLI handoff: deploy mechanics, F93 workdir discipline, verify_jwt preservation,
owed doc updates). Seventh pass (Q6 DECLINED — no-reply stands; S1 sets `from` only). Sixth pass (S2
forwarding question answered: include STAYS; new open Q6 on `Reply-To`). **Fifth pass: S0 ANSWERED
(covered branch), architecture settled, S1 is next.** Fourth pass (**S-1 SKIPPED** on Rick's challenge; S0 is now the first step). Third pass (live DNS measured: providers confirmed, DMARC relaxed, apex SPF found). Second pass, against the live MailerSend dashboard. **1-domain limit
confirmed hard** (no unverified second domain, so no parallel run); **`pulllist.app` settled as the
domain to verify in both S0 branches**; **S-1 added** (legacy `mlsend2` DKIM needs the `ms1`/`ms2`
CNAMEs — a live issue found in passing, not part of this migration); **S2 gained the single-SPF-record
merge trap and the 10-lookup ceiling**; zero-risk S0 probe method recorded. **S0 still not run.**
