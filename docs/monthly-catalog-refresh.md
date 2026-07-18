# Monthly Catalog Refresh — Step-by-Step Guide

**Last updated:** 2026-07-08 (F81 rewrite — see warning below)
**Applies to:** production (`import.js` → `pulllist.app`). The staging variant
(`import-staging.js` → staging Supabase) follows the identical sequence.

> ⚠️ **F81 warning — do not follow older copies of this document.**
> Versions of this guide before 2026-07-08 instructed a manual
> `DELETE FROM preorders` / `DELETE FROM catalog` clear-out before importing.
> That is now **destructive and wrong**: the import script's new-month sequence
> archives reservation history and purges stale catalog rows itself, in the
> correct order. Running the old manual DELETEs first would permanently destroy
> the month's reservation-history archive and fulfillment audit trail.
> **There is no manual SQL step in the monthly refresh.**

---

## Overview

Each month you receive new CSV files from Lunar and PRH. You run one Node.js
script that normalizes both files and pushes everything to Supabase. When the
script detects a **new catalog month**, it automatically runs the full
transition sequence:

1. `archive_stale_reservations` — copies past reservations into
   `reservation_history` (feeds customer recommendations)
2. `purge_stale_catalog` — removes past-month catalog rows that are past
   on-sale and not referenced by any preorder
3. Catalog upsert — UUIDs preserved across re-runs (critical: preorders
   reference catalog rows by UUID)
4. `delete_dropped_catalog_items` — removes items the distributor dropped
5. Auto-reserve — inserts preorders for subscribers' standard covers
6. Optional weekly-shipment import (invoice files)
7. Prompt to send the customer notification email

If the import month **equals** the latest month already in the database, only
the upsert runs ("mid-month refresh") — safe to re-run any time.

**Files you need each month:**
- `Lunar_Product_Data_MMYY.csv` — from Lunar Distribution
- `YYYY_MM_PRH_metadata_full_active.csv` — from PRH
- `import.js` — lives in the local `scripts` folder (never committed to this repo)

---

## Monthly Refresh Steps

### Step 1 — Lock the Site (Maintenance Mode)

1. Go to `https://pulllist.app/admin.html`
2. Switch the **Maintenance Mode** toggle **ON**
3. Customers now see a holding page; admins can still browse

### Step 2 — Confirm Last Month Is Closed Out

Before exporting the order sheets: on **My List** (logged in as the BookStop
admin account), click **Suggest Shelf Order** to populate/review BookStop's
own shelf-copy reservations from open customer demand, then adjust with the
normal quantity steppers / Remove button as needed. See
`docs/shelf-copy-suggested-order.md`.

The order sheets for the closing month should already have been exported and
placed with the distributors at FOC time (admin → **By Distributor** /
**Paper Orders** print buttons). If not, export them now — the new-month
sequence purges unreserved stale catalog rows.

### Step 3 — Drop the New CSV Files

Place the new Lunar and PRH CSVs in the `catalogs` folder (the parent of
`scripts`). Filenames don't matter — you pass them as arguments.

### Step 4 — Run the Import Script

```powershell
cd C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts
node .\import.js "..\Lunar_Product_Data_MMYY.csv" "..\YYYY_MM_PRH_metadata_full_active.csv"
```

Optional: append shipment invoice paths as third/fourth arguments, or answer
the interactive prompt. Answer "n" to skip shipment import early in the month.

**Confirm the catalog month at the prompt.** This matters most when importing
a new month's files before the calendar month starts — type the correct
`YYYY-MM` if the detected value is wrong. A mislabeled month is the root of
the F80 "stale month" defect family.

Flags:
- `--skip-autoreserve` — use on older-month backfills so subscribers aren't
  re-reserved into a past month (the script also skips auto-reserve on
  older-month imports automatically)

### Step 5 — Verify the Import

In **Supabase → SQL Editor**:

```sql
SELECT catalog_month, distributor, COUNT(*) AS items,
       MIN(foc_date) AS earliest_foc, MAX(on_sale_date) AS latest_on_sale
FROM catalog
WHERE catalog_month = 'YYYY-MM'
GROUP BY catalog_month, distributor
ORDER BY distributor;
```

Two rows (Lunar, PRH) with counts matching the script's output. Also confirm
no duplicate rows for cross-distributor titles (F78 watch):

```sql
SELECT title, COUNT(*) FROM catalog
WHERE catalog_month = 'YYYY-MM'
GROUP BY title, distributor, item_code HAVING COUNT(*) > 1;
```

### Step 6 — Set the Order Deadline

Admin → Settings → **Order Deadline**. Choose a date that falls before the
bulk of the new month's FOC dates while leaving customers the longest possible
reservation window. (Candidate for automation — see the 2026-07 review.)

### Step 7 — Turn Maintenance Mode OFF

Admin → toggle **Maintenance Mode OFF**. The catalog is live.

---

## Re-Run Safety

- Catalog upsert: in-place merge on `(tenant_id, item_code, distributor,
  catalog_month)` — UUIDs preserved
- Auto-reserve: detects existing reservations and skips
- New-month sequence: fires only when the import month is **greater** than the
  latest in the database — mid-month re-runs skip archive/purge entirely
- Shipment import: upsert (Lunar path) / delete-then-insert (PRH path), safe
  to re-run for the same week

---

## Troubleshooting

**`node` is not recognized** — close and reopen PowerShell; if still broken:
`$env:PATH += ";C:\Program Files\nodejs"`

**`Cannot find module 'csv-parse'`** — run `npm install` inside the `scripts`
folder.

**Catalog month shows wrong value** — type the correct `YYYY-MM` at the
confirmation prompt.

**Notification error after import** — the catalog import still succeeded.
Re-run the script with the same files (safe upsert) and answer the
notification prompt again.

---

## Useful SQL Queries

**Months currently in the catalog:**
```sql
SELECT catalog_month, distributor, COUNT(*)
FROM catalog GROUP BY catalog_month, distributor
ORDER BY catalog_month DESC;
```

**All reservations for a month:**
```sql
SELECT up.full_name, c.distributor, c.item_code, c.title, p.quantity,
       (c.price_usd * p.quantity) AS line_total
FROM preorders p
JOIN catalog c ON c.id = p.catalog_id
JOIN user_profiles up ON up.id = p.user_id
WHERE c.catalog_month = 'YYYY-MM'
ORDER BY up.full_name, c.distributor, c.title;
```

**Units and value per distributor:**
```sql
SELECT c.distributor, SUM(p.quantity) AS total_units,
       SUM(c.price_usd * p.quantity) AS total_value
FROM preorders p JOIN catalog c ON c.id = p.catalog_id
WHERE c.catalog_month = 'YYYY-MM'
GROUP BY c.distributor;
```

**Customers with no reservations yet this month:**
```sql
SELECT up.full_name, u.email
FROM user_profiles up
JOIN auth.users u ON u.id = up.id
WHERE up.is_admin = false
  AND up.id NOT IN (
    SELECT DISTINCT p.user_id FROM preorders p
    JOIN catalog c ON c.id = p.catalog_id
    WHERE c.catalog_month = 'YYYY-MM'
  )
ORDER BY up.full_name;
```
