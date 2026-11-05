/**
 * approve-customer — Admin-only Edge Function
 *
 * Called from the admin panel Pending tab to approve a pending account.
 * Sets user_profiles.status = 'active' and sends a branded approval
 * email containing a fresh magic link so the customer can log in
 * immediately and start making reservations.
 *
 * Request body: { user_id: string }
 * Auth: Bearer token from the admin's active session (required)
 */

const APP_BASE_URL  = Deno.env.get('APP_BASE_URL') ?? 'https://pulllist.app'
const APP_INDEX_URL = `${APP_BASE_URL}/index.html`

const MAIL_FROM_EMAIL = Deno.env.get('MAIL_FROM_EMAIL') ?? 'noreply@mrcyberrick.us'

// ── F72 G-F shared tenant-identity block — BEGIN ─────────────────────────────
// Byte-identical in approve-customer, invite-customer, notify-customers,
// reset-password and send-my-list; a grep gate checks the five copies match
// (docs/f72-g-f-mail-and-signup-gate.md, V2). Every tenant's own display_name
// is shown, both tiers; plan = 'pro' adds the shop address and phone. On any
// lookup failure the mail says PULLLIST, never MAIL_FROM_NAME (that secret
// holds the founding tenant's name, so falling back to it re-leaks it).
const PLATFORM_NAME = 'PULLLIST'

// Q14: the only `pro` tenant is the founding store, so the paid contact line is
// a literal. A second paid tenant needs it read from the tenants row instead.
const PAID_CONTACT_HTML = '40 W Main St. Rockaway, NJ 07866 &middot; (973) 586-9182'

type TenantIdentity = { storeName: string; isPaid: boolean; location: string }

function escapeHtml(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
}

// The display name inside a "Name <address>" From header: drop characters
// that would break the header.
function mailFromName(t: TenantIdentity): string {
  return t.storeName.replace(/[<>"\r\n]/g, '').trim() || PLATFORM_NAME
}

async function fetchTenantIdentity(
  supabaseUrl: string | undefined,
  serviceKey: string | undefined,
  tenantId: string | null | undefined,
): Promise<TenantIdentity> {
  const fallback: TenantIdentity = { storeName: PLATFORM_NAME, isPaid: false, location: '' }
  if (!supabaseUrl || !serviceKey || !tenantId) return fallback
  try {
    const res = await fetch(
      `${supabaseUrl}/rest/v1/tenants?id=eq.${encodeURIComponent(tenantId)}&select=display_name,plan,location`,
      { headers: { Authorization: `Bearer ${serviceKey}`, apikey: serviceKey, Accept: 'application/json' } },
    )
    if (!res.ok) return fallback
    const rows = await res.json()
    const row = Array.isArray(rows) ? rows[0] : undefined
    if (!row) return fallback
    return {
      storeName: (typeof row.display_name === 'string' && row.display_name.trim()) ? row.display_name : PLATFORM_NAME,
      isPaid:    row.plan === 'pro',
      location:  typeof row.location === 'string' ? row.location.trim() : '',
    }
  } catch (err) {
    console.warn('fetchTenantIdentity: lookup failed', String(err))
    return fallback
  }
}
// ── F72 G-F shared tenant-identity block — END ───────────────────────────────

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const SUPABASE_URL     = Deno.env.get('SUPABASE_URL')
    const SUPABASE_ANON    = Deno.env.get('SUPABASE_ANON_KEY')
    const SUPABASE_SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    const RESEND_API_KEY   = Deno.env.get('RESEND_API_KEY')

    // ── Parse body ──────────────────────────────────────────────
    let user_id: string
    try {
      const body = await req.json()
      user_id = (body.user_id || '').trim()
    } catch {
      return Response.json({ error: 'Invalid JSON body' }, { status: 400, headers: corsHeaders })
    }
    if (!user_id) {
      return Response.json({ error: 'user_id required' }, { status: 400, headers: corsHeaders })
    }

    // ── Verify caller is an authenticated admin ─────────────────
    // Supabase validates the JWT before the function runs (JWT enabled).
    // We still verify is_admin using the service key to confirm the caller
    // is actually an admin, not just any authenticated user.
    const authHeader = req.headers.get('Authorization') || ''

    // Extract user ID from the JWT claims via Supabase auth API
    const userRes = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
      headers: {
        Authorization: authHeader,
        apikey: SUPABASE_SERVICE!,   // use service key — anon key may not be in secrets
      },
    })
    const userData = await userRes.json()
    if (!userRes.ok || !userData.id) {
      console.error('approve-customer: could not resolve caller identity', JSON.stringify(userData))
      return Response.json({ error: 'Unauthorized' }, { status: 401, headers: corsHeaders })
    }

    const profileRes = await fetch(
      `${SUPABASE_URL}/rest/v1/user_profiles?id=eq.${userData.id}&select=is_admin,tenant_id`,
      {
        headers: {
          Authorization: `Bearer ${SUPABASE_SERVICE}`,
          apikey: SUPABASE_SERVICE!,
          Accept: 'application/json',
        },
      }
    )
    const profiles = await profileRes.json()
    if (!Array.isArray(profiles) || !profiles[0]?.is_admin) {
      return Response.json({ error: 'Forbidden' }, { status: 403, headers: corsHeaders })
    }
    const callerTenantId = profiles[0]?.tenant_id ?? null

    // ── Fetch target user's profile (need name + email) ─────────
    const targetRes = await fetch(
      `${SUPABASE_URL}/rest/v1/user_profiles?id=eq.${user_id}&select=id,full_name,email,status,tenant_id`,
      {
        headers: {
          Authorization: `Bearer ${SUPABASE_SERVICE}`,
          apikey:        SUPABASE_SERVICE!,
          Accept:        'application/json',
        },
      }
    )
    const targets = await targetRes.json()
    const target  = targets?.[0]
    if (!target) {
      return Response.json({ error: 'User not found' }, { status: 404, headers: corsHeaders })
    }
    // Cross-tenant guard: an admin may only approve pending users in their own
    // tenant. Respond 404 (not 403) so a cross-tenant probe cannot distinguish
    // "exists in another tenant" from "does not exist".
    if (!callerTenantId || target.tenant_id !== callerTenantId) {
      console.warn(`approve-customer: tenant mismatch — caller ${userData.id} vs target ${user_id}`)
      return Response.json({ error: 'User not found' }, { status: 404, headers: corsHeaders })
    }
    if (target.status === 'active') {
      return Response.json({ success: true, note: 'already_active' }, { headers: corsHeaders })
    }

    const fullName = target.full_name || 'Customer'
    const email    = target.email

    // ── Set status = 'active' ────────────────────────────────────
    const updateRes = await fetch(
      `${SUPABASE_URL}/rest/v1/user_profiles?id=eq.${user_id}`,
      {
        method: 'PATCH',
        headers: {
          Authorization: `Bearer ${SUPABASE_SERVICE}`,
          apikey:        SUPABASE_SERVICE!,
          'Content-Type': 'application/json',
          Prefer:         'return=minimal',
        },
        body: JSON.stringify({ status: 'active' }),
      }
    )
    if (!updateRes.ok) {
      const txt = await updateRes.text()
      console.error('approve-customer: status update failed', txt)
      return Response.json({ error: 'Failed to update status' }, { status: 500, headers: corsHeaders })
    }

    console.log(`approve-customer: approved ${email} (${user_id})`)

    // ── Send approval email only if we have an email address ─────
    if (!email) {
      console.warn('approve-customer: no email stored for user, skipping notification')
      return Response.json({ success: true, emailed: false }, { headers: corsHeaders })
    }

    // Generate a fresh magic link so they can log in right away
    const linkRes = await fetch(`${SUPABASE_URL}/auth/v1/admin/generate_link`, {
      method: 'POST',
      headers: {
        Authorization:  `Bearer ${SUPABASE_SERVICE}`,
        apikey:         SUPABASE_SERVICE!,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        type:        'magiclink',
        email,
        redirect_to: `${APP_BASE_URL}/catalog.html`,
      }),
    })
    const linkData    = await linkRes.json()
    const hashedToken = linkData.hashed_token as string | undefined
    const magicUrl    = hashedToken
      ? `${APP_INDEX_URL}?token_hash=${hashedToken}&type=magiclink`
      : `${APP_BASE_URL}/`

    // F72 G-F: the approving shop's own identity (target.tenant_id == the
    // admin's tenant, checked above).
    const tenant = await fetchTenantIdentity(SUPABASE_URL, SUPABASE_SERVICE, target.tenant_id)

    const mailRes = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization:  `Bearer ${RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from:    `${mailFromName(tenant)} <${MAIL_FROM_EMAIL}>`,
        to:      email,
        subject: `${tenant.storeName} — You're approved for the pull list!`,
        html:    buildApprovalEmail(fullName, magicUrl, tenant),
      }),
    })

    if (!mailRes.ok) {
      const mailErr = await mailRes.json().catch(() => ({}))
      console.error('approve-customer: Resend error', JSON.stringify(mailErr))
      // Don't fail — approval was saved, just the email didn't send
      return Response.json({ success: true, emailed: false }, { headers: corsHeaders })
    }

    return Response.json({ success: true, emailed: true }, { headers: corsHeaders })

  } catch (err) {
    console.error('approve-customer: unexpected error', String(err))
    return Response.json({ error: String(err) }, { status: 500, headers: corsHeaders })
  }
})

// ── Email template ────────────────────────────────────────────────────────────
// F72 G-F: the shop's own name everywhere (escaped); the address/phone
// paragraph only for plan = 'pro'. For the founding tenant the output is
// byte-identical to the previous hardcoded template.
function buildApprovalEmail(name: string, magicUrl: string, tenant: TenantIdentity): string {
  const safeStore = escapeHtml(tenant.storeName)
  const contactParagraph = tenant.isPaid
    ? `    <p style="margin-top:24px;font-size:0.78rem;color:#666;line-height:1.6">
      Questions? Stop by or give us a call.<br>
      ${safeStore} &middot; ${PAID_CONTACT_HTML}
    </p>
`
    : ''
  return `
<div style="font-family:Arial,sans-serif;max-width:520px;margin:0 auto;background:#1a1a1a;color:#f0f0f0;border-radius:8px;overflow:hidden">
  <div style="background:#111;padding:24px 32px;border-bottom:3px solid #e63946">
    <div style="font-size:1.6rem;font-weight:900;letter-spacing:0.08em">PULL<span style="color:#e63946">LIST</span></div>
    <div style="font-size:0.75rem;color:#888;margin-top:2px">${safeStore} &mdash; Monthly Comics Pre-Order System</div>
  </div>
  <div style="padding:32px">
    <h2 style="margin:0 0 16px;font-size:1.1rem;color:#fff">Hi ${name} — you're in!</h2>
    <p style="color:#ccc;line-height:1.7;margin:0 0 16px">
      Your PULLLIST account has been approved by ${safeStore}.
      You can now browse the monthly catalog and reserve your titles before the order deadline.
    </p>
    <p style="color:#ccc;line-height:1.7;margin:0 0 24px">
      Click below to sign in and get started. You can also set a password from the login page
      so you don't need a link each time.
    </p>
    <a href="${magicUrl}"
       style="display:inline-block;background:#e63946;color:white;padding:13px 28px;
              border-radius:4px;text-decoration:none;font-weight:700;font-size:0.9rem;
              letter-spacing:0.03em">
      Go to My Pull List &rarr;
    </a>
    <div style="margin-top:24px;background:rgba(255,255,255,0.04);
                border-left:3px solid rgba(232,57,70,0.4);padding:12px 16px;
                border-radius:0 4px 4px 0">
      <div style="font-size:0.78rem;color:#aaa;line-height:1.8">
        &#10003;&nbsp; This invite was sent personally by ${safeStore}<br>
        &#10003;&nbsp; You will not be charged &mdash; this is a reservation system only<br>
        &#10003;&nbsp; If your link expires, use Forgot Password on the login page
      </div>
    </div>
${contactParagraph}  </div>
  <div style="background:#111;padding:16px 32px;font-size:0.72rem;color:#555;border-top:1px solid #222">
    ${safeStore} &middot; Sent via the PullList pre-order system
  </div>
</div>`
}