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
    const SUPABASE_URL       = Deno.env.get('SUPABASE_URL')
    const SUPABASE_ANON      = Deno.env.get('SUPABASE_ANON_KEY')
    const SUPABASE_SERVICE   = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    const RESEND_API_KEY     = Deno.env.get('RESEND_API_KEY')
    const FOUNDING_TENANT_ID = Deno.env.get('FOUNDING_TENANT_ID')

    if (!FOUNDING_TENANT_ID) {
      console.warn('invite-customer: FOUNDING_TENANT_ID secret not set')
    }

    // Parse body
    let name, email
    try {
      const body = await req.json()
      name  = (body.name  || '').trim()
      email = (body.email || '').trim()
    } catch {
      return Response.json({ error: 'Invalid body' }, { status: 400, headers: corsHeaders })
    }

    if (!name || !email) {
      return Response.json({ error: 'Name and email required' }, { status: 400, headers: corsHeaders })
    }

    // Verify caller is authenticated
    const authHeader = req.headers.get('Authorization') || ''
    const userRes = await fetch(SUPABASE_URL + '/auth/v1/user', {
      headers: { Authorization: authHeader, apikey: SUPABASE_ANON }
    })
    const userData = await userRes.json()
    if (!userRes.ok || !userData.id) {
      return Response.json({ error: 'Unauthorized' }, { status: 401, headers: corsHeaders })
    }

    // Verify caller is admin — also fetch tenant_id for F34 fix
    const profileRes = await fetch(
      SUPABASE_URL + '/rest/v1/user_profiles?id=eq.' + userData.id + '&select=is_admin,tenant_id',
      { headers: { Authorization: authHeader, apikey: SUPABASE_ANON, Accept: 'application/json' } }
    )
    const profiles = await profileRes.json()
    if (!Array.isArray(profiles) || !profiles[0] || !profiles[0].is_admin) {
      return Response.json({ error: 'Forbidden' }, { status: 403, headers: corsHeaders })
    }

    // Resolve the inviting admin's tenant — fall back to FOUNDING_TENANT_ID if lookup fails
    const callerTenantId = profiles[0]?.tenant_id || FOUNDING_TENANT_ID

    // Generate invite link via Supabase Admin API (no email sent by Supabase)
    const generateRes = await fetch(SUPABASE_URL + '/auth/v1/admin/generate_link', {
      method: 'POST',
      headers: {
        Authorization: 'Bearer ' + SUPABASE_SERVICE,
        apikey: SUPABASE_SERVICE,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        type:        'invite',
        email:       email,
        data:        { full_name: name },
        redirect_to: APP_INDEX_URL,
      }),
    })
    const generateData = await generateRes.json()
    console.log('generate_link response:', JSON.stringify(generateData))

    if (!generateRes.ok) {
      const msg = ((generateData.msg || generateData.message) || '').toLowerCase()
      if (msg.includes('already') || msg.includes('duplicate')) {
        return Response.json({ error: 'A user with this email already exists' }, { status: 409, headers: corsHeaders })
      }
      return Response.json({ error: generateData.msg || generateData.message || 'Failed to generate invite' }, { status: 400, headers: corsHeaders })
    }

    // Use Supabase's action_link directly — it routes through the Supabase verify
    // endpoint and then redirects to APP_INDEX_URL. More reliable than constructing
    // a custom URL from hashed_token, which requires the client app to call verifyOtp.
    const action_url = generateData.action_link as string
    const userId     = generateData.user?.id
                    || generateData.data?.user?.id
                    || generateData.id

    console.log('action_url:', action_url, 'userId:', userId)

    if (!action_url) {
      return Response.json({ error: 'Failed to generate invite link' }, { status: 500, headers: corsHeaders })
    }

    // F72 G-F: the inviting shop's own identity.
    const tenant = await fetchTenantIdentity(SUPABASE_URL, SUPABASE_SERVICE, callerTenantId)

    // Send branded invite email via Resend — inline HTML, no template dependency
    const mailRes = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: 'Bearer ' + RESEND_API_KEY,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from:    `${mailFromName(tenant)} <${MAIL_FROM_EMAIL}>`,
        to:      email,
        subject: `${tenant.storeName} — Your pull list account is ready`,
        html:    buildInviteEmail(name, action_url, tenant),
      }),
    })

    if (!mailRes.ok) {
      const mailErr = await mailRes.json().catch(() => ({}))
      console.error('Resend error:', JSON.stringify(mailErr))
      return Response.json({ error: 'Failed to send invite email' }, { status: 500, headers: corsHeaders })
    }

    // Create user_profiles record — tenant_id scopes the new user to the inviting admin's tenant
    if (userId) {
      await fetch(SUPABASE_URL + '/rest/v1/user_profiles', {
        method: 'POST',
        headers: {
          Authorization: 'Bearer ' + SUPABASE_SERVICE,
          apikey: SUPABASE_SERVICE,
          'Content-Type': 'application/json',
          Prefer: 'resolution=merge-duplicates',
        },
        body: JSON.stringify({
          id:               userId,
          full_name:        name,
          email:            email,
          status:           'active',
          is_admin:         false,
          created_by_admin: true,
          tenant_id:        callerTenantId,
        }),
      })
    } else {
      console.error('Could not extract userId from generateData:', JSON.stringify(generateData))
    }

    // Customer engagement S2 (closes F89): record the invite. Attributed to
    // the admin who sent it, not the new customer — the same reasoning
    // convert-paper-customer already documents: a non-promo event under the
    // customer's own id would read as their own activity (Analytics' tally,
    // Accounts' "last seen"), marking a just-invited customer active today.
    // Non-fatal: a logging failure must never undo an invite that already sent.
    if (userId) {
      try {
        const evRes = await fetch(SUPABASE_URL + '/rest/v1/usage_events', {
          method: 'POST',
          headers: {
            Authorization: 'Bearer ' + SUPABASE_SERVICE,
            apikey: SUPABASE_SERVICE,
            'Content-Type': 'application/json',
            Prefer: 'return=minimal',
          },
          body: JSON.stringify({
            event_type: 'invite_sent',
            user_id:    userData.id,
            tenant_id:  callerTenantId,
            metadata:   { target_user_id: userId, via: 'invite' },
          }),
        })
        if (!evRes.ok) console.error('invite-customer: usage_events insert failed', evRes.status, await evRes.text())
      } catch (err) {
        console.error('invite-customer: usage_events insert threw', String(err))
      }
    }

    return Response.json({ success: true, user_id: userId }, { headers: corsHeaders })

  } catch (err) {
    console.error('Unexpected error:', String(err))
    return Response.json({ error: String(err) }, { status: 500, headers: corsHeaders })
  }
})

// ── Email template ─────────────────────────────────────────────────────────────
// F72 G-F: the shop's own name everywhere (escaped); the address/phone
// paragraph only for plan = 'pro'. For the founding tenant the output is
// byte-identical to the previous hardcoded template.
function buildInviteEmail(name: string, actionUrl: string, tenant: TenantIdentity): string {
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
    <h2 style="margin:0 0 16px;font-size:1.1rem;color:#fff">Hi ${name} — you're invited!</h2>
    <p style="color:#ccc;line-height:1.7;margin:0 0 16px">
      ${safeStore} has set up a PULLLIST account for you.
      Click below to sign in and start browsing the monthly catalog.
    </p>
    <p style="color:#ccc;line-height:1.7;margin:0 0 24px">
      You can set a password from the login page so you don't need a link each time.
    </p>
    <a href="${actionUrl}"
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
