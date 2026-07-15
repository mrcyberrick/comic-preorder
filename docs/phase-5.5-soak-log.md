# Phase 5.5 — Two-Tenant Production Soak Log

**Parent plan:** `docs/phase-5-second-tenant-onboarding.md`
**Sub-deploy plan:** `docs/phase-5.5-second-tenant-onboarding.md`
**Soak definition:** One full monthly prod import cycle with both tenants present + post-import isolation re-verification = 0 in both directions (decision: Rick, 2026-06-17; no extra buffer — § 1.4)
**Soak opened:** 2026-06-20 (S3 green 2026-06-19)
**Expected close:** Early–mid July 2026, after the monthly prod import runs (anchor: "within ~2 weeks" of 2026-06-19 — Rick, 2026-06-19 § 1.7)

---

## Tenant inventory

| Role | Slug | Tenant ID | Notes |
|---|---|---|---|
| Founding | `rjbookstop` | `20941129-c35a-476d-ae21-44b8f77af89c` | Unchanged throughout Phase 5 |
| Tenant 2 | `comicstore` | `6f6ef2c3-…` (full UUID in local scratch file) | Created via `register-tenant` on prod 2026-06-19 (S2); pilot/seeded — no real customer writes during soak |

---

## Rollback note

Tenant 2 is **pilot/seeded only** throughout this soak (decision: Rick, 2026-06-17). The §4.1 FK-ordered teardown (`docs/phase-4.1-canary-procedure.md`) remains a clean rollback for the entire soak window. Real-customer go-live is the post-close operational step (§ S5 runbook). Flipping this to real-customer writes during the soak is a scope/rollback-tier change — STOP and ask.

---

## Operational note (from S3 Deploy Log) — corrected 2026-07-15 (S6 closeout)

**Correction:** the original S3 note below claimed `create-paper-customer` and `invite-customer` write to `FOUNDING_TENANT_ID` regardless of the calling admin's tenant. That description matched pre-2026-05-10 behavior; the F34 fix (commit `7ea592c`, 2026-05-10) resolves `tenant_id` from the caller's own profile (`callerTenantId`, falling back to `FOUNDING_TENANT_ID` only if the profile lookup fails) and was live on both envs well before S3 ran. Re-verified against deployed source at S6 closeout (2026-07-15) — see `docs/technical-reference.md` § 13 F34. **Both EFs are safe to use from the Comic Store admin dashboard.** Original (incorrect) note preserved below for the record:

> `create-paper-customer` and `invite-customer` Edge Functions retain the F34 residual partial tenant-awareness: they write to `FOUNDING_TENANT_ID` regardless of the calling admin's tenant. **Do NOT use these EFs from the Comic Store admin dashboard during the pilot** — customers would land in the founding tenant, not tenant 2. If pilot customers must be added, use a service-role INSERT directly into `user_profiles` scoped to tenant 2's id, or wait for a dedicated fix (post-Phase 5).

---

## Close gate (all must be true before S4 complete)

1. ≥ 1 complete monthly prod import has run with both tenants present (founding `import.js`, founding-pinned)
2. Founding import touched only founding rows; tenant-2 seeded data unchanged post-import
3. **Post-import** abbreviated isolation re-verification = 0 in both directions (founding ↔ tenant-2, across high-traffic tables at minimum)
4. Founding Playwright green (19/19) after the import
5. Founding write-smoke clean post-import (reserve + cancel on `pulllist.app`)
6. No customer-reported regressions across the soak span

---

## Soak observations

### S4 opening — 2026-06-20

**State inherited from S3 (2026-06-19):**
- Both tenants live on prod: founding (`rjbookstop`) + tenant 2 (`comicstore`, `comicstore.pulllist.app` Active, TLS issued)
- Tenant-2 seeded data: 2 catalog rows (TCS-001/TCS-002, `Lunar`, `Standard`, `2026-06`); 0 real customers; 0 preorders
- S3 full isolation matrix (both directions, 7 tables): all = 0 ✓
- Branding-by-host: `comicstore.pulllist.app` → `#00FF00`/Comic Store; `pulllist.app` → founding ✓
- `register-customer` with tenant-2 webhook secret → tenant-2 `user_profiles` (probe row deleted) ✓
- Playwright 19/19 green (S3 gate) ✓

**Opening observations (this session, 2026-06-20):**

| Check | Result | Notes |
|---|---|---|
| Row-count isolation probe (superuser) | ✓ PASS | See counts below; no cross-tenant drift in either direction |
| Branding-by-host spot-check | ✓ | `pulllist.app` → HTTP 200; `comicstore.pulllist.app` → HTTP 200 |
| Founding Playwright (19/19) | ✓ 19/19 | All specs green incl. F15/F20 + branding unit tests; import regression 5/5; synthetic tenant created + torn down cleanly |
| Customer-reported issues | None | Tenant 2 pilot/seeded; no real customers |

**Row counts (prod SQL Editor, superuser, 2026-06-20):**

| total_tenants | founding_profiles | t2_profiles | founding_catalog | t2_catalog | founding_preorders | t2_preorders |
|---|---|---|---|---|---|---|
| 2 | 19 | 1 | 11116 | 2 | 801 | 0 |

- `total_tenants = 2` ✓ (founding + comicstore only; no extra tenants)
- `t2_catalog = 2` ✓ (TCS-001/TCS-002 from S3 seeding — unchanged)
- `t2_profiles = 1` ✓ (Comic Store admin only; no real customers)
- `t2_preorders = 0` ✓
- Founding rows at normal production levels; no tenant-2 data found in founding tables
- Note: isolation probe was superuser row-count level (no `SET LOCAL` RLS simulation); full RLS simulation was completed in S3 and will repeat at S4.3 import close gate
- Note: `founding_profiles = 19` is the production value (staging had 109 in S1 — different environment)

---

*Next major gate: **monthly prod import (expected early July 2026)**. When Rick runs the normal founding monthly import, paste the import summary → Claude prepares post-import isolation re-verification SQL → Rick pastes counts → if all clean, S4 close gate passed → proceed to S5.*

*For post-import re-verification, use the superuser row-count probe above plus a founding-catalog + founding-preorders sanity check that tenant-2 seeded rows are unchanged. Full RLS simulation (SET LOCAL) will be attempted via the SQL Editor; if it fails again, superuser counts + the confirmed-clean S3 baseline together constitute the pass evidence.*
