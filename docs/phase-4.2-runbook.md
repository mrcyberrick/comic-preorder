# Runbook — Phase 4.2 Production Schema (Additive)

**CLI-orchestrated, Rick-in-the-loop.** A Claude Code CLI session runs this top to bottom. It
**executes the repo/doc steps itself** and **pauses at every production-database step**, handing
the SQL to Rick to run in the Supabase SQL Editor and waiting for pasted results before
continuing. Self-contained — no chat context required.

**Plan / rationale:** `docs/phase-4.2-prod-schema-additive.md`
**Baseline:** `docs/production-baseline-2026-05-28.md`

---

## ⛔ IMMUTABLE EXECUTION RULES (CLI: read first, never violate)

1. **You have NO production database access.** Do not open a psql/pg connection, do not use the
   Supabase CLI, do not write or run a script that connects to `plgegklqtdjxeglvyjte`, do not
   touch the service role key. There is no path from this CLI session to production. Attempting
   one is a hard failure.
2. **You execute ONLY repo/filesystem steps** (marked `[CLI]`). Every step marked `[RICK→SQL]`
   is run by Rick in the production SQL Editor. For those steps you **print the SQL block, stop,
   and wait** for Rick to paste the result back into this session.
3. **Do not improvise around a pause.** If you cannot proceed without a prod result, that is
   correct — stop and wait. Never synthesize, assume, or fabricate a SQL result.
4. **Verify before advancing.** After Rick pastes a result, compare it to the block's "Expect"
   line. If it does not match, **halt the window** and follow § Rollback. Do not continue.
5. **Stay in scope.** Surface anything off-plan as a finding; do not fix inline. See § Out of scope.
6. **Maintenance mode is ON the entire run.** No customer writes occur.

Owner legend:  `[CLI]` CLI executes · `[RICK→SQL]` Rick runs in prod SQL Editor · `[RICK]` Rick manual action.

---

## STEP 0 — Housekeeping commit  `[CLI]`

Branch: commit to `staging` (NOT the cutover branch). Doc-only.

0.1 Place `production-baseline-2026-05-28.md`, `phase-4.2-prod-schema-additive.md`, and this
    runbook in `docs/`.
0.2 Apply the doc corrections:
    - `CLAUDE.md` L19 — confirm baseline filename reference matches the committed name.
    - `CLAUDE.md` — replace any "production has 7 tables" wording with: "9 base tables
      (`app_settings` and `usage_events` already present); only `tenants` and `tenant_id`
      columns are missing."
    - `phase-4-production-migration.md` § In Scope L142 — "create app_settings/usage_events" →
      "add tenant_id to all 9 existing tables (both already exist on prod)."
    - `phase-4-production-migration.md` carry-forward item 9 — mark corrected (no table gap).
    - `phase-4-production-migration.md` § In Scope L148 — analytics views + `admin_preorders`
      already exist; 4.4 retrofits, not creates.
0.3 Commit:
    `git add docs/ CLAUDE.md && git commit -m "docs(phase-4.2): production baseline + correct 7→9 table premise; add 4.2 plan/runbook"`
0.4 **Do not push to origin main.** Leave on `staging` for Rick to PR.

**CLI: report the commit hash, then continue to Step 1.**

---

## STEP 1 — Pre-flight gates  `[RICK→SQL]` + `[RICK]`

**CLI: print the following to Rick, then STOP and wait for results.**

> Rick — run in the **production** SQL Editor (`plgegklqtdjxeglvyjte`) and paste back all three
> result sets. Also confirm the two manual items.

```sql
-- PF1: maintenance mode ON
SELECT value FROM public.app_settings WHERE key = 'maintenance_mode';

-- PF4: founding admin present and flagged
SELECT id, is_admin, status FROM public.user_profiles
WHERE id = '734bfd7e-23a6-4c23-ba35-1f64843603c0';

-- PF6: live still matches baseline
SELECT table_name FROM information_schema.tables
WHERE table_schema='public' AND table_type='BASE TABLE' ORDER BY table_name;
SELECT count(*) AS tenant_id_cols FROM information_schema.columns
WHERE table_schema='public' AND column_name='tenant_id';
```

**Expect:** PF1 → `true` · PF4 → `is_admin=true, status=active` · PF6 → 9 base tables
(app_settings, catalog, preorders, reservation_history, settings, subscriptions, usage_events,
user_profiles, weekly_shipment), **no `tenants`**, `tenant_id_cols = 0`.

**Manual (Rick confirms in chat):**
- **PF2** fresh prod snapshot taken, stored with `pre-multitenancy-v1`.
- **PF3** `scripts/phase-4-prod-tenant-uuid.txt` exists, one v4 UUID, **not**
  `72e29f67-39f7-42bc-a4d5-d6f992f9d790`. **Rick: paste the UUID into chat — it's needed for Step 3.**

**CLI: when Rick returns results — verify every Expect line. Any mismatch → STOP, do not proceed.
All pass → continue to Step 2. Record the PF3 UUID for Step 3 substitution.**

---

## STEP 2 — Create `tenants`  `[RICK→SQL]`

**CLI: print to Rick, STOP, wait.**

```sql
CREATE TABLE IF NOT EXISTS public.tenants (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug          text NOT NULL UNIQUE,
  display_name  text NOT NULL,
  contact_email text,
  contact_phone text,
  location      text,
  plan          text NOT NULL DEFAULT 'free',
  branding      jsonb DEFAULT '{}'::jsonb,
  settings      jsonb DEFAULT '{}'::jsonb,
  created_at    timestamptz DEFAULT now(),
  updated_at    timestamptz DEFAULT now()
);

-- verify
SELECT to_regclass('public.tenants');
```

**Expect:** `to_regclass` → `tenants` (not null). **CLI: verify, then continue.**

---

## STEP 3 — Founding tenant row  `[RICK→SQL]`

**CLI: substitute the PF3 UUID into `<<PROD_TENANT_UUID>>` below (it appears once), print to
Rick, STOP, wait.** If you do not have the UUID from Step 1, STOP and ask Rick for it — do not
invent one.

```sql
INSERT INTO public.tenants (id, slug, display_name)
VALUES ('<<PROD_TENANT_UUID>>', 'rjbookstop', 'Ray & Judy''s Book Stop')
ON CONFLICT (slug) DO NOTHING;

-- verify
SELECT id, slug, display_name FROM public.tenants WHERE slug = 'rjbookstop';
```

**Expect:** exactly 1 row; `id` equals the scratch-file UUID. **CLI: verify id matches, continue.**

---

## STEP 4 — tenant_id + backfill + index, all 9 tables  `[RICK→SQL]`

**CLI: print the full block to Rick, STOP, wait.** Idempotent; backfill resolves id by slug.

```sql
-- C3 user_profiles
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS tenant_id uuid;
UPDATE public.user_profiles SET tenant_id=(SELECT id FROM public.tenants WHERE slug='rjbookstop') WHERE tenant_id IS NULL;
CREATE INDEX IF NOT EXISTS idx_user_profiles_tenant ON public.user_profiles (tenant_id);
-- C4 catalog
ALTER TABLE public.catalog ADD COLUMN IF NOT EXISTS tenant_id uuid;
UPDATE public.catalog SET tenant_id=(SELECT id FROM public.tenants WHERE slug='rjbookstop') WHERE tenant_id IS NULL;
CREATE INDEX IF NOT EXISTS idx_catalog_tenant ON public.catalog (tenant_id);
-- C5 preorders
ALTER TABLE public.preorders ADD COLUMN IF NOT EXISTS tenant_id uuid;
UPDATE public.preorders SET tenant_id=(SELECT id FROM public.tenants WHERE slug='rjbookstop') WHERE tenant_id IS NULL;
CREATE INDEX IF NOT EXISTS idx_preorders_tenant ON public.preorders (tenant_id);
-- C6 subscriptions
ALTER TABLE public.subscriptions ADD COLUMN IF NOT EXISTS tenant_id uuid;
UPDATE public.subscriptions SET tenant_id=(SELECT id FROM public.tenants WHERE slug='rjbookstop') WHERE tenant_id IS NULL;
CREATE INDEX IF NOT EXISTS idx_subscriptions_tenant ON public.subscriptions (tenant_id);
-- C7 reservation_history
ALTER TABLE public.reservation_history ADD COLUMN IF NOT EXISTS tenant_id uuid;
UPDATE public.reservation_history SET tenant_id=(SELECT id FROM public.tenants WHERE slug='rjbookstop') WHERE tenant_id IS NULL;
CREATE INDEX IF NOT EXISTS idx_reservation_history_tenant ON public.reservation_history (tenant_id);
-- C8 weekly_shipment
ALTER TABLE public.weekly_shipment ADD COLUMN IF NOT EXISTS tenant_id uuid;
UPDATE public.weekly_shipment SET tenant_id=(SELECT id FROM public.tenants WHERE slug='rjbookstop') WHERE tenant_id IS NULL;
CREATE INDEX IF NOT EXISTS idx_weekly_shipment_tenant ON public.weekly_shipment (tenant_id);
-- C9 settings
ALTER TABLE public.settings ADD COLUMN IF NOT EXISTS tenant_id uuid;
UPDATE public.settings SET tenant_id=(SELECT id FROM public.tenants WHERE slug='rjbookstop') WHERE tenant_id IS NULL;
CREATE INDEX IF NOT EXISTS idx_settings_tenant ON public.settings (tenant_id);
-- C10 app_settings
ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS tenant_id uuid;
UPDATE public.app_settings SET tenant_id=(SELECT id FROM public.tenants WHERE slug='rjbookstop') WHERE tenant_id IS NULL;
CREATE INDEX IF NOT EXISTS idx_app_settings_tenant ON public.app_settings (tenant_id);
-- C11 usage_events
ALTER TABLE public.usage_events ADD COLUMN IF NOT EXISTS tenant_id uuid;
UPDATE public.usage_events SET tenant_id=(SELECT id FROM public.tenants WHERE slug='rjbookstop') WHERE tenant_id IS NULL;
CREATE INDEX IF NOT EXISTS idx_usage_events_tenant ON public.usage_events (tenant_id);
```

**Expect:** no errors. **CLI: on clean run, continue to Step 5 (verification).**

---

## STEP 5 — Verification gate V1–V5  `[RICK→SQL]`

**CLI: print to Rick, STOP, wait. This is the pass/fail gate for 4.2.**

```sql
-- V1
SELECT count(*) FROM public.tenants;
SELECT id FROM public.tenants WHERE slug='rjbookstop';
-- V2
SELECT table_name FROM information_schema.columns
WHERE table_schema='public' AND column_name='tenant_id' ORDER BY table_name;
-- V3 (every value must be 0)
SELECT 'user_profiles' t, count(*) c FROM public.user_profiles WHERE tenant_id IS NULL
UNION ALL SELECT 'catalog',             count(*) FROM public.catalog             WHERE tenant_id IS NULL
UNION ALL SELECT 'preorders',           count(*) FROM public.preorders           WHERE tenant_id IS NULL
UNION ALL SELECT 'subscriptions',       count(*) FROM public.subscriptions       WHERE tenant_id IS NULL
UNION ALL SELECT 'reservation_history', count(*) FROM public.reservation_history WHERE tenant_id IS NULL
UNION ALL SELECT 'weekly_shipment',     count(*) FROM public.weekly_shipment     WHERE tenant_id IS NULL
UNION ALL SELECT 'settings',            count(*) FROM public.settings            WHERE tenant_id IS NULL
UNION ALL SELECT 'app_settings',        count(*) FROM public.app_settings        WHERE tenant_id IS NULL
UNION ALL SELECT 'usage_events',        count(*) FROM public.usage_events        WHERE tenant_id IS NULL;
-- V4
SELECT indexname FROM pg_indexes
WHERE schemaname='public' AND indexname LIKE 'idx_%_tenant' ORDER BY indexname;
-- V5 (must equal pre-cutover snapshot)
SELECT 'user_profiles' t, count(*) c FROM public.user_profiles
UNION ALL SELECT 'catalog',             count(*) FROM public.catalog
UNION ALL SELECT 'preorders',           count(*) FROM public.preorders
UNION ALL SELECT 'subscriptions',       count(*) FROM public.subscriptions
UNION ALL SELECT 'reservation_history', count(*) FROM public.reservation_history
UNION ALL SELECT 'weekly_shipment',     count(*) FROM public.weekly_shipment
UNION ALL SELECT 'settings',            count(*) FROM public.settings
UNION ALL SELECT 'app_settings',        count(*) FROM public.app_settings
UNION ALL SELECT 'usage_events',        count(*) FROM public.usage_events;
```

**Expect:** V1 → 1 row, id = scratch UUID · V2 → the 9 tables · V3 → all `0` · V4 → 9 indexes ·
V5 → `19 / 6399 / 680 / 3 / 81 / 443 / 2 / 2 / 373`.

**CLI: verify all five. Any mismatch → STOP, § Rollback. All pass → Step 6.**

---

## STEP 6 — Smoke + close-out  `[RICK]` then `[CLI]`

6.1 `[RICK]` Load prod as admin (maintenance ON): pages render, no console errors, banner shows
    for non-admin. Confirm in chat.
6.2 `[CLI]` After Rick confirms 6.1, on `staging`: update the parent-plan Sub-Deploys table —
    4.2 row → done/window-checkpoint. Commit:
    `git commit -am "docs(phase-4.2): mark 4.2 prod additive schema complete"`
6.3 `[CLI]` Report: commit hashes (Step 0, Step 6), the V5 counts Rick confirmed, and the
    standing carry-forward (below) for the next Opus session. **Then stop — 4.3 is a separate
    planning session.**

---

## Rollback (Tier 1 — additive, no customer writes)  `[RICK→SQL]`

**CLI: if invoked, print to Rick, STOP. Do not run.**

```sql
ALTER TABLE public.usage_events        DROP COLUMN IF EXISTS tenant_id;
ALTER TABLE public.app_settings        DROP COLUMN IF EXISTS tenant_id;
ALTER TABLE public.settings            DROP COLUMN IF EXISTS tenant_id;
ALTER TABLE public.weekly_shipment     DROP COLUMN IF EXISTS tenant_id;
ALTER TABLE public.reservation_history DROP COLUMN IF EXISTS tenant_id;
ALTER TABLE public.subscriptions       DROP COLUMN IF EXISTS tenant_id;
ALTER TABLE public.preorders           DROP COLUMN IF EXISTS tenant_id;
ALTER TABLE public.catalog             DROP COLUMN IF EXISTS tenant_id;
ALTER TABLE public.user_profiles       DROP COLUMN IF EXISTS tenant_id;
DROP TABLE IF EXISTS public.tenants;
```

After rollback: maintenance stays ON, abort window, post-mortem before retry.

---

## Out of scope — CLI must NOT do, even if it looks easy

- No `NOT NULL`, FK, unique-key change, or `tenants` slug CHECK (→ 4.3)
- No RLS / view / function / default changes (→ 4.3, 4.4)
- No PRH `weekly_shipment` partial index (→ 4.5/4.6)
- No `import.js` change (→ 4.5); do not drop `claim_paper_account` (deferred)
- **No production DB connection of any kind.** Prod SQL is Rick's, always.

---

## Carry-forward to next Opus session (4.3 planning)

Hand a new Opus session: updated `CLAUDE.md`, `technical-reference.md`,
`phase-4-production-migration.md`, the committed `production-baseline-2026-05-28.md`, this
session's 4.2 result, **plus two live prod pulls** (Rick runs, pastes to Opus):
- `SELECT pg_get_functiondef('public.is_admin'::regproc);`
- `SELECT indexname, indexdef FROM pg_indexes WHERE schemaname='public' ORDER BY tablename, indexname;`

4.3 scope: tenant_id→tenants FKs (×9), NOT NULL (×9), tenant-aware unique on catalog +
subscriptions, tenants_slug_format_check, admin_preorders recreation, RLS recursion fix across
**7** policies, reconcile is_admin() vs current_user_is_admin().
