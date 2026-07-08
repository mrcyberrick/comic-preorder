# PULLLIST — Comic Pre-Order System

A web-based pre-order management system for **Ray & Judy's Book Stop**, Rockaway NJ.
Customers browse the monthly comic catalog, reserve titles, and manage their pull list.
The store uses the admin dashboard to track orders and export distributor order sheets.
Multi-tenant under the hood (Phases 1–5 migration program) — one founding tenant live.

**Production**: https://pulllist.app/
**Staging**: https://staging.pulllist.pages.dev/

---

## Features

- Monthly catalog import from Lunar Distribution and PRH (Penguin Random House)
- Customer browse, search, and reserve — with UPC/ISBN/item-code search support
- Pull list management with quantity adjustments, FOC locking, and CSV export
- Series subscriptions — auto-reserve standard covers each month
- This Week's Arrivals — Mon–Sun week view for customers and admin bagging
- Upcoming Arrivals — multi-month forward view on customer pull list
- Admin dashboard — by customer, by distributor, this week, all reservations,
  subscriptions, top series, pending approvals, paper orders
- Paper customers — admin-managed accounts for walk-in/phone customers, with
  claim/merge into real accounts
- Customer invite + self-registration (MailerLite webhook) with admin approval
- Per-tenant branding and slug-based tenant resolution
- Maintenance mode for catalog refresh downtime
- Print/PDF export for order sheets, bagging lists, and pull lists
- Mobile-responsive with hamburger nav

---

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Vanilla HTML, CSS, JavaScript (no build step) |
| Backend | Supabase (PostgreSQL, Auth, RLS, Edge Functions) |
| Hosting | Cloudflare Pages (static; auto-deploys `main` → prod, `staging` → preview) |
| Email | MailerSend via Supabase Edge Functions; MailerLite signup webhook |
| Import | Node.js script (runs locally, not in this repo) |

---

## Repository Structure

```
/
  index.html            ← login + invite/recovery landing
  catalog.html          ← monthly catalog browse & reserve
  mylist.html           ← customer pull list
  arrivals.html         ← this week's arrivals
  subscriptions.html    ← series subscription management
  admin.html            ← admin dashboard
  analytics.html        ← admin analytics
  forgot-password.html  ← password reset landing
  app.js                ← shared app logic & Supabase API objects
  style.css             ← all styles
  config.js             ← per-environment values (see below)
  _headers              ← Cloudflare Pages cache/security headers
  _redirects            ← legacy URL redirects
  supabase/functions/   ← all Edge Functions (deployed to Supabase)
  CLAUDE.md             ← AI assistant project instructions & workflow contract
  docs/
    technical-reference.md        ← canonical schema, RLS, findings register
    monthly-catalog-refresh.md    ← monthly import SOP
    phase-*.md                    ← migration phase plans & runbooks
```

---

## config.js — tracked per branch, never merged

`config.js` **is committed**, with different values on each branch: `main`
holds the production Supabase URL/anon key and founding-tenant identity;
`staging` holds the staging equivalents. The Supabase **anon key is public by
design** — RLS is the security boundary, not key secrecy.

Rules:
- Never merge `config.js` between branches. The promotion workflow runs
  `git checkout main -- config.js` to preserve prod values (see CLAUDE.md).
- Service-role keys are different: they bypass RLS and live only in the local
  scripts folder, never in this repo.

---

## Setup (new environment)

### Prerequisites
- Node.js v20+ (for the import script)
- A Supabase project with the schema from `docs/technical-reference.md`

### Database
Apply the schema and RLS policies documented in `docs/technical-reference.md`
via the Supabase SQL Editor, and deploy the Edge Functions in
`supabase/functions/` with the secrets listed in that doc (§ 11.2).

### Import Script
The monthly import script lives outside the repo:
```
C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts\
  import.js         ← production
  import-staging.js ← staging
```
Install dependencies once: `npm install` inside the scripts folder.

---

## Monthly Catalog Refresh

See `docs/monthly-catalog-refresh.md` for the step-by-step guide.

Quick summary — **no manual SQL; the script automates month transition**:
1. Enable Maintenance Mode in the admin panel
2. Drop the new CSV files in the catalogs folder
3. Run `node .\import.js "..\Lunar_....csv" "..\YYYY_MM_PRH_....csv"`
   (archives history, purges stale rows, upserts, auto-reserves, prompts
   for notifications)
4. Verify in Supabase SQL Editor
5. Set the new Order Deadline
6. Disable Maintenance Mode

---

## Deployment

Authoritative workflow (including the F59 merge-base assertions): **CLAUDE.md
§ Standard Deployment Workflow**. Short version:

### Staging
```powershell
git checkout staging
# merge feature branch --ff-only, run local smoke suite
git push origin staging
# Cloudflare Pages auto-deploys https://staging.pulllist.pages.dev/
```

### Production
```powershell
git checkout main
git pull origin main
git merge staging --no-commit --no-ff
git checkout main -- config.js   # preserve prod values
git commit -m "type: description"
git checkout -b feat/description-prod
git push origin feat/description-prod
# Open PR → main. Verify config.js is NOT in the diff before merging.
# Cloudflare Pages auto-deploys https://pulllist.app/
```

---

## Development Notes

- No build step — edit HTML/CSS/JS files directly
- All pages share `app.js` and `style.css`; script load order everywhere:
  Supabase bundle → `config.js` → `app.js` → page script
- Nav and footer blocks must stay in sync across all pages — see `CLAUDE.md`
- Never use `toISOString()` for date display — local date parts only (F28)
- Supabase `.range()` returns 416 on empty result sets — count-first approach
- Smoke tests: local Playwright suite (see `CLAUDE.md` § Smoke Test Suite);
  staging-only by design

---

## Contact

Ray & Judy's Book Stop · Rockaway, NJ · 973-586-9182
