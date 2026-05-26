# Phase 4.0 — Backfill Parity (staging script catches up to production)

**Status:** Planning — plan written 2026-05-26
**Parent plan:** `docs/phase-4-production-migration.md`
**Branch base:** `staging`
**Branch name:** `feature/4.0-backfill-parity`
**Estimated duration:** one short session (single file, four discrete patches, two doc updates)
**Customer impact:** none (staging-only; tooling script)

---

## Goal

Bring `import-staging.js` up to feature parity with the production `import.js` for older-month catalog imports. Production has independently accumulated four backfill-related features that staging never received. Without porting them, the Sub-Deploy 4.5 bidirectional merge has to invent test conditions for prod-only behaviors that staging has never exercised — that's the worst kind of cutover surprise.

This sub-deploy is forward-port only. No prod files are touched. No SQL. No Edge Functions. No app code.

The four features are:

1. **`--skip-autoreserve` flag** — manual override to suppress the auto-reserve step
2. **`isOlderMonth` detection** — third state in the month-comparison logic (older / same / newer)
3. **Auto-skip auto-reserve for older-month backfills** — never auto-reserve already-shipped issues
4. **Older-month notification warning** — UX nudge before the email-customers prompt when running a backfill

Also resolves a finding surfaced during Phase 4 parent-plan drafting:

5. **`r.foc_date >= today` filter in staging's notify-customers payload** — provenance unknown; `CLAUDE.md` carry-forward list does not mention it. This sub-deploy runs `git log -p` against `import-staging.js` to recover the history and produce a documented decision before the 4.5 merge inherits the divergence.

---

## Approach Summary

| Decision | Choice | Rationale |
|---|---|---|
| Direction | Forward-port only (prod → staging) | Production has the canonical backfill behavior; staging is the catch-up target. Matches the 4.5 Strategy B principle: prod's older-month logic survives the merge as no-op preservation, not re-introduction |
| Scope of port | All four features as a single sub-deploy | They are interdependent (auto-skip depends on `isOlderMonth`; warning depends on `isOlderMonth`; flag and auto-skip share a control variable). Splitting them produces partial states that aren't worth testing |
| File touched | `import-staging.js` only | The local `scripts/test-this-week.ps1` and other helpers are unaffected; backfill is a script-level concern, not a fixture concern |
| Verification | Manual staging dry-run with three month conditions (newer, same, older) + manual `--skip-autoreserve` exercise | The script is interactive and prompts the user; Playwright doesn't cover it. Exercise each branch by manipulating the staging catalog's latest `catalog_month` value temporarily, or by running against a deliberately mis-dated CSV |
| `foc_date >= today` filter decision | **Defer the merge decision to 4.5** — but this sub-deploy must run `git log -p import-staging.js \| grep foc_date` and **commit the resulting provenance note** to `docs/phase-4.0-backfill-parity.md` § Findings During Execution before 4.0 closes. The 4.5 plan then reads that note and decides whether to propagate, revert, or leave divergent | Decision belongs with the merge (4.5), but the historical evidence must be recovered now while the diff context is fresh |
| Anti-drift posture | Discover-describe-ask if any of the four features look different from the planned port | Production code is the source; if the on-disk prod file has drifted from the `prod-import.js` snapshot captured 2026-05-26, halt and reconcile before patching |

---

## In Scope

### Code (one file)

1. **`import-staging.js` § Step 1 (CLI arg parsing)** — add `rawArgs` filter for `--skip-autoreserve`; add flag to usage banner
2. **`import-staging.js` § Step 3 (month detection)** — add `isOlderMonth` boolean alongside `isNewMonth`; expand the if-else chain to three states with the prod-side console messaging
3. **`import-staging.js` § Step 5 (auto-reserve)** — wrap the `autoReserveSubscriptions` call in a skip-check; print reason
4. **`import-staging.js` § Step 7 (notify prompt)** — add the older-month warning console block before the readline prompt

### Docs

5. **`docs/phase-4.0-backfill-parity.md`** — this file, ending with § Findings During Execution populated by the runbook
6. **`docs/phase-4-production-migration.md`** — flip Sub-Deploy 4.0 status to **Complete** with date; flip 4.1 status to **Planning**
7. **`CLAUDE.md` § Current Migration Phase** — active sub-deploy → 4.1
8. **`docs/technical-reference.md`** — no change expected (script-level changes; canonical schema reference does not document import script behavior). Confirm during runbook and stop-and-ask if drift discovered

### Findings recovery

9. **`git log -p import-staging.js | grep -B5 -A5 foc_date`** — run during pre-flight; capture the relevant commit hashes, authors, dates, and adjacent commit messages; paste the result verbatim into § Findings During Execution

## Out of Scope

Per anti-drift: discover → describe → ask → wait if any of these surface during execution.

- **`import.js` (production) edits** — that's 4.5's job
- **Edge Function changes** — `notify-customers` payload schema change is downstream of any `foc_date` filter decision; out of scope here
- **App code changes** — staging app code already handles older-month backfills correctly via the existing catalog read path
- **SQL / RLS / function changes** — nothing in this sub-deploy touches the database
- **`config.js`** — gitignored; do not edit
- **Production import.js feature documentation in `technical-reference.md`** — the script section there (if any) documents both scripts collectively; if it needs an update, that's a 4.5 carry-forward, not this sub-deploy
- **Playwright spec coverage of import-staging** — the script is interactive and is not Playwright-exercised; adding coverage would be its own sub-deploy
- **`r.foc_date >= today` filter merge decision** — recover history here; *decide* in 4.5

---

## Pre-flight Checks

Run before any edit. If any check fails, stop and reconcile.

### P1 — Clean tree on staging
```bash
git status
git fetch origin
git log staging..HEAD --oneline   # expect empty
```

### P2 — Capture current state of the four target callsites in import-staging.js
```bash
grep -n "process.argv\|isNewMonth\|isOlderMonth\|autoReserveSubscriptions\|notification email\|notifyAnswer\|skip-autoreserve" \
  import-staging.js
```

**Expected hits** (line numbers approximate — re-verify before patching):
- `process.argv.slice(2)` — once, in `main()`
- `isNewMonth = false` — once, in Step 3
- `isOlderMonth` — **zero hits** (the gap we're filling)
- `autoReserveSubscriptions(confirmedMonth)` — once, in Step 5 (called unconditionally)
- `notification email` — once, in the Step 7 prompt
- `skip-autoreserve` — **zero hits** (the flag doesn't exist yet)

If `isOlderMonth` or `skip-autoreserve` returns any hits, the script has drifted from the 2026-05-26 baseline. **Stop and reconcile** — someone may have started this work informally.

### P3 — Compare against the prod snapshot
The 2026-05-26 prod snapshot lives at the project file `/mnt/project/sample-import-staging.js`'s sibling location in this planning conversation as `prod-import.js`. The runbook captures the exact line ranges for each of the four features:

- `--skip-autoreserve` flag: prod lines 700–702 + usage banner edit ~705 + flag-description block ~713–715
- `isOlderMonth` detection: prod lines 761–789
- Auto-skip wrapper: prod lines 797–809
- Older-month warning: prod lines 884–888

The runbook must `view` each range immediately before patching to confirm the prod source hasn't drifted from the 2026-05-26 snapshot. If drift exists, stop and reconcile.

### P4 — Recover the `foc_date` history
```bash
git log -p -- import-staging.js | grep -B5 -A5 'foc_date' | head -200
```
Capture the most recent commit(s) that introduced or modified the `r.foc_date >= today` filter. Note the commit hash, date, author, and commit message. This is the input to the § Findings During Execution writeup.

If `git log -p` returns no `foc_date` history, document that — it means the filter was introduced before the current staging branch was forked, or via a squash that lost the original commit. Either way, the absence of provenance becomes the finding.

### P5 — Confirm `config.js` is untouched and gitignored
```bash
git check-ignore -v config.js
cat .gitignore | grep -i config
```
Standard credential-safety pre-flight.

### P6 — Confirm no in-flight branch
```bash
git branch --show-current   # expect "staging"
git branch | grep -i "4.0\|backfill"   # expect empty
```

---

## Changes (literal diffs for mechanical execution)

Each diff is a `str_replace` operation against `import-staging.js`. Line numbers are 2026-05-26 staging baseline (matching the conversation's `/mnt/project/sample-import-staging.js`); the `old_str` halves are byte-exact and locate the insertion point unambiguously.

**Anti-drift gate before each diff:** the CLI session must `view` the target line range and confirm the `old_str` matches verbatim. If staging has drifted from the baseline since 2026-05-26, halt and stop-and-ask per `CLAUDE.md`. Do not adapt the diff to drift.

---

### C1 — `import-staging.js` § `main()` arg parsing (around line 705)

**Pre-check:** `view import-staging.js [702, 718]`. Confirm matches `old_str` below.

**str_replace:**

`old_str`:
```javascript
  const args = process.argv.slice(2);
  if (args.length < 2) {
    console.error('Usage: node import-weekly-staging.js <lunar_catalog> <prh_catalog> [shipment1] [shipment2]');
    console.error('');
    console.error('Example (catalog only):');
    console.error('  node import-weekly-staging.js "..\\Lunar_Product_Data_0426.csv" "..\\2026_04_PRH_metadata_full_active.csv"');
    console.error('');
    console.error('Example (catalog + shipment):');
    console.error('  node import-weekly-staging.js "..\\Lunar_Product_Data_0426.csv" "..\\2026_04_PRH_metadata_full_active.csv" "..\\delivery-detail-LUNAR.csv" "..\\Shipment_784960.csv"');
    console.error('');
    console.error('Note: Shipment file order does not matter — format is auto-detected from file content.');
    process.exit(1);
  }
```

`new_str`:
```javascript
  // Parse CLI args. Strip flag args (anything starting with --) from the
  // positional list before destructuring, so flag position doesn't matter.
  const rawArgs             = process.argv.slice(2);
  const skipAutoReserveFlag = rawArgs.includes('--skip-autoreserve');
  const args                = rawArgs.filter(a => !a.startsWith('--'));

  if (args.length < 2) {
    console.error('Usage: node import-weekly-staging.js <lunar_catalog> <prh_catalog> [shipment1] [shipment2] [--skip-autoreserve]');
    console.error('');
    console.error('Example (catalog only):');
    console.error('  node import-weekly-staging.js "..\\Lunar_Product_Data_0426.csv" "..\\2026_04_PRH_metadata_full_active.csv"');
    console.error('');
    console.error('Example (catalog + shipment):');
    console.error('  node import-weekly-staging.js "..\\Lunar_Product_Data_0426.csv" "..\\2026_04_PRH_metadata_full_active.csv" "..\\delivery-detail-LUNAR.csv" "..\\Shipment_784960.csv"');
    console.error('');
    console.error('Flags:');
    console.error('  --skip-autoreserve   Force-skip auto-reserve. Auto-enabled for older-month imports.');
    console.error('');
    console.error('Note: Shipment file order does not matter — format is auto-detected from file content.');
    process.exit(1);
  }
```

**Verification immediately after:**
```bash
grep -c "skipAutoReserveFlag\|--skip-autoreserve" import-staging.js
# expect: 3 (one declaration, one usage banner line, one flag-description line)
```

---

### C2 — `import-staging.js` § Step 3 month detection (around line 758)

**Pre-check:** `view import-staging.js [758, 784]`. Confirm matches `old_str` below.

**str_replace:**

`old_str`:
```javascript
  // ── Step 3: Detect new vs same month ─────────────────────
  console.log('\n🔎 Checking current catalog month in database...');
  let isNewMonth = false;
  try {
    const monthRes = await fetch(
      `${SUPABASE_URL}/rest/v1/catalog?select=catalog_month&order=catalog_month.desc&limit=1`,
      { headers: HEADERS }
    );
    if (monthRes.ok) {
      const monthData      = await monthRes.json();
      const currentDbMonth = monthData[0]?.catalog_month || null;
      if (currentDbMonth) {
        isNewMonth = confirmedMonth > currentDbMonth;
        console.log(`   Database month: ${currentDbMonth}`);
        console.log(`   Import month:   ${confirmedMonth}`);
        console.log(isNewMonth
          ? '   🆕 New month — full import sequence will run (archive, purge, delete_dropped)'
          : '   ♻️  Same month — upsert refresh only');
      } else {
        isNewMonth = true;
        console.log('   Empty catalog — treating as new month');
      }
    }
  } catch (e) {
    console.warn('   ⚠️  Could not detect current DB month — defaulting to refresh-only');
  }
```

`new_str`:
```javascript
  // ── Step 3: Detect new vs same vs older month ─────────────
  console.log('\n🔎 Checking current catalog month in database...');
  let isNewMonth   = false;
  let isOlderMonth = false;
  try {
    const monthRes = await fetch(
      `${SUPABASE_URL}/rest/v1/catalog?select=catalog_month&order=catalog_month.desc&limit=1`,
      { headers: HEADERS }
    );
    if (monthRes.ok) {
      const monthData      = await monthRes.json();
      const currentDbMonth = monthData[0]?.catalog_month || null;
      if (currentDbMonth) {
        isNewMonth   = confirmedMonth > currentDbMonth;
        isOlderMonth = confirmedMonth < currentDbMonth;
        console.log(`   Database month: ${currentDbMonth}`);
        console.log(`   Import month:   ${confirmedMonth}`);
        if (isNewMonth) {
          console.log('   🆕 New month — full import sequence will run (archive, purge, delete_dropped)');
        } else if (isOlderMonth) {
          console.log('   ⏪ Older month — backfill upsert only.');
          console.log('      • archive / purge / delete_dropped will NOT run (current month is preserved)');
          console.log('      • auto-reserve will be SKIPPED automatically (issues already shipped)');
        } else {
          console.log('   ♻️  Same month — upsert refresh only');
        }
      } else {
        isNewMonth = true;
        console.log('   Empty catalog — treating as new month');
      }
    }
  } catch (e) {
    console.warn('   ⚠️  Could not detect current DB month — defaulting to refresh-only');
  }
```

**Verification immediately after:**
```bash
grep -n "isOlderMonth" import-staging.js
# expect: 4+ hits (declaration, assignment, branch condition, Step 5 wrapper later)
# at this point in execution sequence: 3 hits (decl, assignment, branch)
```

---

### C3 — `import-staging.js` § Step 5 auto-reserve wrapper (around line 788)

**Pre-check:** `view import-staging.js [785, 791]`. Confirm matches `old_str` below.

**Important:** this `old_str` is short. Confirm there is exactly one occurrence in the file before running `str_replace`:
```bash
grep -c "await autoReserveSubscriptions(confirmedMonth);" import-staging.js
# expect: 1
```

**str_replace:**

`old_str`:
```javascript
  // ── Step 5: Auto-reserve for subscribers ─────────────────
  await autoReserveSubscriptions(confirmedMonth);
```

`new_str`:
```javascript
  // ── Step 5: Auto-reserve for subscribers ─────────────────
  // Skip when:
  //   - --skip-autoreserve flag is passed (manual override), or
  //   - import is for an older catalog month (backfill — issues already shipped)
  const skipAutoReserve = skipAutoReserveFlag || isOlderMonth;
  if (skipAutoReserve) {
    const reason = skipAutoReserveFlag
      ? '--skip-autoreserve flag'
      : 'older catalog month (backfill — already-shipped issues)';
    console.log(`\n⏭️  Skipping auto-reserve (${reason}).`);
  } else {
    await autoReserveSubscriptions(confirmedMonth);
  }
```

**Verification immediately after:**
```bash
grep -n "skipAutoReserve\b" import-staging.js
# expect: 3+ hits (const decl, if-condition, ternary check on reason)
```

---

### C4 — `import-staging.js` § Step 7 older-month notification warning (around line 862)

**Pre-check:** `view import-staging.js [860, 866]`. Confirm matches `old_str` below.

**str_replace:**

`old_str`:
```javascript
  // ── Step 7: Prompt to send notification email ─────────────
  const rl5 = readline.createInterface({ input: process.stdin, output: process.stdout });
  const notifyAnswer = await ask(rl5, '\n📧 Send catalog notification email to all customers? (y/n): ');
```

`new_str`:
```javascript
  // ── Step 7: Prompt to send notification email ─────────────
  // For older-month backfills, warn before the prompt — there's almost
  // never a reason to email customers about an already-shipped catalog.
  if (isOlderMonth) {
    console.log('\n⚠️  This is an older-month backfill — answering "y" below would email');
    console.log('   customers about a catalog that has already shipped. Recommend "n".');
  }

  const rl5 = readline.createInterface({ input: process.stdin, output: process.stdout });
  const notifyAnswer = await ask(rl5, '\n📧 Send catalog notification email to all customers? (y/n): ');
```

**Verification immediately after:**
```bash
grep -n "older-month backfill" import-staging.js
# expect: 1 hit (the warning line)
grep -n "if (isOlderMonth)" import-staging.js
# expect: 1 hit (the Step 7 guard; the Step 3 logic uses else-if, not standalone)
```

---

### C5 — Documentation: parent plan and CLAUDE.md updates

**File 1:** `docs/phase-4-production-migration.md`

In the Sub-Deploys table, the 4.0 row currently reads:
```
| 4.0 | Backfill parity — port prod's older-month features into staging          | `phase-4.0-backfill-parity.md`                        | Planning | —         |
```

`str_replace` to (filling in today's date for `YYYY-MM-DD`):
```
| 4.0 | Backfill parity — port prod's older-month features into staging          | `phase-4.0-backfill-parity.md`                        | Complete | YYYY-MM-DD |
```

And the 4.1 row currently reads:
```
| 4.1 | Pre-cutover hardening — RLS/EF/script cross-tenant audit + canary tenant | `phase-4.1-pre-cutover-hardening.md`                  | Pending  | —         |
```

`str_replace` to:
```
| 4.1 | Pre-cutover hardening — RLS/EF/script cross-tenant audit + canary tenant | `phase-4.1-pre-cutover-hardening.md` (not yet written) | Planning | —         |
```

**File 2:** `CLAUDE.md` § Current Migration Phase

Update the active sub-deploy pointer from 4.0 to 4.1, and add a one-line note that 4.0 closed. Exact `old_str`/`new_str` depend on the current text of that section — the CLI session reads it first, then crafts the diff. If the section's structure has drifted from what this plan assumes, **stop and stop-and-ask**.

---

### C6 — Documentation: § Findings During Execution

**File:** `docs/phase-4.0-backfill-parity.md` (this file).

**Source:** the P4 `git log -p` output captured during pre-flight.

Replace the placeholder in § Findings During Execution with the actual provenance writeup. The placeholder block is the one that begins with `> P4 (\`git log -p`. Replace the entire blockquote with:

- A fenced code block containing the relevant `git log -p` excerpt (commit hashes, dates, authors, messages, and the actual diff hunks that touched `foc_date`)
- A one-paragraph provenance summary in prose
- A bold "**Decision deferred to Sub-Deploy 4.5**" closing line

If P4 returned no `foc_date` history at all, the writeup says so explicitly and notes that the filter predates the current git history (likely introduced before the staging branch was forked or lost to a squash). That absence-of-history is itself the finding.

---

## Execution Sequence

1. `git checkout -b feature/4.0-backfill-parity`
2. Run P1–P6 pre-flight; halt if any fails
3. Capture P4 `git log -p` output to a scratch buffer for C6
4. Apply C1 (arg parsing) — sanity-check by running `node import-staging.js --help`-equivalent (script prints usage when args < 2; verify `--skip-autoreserve` appears in banner)
5. Apply C2 (`isOlderMonth` detection)
6. Apply C3 (auto-reserve wrapper) — `isOlderMonth` from C2 must exist for this to make sense
7. Apply C4 (older-month notification warning) — `isOlderMonth` from C2 must exist
8. Apply C6 (§ Findings During Execution) using the P4 scratch buffer
9. Apply C5 (parent plan + CLAUDE.md doc updates) — last, so they reflect the committed code state
10. Manual verification per § Post-execution Verification
11. Single commit: `feat(4.0): port older-month backfill features from prod import.js`
12. Push branch; open PR; user reviews and merges to `staging`

Single commit because the four features are interdependent and tested as a unit. The history-recovery doc work in C6 + the housekeeping in C5 ride along in the same commit; they're scoped to this sub-deploy and not independently meaningful.

---

## Post-execution Verification

### V1 — Static greps confirm the patch landed
```bash
grep -n "skip-autoreserve\|isOlderMonth" import-staging.js
```
Expect: 4+ hits each (flag definition, usage banner, conditional, wrapper).

```bash
grep -c "skip-autoreserve" import-staging.js
```
Expect: ≥ 3 (raw-args check, usage banner, flag-description block).

### V2 — Newer-month branch unchanged (regression check)
Run the script against a known-newer-month catalog CSV pair. Confirm:
- Step 3 prints "🆕 New month — full import sequence will run..." (unchanged)
- Step 5 calls `autoReserveSubscriptions` (unchanged)
- Step 7 has no older-month warning before the prompt (unchanged)
- Auto-reserve count, catalog upsert count, RPC calls — all unchanged from the pre-4.0 baseline

### V3 — Older-month branch exercises new behavior
Temporarily fabricate an older-month scenario. Two options:

**Option A — staging catalog manipulation:** Insert a sentinel row into staging `catalog` with `catalog_month = '2099-12'`. Run the script with a real recent catalog CSV pair. Step 3 should detect older-month; auto-reserve should be skipped with the printed reason; Step 7 should print the warning. After verification, delete the sentinel row.

**Option B — CSV manipulation:** Rename a recent catalog CSV with an older filename pattern (e.g. `Lunar_Product_Data_0120.csv` to fake January 2026). The `inferCatalogMonth` regex picks up the older month. Run; observe; restore the filename.

Option B is cleaner — no DB state to clean up. Confirm:
- Step 3 prints "⏪ Older month — backfill upsert only" + two sub-bullets
- Step 5 prints "⏭️  Skipping auto-reserve (older catalog month...)"
- Step 7 prints the two-line warning before the prompt
- Catalog upsert runs (older months can still be back-filled)
- `purge_stale_catalog`, `delete_dropped_catalog_items`, `archive_stale_reservations` RPCs do NOT run (gated on `isNewMonth`, which stays false)

### V4 — `--skip-autoreserve` flag exercise
Run with the flag on a same-month or newer-month catalog:
```bash
node import-staging.js <lunar.csv> <prh.csv> --skip-autoreserve
```
Expect:
- Step 5 prints "⏭️  Skipping auto-reserve (--skip-autoreserve flag)"
- All other steps run normally
- Flag position is irrelevant (filter strips it regardless of position)

Also confirm: passing the flag with shipment paths (`node import-staging.js <a> <b> <s1> <s2> --skip-autoreserve`) works — flag filter must not consume positional args.

### V5 — Findings During Execution populated
Open `docs/phase-4.0-backfill-parity.md`; confirm § Findings During Execution exists and contains:
- The `git log -p` output (or absence-of-history note)
- A one-paragraph provenance summary
- A clearly-marked "**Decision deferred to Sub-Deploy 4.5**" line

### V6 — Parent plan + CLAUDE.md reflect closure
```bash
grep "4.0" docs/phase-4-production-migration.md | head -5
```
Expect: row shows status **Complete** with today's date.

```bash
grep "Current Migration Phase" -A8 CLAUDE.md
```
Expect: active sub-deploy reads **4.1**.

---

## Completion Criteria

Sub-Deploy 4.0 is complete when **all** of the following are true on staging:

- [ ] `import-staging.js` contains the `--skip-autoreserve` flag in usage banner and runtime
- [ ] `isOlderMonth` boolean exists and drives the three-state Step 3 logic
- [ ] Step 5 auto-reserve is gated by `skipAutoReserveFlag || isOlderMonth`
- [ ] Step 7 prints the older-month warning when `isOlderMonth === true`
- [ ] V1–V4 manual verification all pass
- [ ] § Findings During Execution populated with `foc_date` filter provenance
- [ ] `docs/phase-4-production-migration.md` Sub-Deploys table: 4.0 → Complete; 4.1 → Planning
- [ ] `CLAUDE.md` § Current Migration Phase: active sub-deploy → 4.1
- [ ] PR merged to `staging`
- [ ] One-day soak passes (nothing breaks; no urgent rollback signals)

---

## Carry-forward / Notes

- **`r.foc_date >= today` filter merge decision** — deferred to Sub-Deploy 4.5 with provenance evidence captured in § Findings During Execution
- **`prod-import.js` historical drift verification** — the 4.5 plan must re-confirm prod hasn't drifted from the 2026-05-26 snapshot at the moment the merge happens. If prod has drifted since 4.0 closed, the merge must account for the additional changes
- **Documentation footprint** — `technical-reference.md` does not document import script behavior in detail; if a section on the script is later added, the older-month/`--skip-autoreserve` features belong there. Not in scope for 4.0
- **Test harness** — the script remains interactive and Playwright-uncovered. A future sub-deploy could add a `--non-interactive` mode and a Playwright (or simpler harness) test suite; out of scope here

---

## Findings During Execution

*Populated by the CLI runbook during execution. Pre-execution placeholder:*

```
P3 command run during pre-flight:
  git log -p -- import-staging.js | grep -B5 -A5 'foc_date' | head -200

Result:
  fatal: not a git repository (or any of the parent directories): .git
```

The `import-staging.js` file lives at `C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts\` — a local-only folder that is explicitly outside the repo and has never been committed to any git repository. `git log -p` cannot recover history for a file with no git tracking.

The filter in question (located at line 915 of `import-staging.js` as of the 4.0 close):

```javascript
const focDates = allCatalogRecords.filter(r => r.foc_date && r.foc_date >= today).map(r => r.foc_date).sort();
```

This feeds `earliestFoc` into the notify-customers Edge Function payload (`foc_date: earliestFoc` at line 923). The filter restricts the FOC date computation to records whose `foc_date` is today or in the future. Production `import.js` may or may not carry the same filter — that comparison is the 4.5 merge task. No commit hash, author, date, or commit message can be attributed to the introduction of this filter; the provenance is unrecoverable from git.

**Decision deferred to Sub-Deploy 4.5.** This sub-deploy intentionally does not propagate, revert, or otherwise resolve the filter divergence. The merge decision happens in 4.5 with this provenance note as input.

---

## Reference

- Parent plan: `docs/phase-4-production-migration.md`
- Anti-drift rules: `CLAUDE.md` § Anti-Drift Rules for Agentic Sessions
- Sibling sub-deploy template (this plan mirrors its shape): `docs/phase-3.6-admin-wednesday-tooling.md`
- Production script source-of-truth snapshot: chat-session artifact `prod-import.js` (captured 2026-05-26)
- Staging script: `import-staging.js` (root of staging repo)
- Project file reference: `/mnt/project/sample-import-staging.js` for context during runbook generation
- Founding tenant UUID (staging): `72e29f67-39f7-42bc-a4d5-d6f992f9d790`

---

**Plan written:** 2026-05-26
**Plan author session:** chat (Opus)
**Execution session target:** Claude Code CLI on staging repo
**Pending decisions before runbook generation:** none — all decisions resolved in § Approach Summary; the `foc_date` provenance decision is explicitly deferred to 4.5 by design
