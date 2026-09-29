# October import close-out, doc-truth fixes, and filing F163

**STATUS:** COMPLETE · 2026-09-29 · staging=doc-only commits (fd78909 S1, S2a, S2b, F163 8956d88) · prod=— (read-only on prod; no writes) · PR=— · findings: F163 (filed)

One session, three items, all **read-only against the databases** and **doc-only in the repo**. No
code, no schema, no deploy, no production write. They are grouped because each one closes a
record that is currently wrong or missing, and the first one gates everything scheduled after it.

---

## 0. Why now, in one paragraph

The October catalog import was the attended gate CLAUDE.md scheduled for **2026-09-25**, carrying
the **first live production exercise** of F147's corrected FOC check and F146's unconditional clear
half. Both of those have fired exactly once each and both fired wrong (519 marks, 16 marks).
**Nothing in the repo records that the import happened.** The only evidence is on disk:
`catalogs/Lunar_Product_Data_1026.csv` and `catalogs/2026_10_PRH_metadata_full_active.csv` were
saved at 2026-09-27 19:04, `normalized_catalog.json` was regenerated at 19:43 with **2,215 rows, all
`catalog_month` 2026-10 (Lunar 1,402 / PRH 813)**, and both `Shipment-detail-*.csv` files are dated
19:38–19:39. It is **unknown which environment ran it, and whether it was a dry run or a real run.**
Until that is measured, the Admin Settings S4 promotion and the F157 distributor-scoping work (both
held "until after the October gate") have no confirmed gate to sit behind.

---

## 1. Scope

**IN**
- **S1**: measure and record the October import's outcome on both environments.
- **S2**: correct two stale status claims (CLAUDE.md, and the S1 RPC SQL file's STATUS line).
- **S3**: file **F163**, the customer-invisible stranded never-arrived rows, via `/file-finding`.

**OUT — stop and ask if the session drifts toward any of these**
- Any database **write**, on either environment. That includes clearing withdrawn marks, setting
  `order_deadline` and toggling Maintenance Mode. If one is needed, it goes to Rick with the exact
  statement.
- Fixing F163. This session files it and does nothing more.
- The Admin Settings S4 production promotion, V2/V4/V10, and the F157 distributor-scoping half.
  S1's result **unblocks** these; it does not start them.
- Any edit to `import.js` / `import-staging.js`.

---

## 2. S1 — the October import close-out (read-only)

### 2.1 Ask Rick first (a single message; this saves the most guesswork)

1. Which environment(s) did you import October into, and was it `--no-write` or real?
2. Do you still have the console output? The lines that matter are the withdrawal-marking summary,
   the F146 "reappeared / cleared" summary, the F157 raw-vs-normalised counts, and the
   auto-fulfil count.
3. Was **Step 7** (Order Deadline) set and **Step 8** (Maintenance Mode OFF) done?

Measure regardless of the answers. The answers say what to *expect*, and the database says what is
*true*. Where they disagree, that disagreement is the result to record.

### 2.2 Measure — service-role REST reads from the scripts folder's `.env`, GET only

Run `/sql-check` first. Column names below were checked against `docs/technical-reference.md`
§ 4.2 / § 4.3 / § 4.4 on 2026-09-29; re-read those sections before writing any query.
**Tenant-scope every query** (`IMPORT_TENANT_ID` / `IMPORT_TENANT_ID_PROD`). Use `curl.exe`, not
`Invoke-RestMethod` (see Known Issues). **Paginate or use `Prefer: count=exact`**. This project has
been bitten six times by PostgREST's 1,000-row cap (F82/F113/F139/F140/F156/F162).

Run each check on **both** projects:

| # | Check | What pass looks like | HALT if |
|---|---|---|---|
| M1 | `max(catalog.catalog_month)` for the tenant | `2026-10` on whichever env(s) Rick names | The env reads 2026-09 → that import did not happen there. **This is not a failure**: record the gate as still OPEN and go to § 2.4 |
| M2 | `catalog` row count for `catalog_month=2026-10`, per distributor | Matches the script's printed count. `normalized_catalog.json` (1,402 / 813) is only a reference for whichever run happened *last* | A distributor at **0** → the F157 guard should have made that impossible. HALT |
| M3 | `catalog` rows with `withdrawn_at` not null, with `foc_date`, `catalog_month`, `withdrawn_last_seen_month`, and whether each has an unfulfilled `preorders` row | **Every** mark has `foc_date` before the import date (F147's invariant). The count is small (single or low double digits) | **Any** mark whose `foc_date` is on/after the import date, or a count in the hundreds → an F147 regression. HALT, touch nothing, go to Rick |
| M4 | Of M3's marks, how many were set by this import (`withdrawn_at` on the import date) vs. carried over | Stated either way. Before this import, production held 0 marks | — |
| M5 | `app_settings` rows `order_deadline` and `maintenance_mode` | `maintenance_mode` = false. `order_deadline` is **set** to a date in the 2026-10 cycle. The new-month branch clears it (F108), so an empty value means Step 7 was skipped | `maintenance_mode` = true on production and Rick did not intend it → report immediately; do not flip it |
| M6 | `preorders.arrival_outcome` distribution, and `fulfilled` counts, compared with the last recorded figures (§ 13 F115) | A plausible delta from the shipment import | — (record only) |

**F146's clear half**: production held **0** marks before this import, so there was nothing for it
to clear. Say exactly that. Do not claim F146 was exercised unless M4 shows a mark that was
present before the import and is gone after it.

### 2.3 Record — doc-only commits to `staging`

- **CLAUDE.md § Current Migration Phase.** Replace the "⏰ GATE SCHEDULED" / "attended-session gate"
  paragraphs with a dated result, keeping the old wording visible per convention: which env, real
  or dry, the M1–M5 numbers, and whether F147/F146 behaved. Add a **"Last completed work"** entry
  at the top of the history.
- **`docs/technical-reference.md` § 13**: append a dated "first live production exercise" line to
  **F147**, to **F146**, and to **F157** (zero-row guard: did it print raw vs. normalised, and was
  it clean?).
- **CLAUDE.md findings table**: update the F146/F147/F157 rows' last clause to match.
- **`docs/admin-settings-catalog-visibility.md`**: one line under § 9's production-promotion box
  stating the October gate is now clear (or is not), so the next session sees it.

### 2.4 If the import has NOT run on production

Record that plainly as the finding of S1. Update the gate paragraph to read **OPEN, not yet run**,
and ask Rick for a new date. Then run `/schedule-gate` for it. The 2026-09-25 cloud reminder
(`trig_01FQesEHRh9XdRXgwASFJoh7`) has already fired, so nothing is watching the gate now.

---

## 3. S2 — two stale claims (doc-only)

**S2a — CLAUDE.md, the F162 history entry (≈ line 212).** It still ends *"The companion SQL's
production run remains the one open residual."* That run was **applied 2026-09-28** (the SQL file's
own STATUS line reads `prod=APPLIED 2026-09-28`, and the "Last completed work" entry records the
`pg_get_functiondef` check). Append a correction rather than deleting the sentence, matching the
file's own `*(…)*` convention. Grep CLAUDE.md for any other F162 "pending / residual" wording first,
and fix every hit, not only the first one.

**S2b — `docs/sql/2026-09-23-publisher-reserve-counts-rpc.sql` line 1** reads
`staging=PENDING | prod=PENDING`. `admin-settings-catalog-visibility.md`'s STATUS token says *"S1
applied by Rick"*, while its own § 4 S1 heading still says *"NOT APPLIED"*. Two of these three are
wrong. **Measure before editing**:

- Behavioural probe on **each** project: `POST /rest/v1/rpc/get_publisher_reserve_counts` with the
  service-role key and `{}` as the body.
  - `PGRST202` ("Could not find the function") → **not applied**.
  - Anything else (a `200`, even with an empty body, or a `42501`) → **exists**.
  - Write down, *before* running it, what the "missing" response looks like, so the probe cannot
    pass by accident. See § Smoke Test Suite: "a verification step that cannot fail…"
- Then make all three agree with the measurement: the SQL STATUS line, the plan's STATUS token, and
  the § 4 S1 heading. Ask Rick for the staging apply date if the plan doc doesn't state one.
- **Leave § 9's box "S1 RPC applied to staging, verified by V2" UNTICKED** even if the function
  exists. V2 is still open, and it now has to compare against the pre-`886cab0` code from git
  history, because S4 deleted `getReservedPublishers()`. Add one line under that box saying so.
- **Why this matters:** `/promote-prod` step 0 reads this STATUS line. A `PENDING` that should read
  `APPLIED` makes it flag noise. A `prod=APPLIED` that is false would make it pass when it should
  fail. That second case is F105, and it has already happened once (F155).

After S2, run `/preflight` and confirm the STATUS cross-check reports nothing new.

---

## 4. S3 — file F163 (use `/file-finding`, which claims the ID)

**The defect.** A reservation that genuinely never arrived appears on **neither** My List section,
so a customer can never be shown an arrival status for it, whatever an admin marks. `mylist.html`
scopes the main table to `catalog_month === currentMonth` (≈ `:937`) and Upcoming Arrivals to
`on_sale_date >= today` (≈ `:938-940`). A prior-month title whose on-sale date has passed fails
both. The copy that would tell the customer already exists and has no row to render on:
`⚠ Did not arrive — contact the store.` (≈ `mylist.html:1099`). This is F155's stranding mechanism
at its terminal case. F155 fixed date *drift*, but a title that will never arrive still disappears.
Re-read those line numbers from disk; they were recorded on 2026-09-21 and `mylist.html` may have
moved since.

**Provenance.** CLAUDE.md's 2026-09-21 entry (PR #154) found it, measured it (23 production rows at
the time), and states it *"remains unfiled, so it will be lost unless someone files it."* Rick chose
to fix the admin panel first. This session files it; it does not fix it.

**Measure fresh before filing (production, read-only).** Count the reservations in the stranded
shape: the joined `catalog.catalog_month` is not the current month, `on_sale_date` is before today,
and the row is one the customer needs to hear about. That means either `arrival_outcome` in
(`not_arrived`, `unknown`, `damaged`), or unfulfilled with no shipment evidence. Break the count
down by `arrival_outcome` × `fulfilled`, and **reconcile that breakdown against the total** before
writing it down. The F156 session published a breakdown that did not sum to its own total. October's
new `catalog_month` will have **moved the number** since 2026-09-21: expect it to grow, and say why.

**Severity:** Medium. It is customer-facing and silent, but nothing is lost: the store's admin
surfaces show the row. **Fix direction, one line, not designed:** a third My List bucket for
prior-month reservations carrying a customer-relevant `arrival_outcome`. Leave the design for its
own session.

The skill handles the rest: the § 13 entry, the CLAUDE.md "next free ID" pointer (→ **F164**), the
findings-table row, and a doc-only commit to `staging`. First check that F163 is still free: grep
§ 13 for `### F16`.

---

## 5. Order, halts, and done

**Order:** S1 → S2 → S3. S1 goes first because an F147 regression (the M3 halt) outranks everything
else here. If it fires, stop the session there, report to Rick, and leave S2/S3 for later.

**Commits:** separate doc-only commits per item, straight to `staging`, pushed. Each message names
what it records (`docs: record October import outcome (F146/F147/F157 first live exercise)`, and so
on). **Before trusting the CLAUDE.md you re-read, check `git rev-parse --abbrev-ref HEAD` returns
`staging`.**

**Done when:**
- [x] S1: both environments measured (M1–M6), the result recorded in CLAUDE.md and § 13
      F146/F147/F157, or the gate re-armed per § 2.4
- [x] S2a: no CLAUDE.md sentence still claims F162 has an open production residual
- [x] S2b: SQL STATUS, plan STATUS token and § 4 S1 heading all agree with a measured probe on both
      projects. The V2 box stays open, with its new caveat noted. `/preflight` is clean
- [x] S3: F163 filed with a fresh, reconciled production count. Next free ID → F164
- [x] This doc's STATUS token → COMPLETE with the date
- [ ] `/wrap-up` run
