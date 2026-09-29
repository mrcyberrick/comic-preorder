/**
 * register-customer — Public Edge Function
 *
 * ONE entry path: native direct-POST signup, called by the app's own "Create account" UI on a
 * tenant's branded login (native-customer-signup, S2/S3). Body:
 *   { email, name, slug, turnstileToken, honeypot }
 * Tenant is resolved from the posted `slug` (the client knows it via TenantContext.current().slug,
 * resolved unauthenticated from the host). A caller can post any slug; worst case is a pending row
 * in the wrong tenant, which that tenant's admin declines — the approval state machine is the real
 * access gate, not signup itself. Abuse gate: honeypot (silent no-op) + Cloudflare Turnstile
 * (server-verified) + the existing already_exists dedup below.
 *
 * MailerLite webhook path REMOVED 2026-08-30 (native-customer-signup § S5, Rick's decision
 * 2026-08-29: remove entirely rather than leave present-but-dead). It accepted
 * `?secret=<tenant's webhook secret>`, resolved the tenant by looking that secret up against
 * tenants.settings->>'mailerlite_webhook_secret', and parsed a MailerLite subscriber payload.
 * Removal is PLATFORM-WIDE, not founding-only — the mechanism was per-tenant, so no tenant can use
 * it now. `?secret=` is simply ignored today: a request carrying it falls through to the native
 * path and is judged on its JSON body like any other.
 * Two consequences worth knowing before reinstating anything:
 *   - `tenants.settings->>'mailerlite_webhook_secret'` is now DEAD CONFIG. Nothing reads it.
 *   - Recovering the path means git history (this file, pre-2026-08-30), not a feature flag.
 *
 * Required env vars (set in Supabase → Edge Functions → Secrets):
 *   SUPABASE_URL
 *   SUPABASE_SERVICE_ROLE_KEY
 *   RESEND_API_KEY              ← F99 migration: replaced the old MailerSend key, 2026-09-02
 *   FOUNDING_TENANT_ID          ← retained for diagnostics; not the tenant source (see F34 note)
 *   TURNSTILE_SECRET_KEY        ← server-side Turnstile token verification
 *
 * F34 note (resolved 5.4 S2, 2026-06-16): this function is no longer pinned to the founding
 * tenant. With the webhook path gone, the sole tenant source is the posted `slug`.
 *
 * F72 S2 (free-tier slice, 2026-09-03): email branding is now tenant-aware. Every tenant's own
 * `display_name` appears in the from-name, subject and greeting (both tiers — this was hardcoded
 * to the founding tenant for every signup before this change, which was F72's actual defect).
 * `plan = 'pro'` additionally shows phone/address in the footer; free tier omits it. The founding
 * tenant's own email renders byte-identically to before this change (its display_name equals the
 * former hardcoded literal exactly). Remaining, deliberately NOT done here: the other five mail
 * functions, and the tier-gated "View Online" link (new scope per the plan's § 0.1) — F72 remains
 * open for those.
 */

const APP_BASE_URL  = Deno.env.get('APP_BASE_URL') ?? 'https://pulllist.app'
const APP_INDEX_URL = `${APP_BASE_URL}/index.html`

const MAIL_FROM_EMAIL = Deno.env.get('MAIL_FROM_EMAIL') ?? 'noreply@mrcyberrick.us'
const MAIL_FROM_NAME  = Deno.env.get('MAIL_FROM_NAME')  ?? "Ray & Judy's Book Stop"

// F72 S2 (free-tier slice): a tenant's display_name is admin-set, not
// user-submitted, but it is interpolated into HTML mail — escape it before
// use, same as any DB-sourced string reaching an HTML template.
function escapeHtml(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
}

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

// ── Shared tail: create pending account, generate magic link, send email ────
async function provisionPendingCustomer(opts: {
  SUPABASE_URL: string
  SUPABASE_SERVICE: string
  RESEND_API_KEY: string
  tenantId: string
  fullName: string
  email: string
  storeName: string
  isPaid: boolean
}): Promise<Response> {
  const { SUPABASE_URL, SUPABASE_SERVICE, RESEND_API_KEY, tenantId, fullName, email, storeName, isPaid } = opts

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
  const mailRes = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${RESEND_API_KEY}`,
      'Content-Type':  'application/json',
    },
    body: JSON.stringify({
      from:    `${storeName} <${MAIL_FROM_EMAIL}>`,
      to:      email,
      subject: `${storeName} — Your PULLLIST access is being set up`,
      html:    buildPendingEmail(fullName, magicUrl, storeName, isPaid),
    }),
  })

  if (!mailRes.ok) {
    const mailErr = await mailRes.json().catch(() => ({}))
    console.error('register-customer: Resend error', JSON.stringify(mailErr))
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
    const RESEND_API_KEY      = Deno.env.get('RESEND_API_KEY')!
    const FOUNDING_TENANT_ID  = Deno.env.get('FOUNDING_TENANT_ID')
    const TURNSTILE_SECRET_KEY = Deno.env.get('TURNSTILE_SECRET_KEY')

    if (!FOUNDING_TENANT_ID) {
      console.warn('register-customer: FOUNDING_TENANT_ID secret not set')
    }

    // The MailerLite webhook path (`?secret=`) was removed 2026-08-30 — see the header.
    // A stray `?secret=` on the URL is now inert: the request falls through to the
    // native path below and is judged on its JSON body like any other.

    // ════════════════════════════════════════════════════════════════════
    // Native direct-POST signup
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
      `${SUPABASE_URL}/rest/v1/tenants?slug=eq.${encodeURIComponent(slug)}&select=id,slug,display_name,plan`,
      {
        headers: {
          'Authorization': `Bearer ${SUPABASE_SERVICE}`,
          'apikey':        SUPABASE_SERVICE,
          'Accept':        'application/json',
        },
      }
    )
    const matchedTenants = await tenantLookupRes.json()
    const matchedTenant  = Array.isArray(matchedTenants) ? matchedTenants[0] : undefined
    const tenantId       = matchedTenant?.id as string | undefined

    if (!tenantLookupRes.ok || !tenantId) {
      console.warn('register-customer: native signup posted an unknown slug', slug)
      return Response.json({ error: 'Unknown shop' }, { status: 400, headers: corsHeaders })
    }

    // F72 S2 (free-tier slice): tenant identity for the confirmation email.
    // isPaid gates ONLY the phone/address footer content (§ 0.1 Q8) — the
    // tenant's own name is shown to BOTH tiers, in subject/greeting/from, as
    // it always should have been (this was hardcoded to the founding tenant
    // for every signup until this change, which is F72's actual defect).
    const storeName = (matchedTenant?.display_name as string | undefined) || MAIL_FROM_NAME
    const isPaid    = matchedTenant?.plan === 'pro'

    console.log(`register-customer: native signup ${name} <${email}> for tenant slug "${slug}"`)

    return await provisionPendingCustomer({
      SUPABASE_URL, SUPABASE_SERVICE, RESEND_API_KEY,
      tenantId, fullName: name, email, storeName, isPaid,
    })

  } catch (err) {
    console.error('register-customer: unexpected error', String(err))
    return Response.json({ error: String(err) }, { status: 500, headers: corsHeaders })
  }
})

// ── Email template ────────────────────────────────────────────────────────────
// F72 S2 (free-tier slice, 2026-09-03): storeName/isPaid parameterize what was
// unconditionally the founding tenant's identity. isPaid gates ONLY the
// phone/address content (§ 0.1 Q8) — storeName (the tenant's OWN name) shows
// to every tenant, both tiers, which is what should have been true all along;
// this was hardcoded to "Ray & Judy's Book Stop" for every signup regardless
// of tenant until this change. For the founding (paid) tenant storeName
// equals that exact literal, so its rendered email is byte-identical to
// before this change — verified live (V4).
function buildPendingEmail(name: string, magicUrl: string, storeName: string, isPaid: boolean): string {
  const safeStore = escapeHtml(storeName)
  const phoneBullet = isPaid
    ? '<br>\n        &#10003;&nbsp; Questions? Call us at (973) 586-9182'
    : ''
  const contactParagraph = isPaid
    ? `    <p style="margin-top:24px;font-size:0.78rem;color:#666;line-height:1.6">
      ${safeStore} &middot; 40 W Main St. Rockaway, NJ 07866 &middot; (973) 586-9182
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
    <h2 style="margin:0 0 16px;font-size:1.1rem;color:#fff">Hi ${name} — we received your request</h2>
    <p style="color:#ccc;line-height:1.7;margin:0 0 16px">
      Thanks for signing up for the PULLLIST pre-order system at ${safeStore}.
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
        &#10003;&nbsp; Link expires after use &mdash; use Forgot Password on the login page for a new one${phoneBullet}
      </div>
    </div>
${contactParagraph}  </div>
  <div style="background:#111;padding:16px 32px;font-size:0.72rem;color:#555;border-top:1px solid #222">
    ${safeStore} &middot; Sent via the PullList pre-order system
  </div>
</div>`
}
