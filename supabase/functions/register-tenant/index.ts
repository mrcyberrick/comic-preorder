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
 *     location?, branding? }
 *
 * Required env vars (set in Supabase → Edge Functions → Secrets):
 *   SUPABASE_URL
 *   SUPABASE_SERVICE_ROLE_KEY
 *   TENANT_PROVISION_SECRET   ← operator gate; never shared with tenant admins
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
 */

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
        plan:     'free',
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
    return Response.json(
      { tenant_id: tenantId, admin_user_id: adminUserId, slug, webhook_secret: webhookSecret },
      { headers: corsHeaders }
    )

  } catch (err) {
    console.error('register-tenant: unexpected error', String(err))
    await compensate()
    return Response.json({ error: String(err) }, { status: 500, headers: corsHeaders })
  }
})
