# Monthly Catalog Refresh — Step-by-Step Guide

**Last updated:** 2026-08-22 (F136 S3 — added Step 3, the revision-sweep step;
see warning below for the earlier F81 rewrite)
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

## 🚨 Pre-flight: running an AD-HOC shipment import (not the monthly refresh)

**Read this before importing a one-off shipment invoice.** It is not part of the monthly sequence
below, but it is the step most likely to be forgotten and it has already caused one live incident.

> **Comment out `GITHUB_TOKEN_PULL_FEED` in the scripts `.env` before the run. Restore it after.**

**Why.** The weekly pull-feed publish is welded inside the shipment-import block and fires
**unconditionally** (**F135**). It aims at whatever week `resolveFeedWeek()` infers *from the rows
just imported* — and an ad-hoc file holds a handful of books that **already went on sale**, which is
why they are being chased. So its dominant `on_sale_date` is a **past** week. The publish then
republishes that past issue, the orphan purge deletes the current week's thumbnails, and the next
Brevo cron mails the stale issue.

**This is measured, not hypothetical.** Production, 2026-08-11: *"the feed republished 19
already-shipped titles, purged the 50 correct thumbnails as orphans, and the Tue 08-11 Brevo send
mailed that stale issue. The 08-12 week was never previewed at all."*

- **Comment the line out — do not export an empty shell variable.** The `.env` loads through dotenvx
  and whether it overrides an already-present empty key is version-dependent. Commenting is
  unambiguous.
- `upsertShipment()` runs **before** the publish block, so the shipment still lands; the publish is
  skipped with a printed warning. **Confirm you see that warning** — it is how you know the
  mitigation took.
- **F134's one-off shipment path makes ad-hoc imports routine**, which is exactly why this pre-step
  now lives here, in the runbook an operator actually opens, rather than only inside
  `docs/f135-decouple-feed-publish.md`.
- **This is a standing requirement, not a temporary workaround.** The permanent fix (move the
  trigger into the weekly send workflow, delete `resolveFeedWeek()`) is planned and **deferred** —
  Rick's call, 2026-08-29. Until it is built, this manual step *is* the control.

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

### Step 3 — Revision Sweep: Re-Pull Still-Open Months (F136 Part C)

**Do this before Step 4's new-month import.** A distributor can re-issue a
still-open month's file with revised FOC/in-store dates for titles that
haven't gone on sale yet — nothing about the normal monthly cycle re-fetches
an older month on its own, so a date revision on a row **nobody has
reserved** has no detection path unless someone manually re-supplies that
month's file. This is the sequence Rick ran by hand on 2026-08-21 to find and
fix 49 stale production titles (SPAWN SCORCHED #54's FOC pushed a full week
with zero prior signal); this step turns that one-off rescue into a
documented recurring one, feeding S1's widened drift report (F136 Part C(1)
— `classifyReservedDateDrift()`'s `unreserved` list).

1. Re-download the **previous 1–2 still-open months'** Lunar Product Data
   file(s) from the Lunar portal (a month is "still open" if any of its
   titles have an `on_sale_date` still in the future — check via the "Months
   currently in the catalog" query under § Useful SQL Queries below).
2. Re-import them **oldest-to-newest**, one month at a time, confirming the
   correct historical `YYYY-MM` at the prompt (not the new month) and passing
   `--skip-autoreserve` so subscribers aren't re-reserved into a past month:
   ```powershell
   node .\import.js "..\Lunar_Product_Data_<older-MMYY>.csv" "..\YYYY_MM_PRH_metadata_full_active.csv" --skip-autoreserve
   ```
3. **Read the console's F136 report on each run:**
   `📌 N unreserved title(s) changed in-store date on re-pull (F136)` lists
   exactly what changed and for which titles — this is the signal that did
   not exist before S1. If a change looks surprising, cross-check the title
   against the distributor's own site the way Rick did for SPAWN SCORCHED #54
   before trusting it.
4. Repeat for PRH's still-open months if its active-export file has been
   re-downloaded; PRH's export omits withdrawn titles rather than revising
   dates in place (see F110), so this step matters most for Lunar.

**5. This same step is also how you clear a false withdrawal flag (F146) — and it is the *only*
way, for a Lunar-coded one.** A title wrongly marked "Withdrawn — cannot be ordered" clears when it
**reappears in an imported file**. The instinct is to re-pull the *new* month fresher and re-run.
**For a Lunar code that can never work, at any freshness, ever:**

- **Lunar mints its item codes from the solicitation month.** An August title is `0826…`, a
  September one `0926…` — measured across three consecutive monthly files, 100% self-prefixing, with
  **zero** `0826`-prefixed rows in the September file's 1,377 records. A title marked withdrawn was
  marked *because it was absent from the new month's file*, so it necessarily carries the **prior**
  month's permanent code — which cannot appear in any subsequent month's file by construction.
- **PRH codes are issue-scoped**, which fails the same way for a related reason: the next issue
  appears under a *different* code.
- **So: re-pull the mark's OWN month and re-import it as an older-month backfill**, exactly as
  steps 1–2 above describe. That is what cleared all 16 staging marks on 2026-08-29 after a fresh
  September pull had been correctly diagnosed as a guaranteed no-op and the write run withheld.
- **Reading the result — this is the part that matters.** `clearReappearedWithdrawals()` prints
  either `✅ N previously-withdrawn title(s) reappeared — clearing:` with every title named, or
  `N currently-withdrawn title(s) on record; none reappear in this import`. **Do not read the second
  as success.** It has three possible causes and only one is good news: the file genuinely lacks the
  reappearance (wait and re-pull), the fix is broken, or — the one that cost a session — you supplied
  a month whose codes *structurally cannot* match. Check which branch you are in before concluding
  anything. Always `--no-write` first.

Then continue with Step 4 using the **new** month's files.

---

## What a second operator needs (F131)

**This runbook assumes the person running it already holds credentials and portal access. That
assumption is the single-operator risk, not the steps below.** Today the catalog import is one
person, on one machine, with a service-role key that cannot be distributed — invisible at one paying
tenant, load-bearing the moment there are several. This section exists so the *knowledge* half is
recoverable even though the *access* half is not yet.

**What a second operator would need, in order:**

1. **The scripts working tree** — `catalogs/scripts`, the working tree of the private repo
   `github.com/mrcyberrick/comic-preorder-scripts`. Tracked: `import.js`, `import-staging.js`, the
   unit suite. **Not tracked, and not recoverable from any repo:** `.env`, the Playwright suite, and
   the scratch files.
2. **The `.env` variables, by name** (values are local-only and must never be committed):
   `IMPORT_SERVICE_KEY`, `IMPORT_TENANT_ID`, `SUPABASE_URL` for staging, and
   `IMPORT_SERVICE_KEY_PROD`, `IMPORT_TENANT_ID_PROD`, `SUPABASE_URL_PROD` for production, plus
   `GITHUB_TOKEN_PULL_FEED` for the weekly feed publish. `.env.example` in the scripts repo lists
   the shape. Each script hard-fails on a missing var or a URL pointing at the wrong project.
3. **Distributor portal access** — a **Lunar Distribution** retailer login and a **PRH** retailer
   login, to download the two monthly CSVs. **This is the irreplaceable one.** Every tenant's
   catalog is sourced from one shop's distributor accounts; losing that access stales every tenant
   at once, and no amount of documentation substitutes for it.
4. **Where files go** — the two CSVs land in `catalogs/` (the parent of `scripts/`), named
   `Lunar_Product_Data_MMYY.csv` and `YYYY_MM_PRH_metadata_full_active.csv`. Shipment invoices land
   in the same folder.
5. **Admin access to the app** — Steps 1, 7 and 8 (Maintenance Mode, Order Deadline) are UI actions
   requiring an admin account on the tenant.

**Still owed, and only Rick can do it (F131 interim mitigation (b)):** making the `.env` contents
and the two portal logins recoverable by someone other than the current operator. An agent cannot do
this and should not pretend to. Until it is done, items 2 and 3 above are a documented list of
things exactly one person has.

**One open question, flagged and deliberately not researched:** whether populating other retailers'
systems from one retailer account's catalog download is permitted by the distributors' terms. It has
never been checked. Do not treat its absence from this doc as clearance.

---

### Step 4 — Drop the New CSV Files

Place the new Lunar and PRH CSVs in the `catalogs` folder (the parent of
`scripts`). Filenames don't matter — you pass them as arguments.

### Step 5 — Run the Import Script

```powershell
cd C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts
node .\import.js "..\Lunar_Product_Data_MMYY.csv" "..\YYYY_MM_PRH_metadata_full_active.csv"
```

Optional: append shipment invoice paths as third/fourth arguments, or answer
the interactive prompt. Answer "n" to skip shipment import early in the month.

**Confirm the catalog month at the prompt.** This matters most when importing
a new month's files before the calendar month starts — type the correct
`YYYY-MM` if the detected value is wrong. A mislabeled month is the root of
the F80 "stale month" defect family, and as of F136 S1 the script no longer
accepts a silent guess here at all — it requires a typed month.

Flags:
- `--skip-autoreserve` — use on older-month backfills so subscribers aren't
  re-reserved into a past month (the script also skips auto-reserve on
  older-month imports automatically)

### Step 6 — Verify the Import

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

### Step 7 — Set the Order Deadline

Admin → Settings → **Order Deadline**. Choose a date that falls before the
bulk of the new month's FOC dates while leaving customers the longest possible
reservation window. (Candidate for automation — see the 2026-07 review.)

### Step 8 — Turn Maintenance Mode OFF

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
