# Phase 5 — Second-Tenant Onboarding

**Status:** Planning — stub only; parent plan not yet written
**Created:** 2026-06-10 (Phase 4 completion audit)
**Predecessor:** Phase 4 — Production Migration (`docs/phase-4-production-migration.md`)

This is a placeholder created at Phase 4 closeout. The full parent plan
(sub-deploy index, sequencing, completion criteria) is written when Phase 5
planning begins. Scope bullets below are carried verbatim from the Phase 4
parent plan § Out of Scope and `CLAUDE.md` § Current Migration Phase.

---

## Scope (from Phase 4 deferrals)

- **Hosting migration** (GitHub Pages → Cloudflare Pages or Vercel) — required
  before subdomain-based tenant routing
- **Per-tenant branding rendering** — `tenants.branding` jsonb column exists;
  no UI reads it
- **Self-service tenant signup** — public flow for a second bookstore to
  register, claim a slug, configure their account
- **Slug→id mapping via RPC** — replace hardcoded `TENANT_SLUG_MAP` in `app.js`
- **`register-customer` Edge Function tenant resolution** — currently
  hard-pinned to `FOUNDING_TENANT_ID` (F34 documented status); must be
  revisited before tenant 2 onboards

## Carry-forward candidates (filed during Phase 4, not yet scheduled)

To be triaged into the Phase 5 parent plan or a pre-Phase-5 housekeeping
sub-deploy when planning begins — see `technical-reference.md` § 13 for
current status:

- F58 — `user_profiles` admin-write policy parity (staging audit)
- F63 — staging RLS policies missing `TO authenticated` (staging-only DDL)
- F64 — pre-Phase-4 DDL divergences (per-item dispositions in the finding)
- F65 — `subscriptions.html` unsubscribe `window.confirm()` (same class as F61)
- F66 — `delete_dropped_catalog_items` missing preorder guard (latent; fix
  paired with F64 item 4 prod FK alignment)

---

**Last updated:** 2026-06-10 (stub created at Phase 4 completion audit)
