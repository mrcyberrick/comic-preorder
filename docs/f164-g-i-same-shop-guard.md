# F164 guard (session G-I): the import reads only its own shop's rows, then a same-shop trigger on `preorders`

**STATUS:** APPROVED 2026-11-11 (Rick: "Defaults"), NOT STARTED · plan written 2026-11-11 · staging: — · prod: — · PR: — (S1 = scripts repo, no PR flow; S2 = SQL only, Rick-run) · findings: F164, F181 (filed while planning)

Plan written 2026-11-11 (planning session). Owner finding: `docs/technical-reference.md` § 13 F164 (Medium, OPEN).
Design source: `docs/pre-phase-6-gate-closure.md` § 2e "G-I". This doc turns that design into two executable
sessions, adds what the 2026-11-11 code read found, and records the blocker check. Closing it closes Phase 6 gate
**G8**.

**Two sessions, in this order, never combined:**

- **S1 (scripts repo):** `autoReserveSubscriptions()` reads only the import tenant's subscriptions and catalog rows,
  and `matchSubscriptions()` refuses any other shop's row even if a read regresses. Both `import.js` and
  `import-staging.js`. No app, SQL or production write.
- **S2 (one SQL migration, both environments, Rick-run):** a `BEFORE INSERT OR UPDATE` trigger on `preorders` that
  refuses a reservation whose listing, or (D1) whose customer, belongs to another shop. No app or script change.
  Two sittings: **S2a staging**, **S2b production**.

**Date gates apply to production steps only (Rick, 2026-11-11: "Reminders apply to Production scripts but staging
can be managed outside these restrictions").** Staging work runs whenever it is ready. What waits for a date:
merging S1 to the scripts repo's `main` (that changes the production `import.js`) and S2b.

**Why the order matters** (§ 2e item 3, unchanged): with the trigger first, the importer's batched `POST` fails as a
whole on any environment holding a second shop's matching rows, and the script prints "Auto-reserve batch failed"
and carries on, so every subscriber in that batch silently gets nothing.

---

## 1. Blocker check (2026-11-11): none

| Item | Result |
|---|---|
| "Scripts half waits for the November import" | **Cleared.** The November new-month import ran on production 2026-10-28. |
| Scripts repo state | `main` == `origin/main`, clean, HEAD `271e824` (F180). |
| The two unfiltered reads | **Still present, unchanged:** `import.js:999` (subscriptions) and `:1021` (the month's catalog); `import-staging.js:998` / `:1020`. |
| Every other service-role read in both scripts (§ 2e asked for this audit) | **Done by reading all 32 REST calls per script (the two scripts' call lines are identical).** Every other read filters on `tenant_id=eq.${TENANT_ID}` or takes its ids from a read that does (`:1044` / `:1081` preorders by this tenant's catalog ids, `:1259` from `:1585`, `:1297` from `:1277`). Every RPC call passes `p_tenant_id`. Every insert or upsert body carries `tenant_id`; every PATCH targets ids from a tenant-filtered read. So the fix is the two reads plus the matcher, nothing else. `check-dates.js` was also read: tenant-filtered throughout, never writes `preorders`, out of scope. |
| Who else writes `preorders.catalog_id` / `tenant_id` / `user_id` (would a correct trigger refuse a legitimate write?) | **No.** `app.js` `reserve()` / `upsertReservation()` / `bulkUpsert()` take `catalog_id` from catalog rows the caller's RLS can see and stamp `TenantContext`'s tenant (and RLS already requires that tenant to be the caller's). `admin_move_reservations()` (F173) re-checks both listings against `current_tenant_id()` (its SQL file, lines 138 / 142 / 197). `dedupe_catalog_months()` deletes catalog rows and never updates `preorders`. Quantity, fulfilment, `arrival_outcome` and `unavailable_dismissed_at` updates do not name the trigger's columns, so they do not fire it. |
| Playwright fixtures | `seedPreorder()` callers pair each tenant with its own catalog row (spec 07 seeds A-with-A and B-with-B). The full-suite run after the trigger is the check (S2 gate T8). |
| The only existing `preorders` trigger | F109's `trg_preorders_block_ordered_delete`, `BEFORE DELETE`. No interaction. |
| Production exposure today | Latent, not live (§ 2e). The interim rule (two read-only queries before any import) stays in force until § 5 retires it. |

**Not blockers, sequencing only:** F180's first real exercise is Rick's Fri 2026-11-13 import, which runs the same
`import.js` (auto-reserve is Step 5 and runs on every non-backfill import, weekly ones included). G-G (F169 / F157)
edits the same files and is not started; it goes after G-I.

---

## 2. Decisions (ANSWERED 2026-11-11, Rick: "Defaults", plus the production-only date rule above)

| # | Question | Answer |
|---|---|---|
| D1 | Should the trigger also refuse a reservation whose **customer** belongs to another shop, not only one whose listing does? | **Yes.** The same unfiltered subscriptions read that produced F164's rows also produces this shape (another shop's subscriber matched against our listing, stamped with our tenant), and so does `claim-paper-customer` (§ 2.1, F181). G-D's own method note says the sweep had to compare the owner's tenant too. The cost is one primary-key lookup per row and `user_id` in the column list. **This extends § 2e's design**, which checked the listing only. |
| D2 | When does S1 run? | **Now (staging is not date-gated).** Steps 1-6 (code, tests, the staging harness) run any day. **Step 7, the merge to scripts `main`, waits until Rick has read the Fri 2026-11-13 import's output (F180 V3)**, so F180's first real run uses code changed only by F180. If S1 finishes earlier, the branch is pushed and left unmerged, and the folder goes back to `main`. |
| D3 | When does S2 run? | **S2a (staging) once S1's staging gates are green.** **S2b (production) on or after Sat 2026-11-21, after the first production weekly import on S1's merged code (expected Fri 2026-11-20) reads normal (§ 5).** |
| D4 | `claim-paper-customer` checks neither account's shop (§ 2.1). File it? | **Filed as F181 (2026-11-11), not fixed in G-I.** D1's trigger closes only its `preorders` half. |

**One staging caution that follows from D2 + D3.** S2a can land on staging before S1 is merged, while scripts
`main` still holds the old `import-staging.js`. A staging import run from `main` in that window could match another
shop's rows and lose a whole auto-reserve batch to the trigger. So **until S1 is merged, run the § 2e interim
queries before any staging import too** (on 2026-10-06 demoshop held catalog rows for 2026-09 only, so a
current-month staging import cannot match them; re-read rather than assume).

### 2.1 Found while planning: FILED as F181 (2026-11-11, D4)

`supabase/functions/claim-paper-customer/index.ts` verifies the caller is an admin and reads the caller's tenant,
then reads `paper_user_id` (`:71`) and `real_user_id` (`:97`) from `user_profiles` by id with the service role and **no tenant filter**.
The three reassignments filter the source rows by the caller's tenant (`preorders` `:121`, `subscriptions` `:145`,
`reservation_history` `:173`) but never check that `real_user_id` belongs to that tenant, and the final deletes of
the paper profile (`:227`) and the paper auth user (`:242`) have no tenant filter at all. So an admin of shop A who
has a UUID from shop B could move A's reservations onto B's customer, or delete B's paper account (if it holds no
reservations, which the `user_id` foreign key would otherwise block). **Read from code, not tested.** Needs a
foreign UUID, which RLS hides. Severity guess: Low today, Medium at tenant N+1, the same shape as F164's API path.
S2's trigger (with D1) refuses the `preorders` move; the subscriptions and history moves and the deletes remain.
Fix direction: the function reads both profiles with `tenant_id=eq.${callerTenantId}` and returns 404 otherwise.
Different from the unfiled "silently orphans data on a user_id overlap" note in memory.

---

## 3. Session S1: the import reads (scripts repo)

The scripts folder is **the working tree Rick runs imports from**. Do the work on a feature branch, and end the
session on `main`, clean, and pushed (or, if anything fails, back on `main` with the branch left unmerged). Never
leave the folder on a feature branch: the next import would run that branch's code.

**Step 0.** `/preflight`. Confirm the scripts repo is on `main`, clean, equal to `origin/main` (HEAD `271e824` or
later). Re-measure the unit baseline (`npm test`; 449/449 at F180, 2026-11-09). Branch:
`feature/f164-import-tenant-reads`. Steps 1-6 are staging-only and run any day (D2).

**Step 1. Re-run the audit** in § 1 (grep every `rest/v1/` line in both scripts; diff the two lists). Expected:
exactly the two unfiltered reads. Anything else is halt-and-report.

**Step 2. Commit A: export only, no behaviour change.** Add `autoReserveSubscriptions` to `module.exports` in both
scripts (the harness in Step 5 calls the real function; `main()` is already behind `require.main === module`).
`npm test` unchanged. This commit exists so the control in Step 5 runs against the **old** behaviour.

**Step 3. Commit B: the fix, byte-identical in both scripts' changed regions** (the unit suite runs every `matchSubscriptions` test against both scripts; diff the two scripts' changed regions as well):

1. Subscriptions read: `subscriptions?tenant_id=eq.${TENANT_ID}&select=user_id,series_name,distributor,format,tenant_id`.
2. Catalog read: `catalog?tenant_id=eq.${TENANT_ID}&catalog_month=eq.${catalogMonth}&select=id,tenant_id,series_name,distributor,title,variant_type,format,item_code&order=series_name`.
3. **A missing `tenant_id` stops auto-reserve loudly:** if any fetched subscription or catalog row has no `tenant_id`,
   print `⚠️  ... rows arrived without tenant_id — skipping auto-reserve (F164).` and return, the same shape as the
   existing page-failure skip. A select list that loses `tenant_id` must not silently match nothing.
4. `matchSubscriptions()` keeps only `sub.tenant_id === tenantId` and `c.tenant_id === tenantId` (strict equality;
   missing counts as another shop) **before** matching, so `find()` can never pick another shop's row, and the
   carry-forward `match.id` comes from the same filtered list. Return `ignoredSubscriptions` and `ignoredItems`;
   `autoReserveSubscriptions()` prints `Ignored N subscription(s) and M catalog row(s) from other shops (F164).`
   **only when either is above 0**. With the read filters in place that line never prints; if it ever does, a read
   filter has regressed.
5. Docblock on both functions names F164.

**Step 4. Unit tests** in `test/builders.test.mjs` (its `[${name}]` loop runs both scripts):
- two shops with the same `series_name` and `distributor`, the **other shop's row listed first** (so an unguarded
  `find()` picks it): a tenant-1 subscription matches tenant-1's row;
- a tenant-2 subscription against a tenant-1 row: not matched, `ignoredSubscriptions` 1;
- a row with no `tenant_id` counts as another shop;
- carry-forward with the other shop's row listed first: carries forward onto tenant-1's row;
- the three existing `matchSubscriptions` tests gain `tenant_id: 'tenant-1'` on their fixtures.

**Negative control:** remove the step-3.4 filter, see the new tests go red (record which), restore, see green.
Full `npm test`: baseline + the new tests, all green.

**Step 5. Live check on STAGING through the real function** (local harness `playwright/f164-autoreserve-verify.mjs`,
gitignored, requires `import-staging.js`; refuses to run unless `SUPABASE_URL` is the staging ref).

- **Fixture month `2000-01`**: first read that it holds 0 catalog rows for every tenant (halt otherwise). A past month
  cannot become anyone's "latest month", and the carry-forward read (`catalog_month < 2000-01`) finds nothing.
- Fixture: series `ZZTEST164 <run id>`, distributor `Lunar`, standard cover, a format `isComicFormat()` accepts;
  item codes `ZZTEST164-<run>-F` (founding) and `-D` (demoshop); a throwaway **founding** customer and a throwaway
  **demoshop** customer (the `fixtures/auth.ts` `createUser` shape), each subscribed (own `tenant_id`, `format` null).
  Read `docs/technical-reference.md` for `catalog` / `subscriptions` required columns before writing any seed
  (`/sql-check`); dry-fit one row first.
- `NO_WRITE` is fixed when the module loads, so each phase is its own process (`node f164-autoreserve-verify.mjs --phase=… [--no-write]`):

| Phase | Code | Catalog rows in `2000-01` | Mode | Expected auto-reserve line |
|---|---|---|---|---|
| C1 (control) | commit A | demoshop row only | `--no-write` | **Matched 1, To insert 1** (the founding subscriber matched another shop's listing: F164's mechanism, reproduced) |
| C2 (control) | commit A | founding row only | `--no-write` | **Matched 2, To insert 2** (the demoshop subscriber matched too: the owner shape, D1) |
| F1 | commit B | demoshop row only | `--no-write` | Matched 0, To insert 0 |
| F2 | commit B | founding row only | `--no-write` | Matched 1, To insert 1 |
| F3 | commit B | both rows | **write** | exactly 1 preorder lands: the founding customer, the founding row, the founding `tenant_id`; none for the demoshop customer; none on the demoshop row (read back with the service role) |
| F4 | commit B | both rows | write | Already reserved 1, To insert 0 (idempotent) |

  Also record `Found N subscription(s)` on commit A (every shop's) against commit B (founding only; must equal a
  service-role count of the founding tenant's subscriptions). **If C1 or C2 does not reproduce, halt: the gate
  would prove nothing.** No "Ignored …" line may print in F1-F4.
- **Teardown:** the fixture's preorders, subscriptions, catalog rows (`catalog_month = '2000-01'` and the
  `ZZTEST164-` prefix only), then each user (profile, then auth). Fresh read: 0 rows each, auth 404.

**Step 6. Optional broad regression:** if the staging current month's two catalog files are on disk,
`node import-staging.js <lunar> <prh> --no-write` on commit A then commit B: the auto-reserve counts must be equal
(demoshop holds no current-month rows). If the files are not on disk, skip it and say so.

**Step 7 (the production step, date-gated, D2).** `node --check` both scripts. **Ask Rick whether the Fri 2026-11-13
import ran and its output was read.** If yes: merge `--ff-only` to `main`, push, confirm on `origin/main`. If not
yet: push the feature branch to `origin` (a backup, the scripts repo is private), switch the folder back to `main`,
and leave the merge as a later two-command step (`git merge --ff-only feature/f164-import-tenant-reads`, push).
Either way the session ends with the folder on `main`, clean.

**Step 8. Records** (doc-only commit to the app repo's `staging`, pushed): this doc's STATUS and § 9 log;
`pre-phase-6-gate-closure.md` § 2e G-I line ("S1 done"); `technical-reference.md` § 13 F164 bullet; CLAUDE.md F164
row. F164 stays OPEN. `/wrap-up`.

### S1 gates (a failed gate is halt-and-report)

1. Audit result equals § 1 (Step 1).
2. `npm test` green with the new tests; negative control seen red then green.
3. Harness C1 and C2 reproduce the old behaviour on commit A; F1-F4 as tabled on commit B; teardown re-read 0.
4. Scripts repo `main` == `origin/main`, clean, both scripts carry identical changed regions.

---

## 4. What S1 does NOT prove

Production never runs in S1. The first real exercise is § 5. Staging's demoshop holds no current-month rows, so
staging's own weekly imports could not misfire before S1 either; the harness's fixture month is the only place the
mechanism is shown live.

---

## 5. Between S1 and S2: Rick's next production import (expected Fri 2026-11-20)

Run the § 2e interim queries first as usual. In the import output, read Step 5's lines:
- `Found N subscription(s)`: N equals the founding shop's subscription count (66 when last read, 2026-10-28);
- **no** `Ignored … from other shops` line and **no** `rows arrived without tenant_id` line;
- `Matched / Already reserved / Carried forward / To insert` look like a normal week (no sudden 0).

If all three hold, **the interim pre-import queries can be retired** (the import path is fixed; the API path stays
open until S2). Paste the Step 5 block to the next session.

---

## 6. Session S2: the trigger (one migration, both environments, Rick-run)

### 6.0 Before the session

- D1 = yes (answered 2026-11-11), so the SQL below is final as written.
- **Create `docs/sql/2026-11-DD-f164-preorders-same-shop-trigger.sql` (S2a's date) at the start of S2a**, STATUS
  `-- STATUS: staging=PENDING | prod=PENDING`, then `staging=APPLIED <date> | prod=PENDING (deliberately: production
  sitting S2b, on or after 2026-11-21)` after the staging apply. Between S2a and S2b, `/promote-prod` step 0 will
  list this file on every promotion. **It is not a hard blocker** (step 0b greps the client for the identifiers a
  migration adds, and no page or `app.js` references `preorders_require_same_tenant`), but each promotion in the
  window must say out loud that it is deliberately staging-only until S2b. *(This bullet first said a pending file
  "would block unrelated promotions"; the skill's own text makes it a stated decision, not a block.)*

### 6.1 Pre-checks (read-only, BOTH environments, before applying)

```sql
-- P1. Existing rows. PASS: all four 0.
SELECT
  (SELECT count(*) FROM public.preorders p JOIN public.catalog c ON c.id = p.catalog_id
    WHERE c.tenant_id <> p.tenant_id)                                                    AS catalog_other_shop,
  (SELECT count(*) FROM public.preorders p JOIN public.user_profiles u ON u.id = p.user_id
    WHERE u.tenant_id <> p.tenant_id)                                                    AS customer_other_shop,
  (SELECT count(*) FROM public.preorders p
    WHERE NOT EXISTS (SELECT 1 FROM public.catalog c WHERE c.id = p.catalog_id))         AS catalog_missing,
  (SELECT count(*) FROM public.preorders p
    WHERE NOT EXISTS (SELECT 1 FROM public.user_profiles u WHERE u.id = p.user_id))      AS customer_missing;
```

```sql
-- P2. Can the trigger function see every shop's rows? It runs as its owner (SECURITY DEFINER).
SELECT c.relname, pg_get_userbyid(c.relowner) AS owner, c.relrowsecurity AS rls_on, c.relforcerowsecurity AS rls_forced
FROM pg_class c
WHERE c.relnamespace = 'public'::regnamespace AND c.relname IN ('catalog', 'user_profiles', 'preorders');
SELECT current_user, rolbypassrls FROM pg_roles WHERE rolname = current_user;
```

PASS for P2: `rls_forced` false on all three, and either `owner` equals `current_user` or `rolbypassrls` is true.
Otherwise halt: the function's lookups would be filtered, and because the trigger fails closed, every reservation
would be refused.

### 6.2 The probe (writes nothing; run BEFORE applying, then AFTER)

Every outcome is an error, so the DO block always rolls back. Before the trigger it must read **`F164 FAIL 1`**
(that is the probe seen red); after, **`F164 PASS: checks 1 2 3 4 passed`**. Any other text is a fail. `1 2 4`
means no second-shop customer exists to test the owner check (likely on production): say so, do not call it a pass
of check 3.

```sql
DO $$
DECLARE
  v_home uuid; v_pid uuid; v_user uuid; v_cat uuid;
  v_foreign_cat uuid; v_foreign_user uuid;
  v_ran text := '';
BEGIN
  SELECT tenant_id INTO v_home FROM preorders GROUP BY tenant_id ORDER BY count(*) DESC LIMIT 1;
  SELECT id INTO v_pid FROM preorders WHERE tenant_id = v_home ORDER BY id LIMIT 1;
  SELECT user_id INTO v_user FROM preorders WHERE id = v_pid;
  SELECT c.id INTO v_cat FROM catalog c
   WHERE c.tenant_id = v_home
     AND NOT EXISTS (SELECT 1 FROM preorders p WHERE p.user_id = v_user AND p.catalog_id = c.id)
   ORDER BY c.id LIMIT 1;
  SELECT id INTO v_foreign_cat  FROM catalog       WHERE tenant_id <> v_home ORDER BY id LIMIT 1;
  SELECT id INTO v_foreign_user FROM user_profiles WHERE tenant_id <> v_home ORDER BY id LIMIT 1;

  IF v_foreign_cat IS NULL THEN
    RAISE EXCEPTION 'F164 PROBE CANNOT RUN: no listing from a second shop';
  END IF;

  -- 1. A reservation on another shop's listing must be refused.
  BEGIN
    INSERT INTO preorders (tenant_id, user_id, catalog_id, quantity) VALUES (v_home, v_user, v_foreign_cat, 1);
    RAISE EXCEPTION 'F164 FAIL 1: a reservation on another shop''s listing was ACCEPTED (rolled back)';
  EXCEPTION WHEN check_violation THEN v_ran := v_ran || ' 1';
  END;

  -- 2. Moving a reservation onto another shop's listing must be refused.
  BEGIN
    UPDATE preorders SET catalog_id = v_foreign_cat WHERE id = v_pid;
    RAISE EXCEPTION 'F164 FAIL 2: moving a reservation onto another shop''s listing was ACCEPTED (rolled back)';
  EXCEPTION WHEN check_violation THEN v_ran := v_ran || ' 2';
  END;

  -- 3. (D1) A reservation for another shop's customer must be refused.
  IF v_foreign_user IS NOT NULL THEN
    BEGIN
      INSERT INTO preorders (tenant_id, user_id, catalog_id, quantity) VALUES (v_home, v_foreign_user, v_cat, 1);
      RAISE EXCEPTION 'F164 FAIL 3: a reservation for another shop''s customer was ACCEPTED (rolled back)';
    EXCEPTION WHEN check_violation THEN v_ran := v_ran || ' 3';
    END;
  END IF;

  -- 4. Negative control: a same-shop reservation must be accepted.
  INSERT INTO preorders (tenant_id, user_id, catalog_id, quantity) VALUES (v_home, v_user, v_cat, 1);
  v_ran := v_ran || ' 4';

  RAISE EXCEPTION 'F164 PASS: checks% passed; nothing was written (this error rolls the probe back)', v_ran;
END $$;
```

If the probe errors with a not-null or other constraint message before any `F164` text, the probe's insert is
missing a required column: fix the probe (read `technical-reference.md` § 7.1), never the trigger.

### 6.3 The migration

```sql
BEGIN;

CREATE OR REPLACE FUNCTION public.preorders_require_same_tenant()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- F164 (G-I). A reservation must point at a listing of its own shop and belong to a customer of its own shop.
  -- SECURITY DEFINER: the caller's RLS hides other shops' rows, and a hidden row must not read as "absent".
  -- Fails closed: no matching row (another shop's, or no such row) refuses the write.
  -- No service-role exemption: the service-role import wrote the two rows F164 found.
  IF NOT EXISTS (SELECT 1 FROM catalog WHERE id = NEW.catalog_id AND tenant_id = NEW.tenant_id) THEN
    RAISE EXCEPTION 'A reservation must reference a listing of its own shop'
      USING ERRCODE = 'check_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM user_profiles WHERE id = NEW.user_id AND tenant_id = NEW.tenant_id) THEN
    RAISE EXCEPTION 'A reservation must belong to a customer of its own shop'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$function$;

-- F124: invoked by the trigger, not by any role. Revoke explicitly (REVOKE FROM PUBLIC alone does not strip
-- Supabase's defaults). Same as F109.
REVOKE ALL ON FUNCTION public.preorders_require_same_tenant() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.preorders_require_same_tenant() FROM anon;
REVOKE ALL ON FUNCTION public.preorders_require_same_tenant() FROM authenticated;

DROP TRIGGER IF EXISTS trg_preorders_require_same_tenant ON public.preorders;
CREATE TRIGGER trg_preorders_require_same_tenant
  BEFORE INSERT OR UPDATE OF catalog_id, tenant_id, user_id ON public.preorders
  FOR EACH ROW EXECUTE FUNCTION public.preorders_require_same_tenant();

COMMIT;
```

Design notes, so nobody re-derives them: `UPDATE OF` fires when a listed column is in the `SET` list even if its
value is unchanged, so PostgREST upserts fire it (and pass); quantity, fulfilment, `arrival_outcome`, `notes`-only
and `unavailable_dismissed_at` updates do not. A missing listing or customer now raises `23514` instead of the
foreign key's `23503`; nothing legitimate sends one. `check_violation` reaches the app as HTTP 400. **A future
shared-catalog model (one listing used by several shops) would have to revisit this trigger.**

**Rollback:**

```sql
BEGIN;
DROP TRIGGER IF EXISTS trg_preorders_require_same_tenant ON public.preorders;
DROP FUNCTION IF EXISTS public.preorders_require_same_tenant();
COMMIT;
```

### 6.4 Verification queries (each states its failing output)

```sql
-- V1. Triggers on preorders.
SELECT t.tgname,
       CASE WHEN t.tgtype & 2 = 2 THEN 'BEFORE' ELSE 'AFTER' END AS timing,
       (t.tgtype & 4  = 4)  AS on_insert,
       (t.tgtype & 8  = 8)  AS on_delete,
       (t.tgtype & 16 = 16) AS on_update,
       CASE WHEN t.tgtype & 1 = 1 THEN 'ROW' ELSE 'STATEMENT' END AS level,
       CASE WHEN t.tgenabled = 'O' THEN 'enabled' ELSE 'DISABLED' END AS status,
       (SELECT string_agg(a.attname, ',' ORDER BY a.attname)
          FROM pg_attribute a
         WHERE a.attrelid = t.tgrelid AND a.attnum = ANY (t.tgattr::int2[])) AS update_columns
FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
WHERE c.relname = 'preorders' AND c.relnamespace = 'public'::regnamespace AND NOT t.tgisinternal
ORDER BY t.tgname;
-- PASS: two rows. trg_preorders_block_ordered_delete: BEFORE, on_delete true, ROW, enabled (F109, unchanged).
--       trg_preorders_require_same_tenant: BEFORE, on_insert true, on_update true, on_delete false, ROW, enabled,
--       update_columns 'catalog_id,tenant_id,user_id'.
-- FAIL: the second row absent, AFTER, STATEMENT, DISABLED, or a different column list.
```

```sql
-- V2. Grants and definer settings.
SELECT has_function_privilege('anon', 'public.preorders_require_same_tenant()', 'EXECUTE')          AS anon_exec,
       has_function_privilege('authenticated', 'public.preorders_require_same_tenant()', 'EXECUTE') AS authenticated_exec,
       p.prosecdef AS security_definer, p.proconfig AS config
FROM pg_proc p WHERE p.oid = 'public.preorders_require_same_tenant()'::regprocedure;
-- PASS: false, false, true, {search_path=public}.   FAIL: any EXECUTE true, security_definer false, config empty.
```

V3 = P1 again (still all 0). V4 = the probe in § 6.2 (`F164 PASS`).

### 6.5 S2 steps and gates

**S2a, staging (any day once S1's staging gates are green; the agent runs the REST checks; Rick runs the SQL in the
SQL Editor):**

- **T0.** P1 and P2 on staging: PASS. The probe on staging reads `F164 FAIL 1` (seen red).
- **T1.** Rick applies § 6.3 on staging. V1, V2, V3 pass; the probe reads `F164 PASS: checks 1 2 3 4 passed`.
- **T2. API boundary re-run** (G-D Step 4's shape; local harness `playwright/f164-trigger-verify.mjs`, staging only,
  throwaway users by password grant): a founding **customer** JWT: `POST preorders` with a demoshop `catalog_id`
  is now **400 / 23514** (was 201 at G-D); `PATCH` of its own row's `catalog_id` to a demoshop listing **400** (was
  200); negative control `POST` with a founding listing **201**. A founding **admin** JWT: `POST` for a demoshop
  customer on a founding listing **400** (D1); for its own customer **201**. **Service role:** `POST` founding tenant
  + demoshop listing **400** (proves there is no exemption). Teardown, fresh read 0, auth 404.
- **T3.** S1's harness phases F3 and F4 again (fresh fixture): the legitimate auto-reserve insert still lands.
- **T4.** `playwright/f173-move-verify.mjs` (exists, local-only): 50/50. It drives `admin_move_reservations()`,
  the one function that updates `catalog_id`.
- **T5. Claim path (D1 adds `user_id` to the column list, and nothing in the suite covers the claim).** Harness:
  a founding paper customer (through `create-paper-customer` with a founding admin JWT) holding one reservation is
  claimed into a founding real customer: success, the reservation moves. A second paper customer claimed into a
  **demoshop** customer: the function returns its "Failed to reassign preorders" error, the reservation stays on
  the paper customer, the paper profile is not deleted. Teardown. (If Rick files § 2.1, run the cross-shop claim
  once BEFORE T1 too: it should succeed, which is that finding's evidence.)
- **T6.** Full Playwright suite on staging (no deploy is needed; the trigger is live the moment it applies): baseline
  **169 passed, 1 skipped** (2026-11-09). Read the log's own summary line, not an exit notice.

**S2b, production (on or after Sat 2026-11-21, once § 5's read is normal; D3):**

- **T6b.** P1 and P2 on production: PASS. The probe on production reads `F164 FAIL 1` (seen red; it writes nothing).
- **T7.** Rick applies § 6.3 on production; pastes V1, V2, V3 and the probe (`F164 PASS`; `1 2 4` is expected if
  no second-shop customer exists, and is recorded as "owner check not exercised on production").
- **T8. Write-smoke (Rick):** reserve one title on production through the app and cancel it. Every reserve now passes
  through the trigger. Read back, if permitted: the `reserve` and `cancel` events and their `tenant_id`.
- **T9.** The next production import after S2: Step 5 prints no "Auto-reserve batch failed".

**Gate rule:** any failure is halt-and-report. If production fails after applying, run the rollback there and stop.

### 6.6 Records on completion

`docs/sql/…f164…sql` STATUS `staging=APPLIED <date> | prod=APPLIED <date>` with the evidence note (what was observed
versus pasted, F109's convention); `technical-reference.md` § 7.1 (`preorders`) gains the trigger; § 13 F164
**RESOLVED on both environments**; `pre-phase-6-gate-closure.md` § 2e G-I DONE, the G8 row closed, STATUS token;
CLAUDE.md F164 row and a Current Migration Phase entry; this doc's STATUS and § 9. Finding-ID disposition: closes
F164; consumes none (F181 only if D4 files § 2.1).

---

## 7. Not in scope, and what stays unverified after both sessions

- **Not in scope:** the `claim-paper-customer` fix (§ 2.1, D4); a same-shop guard on `subscriptions` (G-D's sweep read
  0 owner mismatches; its admin policy, F138, has the same unconstrained `user_id` shape); `weekly_shipment` and
  `usage_events` (0 cross-shop rows, nullable `catalog_id`, no guard needed per § 2e); the composite foreign key
  alternative (§ 2e; not chosen: the unhinted `catalog(...)` embed in `app.js` makes a second relationship a
  `PGRST201` risk); G-G (F169 / F157); the four argument-taking RPCs G-D did not read.
- **Stays unverified:** production's API boundary with a real customer JWT (the probe runs as the SQL Editor's role:
  it exercises the trigger, not RLS); the owner check on production if no second-shop customer exists; an admin
  JWT on production; whether any past production import ever misfired before G-D (the sweeps read 0, which is the
  evidence that it did not leave rows).

---

## 8. Execution handoffs

### 8.1 S1 (paste into a fresh CLI session; any day, the merge in Step 7 is date-gated)

```
SESSION: F164 guard G-I, S1 = the import's tenant reads (scripts repo). Plan: docs/f164-g-i-same-shop-guard.md
(APPROVED 2026-11-11, Rick: "Defaults"; date gates apply to production steps only).

READ FIRST, from disk: CLAUDE.md (check `git branch --show-current` is staging first), the plan in full,
docs/pre-phase-6-gate-closure.md § 2e, docs/technical-reference.md § 13 F164, then import.js,
import-staging.js and test/builders.test.mjs in the scripts repo
(C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts, branch main).

BEFORE ANY EDIT:
 - Scripts repo on main, clean, == origin/main. Re-measure npm test (449/449 at F180).
 - Rick imports from this working tree: work on feature/f164-import-tenant-reads and END ON main.

DO, in order: plan § 3 Steps 1-8 (audit; commit A export only; commit B the fix in both scripts; unit tests with
negative control; staging harness phases C1, C2 on commit A then F1-F4 on commit B, teardown re-read 0;
optional Step 6; Step 7 = ask Rick whether the Fri 2026-11-13 import was read: if yes merge --ff-only, push,
confirm on origin/main; if not, push the branch unmerged and return the folder to main; doc records).
GATES: plan § 3 "S1 gates", each with its own evidence. A failed gate is halt-and-report.
NEVER: production writes or runs (Rick's next weekly import is the first, plan § 5), SQL, app code, the
trigger (that is S2), G-G, claim-paper-customer.
COMMITS: scripts repo, messages via heredoc, ending "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>".
Doc updates go doc-only to the app repo's staging branch, pushed.
END: /wrap-up.
```

### 8.2 S2a, staging (paste into a fresh CLI session once S1's staging gates are green)

```
SESSION: F164 guard G-I, S2a = the same-shop trigger on preorders, STAGING only (SQL Rick-run).
Plan: docs/f164-g-i-same-shop-guard.md § 6 (D1 = yes, answered 2026-11-11).

READ FIRST, from disk: CLAUDE.md (branch staging), the plan in full, docs/sql/f109-ordered-cancel-trigger.sql
(the convention), docs/technical-reference.md § 7.1 and § 13 F164 / F181.

BEFORE ANY SQL:
 - Confirm S1's staging gates are green (plan § 9 log). If S1 is not yet merged, note plan § 2's staging
   caution (interim queries before any staging import) in the session record.
 - Create the docs/sql file per plan § 6.0, STATUS staging=PENDING | prod=PENDING.

DO, in order: plan § 6.5 S2a, T0-T6. Rick runs every SQL block in the SQL Editor and pastes results; the agent
runs the REST harnesses on staging only.
GATES: each with its own evidence; the probe must be seen red (F164 FAIL 1) before it is seen green.
NEVER: anything on production; any app, script or Edge Function change; fixing claim-paper-customer (F181).
END: STATUS staging=APPLIED <date> | prod=PENDING (deliberately, S2b); plan § 9 log; doc-only commit to
staging, pushed; /wrap-up. F164 stays OPEN until S2b.
```

### 8.3 S2b, production (paste into a fresh CLI session on or after Sat 2026-11-21)

```
SESSION: F164 guard G-I, S2b = the same-shop trigger on PRODUCTION (SQL Rick-run; the agent never writes).
Plan: docs/f164-g-i-same-shop-guard.md § 6.5 S2b.

READ FIRST, from disk: CLAUDE.md (branch staging), the plan in full (§ 9 log for S1 and S2a), the docs/sql
f164 file.

BEFORE ANY SQL:
 - Confirm S2a is APPLIED on staging and S1 is merged to scripts main.
 - Confirm Rick read the first production import on S1's merged code (plan § 5) and it was normal.

DO, in order: T6b (P1, P2, probe seen red), T7 (apply, V1-V3, probe green), T8 (Rick's write-smoke),
T9 (the next production import, read later).
ON A PRODUCTION FAILURE: Rick runs the § 6.3 rollback; stop and report.
END: plan § 6.6 records (F164 RESOLVED on both, G8 closed), doc-only commit to staging, pushed; /wrap-up.
```

---

## 9. Execution log

- **2026-11-11, planning session.** Plan written (`78242ac`). Rick: "Defaults" (D1 yes, F181 filed as `ad5a11d`),
  plus "Reminders apply to Production scripts but staging can be managed outside these restrictions", so D2 / D3
  now gate only the production steps.
- **Gates scheduled (2026-11-11), production steps only, 8:00 AM ET (13:00 UTC; Eastern is on standard time):**
  - Sat 2026-11-14: S1's merge to scripts `main` allowed once the Fri 11-13 import is read. Routine
    `trig_01BYubBzX9uVvmCRvYWC9Z6m`; Google Calendar event `10r4rjgo2k38gglf3n015noca0`.
  - Fri 2026-11-20: read Step 5 of that day's import (§ 5); retire the interim queries if clean. Routine
    `trig_019SkmsYsRguzwMQdfP5BzGw`; calendar `8t7b5m6gmarmab0ettmn958n2o`.
  - Sat 2026-11-21: S2b allowed if § 5 read normal and S2a is on staging. Routine
    `trig_01SLUTLShf5fSCrQabDQAjHd`; calendar `hnfv1msur4o2n8uvm5k8e64e1c`.
  - Each routine is one-shot, reminds only (PushNotification / Read / Grep / Glob), with every connector removed;
    each calendar event has a popup at 8:00 and an email an hour before. Delete stale ones at
    https://claude.ai/code/routines if the plan changes.
