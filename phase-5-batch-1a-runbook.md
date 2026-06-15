# Runbook — Phase 5 Enhancement Batch 1a (first wave)

> **Validated copy — 2026-06-14.** This is the clean-UTF-8, anchor-verified version of the
> Batch 1a runbook. The earlier draft was double-encoded (mojibake `ð¡`/`â`/`â¢`); all glyphs
> here (`📡`, em-dash `—`, `•`, `⚠️`, `📅`, `→`) match the live files byte-for-byte. The E1
> closeout has been corrected for the 5.1 hosting cutover, and the E2/E3 mirror step now
> reflects finding **F70** (staging script's wrong `TENANT_ID`). Apply `old_str`/`new_str`
> blocks exactly as written here — do not re-introduce the old draft's encoding.

**Hand this entire file to a Claude Code CLI session as its first message.** Execute top to bottom, halt on any mismatch, do not improvise.

**Task:** Three independent, fully-scoped enhancements:
- **E1 — UPC on the bagging list** (repo: `admin.html`, staging branch)
- **E2 — Import: report in-store-date changes on reserved titles** (local script, no repo)
- **E3 — Import: catalog month-mismatch guard** (local script, no repo)

**Branch (E1 only):** `feature/batch-1a-bagging-upc` off `staging`
**Findings addressed:** none directly (these are enhancements). **Awareness:** F70 (filed 2026-06-14) — `import-staging.js` carries the **prod** founding-tenant UUID; the E2/E3 mirror step below must NOT touch that line (see Closeout 2). E2 implements the operator's own NOTE in `Change.docx`; E3 implements the "PRH & Lunar must be same month" safeguard.
**Out of scope:** everything else in Batch 1 (hide $0, empty-state placeholders, This Week→popular, bulk fulfillment, rejected status, reservation-history search), all of 5.2, **and the F70 tenant-UUID fix** (separate, needs a live DB check). Do not touch those files.

---

## Pre-flight (halt on any mismatch)

1. `git rev-parse --abbrev-ref HEAD` → `staging`; `git status` clean (a clean tree is expected as of 2026-06-14; if the known stray `docs/status-slide.html` is untracked that's OK; anything else, stop and ask).
2. `git pull origin staging` → up to date / fast-forward.
3. **Read from disk before editing** (never edit from memory):
   - `admin.html` — the `renderThisWeek()` function and its `preorders` query.
   - The local import script at its absolute path (E2/E3 below). Confirm it is the **production** file (`TENANT_ID = '20941129-c35a-476d-ae21-44b8f77af89c'`, header says PROD).
4. **Local-script reality:** the import script is **not in any repo**. E2/E3 are edited against the absolute path, verified with `Select-String` + a dry run, never via `git diff`. After editing, the same logic must be mirrored into the staging import script (`import-staging.js`) — see E2/E3 closeout. **Do not "correct" the staging script's `TENANT_ID` — that's F70, out of scope here.**
5. Environment: PowerShell on Windows. No `&&`; separate lines. Quote paths with parentheses.

---

## E1 — UPC on the bagging list  `[admin.html]`

**What changes:** The This Week bagging rows show title + qty + price. Add the **UPC** (scannable barcode) beside the title so Ray can scan/verify when bagging. The This Week query selects `item_code` but not `upc`, so the query gains `upc`, and the row template gains a UPC span.

> Decision recorded: UPC chosen over `item_code` because it's the physical barcode used at bagging. The import populates `catalog.upc` for both Lunar and PRH rows, so this renders a real barcode on virtually every row (null-guarded for the rare row without one). To switch to the distributor order code instead, display `c.item_code` (already in the query) — trivial flip, no query change.

### E1.1 — Add `upc` to the This Week query select

**File:** `admin.html` — inside `renderThisWeek()`. Verify the target with `Select-String`:

```powershell
Select-String -Path admin.html -Pattern "id, distributor, item_code, title, series_name, publisher,"
```
Expect exactly **one** hit (the This Week `catalog!inner(...)` select). If more or zero, stop and ask.

**Edit** (`old_str` → `new_str`, byte-exact):

old:
```
        catalog!inner(
          id, distributor, item_code, title, series_name, publisher,
          price_usd, on_sale_date, cover_url, variant_type, catalog_month
        )
```
new:
```
        catalog!inner(
          id, distributor, item_code, upc, title, series_name, publisher,
          price_usd, on_sale_date, cover_url, variant_type, catalog_month
        )
```

### E1.2 — Show the UPC in the bagging row

**File:** `admin.html` — the `rows` template inside `renderThisWeek()`. Verify:

```powershell
Select-String -Path admin.html -Pattern 'aria-label="Picked up'
```
Expect exactly **one** hit. If not, stop and ask.

**Edit** (byte-exact). old:
```
          return `
            <li class="bagging-row" style="display:flex;align-items:center;gap:8px;padding:4px 0;font-size:0.92rem">
              <input type="checkbox" class="bagging-check" ${p.fulfilled ? 'checked' : ''} aria-label="Picked up ${escapeHtml(c.title || '')}">
              <span style="flex:1">${escapeHtml(c.title || '—')}${qtyTxt}</span>
              <span style="font-weight:600;color:var(--text-secondary);white-space:nowrap">$${unit.toFixed(2)}</span>
            </li>`;
```
new:
```
          const codeTxt = c.upc
            ? `<span class="bagging-upc" style="font-family:monospace;font-size:0.72rem;color:var(--text-muted);white-space:nowrap">${escapeHtml(c.upc)}</span>`
            : '';
          return `
            <li class="bagging-row" style="display:flex;align-items:center;gap:8px;padding:4px 0;font-size:0.92rem">
              <input type="checkbox" class="bagging-check" ${p.fulfilled ? 'checked' : ''} aria-label="Picked up ${escapeHtml(c.title || '')}">
              <span style="flex:1">${escapeHtml(c.title || '—')}${qtyTxt}</span>
              ${codeTxt}
              <span style="font-weight:600;color:var(--text-secondary);white-space:nowrap">$${unit.toFixed(2)}</span>
            </li>`;
```

### E1.3 — Verify

- `Select-String -Path admin.html -Pattern "item_code, upc, title"` → **1** hit.
- `Select-String -Path admin.html -Pattern "bagging-upc"` → **1** hit.
- Smoke (staging): `cd …\scripts\playwright`; `.\run-smoke.ps1` → full suite green (the `04-arrivals-this-week` spec covers this surface). The UPC is additive markup; specs should be unaffected. If any spec asserts exact bagging-row HTML and fails, stop and report — do not edit the spec.
- Manual (Rick): This Week tab → confirm UPC renders beside titles on screen **and** in Print Bagging List (same DOM, so it prints).

**Commit:**
```
feat(admin): show UPC on This Week bagging rows (Batch 1a E1)
```

---

## E2 — Import: report in-store-date changes on reserved titles  `[local script]`

**What it does:** During catalog upsert, detect any **reserved** title whose `on_sale_date` (in-store date) in the incoming catalog differs from what's already in the DB, and print the deltas in the run summary so Ray knows a customer's title slipped its date. **Read-only signal — changes nothing that gets written.**

**Ordering constraint (critical):** the catalog upsert uses `merge-duplicates`, so the old `on_sale_date` must be captured **before** `refreshCatalog` runs the upsert. We fetch the existing on-sale dates for reserved titles first, hold them in memory, then diff against the incoming records.

**File (absolute path):**
`C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts\import.js`
(the production script; verify `TENANT_ID = '20941129-c35a-476d-ae21-44b8f77af89c'` at the top before editing).

### E2.1 — Add the diff helper

Insert a new function immediately **before** `async function refreshCatalog(` (verify the anchor first):

```powershell
Select-String -Path "C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts\import.js" -Pattern "^async function refreshCatalog"
```
Expect **1** hit.

**Insert before that line** (the `📅` is cosmetic console output — any valid emoji works, but use exactly this so the verify counts match):
```javascript
// ── Reserved-title in-store-date change report ────────────────
// Read-only. Before the catalog upsert overwrites on_sale_date, capture the
// existing in-store date for every catalog row that has a preorder, then diff
// it against the incoming records. Prints a summary of titles whose in-store
// date changed for a customer who has them reserved. Best-effort: any fetch
// failure logs a warning and skips the report (never blocks the import).
async function reportReservedInStoreDateChanges(records, catalogMonth) {
  try {
    // 1. Existing catalog rows for this month, keyed by (item_code||distributor).
    const existing = new Map();
    const catRes = await fetch(
      `${SUPABASE_URL}/rest/v1/catalog?catalog_month=eq.${catalogMonth}` +
      `&tenant_id=eq.${TENANT_ID}&select=id,item_code,distributor,title,on_sale_date`,
      { headers: HEADERS }
    );
    if (!catRes.ok) { console.warn('   ⚠️  In-store-date report: catalog fetch failed — skipped.'); return; }
    for (const row of await catRes.json()) {
      existing.set(`${row.item_code}||${row.distributor}`, row);
    }
    if (!existing.size) return; // nothing to compare against (first import of month)

    // 2. Which of those catalog ids are reserved?
    const ids = [...existing.values()].map(r => r.id);
    const reserved = new Set();
    for (let i = 0; i < ids.length; i += 100) {
      const chunk = ids.slice(i, i + 100);
      const res = await fetch(
        `${SUPABASE_URL}/rest/v1/preorders?select=catalog_id&catalog_id=in.(${chunk.join(',')})`,
        { headers: HEADERS }
      );
      if (res.ok) for (const p of await res.json()) reserved.add(p.catalog_id);
    }
    if (!reserved.size) return;

    // 3. Diff incoming on_sale_date vs existing, for reserved titles only.
    const changes = [];
    for (const rec of records) {
      const key = `${rec.item_code}||${rec.distributor}`;
      const old = existing.get(key);
      if (!old || !reserved.has(old.id)) continue;
      if ((old.on_sale_date || null) !== (rec.on_sale_date || null)) {
        changes.push({ title: old.title, from: old.on_sale_date || '—', to: rec.on_sale_date || '—' });
      }
    }

    if (changes.length) {
      console.log(`\n   📅 In-store-date changes on ${changes.length} reserved title(s):`);
      changes
        .sort((a, b) => (a.title || '').localeCompare(b.title || ''))
        .forEach(c => console.log(`      • ${c.title}: ${c.from} → ${c.to}`));
    } else {
      console.log('   📅 No in-store-date changes on reserved titles.');
    }
  } catch (e) {
    console.warn(`   ⚠️  In-store-date report errored (non-fatal): ${e.message}`);
  }
}

```

### E2.2 — Call it before the upsert

In `refreshCatalog`, the report must run before any catalog write. Verify the anchor:

```powershell
Select-String -Path "C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts\import.js" -Pattern "const today = new Date\(\).toISOString\(\).split"
```
Expect **1** hit (the first line inside `refreshCatalog`).

**Edit** (byte-exact; note the real `📡` emoji). old:
```
async function refreshCatalog(records, catalogMonth, isNewMonth) {
  console.log(`\n📡 ${isNewMonth ? 'Importing' : 'Refreshing'} catalog for ${catalogMonth} (${records.length} records)...`);

  const today = new Date().toISOString().split('T')[0];
```
new:
```
async function refreshCatalog(records, catalogMonth, isNewMonth) {
  console.log(`\n📡 ${isNewMonth ? 'Importing' : 'Refreshing'} catalog for ${catalogMonth} (${records.length} records)...`);

  // Report in-store-date changes on reserved titles BEFORE the upsert overwrites them.
  await reportReservedInStoreDateChanges(records, catalogMonth);

  const today = new Date().toISOString().split('T')[0];
```

### E2.3 — Verify (local)

- `Select-String … -Pattern "reportReservedInStoreDateChanges"` → **2** hits (definition + call).
- Dry run against the real catalog files for the current month (a same-month refresh is non-destructive): run the import, answer the month prompt, and confirm the `📅` report line appears before `📡`/upsert output. The catalog still upserts normally afterward.

---

## E3 — Import: catalog month-mismatch guard  `[local script]`

**What it does:** Today the catalog month is inferred from the **Lunar** filename only; the PRH filename isn't checked. Add a guard that (a) infers the month from **both** filenames and warns if they disagree, and (b) after the operator confirms the month, warns if it's wildly off from the current calendar month (likely wrong file). **Warns and prompts — does not silently halt** (operator may legitimately backfill an older month).

**File:** same absolute path (`…\scripts\import.js`).

### E3.1 — Add the cross-file check after month confirmation

Verify the anchor:
```powershell
Select-String -Path "C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts\import.js" -Pattern "console.log\(`   Using: \$\{confirmedMonth\}`\);"
```
Expect **1** hit.

**Edit** (byte-exact). old:
```
  const confirmedMonth = monthAnswer.trim().match(/^\d{4}-\d{2}$/) ? monthAnswer.trim() : catalogMonth;
  console.log(`   Using: ${confirmedMonth}`);
```
new:
```
  const confirmedMonth = monthAnswer.trim().match(/^\d{4}-\d{2}$/) ? monthAnswer.trim() : catalogMonth;
  console.log(`   Using: ${confirmedMonth}`);

  // ── Month-mismatch guard ──────────────────────────────────
  // (a) Lunar vs PRH filename month: warn loudly if the two catalog files
  //     appear to be for different months (a common copy-paste mistake).
  const prhInferred = inferCatalogMonth(prhCatalogPath);
  if (prhInferred !== confirmedMonth) {
    console.warn(`\n   ⚠️  CATALOG MONTH MISMATCH:`);
    console.warn(`      Lunar file → ${confirmedMonth}`);
    console.warn(`      PRH file   → ${prhInferred}`);
    console.warn(`      The two catalog files look like different months. Both will be`);
    console.warn(`      imported under "${confirmedMonth}". If that's wrong, Ctrl-C now.`);
    const rlChk = readline.createInterface({ input: process.stdin, output: process.stdout });
    const ans = await ask(rlChk, `      Type "yes" to continue anyway: `);
    rlChk.close();
    if (ans.trim().toLowerCase() !== 'yes') {
      console.error('   Aborted on month mismatch.');
      process.exit(1);
    }
  }
  // (b) Sanity vs current calendar month: warn if confirmedMonth is more than
  //     one month away from now in either direction (likely a stale/wrong file).
  {
    const now = new Date();
    const nowMonths  = now.getFullYear() * 12 + now.getMonth();
    const [cy, cm]   = confirmedMonth.split('-').map(Number);
    const confMonths = cy * 12 + (cm - 1);
    const delta = confMonths - nowMonths;
    if (Math.abs(delta) > 1) {
      console.warn(`\n   ⚠️  "${confirmedMonth}" is ${Math.abs(delta)} months ${delta < 0 ? 'in the past' : 'in the future'} ` +
                   `relative to the current calendar month. Double-check this is intended.`);
    }
  }
```

> Note: `readline` and `ask` are already in scope at this point inside `main()` (`readline` is required at the top of `main()`; `ask` is module-level; the month prompt just above uses both), so no new imports are needed.

### E3.2 — Verify (local)

- `Select-String … -Pattern "CATALOG MONTH MISMATCH"` → **1** hit.
- Dry run with two same-month files → no mismatch prompt, import proceeds.
- Dry run with deliberately mismatched filenames (rename a copy) → mismatch warning appears and requires `yes`. (Then discard the rename.)

---

## Closeout

1. **E1 (repo):** merge `feature/batch-1a-bagging-upc` → `staging` with `--ff-only`; then `git push origin staging` **only**. CF Pages auto-deploys the staging preview at `https://staging.pulllist.pages.dev/`. **Do NOT run `git push staging staging:main`** — it was retired by the 5.1 hosting cutover (Phase 5.1 Complete 2026-06-14; the `staging` repo is kept warm as rollback only, no longer a deploy target). Do **not** promote to production in this runbook — E1 is staging-only; Rick opens the prod PR when ready (standard workflow: `git checkout main` → merge → `git checkout main -- config.js` → prod feature branch → PR → CF deploys `pulllist.app` from `main`).
2. **E2/E3 (local scripts):** after verifying on the production `import.js`, **mirror the same two edits into the staging script** `import-staging.js` (keep both in sync — divergence is a known footgun). The E2/E3 edits reference the `TENANT_ID` **variable**, not a literal, so they apply identically to both files — **do not edit the `TENANT_ID` line itself.** ⚠️ **Note (F70):** `import-staging.js` currently has the wrong `TENANT_ID` (`20941129-…`, the prod founding tenant, instead of the staging `72e29f67-…`). That is tracked separately as finding F70 and is **out of scope for this batch** — leave it exactly as-is; do not "fix" it here. (Consequence: E2's report will find nothing on staging until F70 is resolved, which is harmless — the helper returns early.) Verify both files with the same `Select-String` counts. These files are committed to **no repo** — there is no push step.
3. **Status update:** report files changed (with line ranges), `Select-String` counts confirmed, smoke result, and that E2/E3 were mirrored to staging (with the F70 line left untouched). No new findings filed by this runbook. No production database change. No `CLAUDE.md` change beyond what the validation session already recorded.

## Rollback
- E1: revert the feature commit on `staging`; CF redeploys the prior commit.
- E2/E3: revert the local edits (they're self-contained additions; remove the inserted block and the one call line). No data dependency — both are read-only/guard-only.
