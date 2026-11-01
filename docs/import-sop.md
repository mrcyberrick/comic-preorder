# Import SOP — Catalog & Shipment Data

**STATUS:** REFERENCE · created 2026-09-06 · updated 2026-10-29 (brought current with the scripts after the 2026-11 import: the import no longer publishes the newsletter feed (F135 S4), so Run B loses its `.env` and feed steps; Run C gains the 2026-10-19 sections (unreserved Lunar corrections under a second prompt, likely recodes, the hand-check list, confirm-to-mark) and its per-environment state file; the Order Deadline and Maintenance Mode are in the dashboard header in Ordering mode, not Settings; dry-run artifacts and the 14-day hold noted in Run A) · earlier: 2026-10-27 (added **Run E**, placing the monthly distributor order, written for someone new to the system, and a "New to the system?" primer; checked against `admin.html` on `staging` the same day) · earlier: 2026-10-09 (any number of shipment files per run; F165 S1 retired the automatic withdrawal mark; F165 S2 report and the recheck-folder rules; later the same day: the F164 pre-import check, handling for the F122 "PINNED" report, and recovery from a dead feed token) · earlier: 2026-09-18 (F157 zero-row guard; F159 frozen-catalog warning)
**Audience:** whoever runs the import. Assumes portal logins and a working `.env` (see F131).
**Scope:** the short, followable version. The *why* behind each step, and every warning-sign
narrative, lives in `docs/monthly-catalog-refresh.md` — that file stays canonical for
**reasoning**; this file is canonical for **sequence**.
**Last checked against the scripts:** scripts repo `main` at `6de0c5f` (read 2026-10-29; was `3ef4b89` on 2026-10-09). If
`git log` in the scripts folder shows newer commits to `import.js`, `import-staging.js` or
`check-dates.js`, re-check the prompts table and the Run C report sections before trusting this file.

---

## New to the system? Start here

PULLLIST is the store's comic pre-order website. Customers browse next month's comics online and
**reserve** the ones they want. Once a month the store turns those reservations into an order with
the two comic distributors, and when the books arrive the store bags them for each customer.

Words you will see on every screen:

| Word | What it means |
|---|---|
| **Lunar** and **PRH** | The two distributors the store buys from (Lunar Distribution; Penguin Random House). Each has its own retailer website, and each needs its own order |
| **Catalog month** | The monthly list of comics the distributors offer, loaded into the app once a month (Run A). Written `YYYY-MM`, for example `2026-11` |
| **Reservation** | One customer asking for one title (with a quantity). "Pre-order" means the same thing |
| **FOC date** | "Final Order Cutoff": the last day the store can order a title from the distributor. After it passes the app locks the title, and ordering it then is a **backorder** that may not arrive |
| **Order cycle** | All the titles that share one FOC date. A catalog month has many (13 in July 2026), so you order **by cycle**, not "the whole month" |
| **Order Deadline** | The date shown to customers as their last day to reserve. It is a customer cutoff only; the distributor's FOC dates are separate |
| **Paper customer** | A customer with no login whose order was written on the printed catalog in the store. Staff type it in for them |
| **Order record** | The app's list of what was actually ordered from each distributor. The Order Builder adds to it; it is never edited, only added to (corrections are new lines) |
| **Maintenance Mode** | A switch that shows customers a "back soon" page so nothing changes while you work. Admins can still use everything |

**Where things are.** Sign in at `https://pulllist.app/` with the store's admin account and open
**Admin ▾ → Dashboard**. Along the top are three mode buttons: **Customers** (ongoing work, and the
Order Follow-Up panel), **Bagging** (weekly) and **Ordering** (monthly). The **Order Deadline** box and
the **Maintenance Mode** switch sit in the dashboard header, and appear **only in Ordering mode**.

> **One naming note.** The Ordering tab labelled **All Orders** on screen is called "By
> Distributor" in older notes and in a few on-screen messages. They are the same tab.

---

## The runs (and one procedure for when a product code changes)

There is no single "import." There are three separate operator runs on different clocks, plus
**Run D**, a procedure you start when the distributor changes a product code, and **Run E**, the
monthly distributor order, which is done in the website rather than with a script.
**None of them is scheduled — every one is started by a human.**

| # | Run | When | Script | Manual steps |
|---|---|---|---|---|
| A | Monthly catalog refresh | Once a month, when both new CSVs land | `import.js` | **9** |
| B | Weekly shipment import | Every shipment week, once its invoices are out (lately Fridays) and **before the Tuesday newsletter send (cron 21:00 UTC)** | `import.js` | **3** |
| C | Weekly date re-check | Fri or Sat | `check-dates.js` | **3** |
| D | A product code changed (Lunar recode) | When Run C or the Never Arrived panel shows a reserved code that the distributor replaced | store admin: screens only (D0 to D3); operator: one SQL block to carry the reservation across (D4) | **4 per customer** (UI) |
| E | **Place the monthly distributor order** | Once a month, after the customer Order Deadline passes, before the FOC dates you are ordering, and **before** Run A (Run A's new-month import closes the month) | none: the website only (admin dashboard + each distributor's retailer site) | **12** |

**Everything runs from one folder:**

```powershell
cd C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts
```

CSV files go in the folder **above** that one (`..\catalogs\`).
`import.js` = production. `import-staging.js` = staging. They take identical arguments.

**Flags worth knowing:**
- `--no-write` — dry run (`import.js` and `check-dates.js`). Prints what it *would* write, changes
  nothing. Use it whenever unsure. One limit: `check-dates.js` still records what it saw in its
  state file and writes its before-state log (see Run C). On `import.js`, a few dry-run lines read
  differently from the real run because nothing was written (Run A, Step 5).
- `--skip-autoreserve` — `import.js` only. Skips subscriber auto-reserve. Pass it on any
  older-month re-import (Run A, Step 3); the script also switches it on by itself when the month
  is older than the database's.
- `--staging` — `check-dates.js` only. Points it at staging. It still needs the **production**
  variables in `.env`, because it loads `import.js`. Since 2026-10-19 it keeps its own state file
  (`check-dates-state.staging.json`) and its logs carry `-staging-` in the name (F175, F177), so a
  staging run no longer touches production's withdrawal history or revert logs.
- *(`--include-unreserved` was REMOVED 2026-10-19. Run C now checks unreserved Lunar listings in
  every month on every run and corrects them under their own prompt; see Run C, Step 3.)*

---

## Before ANY import (Run A or Run B): confirm there is no second tenant (F164)

Until the guard in `docs/pre-phase-6-gate-closure.md` § 2e (session G-I) is built, the import's
auto-reserve reads **every** tenant's subscriptions and catalog rows with no tenant filter. With one
tenant that is harmless; the first time a second tenant has either, an import can write a
reservation across tenants. This is not a prompt — nothing in the script stops you — so run both
queries first (Supabase → SQL Editor, on the environment you are importing to) and **stop if either
shows a second tenant**:

```sql
SELECT tenant_id, count(*) FROM subscriptions GROUP BY tenant_id;
```
```sql
SELECT tenant_id, catalog_month, count(*) FROM catalog GROUP BY tenant_id, catalog_month ORDER BY catalog_month DESC, tenant_id;
```

Expect one tenant in the first. In the second, expect only the founding tenant for the month you
are importing. Production read exactly that on 2026-10-06 and again on 2026-10-09 (63 subscriptions,
one tenant; 2026-10 all one tenant; a second tenant held only 2 rows, in 2026-06, which is harmless),
and again before the 2026-11 import on 2026-10-28 (66 subscriptions, all the founding tenant; the
same 2 `comicstore` rows in 2026-06, nothing else).
Staging holds `demoshop` rows for 2026-09, which is why a 2026-10 staging import cannot misfire.

---

## RUN A — Monthly catalog refresh (9 steps)

### 1. Turn Maintenance Mode ON
`https://pulllist.app/admin.html` → **Ordering** mode → **Maintenance Mode** switch in the
dashboard header → ON. (The switch only appears in Ordering mode.)
Customers see a holding page; you can still browse.

### 2. Close out the month that is ending
- **My List** (as the store admin account) → **Suggest Shelf Order** → review, adjust quantities.
- Confirm last month's order was already placed and recorded with both distributors (**Run E**
  below). If not, do Run E **now** — Step 5 purges unreserved stale rows. (Run E Step E4 turns
  Maintenance Mode on and Step E12 tells you to leave it on when Run A follows straight away.)

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

> **Weigh this step against Run C before doing it (added 2026-10-29).** Since 2026-10-19 the weekly
> recheck (Run C) corrects dates on **reserved** titles and on **unreserved Lunar** listings in every
> catalog month, from fresher sources than a monthly file. So the Lunar half of this sweep is now
> covered every week, and a re-import can put back a date Run C has already fixed. What only this
> step still catches is a revised date on an **unreserved PRH** title in a live PRH month (Run C
> leaves unreserved PRH rows alone, F159). If Run C ran in the last week, skipping this step is
> reasonable; if you do run it, run Run C straight after it so any reverted date is corrected
> again. The 2026-11 import (2026-10-28) skipped it; Run C had last run 2026-10-23.

### 4. Drop the new month's files in place
Put the two new CSVs in `..\catalogs\`:
- `Lunar_Product_Data_MMYY.csv`
- `YYYY_MM_PRH_metadata_full_active.csv`

Filenames don't matter — you pass them as arguments — but the Lunar name is where the script
reads the month from, so keep the convention.

### 5. Run the import
Dry run first, then the real run:
```powershell
node .\import.js "..\Lunar_Product_Data_MMYY.csv" "..\YYYY_MM_PRH_metadata_full_active.csv" --no-write
node .\import.js "..\Lunar_Product_Data_MMYY.csv" "..\YYYY_MM_PRH_metadata_full_active.csv"
```
Then answer the prompts — see **Answering the prompts** below. This is one step with several
questions inside it, not several steps. Pass **no** shipment files on a catalog run and answer
`n` to the shipment question.

**Three dry-run lines that are NOT problems** (seen on the 2026-11 dry run; the real run read
correctly):
- `No order_deadline row on record for this tenant — nothing to clear.` The dry run pretends to
  write and gets nothing back. The real run prints `✅ order_deadline cleared`.
- `Catalog rows fetched: 0` and `✅ No new auto-reserves needed.` The new month's rows were not
  written, so there is nothing to match subscriptions against. The real run should show a non-zero
  `To insert` (2026-11: 66 subscriptions, 33 auto-reserved). **A zero in the real run is a problem.**
- `✅ Archived  reservation(s)`, `Purged  stale unreserved rows`, and so on, with no number. The
  counts only exist once the database has done the work.

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

**The reports:**
- `N reserved title(s) PINNED to a superseded listing (F122)` — **act on this one.** A title was
  re-listed under a newer month with a different date, but the reservations still point at the old
  row, so customers see the **wrong date** (and once that stale date passes, the title drops out of
  My List entirely). The import cannot fix it: its upsert keys on the month. The by-hand repair
  (a production write — yours, not the script's) is in `docs/technical-reference.md` § 13 F122,
  "Repair applied 2026-08-10": `UPDATE` each reservation's `catalog_id` to the newest listing's id,
  **filtered on the expected old `catalog_id`** so a changed state matches zero rows and writes
  nothing; if that customer already holds the newest row (a unique pair), delete the redundant older
  reservation only **after** the `UPDATE`. The report prints on shipment weeks too (a same-month
  refresh), so read it there as well.
  **Often Run C fixes it with no repoint (seen 2026-10-09).** When the newer month's PRH file is in
  `..\recheck\`, the weekly recheck lists the title under `STRANDED` and its apply prompt corrects
  the **old row's date** to the newest listing's. The three Magic: The Gathering Liliana #2 covers
  that the 2026-10-09 import reported as pinned were fixed that way (42 of 42 corrections confirmed by a fresh read afterwards): their reservations stay on the old
  row but now show the right date. It works when the date is the only problem, and it depends on the
  newest month's file being read last (files are read in name order), so do not rename them.
- `N unreserved title(s) changed in-store date` — date revisions found.
- `N title(s) are about to be marked fulfilled with nothing showing they arrived` — books the
  customer is about to be told "Order placed" for. Non-blocking by design. Note them; they land
  on admin → Ordering → **Never Arrived** for a Received / Didn't arrive / Damaged decision.
  **This list overstates what is fulfilled now.** It counts every unfulfilled reservation past its
  on-sale date, but the fulfil step itself holds back any title with no shipment record until 14
  days after its on-sale date (F155 S3). Compare with the next line, `Auto-fulfilled N preorder(s)`:
  on 2026-10-28 the list named 36 titles (38 reservations) and only 2 reservations were fulfilled,
  the one title more than 14 days past on-sale. The rest stay open and are still flagged for
  Never Arrived.

**The withdrawal line (every run, since 2026-10-04 — F165 S1):**
```
   Withdrawal marking is retired from the import (F165 S1); nothing marks a title withdrawn ...
```
The import no longer marks anything withdrawn. It only *clears* a mark when a title reappears
(`N previously-withdrawn title(s) reappeared — clearing`). The line exists so that a missing
"withdrawn title(s) detected" is not read as "none found". Its tail ("until check-dates.js gains
the candidate report (S2)") is out of date: that report now exists, in Run C, and is report-only.

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
Admin dashboard → **Ordering** mode → **Order Deadline** box in the dashboard header.
*(This step read "Admin → Settings → Order Deadline" until 2026-10-29. The Settings page only links
back to the dashboard for it.)*

> **This is not optional.** A new-month import *clears* the deadline on purpose. Until you set
> it, the At-Risk and Backorder panels classify against an empty value.

Pick a date before the bulk of the new month's FOC dates, leaving customers the longest
possible reservation window. Step 7's `earliest_foc` gives the first one; to see how titles spread
across FOC dates:
```sql
SELECT foc_date, COUNT(*) FROM catalog WHERE catalog_month = 'YYYY-MM'
GROUP BY foc_date ORDER BY foc_date LIMIT 6;
```
Titles whose FOC falls before your deadline show as **At risk** and are ordered ad-hoc (Run E, E1).

### 9. Turn Maintenance Mode OFF
Admin dashboard → **Ordering** mode → **Maintenance Mode** → OFF. The catalog is live. The script
reminds you at the end.

**Then:** print the in-store paper catalog for the new month (Paper Orders → **Print Catalog**,
Run E step E10).

---

## RUN B — Weekly shipment import (3 steps)

The shipment path lives inside the same script, so you still pass the **current month's**
catalog files. That re-upserts the catalog in place, which is safe and expected.

> **The import does not publish the newsletter any more (F135 S4, scripts `fc044f9`, 2026-10-13).**
> The `weekly-pull-feed` repo's own Tuesday workflow builds the feed from the database and sends it;
> a read-only Monday preflight warns if the week is empty. So there is no `.env` edit for an ad-hoc
> or catch-up shipment, no feed line to check, and no token to keep alive: an old week's invoice can
> no longer republish a past newsletter. *(Until 2026-10-29 this run had five steps, including
> "comment out `GITHUB_TOKEN_PULL_FEED` for an ad-hoc import", "check the feed line" and "restore
> `.env`". Those are retired; the `GITHUB_TOKEN_PULL_FEED` line is gone from `.env` and the tokens
> were deleted on 2026-10-21.)* **Run the import before Tuesday's send** (cron 21:00 UTC, often
> starting a few hours late), because the send reads whatever shipment rows are loaded.

### 1. Get every invoice file for the week
- **Lunar** — the numbered code invoice (first line is just digits). One per week.
- **PRH** — one **delivery-detail** file *per delivery* (first line starts `Delivery Number`).
  A week can have several deliveries; the week of 2026-10-05 had three.

> **Pass all of the week's files in the one run — any number, any order.** Format is detected from
> the file's contents, not its name. Since 2026-10-04 there is no two-file limit, and no placeholder
> file is needed when a week has only one distributor's invoice.
>
> **Why together:** quantities for the same title are *summed* across the files in one run, but a
> later run *replaces* what an earlier run stored (PRH rows merge on UPC + on-sale date; the Lunar
> code invoice deletes that on-sale date's rows and re-inserts them). A title split across two
> deliveries is only right if both files go in the same run — a later run with just one of them
> overwrites the other's quantity instead of adding to it. Titles in only one file are unaffected.

### 2. Run the import: the two catalog files, then every shipment file
```powershell
node .\import.js "..\Lunar_Product_Data_1126.csv" "..\2026_11_PRH_metadata_full_active.csv" "..\Shipment-detail-LUNAR.csv" "..\Shipment-detail-PRH.csv"
```
That is the shape for a week in the 2026-11 catalog month: substitute the current month's two
catalog files (the month the database is on, which changes after each Run A), and add one more
quoted path for each extra delivery.

Confirm the month at the prompt (it is the **current** month — same month as the DB, so only an
upsert refresh runs). Answer **n** to the notification email.

With the shipment files on the command line, the script does **not** ask "Do you have shipment
invoices?". Leave them off and it asks, then takes one path per line until a blank line.

**All-or-nothing, and it says so.** If any listed shipment file is missing, or one repeats another
(same path, or the same delivery/shipment number), the script prints a `❌` line naming the file and
skips the **whole** shipment import: nothing is read or written for the shipment.
The catalog refresh before it still happened. Fix the list and run again with the full set; re-running
files that already loaded is safe. A file that yields no rows is called out by name
(`contributed 0 rows`); a file that is neither format prints `Unrecognized shipment format`.

> **The F157 catalog check runs on shipment weeks too.** You are passing catalog files, so if
> one of them is wrong the run aborts **before the shipment lands**. That is intended — but it
> means a bad catalog file delays the shipment import, so reuse the current month's files you
> already imported rather than re-downloading on the day.

### 3. Read what it printed
- The F157 per-distributor counts and the reports from Run A, Step 6 print here too (a same-month
  refresh); the `PINNED` one is the one to act on.
- Each shipment file's row count. A file that `contributed 0 rows` is usually the wrong download.
- **Free promos are dropped on purpose** (F172, since 2026-10-23): a Lunar row with `Retail` 0, or
  with `Total` or `Discounted Price` exactly 0 (a 100%-discounted giveaway such as an ashcan), is
  not loaded, so it is not on the store grid or the newsletter even though it is in the box.
- The newsletter is not mentioned: the import does not publish it (see the note at the top of this
  run). If Tuesday's email looks wrong, look at the `weekly-pull-feed` workflow run, not here.

**Optional:** see what was reserved but did not arrive:
```powershell
node .\reconcile-shipment.js
node .\reconcile-shipment.js --week=2026-07-08 --out=reconcile.csv
```
Read-only, never writes.

---

## RUN C — Weekly date re-check (3 steps)

Catches dates the distributor revised after solicitation. Only ever updates `on_sale_date` /
`foc_date` on rows that already exist — it never imports a catalog. Since 2026-10-04 it also prints
several **report-only** sections that write nothing (Step 3 says which).

### 1. Empty `..\recheck\`, then download into it — LIVE catalogs only
**The script reads every `.csv` at the top of that folder.** Move last week's exports out first (to
`..\old\`), or two Lunar files, or a stale PRH month, are read together and a re-supplied file shows
as `unchanged ×N`. The `_frozen-do-not-use\` sub-folder is not read; leave it alone.

- **Lunar** → Resources → **All Products CSV Order Form** (one file, all months). The file we have
  been getting is named `Lunar Available Products - MMDDYYYY.csv`; the script recognises it by its
  header (an `In-Store` column), not its name.
- **PRH** → Master Data for each **live** catalog — roughly the last three months, and the newest
  catalog too.

> ⚠️ **Do NOT pull a frozen PRH catalog, even though the script asks for it.** The script's
> `NEXT RUN` list ranks months by how many reserved codes they hold and **knows nothing about**
> **freezing** — on 2026-09-18 it listed 2026-05, which is frozen. A frozen catalog reports the
> original solicitation date forever, and the script will write that stale date over a correct
> one. That happened on 2026-09-18 (**F159**) and had to be reverted by hand.
>
> Already-frozen files live in `..\recheck\_frozen-do-not-use\`. **Leave them there.**
> As of 2026-10-09: 2026-07 / 08 / 09 / 10 are live; 2026-04, 05 and 06 are frozen and quarantined.
> **2026-07 is at the edge** — it still produced two corrections on 2026-10-02, so keep pulling it
> until a pull comes back byte-identical, then quarantine it too.
>
> **The script's own frozen rule covers only half the job.** Since 2026-10-04 its withdrawal-candidate
> section skips PRH months more than three months old, but the date-**correction** step still has no
> frozen-month guard (F159 is open). The quarantine above is the only protection for that half.

### 2. Run it
```powershell
node .\check-dates.js --no-write
node .\check-dates.js
```
The `--no-write` run first is cheap: it reads and reports, and applies nothing. It still records what
it saw in `check-dates-state.json` (scripts folder), and a dry run plus the real run on the same day
count as **one** observation, not two. Do not delete that file: the withdrawal report's two-run
history lives in it. A `--staging` run uses `check-dates-state.staging.json` instead (F175), so it
is safe to run against staging again.

### 3. Read the report, then answer the apply prompt
Read these in order. The first two groups are written by the first apply prompt, the unreserved
Lunar group by a second one, and withdrawal candidates by their own per-title question; the rest
are for you.

| Section | What it means | What you do |
|---|---|---|
| `⚠️ STRANDED` | Reserved title in an **older** month whose date moved. `← ALREADY HIDDEN FROM CUSTOMERS` means the customer cannot see it at all | Applied by the first prompt below — read these first |
| `N reserved title(s) in the current month … changed date`, `N title(s) changed FOC date only` | Ordinary revisions | Applied by the first prompt below |
| `📋 UNRESERVED LUNAR LISTINGS (F173 (a))`, with `HIDDEN BUT STILL ORDERABLE` listed first | Unreserved Lunar listings, any catalog month, whose dates disagree with Lunar's export. "Hidden but still orderable" means our FOC has passed and Lunar's has not, so no customer can reserve a title that is still for sale | Applied by the **second** prompt below. Replaces the removed `--include-unreserved` flag |
| `✋ PREVIOUSLY CORRECTED; CHECK BY HAND` | Unreserved Lunar listings whose current value was set by an earlier **hand fix** (read from the one-off fix scripts' logs), held out so the recheck does not undo it (F159) | **Report only.** Check on Lunar's site; correct by hand if needed |
| `🔁 LIKELY RECODES` | A reserved Lunar code missing from the export while another of our listings, in a **different** month, has the same UPC (or ISBN) | **Report only.** If Lunar confirms the recode, move the reservations with Run D-MOVE |
| `📅 CHECK THESE DATES BY HAND on Lunar's site` | Reserved Lunar titles in-store within 35 days but absent from the export, so no file can correct their date | **Report only.** Look each up on Lunar's site |
| `🚨 N FULFILLED reservation(s) with no arrival judgement …` (F158) | Closed within the last 14 days, so customers already see "Order placed", with nothing showing it arrived. Nothing else catches these | **Report only.** Each needs a human decision |
| `⛔ N reserved title(s) the distributor shows as CANCELLED / no longer sold` | Lunar still lists the title but with a **placeholder** in-store date before 2000 (usually 1/1/1901, FOC 1/1/1900; the title often ends "Cancelled"). The script never writes that as a date | **Report only.** See below |
| `N reserved code(s) absent from this week's exports`, then `>> N … PAST on-sale with NO shipment evidence` | "Catalog not pulled" is no signal. The `>>` list is the F155 shape: nothing can correct it automatically | **Report only.** Look the listed titles up by hand |
| `🔎 WITHDRAWAL CANDIDATES` | Titles absent from their **own** source on two runs, on different dates. Lunar ratio covers (1:25 and so on) and PRH codes listed in any supplied PRH file are no longer candidates (the two V5 false-alarm causes) | One `Mark as withdrawn? [y/N]` question each, after the report. See below |
| `📥 NEXT RUN`, `🧊 FROZEN CATALOG(S)` | Which PRH catalogs to pull next time; catalogs whose file stopped changing | Ignore any month on the frozen list |

**Cancelled titles (Lunar's 1/1/1901 date).** Lunar sometimes keeps a title it no longer sells in
its export and sets the in-store date to a placeholder: 1/1/1901 mostly, but also 2/1/1901,
12/31/1900 and others (469 such rows in the 2026-10-09 export). Until scripts commit `8e2dae9`
(2026-10-11) `check-dates.js` read these as real dates, so a reserved title would have been
"corrected" to 1901-01-01, dropped off My List and been auto-fulfilled at the next import. It now
ignores any in-store date before 2000 and lists the reserved ones in the `⛔` section, with our
in-store date, the copies ordered (`ledger net`) and Lunar's note. Confirm each one on Lunar's
site, then:

| Where the title stands | What to do |
|---|---|
| Our in-store date has passed | Order Follow-Up → **Didn't arrive** (the customer sees "No longer coming" / "Store is handling this") |
| Ordered (`ledger net` above 0), in-store date not yet passed | **Rejected by supplier** (the customer sees Rejected and can remove it) |
| Never ordered (`no order recorded`) | Cancel the reservation for the customer through impersonation |

*(This paragraph read "There is no Withdrawn mark to set; that is F165 S3 and is not built" until
2026-10-29. S3 landed 2026-10-19; see Withdrawal candidates below.)* A title Lunar drops from
the export altogether, rather than re-dating it, shows up under withdrawal candidates instead. That
is how BUFFY THE VAMPIRE SLAYER #2 CVR A (shown as Cancelled, 1/1/1901 on Lunar's site, 2026-10-11)
appeared, and it was already marked Didn't arrive.

**Withdrawal candidates.** The import never marks a title withdrawn (F165 S1). Since 2026-10-19
(F165 S3) this script asks about **each** candidate, after the report and never under `--no-write`:
`Mark as withdrawn? Check the distributor's site first. [y/N]`. **The default is No**, and only
`y` or `yes` marks. The question first says what a "y" does: the reservation's customers see
"cannot arrive" on My List at once and may remove it, even if it was ordered. Absence is evidence,
not proof (a withdrawn title and one whose allocation merely closed look the same in these files),
so check each one on the distributor's site before answering. **If you mark one that was ordered,
also record "Rejected by supplier"** in admin (Order Follow-Up), so the order record nets to 0.
Before writing, the script saves each chosen row's before-state to that day's
`check-dates-log-YYYY-MM-DD.json`, and afterwards it re-reads the rows and counts them. A title is
only listed after it is absent on two runs on **different dates**, so the first run on a new title
records a first sighting (`N absent for the first time`) and cannot list it.

**The apply prompts** appear only if there is something to write (otherwise `No reserved date
corrections needed`), in this order:

1. `Apply N date correction(s) to PRODUCTION? (y/n)` (reserved titles). Before it asks, the script
   writes the before-state to `check-dates-log-YYYY-MM-DD.json` in the scripts folder (exact revert
   data; written for `--no-write` too).
2. `Apply N UNRESERVED Lunar date correction(s) to PRODUCTION? (y/n)` (the `📋` group). Its own
   before-state log is `check-dates-unreserved-log-YYYY-MM-DD.json`; `--no-write` writes neither
   this log nor the rows. It is asked whichever way you answered the first.

After each `y` it re-reads the rows and prints `Done. N/N confirmed by an independent re-read`;
`VERIFICATION FAILED` means stop and look. On a `--staging` run the prompts say STAGING and the
log names carry `-staging-`. **Re-run this after any older-month import** — re-importing a month restores whatever its file says.

A frozen PRH catalog is a **known dead end, not a mistake on your part** — once frozen, no file
carries revisions for that month any more.

> ⚠️ **Do not rely on the script's `unchanged ×N` counter to tell you a catalog has frozen.**
> *(This paragraph previously said the script "tracks each file's hash between runs and tells
> you when a PRH catalog has frozen." **Measured false on 2026-09-18**, and corrected here — the
> same shape as F155's own root cause, where one confident runbook sentence stopped anyone
> re-pulling PRH at all.)* Two reasons it cannot carry that weight: only a file seen on a
> **previous** run carries a stored hash, so a first-seen file gives no signal at all — five of
> seven did on 2026-09-18 — and the counter cannot tell *"the distributor stopped publishing"*
> from *"the operator re-supplied the same file"*. Re-run a stale file a few weeks running and
> it will declare a **live** catalog frozen. **Judge by catalog age instead: roughly three
> months past the catalog date.**

---

## RUN D — A product code changed (Lunar recode)

Sometimes Lunar replaces a title's product code and keeps the comic: **Hyde Street #14 CVR A** went from
`0526IM0377` to `0726IM0466` (2026-10). **Nothing in the app links the two codes.** The weekly recheck
compares each code on its own, so the old code simply goes missing from Lunar's export and nothing ever
corrects itself: the reservation does **not** transfer to the new code. Left alone, the old reservation keeps
a dead date (and can drop out of the customer's My List), the admin panels read it as "released, nothing
arrived", and the weekly import closes it once its stale on-sale date is 14 days past; the customer then sees
it under "No longer coming" for 180 days.

**Who does what.** D0 and D-MOVE are for a **store admin using only the screens** (no scripts, no SQL). The
platform operator's part is the weekly recheck, which corrects the new listing's dates once it holds a
reservation. D1 to D4 are fallbacks, and D4 is the only part that needs SQL. Recodes are rare (12 of 6,615
distinct UPCs in the catalog appear under more than one code, measured 2026-10-11), so a manual routine is enough.

> **Status (2026-10-11): D-MOVE is the normal route and has been live on production since 2026-10-11 (PR #173).** It was exercised on
> staging only (an automated run, then a seeded demo that Rick walked through), **not on a real recode.** Watch
> the first real use. D1 to D4 are kept for the one case D-MOVE cannot cover: the new code is not in the catalog
> at all, so it cannot be chosen. An earlier version of this section presented a UI-only repair as the normal
> route; it was not, because the customer Catalog page lists only the **current** catalog month (F173).

### D0. Is it really a recode?
Most "missing" codes are not. An incentive variant (1:25, 1:50 …) just stops being offered after its ordering
window and still ships under the **same** code (F165 § 1.3). Look the title up on **Lunar's retailer site**: the
**same comic listed under a different product code** is a recode; a title that is simply no longer offered is
not, and this section does not apply.
*(Operator shortcut, from the scripts folder: search Lunar's latest export by the title's UPC; the same UPC under
a different `Code` is a recode.)*
```powershell
Select-String -Path "..\recheck\Lunar Available Products*.csv" -Pattern "70985304127601411"
```

### D-MOVE. Move the reservations (use this first)
Ordering → By Distributor has a small **Move reservations…** button under each listing that still has an open
reservation. It moves those reservations to the new listing in one step, in any catalog month. **For a recode,
use it; D1 to D4 below are fallbacks.**
1. Find the OLD listing (search its title or code; the search reaches every catalog month) and click **Move
   reservations…**.
2. The dialog lists listings with the **same UPC in a different month** ("probably the new code"). Pick one, or
   search by title, code or UPC. It only suggests: read the listing it shows (title, code, month, dates) before
   you pick it. Two listings with the same UPC in the **same** month are different products (a paid and a free
   bundle, a pallet and a bundle of five) and are never suggested.
3. The move does **not** change dates. The weekly recheck corrects them once the listing holds a reservation (the
   platform operator runs it; PRH catalogs older than about three months are not rechecked).
4. Tick **"carry the order record"** only after you have confirmed in the Lunar portal that your order carried
   over to the new code. Leave it unticked otherwise. It adds a −N under the old code and a +N under the new
   one; the record is append-only, so a mistake is fixed with another adjustment, never an edit.
5. Click **Move**. Fulfilled reservations stay on the old listing as history.
6. Check: search the new code in By Distributor. The customer should be listed on it, with "Ordered (n)" if you
   ticked the box.

It refuses, in words, when the customer already holds the new listing, when the new listing is withdrawn, or when
the two listings are from different distributors. Nothing is saved when it refuses. **To undo a move, open the
same dialog on the new listing and move the reservation back** (tick the order-record box again if you ticked it
the first time).
**If the dialog finds no listing for the new code**, the code is not in any imported catalog month yet, or you
are searching the wrong distributor. Try the title; if it is still absent, you cannot move yet: use D3 for now
and tell the platform operator both codes so the new one can be imported, then come back to D-MOVE.

### D1. Fallback: can customers still reserve the new code?
*Use D1 to D4 only if D-MOVE cannot find the new listing.*
Search for the new title on the **Catalog** page. The page lists only the **current catalog month**, and the new
code may sit in an older month or may not have been imported yet.
- It **appears**, with a future FOC date: use **Pattern 1** (D2).
- It does **not** appear, or its Reserve button is locked: use **Pattern 2** (D3).

### D2. Pattern 1: the customer can re-reserve the new code (a "second opportunity")
1. **Ordering → By Distributor → the OLD code's row → Rejected by supplier** and confirm. This nets the old
   code to 0 in the order record. The customer's card reads "Rejected by supplier" until step 2 removes it.
2. **Customers → impersonate the customer → My List → Remove** the old card. This is allowed now, because the
   record nets to 0 and nothing arrived.
3. Still impersonating: **Catalog → the new listing → Reserve** the same quantity. (Or let the customer do it.)
4. **Ordering → By Distributor → the NEW code's row → Mark Ordered** for the quantity Lunar holds. With several
   customers, repeat 2 and 3 for each, then do step 4 **once** for the total. Mark Ordered also works on a row found by
   the search box (F174, fixed 2026-10-11). Before that fix it did nothing on a row from another month, so if it ever
   does nothing for you, reach the row with the month selector instead and tell the platform operator.

The new reservation is dated **today**, so the customer's original reservation date is lost. Confirm in the Lunar
portal that your order carried to the new code before you record it.

### D3. Pattern 2: the new code cannot be reserved in the app (older month, or not imported)
This is the usual case so far: both recodes seen landed in an older catalog month. The app cannot move the
reservation, so close the old one honestly and handle the copy yourself.
1. **Write it down outside the app:** the title, the old code, the new code, and the customers' names. The app
   has nowhere to record "the new code is X" (the move in D-MOVE writes a note on the reservation it moves; no
   other screen records it).
2. **Ordering → Order Follow-Up → Never Arrived → the old code → Didn't arrive.** The customer then sees
   "Store is handling this" and does not need to call. *(This button is offered on the Never Arrived panel, so
   the old listing must appear there: its on-sale date must have passed with nothing received. If it is not
   listed yet, use **Rejected by supplier** on By Distributor, or wait until it appears.)*
   Use **Rejected by supplier** instead when Lunar cancelled the old order outright and you want the order
   record netted to 0: the customer then sees that wording and may remove the card.
3. **Place or confirm the order under the new code with Lunar and hold the copy for the customer**, and tell the
   customer yourself. The app cannot track the new code until it appears in a catalog month the app can show.
4. **Tell the platform operator both codes**, so the new code can be brought into the app. Once it is in the
   catalog, D-MOVE can carry the reservation across instead of leaving it closed.

What this does **not** do: it does not transfer the reservation (D-MOVE does, once the new listing is in the
catalog). The old one is closed by the weekly import and sits under "No longer coming"; the order record still
shows the old code as ordered.

### D4. Operator only, fallback: carry the reservation across (SQL)
**Since D-MOVE exists this is a fallback**, for a case the dialog cannot handle. Needed when the customer should
keep the **same reservation** on the new code and D-MOVE cannot be used, as with Hyde Street #14 (repaired this
way on 2026-10-11, before D-MOVE existed): its replacement
sat in the `2026-07` month and Lunar had re-dated the issue (our row said FOC 10/5 and on-sale 10/28; Lunar:
FOC 11/23, in-store 12/23). D-MOVE now moves the reservation and the order record, and the Friday
recheck corrects a listing's dates once it holds a reservation or sits in the current month. The SQL route takes
one guarded SQL transaction in the Supabase SQL Editor: correct the new
listing's dates, repoint the reservation, and add a −1 and a +1 adjustment to the order record, all inside a
single `DO` block that rolls back if any guard does not match exactly one row (the F122 repair method,
`docs/technical-reference.md` § 13 F122, "Repair applied 2026-08-10"). Do not edit or delete order-record
rows; they are append-only. The 2026-10-11 version is the template; have it drafted for the new ids rather than
adapting it by hand. Afterwards: By Distributor shows the old code with no reservations and the new code
"Ordered", the customer's My List shows the **new** date under Upcoming Arrivals, and the next Friday recheck
lists nothing for the title.

---

## RUN E — Place the monthly distributor order (12 steps)

**What this does.** It turns the month's customer reservations into two orders, one for Lunar and
one for PRH, places them on each distributor's website, and records in the app what each
distributor accepted. Everything after that depends on this record: customers see "Order placed"
on My List from it, and the Order Follow-Up panel uses it to warn about titles nobody ordered.

**How it works, in one paragraph.** The app does not send anything to a distributor. It builds a
small text file for each distributor, one line per title in the form `code,quantity`. You paste
those lines into the distributor's own website and submit there. Then you come back to the app
and record what the distributor actually accepted. Downloading the file is **not** recording the
order: only Step E9 records it.

**You need:** the store admin login for `https://pulllist.app/`, the **Lunar** and **PRH**
retailer website logins, a computer (the dashboard is built for a full-size screen), and about an
hour. No scripts, no SQL.

**When.** After the customer **Order Deadline** has passed (shown in the dashboard header), so
customers have finished reserving (switch to **Ordering** mode to see it), and before the **FOC dates** of the cycles you are ordering.
Do it before Run A's new-month import: that import closes this month. If an FOC date in this
month falls *before* the Order Deadline, that title cannot wait for this run; see Step E1.

### E1. Clear anything urgent first (Order Follow-Up)
Dashboard → **Customers** mode. Above the tabs is the **Order Follow-Up** panel (it hides itself
when there is nothing to show). Two groups matter for ordering:
- **At risk**: reserved titles whose FOC date comes before this run will reach them. Order these
  now, as single **ad-hoc** orders on the distributor's website. Then record each one: **Ordering**
  mode → **All Orders** → find the title (type in the search box) → **Mark Ordered** in its Status
  column → quantity you ordered, Order type **Ad-hoc**, today's date → **Save**. Ad-hoc orders are
  then left out of the monthly file automatically, so they are not ordered twice.
- **Backordered**: the FOC date passed and nothing was ordered. It can usually still be ordered
  but may not arrive. Decide per title with the store; record any order you place the same way.

The panel's **Never Arrived** group is about deliveries, not ordering. Leave it for the weekly work.

### E2. Type in the paper orders
Customers who ordered on the printed catalog in the store need their reservations entered, or
they will not be in the order. Dashboard → **Ordering** mode → **Paper Orders** tab.
1. A customer not on the system yet: type their name under **Add Paper Customer** → **Add**. No
   email is sent and they never log in.
2. Under **Add Title to Order**, search the title (title, series or writer) and click the right
   result. It appears under **Pending Order**. Check the distributor badge (Lunar or PRH) and the
   price to be sure it is the right edition and cover.
3. On that title, use **+ Add customer…** to pick each customer who wants it, and set each
   customer's quantity in the small box beside their name.
4. Repeat for every title on the paper forms, then click **Submit Reservations**.
5. Check: **All Orders** → search a title you entered; the paper customer is listed on it.

### E3. Add the store's own shelf copies
Copies for the store's shelves are reserved under the store admin account like any customer's.
1. Signed in as the store admin, open **My List** (top menu) → **📦 Suggest Shelf Order**.
2. A preview lists each title with a **Suggested Qty**, worked out from customer demand. Read it,
   then click **Apply**. It only adds titles or raises quantities; it never lowers or removes
   anything, so it is safe to run again.
3. Adjust with the quantity controls on My List, or **Remove** lines the store does not want.

Titles past their FOC date are never suggested.

### E4. Turn Maintenance Mode ON
Dashboard, **Ordering** mode, header → **Maintenance Mode** switch → ON (the label beside it reads
ON). Customers now see a holding page, so no one can add
or cancel a reservation while you build and place the order. This matters: the record you save in
Step E9 is built from the reservations as they stand at that moment, and it must match the file you
submitted.

### E5. Review the month's orders
**Ordering** mode → **All Orders** tab. Make sure **Catalog month** at the top reads the current
month (marked "(current)"). If an older month is selected, the order buttons are greyed out and a
yellow note says so; switch back to the current month.

The page lists every reserved title, grouped under LUNAR DISTRIBUTION and PRH. The **Status**
column on each title shows its order state: **Mark Ordered** (nothing ordered yet), **Add (n of m)**
(some ordered, more reserved), **Over (n of m)** (more ordered than reserved), **Ordered (n)**
(covered). A small amber badge such as **⚠ 1:25** means the distributor rations that title (one
copy per 25 ordinary copies ordered); it may come back reduced or rejected.

Read down the list for anything odd (a huge quantity, a duplicate title) before going on. To fix a
customer's reservation, go to **Customers** mode → **Accounts**, find them and click
**Manage**; you now see the site as that customer and can change their list. Leave their view from
the banner at the top of the screen when done.

### E6. Build the Lunar order file
Click **↓ Lunar Order Sheet** (above the tabs, in Ordering mode). The **Lunar Order Builder**
window opens.
1. **ORDER CYCLE (FOC DATE)** lists each FOC date with how many titles and copies it holds. The
   nearest upcoming one is ticked for you. Tick every cycle you are ordering now (usually the
   upcoming FOC dates this month's order covers; **Select all** ticks every upcoming one).
   - Cycles whose FOC already passed are hidden under a red **⚠ … FOC already passed** line and are
     never ticked by Select all. Tick one only if you mean to backorder it.
   - "· N restricted" on a cycle counts its rationed titles; they are still included.
2. **⚠ ALREADY ORDERED — N need a call**: titles already partly on order (for example an earlier
   ad-hoc order). Each shows how many are reserved and how many are already on order, and offers
   the difference. Leave the box ticked to include that quantity, change the number, or untick to
   leave it out. A line marked **over-ordered** already has more on order than customers reserved.
   Titles already fully covered are folded away under a grey line: nothing to decide.
3. **HELD BACK** lists what is **not** in this file and why, so nothing goes missing silently:
   - **⛔ Withdrawn by the distributor**: cannot be ordered.
   - **🔴 Backordered** and **🟡 At risk**: see Step E1.
   - Grey, folded lines (**Outside selected cycle**, **Ad-hoc ordered**, **Rejected by
     distributor**): correctly left out. "Outside selected cycle" is usually the biggest; those
     titles belong to a later cycle you have not ticked.
4. Bottom left reads **N titles ready to export**. When it looks right, click
   **Generate & Download**. A file named like `lunar-order-2026-11-02.txt` downloads.

**Do not click "Record submitted order" yet.** You have not ordered anything; you have a file.
Leave this window open while you do Step E7, so your cycle choices and any quantities you changed
are still there in Step E9.

### E7. Place the Lunar order on Lunar's website
1. Open the downloaded `.txt` file in Notepad. Each line is `code,quantity`.
2. Sign in to Lunar's retailer website, open its order entry that accepts pasted lines of code and
   quantity, paste every line, and submit the order there.
3. Before leaving the site, note any title Lunar refused or reduced, and by how much. Lunar often
   reports rejections only after it processes the order; that is handled in Step E11.

### E8. Build the PRH order file and place it
Same as E6 and E7 with **↓ PRH Order Sheet** and PRH's website (file `prh-order-YYYY-MM-DD.txt`;
PRH lines use the ISBN where there is one). PRH tends to reject rationed titles at submission, so
check the **⚠** titles first when you read PRH's confirmation.

Do E9 for one distributor before starting the other, or keep two separate notes; the windows look
alike.

### E9. Record what each distributor accepted
In the Order Builder window for that distributor, click **Record submitted order →**.
1. It lists exactly the titles in the file you submitted, with the quantities you sent. Rationed
   titles are listed first.
2. **Untick any title the distributor rejected.** That records it as rejected (quantity 0), not
   ordered, and the customer will see "Rejected by supplier" on their list.
3. **Change the quantity** of any title the distributor filled only partly.
4. For **Lunar**, if you do not know of any rejection yet, record the order exactly as submitted;
   do not untick a title just because it has a ⚠ badge.
5. Click **Record order**. A green message confirms ("Recorded N titles on the order ledger", or
   "Recorded N ordered, M rejected"). The window closes.

**If you closed the window before this step:** open it again with the same Order Sheet button,
tick **exactly the same cycles** as before, and re-enter any quantity you changed under "Already
ordered" (those reset when the window reopens). Then click **Record submitted order →**. Compare
the list with the `.txt` file you pasted: they must match. If a title appears that you did not
submit, untick it; if one you submitted is missing, record it with **Mark Ordered** (Order type
**Monthly cycle**).

Check: on **All Orders**, the titles you ordered now read **Ordered (n)**.

### E10. Print the report for the store
**All Orders** → **Print / Save Report**. Print it, or save it as a PDF, and give it to the store.
For the in-store paper catalog customers write orders on: **Paper Orders** → **Print Catalog**
(about 50 pages; print it after the new month is imported in Run A, so it shows the new titles).

### E11. Fix rejections you learn about later
Distributors (Lunar especially) can reject or cut a title days after you submitted. When that
happens: **All Orders** → search the title →
- Refused completely: **Rejected by supplier** in its Status column → confirm. The dialog says
  exactly what will change; the customer's list shows "Rejected by supplier" straight away.
- Filled only partly: **Mark Ordered** → Order type **Adjustment (correction)** → enter the
  difference as a negative number (for example `-2` if two of five were cut) → **Save**.

The order record is never edited, only added to, so a mistake is fixed by another correction, not
by deleting anything. The Status button stays usable until 7 days after the title is delivered.

### E12. Turn Maintenance Mode OFF, or carry on into Run A
- If the new catalog is being loaded now, **leave Maintenance Mode on** and go to **Run A**,
  Step 2 (Step 1 is already done).
- Otherwise, dashboard, **Ordering** mode, header → **Maintenance Mode** switch → OFF.

When Run A's new-month import runs later, it lists any reserved titles from the closing month that
have **no order recorded** and asks `Record these as ordered?`. If Run E was done fully, that list
should hold only titles you deliberately did not order. **Do not just press Enter**: Enter records
every listed title as ordered. Type `none`, or the numbers of the titles you did not order (see
**Answering the prompts** below).

**When something goes wrong**

| Symptom | What to do |
|---|---|
| The two Order Sheet buttons are greyed out | All Orders has an older Catalog month selected. Switch it back to the current month |
| "No unfulfilled … reservations with an FOC date this month" | Nothing for that distributor is waiting to be ordered. Check the Catalog month and the HELD BACK lines |
| "No … reservations selected for export" when downloading | No cycle is ticked, or every title in the ticked cycles is already ordered or held back |
| "Ledger write failed: …" when recording | Nothing was recorded. Check your internet connection, reload the page, reopen the builder with the same cycles and record again |
| You recorded the wrong quantity | Correct it with Step E11 (an Adjustment). Do not record the whole order a second time |
| Mark Ordered does nothing | Reload the page. If it still does nothing, choose the title's catalog month in the Catalog month selector, then try again, and tell the platform operator |

---

## Answering the prompts (Run A Step 5 / Run B Step 2)

Up to seven questions. Three are conditional guards that appear only when something looks wrong.
The shipment question is skipped when shipment files are given on the command line.

| Prompt | Answer |
|---|---|
| `Catalog month detected: YYYY-MM` | Enter to accept, or **type the correct `YYYY-MM`**. If it detected nothing you must type one — there is no default. |
| `CATALOG MONTH MISMATCH … type "yes"` | **STOP.** The two CSVs look like different months. Ctrl-C and check the files. |
| `LUNAR ITEM CODE / CONFIRMED MONTH MISMATCH … type "yes"` | **STOP.** The Lunar codes' embedded month disagrees with what you typed. This is the exact shape of a past incident that mislabelled a whole file. |
| `CROSS-MONTH COLLISION … type "yes"` | **STOP.** Signature of a file already imported once under the wrong month. |
| `Record these as ordered?` (new month only) | Enter = confirm all. `none` = skip all. Or comma-separated numbers to **exclude** those. |
| `Do you have shipment invoices to import this run? (y/n)` | Only asked when no shipment files were on the command line. `n` for a catalog-only run. `y` then **one path per line** (every delivery for the week), a blank line to finish. |
| `Send catalog notification email to all customers? (y/n)` | `y` only on a genuine new-month refresh. **`n`** on shipment runs and older-month backfills. |

**The three "type yes to continue" guards are stop signs, not speed bumps.** Each one exists
because a real import went wrong in exactly that way. Answering `yes` past one without checking
the files is how a whole month lands under the wrong `catalog_month`.

One warning is not a question: if the confirmed month is more than one month from the calendar
month, the script prints `"YYYY-MM" is N months in the past/future … Double-check this is
intended` and carries on. Read it.

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
| Every run | Clear withdrawal flags for titles that reappeared. **It never sets one** (F165 S1, 2026-10-04) |
| New month only | Archive past reservations into `reservation_history` |
| New month only | Purge stale unreserved catalog rows |
| New month only | Remove items the distributor dropped |
| New month only | Prompt to confirm the closing cycle's open orders |
| New month only | **Clear the order deadline** (you re-set it at Step 8) |
| New / same month | Auto-reserve subscribers' standard covers |
| Shipment supplied | Import shipment rows, dropping Lunar free promos (`Retail` 0, or `Total` / `Discounted Price` exactly 0; F172). **Publishes nothing**: the newsletter is built by the `weekly-pull-feed` Tuesday workflow (F135 S4, 2026-10-13) |
| Every run | Purge `usage_events` older than 90 days |
| Every run | Report about-to-be-fulfilled titles with no arrival evidence, then auto-fulfill past-on-sale preorders (anything with no arrival evidence is held back 14 days) |

---

## Re-run safety

Re-running is safe. Specifically:
- **Catalog upsert** merges in place on `(tenant_id, item_code, distributor, catalog_month)` —
  reservation links survive.
- **Auto-reserve** detects existing reservations and skips them.
- **New-month sequence** fires only when the import month is *greater* than what's in the DB.
- **Shipment import** is safe to re-run for the same week — **with all of that week's files.** A
  later run holding only some of them replaces a shared title's stored quantity instead of adding
  to it (Run B, Step 1).

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
| `❌ Shipment file not found` or `❌ … repeats …`, then `Skipping shipment import` | A path is wrong, or two paths are the same delivery. **Nothing was read or written for the shipment.** Fix the list and run again with every file for the week |
| `⚠️ … contributed 0 rows` | That file parsed to nothing. Usually the wrong download, or a summary rather than the invoice. The other files still loaded, so re-run with the right file **and** the rest of the week's files |
| Tuesday's newsletter is empty, stale or did not send | Not an import problem any more: the import publishes nothing (F135 S4). Check that week's shipment rows landed (Run B), then the `weekly-pull-feed` repo's Actions log (the Monday preflight and the Tuesday send). *(`Pull-feed publish failed` and `build-pull-feed.js` in this folder are gone since 2026-10-13.)* |
| `No .csv files in …\recheck` or `Skipped (unrecognised header)` (`check-dates.js`) | The folder is empty, or the file is not a Lunar All Products export or a PRH master-data file. Re-download it |
| Wrong catalog month imported | Re-import that month's real file under the correct month; see `monthly-catalog-refresh.md` |

---

## Before handing this to a second operator

They need all of these, and two of them cannot be recovered from any repo (F131):

1. The `scripts` working tree (private repo `comic-preorder-scripts`)
2. **`.env`** — local-only, in no repo. Variable names are listed in `.env.example`
3. **Lunar and PRH retailer portal logins** — the irreplaceable one
4. Admin access to the app, for Maintenance Mode and Order Deadline
5. Knowledge that CSVs go in `catalogs\`, one level above `scripts\`
