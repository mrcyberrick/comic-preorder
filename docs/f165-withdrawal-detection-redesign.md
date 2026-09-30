# F165 — Withdrawal detection redesign

**STATUS:** NOT STARTED · staging=— · prod=— · PR=— · findings: F165 (corrects F147; supersedes F110 § 3.3's mark half)

Owner doc for F165. The finding itself lives in `docs/technical-reference.md` § 13 F165; this doc
is the execution plan. Planned 2026-09-29, the day the finding was filed.

---

## 0. The decision in one paragraph

**Stop marking titles withdrawn automatically.** The monthly import compares a title against the
*next* month's file, where it is absent by construction, so the mark fires on import timing rather
than on anything a distributor did. Replace it with a **weekly, report-only candidate list** built
from the right comparison, **a fresher copy of the title's own source**, and let a person confirm
each mark before it is written. Clearing a mark stays automatic, because clearing is the safe
direction.

**The one thing with a deadline is S1**, which removes the automatic mark from `import.js` and
`import-staging.js`. It must land before the **November new-month import** (expected late
October), which is the next time the defect can fire on production.

---

## 1. What was measured (2026-09-29, read-only, local files + § 13 F165)

Load-bearing facts. Re-measure if this date is stale.

### 1.1 The automatic mark has never been right

| When | Environment | Marks | Outcome |
|---|---|---|---|
| 2026-08-28 | production | 519 | all had a future FOC; cleared as unsubstantiated (F147) |
| 2026-08-28 | staging | 16 | all 16 present in a fresh re-pull of **their own** month; cleared (F146) |
| 2026-09-29 | staging | 7 | all 7 confirmed live on the distributors' own catalogs (F165) |

**542 automatic marks, 0 confirmed real.** F146 was recorded as "a mid-month export drop". Its own
evidence shows it was the same cross-month cause: every one of the 16 was absent from September's
file and present in August's.

The one genuine withdrawal this project has seen, **MIDNIGHT X-MEN #2** (PRH `…0211` / `…0221`),
was found by a **re-pull of its own July catalog** (§ 13 F101/F110: the 2026-07-25 re-pull carried
only issue #1) and by PRH answering the order UNKNOWN. **Neither of those is the signal the
import uses.**

### 1.2 The comparison that works: the title's own source, re-pulled

| Distributor | Own source | Already pulled weekly by `check-dates.js`? |
|---|---|---|
| Lunar | *Available Products* export: one file, all months, keeps titles past FOC until they ship | yes |
| PRH | the title's **own catalog month's** master data (`YYYY_MM_PRH_metadata_full_active.csv`) | yes, per live catalog |

**Checked against F165's 7 false marks: all 7 are present in their own source.** The 6 Lunar codes
are in both the 09-22 and 09-29 Available Products exports; `84428401135820011` (Minor Arcana #20)
is in PRH's own 2026-09 master data and absent only from 2026-10. The own-source test rejects
every one.

### 1.3 Absence from the own source is evidence, not proof

Lunar Available Products, codes that disappeared week to week while their in-store date was still
in the future:

| Weekly pull | Rows | Dropped, future in-store | Titled as incentive / unlock / bundle |
|---|---|---|---|
| 09-14 → 09-22 | 17,278 → 18,494 | 100 | 90 |
| 09-22 → 09-29 | 18,494 → 18,147 | 55 | 44 |

That is **tenant-agnostic churn**; only the handful holding a reservation here would ever be
listed. It is mostly allocation variants whose ordering window has closed, which is not a
withdrawal: a store that already ordered one still receives it. The plain titles that dropped
(e.g. CRYPTID CORPS #5, GREATEST AMERICAN HERO #3, dropped the day before in-store) are
unexplained. **Lunar's `Due Date` column does not discriminate**: all 155 dropped titles had a
passed due date, and so do all 2,139 past-FOC titles still listed on 09-29.

PRH's master data is active-only (`SalesStatus` = `Active` on all 915 rows of 2026-09, same as
F110 measured), so a PRH withdrawal can only show as absence. A PRH catalog **freezes** about three
months out (F155 § 1.2), after which no file carries any signal; that gap is accepted, and F155
S3's never-arrived path and F143's supplier rejection cover the late cases.

**Conclusion that shapes the design:** no file we download says "withdrawn". The best available
signal produces candidates for a person to check, not facts for a script to write.

### 1.4 What the mark does to a customer (why a false mark is expensive)

`mylist.html` shows *"No longer available — withdrawn by the distributor. This title cannot
arrive."* and the `isWithdrawn` override in `Preorders.cancel()` (`app.js:1486`) unlocks
cancellation of an **ordered** reservation. A false mark invites a customer to cancel, irreversibly,
a book the store has ordered and will receive. A late mark only delays bad news that Order
Follow-Up's Never Arrived panel and F143's rejection path already carry.

---

## 2. Scope

**IN:** `import.js` + `import-staging.js` withdrawal marking (S1); `check-dates.js` candidate
report and confirm-to-mark (S2, S3); an admin control to clear a mark (S4, optional); the monthly
refresh runbook; § 13 F165/F147/F110 status lines.

**OUT:** the clear half in `import.js` (`clearReappearedWithdrawals()`, F146), which stays exactly
as it is. The customer-facing copy and the cancel override (F110 § 2.2, settled). Any schema
change. PRH's Weekly Change Report or a new download (F110 path 2 stays declined; revisit only if
§ 1.3's PRH noise proves unworkable). F157's distributor-scoping half (separate work).

---

## 3. S1 — retire the automatic mark (scripts repo, before the November import)

**Change.** In both scripts, `planWithdrawalDetection()` returns `shouldMark: false`
unconditionally, and `detectWithdrawals()` is removed along with its call at Step 4b. Keep
`computeWithdrawalCandidates` / `narrowWithdrawalCandidates` only if a test still needs them;
otherwise delete them with their tests. **Do not keep a printed candidate list in the import**: on
production's data it would list 0 / 4 / 182 / 368 reservations depending on the day (§ 13 F165),
which is noise a reader will learn to ignore. Replace Step 4b's mark line with one sentence
pointing at `check-dates.js`.

**The docblock that states the false premise** ("it only becomes evidence of withdrawal once that
window has closed", `import.js:1115-1117`) is deleted with the function; put the correction in
the commit message and § 13, not a tombstone comment.

**Tests.** `planWithdrawalDetection(true)` → `{ shouldClear: true, shouldMark: false }` in both
scripts, plus the parity test. Negative control: restore `shouldMark: isNewMonth`, observe red,
revert.

**Verify.** `npm test` green; `node import-staging.js <Oct Lunar> <Oct PRH> --no-write` against
staging prints the clear check and **no** "withdrawn title(s) detected" line.

**Size:** about 60 lines removed per script. No database change, no web-app change.

---

## 4. S2 — weekly candidate report in `check-dates.js` (report-only)

`check-dates.js` already reads both own sources and already splits reserved codes into "catalog
not pulled" and "catalog WAS pulled and the code is gone" (`droppedOut`, ~line 407). Today it only
acts on the past-on-sale subset. S2 adds a **withdrawal candidates** section.

**A reserved row is a candidate when all hold:**

1. its own source was supplied this run (Lunar: an Available Products export; PRH: its own
   `catalog_month`'s master data), **and that source is not frozen** (PRH catalog month more than
   3 months before today → skip, and say so in the report; F159's lesson that a hash alone cannot
   tell frozen from re-supplied);
2. the code is absent from it;
3. the code was **also absent on the previous run** (persist `absentSince` per code in
   `check-dates-state.json`), so a single late or partial export cannot raise it;
4. `on_sale_date` is today or later and there is no shipment evidence (a shipped title is not
   withdrawn);
5. it is not already marked.

**Each candidate line shows** what a person needs to check it in one look: distributor, code,
title, FOC, in-store, `order_requirement` (flag allocation variants: "often means the allocation
closed, not a withdrawal"), reservations / customers / copies, ledger net, and the date first seen
absent.

**Make it testable:** extract the rule as a pure `classifyWithdrawalCandidates(reservedRows,
suppliedSources, prevState, today, shipped)` and export it (the script has no exports today;
guard `main()` with `require.main === module` like `import.js`).

**Tests (unit):** (a) F165's shape: absent from next month, present in own source → not a
candidate; (b) MIDNIGHT X-MEN #2's shape: absent from two consecutive re-pulls of its own PRH
month → candidate; (c) absent once only → not yet; (d) own source not supplied → not a candidate;
(e) frozen PRH month → skipped and reported; (f) shipped → not a candidate. Negative-control (b)
and (a).

---

## 5. S3 — confirm-to-mark in `check-dates.js`

After the report, and only when not `--no-write`, prompt **per candidate**: `Mark as withdrawn?
Check the distributor's site first. [y/N]`. Default **No**. Before any write, append the
before-state to the run's existing `check-dates-log-<date>.json` (exact revert data, same
convention as the date corrections). Write `withdrawn_at = now()`,
`withdrawn_last_seen_month = <row's catalog_month>`. Independently re-read the written rows
afterwards and print the count.

**Wording the prompt must carry** (the F143 lesson: the wording is the safeguard): customers see
"cannot arrive" immediately and may cancel an **ordered** reservation, and if the title was
ordered and the distributor cancelled it, record **Rejected by supplier** in admin too so the
ledger nets to 0.

**Why the terminal and not the admin page first:** no client code, no schema, and the person
confirming is the person who pulled the files. The admin page already lists confirmed marks
(`#withdrawn-panel`, `admin.html:313`).

---

## 6. S4 — "Not withdrawn" control in admin — DECLINED for now (§ 9 Q3), kept for reference

Today a wrong mark can be cleared only by re-importing its own month's file (F146's two-day
procedure) or by SQL. Add a **Not withdrawn** button per row on `#withdrawn-panel`, confirm-gated,
that nulls both columns. Admin write to `catalog` needs checking against the live RLS policies
first (`/sql-check`); if admins cannot update `catalog`, this becomes a small SECURITY DEFINER RPC
and the step grows. Needs a spec (seed a marked row, clear it, assert My List loses the notice).

---

## 7. Verification gates

| Gate | What | Pass |
|---|---|---|
| V1 | S1 unit tests + negative control, both scripts | green / observed red |
| V2 | `import-staging.js --no-write` on the October files | no mark line; clear check still runs |
| V3 | S2 unit tests (a)-(f) + negative controls | green / observed red |
| V4 | Replay F165 on real files: `check-dates.js --staging --no-write` with the 09-22 and 09-29 exports and PRH 2026-09 | **none of the 7 F165 codes is a candidate** |
| V5 | Production volume, `check-dates.js --no-write` on the next weekly pull | candidate count recorded; each one checked by hand on the distributor's site and the true/false split written into § 13 F165 |
| V6 | S3 on staging: seed one candidate (a `ZZTEST165-` catalog row + reservation, absent from the files for two runs), answer y | row marked, log holds before-state, My List shows the notice; teardown re-read returns 0 rows |
| V7 | Full Playwright suite after S4 only (S1-S3 touch no web code) | `N passed`, 0 failed |

**V5 is the one that decides whether this signal is worth keeping.** If most candidates turn out
live, S2 stays report-only and S3 is not built; the honest fallback is F143's rejection path plus
Never Arrived.

---

## 8. Sequencing and dates

1. **S1** — any session, **before the November new-month import**. Small, and it removes the
   only production exposure. Worth a `/schedule-gate` reminder a week before the expected
   November file date.
2. **S2** — next; soak through two weekly `check-dates.js` runs (the two-run rule needs two runs
   before it can raise anything).
3. **V5** reviewed with Rick → decide S3.
4. **S3** (S4 declined, § 9).

**Gate scheduled (2026-09-29):** S1 must land before the November new-month import, expected
~2026-10-26 (the September and October new-month imports ran 2026-08-28 and 2026-09-27; this is an
estimate, not a known date). Reminder: cloud routine `trig_01Kb5XJp1urERxry29UArQnD` and Google
Calendar event `9n9766hfoe3d0q3r9vbdqj0e0k`, both **Mon 2026-10-19, 8:00 AM ET**. If the November
files are expected earlier, move both.

**Interim until S1 lands (from § 13 F165, unchanged):** run the November import with `--no-write`
first and read the candidate list; do not let the mark step run unattended.

---

## 9. Decisions (Rick, 2026-09-29)

- **Q1 — DECIDED: retire the automatic mark outright.** S1 as written; no automatic marking
  survives in any script.
- **Q2 — DECIDED: confirm in the terminal.** S3 lives in `check-dates.js`; no admin mark control.
- **Q3 — DECIDED: not now.** S4 is out of this plan. A wrong mark is still cleared by re-importing
  its own month's file (F146's procedure) or by SQL. Revisit if that is ever needed in anger.
- **Q4 — DECIDED: the two-consecutive-runs rule stands**, accepting a one-week delay on a real
  mark (§ 1.4).

---

## 10. Completion criteria

- [ ] S1 merged in the scripts repo; V1, V2 green; November import ran with no mark step
- [ ] S2 merged; V3, V4 green; two weekly runs soaked
- [ ] V5 recorded in § 13 F165 with the true/false split
- [ ] S3 decided (built and V6 green, or declined with the reason recorded)
- [x] S4 decided — declined for now, 2026-09-29 (§ 9 Q3); V7 therefore not needed
- [ ] `monthly-catalog-refresh.md` no longer describes withdrawal marking as an import step;
      `check-dates.js` docblock describes the candidate report
- [ ] § 13 F165 → RESOLVED; § 13 F147 and F110 status lines point here; CLAUDE.md F165 row updated
