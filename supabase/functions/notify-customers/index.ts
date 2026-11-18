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

const APP_BASE_URL = Deno.env.get('APP_BASE_URL') ?? 'https://pulllist.app'

// ── Top Picks S5: opt-out links and promotional picks ────────────────────────
// A shorter secret means no links and no picks, never a weaker token: the email then goes out
// exactly as it did before S5 (no picks, no settings link, no List-Unsubscribe header). Picks are
// promotional, so they are never sent without the opt-out they point to.
const PREFS_SECRET   = Deno.env.get('EMAIL_PREFS_SECRET') ?? ''
const PREFS_LINKS_OK = PREFS_SECRET.length >= 32

// ── email-preferences token block — BEGIN ────────────────────────────────────
// notify-customers and notify-arrivals (S5) mint links with the SAME block; keep the copies
// byte-identical and gate on it (docs/top-picks-emails-and-notification-settings.md § 3.4).
// Token = lowercase hex of HMAC-SHA256(secret, "v1|" + lowercase user id). Verification is
// constant-time (crypto.subtle.verify), and a malformed token is refused before any crypto.
const PREFS_UUID_RE  = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
const PREFS_TOKEN_RE = /^[0-9a-f]{64}$/

async function prefsKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey('raw', new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign', 'verify'])
}

async function mintPrefsToken(secret: string, userId: string): Promise<string> {
  const sig = await crypto.subtle.sign('HMAC', await prefsKey(secret),
    new TextEncoder().encode('v1|' + userId.toLowerCase()))
  return [...new Uint8Array(sig)].map(b => b.toString(16).padStart(2, '0')).join('')
}

async function verifyPrefsToken(secret: string, userId: string, token: string): Promise<boolean> {
  if (!PREFS_UUID_RE.test(userId) || !PREFS_TOKEN_RE.test(token)) return false
  const bytes = new Uint8Array(32)
  for (let i = 0; i < 32; i++) bytes[i] = parseInt(token.slice(i * 2, i * 2 + 2), 16)
  return crypto.subtle.verify('HMAC', await prefsKey(secret), bytes,
    new TextEncoder().encode('v1|' + userId))
}
// ── email-preferences token block — END ──────────────────────────────────────

// The page link goes in the footer; the function address goes in List-Unsubscribe (RFC 8058: a
// mail client POSTs "List-Unsubscribe=One-Click" to it, and a browser that follows it is redirected
// to the page). Both carry the same signed token, which authorizes this customer's three email
// switches and nothing else.
async function prefsLinksFor(supabaseUrl: string, userId: string): Promise<{ page: string; unsubscribe: string }> {
  const s = await mintPrefsToken(PREFS_SECRET, userId)
  return {
    page: `${APP_BASE_URL}/email-preferences.html?u=${userId}&s=${s}`,
    unsubscribe: `${supabaseUrl}/functions/v1/email-preferences?u=${userId}&s=${s}&k=catalog`,
  }
}

// ── Top picks email block — BEGIN ────────────────────────────────────────────
// Byte-identical in notify-customers and notify-arrivals; a grep gate checks the two copies
// match (Top Picks plan S5, docs/top-picks-emails-and-notification-settings.md § 3.5). The pick
// RULE lives in the database (get_top_picks); this block only fetches the rows and renders them.
// Every failure here means "no picks": an email's own purpose never depends on this block.
const PICKS_LIMIT = 4
const PICKS_UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

type EmailPick = {
  id: string; tier: string; title: string; series_name: string | null
  publisher: string | null; cover_url: string | null; price_usd: number | string | null
}

// escapeHtml leaves quotes alone, which is fine between tags and wrong inside an attribute.
function escapeAttr(s: string): string {
  return escapeHtml(s).replace(/"/g, '&quot;').replace(/'/g, '&#39;')
}

// An address from the database for an <img src>: http(s) only, safe inside a quoted attribute.
function safeHttpUrl(u: unknown): string {
  if (typeof u !== 'string') return ''
  const t = u.trim()
  return /^https?:\/\/[^\s"'<>]+$/i.test(t) ? escapeAttr(t) : ''
}

function formatPrice(p: unknown): string {
  const n = typeof p === 'number' ? p : (typeof p === 'string' && p.trim() !== '' ? Number(p) : NaN)
  return Number.isFinite(n) && n > 0 ? '$' + n.toFixed(2) : ''
}

async function fetchPicks(supabaseUrl: string, serviceKey: string, userId: string): Promise<EmailPick[]> {
  try {
    const h = { Authorization: `Bearer ${serviceKey}`, apikey: serviceKey, 'Content-Type': 'application/json', Accept: 'application/json' }
    const res = await fetch(`${supabaseUrl}/rest/v1/rpc/get_top_picks`, {
      method: 'POST', headers: h, body: JSON.stringify({ p_user_id: userId, p_limit: PICKS_LIMIT }),
    })
    if (!res.ok) return []
    const ranked = await res.json()
    if (!Array.isArray(ranked)) return []
    const top = ranked
      .filter((r: { pick_id?: unknown }) => typeof r.pick_id === 'string' && PICKS_UUID_RE.test(r.pick_id))
      .sort((a: { pick_rank: number }, b: { pick_rank: number }) => a.pick_rank - b.pick_rank)
      .slice(0, PICKS_LIMIT)
    if (!top.length) return []
    const catRes = await fetch(
      `${supabaseUrl}/rest/v1/catalog?id=in.(${top.map((r: { pick_id: string }) => r.pick_id).join(',')})` +
        `&select=id,title,series_name,publisher,cover_url,price_usd`,
      { headers: h },
    )
    if (!catRes.ok) return []
    const rows = await catRes.json()
    if (!Array.isArray(rows)) return []
    const byId = new Map<string, Record<string, unknown>>(rows.map((r: { id: string }) => [r.id, r]))
    const picks: EmailPick[] = []
    for (const r of top) {
      const c = byId.get(r.pick_id)
      if (!c || typeof c.title !== 'string' || !c.title.trim()) continue
      picks.push({
        id: r.pick_id, tier: String(r.pick_tier ?? ''), title: c.title.trim(),
        series_name: (c.series_name as string | null) ?? null, publisher: (c.publisher as string | null) ?? null,
        cover_url: (c.cover_url as string | null) ?? null, price_usd: (c.price_usd as number | string | null) ?? null,
      })
    }
    return picks
  } catch (err) {
    console.warn('fetchPicks: failed for one customer, sending without picks', String(err))
    return []
  }
}

// The same wording as the catalog rail (catalog.html), so the email and the page describe picks alike.
function picksCaption(picks: EmailPick[]): string {
  const hasPersonal = picks.some(p => p.tier === 'personal')
  const hasPopular  = picks.some(p => p.tier === 'popular')
  const hasNew1     = picks.some(p => p.tier === 'new1')
  const history = hasPersonal && hasPopular ? 'Based on your reservations and the store\u2019s most popular reservations'
    : hasPersonal ? 'Based on your reservations'
    : hasPopular ? 'The store\u2019s most popular reservations' : ''
  return !hasNew1 ? history : history ? history + ', plus New #1s starting this month' : 'New #1 series starting this month'
}

// Table layout, inline styles: mail clients ignore most CSS. Many clients block remote images by
// default, so the title and price carry each card without the cover.
function buildPicksHtml(picks: EmailPick[], baseUrl: string, ref: string): string {
  if (!picks.length) return ''
  const rows = picks.map(p => {
    const link = escapeAttr(`${baseUrl}/catalog.html?pick=${encodeURIComponent(p.id)}&ref=${ref}`)
    const cover = safeHttpUrl(p.cover_url)
    const price = formatPrice(p.price_usd)
    const sub = [p.publisher ? escapeHtml(p.publisher) : '', price].filter(Boolean).join(' &middot; ')
    return `
      <tr style="border-top:1px solid #2e2e2e">
        ${cover ? `<td width="56" valign="top" style="padding:10px 12px 10px 0"><a href="${link}"><img src="${cover}" alt="${escapeAttr(p.title)}" width="56" style="display:block;width:56px;height:auto;border:0;border-radius:3px;background:#222"></a></td>` : `<td width="56" style="padding:10px 12px 10px 0">&nbsp;</td>`}
        <td width="100%" valign="top" style="padding:10px 0;font-size:0.84rem;color:#f0ece4">
          <div style="font-weight:600">${escapeHtml(p.title)}</div>
          ${sub ? `<div style="font-size:0.74rem;color:#9a9390;margin-top:2px">${sub}</div>` : ''}
        </td>
        <td valign="middle" align="right" style="padding:10px 0 10px 12px;white-space:nowrap">
          <a href="${link}" style="display:inline-block;background:#e63946;color:#fff;padding:7px 14px;border-radius:4px;text-decoration:none;font-weight:700;font-size:0.76rem">Reserve</a>
        </td>
      </tr>`
  }).join('')
  return `
    <div style="margin-top:28px;padding-top:18px;border-top:1px solid #2e2e2e">
      <div style="font-size:0.95rem;font-weight:700;color:#fff">Top picks for you</div>
      <div style="font-size:0.74rem;color:#9a9390;margin:2px 0 10px">${escapeHtml(picksCaption(picks))}</div>
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;font-family:Arial,sans-serif">${rows}
      </table>
    </div>`
}

// Runs fn over items, `size` at a time (the picks are read ahead of the send loop).
async function inBatches<T>(items: T[], size: number, fn: (item: T) => Promise<void>): Promise<void> {
  for (let i = 0; i < items.length; i += size) await Promise.all(items.slice(i, i + size).map(fn))
}
// ── Top picks email block — END ──────────────────────────────────────────────
function settingsLinkHtml(pageUrl: string): string {
  return '<br><a href="' + escapeAttr(pageUrl) + '" style="color:#888;text-decoration:underline">Email settings or unsubscribe</a>'
}

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  // Env vars hoisted to function scope so auth check can use them
  const SUPABASE_URL       = Deno.env.get('SUPABASE_URL')
  const SUPABASE_ANON      = Deno.env.get('SUPABASE_ANON_KEY')
  const SUPABASE_SERVICE   = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const RESEND_API_KEY     = Deno.env.get('RESEND_API_KEY')
  const FOUNDING_TENANT_ID = Deno.env.get('FOUNDING_TENANT_ID')

  // Caller authentication: this function triggers a customer-wide email blast,
  // so we verify the caller before doing anything. Platform JWT verification is
  // OFF for this function (Supabase's off-plus-in-body-auth pattern), so this
  // in-body check is the actual gate — and it must NOT trust an unverified
  // token's self-declared claims, because any crafted token reaches this code.
  const authHeader = req.headers.get('Authorization') || ''
  if (!authHeader) {
    return Response.json({ error: 'Missing Authorization header' }, { status: 401, headers: corsHeaders })
  }
  const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : authHeader

  // Resolve caller identity: service-role caller (import script) or admin user (UI).
  // Detect a service-role caller by PROVING the key, not decoding a claim: use it
  // against an admin-only endpoint — only a genuine service key (legacy JWT or the
  // new sb_secret_ secret key) gets 200; a user JWT or a forged role=service_role
  // token gets 401/403. Format-agnostic and spoof-proof. (Replaces an unsigned-JWT
  // role decode that a crafted token could satisfy and that also stopped recognizing
  // the post-F75 sb_secret_ key — see technical-reference.md § 13 F87.)
  const isServiceRole = await (async () => {
    try {
      const probe = await fetch(SUPABASE_URL + '/auth/v1/admin/users?page=1&per_page=1', {
        headers: { Authorization: `Bearer ${token}`, apikey: token }
      })
      return probe.status === 200
    } catch { return false }
  })()
  let callerTenantId: string

  if (isServiceRole) {
    // Service-role caller (e.g. import script) — scope to founding tenant.
    callerTenantId = FOUNDING_TENANT_ID || ''
  } else {
    // User JWT path — verify caller is an authenticated admin.
    const userRes = await fetch(SUPABASE_URL + '/auth/v1/user', {
      headers: { Authorization: authHeader, apikey: SUPABASE_ANON }
    })
    if (!userRes.ok) {
      return Response.json({ error: 'Invalid auth' }, { status: 401, headers: corsHeaders })
    }
    const userData = await userRes.json()

    const profileRes = await fetch(
      SUPABASE_URL + `/rest/v1/user_profiles?id=eq.${userData.id}&select=is_admin,tenant_id`,
      { headers: { Authorization: authHeader, apikey: SUPABASE_ANON, Accept: 'application/json' } }
    )
    const profileData = await profileRes.json()
    if (!Array.isArray(profileData) || profileData.length === 0 || !profileData[0].is_admin) {
      return Response.json({ error: 'Admin required' }, { status: 403, headers: corsHeaders })
    }
    callerTenantId = profileData[0].tenant_id || FOUNDING_TENANT_ID || ''
  }

  try {
    if (!FOUNDING_TENANT_ID) {
      console.warn('notify-customers: FOUNDING_TENANT_ID secret not set — tenant scoping disabled')
    }

    // Parse body — only catalog_month is needed now.
    // foc_date is no longer accepted; the deadline is read from app_settings instead.
    let catalog_month
    try {
      const body    = await req.json()
      catalog_month = body.catalog_month || ''
    } catch {
      return Response.json({ error: 'Invalid body' }, { status: 400, headers: corsHeaders })
    }

    const authHeaders = {
      Authorization: 'Bearer ' + SUPABASE_SERVICE,
      apikey: SUPABASE_SERVICE,
      Accept: 'application/json',
    }

    // Format month label e.g. "2026-04" -> "April 2026"
    const monthLabel = catalog_month
      ? new Date(catalog_month + '-01T12:00:00').toLocaleDateString('en-US', { month: 'long', year: 'numeric' })
      : 'this month'

    // Read the admin-set order deadline from app_settings.
    // This is the same value shown in the catalog banner — single source of truth.
    let deadlineLabel: string | null = null
    try {
      const tenantFilter = `&tenant_id=eq.${callerTenantId}`
      const settingsRes = await fetch(
        SUPABASE_URL + '/rest/v1/app_settings?key=eq.order_deadline&select=value&limit=1' + tenantFilter,
        { headers: authHeaders }
      )
      const settings = await settingsRes.json()
      const rawDeadline = settings?.[0]?.value || ''
      if (rawDeadline) {
        // Parse as local date — split to avoid any UTC offset shifting the day
        const [y, m, d] = rawDeadline.split('-').map(Number)
        deadlineLabel = new Date(y, m - 1, d)
          .toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' })
      }
    } catch (e) {
      console.warn('Could not read order_deadline from app_settings:', String(e))
      // Non-fatal — email sends without a deadline line
    }

    // F72 G-F: the shop's own identity. This is the one promotional email, so
    // its footer must carry a postal address on BOTH tiers (decision Q13):
    // plan = 'pro' keeps today's footer; a free shop shows its own
    // tenants.location, and with no location on file nothing is sent.
    const tenant    = await fetchTenantIdentity(SUPABASE_URL, SUPABASE_SERVICE, callerTenantId)
    const safeStore = escapeHtml(tenant.storeName)
    let contactLine: string
    if (tenant.isPaid) {
      contactLine = 'Questions? Stop by or give us a call.<br>'
        + safeStore + ' &middot; ' + PAID_CONTACT_HTML
    } else if (tenant.location) {
      contactLine = 'Questions? Stop by the shop.<br>'
        + safeStore + ' &middot; ' + escapeHtml(tenant.location)
    } else {
      console.warn('notify-customers: no postal address (tenants.location) for tenant', callerTenantId, '- not sending')
      return Response.json(
        { error: 'No shop postal address on file (tenants.location); catalog email not sent' },
        { status: 422, headers: corsHeaders },
      )
    }

    // Fetch all non-admin customers scoped to the caller's tenant.
    // Paper customers (@paper.pulllist.local) are excluded from the recipient list below.
    const tenantFilter = `&tenant_id=eq.${callerTenantId}`
    const profilesRes = await fetch(
      SUPABASE_URL + '/rest/v1/user_profiles?is_admin=eq.false&select=id,full_name,status,is_paper,email_catalog,email_picks' + tenantFilter,
      { headers: authHeaders }
    )
    const profiles = await profilesRes.json()
    if (!Array.isArray(profiles) || profiles.length === 0) {
      return Response.json({ error: 'No customers found' }, { status: 404, headers: corsHeaders })
    }

    // Fetch emails from auth.users for each profile
    const usersRes = await fetch(
      SUPABASE_URL + '/auth/v1/admin/users?per_page=1000',
      { headers: authHeaders }
    )
    const usersData = await usersRes.json()
    const userMap: Record<string, string> = {}
    ;(usersData.users || []).forEach((u: { id: string; email: string }) => {
      userMap[u.id] = u.email
    })

    // Build recipient list — skip paper placeholder emails and rows with no email.
    // A customer who switched the catalog email off (My Account, or the link in an email) gets
    // nothing, whatever their account state: a mail client's one-click unsubscribe is honoured for
    // pending and paused accounts too (Top Picks plan S4/S5). A missing value reads as on.
    type CatalogProfile = {
      id: string; full_name: string; status: string | null; is_paper: boolean | null
      email_catalog: boolean | null; email_picks: boolean | null
    }
    const skippedCatalogOff = profiles.filter((p: CatalogProfile) => p.email_catalog === false).length
    const recipients = profiles
      .filter((p: CatalogProfile) => p.email_catalog !== false)
      .map((p: CatalogProfile) => ({
        id: p.id, name: p.full_name, email: userMap[p.id],
        // Top Picks are promotional: only an active, non-paper account that has them on (O1).
        // Pending and paused accounts keep the catalog notice, without picks.
        wantsPicks: p.status === 'active' && p.is_paper !== true && p.email_picks !== false,
      }))
      .filter((r: { email?: string }) => r.email && !r.email.endsWith('@paper.pulllist.local'))

    console.log('Sending catalog notification to', recipients.length, 'customers for', catalog_month,
      '(', skippedCatalogOff, 'skipped: catalog email switched off )')

    // Read each picks-eligible customer's picks ahead of the send loop, a few at a time, so the
    // sends are not held up one read at a time. This shop's postal address is already guaranteed
    // above (a send with picks must carry one), so the secret is the only other precondition.
    const picksByUser = new Map<string, EmailPick[]>()
    if (PREFS_LINKS_OK) {
      const t0 = Date.now()
      await inBatches(recipients.filter((r: { wantsPicks: boolean }) => r.wantsPicks), 4, async (r: { id: string }) => {
        picksByUser.set(r.id, await fetchPicks(SUPABASE_URL!, SUPABASE_SERVICE!, r.id))
      })
      console.log('Read picks for', picksByUser.size, 'customers in', Date.now() - t0, 'ms')
    } else {
      console.warn('notify-customers: EMAIL_PREFS_SECRET missing or shorter than 32 characters - sending without picks, settings links or List-Unsubscribe headers')
    }

    // Build the deadline paragraph — omitted cleanly if no deadline is set in admin
    const deadlinePara = deadlineLabel
      ? '<p style="color:#ccc;line-height:1.7;margin:0 0 24px">'
          + 'Please log in and reserve your titles before <strong style="color:#fff">'
          + deadlineLabel
          + '</strong> to lock in your picks for the month.'
          + '</p>'
      : '<p style="color:#ccc;line-height:1.7;margin:0 0 24px">'
          + 'Please log in and reserve your titles before the order deadline.'
          + '</p>'

    const buildHtml = (picksHtml: string, settingsLine: string) => '<div style="font-family:Arial,sans-serif;max-width:520px;margin:0 auto;background:#1a1a1a;color:#f0f0f0;border-radius:8px;overflow:hidden">'
      + '<div style="background:#111;padding:24px 32px;border-bottom:3px solid #e63946">'
      + '<div style="font-size:1.6rem;font-weight:900;letter-spacing:0.08em">PULL<span style="color:#e63946">LIST</span></div>'
      + '<div style="font-size:0.75rem;color:#888;margin-top:2px">' + safeStore + ' &mdash; Monthly Comics Pre-Order System</div>'
      + '</div>'
      + '<div style="padding:32px">'
      + '<h2 style="margin:0 0 16px;font-size:1.1rem;color:#fff">The ' + monthLabel + ' catalog is now live</h2>'
      + '<p style="color:#ccc;line-height:1.7;margin:0 0 16px">The new pull list is ready &mdash; browse this month\'s Lunar and PRH titles and reserve the ones you want.</p>'
      + deadlinePara
      + `<a href="${APP_BASE_URL}/catalog.html" style="display:inline-block;background:#e63946;color:white;padding:13px 28px;border-radius:4px;text-decoration:none;font-weight:700;font-size:0.9rem;letter-spacing:0.03em">Browse the Catalog &rarr;</a>`
      + picksHtml
      + '<p style="margin-top:24px;font-size:0.78rem;color:#666;line-height:1.6">'
      + contactLine
      + '</p></div>'
      + '<div style="background:#111;padding:16px 32px;font-size:0.72rem;color:#555;border-top:1px solid #222">' + safeStore + ' &middot; Sent via the PullList pre-order system' + settingsLine + '</div>'
      + '</div>'

    // Send to each recipient
    let sent   = 0
    let failed = 0

    let withPicks = 0

    for (const recipient of recipients) {
      // The signed links (a settings page for the footer, an RFC 8058 address for the header)
      // go on EVERY send, picks or not: they are how anyone turns this email off.
      const links = PREFS_LINKS_OK ? await prefsLinksFor(SUPABASE_URL!, recipient.id) : null
      const picks = picksByUser.get(recipient.id) ?? []
      const html = buildHtml(
        buildPicksHtml(picks, APP_BASE_URL, 'email-catalog'),
        links ? settingsLinkHtml(links.page) : '',
      )

      const mailRes = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          Authorization: 'Bearer ' + RESEND_API_KEY,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          from: `${mailFromName(tenant)} <${MAIL_FROM_EMAIL}>`,
          to: recipient.email,
          subject: tenant.storeName + ' — The ' + monthLabel + ' pull list is live',
          html,
          ...(links ? { headers: { 'List-Unsubscribe': `<${links.unsubscribe}>`, 'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click' } } : {}),
        }),
      })

      if (mailRes.ok) {
        sent++
        if (picks.length) withPicks++
      } else {
        failed++
        const err = await mailRes.json().catch(() => ({}))
        console.error('Failed to send to', recipient.email, JSON.stringify(err))
      }

      // Small delay to avoid Resend rate limits
      await new Promise(resolve => setTimeout(resolve, 100))
    }

    console.log('Notification complete. Sent:', sent, 'Failed:', failed, 'With picks:', withPicks, 'Skipped (catalog email off):', skippedCatalogOff)
    return Response.json({ success: true, sent, failed, with_picks: withPicks, skipped_catalog_off: skippedCatalogOff }, { headers: corsHeaders })

  } catch (err) {
    console.error('Unexpected error:', String(err))
    return Response.json({ error: String(err) }, { status: 500, headers: corsHeaders })
  }
})
