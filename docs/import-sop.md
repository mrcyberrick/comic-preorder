# Import SOP — Catalog & Shipment Data

**STATUS:** REFERENCE · created 2026-09-06 · updated 2026-10-09 (any number of shipment files per run; F165 S1 retired the automatic withdrawal mark; F165 S2 report and the recheck-folder rules; later the same day: the F164 pre-import check, handling for the F122 "PINNED" report, and recovery from a dead feed token) · earlier: 2026-09-18 (F157 zero-row guard; F159 frozen-catalog warning)
**Audience:** whoever runs the import. Assumes portal logins and a working `.env` (see F131).
**Scope:** the short, followable version. The *why* behind each step, and every warning-sign
narrative, lives in `docs/monthly-catalog-refresh.md` — that file stays canonical for
**reasoning**; this file is canonical for **sequence**.
**Last checked against the scripts:** scripts repo `main` at `3ef4b89` (read 2026-10-09). If
`git log` in the scripts folder shows newer commits to `import.js`, `import-staging.js` or
`check-dates.js`, re-check the prompts table and the Run C report sections before trusting this file.

---

## The three runs (and one procedure for when a product code changes)

There is no single "import." There are three separate operator runs on different clocks, plus
**Run D**, a procedure you start when the distributor changes a product code.
**None of them is scheduled — every one is started by a human.**

| # | Run | When | Script | Manual steps |
|---|---|---|---|---|
| A | Monthly catalog refresh | Once a month, when both new CSVs land | `import.js` | **9** |
| B | Weekly shipment import | Every shipment week, once its invoices are out (lately Fridays) and **before the Tuesday newsletter send (22:00 UTC)** | `import.js` | **5** (7 if ad-hoc) |
| C | Weekly date re-check | Fri or Sat | `check-dates.js` | **3** |
| D | A product code changed (Lunar recode) | When Run C or the Never Arrived panel shows a reserved code that the distributor replaced | store admin: screens only (D0 to D3); operator: one SQL block to carry the reservation across (D4) | **4 per customer** (UI) |

**Everything runs from one folder:**

```powershell
cd C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts
```

CSV files go in the folder **above** that one (`..\catalogs\`).
`import.js` = production. `import-staging.js` = staging. They take identical arguments.

**Flags worth knowing:**
- `--no-write` — dry run (`import.js` and `check-dates.js`). Prints what it *would* write, changes
  nothing. Use it whenever unsure. Two limits: `import.js` will not tell you which week the feed
  would publish, and `check-dates.js` still records what it saw in its state file (see Run C).
- `--skip-autoreserve` — `import.js` only. Skips subscriber auto-reserve. Pass it on any
  older-month re-import (Run A, Step 3); the script also switches it on by itself when the month
  is older than the database's.
- `--staging` — `check-dates.js` only. Points it at staging. It still needs the **production**
  variables in `.env`, because it loads `import.js`.
- `--include-unreserved` — `check-dates.js` only. Also checks, and corrects, dates on
  **unreserved** current-month titles. Off by default.

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
one tenant; 2026-10 all one tenant; a second tenant held only 2 rows, in 2026-06, which is harmless).
Staging holds `demoshop` rows for 2026-09, which is why a 2026-10 staging import cannot misfire.

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

### 3. Run the import: the two catalog files, then every shipment file
```powershell
node .\import.js "..\Lunar_Product_Data_1026.csv" "..\2026_10_PRH_metadata_full_active.csv" "..\Shipment-detail-LUNAR.csv" "..\Shipment-detail-PRH.csv"
```
That is the 2026-10-09 week as an example: substitute the current month's two catalog files, and
add one more quoted path for each extra delivery.

Confirm the month at the prompt (it is the **current** month — same month as the DB, so only an
upsert refresh runs). Answer **n** to the notification email.

With the shipment files on the command line, the script does **not** ask "Do you have shipment
invoices?". Leave them off and it asks, then takes one path per line until a blank line.

**All-or-nothing, and it says so.** If any listed shipment file is missing, or one repeats another
(same path, or the same delivery/shipment number), the script prints a `❌` line naming the file and
skips the **whole** shipment import: nothing is read or written, and the feed is **not** published.
The catalog refresh before it still happened. Fix the list and run again with the full set; re-running
files that already loaded is safe. A file that yields no rows is called out by name
(`contributed 0 rows`); a file that is neither format prints `Unrecognized shipment format`.

> **The F157 catalog check runs on shipment weeks too.** You are passing catalog files, so if
> one of them is wrong the run aborts **before the shipment lands**. That is intended — but it
> means a bad catalog file delays the shipment import, so reuse the current month's files you
> already imported rather than re-downloading on the day.

### 4. Check the feed line
- Normal run: `Feed week: YYYY-MM-DD (from ...)` — confirm that date is the week you mean.
- Ad-hoc run: confirm you see `GITHUB_TOKEN_PULL_FEED missing from .env — skipping feed
  publish.` That warning is how you know Step 2 worked.
- If you see `Pull-feed publish failed (import is unaffected)`: the shipment landed but the feed did
  not, so Tuesday's newsletter would go out stale. Re-publish by hand (it targets the latest loaded
  shipment; add `--week=YYYY-MM-DD` only if that is not the week you mean):
  ```powershell
  node .\build-pull-feed.js --publish
  ```
- If the failure says `HTTP 401 ... Bad credentials`, **republishing will fail the same way**: the
  GitHub token in `.env` (`GITHUB_TOKEN_PULL_FEED`) is dead (expired or revoked; seen on 2026-10-09). Create a new fine-grained token scoped to **contents: read and write on
  `weekly-pull-feed` only**, put it in `.env` in place of the old value, then run the command above.
  Do this before **Tuesday 22:00 UTC**; the live feed's `pull-feed-generated` stamp is what the
  newsletter's stale guard reads. Write down the expiry date you choose so the next lapse is not a surprise.
- If the publish fails with `HTTP 403 ... Resource not accessible by personal access token`, the token
  is alive but **cannot write**: its **Contents** permission is Read-only. A read-only token passes
  every read check (a repo read, the same `git/ref` call as the publish's first step), so a green
  check of the token does **not** prove it can publish; only the publish does. Nothing is written when
  this happens (the failure comes before any commit). Edit the token (Settings → Developer settings →
  Fine-grained tokens → the token → Edit → Contents: **Read and write** → Update), which keeps the
  same value, then re-run `node .\build-pull-feed.js --publish`. After a publish, confirm it was **one**
  new commit on `weekly-pull-feed` and that the live `pull-feed-generated` stamp moved.

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
history lives in it.

### 3. Read the report, then answer the apply prompt
Read these in order. Only the first three groups are written by the apply prompt; the rest are for you.

| Section | What it means | What you do |
|---|---|---|
| `⚠️ STRANDED` | Reserved title in an **older** month whose date moved. `← ALREADY HIDDEN FROM CUSTOMERS` means the customer cannot see it at all | Applied by the prompt below — read these first |
| `N reserved title(s) in the current month … changed date`, `N title(s) changed FOC date only` | Ordinary revisions | Applied by the prompt below |
| `N UNRESERVED title(s) … changed date` | Only appears with `--include-unreserved` | Applied by the prompt below |
| `🚨 N FULFILLED reservation(s) with no arrival judgement …` (F158) | Closed within the last 14 days, so customers already see "Order placed", with nothing showing it arrived. Nothing else catches these | **Report only.** Each needs a human decision |
| `⛔ N reserved title(s) the distributor shows as CANCELLED / no longer sold` | Lunar still lists the title but with a **placeholder** in-store date before 2000 (usually 1/1/1901, FOC 1/1/1900; the title often ends "Cancelled"). The script never writes that as a date | **Report only.** See below |
| `N reserved code(s) absent from this week's exports`, then `>> N … PAST on-sale with NO shipment evidence` | "Catalog not pulled" is no signal. The `>>` list is the F155 shape: nothing can correct it automatically | **Report only.** Look the listed titles up by hand |
| `🔎 WITHDRAWAL CANDIDATES (F165 S2, report only)` | Titles absent from their **own** source on two runs, on different dates | **Report only.** See below |
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

There is no "Withdrawn" mark to set; that is F165 S3 and is not built. A title Lunar drops from
the export altogether, rather than re-dating it, shows up under withdrawal candidates instead. That
is how BUFFY THE VAMPIRE SLAYER #2 CVR A (shown as Cancelled, 1/1/1901 on Lunar's site, 2026-10-11)
appeared, and it was already marked Didn't arrive.

**Withdrawal candidates.** Nothing marks a title withdrawn any more (F165 S1), and this section
writes nothing. Absence is evidence, not proof: a withdrawn title and one whose allocation merely
closed look the same in these files. Check **each** candidate on the distributor's site and record
the true/false split — that is gate V5 in `docs/f165-withdrawal-detection-redesign.md` § 7, and it
decides whether the confirm-to-mark step (S3) is ever built. A title is only listed after it is
absent on two runs on **different dates**, so the first run that has this section records first
sightings (`N absent for the first time`) and can list nothing; the second, on a later date, is the
first that can.

**The apply prompt** appears only if there is something to write (otherwise `No date corrections
needed`):

`Apply N date correction(s) to PRODUCTION? (y/n)`

Before it asks, the script writes the before-state to `check-dates-log-YYYY-MM-DD.json` in the
scripts folder (exact revert data; written for `--no-write` too). After `y` it re-reads the rows
and prints `Done. N/N confirmed by an independent re-read`; `VERIFICATION FAILED` means stop and
look. **Re-run this after any older-month import** — re-importing a month restores whatever its file says.

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

**Who does what.** D0 to D3 are for a **store admin using only the screens** (no scripts, no SQL). D4 is for
the **platform operator** and is the only part that needs SQL. Recodes are rare (12 of 6,615 distinct UPCs
in the catalog appear under more than one code, measured 2026-10-11), so a manual routine is enough.

> **Status: written from what the screens and code do (2026-10-11); NOT rehearsed end to end.** Watch the
> first real use. An earlier version of this section presented a UI-only repair as the normal route; it is
> not, because the customer Catalog page lists only the **current** catalog month (F173).

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

### D1. Can customers still reserve the new code?
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
   customers, repeat 2 and 3 for each, then do step 4 **once** for the total.

The new reservation is dated **today**, so the customer's original reservation date is lost. Confirm in the Lunar
portal that your order carried to the new code before you record it.

### D3. Pattern 2: the new code cannot be reserved in the app (older month, or not imported)
This is the usual case so far: both recodes seen landed in an older catalog month. The app cannot move the
reservation, so close the old one honestly and handle the copy yourself.
1. **Write it down outside the app:** the title, the old code, the new code, and the customers' names. The app
   has nowhere to record "the new code is X" (the database has a `notes` column on reservations but no screen
   writes it; F173).
2. **Ordering → Order Follow-Up → Never Arrived → the old code → Didn't arrive.** The customer then sees
   "Store is handling this" and does not need to call. *(This button is offered on the Never Arrived panel, so
   the old listing must appear there: its on-sale date must have passed with nothing received. If it is not
   listed yet, use **Rejected by supplier** on By Distributor, or wait until it appears.)*
   Use **Rejected by supplier** instead when Lunar cancelled the old order outright and you want the order
   record netted to 0: the customer then sees that wording and may remove the card.
3. **Place or confirm the order under the new code with Lunar and hold the copy for the customer**, and tell the
   customer yourself. The app cannot track the new code until it appears in a catalog month the app can show.
4. **Tell the platform operator both codes**, so the new code can be brought into the app and, if you want the
   reservation carried across rather than closed, repaired (D4).

What this does **not** do: it does not transfer the reservation. The old one is closed by the weekly import and
sits under "No longer coming"; the order record still shows the old code as ordered.

### D4. Operator only: carry the reservation across (SQL)
Needed when the customer should keep the **same reservation** on the new code and the new listing is not
reservable in the app (an older catalog month, stale dates, or both), as with Hyde Street #14: its replacement
sat in the `2026-07` month and Lunar had re-dated the issue (our row said FOC 10/5 and on-sale 10/28; Lunar:
FOC 11/23, in-store 12/23). **No screen moves a reservation or edits a listing's dates**, and the Friday
recheck only corrects a listing that already holds a reservation or sits in the current month. Until a manual
control exists (F173), this takes one guarded SQL transaction in the Supabase SQL Editor: correct the new
listing's dates, repoint the reservation, and add a −1 and a +1 adjustment to the order record, all inside a
single `DO` block that rolls back if any guard does not match exactly one row (the F122 repair method,
`docs/technical-reference.md` § 13 F122, "Repair applied 2026-08-10"). Do not edit or delete order-record
rows; they are append-only. The 2026-10-11 version is the template; have it drafted for the new ids rather than
adapting it by hand. Afterwards: By Distributor shows the old code with no reservations and the new code
"Ordered", the customer's My List shows the **new** date under Upcoming Arrivals, and the next Friday recheck
lists nothing for the title.

---

## Answering the prompts (Run A Step 5 / Run B Step 3)

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
| Shipment supplied | Import shipment rows, then publish the weekly pull feed (skipped with a warning if `GITHUB_TOKEN_PULL_FEED` is absent, or if the shipment import was skipped) |
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
| `❌ Shipment file not found` or `❌ … repeats …`, then `Skipping shipment import` | A path is wrong, or two paths are the same delivery. **Nothing was read or written for the shipment, and the feed was not published.** Fix the list and run again with every file for the week |
| `⚠️ … contributed 0 rows` | That file parsed to nothing. Usually the wrong download, or a summary rather than the invoice. The other files still loaded, so re-run with the right file **and** the rest of the week's files |
| `Pull-feed publish failed` | The shipment landed; the feed did not. Run `node .\build-pull-feed.js --publish` (Run B, Step 4). If the message says `HTTP 401 ... Bad credentials`, the token is dead: replace it first (Run B, Step 4) |
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
