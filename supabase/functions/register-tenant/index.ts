/**
 * register-tenant — Gated operator Edge Function (new, 5.4 S3)
 *
 * Service-role-only tenant provisioning. Not customer-facing — Phase 5 ships no
 * public self-serve signup page (that is Phase 6, gated on a wildcard-DNS/TLS
 * spike). Invoked directly (curl / future internal tooling) by an operator
 * holding TENANT_PROVISION_SECRET — claims a slug, creates the tenant row, the
 * first admin auth user + profile, and a per-tenant MailerLite webhook secret
 * for register-customer.
 *
 * Auth gate: TENANT_PROVISION_SECRET via the `x-operator-secret` header, checked
 * before any body parsing. This is a platform-operator action, distinct from any
 * tenant's admin role, so it is gated by an operator secret rather than the
 * in-body /auth/v1/user pattern used by admin-facing functions. JWT verification
 * is OFF at the platform level (house pattern) — this header is the only gate.
 *
 * Input JSON body:
 *   { slug, display_name, admin_email, contact_email?, contact_phone?,
 *     location?, plan?, branding? }
 *
 *   plan: 'free' (default) | 'pro'. Allowlisted — any other value becomes 'free'.
 *   'pro' gates tenant identity on customer-facing surfaces (F72). A 'pro' tenant
 *   MUST have its <slug>.pulllist.app hostname provisioned (runbook Step 3): there
 *   is no wildcard DNS, so an unprovisioned paid tenant emails and prints a
 *   non-resolving URL to real customers (F145).
 *
 * Required env vars (set in Supabase → Edge Functions → Secrets):
 *   SUPABASE_URL
 *   SUPABASE_SERVICE_ROLE_KEY
 *   TENANT_PROVISION_SECRET     ← operator gate; never shared with tenant admins
 *   RESEND_API_KEY              ← admin invite email (added below, 2026-09-03)
 *   MAIL_FROM_EMAIL             ← same secret every other mail-sending function reads
 *   APP_BASE_URL                ← optional; defaults to https://pulllist.app
 *
 * Non-atomicity: this function performs a tenants INSERT, a GoTrue admin user
 * create, and a user_profiles INSERT — three separate calls, no shared
 * transaction. On a failure after a partial write, it attempts best-effort
 * compensation (delete profile → auth user → tenant, reverse FK order) before
 * returning 500. Any residue is fully removable via the FK-ordered teardown in
 * docs/phase-4.1-canary-procedure.md (proven end-to-end in 5.4 S4).
 *
 * F23 note: this is a Deno Edge Function, not a SQL SECURITY DEFINER function —
 * the parent's SET search_path hardening carve-out for new SQL functions does
 * not apply here; 5.4 adds no new SQL function.
 *
 * Admin invite email, added 2026-09-03 (closes the gap the onboarding runbook's
 * Step 5 wrongly claimed was already closed — this function previously created
 * the admin auth user with NO password, NO invite, NO email of any kind; the
 * only way in was an operator manually triggering a link via the Supabase
 * dashboard). Sent AFTER the tenant + admin profile are fully written; a mail
 * failure here does NOT roll back the tenant (compensate() is not called) —
 * the account is real and recoverable via the runbook's existing dashboard
 * fallback or the admin's own Forgot Password flow (reset-password's `type:
 * 'recovery'` works on any existing account). The response's new `invite_sent`
 * field tells the operator whether that fallback is actually needed.
 *
 * Sender identity is deliberately "PULLLIST", not MAIL_FROM_NAME (which holds
 * today's founding-tenant literal) and not the new tenant's own display_name
 * either — this is the platform inviting someone to a shop that doesn't have
 * an operating identity yet from the recipient's own point of view. Re-reading
 * MAIL_FROM_NAME here would just relocate F72's leak into a brand-new
 * function; not reading it at all is the fix, not a fallback.
 */

const APP_BASE_URL  = Deno.env.get('APP_BASE_URL') ?? 'https://pulllist.app'
const APP_INDEX_URL = `${APP_BASE_URL}/index.html`

// Deliberately NOT reading MAIL_FROM_NAME here — see the header note above.
const MAIL_FROM_EMAIL = Deno.env.get('MAIL_FROM_EMAIL') ?? 'noreply@mrcyberrick.us'

// No _shared/ folder and no cross-function imports in this codebase (F72 S0
// Q11) — duplicated locally, same as every other mail-sending function's own
// copy of this exact helper.
function escapeHtml(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
}

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-operator-secret',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

// Reserved denylist (function-level — not a DB constraint): platform/infra words
// plus both founding slugs (staging + prod).
const RESERVED_SLUGS = new Set([
  'www', 'app', 'api', 'admin', 'staging', 'prod', 'mail', 'ftp', 'blog', 'dev',
  'test', 'canary', 'pulllist', 'raysandjudys', 'rjbookstop',
])

// DNS-safe lowercase slug — mirrors the DB tenants_slug_format_check constraint.
const SLUG_PATTERN = /^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$/

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const SUPABASE_URL             = Deno.env.get('SUPABASE_URL')
  const SUPABASE_SERVICE         = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const TENANT_PROVISION_SECRET  = Deno.env.get('TENANT_PROVISION_SECRET')
  const RESEND_API_KEY           = Deno.env.get('RESEND_API_KEY')

  // ── Operator-secret gate (checked before any body parsing) ────
  const providedSecret = req.headers.get('x-operator-secret') || ''
  if (!TENANT_PROVISION_SECRET || providedSecret !== TENANT_PROVISION_SECRET) {
    console.warn('register-tenant: missing or invalid operator secret')
    return Response.json({ error: 'Unauthorized' }, { status: 401, headers: corsHeaders })
  }

  let tenantId: string | undefined
  let adminUserId: string | undefined

  // ── Best-effort compensation (non-atomic; see header note) ─────
  async function compensate() {
    try {
      if (adminUserId) {
        await fetch(`${SUPABASE_URL}/rest/v1/user_profiles?id=eq.${adminUserId}`, {
          method:  'DELETE',
          headers: { 'Authorization': `Bearer ${SUPABASE_SERVICE}`, 'apikey': SUPABASE_SERVICE! },
        })
        await fetch(`${SUPABASE_URL}/auth/v1/admin/users/${adminUserId}`, {
          method:  'DELETE',
          headers: { 'Authorization': `Bearer ${SUPABASE_SERVICE}`, 'apikey': SUPABASE_SERVICE! },
        })
      }
      if (tenantId) {
        await fetch(`${SUPABASE_URL}/rest/v1/tenants?id=eq.${tenantId}`, {
          method:  'DELETE',
          headers: { 'Authorization': `Bearer ${SUPABASE_SERVICE}`, 'apikey': SUPABASE_SERVICE! },
        })
      }
    } catch (compErr) {
      console.error('register-tenant: compensation failed', String(compErr))
    }
  }

  try {
    // ── Parse + validate input ────────────────────────────────
    let body: Record<string, unknown>
    try {
      body = await req.json()
    } catch {
      return Response.json({ error: 'Invalid request body' }, { status: 400, headers: corsHeaders })
    }

    const slug         = ((body.slug as string | undefined) || '').trim().toLowerCase()
    const displayName  = ((body.display_name as string | undefined) || '').trim()
    const adminEmail   = ((body.admin_email as string | undefined) || '').trim()
    const contactEmail = (body.contact_email as string | undefined)?.trim() || null
    const contactPhone = (body.contact_phone as string | undefined)?.trim() || null
    const location      = (body.location as string | undefined)?.trim() || null
    // Plan tier (F72 S0). ALLOWLIST, not pass-through: the column is NOT NULL with
    // no CHECK constraint, so an unrecognised value ('Pro', 'paid', '') would persist
    // and read as free forever while looking paid to an operator inspecting the row.
    const planRaw       = (body.plan as string | undefined)?.trim().toLowerCase() || 'free'
    const plan          = planRaw === 'pro' ? 'pro' : 'free'
    const branding      = (body.branding && typeof body.branding === 'object') ? body.branding : {}

    if (!slug || !displayName || !adminEmail || !adminEmail.includes('@')) {
      return Response.json(
        { error: 'slug, display_name, and a valid admin_email are required' },
        { status: 400, headers: corsHeaders }
      )
    }

    if (RESERVED_SLUGS.has(slug)) {
      return Response.json({ error: 'slug_reserved' }, { status: 400, headers: corsHeaders })
    }

    if (!SLUG_PATTERN.test(slug)) {
      return Response.json(
        { error: 'invalid_slug', detail: 'slug must be lowercase DNS-safe (a-z0-9-)' },
        { status: 400, headers: corsHeaders }
      )
    }

    // ── Generate per-tenant webhook secret (for register-customer) ─
    const webhookSecret = crypto.randomUUID().replace(/-/g, '')

    // ── Insert tenants row (service-role; unique slug is the final authority) ─
    const tenantInsertRes = await fetch(`${SUPABASE_URL}/rest/v1/tenants`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${SUPABASE_SERVICE}`,
        'apikey':        SUPABASE_SERVICE!,
        'Content-Type':  'application/json',
        'Prefer':        'return=representation',
      },
      body: JSON.stringify({
        slug,
        display_name:  displayName,
        contact_email: contactEmail,
        contact_phone: contactPhone,
        location,
        plan,
        branding,
        settings: { mailerlite_webhook_secret: webhookSecret },
      }),
    })

    if (!tenantInsertRes.ok) {
      const errBody = await tenantInsertRes.json().catch(() => ({}))
      const code = (errBody.code as string | undefined) || ''
      if (code === '23505') {
        return Response.json({ error: 'slug_taken' }, { status: 409, headers: corsHeaders })
      }
      if (code === '23514') {
        return Response.json({ error: 'invalid_slug' }, { status: 400, headers: corsHeaders })
      }
      console.error('register-tenant: tenant insert failed', JSON.stringify(errBody))
      return Response.json({ error: 'Failed to create tenant' }, { status: 500, headers: corsHeaders })
    }

    const tenantRows = await tenantInsertRes.json()
    tenantId = Array.isArray(tenantRows) ? tenantRows[0]?.id as string | undefined : undefined
    if (!tenantId) {
      console.error('register-tenant: no tenant id in insert response', JSON.stringify(tenantRows))
      return Response.json({ error: 'Tenant created but no id returned' }, { status: 500, headers: corsHeaders })
    }

    // ── Create first admin via GoTrue admin API (no direct auth.users INSERT) ─
    const createRes = await fetch(`${SUPABASE_URL}/auth/v1/admin/users`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${SUPABASE_SERVICE}`,
        'apikey':        SUPABASE_SERVICE!,
        'Content-Type':  'application/json',
      },
      body: JSON.stringify({
        email:         adminEmail,
        email_confirm: true,
        user_metadata: { full_name: `${displayName} Admin` },
      }),
    })
    const createData = await createRes.json()

    if (!createRes.ok) {
      const msg = ((createData.msg || createData.message || '') as string).toLowerCase()
      console.error('register-tenant: admin user create failed', JSON.stringify(createData))
      await compensate()
      if (msg.includes('already') || msg.includes('duplicate') || createData.code === 'email_exists') {
        return Response.json({ error: 'admin_email_exists' }, { status: 409, headers: corsHeaders })
      }
      return Response.json({ error: 'Failed to create admin user' }, { status: 500, headers: corsHeaders })
    }

    adminUserId = createData.id as string | undefined
    if (!adminUserId) {
      console.error('register-tenant: no user id in create response', JSON.stringify(createData))
      await compensate()
      return Response.json({ error: 'Admin user created but no id returned' }, { status: 500, headers: corsHeaders })
    }

    // ── Insert admin user_profiles row (status mirrors create-paper-customer's
    // 'active' — there is no 'approved' value in user_profiles_status_check) ──
    const profileRes = await fetch(`${SUPABASE_URL}/rest/v1/user_profiles`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${SUPABASE_SERVICE}`,
        'apikey':        SUPABASE_SERVICE!,
        'Content-Type':  'application/json',
        'Prefer':        'resolution=merge-duplicates',
      },
      body: JSON.stringify({
        id:        adminUserId,
        full_name: `${displayName} Admin`,
        email:     adminEmail,
        status:    'active',
        is_admin:  true,
        tenant_id: tenantId,
      }),
    })

    if (!profileRes.ok) {
      const profErr = await profileRes.json().catch(() => ({}))
      console.error('register-tenant: admin profile insert failed', JSON.stringify(profErr))
      await compensate()
      return Response.json(
        { error: 'Admin user created but profile insert failed' },
        { status: 500, headers: corsHeaders }
      )
    }

    console.log(`register-tenant: created tenant ${tenantId} (${slug}) with admin ${adminUserId}`)

    // ── Invite the new admin (added 2026-09-03) — see header note. A failure
    // here does NOT roll back the tenant/admin: both are already real and
    // recoverable via the runbook's dashboard fallback or Forgot Password.
    // `invite_sent` in the response is how the operator finds out a fallback
    // is actually needed, instead of silently assuming this step worked.
    let inviteSent = false
    try {
      const genRes = await fetch(`${SUPABASE_URL}/auth/v1/admin/generate_link`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${SUPABASE_SERVICE}`,
          'apikey':        SUPABASE_SERVICE!,
          'Content-Type':  'application/json',
        },
        body: JSON.stringify({
          // NOT 'invite' — verified live (2026-09-03) that GoTrue's 'invite' type
          // only works to CREATE a user as a side effect (invite-customer's own
          // pattern, where the user doesn't exist yet). This function already
          // created the admin via /auth/v1/admin/users above, so 'invite' here
          // fails 422 email_exists every time. 'recovery' is the type reset-
          // password already proves works on an existing account; index.html's
          // own completion logic (both types share the set-password UI, differing
          // only in the heading text) confirms this lands correctly either way.
          type:        'recovery',
          email:       adminEmail,
          data:        { full_name: `${displayName} Admin` },
          redirect_to: APP_INDEX_URL,
        }),
      })
      const genData = await genRes.json()
      const actionUrl = genData.action_link as string | undefined

      if (!genRes.ok || !actionUrl) {
        console.error('register-tenant: admin invite link generation failed', JSON.stringify(genData))
      } else if (!RESEND_API_KEY) {
        console.error('register-tenant: RESEND_API_KEY not set, cannot send admin invite')
      } else {
        const mailRes = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${RESEND_API_KEY}`,
            'Content-Type':  'application/json',
          },
          body: JSON.stringify({
            from:    `PULLLIST <${MAIL_FROM_EMAIL}>`,
            to:      adminEmail,
            subject: `Welcome to PULLLIST — your ${displayName} admin account is ready`,
            html:    buildAdminInviteEmail(displayName, slug, actionUrl),
          }),
        })
        if (!mailRes.ok) {
          const mailErr = await mailRes.json().catch(() => ({}))
          console.error('register-tenant: admin invite Resend error', JSON.stringify(mailErr))
        } else {
          inviteSent = true
        }
      }
    } catch (inviteErr) {
      console.error('register-tenant: admin invite step threw', String(inviteErr))
    }

    return Response.json(
      { tenant_id: tenantId, admin_user_id: adminUserId, slug, webhook_secret: webhookSecret, invite_sent: inviteSent },
      { headers: corsHeaders }
    )

  } catch (err) {
    console.error('register-tenant: unexpected error', String(err))
    await compensate()
    return Response.json({ error: String(err) }, { status: 500, headers: corsHeaders })
  }
})

// ── Admin invite email — platform-branded, not tenant-branded (see header) ──
// Deliberately does NOT use the isPaid-gated phone/address pattern F72 S2a
// established for register-customer: this is PULLLIST inviting the SHOP OWNER
// to their own new shop, not a shop emailing its own customer, so there is no
// "hold back identity to motivate upgrading" angle here at all — showing the
// admin their own shop's info back to them isn't a paid-tier perk.
//
// Always shows the free `?t=<slug>` access link, never `<slug>.pulllist.app` —
// deliberately, even for a `plan='pro'` tenant. The paid hostname is a LATER,
// separate manual step (runbook Step 3, sequenced AFTER this one), so it may
// not be provisioned yet when this email sends. F145's own warning: printing
// an unprovisioned hostname anywhere puts a non-resolving URL in someone's
// hands. The apex `?t=` link always resolves, immediately, regardless of plan.
function buildAdminInviteEmail(storeName: string, slug: string, actionUrl: string): string {
  const safeStore = escapeHtml(storeName)
  const shopLink   = `${APP_BASE_URL}/?t=${encodeURIComponent(slug)}`
  return `
<div style="font-family:Arial,sans-serif;max-width:520px;margin:0 auto;background:#1a1a1a;color:#f0f0f0;border-radius:8px;overflow:hidden">
  <div style="background:#111;padding:24px 32px;border-bottom:3px solid #e63946">
    <div style="font-size:1.6rem;font-weight:900;letter-spacing:0.08em">PULL<span style="color:#e63946">LIST</span></div>
    <div style="font-size:0.75rem;color:#888;margin-top:2px">Monthly Comics Pre-Order System</div>
  </div>
  <div style="padding:32px">
    <h2 style="margin:0 0 16px;font-size:1.1rem;color:#fff">Welcome to PULLLIST!</h2>
    <p style="color:#ccc;line-height:1.7;margin:0 0 16px">
      Your new shop, <strong>${safeStore}</strong>, is ready. Click below to sign in and set a
      password for your admin account.
    </p>
    <a href="${actionUrl}"
       style="display:inline-block;background:#e63946;color:white;padding:13px 28px;
              border-radius:4px;text-decoration:none;font-weight:700;font-size:0.9rem;
              letter-spacing:0.03em">
      Set Up My Admin Account &rarr;
    </a>
    <div style="margin-top:24px;background:rgba(255,255,255,0.04);
                border-left:3px solid rgba(232,57,70,0.4);padding:12px 16px;
                border-radius:0 4px 4px 0">
      <div style="font-size:0.78rem;color:#aaa;line-height:1.8">
        &#10003;&nbsp; Your customers can already reach ${safeStore} at:<br>
        &nbsp;&nbsp;&nbsp;<a href="${shopLink}" style="color:#e63946">${shopLink}</a><br>
        &#10003;&nbsp; Sign in any time at pulllist.app with your email<br>
        &#10003;&nbsp; If this link expires, use Forgot Password on the sign-in page
      </div>
    </div>
    <p style="margin-top:24px;font-size:0.78rem;color:#666;line-height:1.6">
      Questions about the platform? pulllist@mrcyberrick.us
    </p>
  </div>
  <div style="background:#111;padding:16px 32px;font-size:0.72rem;color:#555;border-top:1px solid #222">
    Sent via the PULLLIST platform
  </div>
</div>`
}
