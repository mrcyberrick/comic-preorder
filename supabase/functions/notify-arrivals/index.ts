/**
 * notify-arrivals — Scheduled Edge Function (customer engagement S3b)
 *
 * "Your books this week", sent every Tuesday. docs/customer-engagement-paper-to-app.md § S3b.
 *
 * Two callers:
 *   - the production Tuesday cron (docs/sql/2026-11-14-s3b-notify-arrivals-cron.sql), which
 *     presents the ARRIVALS_CRON_SECRET header and gets every shop in one call;
 *   - a signed-in admin (used for Rick's own dry_run check before the first Tuesday, and for
 *     any later manual run), scoped to that admin's own tenant only.
 * Body: { dry_run?: boolean }. dry_run computes and returns the send plan without sending
 * anything or writing arrival_notices.
 *
 * WHY THIS MATCHES BY SHIPMENT, NOT BY DATE. "On this week's shipment" is read from
 * weekly_shipment, the same three-key match auto_fulfill_past_on_sale() uses
 * (docs/sql/auto_fulfill_past_on_sale.sql) — never from catalog.on_sale_date alone. An email
 * built from dates alone would repeat F115's false "it's here": a title can be past its
 * on-sale date with no shipment evidence at all (F155's frozen-PRH-catalog shape). A shop with
 * no weekly_shipment rows for the week gets nothing sent, and the response says why — the
 * shipment import has not run yet, not "nothing is arriving."
 *
 * The per-tenant digest itself (shipment match + withdrawn/ledger-rejected/admin-marked
 * classification) lives in the database as arrivals_this_week_digest() — see
 * docs/sql/2026-11-14-s3b-email-arrivals-opt-out-and-notices.sql for why that logic is not
 * re-derived here in TypeScript.
 *
 * Required env vars (Supabase → Edge Functions → Secrets):
 *   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_ANON_KEY, RESEND_API_KEY
 *   ARRIVALS_CRON_SECRET  ← the cron job's own header value (docs/sql/..-cron.sql)
 *   APP_BASE_URL          ← optional, defaults to https://pulllist.app
 *   EMAIL_PREFS_SECRET    ← signs the opt-out links (Top Picks S5); missing or shorter than 32
 *                           characters means the email goes out WITHOUT picks, settings link or
 *                           List-Unsubscribe header, never with a weaker link
 *
 * verify_jwt: deploy --no-verify-jwt, same reasoning as notify-customers — the cron caller
 * presents no user JWT at all, only the secret header.
 */

const APP_BASE_URL = Deno.env.get('APP_BASE_URL') ?? 'https://pulllist.app'

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
    unsubscribe: `${supabaseUrl}/functions/v1/email-preferences?u=${userId}&s=${s}&k=arrivals`,
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
        ${cover ? `<td width="56" valign="top" style="padding:10px 12px 10px 0"><a href="${link}"><img src="${cover}" alt="${escapeAttr(p.title)}" width="56" style="display:block;width:56px;height:auto;border:0;border-radius:3px;background:#222"></a></td>` : ''}
        <td valign="top" style="padding:10px 0;font-size:0.84rem;color:#f0ece4">
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
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-arrivals-cron-secret',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function json(body: unknown, status = 200) {
  return Response.json(body, { status, headers: corsHeaders })
}

// F148 — Resend's free tier is 100 emails/day and this sends one request per
// recipient (the same shape that finding already names for notify-customers).
// Leaves headroom rather than running right up to the ceiling.
const MAX_RECIPIENTS = 90

type DigestRow = {
  user_id: string
  catalog_id: string
  title: string
  series_name: string | null
  publisher: string | null
  distributor: string
  price_usd: string | number | null
  quantity: number
  is_unavailable: boolean
  unavailable_reason: string | null
}

// Mon-Sun week containing `now`, in UTC — the cron fires at 15:00 UTC
// Tuesday, comfortably inside one calendar day on every timezone this store
// cares about, so there is no day-boundary ambiguity to resolve.
function thisWeekRangeUtc(now = new Date()): { start: string; end: string } {
  const day = now.getUTCDay() // 0=Sun..6=Sat
  const daysSinceMon = (day + 6) % 7
  const monday = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() - daysSinceMon))
  const sunday = new Date(Date.UTC(monday.getUTCFullYear(), monday.getUTCMonth(), monday.getUTCDate() + 6))
  const iso = (d: Date) => d.toISOString().slice(0, 10)
  return { start: iso(monday), end: iso(sunday) }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const SUPABASE_URL      = Deno.env.get('SUPABASE_URL')
    const SUPABASE_ANON     = Deno.env.get('SUPABASE_ANON_KEY')
    const SUPABASE_SERVICE  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    const RESEND_API_KEY    = Deno.env.get('RESEND_API_KEY')
    const CRON_SECRET       = Deno.env.get('ARRIVALS_CRON_SECRET')

    let body: Record<string, unknown> = {}
    try { body = await req.json() } catch { /* the cron posts an empty body; that's fine */ }
    const dryRun = body.dry_run === true

    // ── Auth: the cron secret header, or a signed-in admin (own tenant only) ──
    const secretHeader = req.headers.get('x-arrivals-cron-secret') || ''
    const viaCron = !!CRON_SECRET && !!secretHeader && secretHeader === CRON_SECRET
    let scopeTenantId: string | null = null // null = every tenant (the cron path)
    let actingAdminId: string | null = null

    if (!viaCron) {
      const authHeader = req.headers.get('Authorization') || ''
      if (!authHeader) return json({ error: 'Unauthorized' }, 401)
      const userRes = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
        headers: { Authorization: authHeader, apikey: SUPABASE_ANON! },
      })
      const userData = await userRes.json()
      if (!userRes.ok || !userData.id) return json({ error: 'Unauthorized' }, 401)

      const profileRes = await fetch(
        `${SUPABASE_URL}/rest/v1/user_profiles?id=eq.${userData.id}&select=is_admin,tenant_id`,
        { headers: { Authorization: authHeader, apikey: SUPABASE_ANON!, Accept: 'application/json' } },
      )
      const profiles = await profileRes.json()
      if (!Array.isArray(profiles) || !profiles[0]?.is_admin) return json({ error: 'Forbidden — admin only' }, 403)
      scopeTenantId = profiles[0].tenant_id
      actingAdminId = userData.id
    }

    const svc = { Authorization: `Bearer ${SUPABASE_SERVICE}`, apikey: SUPABASE_SERVICE!, 'Content-Type': 'application/json' }
    const { start: weekStart, end: weekEnd } = thisWeekRangeUtc()

    // ── Which tenants ──
    const tenantsRes = await fetch(
      `${SUPABASE_URL}/rest/v1/tenants?select=id,slug,display_name,plan,location` +
        (scopeTenantId ? `&id=eq.${scopeTenantId}` : ''),
      { headers: svc },
    )
    const tenants: Array<{ id: string; slug: string }> = await tenantsRes.json()
    if (!Array.isArray(tenants)) return json({ error: 'Failed to read tenants' }, 500)

    type Plan = {
      tenant: { id: string; slug: string }
      recipients: Array<{ user_id: string; name: string; email?: string; wantsPicks: boolean; available: DigestRow[]; unavailable: DigestRow[] }>
      skipped?: string
    }
    const plans: Plan[] = []

    for (const tenant of tenants) {
      // A shop with no weekly_shipment rows for the week gets nothing sent —
      // the shipment import has not run, not "nothing is arriving" (F115).
      const shipCountRes = await fetch(
        `${SUPABASE_URL}/rest/v1/weekly_shipment?tenant_id=eq.${tenant.id}` +
          `&on_sale_date=gte.${weekStart}&on_sale_date=lte.${weekEnd}&select=id&limit=1`,
        { headers: { ...svc, Prefer: 'count=exact' } },
      )
      const shipCount = parseInt((shipCountRes.headers.get('content-range') || '').split('/')[1] || '0', 10)
      if (!shipCount) {
        plans.push({ tenant, recipients: [], skipped: 'no weekly_shipment rows for this week yet (shipment import has not run)' })
        continue
      }

      const digestRes = await fetch(`${SUPABASE_URL}/rest/v1/rpc/arrivals_this_week_digest`, {
        method: 'POST', headers: svc,
        body: JSON.stringify({ p_tenant_id: tenant.id, p_week_start: weekStart, p_week_end: weekEnd }),
      })
      if (!digestRes.ok) {
        plans.push({ tenant, recipients: [], skipped: `digest read failed: ${await digestRes.text()}` })
        continue
      }
      const digest: DigestRow[] = await digestRes.json()
      if (!digest.length) {
        plans.push({ tenant, recipients: [], skipped: 'no reservations match this week’s shipment' })
        continue
      }

      const userIds = [...new Set(digest.map(d => d.user_id))]

      // Eligibility: not paper, not pending/suspended, opted in. Read in one
      // paged batch so a large shop never truncates at PostgREST's cap.
      const profilesRes = await fetch(
        `${SUPABASE_URL}/rest/v1/user_profiles?tenant_id=eq.${tenant.id}&id=in.(${userIds.join(',')})` +
          `&select=id,full_name,is_paper,status,email_arrivals,email_picks`,
        { headers: svc },
      )
      const profiles: Array<{ id: string; full_name: string; is_paper: boolean; status: string; email_arrivals: boolean; email_picks: boolean | null }> =
        await profilesRes.json()
      const eligible = new Map(
        profiles
          .filter(p => !p.is_paper && p.status === 'active' && p.email_arrivals !== false)
          .map(p => [p.id, p]),
      )

      // No double sends — already-sent users this (tenant, week) are excluded
      // from the plan entirely, dry_run included: a preview should show what
      // a real run would actually do.
      const alreadySentRes = await fetch(
        `${SUPABASE_URL}/rest/v1/arrival_notices?tenant_id=eq.${tenant.id}&week_start=eq.${weekStart}&select=user_id`,
        { headers: svc },
      )
      const alreadySent = new Set<string>((await alreadySentRes.json()).map((r: { user_id: string }) => r.user_id))

      const byUser = new Map<string, { available: DigestRow[]; unavailable: DigestRow[] }>()
      digest.forEach(row => {
        if (!eligible.has(row.user_id) || alreadySent.has(row.user_id)) return
        if (!byUser.has(row.user_id)) byUser.set(row.user_id, { available: [], unavailable: [] })
        const bucket = byUser.get(row.user_id)!
        ;(row.is_unavailable ? bucket.unavailable : bucket.available).push(row)
      })

      // Only email a customer who has an actual reason to come to the store
      // this week. A customer whose ONLY matching title(s) are withdrawn,
      // rejected by the supplier, or otherwise marked unavailable is dropped
      // here rather than sent an email with nothing to pick up (Rick, 2026-11-14).
      // Their unavailable rows are not lost — they simply aren't emailed about
      // until something in their list is actually available, and the store's
      // own Order Follow-Up panel is still where an unavailable title gets
      // resolved.
      const recipients = [...byUser.entries()]
        .filter(([, rows]) => rows.available.length > 0)
        .map(([user_id, rows]) => ({
          user_id,
          name: eligible.get(user_id)?.full_name || 'Valued Customer',
          // Picks are promotional: only for a customer who has them on (every recipient here is already active and non-paper).
          wantsPicks: eligible.get(user_id)?.email_picks !== false,
          ...rows,
        }))

      const skipped = recipients.length ? undefined
        : byUser.size
          ? 'every matching customer’s titles were withdrawn, rejected or otherwise unavailable this week — nothing worth a trip'
          : 'no eligible customer with a reservation on this week’s shipment'
      plans.push({ tenant, recipients, skipped })
    }

    const totalRecipients = plans.reduce((s, p) => s + p.recipients.length, 0)

    if (dryRun) {
      return json({
        dry_run: true,
        week: { start: weekStart, end: weekEnd },
        would_email: totalRecipients,
        by_tenant: plans.map(p => ({
          tenant: p.tenant.slug,
          skipped: p.skipped,
          recipients: p.recipients.map(r => ({ user_id: r.user_id, name: r.name, title_count: r.available.length + r.unavailable.length })),
        })),
      })
    }

    if (totalRecipients > MAX_RECIPIENTS) {
      return json({
        error: `Refusing to send: ${totalRecipients} recipients exceeds the ${MAX_RECIPIENTS}-recipient cap ` +
          `(Resend's free tier is 100 emails/day across every shop, F148). Nothing was sent.`,
      }, 400)
    }

    // ── Send ──
    const sent: Array<{ tenant: string; user_id: string }> = []
    let withPicks = 0
    const failures: Array<{ tenant: string; user_id: string; error: string }> = []

    for (const plan of plans) {
      if (!plan.recipients.length) continue
      const identity = await fetchTenantIdentity(SUPABASE_URL, SUPABASE_SERVICE, plan.tenant.id)

      // A send that includes picks must carry the shop's postal address (the rule notify-customers
      // follows, Q13): a paid shop's contact line has it, a free shop needs tenants.location. A free
      // shop with none gets this email WITHOUT picks rather than not at all. And no secret, no picks.
      const picksEnabled = PREFS_LINKS_OK && (identity.isPaid || !!identity.location)
      const picksByUser = new Map<string, EmailPick[]>()
      if (picksEnabled) {
        await inBatches(plan.recipients.filter(r => r.wantsPicks), 4, async (r) => {
          picksByUser.set(r.user_id, await fetchPicks(SUPABASE_URL!, SUPABASE_SERVICE!, r.user_id))
        })
      }

      for (const r of plan.recipients) {
        try {
          const authUserRes = await fetch(`${SUPABASE_URL}/auth/v1/admin/users/${r.user_id}`, { headers: svc })
          const authUser = await authUserRes.json()
          const email = authUser?.email
          if (!email) { failures.push({ tenant: plan.tenant.slug, user_id: r.user_id, error: 'no email on auth user' }); continue }

          // Signed links on EVERY send, picks or not: they are how anyone turns this email off.
          const links = PREFS_LINKS_OK ? await prefsLinksFor(SUPABASE_URL!, r.user_id) : null
          const picks = picksByUser.get(r.user_id) ?? []
          const html = buildArrivalsEmail(r.name, r.available, r.unavailable, identity, {
            picksHtml: buildPicksHtml(picks, APP_BASE_URL, 'email-arrivals'),
            settingsLine: links ? settingsLinkHtml(links.page) : '',
            noLinks: !links,
            freeLocation: picks.length && !identity.isPaid ? identity.location : '',
          })
          const mailRes = await fetch('https://api.resend.com/emails', {
            method: 'POST',
            headers: { Authorization: `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({
              from: `${mailFromName(identity)} <${MAIL_FROM_EMAIL}>`,
              to: email,
              subject: `Your books this week — ${identity.storeName}`,
              html,
              ...(links ? { headers: { 'List-Unsubscribe': `<${links.unsubscribe}>`, 'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click' } } : {}),
            }),
          })
          if (!mailRes.ok) {
            failures.push({ tenant: plan.tenant.slug, user_id: r.user_id, error: await mailRes.text() })
            continue
          }

          const noticeRes = await fetch(`${SUPABASE_URL}/rest/v1/arrival_notices`, {
            method: 'POST', headers: { ...svc, Prefer: 'return=minimal' },
            body: JSON.stringify({ tenant_id: plan.tenant.id, user_id: r.user_id, week_start: weekStart }),
          })
          if (!noticeRes.ok) {
            // The email already sent — log, but do not count this as a
            // failure to send. A stale notice row just means a possible
            // re-send next week, not a customer-visible problem.
            console.error('notify-arrivals: arrival_notices insert failed', await noticeRes.text())
          }
          sent.push({ tenant: plan.tenant.slug, user_id: r.user_id })
          if (picks.length) withPicks++
        } catch (err) {
          failures.push({ tenant: plan.tenant.slug, user_id: r.user_id, error: String(err) })
        }
      }
    }

    console.log(`notify-arrivals: ${sent.length} sent (${withPicks} with picks), ${failures.length} failed, week ${weekStart}..${weekEnd}` +
      (actingAdminId ? ` (manual, admin ${actingAdminId}, tenant ${scopeTenantId})` : ' (cron, all tenants)'))

    return json({
      week: { start: weekStart, end: weekEnd },
      sent: sent.length,
      with_picks: withPicks,
      failed: failures.length,
      skipped_tenants: plans.filter(p => p.skipped && !p.recipients.length).map(p => ({ tenant: p.tenant.slug, reason: p.skipped })),
      failures,
    })

  } catch (err) {
    console.error('notify-arrivals: unexpected error', String(err))
    return json({ error: String(err) }, 500)
  }
})

// ── Email template ────────────────────────────────────────────────────────────
// Table style reused from send-my-list's own table (same columns, same look)
// per the plan's ask; the data itself is NOT reused — send-my-list's week mode
// filters by catalog.on_sale_date, which is exactly the date-only match F115
// warns against. This function's data comes from arrivals_this_week_digest()
// (shipment-matched) instead. Adds: the "Not arriving this week" note (D-less,
// Rick's own ask in § S3b) and the opt-out line (D5) neither of send-my-list's
// two modes needed.
function buildArrivalsEmail(
  name: string,
  available: DigestRow[],
  unavailable: DigestRow[],
  identity: TenantIdentity,
  opts: { picksHtml: string; settingsLine: string; noLinks: boolean; freeLocation: string },
): string {
  const safeStore = escapeHtml(identity.storeName)
  const totalQty = available.reduce((s, r) => s + (r.quantity || 1), 0)

  const rows = available.map(r => {
    const qty = r.quantity || 1
    const dist = r.distributor || ''
    const distColor = dist === 'Lunar' ? '#3b82f6' : '#a855f7'
    return `
        <tr style="border-bottom:1px solid #2e2e2e">
          <td style="padding:10px 8px;font-size:0.82rem;color:#f0ece4">
            <div style="font-weight:600">${escapeHtml(r.title || '—')}</div>
            ${r.series_name ? `<div style="font-size:0.75rem;color:#9a9390;margin-top:2px">${escapeHtml(r.series_name)}</div>` : ''}
          </td>
          <td style="padding:10px 8px;font-size:0.78rem;color:#9a9390;white-space:nowrap">${escapeHtml(r.publisher || '—')}</td>
          <td style="padding:10px 8px;text-align:center">
            <span style="font-size:0.68rem;font-weight:700;padding:2px 7px;border-radius:2px;background:${distColor}22;color:${distColor};border:1px solid ${distColor}55">${escapeHtml(dist)}</span>
          </td>
          <td style="padding:10px 8px;text-align:center;font-weight:700;color:${qty > 1 ? '#e8321c' : '#f0ece4'};font-size:0.85rem">${qty}</td>
        </tr>`
  }).join('')

  // available.length is always > 0 here — the caller only emails a customer
  // with something actually worth a trip (Rick, 2026-11-14). Kept as a
  // ternary rather than assumed, so this function stays correct if that
  // caller-side guarantee ever changes.
  const table = available.length ? `
    <table style="width:100%;border-collapse:collapse;font-family:Arial,sans-serif">
      <thead>
        <tr style="border-bottom:2px solid #3a3a3a">
          <th style="padding:8px 8px;text-align:left;font-size:0.68rem;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;color:#666">Title</th>
          <th style="padding:8px 8px;text-align:left;font-size:0.68rem;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;color:#666">Publisher</th>
          <th style="padding:8px 8px;text-align:center;font-size:0.68rem;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;color:#666">Dist</th>
          <th style="padding:8px 8px;text-align:center;font-size:0.68rem;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;color:#666">Qty</th>
        </tr>
      </thead>
      <tbody>${rows}</tbody>
      <tfoot>
        <tr style="border-top:2px solid #3a3a3a">
          <td colspan="4" style="padding:12px 8px;font-size:0.82rem;color:#888">${totalQty} item${totalQty !== 1 ? 's' : ''} on this week's shipment</td>
        </tr>
      </tfoot>
    </table>` : `<p style="color:#ccc;font-size:0.85rem">Nothing from your pull list is on this week's shipment.</p>`

  const notArrivingHtml = unavailable.length ? `
    <div style="margin-top:20px;padding-top:12px;border-top:1px dashed #3a3a3a;font-size:0.78rem;color:#9a9390">
      <div style="font-weight:700;color:#eab308;margin-bottom:4px">Not arriving this week (${unavailable.length})</div>
      <ul style="list-style:none;padding:0;margin:0">
        ${unavailable.map(r => `<li>${escapeHtml(r.title || '—')} — ${escapeHtml(r.unavailable_reason || '')}</li>`).join('')}
      </ul>
    </div>` : ''

  const contactParagraph = identity.isPaid
    ? `    <p style="margin-top:24px;font-size:0.78rem;color:#666;line-height:1.6">
      Questions? Stop by or give us a call.<br>
      ${safeStore} &middot; ${PAID_CONTACT_HTML}
    </p>
`
    // A free shop's email carries no contact line unless it includes picks, which must carry a
    // postal address (Q13); then it is the shop's own tenants.location.
    : opts.freeLocation
      ? `    <p style="margin-top:24px;font-size:0.78rem;color:#666;line-height:1.6">
      Questions? Stop by the shop.<br>
      ${safeStore} &middot; ${escapeHtml(opts.freeLocation)}
    </p>
`
      : ''

  // With a signed settings link the footer carries it. Without one (no EMAIL_PREFS_SECRET) the email
  // keeps a plain sentence that is still true: the switches live in My Account, reached from the
  // name at the top of any page.
  const optOutParagraph = opts.noLinks
    ? `    <p style="margin-top:20px;font-size:0.72rem;color:#666">
      Don't want this weekly note? Open My Account (your name at the top of any page) and switch it off.
    </p>
`
    : ''

  return `
<div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto;background:#1a1a1a;color:#f0f0f0;border-radius:8px;overflow:hidden">

  <div style="background:#111;padding:24px 32px;border-bottom:3px solid #e63946">
    <div style="font-size:1.6rem;font-weight:900;letter-spacing:0.08em">PULL<span style="color:#e63946">LIST</span></div>
    <div style="font-size:0.75rem;color:#888;margin-top:2px">${safeStore} &mdash; Monthly Comics Pre-Order System</div>
  </div>

  <div style="padding:28px 32px">
    <h2 style="margin:0 0 6px;font-size:1rem;color:#fff">Hi ${escapeHtml(name)},</h2>
    <p style="color:#ccc;line-height:1.7;margin:0 0 20px;font-size:0.88rem">
      These titles from your pull list are on this week's shipment, ready from Wednesday.
    </p>

    ${table}
    ${notArrivingHtml}

    <a href="${APP_BASE_URL}/mylist.html"
       style="display:inline-block;margin-top:24px;background:#e63946;color:white;padding:12px 26px;
              border-radius:4px;text-decoration:none;font-weight:700;font-size:0.85rem;
              letter-spacing:0.03em">
      See My List &rarr;
    </a>
${opts.picksHtml}
${optOutParagraph}${contactParagraph}  </div>

  <div style="background:#111;padding:16px 32px;font-size:0.72rem;color:#555;border-top:1px solid #222">
    ${safeStore} &middot; Sent via the PullList pre-order system${opts.settingsLine}
  </div>

</div>`
}
