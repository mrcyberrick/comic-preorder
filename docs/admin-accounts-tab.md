# Admin — the Accounts tab

**Origin:** Rick's direction + mockup, 2026-08-09, immediately after F121's
restructure closed. *"Paper Customers should be something more of a way to manage
users. I see this as the Accounts tab that contains all users."*

**Status:** **In execution 2026-08-09.**
**Target:** **staging only.**
**Branch:** `feature/admin-accounts-tab`
**Findings:** **F126** (profile editing — deferred, OUT), **F127** (status is not
an authorization boundary — filed, OUT).
**Last verified against live code:** `admin.html` @ `cc7d31d`, 2026-08-09 — every
range below read from disk this session.

---

## 1. What this replaces, and the gap it closes

Today the admin dashboard can only see a customer in one of three ways: they
hold a reservation **this catalog month** (By Customer), they are **awaiting
approval** (Pending), or they are a **paper** customer (Paper Customers).

**A customer who is active, digital, and simply has nothing reserved this month
appears nowhere.** Measured on staging: 25 profiles, 10 paper, 5 pending —
leaving 10 with no dedicated surface. On production: 27 profiles, 15 paper.

So this is not a re-layout of two tabs. It is the first surface that lists
**every user**, and Pending and Paper Customers become filters over it.

The second driver is Rick's, and it is about scale: the **impersonation
dropdown** on `catalog.html` (`:486–490`) loads **every non-admin profile** into
a `<select>` with no limit, no search, and no grouping. *"It will become
unmanageable soon."* A row-level **Manage** action is the better door.

---

## 2. Scope

### IN

1. **One `Accounts` tab** under Customers, listing every user in the tenant.
2. **Search** (name, email) and a **status/type filter** — All · Active · Paper · Pending · Paused.
3. **Sortable** Name, Email, Created.
4. **Row actions**, driven by the row's own state:
   - **Manage** — sets `AdminContext` and jumps to `catalog.html`, exactly as the Paper Customers list does today.
   - **Approve · Decline** — on pending rows (Rick 2026-08-09: *"Row actions should be available for pending accounts"*).
   - **Pause · Resume** — writes `status = 'suspended'` / `'active'`.
   - **Claim** — on paper rows, unchanged.
5. **One `New user` button.** Empty email → paper customer. Email present → invite. (Rick: *"No email - it is a paper customer, or if email is included it becomes an invite."*)
6. **`suspended` blocks like `pending`** — one line at `catalog.html:245`.
7. **Retire the `Pending` and `Paper Customers` tabs** into filters.

### OUT — stop and ask

| Not touched | Why |
|---|---|
| **Edit** (name, email, `is_admin`) | **F126**, deferred by Rick. **No Edit control is rendered at all** — not a disabled one. A dead button is the pattern F121 spent six sessions removing. |
| **RLS enforcement of `status`** | **F127.** Parity with `pending` is Rick's explicit choice; the gap is filed so it is visible rather than assumed closed. |
| What happens to a **paused customer's existing reservations** | F126 — genuinely undecided, and it has money attached once a title is ordered (F109/F117). Pause changes access, not reservations. |
| The `catalog.html` **impersonation dropdown** | Manage gets a better home here; whether the dropdown then goes is Rick's call once this is live. Removing it in the same session would confound the two. |
| `By Customer`, `Subscriptions` | Untouched. |

---

## 3. Design

### 3.1 The mockup's "Updated at" column is not buildable — dropped, with reasons

`user_profiles` has **no `updated_at` column** (§ 4.9: `id`, `full_name`,
`is_admin`, `created_by_admin`, `notes`, `created_at`, `status`, `email`,
`has_seen_welcome`, `is_paper`, `tenant_id`). The mockup shows one, and the
sample rows show it differing from Created — so it is meaningful in Rick's
mental model, not decoration.

Three options, and **the tempting one is wrong**:

| Option | Verdict |
|---|---|
| Add `updated_at` + trigger | A schema change. Out of a client-only session, but a legitimate small session if Rick wants it. |
| Derive "last active" from `usage_events` | **Rejected, and worth stating why.** `usage_events` is **purged at 90 days** (F90). The column would be blank for exactly the dormant customers the Pause feature exists to find — an empty cell that reads as "no activity" when it means "we deleted the evidence". That is the F115/F96 shape: an absent signal indistinguishable from a negative one. |
| **Drop the column** | **Chosen.** Ship Name · Email · Status · Created. |

**Flagged for Rick, not decided here:** if "Updated at" was meant as *last
activity* to drive the pause decision, neither existing column provides it, and
the honest fix is the schema change plus a rollup that survives the purge —
which is **F90**, already filed.

### 3.2 Capability was verified against a real admin session, not assumed

`docs/technical-reference.md` § RLS lists `user_profiles` policies as
admin-**SELECT**-only, with *"No INSERT or DELETE policy."* That would make
Pause impossible from the client. A 5.0 S3 note says an `admins manage tenant
profiles` (ALL) policy was added. **The two disagree, so neither was trusted.**

Probed on staging with an anon key + a real admin JWT — **no service key in the
request path**:

| Capability | Result |
|---|---|
| `SELECT` all tenant profiles with the list's columns | **200, 25 rows** |
| `PATCH status = 'suspended'` on another user (Pause) | **200, verified persisted** |
| `PATCH status = 'active'` (Resume) | **200, verified persisted** |

Fixtures torn down; probe profiles remaining = 0. **The doc is stale** — an
instance of the already-filed **F92**, corrected in place rather than filed anew.

### 3.3 Data source — its own fetch, not `loadData()`'s

`loadData()` selects `id, full_name` only (`:1113`), for `profileMap`. Accounts
needs `email, status, is_paper, is_admin, created_at` too. Rather than widen a
fetch that four other consumers depend on, Accounts gets its own
`ensureAccounts()` — the same idempotent-loader shape as `ensurePaperCusts()`
and `ensureFullData()`, loaded on first tab visit.

`Users.getPending()` and `PaperCustomers.list()` become **redundant for this
surface** (both are filtered subsets of the same table) but are **left in
`app.js` untouched** — `PaperCustomers.list()` still feeds the Ordering-side
entry pane, and removing an API in the same session that adds a surface would
confound two changes.

### 3.4 One row, one state — the vocabulary rule

Every row states **one** status, and the actions follow from it:

| Status shown | Condition | Actions |
|---|---|---|
| **Pending** | `status = 'pending'` | Approve · Decline · Manage |
| **Paused** | `status = 'suspended'` | Resume · Manage |
| **Paper** | `is_paper` and active | Manage · Claim |
| **Active** | everything else | Manage · Pause |

`is_paper` and `status` are **orthogonal columns**, so a paper customer could in
principle be pending or suspended. Status wins the label when they conflict, and
paper is shown as a separate marker rather than a competing status — otherwise
one row would claim two states, which is the F121 defect in a single table cell.

### 3.5 New user — one button, branching on email

Reuses the existing invite modal (`:484–530`, handler `:2862+`), with email made
**optional**:

- **email empty** → `PaperCustomers.create(name)` — the `create-paper-customer` Edge Function, no email sent.
- **email present** → `invite-customer` Edge Function, unchanged.

The modal states which will happen **before** the click, from the email field's
own content — not after, in a toast.

### 3.6 The `suspended` block

`catalog.html:245` is the single definition; 8 sites in that file read it.

```js
// before
const isPending = !profile?.is_admin && profile?.status === 'pending';
// after
const isBlocked = !profile?.is_admin &&
  (profile?.status === 'pending' || profile?.status === 'suspended');
```

**Client-side only, deliberately (F127).** Paused is a UI block. It must not be
described anywhere — copy, docs, or commit message — as a hard one.

---

## 4. Gates

| Gate | Check | Pass condition |
|---|---|---|
| **V1** | The list is complete | Accounts shows users that appear in **neither** Pending nor Paper Customers — the gap this closes |
| **V2** | Filters partition correctly | Active + Paper + Pending + Paused counts reconcile to the All count; no row appears under two filters |
| **V3** | **Pause works and blocks** | Pause a seeded active user → status persists as `suspended` → that user's own session cannot reserve through the UI → Resume restores it |
| **V4** | Pending row actions | Approve and Decline both work from an Accounts row, badge and attention dot update |
| **V5** | New user branches | Empty email → paper customer created, no email sent; email present → invite sent |
| **V6** | Manage still jumps | Manage sets `AdminContext` and lands on `catalog.html` managing that customer |
| **V7** | Retired tabs are gone | No `Pending` or `Paper Customers` tab; nothing references their removed containers |
| **V8** | Full suite | Green, with specs repointed for the retired tabs |

**V3 is the gate that matters** — it is the only one proving the new status does
anything. V1 is second: it proves the surface exists for a reason.

### 4.1 Spec fallout — grepped before writing code

Per session 4 § 7.6, run **before** the first edit:

| Selector | Hits | Action |
|---|---|---|
| `[data-tab="pending"]` | `17-admin-modes.spec.ts:110`, `zz-tmp-v4v5-pending.spec.ts:69,92` | repoint to the Accounts tab |
| `#pending-list` / `.pending-approve-btn` / `.pending-decline-btn` | `zz-tmp-v4v5-pending.spec.ts` | repoint to Accounts rows |
| `[data-tab="paper-customers"]` | `17-admin-modes.spec.ts` (session-6 block) | repoint |
| `#paper-customer-list` | `17-admin-modes.spec.ts` (V1, V2, V3) | repoint |

---

## 5. Completion criteria

- [ ] § 3 applied, every range re-verified against disk immediately before edit
- [ ] V1–V8 green, Playwright's **own** exit code captured
- [ ] All seeded fixtures torn down, verified by live SELECT
- [ ] `technical-reference.md` § RLS `user_profiles` corrected (§ 3.2), citing F92
- [ ] Real-browser check by Rick on staging
- [ ] F126 / F127 cross-references accurate

## 6. Rollback

Single feature branch. `admin.html` + `catalog.html` + `style.css`; **no DB
change, no schema change, no Edge Function change.** `git revert` the merge.
Pause writes only an existing, already-legal `status` value — a revert leaves
any suspended row readable and restorable by the same PATCH.

## 7. Deploy log

*(execution in progress)*
