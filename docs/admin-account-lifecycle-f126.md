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
3. **An "Invited, never responded" filter**, derived — no new status.
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

*(not started)*
