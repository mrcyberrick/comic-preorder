# F173 (a) — the weekly recheck corrects unreserved Lunar dates and reports recode-shaped pairs

**STATUS:** NOT STARTED · staging: — · prod: — · PR: — (scripts repo, no PR flow) · findings: F173 (direction (a)); F175 proposed (§ 2.5)

Plan written 2026-10-12 (planning session). Owner finding: `docs/technical-reference.md` § 13 F173, fix direction (a). Direction (b), the Move reservations control, is live (`docs/f173-move-reservations.md`). This is the script-side half.

**Nothing here touches the app repo, SQL, the import scripts, F165 S3 or F172.** One file changes: `check-dates.js` in the private scripts repo, plus its tests.

---

## 1. The problem, in one paragraph

`check-dates.js` builds its write set from **reserved** rows only. `--include-unreserved` is off by default, covers only the newest reserved month, and writes `on_sale_date` only, never `foc_date`. So an unreserved Lunar listing whose FOC we hold as passed, while Lunar still lists it as orderable, is hidden from customers and can never be reserved, and the recheck never corrects it because nobody holds it: a closed loop. Measured read-only on production 2026-10-11 against Lunar's 10-09 export: **468** unreserved Lunar listings disagree with the export, **64** of them hidden though still orderable. Separately, a recode (same UPC, new item code, later month) is never linked to its old listing; today the operator finds it by luck and repairs it with Run D-MOVE.

## 2. Decisions for Rick (one recommendation each)

| # | Question | Recommendation |
|---|---|---|
| D1 | Unreserved Lunar listings: correct or report? | **Correct, any catalog month, both `on_sale_date` and `foc_date`, behind a SECOND y/n prompt separate from the reserved corrections.** Lunar only: its export is one all-months live file, so F159's frozen-catalog rule does not apply. PRH unreserved rows stay out (frozen catalogs, F159). Only rows where Lunar's own in-store date is today or later (a past date harms nobody). Same before-state log, same fresh re-read after. The first run is a one-time sweep of about 468 rows: read the dry run first. After that it is standing weekly behaviour and should be small. |
| D2 | Report the "hidden but orderable" rows separately? | **Yes, listed first** in the unreserved section: our FOC passed, Lunar's has not. These are the only unreserved rows a customer is hurt by today (cannot reserve a live title). They are corrected by D1; the separate list is so you see them. |
| D3 | Recode-shaped pairs: correct, move, or report? | **Report only.** A reserved Lunar listing is listed when its code is ABSENT from Lunar's export AND another catalog listing of ours has the same UPC (ISBN when there is no UPC), a DIFFERENT item code, a DIFFERENT catalog month, and is not withdrawn. Same-month matches never count (DC CONNECT PAID vs FREE, the art-box pallet vs bundle). The line names both codes, months, dates and reservation counts and says "move it with Run D-MOVE if Lunar confirms the recode". No automatic move: you chose a manual move on 2026-10-11, and UPC is a suggestion, not a key (F173 § 2.3). The same listings are also tagged "likely recode, not a withdrawal" in the F165 withdrawal-candidate section, which would otherwise list them after two runs. |
| D4 | Per-tenant scope? | **Unchanged: operator-run, one tenant per run** (`IMPORT_TENANT_ID[_PROD]`). You already accepted this (F173 decision 1). A store admin on another tenant still depends on the operator for dates; not addressed here. |
| D5 | When to build? | **After your real weekly run on Fri 2026-10-16**, so the F165 S2 soak's first candidate-capable run happens on today's code. The execution session starts Sat 2026-10-17 or later; first production use is your Fri 2026-10-23 run, dry run first. |

### 2.5 A defect found while planning: one state file for both environments (proposed F175)

`check-dates-state.json` has one path (`check-dates.js:109`) whatever the environment, and every run saves its `absent` map with whatever it saw. **A `--staging` run, `--no-write` included, replaces production's F165 S2 first sightings with staging's.** Today the file holds production's 29 first sightings from 2026-10-09; a staging run before Friday would wipe them, so the 10-16 run would see all 29 as first sightings again and the soak would slip a week. It would also mix the frozen-file hash counters. Nothing has run on staging since the 10-09 production run, so nothing is damaged (backup taken 2026-10-12, sha256 prefix `7aaae13cfda0c110`, in the planning session's scratchpad; temporary, so the executor takes its own).

**Recommendation: file it as F175 and fix it first, in this same work:** state file per environment (`check-dates-state.json` for production, unchanged, so no migration; `check-dates-state.staging.json` for `--staging`). Gate 3 below depends on it. Until it lands: **do not run `check-dates.js --staging` at all.**

## 3. Steps (execution session, scripts repo `main`)

- **S0.** Confirm the 10-16 production run has happened (ask Rick). Copy `check-dates-state.json` aside and record its sha256 before anything else.
- **S1 (F175).** Per-environment state path. Test: a staging-labelled path differs from the production one, and production's name is unchanged.
- **S2 (D1 + D2).** One extra GET: every non-withdrawn Lunar catalog row for the tenant (`id,item_code,distributor,catalog_month,on_sale_date,foc_date,title,upc,isbn,withdrawn_at`, paginated; about 5,600 rows). A pure function `classifyUnreservedLunarDrift(catalogRows, exportByCode, reservedIds, today)` returns `{ corrections, hiddenOrderable }`: skip reserved rows (they are already handled), placeholder dates (`isPlaceholderDate`), codes absent from the export, and rows where Lunar's in-store is before today; patch `on_sale_date` and/or `foc_date` where they differ; `hiddenOrderable` = our FOC < today <= Lunar's FOC. Report hidden-orderable first, then a count by month with the first 10 lines. Its own before-state log file (`check-dates-unreserved-log-DATE.json`), its own y/n prompt AFTER the reserved prompt, its own fresh re-read. `--no-write` writes neither. The old `--include-unreserved` (current-month, on-sale only) is removed: the new section supersedes it. Say so in the header docblock.
- **S3 (D3).** The export's `UPC`/`ISBN` columns are read in `readExportRow` (they exist: `Code,…,In-Store,UPC,ISBN,EAN,…`). A pure function `findRecodePairs(reservedLunarRows, allLunarCatalogRows, lunarCodesInExport)` applies D3's rule. Report section "LIKELY RECODES (report only; nothing is moved)"; tag matching rows in the withdrawal section. **Do not change `classifyWithdrawalCandidates()` or its streak bookkeeping**: the tag is display only.
- **S4.** Header docblock and `test/README.md` updated; the operator workflow (2 files, 3 actions) is unchanged.

## 4. Gates (a failed check is halt-and-report)

1. `node --check check-dates.js`; `npm test` **baseline 354/354 (measured 2026-10-12; the handoff's 345 was the F165 S2 figure)**, plus new tests for: each D1 skip rule, the FOC patch, hidden-orderable boundaries (FOC equal to today), D3's same-month exclusion (DC CONNECT shape), the ISBN fallback, a recode whose old code is still in the export (not listed), and the F175 path split.
2. **Negative control:** break each new rule in turn, see the matching test go red, revert, see it green.
3. **Staging dry run** `node check-dates.js --staging --no-write` against the current recheck folder, only after S1, with **production's state file hashed before and after: byte-identical**. Staging's counts will NOT equal production's 468 / 64 (different reservations and a different data history); record them and explain any difference rather than chasing equality.
4. **Production read-only dry run is Rick's**, at his Fri 2026-10-23 weekly run: `node check-dates.js --no-write` first, compare with 468 / 64 (expect fewer: a fortnight of change), then the real run. No production write by the agent, ever.

## 5. Not in scope, and what stays unverified

- PRH unreserved rows (frozen catalogs; not measured); per-tenant admin self-service; any app change; automatic moves; F165 S3.
- Whether each of the 468 is a genuine Lunar revision is not checked title by title; Lunar's export is treated as authoritative for Lunar, as F155 already does.
- The five unconfirmed recode-shaped pairs remain unconfirmed until the report lists them and someone checks Lunar's site.

## 6. Completion

STATUS line updated; tests green with negative controls recorded; staging dry-run counts and the before/after production state hash recorded here; `technical-reference.md` § 13 F173 and the CLAUDE.md F173 row updated in words; F175's entry (if filed) closed or updated.
