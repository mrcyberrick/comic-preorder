/**
 * register-customer — Public Edge Function
 *
 * Two entry paths, detected by whether the request carries a `?secret=` query param:
 *
 * 1. MailerLite webhook path (`?secret=<tenant's webhook secret>`) — called by a tenant's
 *    MailerLite webhook when a new subscriber is confirmed. Legacy path, retained harmlessly
 *    until MailerLite is retired for the founding tenant (see native-customer-signup plan § S5).
 *    Webhook URL to configure in MailerLite (per tenant — each tenant has its own generated
 *    secret, issued by register-tenant and stored in tenants.settings):
 *      https://<project>.supabase.co/functions/v1/register-customer?secret=<tenant's webhook secret>
 *    MailerLite webhook event: subscriber.created (or subscriber.updated)
 *
 * 2. Native direct-POST path (no `?secret=`) — called by the app's own "Create account" UI
 *    on a tenant's branded login (native-customer-signup, S2/S3). Body:
 *      { email, name, slug, turnstileToken, honeypot }
 *    Tenant is resolved from the posted `slug` (client already knows it via
 *    TenantContext.current().slug — resolved unauthenticated from the host). A caller can post
 *    any slug; worst case is a pending row in the wrong tenant, which that tenant's admin
 *    declines — the approval state machine is the real access gate, not signup itself. Abuse
 *    gate: honeypot (silent no-op) + Cloudflare Turnstile (server-verified) + the existing
 *    already_exists dedup below. No rate-limit table for v1 (added later only if needed).
 *
 * Both paths share the same account-create / profile-insert / magic-link / MailerSend tail
 * (provisionPendingCustomer below) — verbatim reuse, no behavior drift between paths.
 *
 * Required env vars (set in Supabase → Edge Functions → Secrets):
 *   SUPABASE_URL
 *   SUPABASE_SERVICE_ROLE_KEY
 *   MAILERSEND_API_KEY
 *   FOUNDING_TENANT_ID          ← retained for diagnostics; no longer the tenant source (see F34 note)
 *   TURNSTILE_SECRET_KEY        ← native path only; server-side Turnstile token verification
 *
 * F34 note (resolved 5.4 S2, 2026-06-16): the webhook path's tenant_id is resolved from the
 * incoming `?secret=` query param via a service-role lookup against
 * tenants.settings->>'mailerlite_webhook_secret' — the secret both authenticates the caller and
 * selects the tenant. Email branding (below) remains founding-branded for all tenants — tracked
 * separately as F72 (multi-tenant email branding is out of scope for Phase 5). The native path
 * is founding-only for the same reason (native-customer-signup plan § F72 disposition).
 */

const APP_BASE_URL  = Deno.env.get('APP_BASE_URL') ?? 'https://pulllist.app'
const APP_INDEX_URL = `${APP_BASE_URL}/index.html`

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

// ── Shared tail: create pending account, generate magic link, send email ────
async function provisionPendingCustomer(opts: {
  SUPABASE_URL: string
  SUPABASE_SERVICE: string
  MAILERSEND_API_KEY: string
  tenantId: string
  fullName: string
  email: string
}): Promise<Response> {
  const { SUPABASE_URL, SUPABASE_SERVICE, MAILERSEND_API_KEY, tenantId, fullName, email } = opts

  // ── Create Supabase auth user (no password, email pre-confirmed) ──
  const createRes = await fetch(`${SUPABASE_URL}/auth/v1/admin/users`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${SUPABASE_SERVICE}`,
      'apikey':        SUPABASE_SERVICE,
      'Content-Type':  'application/json',
    },
    body: JSON.stringify({
      email,
      email_confirm:  true,
      user_metadata:  { full_name: fullName },
    }),
  })
  const createData = await createRes.json()

  if (!createRes.ok) {
    const msg = ((createData.msg || createData.message || '') as string).toLowerCase()
    if (msg.includes('already') || msg.includes('duplicate') || createData.code === 'email_exists') {
      // Duplicate submission — account already created, no action needed, no second email
      console.log(`register-customer: duplicate for ${email}, skipping`)
      return Response.json({ success: true, note: 'already_exists' }, { headers: corsHeaders })
    }
    console.error('register-customer: user create failed', JSON.stringify(createData))
    return Response.json({ error: 'Failed to create account' }, { status: 500, headers: corsHeaders })
  }

  const userId = createData.id as string | undefined
  if (!userId) {
    return Response.json({ error: 'No user ID in response' }, { status: 500, headers: corsHeaders })
  }

  // ── Insert user_profiles row (status = 'pending') ────────────
  const profileRes = await fetch(`${SUPABASE_URL}/rest/v1/user_profiles`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${SUPABASE_SERVICE}`,
      'apikey':        SUPABASE_SERVICE,
      'Content-Type':  'application/json',
      'Prefer':        'resolution=merge-duplicates',
    },
    body: JSON.stringify({
      id:        userId,
      full_name: fullName,
      email,
      status:    'pending',
      is_admin:  false,
      tenant_id: tenantId,
    }),
  })
  if (!profileRes.ok) {
    console.error('register-customer: profile insert failed', await profileRes.text())
  }

  // ── Generate magic link so customer can browse immediately ───
  const linkRes = await fetch(`${SUPABASE_URL}/auth/v1/admin/generate_link`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${SUPABASE_SERVICE}`,
      'apikey':        SUPABASE_SERVICE,
      'Content-Type':  'application/json',
    },
    body: JSON.stringify({
      type:        'magiclink',
      email,
      redirect_to: `${APP_BASE_URL}/catalog.html`,
    }),
  })
  const linkData    = await linkRes.json()
  const hashedToken = linkData.hashed_token as string | undefined

  const magicUrl = hashedToken
    ? `${APP_INDEX_URL}?token_hash=${hashedToken}&type=magiclink`
    : `${APP_BASE_URL}/`

  if (!hashedToken) {
    console.warn('register-customer: magic link generation failed', JSON.stringify(linkData))
  }

  // ── Send branded "browse while we review" email ──────────────
  const mailRes = await fetch('https://api.mailersend.com/v1/email', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${MAILERSEND_API_KEY}`,
      'Content-Type':  'application/json',
    },
    body: JSON.stringify({
      from:    { email: 'noreply@mrcyberrick.us', name: "Ray & Judy's Book Stop" },
      to:      [{ email, name: fullName }],
      subject: "Ray & Judy's Book Stop — Your PULLLIST access is being set up",
      html:    buildPendingEmail(fullName, magicUrl),
    }),
  })

  if (!mailRes.ok) {
    const mailErr = await mailRes.json().catch(() => ({}))
    console.error('register-customer: MailerSend error', JSON.stringify(mailErr))
  }

  console.log(`register-customer: complete for ${email} (userId: ${userId})`)
  return Response.json({ success: true, user_id: userId }, { headers: corsHeaders })
}

// ── Turnstile server-side token verification (native path only) ───────────
async function verifyTurnstile(token: string, secretKey: string): Promise<boolean> {
  try {
    const res = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ secret: secretKey, response: token }),
    })
    const data = await res.json()
    if (!data?.success) {
      console.warn('register-customer: Turnstile verification failed', JSON.stringify(data))
    }
    return data?.success === true
  } catch (err) {
    console.error('register-customer: Turnstile verify request failed', String(err))
    return false
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const SUPABASE_URL        = Deno.env.get('SUPABASE_URL')!
    const SUPABASE_SERVICE    = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const MAILERSEND_API_KEY  = Deno.env.get('MAILERSEND_API_KEY')!
    const FOUNDING_TENANT_ID  = Deno.env.get('FOUNDING_TENANT_ID')
    const TURNSTILE_SECRET_KEY = Deno.env.get('TURNSTILE_SECRET_KEY')

    if (!FOUNDING_TENANT_ID) {
      console.warn('register-customer: FOUNDING_TENANT_ID secret not set')
    }

    const url    = new URL(req.url)
    const secret = url.searchParams.get('secret')

    // ════════════════════════════════════════════════════════════════════
    // Path 1 — MailerLite webhook (?secret=<tenant webhook secret>)
    // ════════════════════════════════════════════════════════════════════
    if (secret) {
      // ── Resolve tenant from per-tenant webhook secret ────────────
      // F34 residual (resolved 5.4 S2): the incoming `?secret=` both authenticates
      // the request and selects the tenant. A caller can only create a pending
      // customer in the tenant whose secret they hold — no cross-tenant injection.
      const tenantLookupRes = await fetch(
        `${SUPABASE_URL}/rest/v1/tenants?settings->>mailerlite_webhook_secret=eq.${encodeURIComponent(secret)}&select=id,slug,display_name`,
        {
          headers: {
            'Authorization': `Bearer ${SUPABASE_SERVICE}`,
            'apikey':        SUPABASE_SERVICE,
            'Accept':        'application/json',
          },
        }
      )
      const matchedTenants = await tenantLookupRes.json()
      const tenantId = Array.isArray(matchedTenants) ? matchedTenants[0]?.id as string | undefined : undefined

      if (!tenantLookupRes.ok || !tenantId) {
        console.warn('register-customer: no tenant matched the provided webhook secret')
        return Response.json({ error: 'Unauthorized' }, { status: 401, headers: corsHeaders })
      }

      // ── Parse MailerLite webhook body ───────────────────────────
      let body: Record<string, unknown>
      try {
        body = await req.json()
      } catch {
        return Response.json({ error: 'Invalid JSON body' }, { status: 400, headers: corsHeaders })
      }

      // ── Group filter ────────────────────────────────────────────
      // Only process subscribers added to the PULLLIST onboarding group.
      // All other MailerLite groups (newsletters, other landing pages) are ignored.
      const REQUIRED_GROUP = 'Monthly Comics'

      // subscriber.added_to_group payload shape:
      //   body.data.subscriber  — the subscriber object
      //   body.data.group       — the group object { id, name, ... }
      const data      = body?.data as Record<string, unknown> | undefined
      const group     = data?.group as Record<string, unknown> | undefined
      const groupName = (group?.name as string | undefined)?.trim() || ''

      if (groupName && groupName !== REQUIRED_GROUP) {
        console.log(`register-customer: ignoring group "${groupName}" — not "${REQUIRED_GROUP}"`)
        return Response.json({ success: true, note: 'ignored_group' }, { headers: corsHeaders })
      }

      // ── Parse subscriber ─────────────────────────────────────
      const subscriber: Record<string, unknown> =
        data?.subscriber as Record<string, unknown>
        || body?.subscriber as Record<string, unknown>
        || body

      const email     = (subscriber?.email as string | undefined)?.trim()
      const fields     = subscriber?.fields as Record<string, unknown> | undefined
      const firstName  = ((fields?.name ?? subscriber?.name) as string | undefined)?.trim() || ''
      const lastName   = ((fields?.last_name ?? subscriber?.last_name) as string | undefined)?.trim() || ''
      const fullName   = [firstName, lastName].filter(Boolean).join(' ') || email?.split('@')[0] || 'Customer'

      if (!email || !email.includes('@')) {
        console.error('register-customer: no valid email in payload', JSON.stringify(body))
        return Response.json({ error: 'No valid email in payload' }, { status: 400, headers: corsHeaders })
      }

      console.log(`register-customer: processing ${fullName} <${email}> from group "${groupName}")`)

      return await provisionPendingCustomer({
        SUPABASE_URL, SUPABASE_SERVICE, MAILERSEND_API_KEY,
        tenantId, fullName, email,
      })
    }

    // ════════════════════════════════════════════════════════════════════
    // Path 2 — Native direct-POST signup (no ?secret=)
    // { email, name, slug, turnstileToken, honeypot }
    // ════════════════════════════════════════════════════════════════════
    let nativeBody: Record<string, unknown>
    try {
      nativeBody = await req.json()
    } catch {
      return Response.json({ error: 'Invalid request body' }, { status: 400, headers: corsHeaders })
    }

    const honeypot = (nativeBody.honeypot as string | undefined) || ''
    if (honeypot.trim() !== '') {
      // Bot filled the hidden field — silently absorb, no account, no email, no tell.
      console.log('register-customer: honeypot triggered, absorbing silently')
      return Response.json({ success: true }, { headers: corsHeaders })
    }

    const email = ((nativeBody.email as string | undefined) || '').trim()
    const name  = ((nativeBody.name  as string | undefined) || '').trim()
    const slug  = ((nativeBody.slug  as string | undefined) || '').trim()
    const turnstileToken = (nativeBody.turnstileToken as string | undefined) || ''

    if (!email || !email.includes('@') || !name || !slug) {
      return Response.json({ error: 'email, name, and slug are required' }, { status: 400, headers: corsHeaders })
    }

    if (!TURNSTILE_SECRET_KEY) {
      console.error('register-customer: TURNSTILE_SECRET_KEY secret not set — refusing native signup')
      return Response.json({ error: 'Signup is temporarily unavailable' }, { status: 503, headers: corsHeaders })
    }
    if (!turnstileToken) {
      return Response.json({ error: 'Verification required' }, { status: 400, headers: corsHeaders })
    }
    const turnstileOk = await verifyTurnstile(turnstileToken, TURNSTILE_SECRET_KEY)
    if (!turnstileOk) {
      return Response.json({ error: 'Verification failed, please try again' }, { status: 400, headers: corsHeaders })
    }

    // ── Resolve tenant from the posted slug (client already knows it, from the
    //    host, via TenantContext.current().slug — see native-customer-signup
    //    plan § the hard design question for the accepted low-severity posture
    //    of a caller posting a different tenant's slug). ──────────────────
    const tenantLookupRes = await fetch(
      `${SUPABASE_URL}/rest/v1/tenants?slug=eq.${encodeURIComponent(slug)}&select=id,slug,display_name`,
      {
        headers: {
          'Authorization': `Bearer ${SUPABASE_SERVICE}`,
          'apikey':        SUPABASE_SERVICE,
          'Accept':        'application/json',
        },
      }
    )
    const matchedTenants = await tenantLookupRes.json()
    const tenantId = Array.isArray(matchedTenants) ? matchedTenants[0]?.id as string | undefined : undefined

    if (!tenantLookupRes.ok || !tenantId) {
      console.warn('register-customer: native signup posted an unknown slug', slug)
      return Response.json({ error: 'Unknown shop' }, { status: 400, headers: corsHeaders })
    }

    console.log(`register-customer: native signup ${name} <${email}> for tenant slug "${slug}"`)

    return await provisionPendingCustomer({
      SUPABASE_URL, SUPABASE_SERVICE, MAILERSEND_API_KEY,
      tenantId, fullName: name, email,
    })

  } catch (err) {
    console.error('register-customer: unexpected error', String(err))
    return Response.json({ error: String(err) }, { status: 500, headers: corsHeaders })
  }
})

// ── Email template ────────────────────────────────────────────────────────────
function buildPendingEmail(name: string, magicUrl: string): string {
  return `
<div style="font-family:Arial,sans-serif;max-width:520px;margin:0 auto;background:#1a1a1a;color:#f0f0f0;border-radius:8px;overflow:hidden">
  <div style="background:#111;padding:24px 32px;border-bottom:3px solid #e63946">
    <div style="font-size:1.6rem;font-weight:900;letter-spacing:0.08em">PULL<span style="color:#e63946">LIST</span></div>
    <div style="font-size:0.75rem;color:#888;margin-top:2px">Ray &amp; Judy's Book Stop &mdash; Monthly Comics Pre-Order System</div>
  </div>
  <div style="padding:32px">
    <h2 style="margin:0 0 16px;font-size:1.1rem;color:#fff">Hi ${name} — we received your request</h2>
    <p style="color:#ccc;line-height:1.7;margin:0 0 16px">
      Thanks for signing up for the PULLLIST pre-order system at Ray &amp; Judy's Book Stop.
      Your account has been created and is being reviewed.
    </p>
    <p style="color:#ccc;line-height:1.7;margin:0 0 24px">
      In the meantime, click below to browse the upcoming catalog. Once your account is
      approved, you'll be able to reserve titles for your pull list each month.
    </p>
    <a href="${magicUrl}"
       style="display:inline-block;background:#e63946;color:white;padding:13px 28px;
              border-radius:4px;text-decoration:none;font-weight:700;font-size:0.9rem;
              letter-spacing:0.03em">
      Browse the Catalog &rarr;
    </a>
    <div style="margin-top:24px;background:rgba(255,255,255,0.04);
                border-left:3px solid rgba(232,57,70,0.4);padding:12px 16px;
                border-radius:0 4px 4px 0">
      <div style="font-size:0.78rem;color:#aaa;line-height:1.8">
        &#10003;&nbsp; Reservations will be available once your account is confirmed<br>
        &#10003;&nbsp; This link is for your use only &mdash; do not share it<br>
        &#10003;&nbsp; Link expires after use &mdash; use Forgot Password on the login page for a new one<br>
        &#10003;&nbsp; Questions? Call us at (973) 586-9182
      </div>
    </div>
    <p style="margin-top:24px;font-size:0.78rem;color:#666;line-height:1.6">
      Ray &amp; Judy's Book Stop &middot; 40 W Main St. Rockaway, NJ 07866 &middot; (973) 586-9182
    </p>
  </div>
  <div style="background:#111;padding:16px 32px;font-size:0.72rem;color:#555;border-top:1px solid #222">
    Ray &amp; Judy's Book Stop &middot; Sent via the PullList pre-order system
  </div>
</div>`
}
