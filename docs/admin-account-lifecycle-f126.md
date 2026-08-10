# Admin — account lifecycle (F126)

**Origin:** F126, filed 2026-08-09 while scoping the Accounts tab and deferred
by Rick the same day. Reopened 2026-08-09 with all three open decisions answered.

**Status:** **COMPLETE AND LIVE IN PRODUCTION 2026-08-10** — staging `54ca354` + `89545ea` (V1–V9 green, 112 passed, `PLAYWRIGHT_EXIT=0`), promoted via **PR #116, merge `aa35d7f`**. Rick's real-browser check passed; RPC applied to production ahead of the client merge. **Post-deploy write-smoke owed** (§ 8).
**Target:** **staging only.**
**Branch:** `feature/admin-account-lifecycle`
**Findings:** **F126** (this), **F25** (the email trap that shaped it),
**F127** (why "paused" is a UI block), **F124** (the grant lesson the RPC obeys).
**Last verified against live code:** `admin.html` / `app.js` / `catalog.html`
@ `2b15f6b`, 2026-08-09.

---

## 1. What Rick's three answers removed

This entry was filed expecting a schema migration, an Edge Function and a
four-way status collision. **All three are gone**, and the session is roughly
half the size it looked:

| Feared | Actually |
|---|---|
| Widen `user_profiles_status_check` for an `'invited'` state | **No schema change.** The filter is derived — and became **"Never signed in"** at implementation, because `created_by_admin` cannot support the word "invite" (§ 3.3). |
| An Edge Function to edit email | **None.** Email is read-only; **`full_name` is the only editable field.** |
| Decide what pause does to existing reservations | **Already the shipped behaviour** — pause blocks *new* reservations and leaves existing ones alone. This is documentation, not code. |
| A privilege-escalation surface for `is_admin` | **Cut 2026-08-09** — stays a Supabase-console task (§ 2 OUT). Removes the control, its two guards, and a gate. |

**One DB object remains: a single SECURITY DEFINER RPC.** That is the whole
backend surface of this session.

---

## 2. Scope

### IN

1. **`get_account_activity()`** — one SECURITY DEFINER RPC exposing
   `last_sign_in_at` and `email_confirmed_at` for the caller's tenant, admin-only.
2. **A sortable "Last seen" column** on Accounts.
3. **A "Never signed in" filter**, derived — no new status. (Planned as
   "Invited, never responded"; **corrected at implementation** — see § 3.3.)
4. **An Edit control: `full_name` only.** Email displayed, **read-only**.
5. **Document** that pause leaves existing reservations untouched — in the
   confirm dialog, so the operator reads it at the moment of the decision.

### OUT — stop and ask

| Not touched | Why |
|---|---|
| **Editing email** | Rick 2026-08-09. `user_profiles.email` is a denormalized copy of `auth.users.email` with **no sync trigger (F25)**, and `auth.users.email` is the *login identity*. Editing the profile copy alone would look like it worked and silently not move the login. Doing it properly needs the GoTrue admin API → service role → an Edge Function. Out. |
| **Editing `is_admin`** | **CUT 2026-08-09, Rick's call, in favour of keeping it a Supabase-console task.** It was planned, then cut on being told what it is: a **privilege-escalation surface**. Granting or revoking admin is rare, consequential, and irreversible-by-the-victim — an operator who revokes their own admin loses the surface they would need to undo it. **The database already permits it** (the `admins manage tenant profiles` ALL policy lets any admin PATCH `is_admin` on anyone, today, with no UI), so this is not closing a hole — it is declining to *open a door* to one, and the two client-side guards that door would have needed are guards a hand-crafted request ignores anyway (the **F127** shape). A rare, dangerous action belongs where it is deliberate. |
| **RLS enforcement of `status`** | **F127**, still its own session. This one does not make "paused" any harder than it already is. |
| **Cancelling a paused customer's reservations** | Rick 2026-08-09: leave them. Pause blocks new reservations; the already-ordered copies are still the store's to sell. Avoids any interaction with F109/F117 money. |
| **An `'invited'` status value** | Superseded by § 3.3. |
| The `catalog.html` **impersonation dropdown** | Still Rick's call, still deferred (Accounts § 2). |

---

## 3. Design

### 3.1 The RPC — admin-gated in the BODY, not by the grant

```sql
CREATE OR REPLACE FUNCTION public.get_account_activity()
RETURNS TABLE(id uuid, last_sign_in_at timestamptz, email_confirmed_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF current_user_is_admin() IS NOT TRUE THEN   -- NOT `NOT (...)` — see § 7.1
    RAISE EXCEPTION 'get_account_activity: admin only' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
    SELECT u.id, u.last_sign_in_at, u.email_confirmed_at
    FROM auth.users u
    JOIN public.user_profiles p ON p.id = u.id
    WHERE p.tenant_id = current_tenant_id();
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_account_activity() TO authenticated;
REVOKE ALL ON FUNCTION public.get_account_activity() FROM PUBLIC, anon;
```

**Why the gate is in the body and not the grant, which is the one thing here
that could be got wrong.** `get_ordered_codes()` is the model, but it grants to
`authenticated` because *every customer* needs it. This function is admin-only —
and **admins are `authenticated` too**, so there is no role to grant to that
excludes customers. Revoking `authenticated` would lock out the only intended
caller. The gate therefore has to be `current_user_is_admin()` inside the
function, with `anon` and `PUBLIC` revoked explicitly per **F124** (Supabase's
default privileges grant EXECUTE to `anon` and `authenticated` on every new
function in `public`; `REVOKE … FROM PUBLIC` does **not** remove them).

Tenant scope is derived from `current_tenant_id()` internally, never from a
client parameter — the same rule every RLS-adjacent function here follows.

**It exposes two timestamps and nothing else.** No email, no name, no
`raw_user_meta_data`. `auth.users` is a table the app has deliberately never
exposed (there is no `public.auth_users` view — a service-role read returns
404), and this should not become one by accident.

### 3.2 "Last seen" — a column, and what its blank means

Sortable, beside Created. **Blank is meaningful and must read as such**: a
customer who has never signed in shows *"never"*, not an empty cell. An empty
cell is the F115/F96 shape — an absent signal indistinguishable from a negative
one, which is exactly why the `has_seen_welcome` shortcut was rejected (§ 3.3).

### 3.3 "Never signed in" — derived, and renamed at implementation

**Planned as `created_by_admin = true AND last_sign_in_at IS NULL`, labelled
"Invited, never responded". That predicate is WRONG and shipped for one commit
before real staging data exposed it (§ 7.3).**

`created_by_admin` **defaults to `true`** and `register-customer` never sets it,
so a self-registered customer carries the same value as an invited one. The
column cannot distinguish them, and the label claimed it could.

**Shipped instead: `never signed in AND NOT paper AND NOT pending`.** That is
exactly what the data supports, it is the same operational signal Rick asked for,
and it implies the same action — call them. The two exclusions make it actionable
rather than merely true:

| Excluded | Why |
|---|---|
| `is_paper` | Paper customers never sign in **by design**. Including them buries the real cases under every paper customer in the store (10 of 21 on staging). |
| `status = 'pending'` | Already has its own filter and its own queue, where the action is approve-or-decline rather than chase. |

`Ronald Burke` — the production case this exists for — is `active` and non-paper,
so he matches either way.

**Still rejected: adding an `'invited'` status.** It needs the CHECK widened on
both environments, `invite-customer` changed, and **every** status consumer
taught a fourth value — `catalog.html`'s block, the Accounts filters, By
Customer, analytics.

**Also rejected, and already measured — do not retry it:** `has_seen_welcome` as
a proxy for "never signed in" agrees only **8 of 12** on production. Four
signed-in customers read `false`.

### 3.4 Edit — one field, and the two it deliberately does not touch

**`full_name` only.** A text input and a save. That is the whole control.

The two omissions are the interesting part, and both are visible on screen
rather than mysterious:

- **Email is read-only**, labelled *"login address — to change it, re-invite the
  customer"*. See § 2 OUT and **F25**.
- **`is_admin` is absent entirely** — not disabled, absent. Cut by Rick
  2026-08-09 once it was clear the control would be a privilege-escalation
  surface whose only protections would be client-side. Granting admin stays a
  Supabase-console task: rare, consequential, and better done somewhere the
  operator has to mean it.

**Absent, not disabled** — the same rule the Accounts tab already follows for
Edit itself. A greyed-out "Grant admin" checkbox would invite exactly one
question ("why can't I?") and answer it nowhere, which is the pattern F121 spent
six sessions removing.

**What this leaves the session with is one editable field**, no
privilege-escalation surface, and no client-side guard that a crafted request
could walk through.

### 3.5 Pause — the confirm dialog gains a sentence

No behaviour change. Pause already blocks new reservations and leaves existing
ones standing; that is now Rick's confirmed intent rather than an accident of
implementation. The confirm text says so, at the moment the decision is made:

> Pause **Jane Smith**? They stay signed in and keep their existing
> reservations — those still get bagged — but cannot reserve anything new until
> resumed.

---

## 4. Gates

| Gate | Check | Pass condition |
|---|---|---|
| **V1** | RPC is admin-only | A **non-admin** authenticated session calling `get_account_activity()` is refused (`42501`); an admin session gets rows |
| **V2** | RPC is tenant-scoped | A synthetic-tenant admin sees only their own tenant's users — zero founding rows |
| **V3** | RPC leaks nothing else | Returned columns are exactly `id`, `last_sign_in_at`, `email_confirmed_at` |
| **V4** | Last seen renders and sorts | Never-signed-in reads **"never"**, not blank; sort puts them together |
| **V5** | **The one that matters** — the invite filter finds the real case | On production data the filter would return `Ronald Burke` and nothing else; on staging, a seeded equivalent |
| **V6** | Edit writes | `full_name` change persists and re-renders across By Customer and Accounts |
| **V7** | Edit offers nothing else | Email input is `readonly`; **no `is_admin` control exists in the DOM at all** — asserted as an absence, so re-adding it later is a conscious act |
| **V8** | Pause unchanged | A paused customer keeps their reservations and still appears on the bagging list |
| **V9** | Full suite | Green |

**V1 and V5 are the gates that matter.** V1 because the RPC reads `auth.users`
and a wrong grant is the whole risk of this session; V5 because a filter that
does not surface the one real case is decoration.

### 4.1 Spec fallout — grep before editing

Per session 4 § 7.6, run **before** the first edit: any spec asserting the
Accounts column count, the filter option list, or row action sets will need
extending — spec 17's `accounts tab` block owns all three.

---

## 5. Completion criteria

- [ ] § 3 applied, ranges re-verified against disk first
- [ ] SQL run on **staging** by Rick (DB steps are Rick-in-the-loop), grants verified by execution not by reading
- [ ] V1–V9 green, Playwright's **own** exit code captured
- [ ] Fixtures torn down, verified by live SELECT
- [ ] Real-browser check by Rick
- [ ] F126 updated; F25 cross-reference accurate

## 6. Rollback

Client changes: `git revert`. The RPC: `DROP FUNCTION public.get_account_activity()`
— additive, read-only, and nothing else references it.

## 7. Deploy log

**Staging only, 2026-08-09.** One DB object (`get_account_activity`), plus
`admin.html` and `app.js`. No schema change, no Edge Function.

| Commit | What |
|---|---|
| `a5887f8` / `7f0180d` | Plan, then the `is_admin` cut |
| `1607793` | **SQL gate fix** — `IS NOT TRUE`, not `NOT (...)` |
| `54ca354` | Last seen, the filter, Edit name |
| `d925473` | End the SQL file on a check that can actually fail |
| `89545ea` | **The filter is "Never signed in", not "unanswered invite"** |

**Suite: 112 passed, 1 flaky, `PLAYWRIGHT_EXIT=0`, 16.1 min.** All six F126
gates green.

### 7.1 The SQL gate was open, and reading it would never have shown that

`IF NOT current_user_is_admin()` looked correct and was not.
`current_user_is_admin()` returns **NULL**, not false, when there is no user
identity — `auth.uid()` is NULL so its `user_profiles` lookup finds no row.
`NOT NULL` is NULL, an `IF` on NULL is not taken, and execution fell straight
**through** the gate.

It returned `200 []` rather than data only because `current_tenant_id()` was
*also* NULL and the WHERE matched nothing — **safe by a second accident.**

Caught by **calling** the deployed function, not by reading it. The signature was
right, the grants were right (`anon` correctly got `401 permission denied`), and
the gate still did not fire. Fixed to `IS NOT TRUE`, which refuses on both false
and NULL, then verified from outside: `403 admin only` for a caller with no
identity, `401` for anon, `200` with rows for a real admin session.

**Exposure, stated precisely rather than dramatically:** the real threat — a
logged-in non-admin customer — was refused throughout, because their profile
exists and the function returns `false`, not NULL. What was open was the
no-identity path, which `anon` could not reach either.

### 7.2 A verification step that cannot fail is not a verification step

The file originally ended on VERIFY 3, which reports the return **signature** —
identical before and after the gate fix. The Supabase SQL Editor shows the last
statement's result, so that is what the operator saw, three times, while the
probe kept reporting the gate open. **Three round-trips spent on a query that
could not distinguish the two states.**

VERIFY 4 now ends the file and reads the function body:

    SELECT position('IS NOT TRUE' in prosrc) > 0 AS gate_fixed

It can come back `false`. That is the whole point.

### 7.3 "Unanswered invite" was not derivable — the label was corrected, not the data

The filter shipped in `54ca354` as `created_by_admin AND never signed in`. It
matched a **self-registered pending account** on staging.

`created_by_admin` **defaults to `true`**, and `register-customer` never sets
it, so a self-registered customer carries the same value as an invited one. The
column cannot answer the question the filter was named for.

Renamed to **"Never signed in"** — exactly what is knowable, the same
operational signal Rick asked for, and the same action. Two exclusions make it
actionable rather than merely true: **paper** customers never sign in by design
(including them would bury the real cases under all ten), and **pending**
accounts have their own queue where the action is approve-or-decline.

`Ronald Burke`, the production case this exists for, is `active` and non-paper —
he matches either way.

**Found by looking at what the filter RETURNED on real data, not at whether it
ran.** A green test would have told me nothing: my own fixtures were all
`created_by_admin = true` and never-signed-in, so they passed under both the
wrong predicate and the right one.

### 7.4 Test defects, and one unexplained flake

- **V1 requested two identities that cannot coexist.** `adminPage` and
  `authenticatedPage` both derive from the same `page` fixture, so asking for
  both yields ONE page signed in as whichever ran last. The admin half failed
  with "admin only" — the assertion was right, the session was the customer's.
  Verified the function was fine (a real admin session outside Playwright got
  `200` with rows) **before** touching the test. The non-admin now gets its own
  browser context. **This is undocumented in the suite and fails looking like a
  permissions bug.**
- **`window.db` is undefined.** `app.js` declares `const db` at the top level of
  a classic script, so it lives in the global *lexical* environment, not on
  `window`. All three RPC calls in the new specs would have thrown. A bare `db`
  resolves inside `page.evaluate`; `declare const db: any` satisfies TypeScript.
- **One flake, not explained.** V6 (Manage) timed out once waiting for the
  Accounts **tab button** — static markup that exists before any JS — then
  passed on retry. **The obvious explanation was checked and rejected:** a grep
  for `429` matched, but on the *line number* in the source listing, not a rate
  limit. No rate limiting, no other slow test in the run. Recorded as
  transient-and-unexplained rather than given a tidy story; it is consistent
  with **F107**'s repeated-full-suite conditions (this was the fourth run of the
  day) but that is not evidence.

### 7.5 Owed before production

1. **Rick's real-browser check** on staging.
2. **The RPC must be created on PRODUCTION before the client is promoted** —
   `docs/sql/get-account-activity-rpc.sql`, and `gate_fixed = true` is the check
   that matters, not the signature. If the client ships first, Last seen reads
   **"unknown"** for every row: degraded by design rather than broken, but it
   would look like a defect.

### 7.6 Fixture teardown — verified by SELECT

`TEST_PW_*` profiles **0**, `status = 'suspended'` **0** (no customer left
blocked by a test), synthetic tenants **0**.

Two leftovers were found and cleaned first — a profile and a tenant timestamped
22:41 and 22:50, from the two suite runs **stopped mid-flight** when the build
moved under them. Stopping a run skips its teardown; worth remembering, since
that is a self-inflicted version of F95's pattern.

---

## 8. Production — PR #116, merge `aa35d7f`, 2026-08-10

Client-only for the app (`admin.html`, `app.js`). The SQL file in the diff was
**already applied to production by hand before the merge**, so merging changed
nothing in Postgres. Sequencing was deliberate: had the client shipped first,
Last seen would have read **"unknown"** for every row — degraded by design, but
indistinguishable from a defect to anyone looking at it.

### 8.1 Post-deploy verification (read-only)

| Check | Result |
|---|---|
| F126 markers served | ✅ `get_account_activity`, `Last seen`, `isNeverSignedIn`, the `never` filter option, `acct-edit`, `activityById` |
| `Users.setName` in `app.js` | ✅ served |
| Superseded label gone | ✅ **0** occurrences of "Invited, never responded" |
| **RPC gate on production** | ✅ **403 `get_account_activity: admin only`** for a caller with no identity |
| Row counts | ✅ `preorders` 2,005 · `order_submissions` 864 · `catalog` 11,724 · `user_profiles` 27 |
| Account mix | ✅ 15 paper · 0 pending · **0 suspended** — the pause path is live but unexercised |

### 8.2 The feature surfaces the exact case that prompted it

**"Never signed in" lists one person on production: `Ronald Burke`** — invited
2026-03-17, email never confirmed, never signed in, status `active`.

That is the whole point of the session, and it is worth stating that he was
**already findable before any of this shipped** — by a service-role query no one
was going to run. What changed is that he is now visible from a screen Rick opens
anyway, next to a filter that names the condition.

**He still needs a phone call.** Shipping the surface is not the fix.

### 8.3 Owed

- **Post-deploy write-smoke** — Rick's, by hand: a real browser session on
  production, which the Playwright runner is barred from by design.
