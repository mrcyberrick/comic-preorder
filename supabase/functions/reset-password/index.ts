const FORGOT_PASSWORD_URL = `${Deno.env.get('APP_BASE_URL') ?? 'https://pulllist.app'}/forgot-password.html`

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
    const SUPABASE_SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    const RESEND_API_KEY   = Deno.env.get('RESEND_API_KEY')

    let email
    try {
      const body = await req.json()
      email = (body.email || '').trim()
    } catch {
      return Response.json({ error: 'Invalid body' }, { status: 400, headers: corsHeaders })
    }

    if (!email) {
      return Response.json({ error: 'Email required' }, { status: 400, headers: corsHeaders })
    }

    // Generate recovery link (no email sent by Supabase)
    const generateRes = await fetch(SUPABASE_URL + '/auth/v1/admin/generate_link', {
      method: 'POST',
      headers: {
        Authorization: 'Bearer ' + SUPABASE_SERVICE,
        apikey: SUPABASE_SERVICE,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        type:        'recovery',
        email:       email,
        redirect_to: FORGOT_PASSWORD_URL,
      }),
    })
    const generateData = await generateRes.json()

    // Always return success — never leak whether an email address exists
    if (!generateRes.ok) {
      console.log('generate_link failed:', generateData.message)
      return Response.json({ success: true }, { headers: corsHeaders })
    }

    // Build reset URL using hashed_token so email security scanners that
    // pre-fetch links don't consume the one-time token before the user clicks.
    // The forgot-password.html page reads token_hash + type from the query
    // string and calls supabase.auth.verifyOtp({ token_hash, type }) to
    // establish the session before prompting for a new password.
    const hashed_token = generateData.hashed_token
    const action_url   = FORGOT_PASSWORD_URL
                       + '?token_hash=' + hashed_token + '&type=recovery'

    const name = generateData.user?.user_metadata?.full_name
              || generateData.email?.split('@')[0]
              || 'there'

    // F72 G-F: the account's own shop, from the user id generate_link just
    // returned (not a second email-keyed lookup). Runs only for an existing
    // account, after the early return above, and the response is the same
    // { success: true } either way, so it adds no enumeration signal.
    const userId = generateData.user?.id || generateData.id
    let tenantId: string | null = null
    if (userId) {
      try {
        const profileRes = await fetch(
          SUPABASE_URL + '/rest/v1/user_profiles?id=eq.' + encodeURIComponent(userId) + '&select=tenant_id&limit=1',
          { headers: { Authorization: 'Bearer ' + SUPABASE_SERVICE, apikey: SUPABASE_SERVICE, Accept: 'application/json' } },
        )
        const profiles = profileRes.ok ? await profileRes.json() : []
        tenantId = (Array.isArray(profiles) && profiles[0]?.tenant_id) || null
      } catch (err) {
        console.warn('reset-password: profile lookup failed', String(err))
      }
    }
    const tenant = await fetchTenantIdentity(SUPABASE_URL, SUPABASE_SERVICE, tenantId)

    // Send branded reset email — inline HTML, no shared template dependency
    const mailRes = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: 'Bearer ' + RESEND_API_KEY,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from:    `${mailFromName(tenant)} <${MAIL_FROM_EMAIL}>`,
        to:      email,
        subject: `${tenant.storeName} — Reset your password`,
        html:    buildResetEmail(name, action_url, tenant),
      }),
    })

    if (!mailRes.ok) {
      const mailErr = await mailRes.json().catch(() => ({}))
      console.error('Resend error:', JSON.stringify(mailErr))
    }

    return Response.json({ success: true }, { headers: corsHeaders })

  } catch (err) {
    console.error('Unexpected error:', String(err))
    return Response.json({ success: true }, { headers: corsHeaders })
  }
})

// ── Email template ─────────────────────────────────────────────────────────────
// F72 G-F: the shop's own name everywhere (escaped); the address/phone
// paragraph only for plan = 'pro'. For the founding tenant the output is
// byte-identical to the previous hardcoded template.
function buildResetEmail(name: string, actionUrl: string, tenant: TenantIdentity): string {
  const safeStore = escapeHtml(tenant.storeName)
  const contactParagraph = tenant.isPaid
    ? `    <p style="margin-top:16px;font-size:0.78rem;color:#666;line-height:1.6">
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
    <h2 style="margin:0 0 16px;font-size:1.1rem;color:#fff">Hi ${name} — reset your password</h2>
    <p style="color:#ccc;line-height:1.7;margin:0 0 24px">
      We received a request to reset the password for your PULLLIST account.
      Click below to choose a new password. This link expires in 1 hour.
    </p>
    <a href="${actionUrl}"
       style="display:inline-block;background:#e63946;color:white;padding:13px 28px;
              border-radius:4px;text-decoration:none;font-weight:700;font-size:0.9rem;
              letter-spacing:0.03em">
      Reset My Password &rarr;
    </a>
    <p style="margin-top:24px;color:#888;font-size:0.82rem;line-height:1.7">
      If you didn't request a password reset, you can safely ignore this email.
      Your password will not change.
    </p>
${contactParagraph}  </div>
  <div style="background:#111;padding:16px 32px;font-size:0.72rem;color:#555;border-top:1px solid #222">
    ${safeStore} &middot; Sent via the PullList pre-order system
  </div>
</div>`
}
