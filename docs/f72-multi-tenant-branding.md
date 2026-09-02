# F72 — multi-tenant branding: remove the founding tenant's identity from every tenant-facing surface

**STATUS:** **RESEQUENCED 2026-09-02 (later, same day) — S0 written up and moved to first; NOT
STARTED.** § 8 Q1–Q6 (2026-09-01) still hold for *what data exists*; **§ 0.1 is a premise change** —
branding is gated on `tenants.plan`, not uniform. **Q7–Q9 answered 2026-09-02**; **Q10–Q11 answered
2026-09-02 (later)** — paid-tier email promise, and how the tier check is shared across six Edge
Functions. **§ 4.0 (S0) is byte-exact and ready to execute**, re-read from disk 2026-09-02 and
verified against the post-Resend tree. **§ 4.1–§ 4.3 (S1/S2/S3) are still design-level** and owe the
free/paid-content-per-site pass § 0.1's closing note describes — do not execute them from their
current text. | staging=— | prod=— | findings=F72,F99,F145,F151

**Owner finding:** F72 (`docs/technical-reference.md` § 13). This plan **widens F72's
recorded scope** — it is filed as one email template in `register-customer`, and the
measured surface is 6 Edge Functions plus 24 client line sites across 7 files.

**Prerequisite reading:** `docs/phase-5.3-per-tenant-branding.md` § 1.1 and § 1.5 (the
`Branding.apply()` contract and the deliberate `resolve_tenant_by_slug` projection
boundary this plan **preserves**); `docs/f99-sender-domain-consolidation.md` § 4 S1 (the
`MAIL_FROM_NAME` / `MAIL_FROM_EMAIL` parameterization this plan builds on).

**Target: staging only.** Production promotion is a separate, explicitly-requested step
per CLAUDE.md § Staging Only.

---

## 0.1 Tier-gated branding — 2026-09-02 revision (read this first)

**This section changes the plan's premise. Everything below it (§ 1–§ 10) was written and approved
2026-09-01 against a *uniform-for-everyone* branding model. That model is superseded — Rick's
explicit direction, decided in a planning conversation 2026-09-02, after F99's own migration
finished (both environments, same day): branding is now split by `tenants.plan`, and the split is
the product's actual free-vs-paid lever, not an afterthought layered on top of a uniform fix.**

### Why this changed

F72 was originally framed as pure defect-fixing — "the software works for two tenants" (Phase 5)
vs. "the software can be sold to a second tenant" (blocked by identity leaks). That framing produced
a plan where every tenant, paid or free, gets full identity everywhere. But the live pricing page
(`index.html:247-262`) already sells a "Branded" tier — *"your own `yourshop.pulllist.app` address,
your logo and colors, and customer emails from your shop"* — and a uniform-for-everyone F72 would
make that entire value proposition **disappear the moment F72 shipped**: two of its three claimed
perks (subdomain, logo/colors) would already be free-tier baseline, and the third (branded sending
address) isn't built by F72 at all (F99 kept the sending address flat for everyone, deliberately).
Nobody had caught that collision before this conversation.

### The mechanism: `tenants.plan` — already exists, already has live values, currently dead code

No new schema needed. `tenants.plan` (`text NOT NULL DEFAULT 'free'`) has existed since before this
plan was written (`docs/technical-reference.md` § 4.1) and is **read by zero lines of code anywhere**
— confirmed by grep across `app.js` and every Edge Function, 2026-09-02.

**Live values, checked 2026-09-02 (service-role read-only):**

| Environment | Tenant | `plan` |
|---|---|---|
| staging | `raysandjudys` (test proxy for the founding tenant) | `pro` ✅ |
| staging | all four `pw-*` Playwright fixtures | `free` (correct — none are paying) |
| production | **`rjbookstop` — the real, paying, $50/mo Ray & Judy's Book Stop** | **`free` ❌ — a real data bug** |
| production | `comicstore` (demo/test, never a real customer) | `free` ✅ correct |

**Production's actual paying tenant is currently marked `free`.** This must be corrected
(`UPDATE tenants SET plan = 'pro' WHERE slug = 'rjbookstop'`) as part of shipping this work, not
left for later — shipping tier-gated branding without that fix would flip Ray & Judy's own
production site to generic branding, which is exactly backwards. **New completion-criteria item**, see
§ 9.

### The surface-by-surface design (Rick, 2026-09-02)

The balance being struck, stated explicitly so it isn't re-derived: **free tier needs enough
identity to establish trust with a new customer** (a shop's own name, so the relationship reads as
legitimate, not as a generic tool) **while paid tier needs enough held back to motivate upgrading**
(full identity, custom visual branding, and a branded link). The four rows differ in how much of
that identity shows, and the pattern is deliberate — web and email are where a free customer needs
to trust the shop is real, so the name shows; print has the least trust-building need (handed over
in person by a staffer the customer already trusts) and the most visible upgrade nudge (an owner
sees their own pickup slips carry no name/phone and that's a concrete, tangible reason to pay):

| Surface | Free tier | Paid tier |
|---|---|---|
| **Color / logo** — everywhere | PULLLIST apex defaults, always — `branding.primary_color`/`branding.logo_url` are **never** applied | Tenant's own `primary_color` / `logo_url` (existing `Branding.apply()` mechanism, § 1.3) |
| **Web pages** (nav, footers, pending-approval messages, welcome modal) | Tenant's own `display_name` shown (trust signal) | `display_name` + `contact_phone` + `location` + `branding.website` shown wherever § 2.1 already identifies a site |
| **Emails** (all six Edge Functions) | PULLLIST template chrome + tenant name in subject/greeting/`from` display-name; footer carries **no** shop phone/address; **link: `pulllist.app`** | Name + phone + address in the footer; PULLLIST chrome (color stays platform-default here too, same rule as web); **link: `<slug>.pulllist.app`** |
| **Print-outs** (My List, pickup slips, bagging list, catalog print) | **Fully generic** — no name, no phone, no address; **link: `pulllist.app`** | Full identity — name + phone + street address, matching what's live today; **link: `<slug>.pulllist.app`** |

### The link-by-tier requirement — new work, not a small addition

**Every email and every print-out gets a "View Online" style link, and which URL it carries is
itself tier-gated.** This is genuinely new scope in three ways:

1. **It resolves § 4.3's blocked hostname item, but only for paid tenants.** § 4.3 (below, 2026-09-01)
   correctly blocked deriving `<slug>.pulllist.app` unconditionally — F145 measured there is no
   wildcard DNS, so an unprovisioned tenant's paper would carry a **non-resolving URL**. This
   revision doesn't lift that block for everyone; it resolves it narrowly: **`<slug>.pulllist.app`
   is only ever printed/emailed for a `plan = 'pro'` tenant, and provisioning that hostname becomes
   a required, manual step of onboarding a tenant to paid** (same mechanism as `comicstore` today,
   5.5's pattern) — not a self-serve or wildcard mechanism. A paid tenant without a provisioned
   subdomain is a shipping error, not an edge case to handle gracefully.
2. **Free tier's link is always safe** — `pulllist.app` is the apex, always resolves, needs no
   per-tenant provisioning. This is also new: today's print-outs that already carry a "View Online"
   link (`admin.html`'s Bagging List and Print Catalog, PR #140) hardcode
   `rjbookstop.pulllist.app` unconditionally — that becomes tier-conditional too.
3. **No email carries any such link today.** All six templates' only links are the specific
   action URL (reset link, magic link, catalog CTA) — verified by re-reading all six in this same
   session (F99 M2). A generic "View Online: `{link}`" line is new copy in every template's footer.

### What this means for § 4's work breakdown

**S1–S4 below (2026-09-01) still describe correct mechanics — the data plumbing, the `Branding.apply()`
extension, the client hook pattern, the Edge Function tenant-row fetch — but every render decision
in them needs a `plan === 'pro' ? tenantValue : genericDefault` branch, not the unconditional
`tenantValue ?? foundingLiteral` fallback they currently describe.** Concretely:

- **The `??`/`||` fallback content changes meaning.** Today's fallback literals
  (`noreply@mrcyberrick.us` / "Ray & Judy's Book Stop" / the street address) exist so an
  *unresolved* tenant renders safely. Under tier-gating, the **free-tier branch is not a fallback
  for a broken lookup — it is the deliberately-shipped free experience**, and its content must be
  genuinely generic (PULLLIST-only), never a specific tenant's literal identity. Re-using Ray &
  Judy's info as the "default" would re-introduce F72's original defect for every free tenant.
- **S1** (client) needs a `TenantContext.current().plan` (or equivalent) read available wherever
  § 2.1's hooks render, gating name/phone/location/website/color/logo independently per the table
  above — not a single flag, since web shows name-for-free but print does not.
- **S2** (Edge Functions) needs each function's tenant-row fetch to include `plan`, and the
  subject/body/footer construction to branch on it — including the new "View Online" line.
- **S3** (print) needs the *existing* `rjbookstop.pulllist.app` literals in `admin.html` made
  tier-conditional (§ 4.3 above), extended to **mylist.html and arrivals.html's print outputs**,
  which today have no such link at all and were explicitly out of scope for PR #140.
- **A new S0** (implied, not yet written up as steps): fix `rjbookstop`'s `plan` value; write the
  shared `plan === 'pro'` check as one helper both client and server code call, rather than six
  independent ternaries; decide and write the exact generic-tier copy (what a free-tier email
  subject/footer/print header literally says).

**This section is a design record, not a byte-exact implementation plan.** § 4's own steps need a
real rewrite pass — re-reading every site in § 2.1 from disk and stating its free-tier and paid-tier
content explicitly — before this is ready to execute. That pass has not happened yet.

### New decisions (Q7–Q9), same numbering series as § 8

| # | Question | ✅ DECISION |
|---|---|---|
| **Q7** | What gates the tier? | **`tenants.plan`** (`'free'` \| `'pro'`) — already exists, was dead code. `rjbookstop` must be corrected to `'pro'` before/as part of shipping (data bug, § 0.1 above) |
| **Q8** | What does "generic" free-tier content actually say? | Web/email: tenant's own name, PULLLIST chrome, no phone/address, link to `pulllist.app`. Print: no identity at all beyond PULLLIST, link to `pulllist.app`. Color/logo: PULLLIST defaults on every surface, both tiers' emails, and paid-tier email chrome too — **the one thing that's never tenant-customized on email regardless of plan** |
| **Q9** | Should `<slug>.pulllist.app` ever appear for a free tenant? | **No, never.** Only `plan = 'pro'` tenants get the subdomain link, and only once it's been manually provisioned as part of their paid onboarding — never derived/assumed (F145's own warning) |
| **Q10** | The live pricing page (`index.html:247-262`) sells "Branded" as including *"customer emails from your shop"*, but F99 deliberately shipped a **flat `noreply@pulllist.app` sender for every tenant**. What does paid tier actually promise on email? | **Footer identity + branded link; edit the pricing copy to match.** Paid emails carry the shop's name as the `from` **display name**, name + phone + full postal address in the footer, and a `<slug>.pulllist.app` "View Online" link. **The sending address stays flat for both tiers** — no new DNS, no new domain slot, no reopening of F99's addressing decision. ⚠️ **Consequence: `index.html:247-262` is now knowingly stale copy and must be edited as part of this work** — see § 4.4 S4. Rejected alternative: per-tenant sending addresses, which Resend's own D7 probe makes expensive (a verified parent does **not** cover subdomains, so each paid tenant costs a domain slot — Resend Pro, $20/mo) |
| **Q11** | § 9 requires the tier check be "written once … not six independent ternaries". There is no `_shared/` folder and **zero cross-function imports** in this repo (verified 2026-09-02); F99 S1 duplicated its `MAIL_FROM_*` constants six times instead. | **Six byte-identical copies, plus V10 — a grep gate that fails when they diverge.** Satisfies the criterion's intent (no *divergent* ad-hoc ternaries) with a property that is **checked** rather than assumed, and keeps the codebase's existing zero-import EF convention intact across six `verify_jwt`-sensitive deploys. Full reasoning and the canonical block: § 4.0.1 (4) |

---

## 0.2 Why this is worth doing now

PULLLIST is being priced and sold to other shops (Founding Partner tiering). Today a
second shop's customers would receive email and printed pickup slips carrying **Ray &
Judy's Book Stop's name, street address, phone number and website** — a competing shop's
identity, on paper, in their own customers' hands.

That is the single blocking defect between "the software works for two tenants" (true
since Phase 5) and "the software can be sold to a second tenant" (not true today).

**This plan closes that gap without touching DNS, MailerSend domains, or Phase 6.**

---

## 1. What is already true — measured 2026-09-01, not assumed

### 1.1 The schema is already there

`tenants` already carries the columns this work needs (`docs/technical-reference.md` § 4.1):

| Column | Type | Nullable |
|---|---|---|
| `display_name` | text | NO |
| `contact_email` | text | YES |
| `contact_phone` | text | YES |
| `location` | text | YES |
| `branding` | jsonb | YES (`{}`) |

`docs/tenant-onboarding-runbook.md` Step 1 already **collects** `contact_email`,
`contact_phone` and `location` in the `register-tenant` body. Nothing reads them.

**⇒ Steps S1 and S2 need NO DDL and NO migration.** This is the single biggest
difference between this plan and the shape F72's filing implies.

### 1.2 No RPC change is needed either — and 5.3's decision stands

`resolve_tenant_by_slug` returns `id, slug, display_name, branding` and, per
`phase-5.3-per-tenant-branding.md` § 1.5, **deliberately** excludes `contact_*`.

`TenantContext` has two resolution sources (`app.js:53-62` RPC, `app.js:82-86` profile):

| Source | Path | How the tenant row is read |
|---|---|---|
| `slug` | anon, pre-sign-in | `resolve_tenant_by_slug` RPC — 4 columns, no `contact_*` |
| `profile` | authenticated | **direct `.from('tenants').select(...)`** — RLS permits SELECT on the user's own tenant row (§ 4.1: *"Authenticated users can SELECT only their own tenant"*) |

**Every Tier-A client surface in § 2 below is on an authenticated page.** So the
authenticated branch's `select()` is simply widened to include `contact_phone, location`
— row-level RLS already permits it, no policy change, no RPC change, and 5.3's anon
projection boundary is left exactly as it is.

> **⚠️ TRAP — the constraint this creates.** After S1, `[data-tenant-phone]` and
> `[data-tenant-location]` resolve **only under the `profile` source**. Adding either
> hook to an anon-reachable surface (`index.html`'s landing panel,
> `forgot-password.html`) renders the founding literal to every tenant — silently, with
> no error. **Widening the RPC is the prerequisite for that, and it is out of scope
> here (§ 6).** `index.html` today shows a name but no phone or location, which is why
> this plan can stop short of the RPC.

### 1.3 `Branding.apply()` covers exactly three things

`app.js:172-201`. Called twice: `app.js:467` (`initNav`, all six nav pages) and
`index.html:561` (anon landing).

| Key | Effect |
|---|---|
| `branding.primary_color` | `--accent` / `--accent-hover` / `--accent-dim` |
| `tenant.display_name` | `textContent` of every `[data-tenant-name]` |
| `branding.logo_url` | `src` of every `img[data-tenant-logo]` |

Everything else on every page is a literal.

### 1.4 Existing `[data-tenant-name]` coverage is partial and uneven

| Page | `data-tenant-name` | `data-tenant-logo` |
|---|---|---|
| `index.html` | 2 | 1 |
| `arrivals.html` | 3 | 0 |
| `catalog.html` / `mylist.html` / `subscriptions.html` / `admin.html` / `analytics.html` | 1 each | 0 |
| `forgot-password.html` | 0 | 0 — **verified carrying no store identity at all; correctly neutral, needs no work** |

### 1.5 Five of the six Edge Functions already hold a tenant UUID

| Function | Tenant UUID in hand? | Where |
|---|---|---|
| `register-customer` | ✅ — **already fetches the `tenants` row** (`index.ts:243`, `select=id,slug,display_name`) and **discards `display_name`**, using only `id` | slug lookup |
| `approve-customer` | ✅ `target.tenant_id` | `index.ts:83`, `:100` |
| `invite-customer` | ✅ `callerTenantId` | `index.ts:62` |
| `notify-customers` | ✅ `callerTenantId` | `index.ts:69` |
| `send-my-list` | ✅ `callerTenantId` | `index.ts:97` |
| `reset-password` | ❌ **none — zero `tenant_id` references in the file** | — |

So S2 is *one* new tenant-row fetch per function (all six need the row, not just the
id), plus *one* new id-derivation in `reset-password` alone (§ 4.2.2).

### 1.6 The sending identity is already a variable

F99 S1 (`eff9793`, staging) made all six read `MAIL_FROM_EMAIL` / `MAIL_FROM_NAME` via
`Deno.env.get()` with a `??` fallback to the founding literal. Those fallbacks are six
of the Tier-A leaks in § 2, and S2 replaces the **name** half with the tenant's own.

### 1.7 The live tenant data — measured 2026-09-01, and it changes two things

Service-role read-only against both projects (jsonb **key names only**; no secret value was
fetched or recorded):

| Env | Tenant | `contact_phone` | `location` | `branding` keys |
|---|---|---|---|---|
| staging | `raysandjudys` | `973-586-9182` | `Rockaway, NJ` | `promo_banner` |
| staging | `pw-fc2e3fc7`, `pw-2d3c4d60` | NULL | NULL | `promo_banner`, `primary_color` |
| staging | `pw-56132e92`, `pw-a62e4116` | NULL | NULL | `{}` |
| prod | `rjbookstop` | **NULL** | **NULL** | `promo_banner` |
| prod | `comicstore` | `555-555-5555` | `New Jersey` | `display_name`, `primary_color` |

**Three consequences the plan had wrong before this read:**

1. **There is no `comicstore` on staging.** The second tenant exists on **production only**.
   Staging holds the founding tenant plus four `pw-*` Playwright fixture tenants. **V3 as
   originally written — "sign in as a `comicstore` user on staging" — was impossible.** It is
   rewritten in § 5 to use a `pw-*` fixture tenant, which is the only second-tenant vehicle
   staging actually has.
2. **`location` is currently a city string, not a postal address** (`Rockaway, NJ`). Under Q1
   this value must be **changed**, not merely populated — and `Rockaway, NJ` becomes
   `branding.location_short`. Production's founding tenant has **both fields NULL**, so it needs
   populating from scratch before S1 renders anything there.
3. **`branding` has a fourth key in live use that no doc lists: `promo_banner`** — read by
   `catalog.html:508`, documented in `docs/subscription-promotion.md`, absent from the onboarding
   runbook's key table. Not this plan's defect, but S4 fixes the list while it is there.

**Also found, and it is a live doc defect:** `tenant-onboarding-runbook.md` Step 2 instructs
operators to write `display_name` **into the `branding` jsonb** — and `Branding.apply()` reads the
`tenant.display_name` **column** (`app.js:186`), never `branding.display_name`. Production's
`comicstore` has the jsonb key set, and **it is ignored**. Harmless today only because the column is
`NOT NULL` and therefore always populated. S4 corrects the runbook.

**`tenants.settings` finding:** the same probe found `mailerlite_webhook_secret` still stored on all
three real tenant rows — **filed as F151** (§ 6 discovery 2, resolved disposition below).

---

## 2. The measured leak inventory

Every line below was read from disk on 2026-09-01. **Re-verify before editing** —
line numbers in this repo drift (CLAUDE.md § File Drift Prevention).

### 2.1 Tier A — a competing shop's customer sees a competitor's identity

**Client — 18 line sites across 7 files:**

| Surface | Site | Leaks |
|---|---|---|
| Pending-approval message | `catalog.html:331` | name |
| Pending-approval message | `mylist.html:801` | name |
| Pending-approval message | `subscriptions.html:432` | name |
| Welcome modal copy | `app.js:1635` | name |
| Logo `alt` text | `index.html:313` | name |
| Invite landing copy | `index.html:337`, `:346` | name |
| My List print header | `mylist.html:547`, `:548` | name + phone |
| My List pickup note | `mylist.html:562` | phone ×2 (body text + `tel:` href) |
| Arrivals print header | `arrivals.html:390` | phone (name at `:389` **is** wrapped) |
| Pickup slip store block | `arrivals.html:496` | phone (name at `:495` **is** wrapped) |
| Pickup slip CTA foot | `arrivals.html:527` | phone |
| Bagging list print header | `admin.html:3825`, `:3826` | name + phone + `rjbookstop.com` + hostname |
| Print catalog header | `admin.html:5134` | hostname |
| Print catalog `@page` footer | `admin.html:4966`, `:5354` | `rjbookstop.com` + hostname |

**Edge Functions — all six:**

| Function | `MAIL_FROM_NAME` fallback | Subject | Body / footer |
|---|---|---|---|
| `approve-customer` | `:17` | `:168` | `:194`, `:199`, `:216`, `:223`, `:227` |
| `invite-customer` | `:5` | `:114` | `:163`, `:168`, `:184`, `:191`, `:195` |
| `notify-customers` | `:2` | `:192` | `:164`, `:173`, `:175` |
| `register-customer` | `:40` | `:148` | `:279`, `:284`, `:304`, `:308`, `:312` |
| `reset-password` | `:4` | `:77` | `:101`, `:121`, `:125` |
| `send-my-list` | `:2` | `:153-154` | `:197`, `:228`, `:233` |

Every one of the six footers carries `40 W Main St. Rockaway, NJ 07866 · (973) 586-9182`.

> **Both `admin.html` print outputs are Tier A, not staff-only.** The record for PR #140
> states the print CTA's own rationale — *"paper that lands in a customer's hands should
> carry a path back to an account"* — and applies it to exactly these two outputs (Print
> Catalog / Print Bagging List). They are customer-facing paper by Rick's own scoping.

### 2.2 Tier B — cosmetic: a wrong city in the shared footer

`· Rockaway, NJ` is a literal sitting **outside** the `[data-tenant-name]` span beside it,
on all six nav pages: `catalog.html:266`, `mylist.html:666`, `arrivals.html:538`,
`subscriptions.html:327`, `admin.html:578`, `analytics.html:547`.

### 2.3 Not a leak — leave alone

`PULLLIST`, `PullList pre-order system`, `Monthly Comics Pre-Order System`, and
`pulllist.app` (the apex CTA at `arrivals.html:527`) are **platform** branding and are
correct for every tenant. This plan parameterizes *store* identity only.

---

## 3. The separation that makes this shippable — F72 is not blocked by F99

> ⚠️ **Overtaken by events, kept for the record — F99 is done, both environments, 2026-09-02.**
> The reasoning below was written 2026-09-01 while F99 S3 was genuinely stuck. It resolved the same
> day this revision was written, via a different provider (Resend) rather than the blocked
> MailerSend path — see `docs/f99-resend-migration.md`. The **conclusion** (F72 doesn't need to
> wait on F99) still holds, for a stronger reason than the one below: there's no longer anything to
> wait *for*. **The specific address** cited below is wrong — see the correction after the list.

F99's § 13 entry says F99 *"must be designed together with F72, not sequenced ahead of
it."* That constrained **F99**. It never made F72 wait on F99, and by 2026-09-02 there's nothing
left to wait on:

- ~~**F99 S3 is stuck.**~~ **Resolved 2026-09-02** — not by unsticking S3, by replacing it. Both
  environments now send via Resend, `noreply@pulllist.app`, cleanly authenticated on both
  mechanisms. See `docs/f99-resend-migration.md`.
- **The From *name* is free text**, same fact under either provider. Resend takes a display name
  alongside a verified From address exactly like MailerSend did, so `"Comic Shop X"
  <noreply@pulllist.app>` needs **zero** DNS work. F99 S1's parameterization survived the provider
  swap unchanged in shape.
- **Body, subject and footer are pure template code.** No vendor involvement at all.

**Corrected sending address:** mail now arrives from **`noreply@pulllist.app`**, not
`noreply@mrcyberrick.us` — flat, for every tenant, any `plan` value, per § 0.1 Q8. If anything this
argument is *stronger* now than the original "odd, not a competitor's shop" framing: `pulllist.app`
reads as the platform's own domain, not as any one shop's (founding or otherwise), so there's no
longer even a founding-tenant-flavored oddity to explain away.

The one hard F145 dependency is § 4.3's hostname half — **resolved for paid tenants**, § 0.1 Q9.

---

## 4. Work breakdown

**Four steps** (S0 added 2026-09-02), each independently shippable and independently revertible.

**S0 is now first and is a hard prerequisite for the other three** — every render decision in S1,
S2 and S3 branches on the tier input S0 provides. **S1 and S2 still do not depend on each other**
and may be done in either order or in one branch once S0 has landed; S3 depends on S1's helper
existing.

*(This paragraph read "Three steps" and described S1 as the entry point, from the 2026-09-01
uniform-branding plan. § 0.1's tier revision made S0 load-bearing, and this pass wrote it up as
§ 4.0.)*

### 4.0 S0 — The tier mechanism (no render change anywhere)

**Added 2026-09-02, Rick's explicit direction.** S0 did not exist as a step until this pass — § 0.1
named it only as *"a new S0 (implied, not yet written up as steps)."* It is now the **first**
shippable step, and it is deliberately the one step that changes **no rendered output on any
surface**: it makes the system able to *identify* a paid tenant — the stated success criterion —
without yet acting on that identity anywhere.

**Why first.** Every render decision in S1, S2 and S3 needs a `plan === 'pro'` branch (§ 0.1). Ship
that branch's *input* once, verifiably, and the three leak-closing steps each become a mechanical
edit against a helper that already exists and is already proven. Ship it last and every S1 site
gets reopened.

**S0 touches zero leak sites.** All 18 Tier-A client sites, all 6 Tier-B footers and all six email
templates render byte-identically before and after. That is what makes V6 cheap here, and it is the
property to protect while editing.

#### 4.0.1 Byte-exact edits — re-read from disk 2026-09-02

**(1) `app.js` — widen the authenticated tenant read.** Line 84 today (verified 2026-09-02):

```
            .select('id, slug, display_name, branding')
```

becomes

```
            .select('id, slug, display_name, branding, plan')
```

RLS already permits it (§ 1.2) — row-level, no policy change, no RPC change. **Leave
`lookupTenantBySlug()` and `resolve_tenant_by_slug` untouched** (§ 1.2 trap): `plan` deliberately
does **not** reach the anon path, so no anon-reachable surface may branch on tier. See § 4.0.4.

> ⚠️ **Sequencing note for S1.** § 4.1 step 1 describes this same line and was written against its
> **pre-S0** text. After S0 the line reads `'id, slug, display_name, branding, plan'`, and S1's edit
> adds `contact_phone, location` to *that* string. Re-read the line from disk before editing it —
> do not apply § 4.1's `old_str` literally.

**(2) `app.js` — add the `Tier` helper.** Insert immediately after `window.Branding = Branding;`
(line 202 today) and before the `// ── Auth Helpers ──` banner. It reuses `TENANT_APEX`
(`'pulllist.app'`, `app.js:37`) rather than restating the apex:

```js
// ── Plan Tier ────────────────────────────────────────────────
// Reads tenants.plan. 'pro' ⇒ full identity; anything else ⇒ platform defaults.
// Fails CLOSED: an unresolved tenant, a missing plan, or the anon path (which
// never selects plan — § 1.2) all evaluate to free. A free render is always safe;
// a wrong paid render puts an unprovisioned hostname on customer paper (F145).
const Tier = {
  isPaid(tenant) {
    return !!(tenant && tenant.plan === 'pro');
  },
  // The "View Online" target. Paid ⇒ their provisioned subdomain; free ⇒ the apex.
  publicUrl(tenant) {
    return this.isPaid(tenant) && tenant.slug
      ? `${tenant.slug}.${TENANT_APEX}`
      : TENANT_APEX;
  },
};
window.Tier = Tier;
```

**Fail-closed is the whole design, not a defensive nicety.** Free is the safe render: it shows less
identity and links to an always-resolving apex. Paid is the *unsafe* default, because
`publicUrl()`'s paid branch emits `<slug>.pulllist.app`, and F145 measured that there is **no
wildcard DNS** — an unprovisioned slug puts a non-resolving URL on customer paper. Every ambiguous
state must therefore land on free.

**(3) `supabase/functions/register-tenant/index.ts` — accept a plan at create.** Today line 148
hardcodes `plan: 'free'` and **no runbook step sets it afterwards**, so there is currently no
supported path to create a paid tenant at all. *(Found 2026-09-02 during this pass; not previously
recorded in this plan.)*

Add to the input block (after `location`, line 109):

```ts
    const planRaw       = (body.plan as string | undefined)?.trim().toLowerCase() || 'free'
    const plan          = planRaw === 'pro' ? 'pro' : 'free'
```

and change the insert body's `plan:     'free',` (line 148) to `plan,`. **Allowlist, not
pass-through** — an unrecognized value must become `free`, never reach the column, and never error.
The column is `NOT NULL` with **no CHECK constraint**, so a typo like `'Pro'` would otherwise
persist and read as free forever while looking paid to an operator inspecting the row.

**(4) The Edge Function tier block — six identical copies, gated on byte-identity.** There is no
`_shared/` folder in this repo and **zero cross-function imports exist today** (verified
2026-09-02); F99 S1 set the precedent by duplicating its `MAIL_FROM_*` constants across all six
functions rather than sharing them. S0 follows that convention. **Not deployed in S0 itself** — no
function reads a tenant row until S2 — but the block is *defined* here so S2 has one canonical text
to paste and V10 has something to assert against:

```ts
// ── Plan Tier ── keep byte-identical across all six mail functions (F72 S0) ──
const isPaidTenant = (t: { plan?: string } | null) => t?.plan === 'pro'
const tenantPublicUrl = (t: { plan?: string; slug?: string } | null) =>
  isPaidTenant(t) && t?.slug ? `${t.slug}.pulllist.app` : 'pulllist.app'
```

> **On § 9's "written once" criterion.** A `_shared/tier.ts` import would be *literally* once, but
> it introduces a cross-function import convention this codebase has never used, and it changes what
> `supabase functions deploy` bundles — across six deploys that each already carry F93 `verify_jwt`
> discipline. Six byte-identical copies plus **V10, a grep that fails when they diverge**, satisfies
> the criterion's intent (no six *independent, divergent* ternaries) with a property that is
> *checked* rather than assumed. Recorded as **Q11**. If a later step needs genuinely shared EF code
> for other reasons, revisit — this is a convention call, not a technical limit.

#### 4.0.2 The data fix — `rjbookstop` is marked `free` on production

**A real data bug, not a migration.** Production's paying tenant reads `plan = 'free'` (§ 0.1,
measured 2026-09-02, service-role). Ship tier-gating without fixing it and Ray & Judy's own
production site flips to generic branding — exactly backwards.

```sql
-- production only
UPDATE public.tenants SET plan = 'pro' WHERE slug = 'rjbookstop';
SELECT slug, display_name, plan FROM public.tenants ORDER BY slug;
-- Expected: comicstore = free, rjbookstop = pro
```

**Run by Rick, not the agent** — the established pattern for anything touching live data
(CLAUDE.md § Document Integrity). **Safe to run before any code ships, and it should be:** with
`plan` read by zero lines today, the UPDATE is inert until S1 lands. Doing it early de-risks the
sequence instead of making it a launch-day step.

**Staging needs a durable `free`/`pro` pair for V3/V4.** `raysandjudys` is already `pro`; the only
`free` tenants are the four `pw-*` Playwright fixtures, which are **ephemeral and torn down**
(§ 1.7, F130) — not a vehicle to verify against. Create one purpose-made staging tenant via
`register-tenant`; with S0's new `plan` input this is a single call rather than a create-then-UPDATE.

#### 4.0.3 Onboarding — the runbook half of "identify a paid tenant"

`docs/tenant-onboarding-runbook.md`, three edits. **These are what make paid onboarding a supported
path rather than an undocumented manual UPDATE:**

1. **Step 0/1 — `plan` becomes a collected input.** Add to Step 0's input table and Step 1's
   `register-tenant` body. Default `free`; `pro` only for a tenant who is actually paying.
2. **New Step 2b — a paid tenant's hostname must be provisioned.** § 0.1 Q9 puts
   `<slug>.pulllist.app` on paid customers' paper and in their email. Step 3 already provisions the
   Cloudflare custom hostname; make it **required, not optional, when `plan = 'pro'`**, and state
   the consequence plainly: a paid tenant whose hostname is unprovisioned ships a non-resolving URL
   to real customers. F145's warning, now load-bearing rather than advisory.
3. **Step 2's SQL is wrong, re-confirmed live this pass.** Line 88 writes `display_name` into the
   `branding` jsonb; `Branding.apply()` reads the `tenant.display_name` **column** (`app.js:186`)
   and ignores the jsonb key entirely. Production's `comicstore` carries the ignored key today.
   Already recorded as § 4.4 S4 fix 3 — **pull it forward into S0**, because S0 is the step an
   operator follows to create the V3 test tenant, and following it as written seeds the wrong shape.

#### 4.0.4 Explicitly NOT in S0

- **Any render change.** No `data-tenant-*` hook, no template edit, no print change. If a diff
  changes a rendered byte, it belongs in S1/S2/S3.
- **Widening `resolve_tenant_by_slug`.** `plan` stays off the anon path (§ 1.2 trap, § 6). A
  consequence worth stating: **no anon-reachable surface can tier-gate** — `index.html`'s landing
  panel and `forgot-password.html` render platform-default for every tenant, which is correct and
  needs no work (§ 1.4 confirms `forgot-password.html` carries no store identity at all).
- **Billing, plan self-service, an upgrade flow.** `plan` is set by Rick at onboarding or by UPDATE
  (§ 6). S0 adds an input to `register-tenant`; it does not add a way for a tenant to change their
  own tier.
- **Free-tier service restriction.** Rick's explicit sequencing, 2026-09-02: identity and branding
  first, lockdown later. `Tier.isPaid()` is the hook a future restriction step would read, but S0
  gates nothing functional — a free tenant keeps every capability they have today.

### 4.1 S1 — Client surfaces (no DB change, no EF change)

**Files:** `app.js`, `catalog.html`, `mylist.html`, `arrivals.html`, `subscriptions.html`,
`admin.html`, `analytics.html`, `index.html`.

1. **Widen the authenticated tenant read.** `app.js:82-86` —
   `.select('id, slug, display_name, branding')` → add `contact_phone, location`.
   RLS already permits it (§ 1.2). Leave `settings` unselected (§ 6).
   **Do not touch `lookupTenantBySlug()` or the RPC** (§ 1.2 trap).
2. **Extend `Branding.apply()`** (`app.js:172-201`) with two hooks, each following the
   existing absent-key-is-a-no-op contract exactly:
   - `[data-tenant-phone]` → `textContent = tenant.contact_phone` when present
   - `[data-tenant-location]` → `textContent = tenant.location` when present
   - Also set `href = 'tel:' + digitsOnly(contact_phone)` on `a[data-tenant-phone]`,
     for `mylist.html:562`.
3. **Add hooks at the 18 Tier-A client sites and 6 Tier-B footers** in § 2, with the
   founding literal left in place as the inline fallback — the 5.3 pattern, so an
   unresolved tenant renders exactly as today.
4. **The three pending-approval strings and the welcome modal are JS-built, not markup**
   (`catalog.html:331`, `mylist.html:801`, `subscriptions.html:432`, `app.js:1635`).
   They cannot take a `data-` hook. Interpolate
   `TenantContext.current().display_name` directly at build time, with the founding
   literal as the `||` fallback.
5. **`index.html:313`'s `alt` is an attribute, not text** — `Branding.apply()`'s
   `logo_url` branch already loops `img[data-tenant-logo]`; set `alt` there from
   `display_name` in the same loop.

**Not in S1:** `admin.html`'s print outputs (S3), anything anon-reachable (§ 6).

### 4.2 S2 — Email templates (6 Edge Functions)

**Deployment is NOT the Cloudflare Pages flow** — deploy one function at a time,
**explicitly preserving each function's live `verify_jwt` setting**, per F93 discipline
and F99 S1's own record (`approve-customer` and `send-my-list` run JWT **ON**; the other
four OFF — CLAUDE.md's § Supabase platform facts was wrong about this once already).

#### 4.2.1 The shared shape

Each function gains one service-role fetch of its own tenant row:

```
GET {SUPABASE_URL}/rest/v1/tenants?id=eq.{tenantId}&select=display_name,contact_phone,location
```

and threads `{ storeName, storePhone, storeLocation }` into its subject, body and footer,
each with a `??` fallback to today's literal — same reversibility posture as F99 S1.

`from.name` becomes `storeName ?? MAIL_FROM_NAME`. **`from.email` is NOT touched** (§ 3).

`register-customer` is the cheapest: widen the `select` it **already issues** at
`index.ts:243` and use the `display_name` it currently discards.

#### 4.2.2 `reset-password` is the one real design item

It holds no tenant reference at all (§ 1.5) and is deliberately enumeration-safe —
`index.ts:47` *"Always return success — never leak whether an email address exists."*

**Resolve the tenant from `generateData.user.id` → `user_profiles.tenant_id`**, not from
the posted email. It is the same identity the function has already established, and it
avoids adding a second email-keyed lookup.

**This introduces no new enumeration signal:** `generateRes.ok` already tells the
function internally whether the account exists, and the early-return at `:48-51` fires
**before** any new lookup would run. **Constraint for the executor: the unconditional
`{ success: true }` response shape must be byte-identical on both paths after the
change.** Verified by V5.

#### 4.2.3 A legal constraint worth surfacing

`notify-customers` is the monthly promotional blast — the one function of the six whose
mail is plausibly *commercial* rather than transactional, and therefore the one that
actually needs a real physical postal address in its footer. **`tenants.location` must
hold a full mailing address, not a "City, ST" string**, or that footer degrades from
compliant to non-compliant for every new tenant. See § 8 Q1.

### 4.3 S3 — Paper: the half that does not need Phase 6

`admin.html` only. Split the print leaks by what they depend on:

| Leak | Depends on | S3? |
|---|---|---|
| Store name, `admin.html:3825` | `display_name` | ✅ yes |
| Phone, `admin.html:3825` | `contact_phone` | ✅ yes |
| `rjbookstop.com`, `:3825`, `:4966`, `:5354` | a tenant website — **no such field exists** | ⛔ needs `branding.website` (§ 8 Q2) |
| `rjbookstop.pulllist.app`, `:3826`, `:4966`, `:5134` | a per-tenant hostname | ✅ **RESOLVED for `plan = 'pro'` tenants only — § 0.1 Q9, 2026-09-02.** Unconditional derivation is still ⛔ blocked (below); tier-gating it is what unblocks it |

> **⚠️ 2026-09-02 update — narrower than a full unblock.** § 0.1 Q9 resolves this for *paid*
> tenants specifically: `<slug>.pulllist.app` prints/emails only when `plan = 'pro'`, and only once
> that hostname has been manually provisioned as a required step of paid onboarding (same 5.5
> mechanism as `comicstore`) — never derived and assumed. **Free tenants still get the safe,
> always-resolving `pulllist.app` apex link, per Q9** — the reasoning below (why an unconditional
> derivation is dangerous) is exactly why the free-tier branch stays on the apex rather than
> guessing at a subdomain. Phase 6 S0 (the wildcard spike) remains untouched and unneeded by this —
> paid-tier provisioning stays manual, low-volume, per F145's own recorded pattern.

**Why deriving the hostname unconditionally is genuinely dangerous, not deferred by preference:**
F145 measured that **there is no wildcard DNS on `pulllist.app`**; `rjbookstop` and
`comicstore` resolve only because each is an individually provisioned Cloudflare Pages
custom hostname. Deriving `<slug>.pulllist.app` in print output would put a
**non-resolving URL on customer paper** for any tenant not manually provisioned. That
gate is Phase 6 S0 — **for a wildcard/self-serve mechanism.** It is not a gate on a manually-provisioned,
paid-tenant-only link, which is what § 0.1 Q9 actually ships.

`:4966` and `:5354` are CSS `@page` `content:` strings — they are built inside a JS
template literal and can be interpolated the same way, but **note the escape trap** the
2026-08-27 print-CTA session hit: a `\00b7` CSS escape inside a JS template literal is an
illegal legacy-octal escape and a hard `SyntaxError` for the whole inline script. Use
literal characters.

### 4.4 S4 — Docs

- `docs/technical-reference.md` § 13 **F72**: correct the recorded scope (it reads as one
  template in one function) and set status.
- `docs/technical-reference.md` § 4.1: note `contact_phone` / `location` are now read by
  `Branding.apply()`, matching the existing `branding` note.
- `docs/tenant-onboarding-runbook.md` — **four fixes, three of them found by § 1.7's live read:**
  1. `contact_phone` / `location` move from *optional metadata* to **required at create** — they
     are now rendered. `location` must be a **full postal address** (Q1 / § 4.2.3).
  2. Update the go-live checklist F72 item.
  3. **Step 2's SQL is wrong.** It instructs operators to write `display_name` into the `branding`
     jsonb; `Branding.apply()` reads the `tenant.display_name` **column** (`app.js:186`) and ignores
     the jsonb key entirely. Production's `comicstore` has the ignored key set today. Correct the
     example to `UPDATE ... SET display_name = ...` for the name, `branding` for colour/logo only.
  4. The branding key table lists `primary_color` / `display_name` / `logo_url`. Real keys in use
     are `primary_color`, `logo_url`, **`promo_banner`** (`catalog.html:508`, documented in
     `docs/subscription-promotion.md`), and — added by this plan — **`location_short`** (Q1) and
     **`website`** (Q2). `display_name` should be **removed** from the list per fix 3.
- `docs/phase-5.3-per-tenant-branding.md`: append a note that the `Branding.apply()`
  contract was extended, and that § 1.5's anon projection boundary was **preserved**.
- **`index.html:247-262` — the live pricing page (new, Q10).** The "Branded" tier currently claims
  *"customer emails from your shop"*; what ships is the shop's **name** as the From display-name
  plus full identity in the footer and a branded "View Online" link, over a **flat**
  `noreply@pulllist.app` sender for both tiers. Edit the copy to describe that. The "Free" tier's
  *"shared pulllist.app front door"* line is already accurate and needs no change.
- `CLAUDE.md`: § Current Migration Phase entry; § Key Business Logic branding line.

---

## 5. Verification gates

| Gate | What | How it fails |
|---|---|---|
| **V1** | Grep for `Ray & Judy` / `973-586-9182` / `9735869182` / `Rockaway` / `40 W Main` over `*.html` and `app.js` returns **only** inline fallbacks inside a `data-tenant-*` element or a `??` / `\|\|` fallback expression | any bare literal remains |
| **V2** | Same grep over `supabase/functions/*/index.ts` returns only `??` fallbacks | a hardcoded literal survives in a template |
| **V3** | **Second-tenant render proof.** ⚠️ **`comicstore` does not exist on staging** (§ 1.7) — the second tenant is production-only. Use a **`pw-*` Playwright fixture tenant** (or create a purpose-made staging tenant via `register-tenant`), give it a distinct `display_name` / `contact_phone` / `location`, sign in as one of its users, and load all six nav pages + the My List print header + an arrivals pickup slip. **Zero** occurrences of the founding name, phone or city | the leak is not actually closed |
| **V4** | **Real delivered email, per function.** Trigger each of the six against a `comicstore` recipient; read the **delivered** message (not the API's unconditional `{"success":true}` — F99 § 2's own warning) and confirm From-name, subject and footer all carry `comicstore`'s identity | a template was missed |
| **V5** | `reset-password` returns a **byte-identical** `{success:true}` body for a known-good address and a nonexistent one (§ 4.2.2) | enumeration signal introduced |
| **V6** | Founding tenant renders **byte-identically** to pre-change on all six pages and all six emails | the fallback contract broke |
| **V7** | Unresolved-tenant path: force `TenantContext` to fail and confirm every surface still renders the founding literal — no `undefined`, no empty node | absent-key no-op contract broke |
| **V8** | `node --check` on `app.js` and every extracted inline `<script>` block (the S3 escape trap); full `run-smoke.ps1` — unit + Playwright, **0 failures**, run **after** push against deployed staging bytes | — |

**S0's own gates — added 2026-09-02. S0 ships before S1/S2/S3, so it needs gates that do not
depend on any render change existing yet:**

| Gate | What | How it fails |
|---|---|---|
| **V9** | **S0 changes no rendered byte.** Load all six nav pages as the founding tenant before and after S0 and diff the rendered output; separately confirm `document.querySelectorAll('[data-tenant-name]')` text is unchanged. **This is S0's headline property** (§ 4.0) | a render moved — something in the diff belongs in S1/S2/S3, not S0 |
| **V10** | **Tier-block byte-identity across the six mail functions.** `grep -c 'const isPaidTenant'` returns 1 in each of the six; the extracted blocks hash identically across all six. *(Applies from S2 — in S0 the block exists only in this doc.)* | the six copies diverged — the failure mode Q11's convention accepts and this gate exists to catch |
| **V11** | **`Tier` fails closed, proven by test not by reading.** In a live console: `Tier.isPaid(null)`, `Tier.isPaid({})`, `Tier.isPaid({plan:'Pro'})`, `Tier.isPaid({plan:'FREE'})` all return `false`; `Tier.publicUrl({plan:'pro'})` (no slug) returns `pulllist.app`, **not** `undefined.pulllist.app`. Confirm the same for `register-tenant` by creating a throwaway tenant with `plan: 'Pro'` and reading back `free` | a mis-cased or absent plan reads as paid — the state that puts a non-resolving hostname on customer paper (F145) |
| **V12** | **Anon path carries no tier.** Sign out, load `index.html` on a tenant subdomain, confirm `TenantContext.current()` has **no `plan` key** — the § 1.2 boundary held and no anon surface can branch on tier (§ 4.0.4) | `plan` leaked onto the anon RPC projection, breaking 5.3 § 1.5 |
| **V13** | **The data fix landed.** `SELECT slug, plan FROM tenants` on production returns `rjbookstop = pro`, `comicstore = free`; staging holds a durable `free`/`pro` pair (§ 4.0.2) | the paying tenant is still marked free — shipping S1 would flip Ray & Judy's to generic branding |


**Negative-control every new assertion** by temporarily inverting it and confirming it
goes red — the discipline the F142 / single-catalog-print / F149 sessions all record.

**V3 and V4 are the gates that matter.** V1/V2 are greps and can pass while a surface is
still wrong; V8 is a regression gate and **has no existing coverage of email templates,
print headers or pickup slips at all** — a green suite says nothing about this work
(CLAUDE.md § "Green is not the same as verified").

---

## 6. Out of scope — stop and ask

> ⚠️ **The sending-domain line below is stale — corrected 2026-09-02, kept for the record.** It
> read "F99 S3, blocked" when F99 was written 2026-09-01; **F99 has since shipped in full, both
> environments** (M1–M7, same day as this revision, via Resend rather than the blocked MailerSend
> S3 path). `MAIL_FROM_EMAIL` is now `noreply@pulllist.app` — flat, for every tenant, any plan —
> **not** `noreply@mrcyberrick.us`. This does not change § 0.1's design: the flat address stays flat
> for both tiers (§ 0.1 Q8 — sender address is not a branding lever this plan uses), it's just no
> longer the *founding tenant's* address either.

- ~~**The sending domain.** `MAIL_FROM_EMAIL` stays `noreply@mrcyberrick.us`. That is F99
  S3, blocked (§ 3).~~ **Superseded — see callout above.** F99 is done; the address is flat
  `noreply@pulllist.app` for every tenant regardless of plan, by this plan's own § 0.1 design, not
  because of a blocker.
- **Widening `resolve_tenant_by_slug`.** Preserves 5.3 § 1.5. Needed only if a
  `[data-tenant-phone]` / `[data-tenant-location]` hook is ever wanted on an
  anon-reachable page (§ 1.2 trap).
- ~~**The per-tenant print hostname.** F145 / Phase 6 S0 (§ 4.3).~~ **Resolved for paid tenants —
  see § 4.3's 2026-09-02 update and § 0.1 Q9.** Still out of scope: deriving it for a tenant with no
  manually-provisioned subdomain, and anything wildcard/self-serve (that part is still Phase 6 S0).
- **Per-tenant MailerSend sender identities**, `reply_to` (F99 § 8 Q6, declined),
  bulk-send (F148). *(MailerSend itself is now dormant, not live — F99 — but the same "no
  per-tenant sending identity" decision holds under Resend too, per § 0.1 Q8.)*
- **Phase 6 self-service signup** and the wildcard spike.
- **`tenants.settings` exposure.** Noted below as a discovery, deliberately not acted on.
- **Billing / plan enforcement / an upgrade flow.** `tenants.plan` is set manually by Rick (same
  operator-driven pattern as tenant onboarding itself, § 0.1 Q7) — this plan reads that column, it
  does not build a way for a tenant to change it themselves.

### Discovered while measuring — both now dispositioned (§ 8 Q4, Q5)

1. ✅ **RESOLVED 2026-09-01 — doc fix, no finding.** CLAUDE.md said "all 8 Edge Functions"
   in two places (§ Repository Structure, § Edge Functions). There are **9** —
   `register-tenant`, added at Phase 5.4 S3, whose own commit `0bdc55c` reads
   *"EF inventory -> 9"*. It was also **missing from the § Edge Functions list itself**,
   not merely miscounted. Both sites corrected and the function added to the list.
2. ✅ **FILED AS F151, 2026-09-01 — not fixed here.** `tenants` RLS is row-level, so any
   authenticated user can `SELECT` every column of their own tenant row — including
   `settings`. `app.js:82-86` deliberately never selects it and `resolve_tenant_by_slug`
   deliberately never returns it (5.3 § 1.5), **but neither is an enforcement boundary**
   against a client that asks directly. **Verified live before filing, as Q5 required:**
   `mailerlite_webhook_secret` is still stored on all three real tenant rows — the hoped-for
   `{}` was wrong. Inert (dead config since 2026-08-30) and tenant-scoped, hence Low.
   Full entry and fix direction: § 13 F151.

---

## 7. Rollback

Each step is a separate commit with the finding ID in the message, and each is a clean
revert:

- **S0** — `git revert` for the two `app.js` edits; redeploy `register-tenant` from its pre-change
  source, **preserving `verify_jwt`**. Reverting leaves `plan` unread by anything, which is exactly
  today's state. **The `rjbookstop` data fix (§ 4.0.2) is deliberately NOT reverted** — it corrects a
  wrong value, is inert while no code reads the column, and would have to be re-applied on the next
  attempt anyway.
- **S1** — `git revert`; the founding literals are still present as inline fallbacks
  throughout, so a revert restores today's behaviour exactly.
- **S2** — redeploy each function from its pre-change source, **preserving `verify_jwt`**.
  The `??` fallbacks mean even a partial rollback renders the founding identity rather
  than an empty string.
- **S3** — `git revert`; `admin.html` only.

No DDL and no migration in any step. **One data write exists — S0's `rjbookstop` plan correction
(§ 4.0.2)** — and it is intentionally not part of any rollback, per the S0 bullet above. *(This line
read "no data write" before S0 was written up; corrected 2026-09-02.)*

---

## 8. Decisions — all ANSWERED 2026-09-01 (Rick)

**Every question below is settled. Do not re-litigate; execute against these.** *(Q7–Q9 — the tier
gate, the generic-content definition, the link-by-tier rule — were answered 2026-09-02 and live in
§ 0.1, not here. This section's numbering intentionally stops at Q6; it predates the tier revision.)*

| # | Question | ✅ DECISION |
|---|---|---|
| **Q1** | `tenants.location` has to serve both a compact page footer (*"Rockaway, NJ"*) and a full postal footer in email (*"40 W Main St. Rockaway, NJ 07866"*). One column, two granularities. | **Full postal address in `location`**; add **`branding.location_short`** for the six page footers, falling back to `location` when absent. ⚠️ Staging's founding tenant currently holds `Rockaway, NJ` in `location` — that value **moves to `location_short`** and `location` is **rewritten** as the full address (§ 1.7). |
| **Q2** | `rjbookstop.com` is a tenant's own website. No field exists for it. | Add **`branding.website`** — jsonb key, no DDL, consistent with `logo_url`. **Omit the line entirely when absent**; never print a placeholder. |
| **Q3** | Both existing tenants need `contact_phone` / `location` populated before S1 renders anything. | **Populate the founding tenant with real values; give the test tenant obviously-synthetic ones.** ⚠️ Reality per § 1.7: prod `rjbookstop` has **both NULL** (needs full population); prod `comicstore` **already** carries synthetic values (`555-555-5555` / `New Jersey`) — Q3 is already satisfied there; staging's `pw-*` fixtures are all NULL and are the V3 vehicle. |
| **Q4** | The 8-vs-9 Edge Function count (§ 6 discovery 1). | **Doc fix, no finding.** ✅ **Applied 2026-09-01, ahead of S4** — both CLAUDE.md sites corrected and `register-tenant` added to the § Edge Functions list (it was missing from the list too, not just the count). Done early because a stale claim in CLAUDE.md misleads the *next* session, and this is exactly the F132/F138/F145 pattern. |
| **Q5** | `tenants.settings` readable by any authenticated user (§ 6 discovery 2). | **File it, don't fix it here.** ✅ **Filed as F151, 2026-09-01** (§ 13). Live verification ran first, as this question required: `mailerlite_webhook_secret` is present on **all three real tenant rows**, not `{}` as hoped — so it is a real stored value, though inert and tenant-scoped. Fix direction recorded in F151; **out of scope for this plan.** |
| **Q6** | Step order. | **S1 → S2 → S3.** |

---

## 9. Completion criteria

**§ 0.1 items — new 2026-09-02, block execution start, not just close-out:**

- [x] ~~Q7–Q9 answered~~ — settled 2026-09-02 (§ 0.1): `tenants.plan` is the gate, generic-tier
      content defined per surface, hostname link resolved for paid tenants only
- [x] ~~Q10–Q11 answered~~ — settled 2026-09-02 (§ 0.1): paid-tier email promise is footer identity
      + branded link with a **flat sender for both tiers**; the tier check ships as six byte-identical
      EF copies gated by V10
- [x] ~~**S0 written up as byte-exact steps**~~ — done 2026-09-02, § 4.0, re-read from disk against
      the post-Resend tree
- [ ] **S0 complete** — V9, V11, V12, V13 green. `plan` in the authenticated select; `Tier` helper
      in `app.js`; `register-tenant` accepting an allowlisted `plan`; runbook's three edits
      (§ 4.0.3). **No rendered byte changes** (V9 is the gate that says so)
- [ ] **`rjbookstop`'s `plan` corrected from `free` to `pro` on production** — real data bug found
      2026-09-02, folded into S0 as § 4.0.2. **Safe to run before any code ships and it should be**
      — inert until S1 lands
- [ ] **A durable staging `free`/`pro` tenant pair** — the `pw-*` fixtures are ephemeral (§ 4.0.2),
      so V3/V4 have no vehicle without this
- [ ] § 4.1–§ 4.3 rewritten with explicit free/paid content per site — **still owed.** S0 is now
      byte-exact; S1/S2/S3 remain design-level and must not be executed from their current text
- [ ] mylist.html and arrivals.html print outputs gain the tier-gated "View Online" link — new
      scope, these had none before (§ 0.1)
- [ ] admin.html's existing `rjbookstop.pulllist.app` literals (§ 4.3) made tier-conditional,
      falling back to `pulllist.app` for any non-`pro` tenant
- [ ] **`index.html:247-262` pricing copy edited to match what Q10 actually ships** — the "Branded"
      tier's *"customer emails from your shop"* claim is knowingly stale as of 2026-09-02

**§ 8 items — 2026-09-01, still valid for what data exists (not gated on tier):**

- [x] ~~Q1–Q6 answered~~ — **all six settled 2026-09-01 (§ 8); Q4 applied, Q5 filed as F151**
- [ ] Tenant data prepared (Q3 / § 1.7): prod `rjbookstop` `contact_phone` + `location`
      populated from NULL; staging `raysandjudys` `location` rewritten to a full postal
      address with `Rockaway, NJ` moved to `branding.location_short`; a staging second
      tenant given distinct values for V3 — **and now also a distinct-`plan` tenant pair**,
      one `free` and one `pro`, since V3/V4 need to prove both branches, not just "a second tenant"
- [ ] S1 complete — V1, V3, V6, V7 green, **re-run against both a `free` and a `pro` tenant**
- [ ] S2 complete — V2, V4, V5, V6 green, **both plans**; all six deployed with `verify_jwt` preserved and each setting **read from the live dashboard, not from a doc**
- [ ] S3 complete — name + phone parameterized **per plan**; hostname link tier-gated (no longer
      deferred, § 0.1 Q9); website half still explicitly deferred and recorded
- [ ] V8 green — `node --check` clean, full suite 0 failures, run post-push against deployed staging bytes
- [ ] S4 doc updates landed
- [ ] § 13 F72 status updated with its corrected scope
- [ ] CLAUDE.md § Current Migration Phase advanced
- [ ] **Staging only.** Production promotion is a separate explicit request.

---

## 10. Reference

| Thing | Where |
|---|---|
| F72 (owner finding) | `docs/technical-reference.md` § 13 F72 |
| **§ 0.1's tier design (2026-09-02)** | this doc, § 0.1 — the live record; nowhere else |
| **S0 — the tier mechanism, byte-exact** | this doc, § 4.0 — the only executable step today |
| `register-tenant`'s hardcoded `plan: 'free'` | `supabase/functions/register-tenant/index.ts:148` — why no paid-tenant create path exists today (§ 4.0.1) |
| `TENANT_APEX` (`'pulllist.app'`) | `app.js:37` — reused by `Tier.publicUrl()`, not restated |
| `tenants.plan` — the gate | `docs/technical-reference.md` § 4.1 (schema); § 0.1 (live values, the `rjbookstop` bug) |
| Live pricing page this design must eventually match | `index.html:247-262` — currently describes the pre-tier-gating "Branded" perks, itself now stale, not yet updated |
| `Branding.apply()` contract | `docs/phase-5.3-per-tenant-branding.md` § 1.1, § 1.5 |
| `resolve_tenant_by_slug` contract | `docs/technical-reference.md` § 6; `docs/phase-5.2-slug-id-routing-rpc.md` |
| `tenants` schema | `docs/technical-reference.md` § 4.1 |
| Sender parameterization (F99 S1, now on Resend) | `docs/f99-resend-migration.md`; `docs/f99-sender-domain-consolidation.md` § 4 S1 |
| F99's own completion, both environments | `docs/f99-resend-migration.md` STATUS token |
| No wildcard DNS (F145) | `docs/technical-reference.md` § 13 F145 |
| Existing "View Online" pattern to extend | `admin.html:3826`, `:4966`, `:5134` (PR #140) |
| Phase 6 S0 wildcard gate | `docs/phase-6-self-service-signup.md` |
| Tenant onboarding metadata | `docs/tenant-onboarding-runbook.md` Step 1, Step 2 |
| EF deploy discipline (`verify_jwt`) | CLAUDE.md § Supabase platform facts |
| Founding Partner pricing this design should reconcile with | `hybrid_frontdoor_premium_tiering` memory; `docs/pre-phase-6-consolidation-wave-2.md` § 2.5 |
