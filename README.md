# BookStop Comics — Pull List Pre-Order System

A monthly comic book pre-order system for Ray & Judy's Book Stop, Rockaway NJ.
Customers log in to browse the current Lunar and PRH catalog and reserve titles
before the Final Order Cutoff (FOC) deadline. The admin panel manages customers,
views all reservations, and exports distributor order sheets.

Live site: [mrcyberrick.us/comic-preorder](https://mrcyberrick.us/comic-preorder)

---

## Stack

| Layer | Technology |
|---|---|
| Hosting | GitHub Pages |
| Database + Auth | Supabase (PostgreSQL + Row Level Security) |
| Email | MailerSend |
| Frontend | Vanilla HTML / CSS / JS |

---

## Site Pages

| File | Description |
|---|---|
| `index.html` | Login page |
| `catalog.html` | Browse current month's Lunar + PRH titles, reserve with one click |
| `mylist.html` | Customer's personal pull list with running total and CSV export |
| `admin.html` | Admin dashboard — reservations by customer, by distributor, order sheet exports, invite customers, maintenance mode |
| `forgot-password.html` | Password reset flow |
| `app.js` | Shared Supabase client, auth, and all API logic |
| `style.css` | Dark comic shop aesthetic, fully responsive |

---

## Supabase Edge Functions

| Function | Purpose |
|---|---|
| `invite-customer` | Creates auth account and sends branded invite email via MailerSend |
| `notify-customers` | Sends catalog live notification to all customers after monthly import |
| `reset-password` | Handles branded password reset emails |

---

## Monthly Catalog Refresh

Each month new CSV files are received from Lunar Distribution and PRH.
A local Node.js script normalizes both files and imports them into Supabase.

See [`docs/monthly-catalog-refresh.md`](docs/monthly-catalog-refresh.md) for the full step-by-step workflow.

**Quick reference:**
```bash
cd catalogs/scripts
node .\import.js "..\Lunar_Product_Data_MMYY.csv" "..\YYYY_MM_PRH_metadata_full_active.csv"
```

The script handles normalization, Supabase import, and customer email notification in one run.

---

## Database Schema

Full schema including all tables, indexes, RLS policies, and views:
[`docs/schema.sql`](docs/schema.sql)

**Tables:**
- `catalog` — unified Lunar + PRH items, replaced monthly
- `user_profiles` — extends Supabase auth with name, admin flag, notes
- `preorders` — one row per customer reservation, supports quantity
- `app_settings` — key/value store for maintenance mode and site config

---

## Security

- All tables have Row Level Security (RLS) enabled
- Customers can only read the catalog and manage their own preorders
- Admin functions are enforced server-side via Edge Functions
- The anon key in `app.js` is intentionally public — RLS is the access control layer
- Service role key and distributor CSV files are never committed to this repo

---

## Local Scripts (not in repo)

These files live on the admin's local machine only and are excluded via `.gitignore`:

| File | Purpose |
|---|---|
| `catalogs/scripts/import.js` | Monthly catalog normalizer and Supabase importer |
| `catalogs/import-catalog.ps1` | PowerShell backup import script |

---

## Contact

Rick Sedivec
mrcyberrick.us
