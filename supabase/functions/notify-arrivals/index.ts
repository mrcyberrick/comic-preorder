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
      recipients: Array<{ user_id: string; name: string; email?: string; available: DigestRow[]; unavailable: DigestRow[] }>
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
          `&select=id,full_name,is_paper,status,email_arrivals`,
        { headers: svc },
      )
      const profiles: Array<{ id: string; full_name: string; is_paper: boolean; status: string; email_arrivals: boolean }> =
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

      const recipients = [...byUser.entries()].map(([user_id, rows]) => ({
        user_id,
        name: eligible.get(user_id)?.full_name || 'Valued Customer',
        ...rows,
      }))

      plans.push({ tenant, recipients, skipped: recipients.length ? undefined : 'no eligible customer with a reservation on this week’s shipment' })
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
    const failures: Array<{ tenant: string; user_id: string; error: string }> = []

    for (const plan of plans) {
      if (!plan.recipients.length) continue
      const identity = await fetchTenantIdentity(SUPABASE_URL, SUPABASE_SERVICE, plan.tenant.id)

      for (const r of plan.recipients) {
        try {
          const authUserRes = await fetch(`${SUPABASE_URL}/auth/v1/admin/users/${r.user_id}`, { headers: svc })
          const authUser = await authUserRes.json()
          const email = authUser?.email
          if (!email) { failures.push({ tenant: plan.tenant.slug, user_id: r.user_id, error: 'no email on auth user' }); continue }

          const html = buildArrivalsEmail(r.name, r.available, r.unavailable, identity)
          const mailRes = await fetch('https://api.resend.com/emails', {
            method: 'POST',
            headers: { Authorization: `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({
              from: `${mailFromName(identity)} <${MAIL_FROM_EMAIL}>`,
              to: email,
              subject: `Your books this week — ${identity.storeName}`,
              html,
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
        } catch (err) {
          failures.push({ tenant: plan.tenant.slug, user_id: r.user_id, error: String(err) })
        }
      }
    }

    console.log(`notify-arrivals: ${sent.length} sent, ${failures.length} failed, week ${weekStart}..${weekEnd}` +
      (actingAdminId ? ` (manual, admin ${actingAdminId}, tenant ${scopeTenantId})` : ' (cron, all tenants)'))

    return json({
      week: { start: weekStart, end: weekEnd },
      sent: sent.length,
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

    <p style="margin-top:20px;font-size:0.72rem;color:#666">
      Don't want this weekly note? Turn it off on My List, next to Email My List.
    </p>
${contactParagraph}  </div>

  <div style="background:#111;padding:16px 32px;font-size:0.72rem;color:#555;border-top:1px solid #222">
    ${safeStore} &middot; Sent via the PullList pre-order system
  </div>

</div>`
}
