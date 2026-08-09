# Admin — the Accounts tab

**Origin:** Rick's direction + mockup, 2026-08-09, immediately after F121's
restructure closed. *"Paper Customers should be something more of a way to manage
users. I see this as the Accounts tab that contains all users."*

**Status:** **COMPLETE ON STAGING 2026-08-09** (`40b8bc4` + `617cbd7`) — V1–V8
green, **108/108**, `PLAYWRIGHT_EXIT=0`, zero flaky. **Rick's real-browser check
and production promotion both owed.**
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

- [x] § 3 applied, every range re-verified against disk immediately before edit
- [x] V1–V8 green, Playwright's **own** exit code captured — **108/108, `PLAYWRIGHT_EXIT=0`**
- [x] All seeded fixtures torn down, verified by live SELECT (§ 8.4)
- [x] `technical-reference.md` § RLS `user_profiles` corrected (§ 3.2), citing F92
- [ ] **Real-browser check by Rick on staging** — owed
- [x] F126 / F127 cross-references accurate

## 6. Rollback

Single feature branch. `admin.html` + `catalog.html` + `style.css`; **no DB
change, no schema change, no Edge Function change.** `git revert` the merge.
Pause writes only an existing, already-legal `status` value — a revert leaves
any suspended row readable and restorable by the same PATCH.

## 7. Deploy log

**Staging only, 2026-08-09.** Client-only (`admin.html`, `catalog.html`,
`app.js`); no DB change, no schema change, no Edge Function change.

| Commit | What |
|---|---|
| `ec40938` | This plan (doc-only) + the stale `user_profiles` RLS correction |
| `40b8bc4` | The Accounts tab, the Pause/Resume path, the one-button New user |
| `617cbd7` | Filters must partition the list — two defects the gate caught |

**Suite: 108 passed / 108 declared, `PLAYWRIGHT_EXIT=0`, 14.3 min, zero
failures, zero flaky.**

### 7.1 The gate that earned its place

**V2 was written expecting to be a formality and caught two real defects on its
first run** — both mine, both invisible on screen:

1. **"All" silently included admins that every status filter excluded.** So the
   counts could not reconcile: an admin appeared in one view and vanished from
   every other. Accounts now lists everyone (Rick's ask was literally *"contains
   all users"*), with an `admin` marker and **Pause suppressed on admin rows** —
   `catalog.html` exempts admins from the block, so the button would have
   written a status that changes nothing.
2. **The Paper filter matched a TYPE (`is_paper`) while the rows displayed a
   STATE.** A pending paper customer was counted under two filters and shown
   under a label it did not carry. Filtering now matches the state the row
   displays.

**That second one is F121's own defect — numbers on a page that do not
reconcile — reappearing inside the feature built to remove it.** Recorded
because the lesson is not "write more tests": it is that a *partition* assertion
(the parts sum to the whole) catches a class of incoherence that per-element
assertions never will, and it cost four lines.

### 7.2 Three test defects, each of a different kind

Worth separating, because only one was staleness:

- **V6 asserted a URL that can never appear.** Cloudflare Pages serves clean
  URLs, so `window.location.href = 'catalog.html'` lands on `/catalog`. Every
  other spec in the suite already matches `/\/catalog/`; this one did not, and
  timed out while the page snapshot showed the catalog rendering perfectly
  behind it. **Read the snapshot before theorising** — it said "catalog page" in
  its second line.
- **V6 then asserted the wrong element**, which exposed real behaviour:
  `#catalog-subtitle` only gains *"managing <name>"* inside
  `updateReservedStat()`, called on reserve/unreserve and **never on plain page
  load**. Arriving via Manage shows a fully-active impersonation session whose
  subtitle still reads "browse and reserve items". Pre-existing `catalog.html`
  behaviour, not caused by this session; the orange banner is the real signal
  and was correct throughout. Left alone rather than fixed — out of scope, and
  surfaced to Rick instead.
- **The repointed approve test would have asserted nothing.** It stubs the
  `approve-customer` Edge Function so no real mail is sent (F99, sender
  reputation). But Accounts re-reads `user_profiles` after a successful approve
  rather than optimistically removing the row — the more honest behaviour, since
  the old code showed success even when the write had not landed. Against a stub
  returning only `{"ok":true}` the row stays genuinely pending, so the new
  assertion would have been checking a state nothing changed. The stub now
  applies the function's DB effect before fulfilling.

### 7.3 One self-inflicted break, stated plainly

A Python `open(path, 'w')` truncates before writing. Mine then raised a
`UnicodeEncodeError` and left **`catalog.html` at 0 bytes**. The file is tracked
and its changes were uncommitted, so `git checkout --` restored it and the three
edits were redone. Every later write encodes to bytes *first* and opens the file
only once the encode has succeeded.

Separately, an HTML comment containing backticks was placed inside a JS template
literal and terminated the string, breaking the whole script. The `node --check`
gate caught it before it left the machine.

### 7.4 Fixture teardown — verified by SELECT

The V3 pause fixture creates a real auth user and pauses it. Verified after the
run: `TEST_PW_*` profiles **0**, `status = 'suspended'` profiles **0** (so no
customer was left blocked by a test), synthetic tenants **0**.

**Four orphaned `TEST_PW_Pending` profiles were also found and removed** — left
by earlier interrupted runs, not by this one, along with three `pw-*` profiles
and two synthetic tenants from the same interruptions. Cleaned in F95's required
order (preorders first, or the `ON DELETE NO ACTION` FK 409s the profile
delete). **This is F95's pattern in miniature**: nothing here was broken, but
that finding reached 292 orphans by nobody looking.

### 7.5 Owed

- **Rick's real-browser check on staging.**
- **Production promotion** — his call, not requested.
- The `#catalog-subtitle` impersonation gap (§ 7.2) — surfaced, not filed.
