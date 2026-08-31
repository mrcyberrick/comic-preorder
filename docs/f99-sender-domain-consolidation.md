# F99 — consolidate the transactional sending identity onto `pulllist.app`

**STATUS:** PLANNED — **S0 ANSWERED 2026-08-31 (covered branch, evidence in § 2)**; S1 next, not started | staging=— | prod=— | findings=F99,F72,F148,F145

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
be added. **Checked in the dashboard 2026-08-31: a second domain cannot be held even unverified**, so
the hoped-for parallel path does not exist. Between removal and a working new sender, **all
transactional mail is down**: magic links, invites, approvals, password resets.

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

### S2 — Pre-publish DNS in Cloudflare (no MailerSend change)

Add the DKIM + Return-Path records the new domain will need, **before** touching MailerSend, so
verification is near-instant when the slot frees.

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

1. ~~**S0's answer**~~ — ✅ **ANSWERED 2026-08-31: subdomains ARE covered.** See § 2.
2. ~~If subdomains are not covered: flat sender, or price the paid tier?~~ — **MOOT.** The covered
   answer means the free tier carries the per-tenant design.
3. Cutover window preference, given it must clear 2026-09-25.
4. `p=quarantine` — publish at S4, or hold until after a second tenant is live?
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

---

## Reference

- **F99** (`docs/technical-reference.md` § 13) — the finding this executes; steps (1)–(2) done, the
  2026-08-20 sender inventory, the GoDaddy-zone trap, the reputation note (no warm-up concern).
- **F72** — per-tenant email branding; S1 is its shared first step.
- **F148** — the daily-API-cap limit on the same account.
- **F145** — no wildcard DNS on `pulllist.app`; each hostname is individually provisioned. Relevant
  if per-tenant sending subdomains are chosen.
- `CLAUDE.md` § Current Migration Phase — the 2026-09-25 October import gate.

**Last updated:** 2026-08-31 — ninth pass (V3 split into V3a/V3b — the old wording was unpassable at S1 by design). Eighth pass (S1 execution detail added ahead of CLI handoff: deploy mechanics, F93 workdir discipline, verify_jwt preservation, owed doc updates). Seventh pass (Q6 DECLINED — no-reply stands; S1 sets `from` only). Sixth pass (S2 forwarding question answered: include STAYS; new open Q6 on `Reply-To`). **Fifth pass: S0 ANSWERED (covered branch), architecture settled, S1 is next.** Fourth pass (**S-1 SKIPPED** on Rick's challenge; S0 is now the first step). Third pass (live DNS measured: providers confirmed, DMARC relaxed, apex SPF found). Second pass, against the live MailerSend dashboard. **1-domain limit
confirmed hard** (no unverified second domain, so no parallel run); **`pulllist.app` settled as the
domain to verify in both S0 branches**; **S-1 added** (legacy `mlsend2` DKIM needs the `ms1`/`ms2`
CNAMEs — a live issue found in passing, not part of this migration); **S2 gained the single-SPF-record
merge trap and the 10-lookup ceiling**; zero-risk S0 probe method recorded. **S0 still not run.**
