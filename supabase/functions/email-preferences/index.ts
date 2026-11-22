// email-preferences — a customer's three email switches, reached from the link in
// an email, WITHOUT signing in. Top Picks plan S4 (docs/top-picks-emails-and-notification-settings.md
// § 3.4, decision D9).
//
// PUBLIC BY DESIGN (deployed --no-verify-jwt): the signed token in the link is the only gate.
// The token is HMAC-SHA256 over `v1|<user_id>` with the secret EMAIL_PREFS_SECRET, written as
// 64 lowercase hex characters; it has no expiry (an opt-out link must keep working) and it
// authorizes ONE thing: changing that customer's email_catalog / email_arrivals / email_picks.
// It cannot read or write any other column, any other customer, or anything else.
//
//   GET  ?u=<user_id>&s=<token>             -> JSON: shop name, whether the switches apply, the 3 values.
//                                              CHANGES NOTHING (link scanners open links).
//                                              A browser navigation (Accept: text/html) is redirected to the
//                                              static page email-preferences.html with the same parameters.
//   POST ?u=&s=      JSON body {email_catalog?, email_arrivals?, email_picks?}   (booleans only)
//                                           -> sets those switches. Account must be editable (see below).
//   POST ?u=&s=&k=catalog|arrivals   body  List-Unsubscribe=One-Click   (RFC 8058, what a mail client's
//                                              "Unsubscribe" button sends) -> turns that ONE email off.
//                                              Honoured for every account state: a mail client that shows
//                                              "unsubscribed" while we keep sending is worse than any rule.
//
// "Editable" mirrors My Account (account.html): a pending or paused account (not an admin) sees no
// switches, because the catalog email is a notice about their account, not promotion (O1, Rick
// 2026-11-17). The page says so plainly instead.
//
// Every refusal of a token (missing, malformed, wrong signature, a signature for another customer,
// a customer that no longer exists) is ONE identical response, so nothing here tells a caller
// which user ids exist. No usage_events row is written: an event attributed to the customer would
// move their "last seen" in Analytics when only a link scanner or a mail client touched this.

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')
const SERVICE_KEY  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
const PREFS_SECRET = Deno.env.get('EMAIL_PREFS_SECRET') ?? ''
const APP_BASE_URL = (Deno.env.get('APP_BASE_URL') ?? 'https://pulllist.app').replace(/\/+$/, '')

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

const TOGGLES = ['email_catalog', 'email_arrivals', 'email_picks'] as const
// What a mail client's one-click button may turn off. (A "just stop the picks" link would be one
// more line here; it is not offered until the emails ask for it.)
const ONE_CLICK: Record<string, typeof TOGGLES[number]> = { catalog: 'email_catalog', arrivals: 'email_arrivals' }

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, accept',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
}
const baseHeaders = { ...corsHeaders, 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' }

const reply = (body: unknown, status = 200) => Response.json(body, { status, headers: baseHeaders })
const REFUSED     = () => reply({ error: 'This link is not valid.' }, 403)
const UNAVAILABLE = () => reply({ error: 'Email settings are unavailable right now. Please try again later.' }, 503)

type Profile = {
  id: string; tenant_id: string | null; status: string | null; is_admin: boolean | null
  email_catalog: boolean; email_arrivals: boolean; email_picks: boolean
}

async function rest(path: string, init: RequestInit = {}): Promise<Response> {
  return fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${SERVICE_KEY}`, apikey: SERVICE_KEY!, Accept: 'application/json',
      ...(init.body ? { 'Content-Type': 'application/json' } : {}), ...(init.headers ?? {}),
    },
  })
}

async function readProfile(userId: string): Promise<Profile | null | 'error'> {
  const res = await rest(`user_profiles?id=eq.${userId}&select=id,tenant_id,status,is_admin,email_catalog,email_arrivals,email_picks`)
  if (!res.ok) { console.error('profile read failed', res.status); return 'error' }
  const rows = await res.json()
  return Array.isArray(rows) && rows.length === 1 ? rows[0] as Profile : null
}

// The shop's name for the page heading. Any failure reads as the platform name.
async function storeName(tenantId: string | null): Promise<string> {
  if (!tenantId) return 'PULLLIST'
  try {
    const res = await rest(`tenants?id=eq.${tenantId}&select=display_name`)
    if (!res.ok) return 'PULLLIST'
    const rows = await res.json()
    const n = Array.isArray(rows) ? rows[0]?.display_name : null
    return typeof n === 'string' && n.trim() ? n.trim() : 'PULLLIST'
  } catch { return 'PULLLIST' }
}

// Same rule as account.html: an admin always; anyone else only once past pending / paused.
const isEditable = (p: Profile) => p.is_admin === true || (p.status !== 'pending' && p.status !== 'suspended')

const valuesOf = (p: Pick<Profile, typeof TOGGLES[number]>) => ({
  email_catalog: p.email_catalog, email_arrivals: p.email_arrivals, email_picks: p.email_picks,
})

async function writeToggles(userId: string, patch: Record<string, boolean>): Promise<Response> {
  const res = await rest(`user_profiles?id=eq.${userId}&select=email_catalog,email_arrivals,email_picks`, {
    method: 'PATCH', headers: { Prefer: 'return=representation' }, body: JSON.stringify(patch),
  })
  if (!res.ok) { console.error('toggle write failed', res.status); return UNAVAILABLE() }
  const rows = await res.json()
  // A write that matched no row (or more than one) is a failure, never "saved".
  if (!Array.isArray(rows) || rows.length !== 1) { console.error('toggle write matched', Array.isArray(rows) ? rows.length : 'n/a'); return UNAVAILABLE() }
  return reply({ ok: true, ...valuesOf(rows[0]) })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'GET' && req.method !== 'POST') return reply({ error: 'Method not allowed' }, 405)

  // A secret that is missing or short means every link would be checked against nothing.
  // Fail closed and loudly, never accept a token.
  if (!SUPABASE_URL || !SERVICE_KEY || PREFS_SECRET.length < 32) {
    console.error('email-preferences: EMAIL_PREFS_SECRET missing or shorter than 32 characters')
    return UNAVAILABLE()
  }

  const url = new URL(req.url)
  const u = (url.searchParams.get('u') ?? '').toLowerCase()
  const s = (url.searchParams.get('s') ?? '').toLowerCase()
  const k = url.searchParams.get('k') ?? ''

  // A browser that follows an Unsubscribe link lands here with a plain GET. Send it to the
  // page (which shows the switches and changes nothing until a switch is pressed). The
  // parameters are re-encoded and the destination is fixed, so this is not an open redirect;
  // the token is checked by the page's own GET, not here.
  if (req.method === 'GET') {
    const accept = req.headers.get('accept') ?? ''
    if (accept.includes('text/html') && !accept.includes('application/json')) {
      const q = new URLSearchParams()
      if (u) q.set('u', u)
      if (s) q.set('s', s)
      if (Object.prototype.hasOwnProperty.call(ONE_CLICK, k)) q.set('k', k)
      return new Response(null, { status: 302, headers: { ...baseHeaders, Location: `${APP_BASE_URL}/email-preferences.html?${q.toString()}` } })
    }
  }

  if (!(await verifyPrefsToken(PREFS_SECRET, u, s))) return REFUSED()

  // Nothing below runs for a bad token, so user ids cannot be probed through this function.
  const profile = await readProfile(u)
  if (profile === 'error') return UNAVAILABLE()
  if (!profile) return REFUSED()

  if (req.method === 'GET') {
    const editable = isEditable(profile)
    return reply({ ok: true, store: await storeName(profile.tenant_id), editable, ...(editable ? valuesOf(profile) : {}) })
  }

  // ── POST ────────────────────────────────────────────────────────────────────
  if (Number(req.headers.get('content-length') ?? '0') > 2048) return reply({ error: 'Request too large' }, 413)
  const contentType = (req.headers.get('content-type') ?? '').toLowerCase()
  const raw = await req.text()
  if (raw.length > 2048) return reply({ error: 'Request too large' }, 413)

  // RFC 8058 one-click: a form body of exactly `List-Unsubscribe=One-Click`, and ?k= names the email.
  if (contentType.includes('application/x-www-form-urlencoded')) {
    const form = new URLSearchParams(raw)
    const col = Object.prototype.hasOwnProperty.call(ONE_CLICK, k) ? ONE_CLICK[k] : null
    if (form.get('List-Unsubscribe') !== 'One-Click' || !col) return reply({ error: 'Invalid request' }, 400)
    return writeToggles(u, { [col]: false })
  }

  // The page's own save: a JSON object holding only the three switches, as booleans.
  if (!isEditable(profile)) return reply({ error: 'Email settings are available once your account is active.', editable: false }, 403)
  let body: unknown
  try { body = JSON.parse(raw) } catch { return reply({ error: 'Invalid request' }, 400) }
  if (!body || typeof body !== 'object' || Array.isArray(body)) return reply({ error: 'Invalid request' }, 400)
  const entries = Object.entries(body as Record<string, unknown>)
  const allowed = new Set<string>(TOGGLES)
  if (entries.length === 0 || entries.some(([key, v]) => !allowed.has(key) || typeof v !== 'boolean')) {
    return reply({ error: 'Invalid request' }, 400)
  }
  return writeToggles(u, Object.fromEntries(entries) as Record<string, boolean>)
})
