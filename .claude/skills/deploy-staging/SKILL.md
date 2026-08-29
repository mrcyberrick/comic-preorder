---
name: deploy-staging
description: Run the standard feature → staging deployment flow for PULLLIST — ff-only merge, JS syntax gate, push to origin staging, then the post-deploy Playwright smoke gate (the suite tests the deployed site, so it must run after the push). Use when a feature branch is ready to land on staging.
---

# /deploy-staging — Feature → staging flow

Follow CLAUDE.md § Standard Deployment Workflow exactly. This skill encodes the
gates; **any failed gate is a halt-and-report, never an improvise.**

## Steps

1. **Confirm scope** — state which feature branch / sub-deploy this lands and confirm
   it maps to exactly one sub-deploy (one sub-deploy per session rule).

2. **Syntax gate** — for every `.js` file changed on the branch:
   `node --check <file>`. Halt on any error.

3. **Commit state** — confirm the working tree is committed on the feature branch;
   `config.js` must NOT appear in the diff (agent never edits it).

4. **Merge ff-only**
   ```powershell
   git checkout staging
   git pull origin staging
   git merge --ff-only feature/<name>
   ```
   If ff-only fails, stop and report — do not create a merge commit.

5. **Pre-push baseline** — *not* a gate on the code you are about to push
   ```powershell
   cd C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts\playwright
   .\run-smoke.ps1 -SkipPlaywright
   ```
   Stage **[1/2] `npm test`** runs against **local files** — a real pre-push gate
   when `import.js` / `import-staging.js` changed; halt on failure there (~3s).
   `-SkipPlaywright` skips stage [2/2] deliberately: it uses
   `baseURL = https://staging.pulllist.pages.dev/` and tests the **deployed**
   site, so for `app.js` / `*.html` / `style.css` it would exercise the
   *previous* build and prove nothing about the pending push — running it here
   only cost ~16 minutes for a result with no evidentiary value. The full suite
   (no flag) still runs unconditionally at step 7, which is the real gate.

6. **Push**
   ```powershell
   git push origin staging
   ```
   Never run `git push staging staging:main` (retired as of 5.1).

7. **Confirm the deploy, then run the real smoke gate**
   Wait for CF Pages (~30–60s) and confirm the new bytes are actually served —
   a stale build otherwise looks like a passing test run:
   ```powershell
   curl.exe -s -L "https://staging.pulllist.pages.dev/<changed-file>"
   ```
   Match a marker string your change introduced. **Note `-L`** — without it the
   redirect returns an empty body that reads exactly like a stale build.

   **Use the PLAIN URL — no `?cb=` cache-buster** (corrected 2026-08-07; this
   step used to recommend one). A query string is a different Cloudflare cache
   key, so it can return the new build while the plain URL a browser and
   Playwright actually request still serves the old one. On 2026-08-06 that
   produced a green "new bytes served" check followed by a spec failing against
   stale bytes — it looked like a code defect and was not. Verify what the
   browser will get. Then:
   ```powershell
   .\run-smoke.ps1
   ```
   Any failure → halt and report; fix forward or revert the push. **Attribute
   before blaming the diff:** F103 (fixture seeds the calendar month while the
   catalog page scopes to the newest month in data), F91, and F95 are known
   local-only test-infra defects that redden specs with no product regression.

8. **Report** — remind the user to smoke test manually at
   https://staging.pulllist.pages.dev/ and that promotion to prod is a separate,
   explicit step (`/promote-prod`). **State whether the change is covered by any
   spec** — green proves nothing about an uncovered path, and the catalog
   info-card reserve path has no coverage at all (see F103).
