# Tenant Onboarding Runbook (tenant N+1)

**Purpose:** Repeatable operational steps for onboarding any new tenant after Phase 5 closes. After 5.5, onboarding is an operational task, not an engineering phase.

**Who runs this:** The operator (Rick), with Claude Code as an assist for curl prep and doc recording. All database + GoTrue writes are Rick's — Claude never touches prod credentials.

**When to use:** When a new bookshop is ready to join PULLLIST and has a real admin email address and a chosen subdomain slug.

**Prerequisite reading:** `docs/phase-5.5-second-tenant-onboarding.md` § 1 (decisions), § 3 (out of scope), § 6 (rollback tiers). This runbook distills the S0–S3 pattern from 5.5 into operational steps.

**Credential rule (F73/F74 lesson): Never paste the `webhook_secret` from `register-tenant` into any chat, transcript, or committed file.** Save it to a local scratch file only.

---

## Step 0 — Gather and validate inputs

Collect from the operator before writing any SQL or running any curl:

| Input | Constraint |
|---|---|
| `slug` | lowercase DNS-safe: `^[a-z0-9][a-z0-9-]*[a-z0-9]$` (or single char); **not** on the reserved denylist (below) |
| `display_name` | customer-facing name for the tenant |
| `admin_email` | a real, reachable mailbox the tenant admin controls |
| `branding` (optional) | jsonb: `{ "primary_color": "#xxxxxx", "display_name": "...", "logo_url": "..." }` — may be set at create or updated after |
| `contact_email`, `contact_phone`, `location` (optional) | tenant metadata; passed in the `register-tenant` body |
| `plan` | **`free` (default) or `pro`.** Set `pro` only for a tenant who is actually paying. Gates how much of the tenant's identity appears on customer-facing web, email and print surfaces (F72). Allowlisted in `register-tenant` — any other value silently becomes `free`, so check the read-back in Step 1 |

**Reserved slug denylist** (hard-coded in `register-tenant`): `www`, `app`, `api`, `admin`, `staging`, `prod`, `mail`, `ftp`, `blog`, `dev`, `test`, `canary`, `pulllist`, `raysandjudys`, `rjbookstop`.

If the desired slug is on the denylist or fails the format check, ask the operator for an alternative before proceeding.

**Confirm:** Cloudflare dashboard access to the Pages project serving `pulllist.app` (needed for Step 3).

---

## Step 1 — Create the tenant via `register-tenant`

Claude prepares the curl; Rick substitutes the operator secret and runs it. Save the response to a local scratch file — **do not paste `webhook_secret` into chat**.

**Prepare a JSON body file** (PowerShell, local shell):

```powershell
$tmpBody = "$env:TEMP\new-tenant.json"
# Fill in the actual values before running:
[System.IO.File]::WriteAllText($tmpBody, @'
{
  "slug": "<slug>",
  "display_name": "<display_name>",
  "admin_email": "<admin_email>",
  "location": "<optional>",
  "plan": "free",
  "branding": { "primary_color": "#xxxxxx" }
}
'@)
```

**Run `register-tenant` (Rick — substitutes `<TENANT_PROVISION_SECRET_PROD>` from `.env`):**

```powershell
$secret = $env:TENANT_PROVISION_SECRET_PROD   # loaded from .env before this block
curl.exe -s -X POST "https://plgegklqtdjxeglvyjte.supabase.co/functions/v1/register-tenant" `
  -H "Content-Type: application/json" `
  -H "x-operator-secret: $secret" `
  --data-binary "@$env:TEMP\new-tenant.json"
```

**Expected response (`200`):**

```json
{ "tenant_id": "...", "admin_user_id": "...", "slug": "...", "webhook_secret": "...", "invite_sent": true }
```

**Save the first four values to a local scratch file. Do not paste `webhook_secret` into chat.**
**Check `invite_sent`** — `false` means the tenant and admin were created correctly but the
invite email failed to send; see Step 5 for the fallback.

Error responses:
- `401` — operator secret wrong or not loaded; re-check `.env`
- `409 slug_taken` — slug already exists; choose another
- `400` — required fields missing; check the request body
- Non-200 — run the §4.1 FK-ordered teardown (Step rollback below) before retrying

---

## Step 2 — Set / refine branding

If branding was included in the `register-tenant` body it is already seeded. If not, or if you want to update it after creation:

> ⚠️ **`display_name` is a COLUMN, not a `branding` key.** `Branding.apply()` reads
> `tenant.display_name` (`app.js:186`) and **ignores** `branding.display_name` entirely.
> This step's SQL used to write the name into the jsonb, which does nothing — production's
> `comicstore` still carries that ignored key today. Corrected 2026-09-02 (F72 S0).

```sql
-- Prod SQL Editor
-- Name: the COLUMN. Colour/logo/banner: the jsonb.
UPDATE public.tenants
  SET display_name = '<display_name>',
      branding     = '{"primary_color":"#xxxxxx","logo_url":"<optional>"}'::jsonb
  WHERE slug = '<slug>';
SELECT id, slug, display_name, plan, branding FROM public.tenants WHERE slug = '<slug>';
```

Expected: one row with the correct name, plan and branding.

**Recognised `branding` keys** (anything else is inert): `primary_color`, `logo_url`,
`promo_banner` (`catalog.html:508`). **`display_name` is NOT one of them** — see the warning
above.

---

## Step 3 — Add the Cloudflare custom domain

> ⚠️ **REQUIRED, not optional, for any `plan = 'pro'` tenant** (F72 S0, 2026-09-02).
> A paid tenant's own `<slug>.pulllist.app` is printed on their customers' pickup slips and
> bagging lists and is emailed as the "View Online" link. **There is no wildcard DNS on
> `pulllist.app`** — every hostname is individually provisioned here (F145, measured). So a
> paid tenant whose hostname is not provisioned ships a **non-resolving URL to real
> customers, on paper**. Free tenants are unaffected: they always link to the `pulllist.app`
> apex, which needs no provisioning.

> **Order matters:** provision the hostname *before* setting `plan = 'pro'`, or before the
> tenant's first print/email run if the plan was set at create.

**Rick — Cloudflare dashboard (Pages project for `pulllist.app`):**

1. Go to the Pages project → **Custom domains** → **Set up a custom domain**
2. Enter `<slug>.pulllist.app`
3. Add the DNS record Cloudflare requests (CNAME or A record on the `pulllist.app` zone)
4. Wait for status → **Active** and TLS certificate → **Issued**

**Verify (curl — Claude or Rick):**

```powershell
curl.exe -s -o /dev/null -w "%{http_code}" https://<slug>.pulllist.app/
# Expected: 200
curl.exe -s -o /dev/null -w "%{http_code}" https://pulllist.app/
# Expected: 200 (founding unaffected)
```

**Do not route traffic to the new subdomain until TLS is issued.** If the cert does not issue within ~15 minutes, check the DNS record and Cloudflare zone settings before announcing.

### Step 3a — Live hostname inventory (F145 item 3)

**Read this before touching anything in the `pulllist.app` zone.** These hostnames are durable
infrastructure with dependencies outside this repo. **There is no wildcard DNS on `pulllist.app`** —
every tenant subdomain is an individually provisioned Cloudflare Pages custom domain, which is why
onboarding tenant N+1 requires Step 3 at all and why Phase 6's S0 gate is still closed.

**Cloudflare account:** `Pulllist@mrcyberrick.us's Account` (`f7fec5a26d14edbb47009a0d7d78002a`).
**Pages project:** `pulllist` (`pulllist.pages.dev`). **Zone DNS:** Cloudflare
(`morgan`/`tia.ns.cloudflare.com`). **Registrar:** Namecheap (the apex MX records point at
`eforward*.registrar-servers.com`).

Verified against the Pages project's Custom domains tab **and** a full zone export, 2026-08-30:

| Hostname | Record | Proxied | Serves | Retire freely? |
|---|---|---|---|---|
| `pulllist.app` (apex) | CNAME → `pulllist.pages.dev` | yes | apex marketing + universal login; **the landing page for all tenants** (Rick, 2026-08-29) | **No** — platform front door |
| `rjbookstop.pulllist.app` | CNAME → `pulllist.pages.dev` | yes | founding tenant front door | **No — see the two dependencies below** |
| `comicstore.pulllist.app` | CNAME → `pulllist.pages.dev` | yes | pilot/seeded second tenant | Only with the pilot |

**Exactly three custom domains exist. There is no `*` wildcard record** — confirmed two independent
ways: an NXDOMAIN probe of an unprovisioned name (F145, 2026-08-27) and the zone export above
(2026-08-30). All three CNAME to the *same* Pages project.

**⚠️ `rjbookstop.pulllist.app` carries two dependencies that a hostname change would break, and
neither is recoverable by redeploying:**

1. **It is printed on customer paper.** The "View Online" CTA (PR #140, 2026-08-27) puts it on the
   Print Catalog page-1 header, that report's `@page` footer margin box on **every** page, and the
   Print Bagging List per-customer header. **Paper cannot be redeployed.** Do not retire or rename
   this hostname without reprinting.
2. **It is a mail-authentication domain, not just a web host.** The zone carries, on this subdomain
   specifically: `brevo1._domainkey` and `brevo2._domainkey` CNAMEs (Brevo DKIM), an SPF record
   (`v=spf1 include:spf.brevo.com ~all`), and a `brevo-code:` verification TXT. **The weekly
   newsletter authenticates as this hostname.** Removing it breaks DKIM/SPF for customer marketing
   mail — a failure that shows up as deliverability decay, not as an error anyone sees.

**Provisioning date: unrecovered.** The 2026-06-11 audit-log entry found while looking is
`Create Subdomain` on `/accounts/…/workers/subdomain` (`{"subdomain": "pulllist"}`) — that is the
account's **workers.dev** subdomain, *not* this Pages custom domain. To try again, filter the audit
log for `product: pages` / a URI containing `/pages/projects/pulllist/domains`; Cloudflare's
retention is limited, so if it is not there, leave this as unrecovered rather than estimate.

**Two zone facts worth knowing before any email work** (F72/F99 territory, not actionable here):
`_dmarc.pulllist.app` is `p=none` today — matching F99's "quarantine held" record — and the **apex**
SPF authorizes only Namecheap's forwarder (`include:spf.efwd.registrar-servers.com`), **not**
MailerSend. Any future move to send transactional mail from `@pulllist.app` needs that SPF extended
first.

---

## Step 4 — ~~Configure MailerLite webhook~~ — **REMOVED 2026-08-30. Do not perform this step.**

**There is no MailerLite webhook path any more.** The `?secret=` branch was deleted from
`register-customer` on 2026-08-30 (native-customer-signup § S5; Rick's decision 2026-08-29 to
remove it entirely rather than leave it present-but-dead). The removal is **platform-wide** — the
mechanism was per-tenant, so it is gone for every tenant, existing and future, not just the founding
one. A URL carrying `?secret=` is now inert: the request falls through to the native signup path and
is judged on its JSON body.

**`register-tenant` may still return a `webhook_secret`, and `tenants.settings` may still carry
`mailerlite_webhook_secret`. Both are DEAD CONFIG. Nothing reads either one.** Do not configure a
webhook with it, and do not treat its presence as a step you have missed.

**How a new tenant's customers actually get accounts — the two live paths:**

1. **Admin-initiated** — the tenant's admin uses **Invite Customer** (`invite-customer`) or **Add
   Paper Customer** (`create-paper-customer`) from their own dashboard. Both resolve `tenant_id`
   from the calling admin's profile, so both are safe from any tenant (see the note below).
2. **Customer-initiated** — native self-registration on the tenant's branded login, which posts to
   `register-customer` with the tenant `slug`. Live for the founding tenant since 2026-07-24
   (PR #95). **Before enabling it for a new tenant, read F72:** the confirmation email is still
   founding-branded for every tenant, which is a real customer-visible problem and is why
   `comicstore` has deliberately stayed pilot/seeded. See Step 7's go-live checklist.

*This step is kept as a tombstone rather than deleted, because an operator following an older copy
of this runbook — or a printed one — will look for a Step 4 and needs to be told it is gone rather
than find a gap in the numbering.*

**Note (corrected 2026-07-15, 5.5 S6):** an earlier version of this note warned that `create-paper-customer` and `invite-customer` write to `FOUNDING_TENANT_ID` regardless of the calling admin's tenant. That described pre-2026-05-10 behavior — the F34 fix (`docs/technical-reference.md` § 13) resolves `tenant_id` from the caller's own profile and was live on both envs before this runbook was first written. **Both EFs are safe to use from any tenant's admin dashboard**; no manual SQL workaround is needed for pilot customers.

---

## Step 5 — Admin handoff

**`register-tenant` sends a real invite email automatically to `admin_email` at creation time**
(added 2026-09-03 — before this, the function created the admin's auth user with no password, no
email, and no automated way in at all; the only path was this section's own dashboard fallback,
run every time). Check the function's JSON response for `invite_sent: true` — if it came back
`false`, the tenant and admin account are still real and correctly created, but the email failed
(check `RESEND_API_KEY` is set) and you need the fallback below.

**What the admin actually sees:** the email links to a page where they set a password. Once set,
**they land on `catalog.html`, not `admin.html` directly** — from there they use the nav's Admin
link (visible because their profile has `is_admin = true`) to reach the admin surface. Confirm with
them that they can:

1. Follow the emailed link and set a password
2. Reach `admin.html` via the nav and see an **empty, scoped** admin surface (0 customers, no
   founding data visible)

**The access URL depends on `plan`, and this matters for what you tell the admin.** A `free`
tenant has **no provisioned hostname** (Step 3 is paid-only, § above) — their shop, and their own
admin panel, live at `https://pulllist.app/?t=<slug>` (the invite email itself says this). Do
**not** tell a free-tier admin to expect `<slug>.pulllist.app` — it will not resolve (F145). A
`pro` tenant's hostname should already be live from Step 3, run before this step for a paid tenant.

If the invite email didn't arrive or the link has expired (links expire; re-invitation may be
needed), use the Supabase Auth dashboard → **Users** → find `admin_email` → **Send magic link**.
(Note: a **magic link** signs them straight into `catalog.html` with no password-setup step at
all — different from the emailed **recovery** link, which prompts them to set one. Either gets
them in; only the recovery-style link also gets them a password for next time.)

---

## Step 6 — Isolation spot-check before announcing

Run this in the prod SQL Editor (superuser view — no transaction wrapper needed):

```sql
SELECT
  (SELECT COUNT(*) FROM public.tenants) AS total_tenants,
  (SELECT COUNT(*) FROM public.user_profiles WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = '<slug>')) AS new_tenant_profiles,
  (SELECT COUNT(*) FROM public.catalog       WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = '<slug>')) AS new_tenant_catalog,
  (SELECT COUNT(*) FROM public.preorders     WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = '<slug>')) AS new_tenant_preorders,
  (SELECT COUNT(*) FROM public.user_profiles WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'rjbookstop')) AS founding_profiles,
  (SELECT COUNT(*) FROM public.preorders     WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'rjbookstop')) AS founding_preorders;
```

Expected: `new_tenant_profiles = 1` (admin only), `new_tenant_catalog = 0` (unless you seeded), `new_tenant_preorders = 0`, founding rows unchanged from before this onboarding.

Also confirm founding write-smoke: reserve one item on `pulllist.app` as a test customer → row has founding `tenant_id` → cancel it.

If any count is unexpected, investigate before announcing the new tenant. File a finding (next free ID: check `docs/technical-reference.md` § 13 last entry) and do not proceed to real-customer go-live.

---

## Step 7 — Real-customer go-live checklist (post-pilot, when the tenant is ready)

**This is a one-way step.** Once real customers write preorders, subscriptions, or reservation history under the new tenant, the clean §4.1 FK-ordered teardown no longer applies. Assess before proceeding.

- [ ] **F9 shipment-import collision gate — ⚠️ the only item here that can damage a *different* tenant, and the only one whose trigger may arrive before go-live.** Check this **before this tenant's first shipment import**, whenever that happens — pilot or live. `weekly_shipment_unique` is `(distributor, upc, on_sale_date)` with no `tenant_id`. Two comic shops stock the same books on the same street date, so a shared `(upc, on_sale_date)` is near-certain rather than unlucky. On the Format A path (`distributor='PRH'`) the import upserts with `resolution=merge-duplicates` and the payload carries `tenant_id` — so a collision does not error, it **UPDATEs the other tenant's row and rewrites its `tenant_id`**, silently moving that row out of the tenant that owns it. Verify:

  ```sql
  SELECT indexdef FROM pg_indexes
  WHERE schemaname = 'public' AND tablename = 'weekly_shipment'
    AND indexname = 'weekly_shipment_unique';
  ```

  If the result does **not** contain `tenant_id`, F9 has regressed: **do not run a shipment import for this tenant.** (**Prod and staging state as of 2026-07-28: fixed** — `weekly_shipment_tenant_unique` on `(tenant_id, distributor, upc, on_sale_date)`, with the old `weekly_shipment_unique` constraint dropped on both. The check is kept as a standing guard, not because it is currently failing.) See `docs/technical-reference.md` § 13 F9.
- [ ] **Plan tier is correct and matches reality** (F72 S0): `SELECT slug, plan FROM public.tenants WHERE slug = '<slug>';` returns the intended value. A paying tenant left on `free` renders generic identity everywhere; a `pro` tenant whose `<slug>.pulllist.app` is unprovisioned puts a non-resolving URL on customer paper (Step 3). **Check the column, not the invoice.**
- [ ] **F72 email-branding decision:** `register-customer` sends founding-branded confirmation emails regardless of tenant. Confirm this is acceptable for the tenant's launch, OR wait for a dedicated multi-tenant email branding sub-deploy (Phase 6 / follow-on). Surfacing this to the tenant admin before go-live is required.
- [x] ~~**MailerLite webhook configured** (Step 4)~~ — **N/A since 2026-08-30.** The webhook path was removed from `register-customer` platform-wide; there is nothing to configure. Customers arrive via admin **Invite Customer** / **Add Paper Customer**, or via native self-registration — and native signup is gated on **F72** (founding-branded confirmation email), which is the item that actually matters before a real-customer go-live.
- [ ] **Isolation spot-check green** (Step 6) against the pilot/seeded data.
- [ ] **`<slug>.pulllist.app` TLS Active** and the admin has confirmed sign-in.
- [ ] **Rollback acknowledged:** once real customers are onboarded, forward-fix only. The tenant row + its customer data cannot be cleanly removed via the §4.1 teardown.

Only after all boxes are checked: announce the new tenant and allow customer-facing use.

---

## Rollback (while tenant is pilot/seeded — clean teardown)

While the tenant has no real customer writes (pilot/seeded only), use the §4.1 FK-ordered teardown:

```sql
-- Prod SQL Editor — substitute <tenant_id> from scratch file
-- Run in this order; verify each before continuing
DELETE FROM usage_events        WHERE tenant_id = '<tenant_id>'::uuid;
DELETE FROM reservation_history WHERE tenant_id = '<tenant_id>'::uuid;
DELETE FROM preorders           WHERE tenant_id = '<tenant_id>'::uuid;
DELETE FROM subscriptions       WHERE tenant_id = '<tenant_id>'::uuid;
DELETE FROM weekly_shipment     WHERE tenant_id = '<tenant_id>'::uuid;
DELETE FROM catalog             WHERE tenant_id = '<tenant_id>'::uuid;
DELETE FROM app_settings        WHERE tenant_id = '<tenant_id>'::uuid;
-- user_profiles before auth.users (FK)
DELETE FROM user_profiles WHERE tenant_id = '<tenant_id>'::uuid;
-- auth.users: delete the admin + any pilot customers
-- Option A (SQL Editor): DELETE FROM auth.users WHERE id IN ('<admin_user_id>'::uuid, ...);
-- Option B (service-role curl): DELETE /auth/v1/admin/users/<user_id>
-- Tenant row (last — FKs cascade or are satisfied by prior deletes)
DELETE FROM tenants WHERE id = '<tenant_id>'::uuid;
-- Verify
SELECT COUNT(*) AS tenant_rows FROM tenants WHERE id = '<tenant_id>'::uuid;
-- Expected: 0
```

Also remove the Cloudflare custom domain from the Pages project (see Step 3a for the live inventory — do **not** remove `rjbookstop.pulllist.app` or the apex). No MailerLite webhook needs unsetting: that path was removed 2026-08-30.

After real customer writes: no clean teardown exists. Forward-fix only.

---

## References

- `register-tenant` contract: `docs/technical-reference.md` § 11.3
- FK-ordered teardown template: `docs/phase-4.1-canary-procedure.md` § Teardown
- curl pattern (`--data-binary @file`; not `Invoke-RestMethod`): `CLAUDE.md` § Known Issues
- F34 (`create-paper-customer` / `invite-customer` tenant resolution, fixed 2026-05-10): `docs/technical-reference.md` § 13 F34
- F72 (`register-customer` email branding still founding-only): `docs/technical-reference.md` § 13 F72
- F9 (`weekly_shipment` unique key omitted `tenant_id` — silent cross-tenant row capture on shipment import): **resolved 2026-07-28 on both environments.** `docs/technical-reference.md` § 13 F9. The Step 7 check remains as a standing regression guard; **its trigger is the first shipment import, not go-live.**
- F105 (why gates like F9 are written as checkboxes here rather than as prose in a finding): `docs/technical-reference.md` § 13 F105. The F6 precondition that motivated it was missed by 13 days because it lived only in a SQL comment.
- Reserved slug denylist: `docs/technical-reference.md` § 11.3 (`register-tenant` contract)
- Projects: prod `plgegklqtdjxeglvyjte`; staging `puoaiyezsreowpwxzxhj`
- Founding tenant: `rjbookstop` / `20941129-c35a-476d-ae21-44b8f77af89c`
- Wildcard DNS/TLS (Phase 6): until Phase 6 lands, each new tenant requires a **manual** Cloudflare custom-domain add (one per tenant). Self-serve subdomain provisioning is not yet available.
