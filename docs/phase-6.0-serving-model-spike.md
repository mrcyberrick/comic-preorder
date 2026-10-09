# Phase 6.0 — Serving-model spike (S0): how `*.pulllist.app` could be served, and what it costs

**STATUS:** COMPLETE as a decision record (desk research and read-only probes; the Phase 2 live experiment was deliberately SKIPPED by Rick 2026-10-07) — **Phase 6 gate G1 stays OPEN**, with Q2 and Q3 named below as the unanswered questions | staging=docs only 2026-10-07 | prod=N/A (no zone, Pages, Worker, Supabase or code change was made anywhere) | findings=F145,F171,F72

**Written:** 2026-10-07, pre-Phase-6 session G-C (runbook: `docs/pre-phase-6-gate-closure.md` § 2f).
**Parent:** `docs/phase-6-self-service-signup.md` (§ Gating prerequisite, § Readiness G1).
**Evidence tags used below:** **[doc]** a Cloudflare page read 2026-10-06 (URL in § 8; the pages came back through a page-summarising fetch tool, so the quoted phrases are as that tool returned them) · **[measured]** a read-only probe I ran 2026-10-06 or 2026-10-07 · **[export]** Rick's Cloudflare zone export of 2026-10-07 · **[inferred]** my reasoning, not observed · **[unclear]** the sources I could reach do not settle it.

---

## 0. The answer in brief

1. **The model the stub leads with does not exist as written.** Stub model (a), "a single `*.pulllist.app` DNS record + one wildcard TLS cert, no per-tenant custom hostname", cannot be done on Cloudflare **Pages**: Cloudflare's own known-issues page says "It is currently not possible to add a custom domain with a wildcard" **[doc]**. The DNS half and the certificate half are available and free (a proxied wildcard record on any plan; Universal SSL already presents `*.pulllist.app` **[measured]**). **The missing piece is something that serves the app for a name Pages has never heard of.** That means a Worker layer (new moving part, on the path of a hostname printed on customer paper) or moving the build from Pages to Workers static assets.
2. **Cost for D1: a tenant costs about $0 to serve** in every model that fits the free tier. The ceilings are: Workers Free **100,000 script invocations a day across all tenants**, then **$5/month** with 10M requests included (model a); **100 Pages custom domains per project** on Free, 250 on Pro (model c); **100 free Cloudflare-for-SaaS hostnames, then $0.10 each** (model b, which exists for tenants' own vanity domains, not for `<slug>.pulllist.app`).
3. **D4, provisional (nothing here needs deciding until D1 reverses Shape D).** If Phase 6 opens: run the live checks in § 6 for (a) behind a pass-through Worker, with (c) as the fallback that already exists in production for three hostnames, and (b) only later as a paid vanity-domain opt-in. **Confidence in (a) is low** until those checks run: the two behaviours that make or break it are undocumented (Q2, Q3).
4. **G1 is NOT closed.** No model was proven live and the docs do not answer Q2 and Q3 unambiguously. Rick chose to skip the live experiment (2026-10-07): the cost answer D1 lacked came from docs, and Phase 6's own S0 would redo any experiment against the real design.
5. **One new hard precondition: F171** (an unknown `<slug>.pulllist.app` renders as the founding store). Filed 2026-10-07 at Rick's request. **No wildcard record may point at the real app until it is fixed.**

---

## 1. What was done, and what was not

Done: read-only DNS probes (`dns.google`), read-only HTTPS probes of Cloudflare's public edge, one `openssl` certificate read per production hostname, Cloudflare documentation research (Q1-Q8), reading Rick's zone export, and reading `app.js` / `index.html`.

**Not done, by decision:** the Phase 2 contained live experiment (Rick, 2026-10-07: "skip"). **Nothing was changed on any zone, Pages project, Worker, Supabase project or deployed file.** The agent has no Cloudflare API token and made no write of any kind. The only requests sent to production infrastructure were ordinary reads: DNS queries, a TLS handshake to each of the three production hostnames, two `app.js` fetches, and one HTTPS request to Cloudflare's edge for a random hostname that has no record (§ 2.3).

**Not read** (Rick answered the Workers question from the dashboard; he did not paste the rest): the Pages project's own **Custom domains list**, any **Rules** (Origin, Redirect, Transform) on the zone, and the **zone plan**. The three CNAMEs to `pulllist.pages.dev` in the export (apex, `rjbookstop`, `comicstore`) imply at least three Pages custom domains; that count is **[inferred]**, not read.

---

## 2. Step 1: baseline

### 2.1 Zone export (Rick, 2026-10-07) versus public DNS (agent, 2026-10-06 and 2026-10-07)

The export and `dns.google` agree on every name they share. A re-run of the full probe list on 2026-10-07 changed **none** of the 30 lines recorded on 2026-10-06 **[measured]**, so the zone did not move between Step 0 and the record.

| Name | Type (proxied?) | Value (secrets omitted) | Note |
|---|---|---|---|
| `pulllist.app` | CNAME, **proxied** | `pulllist.pages.dev` | publicly visible only as Cloudflare A/AAAA (flattened) |
| `rjbookstop.pulllist.app` | CNAME, **proxied** | `pulllist.pages.dev` | printed on customer paper |
| `comicstore.pulllist.app` | CNAME, **proxied** | `pulllist.pages.dev` | free-tier demo tenant |
| `pulllist.app` | MX x5 | registrar email forwarding | |
| `pulllist.app` | TXT | SPF: `include:_spf.mailersend.net include:spf.efwd.registrar-servers.com ~all` | MailerSend is the dormant rollback path (F99 M8, unscoped) |
| `_dmarc.pulllist.app` | TXT | `p=none`, `rua` to a mailbox on Rick's other domain (address not recorded here) | |
| `send.pulllist.app` | MX + TXT | Resend/SES return path, `include:amazonses.com` | name has **no** address record |
| `resend._domainkey.pulllist.app` | TXT | DKIM public key | live transactional sender |
| `ms1`/`ms2._domainkey`, `mta` | CNAME, DNS-only | MailerSend | dormant |
| **`rjbookstop.pulllist.app`** | **TXT x2** | **Brevo SPF (`include:spf.brevo.com`) and a Brevo verification token** | **omitted from the runbook's Step 1 list** |
| **`brevo1`/`brevo2._domainkey.rjbookstop.pulllist.app`** | **CNAME, DNS-only** | **Brevo DKIM** | **omitted from the runbook's Step 1 list; this is the live weekly newsletter's sender authentication** |

**Absent, confirmed by both sources:** any `A`/`AAAA` record (everything is a proxied CNAME), any `*` wildcard record, `www`, `staging`, any CAA record. A zone export is DNS only, so it cannot show Workers, routes or rules; **Rick answered that question from the dashboard: no Workers are connected.**

**A gap in the runbook, found by the export:** § 2f's Step 1 list named the transactional and MailerSend names but not the Brevo records under `rjbookstop`. Public DNS shows them, but only a name list that includes them would have caught a change. The baseline probe now includes them (appendix). **A future live S0 must treat all of the above as "must not change".**

### 2.2 Names that stay NXDOMAIN today **[measured]**

A random `zzz-probe-*.pulllist.app` (A, AAAA, CNAME, TXT, MX), `_dmarc.<random>`, `spike-<random>`, `www`, `staging`, and `brevo3._domainkey.rjbookstop`: all NXDOMAIN. `_domainkey.rjbookstop.pulllist.app` is NODATA, not NXDOMAIN (it exists as a parent of the two Brevo names).

### 2.3 What the Cloudflare edge itself shows **[measured, 2026-10-06 23:24Z]**

- **A name with no record, sent straight to the edge** (SNI and Host set to a random label, resolved by hand to one of the production edge addresses): **HTTP 530, body `error code: 1016`**, with a **valid certificate whose SAN is `pulllist.app, *.pulllist.app`** (Universal SSL). That is what an unregistered name gets from Cloudflare before any Pages or Worker logic runs. It says nothing about what a proxied wildcard record pointing at a dummy origin would return.
- **The three production hostnames do NOT use that wildcard certificate.** Each presents its **own single-name certificate** (Google Trust Services, about 90 days, auto-renewed): `pulllist.app` (valid 2026-08-10 to 11-08), `comicstore.pulllist.app` (08-17 to 11-15), `rjbookstop.pulllist.app` (09-21 to 12-20). A Pages custom domain gets a per-hostname certificate. A wildcard route would terminate on the Universal certificate instead and would not touch these.
- **`pulllist.pages.dev` serves 200 and the same `app.js` as `origin/main`** (`883d34292426afad`, equal on `pulllist.pages.dev`, `rjbookstop.pulllist.app` and `origin/main` on 2026-10-06). It is the origin a fronting Worker would proxy.

---

## 3. Step 2: the eight questions

| # | Question | Answer | Status |
|---|---|---|---|
| 1 | Can a **Pages** project take a wildcard custom domain? | **No.** Pages known issues: "It is currently not possible to add a custom domain with a wildcard, for example, `*.domain.com`." The Pages custom-domains page itself is silent about wildcards. | **Answered** **[doc]** |
| 2 | Does a **Worker route** `*.pulllist.app/*` plus a proxied wildcard record work in front of Pages, what does an unregistered hostname receive, and can a Worker serve the build itself? | Routes accept wildcard host patterns and require the hostname to have a **proxied** DNS record ("all domains and subdomains must have a DNS record"; without one the result is `ERR_NAME_NOT_RESOLVED`). Workers **Custom Domains** do not support wildcards; only **Routes** do. A Worker with static assets serves them free and unlimited, and `_headers` / `_redirects` work natively. A record-less name gets 530 / 1016 (§ 2.3). **Not found in the pages I read:** a statement that a wildcard route works in front of a Pages project, that an assets-only Worker can take a wildcard route, or what a proxied wildcard pointing at `pulllist.pages.dev` returns for a hostname Pages has not registered. | **Partly unclear** |
| 3 | Does a `*.pulllist.app/*` route also intercept `rjbookstop`, a Pages custom domain? | Precedence is documented: "the most specific route pattern wins", and a route "specified without being associated with a Worker" **negates** less specific patterns, so an exclusion route per explicit hostname is possible. **How a Worker route behaves in front of an existing Pages custom domain is not documented.** Related and worrying: Pages known issues also say you cannot add a custom domain "with a Worker already routed on that domain", so model (a) and model (c) may not coexist on one zone. | **Unclear** |
| 4 | Does Universal SSL cover first-level `*.pulllist.app` for proxied records? | **Yes.** "Universal SSL certificates cover your root domain and first-level subdomains", and the edge presents `*.pulllist.app` **[measured]**. A second level (`*.x.pulllist.app`) needs Advanced Certificate Manager or Total TLS; Pages known issues add "Advanced Certificates cannot be used with Pages due to certificate prioritization conflicts". **ACM price: not on any Cloudflare page I could reach.** The docs table lists it as a "Paid add-on" in all four plan columns; a third-party search summary says $10/month per zone on Pro and up, which conflicts with that table. | **Answered for first level; ACM price unclear** (irrelevant to the first-level design) |
| 5 | DNS semantics | "A wildcard record applies only when no exact record exists at the queried name. If a record or delegation exists, the wildcard does not apply." Wildcards are **multi-level by default** ("`*.example.com` covers both `abc.example.com` and `123.abc.example.com`, unless more specific records exist at intermediate levels"), can be A, CNAME or TXT, and "customers on all plans can create and proxy wildcard DNS records". **Not stated:** whether a name that exists with only other types (`send.pulllist.app` has MX and TXT) would get the wildcard's address answer, and what a random `_dmarc.<x>` TXT query returns. The stub's own safety note (a wildcard **CNAME** answers every record type for non-existent names) is consistent with the multi-level rule but was not tested. | **Mostly answered; type-level behaviour unclear** **[doc]** |
| 6 | Cloudflare for SaaS (model b) | **100 hostnames included** on Free, Pro and Business, **$0.10 per additional hostname**, **50,000 maximum** on non-Enterprise plans. Fallback origin must be a **proxied A, AAAA or CNAME record**; the page does not say whether Pages or a Worker can be one. API: `POST` / `GET` on `/zones/{zone_id}/custom_hostnames`, `GET` / `PATCH` / `DELETE` on `/zones/{zone_id}/custom_hostnames/{custom_hostname_id}` (so the abandoned-tenant sweep **can** reclaim hostnames by API). It exists for **customers' own domains**; `<slug>.pulllist.app` does not need it. | **Answered** except the fallback-origin question |
| 7 | Model (c), per-project Pages custom-domain limit | **100 on Free, 250 on Pro, 500 on Business and Enterprise.** The Pages custom-domains page describes the dashboard flow only; **whether a Pages custom domain can be added by API was not confirmed.** | **Answered**; automation path unclear |
| 8 | Workers free-tier limits | **100,000 requests/day**, **10 ms CPU per invocation**, 50 subrequests per request, 1,000 routes per zone, 100 Workers. Over the daily limit Cloudflare returns Error 1027; the route's fail mode decides whether the Worker is bypassed or the error is returned (that sentence came from the limits page; the routes page did not repeat it). **Paid: $5/month minimum, 10M requests included, $0.30 per additional million.** "Requests to static assets are free and unlimited"; a Worker invoked first (`run_worker_first`) is billed. | **Answered** |

### 3.1 Per-page request count (static estimate, **[inferred]** from this repo, not browser-measured)

Each of the five main pages loads about 8 to 9 same-origin sub-resources plus its own HTML, so about **10 requests on a cold load**. `_headers` makes `app.js`, `config.js` and `vendor/supabase.min.js` `no-cache` (they revalidate on every load) and `style.css` and the HTML are deliberately not long-cached, so a **warm** page view still sends **about five** requests. If a Worker script sat in front of everything, that is **5 to 10 invocations per page view**, i.e. roughly **10,000 to 20,000 page views a day** inside the free 100,000, across all tenants. Production traffic measured 2026-10-04 was about 16 `visit` events a day (32 since 2026-10-02 13:00Z; a visit is one sign-in session of 30 minutes or more apart, not a page view). Even at ten page views a visit that is on the order of 1,600 requests a day, so today's headroom is large (tens of times over), not close. This number matters only for model (a), and only if the Worker runs a script on every request.

---

## 4. The models compared

| | **(a1) Worker route + proxied wildcard record, Worker proxies `pulllist.pages.dev`** | **(a2) Move the build to Workers static assets, wildcard route** | **(b) Cloudflare for SaaS** | **(c) Status quo scaled: one Pages custom domain + DNS record per tenant** |
|---|---|---|---|---|
| What it is | Keeps Pages as the host; a Worker on `*.pulllist.app/*` fetches the build from `pulllist.pages.dev` | Pages project replaced by a Worker whose static assets are the site | Per-hostname custom hostnames on the zone | What `rjbookstop` and `comicstore` are today |
| Per-tenant cost | $0 | $0 | $0 for the first 100, then $0.10/month | $0 |
| Platform ceiling | 100,000 invocations/day Free; $5/month Paid | Asset requests free and unlimited; only scripted requests billed | 100 free, 50,000 max | **100 custom domains per Pages project on Free** |
| Needs a new component on the live path | **Yes** (Worker) | **Yes** (and a Pages-to-Workers migration, touching the project that serves the printed hostname) | Yes (fallback origin) | **No** |
| Unknown / unclaimed name | Resolves to the Worker; **F171 is live** unless fixed | same | not applicable | **NXDOMAIN by default, F171 unreachable by construction** |
| Abuse shape | rows, not money; invocation cap is shared | rows, not money | each tenant is a hostname: abuse costs money past 100 | **abuse fills the 100-domain cap** (denial of onboarding), not money **[inferred]** |
| Provisioning | none per tenant | none per tenant | API call per tenant | **a Pages custom-domain add and a DNS record per tenant** (API path unconfirmed); **a Cloudflare token with DNS-edit scope would have to live in an Edge Function [inferred]** |
| Proven here | Parts only: wildcard DNS and Universal certificate are documented; Worker-in-front-of-Pages is not | No | No | **Yes, for three hostnames (manual)** |
| Open question | Q2, Q3 | Q2 (does an assets-only Worker take a wildcard route) | fallback-origin question; wrong tool for subdomains | automation path (Q7) |

---

## 5. Cost line for D1

**Marginal cost of one more tenant: about $0 in every free-tier model; a bot-created tenant costs rows, not money, except in (c), where it costs headroom under the 100-domain cap.** The first real cost steps, in the order a growing platform would meet them: **$5/month** (Workers Paid) if model (a1) passes about 100,000 scripted requests a day; **$0.10/hostname/month** past 100 vanity domains (b); a Cloudflare **Pro** plan for 250 Pages custom domains (c) (its price was not read). None of these is large next to the founding tenant's $50/month, but none is free of engineering: every one adds provisioning, sweeping and monitoring work that Phase 6 has to own. The stub's cost-hygiene rules (provision the serving entry on **activation**, never on signup; the sweep reclaims it; alert near any ceiling) apply to every model above.

---

## 6. Recommendation, and what a live S0 would have to prove

**D4 (provisional):** if Rick reverses Q3 and Phase 6 opens, make the **first** 6.0 sub-deploy a live check of (a1) behind a **pass-through** Worker, using the checklist below, with (c) as the fallback if the collision check fails (it is the only model that already runs in production, it keeps unknown names NXDOMAIN, and it removes F171 from the critical path, at the price of a 100-tenant ceiling and per-tenant provisioning). Treat (a2) as a later optimisation, because it moves the project that serves the printed hostname. Keep (b) for a paid vanity-domain opt-in, as the stub says. **Do not start any of this until F171 is fixed.**

**Corrections to the stub's text (old wording left in the stub):** (1) "a single `*.pulllist.app` DNS record + one wildcard TLS cert ... no per-tenant custom hostname" is true of DNS and TLS and **false of serving**: Pages will not accept the wildcard. (2) The stub's recommended order says the spike needs "one DNS record on a throwaway label". **A wildcard is not a throwaway label:** one `*` record changes the answer for **every** unregistered name, including `www` and `staging`, which are NXDOMAIN today. (3) `NON_TENANT_HOSTS` (`app.js:32-36`) lists `www.pulllist.app`, which does not resolve. Observed, not filed (not a defect today).

**Checklist for a future live S0 (each check can fail; teardown in the same session, DNS record then route then Worker):**

1. `spike-<random>.pulllist.app` returns 200 with the Worker's marker header, and its certificate SAN includes `*.pulllist.app`.
2. `rjbookstop` and `comicstore` still serve `origin/main`'s bytes, show **no** marker header, and still present their **own single-name certificates** (same SAN as § 2.3). The route must be the narrowest pattern that works; a broad `*.pulllist.app/*` route additionally tests Q3 and only with a pass-through Worker (`return fetch(request)` for every non-spike name).
3. Re-run the baseline probe (appendix): **none** of the 38 lines in § 2 may change except the names the wildcard is meant to answer. Include the Brevo names.
4. Type-level checks the docs leave open: `send.pulllist.app` `A` must **not** return the wildcard's address; a random `_dmarc.<x>` `TXT` and `MX` must return NODATA, not a CNAME; `brevo3._domainkey.rjbookstop` must stay NXDOMAIN and `_domainkey.rjbookstop` must stay NODATA.
5. Record what `www` and `staging` return once they resolve, and what a hostname Pages has not registered returns through the Worker.
6. Teardown: delete the record, then the route, then the Worker; confirm a random label is NXDOMAIN again (record how long the TTL took) and the production bytes and certificates are unchanged. **Halt and tear down first** if a production hostname shows the marker or any email record changes.

**6.0 must also decide before any wildcard serves the real app:** what an unclaimed name renders (404 or the apex marketing page), and how F171's fix tells "no such tenant" from "lookup failed". Phase 6's provisional 6.1 (status filtering in `resolve_tenant_by_slug`) does not cover F171 and would widen it.

---

## 7. Not verified, stated plainly

- **No wildcard record, route or Worker has ever been created for this.** Everything about model (a) is documentation plus the edge probes in § 2.3; the Worker-in-front-of-Pages behaviour is **unproven**.
- **Quoted Cloudflare phrases came through a summarising fetch tool**, not a raw page read. The conclusions I lean on (Q1, the route precedence rule, the limits, the SaaS price) each matched a second page or a measurement where I could check; the Pages-custom-domain **API** and the **ACM price** I could not.
- **The Pages Custom domains list, any zone Rules, and the zone plan were not read** (§ 1).
- The per-page request count is a static estimate (§ 3.1); a real browser measurement was not run.
- Certificates and the 530 / 1016 response describe **2026-10-06**. Cloudflare can change either.
- I did not test a proxied wildcard **CNAME to `pulllist.pages.dev`**, the shape a naive attempt would use. That is the case most worth a real test in 6.0, because it mirrors the existing three records minus the Pages registration.

---

## 8. Sources (all read 2026-10-06)

- Pages known issues (wildcard custom domains, Worker-already-routed, Advanced Certificates): https://developers.cloudflare.com/pages/platform/known-issues/
- Pages custom domains: https://developers.cloudflare.com/pages/configuration/custom-domains/
- Pages limits: https://developers.cloudflare.com/pages/platform/limits/
- Workers routes: https://developers.cloudflare.com/workers/configuration/routing/routes/
- Workers custom domains: https://developers.cloudflare.com/workers/configuration/routing/custom-domains/
- Workers limits: https://developers.cloudflare.com/workers/platform/limits/
- Workers pricing: https://developers.cloudflare.com/workers/platform/pricing/
- Workers static assets billing: https://developers.cloudflare.com/workers/static-assets/billing-and-limitations/
- Pages to Workers migration: https://developers.cloudflare.com/workers/static-assets/migration-guides/migrate-from-pages/
- Universal SSL: https://developers.cloudflare.com/ssl/edge-certificates/universal-ssl/
- Advanced Certificate Manager: https://developers.cloudflare.com/ssl/edge-certificates/advanced-certificate-manager/
- Wildcard DNS records: https://developers.cloudflare.com/dns/manage-dns-records/reference/wildcard-dns-records/
- Cloudflare for SaaS (overview, plans, getting started): https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/ , `.../plans/` , `.../start/getting-started/`
- Custom Hostnames API: https://developers.cloudflare.com/api/resources/custom_hostnames/

---

## Appendix: the baseline probe

Read-only; one DNS-over-HTTPS query per name and type through `dns.google`. Output is sorted and stable, so two runs can be diffed. Usage: `node dns-baseline.mjs <random-label> [outfile]`. The 2026-10-06 run (30 lines) and the 2026-10-07 run (38 lines, the added names being the Brevo and `rjbookstop` records) are identical on every shared line.

```js
import fs from 'node:fs';
const rand = process.argv[2], out = process.argv[3], Z = 'pulllist.app';
const q = [
  [Z,'A'],[Z,'AAAA'],[Z,'MX'],[Z,'TXT'],[Z,'NS'],[Z,'CAA'],
  ['www.'+Z,'A'],['www.'+Z,'CNAME'],
  ['rjbookstop.'+Z,'A'],['rjbookstop.'+Z,'AAAA'],['rjbookstop.'+Z,'CNAME'],
  ['comicstore.'+Z,'A'],['comicstore.'+Z,'AAAA'],['comicstore.'+Z,'CNAME'],
  ['staging.'+Z,'A'],['send.'+Z,'MX'],['send.'+Z,'TXT'],['mta.'+Z,'CNAME'],
  ['rjbookstop.'+Z,'TXT'],['comicstore.'+Z,'TXT'],['rjbookstop.'+Z,'MX'],
  ['brevo1._domainkey.rjbookstop.'+Z,'CNAME'],['brevo2._domainkey.rjbookstop.'+Z,'CNAME'],
  ['_domainkey.rjbookstop.'+Z,'TXT'],['brevo3._domainkey.rjbookstop.'+Z,'CNAME'],['_dmarc.rjbookstop.'+Z,'TXT'],
  ['resend._domainkey.'+Z,'TXT'],['ms1._domainkey.'+Z,'CNAME'],['ms2._domainkey.'+Z,'CNAME'],
  ['_dmarc.'+Z,'TXT'],['_dmarc.'+rand+'.'+Z,'TXT'],
  [rand+'.'+Z,'A'],[rand+'.'+Z,'AAAA'],[rand+'.'+Z,'CNAME'],[rand+'.'+Z,'TXT'],[rand+'.'+Z,'MX'],
  ['spike-'+rand+'.'+Z,'A'],['*.'+Z,'A'],
];
const lines = [];
for (const [name, type] of q) {
  const j = await (await fetch(`https://dns.google/resolve?name=${encodeURIComponent(name)}&type=${type}`)).json();
  const ans = (j.Answer || []).map(a => `${a.type}:${a.data}`).sort();
  lines.push(`${name} ${type} -> Status ${j.Status}${ans.length ? ' | ' + ans.join(' ; ') : ''}`);
}
const text = lines.join('\n') + '\n';
if (out) fs.writeFileSync(out, text);
process.stdout.write(text);
```
