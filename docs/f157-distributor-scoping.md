# F157 — Distributor-scoping `delete_dropped_catalog_items` (design)

**STATUS:** NOT STARTED — design written 2026-10-04, build deferred to its trigger (§ 9) · staging=— · prod=— · PR=— · findings: F157 (advances), F169 (filed 2026-10-04 from § 4.4)

Owner doc for the **remaining half** of F157. The finding itself lives in
`docs/technical-reference.md` § 13 F157; the withdrawal half is closed (§ 10) and the zero-row
guard half shipped 2026-09-07 (scripts `9d9aa40`). This is **design only**: no code, no SQL run,
no deploy. Written in `docs/next-work-sequencing-2026-09-29.md` § 5 Session E. If Rick wants it
built, that is a separate scripts-repo session against this doc.

---

## 0. The answer in one paragraph

Give `delete_dropped_catalog_items` an optional trailing `p_distributor text DEFAULT NULL`. The
import scripts pass it **only** on a run that explicitly declares itself single-distributor
(`--only=Lunar|PRH`); the default two-distributor run keeps calling the function exactly as it does
today. Replace the function with `DROP` + `CREATE` in one transaction (a plain `CREATE OR REPLACE`
with a new parameter list leaves a second function behind), and **re-state the grants**, because a
freshly created function is executable by `anon` and `authenticated` until revoked (F124).

> **⚠️ The thing this design discovered, which changes what it is for (§ 3).** In its current
> wiring this function **cannot delete anything**: F66 (2026-06) and F110 (2026-08-03) both recorded
> that it matches zero rows (F110: "on every run"), and re-deriving it against the live body
> measured in Step 0 confirms it. So F157's "Effect 1" (an absent distributor's just-imported month is deleted)
> is **not reachable**, and **the RPC is not what blocks a one-distributor tenant**. Scoping is
> (a) defence in depth, (b) a hard precondition for ever wiring this function onto any path where
> it can match rows, and (c) cheap to carry along when the single-distributor import mode is built.
> It is not, by itself, what Phase 6 gate G4 is waiting on (§ 4.4).

---

## 1. Step 0 — the measured live definition (2026-10-04)

Query run by Rick in each project's SQL Editor (read-only; an overload-safe superset of
`pg_get_functiondef('public.delete_dropped_catalog_items'::regproc)`, which errors if the name is
overloaded, plus the grants a definition cannot show — F124):

```sql
SELECT p.oid::regprocedure::text AS signature,
       p.prosecdef               AS security_definer,
       p.proconfig               AS config,
       p.proacl::text            AS acl,
       pg_get_functiondef(p.oid) AS definition
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'delete_dropped_catalog_items'
ORDER BY 1;
```

### 1.1 Staging (`puoaiyezsreowpwxzxhj`) — one row, verbatim

| column | value |
|---|---|
| signature | `delete_dropped_catalog_items(uuid,text,text[])` |
| security_definer | `true` |
| config | `["search_path=public"]` |
| acl | `{postgres=X/postgres,service_role=X/postgres}` |

```sql
CREATE OR REPLACE FUNCTION public.delete_dropped_catalog_items(p_tenant_id uuid, p_catalog_month text, p_item_codes text[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE deleted_count integer;
BEGIN
  DELETE FROM catalog
  WHERE tenant_id = p_tenant_id
    AND catalog_month = p_catalog_month
    AND item_code != ALL(p_item_codes)
    AND id NOT IN (SELECT catalog_id FROM preorders WHERE tenant_id = p_tenant_id);
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$function$
```

(The pasted output rendered newlines as `<br>`; they are restored here, nothing else changed.)
This is **byte-for-byte the body `phase-5.0-pre-phase-5-housekeeping.md` § S4 wrote on 2026-06-11**
(F66's preorder guard). The ACL is the hardened state: owner plus `service_role`, **no `anon`, no
`authenticated`, no PUBLIC entry**.

### 1.2 Production (`plgegklqtdjxeglvyjte`) — one row, IDENTICAL to staging

| column | value |
|---|---|
| signature | `delete_dropped_catalog_items(uuid,text,text[])` |
| security_definer | `true` |
| config | `["search_path=public"]` |
| acl | `{postgres=X/postgres,service_role=X/postgres}` |

The `definition` column is the same text as § 1.1, character for character (compared after the
paste was received: same `CREATE OR REPLACE` header, same `SET search_path TO 'public'`, same
four-condition `DELETE` ending in the F66 preorder guard, same `GET DIAGNOSTICS` / `RETURN`).
**No divergence between environments, so the stop condition did not trigger.**

### 1.3 What the measurement settles

- **One signature, no overloads**, on **both** environments, and the two are identical. A new
  overload would therefore be *created by* this change, not found beforehand (§ 4.1.1), and one
  migration text serves both projects.
- `search_path=public` is a **function-level setting** (`proconfig`). A `DROP` + `CREATE` must carry
  it, or the `SECURITY DEFINER` function resolves `catalog` and `preorders` through the caller's
  path. It is in the SQL below and V2 checks it.
- The grants are in the **hardened** state, so a re-created function must reproduce exactly
  `{postgres=X/postgres,service_role=X/postgres}`, and V2 compares against this string.

---

## 2. Callers (fresh grep, 2026-10-04)

| Where | What | Live? |
|---|---|---|
| `import.js:898` (`refreshCatalog()`, inside `if (isNewMonth)` at `:895`) | `POST /rpc/delete_dropped_catalog_items`, body `{ p_tenant_id, p_catalog_month, p_item_codes }` | **Yes — production** |
| `import-staging.js:897` (same function, `if (isNewMonth)` at `:894`) | same body | **Yes — staging** |
| `catalogs/scripts/old/*.js` (8 files: `import-staging`, `import-weekly*`, `prod-import`, `sample-import-staging`, `old-import-weekly*`) | older copies of the same call | **No — retired** |
| `catalogs/scripts/schema-*-4.8.sql`, `schema-*-full.sql` | local, gitignored schema snapshots of the 3-argument definition | snapshots only |
| `docs/phase-1-schema-migration.md`, `phase-5.0-pre-phase-5-housekeeping.md` | historical definitions | docs |

**No caller exists in the web app, in any Edge Function, or in any `docs/sql/` file** (grep of
`*.js`, `*.html`, `*.ts`, `*.sql` across the web repo returned only a comment). So the blast radius
of a signature change is exactly the two import scripts.

Both live callers build `p_item_codes` as `records.map(r => r.item_code)` over **the whole import**,
Lunar and PRH together. That is the "no distributor awareness" F157 named.

---

## 3. What the function actually does today (and a correction to F157)

This is the section that decides how much to build, so it shows its working.

1. **The body** (§ 1.1) deletes rows where `tenant_id` matches, `catalog_month = p_catalog_month`,
   `item_code` is not in the array, and no `preorders` row references the catalog row.
2. **Both callers invoke it only when `isNewMonth` is true**, and only **after** `refreshCatalog()`
   has upserted `records` for that month (`import.js:869-887`, then `:895-911`).
3. **`isNewMonth = confirmedMonth > currentDbMonth`**, where `currentDbMonth` is the tenant's
   **maximum** `catalog_month` (tenant-scoped since F137). If any row already existed at
   `confirmedMonth`, the maximum would be `>= confirmedMonth` and the run would not be a new month.
   (The other route to `isNewMonth` is an empty catalog, which has no rows at all.)
4. **So at the moment of the DELETE, every row at `(tenant, confirmedMonth)` is a row this same
   run just upserted, and the array is built from those same records.** `item_code != ALL(array)`
   is false for every one of them. The statement matches **zero rows**.

That is not new. It is recorded twice already:

- **F66** (2026-06): every surviving row's `item_code` is already in `p_item_codes`, "so the DELETE
  matches zero rows" (recorded as why the function was unreachable, before its guard was added).
- **F110** (2026-08-03), correcting its own fix direction: it "**matches zero rows on every run**",
  and it calls the step "the no-op `delete_dropped_catalog_items` call".

**F157's Effect 1 (2026-09-07) did not carry that forward.** It says a Lunar-only record set
"deletes every PRH row in that month". There are no PRH rows at that month to delete: a PRH file
that normalised to zero records upserted none, and a new month has no earlier ones. F157 even says,
two bullets later, that the month's rows "were inserted moments earlier" — which is the reason the
delete is empty. Effect 2 (the withdrawal mark) was real and is closed (§ 10). Effect 1 was not
reachable.

**What this changes, stated precisely:**

| Claim | Status after this analysis |
|---|---|
| "A single-distributor new-month import deletes the absent distributor's rows" (`next-work-sequencing` § 5 correction note) | **Not reachable.** There are no such rows at the moment of the call. |
| "Scoping the RPC is what makes a one-distributor tenant possible" (F157 "relevant to Phase 6", G4) | **False as stated.** What stops a one-distributor tenant is the script's own argument and month handling (§ 4.4). The RPC is not in that path. |
| The RPC is dangerous if it is ever called where it can match rows | **True, and is the real reason to scope it** (F66's "activation risk"). §§ 3.1 and 9. |

### 3.1 When scoping would actually matter

The DELETE becomes live the moment the call is moved or reused where `(tenant, month)` already
holds rows the array does not cover:

- **Same-month or older-month refresh** — the use `technical-reference.md` § 6.2 describes ("drop
  titles that have disappeared from this month's distributor catalog between imports"), and F66
  names as its activation risk. A Lunar-only refresh of a two-distributor tenant would then delete
  every **unreserved** PRH row of the month (the F66 guard protects only referenced rows).
- **A hand-run or future caller** that passes the whole-import array for a partial import.

Neither exists today. That makes this a **precondition rule** (§ 9), not a live defect.

### 3.2 How this could be wrong

- The conclusion comes from the **measured body plus reading the call site**, not from an observed
  run. I found no run log on disk showing the printed result, and ran no query beyond Step 0.
- **Tripwire:** an import prints `✅ No dropped items to remove` when the count is 0 and
  `✅ Removed N dropped item(s)` otherwise (`import.js:905-907`). **If any new-month import ever
  prints "Removed N", this section is wrong — stop and re-derive before building anything.**
  Rick's November import is the next chance to see it.

---

## 4. The design

### 4.1 The RPC change

#### 4.1.1 Why `DROP` + `CREATE`, not `CREATE OR REPLACE`

Postgres identifies a function by name **and** argument types. `CREATE OR REPLACE` with an extra
parameter does not replace the 3-argument function; it **adds a second one**. With both present,
a PostgREST call that names only the three old arguments matches two candidates and can fail as
ambiguous (PostgREST error `PGRST203`). The fix is to drop the old signature and create the new
one **in the same transaction**, with `DEFAULT NULL` so a 3-argument call resolves to the single
remaining function. V4 proves this through PostgREST (the SQL Editor cannot show `PGRST203`).

`DROP FUNCTION IF EXISTS` without `CASCADE`: if anything unexpectedly depends on the old
signature, the drop fails and the transaction rolls back, which is the safe outcome.

#### 4.1.2 Why the grants are rewritten

A new function in `public` is granted `EXECUTE` to `anon` and `authenticated` by Supabase's default
privileges, and `REVOKE … FROM PUBLIC` does not remove those (F124). This is a destructive
`SECURITY DEFINER` function. Forgetting the revokes would make it callable from any browser holding
the publishable key. The statements below follow the committed sibling
`docs/sql/f136-dedupe-catalog-months.sql`, and V2/V3 check the result.

#### 4.1.3 The migration text — WRITTEN, NOT RUN

Deliberately **embedded here and not committed under `docs/sql/`**: `/promote-prod` step 0 lists
every `docs/sql/*.sql` whose `-- STATUS:` line is not applied on production (F105), so a `PENDING`
file sitting on `staging` would block every production promotion until it ran. The build session
creates the file, dated that day, in the same commit that first needs it.

```sql
-- STATUS: staging=PENDING | prod=PENDING
--         F157. Update this line the moment this runs on each environment (F105).
-- ============================================================================
-- delete_dropped_catalog_items -- optional p_distributor (F157)
-- Plan: docs/f157-distributor-scoping.md. Run: staging first, then production.
-- Run the whole block as ONE paste. Run the VERIFY queries as a SEPARATE paste
-- AFTER the COMMIT (F162: a verification error in the same implicit transaction
-- can roll the real change back with it).
-- ============================================================================
BEGIN;

-- The old 3-argument function must go: CREATE OR REPLACE with a new parameter
-- list would leave it behind as an overload, which PostgREST can reject as
-- ambiguous. No CASCADE: if anything depends on it, this fails and rolls back.
DROP FUNCTION IF EXISTS public.delete_dropped_catalog_items(uuid, text, text[]);

CREATE FUNCTION public.delete_dropped_catalog_items(
  p_tenant_id     uuid,
  p_catalog_month text,
  p_item_codes    text[],
  p_distributor   text DEFAULT NULL
)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE deleted_count integer;
BEGIN
  -- Fail closed. An empty array makes "item_code != ALL('{}')" TRUE for every row,
  -- i.e. "delete the whole month". No caller can send one today (F157's zero-row
  -- guard stops it upstream); this makes the function refuse it on its own.
  IF p_item_codes IS NULL OR cardinality(p_item_codes) = 0 THEN
    RAISE EXCEPTION 'delete_dropped_catalog_items: p_item_codes is empty; refusing to delete a whole month';
  END IF;

  -- Fail closed. A scoped call for a distributor with no rows in this month is a
  -- typo, a wrong-case value or a failed upsert. Without this it would match zero
  -- rows and look like success.
  IF p_distributor IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM catalog
       WHERE tenant_id = p_tenant_id
         AND catalog_month = p_catalog_month
         AND distributor = p_distributor
     ) THEN
    RAISE EXCEPTION 'delete_dropped_catalog_items: no % rows for tenant % in %',
      p_distributor, p_tenant_id, p_catalog_month;
  END IF;

  DELETE FROM catalog
  WHERE tenant_id = p_tenant_id
    AND catalog_month = p_catalog_month
    AND (p_distributor IS NULL OR distributor = p_distributor)
    AND item_code != ALL(p_item_codes)
    AND id NOT IN (SELECT catalog_id FROM preorders WHERE tenant_id = p_tenant_id);
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$function$;

-- Service-role only (F124). Explicit on BOTH roles: Supabase's default privileges
-- grant EXECUTE to anon and authenticated on every new function.
REVOKE ALL ON FUNCTION public.delete_dropped_catalog_items(uuid, text, text[], text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.delete_dropped_catalog_items(uuid, text, text[], text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.delete_dropped_catalog_items(uuid, text, text[], text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.delete_dropped_catalog_items(uuid, text, text[], text) TO service_role;

COMMIT;

-- ── VERIFY (separate paste, after the COMMIT) ───────────────────────────────
-- Same query as Step 0. EXPECTED: exactly ONE row; signature
-- delete_dropped_catalog_items(uuid,text,text[],text); security_definer true;
-- config ["search_path=public"]; acl {postgres=X/postgres,service_role=X/postgres};
-- definition contains the line "AND id NOT IN (SELECT catalog_id FROM preorders
-- WHERE tenant_id = p_tenant_id)". FAILURE LOOKS LIKE: TWO rows (the old function
-- survived), or anon=X/postgres / authenticated=X/postgres in acl (the revokes
-- did not take), or config null (search_path lost).
```

Names checked against `technical-reference.md` § 4.3 / § 4.4 and the Step 0 body:
`catalog.id uuid`, `catalog.tenant_id uuid NOT NULL`, `catalog.distributor text NOT NULL`,
`catalog.item_code text NOT NULL`, `catalog.catalog_month text`, `preorders.catalog_id uuid NOT NULL`,
`preorders.tenant_id uuid NOT NULL`. `p_tenant_id`, `p_catalog_month`, `p_item_codes` are unchanged
from the measured definition.

#### 4.1.4 Rollback

```sql
BEGIN;
DROP FUNCTION IF EXISTS public.delete_dropped_catalog_items(uuid, text, text[], text);
-- recreate the Step 0 definition from § 1.1 verbatim, then:
REVOKE ALL ON FUNCTION public.delete_dropped_catalog_items(uuid, text, text[]) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.delete_dropped_catalog_items(uuid, text, text[]) FROM anon;
REVOKE EXECUTE ON FUNCTION public.delete_dropped_catalog_items(uuid, text, text[]) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.delete_dropped_catalog_items(uuid, text, text[]) TO service_role;
COMMIT;
```

Safe at any time an import is not running. Between the `DROP` and the `COMMIT` nothing is visible
to callers (DDL is transactional); after it, PostgREST reloads its schema cache on DDL, so a
request landing in that sub-second window could see `PGRST202`. Imports are attended and manual,
so apply it when none is running.

### 4.2 The import-script change

#### 4.2.1 How "supplied" is decided

**By explicit declaration, never by inference.** A run supplies a single distributor only if the
operator says so with `--only=Lunar` or `--only=PRH` (input case-insensitive, normalised to the
exact-case values `Lunar` / `PRH`, which is what `catalog.distributor` holds). Anything else is a
usage error. Without the flag the run is the **two-distributor run it is today**.

Why not infer it from the arguments: the scripts take two positional catalog files, Lunar then PRH
(`import.js:1893`). A missing, empty or wrong file must keep meaning "something is wrong", which is
exactly what F157's guard enforces. If "one file" were inferred to mean "single-distributor", a
forgotten PRH file would silently become a legitimate-looking partial import — the very ambiguity
F157 exists to remove. An explicit flag keeps the two cases distinguishable.

| Invocation | Catalog positionals | Declared set | RPC body |
|---|---|---|---|
| default | 2 (Lunar, PRH) — as today | `Lunar`, `PRH` | `{ p_tenant_id, p_catalog_month, p_item_codes }` — **byte-for-byte today's** |
| `--only=Lunar` | 1 | `Lunar` | same three keys **+ `p_distributor: "Lunar"`**, codes restricted to Lunar records |
| `--only=PRH` | 1 | `PRH` | same three keys **+ `p_distributor: "PRH"`**, codes restricted to PRH records |

#### 4.2.2 Invariants (each one is a test or a gate in §§ 5-6)

- **I1.** No flag ⇒ today's behaviour exactly: both files required, the RPC body has **no
  `p_distributor` key**, the zero-row guard covers both sources.
- **I2.** A single-distributor run is reachable **only** through the flag.
- **I3.** F157's zero-row guard applies to **every declared source**. A declared distributor that
  normalises to zero still aborts before any write. An undeclared distributor is not a source and
  is never read.
- **I4.** In a scoped run the DELETE can touch only the declared distributor's rows (enforced in
  SQL by `distributor = p_distributor`, and in the script by building the array from that
  distributor's records only).
- **I5.** **Every failure leaves rows in place.** The call is already non-fatal
  (`import.js:908-910` warns "Could not remove dropped items"); an exception from the new
  fail-closed checks, a `PGRST202` from a database that has not been migrated yet, or a thrown
  planning error all end as "nothing deleted".

#### 4.2.3 Shape of the change (both scripts, in lockstep)

Two small **pure, exported** functions, so the logic is an assertion and not a code-review read
(the `classifyEmptyCatalogSources` / `planWithdrawalDetection` convention), plus a few lines of
wiring:

```js
// Pure. Returns the distributors this run declared, or throws on anything ambiguous.
parseSuppliedDistributors(rawArgs)
  // []                      -> ['Lunar', 'PRH']
  // ['--only=lunar']        -> ['Lunar']        (case-insensitive in, exact-case out)
  // ['--only=PRH']          -> ['PRH']
  // ['--only=Diamond']      -> throws           (unknown distributor)
  // ['--only=Lunar','--only=PRH'] / ['--only='] -> throws

// Pure. The exact RPC request body for refreshCatalog()'s delete step.
planDroppedItemsCall({ tenantId, catalogMonth, records, suppliedDistributors })
  // both declared (either order)  -> { p_tenant_id, p_catalog_month, p_item_codes: all codes }
  // one declared                  -> { ..., p_item_codes: that distributor's codes, p_distributor }
  // none / unknown / duplicate / a record whose distributor is outside the declared set /
  // zero records for a declared distributor -> throws
```

`refreshCatalog(records, catalogMonth, isNewMonth)` gains a `suppliedDistributors` argument and
calls `planDroppedItemsCall` inside the existing `try`/non-fatal handling; a throw becomes the same
warning the RPC failure already produces. `main()` builds the `catalogSources` list for the guard
from the **declared** distributors only. Console: print one line, e.g.
`   Distributors supplied: Lunar, PRH` or `   Distributors supplied: PRH (single-distributor run, --only=PRH)`,
so an operator sees which mode they are in before anything writes.

### 4.3 Which new-month steps are distributor-blind

F157 said "the new-month sequence is built on set-differences against the WHOLE import". Re-checked
step by step, so nobody has to redo it:

| Step | Distributor-blind? | Matters? |
|---|---|---|
| `archive_stale_reservations` | tenant + month based, all distributors | No — it copies history, it never decides "dropped" |
| `purge_stale_catalog` | date and preorder-guard based | No |
| `dedupe_catalog_months` | groups by `(item_code, distributor)` | No — already distributor-keyed |
| **`delete_dropped_catalog_items`** | **Yes** — one array for the import | **This doc** (and § 3: no effect today) |
| `clearReappearedWithdrawals(allCatalogRecords)` | keyed by `(distributor, item_code)`, clear-only | No — an absent distributor just clears nothing, the safe direction |
| cross-month collision check | counts `(item_code, distributor)` overlaps, then prompts | No |
| `reportReservedInStoreDateChanges` | report-only | No |

So `delete_dropped_catalog_items` is the **only** step that needs scoping.

### 4.4 NOT solved here — what actually stands between a one-distributor tenant and an import

Recorded so G4 is read correctly. None of these is the RPC; none is designed in this doc (it would
be scope expansion — they belong to the single-distributor import mode that Phase 6 / F131 will
need). This doc supplies only the **declaration** (§ 4.2.1) and the **scoped delete**. **Filed as
F169** (2026-10-04, at Rick's request), which owns the missing work; this table is its evidence.

| Obstacle | Where | Note |
|---|---|---|
| Two positional catalog files are mandatory | `import.js:1876`, `:1893` | `args.length < 2` refuses to start |
| The catalog month is inferred from the **Lunar** filename | `import.js:1914` | `inferCatalogMonth()` already parses a PRH filename too (`:1942`), so this is wiring, not new parsing |
| `normalized_catalog.json` is written beside the Lunar file | `import.js:2034` | needs a path that exists in PRH-only mode |
| Lunar item-code month check assumes Lunar records | `import.js:1977` | must skip when Lunar is not declared |
| Month-mismatch guard compares the two filenames | `import.js:1942-1956` | meaningless with one file |
| Shipment and auto-reserve steps | per F157 filing, "likewise requires both invoices" | **re-verify at build time**: `f5fb6f0` since made shipment files any-number, so this may already be partly stale |

---

## 5. Unit tests (credential-free, run against BOTH scripts)

Same convention as `test/empty-catalog-source-guard.test.mjs`: dummy env vars before `require`,
both modules in one loop, no network. A new file, e.g. `test/distributor-scoping.test.mjs`. The
export set must stay identical across the two scripts (`builders.test.mjs` asserts parity).

| # | Case | Expected |
|---|---|---|
| T1 | both scripts export `parseSuppliedDistributors` and `planDroppedItemsCall` | functions |
| T2 | **two-distributor path unchanged** — `planDroppedItemsCall` with `['Lunar','PRH']` | body's **exact key set** is `p_tenant_id, p_catalog_month, p_item_codes`; **no `p_distributor` key at all** (assert `Object.keys`, not just `JSON.stringify`, which hides `undefined`); `p_item_codes` equals today's `records.map(r => r.item_code)` |
| T3 | declared order `['PRH','Lunar']` | identical to T2 |
| T4 | `--only=Lunar` over mixed records | `p_distributor === 'Lunar'`; codes are the Lunar records' only |
| T5 | `--only=PRH` over mixed records | `p_distributor === 'PRH'`; codes are the PRH records' only |
| T6 | **single-distributor tenant import** — every record is PRH, declared `['PRH']` | scoped body; codes are all records |
| T7 | a record whose distributor is outside the declared set | **throws** (never silently widens or narrows) |
| T8 | empty, unknown, lowercase `'lunar'`, duplicate declared sets | **throws** |
| T9 | declared distributor with zero records | **throws** (backs up the F157 guard) |
| T10 | does not mutate its input | deep-equal before/after |
| T11 | `parseSuppliedDistributors`: none → both; `--only=lunar` → `['Lunar']`; `--only=Diamond`, repeated `--only`, empty value → throws | as listed |
| T12 | `classifyEmptyCatalogSources` on a **declared-only** source list | declared + healthy passes; declared + `normalized: 0` aborts; the existing V1-V7 untouched |
| T13 | a flag/positional mismatch helper, if the build adds one (`--only=` with 2 positionals; default with 1) | refuses |

Unit-suite baseline at design time: **345/345** (CLAUDE.md, 2026-10-04). The build must state its
own new total (`345 + new tests`) and a negative control (neuter `planDroppedItemsCall` to always
return the unscoped body → T4-T6 go red; restore → green).

**SQL behaviour cannot be unit-tested** and is not claimed to be: it is covered by the constructed
gates in § 6.

---

## 6. Verification gates (every expected value is one that would LOOK DIFFERENT on failure)

> **Why these are constructed, not live.** Because the call matches zero rows in its real wiring
> (§ 3), a normal import cannot show scoping working, and a gate that passes before and after the
> change is not a gate (the F137 V0 lesson, and `CLAUDE.md` § "A verification step that cannot
> fail"). Every behavioural gate therefore uses seeded rows on a throwaway tenant.

| # | Env | Gate | Expected | Failure looks like |
|---|---|---|---|---|
| V1 | both | Step 0 query **before** applying | one row, 3-arg signature, ACL `{postgres=X/postgres,service_role=X/postgres}`, body = § 1.1 | any difference: **stop**, someone changed it since 2026-10-04 |
| V2 | both | Step 0 query **after** applying | **one** row, signature `…(uuid,text,text[],text)`, `config ["search_path=public"]`, ACL **identical to V1**, definition contains the preorder-guard line | **two rows** (old function survived); `anon=X/…` or `authenticated=X/…` in ACL; `config` null |
| V3 | both | anon probe, zero-write: `POST /rest/v1/rpc/delete_dropped_catalog_items` with the **anon** key, tenant `00000000-0000-0000-0000-000000000000`, month `1999-01`, codes `["x"]` | body contains `42501` (permission denied) | HTTP 200 with a number: the revokes did not take |
| V4 | both | **stale-script compatibility, through PostgREST**: service-role POST with the **three old named args only** (nonexistent tenant, month `1999-01`, codes `["x"]`) | HTTP 200, body `0` | `PGRST203` (ambiguous overload) or `PGRST202` (function not found) |
| V5 | staging | scoped delete on a **seeded throwaway tenant**: month `1999-01`, 2 Lunar + 2 PRH rows; array holds 1 Lunar + 1 PRH code. Call (a) `p_distributor` omitted, (b) `'Lunar'`, on fresh seeds each time | (a) returns **2** (one of each dropped) — the old behaviour; (b) returns **1** and the unlisted PRH row **survives** | (b) returns 2: scoping not applied |
| V6 | both | fail-closed: same nonexistent tenant, `p_distributor: "Nope"` | HTTP 400 carrying `no Nope rows for tenant` | HTTP 404/`PGRST202` (old function still there) or 200 `0` (silent) |
| V7 | both | fail-closed: `p_item_codes: []` | HTTP 400 carrying `p_item_codes is empty` | HTTP 200 `0` — the old function's reading of "delete everything" |
| V8 | staging | script wiring, `--no-write` dry run with a real Lunar file and `--only=Lunar` | prints `Distributors supplied: Lunar (single-distributor run, --only=Lunar)`, never reads or mentions a PRH file, exit 0 | a PRH line, or a usage error |
| V9 | staging | the same dry run **without** the flag | prints `Distributors supplied: Lunar, PRH`; output otherwise identical to a pre-build dry run (diff them) | any difference |

Teardown for V5: delete the `1999-01` rows and the throwaway tenant, then confirm by a **fresh
read** that zero rows remain (Definition of Done: "verify with a live SELECT returning zero rows —
not 'we ran the teardown SQL'"). Production gets V1-V4, V6, V7 only: **zero writes**, since the
nonexistent-tenant probes distinguish old from new without creating anything.

The preorder guard needs no separate live fixture: its line is **byte-identical** to the one F66
verified, and V2 asserts it is still in the definition. (A reservation fixture needs an auth user;
add one only if Rick wants the belt and braces.)

**Not provable by any gate, and said plainly:** that a real two-distributor monthly import still
behaves. The first real exercise will be Rick's next monthly import after the build, and it will
print `No dropped items to remove` whether or not scoping works (§ 3). V2/V4/V9 plus T2 are the
proof; the live import is a smoke test, not evidence.

---

## 7. Rollout order and rollback

1. **SQL first, staging then production** (§ 4.1.3). It is backward compatible: V4 proves an
   unchanged script still works against the new function.
2. **Both scripts in one scripts-repo commit** (`import.js` + `import-staging.js`, never one
   without the other — the 2026-05-08 drift incident). The scripts have no deploy step; they take
   effect at the next run.
3. Script-before-SQL is also safe: a default run never sends `p_distributor`, and a scoped run
   against an unmigrated database gets `PGRST202`, which is non-fatal and deletes nothing (I5).
4. **Rollback:** § 4.1.4 for the SQL, `git revert` for the scripts. Neither touches data.

---

## 8. Alternatives considered

| Option | Verdict |
|---|---|
| **A. Per-distributor calls on every run** (one scoped call per distributor, including two-distributor runs) | Rejected for now. It changes the one path that has run cleanly in production (October 2026), for a benefit no reachable scenario needs. Revisit if a third distributor ever exists. |
| **B. Retire the call** — delete the step from both scripts (and optionally drop the RPC) | **Materially cheaper, and a legitimate choice given § 3.** Zero behaviour change (it matches nothing), no cross-environment migration, and F157's whole class disappears. It loses the (unused) same-month dropped-item capability, which anyone could rebuild with scoping later. **Rick's call at build time; if the build would otherwise touch only this RPC and not the single-distributor mode, I would lean to B.** |
| **C. Declare the distributors per tenant** (`tenants.settings`) instead of per run | The right shape for Phase 6, where a tenant imports without an operator at the keyboard (F131). Too much machinery today; the flag's semantics carry over unchanged when it is replaced. |
| **D. `p_distributors text[]`** | YAGNI until a third distributor exists. |
| **E. Widen the existing function in place** (`CREATE OR REPLACE`, same 3 arguments, infer from the codes) | Rejected: Lunar and PRH item codes are not guaranteed distinguishable by shape, and inference is the failure F157 describes. |

---

## 9. When to build it — the trigger

**Build when the first single-distributor tenant is onboarded, or at Phase 6 S0, whichever comes
first.** (Rick, 2026-10-04.)

Two things the build session must carry with it:

1. **Scoping alone unblocks nothing** (§ 3, § 4.4). The same session has to address, or explicitly
   hand off, the single-distributor import mode; otherwise it ships a correct parameter that no
   one can reach. This is a scheduling note, not a change to the trigger.
2. **A standing rule that does not wait for the trigger:** *`delete_dropped_catalog_items` must not
   be called from any path other than the new-month branch until it is scoped.* If anyone proposes
   same-month or older-month "dropped item" removal, that is the moment this becomes mandatory
   (F66's activation risk, § 3.1).

---

## 10. The withdrawal half of F157 is CLOSED

F157 originally named two effects. **Effect 2 — `computeWithdrawalCandidates()` flagging an absent
distributor's reserved titles "Withdrawn" — no longer exists as a risk**, by two independent
changes:

- **F165 S1, scripts repo `5919130`** deleted `computeWithdrawalCandidates()`,
  `narrowWithdrawalCandidates()`, `detectWithdrawals()` and the automatic mark from `import.js` and
  `import-staging.js` outright. `planWithdrawalDetection()` pins `shouldMark: false`.
- **F165 S2, scripts repo `3ef4b89`** added the weekly, report-only candidate section to
  `check-dates.js`, which compares each title only with a fresher copy of **its own** distributor's
  source, so a one-distributor input cannot raise a candidate for the other.

Nothing in this design touches withdrawal logic.

---

## 11. Completion criteria

**This design session** (Session E of `next-work-sequencing-2026-09-29.md`):
- [x] Step 0 recorded verbatim for **both** environments and compared — **DONE 2026-10-04, identical** (§ 1)
- [ ] This doc committed and pushed to `staging`; `git status -sb` shows no "ahead"
- [x] § 13 F157, `next-work-sequencing` § 5/§ 6, `CLAUDE.md` F157 row and Phase 6 G4 updated — **DONE 2026-10-04**

**The future build session** (not started):
- [ ] § 4.1.3 applied on staging, V1/V2/V3/V4/V5/V6/V7 green; then production, V1-V4/V6/V7 green
- [ ] Both scripts changed together; unit suite green with the new total stated, negative control observed
- [ ] V8/V9 dry runs; teardown re-read shows zero fixture rows
- [ ] `technical-reference.md` § 6.2 signature, `docs/import-sop.md` (the flag) and the new `docs/sql/` file's `-- STATUS:` line updated
- [ ] This doc's STATUS token → COMPLETE, with dates
