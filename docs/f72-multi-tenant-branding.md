# F72 — multi-tenant branding: remove the founding tenant's identity from every tenant-facing surface

**STATUS:** PLANNED — **§ 8 Q1–Q6 all ANSWERED 2026-09-01 (Rick); ready to execute** | staging=— | prod=— | findings=F72,F99,F145,F151

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

## 0. Why this is worth doing now

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

F99's § 13 entry says F99 *"must be designed together with F72, not sequenced ahead of
it."* That constrains **F99**. It does not make F72 wait on F99, and it must not, because:

- **F99 S3 is stuck.** Attempted and rolled back 2026-09-01 at the cost of a ~50-minute
  production outage, `#MS42207` **cause unresolved**, next attempt gated on buying a
  month of MailerSend paid tier (§ 8 Q7 there).
- **The From *name* is free text.** MailerSend takes a display name alongside a verified
  From address, so `"Comic Shop X" <noreply@mrcyberrick.us>` needs **zero** DNS work.
  F99 S1 already made that name a variable.
- **Body, subject and footer are pure template code.** No vendor involvement at all.

**What still leaks after this plan, and why it is acceptable:** mail arrives from
`noreply@mrcyberrick.us`. That reads as an unbranded relay — odd, and worth fixing — not
as a competitor's shop. **That is the whole difference between "odd" and "unsellable",
and it is why F72 goes first.**

The one hard F99/F145 dependency is § 4.3's hostname half, which is scoped out.

---

## 4. Work breakdown

Three steps, each independently shippable and independently revertible. **S1 and S2 do
not depend on each other** and may be done in either order or in one branch; S3 depends
on S1's helper existing.

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
| `rjbookstop.pulllist.app`, `:3826`, `:4966`, `:5134` | a per-tenant hostname | ⛔ **F145 / Phase 6 S0** — see below |

**Why the hostname half is genuinely blocked, not deferred by preference:** F145
measured that **there is no wildcard DNS on `pulllist.app`**; `rjbookstop` and
`comicstore` resolve only because each is an individually provisioned Cloudflare Pages
custom hostname. Deriving `<slug>.pulllist.app` in print output would put a
**non-resolving URL on customer paper** for any tenant not manually provisioned. That
gate is Phase 6 S0.

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

**Negative-control every new assertion** by temporarily inverting it and confirming it
goes red — the discipline the F142 / single-catalog-print / F149 sessions all record.

**V3 and V4 are the gates that matter.** V1/V2 are greps and can pass while a surface is
still wrong; V8 is a regression gate and **has no existing coverage of email templates,
print headers or pickup slips at all** — a green suite says nothing about this work
(CLAUDE.md § "Green is not the same as verified").

---

## 6. Out of scope — stop and ask

- **The sending domain.** `MAIL_FROM_EMAIL` stays `noreply@mrcyberrick.us`. That is F99
  S3, blocked (§ 3).
- **Widening `resolve_tenant_by_slug`.** Preserves 5.3 § 1.5. Needed only if a
  `[data-tenant-phone]` / `[data-tenant-location]` hook is ever wanted on an
  anon-reachable page (§ 1.2 trap).
- **The per-tenant print hostname.** F145 / Phase 6 S0 (§ 4.3).
- **Per-tenant MailerSend sender identities**, `reply_to` (F99 § 8 Q6, declined),
  bulk-send (F148).
- **Phase 6 self-service signup** and the wildcard spike.
- **`tenants.settings` exposure.** Noted below as a discovery, deliberately not acted on.

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

- **S1** — `git revert`; the founding literals are still present as inline fallbacks
  throughout, so a revert restores today's behaviour exactly.
- **S2** — redeploy each function from its pre-change source, **preserving `verify_jwt`**.
  The `??` fallbacks mean even a partial rollback renders the founding identity rather
  than an empty string.
- **S3** — `git revert`; `admin.html` only.

No DDL, no migration, no data write ⇒ **there is no database state to roll back.**

---

## 8. Decisions — all ANSWERED 2026-09-01 (Rick)

**Every question below is settled. Do not re-litigate; execute against these.**

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

- [x] ~~Q1–Q6 answered~~ — **all six settled 2026-09-01 (§ 8); Q4 applied, Q5 filed as F151**
- [ ] Tenant data prepared (Q3 / § 1.7): prod `rjbookstop` `contact_phone` + `location`
      populated from NULL; staging `raysandjudys` `location` rewritten to a full postal
      address with `Rockaway, NJ` moved to `branding.location_short`; a staging second
      tenant given distinct values for V3
- [ ] S1 complete — V1, V3, V6, V7 green
- [ ] S2 complete — V2, V4, V5, V6 green; all six deployed with `verify_jwt` preserved and each setting **read from the live dashboard, not from a doc**
- [ ] S3 complete — name + phone parameterized; hostname/website halves explicitly deferred and recorded
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
| `Branding.apply()` contract | `docs/phase-5.3-per-tenant-branding.md` § 1.1, § 1.5 |
| `resolve_tenant_by_slug` contract | `docs/technical-reference.md` § 6; `docs/phase-5.2-slug-id-routing-rpc.md` |
| `tenants` schema | `docs/technical-reference.md` § 4.1 |
| Sender parameterization (F99 S1) | `docs/f99-sender-domain-consolidation.md` § 4 S1 |
| Why the sending domain is blocked | `docs/f99-sender-domain-consolidation.md` § 4 S3 |
| No wildcard DNS (F145) | `docs/technical-reference.md` § 13 F145 |
| Phase 6 S0 wildcard gate | `docs/phase-6-self-service-signup.md` |
| Tenant onboarding metadata | `docs/tenant-onboarding-runbook.md` Step 1, Step 2 |
| EF deploy discipline (`verify_jwt`) | CLAUDE.md § Supabase platform facts |
