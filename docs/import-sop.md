# Import SOP — Catalog & Shipment Data

**STATUS:** REFERENCE · created 2026-09-06 · updated 2026-09-07 (F157 zero-row guard)
**Audience:** whoever runs the import. Assumes portal logins and a working `.env` (see F131).
**Scope:** the short, followable version. The *why* behind each step, and every warning-sign
narrative, lives in `docs/monthly-catalog-refresh.md` — that file stays canonical for
**reasoning**; this file is canonical for **sequence**.

---

## The three runs

There is no single "import." There are three separate operator runs on different clocks.
**None of them is scheduled — every one is started by a human.**

| # | Run | When | Script | Manual steps |
|---|---|---|---|---|
| A | Monthly catalog refresh | Once a month, when both new CSVs land | `import.js` | **9** |
| B | Weekly shipment import | Every shipment week (Tue/Wed) | `import.js` | **5** (7 if ad-hoc) |
| C | Weekly date re-check | Fri or Sat | `check-dates.js` | **3** |

**Everything runs from one folder:**

```powershell
cd C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts
```

CSV files go in the folder **above** that one (`..\catalogs\`).
`import.js` = production. `import-staging.js` = staging. They take identical arguments.

**Two flags worth knowing:**
- `--no-write` — dry run. Prints what it *would* write, changes nothing. Use it whenever unsure.
- `--skip-autoreserve` — required on any older-month re-import (Run A, Step 3).

---

## RUN A — Monthly catalog refresh (9 steps)

### 1. Turn Maintenance Mode ON
`https://pulllist.app/admin.html` → **Maintenance Mode** toggle → ON.
Customers see a holding page; you can still browse.

### 2. Close out the month that is ending
- **My List** (as the store admin account) → **Suggest Shelf Order** → review, adjust quantities.
- Confirm last month's order sheets were already exported and placed with the distributors
  (admin → **By Distributor** / **Paper Orders**). If not, export them **now** — Step 5 purges
  unreserved stale rows.

### 3. Revision sweep — re-pull the still-open older months
Distributors revise dates after solicitation, and nothing re-reads an older month on its own.

1. Find which months are still open (any title with a future on-sale date):
   ```sql
   SELECT catalog_month, distributor, COUNT(*)
   FROM catalog GROUP BY catalog_month, distributor
   ORDER BY catalog_month DESC;
   ```
2. Download those months again — **both** distributors:
   - **Lunar** → Product Data file for that month (only the last 3 months exist on the portal)
   - **PRH** → Master Data for that catalog
3. Re-import each one, **oldest first**, typing the *historical* month at the prompt:
   ```powershell
   node .\import.js "..\Lunar_Product_Data_<older-MMYY>.csv" "..\<older>_PRH_metadata_full_active.csv" --skip-autoreserve
   ```
4. Read the line `N unreserved title(s) changed in-store date on re-pull`. That is the whole
   point of this step. Cross-check anything surprising against the distributor's own site.

> **This step is where a wrong file is most likely.** Since 2026-09-07 the import refuses to run
> if a catalog file yields no records (F157), which catches the commonest version of that
> mistake before anything is written. It does **not** catch a *valid* file for the wrong month
> — the month prompt and its guards are still yours to read.

> **Re-importing a month restores whatever the file says.** Any hand-correction to a date is
> silently reverted. Re-apply corrections *after* an older-month import, never before.

### 4. Drop the new month's files in place
Put the two new CSVs in `..\catalogs\`:
- `Lunar_Product_Data_MMYY.csv`
- `YYYY_MM_PRH_metadata_full_active.csv`

Filenames don't matter — you pass them as arguments — but the Lunar name is where the script
reads the month from, so keep the convention.

### 5. Run the import
```powershell
node .\import.js "..\Lunar_Product_Data_MMYY.csv" "..\YYYY_MM_PRH_metadata_full_active.csv"
```
Then answer the prompts — see **Answering the prompts** below. This is one step with several
questions inside it, not several steps.

### 6. Read what the script prints
Do not skip past these; nothing else surfaces them.

**The per-distributor counts (every run, added 2026-09-07 — F157):**
```
   Lunar normalized: 1202 record(s) from 1202 raw row(s)
   PRH   normalized: 1078 record(s) from 1078 raw row(s)
```
Both numbers should be close. A **normalised count far below the raw count** means many rows are
being rejected — usually a changed export format. A normalised count of **zero aborts the run**
(see Troubleshooting).

**The two reports:**
- `N unreserved title(s) changed in-store date` — date revisions found.
- `N title(s) are about to be marked fulfilled with nothing showing they arrived` — books the
  customer is about to be told "Order placed" for. Non-blocking by design. Note them; they land
  on admin → Ordering → **Never Arrived** for a Received / Didn't arrive / Damaged decision.

### 7. Verify the import landed
Supabase → SQL Editor:
```sql
SELECT catalog_month, distributor, COUNT(*) AS items,
       MIN(foc_date) AS earliest_foc, MAX(on_sale_date) AS latest_on_sale
FROM catalog
WHERE catalog_month = 'YYYY-MM'
GROUP BY catalog_month, distributor
ORDER BY distributor;
```
Expect two rows (Lunar, PRH) with counts matching what the script printed.

### 8. Set the Order Deadline
Admin → **Settings** → **Order Deadline**.

> **This is not optional.** A new-month import *clears* the deadline on purpose. Until you set
> it, the At-Risk and Backorder panels classify against an empty value.

Pick a date before the bulk of the new month's FOC dates, leaving customers the longest
possible reservation window.

### 9. Turn Maintenance Mode OFF
Admin → **Maintenance Mode** → OFF. The catalog is live. The script reminds you at the end.

---

## RUN B — Weekly shipment import (5 steps)

The shipment path lives inside the same script, so you still pass the **current month's**
catalog files. That re-upserts the catalog in place, which is safe and expected.

### 1. Get both invoice files
- **Lunar** — the numbered code invoice (first line is just digits)
- **PRH** — the delivery invoice (first line starts `Delivery number`)

> **You need both.** The script skips the shipment entirely if either file is missing.
> Format is auto-detected, so the order you pass them in does not matter.

### 2. If this is an AD-HOC catch-up shipment, not the current week — edit `.env` first
Comment out this line in `scripts\.env`:
```
# GITHUB_TOKEN_PULL_FEED=...
```
**Comment it out. Do not blank it.** Otherwise the newsletter republishes an old week, deletes
the current week's thumbnails, and the Tuesday mailout sends the stale issue. This has happened
for real (2026-08-11).

> **How to tell, and it is NOT about how many shipments you have this week.** Open the invoice and
> look at the on-sale dates. The publish targets the **most common** on-sale date in the file.
> - Most dates in the **current** week → skip this step.
> - Most dates in a week that has **already passed** → do this step.
>
> **A second shipment in the current week is safe** and needs no `.env` edit — it just rebuilds the
> current week's feed with more titles. **A single catch-up shipment is the dangerous one**, even
> though it is the only shipment that week. Count of shipments is irrelevant; the dates decide.
>
> A stray late row inside an otherwise-current shipment is also fine — the "most common date" rule
> was adopted on 2026-08-11 precisely to stop one straggler dragging the publish backwards.

> **A `--no-write` dry run will not answer this for you.** Under `--no-write` the script prints
> `[no-write] would publish weekly pull feed` and never works out which week it would target, so
> you cannot dry-run first to decide. Read the dates off the invoice instead.

### 3. Run the import with all four files
```powershell
node .\import.js "..\Lunar_Product_Data_MMYY.csv" "..\YYYY_MM_PRH_metadata_full_active.csv" "..\delivery-detail-LUNAR.csv" "..\Shipment_784960.csv"
```
Confirm the month at the prompt (it is the **current** month — same month as the DB, so only an
upsert refresh runs). Answer **n** to the notification email.

> **The F157 catalog check runs on shipment weeks too.** You are passing catalog files, so if
> one of them is wrong the run aborts **before the shipment lands**. That is intended — but it
> means a bad catalog file delays the shipment import, so reuse the current month's files you
> already imported rather than re-downloading on the day.

### 4. Check the feed line
- Normal run: `Feed week: YYYY-MM-DD (from ...)` — confirm that date is the week you mean.
- Ad-hoc run: confirm you see `GITHUB_TOKEN_PULL_FEED missing from .env — skipping feed
  publish.` That warning is how you know Step 2 worked.

### 5. Restore `.env` (ad-hoc only)
Uncomment `GITHUB_TOKEN_PULL_FEED`. Do it now, not later — the next weekly run needs it.

**Optional:** see what was reserved but did not arrive:
```powershell
node .\reconcile-shipment.js
node .\reconcile-shipment.js --week=2026-07-08 --out=reconcile.csv
```
Read-only, never writes.

---

## RUN C — Weekly date re-check (3 steps)

Catches dates the distributor revised after solicitation. Only ever updates `on_sale_date` /
`foc_date` on rows that already exist — it never imports a catalog.

### 1. Download two files into `..\recheck\`
- **Lunar** → Resources → **All Products CSV Order Form** (one file, all months)
- **PRH** → Master Data for each catalog the script names

### 2. Run it
```powershell
node .\check-dates.js
```
Add `--no-write` first if you want to look before applying.

### 3. Answer the apply prompt
`Apply N date correction(s) to PRODUCTION? (y/n)`

The script tracks each file's hash between runs and tells you when a PRH catalog has frozen
(stopped changing). Once frozen, no file carries revisions for that month any more — that is a
known dead end, not a mistake on your part.

---

## Answering the prompts (Run A Step 5 / Run B Step 3)

Up to seven questions. Three are conditional guards that appear only when something looks wrong.

| Prompt | Answer |
|---|---|
| `Catalog month detected: YYYY-MM` | Enter to accept, or **type the correct `YYYY-MM`**. If it detected nothing you must type one — there is no default. |
| `CATALOG MONTH MISMATCH … type "yes"` | **STOP.** The two CSVs look like different months. Ctrl-C and check the files. |
| `LUNAR ITEM CODE / CONFIRMED MONTH MISMATCH … type "yes"` | **STOP.** The Lunar codes' embedded month disagrees with what you typed. This is the exact shape of a past incident that mislabelled a whole file. |
| `CROSS-MONTH COLLISION … type "yes"` | **STOP.** Signature of a file already imported once under the wrong month. |
| `Record these as ordered?` (new month only) | Enter = confirm all. `none` = skip all. Or comma-separated numbers to **exclude** those. |
| `Do you have shipment invoices to import this run? (y/n)` | `n` for a catalog-only run. `y` then two file paths otherwise. |
| `Send catalog notification email to all customers? (y/n)` | `y` only on a genuine new-month refresh. **`n`** on shipment runs and older-month backfills. |

**The three "type yes to continue" guards are stop signs, not speed bumps.** Each one exists
because a real import went wrong in exactly that way. Answering `yes` past one without checking
the files is how a whole month lands under the wrong `catalog_month`.

---

## What the script does on its own

You do not trigger any of these; they are listed so the console output is readable.

| Runs when | What happens |
|---|---|
| Every run | Parse + normalize both CSVs |
| Every run | **Check each catalog file produced records — abort if not (F157)** |
| Every run | Save `normalized_catalog.json` |
| Every run | Cross-month collision pre-check |
| Every run | Catalog upsert (UUIDs preserved — safe to re-run) |
| Every run | Clear withdrawal flags for titles that reappeared |
| New month only | Archive past reservations into `reservation_history` |
| New month only | Purge stale unreserved catalog rows |
| New month only | Remove items the distributor dropped |
| New month only | Mark withdrawn titles (only those past their FOC date) |
| New month only | Prompt to confirm the closing cycle's open orders |
| New month only | **Clear the order deadline** (you re-set it at Step 8) |
| New / same month | Auto-reserve subscribers' standard covers |
| Shipment supplied | Import shipment rows, then publish the weekly pull feed |
| Every run | Purge `usage_events` older than 90 days |
| Every run | Report about-to-be-fulfilled titles with no arrival evidence, then auto-fulfill past-on-sale preorders (anything with no arrival evidence is held back 14 days) |

---

## Re-run safety

Re-running is safe. Specifically:
- **Catalog upsert** merges in place on `(tenant_id, item_code, distributor, catalog_month)` —
  reservation links survive.
- **Auto-reserve** detects existing reservations and skips them.
- **New-month sequence** fires only when the import month is *greater* than what's in the DB.
- **Shipment import** is safe to re-run for the same week.

If a notification email errors, the catalog import still succeeded — re-run with the same files
and answer the email prompt again.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `node` is not recognized | Close and reopen PowerShell. Still broken: `$env:PATH += ";C:\Program Files\nodejs"` |
| `Cannot find module 'csv-parse'` | Run `npm install` inside the `scripts` folder |
| `FATAL: ... missing from .env` | A required variable is absent. See `.env.example` for the names |
| `FATAL: SUPABASE_URL_PROD does not point at the production Supabase project` | The `.env` points at the wrong project. The script refuses rather than writing to the wrong database |
| `A CATALOG FILE PRODUCED NO RECORDS (F157)` | **The run aborted before writing anything — nothing was changed.** One of the two catalog files yielded zero usable records. Almost always the wrong file, an empty export, or a changed export format. Note that *raw* rows can look plausible while every row fails: the message prints both counts. Re-download the named file and run again. There is no override, and that is deliberate |
| `Unrecognized shipment format` | The file isn't a Lunar code invoice or a PRH delivery invoice. Check you downloaded the invoice, not a summary |
| Shipment silently skipped | One of the two files was missing. Both are required |
| Wrong catalog month imported | Re-import that month's real file under the correct month; see `monthly-catalog-refresh.md` |

---

## Before handing this to a second operator

They need all of these, and two of them cannot be recovered from any repo (F131):

1. The `scripts` working tree (private repo `comic-preorder-scripts`)
2. **`.env`** — local-only, in no repo. Variable names are listed in `.env.example`
3. **Lunar and PRH retailer portal logins** — the irreplaceable one
4. Admin access to the app, for Maintenance Mode and Order Deadline
5. Knowledge that CSVs go in `catalogs\`, one level above `scripts\`
