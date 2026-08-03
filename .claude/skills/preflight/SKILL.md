---
name: preflight
description: Verify the environment is ready before any deployment or runbook session — git branch, gh CLI auth, node, scripts .env vars, Playwright suite, OneDrive script blocks. Run at the start of every execution session.
---

# /preflight — Environment readiness check

Run every check below, then print a single PASS/FAIL table. **Do not start deployment
or runbook work if any check fails** — report the failure and the fix command instead.
Never print credential values; report variable names and present/missing only.

## Checks

1. **Repo + branch**
   - `git -C "c:\Users\richa\OneDrive\Documents\(Work)\BookStop\repo\comic-preorder" status` — confirm current branch is `staging` (or the expected feature branch) and note any uncommitted files.
   - `git fetch origin` then report if local `staging` is behind `origin/staging`.

2. **gh CLI** (needed for PR workflows)
   - `gh --version` — if missing: fix is `winget install GitHub.cli`.
   - `gh auth status` — if unauthenticated: fix is `gh auth login`.

3. **Node**
   - `node --version` — needed for import scripts and `node --check` syntax gates.

4. **Scripts folder `.env`** (`C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts\.env`)
   - Confirm the file exists and contains non-empty assignments for:
     `IMPORT_SERVICE_KEY`, `IMPORT_TENANT_ID`, `SUPABASE_URL`,
     `IMPORT_SERVICE_KEY_PROD`, `IMPORT_TENANT_ID_PROD`, `SUPABASE_URL_PROD`.
   - Check names only (e.g. `Select-String -Pattern '^IMPORT_SERVICE_KEY='`). **Never echo values.**
   - Confirm `SUPABASE_URL` contains `puoaiyezsreowpwxzxhj` (staging) — abort with a warning if it points at prod.

5. **Playwright smoke suite**
   - Confirm `C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts\playwright\run-smoke.ps1` exists.
   - OneDrive gotcha: run `Unblock-File` on `run-smoke.ps1` and `test-*.ps1` in the scripts folder (synced `.ps1` files get blocked as "downloaded from internet").

6. **Supabase reachability** (cheap, no auth)
   - `curl.exe -s -o $null -w "%{http_code}" https://puoaiyezsreowpwxzxhj.supabase.co/rest/v1/` — expect 401/200-range, not a timeout.

## Output

A table: check | status (PASS/FAIL) | fix (if FAIL). End with one line: either
"Preflight clean — safe to start" or "Preflight FAILED — resolve before starting".
