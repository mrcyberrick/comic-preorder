# Phase 6 — Open Self-Service Tenant Signup (STUB)

**Status:** **Stub — not started.** Successor to Phase 5. This is a *thin coordinator stub* capturing the goal, the gating prerequisite, and the design decisions taken at 5.4 planning (2026-06-15). **Detailed sub-deploy runbooks are written when Phase 6 actually opens — after Phase 5 (5.5) closes** — per the Phase 3/4/5 pattern (plan-when-its-turn-comes; do not plan execution detail against future schema/infra state).
**Predecessor:** Phase 5 — Second-Tenant Onboarding (`docs/phase-5-second-tenant-onboarding.md`). **Phase 6 does not begin until Phase 5 is Complete.**
**Depends on (built in Phase 5, reused here):**
- The **`register-tenant` gated operator Edge Function** (Phase 5.4 S3) — the service-role provisioning engine. Phase 6 reuses this engine **unchanged in its core**; "open self-serve" is a *layer on top* (a public front end + an anti-abuse gate replacing the operator-secret gate), **not** a reimplementation.
- The **per-tenant webhook-secret** mechanism + `register-customer` un-pin (5.4 S1/S2).
- **`Branding.apply()`** (5.3) — already renders `tenants.branding`; the Phase 6 onboarding wizard just *writes* `branding` and the site brands itself live.
- **Slug→subdomain tenant resolution** (5.2) — the frontend already resolves a tenant from its subdomain; Phase 6's gap is the DNS/TLS layer, not the routing.
- The **4.1 FK-ordered canary teardown** (proven in 5.4 S4) — Phase 6's abandoned-tenant sweep and takedown tooling build on it.

> **Why a separate phase, not a 5.6:** Phase 5's goal and completion criteria end at "two tenants side by side + two-tenant production soak." Open public self-serve (public signup page, wildcard DNS/TLS, bot/abuse controls, tenant lifecycle/suspend, onboarding wizard) is a distinct product expansion with its own risk surface. Phase 5's completion criteria already anticipate "Phase 6 stub created if a successor phase exists" — this is that stub.

---

## Goal

Let a business owner spin up a fully-branded, working PULLLIST tenant in ~6 minutes, self-service, with no operator in the loop — while the platform stays safe from squatting, spam, and abuse. After Phase 6, onboarding tenant *N+1* is a self-service signup, not even an operational task.

The data-isolation boundary is **already solved** (RLS via `current_tenant_id()` — a self-serve tenant can never see another's data). Phase 6's problem is therefore **resource abuse and provisioning UX**, not leakage.

---

## 🚩 Gating prerequisite (Phase 6 S0 — a spike before any feature work)

**Wildcard DNS + wildcard TLS for `*.pulllist.app`, terminating at Cloudflare Pages.** The entire "6 minutes" promise depends on a freshly-claimed slug serving at `<slug>.pulllist.app` **instantly, with zero per-tenant DNS work.** If a new tenant needs a manual DNS record, it is not self-serve.

- **Spike first, gate everything on it.** This mirrors how F64 item 5 gated 5.4: the first sub-deploy's S0 is this infra spike, and no public-signup feature work begins until the serving model + cost are proven.
- **The serving model drives whether abuse raises cost — price out both (2026-06-16 discussion, Rick):**
  - **(a) Wildcard subdomain** — `<slug>.pulllist.app` via a single `*.pulllist.app` DNS record + **one wildcard TLS cert** on the `pulllist.app` zone. All tenants share one cert; **no per-tenant custom hostname, no per-tenant cost.** A bot-created tenant costs DB rows, not money.
  - **(b) Cloudflare for SaaS / Custom Hostnames** — needed **only** if tenants bring their **own vanity domain** (`pulls.theirstore.com`). Here each tenant = one custom hostname: **<100 free, $0.10/hostname after** — abuse directly raises cost.
  - **Lead recommendation:** ship Phase 6 on **(a) wildcard subdomains** (free, abuse-cheap); offer **(b) vanity domains** later as a **paid opt-in** so the per-hostname cost lands on the tenant who wants it.
- **Cost-hygiene rules regardless of model:** provision the serving entry/hostname **only on tenant *activation*** (post email-verify + eligibility), **never on signup submit**; the **abandoned-tenant sweep must reclaim the hostname** (call the Cloudflare API to delete it, not just the DB rows); track hostname count with an alert near any free-tier limit.

---

## Approach Decisions (taken at 5.4 planning, 2026-06-15 — Rick)

- **Public ≠ ungated.** The raw `register-tenant` EF is never exposed publicly. The public page is a thin client to a *public-facing wrapper* that replaces the operator-secret gate with anti-abuse controls. Same service-role provisioning engine underneath.
- **Verify email before you provision (the #1 abuse control).** On submit, create a *pending* signup and email a confirm link; the `tenants` row + first admin are written **only after** the owner clicks. Kills drive-by squatting/spam.
- **Reuse, don't rebuild.** 5.4's engine, 5.3's branding render, 5.2's subdomain resolution, and the 4.1 teardown are the foundation. Phase 6 is additive.
- **Eligibility = a PRH or Lunar retailer account (likely a hard pre-requisite).** See the dedicated section below — this is both the value gate and the strongest abuse/cost control.
- **Phase it separately from Phase 5** (see "Why a separate phase" above).

---

## Eligibility gate — PRH / Lunar retailer account (2026-06-16 discussion, Rick)

The system only provides value to a business with a **PRH (Penguin Random House) and/or Lunar Distribution retailer account** — those are the catalogs it imports. So "has a PRH or Lunar retailer account" is a natural **signup pre-requisite and the single strongest abuse/cost control**: a bot or random has no such account, so requiring one shrinks the spam-and-hostname-cost surface far more than Turnstile + rate-limiting alone. It is simultaneously the **value-alignment gate** and the **cost gate** (no eligible account → no provisioned tenant → no hostname cost).

- **Either-or:** a PRH **or** Lunar account suffices — the system supports both distributors independently; a tenant with one still gets value (imports that distributor's catalog).
- **Verification method (open question — the real tension with "6-minute self-serve"):**
  - *Self-attestation* (enter the PRH/Lunar retailer account #): lowest friction, weakest; acceptable combined with email-verify + Turnstile for a **trial** state.
  - *Manual operator review*: strongest, but reintroduces a human in the loop (tempers pure instant self-serve). Good for the early/low-volume cohort; matches Phase 5's "onboarding gated" instinct.
  - *Automated verification against PRH/Lunar*: ideal but **likely infeasible** (no known public retailer-verification API — confirm during Phase 6).
- **Recommended hybrid (preserves the wow without the cost exposure):** instant signup → email-verify → **branded site live immediately in a pending/trial state** (no catalog import; possibly not yet on a provisioned hostname), with **going-live / first catalog import gated on eligibility verification** (self-attested up front, operator-confirmed or spot-checked for the first cohort). Keeps the ~6-minute "see your branded site" payoff while the cost-bearing provisioning stays behind a real retailer account.

---

## Provisional sub-deploy shape (illustrative — finalized when Phase 6 opens)

Not committed; recorded so the work is sized and findable.

| #   | Title (provisional) | Notes |
|-----|--------------------|-------|
| 6.0 | **Wildcard DNS + TLS spike** (the S0 gate) | `*.pulllist.app` wildcard cert/serving via Cloudflare for SaaS / Worker; proven before any 6.x feature work |
| 6.1 | **`tenants.status` + suspend/takedown tooling** | Add `status` (active/suspended/pending) col; `resolve_tenant_by_slug` filters to active (the RPC note already anticipates this); admin suspend/rename for squatting/impersonation takedowns |
| 6.2 | **Public signup flow + eligibility gate** | `/signup` page; `check_slug_available(slug)→bool` anon RPC (returns *only* a boolean — no tenant data leak); **PRH/Lunar retailer-account eligibility checkpoint** (self-attest → trial; operator-confirm for the first cohort); Cloudflare Turnstile (server-verified in the EF); per-IP/per-email rate limit; reserved-slug + profanity/impersonation filter (extend the 5.4 denylist); email-verify-before-provision wrapper EF |
| 6.3 | **First-admin onboarding wizard + activation** | Post-verify: set display name, brand color, logo upload, contact info → writes `tenants.branding` (rendered live by 5.3's `Branding.apply()`); branded site live in a **pending/trial** state; **catalog import / going-live gated on eligibility**; serving entry/hostname provisioned **on activation only**; new-tenant customers arrive via the existing admin **invite-customer / create-paper-customer** path, *not* MailerLite (which stays founding-specific) |
| 6.4 | **Abandoned-tenant TTL sweep + soak** | Reap unverified/never-activated tenants and orphans from non-atomic provisioning failures (reuses the 4.1 FK-ordered teardown, **extended to delete the Cloudflare hostname via API**); hostname-count monitoring/alert; abuse-control soak |

---

## In Scope for Phase 6 (provisional)

- Serving-model + cost spike for `*.pulllist.app` (wildcard subdomain vs CF-for-SaaS custom hostnames) — the gating S0.
- **PRH/Lunar retailer-account eligibility gate** (value + cost control; verification method TBD per the dedicated section).
- Public `/signup` page + email-verify-before-provision wrapper around the 5.4 `register-tenant` engine.
- Anti-abuse: Turnstile, rate limiting, reserved/profanity/impersonation slug filtering, disposable-email handling (optional).
- `check_slug_available` anon RPC (boolean only).
- `tenants.status` column + active-tenant filtering in `resolve_tenant_by_slug` + suspend/rename takedown tooling.
- First-admin onboarding wizard writing `tenants.branding`; pending/trial → activation lifecycle; serving entry provisioned on activation only.
- Abandoned-tenant TTL sweep **incl. Cloudflare hostname reclamation** + hostname-count monitoring.

## Out of Scope for Phase 6 (provisional — revisit when sized)

- **Billing / plan tiers / paid plans** — no requirement yet (carried from Phase 5 out-of-scope). Free self-serve may still need a per-account cap.
- **Multi-tenant email branding / per-tenant MailerSend identities** — still the Phase 5 out-of-scope item (tracked at **F72**, filed in 5.4). A self-serve tenant's customer emails being founding-branded is the open gap; Phase 6 may finally act on it, but it is not assumed in scope until sized.
- **POS integration / partial fulfillment** — unchanged.

---

## Completion Criteria (provisional — finalized when Phase 6 opens)

- [ ] Serving model chosen + proven; a freshly-claimed slug serves instantly with zero manual DNS; per-tenant cost understood and bounded (hostname provisioned on activation only; reclaimed on teardown).
- [ ] A new owner can go signup → email-verify → branded live (trial) site in ~6 minutes, unaided.
- [ ] **Eligibility gate live:** no tenant goes live / imports a catalog without a verified PRH or Lunar retailer account.
- [ ] Abuse controls verified: bot signups blocked (Turnstile), rate-limited, reserved/impersonation slugs rejected, unverified/ineligible signups never provision a cost-bearing hostname.
- [ ] `tenants.status` live; suspended tenants do not resolve; takedown tooling works end-to-end.
- [ ] Founding + all prior tenants unchanged; full tenant-isolation suite (F15/F20) green.
- [ ] Abandoned-tenant sweep verified (no orphan tenants/auth users from abandoned or failed signups).
- [ ] All Phase 6 sub-deploy plan files committed to `docs/`.

---

## Reference

- Engine + foundations: `docs/phase-5.4-tenant-signup.md` (the `register-tenant` gated EF + per-tenant webhook secret), `docs/phase-5.3-per-tenant-branding.md` (`Branding.apply()`), `docs/phase-5.2-slug-id-routing-rpc.md` (subdomain resolution + the `resolve_tenant_by_slug` status-filter note), `docs/phase-4.1-canary-procedure.md` (FK-ordered teardown).
- Parent of the predecessor: `docs/phase-5-second-tenant-onboarding.md`.
- Anti-drift / plan-when-its-turn-comes discipline: `CLAUDE.md` § Anti-Drift Rules; § Document Integrity.
- Findings: `docs/technical-reference.md` § 13 — **F72** (email-branding deferral, filed in 5.4); `tenants` schema § 4.1 (no `status` column today; `register-tenant` reserved-slug denylist to extend).

---

**Last updated:** 2026-06-16 (added cost-model distinction — wildcard subdomain vs CF-for-SaaS custom hostnames — and the PRH/Lunar retailer-account eligibility gate as the primary value+cost control; detail still deferred until Phase 5 closes)
