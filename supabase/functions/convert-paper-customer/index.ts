/**
 * convert-paper-customer — admin-only Edge Function (customer engagement S1,
 * docs/customer-engagement-paper-to-app.md)
 *
 * Turns a PAPER customer (an admin-managed account with a made-up address
 * @paper.pulllist.local) into a normal app customer IN PLACE, then emails them a
 * link to set a password and sign in. Nothing moves between accounts: the same
 * auth user and profile row keep their reservations, subscriptions and history,
 * so F13 (history lost when an account is deleted) and F181 (claim-paper-customer
 * never checks the shop) do not apply to this path.
 *
 * Two modes, one endpoint:
 *   convert  { paper_user_id, email, phone? }
 *   resend   { resend: true, user_id }       the link again, for an account this
 *                                            function already converted
 *
 * Auth: in-body, as create-paper-customer does. The caller's own token is checked
 * against /auth/v1/user, then their profile must be an admin. Deployed with
 * --no-verify-jwt (a brand-new function, so there is no live setting to preserve;
 * F93 asks that the flag be stated explicitly). Unlike create-paper-customer there
 * is NO fallback to FOUNDING_TENANT_ID: an admin whose profile has no tenant is
 * refused, because a fallback here would let the shop check below pass against
 * the wrong shop.
 *
 * What the live staging probe showed about GoTrue (plan section 6, 2026-11-13):
 *   - admin update-user with { email, email_confirm: true } keeps the user id.
 *   - A taken address is HTTP 500 with Postgres code 23505 (users_email_partial_key),
 *     NOT a 4xx and NOT error_code email_exists; the refused change leaves the user
 *     untouched. This file recognises that shape itself.
 *   - generate_link type 'recovery' works for the new address (F153); 'invite' would
 *     fail email_exists, and 'magiclink' would CREATE a user for an unknown address.
 *   - user_profiles.email does not follow the auth email (F25), so it is written here.
 *
 * Required env vars: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY,
 *   RESEND_API_KEY, MAIL_FROM_EMAIL, APP_BASE_URL (optional; defaults to
 *   https://pulllist.app).
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

const PAPER_DOMAIN = '@paper.pulllist.local'
const UUID_RE  = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
// Deliberately narrow: no '*' (PostgREST turns it into a LIKE wildcard), no
// commas, spaces or brackets. Characters a real address may carry that this
// refuses are rare enough that the admin can pick another address.
const EMAIL_RE = /^[A-Za-z0-9._%+'-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/

// LIKE metacharacters in a typed address must match themselves ('_' and '%').
function likeEscape(s: string): string {
  return s.replace(/[\\%_]/g, (c) => '\\' + c)
}

function json(body: unknown, status = 200): Response {
  return Response.json(body, { status, headers: corsHeaders })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const SUPABASE_URL     = Deno.env.get('SUPABASE_URL')
    const SUPABASE_ANON    = Deno.env.get('SUPABASE_ANON_KEY')
    const SUPABASE_SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    const RESEND_API_KEY   = Deno.env.get('RESEND_API_KEY')

    if (!SUPABASE_URL || !SUPABASE_ANON || !SUPABASE_SERVICE) {
      console.error('convert-paper-customer: missing SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY')
      return json({ error: 'Server is not configured' }, 500)
    }
    const svc = {
      Authorization:  `Bearer ${SUPABASE_SERVICE}`,
      apikey:         SUPABASE_SERVICE,
      'Content-Type': 'application/json',
    }

    // ── Who is calling? An admin, with a shop ────────────────
    const authHeader = req.headers.get('Authorization') || ''
    const userRes = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
      headers: { Authorization: authHeader, apikey: SUPABASE_ANON },
    })
    const userData = await userRes.json().catch(() => ({}))
    if (!userRes.ok || !userData.id) return json({ error: 'Unauthorized' }, 401)

    const profileRes = await fetch(
      `${SUPABASE_URL}/rest/v1/user_profiles?id=eq.${encodeURIComponent(userData.id)}&select=is_admin,tenant_id`,
      { headers: { Authorization: authHeader, apikey: SUPABASE_ANON, Accept: 'application/json' } },
    )
    const profiles = await profileRes.json().catch(() => null)
    if (!Array.isArray(profiles) || !profiles[0]?.is_admin) return json({ error: 'Forbidden — admin only' }, 403)

    const callerTenantId: string | undefined = profiles[0].tenant_id
    if (!callerTenantId) return json({ error: 'Forbidden — no shop on this admin profile' }, 403)
    const actorId: string = userData.id

    // ── Body ─────────────────────────────────────────────────
    let body: Record<string, unknown>
    try {
      body = await req.json()
    } catch {
      return json({ error: 'Invalid request body' }, 400)
    }
    const isResend = body.resend === true

    // ── RESEND: the link again, for an account this function converted ──
    if (isResend) {
      const userId = typeof body.user_id === 'string' ? body.user_id.trim() : ''
      if (!UUID_RE.test(userId)) return json({ error: 'user_id is required' }, 400)

      // Same shop, no longer paper, and carrying the conversion stamp. Anything
      // else (another shop's customer, an ordinary sign-up) is a 404.
      const rows = await readProfiles(SUPABASE_URL, svc,
        `id=eq.${userId}&tenant_id=eq.${callerTenantId}&is_paper=eq.false&converted_from_paper_at=not.is.null`,
        'id,full_name,email')
      const prof = rows?.[0]
      if (!prof) return json({ error: 'Converted customer not found' }, 404)

      const sent = await linkAndSend(SUPABASE_URL, svc, RESEND_API_KEY, callerTenantId, prof.email, prof.full_name)
      if (sent) await logEvents(SUPABASE_URL, svc, [
        eventRow('invite_sent', actorId, callerTenantId, { target_user_id: userId, via: 'resend' }),
      ])
      return json({ success: true, user_id: userId, invite_sent: sent })
    }

    // ── CONVERT ──────────────────────────────────────────────
    const paperId = typeof body.paper_user_id === 'string' ? body.paper_user_id.trim() : ''
    const email   = typeof body.email === 'string' ? body.email.trim() : ''
    const phone   = typeof body.phone === 'string' ? body.phone.trim() : ''

    if (!UUID_RE.test(paperId)) return json({ error: 'paper_user_id is required' }, 400)
    if (!email || email.length > 254 || !EMAIL_RE.test(email)) return json({ error: 'A valid email address is required' }, 400)
    if (email.toLowerCase().endsWith(PAPER_DOMAIN)) return json({ error: 'Enter the customer\'s real email address' }, 400)
    if (phone.length > 40) return json({ error: 'Phone is too long (40 characters)' }, 400)

    // The paper profile, read WITH the caller's shop and is_paper = true: a
    // customer of another shop, an app customer, or an unknown id all read the same.
    const paperRows = await readProfiles(SUPABASE_URL, svc,
      `id=eq.${paperId}&tenant_id=eq.${callerTenantId}&is_paper=eq.true`,
      'id,full_name,email,phone,status')
    const paper = paperRows?.[0]
    if (!paper) return json({ error: 'Paper customer not found' }, 404)

    // Is the address already an account? Looked up on the profile copy first so the
    // page can offer Claim for a same-shop account (D2). An account in another shop
    // is answered with a bare 409: it must not reveal who that customer is.
    const dupRows = await readProfiles(SUPABASE_URL, svc,
      `email=ilike.${encodeURIComponent(likeEscape(email))}&id=neq.${paperId}`,
      'id,full_name,tenant_id', 10)
    if (dupRows && dupRows.length) {
      const mine = dupRows.find((r: { tenant_id: string }) => r.tenant_id === callerTenantId)
      return mine
        ? json({ error: 'email_in_use', same_shop: true, existing: { id: mine.id, full_name: mine.full_name } }, 409)
        : json({ error: 'email_in_use', same_shop: false }, 409)
    }

    // Step 1: the sign-in address. The live probe showed a refused change leaves
    // the auth user untouched, so doing this first is safe.
    const updRes = await fetch(`${SUPABASE_URL}/auth/v1/admin/users/${paperId}`, {
      method: 'PUT',
      headers: svc,
      body: JSON.stringify({ email, email_confirm: true }),
    })
    if (!updRes.ok) {
      const e = await updRes.json().catch(() => ({}))
      if (isEmailTaken(e)) return json({ error: 'email_in_use', same_shop: false }, 409)
      console.error('convert-paper-customer: auth email update failed', updRes.status, JSON.stringify({ code: e.code, error_code: e.error_code }))
      return json({ error: 'Could not change the sign-in email' }, 500)
    }

    // Step 2: the profile. If it fails, put the auth email back, or the account
    // would sign in as the new address while still looking like paper.
    const patch: Record<string, unknown> = {
      email,
      is_paper: false,
      converted_from_paper_at: new Date().toISOString(),
    }
    if (phone) patch.phone = phone
    const patchRes = await fetch(
      `${SUPABASE_URL}/rest/v1/user_profiles?id=eq.${paperId}&tenant_id=eq.${callerTenantId}&is_paper=eq.true`,
      { method: 'PATCH', headers: { ...svc, Prefer: 'return=representation' }, body: JSON.stringify(patch) },
    )
    const patched = patchRes.ok ? await patchRes.json().catch(() => null) : null
    if (!Array.isArray(patched) || patched.length !== 1) {
      console.error('convert-paper-customer: profile update failed', patchRes.status, '- restoring the auth email')
      const back = await fetch(`${SUPABASE_URL}/auth/v1/admin/users/${paperId}`, {
        method: 'PUT',
        headers: svc,
        body: JSON.stringify({ email: paper.email, email_confirm: true }),
      })
      if (!back.ok) console.error('convert-paper-customer: COULD NOT restore the auth email for', paperId)
      return json({ error: 'Could not update the customer profile' }, 500)
    }

    // The account is converted from here on. Everything below can fail without
    // undoing it; the response says whether the email went (invite_sent).
    const [reservations, subscriptions] = await Promise.all([
      countRows(SUPABASE_URL, svc, `preorders?user_id=eq.${paperId}&fulfilled=eq.false`),
      countRows(SUPABASE_URL, svc, `subscriptions?user_id=eq.${paperId}`),
    ])
    const sent = await linkAndSend(SUPABASE_URL, svc, RESEND_API_KEY, callerTenantId, email, paper.full_name,
      { reservations, subscriptions })

    // Events are attributed to the ADMIN who acted, with the customer in
    // metadata. Attributed to the customer they would count as the customer's
    // own activity: Analytics tallies every non-promo event per user, and
    // Accounts' "Last seen" takes the newest event, so a just-invited customer
    // would read as active today.
    const events = [eventRow('paper_converted', actorId, callerTenantId, { target_user_id: paperId, via: 'admin' })]
    if (sent) events.push(eventRow('invite_sent', actorId, callerTenantId, { target_user_id: paperId, via: 'convert' }))
    await logEvents(SUPABASE_URL, svc, events)

    return json({ success: true, user_id: paperId, email, invite_sent: sent })

  } catch (err) {
    console.error('convert-paper-customer: unexpected error', String(err))
    return json({ error: String(err) }, 500)
  }
})

// ── Helpers ───────────────────────────────────────────────────────────────────

type Hdrs = Record<string, string>

// GoTrue answers a taken address with HTTP 500 and the raw Postgres code.
function isEmailTaken(e: Record<string, unknown>): boolean {
  const text = `${e.code ?? ''} ${e.error_code ?? ''} ${e.message ?? ''} ${e.msg ?? ''}`.toLowerCase()
  return String(e.code) === '23505'
    || e.error_code === 'email_exists'
    || text.includes('users_email_partial_key')
    || text.includes('duplicate')
    || text.includes('already')
}

async function readProfiles(supabaseUrl: string, svc: Hdrs, filter: string, select: string, limit = 1) {
  try {
    const res = await fetch(`${supabaseUrl}/rest/v1/user_profiles?${filter}&select=${select}&limit=${limit}`, { headers: svc })
    if (!res.ok) return null
    const rows = await res.json()
    return Array.isArray(rows) ? rows : null
  } catch {
    return null
  }
}

// Row count through PostgREST's content-range, with limit=1 (a Range header on an
// empty result can answer 416). null = could not be read; the email then says nothing.
async function countRows(supabaseUrl: string, svc: Hdrs, path: string): Promise<number | null> {
  try {
    const res = await fetch(`${supabaseUrl}/rest/v1/${path}&select=id&limit=1`, { headers: { ...svc, Prefer: 'count=exact' } })
    if (!res.ok) return null
    const m = (res.headers.get('content-range') || '').match(/\/(\d+)$/)
    return m ? parseInt(m[1], 10) : null
  } catch {
    return null
  }
}

function eventRow(event_type: string, user_id: string, tenant_id: string, metadata: Record<string, unknown>) {
  return { event_type, user_id, tenant_id, metadata }
}

// Non-fatal: the stamp on the profile is the durable record of a conversion;
// events are the audit trail.
async function logEvents(supabaseUrl: string, svc: Hdrs, rows: unknown[]) {
  try {
    const res = await fetch(`${supabaseUrl}/rest/v1/usage_events`, {
      method: 'POST',
      headers: { ...svc, Prefer: 'return=minimal' },
      body: JSON.stringify(rows),
    })
    if (!res.ok) console.error('convert-paper-customer: usage_events insert failed', res.status)
  } catch (err) {
    console.error('convert-paper-customer: usage_events insert threw', String(err))
  }
}

// generate_link 'recovery' (never 'invite' or 'magiclink', see the header), then
// the email through Resend. Returns whether the email was accepted. Nothing that
// carries the link is ever logged.
async function linkAndSend(
  supabaseUrl: string,
  svc: Hdrs,
  resendKey: string | undefined,
  tenantId: string,
  email: string,
  name: string,
  counts: { reservations: number | null; subscriptions: number | null } = { reservations: null, subscriptions: null },
): Promise<boolean> {
  try {
    const genRes = await fetch(`${supabaseUrl}/auth/v1/admin/generate_link`, {
      method: 'POST',
      headers: svc,
      body: JSON.stringify({ type: 'recovery', email, redirect_to: APP_INDEX_URL }),
    })
    const gen = await genRes.json().catch(() => ({}))
    const actionUrl = gen.action_link as string | undefined
    if (!genRes.ok || !actionUrl) {
      console.error('convert-paper-customer: could not generate a sign-in link', genRes.status)
      return false
    }
    if (!resendKey) {
      console.error('convert-paper-customer: RESEND_API_KEY not set, cannot send')
      return false
    }

    const tenant = await fetchTenantIdentity(supabaseUrl, svc.apikey, tenantId)
    const mailRes = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${resendKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from:    `${mailFromName(tenant)} <${MAIL_FROM_EMAIL}>`,
        to:      email,
        subject: `${tenant.storeName} — Your pull list is online`,
        html:    buildConvertEmail(name, actionUrl, tenant, counts),
      }),
    })
    if (!mailRes.ok) {
      const mailErr = await mailRes.json().catch(() => ({}))
      console.error('convert-paper-customer: Resend error', mailRes.status, JSON.stringify(mailErr))
      return false
    }
    return true
  } catch (err) {
    console.error('convert-paper-customer: link or send threw', String(err))
    return false
  }
}

// ── Email template ────────────────────────────────────────────────────────────
// The invite-customer layout, reworded for someone whose list already exists.
// The shop's own name everywhere (escaped); the address and phone paragraph only
// for plan = 'pro', exactly as in the other mail functions.
function plural(n: number, one: string, many: string): string {
  return `${n} ${n === 1 ? one : many}`
}

function waitingLine(c: { reservations: number | null; subscriptions: number | null }): string {
  const r = c.reservations ?? 0
  const s = c.subscriptions ?? 0
  if (r > 0 && s > 0) return `${plural(r, 'reservation is', 'reservations are')} and ${plural(s, 'subscription is', 'subscriptions are')} already waiting for you.`
  if (r > 0) return `${plural(r, 'reservation is', 'reservations are')} already waiting for you.`
  if (s > 0) return `${plural(s, 'subscription is', 'subscriptions are')} already waiting for you.`
  return 'Your pull list is now online.'
}

function buildConvertEmail(
  name: string,
  actionUrl: string,
  tenant: TenantIdentity,
  counts: { reservations: number | null; subscriptions: number | null },
): string {
  const safeStore = escapeHtml(tenant.storeName)
  const safeName  = escapeHtml(name)
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
    <h2 style="margin:0 0 16px;font-size:1.1rem;color:#fff">Hi ${safeName} — your pull list is online!</h2>
    <p style="color:#ccc;line-height:1.7;margin:0 0 16px">
      ${safeStore} has set up online access to the pull list we already keep for you. ${waitingLine(counts)}
    </p>
    <p style="color:#ccc;line-height:1.7;margin:0 0 24px">
      Click below to set a password and sign in. After that you can see your list, reserve new titles
      and check what is arriving, any time.
    </p>
    <a href="${actionUrl}"
       style="display:inline-block;background:#e63946;color:white;padding:13px 28px;
              border-radius:4px;text-decoration:none;font-weight:700;font-size:0.9rem;
              letter-spacing:0.03em">
      Open My Pull List &rarr;
    </a>
    <div style="margin-top:24px;background:rgba(255,255,255,0.04);
                border-left:3px solid rgba(232,57,70,0.4);padding:12px 16px;
                border-radius:0 4px 4px 0">
      <div style="font-size:0.78rem;color:#aaa;line-height:1.8">
        &#10003;&nbsp; Your reservations and subscriptions are already in your account<br>
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
