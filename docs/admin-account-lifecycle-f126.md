# Admin — account lifecycle (F126)

**Origin:** F126, filed 2026-08-09 while scoping the Accounts tab and deferred
by Rick the same day. Reopened 2026-08-09 with all three open decisions answered.

**Status:** **Planned, not started.**
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
| Widen `user_profiles_status_check` for an `'invited'` state | **No schema change.** "Unanswered invite" is derived: `created_by_admin AND last_sign_in_at IS NULL`. |
| An Edge Function to edit email | **None.** Email is read-only; only `full_name` and `is_admin` are editable, and both live in `user_profiles`. |
| Decide what pause does to existing reservations | **Already the shipped behaviour** — pause blocks *new* reservations and leaves existing ones alone. This is documentation, not code. |

**One DB object remains: a single SECURITY DEFINER RPC.** That is the whole
backend surface of this session.

---

## 2. Scope

### IN

1. **`get_account_activity()`** — one SECURITY DEFINER RPC exposing
   `last_sign_in_at` and `email_confirmed_at` for the caller's tenant, admin-only.
2. **A sortable "Last seen" column** on Accounts.
3. **An "Invited, never responded" filter**, derived — no new status.
4. **An Edit control**: `full_name` and `is_admin`. Email displayed, **read-only**.
5. **Document** that pause leaves existing reservations untouched — in the
   confirm dialog, so the operator reads it at the moment of the decision.

### OUT — stop and ask

| Not touched | Why |
|---|---|
| **Editing email** | Rick 2026-08-09. `user_profiles.email` is a denormalized copy of `auth.users.email` with **no sync trigger (F25)**, and `auth.users.email` is the *login identity*. Editing the profile copy alone would look like it worked and silently not move the login. Doing it properly needs the GoTrue admin API → service role → an Edge Function. Out. |
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
  IF NOT current_user_is_admin() THEN
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

### 3.3 "Invited, never responded" — derived, and why that beats a status

`created_by_admin = true AND last_sign_in_at IS NULL`.

- `invite-customer` sets `created_by_admin: true` and `status: 'active'`
  (`supabase/functions/invite-customer/index.ts:136–138`).
- `register-customer` (self-signup) sets `'pending'`.

So the pair already separates *invited* from *self-registered* — the missing
half was only ever "did they ever turn up", which the RPC now supplies.

**Rejected: adding an `'invited'` status.** It needs the CHECK widened on both
environments, `invite-customer` changed, and **every** status consumer taught a
fourth value — `catalog.html`'s block, the Accounts filters, By Customer,
analytics. All to express something two existing columns already imply.

**Also rejected, and already measured — do not retry it:** `has_seen_welcome` as
a proxy for "never signed in" agrees only **8 of 12** on production. Four
signed-in customers read `false`. It would have been free; it is also wrong.

### 3.4 Edit — two fields, and two guards on the second

`full_name` is unremarkable. **`is_admin` is a privilege-escalation surface** and
needs guards the UI must not omit:

1. **You cannot revoke your own admin.** One misclick otherwise locks the
   operator out of the surface they would need to undo it.
2. **You cannot revoke the last admin.** Same failure, one step removed.

Neither is enforced by the database — the `admins manage tenant profiles` ALL
policy permits any admin to PATCH `is_admin` on anyone, and **that is already
true today**; this session only makes it reachable from the UI. Worth stating
plainly rather than discovering later: these guards are client-side, like
F127's, and a hand-crafted request bypasses them.

Email renders read-only with the reason on screen — *"login address; to change
it, re-invite the customer"* — so the constraint is visible rather than
mysterious.

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
| **V6** | Edit writes | `full_name` change persists and re-renders; `is_admin` toggle persists |
| **V7** | Edit guards hold | Own-admin revoke blocked; last-admin revoke blocked |
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

*(not started)*
