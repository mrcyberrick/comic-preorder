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

- **Spike first, gate everything on it.** Verify the exact Cloudflare mechanism — CF Pages custom-domain wildcards are limited; the clean SaaS path is **Cloudflare for SaaS / Custom Hostnames** (or a Worker in front of Pages). Confirm wildcard-TLS issuance and cost before committing to the public flow.
- This mirrors how F64 item 5 gated 5.4: the first sub-deploy's S0 is this infra spike, and no public-signup feature work begins until wildcard DNS+TLS is proven.

---

## Approach Decisions (taken at 5.4 planning, 2026-06-15 — Rick)

- **Public ≠ ungated.** The raw `register-tenant` EF is never exposed publicly. The public page is a thin client to a *public-facing wrapper* that replaces the operator-secret gate with anti-abuse controls. Same service-role provisioning engine underneath.
- **Verify email before you provision (the #1 abuse control).** On submit, create a *pending* signup and email a confirm link; the `tenants` row + first admin are written **only after** the owner clicks. Kills drive-by squatting/spam.
- **Reuse, don't rebuild.** 5.4's engine, 5.3's branding render, 5.2's subdomain resolution, and the 4.1 teardown are the foundation. Phase 6 is additive.
- **Phase it separately from Phase 5** (see "Why a separate phase" above).

---

## Provisional sub-deploy shape (illustrative — finalized when Phase 6 opens)

Not committed; recorded so the work is sized and findable.

| #   | Title (provisional) | Notes |
|-----|--------------------|-------|
| 6.0 | **Wildcard DNS + TLS spike** (the S0 gate) | `*.pulllist.app` wildcard cert/serving via Cloudflare for SaaS / Worker; proven before any 6.x feature work |
| 6.1 | **`tenants.status` + suspend/takedown tooling** | Add `status` (active/suspended/pending) col; `resolve_tenant_by_slug` filters to active (the RPC note already anticipates this); admin suspend/rename for squatting/impersonation takedowns |
| 6.2 | **Public signup flow** | `/signup` page; `check_slug_available(slug)→bool` anon RPC (returns *only* a boolean — no tenant data leak); Cloudflare Turnstile (server-verified in the EF); per-IP/per-email rate limit; reserved-slug + profanity/impersonation filter (extend the 5.4 denylist); email-verify-before-provision wrapper EF |
| 6.3 | **First-admin onboarding wizard** | Post-verify: set display name, brand color, logo upload, contact info → writes `tenants.branding` (rendered live by 5.3's `Branding.apply()`); sensible empty-state defaults so the site is immediately functional; new-tenant customers arrive via the existing admin **invite-customer / create-paper-customer** path, *not* MailerLite (which stays founding-specific) |
| 6.4 | **Abandoned-tenant TTL sweep + soak** | Reap unverified/never-activated tenants and orphans from non-atomic provisioning failures (reuses the 4.1 FK-ordered teardown); abuse-control soak |

---

## In Scope for Phase 6 (provisional)

- Wildcard DNS + TLS for `*.pulllist.app` (the gating spike).
- Public `/signup` page + email-verify-before-provision wrapper around the 5.4 `register-tenant` engine.
- Anti-abuse: Turnstile, rate limiting, reserved/profanity/impersonation slug filtering, disposable-email handling (optional).
- `check_slug_available` anon RPC (boolean only).
- `tenants.status` column + active-tenant filtering in `resolve_tenant_by_slug` + suspend/rename takedown tooling.
- First-admin onboarding wizard writing `tenants.branding`.
- Abandoned-tenant TTL sweep.

## Out of Scope for Phase 6 (provisional — revisit when sized)

- **Billing / plan tiers / paid plans** — no requirement yet (carried from Phase 5 out-of-scope). Free self-serve may still need a per-account cap.
- **Multi-tenant email branding / per-tenant MailerSend identities** — still the Phase 5 out-of-scope item (tracked at **F72**, filed in 5.4). A self-serve tenant's customer emails being founding-branded is the open gap; Phase 6 may finally act on it, but it is not assumed in scope until sized.
- **POS integration / partial fulfillment** — unchanged.

---

## Completion Criteria (provisional — finalized when Phase 6 opens)

- [ ] Wildcard `*.pulllist.app` DNS+TLS proven; a freshly-claimed slug serves instantly with zero manual DNS.
- [ ] A new owner can go signup → email-verify → branded live site in ~6 minutes, unaided.
- [ ] Abuse controls verified: bot signups blocked (Turnstile), rate-limited, reserved/impersonation slugs rejected, unverified signups never provision a tenant.
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

**Last updated:** 2026-06-15 (stub created at 5.4 planning — phasing decision: open self-serve is Phase 6, gated on a wildcard-DNS/TLS spike; detail deferred until Phase 5 closes)
