# F92 catalog audit + F115 arrival-truth decision — one Rick-in-the-loop session

**STATUS:** NOT STARTED | staging=— | prod=— | findings=F92,F115
**Status:** **PLANNED — not started.** Written 2026-08-18.
**Target:** **read-only on both environments** for F92. F115 produces a **decision**, not code —
implementation is a separate session scoped by whatever is decided here.
**Rick-in-the-loop:** every F92 query runs in the Supabase SQL Editor. PostgREST cannot read the
Postgres catalog at all, which is the entire reason this residual survived three sweeps.
**Last verified against live:** 2026-08-18 — `origin/staging` `ce35dba`, `origin/main` `47d42dd`,
tree clean, no active phase or sub-deploy.

> **Two halves, paired only because both need Rick at the keyboard.** They share no code and no
> data. If time runs short, **F92 first** — it is mechanical and finishes. F115 is a conversation
> and deserves an unhurried one.

---

## 1. Why these two, now

**F92** is the last unread surface in the whole system. The 2026-08-10 pass re-read everything
PostgREST can reach and corrected § 1–§ 12 against live. What remains is only what the REST API
structurally cannot see: **RLS policy bodies, SECURITY DEFINER `prosecdef`/`proconfig`/EXECUTE
grants, CHECK constraints, FKs, column types/defaults, index lists.** Two of those are an
authorization surface, and **F124 already proved this is not theoretical** — `REVOKE … FROM PUBLIC`
looked correct and left `anon`/`authenticated` defaults in place on every DEFINER function.

**F115** is the only open finding with live customer impact, and as of 2026-08-18 it has no owner:
its residual was delegated to F108, which closed 2026-08-11 shipping the customer arrival chip
rather than a record of whether a title arrived. Measured on production: **28 reservations /
23 titles marked fulfilled with no shipment record and no ledger row — 4.2% of past-on-sale
reservations.** Each of those tells a customer **"✓ Order placed"** for a book that never came.

---

## 2. Part A — F92: read the catalog, both environments

Run each query on **staging and production**, paste both results back. Nothing here writes.

### 2.1 The queries

**Q1 — RLS policies (the authorization surface):**
```sql
SELECT tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies WHERE schemaname = 'public'
ORDER BY tablename, permissive, policyname;
```

**Q2 — RLS actually enabled (a policy on a table with RLS off is decoration):**
```sql
SELECT relname, relrowsecurity, relforcerowsecurity
FROM pg_class WHERE relnamespace = 'public'::regnamespace AND relkind = 'r'
ORDER BY relname;
```

**Q3 — function security, search_path, and EXECUTE grants (the F124 lesson):**
```sql
SELECT p.proname, p.prosecdef, p.proconfig,
       pg_get_userbyid(p.proowner) AS owner,
       array_to_string(p.proacl, E'\n')  AS execute_grants
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
ORDER BY p.proname;
```

**Q4 — CHECK constraints, FKs and their delete behaviour:**
```sql
SELECT conrelid::regclass AS tbl, conname, contype, confdeltype,
       pg_get_constraintdef(oid) AS def
FROM pg_constraint WHERE connamespace = 'public'::regnamespace
ORDER BY 1, 2;
```

**Q5 — indexes:**
```sql
SELECT tablename, indexname, indexdef FROM pg_indexes
WHERE schemaname = 'public' ORDER BY tablename, indexname;
```

**Q6 — columns, types, nullability, defaults:**
```sql
SELECT table_name, column_name, data_type, is_nullable, column_default
FROM information_schema.columns WHERE table_schema = 'public'
ORDER BY table_name, ordinal_position;
```

### 2.2 What a FAILING result looks like — state this BEFORE running

F105's closing lesson: *before asking anyone to run a check, ask what its output looks like when the
thing has failed.* These are the pre-stated expectations. **A mismatch is a halt-and-report, not a
"probably fine".**

| Query | Expected | What a mismatch means |
|---|---|---|
| Q1 `preorders` | **2 PERMISSIVE** (`users manage own preorders`, `admins manage tenant preorders`) **+ 2 RESTRICTIVE** from F127 (INSERT/UPDATE) = 4 rows | **Do not misread 4 as an F16 regression** — F16 is closed, verified five ways. A *third* PERMISSIVE policy, or `admins write tenant preorders` reappearing, is the real alarm |
| Q1 `subscriptions` | admin **SELECT** only, no admin write policy, **+ 2 RESTRICTIVE** from F127 | An admin write policy here would mean F128's product decision was implemented without being recorded |
| Q1 every tenant-scoped table | every `qual` references `current_tenant_id()` | a bare `true` is F15's shape — that was a real HIGH |
| Q2 | `relrowsecurity = true` on every tenant-scoped table | RLS off anywhere = the policies above are ornamental |
| Q3 count | **11 functions on each** environment | prod held 12 until `is_admin()` was dropped 2026-08-11; 12 means the drop didn't take, 10 means something else went |
| Q3 `prosecdef` | every DEFINER function has `proconfig` containing `search_path` | NULL `proconfig` on a DEFINER function is the **F23** gap — the exact defect that condemned `is_admin()` |
| Q3 `execute_grants` | **no `anon=X`** on any DEFINER function; `authenticated` only where intended | this is **F124** exactly. `proacl` NULL means default grants — i.e. PUBLIC can execute |
| Q3 | `current_user_is_active` present on **both** | F127's prod DDL ran 2026-08-11; absent on prod = it didn't |
| Q4 `preorders` | FK `ON DELETE NO ACTION` (`confdeltype = 'a'`), **plus F109's BEFORE DELETE trigger** | `NO ACTION` is protective and deliberate (F10, closed won't-fix) — do not "fix" it |
| Q4 `order_submissions` | `quantity` CHECK permits **negatives** | if it still reads `>= 1`, F117's signed-ledger migration silently no-opped, as it did once on prod already |
| Q4 `weekly_shipment` | unique key `(tenant_id, distributor, upc, on_sale_date)` | F9's rebuild |
| Q6 `catalog` | 33 columns each, incl. `initial_order_due`, `title_note`, `withdrawn_at`, `withdrawn_last_seen_month` | F110/F112(a) |

### 2.3 Then correct the document

- Update § 7, § 6, § 8 and § 4 from the results — **including § 7's `preorders` subsection**, which
  is knowingly stale and was deliberately reserved for a single owner rather than edited by two
  sessions at once. **This session is that owner.**
- Refresh the header's per-scope "last verified against live" table.
- Any divergence between environments gets its own line naming **both**. F64 catalogued eight such
  divergences and still missed `is_admin()`; assume there is a ninth until the diff says otherwise.
- If nothing is wrong anywhere, **say that explicitly with the date**. "Verified clean" is a
  finding too, and its absence is what let F92 read as scary for months.

---

## 3. Part B — F115: the decision

### 3.1 The mechanism, in one paragraph

`auto_fulfill_past_on_sale()` marks a reservation fulfilled once its on-sale date passes. It has
**no arrival check**. So a title that was never ordered and never came is closed on schedule,
indistinguishable from one that arrived — and My List then tells the customer **"✓ Order placed"**.
The backorder panel's exit condition is `!fulfilled`, so the row also leaves the admin panel on
schedule. Nothing anywhere records the outcome. F122 fixed *which date* the function reads; F116
taught the admin panel to clear on shipment evidence. Neither gave the function itself an arrival
check, and F108 closed without taking it on.

### 3.2 Three options — Rick picks, the agent does not

**Option A — give `auto_fulfill_past_on_sale()` an arrival check.** Reuse the F76 three-key shipment
match that `hasShipmentEvidence()` already implements for the admin panel. No new schema.
*The catch, and it is the whole decision:* **a missing shipment row is not proof of non-arrival** —
F115's own 4.2% is explicitly an upper bound. Titles that genuinely arrived but were never recorded
in `weekly_shipment` would stay unfulfilled forever, and their customers would keep seeing them as
pending. This trades a false "arrived" for a false "still coming."

**Option B — persist the outcome.** The import's Step 9 pre-flight already *reports* these at the
point of destruction (the 2026-08-04 mitigation). Make it **write** rather than print — a nullable
outcome column or a small table — then surface it honestly on My List. Costs a schema touch and an
import-script change; it is the only option that makes the outcome *queryable* and would also give
F108's original reconciliation question a data source.

**Option C — accept reported-only, and fix the copy.** Change nothing structural; change what the
customer is told so it stops asserting something unproven. Cheapest, honest, and leaves the store
blind — the same trade F112(b) made deliberately elsewhere.

**Recommendation: B, unless the schema touch is unwelcome, in which case C.** A is tempting because
it reuses shipped machinery, but it converts a visible wrong answer into an invisible stuck one,
which is harder to notice and harder to explain to a customer standing at the counter. **C is a
legitimate answer** — but if it is chosen, it must be chosen out loud and written into § 13, not
arrived at by leaving the finding open another month.

### 3.3 Questions for Rick

1. Which option — and if C, what should My List actually say?
2. Do those **28 reservations / 23 titles** on production need a one-time correction now, separately
   from whatever ships? (They are already marked fulfilled; nothing will revisit them.)
3. Is "never arrived" a state a customer should ever see, or is it staff-only?

### 3.4 The rule this session exists to enforce

**Whatever is decided, F115 gets an owner and a date — a plan doc of its own, or an explicit
"accepted as-is" in § 13 with the reasoning.** It must **not** be re-delegated to another finding.
That is precisely how it went missing: F108 was named as owner, F108 closed, and nothing checked.

---

## 4. Scope

### IN
- The six F92 queries on both environments, results pasted back, `technical-reference.md` corrected.
- § 7's `preorders` subsection — this session owns it.
- The F115 decision interview, recorded in § 13 with a named next step.
- The one-line `/preflight` calibration note from the 2026-08-18 spec-18 session: a plan-level
  `NOT STARTED` token can legitimately contain a finished sub-item, so a flag means *go look*, not
  *the token is wrong*. Correct `weekly-pipeline-consolidation-plan.md:194`'s stale "prod promotion
  pending" (commit `f900247` merged 2026-07-09) — **leave its token as `NOT STARTED`**, which is
  correct.

### OUT — stop and ask
- **Any DDL, any write, on either environment.** Part A is read-only. If a query reveals something
  broken, that is a finding and a separate session — not a fix typed into the SQL Editor while
  it's open.
- Implementing F115. This session decides; it does not build.
- Dropping anything Q3 or Q5 shows as unused. Dead-code cleanup is its own session, and **F27** is
  the standing warning: its "supporting" claim was backwards and nearly cost a live extension.

---

## 5. Verification gates

| Gate | Assertion |
|---|---|
| **V1** | All six queries run on **both** environments; results pasted, not summarised from memory |
| **V2** | Every § 2.2 expectation checked and explicitly ticked or flagged — including the ones that pass |
| **V3** | `technical-reference.md` § 7 `preorders` corrected; header "last verified" table refreshed |
| **V4** | Any prod↔staging divergence recorded naming both environments, or "none found" stated with the date |
| **V5** | F115 decision recorded in § 13 with a named owner and next step — **not** a delegation to another finding |
| **V6** | `git diff --stat` touches only `*.md` — zero app files, zero SQL executed against either DB |

---

## 6. Completion criteria

- [ ] V1–V6 green
- [ ] F92 closed, or its remaining scope re-stated with a reason it is still open
- [ ] F115 has an owner and a date; CLAUDE.md's open-findings table row updated to match
- [ ] `weekly-pipeline-consolidation-plan.md:194` corrected, token left alone
- [ ] `/preflight` carries the calibration note
- [ ] Doc-only commits pushed to `staging`
- [ ] `/wrap-up` status update produced

---

## 7. Rollback

Part A is read-only — nothing to roll back. Doc corrections are `git revert`. Part B produces a
decision and no artifact beyond text.

---

## References

- `docs/technical-reference.md` § 13 — **F92** (§ "Still owed" lists the exact unread scopes),
  **F115**, **F124** (the grants lesson Q3 tests), **F23** (`search_path`), **F16** (why 4 policies
  on `preorders` is correct), **F127**/**F109** (what added them), **F117** (the CHECK that
  no-opped once), **F64** (why environment-qualified claims matter).
- `docs/preorders-authorization-boundary-f127-f109.md` § 2.1 — the five-way proof F16 is closed.
- `CLAUDE.md` § SQL authoring rules, § Anti-Drift Rules.
