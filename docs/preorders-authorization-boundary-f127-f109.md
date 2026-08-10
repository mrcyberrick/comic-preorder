# Moving two client-side guards into the database — F127 (account status) and F109 (ordered-cancel)

**Findings:** `docs/technical-reference.md` § 13 **F127**, **F109**.
**Status:** **PLANNED — not started.** No code written, no DDL run.
**Target:** staging first, then production on Rick's explicit request.
**DDL is Rick-in-the-loop** — PostgREST has no SQL endpoint; every statement in
this plan needs the Supabase SQL Editor.
**Last verified against live:** 2026-08-10 (repo files read from disk; row
counts and profile statuses read from both databases read-only — § 2.5).

---

## 1. Goal

Two guards in this app exist only in the browser. Move both into the database,
without breaking the four things that legitimately write `preorders` from
outside the customer's own session.

| | F127 | F109 |
|---|---|---|
| Guard | account `status` blocks reserving/subscribing | an already-ordered reservation cannot be cancelled |
| Lives in | `catalog.html:257–259` (8 read sites in that file) | `Preorders.cancel()` in `app.js` |
| Measured bypass | `status='pending'` user, own JWT → `POST /rest/v1/preorders` → **HTTP 201** | customer JWT → direct `DELETE /rest/v1/preorders` → **HTTP 204** |
| Enforcement mechanism | RLS predicate | `BEFORE DELETE` trigger |
| Reachable without crafting a request? | **Yes** — `subscriptions.html` has no gate at all | No |

They are planned together because they touch the same table's authorization
surface in the same week, and doing them in two unrelated sessions means two
policy-set audits, two Playwright baselines, and two production windows on the
app's busiest table.

---

## 2. Evidence established 2026-08-10

### 2.1 F16 is CLOSED on both environments — § 7's "4 policies" is stale

This had to be settled first: F127's own root-cause table reproduces § 7's
four-policy list, and if it were true, F127's predicate would be added to a
policy set that already OR-permits cross-tenant admin writes.

It is not true. `preorders` carries **two** policies on both environments:

| Policy | Cmd | Qual and check |
|---|---|---|
| `users manage own preorders` | ALL | `auth.uid() = user_id AND tenant_id = current_tenant_id()` |
| `admins manage tenant preorders` | ALL | `current_user_is_admin() AND tenant_id = current_tenant_id()` (both qual and with_check) |

Five independent pieces of repo evidence, three of them derived from live
captures taken at the time:

1. **A raw `pg_policies` dump of staging**, `docs/phase-4.1-audit-findings.md`
   lines 28–29 and 52 (2026-05-26): exactly those two policies by name, and the
   summary row reads *"preorders | 2 — both PERMISSIVE ALL on {public}"*.
2. **The production migration**, `git show main:supabase/migrations/20260531150558_phase_4_4_prod_rls_functions.sql`,
   Step 5, header comment *"Fixes: … F16 (preorders OR→split)"*. It drops
   production's three pre-existing policies and creates exactly the two above.
3. **The production pre-4.4 baseline**, `docs/production-baseline-2026-05-28.md`
   lines 129–131, lists production's three `preorders` policies —
   `Admins can view all preorders`, `Users can manage own preorders`,
   `admins update all preorders`. **All three are in the migration's DROP list**,
   so the drop was exhaustive. Production never carried the two policies F16
   names; those were staging-only names.
4. **Staging arithmetic from a live capture.**
   `docs/phase-5.0-pre-phase-5-housekeeping.md` records a live `pg_policies`
   count on 2026-06-11: *"Pre-capture: 21 rows (14 `{public}`, 7
   `{authenticated}`)."* § 7's per-table lists sum to 19 policies for every
   table **except** `preorders` at that date. 21 − 19 = **2**. Both halves of
   the split (14 and 7) also reconcile exactly against § 7's lists. Its ALTER
   list names exactly two `preorders` policies.
5. **Production arithmetic from a live capture.** The same document states
   *"Prod has all 22 of its policies qualified."* The 4.4 migration creates 22
   policies across ten tables, with `preorders` at 2. 

**Nothing has touched `preorders` policies since.** `grep -rn "CREATE POLICY\|DROP POLICY" docs/sql/`
returns only the two `order_submissions` policies.

**Consequence for this plan:** no prerequisite session. The predicate is being
added to a policy set that is correct.

**Consequence outside this plan:** `docs/technical-reference.md` § 7's
`preorders` block, the sentence beneath it, § 3's paragraph at line 271, and
F127's own root-cause table all need correcting. That is doc work owned
elsewhere — see § 9.

### 2.2 The `preorders` write paths that must survive

Read from the code, not assumed:

| Path | Authenticated as | `user_id` written | Policy it uses |
|---|---|---|---|
| Customer reserve (`catalog.html`) | the customer | own | `users manage own preorders` |
| **Admin impersonation** (`AdminContext`) | **the admin** | **the customer's** | `admins manage tenant preorders` |
| Admin paper orders (`upsertReservation`, `bulkUpsert`) | the admin | the paper customer's | `admins manage tenant preorders` |
| Monthly import auto-reserve | service role | the subscriber's | **none — RLS bypassed** |

`AdminContext` is `sessionStorage` only (`app.js:502–588`); `resolveUserId()`
substitutes the customer's id into the row body while the request still carries
the **admin's** JWT. So `auth.uid() = user_id` is false during impersonation and
the write has *always* gone through the admin policy.

**This is the fact that makes F127's fix safe.** A predicate on the caller's own
profile, added to `users manage own preorders`, cannot reach the impersonation
path — it is a different policy. No special-casing needed.

### 2.3 The `preorders` DELETE paths — all of them

| Path | Runs as | Trigger fires? |
|---|---|---|
| `Preorders.cancel()` (`app.js:893–897`) — the only `.delete()` on `preorders` anywhere in the client | customer or impersonating admin | **yes** |
| Playwright `deleteUser()` (`fixtures/auth.ts:99`) | service role | **yes** |
| Playwright `cleanupTestRows()` (`fixtures/catalog.ts:295`) | service role | **yes** |
| Tenant teardown (`preorders.tenant_id → tenants.id` is `ON DELETE CASCADE`) | service role / superuser | **yes, per cascaded row** |
| Monthly import | — | **n/a — the import never DELETEs `preorders`.** Verified: `import.js` does PATCH (F85 carry-forward, line 774) and POST (line 789) only |
| Edge Functions | — | none delete `preorders` |

**RLS bypass is not trigger bypass.** Service role and the SQL Editor both fire
`BEFORE DELETE` triggers. This is the single largest risk in the F109 half and
§ 4.6 is built around it.

**Read from the suite, not assumed.** `deleteUser()` issues
`DELETE /rest/v1/preorders?user_id=eq.<id>` with the service key and **throws on
any non-ok response** — that hard throw is F95's own fix, so a trigger rejection
does not degrade gracefully, it fails the run. Spec 15 seeds already-ordered
(non-withdrawn) reservations for V4's flagging assertions and tears them down
through exactly this path. **An unconditional trigger breaks the Playwright
suite's teardown**, which is why § 3.7's exemption is a prerequisite and not a
nicety.

### 2.4 `subscriptions.html` has no status check — confirmed by reading the file

F127 flagged this as *"worth confirming empirically before any fix."* Confirmed:

- The page destructures `{ user, profile }` at line 357 and consults exactly
  one profile field, `is_admin`, at lines 359 and 738.
- There is no occurrence of `status`, `isPending`, `isBlocked` or any
  equivalent in all 744 lines.
- The subscribe paths (`subscriptions.html:598` unsubscribe, `:700` series
  search subscribe, and the reserved-suggestions list) are reachable by
  ordinary use.

So a `pending` or `suspended` customer can subscribe through the UI with no
crafted request. **This is the more urgent half of F127** — the `preorders`
bypass needs someone to hand-write an HTTP call; this one needs someone to
click a button.

`subscriptions` policies (§ 7.1) are the same shape as `preorders`' but with no
admin write policy:

| Policy | Cmd | Condition |
|---|---|---|
| `users manage own subscriptions` | ALL | `auth.uid() = user_id AND tenant_id = current_tenant_id()` |
| `admins view tenant subscriptions` | SELECT | tenant + admin |

### 2.5 Live data — measured read-only, both environments, 2026-08-10

| | Staging | Production |
|---|---|---|
| `user_profiles` `status='active'` | 18 | 28 |
| `status='pending'` | **1** | **0** |
| `status='suspended'` | **0** | **0** |
| `preorders` held by any non-active profile | **0** | **0** |
| `subscriptions` held by any non-active profile | **0** | **0** |

The single staging `pending` row is `test user2`
(`1968c990-bb03-4d3e-8fe3-837ced905e05`, created 2026-06-11), holding nothing.

**This is the number that de-risks the whole F127 half.** The awkward case — an
account blocked *after* it accumulated reservations — does not exist anywhere
today. Whatever this plan does to it, it does to zero real customers. It will
exist the first time Rick uses the Pause button, which is why § 3.3 still has to
answer it properly rather than defer it.

### 2.6 The order code the F109 trigger must match on

`exportCode()` (`app.js:1462–1466`):

```js
distributor === 'PRH' ? (c.isbn || c.item_code || c.upc || '')
                      : (c.item_code || c.upc || c.isbn || '')
```

JavaScript `||` is falsy-coalescing, so **an empty string falls through to the
next candidate**. A naive SQL `COALESCE` does not — it stops at the first
non-NULL, including `''`. The trigger must use `COALESCE(NULLIF(x,''), …)` or it
will disagree with the client on any row with an empty-string code. § 4.5 does.

The ledger is **signed** since F117 (`docs/sql/order-submissions-signed-quantity.sql`):
`CHECK quantity >= 1` was dropped, `order_type` gained `adjustment`, and
`get_ordered_codes()` now aggregates — `SUM(quantity) > 0` → `'ordered'`,
otherwise `'unavailable'`. **The trigger must sum, not test for existence.**
Testing existence would block cancellation of a title the supplier rejected —
the exact false promise the RPC was reworked to stop making.

### 2.7 The withdrawn exception the trigger must not break

`Preorders.cancel()` reads `catalog.withdrawn_at` and, when set, skips **both**
guards (`app.js:863–896`): the `fulfilled` check, the ledger check, and the
defensive `.eq('fulfilled', false)` on the DELETE itself. Two call sites depend
on it — `mylist.html:1097` (current-month table) and `mylist.html:1324`
(`.cancel-btn-arrival`, the Upcoming Arrivals grid, which is where the real
MIDNIGHT X-MEN #2 case lives). F110 § 2.2 records this as a deliberate,
Rick-authorized exception.

A trigger that blocks on ledger presence alone silently reverts it. § 4.5 checks
`withdrawn_at` **first** and returns.

---

## 3. Decisions — recommended, for Rick to confirm before Session 1

### 3.1 The predicate gates writes, never reads or cancels — RECOMMENDED

`users manage own preorders` is `FOR ALL` with a `USING` clause and **no explicit
`WITH CHECK`**, so Postgres uses `USING` for both. Putting the status predicate
in `USING` would take a blocked customer's *own reservations off their own screen*
and stop them cancelling — customer-hostile, and it would make Pause destructive
in a way F126's confirm text explicitly promises it is not (*"existing
reservations stand"*).

**Recommendation: gate INSERT and UPDATE only.** SELECT and DELETE stay
untouched. A paused customer sees their list, can remove things, and cannot add
or increase.

### 3.2 Implement as RESTRICTIVE policies, not by editing the existing one — RECOMMENDED

A new PERMISSIVE policy would OR in and make things *more* permissive — the F16
mistake exactly. That leaves two shapes:

| | Edit `users manage own preorders` | Add RESTRICTIVE policies |
|---|---|---|
| Touches the app's busiest working policy | yes | **no** |
| Rollback | `WITH CHECK` cannot be un-set by `ALTER POLICY` — needs DROP + CREATE, i.e. the rollback re-creates the load-bearing policy from a script | **one `DROP POLICY` per policy** |
| Failure mode if the rollback script is wrong | customers cannot reserve at all | the gate is simply gone |

**Recommendation: RESTRICTIVE.** Restrictive policies AND with the OR'd
permissive set, so the effective rule is
`(own row OR admin) AND (caller is active)` for INSERT/UPDATE, which is exactly
the intent. The working policy is never touched, and rollback is one line.

Both clauses are stated explicitly (`USING (true) WITH CHECK (…)` on the UPDATE
policy) rather than relying on omitted-expression defaults — see § 6 V0.

### 3.3 A blocked account keeps every reservation it already has — RECOMMENDED

Follows from § 3.1: no DELETE gate, no SELECT gate. Reservations stand, remain
visible, remain cancellable by the customer. Zero accounts are affected today
(§ 2.5) but this is the shape Pause will have forever after.

### 3.4 `'suspended'` and `'pending'` are treated identically — SETTLED, not a new decision

Rick settled this on 2026-08-09 (F126: *"`'suspended'` exists as its own status
but carries the same permission impact as `'pending'`"*), and `catalog.html:257–259`
already ships it.

The predicate is written **positively** — `status = 'active'` — rather than as a
blocklist. Consequence worth stating: if the `user_profiles_status_check` CHECK
is ever widened (F126 discusses an `'invited'` state), the new status is blocked
by default. That is the safe direction, and it is deliberate.

### 3.5 The client must be gated everywhere the database now is — REQUIRED, not optional

An RLS `WITH CHECK` failure surfaces as HTTP 403 / `42501` and the client shows a
generic *"Failed to reserve"*. Two surfaces would produce that today:

- **`subscriptions.html`** — no gate at all (§ 2.4). Needs the `catalog.html`
  gate ported.
- **`mylist.html`** — no `status` reference anywhere in the file, so the
  quantity stepper (an UPDATE) is ungated. Needs the same gate.

Shipping the DDL without these turns a clear "your account is paused" message
into a mystery error. **The client change ships in the same session as the DDL.**

### 3.6 F109 stays a trigger, not a policy — CONFIRMED, with one reason F109 did not give

F109's entry already says *"Do not narrow the RLS policy itself… the condition
depends on a join against another table and belongs in a trigger."* True, and
there is a second reason worth recording: **an RLS DELETE failure is silent.**
RLS filters rows rather than raising, so a blocked DELETE returns
`HTTP 204, 0 rows` and `Preorders.cancel()` would report success while nothing
happened. A trigger raises, so the client gets a real error to show.

### 3.7 The trigger enforces against end-user sessions only — RECOMMENDED, needs Rick's confirmation

Because triggers fire for service role and the SQL Editor (§ 2.3), an
unconditional trigger would block:

- Playwright teardown for any fixture that seeds both a preorder and a matching
  ledger row — **spec 15 seeds exactly that shape** (its V4 already-ordered
  reservations are non-withdrawn, so no exception would save them), and
  `deleteUser()` **throws** on a non-ok response rather than warning;
- tenant teardown, via the `ON DELETE CASCADE` on `tenant_id`;
- Rick's own hand repairs. The F122 production repair on 2026-08-10 **deleted an
  F85 cross-month duplicate `preorders` row** for MIDNIGHT X-MEN #1 — a code
  that carries ledger rows. **That exact operation would have been blocked.**

**Recommendation: exempt `auth.uid() IS NULL` (service role, SQL Editor, cascade
teardown) and `current_user_is_admin() IS TRUE` (store staff working in the
app).** The threat F109 describes is a customer crafting a request; neither
exemption widens it.

`IS TRUE`, not `NOT`, per F126's lesson — `current_user_is_admin()` returns NULL
for a caller with no identity, and `IF NOT current_user_is_admin()` is never
taken. Here the `auth.uid() IS NULL` guard runs first so NULL cannot reach it,
but the form is used anyway because the next person to copy this line will not
know that.

---

## 4. Design

### 4.1 One new helper function

```sql
CREATE OR REPLACE FUNCTION public.current_user_is_active()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    (SELECT COALESCE(is_admin, false) OR status = 'active'
       FROM user_profiles
      WHERE id = auth.uid()),
    false)
$function$;
```

Deliberate properties, each because something has gone wrong here before:

- **`SECURITY DEFINER`** — mirrors `current_user_is_admin()`. The internal read
  of `user_profiles` runs as the owner and bypasses RLS, so no policy on
  `user_profiles` has to permit it and there is no recursion path. (Even
  `SECURITY INVOKER` would not recurse here — the policy is on `preorders`, not
  `user_profiles` — but the convention is DEFINER and CLAUDE.md § Known Issues
  is explicit about why.)
- **`SET search_path TO 'public'`** — F23.
- **The double `COALESCE` closes the F126 NULL hazard on both levels.** Inner:
  `is_admin` is nullable, and `NULL OR false` is `NULL`, which would make a
  profile with a null `is_admin` and a non-active status evaluate to NULL rather
  than false. Outer: a caller with no matching profile row (no identity, or a
  deleted profile) yields no row at all, so the scalar subquery is NULL.
  **Both must land on `false`, and this is the exact shape that was open in
  F126.** V2 tests all five cases explicitly.
- **`STABLE`, not `IMMUTABLE`** — it reads a table.
- **Positive predicate** (§ 3.4).

**Grants — F124.** `REVOKE … FROM PUBLIC` does not remove Supabase's default
`anon`/`authenticated` grants, and here `authenticated` is *wanted*: the policy is
`TO authenticated`, so the role must be able to execute the function during
policy evaluation. Revoking it would break RLS the way F124 warns revoking
`current_user_is_admin()` would.

Do **not** write the grant block from this file. Read what
`current_user_is_admin()` actually has on the target environment and mirror it:

```sql
SELECT p.proname, p.proacl
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('current_user_is_admin', 'current_tenant_id', 'current_user_is_active');
```

Then state the intended end state explicitly (`anon` and PUBLIC named, not
assumed removed) and re-run the query to confirm.

### 4.2 Two RESTRICTIVE policies on `preorders`

```sql
CREATE POLICY "blocked accounts cannot create preorders"
  ON public.preorders AS RESTRICTIVE FOR INSERT TO authenticated
  WITH CHECK (public.current_user_is_active());

CREATE POLICY "blocked accounts cannot change preorders"
  ON public.preorders AS RESTRICTIVE FOR UPDATE TO authenticated
  USING (true)
  WITH CHECK (public.current_user_is_active());
```

No restrictive policy on SELECT or DELETE (§ 3.1, § 3.3).

`USING (true)` is stated rather than omitted, so the policy provably imposes
nothing on which rows are updatable and only constrains the resulting row.

### 4.3 Two RESTRICTIVE policies on `subscriptions`

```sql
CREATE POLICY "blocked accounts cannot create subscriptions"
  ON public.subscriptions AS RESTRICTIVE FOR INSERT TO authenticated
  WITH CHECK (public.current_user_is_active());

CREATE POLICY "blocked accounts cannot change subscriptions"
  ON public.subscriptions AS RESTRICTIVE FOR UPDATE TO authenticated
  USING (true)
  WITH CHECK (public.current_user_is_active());
```

Unsubscribe (DELETE) stays open, matching § 3.1.

### 4.4 Client changes shipping with the DDL (§ 3.5)

Port `catalog.html:242–263`'s block — `isPending` / `isPaused` / `isBlocked`,
the banner, and the disabled-button treatment — to:

- **`subscriptions.html`**: disable the series-search subscribe buttons, the
  reserved-suggestions subscribe buttons, and the search input; render the
  banner. Leave **unsubscribe** enabled (§ 3.1). Follow the existing
  impersonation precedent at `subscriptions.html:490` — render disabled with a
  title, do not hide.
- **`mylist.html`**: disable the quantity `−`/`+` stepper; render the banner.
  Leave Remove enabled.

Keep the copy identical to `catalog.html`'s `PAUSED_BTN_LABEL` /
`PAUSED_BANNER_BODY` rather than writing new strings — three surfaces saying the
same thing three ways is what F121 exists to stop. Consider hoisting both
constants and the `isBlocked` derivation into `app.js`; that is a judgement call
for the executing session, not a requirement.

### 4.5 The F109 trigger

```sql
CREATE OR REPLACE FUNCTION public.preorders_block_ordered_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_dist      text;
  v_code      text;
  v_withdrawn timestamptz;
  v_net       integer;
BEGIN
  -- (1) Enforce against end-user sessions only (§ 3.7). Service role, the SQL
  --     Editor, and tenant-cascade teardown all have no auth.uid(); admins keep
  --     a repair path through the app. IS TRUE, not NOT, per F126.
  IF auth.uid() IS NULL THEN RETURN OLD; END IF;
  IF current_user_is_admin() IS TRUE THEN RETURN OLD; END IF;

  SELECT c.distributor,
         CASE WHEN c.distributor = 'PRH'
              THEN COALESCE(NULLIF(c.isbn, ''), NULLIF(c.item_code, ''), NULLIF(c.upc, ''))
              ELSE COALESCE(NULLIF(c.item_code, ''), NULLIF(c.upc, ''), NULLIF(c.isbn, ''))
         END,
         c.withdrawn_at
    INTO v_dist, v_code, v_withdrawn
    FROM catalog c
   WHERE c.id = OLD.catalog_id;

  -- (2) F110 § 2.2 — a withdrawn title overrides this guard AND the fulfilled
  --     guard. Checked before anything else so the exception cannot be reached
  --     around. Mirrors app.js:863.
  IF v_withdrawn IS NOT NULL THEN RETURN OLD; END IF;

  -- (3) No resolvable distributor code (or no catalog row) — nothing to match.
  IF v_code IS NULL THEN RETURN OLD; END IF;

  -- (4) The ledger is SIGNED since F117 — SUM, never EXISTS. A code whose rows
  --     net to <= 0 was rejected or corrected away and must stay cancellable.
  --     Same rule as get_ordered_codes()'s 'ordered' vs 'unavailable'.
  SELECT COALESCE(SUM(quantity), 0) INTO v_net
    FROM order_submissions
   WHERE tenant_id  = OLD.tenant_id
     AND distributor = v_dist
     AND order_code  = v_code;

  IF v_net > 0 THEN
    RAISE EXCEPTION
      'Cannot cancel: the store has already ordered this title from the distributor'
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN OLD;
END;
$function$;

CREATE TRIGGER trg_preorders_block_ordered_delete
  BEFORE DELETE ON public.preorders
  FOR EACH ROW EXECUTE FUNCTION public.preorders_block_ordered_delete();
```

**Scope note — `fulfilled` is deliberately NOT in this trigger.** F109 offers it
as optional (*"and, if wanted, when `fulfilled = true`"*). Leaving it out keeps
this change to one behaviour, and F115/F122 have both shown `fulfilled` to be an
unreliable signal — it has twice been set on titles that never arrived. Adding
it later is additive. If Rick wants it, it belongs after step (2) so the
withdrawn exception still overrides it, exactly as `app.js:896` does.

**Grants — F124 again.** The trigger function is called by the trigger, not by a
role, so no role needs EXECUTE. Revoke `PUBLIC`, `anon` and `authenticated`
explicitly and grant nothing.

### 4.6 F10 and cascade interactions, stated rather than discovered

- `preorders.user_id → user_profiles.id` is `ON DELETE NO ACTION` (**F10**), so
  deleting a profile does not cascade into `preorders` — it *fails*. The trigger
  is therefore never reached from a profile delete, and F95's `deleteUser()`
  ordering (clear preorders first) is unchanged in shape.
- `preorders.catalog_id → catalog.id` is `ON DELETE NO ACTION` likewise, so
  `purge_stale_catalog()` cannot reach the trigger either.
- `preorders.tenant_id → tenants.id` **is `ON DELETE CASCADE`**, and a
  `BEFORE DELETE` trigger fires once per cascaded row. Dropping a tenant is the
  one path that could hit the trigger in bulk. The § 3.7 exemption covers it
  (teardown has no `auth.uid()`), and V11 proves it rather than assuming it.

### 4.7 What this does NOT fix

Named so a later session does not read this plan as covering them:

- **The monthly import still auto-reserves for blocked customers.** `import.js`
  fetches `subscriptions` with no filter on the owner's profile status
  (line 670), and service role bypasses RLS entirely. A paused customer's
  subscriptions keep generating reservations. That is arguably correct — pause
  is about the customer collecting, not about the store's ordering — but it is a
  behaviour nobody has decided. **Scripts-repo work; out of scope here.**
- **`invite-customer` sets `status:'active'` when the invite is sent** (F126), so
  an unanswered invite is an *active* account and this predicate does not touch
  it.
- **The FOC lock (`isFocPast`/`isFocLocked`) stays client-side.** Same shape as
  F109, not the same finding. Untouched.
- **`fulfilled`** — § 4.5.

---

## 5. Scope

### IN

- `current_user_is_active()` (new DEFINER helper) + explicit grants.
- Four RESTRICTIVE policies: INSERT and UPDATE on `preorders` and on
  `subscriptions`.
- `preorders_block_ordered_delete()` + `trg_preorders_block_ordered_delete`.
- Client gates on `subscriptions.html` and `mylist.html`; no change to
  `catalog.html`'s gate beyond possibly hoisting shared constants.
- Two new SQL files in `docs/sql/`, following the F124 convention of explicit
  grants in the file itself.
- Playwright coverage for each gate.

### OUT — stop and ask

- Any change to `users manage own preorders`, `admins manage tenant preorders`,
  or any existing policy. This plan is purely additive.
- Any change to `isFocPast` / `isFocLocked`, or to the F110 withdrawn exception's
  call sites.
- `fulfilled` in the trigger (§ 4.5).
- The import's subscriber-status question (§ 4.7).
- `user_profiles` policies, `is_admin` editing (F126 cut it), or the `'invited'`
  status question.
- Anything in `docs/technical-reference.md` § 7 beyond the corrections listed in
  § 9 — that file is edited by whoever owns the findings index, not from here.

---

## 6. Runbook

Staging only until Rick explicitly requests promotion. **Every SQL step is
Rick-in-the-loop.**

### Session 1 — F127, the status boundary

1. **V0 pre-flight** (§ 7). Do not proceed if it fails.
2. Write `docs/sql/current-user-is-active-and-status-policies.sql` containing
   § 4.1 + § 4.2 + § 4.3, the grant block derived from the § 4.1 query (**not**
   copied from this plan), and its own post-DDL verification block.
3. Rick runs it in the **staging** SQL Editor.
4. Gates **V1–V7**.
5. Client changes per § 4.4 on a feature branch.
6. New Playwright spec; full suite as the gate (push to staging *first* —
   the suite tests the deployed site, CLAUDE.md § Smoke-test ordering).
7. Fixture teardown, **verified by live SELECT returning zero rows** (V13).
8. Real-browser check by Rick on staging: sign in as a paused fixture account,
   confirm the banner and disabled controls on all three pages.

### Session 2 — F109, the ordered-cancel trigger

1. Re-run **V0**.
2. Write `docs/sql/preorders-block-ordered-delete.sql` (§ 4.5 + grants + its own
   verification block).
3. Rick runs it in the **staging** SQL Editor.
4. Gates **V8–V12**.
5. Extend spec 15 (which already owns the order-ledger path).
6. Full suite; teardown verified by SELECT.
7. **V11 is the gate that decides whether this can ship at all** — if
   service-role teardown is blocked, the Playwright suite cannot tear itself
   down and the trigger must not go to production.

### Production promotion — Rick's call, both sessions

Order matters: **SQL files first, on production, verified — then the client via
PR.** Same sequence as the F117 promotion. The client changes are inert without
the DDL; the DDL without the client produces mystery 403s (§ 3.5), so the client
must not lag far behind.

---

## 7. Verification gates

Each gate states its **failure output** as well as its pass condition, per
CLAUDE.md § *A verification step that cannot fail is not a verification step*.

| Gate | Check | Pass | Fail looks like |
|---|---|---|---|
| **V0** | Policy inventory pre-flight, both tables, run on the target environment (§ 8 query) | `unexpected=0, total=2` for `preorders`; `unexpected=0, total=2` for `subscriptions` | any non-zero `unexpected`, or `total` ≠ 2 → **STOP**, § 2.1 is wrong for this environment and the plan is invalid |
| **V1** | Helper exists with the right properties | `prosecdef=true`, `provolatile='s'`, `proconfig` contains `search_path=public` | any of the three differs |
| **V2** | Helper truth table, five cases: active non-admin / pending non-admin / suspended non-admin / pending **admin** / no identity | `true, false, false, true, false` | any `NULL` in the result is the F126 hazard reproduced — **STOP** |
| **V3** | Helper grants (§ 4.1) mirror `current_user_is_admin()` | `authenticated` has EXECUTE; `anon` and PUBLIC do not | `authenticated` missing → RLS evaluation itself will fail |
| **V4** | **F127 negative — the probe that returned 201 at filing.** A `status='pending'` fixture, signed in as itself, `POST /rest/v1/preorders` | **HTTP 403**, code `42501` | **HTTP 201** — the exact result F127 recorded, i.e. nothing changed |
| **V5** | F127 positive control — same fixture set to `'active'` | **HTTP 201**, row persists | 403 → the predicate is too tight and real customers are locked out |
| **V6** | F127 non-regression — the pending fixture can still `GET` its own preorder and `DELETE` it | 200 with the row; 204 and the row is gone | 403 or an empty GET → § 3.1/§ 3.3 violated, customers lose their own list |
| **V7** | **Admin impersonation survives.** Admin JWT + a **suspended** customer's `user_id` → `POST /rest/v1/preorders` | **HTTP 201** | 403 → the predicate reached the admin policy; § 2.2 is wrong |
| **V8** | Same as V4/V5/V6 for `subscriptions`: pending → subscribe 403, active → 201, pending → unsubscribe 204 | as stated | subscribe 201 while pending is the § 2.4 hole still open |
| **V9** | **F109 negative — the probe that returned 204 at filing.** Customer JWT, direct `DELETE /rest/v1/preorders` on a row whose code nets **> 0** in the ledger | **HTTP 4xx**, `check_violation` | **HTTP 204** — the exact result F109 recorded |
| **V10** | **F110 withdrawn exception intact.** Same shape, but `catalog.withdrawn_at` set **and** a ledger row present | **HTTP 204**, row gone | 4xx → the withdrawn exception is broken and MIDNIGHT X-MEN #2 is uncancellable again |
| **V11** | **Service-role teardown unaffected.** Service-role `DELETE` of a preorder whose code nets > 0 | **HTTP 204** | 4xx → Playwright teardown and tenant teardown are both broken → **do not promote** |
| **V12** | Signed-ledger correctness. A code whose rows sum to **0** or **negative** (a rejection / an F117 adjustment) | **HTTP 204** — cancellable | 4xx → the trigger tests existence, not sum; § 2.6 violated |
| **V13** | Every fixture torn down | live `SELECT` returns **0** rows for each seeded table | any non-zero |
| **V14** | Full Playwright suite on the deployed staging build | green at or above the 103/103 baseline, `PLAYWRIGHT_EXIT=0` | any failure, especially in spec 15 (ledger) or the teardown helpers |
| **V15** | Import unaffected — `node --check` plus a `--no-write` dry run | clean; confirms no `preorders` DELETE path exists (§ 2.3) | any DELETE against `preorders` appearing in the dry-run log |

**V4, V9 and V11 are the gates that matter.** V4 and V9 each re-run the exact
probe that produced the finding, so each has a known, documented failure output
(201 and 204) that is unmistakably different from its pass output. V11 is the
one that can veto the F109 half entirely.

---

## 8. The pre-flight query (V0)

Run in the SQL Editor on the environment being changed. This is also the query
that settles § 2.1 live rather than from repo evidence.

```sql
SELECT tablename,
       count(*) AS total_policies,
       count(*) FILTER (
         WHERE policyname NOT IN (
           'users manage own preorders',
           'admins manage tenant preorders',
           'users manage own subscriptions',
           'admins view tenant subscriptions'
         )
       ) AS unexpected_policies,
       string_agg(policyname || ' [' || cmd || ' ' || permissive || ' ' || roles::text || ']',
                  E'\n  ' ORDER BY policyname) AS policy_list
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('preorders', 'subscriptions')
GROUP BY tablename
ORDER BY tablename;
```

**Pass (F16 closed, § 2.1 correct):** two rows, each `total_policies = 2`,
`unexpected_policies = 0`, and `policy_list` naming only the four expected
policies, all `PERMISSIVE`.

**Fail (F16 open):** `preorders` reads `total_policies = 4`,
`unexpected_policies = 2`, and `policy_list` names
`admins write tenant preorders` and `admins view tenant preorders`.

The two outputs cannot be confused: the counts differ and the names are printed.

**Re-run this same query after the DDL.** Expected then: `preorders` = 4 total
(2 permissive + 2 restrictive), `subscriptions` = 4, with `unexpected_policies`
now 2 on each — the two new restrictive ones, named in `policy_list` and
tagged `RESTRICTIVE`. That difference is itself the confirmation the DDL applied.

---

## 9. Doc corrections owed — NOT owned by this plan

Established by § 2.1, to be applied by whoever owns the findings index:

1. **§ 7.1 `preorders`** — header reads *"(4 policies; see F16)"*; the block
   lists `admins write tenant preorders` and `admins view tenant preorders`,
   neither of which exists on either environment. The trailing paragraph
   (*"The 'admins write' policy lacks a row-level tenant check…"*) goes with it.
2. **§ 3**, around line 271 — *"The `preorders` admin policies (F16) demonstrate
   this: three admin-related…"* — present tense about a state that ended
   2026-05-10.
3. **§ 13 F127's root-cause table** — reproduces the same four rows and cites
   F16 as live. F127's *"Fix direction"* and *"Related"* both describe the
   `preorders` policy set as carrying an open defect; it does not.
4. **§ 13 F16** — the entry itself is correct. It should gain a line recording
   that production was fixed separately, by the Phase 4.4 migration on
   2026-05-31, not by the 2026-05-10 staging hot-fix.
5. **§ 4.11 `order_submissions` constraints** — still lists
   `CHECK quantity >= 1`, dropped by `docs/sql/order-submissions-signed-quantity.sql`
   (F117) on both environments. § 6.8's `get_ordered_codes()` shape may have the
   same lag.

Items 1–3 are instances of **F92**, and item 3 is a textbook **F106**: a wrong
value in a doc propagating into new work and surviving review, because review
compares the new work *to the doc*. F127 was filed three months after F16 was
fixed and inherited § 7's stale table without re-reading the database.

---

## 10. Rollback

Every step is independently reversible. Nothing in this plan mutates a row.

| Step | Revert |
|---|---|
| Restrictive policies on `preorders` | `DROP POLICY "blocked accounts cannot create preorders" ON public.preorders;` and `DROP POLICY "blocked accounts cannot change preorders" ON public.preorders;` |
| Restrictive policies on `subscriptions` | `DROP POLICY "blocked accounts cannot create subscriptions" ON public.subscriptions;` and `DROP POLICY "blocked accounts cannot change subscriptions" ON public.subscriptions;` |
| Trigger | `DROP TRIGGER trg_preorders_block_ordered_delete ON public.preorders;` — drop the **trigger** first; the function is inert without it |
| Trigger function | `DROP FUNCTION public.preorders_block_ordered_delete();` |
| Helper | `DROP FUNCTION public.current_user_is_active();` — **only after** all four policies are dropped, or the drop fails on dependency |
| Client changes | `git revert` the feature commit |

**Order on a full rollback:** policies → trigger → functions. Reverse of apply.

**No data is at risk in either direction.** The policies only ever *refuse*
writes, so reverting restores the pre-existing (permissive) behaviour exactly;
the trigger only ever *refuses* deletes; and no row is written, updated or
deleted by any statement in this plan.

**The one-way concern is the opposite of the usual one:** if the DDL ships and
the client gates do not, blocked customers get an unexplained *"Failed to
reserve"*. That argues for reverting the DDL rather than rushing the client.

---

## 11. Completion criteria

### Session 1 — F127

- [ ] V0 green on staging before any DDL
- [ ] `docs/sql/current-user-is-active-and-status-policies.sql` committed to
      `staging` before it is run (§ Document Integrity)
- [ ] V1, V2, V3 green — including all five rows of V2's truth table with no NULL
- [ ] V4 green — the pending fixture is refused with 403/`42501`
- [ ] V5, V6 green — active works, and the pending fixture keeps read + cancel
- [ ] V7 green — admin impersonation writes for a suspended customer
- [ ] V8 green — all three `subscriptions` cases
- [ ] Client gates live on `subscriptions.html` and `mylist.html`
- [ ] V14 green (full suite, post-push, on the deployed build)
- [ ] V13 green — fixtures gone, confirmed by live SELECT
- [ ] Real-browser check by Rick on staging
- [ ] V0 re-run post-DDL shows the two new restrictive policies

### Session 2 — F109

- [ ] V0 green
- [ ] `docs/sql/preorders-block-ordered-delete.sql` committed before it is run
- [ ] V9 green — customer direct DELETE refused
- [ ] V10 green — **withdrawn title still cancellable**
- [ ] V11 green — **service-role teardown still works**
- [ ] V12 green — a net-zero / net-negative code is still cancellable
- [ ] V14, V13, V15 green
- [ ] Real-browser check: a withdrawn reservation is still removable from both
      My List surfaces

### Both, before either finding is closed

- [ ] Applied and verified on **production**, gates re-run there
- [ ] Post-deploy write-smoke on production (reserve → correct `tenant_id` →
      cancel → row gone), run by hand — the Playwright runner is barred from prod
- [ ] § 13 F127 and F109 updated to Resolved with the evidence
- [ ] The § 9 doc corrections applied

---

## 12. Deploy log

*(Empty — nothing has been applied. Record staging and production separately,
with the actual gate outputs, not "green".)*
