# F165 — Withdrawal detection redesign

**STATUS:** IN PROGRESS · staging=S1, S2 2026-10-04 · prod=S1, S2 2026-10-04 (scripts repo `main` `5919130` / `3ef4b89`; no deploy step, each takes effect at the next run of its script) · S2 SOAKING (needs two real weekly runs), S3 not started · PR=— · findings: F165 (corrects F147; supersedes F110 § 3.3's mark half)

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

### S2 LANDED 2026-10-04 (scripts repo `main` `3ef4b89`, pushed and confirmed on origin)

**Built as specified:** rules 1-5; the pure exported `classifyWithdrawalCandidates()` with the five-argument
signature above; `main()` guarded with `require.main === module`; the per-candidate report line (allocation
flag included); `check-dates.js` docblock. Reads widened by two columns (`preorders.user_id` for the customer
count, `catalog.order_requirement` for the flag). No database write of any kind.

**Decisions the spec left open, recorded so a later session does not re-derive them differently:**

1. **State shape.** `check-dates-state.json` gains `absent: { "<distributor>||<catalog_month>||<item_code>": { since, lastRun } }`.
   Keyed per catalog ROW (an F136-style duplicate in another month is judged against its own source), not per
   bare code.
2. **"Also absent on the previous run" means on an EARLIER DATE.** A candidate needs `since < today`. Without that,
   this project's habit of a `--no-write` dry run followed by the real run on the same files would count as two
   runs and raise a candidate off one export, defeating rule 3. A different-day dry run still counts as a run;
   this was not given a day-gap threshold, which would be an invented number.
3. **Only codes absent from a SUPPLIED source are carried forward.** A code that is present, or whose source was
   not supplied that run, drops out of the map, so "two runs" always means two consecutive observations and a run
   that did not look cannot bridge two that did. The cost is that a missed week restarts the clock, which is the
   safe direction (§ 1.4, Q4).
4. **Observations are saved under `--no-write` and before the apply step.** The local state file is not the
   database, rule 3 needs it, and the V4 replay depended on it. The two existing end-of-run state writes replaced
   the whole file and would have dropped `absent`, so all three now go through a `saveState()` that spreads the
   loaded state.
5. **Frozen = the PRH catalog month is MORE than 3 months before today**, by month arithmetic: on 2026-10-04 the
   2026-07 catalog is live and 2026-06 is frozen, and 2026-06 was still live on 2026-09-18, matching what F159
   recorded. The existing hash-based freeze warning is untouched and is not used here (F159: a hash cannot tell
   frozen from re-supplied).
6. **Rule 4 does not gate the streak.** An absent title is tracked even when it already shipped or its in-store
   date has passed; rule 4 only decides whether it is *listed*. The report says how many were absent twice but not
   listed, so a quiet week is distinguishable from a blind one.

**V3 green.** 19 new tests (`test/withdrawal-candidates.test.mjs`): (a)-(f) plus same-day re-run, presence resets
the streak, untrusted future-dated state, already-marked, report ordering, the report line and its allocation
flag, and a check that requiring the module makes no network call, prints nothing and leaves the real state file
untouched. Unit suite **345/345** (was 326). **Negative controls, each observed red then reverted byte-identical
(sha256):** own-source test broken (compare against the newest supplied month, i.e. F165's premise) turned (a) and
(d) red; the two-run rule removed turned (b), four (c) tests and (e) red; the `main()` guard removed turned the
import-safety test red (`main()` ran on `require` and hit the stubbed `fetch`).

**V4 green, with a positive control so the pass is not vacuous.** `check-dates.js --staging --no-write` twice, in
order, with the 09-22 then the 09-29 Lunar Available Products export and PRH 2026-09 master data (the 09-22 pull
for week 1; for week 2 the 10-02 pull, the nearest that exists), the clock set to 2026-09-22 and 2026-09-29. Run
from a byte-identical COPY of the script in a scratch folder (its state and log files land in scratch; the real
`import.js` supplies credentials through a one-line stub) so **nothing in the real folders could change, and
nothing did: the real `check-dates-state.json` (sha256 `3940CBB2...9019`), all four real `check-dates-log-*`
files and every file under `catalogs/recheck/` hashed identically before and after (18 files).** Result: **0
candidates in both weeks.** All 7 F165 codes (6 Lunar + PRH `84428401135820011`) were confirmed by a read-only
query to hold an open, unmarked reservation with a future in-store date (11/4 or 11/11), so they were in the
evaluated set and the only thing excluding them is presence in their own source. **Positive control:** removing
`0926AB0520` from copies of both exports raised it in week 2 (week 1: "absent for the first time", no candidate)
with `absent since 2026-09-22` and a full report line.

**Not proven, stated plainly.** (1) **Never run against production**, not even `--no-write`; the first real run
is Rick's next weekly `check-dates.js`. (2) Staging holds only **39** open-reservation catalog rows, **31** of them
checkable in the replay, so the replay says nothing about the candidate **volume** production will produce; that
is V5. (3) The glue in `main()` (files to per-source code sets, the report) is covered only by these replays, not
by a unit test. (4) The ledger-net column uses the same simple `item_code` + `distributor` join F158's section
already uses, not `admin.html`'s PRH ISBN chain, so a PRH title can read "no order recorded" when it was ordered
(the F158 section records the same simplification). (5) The week-2 PRH file is dated after the 09-29 clock.

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

**S1 LANDED 2026-10-04 (scripts repo `5919130`; V1 and V2 green, record in § 13 F165).** Two earlier
notes are now moot. (1) The interim rule, ~~"Interim until S1 lands: run the November import with
`--no-write` first and read the candidate list; do not let the mark step run unattended"~~: the import
prints no candidate list and writes no mark, so the rule is retired. (2) The gate reminder above
(routine `trig_01Kb5XJp1urERxry29UArQnD`, calendar event `9n9766hfoe3d0q3r9vbdqj0e0k`, Mon 2026-10-19)
existed only to get S1 in before November and is obsolete; deleting both is Rick's call. ~~**Next is
S2.**~~

**S2 LANDED 2026-10-04 (scripts repo `3ef4b89`; V3 and V4 green, record in § 4).** **Next is the soak, then
V5.** The first real (production) run is Rick's next weekly `check-dates.js`: it records first sightings and can
raise nothing. The second weekly run is the first that can list a candidate. V5 (each candidate checked by hand
on the distributor's site, the true/false split written into § 13 F165) is reviewed with Rick, and only then is
S3 decided. Run it as usual; a `--no-write` dry run on the same day as the real run is safe (one observation).

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
      *(Not ticked: S1 is merged and V1/V2 are green as of 2026-10-04, scripts repo `5919130`, but the
      last clause is only checkable after Rick's November import, which should print the "marking is
      retired" line and no `Checking for withdrawn titles` header. Tick it then.)*
- [ ] S2 merged; V3, V4 green; two weekly runs soaked
      *(Not ticked: S2 is merged and V3/V4 are green as of 2026-10-04, scripts repo `3ef4b89`, but the soak
      clause is only checkable after two REAL weekly runs; the first records first sightings and can raise
      nothing, the second can. Tick it after the second.)*
- [ ] V5 recorded in § 13 F165 with the true/false split
- [ ] S3 decided (built and V6 green, or declined with the reason recorded)
- [x] S4 decided — declined for now, 2026-09-29 (§ 9 Q3); V7 therefore not needed
- [ ] `monthly-catalog-refresh.md` no longer describes withdrawal marking as an import step;
      `check-dates.js` docblock describes the candidate report
- [ ] § 13 F165 → RESOLVED; § 13 F147 and F110 status lines point here; CLAUDE.md F165 row updated
