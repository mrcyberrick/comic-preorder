# Monthly Catalog Refresh — Step-by-Step Guide

## Overview

Each month you receive new CSV files from Lunar and PRH. You run one Node.js
script that normalizes both files, pushes everything to Supabase, and sends
customer notification emails. The entire refresh takes about 5 minutes.

**Files you need each month:**
- `Lunar_Product_Data_MMYY.csv` — from Lunar Distribution
- `YYYY_MM_PRH_metadata_full_active.csv` — from PRH
- `import.js` — lives permanently in your `scripts` folder, never changes

**Folder structure:**
```
BookStop\
  catalogs\
    scripts\
      import.js          ← run this each month
      package.json
      node_modules\
    Lunar_Product_Data_0326.csv    ← drop new CSV files here
    2026_03_PRH_metadata_full_active.csv
    normalized_catalog.json        ← generated automatically, replaced monthly
    import-catalog.ps1             ← backup only, not needed for normal workflow
  docs\
    schema.sql
    monthly-catalog-refresh.md
```

---

## One-Time Setup (Do This Once)

**1. Install dependencies** — open PowerShell in the `scripts` folder and run:

```powershell
npm install csv-parse
```

**2. Verify Node.js is working:**

```powershell
node --version
# Should return v20.x.x or higher
```

---

## Monthly Refresh Steps

### Step 1 — Lock the Site (Maintenance Mode)

1. Go to `https://mrcyberrick.us/comic-preorder/admin.html`
2. Switch the **Maintenance Mode** toggle **ON**
3. Customers now see a "site under maintenance" message

---

### Step 2 — Export Last Month's Order Sheets

Before clearing anything, save your order records.

1. In the admin panel, go to the **By Distributor** tab
2. Click **↓ Lunar Order Sheet** — save as `YYYY-MM-Lunar.csv`
3. Click **↓ PRH Order Sheet** — save as `YYYY-MM-PRH.csv`

Keep these — they are your order sheets for calling in to the distributors.

---

### Step 3 — Clear Last Month's Preorders

Go to **Supabase → SQL Editor** and run:

```sql
-- Replace '2026-02' with the month you are clearing
DELETE FROM preorders
WHERE catalog_id IN (
  SELECT id FROM catalog WHERE catalog_month = '2026-02'
);
```

Verify it's clear:
```sql
SELECT COUNT(*) FROM preorders
WHERE catalog_id IN (
  SELECT id FROM catalog WHERE catalog_month = '2026-02'
);
-- Should return 0
```

---

### Step 4 — Remove Last Month's Catalog

```sql
-- Replace '2026-02' with the month to remove
DELETE FROM catalog WHERE catalog_month = '2026-02';
```

Verify:
```sql
SELECT catalog_month, COUNT(*) FROM catalog GROUP BY catalog_month;
-- Should show no rows for the deleted month
```

---

### Step 5 — Drop the New CSV Files

Place the new Lunar and PRH CSV files in your `catalogs` folder alongside the
`scripts` folder. You can overwrite the old files or rename them — the script
reads whatever filenames you pass it.

---

### Step 6 — Run the Import Script

Open PowerShell in the `scripts` folder and run:

```powershell
cd C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts
node .\import.js "..\Lunar_Product_Data_0426.csv" "..\2026_04_PRH_metadata_full_active.csv"
```

Adjust the filenames to match what you received from the distributors.

The script will walk you through the rest:

```
📂 Reading CSV files...
   Lunar: 1099 rows
   PRH:   813 rows

🗓️  Catalog month detected: 2026-04
   Press Enter to confirm, or type correct month (YYYY-MM):
   Confirmed: 2026-04

⚙️  Normalizing records...
   Lunar normalized: 1099 records
   PRH normalized:   813 records
   Total:            1912 records

💾 Saved: ..\normalized_catalog.json
📡 Pushing 1912 records to Supabase...
   ✅ Cleared existing records for 2026-04
   Inserted 1912/1912
   ✅ Import complete! 1912 records inserted.

📧 Send catalog notification email to all customers? (y/n): y
   Sending notifications...
   ✅ Notifications sent: 12  Failed: 0

✅ Done! Remember to turn Maintenance Mode OFF in the admin panel.
```

> **Note on catalog month:** The script detects the month from the filename.
> If it shows the wrong month, just type the correct one (e.g. `2026-04`)
> at the confirmation prompt instead of pressing Enter.

---

### Step 7 — Verify the Import

In **Supabase → SQL Editor** run:

```sql
SELECT
  catalog_month,
  distributor,
  COUNT(*) as items,
  MIN(foc_date) as earliest_foc,
  MAX(on_sale_date) as latest_on_sale
FROM catalog
WHERE catalog_month = '2026-04'
GROUP BY catalog_month, distributor
ORDER BY distributor;
```

You should see two rows — one for Lunar, one for PRH — with item counts
matching what the script reported.

---

### Step 8 — Turn Maintenance Mode OFF

1. Go back to `https://mrcyberrick.us/comic-preorder/admin.html`
2. Switch the **Maintenance Mode** toggle **OFF**
3. The catalog is now live — customers can browse and reserve immediately

---

## Monthly Timeline

| When | Task |
|---|---|
| Receive distributor CSVs | Run Steps 5-6 immediately to generate `normalized_catalog.json` |
| ~1 week before FOC | Run full refresh (Steps 1–8) if not already done |
| FOC date | Export order CSVs (Step 2), place orders with distributors |
| After ordering | Clear preorders + catalog (Steps 3–4), ready for next month |

---

## Troubleshooting

**`node` is not recognized**
Close and reopen PowerShell. If still not working:
```powershell
$env:PATH += ";C:\Program Files\nodejs"
```

**`Cannot find module 'csv-parse'`**
Run `npm install csv-parse` from inside the `scripts` folder.

**Catalog month shows wrong value**
Type the correct month at the confirmation prompt (e.g. `2026-04`).
The script accepts any `YYYY-MM` format.

**Notification error after import**
The catalog was still imported successfully. You can trigger notifications
manually by re-running the script with the same files — it will upsert
(not duplicate) the catalog and prompt for notifications again.

**400 Bad Request / encoding errors**
Make sure you are using the latest `import.js`. The script reads CSV files
as UTF-8 which handles special characters in descriptions correctly.

---

## Useful SQL Queries

**Check what months are currently in the catalog:**
```sql
SELECT catalog_month, distributor, COUNT(*)
FROM catalog
GROUP BY catalog_month, distributor
ORDER BY catalog_month DESC;
```

**See all reservations for a given month:**
```sql
SELECT
  up.full_name,
  c.distributor,
  c.item_code,
  c.title,
  p.quantity,
  (c.price_usd * p.quantity) as line_total
FROM preorders p
JOIN catalog c ON c.id = p.catalog_id
JOIN user_profiles up ON up.id = p.user_id
WHERE c.catalog_month = '2026-04'
ORDER BY up.full_name, c.distributor, c.title;
```

**Total units per distributor for a given month:**
```sql
SELECT
  c.distributor,
  SUM(p.quantity)               as total_units,
  SUM(c.price_usd * p.quantity) as total_value
FROM preorders p
JOIN catalog c ON c.id = p.catalog_id
WHERE c.catalog_month = '2026-04'
GROUP BY c.distributor;
```

**Find customers who haven't reserved anything yet this month:**
```sql
SELECT up.full_name, u.email
FROM user_profiles up
JOIN auth.users u ON u.id = up.id
WHERE up.is_admin = false
  AND up.id NOT IN (
    SELECT DISTINCT p.user_id
    FROM preorders p
    JOIN catalog c ON c.id = p.catalog_id
    WHERE c.catalog_month = '2026-04'
  )
ORDER BY up.full_name;
```
