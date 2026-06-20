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

## Operational note (from S3 Deploy Log)

`create-paper-customer` and `invite-customer` Edge Functions retain the F34 residual partial tenant-awareness: they write to `FOUNDING_TENANT_ID` regardless of the calling admin's tenant. **Do NOT use these EFs from the Comic Store admin dashboard during the pilot** — customers would land in the founding tenant, not tenant 2. If pilot customers must be added, use a service-role INSERT directly into `user_profiles` scoped to tenant 2's id, or wait for a dedicated fix (post-Phase 5).

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
| Abbreviated isolation probe — founding → tenant-2 (high-traffic tables) | PENDING — Rick SQL Editor | See § Abbreviated probe SQL below |
| Abbreviated isolation probe — tenant-2 → founding (high-traffic tables) | PENDING — Rick SQL Editor | See § Abbreviated probe SQL below |
| Branding-by-host spot-check | PENDING — Claude curl | `pulllist.app` + `comicstore.pulllist.app` HTTP status |
| Founding Playwright (19/19) | PENDING — Claude run | `.\run-smoke.ps1` from playwright dir |
| Customer-reported issues | None expected | Tenant 2 is pilot/seeded; no real customers |

---

### Abbreviated isolation probe SQL (for Rick — prod SQL Editor)

> **PAUSE → Rick (PROD SQL Editor):**
>
> Run each block in a separate transaction. Substitute `<founding-admin-uuid>` and `<tenant2-admin-uuid>` from your local scratch file (these are the `sub` values in the JWT claims for the respective admins).
>
> **Block 1 — founding admin view of tenant-2 rows (expected: all 0):**
> ```sql
> BEGIN;
> SET LOCAL role TO authenticated;
> SET LOCAL "request.jwt.claims" TO '{"sub": "<founding-admin-uuid>", "role": "authenticated"}';
> SELECT
>   (SELECT COUNT(*) FROM public.preorders     WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'comicstore')) AS t2_preorders,
>   (SELECT COUNT(*) FROM public.user_profiles WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'comicstore')) AS t2_profiles,
>   (SELECT COUNT(*) FROM public.catalog       WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'comicstore')) AS t2_catalog,
>   (SELECT COUNT(*) FROM public.subscriptions WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'comicstore')) AS t2_subscriptions;
> ROLLBACK;
> ```
>
> **Block 2 — tenant-2 admin view of founding rows (expected: all 0):**
> ```sql
> BEGIN;
> SET LOCAL role TO authenticated;
> SET LOCAL "request.jwt.claims" TO '{"sub": "<tenant2-admin-uuid>", "role": "authenticated"}';
> SELECT
>   (SELECT COUNT(*) FROM public.preorders     WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'rjbookstop')) AS founding_preorders,
>   (SELECT COUNT(*) FROM public.user_profiles WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'rjbookstop')) AS founding_profiles,
>   (SELECT COUNT(*) FROM public.catalog       WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'rjbookstop')) AS founding_catalog,
>   (SELECT COUNT(*) FROM public.subscriptions WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'rjbookstop')) AS founding_subscriptions;
> ROLLBACK;
> ```
>
> **Expected for both blocks:** all columns = 0.
> **STOP + file (F76+)** on any non-zero — do not continue without investigation.
> **Paste:** both result rows (counts only, no sensitive data).

---

*Next entry: abbreviated probe results + Playwright result (once obtained).*

*Next major gate: monthly prod import (expected early July 2026). When Rick runs the import, paste the import summary → Claude prepares post-import isolation re-verification SQL → Rick pastes counts → if all 0, close gate passed → S4 complete → proceed to S5.*
