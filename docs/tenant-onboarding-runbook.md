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
{ "tenant_id": "...", "admin_user_id": "...", "slug": "...", "webhook_secret": "..." }
```

**Save all four values to a local scratch file. Do not paste `webhook_secret` into chat.**

Error responses:
- `401` — operator secret wrong or not loaded; re-check `.env`
- `409 slug_taken` — slug already exists; choose another
- `400` — required fields missing; check the request body
- Non-200 — run the §4.1 FK-ordered teardown (Step rollback below) before retrying

---

## Step 2 — Set / refine branding

If branding was included in the `register-tenant` body it is already seeded. If not, or if you want to update it after creation:

```sql
-- Prod SQL Editor
UPDATE public.tenants
  SET branding = '{"primary_color":"#xxxxxx","display_name":"<display_name>"}'::jsonb
  WHERE slug = '<slug>';
SELECT id, slug, display_name, branding FROM public.tenants WHERE slug = '<slug>';
```

Expected: one row with the correct branding.

---

## Step 3 — Add the Cloudflare custom domain

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

---

## Step 4 — Configure MailerLite webhook (only if the tenant will use webhook-based registration)

The `register-tenant` response's `webhook_secret` is the query parameter for the `register-customer` Edge Function URL:

```
https://plgegklqtdjxeglvyjte.supabase.co/functions/v1/register-customer?secret=<webhook_secret>
```

In MailerLite: **Automations → Webhook → URL** → paste the URL above.

If the tenant will not use MailerLite during the pilot period, **defer this step and note it**. Pilot customers can be added via direct service-role INSERT into `user_profiles` (see § Operational note below). Deferring does not block any other step.

**Operational note — F34 residual:** `create-paper-customer` and `invite-customer` Edge Functions currently write to `FOUNDING_TENANT_ID` regardless of the calling admin's tenant. **Do NOT use these EFs from a non-founding admin dashboard during the pilot.** Add pilot customers via SQL with a service-role key:

```sql
-- Prod SQL Editor (service-role / postgres)
INSERT INTO user_profiles (id, full_name, email, is_paper, tenant_id, status)
VALUES (gen_random_uuid(), '<name>', '<email>', true, '<tenant_id>'::uuid, 'active');
```

This restriction applies until F34 residual is fully remediated (a follow-on sub-deploy).

---

## Step 5 — Admin handoff

Deliver the magic link to the tenant admin's mailbox. The `register-tenant` function sends the magic link automatically to `admin_email` at creation time (via Supabase Auth's invite flow). Confirm with the admin that they can:

1. Sign in via the link at `https://<slug>.pulllist.app/admin.html`
2. See an **empty, scoped** admin surface (0 customers, no founding data visible)

If the magic link has expired (links expire; re-invitation may be needed), use the Supabase Auth dashboard → **Users** → find `admin_email` → **Send magic link**.

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

- [ ] **F72 email-branding decision:** `register-customer` sends founding-branded confirmation emails regardless of tenant. Confirm this is acceptable for the tenant's launch, OR wait for a dedicated multi-tenant email branding sub-deploy (Phase 6 / follow-on). Surfacing this to the tenant admin before go-live is required.
- [ ] **MailerLite webhook configured** (Step 4) if the tenant uses webhook-based customer registration.
- [ ] **Isolation spot-check green** (Step 6) against the pilot/seeded data.
- [ ] **`<slug>.pulllist.app` TLS Active** and the admin has confirmed sign-in.
- [ ] **Rollback acknowledged:** once real customers are onboarded, forward-fix only. The tenant row + its customer data cannot be cleanly removed via the §4.1 teardown.
- [ ] **Inform the tenant admin** about the `create-paper-customer` / `invite-customer` F34 residual (§ Step 4 operational note) — until remediated, paper customers added from their admin dashboard would land in the founding tenant.

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

Also remove the Cloudflare custom domain from the Pages project and unset the MailerLite webhook URL if configured.

After real customer writes: no clean teardown exists. Forward-fix only.

---

## References

- `register-tenant` contract: `docs/technical-reference.md` § 11.3
- FK-ordered teardown template: `docs/phase-4.1-canary-procedure.md` § Teardown
- curl pattern (`--data-binary @file`; not `Invoke-RestMethod`): `CLAUDE.md` § Known Issues
- F34 residual (`create-paper-customer` / `invite-customer` write to founding): `docs/technical-reference.md` § 13 F34
- F72 (`register-customer` email branding still founding-only): `docs/technical-reference.md` § 13 F72
- Reserved slug denylist: `docs/technical-reference.md` § 11.3 (`register-tenant` contract)
- Projects: prod `plgegklqtdjxeglvyjte`; staging `puoaiyezsreowpwxzxhj`
- Founding tenant: `rjbookstop` / `20941129-c35a-476d-ae21-44b8f77af89c`
- Wildcard DNS/TLS (Phase 6): until Phase 6 lands, each new tenant requires a **manual** Cloudflare custom-domain add (one per tenant). Self-serve subdomain provisioning is not yet available.
